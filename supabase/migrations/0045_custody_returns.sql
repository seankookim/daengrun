-- ═══ 0045: R2 — 커스터디 이벤트 1차 진실 + 반환 분리 (club-run-logic.md v3.3 §2·§5·§7·§16 R2) ═══
-- v1 최대 결함의 사형 집행: **러닝 종료(completed)는 더 이상 커스터디를 보호자에게 돌리지 않는다.**
-- 정산 = 돈 계산일 뿐 — 강아지는 양측 반환 확인까지 러너 책임(return_pending).
--
-- 이 슬라이스의 소유권 이전: 커스터디(custodian_*·custody_phase)와 payout_state가 이벤트/RPC
-- 소유 1차 저장이 된다. 0040의 sync_v1 이벤트 트리거·0038의 completed 커스터디 복귀는 폐기.
-- 오버라이드: witness(호스트 비당사자+강증빙)/assisted만 — 자기 오버라이드 금지. 이양:
-- 러너간 = 양측 수락 원자 트랜잭션(배정 이벤트+세그먼트+부킹 러너 교체), clinic/authority =
-- 반환 국면에서만(주행 전·중은 인시던트 경로 — R6 배선까지 명시 거부).

-- ---------- 스키마 ----------
alter table session_dogs
  add column if not exists owner_confirmed_return_at timestamptz,
  add column if not exists runner_confirmed_return_at timestamptz,
  add column if not exists return_override jsonb,        -- {side,kind,artifact,by,at} — 오버라이드 증빙
  add column if not exists pending_transfer jsonb;       -- {toType,toProfile,toExternal,reason,by,at}

alter table session_dogs drop constraint if exists session_dogs_custody_phase_check;
alter table session_dogs add constraint session_dogs_custody_phase_check
  check (custody_phase in ('with_custodian','outbound_pending','transfer_pending','return_pending','resolved'));

alter table dog_custody_events add column if not exists meta jsonb;
-- [순서 진실] 같은 트랜잭션의 이벤트는 occurred_at(now()=tx 시각)이 동일 — uuid 타이브레이크는
-- 무작위다. 단조 seq가 이벤트 로그의 유일한 정렬 진실 (삽입 순서 = 발생 순서).
alter table dog_custody_events add column if not exists seq bigint generated always as identity;
create index if not exists dog_custody_events_sd_seq_idx on dog_custody_events (session_dog_id, seq desc);

-- ---------- v1 커스터디 트리거 폐기 → v2 (이벤트가 진실) ----------
drop trigger if exists club_custody_transition on bookings;
drop trigger if exists club_v1_custody_event on session_dogs;
drop function if exists _club_custody_transition();
drop function if exists _club_v1_custody_event_tg();

create or replace function _club_custody_transition_v2() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_sd record;
begin
  if new.club_session_id is null then return new; end if;
  -- [직렬화 법] 모든 커스터디 변이는 강아지 행 락 + 락 후 검증 아래에서만 — RPC 경로(세션 락)와
  -- 트리거 경로(부킹 → 여기)가 같은 행 락에서 직렬화된다. seq는 '유효한' 이벤트의 순서만 정한다.
  select * into v_sd from session_dogs where booking_id = new.id for update;
  if v_sd.id is null then return new; end if;

  if new.status = 'picked_up' and new.runner_id is not null then
    -- 나가는 인계 완료(양측 스탬프는 전이 주체가 보증) → 아웃바운드 이벤트 + 러너 커스터디
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type, confirmation_kind)
    values (v_sd.id, 'owner', v_sd.owner_profile_id, 'runner', new.runner_id, 'outbound', 'app_user');
    update session_dogs set
      custodian_type = 'runner', custodian_profile_id = new.runner_id, custodian_external = null,
      custody_phase = 'with_custodian',
      responsible_profile_id = new.runner_id,            -- 레거시 동기화 (정리 슬라이스까지)
      checked_in_at = coalesce(checked_in_at, now())
    where id = v_sd.id;
  elsif new.status = 'completed' then
    -- [R2 핵심] 정산 ≠ 반환: 국면만 반환 대기, 커스터디는 러너 유지, 정산액은 earned
    update session_dogs set
      custody_phase = 'return_pending',
      payout_state = case when payout_state = 'none' then 'earned' else payout_state end
    where id = v_sd.id and custodian_type = 'runner';
  end if;
  return new;
end $$;
create trigger club_custody_transition_v2 after update of status on bookings
  for each row when (new.club_session_id is not null) execute function _club_custody_transition_v2();

-- ---------- 반환 확인 (양측·나가는 인계와 대칭) ----------
create or replace function session_confirm_return(p_session_dog uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sd record; v_runner uuid; v_side text; v_both boolean;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  perform 1 from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.custody_phase <> 'return_pending' then raise exception 'not_return_pending'; end if;
  select runner_id into v_runner from bookings where id = sd.booking_id;

  if auth.uid() = sd.owner_profile_id then v_side := 'owner';
  elsif auth.uid() = v_runner then v_side := 'runner';
  else raise exception 'not_party'; end if;

  if v_side = 'owner' then
    update session_dogs set owner_confirmed_return_at = coalesce(owner_confirmed_return_at, now())
    where id = p_session_dog;
  else
    update session_dogs set runner_confirmed_return_at = coalesce(runner_confirmed_return_at, now())
    where id = p_session_dog;
  end if;

  select owner_confirmed_return_at is not null and runner_confirmed_return_at is not null
    into v_both from session_dogs where id = p_session_dog;

  if v_both then
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type,
       confirmation_kind, meta)
    values (sd.id, 'runner', v_runner, 'owner', sd.owner_profile_id, 'return',
      case when sd.return_override is not null then (sd.return_override->>'kind') else 'app_user' end,
      case when sd.return_override is not null then jsonb_build_object('override', sd.return_override) end);
    update session_dogs set
      custodian_type = 'owner', custodian_profile_id = owner_profile_id, custodian_external = null,
      custody_phase = 'resolved',
      responsible_profile_id = owner_profile_id,
      checked_out_at = coalesce(checked_out_at, now()),
      payout_state = case when payout_state = 'earned' then 'payable' else payout_state end
    where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '반환 완료', '위탁이 안전하게 끝났어요 — 리포트를 확인하세요', sd.booking_id),
      (v_runner, 'booking', '반환 완료', '반환이 확인됐어요 — 정산이 지급 대기로 넘어갑니다', sd.booking_id);
  else
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (case when v_side = 'owner' then v_runner else sd.owner_profile_id end,
            'booking', '반환 확인 요청', '상대방이 반환을 확인했어요 — 확인해주세요', sd.booking_id);
  end if;
  return jsonb_build_object('both', v_both);
end $$;

-- ---------- 커스터디 오버라이드 — witness(비당사자 호스트+증빙) / assisted · 자기 오버라이드 금지 ----------
create or replace function session_custody_override(
  p_session_dog uuid, p_side text, p_kind text, p_artifact jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record; v_runner uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if p_side not in ('owner','runner') then raise exception 'bad_side'; end if;
  if p_kind not in ('witness','assisted') then raise exception 'bad_kind'; end if;
  if sd.custody_phase <> 'return_pending' then raise exception 'not_return_pending'; end if;
  select runner_id into v_runner from bookings where id = sd.booking_id;
  -- 자기 오버라이드 금지: 호스트가 그 에지의 당사자면 불가 (백업 호스트/ops 몫)
  if auth.uid() = sd.owner_profile_id or auth.uid() = v_runner then raise exception 'self_override'; end if;
  -- witness는 강증빙 필수 (PIN/QR/서명/사진 — 비어있으면 거부)
  if p_kind = 'witness' and (p_artifact is null or p_artifact = '{}'::jsonb) then
    raise exception 'artifact_required';
  end if;

  update session_dogs set return_override = jsonb_build_object(
    'side', p_side, 'kind', case p_kind when 'witness' then 'host_witnessed_receipt' else 'authorized_person_pin' end,
    'artifact', p_artifact, 'by', auth.uid(), 'at', now())
  where id = p_session_dog;
  -- 해당 측 스탬프를 대신 기록 (assisted = 당사자 본인 확인을 호스트 기기로 수집)
  if p_side = 'owner' then
    update session_dogs set owner_confirmed_return_at = coalesce(owner_confirmed_return_at, now()) where id = p_session_dog;
  else
    update session_dogs set runner_confirmed_return_at = coalesce(runner_confirmed_return_at, now()) where id = p_session_dog;
  end if;
  -- 양측 완성 시 마무리는 남은 당사자의 session_confirm_return이 수행 (이벤트에 오버라이드 meta 부착)
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (case when p_side = 'owner' then sd.owner_profile_id else v_runner end,
          'community', '반환 확인 대리 기록', '호스트가 현장 확인으로 반환 확인을 기록했어요 (' || p_kind || ')', sd.session_id);
end $$;

-- ---------- 비상 이양 — 러너간 양측 수락 원자 6단계 · clinic/authority는 반환 국면 한정 ----------
create or replace function session_transfer_initiate(
  p_session_dog uuid, p_to_type text, p_to_profile uuid default null,
  p_to_external text default null, p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; v_runner uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  perform 1 from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  select runner_id into v_runner from bookings where id = sd.booking_id;
  if auth.uid() <> v_runner then raise exception 'not_custodian'; end if;
  if sd.custodian_type <> 'runner' then raise exception 'not_in_runner_custody'; end if;
  if p_to_type = 'runner' then
    if p_to_profile is null then raise exception 'target_required'; end if;
    if sd.custody_phase not in ('with_custodian','return_pending') then raise exception 'bad_phase'; end if;
  elsif p_to_type in ('clinic','authority','authorized_person') then
    -- 외부 이양은 러너 보유 어느 국면에서도 개시 가능 — **부상은 주행 중에 일어난다.**
    -- 주행 전·중 확정은 accept가 원자 인시던트 경로(런 종료·incident_review·배정 폐쇄·인시던트 개설)로 처리.
    if sd.custody_phase not in ('with_custodian','return_pending') then raise exception 'bad_phase'; end if;
    if coalesce(trim(p_to_external), '') = '' and p_to_profile is null then raise exception 'target_required'; end if;
  else
    raise exception 'bad_target_type';
  end if;
  update session_dogs set custody_phase = 'transfer_pending',
    pending_transfer = jsonb_build_object('toType', p_to_type, 'toProfile', p_to_profile,
      'toExternal', p_to_external, 'reason', p_reason, 'by', auth.uid(), 'at', now())
  where id = p_session_dog;
  if p_to_type = 'runner' then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (p_to_profile, 'booking', '비상 이양 요청', '강아지 커스터디 이양 요청이 왔어요 — 수락 여부를 결정하세요', sd.session_id);
  end if;
end $$;

create or replace function session_transfer_accept(p_session_dog uuid, p_artifact jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_old_runner uuid; v_t jsonb; v_load int; v_cap int; v_ev uuid;
  v_bst text; v_inc uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.custody_phase <> 'transfer_pending' or sd.pending_transfer is null then raise exception 'no_pending_transfer'; end if;
  v_t := sd.pending_transfer;
  select runner_id into v_old_runner from bookings where id = sd.booking_id;

  if v_t->>'toType' = 'runner' then
    if auth.uid() <> (v_t->>'toProfile')::uuid then raise exception 'not_transfer_target'; end if;
    -- 수신 러너 검증: 티어 + 부하 (물리적으로 잡은 모든 개 ≤ 캡)
    v_cap := _club_runner_cap(auth.uid());
    if coalesce(v_cap, 0) = 0 then raise exception 'not_certified_runner'; end if;
    select count(*) into v_load from session_dogs x
    where x.custodian_type = 'runner' and x.custodian_profile_id = auth.uid()
      and x.custody_phase in ('with_custodian','return_pending','transfer_pending');
    if v_load >= v_cap then raise exception 'handler_overloaded'; end if;
    -- 원자 6단계: 배정 이벤트(교체·수락) → 부킹 러너 교체 → 커스터디 이벤트 → 세그먼트 → 프로젝션 → 알림
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_old_runner, 'replaced', 'emergency_transfer', auth.uid()),
           (sd.id, auth.uid(), 'accepted', 'emergency_transfer', auth.uid());
    update bookings set runner_id = auth.uid() where id = sd.booking_id;
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type, confirmation_kind, reason)
    values (sd.id, 'runner', v_old_runner, 'runner', auth.uid(), 'emergency_transfer', 'app_user', v_t->>'reason')
    returning id into v_ev;
    update dog_run_segments set left_at = now(), transfer_event_id = v_ev
    where session_dog_id = sd.id and left_at is null;
    insert into dog_run_segments (session_dog_id, run_id, runner_profile_id, joined_at, transfer_event_id)
    select sd.id, r.id, auth.uid(), now(), v_ev from runs r where r.booking_id = sd.booking_id;
    update session_dogs set
      custodian_profile_id = auth.uid(), custody_phase =
        case when exists (select 1 from bookings b where b.id = sd.booking_id and b.status = 'completed')
             then 'return_pending' else 'with_custodian' end,
      responsible_profile_id = auth.uid(),
      current_runner_profile_id = auth.uid(),
      runner_confirmed_return_at = null,                 -- 새 러너 기준으로 반환 확인 재시작
      pending_transfer = null
    where id = sd.id;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '담당 러너 변경', '비상 이양으로 담당 러너가 변경됐어요 — 새 담당을 확인하세요', sd.booking_id),
      (s.host_profile_id, 'community', '비상 이양 완료', '러너간 커스터디 이양이 완료됐어요', sd.session_id);
  else
    -- clinic/authority/authorized_person: 개시 러너가 증빙과 함께 확정 (수신자는 앱 사용자가 아님)
    if auth.uid() <> (v_t->>'by')::uuid then raise exception 'not_transfer_target'; end if;
    if p_artifact is null or p_artifact = '{}'::jsonb then raise exception 'artifact_required'; end if;
    select status::text into v_bst from bookings where id = sd.booking_id;

    -- [주행 전·중 비상 = 원자 인시던트 경로] 단순 거부 금지 — 부상견은 지금 병원에 가야 한다.
    -- ① 런 종료(end_reason=incident — 0001 이넘에 이미 존재) ② 부킹 incident_review
    -- (전이 맵 허용: picked_up|active → incident_review; 완료 통계·패치·리뷰 흐름 오염 없음)
    -- ③ 배정 폐쇄(revoked) ④ 인시던트 개설 + 대상(dog·session·booking) + 증빙 연결
    if v_bst in ('picked_up','active') then
      update runs set ended_at = now(), end_reason = 'incident',
        condition_note = coalesce(v_t->>'reason', '외부 커스터디 이양')
      where booking_id = sd.booking_id and ended_at is null;
      update bookings set status = 'incident_review' where id = sd.booking_id;
      insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
      values (sd.id, v_old_runner, 'revoked', 'external_custody', auth.uid());
      insert into club_incidents (session_id, severity, state, opened_by, summary)
      values (sd.session_id, 'S2', 'open', auth.uid(),
              coalesce(v_t->>'reason', '주행 중 외부 이양') || ' → ' || coalesce(v_t->>'toExternal', '외부 기관'))
      returning id into v_inc;
      insert into club_incident_subjects (incident_id, subject_type, subject_id) values
        (v_inc, 'dog', sd.dog_id), (v_inc, 'session', sd.session_id), (v_inc, 'booking', sd.booking_id);
      insert into club_incident_evidence (incident_id, kind, payload, created_by)
      values (v_inc, 'document', p_artifact, auth.uid());
    end if;

    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, to_external,
       event_type, confirmation_kind, reason, incident_id, meta)
    values (sd.id, 'runner', v_old_runner, v_t->>'toType', (v_t->>'toProfile')::uuid, v_t->>'toExternal',
      case when v_t->>'toType' = 'clinic' then 'vet_transfer' else 'authority_transfer' end,
      case when v_t->>'toType' = 'clinic' then 'clinic_receipt' else 'ops_attestation' end,
      v_t->>'reason', v_inc, jsonb_build_object('artifact', p_artifact))
    returning id into v_ev;
    update dog_run_segments set left_at = now(), transfer_event_id = v_ev
    where session_dog_id = sd.id and left_at is null;
    update session_dogs set
      custodian_type = v_t->>'toType', custodian_profile_id = (v_t->>'toProfile')::uuid,
      custodian_external = v_t->>'toExternal',
      custody_phase = 'with_custodian',                  -- 외부 커스터디언 보유 중 (종단 허용목록 통과형)
      termination_type = case when v_t->>'toType' = 'clinic' then 'vet_transfer' else termination_type end,
      payout_hold = 'held', payout_hold_reason = 'external_custody',
      pending_transfer = null
    where id = sd.id;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'safety', '외부 커스터디 이양', coalesce(v_t->>'toExternal','외부 기관') || '(으)로 커스터디가 이양됐어요 — 즉시 확인하세요', sd.session_id),
      (s.host_profile_id, 'safety', '외부 커스터디 이양', '위탁견이 외부 커스터디로 이양됐어요 — 케이스 확인 필요', sd.session_id);
  end if;
end $$;

-- 이양 취소 — 수락 거부·부하 초과 후 transfer_pending 좌초 방지 (개시자 또는 호스트)
create or replace function session_transfer_cancel(p_session_dog uuid) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record; v_bst text;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.custody_phase <> 'transfer_pending' or sd.pending_transfer is null then
    raise exception 'no_pending_transfer';
  end if;
  if auth.uid() <> (sd.pending_transfer->>'by')::uuid and auth.uid() <> s.host_profile_id then
    raise exception 'not_initiator';
  end if;
  select status::text into v_bst from bookings where id = sd.booking_id;
  if sd.pending_transfer->>'toType' = 'runner' and (sd.pending_transfer->>'toProfile') is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values ((sd.pending_transfer->>'toProfile')::uuid, 'booking', '이양 요청 취소',
            '커스터디 이양 요청이 취소됐어요', sd.session_id);
  end if;
  update session_dogs set
    custody_phase = case when v_bst = 'completed' then 'return_pending' else 'with_custodian' end,
    pending_transfer = null
  where id = p_session_dog;
end $$;

-- ---------- 종료 게이팅 v2 — 종단 허용목록 (러너·호스트 보유는 절대 종단 아님) ----------
create or replace function _club_dogs_unresolved(p_session uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from session_dogs sd
  where sd.session_id = p_session and sd.custody = 'runner_delegated'
    and (sd.custody_phase in ('outbound_pending','transfer_pending','return_pending')
         or (sd.custodian_type in ('runner','host') and sd.custody_phase <> 'resolved'
             and exists (select 1 from bookings b where b.id = sd.booking_id
                         and b.status in ('picked_up','active','completed'))));
$$;
revoke execute on function _club_dogs_unresolved(uuid) from public, anon, authenticated;

create or replace function club_finish_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_name text; v_teams int; v_dogs int; v_when timestamptz; v_ids uuid[];
begin
  if _club_dogs_unresolved(p_session) > 0 then raise exception 'dogs_not_returned'; end if;
  -- [비평 반영] 클리닉 커스터디는 종단 허용목록을 통과하지만, 열린 인시던트는 케이스 오너가
  -- 배정된 뒤에만 세션을 닫을 수 있다 — 케이스는 세션 종료 후에도 독립적으로 계속된다.
  if exists (select 1 from club_incidents
             where session_id = p_session and state <> 'resolved' and case_owner is null) then
    raise exception 'incident_unassigned';
  end if;
  update club_sessions set status = 'done'
  where id = p_session and host_profile_id = auth.uid() and status in ('open', 'full')
  returning club_id, scheduled_at into v_club, v_when;
  if v_club is null then raise exception 'not_host_or_closed'; end if;
  select name into v_name from clubs where id = v_club;
  select count(*) into v_teams from session_people where session_id = p_session and attendance = 'checked_in';
  select count(*) into v_dogs from session_dogs where session_id = p_session and checked_in_at is not null;
  if v_teams > 0 then
    insert into feed_posts (author_id, body, meta)
    values (auth.uid(), null, jsonb_build_object(
      'club', v_name, 'sessionId', p_session, 'teams', v_teams, 'dogs', v_dogs,
      'sessionAt', v_when, 'badges', jsonb_build_array('🏁 하이클럽')));
    insert into notifications (profile_id, kind, title, body, ref_id)
    select sp.profile_id, 'community', v_name || ' 리캡 도착', v_teams || '팀이 함께 달렸어요 — 피드에서 확인하세요', p_session
    from session_people sp where sp.session_id = p_session and sp.attendance = 'checked_in'
      and sp.profile_id <> auth.uid();
  end if;
  select coalesce(array_agg(id), '{}') into v_ids
  from bookings where club_session_id = p_session and status = 'matching';
  perform _club_refund_bookings(v_ids, 'club_not_picked_up',
    '위탁 미진행 — 전액 환불', '세션이 끝났지만 위탁 러닝이 진행되지 않았어요 — 전액 환불 처리돼요');
  perform _club_refund_confirmed(p_session, 'club_not_picked_up');
end $$;

-- ---------- 인시던트 최소 운영 RPC (R6 전 디버그·종료 게이팅용 — 전체 UX는 R6) ----------
create or replace function club_incident_assign(p_incident uuid, p_owner uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_session uuid;
begin
  perform _club_require_v2();
  select session_id into v_session from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  if not exists (select 1 from club_sessions where id = v_session and host_profile_id = auth.uid()) then
    raise exception 'not_host';
  end if;
  update club_incidents set case_owner = coalesce(p_owner, auth.uid()),
    state = case when state = 'open' then 'investigating' else state end
  where id = p_incident;
end $$;

create or replace function club_incident_resolve(p_incident uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_session uuid; v_owner uuid;
begin
  perform _club_require_v2();
  select session_id, case_owner into v_session, v_owner from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  if auth.uid() <> v_owner and not exists
    (select 1 from club_sessions where id = v_session and host_profile_id = auth.uid()) then
    raise exception 'not_case_owner';
  end if;
  if p_note is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (p_incident, 'text', jsonb_build_object('note', p_note, 'at', now()), auth.uid());
  end if;
  update club_incidents set state = 'resolved', resolved_at = now() where id = p_incident;
end $$;

grant execute on function club_incident_assign(uuid, uuid) to authenticated;
grant execute on function club_incident_resolve(uuid, text) to authenticated;

-- 디버그 릴리스 래퍼 — service role 없이 실기기에서 릴리스 크론을 시험하기 위한 게이트 통로.
-- 허용목록(_club_require_v2) 한정. R6 운영 콘솔이 생기면 폐기 [디버그 시대 한정].
create or replace function club_debug_release_payouts() returns int
language plpgsql security definer set search_path = public as $$
begin
  perform _club_require_v2();
  return club_release_payouts();
end $$;
grant execute on function club_debug_release_payouts() to authenticated;

-- ---------- 지급 릴리스 (일일 배치 — 모의 시대엔 상태 전이만) ----------
create or replace function club_release_payouts() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  -- [직렬화 법] payout_hold가 릴리스 차단의 직렬화 지점이다: 지급을 막아야 하는 모든 인시던트
  -- 개설 RPC는 그 강아지의 세션 락 아래에서 payout_hold='held'를 함께 써야 한다 (clinic 이양이
  -- 그 예). 아래 인시던트 존재 검사는 2차 방어선(defense-in-depth)이지 락 대체가 아니다.
  -- 멱등: payable → released 단방향, 재실행 시 0행.
  update session_dogs sd set payout_state = 'released'
  where sd.payout_state = 'payable' and sd.payout_hold = 'none' and sd.custody_phase = 'resolved'
    and not exists (
      select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
      where i.state <> 'resolved'
        and ((s.subject_type = 'dog' and s.subject_id = sd.dog_id)
          or (s.subject_type = 'booking' and s.subject_id = sd.booking_id)));
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function club_release_payouts() from public, anon, authenticated;
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('club-payout-release', '0 18 * * *', 'select club_release_payouts()');  -- KST 03:00
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

-- ---------- 축 계산 v3 — 커스터디·payout 1차화 (레거시 백필 규칙 포함) ----------
create or replace function _club_compute_axes(sd session_dogs) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bst text; v_brunner uuid; v_bcancel text; v_run_reason text;
  v_ev record; j jsonb := '{}';
begin
  if sd.booking_id is not null then
    select status::text, runner_id, cancel_reason into v_bst, v_brunner, v_bcancel
    from bookings where id = sd.booking_id;
  end if;

  if sd.custody = 'owner_handled' then
    return jsonb_build_object(
      'service_state', null, 'completion_outcome', null, 'termination_type', null,
      'service_reason', null, 'cancelled_by', null,
      'charge_state', 'none', 'hold_status', coalesce(sd.hold_status, 'none'), 'refund_state', 'none',
      'payout_state', 'none', 'payout_hold', 'none',
      'assignment_state', 'unassigned', 'current_runner_profile_id', null,
      'custodian_type', 'owner', 'custodian_profile_id', sd.owner_profile_id,
      'custody_phase', 'with_custodian');
  end if;

  -- 서비스 축 (R1과 동일, termination은 이양이 덮어쓸 수 있음 — 저장값 우선)
  if sd.approval = 'pending' then
    j := j || jsonb_build_object('service_state','requested');
  elsif sd.approval = 'rejected' then
    j := j || jsonb_build_object('service_state','ended','completion_outcome','no_service',
      'termination_type','cancelled','service_reason','host_rejected','cancelled_by','host');
  elsif sd.approval = 'approved' then
    if sd.booking_id is null then
      j := j || jsonb_build_object('service_state','approved');
    elsif v_bst in ('matching','confirmed') then
      j := j || jsonb_build_object('service_state','confirmed');
    elsif v_bst in ('picked_up','active') then
      j := j || jsonb_build_object('service_state','in_service');
    elsif v_bst = 'completed' then
      select end_reason::text into v_run_reason from runs where booking_id = sd.booking_id;
      j := j || jsonb_build_object('service_state','ended',
        'completion_outcome', case when v_run_reason = 'completed' then 'completed' else 'partial' end,
        'termination_type', coalesce(sd.termination_type,
          case when v_run_reason = 'completed' then 'normal' else 'early_return' end));
    elsif v_bst = 'incident_review' then
      -- [R2] 주행 전·중 외부 이양/인시던트: incident_review = 부킹의 상업/관리 검토 상태일 뿐,
      -- 서비스 축은 명시적으로 ended (모델에 없는 'suspended' 암묵 상태 금지).
      -- partial/no_service 분기점 = **런 시작 여부** (인계만으로는 러닝 서비스 시작이 아니다)
      j := j || jsonb_build_object('service_state','ended',
        'completion_outcome', case when exists (select 1 from runs r
            where r.booking_id = sd.booking_id and r.started_at is not null)
          then 'partial' else 'no_service' end,
        'termination_type', coalesce(sd.termination_type, 'cancelled'),
        'service_reason', 'incident', 'cancelled_by', null);
    else
      j := j || jsonb_build_object('service_state','ended','completion_outcome','no_service',
        'termination_type','cancelled',
        'service_reason', case v_bcancel
          when 'club_session_cancelled' then 'session_cancelled'
          when 'club_runner_withdrawn' then 'runner_capacity'
          when 'club_not_picked_up' then 'no_show_owner' else 'other' end,
        'cancelled_by', 'system');
    end if;
  end if;

  -- 돈 축 (R1 규칙 유지 — payout은 R2부터 1차 저장·패스스루)
  if sd.booking_id is not null then
    j := j || jsonb_build_object('charge_state','paid');
    if v_bst in ('refund_pending','cancelled_runner','expired','cancelled_owner') then
      j := j || jsonb_build_object('refund_state','pending');
    else
      j := j || jsonb_build_object('refund_state','none');
    end if;
  else
    j := j || jsonb_build_object(
      'charge_state', case when sd.hold_status = 'active' and sd.hold_expires_at > now() then 'hold' else 'none' end,
      'refund_state','none');
  end if;
  j := j || jsonb_build_object('hold_status', coalesce(sd.hold_status,'none'),
    'payout_state', coalesce(sd.payout_state,'none'), 'payout_hold', coalesce(sd.payout_hold,'none'));

  -- 배정 캐시 (R3 전까지 부킹 파생)
  if v_brunner is not null and v_bst in ('confirmed','picked_up','active','completed') then
    j := j || jsonb_build_object('assignment_state','accepted','current_runner_profile_id', v_brunner);
  else
    j := j || jsonb_build_object('assignment_state','unassigned','current_runner_profile_id', null);
  end if;

  -- 커스터디: 최신 이벤트가 진실 (이벤트 없으면 레거시 규칙: checked_out→owner/resolved, 아니면 responsible)
  -- 정렬은 seq만 — occurred_at은 같은 tx에서 전부 동일해 타이브레이크가 무작위였다 (하네스가 검출)
  select * into v_ev from dog_custody_events where session_dog_id = sd.id
  order by seq desc limit 1;
  if v_ev.id is not null then
    j := j || jsonb_build_object('custodian_type', v_ev.to_type,
      'custodian_profile_id', v_ev.to_profile_id);
    if v_ev.to_type = 'runner' then
      j := j || jsonb_build_object('custody_phase',
        case when sd.custody_phase = 'transfer_pending' then 'transfer_pending'
             when v_bst = 'completed' then 'return_pending' else 'with_custodian' end);
    else
      j := j || jsonb_build_object('custody_phase',
        case when v_ev.to_type = 'owner' then 'resolved' else 'with_custodian' end);
    end if;
  elsif sd.checked_out_at is not null then
    j := j || jsonb_build_object('custodian_type','owner','custodian_profile_id', sd.owner_profile_id,
      'custody_phase','resolved');
  elsif sd.responsible_profile_id is distinct from sd.owner_profile_id then
    j := j || jsonb_build_object('custodian_type','runner','custodian_profile_id', sd.responsible_profile_id,
      'custody_phase', case when v_bst = 'completed' then 'return_pending' else 'with_custodian' end);
  else
    j := j || jsonb_build_object('custodian_type','owner','custodian_profile_id', sd.owner_profile_id,
      'custody_phase', case when sd.custody_phase = 'resolved' then 'resolved' else 'with_custodian' end);
  end if;
  return j;
end $$;

-- ---------- UI 프로젝션 v2 — 커스터디 1급 ('completed' 소비자 감사가 잡은 누수 수정) ----------
-- 0040 프로젝션은 서비스 종료 = '완료'로 표기했다 — R2에선 정산이 끝나도 반환 전이면 '완료'가
-- 거짓말이다. 커스터디 국면이 서비스 축보다 먼저 말한다.
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
        when sd.service_state = 'confirmed' and sd.assignment_state = 'unassigned' then '결제 완료 — 배정 대기'
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
    if exists (select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
               where s.subject_type = 'dog' and s.subject_id = sd.dog_id and i.state <> 'resolved') then
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

comment on function club_dog_ui_state is
  'R2(0045): 커스터디 1급 프로젝션 — 반환/이양/외부 보호가 서비스 축보다 먼저 말한다. 완료 표기는 resolved 한정';

-- ---------- 보드 v3 — R2 커스터디·payout 필드 노출 (최신 정의 = 0043, grep 확인) ----------
create or replace function club_delegation_board(p_session uuid) returns jsonb
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
      'openIncidents', (select count(*) from club_incidents i
                        where i.session_id = s.id and i.state <> 'resolved'),
      'unassignedIncidents', (select count(*) from club_incidents i
                              where i.session_id = s.id and i.state <> 'resolved' and i.case_owner is null)
    ),
    'runners', coalesce((
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
      where a.session_id = s.id and a.status = 'committed'), '[]'::jsonb),
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
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        and (d.service_state is distinct from 'ended' or d.booking_id is not null)), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

-- 커스터디 이벤트 열람 — 당사자(보호자·현 러너)·호스트 한정 definer 초크포인트 (테이블은 봉인 유지)
create or replace function club_dog_custody_events(p_session_dog uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sd record; v_runner uuid;
begin
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select runner_id into v_runner from bookings where id = sd.booking_id;
  if auth.uid() <> sd.owner_profile_id and auth.uid() is distinct from v_runner
     and not exists (select 1 from club_sessions
                     where id = sd.session_id and host_profile_id = auth.uid()) then
    raise exception 'not_party';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'seq', e.seq, 'eventType', e.event_type,
    'fromType', e.from_type, 'fromProfileId', e.from_profile_id,
    'toType', e.to_type, 'toProfileId', e.to_profile_id, 'toExternal', e.to_external,
    'confirmationKind', e.confirmation_kind, 'occurredAt', e.occurred_at,
    'reason', e.reason, 'incidentId', e.incident_id) order by e.seq)
    from dog_custody_events e where e.session_dog_id = p_session_dog), '[]'::jsonb);
end $$;

-- 세션 인시던트 열람 — 호스트·케이스 오너·대상 강아지 보호자/러너 한정
create or replace function club_session_incidents(p_session uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from club_sessions where id = p_session and host_profile_id = auth.uid())
     and not exists (select 1 from club_incidents i where i.session_id = p_session and i.case_owner = auth.uid())
     and not exists (select 1 from session_dogs d left join bookings b on b.id = d.booking_id
                     where d.session_id = p_session
                       and (d.owner_profile_id = auth.uid() or b.runner_id = auth.uid())) then
    raise exception 'not_party';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', i.id, 'severity', i.severity, 'state', i.state, 'summary', i.summary,
    'caseOwner', i.case_owner, 'openedAt', i.opened_at, 'resolvedAt', i.resolved_at) order by i.opened_at)
    from club_incidents i where i.session_id = p_session), '[]'::jsonb);
end $$;

grant execute on function club_dog_custody_events(uuid) to authenticated;
grant execute on function club_session_incidents(uuid) to authenticated;

-- ---------- 백필: 레거시 완료·체크아웃 행 = resolved/released ----------
update session_dogs sd set payout_state = 'released'
where sd.custody = 'runner_delegated' and sd.checked_out_at is not null
  and exists (select 1 from bookings b where b.id = sd.booking_id and b.status = 'completed')
  and exists (select 1 from ledger_items l where l.booking_id = sd.booking_id)
  and sd.payout_state = 'none';
update session_dogs set id = id;   -- 전행 재동기화 (BEFORE 트리거)

grant execute on function session_confirm_return(uuid) to authenticated;
grant execute on function session_custody_override(uuid, text, text, jsonb) to authenticated;
grant execute on function session_transfer_initiate(uuid, text, uuid, text, text) to authenticated;
grant execute on function session_transfer_accept(uuid, jsonb) to authenticated;
grant execute on function session_transfer_cancel(uuid) to authenticated;

comment on function session_confirm_return is
  'R2(0045): 양측 반환 확인 — 완성 시 return 이벤트·커스터디 owner·resolved·payout payable';
comment on trigger club_custody_transition_v2 on bookings is
  'R2(0045): picked_up=아웃바운드 이벤트·러너 커스터디 / completed=return_pending 유지 (정산≠반환)';
comment on function club_finish_session is
  'R2(0045): 종단 허용목록 게이팅 — 러너·호스트 보유/미해결 국면이 있으면 dogs_not_returned';
