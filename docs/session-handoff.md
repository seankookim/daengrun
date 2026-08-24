# Session handoff — announcer v4, 2026-08-21 (full day + night)

**Read with this:** `/announcer` (method) · `supabase/migrations/REGISTRY.md` (the ledger AND the
spec for two unbuilt slices) · `docs/decisions/awaiting-sean.md` (**8 rulings landed today** —
§0-quinvicies has six of them) · `docs/pre-charging-checklist.md` (**four hard blockers**, the flip
gate) · `docs/plans/2026-08-21-late-booking-protocol.md` §12 (the contract 0117 implements) ·
`CLAUDE.md` (the laws) · `docs/handoff-client.md` (ui5's ending state). Prior handoff archived at
`docs/session-handoff-archive-20260821.md`.

Tags: **[verified-now]** I checked it this session against code/live/gate · **[reported]** an agent
said so and I did NOT confirm · **[from-history]** earlier in conversation · **[uncertain]** inference.

---

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Trunk `origin/redesign-v4` | `168d29f` | [verified-now] |
| **Production migrations** | **0001–0104, 0106–0116 applied. 0116 IS live** | [verified-now] — queried `supabase_migrations.schema_migrations` directly |
| ⚠ `supabase migration list --linked` | **MISREPORTS the head** — its JSON carries a trailing empty entry; parsing "last" gives 0115. Query the ledger table instead | [verified-now], cost me a false alarm |
| Edge functions (8) | create-booking-hold v10 · transition-booking **v34** · settle-run v14 · open-drop v8 · geocode-address v1 · **collect-charges v2** (deployed today) · confirm-payment v1 · delete-account v1 | [verified-now] `functions list` |
| Charging | **OFF** — `payments_live_since` null · 0 payments · 0 billing_keys · TOSS_SECRET_KEY unset · Vault secret absent | [from-history], re-verify |
| App builds | **ZERO ever.** Everything native is code+gates only | [from-history] |
| Runner money owed | **₩111,657 across 8 ledger rows, 0 payouts ever** (test runners; mechanism live) | [verified-now] |
| 0117 late-booking | branch `claude/late-booking-server-stage2` @ `e132b3d`, **18 commits, all pushed, NOT landed**. Harness 782/0, deno 231/0 | [reported] by its implementer; I did not re-run |
| 0118 club cancel-fee | branch `claude/club-fee-slice` @ `d1a9ea4`, **pushed by me at handoff**. 857-line migration + 546-line suite. **NEVER MEASURED — no harness has ever run on it** | [verified-now] (existence + push), [verified-now] (never measured) |
| 0119 맹견 gate | branch `claude/wf-maenggyeon` @ `2371502`, **pushed by me at handoff**. **NEVER MEASURED** | [verified-now] |
| 0120 location retention | branch `claude/wf-location` @ `8d3d5cc`, **pushed by me at handoff**. **NEVER MEASURED**. ⚠ Touches `app/` (see §7) | [verified-now] |
| Counsel-brief de-staling | **PRODUCED NOTHING.** `claude/wf-docs` has 0 commits — that agent died before committing | [verified-now] |
| ui5 (client session) | Stage-1 complete, audited, on trunk @ `ca8b3a1`. Ended clean, no claims held. `npm test` now EXISTS and is green across six suites (`app/` had zero this morning) | [reported] |
| **0117: two NEW blockers** | Found by a 36-agent client-side audit (run `wf_a68ecb4d-309`, 31 raised → 20 survived). **Both inert today; both fire on the first late booking after the flag flips.** See §7-bis | **F1 [verified-now]**, F2 [reported] |

---

## 2. Goal & current state

Pre-revenue Banpo pilot. PMF gate = 60% M1 rebooking. **Nothing has ever run on a phone; there is
1 real user.** This session was coordination + four migration slices in parallel.

| Workstream | State |
|---|---|
| 0116 flip-blockers | **DEPLOYED + VERIFIED LIVE.** The only thing that shipped to production today |
| 0117 late-booking protocol | **5 review rounds, NOT landed.** Round 5 (blind) found 9 more incl. 3 that contradict Sean's own rulings. Round 6 fixes were in flight when the process died |
| 0118 club cancel-fee | Authored by **Codex**, committed, pushed, **unmeasured** |
| 0119 맹견 gate | Built by a workflow agent, **unmeasured** |
| 0120 location retention/ledger | Built by a workflow agent, **unmeasured**, crosses into `app/` |
| Counsel briefs | **Untouched.** Still stale, still unsent, clock still running |
| Client (ui5) | Complete for the session; its contract §12 amended after its own miss |

---

## 3. What shipped this session (by theme)

**Production (the only deploy).** `0116_flip_blockers` — landed `7b4bf0d`, deployed via
`scripts/deploy-migrations.sh --push 0116_flip_blockers.sql`, `collect-charges` → v2, verified live
read-only (prosrc guards, ACLs, proconfig), recorded DEPLOYED at `a69a0be`. **Recut before landing:**
its §B (club cancel-fee) was CUT at Sean's gate — see §6.

**Trunk (non-deploy).** `f0bc2bc` suite-70 rewrite (nine unordered `LIMIT 1`s; see §10) ·
`c3ff528`/`c7dac14` fleet-record corrections · `ebec097`/`8af8ffb` client claims ·
`b98fa41`/`613ae9e`/`2985684`/`77a82d1`/`eed8af0` Sean's rulings · `168d29f` contract §12 amendment
(ui5's, after its own miss).

**Branches, unlanded:** 0117 (18 commits) · 0118 (1) · 0119 (2) · 0120 (1). **All four pushed** —
I pushed the last three at handoff time; they existed only on local disk after the worktrees were
torn down.

---

## 4. Standing doctrines (canonical: `CLAUDE.md`, `docs/fleet-roster.md` §7-bis, `/announcer` §10-14)

1. **Verify at send time; never relay.** Every agent report is evidence, not fact.
2. **Reviewer ≠ author, and the third voice is a NEW BLIND CODEX** (Sean, today). Give it the code,
   the contract, the rulings — **never** the author's reasoning. See §6 for why this is load-bearing.
3. **Closure = the unauthorized operation refused at the server boundary**, never "the UI no longer
   offers it."
4. **Migration numbers two-sided at write time**; the REGISTRY row travels in the same commit as the
   file; the announcer arbitrates contention.
5. **Ship means push** (CLAUDE.md corrected today — it had said "Sean pushes" for 11 days after the
   grant). Uncommitted/unpushed work is invisible and dies with its process — **it died four times
   today.**
6. **Honesty laws**: no dead buttons · refusals rendered as refusals · loading ≠ 0 · bind real fields
   or omit · **never claim device-visual success.**

---

## 5. Working-relationship norms (Sean)

- Writes short and decisive: "sure", "B", "do the deploy", "ask why they stopped", "use codex here
  instead of v3". **His latest word governs.**
- **Picks by looking** — labs by number, screenshots. Dislikes choosing between things he can't see.
- Grants broad autonomy, expects **gates not permission** — but irreversible/physical things stay his
  (Apple 2FA, dashboard toggles, credential values, filings, forwarding counsel briefs).
- Wants plain-language reports under a `–––––REPORT–––––` banner with **lettered answer choices**.
- **Record his words verbatim with `[end of his words]`.** Mark stand-in decisions 🔵, never ✅.
- He reads the console artifact: <https://claude.ai/code/artifact/aad92054-9264-4431-9835-d03ef86b3f6b>
  (decision queue) and <https://claude.ai/code/artifact/8d273666-cefa-464c-b2c7-9645e5f363d9> (gap map,
  60 items, built by a 7-agent fleet, freshness-verified).
- **He asks for correction when he suspects drift** ("are you synthesizing?", "codex has been running
  forty minutes") — treat those as prompts to verify, not reassure.

---

## 6. Decision log with WHY

**Sean's rulings today (all verbatim in `docs/decisions/awaiting-sean.md` §0-quinvicies / §0-tricies):**

1. **Club fee ladder** — "Use the club rules as written": free ≥24h · 10% late · 20%
   post-accept/no-show · 50/50 platform:runner. The 미확정 marks are lifted.
2. **§0-quinvicies** — a **server session** builds server halves; no client exception.
3. **Grace 30 min / ceiling 3 h.**
4. **"ask why they stopped."** — `cannot_proceed` carries a reason.
5. **"Join the pool — accrue it."** — the runner's club-fee share writes to `ledger_items` despite
   `payouts` having no writer. **Basis he was shown:** 8 existing writers already do this;
   production holds ₩111,657 owed / 0 payouts. Rejected: a second rulebook for one obligation.
6. **The silent-stalemate rule** — "Nobody pays, nobody is paid." 3h+ silence with no evidence and no
   statement moves **no money in either direction**. **Rejected:** framing it as "waiving the owner's
   fee", because that is the same act as taking ₩12,450 from the runner on a timer (0068 forbids).
7. **Run-watcher separated** — a run that starts and never ends is NOT the lateness protocol's job;
   own future slice; the shipped screens stop implying a watcher.
8. **Fee quote** — expose a real party-gated `quote_cancel_fee`; words as the stopgap. 0066's
   "not a client quote API" posture **knowingly reversed**.

**My reversals (both mine, both refuted by review):**
- I wired the club-fee mint inline in 0116 §B (🔵). **Reversed** — it made live copy false, charged
  retroactively, and stranded intents. Then Sean cut §B entirely.
- I "aligned" the sweep's existence predicate to the mint's. **Reversed** — it enabled a
  ₩15,000+₩20,000 double charge. The predicate is deliberately WIDER; B1 ⓒ′ pins it.

**Refusals:**
- **I refused to deploy 0117** after Sean asked ui5 to do it — the blind review had landed six
  blockers *after* he asked, including "no safe deployment order in either direction."
- **ui5 refused the same deploy** and routed it to me, correctly.
- **Codex refused to build 0118** at the ledger-accrual question and wrote nothing until Sean ruled.

**The blind-reviewer decision (Sean's, and the most consequential of the day).** Two informed Codex
rounds passed 0117. The first **blind** round found **12 findings, 6 blockers** — in code the prior
reviewers had read. Round 5 (blind again) found 9 more. **Why it works:** a reviewer holding the
contract reads a gate as *satisfied-by-existing*; a blind reviewer asks whether the gate refuses
anyone. ui5's own conformance verdict had quoted and passed the exact broken gate.

---

## 7. Architecture & contracts

- **DO-NOT-REFACTOR:** fitness collapsing hero · meetup stage machine (additive renders only) · three
  availability predicates · runner-home ① design + `liveOwnsCoral` · owner-home header must never be
  pinned · `StatusBarCover` stays the **last child inside `TabSwipe`**, before the root `BottomNav`.
- **⚠ 0120 ORDERING/COUPLING (easy to lose, expensive to relearn):** `0120` revokes the client's
  direct `runs.trace` SELECT. **The migration and its `app/src/lib/api.ts` change must land in ONE
  commit** — a column revoke does not hide a field, it **fails the entire PostgREST request** (the
  0088 class where signup 403'd for everyone). The branch already pairs them; do not split.
  ⚠ This puts a *server* slice inside ui5's claimed file. Coordinate before landing.
- **0117 deploy order: MIGRATION FIRST, then the edge function.** Edge-first pays runners ₩0 on
  en-route cancels (measured). The migration's own comment claiming edge-first is safe was FALSE and
  is corrected. [reported]
- **0117 is NOT an inert deploy.** Only the *clock* is flag-gated (`ops_flags.late_protocol_live_since`).
  At push time the fee ladder swaps, a fee trigger attaches, quote/fetch/answer become callable, and
  an ungated repair cron can write historical ledger rows. Charging being off prevents *collection*,
  not wrong stored fees or wrong runner-share decisions. [reported]
- **`payout_state` has two truthful terminals** for a completed+resolved delegation: `released` (v1
  sync, 0040:233) and `payable` (v2 return path, 0045/0046/0069/0070/0072). `payable` is the standing
  **fingerprint of the unbuilt payout loop**, not corruption. [verified-now]

---

## 7-bis. ⚠ THE TWO NEWEST 0117 BLOCKERS — read before touching that branch

Found after round 5, by a 36-agent audit the client session ran (`/workflows` run
`wf_a68ecb4d-309`, four lenses, refute-as-default; 31 raised → 20 survived). Full report with
file:line and cheapest fix per finding is in that run's `journal.jsonl`. **Neither is in any Codex
round.** Both are inert while `ops_flags.late_protocol_live_since` is null and fire on the **first
late booking after the flag flips.**

**F1 — a timer writes `no_show` over the owner's own attestation. [verified-now]**
`_checkin_custody` (0117:159-170) returns `'post'` only when **both** handoff stamps are non-null.
But one stamp is the *normal interval*, not a failure: `transition-booking/index.ts:314` writes one
stamp per request and `:329` notifies the other side to confirm. So: owner taps 인계했어요, the
runner's phone dies → the deadline arm sees `runner_enroute` + owner stamp only → falls to line 166
→ classifies `'pre'` → writes `no_show`. **`0066:56` makes that irreversible**, the run can never
settle, and `0075:750` fires a km release for a dog that is out walking.
**Fix (their words):** one guard before the terminal write, **scoped to clock causes only** — do
**NOT** touch `_checkin_custody` itself; the cancel guard and 0072/0116 money share it.

**F2 — a check-in armed pre-custody terminates a run in progress. [reported]**
Entry is pre-custody-only; **resolution is not.** The sweep's silence arm selects on the check-in row
alone and nothing closes an open check-in at the handoff line. Armed 10:33 → handoff 10:50 → run
starts 10:52 → deadline 11:03 flips a run eleven minutes in to `incident_review`, which per
`0097:80` has **no marketplace money exit** — the runner is permanently unpaid and it takes a manual
DB job per case.
**Fix (their words):** extend the concession already present at ~`:535`/`:555` (`superseded` — the
run DID start, run-end owns it) to the silence arm. [I verified those `superseded` arms exist;
I did NOT verify the silence arm lacks it.]

**§12 CONTRACT AMENDMENTS — round 6 must use the AMENDED clauses, not the originals. [reported]**
After the blind reviewer found the `current_user`-inside-DEFINER gate that a conformance review had
passed, the client session amended §12 to say what a gate must **REFUSE**, then applied that rule to
its own remaining clauses: **C1/C3/C4/C5 name a mechanism and no refusal**, and **C2 (`§13:315`)
states the custody rule OUTRIGHT WRONG** — the server built something stricter, so client and server
disagree about the D3 handoff line while both "conform". Replacement wording for all five is in the
audit run's journal. The trunk amendment is `168d29f`; confirm it carries all five before relying on it.

## 8. File map

- `supabase/migrations/REGISTRY.md` — the ledger; **row 0116 carries the full spec for the held §B
  slice**; in-flight claims table lives here (announcer writes client claims on their behalf).
- `docs/pre-charging-checklist.md` — **four hard blockers** added today: club-fee slice landed ·
  incident `settled_at` reconciled · refund-shaped rows have a reconciliation arm · the 0066
  stale-enroute carve-out.
- `docs/decisions/awaiting-sean.md` — 35 sections; §0-quinvicies holds six of today's rulings.
- `supabase/tests/70_axes_suite.sql` — rewritten today (§10).
- `supabase/tests/harness.sh` — **ABSOLUTE path only**; its self-pin now resolves `BASH_SOURCE` at
  line 2 (it false-fired twice before that fix).
- `scripts/deploy-migrations.sh` — **the only sanctioned deploy path**; dry-run first, then
  `--push <exact filenames>`.

---

## 9. Pending on Sean

**Ops (only he can do):** two dashboard toggles (email provider OFF; redirect allowlist →
`daengrun://login`) — ⚠ **never `supabase config push`**, config.toml has no `[auth]` section ·
TestFlight 2FA (bundle id is fixed, safe now) · **forward the two counsel briefs — Q6's notification
clock is on day 2–3 and the de-staling agent produced nothing** · one real signup on a phone · the
paperwork chain (사업자등록 → 통신판매업 → PG → 자동결제 심사) — the longest pole, not started.

**Decisions (each blocks something):**
- **The 0117 deploy gate** — it is not inert; migration-first only. *Blocks: the whole slice.*
- **The flag window** — between deploying 0117 and flipping the clock flag, the app will say "late"
  while nothing acts. **A** flip with the deploy · **B** teach the client the flag. *Blocks: honest
  copy at deploy.*
- **Reason privacy (raised by blind round 5, NOT yet asked)** — a `cannot_proceed` reason ("door code
  1234") is stored in two immutable tables, **shown to the counterparty**, and **survives account
  deletion**, and 0115's retained-data disclosure names neither table. He authorized *asking and
  storing*, not counterparty exposure + permanent retention. *Blocks: 0117 landing.*
- **§4.2 fee arms** beyond the carve-out · **the <24h 10% tier's ceiling-awareness** · **orderName
  wording** (still prints the retired brand + a banned word) · **flip-day in-flight stock rule** ·
  **F.1 card-less booking policy** · **ops recipients** (one sentence: who receives, what ack means —
  every detector the fleet built still ends in `console.error`).
- **Looks:** coral ground A/B · handoff-CTA gating · react-doctor 3-part ruling · three route names
  advertising wrong lengths · the "why did you stop" lab (`2cc5cd1`, three variants).

---

## 10. Known bugs, gotchas, false-success producers

- **`supabase migration list --linked` misreports the head** (trailing empty entry). Query
  `supabase_migrations.schema_migrations` directly. [verified-now]
- **Parallel harness runs BRAID.** Two runs on one postmaster produce phantom reds with two different
  frozen `now()` values in one `_t`. Serialize all harness runs. [reported, twice, consistent]
- **Codex's sandbox cannot run this harness** (`initdb` shared-memory denied) and cannot `git fetch`
  or stage. Codex authors → a Claude agent measures → a **new blind Codex** reviews. [verified-now]
- **`codex exec` detached wedges without `< /dev/null`** — looks identical to a long review. Tell:
  no child processes, ~0 CPU, no session-log writes. Cost an hour. [verified-now]
- **A pin that checks one arbitrary row is a coin flip.** Suite 70's `[axes] X2` was 5-of-7 green by
  luck. Removing `LIMIT 1` surfaced the real `payable` finding. [verified-now]
- **`not (A and B)` is NULL when a field is NULL and WHERE silently drops the row** — the fail-open
  this repo has hit in 0058 F1, 110 S2, 0116 §D, and again today. Use `not coalesce(..., false)`.
- **Inside `SECURITY DEFINER`, `current_user` is the OWNER** — it cannot identify a caller. Any
  `current_user not in (...)` exemption is an open door. Present in 0117 (fixed) and **still present
  in shipped `confirm_return_tx` (0083/0096)** — granted to `authenticated` only, no anon, so **not
  reachable by a normal user** (their JWT always carries `sub`). Latent, not urgent. [verified-now]
- **A green mutation is worthless until you prove the mutation applied** — two "greens" today were a
  driver bug and a structurally-blind pin. [reported]

---

## 11. Known-good — do not "fix"

0116 as deployed (all four fixes verified live) · the deploy wrapper + HELD · the pre-push two-sided
hook · the honesty-states UI · 0114's twelve-token refusal set · the `routes_name_km_agrees`
constraint · `run2-` topic namespace · suite 70's rewritten pins (universal + non-vacuity +
NULL-safe) · ui5's stage-1 late-booking surfaces and its `app/test/run-*.sh` suites (they test
shipped code via esbuild, not copies).

---

## 12. Ideas & discussions not yet built

The **gap map** (artifact above) holds 36 back + 24 front items, ranked, chip-coded by what blocks
each, with 42 stale claims already dropped. Highlights not yet started: the payout loop (design:
ops-only manual journal, no automated bank movement) · card-register slice (`billing_keys` has ZERO
writers = 100% charge failure by construction) · ops routing (one INSERT + one secret multiplies
every detector the fleet has built) · moderation/CS/admin actor model · push delivery (nothing emits)
· i18n (absent, not even recorded as a deferral) · the two **ultracode master prompts** (front/back,
Codex-reviewed through 17 findings) — delivered to Sean as files, not yet used.

---

## 13. Strategic read

**The review machinery is now the most valuable thing this project owns, and it is also the thing
telling you to slow down.** Today, three independent adversarial rounds found 21 real defects in one
slice *after* it passed two informed reviews with green tests and exact mutation maps. That is not a
process failure — it is the process working. But the same signal says: **0117 is a 1,000-line money
protocol built against a contract that its own author admits was underspecified, for a feature no
user has ever seen, on an app that has never run on a phone.**

A 36-agent audit run by a *different domain's* session then found two more blockers that five
Codex rounds had missed — both of which write an irreversible terminal over a human's own action.
That is the fourth independent voice to find real defects in this one slice.

If Sean pushes back, my argument is narrow: **land 0116's siblings, then stop adding surface.** The
three unmeasured slices (0118/0119/0120) are each *small and closed* — measure, review, land, deploy.
0117 should land only after the reason-privacy ruling, because that one is not an engineering bug; it
is a promise to users about what happens to something they typed while their dog was in trouble.

And the thing that has not changed all day: **zero builds, zero interviews, one user, ₩111,657 owed
to runners nothing can pay.** Every slice today made the server more correct. None of them moved the
product closer to meeting a customer.

---

## 14. Next 1–3 steps

1. **[read-only]** Verify state before trusting anything here: `git fetch && git log --oneline -5
   origin/redesign-v4`; query the migration ledger table (NOT `migration list`); confirm the four
   branches still exist on origin.
2. **[local-edit]** **Measure the three unmeasured slices, one at a time** (0118 club-fee → 0119 맹견
   → 0120 location). Each needs: a worktree, `git fetch`, two-sided number re-resolution (**0118/0119/
   0120 were each assigned in isolation — verify no collision**), full harness, the author's predicted
   mutation battery, then a **blind Codex** review. None has ever been run.
3. **[local-edit]** **0117 round 6 must fix nine round-5 findings PLUS F1/F2 above PLUS use the
   amended §12 clauses.** The round-5 brief was dispatched and never returned — it exists only in
   the dead conversation. Re-derive it from the round-5 verdict (also not on disk) or re-run a blind
   review against `e132b3d` to regenerate it.
4. **[needs-user]** Put the **reason-privacy question** to Sean before 0117 goes further, and the
   **flag-window** choice with it.

---

## 15. Verification commands

**Safe:**
```
git fetch origin && git log --oneline -5 origin/redesign-v4
supabase db query --linked "select version from supabase_migrations.schema_migrations order by version desc limit 6"
supabase functions list
bash scripts/deploy-migrations.sh                     # dry-run, prints the pending set
PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH LC_ALL=C bash <ABSOLUTE>/supabase/tests/harness.sh
codex exec "<boundary line + prompt>" -C <dir> -s read-only < /dev/null
```
**Expensive / irreversible:** `scripts/deploy-migrations.sh --push <names>` · `supabase functions
deploy <slug>` · any `delete-account` invocation (deletes a real auth user) · `eas build` (Sean's 2FA)
· **never** `supabase config push`.

---

## Environment & agent state at handoff

**Nothing left on production.** No test rows, no flags flipped, no functions invoked to observe a
no-op. The only production change today was 0116 + collect-charges v2.

**Worktrees were torn down when the process exited** — `club-fee-slice`, `wf-docs`, `wf-maenggyeon`,
`wf-location`, `late-booking-server`, `announcer-v4*` no longer exist on disk. **Their branches
survive and I pushed all of them**, so nothing is stranded. Recreate with `git worktree add`.

**Agent work at handoff — all dead, none running:**
- 0117 implementer: delivered through round 5 (`e132b3d`); **round-6 fixes for blind-round-5's 9
  findings were dispatched and never returned.** That brief is in the conversation only — the next
  session must re-derive it from the round-5 verdict, which is NOT saved to disk.
- 0118: Codex authored, a Claude measurement agent was mid-run — **its work is in the commit; the
  measurement never happened.**
- 0119/0120: workflow builders committed; the measurement phase never ran.
- **`wf-docs` produced nothing** — the counsel-brief de-staling did not happen.

**Coverage gaps:** no harness has been run on 0118, 0119 or 0120. The blind round-5 findings on 0117
are unfixed. Three orphaned items have no owner: `confirm_return_tx`'s definer gate, suite 116's C19
fixture, and the <24h tier's ceiling-awareness.
