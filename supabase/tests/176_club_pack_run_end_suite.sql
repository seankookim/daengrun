-- ═══ 176 — 0144 러닝 종료: the club pack run-end fan-out ═════════════════════════════════════
--
-- What this file has to establish, in one sentence: **one host tap ends every delegated pair's
-- run, on numbers the SERVER derived from each runner's own trace, and the runner's own later
-- settle then prices from those numbers instead of the phone's** — with no money minted by the
-- tap and with every pair that could NOT end returned by name.
--
-- ── THE PIN THIS WHOLE FILE EXISTS FOR ─────────────────────────────────────────────────────
-- P7. Everything else can be green while the feature is a complete no-op, and §0-bis of the
-- contract measured exactly how: `0083:744` lets the DEVICE's `actual_km` win whenever
-- `bookings.run_ended_at` is NULL, and `settle-run/handler.ts:77/115` reads the frozen row only
-- when that same stamp exists. A fan-out that writes beautiful numbers into `runs` and forgets
-- the stamp returns success, settles cleanly, keeps every gate green, and the only witness is a
-- difference between two numbers nobody compares. **P7 compares them.** M9 in the battery below
-- plants that hole unfixed and is the measurement that P7 is not decoration.
--
-- ── FIXTURES: THE REAL LIFECYCLE, AND THE THREE PLACES IT IS NOT ───────────────────────────
-- Every pairing is driven through the shipped chain, `t163_pair`'s discipline applied to a
-- MULTI-runner session (163 builds one club per pairing; a fan-out cannot be measured that way):
--   `club_request_district` → `club_claim_host` → `club_create_session` → `session_runner_commit`
--   → `session_checkin` → `session_delegate_dog` → `session_approve_dog` → `session_pay_delegation`
--   → `session_assign_dog` → `session_proposal_respond` → handoff stamps + `picked_up`
--   → `club_start_delegated_runs` → `club_save_run_trace`
-- and the further states use the real RPC too (`club_incident_open`, `session_set_backup`,
-- `club_cancel_session`, `settle_run_tx` through a transcription of the shipping handler).
--
-- ⚠ **THREE WRITES ARE NOT AN RPC CALL. Each is named, with the reason it is the production path
-- rather than a shortcut around one:**
--  ① **the handoff stamps + `status = 'picked_up'`.** There is no SQL RPC for the door handoff;
--     the client calls `transition-booking`, which runs as `service_role`. `_guard_booking_cols`
--     (`0058:143`) blocks `authenticated`/`anon` and lets every server role through, so an UPDATE
--     from this postgres session IS that path — and `enforce_booking_transition` (`0066:40`) still
--     validates `confirmed → picked_up`, so the state machine is enforced, not stepped around.
--     107 and 163 build their custody fixtures the same way.
--  ② **`runs.started_at` is BACK-DATED after `club_start_delegated_runs` wrote it.** `now()` is
--     TRANSACTION-START time in PostgreSQL, so inside one harness block every `now()` is the same
--     instant and **time cannot pass**. Without back-dating, every duration this file measures
--     would be 1 second and the truncation property (P2) would be unmeasurable, because both of
--     one runner's dogs would have started at the same microsecond. This supplies the one INPUT
--     the harness cannot produce — elapsed time — and nothing else; every custody fact, every
--     axis and every km is still produced by the machine that produces it in production.
--     116 sets `ops_flags.payments_live_since = now() - interval '7 days'` for the same reason.
--  ③ **`ops_flags.payments_live_since`** in P12, restored to NULL in the same pin (116's shape).
-- Nothing here ever writes `session_dogs.custody_phase`, `payout_state`, `custodian_type` or
-- `bookings.status` directly. Those are the facts under test, and 0134's §12.1 law applies: a pin
-- that reaches a custody state by writing that state measures its own fixture.
--
-- ── WHY THIS FILE IS IN NINE BLOCKS AND NOT ONE ────────────────────────────────────────────
-- Two reasons, both load-bearing. **(a)** `now()` is constant inside a transaction, so a second
-- tap in the same block could not be distinguished from the first by its timestamp — P4's
-- 「`run_ended_at` is the FIRST tap's time, not the second's」 arm would be vacuously true. Each
-- `do $$ … $$` is its own transaction, so the two taps genuinely happen at different instants.
-- **(b)** 0134's measured lesson: a plpgsql exception handler rolls back to the savepoint at the
-- start of ITS block, so a fixture built inside the same `begin … exception` block as an
-- assertion is undone by the very refusal the pin expects. Fixtures and assertions are separated
-- throughout, and ids travel between blocks through `t176_ctx` rather than through variables.
--
-- ── SIX PAIRINGS THAT END, FOUR THAT DO NOT, AND WHY EACH ONE EXISTS ───────────────────────
--   dA  (runner rA)          → ends, 3.00 km derived
--   dB1 (runner rB)          → ends, 1.80 km   ┐ ONE runner, ONE shared trace, TWO dogs, and
--   dB2 (runner rB)          → ends, 0.60 km   ┘ DIFFERENT km — P2, the truncation property
--   dC  (runner rC)          → ends, 2.40 km
--   dCi (runner rC)          → blocked `incident_open`  (a case on the DOG)
--   dD  (runner rD)          → blocked `not_started`    (handed over, 시작 never tapped)
--   dE  (runner rE)          → blocked `no_trace`       (active, no usable fixes)
--   dF  (runner rF)          → blocked `km_out_of_band` (a trace deriving ≈110 km)
-- Three distinct runners end, and one of them ends TWO dogs. A single-runner fixture cannot tell
-- 「ends every runner's runs」 from 「ends my own」, which is the property Sean actually asked for —
-- M1 in the battery is the mutation that proves the distinction is measured.
--
-- ── MUTATION BATTERY — PREDICTED BEFORE MEASUREMENT, MEASURED BELOW ────────────────────────
-- Each mutation applied ALONE, by appending a mutated `create or replace` as a trailing
-- migration to a COPY of `supabase/` OUTSIDE the worktree — never by editing the live file
-- (CLAUDE.md: a copy-modify-restore is a read-modify-write with a multi-second window, and
-- another agent editing the same file loses its work silently inside it).
--
--   #    mutation                                                            PREDICTED red
--   M1   candidate selector scoped to `b.runner_id = auth.uid()`             [P1,P2,P3,P5,P7]
--        (i.e. `club_start_delegated_runs`'s selector, 0050:176, by mistake)
--   M2   backup host dropped from the gate                                   [P11ⓑ]
--   M3   gate rewritten `not (auth.uid() in (host, backup))`                 [P10ⓐ,P10ⓒ]
--   M5   `run_ended_at`/`ended_at` idempotence re-check dropped              [P4]
--   M6′  the incident pair RAISES instead of classifying (= atomic-or-nothing) [P1,P2,P3,P5]
--   M7   `blocked` merged into `already`                                     [P3,P5]
--   M8   🔴 R-2 half A: stamp `bookings.run_ended_at`, write NO `runs` row   [P1,P7]
--   M9   🔴 R-2 half B: write `runs`, do NOT stamp `bookings.run_ended_at`   [P1,P7]
--   M10  derivation ignores `started_at` (no per-dog truncation)             [P1,P2]
--   M11  derivation returns 0.00 instead of NULL on <2 in-window points      [P1,P3]
--   M12  `revoke … from public, anon` only (service_role left with EXECUTE)  [P13]
--   M15  🔵 the tap writes `custody_phase = 'return_pending'` (void §1-ⓑ)     [NOTHING]
--        — run BECAUSE the prediction is empty: it is §0-bis R-1 reproduced as a measurement.
--        The write is silently normalised away by `club_v1_axes_sync`, no exception, no red
--        gate, nothing dirty. A battery that never runs a mutation it expects to survive has
--        not tested the trap that eats this feature's original design.
--   M16  the tap does not write `runs.ended_at` (left to settle, as today)   [P1,P12ⓐ]
--
-- 🔴 **MEASURED 2026-08-27 — RESULTS ARE RECORDED IN THE 「MEASURED」 BLOCK AT THE END OF THIS
-- HEADER, beside the predictions above, so a later reader sees where the prediction was wrong.**
--
-- ── 🔴 MEASURED 2026-08-27. Thirteen runs plus a baseline. Nothing was edited in place: every
--    mutation was appended as a trailing `0145_mut.sql` to a COPY of `supabase/` outside the
--    worktree, and `gen.py` ASSERTS the mutated text differs from the original before writing —
--    a plant that silently fails to land is a run that measures the clean build and reports it
--    as a red set. ─────────────────────────────────────────────────────────────────────────
--
--   M0  the copy, unmutated — **1017 / 0**, identical to the worktree. A control that could
--       have failed, and the only thing that makes every number below comparable.
--
--   #    PREDICTED red set          MEASURED
--   M1   [P1,P2,P3,P5,P7]           1011/6 = [P1,P3,P4,P5,P7,P11]. Superset. P2 does NOT redden
--        — with the selector scoped to the caller the host owns no dog, so `ended` is EMPTY and
--        P2's own precondition (「the two runs hold the same trace」) still holds; P1's `ended≠4`
--        fires first. P11 joins because the backup host on s2 then ends only their OWN dog.
--   M2   [P11ⓑ]                     1015/2 = [P11,P12]. P12 rides on P11's tap having frozen s2b,
--        and its precondition arm says so out loud (「전제 붕괴: 정지 스탬프가 없다」) instead of
--        scoring a false green on its own first arm.
--   M3   [P10ⓐ,P10ⓒ]                1016/1 = **[P10]. EXACT.** Message: 「멤버=<no raise>
--        낯선이=<no raise> 존재 오라클: 없는세션≠남의세션 (not_host vs <no raise>)」 — with
--        `backup_host_profile_id` NULL, a committed checked-in member AND a total stranger both
--        walk straight through. The fail-open, reproduced.
--   M5   [P4]                       1015/2 = [P4,P7]. The finding is P7's arm: `bookings.
--        run_ended_at` survives (its UPDATE carries its own `and run_ended_at is null`) but
--        **`runs.ended_at` is rewritten by the second tap** — 「정지 시각이 정산 시각으로
--        덮였다」. The idempotence re-check is what protects the stop time, and the stop time is
--        R-3's charging-cutover input.
--   M6′  [P1,P2,P3,P5]              1005/7 = [BLOCK1,P4,P7,P9,P10,P11,P12]. **Far worse than
--        predicted, and the shape is the lesson**: the raise escaped the loop, escaped the
--        function, and hit BLOCK 1's outer handler, which rolled back the whole fixture set —
--        so P1/P2/P3/P5 never reported at all and every downstream block died on missing
--        fixtures. That is ARM A at full volume (one dog's open case takes the session down)
--        AND 0134's savepoint lesson visible in the same run.
--        ⚠ **M6′'s FIRST attempt was mis-specified and is recorded rather than deleted.** It made
--        the incident branch raise but left the `when others` arm in place, so the raise was
--        caught and reclassified as `error`: 1016/1 = [P3], reddening on a reason STRING while
--        proving nothing about atomicity. A mutation that reddens by accident is not a
--        measurement (0142's law), and the second, correct form is the one above.
--   M7   [P3,P5]                    1013/4 = [P1,P3,P4,P5]. P3: 「blocked=0 dCi=∅ dD=∅ dE=∅ dF=∅
--        incidentId=∅ dogName=∅」 — every remainder reason and the incident id vanish into the
--        silent list. This is exactly 「silent catch → happy UI」 and four pins see it.
--   M8   [P1,P7]                    1012/5 = [P1,P4,P7,P11,P12]. 🔴 **R-2 half A, the poisoned
--        NULL.** P7 dies at `unknown_end_reason`: the handler reads the frozen row, finds a NULL
--        `end_reason`, and `compute_runner_payout` fails closed BEFORE `settle_run_tx` is
--        reached. The runner is never paid — the deadlock §0-bis names, arriving one step
--        earlier than `frozen_measurement_mismatch` and just as terminal.
--   M9   [P1,P7]                    1013/4 = [P1,P4,P5,P7]. 🔴 **R-2 half B — THE SILENT NO-OP,
--        AND THE REASON THIS FILE EXISTS.** P7's verbatim message:
--            distance_pay=29970 서버=9000 · 🔴 원장이 디바이스 km으로 값이 매겨졌다 ·
--            정산이 actual_km을 덮었다: 9.99 · 디바이스의 end_reason이 이겼다 ·
--            직접 호출이 거부되지 않았다: <no raise>
--        The server derived 3.00 km, the phone claimed 9.99, and **the ledger paid 29,970 on the
--        phone's number while the settle overwrote the server's row with it** — `0083:744`'s
--        `excluded` arm winning, exactly as the contract predicted, with the SQL belt silent
--        because it only arms when the stamp exists. Without P7 this mutation is a feature that
--        looks shipped and does nothing.
--   M10  [P1,P2]                    1015/2 = **[P1,P2]. EXACT.** P2: 「dB2 km=1.80」 — the dog
--        handed over twenty minutes late is billed the whole pack's distance.
--   M11  [P1,P3]                    1013/4 = [P1,P3,P4,P5]. P3: 「dE=active/stamp✓/0.00/completed/
--        1800/…」 — the dog with no usable GPS gets a FROZEN 0.00 km 'completed' run instead of
--        being named to the host. A fabricated measurement, frozen, and now unappealable.
--   M12  [P13]                      1016/1 = **[P13]. EXACT.** 0144's own VERIFY does not fire
--        (it ran at 0144's apply, before the grant), which is precisely why the standing pin is
--        not redundant with it.
--   M15  [NOTHING]                  1016/1 = **[P13], on the SOURCE-TEXT guard alone —
--        「금지 표면: custody_phase」 — and 13 of 14 pins GREEN.** 🔴 This is the measurement, not
--        a miss. The function wrote `custody_phase = 'return_pending'` on every ended pairing and
--        **not one behavioural pin could see it**, because `club_v1_axes_sync` recomputed it away
--        inside the same statement: no exception, no red gate, nothing dirty. §0-bis R-1
--        reproduced. The prediction was 「NOTHING」 and the refinement is that a text check is the
--        ONLY instrument that reaches this class — which is also why 0144's body may not mention
--        the surfaces it does not touch.
--   M16  [P1,P12ⓐ]                  1013/4 = [P1,P4,P7,P12]. P12 fails on its PRECONDITION arm
--        (「전제 붕괴: 정지 스탬프가 없다」) and then on ⓑ, because with `runs.ended_at` NULL the
--        mint reads `coalesce(r.ended_at, now())` and BOTH cutover directions collapse to the
--        same answer. A pin that asserts its own precondition is what stops that reading as a
--        green ⓐ.
--
--   **Zero dangerous greens: every mutation reddened at least one pin, and M15's single red is a
--   text guard by construction rather than by accident.** Three exact hits (M3, M10, M12); the
--   rest are supersets, all traceable to two fixture dependencies stated here rather than
--   discovered later — P12 needs P11's tap to have frozen s2b, and P4/P5/P7 all read state P1
--   establishes.
set client_min_messages = warning;

-- ── context carried between transactions ───────────────────────────────────────────────────
create table if not exists t176_ctx (k text primary key, v text);
create or replace procedure t176_put(k text, v text) language sql as $$
  insert into t176_ctx values (k, v) on conflict (k) do update set v = excluded.v $$;
create or replace function t176_get(p_k text) returns text
language sql stable as $$ select v from t176_ctx where k = p_k $$;
create or replace function t176_id(p_k text) returns uuid
language sql stable as $$ select v::uuid from t176_ctx where k = p_k $$;

-- ── a synthetic trace in the SHIPPED shape: {lat,lng,t} with t in whole epoch SECONDS ───────
-- `app/app/club/run/[sid].tsx:196-211` builds exactly this — three keys, `t = Math.floor(p.t/1000)`,
-- strictly increasing. The first point is `floor(epoch(started_at)) + 1` so that every generated
-- point is strictly INSIDE the derivation window regardless of the fractional part of the server
-- clock: `floor(epoch)` alone would sometimes fall a fraction of a second BEFORE `started_at` and
-- the first segment would appear and disappear between runs. A flaky pin is worse than none.
-- Movement is pure latitude, so the equirectangular distance of each step is exactly p_metres.
create or replace function t176_trace(p_from timestamptz, p_n int, p_step int, p_metres numeric)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'lat', 37.5096 + (i * p_metres / 111000.0),
           'lng', 126.9954,
           't',   floor(extract(epoch from p_from))::bigint + 1 + (i * p_step)
         ) order by i), '[]'::jsonb)
  from generate_series(0, p_n - 1) i
$$;

-- ── one pairing, driven through the shipped chain, up to (not including) the run start ──────
-- Returns the session_dog id; the booking id is read off it. Every actor switch is explicit so
-- the party gates are the ones production applies.
create or replace function t176_pair(p_sess uuid, p_tag text, p_runner uuid, p_host uuid)
returns uuid language plpgsql as $$
declare v_owner uuid; v_dog uuid; v_sd uuid;
begin
  v_owner := t_user('t176o_' || p_tag, 'owner');
  v_dog   := t_dog(v_owner, p_tag);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_sd := session_delegate_dog(p_sess, v_dog, t_consent());
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  perform session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  perform session_pay_delegation(v_sd, 't176-idem-' || p_tag, true);
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

create or replace function t176_bk(p_sd uuid) returns uuid
language sql stable as $$ select booking_id from session_dogs where id = p_sd $$;

-- ── reading the remainder ──────────────────────────────────────────────────────────────────
create or replace function t176_reason(p_res jsonb, p_list text, p_sd uuid) returns text
language sql immutable as $$
  select e->>'reason' from jsonb_array_elements(p_res->p_list) e
   where (e->>'sdId')::uuid = p_sd
$$;
create or replace function t176_inc(p_res jsonb, p_sd uuid) returns uuid
language sql immutable as $$
  select nullif(e->>'incidentId','')::uuid from jsonb_array_elements(p_res->'blocked') e
   where (e->>'sdId')::uuid = p_sd
$$;
create or replace function t176_km(p_res jsonb, p_sd uuid) returns numeric
language sql immutable as $$
  select (e->>'km')::numeric from jsonb_array_elements(p_res->'ended') e
   where (e->>'sdId')::uuid = p_sd
$$;
create or replace function t176_name(p_res jsonb, p_list text, p_sd uuid) returns text
language sql immutable as $$
  select e->>'dogName' from jsonb_array_elements(p_res->p_list) e
   where (e->>'sdId')::uuid = p_sd
$$;
create or replace function t176_n(p_res jsonb, p_list text) returns int
language sql immutable as $$ select jsonb_array_length(p_res->p_list) $$;

-- one line of state per pairing, so a precondition assertion is one line and not six
create or replace function t176_state(p_sd uuid) returns text
language sql stable as $$
  select coalesce((
    select b.status::text
        || '/' || case when b.run_ended_at is null then 'stamp∅' else 'stamp✓' end
        || '/' || coalesce(r.actual_km::text, 'km∅')
        || '/' || coalesce(r.end_reason::text, 'reason∅')
        || '/' || coalesce(r.duration_sec::text, 'dur∅')
        || '/' || sd.custody_phase || '/' || sd.payout_state
      from session_dogs sd
      join bookings b on b.id = sd.booking_id
      left join runs r on r.booking_id = sd.booking_id
     where sd.id = p_sd), '<no row>')
$$;

-- ── settle-run/handler.ts, transcribed ─────────────────────────────────────────────────────
-- 🔴 THIS IS THE HEART OF P7 AND IT IS A TRANSCRIPTION, NOT AN INVENTION. The whole R-2 defect
-- lives in the handler's TWO-LINE decision about which numbers to price from, so a pin that hand-
-- picks a km would be measuring itself. Line-for-line correspondence:
--   handler.ts:57  the booking row       ·  handler.ts:77   frozen iff `bk.run_ended_at`
--   handler.ts:251-267 readFrozenRun     ·  handler.ts:115-118 km/reason/duration/note choice
--   handler.ts:107-108 commission        ·  handler.ts:150-155 compute_runner_payout
--   handler.ts:173-184 settle_run_tx with the six computed money values
-- The device's numbers are passed in and are DELIBERATELY different from the frozen ones: if the
-- frozen path is not taken, they reach `compute_runner_payout` and the ledger row says so.
create or replace function t176_settle_like_handler(
  p_booking uuid, p_device_km numeric, p_device_reason text, p_device_dur int
) returns jsonb language plpgsql as $$
declare
  v_ended timestamptz; v_runner uuid; v_comm numeric;
  v_fz record; v_po record;
  v_km numeric; v_reason text; v_dur int; v_note text;
begin
  select bk.run_ended_at, bk.runner_id into v_ended, v_runner
    from bookings bk where bk.id = p_booking;                          -- handler.ts:57
  if v_ended is not null then                                          -- handler.ts:77
    select rn.actual_km, rn.end_reason::text as end_reason, rn.duration_sec, rn.condition_note
      into v_fz from runs rn where rn.booking_id = p_booking;          -- handler.ts:251-267
    v_km := v_fz.actual_km; v_reason := v_fz.end_reason;               -- handler.ts:115-116
    v_dur := v_fz.duration_sec; v_note := v_fz.condition_note;         -- handler.ts:117-118
  else
    v_km := p_device_km; v_reason := p_device_reason;
    v_dur := p_device_dur; v_note := null;
  end if;
  select coalesce(rn.commission_rate, 0.33) into v_comm
    from runners rn where rn.profile_id = v_runner;                    -- handler.ts:107-108
  select * into v_po
    from compute_runner_payout(p_booking, v_reason, v_km, coalesce(v_comm, 0.33));  -- :150-155
  return settle_run_tx(p_booking, v_km, v_dur, v_reason, v_note,
                       v_po.base, v_po.distance, v_po.addon, v_po.guarantee, v_po.fee);  -- :173
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 1 — fixtures, the first tap, and everything that tap establishes
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_host uuid; v_bk_host uuid; v_stranger uuid;
  rA uuid; rB uuid; rC uuid; rD uuid; rE uuid; rF uuid;
  v_club uuid; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_route uuid;
  dA uuid; dB1 uuid; dB2 uuid; dC uuid; dCi uuid; dD uuid; dE uuid; dF uuid;
  s2a uuid; s2b uuid;
  v_inc uuid; v_res jsonb; v_at timestamptz; v_bad text; v_t0 timestamptz;
  n_led int; n_pay int; n_fee int; n_mil int;
  m_led int; m_pay int; m_fee int; m_mil int;
begin
  update club_flags set enabled = true where name = 'club_delegation_v2';

  -- ── people ───────────────────────────────────────────────────────────────────────────────
  v_host     := t_user('t176_host',   'runner');
  v_bk_host  := t_user('t176_backup', 'runner');
  v_stranger := t_user('t176_stranger', 'owner');
  rA := t_user('t176_rA', 'runner'); rB := t_user('t176_rB', 'runner');
  rC := t_user('t176_rC', 'runner'); rD := t_user('t176_rD', 'runner');
  rE := t_user('t176_rE', 'runner'); rF := t_user('t176_rF', 'runner');
  -- veteran = cap 2 (`_club_runner_cap`, 0037:39). rB and rC each hold TWO dogs, which is the
  -- per-pairing grain this fan-out has to respect.
  update runners set tier = 'veteran'
   where profile_id in (v_host, v_bk_host, rA, rB, rC, rD, rE, rF);

  v_route := t_route('t176 반포 코스');

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_club := club_request_district('t176동');
  perform club_claim_host(v_club);
  v_s1 := club_create_session(v_club, now() + interval '90 minutes', 't176 집결지', v_route, 20, 'mixed');
  v_s2 := club_create_session(v_club, now() + interval '90 minutes', 't176 집결지 2', v_route, 20, 'mixed');
  v_s3 := club_create_session(v_club, now() + interval '90 minutes', 't176 집결지 3', v_route, 20, 'mixed');
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform session_runner_commit(v_s3); perform session_checkin(v_s3);

  -- every handling runner commits and checks in — `session_assign_dog` refuses a runner who is
  -- not on the ground (`runner_not_checked_in`, 0038:43)
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  perform set_config('request.jwt.claim.sub', rB::text, false);
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  perform set_config('request.jwt.claim.sub', rC::text, false);
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  perform set_config('request.jwt.claim.sub', rD::text, false);
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  perform set_config('request.jwt.claim.sub', rE::text, false);
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  perform set_config('request.jwt.claim.sub', rF::text, false);
  perform session_runner_commit(v_s1); perform session_checkin(v_s1);
  -- s2's handling runner, and the BACKUP HOST — who must be a committed runner of that session
  -- (`backup_not_committed`, 0047:311)
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform set_config('request.jwt.claim.sub', v_bk_host::text, false);
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  perform session_set_backup(v_s2, v_bk_host);
  -- ⚠ s1 is left with `backup_host_profile_id` NULL ON PURPOSE — it is the fixture P10ⓔ needs.
  -- With the gate written as `not (auth.uid() in (host, backup))` the NULL folds the whole
  -- predicate to NULL and every stranger walks through (0072:117-121, 0116:410). That fail-open
  -- is only reachable on a session whose backup is NULL, so one session must have none.

  -- ── the eight pairings of s1, plus s2's two ─────────────────────────────────────────────
  dA  := t176_pair(v_s1, 'dA',  rA, v_host);
  dB1 := t176_pair(v_s1, 'dB1', rB, v_host);
  dB2 := t176_pair(v_s1, 'dB2', rB, v_host);
  dC  := t176_pair(v_s1, 'dC',  rC, v_host);
  dCi := t176_pair(v_s1, 'dCi', rC, v_host);
  dD  := t176_pair(v_s1, 'dD',  rD, v_host);
  dE  := t176_pair(v_s1, 'dE',  rE, v_host);
  dF  := t176_pair(v_s1, 'dF',  rF, v_host);
  s2a := t176_pair(v_s2, 's2a', rA, v_host);
  s2b := t176_pair(v_s2, 's2b', v_bk_host, v_host);

  -- ── the run starts — each runner's OWN fan-out over their OWN dogs (0050:176) ────────────
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform club_start_delegated_runs(v_s1);
  perform set_config('request.jwt.claim.sub', rB::text, false);
  perform club_start_delegated_runs(v_s1);
  perform set_config('request.jwt.claim.sub', rC::text, false);
  perform club_start_delegated_runs(v_s1);
  perform set_config('request.jwt.claim.sub', rE::text, false);
  perform club_start_delegated_runs(v_s1);
  perform set_config('request.jwt.claim.sub', rF::text, false);
  perform club_start_delegated_runs(v_s1);
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform club_start_delegated_runs(v_s2);
  perform set_config('request.jwt.claim.sub', v_bk_host::text, false);
  perform club_start_delegated_runs(v_s2);
  -- rD never taps 시작. dD stays `picked_up` with no `runs` row — the reachable shape of
  -- 「the run never started」, and the one the host must be told about by name.

  -- ── ② back-date the starts (header note ②) ───────────────────────────────────────────────
  v_t0 := now() - interval '30 minutes';
  update runs set started_at = v_t0
   where booking_id in (t176_bk(dA), t176_bk(dB1), t176_bk(dC), t176_bk(dCi),
                        t176_bk(dE), t176_bk(dF), t176_bk(s2a), t176_bk(s2b));
  -- dB2 was handed over LATE — twenty minutes into the pack's walk. Its runner's trace is the
  -- same trace; only the window differs, and that is the whole of P2.
  update runs set started_at = now() - interval '10 minutes' where booking_id = t176_bk(dB2);
  -- ⚠ [0156] dF's run is back-dated FIVE HOURS, alone among the eight. Its fixture is the
  -- over-band case: 999 × 111 m ≈ 110.89 km, which at the ingest gate's 8 m/s ceiling cannot
  -- physically happen in 30 minutes. It previously "fit" only because the generated timestamps
  -- ran ~3.7 HOURS INTO THE FUTURE, which 0156 now refuses at ingest (`trace_future_fix`) and
  -- excludes at derivation. Re-dating the run is the honest repair: 1000 points × 15 s spans
  -- ≈4.16 h, so at 7.4 m/s every fix is in the past, inside the window, and inside the 300 s
  -- coverage gate — and the derived distance is unchanged, which is what P3's `km_out_of_band`
  -- actually pins. dF is BLOCKED and therefore freezes no km and no duration, so no other pin in
  -- this suite reads its timing (`v_dur` is `v_at - v_start`, and dF never reaches the freeze).
  update runs set started_at = now() - interval '5 hours' where booking_id = t176_bk(dF);

  -- ── the traces, uploaded through the shipped RPC by the runner who owns them ─────────────
  -- ⚠ `club_save_run_trace` fans ONE batch out over EVERY active run of that runner in that
  -- session (0053:145-146) — which is exactly why dB1 and dB2 end up holding byte-identical
  -- traces and why the derivation has to truncate.
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform club_save_run_trace(v_s1, t176_trace(v_t0, 31, 60, 100));   -- 30 × 100 m = 3.00 km
  perform set_config('request.jwt.claim.sub', rB::text, false);
  perform club_save_run_trace(v_s1, t176_trace(v_t0, 31, 60, 60));    -- 30 ×  60 m = 1.80 km
  perform set_config('request.jwt.claim.sub', rC::text, false);
  perform club_save_run_trace(v_s1, t176_trace(v_t0, 31, 60, 80));    -- 30 ×  80 m = 2.40 km
  perform set_config('request.jwt.claim.sub', rF::text, false);
  -- [0156] built from dF's own back-dated start, not the shared v_t0 — see the note above.
  perform club_save_run_trace(v_s1, t176_trace(now() - interval '5 hours', 1000, 15, 111)); -- 999 × 111 m ≈ 110.89 km
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform club_save_run_trace(v_s2, t176_trace(v_t0, 31, 60, 100));
  perform set_config('request.jwt.claim.sub', v_bk_host::text, false);
  perform club_save_run_trace(v_s2, t176_trace(v_t0, 31, 60, 100));
  -- rE uploads nothing. `runs.trace` stays '[]' — GPS refused, app never ran, or a clock skew
  -- that stripped the window. There is no honest number for that dog and the tap must say so.

  -- ── the case on dCi's DOG — through the real RPC, opened by the runner who holds it ──────
  perform set_config('request.jwt.claim.sub', rC::text, false);
  v_inc := club_incident_open(v_s1, 'S2', 't176 케이스',
                              (select dog_id from session_dogs where id = dCi),
                              null, null);

  -- ── carry every id forward ───────────────────────────────────────────────────────────────
  call t176_put('host', v_host::text);     call t176_put('backup', v_bk_host::text);
  call t176_put('stranger', v_stranger::text);
  call t176_put('rA', rA::text);           call t176_put('rB', rB::text);
  call t176_put('rC', rC::text);
  call t176_put('s1', v_s1::text);         call t176_put('s2', v_s2::text);
  call t176_put('s3', v_s3::text);
  call t176_put('dA', dA::text);           call t176_put('dB1', dB1::text);
  call t176_put('dB2', dB2::text);         call t176_put('dC', dC::text);
  call t176_put('dCi', dCi::text);         call t176_put('dD', dD::text);
  call t176_put('dE', dE::text);           call t176_put('dF', dF::text);
  call t176_put('s2a', s2a::text);         call t176_put('s2b', s2b::text);
  call t176_put('inc', v_inc::text);

  -- ═══ [P0] FIXTURE PRECONDITION — asserted ONCE and loudly ══════════════════════════════
  -- Every pin below is meaningless if this is wrong, and a suite that discovers it pin by pin
  -- reports eleven confusing reds instead of one. A gate suite fails in a characteristic way:
  -- 「it raised X」 scores green when the fixture was never in the state the pin claims.
  v_bad := '';
  if t176_state(dA)  <> 'active/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
    then v_bad := v_bad || ' dA=' || t176_state(dA); end if;
  if t176_state(dB2) <> 'active/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
    then v_bad := v_bad || ' dB2=' || t176_state(dB2); end if;
  if t176_state(dD)  <> 'picked_up/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
    then v_bad := v_bad || ' dD=' || t176_state(dD); end if;
  if exists (select 1 from runs where booking_id = t176_bk(dD))
    then v_bad := v_bad || ' dD에 runs 행이 있다'; end if;
  -- the outbound custody EVENT that `picked_up` mints (0045:44) — so `_club_compute_axes` takes
  -- its event branch (0048:786), the path production takes, and not the legacy fallback
  if (select count(*) from dog_custody_events e
       where e.session_dog_id in (dA,dB1,dB2,dC,dCi,dD,dE,dF)
         and e.event_type = 'outbound' and e.to_type = 'runner') <> 8
    then v_bad := v_bad || ' outbound 이벤트 8개가 아니다'; end if;
  -- the traces landed, and dB1/dB2 hold the SAME one
  if (select jsonb_array_length(trace) from runs where booking_id = t176_bk(dA)) <> 31
    then v_bad := v_bad || ' dA trace≠31'; end if;
  if (select trace from runs where booking_id = t176_bk(dB1))
     is distinct from (select trace from runs where booking_id = t176_bk(dB2))
    then v_bad := v_bad || ' dB1/dB2 트레이스가 다르다 (절단 성질을 잴 수 없다)'; end if;
  if (select jsonb_array_length(trace) from runs where booking_id = t176_bk(dE)) <> 0
    then v_bad := v_bad || ' dE에 트레이스가 있다'; end if;
  if (select jsonb_array_length(trace) from runs where booking_id = t176_bk(dF)) <> 1000
    then v_bad := v_bad || ' dF trace≠1000'; end if;
  -- and the two started_at values that P2 turns on really do differ
  if (select started_at from runs where booking_id = t176_bk(dB2))
     <= (select started_at from runs where booking_id = t176_bk(dB1))
    then v_bad := v_bad || ' dB2 started_at이 dB1보다 늦지 않다'; end if;
  if (select backup_host_profile_id from club_sessions where id = v_s1) is not null
    then v_bad := v_bad || ' s1에 백업 호스트가 있다 (P10ⓔ의 NULL 케이스가 사라진다)'; end if;
  if (select state from club_incidents where id = v_inc) = 'resolved'
    then v_bad := v_bad || ' 케이스가 이미 해소됐다'; end if;
  if v_bad = ''
    then call _pass('pke','P0 fixture precondition — ten pairings across one session and its sibling, each driven through the real RPC chain to the exact state its pin claims: six active with a runs row and no stamp, one still picked_up with NO runs row at all (rD never tapped 시작 — the reachable shape of 「never started」), the outbound dog_custody_events row on all eight so _club_compute_axes takes its EVENT branch, dB1 and dB2 holding a byte-identical shared trace with different started_at (0053:145-146 — the whole basis of P2), dE with an empty trace, dF with 1000 points, an open S2 case on dCi''s dog, and s1 deliberately carrying NULL backup_host_profile_id so the `in (…)` fail-open has a session to be reachable on');
    else call _fail('pke','P0 fixture precondition', v_bad); end if;

  -- ── money surfaces, counted immediately BEFORE the tap ───────────────────────────────────
  select count(*) into n_led from ledger_items;
  select count(*) into n_pay from payments;
  select count(*) into n_fee from club_fee_items;
  select count(*) into n_mil from miles_ledger;

  -- ═══ THE TAP ═════════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_res := club_end_pack_runs(v_s1);
  perform set_config('request.jwt.claim.sub', '', false);
  v_at := (v_res->>'at')::timestamptz;
  call t176_put('res1', v_res::text);
  call t176_put('at1', v_at::text);

  select count(*) into m_led from ledger_items;
  select count(*) into m_pay from payments;
  select count(*) into m_fee from club_fee_items;
  select count(*) into m_mil from miles_ledger;

  -- ═══ [P1] ONE TAP ENDS EVERY RUNNER'S RUNS, ON SERVER-DERIVED NUMBERS ═══════════════════
  begin
    v_bad := '';
    if t176_n(v_res,'ended') <> 4 then v_bad := v_bad || ' ended=' || t176_n(v_res,'ended'); end if;
    if t176_n(v_res,'already') <> 0 then v_bad := v_bad || ' already=' || t176_n(v_res,'already'); end if;
    -- three DISTINCT runners ended, and the host is none of them. A single-runner fixture cannot
    -- tell 「ends every runner's runs」 from 「ends my own」.
    if (select count(distinct e->>'runnerId') from jsonb_array_elements(v_res->'ended') e) <> 3
      then v_bad := v_bad || ' 종료된 러너 수≠3'; end if;
    if exists (select 1 from jsonb_array_elements(v_res->'ended') e
                where (e->>'runnerId')::uuid = v_host)
      then v_bad := v_bad || ' 호스트 자신의 페어가 종료 목록에 있다'; end if;
    -- the freeze, COMPLETE, on every ended pair: stamp + ended_at + km + duration + reason
    if t176_state(dA)  <> 'active/stamp✓/3.00/completed/1800/with_custodian/none'
      then v_bad := v_bad || ' dA=' || t176_state(dA); end if;
    if t176_state(dB1) <> 'active/stamp✓/1.80/completed/1800/with_custodian/none'
      then v_bad := v_bad || ' dB1=' || t176_state(dB1); end if;
    if t176_state(dB2) <> 'active/stamp✓/0.60/completed/600/with_custodian/none'
      then v_bad := v_bad || ' dB2=' || t176_state(dB2); end if;
    if t176_state(dC)  <> 'active/stamp✓/2.40/completed/1800/with_custodian/none'
      then v_bad := v_bad || ' dC=' || t176_state(dC); end if;
    -- one clock for the whole tap, and it is the value the caller was told
    if (select count(*) from bookings b
         where b.id in (t176_bk(dA), t176_bk(dB1), t176_bk(dB2), t176_bk(dC))
           and b.run_ended_at = v_at) <> 4
      then v_bad := v_bad || ' run_ended_at이 반환된 at과 다르다'; end if;
    if (select count(*) from runs r
         where r.booking_id in (t176_bk(dA), t176_bk(dB1), t176_bk(dB2), t176_bk(dC))
           and r.ended_at = v_at) <> 4
      then v_bad := v_bad || ' runs.ended_at이 at과 다르다'; end if;
    -- every derived km is > 0 and is the one the caller was told
    if coalesce(t176_km(v_res, dA), 0) <> 3.00 or coalesce(t176_km(v_res, dB2), 0) <> 0.60
      then v_bad := v_bad || ' 반환 km이 저장 km과 다르다'; end if;
    -- and the booking's STATUS did not move: ARM 1 would have unpaid every runner (0083:720-724)
    if (select count(*) from bookings b
         where b.id in (t176_bk(dA), t176_bk(dB1), t176_bk(dB2), t176_bk(dC))
           and b.status = 'active') <> 4
      then v_bad := v_bad || ' 부킹 상태가 움직였다'; end if;
    if v_bad = ''
      then call _pass('pke','P1 한 번의 탭이 모든 러너의 런을 끝낸다 — 세 명의 서로 다른 러너(호스트 본인은 아무 개도 맡지 않았다)의 네 페어가 종료되고, 각 개의 km은 그 러너 본인이 업로드한 트레이스에서 서버가 도출했으며(3.00·1.80·0.60·2.40), 시간은 전부 호스트의 탭까지 잰다. 동결은 완전하다: bookings.run_ended_at · runs.ended_at · actual_km · duration_sec · end_reason 다섯이 한 번에, 하나도 NULL이 아닌 채로. 그리고 bookings.status는 움직이지 않는다 — 움직였다면 러너의 자기 정산이 not_active로 거부되어(0083:720-724) 아무도 돈을 못 받는다');
      else call _fail('pke','P1 happy fan-out', v_bad); end if;
  exception when others then call _fail('pke','P1 happy fan-out', sqlerrm);
  end;

  -- ═══ [P2] ONE RUNNER · ONE TRACE · TWO DOGS · TWO DIFFERENT NUMBERS ═════════════════════
  begin
    v_bad := '';
    if (select trace from runs where booking_id = t176_bk(dB1))
       is distinct from (select trace from runs where booking_id = t176_bk(dB2))
      then v_bad := v_bad || ' 전제 붕괴: 두 런의 트레이스가 같지 않다'; end if;
    if (select actual_km from runs where booking_id = t176_bk(dB1)) <> 1.80
      then v_bad := v_bad || ' dB1 km=' || (select actual_km from runs where booking_id = t176_bk(dB1)); end if;
    if (select actual_km from runs where booking_id = t176_bk(dB2)) <> 0.60
      then v_bad := v_bad || ' dB2 km=' || (select actual_km from runs where booking_id = t176_bk(dB2)); end if;
    -- and the durations differ for the same reason
    if (select duration_sec from runs where booking_id = t176_bk(dB1)) <> 1800
       or (select duration_sec from runs where booking_id = t176_bk(dB2)) <> 600
      then v_bad := v_bad || ' 지속시간이 각자의 started_at 기준이 아니다'; end if;
    if v_bad = ''
      then call _pass('pke','P2 절단 — 한 러너, 한 트레이스, 두 마리, 서로 다른 숫자. club_save_run_trace는 배치 하나를 그 러너의 모든 active 런에 팬아웃하므로(0053:145-146) dB1과 dB2의 runs.trace는 바이트 단위로 같다. 그런데 동결된 km은 1.80과 0.60이고 시간은 1800과 600이다 — 각자의 runs.started_at으로 잘랐기 때문. 절단이 없으면 늦게 인계된 아이가 팩의 앞부분 거리를 통째로 청구받는다([sid].tsx:228이 클라에서 같은 결함을 고친 기록)');
      else call _fail('pke','P2 per-dog truncation', v_bad); end if;
  exception when others then call _fail('pke','P2 per-dog truncation', sqlerrm);
  end;

  -- ═══ [P3] THE REMAINDER IS NAMED, AND A BLOCKED PAIR IS COMPLETELY UNSTAMPED ════════════
  begin
    v_bad := '';
    if t176_n(v_res,'blocked') <> 4 then v_bad := v_bad || ' blocked=' || t176_n(v_res,'blocked'); end if;
    if t176_reason(v_res,'blocked',dCi) is distinct from 'incident_open'
      then v_bad := v_bad || ' dCi=' || coalesce(t176_reason(v_res,'blocked',dCi),'∅'); end if;
    if t176_reason(v_res,'blocked',dD)  is distinct from 'not_started'
      then v_bad := v_bad || ' dD=' || coalesce(t176_reason(v_res,'blocked',dD),'∅'); end if;
    if t176_reason(v_res,'blocked',dE)  is distinct from 'no_trace'
      then v_bad := v_bad || ' dE=' || coalesce(t176_reason(v_res,'blocked',dE),'∅'); end if;
    if t176_reason(v_res,'blocked',dF)  is distinct from 'km_out_of_band'
      then v_bad := v_bad || ' dF=' || coalesce(t176_reason(v_res,'blocked',dF),'∅'); end if;
    -- the incident id is asserted as a VALUE, not as a present key: a body returning constant
    -- NULLs keeps every key and passes a key-set check (0065 W6's recorded near-miss)
    if t176_inc(v_res, dCi) is distinct from v_inc
      then v_bad := v_bad || ' incidentId=' || coalesce(t176_inc(v_res,dCi)::text,'∅'); end if;
    if t176_inc(v_res, dE) is not null
      then v_bad := v_bad || ' 인시던트가 아닌 행에 incidentId가 있다'; end if;
    -- named: the host can point at the dog. A remainder the host cannot name is a bare count.
    if t176_name(v_res,'blocked',dCi) is distinct from 'dCi'
      then v_bad := v_bad || ' dogName=' || coalesce(t176_name(v_res,'blocked',dCi),'∅'); end if;
    -- 🔴 and the blocked pairs are UNSTAMPED — the complete-or-absent law. A half freeze is
    -- either a silent no-op (0083:744, the device still wins) or a permanent
    -- frozen_measurement_mismatch (0083:709-717, the runner is never paid).
    if t176_state(dCi) <> 'active/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
      then v_bad := v_bad || ' dCi=' || t176_state(dCi); end if;
    if t176_state(dE)  <> 'active/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
      then v_bad := v_bad || ' dE=' || t176_state(dE); end if;
    if t176_state(dF)  <> 'active/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
      then v_bad := v_bad || ' dF=' || t176_state(dF); end if;
    if t176_state(dD)  <> 'picked_up/stamp∅/km∅/reason∅/dur∅/with_custodian/none'
      then v_bad := v_bad || ' dD=' || t176_state(dD); end if;
    -- blocked is a REPORT, not a refusal: the call succeeded and the other four ended
    if t176_n(v_res,'ended') <> 4 then v_bad := v_bad || ' 차단이 호출을 실패시켰다'; end if;
    if v_bad = ''
      then call _pass('pke','P3 남은 페어는 이름으로 돌아온다 — 네 가지 이유가 각각 구별되어(incident_open·not_started·no_trace·km_out_of_band) sdId·dogName과 함께 오고, 케이스 건에는 실제 incidentId가 값으로 실린다(키 존재가 아니라 값 — 0065 W6). 그리고 차단된 페어는 완전히 무각인이다: 스탬프도, km도, 사유도, 시간도 없다. 반쪽 동결은 0083:744로 무의미해지거나(디바이스 승) 0083:709-717로 영구 미정산이 된다 — 그래서 도출이 실패하면 아무것도 쓰지 않는다');
      else call _fail('pke','P3 named remainder', v_bad); end if;
  exception when others then call _fail('pke','P3 named remainder', sqlerrm);
  end;

  -- ═══ [P5] BEST-EFFORT, NOT ATOMIC — the blast radius is proportional to the failure ═════
  begin
    v_bad := '';
    -- stated WITHOUT reference to any mutation: one dog with an open case blocks exactly one dog.
    if t176_n(v_res,'ended') <> 4 or t176_n(v_res,'blocked') <> 4
      then v_bad := v_bad || ' ended/blocked=' || t176_n(v_res,'ended') || '/' || t176_n(v_res,'blocked'); end if;
    if (select run_ended_at from bookings where id = t176_bk(dA)) is null
      then v_bad := v_bad || ' 무관한 페어(dA)가 끝나지 않았다'; end if;
    if (select run_ended_at from bookings where id = t176_bk(dCi)) is not null
      then v_bad := v_bad || ' 케이스가 열린 페어가 끝났다'; end if;
    -- and the two lists are DISTINCT vocabularies: nothing appears in both
    if exists (select 1 from jsonb_array_elements(v_res->'ended') a
                join jsonb_array_elements(v_res->'blocked') b on a->>'sdId' = b->>'sdId')
      then v_bad := v_bad || ' 같은 페어가 두 목록에 있다'; end if;
    if v_bad = ''
      then call _pass('pke','P5 최선 노력, 원자성 아님 — 케이스가 열린 개 하나가 막는 것은 정확히 그 개 하나다. 나머지 네 페어는 같은 호출에서 끝났고 보호자들은 자기 아이의 기록을 받는다. 원자-아니면-무는 러너 한 명의 미해소 케이스로 세션 전체를 멈추고, 호스트의 유일한 구제책은 현장에서 케이스를 해소하는 것 — 설계상 빠르게 할 수 없는 단 하나의 일이다(club_incident_resolve는 정산을 먼저 요구한다, 0072:276-283). 0118:64가 세션 전체 루프의 raise 한 번으로 세션 한 판의 환불을 잃은 기록이다');
      else call _fail('pke','P5 best-effort', v_bad); end if;
  exception when others then call _fail('pke','P5 best-effort', sqlerrm);
  end;

  -- ═══ [P6] 💰 THE TAP MINTS NOTHING AND MOVES NO LEDGER ROW ══════════════════════════════
  begin
    v_bad := '';
    if m_led <> n_led then v_bad := v_bad || ' ledger_items +' || (m_led - n_led); end if;
    if m_pay <> n_pay then v_bad := v_bad || ' payments +' || (m_pay - n_pay); end if;
    if m_fee <> n_fee then v_bad := v_bad || ' club_fee_items +' || (m_fee - n_fee); end if;
    if m_mil <> n_mil then v_bad := v_bad || ' miles_ledger +' || (m_mil - n_mil); end if;
    -- `runs.settled_at` is the settlement anchor (0083 §1) and the tap must never touch it —
    -- it is also what keeps a tapped-but-unsettled club run invisible to
    -- `sweep_settled_without_payments` (0116:60), which would otherwise bill an owner mid-귀가
    if exists (select 1 from runs where booking_id in
                 (t176_bk(dA), t176_bk(dB1), t176_bk(dB2), t176_bk(dC)) and settled_at is not null)
      then v_bad := v_bad || ' settled_at이 찍혔다'; end if;
    -- and the club payout state machine did not advance: `none`, for every pairing
    if exists (select 1 from session_dogs where id in (dA,dB1,dB2,dC,dCi,dD,dE,dF)
                 and payout_state <> 'none')
      then v_bad := v_bad || ' payout_state가 움직였다'; end if;
    if v_bad = ''
      then call _pass('pke','P6 💰 탭은 돈을 만들지 않는다 — 원장 0행, 결제 0행, 수수료 0행, 마일 0행, runs.settled_at 미기입, payout_state 전부 none. 호스트는 「언제」를 선언하고 서버는 「무엇」을 도출하며 청구는 여전히 자기만의 게이트된 단계다(§11.2). 이것이 무너지면 호스트가 버튼 하나로 N명의 보호자에게 청구하게 된다 — 컷오버 이후에는 카드에');
      else call _fail('pke','P6 no money minted', v_bad); end if;
  exception when others then call _fail('pke','P6 no money minted', sqlerrm);
  end;
exception when others then
  call _fail('pke','BLOCK1 fixtures + first tap', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 2 — the second tap. A NEW TRANSACTION, so `now()` really has moved on.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare v_res jsonb; v_at1 timestamptz; v_at2 timestamptz; v_bad text := '';
begin
  v_at1 := t176_get('at1')::timestamptz;
  perform set_config('request.jwt.claim.sub', t176_get('host'), false);
  v_res := club_end_pack_runs(t176_id('s1'));
  perform set_config('request.jwt.claim.sub', '', false);
  v_at2 := (v_res->>'at')::timestamptz;

  begin
    if v_at2 <= v_at1 then
      -- the pin's own precondition: if the two taps share an instant, the timestamp arm below
      -- is vacuous and would score green while measuring nothing
      v_bad := v_bad || ' 두 탭이 같은 순간이다 (타임스탬프 팔이 무의미해진다)';
    end if;
    if t176_n(v_res,'ended') <> 0 then v_bad := v_bad || ' ended=' || t176_n(v_res,'ended'); end if;
    if t176_n(v_res,'already') <> 4 then v_bad := v_bad || ' already=' || t176_n(v_res,'already'); end if;
    if t176_reason(v_res,'already',t176_id('dA')) is distinct from 'already_ended'
      then v_bad := v_bad || ' dA=' || coalesce(t176_reason(v_res,'already',t176_id('dA')),'∅'); end if;
    -- 🔴 the stamp is the FIRST tap's, not the second's — the idempotency key is
    -- `run_ended_at is null` evaluated under the row lock, not a returned token
    if (select count(*) from bookings b
         where b.id in (t176_bk(t176_id('dA')), t176_bk(t176_id('dB1')),
                        t176_bk(t176_id('dB2')), t176_bk(t176_id('dC')))
           and b.run_ended_at = v_at1) <> 4
      then v_bad := v_bad || ' 스탬프가 두 번째 탭 시각으로 덮였다'; end if;
    if (select count(*) from runs r
         where r.booking_id in (t176_bk(t176_id('dA')), t176_bk(t176_id('dC')))
           and r.ended_at = v_at1) <> 2
      then v_bad := v_bad || ' runs.ended_at이 덮였다'; end if;
    -- the blocked pairs are still blocked, for the same named reasons
    if t176_n(v_res,'blocked') <> 4 then v_bad := v_bad || ' blocked=' || t176_n(v_res,'blocked'); end if;
    if v_bad = ''
      then call _pass('pke','P4 두 번째 탭은 오류가 아니라 같은 탭이다 — ended는 빈 목록, 네 페어 전부 already/already_ended, 예외 없음. 그리고 stamp는 여전히 첫 탭의 시각이다(이 블록은 별도 트랜잭션이라 now()가 실제로 다르다 — 같은 블록이었다면 이 팔은 공허하게 초록이었을 것이다). 멱등 키는 반환 토큰도 클라 논스도 개수도 아니고 행 락 아래에서 읽은 run_ended_at is null이다(0083:386-388과 같은 모양)');
      else call _fail('pke','P4 idempotence', v_bad); end if;
  end;
exception when others then call _fail('pke','P4 idempotence', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 3 — R-1: the post-tap state is STABLE under a session_dogs write
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 This is the pin for the trap that killed the contract's original central deliverable.
-- `session_dogs` carries `club_v1_axes_sync` (0040:280-282), BEFORE INSERT OR UPDATE, FOR EACH
-- ROW, no WHEN clause, which recomputes every axis from `_club_compute_axes` on EVERY write —
-- and that function derives `custody_phase` from `bookings.status` (0048:806-807). So §1-ⓑ's
-- 「the fan-out writes custody_phase = 'return_pending'」 could never have stuck.
-- 0144 therefore does not write custody at all, and this pin measures the consequence in BOTH
-- directions: what the tap wrote survives a normalizer pass, and what the tap deliberately did
-- NOT write is still not there.
do $$
declare v_sd uuid; v_bk uuid; v_before text; v_after text; v_km numeric; v_st timestamptz;
        v_bad text := '';
begin
  v_sd := t176_id('dC'); v_bk := t176_bk(v_sd);
  select sd.custody_phase || '/' || sd.payout_state || '/' || sd.custodian_type
         || '/' || sd.service_state || '/' || sd.assignment_state
    into v_before from session_dogs sd where sd.id = v_sd;
  select actual_km into v_km from runs where booking_id = v_bk;
  select run_ended_at into v_st from bookings where id = v_bk;

  -- the write that fires the normalizer. `update … set id = id` is 0048:822's own idiom for
  -- 「re-derive every row」 and is the cheapest possible touch of this table.
  update session_dogs set id = id where id = v_sd;

  select sd.custody_phase || '/' || sd.payout_state || '/' || sd.custodian_type
         || '/' || sd.service_state || '/' || sd.assignment_state
    into v_after from session_dogs sd where sd.id = v_sd;

  if v_after is distinct from v_before then v_bad := v_bad || ' 축이 바뀌었다 ' || v_before || ' → ' || v_after; end if;
  if (select actual_km from runs where booking_id = v_bk) is distinct from v_km
    then v_bad := v_bad || ' actual_km이 정규화에 쓸려나갔다'; end if;
  if (select run_ended_at from bookings where id = v_bk) is distinct from v_st
    then v_bad := v_bad || ' run_ended_at이 정규화에 쓸려나갔다'; end if;
  -- and the deliberate absence, stated as a measurement rather than as a comment
  if (select custody_phase from session_dogs where id = v_sd) <> 'with_custodian'
    then v_bad := v_bad || ' custody_phase=' || (select custody_phase from session_dogs where id = v_sd); end if;
  if (select payout_state from session_dogs where id = v_sd) <> 'none'
    then v_bad := v_bad || ' payout_state=' || (select payout_state from session_dogs where id = v_sd); end if;
  -- the normalizer is still in place and ENABLED — tgenabled is the STATE, the definition is only
  -- the shape (the law learned on this very trigger, quoted by 0140 §D)
  if (select count(*) from pg_trigger
       where tgrelid = 'public.session_dogs'::regclass
         and tgname = 'club_v1_axes_sync' and tgenabled = 'O') <> 1
    then v_bad := v_bad || ' club_v1_axes_sync가 1/O가 아니다'; end if;

  if v_bad = ''
    then call _pass('pke','P8 탭 이후 상태는 session_dogs 쓰기에 안정적이다 — 정규화 트리거를 실제로 한 번 돌린 뒤에도 다섯 축이 그대로이고 동결된 숫자도 그대로다. 그리고 의도된 부재가 측정된다: custody_phase는 여전히 with_custodian이고 payout_state는 none이다. 이 슬라이스는 반환을 정산보다 먼저 열지 않는다 — 계약 §1-ⓑ는 §0-bis R-1로 무효이며, custody_phase는 bookings.status에서 파생되므로(0048:806-807) 팬아웃이 그것을 썼다면 예외도 빨간 게이트도 없이 조용히 되돌려졌을 것이다. 파생 축을 다시 키잉하는 것은 별개의 결정이고 여기서 몰래 하지 않는다');
    else call _fail('pke','P8 derived-axes stability', v_bad); end if;
exception when others then call _fail('pke','P8 derived-axes stability', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 4 — the residual §0c names: the trace window is NOT closed by the tap
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare v_sd uuid; v_bk uuid; v_before int; v_after int; v_km numeric; v_bad text := '';
        v_t0 timestamptz;
begin
  v_sd := t176_id('dC'); v_bk := t176_bk(v_sd);
  select jsonb_array_length(trace), actual_km, started_at into v_before, v_km, v_t0
    from runs where booking_id = v_bk;
  perform set_config('request.jwt.claim.sub', t176_get('rC'), false);
  -- an append AFTER the freeze, through the shipped RPC, by the runner who owns it
  perform club_save_run_trace(t176_id('s1'), t176_trace(v_t0 + interval '40 minutes', 5, 60, 80));
  perform set_config('request.jwt.claim.sub', '', false);
  select jsonb_array_length(trace) into v_after from runs where booking_id = v_bk;

  if v_after <= v_before then v_bad := v_bad || ' 추가분이 붙지 않았다 (' || v_before || '→' || v_after || ')'; end if;
  if (select actual_km from runs where booking_id = v_bk) is distinct from v_km
    then v_bad := v_bad || ' 🔴 동결된 km이 움직였다'; end if;
  if v_bad = ''
    then call _pass('pke','P9 측정으로 기록된 잔여 사항 — 탭 이후에도 club_save_run_trace는 추가를 받아들이고 트레이스는 동결선을 넘어 계속 자란다. 돈은 움직이지 않는다(actual_km은 동결되고 0083:744가 이제 그것을 보존한다). 마켓플레이스는 이 창을 닫는다: end_run_tx가 최종 트레이스를 커밋하고 _guard_run_cols의 「종료 후 동결」 팔(0083:295)이 문다. 그 팔은 current_user in (authenticated, anon)일 때만 물고 club_save_run_trace는 SECURITY DEFINER라 보이지 않는다. 한 줄 구제책은 그 함수의 셀렉터에 and b.run_ended_at is null 이며, 이는 이 슬라이스가 만지도록 범위 지정되지 않은 shipped 함수의 재생성이다 — 그래서 의심이 아니라 사실로 넘긴다');
    else call _fail('pke','P9 trace window residual', v_bad); end if;
exception when others then call _fail('pke','P9 trace window residual', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 5 — 🔴 P7. THE PIN THIS FILE EXISTS FOR: the settle prices from the SERVER's numbers
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bkA uuid; v_bkB uuid; v_srv record; v_dev record; v_row record;
  v_res jsonb; v_bad text := ''; v_tok text; v_n int;
  DEVICE_KM constant numeric := 9.99;      -- deliberately NOT the derived 3.00
begin
  v_bkA := t176_bk(t176_id('dA'));
  v_bkB := t176_bk(t176_id('dB1'));

  -- both prices computed HERE, at assertion time, from the shipped pricing function — no money
  -- literal is written down, so neither arm can rot when pricing moves (0083 §0d's rule)
  select * into v_srv from compute_runner_payout(v_bkA, 'completed', 3.00, 0.33);
  select * into v_dev from compute_runner_payout(v_bkA, 'completed', DEVICE_KM, 0.33);
  if v_srv.distance = v_dev.distance then
    -- a control that CAN fail: if the two prices were equal the pin could not tell them apart
    v_bad := v_bad || ' 전제 붕괴: 서버 km과 디바이스 km의 가격이 같다';
  end if;

  -- ⓐ the runner's own settle still works after the host ended the run, through a transcription
  --    of the shipping handler, carrying the DEVICE's numbers in its body
  v_res := t176_settle_like_handler(v_bkA, DEVICE_KM, 'dog_condition', 60);
  if (select status::text from bookings where id = v_bkA) <> 'completed'
    then v_bad := v_bad || ' 정산 후 상태=' || (select status::text from bookings where id = v_bkA); end if;
  select count(*) into v_n from ledger_items where booking_id = v_bkA;
  if v_n <> 1 then v_bad := v_bad || ' 원장 행 수=' || v_n; end if;

  -- ⓑ 🔴 THE MEASUREMENT. The ledger row is the SERVER's price, not the phone's.
  select * into v_row from ledger_items where booking_id = v_bkA;
  if v_row.distance_pay is distinct from v_srv.distance
    then v_bad := v_bad || ' distance_pay=' || v_row.distance_pay || ' 서버=' || v_srv.distance; end if;
  if v_row.distance_pay = v_dev.distance
    then v_bad := v_bad || ' 🔴 원장이 디바이스 km으로 값이 매겨졌다'; end if;
  if v_row.base is distinct from v_srv.base or v_row.platform_fee is distinct from v_srv.fee
    then v_bad := v_bad || ' base/fee가 서버 산정과 다르다'; end if;

  -- ⓒ and the frozen row was not rewritten by the settle (0083:744's preservation arm)
  if (select actual_km from runs where booking_id = v_bkA) <> 3.00
    then v_bad := v_bad || ' 정산이 actual_km을 덮었다: '
                        || (select actual_km::text from runs where booking_id = v_bkA); end if;
  if (select end_reason::text from runs where booking_id = v_bkA) <> 'completed'
    then v_bad := v_bad || ' 디바이스의 end_reason이 이겼다'; end if;
  if (select ended_at from runs where booking_id = v_bkA)
     is distinct from t176_get('at1')::timestamptz
    then v_bad := v_bad || ' 정지 시각이 정산 시각으로 덮였다'; end if;

  -- ⓓ the SQL-side belt, independent of the handler: a direct caller carrying the device's km
  --    is REFUSED rather than silently corrected (0083:709-717)
  v_tok := '';
  begin
    perform settle_run_tx(v_bkB, DEVICE_KM, 1800, 'completed', null, 9900, 29970, 0, 0, 12000);
    v_tok := '<no raise>';
  exception when others then v_tok := sqlerrm;
  end;
  if position('frozen_measurement_mismatch' in v_tok) = 0
    then v_bad := v_bad || ' 직접 호출이 거부되지 않았다: ' || v_tok; end if;

  -- ⓔ and the return is now reachable BY THE NORMAL ROUTE — the runner's settle moved the
  --    booking to `completed`, the 0045 trigger moved custody to `return_pending` and payout to
  --    `earned`. That is Sean's 「so they can move on to the transfer」, arrived at honestly.
  if (select custody_phase from session_dogs where id = t176_id('dA')) <> 'return_pending'
    then v_bad := v_bad || ' 정산 후 custody_phase='
                        || (select custody_phase from session_dogs where id = t176_id('dA')); end if;
  if (select payout_state from session_dogs where id = t176_id('dA')) <> 'earned'
    then v_bad := v_bad || ' 정산 후 payout_state='
                        || (select payout_state from session_dogs where id = t176_id('dA')); end if;

  if v_bad = ''
    then call _pass('pke','P7 💰 러너의 자기 정산이 서버의 숫자로 값이 매겨진다 — 이 파일이 존재하는 이유. shipping 핸들러를 그대로 옮긴 경로에 디바이스 km 9.99와 사유 dog_condition을 실어 보냈고, 원장은 서버가 도출한 3.00으로 계산됐다(두 가격은 compute_runner_payout으로 assertion 시점에 계산해 서로 다름을 먼저 확인한다 — 실패할 수 있는 컨트롤). 동결 행은 정산이 덮어쓰지 않았고(0083:744) 정지 시각도 정산 시각으로 밀리지 않았다. 핸들러와 무관한 SQL 벨트도 확인: 디바이스 숫자를 든 직접 호출은 frozen_measurement_mismatch로 거부된다(조용한 보정이 아니라 거부 — 0083:709-717). 그리고 정산이 끝나자 반환이 정상 경로로 열린다(return_pending·earned)');
    else call _fail('pke','P7 settle prices from the frozen numbers', v_bad); end if;
exception when others then call _fail('pke','P7 settle prices from the frozen numbers', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 6 — the party gate, and the order of the gates
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare v_bad text := ''; a text; b text; c text; d text; f text; g text;
        v_s1 uuid; v_s3 uuid;
begin
  v_s1 := t176_id('s1'); v_s3 := t176_id('s3');

  -- s3 is cancelled through the real RPC, so `session_closed` is reached by the machine
  perform set_config('request.jwt.claim.sub', t176_get('host'), false);
  perform club_cancel_session(v_s3);

  -- ⓐ a PLAIN MEMBER — and not a bystander: rA is a committed, checked-in handling runner of
  --    this very session who holds one of its dogs. If anyone but the host and backup could end
  --    other people's runs, it would be this person.
  begin perform set_config('request.jwt.claim.sub', t176_get('rA'), false);
        perform club_end_pack_runs(v_s1); a := '<no raise>';
  exception when others then a := sqlerrm; end;
  -- ⓑ a session that does not exist, asked by the HOST
  begin perform set_config('request.jwt.claim.sub', t176_get('host'), false);
        perform club_end_pack_runs('00000000-0000-0000-0000-000000000144'::uuid); b := '<no raise>';
  exception when others then b := sqlerrm; end;
  -- ⓒ a stranger with no relationship to the club at all
  begin perform set_config('request.jwt.claim.sub', t176_get('stranger'), false);
        perform club_end_pack_runs(v_s1); c := '<no raise>';
  exception when others then c := sqlerrm; end;
  -- ⓓ anon
  begin perform set_config('request.jwt.claim.sub', '', false);
        perform club_end_pack_runs(v_s1); d := '<no raise>';
  exception when others then d := sqlerrm; end;
  -- ⓕ party BEFORE state: a stranger on the CANCELLED session
  begin perform set_config('request.jwt.claim.sub', t176_get('stranger'), false);
        perform club_end_pack_runs(v_s3); f := '<no raise>';
  exception when others then f := sqlerrm; end;
  -- ⓖ the host on the cancelled session
  begin perform set_config('request.jwt.claim.sub', t176_get('host'), false);
        perform club_end_pack_runs(v_s3); g := '<no raise>';
  exception when others then g := sqlerrm; end;
  perform set_config('request.jwt.claim.sub', '', false);

  if position('not_host' in a) = 0 then v_bad := v_bad || ' 멤버=' || a; end if;
  if position('not_host' in b) = 0 then v_bad := v_bad || ' 없는세션=' || b; end if;
  if position('not_host' in c) = 0 then v_bad := v_bad || ' 낯선이=' || c; end if;
  if position('not_signed_in' in d) = 0 then v_bad := v_bad || ' anon=' || d; end if;
  -- ⓑ vs ⓒ compared TO EACH OTHER, not to a literal: two paths that both regressed to the same
  -- NEW string would still be indistinguishable, and INDISTINGUISHABILITY is the property
  if b is distinct from c then v_bad := v_bad || ' 존재 오라클: 없는세션≠남의세션 (' || b || ' vs ' || c || ')'; end if;
  if position('not_host' in f) = 0 or position('session_closed' in f) > 0
    then v_bad := v_bad || ' 게이트 순서: 낯선이가 취소된 세션에서=' || f; end if;
  if position('session_closed' in g) = 0 then v_bad := v_bad || ' 호스트+취소세션=' || g; end if;
  -- ⓔ the fail-open's precondition, asserted so the arm is known to have exercised the NULL case
  if (select backup_host_profile_id from club_sessions where id = v_s1) is not null
    then v_bad := v_bad || ' s1의 백업이 NULL이 아니다 — in(…) 페일오픈이 도달 불가라 ⓐ/ⓒ가 그것을 재지 못했다'; end if;
  -- nothing was written by any refusal
  if (select count(*) from bookings b2 where b2.club_session_id = v_s3 and b2.run_ended_at is not null) <> 0
    then v_bad := v_bad || ' 거부가 무언가를 썼다'; end if;

  if v_bad = ''
    then call _pass('pke','P10 당사자 게이트가 상태 게이트보다 먼저다 — 커밋·체크인까지 마치고 이 세션의 개를 맡고 있는 핸들링 러너도 not_host, 낯선이도 not_host, 없는 세션도 **글자 하나까지 같은** not_host(존재 오라클 없음 — 두 답을 리터럴이 아니라 서로 비교한다), anon은 not_signed_in. 취소된 세션에서 낯선이는 session_closed가 아니라 not_host를 받는다(순서가 맞아야만 참인 명제). ⚠ 이 세션의 backup_host_profile_id는 NULL이고 그것이 이 팔의 요점이다: 게이트를 auth.uid() in (host, backup)으로 쓰면 NULL 하나로 술어 전체가 NULL이 되어 not(NULL)은 절대 발화하지 않는다 — 이 저장소가 이미 두 번 배포한 페일오픈(0072:117-121, 0116:410)');
    else call _fail('pke','P10 party gate', v_bad); end if;
exception when others then call _fail('pke','P10 party gate', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 7 — the feature flag, and the BACKUP HOST actually ending runs
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⓐ and ⓑ are one fixture used twice, deliberately: ⓑ is the control that ⓐ's refusal came from
-- the FLAG and not from a fixture that could never have ended anything.
do $$
declare v_res jsonb; v_tok text; v_bad text := ''; s2a uuid; s2b uuid;
begin
  s2a := t176_id('s2a'); s2b := t176_id('s2b');

  -- ⓐ flag OFF → the backup host's tap is refused, and NOTHING is written
  update club_flags set enabled = false where name = 'club_delegation_v2';
  begin perform set_config('request.jwt.claim.sub', t176_get('backup'), false);
        perform club_end_pack_runs(t176_id('s2')); v_tok := '<no raise>';
  exception when others then v_tok := sqlerrm; end;
  if position('feature_disabled' in v_tok) = 0 then v_bad := v_bad || ' 플래그OFF=' || v_tok; end if;
  if (select count(*) from bookings where id in (t176_bk(s2a), t176_bk(s2b))
        and run_ended_at is not null) <> 0
    then v_bad := v_bad || ' 플래그가 꺼졌는데 스탬프가 찍혔다'; end if;
  if (select count(*) from runs where booking_id in (t176_bk(s2a), t176_bk(s2b))
        and actual_km is not null) <> 0
    then v_bad := v_bad || ' 플래그가 꺼졌는데 km이 써졌다'; end if;

  -- ⓒ the feature gate precedes the STATE gate too — on a cancelled session the answer is still
  --   feature_disabled, never session_closed
  begin perform set_config('request.jwt.claim.sub', t176_get('host'), false);
        perform club_end_pack_runs(t176_id('s3')); v_tok := '<no raise>';
  exception when others then v_tok := sqlerrm; end;
  if position('feature_disabled' in v_tok) = 0 or position('session_closed' in v_tok) > 0
    then v_bad := v_bad || ' 게이트 순서(플래그 vs 상태)=' || v_tok; end if;

  -- ⓑ flag ON → the SAME caller, the SAME fixture, and now both pairs END. The backup host is
  --   not merely admitted; they can actually end other people's runs, which is the ruled power.
  update club_flags set enabled = true where name = 'club_delegation_v2';
  perform set_config('request.jwt.claim.sub', t176_get('backup'), false);
  v_res := club_end_pack_runs(t176_id('s2'));
  perform set_config('request.jwt.claim.sub', '', false);
  call t176_put('at2', (v_res->>'at'));

  if t176_n(v_res,'ended') <> 2 then v_bad := v_bad || ' 백업 탭 ended=' || t176_n(v_res,'ended'); end if;
  if (select count(*) from runs where booking_id in (t176_bk(s2a), t176_bk(s2b))
        and actual_km = 3.00 and end_reason = 'completed') <> 2
    then v_bad := v_bad || ' 백업 탭이 동결하지 않았다'; end if;
  -- and one of the two pairs is the BACKUP HOST'S OWN dog while the other is somebody else's:
  -- the power is over the pack, not over oneself
  if (select count(distinct b.runner_id) from bookings b
       where b.id in (t176_bk(s2a), t176_bk(s2b))) <> 2
    then v_bad := v_bad || ' 두 페어의 러너가 같다 (팬아웃 성질을 못 잰다)'; end if;

  if v_bad = ''
    then call _pass('pke','P11 기능 플래그가 먼저이고, 백업 호스트는 실제로 런을 끝낼 수 있다 — 플래그를 끄면 백업의 탭이 feature_disabled로 거부되고 스탬프도 km도 한 톨 써지지 않는다. 취소된 세션에서도 답은 session_closed가 아니라 feature_disabled다(기능 게이트가 상태 게이트보다 먼저). 플래그를 켜면 **같은 호출자·같은 픽스처**가 두 페어를 끝낸다 — ⓐ의 빨강이 플래그 때문이지 애초에 끝날 수 없는 픽스처 때문이 아님을 보이는, 실패할 수 있는 컨트롤. 그리고 끝난 두 페어의 러너가 서로 달라, 백업이 가진 권한이 자기 개가 아니라 팩 전체에 대한 것임을 잰다(§11.3: 산책을 끝내는 것은 결승선에 서 있는 사람의 실무 행위, 사람을 빼거나 세션을 닫는 것은 권한 — 세션 종료는 호스트 전용으로 남는다)');
    else call _fail('pke','P11 feature gate + backup host', v_bad); end if;
exception when others then
  update club_flags set enabled = true where name = 'club_delegation_v2';
  call _fail('pke','P11 feature gate + backup host', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 8 — R-3: `runs.ended_at` is the CHARGING CUTOVER and the tap now writes it
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ `ops_flags.payments_live_since` is NULL in production and in every other pin of this harness,
-- so **no green anywhere else can see this** — the 「a green light is evidence for exactly one
-- sentence」 shape, the sentence being 「charging is off, so nothing here is measured」. This pin
-- sets the flag, measures both directions, and puts it back (116's precedent, 116:1268).
do $$
declare v_bk uuid; v_stop timestamptz; v_n int; v_before int; v_bad text := ''; v_row record;
begin
  v_bk := t176_bk(t176_id('s2b'));
  select ended_at into v_stop from runs where booking_id = v_bk;
  if v_stop is null then v_bad := v_bad || ' 전제 붕괴: 정지 스탬프가 없다'; end if;
  select count(*) into v_before from payments where booking_id = v_bk;

  -- ⓐ the run stopped BEFORE the cutover ⇒ free, forever. This only works because `runs.ended_at`
  --   is now the TAP and not the settlement: with the old meaning a run that stopped at 09:58 and
  --   settled at 10:08 would be charged (0083 §0③, from the other direction).
  update ops_flags set payments_live_since = v_stop + interval '1 minute', updated_at = now();
  select count(*) into v_n from mint_settle_charge_intent(v_bk, 'completed', 3.00);
  if v_n <> 0 then v_bad := v_bad || ' 컷오버 이전 런이 청구를 만들었다 rows=' || v_n; end if;
  if (select count(*) from payments where booking_id = v_bk) <> v_before
    then v_bad := v_bad || ' 컷오버 이전인데 payments 행이 생겼다'; end if;

  -- ⓑ the control that CAN fail: move the cutover before the stop and the same call MINTS
  update ops_flags set payments_live_since = v_stop - interval '1 minute', updated_at = now();
  select count(*) into v_n from mint_settle_charge_intent(v_bk, 'completed', 3.00);
  if v_n <> 1 then v_bad := v_bad || ' 컷오버 이후인데 청구가 만들어지지 않았다 rows=' || v_n; end if;
  if (select count(*) from payments where booking_id = v_bk) <> v_before + 1
    then v_bad := v_bad || ' 컷오버 이후인데 payments 행이 없다'; end if;

  -- ⓒ restored, and asserted restored — a later suite must not inherit a live cutover
  update ops_flags set payments_live_since = null, updated_at = now();
  if (select payments_live_since from ops_flags) is not null
    then v_bad := v_bad || ' payments_live_since를 되돌리지 못했다'; end if;

  if v_bad = ''
    then call _pass('pke','P12 💰 runs.ended_at은 과금 컷오버이고 이 탭이 그것을 옮긴다 — mint_settle_charge_intent는 coalesce(r.ended_at, now())를 ops_flags.payments_live_since와 비교한다(0084:265-266). 0144 이전 클럽 런의 ended_at은 **정산 시각**이었고 이제는 **호스트의 탭**, 즉 정직한 정지 시각이다. 컷오버를 정지 시각 뒤로 두면 청구가 만들어지지 않고(파일럿 시대 런은 영원히 무료 — 0080의 소급 과금 금지), 앞으로 두면 같은 호출이 청구를 만든다(실패할 수 있는 컨트롤). 플래그는 NULL로 되돌려 놓았고 되돌아갔음을 확인했다 — 그렇지 않으면 이 파일이 이후 모든 스위트를 오염시킨다');
    else call _fail('pke','P12 charging cutover', v_bad); end if;
exception when others then
  update ops_flags set payments_live_since = null, updated_at = now();
  call _fail('pke','P12 charging cutover', sqlerrm);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 9 — ACLs and sealing, from the catalog
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ 0144's own VERIFY asserts the same facts — ONCE, at apply time. This pin asserts them on
-- EVERY harness run, which is what catches the migration that widens the grant six files later.
-- A one-shot VERIFY and a standing pin prove different things and neither is evidence for the
-- other.
do $$
declare v_secdef boolean; v_cfg text[]; v_bad text := '';
        v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean; v_src text; v_tok text;
begin
  select p.prosecdef, p.proconfig, p.prosrc into v_secdef, v_cfg, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_end_pack_runs';
  if v_secdef is null then v_bad := v_bad || ' 함수가 없다';
  else
    if not v_secdef then v_bad := v_bad || ' SECURITY DEFINER가 아니다'; end if;
    -- IN THE BODY. An ALTER-applied config is reset by `create or replace` (98 H1's law), so a
    -- function that got its search_path by ALTER is one recreation away from unsealed.
    if v_cfg is null or not ('search_path=public, pg_temp' = any(v_cfg))
      then v_bad := v_bad || ' search_path proconfig=' || coalesce(v_cfg::text,'∅'); end if;
    select has_function_privilege('public',        'public.club_end_pack_runs(uuid)', 'execute'),
           has_function_privilege('anon',          'public.club_end_pack_runs(uuid)', 'execute'),
           has_function_privilege('authenticated', 'public.club_end_pack_runs(uuid)', 'execute'),
           has_function_privilege('service_role',  'public.club_end_pack_runs(uuid)', 'execute')
      into v_pub, v_anon, v_auth, v_svc;
    if v_pub  then v_bad := v_bad || ' public이 실행 가능'; end if;
    if v_anon then v_bad := v_bad || ' anon이 실행 가능'; end if;
    -- ⚠ service_role holds EXECUTE through Supabase DEFAULT PRIVILEGES, which a revoke naming
    -- only public/anon/authenticated does NOT touch (0057:59-62). A pin asserting 「no
    -- service_role grant」 without an explicit revoke is green while service_role can execute —
    -- which is why 0144 revokes it by name (0118:937-938's shape).
    if v_svc  then v_bad := v_bad || ' service_role가 실행 가능'; end if;
    if not v_auth then v_bad := v_bad || ' authenticated가 실행 불가 (호스트가 못 누른다)'; end if;
    -- the money surfaces are absent from the SOURCE. This is a text check and it is honest only
    -- because 0144's body deliberately carries no comment naming them: a comment that names the
    -- thing it does not do matches every grep hunting for that thing.
    foreach v_tok in array array['ledger_items','miles_ledger','payments','club_fee_items',
                                 'settle_run_tx','mint_settle_charge_intent','compute_owner_charge',
                                 'compute_runner_payout','payout_state','settled_at',
                                 'custody_phase','update bookings set status']
    loop
      if position(v_tok in v_src) > 0 then v_bad := v_bad || ' 금지 표면: ' || v_tok; end if;
    end loop;
  end if;

  select has_function_privilege('public',        'public._club_derive_run_km(jsonb, timestamptz)', 'execute'),
         has_function_privilege('anon',          'public._club_derive_run_km(jsonb, timestamptz)', 'execute'),
         has_function_privilege('authenticated', 'public._club_derive_run_km(jsonb, timestamptz)', 'execute'),
         has_function_privilege('service_role',  'public._club_derive_run_km(jsonb, timestamptz)', 'execute')
    into v_pub, v_anon, v_auth, v_svc;
  if v_pub or v_anon or v_auth or v_svc
    then v_bad := v_bad || ' 도출 헬퍼 ACL 누출 ' || v_pub||v_anon||v_auth||v_svc; end if;

  -- the two shipped mechanisms this design leans on, re-checked on every run rather than once
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'settle_run_tx';
  if position('frozen_measurement_mismatch' in v_src) = 0
    then v_bad := v_bad || ' settle_run_tx의 동결 게이트가 사라졌다'; end if;
  if position('when v_run_ended is null then excluded.actual_km' in v_src) = 0
    then v_bad := v_bad || ' settle_run_tx가 동결 km을 더 이상 보존하지 않는다 (R-2 재개방)'; end if;

  if v_bad = ''
    then call _pass('pke','P13 ACL·봉인 — club_end_pack_runs는 SECURITY DEFINER이고 search_path를 **본문에** 갖는다(ALTER로 붙인 설정은 create or replace가 지운다, 98 H1). public·anon·service_role는 실행 불가, authenticated만 가능 — service_role는 Supabase 기본 권한으로 EXECUTE를 쥐고 있어 이름을 대고 회수해야 하며(0057:59-62), 회수 없이 「service_role 부여 없음」을 주장하는 핀은 실행 가능한 상태에서 초록이다. 도출 헬퍼는 네 역할 모두 실행 불가(당사자 게이트 없이 caller가 준 트레이스를 받는 함수라 클라 역할이 쥐면 안 된다). 함수 소스에 원장·결제·수수료·정산 함수 이름이 하나도 없고, 이 설계가 기대는 shipped 메커니즘 둘(동결 게이트·동결 보존)이 매 실행마다 다시 확인된다');
    else call _fail('pke','P13 ACL and seal', v_bad); end if;
exception when others then call _fail('pke','P13 ACL and seal', sqlerrm);
end $$;
