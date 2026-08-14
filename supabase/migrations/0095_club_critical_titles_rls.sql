-- 0095 — club_critical_titles: RLS was never enabled. The registry that decides which alerts
-- get an acknowledgment row is writable by anyone holding the app's public anon key.
--
-- ═══ §0 WHAT WAS MEASURED, 2026-08-14, AGAINST PRODUCTION ═══════════════════════════════════
-- Not read from a policy — executed. Over plain HTTPS with the anon key shipped inside the
-- client bundle, against the live project:
--
--     GET    /rest/v1/club_critical_titles?select=title&limit=1        -> 200
--     DELETE /rest/v1/club_critical_titles?title=eq.<no-match>         -> 204
--     GET    /rest/v1/profiles?select=phone&limit=1                    -> 401   (control)
--     DELETE /rest/v1/profiles?id=eq.<no-match>                        -> 401   (control)
--
-- The controls matter: the same key on the same connection is refused by `profiles` (0088), so
-- the 200/204 pair is authorization on THIS table, not a broken probe. At SQL level, inside a
-- rolled-back transaction: `set local role anon` then INSERT took the table 13 -> 14, and DELETE
-- of a real row took it 13 -> 12. Production is untouched (still 13); the no-match filter on the
-- HTTP probe deleted nothing by construction.
--
-- ═══ §1 WHY THIS IS A SAFETY DEFECT AND NOT A LOOKUP-TABLE DEFECT ═══════════════════════════
-- `_club_ack_tg()` (0049:311) fires after every `notifications` INSERT and creates a `club_acks`
-- row ONLY when the notification's title appears in this registry. The 30-minute escalation
-- (0049:445, re-emitted at 0068:119) then scans `club_acks` for rows that are unacknowledged and
-- unescalated, and pages the session host.
--
-- So deleting one row from this table severs that chain for that entire alert class:
--   · the notification is still inserted and the push still fires
--   · no `club_acks` row exists, so the recipient never gets an acknowledgment to tap
--   · the unacked -> host escalation NEVER FIRES, because it scans a table that has no row
-- The registry currently holds `인시던트 발생` (0050:135) and `담당견 인시던트` (0067:242).
-- **The failure is silent in both directions**: nothing errors, the alert still arrives, and the
-- only symptom is an escalation that does not happen — which no one observes. The inverse is
-- also open: INSERT an arbitrary title and every ordinary notification carrying it fans out an
-- ack row, which is noise at best and an unbounded write into `club_acks` at worst.
--
-- ═══ §2 WHY EVERY SECURITY SWEEP WALKED PAST IT SINCE 0049 ══════════════════════════════════
-- Because it has no policy to read. 0088 and 0093 were both *policies with no caller term*, two
-- lines apart in `0002_rls.sql`, and the sweeps that found them enumerated `pg_policies`. A table
-- with RLS **off** contributes zero rows to `pg_policies`, so it is invisible to exactly the
-- query that catches its siblings — and in any listing it looks identical to the many tables here
-- that are RLS-on-with-no-policies, which are fail-CLOSED and correct.
--
--   DETECTOR (belongs with the others in REGISTRY.md): audit the tables that have NO policies,
--   not the policies. `relrowsecurity = false` is the whole finding; the policy list is a
--   distraction because the defect is the absence of one.
--
-- ═══ §3 WHY BOTH ARMS, AND WHY NEITHER IS BELT-AND-BRACES ═══════════════════════════════════
-- `revoke all` alone → Supabase's own tooling and several bootstrap snippets run
--   `grant all on all tables in schema public to anon, authenticated`. One such line in a future
--   migration silently reopens this, with no policy anywhere to stop it.
-- `enable row level security` alone → **TRUNCATE is not subject to row security** (PG docs), and
--   anon currently holds TRUNCATE on this table. RLS would leave a one-statement full wipe open.
-- Each arm covers the other's exact failure mode. That is why both are here and why C1-C3 and C6
-- are separate pins rather than one.
--
-- ⚠ **A CLAIM THIS FILE MADE AND THE MUTATION RUN REFUTED — kept, because the correction is the
-- useful part.** The first version of this header asserted: "do NOT add `force row level
-- security` — FORCE applies RLS to the owner too, so the definer trigger's existence check would
-- silently return false and ack rows would stop being created; suite 131 C5 is red under that
-- mutation." It reads well, the mechanism is real in general, and **it is false here.** Running
-- the mutation (M3: add FORCE, rebuild, re-run) left the harness at 545/0 — C5 stayed GREEN.
-- Measured against production afterwards, which is what settled it:
--
--     _club_ack_tg owner = postgres · rolsuper = false · rolbypassrls = TRUE
--
-- **BYPASSRLS overrides FORCE**, so the trigger reads the registry either way. FORCE here is
-- inert, not dangerous. I had reasoned from the PG docs to a conclusion about this system without
-- running it — the precise-but-unverified shape this repo has now hit a dozen times, in a comment
-- warning future readers off a hazard that does not exist. It is recorded rather than deleted
-- because a deleted wrong claim teaches nobody, and because the pin that caught it was one I only
-- wrote in order to prove the claim I got wrong.
-- FORCE is still not added: it buys nothing while the owner bypasses RLS, and an inert clause
-- that looks protective is its own small lie.
--
-- ═══ §4 SCOPE ══════════════════════════════════════════════════════════════════════════════
-- No policy is created, deliberately: nothing in `app/` reads this table (grepped) and the only
-- consumer is a definer trigger that bypasses RLS. Zero policies + RLS on = deny-all for anon and
-- authenticated, which is the correct surface for an operator-owned registry. If a future feature
-- needs to show the list in-product, add a read policy then — do not pre-grant it now.
-- Creates no object. Touches no other table.

revoke all on club_critical_titles from anon, authenticated;

alter table club_critical_titles enable row level security;

comment on table club_critical_titles is
  '0095: registry driving critical-alert ack fanout (_club_ack_tg, 0049:311) and therefore the
30-minute unacked -> host escalation (0049:445 / 0068:119). RLS was never enabled from 0049 until
2026-08-14: measured live, anon could GET (200) and DELETE (204) over PostgREST with the public
client key, so anyone could silently disable escalation for an alert class by deleting its title.
Now deny-all for anon and authenticated (revoke + RLS, no policies) — the definer trigger is
unaffected. Both arms are load-bearing: TRUNCATE ignores RLS, and a future blanket GRANT would
defeat a revoke-only fix. Do NOT add FORCE — it would apply RLS to the owner and silence the
trigger (suite 131 C5).';
