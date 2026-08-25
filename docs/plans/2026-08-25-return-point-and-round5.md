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
