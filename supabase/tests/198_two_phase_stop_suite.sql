-- ═══ 198 — 0168 두 단계 정지: the run-end two-phase stop ═════════════════════════════════════
--                                                            — 0168-P1 ~ 0168-P8 (tag `tps`)
--
-- What this file has to establish, in one sentence: **the host's tap stops the clock without
-- pricing anything, the runner's last uploaded segment is still counted for 90 s afterwards, a
-- point arriving after that is refused BY NAME, and the sweep that freezes the money measures to
-- the TAP and not to its own clock.**
--
-- 🔴 **LIVE MONEY, UN-FLAG-GATED.** The runner's `ledger_items` row is written with
--    `ops_flags.payments_live_since` NULL (`0083:754`), so every proposition here moves real
--    money today. The owner's COLLECTION is flagged; the payout is not.
--
-- ── THE TWO PINS THIS FILE EXISTS FOR, AND THEY ARE A CONTROL PAIR ─────────────────────────
-- **0168-P2** (a point after the window is refused) and **0168-P3** (a point INSIDE the window is
-- accepted AND counted). Name the failure each is blind to and the lists are different: P2 cannot
-- see over-refusal, P3 cannot see over-acceptance. A 「refuse everything」 fix — which is the
-- cheapest way to make the stale-trace race go away and is **the defect's own direction made
-- permanent**, under-paying every runner by one upload interval — passes P2 perfectly and reddens
-- P3 alone. That is what makes them two measurements rather than one printed twice.
--
-- ── THE FIXTURE, AND THE ONE THING IN IT THAT IS MANUFACTURED ──────────────────────────────
-- Every pairing is driven through the shipped chain, exactly as 176 does it:
--   `club_request_district` → `club_claim_host` → `club_create_session` → `session_runner_commit`
--   → `session_checkin` → `session_delegate_dog` → `session_approve_dog` → `session_pay_delegation`
--   → `session_assign_dog` → `session_proposal_respond` → handoff stamps + `picked_up`
--   → `club_start_delegated_runs` → `club_save_run_trace` → `club_end_pack_runs`
--   → `club_finalize_stopped_runs`
--
-- ⚠ **THREE WRITES ARE NOT AN RPC CALL, each for the reason 176's header gives:**
--  ① the handoff stamps + `status = 'picked_up'` — there is no SQL RPC for the door handoff; the
--    client calls `transition-booking`, which runs as `service_role`, and `_guard_booking_cols`
--    (`0058:263`) lets every server role through while `enforce_booking_transition` still
--    validates `confirmed → picked_up`. An UPDATE from this session IS that path.
--  ② `runs.started_at` is BACK-DATED — `now()` is transaction-start time, so inside one block
--    time cannot pass and every duration would be one second.
--  ③ 🔴 **`bookings.run_stopping_at` is BACK-DATED by 330 seconds** (`t198_drain`). Same reason as
--    ②, and it is the only thing in this file that the product does not do: the harness cannot
--    make 90 real seconds pass. The SWEEP itself is the shipped function, called with no
--    arguments exactly as `cron.job` calls it — a test-only parameter on a money function is a
--    door nobody else uses and everybody eventually finds.
--
-- ⚠ **WHY 330 AND NOT 120.** 0168-P5's fixture has to sit where the OLD rule and the NEW rule
--   DISAGREE, or it is testing the fixture (CLAUDE.md's fixture-agreement law). With the cutoff at
--   the tap the window closes at `tap + 60` (0156's grace); with the cutoff at the sweep's `now()`
--   it closes at `sweep + 60`. 330 s of back-date puts indices 28 and 29 of the reference trace
--   INSIDE that gap with ~30 s of margin on both boundaries — comfortably more than the one second
--   of `floor()` jitter, and the tap and the fixture share a transaction so there is no other
--   source of drift.
--
-- ⚠ **SUITE 176 LEAVES TWO BOOKINGS `stopping` FOREVER** (its dE has no trace and its dF derives
--   over band; Sean §8.3 (ii) says such a pair waits for a human). The sweep is GLOBAL, so it
--   picks them up on every call here and defers them again. **Every assertion below is therefore
--   made on THIS file's own bookings or on a delta it caused, never on the sweep's global
--   counters** — a count inherited from another suite's fixture is the purest form of a number
--   that would not change if the behaviour under test were deleted.
--
-- ── MUTATION BATTERY — PREDICTED FIRST, THEN MEASURED 2026-09-15 ──────────────────────────
-- Every mutation applied ALONE, against a COPY of `supabase/` outside the worktree (never by
-- editing the live file), as a trailing `0169_mut.sql` carrying the mutated `create or replace`.
-- ⚠ Each planter `&&`-chains its harness run, so a plant that fails to land yields **no row**
--   rather than a green one — 「assert the plant landed」 REPORTS, 「make the run impossible unless
--   it landed」 PREVENTS, and ui6 measured a battery table with two fictional green rows in it.
-- ⚠ `.pgtest` is excluded from the copy: a copied data dir is a broken cluster and every run dies
--   at the shim, which reads in a summary table as 「the mutation reddened everything」.
--
--   M0  THE CONTROL, unmutated copy — **1196 / 0**, identical to the worktree. Every number below
--       is meaningless without it, and a control that cannot PASS is as uninformative as one that
--       cannot fail.
--
--   #    mutation                                              PREDICTED      MEASURED
--   M1   the drain-window refusal deleted from                 [0168-P2]      1194/2 =
--        `club_save_run_trace` (both the raise and the                        **[0168-P2, 176 P9]**
--        loop selector's window conjunct)                                     — exact + the pin
--        0168-P2: 「거절 토큰=<no raise> 트레이스가 자랐다 (21→25)」. 176's reversed P9 rides along
--        because it owns the FROZEN half of the same rule, which is the division those two pins
--        were split on in the first place.
--   M2   the sweep's cutoff reverted to `now()`                 [P5, P8]      1194/2 =
--        **[0168-P5, 0168-P8]. EXACT.** P5: 「d5=2.90 🔴 창의 상한이 스윕의 now()로 돌아갔다」 —
--        the disagreement-zone fixture doing exactly its job, and the two pins are different KINDS
--        of evidence (a derived number vs the deployed body), neither implying the other.
--   M3   phase 1 stamps `run_ended_at` too                      [P7, P4]      1184/12 = superset
--        **The superset IS the finding and it is worth reading**: 0168-P7 names the hole
--        (「1단계가 run_ended_at을 찍었다」), P4 catches it one line earlier (「스윕 전
--        d4=…/frozen✓/km∅」 — stamped with NO km, which is the `Number(null) === 0` state), and
--        then the damage fans out: the drain refuses every in-window upload because the booking
--        reads as frozen (P1/P3/P5), 176's P7 dies at `unknown_end_reason` because the handler
--        reads a frozen row whose `end_reason` is NULL — **the runner is never paid** — and 176's
--        P12 loses the charging cutover. One column, eleven consequences.
--   M3b  the SAME plant, inside 0168 itself rather than after   [apply ABORT] **APPLY ABORTED**:
--        it, so the apply-time VERIFY is what is measured                     `0168 VERIFY: 🔴
--        phase1-STAMPS-run_ended_at`. M3 and M3b measure DIFFERENT propositions — 「the suite sees
--        it」 and 「the migration refuses to install it」 — and counting either as the other is the
--        「a green is evidence for exactly one sentence」 error.
--   M4   the 「refuse everything」 fix: every post-tap point      [P1, P3]      1193/3 =
--        refused, i.e. the drain's OPEN half closed                           **[0168-P1, P3, P5]**
--        P1: 「🔴 창 안의 업로드가 거절됐다: run_stopping … d1=2.00」 and P3: 「길이=21」. **0168-P2
--        stays GREEN**, which is the whole point of the control pair: the cheapest way to make the
--        stale-trace race disappear passes the refusal pin perfectly and under-pays every runner
--        by one upload interval, for ever. P5 rides along because its tail is part of the same
--        in-window upload.
--
--   **Zero dangerous greens: every mutation reddened at least the pin that owns it, and the two
--   controls (M0 clean, 0168-P2 green under M4) are what make the rest of the table readable.**
--
-- ⚠ Every arm asserts an EXACT boolean (`is distinct from` / an explicit compare), never a bare
--   `IF`. plpgsql does not take an `IF` on a NULL predicate, so a bare `if <expr>` is SILENT
--   precisely when the thing under test returned NULL — and half these pins exist to notice that
--   something is MISSING.
-- ⚠ The one SOURCE pin (0168-P8) strips comments before matching and carries a loud NO-SOURCE
--   arm. This file and 0168 both argue at length about the guards they add, and an un-stripped
--   check for CALLING something is satisfied by a comment EXPLAINING it.

set client_min_messages = warning;

-- ── context carried between transactions ───────────────────────────────────────────────────
create table if not exists t198_ctx (k text primary key, v text);
create or replace procedure t198_put(k text, v text) language sql as $$
  insert into t198_ctx values (k, v) on conflict (k) do update set v = excluded.v $$;
create or replace function t198_get(p_k text) returns text
language sql stable as $$ select v from t198_ctx where k = p_k $$;
create or replace function t198_id(p_k text) returns uuid
language sql stable as $$ select v::uuid from t198_ctx where k = p_k $$;

-- ── a synthetic trace in the SHIPPED shape: {lat,lng,t}, `t` in whole epoch SECONDS ─────────
-- `club/run/[sid].tsx:257-274` builds exactly this. The INDEX is explicit so a second batch can
-- continue the first one's geometry AND its clock: `club_save_run_trace` re-checks 8 m/s across
-- the join between the stored tail and the new head (`0156:105-108`), so a batch that restarts
-- the line somewhere else is refused as `impossible_speed` and the pin would measure that instead.
create or replace function t198_trace(p_from timestamptz, p_i0 int, p_n int, p_step int, p_metres numeric)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'lat', 37.5096 + (i * p_metres / 111000.0),
           'lng', 126.9954,
           't',   floor(extract(epoch from p_from))::bigint + 1 + (i * p_step)
         ) order by i), '[]'::jsonb)
  from generate_series(p_i0, p_i0 + p_n - 1) i
$$;

-- ── one pairing, driven through the shipped chain, up to (not including) the run start ──────
create or replace function t198_pair(p_sess uuid, p_tag text, p_runner uuid, p_host uuid)
returns uuid language plpgsql as $$
declare v_owner uuid; v_dog uuid; v_sd uuid;
begin
  v_owner := t_user('t198o_' || p_tag, 'owner');
  v_dog   := t_dog(v_owner, p_tag);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_sd := session_delegate_dog(p_sess, v_dog, t_consent());
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  perform session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  perform session_pay_delegation(v_sd, 't198-idem-' || p_tag, true);
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  perform session_assign_dog(v_sd, p_runner);
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  perform session_proposal_respond(v_sd, true);
  -- ① the door handoff — the service_role transition path (header note ①)
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
   where id = (select booking_id from session_dogs where id = v_sd);
  update bookings set status = 'picked_up'
   where id = (select booking_id from session_dogs where id = v_sd);
  perform set_config('request.jwt.claim.sub', '', false);
  return v_sd;
end $$;

create or replace function t198_bk(p_sd uuid) returns uuid
language sql stable as $$ select booking_id from session_dogs where id = p_sd $$;

-- ── ③ advance past the drain window, then run phase 2 (header note ③) ──────────────────────
create or replace function t198_drain(p_session uuid) returns jsonb
language plpgsql as $$
declare v_res jsonb;
begin
  update bookings set run_stopping_at = run_stopping_at - interval '330 seconds'
   where club_session_id = p_session
     and run_stopping_at is not null
     and run_ended_at is null;
  v_res := club_finalize_stopped_runs();
  return v_res;
end $$;

-- the state of one pairing, as ONE string, so a failure message names every axis at once
create or replace function t198_state(p_sd uuid) returns text
language sql stable as $$
  select (select b.status::text from bookings b where b.id = t198_bk(p_sd))
      || '/' || case when (select b.run_stopping_at from bookings b where b.id = t198_bk(p_sd)) is null
                     then 'stopping∅' else 'stopping✓' end
      || '/' || case when (select b.run_ended_at from bookings b where b.id = t198_bk(p_sd)) is null
                     then 'frozen∅' else 'frozen✓' end
      || '/' || coalesce((select r.actual_km::text from runs r where r.booking_id = t198_bk(p_sd)), 'km∅')
      || '/' || coalesce((select r.duration_sec::text from runs r where r.booking_id = t198_bk(p_sd)), 'dur∅')
$$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 1 — the fixture, the tap, the drain, the sweep, and everything each of them establishes
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_host uuid; r1 uuid; r2 uuid; r3 uuid; r4 uuid; r5 uuid; r6 uuid; r7 uuid;
  v_club uuid; v_s uuid; v_s2 uuid; v_s3 uuid; v_route uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; p1 uuid; q1 uuid;
  v_t0 timestamptz; v_res jsonb; v_sweep jsonb; v_tap timestamptz; v_stop timestamptz;
  v_bad text; v_err text; v_n int; v_before int; v_after int;
  v_led0 int; v_led1 int; v_win_open boolean; v_win_shut boolean;
  v_km_before numeric; v_stamp_before timestamptz; v_sweep2 jsonb; v_drain_err text;
begin
  update club_flags set enabled = true where name = 'club_delegation_v2';

  -- ── people ───────────────────────────────────────────────────────────────────────────────
  v_host := t_user('t198_host', 'runner');
  r1 := t_user('t198_r1', 'runner'); r2 := t_user('t198_r2', 'runner');
  r3 := t_user('t198_r3', 'runner'); r4 := t_user('t198_r4', 'runner');
  r5 := t_user('t198_r5', 'runner'); r6 := t_user('t198_r6', 'runner');
  r7 := t_user('t198_r7', 'runner');
  update runners set tier = 'veteran'
   where profile_id in (v_host, r1, r2, r3, r4, r5, r6, r7);

  v_route := t_route('t198 반포 코스');

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_club := club_request_district('t198동');
  perform club_claim_host(v_club);
  v_s  := club_create_session(v_club, now() + interval '90 minutes', 't198 집결지', v_route, 20, 'mixed');
  -- a SECOND session, used by 0168-P7 alone: `_club_pack_window` closes on the FIRST frozen
  -- booking in a session, so a window transition measured on `v_s` would be decided by whichever
  -- of five dogs the sweep reached first rather than by the state under test.
  v_s2 := club_create_session(v_club, now() + interval '90 minutes', 't198 집결지 2', v_route, 20, 'mixed');
  -- a THIRD session, used by 0168-P2 alone and deliberately NOT tapped in this block. P2 has to
  -- measure the window's TERMINATOR — drain expired, nothing frozen yet — and on any session this
  -- block sweeps, `run_ended_at is not null` would satisfy the same refusal for a different
  -- reason. Two causes behind one token is exactly the 「a detector whose pattern appears in both
  -- states」 shape; 176's reversed P9 owns the frozen half, this owns the drain half.
  v_s3 := club_create_session(v_club, now() + interval '90 minutes', 't198 집결지 3', v_route, 20, 'mixed');
  perform session_runner_commit(v_s);  perform session_checkin(v_s);
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform session_runner_commit(v_s3); perform session_checkin(v_s3);

  perform set_config('request.jwt.claim.sub', r1::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', r3::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', r4::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', r5::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', r6::text, false);
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform set_config('request.jwt.claim.sub', r7::text, false);
  perform session_runner_commit(v_s3); perform session_checkin(v_s3);
  perform set_config('request.jwt.claim.sub', '', false);

  -- ── the pairings ─────────────────────────────────────────────────────────────────────────
  --   d1 (r1)  base + a late batch uploaded INSIDE the drain   → 2.40 km   [P1, P3]
  --   d2 (r2)  base only — the REFERENCE                       → 2.00 km   [P1's delta]
  --   d3 (r3)  base + an upload AFTER the drain closed         → refused   [P2]
  --   d4 (r4)  base, then silence: the phone never speaks again → 2.00 km  [P4, INACTION]
  --   d5 (r5)  base + a tail dated in the tap↔sweep gap        → 2.70 km   [P5]
  --   p1 (r6)  one dog on the second session                   → [P7]
  --   q1 (r7)  one dog on the third session, tapped in BLOCK 2  → [P2]
  d1 := t198_pair(v_s,  'd1', r1, v_host);
  d2 := t198_pair(v_s,  'd2', r2, v_host);
  d3 := t198_pair(v_s,  'd3', r3, v_host);
  d4 := t198_pair(v_s,  'd4', r4, v_host);
  d5 := t198_pair(v_s,  'd5', r5, v_host);
  p1 := t198_pair(v_s2, 'p1', r6, v_host);
  q1 := t198_pair(v_s3, 'q1', r7, v_host);

  perform set_config('request.jwt.claim.sub', r1::text, false);
  perform club_start_delegated_runs(v_s);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform club_start_delegated_runs(v_s);
  perform set_config('request.jwt.claim.sub', r3::text, false);
  perform club_start_delegated_runs(v_s);
  perform set_config('request.jwt.claim.sub', r4::text, false);
  perform club_start_delegated_runs(v_s);
  perform set_config('request.jwt.claim.sub', r5::text, false);
  perform club_start_delegated_runs(v_s);
  perform set_config('request.jwt.claim.sub', r6::text, false);
  perform club_start_delegated_runs(v_s2);
  perform set_config('request.jwt.claim.sub', r7::text, false);
  perform club_start_delegated_runs(v_s3);
  perform set_config('request.jwt.claim.sub', '', false);

  -- ② back-date the starts (header note ②)
  v_t0 := now() - interval '32 minutes';
  update runs set started_at = v_t0
   where booking_id in (t198_bk(d1), t198_bk(d2), t198_bk(d3), t198_bk(d4), t198_bk(d5),
                        t198_bk(p1), t198_bk(q1));

  -- ── the base traces, uploaded through the shipped RPC by the runner who owns each ─────────
  -- 21 points, 60 s apart, 100 m per step → 20 segments → 2.00 km, every point far inside the
  -- window under either rule.
  perform set_config('request.jwt.claim.sub', r1::text, false);
  perform club_save_run_trace(v_s, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform club_save_run_trace(v_s, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r3::text, false);
  perform club_save_run_trace(v_s, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r4::text, false);
  perform club_save_run_trace(v_s, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r5::text, false);
  perform club_save_run_trace(v_s, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r6::text, false);
  perform club_save_run_trace(v_s2, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r7::text, false);
  perform club_save_run_trace(v_s3, t198_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', '', false);

  select count(*) into v_led0 from ledger_items;

  -- ═══ THE TAP — phase 1 ═══════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_res  := club_end_pack_runs(v_s);
  perform club_end_pack_runs(v_s2);
  perform set_config('request.jwt.claim.sub', '', false);
  v_tap  := (v_res->>'at')::timestamptz;
  v_stop := v_tap - interval '330 seconds';   -- what the back-date below will make it

  -- ═══ UPLOADS INSIDE THE DRAIN WINDOW — the tap has happened and the window is OPEN ════════
  -- This is the segment the defect threw away: real GPS the phone was holding when the host
  -- tapped. Both batches continue their own base trace's index, so the geometry and the clock
  -- join cleanly and `club_save_run_trace`'s 8 m/s re-check across the join (0156:105-108) passes
  -- — a batch that restarted the line elsewhere would be refused as `impossible_speed` and every
  -- pin below would be measuring that instead.
-- ⚠ CAUGHT, not allowed to escape, and the reason is a measured one: under a 「refuse everything」
  -- mutation these two calls RAISE, and an uncaught raise here takes the whole fixture down — every
  -- pin in this block then reports 「BLOCK1 died」 instead of the one that owns the property
  -- (0144's per-pairing subtransaction discipline, and 176's M6′ recorded the same lesson). The
  -- refusal is carried to 0168-P1, which is the pin whose sentence it falsifies.
  begin
    perform set_config('request.jwt.claim.sub', r1::text, false);
    perform club_save_run_trace(v_s, t198_trace(v_t0, 21, 4, 60, 100)); -- +4 fixes, +400 m → 2.40
    -- d5's tail lands in the gap between the two candidate cutoffs and NOWHERE else: with the
    -- back-date at 330 s, indices 28-29 are past `tap + 60` and inside `sweep + 60`.
    perform set_config('request.jwt.claim.sub', r5::text, false);
    perform club_save_run_trace(v_s, t198_trace(v_t0, 21, 9, 60, 100)); -- i=21..29
    v_drain_err := '';
  exception when others then v_drain_err := sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', false);

  call t198_put('s', v_s::text);   call t198_put('s2', v_s2::text);
  call t198_put('host', v_host::text);
  call t198_put('d1', d1::text);   call t198_put('d2', d2::text);
  call t198_put('d3', d3::text);   call t198_put('d4', d4::text);
  call t198_put('d5', d5::text);   call t198_put('p1', p1::text);
  call t198_put('q1', q1::text);   call t198_put('r7', r7::text);
  call t198_put('s3', v_s3::text);
  call t198_put('r3', r3::text);   call t198_put('r4', r4::text);
  call t198_put('stop', v_stop::text);

  -- ═══ [0168-P7] `run_ended_at` KEEPS ITS MEANING — and the pack map stays open ════════════
  -- Two consequences of the same fact, and they fail in opposite directions. The map is measured
  -- as a DELTA this pin causes: open while `stopping`, shut after the freeze.
  begin
    v_bad := '';
    if (select run_ended_at from bookings where id = t198_bk(p1)) is not null
      then v_bad := v_bad || ' 🔴 1단계가 run_ended_at을 찍었다 — settle-run의 frozen 경로가 무장하고 Number(null)===0으로 0km 정산이 된다'; end if;
    if (select run_stopping_at from bookings where id = t198_bk(p1)) is null
      then v_bad := v_bad || ' 1단계가 run_stopping_at을 찍지 않았다'; end if;
    v_win_open := _club_pack_window(v_s2);
    if v_win_open is distinct from true
      then v_bad := v_bad || ' 정지 중인데 팩 지도 창이 이미 닫혔다 (보호자의 라이브 지도가 러닝 도중 죽는다)'; end if;

    perform t198_drain(v_s2);

    if (select run_ended_at from bookings where id = t198_bk(p1)) is null
      then v_bad := v_bad || ' 스윕이 동결하지 않았다'; end if;
    v_win_shut := _club_pack_window(v_s2);
    if v_win_shut is distinct from false
      then v_bad := v_bad || ' 동결 뒤에도 팩 지도 창이 열려 있다 (0159의 문장이 깨졌다)'; end if;

    if v_bad = ''
      then call _pass('tps','0168-P7 run_ended_at은 지금까지의 뜻을 그대로 지킨다 — 「숫자가 얼었다」. 1단계는 그것을 찍지 않는다: 찍으면 settle-run:90의 frozen 경로가 무장하고 readFrozenRun이 Number(null)===0으로 **0 km 정산**을 만들며(밴드·플로어 검사는 그 경로에서 전부 건너뛴다), 동시에 0159:148-154가 팩 지도 채널을 러닝 한가운데서 닫아 보호자의 라이브 지도를 죽인다. 두 결과를 하나의 델타로 잰다: 정지 중에는 창이 열려 있고, 스윕이 동결한 뒤에 닫힌다 — 이 핀이 스스로 일으킨 변화다');
      else call _fail('tps','0168-P7 run_ended_at keeps its meaning', v_bad); end if;
  exception when others then call _fail('tps','0168-P7 run_ended_at keeps its meaning', sqlerrm);
  end;

  -- ═══ [0168-P4] INACTION — the host taps and the phone never speaks again ════════════════
  -- BEFORE the sweep. This is the only moment the phase-1 state is observable, and it is the one
  -- arm that can tell 「the tap stops the clock」 from 「the tap freezes the money two lines
  -- earlier」: every later assertion in this file is green under both designs.
  begin
    v_bad := '';
    if t198_state(d4) is distinct from 'active/stopping✓/frozen∅/km∅/dur∅'
      then v_bad := v_bad || ' 스윕 전 d4=' || t198_state(d4); end if;
    select count(*) into v_n from ledger_items where booking_id = t198_bk(d4);
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 스윕 전 원장 행=' || v_n; end if;
    select count(*) into v_led1 from ledger_items;
    if v_led1 is distinct from v_led0
      then v_bad := v_bad || ' 🔴 탭이 원장을 움직였다 +' || (v_led1 - v_led0); end if;

    -- and the settle door is SHUT while the numbers do not exist. `settle_run_tx` is revoked from
    -- `authenticated` (0083:838) so the reachable door is the edge function, which refuses on
    -- exactly this predicate (`run_stopping_at is not null and run_ended_at is null`) — the SQL
    -- side of that refusal is the NAMED GAP in 0168's header and the assertion here is on the
    -- STATE the handler reads, not on the handler.
    if (select run_stopping_at is not null and run_ended_at is null
          from bookings where id = t198_bk(d4)) is not true
      then v_bad := v_bad || ' 엣지 함수가 읽는 stopping 술어가 참이 아니다'; end if;

    -- ── AFTER the sweep: derived over what actually arrived, and nothing invented ──────────
    v_sweep := t198_drain(v_s);

    -- 1590 = 1920 (started_at, 32 minutes back) − 330 (the drain back-date). Duration is measured
    -- to the TAP (Sean 2026-08-26 ③) and the harness's tap is the back-dated one, so this literal
    -- is the fixture's arithmetic rather than a product constant.
    if t198_state(d4) is distinct from 'active/stopping✓/frozen✓/2.00/1590'
      then v_bad := v_bad || ' 스윕 후 d4=' || t198_state(d4); end if;
    if (select run_ended_at from bookings where id = t198_bk(d4)) is distinct from v_stop
      then v_bad := v_bad || ' 동결 시각이 탭이 아니다'; end if;
    if (select ended_at from runs where booking_id = t198_bk(d4)) is distinct from v_stop
      then v_bad := v_bad || ' runs.ended_at이 탭이 아니다 (과금 컷오버가 스윕의 시계가 됐다)'; end if;
    select count(*) into v_n from ledger_items where booking_id = t198_bk(d4);
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 스윕이 원장 행을 만들었다=' || v_n; end if;

    -- ── the sweep is REGISTERED, and the command it runs names a function that EXISTS ──────
    -- A scheduler faithfully running `select no_such_fn()` is the same product outcome as no
    -- scheduler at all, and this is the arm that makes 「unregister the sweep」 a mutation that
    -- reddens something: the pin itself calls the function directly, so without these arms the
    -- registration would be checked only by 0168's one-shot VERIFY.
    select count(*)::int into v_n
      from cron.job
     where jobname = 'finalize-stopped-runs'
       and active
       and command = 'select club_finalize_stopped_runs()';
    if v_n is distinct from 1 then v_bad := v_bad || ' 크론 등록=' || coalesce(v_n::text,'NULL'); end if;
    if to_regprocedure('public.club_finalize_stopped_runs()') is null
      then v_bad := v_bad || ' 크론이 부르는 함수가 존재하지 않는다'; end if;

    if v_bad = ''
      then call _pass('tps','0168-P4 💰 무행동에 답한다 — 호스트가 탭했고 러너의 폰은 다시 말하지 않으며 러너는 정산하지 않는다. **스윕 전**: run_stopping_at만 찍혀 있고 run_ended_at도 actual_km도 NULL이며 원장은 0행이다(탭 자체가 원장을 한 줄도 움직이지 않는다). **스윕 후**: 실제로 도착한 트레이스로 2.00 km이 도출되고 run_ended_at과 runs.ended_at이 **탭 시각**으로 찍히며 원장은 여전히 0행이다 — 동결은 돈이 아니라 숫자다. 크론 등록은 행으로 다시 읽고(0157 §A의 법: schedule의 반환은 주장이고 cron.job의 행이 사실이다) 그 명령이 부르는 함수가 실제로 존재하는지까지 본다 — 이 두 팔이 없으면 「스윕을 등록 해제한다」는 변이가 아무것도 빨갛게 만들지 않는다');
      else call _fail('tps','0168-P4 inaction', v_bad); end if;
  exception when others then call _fail('tps','0168-P4 inaction', sqlerrm);
  end;

  -- ═══ [0168-P1] 💰 THE MONEY — a point uploaded INSIDE the window is PRICED ═══════════════
  -- Asserted as a DELTA against a twin that differs in exactly one thing: d1 and d2 hold the same
  -- base trace, the same started_at and the same tap, and d1 alone received the late batch. A pin
  -- that asserted only 「d1 = 2.40」 could not distinguish 「the late segment was counted」 from
  -- 「the fixture always produced 2.40」.
  begin
    v_bad := '';
    -- the window was OPEN when these landed, so a refusal here is this pin's failure and not a
    -- fixture accident
    if v_drain_err is distinct from ''
      then v_bad := v_bad || ' 🔴 창 안의 업로드가 거절됐다: ' || v_drain_err; end if;
    if (select actual_km from runs where booking_id = t198_bk(d2)) is distinct from 2.00
      then v_bad := v_bad || ' 기준 d2=' || coalesce((select actual_km::text from runs where booking_id = t198_bk(d2)),'NULL'); end if;
    if (select actual_km from runs where booking_id = t198_bk(d1)) is distinct from 2.40
      then v_bad := v_bad || ' d1=' || coalesce((select actual_km::text from runs where booking_id = t198_bk(d1)),'NULL'); end if;
    -- the delta itself, stated separately so a fixture that drifted to 2.40 on both sides fails
    if (select actual_km from runs where booking_id = t198_bk(d1))
       <= (select actual_km from runs where booking_id = t198_bk(d2))
      then v_bad := v_bad || ' 🔴 배수 창 안에 올라온 구간이 거리에 반영되지 않았다'; end if;
    -- both were frozen to the same tap, so the difference cannot be a clock difference
    if (select run_ended_at from bookings where id = t198_bk(d1))
       is distinct from (select run_ended_at from bookings where id = t198_bk(d2))
      then v_bad := v_bad || ' 두 쌍의 동결 시각이 다르다 (델타가 창 때문이라고 말할 수 없다)'; end if;
    if v_bad = ''
      then call _pass('tps','0168-P1 💰 배수 창 안에 도착한 GPS는 돈이 된다 — 같은 기준 트레이스·같은 started_at·같은 탭을 가진 쌍둥이 두 마리 중 d1만 창 안에서 마지막 구간(4픽스, 400 m)을 더 올렸고, 동결된 거리는 2.40 대 2.00이다. 이것이 계약이 (a) 순수 거절을 거부한 이유다: 창을 아예 닫으면 매 러닝마다 한 번의 업로드 주기만큼의 **진짜 GPS**를 버리고 모든 러너를 설계상 과소 지급하게 된다 — 결함이 향하던 바로 그 방향을, 영구히. 델타로 잰다: 「d1=2.40」만 주장하는 핀은 픽스처가 원래 2.40이었을 가능성과 구별되지 않는다');
      else call _fail('tps','0168-P1 the drain is priced', v_bad); end if;
  exception when others then call _fail('tps','0168-P1 the drain is priced', sqlerrm);
  end;

  -- ═══ [0168-P5] 0156 IS NOT WIDENED — the window ends at the TAP, not at the sweep ════════
  -- d5's tail sits in the gap between the two candidate rules and nowhere else: indices 28-29 are
  -- OUTSIDE `tap + 60` and INSIDE `sweep + 60`. Old rule → 2.90, new rule → 2.70 (MEASURED, and the
  -- first draft of this pin predicted 2.80 by miscounting segments — n points are n-1 segments).
  -- A fixture whose
  -- points agreed under both rules would be testing the fixture (CLAUDE.md's law), which is
  -- exactly how a predicate change ships unnoticed.
  begin
    v_bad := '';
    -- the fixture's own precondition: the tail really is STORED, so an absent km cannot be
    -- mistaken for a window that excluded it
    if (select jsonb_array_length(trace) from runs where booking_id = t198_bk(d5)) is distinct from 30
      then v_bad := v_bad || ' 전제 붕괴: d5 트레이스 길이=' ||
           coalesce((select jsonb_array_length(trace)::text from runs where booking_id = t198_bk(d5)),'NULL'); end if;
    if (select actual_km from runs where booking_id = t198_bk(d5)) is distinct from 2.70
      then v_bad := v_bad || ' d5=' || coalesce((select actual_km::text from runs where booking_id = t198_bk(d5)),'NULL'); end if;
    -- and the value the REVERTED rule would have produced, named so the pin says what it excludes
    if (select actual_km from runs where booking_id = t198_bk(d5)) = 2.90
      then v_bad := v_bad || ' 🔴 창의 상한이 스윕의 now()로 돌아갔다 (0156의 머니 가드가 배수 창만큼 넓어졌다)'; end if;
    if v_bad = ''
      then call _pass('tps','0168-P5 💰 0156의 머니 가드는 넓어지지 않았다 — 도출 창의 상한은 **탭**이지 스윕의 now()가 아니다. 0156은 「이 함수는 프리즈 트랜잭션 안에서만 불리므로 now()가 곧 탭」이라고 적고 그 근거로 파라미터를 넣지 않았는데(0156:16-20), 두 단계 정지는 그 문장을 거짓으로 만든다. 픽스처는 두 규칙이 **갈리는 구간에만** 점을 둔다: 인덱스 28·29는 탭+60 밖이고 스윕+60 안이다. 새 규칙 2.70, 옛 규칙 2.90 — 두 값을 모두 적어 두어 핀이 무엇을 배제하는지 말하게 한다. 두 규칙이 일치하는 곳에 픽스처를 두면 술어 변경이 보이지 않는다');
      else call _fail('tps','0168-P5 the cutoff is the tap', v_bad); end if;
  exception when others then call _fail('tps','0168-P5 the cutoff is the tap', sqlerrm);
  end;

  -- ═══ [0168-P6] IDEMPOTENCE, AS A DELTA THIS PIN CAUSED ══════════════════════════════════
  -- The pin runs phase 2 a SECOND time itself and compares its own before to its own after. A
  -- count inherited from the fixture would be the same number whether or not the guard exists.
  begin
    v_bad := '';
    select actual_km into v_km_before from runs where booking_id = t198_bk(d1);
    select run_ended_at into v_stamp_before from bookings where id = t198_bk(d1);
    select count(*) into v_before from ledger_items;

    v_sweep2 := club_finalize_stopped_runs();

    select count(*) into v_after from ledger_items;
    if (select actual_km from runs where booking_id = t198_bk(d1)) is distinct from v_km_before
      then v_bad := v_bad || ' 두 번째 스윕이 km을 다시 썼다'; end if;
    if (select run_ended_at from bookings where id = t198_bk(d1)) is distinct from v_stamp_before
      then v_bad := v_bad || ' 두 번째 스윕이 동결 시각을 덮었다'; end if;
    if v_after is distinct from v_before
      then v_bad := v_bad || ' 두 번째 스윕이 원장을 움직였다 +' || (v_after - v_before); end if;
    -- this file's OWN bookings, never the sweep's global counters: suite 176 leaves two pairings
    -- `stopping` forever by design and they are deferred on every call here
    if (select count(*) from jsonb_array_elements(v_sweep2->'pending') e
         where (e->>'bookingId')::uuid in (t198_bk(d1), t198_bk(d2), t198_bk(d3),
                                           t198_bk(d4), t198_bk(d5))) <> 0
      then v_bad := v_bad || ' 이미 동결된 쌍이 두 번째 스윕의 pending에 있다'; end if;
    if v_bad = ''
      then call _pass('tps','0168-P6 두 번째 스윕은 오류가 아니라 무동작이다 — 이 핀이 직접 phase 2를 한 번 더 돌리고 자기가 일으킨 전후를 비교한다: km도, 동결 시각도, 원장 행 수도 움직이지 않는다. 멱등 키는 반환 토큰도 개수도 아니고 **행 락 아래에서 다시 읽은 run_ended_at is null**이다. 픽스처에서 물려받은 숫자를 읽는 핀은 행동을 통째로 지워도 같은 값을 돌려주므로 아무것도 재지 않는다 — 그래서 여기서는 스윕의 전역 카운터를 보지 않는다(스위트 176은 설계상 두 쌍을 영원히 stopping으로 남긴다)');
      else call _fail('tps','0168-P6 idempotence', v_bad); end if;
  exception when others then call _fail('tps','0168-P6 idempotence', sqlerrm);
  end;

exception when others then
  call _fail('tps','BLOCK1 fixtures + tap + drain + sweep', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 2 — the CONTROL PAIR. A NEW TRANSACTION, so the window's two sides are measured apart.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0168-P3 runs on `d1`'s history — the late batch it received in BLOCK 1 was accepted while the
-- window was open, and this pin asserts that acceptance as a FACT about the stored trace rather
-- than re-deriving it from P1's km. 0168-P2 then closes the same window on `d3` and asserts the
-- refusal by NAME. Blind-spot lists: P3 cannot see over-acceptance, P2 cannot see over-refusal.
do $$
declare v_bad text := ''; v_err text; v_before int; v_after int; v_km numeric;
        d1 uuid; q1 uuid; v_t0 timestamptz;
begin
  d1 := t198_id('d1'); q1 := t198_id('q1');

  -- ═══ [0168-P3] CONTROL — the OPEN window still accepts, and what it accepted was counted ══
  begin
    v_bad := '';
    -- 21 base + 4 late. A 「refuse everything」 fix leaves 21 here and reddens this pin alone.
    if (select jsonb_array_length(trace) from runs where booking_id = t198_bk(d1)) is distinct from 25
      then v_bad := v_bad || ' 창 안의 업로드가 저장되지 않았다: 길이=' ||
           coalesce((select jsonb_array_length(trace)::text from runs where booking_id = t198_bk(d1)),'NULL'); end if;
    if (select jsonb_array_length(trace) from runs
         where booking_id = t198_bk(t198_id('d2'))) is distinct from 21
      then v_bad := v_bad || ' 기준 d2의 트레이스가 21이 아니다'; end if;
    if (select actual_km from runs where booking_id = t198_bk(d1)) is distinct from 2.40
      then v_bad := v_bad || ' 받아들인 구간이 거리에 반영되지 않았다'; end if;
    if v_bad = ''
      then call _pass('tps','0168-P3 통제 — 창이 열려 있는 동안 club_save_run_trace는 여전히 받아들이고, 받아들인 것은 거리가 된다. 이 팔이 못 보는 실패는 **과잉 수용**이고 P2가 못 보는 실패는 **과잉 거절**이다 — 두 목록이 다르므로 진짜 통제 한 쌍이지 한 측정을 두 번 인쇄한 것이 아니다. 「탭 이후 전부 거절」은 P2를 완벽히 통과하면서 이 핀만 빨갛게 만든다, 그리고 그것이 바로 결함이 향하던 방향을 영구화하는 수정이다');
      else call _fail('tps','0168-P3 the open window accepts', v_bad); end if;
  exception when others then call _fail('tps','0168-P3 the open window accepts', sqlerrm);
  end;

  -- ═══ [0168-P2] THE REFUSAL — a point after the window is refused BY NAME ═════════════════
  begin
    v_bad := '';
    -- the third session is tapped HERE and never swept, so the only thing closing the window is
    -- the drain itself. `run_ended_at` is asserted NULL below for exactly that reason: with a
    -- frozen booking the same token would fire for a different cause and the pin would not be
    -- measuring the drain at all.
    perform set_config('request.jwt.claim.sub', t198_get('host'), false);
    perform club_end_pack_runs(t198_id('s3'));
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set run_stopping_at = run_stopping_at - interval '330 seconds'
     where id = t198_bk(q1);

    select jsonb_array_length(trace), actual_km, started_at into v_before, v_km, v_t0
      from runs where booking_id = t198_bk(q1);
    if (select run_ended_at from bookings where id = t198_bk(q1)) is not null
      then v_bad := v_bad || ' 전제 붕괴: 이 쌍은 이미 동결돼 있다 (거절의 원인이 배수 창이 아니다)'; end if;
    if (select run_stopping_at from bookings where id = t198_bk(q1)) is null
      then v_bad := v_bad || ' 전제 붕괴: 정지 스탬프가 없다'; end if;

    perform set_config('request.jwt.claim.sub', t198_get('r7'), false);
    begin
      perform club_save_run_trace(t198_id('s3'), t198_trace(v_t0, 21, 4, 60, 100));
      v_err := '<no raise>';
    exception when others then v_err := sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    select jsonb_array_length(trace) into v_after from runs where booking_id = t198_bk(q1);

    -- 🔴 the TOKEN, not merely 「it raised」. `impossible_speed` and `trace_out_of_order` stay in
    -- the retry banner because they genuinely are retryable; this one is permanent, and telling a
    -- runner it will retry automatically is a lie the client would tell with no change on our side.
    if (v_err ~ 'run_stopping') is not true then v_bad := v_bad || ' 거절 토큰=' || v_err; end if;
    if v_after is distinct from v_before
      then v_bad := v_bad || ' 트레이스가 자랐다 (' || v_before || '→' || v_after || ')'; end if;
    if (select actual_km from runs where booking_id = t198_bk(q1)) is distinct from v_km
      then v_bad := v_bad || ' 도출된 숫자가 움직였다'; end if;
    if v_bad = ''
      then call _pass('tps','0168-P2 배수 창이 닫힌 뒤의 업로드는 **이름을 붙여** 거절된다 — run_stopping이고, 트레이스는 한 점도 자라지 않는다. 조용히 버리는 것과 거절하는 것의 차이가 이 핀의 전부다: 조용히 버리면 러너 입장에서 「반영된 업로드」와 구별되지 않고, 176 P9가 측정으로 기록해 두었던 그 창이 바로 결함이었다. 토큰으로 잰다 — 「예외가 났다」로는 retryable한 impossible_speed와 구별되지 않고, 영구 거절을 「자동 재시도해요」 배너로 보여 주는 것이 지금 클라이언트가 하던 거짓말이다');
      else call _fail('tps','0168-P2 the closed window refuses by name', v_bad); end if;
  exception when others then call _fail('tps','0168-P2 the closed window refuses by name', sqlerrm);
  end;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 3 — 0168-P8: the guard's PRECONDITIONS, read from the DEPLOYED body
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **THIS IS A SOURCE PIN AND IT HAS TO BE, and saying why is part of the pin.** The harness is
--   a single connection: `for update` can never be observed to BLOCK anything here, so there is no
--   behavioural instrument for the lock at all. Removing it would leave every other pin in this
--   file green — which is the 「a guard with no pin is invisible from both directions」 class, and
--   the only available detector is the deletion. Source is a different KIND of evidence from the
--   behavioural pins above and neither is evidence for the other.
-- ⚠ Comments are stripped before every match. 0168 documents the lock, the cutoff and the freeze
--   clock at length, and an un-stripped check for CALLING something is satisfied by a comment
--   EXPLAINING it — the more carefully the guard is documented, the more surely the check passes.
-- ⚠ A loud NO-SOURCE arm: with `prosrc` NULL every `~` below is NULL, every `is not true` fires
--   correctly, but the message would not say WHY.
do $$
declare v_src text; v_raw text; v_bad text := '';
begin
  select regexp_replace(prosrc, '--[^\n]*', '', 'g'), prosrc into v_src, v_raw
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_finalize_stopped_runs';

  if v_src is null then v_bad := v_bad || ' NO-SOURCE(club_finalize_stopped_runs)'; end if;

  -- ① THE LOCK — the precondition, not the branch. Every `run_ended_at is null` read below it is
  --    an opinion without it: two ticks would both pass and both write the freeze.
  if (v_src ~ 'from bookings bk where bk\.id = r\.booking_id for update') is not true
    then v_bad := v_bad || ' 🔴 부킹 행 락이 없다 (멱등성 팔 전부가 의미를 잃는다)'; end if;
  -- ② THE CUTOFF IS THE TAP — escalation ①. `now()` here silently widens the paid window by the
  --    whole drain and reverts 0156's money guard from a file that never mentions it.
  if (v_src ~ '_club_derive_run_km\(v_trace, v_start, v_stop\)') is not true
    then v_bad := v_bad || ' 🔴 도출에 탭 시각을 넘기지 않는다'; end if;
  if (v_src ~ '_club_derive_run_km\([^)]*now\(\)') is not false
    then v_bad := v_bad || ' 🔴 도출 컷오프가 now() 다 — 0156이 되돌려졌다'; end if;
  -- ③ THE FREEZE CLOCK IS THE TAP — runs.ended_at is the charging cutover and duration is
  --    measured to the host's tap (Sean 2026-08-26 ③).
  if (v_src ~ 'v_stop := v_bk\.run_stopping_at') is not true
    then v_bad := v_bad || ' 동결 시각이 탭에서 오지 않는다'; end if;
  -- ④ and the comment-stripping is doing real work: the RAW source names all three, so a check
  --    that skipped the strip would pass on a body that only TALKED about them.
  if (v_raw ~ 'for update') is not true then v_bad := v_bad || ' RAW-SOURCE 자체가 비어 있다'; end if;

  -- ── the envelope: a definer with no in-body search_path is 98 H1's whole subject, and an
  --    ACL-open sweep over this table is an arbitrary-freeze injector
  if (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'club_finalize_stopped_runs') is not true
    then v_bad := v_bad || ' definer가 아니다'; end if;
  if (select 'search_path=public, pg_temp' = any(proconfig) from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'club_finalize_stopped_runs') is not true
    then v_bad := v_bad || ' search_path가 본문에 없다'; end if;
  if has_function_privilege('public',        'public.club_finalize_stopped_runs()', 'execute') is distinct from false
    then v_bad := v_bad || ' public이 실행 가능'; end if;
  if has_function_privilege('anon',          'public.club_finalize_stopped_runs()', 'execute') is distinct from false
    then v_bad := v_bad || ' anon이 실행 가능'; end if;
  if has_function_privilege('authenticated', 'public.club_finalize_stopped_runs()', 'execute') is distinct from false
    then v_bad := v_bad || ' 🔴 authenticated가 실행 가능 (누구나 남의 러닝을 동결시킬 수 있다)'; end if;
  -- the over-reach arm: revoke too far and the cron installs and never fires
  if has_function_privilege('service_role',  'public.club_finalize_stopped_runs()', 'execute') is distinct from true
    then v_bad := v_bad || ' service_role가 실행 불가 (크론이 영원히 아무것도 안 한다)'; end if;

  -- ── and the derivation helper has exactly ONE signature. A re-added 2-arg overload is a
  --    now()-bounded money door with no caller and no pin, and every ACL arm on the 3-arg form
  --    stays perfectly green beside it.
  if (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = '_club_derive_run_km') is distinct from 1
    then v_bad := v_bad || ' 🔴 _club_derive_run_km 오버로드가 하나가 아니다'; end if;

  if v_bad = ''
    then call _pass('tps','0168-P8 가드가 **읽는 것**까지 잰다 — 분기만이 아니라 전제. 스윕은 run_stopping_at을 읽기 전에 부킹 행을 잠그고(락이 없으면 두 틱이 같은 run_ended_at is null을 통과해 둘 다 동결한다), 도출에 스윕의 now()가 아니라 **탭 시각**을 넘기며, 동결 시각도 탭에서 온다. 하네스는 단일 연결이라 for update가 막는 것을 행동으로 볼 방법이 아예 없다 — 지우면 이 파일의 다른 모든 핀이 초록인 채로 남는다. 그래서 소스이고, 주석은 제거하고 읽는다(설명하는 주석과 호출하는 코드는 grep에게 똑같이 보인다). 봉인도 같은 자리에서: definer · 본문 search_path · 네 역할 중 service_role만, 그리고 도출 헬퍼의 시그니처는 정확히 하나다');
    else call _fail('tps','0168-P8 the guard preconditions', v_bad); end if;
exception when others then call _fail('tps','0168-P8 the guard preconditions', sqlerrm);
end $$;
