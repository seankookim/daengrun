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

## Follow-up round — answered 2026-08-25 13:39-13:41 KST (read at version 1787632885-ad0c)

| # | Question | His answer (verbatim label) | His comment (verbatim) | Time (UTC) |
|---|---|---|---|---|
| F1 | Confirm: remove the dangerous-breed rule completely? (card carried the legal-review context in plain words: statutory duties on five breeds, the review's "one genuine build gap", custody-to-a-stranger) | "Remove it completely" | — | 04:39:43 |
| F2 | When an owner runs their own dog: do they pay anything? | "Stays free" | "state 무료로 크루 참가" | 04:41:25 |

Dispositions (recording session — NOT his words):

F1. **맹견 gate removal: CONFIRMED, informed.** The hold lifts. Execution is a real slice —
the deployed 0119 objects (enum columns, gate function, four triggers, breed screen, cron
belt), suite 154, the fixture edits it spread across suites, and the client wiring (dog.tsx
declaration, delegate/session refusal states) come out together under the full adversarial
cycle, with the same care in REMOVAL that the gate got going in (a half-removed gate is worse
than either state). The removal is flagged in the pending counsel email as the card promised
— the brief gains one line before Sean sends it. Claimed by the spec-v2 session; client half
coordinates with ui6. Until the slice lands, the DEPLOYED gate keeps working — removal is a
deliberate landing+deploy, not a drift.

F2. **Mode A participation: FREE, ruled — and the copy is his**: surfaces state 「무료로 크루
참가」. The addendum's §4 closes (no fee machinery, ever, unless he reopens it); A6's cancel
copy stays fee-less.

## Third round — 2026-08-25 14:19 KST

| # | Question | His answer | His comment (verbatim) | Time (UTC) |
|---|---|---|---|---|
| T1 | Runner base-move cooldown N | "7 days" | "wait, this is fine. no need to over worry about such abuse." | 05:19:37 |

Disposition: **N = 7 days**, and the comment sets the POSTURE — the lightest protection, and
an instruction not to over-engineer this abuse class. The 0123 fix round ships with the 7-day
cooldown + the honest wording; the heavier counters stay only insofar as they are already
built and cheap. Unblocks the 0123 deploy (ui6). Clock-flip, revoke-edge, and route-km cards
remain open on the console; the two soft confirms default to as-built if never tapped.

## Fourth round — 2026-08-25 14:20-14:23 KST

| # | Question | His answer (verbatim label) | Time (UTC) |
|---|---|---|---|
| Q1 | Turn on the late-booking system? | "Turn it on (with the pre-flight)" | 05:20:16 |
| Q2 | Host-revoke → cancel pricing edge | "Free is right (as built)" | 05:21:30 |
| Q3 | Route-name lengths | "Corrected numbers are right (live now)" | 05:22:55 |

Dispositions: Q1 = **CRIT-1 RESOLVED — the clock flip is ordered**, on the card's own terms:
pre-flight first (live candidate counts for all three sweep arms, manual drain of any backlog,
off-peak timing if the backlog is non-trivial), then `ops_flags.late_protocol_live_since` set,
then verified by readback. The R17 flip-activation package's preflight arm is now due; per its
own verdict, the bounded-batching migration builds only if the preflight finds a real batch
(≥~10 candidates). Q2 = the 0124 present-tense reading stands (L5 pin is the law). Q3 = route
names closed as option A.

## Fifth round — relayed via ui6-a5 (lab critique channel), recorded here as pointer only

Sean's palette + type ruling (verbatim words recorded in DESIGN.md by ui6-a5, the 정본):
the pale lilac ground retires PRODUCT-WIDE ("i like the accent color, not the pale color;
product wide and mock wide" — #6C5CE7 survives as accent only), and the v0 font (IBM Plex
Sans KR) retires from mocks/product per his lab critique. ui6-a5 owns the lab remake and the
follow-up product-wide theme sweep; the club-v2 lab files transferred to their claim. No
session introduces new pale-lilac surfaces from this point.

## Sixth round — via ui6-a5 (round-4 lab feedback channel), Sean verbatim

> "i like the pin board 1, but what does the different states mean? aren't they all supposed
> to be in near sync? same start time, maybe different arrival states as some can be doing
> pick up or arrival, but also same end or maybe some are returning or finished completely.
> also, clicking on each names should go to their profiles with their posts (like instagram).
> for the host console, why is the host accepting or rejecting an owner? they shuold be able
> to sign up and runners too without the host's permission. pair reallocation functionality
> for the host? is that really necessary, i dont think so. the club will be running in a pack
> so end times would probably be all the same or similar."

Dispositions (recording session — NOT his words):
1. **Board pick = ①** (pin board) — ui6 executes visually.
2. **PACK MODEL RULED**: the session runs as ONE pack — shared start, shared (or similar)
   end; per-dog variation exists only at the EDGES (pickup/arrival before the run;
   return/finish after). The spec's per-pairing mid-run independence retires; the P-ladder's
   custody edges survive per-pairing. Spec amendment ordered.
3. **NO HOST APPROVAL — RULED, reverses spec §4.2**: owners sign up (and pay) and runners
   commit WITHOUT the host's permission. `session_approve_dog`'s admission role, the P1
   hold-to-pay step, and the console admission queue RETIRE (deprecate-by-refusal per house
   doctrine). The spec had proposed admission survives; his question overrules it.
4. **NO HOST PAIR-REALLOCATION — reverses his own earlier tap, and I am NOT treating that as
   settled without him seeing it.** The earlier tap is **card 10, "Host recovery pen inside
   T−2h" → "Give the host the 2-hour backstop", at 04:26:44Z** — not "14:26", and not the
   base-cooldown round; both were mine and both were wrong, corrected here rather than
   quietly. The subject matter DOES match: card 10's recovery pen is §6.6's 재배정, so this
   afternoon's "pair reallocation functionality for the host? is that really necessary, i
   dont think so" is about the same object he approved this morning.
   ⚠ **But he phrased it as a question with an opinion, not as an instruction**, and it
   reverses something he had explicitly tapped Approve on hours earlier. Two readings are
   live: (a) he has changed his mind and the pen retires, (b) he is asking why it exists and
   would keep it if told. The recording session's judgement is (a) — "i dont think so" is a
   view, not a request for a briefing — **but a reversal of his own explicit approval is
   exactly the thing that must not be executed on an inference.** So: the spec is re-scoped
   as (a), no implementation slice may build against it, and the question goes to the console
   for him to confirm in one tap. If he confirms, this becomes a settled ruling and card 10
   is superseded; if not, §6.6 stands unchanged and only this note is discarded.
5. **Instagram-like profiles with posts, reachable by tapping names** — the first words of
   his deferred community/account commentary; a NEW spec lane, not a club-v2 bolt-on.
   Parked as its own future spec with this verbatim as the seed.
Visual-side rulings (ui6's lane, recorded in DESIGN.md): pure white grounds · clickable-row
affordance mandatory · working Korean floor 15 · stamp style retires.
