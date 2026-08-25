# R17 remainder — the late-booking sweep's lock convoy (contract)

> **STATUS: SHELF DESIGN — DO NOT BUILD FROM THE BODY BELOW.** The dual-voice /autoplan
> review (GSTACK REVIEW REPORT at the foot of this file) rejected the convoy premise at
> pilot scale, found four design defects in §1/§3 as written, and re-scoped R17's remainder
> to a flip-activation package. The USER CHALLENGE at the very bottom is queued for Sean;
> his standing direction ("build the conversion") holds unless he accepts the re-scope.

**Provenance.** R17's first half landed with 0117 (§9f: a handoff stamp may not land on a
booking the clock already closed). This is the released remainder (announcer v5 → this session,
2026-08-25, recorded in trunk handoff commit 2b964ee): the sweep's transaction shape. Sean's
standing queue item 3.

## 0. The defect, precisely

`late_booking_sweep()` (0117:1197) is a FUNCTION: one call = one transaction. Its per-row
`BEGIN … EXCEPTION` blocks isolate *errors* per row, but not *locks* — every row lock its
workers take (`_resolve_checkin` locks `bookings` FOR UPDATE at 0117:843 and
`booking_checkins` at 0117:859; `open_checkin` likewise at 0117:507/511) is held until the
WHOLE batch commits. A 50-row tick holds 50 bookings' row locks for the duration of the batch;
every concurrent owner cancel, run start, and check-in answer touching any already-processed
row stalls behind the tick's tail. Invisible at 1 user; a convoy at 50. The existing
`lock_timeout=2000` (0117:1213) bounds how long the SWEEP waits for others — nothing bounds
how long others wait for the sweep.

## 1. The fix shape — procedure with per-row COMMIT, function kept for suite compatibility

Measured constraint that dictates the split: suite 152 drives the sweep via
`perform late_booking_sweep()` from inside plpgsql DO blocks (12+ call sites) — a DO block is
a transaction context, and a procedure that COMMITs raises `invalid transaction termination`
there. The harness runs suites without `--single-transaction` (harness.sh:117 — plain
`psql -f`), so a top-level `CALL` in a NEW suite is fine, but 152's in-block call sites must
keep a callable FUNCTION or be rewritten wholesale. The design keeps them byte-stable:

1. **`_late_sweep_candidates() returns table(kind text, booking_id uuid)`** — NEW, the single
   source of the three selection predicates (ⓐ expired check-ins → 'deadline' · ⓑ ceiling →
   'ceiling' · ⓒ arm → 'open'), each arm's predicate byte-moved from 0117:1218-1272, ordered
   arm-then-booking_id (the MINOR-14 determinism carried). Internal only (revoked from all
   client roles and service_role — R3S idiom: the explicit grants ARE the allowlist).
2. **`late_booking_sweep()` (function) SHRINKS to a loop over `_late_sweep_candidates()`** —
   same signature, same flag gate, same advisory try-lock, same per-row subtransaction +
   warning, same return count. One transaction, as today. Suite 152's call sites and pins
   survive verbatim; the selection logic stops being duplicated the moment the procedure
   exists (a rule copied N times is a rule you can fix N−1 times).
3. **`late_booking_sweep_tick()` (PROCEDURE)** — NEW, the cron path. Flag gate first; session
   advisory try-lock (SAME key `hashtextextended('late_booking_sweep', 0)` — session-scoped
   locks survive COMMIT, and sharing the key means the function and procedure can never run
   concurrently); materialize the candidate set ONCE into an array from
   `_late_sweep_candidates()`; then per candidate:
   `set_config('lock_timeout','2000',true)` (transaction-local, so re-set at each loop top —
   after a COMMIT the previous setting is gone; this is the trap the implementer must not
   simplify away) → subtransaction (`BEGIN … EXCEPTION WHEN OTHERS → raise warning`, exactly
   the shipped per-row idiom) invoking the same worker the function invokes → **COMMIT** —
   outside the exception block (COMMIT is illegal inside a subtransaction; the block must
   close first). Unlock; done. A stale candidate (state moved after the snapshot) is safe by
   construction: both workers re-read their rows under FOR UPDATE and refuse wrong states —
   the row no-ops or warns, never double-resolves (0117:843's lock-then-re-read is the
   guarantee, not the candidate list).
4. **Cron re-target**: unschedule `late-booking-sweep`, schedule the same name at the same
   `3-53/10` cadence with `call late_booking_sweep_tick()` — same guarded DO idiom
   (0117:1298), same 0060:145 stagger reasoning (unchanged tables).
5. **Grants**: procedure EXECUTE → service_role only (the scheduler-facing hand, CRIT-1's
   flag still gates it); function grants unchanged.

## 2. What this slice does NOT do (unstated scope reads as a seal)

- No change to any resolution RULE, amount, deadline, ceiling, grace, or fee — the workers
  (`_resolve_checkin`, `open_checkin`) are untouched.
- No change to the flag gate (clock stays OFF; the sweep returns/exits 0 while
  `late_protocol_live_since` is null — both entry points).
- No change to suite 152's pinned behaviours — its call sites keep compiling and its pins
  keep meaning what they meant (the function's observable behaviour is identical).
- Does not claim to fix convoy behaviour measurably under the harness — see §4 scope note.

## 3. Traps for the implementer (each one measured or documented in this repo)

- `set_config(..., true)` dies at COMMIT — re-set per row transaction (see §1.3), or the
  second row onward waits unbounded on abandoned locks (the MEDIUM-11 regression, silently).
- COMMIT inside an EXCEPTION-handled block raises `invalid transaction termination` — the
  subtransaction must CLOSE before the COMMIT (loop body = block, then commit).
- Do not loop directly over a held query portal with COMMIT inside — materialize the
  candidate array first (portability + determinism; the snapshot-staleness is handled by the
  workers' own state gates, §1.3).
- The advisory lock must be SESSION level (`pg_advisory_lock` family), not `_xact_` — a
  transaction-scoped lock would vanish at the first per-row COMMIT and a second tick could
  interleave from row 2 onward.
- The unlock-on-exception tail (0117:1288-1291) must exist in BOTH entry points; in the
  procedure it must also handle the case where the failure happens between commits (the lock
  is session-scoped, so the handler's unlock still works — but ONLY if the handler doesn't
  try to also ROLLBACK a transaction that isn't open).
- `search_path = public, pg_temp` in the procedure BODY (test 98 H1 watches the whole schema;
  ALTER-applied config resets on `create or replace`).
- REGISTRY row + migration file push in the same breath; number two-sided at write time
  (0121 is CLAIMED mid-build by ui6's 동 slice as of this writing — expect 0122, verify).

## 4. Suite + measurement plan (numbers resolved two-sided at write time; expect suite 156)

New suite pins (the procedure's own):
- **Parity pin**: identical fixture → `call late_booking_sweep_tick()` resolves/opens exactly
  the set the function resolves on a re-run fixture (three arms each exercised).
- **prokind pin**: `late_booking_sweep_tick` is `prokind='p'`; the function stays `'f'`.
- **Shared-source pin** (0118 §H prosrc idiom): BOTH entry points' `prosrc` reference
  `_late_sweep_candidates` — the anti-drift assertion; and the procedure's prosrc contains a
  `commit` token. ⚠ Scope stated honestly: this is a SOURCE-level assertion — it proves the
  commit statement exists, not that locks release mid-batch; see the scope note below.
- **Flag pin**: with `late_protocol_live_since` null, `call` exits 0-work (both directions:
  set the flag → work happens).
- **ACL pin**: anon/authenticated cannot execute the procedure; candidates fn revoked from
  service_role too.
- **Cron pin**: the registered command for `late-booking-sweep` is the CALL form (when
  pg_cron exists; guarded like the registration itself).
- **152 untouched proof**: suite 152 runs green with zero edits — the harness run itself is
  this pin.

Mutation battery (predicted red sets, each named):
- delete `_late_sweep_candidates` → [shared-source pin, parity pin] both entry points fail
- reintroduce inline predicates in the procedure (drop the shared call) → [shared-source pin]
- drop the COMMIT (procedure becomes function-shaped) → [prosrc commit token pin]
- swap session lock for `_xact_` → [a pin asserting the lock survives... source-level:
  prosrc asserts `pg_try_advisory_lock` not `pg_try_advisory_xact_lock`]
- drop the flag gate from the procedure → [flag pin]
- grant authenticated on the procedure → [ACL pin]
- drop the per-row lock_timeout re-set → [prosrc pin naming set_config inside the loop]

**Scope note, stated so the green is about the right sentence**: the harness is single-session;
lock-convoy RELIEF (the actual goal) is not observable in it. What the suite proves is that
the procedure exists, commits per row at the source level, shares the function's selection
source, keeps the function's behaviour bit-for-bit (parity + 152 green), and is sealed. The
convoy claim itself rides on PostgreSQL's documented transaction semantics (row locks release
at COMMIT), which the design makes true by construction — recorded here as reasoning, not as
a measurement.

## 5. Review path

Contract → /autoplan (standing gate: migration + money-adjacent) → implement (this session
authors; codex blind-reviews the diff with this contract but never the author's reasoning) →
harness measurement serialized with the fleet (announcer v5 notified before each run) →
mutation battery → REGISTRY row + push in one breath.

---

# GSTACK REVIEW REPORT

**/autoplan run, 2026-08-25 afternoon — CEO phase complete with two independent voices; Eng
phase deliberately deferred to the variant Sean picks (the spec-v1 precedent: reviewing
architecture for code the CEO verdict says not to build reviews screens that may never exist).**

## Voices

| Voice | Form | Headline |
|---|---|---|
| Claude CEO subagent (independent, no prior context) | 7 ranked findings, 1 CRITICAL | "The engineering is high quality; the strategy is inverted. Defer the procedure; extract the cheap wins; keep this as the shelf design it already is." ⚠ It grounded on the stale handoff (0117 unlanded) — corrected below; its conclusion survives the correction. |
| Codex CEO voice (gpt-5.6-sol, adversarial, given the corrected deploy facts) | premises + load arithmetic + design-defect list | "DEFER the per-row-commit procedure. BUILD a bounded, observable activation path only when the client flip is scheduled. The convoy mechanism is real; the urgency and the 50-user threshold are assumed." |

## CEO CONSENSUS TABLE

| Dimension | Claude | Codex | Consensus |
|---|---|---|---|
| Premises valid? | NO (convoy asserted, never derived) | NO (zero load today — flag null; "50 users" confuses users with simultaneously-late bookings) | **CONFIRMED: the convoy premise fails arithmetic at pilot scale** |
| Right problem NOW? | NO (zero current victims; PMF work waits) | NO (safe ACTIVATION is the real problem — the client cannot even answer a check-in yet) | **CONFIRMED: not now** |
| Alternatives explored? | NO (LIMIT, statement_timeout, cadence, managed flip all absent) | NO (same list + partial index + shorter lock wait) | **CONFIRMED: the contract under-explored** |
| 6-month regret? | Dual entry points fossilize; unmeasurable relief | Someone invokes the familiar function and silently restores the defect | **CONFIRMED: the dual-entry design is the regret** |
| Scope calibration? | Overbuilt (full adversarial cycle for an unobservable win) | Overbuilt (TRIM helper/parity/source-token battery) | **CONFIRMED: trim or defer** |

## Load arithmetic (the line the contract never did — both voices, converging)

Normal path at 50 users: **0.1–0.3 candidates/tick**; at 500 users: 1–3/tick; 5–30ms per row
warm. Worst-case batch lock hold under a second at any scale the pilot reaches in 12 months.
The convoy survives only under: a synchronized failure wave, pervasive foreground contention,
or **the first-flip backfill** — arm ⓑ ceiling-resolving every pre-protocol booking in one
tick, which is one-time, bounded, countable in advance, and schedulable off-peak. The real
tail amplifier is the 2s `lock_timeout` stacking per contested row, and the real steady-state
scaling cost is `booking_checkins`' missing partial index on unresolved deadlines — neither
of which the per-row-commit procedure addresses.

## DESIGN DEFECTS found in this contract (codex — the shelf design is NOT buildable as written)

1. **Privilege model contradiction**: §1's R3S-idiom revokes would leave the invoker
   procedure unable to call its own workers — and SECURITY DEFINER routines cannot perform
   transaction control, so "make it definer" is not an out. The privilege model needs a real
   design (definer workers + invoker procedure owned by a role with EXECUTE, or cron-owner
   ownership) before any build.
2. **The §3 unlock-tail trap contradicts itself**: an outer EXCEPTION handler makes the block
   a subtransaction, inside which COMMIT is illegal — the "unlock on exception in both entry
   points" requirement cannot be satisfied with a naive outer handler in the procedure.
3. **Single-snapshot materialization is NOT behavior-identical**: an expired unresolved
   check-in past the ceiling matches both arm ⓐ and arm ⓑ in one snapshot; today's
   sequential arms process it once (ⓑ sees ⓐ's write). The "parity" claim was false as
   written.
4. **`now()` drifts across per-row transactions** — largest exactly when the batch is long
   enough for the fix to matter.

## VERDICT

**DEFER the per-row-commit procedure. The contract stays on file as a corrected shelf design
(the four defects above annotated), and R17's remainder re-scopes to a FLIP-ACTIVATION
package** built when — and only when — the clock flip is scheduled:
① flip preflight (count all three arms' candidates live; inspect the pre-protocol backlog) ·
② per-arm LIMIT (~5) or shared batch budget, ordered by deadline/scheduled time ·
③ cron-session `statement_timeout` (~5s) as the total lock-hold fuse ·
④ sweep `lock_timeout` 2000→250ms ·
⑤ partial index on unresolved deadlines ·
⑥ the first flip performed off-peak with cron paused, backlog drained manually, rollback
decision pre-written. Build the procedure only on evidence: sustained candidates >~25/tick or
sweep p95 >250–500ms — then delete the function path outright (one entry point), rewrite the
152 call sites, and add a real two-session concurrency measurement.

## Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale |
|---|---|---|---|---|---|
| 1 | CEO | Corrected the Claude voice's stale base (0117 IS deployed) before weighing it | mechanical | verify-at-source | live ledger queried this morning |
| 2 | CEO | Convoy premise rejected; load model added to the record | mechanical | P6/P3 | both voices' arithmetic converges |
| 3 | CEO | Contract's four design defects recorded IN the contract | mechanical | P1 | a shelf design that hides its defects re-derives them later |
| 4 | CEO | Eng phase deferred to the chosen variant | taste→surfaced | P3/P6 + spec-v1 precedent | no architecture review for unbuilt code |
| 5 | CEO | Flip-activation package proposed as the re-scoped remainder | taste→queued | P2/P5 | bounded, observable, rides the flip Sean already owns |

## USER CHALLENGE — queued for Sean (never auto-decided)

**You said** (standing queue, this morning): item 3 is "R17's remainder" — the sweep →
per-row-commits conversion. **Both models recommend NOT building it now**: the convoy it
fixes fails arithmetic at pilot scale, the sweep is deployed but dormant (flag null — zero
load today), the client can't even answer a check-in yet, and the conversion as contracted
had four design defects. The recommended replacement is the flip-activation package above,
built when you schedule the clock flip. **What we might be missing**: you may know the flip
is imminent, or want the transaction work done while the code is warm. **If we're wrong, the
cost is**: the procedure gets built later from a corrected contract, ~a day, no compounding
debt. Your original direction stands unless you change it.
