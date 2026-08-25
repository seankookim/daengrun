# Session handoff — spec-v2 session, 2026-08-25 afternoon (v6)

**Read with this:** `/announcer` (method) ·
`docs/plans/2026-08-25-club-delegation-spec-v2.md` (**the club spec of record** — coupled
machine, per-side/per-state screens, host respec, Mode C algorithm, six gated slices, review
log §15; Sean's twelve 🔴 in its §14) ·
`docs/contracts/r17-sweep-per-row-commit-contract.md` (R17 remainder: shelf design + DEFER
verdict + the flip-activation re-scope + Sean's User Challenge) ·
`docs/decisions/awaiting-sean.md` §0-undetricies (his seven answers, VERBATIM, with
dispositions) · the console artifact
<https://claude.ai/code/artifact/aad92054-9264-4431-9835-d03ef86b3f6b> (Sean's single place
to look — CURRENT as of this handoff). Prior handoff archived at
`docs/session-handoff-archive-20260825-v5-morning.md` — ⚠ it asserts production 0116, 0117
unlanded, §4.2 unruled, spec v2 unstarted: ALL FALSE since this morning's landings. One R17
reviewer grounded on it and had to be corrected mid-review; verify any handoff's status table
against the live system before building on it.

Tags: **[verified-now]** checked this session against code/live/gate · **[reported]** a peer
said so, unconfirmed by me · **[from-history]** earlier in conversation.

---

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Production | **0119 head.** 0117·0118·0119 + the client mirror deployed together this morning (combined harness 825/0; five edge functions redeployed for parity — see the REGISTRY 0117 row's deploy record). Charging OFF · late-booking clock OFF (`late_protocol_live_since` null) · 0 payments · 0 billing keys · 11 auth users. | [verified-now] live ledger table, twice independently (this session + announcer v5), plus payments/billing_keys re-queried post-deploy |
| Trunk `redesign-v4` | ≥ `7fcc91a` — carries the deploy-morning landings, Sean's seven answers + their build-item commits (Q1/Q2+Q3/Q7), the counsel-brief 4th question, spec v2, the R17 contract+review, and ui6's 0122/157 claim row. **Trunk = production migrations: binaries are safe on devices.** | [verified-now] |
| **Club spec v2** | **DONE, LANDED on trunk.** Grounded in three at-source scouts; hardened by two blind adversarial rounds (fresh Claude voice 15 findings, codex 9 — several design-breaking, every one answered in-design; dispositions in §15 of the spec). Six slices S1-S6 sequenced, each gated: **nothing builds until Sean answers §14** (twelve questions, most one word). S5 additionally hard-gated on the finish-ceiling ruling; S6 on the counsel brief. | [verified-now] |
| **Runner-money strip** (announcer v5) | contract v2.1 (`b310442`, three blind rounds) · migration **0121 + suite 156 AUTHORED and pushed** @ `b6f3d13` on `claude/runner-money-strip` (server half complete: §A-§F net objects, §G two-step seal, §G′ club_fare revoke, §H incident redaction incl. historical sweep) · client swap + deno half IN PROGRESS · measurement next · **NOT landed, NOT deployed** · client-atomic with §G (0088 law). v5 is merging trunk into the branch and will claim its exact api.ts function surfaces in the in-flight table with the client-swap commit. | [reported — v5's own words, this afternoon] |
| **R17 remainder** | **DEFERRED by dual-voice /autoplan review** — the lock-convoy premise fails load arithmetic at pilot scale (≈0.1-0.3 candidates/tick at 50 users; the sweep is deployed but dormant behind the null flag), and the per-row-commit contract as drafted had four design defects (recorded IN the contract). Re-scoped to a **flip-activation package** (preflight · per-arm LIMIT · statement_timeout fuse · 250ms lock wait · partial unresolved-deadline index · off-peak first flip with backlog drained manually) built when the clock flip is scheduled. **USER CHALLENGE queued to Sean** (his queue said build; both models say defer): console card A/B. No migration number is held by this work. | [verified-now] |
| ui6 / Q-slices | Sean's seven answers executing (Q1 care stats · Q2/Q3 photo ASK not gate · Q7 원천징수 small-once landed this morning); the Q6 동 slice renumbered **0121→0122, suite 157** after collision 7 (below) — REGISTRY row claimed on trunk FIRST, files rename pending their live blind reviewer's return. Touches `addresses.dong`, a definer 동-surface, `runner/requests.tsx`, `runner/home.tsx` — no club files. | [reported + row verified on origin] |
| 0120 location law | Parked at `b06f878`, unchanged, clock not running. | [from-history, unchanged] |
| Console | Refreshed three times today; current: spec-v2 §14 card on top, R17 challenge, fee 10-vs-5, custody A/B, 맹견 conditions, feed_posts, Q5 answer-back, board readership, standing items. | [verified-now] |

## 2. Sean's words today — where they are

Morning (verbatim in `docs/decisions/2026-08-24-sean-ui-club-commentary.md` §08-25): club
clarified + greenlit with riders · Mode C = build the algorithm · 도그스하이 · rescue deleted.
Midday (verbatim in `awaiting-sean.md` §0-undetricies): **all seven pick-sheet answers** —
Q1 러닝 리포트 B① + care stats · Q2 no traps, huge photo nudge · Q3 photo-less accepted +
reminders · Q4 12pt stays (closed) · Q5 clarification returned (his counter-question about
runner-side screens is ANSWERED on the console: yes, requests/calendar/availability are
built) · Q6 RULED distance+동 on request cards (server slice dispatched) · Q7 keep, small,
once. Plus: *"feel free to do 0117 whenever is apt"* → landed + deployed same morning.

**STILL HIS, in blocking order:** spec v2 §14 (twelve — blocks all club slices) · CRIT-1
clock flip · R17 challenge A/B · fee 10%-vs-5% unaccepted cancel · custody durable-attendance
A/B · 맹견 refused-vs-conditions · breed-alias scope · feed_posts `using(true)` vs the name ·
board readership (spec 14.9) · counsel briefs (now FOUR questions — S6's gate) ·
community/account commentary ("later").

## 3. Method lessons this session

1. **Collision 7 (near-miss, 0121): a claim living in a peer message is invisible to the
   hook and the in-flight table.** ui6 announced 0121 mid-build by message; v5's 0121 file
   reached origin first, hook-verified, in good faith. Caught only because one session held
   both claims. The mechanical fix, already adopted by ui6 for 0122: **the REGISTRY in-flight
   row precedes authoring, not the push.** (Also in the migration-ledger memory.)
2. **A stale handoff poisons downstream reviewers.** The R17 CEO voice grounded on the
   morning handoff's status table and produced findings from a world where 0117 was
   unlanded. Corrected before weighing. When a reviewer's input includes a handoff, hand it
   the live facts explicitly or instruct it to re-verify the table.
3. **CEO-review-before-build paid for itself in one day**: R17's remainder was a
   fully-contracted, fully-trapped slice that two independent voices killed with arithmetic
   the contract never did. The load-model line ("candidates/tick × per-row cost") is now the
   mandatory first line of any performance-motivated slice.
4. **A contract under review is a moving target** — the strip's `rate()` helper died between
   my citing it and the spec landing (view bodies don't shield function EXECUTE). Citing a
   contract-in-flight requires the re-verify-at-bind clause the spec now carries.
5. **Blind dual-voice review works on SPECS, not just migrations**: 24 findings against spec
   v2 draft 1, three design-breaking (the free-24h repricing, the inescapable state, the
   enroute money dead zone), all caught before a line of SQL existed.

## 4. Fleet & peers (as of handoff)

- **This session** (spec-v2, worktree `club-delegation-spec-v2-a41fbc`): queue complete —
  spec v2 landed, R17 reviewed+challenged, console current, this handoff. Holds nothing
  uncommitted; everything pushed to origin (branch + trunk).
- **announcer v5**: the strip (status above). Harness: FREE — nobody is running it;
  announce-before-run remains the law, one run machine-wide.
- **ui6** (`daengrun-redesign-v4-77ea99-1c`): Q-slices + the 0122 rename pending its
  reviewer. Standing agreement: no club-screen edits before Sean's §14 words; pings me first.
- Coordination protocol that worked today: claims verified at source in BOTH directions
  (every relay re-checked by its receiver), deviations announced before acting, corrections
  relayed to all recipients.

## 5. Next steps, in order

1. **[Sean]** §14 words → S2 (member board) unlocks for the server side, client half to ui6.
2. **[v5]** strip client swap + deno → measurement (announce harness) → land atomic.
3. **[ui6]** 0122/157 rename after review → land the 동 slice.
4. **[Sean]** R17 challenge A/B — if A, the flip-activation package rides CRIT-1 planning;
   if B, the corrected contract builds from the shelf (its four defects are annotated).
5. **[any]** When CRIT-1 flip is scheduled: the flip-activation package (preflight counts,
   LIMIT, fuse, index, off-peak runbook) is the pre-flip slice regardless of R17's answer.

## 6. Gotchas that will bite again

- The morning handoff's world is gone: 0117 is deployed, the clock flag is the only gate
  left. **Do not re-litigate the deploy** — verify the ledger table, not `migration list`.
- One harness at a time, machine-wide; `[axes] X8` still reds randomly (~1/17) — rerun,
  never "fix".
- REGISTRY numbers: two-sided at write time, and now: **row precedes authoring** (lesson 1).
- The spec's slice gates are LOAD-BEARING: S5 without the ceiling ruling ships an
  inescapable custody state (round-1 F2's exact finding) — the gate is not process theater.
- `docs/contracts/r17-sweep-per-row-commit-contract.md` §1/§3 must NOT be built verbatim —
  the STATUS banner and the report's defect list exist precisely because a future session
  might read the body and start typing.

## 7. Environment at handoff

This worktree: clean, branch `claude/club-delegation-spec-v2-a41fbc` = trunk + this handoff
commit, everything pushed. No migration numbers held. No harness run this session (none
needed — docs only). Scratchpad artifacts (scout reports, review logs) die with the session;
everything that matters is in the docs above, on origin. [verified-now at write time]
