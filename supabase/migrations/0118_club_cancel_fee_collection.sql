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
--   functions `_club_fee_event_collectable`, `_cancel_fee_existing_payment`,
--     `_club_fee_event_clock`, `_club_note_fee_mint_failure`,
--     `_club_try_mint_cancel_fee`, `_club_record_fee`, `_club_record_no_show_fee`,
--     `sweep_club_cancel_fee_intents`, `club_fee_mint_reconciliation`
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
-- recorders below continue reading `club_cfg()` exactly as 0048 did. No-show is the fifth ruled
-- value and deliberately reads the current post-acceptance value through its OWN policy wrapper.
update club_config set note = case name
  when 'cancel_free_hours'      then 'Sean 2026-08-21 ruled: owner cancellation is free at least 24 hours before the session'
  when 'cancel_late_pct'        then 'Sean 2026-08-21 ruled: late owner cancellation fee percentage'
  when 'cancel_post_accept_pct' then 'Sean 2026-08-21 ruled: post-acceptance cancellation percentage; no-show reads this value through its own named policy'
  when 'fee_platform_split_pct' then 'Sean 2026-08-21 ruled: fee split to platform; the remainder is runner supply compensation'
  else note end
where name in ('cancel_free_hours', 'cancel_late_pct', 'cancel_post_accept_pct',
               'fee_platform_split_pct');

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
  v_plat := round(v_fee * coalesce(club_cfg('fee_platform_split_pct'), 50) / 100.0)::int;
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
    coalesce(club_cfg('cancel_post_accept_pct'), 20), p_runner,
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
  if v_bst = 'confirmed' and v_runner is not null then
    v_pct := coalesce(club_cfg('cancel_post_accept_pct'), 20);
    v_rule := 'post_acceptance';
  elsif s.scheduled_at - now()
        < make_interval(hours => coalesce(club_cfg('cancel_free_hours'), 24)::int) then
    v_pct := coalesce(club_cfg('cancel_late_pct'), 10);
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
  where b.club_session_id = p_session and b.status = 'confirmed' and b.runner_id is not null;
  perform _club_refund_confirmed(p_session, 'club_not_picked_up');

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
