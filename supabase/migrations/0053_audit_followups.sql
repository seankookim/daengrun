-- ═══ 0053: 감사 잔여 서버 후속 (2026-08-02 클럽 위탁 UI 감사 ✅ 절 "남은 서버 후속") ═══
-- 왜 (항목별 발견 요지):
--  §1 [감사 9] 결제 시트의 '배정 방식 동의' 체크가 서버에 안 남았다 — 분쟁 시 동의 근거가 없고
--     RPC 직접 호출로 체크를 우회할 수 있었다. p_method_consent를 계약에 넣고(distinct from true =
--     method_consent_required) 동의 사실을 delegation_consents에 박제한다. 오버로드 회피를 위해
--     기존 2인자 시그니처를 drop 후 3인자(기본 false)로 재정의 — PostgREST 오버로드 0 유지.
--  §2 [감사 10] club_save_run_trace가 trace를 통째로 덮어썼다 — 클라 재진입/부분 배치가 서버
--     트레이스를 잘랐다(감사 P0의 서버측 근본 해법). 덮어쓰기를 병합(append)으로: 기존 마지막 t보다
--     큰 신규 요소만 이어붙이고, 무결성(t 단조·8m/s)은 배치 내부 + 경계(기존 마지막→신규 첫)까지 유지.
--     빈 기존 = 신규 전체. 전체를 재전송해도 dedup되어 유실·중복 없음.
--  §3a [감사 11a] delegation_consents.photo_consent가 저장되나 아무도 안 읽었다 — shareRunToFeed·
--     영수증 베스트샷이 미동의 견 사진을 공개할 수 있었다. 읽기측 서버 게이트 club_run_photo_allowed
--     신설(위탁 부킹의 최신 동의 photo_consent, 위탁이 아니면 true = 일반 예약 동의 체계 유지).
--  §4 [감사] board dogs 필터가 rejected/withdrawn(ended + booking_id null)을 지워 보호자가 REFUSED
--     카드('정직한 마지막 말')에 닿지 못하고 신청이 증발한 걸 봤다 — 필터를 넓혀 **자기 것만** 노출.
--  §5 [감사] _club_shell_access limited 생존 조건 — §4와의 상호작용 결론은 아래 §5 블록 주석 참조.
-- 불변: 0052까지는 정본. 기존 파일 수정 없음 — 모든 변경은 이 파일에서 drop+create / create or replace.
--
-- ── §3b 지연 계획 (이번 0053 제외 — 별도 슬라이스) ──────────────────────────────────────────
-- 사진 비공개 버킷 전환은 avatars 버킷 전반(아바타·클럽 사진·챗·런·영수증)을 건드리는 대공사라
-- 이번 배치에 넣지 않는다. 후속 슬라이스 계획:
--   1) 새 private 버킷 'club-run-photos'(public=false) 생성 + storage.objects RLS: 소유 러너 write,
--      읽기는 definer 함수 club_run_photo_allowed(booking) = true인 세션 당사자만.
--   2) 기존 런/영수증 미디어 경로를 새 버킷으로 마이그레이트(백필 잡) + media_path 스키마 정규화.
--   3) 공개 URL 대신 서명 URL(짧은 TTL) 발급 RPC — shareRunToFeed·베스트샷이 이 게이트를 경유.
--   4) 클라(patcher)는 공개 URL 조립을 서명 URL 요청으로 교체.
-- 위임: patcher/후속 마이그레이션. 이번 §3a는 '읽기 판정'만 서버에 심어 소비 지점을 준비한다.

-- ---------- §1. session_pay_delegation 배정 방식 동의 박제 (감사 9) ----------
-- 동의 저장 컬럼: payment_attempts.detail은 text이므로(구조화 부적합) delegation_consents에 불리언
-- 컬럼을 추가하고 결제 시 최신 동의행을 갱신한다 — 불변 동의 원장(§12)과 같은 자리에 박제.
alter table delegation_consents add column if not exists method_consent boolean not null default false;

-- [오버로드 회피] 구 2인자 시그니처 drop (grant revoke는 drop이 처리) 후 3인자로 재정의.
drop function if exists session_pay_delegation(uuid, text);

create or replace function session_pay_delegation(p_session_dog uuid, p_idem_key text, p_method_consent boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_km numeric; v_bid uuid; v_reserved int;
  v_start timestamptz; v_end timestamptz; v_clash boolean; v_prev uuid;
  v_hold text; v_hexp timestamptz; v_approval text; v_booking uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if coalesce(trim(p_idem_key), '') = '' then raise exception 'idem_key_required'; end if;
  -- [감사 9] 배정 방식 동의 게이트 — 서버가 강제(RPC 직접 호출 우회 차단). 기본 false = 미동의.
  if p_method_consent is distinct from true then raise exception 'method_consent_required'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'; end if;

  -- 멱등 재전송: 같은 키의 '성공' 시도 → 같은 부킹 반환 (실패 키는 재시도 허용 — 업서트)
  select booking_id into v_prev from payment_attempts
  where session_dog_id = p_session_dog and kind = 'charge' and idempotency_key = p_idem_key and result = 'ok';
  if v_prev is not null then return v_prev; end if;

  select * into s from club_sessions where id = sd.session_id for update;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  -- [②] 락 '후' 재독 — approval·booking·hold 전부 (락 대기 중 이탈 좌초/변경 반영)
  select approval, booking_id, hold_status, hold_expires_at
    into v_approval, v_booking, v_hold, v_hexp
  from session_dogs where id = p_session_dog;
  if v_approval <> 'approved' or v_booking is not null then raise exception 'not_payable'; end if;

  -- 홀드 만료 시: 같은 락 안에서 정원 재확인 → 통과하면 바로 부킹 (중간 홀드 잔재 없음)
  if not (v_hold = 'active' and v_hexp > now()) then
    v_reserved := _club_delegated_reserved(sd.session_id);
    if v_reserved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;
  end if;

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
  if v_clash then raise exception 'dog_slot_clash'; end if;

  insert into bookings
    (owner_id, dog_id, runner_id, route_id, status, scheduled_at,
     km, addons, base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values
    (sd.owner_profile_id, sd.dog_id, null, s.route_id, 'matching', s.scheduled_at,
     v_km, '[]', 9900, club_fare(v_km) - 9900, 0, club_fare(v_km), 9900, sd.session_id)
  returning id into v_bid;

  update session_dogs set booking_id = v_bid, hold_status = 'consumed' where id = p_session_dog;
  insert into payment_attempts (session_dog_id, booking_id, kind, idempotency_key, result)
  values (p_session_dog, v_bid, 'charge', p_idem_key, 'ok')
  on conflict (session_dog_id, kind, idempotency_key) where idempotency_key is not null
  do update set result = 'ok', booking_id = excluded.booking_id, detail = null, created_at = now();

  -- [감사 9] 동의 박제 — 이 session_dog의 최신 동의행에 method_consent 각인 (분쟁 근거)
  update delegation_consents set method_consent = true
  where id = (select id from delegation_consents where session_dog_id = p_session_dog
              order by accepted_at desc, id desc limit 1);

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '결제 완료 — 자리 확정',
     to_char(s.scheduled_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
     || ' 위탁이 확정됐어요 — 담당 러너는 집결지에서 배정돼요', v_bid),
    (s.host_profile_id, 'community', '위탁 결제 완료', '위탁 강아지의 결제가 완료됐어요', sd.session_id);
  return v_bid;
end $$;

grant execute on function session_pay_delegation(uuid, text, boolean) to authenticated;

comment on function session_pay_delegation is
  '감사 후속(0053): 0044 본문 + [감사 9] p_method_consent 게이트(distinct from true → method_consent_required)
· 동의를 delegation_consents.method_consent에 박제(분쟁 근거) · 오버로드 회피 위해 2인자 drop 후 3인자 재정의.';
comment on column delegation_consents.method_consent is
  '감사 후속(0053): 결제 시트 배정 방식 동의 박제 — session_pay_delegation 성공 시 최신 동의행에 각인';

-- ---------- §2. club_save_run_trace append 병합 의미론 (감사 10) ----------
-- 0050 본문(무결성 베이스라인) 복사 후 덮어쓰기를 병합으로. 배치 내부 검증은 그대로 두고,
-- 기존 trace가 있으면 마지막 t보다 큰 신규 요소만 append + 경계(기존 마지막→신규 첫) 속도 검증.
create or replace function club_save_run_trace(p_session uuid, p_trace jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int; v_prev jsonb; v_cur jsonb; v_dt numeric; v_dist numeric; i int;
  v_run runs%rowtype; v_existing jsonb; v_last_t numeric; v_add jsonb; v_merged jsonb;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if jsonb_typeof(coalesce(p_trace, 'null'::jsonb)) <> 'array' then raise exception 'bad_trace'; end if;
  -- 배치 내부 시퀀스 검증: t 단조 증가 · 불가능 속도(>8 m/s) 거부 (기존과 동일)
  for i in 1..coalesce(jsonb_array_length(p_trace), 0) - 1 loop
    v_prev := p_trace->(i - 1); v_cur := p_trace->i;
    v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
    if v_dt <= 0 then raise exception 'trace_out_of_order'; end if;
    v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
    if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
  end loop;

  -- 병합: 대상 런(active·본인)별로 기존 trace에 신규 tail만 이어붙인다.
  n := 0;
  for v_run in
    select r.* from runs r join bookings b on b.id = r.booking_id
    where b.club_session_id = p_session and b.runner_id = auth.uid() and b.status = 'active'
  loop
    v_existing := coalesce(v_run.trace, '[]'::jsonb);
    if jsonb_typeof(v_existing) <> 'array' then v_existing := '[]'::jsonb; end if;

    if jsonb_array_length(v_existing) = 0 then
      v_merged := p_trace;                                             -- 빈 기존 → 신규 전체
    else
      v_last_t := (v_existing->(jsonb_array_length(v_existing) - 1)->>'t')::numeric;
      -- 기존 마지막 t보다 큰 신규 요소만 (전량 재전송/부분 재전송 모두 dedup — 유실·중복 없음)
      select jsonb_agg(e order by (e->>'t')::numeric)
        into v_add
        from jsonb_array_elements(p_trace) e
        where (e->>'t')::numeric > v_last_t;
      if v_add is null or jsonb_array_length(v_add) = 0 then
        v_merged := v_existing;                                       -- 추가분 없음 (오래된 배치)
      else
        -- 경계 무결성: 기존 마지막 → 신규 첫 (필터로 v_dt>0 보장) 속도 검증
        v_cur := v_add->0;
        v_prev := v_existing->(jsonb_array_length(v_existing) - 1);
        v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
        v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                     + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
        if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
        v_merged := v_existing || v_add;                             -- append
      end if;
    end if;

    update runs set trace = v_merged where id = v_run.id;
    n := n + 1;
  end loop;
  return n;
end $$;

comment on function club_save_run_trace is
  '감사 후속(0053): 0050 무결성 베이스라인 + append 병합(감사 10) — 기존 마지막 t 초과 신규 tail만 이어붙임
· 배치 내부 + 경계(기존 마지막→신규 첫) t 단조·8m/s 검증 유지 · 전량/부분 재전송 dedup(유실·중복 0).';

-- ---------- §3a. 러닝 사진 photo_consent 읽기측 게이트 (감사 11a) ----------
-- 위탁 부킹의 session_dog에 연결된 최신 delegation_consents.photo_consent가 true인지.
-- 위탁 부킹이 아니면 true(일반 예약은 기존 동의 체계) — 소비(shareRunToFeed·베스트샷)는 patcher가 배선.
-- [rev2 P2] 당사자 게이트를 머리에 추가 — 임의 booking uuid의 위탁/동의 상태 프로빙 오라클 차단.
-- raise가 필요하므로 sql → plpgsql 전환(본문 판정 로직은 동일). 호출자가 그 부킹의 보호자
-- (bookings.owner_id)·러너(bookings.runner_id)·세션 호스트가 아니면(부킹 부재 포함) not_party.
create or replace function club_run_photo_allowed(p_booking uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (
    select 1 from bookings b
    left join club_sessions s on s.id = b.club_session_id
    where b.id = p_booking
      and (b.owner_id = auth.uid() or b.runner_id = auth.uid()
           or s.host_profile_id = auth.uid())
  ) then
    raise exception 'not_party';
  end if;
  return (select case
    when not exists (select 1 from session_dogs sd
                     where sd.booking_id = p_booking and sd.custody = 'runner_delegated')
      then true                                                       -- 위탁 부킹 아님 → 기존 체계
    else coalesce((
      select dc.photo_consent
      from session_dogs sd
      join delegation_consents dc on dc.session_dog_id = sd.id
      where sd.booking_id = p_booking and sd.custody = 'runner_delegated'
      order by dc.accepted_at desc, dc.id desc
      limit 1), false)                                                -- 동의행 없음 = 미동의(안전측)
  end);
end $$;
revoke execute on function club_run_photo_allowed(uuid) from public, anon;
grant execute on function club_run_photo_allowed(uuid) to authenticated;

comment on function club_run_photo_allowed is
  '감사 후속(0053, 감사 11a + rev2 P2): 당사자(owner/runner/host)만 조회 가능(아니면 not_party — 프로빙
오라클 차단) · 위탁 부킹의 최신 delegation_consents.photo_consent 게이트 — 미동의 견 사진 공개 차단(false)
· 위탁 아니면 true. §3b(비공개 버킷+서명 URL)는 별도 슬라이스(머리 주석 계획 참조).';

-- ---------- §4. 보드에 자기 rejected/withdrawn 카드 노출 (정직한 마지막 말) ----------
-- 0052 _club_delegation_board_impl 전 동작 유지(등급 필터·openIncidentId·session/runners 필터) —
-- dogs where의 첫 절만 넓혀 caller 본인의 rejected/withdrawn 카드 1개를 보이게 한다. **자기 것만**
-- (타인 거절은 등급 필터 owner=uid로 여전히 안 보임). 아래 §5 상호작용 결론과 정합.
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
        -- [0053 §4] 활성/부킹 있음 또는 **자기 것**의 rejected/withdrawn (정직한 마지막 말 도달)
        and (d.service_state is distinct from 'ended' or d.booking_id is not null
             or (d.owner_profile_id = auth.uid() and d.approval in ('rejected', 'withdrawn')))
        -- [rev2 P1] host/full=전체 · limited=자기 개만 · none=[] (both false → 제외)
        and (p_access in ('host', 'full')
             or (p_access = 'limited' and d.owner_profile_id = auth.uid()))), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

revoke execute on function _club_delegation_board_impl(uuid, text) from public, anon, authenticated;

comment on function _club_delegation_board_impl is
  '보드 v8 (0053) — 0052 rev2 등급 필터·openIncidentId 전부 유지 + [0053 §4] dogs where에 자기
rejected/withdrawn 카드 노출(자기 것만: 등급 필터 owner=uid로 타인 거절은 여전히 비공개).';

-- ---------- §6. club_session_detail people 게이트 host/full 축소 (rev2 P1, 리뷰 재검토) ----------
-- [rev2 P1] 0052 최신 본문 충실 복사 + people 게이트만 `= 'none'`(거절/철회 limited 통과) → `in
-- ('host','full')`로 좁힘. limited(거절/철회 신청자)는 담당 러너 실명·역할·출결을 더는 못 본다.
-- peopleCount는 등급 무관 유지(공개 카운트) · dogCount·nextSessionId·isMe·정렬 전부 보존.
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
    -- [rev2 P1] people은 host/full에게만 (거절/철회 limited는 []) — peopleCount는 위에서 등급 무관 유지
    'people', case when _club_shell_access(s.id, auth.uid()) in ('host', 'full') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', pr.name, 'avatarUrl', pr.avatar_url, 'role', sp.role, 'attendance', sp.attendance,
        'isMe', sp.profile_id = auth.uid(),
        'dogName', (select d.name from session_dogs sd join dogs d on d.id = sd.dog_id
                    where sd.session_id = s.id and sd.owner_profile_id = sp.profile_id limit 1)
      ) order by sp.created_at, (sp.role <> 'host_runner'), pr.name)  -- 동시각 타이는 호스트 우선 (빕 001 = 호스트)
      from session_people sp join profiles pr on pr.id = sp.profile_id
      where sp.session_id = s.id), '[]'::jsonb) else '[]'::jsonb end
  )
  from club_sessions s where s.id = p_session;
$$;

grant execute on function club_session_detail(uuid) to authenticated;

comment on function club_session_detail is
  '세션 상세 v5 (0053 rev2 P1) — people은 _club_shell_access in (host,full)인 당사자에게만(거절/철회 limited는
[]), peopleCount는 항상 (문 앞 정직). 0052 v4 대비 게이트만 none→host/full로 좁힘.';

-- ---------- §7. club_session_roster people/전화로그 게이트 host/full 축소 (rev2 P1) ----------
-- [rev2 P1] 0049 최신 본문 충실 복사 + v_people(사람 배열)을 v_access in ('host','full')일 때만 채움
-- (limited는 []) · 전화 열람 로그 insert도 host/full일 때만(로그가 people 노출과 짝). not_party(none)
-- 게이트·dogs 등급 필터·capacityMeter 전부 보존.
create or replace function club_session_roster(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_access text; v_people jsonb; v_dogs jsonb; s record;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into s from club_sessions where id = p_session;
  if s.id is null then raise exception 'not_found'; end if;
  v_access := _club_shell_access(p_session, auth.uid());
  if v_access = 'none' then raise exception 'not_party'; end if;

  -- [rev2 P1] 사람 배열과 전화 열람 로그는 host/full에게만 (limited는 people=[], 로그도 남기지 않음)
  if v_access in ('host', 'full') then
    -- 사람: 참석자 + 커밋 러너 + 호스트 (전화는 규칙 B — 반환 시에만 접근 로그)
    with roster as (
      select p.id, p.name, p.avatar_url,
             coalesce(sp.role, case when a.runner_profile_id is not null then 'handling_runner' end,
                      case when p.id = s.host_profile_id then 'host' end) as role,
             sp.attendance,
             a.delegated_capacity as runner_cap,
             _club_phone_visible(p_session, auth.uid(), p.id) as phone_ok,
             p.phone
      from profiles p
      left join session_people sp on sp.session_id = p_session and sp.profile_id = p.id
      left join session_runner_assignments a
        on a.session_id = p_session and a.runner_profile_id = p.id and a.status = 'committed'
      where sp.profile_id is not null or a.runner_profile_id is not null
         or p.id in (s.host_profile_id, s.backup_host_profile_id)
         or exists (select 1 from session_dogs sd where sd.session_id = p_session
                    and sd.owner_profile_id = p.id and sd.custody = 'runner_delegated'
                    and sd.service_state is distinct from 'ended')   -- 위탁 보호자도 로스터의 사람이다
    )
    select jsonb_agg(jsonb_build_object(
      'profileId', id, 'name', name, 'avatarUrl', avatar_url,
      'role', role, 'attendance', attendance, 'runnerCap', runner_cap,
      'isHost', id = s.host_profile_id, 'isBackup', id = s.backup_host_profile_id,
      'isMe', id = auth.uid(),
      'phone', case when phone_ok then phone end,
      'phoneVia', case when phone_ok then 'direct' else 'host' end
    ) order by (id = s.host_profile_id) desc, name)
    into v_people from roster;

    -- 전화 접근 로그 (실제 반환된 번호만, 세션·뷰어·대상 단위 dedup)
    insert into club_phone_access_log (session_id, viewer_profile_id, target_profile_id)
    select p_session, auth.uid(), p.id
    from profiles p
    where _club_phone_visible(p_session, auth.uid(), p.id) and p.phone is not null
      and p.id <> auth.uid()
      and (exists (select 1 from session_people sp where sp.session_id = p_session and sp.profile_id = p.id)
           or exists (select 1 from session_runner_assignments a where a.session_id = p_session
                      and a.runner_profile_id = p.id and a.status = 'committed')
           or p.id in (s.host_profile_id, s.backup_host_profile_id))
      and not exists (select 1 from club_phone_access_log l
                      where l.session_id = p_session and l.viewer_profile_id = auth.uid()
                        and l.target_profile_id = p.id);
  end if;

  -- 강아지: 능력별 필터 — 호스트=전부 · 담당 러너=자기 배정견 상세 · 보호자=자기 개 상세, 타견 최소
  select coalesce(jsonb_agg(jsonb_build_object(
    'sdId', sd.id, 'dogName', d.name, 'collar', d.collar, 'custody', sd.custody,
    'ownerName', (select name from profiles where id = sd.owner_profile_id),
    'isMine', sd.owner_profile_id = auth.uid(),
    'detail', case
      when v_access = 'host' or sd.owner_profile_id = auth.uid()
           or exists (select 1 from bookings b where b.id = sd.booking_id and b.runner_id = auth.uid())
      then jsonb_build_object(
        'memo', d.memo, 'weightKg', d.weight_kg, 'breed', d.breed,
        'emergencyContact', (select dc.emergency_contact from delegation_consents dc
                             where dc.session_dog_id = sd.id order by dc.accepted_at desc limit 1),
        'pickupName', (select dc.pickup_name from delegation_consents dc
                       where dc.session_dog_id = sd.id order by dc.accepted_at desc limit 1),
        'vetLimitKrw', (select dc.vet_limit_krw from delegation_consents dc
                        where dc.session_dog_id = sd.id order by dc.accepted_at desc limit 1))
      end,
    'chargeLabel', case when v_access = 'host' then sd.charge_state end   -- 호스트 읽기 전용 라벨
  ) order by sd.seq), '[]'::jsonb)
  into v_dogs
  from session_dogs sd join dogs d on d.id = sd.dog_id
  where sd.session_id = p_session and sd.service_state is distinct from 'ended';

  return jsonb_build_object(
    'access', v_access,
    'people', coalesce(v_people, '[]'::jsonb),
    'dogs', case when v_access in ('host', 'full') then v_dogs
                 else (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(v_dogs) e
                       where (e->>'isMine')::boolean) end,   -- limited = 자기 기록만
    'capacityMeter', case when v_access = 'host' then jsonb_build_object(
      'reserved', _club_delegated_reserved(p_session),
      'capacity', s.delegated_dog_capacity,
      'viability', club_session_viability(p_session)) end
  );
end $$;
grant execute on function club_session_roster(uuid) to authenticated;

comment on function club_session_roster is
  '로스터 v2 (0053 rev2 P1) — 0049 본문 + people 배열·전화 열람 로그를 v_access in (host,full)일 때만
(거절/철회 limited는 people=[], 로그 없음) · not_party(none) 게이트·dogs 등급 필터·capacityMeter 보존.';

-- ---------- §5. _club_shell_access / _club_chat_writable 상호작용 결론 (변경 없음) ----------
-- §4는 보호자가 자기 거절·철회 카드('정직한 마지막 말')를 보게 한다. §5의 위험은 만약 shell_access가
-- 거절 후 access를 'none'으로 내리면 board 게이트(0052: none → dogs=[])가 그 카드를 다시 가리는 것.
-- 그러나 0049 _club_shell_access의 limited 분기는 'session_delegate_dog 이력'만으로 서므로 거절/철회
-- 후에도 limited가 유지된다 → board가 자기 카드를 보인다. 그리고 0052 등급 필터로 limited board는
-- **자기 개만**, club_session_detail people=[]이므로 limited가 영구 유지돼도 새는 건 자기 것뿐이다.
--   ⇒ 결론: _club_shell_access는 **변경하지 않는다**. 0052 등급 필터가 이미 누수를 막았다.
--
-- 채팅 쓰기 점검(§5 필수): _club_chat_writable(0049:29)은 limited(거절자 포함)에게 세션 open 동안
-- true를 준다. 그러나 실제 누수 여부는 club_chat_messages insert 정책(0049:85)이 결정한다:
--   · 그룹(audience='group') insert는 shell_access in ('host','full') AND recipient null을 **추가로**
--     요구한다 → limited(거절/철회자)는 그룹 채팅 쓰기 불가. (67_shell H2가 이미 이 거부를 핀)
--   · host_channel은 recipient=본인일 때만 limited가 쓸 수 있다 = 호스트↔신청자 사문의 채널(의도됨,
--     거절 통보를 받고 마지막 말을 나누는 바로 그 통로). 그룹 로스터로는 한 글자도 못 쓴다.
--   ⇒ 결론: 그룹 채팅 쓰기는 이미 등급으로 닫혀 있어 실질 누수 아님. _club_chat_writable도
--     **변경하지 않는다**. (거절 후 열리는 건 자기 host_channel 스레드뿐 = §4의 '정직한 마지막 말'과 정합)
-- (이 판단의 회귀 핀은 96_audit_followups_suite.sql F5에 둔다.)
