# Session handoff — spec-v2 session, 2026-08-25 evening (v8)

> ⚠ **§1 was rewritten at 2026-08-26 ~11:00 KST from live measurement.** A full day and night
> of work sits between v7 and this. **Re-measure before building on any row, including the ones
> I just wrote** — v6 warned exactly this about itself and was stale within hours.
>
> **VERIFIED NOW:** production head **0127**, 125 migrations applied · trunk tip `b75362d` ·
> the 맹견 gate is GONE and verified live · the late-booking clock is LIVE · charging OFF.
>
> **🔴 ON A BRANCH, NOT TRUNK, NOT DEPLOYED — and deliberately so:** `0129` + suite `163`
> (`claude/club-delegation-spec-v2-a41fbc` @ `9893184`, harness **912/0**). It is the SECOND
> attempt at the club return-address arm; the first (`0128`) IS on trunk, undeployed, and was
> found unsafe by two blind reviews. **`0129` awaits its second reviewer and must not land on one
> head.** The pre-push hook refuses branch pushes carrying it, which is correct — that same
> mechanism is how `0128` reached trunk prematurely.

---

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Production | **0127 head — 맹견 gate REMOVED and LIVE.** 0117-0126 all applied. **The late-booking clock is LIVE** — `ops_flags.late_protocol_live_since = 2026-08-25T05:34:06.854Z`, i.e. it has been running ~2h20m as of this write. **Charging is still OFF** (`ops_flags.payments_live_since` null). ⚠ Note the column lives on `ops_flags`, NOT on `club_config` — v6 and several messages said `club_config` and the query errors there. | [verified-now] `db query --linked` against `supabase_migrations.schema_migrations` and `ops_flags`, this hour |
| Edge functions | create-booking-hold **v12** (redeployed with 0127; deployed source downloaded and grepped — no 맹견 token survives) · transition-booking **v35** · settle-run **v16** · collect-charges v3 · confirm-payment v2 · geocode-address v2 · delete-account v1 · open-drop v8. settle-run moved to v16 after the morning parity sweep — somebody redeployed it since; not mine. | [verified-now] `functions list` |
| Trunk `redesign-v4` | ≥ `6b4be67`. Moves several times an hour today — fetch, never quote a SHA from a doc. | [verified-now] |
| **Club spec v2** | Landed, **and now being RE-SCOPED against Sean's sixth-round rulings** (below). Two of its positions are REVERSED, not refined: §4.2's host-admission survival, and §6.6's recovery pen. **Do not build S2-S5 client halves against the landed text** — the admission surfaces are exactly what moves. | [verified-now] |
| **Sixth-round rulings** | On trunk at `6b4be67`, `docs/decisions/2026-08-25-console-rulings.md`. Five machine rulings Sean issued inside a design-lab critique: pack model · **no host approval of signups** · **no host pair-reallocation** (supersedes his own 14:26 tap for the 2-hour backstop — later word governs) · board ① · Instagram-style profiles as a NEW lane. | [verified-now] |
| **맹견 removal (0127 + suite 161)** | **DONE — landed `4632e3d`, deployed, verified live.** Query readback: 0 dangerous triggers · 0 gate functions · 3 `dogs` columns KEPT (Slice A boundary held) · `generate_recurring_bookings` acl = `postgres=X service_role=X` (**no PUBLIC** — the review's Critical closed in the live grant, not just pinned). Harness **886/0** re-measured on the merged tree. Two blind reviews; codex found the Critical (a `create or replace` relying on grant preservation → PUBLIC-executable definer on a partial apply). **Slice B — dropping the three columns — is NOT scheduled by calendar but by a MEASURED bundle-distribution check** (contract §0). | [verified-now] live query + `functions list` |
| **Runner-money strip** | 0121 landed and deployed. | [verified-now] via schema_migrations |
| **R17 remainder** | Closed: 0126, the flip-activation package, is deployed and the clock it was built for is live. | [verified-now] |
| 0120 location law | Parked at `b06f878`, unchanged. | [from-history] |
| Console | <https://claude.ai/code/artifact/aad92054-9264-4431-9835-d03ef86b3f6b> — holds all 24 answered rulings. ⚠ **Re-fetch its STATE before republishing**; seeding from a remembered copy would wipe his answers, which nearly happened twice today. | [verified-now] |

## 1-bis. WHAT IS OPEN, AND WHOSE IT IS (2026-08-26)

**SEAN — one yes/no that unblocks a whole slice:**
> **Has any build of the app reached a device other than your own dev phone?**
Measured: `eas build:list` = `[]` (zero builds ever), only `testflight` of four channels exists,
zero OTA updates. **If no → 맹견 Slice B drops the three `dogs` columns with no compatibility
window at all.** The slice is being authored complete now and will sit committed-unpushed until
he answers. EAS cannot see locally-built binaries or App Store Connect.

**SEAN — 12 questions across three contracts now on trunk** (each phrased for a one-sentence
answer; full text in the contracts):
- `club-host-session-authority-contract.md` — can a host remove a DOG or only a PERSON · mark
  ABSENT or only PRESENT · **is a removed person told, and in what words** (harassment surface) ·
  do both powers extend to the backup host.
- `club-pack-run-end-contract.md` — does the server finish each runner's record from their trace
  or **wait for their phone** (recommended: wait — deriving server-side means one tap writes N
  ledger rows and charges N cards) · may the backup host press 러닝 종료 · does a club run's
  duration measure to the host's tap or the runner's settle · where a blocked pair appears.
- `phone-collection-contract.md` — verified or self-declared number · **host sees EVERY member's
  number, confirm or narrow** · retention · editable-but-not-clearable.

**COUNSEL — two items for the email he already routed the privacy text to:**
1. **The published policy contradicts the shipped code in three places** — it calls the phone
   「선택」 (he ruled REQUIRED), scopes disclosure to open incidents only (the club rule opens on
   any live session or unresolved custody), and says a number is **never** given to a non-party
   (the rule's widest arm is host ↔ every member, and the host is not a party).
2. **A live third-party disclosure that predates all of it:** `delegation_consents.emergency_contact`
   is required at delegation, shown to the runner, kept forever unredacted as consent evidence,
   and has **no retention row in the policy**. Measured: 4 rows in production, all 4 carrying one.

**ENGINEERING — claimed follow-up, not yet sliced:**
🔴 **The harness UNDER-MODELS production's default function ACL.** `00_shim.sql:73` grants default
EXECUTE to `service_role` only; production's `pg_default_acl` is
`postgres=X anon=X authenticated=X service_role=X`. **Every ACL green in this repo proves
「correct under a kinder shim」, not 「correct in production」.** Aligning it changes what every
definer suite measures → its own slice, its own review.

## 1-ter. Laws added today — all on trunk, all measured

- **`git commit -- <paths>`, never `git add` + `git commit`, while any agent can write your tree.**
  Two agents share ONE index. For a NEW file: `git add` first, then STILL put the pathspec on the
  commit. The pathspec form takes WORKING-TREE content, so it must not land a `git add -p` partial.
- **The same hazard is in the working tree**: never write to a file an agent owns, even
  transiently. A copy-modify-restore is a read-modify-write with a multi-second window.
- **A `create or replace` relying on grant preservation is a latent PUBLIC-EXECUTE hole.**
  Write the revoke explicitly. Guard is schema-wide (`98 H9` runtime + `check-definer-acl.mjs`
  source gate, now a commit-gate member); **neither is evidence for the other.**
- **A push succeeding is a claim; `git show origin/<branch>:<path>` is the fact.**
- **A green light is evidence for exactly one sentence** — and the three-proposition mutation
  rule (the hole is real / the pin notices / the fix closes it). This shape hit FIVE times today.

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

---

## ADDENDUM — ui6 close-of-day, 2026-08-25 evening (supersedes the status table's stale rows; verify against live before building)

**Production head is `0123`** [verified-now: `db push` output + ledger re-query + five live probes]. Deployed today after the morning's 0117-0119: **0122** (pickup 동) · **0124** (cancel-ladder repricing, v5) · **0125** (route-km corrections — Sean's 4th-round Q3 confirmed as-built) · **0126** (flip-activation; **the late-booking clock is ON** — Sean's 4th-round Q1, ceremony run by v5) · **0123** (runner base + distance bands, ruling B, **7-day base-change cooldown** — Sean's 3rd-round T1 verbatim; landing record in the REGISTRY row). Charging remains OFF.

**Runner-money strip: LANDED + DEPLOYED** (v5, midday) — the v6 table's "NOT landed" row is stale. Its consequence is structural now: `runners`' read grant is 0121 §O's **literal 11 columns** and 158 N7ⓗ pins that literal (a computed all-minus-N expectation was measured to CERTIFY a revert rather than catch it — my pre-strip §2 nearly re-exposed commission_rate; 156 P6 caught it).

**Client, trunk `c67eedb`** [verified-now]: the ③+③-A check-in surface (owner/schedule + runner/home, 246 pins) — live now that the clock is on · meetup terminal-alert loop fixed (once-latch + goBackOrHome; Sean's live repro) · console #18 visual half (coral #A63A20, profile nudge ①, 하이 피드 rename, schedule band ceiling, no booking-list window) · 0123's settings/base-pin (sim-verified render-only; the 7-day lock means a casual confirm-tap costs a fixture account a week — smoke on hardware instead: set base → bands on request cards → retry → dated lock line).

**Suite-truth notes for whoever builds next:** 152's first armed sweep now DRAINS (L9 was a coin flip under 0126's LIMIT-5 vs the cross-suite backlog — a green landing run is not proof against this class; pin sweep effects with drain-to-zero). `app/node_modules` was briefly TRACKED on trunk (absolute-path symlink, a8d683b) — untracked at 851ff77, gitignore hardened at 41b676b; re-pull if your tree predates it. A scripted mutation battery must run against STAGED fixes (memory: daengrun-mutation-battery-staging).

**Console: CLEAR** except Sean's lab picks [verified-now: 4th round on origin — Q1 flip ordered+done · Q2 revoke-edge free-as-built · Q3 route-km as-built]. 맹견 removal: spec session owns the slice (contract on trunk, ≥0127); ui6's client surfaces ride that landing.
