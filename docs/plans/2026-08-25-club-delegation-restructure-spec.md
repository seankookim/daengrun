# Club delegation restructure — the flow spec Sean ordered

**Provenance.** Sean, 2026-08-24 evening, verbatim in
`docs/decisions/2026-08-24-sean-ui-club-commentary.md`: home pickup by a chosen runner · owner
picks from signed-up runners, runner approves · every step visible on the club public home ·
replaces at-the-scene matching · per-session owner choice (run myself / app-connects / pick from
list) · dogless runners ride unpaid · per-runner finish → host final confirmation → dog returned
home; owner-run dogs release immediately. His directive: *"Straighten this idea out first, every
detail and each scenario and screen and choice everyone needs to make and delineate all flows of
events."* This document is that straightening. **It decides nothing he didn't say** — every point
where the flow needs a call he hasn't made is marked 🔴 in §12.

Status: DRAFT for CEO-lens + blind codex review, then Sean. Nothing here is built.

---

## 1. Actors

| Actor | New capabilities | Loses |
|---|---|---|
| **Owner** | per-session mode choice; picks a runner from the committed list; watches every custody step | nothing — gains the choice at-the-scene matching denied them |
| **Runner (with delegation)** | approves/declines a pick; picks up at the owner's home; runs the club route with the dog; returns the dog home; confirms finish | being assigned a dog at the scene by the host |
| **Runner (dogless companion)** | joins the session run, visible on the board, **paid nothing** (his ruling) | — |
| **Host** | watches the board like everyone; **final confirmation at run end**; session lifecycle (create/cancel/finish) stays theirs | at-the-scene dog assignment (`session_assign_dog`'s current role) |
| **The club public home** | becomes the live board: who runs with whose dog, which dogs wait | — |

## 2. The per-session owner choice — the entry fork

At sign-up-to-session time (today's `session_delegate_dog` moment), the owner chooses ONE of:

- **Mode A — 동반**: "I run with my own dog." Maps to today's `session_rsvp` +
  `custody='owner_handled'`. No money, no matching, no custody transfer. UNCHANGED — this is the
  path 0119 §C deliberately keeps open.
- **Mode B — 지정**: "I pick a runner from the committed list." New. The owner browses runners who
  have `session_runner_commit`ted, sends a pick; the runner approves or declines; on approval the
  pairing is fixed and public.
- **Mode C — 자동**: "the app connects me with a club crew runner." New in mechanism, but it is
  Mode B with the platform choosing — the pick lands on a committed runner (🔴 §12: by what rule),
  and the runner still approves. One state machine serves B and C; only the chooser differs.

An owner may switch modes while unmatched (B→C, C→B, either→A). After a pairing is approved,
leaving it is a cancellation event (§7), not a mode switch.

## 3. Matching lifecycle — replaces at-the-scene assignment

States for a session-dog (extends `session_dogs`, whose custody chain survives):

```
signed_up(A|B|C) ──A──▶ owner_handled (terminal for matching; today's 동반)
   │B: owner_pick(runner) ──▶ pick_pending ──runner approves──▶ paired
   │                              │ runner declines / 48h? lapse ──▶ signed_up(B)
   │C: app_pick(runner)  ──▶ pick_pending (same, chooser=platform)
paired ──owner or runner cancels──▶ signed_up(B|C) + cancellation event (§7 money edges)
```

- **Who may pick:** the owner (B) or the platform (C). Never the host — his restructure removes
  the host from matching entirely (`session_assign_dog` retires; `session_propose_dog` /
  `session_proposal_respond` / `session_reconsider_dog` / `session_review_dog` retire with it).
- **Runner approval is the gate** (his words: "which the runner can approve"). A runner sees the
  dog profile at pick time — which is where 0119's tokens fire for a 맹견/undeclared dog: the PICK
  is refused at creation, not discovered at the door. Gate moves EARLIER in the new flow. ✅
- **Concurrency:** one `pick_pending` per dog at a time; a runner may hold multiple pending picks
  but pairing consumes their capacity (`_club_runner_cap`, 0037:37 — cap semantics unchanged).
- **Visibility:** every state above renders on the club public home (§6).

## 4. Pickup and custody — home pickup replaces scene pickup

His reasoning verbatim: at-the-scene "becomes ambiguous how the dog will be picked up if the
runner is running the club route instead of the owner." The new chain:

1. **Runner travels to the owner's home** (the marketplace's own shape — address exposure follows
   the marketplace rules: gate-code access via the existing `gate_code_access_log` idiom, address
   visible to the paired runner only, from pairing until return).
2. **Handoff at the door** — both-stamp confirmation, the marketplace `confirm_handoff` pattern.
   The club's current `session_checkin` (start-point check-in) STOPS being the custody event for
   delegated dogs; custody transfers at the door. `_club_custody_transition`'s `picked_up` moment
   re-anchors to the door handoff.
3. **Runner + dog travel to the club start point** — a new leg, visible on the board as a state
   ("이동 중"). 🔴 §12: is there a between-legs incident boundary (dog picked up but never arrives
   at start)? The spec proposes: this leg is inside the run's custody (the runner holds the dog),
   and a no-show at start is a host-visible board state, not a new machine.
4. **The session runs** (unchanged run mechanics).
5. **Return leg** — runner takes the dog home; both-stamp return confirmation (the existing
   `session_confirm_return` / marketplace return chain).

**Mode A dogs never enter this chain** — owner holds custody throughout; at run end their
"release" is immediate (his words), which is ALREADY true structurally (owner_handled rows carry
no custody), so Mode A needs copy, not machinery.

## 5. Run end — per-runner finish, then host confirmation

His words: "individual club runners should be prompted to finish the run and the host should do a
final confirmation after which the runner goes back to each owner's home, or if it's the owner,
then there's an immediate release."

```
runner taps finish (per dog) ──▶ finished_pending_host
host final confirmation (once, per session) ──▶ return leg begins per paired dog
                                              └▶ Mode A rows: released immediately at their own finish
```

- Replaces the single-shot `club_finish_session` semantics: finish becomes two-phase. The
  no-show fee arm (0118, both gates) anchors to the same moment it does today — host confirmation
  is the "session actually concluded" event, so `club_finish_session`'s money logic becomes the
  host-confirmation step's logic. **The 0118 time+attendance gates survive unchanged in meaning.**
- 🔴 §12: what if the host never confirms? (The R1-class question — a stalled human step on the
  money path.) Spec proposes the existing recovery idiom: a bounded ceiling after the last
  runner-finish, then `session_host_force_resolve`'s shape (which already exists) auto-confirms
  with an ops note. Needs Sean's nod because it moves money on a timer — but it moves it toward
  *paying runners for completed work*, which the silent-stalemate rule permits (evidence exists:
  the runners' finish stamps).
- **The R screen's fate** (his "Not sure what R in club is doing"): R is today's at-the-scene run
  console. Under the restructure it becomes the per-runner finish surface + return-leg tracker —
  recalibrated, not deleted. ui6 executes once this spec survives review.

## 6. The club public home board — the visibility model

His words: "all this process can be shown in the club public home, who's dog is running with who
and which dogs are waiting to be matched."

Board rows (public to club members): dog (name/photo) · owner (name) · state (waiting / pick
pending / paired-with-RUNNER / 이동 중 / running / returning / home) · dogless companions riding.
**Privacy edges the board must NOT cross:** no addresses ever (the runner alone sees the pickup
address) · no money on the board · 맹견-refused picks render to the OWNER only (a public "this dog
was refused" row would be a disclosure; to everyone else a refused pick is indistinguishable from
a declined one). Extends `club_delegation_board` (exists) — the data shape is close; the states
are new.

## 7. Money edges — where 0118 meets the new flow

- **The fee ladder is mechanism-independent** (anchors on bookings + club_config + event-time):
  free ≥24h · 10% late · 20% post-accept/no-show · 50/50 split. "Post-accept" maps cleanly to
  post-PAIRING (runner approval = acceptance). The ladder's meaning survives; only the accept
  event's producer changes.
- **Slot-based supply comp** (Sean, today): a PAIRED runner holds a slot — owner cancellation
  after pairing owes the supply half exactly as ruled. A `pick_pending` runner holds NOTHING —
  a declined/withdrawn pick moves no money. Clean under the ruling.
- **Dogless companions: paid nothing** (his ruling) — they never enter bookings; board-only rows.
  No ledger writes, no fee exposure. 🔴 §12: do they occupy `_club_runner_cap` capacity? Spec
  proposes NO (they hold no slot; slot-based logic says uncapacitated).
- **Mode C (app-connect)**: the pairing money is identical to Mode B — the chooser is not a money
  actor. No new ledger semantics.
- **Runner-money secrecy** (his ruling, separate slice): club runner surfaces show net-per-run
  only; the server strips `platform_fee`/gross from runner-facing returns. Applies across
  marketplace AND club; the audit found the client reading `platform_fee` off `ledger_items`
  directly (api.ts:1301/2535/2569) — the strip is a column-grant + view change with the 0088
  whole-request-403 hazard, so it and its client half land ATOMICALLY (the 0119 lesson).

## 8. Gate edges — 0119 in the new flow

The custody gate fires at: pick creation (earlier than today — better) · the door handoff stamps ·
any custody-bound transition. The 동반 exemption maps to Mode A untouched. The gate is
mechanism-independent; **zero 0119 changes needed** — but suite 154's G4 fixture drives the
OLD path (`session_delegate_dog`+propose/respond), so when the old functions retire, G4's fixture
moves to the new pick path in the same slice (the suite-updates-in-slice law).

## 9. Screen inventory (client — ui6 executes post-review)

Changed: club home (board states) · session screen (mode fork at sign-up) · delegation screens
(pick list, pick-pending, approval — replaces propose/respond surfaces) · host console (loses
assignment, gains final-confirm) · R screen (per-runner finish + return tracker) · owner session
view (custody step timeline). Unchanged: pass · case · receipt-t (share nudges are a separate
approved item) · chat.

## 10. Impact on built work

- **0118**: fee logic re-anchors from `club_finish_session` to host-confirmation — same predicate,
  new home. Suites 153's P4/P9/P10/P12 fixtures re-target the confirmation event. No ruling moves.
- **0119**: gates untouched; G4 fixture re-targets (above).
- **0116 §D party gates**: `club_delegation_board`/`club_dog_ui_state` grow states, keep gates.
- **Retired**: `session_assign_dog`, `session_propose_dog`, `session_proposal_respond`,
  `session_reconsider_dog`, `session_review_dog` (+ their pins, each re-owned or retired WITH
  a named successor pin, never silently).
- **The DO-NOT-REFACTOR meetup freeze is MARKETPLACE meetup** — club screens are not under it.

## 11. Sequencing

1. Spec survives CEO lens + blind codex + Sean's read (tomorrow).
2. Server slice(s): matching states + board + two-phase finish (one migration, adversarial cycle,
   next free number two-sided at write time).
3. Client slice: the screens (ui6), atomically where column grants move.
4. Runner-money secrecy slice is INDEPENDENT and can go first — it's small and ruled.

## 12. 🔴 Open with Sean (the morning list)

1. **Mode C's chooser rule** — how does the app pick? (nearest? least-loaded? host-tiebreak?)
2. **Pick-pending TTL** — how long may a runner sit on a pick before it lapses?
3. **Host never confirms** — accept the force-resolve ceiling proposed in §5? (It moves money on
   a timer, toward paying completed work — evidence-based, stalemate-rule-compatible.)
4. **Dogless companions and capacity** — confirm they don't consume runner cap (§7).
5. **Between-legs incident boundary** (§4.3) — accept "inside the run's custody"?
6. **His own question answered**: "is there a way to make a case during the run?" —
   `club_incident_open`'s gates are severity/summary/party — 🔵 preliminary reading says a case
   CAN be opened mid-run today; the blind review verifies and the morning brief states it flatly.
7. Deferred by him: community/account commentary — nothing here anticipates it.

---

# GSTACK REVIEW REPORT

**/autoplan run, 2026-08-24 night — CEO phase complete with three voices; Design/Eng phases
deliberately deferred (see Decision Audit Trail #7). Sean away; the two human-only gates (premise
confirmation, user challenges) are QUEUED FOR HIM below, not auto-decided.**

## Voices

| Voice | Form | Headline |
|---|---|---|
| Claude CEO subagent (independent, no prior context) | 15 ranked findings, 5 CRITICAL | "Freeze at document stage. The straightening is done; the building is not what he ordered." |
| Codex CEO voice (gpt-5.6-sol, adversarial) | strategy + marketplace-dynamics + sequencing | "The current sequence does nearly the reverse: architecture first, evidence later." |
| Blind codex spec-vs-code review | still running at report time — folds into the morning brief | — |

## CEO CONSENSUS TABLE

| Dimension | Claude | Codex | Consensus |
|---|---|---|---|
| Premises valid? | CHALLENGE (F5: the ambiguity his directive fixes has a one-sentence alternative) | CHALLENGE (same, listed among 10 dismissed alternatives) | **DISAGREE with the spec's premise-acceptance → USER CHALLENGE #1** |
| Right problem NOW? | NO (F1: one user, zero builds, no metric moves) | NO ("architecture first, evidence later") | **CONFIRMED: not now, not as one piece** |
| Scope calibration? | Overbuilt as a single slice (F15: 4-way split) | Overbuilt (manual Mode C; board first; retire last) | **CONFIRMED: split** |
| Alternatives explored? | NO (F5/F15 missing) | NO (10 named alternatives absent) | **CONFIRMED: the spec under-explored** |
| Competitive/market risks? | F3 insurance · F4 intermediary status | disintermediation · runner concentration · host curation loss | **CONFIRMED: unaddressed, two are counsel-grade** |
| 6-month trajectory? | F12: five regret scenarios, kill criterion missing | same shape | **CONFIRMED: name a kill criterion** |

## FACT CORRECTIONS TO THIS SPEC (not taste — verified, the spec was wrong)

1. **§5's claim "the 0118 time+attendance gates survive unchanged in meaning" is FALSE.**
   Home pickup makes every Mode B/C owner produce `owner_confirmed_handoff_at` at their own door,
   hours before the session — the exact signal the corrected 0118 attendance gate honors. The 20%
   no-show rung becomes structurally unreachable for delegated dogs: **the third inertness of that
   same gate, this time by design.** Any home-pickup variant needs a NEW no-show predicate
   (candidate: the runner's arrival at the start point) and a P4/P9/P10/P12 re-pin.
2. **§12.6 is answered: cases CAN be opened mid-run, today.** Verified three ways — the gates at
   `0067:116-146` carry no run-phase restriction (codex), and the shipped R screen already has the
   entry point at `club/run/[sid].tsx:294` (ui6, at source). His question's answer is YES; the R
   screen respec must carry that entry point forward.
3. **§4.1's "address exposure follows the existing gate_code_access_log idiom" overstates reuse.**
   No club migration touches addresses; `0042:11` deliberately excludes address from the
   marketplace view. A club address-read path is NEW security surface (0116 §D party-gate law,
   0088 whole-request-403 hazard) — its own numbered work item, not reuse.
4. **§10's retirement blast radius was understated by an order of magnitude**: the five functions
   appear across ~17 suites (~88 pins), 10 migrations, api.ts, and the 693-line host console.
   Correct form: DEPRECATE (revoke `authenticated` EXECUTE + refusal pins) — closure is the server
   refusing, not the function vanishing — reversible at ~5 revokes instead of ~88 edits.
5. **§2's free mode-switch contradicts the fee ladder**: the booking mints at delegation time
   (0037:244/0081:184), so B→A inside 24h hits the strict 10% rung Sean ruled. Either the UI says
   so or the mint moves to pairing time — a priced decision, not an implication.
6. **§7's dogless companion is a safety question wearing a money answer**: an unpaid person with
   customers' dogs, no booking, no identity verification, no party standing in
   `club_incident_open`. Board visibility without accountability.
7. **Six silent decisions claimed as "nothing he didn't say" — now marked 🔴** (modes mutually
   exclusive per session · per-dog approval · transit-inside-custody stated-then-asked · pending
   picks and capacity · Mode A "copy only" unverified · **the missing scenario: a Mode B owner who
   ATTENDS the session** — in a Banpo pilot the most likely real case, and the flow forces a
   pointless return trip to an empty home).

## USER CHALLENGES — queued for Sean (never auto-decided)

**#1 — The premise itself has a cheaper fix than the restructure.**
You said: at-the-scene matching is ambiguous about pickup when the runner runs the club route.
Both models recommend: before building home pickup, consider that the ambiguity resolves with ONE
SENTENCE — *the owner brings the dog to the start point and hands off there* (what Mode A owners
already do). What we might be missing: you may want home pickup for its own sake (convenience as
the product), not just to fix the ambiguity. If we're wrong and you did want home pickup itself,
the cost of asking is one morning; the cost of NOT asking is the insurance leg (F3), the
intermediary-status exposure (F4, counsel-grade, brief still unsent), and a new address surface.

**#2 — Sequencing.** Both models, independently, recommend nearly the same split:
① runner-money secrecy (ruled, small, independent) · ② the PUBLIC BOARD over existing states (your
most explicit want, zero regulatory/insurance/retirement risk) · ③ owner-picks + runner-approves
with handoff still at the start point · ④ home pickup + Mode C, gated on counsel + insurance —
Mode C **manual/concierge** in the pilot ("building an algorithm with one user is theatre").
Kill criterion proposed: if no club session with ≥2 delegated dogs runs within N weeks of the
first build, the restructure shelves and scene matching stays.

## Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale |
|---|---|---|---|---|---|
| 1 | CEO | Mode = SELECTIVE EXPANSION | mechanical | autoplan override | mandated |
| 2 | CEO | Fact corrections 1-6 applied to spec text | mechanical | P1 | verified against code, not taste |
| 3 | CEO | Six silent decisions re-marked 🔴 | mechanical | integrity claim | the spec's own standard |
| 4 | CEO | Deprecate-not-retire (correction 4) | taste→adopted | P5/P6 | both voices + house closure doctrine |
| 5 | CEO | Mode C manual in pilot | taste→queued | P3 | codex; needs Sean (it reshapes his Mode C) |
| 6 | CEO | Kill criterion added as proposal | taste→queued | P8 | number is his |
| 7 | CEO | **Design/Eng phases DEFERRED** to the variant Sean picks | taste→surfaced | P3/P6 + Sean's own trim directive | running full dual-voice design+eng on a spec whose CEO verdict is "freeze at document stage, split 4 ways" reviews screens that may never exist; the phases run on the chosen variant tomorrow |

## VERDICT

**SPEC: SOUND AS A DECISION DOCUMENT, NOT APPROVED AS A BUILD PLAN.** The CEO phase's product is
the two USER CHALLENGES above plus the fact corrections. Nothing builds until Sean answers #1/#2.
The already-ruled, already-independent slice (runner-money secrecy) proceeds regardless.

**UNRESOLVED DECISIONS:**
- Sean: User Challenge #1 (premise: home pickup vs one-sentence fix vs middle path ③)
- Sean: User Challenge #2 (sequencing + manual Mode C + kill criterion N)
- Sean: the seven 🔴 in §12 + the six newly marked in correction 7
- Counsel: F3 (transit insurance) and F4 (intermediary status under Mode C) — ride the unsent briefs

## ADDENDUM — the blind spec-vs-code review landed after the report above

**SPEC-VERDICT: RETHINK** — *"pairing, booking/payment, custody, cancellation, and finish order are
one coupled state machine, but the spec defines only the pairing and UI layers."* This sharpens the
CEO verdict rather than contradicting it: whichever variant Sean picks, the money/custody/cancel
layers must be specified as ONE machine before any migration is authored.

Further fact corrections (verified against shipped code, in addition to 1-7 above):

8. **§6's board claim "the data shape is close" is FALSE.** `_club_shell_access` (0049:9) grants
   nothing for club membership alone; `club_delegation_board` (0053:251/:329) returns runners only
   to host/full actors and dogs only to host/full or the limited owner, and queries only
   `runner_delegated` dogs — Mode A dogs and companions are absent. A club-member board is a NEW
   sanitized projection, not an extension.
9. **§3/§7's capacity claims contradict `_club_runner_load`** (0047:50): accepted bookings, ACTIVE
   PROPOSALS, and the runner's own owner-handled dog all count today; proposal creation refuses a
   full runner (0047:104) and acceptance rechecks (0057:121). "Multiple pending picks, pairing
   consumes capacity" cannot coexist with "cap semantics unchanged" — pick one and specify the
   concurrent-approval conflict outcome.
10. **The two-phase finish touches more consumers than §5/§10 name**: incident settlement, the
    return-delay recovery, payout release, and the console screens all read the finish/return
    ordering (0045:327, 0116:577, 0068:96, 0072:221). Required: a consumer-by-consumer migration
    table separating unchanged event-consumers from ordering-consumers that must be rewritten.
11. **§12.6's answer upgraded from preliminary to VERIFIED**: `club_incident_open` carries no phase
    gate (0070:393, 0067:68) and the shipped run screen already invokes it for SOS
    (club/run/[sid].tsx:285). The reworked runner screen must PRESERVE that entry point.

**Net for the morning**: the A/B/C choice stands as written; the RETHINK adds that variants A and C
both require a follow-up spec covering the coupled machine (payment timing, capacity, custody
producer, cancellation arms, finish ordering) with the consumer table — variant B (board-only)
requires only correction 8's sanitized projection.
