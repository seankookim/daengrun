-- ═══ 225 — 0194: 정산 계좌 registration ════════════════════════════════════════════════════════
-- ═══        0194-B1 … B6 · S1, tag `bnk`                                                    ═══
--
-- THE PROPOSITIONS THIS FILE OWNS:
--   · B1 a runner registers and reads back a MASKED number — and the encryption is REAL, not a
--     stub: the stored `account_enc` is neither the plaintext nor equal for two different numbers,
--     and the operator's decrypt returns the exact digits that went in. A re-save REPLACES.
--   · B2 runner A cannot read runner B — through the RPC, and through the table as a real
--     `authenticated` role, where `account_enc` is not selectable AT ALL and no direct write is.
--   · B3 a non-ops caller of `ops_bank_account` is refused BEFORE ANY READ. ⚠ The 「before」 is
--     carried by the arm that distinguishes `not_ops` from `no_runner` and by S1's two source
--     arms — NOT by the journal, whose zero-row arm this suite's first draft wrongly credited
--     with it (see the note at the arm: a refusal rolls its own journal row back).
--   · B4 an ops read leaves EXACTLY ONE journal row, asserted as a DELTA this call caused rather
--     than as a count found lying around — including the found=false arm, because probing for
--     existence is access too.
--   · B5 delete is refused with `payout_owed` while a settled row is unpaid, and the row survives
--     BYTE-IDENTICAL; once `ops_record_manual_payout` clears the last unpaid row, the same call
--     succeeds. The CONTROL is the second half: 「always refuse」 fails it and 「never refuse」
--     fails the first half, so no constant satisfies both.
--   · B6 the refusal vocabulary, each arm writing NOTHING.
--   · S1 deployed shape — the four definers, the two helpers that must NOT be definers, the
--     column grant in both directions, the sealed tables, the journal's argued FK ABSENCE, and
--     source arms (comments stripped) for the two orderings B3/B4 can only half-see.
--
-- ─── WHAT THIS SUITE STRUCTURALLY CANNOT REACH, stated rather than implied ───
--   ⚠ **It cannot prove the key is secret from a DUMP.** Key and ciphertext live in the same
--     database (0194 §0a says so out loud); what is pinned here is that no CLIENT-reachable
--     surface returns either. A pin asserting 「a dump is safe」 would be unfalsifiable in this
--     harness and would read to a later session as coverage — so it is prose, not a pin
--     (the do-not-pin-a-limitation law).
--   ⚠ **It cannot see a CONCURRENT delete racing a payout.** Every arm here is one session. The
--     `payout_owed` predicate is read under no lock, so a delete committing between the payout's
--     read and its write is invisible to B5. Named as a GAP: the next slice touching
--     `delete_my_bank_account` owes a `90_race_check.sh` arm.
--   ⚠ **`verified_at` is NULL in every arm and always will be** — there is no verifier, so an arm
--     asserting it stays NULL after a change is real (B1 has it) while an arm asserting it is ever
--     SET could not be written at all.
--
-- ─── MUTATION MAP — measured 2026-09-22 against these exact files, not predicted ───
--   The lab is a copy of `supabase/` OUTSIDE the worktree, md5-identical on both files; every
--   plant is assert-gated AND `&&`-chained to its harness run, so a failed plant yields NO row
--   rather than a green one. **CONTROL OBSERVED CLEAN FIRST: 1349 / 0.**
--   「demoted」 = §G's VERIFY raise turned into a notice, so what is measured is the SUITE and not
--   the apply; 「plain」 = the shipped file, where VERIFY aborts before any suite runs.
--
--   ⚠ **THIS IS THE SECOND BATTERY. The first one is DISCARDED, not carried forward** — a cold
--     review (below) moved the delete predicate, the unreadable path, two revokes and the trim,
--     and added arms to four pins, so every earlier row measured a tree that does not ship.
--
--   (i)    the ops party gate deleted        → 1347/2: B3 + S1. ⚠ **This row is the HOLE, not a
--          pin's opinion of it**: B3's detail prints `"account": "100200300400"` returned to an
--          owner, to another runner, to an INACTIVE recipient and to a WRONG-CLASS one — four
--          callers who are not ops holding a real decrypted account number.
--   (ii)   the `payout_owed` raise deleted   → 1348/1: **B5 ALONE, and correctly so.** S1 stays
--          green because the predicate TEXT is untouched; only the refusal is gone. B5 owns the
--          behaviour, S1 owns the shape, and the mutation moved exactly one of them. Detail:
--          `delete while owed ⇒ {"ok": true}` and the row is gone.
--   (iv)   the journal insert deleted        → 1347/2: B4 + S1.
--   (v)    plaintext stored in `account_enc` → 1344/5: B1 + B2 + B4 + B6 + S1. The cascade IS the
--          damage: every downstream read goes through the same round trip, so the mask that still
--          renders is the only thing that looks unchanged — which is why B1 asserts the ciphertext
--          rather than the mask.
--   (vi)   the account shape relaxed to strip-first → B6 + S1. Detail: 「계좌 1234567890 입니다」
--          stored and returned as `••••7890` — a destination nobody typed.
--   (vii)  the ops gate moved AFTER the journal + decrypt → 1347/2: B3 + S1. ⚠ **B3 reddens on the
--          `not_ops`-not-`no_runner` arm and S1 on 「게이트가 장부 기록보다 뒤에 있다」 — the
--          JOURNAL-DELTA ARM STAYS GREEN.** That is a fact about plpgsql, not a gap: the refusal
--          unwinds the caller's exception block and the subtransaction rolls the journal row back,
--          so the evidence erases itself. The arm's sentence is corrected at the arm.
--   (ix)   `verified_at` stamped             → 1347/2: B1 + S1. Detail: a real timestamp in a
--          column nothing in the product can honestly write.
--   (xii)  the server's `btrim` removed      → 1347/2: B6 + S1. The client mirror trims, so
--          without it a PASTED number passes locally and is refused remotely.
--   (xiii) the delete gate reverted to 0186's payout-ELIGIBILITY predicate → 1347/2: **B5 + S1.**
--          ⚠ B5 can only see this because of the open-run fixture added in the same round; with
--          the original fixture set it reddened S1 ALONE, which is the fixture-agreement law in
--          one row — every other fixture sits where the two candidate rules AGREE.
--   (xiv)  `account_unreadable` raises again → 1347/2: B4 + S1.
--   (iii)  the column seal deleted           → **plain: APPLY ABORTS** (`account_enc:CLIENT-READABLE
--          bank_accounts:CLIENT-WRITABLE`); demoted: 1347/2 B2 + S1. Both halves measured.
--   (viii) search_path reverted to the house literal → **plain: APPLY ABORTS** naming all four
--          functions; demoted: 1348/1 **S1 alone**, which is the whole point — no behavioural pin
--          can see this in a harness where pgcrypto happens to live in `public`.
--   (x)    `_bank_account_plain` made a definer → **plain: APPLY ABORTS**
--          (`_bank_account_plain(uuid):IS-DEFINER(must not be)`); demoted: 1348/1 S1 alone.
--   (xi)   `service_role` dropped from the two helper revokes → **plain: APPLY ABORTS**
--          (`_bank_account_key():CLIENT-EXECUTABLE _bank_account_plain(uuid):CLIENT-EXECUTABLE`);
--          demoted: 1348/1 S1 alone. ⚠ This is the cold reviewer's HIGH #1 reproduced: without
--          that one word `_bank_account_key()` is a PostgREST RPC that returns the key. **The
--          first draft's arms checked only anon/authenticated and were therefore structurally
--          incapable of reddening on it** — which is why the fix and this row landed together.
--
--   ⚠ **FOUR PLANTS ACROSS THE TWO BATTERIES REPORTED 「DID NOT LAND」 AND PRODUCED NO ROWS — the
--     chain-gate working, and every cause was MY VERIFIER or MY OWN LATER EDIT, never a silent
--     pass.** (vii) and (x) are INSERTIONS that keep the original inside the replacement, so a
--     `count(old) == 0` post-check cannot hold on a plant that landed perfectly — the same
--     verifier bug 0190's battery recorded, reproduced here by someone who had read it; (viii)
--     was a miscount (9 occurrences, not 6); (vi) went stale the moment `btrim` entered the line
--     it patches. The fix is to apply the old-text check only when the replacement does not
--     contain the original. **A verifier that fails CLOSED costs a re-run; one that fails open
--     manufactures evidence**, and none of these four ever produced a green row.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- A runner with `p_items` settled, unpaid earnings — 221's `t_pjr_world` without the bank row,
-- because in this suite the bank row is the thing under test and must be created by the RPC.
create or replace function t_bnk_world(p_tag text, p_items int,
                                       out o uuid, out r uuid, out d uuid, out rt uuid)
language plpgsql as $$
declare i int; bk uuid;
begin
  o  := t_user('bnk_' || p_tag || '_o', 'owner');
  r  := t_user('bnk_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'bnk-' || p_tag);
  rt := t_route('bnk 코스 ' || p_tag);
  for i in 1 .. p_items loop
    bk := t_active_booking(o, r, d, rt, now() - interval '2 days');
    perform t_settle(bk, 'dog_condition');
  end loop;
end $$;

-- Call a three-argument setter as `p_uid` and report either the stored mask or the refusal token.
create or replace function t_bnk_set(p_uid uuid, p_bank text, p_account text, p_holder text)
returns jsonb language plpgsql as $$
declare v record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select * into v from set_my_bank_account(p_bank, p_account, p_holder);
  return jsonb_build_object('masked', v.account_masked, 'bank', v.bank,
                            'label', v.bank_label, 'holder', v.holder,
                            'verified', v.verified_at);
exception when others then
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- ⚠ BOTH READERS CALL THE RPC EXACTLY ONCE, and that is load-bearing rather than tidy. The first
-- draft did `select count(*)` and then `select *`, i.e. TWO invocations — which is invisible for
-- `my_bank_account` and made `0194-B4` read 「one read wrote 2 journal rows」. The pin was right and
-- the fixture was wrong, but a helper that calls twice can only ever measure the journal at double
-- and would have to be 「fixed」 by weakening B4. A `for … loop` collects rows and the count from one
-- call, so the number B4 asserts is the number one read actually produces.
create or replace function t_bnk_mine(p_uid uuid) returns jsonb language plpgsql as $$
declare v record; n int := 0; r jsonb := '{}'::jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  for v in select * from my_bank_account() loop
    n := n + 1;
    r := jsonb_build_object('masked', v.account_masked, 'bank', v.bank,
                            'label', v.bank_label, 'holder', v.holder,
                            'verified', v.verified_at);
  end loop;
  return r || jsonb_build_object('rows', n);
exception when others then
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_bnk_ops(p_uid uuid, p_runner uuid) returns jsonb language plpgsql as $$
declare v record; n int := 0; r jsonb := '{}'::jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  for v in select * from ops_bank_account(p_runner) loop
    n := n + 1;
    r := jsonb_build_object('account', v.account, 'bank', v.bank,
                            'label', v.bank_label, 'holder', v.holder);
  end loop;
  return r || jsonb_build_object('rows', n);
exception when others then
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_bnk_del(p_uid uuid) returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform delete_my_bank_account();
  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- the journal rows THIS suite's operator caused, so no other suite's activity can move the number
create or replace function t_bnk_log(p_ops uuid) returns int language sql as $$
  select count(*)::int from bank_account_access_log where ops_profile_id = p_ops
$$;

create or replace function t_bnk_row(p_runner uuid) returns text language sql as $$
  select coalesce(bank, '-') || '|' || coalesce(account_enc, '-') || '|' || coalesce(holder, '-')
    from bank_accounts where runner_id = p_runner
$$;

do $$
declare
  ops1 uuid; ops_off uuid; ops_other uuid;
  oA uuid; rA uuid; dA uuid; tA uuid;
  oB uuid; rB uuid; dB uuid; tB uuid;
  oC uuid; rC uuid; dC uuid; tC uuid;
  rD uuid; dD uuid; tD uuid; v_bk uuid;
  v jsonb; v2 jsonb;
  v_bad text := ''; v_msg text; v_src text; v_oid oid;
  v_n int; v_before int; v_after int;
  v_encA text; v_encA2 text; v_rowA text;
  ids uuid[]; v_net int;
  fn text;
begin
  perform set_config('request.jwt.claim.sub', '', true);

  ops1      := t_user('bnk_ops',       'owner');
  ops_off   := t_user('bnk_ops_off',   'owner');
  ops_other := t_user('bnk_ops_other', 'owner');
  insert into ops_recipients (profile_id, event_class, active)
       values (ops1, 'payout_due', true),
              (ops_off, 'payout_due', false),          -- an INACTIVE recipient is not ops
              (ops_other, 'handoff_unanswered', true); -- a recipient of a DIFFERENT class is not ops

  select * into oA, rA, dA, tA from t_bnk_world('a', 2);   -- two settled, unpaid earnings
  select * into oB, rB, dB, tB from t_bnk_world('b', 0);   -- a runner with no earnings at all
  select * into oC, rC, dC, tC from t_bnk_world('c', 0);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-B1] register → read back MASKED, and the encryption is real rather than a stub
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';

  -- the control that stops this pin passing for free: nothing on file before the call
  v := t_bnk_mine(rA);
  if (v->>'rows')::int is distinct from 0
    then v_bad := v_bad || ' a row existed BEFORE registration (' || coalesce(v::text, 'null') || ')'; end if;

  v := t_bnk_set(rA, '090', '3333-01-1234567', '김러너');
  if v ? 'raised' then v_bad := v_bad || ' set raised: ' || (v->>'raised'); end if;
  -- the setter returns the row AS STORED, so the mask it hands back is the one the screen draws
  if (v->>'masked') is distinct from '••••4567'
    then v_bad := v_bad || ' setter mask=' || coalesce(v->>'masked', 'null') || ' (expected ••••4567)'; end if;
  if (v->>'bank') is distinct from '090'
    then v_bad := v_bad || ' bank stored as ' || coalesce(v->>'bank', 'null') || ' (the CODE, not the label)'; end if;
  if (v->>'label') is distinct from '카카오뱅크'
    then v_bad := v_bad || ' label=' || coalesce(v->>'label', 'null'); end if;
  if (v->>'holder') is distinct from '김러너'
    then v_bad := v_bad || ' holder=' || coalesce(v->>'holder', 'null'); end if;
  if v->>'verified' is not null
    then v_bad := v_bad || ' verified_at was STAMPED (' || (v->>'verified') || ') — nothing verifies an account'; end if;

  -- read back through the other door: same answer, still masked
  v2 := t_bnk_mine(rA);
  if (v2->>'rows')::int is distinct from 1
    then v_bad := v_bad || ' my_bank_account rows=' || coalesce(v2->>'rows', 'null'); end if;
  if (v2->>'masked') is distinct from '••••4567'
    then v_bad := v_bad || ' reader mask=' || coalesce(v2->>'masked', 'null'); end if;

  -- 🔴 THE ARM THAT MAKES THIS PIN ABOUT ENCRYPTION AND NOT ABOUT STRING FORMATTING.
  -- A mask can be produced without any encryption at all, so the mask alone cannot tell a real
  -- cipher from a stub that stores the plaintext and slices the last four characters off it.
  select account_enc into v_encA from bank_accounts where runner_id = rA;
  if v_encA is null then v_bad := v_bad || ' NO-CIPHERTEXT(rA)';
  else
    if position('3333011234567' in v_encA) > 0 or position('3333-01-1234567' in v_encA) > 0
      then v_bad := v_bad || ' the ACCOUNT NUMBER IS PRESENT IN account_enc — this is not encryption'; end if;
    -- ⚠ THERE IS NO 「the last four digits are absent」 ARM, deliberately, and it was REMOVED rather
    -- than never written. `pgp_sym_encrypt` mints a fresh random session key per call, so the
    -- base64 is ~150 different characters every run and a four-digit literal turns up in it about
    -- once in 10^5 runs — a pin that reddens on a correct system, which is the one thing worse
    -- than a pin that stays green on a broken one. The 13-digit arm above covers the case that
    -- matters (plaintext stored and the last four sliced off it) with no such collision.
  end if;

  -- the operator's decrypt returns EXACTLY the digits that went in, separators stripped —
  -- the round trip, which is the only thing that proves the ciphertext is the right ciphertext
  v := t_bnk_ops(ops1, rA);
  if (v->>'account') is distinct from '3333011234567'
    then v_bad := v_bad || ' ops decrypt=' || coalesce(v->>'account', 'null') || ' (expected the 13 digits, hyphens stripped)'; end if;

  -- a re-save REPLACES rather than duplicating, and re-encrypts (a different number ⇒ different
  -- ciphertext; the same key, a new random IV ⇒ the ciphertext differs even for equal plaintext)
  v := t_bnk_set(rA, '092', '100 200 300400', '김러너');
  if v ? 'raised' then v_bad := v_bad || ' re-save raised: ' || (v->>'raised'); end if;
  if (v->>'masked') is distinct from '••••0400'
    then v_bad := v_bad || ' re-save mask=' || coalesce(v->>'masked', 'null'); end if;
  if (v->>'label') is distinct from '토스뱅크'
    then v_bad := v_bad || ' re-save label=' || coalesce(v->>'label', 'null'); end if;
  select count(*) into v_n from bank_accounts where runner_id = rA;
  if v_n is distinct from 1 then v_bad := v_bad || ' re-save produced ' || v_n || ' rows'; end if;
  select account_enc into v_encA2 from bank_accounts where runner_id = rA;
  if v_encA2 is not distinct from v_encA
    then v_bad := v_bad || ' the ciphertext did not change when the number did'; end if;
  v := t_bnk_ops(ops1, rA);
  if (v->>'account') is distinct from '100200300400'
    then v_bad := v_bad || ' after re-save ops decrypt=' || coalesce(v->>'account', 'null'); end if;

  if v_bad = '' then call _pass('bnk','0194-B1 러너가 계좌를 등록하면 서버가 암호화해서 보관하고, 양쪽 문(setter의 반환·my_bank_account) 모두 마지막 4자리만 돌려준다; 등록 전에는 0행(이 핀이 공짜로 통과하지 않는다는 대조); bank 에는 라벨이 아니라 코드가 저장되고 verified_at 은 찍히지 않는다. ⚠ 마스크만으로는 암호화를 증명하지 못하므로 — 평문을 저장하고 뒤 4자만 잘라도 같은 마스크가 나온다 — account_enc 안에 번호도 뒤 4자리도 없다는 것과, 운영자 복호화가 들어간 숫자 그대로(구분자만 제거) 나온다는 왕복을 함께 단언한다; 재저장은 행을 늘리지 않고 ciphertext 를 바꾼다');
  else v_msg := v_bad; call _fail('bnk','0194-B1 register and read back masked', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-B2] A cannot read B — through the RPC, and through the TABLE as a real `authenticated`
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_bnk_set(rB, '004', '110-123-456789', '박러너');
  if v ? 'raised' then v_bad := v_bad || ' B''s own registration raised: ' || (v->>'raised'); end if;

  v := t_bnk_mine(rA);
  if (v->>'masked') is distinct from '••••0400'
    then v_bad := v_bad || ' A now reads ' || coalesce(v->>'masked', 'null') || ' — B''s write reached A'; end if;
  v := t_bnk_mine(rB);
  if (v->>'masked') is distinct from '••••6789'
    then v_bad := v_bad || ' B reads ' || coalesce(v->>'masked', 'null'); end if;
  -- the two fixtures DELIBERATELY differ, so 「returns the caller's row」 and 「returns any row」
  -- are distinguishable; with equal fixtures this pin would pass on a function that ignores uid
  if (v->>'holder') is distinct from '박러너'
    then v_bad := v_bad || ' B''s holder=' || coalesce(v->>'holder', 'null'); end if;

  -- a runner with no row gets an honest zero, not someone else's
  v := t_bnk_mine(rC);
  if (v->>'rows')::int is distinct from 0
    then v_bad := v_bad || ' a runner with no account read ' || coalesce(v::text, 'null'); end if;

  -- no caller at all
  v := t_bnk_mine(null);
  if (v->>'raised') is distinct from 'not_signed_in'
    then v_bad := v_bad || ' no-uid read raised ' || coalesce(v->>'raised', 'nothing'); end if;

  -- ── the TABLE, as the real role. RLS decides rows; the column grant decides columns, and only
  -- the second one keeps the ciphertext away from a runner who legitimately sees their own row.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, true);
    execute 'set local role authenticated';
    if current_user <> 'authenticated'
      then v_bad := v_bad || ' SET ROLE did not take (current_user=' || current_user || ')'; end if;

    select count(*) into v_n from bank_accounts;
    if v_n is distinct from 1 then v_bad := v_bad || ' authenticated sees ' || v_n || ' bank rows (expected exactly its own)'; end if;
    select count(*) into v_n from bank_accounts where runner_id = rB;
    if v_n is distinct from 0 then v_bad := v_bad || ' B''s row is VISIBLE to A'; end if;

    -- `account_enc` must not be selectable AT ALL — not filtered, REFUSED (42501)
    v_msg := 'no-error';
    begin execute 'select account_enc from bank_accounts limit 1';
    exception when insufficient_privilege then v_msg := 'refused';
              when others then v_msg := sqlstate; end;
    if v_msg is distinct from 'refused'
      then v_bad := v_bad || ' select account_enc as authenticated: ' || v_msg || ' (expected 42501)'; end if;

    -- and no direct write of any kind
    v_msg := 'no-error';
    begin execute format('update bank_accounts set holder = %L where runner_id = %L', 'X', rA);
    exception when insufficient_privilege then v_msg := 'refused';
              when others then v_msg := sqlstate; end;
    if v_msg is distinct from 'refused'
      then v_bad := v_bad || ' UPDATE as authenticated: ' || v_msg || ' (expected 42501)'; end if;
    v_msg := 'no-error';
    begin execute format('insert into bank_accounts (runner_id, bank, account_enc, holder) values (%L, %L, %L, %L)',
                         rC, '004', 'PLAINTEXT', 'X');
    exception when insufficient_privilege then v_msg := 'refused';
              when others then v_msg := sqlstate; end;
    if v_msg is distinct from 'refused'
      then v_bad := v_bad || ' INSERT as authenticated: ' || v_msg || ' (expected 42501 — a client that can write account_enc can store plaintext)'; end if;

    -- the sealed tables are not readable either
    v_msg := 'no-error';
    begin execute 'select count(*) from bank_account_keys';
    exception when insufficient_privilege then v_msg := 'refused';
              when others then v_msg := sqlstate; end;
    if v_msg is distinct from 'refused'
      then v_bad := v_bad || ' bank_account_keys readable as authenticated: ' || v_msg; end if;
    v_msg := 'no-error';
    begin execute 'select count(*) from bank_account_access_log';
    exception when insufficient_privilege then v_msg := 'refused';
              when others then v_msg := sqlstate; end;
    if v_msg is distinct from 'refused'
      then v_bad := v_bad || ' bank_account_access_log readable as authenticated: ' || v_msg; end if;

    -- the CONTROL for the whole block: the four display columns are still there, or the revoke
    -- above would be 「nobody can read anything」 rather than 「nobody can read the ciphertext」
    select count(*) into v_n from (select runner_id, bank, holder, verified_at, updated_at
                                     from bank_accounts) q;
    if v_n is distinct from 1 then v_bad := v_bad || ' the display columns are NOT readable (' || v_n || ') — the re-grant was lost'; end if;
    reset role;
  exception when others then
    reset role;
    v_bad := v_bad || ' role block died: ' || sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', true);

  if v_bad = '' then call _pass('bnk','0194-B2 남의 계좌는 어느 문으로도 안 보인다: RPC 는 호출자의 행만(두 픽스처를 일부러 다르게 둬서 「호출자의 행」과 「아무 행」이 구분된다), 계좌 없는 러너는 0행, uid 없으면 not_signed_in. 테이블 경로는 진짜 authenticated 롤로 — RLS 가 남의 행을 지우고, 열 단위 grant 가 account_enc 를 아예 거절(42501)하며, INSERT/UPDATE 도 거절된다(클라가 account_enc 를 쓸 수 있으면 평문을 넣을 수 있다). 대조: 표시용 네 열은 그대로 읽힌다 — 아니면 이 핀은 「아무것도 못 읽는다」를 증명한 것이 된다');
  else v_msg := v_bad; call _fail('bnk','0194-B2 another runner''s account is unreachable', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-B3] the ops gate refuses BEFORE any read — and the journal is how that is observable
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v_before := t_bnk_log(ops1) + t_bnk_log(ops_off) + t_bnk_log(ops_other)
              + (select count(*)::int from bank_account_access_log where ops_profile_id in (rB, oA));

  -- a stranger, the owner, a RUNNER (even the row's own owner), an INACTIVE recipient and a
  -- recipient of a DIFFERENT class are all `not_ops`
  v := t_bnk_ops(oA, rA);
  if (v->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' owner ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_ops(rB, rA);
  if (v->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' another runner ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_ops(rA, rA);
  if (v->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' the runner reading their OWN row through the ops door ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_ops(ops_off, rA);
  if (v->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' INACTIVE recipient ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_ops(ops_other, rA);
  if (v->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' wrong-class recipient ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_ops(null, rA);
  if (v->>'raised') is distinct from 'not_signed_in' then v_bad := v_bad || ' no uid ⇒ ' || coalesce(v->>'raised', v::text); end if;

  -- 🔴 THE ORDER ARM. A call carrying a NULL runner from a non-ops caller must answer `not_ops`,
  -- never `no_runner`: the difference between those two answers is itself information about where
  -- the gate sits, and a gate that runs after argument validation has already read something.
  v := t_bnk_ops(oA, null);
  if (v->>'raised') is distinct from 'not_ops'
    then v_bad := v_bad || ' non-ops + null runner ⇒ ' || coalesce(v->>'raised', v::text) || ' (the gate is not first)'; end if;

  -- A refused call leaves NO journal row. ⚠ **AND THIS ARM DOES NOT ESTABLISH THE ORDERING —
  -- measured, after this suite's first draft claimed it did.** Moving the gate to sit AFTER the
  -- journal insert (battery vii) leaves this arm GREEN, because the refusal raises, the raise
  -- unwinds the caller's `exception` block, and plpgsql rolls the subtransaction back — taking the
  -- journal row with it. The evidence erases itself, so the arm cannot tell 「the gate ran first」
  -- from 「the gate ran late and its row was rolled back」.
  -- What it DOES prove is worth keeping and is a different sentence: **the journal contains only
  -- genuine accesses**, never an attempt that was refused — which is the property an auditor reads
  -- it for. The ORDERING is owned by the `not_ops`-not-`no_runner` arm above (behavioural) and by
  -- S1's two source arms (gate before the journal, gate before the decrypt), and battery vii
  -- reddens exactly those two. No arm is added here to chase it: a single session structurally
  -- cannot see a rolled-back write, so a pin claiming to would be green by construction.
  v_after := t_bnk_log(ops1) + t_bnk_log(ops_off) + t_bnk_log(ops_other)
             + (select count(*)::int from bank_account_access_log where ops_profile_id in (rB, oA));
  if v_after is distinct from v_before
    then v_bad := v_bad || ' seven refused calls wrote ' || (v_after - v_before) || ' journal row(s) — the gate runs after the read'; end if;

  -- 🔴 AND THE ARM THAT GIVES `no_runner` A PIN AT ALL. Every null-runner arm above uses a
  -- NON-ops caller, so the answer is `not_ops` with or without the check — delete the check and
  -- nothing reddens, which is the 「a guard with no pin is invisible from both directions」 class.
  -- An OPS caller passing NULL is the only fixture that can see it; without the guard this is a
  -- raw 23502 from the journal's `runner_id not null`, i.e. an unnamed refusal.
  v := t_bnk_ops(ops1, null);
  if (v->>'raised') is distinct from 'no_runner'
    then v_bad := v_bad || ' an OPS caller with a null runner ⇒ ' || coalesce(v->>'raised', v::text); end if;

  -- the control: an ACTIVE recipient of the right class passes
  v := t_bnk_ops(ops1, rA);
  if v ? 'raised' then v_bad := v_bad || ' the ACTIVE ops recipient was refused: ' || (v->>'raised'); end if;

  if v_bad = '' then call _pass('bnk','0194-B3 ops_bank_account 의 파티 게이트가 모든 읽기보다 앞이다: 보호자·다른 러너·자기 행을 ops 문으로 읽으려는 러너·비활성 수신자·다른 클래스 수신자 전부 not_ops, uid 없으면 not_signed_in, 그리고 비-ops 가 null 러너를 실어도 답은 no_runner 가 아니라 not_ops — 두 답의 차이 자체가 게이트 위치에 대한 정보이고, **순서를 실제로 붙잡는 것은 이 팔**이다(S1 의 소스 두 팔과 함께). ⚠ 장부 0행 팔은 순서를 증명하지 않는다 — 실측: 게이트를 장부 기록 뒤로 옮겨도 이 팔은 초록이다(거절이 호출자의 exception 블록을 풀면서 서브트랜잭션이 롤백되고 장부 행도 같이 사라진다). 그 팔이 증명하는 것은 다른 문장이다: **장부에는 실제 열람만 남고 거절된 시도는 남지 않는다.** 대조: 활성·정클래스 수신자는 통과한다');
  else v_msg := v_bad; call _fail('bnk','0194-B3 ops gate precedes every read', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-B4] one ops read = exactly one journal row, measured as a DELTA this call caused
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ Written as before/after around the call rather than as 「the count is N」: a count read off a
  -- table another arm already populated is a fact about the fixture, not about this behaviour.
  v_bad := '';
  v_before := t_bnk_log(ops1);
  v := t_bnk_ops(ops1, rB);
  if v ? 'raised' then v_bad := v_bad || ' the ops read raised: ' || (v->>'raised'); end if;
  if (v->>'account') is distinct from '110123456789'
    then v_bad := v_bad || ' decrypt=' || coalesce(v->>'account', 'null'); end if;
  v_after := t_bnk_log(ops1);
  if (v_after - v_before) is distinct from 1
    then v_bad := v_bad || ' one read wrote ' || (v_after - v_before) || ' journal row(s)'; end if;
  -- ⚠ `g.found` is ALIASED because plpgsql has a built-in variable named `found`; an unqualified
  -- reference is ambiguous and kills the whole suite at parse time rather than failing a pin.
  select count(*) into v_n from bank_account_access_log g
   where g.ops_profile_id = ops1 and g.runner_id = rB and g.found;
  if v_n is distinct from 1
    then v_bad := v_bad || ' the row does not name (this operator, this runner, found=true): ' || v_n; end if;

  -- a read of a runner with NO account still journals — probing for existence is access
  v_before := t_bnk_log(ops1);
  v := t_bnk_ops(ops1, rC);
  if v ? 'raised' then v_bad := v_bad || ' reading an absent account raised: ' || (v->>'raised'); end if;
  if (v->>'rows')::int is distinct from 0
    then v_bad := v_bad || ' an absent account returned ' || coalesce(v->>'rows', 'null') || ' row(s)'; end if;
  v_after := t_bnk_log(ops1);
  if (v_after - v_before) is distinct from 1
    then v_bad := v_bad || ' the found=false read wrote ' || (v_after - v_before) || ' row(s)'; end if;
  select count(*) into v_n from bank_account_access_log g
   where g.ops_profile_id = ops1 and g.runner_id = rC and g.found is false;
  if v_n is distinct from 1
    then v_bad := v_bad || ' no found=false row for the absent account: ' || v_n; end if;

  -- two reads leave two rows (a journal that de-duplicates is a journal that loses a look)
  v_before := t_bnk_log(ops1);
  perform t_bnk_ops(ops1, rB);
  perform t_bnk_ops(ops1, rB);
  v_after := t_bnk_log(ops1);
  if (v_after - v_before) is distinct from 2
    then v_bad := v_bad || ' two reads wrote ' || (v_after - v_before) || ' row(s)'; end if;

  -- 🔴 THE UNREADABLE ROW, WHICH IS THE ONE ACCESS THAT MUST NOT BE ABLE TO HAPPEN QUIETLY.
  -- A row whose ciphertext cannot be opened must come back with `account` NULL and STILL leave a
  -- journal row. The earlier draft RAISED here, and the raise rolled its own journal row back in
  -- the same transaction — so an operator could probe for a row's existence with zero audit, on
  -- exactly the path that most needs a record. Fixture: a hand-written row with garbage in
  -- `account_enc`, which is also the shape every pre-0194 row in the harness already has.
  insert into bank_accounts (runner_id, bank, account_enc, holder)
       values (rC, '004', 'NOT-CIPHERTEXT', '최러너')
    on conflict (runner_id) do update
       set bank = '004', account_enc = 'NOT-CIPHERTEXT', holder = '최러너';
  v_before := t_bnk_log(ops1);
  v := t_bnk_ops(ops1, rC);
  if v ? 'raised'
    then v_bad := v_bad || ' an unreadable row RAISED (' || (v->>'raised') || ') — the raise discards its own journal row'; end if;
  if (v->>'rows')::int is distinct from 1
    then v_bad := v_bad || ' an unreadable row returned ' || coalesce(v->>'rows', 'null') || ' row(s)'; end if;
  if v->>'account' is not null
    then v_bad := v_bad || ' an unreadable row returned an account value: ' || (v->>'account'); end if;
  -- the readable fields still come back, so the operator can see WHOSE row it is
  if (v->>'holder') is distinct from '최러너'
    then v_bad := v_bad || ' the unreadable row lost its holder: ' || coalesce(v->>'holder', 'null'); end if;
  v_after := t_bnk_log(ops1);
  if (v_after - v_before) is distinct from 1
    then v_bad := v_bad || ' the unreadable read wrote ' || (v_after - v_before) || ' journal row(s) — a refusal that erases its own record'; end if;
  select count(*) into v_n from bank_account_access_log g
   where g.ops_profile_id = ops1 and g.runner_id = rC and g.found;
  if v_n is distinct from 1
    then v_bad := v_bad || ' no found=true row for the unreadable account: ' || v_n; end if;
  -- and the RUNNER's own door reports it as a failure rather than as a number
  v := t_bnk_mine(rC);
  if (v->>'rows')::int is distinct from 1
    then v_bad := v_bad || ' the owner of an unreadable row reads ' || coalesce(v->>'rows', 'null') || ' row(s)'; end if;
  if v->>'masked' is not null
    then v_bad := v_bad || ' an unreadable row produced a MASK: ' || (v->>'masked'); end if;
  delete from bank_accounts where runner_id = rC;

  if v_bad = '' then call _pass('bnk','0194-B4 복호화는 절대 조용히 일어나지 않는다: ops 읽기 한 번 = 장부 한 행이고, 그 행은 (이 운영자, 이 러너, found=true)를 이름으로 가진다; 계좌가 없는 러너를 조회해도 found=false 로 한 행 남는다(존재 여부를 떠보는 것도 접근이다); 두 번 읽으면 두 행이다(합치는 장부는 한 번의 열람을 잃는 장부다). 🔴 그리고 **복호화가 안 되는 행** — 예외를 던지지 않고 account=NULL 로 보고하며 장부 행을 남긴다. 예외를 던지면 같은 트랜잭션의 장부 행이 함께 롤백돼, 운영자가 아무 흔적 없이 행의 존재를 떠볼 수 있는 유일한 경로가 된다; 읽을 수 있는 필드(예금주)는 그대로 오고, 그 행의 주인이 자기 문으로 봐도 마스크가 아니라 NULL 이 온다(화면은 다시 등록을 안내한다). ⚠ 전부 호출 전후의 DELTA 로 잰다 — 이미 채워진 테이블에서 읽은 개수는 픽스처에 대한 사실이지 이 동작에 대한 사실이 아니다');
  else v_msg := v_bad; call _fail('bnk','0194-B4 every ops read is journalled exactly once', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-B5] delete refused while owed, allowed after paid — and the row survives INTACT
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  -- rA has two settled, unpaid ledger rows and a bank row on file.
  v_rowA := t_bnk_row(rA);
  if v_rowA is null then v_bad := v_bad || ' NO-BANK-ROW(rA) — the fixture for this pin is missing'; end if;

  v := t_bnk_del(rA);
  if (v->>'raised') is distinct from 'payout_owed'
    then v_bad := v_bad || ' delete while owed ⇒ ' || coalesce(v->>'raised', v::text); end if;
  -- 🔴 INTACT, not merely present. Sean's A-intact-when-owed: a blanked row is a row nobody can
  -- pay into, which defeats the whole reason for keeping it.
  if t_bnk_row(rA) is distinct from v_rowA
    then v_bad := v_bad || ' the refused delete CHANGED the row'; end if;

  -- 🔴 THE ARM THAT SITS WHERE THE TWO CANDIDATE PREDICATES DISAGREE, and it exists because a cold
  -- reviewer measured that without it this pin is testing the fixture. Every other fixture here is
  -- SETTLED (`t_settle` ends the run), which is the AGREEMENT zone of `0190 §B`'s rule (any unpaid
  -- ledger row) and of the payout-eligibility rule this file's first draft borrowed from 0186 (an
  -- unpaid row whose booking has no OPEN run). A runner with an unpaid row on a booking whose run
  -- is still running is the ONLY shape that separates them: the borrowed rule says 「nothing owed,
  -- delete away」, the shipped rule says 「money is owed, keep the destination」. Hand-built because
  -- no helper produces it — which is exactly why the draft's mutation could redden nothing.
  select * into oC, rD, dD, tD from t_bnk_world('d', 0);
  v_bk := t_active_booking(oC, rD, dD, tD, now() - interval '1 hour');
  if (select count(*) from runs rn where rn.booking_id = v_bk and rn.ended_at is null) is distinct from 1
    then v_bad := v_bad || ' the open-run fixture has no live run — this arm would prove nothing'; end if;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, platform_fee)
       values (rD, v_bk, 10000, 0, 3300);
  v := t_bnk_set(rD, '011', '3020000123456', '정러너');
  if v ? 'raised' then v_bad := v_bad || ' rD registration raised: ' || (v->>'raised'); end if;
  v := t_bnk_del(rD);
  if (v->>'raised') is distinct from 'payout_owed'
    then v_bad := v_bad || ' an unpaid row on a booking with an OPEN run ⇒ ' || coalesce(v->>'raised', v::text)
                        || ' — this is the fixture where 0190 §B and 0186''s eligibility rule DISAGREE, and the shipped rule must refuse'; end if;
  select count(*) into v_n from bank_accounts where runner_id = rD;
  if v_n is distinct from 1 then v_bad := v_bad || ' rD''s row did not survive the refusal'; end if;

  -- the control against 「always refuse」: rC is a runner with no earnings at all, and rC's delete
  -- must succeed. Register one first so the delete has something to remove.
  v := t_bnk_set(rC, '088', '110-999-000111', '최러너');
  if v ? 'raised' then v_bad := v_bad || ' rC registration raised: ' || (v->>'raised'); end if;
  v := t_bnk_del(rC);
  if v ? 'raised' then v_bad := v_bad || ' an unowed runner''s delete was refused: ' || (v->>'raised'); end if;
  select count(*) into v_n from bank_accounts where runner_id = rC;
  if v_n is distinct from 0 then v_bad := v_bad || ' rC''s row survived a successful delete (' || v_n || ')'; end if;

  -- now PAY rA's last unpaid row through 0186's writer, and the same call that was refused
  -- succeeds. This is the arm that separates 「owed」 from 「has ever earned」.
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  select coalesce(array_agg(id order by created_at, id), '{}'::uuid[]) into ids
    from ledger_items where runner_id = rA and paid_payout_id is null;
  select coalesce(sum(base + distance_pay + addon_pay + tip
                      + coalesce(remaining_guarantee, 0) - platform_fee), 0)::int into v_net
    from ledger_items where id = any(ids);
  if coalesce(array_length(ids, 1), 0) < 1
    then v_bad := v_bad || ' rA has no unpaid ledger rows — the refusal above proved nothing';
  else
    perform ops_record_manual_payout(rA, ids, v_net, 'bnk');
    perform set_config('request.jwt.claim.sub', '', true);
    -- ⚠ 0190 §C releases a TOMBSTONED runner's retained row when the last unpaid row clears.
    -- rA is LIVE, so the row must still be here — that is 221 R4's property observed from this
    -- side, and without it the next arm would pass for the wrong reason.
    if t_bnk_row(rA) is distinct from v_rowA
      then v_bad := v_bad || ' a LIVE runner''s bank row was changed by the payout'; end if;
    v := t_bnk_del(rA);
    if v ? 'raised' then v_bad := v_bad || ' delete after payment ⇒ ' || (v->>'raised'); end if;
    select count(*) into v_n from bank_accounts where runner_id = rA;
    if v_n is distinct from 0 then v_bad := v_bad || ' the row survived the permitted delete (' || v_n || ')'; end if;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);

  if v_bad = '' then call _pass('bnk','0194-B5 지급 대기 중인 정산이 있으면 계좌 삭제는 payout_owed 로 거절되고, 거절된 삭제는 행을 **바이트 그대로** 남긴다(Sean 의 A-intact-when-owed — 비워 놓은 행은 아무도 입금할 수 없는 행이다); 0186 의 기록자가 마지막 미지급 행을 지우면 같은 호출이 성공한다. 🔴 그리고 **두 후보 술어가 갈라지는 자리에 픽스처가 하나 있다** — 아직 끝나지 않은 run 을 가진 예약의 미지급 행: 0190 §B 의 보관 술어는 거절하고, 첫 초안이 0186 에서 빌려 온 지급-자격 술어는 허용한다. 나머지 팔은 전부 두 규칙이 합의하는 구역이라 이 팔이 없으면 이 핀은 규칙이 아니라 픽스처를 재는 핀이다. 두 방향이 다 필요하다: 「항상 거절」은 뒷팔과 rC(수익이 없는 러너) 대조에서 죽고 「절대 거절 안 함」은 앞팔에서 죽으므로 어떤 상수도 둘을 동시에 만족시키지 못한다. 대조 하나 더 — 살아 있는 러너의 계좌는 지급으로 사라지지 않는다(0190 §C 의 해제는 툼스톤 전용; 221 R4 를 이쪽에서 본 것)');
  else v_msg := v_bad; call _fail('bnk','0194-B5 delete refused while owed, allowed after paid', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-B6] the refusal vocabulary, and every arm writes NOTHING
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*) into v_before from bank_accounts;

  -- party gate: an OWNER is not a runner, and the gate is ahead of every validation — so a call
  -- with a bad bank AND a bad account AND a bad holder still answers `not_runner`
  v := t_bnk_set(oA, 'NOPE', 'xx', '');
  if (v->>'raised') is distinct from 'not_runner'
    then v_bad := v_bad || ' owner with three bad arguments ⇒ ' || coalesce(v->>'raised', v::text) || ' (the party gate is not first)'; end if;
  v := t_bnk_set(null, '004', '1101234567', '김');
  if (v->>'raised') is distinct from 'not_signed_in' then v_bad := v_bad || ' no uid ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_del(oA);
  if (v->>'raised') is distinct from 'not_runner' then v_bad := v_bad || ' owner delete ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_del(null);
  if (v->>'raised') is distinct from 'not_signed_in' then v_bad := v_bad || ' no-uid delete ⇒ ' || coalesce(v->>'raised', v::text); end if;

  -- bad_bank: an unknown code, a LABEL passed where a code belongs, and a code that is inactive
  update bank_codes set active = false where code = '071';
  v := t_bnk_set(rB, '999', '1101234567', '박러너');
  if (v->>'raised') is distinct from 'bad_bank' then v_bad := v_bad || ' unknown code ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '카카오뱅크', '1101234567', '박러너');
  if (v->>'raised') is distinct from 'bad_bank' then v_bad := v_bad || ' a LABEL where a code belongs ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '071', '1101234567', '박러너');
  if (v->>'raised') is distinct from 'bad_bank' then v_bad := v_bad || ' an INACTIVE bank ⇒ ' || coalesce(v->>'raised', v::text); end if;
  update bank_codes set active = true where code = '071';

  -- bad_account: too short, too long, letters, a separator-only string, empty, null,
  -- and 🔴 the one that matters most — a number with TEXT around it. Stripping non-digits first
  -- would silently store 1234567890 for 「계좌 1234567890 입니다」, a value nobody typed.
  v := t_bnk_set(rB, '004', '123456789', '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' 9 digits ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '12345678901234567', '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' 17 digits ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '110-abc-456789', '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' letters ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '계좌 1234567890 입니다', '박러너');
  if (v->>'raised') is distinct from 'bad_account'
    then v_bad := v_bad || ' digits buried in text ⇒ ' || coalesce(v->>'raised', v::text) || ' (a strip-first implementation accepts this)'; end if;
  v := t_bnk_set(rB, '004', '----------', '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' separators only ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '', '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' empty ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', null, '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' null ⇒ ' || coalesce(v->>'raised', v::text); end if;
  -- the boundary is INCLUSIVE on both ends, so 10 and 16 are accepted (the control that stops
  -- 「refuse everything」 passing every arm above)
  v := t_bnk_set(rB, '004', '1234567890', '박러너');
  if v ? 'raised' then v_bad := v_bad || ' 10 digits refused: ' || (v->>'raised'); end if;
  v := t_bnk_set(rB, '004', '1234567890123456', '박러너');
  if v ? 'raised' then v_bad := v_bad || ' 16 digits refused: ' || (v->>'raised'); end if;
  -- 🔴 A PASTED NUMBER. `bank-account.ts` trims before testing the same regex, so without `btrim`
  -- here the CLIENT accepts this and the SERVER refuses it — the person is told 「숫자 10~16자리」
  -- while looking at a field holding exactly ten digits, and nothing they can do resolves it. This
  -- arm is the server half of that agreement; the client half is pinned in bank-account.test.cjs.
  v := t_bnk_set(rB, '004', '  1234567890  ', '박러너');
  if v ? 'raised'
    then v_bad := v_bad || ' a PASTED (whitespace-padded) number was refused: ' || (v->>'raised')
                        || ' — the client mirror accepts it, so this is a drift the user cannot resolve'; end if;
  if (v->>'masked') is distinct from '••••7890'
    then v_bad := v_bad || ' a padded number stored as ' || coalesce(v->>'masked', 'null'); end if;
  -- ...and the whitespace is a SEPARATOR only at the edges: interior spaces already group digits,
  -- but a string that is nothing but separators after trimming is still not an account number
  v := t_bnk_set(rB, '004', '   ', '박러너');
  if (v->>'raised') is distinct from 'bad_account' then v_bad := v_bad || ' whitespace-only account ⇒ ' || coalesce(v->>'raised', v::text); end if;

  -- bad_holder: empty, whitespace only, null, over-long; and the control — a trimmed name stores
  v := t_bnk_set(rB, '004', '1101234567', '');
  if (v->>'raised') is distinct from 'bad_holder' then v_bad := v_bad || ' empty holder ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '1101234567', '   ');
  if (v->>'raised') is distinct from 'bad_holder' then v_bad := v_bad || ' whitespace holder ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '1101234567', null);
  if (v->>'raised') is distinct from 'bad_holder' then v_bad := v_bad || ' null holder ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '1101234567', repeat('가', 61));
  if (v->>'raised') is distinct from 'bad_holder' then v_bad := v_bad || ' 61-char holder ⇒ ' || coalesce(v->>'raised', v::text); end if;
  v := t_bnk_set(rB, '004', '1101234567', '  박러너  ');
  if v ? 'raised' then v_bad := v_bad || ' a padded holder was refused: ' || (v->>'raised'); end if;
  if (v->>'holder') is distinct from '박러너'
    then v_bad := v_bad || ' the holder was not trimmed: [' || coalesce(v->>'holder', 'null') || ']'; end if;

  -- 🔴 NOTHING NEW WAS WRITTEN. rB already had a row and the accepted controls above rewrote it;
  -- what must not have happened is a refusal creating one, so the population is what is asserted.
  select count(*) into v_after from bank_accounts;
  if v_after is distinct from v_before
    then v_bad := v_bad || ' the refusal arms changed the bank_accounts population by ' || (v_after - v_before); end if;

  if v_bad = '' then call _pass('bnk','0194-B6 이름으로 거절하는 어휘 전부 — not_signed_in · not_runner(보호자; 잘못된 인자 세 개를 함께 실어도 답은 not_runner 다 = 파티 게이트가 검증보다 앞) · bad_bank(없는 코드·코드 자리에 라벨·비활성 은행) · bad_account(9자리·17자리·글자·글 속에 묻힌 숫자·구분자만·빈 문자열·null) · bad_holder(빈 값·공백만·null·61자). 대조 넷: 10자리와 16자리는 받고(경계는 양끝 포함), 앞뒤 공백이 있는 이름은 trim 해서 저장한다 — 이게 없으면 「전부 거절」이 위의 모든 팔을 통과한다. ⚠ 「글 속에 묻힌 숫자」가 이 팔의 핵심이다: 숫자가 아닌 문자를 먼저 걷어내는 구현은 아무도 입력하지 않은 번호를 조용히 저장한다');
  else v_msg := v_bad; call _fail('bnk','0194-B6 the refusal vocabulary', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0194-S1] deployed shape — what B1…B6 cannot see, and what §G only sees at apply time
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ §G's VERIFY and these arms are different artifacts (0131-G4's lesson): the VERIFY aborts an
  -- apply that lands wrong, this reddens when a LATER file recreates one of these functions and
  -- drops the envelope. A property checked only at apply is protected until someone recreates it.
  v_bad := '';
  foreach fn in array array['my_bank_account()', 'set_my_bank_account(text,text,text)',
                            'delete_my_bank_account()', 'ops_bank_account(uuid)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':definer 아님'; end if;
    -- ⚠ EQUALITY on the exact literal, not a containment. `public, extensions, pg_temp` is
    -- deliberate (0194 §0a: pgcrypto lives in `public` on a from-scratch apply and in `extensions`
    -- on Supabase, and a definer pinned to the house literal resolves in the harness and FAILS IN
    -- PRODUCTION). A future session 「simplifying」 it back reddens here.
    if (select coalesce(array_to_string(proconfig, ','), '') from pg_proc where oid = v_oid)
       is distinct from 'search_path=public, extensions, pg_temp'
      then v_bad := v_bad || ' ' || fn || ':search_path=['
                          || (select coalesce(array_to_string(proconfig, ','), '(none)') from pg_proc where oid = v_oid) || ']'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ':anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':authenticated 실행 불가'; end if;
  end loop;

  -- the two helpers: NOT definers (a definer that returns plaintext is one bad grant from being a
  -- plaintext oracle) and not executable by any client role
  -- ⚠ `service_role` IS IN THIS LOOP and its absence was a real hole in the first draft: the shim
  -- grants EXECUTE on public functions to service_role BY DEFAULT precisely because production
  -- does (`00_shim.sql:132-135`, and `0129:105-120` measured the default ACL), so an arm checking
  -- only anon/authenticated is structurally blind to the one role that had the door open. Without
  -- the revoke, `_bank_account_key()` is a PostgREST RPC that returns the key.
  foreach fn in array array['_bank_account_key()', '_bank_account_plain(uuid)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not false
      then v_bad := v_bad || ' ' || fn || ':definer 다(그러면 안 된다)'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
    or has_function_privilege('service_role', v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ':클라 실행 가능'; end if;
  end loop;

  -- the column grant, both directions
  if has_column_privilege('authenticated', 'bank_accounts', 'account_enc', 'SELECT') is not false
    then v_bad := v_bad || ' account_enc 를 클라가 읽을 수 있다'; end if;
  foreach fn in array array['runner_id', 'bank', 'holder', 'verified_at', 'updated_at'] loop
    if has_column_privilege('authenticated', 'bank_accounts', fn, 'SELECT') is not true
      then v_bad := v_bad || ' 표시용 열 ' || fn || ' 의 재부여가 사라졌다'; end if;
  end loop;
  if has_table_privilege('authenticated', 'bank_accounts', 'INSERT') is not false
  or has_table_privilege('authenticated', 'bank_accounts', 'UPDATE') is not false
  or has_table_privilege('authenticated', 'bank_accounts', 'DELETE') is not false
    then v_bad := v_bad || ' bank_accounts 에 클라 쓰기 권한이 있다'; end if;

  -- the sealed tables
  if (select relrowsecurity from pg_class where oid = 'bank_account_keys'::regclass) is not true
    then v_bad := v_bad || ' bank_account_keys:RLS 꺼짐'; end if;
  if (select count(*) from pg_policy where polrelid = 'bank_account_keys'::regclass) is distinct from 0
    then v_bad := v_bad || ' bank_account_keys 에 정책이 생겼다'; end if;
  if (select relrowsecurity from pg_class where oid = 'bank_account_access_log'::regclass) is not true
    then v_bad := v_bad || ' bank_account_access_log:RLS 꺼짐'; end if;
  -- bank_codes' seal was pinned NOWHERE in the first draft — sealed in §B and checked by neither
  -- §G nor here, which is a seal nobody would notice stopping existing.
  if (select relrowsecurity from pg_class where oid = 'bank_codes'::regclass) is not true
    then v_bad := v_bad || ' bank_codes:RLS 꺼짐'; end if;
  foreach fn in array array['bank_account_keys', 'bank_account_access_log', 'bank_codes'] loop
    if has_table_privilege('authenticated', fn, 'SELECT') is not false
    or has_table_privilege('anon', fn, 'SELECT') is not false
      then v_bad := v_bad || ' ' || fn || ':클라가 읽을 수 있다'; end if;
  end loop;
  if (select count(*) from bank_account_keys) is distinct from 1
    then v_bad := v_bad || ' 키 행이 하나가 아니다'; end if;
  if (select length(key_material) from bank_account_keys where id = 1) is distinct from 32
    then v_bad := v_bad || ' 키 길이가 32바이트가 아니다'; end if;
  -- the journal's FK ABSENCE — 0186 §A's argued choice, pinned so a later session cannot
  -- 「tidy it up」 into the restrict/cascade dilemma 0115 refuses
  if (select count(*) from pg_constraint
       where conrelid = 'bank_account_access_log'::regclass and contype = 'f') is distinct from 0
    then v_bad := v_bad || ' 장부에 FK 가 생겼다(0186 §A 가 안 된다고 논증한 것)'; end if;

  -- ── SOURCE, comments STRIPPED. `prosrc` is source PLUS our own prose, so an un-stripped match
  -- is satisfied by a comment EXPLAINING the guard — the better the explanation, the surer the
  -- false green. Every arm below has a NO-SOURCE partner so an absent function fails LOUDLY
  -- rather than collapsing every `position(… in NULL)` to NULL and firing nothing.
  v_oid := to_regprocedure('ops_bank_account(uuid)');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_bank_account)';
  else
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_bank_account)';
    else
      if (position('ops_recipients_for' in v_src) > 0) is not true
        then v_bad := v_bad || ' ops 게이트가 본문에 없다'; end if;
      -- the gate is ahead of BOTH the journal insert and the decrypt
      if (position('ops_recipients_for' in v_src) > 0
          and position('bank_account_access_log' in v_src) > 0
          and position('ops_recipients_for' in v_src) < position('bank_account_access_log' in v_src)) is not true
        then v_bad := v_bad || ' ops 게이트가 장부 기록보다 뒤에 있다'; end if;
      if (position('ops_recipients_for' in v_src) > 0
          and position('_bank_account_plain' in v_src) > 0
          and position('ops_recipients_for' in v_src) < position('_bank_account_plain' in v_src)) is not true
        then v_bad := v_bad || ' ops 게이트가 복호화보다 뒤에 있다'; end if;
      -- 🔴 IT MUST NOT RAISE ON AN UNREADABLE ROW — a raise rolls back its own journal row, so the
      -- least auditable call would be the only one leaving no audit. Asserted as an ABSENCE,
      -- which is the direction that catches a later session 「restoring」 the refusal.
      if (position('account_unreadable' in v_src) > 0) is not false
        then v_bad := v_bad || ' 복호화 실패에 예외를 던진다 — 같은 트랜잭션의 장부 행이 함께 롤백된다'; end if;
      if (position('_bank_account_plain' in v_src) > 0
          and position('bank_account_access_log' in v_src) > 0
          and position('bank_account_access_log' in v_src)
              < position('_bank_account_plain' in v_src)) is not true
        then v_bad := v_bad || ' 장부 기록이 복호화보다 뒤에 있다'; end if;
      -- the raw>stripped arm: proof the strip is load-bearing rather than decorative
      if (select length(prosrc) > length(v_src) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 주석 제거가 아무것도 지우지 않았다(스트립이 무의미하다는 뜻)'; end if;
    end if;
  end if;

  v_oid := to_regprocedure('set_my_bank_account(text,text,text)');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(set_my_bank_account)';
  else
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(set_my_bank_account)';
    else
      -- the server encrypts. A body that stores `p_account` anywhere near `account_enc` without
      -- `pgp_sym_encrypt` is the failure this whole slice exists to prevent.
      if (position('pgp_sym_encrypt' in v_src) > 0) is not true
        then v_bad := v_bad || ' 암호화 호출이 본문에 없다'; end if;
      if (position('runners' in v_src) > 0
          and position('pgp_sym_encrypt' in v_src) > 0
          and position('runners' in v_src) < position('pgp_sym_encrypt' in v_src)) is not true
        then v_bad := v_bad || ' 러너 파티 게이트가 쓰기보다 뒤에 있다'; end if;
      -- verified_at is never given a value other than null
      if (position('verified_at = null' in v_src) > 0) is not true
        then v_bad := v_bad || ' verified_at 을 NULL 로 초기화하지 않는다'; end if;
      if (position('now()' in v_src) > 0 and position('verified_at = now()' in v_src) = 0) is not true
        then v_bad := v_bad || ' verified_at 에 시각을 찍는다(검증하는 것이 없는데)'; end if;
      -- the server trims before testing the shape, so the client mirror's trim is not a drift
      if (position('btrim(p_account)' in v_src) > 0) is not true
        then v_bad := v_bad || ' 계좌번호를 btrim 하지 않는다 — 클라 미러는 trim 하므로 붙여넣은 번호가 클라에선 통과하고 서버에서 거절된다'; end if;
    end if;
  end if;

  v_oid := to_regprocedure('delete_my_bank_account()');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(delete_my_bank_account)';
  else
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(delete_my_bank_account)';
    else
      -- 🔴 THE OWED PREDICATE IS `0190 §B`'s AND NOTHING MORE, asserted in BOTH directions.
      -- The presence arm alone would pass on the first draft's predicate, which carried the same
      -- clause PLUS 0186's `not exists(open run)` — text copied across a polarity flip, so one
      -- Sean ruling had two doors giving opposite answers about a money destination. The ABSENCE
      -- arm is what makes this pin able to tell those two apart, and it is the arm the first
      -- draft could not have had.
      if (position('paid_payout_id is null' in v_src) > 0) is not true
        then v_bad := v_bad || ' 미지급 술어가 paid_payout_id 를 읽지 않는다'; end if;
      if (position('ended_at is null' in v_src) > 0) is not false
        then v_bad := v_bad || ' 삭제 게이트가 0186 의 지급-자격 절(열린 run)을 다시 들여왔다 — 0190 §B 의 보관 술어와 글자 그대로 같아야 한다'; end if;
      if (position('is not true' in v_src) > 0) is not true
        then v_bad := v_bad || ' 거절이 fail-closed 로 쓰여 있지 않다'; end if;
    end if;
  end if;

  if v_bad = '' then call _pass('bnk','0194-S1 배포 형상: 네 definer 의 prosecdef·본문 search_path(= public, extensions, pg_temp 정확히 일치 — 0194 §0a 의 이유로 집 표준 리터럴이 아니고, 되돌리면 여기가 붉어진다)·값으로 본 ACL; 두 내부 헬퍼는 definer가 **아니어야** 하고 클라가 실행할 수 없다(평문을 돌려주는 definer 는 잘못된 grant 하나 거리의 평문 오라클이다); 열 단위 grant 양방향(account_enc 불가 · 표시용 다섯 열 가능 · 쓰기 전부 불가); 봉인된 두 테이블의 RLS·정책 0개·키 한 행 32바이트; 장부의 FK 0개(0186 §A 가 논증한 부재); 소스는 주석을 제거하고 읽는다(prosrc 는 소스이자 우리 산문이라, 안 지우면 가드를 **설명하는 주석**이 가드를 **호출하는 코드** 대신 매치된다) — ops 게이트가 장부 기록과 복호화 둘 다보다 앞, 복호화 실패는 이름 있는 거절, 러너 게이트가 쓰기보다 앞, verified_at 은 NULL 로만 쓰이고 시각이 찍히지 않는다; 각 팔에 NO-SOURCE 짝과 raw>stripped 대조');
  else v_msg := v_bad; call _fail('bnk','0194-S1 deployed shape', v_msg); end if;
end $$;
