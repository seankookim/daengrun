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
-- ═══ DEPLOY EFFECTS — what changes the moment this file is pushed [codex r2 F8] ═══════════
-- Written because "it deploys inert" was said upward and was wrong. Only the CLOCK is behind
-- ops_flags.late_protocol_live_since; everything else is live on push.
--
-- ① LIVE AT PUSH, changes behavior immediately:
--    · `marketplace_cancel_fee` is REPLACED (§9). An en-route booking past the ceiling with no
--      arrival/handoff evidence now quotes 0 instead of 50%. Sean's 2026-08-04 row is the
--      known case; any other stale en-route row changes price the same way.
--    · The §9c trigger attaches: every marketplace transition into `cancelled_owner` that
--      carries a fee re-derives `cancel_fee` AND `cancel_reason` from the ladder. Stored
--      numbers and tier markers change for cancels whose quote was stale or wrong.
--    · `quote_cancel_fee` and `fetch_checkin` become callable by any authenticated party
--      (reads only). `answer_checkin` becomes callable — but it raises `checkin_not_open`
--      until a check-in row exists, and only the gated sweep creates one.
--    · The new tables and the fault/checkin guards exist. Nothing writes to them yet.
--    · 🔴 DEPLOY ORDER IS **MIGRATION FIRST, EDGE SECOND** — and an earlier version of this
--      block said edge-first was also safe, which was FALSE [blind review BLOCKER-4].
--      EDGE-FIRST IS UNSAFE: the new handler does not write `cancel_reason` (§9c owns it), so
--      with no trigger yet an en-route cancel stores the fee with reason NULL, the only
--      compensation writer is gated on that marker, and the runner is paid NOTHING.
--      MIGRATION-FIRST IS SAFE, and the refuse-and-requote rule above is what makes it so: the
--      old handler writes its own quoted fee and marker, and the trigger either agrees (the
--      write lands, marker re-derived identically) or REFUSES the transition (the owner gets a
--      409 re-quote instead of a wrong price). Both halves of the old handler's behaviour —
--      its response number and its share decision — are then correct by construction, because
--      the only writes that commit are the ones whose quote still matched.
--      Atomic is still better; when it cannot be atomic, this is the order.
--
-- ② WAITS FOR THE FLAG (`update ops_flags set late_protocol_live_since = now()`):
--    the sweep — arming check-ins, deadline resolutions, ceiling resolutions and every
--    booking-status write this protocol performs. While NULL the sweep returns 0 and no
--    booking changes status because of lateness. Flip it when ui5's stage-2 surface ships.
--
-- ③ UNREACHABLE WHILE CHARGING IS OFF (`payments_live_since` NULL): collection only —
--    `mint_cancel_fee_intent` writes nothing, so no card is touched. Stored fees, markers,
--    ledger comp rows and response copy are all REACHABLE — being uncollected is not the
--    same as being unwritten, and the runner's ledger row is money to a human either way.
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
--      server_now so the client neither derives the ceiling nor trusts its own clock). Each
--      party reads only their OWN reason text; the counterparty gets a boolean saying a reason
--      exists, never the words (ruling 4B — see the REASON note below).
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
--   ⚠ WHO MAY READ IT IS A SEPARATE QUESTION, AND ITS ANSWER IS "ONLY THE AUTHOR" (ruling 4B,
--   2026-08-24). Sean authorized ASKING and STORING; he was never asked whether the other side
--   gets to read the words, and the first draft of §7 handed both reasons to whichever party
--   called. A reason typed in the worst minute of a booking can carry a door code or a medical
--   emergency, it is written to two immutable tables and it survives account deletion — so the
--   disclosure would be permanent, and only the narrow reading is reversible later. §7 now
--   returns the caller's own text and a per-side BOOLEAN for both sides; the argument, the
--   naming and the key-absent-not-null choice are written at the return itself. `booking_faults`
--   needs no equivalent narrowing: its `reason` copy is read by nothing — `cancel_moves_no_money`
--   (§9) touches that table only through two `exists (…)` tests and selects no column from it,
--   and no other function, view or client path reads it (verified by grep across migrations,
--   edge functions and app/ on 2026-08-24). The table is also revoked from every role (§3), so
--   the copy is reachable only by a future reader that must decide this question for itself.
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
-- How long a torn cancellation is left alone before §9e repairs it. A knob for the same reason
-- the other two are: `t_bookings_touch` (0002:12) rewrites `bookings.updated_at` on every write,
-- so no fixture can age a row into the window — the harness injects instead.
create or replace function cancel_gap_grace() returns interval
language sql stable set search_path = public, pg_temp as
$$ select coalesce(nullif(current_setting('app.cancel_gap_grace', true), '')::interval,
                   interval '15 minutes') $$;
revoke execute on function cancel_gap_grace() from public, anon, authenticated;
grant  execute on function cancel_gap_grace() to service_role;

create or replace function late_ceiling_at(p_scheduled timestamptz) returns timestamptz
language sql stable set search_path = public, pg_temp as
$$ select p_scheduled + late_ceiling() $$;

-- [codex CRIT-3] ONE copy of the custody classification. The handoff STAMPS are the custody
-- fact and status is the fallback: the live handoff writes both stamps and promotes status in
-- a SEPARATE request, so a booking whose promotion write failed is still a dog in a runner's
-- hands — resolving it no_show would be D3's exact violation. Stamps count only while the
-- booking is still in a protocol-live state (a terminal row is 'out' regardless — another
-- path owned it). Both readers (the §5 resolver under its lock, §7 fetch) call THIS.
create or replace function _checkin_custody(p_status booking_status,
                                            p_owner_handoff timestamptz,
                                            p_runner_handoff timestamptz) returns text
language sql stable set search_path = public, pg_temp as $$
  select case
    when p_status in ('confirmed', 'runner_enroute', 'picked_up', 'active')
         and p_owner_handoff is not null and p_runner_handoff is not null then 'post'
    when p_status in ('confirmed', 'runner_enroute') then 'pre'
    when p_status in ('picked_up', 'active') then 'post'
    else 'out'
  end
$$;
revoke execute on function _checkin_custody(booking_status, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant  execute on function _checkin_custody(booking_status, timestamptz, timestamptz)
  to service_role;
-- ⚠ [R1, 2026-08-24 — this grant is LOAD-BEARING, do not "tidy" it back into the revoke above.]
-- The revoke line and this grant were one line apart and the grant was missing, which made every
-- marketplace owner cancel raise `permission denied for function _checkin_custody` the moment this
-- migration landed — before any flag, because §9d's trigger has no flag in its WHEN clause.
-- The chain: `_booking_cancel_custody_guard` (§9d) is plpgsql with NO `security definer`, so it
-- executes as the role running the statement; that role is service_role, because cancel_owner.ts
-- writes `bookings.status` with a plain `.update()` on the service-role client rather than through
-- a definer RPC. The other three callers (§5 resolver, §7 fetch_checkin ×2) are SECURITY DEFINER
-- and run as the owner, which is why only the INVOKER trigger broke and why nothing else noticed.
--
-- Granting is safe and is not a widening of the money surface: `_checkin_custody` is
-- `language sql stable` over its three ARGUMENTS and touches no table, so a caller learns nothing
-- it did not already hand in — and service_role holds bypassrls on `bookings` regardless. The
-- revoke from public/anon/authenticated stands and is what actually matters: clients must never
-- ask the internals where the dog is, they read the derived answer through fetch_checkin (§7).
-- Reproduced before fixing, under `set local role service_role`, with the edge's exact write.

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

-- [codex MEDIUM-10] immutability is a TABLE invariant, not a role posture: rows are never
-- deleted (bookings themselves survive account deletion — 0115 keeps them), and UPDATE/DELETE
-- are revoked below even from service_role, so the grants bind every non-owner writer and
-- the triggers bind the owner too. The one sanctioned UPDATE shape remains what the guard
-- already permits: answer/renewal/resolution writes with a version step — which is also the
-- suite's honest deadline-aging path (an unresolved row's deadline_at is renewal-writable by
-- design; aging it backward exercises production arithmetic, not a test backdoor).
create or replace function _booking_checkins_no_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'checkin_immutable';
end $$;

create trigger booking_checkins_no_delete
  before delete on booking_checkins
  for each row execute function _booking_checkins_no_delete();

revoke select, insert, update, delete, truncate on booking_checkins
  from anon, authenticated, service_role;   -- [MAJOR-11] SELECT too: nothing server-side reads
  -- these tables directly (the definer functions do, as owner), so a readable-by-service_role
  -- table is a standing copy of both parties' statements behind a key that lives in edge
  -- functions. What service_role MAY do with this protocol is exactly: call the party RPCs
  -- with a real JWT, and run `late_booking_sweep` as a scheduler fallback (§8).
  -- ⚠ INHERITED AND NOT FOUGHT HERE: service_role can still UPDATE `ops_flags`, so it can arm
  -- the late-protocol flag and then run the sweep it holds EXECUTE on. That reach is not new
  -- and not mine — every flag in that table has it (`payments_live_since` included, 0080 §C)
  -- — and NOTHING enforces "only a human flips it": the property is a convention, and 0084 §D
  -- deliberately shipped a guard that is advisory rather than a constraint. Said out loud
  -- rather than implied, because a reader could otherwise mistake the flag for a control.   -- [codex r2 F2] all four write verbs: the
  -- definer functions own every write, so no role needs table-level DML. Round 1 revoked
  -- only UPDATE/DELETE, which left service_role able to INSERT a fabricated check-in and
  -- TRUNCATE the protocol's ledger — the guards bind writers, the grants bind roles, and
  -- an immutability claim needs both.

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
  before update or delete on booking_faults
  for each row execute function _booking_faults_guard();

revoke select, insert, update, delete, truncate on booking_faults
  from anon, authenticated, service_role;   -- [MAJOR-11] as above, and more so: these rows are
  -- the human statements that money follows.   -- [codex r2 F2] same, and it matters more here:
  -- a fabricated fault row waives money (§9), and a TRUNCATE erases the statements that
  -- justify a waiver already granted.
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
-- CONFORMANCE RECORD (contract author, 2026-08-21): the §12 completions below were ruled
-- derived-not-invented and 'superseded' "an improvement the contract should have contained";
-- the post-custody fault reading (the stater's own row also written past the handoff) was
-- settled by stated_by NOT NULL's design and then by Sean's reason ruling the same day —
-- the fault row IS the human statement, custody only picks the terminal.
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
  v_any_cannot boolean; v_both_proceed boolean; v_backfill boolean := false;
  v_lot_ids uuid[]; v_lot_exp timestamptz[];
begin
  if p_cause not in ('answer', 'deadline', 'ceiling') then raise exception 'bad_cause'; end if;

  select bk.id, bk.status::text as status, bk.scheduled_at, bk.owner_id, bk.runner_id,
         bk.club_session_id, bk.owner_confirmed_handoff_at, bk.runner_confirmed_handoff_at
    into b
  from bookings bk where bk.id = p_booking for update;              -- ① bookings lock
  if b.id is null then raise exception 'not_found'; end if;

  select * into c from booking_checkins bc
   where bc.booking_id = p_booking for update;                      -- ② checkin lock

  if c.booking_id is null then
    if p_cause = 'ceiling' then
      -- [codex HIGH-9] a booking that predates the protocol (the 2026-08-04 row's shape:
      -- runner_enroute, 17 days stale, no checkin ever opened). The resolution still gets a
      -- row — the table is the protocol's ledger and a status flip with no record is the old
      -- rot in new clothes — but it resolves under its OWN cause ('ceiling_backfill', set
      -- below): opened_at = deadline_at = now() satisfies the columns, and the distinct
      -- cause is what says NO answer window ever existed — nobody may later read this row
      -- as a check-in the parties ignored. The sweep additionally requires the ceiling to be
      -- past by a full grace margin before creating one (arm ⓑ) — no third number invented.
      insert into booking_checkins (booking_id, opened_at, deadline_at)
      values (p_booking, now(), now());
      select * into c from booking_checkins bc
       where bc.booking_id = p_booking for update;
      v_backfill := true;
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
    when b.club_session_id is not null then 'out'                    -- belt; §4 refuses entry
    else _checkin_custody(b.status::booking_status,
                          b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at)
  end;

  -- ⚠ [blind r5 F6] A HANDOFF IN FLIGHT IS NOT A DEAD BOOKING. `_checkin_custody` reads state
  -- at ONE INSTANT, and the handoff is not one instant: the two stamps and the promotion to
  -- `picked_up` commit in SEPARATE requests (transition-booking/index.ts). So the clock could
  -- see exactly one stamp at 13:00:00, commit `no_show`, and the runner's in-flight request
  -- would then land the second stamp — leaving a durable `no_show` on a booking whose two
  -- humans had both confirmed the dog changed hands. ONE stamp means a handoff is HAPPENING;
  -- the clock steps aside and lets it finish (the next tick re-evaluates, and by then the
  -- promotion has either landed — post-custody — or the row is genuinely stale again).
  if p_cause in ('deadline', 'ceiling')
     and (b.owner_confirmed_handoff_at is not null or b.runner_confirmed_handoff_at is not null)
     and v_custody <> 'post' then
    update booking_checkins
       set resolved_at = now(), resolution = 'superseded', version = c.version + 1
     where booking_id = p_booking and resolved_at is null and version = c.version;
    return;
  end if;

  v_any_cannot   := c.owner_answer = 'cannot_proceed' or c.runner_answer = 'cannot_proceed';
  v_both_proceed := c.owner_answer = 'proceeding' and c.runner_answer = 'proceeding';

  if v_custody = 'out' then
    v_resolution := 'superseded';
  elsif p_cause = 'ceiling' then
    if v_custody = 'pre' then
      v_resolution := case when v_backfill then 'ceiling_backfill' else 'ceiling' end;
      v_terminal := 'no_show';
    else
      v_resolution := 'superseded';                     -- picked up while the arm ran: started
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
  -- [codex r2 F1 — my round-1 analysis was REFUTED, with the mechanism, and this is the fix]
  -- The no_show write fires 0075 §K's km_release_on_terminal → km_release → `_km_close_hold`,
  -- and that function does NOT merely return quantity: `0075:353-358` also EXTENDS an already
  -- EXPIRED lot to `now() + interval '72 hours'`. Returning held km is a pure unwind; handing
  -- back 72 hours of new spendable lifetime is VALUE CREATED BY A TIMER — 0068's forbidden
  -- direction, and my round-1 note ("a pure hold-unwind") was wrong about the second half.
  --
  -- The fix keeps ONE copy of the netting rule (0075 owns `_km_close_hold`; this file
  -- re-creates nothing of 0075's — REGISTRY's silent-collision law): for a CLOCK-CAUSED
  -- terminal we snapshot the owner's already-expired lots before the status write and restore
  -- their `expires_at` after it. Quantity comes back; lifetime does not. Only lots that are
  -- ALREADY expired can be extended by that arm (its own `expires_at <= now()` condition), so
  -- the snapshot is exactly the affected set — precise and complete.
  --
  -- HUMAN-caused terminals (`cannot_proceed`) keep 0075's grace deliberately: there a person
  -- acted, which is the same class as the owner cancel that already extends. The clock never
  -- gets to grant it. An operator who wants to extend a lot can still do it deliberately —
  -- what is refused is the extension nobody asked for.
  if v_resolution in ('ceiling', 'ceiling_backfill', 'void') then
    -- [blind review MAJOR-7] SCOPED to the lots THIS booking actually holds, locked, in a
    -- deterministic order. Round 2 snapshotted every expired lot the owner had, unlocked:
    -- a concurrent HUMAN cancellation that legitimately extended one of the owner's other
    -- lots would be overwritten by this path's stale restore, and two resolutions touching
    -- overlapping owner-wide sets could take the same rows in opposite orders and deadlock.
    -- The booking's own holds are the only lots this terminal may touch.
    -- the lock has to happen BEFORE the aggregate (`FOR UPDATE` is not allowed with aggregate
    -- functions), so the CTE locks the rows in id order and the aggregation reads what it locked.
    with locked as (
      select l.id, l.expires_at
      from km_lots l
      where l.expires_at is not null and l.expires_at <= now()
        and l.id in (select distinct kl.lot_id from km_ledger kl
                     where kl.booking_id = p_booking and kl.lot_id is not null)
      order by l.id
      for update
    )
    select array_agg(id order by id), array_agg(expires_at order by id)
      into v_lot_ids, v_lot_exp
    from locked;
  end if;
  if v_terminal is not null then
    update bookings set status = v_terminal::booking_status where id = p_booking;

    -- …and the clock's grace is taken back (F1 above). `is distinct from` keeps this a no-op
    -- in the ordinary case where nothing was extended.
    if v_lot_ids is not null then
      update km_lots l set expires_at = x.exp
      from unnest(v_lot_ids, v_lot_exp) as x(id, exp)
      where l.id = x.id and l.expires_at is distinct from x.exp;
    end if;

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

  -- party gate before state gate (0083/0096's order) — but with NO server-caller exemption,
  -- deliberately breaking from that idiom [codex CRIT-7]: a check-in answer is a HUMAN
  -- statement (D5), and a null-uid caller could otherwise fabricate the statement that
  -- creates a money-waiving fault row with nobody behind it. fetch/quote keep the exemption
  -- (reads); confirm_return_tx keeps it (custody stamps are not statements of fault). Here:
  -- no JWT, no answer.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
  if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;

  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  select * into c from booking_checkins bc
   where bc.booking_id = p_booking for update;                      -- checkin ②
  if c.booking_id is null then raise exception 'checkin_not_open'; end if;

  -- idempotent on replay (§12): the SAME side re-sending the SAME answer is the same tap —
  -- answered state returned, nothing rewritten, server timestamp untouched.
  -- ⚠ THIS SITS ABOVE EVERY STATE GATE, and that ordering is this repo's own law: 0083's
  -- `_settle_sealed_run` ① and `confirm_return_tx` both answer "already done" before they
  -- refuse on status ("idempotence BEFORE the state gate (110 S3's law)"). A client retrying
  -- a call that already SUCCEEDED — and whose success is what terminated the booking — cannot
  -- distinguish its own landed answer from a lost one, so raising here would punish the
  -- retry for having worked. A replay of an identical recorded statement is not a new
  -- statement; the gate below exists for new ones.
  if (p_side = 'owner'  and c.owner_answer  = p_answer::checkin_answer)
  or (p_side = 'runner' and c.runner_answer = p_answer::checkin_answer) then
    return fetch_checkin(p_booking);
  end if;

  -- resolved check-ins take no further answers (FM8: offered actions expire with the
  -- check-in; a late response never retracts a resolution). This sits ABOVE the state gate
  -- deliberately: when a check-in resolved and its own terminal moved the booking, BOTH
  -- refusals are true, and the protocol's own record is the more specific answer — it names
  -- what closed the window rather than what the window's closing caused.
  if c.resolved_at is not null then raise exception 'checkin_resolved'; end if;

  -- [codex HIGH-8] a booking that left the protocol's states by SOMEONE ELSE'S path takes no
  -- new answers either — when the real 50% cancel wins the race against a genuine
  -- cannot_proceed, the late answer is refused LOUDLY here, before anything persists, instead
  -- of being swallowed into a superseded resolution that reads as if it were considered.
  -- Reached exactly when the check-in is still OPEN and the booking is already gone, which is
  -- that race and nothing else.
  if b.status not in ('confirmed', 'runner_enroute', 'picked_up', 'active') then
    raise exception 'not_late_eligible';
  end if;

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

-- ═══ §6b state_after_the_fact — the question the clock did not close [blind r5 RC-1] ══════
-- Sean, 2026-08-21: *"a later human statement is still what moves money."* Round 4 wrote that
-- sentence into the header and then shipped the opposite: `answer_checkin` refuses a resolved
-- check-in (correctly — an in-window answer cannot retract a resolution), `no_show` is
-- terminal, and the stalemate arm was unconditional. Together those three made the stalemate
-- PERMANENT. This is the door that keeps the question open.
--
-- It is deliberately NOT a re-opening of the check-in. The protocol's window closed and its
-- record is immutable; what remains available is the thing the window was asking for — a
-- person saying what happened — and it lands where every other statement lands: a
-- `booking_faults` row, with `stated_by` naming the human (D5 as schema, §3).
--
-- ⚠ WHAT THE STATEMENT ENTITLES IS NOT DECIDED HERE. Recording it stops the stalemate arm
-- from claiming "nothing moves" (§9 ①/②), which is the half this file owns; the TRANSFER that
-- should follow a fault on a closed booking — the runner's compensation for an owner-caused
-- no-show, and its mirror — is §4.2 of the plan and is Sean's queued question. The fault row
-- is written so that ruling can be applied to real statements rather than to memory.
create or replace function state_after_the_fact(
  p_booking uuid, p_side text, p_reason text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; c record; v_uid uuid := auth.uid(); v_party uuid;
begin
  if p_side not in ('runner', 'owner') then raise exception 'bad_side'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.club_session_id, bk.status::text as status
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- a statement is a HUMAN act (§6's law, same reasoning): no JWT, no statement.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
  if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  select * into c from booking_checkins bc where bc.booking_id = p_booking for update;
  if c.booking_id is null or c.resolved_at is null then
    -- the window is still open (or never opened): the in-window call owns this.
    raise exception 'checkin_not_resolved';
  end if;
  -- only a NO-FAULT resolution leaves a question open. A resolution that already recorded a
  -- statement was not silence, and `cannot_proceed`'s terminal is not re-litigated here.
  if c.resolution not in ('void', 'ceiling', 'ceiling_backfill') then
    raise exception 'nothing_left_open';
  end if;

  v_party := case when p_side = 'owner' then b.owner_id else b.runner_id end;
  if v_party is null then raise exception 'not_party'; end if;

  -- first statement wins, per side — the same immutability every other statement has.
  insert into booking_faults (booking_id, party, source, stated_by, reason)
  values (p_booking, p_side, 'post_resolution_statement', v_party, p_reason)
  on conflict (booking_id, party) do nothing;

  return jsonb_build_object(
    'recorded', true,
    'party', p_side,
    -- the observable consequence THIS file owns: the stalemate stops answering for this
    -- booking. What the fault then entitles is Sean's §4.2 question.
    'moves_no_money', cancel_moves_no_money(p_booking),
    'server_now', now());
end $$;

revoke execute on function state_after_the_fact(uuid, text, text) from public, anon;
grant  execute on function state_after_the_fact(uuid, text, text) to authenticated, service_role;

comment on function state_after_the_fact is
  '0117 §6b (Sean 2026-08-21 + blind r5 RC-1): 시계가 닫은 것은 예약이지 질문이 아니다. 침묵으로
종결된(void/ceiling/ceiling_backfill) 예약에 대해 당사자가 사후에 자기 진술을 남긴다 — 체크인을
다시 열지 않고, 그 진술은 다른 모든 진술과 같은 자리(booking_faults, stated_by=본인)에 적힌다.
그 순간 §9의 교착 팔은 이 예약에 대해 "아무것도 움직이지 않는다"고 답하기를 멈춘다. 그 진술이
무엇을 청구할 자격이 되는지(러너 보상 등)는 계획 §4.2 — Sean의 대기 중 결정이다.';

-- ═══ §7 fetch_checkin — what the surface renders ══════════════════════════════════════════
create or replace function fetch_checkin(p_booking uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; c record; v_uid uuid := auth.uid(); v_out jsonb;
begin
  select bk.id, bk.status::text as status, bk.scheduled_at, bk.owner_id, bk.runner_id,
         bk.club_session_id, bk.owner_confirmed_handoff_at, bk.runner_confirmed_handoff_at
    into b
  from bookings bk where bk.id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;

  -- ⚠ [blind review BLOCKER-10] THE `current_user` EXEMPTION IS GONE, and it was a hole, not
  -- a convenience. Inside a SECURITY DEFINER function `current_user` is the function OWNER
  -- (postgres) — never the caller — so `current_user in ('service_role','postgres')` is TRUE
  -- for every caller alive, and any principal holding EXECUTE with no `sub` claim (a
  -- service-key JWT, or a direct session that cleared the claim) read arbitrary bookings'
  -- check-in answers and reasons. A definer cannot ask who called it; it can only ask who the
  -- JWT says it is. So: a read of two people's statements requires being one of them, full
  -- stop. No server caller needs this function today (the sweep resolves through
  -- `_resolve_checkin`; the edge prices through `marketplace_cancel_fee`), and a future one
  -- must arrive with an explicit ops surface rather than through an identity gap.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
    raise exception 'not_party';
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
      'custody',      _checkin_custody(b.status::booking_status,
                                       b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at),
      'server_now',   now());
  end if;

  -- ⚠ [ruling 4B, 2026-08-24] A PARTY READS ONLY THEIR OWN REASON TEXT. What Sean authorized
  -- was ASKING for it and STORING it ("ask why they stopped."); he was never asked whether the
  -- OTHER side gets to read it, and until now they did — the payload below returned both
  -- `owner_reason` and `runner_reason` to whichever party called. A reason is typed in the
  -- worst minute of a booking and can carry a door code, an address detail or a medical
  -- emergency; it lands in TWO immutable tables (booking_checkins here, booking_faults at
  -- resolution) and survives account deletion, so a disclosure here is permanent and
  -- unretractable. An authorization to collect is not an authorization to publish, and the
  -- narrow reading is the reversible one: showing the counterparty this text later is a
  -- product decision anyone can make, un-showing it is not.
  --
  -- WHAT THE COUNTERPARTY STILL GETS — `owner_has_reason` / `runner_has_reason`, both sides,
  -- unconditionally, for every caller:
  --   · the name follows the payload's own convention (side prefix + snake_case, like
  --     `owner_answer` / `owner_at`), and BOTH sides carry it for BOTH readers so the client
  --     renders one shape rather than branching on who it is;
  --   · it is a strict boolean (`… is not null`), never NULL — no tri-state for a client to
  --     mis-coalesce, this repo's four-times-landed fail-open shape;
  --   · it leaks nothing the reader does not already hold: the answer itself is in the
  --     payload, and a reason can only ride `cannot_proceed` (§6's gate + §2's CHECK), so
  --     "text was attached" is the only new bit — enough for honest copy ("상대가 사유를
  --     남겼어요"), not enough to read a stranger's emergency.
  --
  -- THE COUNTERPARTY'S KEY IS ABSENT, NOT NULL. Emitting `runner_reason: null` to the owner
  -- would be a FALSE statement about the record ("the runner gave no reason") in exactly the
  -- case where they gave one — the honesty law's own shape, and it would make the boolean and
  -- the text contradict each other in the same object. Absent means "not yours to read";
  -- null would mean "there is none".
  --
  -- THE PARTY GATE ABOVE IS UNTOUCHED, deliberately. Both parties still legitimately read this
  -- check-in — the answers, the stamps, the resolution and the derived trio are shared facts of
  -- one booking. It is only the free text that narrows. The no-row branch above is likewise
  -- untouched: it has no statements to narrow, and its exact four-key shape is pinned (L19).
  v_out := jsonb_build_object(
    'open',              c.resolved_at is null,
    'opened_at',         c.opened_at,
    'deadline_at',       c.deadline_at,
    'owner_answer',      c.owner_answer,
    'owner_at',          c.owner_at,
    'owner_has_reason',  c.owner_reason is not null,
    'runner_answer',     c.runner_answer,
    'runner_at',         c.runner_at,
    'runner_has_reason', c.runner_reason is not null,
    'resolved_at',       c.resolved_at,
    'resolution',        c.resolution,
    'version',           c.version,
    -- the surface must not derive these: the ceiling constant lives server-side only, and a
    -- client clock is exactly what FM2/FM6 refuse to trust.
    'past_ceiling',      late_ceiling_at(b.scheduled_at) <= now(),
    'custody',           _checkin_custody(b.status::booking_status,
                                          b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at),
    'server_now',        now());

  -- two independent tests, not an if/else: a caller who is somehow BOTH parties on one booking
  -- is reading two statements that are both their own, and gets both. `is not distinct from`
  -- keeps this strictly boolean where runner_id is NULL (an unmatched booking has no runner —
  -- `v_uid = b.runner_id` would be NULL there, and a NULL in a guard is how this repo has
  -- shipped fail-open four separate times).
  if v_uid is not distinct from b.owner_id then
    v_out := v_out || jsonb_build_object('owner_reason', c.owner_reason);
  end if;
  if v_uid is not distinct from b.runner_id then
    v_out := v_out || jsonb_build_object('runner_reason', c.runner_reason);
  end if;
  return v_out;
end $$;

revoke execute on function fetch_checkin(uuid) from public, anon;
grant  execute on function fetch_checkin(uuid) to authenticated, service_role;

comment on function fetch_checkin is
  '0117 §7 (§12): the render read — party-gated; {open:false} before the clock fires; carries
past_ceiling (so the client can stop offering "proceed" without knowing the constant) and
server_now (so no countdown trusts a phone clock). REASON TEXT IS SELF-ONLY (ruling 4B,
2026-08-24): the caller''s own owner_reason/runner_reason key is present, the counterparty''s
key is ABSENT (not null — null would assert "no reason given"), and both sides always carry
the boolean owner_has_reason/runner_has_reason so the other party can see THAT a reason was
given without reading it. The party gate itself is unchanged — both parties still read the
check-in; only the free text narrows.';

-- ═══ §8 the sweep + its cron tick ═════════════════════════════════════════════════════════
-- [codex CRIT-1] THE CLOCK SHIPS OFF. The client has zero answer/fetch call sites today, so
-- a sweep that armed at deploy would open check-ins nobody can answer and void bookings on a
-- prompt that never rendered — FM2's exact failure, self-inflicted. ops_flags gains
-- late_protocol_live_since (payments_live_since's idiom: a MOMENT, not a boolean, NULL until
-- Sean sets it) and the sweep returns 0 while it is null. Cron registration below is
-- unconditional — a registered tick on a gated sweep is a no-op, not a clock.
--
-- ⚠ [codex r2 F8] THE FLAG GATES THE CLOCK, NOT THE FILE. An earlier draft of this comment
-- said "0117 lands and deploys inert", and that was FALSE — it contradicted §9's own sentence
-- two hundred lines below. The file's DEPLOY EFFECTS are written out at the head of this
-- migration; read them there. Charging being off (payments_live_since) prevents COLLECTION,
-- not a wrong stored number, a wrong response or a wrong runner-share decision.
alter table ops_flags add column if not exists late_protocol_live_since timestamptz;
comment on column ops_flags.late_protocol_live_since is
  '0117: NULL = the late-booking clock is off (sweep returns 0 — no check-ins open, no
deadline or ceiling resolutions). Set to now() when the stage-2 client surface ships
(Sean''s flip). A moment, not a boolean — payments_live_since''s idiom.';

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
  if (select f.late_protocol_live_since from ops_flags f) is null then return 0; end if;
  -- [MINOR-14] ONE sweep at a time. `lock_timeout` alone turns a collision into a silently
  -- skipped row (the booking waits a full tick, or forever if the pattern repeats); a session
  -- lock makes a duplicate tick leave immediately, which is what a duplicate tick should do.
  -- try, not wait: a slow predecessor must not queue ticks behind it.
  if not pg_try_advisory_lock(hashtextextended('late_booking_sweep', 0)) then return 0; end if;
  -- [codex MEDIUM-11] one abandoned row lock must not stall the whole batch: with a bounded
  -- lock wait, a blocked row times out, its per-row handler logs, and the sweep moves on.
  perform set_config('lock_timeout', '2000', true);

  -- ⓐ expired check-ins → the resolver (deadline rules; renewals never happen here)
  for r in
    select bc.booking_id from booking_checkins bc
    where bc.resolved_at is null and bc.deadline_at <= now()
    -- [MINOR-14] deterministic candidate order: overlapping ticks take rows in the same
    -- sequence, so they queue instead of deadlocking.
    order by bc.booking_id
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
      -- [blind review MAJOR-8] NO EXTRA MARGIN. Round 2 delayed row-less bookings by a full
      -- grace period past the ceiling so the protocol would not "claim a window it never
      -- offered" — but that made the ruled 3h ceiling a 3h30m ceiling in fact, and during the
      -- extra half hour the confirmed tier still charged 10% and accrued a runner share. The
      -- honesty that margin was buying is carried by the CAUSE TOKEN instead
      -- (`ceiling_backfill` says in the record that no answer window ever existed), which
      -- costs nothing and keeps Sean's number the number.
    order by b.id
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
    order by b.id
  loop
    begin
      perform open_checkin(r.id);
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep open % : %', r.id, sqlerrm;
    end;
  end loop;

  perform pg_advisory_unlock(hashtextextended('late_booking_sweep', 0));
  return n;
exception when others then
  -- session-scoped: it must not survive a failed tick
  perform pg_advisory_unlock(hashtextextended('late_booking_sweep', 0));
  raise;
end $$;

revoke execute on function late_booking_sweep() from public, anon, authenticated;
grant  execute on function late_booking_sweep() to service_role;
-- [codex MEDIUM-12] the sweep is the one scheduler-facing hand: pg_cron runs it as the job
-- owner, and a service-key scheduler (the fallback the notice below names) can run it too —
-- which is safe precisely because the sweep is flag-gated (CRIT-1 above) and every entrance
-- behind it (open_checkin, _resolve_checkin) stays sealed. The earlier posture ("no
-- service_role EXECUTE anywhere on the clock") contradicted its own fallback notice; this is
-- the documented pick.

comment on function late_booking_sweep is
  '0117 §8: the late-booking clock — ⓐ resolve expired check-ins ⓑ ceiling-resolve rotted
pre-custody bookings (status only, never money — 0068) ⓒ open check-ins past grace. Club
excluded throughout; */10 on the sweep-payment-intents mod-5 family per 0060:145 (the one
5-minute batch touching neither bookings nor runs).';

-- 0017/0060's guarded form: the local harness has no pg_cron and must still apply cleanly.
do $$ begin
  perform cron.schedule('late-booking-sweep', '3-53/10 * * * *', 'select late_booking_sweep()');
exception when others then
  raise notice 'pg_cron unavailable — 서비스 키 스케줄러로 late_booking_sweep() 를 호출하세요 (EXECUTE 부여됨)';
end $$;

-- [codex MEDIUM-12] the guarded form above cannot fail loudly (the local harness has no
-- pg_cron and must still apply) — so it SELF-VERIFIES instead: where pg_cron exists, a
-- missing registration is a hard migration failure, not a notice scrolled past.
do $$ begin
  -- nested on purpose: plpgsql compiles statements lazily, so the cron.job reference is
  -- never parsed where pg_cron (and its schema) does not exist — the local harness.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- [MINOR-13] the NAME is not the job. A pre-existing entry with someone else's schedule or
    -- command satisfied a name check while the protocol's clock ran at the wrong cadence — or
    -- called something else entirely. The SHAPE is verified: our cadence, our command.
    if not exists (select 1 from cron.job
                   where jobname = 'late-booking-sweep'
                     and schedule = '3-53/10 * * * *'
                     and command like '%late_booking_sweep()%') then
      raise exception 'late-booking-sweep cron registration missing or wrong shape';
    end if;
  end if;
end $$;

-- ═══ §9 the 0066 carve-out — money follows fault (D4), and the ceiling is a fact ══════════
-- ⚠ THE RULING THIS SECTION IMPLEMENTS — Sean, 2026-08-21, verbatim: **"Nobody pays, nobody
-- is paid."** A booking 3h+ past its start with NO arrival evidence, NO handoff stamps and NO
-- human statement from either side moves NO MONEY IN EITHER DIRECTION: the owner is not
-- charged (they may have waited for a runner who never came) and the runner is not
-- compensated (no run happened, and only a clock says so). D5 applied symmetrically — silence
-- never charges AND silence never pays.
--
-- THAT IS WHY THIS IS NOT A "WAIVER", and the name below says so. "Waiving the fee" describes
-- the same act as TAKING ₩12,450 from the runner on a timer, which is exactly what 0068
-- forbids; the honest description is that the clock found a stalemate and the protocol
-- declines to move money at all. Two consequences, both asserted rather than implied:
--   · NO FAULT IS FOUND ON THIS PATH. Silence produces no `booking_faults` row, ever — the
--     resolver writes fault only from a side's own `cannot_proceed` (§5), and nothing in this
--     section writes one. A stalemate is the absence of a finding, not a finding of innocence.
--   · A HUMAN STATEMENT STILL MOVES MONEY LATER. The stalemate is the outcome of silence, not
--     a terminal on the truth: an after-the-fact statement from either side is still the thing
--     that produces fault (§3) and, through it, money. The clock closes the booking; it does
--     not close the question.
--
-- FM7 named the other half: "owner charged the 50% en-route arm for a runner's failure."
-- 0066's arm prices ONE thing — an owner walking away from a runner who is actually coming.
-- Two states falsify that story, and they are DIFFERENT GROUNDS with different reasons:
--   · a booking_faults row naming the RUNNER (their own recorded statement — D5-clean). Today
--     the §5 resolver writes fault only together with a terminal, so a cancellable en-route
--     booking with a runner fault is not producible by this file alone — the arm is
--     defense-in-depth for the fault table's future human writers (ops adjudication), and the
--     predicate is specified against the STATE, not against today's writers.
--   · the ceiling has passed (late_ceiling_at ≤ now()) with no arrival or handoff evidence on
--     the row: the departure story is dead no matter what was or wasn't recorded. THIS is the
--     honest fallback for every booking that predates the protocol — it needs no checkin row
--     and no fault row, only scheduled_at, so the 2026-08-04 row (runner_enroute, 17 days
--     stale) quotes 0 the moment this file lands, sweep or no sweep. ⚠ That sentence is
--     exactly why "the flag makes this file inert" is false, and it is listed as an
--     AT-PUSH-TIME behavior change in the DEPLOY EFFECTS block at the head of the file.
-- Fee 0 also zeroes the runner's compensation automatically: record_enroute_cancel_comp
-- (0080 §K) reads bookings.cancel_fee and refuses fee ≤ 0 — no second rule needed, and none
-- added (the comp writers are NOT touched).
create or replace function cancel_moves_no_money(p_booking uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  -- ① money follows fault (D4): the runner's own recorded statement
  select exists (select 1 from booking_faults f
                 where f.booking_id = p_booking and f.party = 'runner')
  -- ② the silent stalemate (Sean's ruling) — and it is the outcome of SILENCE, so it holds
  --    only while the silence does. [blind r5 RC-1] The arm was unconditional, which made the
  --    stalemate PERMANENT: once the clock had closed a booking, no statement could change what
  --    it cost, and Sean's ruling says the opposite ("the clock closes the booking; it does not
  --    close the question"). `not exists (…booking_faults…)` is what makes the silence a
  --    PREMISE of this arm rather than a one-way door: the moment either party states what
  --    happened — through §6 in the window, or §6b after it — this arm stops answering.
      or exists (select 1 from bookings b
                 where b.id = p_booking and late_ceiling_at(b.scheduled_at) <= now()
                   and not exists (select 1 from booking_faults f2 where f2.booking_id = b.id)
                   -- [codex HIGH-4] the TIMER waives only when nothing says the runner showed
                   -- up. With arrival or handoff evidence on the row, an owner waiting out
                   -- the clock must not strip the runner's 0066 entitlement — with evidence,
                   -- only a recorded fault (the arm above) waives.
                   and b.arrived_at is null
                   and b.owner_confirmed_handoff_at is null
                   and b.runner_confirmed_handoff_at is null)
$$;

revoke execute on function cancel_moves_no_money(uuid) from public, anon, authenticated;
grant  execute on function cancel_moves_no_money(uuid) to service_role;

comment on function cancel_moves_no_money is
  '0117 §9 (Sean 2026-08-21, "Nobody pays, nobody is paid."): TRUE means THIS CANCELLATION
MOVES NO MONEY — not that a fee was forgiven. Two distinct grounds: ① a recorded fault names
the RUNNER (D4, money follows fault — their own statement, never silence) · ② the SILENT
STALEMATE: past the lateness ceiling with no arrival evidence, no handoff stamps and no
statement from either side, so neither party is charged and neither is paid. The runner side
follows automatically: cancel_fee 0 makes both comp writers (0080 §K, 0085) refuse on their
own fee<=0 gates, so nobody is paid either. NO fault row is ever written here — silence
produces no finding, and a later human statement is still what can move money.';

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
        case when cancel_moves_no_money(b.id) then 0
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

-- ── §9d post-handoff cancels are refused BY THE STAMPS, not by the status [BLOCKER-6] ─────
-- 0066 §1 closed `picked_up → cancelled_owner` because "past the handoff it's an incident".
-- That guard reads STATUS — and the handoff writes the two stamps and promotes the status in
-- SEPARATE statements (transition-booking/index.ts:313-322), so there is a window where both
-- humans have confirmed the dog changed hands and the row still says `runner_enroute`. An
-- owner cancel landing in that window stored `cancelled_owner` + the 50% + the en-route
-- compensation, and the later promotion to `picked_up` then failed: the durable terminal said
-- pre-custody about a dog that was already gone. My §5 resolver was fixed for exactly this
-- (stamps-first custody, CRIT-3); the cancellation path was not. Same rule, same one copy —
-- `_checkin_custody` is the only definition of "where is the dog", and both callers ask it.
create or replace function _booking_cancel_custody_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if _checkin_custody(old.status, old.owner_confirmed_handoff_at,
                      old.runner_confirmed_handoff_at) = 'post' then
    raise exception 'cancel_after_handoff'
      using hint = 'both handoff stamps exist — past the handoff this is an incident, not a cancellation';
  end if;
  return new;
end $$;

create trigger booking_cancel_custody_guard
  before update of status on bookings
  for each row
  -- ⚠ SCOPED TO THE STATES THE TRANSITION MAP ALLOWS. `picked_up → cancelled_owner` is already
  -- refused by 0066 §1 with `invalid booking transition`, and 105 E6 pins that exact sentence;
  -- firing here first would replace a shipped suite's error with mine for no gain. The hole
  -- this guard closes is the one the map CANNOT see: `runner_enroute` with both handoff stamps
  -- already written, which the map happily allows.
  when (new.status = 'cancelled_owner' and old.status is distinct from new.status
        and old.status in ('confirmed', 'runner_enroute')
        and old.club_session_id is null)
  execute function _booking_cancel_custody_guard();

comment on function _booking_cancel_custody_guard is
  '0117 §9d (blind review BLOCKER-6): 인계 도장 두 개가 찍힌 예약은 status 가 아직
runner_enroute 여도 취소될 수 없다 — 개는 이미 러너 손에 있고, 그 지점부터는 인시던트지
취소가 아니다 (0066 §1 의 규칙을 상태가 아니라 도장으로 읽는다). 커스터디 정의는
_checkin_custody 한 벌 — 리졸버와 취소 경로가 같은 것을 묻는다.';

-- ── §9e the cancel-money repair sweep [blind review BLOCKER-5] ────────────────────────────
-- A cancellation is committed by ONE statement and its money consequences are written by
-- SEVERAL requests afterwards. A worker that dies between them leaves a permanent partial
-- commit: `cancelled_owner` with a fee recorded, no runner compensation, no charge intent —
-- and the retry path cannot repair it, because a second tap sees `cancelled_owner` and
-- returns the already-cancelled answer. Nothing looked for those rows, so the runner simply
-- never got paid and nobody found out.
--
-- This is NOT the class 0068 retired. 0068 deleted a cron that DECIDED money on a timer
-- (a refund fired because a clock passed T-10). Here a human already decided — they cancelled,
-- and the tier was priced at that moment — and the sweep only finishes writing what that
-- decision entailed. The precedent is 0080's own `sweep_settled_without_payments`, which
-- exists for exactly this shape on the settle path. Both writers are idempotent and gated
-- (0080 §K and 0085 refuse anything but their tier, and refuse fee <= 0), and the mint writes
-- nothing while charging is off — so a re-drive can only complete, never duplicate.
create or replace function sweep_cancel_money_gaps() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  -- [blind r5 NOTE-10] gated by the SAME flag as the rest of the protocol. Ungated, this cron
  -- would start writing runner ledger rows for HISTORICAL cancellations the moment the file
  -- landed — money appearing in people's ledgers because a migration was pushed, which is the
  -- deploy-day surprise the flag exists to prevent. It repairs what the protocol era produced.
  if (select f.late_protocol_live_since from ops_flags f) is null then return 0; end if;
  if not pg_try_advisory_lock(hashtextextended('cancel_money_gaps', 0)) then return 0; end if;
  for r in
    select b.id, b.cancel_reason,
           not exists (select 1 from ledger_items li where li.booking_id = b.id) as comp_missing,
           not exists (select 1 from payments pm where pm.booking_id = b.id)     as intent_missing
    from bookings b
    where b.status = 'cancelled_owner'
      and b.club_session_id is null
      and coalesce(b.cancel_fee, 0) > 0
      and b.cancel_reason in ('owner_cancel_enroute', 'owner_cancel_late')
      and b.runner_id is not null
      -- [blind r5 F5] A LEDGER ROW IS NOT EVIDENCE THE FEE WAS COLLECTED. Round 4 excluded any
      -- booking that had one, so the commonest tear — comp written, then the worker dies before
      -- `collectCancelFee` — was invisible to the repair that existed for it, and deleting the
      -- collection call outright left the pin green. The two halves are independent facts and
      -- each is checked for itself.
      and (not exists (select 1 from ledger_items li where li.booking_id = b.id)
           or not exists (select 1 from payments pm where pm.booking_id = b.id))
      -- give the request that owns this cancel time to finish its own writes; only rows that
      -- are STILL bare after the window are torn.
      and b.updated_at < now() - cancel_gap_grace()
    order by b.id
  loop
    begin
      if r.comp_missing then
        if r.cancel_reason = 'owner_cancel_enroute' then
          perform record_enroute_cancel_comp(r.id);
        else
          perform record_late_cancel_share(r.id);
        end if;
      end if;
      -- the owner's side of the same tear. `mint_cancel_fee_intent` is idempotent and returns
      -- ZERO ROWS while charging is off (0080 §E), so this is inert pre-cutover and cannot
      -- double-mint after it. Dispatch stays with the edge/ladder — this only restores the
      -- intent the dying request never wrote.
      if r.intent_missing then
        perform mint_cancel_fee_intent(r.id);
      end if;
      n := n + 1;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select b.runner_id, 'booking', '시간을 비워둔 보상이 기록됐어요',
             '취소 보상 기록이 지연됐다가 방금 반영됐어요', b.id
      from bookings b
      where b.id = r.id and b.runner_id is not null
        and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.profile_id = b.runner_id
                          and nt.title = '시간을 비워둔 보상이 기록됐어요');
    exception when others then
      raise warning 'sweep_cancel_money_gaps % : %', r.id, sqlerrm;
    end;
  end loop;
  perform pg_advisory_unlock(hashtextextended('cancel_money_gaps', 0));
  return n;
exception when others then
  perform pg_advisory_unlock(hashtextextended('cancel_money_gaps', 0));
  raise;
end $$;

revoke execute on function sweep_cancel_money_gaps() from public, anon, authenticated;
grant  execute on function sweep_cancel_money_gaps() to service_role;

comment on function sweep_cancel_money_gaps is
  '0117 §9e (blind review BLOCKER-5): 취소는 한 문장으로 커밋되고 그 돈의 결과는 이어지는
요청들이 쓴다 — 그 사이에 워커가 죽으면 수수료만 적힌 채 러너 보상도 청구 인텐트도 없는
영구 부분 커밋이 남고, 재시도는 이미-취소됨으로 빠져나가 복구하지 못한다. 이 스윕이 그
행들을 찾아 멱등한 보상 기록을 다시 몬다 (0080의 sweep_settled_without_payments 와 같은
형상). 타이머가 돈을 결정하지 않는다 — 사람이 이미 결정한 것을 마저 쓸 뿐이다 (0068 구분).';

do $$ begin
  perform cron.schedule('cancel-money-gaps', '6-56/10 * * * *', 'select sweep_cancel_money_gaps()');
exception when others then
  raise notice 'pg_cron unavailable — sweep_cancel_money_gaps() 를 외부 스케줄러로 호출하세요';
end $$;

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
  select bk.id, bk.owner_id, bk.runner_id, bk.club_session_id into b
  from bookings bk where bk.id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;
  -- [BLOCKER-10] same correction as fetch_checkin: a definer's `current_user` is its OWNER, so
  -- the old exemption admitted every caller that arrived without a `sub` claim. A price quote
  -- for someone else's booking is exactly the read this gate exists to refuse.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
    raise exception 'not_found';   -- indistinguishable from missing — no enumeration oracle
  end if;
  -- [MAJOR-9] the club never gets a marketplace number. `cancel_owner` already refuses club
  -- bookings before quoting (their ladder lives in club_config: free_hours 24 / late 10% /
  -- post-accept 20%), so a quote surface that answered for them would publish a price the club
  -- side never agreed to — and the client would render it as the fee.
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  select f.fee, f.status into v_fee, v_status from marketplace_cancel_fee(p_booking) f;
  return jsonb_build_object('fee', v_fee, 'status', v_status);
end $$;

revoke execute on function quote_cancel_fee(uuid) from public, anon;
grant  execute on function quote_cancel_fee(uuid) to authenticated, service_role;

-- ── §9c the written fee is the at-write-time fee [codex HIGH-6] ───────────────────────────
-- cancel_owner.ts quotes and writes in separate requests, so a 50% quote taken at T+2:59:59
-- can land after T+3:00:00 — pricing a booking the ceiling just waived. The fix lives at the
-- one boundary every cancel crosses: when a marketplace booking transitions INTO
-- cancelled_owner, cancel_fee is re-derived by THE ladder in the same statement (BEFORE
-- UPDATE reads the pre-transition row, so the quote prices the status the CAS matched).
-- ONE copy: the trigger delegates to marketplace_cancel_fee and computes nothing. The whole
-- money chain downstream already reads the STORED fee (mint_cancel_fee_intent 0080:447,
-- record_enroute_cancel_comp 0080 §K, record_late_cancel_share 0085), so the corrected
-- number propagates with no edge-function change; the edge's local variable prices only its
-- response copy, and its fee>0 guard against a stored 0 leads to a mint that reads 0 and
-- records nothing. Club bookings are excluded — their ladder lives in club_config.
-- INVOKER on purpose (enforce_booking_transition's shape): the roles that can move
-- bookings.status are service_role (holds marketplace_cancel_fee EXECUTE) and the server
-- classes; a definer trigger function would also be the 99 S1 anon-executable-definer class.
create or replace function _booking_cancel_fee_truth() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_fee int;
begin
  -- [codex r2 F6] the deliberate ops correction. Round 1 clobbered a one-statement operator
  -- fix of a wrong stored fee — the trigger would recompute it right back. An ops write says
  -- so, in the same transaction, and owns the number it writes:
  --     set local app.ops_cancel_fee_override = 'on';
  --     update bookings set status = 'cancelled_owner', cancel_fee = <n> where id = …;
  -- Nothing client-side can reach this: GUCs are per-session and the client never opens one.
  if coalesce(current_setting('app.ops_cancel_fee_override', true), '') = 'on' then
    return new;
  end if;

  select f.fee into v_fee from marketplace_cancel_fee(old.id) f;

  -- ⚠ [blind review BLOCKER-3] THE WRITE VALIDATES THE QUOTE; IT DOES NOT SILENTLY CORRECT IT.
  -- Round 2 made the STORED number right and left the promise wrong: a status-only CAS cannot
  -- enforce a TIME-DEPENDENT price, so a booking quoted at 10:00:00 and written at 10:00:02
  -- still committed — at a different number than the human was shown. "The price shown IS the
  -- price charged" is only true if the shown price is part of what the write agrees to. So the
  -- claimed fee IS the token: when it no longer matches the ladder, the transition is REFUSED
  -- and the caller must re-quote. Nobody is charged a number they were not shown; the cost is
  -- one extra round trip on a boundary crossing, which is the honest trade.
  if new.cancel_fee is distinct from v_fee then
    raise exception 'cancel_fee_requote'
      using detail = format('quoted=%s derived=%s', new.cancel_fee, v_fee),
            hint = 'the ladder moved between the quote and the write — re-quote and re-confirm';
  end if;
  -- [codex r2 F3] THE MARKER TRAVELS WITH THE FEE, in the same statement, from the same read.
  -- The tier marker is what selects the downstream consequence (0080 §K gates the en-route
  -- compensation on 'owner_cancel_enroute'; 0085 gates the runner's half on
  -- 'owner_cancel_late'), so a fee corrected here while the marker was chosen by someone
  -- else's earlier quote is precisely the split brain: stored 10% with no marker pays the
  -- runner nothing. One statement, one read of the ladder, fee and consequence together.
  -- The en-route marker is written even at a waived 0 because it records the TIER, and both
  -- comp writers already refuse fee <= 0 on their own.
  new.cancel_reason := case
    when old.status = 'runner_enroute' then 'owner_cancel_enroute'
    when v_fee > 0                     then 'owner_cancel_late'
    else null
  end;
  return new;
end $$;

create trigger booking_cancel_fee_truth
  before update of status on bookings
  for each row
  when (new.status = 'cancelled_owner' and old.status is distinct from new.status
        and new.cancel_fee is not null            -- a cancel that claims NO fee writes none:
                                                  -- 113 K7's status-only km fixture and any
                                                  -- ops correction stay byte-identical; the
                                                  -- edge always writes a fee in its CAS, so
                                                  -- HIGH-6's race is fully covered
        and old.club_session_id is null)
  execute function _booking_cancel_fee_truth();

comment on function _booking_cancel_fee_truth is
  '0117 §9c (codex HIGH-6 + r2 F3/F6): 마켓플레이스 예약이 cancelled_owner 로 전이하는 그
문장에서 cancel_fee 와 티어 마커(cancel_reason)를 사다리 한 번 읽어 함께 쓴다 — 기록되는
수수료도, 그 수수료의 결과(러너 보상·배분·청구)도 하나의 숫자가 정한다. BEFORE UPDATE 는
전이 전 행을 읽으므로 CAS 가 맞춘 상태로 가격한다. 사다리 위임 — 사본 없음. 클럽 제외.
운영 정정은 같은 트랜잭션에서 app.ops_cancel_fee_override = ''on'' 으로 이 트리거를 비켜간다
(그 문장이 쓰는 숫자를 그 문장이 책임진다).';

comment on function quote_cancel_fee is
  '0117 §9b (Sean 2026-08-21, reversing 0066:89''s no-client-quote posture): party-gated
read-only window onto marketplace_cancel_fee — THE number, one implementation, zero copies
(delegation pinned at source level). Foreign bookings answer not_found like missing ones (no
enumeration oracle). The client renders words for context from the returned status arm.';
