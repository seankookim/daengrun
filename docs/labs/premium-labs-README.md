# Premium labs — four screens, three variants each, and the questions for Sean

Produced 2026-09-17 from Sean's ask, verbatim: *"make progress in mocks for frontend and new ui
ideas based on the newest ui skills and updates online for vibe coded premium taste skill and
impeccable skill"*.

Two third-party design skills (`impeccable` v4.3.1, `taste-skill` v2 with its soft / minimalist /
redesign / imagegen siblings) were read in full and distilled into
**`docs/design/premium-taste-brief.md`**, which is the rulebook these labs apply. The product record
they both expect is **`docs/design/PRODUCT.md`**. Read the brief's § Tensions before ruling on any
lab; several of the picks below depend on a tension that is still open.

| File | Screen | Source of truth it was drawn against |
|---|---|---|
| `premium-owner-home-lab.html` | owner home | `app/app/owner/home.tsx`, `app/src/components/home-hero.tsx`, `draw-button.tsx` |
| `premium-request-flow-lab.html` | booking request | `app/app/owner/request.tsx` |
| `premium-live-run-lab.html` | owner watching a live run | `app/app/owner/live.tsx` |
| `premium-run-report-lab.html` | post-run report and 인증샷 | `app/app/owner/report.tsx`, `app/app/shot/[bid].tsx` |

Each file is a **complete standalone HTML page** — open it directly, no server and no build step.
Each carries three numbered variants side by side in 390pt phone frames, each variant's dial
settings, a rationale naming the skill rules it leans on, and a state table proving it survives the
states the screen actually has.

---

## Are these still the paper style? ①② yes, ③ deliberately not

**In every lab, variants ① and ② stay inside `DESIGN.md`'s paper world.** Variant ③ is always a
**labelled departure** — a black banner above the frame says so, and a red block beside it lists the
exact `DESIGN.md` clauses it breaks. That is so a pick can be made with eyes open rather than by
noticing later that the corners got rounded.

**What every departure still obeys, because these are not stylistic:** white ground · Korean detail
floor 15pt · real fields only · no gradient text · no glassmorphism or blur · no emoji as icons · no
AI-beige palette · transitions ≤ 240 ms · `prefers-reduced-motion` honoured · WCAG AA contrast.
A departure from the paper world is not a departure from the house laws.

| Lab | ③ is | What it breaks |
|---|---|---|
| owner home | editorial soft card | radius 0 · soft-shadow retirement · **the full-bleed coral hairline** · button matrix + the 4px lip · section-division-by-hairline · the style freeze |
| request flow | earliest-first, soft sheet | the same six, **plus a new component** (segmented control) against §3b's "four kinds of button, nothing else", plus the status-chip spec |
| live run | floating island over a full-bleed map | radius 0 · the coral hairline between island and map · the lip · the chip spec · the freeze. ⚠ Its main shadow is arguably *legal* — §2 allows shadow "where a floating surface genuinely floats" — but the pill, back-button and SOS shadows are not |
| run report | editorial spread | all of the above **plus a negative-margin overlap**; the paper world has one plane and nothing in `DESIGN.md` permits overlapping surfaces |

🔴 **Every ③ breaks the style freeze by definition** (`DESIGN.md` header: *"no NEW aesthetics until
50 paying dogs"*). None of them can ship without Sean lifting it. They are drawn so the question
"what are we giving up by holding the freeze" has a picture attached.

---

## What I recommend, per lab

⚠ **Read this warning before the four rows.** I recommend **② in all four labs**, and that pattern
should be treated as a fact about how the labs were *built*, not as four independent votes. ① is
always "refine what ships" and ③ is always "leave the paper world", so ② is structurally the middle
and the structure biases toward it. This repo's own law about agreement being the same claim counted
twice applies one level down, inside a single lab's construction. **If a ① or a ③ looks right, the
lab's shape is not evidence against it.**

### 1. Owner home → **②, one decision card**

In the `confirmed` state there is exactly one real action — check the ticket. Chat and pre-book are
things the owner *may* do. Giving all three an equal 78–96pt block makes them cancel each other out,
which is `DESIGN.md` §7b's *"Two ink CTAs cancel each other out"* and taste-skill §4.5's
**NO DUPLICATE CTA INTENT** arriving at the same place from two directions. ② costs the 43pt
phrase's visual punch and turns two blocks into 52pt rows, which is worse under Fitts. That trade is
the actual decision.

### 2. Request flow → **②, slots open on the screen** — but take ③'s *strategy*

② takes minimum taps from 4 to 2 by deleting the sheet, and turns the five settled facts into a
receipt that reads as "confirm" rather than "decide". **③'s strategy is separable from ③'s look**:
opening on the earliest bookable slot is already what `draft.autoEarliest` does when home's
지금 찾기 is tapped, and lifting only that into ② takes it to **1 tap** with none of ③'s breakages.
That hybrid is my actual recommendation and it is question 2 below.

### 3. Live run → **②, sentence first**

This is the only recommendation that rests on a rule rather than on taste. HIG checklist **C1**
requires that a **word** carry the state, never colour alone. ① says "fine" with a green chip, which
is gone for a colour-blind owner, on a screen in direct sun, and in a black-and-white screenshot.
② also gives the map ~90pt back. The cost is real: a sentence is needed per state and the states
multiply (3 pace × 3 signal × 2 held).

### 4. Run report → **②, record face first**

A completed run is an object in this brand's own vocabulary — `DESIGN.md` §1's passport, and §7b
exempts run completion from minimization by name. The dark face is *ours*; ③'s editorial spread is
everyone's, and taste-skill §4.2's own warning applies to it: reaching for the category default makes
the brand invisible. ⚠ **The cost is arithmetic and it needs a ruling:** §8 budgets the artifact, and
② makes **three** screens carry a ceremony object (`owner/meetup`'s ticket, `shot/[bid]`'s card,
this face). One of the three then has to stop being one. That is question 4.

---

## Questions for Sean, by number

**1. Owner home — ①, ②, or ③?** If ②, is losing the 43pt hero phrase acceptable, and are two 52pt
rows enough of a target for chat and pre-book?

**2. Request flow — ①, ②, or ③?** And separately: **should the screen open on the earliest bookable
slot when it was entered from 지금 찾기?** That is a behaviour change, not a look change, and it
works in any of the three. The code already carries the failure string for when no slot resolves.

**3. Live run — ①, ②, or ③?** ② is the only one that passes HIG C1 without a follow-up fix. If ①,
the green chip needs a word beside it before the next device smoke.

**4. Run report — ①, ②, or ③?** If ②: **which of the three ceremony objects stops being one** —
meetup's ticket, the shot card, or the report face? §8's artifact budget forces a choice.

**5. Photos in labs.** Every photo position in these four files is a **labelled empty slot**.
taste-skill §4.8 calls that "slop" and asks for `picsum.photos`; the house honesty law says a
stranger's dog in a mock of *this* product is a fabrication on the one surface whose claim is that a
particular run happened. I chose the house law. **The cost is real and I cannot paper over it: a
report lab with no photograph cannot answer whether the composition survives a real photo, and
variant ③ of the report lab is untested for exactly that reason.** Labs are already the sanctioned
mockup arena, so a placeholder image there breaks no shipped rule — **do you want photos in labs?**

**6. The GO state law is stale and the code disagrees with it.** Measured on trunk:
`DESIGN.md` §5 says the waiting blue is periwinkle `#5B82E8` / `#4468CC`, *"deliberately green-shifted
so it can never be confused with accent violet `#6C5CE7`"*. Those two hex values have **zero
occurrences** in `app/`. The shipped value is `home-hero.tsx:102 const WAIT_BLUE = '#6C5CE7'` — the
accent violet itself. Also stale in the same law: `GO_TINT` (zero occurrences; the disc was retired
2026-08-19) and §3b's ready green `#12A05C` (superseded by `paper.ready #119B58`, which `theme.ts`
already records as a correction). **Which is right — the law or the code? And separately, §5 and
`CLAUDE.md` § Design system both still describe a disc that no longer exists.** These labs are drawn
against the code and say so in their own headers. Full write-up: brief § Tension ⑫.

**7. The kicker seam in `DESIGN.md`.** §3b retires the latin kicker app-wide; §2's paper chrome
grammar keeps one ("PAYMENT" / "MOCK · 준비 중") and §3 reserves a sub-15pt tier for it. Proposed
one-line clarification, for you to accept or reject: **a latin kicker may label an artifact, never
announce a heading.** Under that reading impeccable's outright ban and `DESIGN.md` agree completely.
It is a `DESIGN.md` edit, so it is yours. Brief § Tension ②.

**8. The em-dash.** taste-skill bans `—` outright as "the single most-violated Tell". Measured:
**~1,792 lines of Korean in `app/` carry one**, and it is a functional clause separator in shipped
copy. **I recommend NOT adopting the ban.** What is worth adopting is narrower: **`기록 없음` is the
house word for "the server has no measurement", and a bare `'—'` may not stand in for it** — a dash
cannot distinguish *loading* from *failed* from *absent*, and `loading-state-audit.md` already flags
two sites where it does exactly that. `owner/report.tsx` already does it right. Brief § Tension ⑪.

**9. Where `PRODUCT.md` lives.** It is at `docs/design/PRODUCT.md`. impeccable's `init` expects
`PROJECT_ROOT/PRODUCT.md` and its launcher resolves that path. I kept it out of the root because the
root already carries `CLAUDE.md`, `DESIGN.md`, `TODOS.md` and `README.md`, and a fifth competing
authority is the failure this repo keeps recording. **If you want the skill to auto-load it, it moves
or gets a symlink — one line either way.**

**10. Do we install these skills at all?** Install commands and a command-to-work mapping are in the
brief § (e). ⚠ One thing to decide deliberately rather than by default: `npx impeccable install`
also installs an edit hook whose own README says it "runs independently of model-tool approval" and
can cache its engine even when a session denies the launcher. **`.impeccable/hook.cache.json` is
already committed to this repo**, which is evidence that happened once on the old Mac. That is your
call, not a session's. `--no-hooks` skips it.

---

## What was verified, and how

Built from one shared token block (`md5 3e4347864b431bd07f5b453feadd91f5`, byte-identical in all
four). Each file was then checked mechanically rather than by eye:

| check | result |
|---|---|
| doctype, `<head>`, closed `</html>`, CSS inlined, no reference to any build directory | pass ×4 |
| unfilled template tokens | 0 |
| three variants (①②③) present, three dial blocks, ≥3 phone frames | 3 / 3 / 5 in every file |
| departure banner present, breakage list present | 3 / 1 in every file |
| unbalanced or unclosed tags (HTML parser, stack-based) | 0 |
| **side-stripe borders** (impeccable's `side-tab` rule) | **0** |
| font sizes below 15px | only the declared latin tiers (10, 11, 12.5) |
| **Hangul text nodes outside a `lang="ko"` element** | **0** — Korean appears only inside phone frames or as explicitly tagged quotations of app strings |
| file sizes | 55,171 / 53,103 / 54,829 / 59,771 B |

⚠ **The crude control, run beside the side-stripe gate per `CLAUDE.md` § THE STANDING RULE.** An
un-narrowed `grep -cE "border-(left\|right)"` returns **30** across the four files against the gate's
**0**, and every one of the 30 is accounted for in both directions: **15 are `border-*:0`** (explicit
removals, including the loud-fail strip's, which exists precisely to say a callout gets no stripe)
and **15 are 1px vertical dividers between columns of a stat row** — a rule *between* cells, which is
the opposite object from a coloured stripe on a card's leading edge. **Zero hits are above 1px and
zero are on a card, list item, callout or alert.** The two checks agree on the thing that matters.

⚠ **What is NOT verified.** Nothing here has been opened on a device or a simulator. These are HTML
approximations of React Native screens, so the type renders in the browser's Korean stack rather than
the app's, and every spacing judgement is a browser judgement. **No claim is made about how any of
this looks on hardware.**
