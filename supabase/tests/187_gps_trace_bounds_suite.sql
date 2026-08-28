-- ═══ 187: a trace cannot run into the future, and coverage decides zero vs unknown (0156) ═══
--                                                              — 0156-G1~0156-G7
-- 🔴 THE DEFECT THIS OWNS MOVES MONEY TODAY AND IS NOT BEHIND ANY FLAG.
--    The assigned runner supplies every coordinate AND timestamp (`api.ts:4307` →
--    `club_save_run_trace`, granted to `authenticated`, `t` in epoch SECONDS). Ingest validated
--    only monotonicity and ≤8 m/s; derivation took every point with `t >= started_at` and had NO
--    upper bound. A plausible slow trace dated hours ahead froze 99 km into a 5 km booking and the
--    payout path wrote it to `ledger_items`.
--
-- ⚠ THE CONTROLS ARE THE POINT OF THIS SUITE, AND G5 IS THE ONE THAT MATTERS MOST.
--   0152/suite 183 establish the distinction: 「measured 0 km」 is a REAL answer (a stationary dog)
--   and must survive; 「never measured」 must be NULL. A guard that refused both would satisfy every
--   refusal pin here perfectly and be the same defect with the opposite sign. So:
--     G3/G4 are the refusals · **G2/G5 are the positive controls** · name the failure each is
--     blind to and the lists differ, which is what makes them a genuine pair rather than one
--     assertion printed twice.
--
-- ⚠ Every arm asserts an EXACT boolean (`is distinct from` / explicit compare), never a bare `IF`.
--   plpgsql does not take an `IF` on a NULL predicate, so a bare `if <expr>` is SILENT precisely
--   when the thing under test returned NULL — which is the state half these pins exist to detect.
-- ⚠ G6/G7 strip comments before matching `prosrc` and carry NO-SOURCE arms: 0156 documents both
--   guards at length, and an un-stripped check for CALLING something is satisfied by a comment
--   EXPLAINING it. Absence must be loud or every arm above goes vacuously green.

set client_min_messages = warning;
do $$
declare
  uu uuid;
  v_bad text := ''; v_msg text; v_km numeric; v_err text; v_now numeric;
  tr jsonb;
begin
  uu := t_user('gps_rr', 'runner');
  perform set_config('request.jwt.claim.sub', uu::text, false);
  v_now := extract(epoch from now());

  -- ── 0156-G1: a trace dated far in the future is REFUSED at ingest ──
  -- The bound sits before the booking loop on purpose, so this pin needs no session fixture:
  -- the refusal must fire on the DATA, independently of whether a run exists to attach it to.
  v_err := '';
  begin
    perform club_save_run_trace(
      gen_random_uuid(),
      jsonb_build_array(
        jsonb_build_object('t', v_now + 7200, 'lat', 37.5100, 'lng', 127.0100),
        jsonb_build_object('t', v_now + 7260, 'lat', 37.5104, 'lng', 127.0104)));
  exception when others then v_err := SQLERRM;
  end;
  v_msg := 'err=' || coalesce(nullif(v_err,''), '(none)');
  if (v_err ~ 'trace_future_fix') is not true then
    call _fail('gps','0156-G1 미래 시각 트레이스는 수집 단계에서 거부된다', v_msg);
  else
    call _pass('gps','0156-G1 미래 시각 트레이스는 수집 단계에서 거부된다');
  end if;

  -- ── 0156-G2 CONTROL (over-reach): an ORDINARY present-dated trace is still accepted ──
  -- Blind to: a bound so tight it refuses real uploads. G1 cannot see that failure; this can.
  -- No active booking exists for this random session, so the function returns 0 rows updated —
  -- the assertion is that it does NOT RAISE.
  v_err := '';
  begin
    perform club_save_run_trace(
      gen_random_uuid(),
      jsonb_build_array(
        jsonb_build_object('t', v_now - 600, 'lat', 37.5100, 'lng', 127.0100),
        jsonb_build_object('t', v_now - 540, 'lat', 37.5104, 'lng', 127.0104)));
  exception when others then v_err := SQLERRM;
  end;
  v_msg := 'err=' || coalesce(nullif(v_err,''), '(none)');
  if v_err <> '' then
    call _fail('gps','0156-G2 통제: 평범한 현재 시각 트레이스는 그대로 받아들인다', v_msg);
  else
    call _pass('gps','0156-G2 통제: 평범한 현재 시각 트레이스는 그대로 받아들인다');
  end if;

  -- ── 0156-G3: derivation does NOT count points dated after the tap ──
  -- Two real fixes in the last minutes, then a long fabricated tail running into the future.
  -- Under the old rule the tail was billable distance; under the new one the window closes at
  -- now(). Asserted as an EQUALITY against the same trace without the tail, so the pin measures
  -- the exclusion rather than merely "some number came back".
  -- ⚠ THE FABRICATED TAIL IS DENSE ON PURPOSE, and the first version of this pin was wrong for it.
  -- With a sparse tail (one point an hour out) the COVERAGE gate refuses the whole trace and this
  -- arm reddens whether or not the upper bound exists — it would have been testing the fixture,
  -- not the rule. A real forger has no reason to leave holes: 60 s steps sail through coverage,
  -- so only the `now()` upper bound can exclude them. Now the two guards are separately observable.
  tr := jsonb_build_array(
          jsonb_build_object('t', v_now - 300, 'lat', 37.5100, 'lng', 127.0100),
          jsonb_build_object('t', v_now - 240, 'lat', 37.5109, 'lng', 127.0100),   -- ~100 m, real
          jsonb_build_object('t', v_now - 180, 'lat', 37.5109, 'lng', 127.0100),   -- real, still
          jsonb_build_object('t', v_now - 120, 'lat', 37.5109, 'lng', 127.0100),
          jsonb_build_object('t', v_now -  60, 'lat', 37.5109, 'lng', 127.0100),
          jsonb_build_object('t', v_now + 120, 'lat', 37.5113, 'lng', 127.0100),   -- fabricated
          jsonb_build_object('t', v_now + 180, 'lat', 37.5117, 'lng', 127.0100),   -- ~44 m/step,
          jsonb_build_object('t', v_now + 240, 'lat', 37.5121, 'lng', 127.0100),   -- ≤8 m/s, 60 s
          jsonb_build_object('t', v_now + 300, 'lat', 37.5125, 'lng', 127.0100));  -- gaps → passes
                                                                                   -- coverage
  -- ⚠ The tail starts at +120, not +60, and the reason is measured rather than stylistic: the
  -- derivation carries a deliberate 60 s tap grace (a fix a second after the tap is jitter, not
  -- fraud), so a point at exactly `now + 60` is legitimately INSIDE the window and counted. The
  -- first draft of this fixture put one there and the pin read 0.14 instead of 0.10 — the guard
  -- behaving exactly as specified, and the pin asserting a number that ignored its own spec.
  v_km := _club_derive_run_km(tr, to_timestamp(v_now - 360));
  v_msg := 'km with future tail=' || coalesce(v_km::text, 'NULL');
  -- the two in-window fixes are ~100 m apart → 0.10 km, and the tail must contribute nothing
  if v_km is distinct from 0.10 then
    call _fail('gps','0156-G3 탭 이후로 조작된 점은 거리로 계산되지 않는다', v_msg);
  else
    call _pass('gps','0156-G3 탭 이후로 조작된 점은 거리로 계산되지 않는다');
  end if;

  -- ── 0156-G4: two points separated by a hole wider than any real cadence are UNKNOWN, not 0 ──
  -- This is the shape codex found: identical endpoints hours apart accumulated nothing and
  -- returned 0.00, which the caller priced as a completed measured run.
  tr := jsonb_build_array(
          jsonb_build_object('t', v_now - 7200, 'lat', 37.5100, 'lng', 127.0100),
          jsonb_build_object('t', v_now - 60,   'lat', 37.5100, 'lng', 127.0100));
  v_km := _club_derive_run_km(tr, to_timestamp(v_now - 7260));
  v_msg := 'km for a 2-point trace with a ~2h hole=' || coalesce(v_km::text, 'NULL');
  if v_km is not null then
    call _fail('gps','0156-G4 샘플링 구멍이 크면 측정 없음(NULL)이지 0 km 가 아니다', v_msg);
  else
    call _pass('gps','0156-G4 샘플링 구멍이 크면 측정 없음(NULL)이지 0 km 가 아니다');
  end if;

  -- ── 0156-G5 CONTROL, THE ESSENTIAL ONE: a densely-sampled STATIONARY dog still measures 0.00 ──
  -- Blind to: a coverage rule that swallows honest zeroes. G4 cannot see that failure; this can.
  -- Without this arm, "return NULL whenever km = 0" would pass G4 and destroy 0152's distinction.
  tr := jsonb_build_array(
          jsonb_build_object('t', v_now - 240, 'lat', 37.5100, 'lng', 127.0100),
          jsonb_build_object('t', v_now - 180, 'lat', 37.5100, 'lng', 127.0100),
          jsonb_build_object('t', v_now - 120, 'lat', 37.5100, 'lng', 127.0100),
          jsonb_build_object('t', v_now - 60,  'lat', 37.5100, 'lng', 127.0100));
  v_km := _club_derive_run_km(tr, to_timestamp(v_now - 300));
  v_msg := 'km for a densely-sampled stationary dog=' || coalesce(v_km::text, 'NULL');
  if v_km is distinct from 0.00 then
    call _fail('gps','0156-G5 통제: 촘촘히 찍힌 정지 상태의 개는 여전히 측정된 0.00 이다', v_msg);
  else
    call _pass('gps','0156-G5 통제: 촘촘히 찍힌 정지 상태의 개는 여전히 측정된 0.00 이다');
  end if;

  -- ── 0156-G6: the two guards are present in the DEPLOYED bodies, comments stripped ──
  declare v_ing text; v_der text;
  begin
    select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_ing
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'club_save_run_trace';
    select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_der
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '_club_derive_run_km';
    v_bad := '';
    if v_ing is null then v_bad := v_bad || ' NO-SOURCE(club_save_run_trace)'; end if;
    if v_der is null then v_bad := v_bad || ' NO-SOURCE(_club_derive_run_km)'; end if;
    if (v_ing ~ 'trace_future_fix')  is not true then v_bad := v_bad || ' no-future-bound'; end if;
    if (v_der ~ 'c_max_gap_sec')     is not true then v_bad := v_bad || ' no-coverage-gate'; end if;
    v_msg := 'missing:' || v_bad;
    if v_bad <> '' then call _fail('gps','0156-G6 두 가드가 배포된 본문에 존재한다 (주석 제거 후)', v_msg);
                   else call _pass('gps','0156-G6 두 가드가 배포된 본문에 존재한다 (주석 제거 후)'); end if;
  end;

  -- ── 0156-G7: the ACL survived the recreation, both directions ──
  v_bad := '';
  if has_function_privilege('authenticated','public.club_save_run_trace(uuid, jsonb)','EXECUTE')
     is distinct from true then v_bad := v_bad || ' ingest-LOST-authenticated'; end if;
  if has_function_privilege('anon','public.club_save_run_trace(uuid, jsonb)','EXECUTE')
     is distinct from false then v_bad := v_bad || ' ingest-anon-executable'; end if;
  if has_function_privilege('authenticated','public._club_derive_run_km(jsonb, timestamptz)','EXECUTE')
     is distinct from false then v_bad := v_bad || ' derive-client-executable'; end if;
  v_msg := 'acl:' || v_bad;
  if v_bad <> '' then call _fail('gps','0156-G7 재생성 후에도 ACL 이 유지된다 (양방향)', v_msg);
                 else call _pass('gps','0156-G7 재생성 후에도 ACL 이 유지된다 (양방향)'); end if;
end $$;
