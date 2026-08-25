# Sean's console rulings — 2026-08-25 afternoon (13:21–13:30 KST)

**Mechanism.** These answers were given by Sean tapping option buttons and writing comments on
the interactive decision console (artifact aad92054, self-publishing page; each answer embeds
into the page's state with a timestamp and the exact button label). The state JSON was read
back at version `1787632222-5f3b`. Button labels and comments below are VERBATIM from that
state; everything outside quotes is the recording session's disposition, marked as such.

| # | Question (console card) | His answer (verbatim label) | His comment (verbatim) | Time (UTC) |
|---|---|---|---|---|
| 1 | Runner reply window for a pick | "2 hours is good" | — | 04:21:15 |
| 2 | Pickup: home-only or also meet-at-start | "Both options" | "on top of both options, the owner can participate themselves and just pay the club fee and not pay for a runner. we need to figure out all the screens and maps and etc for this side as well, full flushed." | 04:22:29 |
| 3 | Host never confirms run-finish | "6-hour auto-confirm" | — | 04:22:49 |
| 4 | Owner distance pref in auto-match | "Skip for now" | — | 04:23:09 |
| 5 | Backup host may confirm finish | "Backup can confirm" | — | 04:23:19 |
| 6 | Dogless companions as crew | "Guests can be crew too" | — | 04:23:36 |
| 7 | Kill criterion for the redesign | "Other — comment" | "why call it off? no need i think" | 04:24:51 |
| 8 | Materiality-reject refund quirk | "Fix it" | — | 04:25:05 |
| 9 | Member board effectively public | "Fine for the pilot" | "always fine; it's like a public dashboard. may extend it to live ranked dashboard in community." | 04:25:53 |
| 10 | Host recovery pen inside T−2h | "Give the host the 2-hour backstop" | "make sure all the host ui and screens include all steps of the flow, think of each possible step and scenario." | 04:26:44 |
| 11 | Cancel-ladder rung order | "Free 24h+ always wins" | — | 04:27:35 |
| 12 | R17 sweep rework (User Challenge) | "Wait (recommended)" | — | 04:28:06 |
| 13 | Runnerless late-cancel fee 10% vs 5% | (no button) | "should be no fee if the owner was not connected; it's our job to connect them." | 04:28:43 |
| 14 | Durable owner-attended protection | "Add the protection" | — | 04:29:04 |
| 15 | 맹견 policy | "Refusal stands" then | "actually nevermind, no need to worry about 맹견, let's accept all breeds. forget about 맹견 all together, it isnt even something i brought up." | 04:30:21 |
| 16 | 동네 피드 mismatch | "Rename the feed" | — | 04:29:32 |

| 17 | Schedule-list 20-row window | "Fix the list" | "keep everything" | 04:31:04 |
| 18 | Parked look-and-feel bundle | (comment only) | "approve on everything." | 04:31:30 |

ALL 18 CARDS ANSWERED (final read at version 1787632291-b0dd, updated 04:31:30Z).

## Dispositions (recording session — NOT his words)

1. **Pick TTL = 2h** → spec v2 §14.1 SETTLED; S3 parameter fixed.
2. **Pickup mode = both** → §14.2 SETTLED. His comment additionally ORDERS: the
   owner-participates side (Mode A, 동반) gets a FULL per-side/per-state delineation — screens,
   maps, every step — same depth as the delegated side. New spec work item (v2 §4.3 treated
   Mode A as copy-plus-board; that is now insufficient by his word). ⚠ His "just pay the club
   fee and not pay for a runner" — today a 동반 owner pays NOTHING (RSVP creates no booking,
   0048:158). Whether he wants a participation fee, and its amount, is a NEW money question —
   follow-up card placed on the console; do not build a Mode A fee until he answers it.
3. **Finish ceiling = 6h auto-confirm** → §14.3 SETTLED; **S5's hard gate is OPEN**. The
   system confirms after 6h from the last runner-finish, host notified; the three §7.6
   mechanical escapes ship regardless.
4. **Mode C owner distance pref: skip** → §14.4 SETTLED.
5. **Backup host may confirm** → §14.5 SETTLED; host fee routes to `host_profile_id`
   regardless of who taps (§7.5.2's rule, unchanged by this answer).
6. **Guests can be crew** → §14.6 SETTLED against the spec's runner-only proposal: any
   dogless RSVP (guest included) may be listed as crew on the board. Standing survives: every
   RSVP holds a `session_people` row → shell `full` → incident standing (0049:14, 0067:68).
   §4.4 rewritten accordingly.
7. **No kill criterion** → §14.7 SETTLED: none. The models' recommendation is rejected; the
   redesign is not conditional. §12's kill paragraph removed.
8. **Refund quirk: fix** → §14.8 SETTLED; rides S4.
9. **Board public: accepted** → §14.9 SETTLED. Future idea parked verbatim: a live ranked
   dashboard in community.
10. **Host recovery backstop: approved** → §14.10 SETTLED — and his comment raises the bar on
    §10.2: the host console delineation must enumerate EVERY step and scenario of the flow.
11. **Rung order: free-24h wins** → §14.11 SETTLED; §5.2's reorder is ruled, 153's ladder
    pins re-target in the slice that implements it.
12. **R17: wait** → the User Challenge resolved in favor of DEFER. The flip-activation
    package (contract report §VERDICT) is the standing pre-flip slice; no migration now.
13. **Runnerless cancel fee = ZERO** → supersedes the 10%-vs-5% question entirely and
    REPRICES the shipped ladder: when no runner ever accepted, cancellation is FREE at any
    time ("it's our job to connect them"). This retires the 10% runnerless arm (and ruling
    B's halving becomes moot for that arm — there is nothing to halve). Marketplace analog
    (the 0117 unaccepted tier) must be checked against the same principle in its slice.
    MONEY CANON updated. Requires its own migration + 153 re-pins; NOT built yet.
14. **Durable owner-attended fact: build it** → the Custody A/B decision closes as B. The
    reassignment-proof "this owner showed up" record lands with S4's predicate work.
15. **맹견 gate: REMOVAL ORDERED — HELD FOR ONE EXPLICIT CONFIRM.** His comment (later than
    his button, explicit "actually nevermind") orders the dangerous-breed gate removed and
    all breeds accepted. HOLD, not execution, because the console card that prompted this
    never told him WHY the gate exists: it was built from the repo's own legal readiness
    review (docs/legal/readiness-review-nonlocation-2026-08-19.md:173-178 — the review's "one
    genuine build gap": Korean law imposes special obligations around the five 맹견 breeds,
    and the platform hands custody to a stranger). Removing a deployed legal-safety gate on
    the strength of a card that omitted its legal context is not informed consent — a
    follow-up card with the plain-words legal context and an explicit remove/keep choice is
    on the console. **Until he confirms there: 0119 stays exactly as deployed; no session
    touches its gate, columns, or client wiring.** If he confirms removal, it is his call to
    make — the fleet executes with the legal review flagged to counsel.
16. **동네 피드: rename** → the feed keeps its everyone-visible policy and its name changes
    to match reality. Client copy job (ui6) — new name TBD by ui6's judgment or one more
    console card if none is obvious.

17. **Schedule list: fix, keep everything** → the owner booking query flips to keep ALL
    bookings visible (no 20-row drop-off of finished runs) — its own small client/server
    slice, blast radius already recorded in e031a31's report.
18. **Looks bundle: approve on everything** → executes as a batch (ui6): coral ground deepens
    to #A63A20 · the running-report variant as recommended · the three route-name lengths
    corrected · the "why did you stop" lab and the profile-nudge lab (① recommended) both
    proceed as picked. Each item's own record governs details.
