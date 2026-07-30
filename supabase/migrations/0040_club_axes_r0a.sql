-- ═══ 0040: R0A — 직교 축 스키마 (club-run-logic.md v3.3 §2·§14) ═══
-- 순수 스키마 슬라이스: 컬럼·테이블·백필·동기화 트리거·프로젝션·플래그·드리프트 검사.
-- **행동 변화 없음** — v1 RPC(0037~0039)는 그대로 동작하고, 축은 v1 진실에서 파생돼
-- 트리거로 상시 동기화된다(dual-write). R1부터 축이 1차 진실이 되고 v1 로직이 교체된다.
--
-- 매핑 각서 (v1 → 축, 드리프트 검사의 기준):
-- - custody 컬럼(owner_handled/runner_delegated) ≡ participation_mode — 개명은 정리 슬라이스에서.
-- - v1 승인 = 즉시 결제(모의)였으므로: approved+부킹 존재 → charge=paid·hold=consumed.
--   (승인=홀드 분리는 R1 — 그 전까지 hold 시스템은 휴면)
-- - v1 정산 = 즉시 지급이므로: completed+원장 존재 → payout=released. (payable/보류는 R2)
-- - 반환 확인은 v1에 없음 → checked_out = custodian owner (양측 반환 확인은 R2)
-- - assignment_events는 v1 배정(session_assign_dog)에서 이벤트를 남기지 않았으므로 백필 없이
--   현재 상태만 캐시에 반영, R3부터 이벤트가 1차 진실.

-- ---------- 세션 강아지: 축 컬럼 (전부 nullable/default — v1 무영향) ----------
alter table session_dogs
  add column if not exists service_state text
    check (service_state in ('requested','approved','confirmed','in_service','ended')),
  add column if not exists completion_outcome text
    check (completion_outcome in ('completed','partial','no_service')),
  add column if not exists termination_type text
    check (termination_type in ('normal','early_return','cancelled','vet_transfer','session_aborted')),
  add column if not exists service_reason text,
  add column if not exists cancelled_by text
    check (cancelled_by in ('owner','host','runner','system','ops')),
  add column if not exists charge_state text not null default 'none'
    check (charge_state in ('none','hold','paid')),
  add column if not exists hold_status text not null default 'none'
    check (hold_status in ('none','active','consumed','released','expired')),
  add column if not exists hold_expires_at timestamptz,
  add column if not exists refund_state text not null default 'none'
    check (refund_state in ('none','pending','refunded','failed')),
  add column if not exists payout_state text not null default 'none'
    check (payout_state in ('none','earned','payable','released','void')),
  add column if not exists payout_hold text not null default 'none'
    check (payout_hold in ('none','held')),
  add column if not exists payout_hold_reason text,
  add column if not exists payout_hold_incident uuid,
  add column if not exists assignment_state text not null default 'unassigned'
    check (assignment_state in ('unassigned','proposed','accepted','declined','replacement_needed')),
  add column if not exists current_runner_profile_id uuid references profiles(id),
  add column if not exists proposal_expires_at timestamptz,
  add column if not exists custodian_type text
    check (custodian_type in ('owner','runner','host','clinic','authority','authorized_person')),
  add column if not exists custodian_profile_id uuid references profiles(id),
  add column if not exists custodian_external text,
  add column if not exists custody_phase text not null default 'with_custodian'
    check (custody_phase in ('with_custodian','outbound_pending','transfer_pending','return_pending')),
  add column if not exists previous_attempt_id uuid references session_dogs(id);

-- ---------- 이력 테이블 (RLS 전면 차단 — 접근은 definer RPC/프로젝션으로만) ----------
create table if not exists assignment_events (
  id uuid primary key default gen_random_uuid(),
  session_dog_id uuid not null references session_dogs on delete cascade,
  runner_profile_id uuid references profiles(id),
  event text not null check (event in ('proposed','accepted','declined','revoked','expired','replaced')),
  reason text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists assignment_events_sd_idx on assignment_events (session_dog_id, created_at);

create table if not exists dog_custody_events (
  id uuid primary key default gen_random_uuid(),
  session_dog_id uuid not null references session_dogs on delete cascade,
  from_type text check (from_type in ('owner','runner','host','clinic','authority','authorized_person')),
  from_profile_id uuid references profiles(id),
  from_external text,
  to_type text not null check (to_type in ('owner','runner','host','clinic','authority','authorized_person')),
  to_profile_id uuid references profiles(id),
  to_external text,
  event_type text not null check (event_type in
    ('outbound','return','emergency_transfer','vet_transfer','authority_transfer','sync_v1')),
  confirmation_kind text not null default 'app_user' check (confirmation_kind in
    ('app_user','authorized_person_pin','host_witnessed_receipt','clinic_receipt','ops_attestation','sync_v1')),
  initiated_by uuid references profiles(id),
  occurred_at timestamptz not null default now(),
  location jsonb,
  reason text,
  incident_id uuid
);
create index if not exists dog_custody_events_sd_idx on dog_custody_events (session_dog_id, occurred_at);

-- ⚠ `incidents`는 0001이 부킹 단위 신고 테이블로 선점 — 클럽 인시던트는 club_ 접두
create table if not exists club_incidents (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references club_sessions on delete cascade,
  severity text not null check (severity in ('S1','S2','S3')),
  state text not null default 'open' check (state in ('open','investigating','resolved')),
  opened_by uuid references profiles(id),
  case_owner uuid references profiles(id),
  summary text not null,
  opened_at timestamptz not null default now(),
  resolved_at timestamptz
);
create table if not exists club_incident_subjects (
  incident_id uuid not null references club_incidents on delete cascade,
  subject_type text not null check (subject_type in ('dog','person','session','booking')),
  subject_id uuid,
  note text
);
create table if not exists club_incident_evidence (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references club_incidents on delete cascade,
  kind text not null check (kind in ('photo','text','location','document')),
  payload jsonb not null,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists payment_attempts (
  id uuid primary key default gen_random_uuid(),
  session_dog_id uuid references session_dogs on delete cascade,
  booking_id uuid references bookings,
  kind text not null check (kind in ('charge','refund')),
  idempotency_key text unique,
  result text not null check (result in ('ok','failed','duplicate')),
  detail text,
  created_at timestamptz not null default now()
);

create table if not exists dog_run_segments (
  id uuid primary key default gen_random_uuid(),
  session_dog_id uuid not null references session_dogs on delete cascade,
  run_id uuid references runs,
  runner_profile_id uuid not null references profiles(id),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  transfer_event_id uuid references dog_custody_events
);

create table if not exists delegation_consents (
  id uuid primary key default gen_random_uuid(),
  session_dog_id uuid not null references session_dogs on delete cascade,
  owner_profile_id uuid not null references profiles(id),
  dog_id uuid not null references dogs,
  doc_id text not null,
  doc_version text not null,
  vet_limit_krw int,
  photo_consent boolean not null default false,
  custody_ack boolean not null default false,
  pickup_name text, pickup_contact text,
  emergency_contact text,
  accepted_at timestamptz not null default now(),
  meta jsonb not null default '{}'
);

alter table assignment_events enable row level security;
alter table dog_custody_events enable row level security;
alter table club_incidents enable row level security;
alter table club_incident_subjects enable row level security;
alter table club_incident_evidence enable row level security;
alter table payment_attempts enable row level security;
alter table dog_run_segments enable row level security;
alter table delegation_consents enable row level security;
-- 정책 없음 = 직접 접근 전면 차단 (definer RPC·프로젝션 경유만)

-- ---------- 피처 플래그 ----------
create table if not exists club_flags (name text primary key, enabled boolean not null default false);
insert into club_flags (name, enabled) values ('club_delegation_v2', false)
on conflict (name) do nothing;
alter table club_flags enable row level security;
create or replace function club_flag(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select enabled from club_flags where name = p_name), false);
$$;
revoke execute on function club_flag(text) from public, anon, authenticated;

-- ---------- 축 계산 (v1 진실 → 축) — 동기화 트리거와 드리프트 검사가 공유하는 단일 소스 ----------
create or replace function _club_compute_axes(sd session_dogs) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bst text; v_brunner uuid; v_bcancel text; v_run_reason text;   -- 스칼라 = null 안전 (record는 미할당 참조 에러)
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
      'charge_state', 'none', 'hold_status', 'none', 'refund_state', 'none',
      'payout_state', 'none', 'payout_hold', 'none',
      'assignment_state', 'unassigned', 'current_runner_profile_id', null,
      'custodian_type', 'owner', 'custodian_profile_id', sd.owner_profile_id,
      'custody_phase', 'with_custodian');
  end if;

  -- 위탁견 — 서비스 축
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
    else -- refund_pending / cancelled_runner / expired / 기타 종결
      j := j || jsonb_build_object('service_state','ended','completion_outcome','no_service',
        'termination_type','cancelled',
        'service_reason', case v_bcancel
          when 'club_session_cancelled' then 'session_cancelled'
          when 'club_runner_withdrawn' then 'runner_capacity'
          when 'club_not_picked_up' then 'no_show_owner' else 'other' end,
        'cancelled_by', 'system');
    end if;
  end if;

  -- 돈 축 (v1: 승인=모의 결제, 정산=즉시 지급)
  if sd.booking_id is null then
    j := j || jsonb_build_object('charge_state','none','hold_status','none','refund_state','none',
      'payout_state','none','payout_hold','none');
  else
    j := j || jsonb_build_object('charge_state','paid','hold_status','consumed');
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
    j := j || jsonb_build_object('payout_hold','none');
  end if;

  -- 배정 캐시 (이벤트는 R3부터 — v1은 현재값만)
  if v_brunner is not null and v_bst in ('confirmed','picked_up','active','completed') then
    j := j || jsonb_build_object('assignment_state','accepted','current_runner_profile_id', v_brunner);
  else
    j := j || jsonb_build_object('assignment_state','unassigned','current_runner_profile_id', null);
  end if;

  -- 커스터디 프로젝션 (v1: responsible 컬럼이 진실)
  if sd.responsible_profile_id = sd.owner_profile_id then
    j := j || jsonb_build_object('custodian_type','owner','custodian_profile_id', sd.owner_profile_id);
  else
    j := j || jsonb_build_object('custodian_type','runner','custodian_profile_id', sd.responsible_profile_id);
  end if;
  j := j || jsonb_build_object('custody_phase','with_custodian');  -- pending 상태는 R2부터
  return j;
end $$;

-- 동기화: BEFORE 트리거 — NEW에 축을 채운다 (재귀 없음, v1 쓰기 경로 전부 커버)
create or replace function _club_sync_axes_tg() returns trigger
language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  j := _club_compute_axes(new);
  new.service_state := j->>'service_state';
  new.completion_outcome := j->>'completion_outcome';
  new.termination_type := j->>'termination_type';
  new.service_reason := coalesce(j->>'service_reason', new.service_reason);
  new.cancelled_by := j->>'cancelled_by';
  new.charge_state := j->>'charge_state';
  new.hold_status := j->>'hold_status';
  new.refund_state := j->>'refund_state';
  new.payout_state := j->>'payout_state';
  new.payout_hold := j->>'payout_hold';
  new.assignment_state := j->>'assignment_state';
  new.current_runner_profile_id := (j->>'current_runner_profile_id')::uuid;
  new.custodian_type := j->>'custodian_type';
  new.custodian_profile_id := (j->>'custodian_profile_id')::uuid;
  new.custody_phase := j->>'custody_phase';
  return new;
end $$;
drop trigger if exists club_v1_axes_sync on session_dogs;
create trigger club_v1_axes_sync before insert or update on session_dogs
  for each row execute function _club_sync_axes_tg();

-- 커스터디 이벤트 기록: responsible 변경 시 (v1 시대의 이력 — R2가 이벤트를 1차 진실로 승격)
create or replace function _club_v1_custody_event_tg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.responsible_profile_id is distinct from new.responsible_profile_id then
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type, confirmation_kind)
    values (new.id,
      case when old.responsible_profile_id = new.owner_profile_id then 'owner' else 'runner' end,
      old.responsible_profile_id,
      case when new.responsible_profile_id = new.owner_profile_id then 'owner' else 'runner' end,
      new.responsible_profile_id,
      case when new.responsible_profile_id = new.owner_profile_id then 'return' else 'outbound' end,
      'sync_v1');
  end if;
  return new;
end $$;
drop trigger if exists club_v1_custody_event on session_dogs;
create trigger club_v1_custody_event after update on session_dogs
  for each row execute function _club_v1_custody_event_tg();

-- 부킹 변경 → 해당 강아지 행 재동기화 (0038 커스터디 트리거보다 알파벳 순서상 뒤에 발화)
create or replace function _club_v2_axes_poke_tg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.club_session_id is not null then
    update session_dogs set id = id where booking_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists club_v2_axes_poke on bookings;
create trigger club_v2_axes_poke after update of status on bookings
  for each row when (new.club_session_id is not null) execute function _club_v2_axes_poke_tg();

-- 정산 트랜잭션 순서(클레임→runs→원장) 때문에 상태 클레임 시점의 poke는 미완 데이터를 본다
-- → 원장 insert(정산의 마지막 쓰기)에서 한 번 더 재동기화
create or replace function _club_v2_ledger_poke_tg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update session_dogs set id = id
  where booking_id = new.booking_id
    and exists (select 1 from bookings b where b.id = new.booking_id and b.club_session_id is not null);
  return new;
end $$;
drop trigger if exists club_v2_ledger_poke on ledger_items;
create trigger club_v2_ledger_poke after insert on ledger_items
  for each row execute function _club_v2_ledger_poke_tg();

-- ---------- 백필 (기존 행 전부 — no-op 업데이트가 BEFORE 트리거를 통과시킴) ----------
update session_dogs set id = id;

-- ---------- 드리프트 검사 — 저장값 vs 재계산 비교 (하네스 케이스 + 크론, 로그만) ----------
create or replace function club_drift_check() returns table (session_dog_id uuid, field text, stored text, expected text)
language plpgsql stable security definer set search_path = public as $$
declare sd session_dogs; j jsonb; f text; sv text; ev text;
begin
  for sd in select * from session_dogs loop
    j := _club_compute_axes(sd);
    foreach f in array array['service_state','completion_outcome','termination_type','cancelled_by',
      'charge_state','hold_status','refund_state','payout_state','payout_hold',
      'assignment_state','custodian_type','custody_phase'] loop
      ev := j->>f;
      sv := case f
        when 'service_state' then sd.service_state when 'completion_outcome' then sd.completion_outcome
        when 'termination_type' then sd.termination_type when 'cancelled_by' then sd.cancelled_by
        when 'charge_state' then sd.charge_state when 'hold_status' then sd.hold_status
        when 'refund_state' then sd.refund_state when 'payout_state' then sd.payout_state
        when 'payout_hold' then sd.payout_hold when 'assignment_state' then sd.assignment_state
        when 'custodian_type' then sd.custodian_type when 'custody_phase' then sd.custody_phase end;
      if sv is distinct from ev then
        session_dog_id := sd.id; field := f; stored := sv; expected := ev;
        return next;
      end if;
    end loop;
  end loop;
end $$;
revoke execute on function club_drift_check() from public, anon, authenticated;

-- ---------- 구조화 UI 프로젝션 (v3.3 §10) — 라벨 한국어 1급·플랩은 클라 플레이버 ----------
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
      when sd.service_state = 'ended' and sd.completion_outcome in ('completed','partial') then '완료'
      when sd.service_state = 'ended' then '종료'
      else '확인 중' end;
    if sd.refund_state = 'pending' then v_badges := v_badges || '"환불 처리 중"'::jsonb; end if;
    if sd.refund_state = 'failed' then v_badges := v_badges || '"환불 실패"'::jsonb; v_sev := 'critical'; end if;
    if sd.hold_status = 'expired' then v_badges := v_badges || '"결제 기한 만료"'::jsonb; end if;
    if sd.payout_hold = 'held' then v_badges := v_badges || '"정산 보류"'::jsonb; end if;
    if sd.assignment_state = 'replacement_needed' then v_badges := v_badges || '"자리 재확인 중"'::jsonb; v_sev := 'warn'; end if;
    if exists (select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
               where s.subject_type = 'dog' and s.subject_id = sd.dog_id and i.state <> 'resolved') then
      v_badges := v_badges || '"인시던트 확인 중"'::jsonb; v_sev := 'critical';
    end if;
    if sd.service_state = 'approved' and sd.charge_state <> 'paid' then
      v_actors := '["owner"]'; v_block := '["결제"]';
    elsif sd.assignment_state = 'proposed' then v_actors := '["runner"]'; v_block := '["러너 수락"]';
    elsif sd.service_state = 'confirmed' and sd.assignment_state = 'accepted' then
      v_actors := '["owner","runner"]'; v_block := '["인계 확인"]';
    end if;
  end if;
  return jsonb_build_object(
    'primaryStage', v_stage, 'secondaryBadges', v_badges,
    'blockingIssues', v_block, 'primaryIssue', v_block->0,
    'requiredActors', v_actors, 'severity', v_sev,
    'allowedActions', '[]'::jsonb  -- 역할×단계 매트릭스 액션은 R1+에서 뷰어 기준으로 채움
  );
end $$;
grant execute on function club_dog_ui_state(uuid) to authenticated;

comment on function _club_compute_axes is 'R0A: v1 진실→축 매핑 단일 소스 (동기화 트리거·드리프트 검사 공유)';
comment on function club_drift_check is 'R0A: 축 드리프트 정합 검사 — 하네스 케이스 + 크론(로그만)';
comment on function club_dog_ui_state is 'R0A: 구조화 UI 프로젝션 (stage/badges/actors/severity) — v3.3 §10';
