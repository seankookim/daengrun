-- ═══ 0153: the INNER board function stops being callable by clients ═══
--
-- `0147:190` granted `authenticated` direct EXECUTE on `_club_delegation_board_impl(uuid, text)`.
-- That function is SECURITY DEFINER and **trusts a caller-supplied access grade**: the outer
-- `club_delegation_board` computes the grade with `_club_shell_access` and passes it in, but
-- nothing required a caller to go through the outer one.
--
-- ⚠ **A LIVE DISCLOSURE, CONFIRMED BY EXECUTION AGAINST PRODUCTION (2026-08-28) — not inferred
--   from a grant.** Found cold by codex reviewing 0144/0147/0152 (REJECT, 12 findings,
--   `docs/reviews/2026-08-28-codex-runend-money.md`), then reproduced here.
--
--   MEASURED on production, comment-stripped so this is not the comment-matching trap:
--     · prosecdef                                                    → t
--     · has_function_privilege('authenticated', …, 'EXECUTE')        → t   (anon → f)
--     · body references `p_access`                                   → t
--     · body references `_club_shell_access`                         → **f**  ← never re-derives
--
--   PROVEN, as role `authenticated` with NO party relationship to the session, on a session that
--   actually has content:
--     · p_access = 'host'  (forged)   → 1 dog, 2,185 B
--     · p_access = 'none'  (control)  → 0 dogs,  663 B     ← different digest
--   The forged grade disclosed `ownerName`, `runnerName`, `proposedRunnerName`,
--   `custodianProfileId`, `runnerId`, `bookingStatus`, `chargeState`, `refundState`,
--   `payoutState`, `payoutHoldReason`, `openIncidentId`, `dogName`, `collar` — **real names,
--   re-identifying profile ids, money state and incident references for a stranger's session.**
--
-- ⚠ **AND UNLIKE THE `net` GRANT (0151), NO ALLOWLIST STOOD IN FRONT OF THIS ONE.** There the
--   accurate sentence was 「a needless grant behind one config line」, because PostgREST exposes
--   only `public, graphql_public` and `net` is neither. This function IS in `public`. The gap
--   between those two sentences is the gap between a hygiene item and an incident, and this one
--   is on the incident side.
--
-- ⚠ **WHY 0147's OWN VERIFY BLOCK DID NOT CATCH IT** (`0147:210`): it asserts only that the
--   grantee `PUBLIC` is absent. `authenticated` is not `PUBLIC`, so the check passed while the
--   hole was open. A guard that enumerates one grantee cannot see the others — the same shape as
--   every 「green light is evidence for exactly one sentence」 entry in CLAUDE.md.
--
-- ⚠ **BLAST RADIUS, MEASURED BEFORE REVOKING — this is safe and here is why:**
--     · client refs to the inner function  → 0 (executable lines, `app/`)
--     · edge-function refs                 → 0
--     · deployed SQL callers               → exactly ONE: `club_delegation_board`
--   That caller is SECURITY DEFINER owned by `postgres`, so it executes the inner function as
--   `postgres`, not as the caller's role. The inner ACL keeps `postgres=X` and `service_role=X`
--   after this revoke, so **the legitimate path is untouched.** `service_role` is deliberately
--   retained: it is the backend key, and edge functions are entitled to it.
--
-- Correct-forward: this does not recreate the function, so no ACL is re-established by accident
-- and no `create or replace` grant-preservation hole is opened (CLAUDE.md §definer-ACL).

revoke execute on function public._club_delegation_board_impl(uuid, text)
  from public, anon, authenticated;

-- ── VERIFY — abort the apply if the hole is still open ──
-- Enumerates the three CLIENT grantees by name rather than checking one, which is the defect in
-- 0147's own verify. Asserts positively that `service_role` SURVIVES, so a revoke that reached
-- too far fails here instead of silently breaking the board for the backend.
do $$
declare
  v_bad text := '';
begin
  if has_function_privilege('authenticated', 'public._club_delegation_board_impl(uuid, text)', 'EXECUTE')
     is distinct from false then
    v_bad := v_bad || ' authenticated-still-has-execute';
  end if;
  if has_function_privilege('anon', 'public._club_delegation_board_impl(uuid, text)', 'EXECUTE')
     is distinct from false then
    v_bad := v_bad || ' anon-still-has-execute';
  end if;
  -- the over-reach arm: the backend path must keep working
  if has_function_privilege('service_role', 'public._club_delegation_board_impl(uuid, text)', 'EXECUTE')
     is distinct from true then
    v_bad := v_bad || ' service_role-LOST-execute';
  end if;
  -- and the outer wrapper, which is what clients are supposed to call, must still be reachable
  if has_function_privilege('authenticated', 'public.club_delegation_board(uuid)', 'EXECUTE')
     is distinct from true then
    v_bad := v_bad || ' outer-board-LOST-authenticated-execute';
  end if;
  if v_bad <> '' then
    raise exception '0153 VERIFY failed:%', v_bad;
  end if;
end $$;

comment on function public._club_delegation_board_impl(uuid, text) is
  '0153: INTERNAL. Trusts a caller-supplied p_access and does not derive it, so it must never be '
  'callable by a client role — call public.club_delegation_board(uuid), which computes the grade '
  'with _club_shell_access. 0147 granted this to authenticated and it was a live disclosure of '
  'names, profile ids and money state; proven by execution 2026-08-28. service_role is retained '
  'deliberately (backend). Pinned by suite 184.';
