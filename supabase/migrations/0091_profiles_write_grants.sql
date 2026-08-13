-- ═══ 0091: profiles WRITE column whitelist — the other half of 0088 ═══
--
-- 0088 §0b names this gap in its own words: "It does not touch INSERT/UPDATE/DELETE grants on
-- `profiles`, and that gap is real." This file closes it. Same table, same law (0075 §D: RLS는
-- 행만 막는다, 컬럼과 DML은 grant가 막는다), the write direction.
--
-- ⚠⚠ READ §E FIRST IF YOU ARE ABOUT TO DEPLOY 0088. This file is not only additive hardening —
--    it also carries a ONE-LINE REPAIR for a P0 regression that 0088 introduces and that no pin
--    in 124 can see. **0088 without 0091 returns HTTP 403 on every signup and every role
--    switch.** Measured against real PostgREST, not inferred. If these two ever get separated,
--    0091 is the half that must not be dropped.
--
-- ═══ §A THE COMPLETE CLIENT WRITE SET — enumerated, not sampled ═══
-- Every write to `profiles` from a client, across the whole repo (grep `from('profiles')` +
-- upsert|update|insert|delete):
--   · app/app/index.tsx:27     upsert({ id, role, name })      — the role picker at `/`
--   · app/src/lib/api.ts:1459  update({ name?, district? })    — updateMyProfile
--   · app/src/lib/api.ts:2029  update({ avatar_url })          — avatar upload
-- That is all of it. (`app/scripts/e2e-club.mjs:144` also inserts, but through `svc` — the
-- service_role client — so it is unaffected by anything below.)
--
-- ⚠ THE UPSERT IS AN UPSERT, and that is the whole difficulty. `/` is the role picker and it is
-- reachable AFTER signup — tapping 러너/보호자 again re-runs the same call on an existing row. So
-- the statement PostgREST sends is `INSERT … ON CONFLICT DO UPDATE`, not a plain INSERT, and it
-- needs UPDATE privileges as well. A naive test that only inserts a fresh row cannot see this.
--
-- ═══ §B WHY `toss_customer_key` IS THE ONE THAT MATTERS ═══
-- Not "an orphaned row". `billing_keys` is keyed on `profile_id` (0080:103), so a client
-- rewriting its own `toss_customer_key` does not orphan OUR storage at all. What it does is
-- DESYNCHRONIZE us from Toss: the billingKey was issued against the OLD customerKey, and
-- `_shared/charge.ts:232` sends BOTH on every charge. Mismatch → Toss rejects → the row walks the
-- decline ladder → debt → account lock. But `settle_run_tx` has already COMMITTED and the runner
-- has already been paid.
--
-- So this is not a harmless data-integrity nit. It is a **self-service uncharge with our money on
-- the hook** — repeatable, and it converts a rare INVOLUNTARY event (a card declines) into a
-- VOLUNTARY one a user can trigger at will. That asymmetry is the reason this column is the
-- headline of the file rather than one of five.
--
-- ⚠ NOT EXECUTED AGAINST TOSS'S SANDBOX. We have not confirmed by experiment that Toss rejects a
-- billingKey presented with a mismatched customerKey; the trace above is read from our own code
-- plus Toss's documented pairing. **This guard must not depend on their rejecting it.** If Toss
-- were to ACCEPT the mismatch the outcome is worse, not better (a charge succeeds against a key
-- we can no longer attribute), so the grant is correct either way — but do not cite this header
-- as evidence about Toss's behaviour.
--
-- ═══ §C `role` STAYS WRITABLE — do not "fix" this ═══
-- `user_role` is `create type user_role as enum ('owner','runner')` (0001:7). **There is no admin
-- role.** Self-setting `role` is therefore not privilege escalation; it is the role picker doing
-- its job, and revoking it breaks the app's very first screen.
-- Swept before deciding, 2026-08-13: **no SQL anywhere grants privilege based on `profiles.role`.**
-- (`club_members.role` — 0032:25's `m.role = 'host'` — is a DIFFERENT column on a different table;
-- club host powers key on that one, never on this one. Zero edge-function reads of `profiles.role`
-- either.) If you ever add a value to `user_role`, or make any policy/RPC read `profiles.role`,
-- that changes this answer and this grant must be revisited in the same breath.
--
-- ═══ §D `handle` NEEDS NO WRITE GRANT — verified, not assumed ═══
-- `handle` is written by exactly one thing: `set_my_handle` (0074:63), and it is
-- `language plpgsql security definer` — **`prosecdef = true`, confirmed in the catalog**. A
-- definer runs as its owner (postgres), so removing the caller's UPDATE privilege on the column
-- does not touch it. 124 G5 already proves this class end-to-end for the READ direction; 127 W3
-- proves it here for the WRITE direction, in both arms (direct UPDATE denied AND the RPC still
-- works) — because "handle is sealed" and "handle can still be set" are one claim, not two.
--
-- Excluding it is a REAL TIGHTENING, not bookkeeping: today a client can `PATCH
-- /profiles?id=eq.<self>` with `{"handle":"admin"}` and bypass `set_my_handle` entirely — its
-- whole rulebook (lowercase normalisation · 3-20 chars · `[a-z0-9_.]` · no leading/trailing/double
-- dots · the reserved list `admin`/`official`/`dogshigh`/… · case-insensitive uniqueness) lives in
-- the function, and a direct UPDATE walks around all of it. 0074's own column comment predicted
-- this and could not enforce it: "설정은 set_my_handle()만 — 클라 직접 UPDATE는 컬럼 화이트리스트가
-- 없으므로 신뢰하지 않는다." This file is the column whitelist that comment was waiting for.
-- (The unique index still blocks taking a handle someone HAS. It never blocked squatting a
-- reserved one, and it never enforced the charset.)
--
-- ═══ §E ⚠⚠ THE MEASURED CORRECTION: 0088 ALONE BREAKS THE ROLE PICKER ═══
-- This is the most important paragraph in the file and it was found by EXECUTION, against a real
-- PostgREST v12.2.3 + PG16 talking to a mirror of this exact grant state (2026-08-13). It is not
-- reachable by reading DDL, which is why 0088 shipped at 506/0 without it.
--
-- ① WHAT POSTGREST ACTUALLY SENDS for `supabase.from('profiles').upsert({id, role, name})`
--    (captured from `log_statement=all`, verbatim, whitespace trimmed):
--
--      INSERT INTO "public"."profiles"("id","name","role") SELECT … FROM json_to_record(…)
--      ON CONFLICT("id") DO UPDATE
--        SET "id" = EXCLUDED."id", "name" = EXCLUDED."name", "role" = EXCLUDED."role"
--
--    Note `"id" = EXCLUDED."id"`. supabase-js `.upsert()` sends `Prefer: resolution=merge-duplicates`,
--    and PostgREST puts **every payload column** in the DO UPDATE SET list — including the conflict
--    target itself. So the statement needs `UPDATE (id)` even though the value never changes.
--
-- ② POSTGRES ALSO DEMANDS **SELECT** ON EVERY COLUMN IN THAT SET LIST. `SET role = EXCLUDED.role`
--    counts as reading column `role` ("SELECT privilege on any column whose values are read in the
--    ON CONFLICT DO UPDATE expressions"). 0088 §A deliberately left `role` OUT of the read grant
--    ("zero client reads. Least privilege: not granted") — correct for reads, fatal here.
--
-- ③ THE MEASURED CONSEQUENCE OF 0088 WITHOUT THIS FILE. Post-0088 state = table-wide
--    INSERT/UPDATE/DELETE from the Supabase default privileges + `select (id,name,handle,
--    avatar_url,district)`:
--
--      role switch  (upsert onto an existing row) → ERROR: permission denied for table profiles
--      first signup (upsert, no conflict at all)  → ERROR: permission denied for table profiles
--      pre-0088 control (table-wide select)       → INSERT 0 1
--
--    ⚠ The FIRST SIGNUP fails too, and that is the counter-intuitive part worth stating out loud:
--    the privilege check is made once for the STATEMENT, at execution, so the `ON CONFLICT` arm is
--    checked even on a row that does not conflict. There is no "new users are fine" consolation.
--    Every user of the app, on the very first screen, 403.
--
-- ④ WHY NO PIN CAUGHT IT. 124 G3's arm ④ exercises `update profiles set district = …` — a plain
--    UPDATE. Nothing in the repo ever executed the upsert shape in SQL, and the harness has no
--    PostgREST, so the one statement the app actually sends on its first screen was the one
--    statement never tested. **125 W5 executes that exact statement text.**
--
-- ⑤ THE REPAIR IS §F's `grant select (role)`. It is done HERE, in a new file, rather than by
--    editing 0088: 0088 is verified at 506/0 and about to be acted on, and CLAUDE.md forbids
--    amending an applied migration. The cost is that **124 G1's fourth arm reddens** — its
--    `v_public` array must gain `'role'`. That pin is not wrong in shape, only in contents; it is
--    doing precisely the job it was written for (it noticed the read surface changed). The owning
--    slice must add `'role'` to `v_public` in `124_profiles_column_grant_suite.sql:132`.
--    Privacy cost of granting it: ~zero. `role` is `owner`|`runner`, and a runner is already
--    listed publicly in `runners`/`available_runners`.
--
-- ═══ §F THE ID-REWRITE QUESTION, AND WHY NO POLICY CHANGE IS NEEDED ═══
-- Granting `UPDATE (id)` (forced by §E①) looks like it opens profile-identity transfer:
-- `PATCH /profiles?id=eq.<self>` with `{"id": "<some other auth.users id>"}`, moving your row —
-- and every `dogs`/`bookings`/`runners` FK that hangs off it — onto an account you are not.
-- **Measured: it is already blocked, and by something that was there all along.**
-- `profiles self write` (0002:59) is `for update using (auth.uid() = id)` with NO `with check`,
-- and PostgreSQL uses the USING expression AS the WITH CHECK when one is not given. So the
-- proposed row is tested too, and `auth.uid() = <someone else's id>` is false:
--
--   PATCH {"id": <other>}  →  403 new row violates row-level security policy for table "profiles"
--   upsert {id: <self>, …} →  200 (the conflict path sets id to the SAME value, so USING holds)
--
-- Recorded because the instinct on reading `grant update (id)` is to add `alter policy … with
-- check (auth.uid() = id)` for safety. That would be a no-op with a real blast radius (it moves a
-- 0002 policy), and this file does not do it. ⚠ It is a no-op ONLY while `profiles self write`
-- stays USING-only. **Anyone adding an explicit `with check` to that policy must include
-- `auth.uid() = id` in it**, or this grant stops being safe. 127 W6 pins the denial, so that
-- mistake turns the harness red rather than shipping.
--
-- ═══ §G WHAT THIS FILE DOES NOT DO ═══
-- - No policy, no table, no view, no trigger, **no function.** REGISTRY "what it recreates": NONE.
--   In particular it does NOT build a `_guard_profile_cols` trigger (the 0057 shape). A grant is
--   the right tool here because the rule is per-column and unconditional; a trigger would be
--   needed only for a rule that depends on the VALUE or the transition, and there is none.
--   ⚠ It DOES replace one existing `comment on column`: `profiles.handle`'s, written by 0074.
--   0074's sentence "설정은 set_my_handle()만" was an instruction nobody could enforce; §H rewrites
--   it to say that the whitelist it was asking for now exists. Comments are not objects, so this
--   is not a "recreates" entry — but it IS someone else's text, so it is named here rather than
--   changed quietly. `profiles.phone` and `profiles.toss_customer_key`'s comments are 0088's and
--   are left exactly as they are.
-- - It does not touch row visibility. `profiles public runner read` (0002:56) is unchanged, for
--   0088 §C's reason: narrowing it is a product decision about the storefront.
-- - **It does not audit `service_role`.** Edge functions write `profiles` (billing keys, PASS),
--   and breaking them breaks money. §H re-states their grants explicitly so a future blanket
--   revoke reddens 127 W8 instead of turning billing off in production. 124's ⓓ mutation already
--   showed service_role's `profiles` access reaches further than billing (`70_axes` X2 also went
--   red) — anyone narrowing it starts from that pin, not from this file.
-- - It changes no app code. Nothing above requires a client change; the app's three call sites
--   work unmodified, which is the point of §E's measurement.
--
-- ═══ §0d DOCTRINE ═══
-- Mutation-proven pins in `127_profiles_write_grant_suite.sql` (W1-W9). Pins this file must not
-- break: 124 G1-G8 (0088's read wall — ⚠ except G1's fourth arm, see §E⑤), 112 (set_my_handle's
-- own rules), 99 S2-S5 (the column-guard trigger family), and every `set local role authenticated`
-- write in 95-124.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §H the grants
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Order matters, exactly as in 0088 §D: revoke first, then re-grant the whitelist. Revoking a
-- table-level privilege clears the column privileges under it, so this is idempotent — a re-run
-- cannot accumulate a stale column. SELECT is NOT named here; 0088 owns it (and §E⑤ adds to it).
revoke insert, update, delete on profiles from public, anon, authenticated;

-- §E⑤: the repair. `role` must be READABLE for `ON CONFLICT … DO UPDATE SET role = EXCLUDED.role`
-- to be allowed to run at all. Without this line the role picker is 403 for every user — measured.
-- ⚠ This widens 0088 §A's read whitelist by one column; `124:132`'s `v_public` must gain `'role'`.
grant select (role) on profiles to authenticated;

-- INSERT: exactly the role picker's payload. `id` is required by `profiles self insert`
-- (0002:60, `with check (auth.uid() = id)`) — a row you cannot name yourself is not insertable.
grant insert (id, role, name) on profiles to authenticated;

-- UPDATE: the three editable fields, plus the two the upsert's conflict arm rewrites.
--   name       — updateMyProfile (api.ts:1459) AND the upsert conflict arm
--   district    — updateMyProfile
--   avatar_url — the avatar upload (api.ts:2029)
--   role       — the role picker's conflict arm (§A: tapping 러너/보호자 again on an existing row)
--   id         — ⚠ NOT a client feature. PostgREST emits `"id" = EXCLUDED."id"` in the conflict
--                arm (§E①), so the privilege is required even though the value never changes.
--                Safe because the row policy's USING doubles as its WITH CHECK (§F).
-- OUT, on purpose: phone · toss_customer_key (§B) · handle (§D) · created_at · updated_at.
-- `updated_at` needs no grant despite being written on every update: `t_profiles_touch`
-- (0002:9) sets it in a BEFORE trigger, and privilege is checked against the STATEMENT's SET
-- list, not against what a trigger assigns to NEW. Pinned by 127 W2's third arm.
grant update (name, district, avatar_url, role, id) on profiles to authenticated;

-- DELETE: granted to nobody. No client and no edge function deletes a profile row (grep: zero),
-- and account deletion arrives through `id … references auth.users on delete cascade` (0001:27),
-- which is a cascade from the auth schema and needs no privilege here.

-- anon gets NOTHING — not re-granted, deliberately. The app is auth-gated and all three write
-- sites read `auth.getUser()` first. Same reasoning as 0088 §D's read side.

-- Explicit, not redundant (0088 §D's precedent): edge functions write `profiles` through the
-- service_role client, so stating it here means a future blanket revoke turns 127 W8 red instead
-- of turning billing off in production.
grant insert, update, delete on profiles to service_role;

comment on column profiles.role is
  '0001: owner|runner. admin 등급은 존재하지 않는다 — 그래서 본인이 직접 바꿔도 권한 상승이 아니고,
`/` 역할 선택 화면(app/index.tsx:27)이 실제로 upsert로 쓴다. [0091] 클라 쓰기 허용 컬럼.
⚠ profiles.role에 권한을 거는 SQL은 하나도 없다(2026-08-13 전수). 그런 게 생기거나 user_role에
값이 추가되면 이 그랜트를 다시 판단할 것. (club_members.role은 다른 컬럼이다.)';

comment on column profiles.handle is
  '0074: 인스타식 계정 아이디. 소문자 정규화 저장, 3~20자 [a-z0-9_.], 대소문자 무시 유니크.
NULL = 아직 안 만듦 (기존 사용자). 설정은 set_my_handle()만 — [0091]가 컬럼 UPDATE 그랜트에서
빼면서 이 문장이 규칙에서 강제로 바뀌었다. 클라 직접 UPDATE는 permission denied이고,
set_my_handle은 security definer라 그대로 동작한다 (예약어·글자수·charset 검사를 우회할 길이 없다).';
