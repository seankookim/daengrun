-- ═══ 226 — 0195: 굿즈 수령, the claim chip becomes a door ══════════════════════════════════════
-- ═══        0195-C1…C5 · P1…P3 · S1, tag `gcl`                                            ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a
-- pin written while staring at a mutation tends to assert what that mutation broke rather than
-- the property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · C1 An owner claiming their own `claimable` row gets `claimed`, a `claimed_at`, and the
--        FIVE shipping fields stored on the row — read back from the TABLE, not from the return.
--        `already_claimed` is false, and the phone is stored as digits.
--   · C2 **PARTY BEFORE STATE.** A stranger naming someone else's claim id is refused
--        `not_claim_owner` and learns NOTHING about that claim's state — the same refusal word
--        for a `claimable`, a `locked` and a `claimed` row, and nothing is written in any of the
--        three. A caller with no subject at all gets `not_signed_in`.
--   · C3 **IDEMPOTENCY.** A second claim by the same owner on the same row returns
--        `already_claimed = true`, raises nothing, and changes NOTHING — not the status, not the
--        `claimed_at` timestamp, not the stored address (a second call carrying a DIFFERENT
--        address must not overwrite the one the first box is being sent to). A `shipped` row
--        answers the same way and keeps its carrier.
--        ⚠ The address arm is the one that matters and it is not decoration: an idempotent path
--        that returned early but still wrote would be invisible to a status-only assertion.
--   · C4 A `locked` row is refused `not_claimable` and nothing is written. The form is NOT
--        judged first: a `locked` row submitted with a broken postal still answers
--        `not_claimable`, because the state is the fact the runner can act on. And on a genuinely
--        `claimable` row every form field is validated by NAME — five refusal words, five arms,
--        nothing written by any of them.
--   · C5 **RLS scoping of the payload.** `delivery` carries a real phone and address, and
--        `authenticated` holds table SELECT on `gear_claims` (0106:135). The row policy is what
--        keeps it private: executed AS `authenticated`, the OWNER reads their own payload and a
--        STRANGER reads zero rows for the same id. The client also still cannot WRITE the new
--        columns by any path (0106 §4's belt refuses `authenticated` outright).
--   · P1 `ops_gear_claims_pending()` lists `claimed`-and-not-yet-shipped rows WITH the payload,
--        and excludes `claimable` (no address yet), `locked` and `shipped` (already gone).
--   · P2 `ops_mark_gear_shipped()` moves `claimed` → `shipped` with carrier/tracking/dispatched_at;
--        a second call is `already_shipped` and does not overwrite the first tracking number; a
--        `claimable` row is `not_claimed`; empty carrier/tracking are refused by name.
--   · P3 **THE OPS PARTY GATE, ahead of every state gate on BOTH functions.** A signed-in
--        stranger, an INACTIVE ops row and an ops row for ANOTHER class all get `not_ops` — even
--        when the call also names a claim id that does not exist and an empty carrier, either of
--        which would produce a different word if any gate ran first. No caller ⇒ `not_signed_in`.
--   · S1 Deployed shape: three definers, in-body `search_path`, ACL by EFFECTIVE privilege,
--        the source order (lock → party gate → state read) with comments STRIPPED, the
--        `delivery` shape constraint present, and NO-SOURCE arms that fail loudly.
--
-- ─── FIXTURE NOTES ───
--  ① Every count in this file is SCOPED to this suite's own profiles. `gear_claims` is shared
--     with 141 and 207, both of which leave `claimable` rows behind, so a global count would
--     measure the harness rather than this slice — the lesson 217's note ⑥ records.
--  ② The world is built as the OWNER-of-the-table (the harness's default role) so the fixture can
--     set `status` freely; every ASSERTION about the product goes through the RPC with
--     `request.jwt.claim.sub` set, which is how a real caller arrives.
--  ③ `request.jwt.claim.sub` is cleared explicitly for the no-caller arms — a leftover claim
--     would make `not_signed_in` unreachable and the arm would pass for the wrong reason.
--  ④ The stored address is asserted FIELD BY FIELD, never merely "present": C3's whole point is
--     that a second call does not move it, and a `delivery is not null` check cannot see a
--     payload that was replaced.
--
-- ─── MUTATION MAP — measured 2026-09-22 against these exact files, not predicted ───
-- Lab: a copy of `supabase/` OUTSIDE the worktree (226 md5-identical to the committed one), every
-- plant restored-from-pristine and CHAIN-GATED to its harness run (`plant && harness`), so a
-- failed plant yields NO row rather than a green one. 「demoted」 = 0195's VERIFY raise turned into
-- a notice, so what is measured is the SUITE rather than the apply. Control observed clean FIRST:
-- **1362 / 0.**
-- ⚠ PROVENANCE, because the absolute numbers below do not match the shipped tree and the reason
--   must not be left for someone to rediscover: the lab was taken while this branch sat on base
--   `1a535ab`. Trunk then gained 0193 (suite 224, +9 pins, unrelated to this slice), so the
--   shipped tree reads **1371 / 0** where the lab reads 1362. Every DELTA and every reddened-pin
--   identity below is unaffected — 224 shares no fixture, no table and no function with this file.
--
--   (i)   the party gate deleted            → 1359/3: **C2** + S1 + C4. C4 is a CASCADE, not an
--         independent detection — without a gate, C2's stranger calls actually claim the rows C4
--         later reads, so C4's form arms meet an already-claimed row and get success instead of a
--         refusal. Named so nobody reads 「3 pins caught it」 as three witnesses.
--   (ii)  the state gate deleted            → 1360/2: **C4** + S1. The locked row answers
--         `claim_race` / `bad_recipient` instead of `not_claimable` — the refusal a runner can act
--         on is replaced by an assertion failure and a complaint about their form.
--   (iii) the idempotent short-circuit deleted (and the write let through)
--                                           → 1359/3: **C3** + C5 + P1. C3's failure string names
--         받는사람/전화/주소/우편번호 **덮어써졌다** — the DIFFERENT-address arm doing exactly the
--         job §0e argues for. C5/P1 are cascades off the mutated fixture.
--   (v)   a blank 상세주소 stored as '' instead of NULL
--                                           → 1361/1: **C1 ALONE.** This plant exists only because
--         the first battery reddened C1 with nothing: C1 is the happy-path pin, and every other
--         mutation preserves the happy path by construction, so its non-blindness was the one
--         thing the set did not establish. A battery that never attacks its positive control has
--         measured everything except whether the control can fail.
--   (vi)  the ops roster gate deleted from the READ (the write's gate left in place, so the two
--         are separable)                    → 1360/2: **P3** + S1.
--   (vii) the ops list predicate widened to `<> 'shipped'`
--                                           → 1360/2: **P1** + S1. P1's failure names
--         「locked/shipped 행이 목록에 있다」 — the `locked` row walking into the list is precisely
--         the argument §C makes for a POSITIVE match, reproduced rather than asserted.
--   (viii) `already_shipped` removed and the write un-gated
--                                           → 1361/1: **P2 ALONE**, naming 「두 번째 발송이 송장을
--         덮어썼다」 — the overwrite §D refuses to allow.
--
-- 🔴 **(iv) THE ORDER INVERSION — read the state FIRST, gate SECOND → 1361/1: `S1` ALONE, and
--     that is a NAMED GAP rather than a pass.** The behavioural pins are structurally incapable of
--     seeing this plant, and the reason is a fact about the system rather than a weakness in C2:
--     reading a row into local variables has NO observable effect, and the inverted body still
--     raises `not_claim_owner` before any state-dependent branch — so a stranger's experience is
--     byte-identical in both worlds. **No fixture can separate them.**
--     The property is still worth holding, and can only be held in SOURCE: the order is what makes
--     it impossible for a future edit to slip a state-dependent branch between the read and the
--     gate. S1's `into v_status` arm (and 0195 §F's twin) is the only available detector, which is
--     exactly why it exists — the same shape as 221 L1's 「the skip cannot be seen in one session」.
--     ⚠ Per the standing rule, a limitation is PROSE: no extra pin is written for this, because
--     every arm one could write here would be green by construction.
--
-- ⚠ **C5 IS THE WEAKEST ROW IN THIS TABLE AND IS LABELLED RATHER THAN DRESSED UP.** It reddened
--   only as a CASCADE in (iii); no mutation attacks its own property. That is deliberate: the
--   guarantee C5 asserts — a row policy scoping `delivery` to its owner — belongs to `gear self
--   read` (0002:133) and 0106 §4's belt, neither of which this slice owns, and deleting either in
--   the lab would redden dozens of unrelated pins without telling anyone anything about 0195. So
--   C5 is best read as an EXECUTED check that an existing guarantee still covers a NEW column —
--   which is what turns §0b's decision (keep 0106's table-level grant, let RLS answer tenancy)
--   from prose into a measurement — and NOT as a pin with its own mutation behind it.
--
-- ⚠ THE HOLE IN 141 D19 IS REPRODUCED, not assumed: applying 0195 with D19 left at its single
--   `open_drop_tx` entry gave **1341 pass / 1 fail with D19 the only red** (measured on the
--   `1a535ab`-era tree, where the clean total was 1342). The three new client-callable functions
--   are genuinely of the shape that sweep exists to catch, so D19's widening in this slice is a
--   response to a measured red rather than a precaution.
set client_min_messages = warning;

-- a claim row in a named state, owned by a named profile
create or replace function t_gcl_claim(p_owner uuid, p_item text, p_ms int, p_status claim_status)
returns uuid language sql as $$
  insert into gear_claims (profile_id, side, item, milestone, status)
  values (p_owner, 'runner', p_item, p_ms, p_status) returning id
$$;

-- call the door as p_uid and report EITHER the flat row OR the raise word — never both, and never
-- a swallowed success. A bare `exception when others` here is the point: the pins compare the
-- WORD, so a refusal that changed its vocabulary reddens instead of silently passing.
create or replace function t_gcl_claim_as(p_uid uuid, p_claim uuid,
  p_recipient text, p_phone text, p_a1 text, p_a2 text, p_postal text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from claim_gear_tx(p_claim, p_recipient, p_phone, p_a1, p_a2, p_postal);
    return jsonb_build_object('status', r.status, 'already', r.already_claimed,
                              'claimed_at', r.claimed_at, 'carrier', r.carrier,
                              'tracking', r.tracking);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- the row as the TABLE holds it — the pins read this, not the function's answer ④
create or replace function t_gcl_row(p_claim uuid) returns jsonb language sql as $$
  select jsonb_build_object(
    'status', g.status::text, 'claimed_at', g.claimed_at,
    'recipient', g.delivery->>'recipient', 'phone', g.delivery->>'phone',
    'address1', g.delivery->>'address1', 'address2', g.delivery->>'address2',
    'postal', g.delivery->>'postal', 'delivery_null', (g.delivery is null),
    'carrier', g.delivery_carrier, 'tracking', g.delivery_tracking,
    'dispatched', (g.dispatched_at is not null))
  from gear_claims g where g.id = p_claim
$$;

create or replace function t_gcl_pending_as(p_uid uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_agg(jsonb_build_object('claim', claim_id, 'item', item,
             'recipient', recipient, 'phone', phone, 'address1', address1,
             'address2', address2, 'postal', postal) order by claim_id), '[]'::jsonb)
      into v from ops_gear_claims_pending();
    return jsonb_build_object('rows', v);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_gcl_ship_as(p_uid uuid, p_claim uuid, p_carrier text, p_tracking text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from ops_mark_gear_shipped(p_claim, p_carrier, p_tracking);
    return jsonb_build_object('status', r.status, 'carrier', r.carrier, 'tracking', r.tracking);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

do $$
declare
  rn      uuid;   -- the claiming runner
  rn2     uuid;   -- a second runner: the stranger
  ops1    uuid;   -- an active ops operator
  opsoff  uuid;   -- an ops row that is INACTIVE
  opsx    uuid;   -- an ops row for ANOTHER event class
  cClaim  uuid;   -- claimable, the happy path
  cLock   uuid;   -- locked
  cShip   uuid;   -- shipped, with a carrier already on it
  cOther  uuid;   -- claimable, owned by rn2 (the stranger's own row)
  cForm   uuid;   -- claimable, the form-validation subject
  cOps    uuid;   -- claimable → claimed, the ops-flow subject
  v       jsonb;
  v_row   jsonb;
  v_before jsonb;
  v_bad   text := '';
  v_msg   text;
  v_n     int;
  v_src   text;
  v_oid   oid;
  v_word  text;
  fn      text;
begin
  rn     := t_user('gcl_runner',   'runner');
  rn2    := t_user('gcl_stranger', 'runner');
  ops1   := t_user('gcl_ops1',     'owner');
  opsoff := t_user('gcl_opsoff',   'owner');
  opsx   := t_user('gcl_opsx',     'owner');

  insert into ops_recipients (profile_id, event_class, active) values
    (ops1,   'payout_due',            true),
    (opsoff, 'payout_due',            false),
    (opsx,   'charge_dispatch_stale', true);

  cClaim := t_gcl_claim(rn,  'gcl 러너 후디',   5,  'claimable');
  cLock  := t_gcl_claim(rn,  'gcl 러너 캡',     50, 'locked');
  cOther := t_gcl_claim(rn2, 'gcl 남의 교환권', 5,  'claimable');
  cForm  := t_gcl_claim(rn,  'gcl 양식 검증',   15, 'claimable');
  cOps   := t_gcl_claim(rn,  'gcl 운영 대상',   25, 'claimable');
  cShip  := t_gcl_claim(rn,  'gcl 이미 발송',   35, 'claimable');

  -- ① fixture honesty: nothing this suite owns is claimed before the suite runs
  select count(*)::int into v_n from gear_claims
   where profile_id in (rn, rn2) and status <> 'claimable' and status <> 'locked';
  if v_n is distinct from 0 then v_bad := ' fixture: 이 스위트의 교환권이 이미 처리됨 (' || v_n || ')'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('gcl','fixture', v_msg); v_bad := ''; end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-C1] the happy path — the row, not the return, is the evidence
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_gcl_claim_as(rn, cClaim, '  김러너 ', '010-1234-5678', '서울시 서초구 반포대로 1', '101동 202호', '06578');
  if v->>'raised' is not null then v_bad := v_bad || ' 정상 신청이 거절됨: ' || (v->>'raised');
  else
    if v->>'status'  is distinct from 'claimed' then v_bad := v_bad || ' 반환 status=' || coalesce(v->>'status','NULL'); end if;
    if (v->>'already')::boolean is distinct from false then v_bad := v_bad || ' 첫 신청인데 already=true'; end if;
    if v->>'claimed_at' is null then v_bad := v_bad || ' 반환에 claimed_at 없음'; end if;
    -- the carrier is genuinely absent at claim time; the door must not invent one
    if v->>'carrier'  is not null then v_bad := v_bad || ' 신청 직후에 택배사가 있다'; end if;
    if v->>'tracking' is not null then v_bad := v_bad || ' 신청 직후에 송장이 있다'; end if;
  end if;
  v_row := t_gcl_row(cClaim);
  if v_row->>'status'    is distinct from 'claimed'                 then v_bad := v_bad || ' 행 status=' || coalesce(v_row->>'status','NULL'); end if;
  if v_row->>'claimed_at' is null                                    then v_bad := v_bad || ' 행에 claimed_at 없음'; end if;
  if v_row->>'recipient' is distinct from '김러너'                   then v_bad := v_bad || ' 받는사람=' || coalesce(v_row->>'recipient','NULL'); end if;
  -- digits only: 010-1234-5678 and 01012345678 are one number, and storing both spellings makes a
  -- duplicate look like two people (0195 §B ⑥)
  if v_row->>'phone'     is distinct from '01012345678'              then v_bad := v_bad || ' 전화=' || coalesce(v_row->>'phone','NULL'); end if;
  if v_row->>'address1'  is distinct from '서울시 서초구 반포대로 1' then v_bad := v_bad || ' 주소1=' || coalesce(v_row->>'address1','NULL'); end if;
  if v_row->>'address2'  is distinct from '101동 202호'              then v_bad := v_bad || ' 주소2=' || coalesce(v_row->>'address2','NULL'); end if;
  if v_row->>'postal'    is distinct from '06578'                    then v_bad := v_bad || ' 우편번호=' || coalesce(v_row->>'postal','NULL'); end if;
  if (v_row->>'dispatched')::boolean is distinct from false          then v_bad := v_bad || ' 신청만 했는데 발송 시각이 찍혔다'; end if;
  -- address2 is genuinely optional and its absence must be NULL, never the empty string: a
  -- courier label printing a blank line is a different thing from one that has no second line.
  v := t_gcl_claim_as(rn, cForm, '박러너', '01099998888', '서울시 강남구 테헤란로 2', '   ', '06236');
  if v->>'raised' is not null then v_bad := v_bad || ' 주소2 없는 신청이 거절됨: ' || (v->>'raised'); end if;
  v_row := t_gcl_row(cForm);
  if v_row->>'address2' is not null then v_bad := v_bad || ' 공백 주소2가 빈 문자열로 저장됨'; end if;
  if v_row->>'status' is distinct from 'claimed' then v_bad := v_bad || ' 주소2 없는 신청이 안 써졌다'; end if;
  if v_bad = '' then call _pass('gcl','0195-C1 수령 신청 — claimed·claimed_at·다섯 칸이 행에 저장(전화는 숫자만, 빈 주소2는 NULL), 택배사는 아직 없음');
  else v_msg := v_bad; call _fail('gcl','0195-C1 수령 신청', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-C2] PARTY BEFORE STATE — the stranger learns one word, whatever the state is
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- The three subjects are deliberately in THREE DIFFERENT states (claimable / locked / claimed).
  -- If the state were judged first, they would produce three different words — `not_claimable`
  -- for the locked one and `already_claimed` for the claimed one — and the id would become an
  -- oracle for a row the caller does not own. One word for all three is the property.
  v_bad := '';
  foreach v_msg in array array[cClaim::text, cLock::text, cOps::text] loop
    v := t_gcl_claim_as(rn2, v_msg::uuid, '도둑', '01011112222', '어딘가 1', null, '12345');
    if v->>'raised' is distinct from 'not_claim_owner'
    then v_bad := v_bad || ' 남의 행(' || left(v_msg, 8) || ')에 not_claim_owner가 아님: ' || coalesce(v->>'raised', 'ACCEPTED(' || coalesce(v->>'status','?') || ')'); end if;
  end loop;
  -- and nothing moved: the claimable one is still claimable, the locked one still locked, and the
  -- claimed one still holds the address ITS OWNER typed
  if (t_gcl_row(cLock)->>'status')  is distinct from 'locked'    then v_bad := v_bad || ' 잠긴 행이 움직였다'; end if;
  if (t_gcl_row(cOps)->>'status')   is distinct from 'claimable' then v_bad := v_bad || ' cOps가 움직였다'; end if;
  if (t_gcl_row(cClaim)->>'recipient') is distinct from '김러너' then v_bad := v_bad || ' 남이 배송지를 덮어썼다'; end if;
  -- the stranger's OWN row still works — the control that stops this pin passing for free by
  -- refusing everyone
  v := t_gcl_claim_as(rn2, cOther, '이러너', '01033334444', '부산시 해운대구 3', null, '48099');
  if v->>'raised' is not null then v_bad := v_bad || ' 대조: 자기 행도 거절됨 ' || (v->>'raised'); end if;
  if (t_gcl_row(cOther)->>'status') is distinct from 'claimed' then v_bad := v_bad || ' 대조: 자기 행이 안 써졌다'; end if;
  -- no caller at all ③
  perform set_config('request.jwt.claim.sub', '', true);
  v := t_gcl_claim_as(null, cOps, '무명', '01000000000', 'x 1', null, '00000');
  if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' 무기명: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  -- an id that does not exist is not an oracle either: the same word a real stranger's row gives
  -- would leak existence, so a missing row gets its own word and a signed-in caller gets it too
  v := t_gcl_claim_as(rn, gen_random_uuid(), '김러너', '01012345678', 'x 1', null, '06578');
  if v->>'raised' is distinct from 'claim_not_found' then v_bad := v_bad || ' 없는 id: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, null, '김러너', '01012345678', 'x 1', null, '06578');
  if v->>'raised' is distinct from 'claim_not_found' then v_bad := v_bad || ' NULL id: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  if v_bad = '' then call _pass('gcl','0195-C2 파티 게이트가 상태보다 먼저 — 세 가지 상태의 남의 행이 전부 not_claim_owner 한 단어, 아무것도 안 바뀜; 자기 행은 통과(대조); 무기명/없는 id/NULL id는 각자의 단어');
  else v_msg := v_bad; call _fail('gcl','0195-C2 파티 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-C3] IDEMPOTENCY — the second call is a success that writes nothing
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v_before := t_gcl_row(cClaim);
  -- the second call carries a DIFFERENT address on purpose ④: an early return that still wrote
  -- would be invisible to a status-only assertion, and the box is already going somewhere.
  v := t_gcl_claim_as(rn, cClaim, '최다른', '01055556666', '대전시 유성구 9', '9층', '34141');
  if v->>'raised' is not null then v_bad := v_bad || ' 두 번째 신청이 예외를 던졌다: ' || (v->>'raised');
  else
    if (v->>'already')::boolean is not true then v_bad := v_bad || ' already_claimed=' || coalesce(v->>'already','NULL'); end if;
    if v->>'status' is distinct from 'claimed' then v_bad := v_bad || ' 두 번째 반환 status=' || coalesce(v->>'status','NULL'); end if;
  end if;
  v_row := t_gcl_row(cClaim);
  if v_row->>'recipient'  is distinct from (v_before->>'recipient')  then v_bad := v_bad || ' 받는사람이 덮어써졌다'; end if;
  if v_row->>'phone'      is distinct from (v_before->>'phone')      then v_bad := v_bad || ' 전화가 덮어써졌다'; end if;
  if v_row->>'address1'   is distinct from (v_before->>'address1')   then v_bad := v_bad || ' 주소가 덮어써졌다'; end if;
  if v_row->>'postal'     is distinct from (v_before->>'postal')     then v_bad := v_bad || ' 우편번호가 덮어써졌다'; end if;
  if v_row->>'claimed_at' is distinct from (v_before->>'claimed_at') then v_bad := v_bad || ' claimed_at이 다시 찍혔다'; end if;
  -- a SHIPPED row answers the same way and keeps its carrier: shipped is further along the same
  -- path, not a different path, so 「이미 신청했다」 stays the true answer
  update gear_claims set status = 'shipped', claimed_at = now() - interval '2 days',
         delivery = jsonb_build_object('recipient','정러너','phone','01077778888',
                                       'address1','인천시 연수구 7','address2',null,'postal','21999'),
         delivery_carrier = 'CJ대한통운', delivery_tracking = 'TRK-0195-A',
         dispatched_at = now() - interval '1 day'
   where id = cShip;
  v := t_gcl_claim_as(rn, cShip, '최다른', '01055556666', '대전시 유성구 9', null, '34141');
  if v->>'raised' is not null then v_bad := v_bad || ' 발송된 행이 예외를 던졌다: ' || (v->>'raised');
  else
    if (v->>'already')::boolean is not true then v_bad := v_bad || ' 발송 행 already=' || coalesce(v->>'already','NULL'); end if;
    if v->>'status'   is distinct from 'shipped'    then v_bad := v_bad || ' 발송 행 반환 status=' || coalesce(v->>'status','NULL'); end if;
    -- the return must carry the carrier the runner can actually use
    if v->>'carrier'  is distinct from 'CJ대한통운' then v_bad := v_bad || ' 발송 행 반환에 택배사 없음'; end if;
    if v->>'tracking' is distinct from 'TRK-0195-A' then v_bad := v_bad || ' 발송 행 반환에 송장 없음'; end if;
  end if;
  v_row := t_gcl_row(cShip);
  if v_row->>'recipient' is distinct from '정러너'    then v_bad := v_bad || ' 발송 행 배송지가 덮어써졌다'; end if;
  if v_row->>'tracking'  is distinct from 'TRK-0195-A' then v_bad := v_bad || ' 발송 행 송장이 덮어써졌다'; end if;
  if v_bad = '' then call _pass('gcl','0195-C3 멱등성 — 두 번째 신청은 already_claimed=true이고 예외가 아니며, 다른 주소를 실어도 행의 배송지·claimed_at이 움직이지 않는다; shipped 행도 같은 답에 택배사·송장을 싣는다');
  else v_msg := v_bad; call _fail('gcl','0195-C3 멱등성', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-C4] the state gate, and the form refusals by name
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  -- a locked row, with a GOOD form
  v := t_gcl_claim_as(rn, cLock, '김러너', '01012345678', '서울시 서초구 1', null, '06578');
  if v->>'raised' is distinct from 'not_claimable' then v_bad := v_bad || ' 잠긴 행: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  -- ...and with a BROKEN form. The state wins (0195 §0e): the runner cannot act on a postal code
  -- complaint about a reward they have not earned yet.
  v := t_gcl_claim_as(rn, cLock, '', '1', '', null, 'abc');
  if v->>'raised' is distinct from 'not_claimable' then v_bad := v_bad || ' 잠긴 행+깨진 양식: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  if (t_gcl_row(cLock)->>'delivery_null')::boolean is not true then v_bad := v_bad || ' 잠긴 행에 배송지가 써졌다'; end if;
  if (t_gcl_row(cLock)->>'status') is distinct from 'locked' then v_bad := v_bad || ' 잠긴 행 status가 움직였다'; end if;
  -- the form, on a genuinely claimable row, refused BY NAME — five arms, five words
  foreach v_word in array array['bad_recipient', 'bad_phone', 'bad_address', 'bad_postal', 'bad_postal'] loop
    null;  -- vocabulary declared above the arms so a renamed token is visible in one place
  end loop;
  v := t_gcl_claim_as(rn, cOps, '   ',    '01012345678', '서울시 1', null, '06578');
  if v->>'raised' is distinct from 'bad_recipient' then v_bad := v_bad || ' 빈 받는사람: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '010123456',   '서울시 1', null, '06578');
  if v->>'raised' is distinct from 'bad_phone'     then v_bad := v_bad || ' 9자리 전화: '   || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '010123456789','서울시 1', null, '06578');
  if v->>'raised' is distinct from 'bad_phone'     then v_bad := v_bad || ' 12자리 전화: '  || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '01012345678', '   ',      null, '06578');
  if v->>'raised' is distinct from 'bad_address'   then v_bad := v_bad || ' 빈 주소: '      || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '01012345678', '서울시 1', null, '0657');
  if v->>'raised' is distinct from 'bad_postal'    then v_bad := v_bad || ' 4자리 우편: '   || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '01012345678', '서울시 1', null, '065789');
  if v->>'raised' is distinct from 'bad_postal'    then v_bad := v_bad || ' 6자리 우편: '   || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '01012345678', '서울시 1', null, 'ABCDE');
  if v->>'raised' is distinct from 'bad_postal'    then v_bad := v_bad || ' 문자 우편: '    || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', null,          '서울시 1', null, null);
  if v->>'raised' is distinct from 'bad_phone'     then v_bad := v_bad || ' NULL 전화: '    || coalesce(v->>'raised','ACCEPTED'); end if;
  -- nothing above wrote anything, and the row still opens for a good form (the control that stops
  -- this pin passing by refusing everything)
  if (t_gcl_row(cOps)->>'delivery_null')::boolean is not true then v_bad := v_bad || ' 거절된 양식이 배송지를 남겼다'; end if;
  if (t_gcl_row(cOps)->>'status') is distinct from 'claimable'  then v_bad := v_bad || ' 거절이 status를 움직였다'; end if;
  v := t_gcl_claim_as(rn, cOps, '김러너', '010-1234-5678', '서울시 서초구 반포대로 1', null, '06578');
  if v->>'raised' is not null then v_bad := v_bad || ' 대조: 좋은 양식도 거절됨 ' || (v->>'raised'); end if;
  if (t_gcl_row(cOps)->>'status') is distinct from 'claimed' then v_bad := v_bad || ' 대조: 좋은 양식이 안 써졌다'; end if;
  if v_bad = '' then call _pass('gcl','0195-C4 상태 게이트가 양식보다 먼저 — 잠긴 행은 양식이 깨져도 not_claimable, 아무것도 안 써짐; claimable 행에서 양식은 이름으로 거절(bad_recipient/bad_phone/bad_address/bad_postal), 좋은 양식은 통과(대조)');
  else v_msg := v_bad; call _fail('gcl','0195-C4 상태·양식 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-C5] RLS scoping — the payload is the runner's own, and only theirs
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- Executed AS `authenticated`, which is the role the app actually holds. This is the arm that
  -- justifies 0195 §0b's decision NOT to convert 0106's table-level grant into column grants: the
  -- claim is that RLS already answers the tenancy question, and an unexecuted claim is prose.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', rn::text, true);
  begin
    set local role authenticated;
    select count(*)::int into v_n from gear_claims where id = cClaim and delivery->>'phone' = '01012345678';
    if v_n is distinct from 1 then v_bad := v_bad || ' 주인이 자기 배송지를 못 읽는다 (' || v_n || ')'; end if;
  exception when others then v_bad := v_bad || ' 주인 읽기가 터졌다 [' || sqlstate || ' ' || sqlerrm || ']'; end;
  reset role;
  perform set_config('request.jwt.claim.sub', rn2::text, true);
  begin
    set local role authenticated;
    select count(*)::int into v_n from gear_claims where id = cClaim;
    if v_n is distinct from 0 then v_bad := v_bad || ' 남이 남의 교환권 행을 읽었다 (' || v_n || ')'; end if;
    -- and the stranger's own row IS visible — the control, so 「zero rows」 cannot come from a
    -- broken session rather than from the policy
    select count(*)::int into v_n from gear_claims where id = cOther;
    if v_n is distinct from 1 then v_bad := v_bad || ' 대조: 자기 행도 안 보인다 (' || v_n || ')'; end if;
  exception when others then v_bad := v_bad || ' 남 읽기가 터졌다 [' || sqlstate || ' ' || sqlerrm || ']'; end;
  reset role;
  -- 0106 §4's belt still refuses the client on the NEW columns: the door is the only writer
  perform set_config('request.jwt.claim.sub', rn::text, true);
  begin
    set local role authenticated;
    update gear_claims set delivery_tracking = 'FORGED' where id = cClaim;
    v_bad := v_bad || ' 러너가 송장을 직접 썼다';
  exception when others then if sqlstate <> '42501' then v_bad := v_bad || ' 송장 쓰기[' || sqlstate || ']'; end if; end;
  reset role;
  if (t_gcl_row(cClaim)->>'tracking') is not null then v_bad := v_bad || ' 위조 송장이 남았다'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  if v_bad = '' then call _pass('gcl','0195-C5 배송지는 RLS가 막는다 — authenticated로 실행: 주인은 자기 전화/주소를 읽고 남은 그 행을 0행으로 읽으며 자기 행은 보인다(대조); 새 열도 0106 §4 벨트가 클라 쓰기를 42501로 막는다');
  else v_msg := v_bad; call _fail('gcl','0195-C5 배송지 RLS', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-P1] the ops read — claimed and not yet shipped, with the payload
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_gcl_pending_as(ops1);
  if v->>'raised' is not null then v_bad := v_bad || ' ops 읽기가 거절됨: ' || (v->>'raised');
  else
    -- scoped to this suite's rows ①: gear_claims is shared with 141 and 207
    select count(*)::int into v_n from jsonb_array_elements(v->'rows') e
     where (e->>'claim')::uuid in (cClaim, cForm, cOps, cOther);
    if v_n is distinct from 4 then v_bad := v_bad || ' claimed 행 ' || v_n || '개만 보인다(4 기대)'; end if;
    -- `locked` and `shipped` are BOTH excluded, and for different reasons — one has no address
    -- yet, the other's box is gone. A `<> shipped` predicate would have let the locked one in.
    if (select count(*)::int from jsonb_array_elements(v->'rows') e
         where (e->>'claim')::uuid in (cLock, cShip)) is distinct from 0
    then v_bad := v_bad || ' locked/shipped 행이 목록에 있다'; end if;
    -- the payload is actually carried — a list of ids would not let anyone post a box
    if (select e->>'recipient' from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cClaim)
       is distinct from '김러너' then v_bad := v_bad || ' 받는사람이 안 실렸다'; end if;
    if (select e->>'phone' from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cClaim)
       is distinct from '01012345678' then v_bad := v_bad || ' 전화가 안 실렸다'; end if;
    if (select e->>'postal' from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cClaim)
       is distinct from '06578' then v_bad := v_bad || ' 우편번호가 안 실렸다'; end if;
  end if;
  if v_bad = '' then call _pass('gcl','0195-P1 ops 대기 목록 — claimed 행만(locked도 shipped도 제외, 긍정 매칭), 배송지 다섯 칸을 싣는다');
  else v_msg := v_bad; call _fail('gcl','0195-P1 ops 대기 목록', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-P2] the ops write — claimed → shipped, once
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_gcl_ship_as(ops1, cOps, '롯데택배', 'TRK-0195-B');
  if v->>'raised' is not null then v_bad := v_bad || ' 발송 기록이 거절됨: ' || (v->>'raised');
  else
    if v->>'status'   is distinct from 'shipped'    then v_bad := v_bad || ' 반환 status=' || coalesce(v->>'status','NULL'); end if;
    if v->>'carrier'  is distinct from '롯데택배'   then v_bad := v_bad || ' 반환 택배사=' || coalesce(v->>'carrier','NULL'); end if;
    if v->>'tracking' is distinct from 'TRK-0195-B' then v_bad := v_bad || ' 반환 송장=' || coalesce(v->>'tracking','NULL'); end if;
  end if;
  v_row := t_gcl_row(cOps);
  if v_row->>'status'   is distinct from 'shipped'            then v_bad := v_bad || ' 행 status=' || coalesce(v_row->>'status','NULL'); end if;
  if v_row->>'carrier'  is distinct from '롯데택배'           then v_bad := v_bad || ' 행 택배사 없음'; end if;
  if v_row->>'tracking' is distinct from 'TRK-0195-B'         then v_bad := v_bad || ' 행 송장 없음'; end if;
  if (v_row->>'dispatched')::boolean is not true              then v_bad := v_bad || ' dispatched_at이 안 찍혔다'; end if;
  -- the shipped row leaves the ops list — otherwise an operator posts the same box twice
  v := t_gcl_pending_as(ops1);
  if (select count(*)::int from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cOps)
     is distinct from 0 then v_bad := v_bad || ' 발송한 행이 대기 목록에 남았다'; end if;
  -- a second stamp is a MISTAKE, not a retry (0195 §D): it must refuse AND must not overwrite
  v := t_gcl_ship_as(ops1, cOps, '한진택배', 'TRK-OVERWRITE');
  if v->>'raised' is distinct from 'already_shipped' then v_bad := v_bad || ' 두 번째 발송: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  if (t_gcl_row(cOps)->>'tracking') is distinct from 'TRK-0195-B' then v_bad := v_bad || ' 두 번째 발송이 송장을 덮어썼다'; end if;
  -- a row nobody has claimed cannot be posted: there is no address to post it to
  cClaim := cClaim;  -- (cClaim is claimed; cOther is claimed; the claimable subject left is none)
  v := t_gcl_ship_as(ops1, t_gcl_claim(rn, 'gcl 미신청', 45, 'claimable'), 'CJ대한통운', 'TRK-X');
  if v->>'raised' is distinct from 'not_claimed' then v_bad := v_bad || ' 미신청 행: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  -- carrier/tracking refused by name, and nothing written
  v_before := t_gcl_row(cOther);
  v := t_gcl_ship_as(ops1, cOther, '   ', 'TRK-Y');
  if v->>'raised' is distinct from 'bad_carrier'  then v_bad := v_bad || ' 빈 택배사: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_ship_as(ops1, cOther, 'CJ대한통운', null);
  if v->>'raised' is distinct from 'bad_tracking' then v_bad := v_bad || ' NULL 송장: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_ship_as(ops1, null, 'CJ대한통운', 'TRK-Z');
  if v->>'raised' is distinct from 'claim_not_found' then v_bad := v_bad || ' NULL id: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  if (t_gcl_row(cOther)->>'status') is distinct from (v_before->>'status') then v_bad := v_bad || ' 거절이 행을 움직였다'; end if;
  if v_bad = '' then call _pass('gcl','0195-P2 ops 발송 기록 — claimed→shipped에 택배사·송장·dispatched_at, 목록에서 빠지고, 두 번째는 already_shipped로 거절하며 송장을 안 덮어쓴다; 미신청은 not_claimed, 빈 택배사/송장은 이름으로 거절');
  else v_msg := v_bad; call _fail('gcl','0195-P2 ops 발송 기록', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-P3] the ops party gate, ahead of every state gate on BOTH functions
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- Each refusal call ALSO carries arguments that would produce a different word if any other
  -- gate ran first — a claim id that does not exist and an empty carrier. Getting `not_ops`
  -- anyway is what makes this an ordering pin rather than a membership pin.
  v_bad := '';
  foreach v_msg in array array[rn::text, rn2::text, opsoff::text, opsx::text] loop
    v := t_gcl_pending_as(v_msg::uuid);
    if v->>'raised' is distinct from 'not_ops'
    then v_bad := v_bad || ' 읽기/' || left(v_msg, 8) || ': ' || coalesce(v->>'raised','ACCEPTED'); end if;
    v := t_gcl_ship_as(v_msg::uuid, gen_random_uuid(), '', '');
    if v->>'raised' is distinct from 'not_ops'
    then v_bad := v_bad || ' 쓰기/' || left(v_msg, 8) || ': ' || coalesce(v->>'raised','ACCEPTED'); end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
  v := t_gcl_pending_as(null);
  if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' 읽기/무기명: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  v := t_gcl_ship_as(null, gen_random_uuid(), '', '');
  if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' 쓰기/무기명: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  -- the ACTIVE operator still works — without this the pin passes by refusing everyone
  v := t_gcl_pending_as(ops1);
  if v->>'raised' is not null then v_bad := v_bad || ' 대조: 현역 ops도 거절됨 ' || (v->>'raised'); end if;
  if v_bad = '' then call _pass('gcl','0195-P3 ops 파티 게이트가 먼저 — 러너·남·비활성 ops·다른 클래스 ops가 없는 id와 빈 택배사를 같이 실어도 답은 not_ops 하나; 무기명은 not_signed_in; 현역 ops는 통과(대조)');
  else v_msg := v_bad; call _fail('gcl','0195-P3 ops 파티 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0195-S1] deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ Every `prosrc` match here strips comments first. This file's migration documents its own
  -- guards in prose, and a check that a guard is CALLED would otherwise be satisfied by the
  -- paragraph EXPLAINING it — the better the explanation, the more certainly green.
  -- ⚠ Ordering arms anchor on `into v_status`, never the bare name `v_status`: `prosrc` includes
  -- the DECLARE block, so a bare-name anchor compares against a declaration and is false on
  -- correct code.
  v_bad := '';
  foreach fn in array array['claim_gear_tx', 'ops_gear_claims_pending', 'ops_mark_gear_shipped'] loop
    select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = fn;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':definer 아님'; end if;
      if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
            from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':search_path 없음'; end if;
      if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':PUBLIC 실행 가능'; end if;
      if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':anon 실행 가능'; end if;
      if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':authenticated 실행 불가'; end if;
    end if;
  end loop;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'claim_gear_tx';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
  else
    if (position('for update' in v_src) > 0) is not true then v_bad := v_bad || ' 행 잠금 없음'; end if;
    if (position('raise exception ''not_claim_owner''' in v_src) > 0) is not true
    then v_bad := v_bad || ' 파티 게이트 없음'; end if;
    if (position('into v_status' in v_src) > 0) is not true then v_bad := v_bad || ' 상태 읽기 없음'; end if;
    if (position('for update' in v_src)
        < position('raise exception ''not_claim_owner''' in v_src)) is not true
    then v_bad := v_bad || ' 파티 게이트가 잠금보다 앞'; end if;
    if (position('raise exception ''not_claim_owner''' in v_src)
        < position('into v_status' in v_src)) is not true
    then v_bad := v_bad || ' 상태를 파티 게이트보다 먼저 읽는다'; end if;
    -- `already_claimed` must never be a raise: it is a flat return field (0195 §0e)
    if (position('already_claimed' in v_src) > 0) then v_bad := v_bad || ' already_claimed가 예외로 바뀌었다'; end if;
    if (position('raise exception ''not_claimable''' in v_src) > 0) is not true
    then v_bad := v_bad || ' 상태 게이트 없음'; end if;
    -- the answer is read back from the table, not composed from the arguments
    if (v_src ~ 'from gear_claims g where g\.id = p_claim_id;[\s]*end') is not true
       and (position('return query' in v_src) > 0) is not true
    then v_bad := v_bad || ' 반환이 행에서 읽히지 않는다'; end if;
  end if;

  foreach fn in array array['ops_gear_claims_pending', 'ops_mark_gear_shipped'] loop
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = fn;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')';
    else
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' ' || fn || ':0084 로스터 창구를 안 쓴다'; end if;
      if (position('raise exception ''not_ops''' in v_src)
          < position('from gear_claims' in v_src)) is not true
      then v_bad := v_bad || ' ' || fn || ':ops 게이트가 행 읽기보다 뒤'; end if;
    end if;
  end loop;
  -- the ops list predicate is a POSITIVE match on one value, never `<> shipped`
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_gear_claims_pending';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_gear_claims_pending/술어)';
  else
    if (v_src ~ 'g\.status = ''claimed''') is not true then v_bad := v_bad || ' 대기 목록 술어가 긍정 매칭이 아니다'; end if;
  end if;

  -- the column shape belt
  if (select exists (select 1 from pg_constraint
                      where conrelid = 'gear_claims'::regclass
                        and conname = 'gear_claims_delivery_shape')) is not true
  then v_bad := v_bad || ' gear_claims_delivery_shape 제약 없음'; end if;
  -- ...and it actually bites: a payload with a 4-digit postal must be refused by the TABLE, not
  -- only by the RPC. Written as the owner, i.e. past every trigger and policy, so the constraint
  -- is the only thing that can refuse it.
  begin
    update gear_claims set delivery = jsonb_build_object('recipient','x','phone','01011112222',
                                                         'address1','y','address2',null,'postal','123')
     where id = cLock;
    v_bad := v_bad || ' 4자리 우편번호 payload가 테이블을 통과했다';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 제약[' || sqlstate || ']'; end if; end;
  if (t_gcl_row(cLock)->>'delivery_null')::boolean is not true then v_bad := v_bad || ' 거절된 payload가 남았다'; end if;
  -- `shipped_to` is NOT this slice's column and must still be the uuid 0115:442 reasons about
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'gear_claims' and column_name = 'shipped_to')
     is distinct from 'uuid'
  then v_bad := v_bad || ' shipped_to가 더 이상 uuid가 아니다'; end if;
  if v_bad = '' then call _pass('gcl','0195-S1 배포 형상 — 세 definer·in-body search_path·유효 권한으로 본 ACL·주석 제거한 소스 순서(잠금→파티→상태)·already_claimed는 예외가 아님·대기 목록은 긍정 매칭·delivery 제약이 실제로 문다·shipped_to는 그대로 uuid');
  else v_msg := v_bad; call _fail('gcl','0195-S1 배포 형상', v_msg); end if;
end $$;
