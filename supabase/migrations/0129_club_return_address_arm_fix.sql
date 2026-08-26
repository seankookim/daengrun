-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0129 — the club return-address arm, CORRECTED. Mode columns + a six-conjunct custody arm.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Contract: `docs/contracts/club-return-address-arm-contract.md` — read CONTRACT v2 and the two
-- corrections after the horizontal rules, not just §0-§5 above them. Sean, 2026-08-25: 「go ahead
-- with the address fix」; after the review, 「fix it and re-review」.
--
-- ── WHY THIS IS A FOLLOW-UP AND NOT AN EDIT ─────────────────────────────────────────────────
-- `0128_club_return_address_arm.sql` IS ON TRUNK (`git ls-tree origin/redesign-v4` lists it).
-- Production is still 0127, so nothing is deployed — but 0128 is history, and history is
-- corrected forward. Nothing in this file edits 0128; it recreates the one function 0128
-- recreated, with the arm the reviews demanded, and adds the two columns that arm needs.
--
-- ── WHAT TWO BLIND REVIEWS FOUND IN 0128's ARM ──────────────────────────────────────────────
-- 0128's arm was `custody = 'runner_delegated' and custody_phase = 'return_pending' and
-- custodian_profile_id = auth.uid()`. Four defects, each fixed by exactly one conjunct below.
--
--   🔴 CRITICAL — IT LEAKS A HOME THAT HAS NO HOME LEG. The product model permits
--      `pickup_mode = 'owner_home'` WITH `return_mode = 'session_finish'` (spec §7.2a, the four
--      combinations table), and in that pairing `bookings.address_id` IS SET — for the PICKUP leg
--      only. So: owner picks home pickup + on-site return → sign-up writes the home →
--      `completed` → the runner, already standing at the finish, calls the RPC and gets the
--      owner's home. 0128's own reasoning ("a pairing with `address_id` NULL returns 0 rows
--      regardless") covers only the both-legs-on-site row of that table. The mixed row defeats
--      it, and the mixed row is the ordinary one.
--      → FIXED BY `sd.return_mode = 'owner_home'`, and the column has to exist for that, which
--        is why this migration carries BOTH halves. Landing the columns and the arm separately
--        would open a window in which addresses are written against the broad arm — the leak
--        itself.
--
--   🔴 MAJOR — A PHASE LIST STRANDS A DOG. `session_transfer_initiate` (0057:317,331) moves the
--      phase to `transfer_pending` while THE RUNNER STILL PHYSICALLY HOLDS THE DOG. 0128 admitted
--      only `return_pending`, so a runner mid-transfer lost the destination — the exact
--      strand-an-animal failure this slice exists to prevent.
--      → FIXED BY `sd.custody_phase <> 'resolved'`. ⚠ THE NEGATIVE FORM IS THE DESIGN DECISION,
--        NOT A SHORTCUT, AND A FUTURE SESSION MUST NOT "TIGHTEN" IT BACK INTO A LIST. The
--        property the arm must express is 「this caller is holding this dog and it has not been
--        returned」, not 「the row is in one of the phases I happened to think of」. A list is how
--        the `transfer_pending` hole was made; the next phase nobody thinks of makes it again.
--        `resolved` is written only by the return seal (0045:106) and nothing transitions out of
--        it, so the negative form is narrower in intent and wider in coverage at once.
--
--   🔴 F1 — IT NEVER CLOSES WHEN THE RUNNER SIMPLY NEVER CONFIRMS. Owner stamps 「I have my dog」;
--      the runner never taps. `session_confirm_return` only seals when BOTH stamps exist
--      (0045:106), so the phase stays `return_pending` forever — no sweep, and
--      `session_host_force_resolve` refuses at `completed` (0069:207, `not_stuck`). And this is a
--      LIVE read: the owner moves house, edits the address row, and the runner who never
--      confirmed sees the new address.
--      → FIXED BY `sd.owner_confirmed_return_at is null`. Argued, because a timeout was the
--        tempting alternative: **the owner's own stamp is the honest signal that the dog is
--        back.** A clock has to choose between stranding a genuinely delayed runner and leaving a
--        stale grant open; the counterparty asserting possession is neither guesswork nor a
--        deadline.
--      ⚠ **WHAT REMAINS DELIBERATELY UNBOUNDED, SAID OUT LOUD:** if NEITHER side confirms, the
--        runner keeps the destination indefinitely — because in that state the dog genuinely has
--        not been returned and the runner may still need to deliver it. That is the
--        strand-prevention choice, made knowingly. It is NOT a hole for a future sweep to close;
--        a sweep would take the address away from someone still holding an animal. Suite 163's
--        P9 pins the case so nobody "fixes" it by accident.
--
--   🟡 MODERATE — 「club-only by construction」 WAS A CONVENTION, NOT A CONSTRAINT.
--      `session_dogs.session_id` and `.booking_id` are independent FKs (0030:81,86); nothing
--      requires the booking's `club_session_id` to equal the row's session. The normal mint is
--      consistent (0081:184) but the schema permits otherwise.
--      → FIXED BY `sd.session_id = b.club_session_id`. It also makes the marketplace exclusion
--        structural rather than incidental: a marketplace booking has `club_session_id` NULL, so
--        the comparison is NULL, `exists` is false, and the arm cannot be reached at all.
--
-- ── WHAT 0128/0065 GOT RIGHT AND THIS FILE PRESERVES BYTE-FOR-BYTE ──────────────────────────
--   ① ONE `raise exception 'not_runner'` and ONE `not_runner` literal in the whole body. Absent
--      booking / foreign booking / wrong status / wrong mode / wrong custodian are
--      indistinguishable (0054:73 oracle doctrine). The arm is a disjunct inside the SAME
--      boolean, never a second raise site.
--   ② The poisoned-row guard `a.owner_id = b.owner_id` in the body — a mismatched address yields
--      0 rows, never an error.
--   ③ Flat 5-column return label/addr/detail/lat/lng, in that order.
--   ④ `security definer` + `set search_path = public, pg_temp` IN THE BODY (ALTER-applied config
--      is wiped by `create or replace` — measured; 98 H1 sweeps the schema for it).
--   ⑤ Explicit ACL, written and not inherited. This function was FIRST defined in 0060, so on any
--      database where it is absent the statement below is a plain CREATE and the function would
--      be born PUBLIC-executable (0116:636). `check-definer-acl.mjs` refuses this file without
--      the pair.
--      🔴 NEW IN 0129: **`service_role`'s EXECUTE grant is written explicitly — and the CONTRACT'S
--      REASON FOR IT IS FALSE.** Contract v2 §C says the grant 「is INHERITED through
--      `create or replace` and would vanish on the absent-function CREATE path」. **Measured, it
--      would not.** `pg_default_acl` in this schema carries `{service_role=X/postgres}` for object
--      type `f`, so EVERY newly created function is born service_role-executable; dropping
--      `booking_pickup_address` and applying this file with the grant line deleted still yields
--      `{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}`. The repo already
--      recorded this at `0057:59` — 「service_role은 EXECUTE를 **PUBLIC이 아니라** Supabase 함수
--      default privileges로 받는다」 — and the contract (mine) restated it wrongly anyway. That is
--      the ⚠ 「a green light is evidence for exactly one sentence」 law in its other direction: an
--      assertion written for a threat that does not exist.
--      **The line stays, for the reason that survives measurement:** a default ACL is a property
--      of the ENVIRONMENT — a role's default privileges in that database — not of this file. Every
--      other role's access to this function is decided here; leaving one role to an environment
--      setting means a database provisioned without it (a self-hosted rebuild, a restore that does
--      not carry `pg_default_acl`, a future platform change) silently differs from this file's
--      intent, and nothing would say so. One line closes that, and VERIFY ③'s service_role arm
--      then guards the direction that IS reachable: an over-revoke, which is exactly how the
--      `authenticated` arm earns its place too. ⚠ Measured, and stated so nobody re-derives the
--      false version: that arm CANNOT be made to fire by deleting the grant; it fires on an
--      explicit `revoke ... from service_role`.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT DO ─────────────────────────────────────────────────
-- No change to `session_confirm_return`, `session_custody_override`,
-- `_club_custody_transition_v2`, `session_transfer_initiate/accept`, or any return RPC — VERIFY
-- ⑥ pins two of their bodies by DIGEST, not by name. No writer for the two new columns: the mode
-- is an owner CHOICE captured at club sign-up, and the sign-up slice owns the RPC that records
-- it. `session_dogs` carries a SELECT-only RLS policy (0030:136) and no client write policy, so
-- the columns are server-authored from birth and this file adds no write surface. No marketplace
-- change of any kind.
--
-- ── ⚠ TWO THINGS THE VERIFY BLOCK STRUCTURALLY CANNOT SEE — named, so its green is not misread ─
-- The 🔴 law of 2026-08-25: a green light is evidence for exactly ONE sentence. VERIFY's textual
-- arms (④/⑤ below) prove the SHAPE of the body, and shape is not behaviour. Two bodies pass every
-- assertion in this file while being wrong:
--   1. **A CONSTANT-NULL STUB CARRYING THE MAGIC WORDS IN COMMENTS.** `prosrc like '%return_mode%'`
--      matches a comment. A body that gates correctly and then returns `select null,null,null,
--      null,null` keeps all five OUT columns, keeps one raise site, keeps the search_path pin —
--      and hands the runner nothing. Only a pin that asserts VALUES sees it (163 P1-b, and 0065
--      W6's recorded near-miss is the same shape).
--   2. **A SINGLE `raise` WHOSE MESSAGE IS A `case` EXPRESSION.** VERIFY ⑤ counts one
--      `raise exception` and one `not_runner` literal. `raise exception '%', case when <arm was
--      true but mode wrong> then 'wrong_mode' else 'not_runner' end` satisfies both counts and is
--      a working probing oracle. Only a pin comparing REAL SQLSTATE+message pairs to EACH OTHER
--      sees it (163 P7).
-- Neither gap is closed by adding another textual assertion; they are closed by suite 163, and
-- neither this block nor that suite is evidence for the other.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §1  session_dogs.pickup_mode / .return_mode — spec §7.2a, landed HERE so no window exists
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean ruled the model (spec §16.7, verbatim: *"then just do either on site or home address"*),
-- and struck this spec's own 「return mirrors pickup, same flag」: the return point is a choice the
-- owner makes FOR ITSELF. One two-valued flag expresses two of the four combinations, not four.
-- The 🔵 in §7.2a is over the NAMES only; the model is his.
--
-- ⚠ **`return_mode` DEFAULTS TO `owner_home`, AND THE DEFAULT MUST BE ARGUED RATHER THAN
-- ASSUMED** — it is the conjunct that fixes the Critical, and a default of `owner_home` makes it
-- TRUE BY DEFAULT, i.e. the new conjunct protects nothing on a row nobody has answered for. That
-- is correct and it is the SAFE direction, for one measured reason: there is no on-site-return
-- concept shipped, so every pairing that exists today has a home return in practice, and any
-- other default would silently REVOKE the destination for every in-flight club return the moment
-- this applies. The default preserves current meaning; it does not assert a choice nobody made
-- (that distinction is exactly why §7.2a refuses to derive `pickup_mode` from `address_id IS
-- NULL`). **The consequence, stated: the other four conjuncts carry the weight until the sign-up
-- slice starts writing real answers.**
--
-- NOT NULL + defaulted + CHECK-constrained, exactly as §7.2a's table specifies. The CHECKs are
-- named so a violation reports its own constraint name rather than an anonymous `$2`.
alter table session_dogs
  add column pickup_mode text not null default 'owner_home',
  add column return_mode text not null default 'owner_home';

alter table session_dogs
  add constraint session_dogs_pickup_mode_chk check (pickup_mode in ('owner_home', 'session_start')),
  add constraint session_dogs_return_mode_chk check (return_mode in ('owner_home', 'session_finish'));

comment on column session_dogs.pickup_mode is
  '0129 (spec §7.2a): where the OUTBOUND leg happens — `owner_home` (집 픽업, default) ·
`session_start` (현장 인계). Server-authored: session_dogs has a SELECT-only client policy
(0030:136), so this is written by the sign-up RPC, never by a client. Deliberately an explicit
column rather than derived from `bookings.address_id IS NULL`, because NULL is already overloaded —
`booking_pickup_address` returns 0 rows for 「주소 미지정」 AND for a poisoned row (0065:58-59), so a
NULL address cannot distinguish 「the owner chose on-site」 from 「the owner has not answered yet」,
and a screen rendering 현장 인계 off an absent address would assert a choice nobody made.';

comment on column session_dogs.return_mode is
  '0129 (spec §7.2a, Sean 2026-08-25): where the RETURN leg happens — `owner_home` (집 반환,
default) · `session_finish` (현장 반환). ⚠ NOT a mirror of pickup_mode: Sean struck 「return mirrors
pickup, same flag」 and specified the return point as a choice the owner makes for itself, so
home-pickup + on-site-return is a combination an owner can want. **This column is load-bearing for
privacy, not only for UI.** `bookings.address_id` is SET for that mixed combination — for the
pickup leg only — so a return arm that does not read this column hands the owner''s home to a
runner standing at the finish line. That was 0128''s Critical; `booking_pickup_address`''s club arm
requires `owner_home` here. Default argued in 0129 §1: no on-site return is shipped yet, so
`owner_home` preserves current meaning rather than revoking every in-flight return.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §2  booking_pickup_address — 0128's body with the arm corrected on all four findings
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Everything outside the `or exists (...)` block is 0128:104-131 transcribed, which is itself
-- 0065:44-67. The return type is unchanged, so `create or replace` is legal (0065 needed a DROP
-- only because it widened the OUT columns 3 → 5, and that DROP is what cost it its grants).
--
-- ⚠ The parenthesisation is load-bearing and is kept from 0128: the marketplace conjunction is
-- wrapped so the custody arm binds at the TOP level of the predicate. `and` binds tighter than
-- `or`, so an unwrapped form would still be correct by precedence — but it would READ as though
-- the custody arm were another status, which is the misreading that produces a status-list
-- widening in the next edit.
--
-- NULL behaviour is unchanged and still fails closed. With no JWT `auth.uid()` is NULL, so
-- `b.runner_id = auth.uid()` is NULL and `sd.custodian_profile_id = auth.uid()` matches no row;
-- the whole predicate is NULL → `coalesce(..., false)` → `not_runner`. Same for a marketplace
-- booking reaching the arm: `b.club_session_id` is NULL, so `sd.session_id = b.club_session_id`
-- is NULL for every row and `exists` is false.
create or replace function booking_pickup_address(p_booking uuid)
returns table (label text, addr text, detail text, lat numeric, lng numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- party + state gate (absent / foreign / wrong status / wrong mode / wrong custodian all raise
  -- the SAME string — probing-oracle blocker, unchanged from 0060; the club arm is a disjunct
  -- inside this one boolean and never a second raise)
  if not coalesce((
        select (b.runner_id = auth.uid()
                and (b.status in ('runner_enroute', 'picked_up', 'active')
                     or (b.status = 'confirmed' and b.scheduled_at < now() + interval '24 hours')))
            -- [0129] the club return window. Six conjuncts; five of them close a measured defect —
            -- see this file's header for which review found which. Read as one sentence:
            -- 「this pairing belongs to this booking's club session, its dog was delegated, its
            --  return leg is a home leg, it has not been returned, its owner has not said the dog
            --  is home, and the caller is the one holding it.」
            or exists (
                 select 1 from session_dogs sd
                 where sd.booking_id  = b.id
                   and sd.session_id  = b.club_session_id       -- Moderate: club-only, structurally
                   and sd.custody     = 'runner_delegated'
                   and sd.return_mode = 'owner_home'            -- CRITICAL: the home leg must exist
                   and sd.custody_phase <> 'resolved'           -- MAJOR: not a phase list — "not yet returned"
                   and sd.owner_confirmed_return_at is null     -- F1: the owner said the dog is home
                   and sd.custodian_profile_id = auth.uid())
        from bookings b where b.id = p_booking), false)
  then
    raise exception 'not_runner';
  end if;

  -- unassigned (address_id null) · poisoned row (address owner ≠ booking owner)
  -- → 0 rows (not an error), unchanged from 0060/0065/0128
  return query
    select a.label, a.addr, a.detail, a.lat, a.lng
    from bookings b
    join addresses a on a.id = b.address_id
    where b.id = p_booking
      and a.owner_id = b.owner_id;
end $$;

-- ⚠ NOT optional and NOT inheritable — see invariant ⑤ in the header. The first two lines are
-- verbatim from 0065:69-70 / 0128:134-135. The third is new in 0129, and its reason is NOT the one
-- contract v2 §C gives: measured, service_role's EXECUTE comes from this database's function
-- DEFAULT PRIVILEGES (`pg_default_acl` type `f` = `{service_role=X/postgres}`, and 0057:59 already
-- said so), so it does not vanish on the absent-function path. It is written because a default ACL
-- is a property of the environment and not of this file — every other role's access is decided
-- here, and one role left to an environment setting is one role whose access this file cannot
-- claim to have decided.
revoke execute on function booking_pickup_address(uuid) from public, anon;
grant  execute on function booking_pickup_address(uuid) to authenticated;
grant  execute on function booking_pickup_address(uuid) to service_role;

comment on function booking_pickup_address is
  'Pickup/return address for the runner holding the dog (0060, widened by 0065, club arm 0128,
CORRECTED by 0129) — flat 5 fields label/addr/detail/lat/lng. Two ways in, one error out:
  · MARKETPLACE — that booking''s runner, in one of the 3 in-flight states, or `confirmed` and
    starting within 24h. Unchanged since 0060.
  · CLUB RETURN (0129) — the pairing belongs to this booking''s club session, is
    `runner_delegated`, has `return_mode = ''owner_home''`, is not `resolved`, has no
    `owner_confirmed_return_at`, and the caller IS its `custodian_profile_id`. The club keeps
    custody with the runner past `completed` (0045:55-60, 「정산 ≠ 반환」), so its whole return
    window sits outside the marketplace gate by construction; this arm is what lets the runner be
    navigated to the owner''s door.
    ⚠ NOT a status-list widening — `completed` alone would re-open every finished booking''s
      address forever. ⚠ NOT a phase LIST either: 0128 keyed on `return_pending` and thereby
      refused a runner mid-`transfer_pending` who was still holding the dog. ⚠ `return_mode` is
      not decoration: home-pickup + on-site-return carries `address_id` for the pickup leg, and
      without this conjunct the finish-line runner reads the owner''s home (0128''s Critical).
    It closes at the return seal (`custody_phase = ''resolved''`) OR at the owner''s own
    「my dog is home」 stamp, whichever comes first — no sweep, no expiry job, no flag.
    ⚠ If NEITHER side confirms, it stays open, deliberately: the dog has genuinely not been
      returned and the runner may still need to deliver it (163 P9 pins this).
Everything else raises not_runner (absent / foreign / wrong-status / wrong-mode / wrong-custodian
all indistinguishable — 0054:73 oracle doctrine; the club arm is a disjunct, never a second raise).
Unassigned address or owner mismatch → 0 rows, not an error.
lat/lng are NULL until the owner pins the address (client renders the honest dark state);
gate_code_enc remains structurally absent — decryption is its own slice.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — fail the apply closed, in both directions
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- A VERIFY runs once, at apply time; suite 163 is what outlives it. What this block is for is the
-- apply path the harness structurally CANNOT produce: a database where `booking_pickup_address`
-- was absent, so §2's statement was a CREATE rather than a replace. There, preservation never
-- happened, and without §2's explicit ACL lines the function would be born PUBLIC-executable
-- (0116:636) and service_role's grant would be gone.
--
-- 🔴 EVERY ASSERTION BELOW WAS PLANTED-AND-BROKEN ONCE (2026-08-26, against a copy of
-- `supabase/` outside the worktree — never by editing a live migration). An assertion never seen
-- to fail is a claim, not a check. The measurements are recorded in the commit message and in
-- 163's header.
--
-- Strengthened against 0128's VERIFY on the four points the blind review named:
--   · every catalog lookup keys on the EXACT `(uuid)` signature via `::regprocedure`, never on
--     `proname` — under `proname` an overload satisfies the check and the real function is never
--     looked at.
--   · the OUT columns are compared IN ORDER (array equality), not as a set — `label/addr` swapped
--     is a silent contract break that a set comparison cannot see.
--   · `search_path` is asserted to be EXACTLY `{search_path=public, pg_temp}` — one element, exact
--     string — rather than "some value containing pg_temp".
-- 🔴 And ONE ASSERTION MISSED ITS PLANT, which is recorded here rather than quietly re-worded:
-- the `service_role` arm could not be made to fail by DELETING the grant (see invariant ⑤ — the
-- default ACL supplies it), only by an explicit revoke. Both facts are stated at the assertion
-- itself, because an assertion whose stated purpose is not the purpose it can serve is the same
-- error as a green read too broadly.
--   · the return-machine check compares BODY DIGESTS, not the existence of a name. A disabled
--     trigger or a replaced body passed 0128's version.
do $$
declare
  v_oid oid; v_peer_oid oid;
  v_cols text[]; v_n int; v_src text; v_cfg text[]; v_secdef boolean;
  v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_owner oid; v_peer oid;
  v_md5_scr text; v_md5_tg text; v_tgen char;
  v_notnull boolean; v_default text;
  -- Digests of the 0045/0069 return machine as it stands at THIS point in the chain. A VERIFY
  -- observes the state at its own position in history, so a later migration that legitimately
  -- rewrites either body does not retroactively break this file.
  K_CONFIRM_RETURN constant text := '4a2be9767a74dee54e7581161db0a239';  -- session_confirm_return(uuid,text), 0069:84
  K_TRANSITION     constant text := 'fbaf7854bd6cedc74b71a299e8a10443';  -- _club_custody_transition_v2(), 0045:36
begin
  -- ── ① the EXACT signature exists, is a plpgsql SECURITY DEFINER, and pins search_path in-body ─
  -- `::regprocedure` RAISES if the exact `(uuid)` overload is absent, which is the point: a
  -- `proname` lookup is satisfied by any overload and would then assert properties of the wrong
  -- function. `set search_path` written into the HEADER lands in `proconfig` and survives
  -- create-or-replace; an ALTER-applied one does not (measured, 0055's lesson) — so its presence
  -- immediately after §2's statement is what proves it came from the body, because §2 would have
  -- discarded anything ALTER had put there.
  select p.oid, p.prosecdef, p.proconfig, p.prosrc, p.proowner
    into v_oid, v_secdef, v_cfg, v_src, v_owner
    from pg_proc p where p.oid = 'booking_pickup_address(uuid)'::regprocedure;
  if not v_secdef then
    raise exception '0129: booking_pickup_address lost SECURITY DEFINER';
  end if;
  if v_cfg is distinct from array['search_path=public, pg_temp'] then
    raise exception '0129: search_path is not exactly {search_path=public, pg_temp} (proconfig=%) — either the in-body pin is gone or something else set it', v_cfg;
  end if;

  -- ── ② the contract surface did not move: the 5 OUT columns 0065 shipped, IN ORDER ───────────
  select array_agg(a.n order by a.o) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
   where p.oid = v_oid and a.m = 't';
  if v_cols is distinct from array['label','addr','detail','lat','lng'] then
    raise exception '0129: the 5-column return contract moved (OUT columns in order = %)', v_cols;
  end if;

  -- ── ③ the ACL that ACTUALLY landed — the whole reason this block exists ─────────────────────
  -- Asked of the catalog, not of §2's three statements. On an absent-function apply those lines
  -- are the only thing between a definer and PUBLIC EXECUTE, and the only thing that keeps
  -- service_role's grant from vanishing with the preservation it used to ride on.
  select has_function_privilege('public',        v_oid, 'execute'),
         has_function_privilege('anon',          v_oid, 'execute'),
         has_function_privilege('authenticated', v_oid, 'execute'),
         has_function_privilege('service_role',  v_oid, 'execute')
    into v_pub, v_anon, v_auth, v_svc;
  if v_pub then
    raise exception '0129: booking_pickup_address is PUBLIC-executable — the revoke did not take (partial-apply CREATE path)';
  end if;
  if v_anon then
    raise exception '0129: anon can execute booking_pickup_address';
  end if;
  if not v_auth then
    raise exception '0129 OVER-REVOKE: authenticated cannot execute booking_pickup_address — every runner pickup screen is dead';
  end if;
  if not v_svc then
    raise exception '0129: service_role cannot execute booking_pickup_address — the explicit grant did not land, or something revoked it. (⚠ This arm guards an OVER-REVOKE, not the absent-function path: measured 2026-08-26, pg_default_acl type f = {service_role=X/postgres} in this schema, so a plain CREATE is born service_role-executable and deleting the grant line is invisible here. 0057:59 recorded the same fact; contract v2 §C''s claim that the grant would vanish is false.)';
  end if;

  -- ── ③-bis owner CONSISTENCY, not owner identity ─────────────────────────────────────────────
  -- On the absent-function path there is no prior owner to restore, and naming a hardcoded role
  -- would be a guess dressed as a repair (0127's reasoning, transcribed from 0128). So: the same
  -- owner as an untouched definer peer this file never otherwise mentions. `::regprocedure`
  -- RAISES if the anchor is missing, so a doubly-partial apply aborts instead of comparing NULL
  -- to NULL and passing vacuously.
  select p.oid, p.proowner into v_peer_oid, v_peer from pg_proc p
   where p.oid = 'owner_has_unsettled_charge(uuid)'::regprocedure;
  if v_owner is distinct from v_peer then
    raise exception '0129: booking_pickup_address owner % differs from its definer peer % — applied by the wrong role', v_owner::regrole, v_peer::regrole;
  end if;

  -- ── ④ the two columns — NOT NULL, defaulted, and CHECKed against BOTH legal values ─────────
  -- ⚠ SCOPE, said before someone reads it as more: this arm is CATALOG-only. It asserts that the
  -- constraints exist AND that each names both of its legal values — which is what catches the
  -- half-constraint (`check (return_mode in ('owner_home'))`) that a bare existence check passes.
  -- It does NOT execute a refusal: on the absent-function apply path this file may be running
  -- against an empty `session_dogs`, and an insert probe there dies on foreign keys before it
  -- ever reaches the CHECK — a probe that fails for the wrong reason, or worse cannot fail at
  -- all. **163 P10 owns the executed refusal**, against a real lifecycle-built row. Two
  -- propositions, two places; neither is evidence for the other.
  select a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
    into v_notnull, v_default
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'session_dogs'::regclass and a.attname = 'return_mode' and not a.attisdropped;
  if v_notnull is null then
    raise exception '0129: session_dogs.return_mode is absent after this file';
  end if;
  if not v_notnull or coalesce(v_default,'') not like '%owner_home%' then
    raise exception '0129: session_dogs.return_mode is not NOT NULL/defaulted (notnull=%, default=%)', v_notnull, v_default;
  end if;
  select a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
    into v_notnull, v_default
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'session_dogs'::regclass and a.attname = 'pickup_mode' and not a.attisdropped;
  if v_notnull is null then
    raise exception '0129: session_dogs.pickup_mode is absent after this file';
  end if;
  if not v_notnull or coalesce(v_default,'') not like '%owner_home%' then
    raise exception '0129: session_dogs.pickup_mode is not NOT NULL/defaulted (notnull=%, default=%)', v_notnull, v_default;
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'session_dogs'::regclass and contype = 'c'
                    and conname in ('session_dogs_pickup_mode_chk','session_dogs_return_mode_chk')
                  having count(*) = 2) then
    raise exception '0129: the two named mode CHECK constraints are not both on session_dogs';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'session_dogs'::regclass
                    and conname = 'session_dogs_return_mode_chk'
                    and pg_get_constraintdef(oid) like '%session_finish%'
                    and pg_get_constraintdef(oid) like '%owner_home%') then
    raise exception '0129: session_dogs_return_mode_chk does not name both legal values (def=%)',
      (select pg_get_constraintdef(oid) from pg_constraint
        where conrelid = 'session_dogs'::regclass and conname = 'session_dogs_return_mode_chk');
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'session_dogs'::regclass
                    and conname = 'session_dogs_pickup_mode_chk'
                    and pg_get_constraintdef(oid) like '%session_start%'
                    and pg_get_constraintdef(oid) like '%owner_home%') then
    raise exception '0129: session_dogs_pickup_mode_chk does not name both legal values (def=%)',
      (select pg_get_constraintdef(oid) from pg_constraint
        where conrelid = 'session_dogs'::regclass and conname = 'session_dogs_pickup_mode_chk');
  end if;

  -- ── ⑤ the arm is present, and the oracle is still ONE raise ────────────────────────────────
  -- ⚠ TEXTUAL, and it says so: this is the apply-time net for "somebody hand-edited the body",
  -- not evidence about behaviour, and the header names the two bodies it cannot tell apart from a
  -- correct one. What the text CAN prove is the SHAPE that makes 163 P7's property structural:
  -- exactly one `not_runner` raise in the whole body, so there is no second exception site for a
  -- wrong-mode or wrong-phase caller to be told apart by.
  if v_src not like '%runner_delegated%' then
    raise exception '0129: the custody conjunct is not in the body — this file did nothing';
  end if;
  if v_src not like '%sd.session_id  = b.club_session_id%' and v_src not like '%sd.session_id = b.club_session_id%' then
    raise exception '0129: the club-session binding conjunct is missing (Moderate-1 reopened)';
  end if;
  if v_src not like '%return_mode%' then
    raise exception '0129: the return_mode conjunct is missing — this is the CRITICAL leak';
  end if;
  if v_src not like '%custody_phase <> ''resolved''%' then
    raise exception '0129: the phase conjunct is not the negative form — a phase list strands a dog mid-transfer';
  end if;
  if v_src not like '%owner_confirmed_return_at is null%' then
    raise exception '0129: the F1 conjunct is missing — the grant never closes when the runner never confirms';
  end if;
  if v_src not like '%custodian_profile_id = auth.uid()%' then
    raise exception '0129: the custodian conjunct is missing — the arm is session-scoped';
  end if;
  if v_src not like '%a.owner_id = b.owner_id%' then
    raise exception '0129: the poisoned-row guard (a.owner_id = b.owner_id) is gone';
  end if;
  select count(*) into v_n from regexp_matches(v_src, 'raise exception', 'g');
  if v_n <> 1 then
    raise exception '0129 ORACLE: the body raises % times, not once — a second exception site is a probing oracle', v_n;
  end if;
  select count(*) into v_n from regexp_matches(v_src, 'not_runner', 'g');
  if v_n <> 1 then
    raise exception '0129 ORACLE: found % not_runner literals, expected exactly 1', v_n;
  end if;

  -- ── ⑥ SCOPE — the return machine is 0045/0069's, BY DIGEST ─────────────────────────────────
  -- 0128 asserted that a NAME existed. A disabled trigger or a wholly replaced body passed that.
  -- This arm compares md5(prosrc) for the two functions whose state the arm READS, and asserts
  -- the transition trigger is enabled ('O' = origin, i.e. fires normally) rather than merely
  -- present. If a later reader finds this failing, the slice grew a second half.
  select md5(p.prosrc) into v_md5_scr from pg_proc p
   where p.oid = 'session_confirm_return(uuid,text)'::regprocedure;
  if v_md5_scr is distinct from K_CONFIRM_RETURN then
    raise exception '0129 OVER-REACH: session_confirm_return''s body is not 0069:84 (md5=% expected %) — this file must not touch the return RPCs', v_md5_scr, K_CONFIRM_RETURN;
  end if;
  select md5(p.prosrc) into v_md5_tg from pg_proc p
   where p.oid = '_club_custody_transition_v2()'::regprocedure;
  if v_md5_tg is distinct from K_TRANSITION then
    raise exception '0129 OVER-REACH: _club_custody_transition_v2''s body is not 0045:36 (md5=% expected %) — the phase this arm keys on would be set by something else', v_md5_tg, K_TRANSITION;
  end if;
  select t.tgenabled into v_tgen from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
     and c.relname = 'bookings' and t.tgname = 'club_custody_transition_v2';
  if v_tgen is null then
    raise exception '0129 OVER-REACH: club_custody_transition_v2 is not on bookings — the phase this arm keys on would never be set';
  end if;
  if v_tgen <> 'O' then
    raise exception '0129 OVER-REACH: club_custody_transition_v2 is present but tgenabled=% (not ''O'') — a disabled trigger passes an existence check and sets nothing', v_tgen;
  end if;

  raise notice '0129: booking_pickup_address recreated with the corrected six-conjunct club arm — secdef, in-body search_path exactly {search_path=public, pg_temp}, 5 OUT columns in order, ACL (public=%, anon=%, authenticated=%, service_role=%), owner consistent with its definer peer, one raise and one not_runner literal, mode columns NOT NULL/defaulted/CHECKed, 0045+0069 return machine byte-identical and its trigger enabled',
    v_pub, v_anon, v_auth, v_svc;
end $$;
