-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0117 — late-booking protocol, stage 2 (the server half): the clock, the resolver, fault,
--        and the 0066 en-route fee carve-out
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- CONTRACT: docs/plans/2026-08-21-late-booking-protocol.md §12 — written by the client side,
-- implemented TO here. Sean's five rulings (same doc §3) constrain everything below:
--   D1 two-sided check-in, not a bare timeout   D2 HOLD SCOPE   D3 split at the handoff line
--   D4 money follows fault                      D5 silence never charges; fault needs a human
--                                                  statement
-- Product numbers, Sean 2026-08-21, verbatim: "grace 30, ceiling 3 hours".
--
-- ─── STANDING DECISION THIS FILE MUST NOT OVERTURN: 0068_retire_t10_hard_stop ──────────────
-- 0068 DELETED an automatic refund fired by a cron, because "refunding when the host closes
-- the session is true; refunding ten minutes before it starts is false", and accepted a stuck
-- row an operator resolves as "strictly better than an automatic refund fired at the exact
-- moment the service was about to be delivered". THE SAME LAW GOVERNS THE CEILING BELOW:
-- the 3-hour ceiling RESOLVES a rotted booking to a terminal STATUS (no_show, D3's pre-custody
-- terminal) and it NEVER moves money and NEVER writes fault — no cancel_fee, no payments
-- intent, no ledger row, no booking_faults row. Timer-driven state is honest ("the service did
-- not start" is observable); timer-driven money is the thing 0068 retired. Every money effect
-- in this protocol requires a human statement (D5) or an owner's own cancel action (0066 path).
--
-- ─── What each section is ──────────────────────────────────────────────────────────────────
--   §1 the two knobs — late_grace() 30 min / late_ceiling() 3 h, GUC-injectable for the
--      harness, literal defaults are THE product numbers. late_ceiling_at() is the single
--      copy of the ceiling arithmetic (used by the sweep, the answer gate, the renewal bound
--      and the fee carve-out — a rule copied N times is a rule you fix N-1 times).
--   §2 booking_checkins — the §12 table verbatim (column-for-column), plus a BEFORE UPDATE
--      guard trigger that makes the contract's IMMUTABLE words true at the table, not merely
--      in the functions: per-side answers write once, resolved_at/resolution write once,
--      version is strictly monotonic, opened_at never moves, deadline_at freezes at resolve.
--   §3 booking_faults — fault persistence (D4's output). stated_by is NOT NULL by design:
--      a fault row is structurally impossible without the human whose statement it records
--      (D5). The resolver writes one only from a side's own 'cannot_proceed'.
--   §4 open_checkin — cron only (§12: "open_checkin(booking) — cron only"). No client role
--      and no service_role holds EXECUTE; the sweep (job owner postgres) is the caller.
--   §5 _resolve_checkin — THE resolver. One transaction, bookings row locked FIRST (same
--      lock order as confirm_return_tx 0083/0096 — the shared custody path), checkin row
--      locked second, bookings.status re-read under that lock (FM6), resolution written
--      through a CAS on (resolved_at, version) exactly as §12 demands. One copy of the
--      resolution matrix; answer path and deadline path both call it.
--   §6 answer_checkin — per-side immutable, first write wins, idempotent on replay, SERVER
--      timestamps only (owner_at/runner_at = now(), never a client value). Refuses
--      'proceeding' past the ceiling (§4.3 / FM4: two taps must not resurrect a 17-day row).
--   §7 fetch_checkin — what the surface renders (party-gated read; carries past_ceiling and
--      server_now so the client neither derives the ceiling nor trusts its own clock).
--   §8 late_booking_sweep + cron — */10 per 0060:145 stagger doctrine (see §8 header).
--   §9 the 0066 carve-out — enroute_cancel_fee_waived() + marketplace_cancel_fee re-created
--      (base = 0066, the newest definition — verified by grep: 0085 explicitly leaves it
--      untouched, nothing after re-creates it). D4/FM7: the 50% en-route arm prices an
--      OWNER's cancel of a live departure; it must not price a runner's recorded failure or
--      a booking the ceiling already declared rotten.
--
-- ─── Why a cannot_proceed carries a REASON (Sean, 2026-08-21, verbatim: "ask why they
-- stopped.") ─────────────────────────────────────────────────────────────────────────────
--   An emergency abort (injured dog, injured runner) must be distinguishable from a flake
--   when the §4.2 fee arms are someday priced against fault rows — the reason is the record
--   that makes that possible, and capturing it later would mean asking people to remember an
--   emergency after the fact. ONE copy of the rule: the reason is taken at ANSWER time, in
--   the same statement as the answer (per-side columns on booking_checkins, immutable with
--   the answer under the same guard), and the resolver COPIES it onto the fault row it
--   writes — the fault row is a snapshot of the statement, so the copy happens exactly where
--   the statement becomes a fault and nowhere else. The column is NULLABLE: the surface must
--   ASK; a mandate to answer is not invented. A reason is REFUSED on any other answer — a
--   free-text channel on a happy path is the abuse class 0114 closed elsewhere.
--
-- ─── Scope lines, stated rather than implied ───────────────────────────────────────────────
--   · CLUB bookings are excluded everywhere (club_session_id is null in every sweep arm,
--     'club_out_of_scope' in every entry point — 0096's idiom). The club has its own recovery
--     doctrine (club_assignment_recovery, club_finish_session's club_not_picked_up refund —
--     the very machinery 0068 ruled on) and its own money ladder in club_config; this
--     protocol is the MARKETPLACE's clock.
--   · One protocol per booking, by PK (§12: booking_id is the primary key). A booking that
--     somehow leaves and re-enters the pre-custody states after its check-in resolved does
--     not get a second one; the only regression edge (confirmed → matching) is a club-only
--     RPC ([R3] 0047) and club rows never enter this protocol.
--   · The resolver NEVER writes money. §4.2's "runner compensated / owner fee" arms are NOT
--     in the §12 matrix and are deliberately not built here — money beyond the §9 carve-out
--     is a policy Sean has not ruled (announcer stop-condition; recorded in the build report).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ═══ §1 the two knobs — injectable for the harness, literal defaults are the ruling ═══════
-- current_setting(…, true) returns NULL when the GUC is unset, so production always runs on
-- the literals (a GUC is session-scoped; the cron's fresh session can never inherit one).
-- The harness injects with set_config('app.late_grace', '0 seconds', true) inside a do-block
-- and the override dies with the transaction. Same shape as charge_max_attempts (0116 §C):
-- a policy number named once, in SQL, where a pin can hold it.
create or replace function late_grace() returns interval
language sql stable set search_path = public, pg_temp as
$$ select coalesce(nullif(current_setting('app.late_grace', true), '')::interval,
                   interval '30 minutes') $$;   -- Sean 2026-08-21: "grace 30"

create or replace function late_ceiling() returns interval
language sql stable set search_path = public, pg_temp as
$$ select coalesce(nullif(current_setting('app.late_ceiling', true), '')::interval,
                   interval '3 hours') $$;      -- Sean 2026-08-21: "ceiling 3 hours"

-- THE single copy of the ceiling arithmetic. The sweep's arm ⓑ, arm ⓒ's negation, the
-- 'proceeding' answer gate, the renewal bound and the §9 fee carve-out all call THIS —
-- never `scheduled_at + interval '3 hours'` open-coded.
create or replace function late_ceiling_at(p_scheduled timestamptz) returns timestamptz
language sql stable set search_path = public, pg_temp as
$$ select p_scheduled + late_ceiling() $$;

revoke execute on function late_grace()                   from public, anon, authenticated;
revoke execute on function late_ceiling()                 from public, anon, authenticated;
revoke execute on function late_ceiling_at(timestamptz)   from public, anon, authenticated;
grant  execute on function late_grace()                   to service_role;
grant  execute on function late_ceiling()                 to service_role;
grant  execute on function late_ceiling_at(timestamptz)   to service_role;
-- service_role holds EXECUTE because marketplace_cancel_fee (§9) is an INVOKER sql function
-- called over RPC by transition-booking as service_role, and its en-route arm reaches these.
-- Clients get the derived facts through fetch_checkin (§7), never the knobs.

comment on function late_grace() is
  '0117 §1: scheduled_at + grace = the moment the check-in clock fires (Sean 2026-08-21: 30
minutes). Also the answer window and the both-proceeding renewal window — one knob on purpose:
the ruling named two numbers and this file introduces no third. GUC app.late_grace overrides
for the harness only; production runs the literal.';
comment on function late_ceiling() is
  '0117 §1: maximum lateness (Sean 2026-08-21: 3 hours). Past scheduled_at + ceiling the
check-in stops offering "proceed" (plan §4.3, FM4) and the sweep resolves the booking to its
no-fee terminal. NEVER money — 0068 retired timer-driven money and this file cites it as law.';

-- ═══ §2 booking_checkins — the §12 table, column for column ═══════════════════════════════
-- Type name: house convention is <noun>_<noun> (booking_status, claim_status…); the contract
-- writes the domain as `answer := proceeding | cannot_proceed | other_side_absent` and the
-- values are implemented verbatim.
create type checkin_answer as enum ('proceeding', 'cannot_proceed', 'other_side_absent');

create table booking_checkins (
  booking_id    uuid primary key references bookings,
  opened_at     timestamptz not null default now(),  -- when the clock fired
  deadline_at   timestamptz not null,                -- BOUNDED (FM3 dies here): always
                                                     -- least(open/answer + grace, ceiling_at)
  owner_answer  checkin_answer,                      -- null = unanswered ≠ answered-no
  owner_at      timestamptz,                         -- SERVER clock, never client (§6)
  owner_reason  text,                                -- only with cannot_proceed (header note);
                                                     -- nullable — the surface asks, never mandates
  runner_answer checkin_answer,
  runner_at     timestamptz,
  runner_reason text,
  resolved_at   timestamptz,                         -- CAS target (§5)
  resolution    text,                                -- 'cannot_proceed' | 'void' | 'ceiling'
                                                     --  | 'superseded' (§5 header)
  version       int not null default 0,              -- optimistic lock; +1 per mutation
  -- answers and their stamps travel together, both directions:
  constraint checkin_owner_stamp  check ((owner_answer  is null) = (owner_at  is null)),
  constraint checkin_runner_stamp check ((runner_answer is null) = (runner_at is null)),
  -- a reason exists only on a cannot_proceed statement — table-level belt under the §6 gate
  constraint checkin_owner_reason  check (owner_reason  is null or owner_answer  = 'cannot_proceed'),
  constraint checkin_runner_reason check (runner_reason is null or runner_answer = 'cannot_proceed'),
  constraint checkin_resolution_pair check ((resolved_at is null) = (resolution is null))
);

alter table booking_checkins enable row level security;
-- SEALED — RLS on, zero policies (ops_flags' idiom, 0080 §C): no client role reads or writes
-- the table directly. The §12 surface is exactly three calls: open_checkin (cron),
-- answer_checkin and fetch_checkin (definer functions below). The security sweeps that audit
-- rls-off tables (REGISTRY ①) and grant/protection splits (REGISTRY ③) both see this shape.

comment on table booking_checkins is
  '0117 §2 (plan §12 contract): the two-sided late-booking check-in. One row per booking (PK).
Per-side answers are IMMUTABLE (guard trigger below — first write wins), timestamps are the
server''s, resolution is written once through a CAS on (resolved_at, version) with
bookings.status re-read under the same lock (FM6). SEALED: RLS on, zero policies — the only
surface is open_checkin / answer_checkin / fetch_checkin.';
comment on column booking_checkins.deadline_at is
  '0117: bounded, always. Initial = least(opened_at + grace, ceiling_at); a both-proceeding
renewal = least(now() + grace, ceiling_at). The deadline sweep NEVER renews — renewal happens
only on the answer path, and answers are immutable, so FM3 ("both confirm then vanish")
terminates at this timestamp instead of rotting.';
comment on column booking_checkins.resolution is
  '0117 §5: cause token, terminal lives on bookings.status. cannot_proceed = a side''s own
statement (fault recorded, D5-compatible) · void = deadline passed with no fault statement
(silence/one-sided claims/mixed — no fee, no fault, D5) · ceiling = maximum lateness
self-resolution (no fee, no fault, 0068''s law) · superseded = booking left the protocol''s
states by another path (cancel/complete/club regression) — checkin closes, nothing written.';

-- The IMMUTABILITY guard — the contract's words enforced at the table so that no future
-- writer (service_role included; triggers do not care about BYPASSRLS) can retract an answer,
-- move a server timestamp, re-resolve a resolved check-in, or reuse a version.
create or replace function _booking_checkins_guard() returns trigger
language plpgsql as $$
begin
  if new.booking_id is distinct from old.booking_id
     or new.opened_at is distinct from old.opened_at then
    raise exception 'checkin_immutable';
  end if;
  if old.owner_answer is not null and
     (new.owner_answer is distinct from old.owner_answer
      or new.owner_at is distinct from old.owner_at
      or new.owner_reason is distinct from old.owner_reason) then
    raise exception 'checkin_answer_immutable';
  end if;
  if old.runner_answer is not null and
     (new.runner_answer is distinct from old.runner_answer
      or new.runner_at is distinct from old.runner_at
      or new.runner_reason is distinct from old.runner_reason) then
    raise exception 'checkin_answer_immutable';
  end if;
  if old.resolved_at is not null and
     (new.resolved_at is distinct from old.resolved_at
      or new.resolution is distinct from old.resolution
      or new.deadline_at is distinct from old.deadline_at) then
    raise exception 'checkin_resolution_immutable';
  end if;
  -- every real mutation is exactly one optimistic-lock step; a stale writer whose version
  -- arithmetic is off is refused rather than silently interleaved.
  if new.version is distinct from old.version + 1 then
    raise exception 'checkin_version_step';
  end if;
  return new;
end $$;

create trigger booking_checkins_guard
  before update on booking_checkins
  for each row execute function _booking_checkins_guard();

-- ═══ §3 booking_faults — D4's output, D5's constraint ═════════════════════════════════════
create table booking_faults (
  id         uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings,
  party      text not null check (party in ('owner', 'runner')),
  source     text not null,               -- 'checkin_cannot_proceed' from §5; future human
                                          -- writers (ops adjudication) name their own source
  stated_by  uuid not null references profiles,  -- D5 AS A CONSTRAINT: no human, no fault row.
                                          -- The resolver only ever writes the side's own id —
                                          -- fault here is SELF-stated ('cannot_proceed'); an
                                          -- accusation (other_side_absent) never lands here.
  reason     text,                        -- the stater's own words, COPIED from the check-in
                                          -- at resolution (header note: emergency vs flake).
                                          -- Nullable — the surface asks, never mandates.
  detail     text,
  created_at timestamptz not null default now(),
  unique (booking_id, party)
);

alter table booking_faults enable row level security;

-- A fault row is a recorded human statement: write-once, whole row. Corrections are a future
-- ops process writing its own sourced record — never an edit that changes what someone said.
create or replace function _booking_faults_guard() returns trigger
language plpgsql as $$
begin
  raise exception 'fault_immutable';
end $$;

create trigger booking_faults_guard
  before update on booking_faults
  for each row execute function _booking_faults_guard();
-- SEALED like §2: no client surface. Money reads it through enroute_cancel_fee_waived (§9);
-- future settlement reads it server-side. Silence can never appear here (D5) because the only
-- writer records a party's own statement and stated_by refuses NULL structurally.

comment on table booking_faults is
  '0117 §3: fault persistence for the late-booking protocol (D4 "money follows fault").
stated_by NOT NULL = D5 as schema: every row traces to a human statement. The §5 resolver
writes party = the side that answered cannot_proceed, stated_by = that side''s own profile —
never the accused, never the silent. Read today by the §9 fee carve-out; unique(booking,party)
keeps a retried resolver idempotent.';

-- ═══ §4 open_checkin — cron only ══════════════════════════════════════════════════════════
create or replace function open_checkin(p_booking uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; v_ins uuid;
begin
  select bk.id, bk.status::text as status, bk.scheduled_at, bk.owner_id, bk.runner_id,
         bk.club_session_id
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;
  -- the protocol is pre-custody by definition (D3): past the handoff the run-end machinery
  -- owns the clock, and a terminal/matching booking has nothing to check in about.
  if b.status not in ('confirmed', 'runner_enroute') then raise exception 'not_late_eligible'; end if;
  if b.scheduled_at + late_grace() > now() then raise exception 'not_past_grace'; end if;
  -- past the ceiling the check-in must not open at all — §4.3: only terminals remain, and
  -- the sweep's arm ⓑ owns that resolution.
  if late_ceiling_at(b.scheduled_at) <= now() then raise exception 'past_ceiling'; end if;

  insert into booking_checkins (booking_id, opened_at, deadline_at)
  values (p_booking, now(), least(now() + late_grace(), late_ceiling_at(b.scheduled_at)))
  on conflict (booking_id) do nothing
  returning booking_id into v_ins;

  -- FM2 doctrine: the prompt's PRIMARY surface is state-derived (stage 1 renders off
  -- fetch_checkin/lateness state on resume); this notification is the alert fallback, sent
  -- once, only when the row was actually created — push is demoted, never load-bearing.
  if v_ins is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    select p.profile_id, 'booking', '예약 시간이 지났어요',
           '진행할지 함께 확인이 필요해요 — 앱에서 응답해 주세요', p_booking
    from (values (b.owner_id), (b.runner_id)) as p(profile_id)
    where p.profile_id is not null;
  end if;
end $$;

revoke execute on function open_checkin(uuid) from public, anon, authenticated, service_role;
-- §12: "open_checkin(booking) — cron only." Nobody holds EXECUTE; the sweep runs as the cron
-- job owner (postgres) and reaches it as function owner. Deliberately NOT granted to
-- service_role: an edge function that could open check-ins would be a second clock.

comment on function open_checkin is
  '0117 §4 (§12): cron-only. Opens the two-sided check-in for a pre-custody marketplace
booking past grace and under the ceiling; bounded deadline = least(now()+grace, ceiling_at);
idempotent on the PK; alerts both parties once (FM2: alert is fallback, state-derived surface
is primary). No client and no service_role EXECUTE.';

-- ═══ §5 _resolve_checkin — THE resolver ═══════════════════════════════════════════════════
-- One transaction. Lock order is bookings FIRST, checkin second — the same order as
-- confirm_return_tx (0083 §6, 0096 §2), which shares this custody path; a reversed order here
-- would be a deadlock with every return-confirm racing a deadline tick.
--
-- The §12 matrix, restated as the arms below (custody re-read UNDER the bookings lock, FM6):
--   inputs                        pre-custody                      post-custody
--   both 'proceeding'             renew bounded deadline (answer   same (answer path);
--                                 path); at an EXPIRED deadline    at an expired deadline the
--                                 the run never started → void     run DID start → superseded
--   either 'cannot_proceed'       no_show + fault = that side      incident_review + fault =
--                                                                  that side (the terminal
--                                                                  cell differs, the fault
--                                                                  semantics are the row's)
--   one 'other_side_absent',      void — no fee, no fault (D5:     incident_review — no fault
--   other silent (at deadline)    an accusation plus silence       (a dog was handed over and
--                                 charges no one)                  the protocol went dark —
--   both silent (at deadline)     void — no fee, no fault          alarming, D1)
--
-- Combinations §12 does not enumerate (proceeding+silent, proceeding+other_side_absent,
-- both other_side_absent) resolve at the deadline by D5's own principle — no self-stated
-- fault ⇒ no fault, not both-proceeding ⇒ no renewal ⇒ the no-fee void/incident_review
-- terminal. That is a completion of the matrix from the doc's rulings, not a new policy:
-- fault only ever comes from a side's own 'cannot_proceed'; silence and accusations never
-- charge and never blame (plan §4.2's catch-all arm).
--
-- 'superseded': the status re-read shows the booking left the protocol's states (cancelled,
-- completed, refund_pending, expired, no_show/incident_review by another hand, or a club-RPC
-- regression to matching). The checkin closes; the resolver touches neither status nor money
-- nor fault — the concurrent path already owned the outcome (FM8: offered actions expire
-- with the check-in).
create or replace function _resolve_checkin(p_booking uuid, p_cause text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; c record;
  v_custody text; v_resolution text; v_terminal text;
  v_any_cannot boolean; v_both_proceed boolean;
begin
  if p_cause not in ('answer', 'deadline', 'ceiling') then raise exception 'bad_cause'; end if;

  select bk.id, bk.status::text as status, bk.scheduled_at, bk.owner_id, bk.runner_id,
         bk.club_session_id
    into b
  from bookings bk where bk.id = p_booking for update;              -- ① bookings lock
  if b.id is null then raise exception 'not_found'; end if;

  select * into c from booking_checkins bc
   where bc.booking_id = p_booking for update;                      -- ② checkin lock

  if c.booking_id is null then
    if p_cause = 'ceiling' then
      -- a booking that predates the protocol (the 2026-08-04 row's shape: runner_enroute,
      -- 17 days stale, no checkin ever opened). The resolution still gets a row — the table
      -- is the protocol's ledger and a status flip with no record is the old rot in new
      -- clothes. opened_at = deadline_at = now(): the clock fired and expired in one breath.
      insert into booking_checkins (booking_id, opened_at, deadline_at)
      values (p_booking, now(), now());
      select * into c from booking_checkins bc
       where bc.booking_id = p_booking for update;
    else
      raise exception 'checkin_not_open';
    end if;
  end if;

  if c.resolved_at is not null then return; end if;   -- already resolved — back off silently
                                                      -- (the CAS below is the second belt)

  -- custody re-read under the lock (FM6) — the terminal is chosen by where the dog is NOW,
  -- not by where it was when the clock fired. D3: no_show is pre-custody vocabulary only;
  -- past the handoff the honest terminal is incident_review, and enforce_booking_transition
  -- (0066 §1) refuses picked_up/active → no_show as the trigger-level belt.
  v_custody := case
    when b.club_session_id is not null                  then 'out'   -- belt; §4 refuses entry
    when b.status in ('confirmed', 'runner_enroute')    then 'pre'
    when b.status in ('picked_up', 'active')            then 'post'
    else 'out'
  end;

  v_any_cannot   := c.owner_answer = 'cannot_proceed' or c.runner_answer = 'cannot_proceed';
  v_both_proceed := c.owner_answer = 'proceeding' and c.runner_answer = 'proceeding';

  if v_custody = 'out' then
    v_resolution := 'superseded';
  elsif p_cause = 'ceiling' then
    if v_custody = 'pre' then v_resolution := 'ceiling'; v_terminal := 'no_show';
    else v_resolution := 'superseded';                  -- picked up while the arm ran: started
    end if;
  elsif v_any_cannot then
    v_resolution := 'cannot_proceed';
    v_terminal   := case v_custody when 'pre' then 'no_show' else 'incident_review' end;
  elsif v_both_proceed then
    if p_cause = 'answer' then
      -- the renewal — bounded (FM3), one effective shot: answers are immutable, so no third
      -- answer can ever re-enter this arm, and the deadline sweep below NEVER renews.
      -- The 'proceeding' ceiling gate in §6 guarantees now() < ceiling_at here.
      update booking_checkins
         set deadline_at = least(now() + late_grace(), late_ceiling_at(b.scheduled_at)),
             version     = c.version + 1
       where booking_id = p_booking and resolved_at is null and version = c.version;
      return;
    end if;
    -- deadline expired after both said proceeding:
    if v_custody = 'pre' then v_resolution := 'void'; v_terminal := 'no_show';
      -- FM3's second watchdog: they confirmed, then nothing started. No fault, no fee — a
      -- 'proceeding' that never materialised is still not a statement of fault (D5).
    else v_resolution := 'superseded';                  -- the run DID start; run-end owns it
    end if;
  else
    -- silence / one-sided claims / mixed — only the deadline may resolve these (D5: the
    -- silent side keeps the whole window; an early answer is never a verdict on them).
    if p_cause = 'answer' then return; end if;
    v_resolution := 'void';
    v_terminal   := case v_custody when 'pre' then 'no_show' else 'incident_review' end;
  end if;

  -- ─── the CAS, §12 verbatim: (resolved_at, version) ───────────────────────────────────────
  -- Belt over the row lock held above — and the whole protection the moment any future caller
  -- reaches this row without taking the lock first.
  update booking_checkins
     set resolved_at = now(), resolution = v_resolution, version = c.version + 1
   where booking_id = p_booking and resolved_at is null and version = c.version;
  if not found then return; end if;                     -- lost the CAS — the winner owns it

  -- ─── fault — D5: only a side's own statement, only their own name ────────────────────────
  if v_resolution = 'cannot_proceed' then
    if c.owner_answer = 'cannot_proceed' then
      insert into booking_faults (booking_id, party, source, stated_by, reason)
      values (p_booking, 'owner', 'checkin_cannot_proceed', b.owner_id, c.owner_reason)
      on conflict (booking_id, party) do nothing;
    end if;
    if c.runner_answer = 'cannot_proceed' then
      insert into booking_faults (booking_id, party, source, stated_by, reason)
      values (p_booking, 'runner', 'checkin_cannot_proceed', b.runner_id, c.runner_reason)
      on conflict (booking_id, party) do nothing;
    end if;
  end if;

  -- ─── the terminal — a STATUS, never money (0068's law; the file header owns the argument).
  -- enforce_booking_transition validates the edge (confirmed/runner_enroute → no_show,
  -- picked_up/active → incident_review are all in 0066 §1's map).
  if v_terminal is not null then
    update bookings set status = v_terminal::booking_status where id = p_booking;

    insert into notifications (profile_id, kind, title, body, ref_id)
    select p.profile_id,
           case when v_terminal = 'incident_review' then 'safety' else 'booking' end::noti_kind,
           case when v_terminal = 'incident_review' then '확인이 필요해요'
                else '지연 예약이 정리됐어요' end,
           case
             when v_terminal = 'incident_review'
               then '지연 체크인이 해소되지 않아 케이스 검토로 전환됐어요 — 강아지 상태를 확인해 주세요'
             when v_resolution = 'cannot_proceed'
               then '체크인 응답에 따라 예약이 불발로 종결됐어요 — 수수료는 청구되지 않았어요'
             else '응답이 확인되지 않아 예약이 수수료 없이 종결됐어요 — 다시 예약할 수 있어요'
           end,
           p_booking
    from (values (b.owner_id), (b.runner_id)) as p(profile_id)
    where p.profile_id is not null;
  end if;
end $$;

revoke execute on function _resolve_checkin(uuid, text) from public, anon, authenticated, service_role;
-- internal: reached only through answer_checkin and the sweep (both run as owner).

comment on function _resolve_checkin is
  '0117 §5 (§12): the transactional resolver — bookings locked first (confirm_return_tx''s
order), status re-read under that lock (FM6), resolution written once through the
(resolved_at, version) CAS. Fault only from a side''s own cannot_proceed (D5); silence,
accusations and expired proceedings resolve to no-fee terminals; ceiling resolutions cite
0068 — a timer may flip status, never money. superseded = another path owned the outcome.';

-- ═══ §6 answer_checkin ════════════════════════════════════════════════════════════════════
create or replace function answer_checkin(p_booking uuid, p_side text, p_answer text,
                                          p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; c record; v_uid uuid := auth.uid(); v_now timestamptz := now();
begin
  if p_side not in ('runner', 'owner') then raise exception 'bad_side'; end if;
  if p_answer not in ('proceeding', 'cannot_proceed', 'other_side_absent') then
    raise exception 'bad_answer';
  end if;
  -- a reason rides ONLY a cannot_proceed statement (header note — Sean: "ask why they
  -- stopped."). On any other answer it would be a free-text channel on a happy path, the
  -- abuse class 0114 closed elsewhere.
  if p_reason is not null and p_answer <> 'cannot_proceed' then
    raise exception 'reason_not_applicable';
  end if;

  select bk.id, bk.status::text as status, bk.scheduled_at, bk.owner_id, bk.runner_id,
         bk.club_session_id
    into b
  from bookings bk where bk.id = p_booking for update;              -- lock order: bookings ①
  if b.id is null then raise exception 'not_found'; end if;

  -- party gate before state gate (0083/0096's order, verbatim idiom).
  if v_uid is not null then
    if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
    if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  select * into c from booking_checkins bc
   where bc.booking_id = p_booking for update;                      -- checkin ②
  if c.booking_id is null then raise exception 'checkin_not_open'; end if;

  -- idempotent on replay (§12): the SAME side re-sending the SAME answer is the same tap —
  -- answered state returned, nothing rewritten, server timestamp untouched.
  if (p_side = 'owner'  and c.owner_answer  = p_answer::checkin_answer)
  or (p_side = 'runner' and c.runner_answer = p_answer::checkin_answer) then
    return fetch_checkin(p_booking);
  end if;

  -- resolved check-ins take no further answers (FM8: offered actions expire with the
  -- check-in; a late response never retracts a resolution).
  if c.resolved_at is not null then raise exception 'checkin_resolved'; end if;

  -- per-side IMMUTABLE, first write wins (§12): a different second answer is refused, not
  -- merged, not overwritten.
  if (p_side = 'owner' and c.owner_answer is not null)
  or (p_side = 'runner' and c.runner_answer is not null) then
    raise exception 'answer_immutable';
  end if;

  -- §4.3 / FM4: past the ceiling the protocol offers only terminals. Two taps must not
  -- resurrect a 17-day-old booking — the server refuses 'proceeding' even if a stale client
  -- still renders the button. Statements toward a terminal remain accepted.
  if p_answer = 'proceeding' and late_ceiling_at(b.scheduled_at) <= now() then
    raise exception 'checkin_past_ceiling';
  end if;

  -- SERVER timestamps only (§12): v_now is this transaction's clock; no client value exists
  -- in this signature at all.
  -- the reason writes in the SAME statement as the answer and is immutable with it (guard
  -- trigger arm). A replay of the same answer with a different reason is answered by the
  -- idempotence branch above: first write wins, the late reason is ignored, nothing moves.
  if p_side = 'owner' then
    update booking_checkins
       set owner_answer = p_answer::checkin_answer, owner_at = v_now, owner_reason = p_reason,
           version = c.version + 1
     where booking_id = p_booking and resolved_at is null and version = c.version;
  else
    update booking_checkins
       set runner_answer = p_answer::checkin_answer, runner_at = v_now, runner_reason = p_reason,
           version = c.version + 1
     where booking_id = p_booking and resolved_at is null and version = c.version;
  end if;
  if not found then raise exception 'checkin_conflict'; end if;   -- unreachable under the row
                                                                  -- lock; belt for lock-free
                                                                  -- future callers
  perform _resolve_checkin(p_booking, 'answer');
  return fetch_checkin(p_booking);
end $$;

revoke execute on function answer_checkin(uuid, text, text, text) from public, anon;
grant  execute on function answer_checkin(uuid, text, text, text) to authenticated, service_role;

comment on function answer_checkin is
  '0117 §6 (§12): per-side check-in answer — party-gated, first write wins, immutable,
idempotent on replay, server timestamps only, ''proceeding'' refused past the ceiling (FM4).
Resolves in the same transaction when the answer decides (cannot_proceed → terminal + fault;
second proceeding → bounded renewal).';

-- ═══ §7 fetch_checkin — what the surface renders ══════════════════════════════════════════
create or replace function fetch_checkin(p_booking uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; c record; v_uid uuid := auth.uid();
begin
  select bk.id, bk.status::text as status, bk.scheduled_at, bk.owner_id, bk.runner_id,
         bk.club_session_id
    into b
  from bookings bk where bk.id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;

  if v_uid is not null then
    if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
      raise exception 'not_party';
    end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  select * into c from booking_checkins bc where bc.booking_id = p_booking;
  if c.booking_id is null then
    -- No protocol row is the NORMAL state of every booking that predates the protocol — the
    -- 2026-08-04 shape, which §9 waives on scheduled_at alone. A bare {open:false} here would
    -- strand the client's fee-quote mirror without past_ceiling or server_now, forcing it
    -- back onto a client clock — exactly what FM2/FM6 refuse to trust. The booking row is
    -- already loaded; the derived trio costs nothing and lies to no one.
    return jsonb_build_object(
      'open',         false,
      'past_ceiling', late_ceiling_at(b.scheduled_at) <= now(),
      'custody',      case when b.status in ('picked_up', 'active') then 'post' else 'pre' end,
      'server_now',   now());
  end if;

  return jsonb_build_object(
    'open',          c.resolved_at is null,
    'opened_at',     c.opened_at,
    'deadline_at',   c.deadline_at,
    'owner_answer',  c.owner_answer,
    'owner_at',      c.owner_at,
    'owner_reason',  c.owner_reason,
    'runner_answer', c.runner_answer,
    'runner_at',     c.runner_at,
    'runner_reason', c.runner_reason,
    'resolved_at',   c.resolved_at,
    'resolution',    c.resolution,
    'version',       c.version,
    -- the surface must not derive these: the ceiling constant lives server-side only, and a
    -- client clock is exactly what FM2/FM6 refuse to trust.
    'past_ceiling',  late_ceiling_at(b.scheduled_at) <= now(),
    'custody',       case when b.status in ('picked_up', 'active') then 'post' else 'pre' end,
    'server_now',    now());
end $$;

revoke execute on function fetch_checkin(uuid) from public, anon;
grant  execute on function fetch_checkin(uuid) to authenticated, service_role;

comment on function fetch_checkin is
  '0117 §7 (§12): the render read — party-gated; {open:false} before the clock fires; carries
past_ceiling (so the client can stop offering "proceed" without knowing the constant) and
server_now (so no countdown trusts a phone clock).';

-- ═══ §8 the sweep + its cron tick ═════════════════════════════════════════════════════════
-- 0060:145 stagger doctrine: every mod-5 minute offset is taken (0=expire-unmatched,
-- 1=purge-holds, 2=sweep-settled-charges, 3=sweep-payment-intents, 4=dispatch-due-charges),
-- so ANY new tick shares a minute with someone — the doctrine's own precedent
-- (run-end-recovery, 8-58/10, TODOS.md P3 note) picked the coarser */10 cadence sharing the
-- mod-5 family of `sweep-payment-intents`, the one 5-minute batch touching neither `bookings`
-- nor `runs`. This sweep DOES touch bookings, so it takes the same family's other half:
-- 3-53/10 — colliding minutes only with the payments-intents sweep (disjoint tables, no lock
-- contention) and never with expire-unmatched or expire-reschedules, the two bookings-writers.
-- Grace is 30 minutes; a ≤10-minute detection lag is inside the design (the deadline, not the
-- tick, is the contract).
-- Per-row exception isolation in every arm, because this repo has already paid for the
-- alternative twice: 0116 §C ("one poisoned row fails ITS OWN ROW, never the batch") and
-- 0111's generate_recurring_bookings ("continue + raise warning, never raise — one row would
-- abort the whole hourly sweep forever"). A booking whose state surprises the resolver must
-- not stop the clock for every other late booking.
create or replace function late_booking_sweep() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  -- ⓐ expired check-ins → the resolver (deadline rules; renewals never happen here)
  for r in
    select bc.booking_id from booking_checkins bc
    where bc.resolved_at is null and bc.deadline_at <= now()
  loop
    begin
      perform _resolve_checkin(r.booking_id, 'deadline');
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep deadline % : %', r.booking_id, sqlerrm;
    end;
  end loop;

  -- ⓑ the ceiling: pre-custody marketplace bookings past maximum lateness — WITH or WITHOUT
  -- a check-in row (the without case is every booking that predates the protocol, the
  -- 2026-08-04 row first among them). Resolution is a STATUS and a record, never money
  -- (0068 — see the file header). Already-resolved check-ins are excluded so a closed
  -- protocol is never re-entered.
  for r in
    select b.id from bookings b
    where b.status in ('confirmed', 'runner_enroute')
      and b.club_session_id is null
      and late_ceiling_at(b.scheduled_at) <= now()
      and not exists (select 1 from booking_checkins bc
                      where bc.booking_id = b.id and bc.resolved_at is not null)
  loop
    begin
      perform _resolve_checkin(r.id, 'ceiling');
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep ceiling % : %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓒ arm the protocol: pre-custody marketplace bookings past grace, under the ceiling,
  -- no protocol row yet.
  for r in
    select b.id from bookings b
    where b.status in ('confirmed', 'runner_enroute')
      and b.club_session_id is null
      and b.scheduled_at + late_grace() <= now()
      and late_ceiling_at(b.scheduled_at) > now()
      and not exists (select 1 from booking_checkins bc where bc.booking_id = b.id)
  loop
    begin
      perform open_checkin(r.id);
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep open % : %', r.id, sqlerrm;
    end;
  end loop;

  return n;
end $$;

revoke execute on function late_booking_sweep() from public, anon, authenticated, service_role;
-- cron-only, like open_checkin: the clock has exactly one hand.

comment on function late_booking_sweep is
  '0117 §8: the late-booking clock — ⓐ resolve expired check-ins ⓑ ceiling-resolve rotted
pre-custody bookings (status only, never money — 0068) ⓒ open check-ins past grace. Club
excluded throughout; */10 on the sweep-payment-intents mod-5 family per 0060:145 (the one
5-minute batch touching neither bookings nor runs).';

-- 0017/0060's guarded form: the local harness has no pg_cron and must still apply cleanly.
do $$ begin
  perform cron.schedule('late-booking-sweep', '3-53/10 * * * *', 'select late_booking_sweep()');
exception when others then
  raise notice 'pg_cron unavailable — late_booking_sweep() 를 외부 스케줄러로 호출하세요';
end $$;

-- ═══ §9 the 0066 carve-out — money follows fault (D4), and the ceiling is a fact ══════════
-- FM7 named the injustice: "owner charged the 50% en-route arm for a runner's failure."
-- 0066's arm prices ONE thing — an owner walking away from a runner who is actually coming.
-- Two states falsify that story, and both are now knowable:
--   · a booking_faults row naming the RUNNER (their own recorded statement — D5-clean). Today
--     the §5 resolver writes fault only together with a terminal, so a cancellable en-route
--     booking with a runner fault is not producible by this file alone — the arm is
--     defense-in-depth for the fault table's future human writers (ops adjudication), and the
--     predicate is specified against the STATE, not against today's writers.
--   · the ceiling has passed (late_ceiling_at ≤ now()): the departure story is dead no matter
--     what was or wasn't recorded. THIS is the honest fallback for every booking that
--     predates the protocol — it needs no checkin row and no fault row, only scheduled_at,
--     so the 2026-08-04 row (runner_enroute, 17 days stale) quotes 0 the moment this file
--     lands, sweep or no sweep.
-- Fee 0 also zeroes the runner's compensation automatically: record_enroute_cancel_comp
-- (0080 §K) reads bookings.cancel_fee and refuses fee ≤ 0 — no second rule needed, and none
-- added (the comp writers are NOT touched).
create or replace function enroute_cancel_fee_waived(p_booking uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from booking_faults f
                 where f.booking_id = p_booking and f.party = 'runner')
      or exists (select 1 from bookings b
                 where b.id = p_booking and late_ceiling_at(b.scheduled_at) <= now())
$$;

revoke execute on function enroute_cancel_fee_waived(uuid) from public, anon, authenticated;
grant  execute on function enroute_cancel_fee_waived(uuid) to service_role;

comment on function enroute_cancel_fee_waived is
  '0117 §9: THE carve-out predicate, one copy — the en-route 50% owner-cancel fee is waived
when a recorded fault names the runner (D4/D5: their own statement) OR the lateness ceiling
has passed (the honest fallback for pre-protocol bookings — scheduled_at is all it needs).
Fee 0 flows to the comp writers by their own fee<=0 guards; nothing else changes.';

-- ── marketplace_cancel_fee — EXTENDS ←0066 (REGISTRY silent-collision law) ─────────────────
-- Base named: 0066 §2 is both the first and the newest definition (verified by grep across
-- migrations; 0085's header explicitly leaves it as 0066 wrote it). Everything below is
-- byte-faithful to 0066 except the runner_enroute arm, which now consults the §9 waiver.
-- The ladder's other tiers are deliberately untouched: the carve-out Sean ruled is about the
-- en-route arm; whether the <24h 10% tier should also be ceiling-aware is an open product
-- question recorded in the build report, not decided here.
create or replace function marketplace_cancel_fee(p_booking uuid)
returns table (fee int, status text)
language sql stable
set search_path = public, pg_temp
as $$
  select
    case
      when b.runner_id is null or b.status in ('matching', 'runner_pending') then 0
      -- [0117 §9] the en-route arm keeps 0066's 50% (runner compensation, Sean 2026-08-11)
      -- for a live departure, and charges 0 where the departure story is falsified — a
      -- recorded runner fault or a booking past the lateness ceiling (Sean 2026-08-21).
      when b.status = 'runner_enroute' then
        case when enroute_cancel_fee_waived(b.id) then 0
             else round(b.total_price * 0.5)::int end
      when b.scheduled_at >= now() + interval '24 hours' then 0
      else round(b.total_price * 0.1)::int
    end,
    b.status::text
  from bookings b
  where b.id = p_booking
$$;

-- The LADDER stays server-only (re-stated from 0066; create or replace preserves ACLs) —
-- but 0066:89's posture "NOT a client quote API — client copy states the policy in words"
-- was KNOWINGLY REVERSED by Sean on 2026-08-21 (structured choice: "Real quote API + words
-- meanwhile"): clients now read the number through quote_cancel_fee below, a party-gated
-- window onto this one function. The reversal exists because the client's mirror could not
-- see the fault half of the §9 waiver (booking_faults is sealed), and Sean chose reading
-- over mirroring. Direct EXECUTE on the ladder itself remains service_role-only.
revoke execute on function marketplace_cancel_fee(uuid) from public, anon, authenticated;
grant execute on function marketplace_cancel_fee(uuid) to service_role;

comment on function marketplace_cancel_fee is
  '0117 (base ←0066): owner-cancel fee ladder — unmatched 0 / runner_enroute 50% (runner
compensation, Sean 2026-08-11) WAIVED to 0 on recorded runner fault or past the lateness
ceiling (0117 §9, Sean 2026-08-21) / >=24h 0 / <24h 10%. Returns quoted status for the
caller''s CAS. Direct EXECUTE server-only (service_role); clients read the number through
quote_cancel_fee (0117 §9b — 0066:89''s no-client-quote posture reversed by Sean 2026-08-21).';

-- ── §9b quote_cancel_fee — the party-gated window (Sean 2026-08-21: "Real quote API + words
-- meanwhile") ──────────────────────────────────────────────────────────────────────────────
-- ONE fee implementation, by construction: this function CALLS marketplace_cancel_fee and
-- computes nothing itself (a rule copied N times is a rule you fix N-1 times — the quote is
-- a gate around the rule, never a second copy; suite 152 pins the delegation at the SOURCE
-- level, N8''s precedent, because a faithfully-copied ladder would pass every behavior pin
-- right up until the day the two copies drift). Party gate: owner or runner of the booking;
-- a FOREIGN booking answers not_found exactly like a MISSING one — a quote endpoint that
-- said not_party would be an enumeration oracle for valid booking ids. Null-uid server
-- callers pass (0096''s caller-class idiom).
create or replace function quote_cancel_fee(p_booking uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare b record; v_uid uuid := auth.uid(); v_fee int; v_status text;
begin
  select bk.id, bk.owner_id, bk.runner_id into b
  from bookings bk where bk.id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;
  if v_uid is not null then
    if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
      raise exception 'not_found';   -- indistinguishable from missing — no enumeration oracle
    end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  select f.fee, f.status into v_fee, v_status from marketplace_cancel_fee(p_booking) f;
  return jsonb_build_object('fee', v_fee, 'status', v_status);
end $$;

revoke execute on function quote_cancel_fee(uuid) from public, anon;
grant  execute on function quote_cancel_fee(uuid) to authenticated, service_role;

comment on function quote_cancel_fee is
  '0117 §9b (Sean 2026-08-21, reversing 0066:89''s no-client-quote posture): party-gated
read-only window onto marketplace_cancel_fee — THE number, one implementation, zero copies
(delegation pinned at source level). Foreign bookings answer not_found like missing ones (no
enumeration oracle). The client renders words for context from the returned status arm.';
