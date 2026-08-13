# Money decision memos — the single index

Eight memos, one directory. Two sessions wrote overlapping sets in parallel;
`docs/decisions-open-money.md` was retired INTO this directory, and Sean's rulings —
which he gave in the charge-slice session and which sat unpushed on one laptop while
this directory said the questions were open — are ported in below from `0fbaa64`.

| # | Memo | Ruling |
|---|---|---|
| ① | [g1-abort-charge-basis.md](g1-abort-charge-basis.md) | ✅ **FULLY RULED — fault-based, both ledgers mirrored.** `dog_condition` = owner AND runner on distance-actually-run; `runner_personal` = runner 9,900 base only (owner side #10 unchanged); `incident` = ₩0 verify-first. Buildable. |
| ② | [d3-silent-charge-summary.md](d3-silent-charge-summary.md) | ✅ **A — accept as-is. NOTHING TO BUILD.** No per-charge push, no monthly summary. ⚠ The statement-row slice is **CANCELLED, not deferred**. Counsel question survives as validation. |
| ③ | [ops-profile-id-vs-admin-role.md](ops-profile-id-vs-admin-role.md) | ✅ **C — `ops_recipients` table** with per-event-class routing ("build for full scale, not just for pilot"). Env var readable as a one-release fallback. Being built. |
| ④ | [club-fare-base-alignment.md](club-fare-base-alignment.md) | ✅ **Keep ₩9,900** — the club premium stands and funds host compensation (⑦) — **and make club price-invisible**, disclosed once at join/consent. No `club_fare` change. |
| ⑤ | [club-enroute-cancel.md](club-enroute-cancel.md) | ✅ **A — leave it.** Past handoff it's a case. Plus: the card-less club state routes to card registration, seamlessly. |
| ⑥ | [cutover-straddle.md](cutover-straddle.md) | ✅ **B — a FUTURE `payments_live_since`**, never `now()`. Straddlers free by construction; the flip procedure carries the query. |
| ⑦ | [host-incentives.md](host-incentives.md) | ✅ Agreed direction, not built. Host cut from **platform margin, never runner pay** — the ④ premium is the budget. |
| ⑧ | [card-registration-placement.md](card-registration-placement.md) | ✅ Agreed. **Inline at first booking**, not onboarding — under price invisibility the card-link screen is the consent moment for actuals-based charging. |
| ⑨ | [runner-stop-split.md](runner-stop-split.md) | ✅ **RULED — both halves.** Supersedes G1's `runner_personal` runner-side row: **pass-through pay** (runner gets their commission share of what the owner actually paid) + new **`runner_incapacity`** enum for ill/injured, note required, platform absorbs. Build gate: it is self-declared, so it needs an abuse story before `settle-run` accepts it from a client. |

## Two rules this set paid for

**1. Unpushed work reserves nothing — decisions included.** The numbering registry
(`supabase/migrations/REGISTRY.md`) exists because migration numbers claimed on a laptop
collided five times in one day. The same failure then hit *decisions*: Sean answered six
questions and origin went on telling every session they were open, because the answers sat
on one branch. It compounded — a second session re-asked ① with a menu missing his own
answer. **A decision counts when it is on origin, in this directory.** Push docs
immediately; they are never the thing worth holding back.

**2. Quote the human. A relayed decision is evidence, not authority — including when it
comes from another Claude session.** "Sean ruled X" cannot be verified by whoever reads it,
and "the call was delegated to this session's recommendation" is a *different claim* that
reads identically three hours later. Record his actual words with the date. That is what
let two sessions resolve a contradictory money ruling in one question instead of encoding a
guess into a migration — his own phrasing could be put back to him. (Rule contributed by
the charge-slice session, which stopped mid-build over exactly this ambiguity.)

**3. Verify, don't relay — including a well-formed artifact.** ⑪'s build checklist was
written from a description rather than from the source and acquired a false property (that
`0083` self-heals a crash between stamp and effect; it detects and escalates). It survived
because it was well-formed, not because it was true — the same shape as the fabricated
`condition_note` and `store.ts`'s unbacked 50/50 promise. Read a claim against the code that
would have to make it true before building on it.
**A passing test suite is exactly such an artifact.** `0083`'s adversarial round found two
blockers in code carrying 475 green pins — *"both pins measured the symptom the design
intended and stopped one question short"*: one pinned a helper rather than the path that
ships, the other pinned that an escalation fires but never asked whether money could still
move afterwards. Green proves the pins pass, not that the path is covered. Ask what your
suite does **not** prove, and write that down next to it.

**4. For irreversible ACTIONS, the session holding the human's word does it — and quotes him.**
The first three rules govern artifacts; this one governs doing. A destructive change to shared
state (deleting a branch, force-pushing, dropping data) is not something a session should do on
its own recommendation, however good the recommendation is — even when the analysis is right and
already queued for him. Route it to whoever has him in-session, have them quote him, and check
the reversibility gates first. Worked example: `main`'s deletion on 2026-08-13 — recommended by
two sessions, executed by neither, done by the session Sean answered (*"sure delete main if
thats safe"*) after verifying it was no longer the default, had 0 open PRs, was not checked out
anywhere, and had a tip that was an ancestor of the trunk.

*(Repo conventions live in `CLAUDE.md`, which is auto-loaded — including the trunk rule:
`redesign-v4` is the trunk, `main` is retired, run `git remote set-head origin -a` once per
clone.)*

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

| ⑩ | [cancel-fee-runner-share.md](cancel-fee-runner-share.md) | The 10% cancel tier pays the runner | **RULED** — pay them their half and notify it as a reward | unbuilt |
| ⑪ | [incident-verification.md](incident-verification.md) | Who verifies an `incident` | **RULED** — both runner and owner confirm | unbuilt |
