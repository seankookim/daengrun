-- ═══ 210 — 0179's `create_booking_hold_tx` — 0179-K1…K8, tag `bhk` ══════════════════════════════
--
-- THE PROPOSITION THIS FILE OWNS: a submit attempt makes AT MOST ONE booking. The same owner and
-- the same key name the same row however many times they arrive; a reused key with a different
-- slot or price is refused; two keys make two; the same-dog overlap guard is atomic with the
-- insert; the party gate answers before any state is read; and every write of the hold rolls
-- back together. Backend honesty audit 2026-09-17 §(a) #3.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE:
--   · the edge's pre-read gates (ownership before the debt lock, route gate, card/flag gates,
--     km bounds) — `booking_card_path_test.ts` / `booking_route_gate_test.ts` /
--     `booking_runner_body_test.ts` own them; the function re-checks ownership as a belt only.
--   · pricing — the edge computes it and passes it in (`_shared/ctx.ts` PRICING); K1 asserts the
--     stored fares are the ones handed in, not that they are right.
--   · the two-connection race on one key / one dog — serialized by transaction-scoped advisory
--     locks whose ORDER K8 pins in source; the race itself is measured by hand (header of the
--     battery), NAMED GAP.
--
-- ─── MUTATION MAP — MEASURED, not predicted (plants `&&`-chained to their run against an
--     md5-identical COPY of the shipped body; CONTROL = 0179's VERIFY demoted to a notice with
--     NO plant ⇒ 1260/0 first; the copy restored to its md5 after) ───
--   (i)    the dog party gate deleted          ⇒ 1259/1 = K5 ALONE (the VERIFY still finds
--          'forbidden' via the address arm): 「strangers-dog-ACCEPTED」, and an absent dog surfaces
--          as a raw FK violation instead of the same word — 0054:73's oracle, in the flesh.
--   (ii)   the replay lookup deleted            ⇒ un-demoted: APPLY ABORTS `TOKENS-MISSING
--          LOCK-NOT-BEFORE-REPLAY-READ`; demoted ⇒ 1256/4 = K1 (「replay-RAISED [dog_slot_clash]」
--          — with no door the second call meets the clash guard on its own slot) + K2 (the belt's
--          23505 where request_mismatch should be) + K7 (the close-on-replay raises 23505) + K8.
--          ⚠ Before every replay call was wrapped, this plant ABORTED THE SUITE (the harness's
--          「SUITE PARSE/EXEC FAILED」, loud but nameless); the wraps are what make it a pin row.
--   (iii)  the mismatch comparison deleted      ⇒ un-demoted: APPLY ABORTS `TOKENS-MISSING`;
--          demoted ⇒ 1258/2 = K2 (every arm ACCEPTED) + K8 (「토큰 누락」).
--   (iv)   the clash guard moved AFTER the insert ⇒ un-demoted: APPLY ABORTS
--          `CLASH-GUARD-AFTER-INSERT`; demoted ⇒ 1259/1 = K8 ALONE — **K4 STAYS GREEN**, and that is
--          a fact about the door, not a blind pin: inside one transaction a raise after the insert
--          rolls the insert back, so the guard's POSITION is a cost property (a wasted insert), not
--          a correctness one. The order arm is the only detector, kept as such.
--   (v)    the dog lock deleted                  ⇒ 1259/1 = K8 ALONE (the order arm) — and THE RACE
--          below breaks: two overlapping holds for one dog.
--   (vi)   the unique index not created         ⇒ un-demoted: APPLY ABORTS `NO-INDEX`; demoted ⇒
--          1259/1 = K8 (「duplicate-(owner,key)-INSERTED NO-INDEX」 — the belt exercised).
--   (vii)  the key lock deleted                  ⇒ 1259/1 = K8 ALONE (the order arm); see the race.
--   (viii) the replay read no longer OWNER-scoped ⇒ 1259/1 = K5 ALONE (「other-owner+my-key raised
--          [request_mismatch] … an existence oracle」) — the conjunct's own mutation (cold review #1).
--   (ix)   total_price dropped from the comparison ⇒ 1259/1 = K2 ALONE (「price-only-change-ACCEPTED」).
--   (x)    pace_label AND min_fare dropped        ⇒ 1259/1 = K2 ALONE (both arms named).
--   (xi)   a fresh hold answers hold_expires_at NULL ⇒ 1259/1 = K7 ALONE (「hold_expires_at-shape=NULL」
--          — the arm is `is distinct from true`, so NULL is a failure, not silence; cold review #4).
--   (xii)  the replay no longer closes a payment_hold row ⇒ 1259/1 = K7 ALONE (「payment_hold-
--          replay-did-not-close」; cold review #7).
--
-- ─── THE RACES — deterministic, measured by hand on the shipped body, NOT pinned (two
--     connections; `90_race_check.sh` is single-purpose — NAMED GAP, held by K8's order arms plus
--     these measurements). Session A opens a transaction, calls the function and holds it open 3 s;
--     session B calls with `statement_timeout = 1500ms`; then A commits and B calls again.
--   SAME DOG, two keys, overlapping (a double-submit as two attempts):
--     shipped   ⇒ B BLOCKS inside pg_advisory_xact_lock (the timeout fires there), after A commits
--                 B ⇒ `dog_slot_clash`, 1 booking.
--     plant (v) ⇒ B answers IMMEDIATELY with a second booking, 2 bookings — the guard read a
--                 snapshot with no committed row in it. The dog lock is load-bearing.
--   SAME KEY, same dog (a double-submit of one attempt):
--     shipped   ⇒ B blocks, then `unchanged: true` with A's id, 1 booking.
--     plants (v)/(vii) ⇒ same as shipped — the OTHER lock serializes it (recorded, not claimed).
--   SAME KEY, two DIFFERENT dogs (a reused key with a changed payload, concurrently — the one case
--   the key lock alone owns):
--     shipped     ⇒ B blocks on the KEY lock, then `request_mismatch`, 1 booking.
--     plant (vii) ⇒ B blocks on the UNIQUE INDEX instead (「while inserting index tuple」) and would
--                 surface a raw 23505 after A's commit; 1 booking either way. The belt alone
--                 prevents the double booking; the key lock's measured value is that the waiter
--                 gets a NAMED answer (replay or mismatch) instead of a raw unique violation.
--
-- ─── FIXTURE NOTES ───
--  ① The function is service_role-only and takes the OWNER as a parameter (the edge validated the
--     JWT); the suite calls it as the harness owner, which is the same tier. Nothing here goes
--     through PostgREST, so `request.jwt.claim.*` is not set.
--  ② Times are 2 days out, at least six hours apart between pins, so the ±6h clash window of
--     one pin cannot see another's rows.
--  ③ Counts are per owner+dog, never suite-wide.
--  ④ Calls expected to SUCCEED are made directly (K1's replay excepted): a mutation that makes one
--     of them raise aborts this `do` block — the harness reports 「SUITE PARSE/EXEC FAILED」 and
--     exits 1 with no `N pass / M fail` line, which reads as 「the suite never ran」 rather than as
--     「K4 broke」 (cold review #14, measured twice). Loud, but nameless; read the psql error line.
set client_min_messages = warning;

do $$
declare
  u1 uuid; u2 uuid; d1 uuid; d1b uuid; d2 uuid;
  k1 uuid := gen_random_uuid(); k2 uuid := gen_random_uuid(); k3 uuid := gen_random_uuid(); k4 uuid := gen_random_uuid();
  t0 timestamptz := now() + interval '2 days';
  j1 jsonb; j2 jsonb; j3 jsonb;
  v_id uuid; v_id2 uuid; v_n int; v_n2 int; v_bad text; v_msg text; v_st text; v_err text;
  v_oid oid; v_src text; v_acl text; v_idx text; v_upd timestamptz;
  addons constant jsonb := '[{"key":"photo","price":1000}]'::jsonb;
begin
  u1 := t_user('bhk_owner', 'owner'); u2 := t_user('bhk_stranger', 'owner');
  d1 := t_dog(u1, 'bhk-dog'); d1b := t_dog(u1, 'bhk-dog-2'); d2 := t_dog(u2, 'bhk-stranger-dog');

  -- ---------- [0179-K1] REPLAY: the same owner + key ⇒ the same row, unchanged, and no second row ----------
  v_bad := '';
  select count(*) into v_n from bookings where owner_id = u1;
  j1 := create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);
  -- the replay is the call under test, so a RAISE here is a named failure, not a suite crash: with
  -- the replay lookup deleted the belt index answers 23505 (measured, plant ii), and that must
  -- read as 「K1 red」 in the battery rather than as 「suite aborted」.
  begin
    j2 := create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);
  exception when others then
    j2 := null; v_bad := v_bad || ' replay-RAISED [' || sqlstate || ' ' || left(sqlerrm, 60) || ']';
  end;
  if (j1->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' first-unchanged=' || coalesce(j1->>'unchanged','NULL'); end if;
  if (j2->>'unchanged')::boolean is distinct from true  then v_bad := v_bad || ' replay-unchanged=' || coalesce(j2->>'unchanged','NULL'); end if;
  if (j1->>'booking_id') is distinct from (j2->>'booking_id') then v_bad := v_bad || ' replay-made-a-DIFFERENT-booking'; end if;
  if (j1->>'booking_status') is distinct from 'matching' or (j2->>'booking_status') is distinct from 'matching' then v_bad := v_bad || ' status=' || coalesce(j1->>'booking_status','NULL') || '/' || coalesce(j2->>'booking_status','NULL'); end if;
  if (j1->>'total_price')::int is distinct from 14900 or (j2->>'total_price')::int is distinct from 14900 then v_bad := v_bad || ' total=' || coalesce(j1->>'total_price','NULL'); end if;
  select count(*) into v_n2 from bookings where owner_id = u1;
  if v_n2 - v_n <> 1 then v_bad := v_bad || ' bookings +' || (v_n2 - v_n) || ' (expected +1)'; end if;
  v_id := (j1->>'booking_id')::uuid;
  select count(*) into v_n from slot_holds where booking_id = v_id;
  if v_n <> 1 then v_bad := v_bad || ' holds=' || v_n; end if;
  select status::text, client_request_id::text, total_price::text into v_st, v_msg, v_err from bookings where id = v_id;
  if v_st is distinct from 'matching' then v_bad := v_bad || ' row-status=' || coalesce(v_st,'NULL'); end if;
  if v_msg is distinct from k1::text then v_bad := v_bad || ' row-key-not-stored'; end if;
  if v_err is distinct from '14900' then v_bad := v_bad || ' row-total=' || coalesce(v_err,'NULL'); end if;
  if (j2->>'hold_expires_at') is null then v_bad := v_bad || ' replay-hold_expires_at-NULL'; end if;
  -- the replay tells the truth about what the row has BECOME
  update bookings set status = 'confirmed' where id = v_id;
  begin
    j3 := create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);
  exception when others then
    j3 := null; v_bad := v_bad || ' replay-after-confirm-RAISED [' || sqlstate || ']';
  end;
  if (j3->>'booking_status') is distinct from 'confirmed' or (j3->>'unchanged')::boolean is distinct from true then v_bad := v_bad || ' replay-after-confirm=' || coalesce(j3->>'booking_status','NULL'); end if;
  if v_bad = '' then call _pass('bhk','0179-K1 같은 소유자+같은 키 ⇒ 같은 예약 한 행(unchanged=true), 홀드 1개, 키 저장, 두 번째·세 번째 호출은 행이 된 그대로(confirmed)를 말한다');
  else v_msg := v_bad; call _fail('bhk','0179-K1 replay', v_msg); end if;

  -- ---------- [0179-K2] MISMATCH: the same key with a different slot or money payload is refused, nothing written ----------
  v_bad := '';
  select count(*) into v_n from bookings where owner_id = u1;
  select updated_at into v_upd from bookings where id = v_id;
  begin
    perform create_booking_hold_tx(u1, d1, t0, 2.5, addons, 7900, 7500, 1000, 16400, 9900, true, k1);   -- km/price changed
    v_bad := v_bad || ' km-change-ACCEPTED';
  exception when others then
    if sqlerrm <> 'request_mismatch' then v_bad := v_bad || ' km-change: [' || sqlerrm || ']'; end if;
  end;
  begin
    perform create_booking_hold_tx(u1, d1, t0 + interval '1 hour', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);   -- time changed
    v_bad := v_bad || ' time-change-ACCEPTED';
  exception when others then
    if sqlerrm <> 'request_mismatch' then v_bad := v_bad || ' time-change: [' || sqlerrm || ']'; end if;
  end;
  begin
    perform create_booking_hold_tx(u1, d1b, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);   -- another of my dogs
    v_bad := v_bad || ' dog-change-ACCEPTED';
  exception when others then
    if sqlerrm <> 'request_mismatch' then v_bad := v_bad || ' dog-change: [' || sqlerrm || ']'; end if;
  end;
  -- [cold review #2/#3] each remaining comparison field ALONE, so that deleting any one conjunct
  -- reddens this pin rather than hiding behind km's arm: the same slot with only the price moved,
  -- only the pace moved, only the minimum fare moved.
  begin
    perform create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 16400, 9900, true, k1);   -- total only
    v_bad := v_bad || ' price-only-change-ACCEPTED';
  exception when others then
    if sqlerrm <> 'request_mismatch' then v_bad := v_bad || ' price-only: [' || sqlerrm || ']'; end if;
  end;
  begin
    perform create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1, null, null, 'brisk');   -- pace only
    v_bad := v_bad || ' pace-only-change-ACCEPTED';
  exception when others then
    if sqlerrm <> 'request_mismatch' then v_bad := v_bad || ' pace-only: [' || sqlerrm || ']'; end if;
  end;
  begin
    perform create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 14900, 8900, true, k1);   -- min_fare only
    v_bad := v_bad || ' min_fare-only-change-ACCEPTED';
  exception when others then
    if sqlerrm <> 'request_mismatch' then v_bad := v_bad || ' min_fare-only: [' || sqlerrm || ']'; end if;
  end;
  -- the analytics snapshot is NOT part of the comparison: a re-derived chip is the same request
  begin
    j3 := create_booking_hold_tx(u1, d1, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1, null, null, null, null, 'carousel', null, '{"night":true}'::jsonb);
  exception when others then
    j3 := null; v_bad := v_bad || ' snapshot-replay-RAISED [' || sqlstate || ']';
  end;
  if (j3->>'unchanged')::boolean is distinct from true or (j3->>'booking_id')::uuid is distinct from v_id then v_bad := v_bad || ' snapshot-change-was-treated-as-mismatch'; end if;
  select count(*) into v_n2 from bookings where owner_id = u1;
  if v_n2 <> v_n then v_bad := v_bad || ' bookings moved by ' || (v_n2 - v_n); end if;
  if (select updated_at from bookings where id = v_id) is distinct from v_upd then v_bad := v_bad || ' original-row-touched'; end if;
  if v_bad = '' then call _pass('bhk','0179-K2 같은 키에 다른 슬롯/금액(km·시각·다른 강아지, 그리고 금액만·페이스만·최소요금만) ⇒ request_mismatch, 아무것도 안 쓰고 원래 행 그대로; 분석 스냅샷만 다른 재시도는 같은 요청(unchanged)');
  else v_msg := v_bad; call _fail('bhk','0179-K2 mismatch', v_msg); end if;

  -- ---------- [0179-K3] two keys ⇒ two bookings; a NULL key ⇒ no idempotency (the legacy contract) ----------
  v_bad := '';
  select count(*) into v_n from bookings where owner_id = u1;
  j1 := create_booking_hold_tx(u1, d1, t0 + interval '12 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k2);
  j2 := create_booking_hold_tx(u1, d1, t0 + interval '24 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k3);
  if (j1->>'booking_id') is not distinct from (j2->>'booking_id') then v_bad := v_bad || ' two-keys-ONE-booking'; end if;
  if (j1->>'unchanged')::boolean is distinct from false or (j2->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' a-fresh-key-said-unchanged(or NULL)'; end if;
  -- NULL key twice, non-overlapping ⇒ two rows (no key, no replay — exactly the pre-slice behaviour)
  j1 := create_booking_hold_tx(u1, d1, t0 + interval '36 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, null);
  j2 := create_booking_hold_tx(u1, d1, t0 + interval '48 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, null);
  if (j1->>'booking_id') is not distinct from (j2->>'booking_id') then v_bad := v_bad || ' null-keys-collided'; end if;
  select count(*) into v_n2 from bookings where owner_id = u1;
  if v_n2 - v_n <> 4 then v_bad := v_bad || ' bookings +' || (v_n2 - v_n) || ' (expected +4)'; end if;
  select count(*) into v_n2 from bookings where owner_id = u1 and client_request_id is null;
  if v_n2 <> 2 then v_bad := v_bad || ' null-key-rows=' || v_n2; end if;
  if v_bad = '' then call _pass('bhk','0179-K3 다른 키 둘 ⇒ 예약 둘; NULL 키는 멱등성 없음(옛 빌드 계약) ⇒ 겹치지 않으면 둘 다 생성');
  else v_msg := v_bad; call _fail('bhk','0179-K3 two-keys', v_msg); end if;

  -- ---------- [0179-K4] THE OVERLAP GUARD is atomic with the insert and key-independent ----------
  v_bad := '';
  select count(*) into v_n from bookings where owner_id = u1;
  begin
    perform create_booking_hold_tx(u1, d1, t0 + interval '30 minutes', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k4);   -- overlaps K1's (t0, 41 min)
    v_bad := v_bad || ' overlap-with-a-new-key-ACCEPTED';
  exception when others then
    if sqlerrm <> 'dog_slot_clash' then v_bad := v_bad || ' overlap-new-key: [' || sqlerrm || ']'; end if;
  end;
  begin
    perform create_booking_hold_tx(u1, d1, t0 - interval '20 minutes', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, null);   -- overlaps from before, no key
    v_bad := v_bad || ' overlap-with-no-key-ACCEPTED';
  exception when others then
    if sqlerrm <> 'dog_slot_clash' then v_bad := v_bad || ' overlap-no-key: [' || sqlerrm || ']'; end if;
  end;
  -- a stale payment_hold of the SAME dog must NOT block (O-5 §C.1b: a stale hold never blocks a retry)
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price)
  values (u1, d1b, 'payment_hold', t0 + interval '60 hours', 2.0, 7900, 6000, 0, 13900);
  j1 := create_booking_hold_tx(u1, d1b, t0 + interval '60 hours', 2.0, '[]'::jsonb, 7900, 6000, 0, 13900, 9900, true, gen_random_uuid());
  if (j1->>'booking_id') is null then v_bad := v_bad || ' stale-payment_hold-BLOCKED'; end if;
  -- the other dog is free at the same time (the guard is per dog)
  j2 := create_booking_hold_tx(u1, d1b, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, gen_random_uuid());
  if (j2->>'booking_id') is null then v_bad := v_bad || ' other-dog-BLOCKED'; end if;
  select count(*) into v_n2 from bookings where owner_id = u1;
  if v_n2 - v_n <> 3 then v_bad := v_bad || ' bookings +' || (v_n2 - v_n) || ' (expected +3: the fixture, d1b×2)'; end if;
  if v_bad = '' then call _pass('bhk','0179-K4 같은 강아지 겹침은 키가 있어도 없어도 dog_slot_clash, 아무것도 안 쓴다; 지난 payment_hold는 막지 않고, 다른 강아지는 같은 시각에 자유');
  else v_msg := v_bad; call _fail('bhk','0179-K4 overlap-guard', v_msg); end if;

  -- ---------- [0179-K5] PARTY gate before any read: a stranger's dog, an absent dog, a stranger's address — the same word, nothing written, even when a key would replay ----------
  v_bad := '';
  select count(*) into v_n from bookings;
  begin
    perform create_booking_hold_tx(u1, d2, t0 + interval '72 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, gen_random_uuid());
    v_bad := v_bad || ' strangers-dog-ACCEPTED';
  exception when others then
    if sqlerrm <> 'forbidden' then v_bad := v_bad || ' strangers-dog: [' || sqlerrm || ']'; end if;
  end;
  begin
    perform create_booking_hold_tx(u1, gen_random_uuid(), t0 + interval '72 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, gen_random_uuid());
    v_bad := v_bad || ' absent-dog-ACCEPTED';
  exception when others then
    if sqlerrm <> 'forbidden' then v_bad := v_bad || ' absent-dog: [' || sqlerrm || '] (must be the SAME word as a stranger''s)'; end if;
  end;
  -- ORDER: u1's existing key k1 with the STRANGER's dog — party gate first ⇒ forbidden, not request_mismatch
  begin
    perform create_booking_hold_tx(u1, d2, t0, 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);
    v_bad := v_bad || ' replay-key+strangers-dog-ACCEPTED';
  exception when others then
    if sqlerrm <> 'forbidden' then v_bad := v_bad || ' party-gate-after-replay-read: [' || sqlerrm || ']'; end if;
  end;
  -- a stranger's address
  declare v_addr uuid; begin
    insert into addresses (owner_id, label, addr, detail) values (u2, 'x', 'x', 'x') returning id into v_addr;
    begin
      perform create_booking_hold_tx(u1, d1, t0 + interval '72 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, gen_random_uuid(), null, v_addr);
      v_bad := v_bad || ' strangers-address-ACCEPTED';
    exception when others then
      if sqlerrm <> 'forbidden' then v_bad := v_bad || ' strangers-address: [' || sqlerrm || ']'; end if;
    end;
  exception when others then v_bad := v_bad || ' address-fixture-failed [' || sqlerrm || ']';
  end;
  -- [cold review #1] the replay read is scoped to the OWNER: another owner sending u1's key with
  -- their OWN dog gets a fresh booking — never u1's row, never a mismatch (an existence oracle on
  -- another owner's key). The one fixture where the scoped and the unscoped read DISAGREE.
  begin
    j1 := create_booking_hold_tx(u2, d2, t0 + interval '72 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k1);
    if (j1->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' other-owner+my-key: unchanged=' || coalesce(j1->>'unchanged','NULL') || ' (the replay read is not owner-scoped)'; end if;
    if (j1->>'booking_id')::uuid is not distinct from v_id then v_bad := v_bad || ' other-owner-got-MY-booking'; end if;
    if (select owner_id from bookings where id = (j1->>'booking_id')::uuid) is distinct from u2 then v_bad := v_bad || ' other-owner-row-not-theirs'; end if;
  exception when others then
    v_bad := v_bad || ' other-owner+my-key raised [' || sqlerrm || '] (request_mismatch here = an existence oracle)';
  end;
  -- no subject at all
  begin
    perform create_booking_hold_tx(null, d1, t0 + interval '72 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, gen_random_uuid());
    v_bad := v_bad || ' null-owner-ACCEPTED';
  exception when others then
    if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' null-owner: [' || sqlerrm || ']'; end if;
  end;
  select count(*) into v_n2 from bookings;
  if v_n2 - v_n <> 1 then v_bad := v_bad || ' bookings moved by ' || (v_n2 - v_n) || ' (expected +1: the other owner''s own booking)'; end if;
  if v_bad = '' then call _pass('bhk','0179-K5 party 게이트가 어떤 읽기보다 먼저 — 남의/없는 강아지·남의 주소는 같은 말 forbidden(리플레이 키가 있어도), 주체 없음 not_signed_in, 거절은 아무것도 안 쓴다; 리플레이 읽기는 소유자 범위(다른 소유자+내 키+자기 강아지 ⇒ 새 예약)');
  else v_msg := v_bad; call _fail('bhk','0179-K5 party-before-read', v_msg); end if;

  -- ---------- [0179-K6] ATOMICITY: a failing write anywhere rolls the whole hold back — and the key is not consumed ----------
  v_bad := '';
  select count(*) into v_n from bookings where owner_id = u1;
  create function _bhk_planted_hold_fails() returns trigger language plpgsql as $f$
    begin raise exception 'bhk_planted_hold_failure'; end $f$;
  create trigger _bhk_planted_hold_fails_tg before insert on slot_holds for each row execute function _bhk_planted_hold_fails();
  begin
    perform create_booking_hold_tx(u1, d1, t0 + interval '96 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k4);
    v_bad := v_bad || ' hold-insert-failure-did-not-raise';
  exception when others then
    if sqlerrm <> 'bhk_planted_hold_failure' then v_bad := v_bad || ' stopped-for-another-reason [' || sqlerrm || ']'; end if;   -- CONTROL: the planted raise
  end;
  drop trigger _bhk_planted_hold_fails_tg on slot_holds;
  drop function _bhk_planted_hold_fails();
  select count(*) into v_n2 from bookings where owner_id = u1;
  if v_n2 <> v_n then v_bad := v_bad || ' a-booking-SURVIVED-the-failed-hold (+' || (v_n2 - v_n) || ')'; end if;
  if exists (select 1 from bookings where owner_id = u1 and client_request_id = k4) then v_bad := v_bad || ' the-key-was-consumed'; end if;
  -- the same key now creates the booking — nothing was burned
  j1 := create_booking_hold_tx(u1, d1, t0 + interval '96 hours', 2.0, addons, 7900, 6000, 1000, 14900, 9900, true, k4);
  if (j1->>'booking_id') is null or (j1->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' retry-after-failure=' || coalesce(j1::text,'NULL'); end if;
  if v_bad = '' then call _pass('bhk','0179-K6 홀드 쓰기 하나가 실패하면 예약 행까지 되돌아간다(원인은 심은 그것), 키는 소모되지 않고 같은 키로 다시 만들어진다');
  else v_msg := v_bad; call _fail('bhk','0179-K6 atomicity', v_msg); end if;

  -- ---------- [0179-K7] the ladder, the hold row, the CAS switch ----------
  v_bad := '';
  j1 := create_booking_hold_tx(u1, d1, t0 + interval '120 hours', 3.5, '[]'::jsonb, 7900, 10500, 0, 18400, 9900, false, gen_random_uuid(), null, null, 'easy', null, 'auto', 'active', '{}'::jsonb, 7);
  v_id := (j1->>'booking_id')::uuid;
  if (j1->>'booking_status') is distinct from 'payment_hold' then v_bad := v_bad || ' close=false-status=' || coalesce(j1->>'booking_status','NULL'); end if;
  select status::text into v_st from bookings where id = v_id;
  if v_st is distinct from 'payment_hold' then v_bad := v_bad || ' row-status=' || coalesce(v_st,'NULL'); end if;
  select count(*) into v_n from slot_holds h where h.booking_id = v_id and h.runner_id is null and h.owner_id = u1
     and h.starts_at = t0 + interval '120 hours' and h.ends_at = t0 + interval '120 hours' + interval '53 minutes'   -- 3.5*8+25
     and h.expires_at between now() + interval '6 minutes' and now() + interval '8 minutes';
  if v_n <> 1 then v_bad := v_bad || ' hold-row-shape(' || v_n || ')'; end if;
  select count(*) into v_n from bookings b where b.id = v_id and b.runner_id is null and b.pace_label = 'easy' and b.selection_origin = 'auto'
     and b.route_status_at_booking = 'active' and b.km = 3.5 and b.total_price = 18400 and b.min_fare = 9900 and b.addons = '[]'::jsonb;
  if v_n <> 1 then v_bad := v_bad || ' booking-row-shape'; end if;
  if ((j1->>'hold_expires_at') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$') is distinct from true then v_bad := v_bad || ' hold_expires_at-shape=' || coalesce(j1->>'hold_expires_at','NULL'); end if;
  -- [cold review #7] a replay that ASKS to close a payment_hold row closes it — same id, unchanged
  -- (nothing new was created), status matching — instead of echoing the strand back
  begin
    j2 := create_booking_hold_tx(u1, d1, t0 + interval '120 hours', 3.5, '[]'::jsonb, 7900, 10500, 0, 18400, 9900, true, (select client_request_id from bookings where id = v_id), null, null, 'easy');
  exception when others then
    j2 := null; v_bad := v_bad || ' close-on-replay-RAISED [' || sqlstate || ']';
  end;
  if (j2->>'booking_id')::uuid is distinct from v_id or (j2->>'unchanged')::boolean is distinct from true then v_bad := v_bad || ' close-on-replay=' || coalesce(j2::text,'NULL'); end if;
  if (j2->>'booking_status') is distinct from 'matching' or (select status::text from bookings where id = v_id) is distinct from 'matching' then v_bad := v_bad || ' payment_hold-replay-did-not-close(' || coalesce(j2->>'booking_status','NULL') || ')'; end if;
  if v_bad = '' then call _pass('bhk','0179-K7 close_to_matching=false ⇒ payment_hold 그대로; 홀드 행(러너 없음·km*8+25분·만료 p_hold_minutes)·예약 행(전달한 요금·페이스·스냅샷) 그대로; hold_expires_at는 ISO-Z; 같은 키로 close=true 리플레이 ⇒ 같은 행이 matching으로 닫힌다');
  else v_msg := v_bad; call _fail('bhk','0179-K7 ladder-and-hold', v_msg); end if;

  -- ---------- [0179-K8] deployed shape: the column, the PARTIAL UNIQUE index (as a belt, exercised), the definer, source ORDER ----------
  v_bad := '';
  -- the belt is real: two direct inserts with the same (owner, key) collide; NULL keys do not
  declare kk uuid := gen_random_uuid(); begin
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, client_request_id)
    values (u1, d1, 'draft', t0 + interval '200 hours', 2.0, 7900, 6000, 0, 13900, kk);
    begin
      insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, client_request_id)
      values (u1, d1, 'draft', t0 + interval '210 hours', 2.0, 7900, 6000, 0, 13900, kk);
      v_bad := v_bad || ' duplicate-(owner,key)-INSERTED';
    exception when unique_violation then null;
           when others then v_bad := v_bad || ' belt: [' || sqlstate || ']'; end;
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, client_request_id)
    values (u1, d1, 'draft', t0 + interval '220 hours', 2.0, 7900, 6000, 0, 13900, null);
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, client_request_id)
    values (u1, d1, 'draft', t0 + interval '230 hours', 2.0, 7900, 6000, 0, 13900, null);
  exception when others then v_bad := v_bad || ' belt-fixture [' || sqlerrm || ']'; end;
  select pg_get_indexdef(i.indexrelid) into v_idx from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'bookings_owner_client_request_uni';
  if v_idx is null then v_bad := v_bad || ' NO-INDEX';
  else
    if (v_idx ~ '\(owner_id, client_request_id\)') is distinct from true then v_bad := v_bad || ' index-columns'; end if;
    if (v_idx ~* 'where \(?client_request_id is not null\)?') is distinct from true then v_bad := v_bad || ' index-not-partial'; end if;
    if (select indisunique from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'bookings_owner_client_request_uni') is distinct from true then v_bad := v_bad || ' index-not-unique'; end if;
  end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'create_booking_hold_tx';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' ACL 기본값'; end if;
    select array_to_string(proacl, ',') into v_acl from pg_proc where oid = v_oid;
    if (coalesce(v_acl,'') ~ '(^|,)=[^/]*X') is distinct from false then v_bad := v_bad || ' PUBLIC 실행'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' authenticated 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE';
    else
      if (v_src ~ '''forbidden''' and v_src ~ '''request_mismatch''' and v_src ~ '''dog_slot_clash''' and v_src ~ '''hold_close_failed''') is distinct from true then v_bad := v_bad || ' 토큰 누락'; end if;
      if (position('''forbidden''' in v_src) > 0 and position('''forbidden''' in v_src) < position('pg_advisory_xact_lock' in v_src)) is distinct from true then v_bad := v_bad || ' party 게이트가 락 뒤'; end if;
      if (position('pg_advisory_xact_lock' in v_src) > 0 and position('pg_advisory_xact_lock' in v_src) < position('client_request_id = p_client_request_id' in v_src)) is distinct from true then v_bad := v_bad || ' 락이 리플레이 읽기 뒤'; end if;
      if (position('booking_hold_key:' in v_src) > 0 and position('booking_hold_key:' in v_src) < position('booking_hold_dog:' in v_src)) is distinct from true then v_bad := v_bad || ' 락 순서(키→강아지) 아님'; end if;
      if (position('''dog_slot_clash''' in v_src) > 0 and position('''dog_slot_clash''' in v_src) < position('insert into bookings' in v_src)) is distinct from true then v_bad := v_bad || ' 겹침 가드가 insert 뒤'; end if;
      if (v_src ~* 'exception\s+when') is distinct from false then v_bad := v_bad || ' 예외 핸들러(원자성)'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('bhk','0179-K8 배포 형태 — 열·부분 UNIQUE 인덱스(직접 중복 insert가 23505, NULL 키는 충돌 없음)·definer·search_path·ACL(service_role만)·소스 순서 party→락(키→강아지)→리플레이 읽기, 겹침 가드→insert, 예외 핸들러 없음');
  else v_msg := v_bad; call _fail('bhk','0179-K8 shape', v_msg); end if;
end $$;
