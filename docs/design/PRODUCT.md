# Product

<!-- impeccable:product-schema 1 -->

> **What this file is.** The durable product record, in the format the `impeccable` skill's
> `init` command writes (`skill/reference/init.md` § Step 4, read 2026-09-17 from the cloned
> skill). It exists so a design skill — or a cold agent, or a new session — can be handed one
> page of product truth instead of re-deriving it from 100 KB of `CLAUDE.md`.
>
> **It is not canon.** `CLAUDE.md` holds the permanent laws, `DESIGN.md` is the design 정본, and
> `docs/session-handoff.md` holds current state. On any conflict those win and this file is the
> thing that is wrong. **Every fact below carries the file it was read from.** Nothing here is
> inferred from vibes, and nothing here is a metric — see § Evidence on Hand for why that matters
> in this repo specifically.
>
> Written 2026-09-17. Facts read on trunk `redesign-v4` @ `acc2263`.

## Platform

ios

Read from `app/app.json` (`expo.ios.bundleIdentifier`, `expo.ios.supportsTablet`,
`expo.orientation: "portrait"`) and `docs/design/hig-conformance-checklist.md` §1, whose scope line
is *"iPhone, the Banpo pilot build (`app/app` + `app/src`, branch `redesign-v4`)"*. The stack is
React Native 0.86 / Expo SDK 57 with `expo-router` (`app/package.json`), so an Android build is
technically reachable and the codebase already carries Android-aware rules (`DESIGN.md` §3b warns
that `elevation` draws its own shadow on Android). **But no Android surface is in the pilot**, and
the design law is written against iOS conventions, so the platform value is `ios` rather than
`adaptive`. A future Android target is a product decision, not a build flag.

## Users

Two roles in one app, each with its own tab bar (`app/src/components/bottomnav.tsx:38-50`):

- **보호자 (owner)** — a dog's guardian in Banpo who wants their dog run. Tabs: 홈 · 내 일정 ·
  커뮤니티 · 샵 · 마이. The owner's jobs are: book a run (`app/app/owner/request.tsx`), watch it
  happen (`app/app/owner/live.tsx`), and read what happened (`app/app/owner/report.tsx`,
  `app/app/shot/[bid].tsx`).
- **러너 (runner)** — the person who takes the dog out and runs. Tabs: 홈 · 요청 · 캘린더 · 수익 ·
  마이. The runner's jobs are: accept work, run it, hand the dog back, get paid.

A third audience exists inside the product rather than beside it: **하이클럽 (hi-club) session
participants** — owners and runners in a group run, with a host, a public pack map, and delegated
dogs (`app/app/club/**`, `app/src/components/club-board.tsx`). Club is a distinct world, not a
variant of the two roles.

**Situation matters more than demographics here.** The owner uses this app anxious, one-handed, at
the moment they hand their dog to a stranger, and again mid-run to check that the dog is fine. The
runner uses it **outdoors, mid-run, in daylight, moving** — which is why
`docs/design/hig-conformance-checklist.md` row C7 puts a daylight leg into the device smoke list
for `runner/run.tsx` and `owner/live.tsx` specifically. Neither user is at a desk.

## Product Purpose

daengrun (도그스하이) is a dog-running marketplace: an owner books a runner to take their dog on a
real run, watches it live, and receives a record of it. The pilot is geographically scoped to
**Banpo, Seoul** (`CLAUDE.md` header).

**Success is one number and it is not a vanity one.** `CLAUDE.md`'s first line sets the PMF gate as
**M1 rebooking 60%** — of the owners who book once, 60% book again within a month. That gate is
what makes the run report and the live screen product-critical rather than nice: they are the
surfaces that decide whether a first booking becomes a second one.

## Positioning

The product's claim is **the run actually happened, and here is the evidence** — a neighbouring
dog-walking app could copy the booking flow and could not copy this, because it is enforced as an
engineering law rather than as a feature. `CLAUDE.md` § Honesty laws: *"No mockups, fake numbers, or
fabricated data in the app: bind real fields or omit the element."* `DESIGN.md` §7 restates it as a
design primitive: *"no element may claim knowledge the system doesn't have"*, and §1 names honesty
as part of the identity rather than part of the QA pass.

The second half of the position is the **artifact grammar** (`DESIGN.md` §1): *"Athletic editorial ×
honest paper. The brand grammar is **artifacts**: passport, seal/soin, race bib, boarding pass,
ticket stub, receipt."* A completed run produces an object, not a toast.

## Operating Context

- **In-app language is Korean, everything else is English.** `CLAUDE.md` § Language: *"**English
  everywhere except in-app content.** … The ONLY Korean is what a user reads inside the product:
  UI copy, button labels, notification titles/bodies, error strings, and user-facing legal
  documents (개인정보처리방침, 이용약관)."* Korean product terms stay Korean when quoted in English
  prose (하이 포인트, 인계, 정산).
- **One appearance: light.** `app/app.json` → `expo.userInterfaceStyle: "light"`. This is a
  decision, not an oversight — `DESIGN.md` §1: *"'Dark is the artifact, light is the screen' — dark
  surfaces are reserved for ceremony objects (passport record face, handoff seal band, club night
  world), never for chrome."* See `docs/design/hig-conformance-checklist.md` Tension ③.
- **Maps are Naver** (`@mj-studio/react-native-naver-map`, `app/package.json`), with a documented
  null fallback at `app/src/lib/geo.ts:333` that must render an honest failure, not a blank
  (checklist row G7).
- **Login is Kakao-only.** Measured in `docs/session-handoff.md` (02:5x block): *"zero OTP/email/
  password fields exist (Kakao-only login)"*.
- **Time is KST, and it is computed, not read from the device.** `app/src/lib/kst.ts` is a fixed
  +9 offset with no `Intl`; `app/scripts/check-device-clock.mjs` is a commit gate that refuses a
  client module reading the device clock for a KST fact. A device-local read silently deletes
  features off-KST (`CLAUDE.md`: `owner/report.tsx:101`'s 「다음 주 같은 시간」 panel never renders).
- **The design arena is `docs/labs/`** — numbered HTML variants, Sean picks by number, and only
  then does implementation bind real fields (`CLAUDE.md` § Honesty laws).
- **Style freeze.** `DESIGN.md` header: *"no NEW aesthetics until 50 paying dogs. Craft, scale,
  spacing, and motion-tactility polish are freeze-compliant; new colors, fonts, or motifs are
  not."*

## Capabilities and Constraints

**Shipped surfaces** (59 route files under `app/app/**`, counted in
`docs/design/loading-state-audit.md`): login/auth · owner home · booking request flow (request,
matching, radar) · runner home/jobs · live run + pack map · chat · payments and card linking ·
settings/profile · club session, console and board.

**Terminology, in the product's own words:**

| Korean | What it is |
|---|---|
| 하이 포인트 | the app's point currency |
| 인계 | the handoff — owner to runner, and back |
| 정산 | settlement / payout |
| 하이클럽 | the group-run world (club) |
| 보호자 · 러너 | owner · runner |

**Constraints a design pass must not break:**

- **Frozen zones** (`DESIGN.md` §9, `CLAUDE.md` § DO-NOT-REFACTOR): owner-home and fitness
  collapsing heroes (a perf architecture: pinned absolute overlay + ScrollView paddingTop
  reservation, transform/opacity native-driver only) · meetup stage machines, polling and
  `confirmHandoff` · the 2-layer matching compositor · availability as three deliberately distinct
  predicates. Styling changes only.
- **No native-only import at module scope in anything a route can reach** (`CLAUDE.md` § Commit
  gate, enforced by `app/scripts/check-route-native-imports.mjs`). Expo Router evaluates every
  route module at launch, so such an import crashes the app on the home screen. A dev-only screen
  can crash a production launch.
- **Motion is native-driver only: transform and opacity** (`DESIGN.md` §6). No layout animation, no
  `backgroundColor` animation — state colors swap discretely.
- **Celebration animations play once per entity** and never replay on re-entry hydration
  (`CLAUDE.md` § Honesty laws, the module-level Set idiom: `sealStampFresh` / `_patchPopSeen` in
  `api.ts`).
- **Gate logic and badges on `rawStatus`, never on display vocabulary** — `STATUS_MAP` flattens
  server states and must not be the thing a branch reads (`CLAUDE.md` § Honesty laws).

**Explicitly undecided, recorded rather than guessed:**

- **The body typeface.** `DESIGN.md` §3 mandates IBM Plex Sans KR *and flags its own line*: *"THIS
  LINE IS CONTESTED AND THE CONFLICT IS UNRESOLVED — do not act on either side without Sean."*
  `theme.ts` still sets `BODY_FONT = 'IBMPlexSansKR_400Regular'`; the labs have run on the system
  Korean stack since 2026-08-25. One word from Sean settles it.
- **Dynamic Type.** `grep -ro 'maxFontSizeMultiplier'` over `app/app app/src` returns **0**
  (checklist row T1). Whether DESIGN.md's 15pt floor is a floor *at the default text size*
  (compatible with Dynamic Type) or an absolute law at every size (incompatible) is queued for Sean
  as Tension ①.

## Brand Commitments

- **Name and wordmark:** 도그스하이 (`app/app.json` → `expo.name`). The brandmark is a running-dog
  mark plus a stacked wordmark (`app/src/components/brandmark.tsx`), and on owner home the masthead
  lockup *is* the screen title — home has no text title (`DESIGN.md` §2, §3b).
- **Identity:** *"Athletic editorial × honest paper"* (`DESIGN.md` §1). Screens are paper;
  ceremonies are artifacts.
- **The coral hairline is the brand.** `DESIGN.md` §2 Paper laws: *"Hairline = **solid coral
  `#E8552F` 1px, full-bleed** (edge to edge, no side margins, no opacity). The line is the brand."*
- **Scarcity is the aesthetic** (`DESIGN.md` §8): one Black Han Sans use per screen · holo foil =
  monogram plus one ticket edge per surface · emphasis = the coral line plus one CTA · gold for
  milestone events only · motion for ceremonies and state truth only.
- **No decorative emoji** (`DESIGN.md` §7b, Sean 2026-08-11): *"Colored pictorial emoji (🐾 📸 ⚡ …)
  are banned from shipped UI — they render as cheap color images against an ink-and-paper system."*
  Monochrome typographic glyphs (› ‹ ✓ ✎ ◐ ● § ★) are ink, not pictures, and stay.
- **Baby work** (`DESIGN.md` §7a-bis, Sean 2026-08-26, binding, his words): *"way too much words
  and too dense. make it easy for the customer. intuitive. baby work. also too much dim text."*
  The word budget per screen state is 1 headline ≤6 words, 1 supporting line ≤12 words, **0 body
  paragraphs**, dim text only on the one line under the CTA, 1 primary action.

## Evidence on Hand

- `DESIGN.md` — the design 정본, with decision provenance and the human's verbatim rulings.
- `docs/labs/` and `docs/design/*.html` — ~100 HTML labs, the sanctioned mockup arena.
- `docs/decisions/` — the rulings ledger; `docs/decisions/awaiting-sean.md` is the open queue.
- `docs/design/hig-conformance-checklist.md` (2026-09-17) — 99 rows against 61 Apple HIG pages,
  8 tensions, with an explicit epistemic ladder saying which claims are observed and which are read
  through a summarizer.
- `docs/design/loading-state-audit.md` (2026-09-17) — all 59 routes read, not grepped: 46 name a
  loading state, 8 Tier-1 honesty defects, 7 opacity-busy buttons.
- `supabase/tests/harness.sh` — the SQL pin suite; `app/test/` — the client suites, run through
  `npm test`.

🔴 **What must never be fabricated, with the incident that proves it.** There are **no usage
metrics, no testimonials, no customer count, and no revenue** to put on any surface. On 2026-08-26 a
session read `count(*) = 11` from a table and shipped it downstream as "11 accounts", which became a
design constraint and a scale argument. Sean's answer, verbatim in `CLAUDE.md`: *"the existing ones
are fake so it's fine"* — **the real user count was zero.** Every "small enough not to matter yet"
argument built on that 11 was rhetorical. A fixture, a churned account and a live user are
indistinguishable in a count. So: no invented numbers in a lab, no invented numbers in a screen, and
sample data in a mockup is labelled as sample in the lab's own header.

## Product Principles

1. **Bind a real field or omit the element.** The strongest thing this product can say is that the
   run happened; the fastest way to lose that is one fabricated number. Loading is not 0, and 0 is
   not empty (`CLAUDE.md` § Honesty laws, `DESIGN.md` §7).
2. **Failures are shown as failures.** No silent catch into a happy UI. A dark or empty state names
   its real cause and carries a fix path when the viewer is the one who can fix it — the owner sees
   위치 지정하기, the runner is routed to chat (`DESIGN.md` §7).
3. **No dead buttons.** Every visible action has a real route or effect in *every* state; an action
   renders only when its effect exists (길찾기 renders only with coordinates). A dead slider is a
   dead button (`DESIGN.md` §7, checklist G6).
4. **One job per screen, said in the fewest words that still say it.** Baby work. Delete before
   shrinking — the instinct to keep a sentence and drop it to 14pt breaks the floor to preserve
   words nobody asked for (`DESIGN.md` §7a-bis).
5. **Scarcity is the aesthetic.** One emphasis, one display face, one CTA. Two ink CTAs cancel each
   other out (`DESIGN.md` §7b, Von Restorff).
6. **Peak moments are exempt from minimization.** The GO press, the handoff seal and run completion
   are the peaks the rebooking gate actually rides on — polish them, do not declutter them away
   (`DESIGN.md` §7b, Peak-End protection).

## Accessibility & Inclusion

The product-specific requirements, all with a measured source:

- **Korean detail-text floor: 15pt** (`DESIGN.md` §3, raised from 14 on 2026-08-25 after Sean sent
  a screenshot of owner home: *"some parts of the home screen has very small font text sizes; not
  acceptable and are illegible"*). Exempt: latin letterspaced caps kickers, serial/MRZ strings,
  barcode/stamp glyphs, avatar-dot initials. **Korean text never rides the kicker exemption.**
  Button labels ≥16. This floor sits *above* iOS's 11pt system minimum, so it is compatible with
  the HIG rather than in tension with it (checklist T3).
- **Contrast floors, stricter than WCAG AA** (`DESIGN.md` §2): head ≥12:1 · text ≥7:1 · dim ≥4.5:1
  against canvas. `paper.faint #999` is a decoration class only. Small white text never sits
  directly on coral or sage — it needs an ink plate (≥4.5:1).
- **Touch targets 44×44 pt minimum** (`DESIGN.md` §7b, Fitts/HIG). Icon-only controls are specified
  at 40×40 (`DESIGN.md` §3b), so they need `hitSlop` to reach 44 — checklist G1 measured `hitSlop`
  on only 72 of 535 `<Pressable>`.
- **Never convey state by color alone** (checklist C1). The GO state law — coral = your turn, blue
  = waiting, sage = ready — now rides the button count plus an alert line since the disc was
  retired (Sean 2026-08-19), and a **word** must carry the meaning in every state.
- **VoiceOver names and roles on every icon-only control** — landed 2026-09-17 (`02e778f`). The tab
  bar deliberately ships without visible labels (Sean 2026-08-12: *"탭 아이콘 밑 글자 빼고 아이콘
  키워라"*), and the ruling is only safe because the Pressable keeps `accessibilityRole="tab"` +
  `accessibilityLabel` + selected state (checklist Tension ②).
- **Reduced motion is honored as "less motion", not "no motion"** — swap slides and springs for a
  short cross-fade and keep the static cue (`DESIGN.md` §7c).
- **Dynamic Type is NOT currently supported** and this is a known, queued gap, not a claim of
  conformance: 0 `maxFontSizeMultiplier` sites, every size a fixed literal (checklist T1, Tension
  ①). One legitimate `allowFontScaling={false}` exists — `app/src/components/run-share-card.tsx:199`,
  a fixed-canvas share image. **Any second occurrence is a defect** (checklist T7).
- **Outdoor legibility is an accessibility requirement here, not a nicety** — the runner reads
  `runner/run.tsx` in daylight while moving (checklist C7).
