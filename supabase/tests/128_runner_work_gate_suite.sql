-- ═══ 128 runner work-gate suite — 0092 pins (⑫: pay the runner, gate the next run) ═══
-- Sean, 2026-08-13, verbatim:
--   "for 12, pay the runner but dont let them make new runs until the dog is confirmed by
--    both sides."
--
-- What this suite pins, and the one sentence that shapes all of it: **the gate is DERIVED, so
-- the property to measure is not "a flag was written" but "the answer changes the instant the
-- stamps change, with no second write anywhere".** Every pin below is written to fail if someone
-- later "optimises" this into a `runners.work_gated` column — which is the shape ⑫'s own build
-- note proposed and 0092 §2 declines, because 0089's review removed exactly that shape (a cache
-- of a derivable) the same day.
--
-- ⚠ THE EXIT IS THE DOG, NOT THE INCIDENT. Sean said "until the DOG is confirmed by both sides".
--   That is 0083's `runner_confirmed_return_at` + `owner_confirmed_return_at` — shipped — not
--   ⑪'s unbuilt incident-verification machine. W1 pins that the exit is those two stamps, so a
--   future slice that re-points the gate at ⑪ reddens here rather than silently changing what
--   clears a suspension. (This suite exists partly because the assignment that reached the
--   building session asserted the opposite; the ruling's own words settled it.)
--
-- Style: sibling of 119/125 — `_pass('wkg',…)`/`_fail('wkg',…)`, one begin…exception per case,
--   `_fail` arguments pre-computed into v_msg (the 110 header law). Self-contained fixtures.
-- ⚠ No pin here asserts a money amount. W4's money claims are PRESENCE/ABSENCE only — the point
--   is that the gate does not touch the ledger, not what the ledger says.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   W1 ← 0092 §6: drop either stamp from the blocking predicate (`runner_confirmed_return_at is
--        null or owner_confirmed_return_at is null`) — one side's confirmation then clears the
--        gate alone, which is the one-sided conclusion 0089 spent a whole migration removing,
--        reappearing in a different room                                                → RED
--   W2 ← 0092 §6: collapse `waiting_on` to a constant (or drop the `exit` key) — the runner is
--        told to perform a confirmation they have already performed, and the gate becomes an
--        unexplained suspension, which ⑫'s memo names as its own defect class          → RED
--   W3 ← 0092 §6: drop `b.club_session_id is null` (clubs run their own custody machine and
--        would gate their runners twice), or drop the `status = 'active'` arm so a settled or
--        cancelled booking keeps gating forever                                          → RED
--   W4 ← 0092 §6: drop the `incident_review` arm — ⑫'s own case stops gating, which is the
--        entire ruling                                                                   → RED
--        · or make the gate write anything to `ledger_items`/`payments` — the ruling is "PAY
--          the runner", so a gate with a money side-effect is the design he rejected  → RED
--   W5 ← 0092 §6/§7: grant `_runner_work_gate_blocking` to authenticated (the helper takes an
--        arbitrary runner id, so it is a cross-runner read), or revoke `runner_work_gate` from
--        authenticated (the runner can no longer see why they are gated)                 → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13, from the worktree (the harness runs in
--     worktrees since this morning's socket fix — the "main checkout only" note some suites still
--     carry is a 103-byte path cap misread as a rule). Method: the revert applied to `0092` in
--     place, the WHOLE harness run (it drops and recreates the database every run, so a migration
--     edit fully re-applies — no `rm -rf .pgtest`, which corrupts a cluster if a postmaster is
--     still attached), then restored from a pristine copy and re-verified by md5 + a green run.
--     Pristine `0092` md5 `35baebd8bd0f6d3361f03631fcf86a9d`; green is **529/0**.
--       N1 the two-stamp predicate narrowed to the runner's stamp alone
--          (`and b.runner_confirmed_return_at is null`) → 527/2, red = [W1, W2]. W1's detail is
--          the whole ruling failing in one sentence: `러너 혼자 확인으로 게이트가 풀렸다 (자기
--          탭으로 새 러닝을 받는다)` — the runner frees themselves by their own tap, which is the
--          one-sided conclusion 0089 spent a migration removing, reappearing in another room.
--          W2's cascade is CORRECT: with the owner's stamp out of the predicate, `waiting_on`
--          can no longer name the outstanding side, so the legibility pin fails for the same
--          root cause. Named rather than engineered apart — they are two views of one predicate.
--       N2 the `incident_review` arm deleted → 528/1, red = [W4] alone — ⑫'s own case stops
--          gating, i.e. the ruling's subject stops being covered while every other pin stays
--          green. Exactly the shape a reviewer should be able to spot from the count.
--       N3 `and b.club_session_id is null` deleted → 528/1, red = [W3] alone, detail
--          `클럽 예약이 마켓 게이트를 걸었다` — a club runner gated twice for one dog by two
--          custody machines that do not know about each other.
--     W5 is NOT machine-proven as a primary. Its probe is a direct `has_function_privilege`
--     matrix with a positive control on both roles (the 116 C21 idiom, proven under that suite),
--     and it is named above with the single revert that would redden it. Recorded as inherited
--     rather than claimed as fresh.
set client_min_messages = warning;

-- ---------- suite-local helpers (self-contained: must not depend on 119/125 fixtures) ----------
-- A marketplace booking whose run has STOPPED — the 귀가 window 0083 opens. Stamps are applied
-- by the caller, because which stamps exist is the whole subject of this suite.
create or replace function t_wkg_stopped(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                         p_ago interval default interval '30 minutes')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, run_ended_at)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '2 hours', 5.0,
          9900, 15000, 0, 24900, 9900, now() - p_ago)
  returning id into v;
  insert into runs (booking_id, started_at, ended_at, actual_km, end_reason)
  values (v, now() - interval '2 hours', now() - p_ago, 3.2, 'completed');
  return v;
end $$;

do $$
declare
  oo uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  b1 uuid; b2 uuid; b3 uuid; v_club uuid; v_sess uuid;
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_pre int;
begin
  oo := t_user('wkg_oo', 'owner');
  rr := t_user('wkg_rr', 'runner'); rz := t_user('wkg_rz', 'runner');
  dg := t_dog(oo, '게이트견'); rt := t_route('게이트 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [W1] the gate opens on the stop and closes on the SECOND stamp — never the first
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The ruling's exact words are "confirmed by both sides", so the interesting case is the
  -- MIDDLE one: exactly one stamp present. Under a one-stamp predicate the runner walks free by
  -- their own tap alone — the self-serve shape 0089 removed from the return path, which would
  -- reappear here if this predicate were written loosely. Both orders are exercised, because a
  -- predicate can be wrong in only one of them.
  begin
    v_bad := '';
    -- ⓐ a clean runner is not gated
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 깨끗한 러너가 게이트됐다'; end if;

    -- ⓑ the run stops, nobody has confirmed → gated
    b1 := t_wkg_stopped(oo, dg, rt, rr);
    v_js := runner_work_gate(rr);
    if not coalesce((v_js->>'gated')::boolean, false) then v_bad := v_bad || ' 정지 후 미확인인데 게이트 안 됨'; end if;
    if (v_js->>'booking_id') is distinct from b1::text then v_bad := v_bad || ' 막는 예약을 지목하지 못했다'; end if;

    -- ⓒ RUNNER stamps alone → STILL gated (the self-serve arm)
    update bookings set runner_confirmed_return_at = now() where id = b1;
    v_js := runner_work_gate(rr);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' 러너 혼자 확인으로 게이트가 풀렸다 (자기 탭으로 새 러닝을 받는다)'; end if;

    -- ⓓ the OWNER's stamp lands → free, with NO other write anywhere (the derived property)
    update bookings set owner_confirmed_return_at = now() where id = b1;
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true)
      then v_bad := v_bad || ' 양측 확인 뒤에도 게이트가 남았다 (파생이 아니라 캐시라는 증거)'; end if;

    -- ⓔ the other order: OWNER first, then runner — a predicate can be wrong in one order only
    b2 := t_wkg_stopped(oo, dg, rt, rz);
    update bookings set owner_confirmed_return_at = now() where id = b2;
    v_js := runner_work_gate(rz);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' 보호자 혼자 확인으로 게이트가 풀렸다'; end if;
    update bookings set runner_confirmed_return_at = now() where id = b2;
    v_js := runner_work_gate(rz);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 반대 순서에서 게이트가 안 풀렸다'; end if;

    if v_bad = ''
      then call _pass('wkg','W1 출구는 개다 — 정지 후 미확인이면 게이트, 한쪽 도장만으로는 어느 순서에서도 안 풀리고, 두 번째 도장이 찍히는 순간 다른 어떤 쓰기도 없이 풀린다 (0083의 두 반환 도장이 곧 Sean이 말한 "both sides")');
    else v_msg := v_bad; call _fail('wkg','W1 출구는 개다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('wkg','W1 출구는 개다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [W2] the gate is LEGIBLE — it never asks a runner to redo what they already did
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⑫'s memo: a runner who does not know why they cannot accept work, or what clears it, is the
  -- same defect class as an ops alert whose remedy does not apply. The failure this pins is
  -- specific and would ship easily: a constant "인계를 확인해주세요" shown to a runner who HAS
  -- confirmed and is waiting on the owner. That is not merely unhelpful — it is false about the
  -- runner's own action, and it sends them to a button that will do nothing.
  begin
    v_bad := '';
    b3 := t_wkg_stopped(oo, dg, rt, rr);
    -- neither side
    v_js := runner_work_gate(rr);
    if (v_js->>'waiting_on') is distinct from 'both' then v_bad := v_bad || ' 양쪽 미확인인데 waiting_on=' || coalesce(v_js->>'waiting_on','∅'); end if;
    if (v_js->>'exit') is distinct from 'both_confirm_return' then v_bad := v_bad || ' 출구 이름이 틀렸다(both)=' || coalesce(v_js->>'exit','∅'); end if;
    if coalesce((v_js->>'runner_confirmed')::boolean, true) then v_bad := v_bad || ' runner_confirmed가 참'; end if;
    if coalesce((v_js->>'owner_confirmed')::boolean, true) then v_bad := v_bad || ' owner_confirmed가 참'; end if;
    -- 🔴 the runner has done their part — the gate must now point at the OWNER
    update bookings set runner_confirmed_return_at = now() where id = b3;
    v_js := runner_work_gate(rr);
    if (v_js->>'waiting_on') is distinct from 'owner'
      then v_bad := v_bad || ' 러너가 이미 확인했는데 waiting_on=' || coalesce(v_js->>'waiting_on','∅') || ' (이미 한 일을 또 하라고 말한다)'; end if;
    if (v_js->>'exit') is distinct from 'owner_confirm_return' then v_bad := v_bad || ' 출구가 보호자를 가리키지 않는다'; end if;
    if not coalesce((v_js->>'runner_confirmed')::boolean, false) then v_bad := v_bad || ' 러너 확인이 반영되지 않았다'; end if;
    -- and the mirror: the owner has confirmed, the runner has not
    update bookings set runner_confirmed_return_at = null, owner_confirmed_return_at = now() where id = b3;
    v_js := runner_work_gate(rr);
    if (v_js->>'waiting_on') is distinct from 'runner' then v_bad := v_bad || ' 러너 미확인인데 waiting_on=' || coalesce(v_js->>'waiting_on','∅'); end if;
    if (v_js->>'exit') is distinct from 'runner_confirm_return' then v_bad := v_bad || ' 출구가 러너를 가리키지 않는다'; end if;
    -- the blocking booking is named, so the client can route to THAT booking and not guess
    if (v_js->>'booking_id') is distinct from b3::text then v_bad := v_bad || ' 막는 예약 미지목'; end if;
    -- a clean runner gets no reason keys at all — absence is the honest shape for "not gated"
    v_js := runner_work_gate(rz);
    if v_js ? 'waiting_on' or v_js ? 'exit'
      then v_bad := v_bad || ' 게이트 안 된 러너에게 이유가 붙었다=' || v_js::text; end if;
    -- ⚠ hand the fixture back clean. This suite's pins share one runner, and the gate answers
    -- about the OLDEST blocking booking — so a pin that leaves one behind silently re-points a
    -- later pin at the wrong row. (Observed: W4 read W2's leftover and reported its status.)
    update bookings set runner_confirmed_return_at = now(), owner_confirmed_return_at = now()
     where id = b3;

    if v_bad = ''
      then call _pass('wkg','W2 게이트는 읽힌다 — waiting_on·exit·양쪽 도장 상태·막는 예약 id를 정확히 돌려주고, 이미 확인한 쪽에게 다시 확인하라고 말하지 않으며(양방향), 게이트 안 된 러너에게는 이유 키가 아예 없다');
    else v_msg := v_bad; call _fail('wkg','W2 게이트는 읽힌다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('wkg','W2 게이트는 읽힌다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [W3] scope — whose dog, whose booking, and which states
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- A gate that is too wide suspends innocent runners, which costs supply and is invisible until
  -- someone complains. Each arm here is a specific over-reach that a looser predicate produces.
  begin
    v_bad := '';
    -- ⓐ another runner's unreturned dog does not gate me
    b1 := t_wkg_stopped(oo, dg, rt, rz);
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true)
      then v_bad := v_bad || ' 남의 미반환 예약이 나를 게이트했다'; end if;
    -- and it DOES gate its own runner (positive control — else ⓐ passes vacuously)
    v_js := runner_work_gate(rz);
    if not coalesce((v_js->>'gated')::boolean, false) then v_bad := v_bad || ' 양성 대조 실패: 당사자가 안 막혔다'; end if;
    update bookings set runner_confirmed_return_at = now(), owner_confirmed_return_at = now() where id = b1;

    -- ⓑ a booking that never started a 귀가 (no run_ended_at) does not gate — that is the
    --    conflict guard's job, and gating here would turn "you didn't bring a dog home" into
    --    "you are busy", a different rule with different false positives (0092 §3)
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (oo, dg, rr, rt, 'active', now() - interval '30 minutes', 5.0, 9900, 15000, 0, 24900, 9900)
    returning id into b2;
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 러닝 중(미정지)인데 게이트됐다'; end if;
    update bookings set status = 'completed' where id = b2;

    -- ⓒ a CLUB booking does not gate — clubs run their own custody machine (0045/0069), and
    --    gating here would suspend a club runner twice for one dog
    insert into clubs (name, district) values ('게이트 클럽', '반포') returning id into v_club;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, oo, now() - interval '2 hours', '{"lat":37.51,"lng":127.01}'::jsonb)
    returning id into v_sess;
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare, run_ended_at, club_session_id)
    values (oo, dg, rr, rt, 'active', now() - interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
            now() - interval '30 minutes', v_sess)
    returning id into b3;
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 클럽 예약이 마켓 게이트를 걸었다'; end if;
    delete from bookings where id = b3;

    -- ⓓ a booking that LEFT the 귀가 window stops gating even with stamps missing — otherwise a
    --    cancelled or settled row gates its runner forever with no reachable exit
    b3 := t_wkg_stopped(oo, dg, rt, rr);
    v_js := runner_work_gate(rr);
    if not coalesce((v_js->>'gated')::boolean, false) then v_bad := v_bad || ' 정지 예약이 게이트를 안 걸었다'; end if;
    update bookings set status = 'completed' where id = b3;
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true)
      then v_bad := v_bad || ' completed로 나간 예약이 영구 게이트로 남았다 (탈출 불가)'; end if;

    -- ⓔ 🔴 THE CAPACITY GAP (run-end plan §4): the accept path's conflict guard uses the NOMINAL
    --    window (km*8+25min ≈ 65min here). A 귀가 that outlives the estimate slips past it. This
    --    gate is unconditional on wall-clock, so an ancient unreturned dog still gates.
    b1 := t_wkg_stopped(oo, dg, rt, rz, interval '9 hours');
    v_js := runner_work_gate(rz);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' 예정 창을 한참 넘긴 미반환이 게이트를 안 걸었다 (용량 구멍)'; end if;
    update bookings set runner_confirmed_return_at = now(), owner_confirmed_return_at = now() where id = b1;

    if v_bad = ''
      then call _pass('wkg','W3 범위 — 남의 예약·러닝 중(미정지)·클럽 예약·귀가 창을 벗어난 예약은 게이트하지 않고(각각 양성 대조 포함), 예정 시간을 9시간 넘긴 미반환은 여전히 게이트한다 (충돌 가드의 명목 창이 못 잡는 용량 구멍)');
    else v_msg := v_bad; call _fail('wkg','W3 범위', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('wkg','W3 범위', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [W4] ⑫'s own case gates — and the gate never touches money
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The ruling is "PAY the runner but dont let them make new runs". Both halves are one pin
  -- because they are one sentence: an implementation that gated by withholding money would pass
  -- any test of the gate alone while being precisely the design Sean rejected.
  begin
    v_bad := '';
    b1 := t_wkg_stopped(oo, dg, rt, rr);
    select count(*) into v_pre from ledger_items where booking_id = b1;
    update bookings set status = 'incident_review' where id = b1;

    v_js := runner_work_gate(rr);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' incident_review인데 게이트 안 됨 (⑫ 본체가 안 걸린다)'; end if;
    -- name the row before reading its status: the gate answers about the OLDEST blocking
    -- booking, so asserting the status without pinning WHICH booking reads whatever a previous
    -- pin left behind and reports it as this pin's result.
    if (v_js->>'booking_id') is distinct from b1::text
      then v_bad := v_bad || ' 다른 예약을 지목했다 (앞 핀의 잔여물)=' || coalesce(v_js->>'booking_id','∅'); end if;
    if (v_js->>'status') is distinct from 'incident_review'
      then v_bad := v_bad || ' 상태 보고=' || coalesce(v_js->>'status','∅'); end if;

    -- the money side is untouched by asking the question, repeatedly
    perform runner_work_gate(rr); perform runner_work_gate(rr);
    select count(*) into v_n from ledger_items where booking_id = b1;
    if v_n <> v_pre then v_bad := v_bad || ' 게이트 조회가 원장을 바꿨다 ' || v_pre || '→' || v_n; end if;
    if exists (select 1 from payments where booking_id = b1)
      then v_bad := v_bad || ' 게이트가 결제 행을 만들었다'; end if;
    -- and nothing was written to `runners` either — the flag this design refuses (0092 §2)
    if (select count(*) from information_schema.columns
         where table_name = 'runners' and column_name in ('work_gated','gated_until','work_gate')) > 0
      then v_bad := v_bad || ' runners에 게이트 플래그 컬럼이 생겼다 (파생이어야 한다)'; end if;

    -- the exit still works from incident_review: both stamps free the runner even here, because
    -- the ruling's exit is the DOG coming home, not the case being closed
    update bookings set runner_confirmed_return_at = now(), owner_confirmed_return_at = now() where id = b1;
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true)
      then v_bad := v_bad || ' incident_review에서 양측 확인이 게이트를 못 풀었다 (출구 없는 정지)'; end if;

    if v_bad = ''
      then call _pass('wkg','W4 ⑫ 본체 — incident_review는 게이트되고 상태를 정직하게 보고하며, 게이트 조회는 원장·결제를 만들지 않고 runners에 플래그 컬럼도 없다("돈은 풀고 일을 막는다"), 그리고 케이스가 열린 채로도 양측 확인이면 러너는 풀린다 (출구는 개지 사건이 아니다)');
    else v_msg := v_bad; call _fail('wkg','W4 ⑫ 본체', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('wkg','W4 ⑫ 본체', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [W5] the grant matrix — a runner may read their own standing, not anyone else's
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the helper takes an ARBITRARY runner id and returns their booking ids — a cross-runner
    -- read, so it stays server-side. The gate itself is client-readable because ⑫'s legibility
    -- half is worthless if only the server can see the reason.
    if has_function_privilege('authenticated', '_runner_work_gate_blocking(uuid)', 'execute')
      then v_bad := v_bad || ' 헬퍼가 authenticated에 열렸다 (임의 러너의 예약을 읽는다)'; end if;
    if has_function_privilege('anon', '_runner_work_gate_blocking(uuid)', 'execute')
      then v_bad := v_bad || ' 헬퍼가 anon에 열렸다'; end if;
    if not has_function_privilege('service_role', '_runner_work_gate_blocking(uuid)', 'execute')
      then v_bad := v_bad || ' 헬퍼가 service_role에서 막혔다'; end if;
    if not has_function_privilege('authenticated', 'runner_work_gate(uuid)', 'execute')
      then v_bad := v_bad || ' 게이트가 클라에서 막혔다 (이유를 볼 수 없다)'; end if;
    if has_function_privilege('anon', 'runner_work_gate(uuid)', 'execute')
      then v_bad := v_bad || ' 게이트가 anon에 열렸다'; end if;
    -- both are definers with a pinned search_path (98 H1's law, asserted locally too)
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('runner_work_gate','_runner_work_gate_blocking')
           and p.prosecdef and 'search_path=public, pg_temp' = any(p.proconfig)) <> 2
      then v_bad := v_bad || ' definer/search_path 설정이 둘 다 갖춰지지 않았다'; end if;
    -- null in, named error out — never a silent "not gated", which would open the door
    begin
      perform runner_work_gate(null);
      v_bad := v_bad || ' null 러너가 통과했다';
    exception when others then
      if sqlerrm <> 'runner_required' then v_bad := v_bad || ' null 거부 사유=' || sqlerrm; end if;
    end;

    if v_bad = ''
      then call _pass('wkg','W5 권한 매트릭스 — 헬퍼는 service_role 전용(임의 러너 조회), 게이트는 authenticated에 열려 러너가 자기 사유를 읽을 수 있고 anon은 둘 다 거부, 둘 다 definer+search_path 고정, null 러너는 조용히 통과하지 않고 runner_required로 거부된다');
    else v_msg := v_bad; call _fail('wkg','W5 권한 매트릭스', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('wkg','W5 권한 매트릭스', v_msg);
  end;
end $$;
