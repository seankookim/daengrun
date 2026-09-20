-- ═══ 221 — 0190: the sweep's job lock, and the END of the bank-detail retention ═══════════════
-- ═══        0190-L1 · R1…R4 · S1, tag `pjr`  (+ `90_race_check.sh` RP)                     ═══
--
-- THE PROPOSITIONS THIS FILE OWNS (codex REJECT/2 on 0186):
--   · L1 the sweep takes a TRANSACTION-scoped TRY job lock before any candidate is read, and
--     still holds it after the call. **The skip itself is NOT here and cannot be** — an advisory
--     lock is re-entrant within one session, so a second call from this connection acquires it
--     again and runs. Only two processes can see a skip, and that is `90_race_check.sh` RP.
--     This pin owns 「the lock exists, is taken first, is never released early, and is held」.
--   · R1 **delete-then-pay** — the order §B alone cannot fix. A runner with unpaid earnings
--     deletes: tombstoned, `bank_kept = true`, the row INTACT (not blanked — Sean's ruling). The
--     later payment clears the last unpaid row and the retained row is GONE.
--   · R2 **pay-then-delete** — paid first (and, being live, nothing is released: R4's property
--     observed from the other side), then deleted: `bank_kept = false` and the row goes with the
--     account, because the retention predicate now reads the paid marker instead of lifetime
--     earnings. ⚠ This is the fixture that sits where the OLD and NEW predicates DISAGREE — it is
--     why 150 P9 could keep both of its arms and still be blind to this slice.
--   · R3 a PARTIAL payment retains: two unpaid rows, one paid, the row survives with its account
--     number and holder byte-identical; the second payment releases it.
--   · R4 CONTROL — a LIVE runner's bank details are untouched by a payment that clears every
--     unpaid row they have. The release is for tombstones only; deleting a working runner's
--     destination would break the next payout, which is the opposite of the ruling.
--   · S1 deployed shape: the retention predicate reads `paid_payout_id is null`; **0138 §F's
--     revocation enqueue SURVIVED the catalog copy**; the writer holds the release, gated on the
--     tombstone AND the last unpaid row, with the profile lock taken BEFORE `deleted_at` is read;
--     definer/search_path/ACL on both, comments stripped, NO-SOURCE arms.
--
-- ─── WHY 150 STAYS GREEN AND ITS PROSE DOES NOT (suite-update law) ───
-- 150 P9's two arms are 「has ledger rows ⇒ kept」 and 「has none ⇒ deleted」. Both fixtures are in
-- the AGREEMENT zone of the old predicate (`any ledger row`) and the new one (`any UNPAID ledger
-- row`): P9 arm A's rows are unpaid, arm B has no rows at all. So P9 keeps both arms unchanged and
-- is NOT stale as a behavioural pin — what WAS stale is its pass sentence, which told a reader
-- 「payouts에 기록자가 없어 unpaid_payout은 오늘 발화하지 않는다」. 0186 is that writer. That
-- sentence is corrected in 150 in this same slice, pointing here; the arms that can tell the two
-- predicates apart are R2 and R3, and they are new because no fixture in 150 could have them.
--
-- ─── MUTATION MAP — measured 2026-09-21 against these exact files, not predicted ───
--   Lab: a copy of `supabase/` OUTSIDE the worktree (suite md5-identical to the committed one),
--   every plant restored-from-pristine, assert-gated and CHAIN-GATED to its harness run so a
--   failed plant yields NO row rather than a green one. Control observed clean FIRST: **1328 / 0**.
--   「demoted」 = 0190's VERIFY raise turned into a notice so the SUITE is what is measured;
--   「un-demoted」 = the shipped file, where VERIFY aborts the apply before any suite runs.
--
--   (i)    the sweep's job lock deleted          → 1326/2: L1 + race RP. Un-demoted ABORTS
--          (`sweep:JOB-LOCK-MISSING-OR-AFTER-THE-FIRST-ARM`). This is codex's #1 reproduced.
--   (ii)   an early `pg_advisory_unlock` added   → 1327/1: **L1 alone, and RP stays green for a
--          reason that is a fact about postgres rather than a gap in RP**: `pg_advisory_unlock`
--          cannot release a lock taken with `pg_try_advisory_xact_lock` — it warns and returns
--          false — so this plant is not behaviourally effective in this exact form. The source arm
--          is therefore the ONLY available detector, which is precisely why it exists: a
--          SESSION-level lock would be releasable, and that is the shape the arm refuses.
--          Un-demoted ABORTS (`sweep:SESSION-UNLOCK-PRESENT`).
--   (iii)  the key borrowed from the handoff sweep → 1326/2: L1 + race RP (the follower no longer
--          skips, because the leader is holding a different key). Un-demoted ABORTS.
--   (iv)   §B reverted to the lifetime predicate → 1326/2: **R2** + S1. R1/R3/R4 stay green, which
--          is the fixture-agreement law visible in one row: only R2's runner is fully paid, so
--          only R2 sits where the old and new predicates disagree. Un-demoted ABORTS
--          (`delete:RETENTION-STILL-LIFETIME-SCOPED`).
--   (v)    §C's release deleted                  → 1325/3: R1 + R3 + S1 (the delete-then-pay order
--          is never closed and the retained row survives forever).
--   (vi)   the release fires for EVERY runner    → 1326/2: **R2 + R4** — the control earning its
--          place: a release hard-wired to 「always」 passes none of R1/R3 and fails R4, while one
--          hard-wired to 「never」 fails R1/R3 and passes R4. Neither constant satisfies both.
--   (vii)  the release not gated on the last unpaid row → 1326/2: R3 + S1 (a partial payment
--          releases a destination the rest of the money still needs).
--   (viii) the profile row lock deleted          → 1327/1: **S1 ALONE — a NAMED GAP, not a pass.**
--          The interleaving it protects (the payout reads 「not a tombstone yet」 while the deletion
--          reads 「still unpaid」, both correct, and the row is retained forever) needs two
--          transactions; every pin in this file is one session. It is pinned by TEXT and by the
--          apply: un-demoted ABORTS (`writer:NO-PROFILE-LOCK` · `writer:TOMBSTONE-READ-BEFORE-THE-
--          LOCK`). A future slice touching this function owes a `90_race_check.sh` arm for it.
--   (ix)   the catalog copy ALSO strips 0138 §F's enqueue → 1326/2: S1 **and `[bkr] R4`, 0138's
--          OWN pin** — an independent shipped pin from another slice agreeing that the property is
--          real, which is worth more than either alone. Un-demoted ABORTS
--          (`delete:0138-ENQUEUE-LOST-IN-THE-COPY`).
--
--   ⚠ Two plants (ii, ix) initially reported as UNLANDED and produced NO battery rows — the
--   chain-gate working. The cause was the planter's own post-check (`count(old) == 0`), which
--   cannot hold for an INSERTION that keeps the original text inside its replacement. The
--   verifier was fixed to compare against pristine and assert the replacement is present; a
--   verifier that fails CLOSED costs a re-run, one that fails open manufactures evidence.
--
-- ─── FIXTURE NOTES ───
--  ① `t_pjr_world` builds its own runner rather than borrowing 150's `t_acd_rich`: a pin that
--     inherits another suite's setup is testing that setup. It uses only the shared 10_settle
--     helpers (`t_user`/`t_dog`/`t_route`/`t_active_booking`/`t_settle`), so a settled run leaves
--     a real `ledger_items` row written by the real settle path.
--  ② Every amount is READ from the row it pays (the same `base+distance+addon+tip+guarantee−fee`
--     an operator reads out of `ops_payouts_due()`), never a literal. The amount equality itself
--     is 217 P3's property; this file's is the retention.
--  ③ `request.jwt.claim.sub` is the ops caller for the payout half and is CLEARED before each
--     `delete_my_account_tx` call — that function takes the uid as a PARAMETER and a leftover
--     claim would prove nothing about who it acts for.
--  ④ The bank row is asserted BYTE-IDENTICAL wherever it is retained (bank · account_enc ·
--     holder), never merely present: 0115's ruling is 「KEEP INTACT, not anonymised」, and a
--     blanked row is a row nobody can pay into.
set client_min_messages = warning;

-- ① a runner with `p_items` settled, unpaid earnings and a bank row on file
create or replace function t_pjr_world(p_tag text, p_items int,
                                       out o uuid, out r uuid, out d uuid, out rt uuid)
language plpgsql as $$
declare i int; bk uuid;
begin
  o  := t_user('pjr_' || p_tag || '_o', 'owner');
  r  := t_user('pjr_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'pjr-' || p_tag);
  rt := t_route('pjr 코스 ' || p_tag);
  for i in 1 .. p_items loop
    bk := t_active_booking(o, r, d, rt, now() - interval '2 days');
    perform t_settle(bk, 'dog_condition');
  end loop;
  insert into bank_accounts (runner_id, bank, account_enc, holder)
  values (r, '토스뱅크', 'ENC-' || upper(p_tag), '김러너');
end $$;

-- the net of one ledger row — the number an operator reads out of ops_payouts_due() ②
create or replace function t_pjr_net(p_ids uuid[]) returns int language sql as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)::int
    from ledger_items where id = any(p_ids)
$$;

-- the runner's unpaid ledger ids, oldest first
create or replace function t_pjr_unpaid(p_runner uuid) returns uuid[] language sql as $$
  select coalesce(array_agg(id order by created_at, id), '{}'::uuid[])
    from ledger_items where runner_id = p_runner and paid_payout_id is null
$$;

-- the retained bank row, asserted BYTE-IDENTICAL rather than merely present ④
create or replace function t_pjr_bank(p_runner uuid, p_tag text) returns int language sql as $$
  select count(*)::int from bank_accounts
   where runner_id = p_runner and bank = '토스뱅크'
     and account_enc = 'ENC-' || upper(p_tag) and holder = '김러너'
$$;

create or replace function t_pjr_pay(p_runner uuid, p_ids uuid[], p_amount int) returns jsonb
language plpgsql as $$
declare v uuid;
begin
  begin
    v := ops_record_manual_payout(p_runner, p_ids, p_amount, 'pjr');
    return jsonb_build_object('payout', v);
  exception when others then
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

do $$
declare
  ops1 uuid;
  o uuid; r uuid; d uuid; rt uuid;
  v jsonb; res jsonb;
  ids uuid[]; one uuid[];
  v_bad text := ''; v_msg text; v_src text; v_oid oid;
  v_n int; v_key bigint;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  ops1 := t_user('pjr_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active) values (ops1, 'payout_due', true);

  -- ---------- [0190-L1] the sweep's TRY job lock: taken first, held after, never released early ----------
  -- ⚠ WHAT THIS PIN CANNOT SEE, stated rather than implied: an advisory lock is RE-ENTRANT within
  -- one session, so calling the sweep twice from this connection acquires it twice and both runs
  -- proceed. 「the second tick skips」 is a two-process fact and lives in `90_race_check.sh` RP.
  -- This block owns the lock's EXISTENCE, its POSITION and the fact that it is still held — which
  -- is exactly what a deletion of the `pg_try_advisory_xact_lock` line destroys.
  v_bad := '';
  v_key := hashtextextended('ops_payouts_stuck_sweep', 0);
  select count(*) into v_n from pg_locks l
   where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1 and l.classid = ((v_key >> 32) & 4294967295)::oid
     and l.objid = (v_key & 4294967295)::oid;
  if v_n is distinct from 0 then v_bad := v_bad || ' the lock was already held BEFORE the call (' || v_n || ') — this pin would pass without the sweep taking anything'; end if;

  perform ops_payouts_stuck_sweep();

  select count(*) into v_n from pg_locks l
   where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1 and l.classid = ((v_key >> 32) & 4294967295)::oid
     and l.objid = (v_key & 4294967295)::oid;
  if v_n < 1 then v_bad := v_bad || ' job-lock-not-held-after-the-call(' || v_n || ')'; end if;

  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_payouts_stuck_sweep';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_payouts_stuck_sweep)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' 클라 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_payouts_stuck_sweep)';
    else
      if (position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src) > 0
          and position('for r in' in v_src) > 0
          and position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src)
              < position('for r in' in v_src)) is distinct from true
        then v_bad := v_bad || ' 잡 락이 없거나 첫 팔 뒤에 있다'; end if;
      if (v_src ~ 'pg_advisory_unlock') is distinct from false then v_bad := v_bad || ' 세션 unlock 있음(조기 해제는 레이스를 다시 연다)'; end if;
      -- the key must be this sweep's own name: sharing the handoff sweep's string would make two
      -- unrelated janitors block each other, and it would read as a deadlock rather than a typo
      if (v_src ~ 'hashtextextended\(''sweep_run_end_recovery''') is distinct from false then v_bad := v_bad || ' 다른 스윕의 락 키를 쓴다'; end if;
      -- and the dedupe the lock protects is still there (0186's property, not re-owned here)
      if (v_src ~ 'created_at > now\(\) - DEDUPE_WINDOW') is distinct from true then v_bad := v_bad || ' 20시간 중복 방지 가드가 사라졌다'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('pjr','0190-L1 스윕의 잡 락: 호출 전에는 안 잡혀 있고(이 핀이 공짜로 통과하지 않는다는 대조), 첫 후보를 읽기 전에 pg_try_advisory_xact_lock(이 함수 자신의 이름)을 잡으며, xact 스코프라 호출 뒤에도 잡혀 있고, 조기 해제(pg_advisory_unlock)는 없다; 락이 지키는 20시간 중복 방지 가드도 그대로. ⚠ 「둘째 틱이 건너뛴다」는 한 세션에서 볼 수 없다(advisory 락은 세션 안에서 재진입 가능) — 그건 90_race_check.sh RP의 몫이다');
  else v_msg := v_bad; call _fail('pjr','0190-L1 sweep job lock', v_msg); end if;

  -- ---------- [0190-R1] delete-then-pay: the retention ENDS when the last unpaid row clears ----------
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_pjr_world('r1', 1) w;
  if t_pjr_bank(r, 'r1') is distinct from 1 then v_bad := v_bad || ' fixture: no bank row'; end if;
  ids := t_pjr_unpaid(r);
  if coalesce(array_length(ids, 1), 0) is distinct from 1 then v_bad := v_bad || ' fixture: unpaid rows = ' || coalesce(array_length(ids, 1), 0) || ' (expected 1)'; end if;

  -- the runner deletes while the money is still owed
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ③
  res := delete_my_account_tx(r);
  if (res->>'ok')::boolean is not true then v_bad := v_bad || ' delete refused: ' || res::text; end if;
  if (res->>'bank_kept')::boolean is not true then v_bad := v_bad || ' bank_kept=' || coalesce(res->>'bank_kept', '∅') || ' (expected true — the money is still owed)'; end if;
  if t_pjr_bank(r, 'r1') is distinct from 1 then v_bad := v_bad || ' 🔴 the retained row was deleted or blanked — a row nobody can pay into defeats the reason for keeping it'; end if;
  if (select deleted_at is not null from profiles where id = r) is not true then v_bad := v_bad || ' the runner was not tombstoned'; end if;

  -- and now the payment that ends the obligation
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_pjr_pay(r, ids, t_pjr_net(ids));
  if v->>'raised' is not null then v_bad := v_bad || ' pay raised=' || (v->>'raised'); end if;
  if t_pjr_unpaid(r) is distinct from '{}'::uuid[] then v_bad := v_bad || ' unpaid rows survive the payment'; end if;
  if exists (select 1 from bank_accounts where runner_id = r) then
    v_bad := v_bad || ' 🔴 THE FINDING: a tombstoned runner''s account number and legal name survive their final payout — 0115:562-563 says the retention ends here, and nothing else can ever run (0115:227-234 short-circuits a tombstoned retry)'; end if;
  -- the ledger itself stays: it is the record of what was earned and paid, not the retention basis
  if (select count(*) from ledger_items where runner_id = r) < 1 then v_bad := v_bad || ' the ledger rows were destroyed'; end if;

  if v_bad = '' then call _pass('pjr','0190-R1 삭제 후 지급: 미지급이 남은 채 탈퇴하면 계좌는 가려지지 않고 그대로 보관되고(bank_kept=true, 계좌번호·실명 바이트 동일) 툼스톤이 찍힌다; 그 뒤 마지막 미지급 행을 지급하는 순간 보관이 끝나고 계좌 행이 사라진다(원장 자체는 남는다 — 보관 근거였지 기록이 아니었다). 탈퇴는 재시도해도 0115:227-234에서 조기 반환하므로, 이 해제가 없으면 그 행은 영원히 남는다');
  else v_msg := v_bad; call _fail('pjr','0190-R1 delete-then-pay', v_msg); end if;

  -- ---------- [0190-R2] pay-then-delete: the retention predicate reads the MARKER, not a lifetime ----------
  -- ⚠ THIS IS THE FIXTURE THAT SITS WHERE THE OLD AND NEW PREDICATES DISAGREE. Under the old rule
  -- (「any ledger row」) this runner is retained forever; under the new one they are not owed a won
  -- and the destination goes with the account. 150 P9 has no fixture here, which is why it stayed
  -- green through the defect.
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_pjr_world('r2', 1) w;
  ids := t_pjr_unpaid(r);
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_pjr_pay(r, ids, t_pjr_net(ids));
  if v->>'raised' is not null then v_bad := v_bad || ' pay raised=' || (v->>'raised'); end if;
  -- still LIVE, so nothing is released — R4's property, observed from the other side
  if t_pjr_bank(r, 'r2') is distinct from 1 then v_bad := v_bad || ' 🔴 a LIVE runner''s destination was deleted by paying them'; end if;

  perform set_config('request.jwt.claim.sub', '', true);
  res := delete_my_account_tx(r);
  if (res->>'ok')::boolean is not true then v_bad := v_bad || ' delete refused: ' || res::text; end if;
  if (res->>'bank_kept')::boolean is not false then v_bad := v_bad || ' bank_kept=' || coalesce(res->>'bank_kept', '∅') || ' (expected false — nothing is owed, so the retention has no basis)'; end if;
  if (res#>>'{deleted,bank_accounts}')::int is distinct from 1 then v_bad := v_bad || ' deleted.bank_accounts=' || coalesce(res#>>'{deleted,bank_accounts}', '∅') || ' (expected 1)'; end if;
  if exists (select 1 from bank_accounts where runner_id = r) then
    v_bad := v_bad || ' 🔴 the account number and legal name of a fully-paid runner survived their own deletion'; end if;

  if v_bad = '' then call _pass('pjr','0190-R2 지급 후 삭제: 다 지급된 러너가 탈퇴하면 bank_kept=false이고 계좌도 실명도 계정과 함께 사라진다 — 보관 근거는 「평생 수익이 있었는가」가 아니라 「지금 갚을 것이 남았는가」다(0115:562-563의 문장을 0186 §A의 표시자가 처음으로 술어로 만든다). ⚠ 이 픽스처가 옛 술어와 새 술어가 갈라지는 지점이고, 150 P9에는 이 지점의 팔이 없다');
  else v_msg := v_bad; call _fail('pjr','0190-R2 pay-then-delete', v_msg); end if;

  -- ---------- [0190-R3] a PARTIAL payment retains ----------
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_pjr_world('r3', 2) w;
  ids := t_pjr_unpaid(r);
  if coalesce(array_length(ids, 1), 0) is distinct from 2 then v_bad := v_bad || ' fixture: unpaid rows = ' || coalesce(array_length(ids, 1), 0) || ' (expected 2)'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  res := delete_my_account_tx(r);
  if (res->>'bank_kept')::boolean is not true then v_bad := v_bad || ' bank_kept=' || coalesce(res->>'bank_kept', '∅') || ' (expected true)'; end if;

  one := array[ids[1]];
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_pjr_pay(r, one, t_pjr_net(one));
  if v->>'raised' is not null then v_bad := v_bad || ' first pay raised=' || (v->>'raised'); end if;
  if t_pjr_bank(r, 'r3') is distinct from 1 then
    v_bad := v_bad || ' 🔴 a PARTIAL payment released the destination — the rest of the money still has to go somewhere'; end if;
  if coalesce(array_length(t_pjr_unpaid(r), 1), 0) is distinct from 1 then v_bad := v_bad || ' after the partial payment unpaid rows = ' || coalesce(array_length(t_pjr_unpaid(r), 1), 0) || ' (expected 1)'; end if;

  one := t_pjr_unpaid(r);
  v := t_pjr_pay(r, one, t_pjr_net(one));
  if v->>'raised' is not null then v_bad := v_bad || ' second pay raised=' || (v->>'raised'); end if;
  if exists (select 1 from bank_accounts where runner_id = r) then
    v_bad := v_bad || ' the last payment did not release the retained row'; end if;

  if v_bad = '' then call _pass('pjr','0190-R3 부분 지급은 보관을 유지한다: 탈퇴한 러너의 미지급 두 행 중 하나만 지급하면 계좌 행은 계좌번호·실명 그대로 남고(남은 돈도 어딘가로 가야 한다), 마지막 행까지 지급되는 순간에만 해제된다');
  else v_msg := v_bad; call _fail('pjr','0190-R3 partial payment retains', v_msg); end if;

  -- ---------- [0190-R4] CONTROL — a LIVE runner's destination is not deleted by paying them ----------
  -- If this arm and R1/R2/R3 were blind to the same thing, R4 would not be a control. They are
  -- not: every release arm above fails when the release does NOT happen, and this one fails when
  -- it happens where it must not. A release hard-wired to 「always」 passes none of them; a release
  -- hard-wired to 「never」 passes only this one.
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_pjr_world('r4', 2) w;
  ids := t_pjr_unpaid(r);
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_pjr_pay(r, ids, t_pjr_net(ids));
  if v->>'raised' is not null then v_bad := v_bad || ' pay raised=' || (v->>'raised'); end if;
  if t_pjr_unpaid(r) is distinct from '{}'::uuid[] then v_bad := v_bad || ' the payment did not clear every unpaid row'; end if;
  if (select deleted_at is null from profiles where id = r) is not true then v_bad := v_bad || ' fixture: the runner is not live'; end if;
  if t_pjr_bank(r, 'r4') is distinct from 1 then
    v_bad := v_bad || ' 🔴 a working runner''s bank account was deleted by paying them — the next payout has nowhere to go'; end if;

  if v_bad = '' then call _pass('pjr','0190-R4 대조: 살아 있는(탈퇴하지 않은) 러너는 미지급 행이 전부 지급돼도 계좌가 그대로다 — 해제는 툼스톤 전용이고, 일하는 러너의 입금처를 지우는 것은 규칙의 정반대다. 「항상 해제」는 R4를, 「절대 해제 안 함」은 R1·R2·R3을 빨갛게 만든다');
  else v_msg := v_bad; call _fail('pjr','0190-R4 live runner control', v_msg); end if;

  -- ---------- [0190-S1] deployed shape: the deletion's predicate, 0138's survival, the writer's release ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'delete_my_account_tx';
  if v_oid is null then v_bad := v_bad || ' A:NO-FUNCTION(delete_my_account_tx)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' A:ACL 기본값(PUBLIC 실행)'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:클라 실행 가능(uid가 파라미터라 남을 지목할 수 있다)'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' A:service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' A:NO-SOURCE(delete_my_account_tx)';
    else
      if (v_src ~ 'from ledger_items where runner_id = p_uid and paid_payout_id is null;') is distinct from true
        then v_bad := v_bad || ' A:보관 술어가 아직 평생 수익 기준이다'; end if;
      -- the catalog copy must not have thrown away 0138 §F's insertion; a session that "tidies"
      -- this by pasting 0115's body would pass every other arm in this file
      if (v_src ~ 'enqueue_billing_key_revocation\(p_uid, ''account_deleted''\)') is distinct from true
        then v_bad := v_bad || ' A:0138 §F의 revocation enqueue가 복사에서 사라졌다 — 탈퇴 뒤에도 PG가 계속 인정하는 카드가 남는다'; end if;
      if (v_src ~ 'v_bank_kept := v_n > 0;') is distinct from true then v_bad := v_bad || ' A:bank_kept 대입이 사라졌다'; end if;
      -- the enqueue must still precede the billing_keys delete (0138 §F's whole point)
      if (position('enqueue_billing_key_revocation' in v_src) > 0
          and position('delete from billing_keys where profile_id = p_uid' in v_src) > 0
          and position('enqueue_billing_key_revocation' in v_src)
              < position('delete from billing_keys where profile_id = p_uid' in v_src)) is distinct from true
        then v_bad := v_bad || ' A:enqueue가 billing_keys 삭제 뒤로 밀렸다(읽을 행이 이미 없다)'; end if;
    end if;
  end if;

  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_record_manual_payout';
  if v_oid is null then v_bad := v_bad || ' B:NO-FUNCTION(ops_record_manual_payout)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:본문 search_path 없음'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:public/anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' B:authenticated 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' B:NO-SOURCE(ops_record_manual_payout)';
    else
      if (v_src ~ 'delete from bank_accounts where runner_id = p_runner;') is distinct from true
        then v_bad := v_bad || ' B:해제가 없다'; end if;
      if (v_src ~ 'l2\.paid_payout_id is null') is distinct from true
        then v_bad := v_bad || ' B:해제가 마지막 미지급 행 조건에 걸려 있지 않다'; end if;
      if (v_src ~ 'pr\.deleted_at is not null') is distinct from true
        then v_bad := v_bad || ' B:해제가 툼스톤 조건에 걸려 있지 않다'; end if;
      -- THE LOCK IS A PRECONDITION OF THE TOMBSTONE READ, not part of it: without it the payout
      -- and the deletion interleave into 「not yet a tombstone」 + 「still unpaid」, both correct,
      -- and the row is retained forever. A single-session pin cannot see this at all.
      if (position('from profiles pr where pr.id = p_runner for update;' in v_src) > 0
          and position('pr.deleted_at is not null' in v_src) > 0
          and position('from profiles pr where pr.id = p_runner for update;' in v_src)
              < position('pr.deleted_at is not null' in v_src)) is distinct from true
        then v_bad := v_bad || ' B:프로필 행 잠금이 없거나 툼스톤 판독 뒤에 있다'; end if;
      -- and the 0186 gates it inherits are still in front of everything
      if (position('raise exception ''not_ops''' in v_src) > 0
          and position('from profiles pr where pr.id = p_runner for update;' in v_src) > 0
          and position('raise exception ''not_ops''' in v_src)
              < position('from profiles pr where pr.id = p_runner for update;' in v_src)) is distinct from true
        then v_bad := v_bad || ' B:ops 파티 게이트가 잠금보다 뒤로 밀렸다'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'insert into payouts', 'g');
      if v_n is distinct from 1 then v_bad := v_bad || ' B:payouts 삽입 ' || v_n || '개(1 기대)'; end if;
    end if;
  end if;

  if v_bad = '' then call _pass('pjr','0190-S1 배포 형상: delete_my_account_tx의 보관 술어가 paid_payout_id IS NULL을 읽고, 카탈로그 복사가 0138 §F의 revocation enqueue를 (billing_keys 삭제보다 앞선 자리 그대로) 살려 뒀으며, bank_kept 대입은 그대로다; ops_record_manual_payout은 해제를 갖고 있고 툼스톤 + 마지막 미지급 행 두 조건에 걸려 있으며 프로필 행 잠금이 툼스톤 판독보다 먼저다(ops 게이트는 그 잠금보다도 먼저); 두 함수 모두 definer·본문 search_path·값으로 확인한 ACL');
  else v_msg := v_bad; call _fail('pjr','0190-S1 shape', v_msg); end if;
end $$;

drop function if exists t_pjr_world(text, int);
drop function if exists t_pjr_net(uuid[]);
drop function if exists t_pjr_unpaid(uuid);
drop function if exists t_pjr_bank(uuid, text);
drop function if exists t_pjr_pay(uuid, uuid[], int);
