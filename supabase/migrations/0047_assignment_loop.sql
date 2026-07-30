-- ═══ 0047: R3 — 배정 루프 (Model A 고정: 호스트 제안 → 러너 수락 → 보호자 이의권) ═══
-- club-run-logic.md v3.3 §5·§6·§16 R3.
-- v1 직접 배정(호스트가 러너 의사 없이 확정)은 Model A 위반 — 제안/수락으로 대체.
-- 자기 제안(호스트=대상 러너)은 수락이 자명하므로 즉시 수락 (솔로 테스트·호스트 러너 경로 보존).
-- 보호자는 제안 중 후보를 보지 못한다 (러너 프라이버시 — 거절은 보이지 않는 이탈).
-- 배정 축은 이벤트 파생 캐시: assignment_events(단조 seq)가 진실, 컬럼은 프로젝션.

-- ---------- 스키마 ----------
alter table session_dogs
  add column if not exists proposed_runner_profile_id uuid references profiles(id),
  add column if not exists proposal_expires_at timestamptz,     -- 실시간 만료 (술어가 now() 직접 평가)
  add column if not exists objection_used boolean not null default false;

alter table club_sessions
  add column if not exists backup_host_profile_id uuid references profiles(id),
  add column if not exists original_host_profile_id uuid references profiles(id),
  add column if not exists host_assumed_at timestamptz;

-- [0045 교훈 선제 적용] 같은 tx의 이벤트는 occurred_at 동일 — 단조 seq가 유일 정렬 진실
alter table assignment_events add column if not exists seq bigint generated always as identity;
create index if not exists assignment_events_sd_seq_idx on assignment_events (session_dog_id, seq desc);

-- ---------- 전이 맵 확장 (최신 정의 = 0005, grep 확인): confirmed → matching ----------
-- 배정 철회/이의(인계 전)는 부킹을 풀로 되돌린다 — 러너 없는 confirmed는 거짓 상태.
create or replace function enforce_booking_transition() returns trigger
language plpgsql as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'draft'          then new.status in ('quoted','expired')
    when 'quoted'         then new.status in ('payment_hold','expired')
    when 'payment_hold'   then new.status in ('matching','expired','refund_pending')
    when 'matching'       then new.status in ('runner_pending','confirmed','expired','refund_pending','cancelled_owner')
    when 'runner_pending' then new.status in ('confirmed','matching','expired','cancelled_owner')
    -- [R3] matching 추가 — 배정 철회/보호자 이의 (인계 전 한정, 클럽 RPC만 수행)
    when 'confirmed'      then new.status in ('matching','runner_enroute','picked_up','cancelled_owner','cancelled_runner','no_show')
    when 'runner_enroute' then new.status in ('picked_up','no_show','cancelled_runner','incident_review')
    when 'picked_up'      then new.status in ('active','incident_review')
    when 'active'         then new.status in ('completed','incident_review')
    when 'completed'      then new.status in ('incident_review')
    else new.status in ('refund_pending')
  end;
  if not ok then
    raise exception 'invalid booking transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;

-- ---------- 러너 부하 (제안 예약 포함) — 개인 단속이 1차 (§6) ----------
-- handler_load = 수락된 위탁 + 활성 제안(실시간) + 본인 동반견. 집계는 개요일 뿐.
create or replace function _club_runner_load(p_session uuid, p_runner uuid) returns int
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from session_dogs x join bookings b on b.id = x.booking_id
     where x.session_id = p_session and x.custody = 'runner_delegated'
       and b.runner_id = p_runner and b.status in ('confirmed','picked_up','active','completed'))
  + (select count(*) from session_dogs x join bookings b on b.id = x.booking_id
     where x.session_id = p_session and x.custody = 'runner_delegated'
       and x.proposed_runner_profile_id = p_runner and x.proposal_expires_at > now()
       and b.status = 'matching')
  + (select count(*) from session_dogs x
     where x.session_id = p_session and x.custody = 'owner_handled'
       and x.owner_profile_id = p_runner and x.service_state is distinct from 'ended');
$$;
revoke execute on function _club_runner_load(uuid, uuid) from public, anon, authenticated;

-- ---------- 제안 (호스트) — confirmed 위 제안 = 암묵 철회(replaced) 후 제안 ----------
create or replace function session_propose_dog(p_session_dog uuid, p_runner uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_cap int; v_bstatus text; v_old_runner uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if s.status not in ('open', 'full') then raise exception 'session_closed'; end if;
  if now() < s.scheduled_at - interval '2 hours' or now() > s.scheduled_at + interval '6 hours' then
    raise exception 'assign_window';
  end if;
  if sd.custody <> 'runner_delegated' or sd.approval <> 'approved' or sd.booking_id is null then
    raise exception 'not_approved';
  end if;

  select delegated_capacity into v_cap from session_runner_assignments
  where session_id = sd.session_id and runner_profile_id = p_runner and status = 'committed';
  if v_cap is null then raise exception 'runner_not_committed'; end if;
  if not exists (select 1 from session_people
                 where session_id = sd.session_id and profile_id = p_runner and attendance = 'checked_in') then
    raise exception 'runner_not_checked_in';
  end if;

  select status::text, runner_id into v_bstatus, v_old_runner from bookings where id = sd.booking_id for update;
  if v_bstatus not in ('matching', 'confirmed') then raise exception 'already_handed_off'; end if;
  -- 활성 제안이 이미 있으면 이중 제안 금지 (철회 후 재제안 — 조용한 교체 없음)
  if v_bstatus = 'matching' and sd.proposed_runner_profile_id is not null
     and sd.proposal_expires_at > now() then
    raise exception 'proposal_active';
  end if;
  -- 개인 부하 (수락 + 활성 제안 + 동반견) — 이 제안까지 캡 안이어야 한다
  if _club_runner_load(sd.session_id, p_runner) >= v_cap then raise exception 'runner_cap_full'; end if;

  -- confirmed 위 제안 = 기존 배정 암묵 철회 (인계 전 한정 — 위에서 검증됨)
  if v_bstatus = 'confirmed' then
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_old_runner, 'replaced', 'host_reassign', auth.uid());
    update bookings set runner_id = null, status = 'matching',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  end if;

  insert into assignment_events (session_dog_id, runner_profile_id, event, created_by)
  values (sd.id, p_runner, 'proposed', auth.uid());

  if p_runner = auth.uid() then
    -- 자기 제안 = 자명한 수락 (호스트 러너·솔로 테스트) — Model A의 수락이 암묵 성립
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, p_runner, 'accepted', 'self_proposal', auth.uid());
    update bookings set runner_id = p_runner, status = 'confirmed',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null
    where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '담당 러너 배정',
       (select name from profiles where id = p_runner) || ' 러너가 아이의 담당으로 확정됐어요 — 집결지에서 인계를 확인하세요', sd.booking_id);
  else
    -- 제안 대기: 보호자에게는 후보 없이 진행 상태만 (러너 프라이버시) — 알림도 러너에게만
    update session_dogs set proposed_runner_profile_id = p_runner,
      proposal_expires_at = now() + interval '5 minutes'
    where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (p_runner, 'booking', '위탁 배정 제안',
      (select name from dogs where id = sd.dog_id) || ' 담당 제안이 왔어요 — 5분 안에 수락 여부를 결정하세요', sd.session_id);
  end if;
end $$;

-- v1 이름 보존: session_assign_dog = 제안 흐름의 별칭 (기존 호출부·랩 호환)
create or replace function session_assign_dog(p_session_dog uuid, p_runner uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform session_propose_dog(p_session_dog, p_runner);
end $$;

-- ---------- 제안 응답 (러너) — 실시간 만료: 술어가 now() 직접 평가 ----------
create or replace function session_proposal_respond(p_session_dog uuid, p_accept boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record; v_bstatus text;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.proposed_runner_profile_id is null or auth.uid() <> sd.proposed_runner_profile_id then
    raise exception 'no_proposal_for_you';
  end if;
  if sd.proposal_expires_at <= now() then raise exception 'proposal_expired'; end if;
  select status::text into v_bstatus from bookings where id = sd.booking_id for update;
  if v_bstatus <> 'matching' then raise exception 'not_pending'; end if;

  if p_accept then
    -- 수락 시점 부하 재검증 (제안 후 다른 수락으로 캡이 찼을 수 있다 — 락 후 현재값)
    if _club_runner_load(sd.session_id, auth.uid())
       - 1  -- 본인의 이 활성 제안은 부하에 이미 계상돼 있다 — 수락은 제안→수락 치환
       >= coalesce((select delegated_capacity from session_runner_assignments
                    where session_id = sd.session_id and runner_profile_id = auth.uid()
                      and status = 'committed'), 0) then
      raise exception 'runner_cap_full';
    end if;
    insert into assignment_events (session_dog_id, runner_profile_id, event, created_by)
    values (sd.id, auth.uid(), 'accepted', auth.uid());
    update bookings set runner_id = auth.uid(), status = 'confirmed',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null
    where id = p_session_dog;
    -- 이제야 보호자에게 확정 러너 카드가 공개된다 (Model A)
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '담당 러너 배정',
       (select name from profiles where id = auth.uid()) || ' 러너가 아이의 담당으로 확정됐어요 — 집결지에서 인계를 확인하세요', sd.booking_id),
      (s.host_profile_id, 'community', '배정 수락',
       (select name from dogs where id = sd.dog_id) || ' 배정이 수락됐어요', sd.session_id);
  else
    -- 거절: 보이지 않는 이탈 — 호스트에게만, 보호자 알림 없음
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, auth.uid(), 'declined', p_reason, auth.uid());
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null
    where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.host_profile_id, 'community', '배정 거절',
      (select name from dogs where id = sd.dog_id) || ' 제안이 거절됐어요 — 다른 러너에게 제안하세요', sd.session_id);
  end if;
end $$;

-- ---------- 제안 취소 (호스트) ----------
create or replace function session_proposal_revoke(p_session_dog uuid) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.proposed_runner_profile_id is null then raise exception 'no_proposal'; end if;
  insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
  values (sd.id, sd.proposed_runner_profile_id, 'revoked', 'host_cancel_proposal', auth.uid());
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (sd.proposed_runner_profile_id, 'community', '배정 제안 취소', '위탁 배정 제안이 취소됐어요', sd.session_id);
  update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null
  where id = p_session_dog;
end $$;

-- ---------- 배정 철회 (호스트, 인계 전만) → replacement_needed ----------
create or replace function session_assignment_revoke(p_session_dog uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record; v_bstatus text; v_runner uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  select status::text, runner_id into v_bstatus, v_runner from bookings where id = sd.booking_id for update;
  if v_bstatus <> 'confirmed' or v_runner is null then raise exception 'not_assigned'; end if;
  perform 1 from bookings where id = sd.booking_id
    and (owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null);
  if found then raise exception 'already_handed_off'; end if;
  -- 상습 철회는 이벤트 조회로 추적한다 (스트라이크 정책 수치 = Sean) — 기록이 정책보다 먼저
  insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
  values (sd.id, v_runner, 'revoked', coalesce(p_reason, 'host_revoke'), auth.uid());
  update bookings set runner_id = null, status = 'matching',
    owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
  where id = sd.booking_id;
  -- 즉시 재동기화 (deferred 포크는 커밋 시점 — 같은 tx의 후속 판단이 낡은 캐시를 보면 안 된다)
  update session_dogs set id = id where id = p_session_dog;
  insert into notifications (profile_id, kind, title, body, ref_id) values
    (v_runner, 'booking', '배정 철회', '위탁 배정이 철회됐어요', sd.session_id),
    (sd.owner_profile_id, 'booking', '담당 재배정 중', '담당 러너를 다시 배정하고 있어요 — 자리는 유지돼요', sd.booking_id);
end $$;

-- ---------- 보호자 이의 — 선호(T-20까지·1회 무료·사유 필수) / 안전(인계까지) (§5) ----------
create or replace function session_owner_objection(
  p_session_dog uuid, p_kind text, p_reason text, p_want_refund boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record; v_bstatus text; v_runner uuid;
begin
  perform _club_require_v2();
  if p_kind not in ('preference', 'safety') then raise exception 'bad_kind'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'; end if;
  select status::text, runner_id into v_bstatus, v_runner from bookings where id = sd.booking_id for update;
  if v_bstatus <> 'confirmed' or v_runner is null then raise exception 'not_assigned'; end if;
  perform 1 from bookings where id = sd.booking_id
    and (owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null);
  if found then raise exception 'already_handed_off'; end if;   -- 인계 후엔 조기 반환/인시던트 경로

  if p_kind = 'preference' then
    if now() > s.scheduled_at - interval '20 minutes' then raise exception 'objection_window_closed'; end if;
    if sd.objection_used then raise exception 'objection_already_used'; end if;
    update session_dogs set objection_used = true where id = p_session_dog;
  end if;
  -- 안전 이의는 시한·횟수 제한 없음 (인계 전까지) — 기록은 이벤트 reason에 남는다

  insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
  values (sd.id, v_runner, 'revoked', 'owner_objection:' || p_kind || ':' || p_reason, auth.uid());

  if p_want_refund then
    -- 전액 환불로 이탈 (confirmed → cancelled_runner → refund_pending 2단 — 0038 선례)
    update bookings set status = 'cancelled_runner', cancel_reason = 'club_owner_objection' where id = sd.booking_id;
    update bookings set status = 'refund_pending' where id = sd.booking_id;
    update session_dogs set id = id where id = p_session_dog;   -- 즉시 재동기화
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '이의 접수 — 전액 환불', '위탁이 취소되고 전액 환불 처리돼요', sd.booking_id),
      (s.host_profile_id, 'community', '보호자 이의 — 위탁 취소', '이의로 위탁이 취소됐어요 (' || p_kind || ')', sd.session_id);
  else
    update bookings set runner_id = null, status = 'matching',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
    update session_dogs set id = id where id = p_session_dog;   -- 즉시 재동기화
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (s.host_profile_id, 'community', '보호자 이의 — 재배정 필요',
       '이의(' || p_kind || ')로 배정이 해제됐어요 — 다른 러너를 제안하세요', sd.session_id),
      (v_runner, 'booking', '배정 변경', '해당 위탁의 담당이 변경될 예정이에요', sd.session_id);
  end if;
end $$;

-- ---------- 백업 호스트 · 호스트 인수 (§5 host absence) ----------
create or replace function session_set_backup(p_session uuid, p_profile uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  perform _club_require_v2();
  select * into s from club_sessions where id = p_session for update;
  if s.id is null then raise exception 'not_found'; end if;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if p_profile = s.host_profile_id then raise exception 'backup_is_host'; end if;
  if not exists (select 1 from session_runner_assignments
                 where session_id = p_session and runner_profile_id = p_profile and status = 'committed') then
    raise exception 'backup_not_committed';   -- 백업은 커밋된 러너 중에서 (현장 인수 가능해야)
  end if;
  update club_sessions set backup_host_profile_id = p_profile where id = p_session;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (p_profile, 'community', '백업 호스트 지정', '이 세션의 백업 호스트로 지정됐어요 — 호스트 부재 시 인수하게 돼요', p_session);
end $$;

create or replace function club_assume_host(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  perform _club_require_v2();
  select * into s from club_sessions where id = p_session for update;
  if s.id is null then raise exception 'not_found'; end if;
  if s.backup_host_profile_id is distinct from auth.uid() then raise exception 'not_backup'; end if;
  if s.status not in ('open', 'full') then raise exception 'session_closed'; end if;
  if now() < s.scheduled_at - interval '30 minutes' then raise exception 'too_early'; end if;
  if exists (select 1 from session_people
             where session_id = p_session and profile_id = s.host_profile_id and attendance = 'checked_in') then
    raise exception 'host_present';           -- 호스트가 현장에 있으면 인수 불가
  end if;
  update club_sessions set
    original_host_profile_id = coalesce(original_host_profile_id, s.host_profile_id),
    host_profile_id = auth.uid(), host_assumed_at = now(),
    backup_host_profile_id = null
  where id = p_session;
  insert into notifications (profile_id, kind, title, body, ref_id) values
    (s.host_profile_id, 'community', '호스트 인수됨', '백업 호스트가 세션을 인수했어요', p_session);
  insert into notifications (profile_id, kind, title, body, ref_id)
  select a.runner_profile_id, 'community', '호스트 변경',
         '백업 호스트가 세션을 인수했어요 — 배정·인계는 새 호스트가 진행해요', p_session
  from session_runner_assignments a
  where a.session_id = p_session and a.status = 'committed' and a.runner_profile_id <> auth.uid();
end $$;

-- ---------- 회복 크론 (5분) — T-10 하드 스톱·제안 만료 정리·T-30 경보 ----------
-- 실시간 법 유지: 만료·미배정 판정은 술어가 이미 now()로 한다. 크론은 ① 하드 스톱 환불의
-- '실행'(결제된 개는 구조적으로 좌초 불가 — §5) ② 만료 캐시 정리+이벤트 ③ 경보(알림 dedup).
create or replace function club_assignment_recovery() returns int
language plpgsql security definer set search_path = public as $$
declare r record; sess record; n int := 0; v_ids uuid[];
begin
  -- ① T-10 하드 스톱: 결제됐지만 수락된 배정이 없는 개 → 자동 전액 환불 + 옵션 안내
  for sess in
    select * from club_sessions
    where status in ('open', 'full')
      and scheduled_at <= now() + interval '10 minutes'
      and scheduled_at > now() - interval '12 hours'
      and delegated_dog_capacity > 0
    for update
  loop
    select coalesce(array_agg(b.id), '{}') into v_ids
    from session_dogs d join bookings b on b.id = d.booking_id
    where d.session_id = sess.id and d.custody = 'runner_delegated' and b.status = 'matching';
    continue when coalesce(array_length(v_ids, 1), 0) = 0;
    n := n + _club_refund_bookings(v_ids, 'club_assignment_failed',
      '배정 불발 — 전액 환불', 'T-10까지 담당 러너가 확정되지 않아 전액 환불돼요 — 다음 세션 우선권을 드려요');
    insert into notifications (profile_id, kind, title, body, ref_id)
    select sess.host_profile_id, 'community', '배정 불발 자동 환불',
           coalesce(array_length(v_ids, 1), 0) || '건이 T-10 하드 스톱으로 환불됐어요', sess.id
    where not exists (select 1 from notifications
                      where profile_id = sess.host_profile_id and ref_id = sess.id and title = '배정 불발 자동 환불');
  end loop;

  -- ② 만료 제안 정리: 이벤트 기록 + 캐시 클리어 (진실은 이벤트 — 캐시 청소는 상태 변경이 아님)
  for r in
    select d.id, d.session_id, d.proposed_runner_profile_id, d.dog_id,
           (select host_profile_id from club_sessions where id = d.session_id) as host
    from session_dogs d join bookings b on b.id = d.booking_id
    where d.proposed_runner_profile_id is not null and d.proposal_expires_at <= now()
      and b.status = 'matching'
  loop
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason)
    values (r.id, r.proposed_runner_profile_id, 'expired', 'proposal_timeout');
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null where id = r.id;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (r.host, 'community', '배정 제안 만료',
      (select name from dogs where id = r.dog_id) || ' 제안이 응답 없이 만료됐어요 — 다시 제안하세요', r.session_id);
    n := n + 1;
  end loop;

  -- ③ T-30 경보 (dedup: 제목+ref+수신자 1회) — 러너 지각 = capacity-at-risk · 호스트 부재 = 백업 안내
  for r in
    select s.id, s.host_profile_id, s.backup_host_profile_id, a.runner_profile_id
    from club_sessions s
    join session_runner_assignments a on a.session_id = s.id and a.status = 'committed'
    where s.status in ('open', 'full')
      and s.scheduled_at between now() and now() + interval '30 minutes'
      and not exists (select 1 from session_people sp
                      where sp.session_id = s.id and sp.profile_id = a.runner_profile_id
                        and sp.attendance = 'checked_in')
      and exists (select 1 from session_dogs d join bookings b on b.id = d.booking_id
                  where d.session_id = s.id and b.runner_id = a.runner_profile_id
                    and b.status = 'confirmed')
  loop
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.host_profile_id, 'community', '러너 체크인 지연',
           '배정 수락 러너가 T-30까지 체크인하지 않았어요 — 교체 제안을 준비하세요', r.id
    where not exists (select 1 from notifications
                      where profile_id = r.host_profile_id and ref_id = r.id and title = '러너 체크인 지연');
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.runner_profile_id, 'booking', '체크인 지연',
           '배정을 수락한 세션이 30분 안에 시작돼요 — 지금 체크인하세요', r.id
    where not exists (select 1 from notifications
                      where profile_id = r.runner_profile_id and ref_id = r.id and title = '체크인 지연');
  end loop;
  for r in
    select s.id, s.backup_host_profile_id from club_sessions s
    where s.status in ('open', 'full') and s.backup_host_profile_id is not null
      and s.scheduled_at between now() and now() + interval '30 minutes'
      and not exists (select 1 from session_people sp
                      where sp.session_id = s.id and sp.profile_id = s.host_profile_id
                        and sp.attendance = 'checked_in')
  loop
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.backup_host_profile_id, 'community', '호스트 부재 위험',
           '호스트가 T-30까지 체크인하지 않았어요 — 인수(assume host)가 가능해요', r.id
    where not exists (select 1 from notifications
                      where profile_id = r.backup_host_profile_id and ref_id = r.id and title = '호스트 부재 위험');
  end loop;
  return n;
end $$;
revoke execute on function club_assignment_recovery() from public, anon, authenticated;
do $$ begin
  perform cron.schedule('club-assignment-recovery', '*/5 * * * *', 'select club_assignment_recovery()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

grant execute on function session_propose_dog(uuid, uuid) to authenticated;
grant execute on function session_proposal_respond(uuid, boolean, text) to authenticated;
grant execute on function session_proposal_revoke(uuid) to authenticated;
grant execute on function session_assignment_revoke(uuid, text) to authenticated;
grant execute on function session_owner_objection(uuid, text, text, boolean) to authenticated;
grant execute on function session_set_backup(uuid, uuid) to authenticated;
grant execute on function club_assume_host(uuid) to authenticated;

comment on function session_propose_dog is
  'R3(0047): Model A 제안 — 자기 제안=즉시 수락, confirmed 위 제안=암묵 철회(replaced) 후 제안, 부하=수락+활성 제안+동반견';
comment on function club_assignment_recovery is
  'R3(0047): T-10 하드 스톱 환불(결제견 좌초 불가) · 제안 만료 정리(이벤트+캐시) · T-30 경보(dedup)';

-- ---------- 축 계산 v5 — 배정 축 이벤트 파생 (최신 정의 = 0045, grep 확인 — R2 본문 유지) ----------
create or replace function _club_compute_axes(sd session_dogs) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bst text; v_brunner uuid; v_bcancel text; v_run_reason text; v_ae text;
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

  -- [R3] 배정 축 = 이벤트 파생 캐시: 부킹 러너(물리 진실) → 활성 제안(실시간) → 최종 이벤트
  if v_brunner is not null and v_bst in ('confirmed','picked_up','active','completed') then
    j := j || jsonb_build_object('assignment_state','accepted','current_runner_profile_id', v_brunner);
  elsif sd.proposed_runner_profile_id is not null and sd.proposal_expires_at > now()
        and v_bst = 'matching' then
    j := j || jsonb_build_object('assignment_state','proposed','current_runner_profile_id', null);
  else
    select event into v_ae from assignment_events
    where session_dog_id = sd.id order by seq desc limit 1;   -- 단조 seq만 (0045 교훈)
    if v_bst = 'matching' and v_ae = 'declined' then
      j := j || jsonb_build_object('assignment_state','declined','current_runner_profile_id', null);
    elsif v_bst = 'matching' and v_ae in ('revoked','replaced') then
      j := j || jsonb_build_object('assignment_state','replacement_needed','current_runner_profile_id', null);
    else
      j := j || jsonb_build_object('assignment_state','unassigned','current_runner_profile_id', null);
    end if;
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

-- ---------- UI 프로젝션 v3 — declined/replacement도 '배정 대기' (최신 정의 = 0045) ----------
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

-- ---------- 보드 v4 — 배정 축·제안 노출 (프라이버시: 후보는 호스트·피제안자만) ----------
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
        -- [R3] 배정 축 — 제안 후보는 호스트·피제안 러너에게만 (보호자는 상태만: 러너 프라이버시)
        'assignmentState', d.assignment_state,
        'objectionUsed', d.objection_used,
        'proposedRunnerId', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                 then d.proposed_runner_profile_id end,
        'proposedRunnerName', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                   then (select name from profiles where id = d.proposed_runner_profile_id) end,
        'proposalExpiresAt', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                  then d.proposal_expires_at end,
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        and (d.service_state is distinct from 'ended' or d.booking_id is not null)), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

comment on function _club_compute_axes is
  'R3(0047): 배정 축 이벤트 파생 — accepted(부킹)>proposed(활성 제안·실시간)>declined/replacement_needed(최종 이벤트)>unassigned';

-- 전행 재동기화 (BEFORE 트리거가 새 축 계산으로 캐시 갱신)
update session_dogs set id = id;
