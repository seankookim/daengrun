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
  select * into v_sd from session_dogs where booking_id = new.id;
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
    -- 주행 전·중의 외부 이양 = 인시던트 경로 (R6 배선까지 명시 거부 — 조용한 우회 금지)
    if sd.custody_phase <> 'return_pending' then raise exception 'use_incident_flow'; end if;
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
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, to_external,
       event_type, confirmation_kind, reason, meta)
    values (sd.id, 'runner', v_old_runner, v_t->>'toType', (v_t->>'toProfile')::uuid, v_t->>'toExternal',
      case when v_t->>'toType' = 'clinic' then 'vet_transfer' else 'authority_transfer' end,
      case when v_t->>'toType' = 'clinic' then 'clinic_receipt' else 'ops_attestation' end,
      v_t->>'reason', jsonb_build_object('artifact', p_artifact));
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

-- ---------- 지급 릴리스 (일일 배치 — 모의 시대엔 상태 전이만) ----------
create or replace function club_release_payouts() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update session_dogs set payout_state = 'released'
  where payout_state = 'payable' and payout_hold = 'none' and custody_phase = 'resolved';
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
