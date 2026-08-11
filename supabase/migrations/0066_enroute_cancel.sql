-- 0066 — en-route owner cancel: transition widening + cancel-fee tiers as SQL truth
-- (Sean decision 2026-08-11, TODOS.md "cancel window at the handoff moment": an owner MAY
--  cancel while the runner is EN ROUTE, at a 50% fee that is runner compensation.)
--
-- §1 enforce_booking_transition: add cancelled_owner to the runner_enroute row — and ONLY
--   there. picked_up stays blocked on purpose: the dog is already handed over, so an owner
--   exit at that point is an incident (incident_review path), not a cancellation. The full
--   map is copied verbatim from the latest definition (0047:25-48 — 0058 only references
--   the function in comments; verified by grep over migrations). The original is a plain
--   invoker trigger function with no search_path clause, no grants, and no comment — the
--   recreation preserves that shape and adds a comment documenting the widening.
--
-- §2 marketplace_cancel_fee(p_booking): the owner-cancel fee ladder moves from
--   transition-booking/index.ts (TS) into SQL so the harness can pin it — the harness is
--   SQL-only, and a money constant that lives solely in a Deno function is a money constant
--   no pin can protect. The edge function now calls this and CASes the transition on the
--   quoted status (see index.ts cancel_owner). Tiers:
--     unmatched (no runner, or matching/runner_pending)  → 0    (full refund, any time)
--     runner_enroute                                     → 50%  (runner compensation — Sean 2026-08-11)
--     matched, >= 24h before start                       → 0
--     matched, < 24h before start (confirmed)            → 10%
--   The en-route arm sits above the 24h arm: once the runner has set out, compensation is
--   owed regardless of the clock. (In practice enroute implies < 24h — the enroute action
--   gates on scheduled_at, index.ts — so the ordering is doctrine, not a reachable fork.)
--   round() half-away-from-zero == Math.round for positive prices (total_price int > 0).
--
-- NO new column. The runner-compensation split needs no schema: bookings.cancel_fee already
--   records the money, and the en-route tier is marked by the edge function writing
--   cancel_reason = 'owner_cancel_enroute' (column exists since 0001:184, null for
--   marketplace owner-cancels until now; club readers of cancel_reason map unknown values
--   to 'other' exactly as they map null — verified against _club_compute_axes). Settlement
--   (future, payments are mocked) reads tier from cancel_reason, amount from cancel_fee.
--   A runner_comp column would duplicate a value derivable as `cancel_fee where
--   cancel_reason = 'owner_cancel_enroute'` — two writers for one fact.

-- ---------- §1 transition map: runner_enroute → cancelled_owner ----------
create or replace function enforce_booking_transition() returns trigger
language plpgsql as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'draft'          then new.status in ('quoted','expired')
    when 'quoted'         then new.status in ('payment_hold','expired')
    when 'payment_hold'   then new.status in ('matching','expired','refund_pending')
    when 'matching'       then new.status in ('runner_pending','confirmed','expired','refund_pending','cancelled_owner')
    when 'runner_pending' then new.status in ('confirmed','matching','expired','cancelled_owner')
    -- [R3] matching 추가 — 배정 철회/보호자 이의 (인계 전 한정, 클럽 RPC만 수행)
    when 'confirmed'      then new.status in ('matching','runner_enroute','picked_up','cancelled_owner','cancelled_runner','no_show')
    -- [0066] cancelled_owner added — owner cancel while the runner is en route (50% fee,
    -- runner compensation). picked_up below stays closed: past the handoff it's an incident.
    when 'runner_enroute' then new.status in ('picked_up','no_show','cancelled_runner','incident_review','cancelled_owner')
    when 'picked_up'      then new.status in ('active','incident_review')
    when 'active'         then new.status in ('completed','incident_review')
    when 'completed'      then new.status in ('incident_review')
    else new.status in ('refund_pending')
  end;
  if not ok then
    raise exception 'invalid booking transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;

comment on function enforce_booking_transition is
  '0066: latest map (base = 0047) + runner_enroute → cancelled_owner (en-route owner cancel, 50% fee). picked_up → cancelled_owner stays blocked (incident, not cancellation).';

-- ---------- §2 owner-cancel fee ladder (single money truth; edge fn calls via rpc) ----------
-- Returns the quoted status alongside the fee so the caller can CAS the transition on the
-- exact state the quote priced: after §1, confirmed AND runner_enroute → cancelled_owner are
-- both legal, so the trigger no longer catches a quote-then-depart race — a 0/10% fee landing
-- on an en-route runner. The CAS (update ... eq status = quoted) is the only fence left.
create or replace function marketplace_cancel_fee(p_booking uuid)
returns table (fee int, status text)
language sql stable
set search_path = public, pg_temp
as $$
  select
    case
      when b.runner_id is null or b.status in ('matching', 'runner_pending') then 0
      when b.status = 'runner_enroute' then round(b.total_price * 0.5)::int
      when b.scheduled_at >= now() + interval '24 hours' then 0
      else round(b.total_price * 0.1)::int
    end,
    b.status::text
  from bookings b
  where b.id = p_booking
$$;

-- Server-only surface: the caller is transition-booking (service_role). Not a client quote
-- API — client copy states the policy in words and the success alert shows server numbers.
revoke execute on function marketplace_cancel_fee(uuid) from public, anon, authenticated;
grant execute on function marketplace_cancel_fee(uuid) to service_role;

comment on function marketplace_cancel_fee is
  '0066: owner-cancel fee ladder — unmatched 0 / runner_enroute 50% (runner compensation, Sean 2026-08-11) / >=24h 0 / <24h 10%. Returns quoted status for the caller''s CAS. Server-only (service_role).';
