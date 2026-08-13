-- ═══ 0080: the settle-time CHARGE MACHINE — post-pay, per-run, invisible ═══
--
-- Source of truth: `docs/plans/payments-toss-plan.md` §0-bis (Sean, 2026-08-12 — two-way
-- payments become one way: per-run, INVISIBLE, POST-PAY) and §0-ter (the engineering pass that
-- resolves §0-bis's NEEDS-ENG-PASS), INCLUDING all of §0-ter's absorbed adversarial round-1
-- findings. Finding numbers are cited inline as `§0-ter #n` — every one of them is a decision
-- somebody already argued for, and the citation is how the next author finds that argument.
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- 0071 gave us a row that says money arrived. 0076 made that row exist BEFORE the money moves.
-- This file answers the question both of them left open: **who decides how much, and when.**
--   booking is free → matching is free → the run happens → `settle_run_tx` commits FIRST
--   (the runner is paid) → and only then does the owner's card get charged, on the booking's
--   FROZEN numbers with basis `min(actual, planned)`.
-- The charge is therefore never in the settlement transaction, never in front of the service,
-- and never computed from live constants.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - It does not charge anyone. `net.http_post` → `collect-charges` (§K) is the only outbound
--   edge here, and it is inert until Sean sets the vault secret AND the edge function exists.
-- - It does not touch `settle_run_tx` (0028:18-167). That function's atomic claim
--   (`active → completed`, 0 rows → `not_active`) is THE settlement anchor; the ordering law
--   (§0-ter: settlement never waits on collection) is exactly the statement that this file's
--   code runs after that function returns, from the edge, outside its transaction.
-- - It does not add a booking status, an enum value, or a transition-map edge (toss-plan §0;
--   `109 P6` keeps that premise honest).
-- - It adds NO cached collection state. Debt is DERIVED (§F) — repo law, no `collection_status`
--   column, ever.
--
-- ═══ §0c THE CUTOVER SWITCH (§C) ═══
-- `ops_flags.payments_live_since` is NULL in this migration and stays NULL until **Sean flips
-- it**, which is a timestamp and not a boolean:
--   `update ops_flags set payments_live_since = now(), updated_at = now();`
-- It is a MOMENT because two hazards showed up in the build (Unit B's report, 2026-08-13) that
-- a boolean cannot express:
--   ⓐ While charging is off, minting settle intents for card-less pilot owners would leave
--      `pending` rows that the 1h stale sweep (§I) flips to `failed` — manufacturing debt, and
--      through §F an account lock, for the entire pilot. So while NULL, the mints write NOTHING.
--   ⓑ A plain boolean flip would let §G's sweep retroactively mint charges for runs that
--      already happened, i.e. bill people for free pilot runs. Scoping every mint and the sweep
--      to `runs.ended_at >= payments_live_since` makes the switch a line in time rather than a
--      light switch: what happened before the cutover stays free, forever, by construction.
-- While NULL, today's behavior is preserved byte-for-byte (card-less owners keep getting
-- recurring bookings generated). The debt gate and the honesty copy fixes are deliberately NOT
-- flag-keyed: they derive from per-booking payment state and are true in every era.
--
-- ═══ §0d DEPLOY STEPS THAT ARE SEAN'S — IN THIS ORDER (a migration cannot do them) ═══
-- The ordering is load-bearing, not tidiness: three edge functions in this slice call SQL that
-- exists only after this file applies, and one of them FAILS CLOSED without it.
--   ① `supabase db push` — THIS MIGRATION FIRST. What each pre-0080 function deploy breaks,
--      concretely (read before deciding to "just ship the functions"):
--        · create-booking-hold — the debt gate (`owner_has_unsettled_charge`,
--          create-booking-hold/handler.ts:53) turns an RPC error into a 500 deliberately (a money
--          gate that fails open is not a gate), so EVERY booking creation fails until 0080 lands.
--          This is the hard block, and the reason nothing else in the list may go first.
--        · settle-run — `mint_settle_charge_intent` errors are caught (settle-run/handler.ts:187):
--          settlement still succeeds and the runner is still paid, but every run reports
--          collection 'failed' and no intent is ever recorded.
--        · transition-booking — `mint_cancel_fee_intent` and `record_enroute_cancel_comp` are both
--          caught (cancel_owner.ts:123 / :163), so cancels keep working; the runner's en-route
--          compensation row silently does not exist and only the ops notification says so.
--   ② `supabase functions deploy create-booking-hold` — the hard-blocked one, immediately after
--      the push closes its dependency.
--   ③ `supabase functions deploy collect-charges --no-verify-jwt`. WHY the flag: the cron reaches
--      this function through §K's `net.http_post`, which carries no user JWT, so `X-Cron-Key` IS
--      the credential for that path (collect-charges/handler.ts:35-45 — and an unset
--      CRON_COLLECT_KEY authenticates nobody: 503, never an open batch-charging endpoint). The
--      owner CTA is NOT opened by the flag: that path still validates the caller's JWT through
--      `caller()` (handler.ts:52) and gates on booking ownership before any row is read.
--   ④ `supabase functions deploy settle-run` and `supabase functions deploy transition-booking` —
--      order between these two is free, because both catch every charge-path error.
--   ⑤ app build / submit (Unit D's screens call `my_billing_card()` and `my_unsettled_charge()`,
--      both created in this file — so they too wait on ①, and on nothing else).
--   ⑥ vault secret `charge_dispatch` = `{"url": "https://<ref>.supabase.co/functions/v1",
--      "cron_key": "<same value as the edge env CRON_COLLECT_KEY>"}` AND the edge env
--      `CRON_COLLECT_KEY` on collect-charges. Both or neither: the secret alone posts a key
--      nothing accepts (401 every tick), the env alone leaves §K no-op'ing loudly. Until this
--      step the dispatcher's absent-secret NOTICE is the correct, honest pre-cutover state.
--   ⑦ LAST — and only once 자동결제(빌링) 심사 and the card-register slice have landed:
--        `update ops_flags set payments_live_since = now(), updated_at = now();`
--      Set it to the moment charging starts, never to a past timestamp: everything that ended
--      before it is free by definition, and back-dating it bills people for free runs.
--
-- ═══ §0e DOCTRINE (0059 money-path list) ═══
-- self-contained migration · adversarial cycle · mutation-proven pins · every definer carries
-- `set search_path = public, pg_temp` (98 H1 fails the harness otherwise — ALTER-applied config
-- is reset by `create or replace`) · party gate before state gate · no derived cache columns.
-- Pins: `116_charge_suite.sql` (C1–C25) + `90_race_check.sh` RD/RE (the two concurrency claims:
-- one mint per booking, one compensation row per booking), plus the pins this file must NOT break:
-- 109 P4-P11 (payments shape), 100 W7/W10 (hold expiry + ACL preservation), 20 G1-G9/A4
-- (recurring), 110 S1-S6 (incident settlement).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A billing_keys — the card lives here, and NOTHING may read it
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The 빌링키 is a bearer credential: whoever holds it can charge the card. So this table is
-- SEALED the way 68 V1 means it — RLS on, ZERO policies — and the only client-facing surface
-- is `my_billing_card()` below, which returns the *display* fields and never the key.
-- The card-REGISTER flow (widget `/v1/billing/authorizations/…`) is a separate slice; this
-- table is correct and empty until it lands, and every consumer here treats "no row" as the
-- normal pre-cutover state rather than an error.
create table if not exists billing_keys (
  profile_id uuid primary key references profiles on delete cascade,
  billing_key text not null,
  -- display metadata only (brand / last4 / issuer) — never anything that can move money.
  card jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table billing_keys enable row level security;

comment on table billing_keys is
  '0080 §A: 빌링키 storage. SEALED — RLS on, zero policies; server (service_role) only.
The key is a bearer credential; clients see only my_billing_card() (brand/last4/linked_at)';
comment on column billing_keys.billing_key is
  '0080: Toss billingKey. NEVER exposed to any client surface — not in an RPC return, not in raw';

-- Card state for the owner's own settings screen. Zero rows = no card linked (an honest empty
-- state, not an error). definer because the table is sealed; auth.uid()-scoped so the definer
-- cannot become a lookup oracle for other people's cards.
create or replace function my_billing_card()
returns table (brand text, last4 text, linked_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select bk.card->>'brand', bk.card->>'last4', bk.created_at
  from billing_keys bk
  where bk.profile_id = auth.uid()
$$;
revoke execute on function my_billing_card() from public, anon;
grant execute on function my_billing_card() to authenticated;

comment on function my_billing_card is
  '0080 §A: the owner''s own card, display fields only (brand/last4/linked_at). auth.uid()-scoped;
zero rows = no card. billing_key itself has no place in this return shape and never will';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B payments vocabulary gains 'waived' — a zero-amount, DELIBERATE non-charge
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Invariant #1 (§0-ter #1) is "every SETTLED booking has a payments row". Without a vocabulary
-- member for "we decided not to charge", that invariant would have exceptions — and an
-- invariant with exceptions is a sentence, not an invariant. 'waived' is how a G1 abort
-- (dog_condition/incident) or a ~0-actual runner_personal end still leaves a row saying
-- explicitly: we looked, and the answer was zero.
alter table payments drop constraint if exists payments_status_vocab;
alter table payments add constraint payments_status_vocab
  check (status in ('pending', 'confirmed', 'canceled', 'partial_canceled', 'failed', 'waived'));

-- 0076's stronger invariant, amended: a waived row has no payment_key because no PG call was
-- ever made. confirmed/canceled still must carry the key that proves (and can reverse) capture.
alter table payments drop constraint if exists payments_settled_has_key;
alter table payments add constraint payments_settled_has_key
  check (status in ('pending', 'failed', 'waived') or payment_key is not null);

-- 'waived' means ZERO. Permitting a nonzero waived row would let a real charge hide behind the
-- word — the amount column would say money is owed while the status says nobody will collect
-- it. (Not spelled out in the build contract; added because 'waived' is otherwise only a
-- convention, and conventions are what the next author reasonably breaks.)
alter table payments drop constraint if exists payments_waived_is_zero;
alter table payments add constraint payments_waived_is_zero
  check (status <> 'waived' or (amount = 0 and payment_key is null));

comment on column payments.status is
  '0080: pending(intent) → confirmed | failed | canceled; waived = deliberate zero-amount
non-charge (G1 abort / ~0 runner_personal) that keeps invariant #1 exception-free.
partial_canceled remains vocabulary nobody writes (toss-plan §5-4)';

-- §0-ter #12: the debt derivation (§F) and the retry ladder both scan for failed rows per
-- booking. Partial, matching 0076's predicate-shaped-index idiom — failures are always few.
create index if not exists payments_failed_booking_idx on payments (booking_id) where status = 'failed';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C ops_flags — the cutover switch, one row, sealed
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- A single-row table rather than a settings jsonb: the switch has to be readable from inside a
-- definer function on the hot path (§E/§G/§H) and writable by exactly one human in a SQL editor.
-- `id boolean primary key default true check (id)` is the standard single-row idiom — a second
-- row is a primary-key violation, so "the switch" can never become "one of the switches".
-- A TIMESTAMP, not a boolean — see §0c: NULL means charging is off, and once set it is also the
-- line that keeps pilot-era runs free forever (nothing that ended before it is ever charged).
create table if not exists ops_flags (
  id boolean primary key default true check (id),
  payments_live_since timestamptz,
  updated_at timestamptz not null default now()
);
insert into ops_flags (id) values (true) on conflict (id) do nothing;
alter table ops_flags enable row level security;

comment on table ops_flags is
  '0080 §C: single-row ops switchboard. payments_live_since = THE post-pay cutover moment, NULL
until Sean sets it (see the file header §0c). SEALED — RLS on, zero policies; nothing
client-side reads or writes it. NULL = the mints write nothing and the invariant-#1 sweep does
nothing; once set, only runs that ended AT OR AFTER it are ever charged (no retroactive billing)';
comment on column ops_flags.payments_live_since is
  '0080: NULL = charging off. A moment rather than a boolean so the flip cannot retroactively
charge pilot-era runs, and so no pending intent exists pre-cutover for the stale sweep to turn
into false debt (Unit B report, 2026-08-13)';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D compute_owner_charge — THE basis table, as SQL, once
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0066's lesson, restated: a money rule that lives only in a Deno function is a money rule no
-- pin can protect. The §0-ter basis table therefore lives HERE, and settle-run/collect-charges
-- read it through the mints below rather than reimplementing it.
--
-- Three rules, all of them somebody's decision:
--   ① FROZEN NUMBERS (§0-ter #6) — the charge is built from `bookings.base_fare /
--      distance_fare / addon_fare / km`, never from live PRICING constants. A price revision
--      must not reprice a booking the owner already consented to, and recurring rows carry old
--      snapshots BY DESIGN (0026's "동의한 가격만 청구한다" is the same promise).
--   ② CEILING (§0-ter #4) — basis = min(actual, planned). The ×2+2 validity band bounds runner
--      payout fraud; it was never a bound on the owner's card. The owner can never be charged
--      more than the price they were quoted. The runner is still paid on actual within band —
--      the delta is the platform-absorb doctrine, deliberately.
--   ③ D2 (owner-caused ends charge exactly PLANNED) — an actuals charge on owner_request /
--      owner_forced goes margin-negative against settle-run's 50% guarantee clause AND pays for
--      cutting the run short. Note this is `= planned`, not `min(actual, planned)`: it is the
--      one arm where the owner can be charged for distance that did not happen, and the reason
--      is that they are the one who ended it.
--   ④ runner_personal waives the base (§0-ter #10) — distance component ONLY, no base fare, no
--      addons. A runner-caused end does not bill the owner 7,900 for undelivered service. The
--      platform absorbs the runner's min_fare floor at tiny actuals (rare, bounded, gauge it).
--   ⑤ BELOW THE PG's FLOOR → waive (round-2 R1 P2-2). A computed amount above zero but under
--      ₩100 cannot be charged at all: the PG refuses it, so minting it would produce a permanent
--      decline, three ladder rungs, a debt state and an account lock — over less money than the
--      notification costs to send. The arms above can genuinely land there (runner_personal at a
--      few hundred metres of a cheap route), so this is a real branch, not a defensive one.
-- 🔴 dog_condition / incident → amount 0, rule 'g1_waive'. **This is Sean's open product call
--    (G1, §0-ter #9)** and the implementation must not silently pick something else. What is
--    recorded here is the provisional pilot default he asked for — charge NOTHING pending
--    review (trust-first, bounded pilot cost, the exception UI already exists). When he rules,
--    the change is this one arm plus its pin, and the rule string is how you find both.
-- Unknown end_reason → raise. Fail closed: settle-run whitelists the six enum members first
-- (0001:18), so an unknown value reaching here means a caller was rewritten wrong, and a money
-- function's answer to that is an exception, not a plausible number.
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

  -- 🔴 G1 — Sean's open call (see the header block above). Provisional: charge nothing.
  if p_end_reason in ('dog_condition', 'incident') then
    return query select 0, 0::numeric, 'g1_waive'::text;
    return;
  end if;

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
revoke execute on function compute_owner_charge(uuid, text, numeric) from public, anon, authenticated;
grant execute on function compute_owner_charge(uuid, text, numeric) to service_role;

comment on function compute_owner_charge is
  '0080 §D: THE owner charge basis table (toss-plan §0-ter). Frozen booking numbers only ·
basis = min(actual, planned) · owner_request/owner_forced = exactly planned (D2) ·
runner_personal = distance component only (#10) · dog_condition/incident = 0 / g1_waive
(🔴 Sean''s open G1 call, provisional) · 0 < amount < 100 = 0 / below_pg_minimum (the PG refuses
sub-₩100 charges, so minting one would manufacture debt) · unknown end_reason raises.
Pinned by 115 C1-C4, C23';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E the mints — one row per collectable event, and never a second one
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- X1's rails, ported to the settle moment: the row exists before the money can move, the
-- order_id is ours, the amount is ours, and a crash leaves a `pending` row rather than a
-- charge nobody recorded. Retries are IN-PLACE updates of this one row (order_id is constant and
-- doubles as the Toss orderId, which Toss itself refuses to charge twice), which is why minting
-- must be idempotent at the SQL layer instead of hoping the caller behaves.
--
-- THE LOCK IS THE CONSTRUCTION (round-2 R1 P1-1). "Never a second row" was previously asserted as
-- if the exists-check below produced it; it does not. The check is read-then-insert, and under
-- READ COMMITTED two concurrent callers on one booking (settle-run's immediate attempt racing the
-- §G sweep, or two settle-run invocations) both see no row and both insert — nothing in the schema
-- stops them, because each mint generates its OWN order_id and the unique index therefore never
-- fires. Two rows = two orderIds = two charges Toss will happily accept. So each mint takes a
-- transaction-scoped advisory lock keyed on the booking FIRST: the loser blocks, and by the time
-- it reads, the winner's row is committed and visible. That serialization, not the caller's
-- manners and not the unique index, is what makes the sentence "never a second row" true.
--
-- The exists-check is deliberately asymmetric about widget-era rows:
--   BLOCKS  · status in ('confirmed','waived')        → prepaid, or already decided as zero.
--           · raw.kind is not null and status in ('pending','failed')
--                                                     → a server charge row already exists;
--                                                       retries reuse THAT row, never a new one.
--   IGNORES · widget-era pending/failed/canceled (no raw.kind) → nothing was captured before
--             service; those rows are the §2 flow's own debris and must not silence a real
--             post-service charge.
-- Preference order when several rows qualify: settled/decided rows (confirmed, waived) first,
-- then oldest server intent. A confirmed prepayment outranks a stray intent — the answer the
-- caller needs is "this booking is already paid", not "here is an intent you could retry".
--
-- THE CUTOVER GUARD COMES FIRST (§C, §0c). Zero rows = "not live, nothing to collect", which is
-- the whole of settle-run's flag logic: the edge function needs none, because the switch is a
-- SQL fact and a mint that must not happen simply produces no row to dispatch. The run's own
-- `runs.ended_at` is the comparison point rather than now(), so a flip can never reach backwards
-- into runs that already happened. No runs row yet (settle-run calls us immediately after
-- settle_run_tx wrote one, so this is the crash-order case only) → treat the end as now().
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

  -- Serialize every minter of THIS booking (round-2 R1 P1-1 — see the §E header). Taken after the
  -- cutover guards so a not-live call costs nothing, and before the exists-check because the
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

  -- Raises on an unknown end_reason — the mint fails closed with it (§D).
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
  )
  returning * into v_row;

  return query select v_row.id, v_row.order_id, v_row.amount, v_row.status, true;
end $$;
revoke execute on function mint_settle_charge_intent(uuid, text, numeric) from public, anon, authenticated;
grant execute on function mint_settle_charge_intent(uuid, text, numeric) to service_role;

comment on function mint_settle_charge_intent is
  '0080 §E: idempotent single-truth minting of the settle-time charge intent. Zero rows while
ops_flags.payments_live_since is null or the run ended before it (no pre-cutover intents, no
retroactive billing — §0c). Otherwise returns the existing row with minted=false rather than
ever writing a second one — which holds under CONCURRENCY only because of the per-booking
pg_advisory_xact_lock taken first (the exists-check alone is read-then-insert; each mint makes its
own order_id, so the unique index would never catch the double). amount 0 → a waived row, so
invariant #1 stays exception-free';

-- Cancel fees ride the SAME rails (§0-ter #5): 0066's ladder already computed the money and
-- transition-booking already wrote it to `bookings.cancel_fee`; under post-pay that number is a
-- small CHARGE rather than a deduction from a refund. Fee 0 mints NOTHING (§0-ter #13) — the
-- booking was never settled, so invariant #1 does not apply to it, and a zero row would only
-- teach the debt derivation to look at bookings that owe nothing. Zero rows returned, which the
-- caller reads as "no charge to dispatch".
-- Same cutover guard as the settle mint (§0c): pre-cutover, a cancel keeps today's behavior —
-- `bookings.cancel_fee` is recorded and nothing is collected. The anchor here is the cancel
-- itself (now()), because a cancel has no run to date it by.
create or replace function mint_cancel_fee_intent(p_booking uuid)
returns table (payment_id uuid, order_id text, amount int, status text, minted boolean)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_existing payments%rowtype;
  v_row      payments%rowtype;
  v_fee      int;
  v_order    text;
  v_since    timestamptz;
begin
  select f.payments_live_since into v_since from ops_flags f where f.id;
  if v_since is null then return; end if;              -- charging is off: fee stays recorded-only

  -- Same serialization as the settle mint, same key space (round-2 R1 P1-1): a cancel that races
  -- itself — the client's retry of a timed-out transition, or a cancel racing the settle mint on
  -- the same booking — must not produce two chargeable intents. One lock per booking covers both
  -- mints precisely because they share the 'mint:' prefix.
  perform pg_advisory_xact_lock(hashtextextended('mint:' || p_booking::text, 0));

  select coalesce(b.cancel_fee, 0) into v_fee from bookings b where b.id = p_booking;
  if v_fee is null then raise exception 'not_found'; end if;

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

  if v_fee <= 0 then return; end if;      -- §0-ter #13: nothing to collect, nothing to record

  v_order := 'dr_' || gen_random_uuid()::text;
  insert into payments (booking_id, order_id, amount, status, raw)
  values (p_booking, v_order, v_fee, 'pending',
          jsonb_build_object('kind', 'cancel_fee', 'attempts', 0))
  returning * into v_row;

  return query select v_row.id, v_row.order_id, v_row.amount, v_row.status, true;
end $$;
revoke execute on function mint_cancel_fee_intent(uuid) from public, anon, authenticated;
grant execute on function mint_cancel_fee_intent(uuid) to service_role;

comment on function mint_cancel_fee_intent is
  '0080 §E: the 0066 cancel fee as a charge intent on the same rails (§0-ter #5). Zero rows
pre-cutover (payments_live_since null → the fee stays recorded-only, today''s behavior).
Mirrors the settle mint''s exists-check AND its per-booking advisory lock (both mints share the
''mint:'' key, so they serialize against each other too); fee 0 mints nothing at all (§0-ter #13 — matching
expiry and free-tier cancels charge nothing, and a zero row would be noise for the debt query)';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §F debt is DERIVED — there is no collection_status column and there never will be
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- "Settled" anchors on `runs.ended_at` / `ledger_items` existence, **never** `bookings.status`
-- (§0-ter #11): an incident_review or refund_pending transition after settlement must not drop
-- a failed charge out of the account lock. The second scope arm is cancelled-with-fee
-- (§0-ter #5) — that money is owed for the same reason, without a run ever existing.
-- Two debt shapes:
--   · failed  → the ladder has spoken (or is between rungs); the owner owes us.
--   · pending AND dispatched over an hour ago → we told Toss to charge and never learned the
--     outcome. Treating that as debt is the safe direction: worst case the owner is briefly
--     locked out of NEW bookings while reconciliation (§I) resolves it, and nothing already
--     booked is disturbed.
-- A never-dispatched pending is NOT debt: nothing was asked of the card yet.
-- BOTH shapes are restricted to SERVER-MINTED rows (`raw.kind is not null` — round-2 R1 P1-2).
-- The plan's original predicate carried an extra clause, "and no later confirmed row exists",
-- which was dropped in the build as redundant; it was not. Widget-era debris is the counter-
-- example: a §2 booking whose first intent failed, whose retry then succeeded (confirmed sibling
-- row), and whose run later settled satisfies the scope arm and the `status = 'failed'` arm and
-- would lock an owner who owes nothing, forever, with no CTA that can clear it (collect-charges
-- refuses kind-less rows: collect-charges/handler.ts:75). `kind` restores that clause in the
-- correct form and a stronger one: this derivation only ever speaks about charges THIS machine
-- minted, so the widget flow's own leftovers can neither create debt nor be silenced into it.
create or replace function owner_has_unsettled_charge(p_owner uuid) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from payments p
    join bookings b on b.id = p.booking_id
    where b.owner_id = p_owner
      and (
        exists (select 1 from runs r where r.booking_id = b.id and r.ended_at is not null)
        or exists (select 1 from ledger_items li where li.booking_id = b.id)
        or coalesce(b.cancel_fee, 0) > 0
      )
      and (p.raw->>'kind') is not null      -- server-minted only (round-2 R1 P1-2)
      and (
        p.status = 'failed'
        or (p.status = 'pending'
            and (p.raw->>'dispatched_at') is not null
            and (p.raw->>'dispatched_at')::timestamptz < now() - interval '1 hour')
      )
  )
$$;
revoke execute on function owner_has_unsettled_charge(uuid) from public, anon, authenticated;
grant execute on function owner_has_unsettled_charge(uuid) to service_role;

comment on function owner_has_unsettled_charge is
  '0080 §F: the account lock, DERIVED (repo law — no cached collection state). Settled anchors on
runs.ended_at / ledger_items, never bookings.status (§0-ter #11); cancelled-with-fee is the
second scope arm (#5). failed, or dispatched-pending older than 1h — and only on rows this
machine minted (raw.kind not null), so widget-era debris can never lock an owner. Server-only';

-- The client wrapper. Same truth, auth.uid()-scoped, so the exception banners can ask about
-- themselves without the lock query becoming a probe against other owners.
create or replace function my_unsettled_charge() returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(owner_has_unsettled_charge(auth.uid()), false)
$$;
revoke execute on function my_unsettled_charge() from public, anon;
grant execute on function my_unsettled_charge() to authenticated;

comment on function my_unsettled_charge is
  '0080 §F: my own debt state (auth.uid()) — the exception banners'' read. Zero-arg by contract
(app/scripts/check-rpc-contracts.mjs). Signed-out = false, not an error';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §G invariant #1 sweep — every SETTLED booking has a payments row (§0-ter #1)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Bookings-anchored, because the payments-anchored reconciliation arms structurally CANNOT see
-- this crash class: if the process died between `settle_run_tx` committing and the mint, there
-- is no payments row to be stale. And no client retry ever reaches the charge code —
-- settle-run's own 409 (`이미 정산됐거나`) refuses the second call. So this sweep is the only
-- thing standing between "the runner was paid" and "nobody ever recorded that the owner owes".
-- end_reason/actual_km come from the runs row, which is the same data settle-run had.
-- Per-row exception guard: one poisoned booking must not stop the sweep for everyone else.
-- SCOPE (§0c ⓑ): only runs that ended at or after the cutover moment, and nothing at all while
-- it is NULL. Without that predicate this sweep is precisely the retroactive-billing machine —
-- the morning after the flip it would mint a charge for every free pilot run ever recorded.
-- The mint enforces the same rule itself; the predicate is here so the sweep does not spend the
-- whole batch calling a function that will decline.
create or replace function sweep_settled_without_payments() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  n int := 0;
  v_minted boolean;
  v_since timestamptz;
begin
  select f.payments_live_since into v_since from ops_flags f where f.id;
  if v_since is null then return 0; end if;

  for r in
    select b.id as booking_id, rn.end_reason::text as end_reason, rn.actual_km
    from bookings b
    join runs rn on rn.booking_id = b.id
    where rn.ended_at is not null
      and rn.ended_at >= v_since
      -- "Has a payments row" must mean the SAME thing here as it does in the mint's exists-check
      -- (round-2 R3 P3-9). The old bare `not exists` let any payments row at all blind the sweep,
      -- including the widget flow's kind-less failed/canceled/pending debris — which captures
      -- nothing, blocks nothing in the mint, and would therefore leave a genuinely settled booking
      -- with no charge intent and no sweep willing to look at it. Aligned predicate: a row counts
      -- only if this machine minted it (kind) or if it settles the question (confirmed/waived).
      and not exists (
        select 1 from payments p
        where p.booking_id = b.id
          and ((p.raw->>'kind') is not null or p.status in ('confirmed', 'waived'))
      )
  loop
    -- A finished run with no end_reason cannot be priced honestly, and guessing 'completed'
    -- would charge the owner the full quote on a guess. Leave it for a human (§I is where it
    -- shows up as a settled booking that still has no row).
    if r.end_reason is null then
      raise notice 'sweep_settled_without_payments: booking % has ended_at but no end_reason — skipped', r.booking_id;
      continue;
    end if;
    -- Symmetric refusal for a missing actual_km (round-2 R1 P3). The mint would coalesce NULL to
    -- 0 km and charge the base + addons on an unmeasured run — or, on an owner-caused end, the
    -- whole planned quote — from a number nobody recorded. `actual_km` is not nullable in
    -- practice (settle_run_tx writes it), so a NULL here means something is already wrong, and
    -- the honest output of a money sweep facing a broken row is a NOTICE, not an invoice.
    if r.actual_km is null then
      raise notice 'sweep_settled_without_payments: booking % has ended_at but no actual_km — skipped', r.booking_id;
      continue;
    end if;
    begin
      select m.minted into v_minted
      from mint_settle_charge_intent(r.booking_id, r.end_reason, r.actual_km) m;
      if coalesce(v_minted, false) then n := n + 1; end if;
    exception when others then
      raise notice 'sweep_settled_without_payments: booking % — %', r.booking_id, sqlerrm;
    end;
  end loop;
  return n;
end $$;
revoke execute on function sweep_settled_without_payments() from public, anon, authenticated;
grant execute on function sweep_settled_without_payments() to service_role;

comment on function sweep_settled_without_payments is
  '0080 §G: invariant #1 (§0-ter #1) — settled booking (runs.ended_at) with no payments row gets
one, minted from the runs row''s own end_reason/actual_km (a run missing either is SKIPPED with a
notice — a money sweep does not guess). "Has a row" is the mint''s definition, not any row:
kind-bearing or confirmed/waived, so widget debris cannot blind it. Bookings-anchored on purpose:
the payments-anchored reconciliation arms cannot see a crash that left no row at all. Scoped to
runs that ended at or after ops_flags.payments_live_since (0 while null) — the flip must never
bill a pilot-era run retroactively';

-- Cron. Minute offsets are staggered doctrine (0060:145): taken are */5 (expire-unmatched),
-- 1-56/5 (purge-holds), 3-58/5 (sweep-payment-intents), 7 * * * * (recurring-gen).
-- This one takes 2-57/5; §K takes 4-59/5. Guarded do-block so the migration still applies where
-- pg_cron does not exist — the local harness is exactly that environment.
do $$ begin
  perform cron.schedule('sweep-settled-charges', '2-57/5 * * * *', 'select sweep_settled_without_payments()');
exception when others then
  raise notice 'pg_cron unavailable — call sweep_settled_without_payments() from an external scheduler';
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §H generate_recurring_bookings — the hourly cron learns about money (§0-ter #3)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Why this function and not create-booking-hold: this cron inserts bookings DIRECTLY at
-- matching/runner_pending, bypassing the edge function entirely. Without these two gates the
-- "exposure is bounded at ≤ one fare per owner" claim in §0-bis is simply FALSE — a locked
-- owner would keep receiving generated runs every week, each one an uncollectable fare.
-- 0026:10-11 already said so in words ("실 PG 도입 시 이 크론에 청구 단계 필수"); this is that
-- step arriving.
-- ⚠ WITH THIS GATE THE BOUND HOLDS FOR THE MARKETPLACE AND RECURRING PATHS ONLY (round-2 R1
-- P2-3). One booking-creating path in this repo is NOT covered: `session_pay_delegation`
-- (0037:242-249) inserts a club booking directly — no debt gate, no billing-instrument check, and
-- a hardcoded 9,900 base at 0037:249 rather than the frozen-quote rails this file builds on. A
-- locked owner can therefore still accumulate club runs. That is a real exclusion from the §0-bis
-- sentence, not an oversight of this migration: the club money path is R6 and out of this slice's
-- scope by contract (§J-ⓑ touches one sentence of it and nothing else). It belongs in TODOS as an
-- R6 follow-up (this slice does not own that file); whoever closes it should reuse these two
-- gates verbatim rather than invent a third pair.
--
-- Recreated under 0057 §2 reproduction discipline — the 0026:63-150 body, byte-faithful, with
-- exactly four changes:
--   ⓐ header `search_path = public` → `public, pg_temp` (98 H1 law)
--   ⓑ the debt gate + ⓒ the billing-instrument gate, both immediately BEFORE the insert (not at
--      the top of the loop: a series that is out of window or deduped would otherwise notify an
--      owner about a booking that was never going to be created this hour)
--   ⓓ notify ONCE per owner per sweep (a five-series owner gets one message, not five)
-- ⓒ keys on the cutover switch: while `payments_live_since` is NULL, today's card-less
-- generation is preserved exactly. ⓑ is NOT flag-keyed and does not need to be — a failed
-- charge row can only exist after the cutover anyway, so the gate is dormant by construction
-- rather than by a condition somebody has to remember to remove.
-- Grants: 0026:152 revoked public/anon/authenticated and `create or replace` preserves ACLs;
-- not re-revoked here so that 20 A4 keeps measuring preservation rather than this line
-- (the 0060:101 / 100 W10 doctrine).
create or replace function generate_recurring_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record;
  n int := 0;
  v_dow int; v_time text;
  v_kst_now timestamp;
  v_next_date date;
  v_sched timestamptz;
  v_start timestamptz; v_end timestamptz;
  v_runner uuid; v_avail boolean; v_clash boolean;
  v_bid uuid;
  v_live boolean;              -- [0080] cutover switch, read once per sweep
  v_block text;                -- [0080] null | 'debt' | 'no_card'
  v_notified uuid[] := '{}';   -- [0080] owners already told this sweep (ⓓ)
begin
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;

  for s in select * from recurring_series where not paused and dog_id is not null loop
    v_dow := (s.rule->'weekdays'->>0)::int;
    v_time := s.rule->>'time';
    if v_dow is null or v_time is null then continue; end if;

    -- 다음 발생 시각 (KST) — 오늘 포함, 최소 통보 2h 미달이면 다음 주
    v_kst_now := now() at time zone 'Asia/Seoul';
    v_next_date := v_kst_now::date + ((v_dow - extract(dow from v_kst_now)::int + 7) % 7);
    v_sched := (v_next_date::text || ' ' || v_time)::timestamp at time zone 'Asia/Seoul';
    if v_sched < now() + interval '2 hours' then
      v_sched := v_sched + interval '7 days';
    end if;
    if v_sched > now() + interval '72 hours' then continue; end if;

    -- dedup: 같은 시리즈, 같은 KST 날짜에 이미 예약 존재 (첫 예약 포함 — series_id 링크가 가드)
    if exists (
      select 1 from bookings
      where series_id = s.id
        and (scheduled_at at time zone 'Asia/Seoul')::date = (v_sched at time zone 'Asia/Seoul')::date
    ) then continue; end if;

    v_start := v_sched;
    v_end := v_sched + make_interval(mins => (s.km * 8 + 25)::int); -- 실소요 공식 (hold와 동일)

    -- 같은 강아지 라이브 예약 겹침 가드 (create-booking-hold와 동일 로직의 SQL판)
    select exists (
      select 1 from bookings c
      where c.dog_id = s.dog_id
        and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
        and c.scheduled_at < v_end
        and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
    ) into v_clash;
    if v_clash then continue; end if;

    -- 같은 러너 우선 — 시리즈 최근 확정+ 러너, 가용성 재검증 (감사 ① 교훈: 지명은 검증 후)
    v_runner := null;
    select b2.runner_id into v_runner from bookings b2
    where b2.series_id = s.id and b2.runner_id is not null
      and b2.status in ('confirmed','runner_enroute','picked_up','active','completed')
    order by b2.scheduled_at desc limit 1;
    if v_runner is not null then
      begin
        select is_slot_available(v_runner, v_start, v_end) into v_avail;
      exception when others then
        v_avail := false;
      end;
      if not coalesce(v_avail, false) then v_runner := null; end if;
    end if;

    -- ⓑ/ⓒ [0080 §0-ter #3] money gates — the last thing before the insert.
    v_block := null;
    if owner_has_unsettled_charge(s.owner_id) then
      v_block := 'debt';
    elsif v_live and not exists (select 1 from billing_keys bk where bk.profile_id = s.owner_id) then
      v_block := 'no_card';
    end if;
    if v_block is not null then
      if not (s.owner_id = any(v_notified)) then          -- ⓓ once per owner per sweep
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (s.owner_id, 'booking', '반복 예약 일시 중지',
                '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null);
        v_notified := v_notified || s.owner_id;
      end if;
      continue;
    end if;

    insert into bookings
      (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
       km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values
      (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
       (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
       v_sched, s.km, s.pace_label, s.addons,
       s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
    returning id into v_bid;

    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.owner_id, 'booking', '반복 러닝 예약 생성',
            to_char(v_sched at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
            || ' 러닝이 자동 예약됐어요'
            || case when v_runner is null then ' — 러너를 찾는 중이에요' else '' end,
            v_bid);
    if v_runner is not null then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_runner, 'booking', '지명 러닝 요청',
              '반복 예약 보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', v_bid);
    end if;

    n := n + 1;
  end loop;
  return n;
end $$;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘: 미수금 보호자는 생성 중단(항상), payments_live_since가 설정된
뒤엔 카드 없는 보호자도 중단. 보호자당 스윕 1회만 통지. 그 둘이 없으면 ≤1건 노출 한도가 거짓이 된다';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §I stale intents + reconciliation — dispatched pendings are never auto-failed (§0-ter #2)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0076's sweep predicate (`payment_key is null` = nothing captured) was a WIDGET-flow argument:
-- in that flow, an intent with no key never reached the PG. A server-initiated billing charge
-- breaks that reasoning — we call Toss ourselves and there is no payment_key until the response
-- comes back, so a killed process leaves a keyless pending that may ALREADY HAVE CHARGED THE
-- CARD. Closing it `failed` would erase that from our ledger, which is the exact sin 0076's
-- comment forbids, arriving through a door 0076 could not see.
-- The marker is `raw.dispatched_at`, written by _shared/charge.ts BEFORE the HTTP call. Only
-- never-dispatched pendings may auto-fail; dispatched ones route to reconciliation below.
--
-- AND THE OWNER IS TOLD (round-2 R1 P3). When this sweep flips a KIND-BEARING pending, it is
-- closing a charge that was minted and then never attempted — settle-run's immediate dispatch
-- died, or no billing key existed. §F reads that `failed` row as debt an hour later and
-- create-booking-hold starts refusing new bookings, so silence here means the owner discovers
-- their account is locked by being refused. The copy names exactly what happened (the charge was
-- not attempted — NOT "your card was declined", which would be a different and untrue story) and
-- points at the one screen that can act on it.
-- Kind-less widget debris stays SILENT: nothing was minted, nothing is owed, and the §2 flow's own
-- abandoned intents are not news anybody can act on (100 W7's e_hold silence, same argument).
create or replace function sweep_stale_payment_intents() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare n int;
begin
  with s as (
    update payments set status = 'failed', updated_at = now()
    where status = 'pending'
      and payment_key is null
      and (raw->>'dispatched_at') is null          -- [0080 §0-ter #2]
      and created_at < now() - interval '1 hour'
    returning id, booking_id, raw
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select b.owner_id, 'booking', '결제 처리 안내',
           '지난 러닝 이용료 결제를 시도하지 못했어요 — 설정 > 결제 관리에서 확인해주세요', b.id
    from s join bookings b on b.id = s.booking_id
    where (s.raw->>'kind') is not null            -- [0080] server-minted rows only
  )
  select count(*)::int from s into n;
  return n;
end $$;

comment on function sweep_stale_payment_intents is
  '0080 §I (was 0076 §C): 좌초 인텐트 스윕 (매시 3-58/5분). payment_key가 있는 pending은 그대로,
그리고 [0080] dispatched_at이 찍힌 pending도 그대로 — 토스에 이미 요청한 행을 failed로 닫는 것은
돈이 나갔을 수 있다는 사실을 장부에서 지우는 것이다. 그 행들은 payments_reconciliation()으로 간다.
[0080] kind 있는 행(서버 민팅)을 닫을 때는 보호자에게 "결제 처리 안내"를 보낸다 — 한 시간 뒤
§F가 그 행을 미수금으로 읽고 새 예약이 잠기기 때문이다. kind 없는 위젯 잔해는 침묵';

-- Reconciliation gains two more arms. The four kinds are kept DISJOINT (`stale_pending` now
-- excludes dispatched rows; the two failed/pending/confirmed arms cannot overlap by status): an
-- operator query that lists the same row twice under two names is a query people stop reading.
-- Note the practical effect of the amendment above — with never-dispatched pendings auto-failing,
-- `stale_pending` in production means "pending with a payment_key", i.e. the widget capture-crash
-- class 0076 named, unchanged.
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
$$;

comment on function payments_reconciliation is
  '0080 §I (was 0076 §D): 결제 조정 질의 4종 — orphan_capture(돈은 받았는데 부킹이 못 감) ·
stale_pending(1시간+ 미발송 인텐트, 실전에선 payment_key 있는 캡처 크래시) ·
stale_dispatched(토스에 보냈는데 결과를 모르는 행 — orderId로 조회해 사람이 닫는다) ·
[0080] ladder_exhausted(3회 실패로 래더가 끝난 행 — 자동 재시도는 더 없고 사람/보호자 CTA만
남았다). 상태로 서로소';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §J honesty copy — two shipped sentences that become lies the moment charges are real
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §0-ter #13 rewrote §5-4's go-live gate around exactly this: under post-pay, matching expiry
-- and most cancels take no money, so "전액 환불 처리돼요" and "N원이 환불돼요" promise refunds of
-- money that was never taken. They are correct TODAY (widget prepay) and false TOMORROW, which
-- is why the fix is conditional on per-booking payment state rather than on the cutover flag:
-- a widget-prepaid booking keeps its refund promise forever, and a post-pay booking never gets
-- one. Both functions are recreated here rather than edited in place (shipped files are
-- immutable — 0057 §2).

-- ---------- ⓐ 0060's expire_unmatched_bookings ----------
-- THE TWO SIBLING CTE STRUCTURE IS A DECLARED CONTRACT (0060:95-98), reproduced verbatim:
-- RETURNING gives only NEW values in PG16, so merging the two UPDATEs makes the classes
-- indistinguishable and the noti CTE would send a refund sentence to payment_hold owners too.
-- e_hold stays deliberately SILENT (100 W7 pins that silence). The ONLY change is the body
-- sentence of the e_match notification becoming conditional. Title stays '매칭 만료' (W7 counts
-- by title), return value stays e_match + e_hold, ACLs are preserved by create-or-replace
-- (0057 §3's revokes; 100 W10 measures that preservation, so nothing is re-revoked here).
create or replace function expire_unmatched_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  with e_match as (
    -- [0017/0037 원본 불변] 시작 시간이 지나도록 러너를 못 찾은 예약
    update bookings set status = 'expired'
    where status in ('matching', 'runner_pending') and scheduled_at < now()
      and club_session_id is null
    returning id, owner_id
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select e.owner_id, 'booking', '매칭 만료',
           -- [0080] 위젯 선결제가 실제로 잡혀 있었던 예약만 환불을 약속한다. 후불 예약은
           -- 청구된 적이 없으므로 환불도 없다 — 그 사실을 그대로 말하는 것이 유일한 정직한 문장.
           case when exists (select 1 from payments p
                             where p.booking_id = e.id and p.status = 'confirmed')
                then '시작 시간까지 러너를 찾지 못했어요 — 전액 환불 처리돼요'
                else '시작 시간까지 러너를 찾지 못했어요 — 결제된 금액이 없어 청구되지 않아요' end,
           e.id
    from e_match e
  ), e_hold as (
    -- [0060] 결제 화면 이탈로 30분 넘게 방치된 홀드 — **알림 없음**(청구된 적이 없다)
    update bookings set status = 'expired'
    where status = 'payment_hold' and created_at < now() - interval '30 minutes'
      and club_session_id is null
    returning id
  )
  select (select count(*) from e_match) + (select count(*) from e_hold) into n;
  return n;
end $$;

comment on function expire_unmatched_bookings is
  '0080 §J (was 0060 §3): 두 형제 CTE 계약 그대로(병합 금지 — e_hold는 의도적 침묵, 100 W7).
[0080] e_match 알림 본문만 조건부: confirmed 결제가 있는 예약만 환불 약속, 후불 예약은
"결제된 금액이 없어 청구되지 않아요"';

-- ---------- ⓑ 0072's club_incident_settle step ⑥ ----------
-- COPY FIX ONLY. The club money path is R6 out-of-scope for this slice: the quote, the ledger
-- write, the fee item, the axes, the state moves are all reproduced byte-faithful from
-- 0072:102-207. The single change is the owner notification body, and only in the refund>0
-- branch, and only when no captured payment exists. The runner sentence ("정산에 반영됐어요")
-- is untouched — the ledger write is real either way, which is precisely §0-bis's point that
-- the runner is paid regardless of collection.
-- 🔴 The post-pay branch says "청구되지 않아요" (provisional, G1-adjacent): under post-pay the
--    honest thing to tell an owner whose case was decided in their favour is that no money is
--    being taken. If Sean's G1 ruling changes what an incident charges, this sentence moves
--    with it.
create or replace function club_incident_settle(
  p_incident uuid, p_booking uuid, p_outcome text, p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  i record; s record; q record; sd record; b record; v_sess uuid;
  v_prepaid boolean;   -- [0080] 이 부킹에 실제로 잡힌 돈이 있었나
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_outcome not in ('refund_full','settle_measured','pay_full') then raise exception 'bad_outcome'; end if;

  select * into i from club_incidents where id = p_incident;
  -- 당사자 게이트 선행 — 없는 케이스와 남의 케이스는 같은 답 (0067 §C의 법, 같은 파일군에서 유지)
  if i.id is null then raise exception 'not_case_owner'; end if;
  select * into s from club_sessions where id = i.session_id for update;
  -- [0058 F1의 NULL-안전 형태] exists 형태는 NULL을 '행 없음'으로 처리하므로 안전하다
  -- (백업 호스트가 NULL일 때 `uid in (host, null)`이 무관자에게 NULL로 접히는 fail-open 방지).
  if not ((i.case_owner is not null and auth.uid() = i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                       and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))) then
    raise exception 'not_case_owner';
  end if;
  if i.state = 'resolved' then raise exception 'case_closed'; end if;

  -- 주체 검증: 이 부킹이 **이 케이스의** 대상이어야 한다 (0067 §B와 같은 규율 — 임의 부킹 금지)
  if not exists (select 1 from club_incident_subjects sub
                 where sub.incident_id = p_incident
                   and sub.subject_type = 'booking' and sub.subject_id = p_booking) then
    raise exception 'not_case_subject';
  end if;

  select * into b from bookings where id = p_booking for update;
  -- 멱등 검사가 **상태 검사보다 먼저**다 (110 S3).
  if exists (select 1 from club_fee_items f
             where f.booking_id = p_booking and f.kind = 'incident_settlement') then
    raise exception 'already_settled';
  end if;
  if b.status::text <> 'incident_review' then raise exception 'not_in_review'; end if;

  select * into q from club_incident_settle_quote(p_booking, p_outcome);
  select * into sd from session_dogs where booking_id = p_booking;
  v_sess := coalesce(sd.session_id, i.session_id);

  -- ① 러너 몫 — ledger_items가 러너의 실제 수입 원장이다 (settle_run_tx가 쓰는 바로 그 테이블).
  if q.runner_gross > 0 and b.runner_id is not null then
    insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                              tip, remaining_guarantee, platform_fee)
    values (b.runner_id, p_booking,
            case when q.took_custody then coalesce(b.base_fare, 0) else 0 end,
            greatest(0, q.runner_gross - (case when q.took_custody then coalesce(b.base_fare, 0) else 0 end)),
            0, 0, 0, q.runner_fee);
  end if;

  -- ② 근거 기록 — 금액에는 언제나 근거가 붙는다 (club_fee_items의 '근거 없는 금액 금지')
  insert into club_fee_items (session_id, session_dog_id, booking_id, kind, amount_krw,
                              recipient_type, recipient_profile_id, basis)
  values (v_sess, sd.id, p_booking, 'incident_settlement', q.runner_fee, 'platform', null,
          jsonb_build_object('outcome', p_outcome, 'rule', q.basis,
                             'refund', q.refund, 'runnerGross', q.runner_gross,
                             'runnerNet', q.runner_net, 'measuredKm', q.measured_km,
                             'tookCustody', q.took_custody,
                             'decidedBy', auth.uid(), 'at', now()));

  -- ③ 케이스 증빙 — 이 결정은 분쟁의 원천이므로 케이스 안에 남는다
  insert into club_incident_evidence (incident_id, kind, payload, created_by)
  values (p_incident, 'document', jsonb_build_object(
    'settlement', p_outcome, 'refund', q.refund, 'runnerGross', q.runner_gross,
    'runnerNet', q.runner_net, 'rule', q.basis, 'note', p_note, 'at', now()), auth.uid());

  -- ④ 부킹 먼저 — 환불이 있으면 refund_pending (0066:56). 없으면 incident_review에 남는다.
  if q.refund > 0 then
    update bookings set status = 'refund_pending', cancel_reason = 'incident_settlement'
    where id = p_booking;
  end if;

  -- ⑤ 지급 축 — **부킹 다음**. refund_state는 파생이라 axes 트리거의 몫(110 S4), payout_state만 쓴다.
  if sd.id is not null then
    update session_dogs set
      payout_state = case when q.runner_gross > 0 then 'payable' else 'void' end
    where id = sd.id;
  end if;

  -- ⑥ 양측에 알린다 — 돈이 움직였다는 사실은 통보 대상이다
  -- [0080 §0-ter #13] 환불 문장은 **실제로 잡힌 돈이 있을 때만**. 후불 예약에는 환불할 돈이
  -- 애초에 없으므로 "환불돼요"는 배포된 거짓말이 된다.
  select exists (select 1 from payments p where p.booking_id = p_booking and p.status = 'confirmed')
    into v_prepaid;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (b.owner_id, 'booking', '케이스 정산 결정',
    case when q.refund > 0 then
           case when v_prepaid
                then q.refund || '원이 환불돼요 — 케이스에서 근거를 볼 수 있어요'
                else '이번 건은 청구되지 않아요 — 케이스에서 근거를 볼 수 있어요' end
         else '이번 건은 환불 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  if b.runner_id is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (b.runner_id, 'booking', '케이스 정산 결정',
      case when q.runner_net > 0 then q.runner_net || '원이 정산에 반영됐어요 (수수료 차감 후)'
           else '이번 건은 정산 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  end if;

  return jsonb_build_object('refund', q.refund, 'runnerGross', q.runner_gross,
                            'runnerNet', q.runner_net, 'rule', q.basis);
end $$;
-- 0072:208-209's ACL restated (positive grant — the host surface stops working without it;
-- create-or-replace preserves it, so this is belt, not a change).
revoke execute on function club_incident_settle(uuid, uuid, text, text) from public, anon;
grant execute on function club_incident_settle(uuid, uuid, text, text) to authenticated;

comment on function club_incident_settle is
  '0080 §J (was 0072 §B): 케이스 정산 — 로직 전부 0072 그대로(R6 범위 밖). [0080] 보호자 알림의
환불 문장만 조건부: confirmed 결제가 있으면 "N원이 환불돼요", 없으면 "이번 건은 청구되지 않아요".
러너 문장(정산에 반영)은 불변 — 원장 기록은 어느 쪽이든 진짜다';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §K en-route cancel compensation + the retry dispatcher
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ---------- ⓐ record_enroute_cancel_comp (§0-ter #5) ----------
-- `settle_run_tx` NEVER runs for a cancelled_owner booking, so the 50% en-route fee — which
-- Sean defined on 2026-08-11 as RUNNER COMPENSATION, not platform revenue — currently reaches
-- the runner's earnings through no path at all. The fee is charged to the owner through
-- mint_cancel_fee_intent (§E); this is the other half: the runner's ledger row.
--
-- SHAPE DECISION (the build contract left this open): the whole fee goes in
-- `remaining_guarantee`, with platform_fee 0 and every service column at 0.
--   · platform_fee 0 — the platform takes NOTHING from a compensation payment. Commission is
--     for delivered service; nothing was delivered.
--   · remaining_guarantee, not base/distance/addon — those three mean "we performed this part
--     of the service" and would lie in every earnings breakdown that reads them (and would
--     make an aborted departure look like a completed run's base fare). 0001:272 defines this
--     column as "보호자 요청 종료 시 잔여 50%" — an owner-caused stop paying the runner a
--     compensation percentage, which is exactly this event, one state earlier. `my_ledger_total`
--     sums it identically, so the runner's money is the same either way; only the story differs.
-- Idempotent on the existence of ANY ledger row for the booking, and a booking that somehow
-- reached settlement is never touched. That idempotence is worth exactly as much as its
-- serialization: `ledger_items` has no unique key on booking_id (0001:264-275), so two concurrent
-- callers — the client's retry of a timed-out cancel is the realistic one — would both read "no
-- ledger row" and both insert, paying the runner the fee twice out of the platform's pocket. The
-- per-booking advisory lock below (round-2 R1 P1-1, same pattern as the mints, own 'comp:' key
-- space because this races itself and not them) is what makes "cannot double-pay" true.
-- Pinned by 90_race_check.sh RE.
create or replace function record_enroute_cancel_comp(p_booking uuid)
returns table (comp int, written boolean)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare b record;
begin
  select bk.runner_id, bk.status::text as status, bk.cancel_reason, coalesce(bk.cancel_fee, 0) as fee
    into b
  from bookings bk where bk.id = p_booking;
  if not found then raise exception 'not_found'; end if;

  -- Serialize compensation writers for THIS booking, before the existence check that decides
  -- whether to write (round-2 R1 P1-1). Transaction-scoped; released on commit or abort.
  perform pg_advisory_xact_lock(hashtextextended('comp:' || p_booking::text, 0));

  -- Tier gate: only the en-route class, marked by transition-booking writing this
  -- cancel_reason (0066's "no new column" design — the tier IS the reason string).
  if b.status <> 'cancelled_owner' or b.cancel_reason is distinct from 'owner_cancel_enroute'
     or b.runner_id is null or b.fee <= 0 then
    return query select 0, false;
    return;
  end if;

  if exists (select 1 from ledger_items li where li.booking_id = p_booking) then
    return query select b.fee, false;                 -- idempotent: already compensated
    return;
  end if;

  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                            tip, remaining_guarantee, platform_fee)
  values (b.runner_id, p_booking, 0, 0, 0, 0, b.fee, 0);

  return query select b.fee, true;
end $$;
revoke execute on function record_enroute_cancel_comp(uuid) from public, anon, authenticated;
grant execute on function record_enroute_cancel_comp(uuid) to service_role;

comment on function record_enroute_cancel_comp is
  '0080 §K: en-route owner-cancel runner compensation (§0-ter #5). settle_run_tx never runs for
cancelled_owner, so this is the only ledger path for 0066''s 50% fee — the whole fee to the
runner (remaining_guarantee), platform_fee 0, idempotent per booking under a per-booking
pg_advisory_xact_lock (ledger_items has no unique key to fall back on). Server-only';

-- ---------- ⓑ dispatch_due_charges — the retry ladder actually turning ----------
-- The ladder (0 / +1h / +24h) is executed by `collect-charges`; something has to WAKE it, and
-- pg_cron cannot make an authenticated HTTP call on its own. This function is that bridge:
-- vault → URL + shared cron key → pg_net POST (0024's idiom). Everything is exception-guarded,
-- for two reasons at once: the local harness has no vault (and stubs pg_net), and in production
-- a dispatcher that raises would leave a cron job flapping instead of retrying next tick.
-- Pre-cutover (no secret set) it counts the due rows and says so in a NOTICE — visible, inert,
-- and honest about what it did not do.
create or replace function dispatch_due_charges() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_due int;
  v_secret text;
  v_cfg jsonb;
  v_url text;
  v_key text;
begin
  -- ⚠ THIS PREDICATE AND `isDue()` IN supabase/functions/collect-charges/handler.ts:107 ARE ONE
  -- RULE WRITTEN TWICE (round-2 R2 P1-3 / R3 P2-4). This side decides whether to WAKE the batch;
  -- that side decides which rows the batch touches. They must change together — a SQL predicate
  -- narrower than the TS one leaves rows nobody ever wakes for, and a wider one posts every five
  -- minutes forever for work the function then declines to do.
  -- Due = a SERVER-MINTED row (kind) with a real amount, and one of:
  --   ⓐ a failed row with rungs left (attempts < 3), whose next rung has arrived, and whose card
  --      is not known-dead. `needs_card_relink` is the 카드 재연결 class: retrying a dead billing
  --      key on a timer produces three identical declines and three identical notifications, so
  --      that row waits for the owner to relink, not for the clock.
  --   ⓑ a server intent minted but never dispatched (settle-run's immediate attempt did not
  --      happen or died before writing dispatched_at).
  --   ⓒ a DISPATCHED pending older than 15 minutes — the row this file's §I sweep deliberately
  --      refuses to auto-fail. Waking for it is not a re-charge: it wakes collect-charges'
  --      verification arm, which asks Toss for the orderId's real outcome. Without ⓒ those rows
  --      sit until §F silently locks the owner an hour later on an outcome nobody ever looked up.
  select count(*)::int into v_due
  from payments p
  where (p.raw->>'kind') is not null
    -- amount > 0 sits HERE, before the status split, because that is where isDue() has it
    -- (handler.ts:110): a zero-amount kind row is a waive that never became one, and waking the
    -- batch for it would post every five minutes to find nothing to do.
    and p.amount > 0
    and (
      (p.status = 'failed'
        and coalesce((p.raw->>'attempts')::int, 0) < 3
        and coalesce((p.raw->>'needs_card_relink')::boolean, false) = false
        and coalesce((p.raw->>'next_retry_at')::timestamptz, '-infinity'::timestamptz) <= now())
      or (p.status = 'pending' and (p.raw->>'dispatched_at') is null)
      or (p.status = 'pending'
          and (p.raw->>'dispatched_at')::timestamptz <= now() - interval '15 minutes')
    );
  if v_due = 0 then return 0; end if;

  begin
    select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'charge_dispatch';
  exception when others then
    raise notice 'dispatch_due_charges: vault unavailable (%) — % due row(s) left for the next tick', sqlerrm, v_due;
    return 0;
  end;
  if v_secret is null then
    raise notice 'dispatch_due_charges: vault secret charge_dispatch absent — % due row(s) left for the next tick', v_due;
    return 0;
  end if;

  v_cfg := v_secret::jsonb;
  v_url := v_cfg->>'url';
  v_key := v_cfg->>'cron_key';
  if v_url is null or v_key is null then
    raise notice 'dispatch_due_charges: charge_dispatch secret needs {"url":…,"cron_key":…}';
    return 0;
  end if;

  perform net.http_post(
    url := v_url || '/collect-charges',
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Key', v_key),
    body := jsonb_build_object('mode', 'batch')
  );
  return v_due;
exception when others then
  -- A dispatcher must never be the reason a cron job dies. The rows stay due.
  raise notice 'dispatch_due_charges: %', sqlerrm;
  return 0;
end $$;
revoke execute on function dispatch_due_charges() from public, anon, authenticated;
grant execute on function dispatch_due_charges() to service_role;

comment on function dispatch_due_charges is
  '0080 §K: wakes collect-charges for due rows — failed with next_retry_at reached, attempts<3 and
no needs_card_relink · never-dispatched server intents · dispatched pendings older than 15분
(그 행은 재청구가 아니라 검증 대상이다). 이 술어는 collect-charges/handler.ts:107 isDue()와
**같은 규칙의 두 번째 사본**이므로 함께 바꿔야 한다. Reads the vault secret charge_dispatch
{"url","cron_key"}; absent vault/secret = a NOTICE and 0, which is the correct pre-cutover
state. Fully exception-guarded — the ladder retries next tick, the cron job never dies';

do $$ begin
  perform cron.schedule('dispatch-due-charges', '4-59/5 * * * *', 'select dispatch_due_charges()');
exception when others then
  raise notice 'pg_cron unavailable — call dispatch_due_charges() from an external scheduler';
end $$;
