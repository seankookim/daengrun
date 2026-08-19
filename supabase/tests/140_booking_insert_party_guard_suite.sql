-- ═══ 140 booking INSERT party guard — 0105 pins (B1-B7) ═══
-- What this suite pins: a client cannot manufacture a booking that NAMES someone else. The row is
-- what `is_booking_party()` reads, so a forged draft was a key — the audit drove one root into a
-- chat thread to the victim, a public review of them, and a push notification on their phone.
-- ⚠ B5 and B6 are POSITIVE CONTROLS and matter as much as the denials: this guard sits in the
--   booking-creation path and the money path. A suite that only proves refusals is satisfied by a
--   guard that refuses everything — measured elsewhere today at 11/14, where every negative arm
--   was green while the feature was dead.
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).
do $$
declare
  v_att uuid; v_victim uuid; v_mydog uuid; v_theirdog uuid; v_myaddr uuid; v_theiraddr uuid;
  v_other uuid; v_msg text; v_bad text; v_id uuid;
begin
  v_att := gen_random_uuid(); v_victim := gen_random_uuid(); v_other := gen_random_uuid();
  insert into auth.users(id,email) values (v_att,'b-att@t'),(v_victim,'b-vic@t'),(v_other,'b-oth@t');
  insert into profiles(id,role,name) values (v_att,'owner','B-att'),(v_victim,'runner','B-vic'),(v_other,'owner','B-oth');
  insert into runners(profile_id) values (v_victim);
  insert into dogs(owner_id,name) values (v_att,'mine') returning id into v_mydog;
  insert into dogs(owner_id,name) values (v_other,'theirs') returning id into v_theirdog;
  insert into addresses(owner_id,label,addr) values (v_att,'home','A') returning id into v_myaddr;
  insert into addresses(owner_id,label,addr) values (v_other,'home','B') returning id into v_theiraddr;

  perform set_config('request.jwt.claim.sub', v_att::text, true);

  -- ---------- [B1] the exploit: naming a victim as the runner ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into bookings(owner_id,dog_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,v_victim,'draft',now(),3,7900,9000,16900);
    v_bad := ' 피해자를 러너로 지정한 INSERT가 통과했다 (익스플로잇 그대로)';
  exception when others then
    -- ⚠ ONLY the guard's own raise counts as a refusal. A 42501, a missing column or a bad
    -- fixture must NOT read as "the policy worked" — that is how a suite invents a security
    -- pass it never earned.
    if sqlstate <> 'P0001' then v_bad := ' 가드가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('bipg','B1 생성 시 러너 지정 거부 — is_booking_party()를 여는 위조 예약이 만들어지지 않는다');
  else v_msg := v_bad; call _fail('bipg','B1 러너 지정', v_msg); end if;

  -- ---------- [B2] someone else's dog ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into bookings(owner_id,dog_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_theirdog,'draft',now(),3,7900,9000,16900);
    v_bad := ' 남의 개로 만든 예약이 통과했다';
  exception when others then
    -- ⚠ ONLY the guard's own raise counts as a refusal. A 42501, a missing column or a bad
    -- fixture must NOT read as "the policy worked" — that is how a suite invents a security
    -- pass it never earned.
    if sqlstate <> 'P0001' then v_bad := ' 가드가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('bipg','B2 남의 반려견으로는 예약할 수 없다');
  else v_msg := v_bad; call _fail('bipg','B2 남의 개', v_msg); end if;

  -- ---------- [B3] someone else's address ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into bookings(owner_id,dog_id,address_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,v_theiraddr,'draft',now(),3,7900,9000,16900);
    v_bad := ' 남의 주소로 만든 예약이 통과했다';
  exception when others then
    -- ⚠ ONLY the guard's own raise counts as a refusal. A 42501, a missing column or a bad
    -- fixture must NOT read as "the policy worked" — that is how a suite invents a security
    -- pass it never earned.
    if sqlstate <> 'P0001' then v_bad := ' 가드가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('bipg','B3 남의 주소로는 예약할 수 없다');
  else v_msg := v_bad; call _fail('bipg','B3 남의 주소', v_msg); end if;

  -- ---------- [B4] club session is a server link ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into bookings(owner_id,dog_id,club_session_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,gen_random_uuid(),'draft',now(),3,7900,9000,16900);
    v_bad := ' 클럽 세션을 클라가 붙인 예약이 통과했다';
  exception when others then
    -- ⚠ ONLY the guard's own raise counts as a refusal. A 42501, a missing column or a bad
    -- fixture must NOT read as "the policy worked" — that is how a suite invents a security
    -- pass it never earned.
    if sqlstate <> 'P0001' then v_bad := ' 가드가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('bipg','B4 클럽 세션 연결은 서버가 한다');
  else v_msg := v_bad; call _fail('bipg','B4 클럽 세션', v_msg); end if;

  -- ---------- [B5] POSITIVE CONTROL — a legitimate draft still works ----------
  -- If this ever fails, booking creation is dead and every denial above is meaningless.
  v_bad := '';
  begin
    set local role authenticated;
    insert into bookings(owner_id,dog_id,address_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,v_myaddr,'draft',now(),3,7900,9000,16900) returning id into v_id;
    if v_id is null then v_bad := ' 정상 예약이 만들어지지 않았다'; end if;
  exception when others then v_bad := ' 정상 예약이 거부됐다 (예약 생성이 죽었다) [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('bipg','B5 양성 대조 — 본인 개·본인 주소의 정상 예약은 그대로 만들어진다');
  else v_msg := v_bad; call _fail('bipg','B5 양성 대조', v_msg); end if;

  -- ---------- [B6] POSITIVE CONTROL — service_role is unaffected ----------
  -- create-booking-hold runs as service_role and DOES set runner_id/club_session_id server-side.
  -- The guard keys on current_user, so it must skip entirely here or the money path dies.
  v_bad := '';
  begin
    insert into bookings(owner_id,dog_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,v_victim,'draft',now(),3,7900,9000,16900);
  exception when others then v_bad := ' 서버(create-booking-hold 경로)가 막혔다 [' || sqlstate || ']';
  end;
  if v_bad = '' then call _pass('bipg','B6 양성 대조 — service_role은 영향 없음 (create-booking-hold는 러너를 배정한다)');
  else v_msg := v_bad; call _fail('bipg','B6 서버 경로', v_msg); end if;

  -- ---------- [B7] no regression on 0083's custody arm ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into bookings(owner_id,dog_id,status,scheduled_at,km,base_fare,distance_fare,total_price,run_ended_at)
      values (v_att,v_mydog,'draft',now(),3,7900,9000,16900,now());
    v_bad := ' 커스터디 컬럼이 담긴 INSERT가 통과했다 (0083 회귀)';
  exception when others then
    -- ⚠ ONLY the guard's own raise counts as a refusal. A 42501, a missing column or a bad
    -- fixture must NOT read as "the policy worked" — that is how a suite invents a security
    -- pass it never earned.
    if sqlstate <> 'P0001' then v_bad := ' 가드가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('bipg','B7 0083의 커스터디 컬럼 차단은 그대로 (회귀 없음)');
  else v_msg := v_bad; call _fail('bipg','B7 커스터디 회귀', v_msg); end if;
end $$;
