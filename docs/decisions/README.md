# Money decision memos — the single index (consolidated 2026-08-13)

Six memos, one directory. Two sessions wrote overlapping sets in parallel
(`docs/decisions/` here + `docs/decisions-open-money.md` on mainline); at consolidation
the duplicate was retired INTO this directory with its text preserved, and the one place
the two sets genuinely disagreed was surfaced rather than merged away.

**Sean picks by letter. One line per memo is enough.**

| # | Memo | Status | Recommendation |
|---|---|---|---|
| ① | [g1-abort-charge-basis.md](g1-abort-charge-basis.md) | ✅ **RULED — C** | `dog_condition` = **FULL ACTUALS** (base + distance, like `completed`); `incident` = ₩0 at settle. Sean overrode both sessions' recommendations. Code change spec'd in the memo; required copy: the report must say stopping was right + show the runner's `condition_note`. |
| ② | [d3-silent-charge-summary.md](d3-silent-charge-summary.md) | ✅ agreed, needs counsel | Monthly summary, never a per-charge push. Ask counsel; 전자상거래법 footer is a hard dependency at 사업자등록. |
| ③ | [ops-profile-id-vs-admin-role.md](ops-profile-id-vs-admin-role.md) | ✅ agreed, shipped | Env var for the pilot; payloads already redacted (`f9f7be7`). |
| ④ | [club-fare-base-alignment.md](club-fare-base-alignment.md) | ✅ **RULED — A** | **Keep ₩9,900 as a deliberate club premium** (host coordination + 집결지). No code change. REQUIRED: a one-line disclosure on the club payment surface before the cutover — an undisclosed premium is the version that costs trust. |
| ⑤ | [club-enroute-cancel.md](club-enroute-cancel.md) | 🟡 OPEN | **C — route en-route club cancels into the incident flow** (a button, not a wall). |
| ⑥ | [cutover-straddle.md](cutover-straddle.md) | 🟡 OPEN (at flip time) | **B — set `payments_live_since` to a FUTURE timestamp** past the longest in-flight booking. |

② gates the `payments_live_since` flip (counsel). ⑤/⑥ are pre-cutover: nothing is charged
until the flip, so both are cheap now and expensive after.

## Open work created by the rulings

| From | Work | Owner |
|---|---|---|
| ① C | `compute_owner_charge`: `dog_condition` → actual basis, `incident` stays waived; split the 116 pins at :223/:226 | charge-slice session (owns 0080 + harness) |
| ① C | Report/record-card copy: stopping was the right call + show the runner's `condition_note` — required, not optional | run-end-flow session (owns the report surface) |
| ④ A | One-line club-premium disclosure on the club payment surface, before the cutover | club/next money slice |

## How ① was decided (read before "correcting" it)

Sean delegated the original three calls to this session's recommendations. The
charge-slice session — which owns the built code — refused to treat a *relayed* adoption
as authorization, correctly: a confirmation gate another session can perform is not a
gate. That refusal held the 🔴 in place. Consolidation then revealed the two sessions had
reached **different answers on `dog_condition`** (₩0 waive vs distance-only), each from
its own adversarial round — a founder's risk preference, not a resolvable engineering
question. Put to Sean, he chose **C, which neither session recommended**. That is the
system working: the models surfaced the trade-off honestly and the human made the call.
**Do not "fix" ① back toward a memo's recommendation.**

## Provenance & method

- Original ①–③ memos + dual-voice adversarial round (Claude subagent 12 findings, Codex
  gpt-5.6-sol 16): club-delegation session, 2026-08-13.
- Independent ①–③ + club-specific ④–⑥: charge-slice/club-gates session, same day, written
  against the BUILT code (0080/0081). Text preserved verbatim in ④–⑥.
- Cross-session findings that changed shipped code: the club-delegation round found a
  **financial-data disclosure** (a valid-but-wrong `OPS_PROFILE_ID` put another customer's
  order number and ₩ amount on a stranger's lock screen via 0024's verbatim push) — fixed
  by payload redaction in `f9f7be7`. The charge-slice round found the memo hole that
  `incident` must stay ₩0 for an architectural reason, so a future re-pick can't
  accidentally pre-empt 0072's adjudication. Neither was visible from inside the session
  that wrote it.
- Restore point for this session's drafts:
  `~/.gstack/projects/seankookim-daengrun/claude-club-delegation-money-gaps-b59eb8-autoplan-restore-20260813-111952.md`
