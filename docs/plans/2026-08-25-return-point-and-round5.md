# Round 5 — the return point, and five smaller things

**Source:** Sean, 2026-08-25, reading the club-v2 labs. Verbatim, in full, because five separate
work items are folded into one paragraph and the wording matters:

> "im liking the look of the lab much more. the tan gold should be image of club later with text in
> black font and white shadow effect to make things legible. im looking at the lab: what do you mean
> runner left? how can that happen? left before the start of the session? then someone else should
> carry it over yes. iterate on the button look; it looks just like an excel block, nothing more.
> pace map record should give the shareable card thing; also what do you mean 즉시 헤제 once the run
> is over? the responsibility of the runner of the dog ends once the runner returns the dog home or
> the runner meets the owner at the starting point (owner should have to choose both; whether to
> request a runner at start or run themselves, and if theyve chosen a runner request, whether they
> will meet the runner at the club session run end point or at their home address or some other
> address that's not too far.) quite a few things there; organize and gstack it."

Six items. **R1 (the return point) is the load-bearing one** and is a product-mechanics change, not
a design iteration; the rest are smaller and mostly independent.

---

## R1 — The return point: where does the runner's responsibility end?

### What Sean said, decomposed

Two separate choices the owner must make, and he says **both**:

1. **Self-run or request a runner** — "whether to request a runner at start or run themselves."
2. **If a runner: where the dog comes back** — "the club session run end point, or their home
   address, or some other address that's not too far."

And the doctrine behind it: **"the responsibility of the runner of the dog ends once the runner
returns the dog home or the runner meets the owner at the starting point."**

### ⚠ What already exists — do NOT rebuild it

Scouted at source before writing this plan, because half of R1 is already shipped doctrine:

- `bookings.runner_confirmed_return_at` / `owner_confirmed_return_at` (0083 §1) already exist, and
  0083's own comment states the ruling: **"the runner is paid once the dog is returned"** — the
  responsibility-ends-at-return model is ALREADY the marketplace law.
- `confirm_return_tx` / `force_return_tx` (0083) are the shipped return machinery.
- `0045_custody_returns.sql` is a whole custody/returns slice.
- Club already carries a `보호자 동반` stage (0040/0045/0047/0048) — "owner comes along" is a
  modelled state, which is the closest existing thing to choice (1).
- `create-booking-hold` takes **one** `address_id`, used as the PICKUP address (0060's RPC
  re-verifies `a.owner_id = b.owner_id`).

**So R1 is not "build a return model."** The return model exists. R1 is:
**the owner never gets to CHOOSE the return point, and the club path has no return at all.**

### The actual gap, stated precisely

| Path | Pickup | Return | Owner's choice today |
|---|---|---|---|
| Marketplace booking | `address_id`, owner-chosen | Return confirmed by both parties, but the LOCATION is implicit (assumed = pickup) | none |
| Club session | meetup point (session-level) | **`즉시 해제` — the dog is released at the end point** | none |

Sean's question *"what do you mean 즉시 해제 once the run is over?"* is the bug report: the club
path currently **ends custody at the finish line**, which is not a return. A dog released at the
end point has not been returned to anyone. That is the honesty defect, and it is the reason R1
exists.

### Proposed model (to be reviewed, not assumed)

**A booking gains a RETURN POINT, chosen by the owner at creation, from three kinds:**

- `pickup` — back to where it started (the default; today's implicit behaviour made explicit).
- `session_end` — club only: the owner meets the pack at the session end point.
- `other` — a different saved address, **bounded by distance** ("not too far" — needs a number; see
  Open Questions).

**Custody ends when the return is confirmed at the chosen point**, using the machinery that already
exists (`confirm_return_tx`), rather than at run end. `즉시 해제` stops being a state and becomes
what it actually is: the `session_end` return, confirmed by both parties like any other.

**Self-run vs request-a-runner** is the prior choice, and for the club path it maps onto the
existing `보호자 동반` stage rather than a new concept.

### Blast radius (files that must move)

- `supabase/functions/create-booking-hold/handler.ts` — new input, validated like `address_id` is.
- A migration: `bookings.return_kind` + `return_address_id`, their CHECK, and the party/state gates.
- `confirm_return_tx` / `force_return_tx` — the return's LOCATION becomes part of what is confirmed.
- Club session dogs — `즉시 해제` retires as a terminal state.
- Client: booking creation (the choice), meetup screens (both sides show WHERE), the club run screen.
- Settlement timing — "runner is paid once the dog is returned" now has a location dependency.
- The club-v2 labs — board/console/run all draw return states.

### Open questions (NOT to be auto-decided — money and safety)

1. **"not too far" is a number nobody has set.** A radius from pickup? From the session end point?
   What refuses, and with what copy?
2. **Does the return point change the price?** A cross-town return is runner labour. If yes, this
   touches the money canon and needs Sean.
3. **What happens when the owner is not at the return point?** The late-booking protocol answers
   this for pickup; return has no equivalent, and a runner holding a dog nobody collects is the
   worst state in the product.
4. **Club + `other` — is that even allowed?** A pack of dogs cannot scatter to twelve addresses.
5. Does `session_end` require the owner to be AT the session (i.e. 동반), or can they arrive at the
   end only?

---

## R2 — "runner left": Sean challenged the scenario itself

> "what do you mean runner left? how can that happen? left before the start of the session? then
> someone else should carry it over yes."

Two things at once: he does not accept the event as well-formed, and — conditional on
before-the-start — he rules **someone else carries it over**.

**Status: PARTIALLY RULED, and it is the spec session's item, not this plan's.** Recorded because
the club-v2 console lab draws this scenario. What is still open: mid-run departure (his phrasing
implies he may consider it out of scope), and what the carrying-over runner earns for a second dog.
The settlement amounts in the console lab were withdrawn for exactly this reason and stay withdrawn.

---

## R3 — The club card becomes a photo

> "the tan gold should be image of club later with text in black font and white shadow effect to
> make things legible."

The `#F4EBD3` tan card on owner home (`clubcard.tsx:614`) becomes a **club photo** with black text
over a white text-shadow for legibility. "later" = the image is a future asset; the treatment can
land now with a placeholder that degrades honestly (no photo → no fake photo).

Note this is the card I flagged and did NOT whiten in the pale-ground sweep — Sean's answer is that
it should not be a flat colour at all.

---

## R4 — Buttons: "it looks just like an excel block"

The round-4 affordance treatment (1px border + chevron + white fill) reads as a spreadsheet cell.
The requirement it must still satisfy: **a clickable choice must look clickable** (his round-4
ruling), and a non-tappable row must not. So this is a re-draw, not a retreat — the affordance
stays, the vocabulary changes. Lab item, 2-3 variants, his pick.

---

## R5 — The shareable record card

> "pace map record should give the shareable card thing"

A run's record (pace, map, distance) becomes a **shareable card**. New surface. Needs: what is on
it, what is NOT on it (**privacy: the course trace is location data about where a dog lives** —
0060/0065/0122/0123 all exist because of this), how sharing works (image export vs link), and
whether a club run's card can show other people's dogs.

⚠ This one has a privacy blast radius that the other five do not.

---

## R6 — `즉시 해제` semantics

Folded into R1 — it is the same question. Listed separately because Sean listed it separately.

---

## Sequencing (proposed)

1. **R3, R4** — pure design, no server, no ruling needed. Ship as labs → picks → build.
2. **R5** — needs a privacy contract before a pixel is drawn.
3. **R1** — needs the five open questions answered, then contract → migration → adversarial cycle.
   The client half is atomic with the migration (DOG_SELECT precedent).
4. **R2** — spec session's, tracked not owned here.

**Nothing in R1 gets built until the open questions are answered.** The failure mode this plan
exists to prevent: drawing a return-point picker that implies a distance rule nobody has set, in a
lab Sean reads to decide — the exact mistake made with the settlement amounts earlier today.

---

# REVIEW — Phase 1 (CEO)

## Voice A — Codex (strategy challenge), verdict summary

**Headline: the plan's central premise is contested, hard.**

1. **"Endpoint handoff is not inherently a defect."** It is a legitimate model if the promise is
   explicit: *the owner books a delegated pack run and agrees to collect the dog at the published
   finish point.* It becomes a defect only if the product PROMISED home return, concealed the
   endpoint requirement, or ends custody without transfer to an authorized person. The plan asserts
   the defect without establishing any of those three conditions. **This directly contests R1's
   framing** (and therefore my reading of Sean's 「what do you mean 즉시 해제」).
2. **"An address cannot receive custody."** The real question is not *which address* but *which
   authorized person physically received the dog*. `return_address_id` creates false precision while
   leaving recipient identity, authorization, lateness, refusal and failed handoff unresolved.
   ⚠ **VERIFIED AT SOURCE and it is stronger than Codex knew**: `0083:183-185` records Sean's own
   D-r1 ruling — *"THIS interaction is the evidence, and the runner is paid once the dog is
   returned"*. The shipped return is TWO-SIDED PERSON-TO-PERSON (`runner_confirmed_return_at` +
   `owner_confirmed_return_at`, or a recorded force) and contains **no address at all, by design**.
   So the return point is an EXPECTATION both parties coordinate on, not a custody field — and
   modelling it as a column would put location where Sean deliberately put an interaction.
3. **Per-dog return choice destroys pack economics** — a runner cannot scatter six dogs to six
   destinations; deadhead time after the advertised run; `other` may need a vehicle, parking,
   building access, incompatible dogs sharing transit. An absent owner traps the runner in unpaid
   custody. A destination change materially alters a job the runner already accepted. More
   addresses = more owner location data exposed to runners. "If runners price the uncertainty,
   margins collapse; if they are not paid for it, supply collapses."
4. **`other` is a separate service, not a picker option.** The plan's own five open questions are
   evidence of that, not evidence that five answers unlock a picker.
5. **Six-month regret list**, condensed: generic return columns on `bookings` when marketplace and
   club already run separate custody machines · treating saved-address ownership as proof of an
   authorized recipient · distance rules before knowing whether runners accept distributed returns
   at any price · **letting a mockup wording dispute dictate database architecture** · spending
   cycles on button variants, club photography and shareable cards before knowing why users do or
   don't rebook · treating runner replacement as a side-spec when spare-runner liquidity is not a
   fact in a thin marketplace.
6. **The 10× reframe:** *"What is the single, clearest fulfillment promise daengrun can deliver
   reliably enough that first-time owners book again?"* Proposed pilot shape: marketplace stays
   door-to-door · **one** delegated-club return model for the whole pilot (endpoint collection is
   the lower-risk candidate) · exceptional destinations handled manually, not promised as a feature
   · rename `즉시 해제` on the SELF-RUN record to non-custody language (e.g. 「내 러닝 종료」) ·
   instrument whether return logistics actually affect rebooking before building for it.

**Codex scope verdict: R1 as written is over-built for 11 users; R3/R4/R5 are pre-PMF polish.**

*(Voice B — independent Claude CEO subagent — pending; consensus table follows.)*

## Voice B — independent Claude CEO subagent

**Verdict: R1 as scoped should not be built. Its founding bug report is false.**

Its four critical findings, **each re-verified by me at source before recording** (this plan's own
premise is what they overturn, so relaying them unchecked would be the exact failure this repo
keeps naming):

- **F1 — 「즉시 해제」 is not a defect; it is Sean's own ruling, and it applies only to a dog he is
  holding himself.** ✅ VERIFIED: the lab frame at `club-v2-run-lab.html:266` is titled
  **참가자 러닝 뷰** — the SELF-RUN participant view, and the 즉시 해제 line lives only there. And
  Sean, 2026-08-24 verbatim (`docs/decisions/2026-08-24-sean-ui-club-commentary.md:59-60`):
  *"the runner goes back to each owner's home, **or if it's the owner, then there's an immediate
  release of all responsiblites**."* So he ruled BOTH arms a day earlier: delegated → the runner
  goes to each owner's home; self-run → immediate release. There is no custody to end and no party
  to return to. **This plan read a self-run frame as the club's whole return model.**
- **F1b — delegated club dogs already HAVE a full return model.** ✅ VERIFIED in the very file this
  plan cited and did not open: `0045_custody_returns.sql` ships `custody_phase='return_pending'`,
  `session_confirm_return` (both-stamp), `session_force_return_override`, and `club_finish_session`
  raising `dogs_not_returned`. The plan wrote "the club path has no return at all" one paragraph
  after naming the file that implements it.
- **F2 — the club return-point choice was ALREADY RULED, hours before Sean's message.** ✅ VERIFIED:
  spec v2 §7.2 (`:502-505`) specs it per pairing — 집 픽업 (default) / 현장 인계, *"Return mirrors
  pickup … One column on the pairing (`pickup_mode`)"* — and §14.2 (`:898`) records his answer:
  **"Pickup mode: BOTH ✅"**. This plan proposed `bookings.return_kind` as though the surface were
  open. It is not, and it belongs to the spec session.
- **F3 — scope invention.** Every clause of Sean's paragraph is club-framed, read while looking at
  club labs. This plan put the blast radius in `create-booking-hold` — the MARKETPLACE-only entry
  point, which club bookings never touch (`address_id` null by construction, 0043:341-347).

Plus, ranked lower but real: F5 (making settlement location-dependent drags a cosmetic choice
through the money canon, for a product with 0 payments and charging OFF) · F6 (the "not too far"
radius is **unenforceable**: `addresses.lat/lng` are NULL until the owner pins, 0065:29-33, so the
gate silently wouldn't apply half the time — the honesty law's forbidden shape) · F7 (R1's privacy
blast radius is LARGER than R5's: a second address per booking is a second disclosure and a second
grant surface, in the repo whose 0060/0065/0122/0123 exist to minimise exactly that) · F8 (it taxes
the scarce side: a job becomes bespoke, with no decline-on-destination and no price — and it cuts
against **yesterday's** 0123, which just asked runners to commit to a catchment for 7 days) ·
F9 (nothing ties any item to the M1 rebooking gate, and **Sean is the source but Sean is not a
user** — at 11 users you can ask all of them before lunch) · F11 (**Sean's own sentence contradicts
itself**: "meets the owner at the *starting* point" vs "the club session run *end* point" — this
plan silently harmonized to `session_end`) · F12 (R2's carry-over is already shipped:
`session_transfer_accept`, 0045:199-327) · F13 (a white text-shadow makes DESIGN.md's ≥7:1 floor
unverifiable; the repo's measurable idiom is the ink plate) · F14 (R5 gated too broadly — the
privacy risk is the MAP TRACE and other people's dogs, not the card; a trace-free card has neither)
· F16 (five new questions added to a queue that is already the scarcest resource).

## CEO consensus

| Dimension | Codex | Claude | Consensus |
|---|---|---|---|
| 1. Premise valid (즉시 해제 = defect)? | NO | NO — factually false, it's his own ruling | **CONFIRMED: premise dead** |
| 2. Right problem? | NO — reframe to fulfillment promise | NO — it's a copy bug | **CONFIRMED** |
| 3. Return point belongs on a booking column? | NO — "an address cannot receive custody" | NO — already a pairing flag, already ruled | **CONFIRMED** |
| 4. `other` address earns a slot now? | NO — separate service, handle manually | NO — no demand evidence, unenforceable radius | **CONFIRMED** |
| 5. Scope calibration across the six? | R1 over-built; polish is pre-PMF | R4 + R5-v1 + R1-copy only | **CONFIRMED** |
| 6. Supply-side risk addressed? | NO — margins or supply collapse | NO — bespoke jobs, cuts against 0123's cooldown | **CONFIRMED** |

**6/6 CONFIRMED. Zero disagreements.** Two independent voices, one reading the repo and one
reading the market, reached the same verdict by different routes — and the repo's own files
settle it: this plan proposed building something Sean had already ruled, to fix something that
was never broken.

## USER CHALLENGE (not auto-decided — goes to Sean)

**What Sean said:** the owner should choose the return point, including "some other address that's
not too far", and 즉시 해제 is wrong.
**What both models recommend:** don't build the model. 즉시 해제 is his own 08-24 ruling and only
needs a label that says *whose* dog it was. The 집/현장 choice he's asking for he already ruled
today (spec v2 §14.2 "BOTH"). The only genuinely new thing is the THIRD option, and no owner has
asked for it.
**What we might be missing:** he may know from talking to owners that home-return is the thing
that makes people rebook; he may intend the third address for a real case (a walker, a vet, a
partner's flat). Neither model can see his conversations.
**If we're wrong, the cost is:** we shipped a label fix and asked one question, instead of a
migration — recoverable in days. If we build and they're right, we carry a permanent unenforceable
distance rule, a second address disclosure per booking, and an unpriced runner leg, pre-PMF.

---

# RESOLUTION — Sean, 2026-08-25, answering the premise gate

He did not pick from the options. He specified the flow, and it is **club session sign-up**, which
settles the scope question the review raised. Verbatim, both answers:

> "as the owner goes through the process of signing up for a session, the app should prompt them
> with a set up screen asking all necessary things, including but not limited to whether they will
> run themselves in which case the starting point address and other things need to be shown, or
> whether they will request a runner, at which point the next required questions include but are
> not limited to where they ask the runner to pick up the dog (here there can be two options; a
> default home address or a second option giving a new address option), etc and also be shown all
> session details like time, group number, etc etc, and also whether the owner will pick up the dog
> at the club's ending point and meet the runner after the run is finished on site or whether they
> ask the runner to bring the dog back home so the owner can stay home. in similar fashion, there
> shuold be one more option of where the owner can ask for pick up in the beginning, this option
> being the place where the session run begins so that the requested runner doesnt have to do any
> pick up and just bring themselves and required equipment to the session start site."

> "a requested runner can initially meet and pick up the dog from the owner at the owner's selected
> point, which can be the owner's home or some other place, in which case pick up statuses have to
> be monitored by the host, or they can meet the owner and the dog at the starting site of the
> session run if the owner has decided so… once the club session run has finished, the runner with
> the dog should meet the owner where the owner desires, which can either be the owner's custom
> address (whether that's the owner's home or not and in either case the runner will have
> responsilibty under the the dog transfer has been completed), or at the site where the run has
> finished (where once again the owner and the runner has to complete the transfer and mutual
> confirmation ritual) and the runner does not need to do a go-back-to-owner-home service"

## What this settles, and what it changes about the review

**Scope: CLUB SESSION SIGN-UP.** Confirms voice B's F3 — the marketplace booking flow is not
involved. `create-booking-hold` comes out of the blast radius entirely.

**The model, stated as he specified it:**

| Choice | Options |
|---|---|
| Who runs the dog | **self-run** (starting point address + details shown) · **request a runner** |
| PICKUP point (runner path only) | **home** (default) · **another address** · **the session start site** ← *new, and his own addition* |
| RETURN point | **owner's custom address** (home or not) · **the run finish site** |
| Both transfers | the existing two-sided confirmation ritual — unchanged |
| Host | **monitors pickup statuses** |

**The session-start pickup option is the part no review anticipated, and it inverts two of their
objections.** F8 said this taxes the scarce side; the start-site option *removes the runner's
pickup leg entirely* — the runner brings themselves and their equipment to the start. F7 said a
second address is a second disclosure; the start-site option discloses **zero** owner addresses.
So the option set he added is a supply-side and privacy-side improvement, not a cost.

**What the review got right and still stands:** it is club-only (F3 ✅) · 즉시 해제 was never a
defect and needs a label, not a model (F1 ✅) · the return is a person-to-person ritual and stays
location-blind in the money path (F5 ✅ — he describes the ritual, not a settlement term) ·
the existing `pickup_mode` flag is the right home, it just widens from two options to three (F2/F4 ✅
— **spec session's surface, not this plan's**).

**What is now moot:** the "not too far" radius (F6) — he specified an *option set*, not a distance
rule; nothing to enforce. Four of the five open questions dissolve with it.

**What is still genuinely open:** what a runner is paid when the pickup leg disappears (start-site
pickup is less work than home pickup) — a money question, and money questions are Sean's.

## Disposition

1. **Spec session owns the model** — it widens their already-ruled `pickup_mode` (§7.2) from
   {집, 현장} to a pickup triple and a return pair, both on the pairing. Relayed with his verbatim.
2. **ui6 (this session) owns the SETUP SCREEN** — the sign-up flow he described: self-run vs runner,
   then the pickup/return choices, then session details (time, group number). Lab first, his pick.
3. **The 즉시 해제 label fix** ships regardless and is not blocked on any of it.
4. **Runner pay for a pickup-free job** goes to his queue as one question, not five.
