-- ═══ 0102: an invalid commission must RAISE, not silently pay the runner ₩0 ═══
--
-- ═══ §0 WHY THIS FILE EXISTS ═══
-- Raised by TRUST at 0101's diff review, and they were right. 0101 extracted the payout
-- arithmetic faithfully — including an asymmetry it inherited from TypeScript and documented
-- rather than fixed:
--
--     compute_runner_personal_payout (0086 §A)  →  raises `invalid_commission`
--     compute_runner_payout, general arm (0101) →  computes round(gross × 1.0) = the whole gross
--                                                  as fee, and pays the runner NOTHING. Silently.
--
-- So the two arms of ONE function disagreed about whether the same input is an error. Faithful
-- extraction was the right instinct and the wrong outcome here: **a silent ₩0 to a runner is the
-- exact result `0085` and Sean's ruling ⑩ exist to prevent**, and reintroducing it through a new
-- SQL door with nothing pointing at it is worth one line to close.
--
-- ═══ §1 REACHABILITY, MEASURED — it is OUR mistake, not an attack ═══
--   · `runners.commission_rate` is `numeric(4,3) NOT NULL default 0.20` (0001:75) — **null is
--     impossible**, so the null half of the guard is defensive only.
--   · There is **NO check constraint** on the range anywhere in the repo, so `0` and `>= 1` are
--     storable values.
--   · `0057 §6` made the column **server-only** — a runner cannot write it, which was its own P0
--     (`commission_rate = 0` is payout theft). So an invalid rate can only arrive from OUR ops or
--     OUR bug.
--   **That is precisely the case where a loud failure beats a silent zero**: nobody is attacking,
--   somebody fat-fingered, and the runner is the one who would eat it. Production today is 9
--   runners all at 0.330.
--
-- ⚠ A CHECK CONSTRAINT ON THE COLUMN WOULD BE BETTER AND IS NOT THIS FILE'S. It is a `runners`
-- table change and `runners` is not money's surface. Recorded for trust rather than taken.
--
-- ═══ §2 WHAT THIS CHANGES ═══
-- `create or replace` of `compute_runner_payout`, byte-faithful to 0101 except for the six-line
-- guard marked ⑥. No signature change, no grant change, no other object touched. A settle that
-- succeeds today still succeeds — production has no invalid rate — so this is a behaviour change
-- only for inputs that are already broken.
--
-- Pinned as R7 in `137_runner_payout_suite.sql` (the suite that owns this function) rather than in
-- a suite of its own, and mutation-verified there.

create or replace function compute_runner_payout(
  p_booking uuid, p_end_reason text, p_actual_km numeric, p_commission numeric
) returns table (base int, distance int, addon int, guarantee int, gross int, fee int)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- `PRICING.runnerCompBase` / `PRICING.perKm` (functions/_shared/ctx.ts:10-13). ① — 9,900 is the
  -- RUNNER's basis, the floor of the "minimum wage × 2" pitch. The owner's 7,900 is different money.
  RUNNER_COMP_BASE constant int := 9900;
  PER_KM           constant int := 3000;
  b record;
  v_base     int;
  v_distance int;
  v_addon    int;
  v_guar     int := 0;
  v_gross    int;
  v_fee      int;
  v_full_distance int;
begin
  select bk.km, bk.min_fare, bk.addons into b from bookings bk where bk.id = p_booking;
  if b.km is null then raise exception 'not_found'; end if;

  -- ⑥ [0102] INVALID COMMISSION RAISES HERE TOO. Byte-faithful to 0086 §A's guard, and the whole
  -- change in this file. 1.0 is refused as hard as null: a 100% commission pays the runner
  -- NOTHING, and `settle_run_tx` commits runner pay first, so a silent zero is committed before
  -- anything can object. 0 is legitimate and passes — a promo runner keeps everything.
  if p_commission is null or p_commission < 0 or p_commission >= 1 then
    raise exception 'invalid_commission';
  end if;


  -- Fail closed on a reason nobody ruled on, exactly as `compute_owner_charge` does (0080 §D). An
  -- unknown value reaching a money function means a caller was rewritten wrong, and the answer to
  -- that is an exception, not a plausible number. All SIX enum members are priced here — the four
  -- `settle-run` accepts from a runner AND the two only the server may declare — because §0h's ops
  -- exit has to price `owner_forced` and `incident`, which no client can send.
  if p_end_reason is null or p_end_reason not in
     ('completed', 'dog_condition', 'owner_request', 'runner_personal', 'owner_forced', 'incident')
  then
    raise exception 'unknown_end_reason';
  end if;

  -- ② ⑨a PASS-THROUGH — delegated, never re-derived. 0086 §A owns this arm and reads the OWNER's
  -- basis table for it, so the two sides of a stopped run cannot drift. The decomposition is the
  -- point: base 0, addons 0, the whole payout is distance, and ③ the min_fare floor never appears.
  if p_end_reason = 'runner_personal' then
    select rp.gross, rp.fee into v_gross, v_fee
    from compute_runner_personal_payout(p_booking, p_actual_km, p_commission) rp;
    return query select 0, v_gross, 0, 0, v_gross, v_fee;
    return;
  end if;

  v_base     := RUNNER_COMP_BASE;
  v_distance := round(coalesce(p_actual_km, 0) * PER_KM)::int;   -- actual km, within settle-run's band
  -- The `addons[].price` ARRAY, not the frozen `addon_fare` column — handler.ts:137. coalesce keeps
  -- an empty array at 0 rather than null (JS `[].reduce(…, 0)` is 0).
  select coalesce(sum((a->>'price')::numeric), 0)::int into v_addon
  from jsonb_array_elements(coalesce(b.addons, '[]'::jsonb)) a;

  -- ③ the floor, on this arm only. `greatest` over a null min_fare degrades to the sum, which is
  -- what `Math.max(x, null)` did.
  v_gross := greatest(v_base + v_distance + v_addon, coalesce(b.min_fare, 0));

  -- Both owner-caused ends pay the remaining half of the planned distance. `owner_forced` cannot
  -- reach here from `settle-run` (it is server-only at the whitelist) and the arm stays anyway,
  -- because this is the runner-side mirror of `compute_owner_charge`'s `owner_caused_planned`,
  -- where the two ends are also priced identically — and because §0h will call it directly.
  if p_end_reason in ('owner_request', 'owner_forced') then
    v_full_distance := round(b.km * PER_KM)::int;
    -- ④ THE CLAMP. Without `greatest(0, …)` an early stop whose actual already passed the plan
    -- produces a negative guarantee and the run pays LESS than the same distance under any other
    -- reason — an owner cutting a run short would dock the runner.
    v_guar  := greatest(0, round((v_full_distance - v_distance) * 0.5))::int;
    v_gross := v_gross + v_guar;
  end if;

  v_fee := round(v_gross * p_commission)::int;                   -- ⑤ once. net is the caller's job.

  return query select v_base, v_distance, v_addon, v_guar, v_gross, v_fee;
end $$;
revoke execute on function compute_runner_payout(uuid, text, numeric, numeric) from public, anon, authenticated;
grant execute on function compute_runner_payout(uuid, text, numeric, numeric) to service_role;

-- ⚠ THE GRANT IS THE WHOLE SEAL, and it is pinned for that reason (137 R6, trust's plan-review
-- condition). This is a `security definer` over `bookings` with NO party gate — deliberately, since
-- no client can reach it and a gate on an unreachable function is dead code that implies a threat
-- model which does not exist. But that safety lives ENTIRELY in the line above: grant `execute` to
-- `authenticated` for some convenience feature and this becomes a pricing oracle — pass any booking
-- id, get back its addons, its min_fare, its km and a price for a run you have nothing to do with,
-- with no RLS consulted. Nothing else in the harness would redden; 99 S1 sweeps anon only, 98 H1
-- watches search_path. R6 is the pin that converts "safe because of a grant nobody watches" into
-- "safe because a pin watches the grant".
comment on function compute_runner_payout is
  '0101 §A (§0g — docs/decisions/g0-runner-payout-in-sql.md): THE runner payout basis, ported
verbatim from settle-run/handler.ts:135-187. Returns the five ledger_items money columns plus the
gross/fee pair. base = 9,900 (the RUNNER basis, NOT the owner''s 7,900 — D2) · distance =
round(actual_km × 3,000) · addon = sum(bookings.addons[].price) · gross = max(base+distance+addon,
min_fare) · owner_request/owner_forced add guarantee = max(0, round((planned_distance − distance)/2))
· fee = round(gross × commission), ONCE (net = gross − fee is the caller''s subtraction).
runner_personal DELEGATES to compute_runner_personal_payout (0086 §A ⑨a): base 0, addon 0, the whole
payout is distance, and NO min_fare floor — that floor is the flat base ⑨a retires. Unknown
end_reason raises; unknown booking raises not_found. Live PRICING constants, not the booking''s
frozen fare columns, because a payout is not a consented price. Server-only: the execute grant is
the entire seal (137 R6). Pinned by 137 R1-R6';
