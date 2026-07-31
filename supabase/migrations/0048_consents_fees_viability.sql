-- ═══ 0048: R4 — 동의·수수료 원장·성립성·정원 패밀리·멤버십 분리 (v3.3 §4·§6·§12·§16 R4) ═══
-- 미확정 수치는 전부 club_config [Sean 미확정] — SQL로 조정 가능, 코드 하드코딩 없음.
-- 모의 시대 원칙: 돈은 청구하지 않고 전부 '기록'한다 (수수료 원장 = 실PG의 착륙 지형).

-- ---------- A. 운영 수치 (단일 소스) ----------
create table if not exists club_config (
  name text primary key,
  value_num numeric,
  value_text text,
  note text
);
alter table club_config enable row level security;   -- 정책 없음 — service role/definer만
insert into club_config (name, value_num, note) values
  ('vet_limit_krw',          200000, '[Sean 미확정] 수의 진료 사전 승인 한도 기본값'),
  ('cancel_free_hours',      24,     '[Sean 미확정] 보호자 취소 무료 시한 (시간)'),
  ('cancel_late_pct',        10,     '[Sean 미확정] 시한 내 취소 수수료 %'),
  ('cancel_post_accept_pct', 20,     '[Sean 미확정] 배정 수락 후 취소 수수료 % (노쇼 = 이 상단)'),
  ('fee_platform_split_pct', 50,     '[Sean 미확정] 수수료 중 플랫폼 몫 % (나머지 = 공급 보상)'),
  ('host_fee_krw',           0,      '[Sean 미확정] 세션 완주 호스트 수고비 (0 = 기록 생략)'),
  ('owner_handled_dog_limit', 2,     '[Sean 미확정] 참석 보호자당 동반견 한도'),
  ('min_paid_dogs',          1,      '[Sean 미확정] delegated_only 성립 최소 결제견')
on conflict (name) do nothing;

create or replace function club_cfg(p_name text) returns numeric
language sql stable security definer set search_path = public as $$
  select value_num from club_config where name = p_name;
$$;
revoke execute on function club_cfg(text) from public, anon, authenticated;

-- ---------- B. 수수료 원장 — 기록이 정책보다 먼저 (실PG 착륙 지형) ----------
create table if not exists club_fee_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references club_sessions on delete cascade,
  session_dog_id uuid references session_dogs on delete set null,
  booking_id uuid references bookings on delete set null,
  kind text not null check (kind in
    ('cancel_fee','no_show_fee','host_fee','platform_fee','supply_compensation')),
  amount_krw int not null,
  recipient_type text not null check (recipient_type in ('platform','runner','host')),
  recipient_profile_id uuid references profiles(id),
  basis jsonb not null default '{}',            -- {pct, base, rule, strike?} — 근거 없는 금액 금지
  created_at timestamptz not null default now()
);
alter table club_fee_items enable row level security;  -- 정책 없음

-- 취소 수수료 분배: 플랫폼 몫 + 공급 보상 (수락 러너 있으면 그에게 — §5 fee destinations)
create or replace function _club_record_cancel_fee(
  p_session uuid, p_sd uuid, p_booking uuid, p_kind text,
  p_base int, p_pct numeric, p_runner uuid, p_rule text
) returns void
language plpgsql security definer set search_path = public as $$
declare v_fee int; v_plat int;
begin
  v_fee := round(p_base * p_pct / 100.0)::int;
  if v_fee <= 0 then return; end if;
  v_plat := round(v_fee * coalesce(club_cfg('fee_platform_split_pct'), 50) / 100.0)::int;
  insert into club_fee_items (session_id, session_dog_id, booking_id, kind, amount_krw,
    recipient_type, recipient_profile_id, basis)
  values
    (p_session, p_sd, p_booking, p_kind, v_plat, 'platform', null,
     jsonb_build_object('pct', p_pct, 'base', p_base, 'rule', p_rule, 'share', 'platform')),
    (p_session, p_sd, p_booking, p_kind, v_fee - v_plat,
     case when p_runner is not null then 'runner' else 'platform' end, p_runner,
     jsonb_build_object('pct', p_pct, 'base', p_base, 'rule', p_rule, 'share', 'supply_compensation'));
end $$;
revoke execute on function _club_record_cancel_fee(uuid, uuid, uuid, text, int, numeric, uuid, text)
  from public, anon, authenticated;

-- ---------- C. 스키마 ----------
alter table session_dogs add column if not exists review_needed boolean not null default false;
-- [R4] 보호자 결제 전 자발 취소는 호스트 거절이 아니다 — approval에 'withdrawn' 추가
-- (rejected 재활용은 compute가 host_rejected로 읽어 재신청 차단 — 하네스가 검출한 결함)
alter table session_dogs drop constraint if exists session_dogs_approval_check;
alter table session_dogs add constraint session_dogs_approval_check
  check (approval in ('auto', 'pending', 'approved', 'rejected', 'withdrawn'));   -- auto = 동반견 (0030)
alter table club_sessions add column if not exists total_dog_capacity int;   -- null = people_capacity

create or replace function _club_total_dogs(p_session uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from session_dogs
  where session_id = p_session and service_state is distinct from 'ended';
$$;
revoke execute on function _club_total_dogs(uuid) from public, anon, authenticated;

-- ---------- D. 위탁 신청 v3 — 동의 필수 (서명 없는 위탁 없음) · 멤버십 자동 가입 폐지 ----------
-- 시그니처 변경 = drop+recreate (2인자 오버로드 공존 시 PostgREST 모호성 — 0037 선례)
drop function if exists session_delegate_dog(uuid, uuid);

create or replace function session_delegate_dog(
  p_session uuid, p_dog uuid, p_consent jsonb default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_format text; v_club uuid; v_route uuid; v_host uuid;
  v_id uuid; v_prev uuid; v_total_cap int; v_people_cap int;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  -- [R4 §12] 동의는 신청의 전제: 커스터디 인지 + 비상 연락처 필수, 수의 한도는 미지정 시 기본값
  if p_consent is null
     or coalesce((p_consent->>'custodyAck')::boolean, false) is distinct from true
     or coalesce(trim(p_consent->>'emergencyContact'), '') = '' then
    raise exception 'consent_required';
  end if;
  select status, scheduled_at, format, club_id, route_id, host_profile_id
    into v_status, v_when, v_format, v_club, v_route, v_host
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status not in ('open', 'full') or v_when < now() then raise exception 'session_closed'; end if;
  if v_format not in ('mixed', 'delegated_only') then raise exception 'format_closed'; end if;
  if v_route is null then raise exception 'route_required'; end if;
  if not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
  end if;
  -- [R4 §6] 전견 정원 (동반+위탁 합산) — null이면 people_capacity 준용
  select total_dog_capacity, people_capacity into v_total_cap, v_people_cap
  from club_sessions where id = p_session;
  if _club_total_dogs(p_session) >= coalesce(v_total_cap, v_people_cap) then
    raise exception 'dog_capacity_full';
  end if;

  if exists (select 1 from session_dogs where session_id = p_session and dog_id = p_dog
             and service_state is distinct from 'ended') then
    raise exception 'already_registered';
  end if;
  select id into v_prev from session_dogs
  where session_id = p_session and dog_id = p_dog and service_state = 'ended'
  order by seq desc limit 1;
  if v_prev is not null and exists (select 1 from session_dogs where id = v_prev
      and service_reason = 'host_rejected'
      and not exists (select 1 from session_dogs nx where nx.previous_attempt_id = v_prev)) then
    raise exception 'rejected';
  end if;

  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id, approval, previous_attempt_id)
  values (p_session, p_dog, auth.uid(), 'runner_delegated', auth.uid(), 'pending', v_prev)
  returning id into v_id;

  -- 불변 동의 기록 (§12) — 수정 RPC 없음, 재동의 = 새 행
  insert into delegation_consents
    (session_dog_id, owner_profile_id, dog_id, doc_id, doc_version,
     vet_limit_krw, photo_consent, custody_ack, pickup_name, pickup_contact, emergency_contact, meta)
  values
    (v_id, auth.uid(), p_dog, 'club-delegation', 'v1',
     coalesce((p_consent->>'vetLimitKrw')::int, club_cfg('vet_limit_krw')::int),
     coalesce((p_consent->>'photoConsent')::boolean, false), true,
     p_consent->>'pickupName', p_consent->>'pickupContact',
     trim(p_consent->>'emergencyContact'),
     coalesce(p_consent->'meta', '{}'::jsonb));

  -- [R4] 멤버십 자동 가입 폐지 — RSVP/위탁 ≠ 가입 (가입은 club_join 명시 행위)
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_host, 'community', '위탁 신청 도착', '세션에 위탁 신청이 왔어요 — 승인/거절을 결정하세요', p_session);
  return v_id;
end $$;

-- ---------- E. RSVP v3 — 멤버십 자동 가입 폐지 + 전견 정원 (최신 정의 = 0043) ----------
create or replace function session_rsvp(p_session uuid, p_dog uuid default null, p_waiver text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_cap int; v_cnt int; v_club uuid;
  v_role text; v_total_cap int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select status, scheduled_at, people_capacity, club_id, total_dog_capacity
    into v_status, v_when, v_cap, v_club, v_total_cap
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status <> 'open' or v_when < now() then raise exception 'session_closed'; end if;
  select count(*) into v_cnt from session_people where session_id = p_session and attendance <> 'no_show';
  if v_cnt >= v_cap then raise exception 'session_full'; end if;
  if p_dog is not null and not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
  end if;
  if p_dog is not null and _club_total_dogs(p_session) >= coalesce(v_total_cap, v_cap) then
    raise exception 'dog_capacity_full';
  end if;
  v_role := case when p_dog is null and exists (
    select 1 from runners where profile_id = auth.uid() and tier <> 'applicant'
  ) then 'runner_attending' else 'owner_attending' end;
  begin
    insert into session_people (session_id, profile_id, role, waiver_version)
    values (p_session, auth.uid(), v_role, p_waiver);
  exception when unique_violation then
    raise exception 'already_joined';
  end;
  if p_dog is not null then
    insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id)
    values (p_session, p_dog, auth.uid(), 'owner_handled', auth.uid())
    on conflict (session_id, dog_id) where (service_state is distinct from 'ended') do nothing;
  end if;
  -- [R4] 멤버십 자동 가입 폐지 — 게스트 RSVP 1급 (가입 권유는 UI/알림 몫)
  if v_cnt + 1 >= v_cap then update club_sessions set status = 'full' where id = p_session; end if;
end $$;

-- ---------- F. 명시적 멤버십 — 가입/탈퇴 (의무는 멤버십 변화를 건너 존속: 표준 불변식) ----------
create or replace function club_join(p_club uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from clubs where id = p_club) then raise exception 'not_found'; end if;
  insert into club_members (club_id, profile_id) values (p_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;
end $$;

create or replace function club_leave(p_club uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  -- 탈퇴는 자유 — 그러나 서비스 의무(위탁·부킹·커스터디)는 멤버십이 아니라 세션/부킹에 산다.
  -- 여기서 아무 의무도 취소하지 않는 것이 불변식이다 (§15 canonical).
  delete from club_members where club_id = p_club and profile_id = auth.uid();
end $$;

grant execute on function session_delegate_dog(uuid, uuid, jsonb) to authenticated;
grant execute on function club_join(uuid) to authenticated;
grant execute on function club_leave(uuid) to authenticated;

-- ---------- G. 강아지 수정 물질성 (§12) — 결제견은 requested로 돌아가지 않는다 ----------
-- 안전 결정 필드(현 스키마: weight_kg) 변경 → 배정 철회 + 재검토 배지 + 호스트 재심사.
-- 미심사 좌초는 T-10 하드 스톱이 구조적으로 회수 (배정 철회로 matching이 되므로).
create or replace function _club_dog_materiality_tg() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_runner uuid; v_bst text;
begin
  if new.weight_kg is not distinct from old.weight_kg then return new; end if;
  for r in
    select sd.id, sd.session_id, sd.booking_id, sd.owner_profile_id,
           (select host_profile_id from club_sessions cs where cs.id = sd.session_id) as host
    from session_dogs sd
    where sd.dog_id = new.id and sd.custody = 'runner_delegated'
      and sd.approval = 'approved' and sd.service_state is distinct from 'ended'
  loop
    select status::text, runner_id into v_bst, v_runner from bookings where id = r.booking_id for update;
    if v_bst in ('picked_up', 'active', 'completed', 'incident_review') then
      continue;                                        -- 인계 후 편집은 커스터디 흐름 밖 (기록만)
    end if;
    update session_dogs set review_needed = true where id = r.id;
    if v_bst = 'confirmed' and v_runner is not null then
      insert into assignment_events (session_dog_id, runner_profile_id, event, reason)
      values (r.id, v_runner, 'revoked', 'safety_edit');
      update bookings set runner_id = null, status = 'matching',
        owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
      where id = r.booking_id;
      update session_dogs set id = id where id = r.id;   -- 즉시 재동기화 (deferred 포크 규칙)
    end if;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (r.host, 'community', '안전 정보 변경 — 재검토 필요',
       '위탁견의 안전 결정 정보가 바뀌었어요 — 재심사 후 계속/거절을 결정하세요', r.session_id),
      (r.owner_profile_id, 'booking', '재검토 대기',
       '변경된 정보로 호스트가 재심사해요 — 자리와 결제는 유지돼요', r.session_id);
  end loop;
  return new;
end $$;
drop trigger if exists club_dog_materiality on dogs;
create trigger club_dog_materiality after update of weight_kg on dogs
  for each row execute function _club_dog_materiality_tg();

create or replace function session_review_dog(p_session_dog uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare sd record; s record;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if not sd.review_needed then raise exception 'no_review_pending'; end if;
  if p_approve then
    update session_dogs set review_needed = false where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (sd.owner_profile_id, 'booking', '재검토 통과', '변경된 정보로 계속 진행해요 — 결제·자리 유지', sd.session_id);
  else
    -- 재심사 거절 = 자동 전액 환불 (보호자 과실 아님 — 정보를 정직하게 갱신한 결과)
    update session_dogs set review_needed = false where id = p_session_dog;
    if sd.booking_id is not null then
      update bookings set status = 'refund_pending', cancel_reason = 'club_review_rejected'
      where id = sd.booking_id and status = 'matching';
      update session_dogs set id = id where id = p_session_dog;
    end if;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (sd.owner_profile_id, 'booking', '재검토 거절 — 전액 환불', '변경된 조건으로는 이번 세션 위탁이 어려워요 — 전액 환불돼요', sd.session_id);
  end if;
end $$;
grant execute on function session_review_dog(uuid, boolean) to authenticated;

-- ---------- H. 보호자 취소 사다리 (§ fee destinations) — 모의: 전액 환불 + 수수료 '기록' ----------
create or replace function session_cancel_delegation(p_session_dog uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_bst text; v_runner uuid; v_total int; v_pct numeric; v_rule text;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'; end if;
  if sd.service_state = 'ended' then raise exception 'already_ended'; end if;

  if sd.booking_id is null then
    -- 결제 전 = 자유 취소: 행 종결 (홀드 해제 포함) — 수수료 없음, 재신청 자유(withdrawn)
    update session_dogs set approval = 'withdrawn',
      hold_status = case when hold_status = 'active' then 'released' else hold_status end
    where id = p_session_dog;
    update session_dogs set id = id where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.host_profile_id, 'community', '위탁 신청 취소', '보호자가 위탁 신청을 취소했어요', sd.session_id);
    return;
  end if;

  select status::text, runner_id, total_price into v_bst, v_runner, v_total
  from bookings where id = sd.booking_id for update;
  if v_bst not in ('matching', 'confirmed') then raise exception 'already_handed_off'; end if;

  -- 사다리 (config): 수락 후 > 시한 내 > 무료 — 근거는 basis에 기록
  if v_bst = 'confirmed' and v_runner is not null then
    v_pct := coalesce(club_cfg('cancel_post_accept_pct'), 20); v_rule := 'post_acceptance';
  elsif s.scheduled_at - now() < make_interval(hours => coalesce(club_cfg('cancel_free_hours'), 24)::int) then
    v_pct := coalesce(club_cfg('cancel_late_pct'), 10); v_rule := 'late_cancel';
  else
    v_pct := 0; v_rule := 'free_window';
  end if;

  if v_bst = 'confirmed' then
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_runner, 'revoked', 'owner_cancel', auth.uid());
    update bookings set runner_id = null, status = 'matching',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  end if;
  update bookings set status = 'refund_pending', cancel_reason = 'club_owner_cancel'
  where id = sd.booking_id;
  update session_dogs set id = id where id = p_session_dog;

  perform _club_record_cancel_fee(sd.session_id, sd.id, sd.booking_id, 'cancel_fee',
    v_total, v_pct, v_runner, v_rule);

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '위탁 취소 접수',
     case when v_pct > 0 then '환불이 진행돼요 — 취소 수수료 ' || v_pct || '%가 기록됐어요 (모의 시대: 청구 없음)'
          else '전액 환불이 진행돼요' end, sd.booking_id),
    (s.host_profile_id, 'community', '위탁 취소', '보호자가 결제된 위탁을 취소했어요', sd.session_id);
  if v_runner is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_runner, 'booking', '배정 취소', '보호자 취소로 배정이 해제됐어요 — 보상 기록이 남았어요', sd.session_id);
  end if;
end $$;
grant execute on function session_cancel_delegation(uuid) to authenticated;

-- ---------- I. 성립성 (§4) — 포맷별 판정, 자동 취소 없음 (사람이 열고 사람이 닫는다) ----------
create or replace function club_session_viability(p_session uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s record; v_teams int; v_paid int; v_present_runners int; v_headroom int;
  v_att boolean; v_cov boolean;
begin
  select * into s from club_sessions where id = p_session;
  if s.id is null then return null; end if;
  select count(*) into v_teams from session_people
  where session_id = p_session and attendance <> 'no_show';
  select count(*) into v_paid from session_dogs sd
  where sd.session_id = p_session and sd.custody = 'runner_delegated'
    and exists (select 1 from bookings b where b.id = sd.booking_id
                and b.status in ('matching','confirmed','picked_up','active'));
  select count(*), coalesce(sum(greatest(a.delegated_capacity - _club_runner_load(p_session, a.runner_profile_id), 0)), 0)
    into v_present_runners, v_headroom
  from session_runner_assignments a
  where a.session_id = p_session and a.status = 'committed'
    and exists (select 1 from session_people sp where sp.session_id = p_session
                and sp.profile_id = a.runner_profile_id and sp.attendance = 'checked_in');
  -- 수락된 부하는 이미 커버 — 커버리지 = 미수락 결제견 ≤ 현장 여유
  v_att := v_teams >= coalesce(s.min_attendance, 0);
  v_cov := (select count(*) from session_dogs sd join bookings b on b.id = sd.booking_id
            where sd.session_id = p_session and sd.custody = 'runner_delegated'
              and b.status = 'matching') <= v_headroom;
  return jsonb_build_object(
    'format', s.format,
    'attendanceOk', v_att,
    'paidDogs', v_paid,
    'presentRunners', v_present_runners,
    'coverageOk', v_cov,
    'viable', case s.format
      when 'owner_only' then v_att
      when 'delegated_only' then v_paid >= coalesce(club_cfg('min_paid_dogs'), 1)::int and v_present_runners >= 1
      else v_att and v_cov end);
end $$;
revoke execute on function club_session_viability(uuid) from public, anon, authenticated;

-- ---------- J. 세션 종료 v3 — 수수료 기록 결합 (최신 정의 = 0045, grep 확인) ----------
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
  -- [R4] 노쇼(인계 미완) 수수료 기록: 사다리 상단 + 신뢰도 스트라이크 표기 (모의: 기록만)
  perform _club_record_cancel_fee(p_session, sd.id, b.id, 'no_show_fee',
    b.total_price::int, coalesce(club_cfg('cancel_post_accept_pct'), 20), b.runner_id, 'no_show_ladder_top')
  from bookings b join session_dogs sd on sd.booking_id = b.id
  where b.club_session_id = p_session and b.cancel_reason = 'club_not_picked_up'
    and b.status = 'refund_pending' and b.runner_id is not null;
  -- [R4] 호스트 수고비: 위탁 완주가 있었던 세션만, 금액은 config (0 = 기록 생략)
  if coalesce(club_cfg('host_fee_krw'), 0) > 0 and exists (
    select 1 from bookings where club_session_id = p_session and status = 'completed') then
    insert into club_fee_items (session_id, kind, amount_krw, recipient_type, recipient_profile_id, basis)
    values (p_session, 'host_fee', club_cfg('host_fee_krw')::int, 'host', auth.uid(),
      jsonb_build_object('rule', 'session_completed'));
  end if;
end $$;

-- ---------- K. 제안 v2 — 재검토 게이트 (최신 정의 = 0047) ----------
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
  if sd.review_needed then raise exception 'review_pending'; end if;   -- [R4] 재심사 통과 전 배정 금지

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

-- ---------- L. 프로젝션 v4 — 재검토 배지 (최신 정의 = 0047) ----------
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

-- ---------- M. 보드 v5 — 성립성·재검토 노출 (최신 정의 = 0047) ----------
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
      'viability', club_session_viability(s.id),
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
        'reviewNeeded', d.review_needed,
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

-- ---------- N. 축 계산 v6 — withdrawn 분기 (최신 정의 = 0047) ----------
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
  elsif sd.approval = 'withdrawn' then
    -- [R4] 결제 전 보호자 자발 취소 — 호스트 거절과 구분 (재신청 자유)
    j := j || jsonb_build_object('service_state','ended','completion_outcome','no_service',
      'termination_type','cancelled','service_reason','owner_cancel','cancelled_by','owner');
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

comment on table club_config is 'R4(0048): 운영 수치 단일 소스 — [Sean 미확정] 값은 SQL로 조정';
comment on table club_fee_items is 'R4(0048): 수수료 원장 — 모의 시대: 청구 0, 기록 전부 (실PG 착륙 지형)';
comment on function session_delegate_dog is 'R4(0048): 동의 필수(커스터디 인지+비상 연락처) · 불변 동의 기록 · 멤버십 자동 가입 폐지 · 전견 정원';
comment on function session_cancel_delegation is 'R4(0048): 보호자 취소 사다리 — 무료/시한 내/수락 후 (config) · 수수료 분배 기록';
comment on function club_session_viability is 'R4(0048): 포맷별 성립성 — 자동 취소 없음, 판정만 (보드 노출)';

update session_dogs set id = id;   -- 전행 재동기화
