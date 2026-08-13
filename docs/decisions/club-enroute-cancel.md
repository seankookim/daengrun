# ⑤ Should a club booking be cancellable once the runner is en route?

**Status: ✅ RULED BY SEAN 2026-08-13 — option A: LEAVE IT.** Club cancels stop at
`confirmed`; past handoff it is a case, which is the club's own designed answer. No
en-route club tier, no new money rule. (The memo had recommended C.)

✅ **Also ruled: the card-less club state points at card registration, and the flow must be
seamless** — the post-cutover refusal becomes a route, not a dead end. Being built with the
price-invisibility pass. Note the asymmetry Sean accepted deliberately: the one surviving
"wall" is an en-route club cancel (rare); the card-less case (common) gets a path.

**Shipped today (2026-08-13, this session).** The marketplace cancel path now REFUSES club
bookings (`cancel_owner`, mirroring the club exclusion `runner_accept` already had). It had
to: a club booking reaches /owner/schedule, and its cancel button was quoting 0066's
marketplace ladder (0 / 50% en-route / 0 ≥24h / 10% <24h) onto a club booking, writing
`bookings.cancel_fee` at a rate the club never agreed to, and leaving the club side blind —
no `club_fee_items`, no host notification, no assignment revocation. Post-cutover that wrong
number becomes a real charge.

**The gap the refusal exposes.** The club's own exit, `session_cancel_delegation`
(0057:190), accepts booking status `matching` and `confirmed` only — past that it raises
`already_handed_off`. The marketplace opened `runner_enroute → cancelled_owner` (your
2026-08-11 call, 50% = runner compensation); that was never extended to club. So an
en-route club booking now has **no owner-initiated cancel at all**. Past handoff the club's
designed answer is a case, not a cancellation — which is coherent, but it is a narrowing,
and you should know it happened.

| # | Rule | Consequence |
|---|---|---|
| A | **Leave it** (shipped) — club cancels stop at `confirmed`; past that it's a case | Coherent with the club's own model. An owner who needs out while the runner is en route has only the case path, which is slower and feels heavier than a cancel. |
| B | Extend the club ladder with an en-route tier mirroring the marketplace 50% | Restores the capability with club-correct bookkeeping (club_fee_items + host notify + revocation). Real work in club SQL, and it commits you to paying club runners the same comp the marketplace pays. |
| C | Route en-route club cancels into the incident flow explicitly (a button, not a dead end) | Cheapest honest middle: no new money rule, but the owner gets a path instead of a wall. |

**Recommendation: C now, B only if it actually comes up.** The capability gap is real but
the volume is probably zero in a Banpo pilot; a dead end is the part worth fixing today.

**Also from the adversarial round, for your awareness:** after the flip a card-less owner
can still book a MARKETPLACE run (create-booking-hold treats "no card" as routing — it sends
them down the widget path) but is refused outright from club sessions and recurring
generation, which are post-pay-only and have no widget fallback. That asymmetry is
defensible and 0081 is accurate about it, but it means the first card-less owner after the
flip experiences the club as broken rather than as "link a card first". If that reads wrong
to you, the fix is a club-side empty state pointing at card registration, not a gate change.

**Related, documented not fixed:** club cancel fees are structurally uncollectable
post-cutover — `session_cancel_delegation` writes only `club_fee_items`, never
`bookings.cancel_fee`, so `mint_cancel_fee_intent` sees zero and the debt derivation's
cancel arm never fires for club. That may be exactly right (0048's mock-era doctrine is
"record, don't charge"), which is why it is a decision: at cutover, club cancel fees either
become real money or stay recorded-only forever.

