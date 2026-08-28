# Codex review — the club run-end freeze and the money it prices (0144 · 0147 · 0152)

**Date:** 2026-08-28 · **Reviewer:** codex `gpt-5.6-sol` @ `xhigh`, read-only sandbox
**Verdict: REJECT · 12 findings** — 1 CRITICAL, 6 HIGH, 5 MEDIUM
**Frozen at:** `ce509d9` · **Prompt:** `2026-08-28-runend-money.prompt.md` · 425,763 tokens
Detected with `grep -cE '^FINDINGS: [0-9]+'` on **stdout**; `usage limit` checked positively on
**stderr** and absent.

⚠ **This review was recorded as UNRESOLVED in the queue file while it was still running, and the
prediction attached to it was WRONG.** Its stderr had gone flat at 1.27 MB with 0 bytes of stdout
while the account was already quota-walled by a sibling run, so it looked exactly like a death at
the emit step. It was not — it finished normally with 26 KB of output. **Recorded because it is the
argument for writing 「unresolved」 instead of a guess**: the guess would have been wrong in the
direction that loses a CRITICAL finding.

---

## 🔴 FINDING 2, CONFIRMED BY EXECUTION AGAINST PRODUCTION — a live disclosure, today

Codex found it cold. It was then **reproduced on production**, which is the pairing this repo's
laws prescribe: codex reads without author reasoning, an executing agent measures what actually
happens.

**The mechanism.** `0147` grants `authenticated` direct EXECUTE on the INNER function, and that
function trusts a caller-supplied access grade instead of deriving it:

```
_club_delegation_board_impl(p_session uuid, p_access text)   prosecdef = true
has_function_privilege('authenticated', …, 'EXECUTE')      = TRUE      (anon = false)
body references p_access                                    = TRUE
body references _club_shell_access (comment-stripped)       = FALSE   ← it never re-derives
```

The outer `club_delegation_board` computes the grade properly with `_club_shell_access`. Nothing
requires a caller to go through the outer one. It is in `public`, which PostgREST **does** expose —
unlike the `net` case, where the schema allowlist was the thing that made a grant harmless.

**The proof, run as role `authenticated` with NO party relationship to the session:**

| call | dogs returned | payload | digest |
|---|---:|---:|---|
| `p_access = 'host'` (forged) | **1** | **2,185 B** | `7b3167f1…` |
| `p_access = 'none'` (control) | 0 | 663 B | `adf32cb1…` |

⚠ **The first attempt at this proof measured nothing and would have been reported as reassuring.**
Run against the first session id in the table, both grades returned identical digests — because
that session has **0 dogs and 0 runners**. An empty fixture discloses nothing regardless of grade.
The same empty-table trap that makes `billing_keys` unmeasurable by hand. The table above is from a
session that actually has content.

**What the forged grade hands over** — every field of the dog row, including:
`ownerName` · `runnerName` · `proposedRunnerName` · `custodianProfileId` · `runnerId` ·
`proposedRunnerId` · `bookingStatus` · `chargeState` · `refundState` · `payoutState` ·
`payoutHold` · `payoutHoldReason` · `openIncidentId` · `dogName` · `collar`.

**Real people's names, re-identifying profile IDs, money/charge/refund state and incident
references, for a session the caller has nothing to do with.** No flag gates it; it is live now.

**Fix:** `revoke execute on function _club_delegation_board_impl(uuid, text) from authenticated;`
Expose only `club_delegation_board`, which computes the grade server-side.

⚠ **Honest rung count.** OBSERVED: the grant, the trusted parameter, the absence of re-derivation,
and the differing payloads under a role switch. NOT observed: the same call over PostgREST with a
real user JWT. The DB-level result is what makes the disclosure real; the HTTP rung would only
confirm the route. It is a `public` function and PostgREST exposes `public`, so I do not expect a
surprise there — but that sentence is a READ, not a measurement.

---

## The other 11 findings

### CRITICAL

**1. Runner-authored future GPS can mint arbitrarily inflated pack earnings.** The assigned runner
supplies every coordinate and timestamp. Ingest checks only monotonicity and speed — it rejects
neither future timestamps nor trace duration — and derivation accepts every point after
`started_at`, including points after the host's tap. The only final bound is 100 km. A plausible
≤8 m/s trace extending hours into the future freezes 99 km into a 5 km booking, and payout writes
that distance into the ledger. Multiple active dogs handled by that runner receive the same trace.
**Moves the ledger and runner earnings TODAY**; only owner card collection waits for a flag.
*Fix:* reject future fixes at ingest, pass the tap time into derivation and require
`started_at <= t <= v_at`, restore a planned-distance-relative cap.

### HIGH

**3. The shipped client never invokes `club_end_pack_runs` at all.** VERIFIED INDEPENDENTLY:
**zero executable references anywhere under `app/`** — the only mentions in the repo are `0144`
itself and the REGISTRY. The host console's 종료 calls `club_finish_session`; runs are settled from
each runner's per-dog button, so **the runner's client values price the ledger, not the pack
freeze**. If host and runner both abandon, the booking stays active and both recovery arms exclude
club bookings. The whole 0144 feature has no caller.

**4. The host can freeze up to 60 s of stale trace while later GPS stays writable.** Uploads happen
every 60 s; the RPC freezes whatever is stored without requesting a flush, and leaves the booking
`active` so the trace RPC keeps accepting points. A truncated distance is priced, then the tail
lands after the price is immutable — while the run sheet still shows the local distance and says it
will be used for settlement.

**5. Two sparse or unusable fixes are misclassified as a measured zero.** No GPS / one point / a
silent device correctly return NULL. But with **two** points there is no maximum gap and no coverage
requirement: two identical endpoints hours apart, or a pair whose only segment is rejected as
teleport, return `0.00` and the caller accepts it as a completed measured run.

**6. `runEnded` fails OPEN under deploy skew, while frozen paths fail CLOSED on irrelevant GPS
state.** It is an optional truthiness-checked boolean, so `undefined`/stale `false` shows the reason
picker; the runner enters a dog-condition note, is told it will appear in the report, and the frozen
handler discards it. `owner_request` and `runner_personal` have different payout arithmetic, so the
discarded reason **can change today's runner net**. In the other direction a correctly frozen row
still cannot settle when `trackMode` is unavailable, though none of those client values are used.

**7. 0152's in-band refusal is allow-by-default in every live caller.** Consumers recognise only the
exact literal `incident_unmeasured`; the API converts an absent basis to `''` and an absent row to
an object of NULLs, so `Promise.all` resolves and the case screen offers 「선택」 for any missing or
new refusal reason. Safe for the exact current refusal; unsafe under skew or the next widened one.
*This is the widened-meaning law (§④) arriving exactly as predicted.*

**8. 0152 is incomplete — aggregates still turn unknown distance into zero.** `my_week_stats`
coalesces an all-NULL sum to zero; `fetchFitness` seeds the measured-only sum at zero and owner home
discards `weekUnmeasured`, printing a lower bound as the complete weekly distance; both leaderboard
functions rank all-NULL groups as `0km`. The per-run surfaces (report, receipt, my-record) correctly
preserve NULL — these aggregates are the remaining executable zero conversions.
> ✅ **Codex's own open question, ANSWERED against production:** `completed` bookings whose
> `runs.actual_km` is NULL = **0 of 8**. So this is **schema-reachable but NOT observable today**.
> ⚠ It is one transition away: of 9 runs, **1 has NULL km AND NULL duration** — the
> `end_reason='incident'` run whose booking sits in `incident_review`. The moment that resolves to
> `completed`, every surface above starts printing it as `0km`.

### MEDIUM

**9.** The runner earnings row labels settled money with the **planned** distance (`bookings.km`),
so a 5 km booking settled at 1.8 km shows 「5km」 beside a net priced from 1.8 km.
**10.** A lost settlement response turns a **committed** ledger into a false 「아무것도 반영되지
않았어요」 — the retry gets `not_active` while the money row already exists.
**11.** Any settlement with `refund > 0` writes `refund_pending` whether or not a payment was ever
captured, and owner/pay derives its phase from booking status alone, so it says 「환불이 진행
중이에요」 for a charge that never happened.
**12.** After ledger commit, a mint/dispatch exception is caught, logged, and reduced to a normal
happy settlement response — so once charging is live a card failure produces success haptics and no
visible failure state. Today the `skipped_not_live` branch prevents it.

### Cleared

0144's client RPC and 0152's two RPCs set `search_path` in-body and restate same-file ACLs. 0147
also sets `search_path` and restates its ACL — **its defect is the grant in finding 2, not a missing
ACL.** No additional body/search-path violation in the three migrations.

---

## Recommended order

1. 🔴 **Finding 2 — revoke the inner grant. One line, live disclosure of names + money state, today.**
   Nothing else here is as cheap or as urgent.
2. 🔴 **Finding 1 — the GPS fraud vector.** It mints money today. Needs an ingest-time bound plus a
   derivation bound; the cap policy is a product decision.
3. **Finding 3** decides how much of the rest matters: the pack-end feature has no caller, so 0144's
   freeze is not actually in the settlement path today. Whether the fix is 「wire it」 or 「retire it」
   is Sean's call, and findings 4 and 6 largely fall out of that answer.
4. Findings 5, 7, 8 are one 「unknown is not zero」 slice, continuing 0152's own job.
5. Findings 9–12 are honesty/idempotency defects on surfaces people read today.

## Still open

- What maximum GPS gap and minimum coverage define a measured run, including a genuinely stationary
  dog? (product)
- Is host pack-end allowed while a runner still considers the pair running, or is acknowledgement
  required? (product)
- Is there a host surface outside this repo calling `club_end_pack_runs`? (measured: nothing in
  `app/` does)
