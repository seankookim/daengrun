-- ═══ 155 location-law suite — 0120 pins (위치정보법 시행령 제26조의2 파기 + 제16조 확인자료) ═══
-- Contract: the migration's own §0. Statutes and the measured gap:
--   `docs/legal/readiness-review-2026-08-19.md:411-448` (ⓐ nothing purges runs.trace, ⓑ no ledger),
--   `docs/handoff-codex/legal-ops-domain.md` §2.7 / §5.1 / §5.2, `docs/decisions/awaiting-sean.md`
--   §0-sexdecies ("Both are BUILD items… nothing for Sean").
-- Style: sibling of 105-151 — `_pass('loc',…)`/`_fail('loc',…)`. Clear `request.jwt.claim.sub`
--   before `set local role` (129's law). **Assert by EXECUTING**; a privilege listing is not proof
--   (147 M5 / 148 R2 — 148's author wrote that law and broke it in the next file, so it is repeated
--   here). The ONE place this suite reads a catalog instead of executing is L10c, and it says why.
--
-- ─── WHAT THIS SUITE IS ACTUALLY GUARDING ──────────────────────────────────────────────────────
-- Two failures that look nothing alike and are the same failure:
--   ① a purge that keeps what it should destroy — and the way that happens here is NOT a wrong
--      constant, it is `where ended_at < now() - cap` on a NULLABLE column. The run that never
--      ended is the run whose coordinates are most orphaned, and the obvious spelling keeps it
--      forever. NULL fail-open is this repo's recurring defect (0058 F1, 110 S2, 0116 §D) and L2
--      is the pin that exists because of it.
--   ② a ledger that exists and does not record — `gate_code_access_log` (0001:130) has had RLS, a
--      policy and zero writers since the first migration, and `0060:52-53` says so verbatim
--      ("한 번도 쓰인 적 없는 빈 껍데기"). L13/L18 are written so that a shape without a behaviour
--      cannot score green: L13 executes the read and counts the row, L18 makes the ledger
--      unwritable and asserts the COORDINATES DO NOT COME OUT.
--
-- ⚠ THE FIXTURE BORROWS STATE, IT DOES NOT SET IT (148 ① — a fixture that grants or revokes makes
-- the suite measure itself). Nothing here grants, revokes, or creates a policy. The one piece of
-- DDL is L18's temporary raising trigger, which is created and dropped inside its own pin and
-- touches no privilege.
--
-- ⚠ COUNT BASELINES. `purge_expired_run_traces` is global, so this suite never asserts a bare
-- count: it takes a dry run (`p_limit => 0`, which clears nothing) BEFORE seeding and asserts
-- deltas. Every other suite's fixtures are created at `now()`, so the baseline is expected to be 0
-- — but asserting a delta means a future suite that seeds an aged run cannot silently redden this
-- one.
--
-- 20 pins: L1~L8, L10, L10c, L11, L13~L21.
--
-- ─── MUTATION map (PREDICTIONS — this session did not run the harness) ─────────────────────────
--   ⚠ These are stated as predictions on purpose. Fleet law: a dedicated agent measures after the
--   author, because parallel harness runs on one postmaster produce phantom reds. Nothing below is
--   reported as a measurement.
--   M1  0120 §E: delete the `insert into location_access_log`  → red = [L13, L14, L17, L18]
--       (L18 too, and that is the point: with no insert, an unwritable ledger stops refusing.)
--   M2  0120 §G: anchor `least(greatest(ended_at, started_at, b.created_at), now())`
--       → plain `r.ended_at`                                    → red = [L2] alone
--   M3  0120 §C: `interval '1 year'` → `interval '2 years'`     → red = [L1, L3]
--       (L3 because the cap is RECORDED per row, not inferred — the log names the number.)
--   M4  0120 §H: delete the `do $$ … cron.schedule … $$` block  → red = [L7] alone
--   M5  0120 §D: delete the revoke + whitelist grant            → red = [L10] alone
--   M6  0120 §A: `subject_profile_id … references profiles(id) on delete cascade`
--                                                               → red = [L20] alone here, and it
--       is ALSO the shape suite 150 N6-2 was mutation-built to catch (150:118-148, M3d). Two
--       independent guards, which is why the FK is NO ACTION and not merely "not cascade".
--   M7  0120 §E: drop the `where not exists` dedup              → red = [L17] alone
--   M8  0120 §G: drop the `limit` (purge everything at once)    → red = [L4] alone
--   M9  0120 §G: `delete from runs` instead of emptying `trace`
--                                                               → red = [L1, L3, L4, L5, L8] — and
--       it cannot even complete: `location_retention_log.run_id` is NO ACTION, so the delete raises
--       rather than taking the evidence with it. That refusal is the FK doing its job.

-- ─── MEASURED 2026-08-24 (announcer session, main loop) — 13 full harness runs ─────────────────
-- FIRST-EVER measurement. Baseline was 750/1: L10's anon arm asserted anon could read the runs
-- whitelist — FALSE IN PRODUCTION when written (measured live: anon holds no EXECUTE on
-- is_booking_party, so the party-read policy refuses every anon runs read at the executor). Pin
-- fixed to production's world (751/0), commit 8b0fd27. Then the 9-mutation map, one at a time,
-- byte-clean reverts proven between runs; final clean 751/0.
--   M1 ledger insert deleted   → 746/5 RED=[L13,L14,L17,L18,L19]  predicted [L13,L14,L17,L18] (+L19)
--   M2 anchor → plain ended_at → 747/4 RED=[L2,L3,L4,L8]          predicted [L2] alone (superset —
--      the surviving NULL row shifts every downstream count; L2's own arm fired verbatim).
--      ⚠ measurement note: the FIRST M2 attempt scored a FALSE GREEN — the mutation had matched a
--      COMMENT restating the anchor, not the code. Caught by echoing what was replaced. A green
--      mutation is worthless until the mutation provably applied TO THE CODE.
--   M3 cap 1y→2y               → 745/6 RED=[L1,L2,L3,L4,L8,L16]   predicted [L1,L3] (wide superset)
--   M4 cron block deleted      → 750/1 RED=[L7] alone             EXACT — 0060's failure, refused
--   M5 revoke+whitelist gone   → 749/2 RED=[L10,L10c]             predicted [L10] (+the catalog arm)
--   M6 subject FK → cascade    → 749/2 RED=[L20 + 150 N6-2]       EXACT incl. the predicted
--      cross-suite co-fire — "two independent guards" measured as exactly that.
--   M7 dedup dropped           → 750/1 RED=[L17] alone, both window arms  EXACT
--   M8 purge limit dropped     → 750/1 RED=[L4] alone             EXACT
--   M9 delete rows not trace   → 745/6 RED=[L1,L2,L3,L4,L8,L16], and the FK REFUSED the delete
--      verbatim ("violates foreign key constraint location_retention_log_run_id_fkey") — the map's
--      own sentence, measured. Composition differs (predicted L5; measured L2/L16 instead) because
--      the FK raise aborts the purge earlier than the prediction assumed.
-- Net: 5 exact · 4 benign supersets/shifts · 1 pin corrected against production (L10) · zero
-- dangerous greens (the one green was the measurer's own mutation hitting a comment — caught).
set client_min_messages = warning;

do $$
declare
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_json jsonb; v_roots text[];
  o1 uuid; o2 uuid; r1 uuid; d1 uuid; rt uuid; stranger uuid;
  b_old uuid; b_young uuid; b_null uuid; b_future uuid; b_read uuid; b_extra uuid;
  run_old uuid; run_young uuid; run_null uuid; run_future uuid; run_read uuid; run_extra uuid;
  v_base_remaining int; v_purged int; v_points int; v_remaining int;
  v_trace3 jsonb := '[{"lat":37.51,"lng":127.01,"t":1000},{"lat":37.52,"lng":127.02,"t":1060},{"lat":37.53,"lng":127.03,"t":1120}]'::jsonb;
  v_trace2 jsonb := '[{"lat":37.41,"lng":127.11,"t":2000},{"lat":37.42,"lng":127.12,"t":2060}]'::jsonb;
begin
  -- ─── fixture ────────────────────────────────────────────────────────────────────────────────
  o1       := t_user('loc_owner1',   'owner');
  o2       := t_user('loc_owner2',   'owner');
  r1       := t_user('loc_runner1',  'runner');
  stranger := t_user('loc_stranger', 'owner');
  d1 := t_dog(o1, '보리');
  rt := t_route('위치법 테스트 코스');

  -- the dry run BEFORE anything is seeded — see the baseline note in the header
  select remaining_runs into v_base_remaining from purge_expired_run_traces(0);

  -- ⓐ past the cap: anchored 400 days ago on every timestamp it has
  b_old := t_active_booking(o1, r1, d1, rt);
  update bookings set created_at = now() - interval '400 days' where id = b_old;
  update runs set trace = v_trace3,
                  started_at = now() - interval '400 days',
                  ended_at   = now() - interval '400 days' + interval '40 minutes',
                  actual_km = 5.0, settled_at = now() - interval '399 days',
                  photos = array['a.jpg','b.jpg'], events = '[{"k":"start"}]'::jsonb
   where booking_id = b_old;
  select id into run_old from runs where booking_id = b_old;

  -- ⓑ INSIDE the cap by two days — the other half of the boundary
  b_young := t_active_booking(o1, r1, d1, rt);
  update bookings set created_at = now() - interval '363 days' where id = b_young;
  update runs set trace = v_trace2,
                  started_at = now() - interval '363 days',
                  ended_at   = now() - interval '363 days' + interval '30 minutes'
   where booking_id = b_young;
  select id into run_young from runs where booking_id = b_young;

  -- ⓒ THE FAIL-OPEN ROW: never ended, never started. Only `bookings.created_at` says how old it is.
  b_null := t_active_booking(o1, r1, d1, rt);
  update bookings set created_at = now() - interval '500 days' where id = b_null;
  update runs set trace = v_trace3, started_at = null, ended_at = null where booking_id = b_null;
  select id into run_null from runs where booking_id = b_null;

  -- ⓓ a corrupt FUTURE timestamp on an ancient booking — the clamp's row
  b_future := t_active_booking(o1, r1, d1, rt);
  update bookings set created_at = now() - interval '900 days' where id = b_future;
  update runs set trace = v_trace2, started_at = null, ended_at = now() + interval '900 days'
   where booking_id = b_future;
  select id into run_future from runs where booking_id = b_future;

  -- ⓔ a THIRD overdue row so "bounded" has something to be bounded against (ⓐ + ⓒ + this = 3)
  b_extra := t_active_booking(o1, r1, d1, rt);
  update bookings set created_at = now() - interval '450 days' where id = b_extra;
  update runs set trace = v_trace2, started_at = null,
                  ended_at = now() - interval '450 days' + interval '20 minutes'
   where booking_id = b_extra;
  select id into run_extra from runs where booking_id = b_extra;

  -- ⓕ a live, in-cap run used by every §B pin. Owner o2 so §B's owner arm is a different person.
  b_read := t_active_booking(o2, r1, d1, rt);
  update runs set trace = v_trace3 where booking_id = b_read;
  select id into run_read from runs where booking_id = b_read;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- §A — THE PURGE
  -- ══════════════════════════════════════════════════════════════════════════════════════════

  -- ORDER OF THE §A PINS IS DELIBERATE. L4 runs first because it is the only pin that must observe
  -- the purge MID-FLIGHT (one bounded call at a time, oldest first); L1/L2/L3/L5 then read the
  -- settled state it leaves behind. Overdue at seed time = ⓐ(400d) + ⓒ(500d) + ⓔ(450d) = 3, and
  -- ⓓ is deliberately NOT among them — its future-dated `ended_at` clamps to now().

  -- ── L4: bounded, resumable, oldest first, and `remaining` tells the truth ────────────────────
  begin
    v_bad := '';
    select purged_runs, purged_points, remaining_runs into v_purged, v_points, v_remaining
      from purge_expired_run_traces(1);
    if v_purged <> 1 then v_bad := v_bad || ' 1회차가 ' || v_purged || '행을 지웠다 (경계가 없다)'; end if;
    if v_remaining <> v_base_remaining + 2 then
      v_bad := v_bad || ' 1회차 remaining=' || v_remaining || ' (기대 ' || (v_base_remaining + 2) || ')'; end if;
    -- oldest first: 만기 3건(ⓐ 400일·ⓒ 500일·ⓔ 450일) 중 가장 오래된 것은 ⓒ. ⓓ는 클램프로 만기가 아니다.
    if (select trace from runs where id = run_null) <> '[]'::jsonb then
      v_bad := v_bad || ' 가장 오래된 행(500일)이 먼저 처리되지 않았다'; end if;

    select purged_runs into v_purged from purge_expired_run_traces(1);
    if v_purged <> 1 then v_bad := v_bad || ' 2회차가 ' || v_purged || '행'; end if;
    select purged_runs, remaining_runs into v_purged, v_remaining from purge_expired_run_traces(1);
    if v_purged <> 1 then v_bad := v_bad || ' 3회차가 ' || v_purged || '행'; end if;
    if v_remaining <> v_base_remaining then
      v_bad := v_bad || ' 3회차 뒤 remaining=' || v_remaining || ' (기대 ' || v_base_remaining || ' — 밀린 게 없어야 한다)'; end if;
    -- and a fourth call on a drained queue is a no-op, not an error. Expressed against the baseline
    -- rather than against 0: if a future suite seeds an aged run of its own, this pin must not
    -- redden for someone else's fixture.
    select purged_runs into v_purged from purge_expired_run_traces(1);
    if v_purged <> least(v_base_remaining, 1) then
      v_bad := v_bad || ' 큐가 빈 뒤 4회차가 ' || v_purged || '행을 지웠다 (기대 ' || least(v_base_remaining,1) || ')'; end if;

    if v_bad = '' then
      call _pass('loc','L4 파기는 경계·재개 가능하다 — p_limit=1이면 매 호출 정확히 한 행(오래된 것부터)만 처리하고, remaining이 남은 백로그를 정직하게 세며, 세 번이면 다 빠지고 네 번째는 오류가 아니라 무동작이다 (경계 없는 set-based UPDATE는 전 이력 런을 한 문장으로 잠근다)');
    else v_msg := v_bad; call _fail('loc','L4 파기는 경계·재개 가능하다', v_msg); end if;
  exception when others then call _fail('loc','L4 파기는 경계·재개 가능하다', sqlerrm); end;

  -- ── L1: the boundary — past the cap goes, inside the cap is byte-identical ───────────────────
  begin
    v_bad := '';
    if (select trace from runs where id = run_old) <> '[]'::jsonb then
      v_bad := v_bad || ' 400일 지난 트레이스가 남아 있다'; end if;
    if (select trace from runs where id = run_young) <> v_trace2 then
      v_bad := v_bad || ' 상한 안(363일) 트레이스가 훼손됐다 — 파기가 과했다'; end if;
    if (select count(*) from location_retention_log where run_id = run_young) <> 0 then
      v_bad := v_bad || ' 지우지도 않은 행의 파기 기록이 있다'; end if;
    if v_bad = '' then
      call _pass('loc','L1 경계 양방향 — 상한(1년)을 넘긴 런의 좌표는 사라지고, 이틀 차이로 상한 안에 있는 런의 좌표는 바이트 단위로 그대로다. 한쪽만 있는 핀은 "전부 지운다"와 구별되지 않는다');
    else v_msg := v_bad; call _fail('loc','L1 경계 양방향', v_msg); end if;
  exception when others then call _fail('loc','L1 경계 양방향', sqlerrm); end;

  -- ── L2: NULL does not fail open, and a future timestamp does not either ─────────────────────
  begin
    v_bad := '';
    if (select trace from runs where id = run_null) <> '[]'::jsonb then
      v_bad := v_bad || ' ended_at·started_at이 NULL인 500일 된 런의 좌표가 살아남았다 — 앵커가 fail-open이다'; end if;
    if (select subject_profile_id from location_retention_log where run_id = run_null) is distinct from r1 then
      v_bad := v_bad || ' NULL 앵커 행의 파기 기록에 주체가 없다'; end if;
    -- the clamp: a 900-day-old booking whose ended_at is corrupt-future is NOT destroyed today
    if (select trace from runs where id = run_future) <> v_trace2 then
      v_bad := v_bad || ' 미래로 오염된 타임스탬프 행이 오늘 파기됐다 — 클램프는 늦추기만 해야 하고 앞당겨선 안 된다'; end if;
    if v_bad = '' then
      call _pass('loc','L2 NULL 앵커는 열린 채 실패하지 않는다 — `where ended_at < now() - cap`은 끝나지 않은 런(=좌표가 가장 고아인 런)을 영원히 보관한다. greatest(ended_at, started_at, bookings.created_at)은 bookings.created_at이 NOT NULL이라 절대 NULL이 될 수 없고, least(…, now())는 미래로 오염된 타임스탬프를 1년 뒤 만료시키되 오늘 앞당겨 파기하지는 않는다');
    else v_msg := v_bad; call _fail('loc','L2 NULL 앵커는 열린 채 실패하지 않는다', v_msg); end if;
  exception when others then call _fail('loc','L2 NULL 앵커는 열린 채 실패하지 않는다', sqlerrm); end;

  -- ── L3: it writes down what it destroyed, and under which cap ───────────────────────────────
  begin
    v_bad := '';
    select count(*) into v_n from location_retention_log where run_id in (run_old, run_null, run_extra);
    if v_n <> 3 then v_bad := v_bad || ' 파기 기록이 ' || v_n || '행 (기대 3)'; end if;
    select points_removed into v_n from location_retention_log where run_id = run_old;
    if v_n <> 3 then v_bad := v_bad || ' 400일 행의 points_removed=' || coalesce(v_n::text,'null') || ' (기대 3)'; end if;
    select points_removed into v_n from location_retention_log where run_id = run_extra;
    if v_n <> 2 then v_bad := v_bad || ' 450일 행의 points_removed=' || coalesce(v_n::text,'null') || ' (기대 2)'; end if;
    -- the cap is RECORDED, not inferred — this is the arm M3 reddens
    if (select cap from location_retention_log where run_id = run_old) <> location_retention_cap() then
      v_bad := v_bad || ' 기록된 cap이 적용된 cap과 다르다'; end if;
    if (select cap from location_retention_log where run_id = run_old) <> interval '1 year' then
      v_bad := v_bad || ' 기록된 cap이 1년이 아니다 (시행령 제26조의2 상한)'; end if;
    if (select anchor_at from location_retention_log where run_id = run_old) > now() then
      v_bad := v_bad || ' 앵커가 미래다'; end if;
    if v_bad = '' then
      call _pass('loc','L3 조용한 대량 삭제가 아니다 — 지운 모든 행이 location_retention_log에 남고(런 3건, 점수 3·2), 적용된 상한이 행마다 기록된다(추론이 아니라 기록 — 나중에 상한을 줄이면 데이터에서 보인다). 지우지 않은 행에는 기록이 없다');
    else v_msg := v_bad; call _fail('loc','L3 조용한 대량 삭제가 아니다', v_msg); end if;
  exception when others then call _fail('loc','L3 조용한 대량 삭제가 아니다', sqlerrm); end;

  -- ── L5: the row survives; only the column is emptied ────────────────────────────────────────
  begin
    v_bad := '';
    if not exists (select 1 from runs where id = run_old) then
      v_bad := v_bad || ' 파기가 runs 행 자체를 지웠다 — runs는 정산·원장·코스증거가 매달린 보존 테이블이다'; end if;
    if (select actual_km from runs where id = run_old) is distinct from 5.0 then
      v_bad := v_bad || ' actual_km이 사라졌다'; end if;
    if (select settled_at from runs where id = run_old) is null then
      v_bad := v_bad || ' settled_at이 사라졌다'; end if;
    if (select array_length(photos, 1) from runs where id = run_old) is distinct from 2 then
      v_bad := v_bad || ' photos가 사라졌다'; end if;
    if (select events from runs where id = run_old) = '[]'::jsonb then
      v_bad := v_bad || ' events가 사라졌다'; end if;
    if v_bad = '' then
      call _pass('loc','L5 파기 대상은 좌표이지 거래가 아니다 — 제26조의2는 개인위치정보의 파기를 요구하지 런 기록의 삭제를 요구하지 않는다. 행은 남고 actual_km·settled_at·photos·events는 그대로, trace만 비워진다');
    else v_msg := v_bad; call _fail('loc','L5 파기 대상은 좌표이지 거래가 아니다', v_msg); end if;
  exception when others then call _fail('loc','L5 파기 대상은 좌표이지 거래가 아니다', sqlerrm); end;

  -- ── L6: no coordinate may ever live in either new table ─────────────────────────────────────
  -- A ledger that stored the track it recorded the reading of would hand the purge a perfect copy
  -- to leave behind under an audit label. This is a column-SHAPE pin on purpose: it fires the day
  -- someone adds lat/lng or a jsonb payload, which is exactly when nobody would be looking.
  -- ⚠ It asserts the EXACT column set, not a name pattern. A pattern was the first draft and it was
  -- wrong in both directions on this very schema: `viewer_relation` contains "lat" and
  -- `points_removed` contains "point", so the pattern flagged two innocent columns — and a pattern
  -- loose enough to spare them would also spare `lat_hint` or a jsonb named `meta`. An exact set is
  -- unambiguous, self-documenting, and reddens on any addition or type change whatsoever.
  begin
    v_bad := '';
    select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) into v_msg
      from information_schema.columns
     where table_schema='public' and table_name='location_access_log';
    if v_msg is distinct from
       'id:bigint,run_id:uuid,subject_profile_id:uuid,viewer_profile_id:uuid,'
       || 'viewer_relation:text,access_kind:text,point_count:integer,'
       || 'accessed_at:timestamp with time zone'
    then v_bad := v_bad || ' location_access_log 컬럼 집합이 바뀌었다: ' || coalesce(v_msg,'(없음)'); end if;

    select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) into v_msg
      from information_schema.columns
     where table_schema='public' and table_name='location_retention_log';
    if v_msg is distinct from
       'id:bigint,run_id:uuid,subject_profile_id:uuid,points_removed:integer,'
       || 'anchor_at:timestamp with time zone,cap:interval,'
       || 'purged_at:timestamp with time zone'
    then v_bad := v_bad || ' location_retention_log 컬럼 집합이 바뀌었다: ' || coalesce(v_msg,'(없음)'); end if;
    if v_bad = '' then
      call _pass('loc','L6 대장과 파기 기록에는 좌표가 없다 — 읽힌 사실을 기록하면서 읽힌 좌표를 함께 보관하면 파기가 무의미해진다(감사 라벨을 단 완벽한 사본). 컬럼 형상 핀이라 lat/lng/jsonb가 추가되는 날 붉어진다');
    else v_msg := v_bad; call _fail('loc','L6 대장과 파기 기록에는 좌표가 없다', v_msg); end if;
  exception when others then call _fail('loc','L6 대장과 파기 기록에는 좌표가 없다', sqlerrm); end;

  -- ── L7: THE CRON ROW, not the function ──────────────────────────────────────────────────────
  -- `0060:129-147`: `purge_expired_holds` sat unscheduled for months while a comment claimed it ran
  -- every minute, and its predicate meant it had never deleted a row. A function without a verified
  -- schedule row is the failure this repo already made. 00_shim gained a pg_cron stub in 0120's
  -- commit so this can be a gate here instead of a sentence.
  begin
    v_bad := '';
    select count(*) into v_n from cron.job where jobname = 'purge-run-traces';
    if v_n <> 1 then
      v_bad := v_bad || ' cron.job에 purge-run-traces 행이 ' || v_n || '개다 — 함수는 있고 일정이 없다(0060의 그 실패)';
    else
      if (select schedule from cron.job where jobname='purge-run-traces') <> '43 17 * * *' then
        v_bad := v_bad || ' 일정이 43 17 * * * 가 아니다'; end if;
      if (select command from cron.job where jobname='purge-run-traces')
         not like '%purge_expired_run_traces%' then
        v_bad := v_bad || ' 명령이 파기 함수를 부르지 않는다'; end if;
      if not (select active from cron.job where jobname='purge-run-traces') then
        v_bad := v_bad || ' 잡이 비활성이다'; end if;
      -- and the command must name something that EXISTS — a scheduled call to a missing function
      -- is a job that fails silently every night
      if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                      where n.nspname='public' and p.proname='purge_expired_run_traces') then
        v_bad := v_bad || ' 예약된 함수가 존재하지 않는다'; end if;
      -- the stagger: nothing else may hold this exact slot
      select count(*) into v_n from cron.job where schedule = '43 17 * * *';
      if v_n <> 1 then v_bad := v_bad || ' 같은 분에 잡이 ' || v_n || '개다 (0060:145 스태거)'; end if;
    end if;
    if v_bad = '' then
      call _pass('loc','L7 핀은 함수가 아니라 cron.job 행에 있다 — purge-run-traces가 43 17 * * *(KST 02:43)에 실재하고, 활성이며, 존재하는 함수를 부르고, 그 슬롯을 혼자 쓴다. 0060:144의 교훈: 주석이 매분 돈다고 말하는 동안 실제로는 몇 달간 예약된 적이 없었다');
    else v_msg := v_bad; call _fail('loc','L7 핀은 함수가 아니라 cron.job 행에 있다', v_msg); end if;
  exception when others then call _fail('loc','L7 핀은 함수가 아니라 cron.job 행에 있다', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- §B — THE LEDGER AND ITS ONE WINDOW
  -- ══════════════════════════════════════════════════════════════════════════════════════════

  -- ── L10: the raw column is closed to client roles, and the survivors still read ─────────────
  begin
    v_bad := '';
    foreach v_msg in array array['anon','authenticated'] loop
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role ' || v_msg;
      begin
        execute 'select trace from runs limit 1';
        v_bad := v_bad || ' ' || v_msg || ' 이(가) runs.trace를 직접 읽었다';
      exception when insufficient_privilege then null; end;
      -- ⚠ FIXED at first measurement (2026-08-24): the whitelist-readability half runs for
      -- authenticated ONLY. As written it asserted anon could read the whitelist columns — and
      -- that was FALSE IN PRODUCTION when written: measured live, anon holds no EXECUTE on
      -- is_booking_party (authenticated does), so the "runs party read" policy itself refuses
      -- every anon read of runs at the executor. anon's runs access is closed by a different
      -- door, one migration older than this file, and the client's three query shapes are all
      -- authenticated. The pin was asserting a world that never existed — the harness faithfully
      -- reproduced production and went red on the pin, not the code.
      if v_msg = 'authenticated' then
        -- the three shipped client query shapes must all survive (0088/0091's outage direction)
        begin execute 'select photos, booking_id from runs limit 1';
        exception when others then v_bad := v_bad || ' ' || v_msg || ' photos/booking_id 실패: ' || sqlerrm; end;
        begin execute 'select started_at, pace_suggest_sec from runs limit 1';
        exception when others then v_bad := v_bad || ' ' || v_msg || ' started_at/pace 실패: ' || sqlerrm; end;
        begin execute 'select booking_id, actual_km, settled_at, events, end_reason, condition_note, duration_sec, avg_pace_sec_per_km, id, ended_at from runs limit 1';
        exception when others then v_bad := v_bad || ' ' || v_msg || ' 화이트리스트 잔여 컬럼 실패: ' || sqlerrm; end;
      else
        -- anon: EVERY runs read must refuse (the policy's own gate) — assert the closure rather
        -- than skipping the role, so a future grant of is_booking_party to anon surfaces here.
        begin
          execute 'select photos, booking_id from runs limit 1';
          v_bad := v_bad || ' anon이 runs 화이트리스트를 읽었다 (is_booking_party가 anon에 열렸나)';
        exception when others then null; end;
      end if;
      execute 'reset role';
    end loop;
    if v_bad = '' then
      call _pass('loc','L10 원본 컬럼이 닫혔다 — 두 클라 역할 다 runs.trace를 직접 읽지 못하고, authenticated의 세 가지 실제 질의 형상은 그대로 읽히며, anon은 runs 전체가 정책 게이트에서 거절된다(프로덕션 측정과 일치). 과잉 회수는 필드를 숨기는 게 아니라 요청 전체를 403으로 만든다(0088→0091)');
    else v_msg := v_bad; call _fail('loc','L10 원본 컬럼이 닫혔다', v_msg);
    end if;
  exception when others then execute 'reset role'; call _fail('loc','L10 원본 컬럼이 닫혔다', sqlerrm); end;

  -- ── L10c: the whitelist covers the table, and a new column will say so ──────────────────────
  -- ⚠ THIS PIN READS A CATALOG, and 148 R2's law says a privilege listing is not proof. It is the
  -- right instrument HERE and only here: the failure being guarded is a column that does not exist
  -- yet, which no execution can reach. The executing arm is L10 directly above; this arm exists so
  -- that `alter table runs add column …` surfaces as a red pin instead of as a blank screen.
  begin
    v_bad := '';
    select count(*) into v_n from information_schema.columns
     where table_schema='public' and table_name='runs';
    if v_n <> 14 then
      v_bad := v_bad || ' runs 컬럼이 ' || v_n || '개다 (0120 시점 14). 새 컬럼은 클라이언트에게 자동으로 열리지 않는다 — 그 마이그레이션이 grant select (새컬럼) on runs to anon, authenticated 를 함께 내야 한다'; end if;
    select count(*) into v_n2 from information_schema.columns c
     where c.table_schema='public' and c.table_name='runs' and c.column_name <> 'trace'
       and has_column_privilege('authenticated','runs',c.column_name,'SELECT');
    if v_n2 <> v_n - 1 then
      v_bad := v_bad || ' authenticated가 읽을 수 있는 비-trace 컬럼이 ' || v_n2 || '/' || (v_n-1) || '개다'; end if;
    if has_column_privilege('authenticated','runs','trace','SELECT') then
      v_bad := v_bad || ' 카탈로그상 authenticated가 여전히 trace SELECT를 들고 있다'; end if;
    if v_bad = '' then
      call _pass('loc','L10c 화이트리스트가 테이블을 덮는다 — runs의 14개 컬럼 중 trace를 제외한 13개 전부에 authenticated의 SELECT가 있고 trace에는 없다. 화이트리스트의 상시 비용(새 컬럼은 명시 grant가 필요하다)이 빈 화면이 아니라 붉은 핀으로 나타난다');
    else v_msg := v_bad; call _fail('loc','L10c 화이트리스트가 테이블을 덮는다', v_msg); end if;
  exception when others then call _fail('loc','L10c 화이트리스트가 테이블을 덮는다', sqlerrm); end;

  -- ── L11: the write path and the server path both survive ────────────────────────────────────
  begin
    v_bad := '';
    -- saveRunTrace's exact statement, as the booking's runner. The live append surface is NOT the
    -- provision surface, and closing the read must not close the write.
    perform set_config('request.jwt.claim.sub', r1::text, true);
    execute 'set local role authenticated';
    begin
      execute format('update runs set trace = %L::jsonb where booking_id = %L', v_trace3, b_read);
    exception when others then v_bad := v_bad || ' 러너가 자기 런의 trace를 저장하지 못한다: ' || sqlerrm; end;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role service_role';
    begin
      execute 'select trace from runs where trace <> ''[]''::jsonb limit 1';
    exception when others then v_bad := v_bad || ' service_role이 trace를 못 읽는다 — 정산·LA·시드가 전부 여기 매달려 있다: ' || sqlerrm; end;
    execute 'reset role';
    if v_bad = '' then
      call _pass('loc','L11 닫힌 것은 읽기뿐이다 — 러너의 saveRunTrace UPDATE는 그대로 통과하고(라이브 append 표면 ≠ 제공 표면), service_role은 여전히 원본 좌표를 읽는다(비식별화는 공개 독자를 위한 것이지 파생하는 서버를 위한 게 아니다 — 0113 R2)');
    else v_msg := v_bad; call _fail('loc','L11 닫힌 것은 읽기뿐이다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L11 닫힌 것은 읽기뿐이다', sqlerrm); end;

  -- ── L13: every provided read leaves a ledger row — THE PIN M1 REDDENS ───────────────────────
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', r1::text, true);
    execute 'set local role authenticated';
    select run_trace_read(b_read) into v_json;
    execute 'reset role';
    if jsonb_array_length(coalesce(v_json,'[]'::jsonb)) <> 3 then
      v_bad := v_bad || ' 창구가 좌표 3점을 돌려주지 않았다'; end if;
    select count(*) into v_n from location_access_log where run_id = run_read and viewer_profile_id = r1;
    if v_n <> 1 then v_bad := v_bad || ' 확인자료가 ' || v_n || '행 (기대 1)'; end if;
    if (select subject_profile_id from location_access_log where run_id=run_read and viewer_profile_id=r1) <> r1 then
      v_bad := v_bad || ' 주체가 러너가 아니다'; end if;
    if (select viewer_relation from location_access_log where run_id=run_read and viewer_profile_id=r1) <> 'subject' then
      v_bad := v_bad || ' 관계가 subject가 아니다'; end if;
    if (select point_count from location_access_log where run_id=run_read and viewer_profile_id=r1) <> 3 then
      v_bad := v_bad || ' 기록된 점수가 실제 제공된 점수와 다르다'; end if;
    if (select access_kind from location_access_log where run_id=run_read and viewer_profile_id=r1) <> 'run_trace_read' then
      v_bad := v_bad || ' 목적이 서버 파생값이 아니다'; end if;
    if v_bad = '' then
      call _pass('loc','L13 제공된 모든 열람이 확인자료를 남긴다 (제16조 자동 기록) — 러너가 창구로 읽으면 좌표 3점이 나오고 대장에 정확히 한 행이 남는다: 주체=러너, 관계=subject, 목적=서버 파생(클라가 준 문자열이 아니다), 점수=실제 제공된 점수. gate_code_access_log는 이 핀이 없어서 5년째 빈 껍데기다');
    else v_msg := v_bad; call _fail('loc','L13 제공된 모든 열람이 확인자료를 남긴다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L13 제공된 모든 열람이 확인자료를 남긴다', sqlerrm); end;

  -- ── L14: the owner's read is 제공 to a 열람자, and the subject is whose device it was ────────
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', o2::text, true);
    execute 'set local role authenticated';
    select run_trace_read(b_read) into v_json;
    execute 'reset role';
    if jsonb_array_length(coalesce(v_json,'[]'::jsonb)) <> 3 then
      v_bad := v_bad || ' 보호자가 좌표를 못 받았다 — 이 슬라이스는 제품을 좁히지 않는다, 기록할 뿐이다'; end if;
    select count(*) into v_n from location_access_log where run_id = run_read and viewer_profile_id = o2;
    if v_n <> 1 then v_bad := v_bad || ' 보호자 열람의 확인자료가 ' || v_n || '행'; end if;
    if (select subject_profile_id from location_access_log where run_id=run_read and viewer_profile_id=o2) <> r1 then
      v_bad := v_bad || ' 주체가 요청자로 적혔다 — 개인위치정보주체는 기기의 주인(러너)이지 물어본 사람이 아니다'; end if;
    if (select viewer_relation from location_access_log where run_id=run_read and viewer_profile_id=o2) <> 'owner' then
      v_bad := v_bad || ' 관계가 owner가 아니다'; end if;
    if v_bad = '' then
      call _pass('loc','L14 보호자의 열람은 제3자 제공이고 그렇게 기록된다 — `runs party read`(0002:106)는 보호자도 들여보낸다. 클라가 그 경로를 안 쓴다는 것은 통제가 아니다(REGISTRY: 빈 결과는 통제가 아니다). 주체는 기기의 주인(러너), 제공받은 자는 보호자로 적힌다');
    else v_msg := v_bad; call _fail('loc','L14 보호자의 열람은 제3자 제공이고 그렇게 기록된다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L14 보호자의 열람은 제3자 제공이고 그렇게 기록된다', sqlerrm); end;

  -- ── L15: party gate first, and 부재 == 타인 ──────────────────────────────────────────────────
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', stranger::text, true);
    execute 'set local role authenticated';
    begin
      select run_trace_read(b_read) into v_json;
      v_bad := v_bad || ' 제3자가 좌표를 받았다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 제3자 응답=' || sqlerrm; end if;
    end;
    begin
      select run_trace_read('00000000-0000-0000-0000-000000000000'::uuid) into v_json;
      v_bad := v_bad || ' 없는 부킹이 예외를 내지 않았다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 없는 부킹 응답=' || sqlerrm || ' (타인과 달라지면 그 자체가 열거 오라클)'; end if;
    end;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role authenticated';
    begin
      select run_trace_read(b_read) into v_json;
      v_bad := v_bad || ' JWT 없는 호출자가 통과했다';
    exception when others then
      if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' 무JWT 응답=' || sqlerrm; end if;
    end;
    execute 'reset role';
    execute 'set local role anon';
    begin
      execute format('select run_trace_read(%L)', b_read);
      v_bad := v_bad || ' anon이 창구를 실행했다';
    exception when insufficient_privilege then null;
             when others then if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' anon 응답=' || sqlerrm; end if;
    end;
    execute 'reset role';
    select count(*) into v_n from location_access_log
     where run_id = run_read and viewer_profile_id = stranger;
    if v_n <> 0 then v_bad := v_bad || ' 거절된 호출이 대장에 기록을 남겼다'; end if;
    if v_bad = '' then
      call _pass('loc','L15 당사자 게이트가 먼저고, 부재와 타인은 같은 답이다 — 제3자·없는 부킹 모두 not_party, JWT 없는 호출자는 not_signed_in(SECURITY DEFINER 안에서 current_user는 소유자이므로 auth.uid()가 유일한 신원이다), anon은 EXECUTE 자체가 없다. 거절된 호출은 아무것도 제공하지 않았으므로 대장에도 남지 않는다');
    else v_msg := v_bad; call _fail('loc','L15 당사자 게이트가 먼저고, 부재와 타인은 같은 답이다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L15 당사자 게이트가 먼저고, 부재와 타인은 같은 답이다', sqlerrm); end;

  -- ── L16: a read that provided nothing records nothing (and the purged run lands here) ────────
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', r1::text, true);
    execute 'set local role authenticated';
    select run_trace_read(b_old) into v_json;      -- §A emptied this one
    execute 'reset role';
    if v_json <> '[]'::jsonb then v_bad := v_bad || ' 파기된 런이 좌표를 돌려줬다'; end if;
    select count(*) into v_n from location_access_log where run_id = run_old;
    if v_n <> 0 then v_bad := v_bad || ' 0점 제공에 확인자료가 ' || v_n || '행 생겼다 — 유령 기록'; end if;
    if v_bad = '' then
      call _pass('loc','L16 제공한 게 없으면 기록도 없다 (0049:236의 "실제 반환된 번호만") — 파기된 런을 열람하면 빈 배열이 나오고 대장은 조용하다. 반대였다면 파기 뒤의 열람이 유령 이용 기록을 만들어 확인자료 자체를 오염시켰을 것이다');
    else v_msg := v_bad; call _fail('loc','L16 제공한 게 없으면 기록도 없다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L16 제공한 게 없으면 기록도 없다', sqlerrm); end;

  -- ── L17: the dedup is a WINDOW, not a suppression ───────────────────────────────────────────
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', r1::text, true);
    execute 'set local role authenticated';
    select run_trace_read(b_read) into v_json;     -- second read, inside the 10-minute window
    execute 'reset role';
    select count(*) into v_n from location_access_log where run_id = run_read and viewer_profile_id = r1;
    if v_n <> 1 then v_bad := v_bad || ' 10분 창 안 재열람이 ' || v_n || '행을 만들었다 (재마운트가 대장을 도배한다)'; end if;
    -- push the existing row out of the window and read again: a WINDOW re-opens, a suppression does not
    update location_access_log set accessed_at = now() - interval '11 minutes'
     where run_id = run_read and viewer_profile_id = r1;
    perform set_config('request.jwt.claim.sub', r1::text, true);
    execute 'set local role authenticated';
    select run_trace_read(b_read) into v_json;
    execute 'reset role';
    select count(*) into v_n from location_access_log where run_id = run_read and viewer_profile_id = r1;
    if v_n <> 2 then v_bad := v_bad || ' 창 밖 재열람이 새 기록을 남기지 않았다 (' || v_n || '행) — dedup이 창이 아니라 영구 억제다'; end if;
    if v_bad = '' then
      call _pass('loc','L17 dedup은 창이지 억제가 아니다 (0053:435의 club_phone_access_log 관용구) — 10분 안의 재진입·재마운트는 한 행으로 접히고, 창이 지난 열람은 새로운 이용 사실로 다시 기록된다. 영구 억제였다면 두 번째 사건이 법적으로 존재하지 않게 된다');
    else v_msg := v_bad; call _fail('loc','L17 dedup은 창이지 억제가 아니다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L17 dedup은 창이지 억제가 아니다', sqlerrm); end;

  -- ── L18: the record is a PRECONDITION of the provision, not a side effect ────────────────────
  -- This is the pin that separates a ledger from a shape. Make the ledger unwritable and the
  -- coordinates must not come out. Under M1 (insert deleted) the read succeeds and this reddens.
  begin
    v_bad := '';
    execute 'create or replace function _loc155_block() returns trigger language plpgsql as $f$ begin raise exception ''ledger_unwritable''; end $f$';
    execute 'create trigger _loc155_block before insert on location_access_log for each row execute function _loc155_block()';
    -- o2's L14 row must be pushed OUT of the 10-minute window first, or the dedup skips the insert
    -- entirely, the blocking trigger never fires, coordinates come back legitimately, and this pin
    -- measures nothing while looking green.
    update location_access_log set accessed_at = now() - interval '11 minutes'
     where run_id = run_read and viewer_profile_id = o2;
    begin
      perform set_config('request.jwt.claim.sub', o2::text, true);
      execute 'set local role authenticated';
      select run_trace_read(b_read) into v_json;
      v_bad := v_bad || ' 대장에 쓸 수 없는데도 좌표가 나왔다 — 기록은 부작용이 아니라 전제조건이어야 한다';
      execute 'reset role';
    exception when others then
      execute 'reset role';
      if sqlerrm <> 'ledger_unwritable' then v_bad := v_bad || ' 예상치 못한 예외: ' || sqlerrm; end if;
    end;
    execute 'drop trigger if exists _loc155_block on location_access_log';
    execute 'drop function if exists _loc155_block()';
    -- and the refusal left no half-state: the ledger row was not written either
    select count(*) into v_n from location_access_log
     where run_id = run_read and viewer_profile_id = o2 and accessed_at > now() - interval '1 minute';
    if v_n <> 0 then v_bad := v_bad || ' 거절됐는데 새 대장 행이 남았다'; end if;
    if v_bad = '' then
      call _pass('loc','L18 기록은 제공의 전제조건이다 — 대장이 쓰이지 못하는 상태에서 열람하면 좌표가 나오지 않고 호출 전체가 롤백된다(insert가 return보다 먼저, 같은 트랜잭션). "기록 없이 제공"이 구조적으로 불가능하다는 뜻이고, 0060:52가 열어둔 트레이드(로그를 달면 volatile이 된다)를 반대편에서 받은 대가다');
    else v_msg := v_bad; call _fail('loc','L18 기록은 제공의 전제조건이다', v_msg); end if;
  exception when others then
    execute 'reset role';
    begin execute 'drop trigger if exists _loc155_block on location_access_log'; exception when others then null; end;
    begin execute 'drop function if exists _loc155_block()'; exception when others then null; end;
    call _fail('loc','L18 기록은 제공의 전제조건이다', sqlerrm);
  end;

  -- ── L19: the 열람권 window returns the subject's own rows and nobody else's ──────────────────
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', r1::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from my_location_access_log(500);
    execute 'reset role';
    if v_n < 2 then v_bad := v_bad || ' 주체가 자기 확인자료를 ' || v_n || '행밖에 못 본다 (자기 열람 + 보호자 열람 최소 2)'; end if;

    perform set_config('request.jwt.claim.sub', o2::text, true);
    execute 'set local role authenticated';
    select count(*) into v_n from my_location_access_log(500);
    execute 'reset role';
    if v_n <> 0 then v_bad := v_bad || ' 열람자(보호자)가 남의 확인자료를 ' || v_n || '행 봤다 — 이 창구는 주체의 권리이지 열람자의 권리가 아니다'; end if;

    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role authenticated';
    begin
      select count(*) into v_n from my_location_access_log(500);
      v_bad := v_bad || ' JWT 없이 열람권 창구가 열렸다';
    exception when others then
      if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' 무JWT 응답=' || sqlerrm; end if;
    end;
    execute 'reset role';
    if v_bad = '' then
      call _pass('loc','L19 열람권 창구는 주체의 행만 돌려준다 — privacy-policy.md:95가 이미 약속한 권리(제16조 열람·고지)가 이제 답을 만들 수 있다. 러너는 자기 위치가 누구에게 언제 몇 점 제공됐는지 보고, 보호자는 0행을 보며(그는 주체가 아니라 열람자다), JWT 없는 호출은 거절된다. 대장 테이블 자체는 봉인된 채다');
    else v_msg := v_bad; call _fail('loc','L19 열람권 창구는 주체의 행만 돌려준다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L19 열람권 창구는 주체의 행만 돌려준다', sqlerrm); end;

  -- ── L20: 0115 §F's watchdog, re-derived for the two tables it was written in advance FOR ─────
  -- `0115:755` armed a `%access_log` wildcard specifically for this unbuilt ledger and suite 150
  -- mutation-tested it (M3d: a `profile_id → profiles ON DELETE SET DEFAULT` ledger reddens N6-2
  -- alone; M7: with the pre-2026-08-20 filters it scored FULLY GREEN with the hole open —
  -- *"Do not narrow these filters again"*). That watchdog is a do-block inside 0115, which ran
  -- before these tables existed, and `location_retention_log` does not match the wildcard at all.
  -- So the check is re-derived here, verbatim in shape, over both new tables.
  begin
    v_bad := '';
    -- ARM 2 — no retention table may make its survival depend on `profiles`/`auth.users` surviving
    select string_agg(conrelid::regclass::text || '.' || conname || ' -> '
                      || confrelid::regclass::text || ' [' || confdeltype::text || ']', ' ')
      into v_msg
      from pg_constraint
     where contype = 'f'
       and confdeltype in ('c','n','d')                       -- CASCADE | SET NULL | SET DEFAULT
       and conrelid::regclass::text in ('location_access_log','location_retention_log')
       and confrelid::regclass::text in ('profiles','auth.users');
    if v_msg is not null then v_bad := v_bad || ' 삭제에 딸려가는 FK: ' || v_msg; end if;

    -- ARM 1 — the recursive closure from what account deletion ACTUALLY deletes.
    -- ⚠ The root set is RE-DERIVED from `delete_my_account_tx`'s own `prosrc`, never copied. A
    -- copied list is a second thing to keep in sync, and it goes stale in the silent direction:
    -- 0115 adds a table to its delete list, this pin never hears about it, and the ledger becomes
    -- reachable with the suite green. An over-inclusive regex (it also matches table names inside
    -- that function's comments) makes the check STRICTER, which is the safe direction.
    select array_agg(distinct m[1]) into v_roots
      from pg_proc p
      cross join lateral regexp_matches(p.prosrc, 'delete\s+from\s+([a-z_][a-z0-9_]*)', 'g') m
     where p.proname = 'delete_my_account_tx';
    if v_roots is null or array_length(v_roots, 1) < 10 then
      v_bad := v_bad || ' delete_my_account_tx의 삭제 목록을 prosrc에서 유도하지 못했다 — 이 팔은 침묵하지 않고 붉어진다';
    else
      with recursive edge as (
        select confrelid::regclass::text as parent, conrelid::regclass::text as child
          from pg_constraint where contype='f' and confdeltype in ('c','n','d')
      ), closure(t, path) as (
        select r, r from unnest(v_roots || array['auth.users']) r
        union
        select e.child, c.path || ' > ' || e.child
          from closure c join edge e on e.parent = c.t
         where position(' ' || e.child || ' ' in ' ' || c.path || ' ') = 0
      )
      select string_agg(distinct t || ' (' || path || ')', ' ') into v_msg
        from closure where t in ('location_access_log','location_retention_log');
      if v_msg is not null then v_bad := v_bad || ' 계정 삭제가 대장까지 닿는다: ' || v_msg; end if;
    end if;

    -- and the positive statement: every FK on both tables refuses the delete
    select count(*) into v_n from pg_constraint
     where contype='f' and conrelid::regclass::text in ('location_access_log','location_retention_log')
       and confdeltype not in ('a','r');
    if v_n <> 0 then v_bad := v_bad || ' ' || v_n || '개 FK가 삭제를 거절하지 않는다 (안전한 두 가지는 거절하는 두 가지뿐 — 0115의 자기 교정)'; end if;
    if v_bad = '' then
      call _pass('loc','L20 대장은 계정 삭제로 사라질 수 없다 — 0115 §F가 이 테이블이 태어나기 전에 겨눠 둔 %access_log 와일드카드를 여기서 재유도한다(그 do-block은 이미 실행됐고, location_retention_log는 와일드카드에 걸리지도 않는다). 두 팔 모두 통과하고, 두 테이블의 모든 FK가 NO ACTION이다: 캐스케이드로 지워질 수 있는 확인자료는 확인자료가 아니다');
    else v_msg := v_bad; call _fail('loc','L20 대장은 계정 삭제로 사라질 수 없다', v_msg); end if;
  exception when others then call _fail('loc','L20 대장은 계정 삭제로 사라질 수 없다', sqlerrm); end;

  -- ── L21: both tables are sealed from client roles, by privilege AND by RLS ───────────────────
  -- ⚠ The write arms assert on the SURVIVING ROW COUNT, not on "an exception was raised". Both
  -- refusals are legitimate here — the grant is gone AND RLS has no policy — but they fail
  -- differently: a privilege refusal raises, while an RLS-with-no-policy DELETE quietly affects
  -- zero rows and raises nothing. A pin written against the exception alone would go falsely RED
  -- the day the seal changed hands from the ACL to RLS, which is a real and reasonable future edit.
  begin
    v_bad := '';
    select count(*) into v_n from location_access_log;
    select count(*) into v_n2 from location_retention_log;
    foreach v_msg in array array['anon','authenticated'] loop
      perform set_config('request.jwt.claim.sub', r1::text, true);
      execute 'set local role ' || v_msg;
      begin execute 'select count(*) from location_access_log';
        v_bad := v_bad || ' ' || v_msg || ' 이(가) 대장을 읽었다'; exception when insufficient_privilege then null; end;
      begin execute 'select count(*) from location_retention_log';
        v_bad := v_bad || ' ' || v_msg || ' 이(가) 파기 기록을 읽었다'; exception when insufficient_privilege then null; end;
      begin execute format('insert into location_access_log (run_id, subject_profile_id, viewer_profile_id, viewer_relation, access_kind, point_count) values (%L,%L,%L,''subject'',''run_trace_read'',1)', run_read, r1, r1);
      exception when others then null; end;
      begin execute 'delete from location_access_log';
      exception when others then null; end;
      begin execute 'delete from location_retention_log';
      exception when others then null; end;
      execute 'reset role';
    end loop;
    if (select count(*) from location_access_log) <> v_n then
      v_bad := v_bad || ' 클라이언트 역할이 대장의 행 수를 바꿨다 — 위조하거나 지울 수 있는 확인자료는 확인자료가 아니다'; end if;
    if (select count(*) from location_retention_log) <> v_n2 then
      v_bad := v_bad || ' 클라이언트 역할이 파기 기록의 행 수를 바꿨다'; end if;
    -- RLS on, zero policies — the 0049 seal, and 0095's lesson is that RLS-off looks identical in a
    -- listing, so both facts are asserted rather than one
    select count(*) into v_n from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname in ('location_access_log','location_retention_log')
       and c.relrowsecurity;
    if v_n <> 2 then v_bad := v_bad || ' RLS가 켜진 새 테이블이 ' || v_n || '/2개다 (0095: RLS 꺼진 테이블은 pg_policies에 0행이라 형제들과 구별되지 않는다)'; end if;
    select count(*) into v_n from pg_policies
     where schemaname='public' and tablename in ('location_access_log','location_retention_log');
    if v_n <> 0 then v_bad := v_bad || ' 정책이 ' || v_n || '개 생겼다 (0049 패턴은 정책 0 — 열람은 my_location_access_log 창구로만)'; end if;
    if v_bad = '' then
      call _pass('loc','L21 대장과 파기 기록은 클라이언트에게 봉인돼 있다 — anon·authenticated 모두 SELECT/INSERT/DELETE를 실행으로 거절당하고(권한), RLS는 켜져 있으며 정책은 0개다(0049 club_phone_access_log 패턴). 위조할 수 있는 확인자료는 확인자료가 아니고, 지울 수 있는 확인자료도 마찬가지다');
    else v_msg := v_bad; call _fail('loc','L21 대장과 파기 기록은 클라이언트에게 봉인돼 있다', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('loc','L21 대장과 파기 기록은 클라이언트에게 봉인돼 있다', sqlerrm); end;

  -- ── L8: the purge does not touch the ledger ─────────────────────────────────────────────────
  -- Runs last, after §B has written ledger rows, so it can assert survival rather than absence.
  begin
    v_bad := '';
    select count(*) into v_n from location_access_log where run_id = run_read;
    perform * from purge_expired_run_traces(500);
    select count(*) into v_n2 from location_access_log where run_id = run_read;
    if v_n2 <> v_n then v_bad := v_bad || ' 파기가 확인자료를 ' || (v_n - v_n2) || '행 가져갔다'; end if;
    select count(*) into v_n from location_retention_log where run_id in (run_old, run_null, run_extra);
    if v_n <> 3 then v_bad := v_bad || ' 재실행이 파기 기록을 중복·삭제했다 (' || v_n || '행)'; end if;
    if (select trace from runs where id = run_read) = '[]'::jsonb then
      v_bad := v_bad || ' 상한 안의 살아있는 런이 재실행에서 지워졌다'; end if;
    if v_bad = '' then
      call _pass('loc','L8 파기는 확인자료를 건드리지 않는다 — 제16조 대장의 보존 하한은 6개월이고 상한은 없다(확인자료는 위치정보 자체가 아니므로 시행령 제26조의2의 1년 상한 대상이 아니다). 재실행은 멱등이다: 이미 비운 행을 다시 세지도, 기록을 중복시키지도 않는다');
    else v_msg := v_bad; call _fail('loc','L8 파기는 확인자료를 건드리지 않는다', v_msg); end if;
  exception when others then call _fail('loc','L8 파기는 확인자료를 건드리지 않는다', sqlerrm); end;

exception when others then
  begin execute 'reset role'; exception when others then null; end;
  call _fail('loc','155 스위트 자체', sqlerrm);
end $$;
