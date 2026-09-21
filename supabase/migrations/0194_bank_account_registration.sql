-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0194 — 정산 계좌 registration: the table 0001 created and nobody ever filled
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY NOW. `bank_accounts` (0001:277-283) has existed since the first migration, `0002:125` gave
-- it RLS, `0115:537-572` wrote a whole ruling about RETAINING it through account deletion, and
-- `0190 §C` wrote the release that ends that retention. Four migrations reason about a row that
-- **cannot be created**: `grep bank_accounts app/src/lib/api.ts` returns 0, and
-- `app/app/runner/earnings.tsx:158-161` states the absence as a sentence
-- (「아직 등록된 계좌가 없어요 — 계좌 등록은 오픈뱅킹 연동과 함께 제공돼요」).
--
-- `0186:22` says the operator 「러너를 bank_accounts에서 찾아 은행에서 이체한 뒤」 types the number
-- into `ops_record_manual_payout`. That lookup has had nobody to find. This file gives the runner a
-- way to put a destination in, and the operator a gated, JOURNALLED way to read it out.
--
-- WHAT DID NOT CHANGE, said first because three shipped slices depend on it:
--   · `bank_accounts`'s columns keep their names and meanings. `account_enc` is still the
--     encrypted account number, `holder` still the real legal name, `verified_at` still NULL.
--   · `0115`'s conditional delete and `0190 §C`'s release are NOT touched. 221's R1/R3 assert a
--     retained row BYTE-IDENTICAL on (bank, account_enc, holder); this file adds a column and
--     changes no existing value, so those pins keep their meaning.
--   · `0186`'s ops gate is reused verbatim (`ops_recipients_for('payout_due')`) rather than
--     re-invented — the person who reads the account is the person who records the payout.
--
-- ⚠ `verified_at` STAYS NULL AND THIS FILE NEVER WRITES IT. There is no 예금주 조회 / 1원 인증
--   integration, so there is nothing that could honestly stamp it. A `now()` there would be a
--   fabricated verification in a money table — the exact shape the honesty law forbids. It is
--   RESET to NULL on every change (§F) so that the day a verifier does land, an edited account is
--   correctly unverified rather than carrying its predecessor's stamp.
--
-- ═══ §0a THE ENCRYPTION ROUTE, AND WHY IT IS NOT VAULT ════════════════════════════════════════
-- The route taken: **pgcrypto `pgp_sym_encrypt`, keyed from a SEALED key table whose key material
-- this migration generates itself with `gen_random_bytes(32)`.** No human ever types, sees or
-- relays the key; it is born inside the apply and read only by functions that never return it.
--
-- WHY NOT `vault.decrypted_secrets`, which is this repo's usual home for a secret (0080:1218,
-- 0116:339, 0138:249, …): **the local harness has no vault, and three shipped suites depend on
-- that absence being real.**
--   · `116:155-159` — 「the function returns 0 without ever exposing the count when the vault is
--     absent, and the local harness is exactly that environment (no vault schema), so no probe can
--     tell a correct predicate from a broken one … **if the vault ever gets stubbed in the shim,
--     this is the first pin to add**」. That is a shipped suite naming the exact edit as a change
--     to its own premise.
--   · `151:197-205` builds a vault STUB for its own arm and deletes only the secret ROW after it;
--     `181:38-43` measured that the schema survives and rewrote its own inherited claim because of
--     it. Stubbing vault in `00_shim.sql` would move the environment under all three.
-- Doing it anyway would buy a preference and cost three suites their premise, so the honest trade
-- is to take the route that behaves IDENTICALLY in the harness and in production and can therefore
-- be proven end to end here: pgcrypto, which `0001:4` already installs.
--
-- ⚠ WHAT THIS ROUTE IS WORTH, stated plainly rather than implied, because the name `account_enc`
--   invites over-reading: the key and the ciphertext live in the SAME DATABASE, so a full dump
--   carries both. What this defends against is every path that is not a full dump — a leaked
--   `select` on the table, a mis-scoped grant, a PostgREST mistake, a backup of one table, an
--   operator's screen. It is strictly stronger than the sealed-column model `0080 §A` uses for
--   `billing_keys` (which is not encrypted at all) and strictly weaker than an out-of-database
--   KMS. Moving the key to vault later is a key-rotation migration — re-encrypt each row under the
--   new key — and needs no schema change and no client change. That is the upgrade path, and it is
--   cheap precisely because nothing outside §E ever touches ciphertext.
--
-- ⚠ `set search_path = public, extensions, pg_temp` — **NOT the house literal, and a future
--   session must not 「simplify」 it back.** pgcrypto's schema is not the same in both worlds:
--   `0001:4`'s bare `create extension if not exists "pgcrypto"` lands it in `public` on a
--   from-scratch apply (the harness), while a Supabase project ships it pre-installed in
--   `extensions`, where that statement is a no-op. A definer pinned to `public, pg_temp` would
--   therefore resolve `pgp_sym_encrypt` in the harness and FAIL AT RUNTIME in production — a green
--   that means something narrower than it looks, in the direction that ships. Naming both schemas
--   costs nothing (`public` is still searched first, and a schema that does not exist is silently
--   skipped) and removes the difference instead of betting on it. `98 H1` asks only that
--   `pg_temp` be present, so the seal it enforces is intact; `0194-S1` pins this exact literal.
--
-- ═══ §0b DOCTRINE (0059 money-path list) ══════════════════════════════════════════════════════
-- self-contained · `set search_path` IN THE BODY (98 H1 — ALTER-applied config is reset by
-- `create or replace`) · every ACL written in THIS file, for functions first defined in THIS file ·
-- party gate BEFORE any state gate and before any read of the thing being gated ·
-- `is not true` / `is distinct from`, never a bare `IF` on a predicate that can be NULL ·
-- mutation-verified pins in `225_bank_account_registration_suite.sql`.
--
-- DEPLOY: **`supabase db push` ONLY.** No edge function change. The client half
-- (`app/app/runner/bank-account.tsx`, `app/src/lib/bank-account.ts`, `api.ts`) ships in the same
-- branch and needs a build, but nothing in this file waits on it.

-- ⚠ BELT ONLY — nothing in this file depends on it, and a future reader must not add a statement
--   that does. Every pgcrypto call lives inside a function whose own `set search_path` clause
--   postgres applies on entry (§A's key bootstrap included), which is why this file behaves the
--   same whether or not the runner wraps it in a transaction. A bare `set local` outside one is a
--   no-op with a warning, so anything resting on this line would be resting on the RUNNER.
set local search_path = public, extensions, pg_temp;
set client_min_messages = warning;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A the key — SEALED the way 0080 §A means it, and born inside this apply
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- One row, forever (`check (id = 1)` — a second key would silently orphan every row encrypted
-- under the first). RLS on with ZERO policies is `0080 §A`'s seal for `billing_keys`; the explicit
-- `revoke` beside it is belt, because a table born in a migration inherits whatever default
-- privileges the role carries and 0116:636 records that this stack's default is generous.
create table if not exists bank_account_keys (
  id           smallint primary key default 1 check (id = 1),
  key_material bytea    not null,
  created_at   timestamptz not null default now()
);
alter table bank_account_keys enable row level security;
revoke all on bank_account_keys from public, anon, authenticated;

-- ⚠ THE KEY IS MINTED INSIDE A FUNCTION, AND THE REASON IS THE SEARCH PATH RATHER THAN STYLE.
--   Every other pgcrypto call in this file sits in a function carrying
--   `set search_path = public, extensions, pg_temp`, which postgres applies on ENTRY and which no
--   session setting can undo. A bare top-level `gen_random_bytes(32)` would have been the ONE
--   statement here resolving against whatever `search_path` the migration runner happens to have —
--   and §0a's whole point is that pgcrypto lives in `public` here and in `extensions` on Supabase.
--   A `set local` above it would work only while the apply is inside a transaction, which is true
--   for both `db push` and the harness but is a property of the RUNNER, not of this file. This form
--   depends on nothing outside itself. The bootstrap is dropped immediately: it exists for one
--   statement and a function that can mint keys should not outlive that.
-- ⚠ `on conflict do nothing` is what makes this idempotent AND non-destructive: a re-apply must
--   never mint a second key, because that would make every existing `account_enc` unreadable —
--   silently, and only discovered the next time an operator tried to pay someone.
create or replace function _bank_account_key_init() returns void
language plpgsql volatile
set search_path = public, extensions, pg_temp
as $$
begin
  insert into bank_account_keys (id, key_material)
  values (1, gen_random_bytes(32))
  on conflict (id) do nothing;
end $$;
select _bank_account_key_init();
drop function _bank_account_key_init();

comment on table bank_account_keys is
  '0194 §A: bank_accounts.account_enc 를 여는 대칭키. SEALED — RLS on, 정책 0개, 클라 권한 전부 회수.
읽는 곳은 _bank_account_key() 하나뿐이고, 그 함수는 anon·authenticated·**service_role** 전부에서
EXECUTE 가 회수돼 있다 — service_role 은 bypassrls 라 RLS 가 봉인이 아니고 Supabase 기본 권한으로
public 함수 EXECUTE 를 받으므로(§E), 그 단어가 빠지면 이 키를 그대로 돌려주는 RPC 가 된다.
사람이 이 값을 입력하거나 보거나 옮기는 경로는 존재하지 않는다 — 마이그레이션이 gen_random_bytes(32)로 만든다.
⚠ 행은 영원히 하나다(check id = 1). 두 번째 키는 기존 ciphertext 전부를 조용히 못 읽게 만든다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B the bank list — a TABLE, not a check constraint
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `0186 §A` already argued this choice for `payouts.method`: 「어휘를 늘리는 일이 마이그레이션이
-- 되면 안 된다」. A bank that opens next year should be an INSERT, not a schema change.
--
-- ⚠ NO foreign key from `bank_accounts.bank` to this table, deliberately. `set_my_bank_account`
--   validates against it and raises the NAMED token `bad_bank`; an FK would fire first on some
--   paths and hand the client a raw `23503` constraint error, which is the unnamed refusal
--   `0115 §B.1` prohibits (a refusal must name something the user can resolve). Validation in the
--   function is the reachable rule; the table is its data.
--
-- ⚠ SEALED like §A, because the CLIENT DOES NOT READ THIS TABLE. The picker's list lives in
--   `app/src/lib/bank-account.ts`, and the two copies are drift-pinned in BOTH directions by
--   `app/test/bank-account.test.cjs`, which reads THIS FILE's seed block and compares it to the TS
--   array. That is `0189`'s shape for `_noti_urgent_noti_titles`, and it buys the picker an
--   instant render with no loading state and no RPC, without letting the lists diverge.
create table if not exists bank_codes (
  code   text primary key,
  label  text not null,
  sort   int  not null,
  active boolean not null default true
);
alter table bank_codes enable row level security;
revoke all on bank_codes from public, anon, authenticated;

-- 금융결제원 기관코드. The CODE is what `bank_accounts.bank` stores (§C), because a code survives a
-- rename and a label does not — 대구은행 became iM뱅크 in 2024 and any row holding the old string
-- would now be making a false claim about where the money goes.
-- BANK-LIST-BEGIN  (app/test/bank-account.test.cjs parses between these two markers)
insert into bank_codes (code, label, sort) values
  ('004', 'KB국민은행',   10),
  ('088', '신한은행',     20),
  ('020', '우리은행',     30),
  ('081', '하나은행',     40),
  ('011', 'NH농협은행',   50),
  ('003', 'IBK기업은행',  60),
  ('090', '카카오뱅크',   70),
  ('092', '토스뱅크',     80),
  ('089', '케이뱅크',     90),
  ('007', '수협은행',    100),
  ('023', 'SC제일은행',  110),
  ('027', '한국씨티은행', 120),
  ('031', 'iM뱅크',      130),
  ('032', '부산은행',    140),
  ('039', '경남은행',    150),
  ('034', '광주은행',    160),
  ('037', '전북은행',    170),
  ('035', '제주은행',    180),
  ('002', 'KDB산업은행', 190),
  ('045', '새마을금고',  200),
  ('048', '신협',        210),
  ('071', '우체국',      220)
on conflict (code) do update set label = excluded.label, sort = excluded.sort;
-- BANK-LIST-END

comment on table bank_codes is
  '0194 §B: 정산 계좌를 받을 수 있는 은행 목록(금융결제원 기관코드). bank_accounts.bank 가 담는 값은
LABEL이 아니라 CODE다 — 이름은 바뀌고(대구은행 → iM뱅크) 코드는 안 바뀐다. SEALED: 클라는 이 테이블을
읽지 않고 app/src/lib/bank-account.ts 의 사본을 쓰며, 두 사본은 app/test/bank-account.test.cjs 가
양방향으로 핀한다. 은행 추가는 INSERT이지 마이그레이션이 아니다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C bank_accounts — one new column, and the seal that was missing since 0002
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `updated_at` is what the screen shows next to a masked number so a runner can tell whether the
-- destination on file is the one they meant. There was no such column; `verified_at` is NULL by
-- design and `created_at` does not exist on this table.
-- ⚠ `not null default now()` backfills existing rows with the apply time, which is a claim about
--   WHEN they were last edited that we cannot actually make. It is accepted here for exactly one
--   measured reason: **production has no rows** — nothing in the repo has ever written this table
--   (this file is the first writer), and the only rows that exist anywhere are harness fixtures
--   created after the migrations apply. A nullable column would have been the honest shape on a
--   populated table, and a future session porting this pattern should reach for that instead.
alter table bank_accounts add column if not exists updated_at timestamptz not null default now();

comment on column bank_accounts.updated_at is
  '0194 §C: 이 계좌 정보가 마지막으로 바뀐 시각. set_my_bank_account 만 쓴다.';
comment on column bank_accounts.account_enc is
  '0194 §C: 계좌번호의 pgp_sym_encrypt ciphertext, base64. 키는 bank_account_keys(§A).
**authenticated 는 이 열을 SELECT 할 수 없다** — 아래 열 단위 grant 참고. 평문을 보는 곳은
_bank_account_plain() 하나뿐이고, 그 값을 반환하는 RPC 는 ops_bank_account() 하나뿐이며 그 호출은
bank_account_access_log 에 남는다.';
comment on column bank_accounts.bank is
  '0194 §B: 금융결제원 기관코드(bank_codes.code). 라벨이 아니다.';

-- ── THE SEAL. `bank self all` (0002:125) is `for all using (runner_id = auth.uid())`, so until
-- this statement the runner could `select account_enc` straight off the table over PostgREST and
-- could also INSERT and UPDATE it by hand. Both are wrong, for different reasons:
--   · READING the ciphertext buys an attacker who has the runner's session a copy of the payload
--     to attack offline, for no product benefit — nothing the runner needs is in that column.
--   · WRITING it is worse: a client that can set `account_enc` directly can store PLAINTEXT
--     there, and every later reader would decrypt garbage or, worse, succeed on a value we never
--     encrypted. The encryption owner is the server; this makes that a fact rather than a habit.
-- RLS decides ROWS; a column grant is the only thing that decides COLUMNS (0088's law, 0107's
-- two-step shape, 0186 §A's precedent on `payouts`).
-- ⚠ The re-grant is 0001's four columns plus §C's new one, i.e. TODAY'S REACH MINUS `account_enc`.
--   A `select *` by the runner narrows rather than breaking: PostgREST asks for named columns.
revoke select, insert, update, delete on bank_accounts from public, anon, authenticated;
grant select (runner_id, bank, holder, verified_at, updated_at) on bank_accounts to authenticated;

-- ⚠ `delete_my_account_tx` (0115:200-203, `security definer`, re-created by 0138 §F and 0190 §B
--   from the catalog) and `ops_record_manual_payout`'s §C release both delete from this table.
--   Both are SECURITY DEFINER owned by the table owner, so the revoke above does not reach them —
--   verified by the harness, which runs 0115's and 0190's own retention pins (150 P9, 221 R1-R4)
--   AFTER this file has applied.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D the journal — a decrypt is never silent
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `ops_bank_account()` hands a real account number to a human. That is the single most sensitive
-- return value in this schema, and the only thing that makes it acceptable is that every call
-- leaves a row saying WHO looked, at WHOSE row, WHEN, and whether anything was there.
--
-- ⚠ NAMED `%_access_log` ON PURPOSE — but read WHICH guard that enrols it in, because this file's
--   first draft named the wrong one and a cold reviewer caught it.
--   The wildcard `t like '%access\_log'` appears in TWO places, and they are not interchangeable:
--     · `0115:833` / `0115:853` — a `do $watchdog$` block, which executes **at 0115's position in
--       the numeric order, seventy-nine files before this table exists.** It can therefore NEVER
--       see `bank_account_access_log`, on a fresh apply or on `db push`. The draft claimed a
--       convenient `on delete cascade` here 「is stopped by 0115's own VERIFY」. It is not.
--     · `150 N6-1` / `N6-2` (`150:951-957`, `150:972-974`) — the SUITE re-derives the same closure
--       from `prosrc` after every migration has applied, so it does see this table. **That** is
--       what the name buys, and it is still worth having: a future FK here yields a clean apply
--       and a red harness, rather than nothing at all.
--   The distinction matters beyond the credit: a session that adds an FK expecting an ABORT gets a
--   successful apply, and one that checks 0115's block to confirm enrolment finds the table absent
--   and may wrongly conclude the guard is broken. Same family as reading a green as broader than
--   its own sentence — here it was a guard read as earlier than its own position.
--
-- ⚠ NO FOREIGN KEYS, and this is `0186 §A`'s argued precedent for `payouts.recorded_by` rather
--   than laziness. `runners.profile_id references profiles on delete cascade` (0001:58) and
--   `0115`'s ④ deletes `auth.users`, so an FK here would have to choose between:
--     · NO ACTION / restrict — an operator's (or a runner's) own account deletion fails with a raw
--       constraint error that `delete_my_account_tx` does not name, which is `0115 §B.1`'s exact
--       prohibition; or
--     · CASCADE / SET NULL — which ERASES an audit fact so that an account can close, and is
--       precisely what 0115 §F arm 2 exists to refuse.
--   Both are 0115's decision, not this file's. The two uids are recorded as FACTS: they resolve
--   while the profile lives and stand as opaque audit ids afterwards. Pinned as an ABSENCE (S1).
create table if not exists bank_account_access_log (
  id             uuid primary key default gen_random_uuid(),
  ops_profile_id uuid not null,
  runner_id      uuid not null,
  found          boolean not null,
  at             timestamptz not null default now()
);
create index if not exists bank_account_access_log_runner_idx
  on bank_account_access_log (runner_id, at desc);
alter table bank_account_access_log enable row level security;
revoke all on bank_account_access_log from public, anon, authenticated;

comment on table bank_account_access_log is
  '0194 §D: ops_bank_account() 호출 장부. 복호화는 절대 조용히 일어나지 않는다 — 한 번 호출 = 한 행,
행이 없었어도(found=false) 남는다(존재 여부를 떠보는 것도 접근이다). SEALED: RLS on, 정책 0개.
FK 없음 — 0186 §A 가 recorded_by 로 이미 논증한 이유 그대로(restrict 는 탈퇴를 이름 없는 제약
오류로 막고, cascade 는 감사 사실을 지운다; 둘 다 0115 의 결정이다).
이름이 %_access_log 인 것은 0115 §F 의 감시 대상에 자동으로 들어가기 위함이다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E the two private helpers — the ONLY places ciphertext is touched
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Both are `_`-prefixed, which is this repo's marker for 「not a client surface」
-- (`scripts/check-rpc-contracts.mjs` skips them by that prefix).
--
-- ⚠ NEITHER IS `SECURITY DEFINER`, and that is the stronger choice rather than an omission. A
--   definer that returns plaintext is one bad grant away from being a plaintext oracle. These run
--   with the CALLER's privileges, so the §F definers reach them (they execute as the table owner,
--   for whom RLS does not apply) while `anon` and `authenticated` are stopped twice over: the
--   revoke below, and §A's RLS returning them zero rows even if they somehow held EXECUTE.
--
-- 🔴 `service_role` IS NAMED IN THE REVOKE, and leaving it out was a real hole in this file's
--   first draft — caught by a cold reviewer, then confirmed against three artifacts rather than
--   taken on trust. It is NOT the 「two independent seals」 story: `service_role` is `bypassrls`
--   (`00_shim.sql:6`), so RLS is not a seal for it at all, and `00_shim.sql:132-135` grants
--   EXECUTE on public functions to `service_role` BY DEFAULT — with a comment saying it models
--   production deliberately, because a reviewer once found `settle_run_tx` reading
--   `service_role=false` in the harness and true in the real schema. `0129:105-120` then MEASURED
--   `pg_default_acl` object type `f` = `{service_role=X/postgres}`. So without this word,
--   `_bank_account_key()` is a PostgREST-reachable RPC that RETURNS THE KEY, and
--   `_bank_account_plain()` a one-call plaintext oracle for any runner — with no journal row,
--   which is precisely what §D exists to make impossible.
--   ⚠ HONEST SCOPE, because the difference decides what this is: `service_role` already holds
--   `select` on every table here (`0080 §A`'s posture, and the house's), so a key holder could
--   read `key_material` and `account_enc` and decrypt by hand. This is therefore a needless
--   ONE-CALL door beside a hard one, not a privilege escalation — the same distinction as
--   「a grant is not a door」. It is still wrong to leave: the file ARGUED the seal, and §G and the
--   suite both checked only `anon`/`authenticated`, so neither could ever have noticed.
--   `0117:808` is the house form for exactly this shape, verbatim: an internal helper reached only
--   through functions that run as owner, revoked from `public, anon, authenticated, service_role`.
create or replace function _bank_account_key() returns bytea
language sql stable
set search_path = public, extensions, pg_temp
as $$ select key_material from bank_account_keys where id = 1 $$;
revoke all on function _bank_account_key() from public, anon, authenticated, service_role;

-- The plaintext account number, or NULL when this row cannot be read.
-- ⚠ THE `exception when others` IS DELIBERATE AND IS NOT A SILENT-CATCH VIOLATION. It converts
--   three genuinely different faults — `account_enc` that is not base64, ciphertext written under
--   a key that no longer exists, a missing key row — into one value, NULL, whose entire purpose is
--   that BOTH CALLERS TURN IT BACK INTO A VISIBLE FAILURE: `my_bank_account` returns a NULL mask
--   so the screen can say the number must be re-entered, and `ops_bank_account` returns the row
--   with a NULL `account` rather than hand an operator a partial answer. What must never happen is
--   a raw pgcrypto error reaching a client as a stack-shaped string, and what must never happen
--   twice as badly is a half-decrypted number being typed into a bank transfer.
--   ⚠ NEITHER CALLER RAISES on this path, and that is deliberate — see §F④: a raise would roll
--   back its own journal row, so the least auditable outcome would be the one that leaves no
--   audit. NULL is reported, the transaction commits, and the record of the attempt survives.
create or replace function _bank_account_plain(p_runner uuid) returns text
language plpgsql stable
set search_path = public, extensions, pg_temp
as $$
declare v_enc text; v_key bytea;
begin
  select account_enc into v_enc from bank_accounts where runner_id = p_runner;
  if v_enc is null then return null; end if;
  v_key := _bank_account_key();
  if v_key is null then return null; end if;
  return pgp_sym_decrypt(decode(v_enc, 'base64'), encode(v_key, 'hex'));
exception when others then
  return null;
end $$;
revoke all on function _bank_account_plain(uuid) from public, anon, authenticated, service_role;

comment on function _bank_account_plain(uuid) is
  '0194 §E: 계좌번호 평문 또는 NULL(못 읽음). definer 아님 — 호출자 권한으로 돈다.
NULL 은 삼킨 실패가 아니다: my_bank_account 는 마스크를 NULL 로 돌려 화면이 「다시 등록해주세요」를
말하게 하고, ops_bank_account 는 account_unreadable 로 거절한다. 반쯤 복호화된 번호가 이체창에
들어가는 것보다 거절이 낫다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §F the four RPCs
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The refusal vocabulary, in one place because `app/src/lib/bank-account.ts` mirrors it and
-- `app/test/bank-account.test.cjs` pins the two lists against each other BY EQUALITY:
--   not_signed_in · not_runner · bad_bank · bad_account · bad_holder · payout_owed ·
--   not_ops · no_runner
-- ⚠ `account_unreadable` is NOT in this list any more. It was, until §F④ stopped raising it (a
--   raise discards its own journal row), and it now names a STATE the client renders — a NULL
--   mask — rather than a refusal the server sends. It therefore lives in `bank-account.ts` as its
--   own copy constant and NOT in the refusal map, so the equality pin stays an equality.

-- ── ① READ (own) ──────────────────────────────────────────────────────────────────────────────
-- Zero rows = no account on file, an honest empty state rather than an error (0080 §A's
-- `my_billing_card` shape). `account_masked` is NULL only when the row cannot be decrypted.
create or replace function my_bank_account()
returns table (bank text, bank_label text, holder text, account_masked text,
               verified_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
declare v_uid uuid := auth.uid(); v_plain text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  v_plain := _bank_account_plain(v_uid);
  return query
    select b.bank,
           c.label,
           b.holder,
           case when v_plain is null then null else '••••' || right(v_plain, 4) end,
           b.verified_at,
           b.updated_at
      from bank_accounts b
      left join bank_codes c on c.code = b.bank
     where b.runner_id = v_uid;
end $$;
revoke execute on function my_bank_account() from public, anon;
grant  execute on function my_bank_account() to authenticated;

comment on function my_bank_account is
  '0194 §F①: 본인의 정산 계좌. 번호는 마지막 4자리만(서버에서 복호화해 만든다), 행이 없으면 0행.
account_masked 가 NULL 이면 그 행은 복호화가 안 된다는 뜻이고 화면은 다시 등록을 안내해야 한다.';

-- ── ② WRITE (own) ─────────────────────────────────────────────────────────────────────────────
-- Returns the row AS STORED, the same reason `set_notification_prefs` does (0187 §B, and
-- `api.ts`'s note on it): a screen that draws what it SENT rather than what the server KEPT is
-- showing a guess. Here the guess would be about a money destination.
create or replace function set_my_bank_account(p_bank text, p_account text, p_holder text)
returns table (bank text, bank_label text, holder text, account_masked text,
               verified_at timestamptz, updated_at timestamptz)
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_digits text;
  v_holder text;
begin
  -- ① PARTY GATE — ahead of every validation, so a non-runner learns nothing about which bank
  --    codes exist or what shape an account number has.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from runners r where r.profile_id = v_uid)) is not true
    then raise exception 'not_runner'; end if;

  -- ② the bank. `is not true` rather than a bare IF: a NULL from any cause refuses.
  if (select exists (select 1 from bank_codes c
                      where c.code = p_bank and c.active)) is not true
    then raise exception 'bad_bank'; end if;

  -- ③ the account number. ⚠ The shape is checked BEFORE the strip, not after. Stripping every
  --    non-digit first would silently accept 「계좌 1234567890」 and store the digits — a value the
  --    runner never typed. So: digits, with hyphens or spaces allowed BETWEEN them, and nothing
  --    else; then the separators come out and the length is measured on what remains.
  -- ⚠ `btrim` FIRST, and it is a drift fix rather than a nicety. `bank-account.ts`'s mirror trims
  --    before testing the same regex, so without this the client ACCEPTS a pasted 「 1234567890 」
  --    and the server refuses it — the person is told 「숫자 10~16자리예요」 while looking at a
  --    field holding exactly ten digits, and nothing they can do resolves it. A mirror that
  --    accepts what the server refuses is the worst direction for the two copies to differ, and
  --    `app/test/bank-account.test.cjs` pinned the client's trim as correct, so only the server
  --    could move. Leading and trailing whitespace is a paste artifact, never data.
  if p_account is null or btrim(p_account) !~ '^[0-9]([0-9 -]*[0-9])?$'
    then raise exception 'bad_account'; end if;
  v_digits := regexp_replace(btrim(p_account), '[^0-9]', '', 'g');
  if length(v_digits) < 10 or length(v_digits) > 16
    then raise exception 'bad_account'; end if;

  -- ④ the holder. Stored trimmed; empty after trimming is not a name.
  v_holder := btrim(coalesce(p_holder, ''));
  if v_holder = '' or length(v_holder) > 60 then raise exception 'bad_holder'; end if;

  -- ⑤ the write. `verified_at` is RESET, never preserved — see the header. `updated_at` is set
  --    explicitly on both arms so the column means 「last edited」 and not 「first created」.
  insert into bank_accounts (runner_id, bank, account_enc, holder, verified_at, updated_at)
  values (v_uid, p_bank,
          encode(pgp_sym_encrypt(v_digits, encode(_bank_account_key(), 'hex')), 'base64'),
          v_holder, null, now())
  on conflict (runner_id) do update
     set bank        = excluded.bank,
         account_enc = excluded.account_enc,
         holder      = excluded.holder,
         verified_at = null,
         updated_at  = now();

  return query select * from my_bank_account();
end $$;
revoke execute on function set_my_bank_account(text, text, text) from public, anon;
grant  execute on function set_my_bank_account(text, text, text) to authenticated;

comment on function set_my_bank_account(text, text, text) is
  '0194 §F②: 본인의 정산 계좌 등록/변경. 러너만(party gate 가 모든 검증보다 앞). p_bank 는
bank_codes.code, p_account 는 숫자와 구분자(- 공백)만 10~16자리, p_holder 는 trim 후 비어 있지 않을 것.
거절: not_signed_in · not_runner · bad_bank · bad_account · bad_holder.
암호화는 서버가 한다 — 클라가 account_enc 를 쓸 방법은 §C 의 revoke 로 없앴다.
verified_at 은 항상 NULL 로 초기화된다(예금주 조회가 없으므로 찍을 수 있는 진실이 없다).';

-- ── ③ DELETE (own) ────────────────────────────────────────────────────────────────────────────
-- Sean's O-7 / `A-intact-when-owed` ruling (0115:537-563) says the row must stay INTACT while
-- money is owed, because 「a payment instrument with no holder name is not a payment instrument」.
-- That ruling was written for account DELETION; it applies with exactly the same force to a runner
-- deleting only the bank row, and for the same reason — the money must still have a destination.
--
-- 🔴 THE PREDICATE IS `0190 §B`'s, EXACTLY — `paid_payout_id is null`, and NOTHING ELSE. This
--   file's first draft used 0186's PAYOUT-ELIGIBILITY predicate instead (the same clause plus
--   `not exists (an open run on the booking)`) and described it as 「0186's, verbatim」. A cold
--   reviewer took that apart and was right twice:
--     · It is not verbatim — 0186 also carries `having sum(…) > 0`, which the draft dropped.
--     · **The conjunct's POLARITY INVERTS between the two uses, so copying the text copies the
--       wrong meaning.** In 0186 `not exists(open run)` narrows what may be PAID — conservative,
--       「the amount can still move, so don't pay yet」. Here the same clause narrowed what is
--       REFUSED — permissive, 「nothing is owed, so go ahead and delete the destination」. Identical
--       text, opposite sign; the §④ 「widening a return's MEANING」 class with no edit to look at.
--   The consequence was concrete: a runner whose unpaid rows all belonged to bookings with an open
--   run was REFUSED by account deletion (`0190 §B` keeps the bank row) and ALLOWED by this RPC —
--   **one Sean ruling, two doors, opposite answers, about a money destination.** Aligning to
--   `0190 §B` is the minimal honest fix: it is the sibling implementation of the SAME ruling
--   (A-intact-when-owed) about the SAME row, and it refuses strictly more, which is the safe
--   direction for a payment destination.
-- ⚠ AND THE INACTION CORNER, NAMED RATHER THAN SILENTLY INHERITED (same review, law 8). The
--   predicate is EXISTENCE, not `sum(...) > 0`, so a runner whose remaining unpaid rows net to
--   ≤ ₩0 is invisible to `ops_payouts_due` (`0186:249` hides a non-positive total), unpayable by
--   `ops_record_manual_payout` (`0186:329` refuses `bad_amount` on ≤ 0), and therefore refused
--   here forever, with copy telling them to wait for something nobody can do. **That corner is
--   `0190 §B`'s, not this file's** — it is exactly what keeps such a runner's bank row through
--   account deletion too, and `delete-account-sheet.tsx:221-222` already records the shape
--   (「a ledger netting exactly ₩0 would have been kept server-side」). Adding `> 0` HERE would
--   re-create the two-doors divergence this paragraph just removed, so the corner stays shared and
--   stays written down; whoever narrows it must narrow both doors in one slice.
create or replace function delete_my_bank_account() returns void
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from runners r where r.profile_id = v_uid)) is not true
    then raise exception 'not_runner'; end if;

  -- Written as 「the proof of absence must be TRUE」 (0186 §0d ⓒ's form) so that a NULL from any
  -- cause REFUSES the deletion rather than allowing it. Failing closed here keeps a destination;
  -- failing open loses one while money is owed.
  if (select not exists (
        select 1 from ledger_items l
         where l.runner_id = v_uid
           and l.paid_payout_id is null
      )) is not true
    then raise exception 'payout_owed'; end if;

  delete from bank_accounts where runner_id = v_uid;
end $$;
revoke execute on function delete_my_bank_account() from public, anon;
grant  execute on function delete_my_bank_account() to authenticated;

comment on function delete_my_bank_account is
  '0194 §F③: 본인의 정산 계좌 삭제. 미지급 원장 행이 하나라도 있으면 payout_owed 로 거절한다.
근거는 Sean 의 A-intact-when-owed(0115:537-563)이고, 술어는 **0190 §B 의 보관 술어와 글자 그대로
같다**(paid_payout_id is null) — 같은 판결을 집행하는 두 문이 다른 답을 내면 안 되기 때문이다.
0186 의 지급-자격 술어를 빌려 쓰면 안 된다: 같은 절이 거기서는 지급을 좁히고(보수적) 여기서는
거절을 좁힌다(허용적) — 글자는 같고 뜻이 뒤집힌다. 거절은 fail-closed 로 쓰여 있다.';

-- ── ④ READ (ops) ──────────────────────────────────────────────────────────────────────────────
-- The operator's transfer destination. Everything about this function is the gate and the journal.
create or replace function ops_bank_account(p_runner uuid)
returns table (bank text, bank_label text, holder text, account text,
               verified_at timestamptz, updated_at timestamptz)
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  v_uid   uuid := auth.uid();
  v_plain text;
  v_has   boolean;
begin
  -- ① PARTY GATE — ops membership, ahead of EVERY read. The `p_runner is null` check sits after
  --    it deliberately: a stranger passing a null must learn `not_ops`, not `no_runner`, because
  --    the difference between those two answers is itself information about the gate.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
    then raise exception 'not_ops'; end if;
  if p_runner is null then raise exception 'no_runner'; end if;

  -- ② the journal, BEFORE the answer is assembled. A row exists for every gated call, including
  --    the ones that find nothing — probing for existence is access.
  select exists (select 1 from bank_accounts b where b.runner_id = p_runner) into v_has;
  insert into bank_account_access_log (ops_profile_id, runner_id, found)
  values (v_uid, p_runner, v_has);

  if v_has is not true then return; end if;

  -- ③ the decrypt. An unreadable row comes back with `account` NULL — never a partial number, and
  --    never a raise.
  -- 🔴 IT MUST NOT RAISE, AND THE REASON IS THE JOURNAL. The first draft raised
  --    `account_unreadable` here, two statements after the insert above. A cold reviewer pointed
  --    out what that costs: PostgREST wraps each request in a transaction, so **the raise discards
  --    its own journal row** — and the one access an operator should never be able to make quietly
  --    was the only one leaving no trace at all. Worse, it is a usable probe: repeat the call and
  --    you learn the row EXISTS, with zero audit. A refusal that erases the record of itself is
  --    the opposite of what §D is for, so the failure is REPORTED IN THE ROW instead: the
  --    transaction commits, the journal keeps its line, and the operator sees `account = NULL`,
  --    which is absent rather than partial. Zero rows still means 「no account on file」, so the two
  --    outcomes stay distinguishable.
  -- ⚠ A CONCURRENT DELETE LANDS HERE TOO and is reported the same way — the row existed at ②,
  --    is gone by ③, and `account` comes back NULL. That reads as 「could not be read」 rather than
  --    「was deleted」. Naming it rather than locking it: a `for update` on someone else's bank row
  --    inside an ops read would block a runner's own deletion behind an operator's screen, which
  --    is a worse trade than an operator re-running a read.
  v_plain := _bank_account_plain(p_runner);

  return query
    select b.bank, c.label, b.holder, v_plain, b.verified_at, b.updated_at
      from bank_accounts b
      left join bank_codes c on c.code = b.bank
     where b.runner_id = p_runner;
end $$;
revoke execute on function ops_bank_account(uuid) from public, anon;
grant  execute on function ops_bank_account(uuid) to authenticated;

comment on function ops_bank_account(uuid) is
  '0194 §F④: 운영자가 이체하려고 읽는 러너의 실계좌번호. 게이트는 0186 의 것과 같다
(ops_recipients_for(''payout_due'')) — 지급을 기록하는 사람이 계좌를 읽는 사람이다.
게이트를 통과한 호출 한 번 = bank_account_access_log 한 행, 행을 못 찾았어도(found=false) 남는다.
복호화 실패는 **예외가 아니라 account = NULL 로** 보고한다 — 예외를 던지면 같은 트랜잭션의 장부 행이
함께 롤백돼, 가장 감사돼야 할 호출이 흔적을 안 남기는 유일한 호출이 된다. 반쯤 읽힌 번호는 어느
경우에도 나가지 않는다(부분이 아니라 부재다).
⚠ authenticated 에 EXECUTE 가 있는 것은 PostgREST 를 통해 운영자가 부르기 때문이고, 그래서 이 함수의
유일한 방어는 본문 첫 팔의 ops 게이트다 — 그 팔을 지우면 모든 러너의 계좌가 모두에게 열린다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §G VERIFY — this apply fails rather than ships a half-built seal
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ These arms and `225_bank_account_registration_suite.sql` are DIFFERENT ARTIFACTS and neither
--   is evidence for the other: this aborts a production apply that lands wrong, the suite reddens
--   when a LATER file undoes something. Per `0131-G4`'s lesson, a property checked only at apply
--   is protected exactly until someone recreates the function — so S1 restates these in the suite.
do $verify$
declare
  v_bad text := '';
  v_oid oid;
  fn    text;
  fns   text[] := array['my_bank_account()', 'set_my_bank_account(text,text,text)',
                        'delete_my_bank_account()', 'ops_bank_account(uuid)'];
begin
  foreach fn in array fns loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '')
          = 'search_path=public, extensions, pg_temp' from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':SEARCH-PATH'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ':ANON-EXECUTABLE'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':NO-AUTHENTICATED'; end if;
  end loop;

  -- The private helpers must not be reachable by ANY role that talks to PostgREST.
  -- ⚠ `service_role` IS IN THIS LIST, and its absence was the defect a cold reviewer found in the
  --   first draft: `00_shim.sql:132-135` (modelling production, as its own comment says) grants
  --   EXECUTE on public functions to `service_role` by default and `0129:105-120` measured that
  --   default ACL, so an arm that checks only anon/authenticated CANNOT SEE the hole it exists to
  --   guard. This is the arm that would have.
  foreach fn in array array['_bank_account_key()', '_bank_account_plain(uuid)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
    or has_function_privilege('service_role', v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ':CLIENT-EXECUTABLE'; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not false
      then v_bad := v_bad || ' ' || fn || ':IS-DEFINER(must not be)'; end if;
  end loop;

  -- the ciphertext column is not selectable, and the four display columns still are
  if has_column_privilege('authenticated', 'bank_accounts', 'account_enc', 'SELECT') is not false
    then v_bad := v_bad || ' bank_accounts.account_enc:CLIENT-READABLE'; end if;
  if has_column_privilege('authenticated', 'bank_accounts', 'holder', 'SELECT') is not true
    then v_bad := v_bad || ' bank_accounts.holder:LOST-THE-REGRANT'; end if;
  if has_table_privilege('authenticated', 'bank_accounts', 'INSERT') is not false
  or has_table_privilege('authenticated', 'bank_accounts', 'UPDATE') is not false
    then v_bad := v_bad || ' bank_accounts:CLIENT-WRITABLE'; end if;

  -- the two sealed tables
  if (select relrowsecurity from pg_class where oid = 'bank_account_keys'::regclass) is not true
    then v_bad := v_bad || ' bank_account_keys:NO-RLS'; end if;
  if (select count(*) from pg_policy where polrelid = 'bank_account_keys'::regclass) <> 0
    then v_bad := v_bad || ' bank_account_keys:HAS-POLICY'; end if;
  if (select relrowsecurity from pg_class where oid = 'bank_account_access_log'::regclass) is not true
    then v_bad := v_bad || ' bank_account_access_log:NO-RLS'; end if;
  -- ⚠ `bank_codes` IS IN THIS SWEEP. The first draft sealed it and then checked only the other
  --   two, so the seal on the one table a client might plausibly want to read was pinned nowhere
  --   (a cold reviewer's finding). It is not secret, but it is not a client surface either — the
  --   picker reads `bank-account.ts`, and an unguarded seal is a seal that quietly stops existing.
  if (select relrowsecurity from pg_class where oid = 'bank_codes'::regclass) is not true
    then v_bad := v_bad || ' bank_codes:NO-RLS'; end if;
  if has_table_privilege('authenticated', 'bank_account_keys', 'SELECT') is not false
  or has_table_privilege('authenticated', 'bank_account_access_log', 'SELECT') is not false
  or has_table_privilege('authenticated', 'bank_codes', 'SELECT') is not false
  or has_table_privilege('anon', 'bank_account_keys', 'SELECT') is not false
  or has_table_privilege('anon', 'bank_account_access_log', 'SELECT') is not false
  or has_table_privilege('anon', 'bank_codes', 'SELECT') is not false
    then v_bad := v_bad || ' sealed-table:CLIENT-READABLE'; end if;

  -- the journal must have no foreign keys (§D's argued absence)
  if (select count(*) from pg_constraint
       where conrelid = 'bank_account_access_log'::regclass and contype = 'f') <> 0
    then v_bad := v_bad || ' bank_account_access_log:HAS-FK(0186 §A says no)'; end if;

  -- exactly one key, and it is 32 bytes
  if (select count(*) from bank_account_keys) <> 1
    then v_bad := v_bad || ' bank_account_keys:ROW-COUNT'; end if;
  if (select length(key_material) from bank_account_keys where id = 1) is distinct from 32
    then v_bad := v_bad || ' bank_account_keys:KEY-LENGTH'; end if;

  -- the seed landed. ⚠ Counted over ALL rows, NOT `where active` — deactivating a bank that has
  --   closed is an ordinary INSERT-shaped data operation (§B's whole argument for a table), and an
  --   arm keyed to `active` would abort a future apply the third time someone did it. The property
  --   here is 「the seed ran」, not 「nobody has ever retired a bank」.
  if (select count(*) from bank_codes) < 20
    then v_bad := v_bad || ' bank_codes:SHORT-LIST'; end if;

  if v_bad <> '' then
    raise exception '0194 §G VERIFY:%', v_bad
      using hint = 'Do not weaken this block. Each arm is a seal that the suite restates as 0194-S1.';
  end if;
end
$verify$;
