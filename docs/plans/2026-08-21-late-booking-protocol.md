# Late / unresponsive reservation — CEO review, 2026-08-21

`/plan-ceo-review` · mode **HOLD SCOPE** · branch `claude/client-redesign-v4-work-3e224f`
Live evidence: Sean's account holds a `runner_enroute` booking from **2026-08-04 — 17 days stale**.
Owner home hero reads 「예약 시간이 지났어요」 / 「아직 정리되지 않았어요」 with no resolution path.

---

## 1. Audit — three findings, each verified in source

**F1. `no_show` is a status nothing produces.** It is a legal destination from `confirmed` and
`runner_enroute` (`0001_init.sql:205-206`, re-stated in 0005, 0047, 0066), it sits in the ledger's
terminal trigger (`0075_km_ledger.sql:750`), and the client renders it as a 불발 badge
(`owner/schedule.tsx:56`). **No cron, no edge function, no RPC ever writes it.** The app has a
vocabulary for lateness with no clock and no actor behind it.

**F2. The only expiry cron stops at the match.** `expire-unmatched` (`*/5`) moves
`matching|runner_pending → expired`. There is **no timeout on `confirmed`, `runner_enroute`,
`picked_up` or `active`.** Once a runner accepts, the booking has no clock. F1 + F2 are why the
Aug 4 row is still open.

**F3. ⚠ This codebase already ruled against timer-driven money, ten days ago.**
`0068_retire_t10_hard_stop.sql` DELETED an automatic T-10 refund:

> "moving the hard stop to T+0 or T+6h would only relocate the same disagreement… Refunding when
> the host closes the session is true; refunding ten minutes before it starts is false."
> "ACCEPTED RESIDUAL … a stuck refund an operator can still resolve … is **strictly better than an
> automatic refund fired at the exact moment the service was about to be delivered**."

Any design here that moves money on a clock is overturning a decision that already exists.

## 2. The premise correction

The question was "which decisions and statuses should each side see." One layer down: **there is no
lateness event to present.** Build screens over a state machine with no clock and you get honest
screens that still cannot resolve anything. Statuses were never the gap.

## 3. Decisions (Sean, this session)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Two-sided check-in protocol**, not a bare timeout | A silent status flip tells neither human what to do; this is custody of a live animal |
| D2 | **HOLD SCOPE** | C is already the expansion; the pilot needs it bulletproof, not bigger |
| D3 | **Split the protocol at the handoff line** | The schema already draws it and is right |
| D4 | **Money follows fault** | The protocol's only real output is knowing who failed |
| D5 | **…but fault requires a human statement — silence never charges** | 0068 + push is not evidence |

## 4. Design

### 4.1 The handoff line is the seam (D3)

```
  PRE-CUSTODY                          ║  POST-CUSTODY (dog is with the runner)
  confirmed / runner_enroute           ║  picked_up / active
  ─────────────────────────────────────╫──────────────────────────────────────
  no_show is LEGAL                     ║  no_show is ILLEGAL — guard refuses it
  "the service did not start"          ║  "something happened to a dog"
  terminal: no_show (no fee)           ║  terminal: incident_review
  exits: reassign · cancel · re-book   ║  exits: 0072 case settlement, 0096 return stamps
```

`0066:50` closes `picked_up → no_show` deliberately: *"picked_up below stays closed: past the
handoff it's an incident."* One prompt, two protocols, terminal chosen by custody.

### 4.2 The clock notices and offers; it never decides (D5)

```
  scheduled_at + grace
        │
        ▼
  ┌─────────────────┐   both confirm   ┌──────────────────────────────┐
  │  CHECK-IN OPEN  │─────────────────▶│ run proceeds late            │
  │  ask BOTH sides │                  │ ⚠ NEW bounded deadline set   │
  └─────────────────┘                  │   (else the rot returns)     │
        │                              └──────────────────────────────┘
        ├── owner states "runner never came" ──▶ no_show · owner fee 0 · runner record
        ├── runner states "waited and left"  ──▶ no_show · runner compensated · owner fee
        │
        └── SILENCE (either or both) ──▶ void to a NO-FEE terminal
                                        + alert + exits offered
                                        + NEVER a charge, NEVER a fault record
```

**Silence is not evidence.** Push dispatch swallows Expo errors (`0024_push.sql:19`); registration
silently exits on denied permission or missing token (`push.ts:125`); the only fallback is an alerts
screen capped at 20 rows (`alerts.tsx:61`). A runner at the door with a dead phone is
indistinguishable from a runner who never came. The clock may therefore void, alert and offer — it
may never charge or blame.

### 4.3 Maximum lateness (from the codex pass)

Two taps must not resurrect a 17-day-old booking. Nothing currently enforces `scheduled_at` at run
start. A hard ceiling is required past which the check-in stops offering "proceed" and offers only
terminals.

## 5. Failure modes registry

| # | Failure | Sev | Handled by |
|---|---|---|---|
| FM1 | Runner at the door, phone dead, owner silent → marked no_show | **Critical** | D5: silence never charges or blames |
| FM2 | Check-in prompt never delivered; countdown runs invisibly | **Critical** | State-derived prompts on home/schedule/meetup, refresh on resume; push demoted to alert |
| FM3 | Both confirm, then both vanish — unbounded again, just later | High | §4.2 bounded renewed deadline + second watchdog |
| FM4 | Two taps revive a 17-day-old booking | High | §4.3 maximum lateness ceiling |
| FM5 | `picked_up → no_show` attempted | High | D3 split; guard would raise `invalid booking transition` |
| FM6 | Simultaneous answers / timeout racing a response | High | One transactional resolver: per-side immutable responses, server timestamps, `resolved_at` CAS, booking status re-read under the same lock |
| FM7 | Owner charged the 50% en-route arm for a runner's failure | High | D4/D5: that arm prices OWNER cancels; no-show fault is separate |
| FM8 | Late response retracts an already-offered cancel/reassign | Med | Resolver decides; offered actions expire with the check-in |

## 6. Domain split — what is mine and what is not

**Client (`app/`), mine, buildable now:** the check-in surface on both sides · state-derived prompts
that do not depend on push · the custody-aware terminal copy · the exit buttons and their screen
paths · honest hero/schedule states for a stale booking.

**Server (`supabase/`), NOT my domain — needs Sean's ruling:** the clock itself (cron), the
transactional resolver, any fault persistence, and any money. §0-quinvicies is still open.

⚠ The client half **cannot end the rot alone** — that was the whole finding against approach A. It
can stop the screen lying while the server half waits for a ruling.

## 7. Codex third-opinion findings (gpt-5.6-sol xhigh) — absorbed

Verdict was **request changes**. Accepted in full and reflected above: silence-is-not-evidence
(FM1/FM2, and it refuted my own "never a guess" claim), the unbounded-after-confirmation hole (FM3),
no maximum lateness (FM4), the unspecified race model (FM6), and the recommendation to split into
pre-custody attendance / custody recovery / financial adjudication rather than one protocol.

Mechanisms it correctly flagged as already existing and NOT covering this gap: `club_assignment_recovery`
(club-only), `purge-holds` (slot holds, not bookings), `0096` (return stamps after escalation, no
money), `runner_work_gate` (0092, does not cover stale confirmed/enroute/picked_up), `run-end-recovery`
(only runs that recorded an end), `owner_la_sweep_stale` and `ops_unsettled_runs` (detect, never repair).

## 8. NOT in scope

Runner reliability tiering · owner punctuality scoring · automatic re-matching on a dark runner ·
M1 instrumentation for late bookings. All raised and deliberately deferred under HOLD SCOPE (D2);
designing a reputation system before observing one real late booking is premature.

## 9. Next steps

1. **[needs-Sean]** Ruling on the server half (§6) — the cron, the resolver, fault persistence.
   Without it this stays a client-side honesty fix and the rot survives.
2. **[client, mine]** State-derived check-in surface that does not depend on push (FM2) — the single
   highest-value client piece and it is a prerequisite for the server half being trustworthy.
3. **[client, mine]** Custody-aware terminal copy and exits, replacing 「아직 정리되지 않았어요」 with
   a path.
4. **[needs-Sean]** The maximum-lateness ceiling (§4.3) is a product number, not an engineering one.

## 10. Unresolved

- **The grace period and the ceiling are unset numbers.** Both are product calls.
- **Who works the stuck queue.** D5 accepts 0068's residual — a human resolves what silence cannot.
  At pilot scale that human is Sean, and there is no ops surface for it today.

---

# ENGINEERING PLAN — `/plan-eng-review`, 2026-08-21

Four decisions (D1 target · D2 staging · D3 contract-first · D4 test home).

## 11. Staging (D2) — the domain line is the seam

**Stage 1 (client, mine, no ruling needed).** Detect and state lateness honestly; offer exits that
already exist. **Stage 1 physically cannot take a check-in answer** — an answer needs durable server
state and no column exists. Stage 1 is therefore the client-only approach rejected in the CEO
review, re-cast as a prerequisite rather than a substitute: codex's FM2 says a clock whose prompt
may never arrive cannot be trusted, so the state-derived surface must exist BEFORE the server clock
is allowed to mean anything.

**Stage 2 (server, needs Sean's §0-quinvicies ruling).** The clock, the resolver, fault, money.

⚠ Named risk, accepted with eyes open: stage 1 alone leaves the rot intact and will look finished.

## 12. The resolver contract (D3) — defined here, implemented in stage 2

Written by the client side, which cannot verify it. Stage 2 implements *to* this; if it diverges,
the divergence is a decision, not a discovery.

```
booking_checkins
  booking_id    uuid  pk → bookings
  opened_at     timestamptz  not null   -- when the clock fired
  deadline_at   timestamptz  not null   -- BOUNDED. FM3: "both confirm then vanish" dies here
  owner_answer  answer null             -- null = unanswered ≠ answered-no
  owner_at      timestamptz null        -- SERVER clock, never client
  runner_answer answer null
  runner_at     timestamptz null
  resolved_at   timestamptz null        -- CAS target
  resolution    text null
  version       int not null default 0  -- optimistic lock

answer := 'proceeding' | 'cannot_proceed' | 'other_side_absent'
```

**Three calls.** `open_checkin(booking)` — cron only. `answer_checkin(booking, side, answer)` —
per-side IMMUTABLE, first write wins, idempotent on replay. `fetch_checkin(booking)` — what the
surface renders.

**Resolution, one transaction, CAS on `(resolved_at, version)`, re-reading `bookings.status` under
the same lock** (FM6; `90_race_check.sh` already has a two-connection harness for exactly this):

| Inputs | Pre-custody | Post-custody |
|---|---|---|
| both `proceeding` | new bounded `deadline_at`, no terminal | same |
| either `cannot_proceed` | `no_show`, fault = that side | `incident_review` |
| one `other_side_absent`, other silent | **void, no fee, no fault** (D5) | `incident_review` |
| both silent at deadline | **void, no fee, no fault** (D5) | `incident_review` |

Silence never appears in a fault column. `no_show` never appears post-custody (D3, guard `0066:50`).

## 13. Client contract for stage 1 (no server state required)

```ts
// src/lib/lateness.ts  (D4 — pure, testable, .cjs suite alongside route-pick/pace/geo)
lateness(b: {scheduledAt, status, arrivedAt}, now): {
  late: boolean
  sinceMs: number
  custody: 'pre' | 'post'        // status ∈ picked_up|active → 'post'
  waitingOn: 'runner' | 'owner' | 'both' | null
}
```

Derivable entirely from fields `fetchMyBookings` already selects. No new round trip.

## 14. Architecture constraints found in review

- **[P1] (9/10) Cron tick collision.** `0060:145` — *"every mod-5 minute offset is taken."* Its own
  precedent picked a tick "touching neither `bookings` nor `runs`", which a lateness sweep cannot
  honour. Stage 2 must either share a tick with a `bookings` job (and reason about lock contention)
  or run at a coarser cadence. Grace is minutes-scale, so `*/10` is likely fine and free-er.
- **[P1] (9/10) A second race lands beside an untested one.** `TODOS.md:253` — `confirm_return_tx`'s
  two-connection race is "named, not simulated". The resolver touches the same custody path. Stage 2
  should add BOTH to `90_race_check.sh`, not just its own.
- **[P2] (8/10) `arrived_at` is self-attested.** It is the only signal separating "en route" from "at
  the door", and stage 1's copy wants it — but the gate that reads it is reserved under Sean's
  handoff-CTA A/B. Stage 1 must not consume it as a gate; display only.

## 15. Stage 1 task list

| # | Task | Files | Effort (human / CC) |
|---|---|---|---|
| T1 | `src/lib/lateness.ts` + `app/test/lateness.test.cjs` | 2 new | 2h / 15m |
| T2 | Move E6 KST helpers to `src/lib` + tests (D4 settles this) | 4 | 3h / 20m |
| T3 | Shared late-booking surface component | 1 new | 4h / 25m |
| T4 | Mount on owner home + schedule; custody-aware copy and exits | 2 | 3h / 20m |
| T5 | Mount on runner home + meetup | 2 | 3h / 20m |
| T6 | Replace 「아직 정리되지 않았어요」 with a real path | 1 | 1h / 10m |

Ordering: T1 → T2 (same extraction, same suite) → T3 → T4/T5 → T6. T1 first because everything
downstream renders off its output, and it is the one piece with a test path.

## GSTACK REVIEW REPORT

| Run | Status | Findings |
|---|---|---|
| Scope gate (D1) | ✅ | Target = this plan doc, not the branch diff |
| Step 0 scope challenge | ✅ | Complexity gate TRIGGERED (7-8 client files, 3 new server services) → staged, not reduced |
| §1 Architecture | ✅ | 1 P1 raised to Sean (stage 1 cannot take an answer) + 2 P1 / 1 P2 recorded in §14 |
| §2 Code quality | ✅ | No blocking findings. One judgment recorded: shared component, not per-screen |
| §3 Tests | ✅ | Client had NO test path for this; resolved by D4 (`src/lib` + `.cjs` suite) |
| §4 Performance | ✅ | No issues — derivation is arithmetic over already-fetched fields |
| Outside voice (codex gpt-5.6-sol xhigh) | ✅ absorbed | Ran during the CEO phase against this same design; returned REQUEST CHANGES; all findings folded into §7 and §12 (silence-is-not-evidence, FM3 unbounded-after-confirm, FM4 no max lateness, FM6 race model) |

**VERDICT: APPROVED FOR STAGE 1.** The client half is buildable now against the §12 contract, with
T1 carrying the test coverage. Stage 2 is BLOCKED on Sean's `supabase/` ruling and must not be
started from this session's domain.

**CODEX absorbed:** yes — request-changes findings integrated rather than deferred.

**UNRESOLVED DECISIONS:**
- Sean's ruling on the `supabase/` half (§0-quinvicies) — without it stage 2 cannot start and the rot survives stage 1.
- The grace period and the maximum-lateness ceiling are unset product numbers, not engineering ones.
- Who works the stuck queue that D5 deliberately accepts — at pilot scale there is no ops surface and no on-call.
