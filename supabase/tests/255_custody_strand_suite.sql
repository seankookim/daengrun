-- ═══ 255 — 0224: a custody that never moved · the sealed-unsettled ops bell · the recurring pause
-- ═══        dedupe · the resolver's actor leaves the party-readable blob
-- ═══        0224-A1 · A2 · A3 · A4 · A5 · B1 · B2 · B3 · C1 · D1 · S1, tag `cst`
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · A1 **A `picked_up` CUSTODY PAST THE START THRESHOLD IS TOLD ONCE — AND ONLY THEN.** With the
--        threshold NULL (the shipped value) a real `sweep_run_end_recovery()` tick writes NOTHING
--        about a month-old pickup. With it set, the same tick writes exactly one row to the owner,
--        one to the runner (each with its own sentence — the runner is asked to start, the owner is
--        told the runner was asked) and exactly one `system` row to EVERY active `return_strand`
--        recipient; a second tick adds none. A pickup inside the threshold and a CLUB pickup of the
--        same age get nothing, and the month-old pickup gets no END-shape row.
--   · A2 **AN `active` RUN THAT WAS NEVER STOPPED, PAST THE END THRESHOLD, IS TOLD ONCE.** Same
--        shape as A1 for `end_run`, measured against the run's NOMINAL end — including a row with
--        NO `runs` row at all (the clock falls back rather than going silent). A run started five
--        minutes ago and a run that ENDED (return unconfirmed — arms ⓑ/ⓕ's subject, not this one's)
--        get no custody row.
--   · A3 **THE WORK GATE HOLDS A STRANDED CUSTODY, NOT A LIVE ONE.** `runner_work_gate` answers
--        `gated`, `waiting_on = start_run | end_run`, `exit = runner_start_run | runner_end_run`
--        for a runner whose only booking is a stranded pickup / an unstopped run, and `gated =
--        false` for the SAME rows with the thresholds NULL. A runner whose pickup is five minutes
--        old is NOT gated (0092 §3's line). The existing arm is unmoved: a run that ended with only
--        the runner's stamp still answers `owner` / `owner_confirm_return`, and a completed booking
--        gates nobody. `ops_gated_runners()` lists exactly the gated custody rows with the new words.
--   · A4 **`ops_stranded_custody()` IS THE ROSTER'S READ, AND IT IS THE SWEEP'S OWN SET.** A
--        signed-in stranger and a `payout_due`-only operator get `not_ops` — the same word before
--        any strand exists and after three have been belled — and no caller gets `not_signed_in`.
--        For a `return_strand` operator the set of this suite's bookings the list returns EQUALS the
--        set the sweep actually belled; with the thresholds switched back to NULL the belled rows
--        stay listed and nothing else appears. The row's KEY SET is exactly the declared eleven
--        (no money, no contact field — asserted on `to_jsonb`, not a substring scan).
--   · A5 **AN EMPTY ROSTER CANNOT HOLD THE PARTIES' NOTICE HOSTAGE.** With every `return_strand`
--        row inactive, 51 stranded pickups: tick one tells the parties of fifty, tick two tells the
--        fifty-first — although all 51 ops halves are still PENDING. No operator row is written to
--        nobody; subscribing ONE operator delivers exactly one row per strand on the next tick and
--        tells no party twice. (Rolled back after measuring — the shared roster is restored.)
--   · B1 **A SEALED-BUT-UNSETTLED RUN PAST `SEAL_ALARM_AFTER` BELLS EVERY `payout_due` RECIPIENT
--        ONCE.** The parties' alarm is unchanged (still two rows); a row sealed an hour ago bells
--        nobody; a second tick adds nothing; and a row whose PARTIES were told before 0224 (the
--        alarm row already exists) still gets its operator bell once — the ops one-shot is its own.
--   · B2 **THE THREE NEW `system` TITLES ARE LEDGERED — measured against what the deployed writers
--        actually WROTE, not against a copy of a list.** Every `system` title the sweep wrote about
--        this suite's bookings is in `_noti_ops_titles()`, classifies as `ops`, and is not in the
--        urgent family; the ledger has no duplicates.
--   · B3 **`ops_sealed_unsettled()` IS `payout_due`'s READ.** Stranger and `return_strand`-only
--        operator → `not_ops`; no caller → `not_signed_in`; the operator sees both sealed rows (the
--        belled one with `notified_at`, the young one without) and no unsealed or completed row.
--        Key set exact.
--   · C1 **THE PAUSE NOTICE IS ONCE PER 24 h PER OWNER PER EPISODE.** Two ticks in one transaction
--        → one row. The row aged 25 h → the next tick writes a second. And the EPISODE: the owner's
--        debt clears, the series produces a booking, a new block arrives two hours after the last
--        notice → the owner is told again (a bare 24 h window would have said nothing).
--   · D1 **THE OPERATOR'S ID IS NOT IN THE PARTY-READABLE BLOB.** A real `ops_resolve_return_tx`
--        leaves `bookings.return_force_evidence` with exactly {source, from_status, runner_stamped,
--        owner_stamped, resolved_at}, the journal row still carries `resolved_by`, and the owner —
--        reading `bookings` AS `authenticated` — finds the operator's uuid nowhere in the blob. The
--        repair: a pre-0224 blob (the key PRESENT first — an absence pin over an empty world proves
--        nothing) loses exactly that key and keeps every other; a second call returns 0; an array
--        blob is untouched.
--   · S1 **DEPLOYED SHAPE.** Every definer this file creates or re-declares has an in-body
--        `search_path`, and effective ACLs in both directions; the two lists take zero arguments;
--        in comment-STRIPPED source each list's roster gate precedes its read, arm ⓖ is locked and
--        bounded twice and takes the sweep's job lock before its first loop, the sweep calls arm ⓖ,
--        and all four consumers call `_custody_strand(`. The flag CHECK refuses 0. NO-FUNCTION /
--        NO-SOURCE arms fail loudly.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins — the harness cannot reach it) ───
--   · That a runner READS the strip truthfully. The gate's two new `waiting_on` words are asserted
--     here; the runner-home strip does not map them yet (0224 §0c) and no SQL pin can see a screen.
--   · The `lateral` status conjunct in the gate / `ops_gated_runners` is PERFORMANCE: §B returns no
--     row for any other status, so deleting it changes no answer. Not pinned — a pin could not tell.
--   · Arm ⓖ's both-NULL short-circuit is likewise not separately observable: §B answers 「not
--     stranded」 for every row when both thresholds are NULL. A1/A2's NULL arms prove the OUTCOME.
--   · The job-lock SKIP (a standalone arm ⓖ call while a real tick holds the lock) needs two
--     sessions; `90_race_check.sh` RL measures the sweep's lock and arm ⓖ takes the same key.
--     S1 pins that the lock is taken before the first loop.
--   · Nothing here pushes. `00_shim.sql` stubs `net.http_post`; the category is 245's subject.
--
-- ─── FIXTURE NOTES ───
--  ① Every count is SCOPED to this suite's own bookings and profiles. `bookings`, `notifications`
--     and both rosters are shared with every suite before this one.
--  ② 🔴 THIS SUITE SETS THE CUSTODY THRESHOLDS AND TICKS THE REAL SWEEP. The sweep is global and
--     batched (`limit 50`, ordered by due time), so this suite's strands are aged a MONTH (and A5's
--     a year) — older than anything another suite builds — so they sort first and cannot be
--     shadowed. Both thresholds, `payments_live_since` and the rosters are RESTORED at the end.
--  ③ One DO block = one transaction = one `now()`. A 「later tick」 is therefore simulated by moving
--     a row's `created_at` back, never by waiting (C1).
--  ④ `request.jwt.claim.sub` is set and cleared explicitly around every caller-shaped read; a
--     leftover claim would make `not_signed_in` unreachable and that arm would pass for the wrong
--     reason.
--
-- ─── MUTATION MAP — measured, never predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant CHAIN-GATED to
-- its harness run (`plant.py && harness.sh`), control observed clean FIRST.
set client_min_messages = warning;

-- ---------- suite-local fixtures ----------

-- A marketplace booking at `picked_up`: the handoff finished `p_ago` ago (both stamps), no run.
create or replace function t_cst_picked(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                        p_ago interval, p_club uuid default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at, club_session_id)
  values (p_owner, p_dog, p_runner, p_route, 'picked_up', now() - p_ago - interval '5 minutes', 5.0,
          9900, 15000, 0, 24900, 9900,
          now() - p_ago - interval '1 minute', now() - p_ago, p_club)
  returning id into v;
  return v;
end $$;

-- A marketplace run that STARTED `p_ago` ago and was never stopped. `p_with_run = false` builds the
-- legacy shape with no `runs` row (0087 §0's dead second statement) — the clock must fall back.
create or replace function t_cst_live(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                      p_ago interval, p_with_run boolean default true)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - p_ago - interval '5 minutes', 5.0,
          9900, 15000, 0, 24900, 9900,
          now() - p_ago - interval '2 minutes', now() - p_ago - interval '1 minute')
  returning id into v;
  if p_with_run then
    insert into runs (booking_id, started_at, trace) values (v, now() - p_ago, '[]'::jsonb);
  end if;
  return v;
end $$;

create or replace function t_cst_n(p_booking uuid, p_title text, p_profile uuid default null)
returns int language sql as $$
  select count(*)::int from notifications
   where ref_id = p_booking and title = p_title
     and (p_profile is null or profile_id = p_profile)
$$;

create or replace function t_cst_flags(p_start int, p_end int) returns void
language sql as $$
  update ops_flags set custody_start_strand_minutes = p_start,
                       custody_end_strand_minutes   = p_end,
                       updated_at = now()
   where id
$$;

-- `runner_work_gate` as the runner themself (the client's only legal call, 0116 §D ⓑ).
create or replace function t_cst_gate(p_runner uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_runner::text, true);
  begin
    v := runner_work_gate(p_runner);
  exception when others then v := jsonb_build_object('raised', sqlerrm);
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

-- An ops read as ONE caller: the rows keyed by booking id, OR the raise word — never both.
create or replace function t_cst_custody_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_object_agg(x.booking_id::text, to_jsonb(x)), '{}'::jsonb)
      into v from ops_stranded_custody() x;
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('rows', v);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_cst_sealed_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_object_agg(x.booking_id::text, to_jsonb(x)), '{}'::jsonb)
      into v from ops_sealed_unsettled() x;
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('rows', v);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- the quote the EDGE computes and hands to the resolver (a fixture, not a rule — 137 owns pricing)
create or replace function t_cst_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

-- the set (as a sorted text[]) of `p_ids` for which a row titled one of `p_titles` exists
create or replace function t_cst_belled(p_ids uuid[], p_titles text[]) returns text[]
language sql as $$
  select coalesce(array_agg(distinct nt.ref_id::text order by nt.ref_id::text), '{}')
    from notifications nt
   where nt.ref_id = any (p_ids) and nt.title = any (p_titles) and nt.kind = 'system'
$$;

do $$
declare
  -- people
  oo uuid; sx uuid; opsR uuid; opsP uuid;
  rrA uuid; rrB uuid; rrC uuid; rrD uuid; rrE uuid; rrF uuid; rrG uuid; rrH uuid;
  dg uuid; rt uuid; v_club uuid; v_sess uuid;
  -- A: custody fixtures
  bP uuid; bPlive uuid; bPclub uuid;           -- picked_up: a month old · five minutes · a club one
  bA uuid; bAnorun uuid; bAlive uuid; bAended uuid; bDone uuid;
  -- B: sealed fixtures
  bS8 uuid; bS8pre uuid; bS1 uuid;
  -- the titles, spelled once
  T_START     constant text := '러닝 시작이 멈춰 있어요';
  T_END       constant text := '러닝 종료가 멈춰 있어요';
  T_START_OPS constant text := '러닝 시작 좌초 — 확인 필요';
  T_END_OPS   constant text := '러닝 종료 좌초 — 확인 필요';
  T_SEAL_OPS  constant text := '정산 미완료 — 확인 필요';
  T_SEAL_PTY  constant text := '정산을 확인하고 있어요';
  B_START_RUNNER constant text := '인계는 끝났는데 러닝이 아직 시작되지 않았어요 — 앱에서 러닝을 시작해주세요';
  B_START_OWNER  constant text := '인계는 끝났는데 러닝이 아직 시작되지 않았어요 — 러너에게도 알렸어요';
  B_END_RUNNER   constant text := '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요 — 앱에서 러닝을 종료해주세요';
  B_END_OWNER    constant text := '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요 — 러너에게도 알렸어요';
  CUSTODY_KEYS constant text[] := array['booking_id','dog_name','owner_name','runner_name','status','shape',
                                        'since_at','due_at','minutes_overdue','strand_minutes','notified_at'];
  SEALED_KEYS  constant text[] := array['booking_id','dog_name','owner_name','runner_name','status',
                                        'run_ended_at','settlement_ready_at','minutes_sealed','notified_at'];
  -- saved world
  v_save_live timestamptz; v_save_strand int;
  -- scratch
  v jsonb; v2 jsonb; v_bad text; v_msg text; v_n int; v_n2 int; v_roster int; v_proster int;
  v_txt text; v_arr text[]; v_arr2 text[]; v_ids uuid[]; r record; v_src text; v_ev jsonb;
  -- A5
  a5_told1 int; a5_told2 int; a5_ops1 int; a5_ops2 int; a5_ops3 int; a5_ops4 int; a5_retold int;
  a5_last_told1 int; a5_last_told2 int; a5_err text; a5_n int;
  a5_ids uuid[]; a5_last uuid; a5_prev uuid[];
begin
  perform set_config('request.jwt.claim.sub', '', true);                                        -- ④
  select f.payments_live_since, f.return_strand_minutes into v_save_live, v_save_strand
    from ops_flags f where f.id;
  -- the arm this suite measures must start OFF — the shipped state (fixture note ②)
  perform t_cst_flags(null, null);
  update ops_flags set return_strand_minutes = null where id;

  oo   := t_user('cst_owner',   'owner');
  sx   := t_user('cst_stranger','owner');
  opsR := t_user('cst_ops_ret', 'owner');
  opsP := t_user('cst_ops_pay', 'owner');
  rrA  := t_user('cst_rA', 'runner'); rrB := t_user('cst_rB', 'runner'); rrC := t_user('cst_rC', 'runner');
  rrD  := t_user('cst_rD', 'runner'); rrE := t_user('cst_rE', 'runner'); rrF := t_user('cst_rF', 'runner');
  rrG  := t_user('cst_rG', 'runner'); rrH := t_user('cst_rH', 'runner');
  dg   := t_dog(oo, '좌초견');
  rt   := t_route('cst 코스');
  insert into ops_recipients (profile_id, event_class, active) values (opsR, 'return_strand', true)
  on conflict (profile_id, event_class) do update set active = true;
  insert into ops_recipients (profile_id, event_class, active) values (opsP, 'payout_due', true)
  on conflict (profile_id, event_class) do update set active = true;
  insert into clubs (name, district, host_profile_id) values ('cst 클럽', '반포동', rrC) returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, rrC, now() - interval '30 days', 'cst 집결지') returning id into v_sess;

  -- ── the custody world (fixture note ②: a MONTH old so nothing another suite built sorts first)
  bP      := t_cst_picked(oo, rrA, dg, rt, interval '30 days');
  bPlive  := t_cst_picked(oo, rrB, dg, rt, interval '5 minutes');
  bPclub  := t_cst_picked(oo, rrC, dg, rt, interval '30 days', v_sess);
  bA      := t_cst_live(oo, rrD, dg, rt, interval '30 days');
  bAnorun := t_cst_live(oo, rrE, dg, rt, interval '30 days', false);
  bAlive  := t_cst_live(oo, rrH, dg, rt, interval '5 minutes');
  -- a run that ENDED a month ago with only the runner's stamp: arm ⓑ-②'s subject (it alarms, never
  -- moves status), so it stays `active` and is exactly where the custody shape and the return
  -- shape DISAGREE — `run_ended_at` is the whole difference (the fixture-agreement law)
  bAended := t_cst_live(oo, rrF, dg, rt, interval '30 days');
  update runs set ended_at = now() - interval '30 days' + interval '40 minutes' where booking_id = bAended;
  update bookings set run_ended_at = now() - interval '30 days' + interval '40 minutes',
                      runner_confirmed_return_at = now() - interval '30 days' + interval '45 minutes'
   where id = bAended;
  -- a completed booking whose return stamps are missing: gates nobody (no arm names `completed`)
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (oo, dg, rrG, rt, 'completed', now() - interval '30 days', 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bDone;

  select count(*)::int into v_roster from ops_recipients_for('return_strand');
  select count(*)::int into v_proster from ops_recipients_for('payout_due');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-A4 ①] the read BEFORE any strand exists — the words a stranger gets now must equal the
  -- words they get after three are belled (below), or the refusal is an existence oracle
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v  := t_cst_custody_as(sx);
  v2 := t_cst_custody_as(opsP);
  v_arr := array[coalesce(v->>'raised', 'ROWS'), coalesce(v2->>'raised', 'ROWS'),
                 coalesce(t_cst_custody_as(null)->>'raised', 'ROWS')];

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-A1] the start strand
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_roster < 1 then v_bad := v_bad || ' FIXTURE: the return_strand roster is empty (「one per recipient」 would pass by writing nothing)'; end if;
    -- ⓪ thresholds NULL — the shipped state — and a REAL tick: nothing, and the arm reads nothing
    perform sweep_run_end_recovery();
    if _sweep_custody_strands() is distinct from 0 then v_bad := v_bad || ' NULL-off: arm ⓖ returned non-zero'; end if;
    if t_cst_n(bP, T_START) + t_cst_n(bP, T_START_OPS) is distinct from 0
      then v_bad := v_bad || ' NULL-off: a month-old pickup was told with the threshold NULL (' || t_cst_n(bP, T_START) || '/' || t_cst_n(bP, T_START_OPS) || ')'; end if;

    -- ① the threshold set: ONE tick
    perform t_cst_flags(60, null);
    perform sweep_run_end_recovery();
    if t_cst_n(bP, T_START, oo) is distinct from 1 then v_bad := v_bad || ' tick1 owner rows=' || t_cst_n(bP, T_START, oo); end if;
    if t_cst_n(bP, T_START, rrA) is distinct from 1 then v_bad := v_bad || ' tick1 runner rows=' || t_cst_n(bP, T_START, rrA); end if;
    if t_cst_n(bP, T_START) is distinct from 2 then v_bad := v_bad || ' tick1 party rows=' || t_cst_n(bP, T_START) || ' (a third party was told?)'; end if;
    if (select body from notifications where ref_id = bP and title = T_START and profile_id = rrA) is distinct from B_START_RUNNER
      then v_bad := v_bad || ' the runner was not asked to START'; end if;
    if (select body from notifications where ref_id = bP and title = T_START and profile_id = oo) is distinct from B_START_OWNER
      then v_bad := v_bad || ' the owner got the wrong sentence'; end if;
    if exists (select 1 from notifications where ref_id = bP and title = T_START and kind::text is distinct from 'booking')
      then v_bad := v_bad || ' a party row is not kind=booking'; end if;
    if t_cst_n(bP, T_START_OPS) is distinct from v_roster
      then v_bad := v_bad || ' tick1 ops rows=' || t_cst_n(bP, T_START_OPS) || ' roster=' || v_roster; end if;
    if exists (select 1 from ops_recipients_for('return_strand') rc(pid) where t_cst_n(bP, T_START_OPS, rc.pid) is distinct from 1)
      then v_bad := v_bad || ' a return_strand recipient did not get exactly one ops row'; end if;
    if exists (select 1 from notifications where ref_id = bP and title = T_START_OPS and kind::text is distinct from 'system')
      then v_bad := v_bad || ' an ops row is not kind=system'; end if;
    -- 0084 §E: no identifier in an ops body
    if exists (select 1 from notifications where ref_id = bP and title = T_START_OPS
                and (body ~ '[0-9a-f]{8}-[0-9a-f]{4}' or body ~ '[0-9]'))
      then v_bad := v_bad || ' an ops body carries an id or a number'; end if;
    -- ② a SECOND tick: the delta is zero
    v_n := t_cst_n(bP, T_START); v_n2 := t_cst_n(bP, T_START_OPS);
    perform sweep_run_end_recovery();
    if t_cst_n(bP, T_START) - v_n is distinct from 0 then v_bad := v_bad || ' tick2 re-told the parties (+' || (t_cst_n(bP, T_START) - v_n) || ')'; end if;
    if t_cst_n(bP, T_START_OPS) - v_n2 is distinct from 0 then v_bad := v_bad || ' tick2 re-rang ops (+' || (t_cst_n(bP, T_START_OPS) - v_n2) || ')'; end if;
    -- ③ the controls: inside the threshold, a club custody, and the other shape
    if t_cst_n(bPlive, T_START) + t_cst_n(bPlive, T_START_OPS) is distinct from 0
      then v_bad := v_bad || ' a five-minute-old pickup was told (the clock does not matter?)'; end if;
    if t_cst_n(bPclub, T_START) + t_cst_n(bPclub, T_START_OPS) is distinct from 0
      then v_bad := v_bad || ' a CLUB pickup was told (clubs run their own custody machine)'; end if;
    if t_cst_n(bP, T_END) + t_cst_n(bP, T_END_OPS) is distinct from 0
      then v_bad := v_bad || ' a pickup got an END-shape row'; end if;
    if v_bad = '' then call _pass('cst','0224-A1 인계 뒤 시작되지 않은 커스터디 — 임계값이 NULL이면 실제 틱이 한 달 된 픽업에 대해 아무것도 쓰지 않고, 설정되면 보호자 1·러너 1(각자의 문장)·return_strand 수신자 전원에게 system 1행, 두 번째 틱은 델타 0; 임계값 안의 픽업·클럽 픽업은 0, 종료 모양 행도 0');
    else v_msg := v_bad; call _fail('cst','0224-A1 start strand', v_msg); end if;
  exception when others then call _fail('cst','0224-A1 start strand', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-A2] the end strand
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓪ the END threshold still NULL (the start one is set): an unstopped month-old run is not told
    perform sweep_run_end_recovery();
    if t_cst_n(bA, T_END) + t_cst_n(bA, T_END_OPS) + t_cst_n(bAnorun, T_END) is distinct from 0
      then v_bad := v_bad || ' NULL-off: an unstopped run was told with the end threshold NULL'; end if;
    -- ① set it: one tick
    perform t_cst_flags(60, 60);
    perform sweep_run_end_recovery();
    for r in select unnest(array[bA, bAnorun]) as id, unnest(array[rrD, rrE]) as rr loop
      if t_cst_n(r.id, T_END, oo) is distinct from 1 then v_bad := v_bad || ' ' || r.id || ' owner rows=' || t_cst_n(r.id, T_END, oo); end if;
      if t_cst_n(r.id, T_END, r.rr) is distinct from 1 then v_bad := v_bad || ' ' || r.id || ' runner rows=' || t_cst_n(r.id, T_END, r.rr); end if;
      if (select body from notifications where ref_id = r.id and title = T_END and profile_id = r.rr) is distinct from B_END_RUNNER
        then v_bad := v_bad || ' the runner was not asked to STOP'; end if;
      if (select body from notifications where ref_id = r.id and title = T_END and profile_id = oo) is distinct from B_END_OWNER
        then v_bad := v_bad || ' the owner got the wrong end sentence'; end if;
      if t_cst_n(r.id, T_END_OPS) is distinct from v_roster
        then v_bad := v_bad || ' ops rows=' || t_cst_n(r.id, T_END_OPS) || ' roster=' || v_roster; end if;
      if t_cst_n(r.id, T_START) + t_cst_n(r.id, T_START_OPS) is distinct from 0
        then v_bad := v_bad || ' an unstopped run got a START-shape row'; end if;
    end loop;
    -- ② a second tick: delta zero
    v_n := t_cst_n(bA, T_END) + t_cst_n(bAnorun, T_END); v_n2 := t_cst_n(bA, T_END_OPS) + t_cst_n(bAnorun, T_END_OPS);
    perform sweep_run_end_recovery();
    if t_cst_n(bA, T_END) + t_cst_n(bAnorun, T_END) - v_n is distinct from 0 then v_bad := v_bad || ' tick2 re-told the parties'; end if;
    if t_cst_n(bA, T_END_OPS) + t_cst_n(bAnorun, T_END_OPS) - v_n2 is distinct from 0 then v_bad := v_bad || ' tick2 re-rang ops'; end if;
    -- ③ controls: a run five minutes old; a run that ENDED (arms ⓑ/ⓕ's subject — the disagreement row)
    if t_cst_n(bAlive, T_END) + t_cst_n(bAlive, T_END_OPS) is distinct from 0
      then v_bad := v_bad || ' a five-minute-old run was told'; end if;
    if t_cst_n(bAended, T_END) + t_cst_n(bAended, T_END_OPS) is distinct from 0
      then v_bad := v_bad || ' a run that ENDED got a custody row (run_ended_at is the whole difference)'; end if;
    if (select b.status::text from bookings b where b.id = bAended) is distinct from 'active'
      then v_bad := v_bad || ' FIXTURE: the ended row left active (' || (select b.status::text from bookings b where b.id = bAended) || ')'; end if;
    if v_bad = '' then call _pass('cst','0224-A2 멈추지 않은 러닝 — 종료 임계값이 NULL이면 0, 설정되면 명목 종료 시각 기준으로 보호자 1·러너 1·ops 수신자 전원 1, runs 행이 없는 러닝도(시계가 폴백한다), 두 번째 틱 델타 0; 5분 된 러닝과 이미 종료된 러닝(반환 미확인 — ⓑ/ⓕ의 몫)은 0');
    else v_msg := v_bad; call _fail('cst','0224-A2 end strand', v_msg); end if;
  exception when others then call _fail('cst','0224-A2 end strand', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-A3] the work gate — thresholds are (60, 60) here
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v := t_cst_gate(rrA);
    if (v->>'gated')::boolean is not true or v->>'waiting_on' is distinct from 'start_run'
       or v->>'exit' is distinct from 'runner_start_run' or v->>'booking_id' is distinct from bP::text
      then v_bad := v_bad || ' stranded pickup: ' || v::text; end if;
    v := t_cst_gate(rrD);
    if (v->>'gated')::boolean is not true or v->>'waiting_on' is distinct from 'end_run'
       or v->>'exit' is distinct from 'runner_end_run' or v->>'booking_id' is distinct from bA::text
      then v_bad := v_bad || ' unstopped run: ' || v::text; end if;
    v := t_cst_gate(rrE);
    if (v->>'gated')::boolean is not true or v->>'waiting_on' is distinct from 'end_run'
      then v_bad := v_bad || ' unstopped run with no runs row: ' || v::text; end if;
    -- 0092 §3's line: a LIVE custody is not a strand
    v := t_cst_gate(rrB);
    if (v->>'gated')::boolean is not false then v_bad := v_bad || ' a five-minute-old pickup GATED its runner: ' || v::text; end if;
    v := t_cst_gate(rrH);
    if (v->>'gated')::boolean is not false then v_bad := v_bad || ' a five-minute-old run GATED its runner: ' || v::text; end if;
    -- the existing arm, unmoved: runner stamped, owner has not — `owner` / `owner_confirm_return`
    v := t_cst_gate(rrF);
    if (v->>'gated')::boolean is not true or v->>'waiting_on' is distinct from 'owner'
       or v->>'exit' is distinct from 'owner_confirm_return'
      then v_bad := v_bad || ' the ended run''s existing arm moved: ' || v::text; end if;
    v := t_cst_gate(rrG);
    if (v->>'gated')::boolean is not false then v_bad := v_bad || ' a completed booking gated: ' || v::text; end if;
    v := t_cst_gate(rrC);
    if (v->>'gated')::boolean is not false then v_bad := v_bad || ' a CLUB pickup gated: ' || v::text; end if;
    -- ops_gated_runners lists exactly the gated custody rows, with the new words
    if (select count(*) from ops_gated_runners() g where g.booking_id = bP and g.runner_id = rrA and g.waiting_on = 'start_run') is distinct from 1::bigint
      then v_bad := v_bad || ' ops_gated_runners: the stranded pickup is not listed as start_run'; end if;
    if (select count(*) from ops_gated_runners() g where g.booking_id = bA and g.waiting_on = 'end_run') is distinct from 1::bigint
      then v_bad := v_bad || ' ops_gated_runners: the unstopped run is not listed as end_run'; end if;
    if exists (select 1 from ops_gated_runners() g where g.booking_id in (bPlive, bAlive, bPclub, bDone))
      then v_bad := v_bad || ' ops_gated_runners: lists a live / club / completed row'; end if;
    if ((select g.remedy from ops_gated_runners() g where g.booking_id = bP) ~ 'start_run') is not true
      then v_bad := v_bad || ' ops_gated_runners: the start strand''s remedy does not name start_run'; end if;
    -- ⓪ the SAME rows with the thresholds NULL: nobody is gated by custody
    perform t_cst_flags(null, null);
    if (t_cst_gate(rrA)->>'gated')::boolean is not false then v_bad := v_bad || ' NULL-off: the pickup still gates'; end if;
    if (t_cst_gate(rrD)->>'gated')::boolean is not false then v_bad := v_bad || ' NULL-off: the unstopped run still gates'; end if;
    if exists (select 1 from ops_gated_runners() g where g.booking_id in (bP, bA, bAnorun))
      then v_bad := v_bad || ' NULL-off: ops_gated_runners still lists a custody row'; end if;
    if (t_cst_gate(rrF)->>'waiting_on') is distinct from 'owner' then v_bad := v_bad || ' NULL-off moved the existing arm'; end if;
    perform t_cst_flags(60, 60);
    if v_bad = '' then call _pass('cst','0224-A3 작업 게이트 — 좌초된 픽업은 start_run/runner_start_run, 멈추지 않은 러닝은 end_run/runner_end_run(runs 행이 없어도), 같은 행이 임계값 NULL이면 gated=false; 5분 된 픽업·러닝은 막지 않는다(0092 §3); 기존 팔은 그대로 owner/owner_confirm_return, completed·클럽은 0; ops_gated_runners가 같은 행을 같은 낱말로');
    else v_msg := v_bad; call _fail('cst','0224-A3 work gate', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('cst','0224-A3 work gate', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-A4] ops_stranded_custody — the roster's read, and the sweep's own set
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ① the refusals, BEFORE (captured above) and AFTER three strands were belled — identical words
    if v_arr is distinct from array['not_ops', 'not_ops', 'not_signed_in']
      then v_bad := v_bad || ' before any strand: ' || array_to_string(v_arr, '/'); end if;
    v_arr2 := array[coalesce(t_cst_custody_as(sx)->>'raised', 'ROWS'), coalesce(t_cst_custody_as(opsP)->>'raised', 'ROWS'),
                    coalesce(t_cst_custody_as(null)->>'raised', 'ROWS')];
    if v_arr2 is distinct from v_arr then v_bad := v_bad || ' the refusal CHANGED once strands existed: ' || array_to_string(v_arr2, '/'); end if;
    -- ② the operator's rows == the sweep's belled set (this suite's bookings only)
    v_ids := array[bP, bPlive, bPclub, bA, bAnorun, bAlive, bAended, bDone];
    v := t_cst_custody_as(opsR);
    if v ? 'raised' then v_bad := v_bad || ' the operator was refused: ' || (v->>'raised');
    else
      select coalesce(array_agg(k order by k), '{}') into v_arr
        from jsonb_object_keys(v->'rows') k where k::uuid = any (v_ids);
      v_arr2 := t_cst_belled(v_ids, array[T_START_OPS, T_END_OPS]);
      if v_arr is distinct from v_arr2 then v_bad := v_bad || ' list ' || array_to_string(v_arr, ',') || ' ≠ belled ' || array_to_string(v_arr2, ','); end if;
      if array_length(v_arr2, 1) is distinct from 3 then v_bad := v_bad || ' FIXTURE: the sweep belled ' || coalesce(array_length(v_arr2, 1), 0) || ' of mine, expected 3'; end if;
      if (v->'rows' ? bP::text and v->'rows' ? bA::text and v->'rows' ? bAnorun::text) is not true
        then v_bad := v_bad || ' a stranded row is missing by name'; end if;
      if ((v->'rows') ?| array[bPlive::text, bPclub::text, bAlive::text, bAended::text, bDone::text]) is not false
        then v_bad := v_bad || ' a live / club / ended / completed row is listed'; end if;
      -- ③ the facts are the row's
      if v->'rows'->bP::text->>'shape' is distinct from 'start_run' or v->'rows'->bA::text->>'shape' is distinct from 'end_run'
        then v_bad := v_bad || ' wrong shape'; end if;
      if v->'rows'->bP::text->>'status' is distinct from 'picked_up' then v_bad := v_bad || ' status not raw'; end if;
      if v->'rows'->bP::text->>'notified_at' is null then v_bad := v_bad || ' notified_at NULL on a belled row'; end if;
      if (v->'rows'->bP::text->>'strand_minutes')::int is distinct from 60 then v_bad := v_bad || ' strand_minutes not the flag'; end if;
      if (v->'rows'->bP::text->>'dog_name') is distinct from '좌초견' or (v->'rows'->bP::text->>'runner_name') is distinct from 'cst_rA'
        then v_bad := v_bad || ' names are not the row''s'; end if;
      if ((v->'rows'->bP::text->>'minutes_overdue')::int >= 60 * 24 * 29) is not true then v_bad := v_bad || ' minutes_overdue is not a month'; end if;
      -- ④ the key set is exactly the declared columns — a column added later reddens
      select coalesce(array_agg(k order by k), '{}') into v_arr from jsonb_object_keys(v->'rows'->bP::text) k;
      select array_agg(k order by k) into v_arr2 from unnest(CUSTODY_KEYS) k;
      if v_arr is distinct from v_arr2 then v_bad := v_bad || ' key set ' || array_to_string(v_arr, ','); end if;
    end if;
    -- ⑤ thresholds back to NULL: the belled rows stay, nothing is invented
    perform t_cst_flags(null, null);
    v := t_cst_custody_as(opsR);
    select coalesce(array_agg(k order by k), '{}') into v_arr
      from jsonb_object_keys(coalesce(v->'rows', '{}')) k where k::uuid = any (v_ids);
    if v_arr is distinct from t_cst_belled(v_ids, array[T_START_OPS, T_END_OPS])
      then v_bad := v_bad || ' NULL: the list is not exactly the belled rows: ' || array_to_string(v_arr, ','); end if;
    if v->'rows'->bP::text->>'due_at' is not null then v_bad := v_bad || ' NULL: due_at invented'; end if;
    perform t_cst_flags(60, 60);
    if v_bad = '' then call _pass('cst','0224-A4 ops_stranded_custody — 낯선 이와 payout_due 전용 운영자는 not_ops, 호출자 없음은 not_signed_in, 좌초가 생기기 전과 후의 낱말이 같다; return_strand 운영자의 목록 = 스윕이 실제로 울린 집합(이 스위트 예약 한정), 행의 사실은 행의 것, 키 집합은 선언한 열한 개; 임계값을 NULL로 돌리면 울린 행만 남고 마감은 만들어 내지 않는다');
    else v_msg := v_bad; call _fail('cst','0224-A4 custody read', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('cst','0224-A4 custody read', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-A5] an empty roster cannot hold the parties' notice hostage — measured, then ROLLED BACK
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- Everything between `begin` and the sentinel raise is undone by the raise: the shared roster, the
  -- 51 fixture bookings and every row the ticks wrote. The measurements survive in variables.
  a5_err := null;
  begin
    update ops_recipients set active = false where event_class = 'return_strand' and active;
    perform t_cst_flags(60, 60);
    a5_ids := '{}';
    -- fifty pickups a YEAR old, then the fifty-first — the youngest of them, so it sorts LAST
    for a5_n in 1..50 loop
      a5_ids := a5_ids || t_cst_picked(oo, rrA, dg, rt, interval '400 days' + make_interval(mins => a5_n));
    end loop;
    a5_last := t_cst_picked(oo, rrA, dg, rt, interval '399 days');
    perform _sweep_custody_strands();
    select count(*) into a5_told1 from unnest(a5_ids) i where t_cst_n(i, T_START, rrA) = 1;
    a5_last_told1 := t_cst_n(a5_last, T_START, rrA);
    select count(*) into a5_ops1 from notifications where ref_id = any (a5_ids || a5_last) and title = T_START_OPS;
    perform _sweep_custody_strands();
    select count(*) into a5_told2 from unnest(a5_ids) i where t_cst_n(i, T_START, rrA) = 1;
    a5_last_told2 := t_cst_n(a5_last, T_START, rrA);
    select count(*) into a5_ops2 from notifications where ref_id = any (a5_ids || a5_last) and title = T_START_OPS;
    -- one operator subscribes: ONE row per strand on the next ticks (batch 50 ⇒ two ticks for 51)
    update ops_recipients set active = true where profile_id = opsR and event_class = 'return_strand';
    perform _sweep_custody_strands();
    perform _sweep_custody_strands();
    select count(*) into a5_ops3 from notifications where ref_id = any (a5_ids || a5_last) and title = T_START_OPS and profile_id = opsR;
    select count(*) into a5_ops4 from notifications where ref_id = any (a5_ids || a5_last) and title = T_START_OPS;
    select count(*) into a5_retold from notifications where ref_id = any (a5_ids || a5_last) and title = T_START;
    raise exception 'cst-a5-rollback';
  exception when others then
    if sqlerrm is distinct from 'cst-a5-rollback' then a5_err := sqlerrm; end if;
  end;
  begin
    v_bad := '';
    if a5_err is not null then v_bad := v_bad || ' raised: ' || a5_err; end if;
    if a5_told1 is distinct from 50::bigint then v_bad := v_bad || ' tick1 told ' || coalesce(a5_told1::text, 'NULL') || ' of the fifty (batch 50)'; end if;
    if a5_last_told1 is distinct from 0 then v_bad := v_bad || ' FIXTURE: the 51st was told on tick 1 (it must sort last)'; end if;
    if a5_ops1 is distinct from 0::bigint or a5_ops2 is distinct from 0::bigint then v_bad := v_bad || ' an ops row was written to an EMPTY roster'; end if;
    if a5_last_told2 is distinct from 1 then v_bad := v_bad || ' 🔴 tick2 did not tell the 51st (a PENDING ops half shadowed it)'; end if;
    if a5_told2 is distinct from 50::bigint then v_bad := v_bad || ' tick2 changed the first fifty (' || coalesce(a5_told2::text, 'NULL') || ')'; end if;
    if a5_ops3 is distinct from 51::bigint then v_bad := v_bad || ' after subscribing: ' || coalesce(a5_ops3::text, 'NULL') || ' ops rows to the operator (51 expected)'; end if;
    if a5_ops4 is distinct from 51::bigint then v_bad := v_bad || ' after subscribing: ' || coalesce(a5_ops4::text, 'NULL') || ' ops rows in total'; end if;
    if a5_retold is distinct from 102::bigint then v_bad := v_bad || ' parties rows=' || coalesce(a5_retold::text, 'NULL') || ' (51 × 2 — nobody told twice)'; end if;
    -- the rollback really happened (the shared roster is as other suites left it)
    if exists (select 1 from bookings where id = a5_last) then v_bad := v_bad || ' FIXTURE: the A5 world was not rolled back'; end if;
    if (select count(*)::int from ops_recipients_for('return_strand')) is distinct from v_roster
      then v_bad := v_bad || ' FIXTURE: the return_strand roster was not restored'; end if;
    if v_bad = '' then call _pass('cst','0224-A5 빈 명부는 당사자 통지를 인질로 잡지 못한다 — return_strand가 비어 있을 때 좌초 51건: 첫 틱에 50건, 둘째 틱에 51번째까지 당사자 통지(51건 모두 ops가 PENDING인데도); 빈 명부에는 ops 행 0; 운영자 하나가 구독하면 좌초당 정확히 1행, 당사자는 두 번 듣지 않는다 (측정 후 롤백)');
    else v_msg := v_bad; call _fail('cst','0224-A5 empty roster', v_msg); end if;
  exception when others then call _fail('cst','0224-A5 empty roster', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-B1] the sealed-but-unsettled run finally pages an operator
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_proster < 1 then v_bad := v_bad || ' FIXTURE: the payout_due roster is empty'; end if;
    bS8 := t_cst_live(oo, rrA, dg, rt, interval '10 hours');
    update runs set ended_at = now() - interval '9 hours' where booking_id = bS8;
    update bookings set run_ended_at = now() - interval '9 hours',
                        runner_confirmed_return_at = now() - interval '9 hours',
                        owner_confirmed_return_at  = now() - interval '8 hours',
                        settlement_ready_at        = now() - interval '8 hours' where id = bS8;
    -- the pre-0224 row: its PARTIES were already told (the alarm row exists), its operator never was
    bS8pre := t_cst_live(oo, rrA, dg, rt, interval '10 hours');
    update runs set ended_at = now() - interval '9 hours' where booking_id = bS8pre;
    update bookings set run_ended_at = now() - interval '9 hours',
                        settlement_ready_at = now() - interval '8 hours' where id = bS8pre;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (oo, 'booking', T_SEAL_PTY, 'cst pre-0224 alarm', bS8pre);
    -- sealed an hour ago: inside SEAL_ALARM_AFTER
    bS1 := t_cst_live(oo, rrA, dg, rt, interval '2 hours');
    update runs set ended_at = now() - interval '90 minutes' where booking_id = bS1;
    update bookings set run_ended_at = now() - interval '90 minutes',
                        settlement_ready_at = now() - interval '1 hour' where id = bS1;
    if t_cst_n(bS8, T_SEAL_OPS) + t_cst_n(bS8pre, T_SEAL_OPS) is distinct from 0 then v_bad := v_bad || ' FIXTURE: a bell before the tick'; end if;

    perform sweep_run_end_recovery();
    if t_cst_n(bS8, T_SEAL_OPS) is distinct from v_proster then v_bad := v_bad || ' ops rows=' || t_cst_n(bS8, T_SEAL_OPS) || ' roster=' || v_proster; end if;
    if exists (select 1 from ops_recipients_for('payout_due') rc(pid) where t_cst_n(bS8, T_SEAL_OPS, rc.pid) is distinct from 1)
      then v_bad := v_bad || ' a payout_due recipient did not get exactly one row'; end if;
    if exists (select 1 from notifications where ref_id = bS8 and title = T_SEAL_OPS
                and (kind::text is distinct from 'system' or body ~ '[0-9]'))
      then v_bad := v_bad || ' an ops row is not system, or its body carries a number'; end if;
    if exists (select 1 from notifications nt where nt.ref_id = bS8 and nt.title = T_SEAL_OPS
                and nt.profile_id not in (select rc.pid from ops_recipients_for('payout_due') rc(pid)))
      then v_bad := v_bad || ' an ops row went to someone off the roster'; end if;
    -- the parties' alarm is 0083's, unchanged — the control that this tick really ran arm ⓐ
    if t_cst_n(bS8, T_SEAL_PTY) is distinct from 2 then v_bad := v_bad || ' party alarm rows=' || t_cst_n(bS8, T_SEAL_PTY) || ' (2 expected)'; end if;
    if t_cst_n(bS8pre, T_SEAL_OPS) is distinct from v_proster
      then v_bad := v_bad || ' 🔴 a row whose parties were told before 0224 never pages ops (' || t_cst_n(bS8pre, T_SEAL_OPS) || ')'; end if;
    if t_cst_n(bS8pre, T_SEAL_PTY) is distinct from 1 then v_bad := v_bad || ' the pre-0224 party alarm was re-sent'; end if;
    if t_cst_n(bS1, T_SEAL_OPS) + t_cst_n(bS1, T_SEAL_PTY) is distinct from 0 then v_bad := v_bad || ' a row sealed an hour ago was belled'; end if;
    v_n := t_cst_n(bS8, T_SEAL_OPS) + t_cst_n(bS8pre, T_SEAL_OPS);
    perform sweep_run_end_recovery();
    if t_cst_n(bS8, T_SEAL_OPS) + t_cst_n(bS8pre, T_SEAL_OPS) - v_n is distinct from 0 then v_bad := v_bad || ' tick2 re-rang'; end if;
    if (select b.status::text from bookings b where b.id = bS8) is distinct from 'active'
      then v_bad := v_bad || ' the alarm MOVED the sealed row''s status (it must stay payable)'; end if;
    if v_bad = '' then call _pass('cst','0224-B1 봉인됐지만 정산 안 된 러닝 — SEAL_ALARM_AFTER가 지나면 payout_due 수신자 전원에게 system 1행(본문에 id·숫자 없음), 당사자 알람은 그대로 2행, 1시간 된 봉인은 0, 두 번째 틱 델타 0, 상태 무이동; 0224 이전에 당사자만 들은 행도 운영자 종은 한 번 울린다(자기 제목의 1회성)');
    else v_msg := v_bad; call _fail('cst','0224-B1 sealed ops bell', v_msg); end if;
  exception when others then call _fail('cst','0224-B1 sealed ops bell', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-B2] what the writers WROTE is ledgered
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select coalesce(array_agg(distinct nt.title order by nt.title), '{}') into v_arr
      from notifications nt
     where nt.kind = 'system' and nt.ref_id = any (array[bP, bA, bAnorun, bS8, bS8pre]);
    select array_agg(t order by t) into v_arr2 from unnest(array[T_START_OPS, T_END_OPS, T_SEAL_OPS]) t;
    if v_arr is distinct from v_arr2 then v_bad := v_bad || ' the deployed writers wrote ' || array_to_string(v_arr, ' | '); end if;
    foreach v_txt in array v_arr loop
      if (v_txt = any (_noti_ops_titles())) is not true then v_bad := v_bad || ' NOT LEDGERED: 「' || v_txt || '」'; end if;
      if _noti_push_category('system'::noti_kind, v_txt) is distinct from 'ops' then v_bad := v_bad || ' not the ops category: 「' || v_txt || '」'; end if;
      if (v_txt = any (_noti_urgent_noti_titles())) is not false then v_bad := v_bad || ' in the urgent family: 「' || v_txt || '」'; end if;
    end loop;
    select count(*) into v_n from (select distinct unnest(_noti_ops_titles())) s;
    if v_n is distinct from coalesce(array_length(_noti_ops_titles(), 1), -1) then v_bad := v_bad || ' the ledger has duplicates'; end if;
    if v_bad = '' then call _pass('cst','0224-B2 배포된 작성자가 실제로 쓴 system 제목(이 스위트 예약 한정) 셋이 정확히 새 제목 셋이고, 셋 모두 _noti_ops_titles에 있으며 ops 범주로 분류되고 긴급 가족이 아니다; 원장에 중복 없음 — 목록 사본끼리가 아니라 작성자의 출력과 비교');
    else v_msg := v_bad; call _fail('cst','0224-B2 titles ledgered', v_msg); end if;
  exception when others then call _fail('cst','0224-B2 titles ledgered', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-B3] ops_sealed_unsettled — payout_due's read
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_arr := array[coalesce(t_cst_sealed_as(sx)->>'raised', 'ROWS'), coalesce(t_cst_sealed_as(opsR)->>'raised', 'ROWS'),
                   coalesce(t_cst_sealed_as(null)->>'raised', 'ROWS')];
    if v_arr is distinct from array['not_ops', 'not_ops', 'not_signed_in']
      then v_bad := v_bad || ' refusals: ' || array_to_string(v_arr, '/'); end if;
    v := t_cst_sealed_as(opsP);
    if v ? 'raised' then v_bad := v_bad || ' the operator was refused: ' || (v->>'raised');
    else
      if (v->'rows' ? bS8::text and v->'rows' ? bS1::text and v->'rows' ? bS8pre::text) is not true
        then v_bad := v_bad || ' a sealed row is missing'; end if;
      if ((v->'rows') ?| array[bA::text, bAended::text, bDone::text, bP::text]) is not false
        then v_bad := v_bad || ' an unsealed / completed row is listed'; end if;
      if v->'rows'->bS8::text->>'notified_at' is null then v_bad := v_bad || ' the belled row has no notified_at'; end if;
      if v->'rows'->bS1::text->>'notified_at' is not null then v_bad := v_bad || ' the young row has a notified_at'; end if;
      if (v->'rows'->bS8::text->>'minutes_sealed')::int is distinct from 480 then v_bad := v_bad || ' minutes_sealed=' || coalesce(v->'rows'->bS8::text->>'minutes_sealed', 'NULL'); end if;
      if v->'rows'->bS8::text->>'status' is distinct from 'active' then v_bad := v_bad || ' status not raw'; end if;
      select coalesce(array_agg(k order by k), '{}') into v_arr from jsonb_object_keys(v->'rows'->bS8::text) k;
      select array_agg(k order by k) into v_arr2 from unnest(SEALED_KEYS) k;
      if v_arr is distinct from v_arr2 then v_bad := v_bad || ' key set ' || array_to_string(v_arr, ','); end if;
    end if;
    if v_bad = '' then call _pass('cst','0224-B3 ops_sealed_unsettled — 낯선 이와 return_strand 전용 운영자는 not_ops, 호출자 없음은 not_signed_in(명부는 서로 다르다); payout_due 운영자는 봉인된 행 셋을 모두 보고(울린 행에만 notified_at), 미봉인·완료 행은 보지 않는다; 키 집합 정확');
    else v_msg := v_bad; call _fail('cst','0224-B3 sealed read', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('cst','0224-B3 sealed read', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-C1] the recurring pause notice — once per 24 h per owner per episode
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  declare
    oRec uuid; dR uuid; dR2 uuid; bDebt uuid; pDebt uuid; s1 uuid; s2 uuid;
    v_kst_tomorrow int; c1 int; c2 int; c3 int; c4 int; c5 int; g1 int;
    T_PAUSE constant text := '반복 예약 일시 중지';
  begin
    v_bad := '';
    -- the card gate must be OFF so the ONLY block is the debt (fixture note ②; restored at the end)
    update ops_flags set payments_live_since = null where id;
    oRec  := t_user('cst_recur', 'owner');
    dR  := t_dog(oRec, '반복좌초견1');
    dR2 := t_dog(oRec, '반복좌초견2');
    -- debt: a cancelled booking with a fee and a FAILED server-minted charge (owner_has_unsettled_charge)
    insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee)
    values (oRec, dR, rt, 'cancelled_owner', now() - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900, 5000)
    returning id into bDebt;
    insert into payments (booking_id, order_id, amount, status, raw)
    values (bDebt, 'ord_cst_recur_debt', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee'))
    returning id into pDebt;
    if owner_has_unsettled_charge(oRec) is not true then v_bad := v_bad || ' FIXTURE: the debt gate does not see the debt'; end if;
    -- two series, tomorrow and the day after (KST), noon — both inside the 72 h window
    v_kst_tomorrow := (extract(dow from (now() at time zone 'Asia/Seoul'))::int + 1) % 7;
    insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
    values (oRec, dR,  jsonb_build_object('weekdays', jsonb_build_array(v_kst_tomorrow), 'time', '12:00'),
            5.0, 9900, 15000, 0, 24900, 9900, false) returning id into s1;
    insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
    values (oRec, dR2, jsonb_build_object('weekdays', jsonb_build_array((v_kst_tomorrow + 1) % 7), 'time', '12:00'),
            5.0, 9900, 15000, 0, 24900, 9900, false) returning id into s2;

    -- ① two ticks in one hour → one row (and nothing generated)
    perform generate_recurring_bookings();
    perform generate_recurring_bookings();
    select count(*) into c1 from notifications where profile_id = oRec and title = T_PAUSE;
    if c1 is distinct from 1 then v_bad := v_bad || ' two ticks wrote ' || c1 || ' pause rows (1 expected)'; end if;
    select count(*) into g1 from bookings where series_id in (s1, s2);
    if g1 is distinct from 0 then v_bad := v_bad || ' FIXTURE: a blocked owner got ' || g1 || ' booking(s)'; end if;
    if exists (select 1 from notifications where profile_id = oRec and title = T_PAUSE and ref_id is not null)
      then v_bad := v_bad || ' the pause row gained a ref (notification-route pins NULL)'; end if;
    -- ② the window expires → a second row
    update notifications set created_at = now() - interval '25 hours' where profile_id = oRec and title = T_PAUSE;
    perform generate_recurring_bookings();
    select count(*) into c2 from notifications where profile_id = oRec and title = T_PAUSE;
    if c2 - c1 is distinct from 1 then v_bad := v_bad || ' after 25 h the next tick wrote ' || (c2 - c1) || ' (1 expected)'; end if;
    -- ③ THE EPISODE: the latest notice is two hours old; the debt clears; the series produce bookings
    update notifications set created_at = now() - interval '2 hours'
     where profile_id = oRec and title = T_PAUSE and created_at > now() - interval '24 hours';
    delete from payments where id = pDebt;
    perform generate_recurring_bookings();
    select count(*) into g1 from bookings where series_id in (s1, s2);
    if g1 is distinct from 2 then v_bad := v_bad || ' FIXTURE: debt cleared but ' || g1 || ' booking(s) generated (2 expected)'; end if;
    select count(*) into c3 from notifications where profile_id = oRec and title = T_PAUSE;
    if c3 - c2 is distinct from 0 then v_bad := v_bad || ' an unblocked tick wrote a pause row'; end if;
    -- s2's booking is removed so s2 can be blocked again; s1's stays — it is the FACT that the
    -- series produced a booking after the last notice
    delete from bookings where series_id = s2;
    insert into payments (booking_id, order_id, amount, status, raw)
    values (bDebt, 'ord_cst_recur_debt2', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee'));
    perform generate_recurring_bookings();
    select count(*) into c4 from notifications where profile_id = oRec and title = T_PAUSE;
    if c4 - c3 is distinct from 1
      then v_bad := v_bad || ' 🔴 a NEW block after the series resumed wrote ' || (c4 - c3) || ' rows inside 24 h (the owner who fixed it is never told it paused again)'; end if;
    -- …and that new episode is itself deduped
    perform generate_recurring_bookings();
    select count(*) into c5 from notifications where profile_id = oRec and title = T_PAUSE;
    if c5 - c4 is distinct from 0 then v_bad := v_bad || ' the new episode repeated (+' || (c5 - c4) || ')'; end if;
    if (select body from notifications where profile_id = oRec and title = T_PAUSE order by created_at desc limit 1)
       is distinct from '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요'
      then v_bad := v_bad || ' the pause body changed (the brief: NO copy change)'; end if;
    update recurring_series set paused = true where id in (s1, s2);          -- leave no live series behind
    if v_bad = '' then call _pass('cst','0224-C1 반복 예약 일시 중지 — 한 트랜잭션의 두 틱은 1행, 25시간이 지나면 다음 틱이 1행 더; 에피소드: 미수금이 풀려 시리즈가 예약을 만든 뒤 2시간 만에 다시 막히면 24시간 안이라도 다시 알린다(맨 창이었다면 침묵), 그 새 에피소드도 반복되지 않는다; 제목·본문·NULL ref 불변');
    else v_msg := v_bad; call _fail('cst','0224-C1 recurring pause dedupe', v_msg); end if;
  exception when others then call _fail('cst','0224-C1 recurring pause dedupe', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0224-D1] F6 — the operator's id is not in the party-readable blob
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  declare
    bR uuid; bOld uuid; bArr uuid; v_res jsonb; v_keys text[]; v_scrub1 int; v_scrub2 int;
    v_old_before jsonb; v_old_after jsonb; v_arr_before jsonb;
  begin
    v_bad := '';
    -- a real strand through the real doors: the runner stops and stamps; the owner never does
    bR := t_cst_live(oo, rrA, dg, rt, interval '6 hours');
    perform set_config('request.jwt.claim.sub', rrA::text, true);
    perform end_run_tx(bR, 4.0, 1500, 'completed', null, null);
    perform confirm_return_tx(bR, 'runner');
    perform set_config('request.jwt.claim.sub', '', true);
    update bookings set run_ended_at = now() - interval '5 hours' where id = bR;
    update runs set ended_at = now() - interval '5 hours' where booking_id = bR;
    v_res := ops_resolve_return_tx(bR, t_cst_quote(4.0), 'cst 보호자 통화 — 귀가 확인', opsR);
    if (v_res->>'resolved')::boolean is not true then v_bad := v_bad || ' FIXTURE: not resolved: ' || v_res::text; end if;
    select b.return_force_evidence into v_ev from bookings b where b.id = bR;
    if v_ev is null then v_bad := v_bad || ' FIXTURE: no evidence blob at all';
    else
      if v_ev ? 'resolved_by' then v_bad := v_bad || ' 🔴 the blob carries resolved_by'; end if;
      select array_agg(k order by k) into v_keys from jsonb_object_keys(v_ev) k;
      if v_keys is distinct from array['from_status','owner_stamped','resolved_at','runner_stamped','source']
        then v_bad := v_bad || ' blob keys ' || array_to_string(v_keys, ','); end if;
    end if;
    -- the journal still carries the actor (0218's CHECK requires it; the audit trail needs it)
    -- (alias `rj`, not `r`: `r` is this block's record variable and plpgsql would resolve to it)
    if (select rj.resolved_by from return_resolutions rj where rj.booking_id = bR order by rj.created_at desc limit 1)
       is distinct from opsR then v_bad := v_bad || ' the journal lost resolved_by'; end if;
    -- the PARTY's own read, as `authenticated`: the operator's uuid is nowhere in what they can see
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select return_force_evidence from bookings where id = $1' into v_ev using bR;
      perform set_config('request.jwt.claim.sub', '', true);
      reset role;
    exception when others then reset role; perform set_config('request.jwt.claim.sub', '', true);
      v_bad := v_bad || ' the party read raised: ' || sqlerrm; v_ev := null;
    end;
    if v_ev is null then v_bad := v_bad || ' CONTROL: the owner cannot read the blob at all (an absence over an unreadable column proves nothing)';
    elsif position(opsR::text in v_ev::text) > 0 then v_bad := v_bad || ' 🔴 the owner reads the operator''s uuid'; end if;

    -- the repair: a PRE-0224 blob (the key PRESENT first), an array blob, then twice
    bOld := t_cst_live(oo, rrA, dg, rt, interval '7 hours');
    update bookings set return_forced_by = 'ops', return_forced_at = now() - interval '1 hour',
                        return_force_reason = 'ops_resolved:strand',
                        return_force_evidence = jsonb_build_object('source', 'ops_resolve_return_tx', 'from_status', 'active',
                                                   'runner_stamped', true, 'owner_stamped', false,
                                                   'resolved_by', opsR, 'resolved_at', now() - interval '1 hour')
     where id = bOld;
    bArr := t_cst_live(oo, rrA, dg, rt, interval '7 hours');
    update bookings set return_force_evidence = '["resolved_by", "x"]'::jsonb where id = bArr;
    select b.return_force_evidence into v_old_before from bookings b where b.id = bOld;
    select b.return_force_evidence into v_arr_before from bookings b where b.id = bArr;
    if (v_old_before ? 'resolved_by') is not true then v_bad := v_bad || ' CONTROL: the pre-0224 fixture lacks the key'; end if;
    -- the scrub's target set, counted independently before it runs (other suites' blobs included —
    -- the property is about every party-readable blob, not about this fixture)
    select count(*)::int into v_n from bookings b
     where jsonb_typeof(b.return_force_evidence) = 'object' and b.return_force_evidence ? 'resolved_by';
    if v_n < 1 then v_bad := v_bad || ' CONTROL: nothing for the scrub to find'; end if;
    v_scrub1 := _scrub_resolver_actor_0224();
    select b.return_force_evidence into v_old_after from bookings b where b.id = bOld;
    if v_scrub1 is distinct from v_n then v_bad := v_bad || ' first scrub touched ' || v_scrub1 || ' row(s), ' || v_n || ' carried the key'; end if;
    if exists (select 1 from bookings b where b.return_force_evidence ? 'resolved_by' and jsonb_typeof(b.return_force_evidence) = 'object')
      then v_bad := v_bad || ' an object blob still carries resolved_by after the scrub'; end if;
    if v_old_after ? 'resolved_by' then v_bad := v_bad || ' the scrub left the key'; end if;
    if v_old_after is distinct from (v_old_before - 'resolved_by') then v_bad := v_bad || ' the scrub changed another key'; end if;
    if (select b.return_force_evidence from bookings b where b.id = bArr) is distinct from v_arr_before
      then v_bad := v_bad || ' the scrub rewrote an ARRAY blob'; end if;
    v_scrub2 := _scrub_resolver_actor_0224();
    if v_scrub2 is distinct from 0 then v_bad := v_bad || ' second scrub touched ' || v_scrub2 || ' (not idempotent)'; end if;
    if (select b.return_force_evidence from bookings b where b.id = bOld) is distinct from v_old_after
      then v_bad := v_bad || ' second scrub moved the blob'; end if;
    if v_bad = '' then call _pass('cst','0224-D1 F6 — 실제 ops_resolve_return_tx 뒤 당사자가 읽는 blob은 정확히 {source, from_status, runner_stamped, owner_stamped, resolved_at}이고 운영자 id가 없다(보호자가 authenticated로 직접 읽어 uuid를 못 찾는다), 저널은 resolved_by를 그대로 지닌다; 수리 함수는 0224 이전 모양(키가 먼저 있다)에서 그 키만 지우고 나머지는 그대로, 두 번째 호출 0, 배열 blob은 건드리지 않는다');
    else v_msg := v_bad; call _fail('cst','0224-D1 resolver actor', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('cst','0224-D1 resolver actor', sqlerrm); end;

  -- ── restore the shared world (fixture note ②) ────────────────────────────────────────────
  perform t_cst_flags(null, null);
  update ops_flags set payments_live_since = v_save_live, return_strand_minutes = v_save_strand where id;
  update ops_recipients set active = false where profile_id in (opsR, opsP);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0224-S1] deployed shape
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- comment-STRIPPED source of the one public function with this name (NULL if absent — every caller
-- turns NULL into a loud NO-SOURCE, never a silent pass)
create or replace function t_cst_src(p_name text) returns text
language sql stable as $$
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;

do $$
declare
  v_bad text := ''; v_msg text; fn text; v_oid oid; v_src text; v_n int;
  p_a int; p_b int;
  server_only text[] := array['_custody_strand(uuid)', '_sweep_custody_strands()', 'sweep_run_end_recovery()',
                              '_runner_work_gate_blocking(uuid)', 'ops_gated_runners()',
                              'ops_resolve_return_tx(uuid,jsonb,text,uuid)', '_scrub_resolver_actor_0224()'];
  signed_in   text[] := array['ops_stranded_custody()', 'ops_sealed_unsettled()', 'runner_work_gate(uuid)'];
begin
  -- ① every definer: exists, prosecdef, in-body search_path, ACL by EFFECTIVE privilege both ways
  foreach fn in array server_only || signed_in || array['generate_recurring_bookings()'] loop
    v_oid := to_regprocedure('public.' || fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ': not a definer'; end if;
    if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ': no in-body search_path'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false
      then v_bad := v_bad || ' ' || fn || ': anon can execute'; end if;
  end loop;
  foreach fn in array server_only || array['generate_recurring_bookings()'] loop
    v_oid := to_regprocedure('public.' || fn);
    if v_oid is not null and has_function_privilege('authenticated', v_oid, 'execute') is not false
      then v_bad := v_bad || ' ' || fn || ': authenticated can execute (server-only)'; end if;
  end loop;
  foreach fn in array server_only loop
    v_oid := to_regprocedure('public.' || fn);
    if v_oid is not null and has_function_privilege('service_role', v_oid, 'execute') is not true
      then v_bad := v_bad || ' ' || fn || ': service_role cannot execute'; end if;
  end loop;
  foreach fn in array signed_in loop
    v_oid := to_regprocedure('public.' || fn);
    if v_oid is not null and has_function_privilege('authenticated', v_oid, 'execute') is not true
      then v_bad := v_bad || ' ' || fn || ': authenticated cannot execute (a dead door)'; end if;
  end loop;
  if has_function_privilege('authenticated', 'public._noti_ops_titles()', 'execute') is not false
    then v_bad := v_bad || ' _noti_ops_titles: authenticated can execute'; end if;
  -- the two lists take ZERO arguments — no parameter by which to point them at a third party
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('ops_stranded_custody', 'ops_sealed_unsettled') and p.pronargs = 0) is distinct from 2::bigint
    then v_bad := v_bad || ' a list takes arguments (or is missing)'; end if;

  -- ② the lists: the roster gate BEFORE the read, and the right roster
  foreach fn in array array['ops_stranded_custody', 'ops_sealed_unsettled'] loop
    v_src := t_cst_src(fn);
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')'; continue; end if;
    p_a := position('ops_recipients_for(c_ops_class)' in v_src);
    p_b := position('from bookings' in v_src);
    if (p_a > 0 and p_b > 0 and p_a < p_b) is not true then v_bad := v_bad || ' ' || fn || ': the roster gate is not ahead of the read'; end if;
    if (v_src ~ 'raise exception ''not_ops''') is not true then v_bad := v_bad || ' ' || fn || ': no not_ops refusal'; end if;
  end loop;
  if (t_cst_src('ops_stranded_custody') ~ 'c_ops_class\s+constant text := ''return_strand''') is not true
    then v_bad := v_bad || ' ops_stranded_custody: not the return_strand roster'; end if;
  if (t_cst_src('ops_sealed_unsettled') ~ 'c_ops_class\s+constant text := ''payout_due''') is not true
    then v_bad := v_bad || ' ops_sealed_unsettled: not the payout_due roster'; end if;

  -- ③ arm ⓖ: the job lock before the first loop, locked and bounded in BOTH passes, its own handler
  v_src := t_cst_src('_sweep_custody_strands');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(_sweep_custody_strands)';
  else
    p_a := position('pg_try_advisory_xact_lock(hashtextextended(''sweep_run_end_recovery'', 0))' in v_src);
    p_b := position('for r in' in v_src);
    if (p_a > 0 and p_b > 0 and p_a < p_b) is not true then v_bad := v_bad || ' arm ⓖ: the job lock is not ahead of the first loop'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' arm ⓖ: row locks=' || v_n || ' (2)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'limit c_batch', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' arm ⓖ: batch bounds=' || v_n || ' (2)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' arm ⓖ: handlers=' || v_n || ' (two per-row + one outer)'; end if;
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true then v_bad := v_bad || ' arm ⓖ: no roster'; end if;
    if (v_src ~ 'c_ops_class\s+constant text := ''return_strand''') is not true then v_bad := v_bad || ' arm ⓖ: not return_strand'; end if;
  end if;
  -- ④ the sweep calls arm ⓖ, and its own lock count is still 0201's
  v_src := t_cst_src('sweep_run_end_recovery');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(sweep_run_end_recovery)';
  else
    if (v_src ~ 'n := n \+ _sweep_custody_strands\(\);') is not true then v_bad := v_bad || ' the sweep does not call arm ⓖ'; end if;
    if (v_src ~ 'ops_recipients_for\(c_seal_ops_class\)') is not true then v_bad := v_bad || ' arm ⓐ has no ops roster'; end if;
    if (v_src ~ 'c_seal_ops_class\s+constant text := ''payout_due''') is not true then v_bad := v_bad || ' arm ⓐ: not payout_due'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
    if v_n is distinct from 5 then v_bad := v_bad || ' sweep row locks=' || v_n || ' (0201''s 5)'; end if;
  end if;
  -- ⑤ the four consumers of the ONE predicate
  foreach fn in array array['_sweep_custody_strands', '_runner_work_gate_blocking', 'ops_gated_runners', 'ops_stranded_custody'] loop
    v_src := t_cst_src(fn);
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')';
    elsif (v_src ~ '_custody_strand\(') is not true then v_bad := v_bad || ' ' || fn || ' does not read _custody_strand'; end if;
  end loop;
  -- ⑥ F6 in source, comment-STRIPPED: no `resolved_by` key literal; the journal column survives.
  --    The raw source is checked too, as the crude control: 0224's own comment explains the removal,
  --    so a stripper that blanked the body would otherwise read as a clean pass.
  v_src := t_cst_src('ops_resolve_return_tx');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_resolve_return_tx)';
  else
    if (v_src ~ '''resolved_by''') is not false then v_bad := v_bad || ' 🔴 the resolver still writes a resolved_by key'; end if;
    if (v_src ~ 'insert into return_resolutions \(booking_id, resolved_by,') is not true then v_bad := v_bad || ' the journal insert lost resolved_by'; end if;
    if ((select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ops_resolve_return_tx')
        ~ '\[0224 §I\]') is not true then v_bad := v_bad || ' CONTROL: the raw source lacks 0224''s own note (is this the 0224 body?)'; end if;
  end if;
  -- ⑦ the recurring guard is in the deployed body
  v_src := t_cst_src('generate_recurring_bookings');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings)';
  elsif (v_src ~ 'interval ''24 hours''') is not true then v_bad := v_bad || ' generate_recurring_bookings: no 24 h guard'; end if;
  -- ⑧ the flag CHECK refuses 0 and negatives (a zero would strand every live pickup at once)
  begin
    update ops_flags set custody_start_strand_minutes = 0 where id;
    v_bad := v_bad || ' ops_flags accepted custody_start_strand_minutes = 0';
    update ops_flags set custody_start_strand_minutes = null where id;
  exception when check_violation then null;
  end;
  begin
    update ops_flags set custody_end_strand_minutes = -5 where id;
    v_bad := v_bad || ' ops_flags accepted custody_end_strand_minutes = -5';
    update ops_flags set custody_end_strand_minutes = null where id;
  exception when check_violation then null;
  end;
  if (select custody_start_strand_minutes is null and custody_end_strand_minutes is null from ops_flags where id) is not true
    then v_bad := v_bad || ' the thresholds are not back to NULL after this suite (fixture note ②)'; end if;

  if v_bad = '' then call _pass('cst','0224-S1 배포 형상 — 정의자 11개 모두 본문 search_path·유효 권한 양방향(anon 0, 서버 전용은 authenticated 0·service_role 1, 목록 둘과 작업 게이트만 authenticated 1), 목록은 인자 0개이고 주석을 벗긴 소스에서 명부 게이트가 읽기보다 앞이며 명부가 맞다; 팔 ⓖ는 잡 락이 첫 루프 앞, 행 락 2·배치 상한 2·핸들러 3; 스윕은 팔 ⓖ를 부르고 자기 락 수는 0201의 5; 소비자 넷이 모두 _custody_strand를 읽는다; 해결 RPC에 resolved_by 키 없음(저널 열은 유지, 원본 소스 대조 포함); 반복 가드 존재; 플래그 CHECK가 0과 음수를 거절');
  else v_msg := v_bad; call _fail('cst','0224-S1 deployed shape', v_msg); end if;
exception when others then call _fail('cst','0224-S1 deployed shape', sqlerrm);
end $$;
