# ⑪ Who verifies an `incident` — both sides

**Status: ✅ RULED BY SEAN 2026-08-13 — "incident verified by both runner and owner."**
**Unbuilt.**

## Why this needed a ruling

`incident` is the largest single loss in the money system (−₩8,643 on a 1km stop of a 3km
booking, more on longer runs) and the only outcome nobody disputes — because the owner is not
billed. Every other cell has a natural auditor: an owner who is charged reads the charge. Here
there is none, which is exactly why Sean's original G1 instruction was "nothing for incident,
**but verify incident first to avoid abuse of this feature**."

Two halves of that were already built (0084): `settle-run` refuses a runner-declared `incident`
(it whitelists only the four reasons a client can legitimately send — otherwise, once `incident`
means "the owner pays nothing", declaring it is a self-serve free run), and the waive is
reviewable rather than silent (a review marker on the `payments` row plus its own
`payments_reconciliation` arm). **What was missing was a person.**

## The ruling

**Two-sided verification: both the runner and the owner confirm the incident.** Neither party
alone can establish it — the same shape as `confirm_handoff`, where the transition only fires
when both sides have stamped it, for the same reason: a one-sided claim about a shared event is
not evidence.

## Build notes

- Model it on the two-sided handoff — and prefer **`0083`'s return-handoff machine over
  `0047`'s** (0047 is the original rails; 0083, in build on the run-end-flow branch, ships the
  fuller version of the same shape). What to take from it, with `incident` in place of `return`:
    1. **Two independent party stamps, server-written only — but the two guards are NOT
     symmetric, and writing them symmetrically breaks draft creation.** UPDATE is already
     closed by 0058 §3's deny-all (`0058_security_hardening_2.sql:242`); 0083 adds nothing
     there. INSERT is 0083's own `_guard_booking_insert_cols`, and it is **deliberately a
     blacklist, not a deny-all** — its comment says why: *"owners may INSERT drafts
     (0002:95) — so a client could be born holding a return/handoff confirmation. Blacklist
     rather than deny-all, because a draft legitimately carries most columns."*
  2. One locked primitive that fires only when both stamps are present, never
     re-implemented per call site.
  3. A durable `settlement_ready_at`-style fact plus a recovery sweep that **detects and
     reports** a crash between stamp and effect, escalating to a human at 2h — **it does NOT
     self-heal.** 0083 §0g is explicit that the sweep can "report a sealed-but-unsettled
     booking but cannot settle it": `_settle_sealed_run(p_booking uuid, p_quote jsonb)`
     (line 783) takes the price as an argument, and SQL has none to re-drive with, because
     Sean's G1 ruling made the payout basis depend on `end_reason` and that pricing lives in
     TypeScript. Full self-healing needs `compute_runner_payout(booking, end_reason,
     actual_km)` in SQL, sibling to 0080 §D's `compute_owner_charge` — §0g names it as the
     missing piece.
     **⑪ can likely do better than 0083 here.** If ⑪'s effect is a status change rather than
     a payment, it has no price to re-drive and genuinely can self-heal. Do not inherit this
     limitation by assuming the pattern implies it.
  4. A force path recording actor, eligibility time, reason and evidence immutably.
  5. A 2h escalation so nothing strands.
  6. Idempotence on both stamps, with the concurrent loser returning success after verifying
     the same outcome rather than raising.
  7. **Distinct exception names for distinct facts.** 0083 raises
     `run_frozen_after_settlement` and `run_frozen_after_end` separately (lines 248-265)
     precisely so a client cannot collapse them into one sentence telling a runner the run
     was settled when it wasn't. **Frozen and settled are different facts**; any two-party
     machine inherits this hazard and needs an error vocabulary that keeps them apart.
  ⚠ **Extract the SHAPE; do not copy the functions.** Re-creating an object another slice owns
  is the silent-collision class `supabase/migrations/REGISTRY.md` exists to catch — it reverts
  their work quietly and the harness still passes, because each slice's pins live in its own
  suite. Build your own objects on 0083's pattern and name whose version you built on in the
  file header.
- Until both confirmations exist the waive stays in its pending-review state — which already has
  a reconciliation arm and therefore an operator queue.
- Consider what happens when the two sides disagree: that is 0072's incident-settlement
  territory (`refund_full | settle_measured | pay_full`), and it should route there rather than
  inventing a second adjudication.
- The runner is paid normally throughout — verification governs the OWNER's ₩0, never the
  runner's settlement. Settlement never waits on collection (§0-ter ordering law).
- Pin: a single-sided confirmation does not resolve the waive; both do; the runner's ledger is
  untouched in every branch.

## How to TEST it (0083's adversarial round, 2026-08-13 — read before writing pins)

`0083` was held off the trunk by two blockers found in code carrying **475 green pins**. The
session's own summary: *"Both pins measured the symptom the design intended and stopped one
question short."*

- **F1** pinned the *helper* (`_settle_sealed_run`) rather than the path that ships
  (`settle-run/handler.ts:113` calls `settle_run_tx` directly with the client's `actual_km`
  and `end_reason`). The one direct probe passed numbers that already matched the frozen row,
  so **a mismatch was never attempted anywhere in the suite** — the seal checked whether the
  dog was home, never whether the numbers matched what was frozen.
- **F2** pinned that the 2h escalation *fires* and that no ledger row appeared — never whether
  money could still move afterwards. It cannot: the state's only commercial exit is club-only,
  so a marketplace runner becomes permanently unpayable.

**Therefore, for ⑪ specifically:** pin the **shipping entry point**, not the primitive. And
⑪ is a two-sided gate whose entire value is *refusing* — so a suite that only ever exercises
both parties agreeing proves nothing about the refusal. Attempt the mismatch: one side only,
the wrong party, a stamp after the window, a forged stamp on INSERT, the same side twice.
Then ask F2's question about every terminal state you create: **can money still move out of
it, and by which exit?**

This is `README.md`'s rule 3 in a different medium. A passing suite is a well-formed artifact:
475/0 read as coverage and was 475 pins each stopping one question short of the thing they
appeared to prove.

## Before ⑪ ships — two items for Sean, and one fact to verify first

Both surfaced from the ⑪ / `0088` interaction (announcer + payments sessions, 2026-08-13):

1. **The privacy-policy line must ship BEFORE ⑪ does.** A two-sided incident confirmation means
   a counterparty may see the other party's real phone number, and that needs disclosing. The
   Korean norm we would be departing from is **안심번호** — a masked relay, the pattern Kakao T
   uses. Not following it is defensible for a pilot, but it is a trade-off Sean should confirm
   **knowingly rather than inherit** from a build decision. 🟡 his call, queued.
2. **`profiles.phone` may be null in practice — verify before designing against it.** It is
   `phone text` (nullable), annotated *"PASS 본인인증 후 확정"*, and PASS looks unintegrated, so
   ⑪ could render an empty row where it promises a contact. Note that
   `0062_runner_applications.sql:380` declares `phone text not null` — the real data may live on
   the application rather than the profile. Whoever builds ⑪ confirms which source is
   authoritative before the design assumes one; this is exactly the "verify, don't relay" check,
   and the answer changes the screen.
