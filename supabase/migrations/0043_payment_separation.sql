-- ═══ 0043: R1 — 결제 분리 (club-run-logic.md v3.3 §1·§2·§16 R1) ═══
-- 첫 행동 변경 슬라이스: 승인 ≠ 결제. 승인 = 20분 정원 홀드(자격), 부킹 생성은 보호자의
-- 결제 RPC로 이동(멱등). 위탁 진입 RPC 4종(등록·커밋·승인·결제)은 club_delegation_v2 플래그로
-- 게이트 — 플래그 OFF면 위탁 기능 자체가 닫힌다 (v1 UI는 출시된 적 없음).
--
-- 축 소유권 이전 (1단계): hold_status/hold_expires_at은 이제 RPC가 직접 쓰는 1차 저장이고,
-- charge_state는 (부킹 존재, 홀드 상태)에서 파생된다 — _club_compute_axes가 v2 규칙으로 갱신.
-- 정산·환불·배정·커스터디 축은 여전히 v1 진실 파생 (R2·R3에서 순차 이전).
--
-- 함께: club_fare() 단일 가격 소스(0037·0039의 인라인 상수 은퇴) · 활성 시도 부분 유니크
-- (거절 번복 = 새 시도 행, ended 불변) · 홀드 만료 크론 · 정원 술어(홀드+라이브 결제) 세션 락.

-- ---------- 가격 단일 소스 ----------
create or replace function club_fare(p_km numeric) returns int
language sql immutable as $$
  select 9900 + round(p_km * 3000)::int;
$$;

-- ---------- 플래그 게이트 ----------
create or replace function _club_require_v2() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not club_flag('club_delegation_v2') then raise exception 'feature_disabled'; end if;
end $$;
revoke execute on function _club_require_v2() from public, anon, authenticated;

-- ---------- 활성 시도 부분 유니크 (ended 행은 이력 — 같은 세션·강아지의 새 시도 허용) ----------
alter table session_dogs drop constraint if exists session_dogs_session_id_dog_id_key;
create unique index if not exists session_dogs_active_uni
  on session_dogs (session_id, dog_id)
  where (service_state is distinct from 'ended');

-- session_rsvp(0030)의 ON CONFLICT 중재자를 부분 인덱스로 교체 — 최신 정의는 0030 (grep 확인)
create or replace function session_rsvp(p_session uuid, p_dog uuid default null, p_waiver text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_cap int; v_cnt int; v_club uuid;
  v_role text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select status, scheduled_at, people_capacity, club_id into v_status, v_when, v_cap, v_club
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status <> 'open' or v_when < now() then raise exception 'session_closed'; end if;
  select count(*) into v_cnt from session_people where session_id = p_session and attendance <> 'no_show';
  if v_cnt >= v_cap then raise exception 'session_full'; end if;
  if p_dog is not null and not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
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
  insert into club_members (club_id, profile_id) values (v_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;
  if v_cnt + 1 >= v_cap then update club_sessions set status = 'full' where id = p_session; end if;
end $$;

-- ---------- 정원 술어 (§6): 소비 = 활성 홀드 + 라이브 결제 ----------
create or replace function _club_delegated_reserved(p_session uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from session_dogs sd
  where sd.session_id = p_session and sd.custody = 'runner_delegated'
    and (
      (sd.hold_status = 'active' and sd.hold_expires_at > now())
      or exists (select 1 from bookings b where b.id = sd.booking_id
                 and b.status in ('matching','confirmed','picked_up','active'))
    );
$$;
revoke execute on function _club_delegated_reserved(uuid) from public, anon, authenticated;

-- ---------- 축 계산 v2 — charge = (부킹, 홀드)에서 파생·홀드 컬럼은 1차 저장(패스스루) ----------
create or replace function _club_compute_axes(sd session_dogs) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bst text; v_brunner uuid; v_bcancel text; v_run_reason text;
  j jsonb := '{}';
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

  -- 서비스 축
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
        'termination_type', case when v_run_reason = 'completed' then 'normal' else 'early_return' end);
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

  -- 돈 축 v2: paid ⇔ 부킹 존재 · hold ⇔ 활성 홀드 (홀드 컬럼 자체는 RPC 소유 — 패스스루)
  if sd.booking_id is not null then
    j := j || jsonb_build_object('charge_state','paid');
    if v_bst in ('refund_pending','cancelled_runner','expired','cancelled_owner') then
      j := j || jsonb_build_object('refund_state','pending');
    else
      j := j || jsonb_build_object('refund_state','none');
    end if;
    if v_bst = 'completed' and exists (select 1 from ledger_items where booking_id = sd.booking_id) then
      j := j || jsonb_build_object('payout_state','released');
    else
      j := j || jsonb_build_object('payout_state','none');
    end if;
  else
    j := j || jsonb_build_object(
      'charge_state', case when sd.hold_status = 'active' and sd.hold_expires_at > now() then 'hold' else 'none' end,
      'refund_state','none','payout_state','none');
  end if;
  j := j || jsonb_build_object('hold_status', coalesce(sd.hold_status,'none'), 'payout_hold', coalesce(sd.payout_hold,'none'));

  -- 배정 캐시 (R3 전까지 부킹 파생)
  if v_brunner is not null and v_bst in ('confirmed','picked_up','active','completed') then
    j := j || jsonb_build_object('assignment_state','accepted','current_runner_profile_id', v_brunner);
  else
    j := j || jsonb_build_object('assignment_state','unassigned','current_runner_profile_id', null);
  end if;

  -- 커스터디 프로젝션 (R2 전까지 responsible 파생)
  if sd.responsible_profile_id = sd.owner_profile_id then
    j := j || jsonb_build_object('custodian_type','owner','custodian_profile_id', sd.owner_profile_id);
  else
    j := j || jsonb_build_object('custodian_type','runner','custodian_profile_id', sd.responsible_profile_id);
  end if;
  j := j || jsonb_build_object('custody_phase','with_custodian');
  return j;
end $$;

-- ---------- 등록 v2 — 게이트 + 활성 행 기준 + 번복 후 새 시도 연결 ----------
create or replace function session_delegate_dog(p_session uuid, p_dog uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_format text; v_club uuid; v_route uuid; v_host uuid;
  v_id uuid; v_prev uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
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

  -- 활성 행 존재 = 중복. ended 행 중 최신이 '거절'이면 번복 전 재신청 불가 (§2)
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
    -- 최신 시도가 호스트 거절이고 번복(새 시도 행)이 없으면 재신청 불가 — 번복은 호스트 몫
    raise exception 'rejected';
  end if;

  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id, approval, previous_attempt_id)
  values (p_session, p_dog, auth.uid(), 'runner_delegated', auth.uid(), 'pending', v_prev)
  returning id into v_id;
  insert into club_members (club_id, profile_id) values (v_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_host, 'community', '위탁 신청 도착', '세션에 위탁 신청이 왔어요 — 승인/거절을 결정하세요', p_session);
  return v_id;
end $$;

-- ---------- 커밋 v2 — 게이트만 추가 (본문 = 0037 최신 정의 grep 확인 후 유지) ----------
create or replace function session_runner_commit(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_format text; v_club uuid;
  v_pcap int; v_pcnt int; v_cap int; v_role text;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  v_cap := _club_runner_cap(auth.uid());
  if v_cap is null or v_cap = 0 then raise exception 'not_certified_runner'; end if;
  select status, scheduled_at, format, club_id, people_capacity
    into v_status, v_when, v_format, v_club, v_pcap
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status not in ('open', 'full') or v_when < now() then raise exception 'session_closed'; end if;
  if v_format not in ('mixed', 'delegated_only') then raise exception 'format_closed'; end if;
  select role into v_role from session_people where session_id = p_session and profile_id = auth.uid();
  if v_role is null then
    select count(*) into v_pcnt from session_people where session_id = p_session and attendance <> 'no_show';
    if v_pcnt >= v_pcap then raise exception 'session_full'; end if;
    insert into session_people (session_id, profile_id, role) values (p_session, auth.uid(), 'handling_runner');
  elsif v_role in ('runner_attending', 'owner_attending') then
    update session_people set role = 'handling_runner'
    where session_id = p_session and profile_id = auth.uid();
  end if;
  insert into session_runner_assignments (session_id, runner_profile_id, delegated_capacity, status)
  values (p_session, auth.uid(), v_cap, 'committed')
  on conflict (session_id, runner_profile_id)
  do update set status = 'committed', delegated_capacity = excluded.delegated_capacity;
  insert into club_members (club_id, profile_id) values (v_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;
  return _club_rederive_capacity(p_session);
end $$;

-- ---------- 승인 v2 — 홀드만 연다 (부킹·클래시 가드는 결제로 이동) ----------
create or replace function session_approve_dog(p_session_dog uuid, p_approve boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_reserved int;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.custody <> 'runner_delegated' or sd.approval <> 'pending' then raise exception 'not_pending'; end if;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  if not p_approve then
    update session_dogs set approval = 'rejected' where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (sd.owner_profile_id, 'community', '위탁 신청 거절',
            '이번 세션에는 함께하지 못하게 됐어요', sd.session_id);
    return null;
  end if;

  v_reserved := _club_delegated_reserved(sd.session_id);
  if v_reserved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;

  update session_dogs set approval = 'approved',
    hold_status = 'active', hold_expires_at = now() + interval '20 minutes'
  where id = p_session_dog;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (sd.owner_profile_id, 'booking', '위탁 승인 — 결제 대기',
          '20분 안에 결제하면 자리가 확정돼요 · ' || club_fare((select km from routes where id = s.route_id)) || '원', sd.session_id);
  return p_session_dog;
end $$;

-- ---------- 결제 (신규, 보호자·멱등) — 부킹은 여기서 태어난다 ----------
create or replace function session_pay_delegation(p_session_dog uuid, p_idem_key text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_km numeric; v_bid uuid; v_reserved int;
  v_start timestamptz; v_end timestamptz; v_clash boolean; v_prev uuid;
  v_hold text; v_hexp timestamptz;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if coalesce(trim(p_idem_key), '') = '' then raise exception 'idem_key_required'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'; end if;

  -- 멱등 재전송: 같은 키의 성공 시도 → 같은 부킹 반환
  select booking_id into v_prev from payment_attempts
  where session_dog_id = p_session_dog and kind = 'charge' and idempotency_key = p_idem_key and result = 'ok';
  if v_prev is not null then return v_prev; end if;

  select * into s from club_sessions where id = sd.session_id for update;   -- 정원·홀드는 세션 락 아래
  if sd.approval <> 'approved' or sd.booking_id is not null then raise exception 'not_payable'; end if;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  -- 홀드 만료 시 재홀드 시도 (§2: 결제 RPC가 정원 재확인 후 새 홀드) — 락 후 재독
  select hold_status, hold_expires_at into v_hold, v_hexp
  from session_dogs where id = p_session_dog;
  if not (v_hold = 'active' and v_hexp > now()) then
    v_reserved := _club_delegated_reserved(sd.session_id);
    if v_reserved >= s.delegated_dog_capacity then
      insert into payment_attempts (session_dog_id, kind, idempotency_key, result, detail)
      values (p_session_dog, 'charge', p_idem_key, 'failed', 'no_capacity');
      raise exception 'no_capacity';
    end if;
  end if;

  -- 같은 강아지 라이브 겹침 가드 (돈의 순간으로 이동 — 0026 공식)
  select km into v_km from routes where id = s.route_id;
  if v_km is null then raise exception 'route_required'; end if;
  v_start := s.scheduled_at;
  v_end := s.scheduled_at + make_interval(mins => (v_km * 8 + 25)::int);
  select exists (
    select 1 from bookings c
    where c.dog_id = sd.dog_id
      and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
      and c.scheduled_at < v_end
      and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
  ) into v_clash;
  if v_clash then
    insert into payment_attempts (session_dog_id, kind, idempotency_key, result, detail)
    values (p_session_dog, 'charge', p_idem_key, 'failed', 'dog_slot_clash');
    raise exception 'dog_slot_clash';
  end if;

  insert into bookings
    (owner_id, dog_id, runner_id, route_id, status, scheduled_at,
     km, addons, base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values
    (sd.owner_profile_id, sd.dog_id, null, s.route_id, 'matching', s.scheduled_at,
     v_km, '[]', 9900, club_fare(v_km) - 9900, 0, club_fare(v_km), 9900, sd.session_id)
  returning id into v_bid;

  update session_dogs set booking_id = v_bid, hold_status = 'consumed' where id = p_session_dog;
  insert into payment_attempts (session_dog_id, booking_id, kind, idempotency_key, result)
  values (p_session_dog, v_bid, 'charge', p_idem_key, 'ok');

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '결제 완료 — 자리 확정',
     to_char(s.scheduled_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
     || ' 위탁이 확정됐어요 — 담당 러너는 집결지에서 배정돼요', v_bid),
    (s.host_profile_id, 'community', '위탁 결제 완료', '위탁 강아지의 결제가 완료됐어요', sd.session_id);
  return v_bid;
end $$;

-- ---------- 거절 번복 (호스트) — ended 불변: 새 시도 행 생성 ----------
create or replace function session_reconsider_dog(p_session_dog uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare sd record; s record; v_new uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.approval <> 'rejected' then raise exception 'not_rejected'; end if;
  if s.status not in ('open','full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;
  -- 번복 표식 (원행 불변 — 이벤트로 기록)
  insert into assignment_events (session_dog_id, event, reason, created_by)
  values (p_session_dog, 'replaced', 'host_reconsidered', auth.uid());
  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id, approval, previous_attempt_id)
  values (sd.session_id, sd.dog_id, sd.owner_profile_id, 'runner_delegated', sd.owner_profile_id, 'pending', sd.id)
  returning id into v_new;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (sd.owner_profile_id, 'community', '위탁 재검토', '호스트가 신청을 다시 열었어요 — 심사 대기로 돌아갑니다', sd.session_id);
  return v_new;
end $$;

-- ---------- 홀드 만료 크론 ----------
create or replace function club_expire_delegation_holds() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with e as (
    update session_dogs set hold_status = 'expired'
    where hold_status = 'active' and hold_expires_at < now()
    returning id, owner_profile_id, session_id
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select owner_profile_id, 'booking', '결제 기한 만료',
           '자리 홀드가 풀렸어요 — 정원이 남아 있으면 다시 결제할 수 있어요', session_id
    from e
  )
  select count(*) into n from e;
  return n;
end $$;
revoke execute on function club_expire_delegation_holds() from public, anon, authenticated;
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('club-hold-expiry', '*/5 * * * *', 'select club_expire_delegation_holds()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

-- ---------- 이탈 v2 — 소비자(홀드·결제) 기준 좌초, 홀드는 해제·결제는 환불 (0038 본문 계승) ----------
create or replace function session_runner_withdraw(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_new_cap int; v_consumers int; v_excess int; v_row record; v_host uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select host_profile_id into v_host from club_sessions where id = p_session for update;
  if v_host is null then raise exception 'not_found'; end if;
  if exists (
    select 1 from bookings b
    where b.club_session_id = p_session and b.runner_id = auth.uid()
      and b.status in ('confirmed', 'picked_up', 'active')
  ) then raise exception 'reassign_dogs_first'; end if;
  update session_runner_assignments set status = 'withdrawn'
  where session_id = p_session and runner_profile_id = auth.uid() and status = 'committed';
  if not found then raise exception 'not_committed'; end if;
  update session_people set role = 'runner_attending'
  where session_id = p_session and profile_id = auth.uid() and role = 'handling_runner';
  v_new_cap := _club_rederive_capacity(p_session);

  v_consumers := _club_delegated_reserved(p_session);
  v_excess := v_consumers - v_new_cap;
  if v_excess > 0 then
    for v_row in
      select sd.id, sd.owner_profile_id, sd.booking_id, sd.hold_status, sd.hold_expires_at from session_dogs sd
      where sd.session_id = p_session and sd.custody = 'runner_delegated'
        and ((sd.hold_status = 'active' and sd.hold_expires_at > now())
             or exists (select 1 from bookings b where b.id = sd.booking_id and b.status = 'matching'))
      order by sd.seq desc limit v_excess
    loop
      if v_row.booking_id is not null then
        update session_dogs set approval = 'pending', booking_id = null, hold_status = 'none' where id = v_row.id;
        perform _club_refund_bookings(array[v_row.booking_id], 'club_runner_withdrawn',
          '위탁 승인 대기로 변경', '러너 이탈로 위탁 정원이 줄었어요 — 승인 대기로 돌아가며 전액 환불 처리돼요');
      else
        update session_dogs set approval = 'pending', hold_status = 'released' where id = v_row.id;
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_row.owner_profile_id, 'booking', '홀드 해제',
                '러너 이탈로 정원이 줄어 결제 대기가 취소됐어요 — 승인 대기로 돌아갑니다', p_session);
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_host, 'community', '위탁 정원 초과', '러너 이탈로 위탁이 대기로 돌아갔어요 — 세션을 확인하세요', p_session);
    end loop;
  end if;
  return v_new_cap;
end $$;

-- ---------- 보드(0039) fare — 단일 소스로 교체 + 홀드 필드 노출 (최신 정의 = 0039) ----------
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
      'checkinOpen', now() between s.scheduled_at - interval '2 hours' and s.scheduled_at + interval '6 hours'
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
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        and (d.service_state is distinct from 'ended' or d.booking_id is not null)), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

grant execute on function session_pay_delegation(uuid, text) to authenticated;
grant execute on function session_reconsider_dog(uuid) to authenticated;

comment on function session_approve_dog is 'R1(0043): 승인 = 20분 홀드만 — 부킹·클래시 가드는 결제로 이동';
comment on function session_pay_delegation is 'R1(0043): 보호자 결제 — 부킹 생성·멱등(payment_attempts)·만료 시 재홀드';
comment on function club_expire_delegation_holds is 'R1(0043): 홀드 만료 크론(*/5) — 정원 술어로 자동 해방';
