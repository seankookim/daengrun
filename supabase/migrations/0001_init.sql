-- 댕런 core schema v1 — every table traces to a mocked screen (docs/feature-audit.md).
-- Booking state machine per docs/calendar.md.

create extension if not exists "pgcrypto";

-- ---------- enums ----------
create type user_role as enum ('owner', 'runner');

create type booking_status as enum (
  'draft', 'quoted', 'payment_hold', 'matching', 'runner_pending',
  'confirmed', 'runner_enroute', 'picked_up', 'active', 'completed',
  'cancelled_owner', 'cancelled_runner', 'expired', 'no_show',
  'incident_review', 'refund_pending'
);

create type runner_tier as enum ('applicant', 'certified', 'veteran', 'master'); -- 인증 러너/베테랑/마스터
create type funnel_step as enum ('info', 'kyc', 'education', 'trial', 'certified');
create type end_reason as enum ('completed', 'dog_condition', 'owner_request', 'runner_personal', 'owner_forced', 'incident');
create type review_visibility as enum ('public', 'platform_only');
create type drop_type as enum ('mini', 'pick'); -- 보급 드랍 / 픽 드랍
create type claim_status as enum ('locked', 'claimable', 'claimed', 'shipped');
create type payout_status as enum ('pending', 'processing', 'paid', 'failed');
create type noti_kind as enum ('booking', 'community', 'shop', 'safety', 'reward', 'system');

-- ---------- identity ----------
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  role user_role not null default 'owner',
  name text not null,
  phone text,                       -- PASS 본인인증 후 확정
  avatar_url text,
  district text,                    -- 활동/거주 동네 (성수동)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table dogs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles on delete cascade,
  name text not null,
  breed text,
  birth_date date,
  weight_kg numeric(4,1),
  neutered boolean,
  memo text,                        -- 러너에게 전달되는 성향 메모
  vaccinations jsonb not null default '[]',   -- [{type, at}]
  preferences jsonb not null default '{}',    -- 흙길 선호, 페이스, 시간대, 코스
  weekly_goal_km numeric(4,1) not null default 15,  -- 수의 검증 공식으로 대체 예정
  fitness_age numeric(3,1),         -- 체력 나이 (secondary metric)
  cumulative_km numeric(7,2) not null default 0,
  streak_days int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- runner supply (mock: /runner/apply) ----------
create table runners (
  profile_id uuid primary key references profiles on delete cascade,
  tier runner_tier not null default 'applicant',
  funnel_step funnel_step not null default 'info',
  bio text,                         -- 스토어프런트 소개
  specialties text[] not null default '{}',   -- 대형견, 새벽러닝, 행동교정...
  avg_pace_sec_per_km int,          -- 410 = 6'50"
  service_radius_km numeric(3,1) not null default 3,
  max_dog_weight_kg numeric(4,1),
  identity_verified boolean not null default false,
  insurance_active boolean not null default false,
  trainer_certified boolean not null default false,
  education_modules_done int not null default 0,   -- /6
  total_runs int not null default 0,
  total_km numeric(8,2) not null default 0,
  completion_rate numeric(4,3),     -- 러너 개인 사유 종료만 반영 (dog_condition 무영향)
  compliance_pct int,               -- 신호 준수율
  respond_rate_pct int,
  commission_rate numeric(4,3) not null default 0.20,  -- tier에 따라 0.18/0.15
  online boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table runner_documents (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners on delete cascade,
  kind text not null,               -- id_card | criminal_record | trainer_cert
  storage_path text not null,       -- 인증 후 원본 파기 정책
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table runner_availability_rules (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners on delete cascade,
  weekday int not null check (weekday between 0 and 6),
  start_min int not null,           -- minutes from midnight, Asia/Seoul rule attached
  end_min int not null,
  check (end_min > start_min)
);

create table runner_availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  kind text not null default 'blocked',  -- vacation | personal | extended
  note text
);

create table runner_booking_rules (
  runner_id uuid primary key references runners on delete cascade,
  min_notice_min int not null default 120,
  max_sessions_per_day int not null default 4,
  rest_after_min int not null default 30,
  group_capacity int not null default 2
);

-- ---------- addresses (mock: /owner/addresses) ----------
create table addresses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles on delete cascade,
  label text not null,
  addr text not null,
  detail text,
  gate_code_enc text,               -- pgsodium/KMS 암호화; 세션 중에만 러너에게 복호 노출
  lat numeric(9,6),
  lng numeric(9,6),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create table gate_code_access_log (   -- 열람 기록은 안심 센터에서 확인
  id bigint generated always as identity primary key,
  address_id uuid not null references addresses on delete cascade,
  runner_id uuid not null references runners,
  booking_id uuid,                  -- fk added after bookings
  accessed_at timestamptz not null default now()
);

-- ---------- certified routes (mock: 안심 코스 carousel) ----------
create table routes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  area text not null,
  km numeric(4,1) not null,
  terrain text,
  features jsonb not null default '[]',   -- [{g,label}]
  tags text[] not null default '{}',
  trace jsonb not null default '[]',      -- [{x,y}] normalized; 실좌표는 후속
  checked_at date,                        -- 안전 점검일 — 만료 관리 대상
  checked_by uuid references profiles,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- bookings + state machine ----------
create table recurring_series (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles,
  rule jsonb not null,              -- {weekdays:[..], time, tz:'Asia/Seoul', skip_holidays}
  same_runner_pref boolean not null default true,
  paused boolean not null default false,
  created_at timestamptz not null default now()
);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles,
  dog_id uuid not null references dogs,
  runner_id uuid references runners,          -- matching 전 null
  route_id uuid references routes,
  address_id uuid references addresses,
  series_id uuid references recurring_series,
  status booking_status not null default 'draft',
  scheduled_at timestamptz not null,
  km numeric(4,1) not null,
  pace_label text,
  addons jsonb not null default '[]',         -- [{key,label,price}]
  base_fare int not null,
  distance_fare int not null,
  addon_fare int not null default 0,
  total_price int not null,
  min_fare int not null default 9900,         -- 조기 종료 최소 요금
  owner_confirmed_handoff_at timestamptz,     -- 양측 인계 확인 (보험 기점)
  runner_confirmed_handoff_at timestamptz,
  cancel_reason text,
  cancel_fee int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table gate_code_access_log
  add constraint gate_log_booking_fk foreign key (booking_id) references bookings;

-- 서버가 유일한 상태 전이자: 허용 전이만 통과
create or replace function enforce_booking_transition() returns trigger
language plpgsql as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'draft'          then new.status in ('quoted','expired')
    when 'quoted'         then new.status in ('payment_hold','expired')
    when 'payment_hold'   then new.status in ('matching','expired','refund_pending')
    when 'matching'       then new.status in ('runner_pending','expired','refund_pending')
    when 'runner_pending' then new.status in ('confirmed','matching','expired','cancelled_owner')
    when 'confirmed'      then new.status in ('runner_enroute','cancelled_owner','cancelled_runner','no_show')
    when 'runner_enroute' then new.status in ('picked_up','no_show','cancelled_runner','incident_review')
    when 'picked_up'      then new.status in ('active','incident_review')
    when 'active'         then new.status in ('completed','incident_review')
    when 'completed'      then new.status in ('incident_review')
    else new.status in ('refund_pending')  -- terminal-ish states can flow to refund
  end;
  if not ok then
    raise exception 'invalid booking transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;

create trigger booking_transition before update of status on bookings
  for each row execute function enforce_booking_transition();

-- 더블부킹 방지: 결제 중 슬롯 임시 홀드 (~5분)
create table slot_holds (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid references runners,          -- null = 자동매칭 풀 홀드
  owner_id uuid not null references profiles,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  expires_at timestamptz not null,            -- now() + interval '5 min'
  booking_id uuid references bookings,
  created_at timestamptz not null default now()
);

-- ---------- runs (실측) ----------
create table runs (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings unique,
  started_at timestamptz,
  ended_at timestamptz,
  actual_km numeric(5,2),
  duration_sec int,
  avg_pace_sec_per_km int,
  end_reason end_reason,
  trace jsonb not null default '[]',          -- [{lat,lng,t,v}]
  condition_note text,                        -- 컨디션 종료 시 필수
  photos text[] not null default '{}'
);

-- ---------- two-sided reviews (mock: /runner/review) ----------
create table reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings,
  author_id uuid not null references profiles,
  target_kind text not null check (target_kind in ('runner','owner','dog')),
  target_id uuid not null,                    -- runner profile_id | owner profile_id | dog id
  rating int check (rating between 1 and 5),
  tags text[] not null default '{}',
  note text,
  visibility review_visibility not null default 'public',  -- 미고지 문제 = platform_only
  created_at timestamptz not null default now(),
  unique (booking_id, author_id, target_kind)
);

-- ---------- money (mock: /runner/earnings) ----------
create table ledger_items (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners,
  booking_id uuid not null references bookings,
  base int not null default 0,
  distance_pay int not null default 0,
  addon_pay int not null default 0,
  tip int not null default 0,
  remaining_guarantee int not null default 0, -- 보호자 요청 종료 시 잔여 50%
  platform_fee int not null default 0,
  created_at timestamptz not null default now()
);

create table bank_accounts (
  runner_id uuid primary key references runners,
  bank text not null,
  account_enc text not null,                  -- 암호화
  holder text not null,
  verified_at timestamptz
);

create table payouts (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners,
  period_start date not null,
  period_end date not null,
  gross int not null,
  tax_withheld int not null,                  -- 3.3%
  net int not null,
  status payout_status not null default 'pending',
  instant boolean not null default false,     -- 빠른 정산 (수수료 500)
  paid_at timestamptz
);

-- ---------- rewards (mock: /runner/rewards, home beacon) ----------
create table miles_ledger (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles,
  delta int not null,                         -- 댕마일 +적립/-사용
  reason text not null,                       -- run_bonus | drop | shop_spend ...
  ref_id uuid,
  created_at timestamptz not null default now()
);

create table drops (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners,
  kind drop_type not null,
  run_count_at int not null,                  -- 215
  contents jsonb not null,                    -- roll 결과 {miles, card?, gear?}
  pick_choice text,                           -- pick: boost | miles | gear
  opened_at timestamptz,
  created_at timestamptz not null default now()
);

create table boosts (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null
);

create table gear_claims (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles,
  side user_role not null,                    -- runner 어패럴 / owner 콜라보
  item text not null,
  milestone int not null,                     -- 러너: 회수 / 보호자: km
  status claim_status not null default 'locked',
  shipped_to uuid references addresses,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create table cards_owned (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles,
  card_key text not null,
  tier text not null default '일반',
  run_id uuid references runs,
  acquired_at timestamptz not null default now(),
  unique (profile_id, card_key)
);

-- ---------- comms & safety ----------
create table notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles,
  kind noti_kind not null,
  title text not null,
  body text,
  ref_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table chat_threads (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings unique,
  created_at timestamptz not null default now()
);

create table chat_messages (
  id bigint generated always as identity primary key,
  thread_id uuid not null references chat_threads on delete cascade,
  sender_id uuid not null references profiles,
  body text,
  kind text not null default 'text',          -- text | photo | location
  media_path text,
  created_at timestamptz not null default now()
);

create table emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles on delete cascade,
  name text not null,
  phone text not null
);

create table incidents (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references bookings,
  reporter_id uuid not null references profiles,
  kind text not null,                         -- dog_injury | lost_dog | third_party | equipment | other
  severity text not null default 'normal',    -- normal | urgent | sos
  note text,
  media text[] not null default '{}',
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------- indexes ----------
create index on bookings (owner_id, scheduled_at desc);
create index on bookings (runner_id, scheduled_at desc) where runner_id is not null;
create index on bookings (status);
create index on slot_holds (runner_id, starts_at) where booking_id is null;
create index on slot_holds (expires_at);
create index on chat_messages (thread_id, created_at);
create index on notifications (profile_id, created_at desc) where read_at is null;
create index on ledger_items (runner_id, created_at desc);
create index on miles_ledger (profile_id, created_at desc);
