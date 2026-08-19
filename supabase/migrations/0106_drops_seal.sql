-- ═══ 0106: the drops seal — a reward drop is a SERVER fact, from mint to open ═══
--
-- Sibling of 0061 (`runners` INSERT seal), 0087 (`runs` INSERT seal) and 0105 (`bookings`
-- INSERT party guard): one more 0002 policy that asked WHO and never WHAT. This file's one-line
-- summary is: **`drops self open` (0002:131) is `for update using (runner_id = auth.uid())`
-- with no WITH CHECK, no trigger, and no column list — and `open-drop` (service_role) reads
-- `drop.contents` off that same row and PAYS it.**
--
-- ═══ §0 THE HOLE, MEASURED (local harness DB at 0105, rolled back — never production) ═══
--   set local role authenticated;   -- request.jwt.claim.sub = the runner
--   update drops set contents = '{"miles":9999999}', opened_at = null where id = <my opened drop>;
--   → UPDATE 1.  Re-read as postgres: contents = {"miles": 9999999}, opened_at = NULL.
-- The runner then calls `open-drop` again. Its CAS (`.is('opened_at', null)`) is satisfied —
-- the runner just re-armed it — and the mini arm does
--     `miles_ledger.insert({ delta: c.miles, reason: 'drop' })`  with c = drop.contents
-- so 9,999,999 하이 포인트 land in the ledger. `card` and `gear` are the same class one line
-- down (a forged `gear` string becomes a `gear_claims` row with `status = 'claimable'`, i.e. a
-- shipping obligation typed by its beneficiary). Every drop the runner has ever opened is
-- re-openable, and every one is worth whatever the runner writes.
--
-- Production state read before writing this (2026-08-19, `db query --linked`, read-only):
-- 0 rows in `drops`, 0 in `gear_claims`; both tables carry the four 0002 policies AND the
-- Supabase default `grant all` to anon+authenticated — INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/
-- TRIGGER. So the CHECK constraints below validate against an empty table and there is no
-- backfill question. `gear_claims` has the same shape (`gear self claim`, 0002:134) and the same
-- absence of any client caller.
--
-- ═══ §0b WHAT THIS FILE DOES ═══
--   §1  the revocation   — no client role INSERTs, UPDATEs, DELETEs (or truncates…) `drops` or
--                          `gear_claims`. The two write policies are dropped, not narrowed.
--   §2  the shape        — CHECK constraints: `contents` is a whitelisted object whose `miles` is
--                          an integer 0..5000; `pick_choice` ∈ {boost,miles,gear} and only on an
--                          opened row; `gear_claims.item` is short text.
--   §3  _guard_drop_cols — BEFORE INSERT/UPDATE/DELETE, INVOKER: the client branch refuses every
--                          op (belt behind §1); for EVERY role but the table owner / a superuser,
--                          `contents`/`kind`/`runner_id`/`run_count_at`/`created_at` are frozen
--                          after insert, `opened_at` once set never moves (never back to null,
--                          never re-stamped), and `pick_choice` freezes with it.
--   §4  _guard_gear_claim_cols — same shape for `gear_claims`: client refused outright; identity
--                          columns (`profile_id`/`side`/`item`/`milestone`/`created_at`) frozen
--                          for everyone but the owner. `status`/`shipped_to`/`claimed_at` remain
--                          service_role-writable for the ops fulfilment path that does not exist
--                          yet.
--
-- ═══ §0c WHAT THIS FILE DOES **NOT** DO ═══
-- - **No `drop_set_pick_choice` RPC.** The brief allowed one if the client needed to write
--   `pick_choice`. It does not: `grep -n "drops\|gear_claims" app/src/lib/api.ts` → ONE select on
--   each (`fetchDrops` :2584, `fetchGearClaims` :2613) and `openDrop` (:2593), which sends
--   `pick_choice` in the `open-drop` request BODY. `rewards.tsx:144/155` calls `openDrop(d, k)` /
--   `openDrop(d)`. No client write on either table exists to preserve, so none is exposed.
--   The app is unaffected by §1 — verified before the revoke, because a revoke that kills a shipped
--   screen is worse than the hole.
-- - It does not touch `open-drop`. Its CAS UPDATE (`opened_at = now(), pick_choice = ?` where
--   `id = ? and opened_at is null`) is exactly what §3 permits service_role to do, once. §3 makes
--   the CAS a DB property rather than an edge-function habit: a second stamp on an opened row now
--   RAISES (`drop_already_opened`) instead of relying on the `.is('opened_at', null)` predicate.
-- - It does not touch `settle_run_tx` (the minter, 0083 §6). It runs as the table owner and its
--   two shapes — `{"miles":N[,"card":…][,"gear":…]}` for `mini`, `{"options":[…]}` for `pick` —
--   are what §2 whitelists. Suite 10 D1/D2 keep pinning that it still mints.
-- - It adds no alert or notification: every refusal is a synchronous raise to the writer.
--
-- ═══ §0d WHOSE TEXT EACH TOUCHED OBJECT WAS BUILT ON ═══
--   · `"drops self open"`   ← 0002:131 — **DROPPED**. Nothing else re-creates it (grep: 0002 only).
--   · `"gear self claim"`   ← 0002:134 — **DROPPED**. Same.
--   · `"drops self read"` / `"gear self read"` ← 0002:130/133 — UNTOUCHED (the app's two selects).
--   NEW and owned here: `_drop_contents_ok`, `_guard_drop_cols` + trigger, `_guard_gear_claim_cols`
--   + trigger, constraints `drops_contents_shape`, `drops_pick_choice_shape`,
--   `drops_pick_opened_has_choice`, `gear_claims_item_len`.
--
-- ═══ §0e DOCTRINE (0059 money-path list) ═══
-- self-contained · every function carries `set search_path = public, pg_temp` IN THE BODY (98 H1)
-- · role judgement is `current_user` in an INVOKER trigger (0083's trap: `current_user` inside a
-- DEFINER is always the owner) · views via create or replace only (none touched) · mutation-proven
-- pins (`141_drops_seal_suite.sql`, D1-D20).
--
-- ═══ §0f MUTATION TABLE — MEASURED 2026-08-19: each mutation applied in a transaction on the
--        harness DB after all migrations, suite 141 run inside it, rolled back. "red" = the pins
--        that failed; every other pin stayed green. Baseline: 20/20 green. ═══
--   M1  `grant update on drops to authenticated` (undo §1)          → D1 D2 D7 (the exploit and
--                                                                     its neighbours land) · D6
--                                                                     (grant law)         4 red
--   M2  `drop trigger _guard_drop_cols_tg on drops` (undo §3)        → D9 D9b D10 D12 (service_role
--                                                                     mutations land) · D11 (the
--                                                                     re-armed row opens twice) ·
--                                                                     D17 (belt gone) · D19b
--                                                                     (post-review)      7 red
--   M3  `_drop_contents_ok` without the miles ceiling (weaken §2)    → D13 (5001 and 9,999,999
--                                                                     accepted)          1 red
--   M4  trigger arm that lets opened_at return to null (keeps        → D10 · D11 (cascade: the
--       the re-stamp refusal)                                          reset row opens again) ·
--                                                                     D19b (post-review) 3 red
--   M5  trigger arm that lets an opened row be re-stamped (keeps     → D12 (second stamp without
--       only the → null refusal)                                       the CAS predicate lands)
--                                                                     D11 stays green — the CAS
--                                                                     two-step is SQL semantics,
--                                                                     D12 is the seal   1 red
--   M6  `drop trigger _guard_gear_claim_cols_tg` + `grant update on  → D6 · D16 (client rewrites
--       gear_claims to authenticated`                                  status/item; service_role
--                                                                     rewrites item)     2 red
--   M7  re-create `"drops self open"` (grants stay revoked)          → D6 (policy pin) — and D1-D5
--                                                                     stay green: the grant alone
--                                                                     holds              1 red
--   ── after adversarial review (APPROVE-WITH-FIXES, same day) ──
--   M8  `alter table gear_claims drop constraint gear_claims_item_len` → D16 (81-char / empty
--                                                                     item accepted)    1 red
--   M9  trigger owner-exemption WITHOUT the JWT-role clause (undo F1) → D19b (owner + client
--                                                                     JWT rewrites contents) 1 red
--   M10 `grant trigger on drops, gear_claims to service_role` (undo F3)→ D6           1 red
--   M11 `drop constraint drops_pick_opened_has_choice` (undo F5)     → D20 (pick stamped with
--                                                                     no choice)      1 red
--   M12 a SECURITY DEFINER granted to authenticated that updates      → D19 (catalog sweep)
--       drops (the reviewer's temp function)                                          1 red
--   Note under M2, D17 first read `42501 permission denied for function _drop_contents_ok`
--   rather than a CHECK verdict — which is why §2's helper is granted to public (see there);
--   re-measured after the grant: `23514 … drops_contents_shape` — the CHECK's own verdict, and
--   D17 still red because the belt it pins is the trigger, not the CHECK.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §1 THE REVOCATION — no client role writes `drops` or `gear_claims`
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- WHY REVOKE + DROP RATHER THAN A WITH CHECK. A WITH CHECK on `drops self open` could say
-- "opened_at must be null and contents unchanged", but a policy cannot say "the server chose
-- this" — and every column here is a money input read by a service_role function that trusts
-- the row. There is exactly one legitimate writer of `drops` on the client's behalf (`open-drop`,
-- service_role) and one minter (`settle_run_tx`, owner). With the grants gone the ROLE cannot
-- reach the table, before RLS is even consulted; with the policies gone, a future re-grant still
-- meets an RLS deny; with §3, a future re-grant AND re-policy still meets a trigger.
-- The two `for select` policies stay: `fetchDrops` / `fetchGearClaims` are `runner_id =
-- auth.uid()` reads and keep working exactly as before. SELECT is re-granted to `authenticated`
-- only — `anon` had it via the Supabase default and could never see a row (auth.uid() is null),
-- so nothing observable changes and one dead door closes.
revoke all on table drops       from public, anon, authenticated;
revoke all on table gear_claims from public, anon, authenticated;
grant select on table drops       to authenticated;
grant select on table gear_claims to authenticated;
drop policy if exists "drops self open" on drops;
drop policy if exists "gear self claim" on gear_claims;
-- service_role keeps SELECT/INSERT/UPDATE/DELETE (open-drop needs the first three) and loses the
-- three it never needed: TRIGGER (review F3 — the reviewer created a trigger on `drops` AS
-- service_role, which would run ahead of §3 in name order), TRUNCATE (not subject to RLS or to
-- §3), REFERENCES. Scoped to these two tables; the repo-wide anon/authenticated TRUNCATE sweep
-- is 0109's, not this file's.
revoke trigger, truncate, references on table drops, gear_claims from service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §2 THE SHAPE — what `contents` may be, decided by the minter's own two shapes
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `settle_run_tx` (0083 §6:812-826) mints exactly two shapes:
--   mini : {"miles": 500..1199} plus optionally {"card": '드랍 카드'} or {"gear": '기어 교환권'}
--   pick : {"options": ["boost","miles","gear"]}
-- `open-drop` reads `miles`/`card`/`gear` on the mini arm and nothing on the pick arm (its
-- `miles` choice pays a constant 5,000). So the whitelist below is the union of what is minted
-- and what is read; a key outside it has no reader and no writer and is refused.
-- MILES CEILING = 5000: the largest 하이 포인트 figure the drop system knows (the pick payout);
-- the largest a mini can carry is 1,199. Nothing legitimate is near the ceiling; 9,999,999 is
-- refused by two orders of magnitude before the trigger is even consulted.
-- CASE, not `and`: SQL `and` does not promise evaluation order, so `contents - 'miles'` on a
-- scalar could raise (22023) before `jsonb_typeof(...) = 'object'` is tested. A refusal by the
-- wrong error is still a refusal, but a CHECK should say 23514, so each arm is reached only
-- after the arm that makes it well-typed.
create or replace function _drop_contents_ok(p_kind drop_type, p jsonb) returns boolean
language sql immutable set search_path = public, pg_temp as $$
  select case
    when p is null or jsonb_typeof(p) <> 'object' then false
    when (p - 'miles' - 'card' - 'gear' - 'options') <> '{}'::jsonb then false
    -- typeof arm BEFORE the cast arm, as separate WHENs: a `"miles":"abc"` must be false, not 22P02
    when p ? 'miles' and jsonb_typeof(p->'miles') <> 'number' then false
    when p ? 'miles' and not ((p->>'miles')::numeric = floor((p->>'miles')::numeric)
                              and (p->>'miles')::numeric between 0 and 5000) then false
    when p ? 'card' and jsonb_typeof(p->'card') <> 'string' then false
    when p ? 'card' and length(p->>'card') not between 1 and 40 then false
    when p ? 'gear' and jsonb_typeof(p->'gear') <> 'string' then false
    when p ? 'gear' and length(p->>'gear') not between 1 and 40 then false
    when p ? 'options' and jsonb_typeof(p->'options') <> 'array' then false
    when p ? 'options' and jsonb_array_length(p->'options') not between 1 and 8 then false
    -- kind-conditioned: a mini carries miles and never options; a pick carries options and none
    -- of the paid keys. open-drop's arms are chosen by `kind`, so a row that satisfies the other
    -- arm's shape is a row nobody minted.
    when p_kind = 'mini' and not (p ? 'miles' and not p ? 'options') then false
    when p_kind = 'pick' and not (p ? 'options' and not (p ? 'miles' or p ? 'card' or p ? 'gear')) then false
    else true
  end
$$;
-- ⚠ EXECUTABLE BY PUBLIC, deliberately — the one function in this file that is NOT revoked. A
-- CHECK constraint runs as the role performing the write, so a helper revoked from a role turns
-- every write by that role into `42501 permission denied for function` instead of a 23514
-- (measured under mutation M2+D17: trigger gone, client re-granted → 42501 on the helper, not the
-- CHECK's own verdict). It is IMMUTABLE, touches no table and reads no caller state; exposing it
-- exposes nothing. Fail-closed-by-accident is not a seal.
grant execute on function _drop_contents_ok(drop_type, jsonb) to public;
comment on function _drop_contents_ok is
  '0106 §2: the contents whitelist behind drops_contents_shape. Object only; keys ⊆ {miles,card,gear,options}; miles integer 0..5000; card/gear 1..40 chars; options a 1..8 array; mini ⇒ miles ∧ ¬options, pick ⇒ options ∧ ¬paid keys. CASE so a scalar cannot raise ahead of the typeof test.';

alter table drops drop constraint if exists drops_contents_shape;
alter table drops add constraint drops_contents_shape check (_drop_contents_ok(kind, contents));

-- pick_choice: the three strings open-drop accepts, and only on a row that has been opened —
-- open-drop writes both columns in one statement, so an unopened row with a choice cannot come
-- from it. (Today open-drop stamps FIRST and validates the choice AFTER, so a pick drop opened
-- with a garbage choice used to be burned — stamped, nothing applied. With this CHECK the CAS
-- UPDATE itself fails on a bad choice and the drop stays unopened. That is a behaviour change in
-- the runner's favour and is named here rather than left to be found.)
alter table drops drop constraint if exists drops_pick_choice_shape;
alter table drops add constraint drops_pick_choice_shape check (
  (pick_choice is null or pick_choice in ('boost', 'miles', 'gear'))
  and (pick_choice is null or opened_at is not null)
);

-- (review F5) A pick drop stamped with NO choice is burned: open-drop's pick arm applies nothing,
-- and §3 forbids writing pick_choice afterwards. open-drop always sends one for a pick
-- (`rewards.tsx:144` open(d, k)) and validates it before paying, so this arm is unreachable by
-- the real path — it exists so a future caller cannot create the unrepairable row.
alter table drops drop constraint if exists drops_pick_opened_has_choice;
alter table drops add constraint drops_pick_opened_has_choice check (
  not (kind = 'pick' and opened_at is not null and pick_choice is null)
);

alter table gear_claims drop constraint if exists gear_claims_item_len;
alter table gear_claims add constraint gear_claims_item_len check (length(item) between 1 and 80);

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §3 _guard_drop_cols — defence in depth on `drops`
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §1 is the fix; this is the belt. It also does one thing §1 cannot: it constrains SERVICE_ROLE.
-- `open-drop` runs as service_role and legitimately writes exactly two columns, once. Should a
-- future edge function (or a compromised service key, or a bug like 0083's "discarded error")
-- try to rewrite `contents` or re-arm `opened_at`, the table itself refuses.
--
-- ROLES, stated:
--   · `authenticated` / `anon`  → EVERY op refused (`drop_client_write`). Belt behind §1.
--   · every other role that is NOT the table owner and NOT a superuser (in production that is
--     `service_role`; in the harness, `service_role`) → `contents`/`kind`/`runner_id`/
--     `run_count_at`/`created_at` frozen; `opened_at` may go null→non-null ONCE and never move
--     again (not back to null, not to a later time); `pick_choice` may only be written in the
--     statement that stamps `opened_at`. INSERT and DELETE are allowed (nothing forbids
--     service_role minting or ops removal — the money is in the mutation, not the row's life).
--   · the table owner (`postgres` — migrations, `settle_run_tx` and every definer) and superusers
--     → exempt **unless the request carries a client JWT** (review F1). A SECURITY DEFINER RPC
--     granted to authenticated runs as the owner, so an owner exemption keyed on `current_user`
--     alone would let a future definer rewrite drops on a runner's behalf (the reviewer proved it
--     with a temp function; no such function exists today — 141 D19 sweeps the catalog for one).
--     So the exemption also requires `request.jwt.claim.role` NOT to be authenticated/anon: a
--     definer called through PostgREST by a client is judged at the service_role tier (columns
--     frozen, opened_at once). The bare-owner path — the SQL editor, migrations, the harness,
--     `settle_run_tx` invoked by settle-run (service_role JWT) — is where an ops repair of a
--     wrongly-stamped drop lives; it is a SQL-editor act by Sean, not an API. Judged by
--     `pg_class.relowner` / `pg_roles.rolsuper`, not by a role name, so a differently-named owner
--     would still be exempt and a differently-named service account would still be guarded.
--   · (review F4, documented allowance) service_role may DELETE a row and INSERT a fresh one —
--     "row replacement" — because INSERT/DELETE are not frozen at that tier; the money is in the
--     mutation of a row open-drop is about to pay, and a replaced row is a new unopened mint
--     with a new id, which is service_role's to make anyway. Not guarded, by decision.
-- INVOKER, for 0083's reason: `current_user` inside a DEFINER is always the owner and would
-- exempt everybody.
create or replace function _guard_drop_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_owner text;
  v_super boolean;
begin
  if current_user in ('authenticated', 'anon') then
    raise exception 'drop_client_write'
      using detail = '드랍은 서버만 만들고 열어요 — 앱에서 직접 바꿀 수 없어요';
  end if;

  select r.rolname into v_owner from pg_class c join pg_roles r on r.oid = c.relowner where c.oid = tg_relid;
  select rolsuper into v_super from pg_roles where rolname = current_user;
  -- owner/superuser exempt ONLY when no client JWT is on the request (F1): a definer RPC called
  -- by an authenticated user is judged like service_role below.
  if (current_user = v_owner or coalesce(v_super, false))
     and coalesce(current_setting('request.jwt.claim.role', true), '') not in ('authenticated', 'anon') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE' then
    if new.contents     is distinct from old.contents
    or new.kind         is distinct from old.kind
    or new.runner_id    is distinct from old.runner_id
    or new.run_count_at is distinct from old.run_count_at
    or new.created_at   is distinct from old.created_at
    then
      raise exception 'drop_immutable_columns'
        using detail = '드랍의 내용물·종류·주인·회차는 만들어진 뒤 바뀌지 않아요';
    end if;
    if old.opened_at is not null and (
         new.opened_at   is distinct from old.opened_at
      or new.pick_choice is distinct from old.pick_choice)
    then
      raise exception 'drop_already_opened'
        using detail = '이미 열린 드랍이에요 — 다시 열거나 되돌릴 수 없어요';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke execute on function _guard_drop_cols() from public, anon, authenticated;

drop trigger if exists _guard_drop_cols_tg on drops;
create trigger _guard_drop_cols_tg before insert or update or delete on drops
  for each row execute function _guard_drop_cols();

comment on function _guard_drop_cols is
  '0106 §3: the drops seal belt. authenticated/anon: every op refused. Any non-owner non-superuser role (service_role) — and the owner when the request carries a client JWT (a definer RPC called by a user): contents/kind/runner_id/run_count_at/created_at frozen after insert; opened_at may be stamped once and never moves again (no reset to null, no re-stamp); pick_choice freezes with it. Bare owner/superuser exempt (ops repair). INVOKER — current_user in a DEFINER is always the owner.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §4 _guard_gear_claim_cols — the same belt on `gear_claims`
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Writers today: `open-drop` INSERTs (`status = 'claimable'`) as service_role; nobody UPDATEs.
-- The client reads (`fetchGearClaims`) and never writes, so `authenticated`/`anon` are refused
-- outright. For service_role the identity of a claim (whose, which item, at which milestone) is
-- frozen; the fulfilment columns (`status`, `shipped_to`, `claimed_at`) stay writable because a
-- future ops flow will need them and freezing them now would only be undone.
create or replace function _guard_gear_claim_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_owner text;
  v_super boolean;
begin
  if current_user in ('authenticated', 'anon') then
    raise exception 'gear_claim_client_write'
      using detail = '기어 교환권은 서버만 만들고 처리해요 — 앱에서 직접 바꿀 수 없어요';
  end if;

  select r.rolname into v_owner from pg_class c join pg_roles r on r.oid = c.relowner where c.oid = tg_relid;
  select rolsuper into v_super from pg_roles where rolname = current_user;
  if (current_user = v_owner or coalesce(v_super, false))
     and coalesce(current_setting('request.jwt.claim.role', true), '') not in ('authenticated', 'anon') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE' then
    if new.profile_id is distinct from old.profile_id
    or new.side       is distinct from old.side
    or new.item       is distinct from old.item
    or new.milestone  is distinct from old.milestone
    or new.created_at is distinct from old.created_at
    then
      raise exception 'gear_claim_immutable_columns'
        using detail = '교환권의 주인·품목·마일스톤은 만들어진 뒤 바뀌지 않아요';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke execute on function _guard_gear_claim_cols() from public, anon, authenticated;

drop trigger if exists _guard_gear_claim_cols_tg on gear_claims;
create trigger _guard_gear_claim_cols_tg before insert or update or delete on gear_claims
  for each row execute function _guard_gear_claim_cols();

comment on function _guard_gear_claim_cols is
  '0106 §4: gear_claims belt. authenticated/anon: every op refused. Non-owner roles (service_role): profile_id/side/item/milestone/created_at frozen; status/shipped_to/claimed_at writable (future ops fulfilment). Owner/superuser exempt. INVOKER.';
