-- ═══ 0052: 감사 후속 서버 게이트·정직성 배치 (2026-08-02 클럽 위탁 UI 감사 🔜 절) ═══
-- 왜 (감사 발견 요지):
--  1) club_delegation_board는 세션 id만 알면 누구나 호출할 수 있었다 — 보드는 참가자 명단·러너 이름·
--     보호자 이름을 담는다. 셸 접근 등급이 'none'인 사람에게 열려 있는 건 프라이버시 구멍이다.
--     (겸사: 케이스 딥링크가 dog→인시던트를 클라에서 추측하고 있었다 → openIncidentId를 서버가 준다)
--  2) club_session_detail.people도 같은 부류 — 무관자에게 참가자 이름·강아지 이름·출결이 나갔다.
--     다만 '몇 명 오는지'는 문 앞에서 정직해야 하므로 peopleCount는 남긴다 (클라 폴백의 유일 원천).
--  3) session_cancel_rsvp는 위탁 행까지 조용히 지웠다 — 결제·배정된 위탁이 참여 취소 한 번에
--     증발하면 정산·커스터디가 고아가 된다. 위탁은 위탁 취소로만 끝난다.
--  4) 호스트 채널 insert가 수신자의 세션 자격을 확인하지 않았다 — 호스트가 임의 profile_id로
--     메시지를 만들 수 있었다 (세션 밖 사람에게 스레드가 생긴다).
--  5) 위탁 거절·취소·미진행 알림이 크리티컬 레지스트리에 없어 ack 배선을 타지 않았다.
--  6) 조기 반환(completion_outcome='partial')이 '완료'와 구분되지 않았다 — 낱말은 그대로 두고 배지로.
--  7) 케이스 상세가 isHost를 주지 않아 클라가 호스트 액션 노출을 스스로 추측했다 (죽은 버튼 부류).
-- rev2 (리뷰어 A·B 발견 반영):
--  P0) 인시던트 게이트 NULL 우회 — case_owner 기본 NULL이라 당사자 술어가 NULL로 접혀 not(...)이
--      미발화, 무관자가 detail 열람·증거 위조 가능 → detail·evidence_add 둘 다 coalesce(..., false).
--  P1) 보드 게이트를 not_party 이분법 → 등급별 페이로드 필터로(session·me 항상 · dogs host/full=전체·
--      limited=자기개·none=[] · runners host/full만). impl에 p_access 인자.
--  P2) ui_state 인시던트 배지 세션 필터 · 크리티컬 제목 '세션 취소 — 전액 환불' 추가 ·
--      club_host_channel_ok no_show/기록 존재로 완화 · club_incident_resolve 백업 호스트 허용.
-- 불변: 0051까지는 원격 적용됨 — 기존 파일 수정 없음. 모든 변경은 create or replace / drop+create.

-- ---------- §1. 보드 당사자 게이트 (발견 1 · rev2 P1) ----------
-- 정의는 impl로 옮기고(세 역할 모두 revoke — 호출 통로는 게이트뿐), 공개 함수는 등급을 재고 넘긴다.
-- 최신 정의 = 0048 §M 복사 + dogs[].openIncidentId 추가.
-- [rev2 P1] not_party 이분법(none만 차단) → 등급별 페이로드 필터. 이유:
--   (a) 미확약 인증 러너까지 not_party로 막으면 세션 셸의 러너 확약 CTA(me.runnerCap)가 사라진다.
--   (b) limited(session_delegate_dog 1회로 자가취득·영구)가 보드 전문(타 보호자 실명·chargeState·
--       정산 축·러너 실명/티어)을 그대로 봤다.
--   → impl에 p_access를 받아: session·me는 등급 무관 전량(집결지·시각·요금은 club_overview급 공개
--     정보 + me.runnerCap은 세션 무관 확약 문에 필요), dogs는 host/full=전체·limited=자기 개만·none=[],
--     runners는 host/full=전체·그 외=[].

create or replace function _club_delegation_board_impl(p_session uuid, p_access text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id, 'clubId', s.club_id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point,
      'format', s.format, 'status', s.status,
      'routeName', (select name from routes where id = s.route_id),
      'routeKm', (select km from routes where id = s.route_id),
      'fare', (select club_fare(km) from routes where id = s.route_id),
      'delegatedCapacity', s.delegated_dog_capacity,
      'reservedCount', _club_delegated_reserved(s.id),
      'approvedCount', (select count(*) from session_dogs d
                        where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'approved'),
      'pendingCount', (select count(*) from session_dogs d
                       where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'pending'
                         and d.service_state is distinct from 'ended'),
      'isHost', s.host_profile_id = auth.uid(),
      'checkinOpen', now() between s.scheduled_at - interval '2 hours' and s.scheduled_at + interval '6 hours',
      'viability', club_session_viability(s.id),
      'openIncidents', (select count(*) from club_incidents i
                        where i.session_id = s.id and i.state <> 'resolved'),
      'unassignedIncidents', (select count(*) from club_incidents i
                              where i.session_id = s.id and i.state <> 'resolved' and i.case_owner is null)
    ),
    -- [rev2 P1] runners는 host/full에게만 (러너 실명·티어) — 그 외 등급은 []
    'runners', case when p_access in ('host', 'full') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'profileId', a.runner_profile_id,
        'name', (select name from profiles where id = a.runner_profile_id),
        'tier', (select tier::text from runners where profile_id = a.runner_profile_id),
        'cap', a.delegated_capacity,
        'assigned', (select count(*) from session_dogs x join bookings b on b.id = x.booking_id
                     where x.session_id = s.id and x.custody = 'runner_delegated'
                       and b.runner_id = a.runner_profile_id
                       and b.status in ('confirmed', 'picked_up', 'active', 'completed')),
        'checkedIn', exists (select 1 from session_people sp
                             where sp.session_id = s.id and sp.profile_id = a.runner_profile_id
                               and sp.attendance = 'checked_in'),
        'isMe', a.runner_profile_id = auth.uid()
      ) order by a.delegated_capacity desc, a.runner_profile_id)
      from session_runner_assignments a
      where a.session_id = s.id and a.status = 'committed'), '[]'::jsonb) else '[]'::jsonb end,
    'me', jsonb_build_object(
      'committed', exists (select 1 from session_runner_assignments a
                           where a.session_id = s.id and a.runner_profile_id = auth.uid() and a.status = 'committed'),
      'runnerCap', coalesce(_club_runner_cap(auth.uid()), 0),
      'checkedIn', exists (select 1 from session_people sp
                           where sp.session_id = s.id and sp.profile_id = auth.uid() and sp.attendance = 'checked_in')
    ),
    'dogs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sdId', d.id, 'dogId', d.dog_id,
        'dogName', (select name from dogs where id = d.dog_id),
        'collar', (select collar from dogs where id = d.dog_id),
        'ownerName', (select name from profiles where id = d.owner_profile_id),
        'isMine', d.owner_profile_id = auth.uid(),
        'approval', d.approval,
        'serviceState', d.service_state,
        'completionOutcome', d.completion_outcome,
        'terminationType', d.termination_type,
        'chargeState', d.charge_state,
        'holdStatus', d.hold_status,
        'holdExpiresAt', d.hold_expires_at,
        'refundState', d.refund_state,
        'bookingId', d.booking_id,
        'bookingStatus', (select status::text from bookings b where b.id = d.booking_id),
        'runnerId', (select runner_id from bookings b where b.id = d.booking_id),
        'runnerName', (select p.name from bookings b join profiles p on p.id = b.runner_id where b.id = d.booking_id),
        'ownerConfirmed', (select owner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'runnerConfirmed', (select runner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'custodyWithRunner', d.responsible_profile_id <> d.owner_profile_id,
        'checkedOut', d.checked_out_at is not null,
        -- [R2] 커스터디·payout 축 (디버그 스크린의 축 분리 표시 원천)
        'custodyPhase', d.custody_phase,
        'custodianType', d.custodian_type,
        'custodianProfileId', d.custodian_profile_id,
        'custodianExternal', d.custodian_external,
        'ownerReturnConfirmed', d.owner_confirmed_return_at is not null,
        'runnerReturnConfirmed', d.runner_confirmed_return_at is not null,
        'payoutState', d.payout_state,
        'payoutHold', d.payout_hold,
        'payoutHoldReason', d.payout_hold_reason,
        'pendingTransfer', d.pending_transfer,
        'returnOverrideKind', d.return_override->>'kind',
        -- [R3] 배정 축 — 제안 후보는 호스트·피제안 러너에게만 (보호자는 상태만: 러너 프라이버시)
        'assignmentState', d.assignment_state,
        'objectionUsed', d.objection_used,
        'reviewNeeded', d.review_needed,
        'proposedRunnerId', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                 then d.proposed_runner_profile_id end,
        'proposedRunnerName', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                   then (select name from profiles where id = d.proposed_runner_profile_id) end,
        'proposalExpiresAt', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                  then d.proposal_expires_at end,
        -- [0052 §1] 이 강아지를 대상으로 한 이 세션의 미해소 인시던트 (케이스 딥링크 원천)
        'openIncidentId', (select i.id from club_incidents i
                           join club_incident_subjects sub on sub.incident_id = i.id
                           where i.session_id = s.id and i.state <> 'resolved'
                             and sub.subject_type = 'dog' and sub.subject_id = d.dog_id
                           order by i.opened_at limit 1),
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        and (d.service_state is distinct from 'ended' or d.booking_id is not null)
        -- [rev2 P1] host/full=전체 · limited=자기 개만 · none=[] (both false → 제외)
        and (p_access in ('host', 'full')
             or (p_access = 'limited' and d.owner_profile_id = auth.uid()))), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

revoke execute on function _club_delegation_board_impl(uuid, text) from public, anon, authenticated;

create or replace function club_delegation_board(p_session uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_access text;
begin
  -- [rev2 P1] not_party 예외 제거 — 등급을 재서 impl 페이로드 필터에 넘긴다.
  -- none도 session+me는 받는다(의도된 최소 노출: 집결지·시각·요금은 클럽 공개 정보 수준 +
  -- me.runnerCap은 미확약 러너의 확약 CTA에 필요). dogs/runners만 실질 사적 정보다.
  v_access := _club_shell_access(p_session, auth.uid());
  return _club_delegation_board_impl(p_session, v_access);
end $$;
grant execute on function club_delegation_board(uuid) to authenticated;

comment on function club_delegation_board is
  '보드 v7 (0052 rev2) — 등급별 페이로드 필터(session·me 항상 · dogs host/full=전체/limited=자기개/none=[] · runners host/full만) + dogs[].openIncidentId. 정의는 _club_delegation_board_impl(uuid,text)';

-- ---------- §2. 세션 상세 people 게이트 + peopleCount (발견 2) ----------
-- 최신 정의 = 0036 복사 + people을 당사자에게만, 인원수는 모두에게.

create or replace function club_session_detail(p_session uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', s.id, 'clubId', s.club_id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point,
    'status', s.status, 'capacity', s.people_capacity,
    'hostName', (select name from profiles where id = s.host_profile_id),
    'isHost', s.host_profile_id = auth.uid(),
    'joined', exists (select 1 from session_people where session_id = s.id and profile_id = auth.uid()),
    'myAttendance', (select attendance from session_people where session_id = s.id and profile_id = auth.uid()),
    'dogCount', (select count(*) from session_dogs where session_id = s.id),
    'nextSessionId', (select s2.id from club_sessions s2
                      where s2.club_id = s.club_id and s2.status in ('open','full')
                        and s2.scheduled_at > now() and s2.id <> s.id
                      order by s2.scheduled_at limit 1),
    -- [0052 §2] 인원수는 누구에게나 정직하게 (문 앞 폴백), 명단은 당사자에게만
    'peopleCount', (select count(*) from session_people
                    where session_id = s.id and attendance <> 'no_show'),
    'people', case when _club_shell_access(s.id, auth.uid()) = 'none' then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', pr.name, 'avatarUrl', pr.avatar_url, 'role', sp.role, 'attendance', sp.attendance,
        'isMe', sp.profile_id = auth.uid(),
        'dogName', (select d.name from session_dogs sd join dogs d on d.id = sd.dog_id
                    where sd.session_id = s.id and sd.owner_profile_id = sp.profile_id limit 1)
      ) order by sp.created_at, (sp.role <> 'host_runner'), pr.name)  -- 동시각 타이는 호스트 우선 (빕 001 = 호스트)
      from session_people sp join profiles pr on pr.id = sp.profile_id
      where sp.session_id = s.id), '[]'::jsonb) end
  )
  from club_sessions s where s.id = p_session;
$$;

grant execute on function club_session_detail(uuid) to authenticated;

comment on function club_session_detail is
  '세션 상세 v4 (0052) — people은 _club_shell_access <> none인 당사자에게만, peopleCount는 항상 (문 앞 정직)';

-- ---------- §3. 참여 취소의 커스터디 가드 (발견 3) ----------
-- 최신 정의 = 0030 복사 + 동반견만 삭제 · 활성 위탁이 있으면 참여 취소 자체를 거부.

create or replace function session_cancel_rsvp(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_role text;
begin
  select role into v_role from session_people where session_id = p_session and profile_id = auth.uid();
  if v_role is null then raise exception 'not_joined'; end if;
  if v_role = 'host_runner' then raise exception 'host_cannot_leave'; end if;
  -- [0052 §3] 위탁은 참여 취소로 조용히 사라지지 않는다 — 먼저 위탁을 취소해야 한다
  if exists (select 1 from session_dogs
             where session_id = p_session and owner_profile_id = auth.uid()
               and custody = 'runner_delegated' and service_state is distinct from 'ended') then
    raise exception 'delegation_active';
  end if;
  delete from session_dogs where session_id = p_session and owner_profile_id = auth.uid()
    and custody = 'owner_handled';
  delete from session_people where session_id = p_session and profile_id = auth.uid();
  update club_sessions set status = 'open' where id = p_session and status = 'full';
end $$;

grant execute on function session_cancel_rsvp(uuid) to authenticated;

comment on function session_cancel_rsvp is
  'RSVP 취소 v2 (0052) — 동반견(owner_handled)만 제거, 활성 위탁(runner_delegated·미종료) 있으면 delegation_active';

-- ---------- §4. 호스트 채널 수신자의 세션 자격 (발견 4) ----------
-- RLS 정책은 호출자 권한으로 술어를 실행한다 (0049 §A 근거) — _club_shell_access는 authenticated에
-- 열 수 없다(임의 인자 = 참여 프로빙 통로). 그래서 '호출자가 그 세션의 호스트일 때만' 답하는
-- definer 래퍼를 연다: 호스트는 이미 자기 세션의 참가자를 아는 사람이라 새 정보가 새지 않는다.
-- [rev2 P2] 수신자 자격을 _club_shell_access <> 'none'로 재면 no_show가 none으로 떨어져
-- 노쇼 직후 호스트 안내가 막힌다(+ RLS 원문 노출). → '수신자가 그 세션에 **기록**이 있으면'
-- (session_people 행 OR session_dogs 행 존재) 허용으로 완화. 세션 밖 임의 profile 차단은 유지.
create or replace function club_host_channel_ok(p_session uuid, p_recipient uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select _club_shell_access(p_session, auth.uid()) = 'host'
     and (exists (select 1 from session_people sp
                  where sp.session_id = p_session and sp.profile_id = p_recipient)
          or exists (select 1 from session_dogs sd
                     where sd.session_id = p_session and sd.owner_profile_id = p_recipient));
$$;
grant execute on function club_host_channel_ok(uuid, uuid) to authenticated;

drop policy if exists "club chat read" on club_chat_messages;
drop policy if exists "club chat send" on club_chat_messages;

-- 읽기: 그룹 = full/host · 호스트 채널 = 호스트 + 그 수신자 본인 (0049와 동일 — limited도 자기 스레드는 읽는다)
create policy "club chat read" on club_chat_messages for select using (
  case audience
    when 'group' then club_my_shell_access(session_id) in ('host', 'full')
    else club_my_shell_access(session_id) = 'host' or recipient_profile_id = auth.uid()
  end
);
-- 쓰기: 그룹 = full/host + 수명 안 · 호스트 채널 = 본인 스레드(limited 이상) 또는
-- 호스트 → **이 세션에 자격이 있는 수신자** (0052: 세션 밖 profile_id로 스레드를 만들 수 없다)
create policy "club chat send" on club_chat_messages for insert with check (
  sender_id = auth.uid()
  and club_my_chat_writable(session_id)
  and kind in ('text', 'photo')
  and case audience
    when 'group' then club_my_shell_access(session_id) in ('host', 'full')
                      and recipient_profile_id is null
    else (recipient_profile_id = auth.uid()
          and club_my_shell_access(session_id) in ('limited', 'full'))
         or (club_my_shell_access(session_id) = 'host' and recipient_profile_id is not null
             and club_host_channel_ok(session_id, recipient_profile_id))
  end
);

-- ---------- §5. 크리티컬 제목 레지스트리 보강 (발견 5 · rev2 P2) ----------
-- 위탁이 거절·취소·미진행으로 끝나는 알림은 ack 배선(0049 §D)을 타야 한다 — 돈이 움직인 사실이다.
-- [rev2 P2] 실제 발신 제목 '세션 취소 — 전액 환불'(club_cancel_session, 0038:247)이 레지스트리의
-- '세션 취소'와 불일치해 ack 미배선이었다 — 실발신 제목을 추가한다.
insert into club_critical_titles (title) values
  ('위탁 신청 거절'), ('위탁 취소 — 전액 환불'), ('위탁 미진행 — 전액 환불'),
  ('세션 취소 — 전액 환불')
on conflict do nothing;

-- ---------- §6. 프로젝션 v5 — 조기 반환 배지 (발견 6) ----------
-- 최신 정의 = 0048 §L 복사 + partial 배지. primaryStage 낱말은 건드리지 않는다.

create or replace function club_dog_ui_state(p_session_dog uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sd session_dogs; v_stage text; v_badges jsonb := '[]'; v_actors jsonb := '[]';
        v_sev text := 'info'; v_block jsonb := '[]';
begin
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then return null; end if;
  if sd.custody = 'owner_handled' then
    v_stage := '보호자 동반';
  else
    -- 커스터디 우선 단계 (반환·이양·외부 보호는 서비스 축이 뭐라 하든 화면의 1번 사실)
    if sd.custodian_type in ('clinic','authority') then
      v_stage := '외부 보호 중';
      v_badges := v_badges || to_jsonb(coalesce(sd.custodian_external, '외부 기관'));
      v_sev := 'critical'; v_actors := '["host","ops"]'; v_block := '["케이스 확인"]';
    elsif sd.custody_phase = 'transfer_pending' then
      v_stage := '이양 수락 대기'; v_sev := 'warn';
      v_actors := '["runner"]'; v_block := '["이양 수락"]';
    elsif sd.custody_phase = 'return_pending' then
      v_stage := '반환 대기'; v_sev := 'warn';
      v_actors := case
        when sd.owner_confirmed_return_at is null and sd.runner_confirmed_return_at is null
          then '["owner","runner"]'
        when sd.owner_confirmed_return_at is null then '["owner"]'
        else '["runner"]' end;
      v_block := '["반환 확인"]';
    else
      v_stage := case
        when sd.service_state = 'requested' then '신청 대기'
        when sd.service_state = 'approved' and sd.hold_status = 'active' then '승인 — 결제 대기'
        when sd.service_state = 'approved' then '승인 — 결제 필요'
        when sd.service_state = 'confirmed' and sd.assignment_state in ('unassigned','declined','replacement_needed') then '결제 완료 — 배정 대기'
        when sd.service_state = 'confirmed' and sd.assignment_state = 'proposed' then '러너 수락 대기'
        when sd.service_state = 'confirmed' then '담당 확정 — 인계 대기'
        when sd.service_state = 'in_service' and (select status from bookings where id = sd.booking_id)::text = 'picked_up'
          then '러너가 보호 중'
        when sd.service_state = 'in_service' then '러닝 중'
        when sd.service_state = 'ended' and sd.completion_outcome in ('completed','partial')
          and sd.custody_phase = 'resolved' then '완료'
        when sd.service_state = 'ended' then '종료'
        else '확인 중' end;
      if sd.service_state = 'approved' and sd.charge_state <> 'paid' then
        v_actors := '["owner"]'; v_block := '["결제"]';
      elsif sd.assignment_state = 'proposed' then v_actors := '["runner"]'; v_block := '["러너 수락"]';
      elsif sd.service_state = 'confirmed' and sd.assignment_state = 'accepted' then
        v_actors := '["owner","runner"]'; v_block := '["인계 확인"]';
      end if;
    end if;
    if sd.refund_state = 'pending' then v_badges := v_badges || '"환불 처리 중"'::jsonb; end if;
    if sd.refund_state = 'failed' then v_badges := v_badges || '"환불 실패"'::jsonb; v_sev := 'critical'; end if;
    if sd.hold_status = 'expired' then v_badges := v_badges || '"결제 기한 만료"'::jsonb; end if;
    if sd.payout_hold = 'held' then v_badges := v_badges || '"정산 보류"'::jsonb; end if;
    if sd.assignment_state = 'replacement_needed' then v_badges := v_badges || '"자리 재확인 중"'::jsonb; v_sev := 'warn'; end if;
    if sd.review_needed then v_badges := v_badges || '"재검토 필요"'::jsonb; v_sev := 'warn'; end if;
    -- [0052 §6] 조기 반환(부분 완료)은 '완료'와 같은 낱말로 덮이면 안 된다 — 배지로만 정직하게
    if sd.service_state = 'ended' and sd.completion_outcome = 'partial' then
      v_badges := v_badges || '"조기 반환"'::jsonb;
    end if;
    -- [rev2 P2] 세션 필터 — 타 세션 미해소 인시던트가 오늘 보드에서 크리티컬 배지(+openIncidentId
    -- 세션 한정과 비대칭: null id 죽은 딥링크)·교차 세션 존재 누수를 일으켰다. session_id로 좁힌다.
    if exists (select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
               where s.subject_type = 'dog' and s.subject_id = sd.dog_id and i.state <> 'resolved'
                 and i.session_id = sd.session_id) then
      v_badges := v_badges || '"인시던트 확인 중"'::jsonb; v_sev := 'critical';
    end if;
  end if;
  return jsonb_build_object(
    'primaryStage', v_stage, 'secondaryBadges', v_badges,
    'blockingIssues', v_block, 'primaryIssue', v_block->0,
    'requiredActors', v_actors, 'severity', v_sev,
    'allowedActions', '[]'::jsonb
  );
end $$;

grant execute on function club_dog_ui_state(uuid) to authenticated;

comment on function club_dog_ui_state is
  'UI 프로젝션 v5 (0052) — ended·partial이면 secondaryBadges에 조기 반환 (낱말=primaryStage는 불변)';

-- ---------- §7. 케이스 상세 isHost (발견 7) ----------
-- 최신 정의 = 0050 복사 + isHost (호스트·백업 호스트).

create or replace function club_incident_detail(p_incident uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i record;
begin
  select * into i from club_incidents where id = p_incident;
  if i.id is null then raise exception 'not_found'; end if;
  -- [rev2 P0] case_owner 기본 NULL → `auth.uid() in (i.opened_by, i.case_owner)`가 `false OR NULL`
  -- = NULL → `not (...)` = NULL → if 미발화 → 게이트 통째 우회(케이스 오너 배정 전엔 아무 인증
  -- 유저나 detail 열람 가능). 당사자 술어 전체를 coalesce(..., false)로 감싸 NULL을 false로.
  if not coalesce((auth.uid() in (i.opened_by, i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                     and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
          or exists (select 1 from club_incident_subjects sub
                     join session_dogs sd on sd.dog_id = sub.subject_id and sd.session_id = i.session_id
                     left join bookings b on b.id = sd.booking_id
                     where sub.incident_id = p_incident and sub.subject_type = 'dog'
                       and (sd.owner_profile_id = auth.uid() or b.runner_id = auth.uid()))), false) then
    raise exception 'not_case_party';
  end if;
  return jsonb_build_object(
    'id', i.id, 'severity', i.severity, 'state', i.state, 'summary', i.summary,
    'openedBy', i.opened_by, 'caseOwner', i.case_owner,
    -- [0052 §7] 호스트 여부는 서버 판정 — 클라가 케이스 화면의 호스트 액션을 지어내지 않게
    'isHost', exists (select 1 from club_sessions cs where cs.id = i.session_id
                      and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id)),
    'openedAt', i.opened_at, 'resolvedAt', i.resolved_at,
    'subjects', (select coalesce(jsonb_agg(jsonb_build_object(
       'type', sub.subject_type, 'id', sub.subject_id)), '[]'::jsonb)
       from club_incident_subjects sub where sub.incident_id = p_incident),
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object(
       'kind', e.kind, 'payload', e.payload, 'by', e.created_by, 'at', e.created_at)
       order by e.created_at), '[]'::jsonb)
       from club_incident_evidence e where e.incident_id = p_incident));
end $$;

grant execute on function club_incident_detail(uuid) to authenticated;

comment on function club_incident_detail is
  '케이스 상세 v2 (0052) — isHost 추가 (호스트/백업 호스트 판정은 서버가 한다)';

-- ---------- §8. 인시던트 게이트 NULL 우회 + 백업 호스트 해소 (rev2 P0 · P2) ----------
-- [rev2 P0] club_incident_evidence_add도 club_incident_detail과 동일한 NULL 우회를 갖는다 —
--   case_owner 미배정 케이스에 아무 인증 유저나 증거 위조 가능. 0050:76 정의 복사 + 당사자 술어를
--   coalesce(..., false)로 감싼다 (그 변경만).
create or replace function club_incident_evidence_add(
  p_incident uuid, p_kind text, p_payload jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare i record;
begin
  perform _club_require_v2();
  if p_kind not in ('photo', 'text', 'location', 'document') then raise exception 'bad_kind'; end if;
  select * into i from club_incidents where id = p_incident;
  if i.id is null then raise exception 'not_found'; end if;
  -- [rev2 P0] case_owner NULL이면 `false OR NULL` = NULL → not(...) = NULL → 우회. coalesce로 봉함.
  if not coalesce((auth.uid() in (i.opened_by, i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                     and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
          or exists (select 1 from club_incident_subjects sub
                     join session_dogs sd on sd.dog_id = sub.subject_id and sd.session_id = i.session_id
                     left join bookings b on b.id = sd.booking_id
                     where sub.incident_id = p_incident and sub.subject_type = 'dog'
                       and (sd.owner_profile_id = auth.uid() or b.runner_id = auth.uid()))), false) then
    raise exception 'not_case_party';
  end if;
  insert into club_incident_evidence (incident_id, kind, payload, created_by)
  values (p_incident, p_kind, p_payload, auth.uid());
end $$;

grant execute on function club_incident_evidence_add(uuid, text, jsonb) to authenticated;

comment on function club_incident_evidence_add is
  '증거 추가 v2 (0052 rev2) — 당사자 술어 coalesce로 NULL 우회 봉함 (case_owner 미배정 케이스 위조 차단)';

-- [rev2 P2] 0052 §7 isHost는 backup_host_profile_id를 호스트로 인정하는데 club_incident_resolve
--   (0050:143)는 host_profile_id·case_owner만 허용 → 백업 호스트가 '케이스 해소'를 보고도 not_case_owner.
--   0050 본문 복사 + 허용 host 판정에 backup_host_profile_id 추가 (그 조건만).
create or replace function club_incident_resolve(p_incident uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_session uuid; v_owner uuid; v_sd record;
begin
  perform _club_require_v2();
  select session_id, case_owner into v_session, v_owner from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  -- [rev2 P2] 백업 호스트도 케이스 해소 가능 (isHost가 이미 인정한 역할 — 죽은 버튼 제거)
  if auth.uid() <> v_owner and not exists
    (select 1 from club_sessions where id = v_session
       and auth.uid() in (host_profile_id, backup_host_profile_id)) then
    raise exception 'not_case_owner';
  end if;
  if p_note is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (p_incident, 'text', jsonb_build_object('note', p_note, 'at', now()), auth.uid());
  end if;
  update club_incidents set state = 'resolved', resolved_at = now() where id = p_incident;
  -- 이 인시던트가 걸었던 지급 보류만 해제 — 같은 강아지의 다른 오픈 케이스가 있으면 유지
  for v_sd in select id, dog_id from session_dogs
    where payout_hold = 'held' and payout_hold_reason = 'incident' and payout_hold_incident = p_incident
  loop
    if not exists (
      select 1 from club_incident_subjects sub join club_incidents i2 on i2.id = sub.incident_id
      where sub.subject_type = 'dog' and sub.subject_id = v_sd.dog_id
        and i2.state <> 'resolved' and i2.id <> p_incident) then
      update session_dogs set payout_hold = 'none', payout_hold_reason = null,
        payout_hold_incident = null where id = v_sd.id;
    end if;
  end loop;
end $$;

grant execute on function club_incident_resolve(uuid, text) to authenticated;

comment on function club_incident_resolve is
  '케이스 해소 v2 (0052 rev2) — 허용에 backup_host_profile_id 추가 (백업 호스트 해소 죽은 버튼 제거)';
