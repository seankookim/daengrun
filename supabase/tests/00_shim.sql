-- 로컬 하네스 심 — Supabase 관리 스키마/역할을 흉내낸다 (테스트 전용, 배포 금지)

-- 역할
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;

-- auth 스키마: users + uid() (GUC 기반 — set_config('request.jwt.claim.sub', uuid, false)로 로그인 흉내)
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  email text
);
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
-- Schema USAGE, measured from production: authenticated can call auth.uid().
-- Without it a guard that calls auth.uid() raises 42501, and any test whose handler
-- catches `others` reads that infrastructure failure as a security refusal.
grant usage on schema auth to anon, authenticated;
create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon')
$$;

-- storage 스키마 (0006/0007/0010 정책용 최소 구조)
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  owner uuid
);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$
  select (string_to_array(name, '/'))[1 : array_upper(string_to_array(name, '/'), 1) - 1]
$$;

-- realtime 퍼블리케이션 (0008)
do $$ begin
  create publication supabase_realtime;
exception when duplicate_object then null; end $$;

-- pg_net 스텁 (0024) — http 호출을 기록만 하고 성공 흉내
create schema if not exists net;
create table if not exists net._stub_calls (id bigint generated always as identity, url text, body jsonb, at timestamptz default now());
create or replace function net.http_post(url text, headers jsonb default '{}'::jsonb, body jsonb default '{}'::jsonb)
returns bigint language plpgsql as $$
declare v_id bigint;
begin
  insert into net._stub_calls (url, body) values (url, body) returning id into v_id;
  return v_id;
end $$;

-- supabase 기본 권한 모사: 실서비스는 default privileges로 신규 테이블에 authenticated 전권을
-- 부여한다 — 따라서 '봉인'은 grant 부재가 아니라 RLS(정책 0 = 행 비가시·쓰기 거부)가 담당해야
-- 하고, leak 테스트도 그 조건에서 돌아야 실환경과 같다.
grant usage on schema public to anon, authenticated, service_role;
-- `all`, not `select, insert, update, delete` (2026-08-19, 0109): production's pg_default_acl for
-- tables in public is `arwdDxtm` — the `D` is TRUNCATE, which RLS does not cover. The old DML-only
-- line meant client roles never held TRUNCATE locally, so a suite could not tell 0109 present from
-- absent (its pins were green with the migration deleted). Same grantor as production (postgres).
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to authenticated, service_role;
-- service_role은 함수 EXECUTE를 PUBLIC이 아니라 Supabase 함수 default privileges로 받는다(운영). 심이
-- 이를 미모델링해 스크래치에서 settle_run_tx가 service_role=false로 보였다(리뷰어 플래그). 실환경과 맞춘다:
-- 이후 마이그레이션(같은 postgres 역할)이 만드는 public 함수는 default privileges로 service_role EXECUTE를
-- 받고(§1/§4의 public·anon 회수와 무관하게 유지), 심 시점 기존 함수엔 명시 grant로 소급한다.
alter default privileges in schema public grant execute on functions to service_role;
grant execute on all functions in schema public to service_role;

-- R4(0048) 동의 헬퍼 — 위탁 신청 필수 동의의 표준 테스트 값
create or replace function t_consent() returns jsonb
language sql immutable as $$
  select '{"custodyAck": true, "emergencyContact": "010-0000-0000", "pickupName": "테스트 픽업", "vetLimitKrw": 150000}'::jsonb
$$;

-- ---------- realtime (2026-08-15, trust — for 0103's broadcast authorization) ----------
-- The platform owns `realtime` in production; the harness has never had one, so 0103's policies
-- could not be applied here at all and the RULE would be pinned while the WIRING went untested.
-- That gap is this repo's signature defect (a pin that measures the helper, not the shipping
-- path), so the shim exists to close it: with it, suite 139 attempts real SELECT/INSERT against
-- `realtime.messages` as `authenticated` and observes RLS deciding.
-- Shapes match production, measured: columns from information_schema, RLS on, and `topic()`
-- reading a GUC so a test can set the topic the way realtime sets it per-connection.
create schema if not exists realtime;
create table if not exists realtime.messages (
  topic          text not null,
  extension      text not null,
  payload        jsonb,
  event          text,
  private        boolean default false,
  updated_at     timestamp not null default now(),
  inserted_at    timestamp not null default now(),
  id             uuid not null default gen_random_uuid(),
  binary_payload bytea
);
alter table realtime.messages enable row level security;
-- Grants MEASURED from production: anon AND authenticated both hold INSERT/SELECT/UPDATE, so RLS
-- is the only gate there. The shim must match, or a boundary test denies by PRIVILEGE and reads
-- as if the policy worked — which is exactly the false pass this shim exists to prevent.
grant usage on schema realtime to anon, authenticated;   -- schema USAGE, measured from production
grant select, insert, update on realtime.messages to anon, authenticated;
create or replace function realtime.topic() returns text
language sql stable as $$ select current_setting('realtime.topic', true) $$;

-- ---------- pg_cron (2026-08-21, location slice — 0120 §H) ----------
-- The platform owns `pg_cron` in production; the harness has never had one, so EVERY
-- `cron.schedule` in this repo has taken its `exception when others` arm locally and **no suite has
-- ever been able to assert that a job is actually scheduled.** That is not a hypothetical gap:
-- `0060:129-147` records `purge_expired_holds` sitting UNSCHEDULED for months while a comment
-- claimed it ran every minute, and `legal-ops-domain.md:415` says in as many words that *"the pin
-- belongs on `cron.job`, not on the function."* Without this stub that pin can only be prose.
-- Same reason, same shape and same precedent as the `realtime` shim twelve lines up: the shim
-- exists so a suite can measure the SHIPPING path instead of a helper.
--
-- ⚠ WHAT THIS CHANGES FOR EVERY OTHER SUITE, stated rather than discovered. Migrations whose
-- do-block calls `create extension if not exists pg_cron` FIRST (0014, 0026, 0035, 0037, 0043,
-- 0045, 0070) still take the exception arm here — a stub cannot fake an extension — so their jobs
-- do NOT appear locally. The ~9 whose do-block is the bare 0017/0060 form (0017, 0021, 0047, 0060,
-- 0063, 0076, 0080 ×2, 0083) now insert a `cron.job` row where they previously raised a NOTICE that
-- the harness filters anyway. Nothing in `supabase/tests/` reads `cron` today (grepped), so the
-- PREDICTED pin movement is zero — but it is a prediction, not a measurement, and it is written
-- here so the next red run has somewhere to look.
create schema if not exists cron;
create table if not exists cron.job (
  jobid    bigint generated always as identity primary key,
  schedule text not null,
  command  text not null,
  nodename text not null default 'localhost',
  nodeport int  not null default 5432,
  database text not null default current_database(),
  username text not null default current_user,
  active   boolean not null default true,
  jobname  text unique
);
-- Signature matches pg_cron's 3-arg form, which is the only one this repo calls (17 call sites).
create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint
language plpgsql as $$
declare v bigint;
begin
  insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid into v;
  return v;
end $$;
create or replace function cron.unschedule(job_name text) returns boolean
language plpgsql as $$ begin delete from cron.job where jobname = job_name; return found; end $$;
-- No client grant: production's `cron` schema is not reachable by anon/authenticated either, and a
-- suite that could read it as a client role would be measuring the wrong thing.
revoke all on schema cron from public;
revoke all on all tables in schema cron from public;
