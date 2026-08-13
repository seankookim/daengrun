-- ═══ 0081: the CLUB booking path learns about money — the third gate 0080 could not reach ═══
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- 0080 gated the two booking-creating paths it owned: `create-booking-hold` (debt gate, in the
-- edge function) and `generate_recurring_bookings` (debt + billing-instrument gates, §H). Its
-- own exposure-bound comment (0080:657-665) names the third path as an EXPLICIT exclusion:
-- the club delegation insert has no debt gate and no instrument check, so a locked owner can
-- keep accumulating club runs and the §0-bis sentence "exposure is bounded at ≤ one fare per
-- owner" stays false for that path. This file closes it, reusing 0080's two gates verbatim
-- rather than inventing a third pair (which is what 0080:664-665 asked the closer to do).
--
-- ⚠ CITATION CORRECTION (0080:658 says `session_pay_delegation` is "0037:242-249"). That line
-- number points at DEAD CODE: 0037's booking insert lives inside `session_approve_dog`, and
-- 0043 §R1 replaced that function with a hold-only version (0043:252 — "승인 = 자격, 부킹은
-- 보호자 결제 RPC로 이동"). The live insert is `session_pay_delegation(uuid, text, boolean)`,
-- **0053:37, insert at 0053:86**, recreated four times (0037:244 → 0043:341 → 0044:80 →
-- 0053:37). 0080 is applied and stays untouched — a shipped migration is not edited for a
-- comment (0057 §2) — so the correction lives here, and in TODOS.md.
--
-- ═══ §0b WHY THIS IS A PRE-CUTOVER GATE (it must land before `payments_live_since` is set) ═══
-- Club bookings really do reach the charge branch; nothing about the club path is excluded from
-- it at any point:
--   `club_start_delegated_runs` (0050:169-198) opens a runs row per club booking →
--   `app/app/club/run/[sid].tsx:247` calls `settleRun` → `settle-run/handler.ts:110`
--   (collectAfterSettle) → `mint_settle_charge_intent` (0080 §E).
-- 0038:13 states the design in words ("정산은 기존 settle-run(부킹별) 그대로"), `settle_run_tx`
-- (0028) carries no club exclusion, and neither does 0080's charge branch. So the moment Sean
-- sets `ops_flags.payments_live_since`, a club-delegated run charges the owner's card on this
-- booking's frozen numbers — a booking that today is created with no check that the owner can
-- pay at all.
--
-- ═══ §0c WHAT THIS FILE MUST NOT CHANGE — the pilot is running on it ═══
-- The club delegation flow is live for allowlisted accounts (`club_test_accounts`, 0044 §③).
-- Pre-cutover (`payments_live_since is null`) every behavior below has to stay byte-identical:
-- the hold machinery, the idempotence contract, the consent stamp, the fare columns, the
-- booking status, `payment_attempts`. The only pre-cutover changes in this file are ⓐ the debt
-- gate (dormant by construction — a failed charge row cannot exist before the cutover) and ⓓ
-- the two notification sentences, which are conditional on payment reality exactly the way
-- 0080 §J made 0060's and 0072's conditional. 117 K5 mutation-pins that byte-identity.
--
-- ═══ §0d WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - It does not change `club_fare` (0043:14) or any price. Club owners pay a 9,900 base while
--   the marketplace owner base is 7,900 (the D2 decoupling swept TypeScript and could not reach
--   this SQL function). That is a PRICE question and Sean's call — written up as memo ④ in
--   `docs/decisions-open-money.md`, with a loud comment at the call site in §A below.
-- - It does not rework club settlement, `payment_attempts`, or the delegation consent machinery
--   (R6). §B fixes the CONFIRMATION SENTENCE and adds a comment saying what the
--   `payment_attempts` row now means; the row itself keeps being written, unchanged.
-- - It does not touch 0080, the charge functions, or any marketplace path.
-- - It does NOT fix the club REFUND copy class ('전액 환불' promised for money never taken, in
--   `club_cancel_session` / `club_finish_session` / `club_assignment_recovery` /
--   `club_stale_delegation_sweep` / `session_runner_withdraw` / `session_cancel_delegation`).
--   That is the same §0-ter #13 class 0080 §J fixed twice, and it is deliberately left for its
--   own slice, for four reasons recorded here so the next author does not re-derive them:
--     ① the lie is in the TITLES as much as the bodies ('세션 취소 — 전액 환불', '배정 불발 —
--        전액 환불', '위탁 미진행 — 전액 환불', '위탁 취소 — 전액 환불'), and three shipped
--        suites assert those titles verbatim (65:248, 95:212, 107:114) — fixing the copy means
--        moving pins in suites this slice does not own;
--     ② the one shared choke point (`_club_refund_bookings`, 0037:61) cannot carry the fix: the
--        title and body are CALLER-SUPPLIED strings, so an honest post-pay sentence has to be
--        written at each of the six call sites, i.e. six byte-faithful reproductions of large
--        shipped functions for one sentence each;
--     ③ all six also move the booking to `refund_pending`. Post-cutover that STATUS is the same
--        false statement as the copy, so a copy-only patch would leave the louder half of the
--        lie in place;
--     ④ the honest post-cutover sentence for the cancel path is not yet decidable — it depends
--        on Sean's answer to memo ④'s club-cancel-fee question (do club cancel fees become real
--        at cutover, or stay recorded-only forever?). Writing the copy now prejudges it.
--
-- ═══ §0e DOCTRINE (0059 money-path list) ═══
-- self-contained migration · byte-faithful reproduction of the latest definition (0057 §2) ·
-- every definer carries `set search_path = public, pg_temp` IN THE BODY (98 H1) · party gate
-- before state gate · mutation-proven pins (`117_club_money_suite.sql` K1-K8) · no price change.
-- Pins this file must not break: 50 D5/D7/D12 (the delegation flow), 96 C1-C2 (0053's consent
-- stamp), 67 shell, 110 S1-S6 (incident settlement builds its fixtures through this RPC).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A session_pay_delegation — the two money gates, immediately before the insert
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Recreated under 0057 §2 reproduction discipline: the 0053:37-111 body, byte-faithful, with
-- exactly four changes.
--   ⓐ header `search_path = public` → `public, pg_temp` (98 H1 law — ALTER-applied config is
--      reset by `create or replace`, so it belongs in the body).
--   ⓑ the DEBT gate and ⓒ the BILLING-INSTRUMENT gate, both the last thing before the insert
--      (not at the top): a call that was going to be refused for no_capacity / dog_slot_clash /
--      not_payable anyway must not be reported as a money problem. Same placement argument as
--      0080 §H, same two predicates, deliberately — `owner_has_unsettled_charge` (0080 §F) and
--      "no `billing_keys` row while charging is live" (0080 §A/§C).
--      ⓒ keys on the cutover switch, so a card-less pilot owner keeps paying-in-the-mock-sense
--      exactly as today. ⓑ is NOT flag-keyed and does not need to be: a `failed` server-minted
--      charge row can only exist after the cutover, so the gate is dormant by construction.
--   ⓓ §B's conditional confirmation copy (see the §B block below for the argument).
--
-- ⚠ THE REFUSAL SHAPE — and a correction to this slice's build contract.
-- The contract expected the caller here to be the HOST approving somebody else's dog, and
-- therefore required a refusal that hides the owner's payment problem from the host plus a
-- separate notification to the owner. That premise describes 0037's `session_approve_dog`,
-- which has not created bookings since 0043. In the LIVE function the caller is the OWNER
-- THEMSELVES — 0053:51, `if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'`
-- — so:
--   · the privacy hazard does not arise: the host is not the caller, and the host's
--     notification is only ever written on the success path below (a refusal writes nothing to
--     anybody, because a raise rolls the whole transaction back);
--   · the person who must be told about the money IS the person holding the phone. A raised
--     exception reaches them synchronously, which is strictly better than a notification.
-- So the refusal is a plain `raise exception` with an English code, the way every other gate in
-- this function refuses (`method_consent_required`, `no_capacity`, `dog_slot_clash`), and there
-- is deliberately NO notification insert in front of it. Writing one would be reintroducing the
-- exact dead code 0044 §① removed from this function ("raise exception이 트랜잭션 전체를
-- 롤백하므로 0043의 실패 insert는 죽은 코드") — it would never reach the owner's inbox.
-- The owner in the debt state has already been told by the machine that created the debt:
-- 0080 §I notifies '결제 처리 안내 — 설정 > 결제 관리에서 확인해주세요' when it closes a minted
-- intent, and the retry ladder notifies on decline. This gate is the door being locked, not the
-- first news of it.
-- ⚠ THE CALLER HALF is not in this file: the client's error map at
-- `app/app/club/session/[sid].tsx:606-617` is what turns each code into Korean (it falls through
-- to the raw message otherwise, so an unmapped code is visible but ugly, never silent). Both
-- codes here were mapped by the app-side unit in the same session — '지난 러닝의 결제가 아직
-- 처리되지 않아 새 예약이 잠겼어요 — 설정 › 결제 관리…' and '결제 수단이 등록되어 있지 않아요
-- — 설정 › 결제 관리…'. If either code is ever renamed, that file changes with it: they are one
-- contract written twice, and nothing in the SQL harness can see the TypeScript half.
create or replace function session_pay_delegation(p_session_dog uuid, p_idem_key text, p_method_consent boolean default false) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  sd record; s record; v_km numeric; v_bid uuid; v_reserved int;
  v_start timestamptz; v_end timestamptz; v_clash boolean; v_prev uuid;
  v_hold text; v_hexp timestamptz; v_approval text; v_booking uuid;
  v_live boolean;   -- [0081] cutover switch (ops_flags.payments_live_since), read once
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if coalesce(trim(p_idem_key), '') = '' then raise exception 'idem_key_required'; end if;
  -- [감사 9] 배정 방식 동의 게이트 — 서버가 강제(RPC 직접 호출 우회 차단). 기본 false = 미동의.
  if p_method_consent is distinct from true then raise exception 'method_consent_required'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'; end if;

  -- 멱등 재전송: 같은 키의 '성공' 시도 → 같은 부킹 반환 (실패 키는 재시도 허용 — 업서트)
  select booking_id into v_prev from payment_attempts
  where session_dog_id = p_session_dog and kind = 'charge' and idempotency_key = p_idem_key and result = 'ok';
  if v_prev is not null then return v_prev; end if;

  select * into s from club_sessions where id = sd.session_id for update;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  -- [②] 락 '후' 재독 — approval·booking·hold 전부 (락 대기 중 이탈 좌초/변경 반영)
  select approval, booking_id, hold_status, hold_expires_at
    into v_approval, v_booking, v_hold, v_hexp
  from session_dogs where id = p_session_dog;
  if v_approval <> 'approved' or v_booking is not null then raise exception 'not_payable'; end if;

  -- 홀드 만료 시: 같은 락 안에서 정원 재확인 → 통과하면 바로 부킹 (중간 홀드 잔재 없음)
  if not (v_hold = 'active' and v_hexp > now()) then
    v_reserved := _club_delegated_reserved(sd.session_id);
    if v_reserved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;
  end if;

  select km into v_km from routes where id = s.route_id;
  if v_km is null then raise exception 'route_required'; end if;
  v_start := s.scheduled_at;
  v_end := s.scheduled_at + make_interval(mins => (v_km * 8 + 25)::int);
  select exists (
    select 1 from bookings c
    where c.dog_id = sd.dog_id
      and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
      and c.scheduled_at < v_end
      and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
  ) into v_clash;
  if v_clash then raise exception 'dog_slot_clash'; end if;

  -- ⓑ/ⓒ [0081 §A] money gates — the last thing before the insert (0080 §H's two predicates).
  -- The owner is the caller (not_owner above), so the code that comes back IS the message: no
  -- notification is written here, because a raise rolls it back (0044 §①).
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;
  if owner_has_unsettled_charge(sd.owner_profile_id) then
    -- 미수금 = 새 부킹 금지. 클럽만 열어두면 0080 §0-bis의 '보호자당 ≤1건' 노출 한도가 거짓이 된다.
    raise exception 'unsettled_charge';
  elsif v_live and not exists (select 1 from billing_keys bk where bk.profile_id = sd.owner_profile_id) then
    -- 컷오버 이후엔 카드 없이 확정할 수 없다 — 러닝 뒤에 청구할 수단이 없는 자리를 잡는 것이므로.
    raise exception 'billing_key_required';
  end if;

  insert into bookings
    (owner_id, dog_id, runner_id, route_id, status, scheduled_at,
     km, addons, base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values
    -- 🔴 PRICE, unchanged and deliberately so (memo ④ in docs/decisions-open-money.md).
    -- `club_fare(km) = 9900 + round(km*3000)` (0043:14) is the PRE-D2 owner price: a club owner
    -- pays ₩2,000 more than a marketplace owner for the same distance (owner base is 7,900 since
    -- the D2 decoupling, which swept TypeScript constants and could not reach this SQL function).
    -- The decomposition below is internally consistent — 9900 + (club_fare - 9900) + 0 = club_fare
    -- — so a full-distance settle charge equals the quote exactly (0080 §D reads these frozen
    -- columns, never live constants). This is therefore a PRICE question, not an arithmetic bug,
    -- and pricing is Sean's call. 117 K7 pins the decomposition so a later club_fare change
    -- cannot silently desynchronize base/distance/total.
    (sd.owner_profile_id, sd.dog_id, null, s.route_id, 'matching', s.scheduled_at,
     v_km, '[]', 9900, club_fare(v_km) - 9900, 0, club_fare(v_km), 9900, sd.session_id)
  returning id into v_bid;

  update session_dogs set booking_id = v_bid, hold_status = 'consumed' where id = p_session_dog;
  -- [0081 §B] WHAT THIS ROW MEANS, now that a real charge exists somewhere else. It is NOT a
  -- record that money moved — nothing is charged here in either era. It is the delegation
  -- CHECKOUT record, and its only load-bearing job is the idempotency contract above (same key
  -- → same booking, 0044 §①). The real charge for this booking is minted after the run by
  -- `mint_settle_charge_intent` (0080 §E) and lives in `payments`. Reworking this table into an
  -- honest vocabulary is R6; renaming `kind`/`result` here would break that idempotence read.
  insert into payment_attempts (session_dog_id, booking_id, kind, idempotency_key, result)
  values (p_session_dog, v_bid, 'charge', p_idem_key, 'ok')
  on conflict (session_dog_id, kind, idempotency_key) where idempotency_key is not null
  do update set result = 'ok', booking_id = excluded.booking_id, detail = null, created_at = now();

  -- [감사 9] 동의 박제 — 이 session_dog의 최신 동의행에 method_consent 각인 (분쟁 근거)
  update delegation_consents set method_consent = true
  where id = (select id from delegation_consents where session_dog_id = p_session_dog
              order by accepted_at desc, id desc limit 1);

  -- ⓓ [0081 §B] 확정 알림 — '결제 완료'는 어느 시대에도 참이 아니다 (§B 블록 참조).
  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '자리 확정',
     to_char(s.scheduled_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
     || ' 위탁이 확정됐어요 — 담당 러너는 집결지에서 배정돼요'
     || case when v_live then ' · 이용료는 러닝이 끝난 뒤 결제돼요' else '' end, v_bid),
    (s.host_profile_id, 'community', '위탁 자리 확정', '위탁 강아지의 자리가 확정됐어요', sd.session_id);
  return v_bid;
end $$;

-- 0053:113's ACL restated (positive grant — the owner's payment sheet stops working without it;
-- `create or replace` preserves it, so this is belt, not a change — 0080 §J-ⓑ's precedent).
grant execute on function session_pay_delegation(uuid, text, boolean) to authenticated;

comment on function session_pay_delegation is
  '0081 §A (was 0053 §1): 위탁 결제 RPC — 0053 본문 그대로(홀드 재독·멱등·동의 박제) + [0081]
결제 게이트 둘: 미수금 보호자는 unsettled_charge로 거부(항상), payments_live_since가 설정된 뒤엔
카드 없는 보호자도 billing_key_required로 거부. 호출자가 보호자 본인이므로(not_owner 게이트)
거부는 예외 코드로 충분하다 — raise는 알림 insert를 롤백한다(0044 §①). [0081 §B] 확정 알림에서
"결제 완료" 제거: 컷오버 전엔 청구가 없고, 뒤엔 러닝이 끝난 뒤에 청구된다';

-- ⚠ [adversarial round 2026-08-13, P3-3] §C closes ONE instance of a class, not the class.
-- 0057 §1's revoke walked `prosecdef` functions only, so plain pricing formulas kept their
-- PUBLIC execute. `club_fare` was the one this slice touches; three siblings from the km
-- ledger are still anon-executable and were left alone deliberately (out of scope, and 0075
-- is applied):  km_face_price (0075:69) · km_overrun_allowance (0075:84) · km_run_floor
-- (0075:92).  Naming them here so the next author does not read §C as "the class is swept".
-- (my_ledger_total / my_miles_balance are also PUBLIC but invoker-rights, so RLS covers them.)

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B the '결제 완료' sentences — honesty law, 0080 §J's conditional-copy technique
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Two shipped sentences asserted a payment (0053:105-109, unchanged since 0043:353):
--   owner  '결제 완료 — 자리 확정' / '… 위탁이 확정됐어요 — 담당 러너는 집결지에서 배정돼요'
--   host   '위탁 결제 완료'        / '위탁 강아지의 결제가 완료됐어요'
-- Neither is true in either era, which is what makes this a copy fix and not a flag:
--   · PRE-cutover  — nothing is ever charged for club. The sentence is mock-era decoration; the
--     app already knows it (app/app/club/session/[sid].tsx:601 — "'결제 완료'는 돈이 움직였다는
--     주장이다. 움직이지 않았다" — and shows '자리 확정' in its own alert). The server was still
--     writing the claim into the owner's inbox.
--   · POST-cutover — the club booking is charged like every other booking, AFTER the run
--     (settle-run → mint, §0b). So at the moment of confirmation nothing has been charged yet,
--     and saying '결제 완료' would be false in the more expensive direction.
-- The fix is the technique 0080 §J used for 0060/0072: make the sentence conditional on reality
-- rather than deleting it. The owner's body gains a post-cutover clause naming WHEN the money
-- moves; the title becomes '자리 확정' in both eras (the seat is the fact that is true in both).
-- The HOST's sentence is unconditional and simply stops mentioning money: the host is not a
-- party to this owner's payment, and 'the seat is confirmed' is the whole of what they need —
-- which is also the only version that cannot leak an owner's money state into a community feed.
-- No `payment_attempts` write was deleted (R6, see §0d and the comment at the write itself).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C club_fare grant hygiene — the pricing formula was never swept
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0057 §1's blanket revoke only walked SECURITY DEFINER functions (`p.prosecdef`), and
-- `club_fare` (0043:14) is a plain immutable SQL formula — so it kept PostgREST's default
-- PUBLIC execute and is callable as `POST /rest/v1/rpc/club_fare` by an anon key holder. What
-- leaks is arithmetic the app already displays, so this is hygiene rather than a hole; it is
-- fixed here because this slice is the one reading that function's price out loud.
-- `authenticated` is RESTORED rather than dropped, which is exactly 0057 §1's capture-and-
-- restore rule: every caller today reads club_fare from inside a definer (the board impls,
-- `_club_delegation_board_impl` 0053:227 and its siblings, plus §A above), so nothing needs the
-- direct grant — but PUBLIC was giving `authenticated` effective execute, and silently removing
-- a privilege that a view or an invoker-context caller might hold is how 0057 §1 says NOT to do
-- it. Pinned by 117 K8.
revoke execute on function club_fare(numeric) from public, anon;
grant execute on function club_fare(numeric) to authenticated;

comment on function club_fare is
  '0043 §1 단일 가격 소스, 값 불변: 9900 + round(km*3000). 🔴 base 9900은 D2 이전 보호자 가격이다
(마켓플레이스 보호자 base는 7900) — 같은 거리에 클럽 보호자가 ₩2,000 더 낸다. 가격 결정은 Sean의
몫이라 이 파일은 값을 바꾸지 않는다: docs/decisions-open-money.md 메모 ④ 참조.
[0081 §C] public·anon 실행 회수(0057 §1 doctrine, definer가 아니라 그 sweep이 못 봤다)';
