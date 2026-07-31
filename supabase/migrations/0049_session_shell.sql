-- ═══ 0049: R5 — 세션 셸 백엔드: 그룹 채팅·능력 로스터·전화 규칙 B·크리티컬 ack (v3.3 §9) ═══
-- 프라이빗 채널(보호자↔담당 러너)은 기존 부킹 채팅(chat_threads, 0001/0008)이 그대로 담당 —
-- 클럽 부킹도 당사자 RLS로 이미 동작한다. 여기는 '세션' 층: 그룹 채팅 + 제한된 호스트 채널.
-- 접근 원칙 (§9): 신청만 한 사람은 그룹 채팅에 들어오지 못한다 — 신청은 사적 공간의 문이 아니다.

-- ---------- A. 셸 접근 등급 (단일 판정 함수 — RLS·로스터·채팅이 공유) ----------
-- 'host' = 호스트/백업 · 'full' = 참석자·커밋 러너·승인+ 위탁 보호자 · 'limited' = 신청 기록만
-- (pending/rejected/withdrawn/만료) · 'none' = 무관
create or replace function _club_shell_access(p_session uuid, p_profile uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from club_sessions s where s.id = p_session
                 and (s.host_profile_id = p_profile or s.backup_host_profile_id = p_profile)) then 'host'
    when exists (select 1 from session_people sp where sp.session_id = p_session
                 and sp.profile_id = p_profile and sp.attendance <> 'no_show') then 'full'
    when exists (select 1 from session_runner_assignments a where a.session_id = p_session
                 and a.runner_profile_id = p_profile and a.status = 'committed') then 'full'
    when exists (select 1 from session_dogs sd where sd.session_id = p_session
                 and sd.owner_profile_id = p_profile and sd.custody = 'runner_delegated'
                 and sd.approval = 'approved' and sd.service_state is distinct from 'ended') then 'full'
    when exists (select 1 from session_dogs sd where sd.session_id = p_session
                 and sd.owner_profile_id = p_profile and sd.custody = 'runner_delegated') then 'limited'
    else 'none'
  end;
$$;
revoke execute on function _club_shell_access(uuid, uuid) from public, anon, authenticated;

-- 쓰기 수명 (§9): 참여 시점부터 — 본인 관련 커스터디 전부 해소 + 24h까지 (인시던트는 연장)
create or replace function _club_chat_writable(p_session uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select _club_shell_access(p_session, p_profile) <> 'none'
     and exists (
       select 1 from club_sessions s where s.id = p_session
         and (s.status in ('open', 'full')
              or (s.status = 'done' and (
                    now() < s.scheduled_at + interval '24 hours'
                    or exists (select 1 from session_dogs sd where sd.session_id = p_session
                               and (sd.owner_profile_id = p_profile or sd.custodian_profile_id = p_profile)
                               and sd.custody = 'runner_delegated'
                               and sd.custody_phase not in ('resolved')
                               and sd.service_state is distinct from 'ended')
                    or exists (select 1 from club_incidents i where i.session_id = p_session
                               and i.state <> 'resolved')))));
$$;
revoke execute on function _club_chat_writable(uuid, uuid) from public, anon, authenticated;

-- RLS 정책은 '호출자' 권한으로 술어 함수를 실행한다 — 임의 인자 원함수 grant는 참여 프로빙
-- 통로가 되므로, auth.uid() 고정 래퍼만 authenticated에 연다 (앱 셸 판정에도 재사용).
create or replace function club_my_shell_access(p_session uuid) returns text
language sql stable security definer set search_path = public as $$
  select _club_shell_access(p_session, auth.uid());
$$;
create or replace function club_my_chat_writable(p_session uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select _club_chat_writable(p_session, auth.uid());
$$;
grant execute on function club_my_shell_access(uuid) to authenticated;
grant execute on function club_my_chat_writable(uuid) to authenticated;

-- ---------- B. 그룹 채팅 + 호스트 채널 (RLS 직접 접근 — 리얼타임 구독 경로) ----------
create table if not exists club_chat_messages (
  id bigint generated always as identity primary key,
  session_id uuid not null references club_sessions on delete cascade,
  sender_id uuid not null references profiles(id),
  audience text not null default 'group' check (audience in ('group', 'host_channel')),
  recipient_profile_id uuid references profiles(id),   -- host_channel: 신청자 (그룹은 null)
  kind text not null default 'text' check (kind in ('text', 'photo', 'system')),
  body text,
  media_path text,
  flagged boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists club_chat_session_idx on club_chat_messages (session_id, id);
alter table club_chat_messages enable row level security;

-- 읽기: 그룹 = full/host · 호스트 채널 = 호스트 + 그 신청자 본인
create policy "club chat read" on club_chat_messages for select using (
  case audience
    when 'group' then club_my_shell_access(session_id) in ('host', 'full')
    else club_my_shell_access(session_id) = 'host' or recipient_profile_id = auth.uid()
  end
);
-- 쓰기: 그룹 = full/host + 수명 안 · 호스트 채널 = limited 이상 본인(수신자=본인) 또는 호스트(수신자=신청자)
create policy "club chat send" on club_chat_messages for insert with check (
  sender_id = auth.uid()
  and club_my_chat_writable(session_id)
  and kind in ('text', 'photo')
  and case audience
    when 'group' then club_my_shell_access(session_id) in ('host', 'full')
                      and recipient_profile_id is null
    else (recipient_profile_id = auth.uid()
          and club_my_shell_access(session_id) in ('limited', 'full'))
         or (club_my_shell_access(session_id) = 'host' and recipient_profile_id is not null)
  end
);
-- 수정·삭제 직접 불가 — delete-own 5분·신고는 definer RPC만 (아래)

-- 레이트 리밋 (파일럿): 세션당 분당 20건 — 트리거가 정책보다 정직하다 (RLS로는 횟수 못 센다)
create or replace function _club_chat_rate_tg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from club_chat_messages
      where session_id = new.session_id and sender_id = new.sender_id
        and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'rate_limited';
  end if;
  return new;
end $$;
drop trigger if exists club_chat_rate on club_chat_messages;
create trigger club_chat_rate before insert on club_chat_messages
  for each row execute function _club_chat_rate_tg();

-- delete-own 5분 (파일럿 모더레이션)
create or replace function club_chat_delete(p_message bigint) returns void
language plpgsql security definer set search_path = public as $$
declare m record;
begin
  select * into m from club_chat_messages where id = p_message;
  if m.id is null then raise exception 'not_found'; end if;
  if m.sender_id <> auth.uid() then raise exception 'not_yours'; end if;
  if m.created_at < now() - interval '5 minutes' then raise exception 'too_late'; end if;
  update club_chat_messages set deleted_at = now(), body = null, media_path = null
  where id = p_message;
end $$;

-- 신고 → 플래그 + 호스트 알림 (운영 채널은 R6)
create or replace function club_chat_report(p_message bigint, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare m record; v_host uuid;
begin
  select * into m from club_chat_messages where id = p_message;
  if m.id is null then raise exception 'not_found'; end if;
  if _club_shell_access(m.session_id, auth.uid()) = 'none' then raise exception 'not_party'; end if;
  update club_chat_messages set flagged = true where id = p_message;
  select host_profile_id into v_host from club_sessions where id = m.session_id;
  insert into notifications (profile_id, kind, title, body, ref_id)
  select v_host, 'safety', '채팅 신고 접수',
         coalesce('사유: ' || nullif(trim(p_reason), ''), '메시지가 신고됐어요') || ' — 확인 후 조치하세요', m.session_id
  where not exists (select 1 from notifications where profile_id = v_host
                    and title = '채팅 신고 접수' and ref_id = m.session_id
                    and created_at > now() - interval '10 minutes');
end $$;

grant execute on function club_chat_delete(bigint) to authenticated;
grant execute on function club_chat_report(bigint, text) to authenticated;

-- 리얼타임 (0008 선례 — 로컬/샌드박스에서 publication 부재 시 무해 통과)
do $$ begin
  alter publication supabase_realtime add table club_chat_messages;
exception when others then
  raise notice 'realtime publication skip: %', sqlerrm;
end $$;

-- ---------- C. 능력 로스터 + 전화 규칙 B + 접근 로그 (§9) ----------
create table if not exists club_phone_access_log (
  id bigint generated always as identity primary key,
  session_id uuid not null references club_sessions on delete cascade,
  viewer_profile_id uuid not null references profiles(id),
  target_profile_id uuid not null references profiles(id),
  accessed_at timestamptz not null default now()
);
alter table club_phone_access_log enable row level security;   -- 정책 없음

-- 전화 규칙 B: 호스트↔전원 · 보호자↔(자기 개의) 수락 러너 · 그 외 = 호스트 경유(비공개).
-- 수명 스코프: 세션 진행 중(open/full) 또는 본인 관련 커스터디 미해소 동안만.
create or replace function _club_phone_visible(
  p_session uuid, p_viewer uuid, p_target uuid
) returns boolean
language sql stable security definer set search_path = public as $$
  select
    -- 수명 게이트
    (exists (select 1 from club_sessions s where s.id = p_session and s.status in ('open', 'full'))
     or exists (select 1 from session_dogs sd where sd.session_id = p_session
                and sd.custody = 'runner_delegated' and sd.custody_phase <> 'resolved'
                and sd.service_state is distinct from 'ended'
                and (sd.owner_profile_id in (p_viewer, p_target)
                     or sd.custodian_profile_id in (p_viewer, p_target))))
    and (
      -- 호스트 ↔ 전원 (양방향)
      exists (select 1 from club_sessions s where s.id = p_session
              and (s.host_profile_id = p_viewer or s.backup_host_profile_id = p_viewer))
      or exists (select 1 from club_sessions s where s.id = p_session
                 and (s.host_profile_id = p_target or s.backup_host_profile_id = p_target))
      -- 보호자 ↔ 수락 러너 (자기 개 한정, 양방향)
      or exists (select 1 from session_dogs sd join bookings b on b.id = sd.booking_id
                 where sd.session_id = p_session and sd.custody = 'runner_delegated'
                   and b.runner_id is not null
                   and ((sd.owner_profile_id = p_viewer and b.runner_id = p_target)
                     or (sd.owner_profile_id = p_target and b.runner_id = p_viewer)))
    );
$$;
revoke execute on function _club_phone_visible(uuid, uuid, uuid) from public, anon, authenticated;

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

-- ---------- D. 크리티컬 알림 ack (§9) — 푸시 + 지속 배너, 미확인 시 에스컬레이션 ----------
create table if not exists club_critical_titles (title text primary key);
insert into club_critical_titles (title) values
  ('담당 러너 배정'), ('외부 커스터디 이양'), ('배정 불발 — 전액 환불'),
  ('세션 취소'), ('반환 지연 경보'), ('이의 접수 — 전액 환불'), ('재검토 거절 — 전액 환불')
on conflict do nothing;

create table if not exists club_acks (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  notification_id uuid,
  title text not null,
  body text,
  ref_id uuid,
  created_at timestamptz not null default now(),
  acked_at timestamptz,
  escalated_at timestamptz
);
create index if not exists club_acks_pending_idx on club_acks (profile_id) where acked_at is null;
alter table club_acks enable row level security;
create policy "own acks read" on club_acks for select using (profile_id = auth.uid());

-- 데이터 주도 배선: 크리티컬 제목의 알림이 삽입되면 ack 행 자동 생성 — RPC 6곳 재정의 대신
-- 등록부 1곳 (제목 레지스트리). 새 크리티컬 = 제목 한 줄 추가.
create or replace function _club_ack_tg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from club_critical_titles t where t.title = new.title) then
    insert into club_acks (profile_id, notification_id, title, body, ref_id)
    values (new.profile_id, new.id, new.title, new.body, new.ref_id);
  end if;
  return new;
end $$;
drop trigger if exists club_ack_fanout on notifications;
create trigger club_ack_fanout after insert on notifications
  for each row execute function _club_ack_tg();

create or replace function club_ack(p_ack uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update club_acks set acked_at = now() where id = p_ack and profile_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
end $$;
create or replace function club_my_acks() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'title', title, 'body', body, 'refId', ref_id, 'createdAt', created_at)
    order by created_at desc), '[]'::jsonb)
  from club_acks where profile_id = auth.uid() and acked_at is null;
$$;
grant execute on function club_ack(uuid) to authenticated;
grant execute on function club_my_acks() to authenticated;

-- ---------- E. 회복 크론 v2 — 반환 지연 경보 + ack 에스컬레이션 결합 (최신 정의 = 0047) ----------
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
  -- ④ [R5] 반환 지연 경보: 예정 +6h 지나도 return_pending → 양측 크리티컬 (ack 트리거가 배너化)
  for r in
    select sd.id, sd.owner_profile_id, sd.session_id, b.runner_id,
           (select name from dogs where id = sd.dog_id) as dog_name
    from session_dogs sd
    join club_sessions s on s.id = sd.session_id
    left join bookings b on b.id = sd.booking_id
    where sd.custody = 'runner_delegated' and sd.custody_phase = 'return_pending'
      and s.scheduled_at < now() - interval '6 hours'
  loop
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.owner_profile_id, 'safety', '반환 지연 경보',
           r.dog_name || ' 반환이 아직 확인되지 않았어요 — 즉시 확인하세요', r.session_id
    where not exists (select 1 from notifications where profile_id = r.owner_profile_id
                      and ref_id = r.session_id and title = '반환 지연 경보');
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.runner_id, 'safety', '반환 지연 경보',
           r.dog_name || ' 반환 확인이 지연되고 있어요 — 지금 반환을 완료하세요', r.session_id
    where r.runner_id is not null
      and not exists (select 1 from notifications where profile_id = r.runner_id
                      and ref_id = r.session_id and title = '반환 지연 경보');
  end loop;

  -- ⑤ [R5] ack 에스컬레이션: 30분 미확인 크리티컬 → 세션 호스트에게 1회 (§9 unacked → escalate)
  for r in
    select a.id as ack_id, a.profile_id, a.title,
           coalesce(cs.id, (select b.club_session_id from bookings b where b.id = a.ref_id)) as sess
    from club_acks a
    left join club_sessions cs on cs.id = a.ref_id
    where a.acked_at is null and a.escalated_at is null
      and a.created_at < now() - interval '30 minutes'
  loop
    update club_acks set escalated_at = now() where id = r.ack_id;
    if r.sess is not null then
      insert into notifications (profile_id, kind, title, body, ref_id)
      select s.host_profile_id, 'safety', '미확인 크리티컬 알림',
             '참가자가 중요 알림(' || r.title || ')을 30분째 확인하지 않았어요 — 직접 연락이 필요할 수 있어요', r.sess
      from club_sessions s
      where s.id = r.sess and s.host_profile_id <> r.profile_id
        and not exists (select 1 from notifications where profile_id = s.host_profile_id
                        and ref_id = r.sess and title = '미확인 크리티컬 알림'
                        and created_at > now() - interval '30 minutes');
    end if;
  end loop;
  return n;
end $$;

comment on table club_chat_messages is
  'R5(0049): 세션 그룹 채팅 + 호스트 채널 — 접근은 _club_shell_access (신청자는 그룹 밖), 쓰기 수명 §9';
comment on function club_session_roster is
  'R5(0049): 능력 로스터 — 전화 규칙 B(호스트↔전원·보호자↔수락 러너·그 외 호스트 경유)·수명 스코프·접근 로그';
comment on table club_acks is
  'R5(0049): 크리티컬 알림 ack — 제목 레지스트리(club_critical_titles) 데이터 주도 배선, 30분 미확인 → 호스트 에스컬레이션';
