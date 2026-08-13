# Money decision memos — the single index (consolidated 2026-08-13)

Six memos, one directory. Two sessions wrote overlapping sets in parallel
(`docs/decisions/` here + `docs/decisions-open-money.md` on mainline); at consolidation
the duplicate was retired INTO this directory with its text preserved, and the one place
the two sets genuinely disagreed was surfaced rather than merged away.

**Sean picks by letter. One line per memo is enough.**

| # | Memo | Status | Recommendation |
|---|---|---|---|
| ① | [g1-abort-charge-basis.md](g1-abort-charge-basis.md) | 🟡 **OPEN — the sessions split** | `dog_condition`: **A′ ₩0** (club-delegation) vs **D distance-only** (charge-slice). `incident` = ₩0 at settle either way. |
| ② | [d3-silent-charge-summary.md](d3-silent-charge-summary.md) | ✅ agreed, needs counsel | Monthly summary, never a per-charge push. Ask counsel; 전자상거래법 footer is a hard dependency at 사업자등록. |
| ③ | [ops-profile-id-vs-admin-role.md](ops-profile-id-vs-admin-role.md) | ✅ agreed, shipped | Env var for the pilot; payloads already redacted (`f9f7be7`). |
| ④ | [club-fare-base-alignment.md](club-fare-base-alignment.md) | 🟡 OPEN | **B — align `club_fare` to 7,900 before the cutover.** Club owners currently pay ₩2,000 more than marketplace for the same km. |
| ⑤ | [club-enroute-cancel.md](club-enroute-cancel.md) | 🟡 OPEN | **C — route en-route club cancels into the incident flow** (a button, not a wall). |
| ⑥ | [cutover-straddle.md](cutover-straddle.md) | 🟡 OPEN (at flip time) | **B — set `payments_live_since` to a FUTURE timestamp** past the longest in-flight booking. |

①/② gate the `payments_live_since` flip. ④/⑤/⑥ are pre-cutover: nothing is charged until
the flip, so all of them are cheap now and expensive after.

## Why ① is still open (read this before assuming it was mishandled)

Sean delegated the three original calls to this session's recommendations. The
charge-slice session — which owns the built code — refused to treat a *relayed* adoption
as authorization, correctly: a confirmation gate another session can perform is not a
gate. That refusal held the 🔴 marker in place. Then consolidation revealed the two
sessions had reached **different answers on `dog_condition`** (₩0 vs distance-only), each
from its own adversarial round. No model resolved it, because the disagreement is a
founder's risk preference: waive optimises for the first emergency, distance-only for the
tenth. It is the one thing genuinely waiting on Sean.

**Nothing was built on the relayed adoption.** ① keeps its 🔴 provisional (both end
reasons charge nothing today) and ② is unbuilt.

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
