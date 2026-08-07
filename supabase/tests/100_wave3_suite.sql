-- ═══ 0060 웨이브 3 서버 정직 스위트 — 픽업 주소 RPC · 홀드 만료 · 도착 시각 ═══
-- 목적: 0060이 세운 세 계약마다, **그 보증이 되돌려지면 빨간불이 되는** 핀을 건다.
--   ① booking_pickup_address — 배정 러너에게만·진행 중이거나 24h 이내에만·게이트 코드는 절대 안 나간다.
--   ② 홀드 만료 — payment_hold도 만료되되 **알림은 없고**(청구된 적 없음), slot_holds 청소가 실제로 지운다.
--   ③ arrived_at — 서버 사실이고, CAS로 정확히 한 번이며, 클라 직접 쓰기는 여전히 막힌다.
-- 스타일: 97/98/99 형제 그대로 — `_pass('w3',…)`/`_fail('w3',…)`, 각 케이스는 자체 begin…exception
--   when others. definer RPC 경로는 postgres 세션에서 GUC(request.jwt.claim.sub = auth.uid())만 바꿔
--   호출하고, 실 RLS/역할 경로는 `set local role` + 항상 reset role. 헬퍼는 97의 t_av_booking 재사용
--   (이 스위트는 하네스 **마지막**에 돈다 — 97 이후이므로 헬퍼가 이미 존재한다).
-- 시각 배치: 상태 게이트가 now()와 무관한 fixture는 2026-10-20+ (95~99의 09-01/09-20/10-01 창과 분리).
--   **예외 — 계약이 now() 상대인 세 곳은 now() 기준일 수밖에 없다**: (a) confirmed 24h 창(W1 해피는
--   now()+2h, W3 음성은 now()+48h), (b) 30분 홀드 만료(created_at 기준), (c) slot_holds expires_at.
--   이 스위트 뒤에 도는 스위트가 없으므로(하네스 마지막) now() 근처 fixture가 남는 부작용은 없다.
-- 전역 부수효과 주의: W7은 expire_unmatched_bookings()를 **전역으로** 호출한다 — 앞 스위트가 남긴
--   만료 대상까지 함께 만료된다. 그래서 절대 개수가 아니라 호출 직전 사전 카운트와 비교한다
--   (반환값 = e_match + e_hold 합이라는 계약을 그 자체로 핀하는 형태).
--
-- ─── MUTATION 검증 (2026-08-07 · 전체 하네스 재실행 방식: 0060을 되돌려 RED → 복원 후 GREEN) ───
-- 각 핀은 아래의 **단일 revert 하나**로 빨간불이 된다. ✔ 표시는 이번 빌드에서 실제로 실행해 확인한 것.
--   W1  ← 게이트에서 `or (b.status='confirmed' and b.scheduled_at < now()+interval '24 hours')` 제거   → RED
--   W2  ← 게이트에서 `b.runner_id = auth.uid()` 연언 제거(존재 검사만 남김)                            → RED
--   W3  ← 게이트에서 상태 연언 전체 제거(러너 판정만 남김)                                             → RED
--   W4  ← 본문 앞에 `if (select address_id …) is null then raise exception 'not_runner'` 추가          → RED
--   W5  ← return query의 `and a.owner_id = b.owner_id` 제거                                  ✔ 실행 → RED
--   W6  ← returns table + select에 `gate_code_enc text` 추가                                 ✔ 실행 → RED
--   W7  ← e_hold CTE 삭제 + 반환을 `(select count(*) from e_match)`로 되돌림                 ✔ 실행 → RED
--   W8  ← purge_expired_holds의 delete에 `and booking_id is null` 복원                       ✔ 실행 → RED
--   W9  ← `alter table bookings add column arrived_at timestamptz;` 삭제                              → RED
--   W10 ← `grant execute on function purge_expired_holds() to authenticated;` 추가           ✔ 실행 → RED
--   W11 ← `drop trigger _guard_booking_cols on bookings;` (0057 §4 회귀)                              → RED
-- ✔ 다섯 건은 각각 **무손상 0060에 그 revert 하나만** 얹어 전체 하네스를 돌렸다 — 매번 245/1로,
--   붉어진 핀은 정확히 대상 하나뿐이었다(다른 245개 무영향 = 핀이 겨냥한 것만 겨냥한다는 증거).
--   복원 후 246/0 복귀도 확인. 초록으로 남는 무가치 핀은 없다.
set client_min_messages = warning;

do $$
declare
  oo uuid; zz uuid; rr uuid; dg uuid; rt uuid;
  ad_ok uuid; ad_bad uuid;                       -- 정상 주소(oo 소유) · 오염 주소(zz 소유)
  b_ok uuid; b_far uuid; b_done uuid;            -- 해피 · 24h 밖 confirmed · 종단(completed)
  b_noaddr uuid; b_poison uuid;                  -- 주소 미지정 · 소유자 불일치
  b_arr uuid; b_w11 uuid;                        -- W9 CAS 무대 · W11 트리거 비간섭 무대
  clb uuid; cs uuid;                             -- W7 클럽 무대 (클럽 홀드는 세션이 수명 소유)
  bh_solo uuid; bh_young uuid; bh_club uuid; bm uuid;
  h_exp uuid; h_null uuid; h_future uuid;        -- W8 슬롯 홀드 3종
  cx uuid;
  v_n int; v_n2 int; v_n3 int; v_cnt int; v_cnt2 int;
  v_pre_m int; v_pre_h int; v_noti_pre int;
  v_bad text; v_st text; v_stat text;
  v_label text; v_addr text; v_detail text;
  v_a boolean; v_b boolean; v_c boolean; v_d boolean;
  v_cols text[]; v_keys text[];
  v_exp_cols text[] := array['label', 'addr', 'detail'];
  v_flight text[] := array['runner_enroute', 'picked_up', 'active'];
  v_t timestamptz := timestamptz '2026-10-20 10:00:00+09';   -- now() 무관 fixture 창 (95~99와 분리)
begin
  -- ---------- 시드 ----------
  oo := t_user('w3_oo', 'owner'); zz := t_user('w3_zz', 'owner');
  rr := t_user('w3_rr', 'runner');
  dg := t_dog(oo, '정직견'); rt := t_route('정직 코스');
  -- gate_code_enc는 **일부러** 채운다 — W6의 누수 핀이 '값이 없어서 안 새는' false-green이 되지 않게.
  insert into addresses (owner_id, label, addr, detail, gate_code_enc)
    values (oo, '우리 집', '서울 성동구 왕십리로 83', '101동 1203호', 'ENC::절대노출금지')
    returning id into ad_ok;
  insert into addresses (owner_id, label, addr, detail, gate_code_enc)
    values (zz, '남의 집', '서울 강남구 테헤란로 1', '5층', 'ENC::남의것')
    returning id into ad_bad;

  b_ok     := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours',  5.0, 'confirmed');
  b_far    := t_av_booking(oo, dg, rt, rr, now() + interval '48 hours', 5.0, 'confirmed');
  b_done   := t_av_booking(oo, dg, rt, rr, v_t,                         5.0, 'completed');
  b_noaddr := t_av_booking(oo, dg, rt, rr, v_t + interval '1 day',      5.0, 'runner_enroute');
  b_poison := t_av_booking(oo, dg, rt, rr, v_t + interval '2 days',     5.0, 'runner_enroute');
  b_arr    := t_av_booking(oo, dg, rt, rr, v_t + interval '3 days',     5.0, 'runner_enroute');
  b_w11    := t_av_booking(oo, dg, rt, rr, v_t + interval '4 days',     5.0, 'runner_enroute');
  -- address_id 부여는 postgres 세션 UPDATE(가드 밖) · status를 SET에 안 넣으므로 전이 트리거 무발화
  update bookings set address_id = ad_ok  where id in (b_ok, b_far, b_done);
  update bookings set address_id = ad_bad where id = b_poison;   -- 오염: 주소 소유자 ≠ 부킹 소유자

  -- ---------- [W1] 픽업 주소 해피 — 배정 러너 + confirmed(24h 이내) ----------
  -- 계약의 양성면. 여기가 죽으면 러너 화면은 영원히 '주소는 채팅으로 물어보세요'로 남는다.
  -- fixture가 confirmed인 것이 요점이다: 24h 창 분기를 지우는 revert가 정확히 여기서 터진다
  -- (진행 중 3종만으로 해피를 세우면 그 분기는 아무 핀도 안 걸린 채 사라질 수 있다).
  begin
    perform set_config('request.jwt.claim.sub', rr::text, false);
    select count(*) into v_n from booking_pickup_address(b_ok);
    select x.label, x.addr, x.detail into v_label, v_addr, v_detail
      from booking_pickup_address(b_ok) x;
    if v_n = 1 and v_label = '우리 집' and v_addr = '서울 성동구 왕십리로 83'
       and v_detail = '101동 1203호'
      then call _pass('w3','W1 픽업 주소 해피 — 배정 러너·confirmed(24h 이내) → 1행, label/addr/detail 값 온전');
    else call _fail('w3','W1 픽업 주소 해피','rows=' || coalesce(v_n::text,'∅')
                    || ' label=' || coalesce(v_label,'∅') || ' addr=' || coalesce(v_addr,'∅')
                    || ' detail=' || coalesce(v_detail,'∅')); end if;
  exception when others then call _fail('w3','W1 픽업 주소 해피', sqlerrm);
  end;

  -- ---------- [W2] 권한 — 타인·부재 부킹·소유자·미인증은 not_runner, anon 역할은 실행 거부 ----------
  -- 97 V9의 형제. 다섯 경로가 **하나의 문자열**로 수렴해야 한다 — 부재와 타인이 구별되는 순간
  -- 임의 uuid를 훑어 '이 부킹은 존재한다'를 알아내는 열거 오라클이 된다(0054:73).
  begin
    v_bad := '';
    -- (a) 인증된 타인 (무관 보호자)
    perform set_config('request.jwt.claim.sub', zz::text, false);
    begin
      perform 1 from booking_pickup_address(b_ok); v_bad := v_bad || 'a:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || 'a:' || sqlerrm || ' '; end if;
    end;
    -- (b) 존재하지 않는 부킹 (부재와 타인은 구별 불가여야 한다)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform 1 from booking_pickup_address(gen_random_uuid()); v_bad := v_bad || 'b:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || 'b:' || sqlerrm || ' '; end if;
    end;
    -- (c) 부킹의 **소유자** (당사자지만 러너가 아니다 — 자기 주소라도 이 창구로는 안 준다)
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform 1 from booking_pickup_address(b_ok); v_bad := v_bad || 'c:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || 'c:' || sqlerrm || ' '; end if;
    end;
    -- (d) 미인증 (GUC 없음 → auth.uid() null → coalesce(...,false)가 술어를 접는다)
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      perform 1 from booking_pickup_address(b_ok); v_bad := v_bad || 'd:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || 'd:' || sqlerrm || ' '; end if;
    end;
    -- (e) anon 역할 — execute 권한 자체가 회수됨 (99 S1의 개별 케이스)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      set local role anon;
      perform 1 from booking_pickup_address(b_ok);
      reset role;
      v_bad := v_bad || 'e:예외없음 ';
    exception when others then
      reset role;
      if sqlerrm not like '%permission denied%' then v_bad := v_bad || 'e:' || sqlerrm || ' '; end if;
    end;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if v_bad = ''
      then call _pass('w3','W2 권한 — 타인·부재 부킹·부킹의 소유자·미인증 전부 not_runner·anon 역할 실행 거부');
    else call _fail('w3','W2 권한', v_bad); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', rr::text, false);
    call _fail('w3','W2 권한', sqlerrm);
  end;

  -- ---------- [W3] 상태·시간 게이트 — 진행 중 3종만 무조건 열리고, 종단·먼 confirmed는 닫힌다 ----------
  -- 0001:124의 '세션 중에만' 자세를 시간축으로 옮긴 것. 양성(3종)과 음성(completed·24h 밖 confirmed)을
  -- 같은 핀에 두는 이유: 상태 연언을 통째로 지우는 revert는 음성에서만, 3종 중 하나를 빠뜨리는 revert는
  -- 양성에서만 터진다 — 둘 다 같은 게이트 문장의 회귀다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    foreach v_st in array v_flight loop
      cx := t_av_booking(oo, dg, rt, rr, v_t + interval '10 days', 5.0, v_st::booking_status);
      update bookings set address_id = ad_ok where id = cx;
      begin
        select count(*) into v_n from booking_pickup_address(cx);
        if v_n <> 1 then v_bad := v_bad || v_st || ':rows=' || v_n || ' '; end if;
      exception when others then v_bad := v_bad || v_st || ':' || sqlerrm || ' ';
      end;
      delete from bookings where id = cx;
    end loop;
    begin
      perform 1 from booking_pickup_address(b_done); v_bad := v_bad || 'completed:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || 'completed:' || sqlerrm || ' '; end if;
    end;
    begin
      perform 1 from booking_pickup_address(b_far); v_bad := v_bad || 'confirmed+48h:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || 'confirmed+48h:' || sqlerrm || ' '; end if;
    end;
    if v_bad = ''
      then call _pass('w3','W3 상태·시간 게이트 — runner_enroute·picked_up·active 각 1행·completed와 24h 밖 confirmed는 not_runner');
    else call _fail('w3','W3 상태·시간 게이트', v_bad); end if;
  exception when others then call _fail('w3','W3 상태·시간 게이트', sqlerrm);
  end;

  -- ---------- [W4] 주소 미지정 → 0행 (오류가 아니다) ----------
  -- 오류와 빈 결과는 서로 다른 신호다: 클라는 전자를 '불러오지 못했어요(재시도)'로, 후자를 '미지정
  -- (채팅으로 물어보기)'로 렌더한다. 둘이 합쳐지면 러너는 영원히 재시도 버튼만 누른다.
  begin
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_bad := '';
    begin
      select count(*) into v_n from booking_pickup_address(b_noaddr);
    exception when others then v_bad := 'raise:' || sqlerrm; v_n := -1;
    end;
    if v_bad = '' and v_n = 0
      then call _pass('w3','W4 주소 미지정 — address_id null은 0행 반환(예외 아님)');
    else call _fail('w3','W4 주소 미지정','rows=' || coalesce(v_n::text,'∅') || ' ' || v_bad); end if;
  exception when others then call _fail('w3','W4 주소 미지정', sqlerrm);
  end;

  -- ---------- [W5] 오염 주소 (소유자 불일치) → 0행 ----------
  -- create-booking-hold가 소유권 검사를 갖기 전에 남의 address_id로 심어진 부킹(레거시 오염)이 있어도
  -- 그 주소는 읽히지 않는다 — RPC 내부 a.owner_id = b.owner_id 재검증이 두 번째 방벽이다.
  -- 이 핀이 죽으면 '아무 uuid나 address_id에 박은 부킹'이 남의 집 주소 조회기가 된다.
  begin
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_bad := '';
    begin
      select count(*) into v_n from booking_pickup_address(b_poison);
      select count(*) into v_n2 from booking_pickup_address(b_ok);   -- 대조군: 정상 주소는 여전히 1행
    exception when others then v_bad := 'raise:' || sqlerrm; v_n := -1;
    end;
    if v_bad = '' and v_n = 0 and v_n2 = 1
      then call _pass('w3','W5 오염 주소 — 주소 소유자 ≠ 부킹 소유자면 0행(대조군 정상 주소는 1행)');
    else call _fail('w3','W5 오염 주소','poison=' || coalesce(v_n::text,'∅')
                    || ' 대조군=' || coalesce(v_n2::text,'∅') || ' ' || v_bad); end if;
  exception when others then call _fail('w3','W5 오염 주소', sqlerrm);
  end;

  -- ---------- [W6] 반환 형상 + 누수 — 평면 3필드 정확히, gate_code_enc는 자리 자체가 없다 ----------
  -- 97 V10의 클론. 두 반쪽을 모두 본다:
  --  (1) 계약 표면 — proargnames(모드 't') = 선언된 반환 컬럼. 미래의 create or replace가 컬럼을 늘리면 여기.
  --  (2) 런타임 키 — 실제 행을 to_jsonb 한 키 집합. **W1 해피 fixture에 대고 돌린다**(0행이면
  --      to_jsonb가 NULL이 되어 단언이 조용히 무너진다 — V10 헤더가 지적한 바로 그 함정).
  -- 누수 정규식은 97의 것에 gate|code|enc|owner|phone을 더한 확장판이다. ad_ok에는 gate_code_enc가
  -- 실제로 채워져 있으므로(시드 참조) 이 핀은 '값이 없어서 안 샌다'가 아니라 '구조적으로 없다'를 본다.
  begin
    perform set_config('request.jwt.claim.sub', rr::text, false);
    select array_agg(a.n order by a.o) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(k order by k) into v_keys from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from booking_pickup_address(b_ok) x limit 1) s) t;
    select count(*) into v_n
    from unnest(coalesce(v_cols, '{}'::text[]) || coalesce(v_keys, '{}'::text[])) c
    where c ~* 'schedul|booking|owner|price|fare|status|club|address|dog|route|gate|code|enc|phone';
    if coalesce(array_length(v_cols, 1), 0) = 3 and v_cols @> v_exp_cols and v_exp_cols @> v_cols
       and coalesce(array_length(v_keys, 1), 0) = 3 and v_keys @> v_exp_cols and v_exp_cols @> v_keys
       and v_n = 0
      then call _pass('w3','W6 반환 형상·누수 — 선언 3컬럼 = 런타임 3키 = {label,addr,detail}, gate/code/enc/owner/phone 0');
    else call _fail('w3','W6 반환 형상·누수','proargnames=' || coalesce(v_cols::text,'∅')
                    || ' 런타임키=' || coalesce(v_keys::text,'∅')
                    || ' 누수=' || coalesce(v_n::text,'∅')); end if;
  exception when others then call _fail('w3','W6 반환 형상·누수', sqlerrm);
  end;

  -- ---------- [W7] 홀드 만료 두 클래스 — 만료는 하되 **환불 거짓말은 안 한다** ----------
  -- 네 개의 fixture가 각각 다른 revert를 잡는다:
  --   bh_solo(31분 · 클럽 아님)  → expired,  알림 0건   ← e_hold 삭제 / e_hold에 noti 결합
  --   bh_young(29분)            → payment_hold 유지     ← 30분 경계를 줄이는 회귀
  --   bh_club(31분 · 클럽 세션)  → payment_hold 유지     ← club_session_id is null 누락
  --   bm(matching · 시작 지남)   → expired + '매칭 만료' 1건 ← 기존 X1 클래스 불변(0017/0037)
  -- 반환값은 절대 개수가 아니라 **사전 카운트 합**과 비교한다 — 앞 스위트가 남긴 만료 대상이
  -- 함께 처리되기 때문이고, 동시에 '두 CTE의 합을 돌려준다'는 계약 자체를 핀하는 형태다
  -- (e_hold를 빼면 v_pre_h(≥1)만큼 어긋난다). now()는 트랜잭션 시작 시각이라 사전/사후가 같은 기준이다.
  begin
    insert into clubs (name, district, host_profile_id) values ('정직 클럽', '성수동', rr)
      returning id into clb;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
      values (clb, rr, now() + interval '5 days', '정직 집결지') returning id into cs;

    bh_solo  := t_av_booking(oo, dg, rt, null, now() + interval '5 days', 5.0, 'payment_hold');
    bh_young := t_av_booking(oo, dg, rt, null, now() + interval '5 days', 5.0, 'payment_hold');
    bh_club  := t_av_booking(oo, dg, rt, null, now() + interval '5 days', 5.0, 'payment_hold');
    bm       := t_av_booking(oo, dg, rt, null, now() - interval '1 hour', 5.0, 'matching');
    update bookings set created_at = now() - interval '31 minutes' where id in (bh_solo, bh_club);
    update bookings set created_at = now() - interval '29 minutes' where id = bh_young;
    update bookings set club_session_id = cs where id = bh_club;

    select count(*) into v_pre_m from bookings
      where status in ('matching', 'runner_pending') and scheduled_at < now() and club_session_id is null;
    select count(*) into v_pre_h from bookings
      where status = 'payment_hold' and created_at < now() - interval '30 minutes' and club_session_id is null;
    select count(*) into v_noti_pre from notifications where title = '매칭 만료';

    select expire_unmatched_bookings() into v_n;

    select count(*) into v_cnt  from notifications where ref_id in (bh_solo, bh_young, bh_club);
    select count(*) into v_cnt2 from notifications where ref_id = bm and title = '매칭 만료';
    select count(*) into v_n2   from notifications where title = '매칭 만료';
    v_a := (select b.status from bookings b where b.id = bh_solo)  = 'expired';
    v_b := (select b.status from bookings b where b.id = bh_young) = 'payment_hold';
    v_c := (select b.status from bookings b where b.id = bh_club)  = 'payment_hold';
    v_d := (select b.status from bookings b where b.id = bm)       = 'expired';

    if v_a and v_b and v_c and v_d and v_cnt = 0 and v_cnt2 = 1
       and v_pre_h >= 1 and v_pre_m >= 1 and v_n = v_pre_m + v_pre_h and (v_n2 - v_noti_pre) = v_pre_m
      then call _pass('w3','W7 홀드 만료 두 클래스 — 31분 홀드 expired·알림 0(환불 거짓말 없음)·29분 생존·클럽 홀드 불가침·matching 클래스 불변(반환값 = e_match+e_hold)');
    else call _fail('w3','W7 홀드 만료 두 클래스',
                    '31분=' || coalesce(v_a::text,'∅') || ' 29분생존=' || coalesce(v_b::text,'∅')
                    || ' 클럽생존=' || coalesce(v_c::text,'∅') || ' matching만료=' || coalesce(v_d::text,'∅')
                    || ' 홀드알림=' || coalesce(v_cnt::text,'∅') || ' 매칭알림=' || coalesce(v_cnt2::text,'∅')
                    || ' 반환=' || coalesce(v_n::text,'∅') || ' 기대=' || coalesce((v_pre_m + v_pre_h)::text,'∅')
                    || '(m=' || coalesce(v_pre_m::text,'∅') || ',h=' || coalesce(v_pre_h::text,'∅') || ')'
                    || ' 알림증가=' || coalesce((v_n2 - v_noti_pre)::text,'∅')); end if;
  exception when others then call _fail('w3','W7 홀드 만료 두 클래스', sqlerrm);
  end;

  -- ---------- [W8] 슬롯 홀드 청소 — booking_id를 단 홀드가 **실제로** 지워진다 ----------
  -- 0003의 `booking_id is null`은 이 함수를 영구 no-op으로 만들었다(실제 홀드는 전부 booking_id를 단다).
  -- h_null은 구 계약이 지우던 유일한 클래스 — 함께 지워져야 회귀가 아니다.
  -- h_future는 안전면: is_slot_available(0003:61)이 읽는 미래 만료 홀드를 청소가 건드리면 예약이 증발한다.
  begin
    insert into slot_holds (runner_id, owner_id, starts_at, ends_at, expires_at, booking_id)
      values (rr, oo, v_t, v_t + interval '1 hour', now() - interval '1 minute', b_ok)
      returning id into h_exp;
    insert into slot_holds (runner_id, owner_id, starts_at, ends_at, expires_at, booking_id)
      values (rr, oo, v_t, v_t + interval '1 hour', now() - interval '1 minute', null)
      returning id into h_null;
    insert into slot_holds (runner_id, owner_id, starts_at, ends_at, expires_at, booking_id)
      values (rr, oo, v_t, v_t + interval '1 hour', now() + interval '10 minutes', b_ok)
      returning id into h_future;
    select count(*) into v_pre_h from slot_holds where expires_at < now();
    select purge_expired_holds() into v_n;
    select count(*) into v_cnt from slot_holds where id = h_exp;
    select count(*) into v_cnt2 from slot_holds where id = h_null;
    select count(*) into v_n2 from slot_holds where id = h_future;
    if v_cnt = 0 and v_cnt2 = 0 and v_n2 = 1 and v_pre_h >= 2 and v_n = v_pre_h
      then call _pass('w3','W8 슬롯 홀드 청소 — booking_id 있는 만료 홀드 삭제·booking_id null 만료 홀드도 삭제·미래 만료 홀드 생존·반환 = 삭제 건수');
    else call _fail('w3','W8 슬롯 홀드 청소',
                    'booking홀드잔존=' || coalesce(v_cnt::text,'∅') || ' null홀드잔존=' || coalesce(v_cnt2::text,'∅')
                    || ' 미래홀드=' || coalesce(v_n2::text,'∅') || ' 반환=' || coalesce(v_n::text,'∅')
                    || ' 사전만료=' || coalesce(v_pre_h::text,'∅')); end if;
  exception when others then call _fail('w3','W8 슬롯 홀드 청소', sqlerrm);
  end;

  -- ---------- [W9] arrived_at CAS — 정확히 한 번, 알림도 한 번 ----------
  -- transition-booking `arrived` 액션의 SQL 등가. 두 번째 탭이 행을 못 무는 것이 **설계**다:
  -- 알림은 '행이 반환됐을 때만' 발화하므로 CAS가 곧 exactly-once 장치다(enroute 이중발화 버그 미복제).
  -- 클라 직접 쓰기는 여전히 booking_protected_columns — 신규 컬럼이 0058 deny-all에 자동 포섭됨을 함께 핀한다.
  begin
    update bookings set arrived_at = now()
      where id = b_arr and arrived_at is null and status = 'runner_enroute';
    get diagnostics v_n = row_count;
    if v_n = 1 then
      insert into notifications (profile_id, kind, title, body, ref_id)
        values (oo, 'booking', '러너 도착', '러너가 픽업 장소에 도착했어요 — 인계를 준비해주세요', b_arr);
    end if;
    update bookings set arrived_at = now()                       -- 재탭 (연타·재시도·낡은 푸시)
      where id = b_arr and arrived_at is null and status = 'runner_enroute';
    get diagnostics v_n2 = row_count;
    if v_n2 = 1 then                                             -- 여기 들어오면 알림이 두 번 간다
      insert into notifications (profile_id, kind, title, body, ref_id)
        values (oo, 'booking', '러너 도착', '러너가 픽업 장소에 도착했어요 — 인계를 준비해주세요', b_arr);
    end if;
    select count(*) into v_cnt from notifications where ref_id = b_arr and title = '러너 도착';
    v_a := (select b.arrived_at is not null from bookings b where b.id = b_arr);
    -- 주의: now()는 트랜잭션 시작 시각 상수라 이미 찍힌 스탬프와 **같은 값**이 된다 → 가드의
    -- `new is distinct from old`가 거짓이 되어 no-op으로 통과한다(실측). 실제 위조 시도를 모사하려면
    -- 반드시 다른 값을 써야 한다 — 여기서 now()를 쓰면 핀이 조용히 무너진다.
    v_b := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rr::text, true);
      execute format($f$update bookings set arrived_at = now() - interval '3 hours' where id = %L$f$, b_arr);
      reset role;
    exception when others then
      reset role;
      v_b := sqlerrm like '%booking_protected_columns%';
    end;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if v_n = 1 and v_n2 = 0 and v_cnt = 1 and v_a and v_b
      then call _pass('w3','W9 arrived_at CAS — 최초 1행·재탭 0행(알림 정확히 1건)·러너 직접 쓰기는 booking_protected_columns');
    else call _fail('w3','W9 arrived_at CAS',
                    '최초=' || coalesce(v_n::text,'∅') || ' 재탭=' || coalesce(v_n2::text,'∅')
                    || ' 알림=' || coalesce(v_cnt::text,'∅') || ' 스탬프=' || coalesce(v_a::text,'∅')
                    || ' 가드=' || coalesce(v_b::text,'∅')); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', rr::text, false);
    call _fail('w3','W9 arrived_at CAS', sqlerrm);
  end;

  -- ---------- [W10] 배치 함수 권한 보존 — create or replace가 ACL을 되살리지 않는다 ----------
  -- 0057 §3이 두 배치 함수를 세 역할 모두에서 회수했다. 0060은 둘 다 create or replace로 갈아끼운다 —
  -- replace는 ACL을 보존하지만 **drop + create**는 보존하지 않는다(PUBLIC 기본 grant가 되살아난다).
  -- 99 S1은 anon만 본다. 여기서 authenticated를 본다 — 미래의 drop+create 재부여를 잡는 자리다.
  -- 양성 대조로 신규 RPC의 authenticated 실행권을 함께 본다: has_function_privilege가 무조건 false를
  -- 돌려주는 게 아님을(즉 이 핀이 판별력을 갖는지를) 같은 호출로 증명한다.
  begin
    select has_function_privilege('authenticated', 'expire_unmatched_bookings()', 'execute') into v_a;
    select has_function_privilege('authenticated', 'purge_expired_holds()', 'execute') into v_b;
    select has_function_privilege('authenticated', 'booking_pickup_address(uuid)', 'execute') into v_c;
    if not v_a and not v_b and v_c
      then call _pass('w3','W10 배치 함수 권한 — expire_unmatched_bookings·purge_expired_holds는 authenticated 실행 불가(양성 대조: booking_pickup_address는 가능)');
    else call _fail('w3','W10 배치 함수 권한',
                    'expire=' || coalesce(v_a::text,'∅') || ' purge=' || coalesce(v_b::text,'∅')
                    || ' 대조군(pickup)=' || coalesce(v_c::text,'∅')); end if;
  exception when others then call _fail('w3','W10 배치 함수 권한', sqlerrm);
  end;

  -- ---------- [W11] 전이 트리거 비간섭 — arrived_at 단독 쓰기는 상태 머신을 지나지 않는다 ----------
  -- booking_transition은 `before update OF STATUS`다: SET 목록에 status가 없으면 발화하지 않는다.
  -- transition-booking의 `arrived` 액션이 '상태를 안 바꾸는 쓰기'로 설계된 근거가 정확히 이것이다.
  -- 양성 대조로 같은 문장에 status를 얹어 본다 — runner_enroute→completed는 허용 전이가 아니므로
  -- 트리거가 살아 있다면 반드시 터진다. 즉 위의 '무발화'가 '트리거가 죽어서'가 아님을 증명한다.
  -- 마지막으로 authenticated 경로: 서버 전용 컬럼이라는 사실을 클라 쪽에서 확인한다(0058 §3).
  begin
    update bookings set arrived_at = now() where id = b_w11;
    get diagnostics v_n = row_count;
    select b.status::text into v_stat from bookings b where b.id = b_w11;
    v_a := false;
    begin
      update bookings set arrived_at = now(), status = 'completed' where id = b_w11;
    exception when others then v_a := sqlerrm like '%invalid booking transition%';
    end;
    v_b := false;                                  -- W9와 같은 이유로 now()가 아닌 값을 쓴다(no-op 회피)
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute format($f$update bookings set arrived_at = now() - interval '3 hours' where id = %L$f$, b_w11);
      reset role;
    exception when others then
      reset role;
      v_b := sqlerrm like '%booking_protected_columns%';
    end;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if v_n = 1 and v_stat = 'runner_enroute' and v_a and v_b
      then call _pass('w3','W11 전이 트리거 비간섭 — postgres arrived_at 단독 쓰기 1행·상태 불변(양성 대조: status를 얹으면 invalid transition)·authenticated는 booking_protected_columns');
    else call _fail('w3','W11 전이 트리거 비간섭',
                    'rows=' || coalesce(v_n::text,'∅') || ' status=' || coalesce(v_stat,'∅')
                    || ' 양성대조=' || coalesce(v_a::text,'∅') || ' 가드=' || coalesce(v_b::text,'∅')); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', rr::text, false);
    call _fail('w3','W11 전이 트리거 비간섭', sqlerrm);
  end;

  -- 시드 정리 — 오픈 풀 오염 방지(80/98 선례). 이 스위트 뒤에 도는 스위트는 없지만 관례를 지킨다.
  update bookings set status = 'expired' where id = bh_young and status = 'payment_hold';
end $$;
