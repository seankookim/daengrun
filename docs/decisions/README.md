# Money decision memos — the single index

Eight memos, one directory. Two sessions wrote overlapping sets in parallel;
`docs/decisions-open-money.md` was retired INTO this directory, and Sean's rulings —
which he gave in the charge-slice session and which sat unpushed on one laptop while
this directory said the questions were open — are ported in below from `0fbaa64`.

| # | Memo | Ruling |
|---|---|---|
| ① | [g1-abort-charge-basis.md](g1-abort-charge-basis.md) | 🔴 **CONFLICTED — needs one more word from Sean.** He answered twice, differently: *base fare only, flat* (earlier, charge-slice session) vs *full actuals* (later, from a menu here that didn't contain his own answer). `incident` = ₩0 with verification, settled either way. **Nothing is being built on it.** |
| ② | [d3-silent-charge-summary.md](d3-silent-charge-summary.md) | ✅ **A — accept as-is. NOTHING TO BUILD.** No per-charge push, no monthly summary. ⚠ The statement-row slice is **CANCELLED, not deferred**. Counsel question survives as validation. |
| ③ | [ops-profile-id-vs-admin-role.md](ops-profile-id-vs-admin-role.md) | ✅ **C — `ops_recipients` table** with per-event-class routing ("build for full scale, not just for pilot"). Env var readable as a one-release fallback. Being built. |
| ④ | [club-fare-base-alignment.md](club-fare-base-alignment.md) | ✅ **Keep ₩9,900** — the club premium stands and funds host compensation (⑦) — **and make club price-invisible**, disclosed once at join/consent. No `club_fare` change. |
| ⑤ | [club-enroute-cancel.md](club-enroute-cancel.md) | ✅ **A — leave it.** Past handoff it's a case. Plus: the card-less club state routes to card registration, seamlessly. |
| ⑥ | [cutover-straddle.md](cutover-straddle.md) | ✅ **B — a FUTURE `payments_live_since`**, never `now()`. Straddlers free by construction; the flip procedure carries the query. |
| ⑦ | [host-incentives.md](host-incentives.md) | ✅ Agreed direction, not built. Host cut from **platform margin, never runner pay** — the ④ premium is the budget. |
| ⑧ | [card-registration-placement.md](card-registration-placement.md) | ✅ Agreed. **Inline at first booking**, not onboarding — under price invisibility the card-link screen is the consent moment for actuals-based charging. |

## The lesson this set paid for twice

**Unpushed work reserves nothing — decisions included.** The numbering registry
(`supabase/migrations/REGISTRY.md`) exists because migration numbers claimed on a laptop
collided five times in one day. The same failure then hit *decisions*: Sean answered six
questions, and origin went on telling every session they were open, because the answers
sat on one branch. Then it compounded — this session asked him ① again with a menu that
omitted his own answer, and got a different answer back. **A decision counts when it is on
origin, in the canonical directory.** Push docs immediately; they are never the thing
worth holding back.

## How to read a ruling here

Every memo keeps the superseded recommendation below the ruling, so the reasoning survives
and nobody "corrects" a ruling back toward a model's advice. Where Sean overrode both
sessions (①, ③, ④, ⑤), that is stated explicitly — the models' job was to surface the
trade-off honestly, and his call stands over both.

## Provenance

- ①–③ memos + dual-voice adversarial round (Claude subagent 12 findings, Codex 16):
  club-delegation session, 2026-08-13.
- ①–⑧ + Sean's rulings: charge-slice/club-gates session, same day, against built code
  (0080/0081); ported here from `0fbaa64` at consolidation with text preserved.
- Cross-session findings that changed shipped code: a **financial-data disclosure** (a
  valid-but-wrong `OPS_PROFILE_ID` put another customer's order number and ₩ amount on a
  stranger's lock screen via 0024's verbatim push) — fixed by payload redaction
  (`f9f7be7`); the **`incident` free-run hole** Sean's "verify first" instinct caught
  (`settle-run` whitelisted all six `end_reason` values on a public endpoint); and the
  **fabricated `condition_note`** (`run.tsx:444` sent a hardcoded string on every abort,
  making G1's anti-gaming control inert) — fixed in `611f014`.
