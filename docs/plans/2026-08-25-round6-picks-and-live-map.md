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

### ⚠⚠ CORRECTED — the phone is NOT unruled. It is ruled, built, and a phone button was already REFUSED.

I wrote that a runner seeing an owner's phone was an unruled question and briefed the lab to draw
the affordance with its source "owed". Wrong on both halves, verified at source:

- **The policy exists and is enforced.** `_club_phone_visible` (0049:167) implements the rule —
  호스트↔전원 · 보호자↔(자기 개의) 수락 러너 양방향 · 그 외 호스트 경유 — with a lifetime gate
  covering unresolved custody, i.e. the 현장 반환 moment is squarely inside it, and an audit table
  (`club_phone_access_log`) written on every reveal. Entitlement is settled, not open.
- **The absence of data is a DECISION, not a gap.** `api.ts:3167-3168`, verbatim: 「연락처는 묻지
  않는다. profiles.phone 은 전원 NULL 이고 읽는 화면이 없다 — 받아두기만 하는 필드를 묻는 건
  넛지가 아니라 수집이고, **§12 가 전화 버튼을 거부한 것과 같은 이유다**」.

So a phone button has already been declined once, and the reason was not "who may see it" but
**collecting a field nobody reads is collection, not a nudge.** Drawing the affordance with a
source owed would re-propose a refused thing and render a permanently empty state.

**Corrected build:** the 현장 반환 arm uses **club chat**, which is shipped and realtime
(`club_chat_messages`, api.ts:3755/3791). No phone affordance anywhere.
**The real question, and it goes to Sean as this:** not "may a runner see the number" but **"do we
start collecting phone numbers at all?"** — a privacy decision with a prior NO. Spec session is
putting it on his console.

Caught by the spec session reading the source. My error was assuming that a NULL column plus no
reader meant nobody had decided, when the file said in words that somebody had.

## S6 — The session card: his question, and his own answer

> "where does the show this to the host club session card screen come into play?"

He answers it himself in the next clause: **leaveable and re-enterable** from the runner's — or the
owner's, if the owner is running — perspective, and **the host verifies, "perhaps the list?"**

So the card is a PASS, not a stage: something a participant can open at the gate, leave, and reopen;
and the host's verification is a checklist action against the pair list rather than a scanner
ceremony. Drawn that way in the lab, with the host side landing in the pair list (S3's other half).

---

# RULING — phone collection at onboarding (Sean, 2026-08-25)

> "the owner inputs their phone number when they sign up no? … i think we should have the owner and
> any new person insert phone number on onboarding for safety and contact purposes"

## The factual half of his question, answered

**No — onboarding does NOT collect a phone today.** Measured: `app/app/onboard/owner.tsx` and
`app/app/onboard/runner.tsx` contain zero phone/전화/연락처 references. `profiles.phone` exists and
is all-NULL. His recollection was of an intention, not a shipped field.

## The ruling, and why it is NOT a contradiction of §12's refusal

§12 refused a phone BUTTON, and `api.ts:3167` records the reason precisely: 「받아두기만 하는 필드를
묻는 건 넛지가 아니라 수집이고」 — *asking for a field nobody reads is collection, not a nudge.*
That refusal was conditional on there being **no reader**. Sean now names two: **safety** and
**contact**, and the 현장 반환 arm is a concrete third. So this ruling satisfies the refusal's own
condition rather than overriding it — the field acquires a purpose, which is exactly what it lacked.

**Scope of his words:** 「the owner **and any new person**」 — owners AND runners, at onboarding.

## What already exists, and what this actually costs

**Already built, and it is the expensive half:** `_club_phone_visible` (0049:167) implements the
disclosure policy (호스트↔전원 · 보호자↔자기 개의 수락 러너 양방향 · 그 외 호스트 경유), gated on
session state OR unresolved custody, with `club_phone_access_log` writing an audit row on every
reveal. **So the "who may see it" machinery is done.** What is missing is only the collection point
and the render.

**Owed:**
1. The onboarding field itself (both roles), with validation and an honest optional/required stance.
2. 🔴 **THE PRIVACY POLICY — SEAN-ONLY.** Collecting a phone is 개인정보 collection: the
   개인정보처리방침 must state the item, the purpose, the retention period and the recipient
   (a runner seeing an owner's number IS a third-party disclosure to that user). CLAUDE.md puts
   "changing what users are told" on the Sean-only list, so **the policy text is his to write or
   approve — no session drafts it into the app.** This is the gate, not the field.
3. Retention: a phone outlives a session, so it needs a deletion path — `delete_my_account_tx`
   already redacts columns and would need the new one (the 0122 dong lesson: a new column that
   survives account deletion is the exact defect class that has bitten twice).
4. Whether it is REQUIRED or optional at onboarding — a required field is a signup-funnel cost at
   11 users; optional means the 현장 반환 arm still needs its empty state.

## Also answered: the 봉인 paper lab was not deleted

He asked whether yesterday's paper/봉인 lab was redesigned away. **It exists**:
`docs/labs/enh-club-lab.html` (2026-08-24), and it still carries the consent-document 봉인 grammar.
The club-v2 set is not its replacement — it is newer work for the delegation spec, drawn after the
white-ground and type rulings. Both are alive; his preference for the current set is recorded, and
it is consistent with the rulings that came between them.


---

# D3 — the host live map has no feed, and the option I called "cheapest" is not

Recorded because I put a three-option menu in front of Sean with **one cost label wrong**, and he
may act on it.

**Verified:** runner positions publish per BOOKING on `run2-{bookingId}` (geo.ts:375). `0104:63-65`
gates that topic on the BOOKING PARTY — read is `p_uid = b.owner_id or p_uid = b.runner_id`, write
is `p_uid = b.runner_id`. **The host appears nowhere in it and would be refused at subscribe time.**

So my framing to Sean — 「the host subscribes to every runner's channel at once (simplest, but every
host holds N live connections)」 — was wrong in the part that matters. It is not a client-side
scaling trade. It is **a change to the security policy whose entire purpose was closing a walkable
authorization hole** (0104's own first line: 「so 0103's authorization cannot be walked around by an
old binary」). Caught by the spec session.

**The three options, correctly costed — all are new server surface, none is free:**

| # | Option | What it actually costs |
|---|---|---|
| 1 | Widen `0104` to admit the session host | Editing the policy that exists to close a walkable auth hole. Cheapest in lines, most delicate in review. |
| 2 | A session-level topic | A new policy surface with its own party gate — nothing to weaken, but nothing to reuse either. |
| 3 | Positions in a column, host polls | **A location at rest**, with a retention question. This is the entire argument 0123 had about the runner's base coordinate. |

**Sean's call, and the split is worth stating in his words:** 1 and 2 change **who may watch a live
position**; 3 changes **what the product stores about where people are**. The second kind is the
one his privacy policy has to describe, which puts it on his desk rather than ours.

**Also confirmed:** `session_checkin` (0030:254) is the ONLY statement in the schema that writes
`session_people.attendance` — every other reference reads it. So the host-verify affordance needs a
new writer AND a party gate admitting host and backup host without admitting every member.
`return_arrived_at` is absent (zero hits); the spec session's view, which I share, is that it should
be a RECORD rather than a screen transition — the two-sided ritual's premise is that the interaction
is the evidence — and that it therefore belongs in the same slice as `return_mode`, not bolted on.
