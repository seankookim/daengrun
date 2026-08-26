# Round 6 — his picks, and four new surfaces

**Source:** Sean, 2026-08-25, reading the six labs. Verbatim in full:

> "share card i like 3 but make it so that the pace info background is transparent so it's just
> text overlaid on photo. session sign up i like b for the pick up location selection and L1. the
> host should also have a live map screen but also be able to leave that screen to check all other
> host screen functionalities like the list of pairs, case registration, etc and have the end
> session button in the live map. for the live map screen, once the run is over, it should be
> conditional for a runner between leave at home or meet owner at site, as the former would have to
> navigate the runner to the owner set address which once the runner has arrived he or she can
> click arrived after which the transfer ritual screen between the owner and the runner can pop up,
> and the latter would have to just to tell the runner to find the owner and give the owner's phone
> number and the transfer ritual on site. route trace should be optionally overlaid on the image to
> export (add a slide button for that). also where does the show this to the host club session card
> screen come into play? should be a leaveable and re-comeback-able screen from the runner or the
> owner's perspective if the owner is running, and the host should have a way to verify (perhaps
> the list?)."

## PICKS — settled, no further review

| # | Pick | Notes |
|---|---|---|
| Share card | **③ 스토리** (9:16) | with an amendment, below |
| Pickup-location choice row | **ⓑ 도장 칸** | the no-box variant — dashed square that asks to be stamped |
| 즉시 해제 label | **L1** 「내가 데리고 있었어요 · 인계 없음」 | |

### ⚠ Amendment on ③, and the tension it creates — stated, not silently resolved

He wants **the pace block's background transparent — text directly on the photo.** ③ was drawn
with an ink plate for a measured reason: white type cannot be contrast-checked against an unknown
photo, and DESIGN.md's floors are *vs canvas*. Removing the plate removes the only thing making
that text gateable.

**This is his second request of the same shape** — R3 (round 5) asked for the club card to be a
photo with 「black font and white shadow effect to make things legible」. So the pattern is a
standing preference: *text on photo, no boxes.*

**How it is built** (my call, flagged as a copy/craft decision, not a rule change): no plate, no
visible box — but a **deterministic scrim** the type sits on: a soft bottom-up gradient burned into
the exported image beneath the text band. It reads as "transparent, text on photo" because there is
no edge, and it is measurable because the gradient's floor value is fixed and known. That preserves
his look AND keeps a contrast number that can be gated. If he dislikes the scrim, the fallback is a
text-shadow, which is weaker and unmeasurable — recorded so the trade is visible.

## S5 — Route trace becomes OPT-IN on the export (「add a slide button」)

His answer to the privacy flag: not removal, **user-controlled disclosure**. Correct instinct and
it is the stronger fix — a shape a person chose to publish is not a leak.

**Recommendation attached to the build: default OFF.** A toggle that defaults ON publishes the
route for everyone who never opens the switch, which is the same disclosure with a consent-shaped
label on it. Default OFF makes the trace something someone reaches for. His to overturn.

## S3 — The host gets a LIVE MAP, and it must be leaveable

Ruled: the host's live map is a screen, not the host's only screen — they can leave it for the pair
list, case registration and the rest, and come back. **The 세션 종료 button lives in the live map.**

## S4 — The runner's post-run branch 🔴 **THIS MAKES DEFECT 2 BLOCKING**

Once the run ends, the runner's screen branches on the return mode:

| Return mode | What the runner's screen does |
|---|---|
| **집 반환** (leave at home) | **navigates the runner to the owner's set address** → runner taps 도착 → the two-sided transfer ritual opens |
| **현장 반환** (meet on site) | tells the runner to find the owner, **shows the owner's phone number**, ritual on site |

🔴 **The 집 반환 arm is exactly the case `booking_pickup_address` forbids.** Confirmed earlier
today: the club's return window lies outside the address gate *by construction* (booking is
`completed`, custody `return_pending`; the gate admits only through `active`). So the screen Sean
just specified — "navigate the runner to the owner set address" — **cannot fetch that address on
today's server.** This converts defect 2 from "precondition of the sign-up slice" to "precondition
of the live-map slice too." Relayed to the spec session, who already decided the fix (a
custody-aware arm on 0065 keyed to `return_pending`).

⚠ Second dependency, smaller: the 현장 반환 arm **shows the owner's phone number**. Whether a
runner may see an owner's phone, and in which window, is a privacy/product decision that is NOT
ruled — `profiles.phone` is all-NULL with no reader today (recorded in the profile-nudge lab).
Drawing a phone number the system cannot produce would be a fabricated field. Flagged for the spec
session; the lab draws the affordance and marks the source as owed.

## S6 — The session card: his question, and his own answer

> "where does the show this to the host club session card screen come into play?"

He answers it himself in the next clause: **leaveable and re-enterable** from the runner's — or the
owner's, if the owner is running — perspective, and **the host verifies, "perhaps the list?"**

So the card is a PASS, not a stage: something a participant can open at the gate, leave, and reopen;
and the host's verification is a checklist action against the pair list rather than a scanner
ceremony. Drawn that way in the lab, with the host side landing in the pair list (S3's other half).
