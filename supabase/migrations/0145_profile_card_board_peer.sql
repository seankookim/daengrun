-- ═══ 0145: the board's tap is a dead end for everyone who is not a runner — the cause is a ROW
--          rule, so a ROW rule is what changes ═══
--
-- 0139 put `owner_profile_id` / `runner_profile_id` on `club_session_board` so a row could route
-- to a profile (Sean, 2026-08-27: 「for the tap for profile, yes make it like instagram」). The
-- screen it routes to reads one `profiles` row. `profiles` has three SELECT policies — self
-- (0002:55), non-applicant runner (0002:56), tombstone (0115:727) — and a live non-runner is in
-- none of them. So the tap resolves to zero rows and the screen honestly says
-- 「이 프로필은 공개되어 있지 않아요」 for every owner and every dogless crew member on the board.
--
-- ⚠ MEASURED, not inferred, on the harness cluster against suite 172's own fixtures
--   (2026-08-27). `bpi_mem` is a club member who can read the board:
--     mem → non-runner owner (`bpi_owner`) rows : 0     ← the defect
--     mem → runner (`bpi_run`)            rows : 1
--     mem → self                          rows : 1
--   The board hands `bpi_mem` that owner's NAME and their id in the same call. The id is a
--   destination that leads nowhere.
--
-- ═══ §0a WHAT IS ACTUALLY BEING OPENED — the disclosure question, measured ═══
-- 「Does this reveal a NEW fact, or only unlock a screen for facts already granted?」 Both, and
-- the honest answer separates the two halves, because they are governed by different mechanisms:
--
--   COLUMNS — decided already, and NOT TOUCHED BY THIS FILE. `authenticated` holds column-level
--   SELECT on exactly six columns of `profiles`, measured on the applied schema rather than read
--   off a migration: `id, name, handle, avatar_url, district` (0088:135) + `role` (0091:180).
--   `phone`, `toss_customer_key`, `created_at`, `updated_at`, `deleted_at` and every future
--   column are outside it (0088 §A is a whitelist, so a new column is private by default). This
--   file adds NO grant and revokes none; §A refuses to apply if that set has moved, and §D
--   re-asserts it afterwards. **「not one column more」 is therefore enforced by construction
--   here, not by my discipline** — a policy physically cannot widen a column grant.
--
--   ROWS — the half that is genuinely missing, and the only thing this file changes.
--
--   So, per person, the incremental disclosure to a caller who can already read the board:
--     · `name`       — ALREADY DISCLOSED. `club_session_board` returns `owner_name` ungated on
--                      every dog row and every crew row (0139), and `club_session_roster`
--                      (0053:392) returns `name` + `avatarUrl` + `profileId` for every session
--                      person to any host/full shell holder.
--     · `avatar_url` — already disclosed to host/full via the roster; NEW to the wider board
--                      audience for owners and crew (the board carries `runner_photo_url` only).
--     · `handle`     — NEW. It is the Instagram-style public account id (0074 §A; 0088:135's own
--                      note: 「it is meant to be seen」), it is already read cross-user for feed
--                      post authors (`api.ts` `fetchFeed` embeds `handle`), and it is the field
--                      Sean's 「like instagram」 model puts in the id bar. It is the point.
--     · `district`   — NEW. A 동 name. The club the caller shares with this person IS a district
--                      club (`club_request_district`), so this is close to already-known, but not
--                      identical, and it is named as a real disclosure rather than waved past.
--     · `role`       — NEW, and it rides along because a POLICY CANNOT BE PER-COLUMN. It is
--                      `owner`|`runner`. 0091 §E⑤ already recorded its privacy cost as 「~zero:
--                      a runner is already listed publicly in runners/available_runners」. Stated
--                      here because it is the one column the screen does not ask for.
--
--   NOTHING ELSE MOVES. No phone, no address, no money, no incident, no health/breed, no booking
--   history. Those live in other tables behind their own RLS and their own definers, none of
--   which consult this policy, and 0139 already measured that they refuse an authenticated
--   caller whatever profile id they hold.
--
-- ═══ §0b THE SHAPE: A SCOPED RLS POLICY, NOT A NEW DEFINER — decided, with the losing case ═══
-- A `security definer` returning a flat whitelisted row was the obvious alternative and is
-- rejected for three measured reasons:
--
--  ① **`profiles` row visibility is ALREADY an RLS question, in three places.** Self, runner and
--     tombstone are policies. A definer would be a FOURTH, parallel answer to 「who may see a
--     profile row」 that must then be kept in sync with those three by memory — the 「a rule copied
--     N times」 failure 0140 was written to stop. Worse, the client's one read
--     (`api.ts fetchProfileIdentity`, a plain `from('profiles').select(...)`) would have to move
--     to the definer and would LOSE the self, runner and tombstone arms unless the definer
--     re-implemented all three; 0115 built the tombstone arm deliberately so a departed
--     counterparty renders as 「탈퇴한 사용자」 instead of blank.
--  ② **The column ceiling already exists.** A definer's advantage is naming its columns; here the
--     grant names them, for every caller and every query shape at once, and has since 0088. The
--     only column a definer would additionally hide is `role`, whose cost 0091 already measured
--     as ~zero. That is a small prize for a second source of truth.
--  ③ **A definer would not fix the thing.** This migration is supposed to make the tap work. With
--     a definer the screen stays broken until a client slice lands; with a policy the shipped
--     `fetchProfileIdentity` starts returning the row it already asks for, unmodified.
--
-- ⚠ **CONSEQUENCE OF THE ROW SHAPE, NAMED RATHER THAN DISCOVERED LATER.** A row policy is read by
--   every `profiles` query, so three other already-shipped client surfaces that read these same
--   rows stop degrading for these same people: club chat sender names (`fetchClubChat`, today
--   falls back to 「참가자」), incident participant names (`fetchIncidentDetail`, same fallback),
--   and the feed author embed (`profiles!feed_posts_author_id_fkey`, today an empty author for a
--   non-runner poster). That is the SAME hole in three more places, and it is a partial repair,
--   not a complete one: a chat sender who is `limited` (an applicant whose delegation was
--   rejected) is on no board and still renders as 「참가자」. Recorded as an effect of the shape —
--   it is not a widening beyond what §0c defines, because those surfaces read exactly the rows
--   and exactly the columns defined below.
--
-- ═══ §0c THE PREDICATE: 「the board already told me this id」, delegated rather than copied ═══
-- The gate is not club membership and must not be. **Measured**: 0048 §R4 abolished RSVP
-- auto-join (「멤버십 자동 가입 폐지 — 게스트 RSVP 1급」), so the latest `session_rsvp` (0134) and
-- `session_delegate_dog` (0048) write NO `club_members` row. The people whose taps are broken —
-- owners who delegated, crew who RSVP'd — are frequently not members at all, so a co-membership
-- predicate would fail on precisely the rows this file exists to fix. It would also be WIDER
-- where it did apply, since `club_join(p_club)` (0048:197) admits any authenticated caller to any
-- club in one call.
--
-- So the predicate asks the board itself:
--
--     `_profile_board_visible(t)` = there is a session whose board, READ AS ME, hands me `t`
--                                  as `owner_profile_id` or `runner_profile_id`.
--
-- It CALLS `club_session_board` rather than re-stating its WHERE clause. `auth.uid()` is a GUC
-- and SECURITY DEFINER does not change it, so the board applies its own viewer gate (club member
-- of that session's club, or `_club_shell_access <> 'none'`), its own row filter, and its own
-- 🔴 R3 runner-name gate to ME. Three properties fall out, and the third is the reason for the
-- shape:
--   · **Exact.** Not 「approximately what the board shows」 — the board's output, by definition.
--   · **Drift-proof.** A later change to what the board renders changes this predicate in the
--     same commit, with no second copy to forget. 0139's R3 conjunction is inherited whole: a
--     third party is handed NULL for a pick-pending runner, so `t in (owner_id, runner_id)` is
--     false and no card opens — the courtship leak cannot arrive one hop later through here.
--   · **Errors fall CLOSED.** The `union` sub-select is a CANDIDATE set only — a cheap superset
--     of 「sessions this person has any row in」, used to bound the scan. Correctness is entirely
--     the board's. So the failure mode of a stale candidate set is 「a card that should open does
--     not」, never 「a card opens that should not」. Suite 177 P2 is written against the board's
--     OUTPUT precisely to catch that direction.
--
-- ⚠ **THE NULL-uid ARM IS LOAD-BEARING.** `club_session_board`'s gate is
--   `if v_uid is not null and not (…) then return; end if` — with a NULL `auth.uid()` it skips
--   the gate and returns the WHOLE board (169 P18 pins that as deliberate). Delegating to it
--   inherits that exemption, so `auth.uid() is not null` is written explicitly. **MEASURED, and
--   the measurement corrected the first draft of this paragraph:** the conjunct appears TWICE —
--   in §B's body and in §C's policy — and removing EITHER one alone reddens nothing (M3, M3c),
--   because an AND is order-independent for truth even where the planner will not short-circuit.
--   Removing BOTH gives `NULL-uid sees 3 cards` on 177 P5 (M3b). So: the hole is real, the pin is
--   not blind, and the redundancy is deliberate — but no single line here may be described as
--   「the only thing standing between」, and this file does not describe it that way.
--
-- ═══ §0d INACTION — what happens if nobody ever does anything ═══
-- Asked in the form the house requires: this grant is justified as 「it is open exactly while the
-- board shows you this person」, so — what if the board never stops showing them?
--   Then the card stays open, and that is CORRECT rather than a stranded grant, because the two
--   are the same fact: there is no clock, no second lifetime and no state anyone must transition.
--   The card cannot outlive the board row by one second in either direction, and nobody has to
--   act for it to be right. It closes when the board drops the row (a delegation rejected or
--   withdrawn, a dog ended with no booking) — 177 P6 measures a card that is open under
--   `approval='pending'` and shut after `session_approve_dog(…, false)`, i.e. closed by the
--   board's own act and not by anything this file schedules.
--   ⚠ **It does NOT close for crew.** A `session_people` row has no expiry, and `club_session_board`
--   renders crew with no time filter, so somebody who ran with you once is visible to you
--   indefinitely. That is a property of Sean's 「always fine; it's like a public dashboard」 board,
--   inherited, not created here — and it is the honest reason to delegate rather than invent a
--   narrower lifetime this file has no authority to choose.
--
-- ═══ §0e COST ═══
-- A SECURITY DEFINER cannot be inlined, so this is a function call per candidate `profiles` row,
-- and each call runs `club_session_board` once per session the TARGET has a row in. Measured
-- mitigation: `uuid_eq` is `proleakproof = true` (checked on the applied cluster), so the planner
-- may apply `id = $1` / `id in (…)` BEFORE the RLS qual — and both real call shapes
-- (`fetchProfileIdentity`'s `.eq('id', …)` and the chat/incident `.in('id', ids)`) are exactly
-- that. A person with no club rows costs nothing: the candidate set is empty and the board is
-- never called. If these tables ever grow, the fix is a materialised peer set, not a wider
-- policy — 0131 §COST records the same trade for the same reason.
--
-- ═══ §0f WHAT THIS FILE DOES NOT DO ═══
-- - No grant, no revoke on `profiles`. No column moves. §A aborts if the ceiling has changed.
-- - No change to `club_session_board`, `club_session_roster`, or any existing policy. It creates
--   ONE function and ONE policy; REGISTRY 「what it recreates」: NONE.
-- - It does not touch writes. `profiles self write` / `self insert` are untouched.
-- - It does not open anything for `anon`. The policy is `to authenticated` (0131 measured why
--   that is load-bearing and not cosmetic), and `anon` holds no column grant on `profiles` at all
--   after 0088/0093.
-- - It does not make anyone tappable who is not already NAMED to the caller by the board.
--
-- ═══ §0g DOCTRINE ═══
-- Mutation-proven pins in `177_profile_board_peer_suite.sql` (P1-P7). Pins this file must not
-- break: 124 G1-G8 (0088's column wall), 127 W1-W9 (0091's write wall), 150 N5 (0115's tombstone
-- arm), 169 P1-P21 + 172 I1-I4 (the board's own gates), 98 H1 (in-body search_path), 99 S1
-- (anon-executable sweep).

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- §A PRE-CHECK — fail closed BEFORE changing anything.
-- This file's entire privacy argument is 「the columns were decided elsewhere; I only decide
-- rows」. If either half of that premise has moved, the argument is stale and the file must
-- abort rather than apply on top of an assumption nobody re-read.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare v_cols text; v_pols text; v_n int;
begin
  -- ① The column ceiling, read as PRIVILEGE and not as migration text.
  select coalesce(string_agg(column_name, ',' order by column_name), '')
    into v_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'profiles'
     and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_cols <> 'avatar_url,district,handle,id,name,role' then
    raise exception '0145 A: authenticated SELECT columns on profiles are [%], expected the 0088+0091 set. This file argues about ROWS on the assumption that COLUMNS are already settled — re-scout before applying.', v_cols;
  end if;

  -- ② `anon` must hold nothing. If it does, `to authenticated` is not the whole story.
  select count(*) into v_n
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'profiles' and grantee = 'anon';
  if v_n <> 0 then
    raise exception '0145 A: anon holds % column privileges on profiles; expected 0 (0088 §D / 0093).', v_n;
  end if;

  -- ③ The known SELECT policies, by name. A fourth one already present means someone has
  --    widened row visibility since this file was written.
  select coalesce(string_agg(p.polname, ',' order by p.polname), '')
    into v_pols
    from pg_policy p join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'profiles' and p.polcmd = 'r';
  if v_pols <> 'profiles public runner read,profiles self read,profiles tombstone read' then
    raise exception '0145 A: profiles SELECT policies are [%], expected the three known arms (0002:55, 0002:56, 0115:727).', v_pols;
  end if;

  -- ④ The authority this file delegates to. If the board stopped being a SECURITY DEFINER it
  --    would start obeying RLS on `profiles`, and the predicate below would recurse.
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_session_board' and p.prosecdef;
  if v_n <> 1 then
    raise exception '0145 A: expected exactly one SECURITY DEFINER public.club_session_board, found %.', v_n;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- §B THE PREDICATE.
-- `set search_path` is IN THE BODY, not ALTER-applied — ALTER-applied config is reset by
-- `create or replace` (test 98 H1 fails the harness on any omission).
-- The revoke is EXPLICIT and in this same file: `create or replace` preserves an ACL only where
-- the function already exists, and on a partial-apply or rebuilt environment it is a plain CREATE
-- whose definer is born PUBLIC-executable (0116:636). Never rely on preservation.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public._profile_board_visible(p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- NOT an arbitrary-pair oracle: the viewer is fixed to auth.uid() because every authenticated
  -- user holds EXECUTE (an RLS policy evaluates its predicate AS the querying role), so a
  -- (viewer, target) signature would let anyone probe anyone else's board membership.
  --
  -- 🔴 `auth.uid() is not null` IS NOT DECORATION. club_session_board's own guard is
  --    `if v_uid is not null and not (…) then return`, so a NULL uid skips it and receives the
  --    ENTIRE board (169 P18 pins that as deliberate). With this conjunct removed HERE AND in the
  --    policy, 177 P5 measures `NULL-uid sees 3 cards`. It is deliberately written in both
  --    places; neither copy alone is 「the」 guard, and removing either alone reddens nothing.
  select p_target is not null
     and auth.uid() is not null
     and exists (
       select 1
         from (
           -- CANDIDATE SET ONLY — a cheap superset of 「sessions this person has a row in」, whose
           -- job is to bound the scan. It decides nothing: the board below decides everything.
           -- Being too NARROW here loses a legitimate tap (177 P2 catches it); it cannot open a
           -- card, because the board still has to hand the id back.
           select sp.session_id from session_people sp where sp.profile_id = p_target
           union
           select sd.session_id from session_dogs sd
            where p_target in (sd.owner_profile_id,
                               sd.current_runner_profile_id,
                               sd.proposed_runner_profile_id)
         ) cand
        cross join lateral public.club_session_board(cand.session_id) b
        -- READ AS ME. The board applies its viewer gate, its row filter and its R3 runner-name
        -- gate with my auth.uid(); a pick-pending runner comes back NULL to a third party, so no
        -- card opens for a courtship this caller cannot already see.
        where p_target in (b.owner_profile_id, b.runner_profile_id)
     );
$$;

-- `from public, anon` — not `public` alone. `create or replace` preserves role-specific ACL
-- entries, so a pre-existing explicit anon grant would survive a PUBLIC-only revoke silently.
-- `authenticated` keeps EXECUTE because the policy below evaluates this AS the querying role.
-- `service_role` is granted for parity with 0131's helper; it bypasses RLS and never needs it.
revoke all on function public._profile_board_visible(uuid) from public, anon;
grant execute on function public._profile_board_visible(uuid) to authenticated, service_role;

comment on function public._profile_board_visible(uuid) is
  'RLS predicate for `profiles` (0145): true when club_session_board, read as the CALLER, hands '
  'the caller this profile id. Delegates to the board rather than copying its WHERE, so the '
  'answer cannot drift from what the caller was already shown. Grants nothing by itself.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §C THE ARM.
-- `to authenticated` follows 0131 §C, where a policy left at PUBLIC made an anonymous read raise
-- `permission denied for function` instead of returning zero rows (the planner may evaluate a
-- helper call before a uid guard in the same chain).
-- ⚠ **MEASURED HERE, AND IT IS NOT THE SAME STORY — recorded rather than borrowed.** Planting the
-- PUBLIC form on THIS table gives anon `42501: permission denied for TABLE profiles`, never the
-- function, because 0088/0093 leave anon with zero column privileges on `profiles` and the
-- relation-level check fires before RLS is evaluated. 0131's four tables had no such wall, which
-- is why it bit there and not here. `to authenticated` is kept as defence in depth — it means the
-- helper is unreachable on the anon path by policy AND by grant — but this file must not claim
-- it is what saves anon, because on this table it demonstrably is not (177 P7 asserts the
-- refusal's SOURCE for exactly that reason).
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "profiles board peer read" on profiles;
create policy "profiles board peer read" on profiles for select to authenticated
  using (auth.uid() is not null and public._profile_board_visible(id));

comment on policy "profiles board peer read" on profiles is
  '0145: the fourth SELECT arm — a person the club session board already NAMES to you. Sean '
  '2026-08-27 「for the tap for profile, yes make it like instagram」 made board rows destinations '
  '(0139); this makes the destination exist for the non-runners, who were the only dead ends. '
  'Rows only — the disclosed columns are 0088:135 + 0091:180 and this file changes no grant.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §D VERIFY — fail closed AFTER. Every claim §0 makes about the shipped state, executed.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare v_n int; v_b boolean; v_cols text;
begin
  -- ① in-body search_path (98 H1's law, asserted locally so a bad apply dies here)
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_profile_board_visible'
     and p.prosecdef and p.proconfig @> array['search_path=public, pg_temp'];
  if v_n <> 1 then raise exception '0145 D: _profile_board_visible is not a SECURITY DEFINER with in-body search_path.'; end if;

  -- ② the ACL, both directions
  select has_function_privilege('public', 'public._profile_board_visible(uuid)', 'execute') into v_b;
  if v_b then raise exception '0145 D: _profile_board_visible is PUBLIC-executable.'; end if;
  select has_function_privilege('anon', 'public._profile_board_visible(uuid)', 'execute') into v_b;
  if v_b then raise exception '0145 D: _profile_board_visible is anon-executable.'; end if;
  if not has_function_privilege('authenticated', 'public._profile_board_visible(uuid)', 'execute') then
    raise exception '0145 D: authenticated cannot execute _profile_board_visible — every profiles read would raise 42501.';
  end if;

  -- ③ the policy exists in the shape §C describes: permissive, SELECT, authenticated only
  select count(*) into v_n
    from pg_policy p join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'profiles'
     and p.polname = 'profiles board peer read'
     and p.polcmd = 'r' and p.polpermissive
     and p.polroles::regrole[] = array['authenticated']::regrole[];
  if v_n <> 1 then raise exception '0145 D: the new policy is missing or not the permissive SELECT/authenticated shape.'; end if;

  -- ④ THE COLUMN CEILING IS UNMOVED. This file must not be the one that widened it.
  select coalesce(string_agg(column_name, ',' order by column_name), '')
    into v_cols
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'profiles'
     and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_cols <> 'avatar_url,district,handle,id,name,role' then
    raise exception '0145 D: authenticated SELECT columns on profiles ended as [%] — this file must move ROWS ONLY.', v_cols;
  end if;
end $$;

commit;
