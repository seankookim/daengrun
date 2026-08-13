# Run-end flow — stop confirm · 귀가 custody · return handoff

Provenance: `TODOS.md:72-83` (Sean, 2026-08-12 evening). **Now P1**: its own note says
"P1 with real charges — the charge boundary depends on it", and the charge machine
landed 2026-08-13 (`0080_charge_machine.sql`, harness 430/0). The doctrine text already
exists — `0078_route_catalog.sql:6-7`: *접근(커스터디, 무과금) → 루프(THE run, 과금 구간)
→ 귀가(커스터디, 동결)*. This plan builds the third segment.

Status: DRAFT 2026-08-13, authored by Fable 5 under Sean's standing autonomy grant.
Review report at the end.

---

## §0 The one sentence

**Run-end ≠ dog-home.** The money meter cuts when the runner stops running; the dog is
still in the runner's custody until it is handed back. Today those two moments are the
same event, which is why the app has no honest way to say "집으로 가는 중".

**There is a live honesty bug this closes.** `owner/live.tsx:209` and `:498` already tell
the owner the runner will "픽업 장소로 복귀" — copy that promises a return leg with no
state, no screen, and no confirmation behind it (honesty law §7: bind real fields or omit).

## §1 The money boundary (the reason this is P1)

`compute_owner_charge` bills `least(greatest(actual,0), planned)` (`0080:274`) from the
frozen booking numbers, and the runner is paid on `actual_km` (`settle-run/handler.ts:76`).
`actual_km` arrives from ONE place: `run.tsx:442`'s `settleRun({actual_km: km})`.

**The law: no metre walked after the stop may reach that argument.** The build achieves
this *by construction*, not by arithmetic:

- At run-stop the client **stops persisting the trace** (`saveRunTrace` ceases) and stops
  advancing the displayed km/time. `runs.trace` therefore remains exactly the run segment.
- Custody GPS keeps flowing to the **realtime channel only** (`publishPos` → `run-{bid}`),
  which is what the owner's map already consumes. It is broadcast, never persisted.
- So the billable record cannot grow during 귀가 — there is no code path that writes it.

This is deliberately stronger than "subtract the homeward distance at settle": a
subtraction can be wrong; an absent write cannot. It also sidesteps `_guard_run_cols`
(`0079:53-81`), which would hard-reject custody writes anyway once settled.

## §2 State representation — timestamp, not a new enum value

**Decision: `bookings.run_ended_at timestamptz` + two return stamps. Status stays `active`
throughout 귀가.**

Rejected: a new `returning` enum value. The scout measured the blast radius — every
`status = 'active'` check would have to learn the new value: the settle claim
(`0028:60-65`), `FLIGHT_RANK` resolvers, `available_runners`, the LA triggers, matching
guards. A new enum value also needs its own migration file (Postgres cannot add and use a
value in one transaction). The codebase already has the precedent for exactly this
situation — `arrived_at` is documented at `transition-booking/index.ts:242-244` as *a
stage that is a timestamp, not a status*.

Columns (all on `bookings`, mirroring `0045_custody_returns.sql:12-16` which did this for
club `session_dogs`):

| column | meaning |
|---|---|
| `run_ended_at` | the meter stopped. Set by the new `end_run` action. |
| `runner_confirmed_return_at` | runner stamped the return handoff |
| `owner_confirmed_return_at` | owner stamped the return handoff |

All three are **server-stamped only** and must join `run_protected_columns`-style
protection: `0057_security_hardening.sql:399-401` already protects the *pickup* stamps
from client forgery; the return stamps get the identical treatment. A client that can
stamp its own return can end custody unilaterally.

## §3 Settlement fires at RETURN, not at stop

Sequence: stop → `end_run` (meter cuts, stats freeze) → 귀가 → both sides confirm return
→ **then** `settle_run_tx` with the frozen numbers → record card.

Why not settle at stop: `completed` deletes the owner's LA push token (`0079:380-395`),
freezes `runs` (`0079:60-64`), and navigates the owner to `/owner/report` (`live.tsx:151`).
Settling at stop would mean the 귀가 state lives after completion and fights all three.
Keeping status `active` through 귀가 keeps the lock screen alive, the trace writable, and
the owner on the live screen — which is precisely where a person whose dog is still out
should be.

Honesty consequence, stated plainly: the service is not complete when the running stops.
It is complete when the dog is back. Settling at the doorstep matches what was sold.

**⚠ The hazard this creates, and its fallback.** If the owner never stamps the return, the
runner is unpaid. The pickup handoff carries the same structural risk (both sides must
stamp) but its failure mode is "run doesn't start" — recoverable. Here the failure mode is
money. Mitigation, mirroring club's force-resolve precedent (`0068/0069` C4/H5) and the
existing pickup nudge (`index.ts:295-296`):

- One-sided stamp notifies the peer immediately (reuse the pickup nudge path).
- After **20 minutes** with the runner stamped and the owner silent, the runner may
  **force the return** — it settles, and records `return_forced_by = 'runner'` so the
  event is legible rather than silent. The dog being physically returned is not
  contingent on the owner's phone.
- Timer starts at the runner's stamp, never at run-end (a runner walking home for 15
  minutes must not accrue force-eligibility for a return that has not happened).

## §4 Surfaces

### 4a. Runner — stop confirmation (`run.tsx`)

Inserts between `endWith`/`finish` and `settle` (`run.tsx:473-485`), i.e. **before** the
`handle.stop()`/`stopPublishing()` cluster at `:409-411`, which must NOT run at stop any
more — only the *stats* freeze; tracking continues for custody.

Dialog states the consequence in the two cases that differ:
- **Under minimum distance** (`km < plannedKm*0.5`, the existing `completed` gate at
  `handler.ts:72`): name it — 최소 거리에 못 미쳐 완주로 기록되지 않아요, and what that
  means for pay. This is the "early-end consequences named" clause of the TODO.
- **At or over**: plain confirm.

Copy is factual, never discouraging: the runner may be stopping because the dog needs to.

### 4a-bis. 🔴 The condition note is FABRICATED today — this slice fixes it

Found 2026-08-13 while scoping the stop dialog; escalated by the club-delegation session's
G1 sync, whose adopted decision depends on this field being real.

- `run.tsx:444` sends `condition_note: reason === 'dog' ? '러너 판단: 컨디션 저하 관찰' :
  undefined` — **a hardcoded constant**, sent because the server *requires* a note for
  dog-condition ends (`settle-run/handler.ts:53-54`).
- `run.tsx:478` tells the runner *"상태 사진과 메모를 남겨주세요"* — **there is no field to
  write one.** A dead promise in copy (§7 honesty law: no dead affordances).
- `owner/report.tsx:384` renders `run.conditionNote` to the owner as the runner's account
  of why their dog stopped. Every owner who has ever seen it read the same sentence.

Three laws broken at once: fabricated data presented as observation (the repo's first
law), a promise with no affordance, and — now — a money control resting on a constant.
**G1's adopted anti-gaming mitigation is literally "the record card for a dog_condition end
shows the runner's condition_note to the OWNER — the owner knows whether their dog was
actually unwell."** A constant cannot carry that. The per-runner dog_condition-rate
telemetry G1 also requires is measuring ends whose stated reason is unverifiable.

**Fix, inside the stop-confirmation dialog (§4a):** when the reason is `dog_condition`,
the dialog collects a REAL note — a required free-text field (the schema has said
`컨디션 종료 시 필수` since `0001:244`), with the existing photo affordance surfaced beside
it rather than merely mentioned. Empty/whitespace cannot proceed; the client stops sending
any canned fallback, so a missing note becomes a visible failure instead of an invented
sentence. The owner's report card keeps rendering the field — it just becomes true.

This is small, independently shippable, and gates nothing else — so it ships as **Slice 1**,
ahead of the state machine.

### 4b. Runner — 귀가 screen

Same screen, new mode (the run screen already has `panel`/`island` layouts; 귀가 is a
third visual state, not a new route). Stats row FREEZES at the stop values and is labelled
as frozen (`기록 확정 · 12.4km`). The primary CTA becomes **인계 확인** (return handoff).
Map/tracking stay live. The pace-state chip and its 권장 caption **disappear** — plan
§6 of the pace-state plan already recorded this composition point ("state freezes to ''
at 귀가 entry; custody is not a run, so no pace claim").

### 4c. Owner — live screen 귀가 state

`live.tsx:141-154` `done()` currently has one branch (`completed` → replace to report).
Add the earlier branch: `run_ended_at` set and not yet returned → **stay on the screen**
and render the 귀가 state:
- Status pill 집으로 가는 중, the dog's dot still moving (the channel is unchanged).
- Stats frozen with an explicit label — the numbers must not look live while they are not.
- The pace row is removed (no live claim during custody).
- Return-handoff affordance for the owner's stamp.

### 4d. Live Activity — a sixth phase

`phase: 'pre' | 'running' | 'stale' | 'done' | 'ended'` gains **`'homeward'`**
(`OwnerRunActivity.tsx:21`). Paint: pill 귀가, frozen km, footer 집으로 가는 중.
**No pace pill** (running-only, already gated at `:113`).

Server: driven by a new `after update of run_ended_at on bookings` trigger. ⚠ The trace
trigger hard-sets `phase='running'` on every trace write (`0079:297`) — it must be guarded
on `run_ended_at is null`, or custody fixes would fight the homeward phase every 60s. That
guard is the one edit inside 0079's territory and it belongs in this migration.

## §5 Server

New migration `0081_run_end_flow.sql`:
- three columns + protection (client-forgery seal, mirroring `0057:399-401`)
- `after update of run_ended_at` LA trigger → `phase 'homeward'`
- guard the 0079 trace trigger on `run_ended_at is null`
- settle path reads the frozen segment; the `active → completed` claim is unchanged
  (status never left `active`, so `settle_run_tx` needs **no** change — a deliberate
  win of the timestamp design)

New `transition-booking` actions:
- `end_run` — runner-only, stamps `run_ended_at`, status untouched, notifies owner.
- `confirm_return` — `meta.side` grammar copied verbatim from `confirm_handoff`
  (`index.ts:267-299`): stamp one side, **re-read fresh**, both stamped → settle-eligible
  + notify both; one stamped → nudge the peer.
- `force_return` — runner-only, ≥20min after the runner's own stamp, records the forcing.

## §5-bis Two collisions found by reading the code (verified 2026-08-13, pre-review)

**C1 — the stale sweep would lie during every 귀가. (critical, found by inspection)**
`owner_la_sweep_stale()` (`0079:317-357`) selects `from owner_la_tokens t join bookings b
... and b.status = 'active'` and pushes `phase='stale'` + "N분째 위치가 갱신되지 않았어요"
whenever the last `runs.trace` point is older than 90s. Under this design 귀가 keeps status
`active` **and deliberately stops persisting the trace** — so 90 seconds into every single
귀가 the sweep would overwrite `homeward` with a stale claim, once a minute, telling the
owner the位치 is unknown while the dog's dot is visibly moving on their map. It is the
exact "no signal ≠ something else" confusion the pace-state work just designed out.
**Fix (this migration): `and b.run_ended_at is null` in the sweep's join.** Custody is not
a signal failure. Pinned by R8-b.

**C2 — the auto-settle effect must not fire during 귀가. (high, found by inspection)**
`run.tsx:493-501` fires `settle(null, true)` when `reachedTarget && appActive`. Its first
guard is `if (!running || !appActive) return`, so setting `running = false` at run-end
makes it inert — but *only by accident of an unrelated flag*. Since tracking must stay
alive during 귀가 (custody), the flags separate: `running=false` + `homeward=true`, with
tracking owned by `handle.current`, which is untouched by either. **The effect gets an
explicit `!homeward` guard anyway** — money-moving code should not depend on a coincidence,
and the next reader deserves to see the intent.

## §6 Harness pins (suite `117_run_end_suite.sql`)

Placement follows the scout's map of which suite owns which law:
- **This suite**: R1 `end_run` stamps and does NOT change status · R2 client cannot forge
  any of the three stamps · R3 one-sided return notifies, does not settle · R4 both sides
  → settle-eligible · R5 force-return refused before 20min, allowed after, and only by the
  runner · R6 force-return records its actor · R7 LA phase 'homeward' on the stamp ·
  R8-a trace trigger stays silent (does not push 'running') while `run_ended_at` is set ·
  **R8-b the stale sweep skips a 귀가 booking entirely** (§5-bis C1 — the pin that stops
  the lock screen from claiming lost signal while the dog is walking home).
- **`116_charge_suite`**: the money pin — custody distance never reaches
  `compute_owner_charge`'s basis.
- **`10_settle_suite`**: settle after a return is a normal `active → completed` claim
  (proves the timestamp design left the money path untouched).

## §7 NOT in scope

- Emergency-stop refund path (G1) — its own TODO, its own money cycle.
- 더 뛰어도 좋아요 fast-finish nudge + level-up signal (TODO's second paragraph) — a
  separate encourager feature; this slice builds the state machine it would ride on.
- Club sessions — they already have `session_confirm_return` (`0046`) and their own phases.
- Charging for custody time — explicitly never (귀가 is custody, not service).

## §8 Open for Sean

- **D-r1 force-return window**: 20 minutes. Alternative: no force at all (runner must
  reach the owner). Rec: keep the force — the alternative makes an unresponsive owner able
  to withhold a runner's pay.
- **D-r2**: should the owner's stamp be *required*, or should the runner's stamp alone
  settle after a nudge? Rec: required + force fallback (above), because the two-sided seal
  is what makes the handoff a ceremony rather than a claim.
