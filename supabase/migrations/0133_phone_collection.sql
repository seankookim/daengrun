-- ═══ 0133: a phone number, collected at signup — the one contact channel that works ═══
--
-- Contract: docs/contracts/phone-collection-contract.md. Sean, verbatim: 「i think we should have
-- the owner and any new person insert phone number on onboarding for safety and contact
-- purposes」.
--
-- ⚠ READ §1 OF THE CONTRACT BEFORE ASSUMING THIS SLICE IS BIG. Most of the phone feature is
--   ALREADY SHIPPED and was built long before the ruling: `_club_phone_visible` (0049:167-192)
--   decides who may see whose number, `phone_reveal` audits every disclosure (0049:156-163,
--   write at 0053:435), `club_session_roster` returns it, the session shell renders it as a
--   tappable `tel:` chip with a 「호스트 경유」 fallback, and `delete_my_account_tx` ALREADY nulls
--   it in the tombstone (0115:421) — so deletion of this column is not owed by this slice.
--   What was missing is the thing nobody could do: **put a number in.** 0 of 10 profiles have
--   one, because no write path exists for `authenticated` at all.
--
-- ═══ §10 RULINGS — Sean 2026-08-26 04:57Z, CLOSED 4/4. Read before changing anything here. ═══
--   ① verification: 「Shape-check is fine for the pilot」 — format only, no SMS/PASS vendor.
--      🔴 This carries an HONESTY OBLIGATION, not just a saving: the number must NEVER be
--      presented to a user as verified. No 「인증됨」 badge, no copy implying we checked. A
--      shape-checked string is a string someone typed, and the UI may not imply otherwise.
--   ② scope: 「Host sees everyone — as built」 — Rule B (0049) ships at full width.
--   ③ retention: 「Until they delete the account」 — 0115:421 already nulls it in the tombstone.
--      **NO dormancy purge exists and none is wanted** — do not add one as a tidy-up.
--   ④ editable: 「Editable, but never blank」 — 🔴 A BUILD REQUIREMENT. Clearing must be REFUSED,
--      because if an empty string is accepted then 「required at signup」 is a ten-second
--      formality and the entire safety case behind Sean's ruling evaporates. §B raises on empty
--      by construction (a blank normalises to '' and fails the regex) and suite 166 P2 pins it
--      as its own proposition rather than leaving it as a side effect of the format check.
--
-- 🔴 ═══ SHIP GATE — UNMET AT AUTHORING TIME (contract §8). This file is LANDED, NOT LIVE. ═══
--   Sean routed the privacy-policy wording to counsel (01:46:38Z) and that email has not been
--   sent. Nothing may COLLECT a phone number until counsel's text exists. That is why this slice
--   lands the SERVER only: a SECURITY DEFINER that no screen calls collects nothing, harms
--   nobody, and is the half Sean asked for when he said he needs the backend built. **The
--   client collection point is deliberately NOT wired in the same commit.** He clears that gate
--   — not a session, and not a green harness. Do not describe this slice as shippable until he
--   confirms counsel's text has landed.
--
-- ═══ §A the shape CHECK ═══
-- The column has been `text` with no constraint since 0001. Storage format is normalised digits;
-- the client may send anything a human types.
-- ⚠ Adding a CHECK to a populated table validates every existing row. Measured immediately
--   before authoring: `count(*) filter (where phone is not null)` = **0 of 10**, so this cannot
--   fail on apply. Stated rather than assumed — a CHECK that aborts a migration on production
--   data is the classic way this shape goes wrong.
alter table profiles
  add constraint profiles_phone_shape
  check (phone is null or phone ~ '^01[0-9]{8,9}$');

-- ═══ §B set_my_phone — the only way a number gets in ═══
-- ⚠ WHY AN RPC AND NOT A COLUMN GRANT. `authenticated` has no UPDATE grant on `phone`
--   (0091:198 grants name/district/avatar_url/role/id only, and :194 names phone as OUT ON
--   PURPOSE) and no SELECT grant either (0088:135, 0091:180). `127 W2` PINS that refusal. So
--   widening the grant would turn a shipped pin red for a reason the pin's own comment still
--   endorses — the grant list is deliberately narrow because this column is contact data. The
--   definer is how the narrowness survives while the feature ships.
--
-- No target parameter: it writes `auth.uid()`'s row and only that row. **The absence of a target
-- uuid IS the party gate** — there is no argument that could be wrong, so there is no argument to
-- attack. Party gate before state gate (house law), and the tombstone refusal before any write.
create or replace function set_my_phone(p_phone text)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_digits text; v_n int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- NORMALISE, then validate — in that order, so a human typing 「010-8900-0091」 or
  -- 「+82 10 8900 0091」 succeeds rather than being told their own number is invalid.
  v_digits := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  -- A digit string opening with 82 is the country code: Korean mobile numbers begin 01, so this
  -- cannot collide with a real local number.
  if left(v_digits, 2) = '82' then v_digits := '0' || substr(v_digits, 3); end if;

  -- The SAME regex as §A's CHECK. If these two ever disagree the constraint raises 23514 at the
  -- write and the user is shown a database error instead of a sentence — so they are written
  -- together, here, and suite 166 P5 asserts the RPC's answer and the CHECK's answer agree on a
  -- value that is invalid.
  -- ④ 「Editable, but never blank」. An empty or whitespace-only input normalises to '' and fails
  -- the regex below, so the refusal is structural rather than a special case someone can delete.
  -- It is spelled out here anyway because the REASON is not obvious from the regex: this is the
  -- conjunct that keeps 「required」 from being a formality, and a later reader optimising the
  -- 「redundant」 empty case away would silently reopen it.
  if v_digits !~ '^01[0-9]{8,9}$' then
    -- A visible failure, never a silent no-op (honesty law): the caller must be able to tell
    -- 「we saved nothing」 from 「we saved it」, and a void return cannot say so on its own.
    raise exception 'invalid_phone';
  end if;

  -- The tombstone refusal. A deleted account must not be able to re-attach a contact number;
  -- 0123 §5 set this posture. `deleted_at is null` is part of the WHERE rather than a prior
  -- SELECT so there is no window between the check and the write.
  update profiles set phone = v_digits, updated_at = now()
   where id = auth.uid() and deleted_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'no_profile'; end if;
end $$;
-- Explicit ACL in the file that FIRST defines the function — never grant preservation
-- (0116:636: a function born on an absent-function path is PUBLIC-executable, and a
-- SECURITY DEFINER born that way is the worst shape this repo can produce). This also
-- satisfies check-definer-acl.mjs by construction rather than by baseline entry.
revoke execute on function set_my_phone(text) from public, anon;
grant execute on function set_my_phone(text) to authenticated;

comment on function set_my_phone is
  '0133: the ONLY write path to profiles.phone for authenticated. No target parameter — it writes
auth.uid()''s row, so the party gate is structural rather than a predicate. Normalises to digits
(rewriting a leading +82/82 to 0) and then validates against the same regex as the
profiles_phone_shape CHECK; raises invalid_phone rather than no-opping, and no_profile on a
tombstoned or absent row. The column stays NULLABLE deliberately: the profile row is INSERTed at
the role-select screen (app/app/index.tsx:72) BEFORE onboarding runs, so NOT NULL would abort the
launch path itself — "required" is enforced at the collection point, which is where Sean asked
for it.';
