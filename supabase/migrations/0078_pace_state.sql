-- 0078 — pace-state rails: the run-start snapshot + the server mirror of the §1 state machine.
-- Plan: docs/plans/pace-state-ui-plan.md (§1 semantics · §4 snapshot · §5 LA payload extension).
-- Client mirror: app/src/lib/pace.ts — ONE state machine, two implementations, exactly as
-- `_owner_la_trace_km` (0063 §3) mirrors geo.ts's mergeFixes. If §1 changes, BOTH move.
--
-- WHAT THIS FILE IS FOR: completion is minimum-DISTANCE only, so pace-state is the quality signal
-- that polices the slow-stroll incentive. It is a SUGGESTION the owner sets, never a money-bearing
-- threshold, never a public ranking, never a push. On the owner's lock screen the claim can only
-- come from the server (the owner's app is asleep — 0063's founding fact), so the machine has to
-- exist twice. This file is the server half:
--   §1  runs.pace_suggest_sec        — the per-run SNAPSHOT column + its freeze seal
--   §2  _runs_pace_snapshot_tg       — before-insert trigger: one snapshot, server-clamped
--   §3  _owner_la_window_pace        — rolling-window pace over the trace (the judged metric)
--   §4  _owner_la_pace_state         — the state machine, latch and all (mirror of pace.ts)
--   §5  trigger wiring               — trace push carries the claim; stale/done/ended carry ''
--
-- THE THREE LAWS THIS FILE ENCODES, so nobody re-derives them from the UI:
--   · FREEZE (fairness): the suggestion is snapshotted when the run row is born. A pref edit
--     mid-run affects the NEXT run — the goalpost cannot move while the runner is measured.
--   · CLAMP (클라 불신): dogs.preferences is a CLIENT-WRITTEN jsonb. The band 420..540 is
--     re-imposed here at snapshot time; a corrupt value degrades to the 480 default, never to
--     an error and never to a threshold outside the band.
--   · HONESTY GATE: below 0.30km / 180s elapsed there is no measurement, so there is no claim.
--     '' means "no claim rendered" — absence, not a grey third zone (plan §1, 체력나이 precedent).
--
-- ⚠ WHAT THIS FILE DELIBERATELY DOES NOT TOUCH: the `phase` field and `_owner_la_push`'s
-- phase-aware throttle. paceState rides ALONGSIDE phase in the same props object. A phase change
-- bypasses the 20s gap (stale→running recovery must be instant — 103 L13); a pace flip must NOT,
-- or a 60s-cadence ambient channel turns chatty. Accepted consequence: up to ~20s of latency on a
-- colour change on the lock screen. That is the correct trade for an ambient signal (plan §5).
--
-- Pins: 115_pace_state_suite.sql (P1–P9). Mutation reverts recorded in that file's header.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1. The snapshot column
-- ══════════════════════════════════════════════════════════════════════════════════════════════

alter table runs add column pace_suggest_sec int;

comment on column runs.pace_suggest_sec is
  '0078 — 권장 최소 페이스 (sec/km) SNAPSHOTTED at run creation from dogs.preferences.'
  'paceSuggestSec, clamped 420..540, default 480. Live-only quality signal: the LA rails and both '
  'live screens read THIS, never dogs.preferences, so a mid-run pref edit cannot move the '
  'goalpost. Never money-bearing, never aggregated into runner stats.';

-- ── freeze seal (0057 §5 reproduction discipline: the latest definition of _guard_run_cols,
--    copied byte-for-byte, with exactly ONE addition — pace_suggest_sec joins the protected
--    column list). WHY: the "runs runner update" policy lets the RUNNER write runs rows directly
--    (live trace saves go through it), and the runner is the party the threshold measures. An
--    unlisted column is a writable column; a runner nudging their own floor to 540 mid-run is
--    the exact fairness hole the snapshot exists to close. The lesson of the addresses column
--    whitelist (113 K14), applied at birth instead of after the incident.
create or replace function _guard_run_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare v_status text;
begin
  if current_user in ('authenticated', 'anon') then
    -- ① 정산 후 동결 — 부킹이 종단이면 클라 쓰기 전면 거부 (호출자=해당 부킹 러너라 RLS로 정당히 읽힘)
    select b.status::text into v_status from bookings b where b.id = new.booking_id;
    if v_status in ('completed', 'incident_review') then
      raise exception 'run_frozen_after_settlement'
        using detail = '정산·인시던트 종료된 러닝 기록은 변경할 수 없어요';
    end if;
    -- ② 클라 쓰기 가능 표면 = 라이브 append 3종(events/photos/trace)뿐 — 그 외 변경 거부
    if new.actual_km          is distinct from old.actual_km
    or new.duration_sec       is distinct from old.duration_sec
    or new.avg_pace_sec_per_km is distinct from old.avg_pace_sec_per_km
    or new.end_reason         is distinct from old.end_reason
    or new.condition_note     is distinct from old.condition_note
    or new.started_at         is distinct from old.started_at
    or new.ended_at           is distinct from old.ended_at
    or new.booking_id         is distinct from old.booking_id
    or new.pace_suggest_sec   is distinct from old.pace_suggest_sec   -- [0078] 스냅샷 동결
    then
      raise exception 'run_protected_columns'
        using detail = '거리·시간·페이스·종료사유는 서버(정산)만 기록해요 — 클라는 events/photos/trace만';
    end if;
  end if;
  return new;
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2. The snapshot — taken once, when the run row is born
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- WHY A TRIGGER AND NOT A DEFAULT / A CALLER EDIT: runs rows are born in three different places —
--   · the marketplace path: transition-booking edge function, `start_run` case
--     (supabase/functions/transition-booking/index.ts — `db.from("runs").insert(...)`, service_role)
--   · the club path: club_start_delegated_runs (0038, redefined 0050) — `insert into runs` per dog
--   · the settlement backstop: settle_run_tx (0028) — `insert into runs … on conflict do update`,
--     which writes a row when the start event was lost
-- Three writers in two languages, one of them TypeScript. A before-insert trigger is the only
-- place that catches all three and cannot be forgotten by the fourth writer nobody has written
-- yet. (The settle path's ON CONFLICT branch never touches this column, so a re-inserted row
-- keeps the snapshot it was born with.)
--
-- The value is (re)computed on EVERY insert and overwrites whatever the caller supplied: the
-- threshold is a server fact. A client-supplied value would be a client-chosen goalpost.
create or replace function _runs_pace_snapshot_tg() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_raw text; v_sec int;
begin
  select nullif(btrim(coalesce(d.preferences->>'paceSuggestSec', '')), '') into v_raw
    from bookings b join dogs d on d.id = b.dog_id
   where b.id = new.booking_id;
  begin
    -- ::numeric, not ::int — '480.0' is a legitimate jsonb number, and rounding mirrors
    -- clampSuggest()'s Math.round. A value that is not a number at all (true, 'fast', {}) lands
    -- in the handler and becomes the default: a corrupt preference is an ABSENT preference,
    -- never an error that blocks a run from starting.
    v_sec := round(v_raw::numeric)::int;
  exception when others then
    v_sec := null;
  end;
  new.pace_suggest_sec := greatest(420, least(540, coalesce(v_sec, 480)));
  return new;
exception when others then
  new.pace_suggest_sec := 480;   -- a lock-screen colour never blocks a run from starting
  return new;
end $$;

drop trigger if exists runs_pace_snapshot on runs;
create trigger runs_pace_snapshot before insert on runs
  for each row execute function _runs_pace_snapshot_tg();

revoke execute on function _runs_pace_snapshot_tg() from public, anon, authenticated;

comment on function _runs_pace_snapshot_tg is
  '0078 — before-insert on runs: snapshots dogs.preferences.paceSuggestSec into '
  'runs.pace_suggest_sec, server-clamped 420..540 (default 480). Catches all three runs writers '
  '(start_run edge fn · club_start_delegated_runs · settle_run_tx backstop) in one place.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3. The judged metric — rolling-window pace over the trace
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- The state judges what the runner is doing NOW (recoverable), not the run's cumulative average.
-- The DISPLAYED 페이스 stat stays cumulative — two numbers, two jobs, only one ever printed
-- (plan §1, Sean D6). A red light or a care stop can briefly yellow the window; hysteresis, the
-- latch and recoverability are the designed mitigations.
--
-- SEGMENT RULE: byte-identical to `_owner_la_trace_km` (0063 §3) — d > 2m (jitter), d < 120m
-- (teleport), dt > 0, speed ≤ 8 m/s — over the SAME equirectangular approximation.
-- ⚠ THE MATH IS DUPLICATED ON PURPOSE. `_owner_la_trace_km` is pinned byte-exactly by 103 L5 and
-- feeds the number on the owner's lock screen; refactoring it into a shared inner helper would
-- put a live display number one careless edit away from drift, for the sake of nine lines. The
-- duplication is the cheaper risk. If the billable rule ever changes, it changes in BOTH.
--
-- p_window_ms is milliseconds to mirror pace.ts's PACE_WINDOW_MS constant; trace `t` is SECONDS
-- (run.tsx buildTracePts: `Math.floor(p.t / 1000)` — "서버 규약: 초 단위 단조"), so the cutoff is
-- converted here. Returns null — never a guess — when the window holds no billable segment;
-- null is the caller's cue for the '' state.
create or replace function _owner_la_window_pace(p_trace jsonb, p_window_ms int) returns int
language plpgsql immutable as $$
declare
  n int := coalesce(jsonb_array_length(p_trace), 0);
  i int; v_prev jsonb; v_cur jsonb;
  v_t_prev numeric; v_t_cur numeric; v_dt numeric; v_d numeric;
  v_max_t numeric; v_cut numeric;
  v_km numeric := 0; v_first_t numeric; v_last_t numeric;
begin
  if n < 2 or p_window_ms is null or p_window_ms <= 0 then return null; end if;
  -- max(t) rather than "the last element": monotonicity is a client convention, and the anchor
  -- of an honest window must not depend on one.
  select max((e->>'t')::numeric) into v_max_t from jsonb_array_elements(p_trace) e;
  if v_max_t is null then return null; end if;
  v_cut := v_max_t - p_window_ms::numeric / 1000;

  for i in 1..n - 1 loop
    v_prev := p_trace->(i - 1);
    v_cur  := p_trace->i;
    v_t_prev := (v_prev->>'t')::numeric;
    v_t_cur  := (v_cur->>'t')::numeric;
    if v_t_prev is null or v_t_cur is null then continue; end if;
    -- BOTH endpoints inside the window: a segment half outside it would import distance the
    -- window did not measure. (Fewer than 2 in-window points ⇒ no segment ⇒ null, as specified.)
    if v_t_prev < v_cut then continue; end if;
    v_dt := v_t_cur - v_t_prev;
    if v_dt <= 0 then continue; end if;
    v_d := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
              + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
    if v_d > 2 and v_d < 120 and v_d / v_dt <= 8 then
      v_km := v_km + v_d / 1000;
      if v_first_t is null then v_first_t := v_t_prev; end if;
      v_last_t := v_t_cur;
    end if;
  end loop;

  -- The span is the span of the ACCEPTED points, not of the window: time spent inside a rejected
  -- segment (a teleport, a GPS hiccup) is time we cannot honestly attribute to the distance.
  if v_km <= 0 or v_first_t is null or v_last_t - v_first_t <= 0 then return null; end if;
  return round((v_last_t - v_first_t) / v_km)::int;
end $$;

revoke execute on function _owner_la_window_pace(jsonb,int) from public, anon, authenticated;

comment on function _owner_la_window_pace is
  '0078 — rolling-window pace (sec/km) over runs.trace: last p_window_ms of trace, same billable '
  'segment rule as _owner_la_trace_km. null when the window holds no billable distance. Server '
  'mirror of pace.ts windowPaceSec().';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §4. The state machine (plan §1) — the mirror of pace.ts paceState()
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- Two claim states and an absence. The hysteresis is a LATCH, so it needs memory: p_prev is the
-- last state this owner's banner actually showed (last_state->>'paceState' — 0063 already stores
-- every pushed props object per token row). A stateless threshold flickers at the boundary; the
-- latch plus the 15 sec/km slack on the good→slow edge is what makes the chip stay still.
--   gate      : km ≥ 0.30 AND elapsed ≥ 180 — else '' (a 120s sample of a 180s window is not a
--               measurement, and green at 80m would be a fabricated one)
--   null pace : '' (fewer than 2 accepted points in the window — no claim, not a guess)
--   prev slow : back to good only at/under the suggestion itself (the floor is inclusive)
--   prev good : yellow only past suggest + 15
--   prev ''   : benefit of the doubt — same edge as 'good'. Absence of memory (mount, remount,
--               a token row that has never been pushed) never yellows a runner inside the band.
-- Staleness is NOT a parameter: the stale phase hard-sets '' at the call site, because "no signal"
-- and "too slow" must never look alike (plan §1). The latch survives staleness in last_state,
-- so recovery restores the prior state instead of re-litigating it.
create or replace function _owner_la_pace_state(
  p_prev text, p_window_sec int, p_km numeric, p_elapsed int, p_suggest int
) returns text
language sql immutable as $$
  select case
    when p_km is null or p_km < 0.30 then ''
    when p_elapsed is null or p_elapsed < 180 then ''
    when p_window_sec is null then ''
    when coalesce(p_prev, '') = 'slow'
      then case when p_window_sec <= coalesce(p_suggest, 480) then 'good' else 'slow' end
    else case when p_window_sec > coalesce(p_suggest, 480) + 15 then 'slow' else 'good' end
  end
$$;

revoke execute on function _owner_la_pace_state(text,int,numeric,int,int) from public, anon, authenticated;

comment on function _owner_la_pace_state is
  '0078 — plan §1 state machine, server mirror of pace.ts paceState(): honesty gate (0.30km/180s), '
  'null-window ⇒ '''', prev-aware hysteresis latch (good→slow at suggest+15, slow→good at suggest). '
  'Stale is not a parameter — the stale/done/ended paths hard-set '''' at the call site.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §5. Trigger wiring — the claim rides the existing props object
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- 0063 §5's definition, reproduced with exactly three additions (the 0077 reproduction discipline):
--   ⓐ the prev/suggest/window/state locals,
--   ⓑ their computation between the elapsed clock and the props object,
--   ⓒ 'paceState' in the props jsonb.
-- Everything else — the guard order, the silence conditions, the phase, the swallow-everything
-- handler — is byte-identical, because 103 L7/L8/L9/L13 pin it.
--
-- ⚠ PER-TOKEN PREV, ONE STATE PER FIRING: last_state lives per TOKEN row (a booking can have more
-- than one — the owner's phone and iPad). Computing the latch per token would let two of the
-- owner's devices disagree about the same run, and would make the pushed payload a function of
-- which device happened to be throttled. So the state is computed ONCE per trigger firing from a
-- single deterministic token row (oldest registration first, profile_id as the tie-break) and the
-- same value is fanned out to every token. In the overwhelmingly common single-device case the
-- pick is the identity; in the multi-device case the oldest registration is the one that has been
-- following the run longest, which is the memory most likely to be warm.
create or replace function _owner_la_trace_tg() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_status text; v_dog text; v_runner text; v_target numeric;
  v_km numeric; v_sec int; v_props jsonb;
  v_prev text; v_suggest int; v_window int; v_state text;   -- [0078]
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

  -- [0078] the claim. Note what it reads: new.pace_suggest_sec (the SNAPSHOT on this run row),
  -- never dogs.preferences — the freeze law is enforced by where the number comes from.
  select t.last_state->>'paceState' into v_prev
    from owner_la_tokens t
   where t.booking_id = new.booking_id
   order by t.created_at, t.profile_id
   limit 1;
  v_suggest := coalesce(new.pace_suggest_sec, 480);
  v_window  := _owner_la_window_pace(new.trace, 180000);
  v_state   := _owner_la_pace_state(v_prev, v_window, v_km, v_sec, v_suggest);

  v_props := jsonb_build_object(
    'phase', 'running',
    'dogName', v_dog,
    'runnerName', v_runner,
    'km', to_char(v_km, 'FM999990.00'),
    'targetKm', rtrim(rtrim(to_char(v_target, 'FM999990.0'), '0'), '.'),
    'pace', _owner_la_fmt_pace(v_sec, v_km),
    'elapsed', _owner_la_fmt_elapsed(v_sec),
    'statusLine', '방금 업데이트',
    'paceState', v_state);                                   -- [0078]
  perform _owner_la_push(new.booking_id, 'update', v_props);
  return new;
exception when others then
  return new;  -- push is an auxiliary channel — it must never block a trace save (0024 precedent)
end $$;

-- 0063 §6's sweep, reproduced with ONE addition: 'paceState', ''. The stale state drops the pace
-- claim AND blanks the pace datum — "no signal" and "too slow" must never look alike, and a
-- last-known colour that still looks current is the exact false claim the rule exists to prevent.
-- The dedup key (phase + statusLine) is untouched: paceState is constant '' on this path, so it
-- cannot make a dead signal chatty. 103 L11/L12 pin the rest byte-for-byte.
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
      'statusLine', v_line,
      'paceState', '');                                      -- [0078] stale never carries a claim
    v_n := v_n + _owner_la_push(r.booking_id, 'update', v_props, null, 0);
  end loop;
  return v_n;
end $$;

-- 0063 §5's booking trigger, reproduced with ONE addition per branch: 'paceState', ''.
-- done/ended render settled facts, not live claims — no posthumous verdict on a finished run
-- (plan §6). 103 L10/L14 pin the rest.
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
      'statusLine', case when v_photos > 0 then '사진 ' || v_photos || '장' else '' end,
      'paceState', '');                                      -- [0078]
    perform _owner_la_push(new.id, 'end', v_props, 480, 0);
    delete from owner_la_tokens where booking_id = new.id;
  elsif new.status = 'incident_review' and old.status in ('picked_up', 'active') then
    v_props := jsonb_build_object(
      'phase', 'ended', 'dogName', v_dog, 'runnerName', v_runner,
      'km', '', 'targetKm', '', 'pace', '', 'elapsed', '', 'statusLine', '',
      'paceState', '');                                      -- [0078]
    perform _owner_la_push(new.id, 'end', v_props, 0, 0);
    delete from owner_la_tokens where booking_id = new.id;
  end if;
  return new;
exception when others then
  return new;  -- never block settlement or an incident transition over a lock-screen banner
end $$;

revoke execute on function _owner_la_trace_tg() from public, anon, authenticated;
revoke execute on function _owner_la_booking_tg() from public, anon, authenticated;
revoke execute on function owner_la_sweep_stale() from public, anon, authenticated;
