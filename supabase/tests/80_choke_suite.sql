-- ═══ 초크포인트(0042 R0B) 스위트 — 누수·당사자·화이트리스트·서비스롤 ═══
-- 실서비스 권한 모사(shim 기본 grant) 하에서 role 전환으로 실제 RLS 경로를 검증한다.
set client_min_messages = warning;

do $$
declare
  v_owner uuid; v_dog uuid; v_open uuid;          -- 일반 오픈 요청 (뷰에 보여야 함)
  v_runner uuid;                                   -- 인증 러너 (뷰 소비자)
  v_club_bid uuid; v_club_dog uuid;                -- 클럽 matching 부킹 (뷰·직접 모두 불가시)
  v_party_bid uuid; v_party_runner uuid;           -- 러너가 당사자인 부킹 (직접 읽기 유지 확인)
  v_cnt int; v_cnt2 int; v_err boolean;
begin
  -- ---------- 시드: 일반 오픈 요청 1건 + 기존 세계의 클럽 matching 부킹 재사용 ----------
  v_owner := t_user('chk_owner', 'owner');
  v_dog := t_dog(v_owner, '초크견');
  v_runner := t_user('chk_runner', 'runner');
  insert into bookings (owner_id, dog_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (v_owner, v_dog, 'matching', now() + interval '5 hours', 3.0, 9900, 9000, 0, 18900, 9900)
  returning id into v_open;
  select b.id, b.dog_id into v_club_bid, v_club_dog
  from bookings b where b.club_session_id is not null and b.status = 'matching' limit 1;
  select b.id, b.runner_id into v_party_bid, v_party_runner from bookings b
  where b.runner_id is not null and b.club_session_id is null limit 1;

  -- [K1] 뷰: 러너에게 일반 오픈 요청 보임 + 클럽 부킹 구조적 배제
  -- [0121] 오픈 풀의 클라이언트 창구가 marketplace_open_requests → runner_open_requests 로
  -- 이동했다 (요금 컬럼 없는 net 전용 뷰 — 계약 §D). 이 핀의 명제(초크포인트 뷰가 오픈 요청을
  -- 보이고 클럽 부킹을 구조적으로 배제한다)는 그대로이고, 그 명제가 사는 뷰가 바뀌었다.
  -- 구 뷰의 봉인 상태는 156 P6(c)가 소유한다.
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', v_runner::text, true);
    execute 'select count(*) from runner_open_requests where id = $1' into v_cnt using v_open;
    execute 'select count(*) from runner_open_requests where id = $1' into v_cnt2 using v_club_bid;
    reset role;
    if v_cnt = 1 and v_cnt2 = 0 and v_club_bid is not null
      then call _pass('chk','K1 뷰 — 일반 오픈 노출·클럽 부킹 배제');
    else call _fail('chk','K1 뷰','open=' || v_cnt || ' club=' || v_cnt2); end if;
  exception when others then reset role; call _fail('chk','K1 뷰', sqlerrm);
  end;

  -- [K2] 뷰: 비러너(보호자)는 항상 0행
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    -- [0121] K1과 같은 이동 — is_active_runner 게이트는 새 뷰가 그대로 상속한다.
    execute 'select count(*) from runner_open_requests' into v_cnt;
    reset role;
    if v_cnt = 0 then call _pass('chk','K2 뷰 — 비러너 0행 (is_active_runner 게이트)');
    else call _fail('chk','K2 비러너','rows=' || v_cnt); end if;
  exception when others then reset role; call _fail('chk','K2 비러너', sqlerrm);
  end;

  -- [K3] 직접 읽기: 광폭 정책 폐기 후 — 타인 오픈 부킹·클럽 부킹 불가시, 당사자 행은 유지
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', v_runner::text, true);
    execute 'select count(*) from bookings where id = $1' into v_cnt using v_open;        -- 타인 오픈
    execute 'select count(*) from bookings where id = $1' into v_cnt2 using v_club_bid;   -- 클럽
    reset role;
    if v_cnt = 0 and v_cnt2 = 0 then
      -- 당사자 접근 유지: v_party_bid의 러너로 전환
      -- 당사자 uid는 role 전환 '전에' 해석 (전환 후 서브쿼리는 RLS에 가려 NULL — 테스트 자체 버그 방지)
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', v_party_runner::text, true);
      execute 'select count(*) from bookings where id = $1' into v_cnt using v_party_bid;
      reset role;
      if v_cnt = 1 then call _pass('chk','K3 직접 읽기 — 타인·클럽 불가시, 당사자 유지');
      else call _fail('chk','K3 당사자','party=' || v_cnt); end if;
    else call _fail('chk','K3 직접','open=' || v_cnt || ' club=' || v_cnt2); end if;
  exception when others then reset role; call _fail('chk','K3 직접', sqlerrm);
  end;

  -- [K4] 강아지 누수: 클럽 부킹의 강아지는 무관 러너에게 불가시 (0004 dogs 정책 폐기 검증)
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', v_runner::text, true);
    execute 'select count(*) from dogs where id = $1' into v_cnt using v_club_dog;
    reset role;
    if v_cnt = 0 then call _pass('chk','K4 강아지 누수 차단 — 클럽견 무관 러너 불가시');
    else call _fail('chk','K4 강아지','rows=' || v_cnt); end if;
  exception when others then reset role; call _fail('chk','K4 강아지', sqlerrm);
  end;

  -- [K5] 화이트리스트: 민감 컬럼이 뷰에 물리적으로 없음
  begin
    select count(*) into v_cnt from information_schema.columns
    where table_schema = 'public' and table_name = 'marketplace_open_requests'
      and column_name in ('owner_id','address_id','total_price','min_fare','series_id',
                          'owner_confirmed_handoff_at','runner_confirmed_handoff_at','cancel_reason');
    if v_cnt = 0 then call _pass('chk','K5 화이트리스트 — 민감 컬럼 부재');
    else call _fail('chk','K5 화이트리스트','leaked=' || v_cnt); end if;
  end;

  -- [K6] 서비스롤 회귀 없음 (bypassrls) — 운영·엣지 함수 경로 유지
  begin
    set local role service_role;
    execute 'select count(*) from bookings where id = $1' into v_cnt using v_open;
    reset role;
    if v_cnt = 1 then call _pass('chk','K6 서비스롤 접근 유지');
    else call _fail('chk','K6 서비스롤','rows=' || v_cnt); end if;
  exception when others then reset role; call _fail('chk','K6 서비스롤', sqlerrm);
  end;

  -- 시드 정리 (오픈 풀 오염 방지 — 다른 스위트 카운트 보호)
  update bookings set status = 'expired' where id = v_open;
end $$;
