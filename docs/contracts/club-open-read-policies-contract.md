# Contract — the four `auth.uid() IS NOT NULL` read policies

**Status:** CONTRACT, not built. Migration number resolves from origin at build time (§Migrations
law: never from a doc).
**Authority:** Sean, console `dogs-read-wide` → `Fix it — scope the read properly`, 2026-08-26
04:58:12Z.
**⚠ Scope is WIDER than what he approved. See §1. That is a decision he can reverse.**

---

## 1. What he approved, what I found, and why I am proposing more

He approved fixing **one** table: `session_dogs`. Scouting production found the **identical**
policy on **four**:

```
participant_activities · session_dogs · session_people · session_runner_assignments
```

each with exactly one SELECT policy whose predicate is, character for character,
`(auth.uid() IS NOT NULL)` — any logged-in account reads every row.

🔴 **Fixing one of four is the failure this repo already has a law for**: *a rule copied N times
is a rule you can fix N−1 times and ship.* Worse here than usual, because the four are the same
club session viewed from four angles — which dogs are on a walk, who is attending, which runner
was assigned, what each participant did. Narrowing only `session_dogs` closes the door and leaves
three windows open, and the next person to grep for the open predicate finds three hits and
assumes it was never done.

**So this contract covers all four.** If Sean wants only `session_dogs`, delete §4's other three
arms; nothing else changes.

## 2. Measured facts (production + source, 2026-08-26). Every claim here was run, not inferred.

| fact | measured |
|---|---|
| policies on `session_dogs` | exactly **1**, `SELECT`, `(auth.uid() IS NOT NULL)`. No INSERT/UPDATE/DELETE policy exists → writes are already RLS-denied to clients |
| executable client reads of `session_dogs` | **0** (all 3 source hits are comments — verified by opening each, per the comment-matches-every-grep law) |
| edge-function reads of `session_dogs` | **0** |
| views reading `session_dogs` | **0** — so there is no caller-rights path around RLS |
| `SECURITY DEFINER` functions touching `session_dogs` | **58** — these bypass RLS and are unaffected by any policy change |
| executable client reads of the other three | `participant_activities` **0** · `session_runner_assignments` **0** · `session_people` **1** |
| that one `session_people` read | `api.ts:1629`, already `.eq('profile_id', uid)` — and its own comment says the filter is *a correctness requirement, not an optimisation, because the RLS is open*. **A narrowed policy does not break it.** |
| RLS recursion risk today | none — no sibling policy references another of the four |

**The conclusion the numbers force:** the open policy is not serving the product. Every real read
path is a definer RPC. This is not a trade-off between safety and features; it is dead permission.

## 3. What the fix must NOT do — the recursion trap

The obvious predicate is "…or you are a member of this session", which means
`session_dogs`'s policy reads `session_people`, and the natural `session_people` policy reads
`session_dogs`. **Two RLS policies that reference each other's tables recurse and Postgres errors
at query time** — a fault that appears only when a client actually reads, i.e. not in any test
that goes through the definer RPCs.

**Therefore membership is resolved by a `SECURITY DEFINER` helper**, which bypasses RLS and
terminates the chain. Per house law the helper carries `set search_path = public, pg_temp` in the
body (ALTER-applied config is reset by `create or replace` — 98 H1 watches this) and an
**explicit `revoke … from public`** written in the same file, never relying on grant preservation
(0116:636 — a definer born PUBLIC-executable is the worst shape this repo can produce).

## 4. The four arms

Each replaces the single open policy. `create policy` after `drop policy` on the same statement
pair — these are policies, not views, so the view-preservation rule does not apply.

1. **`session_dogs`** — readable when the row is your dog, **or** you are the custodian, **or**
   you are a member of that session.
2. **`session_people`** — readable when it is your own row, **or** you are a member of that
   session.
3. **`session_runner_assignments`** — readable when you are the runner, **or** a member.
4. **`participant_activities`** — readable when it is your own activity, **or** you are a member.

「member」 is the helper: host, backup host, an attending person, a committed runner, or the owner
of a dog in the session.

⚠ **`club_sessions` stays `using (true)` and is NOT touched.** Sean ruled the board public
(2026-08-25 04:25:53Z: 「always fine; it's like a public dashboard」). The session's *existence* is
public; who is in it is not. Naming that here so a later reader does not "tidy" the inconsistency.

## 5. Verification — three propositions, not one

Per the mutation law, "the hole is real", "the pin notices", and "the fix closes it" are three
claims and one mutation proves only the middle.

- **The hole reproduces, unfixed:** as an ordinary authenticated user with no relationship to a
  session, `select count(*) from session_dogs` returns **> 0**. Run before the migration.
- **The fix closes it:** same query, same user, after → **0**, while the same user still reads
  their own rows and every definer RPC returns what it returned before.
- **The fix does not break the one real caller:** drive `fetchStampStats`'s
  `session_people` count as its own user and compare to the pre-migration number.
- **Standing guard, schema-wide, not per-table** (per-table pins only catch the table you already
  suspected): a sweep asserting **no `public` table carries a SELECT policy whose predicate is
  exactly `(auth.uid() IS NOT NULL)`**, with an allowlist where every entry carries its reason.
  This is the arm that makes the 5th occurrence fail instead of shipping.

## 6. Residual, stated rather than buried

`anon` and `authenticated` hold table-level `SELECT/INSERT/UPDATE/DELETE` grants on all four
(the Supabase default). RLS is the only thing standing between `anon` and these rows today. That
is the platform's normal posture and this slice does not change it — but it means **any future
policy added to these tables is load-bearing for anon too**, and a permissive one would be an
unauthenticated leak rather than merely a broad authenticated one. Recorded, not fixed here.
