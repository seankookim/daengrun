# Codex review queue — state at 2026-08-28, and the batches still owed

Companion to `2026-08-28-codex-billing-chain.md`. This file exists so the next session does not
re-derive the batch plan, and does not mistake an attempted review for a completed one.

## Reviewed, verdict in hand

| slice | verdict | where |
|---|---|---|
| Billing/revocation chain — 0137, 0138, 0141, 0143, 0148, 0149, 0150 + `register-billing-key`, `revoke-billing-keys` | **REJECT · 7 findings** | `2026-08-28-codex-billing-chain.md` |
| `club_join`/`club_leave` client slice (`club/[id].tsx`, `api.ts` wrappers) | **REJECT · 3 findings — ALL FIXED** in `16412dc` | the commit message carries the full account |

## 🔴 ATTEMPTED AND DID NOT RUN — do not read this as reviewed

| slice | what happened |
|---|---|
| Board/profiles disclosure — **0136, 0139, 0145** | **QUOTA WALL.** `codex exec` burned the entire read — 194,913 tokens, **540 KB of stderr, 0 bytes of stdout, no verdict** — and died at the emit step with `You've hit your usage limit … try again at 2:33 PM`. **This is the characteristic failure, not the obvious one:** the log is LARGE precisely because the reading is what got burned. Detected by a three-state watcher (verdict · quota wall · process gone with no verdict), which is the only shape that tells this apart from 「still working」. The prompt is saved and the run is one command to repeat once quota returns. |

⚠ **Nobody may say this slice is 「under codex review」.** It is not. It has had no pass at all.

| Run-end money chain — **0144, 0147, 0152** + client half | ✅ **RESOLVED — REJECT · 12 findings** (1 CRITICAL, 6 HIGH). `2026-08-28-codex-runend-money.md`. |

⚠ **The UNRESOLVED row that stood here predicted this run had died, and that prediction was
WRONG.** Its stderr had gone flat at 1.27 MB with 0 bytes of stdout while a sibling run had already
walled the account — the exact signature of death at the emit step. It finished normally. **This is
the argument for writing 「unresolved」 rather than a guess:** the guess would have been wrong in the
direction that loses a CRITICAL finding and a confirmed live disclosure. Byte-growth and log size
are liveness *hints*; only the verdict grep and the process state are evidence.

## The batches still owed, ranked

Derived from the migration contents, not from filenames. Batches are chains that MUST be read
together, because this repo uses `create or replace` heavily and one file DROPS a function — so
reading a single file reviews a body that production does not have.

### 1. Board/profiles disclosure — **0136 · 0139 · 0145** — RUN THIS FIRST
Nothing here is behind a money flag, so **it is all reachable today by any signed-in user.**
0136 creates `club_session_board`; **0139 DROPS and recreates it** to add `owner_profile_id` /
`runner_profile_id`, reversing 0136's own contract §4 R8; 0145 then puts an RLS policy on
`profiles` whose predicate `_profile_board_visible` **delegates its authority to whatever
`club_session_board` currently is.**
> **Worst plausible defect:** a profile ID survives in a state where 0136 deliberately redacts the
> NAME (a courtship / pick-pending runner), which re-identifies exactly the person the redaction
> was protecting — and because a `profiles` policy inherits the same predicate, **one board leak
> becomes a general read of other people's profile rows.**
Also owed here: a DROP discards the ACL, so 0139 must fully restate grants, owner, `prosecdef` and
the in-body `search_path`. And 「member of this session」 may mean 「anyone who found an open session
and tapped join」 — `session_rsvp` has no membership gate and no host approval — while *reading*
like a membership check.
**Client half:** `app/src/lib/api.ts` (board projection incl. the two new ids) ·
`app/src/components/club-board.tsx` (the tap that routes to a profile) ·
`app/app/runner-profile/[id].tsx` · `app/app/club/[id].tsx` (the viewer gate).

### 2. Club membership / RSVP writers — **0134 · 0140 · 0142 · 0135 · 0146**
All `security definer`, all granted to `authenticated`, all writing one `session_dogs` /
`club_members` lifecycle. 0142 re-replaces `session_cancel_rsvp` to add a `for update`; 0140 binds
every writer at the TABLE via a BEFORE trigger rather than at each door.
> **Worst plausible defect:** a gate-ordering or lock gap lets a client reach a capacity-violating
> or terminal state — a second dog past the ruled 1-dog limit, a cancel that deletes a
> money-bearing delegation, or an approval on a row the caller does not own.
**Client half:** `api.ts` (the five RPC wrappers) · `club/session/[sid].tsx` ·
`club/console/[sid].tsx` · `club/companion/[sid].tsx` · `club/[id].tsx`.

### 3. Runner earnings read path — **0132**
Drop-recreates `my_ledger_rows`, replaces `my_week_stats`; both definer, both `authenticated`.
Re-keys a booking-keyed `runs` join.
> **Worst plausible defect:** a reassigned booking hands a previous runner another runner's run
> data — a DISCLOSURE defect on a client-callable definer, not an arithmetic one.
**Client half:** `runner/earnings.tsx` · `runner/home.tsx` · `owner/report.tsx`.

### 4. Phone PII definer — **0133**
`set_my_phone`, definer, `authenticated`. Its entire safety argument is 「no target parameter — the
absence IS the party gate」.
> **Worst plausible defect:** any normalisation or CHECK weakness writes or overwrites a phone
> number on a row the caller does not own.
**Client half: none — deliberately unwired** (0 callers). Review it knowing nothing calls it yet,
and note it is gated behind the lawyer item regardless.

### 5. Grant/schema contraction — **0151 · 0130**
Neither creates a function; both only remove reachable surface.
> **Worst plausible defect:** over-reach breaks a live caller, or under-reach leaves the grant it
> claimed to remove. An outage or a still-open grant, not a logic defect.
**Client half: none.**

## Two UNCERTAIN items nobody has settled

- 🔴 **0131 has SEVEN review rounds and NO RECORDED FINAL VERDICT.** The rounds live in commit
  messages and the file header; there is no artifact in `docs/reviews/`. The newest cross-reference
  (the 0142 REGISTRY row) says 「round 3 came back REJECT and round 4 is in progress」. **So it is
  either the most-reviewed file in the repo or the one thing standing between a REJECT and
  production, and the record cannot tell you which.** Settling this is cheap — read the round 5-7
  commits — and it should happen before anyone cites 0131 as reviewed.
- **0139 · 0147 · 0151 · 0152** are UNREVIEWED by *absence of artifact*, not by an explicit label.
  That is weaker evidence than the rows that say so outright; do not report it at the same strength.

## Method notes earned today — apply these to the next run

1. **Detect the verdict with `grep -cE '^FINDINGS: [0-9]+'`.** The prompt carries the literal
   `FINDINGS: <n>`, which cannot match a digit, so the echo is excluded BY CONSTRUCTION. Verify
   the detector against the prompt file itself *before* launching — it should return 0.
2. **Capture stdout and stderr separately.** The reading lands on stderr and only the answer on
   stdout, so stderr byte-growth is the liveness signal and stdout is the verdict. A merged log
   destroys that discriminator. Measured today: a genuine run climbed 34 KB → 578 KB on stderr with
   stdout at 0 until the very end.
3. **Watch THREE states, not two** — verdict · quota wall · process gone with no verdict. Today's
   quota wall would have read as 「still working」 to a two-state watcher, indefinitely.
4. 🔴 **Include the PARENT commit in the frozen export.** Codex raised this itself: the
   `git archive` + `git init` export has a single **parentless root commit**, so it cannot
   reconstruct a diff and has to review the whole file as if newly written. Export the parent too,
   or hand it the patch. This cost real review quality on the client slice.
5. **Re-freeze before each round.** An export predating your own landings reviews a tree that is
   not trunk — the staleness problem wearing a freeze's costume. Verify by hashing a few files
   against `git show origin/redesign-v4:<path>` before launching.
