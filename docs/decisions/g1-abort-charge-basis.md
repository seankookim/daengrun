# ① G1 — What does an aborted run charge the owner? (`dog_condition` / incident-class)

**Status: 🔴 CONFLICTED — Sean answered this TWICE, differently, in two sessions. Do not
build either answer until he picks one.** Nothing is being built on it; the shipped code
still waives both.

| Where | When | `dog_condition` | `incident` |
|---|---|---|---|
| Charge-slice session (`0fbaa64`) | earlier | **base fare ONLY, flat** — no distance, no addons. Follow-up clarification: *"base as just 7900"* | ₩0, **verify first** |
| This session (AskUserQuestion) | later | **full actuals** = base + distance (option C) | ₩0 |

**Why this happened, plainly: my menu did not contain his own answer.** His base-only
ruling lived in a memo that sat unpushed on one laptop, so when I consolidated I couldn't
see it and offered him A′ (waive) / D (distance-only) / C (full actuals). "Base only,
flat" was not on the menu. He picked C — the only option that charges the base at all.
That makes C a forced choice among three wrong options, not necessarily a reversal, which
is exactly why this must go back to him instead of being resolved by recency.

**The two answers differ more than they look.** They converge on a very early abort and
diverge as the run gets longer:

| abort point (3km booking) | base-only (earlier) | full actuals (later) |
|---|---|---|
| 0.2km | ₩7,900 | ₩8,500 |
| 1.5km | ₩7,900 | ₩12,400 |
| 2.8km | ₩7,900 | ₩16,300 |

**His earlier reasoning, which is worth preserving whichever way he rules:** the base fee
is what the runner's *showing up* costs — pickup, handoff, custody — and that labour
happened; the distance is what didn't. Charging the base and waiving the distance says
exactly that. Note the deliberate asymmetry it creates: the owner's charge is flat while
the platform's absorption grows with distance, so a welfare stop late in a run is the
expensive case for us — which is correct, or we'd be nudging runners to push on.

**Club consequence, either way (name it or someone files it as a bug):** the charge reads
the booking's own frozen `base_fare`, and ruling ④ kept the club premium — so a *club*
condition-abort charges **₩9,900**, not 7,900.

**`incident` is settled: ₩0, gated on verification.** Both answers agree. Sean's "verify
incident first to avoid abuse of this feature" found a real P1: `settle-run` whitelisted
all six `end_reason` values on a public HTTP endpoint, so once `incident` means "the owner
pays nothing" an assigned runner could POST it and hand themselves a free run. The
accepted set now narrows to the four a client can legitimately send. Fixed in the
charge-slice session.

**Required accompaniment, unchanged by which answer wins:** under any charging rule the
report/record card must say stopping was the right call and show the runner's own
`condition_note` — real only since `611f014` (it was the hardcoded constant
`'러너 판단: 컨디션 저하 관찰'` on every abort until 2026-08-13). Without it the owner is
billed for a stop they can't evaluate.

## Decision (Sean) — needs one answer

- [ ] **Base only, flat** (`ownerBaseFare` + addons, no distance) — what you said first
- [ ] **Full actuals** (base + distance) — what you picked from my incomplete menu
- [ ] Something else

`incident` = ₩0 with verification either way. Flips remain forward-only.

---

*Everything below is the analysis that produced the question. Kept for provenance.*

## The open question — where the two sessions split

Both sessions ran their own adversarial rounds and **agree on `incident`**; they disagree
on `dog_condition`.

| | `dog_condition` | `incident` |
|---|---|---|
| **Club-delegation session** (this memo's original) | **₩0 — waive** | ₩0 at settle |
| **Charge-slice session** (`decisions-open-money.md` ①, rec. D) | **₩3,000 × actual, no base** (≈₩2,400 on 0.8km of a 3km run) | ₩0 at settle |

**Agreed by both, for the same architectural reason:** `incident` charges **nothing at
settle** because `club_incident_settle` (0072) already quotes
`refund_full | settle_measured | pay_full` and a human adjudicates. Charging at settle
would pre-empt the case and manufacture exactly the refund post-pay was designed to
delete. This holds under every option below — the ruling governs `dog_condition` only.

### The case for ₩0 (waive)

The scariest moment the product has is a dog that couldn't continue. A bill arriving after
that moment is the wrong first experience of 안심, which is the whole pitch. Absorption is
bounded at pilot scale — the platform eats the runner's NET comp,
`(1−commission) × max(9,900 + 3,000×actual + addons, min_fare)` — and the copy is the
cleanest possible: the record card and the incident flow carry no money at all.

### The case for distance-only (the argument the waive analysis missed)

A completely free outcome puts **unbounded, invisible cost on the platform for a case that
recurs with the same dogs**. An owner with a chronically unfit dog gets free runs
indefinitely and nothing in the system notices. Distance-only keeps the ₩7,900 base
absorbed (a welfare stop must never cost a base fee, or the incentive points the wrong
way) while making repeat aborts non-free. Tiny aborts auto-waive anyway via the
`below_pg_minimum` (<₩100) arm.

**Why the models couldn't settle this:** the waive case optimises for the first emergency;
the distance-only case optimises for the tenth. Which risk you'd rather carry in a Banpo
pilot is a founder call. Neither session would move, and neither should have — the
disagreement is real, not a miscommunication.

## Options

| # | Rule | Owner pays (0.8km of a 3km run) | Consequence |
|---|---|---|---|
| **A′** | **`dog_condition` ₩0, `incident` ₩0** (= shipped provisional) | ₩0 / ₩0 | Club-delegation session's pick. Maximum trust; repeat aborts free and invisible. |
| **D** | **`dog_condition` distance-only, `incident` ₩0** | ₩2,400 / ₩0 | Charge-slice session's pick. Never a base fee on a welfare stop; repeats not free. |
| C | Full actuals for `dog_condition` (base + distance) | ₩10,300 | "Pay what happened." Risks an owner pressuring the runner to keep going. Recommended by neither. |

## Consequences that don't change with the pick

- **`incident` stays ₩0 at settle under EVERY option** — 0072 owns that money question.
- Owner basis ceiling: never above `min(actual, planned)` → never above quote (#4).
- Charges compute from the booking's FROZEN numbers, not live constants (#6).
- **Flips are FORWARD-ONLY** — a later change applies to newly consented bookings, never
  retroactively (frozen-numbers doctrine, extended to abort policy).
- The waive representation is already correct in code: `waived` is a first-class payments
  status (`payments_waived_is_zero`), excluded from the kind-scoped debt derivation, and
  the settled-without-payments sweep keys on ROW EXISTENCE including `waived`
  (0080:594-597). This was the club-delegation session's P0 finding; the charge-slice
  session had independently closed it (R3 P3-9). Recorded so nobody "simplifies" it away.

## The gaming vector — flagged by both, fixed by neither (cutover-gate work)

`completion_rate` counts only `completed` + `runner_personal` (0001:72, 0028:139), so
`dog_condition` is a **stat-free early exit for a runner**, gated only by their own
free-text `condition_note`. Under A′ the owner never disputes a fabricated abort either —
the waive also removes the free fraud detector. The countermeasure is a metric, not a
price: **per-runner abort-rate + absorbed-KRW telemetry**, plus showing the runner's
`condition_note` to the owner on the record card (the owner knows whether their dog was
actually unwell). Timed to the cutover gate — the incentive only exists once
`payments_live_since` is set. ⚠ That note was a hardcoded constant until 2026-08-13
(`run.tsx:444`); the run-end-flow session shipped the runner-writes-it fix (`611f014`),
which is a **precondition** of this mitigation meaning anything.

## Decision (Sean) — RULED 2026-08-13

- [ ] **A′** — `dog_condition` ₩0, `incident` ₩0 (was the shipped provisional)
- [ ] **D** — `dog_condition` distance-only (₩3,000×actual, no base), `incident` ₩0
- [x] **C** — **full actuals for `dog_condition`; `incident` ₩0 at settle. SEAN'S RULING.**

Neither session recommended C. Sean's call stands over both model recommendations —
recorded that way deliberately, so nobody later "corrects" it back to a memo's advice.
Flips remain forward-only.

## Provenance

Original memo + adversarial round (Claude subagent + Codex, 12 + 16 findings) in the
club-delegation session, 2026-08-13; Sean delegated the recommendation there. The
charge-slice session independently wrote the same memo, reached a different
`dog_condition` answer, and correctly refused to build on a relayed adoption. At
consolidation (2026-08-13) both were merged here and the divergence surfaced rather than
resolved by either model.
