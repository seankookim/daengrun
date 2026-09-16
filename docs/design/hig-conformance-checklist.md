# Apple HIG conformance checklist — 도그스하이 (iOS)

A checkable list of Apple Human Interface Guidelines rules that (a) apply to this app's real
surfaces, (b) can be verified from source or a screenshot, and (c) do **not** contradict
`DESIGN.md`. Where HIG and DESIGN.md genuinely disagree, the row is **not** written as a rule —
it is moved to [§Tensions for Sean](#tensions-for-sean) with both sentences and a recommendation.
**This document never overrides DESIGN.md.** On any conflict DESIGN.md wins and Sean rules.

Written 2026-09-17. Scope: iPhone, the Banpo pilot build (`app/app` + `app/src`, branch
`redesign-v4`).

---

## 0. How the HIG was read — and what that licenses

⚠ **The human-facing HIG pages could not be read directly.** Every
`https://developer.apple.com/design/human-interface-guidelines/…` URL returns HTTP 200 with only a
`<title>`; the body is client-rendered JavaScript. The index page returned **no navigation at
all**, so the page list could not be taken from it as intended.

The content was instead read from the documentation JSON that backs those same pages:
`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`. The
slug list was enumerated from `foundations.json` / `patterns.json` / `inputs.json` /
`components.json` and each subsection index, so the URLs below are Apple's real current slugs, not
guesses.

🔴 **Epistemic ladder — read this before quoting anything here as Apple's words.** The fetch tool
runs a summarizing model over the page. So:

| claim | status |
|---|---|
| the page exists at this slug | **OBSERVED** (HTTP 200 / 404 measured) |
| Apple's guidance says roughly X | **READ**, through a summarizer |
| Apple's exact sentence is "X" | **NOT ESTABLISHED** — nothing here is a certified verbatim quote of Apple |
| DESIGN.md's exact sentence is "X" | **OBSERVED** — read directly from the file, verbatim |
| the repo measurements below | **OBSERVED** — every count re-run independently, see §12 |

Consequence: in §Tensions, the **DESIGN.md side is verbatim** and the **HIG side is a faithful
paraphrase**. Before taking a tension to Sean as a decision, open the cited HIG page in a browser
and confirm the sentence.

### 0.1 Pages that fetched OK (61 content pages)

**Foundations (16):** `accessibility`, `app-icons`, `branding`, `color`, `dark-mode`, `icons`,
`images`, `inclusion`, `layout`, `materials`, `motion`, `privacy`, `right-to-left`, `sf-symbols`,
`typography`, `writing`

**Patterns (19):** `charting-data`, `collaboration-and-sharing`, `entering-data`, `feedback`,
`going-full-screen`, `launching`, `live-viewing-apps`, `loading`, `managing-accounts`,
`managing-notifications`, `modality`, `offering-help`, `onboarding`, `playing-haptics`,
`ratings-and-reviews`, `searching`, `settings`, `undo-and-redo`, `workouts`

**Inputs (5):** `focus-and-selection`, `gestures`, `keyboards`, `pointing-devices`,
`virtual-keyboards`

**Components (18):** `action-sheets`, `alerts`, `buttons`, `collections`, `labels`,
`lists-and-tables`, `maps`, `notifications`, `pickers`, `popovers`, `progress-indicators`,
`search-fields`, `segmented-controls`, `sheets`, `tab-bars`, `text-fields`, `toggles`, `toolbars`

**Other (3):** `designing-for-ios`, `design-principles`, `live-activities`

### 0.2 Pages that FAILED, and why

| page | what happened | consequence |
|---|---|---|
| the HIG **index** (HTML) | 200, body is a JS shell — returned no nav | page list enumerated from the section JSON instead |
| every `…/design/human-interface-guidelines/<page>` **HTML** URL | 200, title only, no body | all content read via the `.json` endpoint |
| `navigation-bars` | **HTTP 404 — the page no longer exists** | Apple folded it into **`toolbars`**, which now states that in iOS a navigation-specific toolbar is sometimes called a navigation bar. Nav-bar rules below cite `toolbars`. |
| `activity-indicators` | **HTTP 404 — the page no longer exists** | folded into **`progress-indicators`**, which carries combined guidance. Spinner rules below cite `progress-indicators`. |
| `keyboards` | fetched OK but is about **physical** keyboards | on-screen keyboard guidance lives in **`virtual-keyboards`**, which was then fetched. Form rules cite `virtual-keyboards`. |

### 0.3 Deliberately not read (declared, so nobody assumes coverage)

`spatial-layout`, `immersive-experiences` (visionOS — no surface here) · `multitasking`,
`drag-and-drop`, `file-management`, `printing`, `playing-audio`, `playing-video` (no surface in the
pilot) · `sidebars`, `split-views`, `windows`, `menus`, `the-menu-bar` (iPad/macOS chrome this app
does not use) · `searching` and `search-fields` **were** read but produce no rows, because the app
ships no search field — if one lands, those two pages are the source.

---

## 1. Surfaces this checklist covers

| area | primary files (absolute) |
|---|---|
| login / auth | `/Users/seankim/dev/daengrun/app/app/login.tsx`, `…/app/app/index.tsx` |
| owner home | `…/app/app/owner/home.tsx`, `…/app/src/components/home-hero.tsx` |
| booking request flow | `…/app/app/owner/request.tsx`, `…/owner/matching.tsx`, `…/owner/radar.tsx` |
| runner home / jobs | `…/app/app/runner/home.tsx`, `…/runner/requests.tsx`, `…/runner/calendar.tsx` |
| live run + pack map | `…/app/app/runner/run.tsx`, `…/owner/live.tsx`, `…/club/map/[sid].tsx`, `…/club/run/[sid].tsx` |
| chat | `…/app/app/chat.tsx` |
| payments / card | `…/app/app/owner/card-link.tsx` + `…/app/src/components/card-link-panel.tsx`, `…/app/app/payments.tsx`, `…/owner/pay.tsx` |
| settings / profile | `…/app/app/my.tsx`, `…/app/app/settings.tsx`, `…/app/app/profile/edit.tsx` |
| club session / console / board | `…/app/app/club/session/[sid].tsx`, `…/club/console/[sid].tsx`, `…/app/src/components/club-board.tsx` |

Excluded: `app/app/dev/club-lab.tsx` and `app/app/dev/pay-lab.tsx` (labelled 프로덕션 UI 아님).

**Severity key.** **HIGH** = breaks an iOS expectation or an accessibility guarantee ·
**MEDIUM** = friction · **LOW** = polish.

**Size of this checklist**, so a later session can tell "my rows passed" from "my rows never ran":
99 rows — Layout 8 · Navigation 10 · Typography 8 · Color 8 · Touch/gestures 8 · Entering data 9 ·
Feedback 10 · Accessibility 11 · Launch/onboarding 9 · Notifications/settings 9 · Writing 9.
Plus 8 tensions and 10 first-look items.

---

## 2. Layout & safe areas

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| L1 | Respect system-defined safe areas so the Dynamic Island, status bar and home indicator never cover content or controls (`foundations/layout`). | `cd app && find app -name '*.tsx' \| while read f; do grep -qE 'useSafeAreaInsets\|SafeAreaView\|edges=\{' "$f" \|\| echo "$f"; done` — **measured 56 of 63**. Screenshot every surface on a notched device. | HIGH |
| L2 | A bottom bar must clear the home indicator using the device's real inset, not a constant (`foundations/layout`). | `app/src/components/bottomnav.tsx` `s.bar` uses a literal `paddingBottom: 22`; compare against `useSafeAreaInsets().bottom` on iPhone SE (0) vs iPhone 17 Pro (34). | HIGH |
| L3 | The layout must adapt to text-size changes — adjacent views may need to stack, rows may need to grow (`foundations/layout` › Adaptability). | Set Larger Text to AX3 and screenshot all 11 surfaces; grep fixed heights on text rows: `grep -rnE 'height: *[0-9]+' app/app \| grep -i 'row\|cell\|chip'`. | HIGH |
| L4 | Place primary controls in the middle or lower area of the screen for one-handed reach (`designing-for-ios`). | Screenshot owner home, runner home, `owner/request.tsx`; measure the primary CTA's y-position against the thumb arc. DESIGN.md §4 「Roomy screens get big primary buttons」 already pushes the same way. | MEDIUM |
| L5 | Determine layout from size classes, not device type or orientation; functionality must not change with available space (`foundations/layout` › Size classes). | `app/app.json` sets `ios.supportsTablet: true` **and** `orientation: "portrait"`. Grep for device branching: `grep -rn 'isPad\|Dimensions.get' app/app app/src`. | MEDIUM |
| L6 | Even when locked to one orientation, the interface must resize well across device sizes; test the largest and smallest first (`foundations/layout`). | Run the smoke list on iPhone SE (smallest) and iPad. Existing lists: `docs/design/device-smoke-map-screens.md`, `device-smoke-ui-master-2026-08-31.md`. | MEDIUM |
| L7 | Order content by importance — most important near the top and leading edge (`foundations/layout` › Visual hierarchy). | Screenshot review per surface. Compatible with DESIGN.md §3b (one section-header grammar) and §7a-bis (one headline, one supporting line). | LOW |
| L8 | Extend full-screen background content beneath bars rather than letting a bar's solid fill cut it off (`foundations/layout`). | The 10 `NaverMapView` sites — `app/app/runner/run.tsx:1195`, `…/owner/live.tsx:648`, `…/club/map/[sid].tsx:382`, etc. Screenshot whether the map reaches the screen edges behind the dock. | LOW |

---

## 3. Navigation — tab bar, nav bars, back behaviour, modality/sheets

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| N1 | Prioritize swipe navigation for going back; don't conflict with system edge gestures (`designing-for-ios`, `inputs/gestures`). | `app/app/_layout.tsx:22` — `gestureEnabled: false` globally, commented 「back-swipe conflicted with the slider」. Every one of 63 routes inherits it. | HIGH |
| N2 | Keep the tab bar visible when moving between sections; hide it only for a temporary modal view (`components/tab-bars`). | `grep -rln '<BottomNav' app/app` → **12 of 63 files**. Pushed screens (request, run, chat, club) show no dock. Decide per screen whether it is a push (should keep it) or a modal (may drop it). | MEDIUM |
| N3 | Every screen that shows the dock should show a selected tab (`components/tab-bars`). | `alerts.tsx`, `cards.tsx`, `safety.tsx` render `<BottomNav>` but appear in neither `OWNER_TABS` nor `RUNNER_TABS` (`app/src/components/bottomnav.tsx`), so `active` is false for all five. Screenshot: no indicator anywhere. | MEDIUM |
| N4 | Preserve each tab's navigation state when switching tabs (`components/tab-bars`). | `bottomnav.tsx` calls `router.replace(t.path)` — a replace, not a per-tab stack. Test: drill into a booking from 내 일정, switch to 홈, switch back. | MEDIUM |
| N5 | Use the standard Back button and standard symbols; don't label it "Back" or "Close" (`components/toolbars`). | `headerShown: false` globally, so all back controls are hand-rolled. DESIGN.md §2 specifies the shape (40×40 square, coral border, ‹ glyph 20.5) — check every screen has one, at the leading edge, at ≥44pt. | MEDIUM |
| N6 | Give each screen a title that says where you are; never the app name; keep it short (`components/toolbars`). | DESIGN.md §3b Screen title spec (30/900, lineHeight 37, display font). Grep screens with no title element; lockup-titled screens (owner home, runner home) are explicitly out of that spec. | MEDIUM |
| N7 | Present modally only where there's a clear benefit, keep the modal task short, and give an obvious way out (`patterns/modality`). | 19 `<Modal` sites. Read each for a visible dismiss control: `grep -rn '<Modal' app/app app/src`. Heaviest: `club/session/[sid].tsx:1823,1871,1900,1922,1953`. | MEDIUM |
| N8 | A sheet needs a grabber when resizable, swipe-to-dismiss, Cancel on the leading edge and Done on the trailing edge (`components/sheets`). | Only `app/src/components/toss-sheet-impl.tsx:70` uses a real `presentationStyle="pageSheet"`. The other 18 are `transparent animationType="slide"` — no detents, no grabber, no swipe-dismiss. | HIGH |
| N9 | Show only one sheet at a time; close the first before opening a second (`components/sheets`, `patterns/modality`). | Read the modal-visibility state in `club/session/[sid].tsx` and `owner/request.tsx` — can two `visible` flags be true at once? | MEDIUM |
| N10 | Use an action sheet, not an alert, for a choice arising from a deliberate action; destructive at the top, Cancel at the bottom (`components/action-sheets`). | `grep -ro 'ActionSheetIOS' app/app app/src` → **0**; `Alert.alert` → **284**. Every multi-choice `Alert.alert` is a candidate. | MEDIUM |

---

## 4. Typography & Dynamic Type

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| T1 | Support Dynamic Type; a layout that ignores it can be impossible to use for people who rely on it (`foundations/typography`, `foundations/accessibility`). | `grep -ro 'maxFontSizeMultiplier' app/app app/src` → **0**. Every size in `app/src/theme.ts` (`display 48.5 / title 24 / body 16 / label 15`) and in screens is a fixed literal. See Tension ①. | HIGH |
| T2 | A custom font must support Dynamic Type and respond to Bold Text (`foundations/typography` › Custom fonts, `foundations/branding`). | Three custom families ship: Black Han Sans (`useDisplayFont`), Oswald (`useNumFont`), the body face. Test each with Larger Text and Bold Text on. | HIGH |
| T3 | Body default is 17 pt and the system minimum is 11 pt (`foundations/typography`, `foundations/accessibility`). | DESIGN.md's 15 pt Korean floor sits **above** the system minimum — compatible. Audit sites under the house floor: `grep -rnE 'fontSize: (9\|10\|11\|12\|13\|14)([^0-9.]\|$)' app/app app/src`, then exclude only DESIGN.md §3's named exemptions (latin letterspaced kickers, serial/MRZ, glyphs, avatar-dot initials). | HIGH |
| T4 | Avoid Ultralight/Thin/Light weights; prefer Regular through Bold (`foundations/typography`). | `grep -rn "fontWeight: '[123]00'" app/app app/src` — expect 0; DESIGN.md's ramp runs 400–900. | LOW |
| T5 | Keep truncation to a minimum as text grows; let labels wrap (`foundations/typography` › Dynamic Type). | `grep -rn 'numberOfLines={1}' app/app app/src` on data-bearing Korean text (names, addresses, course names). Korean truncates harder than Latin. | MEDIUM |
| T6 | Maintain the hierarchy at every font size — primary elements stay toward the top (`foundations/typography`). | Screenshot at AX1 and AX3. DESIGN.md §3 already records that raising a floor is not a find-and-replace (kickers went to 19 to avoid an inverted hierarchy) — the same argument applies under scaling. | MEDIUM |
| T7 | Don't disable font scaling on product copy (`foundations/typography`, `foundations/accessibility`). | `grep -rn 'allowFontScaling' app/app app/src` → **one** site, `app/src/components/run-share-card.tsx:199` (`FIXED_TYPE`, applied at lines 367/384/397/399). That is a fixed-canvas share image — a legitimate exemption. **Any second occurrence is a defect.** | HIGH |
| T8 | Leading tightens as size grows; a single letterSpacing across sizes is wrong somewhere (`foundations/typography`, DESIGN.md §7c). | Oswald numerals require explicit `lineHeight ≥ 1.2×` (DESIGN.md §3 「BUG A」). Find violations: `grep -rn 'useNumFont' app/app app/src` and check each call site has a sibling `lineHeight`. | MEDIUM |

---

## 5. Color & dark mode

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| C1 | Never convey information by color alone — pair it with text, shape or an icon (`foundations/color` › Inclusive color). | The GO state law (DESIGN.md §5: coral = your turn · blue = waiting · sage = ready) now rides the button count + an alert line since the disc was retired (CLAUDE.md, Sean 2026-08-19). Screenshot each state and confirm a **word** carries the meaning. Same for club status chips and schedule rails. | HIGH |
| C2 | Contrast floors: 4.5:1 up to 17 pt, 3:1 at 18 pt and above, 3:1 for bold text (`foundations/accessibility` › Vision). | DESIGN.md §2 already sets stricter floors (head ≥12:1, text ≥7:1, dim ≥4.5:1) and §3 bans small white text on coral/sage without an ink plate. Measure every shipped token pair in `app/src/theme.ts`, including `paper.faint #999` (decoration class only) and the club night world. | HIGH |
| C3 | Use a color consistently — the same color never means two things (`foundations/color`). | DESIGN.md §5: signal colors may never be reused for collar decoration. Check the collar palette values in `theme.ts` against every signal value (coral, periwinkle `#5B82E8`/`#4468CC`, green `#12A05C`, accent `#6C5CE7`, gold, terracotta). | MEDIUM |
| C4 | Support Increase Contrast (`foundations/color`, `foundations/dark-mode`). | `grep -ro 'PlatformColor\|DynamicColorIOS\|useColorScheme' app/app app/src` → **0**. Nothing in the app responds to the setting. See Tension ④ for the recommended shape. | MEDIUM |
| C5 | Check legibility with Reduce Transparency on (`foundations/dark-mode`, `foundations/materials`). | `grep -rn 'BlurView\|expo-blur' app/app app/src`. DESIGN.md §7c already limits blur to dark artifacts and forbids stacking translucent surfaces — this row verifies the limit holds. | MEDIUM |
| C6 | Apply the accent color judiciously; reserve it for primary actions and status, not broad surfaces (`foundations/branding`, `foundations/color`). | DESIGN.md §2 rules `#6C5CE7` **accent-only, never a ground or wash**, and §8 caps emphasis at coral line + one CTA. Verify: `grep -rn '6C5CE7' app/app app/src` and check no hit is a `backgroundColor` outside the night-club artifact world. | MEDIUM |
| C7 | Test under bright and dim lighting and on True Tone displays (`foundations/color`). | This app is used outdoors, mid-run. Put a daylight leg into the device smoke list for `runner/run.tsx` and `owner/live.tsx` specifically. | MEDIUM |
| C8 | The app ships one appearance — confirm that is a decision and not an oversight (`foundations/dark-mode`). | `app/app.json` → `expo.userInterfaceStyle: "light"`. See Tension ③. | MEDIUM |

---

## 6. Touch targets & gestures

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| G1 | Every control needs a 44×44 pt minimum hit region (`components/buttons`, `foundations/accessibility` › Mobility). | Measured: **68 explicit `minHeight/height: 44` lines across 38 files**, but `hitSlop` on only **72 of 535 `<Pressable>`**. Audit the small icon-only controls: `grep -rn '<Pressable' app/app app/src \| wc -l` vs `grep -rn 'hitSlop' app/app app/src`. DESIGN.md §3b already mandates 40×40 icon controls — those need `hitSlop` to reach 44. | HIGH |
| G2 | Leave roughly 12 pt of padding around bezeled controls and 24 pt around unbezeled ones (`foundations/accessibility` › Mobility). | Screenshot the dock (`bottomnav.tsx` `s.tab` = `flex:1, paddingVertical:18`) and any icon row; measure the gaps. | MEDIUM |
| G3 | A custom button must have a press state or it feels unresponsive (`components/buttons`). | DESIGN.md §3b is stricter and already specifies it: filled = 4 px lip → `translateY(3)` + 1 px lip; unfilled = `scale(0.96)`; disabled stays flat; busy = label swap, never an opacity trick. Grep `<Pressable` without a pressed style function. | MEDIUM |
| G4 | Don't redefine or conflict with system gestures — edge swipe, three-finger undo, shake (`inputs/gestures`, `patterns/undo-and-redo`). | The slide-to-book slider owns the screen edge, which is why `_layout.tsx:22` disables back-swipe. Verify no other surface eats a system gesture. | HIGH |
| G5 | A custom gesture may never be the only way to do something important; provide a button alternative (`inputs/gestures`). | `app/src/components/tabswipe.tsx` (9 screens) duplicates dock taps — passes. **The booking slider needs an equivalent tap path**; check `owner/request.tsx` for one. | HIGH |
| G6 | Make it clear why an unavailable gesture doesn't work (`inputs/gestures`). | Screenshot the booking slider in a blocked state (no card registered, no address, outside hours). DESIGN.md §7 already forbids dead buttons — the same applies to a dead slider. | MEDIUM |
| G7 | A map must stay interactive (zoom, pan, rotate) and nothing should permanently obscure it (`components/maps`). | The 10 `NaverMapView` sites. Check overlays/sheets do not trap the pan gesture, and that the fallback (`getNaverMap()` → `null` at `app/src/lib/geo.ts:333`) renders an honest failure, not a blank. | MEDIUM |
| G8 | Offer a tap/button alternative to every swipe, for Switch Control and VoiceOver users (`foundations/accessibility` › Mobility). | Swipe surfaces: the booking slider, `tabswipe.tsx`, and the 18 hand-rolled swipe-dismiss modals. Each needs a reachable button. | HIGH |

---

## 7. Entering data — keyboards, text fields, pickers, form flow

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| E1 | Set `textContentType` so iOS AutoFill can fill names, phone numbers, addresses and one-time codes (`inputs/virtual-keyboards`). | Measured: **51 `<TextInput`, 0 `textContentType`, 0 `autoComplete`**. Highest value first: `app/app/onboard/owner.tsx`, `onboard/runner.tsx`, `runner/apply.tsx`, `profile/edit.tsx`, `app/src/components/phone-row.tsx`. | HIGH |
| E2 | Choose a keyboard type that matches the content (`inputs/virtual-keyboards`). | `grep -ro 'keyboardType=' app/app app/src` → **9 of 51 fields**. Audit the other 42: phone, number, email, URL. | MEDIUM |
| E3 | Use a secure field for sensitive input and never prepopulate it (`components/text-fields`, `patterns/entering-data`). | `grep -ro 'secureTextEntry' app/app app/src` → **0**. Confirm no screen collects a password, PIN or card number in a plain field — card entry goes through the Toss sheet (`app/src/components/toss-sheet-impl.tsx`), which should be verified as a web view, not a native field. | HIGH |
| E4 | Keep the keyboard from covering the focused field or its action button (`inputs/virtual-keyboards` › keyboard layout guide). | `KeyboardAvoidingView` exists in only **5 files** (`chat.tsx`, `onboard/owner.tsx`, `onboard/runner.tsx`, `runner/run.tsx`, `src/components/checkin-answer.tsx`) while 51 `<TextInput` are spread wider. Test every text screen with the keyboard up. | HIGH |
| E5 | Customize the Return key when it clarifies the flow, and submit from the last field (`inputs/virtual-keyboards`). | `returnKeyType=` on 8 sites, `onSubmitEditing` on 4. Check each multi-field form advances and the last field submits. | LOW |
| E6 | Minimize data entry — prefill anything the system can already supply (`patterns/entering-data`). | Onboarding asks for an address; `app/src/lib/geo.ts` can reverse-geocode. Check `onboard/owner.tsx` / `onboard/runner.tsx` offer 「현재 위치로」 rather than only typing. | MEDIUM |
| E7 | Validate as the person types and put the error next to the field, phrased as the fix (`patterns/entering-data`, `foundations/writing`). | An `Alert.alert` for a field error is the wrong surface. Grep validation in `onboard/*`, `runner/apply.tsx`, `profile/edit.tsx`, `compose.tsx`. | MEDIUM |
| E8 | Enable Continue/Next only once the required fields are complete, and make the requirement visible (`patterns/entering-data`). | Read each form CTA's `disabled` expression. DESIGN.md §3b: disabled stays flat with `disabledFill #F2F2F2` + faint label — so a disabled CTA must still be legible as "not yet", never invisible. | MEDIUM |
| E9 | Reduce minute granularity in a date/time picker — offer intervals, not 60 values (`components/pickers`). | `REQUEST_SLOTS` in the booking flow (referenced at `app/app/owner/report.tsx:~102`) — confirm the request screen's time choice is slot-based, and that the gear dial follows DESIGN.md §7c momentum projection. | LOW |

---

## 8. Feedback — loading, progress, errors, haptics, alerts

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| F1 | Show a system progress indicator while loading; prefer determinate where the duration is known; keep it moving (`components/progress-indicators`, `patterns/loading`). | `grep -rn 'ActivityIndicator' app/app app/src` → **2 hits, both in `app/app/dev/club-lab.tsx`**. **Zero in any production screen.** Audit what each screen actually renders while loading — DESIGN.md §7 forbids `loading = 0 = empty`, so something should be there. | HIGH |
| F2 | Show something as soon as possible — a placeholder, not a blank screen (`patterns/loading`). | Screenshot the first frame of each of the 11 surfaces on a cold, throttled network. | HIGH |
| F3 | Use an alert only for critical, ideally actionable information — never for purely informational messages and never at startup (`components/alerts`, `patterns/feedback`). | **284 `Alert.alert`**, concentrated at `club/session/[sid].tsx` (**55**), `club/[id].tsx` (14), `club/console/[sid].tsx` (13), `owner/request.tsx` (12). Triage each into: real alert · action sheet (N10) · inline status. | HIGH |
| F4 | Alert buttons: at most 3, titled with a specific verb rather than OK/Yes/No, and Cancel present wherever something is destroyed (`components/alerts`). | Read the button arrays of all 284 sites; grep for `'확인'`-only alerts, which are the informational class F3 rejects. | MEDIUM |
| F5 | Never give a destructive action the primary role (`components/buttons`, `components/alerts`). | DESIGN.md §3b already agrees: destructive = canvas + 1 px critical border + critical ink, never a filled primary. Verify the delete/cancel paths — `app/src/components/delete-account-sheet.tsx`, booking cancel, club incident. | HIGH |
| F6 | Show a failure as a failure and explain what to do; don't let a command fail silently (`patterns/feedback` › Error handling). | CLAUDE.md §Honesty and DESIGN.md §7 say the same thing more strictly (loud-fail strips, never silent catch → happy UI). Grep `catch {` blocks that set a success state or swallow: `grep -rn 'catch' app/app app/src \| grep -v console`. | HIGH |
| F7 | Confirm a significant completion (a payment), but don't confirm the ordinary (`patterns/feedback`). | The pay/card flows plus the seal/stamp ceremonies. DESIGN.md §6 requires a ceremony play **once per entity** and never on re-entry hydration (`sealStampFresh`, `_patchPopSeen`). | MEDIUM |
| F8 | Reserve haptics for commit/snap/success, keep them optional, and fire them on the same frame as the visual (`patterns/playing-haptics`, DESIGN.md §7c). | `app/src/lib/haptics.ts:7-14` (module aliased as `H`) plus one direct call at `app/app/owner/matching.tsx:307`. Check nothing fires a haptic on a passive state change. | MEDIUM |
| F9 | Provide feedback through more than one channel — color, text, sound, haptic (`patterns/feedback` › Accessibility). | The GO/run state transitions and the handoff seal. Pairs with C1: if the color is one channel, the word is the second. | MEDIUM |
| F10 | Automatic updates rather than making people pull-to-refresh for everything; a refresh control needs no instructional title (`components/progress-indicators` › Refresh controls). | 15 `RefreshControl` usages (e.g. `app/app/leaderboard.tsx:50`, `app/app/alerts.tsx:115`). Check each list also polls or subscribes, and that no refresh control carries a how-to title. | MEDIUM |

---

## 9. Accessibility

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| A1 | Label every control VoiceOver will read — an icon-only control has no other name (`foundations/accessibility`, `foundations/icons`). | Measured: **303 `accessibilityRole` vs 535 `<Pressable`**, **247 `accessibilityLabel`**. `app/src/components/bottomnav.tsx` is the model to copy (role `tab` + label + selected state, and its header comment says why). Audit the gap. | HIGH |
| A2 | Give a control a role and a state so VoiceOver announces what it is and whether it is selected, disabled or busy (`foundations/accessibility`). | **68 `accessibilityState`**. `app/app/index.tsx:152` is a good example (`{{ disabled, busy }}`). Every busy CTA using DESIGN.md's label-swap needs `busy: true` too, or the swap is silent to VoiceOver. | HIGH |
| A3 | Add a hint where the label alone doesn't say what will happen (`foundations/accessibility`). | **Exactly 1 `accessibilityHint` in the whole tree** — `app/src/components/delete-account-sheet.tsx:167`. The booking slider and the handoff seal are the two controls that most need one. | MEDIUM |
| A4 | Mark decoration as decoration so assistive tech skips it (`foundations/accessibility`; DESIGN.md §3 logo exemption). | 7 `accessibilityElementsHidden` + 7 `importantForAccessibility` (e.g. `app/app/index.tsx:141-142`). DESIGN.md §3 makes this a **condition** of the wordmark's floor exemption — a wordmark below 15 pt that is not hidden is text, not artwork. | MEDIUM |
| A5 | VoiceOver reading order must follow the visual reading order (`foundations/layout`, `foundations/accessibility`). | The pinned absolute overlays (owner home hero, `owner/fitness.tsx`) reorder the view tree. Test with VoiceOver on, swiping forward through each surface. | HIGH |
| A6 | Announce content that changes without a tap, or it is invisible to VoiceOver (`foundations/accessibility`, `patterns/feedback`). | Measured: **0 `accessibilityLiveRegion`, 0 `announceForAccessibility`, 0 `isScreenReaderEnabled`**. The live run, matching/radar, and chat all change state on their own. | HIGH |
| A7 | Honor Reduce Motion: swap springs and slides for a short cross-fade and keep the static cue (`foundations/accessibility` › Cognitive, `foundations/motion`; DESIGN.md §7c 「Reduced motion is not "no motion"」). | `app/src/lib/reducedMotion.ts` exists but is consumed by only **3 files** (`app/app/course/[id].tsx`, `app/app/owner/home.tsx`, `app/src/components/draw-button.tsx`) against **181 `Animated.`** sites. | HIGH |
| A8 | Text must scale to at least 200% without clipping (`foundations/accessibility` › Vision). | AX5 pass over the 11 surfaces. Pairs with T1 — currently nothing scales, so this is untestable until Dynamic Type lands. | HIGH |
| A9 | Offer a tap alternative to every gesture, and prefer familiar system gestures over custom ones (`foundations/accessibility` › Mobility). | Same audit as G8; recorded here because it is an accessibility guarantee, not only a convenience. | HIGH |
| A10 | Give every chart accessibility labels describing its values (`patterns/charting-data`). | `app/app/owner/fitness.tsx` (the 36-dot ring), `app/app/runner/earnings.tsx`, `app/app/leaderboard.tsx`. Measured **2 `accessibilityValue`** in the codebase, one of which is the request slider (`owner/request.tsx:1478`). | MEDIUM |
| A11 | Provide feedback in more than one modality and don't depend on a single sense (`foundations/accessibility`, `foundations/inclusion`). | Pairs with C1 and F9 — the audit is one pass over the state vocabularies (GO states, club status chips, schedule rails). | MEDIUM |

---

## 10. Launch & onboarding

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| O1 | The launch screen should nearly match the first screen, carry no text and no logo (`patterns/launching`, `foundations/branding`). | `app/app.json` has **no `splash` block** and no `expo-splash-screen` dependency; an unreferenced `assets/splash-icon.png` sits on disk. Nothing is configured, so the launch is whatever Expo defaults to — screenshot the cold launch. | MEDIUM |
| O2 | Launch instantly and restore the previous state (`patterns/launching`). | `app/app/_layout.tsx:6` side-effect-imports `bgTrack` before render. Measure cold start; then kill the app mid-run and confirm it returns to `runner/run.tsx`, not to home. | MEDIUM |
| O3 | Don't request a permission at launch unless it is core; ask when the person first uses the feature (`foundations/privacy`, `patterns/onboarding`). | Notification permission is requested from `app/src/lib/push.ts:218` (`requestPermissionsAsync`) with **no `getPermissionsAsync` pre-check**, called at `app/app/owner/home.tsx:255` and `app/app/runner/home.tsx:373` — i.e. on first home entry, which for a signed-in user is launch. No priming screen. | HIGH |
| O4 | A pre-permission screen has exactly one button, it must not say "Allow", and it must not offer a way to skip the system alert (`foundations/privacy` › Pre-alert screens). | `app/src/components/location-primer.tsx` gets the structure right — **one** button, gated on `undetermined` only (`shouldShowPrimer()`), no escape hatch. But the button reads **「위치 사용 허용」** (line 70) — literally "Allow". HIG wants 계속 / 다음. | HIGH |
| O5 | The location primer must exist wherever the permission is first needed (`foundations/privacy`, `patterns/onboarding`). | `grep -rn 'LocationPrimer' app/app` → mounted **only** in `app/app/onboard/owner.tsx:181`. `onboard/runner.tsx` does not mount it, so runners meet the raw system alert unprimed — and the runner is the role whose whole job is tracked. | HIGH |
| O6 | Purpose strings: active voice, specific, sentence case, ending period (`foundations/privacy`). | `app/app.json` `ios.infoPlist` carries `NSLocationWhenInUseUsageDescription` and `NSCameraUsageDescription`; the Always-location and photo strings come from the `expo-location` / `expo-image-picker` plugin blocks. Read all of them against the rule. Note there is **no `InfoPlist.strings`** localization path — these Korean strings are the only version. | MEDIUM |
| O7 | Onboarding is optional and short, is never replayed on later launches, and stays findable afterwards (`patterns/onboarding`). | `app/app/onboard/owner.tsx`, `onboard/runner.tsx` — check the completion flag survives reinstall-free relaunches and that the flow can be reached again from 마이/설정. | MEDIUM |
| O8 | Delay sign-in as long as possible; explain why an account is needed (`patterns/managing-accounts`). | `app/app/index.tsx` redirects to `/login` when unauthenticated — **nothing is browsable signed-out**. For a marketplace, HIG's shopping example is the direct analogue. Sean's call whether the Banpo pilot wants a browsable state. | MEDIUM |
| O9 | Provide an in-app account deletion that is no harder than any web path (`patterns/managing-accounts`). | **This one passes** — `app/src/components/delete-account-sheet.tsx:278` calls `deleteMyAccount()` in-app; the `mailto:` at line 266 is a support contact, not the deletion path. Verify the sheet still reaches that call and that the `auth_delete_pending` state is shown honestly (the file's own header documents it). | HIGH |

---

## 11. Notifications & settings

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| S1 | Get permission before sending notifications, and ask in a context that explains the benefit (`patterns/managing-notifications`). | Same site as O3: `app/src/lib/push.ts:218`. There is no notification equivalent of `location-primer.tsx`. | HIGH |
| S2 | Assign interruption levels honestly; Time Sensitive only for something happening now or within the hour (`patterns/managing-notifications`). | Read every push payload in `app/src/lib/push.ts` and in the edge functions that send. A 요청 도착 alert is genuinely Time Sensitive; a weekly digest is not. | MEDIUM |
| S3 | A marketing notification must never be Time Sensitive and must be separately opted into (`patterns/managing-notifications`). | Audit every send site for a marketing/retention class and check its level and opt-in. | HIGH |
| S4 | Provide in-app notification preferences (`patterns/managing-notifications`). | `app/app/settings.tsx` — check for per-category toggles, and that a toggle in a list row carries no redundant label (`components/toggles`). | MEDIUM |
| S5 | Notification copy: short title, complete-sentence body, nothing sensitive readable on the Lock Screen (`components/notifications`). | The Korean title/body strings in the senders. A dog's name plus a live address is the sensitive case here. | MEDIUM |
| S6 | End a Live Activity as soon as the run ends, and show only glanceable, non-sensitive data (`live-activities`). | `app/app.json` sets `NSSupportsLiveActivities: true`; `app/src/activities/RunActivity.tsx` and `OwnerRunActivity.tsx`. Confirm the activity ends on run completion, cancel, incident **and** on a crashed/abandoned run. | HIGH |
| S7 | Don't duplicate a Live Activity's updates with push notifications for the same event (`live-activities`). | Diff the run-state pushes against the activity update points. | MEDIUM |
| S8 | Keep task-specific options in their context; put only rarely-changed things in a settings screen (`patterns/settings`). | `app/app/settings.tsx` and `app/app/my.tsx` — anything a person changes while doing the task belongs on the task screen. | LOW |
| S9 | Link directly to system Settings when the fix lives there, rather than describing where to go (`patterns/settings`, `foundations/privacy`). | **This one passes** — 4 `Linking.openSettings` sites, all on denied-permission recovery paths: `club/session/[sid].tsx:715`, `club/companion/[sid].tsx:268`, `onboard/runner.tsx:131`, `runner/run.tsx:1092`. Keep it that way. | LOW |

---

## 12. Writing / copy (in Korean)

| id | rule (HIG page) | how to check it here | sev |
|---|---|---|---|
| W1 | Button and link labels are verbs naming the result, not a place (`foundations/writing`). | Read every CTA label. DESIGN.md §7a-bis caps a screen at **one** primary action, so there are few to check per screen. | MEDIUM |
| W2 | Build one language pattern and hold it — the same word for the same step everywhere (`foundations/writing`). | Grep the confirm verb across the booking flow: `grep -rn '확인\|완료\|다음\|계속' app/app`. Three words for one step is the failure. | MEDIUM |
| W3 | Error copy says what to do next and never blames (`foundations/writing` › Alerts and error messages). | The 284 `Alert.alert` strings, plus `payments.tsx:160` (`'메일 앱을 열 수 없어요'`) as the tone reference. | MEDIUM |
| W4 | Empty states give a real next step (`foundations/writing` › Empty states). | DESIGN.md §7 is stricter and already governs: dark/empty states name their real cause and carry a fix path when the viewer can fix it. Audit every list screen's empty branch against that sentence. | MEDIUM |
| W5 | Use the right verb for touch — 탭/누르기, never 클릭 (`foundations/writing` › device-specific). | `grep -rn '클릭' app/app app/src`. | LOW |
| W6 | Plain language, no jargon, gender-neutral, no humor that won't translate (`foundations/writing`, `foundations/inclusion`). | The onboarding, consent (`club/delegate/[sid].tsx`) and legal copy. | MEDIUM |
| W7 | Eliminate unnecessary text (`foundations/writing`). | DESIGN.md §7a-bis is the binding, stricter form: 1 headline ≤6 words · 1 supporting line ≤12 words · **0 body paragraphs** · dim text only under the CTA · 1 primary action. Count words per screen state. Sean's ruling covers **every** screen, not only new ones. | HIGH |
| W8 | Sentence/title capitalization applied consistently per element type (`foundations/writing`). | Only affects the Latin kickers and English strings; Korean has no case. Check the letterspaced kicker class in `theme.ts` is uniform. | LOW |
| W9 | Include text in an app icon only when essential — it neither localizes nor supports accessibility (`foundations/app-icons`). | `app/assets/icon.png`; `app/app.json` has a single top-level `icon` and **no `ios.icon`**, so there are no dark/tinted/clear variants for iOS. Read the icon against the rule and decide whether the Korean wordmark is essential. | LOW |

---

## Tensions for Sean

Eight places where the HIG and `DESIGN.md` genuinely point in different directions. **The DESIGN.md
side is verbatim from the file. The HIG side is a paraphrase from the fetched page** (see §0) —
confirm it in a browser before ruling. Nothing here has been acted on.

### ① Dynamic Type vs the fixed point scale — *the biggest one*

- **HIG** (`foundations/typography`, `foundations/accessibility`): support Dynamic Type; the
  layout must adapt to all font sizes; apps that don't respond to it *"can be difficult or
  impossible to use for people who rely on this feature."*
- **DESIGN.md §3**: *"**Detail-text floor: 15pt**"* — and the whole system is absolute points,
  e.g. §3b: *"`<title 30/900 · lineHeight 37 (1.23×) · Black Han Sans (useDisplayFont)>`"* and
  *"Size, weight and lineHeight are universal."*

**Recommendation — these are less opposed than they look, and the resolution is mechanical.** A
floor is a *minimum*; Dynamic Type is a *multiplier*. The compatible shape is: DESIGN.md's numbers
become the values at the **default** text size and scale from there, and the fixed `lineHeight`
values become **ratios** (37 → 1.23×, which §3b has already written down beside the number). The
one thing that genuinely breaks is any layout with a hard-coded row height. This is a real slice,
not a token sweep — **do not start it on an inference.** Ask Sean whether the 15 pt floor is a
floor at the *default* size (compatible) or an absolute pixel law at every size (incompatible).

### ② Tab labels

- **HIG** (`components/tab-bars`): include tab labels, using single words where possible to
  describe the content.
- **Sean, 2026-08-12**, recorded verbatim in `app/src/components/bottomnav.tsx`:
  *"탭 아이콘 밑 글자 빼고 아이콘 키워라"* → 라벨 `<Text>` 제거, 아이콘 19 → 26.

**Recommendation: DESIGN.md/Sean wins, and the ruling already protected the part HIG's rule
exists for.** The same comment block requires the Pressable to keep
`accessibilityRole="tab"` + `accessibilityLabel` + selected state, and the code does
(`bottomnav.tsx`), so VoiceOver users still hear 「홈」, 「내 일정」… The residual risk is purely
sighted first-run discoverability of five unlabeled glyphs. That is measurable in a smoke test with
someone who has never used the app — measure it, don't reverse the ruling on HIG's say-so.

### ③ One appearance (light only)

- **HIG** (`foundations/dark-mode`): ensure the app looks good in both appearance modes; avoid
  app-specific appearance settings. A single appearance is offered as a rare exception, and the
  exception Apple names is *dark* for immersive media — not light.
- **DESIGN.md §1**: *"**'Dark is the artifact, light is the screen'** — dark surfaces are reserved
  for ceremony objects (passport record face, handoff seal band, club night world), never for
  chrome."* §2 amendment (Sean 2026-08-25): *"white backgrounds."*
- **Measured fact**: `app/app.json` → `expo.userInterfaceStyle: "light"`, so iOS never asks the app
  to go dark.

**Recommendation: leave it, and write the reason into DESIGN.md.** A locked appearance is a
decision; an *unlocked* app that only looks right in light is a bug, and the lock is what prevents
the second. It does not fail App Review. The thing worth doing is recording it in DESIGN.md §2 so a
future session doesn't "add dark mode" as a polish item and quietly void the artifact law.

### ④ System colors vs the fixed palette

- **HIG** (`foundations/color`): never hard-code system color values; prefer system-defined colors
  because they carry accessible variants that adapt to Increase Contrast and appearance changes.
- **DESIGN.md §2 Paper laws**: *"Canvas `#FFFFFF`"*, *"Hairline = **solid coral `#E8552F` 1px,
  full-bleed** (edge to edge, no side margins, no opacity). The line is the brand."*

**Recommendation: keep the palette; close the gap the system colors would have closed for free.**
HIG's argument is about *system* colors specifically — it does not say a brand palette is wrong,
and the coral hairline is load-bearing identity. What the app actually loses is the
Increase-Contrast variant. So the proposal is narrow: add an Increase-Contrast variant for
`paper.dim` and for the coral line, and nothing else. That is additive, freeze-compliant (no new
aesthetic), and answers the real accessibility complaint rather than the stylistic one.

### ⑤ Custom body font vs system fonts for body copy

- **HIG** (`foundations/branding`): use custom fonts for headlines and subheadings; use system
  fonts for body copy and captions for optimal legibility. Custom fonts must support Dynamic Type
  and Bold Text.
- **DESIGN.md §3**: *"**Body: IBM Plex Sans KR** (`useBodyFont`/`useBodyBold`) — system fonts are
  retired ("시스템폰트 박멸", upheaval lab)."*
- ⚠ **And DESIGN.md flags its own line as unresolved**: *"**THIS LINE IS CONTESTED AND THE CONFLICT
  IS UNRESOLVED — do not act on either side without Sean.**"*

**Recommendation: do NOT let the HIG be the tiebreaker on the open IBM Plex question.** DESIGN.md
says explicitly that swapping a product-wide body face on an inference is the class of move that
file exists to prevent, and "Apple prefers system fonts for body" is exactly such an inference.
What the HIG legitimately adds is a *requirement that applies to whichever face wins*: it must
support Dynamic Type and Bold Text. Fold that into the question put to Sean; don't answer the
question with it.

### ⑥ Liquid Glass / materials vs the paper world

- **HIG** (`foundations/layout`, `foundations/materials`): take advantage of Liquid Glass to give
  controls a distinct appearance; use a scroll edge effect to elevate controls above content
  *instead of* applying solid or semi-opaque background colors; the tab bar floats above content
  on a Liquid Glass background.
- **DESIGN.md §2**: *"Cards: radius 0… Soft shadows retire with the rounded corners"*; §7c:
  *"we are a paper system, so translucency is used sparingly — never stack a light translucent
  surface on another; a dark artifact may carry blur, chrome may not."*

**Recommendation: DESIGN.md wins — Liquid Glass is a look, not a conformance requirement**, and
adopting it would void the paper grammar and breach the style freeze (§DESIGN.md header: no new
aesthetics until 50 paying dogs). Take only the *problem* it solves: confirm the solid-white dock
(`bottomnav.tsx`, `backgroundColor: paper.canvas`) and any pinned header stay legible over
scrolling content. ⚠ Flag for Sean separately: this is the axis most likely to drift without anyone
deciding anything, because standard components the app *does* use — `Alert.alert`, the one
`pageSheet` — will pick up Liquid Glass from iOS automatically, producing mixed chrome no one chose.

### ⑦ Logo restraint vs the masthead and brand tape

- **HIG** (`foundations/branding`): resist displaying your logo throughout the app unless it is
  essential for context; branding must defer to content; don't use the launch screen as a branding
  opportunity.
- **DESIGN.md §2**: *"**Masthead lockup (owner home)**: the brandmark (`src/components/brandmark.tsx`
  — running-dog mark + stacked wordmark) sits at the top of the header"*; §3: *"**Repetition and
  decorative placement do not turn Korean words into glyphs** — a repeating brand tape is still the
  wordmark, and is exempt for that reason."*

**Recommendation: the masthead is fine; check the tape's exemption clause rather than removing
it.** One lockup on owner home falls inside HIG's "essential for context" carve-out — it *is* that
screen's title under §3b, since home has no text title. The repeating brand tape is the piece that
reads as a violation to a cold reviewer, and DESIGN.md §3 already imposes the right condition on
it: clause (2) requires `accessibilityElementsHidden` + `importantForAccessibility="no-hide-descendants"`.
Verify that clause actually holds at every tape site (measured: only 7 such pairs exist in the whole
codebase) — the exemption is conditional, and an unverified condition is not an exemption.

### ⑧ Emoji in brand voice *(minor, listed for completeness)*

- **HIG** (`foundations/branding`): a brand voice may convey optimism through plain words,
  occasional exclamation marks, **emoji**, and simple sentence structures.
- **DESIGN.md §7b** (Sean 2026-08-11): *"**No decorative emoji.** Colored pictorial emoji (🐾 📸 ⚡ …)
  are banned from shipped UI — they render as cheap color images against an ink-and-paper system."*

**Recommendation: DESIGN.md wins outright, no decision needed.** HIG's line is a permissive example
in a paragraph about voice, not a rule; Sean's is a ruling with a stated reason. Recorded only so a
future session that finds the HIG sentence doesn't treat it as license.

---

## 13. Ten likely violations to look at first

Ranked by expected cost. **Every item is marked `[inferred]` until an audit confirms it** — the
counts below were re-measured independently by me (commands in each row), but a count is not a
verdict: it says a pattern is absent from source, not that the *behaviour* is wrong on device. The
audit is what converts these into findings.

| # | likely violation | evidence (measured) | sev |
|---|---|---|---|
| 1 | **Safe areas are unhandled on almost every screen** `[inferred]` | 56 of 63 route files under `app/app` contain none of `useSafeAreaInsets` / `SafeAreaView` / `SafeAreaProvider` / `edges={` — including `_layout.tsx`, `index.tsx`, `owner/home.tsx`, `runner/home.tsx`, `runner/run.tsx`. And `bottomnav.tsx` pads the dock with a literal `paddingBottom: 22` rather than the device inset. Rows L1, L2. | HIGH |
| 2 | **Dynamic Type is entirely absent** `[inferred]` | `maxFontSizeMultiplier` 0 · `PixelRatio.getFontScale` 0 · every size in `app/src/theme.ts` and in screens is a fixed literal. Nothing scales when a person raises Larger Text. Rows T1, A8 — and Tension ①, so **ask before building**. | HIGH |
| 3 | **No AutoFill on any form field** `[inferred]` | 51 `<TextInput` · **0** `textContentType` · **0** `autoComplete` · **0** `secureTextEntry` · `keyboardType=` on only 9. Onboarding, runner application and profile edit all type from scratch. Rows E1–E3. | HIGH |
| 4 | **The iOS back-swipe is disabled on all 63 routes** `[inferred]` | `app/app/_layout.tsx:22` — `gestureEnabled: false`, commented 「back-swipe conflicted with the slider」. Deliberate, and the trade is recorded — but it is app-wide, while the slider is on one screen. Rows N1, G4. | HIGH |
| 5 | **The location primer's button says 「위치 사용 허용」 — "Allow"** `[inferred]` | `app/src/components/location-primer.tsx:70`. HIG's pre-alert rule names this exact word as the thing not to use (계속 / 다음 instead). ⚠ The rest of that component is exemplary — one button, no escape hatch, gated on `undetermined` only — which is why the single word is worth fixing rather than rewriting. Row O4. | HIGH |
| 6 | **Runners are never primed for location** `[inferred]` | `LocationPrimer` is mounted only at `app/app/onboard/owner.tsx:181`. `onboard/runner.tsx` mounts nothing, so the role whose entire job is GPS-tracked meets the raw system alert cold. Row O5. | HIGH |
| 7 | **Notification permission is requested on first home entry, unprimed** `[inferred]` | `app/src/lib/push.ts:218` calls `requestPermissionsAsync()` with **no** `getPermissionsAsync` pre-check, invoked from `owner/home.tsx:255` and `runner/home.tsx:373`. For a signed-in user that is launch. No notification equivalent of `location-primer.tsx` exists. Rows O3, S1. | HIGH |
| 8 | **VoiceOver has no way to hear a live run change** `[inferred]` | 0 `accessibilityLiveRegion` · 0 `announceForAccessibility` · 0 `isScreenReaderEnabled` · exactly **1** `accessibilityHint` in the whole codebase. The run, matching/radar and chat screens all change state on their own. Rows A3, A6. | HIGH |
| 9 | **Alerts are doing an action sheet's job, 284 times** `[inferred]` | `Alert.alert` 284 (55 in `club/session/[sid].tsx` alone) · `ActionSheetIOS` **0**. HIG reserves alerts for critical, actionable interruptions and sends deliberate multi-choice actions to an action sheet. Rows F3, F4, N10. | HIGH |
| 10 | **18 of 19 modals are hand-rolled, and iPad/launch config is unset** `[inferred]` | Only `app/src/components/toss-sheet-impl.tsx:70` uses `presentationStyle="pageSheet"`; the other 18 are `transparent animationType="slide"` — no detent, no grabber, no swipe-dismiss. Separately: `app.json` sets `ios.supportsTablet: true` **with** `orientation: "portrait"` and has **no** `splash` block and **no** `ios.icon` (so no dark/tinted icon variants). Rows N8, L5, O1, W9. | MEDIUM |

**Two candidates that did NOT make the list, because reading the code refuted the count:**

- *Account deletion* looked like a `mailto:`-only path from a grep. It is not —
  `app/src/components/delete-account-sheet.tsx:278` calls `deleteMyAccount()` in-app and the
  `mailto:` at line 266 is a support contact. **Conformant** (row O9).
- *Zero production `ActivityIndicator`* is real (both hits are in `app/app/dev/club-lab.tsx`) but
  is **not** evidence of a missing loading state — DESIGN.md §7 forbids `loading = 0 = empty`, so
  the screens most likely render custom skeletons. It is filed as row F1, an audit question, not as
  a violation. ⚠ This is the shape to be careful with everywhere in this document: **the absence of
  a standard API is not the presence of a defect.**
