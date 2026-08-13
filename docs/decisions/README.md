# Money decision memos — the single index

Eight memos, one directory. Two sessions wrote overlapping sets in parallel;
`docs/decisions-open-money.md` was retired INTO this directory, and Sean's rulings —
which he gave in the charge-slice session and which sat unpushed on one laptop while
this directory said the questions were open — are ported in below from `0fbaa64`.

| # | Memo | Ruling |
|---|---|---|
| — | **[awaiting-sean.md](awaiting-sean.md)** | 📋 **THE RETURN QUEUE** — everything waiting on Sean, in one file rather than in a conversation. Read this first on his return. |
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

**2. Quote the human — and mark where the quote ends. A relayed decision is evidence, not
authority — including when it comes from another Claude session.** "Sean ruled X" cannot be verified by whoever reads it,
and "the call was delegated to this session's recommendation" is a *different claim* that
reads identically three hours later. Record his actual words with the date. That is what
let two sessions resolve a contradictory money ruling in one question instead of encoding a
guess into a migration — his own phrasing could be put back to him.

**The boundary half is the subtler one, and today produced the only case where the artifact was
CORRECT and only its edge was wrong: an inference placed next to a ruling inherits the ruling's
authority.** ⑪'s phone-number requirement was written up beside a ✅ heading, and by the time it
had been relayed twice it was being built as *"show the numbers at all times"*. It was
recoverable purely because the memo said *"the payments session reads the ruling as…"* rather
than asserting it — so the premise stayed checkable, was checked, and Sean narrowed it himself
to *"during those emergency situations."* A paragraph under a ✅ looks ruled. Say which sentence
is his, and let the rest be visibly yours. (Rule contributed by
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
**Corollary — when a question is unanswerable, look for the stronger one that is answerable.**
Asked *"which client build is live?"* (unanswerable: no local EAS/OTA record), the payments
session instead enumerated every `profiles` SELECT in **every commit that ever touched `app/`* *
— five distinct projections, all a strict subset of `0088`'s whitelist. The answer stopped
depending on which build is live: **every build that has ever existed is compatible**, including
a user on a months-old binary. That is the same move as replacing "remember the rule" with "the
tool enforces it" — reshape the question until the answer cannot rot.
**And a commit message that asserts a property is a third such artifact** — one claimed that a
user-facing string was quoted from a migration's own error detail "so the two can't drift", and
nothing checked it. A claim in a commit message is exactly as enforceable as a comment: not at
all. Three artifacts now, all authoritative purely because they are well-formed — **a checklist
that reads well · a suite that is green · a commit message that asserts a property.** None were
vague. Precision without verification is indistinguishable from precision with it.

The repair pattern that came out of it is worth more than the rule: when the same fact lives in
two languages, **do not synchronise the copies — delete the duplication.** Let one side own the
fact and have the other read it at test time and verify against it, in both directions. That
works with existing fakes in place, needs no shared constant and no cross-language import, and
it is what closed ⑩'s three-copy marker string.
⚠ **Its precondition, which is easy to lose:** *delete the duplication* holds only while the
owning side stays the ONLY copy. The moment the reading side caches the value in a constant —
which looks like tidying, and would pass review, because hoisting a repeated string is normally
right — the test passes against the copy and the join is open again. Say so in a comment at the
read; the test cannot defend its own premise.

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

## 🔵 When the founder is away: a stand-in decides, but never in his name
> **Window closed 2026-08-13 — Sean is back; 🟡 items go to him directly.** Kept because the
> rule holds for the next absence, and because ⑫ still carries a 🔵 that must not drift into a
> ✅ now that he is reachable: it is answered when he answers it, not when he is available.

Sean, 2026-08-13, going on break: *"tell others to run autonomous or ask codex in replacement
of me. ill tell u when im back."* So work proceeds, and codex stands in for the judgement calls.
**With one hard line: a codex decision is recorded as CODEX's, never as his.**

- **✅ is reserved. It has meant exactly one thing across all eleven memos — the human's own
  words are on origin — and a codex-sourced decision does not get one AT ALL**, not even an
  attributed one. Not "✅ RULED BY CODEX", not "✅ pending confirmation". A second kind of ✅
  devalues the eleven retroactively, and it fails silently: nobody re-reads a memo to check
  *which sort* of ✅ it carries. (Tightening from the payments session; it is sharper than the
  first version of this rule, which only banned putting Sean's name on it.)
- Status stays **🟡 OPEN** on anything he has not personally ruled, with the stand-in's analysis
  recorded beneath it under its own marker, **🔵 CODEX**.
- The reader must be able to tell at a glance which of these came from the founder and which
  from a stand-in while he was out.

This is rule 2 applied to the instruction itself. *Quote the human* exists because ⑨ was asked
twice and answered differently, and because a relayed decision read as authority. A codex
answer promoted to "RULED BY SEAN" is that same failure with a longer fuse — and unlike the ⑨
version, **nobody would ever catch it**, because the artifact would look exactly like the
eleven real ones. Codex is a good reviewer. It is not the person whose money it is.

Corollary from rule 4: while he is away **nobody holds his word**, so no irreversible action on
shared state — no branch deletions, no force-pushes, no `db push`.

## The status line IS the interface — keep it true

A reader is told to read the status line rather than the body, so **a status line that lags its
own memo is the worst artifact in this set**: it is the one thing everybody trusts without
checking. On 2026-08-13 ⑫'s body carried Sean's ruling in three places while line 3 still read
*"🟡 OPEN — needs Sean's ruling"* — so anyone following the rule concluded he owed an answer he
had already given. Caught by another session reading it, not by anything failing.

A sweep of all thirteen then found a second, quieter instance: two memos said *"Buildable"* long
after the code had shipped. **When a memo changes, change line 3 first** — and when you record a
build, say so there, because "ruled" and "built" are different facts and only one of them tells
a builder what to do next.

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
| ⑫ | [marketplace-incident-exit.md](marketplace-incident-exit.md) | ✅ **RULED IN FULL 2026-08-13.** *"pay the runner but dont let them make new runs until the dog is confirmed by both sides."* The runner is paid; the counterweight is a work gate, not a payment condition — which dissolves the question codex refused rather than answering it. **Build unowned.** |
| ⑬ | [chat-notifications.md](chat-notifications.md) | 🔴 **BUILD ITEM, blocks ⑪ and ⑫.** Runner↔owner chat never reaches a phone — push fires only on `notifications` inserts and nothing writes one when a chat is sent. Every ⑫ ruling is *tell someone something*, and the channel they'd reach for is the one that doesn't ring. |