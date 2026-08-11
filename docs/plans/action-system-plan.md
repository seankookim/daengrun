# Plan — the action system, club audit, runner identity, and the polish layer

Branch `redesign-v4`. Written 2026-08-11. Sean is away; running under the standing autonomy grant.

## 0. Sean's directive (verbatim intent)

1. **"I don't like black buttons. All action buttons must evoke motive and initiate action —
   through color or animation or some other means. Black is the dullest of all. Give buttons
   purpose. So many black buttons and empty white buttons around the app."**
2. Go through the **club system** — all scenarios, logic, payment, buttons, screens.
3. **Remove or enlarge too-small text**; declutter every other screen, both sides.
4. Add **pic + text logo for the runner side**. Give it identity.
5. Maybe put the **logo on climax buttons**.
6. **Skeleton loads and the professional nuances.**
7. **Make it fun, not boring.**

## 1. This overrules DESIGN.md §3b, and I made it worse last turn

§3b currently reads: `Primary | paper.ink (inkPressed on press) | none | white 17/800`.
Sean is retiring that. **DESIGN.md is a law book, so this is an amendment, not a patch** —
the file changes and the provenance row records who decided and why.

Worse: in `7350d49` and `3a9d761` (this session) I converted schedule's `primaryAction`,
dog.tsx's save bar, and club/[id]'s host CTA **to black**, citing §3b. That was the law at the
time, and it is now the exact thing he is objecting to. Those three are the first reversals.

## 2. The action color — derived, not invented (style-freeze compliant)

The style freeze (DESIGN.md §Style freeze, Sean 2026-08-06) forbids **new** colors until 50
paying dogs. So the action color must come out of the existing palette. It does:

**§5 GO disc color law already says `coral = YOUR turn to act`.** Making primary CTAs coral is
not a new aesthetic — it is the existing "whose turn is it" law applied to buttons. Black said
nothing about whose turn it was; coral says "this one is yours."

Measured contrast of white labels (WCAG AA needs 4.5:1 normal, 3:1 large):

| fill | white label | verdict |
|---|---|---|
| brand coral `#E8552F` | **3.64** | large text only — fails a 14pt label |
| **`action` = `#C7401F`** | **5.02** | **passes at every size** |
| energy `#119B58` | 3.59 | large only |
| accent `#6C5CE7` | 4.86 | passes |

`ACTION = #C7401F` is the same hue, darkened until white is legal. DESIGN.md's own rule
("small white text never sits directly on coral — use an ink plate") is then satisfied *by
construction* instead of by exception. **The hairline stays `#E8552F`** — the brand line does
not move; it gains a deeper sibling for fills.

### The new button matrix (replaces §3b's)

| Kind | Fill | Label | Motion | When |
|---|---|---|---|---|
| **Primary / action** | `btn.primaryFill` (`btn.primaryPressed` pressed) | white 17/800 | scale 0.96 on press-down + haptic on commit | the ONE thing this screen wants you to do |
| **Climax** | `btn.primaryFill` + brandmark glyph + a settle spring | white 19/800 | logo mark rides the label | GO, 결제하기, 봉인, 인계 확인, 완주 |
| **Ready/confirm** | `ready` token w/ ink plate label | ink 17/800 | — | state is already satisfied (§5 sage law) |
| **Secondary** | `btn.secondaryFill` + 1px `btn.secondaryBorder` | `btn.secondaryInk` 16/800 | scale 0.98 | the second-most action |
| **Quiet** | canvas + 1px `#EEE` | `paper.text` 16/800 | — | tertiary, genuinely low stakes |
| **Destructive** | canvas + 1px `critical` | critical 16/800 | — | unchanged |

**The "empty white button" problem** is fixed by the secondary row: `ACTION_WASH` is a 4%
coral tint, so a secondary button reads as *part of the action family* instead of an
unfilled outline. Quiet stays neutral, but it must be rare — if a screen has three quiet
buttons, the screen has no point of view.

**Ink does not disappear.** It stays for surfaces (dark artifacts, the passport face, the
run ticket) and for text. What it stops being is *the answer to "what colour is a button."*

## 3. Scope

### 3a. Action system rollout
Every `PaperBtn`/primary across owner + runner + club. Census first (`grep` for `paper.ink`
as a `backgroundColor`), then convert by screen, then look at each one.

### 3b. Club system audit — behavior, not just paint
Sean asked for scenarios/logic/payment/buttons/screens. The club has 8 screens and a real
state machine (`club_sessions`, delegation, custody, incidents, settlement). Audit method:
walk every reachable state on the simulator against the DB, and read the RPC contracts for
the ones I cannot reach with current data (0 delegations, 1 member).

### 3c. Type floor + declutter, both sides
The FLOOR14 sweep never reached: `runner-profile` 9pt, `community`/`alerts` 12pt, `pay` 11.5pt,
`patch.tsx` 6pt labels, `CourseStrip` 8.5pt. Plus the §7b declutter pass on the screens the
2026-08-11 review scored NEEDS WORK.

### 3d. Runner identity
The runner side has no brandmark — owner home has `BrandLockup`, runner home has a bare
greeting. Add the mark + wordmark, and give the runner world its own accent so the two
sides are distinguishable at a glance without being different products.

### 3e. Skeletons + nuances
`Skeleton` exists but is used on 2 screens. Extend to the list surfaces that currently render
`불러오는 중...` text. Add press-down haptics on commit actions (§7c multimodal harmony).

### 3f. Fun
Sean's "not boring" is the hardest ask and the easiest to get wrong. Constraint: §7b Peak-End
says the GO press, handoff seal, and completion are peaks and are *exempt from minimisation* —
so fun goes THERE, not sprinkled everywhere. No idle loops (§6 honest motion).

## 3.5 CORRECTIONS from the CEO voice (both verified by me against the code)

- **This doc shipped a broken hex.** It said pressed = `#A8331580` — an 8-digit value, i.e. 50%
  alpha. Composited on white that is `#D4998A` and a white label measures **2.41:1**: a pressed
  state *lighter* than rest, failing AA, and violating the matrix's own no-opacity-tricks law.
  The code always had the opaque `#A83315` (**6.67:1**). Doc and code forked within two hours.
  → **Fix adopted: DESIGN.md and plans carry TOKEN NAMES ONLY. `theme.ts` is the sole hex
  authority.** This is why: a hex in prose is a value nobody typechecks.
- **Energy green is already a ghost.** DESIGN.md:163 still specifies `#12A05C`, which its own
  author measured at 3.38:1 — under the ≥3.5 gate written in the same paragraph. The shipped
  value lives as `GO_SAGE` in `owner/home.tsx:72`, a screen-local const, not a token. The law
  book names a colour that fails its own rule and does not exist in `theme.ts`.
  → Promoted to `paper.ready` / `paper.readyDeep`.
- **Token indirection is the real fix, and this plan originally missed it.** The reason Sean's
  taste change costs 64 edits is that screens hardcode `paper.ink` as a *fill*. Semantic role
  tokens (`btn.primaryFill`, …) mean the NEXT reversal is a one-line diff instead of another
  64-site sweep with 52 screens to re-verify. Adopted as the top-priority item.
- **Process, honestly:** I began editing `theme.ts` before this review returned. Under an
  autonomy grant with Sean away, the review is the only pushback there is, and the code moved
  first. Recorded rather than smoothed over.

## 4. Non-negotiables this plan must not break

- §6 honest motion: no animation that claims knowledge the system lacks. No idle loops.
- §7 honesty: no dead buttons, loading ≠ empty ≠ error.
- Frozen zones (§9): owner-home/fitness morph, meetup stage machines, matching compositor,
  availability's 3 predicates.
- Style freeze: no NEW hues. `ACTION` is a darkened existing brand coral, not a new color.
- Contrast floors: every fill/label pair measured, not eyeballed (the `#12A05C` lesson).
