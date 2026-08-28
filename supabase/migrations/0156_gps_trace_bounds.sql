-- ═══ 0156: a GPS trace cannot run into the future, and two useless points are not a measurement ═══
--
-- Closes findings 1 (CRITICAL) and 5 (HIGH) of `docs/reviews/2026-08-28-codex-runend-money.md`.
-- Both move the ledger and runner earnings TODAY. Neither is gated by a money flag.
--
-- ── FINDING 1, THE FRAUD VECTOR ──
-- The assigned runner supplies every coordinate AND every timestamp (`api.ts:4307` →
-- `club_save_run_trace`, granted to `authenticated` at `0038:291`; `t` is epoch SECONDS).
-- Ingest (`0053:135-142`) validates exactly two things: `t` strictly increasing, and ≤ 8 m/s
-- between consecutive fixes. **Neither bounds the absolute value of `t`.** Derivation
-- (`0144:216-222`) then takes every point with `t >= started_at` and has **no upper bound at all**.
-- So a plausible ≤8 m/s trace whose timestamps run hours into the future is accepted, stored, and
-- counted: 99 km frozen into a 5 km booking, written to `ledger_items` by the payout path.
--
-- ── THE FIX, AND WHY IT IS SHAPED THIS WAY ──
-- §B is the money guard and it does NOT change any signature. `_club_derive_run_km` is `stable`
-- and is called from exactly one place — `club_end_pack_runs:427` — inside the freeze
-- transaction. So `now()` evaluated there **is the host's tap moment**. Bounding the window at
-- `now()` therefore gives us codex's `started_at <= t <= v_at` without threading a new parameter
-- through a 225-line function, and without a DROP that would discard an ACL.
-- ⚠ It also closes the derivation half of finding 4 (points arriving after the tap are no longer
--   counted). It does NOT close finding 4 itself — the stale-trace race needs a two-phase stop
--   (stamp a cutoff, finalize the runner's tail through it, then freeze), which is a separate
--   slice. Do not read this migration as closing 4.
--
-- ⚠ §A is deliberately GENEROUS, and that is a considered trade, not laziness. A tight ingest
--   bound would strand a runner whose phone clock is skewed — trading a defect that arms later
--   for one that fires now, which this repo has a law about. §B already caps the money at real
--   elapsed server time regardless of skew, so §A only has to stop absurd data from being stored
--   at all. One hour is far outside any plausible clock skew and far inside "hours into the
--   future". The runner gets a NAMED error, not a silent drop.
--
-- ── FINDING 5, THE TWO-POINT ZERO ──
-- With exactly two in-window points there is no maximum gap and no coverage requirement, so two
-- identical endpoints hours apart accumulate nothing and return `0.00` — which the caller accepts
-- as a COMPLETED MEASURED run and prices.
-- 🔴 The fix must NOT simply refuse zero. 0152/suite 183 establish the distinction this whole
--    family turns on: 「measured 0 km」 is a real answer (a stationary dog) and must survive;
--    「never measured」 must be NULL. A rule that refused both would pass a refusal pin perfectly
--    and be the same defect with the opposite sign. So the discriminator is COVERAGE, not the
--    value: a densely-sampled stationary dog still returns 0.00; a pair of points separated by a
--    gap larger than any real sampling cadence returns NULL.
-- ⚠ THE THRESHOLD IS PROVISIONAL AND IS SEAN'S CALL. codex's own open question is 「what maximum
--   gap and minimum coverage define a measured run, including a genuinely stationary dog?」 and
--   nobody has answered it. 300 s is chosen because the client uploads every 60 s
--   (`club/run/[sid].tsx:18`), so a five-minute hole means the app was not reporting, not that the
--   dog was still. It is a single named constant so his ruling is a one-line change.

-- ---------- §A. INGEST: a fix cannot be dated meaningfully in the future ----------
-- 0053's body, unchanged except for the new bound. Correct-forward: this file defines the version
-- production will run, so the whole body is restated rather than patched.
create or replace function club_save_run_trace(p_session uuid, p_trace jsonb) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n int; v_prev jsonb; v_cur jsonb; v_dt numeric; v_dist numeric; i int;
  v_run runs%rowtype; v_existing jsonb; v_last_t numeric; v_add jsonb; v_merged jsonb;
  v_now numeric; v_max_t numeric;
  -- Generous on purpose — see the header. §B is what caps the money.
  c_future_slack_sec constant numeric := 3600;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if jsonb_typeof(coalesce(p_trace, 'null'::jsonb)) <> 'array' then raise exception 'bad_trace'; end if;

  -- 🔴 THE NEW BOUND. `t` is epoch seconds. Asserted as an exact comparison on a non-NULL max so a
  -- trace of objects with no `t` cannot slip through as NULL (a NULL predicate would make the
  -- guard silent, which is the failure mode this repo has a standing law about).
  v_now := extract(epoch from now());
  select max((e->>'t')::numeric) into v_max_t
    from jsonb_array_elements(p_trace) e
   where jsonb_typeof(e) = 'object' and (e->>'t') is not null;
  if v_max_t is not null and v_max_t > v_now + c_future_slack_sec then
    raise exception 'trace_future_fix';
  end if;

  -- 배치 내부 시퀀스 검증: t 단조 증가 · 불가능 속도(>8 m/s) 거부 (0053과 동일)
  for i in 1..coalesce(jsonb_array_length(p_trace), 0) - 1 loop
    v_prev := p_trace->(i - 1); v_cur := p_trace->i;
    v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
    if v_dt <= 0 then raise exception 'trace_out_of_order'; end if;
    v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
    if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
  end loop;

  n := 0;
  for v_run in
    select r.* from runs r join bookings b on b.id = r.booking_id
    where b.club_session_id = p_session and b.runner_id = auth.uid() and b.status = 'active'
  loop
    v_existing := coalesce(v_run.trace, '[]'::jsonb);
    if jsonb_typeof(v_existing) <> 'array' then v_existing := '[]'::jsonb; end if;
    if jsonb_array_length(v_existing) = 0 then
      v_merged := p_trace;
    else
      v_last_t := (v_existing->(jsonb_array_length(v_existing) - 1)->>'t')::numeric;
      select jsonb_agg(e order by (e->>'t')::numeric)
        into v_add
        from jsonb_array_elements(p_trace) e
        where (e->>'t')::numeric > v_last_t;
      if v_add is null or jsonb_array_length(v_add) = 0 then
        v_merged := v_existing;
      else
        v_cur := v_add->0;
        v_prev := v_existing->(jsonb_array_length(v_existing) - 1);
        v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
        v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                     + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
        if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
        v_merged := v_existing || v_add;
      end if;
    end if;
    update runs set trace = v_merged where id = v_run.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- 0038:291 granted this to `authenticated` and this file does not re-establish that by accident:
-- the grant is restated explicitly, because a `create or replace` in a file that did not FIRST
-- define the function is a plain CREATE wherever the function is absent, and a definer born that
-- way is PUBLIC-executable (CLAUDE.md §definer-ACL, 0116:636).
-- ⚠ Written UNQUALIFIED deliberately. `check-definer-acl.mjs:118` matches
-- `revoke execute on function <bare-name>(`, so a schema-qualified `public.<name>` — which is
-- perfectly correct SQL — is not recognised and the gate reports the ACL as unset. Matching the
-- gate's convention rather than widening the gate: its narrowness is deliberate and documented.
revoke execute on function club_save_run_trace(uuid, jsonb) from public, anon;
grant  execute on function club_save_run_trace(uuid, jsonb) to authenticated;

comment on function club_save_run_trace is
  '0156 §A — 0053 본문 + 미래 시각 거부(trace_future_fix). t 는 epoch 초이고, 기존 검증은 단조성과
8 m/s 뿐이라 「몇 시간 뒤」 타임스탬프가 그대로 저장되고 거리로 환산됐다. 관대한 1시간 여유는 의도적이다 —
시계가 어긋난 폰을 지금 막아 세우는 대신, 돈의 상한은 §B(now() 상한)가 진다.';

-- ---------- §B. DERIVATION: the window has an upper bound, and coverage decides zero vs unknown ----------
create or replace function public._club_derive_run_km(p_trace jsonb, p_started timestamptz)
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_t0   numeric;
  v_t1   numeric;
  v_pts  jsonb;
  v_n    int;
  i      int;
  v_prev jsonb;
  v_cur  jsonb;
  v_psec numeric;
  v_csec numeric;
  v_dt   numeric;
  v_d    numeric;
  v_km   numeric := 0;
  v_gap  numeric := 0;
  -- Provisional, and Sean's to rule on — see the header.
  c_max_gap_sec constant numeric := 300;
  c_tap_grace_sec constant numeric := 60;
begin
  if p_trace is null or p_started is null then return null; end if;
  if jsonb_typeof(p_trace) <> 'array' then return null; end if;
  v_t0 := extract(epoch from p_started);
  -- 🔴 THE MONEY GUARD. This function is `stable` and is called only from `club_end_pack_runs`
  -- inside the freeze transaction, so `now()` here IS the host's tap. Points dated after the tap
  -- — whether fabricated in the future or uploaded late — are outside the window and are not paid.
  -- ⚠ A SMALL GRACE, and it is deliberate. A fix timestamped a second or two after the tap is
  -- clock jitter and upload-boundary timing, not fraud — a strict `<= now()` would silently drop
  -- a legitimate final segment and under-pay the runner, which is the same class of error as
  -- over-paying, pointed the other way. The fraud this guard exists to stop is measured in HOURS;
  -- 60 s caps any residual at 8 m/s × 60 s ≈ 480 m while leaving honest boundary fixes alone.
  v_t1 := extract(epoch from now()) + c_tap_grace_sec;

  select jsonb_agg(e order by (e->>'t')::numeric)
    into v_pts
    from jsonb_array_elements(p_trace) e
   where jsonb_typeof(e) = 'object'
     and (e->>'t')   is not null
     and (e->>'lat') is not null
     and (e->>'lng') is not null
     and (e->>'t')::numeric >= v_t0
     and (e->>'t')::numeric <= v_t1;

  if v_pts is null then return null; end if;
  v_n := jsonb_array_length(v_pts);
  if v_n < 2 then return null; end if;

  v_prev := v_pts->0;
  v_psec := floor((v_prev->>'t')::numeric);
  for i in 1 .. v_n - 1 loop
    v_cur  := v_pts->i;
    v_csec := floor((v_cur->>'t')::numeric);
    if v_csec > v_psec then
      v_dt := v_csec - v_psec;
      if v_dt > v_gap then v_gap := v_dt; end if;   -- widest hole between accepted fixes
      v_d  := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
      if v_d > 2 and v_d < 120 and v_d / v_dt <= 8 then
        v_km := v_km + v_d / 1000;
      end if;
      v_prev := v_cur;
      v_psec := v_csec;
    end if;
  end loop;

  -- 🔴 COVERAGE, not value. A hole wider than any real sampling cadence means the app was not
  -- reporting — that is an ABSENCE of measurement and must be NULL, exactly as 0144 already
  -- returns NULL for fewer than two points. A densely-sampled stationary dog still reaches the
  -- return below with v_km = 0 and is priced as a true measured zero, which 0152/183 require.
  if v_gap > c_max_gap_sec then return null; end if;

  return round(v_km, 2);
end $$;

revoke execute on function _club_derive_run_km(jsonb, timestamptz)
  from public, anon, authenticated, service_role;

comment on function public._club_derive_run_km is
  '0156 §B — 0144 본문 + (a) 창의 상한 now() (이 함수는 stable 이고 프리즈 트랜잭션 안에서만 불리므로
now() 가 곧 호스트의 탭 시각이다): 미래로 조작된 점도, 탭 이후 늦게 올라온 점도 돈이 되지 않는다.
(b) 커버리지 게이트: 실제 샘플링 간격보다 넓은 구멍은 「측정 없음」(NULL)이지 0 km 가 아니다 —
촘촘히 찍힌 정지 상태의 개는 여전히 0.00 을 돌려받는다 (0152/183 의 구분).
⚠ 300 초 상한은 잠정값이고 Sean 의 판단 사항이다.';

-- ── VERIFY — abort the apply if either guard is absent from the deployed body ──
-- Reads `prosrc` with COMMENTS STRIPPED: this file documents both guards at length, and a check
-- for CALLING something is otherwise satisfied by a comment EXPLAINING it (CLAUDE.md, three
-- instances of that class this week).
do $$
declare
  v_ing text; v_der text; v_bad text := '';
begin
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_ing
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_save_run_trace';
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_der
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_derive_run_km';

  if v_ing is null then v_bad := v_bad || ' NO-SOURCE(club_save_run_trace)'; end if;
  if v_der is null then v_bad := v_bad || ' NO-SOURCE(_club_derive_run_km)'; end if;

  if (v_ing ~ 'trace_future_fix') is not true then v_bad := v_bad || ' ingest-missing-future-bound'; end if;
  if (v_der ~ 'v_t1') is not true then v_bad := v_bad || ' derive-missing-upper-bound'; end if;
  if (v_der ~ 'c_tap_grace_sec') is not true then v_bad := v_bad || ' derive-missing-tap-grace'; end if;
  if (v_der ~ 'c_max_gap_sec') is not true then v_bad := v_bad || ' derive-missing-coverage-gate'; end if;

  -- the ACL half, both directions
  if has_function_privilege('authenticated','public.club_save_run_trace(uuid, jsonb)','EXECUTE')
     is distinct from true then v_bad := v_bad || ' ingest-LOST-authenticated'; end if;
  if has_function_privilege('anon','public.club_save_run_trace(uuid, jsonb)','EXECUTE')
     is distinct from false then v_bad := v_bad || ' ingest-anon-executable'; end if;
  if has_function_privilege('authenticated','public._club_derive_run_km(jsonb, timestamptz)','EXECUTE')
     is distinct from false then v_bad := v_bad || ' derive-client-executable'; end if;

  if v_bad <> '' then raise exception '0156 VERIFY failed:%', v_bad; end if;
end $$;
