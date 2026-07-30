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
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to authenticated, service_role;
