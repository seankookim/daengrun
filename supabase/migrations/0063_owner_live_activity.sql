-- 0063 — owner-side Live Activity: APNs push plumbing (lab: docs/labs/live-activity-lab.html, option ② 기록형).
--
-- THE ARCHITECTURAL FACT THIS FILE EXISTS FOR: the owner's app is NOT running during the run.
-- The runner LA (RunActivity.tsx) updates locally because the runner's app is alive; the owner's
-- lock-screen banner can only be updated by APNs (`apns-push-type: liveactivity`) against a
-- PER-ACTIVITY ActivityKit push token — a different animal from the per-device Expo token in
-- push_tokens (0024). This migration owns:
--   §1  owner_la_tokens        — per-activity token registry (RLS on, ZERO policies — 0062 idiom)
--   §2  owner_la_push_config   — relay URL + shared secret, ops-inserted AFTER deploy (no secrets in repo)
--   §3  registration RPCs      — owner_la_register / owner_la_unregister (party gate before state gate)
--   §4  server-side km + formatting over runs.trace (close approximation of the paid number —
--       see §4's note; the DONE push uses the exact settled runs.actual_km)
--   §5  the push composer      — _owner_la_push → pg_net POST to the relay
--   §6  triggers               — runs.trace save → 'running' push · bookings.status → 'done'/'ended' push
--   §7  staleness sweep + cron — 90s without a fix ⇒ the number goes grey and says so (honesty law)
--
-- WHY THE TRACE AND NOT THE REALTIME BROADCAST: owner-visible position arrives two ways today —
-- the `run-{booking}` Realtime broadcast (3s throttle, ephemeral, never touches the DB) and
-- runs.trace, which the runner client persists every 60s (run.tsx saveTrace) and which settlement
-- pays out on. Postgres cannot observe broadcasts, so the ONLY server-side truth that can drive an
-- APNs update is runs.trace — and it is the same merged buffer that feeds the broadcast, not a
-- second source. Consequence: pushed updates have a ~60s cadence (plus save latency); the in-app
-- live map stays on the 3s broadcast, and owner/live.tsx also updates the LA locally while the app
-- is awake. The push path is for the lock screen when the app is suspended.
--
-- WHY A RELAY AND NOT pg_net → APNs DIRECT: the APNs provider API demands an ES256-signed provider
-- JWT rotated hourly. Postgres cannot sign ES256 and a pre-signed token would go stale — so the
-- trigger POSTs a flat JSON job to a relay (Supabase Edge Function, spec in the wave report) which
-- holds the .p8 key, signs the JWT, and forwards to APNs. Same shape as 0024's pg_net → Expo hop.
-- Until ops inserts the config row, _owner_la_push is a silent no-op: the LA still starts and
-- updates locally while the owner's app is awake, and nothing pretends a push pipeline exists.
--
-- Security laws honored (each pinned in 103_owner_la_suite.sql):
--   · every definer function sets `search_path = public, pg_temp` in its CREATE (98 H1 sweeps this)
--   · client RPCs revoked from public/anon, granted to authenticated; internal fns revoked from all
--     three client roles (99 S1 sweeps anon-execute on definer functions)
--   · party gate BEFORE state gate; `not_found` byte-identical for "no such booking" and "not yours"
--   · NULL-safe auth (`not_signed_in` raised explicitly, never a silent zero-row match)
--   · tokens table: RLS on, ZERO policies — a push token must never be one policy mistake from
--     public (0024's own design note about runner tokens, taken one step further)

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1. Per-activity token registry
-- ══════════════════════════════════════════════════════════════════════════════════════════════

create table owner_la_tokens (
  booking_id   uuid not null references bookings(id) on delete cascade,
  profile_id   uuid not null references profiles(id) on delete cascade,
  activity_id  text not null,   -- ActivityKit activity id (client-side identity, rotation dedup)
  apns_token   text not null,   -- hex per-activity token — rotates; client re-registers on rotation
  environment  text not null default 'production' check (environment in ('development','production')),
  last_push_at timestamptz,     -- throttle anchor
  last_state   jsonb,           -- last pushed props — staleness dedup + phase-aware throttle
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (booking_id, profile_id)
);

create trigger t_owner_la_touch before update on owner_la_tokens
  for each row execute function touch_updated_at();

alter table owner_la_tokens enable row level security;
-- ZERO policies (0062 idiom). Writes go through owner_la_register/unregister; reads go through
-- nothing — no client ever needs to read a push token back.

comment on table owner_la_tokens is
  '0063 — ActivityKit per-activity push tokens for the OWNER lock-screen Live Activity. RLS on '
  'with ZERO policies: register/unregister via definer RPCs only. Distinct from push_tokens (0024) '
  'which holds per-device Expo tokens.';

create table owner_la_push_config (
  id           boolean primary key default true check (id),  -- at most one row
  relay_url    text not null,
  relay_secret text not null,
  updated_at   timestamptz not null default now()
);
alter table owner_la_push_config enable row level security;
-- ZERO policies. Ops inserts the row with the service role after deploying the relay function.
-- No row ⇒ _owner_la_push is a no-op ⇒ no push pipeline is pretended into existence.

comment on table owner_la_push_config is
  '0063 — APNs relay endpoint + shared secret, inserted by ops AFTER the relay is deployed. '
  'Secrets never live in migrations. Empty table = pushes silently disabled (LA is local-only).';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2. Registration RPCs (client-facing)
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- Register (or rotate) the caller's per-activity token for a booking they own.
-- PARTY GATE BEFORE STATE GATE: `not_found` is identical for "no such booking" and "someone
-- else's booking", so booking ids cannot be enumerated through this surface.
create or replace function owner_la_register(
  p_booking uuid, p_activity_id text, p_token text, p_env text default 'production'
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid    uuid := auth.uid();
  v_status text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;

  select b.status::text into v_status from bookings b
   where b.id = p_booking and b.owner_id = v_uid;
  if not found then raise exception 'not_found'; end if;

  -- The LA exists from handoff-sealed to completed — outside that there is nothing to push to.
  if v_status not in ('picked_up','active') then raise exception 'not_live'; end if;

  -- Hex only, 16-400 chars. Length is checked separately: PG regex repetition counts cap at 255,
  -- so '{16,400}' inside the pattern is not even a legal regex.
  if p_token is null or p_token !~* '^[0-9a-f]+$'
     or char_length(p_token) not between 16 and 400 then
    raise exception 'bad_token';
  end if;
  if coalesce(btrim(p_activity_id), '') = '' then raise exception 'bad_activity'; end if;
  if p_env not in ('development','production') then raise exception 'bad_env'; end if;

  insert into owner_la_tokens (booking_id, profile_id, activity_id, apns_token, environment)
  values (p_booking, v_uid, p_activity_id, lower(p_token), p_env)
  on conflict (booking_id, profile_id) do update
     set activity_id = excluded.activity_id,
         apns_token  = excluded.apns_token,
         environment = excluded.environment,
         updated_at  = now();
end $$;

-- Remove the caller's own registration. Deleting nothing is not an error (no oracle).
create or replace function owner_la_unregister(p_booking uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  delete from owner_la_tokens where booking_id = p_booking and profile_id = v_uid;
end $$;

revoke execute on function owner_la_register(uuid,text,text,text) from public, anon;
grant  execute on function owner_la_register(uuid,text,text,text) to authenticated;
revoke execute on function owner_la_unregister(uuid) from public, anon;
grant  execute on function owner_la_unregister(uuid) to authenticated;

comment on function owner_la_register is
  '0063 — owner registers/rotates the ActivityKit push token for their own live booking. '
  'Party gate (not_found) before state gate (not_live); token must be 16-400 hex chars '
  '(length checked outside the regex — PG repetition counts cap at 255).';
comment on function owner_la_unregister is
  '0063 — owner removes their own token row. Silent when nothing matches.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3. Server-side distance + display formatting over runs.trace
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- Billable km over a stored trace — the SQL mirror of the client's mergeFixes billable rule
-- (geo.ts: count a segment only when d > 2m, d < 120m, dt > 0, speed ≤ 8 m/s). Distance uses the
-- same equirectangular approximation as club_save_run_trace (0050): 111000 m/° lat, 88800 m/° lng.
-- The stored trace already passed the client 8 m/s gate and (club path) the server gate, so
-- consecutive-pair accumulation here measures the same run the app displays.
-- ⚠ It is NOT byte-identical to the number settlement pays. settle-run pays on the client's
-- actual_km, which geo.ts computes with Haversine; this uses equirectangular. Measured delta:
-- ~0.03% on a typical mixed route, 0.72% worst case (pure due-east 10km — server 9.99 vs client
-- 9.92). That is display-only: this value drives the LIVE lock-screen number, while the 'done'
-- push sends the exact runs.actual_km, so the final banner and the invoice always agree.
-- Do not "fix" this by paying on the server number without an isolation cycle — it is a money
-- surface (0059 doctrine).
create or replace function _owner_la_trace_km(p_trace jsonb) returns numeric
language plpgsql immutable as $$
declare
  n int := coalesce(jsonb_array_length(p_trace), 0);
  i int; v_prev jsonb; v_cur jsonb; v_dt numeric; v_d numeric; v_km numeric := 0;
begin
  if n < 2 then return 0; end if;
  for i in 1..n - 1 loop
    v_prev := p_trace->(i - 1);
    v_cur  := p_trace->i;
    v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
    if v_dt <= 0 then continue; end if;
    v_d := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
              + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
    if v_d > 2 and v_d < 120 and v_d / v_dt <= 8 then
      v_km := v_km + v_d / 1000;
    end if;
  end loop;
  return v_km;
end $$;

-- 'MM:SS' — same shape as the client fmt() in owner/live.tsx (minutes may exceed 60, like 90:00).
create or replace function _owner_la_fmt_elapsed(p_sec int) returns text
language sql immutable as $$
  select lpad((greatest(coalesce(p_sec, 0), 0) / 60)::text, 2, '0')
      || ':' || lpad((greatest(coalesce(p_sec, 0), 0) % 60)::text, 2, '0')
$$;

-- "7'02''" — mirror of the client paceStr(): below 0.05 km there is no honest pace, return ''.
create or replace function _owner_la_fmt_pace(p_sec int, p_km numeric) returns text
language sql immutable as $$
  select case
    when p_km is null or p_km < 0.05 or coalesce(p_sec, 0) <= 0 then ''
    else floor((p_sec / p_km) / 60)::int::text
         || '''' || lpad(round((p_sec / p_km) % 60)::int::text, 2, '0') || '"'
  end
$$;

revoke execute on function _owner_la_trace_km(jsonb) from public, anon, authenticated;
revoke execute on function _owner_la_fmt_elapsed(int) from public, anon, authenticated;
revoke execute on function _owner_la_fmt_pace(int,numeric) from public, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §4. Push composer — one job per token row, POSTed to the relay
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- Job shape (the relay turns this into the actual APNs request — see wave report for the mapping):
--   { token, environment, event: 'update'|'end', activity: 'OwnerRunActivity',
--     props: {phase, dogName, runnerName, km, targetKm, pace, elapsed, statusLine},
--     dismiss_sec, booking_id }
-- Throttle: an 'update' whose phase equals the last pushed phase is skipped inside
-- p_min_gap_sec of the previous push (default 20s — trace saves are 60s apart in the steady
-- state; the gap only absorbs the unmount+interval double-save). A PHASE CHANGE is never
-- throttled: stale→running recovery must not wait out the gap.
create or replace function _owner_la_push(
  p_booking uuid, p_event text, p_props jsonb,
  p_dismiss_sec int default null, p_min_gap_sec int default 20
) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_url text; v_secret text; r record; v_n int := 0;
begin
  select relay_url, relay_secret into v_url, v_secret from owner_la_push_config where id;
  if not found then return 0; end if;  -- relay not deployed — pushes honestly do not exist yet

  for r in select * from owner_la_tokens t where t.booking_id = p_booking for update loop
    if p_event = 'update'
       and p_min_gap_sec > 0
       and r.last_push_at is not null
       and r.last_push_at > now() - make_interval(secs => p_min_gap_sec)
       and coalesce(r.last_state->>'phase', '') = coalesce(p_props->>'phase', '') then
      continue;
    end if;
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret),
      body := jsonb_build_object(
        'token', r.apns_token,
        'environment', r.environment,
        'event', p_event,
        'activity', 'OwnerRunActivity',
        'props', p_props,
        'dismiss_sec', p_dismiss_sec,
        'booking_id', p_booking));
    update owner_la_tokens
       set last_push_at = now(), last_state = p_props
     where booking_id = r.booking_id and profile_id = r.profile_id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

revoke execute on function _owner_la_push(uuid,text,jsonb,int,int) from public, anon, authenticated;

comment on function _owner_la_push is
  '0063 internal — fans one LA update out to every registered token of a booking via pg_net → '
  'relay. No config row = no-op. Phase-aware 20s throttle on updates; phase changes always pass.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §5. Triggers — the update pipeline
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- runs.trace save (runner client, every 60s while running) → 'running' push.
-- Honesty guards, in order: no tokens → silence · booking not active → silence · fewer than two
-- points or < 10m of billable distance → silence (a number that does not exist yet is not drawn —
-- the LA stays on the handoff card until there is a real distance; lab §C-① law).
create or replace function _owner_la_trace_tg() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_status text; v_dog text; v_runner text; v_target numeric;
  v_km numeric; v_sec int; v_props jsonb;
begin
  if not exists (select 1 from owner_la_tokens t where t.booking_id = new.booking_id) then
    return new;
  end if;

  select b.status::text, d.name, coalesce(p.name, '러너'), b.km
    into v_status, v_dog, v_runner, v_target
    from bookings b
    join dogs d on d.id = b.dog_id
    left join profiles p on p.id = b.runner_id
   where b.id = new.booking_id;
  if v_status is distinct from 'active' then return new; end if;

  if coalesce(jsonb_array_length(new.trace), 0) < 2 then return new; end if;
  v_km := _owner_la_trace_km(new.trace);
  if v_km < 0.01 then return new; end if;

  v_sec := greatest(0, floor(extract(epoch from (now() - coalesce(new.started_at, now()))))::int);
  v_props := jsonb_build_object(
    'phase', 'running',
    'dogName', v_dog,
    'runnerName', v_runner,
    'km', to_char(v_km, 'FM999990.00'),
    'targetKm', rtrim(rtrim(to_char(v_target, 'FM999990.0'), '0'), '.'),
    'pace', _owner_la_fmt_pace(v_sec, v_km),
    'elapsed', _owner_la_fmt_elapsed(v_sec),
    'statusLine', '방금 업데이트');
  perform _owner_la_push(new.booking_id, 'update', v_props);
  return new;
exception when others then
  return new;  -- push is an auxiliary channel — it must never block a trace save (0024 precedent)
end $$;

drop trigger if exists owner_la_trace on runs;
create trigger owner_la_trace after update of trace on runs
  for each row execute function _owner_la_trace_tg();

-- bookings.status terminal transitions → 'end' push + token cleanup.
--   completed        → phase 'done' with the SETTLED numbers (runs.actual_km/duration/photos),
--                      kept on the lock screen 8 minutes (lab §C-④), tap → report.
--   incident_review  (from picked_up/active — the only mid-run exits the transition matrix allows)
--                    → phase 'ended', dismissed immediately. A live-looking banner surviving an
--                      aborted run would be a lie.
create or replace function _owner_la_booking_tg() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_dog text; v_runner text;
  v_km numeric; v_sec int; v_photos int; v_props jsonb;
begin
  if not exists (select 1 from owner_la_tokens t where t.booking_id = new.id) then
    return new;
  end if;

  select d.name, coalesce(p.name, '러너') into v_dog, v_runner
    from bookings b
    join dogs d on d.id = b.dog_id
    left join profiles p on p.id = b.runner_id
   where b.id = new.id;

  if new.status = 'completed' then
    select r.actual_km, r.duration_sec, coalesce(array_length(r.photos, 1), 0)
      into v_km, v_sec, v_photos
      from runs r where r.booking_id = new.id;
    v_props := jsonb_build_object(
      'phase', 'done',
      'dogName', v_dog,
      'runnerName', v_runner,
      'km', case when v_km is null then '' else to_char(v_km, 'FM999990.00') end,
      'targetKm', '',
      'pace', '',
      'elapsed', case when v_sec is null then '' else _owner_la_fmt_elapsed(v_sec) end,
      'statusLine', case when v_photos > 0 then '사진 ' || v_photos || '장' else '' end);
    perform _owner_la_push(new.id, 'end', v_props, 480, 0);
    delete from owner_la_tokens where booking_id = new.id;
  elsif new.status = 'incident_review' and old.status in ('picked_up', 'active') then
    v_props := jsonb_build_object(
      'phase', 'ended', 'dogName', v_dog, 'runnerName', v_runner,
      'km', '', 'targetKm', '', 'pace', '', 'elapsed', '', 'statusLine', '');
    perform _owner_la_push(new.id, 'end', v_props, 0, 0);
    delete from owner_la_tokens where booking_id = new.id;
  end if;
  return new;
exception when others then
  return new;  -- never block settlement or an incident transition over a lock-screen banner
end $$;

drop trigger if exists owner_la_booking on bookings;
create trigger owner_la_booking after update of status on bookings
  for each row execute function _owner_la_booking_tg();

revoke execute on function _owner_la_trace_tg() from public, anon, authenticated;
revoke execute on function _owner_la_booking_tg() from public, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §6. Staleness sweep — the ③ 갱신 끊김 state (non-negotiable, lab §C)
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- Nothing fires a trigger when nothing happens — staleness needs a clock. Every minute: any active
-- booking with a registered LA whose newest trace fix is ≥ 90s old (the SAME 90s the in-app
-- owner/live staleness clock uses) gets a 'stale' push: the number greys out and the line says how
-- long it has been. Dedup by content — a new push only when the minute count (or phase) changes,
-- so a dead signal costs one push per minute, not one per sweep. Recovery is free: the next trace
-- save pushes 'running', and the phase change bypasses the throttle.
create or replace function owner_la_sweep_stale() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; v_last_t numeric; v_age int; v_min int; v_km numeric; v_line text; v_props jsonb;
  v_n int := 0;
begin
  for r in
    select t.booking_id, t.last_state, run.trace, b.km as target_km,
           d.name as dog_name, coalesce(p.name, '러너') as runner_name
      from owner_la_tokens t
      join bookings b on b.id = t.booking_id and b.status = 'active'
      join runs run on run.booking_id = b.id
      join dogs d on d.id = b.dog_id
      left join profiles p on p.id = b.runner_id
  loop
    -- No fix ever received → the LA is still on the handoff card; there is no number to grey out.
    if coalesce(jsonb_array_length(r.trace), 0) < 2 then continue; end if;
    v_last_t := (r.trace->-1->>'t')::numeric;
    v_age := floor(extract(epoch from now()) - v_last_t)::int;
    if v_age < 90 then continue; end if;

    v_min := greatest(1, v_age / 60);
    v_line := v_min || '분째 위치가 갱신되지 않았어요';
    if coalesce(r.last_state->>'phase', '') = 'stale'
       and coalesce(r.last_state->>'statusLine', '') = v_line then
      continue;  -- same minute already pushed
    end if;

    v_km := _owner_la_trace_km(r.trace);
    v_props := jsonb_build_object(
      'phase', 'stale',
      'dogName', r.dog_name,
      'runnerName', r.runner_name,
      'km', case when v_km < 0.01 then '' else to_char(v_km, 'FM999990.00') end,
      'targetKm', rtrim(rtrim(to_char(r.target_km, 'FM999990.0'), '0'), '.'),
      'pace', '',
      'elapsed', '',
      'statusLine', v_line);
    v_n := v_n + _owner_la_push(r.booking_id, 'update', v_props, null, 0);
  end loop;
  return v_n;
end $$;

revoke execute on function owner_la_sweep_stale() from public, anon, authenticated;

comment on function owner_la_sweep_stale is
  '0063 — cron(1min): pushes the ③ 갱신 끊김 state when the newest fix is ≥90s old (same threshold '
  'as the in-app owner/live clock). Content-deduped: one push per stale minute per booking.';

-- pg_cron every minute (0014 pattern — migration survives environments without pg_cron)
do $$ begin
  perform cron.schedule('owner-la-stale', '* * * * *', 'select owner_la_sweep_stale()');
exception when others then
  raise notice 'pg_cron unavailable — schedule owner_la_sweep_stale() externally: %', sqlerrm;
end $$;
