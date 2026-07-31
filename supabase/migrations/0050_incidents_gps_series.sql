-- ═══ 0050: R6 — 인시던트 배선/SOS/증거 · GPS 세그먼트 베이스라인 · 시리즈 회차 정체성 (v3.3 §8·§13) ═══
-- 인시던트 테이블은 R0A부터 있었다 — R6는 참가자 '입'을 연다: 개설·SOS·증거·열람.
-- 원칙: 강아지에 열린 인시던트 ⇒ payout_hold=held (릴리스 직렬화 지점 법) ∧ 무동의 취소 차단 (§8·§11).

-- ---------- A. 인시던트 개설 (참가자) — 대상 강아지 지급 보류는 세션 락 아래에서 ----------
create or replace function club_incident_open(
  p_session uuid, p_severity text, p_summary text,
  p_dog uuid default null, p_booking uuid default null, p_location jsonb default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare s record; v_inc uuid; v_sd record;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_severity not in ('S1', 'S2', 'S3') then raise exception 'bad_severity'; end if;
  if coalesce(trim(p_summary), '') = '' then raise exception 'summary_required'; end if;
  select * into s from club_sessions where id = p_session for update;
  if s.id is null then raise exception 'not_found'; end if;
  if _club_shell_access(p_session, auth.uid()) = 'none' then raise exception 'not_party'; end if;

  insert into club_incidents (session_id, severity, state, opened_by, summary)
  values (p_session, p_severity, 'open', auth.uid(), trim(p_summary))
  returning id into v_inc;
  insert into club_incident_subjects (incident_id, subject_type, subject_id)
  values (v_inc, 'session', p_session);
  if p_dog is not null then
    insert into club_incident_subjects (incident_id, subject_type, subject_id) values (v_inc, 'dog', p_dog);
    -- 강아지에 열린 인시던트 ⇒ 지급 보류 (릴리스 크론의 직렬화 지점 — 세션 락 하에서 씀)
    -- ended 행도 보류한다: 서비스 종료 후 분쟁(반환·정산 시비)이 정확히 payable을 막아야 하는
    -- 경우다 — 레이스 검사(RC)가 잡은 결함: ended 필터가 지급 보류를 무력화했다
    for v_sd in select id from session_dogs
      where session_id = p_session and dog_id = p_dog and custody = 'runner_delegated'
        and payout_state <> 'released'
    loop
      update session_dogs set payout_hold = 'held', payout_hold_reason = 'incident',
        payout_hold_incident = v_inc where id = v_sd.id;
    end loop;
  end if;
  if p_booking is not null then
    insert into club_incident_subjects (incident_id, subject_type, subject_id) values (v_inc, 'booking', p_booking);
  end if;
  if p_location is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (v_inc, 'location', p_location, auth.uid());
  end if;

  -- S1/S2 = 크리티컬 (제목 레지스트리 → ack 배너) · S3 = 커뮤니티 잉크
  insert into notifications (profile_id, kind, title, body, ref_id)
  select p.pid, (case when p_severity = 'S3' then 'community' else 'safety' end)::noti_kind,   -- CASE는 text로 굳는다 (0028 이넘 교훈)
         case when p_severity = 'S3' then '인시던트 접수' else '인시던트 발생' end,
         '[' || p_severity || '] ' || trim(p_summary) || ' — 케이스를 확인하세요', p_session
  from (select s.host_profile_id as pid
        union select s.backup_host_profile_id where s.backup_host_profile_id is not null) p
  where p.pid is not null and p.pid <> auth.uid();
  return v_inc;
end $$;

-- SOS = S1 인시던트 슈가 — 누르는 순간이 급하다: 최소 입력, 최대 팬아웃
create or replace function club_sos(p_session uuid, p_location jsonb default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_inc uuid;
begin
  v_inc := club_incident_open(p_session, 'S1', '긴급 SOS', null, null, p_location);
  -- 커밋 러너 전원에게도 (현장의 손이 가장 가깝다)
  insert into notifications (profile_id, kind, title, body, ref_id)
  select a.runner_profile_id, 'safety', '인시던트 발생', '[S1] 긴급 SOS — 주변을 확인하세요', p_session
  from session_runner_assignments a
  where a.session_id = p_session and a.status = 'committed' and a.runner_profile_id <> auth.uid()
    and not exists (select 1 from notifications n where n.profile_id = a.runner_profile_id
                    and n.ref_id = p_session and n.title = '인시던트 발생'
                    and n.created_at > now() - interval '5 minutes');
  return v_inc;
end $$;

-- 증거 추가 — 케이스 당사자(개설자·케이스 오너·호스트·대상 강아지 당사자)만
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
  if not (auth.uid() in (i.opened_by, i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                     and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
          or exists (select 1 from club_incident_subjects sub
                     join session_dogs sd on sd.dog_id = sub.subject_id and sd.session_id = i.session_id
                     left join bookings b on b.id = sd.booking_id
                     where sub.incident_id = p_incident and sub.subject_type = 'dog'
                       and (sd.owner_profile_id = auth.uid() or b.runner_id = auth.uid()))) then
    raise exception 'not_case_party';
  end if;
  insert into club_incident_evidence (incident_id, kind, payload, created_by)
  values (p_incident, p_kind, p_payload, auth.uid());
end $$;

-- 케이스 열람 초크포인트 (테이블은 봉인 유지)
create or replace function club_incident_detail(p_incident uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i record;
begin
  select * into i from club_incidents where id = p_incident;
  if i.id is null then raise exception 'not_found'; end if;
  if not (auth.uid() in (i.opened_by, i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                     and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
          or exists (select 1 from club_incident_subjects sub
                     join session_dogs sd on sd.dog_id = sub.subject_id and sd.session_id = i.session_id
                     left join bookings b on b.id = sd.booking_id
                     where sub.incident_id = p_incident and sub.subject_type = 'dog'
                       and (sd.owner_profile_id = auth.uid() or b.runner_id = auth.uid()))) then
    raise exception 'not_case_party';
  end if;
  return jsonb_build_object(
    'id', i.id, 'severity', i.severity, 'state', i.state, 'summary', i.summary,
    'openedBy', i.opened_by, 'caseOwner', i.case_owner,
    'openedAt', i.opened_at, 'resolvedAt', i.resolved_at,
    'subjects', (select coalesce(jsonb_agg(jsonb_build_object(
       'type', sub.subject_type, 'id', sub.subject_id)), '[]'::jsonb)
       from club_incident_subjects sub where sub.incident_id = p_incident),
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object(
       'kind', e.kind, 'payload', e.payload, 'by', e.created_by, 'at', e.created_at)
       order by e.created_at), '[]'::jsonb)
       from club_incident_evidence e where e.incident_id = p_incident));
end $$;

grant execute on function club_incident_open(uuid, text, text, uuid, uuid, jsonb) to authenticated;
grant execute on function club_sos(uuid, jsonb) to authenticated;
grant execute on function club_incident_evidence_add(uuid, text, jsonb) to authenticated;
grant execute on function club_incident_detail(uuid) to authenticated;

insert into club_critical_titles (title) values ('인시던트 발생') on conflict do nothing;

-- 해소 시 인시던트 지급 보류 해제 (외부 커스터디 보류는 유지) — 최신 정의 = 0045
create or replace function club_incident_resolve(p_incident uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_session uuid; v_owner uuid; v_sd record;
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

-- ---------- B. GPS 베이스라인: 세그먼트는 시작 시 태어난다 + 트레이스 무결성 (최신 정의 = 0038) ----------
create or replace function club_start_delegated_runs(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; v_id uuid; v_run uuid; v_sd uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select coalesce(array_agg(b.id), '{}') into v_ids
  from bookings b
  where b.club_session_id = p_session and b.runner_id = auth.uid() and b.status = 'picked_up';
  if array_length(v_ids, 1) is null then raise exception 'nothing_to_start'; end if;

  foreach v_id in array v_ids loop
    update bookings set status = 'active' where id = v_id;           -- picked_up → active (허용 전이)
    insert into runs (booking_id, started_at) values (v_id, now())
    on conflict (booking_id) do nothing;
    -- [R6] 세그먼트 = 시작 시 생성 (이양 때가 아니라) — 개의 기록은 세그먼트의 합 (§13)
    select r.id into v_run from runs r where r.booking_id = v_id;
    select sd.id into v_sd from session_dogs sd where sd.booking_id = v_id;
    insert into dog_run_segments (session_dog_id, run_id, runner_profile_id, joined_at)
    select v_sd, v_run, auth.uid(), now()
    where v_sd is not null
      and not exists (select 1 from dog_run_segments g
                      where g.session_dog_id = v_sd and g.run_id = v_run and g.left_at is null);
  end loop;

  insert into notifications (profile_id, kind, title, body, ref_id)
  select b.owner_id, 'booking', '러닝 시작', b.km || 'km 클럽 러닝이 시작됐어요 — 실시간으로 지켜보세요', b.id
  from bookings b where b.id = any(v_ids);

  return to_jsonb(v_ids);
end $$;

-- 트레이스 무결성 (§13 베이스라인): 서버 검증 — 불가능 속도 거부·시퀀스 검증·서버 타임스탬프
create or replace function club_save_run_trace(p_session uuid, p_trace jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int; v_prev jsonb; v_cur jsonb; v_dt numeric; v_dist numeric; i int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if jsonb_typeof(coalesce(p_trace, 'null'::jsonb)) <> 'array' then raise exception 'bad_trace'; end if;
  -- 시퀀스 검증: t 단조 증가 · 불가능 속도(>8 m/s ≈ 3'30"/km보다 빠른 지속 이동 + 점프) 거부
  for i in 1..coalesce(jsonb_array_length(p_trace), 0) - 1 loop
    v_prev := p_trace->(i - 1); v_cur := p_trace->i;
    v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
    if v_dt <= 0 then raise exception 'trace_out_of_order'; end if;
    -- 등장방형 근사 (성수동 위도) — 미터 단위
    v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
    if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
  end loop;
  update runs r set trace = p_trace
  from bookings b
  where r.booking_id = b.id and b.club_session_id = p_session
    and b.runner_id = auth.uid() and b.status = 'active';
  get diagnostics n = row_count;
  return n;
end $$;

-- 정산 시 열린 세그먼트 폐쇄 — 최신 커스터디 전이 트리거(0045)에 결합
create or replace function _club_close_segments_tg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.club_session_id is null or new.status <> 'completed' then return new; end if;
  update dog_run_segments g set left_at = now()
  from session_dogs sd
  where sd.booking_id = new.id and g.session_dog_id = sd.id and g.left_at is null;
  return new;
end $$;
drop trigger if exists club_close_segments on bookings;
create trigger club_close_segments after update of status on bookings
  for each row when (new.club_session_id is not null) execute function _club_close_segments_tg();

-- ---------- C. 시리즈 회차 정체성 — 생성이 series_id를 남기지 않던 결함 수정 + 회차 유일성 ----------
alter table club_sessions add column if not exists occurrence_date date;
create unique index if not exists club_sessions_series_occurrence_uni
  on club_sessions (series_id, occurrence_date) where series_id is not null;

create or replace function club_generate_club_sessions() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_now_kst timestamp := now() at time zone 'Asia/Seoul';
  v_days int; v_next_kst timestamp; v_next timestamptz;
  v_sid uuid; v_host uuid; v_made int := 0;
begin
  for r in
    select s.id, s.club_id, (s.recurrence_rule->>'weekday')::int as wd, s.recurrence_rule->>'time' as tm,
           s.default_route_id, s.meetup_point, s.people_capacity, c.name as club_name, c.host_profile_id
    from club_series s join clubs c on c.id = s.club_id
    where s.status = 'active' and c.status = 'active'
      and s.recurrence_rule ? 'weekday' and s.recurrence_rule ? 'time'
  loop
    v_days := (r.wd - extract(dow from v_now_kst)::int + 7) % 7;
    v_next_kst := date_trunc('day', v_now_kst) + make_interval(days => v_days) + (r.tm)::time;
    if v_next_kst <= v_now_kst then v_next_kst := v_next_kst + interval '7 days'; end if;
    v_next := v_next_kst at time zone 'Asia/Seoul';

    continue when v_next > now() + interval '72 hours';
    continue when v_next < now() + interval '2 hours';
    continue when exists (
      select 1 from club_sessions cs
      where cs.club_id = r.club_id and cs.status <> 'cancelled'
        and cs.scheduled_at between v_next - interval '1 hour' and v_next + interval '1 hour'
    );

    v_host := r.host_profile_id;
    -- [R6] series_id·occurrence_date 기록 — 회차 정체성 (유일 인덱스가 이중 생성을 구조적으로 차단)
    begin
      insert into club_sessions (club_id, host_profile_id, scheduled_at, route_id, meetup_point,
                                 people_capacity, series_id, occurrence_date)
      values (r.club_id, v_host, v_next, r.default_route_id, r.meetup_point, r.people_capacity,
              r.id, (v_next_kst)::date)
      returning id into v_sid;
    exception when unique_violation then
      continue;                                        -- 같은 회차 재생성 시도 = 구조적 무시
    end;
    insert into session_people (session_id, profile_id, role) values (v_sid, v_host, 'host_runner');

    insert into notifications (profile_id, kind, title, body, ref_id)
    select m.profile_id, 'community', '⟳ ' || r.club_name || ' 정기 세션 열림',
           to_char(v_next_kst, 'MM/DD HH24:MI') || ' · ' || coalesce(r.meetup_point, '집결지 미정') || ' — 참여 신청하세요',
           v_sid
    from club_members m
    where m.club_id = r.club_id and m.profile_id <> v_host;

    v_made := v_made + 1;
  end loop;
  return v_made;
end $$;

comment on function club_incident_open is
  'R6(0050): 참가자 인시던트 개설 — 대상견 payout_hold=held(세션 락 하) · S1/S2=크리티컬 ack';
comment on function club_sos is 'R6(0050): SOS = S1 슈가 — 호스트·백업·커밋 러너 팬아웃';
comment on function club_save_run_trace is
  'R6(0050): 트레이스 무결성 베이스라인 — t 단조·불가능 속도(>8m/s) 거부 (§13)';
comment on function club_generate_club_sessions is
  'R6(0050): 시리즈 생성이 series_id·occurrence_date를 기록 — 회차 유일 인덱스로 이중 생성 차단';

-- ---------- D. 취소 v2 — 열린 인시던트 = 무동의 취소 차단 (최신 정의 = 0048) ----------
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
  -- [R6 §8·§11] 강아지에 열린 인시던트 ⇒ 무동의 취소 차단 — 분쟁은 케이스로 푼다
  if exists (select 1 from club_incident_subjects sub join club_incidents i on i.id = sub.incident_id
             where sub.subject_type = 'dog' and sub.subject_id = sd.dog_id and i.state <> 'resolved') then
    raise exception 'incident_open';
  end if;

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
