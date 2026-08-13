-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0085 — ⑩ 취소 수수료 러너 배분 (10% 티어)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Decision: docs/decisions/cancel-fee-runner-share.md — Sean 2026-08-13:
--   "pay the runner and let them know, reward them ykwim."
--
-- WHAT WAS BROKEN. 0066's ladder charges an owner 10% for cancelling a CONFIRMED booking
-- inside 24h. `record_enroute_cancel_comp` (0080 §K) pays the runner only on the OTHER tier
-- (en route, 50%, all of it theirs). The 10% tier wrote nothing — while
-- `app/app/owner/schedule.tsx:604` told the owner, in the pre-commit cancel sheet:
--   "취소 수수료는 시간을 비워둔 러너에게 50%, 도그스하이에 50% 배분돼요"
-- A runner who held an evening free got ₩0 and no word that the cancellation was a money
-- event at all. That is margin resting on a sentence the ledger did not keep. Nothing in the
-- system contradicted itself loudly: the promise is in the client, the write is in SQL, and
-- neither knew about the other. This migration makes the shipped sentence true — the fix is
-- to pay, not to soften the copy (Sean's ruling; the copy needs no edit once this lands).
--
-- EXTENDS, DOES NOT REPLACE (REGISTRY.md silent-collision law): `record_enroute_cancel_comp`
-- and `mint_cancel_fee_intent` stay exactly as 0080 wrote them; `marketplace_cancel_fee` stays
-- as 0066 wrote it. This file adds ONE new function and touches no existing object.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ── Why a sibling function instead of extending 0080's ────────────────────────────────────
-- 0080 owns the en-route comp. Re-creating it to serve a second tier is the silent-revert
-- class the registry exists to catch (its pins live in 116, mine in 121; a revert would stay
-- green). So: a new function, and the two are made mutually exclusive by construction —
-- ── The shared lock key is deliberate ─────────────────────────────────────────────────────
-- Both comp writers take `pg_advisory_xact_lock(hashtextextended('comp:' || booking, 0))`.
-- Same key space as 0080:1116-1118 ON PURPOSE, not by coincidence: a booking has exactly one
-- cancel tier, so only one of the two can legitimately fire, and sharing the key means that
-- even a caller bug cannot get both to interleave past each other's existence check.
-- `ledger_items` has no unique key on booking_id (0001:264, 0080:1112 explains why), so the
-- lock IS the serialization — a read-then-insert under a per-booking lock.
--
-- ── Why the share sits in `remaining_guarantee` with `platform_fee` = 0 ───────────────────
-- MEASURED TRAP: `my_ledger_total` (0027:13) sums
--   base + distance_pay + addon_pay + tip + remaining_guarantee - platform_fee
-- so `platform_fee` SUBTRACTS from what the runner is shown. Recording the platform's half
-- there — which reads as the honest double-entry thing to do — would net the runner to ZERO
-- at a 50/50 split: the row would look correct in the table and pay nothing in the app. The
-- ledger is the RUNNER's ledger, not a double-entry book: it records what they are owed. The
-- platform's half never enters it. `remaining_guarantee` is the compensation column (0001:272,
-- and 0080:1103-1109 argues base/distance/addon would each lie about what happened).
create or replace function record_late_cancel_share(p_booking uuid)
returns table (comp int, written boolean)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  b       record;
  v_share int;
begin
  select bk.runner_id, bk.status::text as status, bk.cancel_reason,
         coalesce(bk.cancel_fee, 0) as fee
    into b
  from bookings bk where bk.id = p_booking;
  if not found then raise exception 'not_found'; end if;

  perform pg_advisory_xact_lock(hashtextextended('comp:' || p_booking::text, 0));

  -- The tier IS the reason string (0066's no-new-column design, extended to this tier by
  -- transition-booking/cancel_owner.ts's CAS). Anything else — the en-route tier, a free
  -- cancel, an unmatched booking, a booking that never reached cancelled_owner — writes
  -- nothing and says so.
  if b.status <> 'cancelled_owner'
     or b.cancel_reason is distinct from 'owner_cancel_late'
     or b.runner_id is null
     or b.fee <= 0 then
    return query select 0, false;
    return;
  end if;

  -- 50% — the rate the owner was shown before they confirmed (client `cancelPolicy.runnerShare`,
  -- app/src/store.ts:197). If this literal ever moves, the copy moves with it or the sentence
  -- lies again; 121 pins the amount against a literal so a drift here goes RED.
  v_share := round(b.fee * 0.5)::int;

  -- Idempotent: any existing ledger row for this booking means a comp writer already ran
  -- (this one on a retry, or 0080's — the shared lock guarantees we see it). Report the amount,
  -- write nothing. Same shape as 0080:1143-1146 so a caller can treat both alike.
  if exists (select 1 from ledger_items li where li.booking_id = p_booking) then
    return query select v_share, false;
    return;
  end if;

  -- A fee small enough to round to nothing pays nothing rather than a ₩0 row that would then
  -- block a later legitimate write via the existence check above.
  if v_share <= 0 then
    return query select 0, false;
    return;
  end if;

  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                            tip, remaining_guarantee, platform_fee)
  values (b.runner_id, p_booking, 0, 0, 0, 0, v_share, 0);

  return query select v_share, true;
end $$;

revoke execute on function record_late_cancel_share(uuid) from public, anon, authenticated;
grant  execute on function record_late_cancel_share(uuid) to service_role;

comment on function record_late_cancel_share is
  '0085 ⑩: 24시간 이내 확정 예약 취소(10% 티어)의 러너 배분 — 수수료의 50%를 러너 원장에 기록.
평생 한 번만 쓴다(부킹당 원장 1행, comp: 자문 락으로 0080의 인루트 보상과 상호 배타).
platform_fee는 0 — my_ledger_total이 platform_fee를 빼기 때문에 플랫폼 몫을 여기 적으면
러너 수령액이 0이 된다. 원장은 러너가 받을 돈의 장부이지 복식부기가 아니다';
