-- ═══ 0054 가용성 게이팅 스위트 — runners_available_for = 수락 게이트의 표시측 거울 핀 ═══
-- 목적: 0054가 세운 '거울' 계약을 하네스에 못박는다. 표시가 서버(transition-booking runner_accept)보다
--   엄격해지면(예: is_slot_available로 갈아끼움·runner_pending을 점유로 셈·휴식 버퍼 부활) 공급이 조용히
--   증발하고, 느슨해지면(예: LIVE 4종 확장 실패·경계 부등호 뒤집힘·분수 절삭) 죽은 지명이 남는다.
--   둘 다 여기서 터진다.
-- 스타일: 95/96 선례 — definer RPC는 postgres 세션에서 auth.uid()(GUC 'request.jwt.claim.sub')만 바꿔
--   호출하고, 역할 권한은 set local role anon + 항상 reset role.
-- 주의: 러너 노출 집합은 online 플래그로 통제한다(t_av_only_online) — limit 10 계약 때문에 케이스마다
--   무대에 올릴 러너를 명시적으로 고정해야 결정적이다. 이 스위트는 하네스 마지막에 돈다.
set client_min_messages = warning;

-- ---------- 스위트 전용 헬퍼 ----------
-- 임의 상태·시각·거리의 부킹 (insert는 전이 트리거를 타지 않는다 — 충돌 표본을 그대로 심는다)
create or replace function t_av_booking(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                        p_when timestamptz, p_km numeric, p_status booking_status)
returns uuid language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, p_status, p_when, p_km, 9900, 15000, 0, 24900, 9900)
  returning id
$$;

-- 무대 고정: 지정한 러너만 online, 나머지는 전부 offline
create or replace function t_av_only_online(variadic p_ids uuid[]) returns void
language sql as $$ update runners set online = (profile_id = any(p_ids)) $$;

-- 목록에 그 러너가 있나 (호출자 auth.uid()는 바깥 세션 GUC를 그대로 쓴다)
create or replace function t_av_has(p_booking uuid, p_runner uuid) returns boolean
language sql stable as $$
  select exists (select 1 from runners_available_for(p_booking) x where x.profile_id = p_runner)
$$;

-- 수락 게이트(TS)의 술어를 SQL로 그대로 재현 — ms 정수 산술 + 반열림 엄격 겹침.
-- (index.ts:41-54: aEnd = aStart + (km*8+25)*60_000 · cs < aEnd && ce > aStart)
create or replace function t_av_ts_conflict(p_target uuid, p_conflict uuid) returns boolean
language sql stable as $$
  select m.c_start < m.a_end and m.c_end > m.a_start
  from (
    select extract(epoch from t.scheduled_at) * 1000                                as a_start,
           extract(epoch from t.scheduled_at) * 1000 + (t.km * 8 + 25) * 60000      as a_end,
           extract(epoch from c.scheduled_at) * 1000                                as c_start,
           extract(epoch from c.scheduled_at) * 1000 + (c.km * 8 + 25) * 60000      as c_end
    from bookings t, bookings c where t.id = p_target and c.id = p_conflict
  ) m
$$;

do $$
declare
  oo uuid; zz uuid; dg uuid; rt uuid;
  r1 uuid; r7a uuid; r7b uuid; r8 uuid; r11 uuid;
  b1 uuid; b5 uuid; b6 uuid; b8 uuid; b11 uuid;
  cx uuid; cy uuid;
  v_t timestamptz := timestamptz '2026-09-01 10:00:00+09';    -- 대상 구간 기준시 (now() 무관 — 고정 산술)
  v_t6 timestamptz := timestamptz '2026-09-04 10:00:00+09';   -- 재지명 케이스 전용 (b1 구간과 무겹침)
  v_t8 timestamptz := timestamptz '2026-09-02 04:13:00+09';   -- 가용 규칙이 절대 안 덮는 새벽 시각
  v_t11 timestamptz := timestamptz '2026-09-03 15:00:00+09';
  v_pid uuid; v_name text; v_dist text; v_avatar text; v_tier text; v_bio text;
  v_pace int; v_runs int; v_resp int; v_n int;
  v_a boolean; v_b boolean; v_c boolean; v_d boolean;
  v_bad text; v_st text; v_pat text; v_err text;
  v_cols text[]; v_keys text[]; v_ids uuid[]; v_got uuid[]; v_exp uuid[];
  v_exp_cols text[] := array['profile_id','name','district','avatar_url','tier','bio',
                             'avg_pace_sec_per_km','total_runs','respond_rate_pct'];
  v_live text[] := array['confirmed','runner_enroute','picked_up','active'];
  v_idle text[] := array['runner_pending','matching','completed','cancelled_owner','cancelled_runner',
                         'expired','no_show','incident_review','refund_pending'];
  v_off text[] := array['-90 minutes','-65 minutes','-30 minutes','0 minutes',
                        '64 minutes 59 seconds','65 minutes'];
begin
  -- ---------- 시드 ----------
  oo := t_user('av_oo', 'owner'); dg := t_dog(oo, '가용견');
  zz := t_user('av_zz', 'owner');                       -- 무관 보호자 (프로빙 시도자)
  rt := t_route('가용 코스');
  r1 := t_user('av_r1', 'runner');
  update profiles set district = '성수동', avatar_url = 'https://cdn.test/av_r1.png' where id = r1;
  update runners set bio = '새벽 러닝 전문', avg_pace_sec_per_km = 410, total_runs = 7,
                     respond_rate_pct = 93 where profile_id = r1;
  r7a := t_user('av_r7a', 'runner'); update runners set tier = 'applicant' where profile_id = r7a;
  r7b := t_user('av_r7b', 'runner');                    -- certified지만 offline
  r8 := t_user('av_r8', 'runner');
  r11 := t_user('av_r11', 'runner');
  b1 := t_av_booking(oo, dg, rt, null, v_t, 5.0, 'matching');       -- 대상 부킹 (km 5.0 → 65분)
  b8 := t_av_booking(oo, dg, rt, null, v_t8, 5.0, 'matching');
  b11 := t_av_booking(oo, dg, rt, null, v_t11, 5.0, 'matching');
  perform set_config('request.jwt.claim.sub', oo::text, false);     -- 이하 전부 소유자 세션
  perform t_av_only_online(r1);

  -- ---------- [V1] 기본 노출 — 온라인·인증 러너가 9개 컬럼 그대로 ----------
  begin
    select count(*) into v_n from runners_available_for(b1);
    select x.profile_id, x.name, x.district, x.avatar_url, x.tier::text, x.bio,
           x.avg_pace_sec_per_km, x.total_runs, x.respond_rate_pct
      into v_pid, v_name, v_dist, v_avatar, v_tier, v_bio, v_pace, v_runs, v_resp
    from runners_available_for(b1) x where x.profile_id = r1;
    if v_n = 1 and v_pid = r1 and v_name = 'av_r1' and v_dist = '성수동'
       and v_avatar = 'https://cdn.test/av_r1.png' and v_tier = 'certified'
       and v_bio = '새벽 러닝 전문' and v_pace = 410 and v_runs = 7 and v_resp = 93
      then call _pass('avail','V1 기본 노출 — 온라인·certified 러너 1행·9개 컬럼 값 온전');
    else call _fail('avail','V1 기본 노출','rows=' || coalesce(v_n::text,'∅')
                    || ' pid=' || coalesce(v_pid::text,'∅') || ' name=' || coalesce(v_name,'∅')
                    || ' dist=' || coalesce(v_dist,'∅') || ' avatar=' || coalesce(v_avatar,'∅')
                    || ' tier=' || coalesce(v_tier,'∅') || ' bio=' || coalesce(v_bio,'∅')
                    || ' pace=' || coalesce(v_pace::text,'∅') || ' runs=' || coalesce(v_runs::text,'∅')
                    || ' resp=' || coalesce(v_resp::text,'∅')); end if;
  exception when others then call _fail('avail','V1 기본 노출', sqlerrm);
  end;

  -- ---------- [V2] 라이브 4종 차단 — 점유 상태 정확히 4종이 러너를 숨긴다 ----------
  begin
    v_bad := '';
    foreach v_st in array v_live loop
      cx := t_av_booking(oo, dg, rt, r1, v_t + interval '10 minutes', 5.0, v_st::booking_status);
      if t_av_has(b1, r1) then v_bad := v_bad || v_st || ' '; end if;
      delete from bookings where id = cx;
    end loop;
    if v_bad = '' then call _pass('avail','V2 라이브 4종 차단 — confirmed·runner_enroute·picked_up·active 겹침 시 숨김');
    else call _fail('avail','V2 라이브 4종 차단','안 숨겨진 상태: ' || v_bad); end if;
  exception when others then call _fail('avail','V2 라이브 4종 차단', sqlerrm);
  end;

  -- ---------- [V3] 비점유 상태 무차단 — 나머지 상태는 겹쳐도 숨기지 않는다 ----------
  -- (is_slot_available로 갈아끼우면 runner_pending에서 즉시 터진다 = 표시가 서버보다 엄격해진 신호)
  begin
    v_bad := '';
    foreach v_st in array v_idle loop
      cx := t_av_booking(oo, dg, rt, r1, v_t + interval '10 minutes', 5.0, v_st::booking_status);
      if not t_av_has(b1, r1) then v_bad := v_bad || v_st || ' '; end if;
      delete from bookings where id = cx;
    end loop;
    if v_bad = '' then call _pass('avail','V3 비점유 상태 무차단 — runner_pending·matching·completed·cancelled_*·expired·no_show·incident_review·refund_pending 겹쳐도 노출');
    else call _fail('avail','V3 비점유 상태 무차단','잘못 숨겨진 상태: ' || v_bad); end if;
  exception when others then call _fail('avail','V3 비점유 상태 무차단', sqlerrm);
  end;

  -- ---------- [V4] 반열림 경계 — 맞닿음은 충돌 아님, 1초 겹침은 충돌 ----------
  begin
    cx := t_av_booking(oo, dg, rt, r1, v_t - interval '65 minutes', 5.0, 'confirmed');  -- ce = 대상 시작
    v_a := t_av_has(b1, r1);
    delete from bookings where id = cx;
    cx := t_av_booking(oo, dg, rt, r1, v_t + interval '65 minutes', 5.0, 'confirmed');  -- cs = 대상 종료
    v_b := t_av_has(b1, r1);
    delete from bookings where id = cx;
    cx := t_av_booking(oo, dg, rt, r1, v_t + interval '64 minutes 59 seconds', 5.0, 'confirmed'); -- 1초 겹침
    v_c := t_av_has(b1, r1);
    delete from bookings where id = cx;
    if v_a and v_b and not v_c
      then call _pass('avail','V4 반열림 경계 — 시작에 끝나는 충돌 노출·종료에 시작하는 충돌 노출·1초 겹침 숨김');
    else call _fail('avail','V4 반열림 경계','끝맞닿음=' || v_a || ' 시작맞닿음=' || v_b || ' 1초겹침=' || v_c); end if;
  exception when others then call _fail('avail','V4 반열림 경계', sqlerrm);
  end;

  -- ---------- [V5] 분수 보존 — km 5.3 → 67.4분 (67분으로 절삭하면 여기서 터진다) ----------
  -- 충돌은 대상 구간의 마지막 24초에만 걸친다: cs = 시작+67분 (= 분수 참 종료 24초 전).
  begin
    b5 := t_av_booking(oo, dg, rt, null, v_t, 5.3, 'matching');
    cx := t_av_booking(oo, dg, rt, r1, v_t + interval '67 minutes', 5.0, 'confirmed');
    v_a := t_av_has(b5, r1);                      -- 분수 참: 숨김 / ::int 절삭 구현: 잘못 노출
    delete from bookings where id = cx;
    cx := t_av_booking(oo, dg, rt, r1, v_t + interval '67 minutes 24 seconds', 5.0, 'confirmed');
    v_b := t_av_has(b5, r1);                      -- 정확히 종료 시각에 시작 → 맞닿음 = 노출
    delete from bookings where id = cx;
    if not v_a and v_b
      then call _pass('avail','V5 분수 보존 — km 5.3=67.4분: 종료 24초 전 시작 충돌 숨김·67분24초 정각 시작 노출');
    else call _fail('avail','V5 분수 보존','24초겹침(숨김이어야)=' || v_a || ' 정각맞닿음(노출이어야)=' || v_b); end if;
  exception when others then call _fail('avail','V5 분수 보존', sqlerrm);
  end;

  -- ---------- [V6] 재지명(rebook) — 현재 지명 러너는 목록에 남고, 진짜 충돌은 그대로 막는다 ----------
  -- (상태 게이트 도입으로 대상 부킹은 LIVE 상태일 수 없어 '자기충돌'은 구조적으로 불가능해졌다.
  --  c.id <> p_booking은 방어선으로 남는다. 여기서 핀하는 것은 사용자 계약: 러너 변경 화면에서
  --  현재 지명자(runner_pending의 runner_id)가 자기 부킹 때문에 사라지면 '변경'이 '재선택'이 된다.)
  begin
    -- b1과 겹치지 않는 시각에 둔다: 이 부킹이 남아 뒤 케이스(V7/V10)의 b1 목록을 정당하게 비우는 것을 피함
    b6 := t_av_booking(oo, dg, rt, r1, v_t6, 5.0, 'runner_pending');   -- 리북 실형상: 현재 지명 러너 R
    v_a := t_av_has(b6, r1);                                      -- 자기 부킹은 충돌 아님 → 노출
    cx := t_av_booking(oo, dg, rt, r1, v_t6 + interval '10 minutes', 5.0, 'confirmed');
    v_b := t_av_has(b6, r1);                                      -- 다른 확정 부킹은 여전히 막는다
    delete from bookings where id = cx;
    if v_a and not v_b
      then call _pass('avail','V6 재지명 — 현재 지명 러너 유지(자기 부킹 무충돌)·타 확정 부킹은 차단');
    else call _fail('avail','V6 재지명','자기부킹노출=' || v_a || ' 타부킹차단=' || (not v_b)); end if;
  exception when others then call _fail('avail','V6 재지명', sqlerrm);
  end;

  -- ---------- [V7] 스토어프런트 필터 — applicant 등급·offline은 일정과 무관하게 부재 ----------
  begin
    perform t_av_only_online(r1, r7a);              -- r7b는 offline으로 남는다
    v_a := t_av_has(b1, r7a);
    v_b := t_av_has(b1, r7b);
    v_c := t_av_has(b1, r1);                        -- 대조군: 목록 자체는 살아있다
    if not v_a and not v_b and v_c
      then call _pass('avail','V7 스토어프런트 필터 — applicant 부재·online=false 부재·정상 러너 유지');
    else call _fail('avail','V7 스토어프런트 필터','applicant=' || v_a || ' offline=' || v_b || ' 대조군=' || v_c); end if;
  exception when others then call _fail('avail','V7 스토어프런트 필터', sqlerrm);
  end;

  -- ---------- [V8] 가용 규칙 무시 — is_slot_available이 아니다 ----------
  -- 주간 규칙 0건 러너 + 새벽 04:13 = is_slot_available는 false. 그래도 지명 화면에는 떠야 한다.
  begin
    perform t_av_only_online(r8);
    select count(*) into v_n from runner_availability_rules where runner_id = r8;
    v_a := t_av_has(b8, r8);
    v_b := is_slot_available(r8, v_t8, v_t8 + interval '65 minutes');
    if v_n = 0 and v_a and not v_b
      then call _pass('avail','V8 가용 규칙 무시 — 규칙 0건·규칙 밖 새벽 시각에도 노출(is_slot_available=false와 무관)');
    else call _fail('avail','V8 가용 규칙 무시','rules=' || v_n || ' rpc노출=' || v_a
                    || ' is_slot_available=' || coalesce(v_b::text,'∅')); end if;
    perform t_av_only_online(r1);
  exception when others then perform t_av_only_online(r1); call _fail('avail','V8 가용 규칙 무시', sqlerrm);
  end;

  -- ---------- [V9] 권한 — 타인·부재 부킹·부킹의 러너·미인증은 not_owner, anon 역할은 실행 거부 ----------
  begin
    v_bad := '';
    -- (a) 인증된 타인 (무관 보호자)
    perform set_config('request.jwt.claim.sub', zz::text, false);
    begin
      perform t_av_has(b1, r1); v_bad := v_bad || 'a:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_owner%' then v_bad := v_bad || 'a:' || sqlerrm || ' '; end if;
    end;
    -- (b) 존재하지 않는 부킹 (부재와 타인은 구별 불가여야 한다)
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform t_av_has(gen_random_uuid(), r1); v_bad := v_bad || 'b:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_owner%' then v_bad := v_bad || 'b:' || sqlerrm || ' '; end if;
    end;
    -- (c) 부킹의 러너 (당사자지만 소유자가 아니다)
    perform set_config('request.jwt.claim.sub', r1::text, false);
    begin
      perform t_av_has(b6, r1); v_bad := v_bad || 'c:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_owner%' then v_bad := v_bad || 'c:' || sqlerrm || ' '; end if;
    end;
    -- (d) 미인증 (GUC 없음 → auth.uid() null → coalesce(...,false)가 술어를 접는다)
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      perform t_av_has(b1, r1); v_bad := v_bad || 'd:예외없음 ';
    exception when others then
      if sqlerrm not like '%not_owner%' then v_bad := v_bad || 'd:' || sqlerrm || ' '; end if;
    end;
    -- (e) anon 역할 — execute 권한 자체가 회수됨
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      set local role anon;
      perform 1 from runners_available_for(b1);
      reset role;
      v_bad := v_bad || 'e:예외없음 ';
    exception when others then
      reset role;
      if sqlerrm not like '%permission denied%' then v_bad := v_bad || 'e:' || sqlerrm || ' '; end if;
    end;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    if v_bad = '' then call _pass('avail','V9 권한 — 타인·부재 부킹·부킹의 러너·미인증 전부 not_owner·anon 역할 실행 거부');
    else call _fail('avail','V9 권한', v_bad); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', oo::text, false);
    call _fail('avail','V9 권한', sqlerrm);
  end;

  -- ---------- [V10] 반환 형상 — 평면 9컬럼 정확히, 스케줄 상세 0 ----------
  begin
    select array_agg(a.n) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'runners_available_for' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(k order by k) into v_keys from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from runners_available_for(b1) x limit 1) s) t;
    select count(*) into v_n from unnest(v_cols) c
    where c ~* 'schedul|booking|owner|price|fare|status|club|address|dog|route';
    if coalesce(array_length(v_cols, 1), 0) = 9 and v_cols @> v_exp_cols and v_exp_cols @> v_cols
       and coalesce(array_length(v_keys, 1), 0) = 9 and v_keys @> v_exp_cols and v_exp_cols @> v_keys
       and v_n = 0
      then call _pass('avail','V10 반환 형상 — 결과 컬럼 정확히 9개(공개 화이트리스트)·스케줄/부킹/소유자 컬럼 0');
    else call _fail('avail','V10 반환 형상','proargnames=' || coalesce(v_cols::text,'∅')
                    || ' 런타임키=' || coalesce(v_keys::text,'∅') || ' 누수=' || coalesce(v_n::text,'∅')); end if;
  exception when others then call _fail('avail','V10 반환 형상', sqlerrm);
  end;

  -- ---------- [V11] 미러 동률 (property) — RPC 판정 == TS 수락 게이트 술어 ----------
  -- 대상 km 5.0 @ T. 오프셋 6종에서 (1) RPC 숨김 여부와 (2) ms 정수 산술로 재현한 TS 술어가
  -- 전부 일치해야 하고, 동시에 기대 패턴 NNYYYN(=충돌 여부)과도 일치해야 한다.
  -- (둘이 함께 틀리는 경우를 패턴이 잡는다.)
  begin
    perform t_av_only_online(r11);
    v_bad := ''; v_pat := '';
    foreach v_st in array v_off loop
      cx := t_av_booking(oo, dg, rt, r11, v_t11 + v_st::interval, 5.0, 'confirmed');
      v_a := not t_av_has(b11, r11);            -- RPC 판정: 숨김 = 충돌
      v_b := t_av_ts_conflict(b11, cx);         -- TS 수락 게이트 술어
      if v_a <> v_b then v_bad := v_bad || v_st || '(rpc=' || v_a || ',ts=' || v_b || ') '; end if;
      v_pat := v_pat || case when v_a then 'Y' else 'N' end;
      delete from bookings where id = cx;
    end loop;
    if v_bad = '' and v_pat = 'NNYYYN'
      then call _pass('avail','V11 미러 동률 — 오프셋 6종(-90m·-65m경계·-30m·동시각·1초겹침·+65m경계)에서 RPC 판정 = TS 수락 게이트 술어 (패턴 NNYYYN)');
    else call _fail('avail','V11 미러 동률','불일치: ' || coalesce(v_bad,'∅') || ' 패턴=' || v_pat || '(기대 NNYYYN)'); end if;
  exception when others then call _fail('avail','V11 미러 동률', sqlerrm);
  end;

  -- ---------- [V12] 8+2 신인 슬롯 — 베테랑 8 + 잔여 후보 중 경험 최하위 2 (0055 §1) ----------
  -- 0054의 순수 상위 10은 공급이 10을 넘는 순간 신규 인증 러너를 영구히 굶겼다: 노출이 없으니
  -- total_runs가 0에 고정되고, 0이니 영원히 노출되지 않는 콜드스타트 교착. 8+2가 그 사각지대를 메운다.
  -- 무대 둘로 나눠 핀다:
  --  (a) 동점 무대(9×6 · 3×6) — 슬롯을 나눈 뒤에도 정렬 결정성이 사나(동점 타이브레이크 포함).
  --  (b) 등급 무대(total_runs 1..12 전부 다름) — 최하위 2명이 **반드시** 오르나. 상위 10 회귀에서는
  --      이 둘이 사라지므로 (b)가 8+2의 실질 핀이다. (a)만으로는 구 계약과 답이 같아 회귀를 못 잡는다
  --      — 동점 무대에서는 '잔여 중 최하위 2' = '상위 10의 9·10번'이기 때문. 그래서 무대가 둘이다.
  declare
    v_vets uuid[]; v_rook uuid[]; v_top10 uuid[]; v_zero uuid[]; v_i int; v_stage text;
  begin
    v_bad := '';
    v_ids := array[]::uuid[];
    for v_n in 1..12 loop
      cx := t_user('av_ord' || v_n, 'runner');
      update runners set total_runs = case when v_n <= 6 then 9 else 3 end where profile_id = cx;
      v_ids := v_ids || cx;
    end loop;
    perform t_av_only_online(variadic v_ids);

    for v_i in 1..2 loop
      if v_i = 2 then                                    -- (b) 등급 무대로 재편성 (동점 제거)
        for v_n in 1..12 loop
          -- 최하위 둘은 문자 그대로 total_runs = 0 — 콜드스타트 교착의 **당사자 본인**이다.
          -- 0055 §1이 지목한 사람은 '덜 뛴 베테랑'이 아니라 '갓 인증돼 한 번도 안 뛴 러너'다.
          -- 1..12 등급만으로는 그 사람이 무대에 아예 없어서, 교착이 실제로 풀리는지가 아니라
          -- '순서가 뒤집히는지'만 검증됐다. 0을 넣어야 핀이 계약의 문장과 같아진다.
          -- 둘 다 0(동점)으로 두면 신인석 타이브레이크(total_runs asc, profile_id)까지 같은 무대에서 걸린다.
          update runners set total_runs = case when v_n <= 2 then 0 else v_n end
          where profile_id = v_ids[v_n];
        end loop;
        select array_agg(r.profile_id) into v_zero
        from runners r where r.profile_id = any(v_ids) and r.total_runs = 0;
      end if;
      v_stage := case v_i when 1 then 'a동점' else 'b등급' end;

      -- 기대값은 RPC와 독립적으로 계산한다: 벤치 8석(desc) · 신인 2석(**벤치를 뺀 잔여**에서 asc)
      -- · 최종은 desc 정렬. 신인석을 잔여에서 고르는 게 계약의 핵심 — 전역 asc 상위 2를 그냥 뽑으면
      -- 동점 타이브레이크가 양쪽 다 profile_id asc라 이미 벤치에 든 사람이 다시 뽑힌다.
      select array_agg(s.pid order by s.rk) into v_vets from (
        select r.profile_id as pid, row_number() over (order by r.total_runs desc, r.profile_id) as rk
        from runners r where r.profile_id = any(v_ids)) s
      where s.rk <= 8;
      select array_agg(t.pid order by t.rk2) into v_rook from (
        select s.pid, row_number() over (order by s.tr asc, s.pid) as rk2 from (
          select r.profile_id as pid, r.total_runs as tr,
                 row_number() over (order by r.total_runs desc, r.profile_id) as rk
          from runners r where r.profile_id = any(v_ids)) s
        where s.rk > 8) t
      where t.rk2 <= 2;
      select array_agg(u.pid order by u.tr desc, u.pid) into v_exp from (
        select r.profile_id as pid, r.total_runs as tr
        from runners r where r.profile_id = any(v_vets || v_rook)) u;
      select array_agg(s.pid order by s.rk) into v_top10 from (        -- 구(0054) 계약의 답
        select r.profile_id as pid, row_number() over (order by r.total_runs desc, r.profile_id) as rk
        from runners r where r.profile_id = any(v_ids)) s
      where s.rk <= 10;

      select array_agg(x.profile_id order by x.ord) into v_got
      from runners_available_for(b1) with ordinality
        as x(profile_id, name, district, avatar_url, tier, bio, pace, total_runs, respond, ord);

      if coalesce(array_length(v_got, 1), 0) <> 10 then
        v_bad := v_bad || v_stage || ':n=' || coalesce(array_length(v_got, 1)::text,'∅') || ' ';
      elsif v_got <> v_exp then
        v_bad := v_bad || v_stage || ':전체 got=' || v_got::text || ' exp=' || v_exp::text || ' ';
      elsif v_got[1:8] <> v_vets then
        v_bad := v_bad || v_stage || ':앞8≠벤치 got=' || v_got[1:8]::text || ' exp=' || v_vets::text || ' ';
      elsif not (v_got[9:10] @> v_rook and v_rook @> v_got[9:10]) then
        v_bad := v_bad || v_stage || ':뒤2≠신인 got=' || v_got[9:10]::text || ' exp=' || v_rook::text || ' ';
      -- 계약을 그 문장 그대로: total_runs = 0인 러너(콜드스타트 당사자)가 신인석에 실제로 앉는가.
      -- 위의 '뒤2=잔여 최하위'는 오라클끼리의 일치라 fixture가 0을 안 만들면 조용히 통과한다 —
      -- 그래서 0의 존재(2명)와 그 2명이 곧 신인석이라는 것을 따로 못박는다.
      elsif v_i = 2 and (coalesce(array_length(v_zero, 1), 0) <> 2 or not (v_got[9:10] @> v_zero)) then
        v_bad := v_bad || 'b등급:total_runs=0 러너가 신인석에 없음 뒤2=' || v_got[9:10]::text
                 || ' zero=' || coalesce(v_zero::text, '∅') || ' ';
      elsif v_i = 2 and v_got = v_top10 then
        v_bad := v_bad || 'b등급:구 상위10과 동일 — 신인석이 실제로 아무도 끌어올리지 못함 ';
      end if;
    end loop;

    if v_bad = ''
      then call _pass('avail','V12 8+2 신인 슬롯 — 동점·등급 두 무대에서 앞8=경험 상위·뒤2=잔여 최하위·전체 정렬 total_runs desc·profile_id asc (등급 무대는 구 상위10과 불일치)');
    else call _fail('avail','V12 8+2 슬롯', v_bad); end if;
  exception when others then call _fail('avail','V12 8+2 슬롯', sqlerrm);
  end;

  -- ---------- [V12b] 풀 ≤ 10 — 슬롯 분할이 아무도 떨어뜨리지 않는다 ----------
  -- 8+2는 '10자리 중 2자리를 신인에게 준다'가 아니라 '11번째부터 생기는 사각지대를 메운다'는 장치다.
  -- 후보가 10 이하면 결과는 풀 전체여야 한다. 특히 9(벤치8+신인1)·10(8+2) 경계에서 한 명이라도 새면
  -- 0054가 고친 바로 그 실패 모드(공급이 조용히 증발)가 슬롯 분할을 타고 되살아난다.
  -- 11은 슬롯이 **처음으로 무는** 크기다 — 10까지는 8+2가 합집합=풀이라 아무 일도 안 일어나고,
  -- 11에서 비로소 정확히 한 명이 떨어진다. 누가 떨어지느냐가 계약의 전부이므로(신인이 떨어지면
  -- 0055가 통째로 무의미, 최상위가 떨어지면 보호자 독법이 깨짐) 여기만 별도 단언을 건다.
  declare
    v_sz int; v_sub uuid[]; v_pool uuid[]; v_v8 uuid[]; v_r2 uuid[]; v_miss uuid[]; v_drop uuid;
  begin
    v_bad := '';
    foreach v_sz in array array[5, 8, 9, 10, 11] loop
      v_sub := v_ids[1:v_sz];
      perform t_av_only_online(variadic v_sub);
      select array_agg(x.profile_id order by x.ord) into v_got
      from runners_available_for(b1) with ordinality
        as x(profile_id, name, district, avatar_url, tier, bio, pace, total_runs, respond, ord);

      if v_sz <= 10 then
        -- ≤10: 슬롯 분할이 아무도 떨어뜨리지 않는다 — 결과 = 풀 전체
        select array_agg(s.pid order by s.tr desc, s.pid) into v_pool from (
          select r.profile_id as pid, r.total_runs as tr
          from runners r where r.profile_id = any(v_sub)) s;
        if v_got is distinct from v_pool then
          v_bad := v_bad || v_sz || '명:got=' || coalesce(array_length(v_got, 1)::text,'∅')
                   || coalesce(v_got::text,'∅') || ' exp=' || coalesce(v_pool::text,'∅') || ' ';
        end if;
      else
        -- =11: 정확히 10행 · 떨어지는 한 명은 (total_runs desc, profile_id) 9위여야 한다.
        -- 즉 벤치 8석 밖이면서 잔여 3명 중 (total_runs asc, profile_id) 하위 2에도 안 드는 사람 —
        -- '가장 덜 뛴 사람'도 '가장 많이 뛴 사람'도 아닌, 잘려도 가장 덜 아픈 중간이다.
        -- (V12는 12명 한 무대에서 순서만 봤고, 경계 11 — 잘림이 시작되는 그 한 칸 — 은 비어 있었다.)
        select array_agg(s.pid order by s.rk) into v_v8 from (
          select r.profile_id as pid, row_number() over (order by r.total_runs desc, r.profile_id) as rk
          from runners r where r.profile_id = any(v_sub)) s
        where s.rk <= 8;
        select array_agg(t.pid order by t.rk2) into v_r2 from (
          select s.pid, row_number() over (order by s.tr asc, s.pid) as rk2 from (
            select r.profile_id as pid, r.total_runs as tr,
                   row_number() over (order by r.total_runs desc, r.profile_id) as rk
            from runners r where r.profile_id = any(v_sub)) s
          where s.rk > 8) t
        where t.rk2 <= 2;
        select array_agg(u.pid order by u.tr desc, u.pid) into v_pool from (
          select r.profile_id as pid, r.total_runs as tr
          from runners r where r.profile_id = any(v_v8 || v_r2)) u;
        select s.pid into v_drop from (
          select r.profile_id as pid, row_number() over (order by r.total_runs desc, r.profile_id) as rk
          from runners r where r.profile_id = any(v_sub)) s
        where s.rk = 9;
        select array_agg(m.pid) into v_miss
        from (select unnest(v_sub) as pid) m where not (m.pid = any(coalesce(v_got, '{}'::uuid[])));

        if coalesce(array_length(v_got, 1), 0) <> 10 then
          v_bad := v_bad || '11명:n=' || coalesce(array_length(v_got, 1)::text,'∅') || ' ';
        elsif v_got is distinct from v_pool then
          v_bad := v_bad || '11명:슬롯 got=' || v_got::text || ' exp=' || coalesce(v_pool::text,'∅') || ' ';
        elsif coalesce(array_length(v_miss, 1), 0) <> 1 or v_miss[1] is distinct from v_drop then
          v_bad := v_bad || '11명:탈락자≠9위 miss=' || coalesce(v_miss::text,'∅')
                   || ' exp9위=' || coalesce(v_drop::text,'∅') || ' ';
        elsif v_drop = any(v_v8) or v_drop = any(v_r2) then
          v_bad := v_bad || '11명:탈락자가 벤치/신인석에 있음 ' || v_drop::text || ' ';
        end if;
      end if;
    end loop;
    perform t_av_only_online(variadic v_ids);            -- 무대 원복 (이후 케이스가 V12 직후 상태를 보도록)
    if v_bad = ''
      then call _pass('avail','V12b 슬롯 경계 — 후보 5·8·9·10명은 결과=풀 전체(누락 0), 11명은 정확히 10행·탈락자는 (desc,pid) 9위 1명(벤치도 신인석도 아님)');
    else call _fail('avail','V12b 슬롯 경계', v_bad); end if;
  exception when others then
    perform t_av_only_online(variadic v_ids); call _fail('avail','V12b 슬롯 경계', sqlerrm);
  end;

  -- ---------- [V14] 상태 게이트 — 무료 draft 프로브·계약 후 부킹은 not_open ----------
  -- (draft는 인증 계정이 무제한 생성 가능(0002:95) — 시각을 바꿔가며 호출하면 남 러너 일정을
  --  초 단위로 복원하는 집계 오라클이 된다. 러너 선택 단계 3종만 허용, 나머지는 not_open.)
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);   -- 명시적 소유자 컨텍스트
    cx := t_av_booking(oo, dg, rt, null, v_t + interval '40 days', 5.0, 'draft');
    begin
      perform t_av_has(cx, r1); v_bad := v_bad || 'draft:예외없음 ';
    exception when others then
      if sqlerrm <> 'not_open' then v_bad := v_bad || 'draft:' || sqlerrm || ' '; end if;
    end;
    cy := t_av_booking(oo, dg, rt, r1, v_t + interval '41 days', 5.0, 'confirmed');
    begin
      perform t_av_has(cy, r1); v_bad := v_bad || 'confirmed:예외없음 ';
    exception when others then
      if sqlerrm <> 'not_open' then v_bad := v_bad || 'confirmed:' || sqlerrm || ' '; end if;
    end;
    begin
      perform t_av_has(b1, r1);   -- 대조군: matching은 게이트 통과 (예외 없어야 함)
    exception when others then v_bad := v_bad || 'matching:' || sqlerrm || ' ';
    end;
    delete from bookings where id in (cx, cy);
    if v_bad = ''
      then call _pass('avail','V14 상태 게이트 — draft·confirmed는 not_open·matching은 통과');
    else call _fail('avail','V14 상태 게이트', v_bad); end if;
  exception when others then call _fail('avail','V14 상태 게이트', sqlerrm);
  end;

  -- ---------- [V13] km 양수 제약 — 음수 km로 겹침 술어(표시+수락 양쪽)를 접는 공격 봉인 ----------
  -- (0054 후반부 constraint bookings_km_positive. not valid여도 신규 쓰기에는 강제된다)
  begin
    begin
      update bookings set km = -99.9 where id = b1;
      call _fail('avail','V13 km 제약','음수 km update가 통과함 — 게이트 무력화 공격 열림');
    exception when check_violation then
      begin
        cx := t_av_booking(oo, dg, rt, r1, v_t + interval '30 days', 0, 'confirmed');
        call _fail('avail','V13 km 제약','km=0 insert가 통과함');
      exception when check_violation then
        call _pass('avail','V13 km 제약 — 음수 update·0 insert 모두 check 위반으로 거부');
      end;
    end;
  exception when others then call _fail('avail','V13 km 제약', sqlerrm);
  end;
end $$;
