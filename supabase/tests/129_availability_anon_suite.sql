-- ═══ 129 availability anon suite — 0093 pins (the schedule half of the who/where/when join) ═══
-- A1-A2 = the wall. A3 = the door that must stay open or 러너 프로필 dies. A4 = the honest
-- statement of what is NOT closed. A5 = the join itself, which is the thing that made this a
-- finding rather than a note.
--
-- Style: sibling of 124 — `_pass('rav',…)`/`_fail('rav',…)`, one begin…exception per case,
--   `set local role` + `request.jwt.claim.sub` for every client path, ALWAYS `reset role`.
--   ⚠ Clearing `request.jwt.claim.sub` before `set local role anon` is MANDATORY, not tidiness.
--     `set local role anon` changes the role but leaves the claim set by earlier suites, so
--     `auth.uid()` keeps returning a real user and any policy gated inside a function still
--     passes. That produced six false positives in 124 and nearly blinded that pin.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert ───
--   A1 ← 0093: delete `revoke select … from anon`                                        → RED
--   A2 ← 0093: as A1 (the join becomes reachable again)                                  → RED
--   A3 ← 0093: `revoke select … from authenticated` — over-tightening kills the storefront → RED
--   A5 ← 0093: as A1
--
-- ⚠ A3 IS THE POINT OF THIS FILE AS MUCH AS A1. The obvious "real" fix is to drop
--   `avail rules public read` (0002:77) since `using (true)` is the defect. That ALSO cuts the
--   authenticated storefront read, which is a feature — 보호자 sees a runner's weekly hours on
--   `runner-profile/[id]`. A grant revoke removes the stranger without removing the feature.
--   If A3 reddens, someone deleted the policy: restore the policy, do not delete this pin.
do $$
declare
  rr uuid; oo uuid;
  v_n int; v_msg text; v_named int;
begin
  -- ---------- seed: a runner with a published week, and an unrelated logged-in owner ----------
  rr := t_user('rav_rr', 'runner');          -- t_user makes tier='certified'
  oo := t_user('rav_oo', 'owner');           -- the snooper, no relationship to rr

  insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
  values (rr, 1, 360, 1200), (rr, 3, 420, 1080), (rr, 5, 360, 1320);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- A1 — a stranger reads nothing. The whole finding in one arm.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);   -- BE a stranger, do not merely say so
    execute 'set local role anon';
    begin
      execute 'select count(*) from runner_availability_rules' into v_n;
      reset role;
      v_msg := format('anon이 %s행을 읽었다 — 계정 없이 러너 주간 스케줄 노출', v_n);
      call _fail('rav', 'A1 anon 스케줄 차단', v_msg);
    exception when insufficient_privilege then
      reset role;
      call _pass('rav', 'A1 anon 스케줄 차단 — 계정 없는 조회는 permission denied (0002:77의 using(true)는 그대로지만 GRANT가 없다)');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- A2 — the filtered form too. A whitelist that only blocks `select *` is not a wall; the
  -- interesting query was always "this one runner's week", not "everyone's".
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute format('select count(*) from runner_availability_rules where runner_id = %L', rr) into v_n;
      reset role;
      call _fail('rav', 'A2 anon 지목 조회 차단', format('anon이 특정 러너를 지목해 %s행을 읽었다', v_n));
    exception when insufficient_privilege then
      reset role;
      call _pass('rav', 'A2 anon 지목 조회 차단 — runner_id를 알아도 그 사람의 요일·시간대는 안 나온다');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- A3 — THE DOOR. 러너 프로필(authenticated)은 그대로 살아 있어야 한다.
  -- 과잉 차단은 유출만큼 확실한 실패다 — 다른 점은 유출은 조용하고 이건 시끄럽다는 것뿐이다.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', oo::text, true);
    execute 'set local role authenticated';
    execute format('select count(*) from runner_availability_rules where runner_id = %L', rr) into v_n;
    reset role;
    if v_n = 3 then
      call _pass('rav', 'A3 스토어프런트 생존 — 로그인한 보호자는 러너 주간시간 3행을 그대로 본다 (api.ts:1898 fetchRunnerProfile)');
    else
      v_msg := format('로그인 사용자가 %s행 (기대 3) — 정책을 지웠거나 grant를 과잉 회수했다', v_n);
      call _fail('rav', 'A3 스토어프런트 생존', v_msg);
    end if;
  exception when insufficient_privilege then
    reset role;
    call _fail('rav', 'A3 스토어프런트 생존',
      'authenticated가 permission denied — 0093가 과잉 차단했거나 누군가 avail rules public read를 지웠다. 러너 프로필 화면이 죽는다');
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- A4 — WHAT IS STILL OPEN, pinned as a FACT so it cannot be mistaken for closed.
  -- 로그인한 아무나가 전체 러너의 스케줄을 대량으로 읽을 수 있다. 이 핀은 그게 '아직 그렇다'를
  -- 주장한다 — 고쳐지면 이 핀이 빨개지고, 그때 이 핀을 지우면서 §C를 함께 지우는 게 맞다.
  -- (그 전까지, 닫혔다고 착각한 사람이 이 파일을 읽고 사실을 알게 하는 것이 목적이다.)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ 이 블록에 exception 핸들러가 있어야 하는 이유는 뮤테이션이 가르쳐줬다. 없을 때
  -- `revoke select … from authenticated`를 걸면 여기서 미처리 에러가 나고, DO 블록 전체가
  -- 하나의 문장이므로 **A1~A3가 기록한 행까지 통째로 롤백된다** — 핀 하나가 빨개지는 대신
  -- 스위트가 통째로 사라진다. 하네스는 여전히 시끄럽게 실패하지만(SUITE PARSE/EXEC FAILED),
  -- 무엇이 왜 깨졌는지는 말해주지 않는다. 벌크 경로가 닫히는 날은 반드시 오므로, 그날
  -- 이 핀은 '스위트 폭발'이 아니라 '이 핀 하나 빨강 + 무엇을 갱신하라'로 답해야 한다.
  begin
    perform set_config('request.jwt.claim.sub', oo::text, true);
    execute 'set local role authenticated';
    begin
      execute 'select count(distinct runner_id) from runner_availability_rules' into v_n;
      reset role;
      if v_n >= 1 then
        call _pass('rav', format('A4 남은 노출을 사실로 고정 — 로그인만 하면 러너 %s명의 스케줄을 대량 조회 가능 (0002:77 using(true)). 0093는 무계정 경우만 닫는다', v_n));
      else
        call _fail('rav', 'A4 남은 노출을 사실로 고정',
          '대량 조회가 0명 — 누군가 벌크 경로를 닫았다면 좋은 일이다. 0093 §C와 이 핀을 함께 갱신하라');
      end if;
    exception when insufficient_privilege then
      reset role;
      call _fail('rav', 'A4 남은 노출을 사실로 고정',
        'authenticated가 permission denied — 벌크 노출이 닫혔거나(축하한다) grant가 과잉 회수됐다. 어느 쪽이든 0093 §C와 이 핀을 같이 갱신하라. A3도 함께 빨간지 확인할 것: 둘 다 빨강이면 과잉 회수, A4만 빨강이면 벌크만 닫힌 것이다');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- A5 — THE JOIN. 이게 이 슬라이스가 존재하는 이유다: 스케줄 단독도, 이름 단독도 아니고
  -- 둘이 붙는 것이 위험이다. anon이 이름을 얻는 경로(available_runners)는 일부러 열어두므로,
  -- 조인이 끊겼다는 것은 스케줄 쪽이 끊겼다는 뜻이어야 한다.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute 'select count(*) from available_runners av
                 join runner_availability_rules ar on ar.runner_id = av.profile_id' into v_named;
      reset role;
      call _fail('rav', 'A5 이름×시간 조인 차단',
        format('anon이 이름과 주간 스케줄을 %s쌍 붙였다 — 누가·어디서·언제 혼자 나가는지', v_named));
    exception when insufficient_privilege then
      reset role;
      call _pass('rav', 'A5 이름×시간 조인 차단 — available_runners(이름·동네)는 계속 공개지만 시간이 빠져 조인이 성립하지 않는다');
    end;
  end;

  reset role;
end $$;
