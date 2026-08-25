# DESIGN.md — 도그스하이 design law book

Single source of truth for the design system. Consolidated 2026-08-10 from the
scattered canon: CLAUDE.md §Design system, `app/src/theme.ts` (tokens + comment
law), 32 decision labs in `docs/design/` + `docs/labs/`, and the gstack decision
log. Rules here are **governing law with provenance** — accidental patterns in
old screens are not law. When this file and stray code disagree, this file wins;
when this file and CLAUDE.md disagree, tell Sean (CLAUDE.md now points here).

**Style freeze (Sean 2026-08-06): no NEW aesthetics until 50 paying dogs.**
Craft, scale, spacing, and motion-tactility polish are freeze-compliant; new
colors, fonts, or motifs are not. Active polish pass: 2026-08-10 (GO craft lab,
type floors, de-densify — all within freeze).

---

## 1. Identity

Athletic editorial × honest paper. The brand grammar is **artifacts**: passport,
seal/soin, race bib, boarding pass, ticket stub, receipt. Screens are paper;
ceremonies are artifacts. **"Dark is the artifact, light is the screen"** — dark
surfaces are reserved for ceremony objects (passport record face, handoff seal
band, club night world), never for chrome.

Honesty is a design primitive here, not just an engineering law: no element may
claim knowledge the system doesn't have (§7).

## 2. Token worlds & migration map

Four coexisting worlds in `theme.ts`, each with a jurisdiction. New code must
pick the world its screen belongs to — never mix within one surface.

| World | Export | Jurisdiction | Status |
|---|---|---|---|
| **Paper 순백/코랄** | `paper` | Service/transaction screens (meetup×2, addresses, address-pin, settings-adjacent) | **TARGET** — Sean 2026-08-06, 디자인 샷건 pick ① |
| **Tailored lilac** | `lilac` | ⚠ **PALE MEMBERS RETIRED PRODUCT-WIDE — Sean 2026-08-25** (see amendment below). Accent #6C5CE7 survives as an accent. | Retiring; sweep slice queued (ui6), exact replacement ground ratified by the club-v2 lab pick |
| **V4 athletic editorial** | `colors` | Numbers/brand accents everywhere; runner home; legacy screens (request, review) awaiting migration | Legacy screens migrate opportunistically — repaint when already editing (addresses.tsx precedent, 2026-08-10) |
| **Night club** | `colors.night*` | 하이클럽 world (D1×D2 hybrid: night stub × race program) | Deliberate keep — ceremony world |

Sub-palettes with single jurisdictions: gold = PB/milestone events only (일상은
볼트, 사건만 골드) · terracotta = shop only (부티크 온도) · collar palette =
per-dog personal color, must never equal a system signal color.

### ⚠ Pale-lilac retirement (2026-08-25, Sean — supersedes the "hues may survive as washes" carve-out for LILAC only)

Sean, reviewing the club-v2 labs (verbatim): *"the lab isnt good enough; still too cramped,
remove the purple and the old v0 font, have some consistency between font styles and schema,
and is not intuitive. clean look without cards within cards."* Scope answers, verbatim: purple →
*"i like the accent color, not the pale color; product wide and mock wide"* · v0 font →
**IBM Plex Sans KR** (a labs-only font; the app never shipped it — labs use the app's real
system-Korean stack from now on).

What this rules: **the pale lilac family — `lilac.bg` #F4F2FB as any canvas, and the
lilac-tinted insets/washes/hairlines (#EFECF9, #E6E2F4 class) as component fills — retires
product-wide.** The 2026-08-10 grammar below said tinted canvases retire but "their hues may
survive as accents/washes inside components"; for lilac, that carve-out is now CLOSED — the
pale tints go entirely. **#6C5CE7 itself survives as an ACCENT** (active states, selection,
links-class emphasis), never as a ground or wash. Coral remains the action color. The
replacement ground for surfaces that rode lilac is the warm consent-doc paper grammar
(club/delegate's doc world) — exact values are ratified by whichever club-v2 lab variant Sean
picks, then swept through `theme.ts` in one slice (owner home/fitness included; fitness's
freeze covers its hero ARCHITECTURE, and a ground-color token change is styling — verify the
non-native-driver rule is untouched when sweeping). Update CLAUDE.md's design extract
("tailored lilac (bg #F4F2FB…)") in the same sweep — on any conflict this file wins.

### Paper chrome migration grammar (2026-08-10, Sean: "all main tabs")

The chrome of every main-tab screen migrates to paper; each screen's SEMANTIC
color system survives (GO state colors, schedule status rails/badges, collar
palette, gold events, shop terracotta accents, club night world = artifact).
Component translations, from the reference screens (pay.tsx, runner/meetup,
addresses):

- **Canvas**: `paper.canvas` #FFFFFF for every screen body and scroll area. No
  tinted canvases (lilac.bg, cream, terraCraft retired as BACKGROUNDS; their
  hues may survive as accents/washes inside components).
- **Back button**: 40×40 square, canvas fill, 1px coral border, ‹ glyph 20.5 ink
  (the runner/meetup `circleBtn` grammar — square despite the legacy name).
- **Section separation**: full-bleed solid coral 1px (`paper.line`), edge to
  edge. Cards inside a section separate with neutral #EEE 1px or spacing.
- **Cards**: radius 0. Emphasis card = 1px coral border; neutral card = 1px
  #EEE. Soft shadows retire with the rounded corners (shadow only where a
  floating surface genuinely floats, e.g. the request floating ticket).
- **Kickers**: latin letterspaced caps, `paper.faint` (the "PAYMENT" /
  "MOCK · 준비 중" grammar).
- **Primary CTA**: PaperBtn primary (full-width ink bar, white ≥16 label) or
  screen-specific state color where a law assigns one (GO-colored ticket CTA).
- **Notice/wash panels**: sharp boxes on `paper.wash` (info) or `criticalWash`
  (failure) — the hold-timer notice grammar. System Alert.alert dialogs are OS
  chrome and stay native.
- **Numerals**: Oswald everywhere (done in the consistency wave).
- **Dark artifacts stay dark**: passport record face + stamps, handoff seal
  band, club night world, course photo cards — chrome around them goes paper.
- **Club widget exception (Sean 2026-08-10, VETO of the paper-wave
  supersession)**: 하이클럽 keeps its side margins + card radius on owner home.
  It is a night artifact island, not a paper card — full-bleed sharp was wrong.
  It is the ONE standing exception to the sharp/full-bleed card law.
- **Masthead lockup (owner home)**: the brandmark (`src/components/brandmark.tsx`
  — running-dog mark + stacked wordmark) sits at the top of the header, greeting
  BELOW it and below the ticker, so the greeting is always flush with the hero.
  The header box height follows the ticker's real presence — never reserve space
  for a conditional element (that dead space was the 2026-08-10 gap bug).

### Paper laws (the target world — memorize these)

- Canvas `#FFFFFF` (`canvasSoft #FBFAF7` for home-family body).
- Ink ramp contrast floors vs canvas: head ≥12:1 · text ≥7:1 · dim ≥4.5:1.
  `faint #999` is a decoration class (letterspaced caps kickers) ONLY.
- Hairline = **solid coral `#E8552F` 1px, full-bleed** (edge to edge, no side
  margins, no opacity). The line is the brand.
- Sharp corners (radius 0). `radius` tokens (6/6/4) belong to the V4 world.
- **Emphasis budget: the coral line + ONE CTA per screen.** Critical ink
  `#B3261E` is budget-exempt and must NEVER be the same value as `line`.
- **Button matrix (F2.1):** primary = ink face / `#333` pressed /
  `disabledFill #F2F2F2` + faint label · secondary = canvas + line border /
  wash pressed · destructive = canvas + critical ink / criticalWash pressed ·
  busy = **label swap ("저장 중...")**, never disabled-paint. No opacity tricks
  anywhere — every state is an explicit color.

## 3. Typography

- **Display: Black Han Sans** (`useDisplayFont`) — ONCE per screen (hero copy or
  wordmark). Budget, not preference.
- **Numerals: Oswald 600** (`useNumFont`) — athletic condensed, the race-bib
  voice. REQUIRES explicit `lineHeight ≥ 1.2×` — ascenders clip without it
  ("BUG A"). `tabular-nums` for data.
- **Body: IBM Plex Sans KR** (`useBodyFont`/`useBodyBold`) — system fonts are
  retired ("시스템폰트 박멸", upheaval lab).
- Weight law: **900 only for numbers and screen titles.** Body/labels at 900
  flatten hierarchy (ui-audit).
- **Detail-text floor: 14pt.** Exemptions: LATIN letterspaced caps kickers,
  serial/MRZ strings, barcode/stamp glyphs. Korean text never rides the kicker
  exemption — data in a kicker slot renders ≥14 (2026-08-10 audit law).
- **Logo artwork is the one Korean exemption, and it must be declared (2026-08-12).**
  The wordmark — `도그스하이` set as a *mark* rather than a sentence (`shot/[bid].tsx`'s
  `IconChip` and its lockup) — is drawing, not text. It may sit below the floor, but only
  when **all three** hold: (1) it is the brandmark or wordmark, never product copy;
  (2) it is marked as decoration for assistive tech (`accessibilityElementsHidden` +
  `importantForAccessibility="no-hide-descendants"`), with any needed label on the parent;
  (3) it carries no data — a route name, date, or status beside a logo is data and renders ≥14.
  Anything that fails a clause is text. **Repetition and decorative placement do not turn Korean
  words into glyphs** — a repeating brand tape is still the wordmark, and is exempt for that
  reason, not because it repeats.
  `type.label`/`type.caption` = 14 as of 2026-08-10; button labels ≥16
  (primary/door class; chips and links may stay 14).
- Small white text never sits directly on coral/sage — use an ink plate (≥4.5:1).

## 3b. COMPONENT SPEC (binding — 2026-08-11)

The 2026-08-10 waves fixed tokens but left *components* unspecified, so every
screen invented its own section header and chip. These are now components with
exact values. New code MUST use them; when you touch a screen, convert it.

### Section header — ONE grammar, no exceptions
```
[full-bleed coral 1px rule]
<title 20/800 ink>            [optional right link 16/800 accent + ›]
```
- **No latin kicker** ("ROSTER", "VERIFIED COURSES", "HIGH CLUB", "NEXT RUN ·
  BOARDING PASS"). They were decoration that competed with the title and made
  every section look different. Retired app-wide.
- **No section subtitle** ("동네에서 함께 달려요", "우리 동네 강아지들의 오늘 러닝").
  If the title doesn't say it, the section is misnamed.
- Numbered chips (01/02) only inside a genuinely ordered sequence; never as
  decoration.
- Every section title in the app is the SAME size/weight/color. A section is not
  more important because someone typed a bigger number.

### Buttons — four kinds, nothing else
| Kind | Fill | Border | Label | Notes |
|---|---|---|---|---|
| Primary | `paper.ink` (`inkPressed` on press) | none | white **17/800** | one per screen |
| Money | `MONEY_DEEP` coral | none | white **31 display** | full-bleed, no side margins, no price sub-plate |
| Secondary | canvas (`wash` pressed) | 1px `paper.line` | ink **16/800** | |
| Destructive | canvas (`criticalWash` pressed) | 1px `critical` | critical **16/800** | |
All: radius 0, `paddingVertical` ≥15, `scale(0.96)` press, busy = label swap.
No opacity tricks. Icon-only controls: 40×40 square, canvas, 1px coral.

### Screen title (2026-08-11 — the gap that let them diverge)

```
<title 30/900 · lineHeight 37 (1.23×) · Black Han Sans (useDisplayFont)>
```

`3b` specified *section* headers and left **screen** titles unspecified, so each screen invented
one. Measured 2026-08-11: **30 / 38 / 40**, five of the seven text-titled tab screens at 30, and
several with no explicit `lineHeight` at all (BUG A applies to Black Han Sans too — `community.tsx`
had already discovered this locally and fixed only itself).

- **Size, weight and lineHeight are universal.** No screen is more important because someone typed
  a bigger number — the same argument §3b already makes for section headers.
- **Color follows the screen's world** (§2), not a single token: `paper.ink` in the paper world,
  `lilac.head` in the lilac world, the masthead's own ink on a dark artifact header (`alerts`).
  This is the one axis where a screen title may legitimately differ.
- Screens whose identity is a *lockup* rather than a word (owner home's `BrandLockup`, runner
  home's bib strap) have no text title and are outside this spec.

### Status chip (확정됨 · 확인 대기 · LIVE …)
16/800, radius 0, tinted fill + no border, and it sits on the **same baseline row
as the datum it qualifies** (a booking's status belongs beside its date, not
floating in a corner).

### Cards
Radius 0 everywhere including the club card — the earlier club exception covered
its *margins*, never its corners. Club keeps side margins (night artifact
island); its corners are sharp like everything else.

### GO disc (owner home)
Word ladder **38/33/28/22** (was 30/26/22/17) with lineHeight ≥1.24×; sub-label
**17/800** on its ink plate. Ring: **36 dots** (was 54 — beyond ~36 they read as
texture, not count, and cost fill-rate on a frozen screen).

### Ready/confirmed green (GO sage → energy green)
`#12A05C` base / `#0E7F49` deep — brighter and more saturated than the retired
`#3F9A75`, deliberately NOT volt/neon. Implementer MUST verify white-label
contrast ≥3.5:1 on base and ≥4.5:1 on deep before shipping, and adjust within
the same hue if it misses.

## 4. Space & structure

- Global gutter: `layout.gutter` = **15** (2026-08-10; supersedes the never-
  enforced 11 — the seven core screens now import it). login's spacious 28 is a
  deliberate local exception.
- Section division by full-bleed hairline, not by cards. Card-soup and rounded
  card grids are retired in paper/V4 worlds; a card must BE the interaction
  (ticket, stub) to earn existence.
- Roomy screens get big primary buttons.
- Lilac world keeps its crisp radius scale (screen 14 · card 8 · inner 6 · btn 8
  · tag 5 · document 2 · circles exempt) and soft layered shadow — do not import
  those into paper.

## 5. Color semantics

- **GO disc color law** (Sean 2026-08-05 — "빨강으로 시작, 찾을 땐 파랑, 확정되면
  부드러운 초록"): color = whose turn it is. Coral = YOUR turn (no booking → act;
  LIVE → watch). Blue = system's turn (searching `#5B82E8`, directed
  `#4468CC` — periwinkle, deliberately green-shifted so it can never be confused
  with accent violet `#6C5CE7`). Sage = ready (`#3F9A75` deep-as-base so the
  white label holds 3.4:1; neon sage forbidden). Hero card wears a ~95% white
  wash of the current state color (`GO_TINT`); halo patches must sync to the
  same tint.
- Personal vs system: 볼트 그린 = personal (booking/run/verification shot),
  바이올렛 = club. Signal colors (volt·tang·amber·blue·violet) may never be
  reused for personal/collar decoration.
- `coralText`/`clubInk`/`goldDeep`/`terraInk` are the **reading versions** of
  their display colors — two-tier law: display color for surfaces, ink version
  for text.

## 6. Motion laws

- **Native driver only: transform + opacity.** No layout animation (width/
  height/top/margin), no backgroundColor animation — state colors swap
  discretely (모프 법).
- **Honest motion:** an animation may only claim what the system knows. The GO
  disc breathes ONLY during matching/LIVE ("idle에 돌리면 거짓 모션"). No idle
  loops, no fake progress.
- **Ceremonies play once per entity** (module-level Set idiom — `sealStampFresh`,
  `_patchPopSeen`) and never replay on re-entry hydration.
- Async surface reveals: crossfade ≤200ms with a **timeout force-reveal**
  fallback (PickupMap pattern) — a cover may never permanently hide live
  content.
- Press feedback: explicit pressed color (matrix law). Scale-on-press 0.96
  (compositor-only) is the approved tactility pattern of the 2026-08-10 polish
  pass — pending lab pick before app-wide adoption.
- Collapsing heroes (owner home, fitness): pinned absolute overlay + ScrollView
  paddingTop reservation; dot-ring layers (36 dots per §3b) hardware-textured;
  center layer fades via its own opacity. **DO-NOT-REFACTOR.**

## 7. Honesty laws (UI face of CLAUDE.md §Honesty)

Bind real fields or omit the element · failures render as failures (loud-fail
strips, never silent catch → happy UI) · loading ≠ 0 ≠ empty · no dead buttons —
render an action only when its effect exists in this state (길찾기 renders only
with coordinates) · gate logic/badges on `rawStatus`, never display vocabulary ·
dark/empty states name their real cause and carry a fix path when the viewer
can fix it (owner sees 위치 지정하기; runner is routed to chat).

## 7b. Decluttering doctrine (Sean 2026-08-11 — "no emojis, no cheap, declutter")

External canon adopted: Laws of UX, Apple HIG (clarity · deference · depth),
Maze UI principles. Binding consequences for this app:

- **No decorative emoji.** Colored pictorial emoji (🐾 📸 ⚡ …) are banned from
  shipped UI — they render as cheap color images against an ink-and-paper
  system. Monochrome typographic glyphs (› ‹ ✓ ✎ ◐ ● § ★) are ink, not
  pictures, and remain in the sanctioned glyph class. Never swap one emoji for
  another; delete, or use a Lucide `Icon` when a real affordance is needed.
- **Hick / Miller**: ≤5–9 competing elements per group; more means chunking or
  progressive disclosure, not smaller type.
- **Von Restorff + the emphasis budget**: exactly one isolated emphasis per
  screen. Two ink CTAs cancel each other out.
- **Cognitive load**: every element must serve the screen's ONE job; the rest
  moves behind a tap.
- **Peak-End protection**: the GO press, the handoff seal, and run completion
  are peak moments — they are exempt from minimization; polish them instead.
- **Decluttering never becomes hiding.** Honest states (loud-fail strips, dark
  states, real empties) are content, not clutter — they always survive a cut.
- **Fitts / HIG**: 44pt minimum targets, safe-area respect, hierarchy from size,
  weight, and space rather than decoration.

## 7c. Motion & feel — Apple fluid-interface doctrine (2026-08-11)

Adopted from the `apple-design` skill (Apple's *Designing Fluid Interfaces*),
translated to React Native. Installed skills: `apple-design`, `prototype`
(both apply). `pick-ui-library` and `ask-sonner` are **web-only** (Sonner,
base-ui, cmdk, Framer Motion) — they cannot be installed here; consult them for
taste, never for dependencies. RN equivalents: `Animated`/Reanimated springs,
`expo-blur` for materials, `AccessibilityInfo.isReduceMotionEnabled()`.

- **Respond on press-down, never on release.** Feedback at touch-down; commit at
  touch-up. Our scale-0.96 press already does this — keep it instant (≤100ms).
- **Interruptibility is the highest law of motion.** Any animation a finger can
  reach must be grabbable and reversible mid-flight, and must animate **from the
  current on-screen value**, never from the target (that causes the jump).
  Practically: gesture-driven surfaces use springs, not timing curves.
- **Spring defaults**: critically damped (`damping 1.0`, response 0.3–0.4) for
  ordinary UI. Bounce (`damping ~0.8`) ONLY after a gesture that carried
  momentum — a flick or throw. Never bounce something that merely faded in.
- **Velocity handoff**: when a drag ends, the spring starts at the finger's
  release velocity — no seam between dragging and animating.
- **Momentum projection**: a flick lands where the gesture was *going*
  (`current + (v/1000)·d/(1−d)`, d≈0.998), then snaps to the nearest detent —
  not the nearest point to the release. **The request gear dial must follow
  this**; snapToInterval alone lands short on a fast flick.
- **Rubber-band at boundaries** rather than hard-stopping.
- **Spatial consistency**: a surface exits along the path it entered; sheets and
  popovers originate from the control that opened them.
- **1:1 tracking** with the grab offset respected — never snap content to the
  finger's center.
- **Multimodal harmony**: visual + haptic fire on the SAME frame; reserve
  haptics for commit/snap/success (our dial detent and seal stamp qualify).
- **Typography**: tracking is size-specific — tighten large display text
  (negative tracking), body near 0; leading tightens as size grows. A single
  `letterSpacing` across sizes is wrong somewhere.
- **Reduced motion is not "no motion"** — swap slides/springs for a short
  cross-fade, keep the static cue. Check `isReduceMotionEnabled` and honor it.
- **Materials**: we are a paper system, so translucency is used sparingly —
  never stack a light translucent surface on another; a dark artifact may carry
  blur, chrome may not.
- Apple's eight foundations (purpose · agency · responsibility · familiarity ·
  flexibility · simplicity-not-minimalism · craft · delight) are the vocabulary
  for design arguments here. "Simplicity is not minimalism" is the guard against
  decluttering into blandness — pairs with §7b Peak-End protection.

## 8. Budgets (scarcity is the aesthetic)

| Thing | Budget |
|---|---|
| Black Han Sans | 1 use per screen |
| Holo foil | monogram + one ticket edge per surface |
| Emphasis (paper) | coral line + 1 CTA |
| Gold | milestone events only |
| Photos (delegation) | 5 content slots, wallpaper forbidden |
| Motion | ceremonies + state truth only |

## 9. Frozen zones

Owner-home/fitness collapsing heroes (perf architecture) · meetup stage
machines, polling, confirmHandoff, once-law hydration ordering (styling/pure-JSX
slot changes only; new state only at the end of the hook bundle) · 2-layer
matching compositor · availability = 3 deliberately distinct predicates.

## 10. Decision provenance

| Decision | Where | Date |
|---|---|---|
| Pale-lilac retirement product-wide; #6C5CE7 accent-only; labs drop IBM Plex | §2 amendment (Sean verbatim), club-v2 lab remake round 3 | 2026-08-25 |
| 순백/코랄 global canvas, pick ① | design shotgun, `theme.ts` paper block | 2026-08-06 |
| Red Core GO disc (Ⓑ①) | `docs/labs/glowup-go-lab.html` | 2026-08-05 |
| GO color progression + tint wash | Sean direction, `owner/home.tsx:51-84` | 2026-08-05 |
| Tailored lilac delegation 정본 | `docs/design/delegation-premium-refresh2.html` | 2026-08-01 |
| D1×D2 night club hybrid | `docs/design/club-premium-lab.html` + final-system-lab | 2026-08-04~08 |
| 시스템폰트 박멸, IBM Plex body | `docs/design/app-upheaval-lab.html` | 2026-08-07 |
| Style freeze to 50 paying dogs | `theme.ts:152` | 2026-08-06 |
| Sharp corners (V4), gutter 11 | `theme.ts:104-106` | 2026-07-28 |
| 2026-08-10 polish pass (GO craft, type floors, de-densify — within freeze) | this file + `docs/labs/go-premium-lab.html` | 2026-08-10 |
