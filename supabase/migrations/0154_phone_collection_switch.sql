-- ═══ 0154: phone collection gets a SWITCH, and a guest gets somewhere to type a number ═══
--
-- Sean, verbatim 2026-08-28: 「guest is a member and needs a phone number enter thing.」
--
-- That one sentence settles a question open since 2026-08-26 and adds a requirement:
--   ① a person who comes to a club walk WITHOUT a dog IS a 「member」 for the phone rule, so the
--      host sees their number — consistent with his `phone-host-scope = wide` ruling (contract
--      §10 ②, 「Host sees everyone — as built」);
--   ② a guest must be able to ENTER a number.
--
-- Contract: docs/contracts/phone-collection-contract.md. Predecessor: 0133_phone_collection.sql.
--
-- ═══ §0 WHY THIS FILE EXISTS AT ALL — read before assuming it is a widening ═══
--
-- 0133 landed the SERVER (`set_my_phone`) and DELIBERATELY wired no client collection point. Its
-- own header says why, and it is still true today:
--
--   「Sean routed the privacy-policy wording to counsel (01:46:38Z) and that email has not been
--    sent. Nothing may COLLECT a phone number until counsel's text exists. That is why this slice
--    lands the SERVER only … The client collection point is deliberately NOT wired in the same
--    commit. He clears that gate — not a session, and not a green harness.」
--
-- ⚠ VERIFIED AT SOURCE BEFORE WRITING THIS FILE, not carried forward from that paragraph:
--   · `set_my_phone` has **0 callers in `app/`** (grep over the whole client tree).
--   · `docs/legal/counsel-email.md` is still the OLDEST open item in `docs/session-handoff.md`
--     (OPEN #1), and it gates 「phone collection, publishing the privacy policy and terms, the KCC
--     filing, and launch」 in that file's own words.
--
-- 🔴 SO THE PROBLEM THIS FILE SOLVES IS NOT 「the client is missing」. It is that **there was no
--    way to build the client without turning collection ON.** `ops_flags` carried a switch for
--    card registration (`card_registration_live_since`, 0138 §D) and **none for phone** — measured
--    on this tree: the table's four columns are `payments_live_since`, `return_seal_since`,
--    `late_protocol_live_since`, `card_registration_live_since`. Whoever wired a signup field
--    would have turned host-sees-everyone on in the same commit, which is exactly what
--    `docs/session-handoff.md` OPEN #5 says.
--
--    The switch converts 「we remembered not to wire it」 into 「the database refuses」. That is the
--    same substitution as deleting `main` instead of asking people to branch correctly: a
--    CONSTRAINT that prevents, rather than a CONVENTION that reports.
--
-- ⚠ WHY THE GATE IS SERVER-SIDE AND NOT A CLIENT `if`. 0138 §D wrote the argument already and it
--   transfers verbatim: 「The booking gate reads a client constant (TOSS_ENABLED) and the settings
--   door reads whether a client key is configured — neither is a protection, because a modified
--   client is not bound by either. This column is.」 A privacy gate that any rebuilt client can
--   step over is a note, not a gate.
--
-- 🔴 ═══ §0b WHAT THIS FILE DOES **NOT** DO, stated because the opposite is the easy assumption ═══
--   · It does **NOT** turn phone collection on. `phone_collection_live_since` ships **NULL**, the
--     reader is fail-CLOSED, and `set_my_phone` REFUSES while it is null. Nothing collects.
--   · It does **NOT** touch `_club_phone_visible` (0049:167-192), `club_session_roster`
--     (0053:392-484), the reveal audit, or `delete_my_account_tx` (0115:421 already nulls the
--     column). Contract §9's list is intact.
--   · It does **NOT** widen a grant. `0088`/`0091`'s column lists are untouched and `127 W2`/`W8`
--     and `166 P6` stay green as written — 185 W1 pins that as its own proposition rather than
--     assuming it.
--   · It does **NOT** wire the SIGNUP collection points. Contract §3 names
--     `app/app/onboard/owner.tsx` and `onboard/runner.tsx`; both are untouched by this slice.
--     Those are what 「required at signup」 means, and they wait for counsel.
--   · It does **NOT** present the number as verified. Contract §10 ① — 「Shape-check is fine for
--     the pilot」 carries an honesty obligation, and the client half honours it (no 인증됨 badge).
--
-- 🔴 ═══ §0c AND IT DOES NOT DECOUPLE COLLECTION FROM HOST-SEES-EVERYONE. Say this out loud. ═══
--   Arming this flag still arms `_club_phone_visible` at full width: host ↔ every member of an
--   open/full session, and a person-only guest IS on that roster (`session_rsvp` inserts a
--   `session_people` row for `p_dog := null`, 0134:121-124 + 130). **That coupling is not closed
--   by this file and is not a defect** — Sean has now ruled it TWICE: contract §10 ② and today's
--   「guest is a member」. What the flag changes is WHO performs the arming: one deliberate
--   `update ops_flags` by Sean, instead of a side effect of an implementer's commit that nobody
--   would have described as a privacy decision. A future session must not read this file as
--   having separated the two.
--
-- ═══ §A the column ═══
-- Same shape and same reasoning as `card_registration_live_since`: a TIMESTAMP, not a boolean, so
-- the moment collection opened is recorded rather than merely the fact that it is open. Nothing
-- here is retroactive — unlike `payments_live_since` the timestamp is not compared against past
-- rows — but keeping the family's one shape means a reader learns the idiom once.
alter table ops_flags add column if not exists phone_collection_live_since timestamptz;

comment on column ops_flags.phone_collection_live_since is
  '0154 §A: the SERVER-owned gate on phone collection. NULL = set_my_phone refuses, whatever any
client believes. Sean flips it, and only after counsel''s revised 개인정보처리방침 naming item /
purpose / retention / RECIPIENT is live in-app (phone-collection-contract §8) — a host or runner
seeing an owner''s number is a third-party disclosure and it is the part the shipped text does not
cover. ⚠ Flipping this ALSO arms _club_phone_visible at full width (host <-> every session member,
a dogless guest included). That is Sean''s ruling twice over, not an oversight; it is named here so
whoever runs the UPDATE knows both things happen at once. A session must not flip it.';

-- ═══ §B the reader ═══
-- Its own function for the two reasons 0138 §D gives: the client needs one thing to call, and the
-- flag can gain conditions later without every caller learning them.
create or replace function phone_collection_live()
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  -- coalesce(..., false): a NULL flag is CLOSED, and so is a MISSING ROW. The second half is the
  -- one that matters and 171 R7 is the reason it is written down — with a row present, a NULL
  -- column already makes the inner select return NULL->false, so the coalesce governs only the
  -- no-row case: a fresh environment, a restored database, a partial apply. That is exactly when
  -- a capability defaulting to ON is worst and exactly when nobody is looking.
  select coalesce((select phone_collection_live_since is not null
                     and phone_collection_live_since <= now()
                     from ops_flags limit 1), false);
$$;
revoke execute on function phone_collection_live() from public, anon;
-- `authenticated` MAY read it, for the dead-button law: the screen has to know whether to draw the
-- 연락처 door at all, and a door that opens onto a refusal IS a dead button. It discloses one
-- boolean about our own rollout, which is not a fact about any user.
grant execute on function phone_collection_live() to authenticated;
grant execute on function phone_collection_live() to service_role;

comment on function phone_collection_live is
  '0154 §B: is phone collection open? Fail-closed on a NULL flag AND on a missing ops_flags row.
The client reads it to decide whether to draw the 연락처 entry at all; set_my_phone enforces it, so
a modified client gains nothing by ignoring it.';

-- ═══ §C set_my_phone learns the gate ═══
--
-- ⚠ THIS IS A `create or replace` OF A FUNCTION FIRST DEFINED IN 0133, so the explicit ACL below
--   is MANDATORY and is not decoration. `create or replace` preserves the ACL only if the function
--   already exists; on a partial prior apply, a branch that never ran 0133, or a rebuilt
--   environment, this statement is a plain CREATE and the definer is born PUBLIC-executable
--   (0116:636). `check-definer-acl.mjs` refuses precisely this shape when the file does not set
--   the ACL itself, and it is right to.
--
-- ⚠ WHAT CHANGED, so a reviewer can diff it in their head: exactly ONE new conjunct — the flag
--   check — placed AFTER the party gate and BEFORE anything else. Everything below it is 0133's
--   body unchanged, comments included, because a reviewer should be able to see that the
--   normalisation, the empty-string refusal (Sean §10 ④) and the tombstone WHERE are untouched.
--
-- ⚠ ORDER MATTERS AND IS DELIBERATE. Party gate, then the collection gate, then format. If the
--   flag check sat after the regex, someone typing a valid number into a build whose server has
--   collection closed would be told their number is invalid — a false statement about THEIR data
--   in place of a true statement about OUR rollout. `phone_collection_closed` is its own token so
--   the client can say the true thing.
create or replace function set_my_phone(p_phone text)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_digits text; v_n int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- [0154 §C] THE SHIP GATE, as a database fact. Contract §8: nothing may collect a phone number
  -- until counsel's revised 개인정보처리방침 exists in-app. Until Sean sets
  -- ops_flags.phone_collection_live_since this refuses every caller, including our own client.
  if not phone_collection_live() then raise exception 'phone_collection_closed'; end if;

  -- NORMALISE, then validate — in that order, so a human typing 「010-8900-0091」 or
  -- 「+82 10 8900 0091」 succeeds rather than being told their own number is invalid.
  v_digits := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  -- A digit string opening with 82 is the country code: Korean mobile numbers begin 01, so this
  -- cannot collide with a real local number.
  if left(v_digits, 2) = '82' then v_digits := '0' || substr(v_digits, 3); end if;

  -- The SAME regex as 0133 §A's CHECK. If these two ever disagree the constraint raises 23514 at
  -- the write and the user is shown a database error instead of a sentence.
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
revoke execute on function set_my_phone(text) from public, anon;
grant execute on function set_my_phone(text) to authenticated;

comment on function set_my_phone is
  '0133, gated by 0154 §C: the ONLY write path to profiles.phone for authenticated. No target
parameter — it writes auth.uid()''s row, so the party gate is structural rather than a predicate.
REFUSES with phone_collection_closed while ops_flags.phone_collection_live_since is null (or
future-dated, or the row is missing) — that is the contract §8 ship gate made enforceable rather
than remembered. Then normalises to digits (rewriting a leading +82/82 to 0) and validates against
the same regex as profiles_phone_shape; raises invalid_phone rather than no-opping, and no_profile
on a tombstoned or absent row. The column stays NULLABLE deliberately: the profile row is INSERTed
at the role-select screen BEFORE onboarding runs, so NOT NULL would abort the launch path itself.';

-- ═══ §D my_phone — so a person can see the number they are editing ═══
--
-- 🔴 WHY THIS IS NOT A GRATUITOUS DISCLOSURE, and why the slice needs it. Sean's §10 ④ ruling is
--   「Editable, but never blank」, and editing requires knowing what is there. `authenticated` has
--   **no SELECT grant on `phone`** (0088:135 grants id/name/handle/avatar_url/district; 0091:180
--   adds role; nothing else) — so without this function the entry screen shows an EMPTY FIELD to
--   somebody who already has a number saved. That is not a blank; it is a **fabricated claim about
--   their own data**, and it is the shape the honesty laws exist to forbid (loading is not 0; an
--   unknown must not render as a known).
--
--   The narrowness is the whole design: no parameter, so it can only ever answer about
--   `auth.uid()`. It hands a person their own number and nobody else's. The column grant stays
--   shut, so `127 W2`, `166 P6` and `185 W1` are all still true afterwards.
--
-- ⚠ NULL means ONE thing here: 「signed in, row exists, no number saved」. 「Not signed in」 and
--   「no row / tombstoned」 raise instead, because a client that cannot tell those apart draws
--   「번호를 등록해 주세요」 at a deleted account. Three states, three answers.
--
-- ⚠ NOT gated on phone_collection_live(). Reading back your own stored number is not collection,
--   and a person whose number exists must be able to see it even if we later close the flag.
--   Changing it is what the flag governs, and §C is where that lives.
create or replace function my_phone()
returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_phone text; v_found boolean := false;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select p.phone, true into v_phone, v_found
    from profiles p where p.id = auth.uid() and p.deleted_at is null;
  -- ⚠ `is not true`, NEVER a bare `if not v_found`. On a zero-row SELECT INTO, plpgsql sets EVERY
  --    target to NULL — including this flag — and `if not NULL` does not fire. The bare form would
  --    fall through and RETURN NULL for a tombstoned account, i.e. answer 「no number saved」 to a
  --    deleted profile: the exact NULL-collapse this repo has now measured five times, in a guard
  --    whose entire job is to notice that something is MISSING.
  if v_found is not true then raise exception 'no_profile'; end if;
  return v_phone;
end $$;
revoke execute on function my_phone() from public, anon;
grant execute on function my_phone() to authenticated;
grant execute on function my_phone() to service_role;

comment on function my_phone is
  '0154 §D: returns auth.uid()''s OWN phone number and nobody else''s — there is no parameter, so
the party gate is structural. Exists because authenticated has no SELECT grant on profiles.phone
(0088:135, 0091:180) and an entry screen that cannot read the stored value renders an empty field
to a person who already has a number, which is a fabricated blank. NULL = signed in, row present,
no number. not_signed_in / no_profile RAISE, so the three states stay distinguishable.';

-- ═══ §E VERIFY — apply-time, and NOT a substitute for suite 185 ═══
-- These two are different kinds of evidence and neither is evidence for the other: VERIFY says
-- 「the apply produced this shape」, the suite says 「the property holds and a mutation breaks it」.
-- A property checked only at apply is protected exactly until someone recreates the function
-- (0131-G4's lesson).
do $$
declare v_bad text := '';
begin
  -- ① the flag ships CLOSED. If this ever aborts an apply, somebody armed collection in a
  --    migration, which is Sean's act and not a file's.
  if (select phone_collection_live_since from ops_flags limit 1) is not null then
    v_bad := v_bad || ' flag-ARMED-at-apply';
  end if;
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' reader-OPEN'; end if;

  -- ② the ACLs this file is obliged to set explicitly, all three functions.
  if has_function_privilege('anon', 'set_my_phone(text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-can-set_my_phone'; end if;
  if not has_function_privilege('authenticated', 'set_my_phone(text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-lost-set_my_phone'; end if;
  if has_function_privilege('anon', 'phone_collection_live()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-can-read-flag'; end if;
  if has_function_privilege('anon', 'my_phone()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-can-my_phone'; end if;
  if not has_function_privilege('authenticated', 'my_phone()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-missing-my_phone'; end if;

  -- ③ the column grants this slice routes AROUND must still be shut. A file that added the
  --    switch and quietly widened the grant would satisfy every sentence above.
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'UPDATE')
    then v_bad := v_bad || ' authed-UPDATE-phone'; end if;
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'SELECT')
    then v_bad := v_bad || ' authed-SELECT-phone'; end if;

  -- ④ all three definers carry an in-body search_path (98 H1's obligation, checked here too so a
  --    bad apply fails loudly rather than waiting for the sweep).
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'phone_collection_live'
                    and p.prosecdef and p.proconfig::text like '%search_path%')
    then v_bad := v_bad || ' flag-reader-no-search_path'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'my_phone'
                    and p.prosecdef and p.proconfig::text like '%search_path%')
    then v_bad := v_bad || ' my_phone-no-search_path'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'set_my_phone'
                    and p.prosecdef and p.proconfig::text like '%search_path%')
    then v_bad := v_bad || ' set_my_phone-no-search_path'; end if;

  if v_bad <> '' then raise exception '0154 VERIFY FAILED:%', v_bad; end if;
end $$;
