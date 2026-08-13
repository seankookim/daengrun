-- ═══ 0086: ⑨a — a `runner_personal` stop pays the runner THROUGH the owner's charge ═══
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- `docs/decisions/runner-stop-split.md`, ruling ①, confirmed twice by Sean on 2026-08-13: on a
-- stopped run the runner receives **their commission share of what the owner was charged**,
-- instead of today's `base + distance + addons`. On a 3km booking abandoned at 1km that is the
-- difference between ₩8,643 (the platform funding ₩5,643 of a run that did not happen) and ₩2,010
-- of a ₩3,000 charge. §A is that formula, in SQL, next to the owner's basis table it reads.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - **NO `runner_incapacity`.** That is ⑨b, and its memo's trap ③ is why it is not here: `0083:366`
--   (`end_run_tx`, the run-end-flow slice) freezes `end_reason` at run-STOP to the same four values
--   `CLIENT_END_REASONS` accepts at settle, and the freeze happens EARLIER than the settle-time
--   whitelist. A value in one set and not the other strands the run forever — never paid, never out
--   of `active`, and no test sees it because each side is individually correct. So the enum value
--   must enter BOTH sets in ONE commit; 0083 is not on this branch, and the abuse story for a
--   self-declared reason is not written. Nothing here adds an enum value, touches
--   `CLIENT_END_REASONS`, or touches 0083's freeze list.
-- - **⑩ (the <24h cancel tier's runner half) IS NOT HERE, and not because it isn't needed.** It is
--   claimed on origin by another session — `0085_cancel_share.sql` / suite 121,
--   `claude/club-delegation-money-gaps-b59eb8`, REGISTRY row pushed 2026-08-13 14:52. This slice
--   was briefed to build it too and yielded on the registry's own rule ("a number is claimed when
--   it is on origin"; the 0083/0084 precedent: the only claim ever pushed stands). See this
--   slice's report and REGISTRY.md's standing-conflicts section.
-- - **It does not change any owner-side number.** `compute_owner_charge`'s
--   `runner_personal_distance_only` arm (0084:188, #10 — distance only, base waived) is correct as
--   shipped and is READ here, never redefined. The ⑨ memo's trap ② exists because two readers have
--   looked at that line and seen a bug; this file is the third reader saying it is not one.
-- - **It does not re-create `settle_run_tx`** — see §B, which is the load-bearing paragraph here.
-- - It does not touch the 0066 ladder, the mints, the debt derivation, the sweeps, or 0083.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON (REGISTRY.md's silent-collision rule) ═══
-- Re-creates NOTHING. `compute_runner_personal_payout` is new; the only shipped object it touches
-- is `compute_owner_charge` (0084 §A, itself 0080 §D's body), which it READS.
--
-- ═══ §0d DOCTRINE (0059 money-path list) ═══
-- self-contained migration · the definer carries `set search_path = public, pg_temp` IN THE BODY
-- (98 H1 — ALTER-applied config is reset by `create or replace`) · revoke from public/anon/
-- authenticated, grant to service_role (the caller is `settle-run`, running as service_role) ·
-- mutation-proven pins in `122_runner_stop_pay_suite.sql` (P1-P4).
-- Pins this file must not break: 120 J1-J2 (the basis table it reads), 116 C1-C4/C23 (the same),
-- 10_settle (settle_run_tx's own scenarios — the other three end reasons are untouched).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A compute_runner_personal_payout — pass-through pay, for `runner_personal` ONLY
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ⚠ THE FORMULA IS THE RULING; THE FIGURES ARE ILLUSTRATIONS. The memo's 2,010 / 8,643 are ONE
-- KILOMETRE OF A THREE-KILOMETRE BOOKING. Hard-coding either breaks every other distance, so
-- neither appears below. What is encoded here, and all that is encoded here:
--        gross = compute_owner_charge(booking, 'runner_personal', actual_km).amount
--        fee   = round(gross × commission)
--        net   = gross − fee                              ( = (1 − commission) × owner charge )
-- `net` is a SUBTRACTION and is computed by the caller, never a second rounding: the runner's share
-- and the platform's must sum to the owner's charge exactly, or the platform quietly gains or loses
-- a won on every stop.
--
-- ⚠ "WHAT THE OWNER ACTUALLY PAID" MEANS THE BASIS TABLE, NOT MONEY THAT CLEARED TOSS. This is the
-- one interpretive decision in ⑨a, and it is load-bearing in both directions:
--   · pre-cutover (`ops_flags.payments_live_since` null) NOTHING is ever charged, so reading
--     collected money would pay every pilot-era stop ₩0 — the whole card-less pilot, unpaid;
--   · post-cutover, a declined card would zero the runner's pay, inverting settle-run's ordering
--     law ("the runner is paid whether or not the owner's card works", handler.ts:13).
-- `compute_owner_charge` is cutover-independent by construction, which is why it is the input.
--
-- CONSEQUENCES THAT FOLLOW FROM THE RULE — named so nobody "fixes" them later:
--   · the `min_fare` floor does NOT apply to this arm, and could not: the floor is 9,900 and the
--     whole point is that a stop no longer pays a full base. 0080:222 records the behaviour that
--     ends here ("platform absorbs the runner's min_fare floor at tiny actuals").
--   · a sub-₩100 owner charge answers 0 (`below_pg_minimum`, 0084 §A ⑤), so the runner is paid 0
--     and the mint writes a `waived` row. Nobody pays, nobody is paid — under ~34 metres.
--   · `base` is 0 in the ledger row the caller composes, because the owner's base was waived on
--     both sides. The D2 decoupling (owner 7,900 / runner 9,900) has nothing to apply to: there is
--     no base on either side of a stop.
--   · `completion_rate` is untouched — 0028 ⑤ still counts `completed` + `runner_personal`, which
--     is the OTHER half of why this reason is distinguishable at all.
--
-- WHY THIS IS SQL AND NOT FOUR LINES OF TypeScript: 0066 §2's rule — "the harness is SQL-only, and
-- a money constant that lives solely in a Deno function is a money constant no pin can protect".
-- It also puts the pass-through one call away from the charge it passes through, so a change to the
-- owner arm cannot silently desynchronize the runner arm.
--
-- `p_commission` is passed IN rather than read here, deliberately: `settle-run` already reads
-- `runners.commission_rate` with the 0059 fallback ("행 부재 시 저과금 방지"), and one reader is
-- better than two that can disagree. It is a server-side read, never client input. An absent or
-- nonsensical rate RAISES rather than defaulting — this runs BEFORE `settle_run_tx`, so a raise
-- costs a retriable 500 with nothing written, while a silent default writes the wrong money into a
-- ledger nobody re-reads.
create or replace function compute_runner_personal_payout(
  p_booking uuid, p_actual_km numeric, p_commission numeric
) returns table (gross int, fee int)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_amount int;
begin
  -- 1.0 is refused as hard as null: a 100% commission pays the runner nothing, and the only way
  -- that value reaches here is a corrupted runners row. 0 is legitimate (a promo runner keeps
  -- everything) and passes.
  if p_commission is null or p_commission < 0 or p_commission >= 1 then
    raise exception 'invalid_commission';
  end if;

  -- Raises `not_found` on an unknown booking, exactly as the mint does (0084 §A).
  select c.amount into v_amount
  from compute_owner_charge(p_booking, 'runner_personal', p_actual_km) c;
  v_amount := coalesce(v_amount, 0);

  return query select v_amount, round(v_amount * p_commission)::int;
end $$;
revoke execute on function compute_runner_personal_payout(uuid, numeric, numeric) from public, anon, authenticated;
grant execute on function compute_runner_personal_payout(uuid, numeric, numeric) to service_role;

comment on function compute_runner_personal_payout is
  '0086 §A (⑨a, Sean 2026-08-13 — docs/decisions/runner-stop-split.md): pass-through pay for a
runner_personal stop. gross = compute_owner_charge(booking, ''runner_personal'', actual_km).amount
(the OWNER''s basis-table charge — distance only, base waived, #10), fee = round(gross×commission),
and the caller''s net = gross − fee, so runner + platform sum to the owner''s charge exactly. THE
FORMULA IS THE RULING — the memo''s 2,010/8,643 are 1km-of-3km illustrations, not constants. No
min_fare floor on this arm (that floor is the flat base ⑨a retires). Knows nothing about
runner_incapacity (⑨b — blocked on 0083''s freeze list and on its abuse story). Server-only.
Pinned by 122 P1-P4';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B WHY `settle_run_tx` IS NOT RE-CREATED HERE — the silent-collision class, live
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The build brief named `settle_run_tx`'s ledger write as a place ⑨a would land. It is not, for
-- two reasons that both matter:
--   ① it does not need to change. Its ledger write (0028:85-86) inserts the five money parameters
--      it is HANDED — `p_base, p_distance_pay, p_addon_pay, p_guarantee, p_fee` — and ⑨a is
--      entirely a question of what those five values are. `settle-run/handler.ts` composes them;
--      §A gives it the number. Nothing about the transaction, the claim, the incentive gates or
--      `completion_rate` moves.
--   ② re-creating it would be REGISTRY.md's silent-collision class in its worst form.
--      `settle_run_tx`'s current definition is **0028:18** (`0028_settle_enum_cast.sql`), and 0083
--      (run-end-flow, claimed, on `origin/claude/run-end-flow-1a67e0`, NOT on this branch) EXTENDS
--      it. 0083 < 0086, so on the merged branch 0083 applies FIRST and a 0086 rebuilt from 0028's
--      body would silently revert it — while the harness stayed green, because 0083's pins live in
--      0083's suite and would be exercising 0086's reverted function.
--      "Add columns and your own functions. Re-create nothing you did not create."
-- ⚠ FOR THE NEXT AUTHOR: if a later slice genuinely must change `settle_run_tx`, it builds on
--    whichever of 0028 / 0083 is newest ON ORIGIN at that moment, says so in its header by
--    migration number, and MUST add `set search_path = public, pg_temp`. 0028:30's body says only
--    `set search_path = public`; the function passes 98 H1 today because 0055's blanket ALTER
--    retro-sealed it, and `create or replace` overwrites `proconfig` with whatever the CREATE
--    statement says — so a byte-faithful reproduction of 0028 would silently un-seal it and turn
--    H1 red. Measured behaviour, recorded at 98 H1's own header.
