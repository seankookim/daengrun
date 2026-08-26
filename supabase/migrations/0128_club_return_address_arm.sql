-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0128 — the club return-address arm. ONE custody-aware disjunct inside `booking_pickup_address`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean, 2026-08-25: 「go ahead with the address fix」. Contract:
-- `docs/contracts/club-return-address-arm-contract.md`. It blocks two ordered slices — the club
-- sign-up screen (which starts writing `bookings.address_id`) and the runner's post-run navigation
-- branch (「집 반환 → navigate the runner to the owner-set address」, round 6).
--
-- ── THE DEFECT IS STRUCTURAL, NOT AN OVERSIGHT ───────────────────────────────────────────────
-- `booking_pickup_address` (0060, widened by 0065) admits the assigned runner at `runner_enroute`
-- / `picked_up` / `active`, or `confirmed` inside T−24h. `completed` is deliberately NOT in that
-- set, and that is correct for the marketplace.
--
-- The club inverts settle-vs-return on purpose. Reaching `completed` fires
-- `_club_custody_transition_v2` (`0045:55-60`), which sets `session_dogs.custody_phase =
-- 'return_pending'` and KEEPS custody with the runner — the comment there is
-- 「[R2 핵심] 정산 ≠ 반환: 국면만 반환 대기, 커스터디는 러너 유지」. Both club return RPCs then
-- REQUIRE that phase: `session_confirm_return` (`0045:79`) and `session_custody_override`
-- (`0045:137`), each raising `not_return_pending` outside it.
--
-- Therefore the club's ENTIRE return window lies outside the address gate BY CONSTRUCTION. The
-- separation that makes club custody honest — the dog is still the runner's responsibility after
-- the money is computed — is exactly what puts the return leg past the window. A runner who is
-- holding someone's dog and is expected to walk it home cannot ask the server where home is.
--
-- Marketplace is unaffected and must not be reasoned about together: `confirm_return_tx` refuses
-- club bookings outright (`0083:383`, `club_out_of_scope`) and `completed` is claimed only FROM
-- `active` (`0083:720`), so a marketplace booking is still `active` through its whole return leg
-- and already inside the gate.
--
-- Latent today only because club bookings mint with `address_id` NULL (`0081:184-186` — the insert
-- there names no `address_id` column at all). It arms the moment sign-up writes one.
--
-- ── WHAT WAS REJECTED, AND WHY THE REJECTION IS THE INTERESTING PART ─────────────────────────
-- ⚠ REJECTED — adding `completed` to the status list. It is the tempting one-liner and it is a
--   privacy regression: it re-opens the pickup address for EVERY finished booking, FOREVER, to a
--   runner whose custody ended months ago. A terminal status is not a live fact.
-- ⚠ REJECTED — a separate club-return RPC. It duplicates the party gate, and a second copy of an
--   admission rule is how the two copies drift.
--
-- ── THE ADOPTED SHAPE ────────────────────────────────────────────────────────────────────────
-- One additional disjunct admitting the caller when THAT pairing's custody is live and the caller
-- is the one holding it. Three properties make it the right shape:
--   · **A live custody fact, not a terminal status.** True only while this dog is in this runner's
--     hands awaiting return.
--   · **It self-closes.** `session_confirm_return` moves the phase to `resolved` (`0045:108`); the
--     arm goes false with no sweep, no expiry job, no flag to forget to clear.
--   · **Its blast radius is bounded by data that already exists.** A pairing whose booking has
--     `address_id` NULL returns 0 rows regardless — the body's join decides that, not the gate —
--     so an on-site-return pairing cannot leak an address it never had. (When `return_mode` ships
--     the arm MAY narrow further to `owner_home`. That narrowing is OPTIONAL, not owed: it is not
--     required for correctness, and recording it as owed would invent a follow-up nobody agreed to.)
-- It is club-only BY CONSTRUCTION — `session_dogs` rows exist only for club pairings — but suite
-- 162 P8 asserts the marketplace behaviour anyway rather than trusting the sentence.
--
-- ⚠ **The `custody = 'runner_delegated'` conjunct is a SECOND BELT, not the primary guard**, and
-- that is worth knowing before someone "simplifies" it away (measured while writing suite 162,
-- 2026-08-26). `_club_compute_axes` returns early for `owner_handled` with
-- `custodian_type='owner'`, `custodian_profile_id = owner_profile_id` and
-- `custody_phase='with_custodian'` (0048:698-706, inherited from 0040:180), and
-- `club_v1_axes_sync` (0040:280-282) is a BEFORE INSERT OR UPDATE trigger that writes that result
-- back on every write — so an accompanied dog's row can never sit at `return_pending` while that
-- normalizer is installed, and the conjunct is unreachable through the table today. It stays
-- because this arm must not depend on another trigger remaining installed, unaltered, and enabled.
-- 162 P5 pins both halves and says which one a mutation can redden.
--
-- ── INVARIANTS THIS FILE MUST NOT MOVE (each has a pin, and the VERIFY block below is the net) ─
--   ① **The probing-oracle blocker.** Absent booking / foreign booking / wrong state all raise the
--      SAME string `not_runner` (0060:58, 0054:73 doctrine). The new arm introduces NO new
--      exception, no early return, and no distinguishable outcome for "exists but wrong phase" —
--      it is a disjunct inside the SAME boolean, so a false arm is indistinguishable from an
--      absent booking. 162 P6 compares the three SQLSTATE+message pairs TO EACH OTHER.
--   ② **The poisoned-row guard stays**: `a.owner_id = b.owner_id` in the body. A mismatched
--      address yields 0 rows, never an error.
--   ③ **Flat 5-column return** label/addr/detail/lat/lng — byte-identical to 0065.
--   ④ **`security definer` + `set search_path = public, pg_temp` IN THE BODY.** ALTER-applied
--      config is wiped by `create or replace` (measured; 98 H1 sweeps the whole schema for it).
--   ⑤ **Explicit ACL, written not inherited.** This function was FIRST defined in 0060, so a
--      `create or replace` here relying on grant preservation is a plain CREATE on any database
--      where the function is absent — and 0116:636 records that a new function is born
--      PUBLIC-executable. A SECURITY DEFINER born public is the worst shape this repo can make.
--      The revoke/grant pair below is copied verbatim from 0065:69-70; `check-definer-acl.mjs`
--      refuses this file without it, and VERIFY ③ fails the apply closed.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────
-- No `return_mode` column (spec-only today). No change to `session_confirm_return`,
-- `session_custody_override`, `_club_custody_transition_v2`, or any return RPC. No change to the
-- transfer ritual — Sean ruled 「THIS interaction is the evidence」 (0083:182-186) and a destination
-- is not an interaction. No marketplace change of any kind. No new table, column, policy, trigger
-- or grant surface: this file recreates exactly ONE function and re-issues its own ACL.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §1  booking_pickup_address — 0065's body with ONE added disjunct
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Everything except the `or exists (...)` block is 0065:44-67 transcribed. The return type is
-- unchanged, so `create or replace` is legal here (0065 needed a DROP only because it widened the
-- OUT columns 3 → 5, and the DROP is what cost it its grants).
--
-- ⚠ The parenthesisation is load-bearing. The marketplace conjunction is wrapped so the new arm
-- binds at the TOP level of the predicate, not inside the status disjunction — `and` binds tighter
-- than `or`, so an unwrapped form would still be correct by precedence but would read as though
-- the custody arm were another status, which is the misreading that produces a status-list
-- widening in the next edit. NULL behaviour is unchanged and still fails closed: with no JWT,
-- `b.runner_id = auth.uid()` is NULL and `sd.custodian_profile_id = auth.uid()` matches no row, so
-- the whole predicate is NULL → `coalesce(..., false)` → `not_runner`.
create or replace function booking_pickup_address(p_booking uuid)
returns table (label text, addr text, detail text, lat numeric, lng numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- party + state gate (absent / foreign / wrong status all raise the same string — probing-oracle
  -- blocker, unchanged from 0060; the 0128 arm is a disjunct inside it, never a second raise)
  if not coalesce((
        select (b.runner_id = auth.uid()
                and (b.status in ('runner_enroute', 'picked_up', 'active')
                     or (b.status = 'confirmed' and b.scheduled_at < now() + interval '24 hours')))
            -- [0128] the club return window. Live custody + the caller IS the custodian. Self-
            -- closes at `resolved`; club-only because session_dogs rows exist only for club
            -- pairings. See this file's header for why a status list was the wrong fix.
            or exists (
                 select 1 from session_dogs sd
                 where sd.booking_id = b.id
                   and sd.custody = 'runner_delegated'
                   and sd.custody_phase = 'return_pending'
                   and sd.custodian_profile_id = auth.uid())
        from bookings b where b.id = p_booking), false)
  then
    raise exception 'not_runner';
  end if;

  -- unassigned (address_id null) · poisoned row (address owner ≠ booking owner)
  -- → 0 rows (not an error), unchanged from 0060/0065
  return query
    select a.label, a.addr, a.detail, a.lat, a.lng
    from bookings b
    join addresses a on a.id = b.address_id
    where b.id = p_booking
      and a.owner_id = b.owner_id;
end $$;

-- ⚠ NOT optional and NOT inheritable — see invariant ⑤ in the header. Verbatim from 0065:69-70.
revoke execute on function booking_pickup_address(uuid) from public, anon;
grant  execute on function booking_pickup_address(uuid) to authenticated;

comment on function booking_pickup_address is
  'Pickup address for the runner holding the dog (0060, widened by 0065, custody arm 0128) — flat
5 fields label/addr/detail/lat/lng. Two ways in, one error out:
  · MARKETPLACE — that booking''s runner, in one of the 3 in-flight states, or `confirmed` and
    starting within 24h. Unchanged since 0060.
  · CLUB RETURN (0128) — that pairing''s `session_dogs` row is `runner_delegated` and
    `return_pending` and the caller IS `custodian_profile_id`. The club keeps custody with the
    runner past `completed` (0045:55-60, 「정산 ≠ 반환」), so its whole return window sits outside
    the marketplace gate by construction; this arm is what lets the runner be navigated to the
    owner''s door. It self-closes when `session_confirm_return` sets the phase to `resolved` —
    there is no flag and no sweep. NOT a status-list widening: `completed` alone would re-open
    every finished booking''s address forever.
Everything else raises not_runner (absent / foreign / wrong-status / wrong-phase all
indistinguishable — 0054:73 oracle doctrine; the 0128 arm is a disjunct, never a second raise).
Unassigned address or owner mismatch → 0 rows, not an error — which is also what bounds the club
arm: a pairing that never had an address cannot leak one.
lat/lng are NULL until the owner pins the address (client renders the honest dark state);
gate_code_enc remains structurally absent — decryption is its own slice.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — fail the apply closed, in both directions
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- A VERIFY runs once, at apply time; suite 162 is what outlives it. What this block is for is the
-- apply path the harness structurally CANNOT produce: a database where `booking_pickup_address`
-- was absent, so the statement above was a CREATE rather than a replace. There, preservation never
-- happened, and without §1's explicit pair the function would be born PUBLIC-executable
-- (0116:636). ③ below asserts the ACL that actually landed rather than trusting that the two
-- lines ran — and asserts it in BOTH directions, because an over-revoke that dropped
-- `authenticated` would break every runner's pickup screen just as silently.
do $$
declare
  v_cols text[]; v_n int; v_src text; v_cfg text[]; v_secdef boolean;
  v_pub boolean; v_anon boolean; v_auth boolean; v_owner oid; v_peer oid;
begin
  -- ── ① the function exists, is a plpgsql SECURITY DEFINER, and pins search_path IN THE BODY ──
  -- `set search_path` written into the header lands in `proconfig` and survives create-or-replace;
  -- an ALTER-applied one does not (measured, 0055's lesson). 98 H1 watches this schema-wide, but a
  -- file that recreates a definer should not need another file's suite to notice it broke it.
  select p.prosecdef, p.proconfig, p.prosrc, p.proowner
    into v_secdef, v_cfg, v_src, v_owner
    from pg_proc p
   where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace;
  if v_secdef is null then
    raise exception '0128: booking_pickup_address is absent after this file';
  end if;
  if not v_secdef then
    raise exception '0128: booking_pickup_address lost SECURITY DEFINER';
  end if;
  -- Matched the way 98 H1 matches it (`%pg_temp%` on the joined proconfig) rather than against an
  -- exact literal — the catalog's spacing is postgres's to choose, and a pin that depends on it
  -- would fail for a reason that has nothing to do with the property.
  if coalesce(array_to_string(v_cfg, ','), '') not like '%search_path=%'
     or coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%' then
    raise exception '0128: booking_pickup_address has no in-body search_path pin (proconfig=%)', v_cfg;
  end if;

  -- ── ② the contract surface did not move: exactly the 5 OUT columns 0065 shipped ─────────────
  select array_agg(a.n order by a.o) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
   where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace
     and a.m = 't';
  if coalesce(array_length(v_cols, 1), 0) <> 5
     or not (v_cols @> array['label','addr','detail','lat','lng']
             and array['label','addr','detail','lat','lng'] @> v_cols) then
    raise exception '0128: the 5-column return contract moved (OUT columns = %)', v_cols;
  end if;

  -- ── ③ the ACL that ACTUALLY landed — the whole reason this block exists ─────────────────────
  -- Asked of the catalog, not of the two statements above. On an absent-function apply those two
  -- lines are the only thing standing between a money-adjacent definer and PUBLIC EXECUTE.
  select has_function_privilege('public',        'booking_pickup_address(uuid)', 'execute'),
         has_function_privilege('anon',          'booking_pickup_address(uuid)', 'execute'),
         has_function_privilege('authenticated', 'booking_pickup_address(uuid)', 'execute')
    into v_pub, v_anon, v_auth;
  if v_pub then
    raise exception '0128: booking_pickup_address is PUBLIC-executable — the revoke did not take (partial-apply CREATE path)';
  end if;
  if v_anon then
    raise exception '0128: anon can execute booking_pickup_address';
  end if;
  if not v_auth then
    raise exception '0128 OVER-REVOKE: authenticated cannot execute booking_pickup_address — every runner pickup screen is dead';
  end if;

  -- ── ③-bis owner CONSISTENCY, not owner identity ─────────────────────────────────────────────
  -- On the absent-function path there is no prior owner to restore, and naming a hardcoded role
  -- would be a guess dressed as a repair (0127's reasoning, transcribed). So: the same owner as an
  -- untouched definer peer this file never otherwise mentions. `::regprocedure` RAISES if the
  -- anchor is missing, so a doubly-partial apply aborts instead of comparing NULL to NULL and
  -- passing vacuously.
  select p.proowner into v_peer from pg_proc p
   where p.oid = 'owner_has_unsettled_charge(uuid)'::regprocedure;
  if v_owner is distinct from v_peer then
    raise exception '0128: booking_pickup_address owner % differs from its definer peer % — applied by the wrong role', v_owner::regrole, v_peer::regrole;
  end if;

  -- ── ④ the arm is present, and the oracle is still ONE raise ────────────────────────────────
  -- Textual, and it says so: this is the apply-time net for "somebody hand-edited the body", not
  -- evidence about behaviour. Suite 162 owns behaviour, and P6 owns the oracle by comparing three
  -- real SQLSTATE+message pairs to each other. What the text CAN prove is the shape that makes
  -- P6's property structural: exactly one `not_runner` raise in the whole body, so there is no
  -- second exception site for a wrong-phase caller to be told apart by.
  if v_src not like '%runner_delegated%' or v_src not like '%return_pending%'
     or v_src not like '%custodian_profile_id%' then
    raise exception '0128: the custody arm is not in the body — this file did nothing';
  end if;
  if v_src not like '%a.owner_id = b.owner_id%' then
    raise exception '0128: the poisoned-row guard (a.owner_id = b.owner_id) is gone';
  end if;
  select count(*) into v_n from regexp_matches(v_src, 'raise exception', 'g');
  if v_n <> 1 then
    raise exception '0128 ORACLE: the body raises % times, not once — a second exception site is a probing oracle', v_n;
  end if;
  select count(*) into v_n from regexp_matches(v_src, 'not_runner', 'g');
  if v_n <> 1 then
    raise exception '0128 ORACLE: found % not_runner literals, expected exactly 1', v_n;
  end if;

  -- ── ⑤ SCOPE — what this file must NOT have touched ─────────────────────────────────────────
  -- The club return machine is 0045's and stays 0045's; the arm READS its state and changes none
  -- of it. If a later reader finds this block failing, the slice grew a second half.
  if not exists (select 1 from pg_proc where proname = 'session_confirm_return'
                   and pronamespace = 'public'::regnamespace) then
    raise exception '0128 OVER-REACH: session_confirm_return is gone — this file must not touch the return RPCs';
  end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
     and c.relname = 'bookings' and t.tgname = 'club_custody_transition_v2';
  if v_n <> 1 then
    raise exception '0128 OVER-REACH: club_custody_transition_v2 is not on bookings — the phase this arm keys on would never be set';
  end if;

  raise notice '0128: booking_pickup_address recreated with the club custody arm — secdef, in-body search_path, 5-column contract, ACL (public=%, anon=%, authenticated=%), owner consistent with its definer peer, one raise and one not_runner literal in the body, 0045 return machine untouched',
    v_pub, v_anon, v_auth;
end $$;
