# HANDOFF — client domain (`app/`), written 2026-08-20 afternoon

**Read with this, in order:** `docs/decisions/awaiting-sean.md` (his live decision queue —
§0-sexvicies and §0-septvicies are mine, both open, and §0-septvicies has a **correction that
supersedes its own spec**) · `DESIGN.md` (tokens, laws) · `CLAUDE.md` (permanent laws) ·
`docs/labs/RULINGS-2026-08-19-journey.md` (his verbatim rulings) · `docs/session-handoff.md`
(fleet-wide, announcer-owned — **do not edit**).

Domain: **client — all of `app/`**. Never write a migration or touch `supabase/`.
This file **replaces** the 2026-08-20-morning version; git history is the archive
(`git log --follow docs/handoff-client.md`).

---

## 1. Status table

| System | State | Tag |
|---|---|---|
| Branch / tree | `redesign-v4` @ `46944a6`, **0 ahead / 0 behind origin**, clean except untracked `ingest.sql` (not mine) | **[verified-now]** |
| `tsc --noEmit` | clean | **[verified-now]** |
| `check-rpc-contracts.mjs` | ✅ all calls match signatures | **[verified-now]** |
| `check-route-native-imports.mjs` | ✅ 56 routes, none | **[verified-now]** |
| `check-embed-fk.mjs` | ✅ 1 pair checked, 107 files — **a fifth gate I had been missing all session** | **[verified-now]** |
| `npm run lint --quiet` | **279 problems, 6 errors** = the baseline. A 7th is yours | **[verified-now]** |
| Migrations (production) | applied through **0115** | **[verified-now]** |
| Edge functions (deployed) | create-booking-hold v10 · transition-booking v34 · settle-run v14 · open-drop v8 · geocode-address v1 · collect-charges v1 · confirm-payment v1 · **delete-account v1** | **[verified-now]** |
| Owner home v3 | **SHIPPED**, simulator-verified across none / confirmed / past / handoff | **[verified-now]** |
| Handoff state render | verified by **temporarily forcing `goState`**, screenshotting, reverting. `home.tsx` byte-identical after (checked) | **[verified-now]** |
| iOS device | **nothing has ever run on hardware.** Simulator only (iPhone 17 Pro `F2FDB7D7-A669-4BBC-8EF4-677597F3851A`). TestFlight zero builds | sim **[verified-now]** · TestFlight **[from-history]** |
| Other sessions | ⚠ see the overnight addendum at the foot of this file — it supersedes this row. announcer **offline** since ~14:00. ⚠ **A SECOND CLIENT SESSION is live** (`exciting-rosalind-e6ac13`) claiming all of `app/`; it has already layered `21825ca` + `f6aa011` on top of my files. My work survived intact — verified — but two client sessions share this surface, so read `git log -- <file>` before editing anything in `app/` | **[verified-now]** |

---

## 2. Goal & current state

Banpo pilot, PMF gate M1 rebooking 60%. This session was **owner-home design → implementation**,
plus one brand-identity research round.

| Workstream | State |
|---|---|
| Brand identity research (7 agents) | **DONE** — synthesis lab `ec2e8b0`; six decision dials unanswered |
| Home v3 design labs (6 labs) | **DONE** — published as artifacts, committed with generators |
| Home v3 implementation | **SHIPPED** — `a8248ae` → `794f07e` → `1dcc42c` → `144ea61` |
| `draw-button.tsx` (new) | **SHIPPED** — 10 drawings, 7 grounds, measured contrast |
| Engraved club widget | **SHIPPED** (`clubcard.tsx` `ClubCompactRow`) |
| Past-booking state | **client half shipped**; server half queued §0-septvicies |
| Handoff CTA off-by-one-state | **FOUND, NOT FIXED** — needs his ruling |
| Wordmark asset | **BLOCKED on Sean** — interim Black Han Sans |
| 반환 확인 (R6) · R1c work-gate | still server slices, unchanged |
| 커뮤니티 / 마이 in this style | not started (Sean: "later") |

---

## 3. What shipped this session (by theme)

**Brand research** — `ec2e8b0`: seven agents (repo archaeology · apple-design motion audit · voice
extraction · four market clusters · 배민 deep-dive) → `docs/labs/brand-identity-lab.html`. Thesis:
*the brand evicted from the app and the market's whitespace are the same thing* — "warm ·
typographic · numeral-owning · record-issuing" is the unclaimed seat in Korean pet apps.

**Design labs** (live HTML, generators committed beside each, all published as artifacts):
`634fbdf` attention-lab (12 시선 structures) · `e35a183` state-lab (logo drop + 7 states + 10 club
widgets) · `0acce78` v3-lab (feature/route table first, then mocks) · `bdc8e54` cta-life-lab
(10 button treatments) · `5a71ad9` cta-drawings-lab · `ba3c9fa` home-full-lab (3 states fanned).

**Implementation** — `a8248ae` v3 build · `794f07e` his seven corrections + club widget ·
`1dcc42c` measured contrast · `144ea61` past-booking honesty + amber ground · `46944a6` queue
correction. Earlier: `22a503e` (the merge he'd wanted as a mock), `0a159b6` (last user-facing
댕런 removed from the runner consent line).

---

## 4. Standing doctrines (canonical: `CLAUDE.md`, `DESIGN.md`)

The five that bit *this* session:
1. **FIVE gates before every commit**, from `app/`: tsc · check-rpc-contracts ·
   check-route-native-imports · **check-embed-fk** · `npm run lint --quiet` (**must stay 6 errors**).
   ⚠ I ran only four all session — `check-embed-fk.mjs` exists and I did not know it. Verified
   green after the fact (1 pair, 107 files), but the gate list in this file was wrong until now.
2. **Honesty**: bind real fields or omit. No invented urgency (`지어낸 긴급함 = 학습된 무시`).
   Failures shown as failures. No dead buttons.
3. **Gate on `rawStatus`, never on display vocabulary** — STATUS_MAP flattens server states.
   *I violated this; it produced the handoff off-by-one. See §7.*
4. **One coral per frame**; coral = your turn only.
5. **DO-NOT-REFACTOR**: `owner/fitness.tsx` collapsing hero · both meetup stage machines ·
   `run.tsx`'s in-file freezes · the three availability predicates.

---

## 5. Working-relationship norms

- **Terse, by number, and he means it.** "A", "②", "then handoff", "implement everything."
- **He looks at the screen and finds what code review misses.** Every defect that mattered this
  session came from him reading a screenshot: inconsistent title sizes, clipped icons, weak
  contrast, two same-coloured buttons, copy that meant nothing.
- **He questions premises, not pixels.** *"what does a late but confirmed run mean?"* opened a
  state-machine defect no design review would have found. When he asks what something **means**,
  treat it as a spec gap, not a copy request.
- **He asked for mocks and I shipped code once** (`22a503e`) — corrected with *"i wanted a merged
  mock."* Default to a lab first unless he says implement.
- **English replies** (he asked twice). In-app copy stays Korean.
- Autonomy is broad; his account, credentials, TestFlight and money rulings are not.

---

## 6. Decision log with WHY

**His rulings this session:** ② direction (from the attention lab) · **the logo drop** (mark leaves
the masthead, fills the phrase's ragged right) · **keep the live dot** (overruling me — I repaired
it instead of obeying, binding it to real online-runner count) · colours + drawings in the other
buttons · **§0-septvicies = A** (grace window + server expiry), which his next question then
narrowed.

**Reversals / supersessions:**
- **Wordmark font.** `a8248ae` set body-900 to protect §3's one-per-screen budget; `794f07e` moved
  it to Black Han Sans on his instruction. Home knowingly spends the display font **twice** until
  the real logotype lands, and says so in-file.
- **§0-septvicies narrowed the same day** (`46944a6`): expiry applies to `rawStatus='confirmed'`
  only. **`runner_enroute` must never expire.**

**Refusals:**
- **Did not implement the handoff-gating fix** — changes which screen shouts, borders the frozen
  meetup flow. Queued for his word.
- **Did not touch `supabase/`** at any point.
- **Did not invent the grace-window number** — proposed 30 min, flagged as his.
- **Did not force-push** to repair a garbled commit message (`ede1b65`); three sessions were live
  on trunk and the tree was correct. Prose damage < diverged trunk.

**Two defects I shipped and then caught myself:**
1. Green 「확정됨」 chip above 「지난 예약이 하나 있어요」 — chip and phrase contradicting each other.
2. `dateLabel + ' 예약'` on phrase line 1 → 「8월 4일 (화)…」 truncated against the mark. **I broke my
   own drop law.** Line 1 now takes fixed-length strings only.

---

## 7. Architecture & contracts

- **`src/components/draw-button.tsx` (NEW)** — ground wash + SVG line drawing + 4px depth edge +
  optional live dot + optional foil sheen. Grounds: coral · paper · gold · blue · volt · lilac ·
  amber. **Every ink/sub pair is measured**, ratio written beside its row. Rule in-file: *ink on a
  wash is never chosen by eye* — three of five failed AA when I picked by eye (3.82 / 3.99 / 3.50).
- **The drop law, enforced by layout not discipline** (`home-hero.tsx` `Phrase`): line 1 is its own
  `Text` with `paddingRight: MARK_W` reserving the mark's box; line 2 runs full width.
  **Variable-length values (names, dates, places) may never sit on line 1.**
- **Live-dot honesty contract**: `onlineRunners` = `fetchCertifiedRunners().length`, which already
  filters `.eq('online', true)`. Dot renders only when `> 0`. `.limit(10)` → ten-or-more says
  "10명 이상".
- **⚠ STATUS_MAP flattening (`api.ts:715-730`) — the fact that matters most next session:**

  | DB status | client sees | truth |
  |---|---|---|
  | `confirmed` | confirmed | runner accepted, **nobody set off** |
  | `runner_enroute` | confirmed | runner travelling; `arrived_at` stamps on arrival |
  | `picked_up` | **handoff** | **both sides already confirmed** — dog is with the runner |

  `picked_up` requires BOTH `owner_confirmed_handoff_at` and `runner_confirmed_handoff_at`
  (`transition-booking/index.ts:300-320`, "둘 다 눌러야 picked_up (보험 기점)"). So **home's loud
  coral 인계하기 fires after the handoff is already done**, while the real handoff moment
  (`runner_enroute` + `arrived_at`) renders calm. `Booking.rawStatus` is already populated
  (`api.ts:3915`) — the fix is client-side; `arrived_at` needs adding to `fetchMyBookings`' select.
- **`no_show` exists and is unreachable** — legal transition from `confirmed` (`0001:205`), set by
  **nothing** in `supabase/functions/` (grep: zero hits).
- **Cancel fee ladder**: 0 at ≥24h, **10% inside 24h, half of it the runner's** (0085). A past-time
  booking is definitionally inside that window — which is why home must not imply free cleanup.
- **`owner/home.tsx`'s header is NOT pinned and must not become pinned again** (carried forward
  from `93ca631`). The masthead and ticker are ordinary children of a plain `ScrollView`; the
  absolute overlay, the `paddingTop: PAD_TOP + HEADER_H + heroH` reservation and the collapse
  machinery retired with the GO disc (`bea1bc8`). **Reintroducing an absolute header brings back
  the plate-bleed-through bug** where scroll content ran through the hero text. Real, visible,
  fixed once.
- **`StatusBarCover` must stay mounted LAST** on every screen that uses it (`45bd558`) — after the
  ScrollView in tree order. Move it earlier and content scrolls over the system bar again, the
  exact defect it was added to fix on nine screens.
- **DO-NOT-REFACTOR** (reasons in-file): `run.tsx`'s tracking singleton / settle retry loop /
  overrun ceiling / Live Activity / background-mode block / K7 camera contract; both meetup stage
  machines and the last-effect hydration law; `owner/fitness.tsx`'s collapsing hero; the three
  availability predicates.
- **`routes` embeds MUST name the FK**: `routes!bookings_route_id_fkey(name)`. Unqualified =
  PGRST201 = the whole list dies.

---

## 8. File map

| Path | Role |
|---|---|
| `app/src/components/draw-button.tsx` | **NEW** — drawn action button + 10 SVG drawings |
| `app/src/components/home-hero.tsx` | rewritten: chip · logo-drop phrase · state-driven button sets |
| `app/app/owner/home.tsx` | wordmark-only masthead (no rule), 코스 둘러보기, 나 drawn rows, MEMBER SINCE foot |
| `app/src/components/clubcard.tsx` | `ClubCompactRow` → engraved widget (foil edge, monogram, ledger foot) |
| `app/src/lib/api.ts` | `fetchMemberMeta()` added (auth `created_at` → MEMBER SINCE) |
| `docs/labs/{brand-identity,home-attention,home-state,home-v3,cta-life,cta-drawings,home-full}-lab.html` | the labs, each with `build-*.py` beside it |
| `docs/decisions/awaiting-sean.md` | §0-septvicies **+ its correction** |

Lab generators subset the real fonts from `app/node_modules/@expo-google-fonts/` and inline them:
`python3 docs/labs/build-<name>.py`. Requires `pip3 install fonttools brotli`.

---

## 9. Pending on Sean

### Ops (only he can)
1. **TestFlight** — `npx eas-cli build --platform ios --profile testflight`, then submit. His 2FA.
   **Nothing has ever run on hardware.**
2. **Save the wordmark** to `app/assets/wordmark.png`. His attached logotype is **custom lettering**
   (angular geometric), not any font we own, and it is not on disk anywhere. One edit swaps
   `<Text>` → `<Image>`, and display-font use drops back to once per screen.
3. **Disable email signup** — Supabase dashboard → Auth → Providers. **[from-history]**

### Decisions (each blocks something)
1. 🔴 **§0-septvicies money ruling** — when a `confirmed` run never starts: owner pays the 10%?
   runner compensated (half, per 0085)? zero both ways? *Blocks any resolution button for a stale
   booking — the client cannot draw one until the ledger agrees.*
2. 🔴 **Handoff gating** — move the coral 인계하기 to `runner_enroute` + `arrived_at`? *Blocks: the
   urgent CTA currently fires one state late. Borders the frozen meetup flow, which is why I
   stopped.*
3. **Grace-window number** — proposed `scheduled_at + 30min`. *Blocks the expiry spec.*
4. **§0-sexvicies** — card-statement copy 「댕런 산책 이용료」 → 「도그스하이 러닝 이용료」. Armed, not
   bleeding (zero charges ever). *Must not survive the charging flip.*
5. **Brand lab's six dials** (`ec2e8b0`) — body font · BHS discipline · violet demotion + `#F20914`
   tokenization + App Store icon · motion · voice · material intensity. All unanswered.
6. **Display-font budget** — home spends Black Han Sans twice until the logotype lands. Accept, or
   move the wordmark back to body-900?

---

## 10. Known bugs, gotchas, failure modes

- **⚠ JSX comments cannot sit between attributes, or as the first child of `&&`.** Hit twice; both
  times `tsc` emitted ~7 cascading errors starting far from the real line.
- **⚠ A downscaled screenshot lies about contrast and weight.** My first contrast check sampled the
  caption text instead of the button title and reported "fine"; a **1:1 crop** showed the titles
  were white. **Always crop one specimen at full resolution.**
- **⚠ The booted simulator can change under you.** Mid-session the booted device switched to a
  non-Pro sim and `simctl launch` failed with a bare code-4. Always target the UDID.
- **`sips --cropOffset` is `top left`**, and `sips -Z` resizes the *max* dimension — my crops landed
  on the wrong variant twice.
- **`git commit -m` with backticks lets the shell eat identifiers** — `ede1b65` is missing three.
  Use `git commit -F -` with a quoted heredoc.
- **react-doctor's pre-commit hook prints a large report and exits 0** — not a gate.
- **Metro down renders "No script URL provided"** — start it and relaunch; the screen is fine.
- **The 6 lint errors are the baseline**, all `exhaustive-deps`.

---

## 11. Known-good — do not "fix" these

- The **drop-law layout** (line-1 padding). Looks redundant; it is what makes truncation
  structurally impossible.
- **Measured contrast values** in `draw-button.tsx`. Do not tidy them to rounder hexes.
- The **live dot's zero-state** (no dot, no pulse, different subline) — the branch that makes the
  dot believable everywhere else.
- The **하이 포인트 beacon is deliberately NOT a drawn row** — it owns real gating (balance > 0 OR a
  promotion) and a progress bar; converting it loses the honest gate.
- **Amber = `paper.pending`'s wash** for the unresolved state — semantic, not decorative.
- **Routes were not changed** anywhere in v3. Every destination already existed.
- Route names render **raw**; `status='active'` filtering is a **gate**; `actual_km` means the whole
  tracked buffer.

---

## 12. Ideas & discussions not yet built

- **② 동네 기록소** — the brand lab's recommended territory, unpicked.
- **기록증 (the certificate)** — designed in the brand lab as the object filling Korea's 수료증 gap.
  런데이 ends its 8-week arc with no object; 런클립 users pay for the *typography* of their proof.
  Zero server changes needed. Unruled.
- **Five signature motions** (리드 · 각인 · 보폭 · 파문 · 종이) from the motion audit. Only the
  depth-press (리드's static half) shipped.
- **App Store icon still wears the retired forest/volt palette**; Android icon is unreplaced Expo
  boilerplate. Outside-world exposure, unowned.
- **The logo's speed streak is `#F20914`** — fire red, matching none of the four corals, untokenized.
  Proposed name `streak`.
- **채팅 as a home row** — I put it in confirmed/handoff. Open: does it earn a row on home, or belong
  inside the ticket screen?
- **Post-first-run "finish your profile" nudge** — Sean wants it after the first real run.

---

## 13. Strategic read (my recommendation)

**Rule on the handoff gating, then build the TestFlight binary. Everything else waits.**

The handoff off-by-one is the most consequential thing found this session and it is not a design
issue. Today the app is calm at the exact moment a runner is standing at the door holding out their
hands for the dog, and loud once the dog has already changed hands. That is a trust-path defect in
the one interaction this product exists to make safe, and the fix is ~20 client-side lines gated
only on his word because it borders the frozen meetup flow.

Everything else on home is polish by comparison. The v3 screen is shipped, gated and verified; the
brand dials keep; the labs are committed.

**The argument against me:** "the meetup path is frozen for a reason, and this app has never run on
hardware — change nothing near trust until a real device has exercised it." That is fair, and it
points the same way I do: **TestFlight is the gate on knowing whether any of this is real.** No
client code has met live GPS, push, background location, or a second account. Every screen shipped
before that binary increases what the first device session can invalidate.

So: rule on the gating (cheap, high value, one ruling), then build.

---

## 14. Next 1–3 steps

1. **[read-only]** Confirm gates green (§15). Then read
   **`docs/decisions/handoff-cta-gating.md`** — written 2026-08-20 night, it supersedes
   `awaiting-sean.md` §0-septvicies' handoff section AND that section's correction. It carries
   re-verified line numbers (the older ones had drifted) and the fact that settles the question.
2. **[needs-user → local-edit]** **Sean answers A or B in one word**, then build it. Do NOT build it
   before he answers — two sessions carved this out for his ruling on 2026-08-20 and he accepted the
   carve-out; the overnight grant is general and does not reverse a specific reservation. Either
   answer needs the same additive plumbing first (`arrived_at` into `fetchMyBookings`' select +
   the `Booking` type). **Prove the frozen meetup ranges byte-identical** the way `2ddac83` did —
   and do not touch `owner/meetup.tsx`, which is already correct.
3. **[needs-user]** TestFlight. Smoke list: the runner approach leg · onboarding submission · a real
   `matching` booking · the full handoff sequence. All four need a device and a second account.

---

## 15. Verification commands

Safe (read-only):
```
cd app && ./node_modules/.bin/tsc --noEmit
cd app && node scripts/check-rpc-contracts.mjs && node scripts/check-route-native-imports.mjs && node scripts/check-embed-fk.mjs
cd app && npm run lint --quiet            # must stay at 6 errors
git -C /Users/sean/dev/daengrun status -sb
supabase migration list --linked
supabase functions list
xcrun simctl openurl F2FDB7D7-A669-4BBC-8EF4-677597F3851A "daengrun://owner/home"
xcrun simctl io F2FDB7D7-A669-4BBC-8EF4-677597F3851A screenshot /tmp/shot.png
```
Expensive / changes the world:
```
cd app && npx eas-cli build --platform ios --profile testflight   # Sean's Apple account
supabase db push --linked                                          # never from this domain
```
⚠ **Never create a booking on Sean's account** (PR-0 signal) and **never press the onboarding CTA**
(writes real `dogs` + `addresses` rows).

---

## Environment & test-data state

Nothing seeded or deleted. His account still holds the stale **8월 4일 (화) 오후 3:30** booking that
drives the past-booking state — it is the only reason that state could be verified at all. Simulator
left on `owner/home` running the current Metro bundle. The scratchpad (screenshots, lab renders,
build scripts) is **ephemeral and will not survive**; the labs and generators are committed, the
screenshots are not.

## Ephemeral artifacts — transcribed

**Sean's attached wordmark** (the one thing to re-attach): 도그스하이 in a **custom angular
geometric face** — squared counters, chamfered corners, flat terminals, near-monospace rhythm,
solid near-black (~`#14181C`) on white, roughly 2000×700px, wide letterspacing. **Not** Black Han
Sans, not any font in the repo. Re-attach it, or save it to `app/assets/wordmark.png`.

**Home v3 as built** (if the screenshots are gone): status bar → 도그스하이 wordmark centred (24pt)
with bell right, **no rule under it** → state chip (9px dot + 13pt letterspaced label) → 43pt/50
display phrase over two lines with the running-dog mark (66pt) dropped into line 1's right → 17pt
subline → drawn buttons (96pt primary / 78pt secondary, 28pt titles, 15pt sublines, 4px depth edge)
→ 동네 kicker → engraved gold club widget (foil top edge, 반 monogram, ledger foot) → 동네 러너
strip → 동네 코스 tiles → 코스 둘러보기 → 나 kicker → record row → 하이 포인트 beacon → two drawn
rows → MEMBER SINCE 2026.07 right-aligned foot.

## Agent work

Seven research agents ran during the brand round; **all completed, none running**. Their findings
live in `ec2e8b0`'s lab and commit message; **raw outputs died with the scratchpad**, so everything
sourced from them is **[reported]** unless the lab cites a file:line I checked. Coverage gap worth
naming: market research exhausted its 200-call WebSearch budget mid-run, so rebrand history and
agency attribution are thinner than the colour/type findings (those came from direct asset fetching
and are stronger).

---

## Addendum — O-6 account deletion, on-device verification (2026-08-20 afternoon)

**delete-account v1 is DEPLOYED and matches trunk exactly** — `supabase functions download`
diffed byte-identical against `supabase/functions/delete-account/` and `_shared/ctx.ts`
**[verified-now]**. Migrations applied through 0115 (per the table above); the wire-level
verification (38/38 assertions, five throwaway accounts, success/409/202/401/400 all exercised)
is in the contract's AS DEPLOYED block — that half was already done.

**Token enumeration diff — exact, no orphans either way [verified-now]:** the 0115 RPC raises
exactly twelve state tokens (`active_booking` `active_run` `unsettled_run` `unsettled_payment`
`unpaid_payout` `km_balance` `open_incident` `active_recurring` `club_host_duty` `club_custody`
`club_custody_owner` `club_assignment`); `REFUSALS` in `delete-account-sheet.tsx` holds exactly
those twelve keys. `not_authenticated`/`unauthorized` ride the 401 status arm, `auth_delete_pending`
rides the 202 pending arm, `confirm_required` is deliberately unmapped (client-bug indicator →
fallback arm). The O-7 KEEP line already ships (`8d3c520` → corrected `3be5c2b`) — nothing to add.

**Device pass (sim, Sean's account, post-`3be5c2b` build) [verified-now]:**
- Sheet disclosure renders in contract order (a)–(e); forfeiture plate sits ABOVE the confirm control.
- **O-7 KEEP line present on 3 consecutive opens** — the exact repro count of the original
  nondeterminism — in its `some` branch (his ledger rows are real). The determinism fix holds.
- Hold-to-confirm armed at 1.5 s; destructive button opened.
- **The 409 refusal arm, live end to end:** pressing 계정 삭제 returned `active_booking`; the sheet
  rendered 「아직 삭제할 수 없어요」 with the contract-verbatim copy and 예약 보기 routed to the real
  schedule screen. **Safety was pre-proven, not assumed:** gate #1's exact predicate was measured
  true against production first (2 `runner_enroute` + 2 `refund_pending` on his account), and the
  gate raises before any write. Post-check: `profiles.deleted_at` still null,
  `account_deletions` = 0 rows. Nothing mutated.
- **NOT verified on device, stated plainly:** the success and 202-retry arms. Both need a
  disposable account signed into the app; signup is Kakao-only and no session may create accounts.
  They remain wire-verified only (throwaway accounts, contract AS DEPLOYED). First candidate for
  the TestFlight/second-account smoke list.

Logistics note: this addendum was committed from a worktree at the origin tip because the main
checkout was 2 behind with another session's uncommitted `routes.json` conflicting with the
incoming route commits — pulling would have required stashing someone else's work. `app/` was
byte-identical between the two trees; gates ran green in the main checkout (tsc clean · rpc ✅ ·
56 routes clean · lint 6 errors = baseline).

---

## Opener for the next session

> Client domain (all of `app/`) on daengrun. Work in the MAIN checkout `/Users/sean/dev/daengrun`
> on `redesign-v4` — never a worktree; run `git status` before you touch anything.
>
> Read `docs/handoff-client.md` fully, then `docs/decisions/awaiting-sean.md` — §0-septvicies has a
> **correction below it that supersedes the original spec**; read both and trust the correction.
>
> Owner home v3 is shipped and simulator-verified (`46944a6`): the mark drops into the hero phrase,
> actions are drawn buttons on measured-contrast washes, the live dot is bound to the real
> online-runner count, the club widget is engraved. Settled — do not re-litigate.
>
> The open thread that matters: **home's coral 인계하기 fires one state too late.** `picked_up` means
> the handoff is already done; the real moment is `runner_enroute` + `arrived_at`. Full write-up with
> both candidate answers: `docs/decisions/handoff-cta-gating.md`. The decisive fact found overnight —
> **`owner/meetup.tsx:338` already gates coral on `arrivedAt`**, so home is the one screen breaking a
> rule the app already has. Still waits on Sean: one word, A or B.
>
> ⚠ **A second client session works this same surface** (`exciting-rosalind-e6ac13`, four subagents).
> Read `git log -- <file>` before editing anything in `app/`, and message it before taking a file.
> It is not adversarial — coordination has worked all night — but nobody is holding a console.
>
> Gates before every commit, from `app/`: tsc · check-rpc-contracts · check-route-native-imports ·
> check-embed-fk · `npm run lint --quiet` (**must stay at 6 errors**). That is FIVE, not four. Never create a booking on Sean's account and
> never press the onboarding CTA. Reply in English; in-app copy stays Korean.

---

## Addendum — overnight, 2026-08-20 → 21 (second grant, no announcer online)

**[verified-now] unless tagged otherwise.** Everything below is on trunk.

| what | commit | state |
|---|---|---|
| O-7 KEEP line no longer claims money is owed | `c60a648` | ✅ landed, 5 gates green |
| Handoff-CTA ruling written for Sean (both answers) | `72256bb` | 📋 queued, **not built** |
| Handoff-CTA **plumbing** — `arrived_at` → `fetchMyBookings` + `Booking.arrivedAt` | `36f501b` | ✅ landed; **no gate reads it**, `goState` untouched |
| Coral-ground A/B queued (`§0-duodetricies`) | `a0bda14` | 📋 queued |
| Gate list corrected — there are **FIVE** | `02fa629` | ✅ |
| Coral sub-line AA failure (3.70 → 4.55) | peer session | ✅ fixed by them, my measurement |

### The one code change I made, and why it is not cosmetic

The account-deletion sheet told a departing runner 「아직 정산되지 않은 금액이 있어요」 — *there is an
amount not yet settled* — whenever `fetchLedger()` returned any row. **Row existence cannot support
that claim.** `ledger_items` (0001:264-275) has no paid/settled marker and no migration adds one, so
a runner paid in full still matched. This is the exact fact **O-7 was decided on** ("unpaid is
uncomputable"), which is why the balance gate was rejected and `unpaid_payout` is knowingly inert —
the copy asserted precisely the quantity the ruling records as unknowable. It is a legally relevant
retention disclosure (PIPA 제37조) on the deletion path, where telling someone money is outstanding
is a reason not to finish leaving. Now binds to what the predicate proves.

**The generalisable part** — two earlier passes fixed this same line (existence-not-sum, then
retry-instead-of-silent-catch). Both asked whether the line *appeared*. Neither asked whether it was
*true*. **A disclosure that renders reliably and says something false is worse than one that
flickers**, because the flicker is at least visible.

### My original brief is now closed except where policy blocks it

- **Token enumeration diff: CLEAN.** All 12 state tokens are in the sheet's `REFUSALS` map, plus
  `not_authenticated` (401), `auth_delete_pending` (202) and `confirm_required`. Dispatch is
  `hasOwnProperty` with an explicit `unknown` phase, so a future server token degrades to a named
  fallback, not a blank sheet.
- **O-6 remaining arms (409 refusal, 202 retry): unverified BY POLICY, not by neglect.** Neither can
  be exercised on Sean's account without creating a booking, which he forbade. The announcer already
  verified both over the wire (38/38 at the DB boundary).
- **The REGISTRY's "contract sync owed" note is STALE** — `account-deletion-contract.md` already
  carries the AS DEPLOYED block at its head and the 🔵 CONDITIONAL note inline at §B.3. Left flagged;
  a client session should not edit REGISTRY.

### Two corrections to things you may otherwise believe

1. **react-doctor's pre-commit hook is NOT dead, but WHEN it scans is unknown — so run it manually.**
   Two structural facts, measured: `.githooks/pre-commit:5` probes `./node_modules/.bin/react-doctor`
   from the repo root while react-doctor lives under `app/`, so it always falls to `npx`; and
   `grep -n exit .githooks/pre-commit` returns nothing, so **the hook can never fail a commit.**
   Every hook result is advisory. Sometimes the npx path scans (`✔ Scanned 1 file in 644ms`, main
   checkout) and sometimes it dies with *"configuration differs between the index and worktree"*,
   naming root-level config files **that exist in neither the index nor the tree**. ⚠ **Two trigger
   theories are already falsified:** "it's a dead no-op" (it demonstrably scanned) and "it dies when
   `app/node_modules` is absent" (I hit the error with deps present, `tsc` running from that same
   symlinked `node_modules`). **The trigger is OPEN. Do not edit the hook.** The reliable path,
   always: from `app/`, `./node_modules/.bin/react-doctor <directory>` — a directory, never a file.
2. **`effect-needs-cleanup` on `delete-account-sheet.tsx:238` is a FALSE POSITIVE.** The effect does
   clean up: `retry` is assigned inside a nested `.catch` and cleared at `:252` with `alive = false`.
   The static pass can't follow the closure. Do not "fix" it and do not suppress it blind.

### ⚠ Two hazards for whoever works the main checkout next

- **`docs/routes/strava/bench/routes.json` is another session's live file, and every recent incoming
  commit touches it.** `git pull --rebase --autostash` would very likely conflict and strand their
  in-flight work in a stash. I landed via a separate clean worktree and pushed `HEAD:redesign-v4`
  instead. **Do the same, or wait for them.**
- Consequently the main checkout sits **2 ahead** with commits whose patches are already upstream.
  Verified by patch-id, not assumed — `9e94211…` and `4222c57…` match on both sides — so the next
  rebase drops them silently. Nothing is lost.

### Known-inert, do NOT "fix"

`unpaid_payout`'s refusal copy (`delete-account-sheet.tsx:104`) has the same uncomputable-amount
shape, but it is **unreachable** — nothing writes `payouts`, so it never renders. If `payouts` ever
gains writers the claim becomes computable (`payouts.paid_at`, 0001:295) and the copy becomes
correct. Leave it; don't let a sweep rewrite it on the assumption the token is live.

### react-doctor `effect-needs-cleanup` — adjudicated so far (2026-08-21)

Two client sessions independently hit this rule and both flags were false. **Adjudicate before
acting; do not mass-fix and do not mass-dismiss.** What is settled and what is not:

| site | verdict | why |
|---|---|---|
| `delete-account-sheet.tsx:238` | ✅ **FALSE POSITIVE** (verified, me) | `retry` is assigned inside a nested `.catch` callback and cleared at `:252` with `alive = false`. **No early return in this effect.** |
| `owner/radar.tsx:141` | ✅ **FALSE POSITIVE** (verified, both sessions) | cleanup returns `unsub(); clearInterval(poll); if (nav) clearTimeout(nav)` — all three handles cleared. |
| `tabswipe.tsx:67` | 🔴 **TRUE POSITIVE — read, then FIXED** (`8257988`) | The one real finding of the night, and the one both sessions were most confident was noise. `.start()`'s callback called `setSnap(null)` and scheduled a 500 ms timer while the effect returned nothing. The unmount case was the lesser half: on a **fast second tab change** the previous spring was still running, its callback fired *after* the new effect had set the incoming snapshot, and cleared it — the incoming screen lost its snapshot and showed exactly the ghost that callback exists to prevent. Fixed with a liveness guard + timer ownership; the animation is deliberately NOT stopped and `releaseCapture` NOT skipped (the callback must run on `finished=false`, and cancelling would leak the temp jpg the timer exists to delete). **Not device-verified** — needs two fast swipes on hardware. |
| `ring.tsx:36` | ✅ **FALSE POSITIVE** (verified, peer) | Returns `anim.removeListener(id)`, and the `!animate` early path adds no listener, so there is nothing to clean on it. |
| `club-ui.tsx:276` | ⚠ **UNADJUDICATED** | Not read by either session. **Not the same as "fine."** |
| `fitness.tsx:151` | ⚠ **UNADJUDICATED + DO-NOT-REFACTOR** | Frozen collapsing hero. An analyzer flag is **not** authority to open a frozen file — read `CLAUDE.md` first. |

**Night's tally on this rule: two confirmed false positives, one confirmed TRUE positive.** Treat it
as low-precision in this codebase — neither disable it nor trust it, read every flag. ⚠ The true
positive was the flag both sessions were most confident was noise; the two we'd have bet were real
were the false ones. That inversion is the reason "not on tonight's edits" must never be written as
if it meant "false".

⚠ **There is no single "shape" here — a peer initially characterised both false positives as the
analyzer miscounting an early `return;` path, and that is wrong.** The three structures differ:
`radar` has an early return *and* nested assignment, `delete-account-sheet` has nested assignment
and **no early return at all**, `ring` has an early return with a **top-level** listener. So a fix
that removes early returns would churn code and still trip the rule. The only safe rule is the one
react-doctor prints itself: treat each diagnostic as a starting hypothesis and read the code.
