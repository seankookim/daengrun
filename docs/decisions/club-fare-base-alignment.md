# ④ club_fare — should a club owner pay ₩9,900 base when a marketplace owner pays ₩7,900?

**Status: ✅ RULED BY SEAN 2026-08-13 — KEEP ₩9,900 for clubs (the premium stands) AND
make the club price-invisible too, "although notifying the price once."**

The gap stops being drift and becomes a stated product fact: a club session costs more
than a solo run, disclosed ONCE at the join/consent moment and never again. No `club_fare`
change — 0043, 117 K3/K7 and 50 D5 all stay. Two consequences worth naming: ① the club's
wider margin is exactly what FUNDS host compensation (see `host-incentives.md` ⑦), so the
premium has a purpose now; ② 117 K7's literal arm pins an *intended* price rather than a
fossil. Club price-invisibility is being built — the session screen shows the fare at five
points today (big number, CTA, '승인 시 가격', status line, pay sheet) and collapses to one
disclosure.

⚠ **G1 interaction:** because the charge reads the booking's own frozen `base_fare`, a club
`dog_condition` abort charges **₩9,900**, not 7,900. Flag it in copy or it reads as a bug.

*Original recommendation was B (align to 7,900); Sean ruled A. Recorded so nobody
"corrects" it back to the memo's advice. Analysis preserved below.*
Authored by the charge-slice/club-gates session; folded into this directory 2026-08-13
at consolidation (text preserved verbatim).

**Shipped today, unchanged by the club money-gates slice (0081).** `club_fare(km) = 9,900 +
round(km × 3,000)` (0043:14) is the single price source for every club surface: the ticket
cell, the board, the 승인 알림 ("20분 안에 결제하면 자리가 확정돼요 · N원"), and the booking
`session_pay_delegation` writes. The marketplace owner base has been **₩7,900** since the D2
decoupling (owner 7,900 / runner 9,900); that change swept the TypeScript constants under tsc
pressure and could not reach this SQL function. Consequence, at a 5km route:

| | base | distance | owner pays |
|---|---|---|---|
| marketplace | 7,900 | 15,000 | **22,900** |
| club 위탁 | 9,900 | 15,000 | **24,900** |

**This is not a bug, and specifically not a quote-vs-charge bug.** The booking's decomposition
is internally consistent — `9,900 + (club_fare − 9,900) + 0 = club_fare` — so 0080 §D, which
charges from those frozen columns, bills a completed club run *exactly the quote the owner
saw*. Nothing is mispriced against itself. What differs is the **cross-product** price: the
same dog, the same distance, ₩2,000 more inside a club session. 0081 K7 pins the
decomposition, so whichever way you rule, the parts and the total can no longer drift apart.

**Options**

| # | Rule | 5km owner price | Consequence |
|---|---|---|---|
| A | **Keep 9,900, deliberately** (shipped) | 24,900 | Reframes the gap as a group-logistics premium: a host coordinates, a runner takes 2 dogs, there is a 집결지. Costs nothing to ship. Risk: it is currently a premium nobody ever decided or explained, and the first owner who books both ways will ask. |
| B | **Align to 7,900** — one owner price everywhere | 22,900 | The simplest sentence a product can have ("보호자 요금은 하나"). ₩2,000 per club run off the top line; club runs are the ones with the *most* platform cost (host coordination, capacity, incidents). One-line change to `club_fare` + K7/50 D5's literals. |
| C | **A separate published club price** (e.g. 8,900 base, or per-dog banding) | your call | Makes the premium a stated product fact instead of an artifact — but it needs a surface that explains it, and today no club screen has a "why is this more" line. |

**Recommendation: B — align to 7,900, and do it before the cutover, not after.**
Three reasons. ① The gap is not a decision anyone made; it is 0043 fossilising the pre-D2
constant, and shipping an unintended premium into *real* charges is a worse first impression
than the ₩2,000 is worth. ② Club is the acquisition surface (the pilot's growth loop is
sessions, not solo runs) — the wrong direction to be the expensive one. ③ Post-cutover the
change gets harder in a way it is not today: bookings freeze their fare columns at creation,
so after the flip you would have two live prices in the wild for weeks, and every support
conversation would need the history. Before the flip, nothing has been charged, so the
correction is invisible.
If you take A instead, the honest form of A is a one-line disclosure on the club payment sheet
("클럽 위탁은 기본요금이 달라요") — an undisclosed premium is the version that costs trust.
**Whatever you pick, no code moves until you say so:** 0081 ships the gates and leaves the
formula untouched; the change, when it comes, is `club_fare`'s literal plus the 24,900
literals in `117 K3/K7` and `50 D5`.

**Related, not part of this decision:** club cancel fees are structurally uncollectable
post-cutover (they land in `club_fee_items`, never `bookings.cancel_fee`) — that one is
written up at the end of memo ⑤, and it is a separate ruling from this price.

