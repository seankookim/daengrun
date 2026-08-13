# ⑥ The cutover straddle — a booking confirmed before the flip, charged after it

**Status: ✅ RULED BY SEAN 2026-08-13 — option B.** `payments_live_since` is set to a
FUTURE timestamp past the longest in-flight booking, never to `now()`. Straddlers stay free
by construction.

**The flip procedure in session-handoff §3 ⑦ carries this, with the query that finds the
right timestamp** — a decision that lives only in a memo is one
`update ops_flags set … = now()` away from being undone.


**Not a defect anyone introduced; a consequence of where the two clocks sit.** The
instrument gate asks "does this owner have a card?" at *confirmation*
(0081 §A, `create-booking-hold`, `generate_recurring_bookings`); the charge asks "was
this run after the cutover?" at *run end* (0080 §E, `ended_at < payments_live_since →
mint nothing`). A booking that straddles the flip therefore passes a gate that didn't
require a card, and then gets charged. Executed by the adversarial round: a card-less
owner confirmed a club seat pre-flip, the switch was set, the run settled — and a
`24,900 pending settle_charge` was minted against an owner with zero cards. It dispatches,
fails, and the debt derivation locks the account.

All three booking paths have this window; the club's is the widest, because a session's
`scheduled_at` is unbounded while recurring only reaches 72h ahead. The straddling
bookings are also the one population that never sees the new post-pay sentence, since
their confirmation copy was written pre-flip.

| # | Mitigation | Cost |
|---|---|---|
| A | **Sequence the card-register slice before the flip** (already 0080 §0d ⑦) and flip when few bookings are in flight | Free; relies on the ordering being honoured, and doesn't cover a club session booked weeks out. |
| B | Set `payments_live_since` to a FUTURE timestamp past the longest in-flight booking | Free, one value; makes the boundary explicit instead of "now". Straddlers stay free by construction. |
| C | Charge only bookings whose *creation* was post-flip (add a booking-level marker) | A schema change and a second clock; the most precise, the most machinery. |

**Recommendation: B.** It costs one deliberate value at flip time and turns the straddle
from a class of surprise charges into a decision. A is not sufficient alone for club.


## What the flip waits on (not a decision — the gate list)


The `payments_live_since` cutover is gated on, in order: 사업자등록 → 통신판매업 →
Toss contract **with 자동결제 심사 in the same application** · billing TEST keys + the §4-2
sandbox matrix · the club-delegation money gates (in progress as its own migration) ·
①/② above. Everything shipped is inert until that timestamp is set.
