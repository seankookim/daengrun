-- ═══ 264 — 0233: a pre-run incident_review no longer work-gates a runner whose dog never left home ·
-- ═══        the pre-run incident bell (arm ⓗ) · the roster's read of the same set
-- ═══        0233-G1 · G2 · G3 · G4 · R1 · B1 · B2 · B3 · B4 · L1 · S1, tag `pig`
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation:
--   · G1 **A RUNNER WHO ONLY TAPPED 도착 IS NOT GATED.** A marketplace booking reached
--        `runner_enroute → incident_review` carrying `arrived_at` and NO handoff stamp and NO
--        `run_ended_at` (0117 _resolve_checkin's evidence arm): `runner_work_gate` answers
--        `gated = false` and `_runner_work_gate_blocking` returns no row for that runner. The
--        fixture's world is asserted FIRST (status, arrived_at set, both stamps and run_ended_at NULL)
--        so the green cannot come from a fixture that never had the shape.
--   · G2 **ONE HANDOFF STAMP GATES — EITHER ONE.** The same transition with ONLY the owner's stamp,
--        and (a second runner) with ONLY the runner's stamp: both gated, `waiting_on = both`,
--        `exit = both_confirm_return`. Two arms so each stamp conjunct is observable on its own.
--   · G3 **`picked_up → incident_review` GATES** (both stamps, no run — 0117:652-656's arm).
--   · G4 **A RUN-ENDED incident_review GATES** (0188 ⓑ-①'s escalation shape: run ended, zero
--        return stamps). ⚠ Its handoff stamps are set, as every real run-ended row's are, so this
--        pin cannot see the `run_ended_at` conjunct ALONE — see GAPS (five shipped pins can).
--   · R1 **`ops_gated_runners()` IS STILL EXACTLY THE GATE'S SET, AND A PRE-RUN ROW NAMES NO DOOR.**
--        This suite's G2/G3/G4 bookings are listed and G1's is not; the remedy of every listed row
--        with `run_ended_at` NULL mentions NO `confirm_return_tx` and says 「no door exists」; G4's
--        (run ended) still names `confirm_return_tx` — the control that the arm is conditional.
--   · B1 **THE BELL RINGS ONCE PER BOOKING, AND ONLY FOR MARKETPLACE PRE-RUN ROWS.** Two real
--        `sweep_run_end_recovery()` ticks: each pre-run fixture (G1's arrived-only shape, G2's
--        one-stamp shape) gets exactly ONE `system` row per active `return_strand` recipient — a
--        delta this pin causes (0 before the first tick) — and the second tick adds none. A CLUB
--        pre-run incident_review and a RUN-ENDED incident_review get none.
--   · B2 **THE TITLE IS LEDGERED** — measured on what the sweep actually wrote: in
--        `_noti_ops_titles()`, `_noti_push_category('system', …) = 'ops'`, not urgent.
--   · B3 **AN EMPTY ROSTER WRITES NOTHING AND RETRIES.** Every active `return_strand` row off → a
--        tick writes no row for a fresh pre-run booking; ONE operator seated → the next tick writes
--        exactly one; a third tick none. Rolled back after measuring (the shared roster is restored).
--   · B4 **NO CLIENT CAN SILENCE THE BELL OR FAKE ITS INSTANT.** Three look-alike rows, each written
--        through a door production ships (asserted first — each write lands exactly one row): the
--        booking's RUNNER inserts a `kind='booking'` row with the bell's title on their own booking
--        (0114 `noti party insert`); a signed-in STRANGER rewrites one of their own rows to kind
--        `system`, the bell's title, another booking's id and `created_at` 2000-01-01 (0002 `noti self
--        update`); a SEATED operator who is also a booking's OWNER inserts a `kind='booking'` look-alike
--        dated 2000-01-01. One real tick: each of the three bookings still gets exactly one `system`
--        row to the seated operator — like an untouched CONTROL booking — and `ops_prerun_cases()`
--        reports the REAL bell's instant for each, never 2000. Each forged row is observable through
--        exactly one conjunct of the bell identity (the stranger's: recipient; the two party rows:
--        kind). Rolled back after measuring.
--   · L1 **`ops_prerun_cases()` IS THE `return_strand` ROSTER'S READ OF ARM ⓗ'S SET.** A signed-in
--        stranger and a `payout_due`-only operator get `not_ops`; no caller gets `not_signed_in`.
--        For the operator, this suite's bookings in the list are EXACTLY the pre-run fixtures (not
--        G4, not the club row); `runner_gated` agrees with `runner_work_gate` for every one of them
--        (false for G1, true for G2/G3); `notified_at` is set once belled; the KEY SET is exact.
--   · S1 **DEPLOYED SHAPE.** Definers with in-body search_path; effective ACLs both ways; the read
--        takes zero arguments and its roster gate precedes its first read (comment-stripped);
--        arm ⓗ takes the job lock before its loop, is locked once, bounded once, handles twice; the
--        sweep calls `_sweep_prerun_incidents()`; the gate's AND ops_gated_runners' incident arm
--        name all three evidence columns. NO-FUNCTION / NO-SOURCE fail loudly.
--
-- ─── GAPS (prose — the harness cannot separate these, so no pin claims them) ───
--   · The `run_ended_at` conjunct of the incident arm is not separately observable through THIS
--     suite's rows: every run that ended passed a handoff, so G4's stamps are set and the stamp
--     conjuncts admit it too. G4 proves the disjunction ADMITS a run-ended row; S1 pins that the
--     conjunct is written. ⚠ MEASURED, and it is better news than this paragraph first said: deleting
--     that conjunct reddens FIVE shipped pins (132 E3/E5 · 128 W4 · 219 0188-B3 · 224 0193-R2) whose
--     run-ended incident_review fixtures carry no handoff stamps — so the conjunct IS guarded, by
--     suites older than this one. This suite adds no manufactured row to duplicate them.
--   · Nothing here pushes (`00_shim.sql` stubs `net.http_post`); the lock-screen category is 245's.
--   · The job-lock SKIP needs two sessions; S1 pins that the lock is taken before the first loop.
--   · Arm ⓗ's once-per-booking guard has TWO halves — the candidate query's `not exists` and the
--     re-check under the row lock — and each covers the other in a single session: deleting either
--     alone leaves B1 green (measured, battery M7a / M7b); deleting both reddens B1 + B3 (M7). The
--     re-check exists for the race between the candidate read and the lock, which one session
--     cannot stage. Named here, not pinned.
--   · B4's battery (fix round, a lab copy, every plant asserted and &&-gated to its run, control
--     1622/0): all four bell-identity sites unfixed → 1620/2 (B4 + 265 `0234-L3` — the hole
--     reproduces); each ONE conjunct deleted — candidate kind · re-check kind · candidate recipient ·
--     re-check recipient · `ops_prerun_cases` kind · `ops_prerun_cases` recipient — → 1621/1, B4
--     alone. Unlike B1's once-guard, the two halves ARE separately observable here, because a
--     suppressed bell (either half excludes the row) is visible where a duplicate one is not.
--
-- ─── FIXTURE NOTES ───
--  ① Every count is SCOPED to this suite's own bookings. `bookings`, `notifications` and the rosters
--     are shared with every suite before this one.
--  ② The sweep is global and batched (`limit 50`, oldest `updated_at` first), so B1's rows are
--     INSERTED at `incident_review` with `updated_at` a year old (the touch trigger fires on UPDATE
--     only) — older than anything another suite builds, so they cannot be shadowed. G1-G3 are
--     reached by a real status UPDATE through the transition trigger (their updated_at is now).
--  ③ `request.jwt.claim.sub` is set and cleared explicitly around every caller-shaped call.
set client_min_messages = warning;

-- a marketplace booking at `p_status` with the given evidence; `p_aged` backdates updated_at
create or replace function t_pig_booking(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                         p_status booking_status,
                                         p_arrived boolean, p_owner_stamp boolean, p_runner_stamp boolean,
                                         p_run_ended boolean, p_aged boolean default false,
                                         p_club_session uuid default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        arrived_at, owner_confirmed_handoff_at, runner_confirmed_handoff_at,
                        run_ended_at, club_session_id, updated_at)
  values (p_owner, p_dog, p_runner, p_route, p_status, now() - interval '2 hours', 5.0,
          9900, 15000, 0, 24900, 9900,
          case when p_arrived then now() - interval '100 minutes' end,
          case when p_owner_stamp then now() - interval '95 minutes' end,
          case when p_runner_stamp then now() - interval '94 minutes' end,
          case when p_run_ended then now() - interval '30 minutes' end,
          p_club_session,
          case when p_aged then now() - interval '400 days' else now() end)
  returning id into v;
  return v;
end $$;

-- `runner_work_gate` as the runner themself (the client's only legal call, 0116 §D ⓑ)
create or replace function t_pig_gate(p_runner uuid) returns jsonb
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

-- `ops_prerun_cases()` as ONE caller: rows keyed by booking id, OR the raise word
create or replace function t_pig_cases_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_object_agg(x.booking_id::text, to_jsonb(x)), '{}'::jsonb)
      into v from ops_prerun_cases() x;
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('rows', v);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_pig_n(p_booking uuid, p_title text) returns int
language sql as $$
  select count(*)::int from notifications where ref_id = p_booking and title = p_title
$$;

create or replace function t_pig_src(p_name text) returns text
language sql stable as $$
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;

do $$
declare
  oo uuid; sx uuid; opsR uuid; opsP uuid;
  r1 uuid; r2o uuid; r2r uuid; r3 uuid; r4 uuid; r5 uuid; r6 uuid; r7 uuid; r8 uuid;
  dg uuid; rt uuid; v_club uuid; v_sess uuid;
  bArr uuid; bOwn uuid; bRun uuid; bPick uuid; bEnded uuid;       -- G1 · G2a · G2b · G3 · G4
  bB1 uuid; bB2 uuid; bClub uuid; bEnd2 uuid;                       -- B1 (aged)
  bB3 uuid;                                                         -- B3
  T_OPS constant text := '러닝 전 사고 검토 — 확인 필요';
  CASE_KEYS constant text[] := array['booking_id','dog_name','owner_name','runner_name','status',
    'scheduled_at','arrived_at','owner_confirmed_handoff_at','runner_confirmed_handoff_at',
    'runner_gated','last_changed_at','notified_at'];
  v jsonb; v2 jsonb; v_bad text; v_msg text; v_n int; v_roster int; v_src text; v_txt text;
  v_ids uuid[]; v_keys text[]; r record; p_a int; p_b int; v_oid oid; fn text;
  b3_first int; b3_second int; b3_third int; b3_err text; b3_roster0 int;
  r9 uuid; r10 uuid; r11 uuid; r12 uuid; bAI uuid; bAU uuid; bAR uuid; bCtl uuid;
  b4_err text; b4_ins_r int; b4_ins_o int; b4_upd int; b4_nid uuid; b4_n jsonb; b4_cases jsonb; b4_pre int;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  oo   := t_user('pig_owner', 'owner');
  sx   := t_user('pig_stranger', 'owner');
  opsR := t_user('pig_ops_ret', 'owner');
  opsP := t_user('pig_ops_pay', 'owner');
  r1 := t_user('pig_r1', 'runner'); r2o := t_user('pig_r2o', 'runner'); r2r := t_user('pig_r2r', 'runner');
  r3 := t_user('pig_r3', 'runner'); r4 := t_user('pig_r4', 'runner'); r5 := t_user('pig_r5', 'runner');
  r6 := t_user('pig_r6', 'runner'); r7 := t_user('pig_r7', 'runner'); r8 := t_user('pig_r8', 'runner');
  dg := t_dog(oo, '도착견');
  rt := t_route('pig 코스');
  insert into ops_recipients (profile_id, event_class, active) values (opsR, 'return_strand', true)
  on conflict (profile_id, event_class) do update set active = true;
  insert into ops_recipients (profile_id, event_class, active) values (opsP, 'payout_due', true)
  on conflict (profile_id, event_class) do update set active = true;
  insert into clubs (name, district, host_profile_id) values ('pig 클럽', '반포동', r7) returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, r7, now() - interval '2 hours', 'pig 집결지') returning id into v_sess;

  -- ── the gate world: each runner holds exactly ONE booking, reached by a real status UPDATE ──
  bArr  := t_pig_booking(oo, r1,  dg, rt, 'runner_enroute', true,  false, false, false);
  bOwn  := t_pig_booking(oo, r2o, dg, rt, 'runner_enroute', true,  true,  false, false);
  bRun  := t_pig_booking(oo, r2r, dg, rt, 'runner_enroute', false, false, true,  false);
  bPick := t_pig_booking(oo, r3,  dg, rt, 'picked_up',      true,  true,  true,  false);
  bEnded := t_pig_booking(oo, r4, dg, rt, 'active',         true,  true,  true,  true);
  update bookings set status = 'incident_review' where id in (bArr, bOwn, bRun, bPick, bEnded);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-G1] arrived only → NOT gated
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select * into r from bookings where id = bArr;
    if r.status::text is distinct from 'incident_review' or r.arrived_at is null
       or r.owner_confirmed_handoff_at is not null or r.runner_confirmed_handoff_at is not null
       or r.run_ended_at is not null or r.club_session_id is not null
      then v_bad := v_bad || ' FIXTURE: not the arrived-only incident_review shape'; end if;
    v := t_pig_gate(r1);
    if (v->>'gated') is distinct from 'false' then v_bad := v_bad || ' runner_work_gate=' || v::text; end if;
    select count(*)::int into v_n from _runner_work_gate_blocking(r1);
    if v_n is distinct from 0 then v_bad := v_bad || ' _runner_work_gate_blocking rows=' || v_n; end if;
    if v_bad = '' then call _pass('pig','0233-G1 도착만 찍고 러닝 전 사고 검토로 넘어간 러너는 작업 게이트에 막히지 않는다 (픽스처 형상 먼저 확인: incident_review·arrived_at 有·인계 도장 둘 다 無·run_ended_at 無)');
    else v_msg := v_bad; call _fail('pig','0233-G1 arrived-only not gated', v_msg); end if;
  exception when others then call _fail('pig','0233-G1 arrived-only not gated', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-G2] one handoff stamp — either one — gates
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach fn in array array['owner', 'runner'] loop
      v := t_pig_gate(case fn when 'owner' then r2o else r2r end);
      if (v->>'gated') is distinct from 'true'
         or (v->>'booking_id') is distinct from (case fn when 'owner' then bOwn else bRun end)::text
         or (v->>'waiting_on') is distinct from 'both'
         or (v->>'exit') is distinct from 'both_confirm_return'
        then v_bad := v_bad || ' ' || fn || '-stamp only: ' || v::text; end if;
    end loop;
    if (select owner_confirmed_handoff_at is not null and runner_confirmed_handoff_at is null
               and run_ended_at is null from bookings where id = bOwn) is not true
       or (select owner_confirmed_handoff_at is null and runner_confirmed_handoff_at is not null
               and run_ended_at is null and arrived_at is null from bookings where id = bRun) is not true
      then v_bad := v_bad || ' FIXTURE: the one-stamp shapes are not what they claim'; end if;
    if v_bad = '' then call _pass('pig','0233-G2 인계 도장이 하나라도 있으면(보호자만 · 러너만 각각) 게이트가 잡는다 — waiting_on both, exit both_confirm_return');
    else v_msg := v_bad; call _fail('pig','0233-G2 one stamp gates', v_msg); end if;
  exception when others then call _fail('pig','0233-G2 one stamp gates', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-G3] picked_up → incident_review gates · [0233-G4] run ended → gates
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v := t_pig_gate(r3);
    if (v->>'gated') = 'true' and (v->>'booking_id') = bPick::text
    then call _pass('pig','0233-G3 픽업 후 러닝 전 사고 검토(인계 도장 둘, 러닝 없음)는 여전히 게이트에 잡힌다');
    else call _fail('pig','0233-G3 picked_up→incident_review gated', v::text); end if;
  exception when others then call _fail('pig','0233-G3 picked_up→incident_review gated', sqlerrm); end;
  begin
    v := t_pig_gate(r4);
    if (v->>'gated') = 'true' and (v->>'booking_id') = bEnded::text
       and (select run_ended_at is not null from bookings where id = bEnded) is true
    then call _pass('pig','0233-G4 러닝이 끝난 뒤의 사고 검토는 여전히 게이트에 잡힌다 (run_ended_at 단독 관측은 GAPS 참조)');
    else call _fail('pig','0233-G4 run-ended incident_review gated', v::text); end if;
  exception when others then call _fail('pig','0233-G4 run-ended incident_review gated', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-R1] ops_gated_runners: the gate's set, and a pre-run row names no door
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_n from ops_gated_runners() g where g.booking_id = bArr;
    if v_n is distinct from 0 then v_bad := v_bad || ' G1 (not gated) is listed'; end if;
    foreach v_txt in array array[bOwn::text, bRun::text, bPick::text, bEnded::text] loop
      select count(*)::int into v_n from ops_gated_runners() g where g.booking_id = v_txt::uuid;
      if v_n is distinct from 1 then v_bad := v_bad || ' gated ' || v_txt || ' listed ' || v_n || 'x'; end if;
    end loop;
    for r in select g.booking_id, g.remedy from ops_gated_runners() g
              where g.booking_id in (bOwn, bRun, bPick) loop
      if (position('confirm_return_tx' in coalesce(r.remedy, 'NULL')) = 0) is not true
        then v_bad := v_bad || ' 🔴 pre-run ' || r.booking_id || ' still names confirm_return_tx: ' || coalesce(r.remedy, 'NULL'); end if;
      if (position('no door exists' in coalesce(r.remedy, '')) > 0) is not true
        then v_bad := v_bad || ' pre-run ' || r.booking_id || ' does not say no door exists'; end if;
    end loop;
    -- CONTROL: the run-ended row still names the door that works for it
    if (select position('confirm_return_tx' in g.remedy) > 0 from ops_gated_runners() g where g.booking_id = bEnded) is not true
      then v_bad := v_bad || ' CONTROL: the run-ended row lost its confirm_return_tx remedy (the arm is not conditional)'; end if;
    if v_bad = '' then call _pass('pig','0233-R1 ops_gated_runners는 게이트와 같은 집합(G1 없음, G2·G3·G4 각 1회) — 러닝 전 행의 처방은 confirm_return_tx를 말하지 않고 「no door exists」라고 하며, 러닝이 끝난 행은 여전히 confirm_return_tx (대조)');
    else v_msg := v_bad; call _fail('pig','0233-R1 ops_gated_runners set and remedy', v_msg); end if;
  exception when others then call _fail('pig','0233-R1 ops_gated_runners set and remedy', sqlerrm); end;

  -- ── the bell world (fixture note ②: inserted at incident_review, updated_at a year old) ──
  bB1   := t_pig_booking(oo, r5, dg, rt, 'incident_review', true, false, false, false, true);
  bB2   := t_pig_booking(oo, r6, dg, rt, 'incident_review', true, true,  false, false, true);
  bClub := t_pig_booking(oo, r7, dg, rt, 'incident_review', true, false, false, false, true, v_sess);
  bEnd2 := t_pig_booking(oo, r8, dg, rt, 'incident_review', true, true,  true,  true,  true);
  select count(*)::int into v_roster from ops_recipients_for('return_strand');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-B1] once per booking; marketplace pre-run rows only
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_roster < 1 then v_bad := v_bad || ' FIXTURE: the return_strand roster is empty (「one per recipient」 would pass by writing nothing)'; end if;
    if t_pig_n(bB1, T_OPS) + t_pig_n(bB2, T_OPS) + t_pig_n(bClub, T_OPS) + t_pig_n(bEnd2, T_OPS) is distinct from 0
      then v_bad := v_bad || ' FIXTURE: a bell existed before the first tick'; end if;
    perform sweep_run_end_recovery();
    foreach v_txt in array array[bB1::text, bB2::text] loop
      if t_pig_n(v_txt::uuid, T_OPS) is distinct from v_roster
        then v_bad := v_bad || ' tick1 ' || v_txt || ' rows=' || t_pig_n(v_txt::uuid, T_OPS) || ' (roster ' || v_roster || ')'; end if;
      if (select count(*) from notifications where ref_id = v_txt::uuid and title = T_OPS and profile_id = opsR) is distinct from 1::bigint
        then v_bad := v_bad || ' tick1 ' || v_txt || ': the seated operator did not get exactly one'; end if;
      if (select bool_and(kind = 'system') from notifications where ref_id = v_txt::uuid and title = T_OPS) is not true
        then v_bad := v_bad || ' a bell is not kind=system'; end if;
      if exists (select 1 from notifications where ref_id = v_txt::uuid and title = T_OPS
                   and profile_id in (oo, r5, r6))
        then v_bad := v_bad || ' 🔴 a PARTY got the ops bell'; end if;
    end loop;
    perform sweep_run_end_recovery();
    if t_pig_n(bB1, T_OPS) is distinct from v_roster or t_pig_n(bB2, T_OPS) is distinct from v_roster
      then v_bad := v_bad || ' 🔴 tick2 rang again (' || t_pig_n(bB1, T_OPS) || '/' || t_pig_n(bB2, T_OPS) || ')'; end if;
    if t_pig_n(bClub, T_OPS) is distinct from 0 then v_bad := v_bad || ' 🔴 the CLUB row rang'; end if;
    if t_pig_n(bEnd2, T_OPS) is distinct from 0 then v_bad := v_bad || ' 🔴 the RUN-ENDED row rang'; end if;
    if v_bad = '' then call _pass('pig','0233-B1 실제 sweep 두 번 — 러닝 전 사고 검토 행마다 return_strand 명부 1인당 정확히 1행(첫 tick 전 0), 두 번째 tick은 추가 0, 당사자에게는 0; 클럽 행과 러닝이 끝난 행은 울리지 않는다');
    else v_msg := v_bad; call _fail('pig','0233-B1 bell once per booking', v_msg); end if;
  exception when others then call _fail('pig','0233-B1 bell once per booking', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-B2] the written title is ledgered, ops, not urgent
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_n from notifications where ref_id in (bB1, bB2) and kind = 'system';
    if v_n = 0 then v_bad := v_bad || ' FIXTURE: the sweep wrote no system row to measure'; end if;
    for r in select distinct title from notifications where ref_id in (bB1, bB2) and kind = 'system' loop
      if (r.title = any (_noti_ops_titles())) is not true then v_bad := v_bad || ' unledgered 「' || r.title || '」'; end if;
      if _noti_push_category('system', r.title) is distinct from 'ops'
        then v_bad := v_bad || ' 「' || r.title || '」 classifies ' || coalesce(_noti_push_category('system', r.title), 'NULL'); end if;
      if (r.title = any (_noti_urgent_noti_titles())) is not false
        then v_bad := v_bad || ' 「' || r.title || '」 is urgent'; end if;
    end loop;
    if v_bad = '' then call _pass('pig','0233-B2 스윕이 실제로 쓴 system 제목은 _noti_ops_titles에 있고 ops로 분류되며 긴급 계열이 아니다');
    else v_msg := v_bad; call _fail('pig','0233-B2 title ledgered', v_msg); end if;
  exception when others then call _fail('pig','0233-B2 title ledgered', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-B3] an empty roster writes nothing and retries (rolled back after measuring)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    b3_err := null;
    begin
      update ops_recipients set active = false where event_class = 'return_strand' and active;
      select count(*)::int into b3_roster0 from ops_recipients_for('return_strand');
      bB3 := t_pig_booking(oo, r1, dg, rt, 'incident_review', true, false, false, false, true);
      perform sweep_run_end_recovery();
      b3_first := t_pig_n(bB3, T_OPS);
      update ops_recipients set active = true where event_class = 'return_strand' and profile_id = opsR;
      perform sweep_run_end_recovery();
      b3_second := t_pig_n(bB3, T_OPS);
      perform sweep_run_end_recovery();
      b3_third := t_pig_n(bB3, T_OPS);
      raise exception 'pig_b3_rollback';
    exception when others then
      if sqlerrm is distinct from 'pig_b3_rollback' then b3_err := sqlerrm; end if;
    end;
    v_bad := '';
    if b3_err is not null then v_bad := v_bad || ' raised: ' || b3_err; end if;
    if b3_roster0 is distinct from 0 then v_bad := v_bad || ' FIXTURE: the roster was not emptied (' || coalesce(b3_roster0::text, 'NULL') || ')'; end if;
    if b3_first is distinct from 0 then v_bad := v_bad || ' 🔴 empty roster wrote ' || coalesce(b3_first::text, 'NULL'); end if;
    if b3_second is distinct from 1 then v_bad := v_bad || ' one seated operator → ' || coalesce(b3_second::text, 'NULL') || ' (1: the arm did not retry)'; end if;
    if b3_third is distinct from 1 then v_bad := v_bad || ' third tick → ' || coalesce(b3_third::text, 'NULL'); end if;
    -- the rollback restored the shared roster
    select count(*)::int into v_n from ops_recipients_for('return_strand');
    if v_n is distinct from v_roster then v_bad := v_bad || ' the roster was not restored (' || v_n || ' vs ' || v_roster || ')'; end if;
    if v_bad = '' then call _pass('pig','0233-B3 명부가 비면 아무것도 쓰지 않고(0) 매 tick 재시도한다 — 운영자 한 명이 앉으면 다음 tick에 정확히 1, 그다음 tick은 그대로 1 (측정 후 롤백, 명부 복원 확인)');
    else v_msg := v_bad; call _fail('pig','0233-B3 empty roster retries', v_msg); end if;
  exception when others then call _fail('pig','0233-B3 empty roster retries', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-B4] no client can silence the bell or fake its instant (rolled back after measuring)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; b4_err := null;
    r9 := t_user('pig_r9', 'runner'); r10 := t_user('pig_r10', 'runner');
    r11 := t_user('pig_r11', 'runner'); r12 := t_user('pig_r12', 'runner');
    begin
      bAI  := t_pig_booking(oo,   r9,  dg, rt, 'incident_review', true, false, false, false, true);
      bAU  := t_pig_booking(oo,   r11, dg, rt, 'incident_review', true, false, false, false, true);
      bAR  := t_pig_booking(opsR, r12, dg, rt, 'incident_review', true, false, false, false, true);
      bCtl := t_pig_booking(oo,   r10, dg, rt, 'incident_review', true, false, false, false, true);
      -- (i) the RUNNER, party insert on their own booking
      perform set_config('request.jwt.claim.sub', r9::text, true);
      set local role authenticated;
      if current_user <> 'authenticated' then raise exception 'b4: role did not take'; end if;
      insert into notifications (profile_id, kind, title, body, ref_id) values (r9, 'booking', T_OPS, '내 알림', bAI);
      get diagnostics b4_ins_r = row_count;
      reset role;
      -- (ii) a STRANGER rewrites one of their own rows (noti self update)
      insert into notifications (profile_id, kind, title, body) values (sx, 'booking', 'pig b4', 'x') returning id into b4_nid;
      perform set_config('request.jwt.claim.sub', sx::text, true);
      set local role authenticated;
      update notifications set kind = 'system', title = T_OPS, ref_id = bAU, created_at = '2000-01-01' where id = b4_nid;
      get diagnostics b4_upd = row_count;
      reset role;
      -- (iii) a SEATED operator who owns a booking, party insert, dated 2000-01-01
      perform set_config('request.jwt.claim.sub', opsR::text, true);
      set local role authenticated;
      insert into notifications (profile_id, kind, title, body, ref_id, created_at)
        values (opsR, 'booking', T_OPS, '내 알림', bAR, '2000-01-01');
      get diagnostics b4_ins_o = row_count;
      reset role;
      perform set_config('request.jwt.claim.sub', '', true);
      -- the bell has not rung for any of them yet (a delta this pin causes)
      select count(*)::int into b4_pre from notifications
       where ref_id in (bAI, bAU, bAR, bCtl) and title = T_OPS and kind = 'system' and profile_id = opsR;
      perform sweep_run_end_recovery();
      select jsonb_object_agg(x.id::text, (select count(*) from notifications nt
                                            where nt.ref_id = x.id and nt.title = T_OPS
                                              and nt.kind = 'system' and nt.profile_id = opsR))
        into b4_n from (select unnest(array[bAI, bAU, bAR, bCtl]) as id) x;
      b4_cases := t_pig_cases_as(opsR);
      raise exception 'pig_b4_rollback';
    exception when others then
      if sqlerrm is distinct from 'pig_b4_rollback' then b4_err := sqlerrm; end if;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    if b4_err is not null then v_bad := v_bad || ' staging raised: ' || b4_err; end if;
    if b4_ins_r is distinct from 1 or b4_upd is distinct from 1 or b4_ins_o is distinct from 1
      then v_bad := v_bad || ' FIXTURE: a forging write did not land (' || coalesce(b4_ins_r::text, 'NULL') || '/'
                   || coalesce(b4_upd::text, 'NULL') || '/' || coalesce(b4_ins_o::text, 'NULL') || ') — the pin would prove nothing'; end if;
    if b4_pre is distinct from 0 then v_bad := v_bad || ' FIXTURE: a real bell existed before the tick (' || coalesce(b4_pre::text, 'NULL') || ')'; end if;
    if (b4_n->>bCtl::text) is distinct from '1' then v_bad := v_bad || ' CONTROL: the untouched booking got ' || coalesce(b4_n->>bCtl::text, 'NULL') || ' (1) — the tick proves nothing'; end if;
    if (b4_n->>bAI::text) is distinct from '1' then v_bad := v_bad || ' 🔴 the runner''s booking-kind look-alike silenced the bell (' || coalesce(b4_n->>bAI::text, 'NULL') || ')'; end if;
    if (b4_n->>bAU::text) is distinct from '1' then v_bad := v_bad || ' 🔴 the stranger''s rewritten system row silenced the bell (' || coalesce(b4_n->>bAU::text, 'NULL') || ')'; end if;
    if (b4_n->>bAR::text) is distinct from '1' then v_bad := v_bad || ' 🔴 the operator-owner''s booking-kind look-alike silenced the bell (' || coalesce(b4_n->>bAR::text, 'NULL') || ')'; end if;
    if b4_cases ? 'raised' or b4_cases is null then v_bad := v_bad || ' cases: ' || coalesce(b4_cases::text, 'NULL');
    else
      foreach v_txt in array array[bAI::text, bAU::text, bAR::text, bCtl::text] loop
        if (b4_cases->'rows'->v_txt->>'notified_at') is null
          then v_bad := v_bad || ' ' || v_txt || ' notified_at NULL';
        elsif ((b4_cases->'rows'->v_txt->>'notified_at')::timestamptz > '2001-01-01'::timestamptz) is not true
          then v_bad := v_bad || ' 🔴 ' || v_txt || ' notified_at=' || (b4_cases->'rows'->v_txt->>'notified_at') || ' — a look-alike row was read as the bell'; end if;
      end loop;
    end if;
    if v_bad = '' then call _pass('pig','0233-B4 클라이언트는 벨을 끄거나 시각을 꾸밀 수 없다 — 러너의 booking 종류 흉내(파티 insert), 낯선 사람이 자기 행을 system·다른 예약·2000-01-01로 바꾼 행(self update), 명부 운영자이자 보호자의 booking 종류 흉내(2000-01-01) 모두 1행 반영 확인 후, 한 tick에 세 예약 모두 대조군처럼 운영자 system 1행, ops_prerun_cases의 notified_at은 실제 벨 시각 (측정 후 롤백)');
    else v_msg := v_bad; call _fail('pig','0233-B4 bell identity', v_msg); end if;
  exception when others then reset role; call _fail('pig','0233-B4 bell identity', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-L1] ops_prerun_cases — the return_strand roster's read of arm ⓗ's set
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (t_pig_cases_as(sx)->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' stranger: ' || t_pig_cases_as(sx)::text; end if;
    if (t_pig_cases_as(opsP)->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' payout_due-only operator: ' || left(t_pig_cases_as(opsP)::text, 80); end if;
    if (t_pig_cases_as(null)->>'raised') is distinct from 'not_signed_in' then v_bad := v_bad || ' no caller: ' || left(t_pig_cases_as(null)::text, 80); end if;
    v := t_pig_cases_as(opsR);
    if v ? 'raised' then v_bad := v_bad || ' operator refused: ' || (v->>'raised');
    else
      -- this suite's bookings in the list are EXACTLY the marketplace pre-run fixtures
      select coalesce(array_agg(k order by k), '{}') into v_keys
        from jsonb_object_keys(v->'rows') k
       where k::uuid in (bArr, bOwn, bRun, bPick, bEnded, bB1, bB2, bClub, bEnd2);
      if v_keys is distinct from (select array_agg(x order by x) from unnest(array[bArr::text, bOwn::text, bRun::text, bPick::text, bB1::text, bB2::text]) x)
        then v_bad := v_bad || ' listed set=' || v_keys::text; end if;
      -- runner_gated agrees with the gate itself, row by row
      foreach v_txt in array array[bArr::text, bOwn::text, bRun::text, bPick::text] loop
        v2 := t_pig_gate((select runner_id from bookings where id = v_txt::uuid));
        if ((v->'rows'->v_txt->>'runner_gated')::boolean) is distinct from
           ((v2->>'gated')::boolean and (v2->>'booking_id') = v_txt)
          then v_bad := v_bad || ' runner_gated disagrees with runner_work_gate on ' || v_txt; end if;
      end loop;
      if (v->'rows'->bArr::text->>'runner_gated') is distinct from 'false'
         or (v->'rows'->bOwn::text->>'runner_gated') is distinct from 'true'
        then v_bad := v_bad || ' runner_gated values wrong'; end if;
      if (v->'rows'->bB1::text->>'notified_at') is null then v_bad := v_bad || ' belled row has no notified_at'; end if;
      if (v->'rows'->bArr::text->>'arrived_at') is null then v_bad := v_bad || ' arrived_at not carried'; end if;
      select array_agg(k order by k) into v_keys from jsonb_object_keys(v->'rows'->bB1::text) k;
      if v_keys is distinct from (select array_agg(x order by x) from unnest(CASE_KEYS) x)
        then v_bad := v_bad || ' key set=' || coalesce(v_keys::text, 'NULL'); end if;
    end if;
    if v_bad = '' then call _pass('pig','0233-L1 ops_prerun_cases — 낯선 사람·payout_due 전용 운영자는 not_ops, 호출자 없음은 not_signed_in; return_strand 운영자에게 이 스위트 예약 중 정확히 러닝 전 마켓 행만(G4·클럽 없음), runner_gated는 runner_work_gate와 행마다 일치, 울린 행은 notified_at, 키 집합 정확');
    else v_msg := v_bad; call _fail('pig','0233-L1 ops_prerun_cases', v_msg); end if;
  exception when others then call _fail('pig','0233-L1 ops_prerun_cases', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0233-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach fn in array array['_runner_work_gate_blocking(uuid)', 'ops_gated_runners()', '_sweep_prerun_incidents()',
                              'sweep_run_end_recovery()', 'ops_prerun_cases()'] loop
      v_oid := to_regprocedure('public.' || fn);
      if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
      if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' ' || fn || ': not a definer'; end if;
      if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
        then v_bad := v_bad || ' ' || fn || ': no in-body search_path'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || fn || ': anon can execute'; end if;
      if fn = 'ops_prerun_cases()' then
        if has_function_privilege('authenticated', v_oid, 'execute') is not true then v_bad := v_bad || ' ' || fn || ': authenticated cannot execute (a dead door)'; end if;
      else
        if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || fn || ': authenticated can execute (server-only)'; end if;
        if has_function_privilege('service_role', v_oid, 'execute') is not true then v_bad := v_bad || ' ' || fn || ': service_role cannot execute'; end if;
      end if;
    end loop;
    if (select p.pronargs from pg_proc p where p.oid = to_regprocedure('public.ops_prerun_cases()')) is distinct from 0::smallint
      then v_bad := v_bad || ' ops_prerun_cases takes arguments'; end if;
    -- the read: roster gate before the first read, the right roster
    v_src := t_pig_src('ops_prerun_cases');
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_prerun_cases)';
    else
      p_a := position('ops_recipients_for(c_ops_class)' in v_src); p_b := position('from bookings' in v_src);
      if (p_a > 0 and p_b > 0 and p_a < p_b) is not true then v_bad := v_bad || ' read: the roster gate is not ahead of the read'; end if;
      if (v_src ~ 'c_ops_class\s+constant text := ''return_strand''') is not true then v_bad := v_bad || ' read: not the return_strand roster'; end if;
    end if;
    -- arm ⓗ: the job lock before the loop, locked and bounded once, two handlers
    v_src := t_pig_src('_sweep_prerun_incidents');
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_sweep_prerun_incidents)';
    else
      p_a := position('pg_try_advisory_xact_lock(hashtextextended(''sweep_run_end_recovery'', 0))' in v_src);
      p_b := position('for r in' in v_src);
      if (p_a > 0 and p_b > 0 and p_a < p_b) is not true then v_bad := v_bad || ' arm ⓗ: the job lock is not ahead of the loop'; end if;
      select count(*)::int into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
      if v_n is distinct from 1 then v_bad := v_bad || ' arm ⓗ: row locks=' || v_n || ' (1)'; end if;
      select count(*)::int into v_n from regexp_matches(v_src, 'limit c_batch', 'g');
      if v_n is distinct from 1 then v_bad := v_bad || ' arm ⓗ: batch bounds=' || v_n || ' (1)'; end if;
      select count(*)::int into v_n from regexp_matches(v_src, 'exception when others', 'g');
      if v_n is distinct from 2 then v_bad := v_bad || ' arm ⓗ: handlers=' || v_n || ' (per-row + outer)'; end if;
    end if;
    v_src := t_pig_src('sweep_run_end_recovery');
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(sweep_run_end_recovery)';
    elsif (position('_sweep_prerun_incidents()' in v_src) > 0) is not true then v_bad := v_bad || ' the sweep does not call arm ⓗ'; end if;
    -- the incident arm names all three evidence columns, in BOTH consumers (whitespace collapsed)
    foreach fn in array array['_runner_work_gate_blocking', 'ops_gated_runners'] loop
      v_src := regexp_replace(t_pig_src(fn), '\s+', ' ', 'g');
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')'; continue; end if;
      if (position('(b.status::text = ''incident_review'' and (b.run_ended_at is not null or b.owner_confirmed_handoff_at is not null or b.runner_confirmed_handoff_at is not null))' in v_src) > 0) is not true
        then v_bad := v_bad || ' ' || fn || ': the incident arm is not the three-column evidence test'; end if;
      if (v_src ~ 'or b\.status::text = ''incident_review''\s*(or|\))') is not false
        then v_bad := v_bad || ' 🔴 ' || fn || ': an UNCONDITIONAL incident arm is still present'; end if;
    end loop;
    if v_bad = '' then call _pass('pig','0233-S1 배포 형상 — 정의자 다섯 모두 본문 search_path·유효 권한 양방향; 목록은 인자 0개, 주석 벗긴 소스에서 return_strand 명부 게이트가 읽기보다 앞; 팔 ⓗ는 잡 락이 루프 앞, 행 락 1·배치 상한 1·핸들러 2; 스윕이 팔 ⓗ를 부른다; 게이트와 ops_gated_runners의 사고 팔이 세 증거 열을 모두 묻고 무조건 팔은 없다');
    else v_msg := v_bad; call _fail('pig','0233-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('pig','0233-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
