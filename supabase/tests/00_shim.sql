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

-- [0150] pg_net's RESPONSE table. `net.http_post` is asynchronous — it returns a request id and
-- the worker writes the answer here later — so anything that reads a response back needs this to
-- exist. Shape copied from the linked production project (pg_net 0.20.4), column for column.
-- ⚠ NO PRIMARY KEY AND NO INDEX ON `id`, deliberately: production has neither (its only index is
--   `_http_response_created_idx` on `created`). A shim that added a PK would let a suite lean on a
--   uniqueness the real table does not provide — the shim's job is to be as weak as production.
-- ⚠ NOTHING WRITES THIS AUTOMATICALLY. The `net.http_post` stub above still only records the call
--   in `net._stub_calls`; a suite that wants an answer plants the row itself, which is the honest
--   model of an async worker we do not run here.
create table if not exists net._http_response (
  id           bigint,
  status_code  int,
  content_type text,
  headers      jsonb,
  content      text,
  timed_out    boolean,
  error_msg    text,
  created      timestamptz default now()
);
create index if not exists _http_response_created_idx on net._http_response (created);

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

-- 🔴 [0160] `realtime.send` — the broadcast-from-postgres entry point. Semantics copied from the
--    DEPLOYED function on the linked production project, recorded 2026-08-31 in
--    `docs/contracts/pack-publish-hardening-contract.md` foundations #4/#5/#6:
--      · it embeds an id into the payload but KEEPS a caller-supplied `payload->>'id'`, while the
--        ROW's id is always the column default's own `gen_random_uuid()` — so a verify-read must
--        match on `payload->>'id'` and never on the row id;
--      · it sets `realtime.topic` LOCALly, which is how the RLS predicate sees the topic;
--      · 🔴 **it SWALLOWS EVERY ERROR** — `exception when others then raise warning`, returns
--        void. A send that fails leaves NO caller-visible signal at all.
--
-- 🔴 **NOTHING IN THE PRODUCT CALLS THIS ANY MORE, AND IT IS KEPT DELIBERATELY.** 0160 §A's first
--    design broadcast through `realtime.send` and then verify-read its own row, precisely because
--    of the swallow above. The /autoplan addendum (item 1) replaced that with a DIRECT INSERT
--    into `realtime.messages` inside its own `begin/exception` block: an INSERT that fails RAISES,
--    and an exception is a better detector than any read-back — free, immediate, and it names the
--    cause. So this mirror is now DOCUMENTATION of what production ships (foundations #4/#5/#6 in
--    `docs/contracts/pack-publish-hardening-contract.md`), not a dependency of any migration or
--    pin. Verified 2026-08-31: no suite calls it. Keep it — a future slice reaching for
--    `realtime.send` needs to meet the swallow here rather than discover it on production.
-- ⚠ **IF A PIN EVER DOES CALL IT, THE `SET LOCAL realtime.topic` LEAKS TO TRANSACTION END.**
--    `set local` is scoped to the transaction, not to this function, and each suite file is ONE
--    transaction — so a later boundary pin in the same file would see a topic it did not set, and
--    an RLS predicate reading `realtime.topic()` would decide against the wrong string. Reset it
--    (`perform set_config('realtime.topic', '', true)`) right after any call. Production has the
--    same behaviour; there the transaction is one PostgREST request, which is why it has never
--    bitten anyone.
-- ⚠ **A LIMITATION OF THIS SHIM, STATED HERE RATHER THAN PINNED**: production's
--    `realtime.messages` is PARTITIONED by day, so a real publish into a cold project can fail
--    with `MissingPartition` and 0160's `not_delivered` refusal is reachable there. This table is
--    unpartitioned and the INSERT always succeeds, so `not_delivered` is UNREACHABLE in the
--    harness. Suite 191 says so in prose and guards the exception handler's EXISTENCE with a
--    source pin instead — a pin whose arms are green by construction would be an unfalsifiable
--    guard doing prose's job.
create or replace function realtime.send(payload jsonb, event text, topic text,
                                         private boolean default true)
returns void
language plpgsql
as $rtsend$
begin
  begin
    execute format('set local realtime.topic to %L', topic);
    insert into realtime.messages (topic, extension, payload, event, private)
    values (topic, 'broadcast',
            jsonb_build_object('id', gen_random_uuid()) || coalesce(payload, '{}'::jsonb),
            event, private);
  exception when others then
    raise warning 'ErrorSendingBroadcastMessage: %', sqlerrm;
  end;
end $rtsend$;

-- 🔴 [0151] MIRROR pg_net's REAL DEFAULT, or 182's pins pass vacuously. Supabase ships pg_net with
--    `usage` on schema `net` and `select` on its tables granted to `anon` and `authenticated`
--    (measured on production 2026-08-27). This stub created the schema as postgres and granted
--    nothing, so 0151 had NOTHING TO REVOKE and N1/N2 were green because the grant never existed
--    — not because the migration removed it. **A fixture that omits the defect cannot test the
--    fix**, and the pin reads identically in both worlds, which is the whole failure mode.
--    Granting here puts the harness in production's starting state so 0151 is exercised each run.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant usage on schema net to anon, authenticated';
    execute 'grant select on all tables in schema net to anon, authenticated';
  end if;
end $$;
