-- ═══ 0084: Sean's rulings become SQL — the abort basis, the reviewable waive, ops routing,
--          and the cutover guard ═══
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- 0080 shipped the charge machine with ONE arm marked as a provisional pending a product call
-- (`dog_condition`/`incident` → 0, rule `g1_waive`, 0080:228-232 — "🔴 Sean's open product call
-- (G1, §0-ter #9) … When he rules, the change is this one arm plus its pin"). 0081 shipped the
-- club gates and left the club price question open as memo ④. Both memos, plus four more, were
-- answered by Sean directly on 2026-08-13 — the six rulings of record are
-- `docs/decisions-open-money.md`, each carrying "✅ SEAN'S RULING" in his own words.
--
-- Four of those six have a SQL half, and it is this file (③⑥ entirely, ①④ in part):
--   ① G1  — an aborted run's basis: `dog_condition` charges FULL ACTUALS, i.e. it stops being a
--           special case at all; `incident` charges nothing, but the waive becomes REVIEWABLE.
--   ③ OPS — "build for full scale, not just for pilot": a dedicated `ops_recipients` table with
--           per-event-class routing, replacing the single `OPS_PROFILE_ID` env var.
--   ⑥     — the cutover straddle: `payments_live_since` is set to a FUTURE timestamp past the
--           longest in-flight booking, never to `now()`. A guard, because a decision that lives
--           only in a memo is one `update ops_flags set … = now()` away from being undone.
--   ④     — club price-invisibility. Mostly the client's job (the session screen showed the fare
--           at five points), but the SIXTH display is SQL and therefore this file's: §F removes
--           the fare, and the retired 결제 verb, from `session_approve_dog`'s owner notification.
-- The rest is not SQL: ② (D-3, "accept as-is") builds nothing, ⑤ is the client's card-register
-- pointer, and ④'s other five surfaces are `app/app/club/session/[sid].tsx` + `[id].tsx`.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - It does not change any PRICE. `club_fare` (0043:14) keeps its 9,900 base — ruling ④ is
--   "keep 9,900 as a STATED premium, and make the club price-invisible", so the formula was ruled
--   ON and left alone, and 117 K3-K7 / 50 D5's literals stand unchanged. §F removes a DISPLAY of
--   that price, never the price. The single surviving disclosure is the client's 승낙서
--   (`app/app/club/delegate/[sid].tsx`, "요금 안내는 여기 한 번이에요"); §F's replacement sentence
--   was checked against it and does not contradict or duplicate it.
-- - It does not change the runner's side of an abort. `settle_run_tx` pays the runner exactly as
--   it does today; §0-bis's platform-absorb doctrine is untouched (and §A comments the asymmetry
--   that creates, because it is the number to watch).
-- - It does not send a single notification. `ops_recipients_for()` REPORTS who should be told;
--   the sending lives in `_shared/ops.ts` (Unit Q, same slice), and the env-var fallback stays
--   there. This file's honest answer to "nobody is subscribed" is zero rows, not a guess.
-- - It does not close the `incident` self-serve hole. Under ruling ①, `end_reason: 'incident'`
--   means "the owner is charged nothing", and `settle-run/handler.ts:30` whitelists all six enum
--   members on a PUBLIC endpoint — so an assigned runner could POST it and hand themselves a free
--   run. That fix is a TypeScript refusal list (Unit Q) and cannot be written here; §B's review
--   marker is the SQL half of "verify incident first" and is not a substitute for it.
-- - It does not touch `ops_flags`'s shape, the mints' idempotence, the advisory locks, the debt
--   derivation, the sweeps, or any of 0081/0082.
--
-- ═══ §0c CORRECTIONS TO SHIPPED FILES (they are immutable — 0057 §2 — so they land here) ═══
-- ⚠ **0080:79-82 (§0d step ⑦) is now WRONG and must not be followed.** It says:
--       `update ops_flags set payments_live_since = now(), updated_at = now();`
--   Ruling ⑥ replaces it. `now()` is precisely the value that charges the straddlers — a booking
--   confirmed before the flip (through a gate that did not require a card) and settled after it.
--   The adversarial round executed that case: a card-less owner confirmed a club seat pre-flip,
--   the switch was set to now(), the run settled, and a `24,900 pending settle_charge` was minted
--   against an owner with zero cards; it dispatches, fails, and the debt derivation locks the
--   account. The club window is the widest of the three booking paths because a session's
--   `scheduled_at` is unbounded. The correct step ⑦ is now:
--       `select longest_inflight_booking_end();`          -- §D: the value to clear
--       `select set_payments_live_since('<that + margin>');`  -- §D: refuses anything in the past
--   Straddlers then stay free by construction. `docs/plans/payments-toss-plan.md` and the
--   handoff's flip procedure carry the same correction in prose; this comment is the copy that
--   sits next to the switch.
-- ⚠ **0080:228-232's provisional is RETIRED.** The old rule string `g1_waive` (kept here as the
--   grep handle it was designed to be) no longer exists in any code path: `dog_condition` answers
--   `actual_capped` like any other measured end, and `incident` answers `incident_pending_review`.
--   Anything still grepping `g1_waive` is reading a decision Sean overruled.
-- ⚠ **116 C1/C6/C9/C23 were amended by this slice**, which is the one place it edits a shipped
--   suite. It is not a drive-by: those four pins assert the retired provisional as a literal
--   (`amount 0`, `rule 'g1_waive'`), so the ruling cannot land while they stand, and 0080:231-232
--   named the pin as part of the change ("the change is this one arm plus its pin"). The
--   amendments are exactly: C1's single G1 line SPLIT IN TWO (dog_condition → the actual-basis
--   charge, the same value the `completed` arm asserts on the same fixture; incident → waived ₩0);
--   C6, C9 and C23 re-point their waive fixtures from `dog_condition` (which is now an ordinary
--   charge) to `incident` (which is the only remaining zero-with-a-rule). No other pin, argument
--   or fixture in 116 moved. Everything this file adds is pinned in 120, not in 116.
-- ⚠ **WHOSE `compute_owner_charge` / `mint_settle_charge_intent` / `payments_reconciliation` THIS
--   BUILDS ON:** 0080's, unamended by anything else at the time of writing (0081 and 0082 do not
--   touch any of the three; `git log -p supabase/migrations -S compute_owner_charge` confirms one
--   definition before this file). All three are shared objects and `create or replace` is silent
--   about collisions — if another migration in the same window also recreates one of them, the
--   later `supabase db push` simply wins and no suite can see the loss. That is the class
--   `supabase/migrations/REGISTRY.md` now warns about; this file's three are named there.
--
-- ═══ §0d DOCTRINE (0059 money-path list) ═══
-- self-contained migration · byte-faithful reproduction of the latest definition (0057 §2) ·
-- every definer carries `set search_path = public, pg_temp` IN THE BODY (98 H1 — ALTER-applied
-- config is reset by `create or replace`) · sealed tables get RLS on and ZERO policies ·
-- revoke from public/anon/authenticated, grant to service_role · mutation-proven pins
-- (`120_g1_ops_cutover_suite.sql`, J1-J10). Pins this file must not break: 116 C1-C25 (the charge
-- machine, four of them amended per §0c), 117 K1-K8 (club gates), 109 P4-P11 (payments shape),
-- 110 S1-S6 (incident settlement — 0072 still owns the money question an incident raises),
-- 50 D5/D7/D12 + 30/65/95/107 (the delegation flow §F reproduces).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A compute_owner_charge — the last hole in the basis table, closed by ruling ①
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Recreated under 0057 §2 reproduction discipline: the 0080:236-297 body, byte-faithful, with
-- exactly one change — the shared `dog_condition`/`incident` → `g1_waive` return is replaced by
-- an `incident`-only waive, and `dog_condition` is simply no longer mentioned in the function.
--
-- ⓐ `dog_condition` → **FULL ACTUALS. It is not a special case, and the cleanest statement of
--    that is its absence: the reason is not named anywhere in the function body.** An aborted run
--    is billed for what happened — `base_fare + round(distance_fare/km × min(actual, planned)) +
--    addon_fare`, rule `actual_capped`, identical in every respect to a completed run of the same
--    measured distance. There is deliberately NO `condition_*` rule string, because a rule string
--    is a price with a name and there is no longer a condition price.
--    Sean confirmed this directly on 2026-08-13 after two sessions recorded the ruling
--    differently (one had "base fee only, 7,900 flat"); that reading is withdrawn.
--
--    ⓐ-1 **WHY THIS IS THE SAFE ANSWER, and not merely the simple one.** Both adversarial rounds
--    worried about the same hole: `completion_rate` counts only `completed` + `runner_personal`,
--    so `dog_condition` is a stat-free early exit for a runner — and a WAIVED owner never disputes
--    a fabricated abort, which removes the free fraud detector (the card statement is the cheapest
--    audit the product has). That worry was entirely premised on the owner paying nothing. Under
--    full actuals the owner pays, so the owner disputes, and per-runner abort telemetry becomes a
--    backstop rather than the only signal there is.
--
--    ⓐ-2 **THE ACCEPTED COST, named because it will be re-litigated the first time it happens.**
--    A dog that limps at 200m is billed roughly ₩8,500 — the base is charged from the first metre
--    and only a sub-₩100 total auto-waives (the ⑤ arm below). Sean accepted that explicitly. The
--    mitigation is COPY, not money: the run report must say that stopping was the right call and
--    surface the runner's own `condition_note` (which `settle-run` already enforces on this
--    reason, so the sentence always has evidence behind it). That surface belongs to the
--    run-end-flow slice (0083) — this file records the dependency and does not build it.
--    ⚠ Do not "fix" this later by adding a condition discount here. The decision was to make the
--    abort honest and the report kind; a quiet discount would undo ⓐ-1 without saying so.
--
-- ⓑ `incident` → **0, rule `incident_pending_review`** (was `g1_waive` — kept in this sentence as
--    the grep handle 0080:232 promised, so the old marker still finds this argument).
--    The amount is unchanged and the reason it must stay 0 is architectural, not generous:
--    `club_incident_settle` (0072) already owns the money question an incident raises, quoting
--    `refund_full | settle_measured | pay_full` for a human to decide. Charging at settle would
--    pre-empt that decision and manufacture the refund post-pay deleted.
--    What changes is that the zero is now VISIBLE: the rule string says a case is open, §B writes
--    the review marker onto the row, and §C gives it an ops arm. Sean's ruling was "incident → 0,
--    **but verify incident first to avoid abuse of this feature**" — the verification itself is
--    Unit Q's refusal list in `settle-run` (§0b), and this is the ledger half of it.
--
-- Everything else below is 0080's, unchanged: the frozen numbers (§0-ter #6), the min(actual,
-- planned) ceiling (#4), D2's exactly-planned arm, runner_personal's distance-only arm (#10), the
-- sub-₩100 floor (round-2 R1 P2-2), and the unknown-end_reason raise. The floor arm is now
-- REACHED by the condition arm too — a booking whose frozen base is above zero but under ₩100 is
-- as uncollectable as any other sub-floor amount, and duplicating the check inside the new arm
-- would be one rule written twice. That is why the arm falls through instead of returning early;
-- `incident` returns early because zero is not "too small to charge", it is a decision.
create or replace function compute_owner_charge(
  p_booking uuid, p_end_reason text, p_actual_km numeric
) returns table (amount int, basis_km numeric, rule text)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- Toss's published card minimum is ₩100 (docs.tosspayments.com — 최소 결제 금액). Named rather
  -- than inlined because it is THEIR number, not ours: verify it in the sandbox at toss-plan §4-2
  -- before the cutover and change it here, in one place, if their floor has moved.
  PG_MIN_CHARGE constant int := 100;
  b record;
  v_basis numeric;
  v_distance int;
  v_amount int;
  v_rule text;
begin
  select bk.km, bk.base_fare, bk.distance_fare, bk.addon_fare
    into b
  from bookings bk where bk.id = p_booking;
  if b.km is null then raise exception 'not_found'; end if;

  if p_end_reason is null or p_end_reason not in
     ('completed', 'dog_condition', 'owner_request', 'runner_personal', 'owner_forced', 'incident')
  then
    raise exception 'unknown_end_reason';
  end if;

  -- ⓑ [0084 §A] a case is open; 0072 decides the money, not this function.
  if p_end_reason = 'incident' then
    return query select 0, 0::numeric, 'incident_pending_review'::text;
    return;
  end if;

  -- ⓐ [0084 §A] `dog_condition` IS NOT NAMED BELOW, and that absence is the ruling. An aborted
  -- run is billed for what happened, exactly like a completed one — same actual-basis path, same
  -- ceiling, same `actual_capped` rule string. There is deliberately no `condition_*` rule to
  -- grep for, because there is no longer a condition-specific price.
  if p_end_reason in ('owner_request', 'owner_forced') then
    v_basis := b.km;                                   -- D2: exactly planned, not min()
    v_rule  := 'owner_caused_planned';
  else
    v_basis := least(greatest(coalesce(p_actual_km, 0), 0), b.km);   -- the ceiling
    v_rule  := case when p_end_reason = 'runner_personal'
                    then 'runner_personal_distance_only' else 'actual_capped' end;
  end if;

  -- distance component from the FROZEN per-km implied by this booking's own two numbers.
  v_distance := round(coalesce(b.distance_fare, 0)::numeric / nullif(b.km, 0) * v_basis)::int;

  if p_end_reason = 'runner_personal' then
    v_amount := coalesce(v_distance, 0);               -- no base, no addons (§0-ter #10)
  else
    v_amount := coalesce(b.base_fare, 0) + coalesce(v_distance, 0) + coalesce(b.addon_fare, 0);
  end if;

  -- ⑤ under the PG's floor (round-2 R1 P2-2): a charge Toss will not accept must never become an
  -- intent. The mint reads amount 0 and writes a `waived` row, so the event is still recorded —
  -- we looked, and the answer was "too small to charge" — with no ladder and no false debt.
  if v_amount > 0 and v_amount < PG_MIN_CHARGE then
    return query select 0, v_basis, 'below_pg_minimum'::text;
    return;
  end if;

  return query select v_amount, v_basis, v_rule;
end $$;
-- 0080:298-299's seal restated (create-or-replace preserves ACLs; this is belt, and it keeps the
-- money function's grant matrix readable in the file that last changed its answer).
revoke execute on function compute_owner_charge(uuid, text, numeric) from public, anon, authenticated;
grant execute on function compute_owner_charge(uuid, text, numeric) to service_role;

comment on function compute_owner_charge is
  '0084 §A (was 0080 §D): THE owner charge basis table. Frozen booking numbers only ·
basis = min(actual, planned) · owner_request/owner_forced = exactly planned (D2) ·
runner_personal = distance component only (#10) · [0084, Sean 2026-08-13 ruling ①]
dog_condition is NOT a special case — an aborted run is billed for what happened, on the same
actual_capped path as completed (no condition rule string exists, deliberately; the owner pays, so
the owner disputes, which is the fraud detector a waive removed) · incident = 0, rule
incident_pending_review (0072 owns an incident''s money; the zero is now reviewable, see §B/§C) ·
0 < amount < 100 = 0 / below_pg_minimum · unknown end_reason raises. Pinned by 120 J1-J2, 116 C1-C4/C23';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B the incident waive becomes REVIEWABLE, not silent
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Recreated under 0057 §2: the 0080:346-404 body, byte-faithful, with exactly one change — the
-- `raw` object gains a review marker when the rule is incident-class.
--
-- WHY A MARKER AND NOT JUST A RULE STRING. `raw.rule` records what the machine decided; the
-- marker records that a HUMAN still owes an answer. They are different facts and they end at
-- different times: the rule is permanent, the review closes. Without the marker, "we charged
-- nothing because a case is open" and "the case was looked at and nothing was owed" are the same
-- row forever, and §C's arm would have nothing to stop listing.
--
-- The fraud argument is the reason this is not decoration (memo ①, the parallel session's sharper
-- framing): **a waived owner never disputes a fabricated abort.** Charging is the free fraud
-- detector — the owner reads their card statement and complains. Waiving removes it. So the waive
-- has to be replaced by a human looking, and a marker nobody reads is not a human looking, which
-- is why §C exists in the same file.
--
-- `review_opened_at` is written as a jsonb timestamp so §C can age it. Resolution is the ABSENCE
-- of `review_resolved_at` (see §C): nothing writes that key today — 0072's `club_incident_settle`
-- is the intended writer when the case closes, and wiring it is out of this slice by the same R6
-- boundary 0080 §J-ⓑ respected. Until then every incident waive stays on the ops board, which is
-- the correct failure direction: an unread board is a visible backlog, a silent one is not.
create or replace function mint_settle_charge_intent(
  p_booking uuid, p_end_reason text, p_actual_km numeric
) returns table (payment_id uuid, order_id text, amount int, status text, minted boolean)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_existing payments%rowtype;
  v_charge   record;
  v_row      payments%rowtype;
  v_order    text;
  v_since    timestamptz;
  v_ended    timestamptz;
begin
  select f.payments_live_since into v_since from ops_flags f where f.id;
  if v_since is null then return; end if;                       -- charging is off: write nothing
  select coalesce(r.ended_at, now()) into v_ended from runs r where r.booking_id = p_booking;
  if coalesce(v_ended, now()) < v_since then return; end if;    -- pilot-era run: free, forever

  -- Serialize every minter of THIS booking (round-2 R1 P1-1 — see 0080's §E header). Taken after
  -- the cutover guards so a not-live call costs nothing, and before the exists-check because the
  -- exists-check is exactly the read the race defeats. Transaction-scoped: released on commit or
  -- abort, so a crashed minter cannot wedge the booking. Pinned by 90_race_check.sh RD.
  perform pg_advisory_xact_lock(hashtextextended('mint:' || p_booking::text, 0));

  select p.* into v_existing
  from payments p
  where p.booking_id = p_booking
    and (p.status in ('confirmed', 'waived')
         or ((p.raw->>'kind') is not null and p.status in ('pending', 'failed')))
  order by case when p.status in ('confirmed', 'waived') then 0 else 1 end, p.created_at
  limit 1;

  if v_existing.id is not null then
    return query select v_existing.id, v_existing.order_id, v_existing.amount,
                        v_existing.status, false;
    return;
  end if;

  -- Raises on an unknown end_reason — the mint fails closed with it (§A).
  select c.amount, c.basis_km, c.rule into v_charge
  from compute_owner_charge(p_booking, p_end_reason, p_actual_km) c;

  -- create-payment-intent/handler.ts:68 idiom — `dr_` + a UUID, ours, never the client's.
  v_order := 'dr_' || gen_random_uuid()::text;

  insert into payments (booking_id, order_id, amount, status, raw)
  values (
    p_booking, v_order, v_charge.amount,
    case when v_charge.amount = 0 then 'waived' else 'pending' end,
    jsonb_build_object('kind', 'settle_charge', 'rule', v_charge.rule,
                       'basis_km', v_charge.basis_km, 'end_reason', p_end_reason)
    -- attempts only on a row that will actually be dispatched; a waived row has no ladder.
    || case when v_charge.amount = 0 then '{}'::jsonb else jsonb_build_object('attempts', 0) end
    -- [0084 §B] the incident waive is reviewable. Keyed on the RULE, not on end_reason: the rule
    -- is what §A decided, and an end_reason that lands somewhere else (the sub-floor arm, say)
    -- must not inherit a case that does not exist.
    || case when v_charge.rule = 'incident_pending_review'
            then jsonb_build_object('review', 'incident_pending', 'review_opened_at', now())
            else '{}'::jsonb end
  )
  returning * into v_row;

  return query select v_row.id, v_row.order_id, v_row.amount, v_row.status, true;
end $$;
revoke execute on function mint_settle_charge_intent(uuid, text, numeric) from public, anon, authenticated;
grant execute on function mint_settle_charge_intent(uuid, text, numeric) to service_role;

comment on function mint_settle_charge_intent is
  '0084 §B (was 0080 §E): idempotent single-truth minting of the settle-time charge intent. Zero
rows while ops_flags.payments_live_since is null or the run ended before it (no pre-cutover
intents, no retroactive billing — 0080 §0c). Otherwise returns the existing row with minted=false
rather than ever writing a second one — which holds under CONCURRENCY only because of the
per-booking pg_advisory_xact_lock taken first. amount 0 → a waived row, so invariant #1 stays
exception-free. [0084, ruling ①] an incident-class waive additionally carries
raw.review = ''incident_pending'' + raw.review_opened_at, so the zero is reviewable rather than
silent and payments_reconciliation() can list it (§C). Pinned by 120 J3, 116 C5/C6/C22';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C payments_reconciliation gains a fifth arm — somebody reads the open reviews
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Recreated under 0057 §2: the 0080:855-901 body, byte-faithful, plus one union arm.
-- The five kinds stay DISJOINT BY STATUS, which is how the previous four already were:
--   orphan_capture    status = 'confirmed'
--   stale_pending     status = 'pending', never dispatched
--   stale_dispatched  status = 'pending', dispatched
--   ladder_exhausted  status = 'failed'
--   incident_waive_pending  status = 'waived'   ← the new one; no other arm reads 'waived'
-- An operator query that lists one row twice under two names is a query people stop reading
-- (0080's own argument, still the reason).
--
-- `age` is measured from `review_opened_at`, not from `created_at`: the operator's question is
-- "how long has this case been waiting on me", and for a row minted at settle those two are the
-- same instant today — but they stop being the same the moment anything re-opens a review, and
-- the honest column is the one that answers the question being asked.
--
-- "No resolution" is `review_resolved_at is null`. Nothing writes that key yet (§B says why), so
-- today the arm lists every incident waive ever minted. That is deliberate and it is the safe
-- direction: a backlog that grows visibly is a backlog somebody closes, and the alternative —
-- inventing a resolution the product cannot yet record — would make the board lie by omission.
create or replace function payments_reconciliation()
returns table (
  kind text,
  payment_id uuid,
  booking_id uuid,
  amount int,
  payment_status text,
  booking_status text,
  needs_manual_cancel boolean,
  age interval
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select 'orphan_capture'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         coalesce((p.raw->>'needs_manual_cancel')::boolean, false), now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'confirmed'
    and b.status in ('draft', 'quoted', 'payment_hold', 'expired')
  union all
  select 'stale_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending' and p.created_at < now() - interval '1 hour'
    and (p.raw->>'dispatched_at') is null
  union all
  -- [0080 §0-ter #2] we told Toss to charge and never learned the outcome. Resolve by querying
  -- Toss with our orderId (tossGetByOrderId) — never by guessing, and never by auto-failing.
  select 'stale_dispatched'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'dispatched_at')::timestamptz
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending'
    and (p.raw->>'dispatched_at') is not null
    and (p.raw->>'dispatched_at')::timestamptz < now() - interval '1 hour'
  union all
  -- [round-2 R1 P3] the ladder is SPENT: three attempts, still failed. `dispatch_due_charges`
  -- deliberately stops counting these rows as due, so nothing automatic will ever touch them
  -- again — they are debt (§F locks the owner) with no timer behind it, waiting on the owner's
  -- manual CTA or on a human. Without this arm the ops query shows an empty board while the
  -- accounts that most need attention sit invisible. Disjoint from the three above by status.
  select 'ladder_exhausted'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'failed'
    and (p.raw->>'kind') is not null
    and coalesce((p.raw->>'attempts')::int, 0) >= 3
  union all
  -- [0084 §C, ruling ①] the owner was charged NOTHING because a case is open. Nothing automatic
  -- will ever revisit that row — a waive has no ladder by construction (§B) — so this arm is the
  -- entire difference between "reviewable" and "silent". 0072's adjudication is what decides the
  -- money; this is the list of decisions nobody has made yet.
  select 'incident_waive_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'review_opened_at')::timestamptz
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'waived'
    and (p.raw->>'review') = 'incident_pending'
    and (p.raw->>'review_resolved_at') is null
$$;

comment on function payments_reconciliation is
  '0084 §C (was 0080 §I): 결제 조정 질의 5종 — orphan_capture(돈은 받았는데 부킹이 못 감) ·
stale_pending(1시간+ 미발송 인텐트) · stale_dispatched(토스에 보냈는데 결과를 모르는 행) ·
ladder_exhausted(3회 실패로 래더가 끝난 행) · [0084] incident_waive_pending(사건이라 0원으로
면제했는데 아직 아무도 판단하지 않은 행 — 면제된 보호자는 위조된 중단을 항의하지 않으므로,
사람이 보는 것이 유일한 대체 탐지기다). 상태로 서로소(confirmed/pending/pending/failed/waived).
Pinned by 120 J4, 116 C11';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D ops_flags gains a GUARD and a query — ruling ⑥, executable
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Sean's ruling: `payments_live_since` is set to a FUTURE timestamp past the longest in-flight
-- booking, never to `now()`. His own words on why it needs code and not just a memo: "a decision
-- that lives only in a memo is one `update ops_flags set … = now()` away from being undone."

-- ⓐ The value the operator needs before they can honour ⑥ at all.
-- Max `scheduled_at + duration` over LIVE bookings, where duration is the repo's one formula
-- (`km * 8 + 25` minutes — 0026:721, `create-booking-hold`, and 0081:162 all write it the same
-- way) and "live" is the same status set the overlap guards use. NULL when nothing is in flight,
-- which reads correctly as "no straddler to clear".
-- Deliberately NOT a materialized fact and deliberately not called by the setter: this is a
-- question the operator asks and then decides on, with a margin of their choosing. Wiring it into
-- the setter would turn a judgement into an automatic value and hide the one number Sean asked
-- to see.
create or replace function longest_inflight_booking_end() returns timestamptz
language sql stable security definer
set search_path = public, pg_temp
as $$
  select max(b.scheduled_at + make_interval(mins => (b.km * 8 + 25)::int))
  from bookings b
  where b.status in ('matching', 'runner_pending', 'confirmed',
                     'runner_enroute', 'picked_up', 'active')
$$;
revoke execute on function longest_inflight_booking_end() from public, anon, authenticated;
grant execute on function longest_inflight_booking_end() to service_role;

comment on function longest_inflight_booking_end is
  '0084 §D (ruling ⑥): the moment the last currently-live booking is expected to end
(max scheduled_at + (km*8+25)min over matching/runner_pending/confirmed/runner_enroute/picked_up/
active). The operator''s input to set_payments_live_since — a cutover past this value has no
straddlers by construction. NULL = nothing in flight. Club sessions make this unbounded, which is
why the number has to be looked up rather than guessed. Pinned by 120 J8';

-- ⓑ The setter that refuses the undoing.
-- Past (and `now()` itself, which is the exact value 0080 §0d ⑦ used to prescribe) → refused.
-- A future timestamp → accepted. NULL → accepted, deliberately: turning charging OFF is the
-- emergency lever, it is the safe direction in every case (nothing that is not charged can be
-- wrongly charged), and refusing it would leave a raw UPDATE as the only way to stop the machine
-- — which is precisely the habit this function exists to replace.
--
-- ⚠ HONEST LIMIT, stated because the alternative is a false sense of a seal: this is a SETTER,
-- not a constraint. `update ops_flags set payments_live_since = now()` still works for anyone
-- holding service_role or a SQL console. The airtight form is a BEFORE UPDATE trigger on
-- ops_flags, and it is not written here for a concrete reason: five shipped pins across two
-- suites this slice may not edit (116 C14/C22, 117 K4/K5/K6) set the flag to `now() - interval
-- '7 days'` on purpose, because simulating the post-cutover era is the only way to test the
-- machine at all. A trigger would fail the harness rather than fail a mistake. The correct
-- sequencing is a follow-up slice that gives the suites a bypass (a session GUC, the 0082 §E
-- `app.route_promote` pattern) and then adds the trigger; it belongs in TODOS, not in a comment
-- that pretends the hole is closed.
create or replace function set_payments_live_since(p_when timestamptz) returns timestamptz
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  -- `<=` and not `<`: `now()` is transaction start time, so passing now() compares equal — and
  -- `= now()` is the literal value ruling ⑥ overturned, so it has to be the refused case rather
  -- than the boundary that squeaks through.
  if p_when is not null and p_when <= now() then
    raise exception 'cutover_must_be_future'
      using hint = 'select longest_inflight_booking_end() — set the cutover past it, or a booking confirmed before the flip gets charged after it';
  end if;

  update ops_flags set payments_live_since = p_when, updated_at = now() where id;
  return p_when;
end $$;
revoke execute on function set_payments_live_since(timestamptz) from public, anon, authenticated;
grant execute on function set_payments_live_since(timestamptz) to service_role;

comment on function set_payments_live_since is
  '0084 §D (ruling ⑥): the cutover setter. REFUSES any timestamp at or before now()
(cutover_must_be_future) — a booking confirmed pre-flip passed a gate that did not require a card
and would then be charged post-flip, which the adversarial round executed for real (a card-less
owner, a 24,900 pending intent, an account lock). NULL is accepted: turning charging off is the
safe direction and the emergency lever. A setter, not a trigger — see the §D comment for why the
airtight version waits on giving the suites a bypass. Pinned by 120 J7';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E ops_recipients — ruling ③, "build for full scale, not just for pilot"
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Sean was recommended A (keep the `OPS_PROFILE_ID` env var, pilot-sized) and ruled C, the
-- dedicated table. Taking C over B (`profiles.is_ops`) is about ROUTING and not merely plurality:
-- the machine already emits distinct marker classes, and at scale they do not all go to the same
-- person. One operator subscribes to money, another to safety, with no code change and no
-- redeploy.
--
-- SEALED the way `billing_keys` and `ops_flags` are (68 V1's law): RLS on, ZERO policies, server
-- only. This table decides WHO receives operational alerts, so a client write is a subscription
-- to other people's incidents — and a client READ is a staff roster. Neither has a client
-- surface, today or planned.
create table if not exists ops_recipients (
  profile_id uuid not null references profiles on delete cascade,
  event_class text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (profile_id, event_class)
);
alter table ops_recipients enable row level security;

-- Deliberately NO check constraint on `event_class`, and the reasoning is worth more than the
-- column: a constrained vocabulary makes adding an emitter a MIGRATION, and the failure mode of a
-- wrong string here is already safe — `ops_recipients_for()` returns zero rows, and the caller
-- falls back to `OPS_PROFILE_ID` (Unit Q). A typo therefore degrades to today's behaviour, never
-- to silence. A check constraint would trade that for a deploy-order hazard, which is the worse
-- trade for a routing table. The vocabulary lives in this comment instead, and it is the contract
-- the edge functions match on.
comment on table ops_recipients is
  '0084 §E (ruling ③, Sean 2026-08-13 "build for full scale, not just for pilot"): per-event-class
ops routing, replacing the single OPS_PROFILE_ID env var. SEALED — RLS on, zero policies; nothing
client-side reads or writes it (a read is a staff roster, a write is a subscription to other
people''s incidents). Read only through ops_recipients_for(event_class), service_role.
EVENT CLASSES (no check constraint on purpose — see the comment above the table):
  payment_manual_cancel   — a capture could not be auto-cancelled; a human must cancel it in the
                            Toss console (confirm-payment/handler.ts notifyOps; orphan_capture)
  charge_ladder_exhausted — 3 attempts, still failed: debt with no timer behind it
                            (payments_reconciliation ladder_exhausted)
  charge_dispatch_stale   — dispatched to Toss, outcome never learned (stale_dispatched)
  settled_without_payment — a settled booking with no payments row (invariant #1, 0080 §G)
  enroute_comp_failed     — the runner''s en-route cancel compensation was not written
                            (transition-booking/cancel_owner.ts)
  incident_waive_pending  — [0084 §C] an incident waive nobody has adjudicated
⚠ The payload the caller sends stays REDACTED — no order ids, no amounts, no booking ids in a
notification body (2026-08-13 hardening: a wrong recipient id pushes the body verbatim to a real
user''s lock screen). This table changes WHO is told, never WHAT they are told.';
comment on column ops_recipients.active is
  '0084: false = unsubscribed without losing the row (who used to be on call is an audit fact).
ops_recipients_for() returns active rows only';

-- Routing lookup. Returns nothing but profile ids: the caller composes the notification, so this
-- function can never become the thing that decides what an operator is told.
-- ZERO ROWS IS AN ANSWER, not an error. If no active recipient is subscribed to the class, the
-- caller falls back to `OPS_PROFILE_ID` and, failing that, logs loudly — today's behaviour,
-- preserved for exactly one release so a mis-provisioned table cannot silence ops. That fallback
-- lives in `_shared/ops.ts` (Unit Q); the SQL's whole job is to report emptiness honestly rather
-- than to paper over it with a default recipient nobody chose.
create or replace function ops_recipients_for(p_event_class text) returns setof uuid
language sql stable security definer
set search_path = public, pg_temp
as $$
  select r.profile_id
  from ops_recipients r
  where r.event_class = p_event_class
    and r.active
  order by r.created_at, r.profile_id
$$;
revoke execute on function ops_recipients_for(text) from public, anon, authenticated;
grant execute on function ops_recipients_for(text) to service_role;

comment on function ops_recipients_for is
  '0084 §E (ruling ③): active recipients for one event class, oldest subscription first (a stable
order so a two-operator class notifies in the same sequence every time). ZERO ROWS = nobody is
subscribed, which the caller reads as "use the OPS_PROFILE_ID fallback" — the honest report, not
an error and not a silent default. service_role only: the roster is not a client fact.
Pinned by 120 J5-J6, J9';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §F the SIXTH club price display — and it is in a notification, not on a screen
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Ruling ④ is "keep 9,900 AND make the club price-invisible — although notifying the price once".
-- The client unit collapses five in-screen displays down to one disclosure at the join/consent
-- moment (`app/app/club/delegate/[sid].tsx`, the 승낙서 — that is where the ONE disclosure now
-- lives). This is the sixth, and no client change can reach it: `session_approve_dog` writes
--     '20분 안에 결제하면 자리가 확정돼요 · ' || club_fare(<route km>) || '원'
-- into the owner's inbox (0043:283), and the app renders notification bodies VERBATIM (0024's
-- insert trigger also pushes them to the lock screen). So after the client work the price would
-- still surface a second time, in the 알림 list, on a schedule nobody controls.
--
-- Two things are wrong with that sentence and only one of them is the price:
--   ⓐ the FARE — a second disclosure, which is exactly what ④ says there must not be.
--   ⓑ the VERB — '결제하면 자리가 확정돼요' says money moves at this step. It does not, in either
--      era. 0081 §B already retired that claim from the CONFIRMATION notification for the same
--      reason ("'결제 완료'는 어느 시대에도 참이 아니다"); this is the same lie one step earlier,
--      in the sentence that tells the owner what to do next. Post-cutover it is worse than
--      inaccurate: the charge happens after the RUN, so "결제하면 확정" describes an order of
--      events that does not exist.
-- The replacement says the only thing that is true at this moment: the seat is held for 20
-- minutes and the owner has to confirm it.
--
-- Recreated under 0057 §2 reproduction discipline: the 0043:252-286 body, byte-faithful, with
-- exactly two changes.
--   ⓐ header `search_path = public` → `public, pg_temp` (98 H1 law — 0055's ALTER is reset by
--      `create or replace`, so it belongs in the body; the same change 0080 §H and 0081 §A made).
--   ⓑ the approval notification BODY. Everything else is 0043's: the host gate, the pending gate,
--      the session-status gate, the capacity recount, the 20-minute hold, the rejection branch and
--      its sentence, the return values.
-- ⚠ NOT CHANGED, and named so the next author knows it was seen: the notification TITLE is still
--    '위탁 승인 — 결제 대기', which carries the same retired verb. It is left alone because this
--    slice's mandate was the body, and a title is what other surfaces match on (0081 §0d ①'s
--    lesson: three shipped suites assert club notification titles verbatim, so a title change is
--    its own slice with its own pin sweep). 117's K6 shape is the model for whoever does it.
-- ⚠ ALSO NOT CHANGED: `club_fare` itself keeps its PUBLIC-revoked/authenticated grant from
--    0081 §C. This function simply stops calling it — the board impls still do.
create or replace function session_approve_dog(p_session_dog uuid, p_approve boolean) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  sd record; s record; v_reserved int;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.custody <> 'runner_delegated' or sd.approval <> 'pending' then raise exception 'not_pending'; end if;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  if not p_approve then
    update session_dogs set approval = 'rejected' where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (sd.owner_profile_id, 'community', '위탁 신청 거절',
            '이번 세션에는 함께하지 못하게 됐어요', sd.session_id);
    return null;
  end if;

  v_reserved := _club_delegated_reserved(sd.session_id);
  if v_reserved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;

  update session_dogs set approval = 'approved',
    hold_status = 'active', hold_expires_at = now() + interval '20 minutes'
  where id = p_session_dog;

  -- ⓑ [0084 §F, ruling ④] 요금 없음, '결제' 없음. 가격 고지는 승낙서 한 곳뿐이고, 이 단계에서
  -- 움직이는 돈은 없다 (컷오버 뒤에도 청구는 러닝이 끝난 뒤다 — 0081 §B와 같은 문장 규율).
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (sd.owner_profile_id, 'booking', '위탁 승인 — 결제 대기',
          '20분 안에 자리를 확정하면 돼요', sd.session_id);
  return p_session_dog;
end $$;
-- 0037:459's ACL restated (positive grant — the host's approve button stops working without it;
-- `create or replace` preserves it, so this is belt, not a change — 0080 §J-ⓑ's precedent).
grant execute on function session_approve_dog(uuid, boolean) to authenticated;

comment on function session_approve_dog is
  '0084 §F (was 0043 §R1): 승인 = 20분 홀드만 — 부킹·클래시 가드는 결제 RPC로 이동(0043 본문 그대로).
[0084, 메모 ④] 승인 알림 본문에서 요금과 ''결제'' 동사 제거: 클럽 가격 고지는 승낙서 한 번뿐이고
(앱은 알림 본문을 그대로 렌더한다 — 화면을 아무리 고쳐도 이 문장은 남는다), 이 단계에서는 어느
시대에도 돈이 움직이지 않는다. 제목 ''위탁 승인 — 결제 대기''는 이번 범위 밖으로 남겨뒀다.
Pinned by 120 J10';
