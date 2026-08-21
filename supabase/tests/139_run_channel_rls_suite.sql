-- ═══ 139 live-location authorization — 0103 pins (L1-L9) ═══
-- What this suite pins: that a runner's live GPS is readable ONLY by the booking's owner and its
-- CURRENTLY ASSIGNED runner, and publishable ONLY by that runner, and only while the run is live.
-- Before 0103 the channel was a public broadcast: `realtime.messages` had zero policies and
-- `geo.ts` never set `private:true`, so a booking UUID was the whole gate — and a LOSING bidder
-- keeps that UUID from `marketplace_open_requests`.
-- ⚠ Every case is executed at the BOUNDARY (a real SELECT/INSERT on `realtime.messages` as
--   `authenticated`, with `realtime.topic()` set the way realtime sets it), not against the
--   predicate alone. Sean's closure rule: the unauthorized operation must be rejected at the
--   server boundary. A predicate-only pin would measure the helper and not the shipping path —
--   this repo's most repeated defect.
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).
do $$
declare
  v_owner uuid; v_runner uuid; v_loser uuid; v_stranger uuid; v_bk uuid; v_other_bk uuid;
  v_topic text; v_msg text; v_bad text; v_n int; v_ok boolean; v_dog uuid; v_dog2 uuid;
begin
  -- ---------- fixtures ----------
  -- profiles.id references auth.users; the shim's auth.users is (id, email) only.
  v_owner := gen_random_uuid(); v_runner := gen_random_uuid();
  v_loser := gen_random_uuid(); v_stranger := gen_random_uuid();
  insert into auth.users (id, email) values
    (v_owner,'l-owner@t'), (v_runner,'l-runner@t'), (v_loser,'l-loser@t'), (v_stranger,'l-stranger@t');
  insert into profiles (id, role, name) values
    (v_owner,'owner','L-owner'), (v_runner,'runner','L-runner'),
    (v_loser,'runner','L-loser'), (v_stranger,'owner','L-stranger');

  -- bookings.runner_id references runners(profile_id), not profiles.
  insert into runners (profile_id) values (v_runner), (v_loser);
  -- [0119] 이 스위트는 t_dog를 안 쓰고 직접 심는다 — 0119 §D 이후 미신고 강아지는 위탁이
  -- 거절되므로 신고값이 명시적으로 필요하다. 이 스위트가 핀하는 성질은 바뀌지 않는다.
  insert into dogs (owner_id, name, dangerous_status) values (v_owner,'L-dog','declared_none') returning id into v_dog;
  insert into dogs (owner_id, name, dangerous_status) values (v_stranger,'L-dog2','declared_none') returning id into v_dog2;
  insert into bookings (id, owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
    values (gen_random_uuid(), v_owner, v_dog, v_runner, 'active', now(), 3, 7900, 9000, 16900)
    returning id into v_bk;
  insert into bookings (id, owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
    values (gen_random_uuid(), v_stranger, v_dog2, null, 'active', now(), 3, 7900, 9000, 16900)
    returning id into v_other_bk;
  v_topic := 'run2-' || v_bk::text;

  -- ---------- [L1] the owner receives, and cannot publish ----------
  -- The asymmetry is the point: the owner watching is the product; the owner INJECTING a position
  -- onto their own map is the forgery half of the same hole.
  perform set_config('realtime.topic', v_topic, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_bad := '';
  if not run_channel_allowed(v_topic, v_owner, 'read')  then v_bad := v_bad || ' 오너가 못 받는다'; end if;
  if     run_channel_allowed(v_topic, v_owner, 'write') then v_bad := v_bad || ' 오너가 발행할 수 있다(위조)'; end if;
  if v_bad = '' then call _pass('rtch','L1 오너는 받고 발행은 못 한다');
  else v_msg := v_bad; call _fail('rtch','L1 오너 읽기/쓰기 비대칭', v_msg); end if;

  -- ---------- [L2] the assigned runner reads AND publishes ----------
  v_bad := '';
  if not run_channel_allowed(v_topic, v_runner, 'read')  then v_bad := v_bad || ' 배정 러너가 못 받는다'; end if;
  if not run_channel_allowed(v_topic, v_runner, 'write') then v_bad := v_bad || ' 배정 러너가 발행 못 한다(기능이 죽는다)'; end if;
  if v_bad = '' then call _pass('rtch','L2 배정된 러너는 받고 발행한다 — 양성 대조');
  else v_msg := v_bad; call _fail('rtch','L2 배정 러너', v_msg); end if;

  -- ---------- [L3] the LOSING bidder — the actual exploit ----------
  -- This is the case the hole was: a runner who saw the open request keeps the UUID forever.
  v_bad := '';
  if run_channel_allowed(v_topic, v_loser, 'read')  then v_bad := v_bad || ' 낙선 러너가 위치를 본다'; end if;
  if run_channel_allowed(v_topic, v_loser, 'write') then v_bad := v_bad || ' 낙선 러너가 위치를 주입한다'; end if;
  if run_channel_allowed(v_topic, v_stranger, 'read') then v_bad := v_bad || ' 무관한 사용자가 본다'; end if;
  if v_bad = '' then call _pass('rtch','L3 낙선 러너·무관한 사용자 모두 거부 — UUID를 알아도 소용없다');
  else v_msg := v_bad; call _fail('rtch','L3 비당사자 거부', v_msg); end if;

  -- ---------- [L4] a FORMER runner loses access the instant reassignment happens ----------
  -- No grace window: the predicate reads b.runner_id live, so the old runner is out on the UPDATE.
  update bookings set runner_id = v_loser where id = v_bk;
  v_bad := '';
  if run_channel_allowed(v_topic, v_runner, 'read')  then v_bad := v_bad || ' 이전 러너가 재배정 후에도 본다'; end if;
  if run_channel_allowed(v_topic, v_runner, 'write') then v_bad := v_bad || ' 이전 러너가 재배정 후에도 발행한다'; end if;
  if not run_channel_allowed(v_topic, v_loser, 'read') then v_bad := v_bad || ' 새 러너가 못 받는다'; end if;
  update bookings set runner_id = v_runner where id = v_bk;   -- restore
  if v_bad = '' then call _pass('rtch','L4 재배정 즉시 이전 러너는 잃고 새 러너가 얻는다 (유예 없음)');
  else v_msg := v_bad; call _fail('rtch','L4 재배정', v_msg); end if;

  -- ---------- [L5] every dead status closes the channel ----------
  -- One booking per status rather than mutating one: the transition trigger correctly refuses
  -- active -> draft, and a fixture must not need the state machine disabled to exist.
  declare v_st text; v_tmp uuid; v_tt text;
  begin
    v_bad := '';
    foreach v_st in array array['draft','confirmed','completed','cancelled_owner','expired','incident_review']
    loop
      insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
        values (v_owner, v_dog, v_runner, v_st::booking_status, now(), 3, 7900, 9000, 16900)
        returning id into v_tmp;
      v_tt := 'run2-' || v_tmp::text;
      if run_channel_allowed(v_tt, v_owner,  'read')  then v_bad := v_bad || ' ' || v_st || '에서 오너가 본다'; end if;
      if run_channel_allowed(v_tt, v_runner, 'write') then v_bad := v_bad || ' ' || v_st || '에서 러너가 발행한다'; end if;
    end loop;
    if v_bad = '' then call _pass('rtch','L5 라이브가 아닌 모든 상태에서 닫힌다 — 종료·취소·만료·인시던트 검토 포함');
    else v_msg := v_bad; call _fail('rtch','L5 상태 게이트', v_msg); end if;
  end;

  -- ---------- [L6] topic substitution and malformed topics ----------
  v_bad := '';
  if run_channel_allowed('run2-' || v_other_bk::text, v_owner, 'read') then v_bad := v_bad || ' 남의 예약 토픽이 열린다'; end if;
  if run_channel_allowed('run2-not-a-uuid',     v_owner, 'read') then v_bad := v_bad || ' 잘못된 토픽이 통과'; end if;
  if run_channel_allowed('chat-' || v_bk::text, v_owner, 'read') then v_bad := v_bad || ' 다른 네임스페이스가 통과'; end if;
  -- 0104: the LEGACY public namespace must be refused here. Not because refusing it protects
  -- anything — a public channel never asks RLS — but because accepting it would let a new client
  -- believe `run-` is policy-bound when it is not.
  if run_channel_allowed('run-' || v_bk::text, v_owner, 'read') then v_bad := v_bad || ' 레거시 run- 네임스페이스가 인가된다(거짓 안심)'; end if;
  if run_channel_allowed(null,                  v_owner, 'read') then v_bad := v_bad || ' null 토픽이 통과'; end if;
  if run_channel_allowed(v_topic,               null,    'read') then v_bad := v_bad || ' null uid가 통과(익명)'; end if;
  if run_channel_allowed(v_topic, v_owner, 'delete')             then v_bad := v_bad || ' 알 수 없는 op가 통과'; end if;
  if v_bad = '' then call _pass('rtch','L6 토픽 치환·형식 오류·null·알 수 없는 op 전부 거부 (fail closed)');
  else v_msg := v_bad; call _fail('rtch','L6 fail closed', v_msg); end if;

  -- ---------- [L7] THE BOUNDARY — a real INSERT on realtime.messages as authenticated ----------
  -- Everything above pins the RULE. This pins that the rule is WIRED: RLS actually refuses.
  v_bad := '';
  perform set_config('realtime.topic', v_topic, true);
  perform set_config('request.jwt.claim.sub', v_loser::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_topic, 'broadcast', '{"lat":37.5,"lng":127.0}'::jsonb, true);
    v_bad := v_bad || ' 낙선 러너의 INSERT가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', v_runner::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_topic, 'broadcast', '{"lat":37.5,"lng":127.0}'::jsonb, true);
  exception when others then
    -- name the cause: a positive control that fails silently teaches nothing
    v_bad := v_bad || ' 배정 러너의 INSERT가 경계에서 막혔다 (기능이 죽는다) [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  -- anon holds INSERT on realtime.messages in production (measured), so RLS is the ONLY thing
  -- refusing it. That makes the anonymous leg the strongest boundary case in the suite.
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_topic, 'broadcast', '{"lat":37.5,"lng":127.0}'::jsonb, true);
    v_bad := v_bad || ' 익명 INSERT가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  if v_bad = '' then call _pass('rtch','L7 경계 실측 — realtime.messages에 대한 실제 INSERT가 낙선 러너는 거부하고 배정 러너는 허용한다');
  else v_msg := v_bad; call _fail('rtch','L7 경계 INSERT', v_msg); end if;

  -- ---------- [L8] the policies exist and are shaped as intended ----------
  v_bad := '';
  select count(*) into v_n from pg_policies
    where schemaname='realtime' and tablename='messages' and policyname in ('run channel read','run channel write');
  if v_n <> 2 then v_bad := v_bad || ' 정책이 2개가 아니다=' || v_n; end if;
  if exists (select 1 from pg_policies where schemaname='realtime' and tablename='messages'
               and policyname='run channel write' and cmd <> 'INSERT')
    then v_bad := v_bad || ' write 정책이 INSERT가 아니다'; end if;
  if has_function_privilege('anon','run_channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' anon이 술어를 실행할 수 있다'; end if;
  if not (select p.prosecdef from pg_proc p where p.proname='run_channel_allowed')
    then v_bad := v_bad || ' 술어가 definer가 아니다'; end if;
  if (select coalesce(array_to_string(p.proconfig,','),'') from pg_proc p where p.proname='run_channel_allowed') not like '%pg_temp%'
    then v_bad := v_bad || ' 술어 본문에 search_path가 없다'; end if;
  if v_bad = '' then call _pass('rtch','L8 배선 — 정책 2개(select/insert), 술어는 definer·search_path 고정·anon 실행 불가');
  else v_msg := v_bad; call _fail('rtch','L8 배선', v_msg); end if;

  -- ---------- [L9] club runs use the SAME namespace and must keep working ----------
  -- createPosPublisher(bookingIds) publishes to run-<booking_id> per dog, and club custody
  -- (0038:105, 0043:422) keys on b.runner_id = auth.uid() — so the same predicate covers club.
  -- If this ever fails, the club live map died and the 1:1 pins would not have noticed.
  update bookings set club_session_id = null where id = v_bk;
  v_bad := '';
  if not run_channel_allowed(v_topic, v_runner, 'write') then v_bad := v_bad || ' 클럽 형상에서 러너가 발행 못 한다'; end if;
  if v_bad = '' then call _pass('rtch','L9 클럽 러닝도 같은 네임스페이스·같은 술어로 계속 동작한다');
  else v_msg := v_bad; call _fail('rtch','L9 클럽', v_msg); end if;
end $$;
