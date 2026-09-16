# Premium-taste brief — `impeccable` + `taste-skill`, scoped to daengrun

**What this is.** Sean asked for *"progress in mocks for frontend and new ui ideas based on the
newest ui skills and updates online for vibe coded premium taste skill and impeccable skill"*
(2026-09-17, verbatim). Two third-party design skills were cloned read-only and read in full. This
file is the distillation: which of their rules apply here as-is, which ones `DESIGN.md` already
covers or outright contradicts, the anti-slop checklist we adopt, dial settings per surface, and how
to actually run the two skills against this repo.

**Authority order, and it is not negotiable.** `CLAUDE.md` → **`DESIGN.md` (the 정본)** →
`docs/design/hig-conformance-checklist.md` → this file. **Where a skill and `DESIGN.md` disagree,
`DESIGN.md` wins and the disagreement is recorded below as a Tension for Sean, never resolved
here.** A third-party skill is an outside opinion with no standing in this repo; it earns its way in
one rule at a time.

**Sources, read 2026-09-17 from the read-only clones.**

| Skill | File read | Frontmatter name |
|---|---|---|
| impeccable v4.3.1 | `.claude/skills/impeccable/SKILL.md`, `skill/reference/craft-floor.md`, `operate.md`, `ios.md`, `init.md`, plus `PRODUCT.md` / `DESIGN.md` as format templates | `impeccable` |
| taste-skill v2 | `skills/taste-skill/SKILL.md` (1207 lines, 14 sections + 3 appendices) | `design-taste-frontend` |
| soft-skill | `skills/soft-skill/SKILL.md` | `high-end-visual-design` |
| minimalist-skill | `skills/minimalist-skill/SKILL.md` | `minimalist-ui` |
| redesign-skill | `skills/redesign-skill/SKILL.md` | `redesign-existing-projects` |
| imagegen (mobile) | `skills/imagegen-frontend-mobile/SKILL.md` | `imagegen-frontend-mobile` |

🔴 **Read this before adopting anything from taste-skill.** Its own §13 OUT OF SCOPE says the skill
is **not** for *"Dashboards / dense product UI / admin panels"*, *"Multi-step forms / wizards (use
Form-specific patterns; this skill won't make them better)"*, or *"Native mobile (use Apple HIG /
Material directly)."* Its §0 header is narrower still: *"Landing pages, portfolios, and redesigns.
Not dashboards, not data tables, not multi-step product UI."*

**daengrun is native mobile, and the booking request flow is literally a multi-step wizard.** So
taste-skill self-declares that it does not govern most of this product. What survives the scope cut
is real and worth having — its **anti-slop tell list**, its **three dials**, its **pre-flight
mechanics**, and its **interactive-state discipline** — and those are what § (a), (c) and (d) below
take. Its architecture sections (React/Next/Tailwind stack, RSC, Motion library, design-system map)
are inapplicable to React Native and are not adopted at all. **impeccable, by contrast, ships a
native iOS reference (`ios.md`) and an Operate-mode reference (`operate.md`) written for exactly our
surface class, so it is the heavier of the two inputs here.**

---

## (a) Rules that apply to daengrun as-is

Each row names the skill and the section it came from. "As-is" means adoptable without a Sean
ruling, because it either agrees with `DESIGN.md` or fills a gap `DESIGN.md` leaves open.

### A1 · Before you draw anything

| Rule | Source | Why it applies here |
|---|---|---|
| **Declare the design read in one line before generating** — *"Reading this as: \<page kind> for \<audience>, with a \<vibe> language, leaning toward \<design system or aesthetic family>."* | taste-skill §0.B | Cheap, and it forces the surface's job to be stated before its look. Every lab in § (d) opens with one. |
| **Set the dials explicitly and reason them from the brief, never silently use the baseline.** | taste-skill §14 pre-flight, first two boxes | The baseline (8/6/4) is wrong for us in every case (see Tension ①). Stating the number makes the deviation visible. |
| **The mode names what the visitor's success looks like on this surface** — Operate = *"the visitor completes a task… Scanability, consistency, native expectations, and the real usage scene outrank expression. Brand lives in precise details."* | impeccable SKILL.md § Modes | Owner home, request, live are **Operate**. The run report is the one surface with an **Experience** claim, and that is why it gets the expression budget in § (d). |
| **Choose the mode from the requested surface, not the product.** | impeccable SKILL.md § Modes | Stops "the whole app is a task tool" from flattening the report, and stops "the brand is athletic" from decorating the request flow. |
| **Refinement preserves; redesign replaces.** *"Never split the difference into polish on the discarded look."* | impeccable SKILL.md § How to design | Under the style freeze every slice here is refinement. A lab that half-replaces the world is the failure mode this names. |
| **Check the dependency file before importing any library.** | taste-skill §3.F; redesign-skill § Rules | `app/package.json`. A new icon family or animation library is also a new motif and therefore a freeze violation. |

### A2 · The craft floor (impeccable `craft-floor.md`) — verified, not intended

impeccable's framing is the useful part: *"Each of these is a check on the built result, not an
intention."* All eight apply. Four are already `DESIGN.md` law and are listed here because the
skill's phrasing is sharper:

- **Contrast** — *"body and placeholder text ≥4.5:1, large text ≥3:1. On colored surfaces tint
  secondary text from that hue or the foreground; never gray."* The second sentence is new to us and
  is correct: it is the general form of `DESIGN.md`'s two-tier `coralText` / `clubInk` / `terraInk`
  rule.
- **Spacing** — *"tight groups, generous separation, more space above a heading than below it. Read
  the computed values."*
- **Type** — *"Run the real copy at every breakpoint and fix what overflows."* Korean truncates
  harder than Latin (checklist T5), so this is load-bearing rather than pedantic.
- **Motion** — *"one authored moment, not scattered effects and not one identical entrance on every
  section."* This is `DESIGN.md` §8's motion budget said from the other direction.
- **States** — *"hover, disabled, loading, error, empty. Plus real content, working controls,
  responsive composition, keyboard focus."*
- 🔴 **Browser surfaces** — *"the parts you did not draw still carry the design… This is the cheapest
  signal that a page was built rather than assembled, and the one models skip most reliably."* The
  RN translation is exact and we have no rule for it: **the parts we did not draw** are
  `Alert.alert`, the keyboard accessory bar, the `RefreshControl` spinner, the text-selection handles
  and the iOS share sheet. Checklist Tension ⑥ already warns that standard components *"will pick up
  Liquid Glass from iOS automatically, producing mixed chrome no one chose."* Same observation,
  arrived at independently. **Adopted as: every lab states which of its chrome is OS chrome and
  therefore not ours to style.**
- **Copy** — *"the product's own language. Controls name their action; errors name the problem and
  the recovery."* Identical in intent to `DESIGN.md` §7's dark-state rule.
- **Coverage** — *"every brief requirement present and findable within seconds."*

### A3 · Operate mode (impeccable `operate.md`) — the closest match to our product

- **The product slop test**, verbatim: *"Product UI's failure mode isn't flatness, it's strangeness
  without purpose: over-decorated buttons, mismatched form controls, gratuitous motion, display
  fonts where labels should be, invented affordances for standard tasks. The bar is earned
  familiarity. The tool should disappear into the task."* **This is the single most useful sentence
  in either skill for us**, because it inverts the instinct "premium means more". It also
  independently re-derives `DESIGN.md` §3's rule that Black Han Sans is display-only.
- *"**One family is often right.** Product UIs don't need display/body pairing."* — we have three
  families and each one is budgeted; adopted as a reason the budget exists, not as a demand to cut
  one.
- *"**Tighter scale ratio.** 1.125–1.2 between steps is typical."* — our lab lattice is
  15/19/24/30, i.e. ratios 1.27/1.26/1.25. Slightly wider than Operate's typical. Fine, and worth
  knowing it is a deliberate edge rather than an accident.
- **Motion: *"150–250 ms on most transitions. Users are in flow; don't make them wait for
  choreography."*** — adopted as the hard ceiling for every lab in this set: **≤240 ms**.
- ***"No orchestrated page-load sequences. Product loads into a task; users don't want to watch it
  load."*** — adopted, and it is the rule that kills soft-skill's staggered mask reveal (Tension ⑥).
- *"Skeleton states for loading, not spinners in the middle of content."* — we already do better:
  `docs/design/loading-state-audit.md` measured **46 of 59 routes naming their loading state in a
  Korean sentence, 2 with a `Skeleton` block, and zero production `ActivityIndicator`.** The house
  idiom is a sentence. Adopted with that amendment.
- *"Empty states that teach the interface, not 'nothing here.'"* — matches `DESIGN.md` §7's
  fix-path rule exactly.
- *"Every interactive component has: default, hover, focus, active, disabled, loading, error. Don't
  ship with half of these."* — on touch, `hover` drops out and `pressed` is the real state; the rest
  hold.

### A4 · iOS (impeccable `ios.md`) — where it does not collide with §DESIGN.md

- **The iOS slop test:** *"The tell is 'ported from a website': reinvented navigation bars, custom
  back gestures, web-shaped buttons, hover-dependent affordances."*
- *"**Safe area.** Lay out inside the safe-area insets."* — landed 2026-09-17 (`d3d56ea`, 49 route
  files).
- *"**44×44 pt minimum** for every tappable control, with breathing room between adjacent
  targets."* — agrees with `DESIGN.md` §7b; checklist G1 has the open measurement.
- *"**Edge-swipe back stays alive.**"* — with one known, deliberate exception: `_layout.tsx:22`
  disables it because the slide-to-book slider owns the screen edge (checklist G4). That exception is
  queued for Sean, not silently kept.
- *"**Deliberate modality.** Sheet for a focused dismissible sub-task… Clear Cancel/Done; honor
  swipe-to-dismiss unless data loss requires a guard."*
- *"**Simulators give breadth; posture, gestures, and performance need hardware.** Say which one
  produced the evidence."* — this is `CLAUDE.md`'s own never-claim-device-visual-success law, written
  by someone else. Good sign.

### A5 · Interactive states, forms and copy (taste-skill §4.5, §4.6, §4.9)

Every one of these survives the native-mobile scope cut, because they are about states and strings
rather than about web layout:

- *"**BUTTON CONTRAST CHECK (mandatory, a11y):** Before shipping any button, verify the button text
  is readable against the button background… Same rule applies to ghost buttons over photographic
  backgrounds (use a backdrop, scrim, or stroke)."* — the photographic case is ours: the run report
  puts labels near photos.
- *"**CTA BUTTON WRAP BAN (mandatory):** Button text MUST fit on one line at desktop."* — translate
  "desktop" to **390 pt**, the narrow phone width. A wrapped Korean CTA at 390 pt is a defect.
- *"**NO DUPLICATE CTA INTENT (mandatory):** Two CTAs with the same intent on one page is a
  Pre-Flight Fail… pick ONE label and use it everywhere."* — this is `DESIGN.md` §7b's
  *"Two ink CTAs cancel each other out"* from the copy side rather than the emphasis side.
- *"Label ABOVE input… **No placeholder-as-label. Ever.**"* (§4.6)
- *"**COPY SELF-AUDIT (mandatory before ship):** Before declaring any task done, re-read every
  visible string on the page… If unsure whether a string makes sense, replace it with a plain
  functional sentence. AI-generated cute copy is worse than boring copy."* — the last sentence is
  `DESIGN.md` §7a-bis's baby-work ruling arrived at from a different direction.
- *"**Fake-precise numbers are flagged.**"* — three allowed states: real data, *"explicitly labeled
  as mock (`<!-- mock -->`, 'example', 'sample data')"*, or banned. Our labs take the middle one and
  say so in the header; the app takes the first one or omits the element.
- *"**One copy register per page.**"*

### A6 · Motion and performance mechanics (taste-skill §5.D, §6.A, §6.B; soft-skill §6)

- *"Animate ONLY `transform` and `opacity`. Never animate `top`, `left`, `width`, `height`."*
  (taste §6.A) — **this is `DESIGN.md` §6 verbatim in a different language.** Two independent
  sources, same rule; that is worth more than either alone.
- *"Use `will-change: transform` sparingly — only on elements that will actually animate."*
- *"**Any motion above `MOTION_INTENSITY > 3` MUST honor `prefers-reduced-motion`. This is
  non-negotiable.**"* (taste §6.B) — RN equivalent `AccessibilityInfo.isReduceMotionEnabled()`,
  already named in `DESIGN.md` §7c. In the labs, `@media (prefers-reduced-motion: reduce)`.
- *"Apply grain / noise filters EXCLUSIVELY to fixed, `pointer-events-none` pseudo-elements…
  NEVER on scrolling containers — continuous GPU repaints destroy mobile FPS."* (taste §6.E,
  soft-skill §6) — directly relevant to `owner/fitness.tsx`'s hardware-textured dot ring, which is
  frozen for exactly this reason.
- *"**Z-Index Restraint.** NEVER spam arbitrary `z-50` or `z-10`."* (taste §6.F, soft-skill §6)
- *"**Blur Constraints:** Apply `backdrop-blur` only to fixed or sticky elements… Never apply blur
  filters to scrolling containers."* (soft-skill §6) — narrower than `DESIGN.md` §7c (*"a dark
  artifact may carry blur, chrome may not"*) and compatible with it.
- *"**MOTION MUST BE MOTIVATED (mandatory).** Before adding any animation, ask: 'what does this
  animation communicate?' Valid answers: hierarchy, storytelling, feedback, state transition.
  Invalid answer: 'it looked cool'… If you cannot articulate the reason in one sentence, drop the
  animation."* (taste §5) — the general form of `DESIGN.md` §6's honest-motion law. Adopted, and
  every motion note in the four labs states its one sentence.

### A7 · Content and naming hygiene (minimalist-skill §2, taste-skill §9.D)

- *"DO NOT use generic placeholder names like 'John Doe', 'Acme Corp', or 'Lorem Ipsum'. Use
  realistic, contextual content."* — our labs use plausible Korean dog and runner names and label
  them as sample.
- *"DO NOT use AI copywriting clichés: 'Elevate', 'Seamless', 'Unleash', 'Next-Gen',
  'Game-changer', 'Delve'."*
- *"**Exclamation marks in success messages.** Remove them. Be confident, not loud."* and
  *"**'Oops!' error messages.** Be direct."* (redesign-skill § Content) — a real check against our
  Korean strings, where the equivalent slip is 「앗!」 and 「완료되었어요!」.
- *"Body text must never be absolute black (`#000000`)."* (minimalist §3) — we already ship
  `paper.ink #111111`. Agreement.
- *"**Numbers in proportional font.** Use… `font-variant-numeric: tabular-nums` for data-heavy
  interfaces."* (redesign-skill § Typography) — we already do (`type.display`, `type.numeric`).
- *"**Orphaned words.** Single words sitting alone on the last line. Fix with `text-wrap: balance`."*
  (redesign-skill) — no RN equivalent exists, so this is a lab-only rule; in RN the fix is a manual
  `\n` in the Korean string, which we already do on display copy.
- *"**Mathematical alignment that looks optically wrong.**… Icons next to text, play buttons in
  circles, or text in buttons often need 1-2px optical adjustments to feel right."* (redesign-skill)
  — new to us and worth having.

### A8 · Mobile screen anatomy (imagegen-frontend-mobile)

This file is written for image generation, not code, but four of its rules are about screens rather
than images and transfer cleanly:

- **§12 First screen cleanliness:** *"use one primary focal point / keep the top screen area
  controlled / keep the headline short / do not overload the first viewport / do not fill it with
  extra stats, chips, tags, or pills / do not bury the main CTA… if imagery is used behind text,
  preserve clear readability with fades, masks, or soft scrims."* Preference stated as *"1 to 3
  short lines for the main statement / concise supporting text / one clear next action"* — which is
  `DESIGN.md` §7a-bis's word budget within rounding.
- **§13 Safe area:** design with awareness of *"safe areas / status bar region / top bar or title
  region / bottom navigation region / home indicator region / sheet docking zone / gesture space"*,
  and *"Mobile images should feel like real app screens, not posters."*
- 🔴 **§15 Clean layout:** *"Do not default to box-in-box-in-box mobile UI… giant nested card stacks
  / floating surfaces everywhere / 5 levels of framing… A premium mobile screen should not feel
  trapped inside too many boxes."* **This is Sean's own 2026-08-25 ruling in a stranger's words:**
  *"clean look without cards within cards."* Adopted with force.
- 🔴 **§29 Text size:** *"Text must never feel too small. Strong rule: if the text feels small, the
  design is not finished yet… If a design choice makes text too small: simplify the layout / reduce
  content / increase spacing / enlarge the text / split content into another screen if needed…
  Readable beats clever. Readable beats dense. Readable beats decorative small type."* **This is the
  15 pt floor's argument, and specifically `DESIGN.md`'s *"Delete before shrinking"* clause.**
- **§31 Spacing:** *"Do not make the app too dense. The UI should breathe… avoid one screen feeling
  cramped while the next is empty."* The second clause is a cross-screen consistency check we have
  never written down.

⚠ **One correction to a common assumption about these skills.** Neither skill states a numeric
tap-target size anywhere. The 44 pt number in this repo comes from `DESIGN.md` §7b and Apple's HIG
(checklist G1), **not** from taste-skill or impeccable's taste layer. impeccable's `ios.md` is the
only file in either clone that names 44×44, and it names it as Apple's rule. Do not cite the taste
skills for it.

---

## (b) Where `DESIGN.md` already covers it, or contradicts it — Tensions for Sean

**`DESIGN.md` wins in every row below. Nothing here has been acted on.** Each tension is one line of
conflict plus a recommendation. The format follows
`docs/design/hig-conformance-checklist.md` § Tensions for Sean, and where a conflict is already
queued there, this file points at it instead of duplicating it.

### ① Dial baseline 8/6/4 vs the style freeze and the paper grammar

- **taste-skill §1:** *"**Baseline:** `8 / 6 / 4`."* At `DESIGN_VARIANCE 8-10` the skill's own §7
  prescribes *"Masonry layouts, CSS Grid with fractional units… massive empty zones
  (`padding-left: 20vw`)"*, and §4.3 says *"Centered Hero / H1 sections are avoided when
  `DESIGN_VARIANCE > 4`."*
- **`DESIGN.md` §4:** *"Section division by full-bleed hairline, not by cards."* §8: emphasis budget
  is *"coral line + 1 CTA."* Header: *"no NEW aesthetics until 50 paying dogs."*
- **Recommendation: use the skill's *mechanism* (state the dials) and reject its *defaults*.** The
  dial settings this file proposes are in § (d) and every one of them is well under the baseline. An
  asymmetric masonry owner home is a new aesthetic and therefore a freeze violation regardless of
  whether it is good. **No ruling needed unless Sean wants the freeze lifted.**

### ② The eyebrow / kicker — three documents, three positions, and `DESIGN.md` is two of them

- **impeccable `craft-floor.md`** bans it outright: *"A kicker or eyebrow above a heading. This one
  is a ban, not a default: no brief earns it back. The heading carries its own weight; delete the
  label and let the heading speak."*
- **taste-skill §4.7** rations it: *"**Maximum 1 eyebrow per 3 sections.**… Pre-Flight Check is
  mechanical: count instances of `uppercase tracking`… If count > ceil(sectionCount / 3), the output
  fails."* It calls this *"the #1 violated rule in production tests."*
- **`DESIGN.md` §3b** agrees with impeccable, for section headers: *"**No latin kicker** ('ROSTER',
  'VERIFIED COURSES', 'HIGH CLUB', 'NEXT RUN · BOARDING PASS'). They were decoration that competed
  with the title and made every section look different. **Retired app-wide.**"*
- ⚠ **But `DESIGN.md` §2's paper chrome grammar keeps one:** *"**Kickers**: latin letterspaced caps,
  `paper.faint` (the 'PAYMENT' / 'MOCK · 준비 중' grammar)."* And §3's type scale reserves a
  sub-15 pt tier specifically for *"LATIN letterspaced caps kickers"*.
- **Recommendation: read the two `DESIGN.md` clauses as one rule with a seam, and say so.** §3b
  retired the kicker **as a section header's eyebrow**; §2 keeps it **as the artifact grammar's
  label** — a serial, a state stamp, a document class marker on a ticket or receipt. Those are
  different objects. **The proposed wording, for Sean to accept or reject: a latin kicker may label
  an artifact, never announce a heading.** Under that reading impeccable's ban and `DESIGN.md` agree
  completely and taste-skill's rationing is unnecessary. This is a one-line clarification to
  `DESIGN.md` §2, not a design change — **but it is a `DESIGN.md` edit and therefore Sean's.**

### ③ Fonts — every skill bans the neutrals and prescribes a shopping list

- **soft-skill §2:** *"**Banned Fonts:** Inter, Roboto, Arial, Open Sans, Helvetica. (Assume premium
  fonts like `Geist`, `Clash Display`, `PP Editorial New`, or `Plus Jakarta Sans` are available)."*
  **minimalist-skill §3** prescribes an *"Editorial Serif (Hero Headings & Quotes): `Lyon Text`,
  `Newsreader`, `Playfair Display`, `Instrument Serif`."* **taste-skill §4.1** bans Inter as a
  default and bans `Fraunces` / `Instrument_Serif` as display serifs — i.e. **taste-skill bans a font
  minimalist-skill prescribes.** The two clones disagree with each other.
- **`DESIGN.md` §3:** Black Han Sans display (once per screen), Oswald 600 numerals, and a body face
  that is **explicitly contested and unresolved**. The header freeze: *"new colors, fonts, or motifs
  are not"* freeze-compliant.
- **Recommendation: no font from any of these lists enters this product, and the labs keep the
  system Korean stack.** These skills are Latin-first: none of them names a Korean face, and a
  premium Latin display face applied to Hangul is the exact "ported from a website" tell impeccable's
  `ios.md` warns about. **No ruling needed.** The one question that *is* open — IBM Plex Sans KR,
  product-wide or labs-only — is already `DESIGN.md` §3's own flagged conflict and checklist
  Tension ⑤; it stays there and is not re-litigated by a third-party skill's preference.

### ④ Dark mode "mandatory"

- **taste-skill §6.C:** *"**Dark Mode (mandatory for any consumer-facing page)**… Never ship
  light-only or dark-only without explicit user instruction."* §8 adds a whole Dark Mode Protocol.
  **impeccable `ios.md`:** *"**Dark Mode is a first-class appearance.** Design and test both."*
- **`DESIGN.md` §1:** *"'Dark is the artifact, light is the screen' — dark surfaces are reserved for
  ceremony objects… never for chrome."* `app/app.json` → `userInterfaceStyle: "light"`.
- **Recommendation: already queued, do not duplicate.** This is checklist **Tension ③** and its
  recommendation stands: leave it, and write the reason into `DESIGN.md` §2 so a future session does
  not "add dark mode" as a polish item and quietly void the artifact law. Two more skills asking for
  dark mode is not new evidence; it is the same category default counted three times.

### ⑤ 🔴 soft-skill's core mechanism is nested enclosures — which Sean banned by name

- **soft-skill §4.A, the "Double-Bezel":** *"**Never** place a premium card, image, or container
  flatly on the background. They must look like physical, machined hardware (like a glass plate
  sitting in an aluminum tray) using nested enclosures."* Concretely: an outer shell at
  `rounded-[2rem]` with `p-1.5`, an inner core at `rounded-[calc(2rem-0.375rem)]` with an inset
  white highlight; buttons as `rounded-full` pills with a nested circular icon wrapper.
- **`DESIGN.md` §2/§3b:** *"Cards: radius 0."* *"Radius 0 everywhere including the club card."*
  **Sean, 2026-08-25, verbatim:** *"clean look without cards within cards."* **§4:** *"a card must BE
  the interaction (ticket, stub) to earn existence."*
- **And the two skills contradict each other here too:** minimalist-skill §2 bans what soft-skill
  mandates — *"DO NOT use `rounded-full` (pill shapes) for large containers, cards, or primary
  buttons"*, radius *"`8px` or `12px` maximum"*.
- **Recommendation: reject the mechanism outright, keep the *intent*, and note what we already have
  instead.** soft-skill's intent is **concentric physical hierarchy**; our version of it is the
  **4 px pressed-fill lip** on filled buttons (`DESIGN.md` §3b, Sean 2026-08-26: *"all primary
  buttons should have a 3d kinda thing like you gave in the lab as well"*), where *"the 3px the edge
  gives up is exactly the 3px the transform takes, so the bottom edge stays put and the key descends
  into it."* That is a more disciplined depth device than a bezel and it already has a press state.
  **No ruling needed. Recorded because a future session reading soft-skill will find "premium =
  nested enclosures" and it is wrong here.**

### ⑥ Motion: 700–800 ms cinematic entrances vs 150–250 ms task motion

- **soft-skill §5:** *"`transition-all duration-700 ease-[cubic-bezier(0.32,0.72,0,1)]`"*; scroll
  entries *"over 800ms+"*; *"Staggered Mask Reveal"* with `delay-100/150/200`.
- **impeccable `operate.md`:** *"150–250 ms on most transitions. Users are in flow; don't make them
  wait for choreography."* and *"**No orchestrated page-load sequences.** Product loads into a task;
  users don't want to watch it load."*
- **`DESIGN.md` §6:** *"an animation may only claim what the system knows… No idle loops, no fake
  progress."* §7c: springs *"critically damped (`damping 1.0`, response 0.3–0.4)"*, bounce **only**
  after a gesture that carried momentum.
- **Recommendation: `DESIGN.md` + Operate win; soft-skill's motion section is for marketing pages.**
  **Every lab in this set caps CSS transitions at 240 ms and ships zero entrance choreography.**
  ⚠ The one thing worth stealing is soft-skill's *"Never use default transitions"* — `ease-in-out`
  is a tell. Our curve is `cubic-bezier(0.16, 1, 0.3, 1)` (exponential ease-out), which is what
  `craft-floor.md` asks for by name: *"Exponential ease-out from an already-visible default."*
  **No ruling needed.**

### ⑦ 🔴 "Real images or it is slop" vs "bind a real field or omit the element"

- **taste-skill §4.8:** *"Text-only pages with fake-screenshot divs are slop… **Div-based fake
  screenshots are banned**… **Hero needs a real visual.** Text + gradient blob is not a hero - it's a
  placeholder."* Its prescribed fallback is `https://picsum.photos/seed/{descriptive-seed}/{w}/{h}`.
  **minimalist-skill §6** says the same. **imagegen §17** bans *"perfectly sterile flat
  backgrounds."*
- **`CLAUDE.md` § Honesty laws:** *"No mockups, fake numbers, or fabricated data in the app: bind
  real fields or omit the element."* **`DESIGN.md` §8:** photos are budgeted — *"5 content slots,
  wallpaper forbidden."*
- **This is a genuine collision and it is the sharpest one in this file.** A stock photo of a dog in
  a mock of the run report is, by the house's own definition, fabricated data on the exact surface
  whose entire claim is that the run happened.
- **Recommendation, and it is a real design decision rather than a dodge: in a lab, a photo slot is
  drawn as a labelled empty frame at its true aspect ratio, never as a stock image.** The frame
  carries the field it will bind (`인증샷 · shot/[bid]`), so the lab shows the *composition* honestly
  and shows nothing it cannot back. taste-skill's own §4.8 already licenses this as its third option:
  *"leave clearly-labeled placeholder slots (`<!-- TODO: hero product photo, 1600x1200 -->`)"* — it
  just ranks it last. **We rank it first, and the reason is a house law rather than laziness.**
  ⚠ **Where this costs us something, stated plainly:** a lab that never shows a photograph cannot
  answer "does this composition survive a real photo", and the run report lives or dies on that.
  **The honest mitigation is a device smoke with a real run's photos, not a prettier lab.** Sean may
  reasonably rule the other way for labs specifically — the labs are already the sanctioned mockup
  arena, so a picsum image there breaks no shipped law. **That is his call and it is worth asking.**

### ⑧ Glyphs as icons

- **impeccable `craft-floor.md`:** *"Unicode glyphs or emoji standing in for an icon system. Icons
  are drawn, from a real library or authored SVG, in one consistent stroke and weight."*
- **`DESIGN.md` §7b (Sean 2026-08-11):** *"Monochrome typographic glyphs (› ‹ ✓ ✎ ◐ ● § ★) are ink,
  not pictures, and remain in the sanctioned glyph class."*
- **Recommendation: `DESIGN.md` wins, and the two are closer than they look.** impeccable's target is
  **emoji-as-icon**, which `DESIGN.md` §7b bans in the same breath. The app already ships a real icon
  library (Lucide, via `app/src/components/icon.tsx`, `bottomnav.tsx:38-50`) for actual affordances,
  with the glyph as the fallback face. What `DESIGN.md` protects is the **typographic** glyph in an
  ink-and-paper system, which is a deliberate world, not a missing icon set. **No ruling needed.**
  ⚠ One live sub-conflict: taste-skill §3.C and soft-skill §2 both **discourage Lucide by name**
  (*"Banned Icons: Standard thick-stroked Lucide"*). taste-skill's own override covers us: Lucide is
  *"Acceptable only when the user explicitly asks for it **or the project already depends on it**."*
  It does. **And swapping icon families is a new motif = freeze violation.** Recorded so nobody
  "upgrades" to Phosphor.

### ⑨ Shadows — three different depth languages, one of them ours

- **soft-skill §2** bans *"Generic 1px solid gray borders"* and *"Harsh, dark drop shadows"* and
  prescribes hairline rings plus *"unbelievably soft, highly diffused ambient shadows"*.
  **minimalist-skill §2** wants shadows *"practically non-existent… (< 0.05)"* but mandates
  *"exactly `border: 1px solid #EAEAEA`"* on cards. **impeccable `craft-floor.md`** says
  *"shadows carry an offset and a soft blur. A zero-offset colored halo is decoration"* and, in its
  codex block, *"**Declare elevation once, border or shadow.** A 1px border under a wide soft shadow
  is the ghost card."*
- **`DESIGN.md` §2:** *"Soft shadows retire with the rounded corners (shadow only where a floating
  surface genuinely floats, e.g. the request floating ticket)."* §3b: *"**A drop shadow and a lip are
  two different depth languages and must not sit on one control.**"*
- **Recommendation: `DESIGN.md` wins and impeccable's "declare elevation once" is the same rule one
  level up.** Our elevation is declared as **the coral hairline**, and our depth as **the lip**.
  **No ruling needed.** Worth noting that `DESIGN.md` §3b reached the "two depth languages" rule by
  retiring `ClubCta`'s shadow after a day of carrying both — measured, not theorised.

### ⑩ Dynamic Type

- **impeccable `ios.md`:** *"**Dynamic Type.** Use the system text styles… **No hard-coded point
  sizes.**"*
- **`DESIGN.md` §3b:** *"Size, weight and lineHeight are universal."*
- **Recommendation: already queued as checklist Tension ①, which has the mechanical resolution
  (floor = the value at the default size, fixed `lineHeight` becomes a ratio). Do not re-open it
  here.** Listed only so a session reading this file does not think a third skill's agreement changes
  the answer.

### ⑪ The em-dash ban — measured, and the answer is NOT the one the skill wants

- **taste-skill §9.G:** *"**Em-dash (`—`) is COMPLETELY banned.**… There is no 'limited use'
  allowance… If your output contains a single `—` or `–` anywhere visible to the user, the output
  fails the Pre-Flight Check and must be rewritten."* It calls this *"the single most-violated
  Tell."*
- **`DESIGN.md`:** silent.
- 🔴 **Measured before recommending anything, because the first draft of this row got it wrong.**
  `grep -rn "—" app/app app/src | grep -P "[가-힣]"` → **4,643 lines**, of which **2,851 look like
  comments**, leaving **~1,792 lines of Korean carrying an em-dash in code**. The screen-truth read
  of the four target screens confirms it is the standard separator in shipped product copy:
  *"이 시간대엔 조명이 없는 코스예요 — 다른 코스나 시간을 확인해주세요"*,
  *"네트워크를 확인해주세요 — 러닝과 기록은 그대로 진행돼요"*,
  *"켜짐 — 좌표는 빠지고 모양만 들어가요."*
- **Recommendation: do NOT adopt the ban, and do not adopt a softened version either.** At ~1,792
  sites this is a copy rewrite of the entire product, the separator is doing real syntactic work in
  Korean sentences that would otherwise need a second sentence, and no ruling asks for it. The
  skill's rule was written against Latin marketing headlines where the em-dash is a decorative pause;
  ours is a functional clause separator. ⚠ **This file's first draft recommended adopting it for
  Korean copy. That was a recommendation made before the measurement, which is exactly the shape
  `CLAUDE.md` warns about — a hedge that becomes a premise. Recorded rather than quietly fixed.**
- ⚠ **But the measurement surfaced a narrower thing that IS worth Sean's attention, and it is a
  different rule wearing the same character.** A large share of those non-comment hits are the bare
  string `'—'` used as a **no-value placeholder**. `docs/design/loading-state-audit.md` already flags
  two of them as honesty defects: *"`app/app/settings.tsx:94` renders `'—'` identically while
  loading and after failure"*, and `my.tsx:201-202` the same. Meanwhile `owner/report.tsx` does it
  correctly: a null measurement renders the words **`기록 없음`**, never a figure and never a dash.
  **The proposal: `기록 없음` is the house word for "the server has no measurement", and a bare
  `'—'` is not allowed to stand in for it** — because a dash cannot distinguish *loading* from
  *failed* from *genuinely absent*, which is the `loading ≠ 0 ≠ empty` law. That is a real rule with
  a worked example already in the codebase, and it is the useful residue of a skill rule that
  otherwise does not apply.

### ⑫ 🔴 The GO state law's blue is shipped as the accent violet it was defined against

**This one is a measured defect in the law's own anti-collision clause, found while grounding the
labs, and it is the only row here that is not a skill conflict at all.**

- **`DESIGN.md` §5, verbatim:** *"Blue = system's turn (searching `#5B82E8`, directed `#4468CC` —
  **periwinkle, deliberately green-shifted so it can never be confused with accent violet
  `#6C5CE7`**)."*
- **Measured on trunk.** `grep -rn "5B82E8\|4468CC" app/app app/src` → **0 hits.** The shipped value
  is `app/src/components/home-hero.tsx:102`:
  ```
  const WAIT_BLUE = '#6C5CE7'; // lilac.accent — 대기
  ```
  used for both the `찾는 중` and `응답 대기` chips (`home-hero.tsx:274-275`). **The waiting state
  ships in exactly the colour the law says it must never be confused with.**
- **Two further stale values in the same law**, same method: `GO_TINT` — the hero card's 95 % white
  wash of the current state colour, named in `DESIGN.md` §5 and `CLAUDE.md` § Design system — **has
  zero occurrences in `app/`**, because the GO disc was retired on 2026-08-19 (Sean: *"A"*) and
  `home.tsx:36-51` records the removal of *"GO 디스크의 잔해 전부"*. And §3b's ready green `#12A05C`
  is superseded by `paper.ready #119B58`, which `theme.ts:221-224` already records as a correction
  (*"법전이 존재하지 않는 색을 지정하고 있었다"*).
- **Recommendation, and it is genuinely two questions, not one.**
  **(a) Which is right — the law or the code?** If the periwinkle was the decision, the code is a
  regression and `home-hero.tsx` changes. If violet-as-waiting was a deliberate later choice, §5's
  parenthetical is stale and should be struck. **Nobody can tell from the artifacts, which is why
  this is a question and not a fix.** ⚠ Note the constraint that makes (a) non-trivial: `DESIGN.md`
  §2 rules `#6C5CE7` *"accent ONLY — never a ground or wash"*. The current use is a chip dot and
  chip text, which is an accent use and therefore legal under §2 — so the code does not obviously
  violate anything except §5's own sentence.
  **(b) Separately: `DESIGN.md` §5 and `CLAUDE.md` § Design system both still describe a GO disc and
  a `GO_TINT` that no longer exist.** That is the stale-extract failure this repo has now recorded
  three times (the 15 pt floor line, the 「Sean pushes」 line, the club-world floor line). It is a
  documentation fix, it is cheap, and it is Sean's file. **The four labs in this set are drawn
  against the CODE, not against §5**, and say so in their own headers.

---

## (c) The anti-slop checklist we adopt

Scoped to what can actually occur in a React Native app or in one of our HTML labs. Every line is
quoted from the skill that names it; items that cannot occur here (RSC boundaries, Next.js fonts,
logo walls, marquees, pricing matrices) are dropped rather than reworded.

### C1 · Banned outright (both skills agree, and `DESIGN.md` does not object)

| # | Pattern | Quoted source |
|---|---|---|
| 1 | **Gradient text** | *"Gradient text. Emphasis comes from weight or size."* — impeccable craft-floor. Also taste §9.A: *"NO excessive gradient text for large headers."* |
| 2 | **Glassmorphism as decoration** | *"Glass and blur as decoration rather than as a specific effect."* — impeccable craft-floor. Compatible with `DESIGN.md` §7c's blur limit. |
| 3 | **Side-stripe borders** | *"A colored `border-left` or `border-right` above 1px on cards, list items, callouts, or alerts."* — impeccable craft-floor (`skill-ban-side-stripe-borders`). **See the measured note below — we have already failed this one.** |
| 4 | **Identical-card grids as page structure** | *"Same-size cards of icon plus heading plus text as the page structure. Cards are the lazy container; **nested cards are always wrong**."* — impeccable craft-floor. Also taste §9.C: *"NO 3-column equal feature cards."* And Sean: *"clean look without cards within cards."* |
| 5 | **The hero-metric template** | *"big number, small label, supporting stats, accent."* — impeccable craft-floor. ⚠ Scope carefully: a run report's km figure **is** the content, not a template. The ban is on the decorative stat row beside it. |
| 6 | **Section numbers as decoration** | *"Section numbers (01 / 02 / 03) unless the sequence itself carries information the reader needs."* — impeccable craft-floor. Identical to `DESIGN.md` §3b: *"Numbered chips (01/02) only inside a genuinely ordered sequence; never as decoration."* |
| 7 | **Decorative status dots** | *"**ZERO decorative status dots by default.** A coloured dot before nav items, before list rows, before badges… is a Tell. Only acceptable when conveying real semantic state."* — taste §9.F. Our LIVE dot conveys real state and survives. |
| 8 | **Pulsing / infinite idle loops** | *"**Perpetual Micro-Interactions** (Pulse, Typewriter, Float, Shimmer…): Use when `MOTION_INTENSITY > 5` AND the section actively benefits… **Not every card needs an infinite loop.**"* — taste §5. `DESIGN.md` §6 is stricter and wins: the GO disc breathes **only** during matching/LIVE, *"idle에 돌리면 거짓 모션"*. |
| 9 | **Emoji as icons** | *"DO NOT use emojis anywhere in code, markup, text content, headings, or alt text."* — minimalist §2. `DESIGN.md` §7b bans them for the reason that matters here: they *"render as cheap color images against an ink-and-paper system."* |
| 10 | **Hard offset block shadows** | *"Hard offset shadows (`box-shadow: 4px 4px 0`) outside a world that is actually neobrutalist. The zero-blur block shadow is a costume, not a depth system."* — impeccable craft-floor. ⚠ Read it against the 4 px **lip**, which is a border, has a press state, and is not a shadow. |
| 11 | **Mono as a costume for "technical"** | *"Monospace as a costume for 'technical' rather than for code, data, or measurement."* — impeccable craft-floor. Our numerals are Oswald, an athletic condensed, not a mono; our `.serial` class is measurement. |
| 12 | **Decorative chrome standing in for content** | *"Sparklines, progress rings, and soft-shadowed rounded rectangles standing in for content."* — impeccable craft-floor. Also taste §9.F: *"NO scoring/progress bars with filled background tracks as comparison visuals."* |
| 13 | **Modal by reflex** | *"A modal for a task that needs neither interruption nor protected focus."* — impeccable craft-floor; *"Modals are usually laziness."* — impeccable operate. |
| 14 | **"Jane Doe" content** | *"NO generic names… NO generic avatars… NO fake-perfect numbers… NO startup-slop brand names… NO filler verbs."* — taste §9.D. |
| 15 | **Scroll cues** | *"Scroll cues are banned. `Scroll`, `↓ scroll`, `Scroll to explore`, animated mouse-wheel icons."* — taste §9.F. Applies to our labs, which have no business teaching anyone to scroll. |
| 16 | **Locale / time / weather strips as decoration** | *"Locale / city-name / time / weather strips are banned for 99% of briefs."* — taste §9.F. ⚠ **Ours is in the 1%:** the mock status bar's 9:41 is a device frame convention, and 반포 is the pilot's real scope, not atmosphere. |
| 17 | **Micro-meta sentences under a heading** | *"NO micro-meta-sentences under eyebrows."* — taste §9.F. Identical to `DESIGN.md` §3b: *"**No section subtitle**… If the title doesn't say it, the section is misnamed."* |
| 18 | **`border-t` + `border-b` on every row of a list** | *"Pick one… and use it sparsely. A 10-row spec table with hairlines under each row is the laziest layout."* — taste §9.F. |
| 19 | **Sketch-style / hand-rolled decorative SVG** | *"Real illustration or none. Sketch-style SVG scenes, `loose-sketch` / `doodle` class names, and `feTurbulence` grain read as amateur."* — impeccable craft-floor (codex). ⚠ It explicitly does **not** ban SVG doing geometry — our dot rings, route lines and stamps are geometry and survive. |
| 20 | **Geometric masks faking an organic cut-out** | *"A circle, polygon, or radial-gradient cutout approximating a photographic subject's edge is the cheap version of the effect."* — impeccable craft-floor. Relevant the moment a dog photo meets a shaped frame. |

### C2 · The "AI beige" ban, and why it does not fire here

taste-skill §4.2 carries a **PREMIUM-CONSUMER PALETTE BAN (mandatory, second-most-recurring AI-tell)**
with named hex families: backgrounds *"`#f5f1ea`, `#f7f5f1`, `#fbf8f1`, `#efeae0`, `#ece6db`,
`#faf7f1`, `#e8dfcb` (all 'warm paper / cream / chalk / bone')"*, accents *"`#b08947`, `#b6553a`,
`#9a2436`, `#9c6e2a`, `#bc7c3a`, `#7d5621` (all 'brass / clay / oxblood / ochre')"*, text
*"`#1a1714`, `#1a1814`, `#1b1814`"*. Its argument: *"Every premium-consumer site you have ever
shipped uses this exact palette. The brand becomes invisible."*

**Measured against `app/src/theme.ts`: we are clean, and the interesting part is that we got here by
a different route.** `paper.canvas` is `#FFFFFF`, `paper.ink` is `#111111`, the accent is a coral
`#E8552F` / `#C6472C`. Sean retired the warm grounds himself on 2026-08-25 (*"white backgrounds"*),
and `DESIGN.md` §2 records the beige retirement a year's worth of labs earlier (*"[V4] 페이퍼 —
베이지 박멸"*, `theme.ts:8`). ⚠ **Two survivors sit near the banned family and are both scoped, not
accidental:** `colors.terraCraft #F8F0E7` (shop screens only, the *"부티크 온도"* separation) and
`colors.goldTint #FBF3DD` (milestone events only). Both are jurisdictional under `DESIGN.md` §2 and
neither is a default ground. **Adopted as a standing check rather than a fix: any new warm ground
outside those two jurisdictions is this tell.**

### C3 · The tells this repo has actually produced — measured, not hypothetical

🔴 **impeccable's detector has already run against our labs, and it found something.**
`.impeccable/hook.cache.json` is committed to this repo (landed in `32bc1cc1`) and records two
sessions of hook runs on the old Mac's worktree path. Parsed:

| rule fired | count | files |
|---|---|---|
| `side-tab` (the side-stripe border ban, C1 #3) | 13 | `enh-owner-live-lab` · `enh-club-lab` · `enh-owner-home-lab` · `enh-runner-run-lab` · `enh-runner-home-lab` · `enh-account-lab` · `enh-runner-money-lab` |
| `dark-glow` | 3 | same set |

⚠ **The crude control, run beside it per the house rule, and the numbers do NOT match.**
`grep -ciE "border-(left|right):\s*[2-9]"` over those seven files returns **18 lines** today against
the detector's **13 findings**, and the per-file counts differ **in both directions** (live: 4
detector / 2 raw lines; club: 6 / 7). Two reasons, both real: a single CSS line can carry more than
one declaration, and **the cache is a snapshot taken at edit time in a worktree that no longer
exists** (`/Users/sean/…`, the old Mac) while the files on trunk have moved on since. **So the
honest claim is "this rule class is present in seven of our labs and a real detector flagged it",
not "there are exactly 13."** The exact count is not established and does not need to be.

**What follows from it:** the side-stripe is our house tell. It is cheap to reach for because the
paper world already speaks in rules and lines, and a 3 px coloured left edge feels like more of the
same. It is not — `DESIGN.md` §2 gives the hairline **one** job, full-bleed and horizontal, and a
vertical coloured stripe is a second, competing emphasis device that the §8 budget does not have room
for. **The four labs in this set contain zero side-stripes, and that is checkable with the grep
above.**

### C4 · Adopted with a scope note

- **Em-dash ban** — **NOT adopted.** Measured at ~1,792 Korean code lines; it is our separator, not
  a tell. What survives is narrower and sharper: a bare `'—'` may not stand in for a missing
  measurement. See Tension ⑪.
- **Eyebrow ban** — as a section heading's label. The artifact kicker survives. See Tension ②.
- **"Real images or it is slop"** — inverted here: labelled empty frames, never stock. See
  Tension ⑦.
- **Hero-metric ban** — the decorative stat row, not the run's own numbers. See C1 #5.

---

## (d) Dial settings per surface

taste-skill §1.C: *"Use these (or user-overridden values) as global variables. Cross-references
throughout this document refer to these exact variable names."* Definitions from §7:
`DESIGN_VARIANCE` 1 = perfect symmetry / 10 = artsy chaos · `MOTION_INTENSITY` 1 = static /
10 = cinematic · `VISUAL_DENSITY` 1 = art gallery / 10 = cockpit.

**Where our numbers come from.** §1.A's inference table gives *"trust-first / public-sector /
regulated / accessibility-critical"* → **3-4 / 2-3 / 4-5** and *"premium consumer / Apple-y /
luxury / brand"* → **7-8 / 5-7 / 3-4**. daengrun is genuinely both: a stranger takes your dog
(trust-first, and §0.A says *"Quiet constraints… **OVERRIDE aesthetic preference**"*), and the
artifact grammar is a premium-consumer claim. **The trust axis wins on task surfaces; the premium
axis is spent on the one ceremony surface.** That is the whole argument for the spread below, and it
is the same argument `DESIGN.md` §7b makes under Peak-End protection.

| Surface | V | M | D | Reasoning |
|---|---|---|---|---|
| **Owner home** (`app/app/owner/home.tsx`) | **4** | **3** | **5** | The daily screen. V4 is §7's "Offset" band — the hero is asymmetric against a symmetric list, nothing more; the collapsing hero is frozen so structural variance is not available anyway. M3 because `DESIGN.md` §6 permits motion only when the system knows something, and the home screen's motion is the state swap plus the press lip. D5 is the honest reading of a screen carrying a hero, a next-run line, the club island and a dock. |
| **Request flow** (`app/app/owner/request.tsx`) | **3** | **3** | **4** | Sean's ask is *"ease of click in flow to a live run"* — a wizard, and taste-skill §13 says it will not make a wizard better. V3 = predictable: the same row shape every step, so the thumb learns one target. M3: motion only on selection and commit. D4: one decision visible at a time. |
| **Live run** (`app/app/owner/live.tsx`) | **3** | **4** | **3** | The one screen read while anxious. V3 because a map plus a state line plus one action needs no composition cleverness. **M4 is the highest in the set and it is earned by the map**: a moving dot is a state truth, which is `DESIGN.md` §6's only licence for motion. D3 because everything that is not the dog's position is noise here. |
| **Run report / shot** (`app/app/shot/[bid].tsx`, `owner/report.tsx`) | **6** | **3** | **3** | **The ceremony surface, and the one the PMF gate actually rides on.** V6 = the artifact can be composed rather than listed; this is where the passport/bib/receipt grammar lives and where `DESIGN.md` §7b's Peak-End exemption applies. M3 anyway: `DESIGN.md` §6 rules the seal stamp plays **once per entity**, so the ceremony is a moment, not a loop. D3 because the numbers need air. |

⚠ **Two honesty notes on these numbers.**
**(a)** Every value is below taste-skill's 8/6/4 baseline on variance and motion, and at or above it
on density. That is not timidity; it is what a trust-first Operate product plus a style freeze
produces, and §0.A explicitly says the quiet constraints override. **If Sean wants bolder, the lever
is the freeze, not the dial.**
**(b)** taste-skill §5 warns *"**Motion claimed, motion shown.** …A static page that claims
`MOTION_INTENSITY: 7` is broken. Conversely, if you cannot ship working motion in the available
scope, drop the dial to 3 and ship a clean static page."* **The labs claim 3-4 and ship 3-4** — CSS
transitions at ≤240 ms with a `prefers-reduced-motion` block, and the motion each one does not have
is stated in a comment rather than implied.

---

## (e) How to run impeccable and taste-skill against this repo

### Install

Both are read-only clones in the session scratchpad right now; neither is installed into this repo.
Commands are quoted from the two READMEs (read 2026-09-17):

```bash
# impeccable — from the project root. README § Installation, Option 1
npx impeccable install
npx impeccable update          # to refresh an existing install

# taste-skill — installs every skill in the repo's skills/ folder
npx skills add https://github.com/Leonxlnx/taste-skill
# or a single one, by its frontmatter `name:` (NOT the folder name)
npx skills add https://github.com/Leonxlnx/taste-skill --skill "design-taste-frontend"
```

### The two context files, and why they are the whole point

impeccable's `SKILL.md` § Setup: the launcher *"loads PRODUCT.md, DESIGN.md, the matching surface
brief, and native-platform guidance when applicable."*

- **`DESIGN.md` already exists at the repo root** and is far richer than anything `impeccable
  document` would generate. **Do not run `/impeccable document` here** — `document.md` records an
  incumbent world into `DESIGN.md`, and pointing it at ours risks overwriting a 정본 with a summary
  of itself.
- **`PRODUCT.md` did not exist.** `docs/design/PRODUCT.md` (this slice) is it, written by hand in
  impeccable's `init` schema. ⚠ **It is at `docs/design/`, not the repo root, which is where
  `init.md` § Step 4 says new files go** (*"New files go at `PROJECT_ROOT/PRODUCT.md`"*). That is a
  deliberate choice — the repo root already carries `CLAUDE.md`, `DESIGN.md`, `TODOS.md` and
  `README.md`, and a fifth root doc competing for authority is the failure this house keeps
  recording. **If Sean wants the skill's launcher to auto-resolve it, the file moves to the root or
  gets a symlink; say so and it is a one-line change.**
- **`init` will otherwise want to interview.** It is designed to ask three focused questions before
  writing. Since the file already exists, `init.md` § Step 1 routes to *"ask what product knowledge
  is stale or missing; do not reopen confirmed fields without a reason."*

### Platform

`PRODUCT.md` § Platform is `ios`. `init.md` § Step 4: *"When the platform you just recorded is
`ios`… load `ios.md`… before any design work."* So a session running impeccable here gets the native
reference automatically — which is exactly the half of the skill that survives our scope cut.

### The command vocabulary, mapped to work that actually exists here

impeccable's 23 commands, and the ones with a real target in this repo today:

| Command | Real target here |
|---|---|
| `critique [target]` | A screen before a redesign slice. Heuristic scoring, no edits. |
| `audit [target]` — native variant `audit.native.md` | The a11y/perf pass. ⚠ Overlaps `docs/design/hig-conformance-checklist.md`, which is better because it is measured against this repo. Use `audit` for what the checklist does not cover, not instead of it. |
| `polish [target]` | The standing use. Freeze-compliant by construction: craft, scale, spacing, tactility. |
| `clarify [target]` | **The highest-value one we are not using.** UX copy, labels and error messages — i.e. the baby-work budget, applied file by file. |
| `harden [target]` | Errors, edge cases, i18n. Points straight at `loading-state-audit.md`'s 8 Tier-1 defects. |
| `layout` · `typeset` · `colorize` | Scoped refinements. `colorize` is the one to be careful with: new colour is a freeze violation. |
| `quieter [target]` | Fits Sean's 「too dense · too much dim text」 direction better than `bolder` does. |
| `distill [target]` | The word budget, structurally. |
| `adapt [target]` — native variant | Device sizes; pairs with the safe-area slice that landed 2026-09-17. |
| **Not applicable** | `live`, `generate` (browser variant modes — this is native RN, there is no page to point a browser at), `document` (see above), `init` (done), `overdrive`, `delight` (freeze). |

### The detector, without the harness

`npx impeccable detect src/` runs the deterministic rules with no LLM and no API key (README
§ CLI). ⚠ **It reads web CSS/markup**, so its honest target here is **`docs/labs/*.html`**, not
`app/**/*.tsx`. That is not a small target: § C3 above is exactly that, and it found a real class of
defect in seven of our labs.

🔴 **Before trusting any count it gives you, run the crude grep beside it and explain every
difference in both directions** — `CLAUDE.md` § THE STANDING RULE. § C3 does this and the numbers did
not match; the conclusion survived anyway, but only because it was stated as a class rather than as a
count.

### The hook — do not turn it on without deciding to

`npx impeccable install` also installs a provider-native hook manifest that *"runs the Impeccable
design detector on direct UI file edits"* (README § Hooks). The README's own security note is worth
quoting before anyone enables it here: *"In Claude Code, installed command hooks run independently of
model-tool approval. The first edit or Stop event can therefore download and cache the engine even if
the session denies the model's launcher command."* **`.impeccable/hook.cache.json` in this repo is
evidence that this already happened once, on the old Mac, and the cache got committed.** That is a
Sean decision, not a session decision. `--no-hooks` skips it for a run.

### What running these skills will NOT do

- It will not tell you whether a screen is honest. Both skills check *looks*; `CLAUDE.md`'s honesty
  laws and `loading-state-audit.md` check *claims*. **Neither is evidence for the other.**
- It will not see Korean typography problems. Every type rule in both clones is Latin-first: measures
  in `ch`, tracking floors tuned for Latin display, serif pools with no Korean face in them. The
  15 pt floor, the kicker exemption and the Black Han Sans budget are ours and no skill will enforce
  them.
- It will not respect the style freeze. `colorize`, `delight`, `bolder` and every "reach past the
  default" instruction in taste-skill §0.D are freeze-hostile by design. **The freeze is the outer
  gate; the skill runs inside it.**

---

## How the labs are structured: ①② inside the paper world, ③ always a departure

Sean's question on seeing the first drafts was *"are you continuing the paper style?"*, and the
answer is now visible in the files rather than in a sentence. In every one of the four labs:

- **① refines what ships** and **② restructures it**, both inside `DESIGN.md`'s paper world.
- **③ is a labelled DEPARTURE** — a black banner above the frame says so, and a red block beside it
  lists the exact `DESIGN.md` clauses it breaks. The departures share one CSS block, commented with
  the same list, so the breakages cannot drift apart between labs.

**Every departure still obeys** white ground, the 15pt Korean floor, real fields only, no gradient
text, no glassmorphism, no emoji as icons, no AI-beige, ≤240 ms transitions, reduced motion, and AA
contrast. **A departure from the paper world is not a departure from the house laws**, and drawing
that line is most of the point: it shows which of `DESIGN.md`'s rules are *style* (radius, shadow,
the hairline, the lip) and which are *law* (honesty, the floor, contrast, motion truth).

🔴 **Every ③ breaks the style freeze by definition**, so none of them can ship without Sean lifting
it. They exist so that "what does holding the freeze cost us" has a picture attached instead of an
argument.

## Files this brief produced

| File | What it is |
|---|---|
| `docs/design/PRODUCT.md` | Product truth in impeccable's `init` schema, every fact cited. |
| `docs/design/premium-taste-brief.md` | This file. |
| `docs/labs/premium-owner-home-lab.html` | Owner home, three variants. |
| `docs/labs/premium-request-flow-lab.html` | Booking request, three variants. |
| `docs/labs/premium-live-run-lab.html` | Owner watching a live run, three variants. |
| `docs/labs/premium-run-report-lab.html` | Post-run report / 인증샷, three variants. |
| `docs/labs/premium-labs-README.md` | What each lab explores, the recommendation, and the questions for Sean by number. |
