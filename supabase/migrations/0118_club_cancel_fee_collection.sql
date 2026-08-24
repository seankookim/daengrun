-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0118 — club cancellation/no-show fees become collectable without crossing the pilot cutover
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean's ruled policy (2026-08-21, verbatim): "Use the club rules as written".
-- `club_config` remains the single source: free ≥24h · 10% late · 20% post-acceptance ·
-- 20% no-show · 50% platform / 50% runner supply compensation.
--
-- ═══ WHOSE OBJECTS THIS FILE RE-CREATES (REGISTRY.md silent-collision law) ═══════════════════
-- This file EXTENDS five existing objects. Each names its base version:
--   §B `mint_cancel_fee_intent`       ← 0080 §E
--   §C `_club_refund_confirmed`       ← 0038:211-227
--   §D `session_cancel_delegation`    ← 0057:190-258 (the latest of 0048/0050/0057)
--   §E `club_finish_session`          ← 0048 §J (the latest definition)
--   §G `payments_reconciliation`      ← 0084 §C (five arms; this adds the sixth)
-- It also REPLACES `_club_record_cancel_fee` ←0048 §B under the same signature, but narrows it
-- to cancellation only. No-show gets its own named function, `_club_record_no_show_fee`.
-- 0117's late-booking truth explicitly excludes club_session_id rows; this file preserves that
-- boundary and does not recreate any 0117 object.
--
-- NEW objects:
--   columns `bookings.club_fee_event_at`, `bookings.club_fee_cutover_at`,
--     `bookings.club_fee_kind`
--   table `club_fee_mint_failures`
--   functions `club_cfg_required`, `_club_config_ruled_row_guard`,
--     `_club_fee_event_collectable`, `_cancel_fee_existing_payment`,
--     `_club_fee_event_clock`, `_club_note_fee_mint_failure`,
--     `_club_try_mint_cancel_fee`, `_club_record_fee`, `_club_record_no_show_fee`,
--     `sweep_club_cancel_fee_intents`, `club_fee_mint_reconciliation`
--   constraint `club_config_ruled_value_present` + triggers `_club_config_ruled_rows`,
--     `_club_config_no_truncate` on `club_config`
--
-- ═══ TWO RULINGS APPLIED IN PLACE, 2026-08-24, BEFORE THIS FILE EVER LANDED ══════════════════
-- 0118 was still unlanded (production ledger head 0116) when Sean ruled on two defects three
-- reviewers found in it. Both are fixed in this file rather than in a follow-up migration,
-- because a defect that never reached a database does not need a correction migration — it needs
-- the file to stop being wrong.
--   R1C  the no-show fee arm in §E now requires that the session has STARTED and that the booking
--        carries NO attendance evidence of either producible kind. Before: a host closing
--        tomorrow's session billed every owner 20%, and an owner who handed the dog over was
--        billed while the runner who walked away was credited the supply half. The gates sit in
--        the fee's WHERE — the session still finishes and still refunds when they fail.
--        Suite 153 P4/P9/P10/P12 own this.
--        ⚠ CORRECTED 2026-08-24, after measurement, before landing: the first draft of the
--        attendance gate read only `session_dogs.checked_in_at`, which a DELEGATION-ONLY owner
--        can never write — `session_checkin` raises `not_joined` without a `session_people` row
--        and `session_delegate_dog` deliberately creates none. That draft was INERT for exactly
--        the population the ruling was about. The gate now also honours
--        `bookings.owner_confirmed_handoff_at`, the one signal that owner can produce.
--        🔴 One residual is left OPEN and named at the gate: `owner_confirmed_handoff_at` is
--        erased by six reassignment paths, so an owner who confirmed handoff and then had the
--        dog reassigned is charged. See the §E comment — it needs a product decision, not a
--        wider WHERE clause.
--        The §H apply-time block is deliberately NOT extended to assert these clauses: an
--        assertion there aborts the MIGRATION, so a mutation that deletes a gate would kill the
--        harness instead of turning P9, P10 or P12 red, and the pins would stop being
--        individually attributable. The suite owns the gates; §H keeps owning the ruled constants.
--        NO GRACE INTERVAL — Sean RULED that on 2026-08-24: ship strict. Recorded at the gate.
--   R2A  `club_cfg_required` (§A) replaces the five `coalesce(club_cfg(k), <ruled number>)` reads
--        that would keep charging the old rate after the config row went NULL. Suite 153 P11
--        owns this. The §H apply-time assertion below is NOT one of those sites and is left
--        alone: it asserts config still EQUALS the ruled values, which is the opposite of
--        reading a number out of code.
--        ⚠ SECOND HALF, added 2026-08-24: R2A and R1C conflicted as first written. The raise has
--        no handler inside `club_finish_session`, so an emptied ladder key rolled the WHOLE
--        transaction back — the session never reached 'done' and neither refund helper ever
--        committed, stranding every owner in it. Resolved by making the bad state UNREACHABLE
--        (a CHECK + a row trigger on `club_config`, §A) rather than by catching the exception:
--        a handler that swallows `missing_club_config:<name>` and finishes anyway is the silent
--        fallback R2A just deleted, wearing a different hat. The loud failure now lands on the
--        ops UPDATE/DELETE that would break policy, naming the key, instead of on an owner
--        waiting for a refund.
--
-- Every created/replaced function carries `set search_path = public, pg_temp` IN ITS BODY.
-- `create or replace` wipes ALTER-applied proconfig; suite 98 H1 owns that invariant.
--
-- The runner-ledger write cites Sean's separate ruling where it happens (§C):
-- "Join the pool — accrue it". It deliberately joins `my_ledger_total` even though `payouts`
-- still has no writer, so the payout gap remains one tracked problem rather than two rules.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  Persist the event, seal it from clients, and persist mint failures
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Lift the four stored [Sean 미확정] marks. No number is copied into application code; the
-- recorders below read the config exactly as 0048 did, except that after R2A they go through
-- `club_cfg_required` so an emptied row refuses instead of resurrecting the constant that used
-- to sit in the `coalesce`. No-show is the fifth ruled value and deliberately reads the current
-- post-acceptance value through its OWN policy wrapper.
update club_config set note = case name
  when 'cancel_free_hours'      then 'Sean 2026-08-21 ruled: owner cancellation is free at least 24 hours before the session'
  when 'cancel_late_pct'        then 'Sean 2026-08-21 ruled: late owner cancellation fee percentage'
  when 'cancel_post_accept_pct' then 'Sean 2026-08-21 ruled: post-acceptance cancellation percentage; no-show reads this value through its own named policy'
  when 'fee_platform_split_pct' then 'Sean 2026-08-21 ruled: fee split to platform; the remainder is runner supply compensation'
  else note end
where name in ('cancel_free_hours', 'cancel_late_pct', 'cancel_post_accept_pct',
               'fee_platform_split_pct');

-- ── R2A (Sean 2026-08-24): club_config is the SINGLE source, and it must fail LOUD ──────────
-- `club_config.value_num` is NULLABLE and `club_cfg` (0048:24-26) is a bare `select value_num`,
-- so every `coalesce(club_cfg('cancel_late_pct'), 10)` below was a SECOND copy of a ruled number
-- that quietly took over the moment the row went NULL. That is not a fallback, it is a policy
-- fork: deleting the late-cancel rate did NOT stop charging late-cancel owners — they kept
-- paying 10% while the config said "no policy". A missing ruled number is not the old number.
-- This wrapper makes the read refuse, and the refusal NAMES the key so the operator who emptied
-- it can put it back.
--
-- It reads THROUGH `club_cfg` rather than re-querying `club_config`: one accessor, one place the
-- table/column name appears. The raise is why this is plpgsql and not `language sql` like its
-- base — a bare SQL function cannot refuse.
--
-- SCOPE — this does NOT replace `club_cfg` everywhere. A `coalesce(club_cfg(k), 0)` whose zero
-- means "record nothing" (see `host_fee_krw` in §E) already fails CLOSED and must keep working.
-- Only reads where the fallback constant would CHARGE somebody move to this wrapper.
--
-- security definer + in-body `set search_path = public, pg_temp`: `club_config` has RLS with no
-- policies, so a non-definer read returns nothing; and ALTER-applied proconfig is wiped by
-- `create or replace`, so 98 H1 requires the header form. Suite 153 P8 pins this signature.
create or replace function club_cfg_required(p_name text) returns numeric
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v numeric;
begin
  v := club_cfg(p_name);
  if v is null then
    raise exception 'missing_club_config:%', p_name;
  end if;
  return v;
end $$;
revoke execute on function club_cfg_required(text) from public, anon, authenticated;
comment on function club_cfg_required is
  '0118 R2A: club_config read that RAISES missing_club_config:<name> instead of silently falling
back to a ruled number copied into code. Use for every value whose absence would otherwise charge
somebody the old rate. Reads whose fallback is a fail-CLOSED zero keep using club_cfg';

-- ── R2A second half (2026-08-24): make the refusal UNREACHABLE, do NOT catch it ─────────────
-- The wrapper above and ruling R1C conflicted as first written, and the conflict was not
-- theoretical: `club_cfg_required` raises INSIDE `club_finish_session` (§E) with no handler, so
-- a single NULLed ladder key rolled the ENTIRE transaction back. The session never reached
-- 'done'; `_club_refund_bookings` and `_club_refund_confirmed` never committed. Every owner in
-- that session sat waiting for a refund because an operator emptied a percentage. R1C's whole
-- shape — the fee gates live in a WHERE so the session still finishes and still refunds when no
-- fee is due — was defeated by a raise two sections away.
--
-- CATCHING IT IS THE WRONG FIX, and it is worth writing down why so nobody re-adds the handler:
-- an `exception when others then <finish anyway>` around the fee arm swallows
-- `missing_club_config:<name>` and continues with no fee. That is a silent fallback to "charge
-- nothing" — the same class of invisible policy fork R2A just removed, only in the other
-- direction. The failure would be as unobservable as the coalesce was.
--
-- So the bad state is made UNREACHABLE instead. The loud failure moves to the ops write that
-- would have broken policy, at the moment it is attempted, naming the key — instead of onto an
-- owner waiting for money hours later. After this, no reachable value of `club_config` can make
-- a ladder read raise, so the un-handled raise in §E has nothing left to fire on.
--
-- TWO DOORS, because `club_cfg_required` refuses on BOTH a NULL value and an ABSENT row:
--   1. CHECK `club_config_ruled_value_present` — a ruled name may not hold a NULL `value_num`.
--   2. TRIGGER `_club_config_ruled_rows` — a ruled row may not be DELETEd, and may not be
--      RENAMED out of the ruled set. A rename is a delete as far as `club_cfg('cancel_late_pct')`
--      is concerned, so both are the same door and both are shut.
--   (+ a statement trigger for TRUNCATE, which bypasses row triggers entirely.)
-- INSERT needs no door of its own: the CHECK already rejects a NULL insert, and `name` is the
-- primary key, so a ruled row cannot be duplicated or shadowed. Delete, rename, truncate and
-- NULL-update are the complete set of ways to reach the state that raises.
--
-- SCOPE — only the four names Sean ruled. `vet_limit_krw`, `host_fee_krw`, `min_paid_dogs` and
-- the rest stay freely editable AND deletable; this is not a freeze on `club_config`. Suite 153
-- P11 owns both halves: the four keys refuse to be emptied, a non-ruled key still can be.
--
-- ⚠ Existing rows are verified BEFORE the constraint is added, and the verification names the
-- offending key. Without it the migration would abort on a bare constraint violation that says
-- only "check constraint violated" — true, useless. §H asserts the same four values equal
-- 24/10/20/50 at the END of this file; this block runs first precisely so the operator gets the
-- key name rather than a constraint name.
do $$
declare v_bad text;
begin
  select string_agg(k.n, ', ' order by k.n) into v_bad
  from unnest(array['cancel_free_hours', 'cancel_late_pct',
                    'cancel_post_accept_pct', 'fee_platform_split_pct']) as k(n)
  where not exists (select 1 from club_config cc where cc.name = k.n and cc.value_num is not null);
  if v_bad is not null then
    raise exception '0118 R2A: cannot seal the ruled club_config ladder — missing or NULL: %', v_bad
      using hint = 'restore the ruled value for each named key (24 / 10 / 20 / 50), then re-apply';
  end if;
end $$;

alter table club_config drop constraint if exists club_config_ruled_value_present;
alter table club_config add constraint club_config_ruled_value_present check (
  -- NULL-collapse-proof on purpose: a CHECK whose expression evaluates to NULL PASSES, so a
  -- collapsing predicate here would fail OPEN and seal nothing. `name` is the primary key and
  -- cannot be NULL, and the coalesce makes that independent of anyone ever changing that.
  coalesce(name, '') not in ('cancel_free_hours', 'cancel_late_pct',
                             'cancel_post_accept_pct', 'fee_platform_split_pct')
  or value_num is not null
);

comment on constraint club_config_ruled_value_present on club_config is
  '0118 R2A: the four Sean-ruled ladder keys may not hold a NULL value_num. club_cfg_required
raises on NULL, and that raise inside club_finish_session would roll back the session finish and
its refunds — so the refusal is moved to the ops UPDATE that would cause it';

create or replace function _club_config_ruled_row_guard() returns trigger
language plpgsql security invoker
set search_path = public, pg_temp
as $$
declare
  v_ruled text[] := array['cancel_free_hours', 'cancel_late_pct',
                          'cancel_post_accept_pct', 'fee_platform_split_pct'];
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'ruled_club_config_row_required:*'
      using detail = 'club_config holds Sean-ruled money policy; truncating it would make every ladder read raise inside club_finish_session and strand refunds';
  end if;
  if tg_op = 'DELETE' then
    if old.name = any (v_ruled) then
      raise exception 'ruled_club_config_row_required:%', old.name
        using detail = 'club_cfg_required raises on an ABSENT row exactly as it does on a NULL one, and that raise rolls back a session finish. Change the value, never remove the row';
    end if;
    return old;
  end if;
  if old.name = any (v_ruled) and new.name is distinct from old.name then
    raise exception 'ruled_club_config_row_required:%', old.name
      using detail = 'renaming a ruled key removes it as far as club_cfg(<name>) is concerned — same rollback, different spelling';
  end if;
  return new;
end $$;

comment on function _club_config_ruled_row_guard is
  '0118 R2A: the DELETE/rename/TRUNCATE half of the ruled-ladder seal. The CHECK constraint
covers a NULL value; this covers an absent row. Both exist so that no reachable club_config
state can make club_cfg_required raise inside club_finish_session, where the raise would roll
back the finish and its refunds';

drop trigger if exists _club_config_ruled_rows on club_config;
create trigger _club_config_ruled_rows
  before update or delete on club_config
  for each row execute function _club_config_ruled_row_guard();

drop trigger if exists _club_config_no_truncate on club_config;
create trigger _club_config_no_truncate
  before truncate on club_config
  for each statement execute function _club_config_ruled_row_guard();

-- `cancel_fee` is shared with marketplace cancellations, so the club event facts are explicitly
-- namespaced. NULL/NULL means "not a club-fee event". Existing pilot rows are NOT backfilled:
-- inventing an event timestamp at deploy time would make an old cancellation look new and is the
-- exact retroactive-charge defect this slice exists to prevent.
alter table bookings add column if not exists club_fee_event_at timestamptz;
alter table bookings add column if not exists club_fee_cutover_at timestamptz;
alter table bookings add column if not exists club_fee_kind text;
alter table bookings drop constraint if exists bookings_club_fee_event_pair;
alter table bookings add constraint bookings_club_fee_event_pair check (
  (club_fee_event_at is null and club_fee_cutover_at is null and club_fee_kind is null)
  or (club_fee_event_at is not null
      and club_fee_kind in ('cancel_fee', 'no_show_fee')
      and coalesce(cancel_fee, 0) > 0)
);

comment on column bookings.club_fee_event_at is
  '0118: when the fee-bearing CLUB event happened. This timestamp, not mint/sweep call time,
decides payments_live_since eligibility. Deliberately no backfill: pilot-era events stay free';
comment on column bookings.club_fee_cutover_at is
  '0118: payments_live_since observed at the CLUB fee event. NULL means charging was off at the
event and can never be changed into eligibility by a later flag backdate; no historical backfill';
comment on column bookings.club_fee_kind is
  '0118: named club policy that produced cancel_fee — cancel_fee or no_show_fee. NULL means the
marketplace path or no club fee. No-show has its own name so its future rate can move alone';

-- 0052 §5: rejection/cancellation/nonperformance money facts ride durable ack fanout. These are
-- the two new INSERT-time titles introduced below; the existing full-refund titles stay registered.
insert into club_critical_titles(title) values
  ('위탁 취소 접수'), ('위탁 미진행 — 취소 수수료')
on conflict do nothing;

-- No new column guard: 0058 §3's `_guard_booking_cols` is deliberately future-proof
-- (`new is distinct from old`) and rejects ANY changed booking column from client roles. 0111
-- separately revoked client INSERT. Copying that rule into a second trigger would violate the
-- one-copy law and, worse, produce a false-green pin when either guard is deleted. Suite 153 P8
-- exercises these new columns through the existing deny-all; 99 S8 / 146 D-9 own that guard.

-- A caught mint exception is allowed ONLY because it becomes durable state. SQL cannot invoke
-- `_shared/ops.ts`, so it cannot use that module's OPS_PROFILE_ID fallback. It does route to any
-- provisioned `ops_recipients(event_class='club_fee_mint_failed')`, and the sealed table plus the
-- reconciliation function below remain the safety net when (as measured today) routing has zero
-- recipients. If writing this row fails, the exception escapes and the cancellation rolls back;
-- invisible success is not an allowed outcome.
create table if not exists club_fee_mint_failures (
  booking_id uuid primary key references bookings(id) on delete cascade,
  fee_kind text not null check (fee_kind in ('cancel_fee', 'no_show_fee')),
  fee_event_at timestamptz not null,
  error_code text not null,
  error_message text not null,
  attempts int not null default 1 check (attempts > 0),
  first_failed_at timestamptz not null default now(),
  last_failed_at timestamptz not null default now(),
  resolved_at timestamptz
);
alter table club_fee_mint_failures enable row level security;
revoke all on table club_fee_mint_failures from public, anon, authenticated;
grant select, insert, update, delete on table club_fee_mint_failures to service_role;

comment on table club_fee_mint_failures is
  '0118: durable, sealed ops queue for a club fee that was recorded but whose payment intent mint
failed. A SQL caller cannot reach _shared/ops.ts/OPS_PROFILE_ID, so provisioned recipients receive
event class club_fee_mint_failed and this table remains the recovery source when none exist';

-- 0084 deliberately keeps the event-class vocabulary in the routing table comment (not a CHECK).
-- Append this emitter there without copying/replacing whatever newer branches added to the list.
do $$
declare v_note text;
begin
  select obj_description('ops_recipients'::regclass, 'pg_class') into v_note;
  if coalesce(v_note, '') not like '%club_fee_mint_failed%' then
    execute format(
      'comment on table ops_recipients is %L',
      coalesce(v_note, '') || E'\n  club_fee_mint_failed   — a recorded club fee whose immediate payment-intent mint failed (0118)'
    );
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  One event-time predicate, one existing-intent predicate, and the amended mint
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- THE event-time rule lives once. The event compares with the cutover SNAPSHOT observed when it
-- happened, never with a later replacement value. This closes 0084 §D's stated raw-UPDATE hole:
-- even a later backdate cannot turn an off-era event into a debt. The current flag appears only
-- as the emergency OFF switch. A null snapshot is forever ineligible; no sweep call can fill it.
create or replace function _club_fee_event_collectable(p_booking uuid) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select coalesce(b.cancel_fee, 0) > 0
       and b.club_fee_kind in ('cancel_fee', 'no_show_fee')
       and b.club_fee_event_at is not null
       and b.club_fee_cutover_at is not null
       and b.club_fee_event_at >= b.club_fee_cutover_at
       and f.payments_live_since is not null
    from bookings b
    cross join ops_flags f
    where b.id = p_booking and f.id
  ), false)
$$;
revoke execute on function _club_fee_event_collectable(uuid) from public, anon, authenticated;
grant execute on function _club_fee_event_collectable(uuid) to service_role;

-- One copy of "does a row already settle/block this charge?". Any server-kind row blocks a new
-- intent, INCLUDING canceled/partial_canceled: 0116 proved that ignoring those refund-shaped
-- rows can create a fresh full charge next to a remainder. The sixth reconciliation arm (§G)
-- summons the human; minting a second row is not the remedy.
create or replace function _cancel_fee_existing_payment(p_booking uuid) returns setof payments
language sql stable security definer
set search_path = public, pg_temp
as $$
  select p.*
  from payments p
  where p.booking_id = p_booking
    and (p.status in ('confirmed', 'waived') or (p.raw->>'kind') is not null)
  order by case when p.status in ('confirmed', 'waived') then 0 else 1 end, p.created_at
  limit 1
$$;
revoke execute on function _cancel_fee_existing_payment(uuid) from public, anon, authenticated;
grant execute on function _cancel_fee_existing_payment(uuid) to service_role;

-- EXTENDS 0080 §E. Marketplace callers keep the old flag-at-call-time behavior because they do
-- not yet persist a club event. Club rows are different: presence of a club session or club kind
-- makes the event-time predicate mandatory, so an old club fee can never become collectable by
-- calling this function after the flip. New intents keep raw.kind='cancel_fee' because the charge
-- dispatcher uses that rail for its receipt name; raw.fee_kind carries the distinct no-show name.
create or replace function mint_cancel_fee_intent(p_booking uuid)
returns table (payment_id uuid, order_id text, amount int, status text, minted boolean)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_existing payments%rowtype;
  v_row payments%rowtype;
  v_fee int;
  v_order text;
  v_since timestamptz;
  v_event_at timestamptz;
  v_cutover_at timestamptz;
  v_fee_kind text;
  v_club uuid;
begin
  select coalesce(b.cancel_fee, 0), b.club_fee_event_at, b.club_fee_cutover_at,
         b.club_fee_kind, b.club_session_id
    into v_fee, v_event_at, v_cutover_at, v_fee_kind, v_club
  from bookings b where b.id = p_booking;
  if not found then raise exception 'not_found'; end if;

  select f.payments_live_since into v_since from ops_flags f where f.id;
  if v_fee_kind is not null or v_club is not null then
    if not _club_fee_event_collectable(p_booking) then return; end if;
  elsif v_since is null then
    return;                                        -- marketplace charging is off
  end if;

  perform pg_advisory_xact_lock(hashtextextended('mint:' || p_booking::text, 0));

  select p.* into v_existing from _cancel_fee_existing_payment(p_booking) p;
  if v_existing.id is not null then
    return query select v_existing.id, v_existing.order_id, v_existing.amount,
                        v_existing.status, false;
    return;
  end if;

  if v_fee <= 0 then return; end if;

  v_order := 'dr_' || gen_random_uuid()::text;
  insert into payments (booking_id, order_id, amount, status, raw)
  values (
    p_booking, v_order, v_fee, 'pending',
    jsonb_strip_nulls(jsonb_build_object(
      'kind', 'cancel_fee',
      'fee_kind', coalesce(v_fee_kind, 'cancel_fee'),
      'fee_event_at', v_event_at,
      'fee_cutover_at', v_cutover_at,
      'attempts', 0
    ))
  ) returning * into v_row;

  return query select v_row.id, v_row.order_id, v_row.amount, v_row.status, true;
end $$;
revoke execute on function mint_cancel_fee_intent(uuid) from public, anon, authenticated;
grant execute on function mint_cancel_fee_intent(uuid) to service_role;

comment on function mint_cancel_fee_intent is
  '0080 §E + 0118 §B: cancel-fee intent mint. Club events use their persisted
bookings.club_fee_event_at against the event-time cutover snapshot; call time or a later raw flag
backdate cannot make a pilot event chargeable. Marketplace rows retain 0080 behavior. Any kind-bearing payment, including
canceled/partial_canceled, blocks a second intent and is surfaced by payments_reconciliation';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  The recorder writes the money, the runner book, and the immediate mint
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Linearization point for fee event + cutover. The row lock is acquired BEFORE clock_timestamp()
-- and remains held through the caller's transaction, so a supported setter or raw ops_flags UPDATE
-- is ordered wholly before or wholly after the event. `_club_record_fee` calls this before it can
-- wait on `comp:` and never rereads the flag after that wait.
create or replace function _club_fee_event_clock()
returns table(event_at timestamptz, cutover_at timestamptz)
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  select f.payments_live_since into cutover_at
  from ops_flags f where f.id
  for share;
  if not found then raise exception 'ops_flags_missing'; end if;
  event_at := clock_timestamp();
  return next;
end $$;
revoke execute on function _club_fee_event_clock() from public, anon, authenticated;

create or replace function _club_note_fee_mint_failure(
  p_booking uuid, p_code text, p_message text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_kind text; v_event_at timestamptz;
begin
  select b.club_fee_kind, b.club_fee_event_at into v_kind, v_event_at
  from bookings b where b.id = p_booking;
  if v_kind is null or v_event_at is null then
    raise exception 'club_fee_event_missing';
  end if;

  insert into club_fee_mint_failures
    (booking_id, fee_kind, fee_event_at, error_code, error_message)
  values
    (p_booking, v_kind, v_event_at, coalesce(p_code, 'P0001'), left(coalesce(p_message, 'unknown'), 1000))
  on conflict (booking_id) do update set
    fee_kind = excluded.fee_kind,
    fee_event_at = excluded.fee_event_at,
    error_code = excluded.error_code,
    error_message = excluded.error_message,
    attempts = club_fee_mint_failures.attempts + 1,
    last_failed_at = now(),
    resolved_at = null;

  -- SQL can use the table half of 0084 routing, but not `_shared/ops.ts`'s environment fallback.
  -- The body is redacted under that module's law; the booking id stays in ref_id/query state.
  insert into notifications (profile_id, kind, title, body, ref_id)
  select r.profile_id, 'system', '클럽 취소 수수료 인텐트 실패 — 확인 필요',
         'club_fee_mint_reconciliation()에서 미발행 인텐트를 확인해주세요', p_booking
  from ops_recipients_for('club_fee_mint_failed') as r(profile_id)
  where not exists (
      select 1 from notifications n
      where n.profile_id = r.profile_id and n.ref_id = p_booking
        and n.title = '클럽 취소 수수료 인텐트 실패 — 확인 필요'
        and n.created_at >= now() - interval '1 hour'
    );
end $$;
revoke execute on function _club_note_fee_mint_failure(uuid, text, text)
  from public, anon, authenticated;

-- This is the ONLY exception guard around the mint. It is not a NOTICE swallow: failure becomes
-- a durable queue row. If the queue write itself fails, that error escapes this handler and rolls
-- the whole event back, which is the only honest fallback.
create or replace function _club_try_mint_cancel_fee(p_booking uuid) returns boolean
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_rows int;
  v_state text;
  v_message text;
begin
  if not _club_fee_event_collectable(p_booking) then return false; end if;

  begin
    select count(*)::int into v_rows from mint_cancel_fee_intent(p_booking);
    if v_rows = 0 then raise exception 'mint_returned_no_row'; end if;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    perform _club_note_fee_mint_failure(p_booking, v_state, v_message);
    return false;
  end;

  update club_fee_mint_failures set resolved_at = now()
  where booking_id = p_booking and resolved_at is null;
  return true;
end $$;
revoke execute on function _club_try_mint_cancel_fee(uuid) from public, anon, authenticated;

-- One writer for BOTH named policies. The wrappers decide policy; this function alone writes the
-- amount, two club_fee_items rows, runner compensation and immediate mint attempt.
create or replace function _club_record_fee(
  p_session uuid, p_sd uuid, p_booking uuid, p_kind text,
  p_base int, p_pct numeric, p_runner uuid, p_rule text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_fee int;
  v_plat int;
  v_share int;
  v_existing_fee int;
  v_existing_kind text;
  v_event_at timestamptz;
  v_cutover_at timestamptz;
begin
  if p_kind is null or p_kind not in ('cancel_fee', 'no_show_fee') then
    raise exception 'bad_fee_kind';
  end if;
  v_fee := round(p_base * p_pct / 100.0)::int;
  if coalesce(v_fee, 0) <= 0 then return; end if;
  -- R2A: NULLing the split must not silently resurrect 50/50 out of this line.
  v_plat := round(v_fee * club_cfg_required('fee_platform_split_pct') / 100.0)::int;
  v_share := v_fee - v_plat;

  -- Capture timestamp + cutover while holding the ops_flags row lock, BEFORE a possibly long
  -- `comp:` wait. Core never rereads the flag: the event's own snapshot is the permanent answer.
  select e.event_at, e.cutover_at into v_event_at, v_cutover_at
  from _club_fee_event_clock() e;

  -- The comp lock IS the ledger serialization. `ledger_items` has no unique booking key, so it is
  -- taken before the read-then-insert existence check and shares 0080/0085's exact key space.
  perform pg_advisory_xact_lock(hashtextextended('comp:' || p_booking::text, 0));

  -- FIRST WRITER WINS. All event facts land in the same statement; a live intent can never be
  -- silently repriced by a retry or by a second policy reaching the same booking.
  update bookings
  set cancel_fee = v_fee, club_fee_event_at = v_event_at,
      club_fee_cutover_at = v_cutover_at, club_fee_kind = p_kind
  where id = p_booking
    and coalesce(cancel_fee, 0) = 0
  returning cancel_fee into v_existing_fee;

  if not found then
    select b.cancel_fee, b.club_fee_kind into v_existing_fee, v_existing_kind
    from bookings b where b.id = p_booking;
    if not found then raise exception 'not_found'; end if;
    if v_existing_fee is distinct from v_fee or v_existing_kind is distinct from p_kind then
      raise exception 'cancel_fee_already_recorded';
    end if;
    perform _club_try_mint_cancel_fee(p_booking);       -- idempotent retry/recovery nudge
    return;
  end if;

  insert into club_fee_items (session_id, session_dog_id, booking_id, kind, amount_krw,
                              recipient_type, recipient_profile_id, basis)
  values
    (p_session, p_sd, p_booking, p_kind, v_plat, 'platform', null,
     jsonb_build_object('pct', p_pct, 'base', p_base, 'rule', p_rule,
                        'share', 'platform', 'eventAt', v_event_at)),
    (p_session, p_sd, p_booking, p_kind, v_share,
     case when p_runner is not null then 'runner' else 'platform' end, p_runner,
     jsonb_build_object('pct', p_pct, 'base', p_base, 'rule', p_rule,
                        'share', 'supply_compensation', 'eventAt', v_event_at));

  -- Sean 2026-08-21, §0-quinvicies, verbatim: "Join the pool — accrue it". The runner share
  -- enters the same ledger/my_ledger_total pool as the eight existing earning writers even while
  -- payouts has no writer. `platform_fee` MUST be 0: my_ledger_total subtracts it. The platform
  -- half already lives in club_fee_items; this is the RUNNER's book of what they are owed.
  if p_runner is not null and v_share > 0
     and not exists (select 1 from ledger_items li where li.booking_id = p_booking) then
    insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                              tip, remaining_guarantee, platform_fee)
    values (p_runner, p_booking, 0, 0, 0, 0, v_share, 0);
  end if;

  perform _club_try_mint_cancel_fee(p_booking);
end $$;
revoke execute on function _club_record_fee(uuid, uuid, uuid, text, int, numeric, uuid, text)
  from public, anon, authenticated;

-- Existing signature retained for the three historical cancellation definitions, but the kind
-- is now an assertion rather than a passenger. Passing no_show_fee here fails loudly.
create or replace function _club_record_cancel_fee(
  p_session uuid, p_sd uuid, p_booking uuid, p_kind text,
  p_base int, p_pct numeric, p_runner uuid, p_rule text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if p_kind is distinct from 'cancel_fee' then raise exception 'bad_cancel_fee_policy'; end if;
  perform _club_record_fee(p_session, p_sd, p_booking, 'cancel_fee',
                           p_base, p_pct, p_runner, p_rule);
end $$;
revoke execute on function _club_record_cancel_fee(uuid, uuid, uuid, text, int, numeric, uuid, text)
  from public, anon, authenticated;

-- No-show is a named policy function. It reads today's ruled 20% from club_cfg just like the
-- cancellation ladder, but a future ruling changes this arm alone rather than a p_kind passenger
-- nobody can see.
create or replace function _club_record_no_show_fee(
  p_session uuid, p_sd uuid, p_booking uuid, p_base int, p_runner uuid
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform _club_record_fee(
    p_session, p_sd, p_booking, 'no_show_fee', p_base,
    club_cfg_required('cancel_post_accept_pct'), p_runner,
    'no_show_ladder_top'
  );
end $$;
revoke execute on function _club_record_no_show_fee(uuid, uuid, uuid, int, uuid)
  from public, anon, authenticated;

-- EXTENDS 0038:211-227. This remains the ONE confirmed→cancelled_runner→refund_pending transition.
-- 0024's AFTER INSERT push trigger freezes NEW title/body immediately, so a post-insert correction
-- would leave the database truthful and the owner's phone false. The shared helper therefore picks
-- the copy at INSERT time from already-frozen no-show event facts. Every other caller retains the
-- original full-refund copy byte-for-byte.
create or replace function _club_refund_confirmed(p_session uuid, p_reason text) returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_row record; n int := 0; v_collectable boolean;
begin
  for v_row in
    select b.id, b.owner_id, b.cancel_fee, b.club_fee_kind
    from bookings b
    where b.club_session_id = p_session and b.status = 'confirmed'
  loop
    update bookings set status = 'cancelled_runner', cancel_reason = p_reason where id = v_row.id;
    update bookings set status = 'refund_pending' where id = v_row.id;
    v_collectable := p_reason = 'club_not_picked_up'
                     and v_row.club_fee_kind = 'no_show_fee'
                     and _club_fee_event_collectable(v_row.id);

    insert into notifications (profile_id, kind, title, body, ref_id)
    values (
      v_row.owner_id, 'booking',
      case when v_collectable
           then '위탁 미진행 — 취소 수수료' else '위탁 취소 — 전액 환불' end,
      case when v_collectable
           then '위탁 러닝이 진행되지 않아 취소 수수료 '
                || v_row.cancel_fee || '원이 결제 예정으로 기록됐어요'
           else '배정된 위탁 러닝이 진행되지 못했어요 — 전액 환불 처리돼요' end,
      v_row.id
    );
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function _club_refund_confirmed(uuid, text)
  from public, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  Live club owner-cancel path: ruled ladder, captured runner, truthful copy
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- EXTENDS 0057:190-258. Party gate precedes every state gate. Missing and somebody else's
-- session_dog both raise `not_found`, so the RPC is not an id-enumeration oracle. The owner rule
-- appears ONCE; after the session lock the already-authorized immutable row is refreshed by id.
create or replace function session_cancel_delegation(p_session_dog uuid) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  sd record;
  s record;
  v_bst text;
  v_runner uuid;
  v_total int;
  v_pct numeric;
  v_rule text;
  v_collectable boolean;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- PARTY GATE FIRST. No row and another owner's row are the same answer.
  select * into sd from session_dogs
  where id = p_session_dog and owner_profile_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
  perform _club_require_v2();

  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;
  if not found then raise exception 'not_found'; end if;

  if sd.service_state = 'ended' then raise exception 'already_ended'; end if;
  if exists (
    select 1 from club_incident_subjects sub
    join club_incidents i on i.id = sub.incident_id
    where sub.subject_type = 'dog' and sub.subject_id = sd.dog_id and i.state <> 'resolved'
  ) then
    raise exception 'incident_open';
  end if;

  if sd.booking_id is null then
    update session_dogs set approval = 'withdrawn',
      hold_status = case when hold_status = 'active' then 'released' else hold_status end
    where id = p_session_dog;
    update session_dogs set id = id where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.host_profile_id, 'community', '위탁 신청 취소',
            '보호자가 위탁 신청을 취소했어요', sd.session_id);
    return;
  end if;

  select status::text, runner_id, total_price into v_bst, v_runner, v_total
  from bookings where id = sd.booking_id for update;
  if v_bst not in ('matching', 'confirmed') then raise exception 'already_handed_off'; end if;

  -- The ruled ladder remains club_cfg single truth: accepted first, then <24h, then free.
  -- R2A: `club_cfg_required`, not `coalesce(club_cfg(k), <ruled number>)`. Every rung is a rate
  -- somebody is CHARGED, so an empty config must stop the charge, not fall back to it. The
  -- free-window arm below stays a literal 0 — that is this ladder's own "no fee", not a config
  -- value with a shadow copy.
  if v_bst = 'confirmed' and v_runner is not null then
    v_pct := club_cfg_required('cancel_post_accept_pct');
    v_rule := 'post_acceptance';
  elsif s.scheduled_at - now()
        < make_interval(hours => club_cfg_required('cancel_free_hours')::int) then
    v_pct := club_cfg_required('cancel_late_pct');
    v_rule := 'late_cancel';
  else
    v_pct := 0;
    v_rule := 'free_window';
  end if;

  if v_bst = 'confirmed' then
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_runner, 'revoked', 'owner_cancel', auth.uid());
    update bookings set runner_id = null, status = 'matching',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  end if;
  update bookings set status = 'refund_pending', cancel_reason = 'club_owner_cancel'
  where id = sd.booking_id;
  update session_dogs set id = id where id = p_session_dog;

  -- p_runner is the captured value. The booking is intentionally NULL by now.
  perform _club_record_cancel_fee(sd.session_id, sd.id, sd.booking_id, 'cancel_fee',
                                  v_total, v_pct, v_runner, v_rule);
  v_collectable := _club_fee_event_collectable(sd.booking_id);

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '위탁 취소 접수',
     case
       when v_pct > 0 and v_collectable then
         '위탁 취소가 접수됐어요 — 취소 수수료 ' || v_pct || '%가 결제 예정으로 기록됐어요'
       when v_pct > 0 then
         '위탁 취소가 접수됐어요 — 취소 수수료 ' || v_pct || '%가 기록됐어요'
       else
         '위탁 취소가 접수됐어요 — 취소 수수료는 없어요'
     end,
     sd.booking_id),
    (s.host_profile_id, 'community', '위탁 취소',
     '보호자가 결제된 위탁을 취소했어요', sd.session_id);
  if v_runner is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_runner, 'booking', '배정 취소',
            '보호자 취소로 배정이 해제됐어요 — 보상 기록이 남았어요', sd.session_id);
  end if;
end $$;
revoke execute on function session_cancel_delegation(uuid) from public, anon;
grant execute on function session_cancel_delegation(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  No-show is its own policy and its own persisted name
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- EXTENDS 0048 §J. The party gate now precedes dogs/case state gates: missing session and another
-- host's session get the same `not_host_or_closed` answer. All finish behavior is otherwise
-- carried forward, with the one no-show call switched to `_club_record_no_show_fee` before the
-- shared refund helper chooses the truthful INSERT-time notification copy.
create or replace function club_finish_session(p_session uuid) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  s record;
  v_name text;
  v_teams int;
  v_dogs int;
  v_ids uuid[];
begin
  -- PARTY GATE FIRST. This fixture also remains NULL-safe when backup_host_profile_id is NULL:
  -- only the named host owns this mutation, and no `not (uid in (..., null))` shape exists.
  select * into s from club_sessions
  where id = p_session and host_profile_id = auth.uid()
  for update;
  if not found then raise exception 'not_host_or_closed'; end if;
  if s.status not in ('open', 'full') then raise exception 'not_host_or_closed'; end if;

  if _club_dogs_unresolved(p_session) > 0 then raise exception 'dogs_not_returned'; end if;
  if exists (
    select 1 from club_incidents
    where session_id = p_session and state <> 'resolved' and case_owner is null
  ) then
    raise exception 'incident_unassigned';
  end if;

  update club_sessions set status = 'done' where id = p_session;
  select name into v_name from clubs where id = s.club_id;
  select count(*) into v_teams from session_people
  where session_id = p_session and attendance = 'checked_in';
  select count(*) into v_dogs from session_dogs
  where session_id = p_session and checked_in_at is not null;

  if v_teams > 0 then
    insert into feed_posts (author_id, body, meta)
    values (auth.uid(), null, jsonb_build_object(
      'club', v_name, 'sessionId', p_session, 'teams', v_teams, 'dogs', v_dogs,
      'sessionAt', s.scheduled_at, 'badges', jsonb_build_array('🏁 하이클럽')));
    insert into notifications (profile_id, kind, title, body, ref_id)
    select sp.profile_id, 'community', v_name || ' 리캡 도착',
           v_teams || '팀이 함께 달렸어요 — 피드에서 확인하세요', p_session
    from session_people sp
    where sp.session_id = p_session and sp.attendance = 'checked_in'
      and sp.profile_id <> auth.uid();
  end if;

  select coalesce(array_agg(id), '{}') into v_ids
  from bookings where club_session_id = p_session and status = 'matching';
  perform _club_refund_bookings(v_ids, 'club_not_picked_up',
    '위탁 미진행 — 전액 환불', '세션이 끝났지만 위탁 러닝이 진행되지 않았어요 — 전액 환불 처리돼요');
  -- DISTINCT POLICY, RECORDED BEFORE REFUND COPY. Pick at most one session_dog id as evidence,
  -- but do not strand the booking if a legacy row lacks that optional link. The fee writer accepts
  -- NULL p_sd; booking id and captured p_runner are the money identities.
  perform _club_record_no_show_fee(
    p_session,
    (select sd.id from session_dogs sd where sd.booking_id = b.id order by sd.id limit 1),
    b.id, b.total_price::int, b.runner_id
  )
  from bookings b
  where b.club_session_id = p_session and b.status = 'confirmed' and b.runner_id is not null
    -- ═══ R1C (Sean 2026-08-24): a no-show fee needs a TIME gate and an ATTENDANCE gate ═══════
    -- Until this line the money predicate was `confirmed and runner_id is not null` and nothing
    -- else. Two people were charged 20% for a no-show that had not happened:
    --   (a) TIME — a host could close TOMORROW's session today and every owner was billed for
    --       failing to show up to a session that has not started. `now() >= s.scheduled_at` is
    --       the whole claim the fee rests on: the appointment arrived and the dog did not.
    --   (b) ATTENDANCE — an owner who turned up and handed the dog over was billed, while the
    --       runner who walked away was CREDITED the supply half of that same fee.
    --
    -- ⚠ ATTENDANCE TAKES **TWO** SIGNALS, NOT ONE. Corrected 2026-08-24 after measurement and
    -- before this file landed. The first draft of this gate read `session_dogs.checked_in_at`
    -- alone, and for the population the ruling was actually about that column can never be
    -- written — the gate was INERT for exactly the people it was made to protect.
    -- MEASURED, driving the real RPC chain against a full-migration database:
    --   • `session_checkin` raises `not_joined` for a delegation-only owner. The mechanism is
    --     the missing `session_people` row and nothing else: the function's own `session_dogs`
    --     UPDATE would have matched 1 row (`responsible_profile_id` is still the owner
    --     pre-handoff), and injecting the one missing `session_people` row makes the identical
    --     call stamp `checked_in_at`. `session_delegate_dog` (0048:135-153) creates no such row,
    --     and a direct client INSERT is refused by RLS. `club_join` does not help — membership
    --     is not the gate, participation is.
    --   • A whole-schema before/after row-count diff over `public` when that owner taps
    --     인계 확인 shows NO table gaining a row. The tap writes exactly ONE column on ONE row:
    --     `bookings.owner_confirmed_handoff_at`. A `service_role` write of it on a club booking
    --     at `confirmed` is ACCEPTED (rows=1), status stays `confirmed`, and
    --     `session_dogs.checked_in_at` does not move (the custody trigger keys on `picked_up`).
    --   • `bookings.arrived_at` is the RUNNER's arrival, is refused to clients by
    --     `booking_protected_columns`, and its CAS matches 0 rows at `confirmed`. Not evidence.
    -- So the gate is the PAIR, and a fee requires that NEITHER exists:
    --   • `session_dogs.checked_in_at` — the owner who RSVP'd as a person and checked in
    --     (`session_rsvp(session, null)` then `session_checkin`: MEASURED producible with the
    --     booking still `confirmed` and the dog still `runner_delegated`), and the same column
    --     stamped by 0038/0045's custody trigger at `picked_up`. Suite 153 P10 owns this arm.
    --   • `bookings.owner_confirmed_handoff_at` — the delegation-only owner who tapped 인계 확인.
    --     `transition-booking/index.ts:314` is the ONLY non-null writer in the schema and all
    --     edge functions, under service_role; direct client forgery is refused by 0057 §3's
    --     `booking_protected_columns` guard. The button's render condition
    --     (`app/club/session/[sid].tsx:784`) is `assigned && checkinOpen`, and `checkinOpen` is a
    --     pure time predicate (0053:244), NOT membership-derived — so this owner does get it.
    --     SOURCE-READ for the client half; MEASURED for the database half. Suite 153 P12 owns it.
    -- Either signal ALONE was wrong. `checked_in_at` alone bills the delegation-only owner who
    -- turned up; `owner_confirmed_handoff_at` alone bills the RSVP owner who checked in but never
    -- had a handoff stamp written. Both together are correct on all five measured populations.
    --
    -- 🔴 OPEN RESIDUAL — NAMED, NOT CLOSED. `owner_confirmed_handoff_at` is NOT DURABLE. Six
    -- functions NULL it on a `confirmed` booking, because the field means "THIS PAIRING's
    -- handoff", not "the owner attended": `session_propose_dog` (0048:484),
    -- `session_proposal_respond`, `session_assignment_revoke`, `session_cancel_delegation`,
    -- `session_owner_objection`, `_club_dog_materiality_tg`. MEASURED end-to-end: owner taps
    -- 인계 확인 → host reassigns the dog to another runner → the stamp is ERASED, status goes to
    -- `matching`, the new runner accepts, and the booking is back at `confirmed` with the stamp
    -- still NULL. That owner demonstrably turned up and is now byte-identical to one who never
    -- came, so this gate charges them 20%. `session_dogs.checked_in_at` SURVIVES the identical
    -- reassignment — nothing in the schema ever sets it back to NULL — so the residual is exactly:
    --     *a delegation-only owner whose dog is reassigned AFTER they confirmed handoff.*
    -- It is strictly narrower than the defect R1C fixed, and it is not closable inside this file:
    -- closing it needs a durable "this owner attended" fact that the reassignment paths do not
    -- reset, which is a new column and a product decision about what the stamp means. The one
    -- durable trace that survives today is a `notifications` row addressed to the runner
    -- (`transition-booking/index.ts:329`, title 인계 확인 요청) — named here for whoever picks
    -- this up, NOT used: it is an incidental side-effect rather than a designed evidence record,
    -- and it was source-read, never measured. LEFT OPEN AND ESCALATED rather than papered over.
    -- (An owner whose dog is NEVER assigned has no handoff button at all — but `runner_id is not
    -- null` above already excludes them, so they are refunded, not charged. No gap there.)
    --
    -- NO GRACE INTERVAL — RULED, not argued. Sean ruled on 2026-08-24: ship STRICT, no grace
    -- window and no `club_config` key for one. This line used to argue for strictness on its own
    -- merits; it is now recording a decision. What strictness COSTS, written down so the ruling
    -- can be revisited on facts rather than rediscovered: a host who finishes at
    -- `scheduled_at + 1 second` bills every owner who has not handed off by that instant —
    -- someone stuck in traffic five minutes out pays 20%. If that ever needs to change it is one
    -- term on this line plus one `club_config` key read through `club_cfg_required`; nothing else
    -- in this file moves.
    --
    -- SHAPE: these gates are in the fee's WHERE, not in an `if ... raise`. When they fail the
    -- session still finishes and `_club_refund_confirmed` below still refunds — that is the
    -- pre-0118 behaviour and 0045's contract. A no-show fee is an addition to finishing, never a
    -- precondition for it. Both attendance terms are NULL-collapse-proof by construction: a
    -- `not exists` subquery (so a missing `session_dogs` row cannot make the term NULL and drop
    -- the booking) and a bare `is null` on the booking's own column. Never `not (A and B)` over a
    -- nullable column — the fail-open shape this repo has been bitten by four times.
    and now() >= s.scheduled_at
    and not exists (
      select 1 from session_dogs sd
      where sd.booking_id = b.id and sd.checked_in_at is not null
    )
    and b.owner_confirmed_handoff_at is null;
  perform _club_refund_confirmed(p_session, 'club_not_picked_up');

  -- R2A EXEMPT, on purpose. This coalesce falls back to ZERO, and zero here means "record no
  -- host fee at all" — deleting the key stops a PAYMENT, it does not silently keep making one.
  -- That is fail-CLOSED, the opposite of the ladder's fail-open constants, so it keeps `club_cfg`.
  if coalesce(club_cfg('host_fee_krw'), 0) > 0 and exists (
    select 1 from bookings where club_session_id = p_session and status = 'completed'
  ) then
    insert into club_fee_items
      (session_id, kind, amount_krw, recipient_type, recipient_profile_id, basis)
    values
      (p_session, 'host_fee', club_cfg('host_fee_krw')::int, 'host', auth.uid(),
       jsonb_build_object('rule', 'session_completed'));
  end if;
end $$;
revoke execute on function club_finish_session(uuid) from public, anon;
grant execute on function club_finish_session(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §F  Recovery: recorded obligation only, never timer-derived money
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- This is compatible with 0068 because the clock decides NOTHING about what is owed. The sweep
-- reads an amount a human event already froze under the ruled ladder, requires that event's own
-- timestamp to be on/after cutover, and calls the same mint as the immediate path. It never
-- infers a fee from booking status, scheduled time, total_price or current config.
create or replace function sweep_club_cancel_fee_intents() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare r record; n int := 0;
begin
  for r in
    select b.id
    from bookings b
    where _club_fee_event_collectable(b.id)
      and not exists (select 1 from _cancel_fee_existing_payment(b.id))
    order by b.club_fee_event_at, b.id
    limit 100
  loop
    if _club_try_mint_cancel_fee(r.id) then n := n + 1; end if;
  end loop;
  return n;
end $$;
revoke execute on function sweep_club_cancel_fee_intents() from public, anon, authenticated;
grant execute on function sweep_club_cancel_fee_intents() to service_role;

comment on function sweep_club_cancel_fee_intents is
  '0118 §F: recovery for club fee recorded + intent absent. Status-only-safe: it mints the frozen
bookings.cancel_fee and never recomputes the ladder. The persisted event time must be at/after
its persisted cutover snapshot, so a pilot cancellation remains unchargeable no matter when this runs';

create or replace function club_fee_mint_reconciliation()
returns table (
  booking_id uuid,
  fee_kind text,
  amount int,
  fee_event_at timestamptz,
  attempts int,
  error_code text,
  error_message text,
  first_failed_at timestamptz,
  last_failed_at timestamptz,
  age interval
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select f.booking_id, f.fee_kind, b.cancel_fee, f.fee_event_at, f.attempts,
         f.error_code, f.error_message, f.first_failed_at, f.last_failed_at,
         now() - f.first_failed_at
  from club_fee_mint_failures f
  join bookings b on b.id = f.booking_id
  where f.resolved_at is null
  order by f.first_failed_at, f.booking_id
$$;
revoke execute on function club_fee_mint_reconciliation() from public, anon, authenticated;
grant execute on function club_fee_mint_reconciliation() to service_role;

comment on function club_fee_mint_reconciliation is
  '0118 §F: open durable club-fee mint failures. This is the ops-visible safety net when SQL
cannot reach _shared/ops.ts and no club_fee_mint_failed ops recipient is provisioned';

-- 2-57/5 is the settled-charge sweep; this takes every other one of those ticks, then the
-- existing 4-59/5 dispatcher gets a newly minted row two minutes later. Guarded for the harness.
do $$ begin
  perform cron.schedule('sweep-club-cancel-fees', '2-52/10 * * * *',
                        'select sweep_club_cancel_fee_intents()');
exception when others then
  raise notice 'pg_cron unavailable — call sweep_club_cancel_fee_intents() from an external scheduler';
end $$;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §G  payments_reconciliation arm six: refund-shaped server rows summon a human
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- EXTENDS 0084 §C byte-faithfully plus the final UNION. The six arms remain disjoint by status
-- and marker. 0116 made canceled/partial_canceled kind rows intentionally sweep-blind after a
-- reviewer reproduced a fresh-full-intent double charge next to the refund remainder. "A human
-- resolves it" was not a mechanism; this arm is the queue.
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
  select 'stale_dispatched'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'dispatched_at')::timestamptz
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending'
    and (p.raw->>'dispatched_at') is not null
    and (p.raw->>'dispatched_at')::timestamptz < now() - interval '1 hour'
  union all
  select 'ladder_exhausted'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'failed'
    and (p.raw->>'kind') is not null
    and coalesce((p.raw->>'attempts')::int, 0) >= 3
  union all
  select 'incident_waive_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'review_opened_at')::timestamptz
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'waived'
    and (p.raw->>'review') = 'incident_pending'
    and (p.raw->>'review_resolved_at') is null
  union all
  select 'refund_shaped_server_charge'::text, p.id, p.booking_id, p.amount, p.status,
         b.status::text, false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status in ('canceled', 'partial_canceled')
    and (p.raw->>'kind') is not null
    and exists (select 1 from runs r where r.booking_id = b.id and r.settled_at is not null)
$$;
revoke execute on function payments_reconciliation() from public, anon, authenticated;
grant execute on function payments_reconciliation() to service_role;

comment on function payments_reconciliation is
  '0084 §C + 0118 §G: 결제 조정 질의 6종. The sixth,
refund_shaped_server_charge, surfaces kind-bearing canceled/partial_canceled rows on a settled
run. 0116 deliberately keeps automatic sweeps away from these
rows to prevent a second full charge; this human queue is the corresponding resolution mechanism';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §H  Apply-time assertions for the ruled constants and the copy/policy split
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare v_finish_src text; v_refund_src text;
begin
  if club_cfg('cancel_free_hours') is distinct from 24
     or club_cfg('cancel_late_pct') is distinct from 10
     or club_cfg('cancel_post_accept_pct') is distinct from 20
     or club_cfg('fee_platform_split_pct') is distinct from 50 then
    raise exception '0118: ruled club_config ladder does not match 24/10/20/50';
  end if;

  select p.prosrc into v_finish_src from pg_proc p
  where p.oid = 'club_finish_session(uuid)'::regprocedure;
  select p.prosrc into v_refund_src from pg_proc p
  where p.oid = '_club_refund_confirmed(uuid,text)'::regprocedure;
  if v_finish_src not like '%_club_record_no_show_fee%'
     or v_finish_src not like '%_club_refund_confirmed%'
     or v_refund_src not like '%club_fee_kind = ''no_show_fee''%' then
    raise exception '0118: club_finish_session did not switch to the named no-show policy/copy arm';
  end if;
end $$;
