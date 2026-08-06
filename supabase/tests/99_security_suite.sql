-- ═══ 0057 보안 경화 스위트 — 원격 P0 봉인의 상시 불변 핀 (audit-2026-08-05-server 워크리스트 4) ═══
-- 목적: 0057이 닫은 원격 악용 P0/K-급 구멍마다, **그 수정이 되돌려지면 빨간불이 되는** 핀을 건다.
--   0057은 적대 리뷰에서 공격 실증으로 닫혔지만(하네스 224/0), 마이그레이션 법(CLAUDE.md)은 새 보증마다
--   MUTATION 검증된 핀을 요구한다 — 되돌리면 FAIL 하는 핀만이 실제 방벽이다.
-- 스타일: 98 형제 그대로 — `_pass('sec',…)`/`_fail('sec',…)`, 각 케이스는 자체 begin…exception when others,
--   definer/역할 판정은 postgres 세션에서 `set local role` + `request.jwt.claim.sub`(auth.uid() 모사)로
--   구성하고 항상 reset role. S1은 98 H1의 형제 — 스키마 전수 불변(anon 실행권 0).
-- 이 스위트는 하네스 마지막(98 다음)에 돈다. 시드는 fresh uuid라 앞 스위트와 충돌하지 않고, 부킹은 전부
--   matching이 아닌 상태(confirmed/active/completed)라 오픈 풀(marketplace_open_requests, status='matching')을
--   오염시키지 않는다 — 별도 정리 불필요.
--
-- ─── MUTATION 검증 (2026-08-06, 스크래치 DB daengrun_sectest — daengrun_test 무손상) ────────────────
-- 각 핀을 되돌리는 특정 revert 하나로 스크래치에서 빨간불을 실측 확인했다. green→revert→RED→restore→green.
--   S1 ← grant execute on function session_proposal_respond(uuid,boolean,text) to anon      → RED
--   S2 ← drop trigger _guard_booking_cols on bookings                                         → RED
--   S3 ← drop trigger _guard_run_cols on runs                                                 → RED
--   S4 ← drop trigger _guard_runner_cols on runners                                           → RED
--   S5 ← drop trigger _guard_runner_doc_verify on runner_documents                            → RED
--   S6 ← grant execute on 4 클럽 RPC to anon (0057 §1 sweep 회귀)                             → RED
--   S7 ← grant execute on function grant_weekly_rewards() to anon, authenticated (§3 회귀)     → RED
-- 각 revert 제거(restore) 후 다시 green으로 복귀함도 확인. 초록으로 남는 무가치 핀은 없다.
set client_min_messages = warning;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  b_g uuid;                              -- S2: 살아있는 부킹(양측 당사자)
  b_done uuid; b_live uuid;             -- S3: 정산 완료 · 라이브
  doc uuid;
  v_n int; v_raised int; v_ok boolean; v_bad text;
  v_freeze boolean; v_prot boolean; v_live boolean;
  v_ins boolean; v_upd boolean; v_legit boolean;
  v_t timestamptz := timestamptz '2026-10-01 10:00:00+09';   -- now() 무관 고정 시각 (97/98과 구간 분리)
begin
  -- ---------- 시드 ----------
  oo := t_user('sec_oo', 'owner'); dg := t_dog(oo, '보안견'); rt := t_route('보안 코스');
  rr := t_user('sec_rr', 'runner');                         -- t_user는 tier='certified'로 만든다
  b_g    := t_av_booking(oo, dg, rt, rr, v_t,                     5.0, 'confirmed');  -- 양측 당사자 살아있음
  b_done := t_av_booking(oo, dg, rt, rr, v_t + interval '1 day',  5.0, 'completed');  -- 정산 종단
  b_live := t_av_booking(oo, dg, rt, rr, v_t + interval '2 days', 5.0, 'active');     -- 라이브
  -- runs 행: b_done은 종단(freeze 대상), b_live는 라이브. end_reason=null로 둬 dog-records 트리거 회피.
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, avg_pace_sec_per_km, end_reason, events)
    values (b_done, v_t, v_t + interval '40 min', 5.0, 2100, 420, null, '[]'::jsonb);
  insert into runs (booking_id, started_at, actual_km, events)
    values (b_live, v_t + interval '2 days', null, '[]'::jsonb);

  -- ---------- [S1] 스키마 전수 anon-execute 봉인 (98 H1의 형제) ----------
  -- 0057 §1 sweep이 세운 상시 불변: public의 어떤 security definer 함수도 anon으로 실행 불가.
  -- 이후 어떤 마이그레이션이 definer 함수를 anon에 재노출하면(create시 PUBLIC 기본 grant를 안 지우면)
  -- POST /rest/v1/rpc/<fn> 가 앱 번들의 공개 anon 키 소지자에게 그 함수를 다시 연다 — 여기서 터진다.
  begin
    select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute');
    if v_n = 0
      then call _pass('sec','S1 anon-execute 봉인 — public security definer 함수 중 anon 실행 가능 0개');
    else call _fail('sec','S1 anon-execute 봉인',
                    'anon 실행 가능 definer 함수 ' || v_n || '개 (0057 §1 sweep 회귀)'); end if;
  exception when others then call _fail('sec','S1 anon-execute 봉인', sqlerrm);
  end;

  -- ---------- [S2] bookings 돈·신원 컬럼 가드 (P0-1 + R1/R2) ----------
  -- 당사자(owner)로 로그인해 8개 보호 컬럼을 직접 쓰면 전부 booking_protected_columns로 거부돼야 한다.
  -- 양성 대조: 같은 당사자(같은 role=authenticated)가 비보호 컬럼(pace_label)을 쓰면 통과 — 가드가
  --   '전부 차단'이 아니라 '컬럼으로' 판별함을 증명한다(가드가 모든 authenticated UPDATE를 막으면 여기서 빨간불).
  begin
    declare
      stmts text[] := array[
        format($f$update bookings set addons = '[{"key":"river","price":2000000}]'::jsonb where id = %L$f$, b_g),
        format($f$update bookings set km = 40 where id = %L$f$, b_g),
        format($f$update bookings set min_fare = 3000000 where id = %L$f$, b_g),
        format($f$update bookings set total_price = 2400000 where id = %L$f$, b_g),
        format($f$update bookings set owner_id = %L where id = %L$f$, gen_random_uuid(), b_g),
        format($f$update bookings set owner_confirmed_handoff_at = now() where id = %L$f$, b_g),
        format($f$update bookings set runner_confirmed_handoff_at = now() where id = %L$f$, b_g),
        format($f$update bookings set scheduled_at = now() + interval '3 days' where id = %L$f$, b_g)
      ];
      s text;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      v_raised := 0; v_bad := '';
      foreach s in array stmts loop
        begin
          execute s; v_bad := v_bad || '[' || left(s, 44) || '→통과!] ';   -- 쓰기 성공 = 가드 실패
        exception when others then
          if sqlerrm like '%booking_protected_columns%' then v_raised := v_raised + 1;
          else v_bad := v_bad || '[' || sqlstate || ':' || left(sqlerrm, 40) || '] '; end if;
        end;
      end loop;
      -- 양성 대조: 비보호 컬럼은 같은 당사자 쓰기가 통과
      v_ok := false;
      begin
        execute format($f$update bookings set pace_label = 'sec-pos' where id = %L$f$, b_g);
        get diagnostics v_n = row_count; v_ok := (v_n = 1);
      exception when others then v_bad := v_bad || '[pos:' || left(sqlerrm, 40) || '] '; end;
      reset role;
      if v_raised = array_length(stmts, 1) and v_ok and v_bad = ''
        then call _pass('sec','S2 bookings 컬럼 가드 — 보호 8종 클라 쓰기 거부·비보호 pace_label 통과');
      else call _fail('sec','S2 bookings 컬럼 가드',
                      'raised=' || v_raised || '/' || array_length(stmts, 1)
                      || ' pos=' || v_ok || ' ' || v_bad); end if;
    end;
  exception when others then reset role; call _fail('sec','S2 bookings 컬럼 가드', sqlerrm);
  end;

  -- ---------- [S3] runs 정산 후 동결 + 컬럼 가드 (P1-6) ----------
  -- 러너 당사자로: (a) 정산 완료(completed) 부킹의 run을 쓰면 run_frozen_after_settlement로 거부.
  --   (b) 라이브(active) run의 actual_km 쓰기는 run_protected_columns로 거부하되 (c) events append는 통과 —
  --   라이브 기록 표면(events/photos/trace)은 살아있어야 한다.
  begin
    v_freeze := false; v_prot := false; v_live := false; v_bad := '';
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', rr::text, true);
    -- (a) 정산 후 동결
    begin
      execute format($f$update runs set actual_km = 900 where booking_id = %L$f$, b_done);
      v_bad := v_bad || '[freeze→통과!] ';
    exception when others then
      if sqlerrm like '%run_frozen_after_settlement%' then v_freeze := true;
      else v_bad := v_bad || '[freeze:' || left(sqlerrm, 44) || '] '; end if;
    end;
    -- (b) 라이브 보호 컬럼 거부
    begin
      execute format($f$update runs set actual_km = 900 where booking_id = %L$f$, b_live);
      v_bad := v_bad || '[prot→통과!] ';
    exception when others then
      if sqlerrm like '%run_protected_columns%' then v_prot := true;
      else v_bad := v_bad || '[prot:' || left(sqlerrm, 44) || '] '; end if;
    end;
    -- (c) 라이브 append 표면 생존
    begin
      execute format($f$update runs set events = '[{"kind":"poop"}]'::jsonb where booking_id = %L$f$, b_live);
      get diagnostics v_n = row_count; v_live := (v_n = 1);
    exception when others then v_bad := v_bad || '[events:' || left(sqlerrm, 44) || '] '; end;
    reset role;
    if v_freeze and v_prot and v_live and v_bad = ''
      then call _pass('sec','S3 runs 동결·컬럼 가드 — 정산 후 freeze·라이브 actual_km 거부·events append 통과');
    else call _fail('sec','S3 runs 동결·컬럼 가드',
                    'freeze=' || v_freeze || ' prot=' || v_prot || ' events=' || v_live || ' ' || v_bad); end if;
  exception when others then reset role; call _fail('sec','S3 runs 동결·컬럼 가드', sqlerrm);
  end;

  -- ---------- [S4] runners 거버넌스 (K-1) ----------
  -- 러너 본인 행: tier/commission_rate/total_runs 직접 쓰기는 runner_protected_columns로 거부.
  --   양성 대조: 스토어프런트 컬럼(bio/online/photos)은 통과 — 가드가 컬럼으로 판별함을 증명.
  begin
    declare
      stmts text[] := array[
        format($f$update runners set tier = 'master' where profile_id = %L$f$, rr),
        format($f$update runners set commission_rate = 0 where profile_id = %L$f$, rr),
        format($f$update runners set total_runs = 9999 where profile_id = %L$f$, rr)
      ];
      s text;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rr::text, true);
      v_raised := 0; v_bad := '';
      foreach s in array stmts loop
        begin
          execute s; v_bad := v_bad || '[' || left(s, 44) || '→통과!] ';
        exception when others then
          if sqlerrm like '%runner_protected_columns%' then v_raised := v_raised + 1;
          else v_bad := v_bad || '[' || sqlstate || ':' || left(sqlerrm, 40) || '] '; end if;
        end;
      end loop;
      v_ok := false;
      begin
        execute format($f$update runners set bio = '달리기 좋아요', online = true, photos = array['p1.jpg']
                        where profile_id = %L$f$, rr);
        get diagnostics v_n = row_count; v_ok := (v_n = 1);
      exception when others then v_bad := v_bad || '[pos:' || left(sqlerrm, 40) || '] '; end;
      reset role;
      if v_raised = array_length(stmts, 1) and v_ok and v_bad = ''
        then call _pass('sec','S4 runners 거버넌스 — tier/commission_rate/total_runs 거부·bio/online/photos 통과');
      else call _fail('sec','S4 runners 거버넌스',
                      'raised=' || v_raised || '/' || array_length(stmts, 1)
                      || ' pos=' || v_ok || ' ' || v_bad); end if;
    end;
  exception when others then reset role; call _fail('sec','S4 runners 거버넌스', sqlerrm);
  end;

  -- ---------- [S5] runner_documents 자가검증 차단 (K-2) ----------
  -- 클라가 verified_at을 세팅해 스스로 검증 통과처럼 위장하는 걸 막는다. INSERT(즉시 위장)·UPDATE(사후
  --   위장) 둘 다 거부, verified_at=null 정상 업로드는 통과.
  begin
    v_legit := false; v_ins := false; v_upd := false; v_bad := ''; doc := null;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', rr::text, true);
    -- (c) 정상 업로드(verified_at null) — (b)의 대상 행도 만든다
    begin
      execute format($f$insert into runner_documents (runner_id, kind, storage_path)
                      values (%L, 'id_card', 'docs/x.jpg') returning id$f$, rr) into doc;
      v_legit := (doc is not null);
    exception when others then v_bad := v_bad || '[legit:' || left(sqlerrm, 44) || '] '; end;
    -- (a) verified_at 세팅 INSERT 거부
    begin
      execute format($f$insert into runner_documents (runner_id, kind, storage_path, verified_at)
                      values (%L, 'id_card', 'docs/y.jpg', now())$f$, rr);
      v_bad := v_bad || '[ins-verified→통과!] ';
    exception when others then
      if sqlerrm like '%runner_doc_verify_server_only%' then v_ins := true;
      else v_bad := v_bad || '[ins:' || left(sqlerrm, 44) || '] '; end if;
    end;
    -- (b) verified_at 세팅 UPDATE 거부
    if doc is not null then
      begin
        execute format($f$update runner_documents set verified_at = now() where id = %L$f$, doc);
        v_bad := v_bad || '[upd-verified→통과!] ';
      exception when others then
        if sqlerrm like '%runner_doc_verify_server_only%' then v_upd := true;
        else v_bad := v_bad || '[upd:' || left(sqlerrm, 44) || '] '; end if;
      end;
    end if;
    reset role;
    if v_legit and v_ins and v_upd and v_bad = ''
      then call _pass('sec','S5 runner_documents 자가검증 차단 — verified_at insert/update 거부·null insert 통과');
    else call _fail('sec','S5 runner_documents 자가검증 차단',
                    'legit=' || v_legit || ' ins=' || v_ins || ' upd=' || v_upd || ' ' || v_bad); end if;
  exception when others then reset role; call _fail('sec','S5 runner_documents 자가검증 차단', sqlerrm);
  end;

  -- ---------- [S6] anon 클럽 RPC 봉인 (P0-3 belt-a = §1 sweep) ----------
  -- anon 역할로 클럽 definer RPC 4종 호출 → 본문 진입 전에 permission denied(42501). 되돌아가면(anon 재노출)
  --   본문이 돌아 not_signed_in(P0001)이 뜨거나 그냥 실행돼 42501이 안 나온다 — 어느 쪽이든 빨간불.
  begin
    declare
      calls text[] := array[
        $c$select session_proposal_respond(gen_random_uuid(), true)$c$,
        $c$select session_assignment_revoke(gen_random_uuid())$c$,
        $c$select session_cancel_delegation(gen_random_uuid())$c$,
        $c$select session_transfer_initiate(gen_random_uuid(), 'runner')$c$
      ];
      c text;
    begin
      set local role anon;
      perform set_config('request.jwt.claim.sub', '', true);   -- auth.uid() = null 확정
      v_raised := 0; v_bad := '';
      foreach c in array calls loop
        begin
          execute c; v_bad := v_bad || '[' || left(c, 40) || '→실행됨!] ';
        exception when others then
          if sqlstate = '42501' then v_raised := v_raised + 1;
          else v_bad := v_bad || '[' || left(c, 30) || ':' || sqlstate || '] '; end if;
        end;
      end loop;
      reset role;
      if v_raised = array_length(calls, 1) and v_bad = ''
        then call _pass('sec','S6 anon 클럽 RPC 봉인 — 4종 전부 permission denied(42501)');
      else call _fail('sec','S6 anon 클럽 RPC 봉인',
                      'denied=' || v_raised || '/' || array_length(calls, 1) || ' ' || v_bad); end if;
    end;
  exception when others then reset role; call _fail('sec','S6 anon 클럽 RPC 봉인', sqlerrm);
  end;

  -- ---------- [S7] 배치/디버그 봉인 (P1-4) ----------
  -- grant_weekly_rewards()는 크론/service-role 전용. anon도 authenticated도 permission denied여야 한다
  --   (anon은 무제한 하이 포인트 발행이 가능했다 — 감사 a11).
  begin
    v_raised := 0; v_bad := '';
    -- anon
    begin
      set local role anon;
      begin
        execute $c$select grant_weekly_rewards()$c$; v_bad := v_bad || '[anon→실행됨!] ';
      exception when others then
        if sqlstate = '42501' then v_raised := v_raised + 1;
        else v_bad := v_bad || '[anon:' || sqlstate || '] '; end if;
      end;
      reset role;
    exception when others then reset role; v_bad := v_bad || '[anon-blk:' || left(sqlerrm, 30) || '] '; end;
    -- authenticated
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rr::text, true);
      begin
        execute $c$select grant_weekly_rewards()$c$; v_bad := v_bad || '[authed→실행됨!] ';
      exception when others then
        if sqlstate = '42501' then v_raised := v_raised + 1;
        else v_bad := v_bad || '[authed:' || sqlstate || '] '; end if;
      end;
      reset role;
    exception when others then reset role; v_bad := v_bad || '[authed-blk:' || left(sqlerrm, 30) || '] '; end;
    if v_raised = 2 and v_bad = ''
      then call _pass('sec','S7 배치/디버그 봉인 — grant_weekly_rewards anon·authenticated 둘 다 permission denied');
    else call _fail('sec','S7 배치/디버그 봉인', 'denied=' || v_raised || '/2 ' || v_bad); end if;
  exception when others then reset role; call _fail('sec','S7 배치/디버그 봉인', sqlerrm);
  end;
end $$;
