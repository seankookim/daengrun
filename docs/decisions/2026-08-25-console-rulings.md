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

## Seventh round — the bailed-runner question, answered while reading the lab (via ui6-a5)

> "what do you mean runner left? how can that happen? left before the start of the session?
> then someone else should carry it over yes."

**RULED, conditionally:** a runner leaving BEFORE the session starts → **someone else carries
the dog over.** That is future #1 of the three on the console. Note his verb: *carry it over* —
a TRANSFER to a named runner, not the pack informally absorbing a dogless dog. Who carries it
decides what that runner earns, so the verb is load-bearing and the money is not yet derivable.

**His challenge deserves the factual answer, and it vindicates him** (measured at source, not
reasoned):
- `session_runner_withdraw` (0043:163ff) **already refuses** if that runner holds any booking in
  `confirmed`/`picked_up`/`active` — `raise exception 'reassign_dogs_first'`. So a runner
  **cannot** silently abandon a confirmed dog today. His instinct that the scenario is ill-formed
  is correct for the case that matters.
- A withdrawal is therefore only possible when the dogs have ALREADY been moved off that runner —
  and the sole mechanism for moving them is `session_assignment_revoke` (0047:230), which is
  **HOST-ONLY** (`if s.host_profile_id <> auth.uid() then raise 'not_host'`).
- When a withdrawal does succeed, capacity re-derives and EXCESS delegated dogs are pushed back
  to `approval = 'pending'` with full refunds (0043:441-450, 「러너 이탈로 위탁 정원이 줄었어요」).

⚠ **THE TRAP THIS EXPOSES, and it is the strongest argument yet against retiring 재배정 naively:**
if the host's revoke retires, `reassign_dogs_first` becomes **unsatisfiable** — no actor can move
a confirmed dog off a runner, so a runner who holds one can NEVER withdraw. Retiring the host
button without building the "someone else carries it over" transfer does not simplify the flow;
it traps runners in commitments they cannot exit. His ruling and the retirement are therefore ONE
piece of work, not two: the transfer mechanism must exist before, or in the same slice as, the
host button's removal.
⚠ And the excess-dogs path pushes rows to `approval='pending'` — a queue that ruling #3 abolishes.
Same collision as §16's finding #5 (stranded zombies), reached from a different direction.

**Still OPEN, not inferred** — both routed back to him rather than guessed:
- **Mid-run departure**: his question implies he may consider it impossible or out of scope. The
  server does treat it as possible (`picked_up`/`active` are in the refusal list precisely because
  such rows exist). Needs his word.
- **What the carrying runner earns** for a second dog. No money can be drawn from §10.2 until
  this is answered; the lab's withdrawn 청구/환불 pair stays withdrawn.

## Eighth round — the bailed-runner question, SETTLED on the console 2026-08-25T09:03:00Z

Card `host-realloc-confirm`, answered by comment rather than button. Verbatim:

> "keep host reassignment functionality when such cases happen for that pair."

**RULED: the host's pair reassignment STAYS.** His "for that pair" is the same object he
questioned in the sixth round ("pair reallocation functionality for the host? is that really
necessary, i dont think so"), so this is his third and final position on it, and the latest.

**Sequence, recorded because the shape is the lesson** — 04:26:44Z approve ("Give the host the
2-hour backstop") → afternoon doubt ("i dont think so") → 09:03:00Z **keep**. Two reversals on
one feature in one day. The sixth-round record downgraded the retirement to PROVISIONAL rather
than executing it, and put the question back to him with the costs; that hold is what made this
answer cheap instead of a rebuild. **A ruling that reverses the human's own explicit approval is
the exact case where you stop and ask.**

Consequences, all reversions of provisional work — none of it was built, which was the point:
1. **Spec v2 §6.6 STANDS.** Its `[AMENDED · §16.n]` retirement marker reverts; §6.6-orig becomes
   §6.6 again, and §14.10's CONTESTED mark clears back to SETTLED.
2. **The trap dissolves.** `session_runner_withdraw`'s `reassign_dogs_first` guard (0043) stays
   satisfiable, because `session_assignment_revoke` (0047:230, host-only) survives as the actor
   that moves a confirmed dog. A runner can still exit a commitment.
3. **159's L5 pin stays reachable** — the accept→host-revoke→near-cancel FREE scenario he
   confirmed at 05:21:30Z keeps a live flow behind it. No pin rescoping, no fixture migration.
4. **The seventh-round "someone else should carry it over" is now MECHANISM, not gap**: the
   carrying-over IS the host's reassignment. His two answers agree — the earlier one said what
   should happen to the dog, this one says who makes it happen.
5. **The settlement fixture's UNPAIRED arm is live again.** The lab's withdrawn 청구/환불 pair was
   withdrawn on a "pack absorbs it" premise nobody ruled; the ruled path is reassignment. Amounts
   still require the open leg-pay answer before anything is drawn.

⚠ STILL OPEN, untouched by this: mid-run departure (his "how can that happen?" implies out of
scope but he has not said so), and what a runner earns for a second dog / a skipped leg.

## Ninth round — console, 2026-08-25T09:03-09:05Z. Four answers, one of them exposing MY error.

| Card | His answer (verbatim) | Time |
|---|---|---|
| `host-realloc-confirm` | "keep host reassignment functionality when such cases happen for that pair. **if no one can, the host can take care.**" | 09:03:48 |
| `host-remove-anyone` | **"Host can remove someone from one walk"** | 09:04:13 |
| `unpaid-slot` | **"Hold the spot for 20 minutes"** + "make the payment for after the run finished no?" | 09:05:05 |
| `pickup-radius` | "answered in chat" (he cut the custom-address option entirely) | 09:05:19 |

**1. Host reassignment STAYS, and gains a LAST RESORT that is new: 「if no one can, the host can
take care.」** The host personally takes the dog when no runner can be found. That is a new arm —
the host becomes the fallback runner, not merely the matcher. It has consequences nobody has
priced: is the host paid as a runner for that walk? Does host+runner in one person break any
party gate? Do not build it until those are answered.

**2. Host may remove someone from ONE walk, not from the club.** The narrowest of the three
options. So: `session`-scoped removal, no club-level ban, no blocklist. This restores an
exclusion mechanism without giving a host power over someone's membership.

**3. ⚠ MY CARD WAS WRONG, and his question is what exposed it.** The `unpaid-slot` card said
「signing up and paying are two steps, with a 20-minute window between them」. **Payment is not in
that window at all.** Measured at source afterwards:
- `0080:11-14`, verbatim: 「booking is free → matching is free → the run happens → `settle_run_tx`
  commits FIRST (the runner is paid) → and only then does the owner's card get charged」.
- The confirm step requires a **registered card**, never a charge — `0081:41`'s own comment:
  「컷오버 이후엔 카드 없이 확정할 수 없다 — 러닝 뒤에 청구할 수단이 없는 자리를 잡는 것이므로」.
- The 20-minute hold is a **CAPACITY reservation**, not a payment window (`0081:148-201`).

So **his 「make the payment for after the run finished no?」 is already exactly how it works**, and
he was reasoning correctly from a false premise I gave him. His "hold the spot" answer stands and
is unaffected — the hold is real, it just holds a slot rather than a payment.
**The lesson is mine**: I wrote a decision card describing a shipped mechanism from memory instead
of reading it, and the founder's confusion was the only thing that caught it. A card is a claim
about the system; it needs the same verification as a status line.

### Ninth round, addendum — the ruling and the shipped mechanism DISAGREE (measured)

Chasing a lab's consequence line turned up a gap between what Sean ruled and what
`session_assignment_revoke` (0047, the host's only reassignment tool) actually does. Both
verified at source:

1. **It REFUSES after handoff.** `if found then raise exception 'already_handed_off'` — the guard
   fires when either `owner_confirmed_handoff_at` or `runner_confirmed_handoff_at` is set. So the
   host can reassign only BEFORE custody transfers. This FITS the scenario he answered ("left
   before the start of the session") and is a real limit on any mid-run story.
2. 🔴 **It does not hand the dog to a runner the host CHOOSES — it returns the booking to
   `matching`** (`update bookings set runner_id = null, status = 'matching'`, nulling both handoff
   stamps). The host un-assigns; the pool re-fills. **His ruling implies the host picks** —
   「keep host reassignment functionality… **if no one can, the host can take care**」 only makes
   sense if the host is looking at candidates and can see that none exist.
3. 🔴 **「if no one can, the host can take care」 has NO mechanism today.** Nothing expresses the
   host becoming the runner for that pair. It also opens an unpriced money question — is the host
   paid as a runner for that walk, on top of the host fee? — and a party-gate question, since host
   and runner would be one person on the same booking.

**Disposition: the model owes the ruling, not the other way round.** His words are the authority
and 0047 predates them. Do NOT quietly reinterpret the ruling to match the shipped function —
that is the failure of describing the world from the code. The slice that implements this owes:
a host-chooses path (or an explicit decision that the pool re-fill IS the answer, put back to
him), the last-resort host-as-runner arm, and its money question answered before either is built.

⚠ Note for the lab: `0045:242` (runner→runner `pending_transfer`) nulls the RETURN stamp; `0047`
nulls the HANDOFF stamps. Two different mechanisms, easy to cite for one another.

### Ninth round, final answer — `leg-pay` @ 09:05:51Z: **"Same pay either way"**

**RULED: a runner earns the same whether or not a leg is skipped.** On-site pickup (owner brings
the dog to the start) and on-site return (owner collects at the finish) pay exactly what the
home-pickup and carry-home variants pay. No per-leg differential, no new money object, no
migration. The simplest possible answer, and it removes a whole class of future edge cases —
there is no "which legs did this booking actually have" arithmetic to get wrong later.

**Every console question is now answered; the board is empty.** Also worth noting: the
"what does a runner earn for a taken-over pair" question **dissolved rather than being answered**.
It only existed under the pack-absorbs premise. With reassignment ruled, `session_assignment_revoke`
returns the booking to `matching` and whoever accepts is simply that booking's runner, paid
normally. The bailing runner gets nothing, having done nothing. No second-dog arithmetic exists.

⚠ Still unpriced, and NOT covered by this ruling — do not read it as settled: his last-resort arm
「if no one can, the host can take care」. That is the host acting AS the runner, not a runner
skipping a leg. Whether the host is paid runner-pay on top of the host fee is untouched by
"same pay either way", and the addendum above still stands.

### Addendum 2 — the shipped owner copy is NOT over-promising (checked, because it was raised)

`0047:246` notifies the owner: 「담당 재배정 중」 / 「담당 러너를 다시 배정하고 있어요 — 자리는
유지돼요」. Raised as possibly over-promising a host hand-pick. **It does not.** Read against what
the function actually does:
- 「다시 배정하고 있어요」 — the booking goes to `matching` and is re-filled. That IS reassignment;
  the sentence names the outcome and is silent on WHO chooses, which is exactly right while the
  agent is unruled.
- 「자리는 유지돼요」 — TRUE: the `session_dogs` row and its capacity slot survive; only
  `bookings.runner_id` is nulled and the status moves. The owner does not lose their place.

So the string is **agent-neutral and accurate under either reading** of Sean's ruling, and needs
no change whichever way the hand-pick question lands. Recording the check rather than the worry,
because "this copy might be lying" is exactly the claim that should not sit unverified in a note.

## Address-window defect — VERIFIED at source, and it is a PRECONDITION of the sign-up slice

Raised by the UI session; **read rather than agreed with**, per the endorsement law. All three
claims hold:

1. **Marketplace is fine, club is not — and they cannot be reasoned about together.**
   `confirm_return_tx` refuses club bookings outright (`0083:383`, `club_out_of_scope`) and claims
   `completed` only FROM `active` (`0083:719-720`, 「active에서만 completed로」). So a marketplace
   booking stays `active` through its whole return window and `booking_pickup_address`'s
   `active` arm (`0065:50-53`) covers it.
2. **The club inverts that order DELIBERATELY.** `0045:55-60`: reaching `completed` sets
   `custody_phase='return_pending'` and **keeps custody with the runner** — the comment is
   「[R2 핵심] 정산 ≠ 반환: 국면만 반환 대기, 커스터디는 러너 유지」. Both club return RPCs then
   REQUIRE that phase (`0045:79`, `0045:137`, `not_return_pending`). **So the club's entire return
   window lies after `completed`, and therefore entirely outside the address gate — by
   construction, not by oversight.** The separation that makes club custody honest (money settles
   while the dog is still out) is precisely what puts the return past the window.
3. **The tempting one-liner is a privacy regression.** Adding `completed` to `0065`'s status list
   re-opens the pickup address for **every finished booking, forever**.

**DECIDED (this session, mine to call): the custody-aware arm, not a separate RPC and not a
status-list nudge.** `booking_pickup_address` gains one arm admitting the assigned runner while
THAT pairing's `session_dogs.custody_phase = 'return_pending'`. Reasons: the gate becomes a live
custody fact rather than a terminal status; it is exactly as wide as the window where the dog is
in hand and needs a destination; and **it self-closes** when the return seals (phase → `resolved`).
A separate club-return RPC would duplicate the party gates — a second copy of an admission rule is
how the two copies drift.

🔴 **This is a PRECONDITION of the sign-up slice, not a follow-up.** The moment sign-up writes an
address, a home-return pairing has a runner who cannot see where to bring the dog, and the failure
surfaces at the worst possible moment: dog in hand, end of the run. Ship the arm first.


### Citation correction — the live `session_assignment_revoke` is `0057`, not `0047`

Everything above that cites `0047:230` / `0047:221` for the host revoke is pointing at a
SUPERSEDED definition. Measured: the function is defined twice — `0047_assignment_loop.sql` and
then `0057_security_hardening.sql:158`, and the later `create or replace` is what runs. The
behaviour I described is unchanged (`0057:171-173` raises `already_handed_off`; `0057:177-179`
writes `runner_id = null, status = 'matching'` and nulls both handoff stamps), so **no conclusion
moves** — but the line numbers were wrong in this file and in what I relayed to the UI session,
and a reader following them lands on dead text. Found by the agent executing the §6.6 reversion,
which read the file instead of inheriting my citation. **A correct claim with a stale citation is
still a defect**: the next person verifies the pointer, not the sentence.

## Phone in the 현장 반환 arm — NOT unruled. Ruled, built, and already refused once.

Raised by a UI session as "NEW AND UNRULED — I'd fabricate a field if I drew it naively". Read at
source; the framing inverts. Three measured facts:

1. **The policy exists and is enforced.** `_club_phone_visible` (`0049:165-192`) is 전화 규칙 B:
   호스트↔전원 · **보호자↔(자기 개의) 수락 러너, 양방향** · 그 외 호스트 경유(비공개). Its lifetime
   gate is session `open`/`full` **OR unresolved custody** (`custody_phase <> 'resolved'` and
   `service_state is distinct from 'ended'`) — so the 현장 반환 moment is inside the rule already.
   Reveals are audited: `club_phone_access_log` (`0049:156`), written at `0049:236` / `0053:435`.
2. **The data is deliberately absent.** `api.ts:3126-3127`: 「⚠ 연락처는 묻지 않는다.
   profiles.phone 은 전원 NULL 이고 읽는 화면이 없다 — 받아두기만 하는 필드를 묻는 건 넛지가
   아니라 수집이고, §12 가 전화 버튼을 거부한 것과 같은 이유다」.
3. **§12 already refused a phone button**, and not on entitlement grounds — on the grounds that
   collecting a field nobody reads is collection rather than a nudge.

**Disposition: the affordance is NOT drawn, and the question put to Sean is the real one.** It is
not 「is a runner entitled to the owner's number」 — the rule already says yes, for their own dog,
during custody. It is **「do we start collecting phone numbers at all」**, which is a privacy
decision carrying a prior NO. Framing it as a UI gap would have smuggled a reversal of §12 past
him inside a screen.

Until he moves it, the arm uses the shipped channel: `club_chat_messages` (`0008`, realtime
publication added at `0049:150`). No empty state, no owed source, no fabricated field.

## Tenth round — phone collection RULED (round-6 plan, his verbatim, trunk)

> "i think we should have the owner and any new person insert phone number on onboarding for
> safety and contact purposes"

**RULED: collect a phone number at onboarding.** Verified at source (`round6:119`).

**This is NOT a reversal of §12, and the spec must say so** — the relaying session's reading is
right and I checked it: §12 refused a phone BUTTON because 「받아두기만 하는 필드를 묻는 건 넛지가
아니라 수집이고」 — asking for a field **nobody reads** is collection, not a nudge. That refusal
was **conditional on the absence of a reader**. He now names two purposes (safety, contact) and
the 현장 반환 arm is a third. **The condition is satisfied, not overridden.** Written this way
deliberately: a future reader must not find "founder overruled a privacy call" where the record
should read "the field acquired the purpose it lacked".

**The expensive half is already built.** `_club_phone_visible` (`0049:165-192`) already encodes
who-may-see-whose (host↔everyone · owner↔their own dog's accepted runner, both directions ·
otherwise via host), gated by session-live OR unresolved-custody, with reveals audited into
`club_phone_access_log` (`0049:156`, written `0049:236` / `0053:435`). What is missing is only the
collection point and the render.

### What that slice OWES — three riders, two of them measured precedent

1. 🔴 **`delete_my_account_tx` must learn the column, and this class has bitten TWICE already.**
   `0115`'s redaction is a **named-column list**, so a new column survives account deletion
   silently: `0122:113` records it for `dong` (「redacts lat/lng but never learned this column」)
   and `0123:299` for the runner base (「SURVIVING `delete_my_account_tx` because 0115's redaction
   list is a named-column…」). A phone number surviving a deletion request is worse than either.
   **Third occurrence — the slice adds the line, and it is the first thing its review checks.**
2. 🔴 **The 개인정보처리방침 text is SEAN-ONLY.** `docs/legal/privacy-policy.md` exists and must
   state item / purpose / retention / recipient, and a runner seeing an owner's number is a
   **third-party disclosure**. CLAUDE.md puts "changing what users are told" on his list.
   **No session drafts this.** Routed to him as its own card, separate from the build.
3. **Required-vs-optional at signup is a product call, not an implementation detail.** Required is
   a funnel cost at 11 users; optional means the 현장 arm keeps an empty state either way. His.

⚠ **The field is empty for every EXISTING user even after collection ships** — so the return arm's
empty state is not a transitional nicety, it is the permanent path for the current cohort. The
live-map session's redirect onto `club_chat_messages` stays correct regardless.

### Correction to rider ① — "bitten twice" was WRONG, and the truth teaches a different fix

I wrote that the deletion-redaction class had bitten twice (`0122` and `0123`). **It bit ONCE and
was HEADED OFF once.** `0123:297-303` verbatim: 「🔴 The 0122 BLOCKER-1 class, **headed off rather
than repeated**… so this file does not wait to be told.」 `0123` wired `_runner_base_tombstone()`
from day one because `0122`'s review had just measured the failure.

The distinction is not bookkeeping. **"Bitten twice" argues the redaction allowlist is structurally
broken and should be replaced. "Bitten once, then prevented by a file that read the previous
review" says the practice WORKS when the lesson is carried forward** — a cheaper and more accurate
conclusion, and it puts the burden where it belongs: on whoever adds a column reading the last
slice that added one. Recorded so this file does not teach a pessimism the evidence refutes.

🔵 **And `0123` supplies the MECHANISM the phone slice should copy — do not edit `0115`'s list.**
Its stated reasoning (`0123:304-312`): `delete_my_account_tx` is 445 lines of money-and-consent
decisions, and re-creating it to add column names is **exactly the silent-revert trap `0086 §B`
records** — a faithful-looking copy that applies later and undoes the newer definition while the
harness stays green. Instead the cascade rides the **tombstone**: `profiles.deleted_at` going
non-null is `0115 §B`'s own definition of a deleted account, it is set inside that transaction, and
it is client-unreachable. The phone slice adds a tombstone-keyed clear, not a line in an allowlist.

Operationally nothing changes — deletion is still the first thing that slice's review checks — but
the slice now has a proven shape instead of a warning.

## Two dependencies found by the live-map lab — verified at source, one of them reshapes a feature

### D2 — the host-verify ask has NO SERVER WRITER. Mine to spec.

Sean asked for host verification against the pair list (「perhaps the list?」). Measured:
**`0030:254` is the ONLY statement in the entire schema that writes `session_people.attendance`**
(`update session_people set attendance = 'checked_in', checked_in_at = now()`), and it is
self-service — keyed on `profile_id = auth.uid()`. Every other hit in the tree is a READER
(`0031:50,54,71,74,116,126`).

**So check-in today is strictly first-person: the host cannot mark anyone present.** His verify
affordance needs a new writer with a party gate that admits the host (and backup host) without
admitting every member. Scoped to me; it rides the pair-list slice.

### D3 — the host live map has NO FEED, and the "cheap" option is not cheap. **SEAN'S CALL.**

Positions publish per BOOKING on `run2-<booking_id>` (`geo.ts:366-375`), private and policy-bound
by `0104`. There is **no session-level topic and no position column anywhere in the schema**
(both grepped). A host map renders blank.

⚠ **Correction to the option list I was handed:** "the host subscribes to N per-booking channels"
was offered as cheap-but-a-scaling-question. It is not cheap — **`0104:64-65` binds the topic to
the BOOKING PARTY**: read is `p_uid = b.owner_id or p_uid = b.runner_id`, write is
`p_uid = b.runner_id`. **The host is not in that policy and would be refused.** So all three
options require a new server surface:
1. widen `0104`'s policy to admit the session host — a change to a **security policy** that exists
   specifically because `0103`'s authorization was walkable (`0104:1`), plus N subscriptions;
2. introduce a session-level topic — a new policy surface with its own party gate;
3. land positions in a column and let the host poll — **a location at rest**, with a retention
   question, which is the entire argument `0123` had about the runner base.

**Routed to Sean, not decided here.** Option 3 changes what the product stores about where people
are; options 1 and 2 change who may watch a live position. Both are "what users are told / what we
keep about them" decisions, which CLAUDE.md puts on his desk. The lab states the gap honestly
rather than faking a feed — correct call, and the feature is not buildable until he answers.

### Smaller: `return_arrived_at` does not exist (zero hits)

The 도착 tap in the 집 반환 arm is currently a screen transition, not a record. If it must be a
record — and the two-sided ritual arguably wants one — that is a column, and it belongs to the
same slice as `return_mode` rather than being bolted on later.

## Eleventh round — the two phone questions, answered 2026-08-26T01:46Z (console)

| Card | His answer | Time (UTC) |
|---|---|---|
| `phone-policy` | **"Add it to the lawyer email"** | 01:46:38 |
| `phone-required` | **"Required"** | 01:46:47 |

**1. The 개인정보처리방침 text goes to COUNSEL, not to me and not to him.** Cleanest of the three
options: the collection line rides the pending legal email alongside the 맹견-removal line, so a
lawyer writes the wording for a lawyer's document. **Consequence for sequencing, stated plainly:
the phone slice's SHIP gate is now an external dependency** — it waits on counsel's reply, not on
our build queue. The build (collection point, render, tombstone-keyed deletion clear) can proceed;
what cannot proceed is turning collection on for real users before the policy names it.

**2. Phone is REQUIRED at signup.** So the onboarding form gains a required field, and the funnel
cost is accepted deliberately at 11 accounts.

⚠ **"Required" does NOT mean the empty state disappears — it means the opposite is permanent.**
All 11 existing accounts have no number and nothing backfills them. A required field binds only
NEW signups, so for the entire current cohort the 현장 반환 arm falls back to `club_chat_messages`
indefinitely. The empty state is the path for every user who exists today, not a transitional
nicety. Anyone drawing that screen must render it as a real state.

⚠ **Do not let "required" leak into a retro-active gate.** Requiring the field at signup is not a
licence to block an existing user from a session until they supply one — that would be a new
refusal Sean did not rule, applied to people who joined under different terms.
