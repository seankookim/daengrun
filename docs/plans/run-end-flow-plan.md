# Run-end flow — stop confirm · 귀가 custody · return handoff

Provenance: `TODOS.md:72-83` (Sean, 2026-08-12 evening). **Now P1**: its own note says
"P1 with real charges — the charge boundary depends on it", and the charge machine landed
2026-08-13 (`0080_charge_machine.sql`). The doctrine text already exists —
`0078_route_catalog.sql:6-7`: *접근(커스터디, 무과금) → 루프(THE run, 과금 구간) → 귀가
(커스터디, 동결)*. This plan builds the third segment.

Status: **v2, 2026-08-13** — rewritten after an adversarial product/state-machine review
(19 findings, all absorbed or explicitly deferred below). v1's central money claim was
WRONG and is corrected in §1; the architecture survived, the specificity did not.
Migration number **0082** (0081 claimed by the club-delegation session — ledger memory).

---

## §0 The one sentence

**Run-end ≠ dog-home.** The money meter cuts when the runner stops running; the dog stays
in the runner's custody until it is handed back. Today those are the same event, which is
why the app has no honest way to say "집으로 가는 중".

Closes a live honesty bug: `owner/live.tsx:209` and `:498` already promise the runner will
"픽업 장소로 복귀" — copy with no state, no screen, no confirmation behind it.

## §1 The money boundary — CORRECTED (v1 was wrong)

**v1 claimed** that ceasing `saveRunTrace` at run-stop made the boundary airtight "by
construction". **That was false.** `actual_km` never came from the trace: `settle()` sends
`actual_km: Number(km.toFixed(2))` (`run.tsx:442`) where `km` is `gpsKm` (`:193`), an
in-memory counter fed by the tracking sink `onTrack` (`:250-269`). v1 deliberately keeps
tracking alive for custody — so `gpsKm` would have grown all the way home and the doorstep
settle would have billed the walk. I protected the wrong object.

**The corrected law: the money numbers are FROZEN SERVER-SIDE at `end_run`, and settle
after 귀가 never trusts a client distance.**

- `end_run` (server) writes the tuple onto the run row in one statement:
  `actual_km`, `duration_sec`, `end_reason`, `condition_note`.
- Those columns join `_guard_run_cols`'s protected list (`0079:53-81`) so no client can
  rewrite them afterwards — the freeze is enforced, not promised.
- `settle-run` after a 귀가 **ignores any client-supplied `actual_km`** and reads the
  frozen row. Pinned (§6 R-money).
- Benefit beyond correctness: the end reason and condition note survive an app kill, which
  in v1 lived only in a JS closure and the in-memory `runResult` store.

Custody GPS keeps flowing to the realtime channel for the owner's map. It now reaches
nothing billable *because the billable numbers are already written and sealed*, not
because a write path is absent.

## §2 State representation — timestamp, not a new enum value

**`bookings.run_ended_at`, `runner_confirmed_return_at`, `owner_confirmed_return_at`.
Status stays `active` throughout 귀가.**

Rejected: a `returning` enum value — every `status='active'` check would have to learn it
(settle claim `0028:60-65`, `FLIGHT_RANK`, `available_runners`, LA triggers, matching
guards), and Postgres cannot add and use an enum value in one transaction. Precedent:
`arrived_at` is documented at `transition-booking/index.ts:242-244` as *a stage that is a
timestamp, not a status*. Verified safe: no cron sweeps `active` bookings (only the settle
functions write `active → completed`; `expire_unmatched_bookings` covers matching/
runner_pending only).

All three columns are server-stamped only, protected exactly as the pickup stamps are
(`0057_security_hardening.sql:399-401`). A client that can stamp its own return can end
custody unilaterally.

**Client read contract** (review #13): `fetchBookingSync` (`api.ts:820-833`, 4 columns
today) carries all three; both live screens and both meetup-family screens read them.

## §3 Settlement fires at RETURN, not at stop

Sequence: stop → `end_run` (meter cuts, numbers frozen) → 귀가 → both sides stamp → settle
from the frozen row → the return ceremony (§4e).

Why not at stop: `completed` deletes the owner's LA push token (`0079:380-395`), freezes
`runs` (`0079:60-64`), and navigates the owner to `/owner/report` (`live.tsx:151`). 귀가
after completion would fight all three. The service is not complete when the running
stops; it is complete when the dog is back.

### 3a. Every path into 귀가 (review #2a — v1 left the main one unreachable)

`run.tsx:493-501`'s auto-complete effect calls `settle(null, true)` on `reachedTarget`.
Left alone, **the most common run in the product would skip 귀가 entirely.** It must call
`endRun()` instead, hard-guarded `if (runEndedAt) return;` — otherwise custody metres push
`gpsKm` past target on the walk home and re-fire the effect into a mid-귀가 settle
(`settled.current` does not protect: it is only set inside `settle`).

### 3b. Flags (review #2b, #14)

`running` goes **false** at `end_run`; a separate `custody` flag owns tracking. The whole
screen keys off `running` today — timer `:326`, trace save `:370`, LA `:315`, pace `:545`,
event chips `:805` — so overloading it is what makes 귀가 either dead or leaky.

**Custody tracking ends at the runner's own return stamp**, not at settle: otherwise a
runner who stamps and waits 20 minutes keeps background GPS alive and the owner watches a
dot inside the runner's home. At that moment the owner's map switches to an explicitly
labelled last-known position.

### 3c. Unfinishable 귀가 — both directions (review #6)

v1 covered only the owner-silent direction. A runner whose battery dies strands the
booking `active` **forever**: the LA token is never deleted, `owner/live.tsx` polls
forever, and `runner_accept`'s conflict guard (`index.ts:61-92`) treats `active` as LIVE,
so the stranded row blocks the runner's future overlapping accepts.

- **Runner force** (owner silent): allowed 20min after `greatest(runner_stamp,
  notified_at)`, gated on proximity to the pickup pin (coords exist — 0065
  `fetchOwnerPickupCoords`), recording `return_forced_by` **and position-at-force**.
  Review #5: without the proximity gate the runner just stamps at run-stop, walks 20
  minutes, and forces on arrival — the exact thing §3 said must not be possible.
- **Owner force** (runner silent, dog demonstrably home): symmetric.
- **Janitor**: `run_ended_at` + no return after ~2h → `incident_review` (already legal,
  `0047:40`) — which ends the LA honestly through 0079's `'ended'` branch.

## §4 Surfaces

### 4a. Runner — stop confirmation

Inserted before the `handle.stop()`/`stopPublishing()` cluster (`run.tsx:409-411`), which
no longer runs at stop. Under-minimum ends (`km < plannedKm*0.5`, `handler.ts:72`) name
the consequence. **The dialog quotes the km it is freezing, and §4b's frozen readout shows
the identical number** (review #16).

### 4a-bis. 🔴 The condition note is FABRICATED today — SLICE 1, in progress

`run.tsx:444` sends a hardcoded `'러너 판단: 컨디션 저하 관찰'` because the server requires
a note (`handler.ts:53-54`); `:478` tells the runner to leave one with no field to write
it; `owner/report.tsx:384` shows the constant to the owner as the runner's account of
their dog. Fabricated data as observation, a promise with no affordance — and now a money
control on a constant: **G1's adopted anti-gaming mitigation is exactly "the owner knows
whether their dog was actually unwell."** Fixed by collecting a real required note in the
stop dialog and deleting the canned fallback.

### 4b. Runner — 귀가 mode

Same screen, third visual state. Stats frozen at the server-written values and labelled as
frozen. Primary CTA becomes 인계 확인. Pace chip and 권장 caption disappear (custody is not
a run — the pace-state plan's §6 already recorded this composition point).

**Re-entry (review #3 — the actual money leak in v1).** After an app kill the mount effect
(`:218-247`) resets, `running` initialises false, and the booking is still `active`, so
`fetchCurrentRunnerJobId` (`api.ts:896-902`) resolves it and shows **러닝 시작** — tapping
it resumes the 60s `saveTrace` interval and writes custody metres into `runs.trace`, which
`_guard_run_cols` permits because status never left `active`. So: mount reads
`run_ended_at` and enters 귀가 mode directly (러닝 시작 replaced by 인계 확인), `saveTrace`
gated on `!runEndedAt`, stats hydrated from the frozen row, seals jumping to static values
on first sync via the documented once-law `hydrated` gate (`runner/meetup.tsx:204-238`).

### 4c. Owner — live screen 귀가 state

`live.tsx:141-154`'s single `completed` branch gains an earlier one: `run_ended_at` set and
not returned → **stay on the screen**. Pill 집으로 가는 중, dot still moving, stats frozen
and labelled, pace row gone, owner's stamp affordance.

**남은 거리** to the pickup pin on both sides (review #10) — the one number that turns a
40-minute wait into information. **No ETA in minutes**: there is no walking-speed model,
and this codebase already retired a fabricated 도보 8분 (`runner/meetup.tsx:306`). A
homeward-specific loud strip at ~`run_ended_at`+25min routes to chat, in the existing strip
grammar.

### 4d. Live Activities — both sides

Owner LA gains `'homeward'` (`OwnerRunActivity.tsx:21`): pill 귀가, frozen km, footer 집으로
가는 중, no pace pill.

⚠ Two server guards, not one (review #4 — and independently found by inspection):
- `_owner_la_trace_tg` hard-sets `phase='running'` on every trace write (`0079:297`) →
  guard on `run_ended_at is null`.
- **`owner_la_sweep_stale` (`0079:322-357`) joins `status='active'` + `runs.trace` and
  pushes "N분째 위치가 갱신되지 않았어요" once the last trace point is ≥90s old** —
  guaranteed 90 seconds into every 귀가, precisely *because* the trace stopped. The owner's
  phone would say 집으로 가는 중 while their lock screen says the position is lost. Guard it
  the same way. Pinned R8-b.

**Runner LA (review #15)** — `RunActivity` has no phase field and is ended only from
`settle()` (`run.tsx:414`). The pocketed phone would keep showing a live run with no way to
stamp. Minimum: re-title at `end_run` (귀가 중 · 인계 확인하기) with a deep link; ideally the
stamp is the LA's own action.

### 4e. The return ceremony — the real peak (review #8)

Pickup is an artifact: NIGHT band, two `SealSlot`s, perforation, 확인 2/2, gold `SEALED`
ribbon, once-law hydration. v1 gave the return "the primary CTA becomes 인계 확인" — a
button. Today the emotional payload of *dog-is-home* lands on the runner's **payout
receipt** (`runner/done.tsx`) and the owner gets a report screen. That is backwards.

**The stub rejoins.** The pickup stub is a ticket torn along a perforation; the return
closes it — one whole stub, perforation sealed, gold rule reading **귀가 완료** rather than
SEALED. It carries what exists only at this moment: the runner's last snap, 오늘 함께한
거리·시간 (frozen), the earned event stamps (`evCounts` already counts 응가/간식/물/사진,
`run.tsx:103`), and **한 줄 인계 메모** the runner writes at the door ("물 많이 마셨고
발바닥 깨끗해요"). That memo is what an owner actually wants when the leash changes hands,
and no competitor's stop button produces it. The owner's stamp then isn't paperwork — it's
receiving the receipt. Reuse `useStamp` + the `hydrated` gate; no second animation grammar.

### 4f. Someone else receives the dog (review #9)

Modelling return as owner↔runner only forces a lie ("아빠가 받으실 거예요" → the owner
stamps a handoff they didn't perform from 40km away) or a force. Clubs already solved
this: `session_custody_transfer` / `session_custody_accept` with a `custodian_type` guard
and a custody event ledger (`0045:170-245`). Minimum here: the owner pre-declares
"다른 분이 받아요 · 이름/관계" from the live screen; the return becomes runner-stamp +
owner-acknowledge, with the recipient recorded. This also settles D-r2 honestly — a
remotely-tappable owner stamp is not proof of physical handoff.

### 4g. Notifications (review #7)

`push.ts:19` `LIVE_TITLES` is exact-match; a new 귀가/return title falls through to
`/owner/report` (`:61`) — a screen gated on `endReason === 'completed'` — when the whole
point is that the owner belongs on `/owner/live`. Copying the pickup nudge string
"인계 확인 요청" verbatim also routes the runner to `/runner/requests` (`:41`) and makes
pickup and return indistinguishable in the inbox. So: distinct return titles + a
`RETURN_TITLES` set routed to `/owner/live` and `/runner/run`.

## §5 Server — `0082_run_end_flow.sql` + `transition-booking`

- three columns + client-forgery protection (mirroring `0057:399-401`; confirm service-role
  writes still pass)
- freeze columns added to `_guard_run_cols`'s protected list
- `after update of run_ended_at` LA trigger → `'homeward'`; guard the 0079 trace trigger
  **and the stale sweep** on `run_ended_at is null`
- `settle_run_tx` itself unchanged — status never left `active` (a deliberate win of the
  timestamp design)
- **server gate (review #19): a booking may not reach `completed` from a 귀가 without both
  stamps or a recorded force.** A server rule, not a client sequence.

Actions, all with `arrived`-grade idempotence (review #11, #12) — `update ... where
<precondition> returning id`, 0 rows → `{unchanged:true}`:
- `end_run` — runner-only, `where run_ended_at is null and status='active'`, freezes the
  tuple, notifies owner.
- `confirm_return` — `meta.side` grammar from `confirm_handoff` (`index.ts:267-299`), but
  the settle-eligible branch is itself a **CAS**: `confirm_handoff`'s simultaneity safety
  is its *status* guard (`:288`), which a stampless design does not inherit — without the
  CAS both callers proceed and the loser gets a raw error plus doubled notifications.
- `force_return` — actor-scoped, window per §3c, records actor + position.

## §6 Harness pins — `117_run_end_suite.sql`

- **R-money (the one that matters)**: settle after a 귀가 ignores client-supplied
  `actual_km` and bills the frozen row. Custody distance never reaches
  `compute_owner_charge`'s basis (companion pin in `116_charge_suite`).
- R1 `end_run` freezes the tuple and does NOT change status · R2 no client can forge any
  stamp or overwrite a frozen number · R3 one-sided return notifies, does not settle ·
  R4 **completed is unreachable without both stamps or a recorded force** · R5 force
  refused before the window / by the wrong actor / away from the pin · R6 force records
  actor + position · R7 LA phase `homeward` · R8-a trace trigger silent during 귀가 ·
  **R8-b the stale sweep skips a 귀가 booking** · R9 double-fire idempotence on `end_run`
  and simultaneous `confirm_return`.
- `10_settle_suite`: settle after return is a normal `active → completed` claim.

## §7 NOT in scope

- Emergency-stop refund path (G1) — its own TODO, its own money cycle.
- 더 뛰어도 좋아요 fast-finish nudge — separate encourager; this slice builds the state it
  would ride on.
- Club sessions — they already have `session_confirm_return` (`0046`).
- Charging for custody time — never. 귀가 is custody, not service.
- Review #17's "nobody is at the door" exit: routes to the existing SOS/incident
  vocabulary (`live.tsx:385`, `active → incident_review`) rather than a new mechanism.

## §8 Slices

1. **Condition note** (§4a-bis) — independent, in progress.
2. **Server**: 0082 + three actions + pins. The money freeze is here; nothing client-side
   is trustworthy until it lands.
3. **Runner**: stop dialog, 귀가 mode, re-entry, flags, tracking-stop, LA re-title.
4. **Owner**: live 귀가 state, 남은 거리, anomaly strip, stamp, notification routing.
5. **Ceremony** (§4e) + recipient declaration (§4f).

## §9 Open for Sean

- **D-r1** force window 20min + proximity gate. Alt: no force (runner must reach the
  owner) — rejected, it lets an unresponsive owner withhold pay.
- **D-r2** owner stamp required? Rec: required, with §4f making it honest and §3c's forces
  as the release valves.
- **D-r3** the 한 줄 인계 메모 (§4e): required or optional? Rec: optional but prompted —
  required text at the door risks a runner typing anything to escape the screen, which is
  how the condition note became a constant in the first place.
