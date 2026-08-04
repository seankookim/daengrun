-- ═══ 0055/0056 경화 스위트 — definer 전수 봉인 · 지명 거절 원장 ═══
-- 목적 둘:
--  (1) 0055 §2가 일괄로 건 `search_path = public, pg_temp`가 **지금 이 순간에도** 전부 걸려 있는지를
--      매 하네스 런에서 전수 검사한다. 0055 자신이 스스로 남긴 한계 — ALTER는 create or replace에
--      리셋된다 — 때문에 마이그레이션 파일 하나로는 지속 보증이 안 된다. 보증은 여기서 진다.
--  (2) 0056의 거절 원장이 세운 계약 4종을 못박는다: 뷰 제외(러너별)·멱등(복합 PK)·RLS 봉인(읽기만)·
--      직접 재지명 생존. 넷 중 하나라도 되돌아가면 "거절한 카드가 1초 뒤 다시 뜬다"(0056 §1)로 회귀한다.
-- 스타일: 95/96/97 선례 — definer/뷰 경로는 postgres 세션에서 auth.uid()(GUC 'request.jwt.claim.sub',
--   단수 claim)만 바꿔 호출하고, 실 RLS 경로는 `set local role authenticated` + 항상 reset role.
-- 이 스위트는 하네스 마지막에 돈다. 시드 부킹은 끝에서 expired로 닫는다(오픈 풀 오염 방지 — 80 선례).
set client_min_messages = warning;

do $$
declare
  oo uuid; dg uuid; rt uuid;
  rA uuid; rB uuid;                       -- rA = 거절하는 러너 · rB = 거절 안 한 대조군
  b2 uuid; b5 uuid; b7 uuid;              -- H2~H4용 · H5용 · H7용 (케이스 간 독립)
  v_n int; v_n2 int; v_n3 int; v_n4 int;
  v_bad text; v_state text; v_st text; v_uid uuid; v_err boolean;
  v_cols text[];
  -- 0042:19-44의 select 리스트 = 뷰 형상의 정본. 0056은 WHERE만 건드렸다고 주장한다 — 여기서 검증.
  v_exp_cols text[] := array['id','scheduled_at','km','pace_label','base_fare','distance_fare',
                             'addon_fare','route_id','route_name','dog_id','dog_name','breed',
                             'weight_kg','memo','photo_url','preferences','vaccinations'];
  v_t timestamptz := timestamptz '2026-09-20 10:00:00+09';   -- now() 무관 고정 시각 (97과 구간 분리)
begin
  -- ---------- 시드 ----------
  oo := t_user('hd_oo', 'owner'); dg := t_dog(oo, '경화견'); rt := t_route('경화 코스');
  rA := t_user('hd_rA', 'runner');            -- t_user는 certified로 만든다 (tier <> 'applicant')
  rB := t_user('hd_rB', 'runner');
  -- online은 기본 false다. rA만 켜고 rB는 끈 채로 둔다 — 뷰는 is_active_runner()(=tier 판정)만 보고
  -- online을 보지 않으므로, 이 비대칭이 유지된 채로 rB가 1행을 봐야 '뷰가 online을 안 본다'가 함께 핀된다.
  -- (온라인 여부는 runners_available_for(0054/0055)의 관심사지 오픈 풀 뷰의 관심사가 아니다.)
  update runners set online = true where profile_id = rA;
  b2 := t_av_booking(oo, dg, rt, null, v_t, 5.0, 'matching');
  b5 := t_av_booking(oo, dg, rt, null, v_t + interval '1 day', 5.0, 'matching');
  b7 := t_av_booking(oo, dg, rt, null, v_t + interval '2 days', 5.0, 'matching');

  -- ---------- [H1] 상시 불변: public의 definer 함수 전수 pg_temp 봉인 ----------
  -- 이 핀은 '0055가 돌았다'를 말하는 게 아니라 **'지금 이 순간 전부 봉인돼 있다'**를 단언한다.
  -- 차이가 중요한 이유: 0055의 ALTER는 이후 누가 그 함수를 create or replace 하는 순간 리셋된다
  -- (실측 확인 — create or replace가 proconfig를 CREATE문에 적힌 값으로 덮어쓴다). 즉 0057 이후
  -- 어떤 마이그레이션이든 definer 함수를 본문에 `set search_path = public, pg_temp` 없이 재정의하면
  -- 그 함수는 조용히 pg_temp 암묵 선탐색으로 돌아가고 — 호출자가 `create temp table bookings(...)`로
  -- 소유자 판정 테이블을 섀도잉해 definer 게이트를 통과할 수 있다(0054 적대 리뷰 P2 실증) — 여기서 터진다.
  -- 그러므로 새 definer 함수의 규칙은 '나중에 ALTER'가 아니라 **본문 헤더에 직접 쓴다**이다.
  -- prokind='f' 한정: definer 프로시저(prokind='p')는 현재 0개다. 생기면 0055의 sweep과 이 핀을
  -- 함께 확장할 것 — 프로시저도 같은 섀도잉에 똑같이 취약하다.
  begin
    select count(*),
           coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
      into v_n, v_bad
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f'
      and coalesce(array_to_string(p.proconfig, ','), '') not like '%pg_temp%';
    if v_n = 0
      then call _pass('hard','H1 definer 전수 봉인 — public의 security definer 함수 전부 search_path에 pg_temp');
    else call _fail('hard','H1 definer 전수 봉인',
                    '미봉인 ' || v_n || '개 (본문에 set search_path = public, pg_temp 누락): ' || left(v_bad, 400));
    end if;
  exception when others then call _fail('hard','H1 definer 전수 봉인', sqlerrm);
  end;

  -- ---------- [H2] 거절 제외 — 뷰는 '거절한 러너에게만' 그 부킹을 숨긴다 ----------
  -- 거절은 부킹을 죽이지 않는다(0056 §3): rA에게만 사라지고 rB에게는 그대로 오픈이어야 한다.
  -- 두 경로 모두 확인 — definer 뷰를 postgres 세션에서 부를 때와, 실제 앱처럼 authenticated 역할
  -- 아래서 부를 때. 뷰가 소유자 권한으로 기저 테이블을 읽으므로 booking_declines에 읽기 정책이
  -- 없어도 제외 술어는 동작해야 한다 — RLS가 제외를 무력화하면(0행 대신 1행) 여기서 터진다.
  begin
    insert into booking_declines (booking_id, runner_profile_id) values (b2, rA);
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from marketplace_open_requests where id = b2;      -- 거절자 → 0
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from marketplace_open_requests where id = b2;     -- 대조군 → 1
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rA::text, true);
      execute 'select count(*) from marketplace_open_requests where id = $1' into v_n3 using b2;
      perform set_config('request.jwt.claim.sub', rB::text, true);
      execute 'select count(*) from marketplace_open_requests where id = $1' into v_n4 using b2;
      reset role;
    exception when others then reset role; v_bad := 'RLS경로 예외:' || sqlerrm;
    end;
    if v_bad = '' and v_n = 0 and v_n2 = 1 and v_n3 = 0 and v_n4 = 1
      then call _pass('hard','H2 거절 제외(뷰) — 거절자 0행·타 러너 1행, authenticated 경로도 동일');
    else call _fail('hard','H2 거절 제외(뷰)',
                    'definer rA=' || coalesce(v_n::text,'∅') || ' rB=' || coalesce(v_n2::text,'∅')
                    || ' / authed rA=' || coalesce(v_n3::text,'∅') || ' rB=' || coalesce(v_n4::text,'∅')
                    || ' ' || v_bad); end if;
  exception when others then reset role; call _fail('hard','H2 거절 제외(뷰)', sqlerrm);
  end;

  -- ---------- [H3] 멱등 + 복합 PK — 연타·재시도·낡은 푸시가 원장을 오염시키지 않는다 ----------
  -- 0056은 "복합 PK가 곧 멱등성"이라 적었다. 두 방향을 다 핀한다: on conflict do nothing은 조용히
  -- 0행(엣지 fn이 쓰는 형태), 그 안전장치 없는 재삽입은 반드시 unique_violation으로 터진다.
  -- PK가 언젠가 (booking_id, runner_profile_id, declined_at)로 넓어지면 멱등이 깨지는데 —
  -- 그때 뷰 제외는 여전히 동작하므로 조용히 지나간다. 그래서 PK 자체를 따로 못박는다.
  begin
    insert into booking_declines (booking_id, runner_profile_id) values (b2, rA) on conflict do nothing;
    get diagnostics v_n = row_count;                                    -- 0이어야 함
    v_err := false;
    begin
      insert into booking_declines (booking_id, runner_profile_id) values (b2, rA);
    exception when unique_violation then v_err := true;
    end;
    select count(*) into v_n2 from booking_declines where booking_id = b2 and runner_profile_id = rA;
    if v_n = 0 and v_err and v_n2 = 1
      then call _pass('hard','H3 거절 멱등 — on conflict 재거절 0행 추가·무방비 재삽입은 unique_violation·원장 1행');
    else call _fail('hard','H3 거절 멱등',
                    'onconflict_rows=' || v_n || ' unique_violation=' || v_err || ' 원장=' || v_n2); end if;
  exception when others then call _fail('hard','H3 거절 멱등', sqlerrm);
  end;

  -- ---------- [H4] RLS 봉인 — 읽기는 본인 것만, 쓰기 문은 없다 ----------
  -- 봉인의 주체는 grant 부재가 아니라 **RLS**다: shim이 모사하는 Supabase default privileges가
  -- 신규 테이블에 authenticated 전권(a/r/w/d)을 자동으로 준다(00_shim:58, 실측 relacl 확인).
  -- 즉 INSERT 권한은 이미 있고, 막는 건 오직 '정책 없음' = 모든 행이 정책 위반이라는 사실이다.
  -- 여기서 INSERT가 통과하기 시작하면 임의 booking_id를 남의 이름으로 박제할 수 있게 되고,
  -- '거절 안 했는데 사라졌다'의 원인을 서버가 설명할 수 없어진다(0056 §4).
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rA::text, true);
      execute 'select count(*) from booking_declines where booking_id = $1' into v_n using b2;   -- 자기 행 1
      perform set_config('request.jwt.claim.sub', rB::text, true);
      execute 'select count(*) from booking_declines where booking_id = $1' into v_n2 using b2;  -- 남의 행 0
      begin
        execute 'insert into booking_declines (booking_id, runner_profile_id) values ($1, $2)'
          using b5, rB;
        v_bad := v_bad || 'INSERT가 통과함(쓰기 문 열림) ';
      exception when others then
        v_state := sqlstate;
        if v_state <> '42501' then v_bad := v_bad || 'INSERT 예외=' || v_state || '/' || sqlerrm || ' '; end if;
      end;
      reset role;
    exception when others then reset role; v_bad := v_bad || 'blk:' || sqlerrm;
    end;
    if v_bad = '' and v_n = 1 and v_n2 = 0
      then call _pass('hard','H4 RLS 봉인 — 자기 거절만 읽힘·타인 행 불가시·클라 INSERT는 정책 부재로 거부');
    else call _fail('hard','H4 RLS 봉인',
                    'self=' || coalesce(v_n::text,'∅') || ' other=' || coalesce(v_n2::text,'∅')
                    || ' ' || v_bad); end if;
  exception when others then reset role; call _fail('hard','H4 RLS 봉인', sqlerrm);
  end;

  -- ---------- [H5] 직접 재지명 생존 — 거절이 '보호자가 콕 집는 것'까지 막지는 않는다 ----------
  -- 0056의 의도적 비대칭(테이블 주석): request_runner는 booking_declines를 참조하지 않는다.
  -- 오픈 풀(내가 안 고른 일이 되돌아오는 것)과 직접 지명(보호자가 나를 지목하는 것)은 다른 사건이고,
  -- 후자까지 막으면 보호자가 러너 한 명의 한 번 거절로 그 러너를 영구히 잃는다.
  -- 여기서는 request_runner의 CAS(status='matching' 조건부 UPDATE)를 SQL 등가로 재현한다 —
  -- 거절 행이 있어도 1행이 갱신되어야 한다. 누가 '거절 존중'을 이유로 CAS에 not exists를 끼워 넣으면 터진다.
  begin
    insert into booking_declines (booking_id, runner_profile_id) values (b5, rA) on conflict do nothing;
    update bookings set runner_id = rA, status = 'runner_pending'
      where id = b5 and status = 'matching';
    get diagnostics v_n = row_count;
    select b.status::text, b.runner_id into v_st, v_uid from bookings b where b.id = b5;
    if v_n = 1 and v_st = 'runner_pending' and v_uid = rA
      then call _pass('hard','H5 직접 재지명 생존 — 거절 원장이 있어도 지명 CAS 1행 성공');
    else call _fail('hard','H5 직접 재지명',
                    'rows=' || v_n || ' status=' || coalesce(v_st,'∅')
                    || ' runner=' || coalesce(v_uid::text,'∅')); end if;
  exception when others then call _fail('hard','H5 직접 재지명', sqlerrm);
  end;

  -- ---------- [H6] 뷰 형상 불변 — 0056은 WHERE만 건드렸다 ----------
  -- create or replace view는 컬럼 집합을 못 바꾸지만, drop+create로 우회하면 바꿀 수 있다.
  -- 0042의 17개 컬럼을 이름·순서까지 그대로 핀한다(ordinal_position 비교). 초크포인트의 값은
  -- '화이트리스트'에 있고, 화이트리스트는 순서까지 고정돼야 클라의 위치 기반 소비도 안 깨진다.
  -- 민감 컬럼은 물리적 부재로 따로 못박는다 — 80 K5와 겹치지만 여기서 함께 보는 게 옳다:
  -- 이 스위트가 뷰를 재정의한 마이그레이션(0056)의 담당 스위트다.
  begin
    select array_agg(c.column_name::text order by c.ordinal_position) into v_cols
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'marketplace_open_requests';
    select count(*) into v_n from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'marketplace_open_requests'
      and c.column_name in ('owner_id','total_price','address_id','min_fare','runner_id',
                            'club_session_id','series_id','cancel_reason','notes_for_runner');
    if v_cols = v_exp_cols and v_n = 0
      then call _pass('hard','H6 뷰 형상 불변 — 0042의 17개 컬럼 이름·순서 동일·민감 컬럼 부재');
    else call _fail('hard','H6 뷰 형상',
                    'cols=' || coalesce(v_cols::text,'∅') || ' leaked=' || v_n); end if;
  exception when others then call _fail('hard','H6 뷰 형상', sqlerrm);
  end;

  -- ---------- [H7] 거절→재개방 e2e (SQL 등가) ----------
  -- 엣지 함수 transition-booking의 runner_decline은 하네스 밖이다. 그 함수가 하는 쓰기는 정확히
  -- 셋: (status='matching', runner_id=null) 되돌리기 + booking_declines 박제. 그 셋을 SQL로 재현해
  -- **부킹이 다시 오픈 상태가 되는 바로 그 순간** 거절자의 풀에는 안 뜨고 남의 풀에는 뜨는지를 본다.
  -- 0056 §1이 지목한 사고가 정확히 이 지점이다 — 되돌린 두 값이 곧 뷰의 술어라서, 제외 술어가
  -- 없으면 거절한 카드가 거절한 러너의 큐 맨 위로 즉시 복귀한다. 상태 전이도 실제 경로를 탄다
  -- (matching→runner_pending→matching, enforce_booking_transition 통과).
  begin
    update bookings set runner_id = rA, status = 'runner_pending'
      where id = b7 and status = 'matching';                        -- 지명 (request_runner 등가)
    update bookings set status = 'matching', runner_id = null
      where id = b7 and status = 'runner_pending' and runner_id = rA;   -- 거절 쓰기 ①
    get diagnostics v_n = row_count;
    insert into booking_declines (booking_id, runner_profile_id) values (b7, rA)
      on conflict do nothing;                                          -- 거절 쓰기 ②
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n2 from marketplace_open_requests where id = b7;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n3 from marketplace_open_requests where id = b7;
    select b.status::text into v_st from bookings b where b.id = b7;
    if v_n = 1 and v_st = 'matching' and v_n2 = 0 and v_n3 = 1
      then call _pass('hard','H7 거절→재개방 e2e — 오픈 복귀 부킹이 거절자 풀엔 0행·타 러너 풀엔 1행');
    else call _fail('hard','H7 거절→재개방 e2e',
                    'decline_upd=' || v_n || ' status=' || coalesce(v_st,'∅')
                    || ' rA=' || coalesce(v_n2::text,'∅') || ' rB=' || coalesce(v_n3::text,'∅')); end if;
  exception when others then call _fail('hard','H7 거절→재개방 e2e', sqlerrm);
  end;

  -- 시드 정리 — 오픈 풀 오염 방지 (80 선례). matching/runner_pending → expired는 허용 전이.
  update bookings set status = 'expired' where id in (b2, b5, b7);
end $$;
