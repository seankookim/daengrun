# Decision memos — the three §4/§9 money calls (ADOPTED 2026-08-13, pending Sean's merge)

One page per decision: the adopted option, the options that lost, and an
adversarial-round addendum reconciled against the BUILT charge slice (0080).

**Provenance & confirmation protocol:** Sean delegated all three calls to the memos'
recommendations in the club-delegation session (/autoplan 2026-08-13, "go ahead with
all things you think will help like u wrote in the mds"). The charge-slice session
correctly refuses to treat a *relayed* adoption as authorization — so the shipped
code keeps G1's 🔴 provisional marker and D-3 stays unbuilt until Sean confirms
directly. **Sean's review+merge of this branch IS that written confirmation**; until
it lands, downstream sessions treat these as provisional-adopted. Any box can still
be re-checked; G1 flips apply forward-only.

| # | Memo | Decision | ADOPTED | Build state (0080 tree) |
|---|---|---|---|---|
| 1 | [g1-abort-charge-basis.md](g1-abort-charge-basis.md) | G1 abort-charge basis | **O1 waive** (dog_condition waives; incident-class defers to 0072 adjudication) | `g1_waive` shipped at 0080:266 (provisional 🔴); `waived` status + row-existence sweep already satisfy the P0 |
| 2 | [d3-silent-charge-summary.md](d3-silent-charge-summary.md) | D-3 silent-charge users | **B monthly in-app summary** (amount-free push, immutable KST statement row) | NOT built — next money slice, migrations ≥0082 |
| 3 | [ops-profile-id-vs-admin-role.md](ops-profile-id-vs-admin-role.md) | OPS_PROFILE_ID | **A env var** + payload redaction (supersedes the OPS_EMAIL idea) | Redaction fixed in charge-slice session (f9f7be7); reconciliation is 4-arm in 0080 |

Source of truth for the model: `docs/plans/payments-toss-plan.md` (§0-bis, §0-ter +
BUILT banner). The D-3 adoption AMENDS §0-bis (third money-UI mode: one scheduled
aggregate receipt/month) — amended in the same commit as this adoption.
NOTE: the charge-slice session independently drafted `docs/decisions-open-money.md`
(same three topics) on its branch — this set is canonical (Sean engaged with it);
the other folds in and retires at consolidation.

## Decision Audit Trail (/autoplan 2026-08-13)

Dual voices: Claude subagent (independent, 12 findings) + Codex gpt-5.6-sol (16).
Both agreed all three PICKS survive. Cross-session reconciliation with the built
charge slice then resolved which accompaniments were already satisfied.

| # | Decision | Classification | Principle | Outcome |
|---|---|---|---|---|
| 1 | G1 = O1 waive | Delegated by Sean | — | Shipped provisionally (0080:266); 🔴 until Sean's merge |
| 2 | G1 incident-class defers to 0072 adjudication | Auto (both voices) | P4 reuse | Recorded; build slice honors at flip time |
| 3 | Waive = first-class `waived` payments status | Auto (both voices, P0) | P5 explicit | ALREADY SATISFIED by 0080 (payments_waived_is_zero; sweep keys on row existence incl. waived — independently hardened R3 P3-9) |
| 4 | G1 flips forward-only | Auto (Codex) | P1 | Recorded policy |
| 5 | Per-runner G1 telemetry + owner-visible condition_note | Auto (both voices) | P1 | STILL REQUIRED — timed to the CUTOVER GATE (fraud incentive starts at payments_live_since; builds in the slice that flips it) |
| 6 | D-3 = B monthly summary | Delegated by Sean | — | Unbuilt pending Sean's direct confirm; spec in memo |
| 7 | §0-bis amended (third money-UI mode) | Auto (both voices) | P5 | Done in this commit |
| 8 | Summary push amount-free | Auto (both voices, P0) | P3 | Spec'd (0024 trigger pushes body verbatim with sound) |
| 9 | Statement = immutable (owner, period-KST) row | Auto (Codex) | P1 | Spec'd; needs migration ≥0082 |
| 10 | Recurring pause after 8 runs w/o app open | Auto (Claude) | P1 | Spec'd; rides the D-3 slice |
| 11 | OPS = A env var | Delegated by Sean | — | Stands |
| 12 | Wrong-uuid financial-data leak | Auto (both voices, P0-class) | P1 | CONFIRMED REAL by charge-slice session; FIXED there via payload redaction (f9f7be7) — better than the OPS_EMAIL cross-check, which is retired (a second env var that must also be right just moves the question) |
| 13 | Reconciliation arms per marker class + heartbeat | Auto (both voices) | P1 | LARGELY SATISFIED (0080 reconciliation 4-arm + 15-min verification arm); >0-rows loud-log heartbeat cron = cutover-gate item |
| 14 | `incident`-class = ₩0 at settle under EVERY option (0072 owns the money question; pick governs dog_condition only) | Auto (charge-slice fold-check delta) | P5 explicit | Absorbed into the G1 memo's invariants — survives any future re-pick |

No User Challenges. Restore point:
`~/.gstack/projects/seankookim-daengrun/claude-club-delegation-money-gaps-b59eb8-autoplan-restore-20260813-111952.md`
