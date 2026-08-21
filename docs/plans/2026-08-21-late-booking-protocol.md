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
