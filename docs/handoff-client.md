# HANDOFF — client domain (`app/`), written 2026-08-24

**Read in order:** this file · `docs/plans/2026-08-21-late-booking-protocol.md` (§12 server contract,
the AMENDMENT at §12, and the **corrected C2/C5 clauses** you must not undo) · `CLAUDE.md`.

Domain: **client — all of `app/`**. Never write a migration. Reading `supabase/` to verify a claim
is required and was done constantly.

---

## 1. 🔴 A NEW DEPLOY BLOCKER — and it is not in F1–F20

**Every marketplace owner cancel raises `permission denied for function _checkin_custody` the
moment 0117 is applied.** This is not gated by `ops_flags.late_protocol_live_since`. It breaks on
**DEPLOY**, not on flip, so it is upstream of everything the previous handoff said.

The chain, verified end to end this session (not taken from an agent):

| step | evidence |
|---|---|
| `_checkin_custody` is plain `language sql stable` — **not** SECURITY DEFINER, so it runs as the caller | `0117:159-170` |
| its EXECUTE is revoked from service_role and **never re-granted** — no grant anywhere in the file, no blanket grant in 0117 or on trunk | `0117:171-172` |
| `_booking_cancel_custody_guard()` is `language plpgsql` with **no** `security definer`, so it runs as the invoking role | `0117:1223-1224` |
| its trigger fires `before update of status on bookings when (new.status = 'cancelled_owner' and old.status in ('confirmed','runner_enroute') and old.club_session_id is null)` — **no flag in the WHEN clause** | `0117:1234-1246` |
| the owner cancel writes that status **directly**, not through a DEFINER RPC | `cancel_owner.ts:137` `.update({ status: "cancelled_owner", … })` |
| and it does so as service_role | `_shared/ctx.ts` `admin()` uses `SUPABASE_SERVICE_ROLE_KEY` |

The file proves the authors knew the rule and missed this one function: the very next block grants
`late_grace()`, `late_ceiling()`, `late_ceiling_at()` to service_role with a comment spelling out
exactly this reasoning (`0117:174-182`). The other three callers (`0117:504, 897, 918`) live inside
DEFINER functions, which is why only the INVOKER trigger breaks.

**Cheapest fix (one line, server domain — not mine to write):**
```sql
grant execute on function _checkin_custody(booking_status, timestamptz, timestamptz) to service_role;
```
Add a pin that an owner cancel from `runner_enroute` with one stamp succeeds, and one that a cancel
with BOTH stamps still raises `cancel_after_handoff` (the guard's intended refusal) rather than a
permission error — otherwise the two failures are indistinguishable in the suite.

**Provenance:** found by a five-lens blind review of 0117 at `e132b3d`, run this session because
round 6 was dispatched and never returned. **Four of the five lenses found it independently**, and
adversarial verification confirmed it in every case. I then re-derived it myself from the file.

---

## 2. What landed this session — `0c9745b` on trunk

Four of the 36-agent audit's §2 findings. Gates at commit: **tsc 0 · rpc ✅ · route-native 57 ✅ ·
embed-fk ✅ · lint 270 / 6 errors (baseline unchanged) · npm test 7 suites green.**

- **F4** — `runner/meetup.tsx`'s terminal guard was a deny-list; 0117 is the first writer of
  `no_show` and `incident_review` and neither was listed. Inverted to the allow-list this tree
  already uses twice, so a future terminal defaults to bouncing. `incident_review` gets 0117's own
  「확인이 필요해요」 (`0117:644`), never 「더 진행할 수 없어요」 (D3).
- **F3** — the 3-hour ceiling was a sentence with no gate. (a) the four impossibility sentences are
  gone; copy states elapsed time + a recommendation. The ceiling number is deliberately **not**
  written into the string — `LATENESS_CEILING_MS` is injectable and 「3시간」 would go quietly false
  the day Sean retunes it. (b) `pastCeiling` gates the preflight and both action blocks at
  `runner/meetup`, the chokepoint all four runner entrances pass through. Gated `=== false` so a
  slow `info` fetch never strands a punctual runner.
- **F2 client half** — entry is pre-custody-only; **resolution is not**. The premise comment said
  otherwise and two strips promised 「자동으로 …되지 않아요」. Both struck.
- **F7 (client half of F1)** — client and server drew the D3 line with different predicates.
  `custodyOf()` now mirrors `_checkin_custody` exactly. Four readers fed `lateness()` with
  `arrived_at` and `runs(started_at)` but **neither stamp**; all four now load both columns.
  `fetchInFlightRunnerJobs` shares its select string with `fetchRunnerJobs` and would have been
  missed by a single-site edit — the assertion that caught it is worth keeping.

**Tests: lateness 65 → 71, late-copy 34 → 84.** The `!resumable` branch had **zero** coverage
before — which is exactly how four impossibility sentences survived. Every new pin is
mutation-verified in both directions.

**Records corrected, not deleted:** §13 C2 (which stated the custody rule *outright wrong*), §4.3
C5, the FM4 registry row, and the stale 「종점만 남는다」 comment in `lateness.ts`.

### What I did NOT close, and why

⚠ **F3 is only PARTIALLY closed, and the record now says so.** The door that needs **no taps** is
still open: `runner/meetup.tsx`'s mount effect fires `runnerEnroute()` before `info` has loaded, so
`pastCeiling` is necessarily `false` at that instant. Merely opening the screen still flips a
17-day-old `confirmed` booking to `runner_enroute` and pushes the owner 「러너 이동 중」. Closing it
from the client means adding `info` to that effect's deps, which reinstalls the subscription and the
8s poll — the meetup stage machine/polling/confirmHandoff flow is under **DO-NOT-REFACTOR**. It
closes with Sean's Q4 and one server refusal, not from here.

Verified while checking that the gate strands nobody: past the ceiling the runner still sees the
late notice, the map, the pickup address, and a live **보호자 채팅** chip — which is exactly what the
new strip recommends. The advice has a real route on the same screen.

---

## 3. Still open from the 36-agent audit

F5 (mislabelled handoff frame — wants Sean's eye), F6 (server: `fetch_checkin` publishes each
party's free-text reason; **must close before the flip**), F8 (runner readers exclude both new
terminals — needs a new `closed` `RunnerJob` arm plus calendar/home surface, i.e. new surface),
F9, F10, F11, and the doc items F12–F18. The durable F1–F20 record with file:line is at
`…/wf_a68ecb4d-309/journal.jsonl` (longest string value = the synthesis).

This session's blind review of 0117 raised **~38 findings across five lenses**, of which the
verifiers refuted only one. Recurring themes beyond §1: the deadline arm terminating a live
post-custody run (independently rediscovered by 4 of 5 lenses — this is F2's server half, still
unfixed); `_resolve_checkin` writing `incident_review` from `confirmed`, an edge `0066` refuses;
`state_after_the_fact` filing the **speaker** in `booking_faults.party`, the column §3 defines as
the party **at fault**; and the forbidden "waiver" framing surviving in durable artifacts Sean's
ruling required 0117 to fix.

---

## 4. ⚠ Environment — a fresh worktree cannot run this app

1. `ln -sfn /Users/sean/dev/daengrun/app/node_modules app/node_modules`
2. `ln -sfn /Users/sean/dev/daengrun/app/.env app/.env` — gitignored; without it Metro dies at
   `supabase.ts:12`
3. `npx expo start --clear` — the Metro cache lives **inside** the shared `node_modules`, so a new
   worktree bundles a *different* worktree's tree until cleared
4. **Delete the node_modules symlink before committing — and restore it after.**

**Now with the reason, which was never written down.** `app/.gitignore:4` is `node_modules/` **with
a trailing slash, so it matches a directory and NOT a symlink.** Once you replace the directory with
a symlink, `git status` shows `?? app/node_modules` and `git add -A` would commit it. That is why
the step exists; it is not superstition. Measured this session:
`git check-ignore -v app/node_modules` succeeds on the real directory and **fails on the symlink**.

⚠ This worktree came with a **partial** real `node_modules` (396 entries vs the main clone's 499,
missing `eslint`) — `ln -sfn` against an existing directory silently creates
`node_modules/node_modules` instead of replacing it. Check `readlink app/node_modules` after linking.

⚠ The installed sim binary is `com.seankookim.daengrun`, the **old** bundle id, so the Naver appname
fix at `13749af` cannot be validly tested there. Nothing has ever run on hardware.

---

## 5. Waiting on Sean

1. **🔴 NEW — the `_checkin_custody` grant (§1).** Not a decision, a one-line fix, but whoever
   deploys 0117 must have it in hand: without it the deploy breaks owner cancels immediately.
2. **Q4 — is the 3-hour ceiling a rule or a recommendation?** This is now the load-bearing one for
   the client: the tap doors are closed, the no-tap door cannot be closed from here, and the copy
   is deliberately non-committal until a server rule exists. (a) real rule — server refuses
   `enroute`/`confirm_handoff`/`start_run` past the ceiling; (b) client gate only — what shipped;
   (c) advisory only — reclassify FM4 as accepted.
3. **CRIT-1 flag window.** 0117 ships the clock off behind a flag; the client does not know about
   it. Flip with the deploy, or the copy learns the flag?
4. **F5's mislabelled handoff frame** — UI change, wants his eye.
5. **Stop-reason build** — ③+③-A settled (§8-bis), blocked on deploy.
6. **Q3 — does each party see the other's free-text stop reason?** Must be decided before the flip;
   the strings are immutable in two places once written.

Settled, do not re-litigate: runner home ① · grace 30 / ceiling 3h · profile nudge ② with no dismiss
· late-booking lab approved as amended · stop-reason ③+③-A · B10 is a FALSE item · `radar.tsx:141`'s
analyser flag persists **by design**.

---

## 6. Two notes on method

**codex returned nothing usable this session.** Two runs (10 min foreground, then background with an
explicit "read at most these five files, produce only findings" instruction). Both times it read
files and exited 0 with **no verdict at all** — 833KB and 273KB of `nl -ba` output and not one
finding. It contributed nothing to this slice; the review value came from the five-lens workflow and
from re-deriving claims by hand. Budget accordingly rather than blocking on it.

**The codebase was right again.** The audit prescribed gating `runner/meetup.tsx:558,573` and said
nothing about the preflight gear block between them — but leaving it would have left
「세 가지를 확인해야 인계를 받을 수 있어요」 pointing at a button that no longer exists. Read the
surrounding block, not just the two lines you were handed.
