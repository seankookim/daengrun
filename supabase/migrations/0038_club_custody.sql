-- ═══ 0038: P-C 슬라이스 2 — 배정·커스터디 전환·공유 러닝 팬아웃 (hi-club-plan v2.1 §2-6 P-C) ═══
-- 0037(등록→커밋→승인→부킹)에 이어 세션 당일의 실행 레이어를 채운다.
--
-- 핵심 결정:
-- - 커스터디 전환은 새 메커니즘이 아니다 [§2-0]: 기존 부킹별 양측 인계 확인
--   (owner/runner_confirmed_handoff_at → picked_up, transition-booking 그대로)이 보험 기점.
--   세션은 그 N건에 공유 장소·창구를 줄 뿐. responsible_profile_id 플립은 부킹 상태 트리거가
--   수행 — 어떤 경로로 전이돼도 책임 불변식이 서버에서 유지된다 (0034 트리거 선례).
-- - 배정은 호스트가 체크인 창(시작 -2h~+6h, session_checkin과 동일)에서 수행. 러너별 캡은
--   배정 시점에 재검증 (승인 정원과 별개로, 실제 배정도 개인 캡을 넘을 수 없다).
-- - 공유 GPS 트레이스 → N runs 팬아웃 [§2-2]: 시작·트레이스 저장만 세션 단위 팬아웃 RPC.
--   이벤트(응가 도장 등)는 특정 강아지의 사실이므로 기존 per-booking append 유지.
-- - 정산은 기존 settle-run(부킹별) 그대로 — 강아지별 완료/조기 종료가 자연히 부킹별로 귀결.
--   완료 시 participant_activities에 gps_verified 기록 (runs 트리거 — 측정 출처 명시 §2-0).
-- - 0037 갭 마감: confirmed+ 상태가 생기므로 — 이탈은 배정 해제 전 차단, 취소는 주행 중 차단
--   + confirmed 부킹은 2단 전이(cancelled_runner→refund_pending)로 환불, 종료 정리도 동일.

-- ---------- 배정 (호스트, 체크인 창) — 승인 위탁견 → 커밋 러너 ----------
create or replace function session_assign_dog(p_session_dog uuid, p_runner uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_cap int; v_assigned int; v_bstatus text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if s.status not in ('open', 'full') then raise exception 'session_closed'; end if;
  if now() < s.scheduled_at - interval '2 hours' or now() > s.scheduled_at + interval '6 hours' then
    raise exception 'assign_window';
  end if;
  if sd.custody <> 'runner_delegated' or sd.approval <> 'approved' or sd.booking_id is null then
    raise exception 'not_approved';
  end if;

  -- 러너 자격: committed 배정 + 본인 체크인 완료 (현장에 있는 러너에게만 강아지가 간다)
  select delegated_capacity into v_cap from session_runner_assignments
  where session_id = sd.session_id and runner_profile_id = p_runner and status = 'committed';
  if v_cap is null then raise exception 'runner_not_committed'; end if;
  if not exists (select 1 from session_people
                 where session_id = sd.session_id and profile_id = p_runner and attendance = 'checked_in') then
    raise exception 'runner_not_checked_in';
  end if;

  -- 개인 캡 재검증 — 배정 실개수 기준 (승인 정원과 별개의 2차 방어선)
  select count(*) into v_assigned
  from session_dogs x join bookings b on b.id = x.booking_id
  where x.session_id = sd.session_id and x.custody = 'runner_delegated'
    and b.runner_id = p_runner and b.status in ('confirmed', 'picked_up', 'active', 'completed')
    and x.id <> sd.id;
  if v_assigned >= v_cap then raise exception 'runner_cap_full'; end if;

  select status into v_bstatus from bookings where id = sd.booking_id for update;
  if v_bstatus = 'matching' then
    -- 첫 배정: matching → confirmed + 인계 스탬프 초기화 (runner_accept 선례 — 잔재 스탬프 사고 방지)
    update bookings set runner_id = p_runner, status = 'confirmed',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  elsif v_bstatus = 'confirmed' then
    -- 재배정: 인계 전까지만 — 러너만 교체, 스탬프 초기화 (상태 불변)
    update bookings set runner_id = p_runner,
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  else
    raise exception 'already_handed_off';
  end if;

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '담당 러너 배정',
     (select name from profiles where id = p_runner) || ' 러너가 아이의 담당으로 배정됐어요 — 집결지에서 인계를 확인하세요', sd.booking_id),
    (p_runner, 'booking', '위탁 배정 도착',
     (select name from dogs where id = sd.dog_id) || ' — 보호자와 인계를 확인하고 러닝을 시작하세요', sd.booking_id);
end $$;

-- ---------- 커스터디 트리거 — 책임 불변식의 서버 소유 (어떤 전이 경로에서도) ----------
-- picked_up(양측 인계 확인 완료 = 보험 기점): 책임자 → 담당 러너, 강아지 체크인.
-- completed(정산): 강아지 체크아웃 + 책임자 → 보호자 복귀 (러닝 종료 = 반환).
create or replace function _club_custody_transition() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.club_session_id is null then return new; end if;
  if new.status = 'picked_up' and new.runner_id is not null then
    update session_dogs set responsible_profile_id = new.runner_id, checked_in_at = coalesce(checked_in_at, now())
    where booking_id = new.id;
  elsif new.status = 'completed' then
    update session_dogs set responsible_profile_id = owner_profile_id, checked_out_at = coalesce(checked_out_at, now())
    where booking_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists club_custody_transition on bookings;
create trigger club_custody_transition after update of status on bookings
  for each row when (new.club_session_id is not null) execute function _club_custody_transition();

-- ---------- 러닝 시작 팬아웃 — 인계 완료된 내 위탁견 전부 한 번에 ----------
create or replace function club_start_delegated_runs(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; v_id uuid;
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
  end loop;

  insert into notifications (profile_id, kind, title, body, ref_id)
  select b.owner_id, 'booking', '러닝 시작', b.km || 'km 클럽 러닝이 시작됐어요 — 실시간으로 지켜보세요', b.id
  from bookings b where b.id = any(v_ids);

  return to_jsonb(v_ids);
end $$;

-- ---------- 공유 트레이스 팬아웃 — 한 GPS 트랙 → 내 위탁견 N runs (§2-2) ----------
-- 이벤트(응가 등)는 특정 강아지의 사실 — 기존 append_run_event(부킹별) 유지, 트레이스만 공유.
create or replace function club_save_run_trace(p_session uuid, p_trace jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if jsonb_typeof(coalesce(p_trace, 'null'::jsonb)) <> 'array' then raise exception 'bad_trace'; end if;
  update runs r set trace = p_trace
  from bookings b
  where r.booking_id = b.id and b.club_session_id = p_session
    and b.runner_id = auth.uid() and b.status = 'active';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- 활동 기록 트리거 — 위탁 완료 = participant_activities(gps_verified) ----------
-- 측정 출처 명시(§2-0)의 스키마화: GPS 위탁런만 verified. person_id는 null (강아지의 활동).
create or replace function _club_log_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_session uuid; v_dog uuid;
begin
  if new.end_reason is null then return new; end if;
  select b.club_session_id, b.dog_id into v_session, v_dog
  from bookings b where b.id = new.booking_id;
  if v_session is null then return new; end if;
  if exists (select 1 from participant_activities where session_id = v_session and run_id = new.id) then
    update participant_activities
    set km = new.actual_km, pace_sec_per_km = new.avg_pace_sec_per_km, duration_sec = new.duration_sec
    where session_id = v_session and run_id = new.id;
  else
    insert into participant_activities (session_id, person_id, dog_id, km, pace_sec_per_km, duration_sec, source, run_id)
    values (v_session, null, v_dog, new.actual_km, new.avg_pace_sec_per_km, new.duration_sec, 'gps_verified', new.id);
  end if;
  return new;
end $$;

drop trigger if exists club_log_activity on runs;
create trigger club_log_activity after insert or update of end_reason on runs
  for each row execute function _club_log_activity();

-- ---------- 0037 갭 마감 ① — 이탈은 배정 해제가 먼저 (강아지가 걸린 이탈 차단) ----------
create or replace function session_runner_withdraw(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_new_cap int; v_approved int; v_excess int; v_row record; v_host uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select host_profile_id into v_host from club_sessions where id = p_session for update;
  if v_host is null then raise exception 'not_found'; end if;

  -- [0038] 이미 배정받은 강아지(confirmed+)가 있으면 이탈 불가 — 호스트가 재배정 후에야 가능
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

  select count(*) into v_approved from session_dogs
  where session_id = p_session and custody = 'runner_delegated' and approval = 'approved';
  v_excess := v_approved - v_new_cap;
  if v_excess > 0 then
    for v_row in
      select id, owner_profile_id, booking_id from session_dogs
      where session_id = p_session and custody = 'runner_delegated' and approval = 'approved'
      order by seq desc limit v_excess
    loop
      update session_dogs set approval = 'pending', booking_id = null where id = v_row.id;
      if v_row.booking_id is not null then
        perform _club_refund_bookings(array[v_row.booking_id], 'club_runner_withdrawn',
          '위탁 승인 대기로 변경', '러너 이탈로 위탁 정원이 줄었어요 — 승인 대기로 돌아가며 전액 환불 처리돼요');
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_host, 'community', '위탁 정원 초과', '러너 이탈로 승인된 위탁이 대기로 돌아갔어요 — 세션을 확인하세요', p_session);
    end loop;
  end if;

  return v_new_cap;
end $$;

-- ---------- 0037 갭 마감 ② — 취소: 주행 중 차단 + confirmed 부킹 2단 환불 ----------
create or replace function _club_refund_confirmed(p_session uuid, p_reason text) returns int
language plpgsql security definer set search_path = public as $$
declare v_row record; n int := 0;
begin
  for v_row in
    select id, owner_id from bookings
    where club_session_id = p_session and status = 'confirmed'
  loop
    -- 전이 맵: confirmed → refund_pending 직행 불가 — cancelled_runner(서비스 미제공) 경유 2단
    update bookings set status = 'cancelled_runner', cancel_reason = p_reason where id = v_row.id;
    update bookings set status = 'refund_pending' where id = v_row.id;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_row.owner_id, 'booking', '위탁 취소 — 전액 환불', '배정된 위탁 러닝이 진행되지 못했어요 — 전액 환불 처리돼요', v_row.id);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function club_cancel_session(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; n int; v_ok uuid;
begin
  -- 호스트·상태 검증 먼저 (행 락 — 검증 전에 세션 정보를 노출하지 않는다)
  select id into v_ok from club_sessions where id = p_session
    and host_profile_id = auth.uid() and status in ('open', 'full') for update;
  if v_ok is null then raise exception 'not_host_or_closed'; end if;
  -- [0038] 주행 중(인계 후) 세션은 취소 불가 — 강아지가 밖에 있다
  if exists (select 1 from bookings where club_session_id = p_session and status in ('picked_up', 'active')) then
    raise exception 'session_in_flight';
  end if;

  update club_sessions set status = 'cancelled' where id = p_session;

  select coalesce(array_agg(id), '{}') into v_ids
  from bookings where club_session_id = p_session and status = 'matching';
  n := _club_refund_bookings(v_ids, 'club_session_cancelled',
    '세션 취소 — 전액 환불', '클럽 세션이 취소됐어요 — 위탁 요금은 전액 환불 처리돼요');
  n := n + _club_refund_confirmed(p_session, 'club_session_cancelled');

  insert into notifications (profile_id, kind, title, body, ref_id)
  select profile_id, 'community', '클럽 세션 취소', '참여 예정이던 세션이 취소됐어요', p_session
  from session_people where session_id = p_session and profile_id <> auth.uid();
  return n;
end $$;

-- ---------- 0037 갭 마감 ③ — 종료 정리: confirmed(배정 후 미인계)도 환불 ----------
create or replace function club_finish_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_name text; v_teams int; v_dogs int; v_when timestamptz; v_ids uuid[];
begin
  update club_sessions set status = 'done'
  where id = p_session and host_profile_id = auth.uid() and status in ('open', 'full')
  returning club_id, scheduled_at into v_club, v_when;
  if v_club is null then raise exception 'not_host_or_closed'; end if;
  select name into v_name from clubs where id = v_club;
  select count(*) into v_teams from session_people where session_id = p_session and attendance = 'checked_in';
  select count(*) into v_dogs from session_dogs where session_id = p_session and checked_in_at is not null;
  -- 체크인 1팀 이상일 때만 리캡 포스트 (0031 본문 유지 — 0팀 자동 포스트는 부정직한 활동 연출)
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
  -- [0037] 인계까지 못 간 matching 위탁 = 러닝 없음 — 전액 환불
  select coalesce(array_agg(id), '{}') into v_ids
  from bookings where club_session_id = p_session and status = 'matching';
  perform _club_refund_bookings(v_ids, 'club_not_picked_up',
    '위탁 미진행 — 전액 환불', '세션이 끝났지만 위탁 러닝이 진행되지 않았어요 — 전액 환불 처리돼요');
  -- [0038] 배정 후 미인계(confirmed)도 동일 — 서비스 미제공 = 환불 (2단 전이)
  perform _club_refund_confirmed(p_session, 'club_not_picked_up');
end $$;

-- ---------- 권한 ----------
grant execute on function session_assign_dog(uuid, uuid) to authenticated;
grant execute on function club_start_delegated_runs(uuid) to authenticated;
grant execute on function club_save_run_trace(uuid, jsonb) to authenticated;
revoke execute on function _club_refund_confirmed(uuid, text) from public, anon, authenticated;
revoke execute on function _club_custody_transition() from public, anon, authenticated;
revoke execute on function _club_log_activity() from public, anon, authenticated;

comment on function session_assign_dog is 'P-C S2: 호스트 배정 (체크인 창·개인 캡 재검증·재배정은 인계 전만) (0038)';
comment on trigger club_custody_transition on bookings is 'P-C S2: picked_up=책임자→러너·체크인 / completed=체크아웃·책임자→보호자 (0038)';
comment on function club_save_run_trace is 'P-C S2: 공유 GPS 트레이스 → N runs 팬아웃 — 이벤트는 부킹별 유지 (0038)';
