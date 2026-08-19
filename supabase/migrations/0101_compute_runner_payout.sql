-- ═══ 0101: §0g — the RUNNER's payout price moves out of TypeScript and into SQL ═══
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- `docs/decisions/g0-runner-payout-in-sql.md` is the contract, written and plan-reviewed before a
-- line of this existed. Sean's G1 ruling made the runner's payout basis depend on `end_reason`;
-- that pricing lived in `supabase/functions/settle-run/handler.ts:135-187`, so `_settle_sealed_run`
-- has to be HANDED a price it cannot derive, and §9's recovery arm can report a sealed-but-unsettled
-- booking without being able to settle it. This file is the sibling of `0080 §D`'s
-- `compute_owner_charge` on the runner's side of the same run: 0066 §2's rule — "a money rule that
-- lives only in a Deno function is a money rule no pin can protect."
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - **NO BEHAVIOUR CHANGE.** This is a pure extraction. Every `end_reason`, every distance, every
--   commission must produce the ledger row the TypeScript produced, to the won. The suite's value
--   pins (137) are literals CAPTURED from a run of the pre-change TypeScript over the same fixture
--   matrix, not numbers re-derived from the SQL below — see 137's header for the captured table.
-- - **The 50%-of-planned completion gate stays in TypeScript** (`handler.ts:127`). It is an
--   *eligibility* rule about whether `completed` may be CLAIMED, not a price. Moving it would
--   change an error path this slice has no business touching, and would make this function refuse
--   to price a run that ops must still be able to settle (§0h).
-- - It does not touch `settle_run_tx`, `_settle_sealed_run` (which keeps `p_quote` — that is
--   sequencing step 2, a separate slice), `compute_owner_charge`, `compute_runner_personal_payout`,
--   the mints, the ladder, or any grant on any table.
-- - It does not re-create anything. See §0c.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON (REGISTRY.md's silent-collision rule) ═══
-- Re-creates NOTHING. `compute_runner_payout` is new. It READS `bookings` (km, min_fare, addons)
-- and CALLS `compute_runner_personal_payout` (0086 §A) — neither is redefined here.
--
-- ═══ §0d DOCTRINE (0059 money-path list) ═══
-- self-contained · `set search_path = public, pg_temp` IN THE BODY (98 H1 — ALTER-applied config is
-- reset by `create or replace`) · revoke from public/anon/authenticated, grant to service_role (the
-- caller is `settle-run`, running as service_role) · mutation-proven pins in
-- `137_runner_payout_suite.sql` (R1-R6), including the GRANT itself.
-- Pins this file must not break: 122 P1-P4 (the arm it delegates to), 116 C1-C4/C23 and 120 J1-J2
-- (the owner-side basis table that arm reads), 10_settle (settle_run_tx's own scenarios).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A compute_runner_payout — the five ledger columns plus the gross/fee pair, in SQL
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Transcribed from `settle-run/handler.ts:135-187`, which was the only definition until this file.
-- The five things a porter gets wrong, each named where it happens below:
--
--   ① **`base` is 9,900, not 7,900.** The runner basis and the owner basis were deliberately
--      decoupled (D2, Sean 2026-08-12). `ctx.ts` says it in capitals: "하나를 다른 하나에 '맞추는'
--      수정은 버그가 아니라 사고다". Reading the owner's 7,900 here silently underpays every runner
--      on every run, forever, and no owner-side pin would notice.
--   ② **`runner_personal` sets `base := 0` and `addon := 0`, and the WHOLE payout becomes
--      `distance`.** Not cosmetic: the owner's base was waived on that arm (§0-ter #10), so writing
--      9,900 into `base` puts a fee the owner never paid — and the run never earned — into every
--      earnings breakdown that reads `ledger_items`. The total can be right while the breakdown
--      lies. `settle_charge_test.ts`'s LEDGER ROW test exists because that is a real revert.
--   ③ **The `min_fare` floor does NOT apply to `runner_personal`** — that floor IS the flat base
--      ⑨a retires (0086 §A). It applies only in the `else` arm.
--   ④ **The guarantee is clamped at 0.** An owner-caused early stop where the actual distance
--      already exceeded the plan once produced a NEGATIVE guarantee, i.e. a pay CUT for the runner.
--      `greatest(0, …)` is a fix, not decoration.
--   ⑤ **`fee` is `round(gross × commission)`, computed ONCE.** The runner's net is the CALLER's
--      subtraction (`gross - fee`), never a second rounding — the runner's share and the platform's
--      must sum to the gross exactly, or the platform quietly gains or loses a won per run. 0086 §A
--      already insists on this for the pass-through arm; it is the same law here.
--
-- WHY THE CONSTANTS ARE LIVE AND NOT FROZEN, unlike `compute_owner_charge`. The owner's charge is
-- built from `bookings.base_fare / distance_fare / addon_fare` — the numbers the owner CONSENTED to
-- (0080 §D ①, "동의한 가격만 청구한다"). The runner's payout is not a consented price; it is
-- `PRICING.runnerCompBase` and `PRICING.perKm` at settle time, as `handler.ts:135-136` reads them,
-- and the `addons[].price` array rather than the frozen `addon_fare` column. Transcribing it any
-- other way would be a behaviour change wearing the costume of a cleanup. ⚠ The consequence is
-- real and is the pre-existing rule, not a new one: a price revision reprices every unsettled
-- run's PAYOUT while leaving its CHARGE alone. If that is ever wrong it is a product decision with
-- its own slice, not something to quietly fix inside a port.
--
-- `p_commission` is passed IN rather than read here for 0086 §A's reason: `settle-run` already
-- reads `runners.commission_rate` with the 0059 fallback ("행 부재 시 저과금 방지"), and one
-- reader is better than two that can disagree. It is a server-side read, never client input.
--
-- ⚠ ASYMMETRY THAT IS DELIBERATE AND WILL LOOK LIKE A BUG: the `runner_personal` arm REJECTS a
-- commission that is null, negative, or ≥ 1 (0086 §A raises `invalid_commission`); the other arm
-- does not. That is exactly what the TypeScript did, and this slice is a pure extraction — the
-- general arm has never validated the rate, and adding a raise here would turn a settle that
-- succeeds today into a 500. Widening the check is a behaviour change and belongs to whichever
-- slice is willing to pin it.
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
