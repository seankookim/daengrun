-- ═══ 233 — 0202: one row version for the operator, no destination behind a tombstone ═════════
-- ═══        0202-A1…A4 · B1…B5 · S1, tag `bdr`                                           ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a
-- pin written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · A1 `ops_bank_account` still answers exactly what 0194 §F④ promised after the rewrite — bank
--        CODE (not label), the joined label, holder, the FULL decrypted number, a NULL
--        `verified_at`, an `updated_at` — and every one of those agrees with what the TABLE holds.
--        A runner with no row gets 0 rows. ⚠ This is the CONTROL for §A, not the atomicity pin:
--        its job is to fail if collapsing three reads into one broke the answer.
--   · A2 0194 §D's journal survives the rewrite intact: one gated call = exactly ONE journal row,
--        measured as a DELTA this call caused; a runner with no account still journals
--        `found = false` and returns 0 rows (probing for existence is access); and an UNREADABLE
--        ciphertext still returns the row with `account = NULL`, raises NOTHING, and KEEPS its
--        journal line — the arm that matters, because a raise would roll back its own audit.
--   · A3 🔴 **THE FIX, and it can only be held in SOURCE.** `ops_bank_account`'s comment-stripped
--        body names `bank_accounts` in EXACTLY ONE statement, decrypts the ciphertext that
--        statement captured (`_bank_account_plain_enc(v_enc)`), and `_bank_account_plain_enc`
--        does not read the table at all. The 0194 order — ops gate → journal → decrypt — is
--        unchanged. See the LIMITATION note below for why there is no behavioural arm.
--   · A4 **THE PRECONDITION the fix reasons from, checked rather than assumed.**
--        `ops_bank_account` is VOLATILE (it must be — it INSERTs the journal row) and therefore
--        takes a fresh snapshot per statement, which is what made three reads a torn read.
--        `my_bank_account` is STABLE and so runs its whole body under the caller's snapshot, which
--        is the entire reason 0202 left it alone. Plus the new helper's shape: INVOKER, not
--        client-executable by anon / authenticated / **service_role**, in-body `search_path`.
--   · B1 🔴 **claim → account deletion → the destination is gone.** A runner claims gear through
--        the real `claim_gear_tx`, then `delete_my_account_tx` tombstones them. The row's
--        `delivery` then contains NO recipient, phone, address1, address2 or postal text — asserted
--        as the ABSENCE of each typed string anywhere in the jsonb, not merely as a changed value —
--        and is exactly `{"redacted": true}`. The FULFILMENT RECORD survives: status, claimed_at,
--        item, milestone. CONTROL: a live runner's claim is byte-identical afterwards.
--   · B2 As ops, `ops_gear_claims_pending()` does not return the redacted claim, and DOES still
--        return the live runner's claim with all five fields. Without the second half this pin
--        would pass on a function that returned nothing at all.
--   · B3 `ops_mark_gear_shipped` refuses a redacted claim by the name `claim_redacted` and writes
--        NOTHING — still `claimed`, no carrier, no tracking, no `dispatched_at`. The live claim
--        still ships (control), a `shipped` row still answers `already_shipped` FIRST, and a
--        `claimable` row still answers `not_claimed` — the new gate did not displace the two that
--        were already there.
--   · B4 The one-time repair `_gear_redact_tombstoned_deliveries()` redacts a snapshot sitting
--        behind an ALREADY-tombstoned profile and returns the count; a LIVE runner's snapshot is
--        untouched (control); a second call returns 0.
--   · B5 The widened shape belt: NULL admitted, a postable five-field address admitted, the exact
--        marker admitted, a malformed address still REFUSED (0195's arm intact), and **a marker
--        carrying a sixth key REFUSED** — the redaction is one value, not a shape (0202 §0b).
--   · S1 Deployed shape: the four re-declared definers' `prosecdef` / in-body `search_path` / ACL
--        by EFFECTIVE privilege; `delete_my_account_tx`'s redaction present and positioned inside
--        the anonymise stage, with 0138 §F's enqueue, 0190 §B's retention predicate and 0191 §A's
--        NINE detail arms all still in the catalog copy; the repair helper's tombstone predicate;
--        every arm comment-STRIPPED with a NO-SOURCE partner and a raw>stripped control.
--
-- ─── THE LIMITATION, WRITTEN AS PROSE BECAUSE A PIN COULD NOT HOLD IT ───
-- 🔴 **THE HARNESS CANNOT REACH FINDING 3's INTERLEAVING, AND NO PIN HERE PRETENDS TO.**
-- A torn read needs a `set_my_bank_account` to COMMIT between two statements of a running
-- `ops_bank_account`. Every suite in this manifest is one psql connection inside one transaction,
-- so there is no second session to commit, and a statement's own transaction sees its own writes
-- either way — every arm one could write about the OLD body would be green. Per the standing rule
-- (a limitation is PROSE; the tell is that you are writing a pin and cannot describe the mutation
-- that would redden it), no behavioural pin is written and the property is held by A3's source
-- arms and A4's volatility arms instead.
-- ⚠ The door that DOES exist is named rather than left implicit: `90_race_check.sh` runs two
--   connections and could carry such an arm. It is not extended here because it is a shared file
--   owned by other slices and the source pin is what a future edit would actually trip over —
--   but 「impossible」 would be the wrong word, and the honest one is 「not built」.
--
-- ─── FIXTURE NOTES ───
--  ① Every count is SCOPED to this suite's own profiles and its own operator. `gear_claims` is
--     shared with 141, 207 and 226 and `bank_account_access_log` with 225, so a global count would
--     measure the harness rather than this slice.
--  ② The world is built as the OWNER of the tables (the harness's default role) so fixtures can
--     set `status` and plant an unreadable ciphertext; every ASSERTION about the product goes
--     through an RPC with `request.jwt.claim.sub` set, which is how a real caller arrives.
--  ③ `request.jwt.claim.sub` is cleared explicitly wherever a no-caller answer matters.
--  ④ The runners deleted here are BARE — a profile, a `runners` row and a gear claim, nothing
--     else — so `delete_my_account_tx`'s twelve state gates are all satisfied and the pin measures
--     the redaction rather than a refusal.
--
-- ─── MUTATION MAP — measured 2026-09-22 against these exact files, not predicted ───
-- Lab: a copy of `supabase/` OUTSIDE the worktree with `.pgtest` EXCLUDED so it does its own
-- initdb (a copied data dir is a broken data dir, and its failure wears the costume of a working
-- guard); this suite md5-identical to the committed one. Every plant asserts its target occurs
-- EXACTLY ONCE and **exits non-zero**, `&&`-chained to the harness, so a failed plant yields NO
-- row rather than a green one for a mutation that never landed. 「demoted」 = the matching 0202 §C
-- VERIFY arm turned into a comment, so what is measured is the SUITE rather than the apply
-- (0131-G4). **Control observed clean FIRST at 1407 / 0 — and again at the END of the battery,
-- also 1407 / 0**, so the frame is valid at both ends.
--
--   M1a  the capture split back into two statements, VERIFY intact
--                                  → the APPLY ABORTS: `0202 §C VERIFY:
--        ops_bank_account:DECRYPT-NOT-FROM-THE-CAPTURED-CIPHERTEXT`. That plant measures the
--        VERIFY, not this file.
--   M1b  the same plant, those VERIFY arms removed
--                                  → **1406/1: `0202-A3` ALONE**, naming both arms.
--   🔴 M1 ALSO CORRECTED ONE OF MY OWN ARMS, AND THE CORRECTION IS RECORDED RATHER THAN TIDIED
--      AWAY. A3's `from bank_accounts` COUNT arm **did not fire** on M1 — reverting the decrypt to
--      `_bank_account_plain(p_runner)` moves the second read into the HELPER and leaves the
--      in-body count at 1. The count arm is not blind (M7 below), but it cannot see the most
--      likely regression, and the two arms cover DIFFERENT failures with neither implying the
--      other. That is why A3 carries three arms and not one.
--   M7   the OTHER half of the old shape re-introduced — a separate `select exists … from
--        bank_accounts` for the journal, capture left in place
--                                  → **1406/1: `0202-A3` alone**, 「문장이 2개다」. The count arm
--        earning its place.
--   M2a  the deletion's redaction statement removed, VERIFY intact
--                                  → the APPLY ABORTS (`NO-DELIVERY-REDACTION` +
--        `REDACTION-NOT-IN-THE-ANONYMISE-STAGE`).
--   M2b  the same plant, those VERIFY arms removed
--                                  → **1402/5: `0202-B1` names all five PII fields surviving the
--        tombstone BY NAME, plus `S1`; `B2`/`B3`/`B4` are CASCADES off the un-redacted world, not
--        independent detections** — named so nobody reads 「5 pins caught it」 as five witnesses.
--        (B4's fixture arm is what reports its cascade honestly: 「툼스톤 뒤에 남은 배송지가
--        2개다」 rather than silently moving its own number.)
--   M3   the `claim_redacted` raise deleted
--                                  → **1405/2: `B3` + `S1`.** The redacted claim is ACCEPTED and
--        reaches `shipped` with a tracking number, for a box that cannot be posted.
--   M4   the repair's `deleted_at is not null` conjunct deleted
--                                  → **1405/2: `B4` + `S1`**, and it is B4's CONTROL that fires —
--        「수리가 **살아 있는 러너**의 배송지를 지웠다」 — with the repair reporting 7 rows where
--        the candidate set is 1.
--   M5   the ops list stops excluding redacted rows
--                                  → **1405/2: `B2` + `S1`.**
--   M6   the constraint admits a SHAPE (`delivery ? 'redacted'`) instead of one VALUE
--                                  → **1406/1: `B5` ALONE** — a row marked redacted that still
--        carries a phone number.
--   M9   bank CODE and LABEL swapped in the return — the slip a single-statement rewrite invites
--                                  → **1406/1: `0202-A1` ALONE.** This plant exists only because
--        **a battery that never attacks its positive control has measured everything except
--        whether the control can fail**, and A1 is the happy-path pin every other mutation
--        preserves by construction.
--   M10  the journal insert moved behind the early return
--                                  → **1405/2: `0202-A2` AND 225's `0194-B4`** — two
--        independently-written fixtures from two slices reaching the same verdict.
-- ═════════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

-- ── helpers, all `t_bdr_`-prefixed so nothing here collides with 225's or 226's ───────────────

-- ⚠ CALLS THE RPC EXACTLY ONCE. 225's note on this is inherited verbatim and is load-bearing
--   rather than tidy: a helper that did `select count(*)` and then `select *` would invoke
--   `ops_bank_account` TWICE and make A2's 「one read = one journal row」 read as two.
create or replace function t_bdr_ops_read(p_uid uuid, p_runner uuid) returns jsonb
language plpgsql as $$
declare v record; n int := 0; r jsonb := '{}'::jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  for v in select * from ops_bank_account(p_runner) loop
    n := n + 1;
    r := jsonb_build_object('bank', v.bank, 'label', v.bank_label, 'holder', v.holder,
                            'account', v.account,
                            'verified_null', (v.verified_at is null),
                            'updated_null',  (v.updated_at is null));
  end loop;
  return r || jsonb_build_object('rows', n);
exception when others then
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_bdr_set(p_uid uuid, p_bank text, p_account text, p_holder text)
returns jsonb language plpgsql as $$
declare v record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select * into v from set_my_bank_account(p_bank, p_account, p_holder);
  return jsonb_build_object('masked', v.account_masked);
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

-- the journal rows THIS suite's operator caused
create or replace function t_bdr_log(p_ops uuid) returns int language sql as $$
  select count(*)::int from bank_account_access_log where ops_profile_id = p_ops
$$;

create or replace function t_bdr_log_last(p_ops uuid) returns jsonb language sql as $$
  select jsonb_build_object('runner', l.runner_id, 'found', l.found)
    from bank_account_access_log l where l.ops_profile_id = p_ops
   order by l.at desc, l.ctid desc limit 1
$$;

create or replace function t_bdr_claim(p_owner uuid, p_item text, p_ms int, p_status claim_status)
returns uuid language sql as $$
  insert into gear_claims (profile_id, side, item, milestone, status)
  values (p_owner, 'runner', p_item, p_ms, p_status) returning id
$$;

-- the claim row as the TABLE holds it — the pins read this, never a function's answer
create or replace function t_bdr_row(p_claim uuid) returns jsonb language sql as $$
  select jsonb_build_object(
    'status', g.status::text, 'item', g.item, 'milestone', g.milestone,
    'claimed', (g.claimed_at is not null),
    'delivery', g.delivery, 'delivery_text', coalesce(g.delivery::text, ''),
    'delivery_null', (g.delivery is null),
    'carrier', g.delivery_carrier, 'tracking', g.delivery_tracking,
    'dispatched', (g.dispatched_at is not null))
  from gear_claims g where g.id = p_claim
$$;

create or replace function t_bdr_claim_as(p_uid uuid, p_claim uuid,
  p_recipient text, p_phone text, p_a1 text, p_a2 text, p_postal text) returns jsonb
language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select * into r from claim_gear_tx(p_claim, p_recipient, p_phone, p_a1, p_a2, p_postal);
  return jsonb_build_object('status', r.status, 'already', r.already_claimed);
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_bdr_pending_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select coalesce(jsonb_agg(jsonb_build_object('claim', claim_id, 'recipient', recipient,
           'phone', phone, 'address1', address1, 'address2', address2, 'postal', postal)
           order by claim_id), '[]'::jsonb)
    into v from ops_gear_claims_pending();
  return jsonb_build_object('rows', v);
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_bdr_ship_as(p_uid uuid, p_claim uuid, p_carrier text, p_tracking text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select * into r from ops_mark_gear_shipped(p_claim, p_carrier, p_tracking);
  return jsonb_build_object('status', r.status, 'carrier', r.carrier, 'tracking', r.tracking);
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

-- does an UPDATE to `delivery` land, or is it refused by the shape belt? Reported as a word so B5
-- can tell 「refused」 from 「accepted」 without the failure aborting the suite.
create or replace function t_bdr_try_delivery(p_claim uuid, p_val jsonb) returns text
language plpgsql as $$
begin
  update gear_claims set delivery = p_val where id = p_claim;
  return 'accepted';
exception when others then return 'refused';
end $$;

do $$
declare
  ops1     uuid;   -- an active `payout_due` operator
  rBank    uuid;   -- a runner with a registered bank account
  rNoBank  uuid;   -- a runner with no bank row at all
  rBad     uuid;   -- a runner whose ciphertext is unreadable
  rGone    uuid;   -- the runner who claims gear and then deletes their account
  rLive    uuid;   -- the control runner, who does not
  rOld     uuid;   -- an ALREADY-tombstoned runner, for the repair
  cGone    uuid;   -- rGone's claim
  cLive    uuid;   -- rLive's claim
  cOld     uuid;   -- rOld's claim, tombstoned the hard way
  cShipped uuid;   -- a `shipped` claim, for B3's ordering control
  cClaimbl uuid;   -- a `claimable` claim, for B3's ordering control
  cBelt    uuid;   -- B5's subject
  v        jsonb;
  v_row    jsonb;
  v_before jsonb;
  v_bad    text := '';
  v_msg    text;
  v_src    text;
  v_raw    text;
  v_n      int;
  v_b      int;
  v_a      int;
  v_oid    oid;
  v_word   text;
  v_ok     boolean;
  fn       text;
begin
  perform set_config('request.jwt.claim.sub', '', true);

  ops1    := t_user('bdr_ops',     'owner');
  rBank   := t_user('bdr_bank',    'runner');
  rNoBank := t_user('bdr_nobank',  'runner');
  rBad    := t_user('bdr_badenc',  'runner');
  rGone   := t_user('bdr_gone',    'runner');
  rLive   := t_user('bdr_live',    'runner');
  rOld    := t_user('bdr_old',     'runner');
  insert into ops_recipients (profile_id, event_class, active) values (ops1, 'payout_due', true);

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-A1] the answer is unchanged — the CONTROL for the whole of §A
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ This pin's entire job is to fail if collapsing three reads into one broke what the operator
  --   sees. It is NOT evidence about atomicity, and the header says so in as many words.
  v_bad := '';
  v := t_bdr_set(rBank, '004', '123-456-789012', '김예금');
  if v->>'raised' is not null then v_bad := v_bad || ' 계좌 등록이 거절됨: ' || (v->>'raised'); end if;

  v := t_bdr_ops_read(ops1, rBank);
  if v->>'raised' is not null then v_bad := v_bad || ' ops 읽기가 거절됨: ' || (v->>'raised');
  else
    if (v->>'rows')::int is distinct from 1 then v_bad := v_bad || ' 행 수=' || coalesce(v->>'rows','NULL'); end if;
    -- the CODE is stored, the LABEL is joined — two different facts, and swapping them is exactly
    -- what a careless single-statement rewrite would do
    if v->>'bank'    is distinct from '004'          then v_bad := v_bad || ' bank=' || coalesce(v->>'bank','NULL'); end if;
    if v->>'label'   is distinct from 'KB국민은행'   then v_bad := v_bad || ' label=' || coalesce(v->>'label','NULL'); end if;
    if v->>'holder'  is distinct from '김예금'       then v_bad := v_bad || ' holder=' || coalesce(v->>'holder','NULL'); end if;
    -- separators removed by the server, digits intact — the round trip through pgcrypto
    if v->>'account' is distinct from '123456789012' then v_bad := v_bad || ' account=' || coalesce(v->>'account','NULL'); end if;
    if (v->>'verified_null')::boolean is distinct from true  then v_bad := v_bad || ' verified_at 에 시각이 찍혔다(검증하는 것이 없는데)'; end if;
    if (v->>'updated_null')::boolean  is distinct from false then v_bad := v_bad || ' updated_at 이 비었다'; end if;
  end if;

  -- and every field agrees with the TABLE, which is the only way to see a rewrite that quietly
  -- started reading a different row
  select (b.bank = (v->>'bank') and b.holder = (v->>'holder')
          and (b.updated_at is not null) = ((v->>'updated_null')::boolean is false))
    into v_ok from bank_accounts b where b.runner_id = rBank;
  if v_ok is not true then v_bad := v_bad || ' 반환이 테이블 행과 다르다'; end if;

  -- a runner with no row at all: zero rows, no raise
  v := t_bdr_ops_read(ops1, rNoBank);
  if v->>'raised' is not null then v_bad := v_bad || ' 계좌 없는 러너에 예외: ' || (v->>'raised'); end if;
  if (v->>'rows')::int is distinct from 0 then v_bad := v_bad || ' 계좌 없는 러너에 행=' || coalesce(v->>'rows','NULL'); end if;

  if v_bad = '' then call _pass('bdr','0202-A1 ops_bank_account 의 답은 0194 §F④ 그대로다: 은행 **코드**와 조인된 라벨, 예금주, 구분자만 뺀 전체 번호, verified_at 은 NULL, updated_at 은 있음 — 그리고 네 칸이 테이블 행과 일치한다; 계좌가 없는 러너는 예외가 아니라 0행. ⚠ 이 핀은 §A 의 **대조**이지 원자성의 증거가 아니다 — 읽기 셋을 하나로 합치면서 답이 깨졌는지를 잡는 것이 전부다');
  else v_msg := v_bad; call _fail('bdr','0202-A1 the ops answer is unchanged', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-A2] 0194 §D's journal survives the rewrite — measured as a DELTA, never as a count
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- A count read off an already-populated table is a fact about the fixture, not about this call.
  v_bad := '';
  v_b := t_bdr_log(ops1);
  v := t_bdr_ops_read(ops1, rBank);
  v_a := t_bdr_log(ops1);
  if (v_a - v_b) is distinct from 1 then v_bad := v_bad || ' 읽기 한 번에 장부 ' || (v_a - v_b) || '행'; end if;
  v_row := t_bdr_log_last(ops1);
  if (v_row->>'runner')::uuid is distinct from rBank then v_bad := v_bad || ' 장부 행이 다른 러너를 가리킨다'; end if;
  if (v_row->>'found')::boolean is distinct from true then v_bad := v_bad || ' found=true 가 아니다'; end if;

  -- probing for existence IS access: a runner with no row still leaves a line, with found=false
  v_b := t_bdr_log(ops1);
  v := t_bdr_ops_read(ops1, rNoBank);
  v_a := t_bdr_log(ops1);
  if (v_a - v_b) is distinct from 1 then v_bad := v_bad || ' 계좌 없는 러너 조회에 장부 ' || (v_a - v_b) || '행'; end if;
  v_row := t_bdr_log_last(ops1);
  if (v_row->>'found')::boolean is distinct from false then v_bad := v_bad || ' 못 찾은 조회가 found=true 로 남았다'; end if;

  -- 🔴 THE ARM THAT MATTERS. An unreadable ciphertext must be REPORTED IN THE ROW, not raised: a
  --    raise rolls back its own journal line inside PostgREST's per-request transaction, so the
  --    least auditable call would be the only one leaving no audit — and it would be a usable
  --    existence probe. The readable fields still come back; `account` is ABSENT, not partial.
  v := t_bdr_set(rBad, '088', '9876543210', '박예금');
  if v->>'raised' is not null then v_bad := v_bad || ' rBad 계좌 등록이 거절됨: ' || (v->>'raised'); end if;
  update bank_accounts set account_enc = 'NOT-CIPHERTEXT' where runner_id = rBad;
  v_b := t_bdr_log(ops1);
  v := t_bdr_ops_read(ops1, rBad);
  v_a := t_bdr_log(ops1);
  if v->>'raised' is not null then v_bad := v_bad || ' 🔴 못 읽는 암호문에 예외를 던졌다: ' || (v->>'raised'); end if;
  if (v_a - v_b) is distinct from 1 then v_bad := v_bad || ' 🔴 못 읽는 암호문 조회의 장부 행이 ' || (v_a - v_b) || ' 이다 — 예외가 자기 장부를 롤백했다'; end if;
  if (v->>'rows')::int is distinct from 1 then v_bad := v_bad || ' 못 읽는 행이 0행으로 사라졌다(부재와 구분이 안 된다)'; end if;
  if v->>'account' is not null then v_bad := v_bad || ' 못 읽는 번호가 NULL 이 아니라 ' || (v->>'account'); end if;
  if v->>'holder'  is distinct from '박예금' then v_bad := v_bad || ' 읽히는 칸(예금주)까지 사라졌다'; end if;

  if v_bad = '' then call _pass('bdr','0202-A2 0194 §D 의 장부가 재작성을 그대로 통과한다: 게이트를 지난 호출 한 번 = 장부 정확히 한 행(호출 전후 **델타**로 잰다 — 이미 찬 테이블에서 읽은 개수는 픽스처에 대한 사실이다), 그 행은 이 러너를 이름으로 갖는다; 계좌 없는 러너를 떠봐도 found=false 로 한 행 남는다(존재 여부를 떠보는 것도 접근이다); 🔴 그리고 **못 읽는 암호문** — 예외 없이 account=NULL 로 보고하고 장부 행을 남긴다. 예외를 던지면 같은 트랜잭션의 장부 행이 함께 롤백돼, 가장 감사돼야 할 호출이 흔적을 안 남기는 유일한 호출이 된다; 읽히는 칸(예금주)은 그대로 온다');
  else v_msg := v_bad; call _fail('bdr','0202-A2 the journal survives the rewrite', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-A3] 🔴 THE FIX — one statement holds the whole answer (SOURCE; see the header)
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- Comments are STRIPPED before every match. `prosrc` is source PLUS our own prose, and 0202 §A③
  -- explains this exact guard inside the function's own body — un-stripped, the paragraph
  -- EXPLAINING the capture would satisfy a check for the capture, and the better the explanation
  -- the surer the false green.
  v_bad := '';
  v_oid := to_regprocedure('ops_bank_account(uuid)');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_bank_account)';
  else
    select prosrc, regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g')
      into v_raw, v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_bank_account)';
    else
      -- the count IS the property: three reads is the defect, one read is the fix. Literal string
      -- arithmetic rather than a regex — nothing here depends on escaping correctly.
      v_n := (length(v_src) - length(replace(v_src, 'from bank_accounts', ''))) / length('from bank_accounts');
      if v_n is distinct from 1
        then v_bad := v_bad || ' 🔴 bank_accounts 를 읽는 문장이 ' || v_n || '개다(1이어야 한다 — Codex Finding 3)'; end if;
      -- and the decrypt is fed the CAPTURED ciphertext, not a runner id it would look up again
      if (position('_bank_account_plain_enc(v_enc)' in v_src) > 0) is not true
        then v_bad := v_bad || ' 🔴 복호화가 붙잡아 둔 암호문이 아니라 다른 것을 받는다'; end if;
      if (position('_bank_account_plain(p_runner)' in v_src) > 0) is not false
        then v_bad := v_bad || ' 🔴 러너 id 로 행을 다시 읽는 옛 복호화가 돌아왔다'; end if;
      -- 0194's order, restated here so this file's own edit cannot quietly move it
      if (position('ops_recipients_for' in v_src) > 0
          and position('ops_recipients_for' in v_src) < position('bank_account_access_log' in v_src)
          and position('bank_account_access_log' in v_src) < position('_bank_account_plain' in v_src))
         is not true
        then v_bad := v_bad || ' 순서가 게이트 → 장부 → 복호화가 아니다'; end if;
      -- the raw>stripped control: proof the strip is load-bearing rather than decorative
      if (length(v_raw) > length(v_src)) is not true
        then v_bad := v_bad || ' 주석 제거가 아무것도 지우지 않았다(스트립이 무의미하다는 뜻)'; end if;
    end if;
  end if;

  v_oid := to_regprocedure('_bank_account_plain_enc(text)');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_bank_account_plain_enc)';
  else
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_bank_account_plain_enc)';
    else
      -- the helper's whole reason to exist: it takes ciphertext and touches no row
      if (position('bank_accounts' in v_src) > 0) is not false
        then v_bad := v_bad || ' 🔴 복호화 헬퍼가 테이블을 읽는다 — 읽기와 복호화를 떼어 놓은 것이 이 슬라이스다'; end if;
      if (position('pgp_sym_decrypt' in v_src) > 0) is not true
        then v_bad := v_bad || ' 복호화 헬퍼가 복호화를 안 한다'; end if;
    end if;
  end if;

  if v_bad = '' then call _pass('bdr','0202-A3 🔴 고침 자체: ops_bank_account 의 본문(주석 제거)이 bank_accounts 를 **정확히 한 문장**에서 읽고, 그 문장이 붙잡은 암호문을 그대로 복호화한다(_bank_account_plain_enc(v_enc)) — 러너 id 로 행을 다시 읽던 옛 경로는 없다; 복호화 헬퍼는 테이블을 아예 읽지 않는다; 0194 의 순서(게이트 → 장부 → 복호화)는 그대로. ⚠ 소스로만 잡는다 — 하네스는 한 세션이라 찢어진 읽기를 만들 두 번째 커밋이 없고, 그 한계는 이 파일 머리말에 산문으로 적혀 있다(핀으로 쓰면 무조건 초록인 팔이 된다)');
  else v_msg := v_bad; call _fail('bdr','0202-A3 one statement holds the whole answer', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-A4] the PRECONDITION the fix reasons from — and the helper's own shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- 🔴 A battery that only attacks what a guard DOES will always miss what the guard READS. The
  --    single capture is necessary BECAUSE `ops_bank_account` is VOLATILE (fresh snapshot per
  --    statement), and `my_bank_account` is left alone BECAUSE it is STABLE (one snapshot for the
  --    whole body). Those two markings are the premises of 0202 §0a, so they are measured.
  v_bad := '';
  if (select provolatile from pg_proc where oid = to_regprocedure('ops_bank_account(uuid)'))
     is distinct from 'v'
    then v_bad := v_bad || ' 🔴 ops_bank_account 가 VOLATILE 이 아니다 — 0202 §0a 의 전제가 무너진다'; end if;
  if (select provolatile from pg_proc where oid = to_regprocedure('my_bank_account()'))
     is distinct from 's'
    then v_bad := v_bad || ' 🔴 my_bank_account 가 STABLE 이 아니다 — 손대지 않은 이유가 바로 그것이었다'; end if;
  if (select provolatile from pg_proc where oid = to_regprocedure('_bank_account_plain_enc(text)'))
     is distinct from 's'
    then v_bad := v_bad || ' _bank_account_plain_enc 가 STABLE 이 아니다'; end if;

  foreach fn in array array['_bank_account_plain(uuid)', '_bank_account_plain_enc(text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    -- 🔴 `service_role` IS IN THIS LIST. `00_shim.sql:132-135` models production by granting
    --    EXECUTE on public functions to service_role by default (0129:105-120 measured that ACL),
    --    so a check of anon/authenticated alone CANNOT SEE a PostgREST-reachable plaintext oracle.
    if has_function_privilege('anon',          v_oid, 'EXECUTE') is not false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
    or has_function_privilege('service_role',  v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ' 를 클라이언트 롤이 실행할 수 있다'; end if;
    -- a definer that returns plaintext is one bad grant away from being a plaintext oracle
    if (select prosecdef from pg_proc where oid = v_oid) is not false
      then v_bad := v_bad || ' ' || fn || ' 가 definer 다(아니어야 한다)'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '')
          = 'search_path=public, extensions, pg_temp' from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ' 의 본문 search_path 가 0194 §0a 의 것이 아니다'; end if;
  end loop;

  if v_bad = '' then call _pass('bdr','0202-A4 고침이 딛고 선 **전제**를 잰다(가드가 하는 일만이 아니라 가드가 읽는 것을 공격하라): ops_bank_account 는 VOLATILE 이어야 하고(장부 INSERT 때문에 그래야 한다 — 그래서 문장마다 새 스냅샷이고, 그래서 읽기 셋이 찢어진 읽기였다), my_bank_account 는 STABLE 이어야 한다(그래서 손대지 않았다). 새 복호화 헬퍼와 0194 의 헬퍼는 definer 가 **아니고**, anon·authenticated·**service_role** 어느 쪽도 실행할 수 없으며(service_role 은 00_shim 이 기본 grant 를 주므로 이 이름이 없으면 PostgREST 로 닿는 평문 오라클이 남는다), 본문 search_path 는 0194 §0a 의 public, extensions, pg_temp 다');
  else v_msg := v_bad; call _fail('bdr','0202-A4 the precondition and the helper shape', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-B1] 🔴 claim → account deletion → the destination is gone, the record is not
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  cGone := t_bdr_claim(rGone, 'bdr 탈퇴자 후디', 5,  'claimable');
  cLive := t_bdr_claim(rLive, 'bdr 현역 캡',     15, 'claimable');
  v := t_bdr_claim_as(rGone, cGone, '최탈퇴', '010-2222-3333', '서울시 마포구 월드컵로 7', '302호', '03925');
  if v->>'raised' is not null then v_bad := v_bad || ' 탈퇴 예정자의 신청이 거절됨: ' || (v->>'raised'); end if;
  v := t_bdr_claim_as(rLive, cLive, '정현역', '010-4444-5555', '서울시 성동구 왕십리로 8', null, '04766');
  if v->>'raised' is not null then v_bad := v_bad || ' 대조 러너의 신청이 거절됨: ' || (v->>'raised'); end if;

  -- the fixture must CONTAIN the defect before the fix can be said to close it: all five fields
  -- are really there, and the control's row is captured byte-for-byte for comparison afterwards
  v_row := t_bdr_row(cGone);
  if (v_row->'delivery'->>'recipient') is distinct from '최탈퇴'
    then v_bad := v_bad || ' 픽스처: 지우기 전에 배송지가 없다 — 이 핀은 빈 세계에서의 부재를 재고 있다'; end if;
  v_before := t_bdr_row(cLive);

  perform set_config('request.jwt.claim.sub', '', true);
  perform delete_my_account_tx(rGone);

  v_row := t_bdr_row(cGone);
  -- asserted as the ABSENCE of each typed string ANYWHERE in the jsonb, not as a changed field: a
  -- redaction that moved the phone to a sixth key would pass a field-by-field check
  foreach v_word in array array['최탈퇴', '01022223333', '서울시 마포구 월드컵로 7', '302호', '03925'] loop
    if position(v_word in (v_row->>'delivery_text')) > 0
      then v_bad := v_bad || ' 🔴 탈퇴 뒤에도 배송지에 「' || v_word || '」 가 남아 있다'; end if;
  end loop;
  if (v_row->'delivery') is distinct from '{"redacted": true}'::jsonb
    then v_bad := v_bad || ' 🔴 지움 표식이 정확히 {"redacted": true} 가 아니다: ' || coalesce(v_row->>'delivery_text','NULL'); end if;
  -- and the FULFILMENT RECORD survives — that is what 0115 §B.3 keeps gear_claims FOR
  if v_row->>'status'  is distinct from 'claimed'          then v_bad := v_bad || ' 이행 기록이 깨졌다: status=' || coalesce(v_row->>'status','NULL'); end if;
  if (v_row->>'claimed')::boolean is distinct from true    then v_bad := v_bad || ' claimed_at 이 지워졌다'; end if;
  if v_row->>'item'    is distinct from 'bdr 탈퇴자 후디'  then v_bad := v_bad || ' 품목이 지워졌다'; end if;
  if (v_row->>'milestone')::int is distinct from 5         then v_bad := v_bad || ' 마일스톤이 지워졌다'; end if;
  -- CONTROL: the live runner's claim is untouched. Without it, 「redact everything」 passes above.
  if t_bdr_row(cLive) is distinct from v_before
    then v_bad := v_bad || ' 🔴 대조: 남의 탈퇴가 현역 러너의 배송지를 건드렸다'; end if;

  if v_bad = '' then call _pass('bdr','0202-B1 🔴 수령 신청 → 탈퇴 → **행선지는 사라지고 이행 기록은 남는다**: 다섯 칸(이름·전화·주소1·주소2·우편번호)의 글자가 jsonb 어디에도 없고 — 칸별 비교가 아니라 **문자열 부재**로 잰다, 여섯 번째 키로 옮긴 「지움」은 칸별 검사를 통과하므로 — 값은 정확히 {"redacted": true} 다; status·claimed_at·품목·마일스톤은 그대로다(0115 §B.3 이 gear_claims 를 남기는 이유가 그 기록이다). 픽스처가 지우기 **전에** 다섯 칸을 실제로 들고 있었음을 먼저 단언한다(빈 세계의 부재는 아무것도 증명하지 않는다). 대조: 현역 러너의 행은 바이트 그대로다');
  else v_msg := v_bad; call _fail('bdr','0202-B1 the destination leaves with the account', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-B2] the ops queue stops handing it out
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_bdr_pending_as(ops1);
  if v->>'raised' is not null then v_bad := v_bad || ' ops 목록이 거절됨: ' || (v->>'raised');
  else
    if (select count(*) from jsonb_array_elements(v->'rows') e
         where (e->>'claim')::uuid = cGone) <> 0
      then v_bad := v_bad || ' 🔴 지워진 신청이 아직 발송 대기 목록에 있다'; end if;
    -- no field of it survives anywhere in the payload either
    foreach v_word in array array['최탈퇴', '01022223333', '서울시 마포구 월드컵로 7', '03925'] loop
      if position(v_word in (v->'rows')::text) > 0
        then v_bad := v_bad || ' 🔴 ops 목록 전체에 「' || v_word || '」 가 실려 있다'; end if;
    end loop;
    -- 🔴 THE CONTROL. Without it this pin is green on a function that returns nothing at all.
    if (select count(*) from jsonb_array_elements(v->'rows') e
         where (e->>'claim')::uuid = cLive) <> 1
      then v_bad := v_bad || ' 🔴 대조: 현역 러너의 신청이 목록에서 사라졌다'; end if;
    if (select e->>'recipient' from jsonb_array_elements(v->'rows') e
         where (e->>'claim')::uuid = cLive) is distinct from '정현역'
      then v_bad := v_bad || ' 대조: 현역 러너의 받는사람이 안 실렸다'; end if;
    if (select e->>'postal' from jsonb_array_elements(v->'rows') e
         where (e->>'claim')::uuid = cLive) is distinct from '04766'
      then v_bad := v_bad || ' 대조: 현역 러너의 우편번호가 안 실렸다'; end if;
  end if;

  if v_bad = '' then call _pass('bdr','0202-B2 ops_gear_claims_pending 이 지워진 배송지를 더 이상 내주지 않는다 — 그 신청 id 도, 다섯 칸의 글자 어느 것도 응답 전체에 없다. 🔴 **대조가 절반이다**: 같은 호출에서 현역 러너의 신청은 받는사람·우편번호까지 그대로 나온다 — 대조가 없으면 이 핀은 아무것도 안 돌려주는 함수에서도 초록이다. 부칠 곳이 없는 행을 큐에 남기는 것은 아무도 실행할 수 없는 일을 매일 보여 주는 것이고, 0115:455-467 의 운영 답도 이미 「주소를 쫓지 말고 신청을 취소하라」였다');
  else v_msg := v_bad; call _fail('bdr','0202-B2 the ops queue excludes redacted claims', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-B3] a redacted claim is not shippable — by NAME, and writing nothing
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v_before := t_bdr_row(cGone);
  v := t_bdr_ship_as(ops1, cGone, 'CJ대한통운', '1234567890');
  if v->>'raised' is distinct from 'claim_redacted'
    then v_bad := v_bad || ' 🔴 지워진 신청의 발송 처리가 claim_redacted 가 아니다: ' || coalesce(v->>'raised', 'ACCEPTED(' || coalesce(v->>'status','?') || ')'); end if;
  v_row := t_bdr_row(cGone);
  if v_row is distinct from v_before
    then v_bad := v_bad || ' 🔴 거절된 발송이 행을 건드렸다'; end if;
  if v_row->>'status' is distinct from 'claimed' then v_bad := v_bad || ' 상태가 움직였다'; end if;
  if v_row->>'carrier'  is not null              then v_bad := v_bad || ' 택배사가 적혔다'; end if;
  if v_row->>'tracking' is not null              then v_bad := v_bad || ' 송장이 적혔다'; end if;
  if (v_row->>'dispatched')::boolean is distinct from false then v_bad := v_bad || ' 일어나지 않은 발송의 시각이 찍혔다'; end if;

  -- 🔴 CONTROL: the live claim still ships. Without it, 「refuse everything」 satisfies the arm above.
  v := t_bdr_ship_as(ops1, cLive, 'CJ대한통운', '9999000011');
  if v->>'raised' is not null then v_bad := v_bad || ' 🔴 대조: 멀쩡한 신청도 거절됐다: ' || (v->>'raised'); end if;
  if v->>'status' is distinct from 'shipped' then v_bad := v_bad || ' 대조: 멀쩡한 신청이 발송되지 않았다'; end if;

  -- and the NEW gate did not displace the two that were already there (0195 §D's order)
  cShipped := t_bdr_claim(rLive, 'bdr 이미 발송', 25, 'shipped');
  cClaimbl := t_bdr_claim(rLive, 'bdr 아직 신청 전', 35, 'claimable');
  v := t_bdr_ship_as(ops1, cShipped, 'CJ대한통운', '1');
  if v->>'raised' is distinct from 'already_shipped'
    then v_bad := v_bad || ' shipped 행이 already_shipped 가 아니다: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_bdr_ship_as(ops1, cClaimbl, 'CJ대한통운', '1');
  if v->>'raised' is distinct from 'not_claimed'
    then v_bad := v_bad || ' claimable 행이 not_claimed 가 아니다: ' || coalesce(v->>'raised','ACCEPTED'); end if;

  if v_bad = '' then call _pass('bdr','0202-B3 지워진 배송지는 발송 처리할 수 없다 — **claim_redacted** 로 이름을 갖고 거절하며(보낼 곳이 없는데 송장을 적으면 일어나지 않은 발송이 기록으로 남는다) 행은 바이트 그대로다: 상태도 택배사도 송장도 발송 시각도 움직이지 않는다. 🔴 대조: 멀쩡한 신청은 그대로 발송된다(없으면 「전부 거절」이 위 팔을 통과한다). 그리고 새 게이트가 기존 둘을 밀어내지 않았다 — shipped 는 여전히 already_shipped(그 상자는 계정보다 먼저 떠났다), claimable 은 여전히 not_claimed');
  else v_msg := v_bad; call _fail('bdr','0202-B3 a redacted claim is not shippable', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-B4] the one-time repair, and its control
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- The state this repair exists for cannot arise from `delete_my_account_tx` any more, so it is
  -- manufactured the only honest way: a snapshot written first, the tombstone stamped afterwards.
  -- ⚠ This is why §B⑤ is a NAMED FUNCTION and not a `do` block (0202 §0e) — a block that touches
  --   zero rows at apply time could only ever be described in prose.
  v_bad := '';
  cOld  := t_bdr_claim(rOld, 'bdr 예전 탈퇴자', 45, 'claimable');
  v := t_bdr_claim_as(rOld, cOld, '한예전', '010-7777-6666', '인천시 연수구 컨벤시아대로 9', null, '21998');
  if v->>'raised' is not null then v_bad := v_bad || ' 픽스처: 예전 탈퇴자의 신청이 거절됨: ' || (v->>'raised'); end if;
  perform set_config('request.jwt.claim.sub', '', true);
  -- the tombstone WITHOUT the redaction — exactly the world 0195 would have left behind
  update profiles set deleted_at = now() where id = rOld;
  if (t_bdr_row(cOld)->'delivery'->>'recipient') is distinct from '한예전'
    then v_bad := v_bad || ' 픽스처: 고치기 전에 배송지가 이미 없다 — 이 핀은 빈 세계를 재고 있다'; end if;

  v_before := t_bdr_row(cLive);
  -- ⚠ The number is a DELTA THIS CALL CAUSED, not a state it found. The candidate set is counted
  --   first — and asserted to be exactly this suite's one row, so a stray candidate left by
  --   another suite names itself here rather than silently moving the number below.
  select count(*)::int into v_b from gear_claims g join profiles p on p.id = g.profile_id
   where p.deleted_at is not null and g.delivery is not null
     and coalesce(g.delivery ? 'redacted', false) is not true;
  if v_b is distinct from 1
    then v_bad := v_bad || ' 픽스처: 툼스톤 뒤에 남은 배송지가 ' || coalesce(v_b::text,'NULL') || '개다(이 스위트가 만든 1개여야 한다)'; end if;
  v_n := _gear_redact_tombstoned_deliveries();
  if v_n is distinct from v_b then v_bad := v_bad || ' 수리가 고친 행 수=' || coalesce(v_n::text,'NULL') || ' (후보 ' || coalesce(v_b::text,'NULL') || '개와 달랐다)'; end if;
  select count(*)::int into v_a from gear_claims g join profiles p on p.id = g.profile_id
   where p.deleted_at is not null and g.delivery is not null
     and coalesce(g.delivery ? 'redacted', false) is not true;
  if v_a is distinct from 0 then v_bad := v_bad || ' 🔴 수리 뒤에도 툼스톤 뒤에 배송지가 ' || coalesce(v_a::text,'NULL') || '개 남았다'; end if;
  v_row := t_bdr_row(cOld);
  if (v_row->'delivery') is distinct from '{"redacted": true}'::jsonb
    then v_bad := v_bad || ' 🔴 예전 탈퇴자의 배송지가 안 지워졌다: ' || coalesce(v_row->>'delivery_text','NULL'); end if;
  if v_row->>'status' is distinct from 'claimed' then v_bad := v_bad || ' 수리가 이행 기록까지 건드렸다'; end if;
  -- 🔴 THE CONTROL, and it is the arm the `deleted_at is not null` conjunct exists for.
  if t_bdr_row(cLive) is distinct from v_before
    then v_bad := v_bad || ' 🔴 대조: 수리가 **살아 있는 러너**의 배송지를 지웠다'; end if;
  -- idempotent: a second call finds nothing left to do
  v_n := _gear_redact_tombstoned_deliveries();
  if v_n is distinct from 0 then v_bad := v_bad || ' 두 번째 호출이 ' || coalesce(v_n::text,'NULL') || '행을 또 고쳤다(멱등이 아니다)'; end if;

  if v_bad = '' then call _pass('bdr','0202-B4 일회성 수리: 이미 툼스톤이 찍힌 프로필 뒤에 남아 있던 배송지 스냅샷을 지우고 고친 행 수를 돌려준다(1); 이행 기록은 안 건드리고, 두 번째 호출은 0이다(멱등). 🔴 **대조가 이 핀의 전부다** — 살아 있는 러너의 행은 바이트 그대로여야 하고, 그것이 deleted_at is not null 절이 존재하는 이유다. 픽스처는 고치기 전에 다섯 칸을 실제로 들고 있다(0195 를 적용하고 이 파일을 적용하지 않은 세계 그대로). 운영 DB 에서는 공집합이지만(0195 가 배포된 적이 없다) 스테이징에서는 아니다');
  else v_msg := v_bad; call _fail('bdr','0202-B4 the one-time repair', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-B5] the shape belt — widened by EXACTLY one value, not by a shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  cBelt := t_bdr_claim(rLive, 'bdr 제약 검증', 55, 'claimable');
  if t_bdr_try_delivery(cBelt, null)                                is distinct from 'accepted' then v_bad := v_bad || ' NULL 배송지가 거절됐다(오늘의 모든 행이 그렇다)'; end if;
  if t_bdr_try_delivery(cBelt, '{"recipient":"가","phone":"01011112222","address1":"어딘가 1","address2":null,"postal":"01234"}'::jsonb)
                                                                    is distinct from 'accepted' then v_bad := v_bad || ' 부칠 수 있는 주소가 거절됐다'; end if;
  if t_bdr_try_delivery(cBelt, '{"redacted": true}'::jsonb)         is distinct from 'accepted' then v_bad := v_bad || ' 🔴 지움 표식이 거절됐다'; end if;
  -- 0195's arm, intact: a payload that cannot be posted is still refused
  if t_bdr_try_delivery(cBelt, '{"recipient":"","phone":"01011112222","address1":"어딘가 1","postal":"01234"}'::jsonb)
                                                                    is distinct from 'refused'  then v_bad := v_bad || ' 받는사람이 빈 주소가 받아들여졌다'; end if;
  if t_bdr_try_delivery(cBelt, '{"recipient":"가","phone":"01011112222","address1":"어딘가 1","postal":"12"}'::jsonb)
                                                                    is distinct from 'refused'  then v_bad := v_bad || ' 우편번호가 5자리가 아닌 주소가 받아들여졌다'; end if;
  -- 🔴 THE ARM THAT MAKES THIS AN EQUALITY AND NOT A SHAPE. A marker with a sixth key beside it
  --    would be a redaction that still carries a phone number.
  if t_bdr_try_delivery(cBelt, '{"redacted": true, "phone": "01011112222"}'::jsonb)
                                                                    is distinct from 'refused'  then v_bad := v_bad || ' 🔴 지움 표식 옆에 여섯 번째 칸이 끼어들 수 있다 — 등호가 아니라 모양으로 받고 있다'; end if;
  if t_bdr_try_delivery(cBelt, '{"redacted": false}'::jsonb)        is distinct from 'refused'  then v_bad := v_bad || ' redacted:false 라는 값이 받아들여졌다(표식은 값 하나다)'; end if;
  -- leave the subject in a state that says nothing to anyone else
  perform t_bdr_try_delivery(cBelt, null);

  if v_bad = '' then call _pass('bdr','0202-B5 형상 벨트는 **값 하나만큼** 넓어졌다: NULL 허용(오늘의 모든 행), 부칠 수 있는 다섯 칸 허용, 정확히 ''{"redacted": true}'' 허용 — 그리고 0195 의 팔은 그대로다(받는사람이 비거나 우편번호가 5자리가 아니면 거절). 🔴 결정적인 팔: **지움 표식 옆에 여섯 번째 칸이 붙은 값은 거절된다** — 모양으로 받으면 「지웠다」고 적힌 행이 전화번호를 계속 들고 있을 수 있다. redacted:false 도 거절(표식은 모양이 아니라 값 하나다)');
  else v_msg := v_bad; call _fail('bdr','0202-B5 the shape belt admits exactly one value', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0202-S1] deployed shape — what A1…B5 cannot see, and what §C only sees at apply time
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ 0202 §C VERIFY and this pin are DIFFERENT ARTIFACTS and neither is evidence for the other:
  --   §C aborts a production apply that lands wrong; this reddens when a LATER file undoes
  --   something. A property checked only at apply is protected exactly until someone recreates the
  --   function (0131-G4).
  v_bad := '';
  foreach fn in array array['ops_bank_account(uuid)', 'ops_gear_claims_pending()',
                            'ops_mark_gear_shipped(uuid,text,text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ' 가 definer 가 아니다'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public'
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ' 에 본문 search_path 가 없다'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is not false
    or has_function_privilege('anon',   v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ' 를 public/anon 이 실행할 수 있다'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ' 를 authenticated 가 실행할 수 없다(운영자가 못 부른다)'; end if;
  end loop;

  -- the two gear definers each still gate on the roster BEFORE the row read, and each carries the
  -- redaction arm this slice added
  foreach fn in array array['ops_gear_claims_pending()', 'ops_mark_gear_shipped(uuid,text,text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then continue; end if;
    select prosrc, regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g')
      into v_raw, v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')';
    else
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
        then v_bad := v_bad || ' ' || fn || ' 가 0084 로스터를 안 읽는다'; end if;
      if (position('raise exception ''not_ops''' in v_src) > 0
          and position('raise exception ''not_ops''' in v_src) < position('from gear_claims' in v_src))
         is not true
        then v_bad := v_bad || ' ' || fn || ' 의 ops 게이트가 행 읽기보다 뒤다'; end if;
      if (position('redacted' in v_src) > 0) is not true
        then v_bad := v_bad || ' ' || fn || ' 에 지움 처리 팔이 없다'; end if;
      if (length(v_raw) > length(v_src)) is not true
        then v_bad := v_bad || ' ' || fn || ': 주석 제거가 아무것도 지우지 않았다'; end if;
    end if;
  end loop;
  -- the refusal exists by NAME, and it is a raise rather than a flat field
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_mark_gear_shipped(uuid,text,text)');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_mark_gear_shipped)';
  elsif (position('raise exception ''claim_redacted''' in v_src) > 0) is not true
    then v_bad := v_bad || ' claim_redacted 가 이름 있는 거절로 없다'; end if;

  -- `delete_my_account_tx` — the catalog copy carried everything forward
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx)';
  else
    if (position('update gear_claims set delivery' in v_src) > 0) is not true
      then v_bad := v_bad || ' 🔴 탈퇴 트랜잭션에 배송지 지우기가 없다'; end if;
    -- inside the ANONYMISE stage, beside the addresses redaction it rides with — not after the
    -- deletes, where a FK cascade could already have moved the row
    if (position('update addresses set' in v_src) > 0
        and position('update addresses set' in v_src) < position('update gear_claims set delivery' in v_src))
       is not true
      then v_bad := v_bad || ' 배송지 지우기가 익명화 단계 안에 있지 않다'; end if;
    -- the three inherited landings. A copy taken from a body that had lost one would ship the loss
    -- under this file's name, which is why 0191 §0b made counting the rule.
    if (position('enqueue_billing_key_revocation(p_uid, ''account_deleted'')' in v_src) > 0) is not true
      then v_bad := v_bad || ' 0138 §F 의 결제키 폐기 큐가 복사 중에 사라졌다'; end if;
    if (position('where runner_id = p_uid and paid_payout_id is null' in v_src) > 0) is not true
      then v_bad := v_bad || ' 0190 §B 의 보관 술어가 복사 중에 사라졌다'; end if;
    v_n := (length(v_src) - length(replace(v_src, 'using detail = coalesce(v_block_id::text, '''')', '')))
           / length('using detail = coalesce(v_block_id::text, '''')');
    if v_n is distinct from 9
      then v_bad := v_bad || ' 0191 §A 의 detail 팔이 ' || v_n || '개다(9여야 한다)'; end if;
  end if;
  if (select prosecdef from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       and ns.nspname = 'public' where p.proname = 'delete_my_account_tx') is not true
    then v_bad := v_bad || ' delete_my_account_tx 가 definer 가 아니다'; end if;
  if (select 'search_path=public, pg_temp' = any(p.proconfig) from pg_proc p
       join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
      where p.proname = 'delete_my_account_tx') is not true
    then v_bad := v_bad || ' delete_my_account_tx 에 본문 search_path 가 없다'; end if;
  if has_function_privilege('anon', 'delete_my_account_tx(uuid)', 'EXECUTE') is not false
  or has_function_privilege('authenticated', 'delete_my_account_tx(uuid)', 'EXECUTE') is not false
    then v_bad := v_bad || ' delete_my_account_tx 를 클라이언트 롤이 실행할 수 있다'; end if;

  -- the repair helper's tombstone predicate — the conjunct B4's control exists for
  v_oid := to_regprocedure('_gear_redact_tombstoned_deliveries()');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_gear_redact_tombstoned_deliveries)';
  else
    if has_function_privilege('anon',          v_oid, 'EXECUTE') is not false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
    or has_function_privilege('service_role',  v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' 수리 함수를 클라이언트 롤이 실행할 수 있다'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_gear_redact_tombstoned_deliveries)';
    elsif (position('deleted_at is not null' in v_src) > 0) is not true
      then v_bad := v_bad || ' 수리 함수에 툼스톤 술어가 없다 — 살아 있는 러너까지 지운다'; end if;
  end if;

  -- the belt itself is still on the table
  if (select exists (select 1 from pg_constraint where conrelid = 'gear_claims'::regclass
                      and conname = 'gear_claims_delivery_shape')) is not true
    then v_bad := v_bad || ' delivery 형상 제약이 테이블에서 사라졌다'; end if;

  if v_bad = '' then call _pass('bdr','0202-S1 배포 형상: 재선언한 definer 셋의 prosecdef·본문 search_path·값으로 본 ACL 양방향(public/anon 불가, authenticated 가능 — 운영자가 PostgREST 로 부른다); 두 gear definer 는 여전히 0084 로스터를 행 읽기보다 먼저 통과하고 각자 지움 처리 팔을 갖는다; claim_redacted 는 이름 있는 raise 다; delete_my_account_tx 는 **카탈로그 복사**가 전부를 들고 왔다 — 배송지 지우기가 익명화 단계 안(주소 익명화 바로 옆)에 있고, 0138 §F 의 폐기 큐·0190 §B 의 보관 술어·0191 §A 의 detail 팔 **정확히 9개**가 살아 있다; 수리 함수의 툼스톤 술어와 ACL; 형상 제약 존재. 모든 소스 팔은 주석을 벗기고 읽으며 NO-SOURCE 짝과 raw>stripped 대조를 갖는다');
  else v_msg := v_bad; call _fail('bdr','0202-S1 deployed shape', v_msg); end if;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
