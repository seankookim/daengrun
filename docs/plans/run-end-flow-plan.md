# Run-end flow — stop confirm · 귀가 custody · return handoff

Provenance: `TODOS.md:72-83` (Sean, 2026-08-12). **P1**: its own note says "P1 with real
charges", and the charge machine landed 2026-08-13 (`0080`). Doctrine already written —
`0078_route_catalog.sql:6-7`: *접근(커스터디, 무과금) → 루프(THE run, 과금 구간) → 귀가
(커스터디, 동결)*.

**Status: v5, 2026-08-13. §9 ruled by Sean; money-anchor corrections absorbed from the
payments session. Migration = 0083 / suite 119, claimed in `REGISTRY.md` on origin.** Two adversarial reviews ran against
v1/v2 (a product/state-machine reviewer: 19 findings; codex on the money path: **"reject
the plan as written"**). Both are absorbed here. v3 exists to meet codex's seven-item
minimum bar (§10) — Sean reads §0-bis first and decides.

Migration slot **0082** (0081 claimed by the club-gaps session — ledger memory).

---

## §0-bis What the reviews changed — read this first

Three of my own claims were **false**, and all three were about money:

1. **"Ceasing trace writes freezes the charge."** No: `actual_km` comes from the in-memory
   `gpsKm` (`run.tsx:193`, fed by `onTrack`), never from the trace. The doorstep settle
   would have billed the walk home. Both reviewers found this independently.
2. **"`settle_run_tx` needs no change."** codex: *"the most dangerous sentence in the
   plan."* `settle-run` claims any `active` booking and checks neither `run_ended_at` nor
   any stamp — so an old client, the `reachedTarget` effect, or a direct API call settles
   mid-귀가 and pays out while the dog is still on the leash. **This bypass exists today.**
3. **"`active` has no blast radius."** I verified only crons. The radius is in the UI and
   matching: `STATUS_MAP` (`api.ts:539`), owner home's ● LIVE (`owner/home.tsx:493`),
   owner schedule's "GPS 실시간" (`owner/schedule.tsx:435`), runner calendar/home routing
   every `active` booking into the run screen (`runner/calendar.tsx:56`,
   `runner/home.tsx:289`).

Plus a genuinely new class I had not considered: **`runs.ended_at` currently means
*settlement* time.** Delay settlement to the doorstep and a run that stopped at 09:58 —
before a 10:00 `payments_live_since` cutover — is charged because it settled at 10:08.
That breaks 0080's "no retroactive charging" law from the other direction.

**Consequence: 귀가 must be a server invariant, not a screen behaviour.** codex's closing
sentence is the design brief: *"this design converts '귀가 is unbilled' from a server
invariant into a promise that one version of one screen will behave correctly."*

## §1 The money boundary — server-owned freeze

**`end_run_tx` (one transaction) closes the run and freezes every settlement input:**
`actual_km`, `duration_sec`, `end_reason`, `condition_note`, and **`runs.ended_at = the
service-stop moment`**. Final trace save commits inside it; the run-mutation window then
closes.

- Frozen columns join `_guard_run_cols`'s protected list (`0079:53-81`) — but note that
  guard only bites after `completed`/`incident_review`, so it is **extended to bite
  whenever `run_ended_at is not null`** (codex #7).
- **The atomic append functions get the same phase gate.** `append_run_event` /
  `append_run_photo` (`0018`) check only `b.runner_id = auth.uid()` — verified. A runner
  can therefore stamp a 응가 event *after* stopping, which `settle_run_tx` rewards with
  miles (`0028:88`). Both functions must reject `run_ended_at is not null`.
- **`settle-run` ignores every client-supplied financial input** and reads the frozen row.
- **`end_run_tx` validates `end_reason` against the exact four-value client-sendable set:**
  `completed · dog_condition · owner_request · runner_personal`. Both `incident` and
  `owner_forced` are refused (the first is ops/G1 territory — a runner declaring it hands
  their owner a free run; the second is ops-written, not a runner's).
  🔴 **Deadlock rule:** the freeze set must be a SUBSET of what `settle-run` accepts.
  Freezing a value settle-run refuses produces a run that can never settle — runner never
  paid, booking never leaves `active`. Reject by name; never silently coalesce to
  `completed`.
- *(superseded framing kept for provenance)* validates against the narrowed set:
  `settle-run` now returns a named 400 for `incident` / `owner_forced` (a runner must not
  self-declare `incident`, which under G1 means the owner is charged nothing). Because this
  slice freezes `end_reason` EARLIER than that gate, the same whitelist must apply at the
  freeze — otherwise a runner freezes `incident` at run-stop and hands their owner a free
  run. Do not re-widen it.
- ⚠ **Never hardcode a G1 amount — it has now been answered THREE different ways in one
  day.** ₩0 both arms (what was shipped) → base-flat 7,900 (an intermediate ruling) →
  ✅ **FULLY RULED `912c6b2` — fault-based, BOTH ledgers mirrored.** Sean reframed it off
  "what does an abort charge" onto **who is at fault decides who absorbs the shortfall**,
  which is a better frame than either memo proposed:

  | end_reason | RUNNER paid | OWNER charged |
  |---|---|---|
  | `dog_condition` | 9,900 + 3,000 × distance actually run | 7,900 + 3,000 × same (mirrored) |
  | `owner_request` / `owner_forced` | 9,900 + 3,000 × run | PLANNED (D2, anti-cut-short) |
  | `runner_personal` | **9,900 base ONLY, no distance** | distance only, base waived |
  | `incident` | normal settle | ₩0, verify first |

  🔴 **This governs the RUNNER's basis too, which invalidated an assumption in this slice:**
  `end_run_tx` froze a computed payout quote built from today's single formula. Under the
  fault rule `runner_personal` has **no distance component**, so a frozen quote carrying
  `distance_pay > 0` would pay a runner for distance the ruling says they don't get — money
  moving on a stale formula that we froze. **Resolution: freeze the MEASUREMENT, not the
  money** (`actual_km`, `duration_sec`, `end_reason`, `condition_note`, `ended_at`). That is
  the entire boundary §1 defends — no metre walked after the stop reaches the money —
  and freezing a formula's *output* defends nothing extra while rotting the moment pricing
  moves. It moved four times today.

  *(superseded: earlier this slice recorded CONFLICTED as of `a186eb6`)* Sean answered TWICE,
  differently, in two sessions: base-flat 7,900 in the payments session (on an unpushed
  branch, so invisible), then full actuals via `ac0c294` in the club session — from an
  AskUserQuestion menu that could not contain the first answer *because it was unpushed*.
  That is the unpushed-decision defect biting a second time, now costing a ruling rather
  than a migration number. It is back with Sean. **The shipped code still waives both
  arms.** `club_fare = A` (9,900
  kept as a stated premium). Every G1 value in this slice reads through
  `compute_owner_charge` — which is precisely why the third ruling cost this slice nothing.
  Exact shape under C: `base_fare + round(distance_fare/km × basis) + addon_fare`, ceilinged
  at `min(actual, planned)` — identical arithmetic to a `completed` run. `incident` remains a
  waived row at settle (0072's adjudication owns that money question).
  **Provenance norm, learned twice today: a relayed decision is evidence, not authority.**
  Both sessions relayed Sean's words in good faith and disagreed; the answer only settled
  when it was read from origin (`ac0c294`). Do not encode a money rule from a relay —
  including a confident one — without reading it at origin yourself.
- Custody GPS rides an explicitly **non-billable path**: broadcast for the map, plus a
  `custody_last_seen_at` heartbeat (§4d). It is structurally unable to touch the run row.

## §2 `settle-run` becomes gated — the bypass closes

Today: `settle-run` accepts any assigned runner and `settle_run_tx` claims any `active`
booking (`handler.ts:39`, `0028:53`). New precondition, enforced **server-side on a locked
row**:

```
settle is permitted iff  run_ended_at is not null
                    AND  (both return stamps present  OR  a recorded force resolution)
```

- Client km/duration/reason are ignored (§1).
- **Old-client rollout is part of this slice, not an afterthought** (codex #1): deployed
  clients call the ungated endpoint today. The gate must ship with a behaviour for them —
  reject with a message that reads as "앱을 업데이트해 주세요", never a silent no-op, and
  never a settle.

## §3 Settlement timing and its anchors

Sequence: stop → `end_run_tx` → 귀가 → both stamps → **settlement inside that same locked
transaction** → ceremony.

**Timestamp semantics (codex #3) — the fix for the cutover bug:**

| fact | meaning | written by |
|---|---|---|
| `runs.ended_at` | **service stop**, always | `end_run_tx` |
| `runs.settled_at` (new) | when money moved | settlement |

0080's cutover eligibility reads **`ended_at` (stop)**, so a pre-cutover run stays free
forever regardless of when its return is confirmed. And `sweep_settled_without_payments`
must require a **settlement anchor**, not merely "a run row with an ended_at and no
payment" — otherwise it mints a charge for a run that has stopped but not yet been
returned (codex #3 scenario B).

⚠ **CORRECTED 2026-08-13 by the payments session (who owns that sweep).** v3 said to anchor
on `status='completed'` + the ledger row. **Both halves are wrong:**
- **Never anchor settlement on `bookings.status`** — §0-ter #11 (`0080:487`, pinned by
  `116` C8). An `incident_review` / `refund_pending` transition drops a settled booking out
  of the sweep's and the lock's view, and a settled booking missing its payments row is
  precisely the crash the sweep exists to catch. A status anchor makes it invisible.
- **`ledger_items` presence is not a substitute** — `record_enroute_cancel_comp` (0081)
  writes a ledger row for a *cancelled* booking, so ledger-presence would make the sweep
  try to mint a settle charge for a cancellation.

**The anchor is `runs.settled_at`** (this slice adds it): status-independent, excludes
cancels, and means exactly "settlement wrote money for this run".
- sweep anchor → `runs.settled_at is not null` ("did money happen?")
- cutover eligibility → `runs.ended_at` ("when did the service happen?")
- debt-derivation scope → `settled_at` OR `ledger_items` OR `cancel_fee > 0` — never status.

Two consequences this slice owns:
- `end_run_tx` must guarantee `ended_at` is written at stop and make it structurally
  impossible for settlement to run without it — 0080's mint reads
  `coalesce(r.ended_at, now())`, which would otherwise silently reclassify a pre-cutover
  run as post-cutover.
- `116_charge_suite.sql`'s `t_chg_settled` helper writes `runs` rows directly, so any NOT
  NULL / CHECK on `settled_at` reddens 116 as well as 119. Updating that fixture is part of
  THIS slice.

**Atomicity (codex #4).** "Both stamped → settle-eligible" is not an implementation. If
the second stamp commits and the process dies, nothing repairs `active + both stamps + no
ledger`. Therefore: **the second stamp performs settlement in the same locked server
transaction**, and a durable recovery sweep re-drives any row left `settlement_ready` —
one idempotent settlement primitive, called from exactly one place. Settlement is **never**
implemented separately in `confirm_return`, `force_return`, and the runner screen. A
concurrent loser returns idempotent success after verifying the same frozen outcome, not a
raw `not_active`.

## §4 Operational phase — the `active` audit

One server-derived phase, then every consumer classified (codex #5):

```
active AND run_ended_at IS NULL      → running
active AND run_ended_at IS NOT NULL  → homeward
```

| consumer | class | behaviour during 귀가 |
|---|---|---|
| `available_runners` (`0015:29`) | custody-inclusive | stays excluded — correct as-is |
| pickup-address access (`0065:49`) | custody-inclusive | stays granted — needed to return the dog |
| `STATUS_MAP`, owner home ● LIVE, owner schedule "GPS 실시간" | running-only | must say 귀가, not 러닝 중 |
| runner calendar/home routing (`:56`, `:289`) | running-only | routes into 귀가 mode, not the run screen |
| LA trace trigger + stale sweep (`0079:270,317`) | running-only | guarded (§4d) |
| runner-accept conflict guard (`index.ts:58`), nominated availability (`0054:106`), booking-hold (`handler.ts:71`), recurring gen (`0080:720`) | **scheduled-capacity — the exploitable gap** | see below |

**The capacity gap**: those four use the *nominal scheduled window* (`km*8+25min`), not
actual custody. A 귀가 running past the estimate lets a runner accept a new targeted
booking while still holding the first dog. Fix: an unconditional **"current custody blocks
acceptance"** check, separate from scheduled-overlap math.

## §5 Custody heartbeat — the honesty counterpart to the sweep guard

Guarding `owner_la_sweep_stale` on `run_ended_at is null` (§4d) stops the false "위치가
갱신되지 않았어요" during every 귀가 — but it also means **nothing** can report a genuinely
dead 귀가: broadcast is ephemeral and invisible to Postgres, so a runner whose phone dies
leaves the lock screen reading 집으로 가는 중 forever (codex #9).

So: a non-billable `custody_last_seen_at` heartbeat, written on the custody path. Homeward
LA freshness reads **that**, never `runs.trace`. Pins: old trace + fresh heartbeat →
homeward; stale heartbeat → homeward/no-signal.

## §6 Surfaces

**Runner** — stop dialog (quotes the km it is freezing, names under-minimum consequences);
귀가 mode (frozen stats, 인계 확인 CTA, no pace chip); **re-entry restores directly into
귀가 mode** — never `start_run`, never trace persistence, never target auto-settle (codex
#8, review #3); custody tracking ends at the runner's own stamp; runner LA re-titled 귀가
중 · 인계 확인하기 with a deep link (it has no phase field and is ended only from `settle`).

**Owner** — live screen keeps the owner *on it* (`live.tsx:141-154` gains the earlier
branch); pill 집으로 가는 중; frozen stats labelled as frozen; 남은 거리 to the pickup pin
(**no ETA in minutes** — no walking-speed model, and a fabricated 도보 8분 was already
retired at `runner/meetup.tsx:306`); anomaly strip at ~stop+25min routing to chat.

**Notifications** — distinct return titles + a `RETURN_TITLES` set routed to `/owner/live`
and `/runner/run`. Today a new title falls through `push.ts:59-62` to `/owner/report` (a
screen gated on `endReason==='completed'`), and any runner title containing '요청' lands on
`/runner/requests` (`:41`) — verified.

**Ceremony (§4e of v2, retained)** — the pickup stub **rejoins**: one whole stub,
perforation sealed, gold rule 귀가 완료, carrying the runner's last snap, frozen 거리·시간,
the earned event stamps, and a **한 줄 인계 메모** written at the door. Today the emotional
peak of *dog-is-home* lands on the runner's payout receipt and the owner gets a report
screen; that is backwards. Reuse `useStamp` + the `hydrated` gate.

**Recipient (§4f of v2, retained)** — owner pre-declares "다른 분이 받아요 · 이름/관계";
return becomes runner-stamp + owner-acknowledge with the recipient recorded. Clubs already
model this (`session_custody_transfer`, `0045:170-245`).

## §7 Races and edges that must be pinned, not discovered

- **Incident vs return precedence** (codex #6): both lock the same booking; declared order.
  Incident before the seal → one specified review/payment path. Incident after settlement →
  an adjustment/refund path, not pretending settlement never happened.
- **Owner cancel during 귀가**: `active → cancelled_owner` is not in the map, so today it
  rolls back to a 409 after quoting a fee — financially safe, badly expressed. Fix with an
  explicit early rejection routed to return-dispute/SOS. **Do not add the edge.**
- **Force-return** (codex #10): server time on a locked fresh row; evidence = pickup-radius
  proof from the custody channel, owner interaction, or an ops override; records actor,
  eligibility time, reason, evidence; **a durable server process, never an app-local
  timer** (a runner who never reopens the app must still get paid).
- **Marketplace-only scoping**: `end_run` and the return actions must reject
  `club_session_id is not null`. "Clubs are out of scope" is not a server guard.
- **Schema completeness**: `return_forced_by` was referenced but never declared (codex).
  Also the new stamps need **INSERT-side** protection — `_guard_booking_cols` is an update
  trigger while owners may insert drafts (`0002_rls.sql:91`).

## §8 Slices

1. **Condition note** (§8-bis) — independent of everything above. **Built.**
1b. **OTA refresh capability** (D-r4 part 2) — `expo-updates` + EAS Update +
   `runtimeVersion`. Needs `expo prebuild --clean` + a new build (Sean's gate). Ships
   BEFORE the settle gate is enforced against real users; valuable far beyond this feature
   (today any shipped JS bug needs an App Store round trip).
2. **Server**: `0082` + `end_run_tx` + gated `settle-run` + phase gates on trace/appends +
   heartbeat + timestamp semantics + `117_run_end_suite`. Nothing client-side is
   trustworthy until this lands.
3. **Runner** screens · 4. **Owner** screens · 5. **Ceremony + recipient**.

### §8-bis The fabricated condition note (built this session)

`run.tsx:444` sent a hardcoded `'러너 판단: 컨디션 저하 관찰'` because the server requires a
note (`handler.ts:53-54`); `:478` told the runner to leave one with no field to write it;
`owner/report.tsx:384` showed the constant to the owner as the runner's account of their
dog. Fabricated data as observation, a promise with no affordance — and a money control on
a constant, since **G1's adopted anti-gaming mitigation is exactly "the owner knows whether
their dog was actually unwell."**

## §9 Decisions — RULED BY SEAN 2026-08-13

- **D-r1 — DECIDED. The owner's interaction on the intermediary screen IS the evidence,
  and the runner is paid once the dog is returned.** Settlement's trigger is therefore the
  owner's confirmation on the meetup/live intermediary surface, not a timer and not a
  proximity computation. Payment follows the return, in that order.
  - *Residual (my proposal, not Sean's ruling — flag at build):* the release valves D-r2
    keeps still need parameters for the case where the owner never interacts at all.
    Proposed: runner force allowed 20min after the peer was notified, gated on the runner
    being at the pickup pin (evidence, since the owner's interaction is absent), driven by
    a **durable server sweep** — never an app-local timer, so a runner who pockets the
    phone is still paid. Owner-side force symmetric. Sean confirms or amends at build.
- **D-r2 — DECIDED: follow the recommendation.** Owner stamp required; the recipient
  declaration (§6, "다른 분이 받아요") is what keeps a remotely-tapped stamp honest; the
  forces stay as release valves.
- **D-r3 — DECIDED: optional but prompted.** Required text at the door invites typing
  anything to escape the screen — precisely how the condition note became a constant.
- **D-r4 — DECIDED: build the refresh capability.** Sean: *"we need a refresh feature
  right? if that's the case add that."* Correct, and the audit confirms the gap is total:
  **`expo-updates` is not installed, there is no EAS Update config, no `runtimeVersion`
  policy, and no update-check code anywhere in the client.** Today a shipped JS bug can
  only be fixed by an App Store round trip. Two parts, deliberately sequenced:
  1. **In this slice (immediate, no rebuild):** the settle gate rejects an unreturned
     settlement with a *distinct* error the client renders as "앱 업데이트가 필요해요",
     never a generic failure and never a silent no-op.
  2. **Its own slice (needs a native rebuild — Sean's gate):** install `expo-updates` +
     EAS Update with a `runtimeVersion` policy, so future JS-only fixes reach installed
     apps without a store release. ⚠ It does **not** retroactively help builds already on
     phones — those lack the updates runtime — so it must ship BEFORE the settle gate is
     enforced against a real user population. Today that population is ~Sean's devices
     (`push_tokens` had 1 row), which is exactly why this is cheap to do now and expensive
     to retrofit after TestFlight.

## §10 codex's minimum bar — status

| # | requirement | v3 |
|---|---|---|
| 1 | `end_run_tx` atomically closes trace + freezes all settlement inputs | §1 |
| 2 | homeward tracking on an explicitly non-billable path | §1, §5 |
| 3 | `settle-run` rejects unreturned bookings, ignores client financial inputs | §2 |
| 4 | return sealing + settlement atomic or durably recovered | §3 |
| 5 | 0080 sweep needs a settlement anchor; cutover uses run-stop time | §3 |
| 6 | incident/force/cancel/restart/old-client races pinned | §7, §2 |
| 7 | every `active` consumer classified | §4 |

All seven are now **specified**. None are **built**. The next action is Sean's call on §9,
then slice 2 — which is a money migration and gets its own adversarial round after build,
per the repo's money doctrine.
