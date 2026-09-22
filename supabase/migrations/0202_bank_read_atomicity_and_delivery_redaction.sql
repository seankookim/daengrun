-- ═══ 0202 — the operator's transfer destination is ONE row version, and a deleted       ═══
-- ═══        account's delivery snapshot leaves with the account                          ═══
--
-- ═══ §0 WHICH FINDINGS ═══════════════════════════════════════════════════════════════════════
-- Correct-forward for two of the five findings in `docs/reviews/2026-09-22-post-reset-codex-verdict.md`
-- (Codex REJECT, run 2026-09-22 14:12 KST against base `623a36b`). The other three are routed to
-- `be/0201-strand-fixes` and are not touched here.
--
--   · **Finding 3 (high) — 0194:596-602, a torn transfer destination.** `ops_bank_account` is
--     `VOLATILE`, decrypts through `_bank_account_plain(p_runner)` in one statement, and reads
--     bank / holder / verified_at / updated_at in another. **A `VOLATILE` plpgsql function takes a
--     FRESH SNAPSHOT for every statement in its body** — that is the mechanism, and it is what
--     makes the finding true rather than theoretical. So a `set_my_bank_account` that commits
--     between those two statements hands the operator the OLD number beside the NEW bank and
--     holder, on the one screen in this product whose entire purpose is to be copied into a bank
--     transfer. §A collapses both reads into ONE statement.
--
--   · **Finding 4 (high) — 0195:258-263, delivery PII survives account deletion.** 0195 §A stores
--     `{recipient, phone, address1, address2, postal}` on `gear_claims.delivery`, deliberately
--     INDEPENDENT of `addresses` (0195 §0d ⓑ: `addresses` has no recipient name, no phone and no
--     postal code, so it structurally cannot hold a shipment). `delete_my_account_tx` redacts
--     `addresses` and KEEPS `gear_claims` (0115 §B.3, the 전자상거래법 재화공급 record) — so after
--     0195 a claim → deletion leaves all five fields intact and `ops_gear_claims_pending` keeps
--     handing them to an operator. §B redacts the snapshot and keeps the fulfilment record.
--
-- ═══ §0a WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - **It edits NO landed migration.** 0194, 0195, 0191 and 0115 are untouched on disk; everything
--   here is a `create or replace` / `alter constraint` forward from this file, and every function
--   re-declared here **restates its own ACL in this file** (a `create or replace` on an apply
--   where the function is absent is a plain CREATE, and a SECURITY DEFINER born PUBLIC-executable
--   is the worst shape this repo makes — 0116:636).
-- - **`my_bank_account` is NOT changed, and the reason is a fact rather than a judgement.** It has
--   the same two-statement SHAPE, and it is **`STABLE`** — a STABLE function executes every
--   command in its body under the snapshot established for the CALLING query, so its decrypt and
--   its display read see one fixed view of the database and cannot tear. The `VOLATILE` marking on
--   `ops_bank_account` is not decoration either: it must be volatile because it INSERTs the §D
--   journal row. **The volatility marking is therefore the PRECONDITION that makes Finding 3 real,
--   so 233 `0202-A4` pins it** rather than only pinning the statement count it forces.
--   ⚠ Epistemic ladder, because only one rung here is an observation:
--     · 「VOLATILE takes a fresh snapshot per statement, STABLE uses the caller's」 — **READ**, from
--       the PostgreSQL volatility contract. Not observed here; the harness is single-session.
--     · 「`ops_bank_account` is volatile and `my_bank_account` is stable」 — **OBSERVED** on the
--       catalog (`provolatile`), and pinned.
--     · 「the fixed body reads the table exactly once」 — **OBSERVED** in source, comments stripped,
--       and mutation-verified.
-- - **No lock is taken on `bank_accounts`, on purpose.** 0194 §F④ argued this out and the argument
--   still holds: a `for update` / `for share` on a runner's bank row inside an OPS read would
--   block that runner's own `delete_my_bank_account` behind an operator's screen. A single
--   statement gets the atomicity without the block, and `left join bank_codes` makes a row lock
--   illegal on the nullable side anyway. The concurrent-DELETE behaviour 0194 named is unchanged.
-- - **No new client surface on the bank side.** `ops_bank_account`'s signature, column order,
--   column names, refusal vocabulary and unreadable-ciphertext behaviour (`account = NULL`, never
--   a raise, journal row kept) are byte-for-byte what 0194 shipped.
-- - **No enum value, no new gate on deletion.** There is still no `unshipped_gear` token: 0115
--   §B.1 refuses to hold an account deletion hostage to a warehouse, and this file agrees with it.
-- - **`gear_claims.shipped_to` is not touched.** It is still the unused `uuid → addresses` FK that
--   0115:442 reasons about and that 0195 §0d left alone.
--
-- ═══ §0b THE REDACTION MARKER, AND WHY THE WRITER IS NARROW WHILE THE READER IS BROAD ═════════
-- The redacted value is the single jsonb `{"redacted": true}`.
--   · **The CONSTRAINT admits it by EXACT EQUALITY** — `delivery = '{"redacted": true}'::jsonb` —
--     so the redaction cannot smuggle a sixth field in beside itself. It is one value, not a shape.
--   · **Every READER excludes it by `? 'redacted'`** — any payload claiming to be redacted is
--     treated as redacted. The two are equivalent today; the asymmetry is what keeps a future
--     widening of the marker (a timestamp, say) fail-CLOSED on the disclosure side rather than
--     silently re-listing PII because an equality stopped matching.
-- ⚠ `delivery = null` was the other candidate and is rejected: a NULL `delivery` already means
-- 「this claim never carried a destination」 (every row alive today, and the `shipped` rows 141 D16
-- hand-writes). Collapsing 「redacted」 into it would destroy the distinction 0115:455-467 asks for
-- in so many words — a state 「recognisable at a glance in the fulfilment queue instead of looking
-- like a data bug」.
--
-- ═══ §0c WHOSE OBJECTS THIS RE-DECLARES ══════════════════════════════════════════════════════
--   0194 §E `_bank_account_plain(uuid)`     — delegates to the new `_bank_account_plain_enc`
--   0194 §F④ `ops_bank_account(uuid)`        — one capture instead of three reads
--   0195 §C `ops_gear_claims_pending()`      — redacted rows excluded
--   0195 §D `ops_mark_gear_shipped(uuid,text,text)` — `claim_redacted` refusal added
--   0115 §D + 0138 §F + 0190 §B + 0191 §A `delete_my_account_tx(uuid)` — patched from the CATALOG
-- NEW and owned here: `_bank_account_plain_enc(text)`, `_gear_redact_tombstoned_deliveries()`.
--
-- ⚠ **THE NEW HELPER'S NAME IS LOAD-BEARING AND A LATER SESSION MUST NOT 「TIDY」 IT.**
-- `225 0194-S1` pins the ORDER inside `ops_bank_account` by searching the comment-stripped body
-- for `_bank_account_plain` and asserting it sits after `ops_recipients_for` and after
-- `bank_account_access_log`. `_bank_account_plain_enc` carries that substring **and is the
-- decrypt**, so the pin keeps measuring exactly the proposition it was written for. Renaming it to
-- something like `_bank_account_decrypt` turns a true pin red for a false reason.
--
-- ═══ §0d THE CATALOG COPY FOR `delete_my_account_tx` (0191 §0b's rule, inherited whole) ═══════
-- `delete_my_account_tx` has now been rewritten IN PLACE three times — 0138 §F (billing-key
-- revocation enqueue), 0190 §B (the bank retention predicate), 0191 §A (nine refusal details) —
-- each by reading `prosrc` back and patching it. **The FILE (0115) and the DEPLOYED FUNCTION
-- disagree**, so transcribing any file's text here would silently delete three landings with
-- nothing failing. This file takes the same shape and inherits every guard:
--   · the body must exist, or the apply aborts rather than guessing;
--   · 0138 §F's enqueue must be present;
--   · 0190 §B's `paid_payout_id is null` retention predicate must be present;
--   · **0191 §A's nine `using detail` arms must be present, counted — exactly 9**, because a copy
--     taken from a body that had lost them would carry the loss forward under our name;
--   · the insertion anchor must occur **EXACTLY ONCE**, computed by literal string arithmetic
--     (`length(src) - length(replace(src, anchor, ''))`) rather than by a regex, so nothing here
--     depends on escaping parentheses and quotes correctly.
--
-- ═══ §0e THE ONE-TIME REPAIR — a FUNCTION, not an inline DO block, and that is the point ══════
-- `_gear_redact_tombstoned_deliveries()` redacts any claim whose owner is already tombstoned.
-- **It is vacuous in production** — 0195 has never been deployed, so no `delivery` value exists
-- anywhere — and it is kept because it is cheap, correct, and the one thing standing between a
-- staging database that DID run 0195 and a permanent copy of five PII fields.
-- ⚠ It is a NAMED FUNCTION rather than a `do $$ … $$` block for one reason: **a `do` block that
-- touches zero rows at apply time cannot be pinned by anything except prose.** As a function the
-- suite can build the state the repair exists for — a tombstoned owner with a live snapshot — call
-- it, and measure that it redacts that row, leaves a LIVE runner's row byte-identical, and reports
-- 0 on a second call. Removing its `deleted_at is not null` conjunct reddens the control
-- (233 `0202-B4`), which is a mutation a `do` block could not have had.
--
-- ═══ §0f DEPLOY ══════════════════════════════════════════════════════════════════════════════
-- **`supabase db push` AND `supabase functions deploy delete-account`, TOGETHER**, in that order.
-- ⚠ The edge half needs NO SOURCE CHANGE — verified by reading
-- `supabase/functions/delete-account/handler.ts`: its only contact with this slice is
-- `db.rpc("delete_my_account_tx", { p_uid: uid })` at :133, whose signature, return type and
-- refusal vocabulary are all unchanged here. It is redeployed anyway because 0191 §A tied that
-- handler's `detail` contract to THIS function's body, and a function re-declared from the catalog
-- is exactly where a silent divergence between the two halves would appear. Redeploying costs
-- nothing and keeps the pair moving together.
-- No cron, no secrets, no new env.
-- Pins: `supabase/tests/233_bank_read_atomicity_and_delivery_redaction_suite.sql`
--       (0202-A1…A4 · B1…B5 · S1).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A FINDING 3 — the transfer destination comes from ONE row version
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── ①  the decrypt, moved off the table ───────────────────────────────────────────────────────
-- 0194 §E's `_bank_account_plain(p_runner)` READS THE ROW ITSELF, which is precisely why a caller
-- could not hold one row version across the decrypt: asking for the plaintext meant issuing
-- another statement against `bank_accounts`. This helper takes the CIPHERTEXT the caller already
-- has, so the read and the decrypt stop being coupled.
--
-- ⚠ Every property of 0194 §E is preserved verbatim and deliberately:
--   · **NOT `SECURITY DEFINER`.** A definer that returns plaintext is one bad grant away from
--     being a plaintext oracle. This runs with the CALLER's privileges, so the §F definers reach
--     it (they execute as the table owner) while client roles are stopped by the revoke below.
--   · **`service_role` IS NAMED IN THE REVOKE.** `00_shim.sql:132-135` models production by
--     granting EXECUTE on public functions to `service_role` by default, and `0129:105-120`
--     measured that default ACL — so a revoke that lists only anon/authenticated leaves a
--     PostgREST-reachable one-call decrypt oracle with no journal row, which is the exact thing
--     0194 §D exists to make impossible.
--   · **The `exception when others` is deliberate and is not a silent catch.** It converts three
--     genuinely different faults — ciphertext that is not base64, ciphertext written under a key
--     that is gone, a missing key row — into one value, NULL, which BOTH callers turn back into a
--     visible failure (a NULL mask that tells the runner to re-register; a NULL `account` that
--     refuses to hand an operator a partial number). A raw pgcrypto error reaching a client as a
--     stack-shaped string is what must never happen; a half-decrypted number typed into a bank
--     transfer is what must never happen twice as badly.
create or replace function _bank_account_plain_enc(p_enc text) returns text
language plpgsql stable
set search_path = public, extensions, pg_temp
as $$
declare v_key bytea;
begin
  if p_enc is null then return null; end if;
  v_key := _bank_account_key();
  if v_key is null then return null; end if;
  return pgp_sym_decrypt(decode(p_enc, 'base64'), encode(v_key, 'hex'));
exception when others then
  return null;
end $$;
revoke all on function _bank_account_plain_enc(text) from public, anon, authenticated, service_role;

comment on function _bank_account_plain_enc(text) is
  '0202 §A①: 암호문 하나를 평문으로 — 또는 못 읽으면 NULL. definer 아님(평문을 돌려주는 definer 는
잘못된 grant 하나 거리의 평문 오라클이다), service_role 포함 전부 revoke.
0194 §E 의 _bank_account_plain(uuid) 이 **행을 직접 읽기 때문에** 호출자가 한 행 버전을 복호화 너머로
들고 갈 수 없었다 — 평문을 달라는 것이 곧 bank_accounts 에 문장을 하나 더 던지는 일이었다.
이 함수는 호출자가 이미 가진 암호문을 받으므로 읽기와 복호화가 분리된다(Codex Finding 3).
예외를 삼켜 NULL 로 만드는 것은 침묵이 아니다: 두 호출자 모두 NULL 을 보이는 실패로 되돌린다.';

-- ── ②  0194 §E's runner-keyed helper now delegates ────────────────────────────────────────────
-- So there is exactly ONE `pgp_sym_decrypt` in the schema. `my_bank_account` keeps calling this
-- one unchanged — and keeps being correct for the reason §0a gives: it is STABLE, so both of its
-- statements run under the caller's snapshot and cannot tear.
-- ⚠ Declared with the SAME modifiers 0194 §E gave it — `stable`, NOT definer, and the in-body
--   `search_path = public, extensions, pg_temp` that 0194 §0a chose over the house standard
--   (pgcrypto lives in `extensions`). Its ACL is restated here for the absent-function apply path.
create or replace function _bank_account_plain(p_runner uuid) returns text
language plpgsql stable
set search_path = public, extensions, pg_temp
as $$
declare v_enc text;
begin
  select account_enc into v_enc from bank_accounts where runner_id = p_runner;
  return _bank_account_plain_enc(v_enc);
end $$;
revoke all on function _bank_account_plain(uuid) from public, anon, authenticated, service_role;

comment on function _bank_account_plain(uuid) is
  '0194 §E + [0202 §A②]: 계좌번호 평문 또는 NULL(못 읽음). definer 아님 — 호출자 권한으로 돈다.
[0202] 복호화 자체는 _bank_account_plain_enc(text) 하나로 모았다(스키마 전체에 pgp_sym_decrypt 는
한 군데뿐이다). 이 함수는 여전히 러너 uuid 로 행을 읽어 넘기며, my_bank_account 가 쓴다 —
my_bank_account 는 STABLE 이라 본문의 모든 문장이 호출 질의의 스냅샷 하나로 돌고, 따라서 찢어지지
않는다(0202 §0a 의 사다리). NULL 은 삼킨 실패가 아니다.';

-- ── ③  ops_bank_account — ONE statement holds the whole answer ────────────────────────────────
-- 🔴 THE FIX IS THE SINGLE `select … into`. Everything else in this body is 0194 §F④ verbatim, and
-- the order 225 `0194-S1` pins is unchanged: **ops gate → journal → decrypt**.
--
-- What the old body did, counted: `select exists(… from bank_accounts …)` for the journal · a
-- `_bank_account_plain(p_runner)` call that read the row again · a `return query … from
-- bank_accounts` that read it a third time. Three statements, three snapshots, because this
-- function is VOLATILE. The middle and the last are the pair Codex named.
-- What it does now: ONE `select … into` captures bank, label, holder, **ciphertext**, verified_at
-- and updated_at together; `FOUND` off that same statement is the journal's `found`; and the
-- decrypt runs on the captured ciphertext. Every field the operator sees comes from one row
-- version by construction, with no lock and therefore no block on the runner's own deletion.
create or replace function ops_bank_account(p_runner uuid)
returns table (bank text, bank_label text, holder text, account text,
               verified_at timestamptz, updated_at timestamptz)
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  v_uid      uuid := auth.uid();
  v_plain    text;
  v_has      boolean;
  v_bank     text;
  v_label    text;
  v_holder   text;
  v_enc      text;
  v_verified timestamptz;
  v_updated  timestamptz;
begin
  -- ① PARTY GATE — ops membership, ahead of EVERY read. The `p_runner is null` check sits after
  --    it deliberately: a stranger passing a null must learn `not_ops`, not `no_runner`, because
  --    the difference between those two answers is itself information about the gate.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
    then raise exception 'not_ops'; end if;
  if p_runner is null then raise exception 'no_runner'; end if;

  -- ② THE CAPTURE — the whole answer, one statement, one snapshot. [0202 §A③]
  --    `account_enc` rides along instead of being fetched separately; that single change is the
  --    difference between an operator reading one row version and reading two.
  select b.bank, c.label, b.holder, b.account_enc, b.verified_at, b.updated_at
    into v_bank, v_label, v_holder, v_enc, v_verified, v_updated
    from bank_accounts b
    left join bank_codes c on c.code = b.bank
   where b.runner_id = p_runner;
  v_has := found;

  -- ③ the journal, BEFORE the answer is assembled and before anything is decrypted. A row exists
  --    for every gated call, including the ones that find nothing — probing for existence is
  --    access. `found` off the capture above is the same fact the old `select exists` produced,
  --    taken from the statement that is already reading the row rather than from a second one.
  insert into bank_account_access_log (ops_profile_id, runner_id, found)
  values (v_uid, p_runner, v_has);

  if v_has is not true then return; end if;

  -- ④ the decrypt, on the CAPTURED ciphertext. An unreadable row comes back with `account` NULL —
  --    never a partial number, and never a raise.
  -- 🔴 IT MUST NOT RAISE, AND THE REASON IS THE JOURNAL. PostgREST wraps each request in a
  --    transaction, so a raise here would discard its own journal row — and the one access an
  --    operator should never be able to make quietly would become the only one leaving no trace at
  --    all. Worse, it is a usable probe: repeat the call and you learn the row EXISTS, with zero
  --    audit. The failure is REPORTED IN THE ROW instead: the transaction commits, the journal
  --    keeps its line, and the operator sees an ABSENT number rather than a partial one. Zero rows
  --    still means 「no account on file」, so the two outcomes stay distinguishable.
  -- ⚠ A CONCURRENT DELETE is now invisible to this function rather than being a second outcome —
  --    the row either was there when the capture ran or it was not, and both answers are complete.
  --    That is a strict improvement on 0194 §F④'s note, which had to name the gap instead.
  v_plain := _bank_account_plain_enc(v_enc);

  return query select v_bank, v_label, v_holder, v_plain, v_verified, v_updated;
end $$;
revoke execute on function ops_bank_account(uuid) from public, anon;
grant  execute on function ops_bank_account(uuid) to authenticated;

comment on function ops_bank_account(uuid) is
  '0194 §F④ + [0202 §A③]: 운영자가 이체하려고 읽는 러너의 실계좌번호. 게이트는 0186 의 것과 같다
(ops_recipients_for(''payout_due'')) — 지급을 기록하는 사람이 계좌를 읽는 사람이다.
게이트를 통과한 호출 한 번 = bank_account_access_log 한 행, 행을 못 찾았어도(found=false) 남는다.
복호화 실패는 **예외가 아니라 account = NULL 로** 보고한다 — 예외를 던지면 같은 트랜잭션의 장부 행이
함께 롤백돼, 가장 감사돼야 할 호출이 흔적을 안 남기는 유일한 호출이 된다.
🔴 [0202] 이 함수는 VOLATILE 이고(장부 INSERT 때문에 그래야 한다), plpgsql 의 VOLATILE 함수는
**본문의 문장마다 새 스냅샷을 잡는다** — 그래서 예전 본문은 은행·예금주를 한 문장에서, 번호를 다른
문장에서 읽었고 그 사이에 set_my_bank_account 가 커밋되면 **옛 번호 + 새 은행**이 이체창에 떴다
(Codex Finding 3). 이제 은행·라벨·예금주·암호문·시각을 **한 문장**에 담고 그 암호문을 복호화하므로
운영자가 보는 모든 칸이 같은 행 버전이다. 잠그지는 않는다 — ops 읽기가 러너 본인의 계좌 삭제를
화면 뒤에서 막는 것이 더 나쁜 거래다(0194 §F④ 의 판단, 그대로).
⚠ authenticated 에 EXECUTE 가 있는 것은 PostgREST 를 통해 운영자가 부르기 때문이고, 그래서 이 함수의
유일한 방어는 본문 첫 팔의 ops 게이트다 — 그 팔을 지우면 모든 러너의 계좌가 모두에게 열린다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B FINDING 4 — the delivery snapshot leaves with the account
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── ①  the shape belt learns the redaction marker ─────────────────────────────────────────────
-- 0195 §A's constraint admits NULL or a postable five-field object. The redaction is neither, so
-- the belt is widened by EXACTLY one admitted value — see §0b for why equality here and `?` in
-- every reader. The five-field arm is byte-for-byte 0195's; nothing about a real address changes.
alter table gear_claims drop constraint if exists gear_claims_delivery_shape;
alter table gear_claims add constraint gear_claims_delivery_shape check (
  delivery is null
  or delivery = '{"redacted": true}'::jsonb
  or (
        jsonb_typeof(delivery) = 'object'
    and coalesce(btrim(delivery->>'recipient'), '') <> ''
    and coalesce(btrim(delivery->>'phone'),     '') <> ''
    and coalesce(btrim(delivery->>'address1'),  '') <> ''
    and coalesce(delivery->>'postal',           '') ~ '^[0-9]{5}$'
  )
);
comment on constraint gear_claims_delivery_shape on gear_claims is
  '0195 §A + [0202 §B①]: delivery 가 있다면 **부칠 수 있는 주소**이거나 **정확히
''{"redacted": true}''** 여야 한다. NULL 은 여전히 허용(오늘의 모든 행, 141 D16 이 손으로 만드는
shipped 행). 표식을 등호로 받는 것은 일부러다 — 모양이 아니라 값 하나라서, 지움 표식 옆에 여섯 번째
칸이 끼어들 수 없다. 읽는 쪽은 반대로 넓다(delivery ? ''redacted''): 나중에 표식이 넓어져도 공개 쪽이
닫힌 채로 틀린다. 「claimed 면 delivery 가 있어야 한다」 규칙은 0195 가 거부한 그대로 없다.';

-- ── ②  delete_my_account_tx — the snapshot is redacted with the addresses ─────────────────────
-- Patched from the CATALOG, never from a file (§0d). The inserted statement sits immediately after
-- 0115's `update addresses` because it is the same act on the other address store — and because
-- 0115:429-448's own OPS CONSEQUENCE paragraph, which sits directly below the anchor, is the
-- paragraph this slice makes true again.
do $mig$
declare
  v_src  text;
  v_new  text;
  v_a    text;
  v_repl text;
  v_n    int;
begin
  select prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then
    raise exception '0202 §B②: delete_my_account_tx not found — refusing to guess';
  end if;

  -- Inherited landings this copy must carry forward. If any is absent, something re-created the
  -- function from a FILE and the loss is already there — stop loudly rather than carry it forward
  -- under our name.
  if position($e$perform enqueue_billing_key_revocation(p_uid, 'account_deleted');$e$ in v_src) = 0 then
    raise exception '0202 §B②: 0138 §F''s revocation enqueue is not in the live body — do not copy this, find out what removed it';
  end if;
  if position($e$where runner_id = p_uid and paid_payout_id is null$e$ in v_src) = 0 then
    raise exception '0202 §B②: 0190 §B''s paid-marker retention predicate is not in the live body — do not copy this, find out what removed it';
  end if;
  -- 0191 §A put a detail on NINE refusals. Counted, not merely detected: a body that had lost
  -- three of them would satisfy a presence check and the copy would ship the loss.
  v_a := $e$using detail = coalesce(v_block_id::text, '')$e$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 9 then
    raise exception '0202 §B②: 0191 §A''s detail arms occur % time(s) in the live body, expected exactly 9 — patch by hand', v_n;
  end if;

  -- ── the anchor: the tail of 0115's `update addresses` redaction ─────────────────────────────
  -- `is_default` appears in exactly one statement in this body, which is what makes this two-line
  -- literal unique without depending on nine lines of whitespace. Asserted below regardless.
  v_a := $a$    is_default    = false
  where owner_id = p_uid;$a$;

  v_repl := $a$    is_default    = false
  where owner_id = p_uid;

  -- 🔴 [0202 §B②] gear_claims.delivery — THE OTHER ADDRESS STORE, and it is not an FK.
  -- 0195 §A froze a shipping SNAPSHOT on the claim row itself — {recipient, phone, address1,
  -- address2, postal} — precisely because `addresses` cannot hold one (0195 §0d ⓑ: no recipient
  -- name, no phone, no postal code anywhere in it). So the redaction directly above, which is the
  -- one 0115:434-467 documents, does not reach these five fields at all: the claim row is KEPT
  -- (0115 §B.3, the 전자상거래법 재화공급 record) and used to keep a full name, a mobile number and
  -- a street address of a person who had asked to be deleted, still being handed to an operator by
  -- `ops_gear_claims_pending`. That is Codex Finding 4 (2026-09-22).
  -- The FULFILMENT RECORD survives untouched — status, claimed_at, item, milestone, carrier,
  -- tracking, dispatched_at — because that is what the 재화공급 record actually is. What leaves is
  -- the destination, and it leaves as a NAMED state rather than as a NULL, so the fulfilment queue
  -- can tell 「this was redacted」 from 「this never had an address」 (0202 §0b).
  update gear_claims set delivery = '{"redacted": true}'::jsonb
   where profile_id = p_uid and delivery is not null;$a$;

  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0202 §B②: the addresses-redaction anchor occurs % time(s) in delete_my_account_tx, expected exactly 1 — patch by hand', v_n;
  end if;

  v_new := replace(v_src, v_a, v_repl);
  if v_new = v_src then raise exception '0202 §B②: patch did not apply'; end if;

  execute format(
    'create or replace function delete_my_account_tx(p_uid uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L',
    v_new);
end $mig$;

-- 0115:645-648 / 0138 §F / 0190 §B / 0191 §A's ACL restated — a `create or replace` on an
-- absent-function path is a plain CREATE, and a SECURITY DEFINER born PUBLIC-executable is the
-- worst shape this repo makes.
revoke execute on function delete_my_account_tx(uuid) from public, anon, authenticated;
grant  execute on function delete_my_account_tx(uuid) to service_role;

comment on function delete_my_account_tx(uuid) is
  '0115 §D + [0138 §F] + [0190 §B] + [0191 §A] + [0202 §B②]: 탈퇴 트랜잭션.
[0191 §A] 열두 개 상태 게이트 중 아홉 개가 막는 행의 id 를 Postgres errdetail 로 함께 보낸다 —
메시지는 여전히 맨 토큰이다(클라이언트가 그 문자열로 매칭한다).
[0202 §B②] ③ 익명화 단계가 **gear_claims.delivery** 도 지운다. 0195 §A 의 배송지 스냅샷은
addresses 와 완전히 별개의 열이라(0195 §0d ⓑ — addresses 에는 받는사람도 전화도 우편번호도 없다)
0115:434-467 이 기술한 주소 익명화가 닿지 않았고, 그래서 탈퇴한 사람의 이름·전화·주소가 교환권 행에
남아 ops_gear_claims_pending 으로 계속 나갔다(Codex Finding 4). 이행 기록 자체 — status·claimed_at·
품목·마일스톤·택배사·송장·발송시각 — 는 그대로 남는다. 그게 재화공급 기록이기 때문이다.
지워진 자리는 NULL 이 아니라 ''{"redacted": true}'' 라서, 「지웠다」와 「원래 주소가 없었다」가
큐에서 구분된다.';

-- ── ③  ops_gear_claims_pending — a redacted claim is not pending, it is unshippable ───────────
-- 0195 §C's predicate is kept EXACTLY as it was — `status = 'claimed'`, a POSITIVE match on one
-- value so an enum value added later cannot fall into this list by default — and gains one
-- conjunct. Everything else, including the deliberate exception to 0186 §B's 「do not join money to
-- destinations」 rule (here the address IS the act), is 0195's and unchanged.
-- ⚠ The exclusion is `? 'redacted'`, not equality to the marker: on the DISCLOSURE side, anything
--   claiming to be redacted must be treated as redacted (§0b).
create or replace function ops_gear_claims_pending()
returns table (
  claim_id    uuid,
  profile_id  uuid,
  item        text,
  milestone   int,
  claimed_at  timestamptz,
  recipient   text,
  phone       text,
  address1    text,
  address2    text,
  postal      text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';   -- 0195 §0f
  v_uid uuid := auth.uid();
begin
  -- ① PARTY GATE — ops membership, before a single row is read.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
    select g.id, g.profile_id, g.item, g.milestone, g.claimed_at,
           g.delivery->>'recipient', g.delivery->>'phone',
           g.delivery->>'address1',  g.delivery->>'address2', g.delivery->>'postal'
      from gear_claims g
     where g.status = 'claimed'
       and coalesce(g.delivery ? 'redacted', false) is not true
     order by g.claimed_at, g.id;
end $$;
revoke execute on function ops_gear_claims_pending() from public, anon;
grant  execute on function ops_gear_claims_pending() to authenticated;

comment on function ops_gear_claims_pending is
  '0195 §C + [0202 §B③]: 수령 신청은 됐는데 아직 안 보낸 교환권 — 운영자가 상자를 부치려고 읽는 목록.
ops 전용(0084 §E 로스터, 클래스는 payout_due — 이유는 0195 §0f). 술어는 status = ''claimed'' 이고
**긍정 매칭**이다: claimable 행에는 아직 주소가 없고 shipped 행은 이미 떠났으며, 나중에 enum 값이
생겨도 기본값으로 이 목록에 들어오지 않는다.
[0202] **지워진 배송지는 목록에서 빠진다.** 탈퇴한 사람의 교환권은 부칠 곳이 없고, 0115:455-467 이
이미 적어 둔 운영 답도 「주소를 쫓지 말고 신청을 취소하라」이다 — 목록에 남기는 것은 아무도 실행할 수
없는 일을 매일 보여 주는 것이다. 조건은 등호가 아니라 delivery ? ''redacted'' 로, 공개 쪽은 넓게
닫는다(0202 §0b). 226 0195-P1·P3, 233 0202-B2 가 핀.';

-- ── ④  ops_mark_gear_shipped — a redacted claim refuses by name ───────────────────────────────
-- 0195 §D verbatim plus ONE refusal. `claim_redacted` is a RAISE and not a flat field, for the
-- same reason `already_shipped` is: an operator typing a tracking number against a claim with
-- nowhere to send it has made a mistake, and a silent success would record a dispatch that cannot
-- have happened.
-- ⚠ The new gate sits AFTER `already_shipped` and AFTER `not_claimed`, which is not arbitrary. A
--   `shipped` row left before the account did (0115's own sentence) and must keep answering
--   `already_shipped`; a `claimable` row must keep answering `not_claimed`. `claim_redacted` is
--   the answer for the one remaining state — a `claimed` row whose destination is gone.
create or replace function ops_mark_gear_shipped(
  p_claim_id uuid, p_carrier text, p_tracking text
) returns table (
  claim_id      uuid,
  status        text,
  carrier       text,
  tracking      text,
  dispatched_at timestamptz
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';   -- 0195 §0f
  v_uid      uuid := auth.uid();
  v_status   text;
  v_redacted boolean;
  v_carrier  text;
  v_tracking text;
  v_n        int;
begin
  -- ① PARTY GATE — ops membership, ahead of the lock and every state gate.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  if p_claim_id is null then raise exception 'claim_not_found'; end if;
  v_carrier  := btrim(coalesce(p_carrier,  ''));
  v_tracking := btrim(coalesce(p_tracking, ''));
  if v_carrier  = '' then raise exception 'bad_carrier';  end if;
  if v_tracking = '' then raise exception 'bad_tracking'; end if;

  -- ② the lock, then the state gates on what the lock held. The redaction flag is read in the
  --    SAME statement as the status — one locked row version, no second look.
  select g.status::text, coalesce(g.delivery ? 'redacted', false)
    into v_status, v_redacted
    from gear_claims g where g.id = p_claim_id for update;
  if not found then raise exception 'claim_not_found'; end if;
  if v_status = 'shipped' then raise exception 'already_shipped'; end if;
  if v_status is distinct from 'claimed' then raise exception 'not_claimed'; end if;
  -- [0202 §B④] `is not false` rather than a bare `if`: a NULL predicate must REFUSE, never
  -- disappear (the NULL-collapse law). There is nowhere to send this box.
  if v_redacted is not false then raise exception 'claim_redacted'; end if;

  update gear_claims g
     set status            = 'shipped',
         delivery_carrier  = v_carrier,
         delivery_tracking = v_tracking,
         dispatched_at     = now()
   where g.id = p_claim_id and g.status = 'claimed';
  get diagnostics v_n = row_count;
  if v_n is distinct from 1 then raise exception 'ship_race'; end if;

  return query
    select g.id, g.status::text, g.delivery_carrier, g.delivery_tracking, g.dispatched_at
      from gear_claims g where g.id = p_claim_id;
end $$;
revoke execute on function ops_mark_gear_shipped(uuid, text, text) from public, anon;
grant  execute on function ops_mark_gear_shipped(uuid, text, text) to authenticated;

comment on function ops_mark_gear_shipped is
  '0195 §D + [0202 §B④]: 운영자가 부친 상자의 택배사·송장번호를 적고 claimed → shipped 로 옮긴다.
ops 전용. enum 에 이미 있던 값이라 새로 만든 값은 없다(0001:21). 두 번째 호출은 already_shipped 로
거절한다 — §B 의 already_claimed 가 플랫 필드인 것과 일부러 다르다: 러너의 재탭은 재시도이지만
운영자가 송장을 덮어쓰는 것은 실제로 보낸 번호를 지우는 실수다. shipped 는 「발송」이고 「도착」이 아니다.
[0202] **claim_redacted** — 배송지가 지워진 신청(주인이 탈퇴했다)은 발송 처리할 수 없다. 보낼 곳이
없는데 송장을 적으면 일어나지 않은 발송이 기록으로 남는다. 순서는 already_shipped · not_claimed
다음이다: 이미 떠난 상자는 계정보다 먼저 떠났고(0115), 아직 신청 전인 행은 그 사실이 먼저다.
226 0195-P2·P3, 233 0202-B3 이 핀.';

-- ── ⑤  the one-time repair (§0e) ──────────────────────────────────────────────────────────────
-- A claim whose owner is ALREADY tombstoned still holds its snapshot, because the redaction above
-- only runs inside a future `delete_my_account_tx`. `profiles.deleted_at` is the tombstone and it
-- has exactly one writer in the whole repo — 0115:424, inside that same function — so
-- `deleted_at is not null` is not a heuristic for 「deleted」, it is the definition.
-- ⚠ NOT a definer: it updates `gear_claims` with the caller's own privileges, so it runs for the
--   migration and the harness (both owner) and for nobody else — every client role is revoked
--   below. A definer that mass-rewrites a table is a bigger target than this needs to be.
create or replace function _gear_redact_tombstoned_deliveries() returns int
language plpgsql volatile
set search_path = public, pg_temp
as $$
declare v_n int;
begin
  update gear_claims g
     set delivery = '{"redacted": true}'::jsonb
    from profiles p
   where p.id = g.profile_id
     and p.deleted_at is not null
     and g.delivery is not null
     and coalesce(g.delivery ? 'redacted', false) is not true;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function _gear_redact_tombstoned_deliveries() from public, anon, authenticated, service_role;

comment on function _gear_redact_tombstoned_deliveries() is
  '0202 §B⑤: 이미 탈퇴한 사람의 교환권에 남아 있는 배송지 스냅샷을 지우고 지운 행 수를 돌려준다.
멱등 — 두 번째 호출은 0 이다. 운영 DB 에서는 **공집합**이다(0195 가 배포된 적이 없어 delivery 값이
아직 존재하지 않는다). 그래도 남기는 이유는 싸고 옳기 때문이고, 0195 를 적용한 스테이징이 다섯 칸을
영구히 들고 있는 것과 이 함수 사이에 다른 것이 없기 때문이다. deleted_at 은 저장소 전체에서 쓰는 곳이
0115:424 하나뿐이라(= delete_my_account_tx 안) 「탈퇴했다」의 추정이 아니라 정의다.
definer 아님 — 호출자 권한으로 돌고 클라이언트 롤은 전부 revoke 되어 있다.
do 블록이 아니라 이름 있는 함수인 이유는 0202 §0e: 적용 시점에 0 행을 건드리는 블록은 산문 말고는
아무것도 핀할 수 없다. 233 0202-B4 가 핀(살아 있는 러너의 행은 대조).';

do $$
declare v_n int;
begin
  v_n := _gear_redact_tombstoned_deliveries();
  raise notice '0202 §B⑤: redacted % already-tombstoned gear delivery snapshot(s)', v_n;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C VERIFY — this apply fails rather than ships a half-built fix
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ⚠ These arms and `233_…_suite.sql` are DIFFERENT ARTIFACTS and neither is evidence for the
--   other: this aborts a production apply that lands wrong, the suite reddens when a LATER file
--   undoes something. Per 0131-G4's lesson, a property checked only at apply is protected exactly
--   until someone recreates the function — so 233 `0202-S1` restates the shape arms.
-- ⚠ Everything matched against `prosrc` is matched with COMMENTS STRIPPED. `prosrc` is source plus
--   our own prose, and the blocks above quote the very strings these arms look for — an
--   un-stripped match would be satisfied by the paragraph EXPLAINING the guard, and the better the
--   explanation the more certainly green (CLAUDE.md, the comment-matching law).
do $verify$
declare
  v_bad text := '';
  v_src text;
  v_oid oid;
  v_n   int;
  fn    text;
begin
  -- ── §A: the six bank-side functions keep 0194's deployed shape ────────────────────────────
  foreach fn in array array['my_bank_account()', 'set_my_bank_account(text,text,text)',
                            'delete_my_bank_account()', 'ops_bank_account(uuid)'] loop
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

  -- the two (now three) private helpers stay private and stay INVOKER
  foreach fn in array array['_bank_account_key()', '_bank_account_plain(uuid)',
                            '_bank_account_plain_enc(text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
    or has_function_privilege('service_role', v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' ' || fn || ':CLIENT-EXECUTABLE'; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not false
      then v_bad := v_bad || ' ' || fn || ':IS-DEFINER(must not be)'; end if;
  end loop;

  -- 🔴 THE VOLATILITY MARKINGS ARE THE PRECONDITION OF FINDING 3, so they are checked, not
  --    assumed. `ops_bank_account` must be VOLATILE (it INSERTs the journal row, and a STABLE
  --    function cannot) — which is exactly why its statements each take a fresh snapshot and why
  --    the single capture is necessary. `my_bank_account` must be STABLE — that, and nothing else,
  --    is why it is left alone.
  if (select provolatile from pg_proc where oid = to_regprocedure('ops_bank_account(uuid)'))
     is distinct from 'v'
    then v_bad := v_bad || ' ops_bank_account:NOT-VOLATILE(0202 §0a reasons from this)'; end if;
  if (select provolatile from pg_proc where oid = to_regprocedure('my_bank_account()'))
     is distinct from 's'
    then v_bad := v_bad || ' my_bank_account:NOT-STABLE(0202 §0a left it alone BECAUSE it is)'; end if;

  -- 🔴 THE FIX ITSELF: `ops_bank_account` reads `bank_accounts` in EXACTLY ONE statement, and the
  --    decrypt helper it calls reads the table NOT AT ALL. Counted by literal string arithmetic so
  --    nothing depends on escaping a regex correctly.
  v_oid := to_regprocedure('ops_bank_account(uuid)');
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_bank_account)';
  else
    v_n := (length(v_src) - length(replace(v_src, 'from bank_accounts', ''))) / length('from bank_accounts');
    if v_n is distinct from 1
      then v_bad := v_bad || ' ops_bank_account:TABLE-READ-COUNT=' || v_n || '(must be 1)'; end if;
    if (position('_bank_account_plain_enc(v_enc)' in v_src) > 0) is not true
      then v_bad := v_bad || ' ops_bank_account:DECRYPT-NOT-FROM-THE-CAPTURED-CIPHERTEXT'; end if;
    -- the order 225 0194-S1 pins, restated here so the apply refuses it too
    if (position('ops_recipients_for' in v_src) > 0
        and position('ops_recipients_for' in v_src) < position('bank_account_access_log' in v_src)
        and position('bank_account_access_log' in v_src) < position('_bank_account_plain' in v_src))
       is not true
      then v_bad := v_bad || ' ops_bank_account:ORDER(gate → journal → decrypt)'; end if;
    if (select length(prosrc) > length(v_src) from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ops_bank_account:COMMENT-STRIP-DID-NOTHING'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('_bank_account_plain_enc(text)');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(_bank_account_plain_enc)';
  else
    if (position('bank_accounts' in v_src) > 0) is not false
      then v_bad := v_bad || ' _bank_account_plain_enc:READS-THE-TABLE(the whole point is that it does not)'; end if;
    if (position('pgp_sym_decrypt' in v_src) > 0) is not true
      then v_bad := v_bad || ' _bank_account_plain_enc:NO-DECRYPT'; end if;
  end if;

  -- ── §B: the gear side ─────────────────────────────────────────────────────────────────────
  if (select exists (select 1 from pg_constraint
                      where conrelid = 'gear_claims'::regclass
                        and conname = 'gear_claims_delivery_shape')) is not true
    then v_bad := v_bad || ' DELIVERY-SHAPE-CONSTRAINT-MISSING'; end if;

  foreach fn in array array['ops_gear_claims_pending()',
                            'ops_mark_gear_shipped(uuid,text,text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':NO-INBODY-SEARCH-PATH'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',   v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':PUBLIC-OR-ANON-EXECUTE'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':AUTHENTICATED-MISSING'; end if;
    -- 0195 §F's own arms, restated: the ops gate is in the body and precedes the row read
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')';
    else
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
        then v_bad := v_bad || ' ' || fn || ':NO-OPS-ROSTER'; end if;
      if (position('raise exception ''not_ops''' in v_src) > 0
          and position('raise exception ''not_ops''' in v_src) < position('from gear_claims' in v_src))
         is not true
        then v_bad := v_bad || ' ' || fn || ':OPS-GATE-AFTER-THE-ROW-READ'; end if;
      if (position('redacted' in v_src) > 0) is not true
        then v_bad := v_bad || ' ' || fn || ':NO-REDACTION-ARM'; end if;
    end if;
  end loop;

  -- `delete_my_account_tx`: the patch landed, and the three inherited landings survived the copy
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx)';
  else
    if (position($q$update gear_claims set delivery = '{"redacted": true}'::jsonb$q$ in v_src) > 0)
       is not true
      then v_bad := v_bad || ' delete_my_account_tx:NO-DELIVERY-REDACTION'; end if;
    if (position($q$enqueue_billing_key_revocation(p_uid, 'account_deleted')$q$ in v_src) > 0)
       is not true
      then v_bad := v_bad || ' delete_my_account_tx:0138-ENQUEUE-LOST-IN-THE-COPY'; end if;
    if (position($q$where runner_id = p_uid and paid_payout_id is null$q$ in v_src) > 0)
       is not true
      then v_bad := v_bad || ' delete_my_account_tx:0190-RETENTION-LOST-IN-THE-COPY'; end if;
    v_n := (length(v_src) - length(replace(v_src, $q$using detail = coalesce(v_block_id::text, '')$q$, '')))
           / length($q$using detail = coalesce(v_block_id::text, '')$q$);
    if v_n is distinct from 9
      then v_bad := v_bad || ' delete_my_account_tx:0191-DETAIL-ARMS=' || v_n || '(must be 9)'; end if;
    -- 🔴 the redaction must be INSIDE the tombstone stage, not after the deletes — asserted by
    --    position against the addresses redaction it rides beside.
    if (position('update addresses set' in v_src) > 0
        and position('update addresses set' in v_src)
            < position('update gear_claims set delivery' in v_src)) is not true
      then v_bad := v_bad || ' delete_my_account_tx:REDACTION-NOT-IN-THE-ANONYMISE-STAGE'; end if;
  end if;
  if (select prosecdef from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       and ns.nspname = 'public' where p.proname = 'delete_my_account_tx') is not true
    then v_bad := v_bad || ' delete_my_account_tx:NOT-SECURITY-DEFINER'; end if;
  if (select 'search_path=public, pg_temp' = any(p.proconfig) from pg_proc p
       join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
      where p.proname = 'delete_my_account_tx') is not true
    then v_bad := v_bad || ' delete_my_account_tx:NO-IN-BODY-SEARCH-PATH'; end if;
  if has_function_privilege('anon', 'delete_my_account_tx(uuid)', 'EXECUTE') is not false
  or has_function_privilege('authenticated', 'delete_my_account_tx(uuid)', 'EXECUTE') is not false
    then v_bad := v_bad || ' delete_my_account_tx:CLIENT-EXECUTABLE'; end if;

  -- the repair helper
  v_oid := to_regprocedure('_gear_redact_tombstoned_deliveries()');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_gear_redact_tombstoned_deliveries)';
  else
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
    or has_function_privilege('service_role', v_oid, 'EXECUTE') is not false
      then v_bad := v_bad || ' _gear_redact_tombstoned_deliveries:CLIENT-EXECUTABLE'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_gear_redact_tombstoned_deliveries)';
    elsif (position('deleted_at is not null' in v_src) > 0) is not true
      then v_bad := v_bad || ' _gear_redact_tombstoned_deliveries:NO-TOMBSTONE-PREDICATE(it would redact LIVE runners)'; end if;
  end if;

  -- and no live snapshot is left behind a tombstone after this apply
  select count(*)::int into v_n from gear_claims g join profiles p on p.id = g.profile_id
   where p.deleted_at is not null and g.delivery is not null
     and coalesce(g.delivery ? 'redacted', false) is not true;
  if v_n is distinct from 0
    then v_bad := v_bad || ' TOMBSTONED-DELIVERY-SURVIVED=' || v_n; end if;

  if v_bad <> '' then
    raise exception '0202 §C VERIFY:%', v_bad
      using hint = 'Do not weaken this block. Each arm is a property 233 0202-S1 restates.';
  end if;
  raise notice '0202 §C VERIFY ok — one row version for the operator, no destination behind a tombstone';
end
$verify$;
