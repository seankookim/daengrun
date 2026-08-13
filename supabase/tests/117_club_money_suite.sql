-- ═══ 117 club-money suite — 0081 pins (the third booking-creating path learns about money) ═══
-- Purpose: 0080 gated create-booking-hold and generate_recurring_bookings and named the club
--   delegation insert as an explicit exclusion (0080:657-665). 0081 closes it with the SAME two
--   gates, inside a function that four migrations have already recreated — so half of what these
--   pins protect is not the new code at all: it is the promise that the reproduction changed
--   nothing else. The club pilot is running on this RPC today.
-- Style: sibling of 105-116 — `_pass('cmg',…)`/`_fail('cmg',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   Money facts are asserted against LITERALS (105's law): t_route is 5.0km, so the club quote
--   is club_fare(5.0) = 9,900 + 15,000 = 24,900 and every fare column below is written out.
-- ⚠ The cutover switch ships NULL and 116 restores NULL as its last act, so this suite starts
--   pre-cutover — which is the era K1/K2/K3 measure. K4, K5 and K6 each set it for themselves
--   (never inheriting it from a sibling pin), K5's second arm turns it off again, and the
--   suite's final line restores the shipped NULL — this suite runs last, and leaving it set
--   would be a lie about the shipped state for anyone reading the database afterwards.
-- ⚠ This suite enables `club_delegation_v2` (50 already does; repeated here so 117 does not
--   depend on suite order for a feature flag).
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   K1  ← §A-ⓑ: delete the `owner_has_unsettled_charge` gate — a locked owner keeps minting
--         club fares that nothing can collect, which is precisely the exclusion 0080 §H
--         named and this file exists to close                                          → RED
--   K2  ← §A-ⓑ: notify the owner (or anyone) BEFORE the raise instead of refusing with a
--         bare exception — the insert rolls back with the transaction, so the pin measures
--         the rollback (no booking, no attempt row, no consent stamp, hold intact) and the
--         host's silence. Also RED if the refusal is downgraded to `return null`, which the
--         client reads as success.                                                     → RED
--   K3  ← §A: any drift in the reproduced 0053 body — the fare decomposition, the booking
--         status, `club_session_id`, the hold consumption, the payment_attempts idempotence
--         row, or the consent stamp. THE behavior-preservation pin: it runs with the switch
--         NULL, i.e. exactly today's pilot, and a card-less owner must sail straight through.
--   K4  ← §A-ⓒ: drop `v_live and` from the instrument gate (card-less pilot owners are
--         refused BEFORE the cutover — today's flow broken), or delete the gate entirely
--         (a post-cutover seat is confirmed for an owner we cannot charge)             → RED
--   K5  ← §A-ⓑ: make the DEBT gate flag-keyed (`v_live and owner_has_unsettled_charge(…)`)
--         — debt is true in every era and 0080 §0c says so; a flag-keyed debt gate reopens
--         the hole for the whole pre-cutover pilot                                     → RED
--   K6  ← §B: revert the confirmation copy to '결제 완료 — 자리 확정' / '위탁 결제 완료'
--         (a payment claim in an era where nothing is charged, and in the era where the
--         charge happens LATER), or drop the post-cutover '러닝이 끝난 뒤 결제' clause so
--         the two eras say the same thing                                              → RED
--   K7  ← §A: change one fare column without the others (e.g. base 7900 with total still
--         club_fare) — base + distance + addon must equal total_price on a club booking,
--         because 0080 §D charges from exactly those frozen columns                    → RED
--       ⚠ [P3-1, 2026-08-13] This entry once also claimed a `total_price = club_fare(km)`
--         arm. That arm was a tautology — total_price was written BY club_fare in the same run,
--         so a club_fare value change (memo ④'s exact proposal) could never redden it. Retired;
--         the value is anchored by the literal arm only, the decomposition by the sum arm.
--   K8  ← §C: drop the `revoke execute on club_fare from public, anon` (the pricing formula
--         is callable with the app's anon key), or revoke it from `authenticated` too
--         (0057 §1's capture-and-restore rule silently broken)                         → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13 (clean cluster each time — server
--     stopped before `rm -rf .pgtest`, or the orphaned postgres holds a deleted socket path and
--     the next run dies at the shim; restore → 438/0 every time). Green = 438/0 (430 baseline
--     + K1-K8). Four reverts, measured:
--       ⓐ §A-ⓑ debt gate deleted → **435/3, red = [K1, K2, K5]** (re-measured 2026-08-13 after
--         the P2-1 repair below). K1's refusal probe succeeds (detail `not_payable` — the
--         unrefused call consumed its own seat, so K1's positive control then hits the state
--         gate); K2 reports `두 번째 미수금 결제가 통과` + `거부 코드=∅`, i.e. it now observes the
--         gate itself failing to fire; K5 measures the same hole from the post-cutover side
--         (`카드 있는 미수금 보호자 통과`). K3/K4/K6/K7 stay GREEN — that separation is why
--         K3 pays its own seat (see the seed comment).
--         ⚠ WHAT THIS ENTRY USED TO SAY, and why the correction matters more than the fix:
--         K2 previously probed `sd_a`, a seat K1's positive control had already paid, so the
--         call died at the state gate 24 lines BEFORE the money gates and every K2 assertion
--         was satisfied by that unrelated `not_payable`. It still went red under this very
--         mutation — but only because K1's failure rolled back K1's own block and un-paid the
--         seat, restoring the fixture K2 needed. **A pin can be mutation-proven and still be
--         measuring another pin's failure mode.** Found by the 2026-08-13 adversarial round
--         (P2-1) by instrumenting the gate with `raise warning` and counting evaluations:
--         53 gate traversals across the harness, none of them K2's.
--       ⓑ §A-ⓒ instrument gate deleted entirely → **437/1, red = [K4]** (detail `not_payable`:
--         the card-less post-cutover call goes through and consumes the seat the ⓒ arm needed).
--         K5/K6 stay green only because they provision their own switch and card — they did NOT
--         in the first draft of this suite, and this revert reddened all three.
--       ⓒ §B copy reverted to 0053's '결제 완료 — 자리 확정' / '위탁 결제 완료' →
--         **436/2, red = [K6, K2]**. K6 by design (`컷오버 전 본문=0 … 호스트에게 결제 완료
--         주장 5건`); K2 genuinely, because its host-silence assertion is the same property from
--         the other side (`호스트에게 돈 얘기가 갔다`).
--       ⓓ §A-ⓒ `v_live and` dropped (the gate stops being switch-keyed) → the harness ABORTS,
--         it does not merely go red: `❌ SUITE PARSE/EXEC FAILED: 60_custody_suite.sql —
--         ERROR: billing_key_required` at 60:289. No totals are produced and 117 never runs.
--         That is the strongest available statement of what this arm protects: a pre-cutover
--         instrument gate breaks the club pilot flow so completely that a 2026-07 suite dies on
--         a top-level error. Recorded here because K4's own probe cannot report it.
--     The remaining pins (K3, K7, K8) are NOT machine-proven; each is named above with the single
--     revert that would redden it, and their probe shapes are clones of proven siblings (116
--     C13/C14 for the two gates, 116 C17/C18 for conditional copy, 111 N7 for the ACL probe).
--   ⚠ HONESTY NOTE: K2 cannot distinguish "no notification was written" from "a notification
--     was written and rolled back" — that is the same transaction, and from outside it there is
--     no difference. That is the point (0044 §① is the argument), but it means K2 pins the
--     OUTCOME (nobody is told, nothing is left behind), not the absence of the insert. An author
--     who adds a doomed notification insert before the raise gets a green harness and a dead
--     line of code; only the comment at §A-ⓑ warns them.
--   ⚠ HONESTY NOTE: the client-side half of the refusal — translating `unsettled_charge` /
--     `billing_key_required` into Korean at app/app/club/session/[sid].tsx:613-617 — exists
--     (added app-side in the same session) but has NO pin here and cannot have one: it is
--     TypeScript, and this harness only sees SQL. K1/K4/K5 assert the CODES, which is exactly
--     the surface that file matches on; if a code is renamed here and not there, nothing in
--     this suite goes red and the owner gets the raw string. That gap is structural.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- Debt in the only shape §F recognises: a booking that SETTLED (runs.ended_at) carrying a
-- server-minted `failed` charge row. Returns the payments id so the pin can delete it and
-- prove the same call succeeds once the debt is gone (a gate with no positive control is a
-- fixture that might simply be broken).
create or replace function t_cmg_debt(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v_b uuid; v_p uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'completed', now() - interval '3 hours', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v_b;
  insert into runs (booking_id, started_at, ended_at, actual_km, end_reason)
  values (v_b, now() - interval '3 hours', now() - interval '2 hours', 5.0, 'completed');
  insert into payments (booking_id, order_id, amount, status, raw)
  values (v_b, 'ord_cmg_' || v_b::text, 24900, 'failed',
          jsonb_build_object('kind','settle_charge','attempts',3))
  returning id into v_p;
  return v_p;
end $$;

do $$
declare
  hh uuid; r2 uuid; oa uuid; ob uuid; dbt_dog uuid;
  da uuid; da2 uuid; da3 uuid; db1 uuid; db2 uuid; db3 uuid; db4 uuid; rt uuid;
  v_club uuid; s1 uuid; s2 uuid;
  sd_a uuid; sd_a2 uuid; sd_a3 uuid; sd_b1 uuid; sd_b2 uuid; sd_b3 uuid; sd_b4 uuid;
  p_debt uuid; b_a uuid; b_card uuid; b_pre uuid; b_post uuid;
  v_bad text := ''; v_msg text; v_n int; v_pre int; v_err text;
begin
  -- ---------- seed ----------
  -- 0044 §③ allowlist is not used: the global flag is the switch every other club suite uses,
  -- and 50 already turns it on. Repeated so this suite stands alone if the order ever changes.
  update club_flags set enabled = true where name = 'club_delegation_v2';

  hh := t_user('cmg_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  r2 := t_user('cmg_r2', 'runner'); update runners set tier = 'veteran' where profile_id = r2;
  oa := t_user('cmg_oa', 'owner'); ob := t_user('cmg_ob', 'owner');
  da := t_dog(oa, '미수금견'); da2 := t_dog(oa, '보존견'); da3 := t_dog(oa, '흔적견');
  dbt_dog := t_dog(oa, '지난러닝견');
  db1 := t_dog(ob, '카드견1'); db2 := t_dog(ob, '카드견2');
  db3 := t_dog(ob, '카드견3'); db4 := t_dog(ob, '카피견');
  rt := t_route('클럽머니 코스');                      -- 5.0km → club_fare = 24,900

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('클럽머니동');
  perform club_claim_host(v_club);
  -- two sessions, two veterans committed to each → delegated capacity 4 per session (a single
  -- certified runner's cap of 1 would make the approvals below fail for capacity reasons and
  -- every pin would go red for the wrong reason).
  s1 := club_create_session(v_club, now() + interval '30 hours', '머니 집결지1', rt, 8, 'mixed');
  s2 := club_create_session(v_club, now() + interval '54 hours', '머니 집결지2', rt, 8, 'mixed');
  perform session_runner_commit(s1); perform session_runner_commit(s2);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_runner_commit(s1); perform session_runner_commit(s2);

  perform set_config('request.jwt.claim.sub', oa::text, false);
  sd_a := session_delegate_dog(s1, da, t_consent());
  -- K3 (behavior preservation) deliberately pays a DIFFERENT dog than K1 probes. When the debt
  -- gate is deleted, K1's refusal probe succeeds and consumes its own session_dog; if K3 read
  -- that same seat it would go red as collateral and the mutation signature would stop naming
  -- the rule that actually broke (110's dead-pin lesson, inverted).
  sd_a2 := session_delegate_dog(s1, da2, t_consent());
  -- [adversarial round 2026-08-13, P2-1] K2 needs its OWN unconsumed seat. It used to probe
  -- sd_a, which K1's positive control had already paid — so K2's call died at the state gate
  -- (`not_payable`, 0081:151) 24 lines before the money gates, and every assertion it makes
  -- was satisfied by that unrelated refusal. It still went red under the debt-gate mutation,
  -- but only as a subtransaction artifact: K1's own failure rolled its block back and
  -- un-paid sd_a, restoring the fixture K2 depended on. A pin that measures another pin's
  -- failure mode is not a pin.
  sd_a3 := session_delegate_dog(s1, da3, t_consent());
  perform set_config('request.jwt.claim.sub', ob::text, false);
  sd_b1 := session_delegate_dog(s2, db1, t_consent());
  sd_b2 := session_delegate_dog(s2, db2, t_consent());
  sd_b3 := session_delegate_dog(s2, db3, t_consent());
  sd_b4 := session_delegate_dog(s2, db4, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sd_a, true);
  perform session_approve_dog(sd_a2, true);
  perform session_approve_dog(sd_a3, true);
  perform session_approve_dog(sd_b1, true);
  perform session_approve_dog(sd_b2, true);
  perform session_approve_dog(sd_b3, true);
  perform session_approve_dog(sd_b4, true);
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- [K1] the debt gate — a locked owner cannot confirm a club seat ----------
  -- 0080 §H's excluded path, closed. The positive control (clear the debt, same call succeeds)
  -- is what makes this a gate pin rather than a broken-fixture pin.
  begin
    v_bad := '';
    p_debt := t_cmg_debt(oa, dbt_dog, rt, hh);
    if not owner_has_unsettled_charge(oa) then v_bad := v_bad || ' 픽스처: 미수금이 생기지 않았다'; end if;

    perform set_config('request.jwt.claim.sub', oa::text, false);
    v_err := '';
    begin
      perform session_pay_delegation(sd_a, 'idem-cmg-k1', true);
      v_bad := v_bad || ' 미수금 보호자 결제 통과';
    exception when others then v_err := sqlerrm;
    end;
    if v_err <> 'unsettled_charge' then v_bad := v_bad || ' 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;
    select count(*) into v_n from bookings where dog_id = da;
    if v_n <> 0 then v_bad := v_bad || ' 거부됐는데 부킹 ' || v_n || '행'; end if;

    -- positive control: the ONLY thing standing between this owner and a booking was the debt
    delete from payments where id = p_debt;
    if owner_has_unsettled_charge(oa) then v_bad := v_bad || ' 미수금이 안 지워졌다'; end if;
    b_a := session_pay_delegation(sd_a, 'idem-cmg-k1b', true);
    perform set_config('request.jwt.claim.sub', '', false);
    if b_a is null then v_bad := v_bad || ' 미수금 해소 후에도 결제 실패'; end if;

    if v_bad = ''
      then call _pass('cmg','K1 미수금 게이트 — 잠긴 보호자는 unsettled_charge로 거부되고 부킹 0행, 미수금을 지우면 같은 호출이 통과 (0080 §H가 명시한 제외 경로)');
    else v_msg := v_bad; call _fail('cmg','K1 미수금 게이트', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('cmg','K1 미수금 게이트', v_msg);
  end;

  -- ---------- [K2] the refusal leaves NOTHING behind, and tells the host nothing ----------
  -- The caller is the owner (0053:51 `not_owner`), so the exception IS the message and no
  -- notification is written — a raise would roll it back anyway (0044 §①). What must hold is
  -- that a refused attempt is invisible: the seat is still held, the idempotency key is unused
  -- (so a later retry is a fresh attempt, not a replayed success), the consent stamp is
  -- unwritten, and the host — who is not a party to this owner's money — hears nothing.
  begin
    v_bad := '';
    p_debt := t_cmg_debt(oa, dbt_dog, rt, hh);          -- lock the owner again
    select count(*) into v_pre from notifications where profile_id = hh;

    perform set_config('request.jwt.claim.sub', ob::text, false);
    v_err := '';
    begin
      perform session_pay_delegation(sd_b1, 'idem-cmg-k2-clean', true);   -- (see below)
      v_err := 'ok';
    exception when others then v_err := sqlerrm;
    end;
    -- ob has no debt: this call must SUCCEED. It is here so the notification delta measured
    -- below is a real number and not zero-because-nothing-happened.
    if v_err <> 'ok' then v_bad := v_bad || ' 깨끗한 보호자가 거부됨=' || v_err; end if;

    perform set_config('request.jwt.claim.sub', oa::text, false);
    v_err := '';
    begin
      perform session_pay_delegation(sd_a3, 'idem-cmg-k2', true);
      v_bad := v_bad || ' 두 번째 미수금 결제가 통과';
    exception when others then v_err := sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓐ 거부의 흔적 없음 (전량 롤백)
    if exists (select 1 from payment_attempts where session_dog_id = sd_a3 and idempotency_key = 'idem-cmg-k2')
      then v_bad := v_bad || ' 거부인데 payment_attempts 행이 남았다'; end if;
    -- ⓑ 호스트는 아무것도 듣지 않는다 (성공한 ob의 알림 1건만 늘었어야 한다)
    select count(*) into v_n from notifications where profile_id = hh;
    if (v_n - v_pre) <> 1 then v_bad := v_bad || ' 호스트 알림 델타=' || (v_n - v_pre) || ' (성공 1건만)'; end if;
    if exists (select 1 from notifications where profile_id = hh and body like '%결제%')
      then v_bad := v_bad || ' 호스트에게 돈 얘기가 갔다'; end if;
    -- ⓒ 거부는 예외다 — 코드에 한글이 없고(클라 매핑용), 돈 사정을 문장으로 흘리지 않는다
    if v_err !~ '^[a-z_]+$' then v_bad := v_bad || ' 거부 코드 형식=' || v_err; end if;
    -- ⓓ 그리고 그 코드는 **미수금** 코드여야 한다. 이 줄이 없으면 어떤 이유의 거부든 이 핀을
    -- 통과시킨다 — 실제로 그랬다 (P2-1: 소진된 좌석의 not_payable이 이 핀을 만족시켰다).
    if v_err <> 'unsettled_charge' then v_bad := v_bad || ' 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;

    delete from payments where id = p_debt;
    if v_bad = ''
      then call _pass('cmg','K2 거부의 흔적 — 전량 롤백(payment_attempts 없음)·호스트 알림 델타는 성공 1건뿐·거부는 한글 없는 예외 코드 (0044 §①: raise는 알림도 되돌린다)');
    else v_msg := v_bad; call _fail('cmg','K2 거부의 흔적', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('cmg','K2 거부의 흔적', v_msg);
  end;

  -- ---------- [K3] behavior preservation — today's pilot flow, byte for byte ----------
  -- Its own seat (sd_a2), paid with the switch NULL and no billing key anywhere: the shipped
  -- pre-cutover world, on an owner with no debt. Every fare column is a literal (105's law) —
  -- 5.0km club_fare is 9,900 + 15,000 = 24,900 — so a reproduction that quietly rewrote the
  -- price cannot pass.
  begin
    v_bad := '';
    if (select f.payments_live_since from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' 전제 오염: 스위치가 이미 켜져 있다'; end if;
    if exists (select 1 from billing_keys where profile_id = oa)
      then v_bad := v_bad || ' 전제 오염: 이 보호자에게 카드가 있다'; end if;
    if owner_has_unsettled_charge(oa)
      then v_bad := v_bad || ' 전제 오염: 미수금이 남아 있다'; end if;

    perform set_config('request.jwt.claim.sub', oa::text, false);
    b_pre := session_pay_delegation(sd_a2, 'idem-cmg-k3', true);
    perform set_config('request.jwt.claim.sub', '', false);

    select count(*) into v_n from bookings b
    where b.id = b_pre and b.status = 'matching' and b.runner_id is null
      and b.club_session_id = s1 and b.owner_id = oa and b.dog_id = da2
      and b.km = 5.0 and b.addons = '[]'::jsonb
      and b.base_fare = 9900 and b.distance_fare = 15000 and b.addon_fare = 0
      and b.total_price = 24900 and b.min_fare = 9900;
    if v_n <> 1 then v_bad := v_bad || ' 부킹 형상 불일치'; end if;
    if (select hold_status from session_dogs where id = sd_a2) <> 'consumed'
      then v_bad := v_bad || ' 홀드 미소모'; end if;
    if (select booking_id from session_dogs where id = sd_a2) is distinct from b_pre
      then v_bad := v_bad || ' session_dogs.booking_id 미연결'; end if;
    if not exists (select 1 from payment_attempts where session_dog_id = sd_a2
                   and kind = 'charge' and idempotency_key = 'idem-cmg-k3' and result = 'ok'
                   and booking_id = b_pre)
      then v_bad := v_bad || ' payment_attempts 성공행 없음'; end if;
    if not exists (select 1 from delegation_consents where session_dog_id = sd_a2 and method_consent)
      then v_bad := v_bad || ' 동의 박제(감사 9) 유실'; end if;
    -- 멱등 재전송 — 같은 키는 같은 부킹, 새 부킹 없음
    perform set_config('request.jwt.claim.sub', oa::text, false);
    if session_pay_delegation(sd_a2, 'idem-cmg-k3', true) is distinct from b_pre
      then v_bad := v_bad || ' 멱등 재전송이 다른 값'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    select count(*) into v_n from bookings where dog_id = da2;
    if v_n <> 1 then v_bad := v_bad || ' 같은 강아지 부킹 수=' || v_n; end if;

    if v_bad = ''
      then call _pass('cmg','K3 컷오버 전 동작 보존 — 카드 없는 보호자가 그대로 통과, 부킹 형상(matching·club_session_id·9900/15000/0/24900/9900)·홀드 consumed·멱등 재전송·동의 박제 전부 0053 그대로');
    else v_msg := v_bad; call _fail('cmg','K3 컷오버 전 동작 보존', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('cmg','K3 컷오버 전 동작 보존', v_msg);
  end;

  -- ---------- [K4] the instrument gate is SWITCH-KEYED (116 C14's shape, club side) ----------
  -- ⓐ switch NULL + no card → proceeds (that is K2's sd_b1 booking, already made)
  -- ⓑ switch set + no card → refused, nothing created
  -- ⓒ card linked      → the same session_dog pays
  begin
    v_bad := '';
    if exists (select 1 from billing_keys where profile_id = ob)
      then v_bad := v_bad || ' 픽스처 오염: 이미 카드 있음'; end if;
    if (select booking_id from session_dogs where id = sd_b1) is null
      then v_bad := v_bad || ' ⓐ 컷오버 전 카드 없이 결제 실패'; end if;

    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
    perform set_config('request.jwt.claim.sub', ob::text, false);
    v_err := '';
    begin
      perform session_pay_delegation(sd_b2, 'idem-cmg-k4b', true);
      v_bad := v_bad || ' ⓑ 카드 없이 컷오버 후 결제 통과';
    exception when others then v_err := sqlerrm;
    end;
    if v_err <> 'billing_key_required' then v_bad := v_bad || ' ⓑ 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;
    if (select booking_id from session_dogs where id = sd_b2) is not null
      then v_bad := v_bad || ' ⓑ 거부인데 부킹 생성'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    insert into billing_keys (profile_id, billing_key, card)
    values (ob, 'bkey_cmg_ob', jsonb_build_object('brand','신한','last4','7777'));
    perform set_config('request.jwt.claim.sub', ob::text, false);
    b_card := session_pay_delegation(sd_b2, 'idem-cmg-k4c', true);
    perform set_config('request.jwt.claim.sub', '', false);
    if b_card is null or (select status::text from bookings where id = b_card) <> 'matching'
      then v_bad := v_bad || ' ⓒ 카드 연결 후에도 결제 안 됨'; end if;

    if v_bad = ''
      then call _pass('cmg','K4 결제수단 게이트 — payments_live_since가 NULL이면 카드 없이도 오늘처럼 확정, 설정되면 billing_key_required로 거부(부킹 0행), 카드 연결 시 재개');
    else v_msg := v_bad; call _fail('cmg','K4 결제수단 게이트', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('cmg','K4 결제수단 게이트', v_msg);
  end;

  -- ---------- [K5] the DEBT gate is NOT flag-keyed — it is true in every era ----------
  -- 0080 §0c drew this line explicitly: the instrument gate keys on the cutover moment, the debt
  -- gate does not. Probed from the post-cutover side with a CARDED owner, so the only thing that
  -- can refuse is the debt itself. Switch and card are (re)provisioned here rather than inherited
  -- from K4: a pin that needs a sibling pin to have succeeded reports the sibling's failure, not
  -- its own rule (the coupling this suite's own mutation run measured, and removed).
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
    insert into billing_keys (profile_id, billing_key, card)
    values (ob, 'bkey_cmg_ob', jsonb_build_object('brand','신한','last4','7777'))
    on conflict (profile_id) do nothing;
    p_debt := t_cmg_debt(ob, db3, rt, hh);
    perform set_config('request.jwt.claim.sub', ob::text, false);
    v_err := '';
    begin
      perform session_pay_delegation(sd_b3, 'idem-cmg-k5', true);
      v_bad := v_bad || ' 카드 있는 미수금 보호자 통과';
    exception when others then v_err := sqlerrm;
    end;
    if v_err <> 'unsettled_charge' then v_bad := v_bad || ' 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;

    -- and OFF, with the debt still there, it still refuses (that is the "every era" half)
    perform set_config('request.jwt.claim.sub', '', false);
    update ops_flags set payments_live_since = null, updated_at = now();
    perform set_config('request.jwt.claim.sub', ob::text, false);
    v_err := '';
    begin
      perform session_pay_delegation(sd_b3, 'idem-cmg-k5-off', true);
      v_bad := v_bad || ' 컷오버 전에는 미수금이 통과';
    exception when others then v_err := sqlerrm;
    end;
    if v_err <> 'unsettled_charge' then v_bad := v_bad || ' OFF 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;
    if (select booking_id from session_dogs where id = sd_b3) is not null
      then v_bad := v_bad || ' 거부인데 부킹 생성'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    delete from payments where id = p_debt;

    if v_bad = ''
      then call _pass('cmg','K5 미수금 게이트는 시대 무관 — 카드가 있어도, 스위치가 꺼져 있어도 미수금이면 거부 (0080 §0c: 계기 게이트만 플래그 키)');
    else v_msg := v_bad; call _fail('cmg','K5 미수금 게이트 시대 무관', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('cmg','K5 미수금 게이트 시대 무관', v_msg);
  end;

  -- ---------- [K6] the confirmation copy tells the truth in BOTH eras ----------
  -- b_pre was confirmed with the switch NULL (nothing is ever charged for club in that era);
  -- b_post is confirmed HERE with it set (the charge happens after the run — settle-run → mint).
  -- Neither may claim a completed payment, and the host's line may not mention money at all.
  -- Own seat, own switch, own card, for the same reason K5 provisions its own.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
    insert into billing_keys (profile_id, billing_key, card)
    values (ob, 'bkey_cmg_ob', jsonb_build_object('brand','신한','last4','7777'))
    on conflict (profile_id) do nothing;
    perform set_config('request.jwt.claim.sub', ob::text, false);
    b_post := session_pay_delegation(sd_b4, 'idem-cmg-k6', true);
    perform set_config('request.jwt.claim.sub', '', false);

    select count(*) into v_n from notifications
      where ref_id = b_pre and kind = 'booking' and title = '자리 확정'
        and body like '%위탁이 확정됐어요 — 담당 러너는 집결지에서 배정돼요'
        and body not like '%결제%';
    if v_n <> 1 then v_bad := v_bad || ' 컷오버 전 본문=' || v_n; end if;
    select count(*) into v_n from notifications
      where ref_id = b_post and kind = 'booking' and title = '자리 확정'
        and body like '%담당 러너는 집결지에서 배정돼요 · 이용료는 러닝이 끝난 뒤 결제돼요';
    if v_n <> 1 then v_bad := v_bad || ' 컷오버 후 본문=' || v_n; end if;
    select count(*) into v_n from notifications
      where ref_id in (b_pre, b_post) and body like '%결제 완료%';
    if v_n <> 0 then v_bad := v_bad || ' 결제 완료 주장 ' || v_n || '건'; end if;
    -- 호스트 라인: 돈 얘기 없음, 두 시대 모두
    select count(*) into v_n from notifications
      where profile_id = hh and title = '위탁 자리 확정' and body = '위탁 강아지의 자리가 확정됐어요';
    if v_n < 2 then v_bad := v_bad || ' 호스트 자리 확정 알림=' || v_n || ' (성공 결제마다 1건)'; end if;
    select count(*) into v_n from notifications where profile_id = hh and title = '위탁 결제 완료';
    if v_n <> 0 then v_bad := v_bad || ' 호스트에게 결제 완료 주장 ' || v_n || '건'; end if;

    if v_bad = ''
      then call _pass('cmg','K6 확정 카피 조건부 — 컷오버 전엔 "자리 확정"만, 뒤엔 "이용료는 러닝이 끝난 뒤 결제돼요"·"결제 완료"는 어느 시대에도 없음·호스트 라인은 돈 언급 없음 (0080 §J 기법)');
    else v_msg := v_bad; call _fail('cmg','K6 확정 카피 조건부', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('cmg','K6 확정 카피 조건부', v_msg);
  end;

  -- ---------- [K7] the club fare decomposition stays internally consistent ----------
  -- 0080 §D builds the settle charge from base_fare / distance_fare / addon_fare / km — the
  -- booking's own frozen columns. If a later club_fare change touches total_price without the
  -- parts (or the reverse), the quote and the charge silently diverge. This is the pin that
  -- makes memo ④'s price decision safe to execute later: change the formula, and the parts must
  -- move with it or this goes red.
  begin
    v_bad := '';
    select count(*) into v_n from bookings b
    where b.club_session_id in (s1, s2)
      and b.base_fare + b.distance_fare + b.addon_fare <> b.total_price;
    if v_n <> 0 then v_bad := v_bad || ' 분해 불일치 ' || v_n || '행'; end if;
    -- [adversarial round 2026-08-13, P3-1] 여기 있던 `total_price <> club_fare(km)` 팔은
    -- 동어반복이었다: total_price를 그 함수로 쓴 게 같은 실행의 같은 함수라, club_fare 값이
    -- 바뀌어도(=메모 ④가 검토하는 바로 그 변경) 절대 발화하지 않는다. 값을 붙잡는 것은
    -- 아래 리터럴 팔뿐이고, 분해 정합성은 위 팔이 본다. 뮤테이션 맵에서도 이 주장을 뺐다.
    -- and the club booking is a full-distance charge of exactly the quote (0080 §D, 'completed'
    -- at planned km) — the property that makes club/marketplace drift a PRICE question
    select count(*) into v_n from bookings b where b.id = b_pre and b.total_price = 24900;
    if v_n <> 1 then v_bad := v_bad || ' 5km 클럽 견적 ≠ 24900'; end if;

    if v_bad = ''
      then call _pass('cmg','K7 클럽 요금 분해 — base+distance+addon = total_price = club_fare(km) (0080 §D가 청구하는 동결 컬럼들, 나중의 가격 변경이 조용히 어긋날 수 없다)');
    else v_msg := v_bad; call _fail('cmg','K7 클럽 요금 분해', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('cmg','K7 클럽 요금 분해', v_msg);
  end;

  -- ---------- [K8] club_fare's ACL — anon cannot ask, authenticated still can ----------
  -- 0057 §1 swept only definer functions, so this pure formula kept PostgREST's PUBLIC default.
  -- 111 N7's probe shape; the second half is 0057 §1's capture-and-restore rule (authenticated
  -- held it through PUBLIC, so it keeps it explicitly).
  begin
    v_bad := '';
    if has_function_privilege('anon', 'club_fare(numeric)', 'execute')
      then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('public', 'club_fare(numeric)', 'execute')
      then v_bad := v_bad || ' public 실행 가능'; end if;
    if not has_function_privilege('authenticated', 'club_fare(numeric)', 'execute')
      then v_bad := v_bad || ' authenticated 실행 불가 (0057 §1 복원 규칙 위반)'; end if;
    if club_fare(5.0) <> 24900 then v_bad := v_bad || ' 값이 바뀌었다=' || club_fare(5.0); end if;

    if v_bad = ''
      then call _pass('cmg','K8 club_fare 권한 — public/anon 실행 회수·authenticated 보존(0057 §1 캡처-복원)·값은 불변(9900+3000/km)');
    else v_msg := v_bad; call _fail('cmg','K8 club_fare 권한', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('cmg','K8 club_fare 권한', v_msg);
  end;

  -- [adversarial round 2026-08-13, P3-2] Teardown BEFORE the flag restore. t_cmg_debt built
  -- settled bookings (completed + a runs row) whose payments rows the pins then deleted — the
  -- exact shape `sweep_settled_without_payments` (0080 §G) exists to mint for. Harmless while
  -- 117 runs last and the switch is off, but a suite 118 that flips the switch and calls the
  -- sweep would inherit three surprise charges from OUR fixtures. A suite that leaves live
  -- money-shaped debris is a trap for the next author, so it cleans up after itself.
  delete from runs r using bookings b
   where r.booking_id = b.id and b.owner_id in (oa, ob) and b.club_session_id is null;
  delete from ledger_items li using bookings b
   where li.booking_id = b.id and b.owner_id in (oa, ob) and b.club_session_id is null;
  delete from bookings b where b.owner_id in (oa, ob) and b.club_session_id is null;
  delete from billing_keys where profile_id in (oa, ob);

  -- restore the SHIPPED default (charging off) — the state 0080 leaves behind, and the state
  -- anyone reading this database after the harness should see.
  update ops_flags set payments_live_since = null, updated_at = now();
  perform set_config('request.jwt.claim.sub', '', false);
end $$;
