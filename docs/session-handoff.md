# SESSION HANDOFF — 2026-08-12 · Sean's directive list, sections B/C/D/E · prod on 0074

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**

Companion docs, in reading order:
- **`CLAUDE.md`** — permanent law book (language, gates, migration doctrine, ops authority).
- **`DESIGN.md`** — design law book. Read before ANY UI work. Gained two clauses this session
  (§3b screen-title spec, §3 logo-artwork exemption).
- **`TODOS.md` → "SEAN'S DIRECTIVE LIST — 2026-08-11"** — **his priority order; it outranks the
  P1/P2 backlog below it.** Every item now carries an outcome. Read it before the backlog.
- `docs/plans/km-token-model.md` — **new.** The §A pricing decision, settled. Read before drawing
  any subscription/refill screen.
- `docs/plans/payments-toss-plan.md` — the live payments scope, now reshaped by the km model.

**Build in the MAIN checkout `/Users/sean/dev/daengrun`, branch `redesign-v4`.**
Worktrees under `.claude/worktrees/` are stale snapshots — never build or gate there.

Fact tags: **[verified-now]** checked at handoff · **[reported]** an agent said so, not
independently confirmed · **[from-history]** remembered, recheck · **[uncertain]** assumption.

---

## ⓪ STATUS

| System | State | Provenance |
|---|---|---|
| git | 8 commits this session (`6ba0f75` → this one) on redesign-v4, **0 dirty tracked files** | **[verified-now]** |
| ⚠ Unpushed | **44 commits ahead of `origin/redesign-v4`** — accumulated across several sessions, not just this one. Not pushed unilaterally; see §⑩ | **[verified-now]** |
| Database | prod through **0074**, local == remote, nothing unpushed | **[verified-now]** (`migration list`) |
| SQL harness | **356 / 0** (was 336 — 20 new pins across 111/112) | **[verified-now]** |
| tsc | 0 errors (re-run after the colophon edit) | **[verified-now]** |
| check-rpc | 80 calls / 116 signatures, all match | **[verified-now]** |
| geo runner | 38 / 0 | **[verified-now]** |
| iOS build | `Build Succeeded, 0 error(s)` with the new native module linked (`Installing InstagramShare (1.0.0)`) | **[verified-now]** |
| **Real customers** | still **ZERO**. Nothing this session changed that, and nothing in the repo can | **[from-history]** |
| Instagram share | renders and gates correctly on the simulator; **the actual handoff to Instagram is unverifiable here** — Instagram cannot be installed on the iOS simulator | **[uncertain]** — see §⑩ |

**Sean's directive list: 25 of 30 items closed.** What remains is in §⑪ — and three of the five
are blocked on him, not on code.

---

## ① Where the product actually is

Korean dog-running marketplace (RN/Expo + Supabase), Banpo pilot, PMF gate M1 rebooking ≥60%.

This session was almost entirely **Sean's list**, in his order: B (navigation), E (runner side),
D (owner side), C (community). It was design and client work with two small server slices behind
it. The most consequential output is not a screen — it is `docs/plans/km-token-model.md`, which
settles the pricing model he asked me to think through before drawing anything.

The single most important fact for planning is unchanged: **no real person has ever used this app.**

## ② What shipped — 7 commits, `6ba0f75` → `a4bf5e8`

**§A — the km prepay / token model (decision, not code).** `docs/plans/km-token-model.md`.
Sean's three open questions answered, with measured ground truth rather than invention:
- **Expiry**: paid km never expires; granted km (welcome 5km, bundle bonus) does — 30d / 90d.
  Two buckets, always rendered separately. Spend granted first, then oldest paid.
- **Mid-run overrun**: reserve `planned + 2km` at BOOKING (held, not spent); **never interrupt the
  run, never ping the owner mid-run**; settle `min(actual, planned+2)` floored at 3km; the platform
  absorbs the rest. This is not a new policy — the codebase *already* charges owners planned km
  and pays runners actual km, and silently absorbs the gap. I wrote down what is already true.
- **Refunds**: service-side refunds return km to the bucket they came from; cash only on deliberate
  close-out, paid km only, at face price. ⚠ **Every debit must record its own `won_value`**, because
  0066's 50% en-route fee is runner compensation paid in ₩ — the one place the two currencies meet.
- Price: **₩5,000/km, 3km floor, base fare retired.** Revenue-neutral at the modal 5km Banpo run
  (24,900 → 25,000). Bundle discounts land as **bonus km**, never a discounted ₩/km, so a cash
  refund stays exactly `5,000 × unused paid km`.
- 🔴 **Sequencing, not negotiable: model (done) → ledger table + pins → screens.** Granted km can
  ship before Toss; **paid km cannot** — selling km is selling stored value, which is deferred
  revenue and needs 사업자등록 + 통신판매업.
- ⚠ This is the app's **second** currency. `miles_ledger` (댕마일) already exists. The "unique token
  icon" Sean asked for is not decoration — its job is to make km ≠ 마일 legible at 16px.

**§B — navigation.**
- 홈 moved to index 2 on both roles (`bottomnav.tsx`), relative order otherwise preserved.
- 🔴 **Edge-swipe tab switching built** (`app/src/components/tabswipe.tsx`) — Sean said the motion
  wasn't working because I had scoped it, not built it. `EDGE=24 · ARM_DX=12 · ARM_RATIO=1.75 ·
  COMMIT=W*0.28`. **Capture-phase only.** The bubble-phase handler was written, measured as
  never-firing, and deleted — RN's ScrollView claims the responder on touch-DOWN, so bubble never
  reaches the parent. The header says so, so nobody re-adds it.
- Screen-title spec written into DESIGN.md §3b (30 / 900 / lineHeight 37).
- `FOREST = '#0F1D13'` retired from 12 files.

**§E — runner side.** Logo conflict adjudicated by Sean (빕 stays, no logo). Run-info widget made
action-inviting (Ⓐ①), available-time widget collapsed (Ⓑ②), duplicate 하이클럽 title fixed, 기록
moved from 마이 to 홈, invisible 역할 전환 button fixed, dead 예약 관리 button fixed.
**Profit tab parked by Sean** — four *different objects* now sit in `docs/labs/profit-tab-lab.html`
awaiting a pick (my first three were three recolourings of one screen; he was right to reject them).

**§D — owner side.** Price tag off the reserve button, small-info-text sweep (with a scanner, not
an eyeball), 마이 subtext filler removed across all 8 MENU rows, and **`0073_address_note.sql`** —
`owner_update_address_detail()`, party gate first, 60-char cap, single-column write. Its header
states in writing that it is **a narrow writer, not a seal** (see §⑩).

**§C — community, the Instagram direction.** Sean's five instructions, all implemented:
- Heart replaces 발자국 (action row + double-tap).
- **`0074_handles_and_feed_claims.sql`** — `profiles.handle`, IG rules (lowercase, 3–20,
  `[a-z0-9_.]`, no leading/trailing/double dots, reserved list, case-insensitive unique),
  `set_my_handle()` idempotent on the same value.
- Story rail derived from the feed already on screen — dogs and clubs both (his Ⓑ① pick over my
  Ⓑ③), purple ring for users, gold for clubs.
- **Free upload.** `compose.tsx` flipped from a run-picker to a free composer; attaching a run is
  now opt-in. The enforcement line moved from the **upload** to the **claim**: a post carrying
  `km`/`durationSec`/`trace` must reference a real `runs` row on the author's own booking.
  *자랑은 누구나, 기록은 달린 사람만.* **F1 pins Sean's decision** so a future session can't quietly
  revert to "completed runs only".
- **`RunShareCard`** extracted (`app/src/components/run-share-card.tsx`) as the single source for
  the share artifact + **one-tap Instagram Stories** via a local Expo Swift module
  (`app/modules/instagram-share/`), availability-gated.
- Colophon rewritten to say only what the system keeps.

**One more honesty fix, found while writing this document.** Two lines below the colophon I had
just made honest, `community.tsx` still printed **"오늘 N건"** — and `fetchFeed` has no date filter
at all (`.order(created_at).limit(30)`, all time). Pre-existing since `afd4dcd` (08-03), but I
rewrote the sentence directly above it and walked past this one. Changed to **"최근 N건"**, which is
what the query actually returns. tsc re-run, 0 errors.

## ③ Standing doctrines — the ones that bit this session

1. **Honesty is a hard law**, and it applies to the sentence *next to* the one you just fixed
   (see the dirty file above).
2. **Commit gate**: `tsc --noEmit` + `check-rpc-contracts.mjs` + `bash app/test/run-geo-tests.sh`,
   plus the SQL harness for anything touching migrations.
3. **Money changes get their own migration + adversarial cycle + mutation-proof pins** (0059).
   Each pin must go red under a single named revert, **and you must run the revert.** Done for both
   0073 and 0074 — the measured maps are in each suite's header.
4. **Definer functions**: `set search_path = public, pg_temp` in the BODY. Party gate before state
   gate. Identical errors for absent vs not-yours.
5. **`_fail` arguments are pre-computed into a variable, never a subquery** (110 header law).
6. 🔴 **Definer trigger functions are still definer functions.** 99 S1 sweeps the whole schema for
   anon-executable definers and went red on `enforce_feed_claim()` even though nothing calls it
   directly. `revoke execute … from public, anon` is not optional for triggers.
7. **Never `git add -A`** — untracked investor decks and secrets live in the tree.

## ④ Defect patterns this session produced — read before writing pins

1. 🔴 **A claim-key whitelist is a compatibility surface.** My first draft of `_feed_claims_run`
   included `badges` — and broke **15 existing pins** at once. Server-side club recap auto-posts
   write `badges` with no `booking_id` in **five** places (0031:123, 0037, 0038, 0045, 0048).
   Narrowed to `km`/`durationSec`/`trace`; **F7 is now a regression pin** so nobody re-adds it.
   The dangerous badges (`★ 역대 최장 거리`) are safe because `shareRunToFeed` always writes them
   *with* `km` (api.ts:2921-2925) — so the km gate already covers them. **Measured, not assumed.**
2. **A CHECK constraint validates existing rows; a trigger does not.** The claim gate is a trigger
   specifically because a CHECK would fail the migration if any prod post already violated it.
3. **A regex sweep can rewrite its own comment.** The FOREST purge replaced `FOREST` → `paper.ink`
   *inside the note I had just written explaining the purge.* Needed a second corrective pass.
4. **Test on device before believing a gesture works.** The bubble-phase pan handler looked correct
   and never fired once. Deleting it was better than leaving code that reads as working.
5. **A layout parent can be somewhere other than where it looks.** The owner/meetup note strip
   rendered inside the 290px `mapPlate`, overlapping the top bar, because `s.topBar` lives *inside*
   `mapPlate`. tsc, gates, and review all passed. **Only looking at the screen caught it.**

## ⑤ Architecture, contracts, DO-NOT-REFACTOR

- **DO-NOT-REFACTOR**: owner-home + fitness collapsing heroes (pinned overlay + paddingTop
  reservation + transform/opacity native driver only) · meetup stage machines, polling,
  confirmHandoff, once-law hydration ordering · the 2-layer matching compositor · availability's
  3 deliberately distinct predicates.
- **`tabswipe.tsx` is capture-only by measurement.** Do not "fix" it into a bubble handler.
  A real horizontal pager (shared surface, no unmount) is a separate slice and fights the frozen
  collapsing heroes — the four blockers are written out in TODOS §B.
- **`RunShareCard` is deliberately NOT unified with the feed card.** Codex asked for that; it is
  over-unification. The feed card is a horizontally-flowing post row; this is a 9:16 poster. Same
  data, different objects. The component header says so.
- **`RunShareCard` must stay pure** (props only, no fetching, no state) — `react-native-view-shot`
  captures an empty frame if anything async is still resolving.
- **BUG A**: Oswald (`useNumFont`) needs explicit `lineHeight ≥ 1.2×` or ascenders clip.
  `Math.ceil`, never `round`.
- **`session_dogs` has a `club_v1_axes_sync` trigger** that recomputes derived columns. Hand-setting
  them in a test or an RPC gets silently reverted.

## ⑥ Known-good — do NOT "fix" these

Zero TouchableOpacity app-wide · the receipt seal ceremony · `club/case`'s LoadGate idiom · the GPS
honesty stack in `run.tsx` · shot's photo truthfulness · the 0060/0065 pickup-address gating ·
the volt block as the export skin (**it is the only skin that does not require a photo**, and
completion photos are optional — a photo-requiring default would lock out every photo-less run).

Deliberate, don't "simplify": dark artifacts (passport record face, seal band, club night world,
settlement ticket, floating request ticket) and Peak moments — exempt from decluttering by §7b.

## ⑦ Gotchas & failure modes

- 🔴 **A local Expo native module can autolink and still never build.** `expo-modules-autolinking
  search` listed `instagram-share` while `pod install` created no target — so the app compiled
  clean, ran fine, and the module simply wasn't there. **Root cause: a missing `.podspec`.**
  An Expo local module needs `expo-module.config.json` **AND** `ios/<Name>.podspec`. Verify by
  grepping the pod install output for `Installing <Name>`, not by a successful build.
- **`.runOnQueue` exists only on `AsyncFunction`**, not on a sync `Function` — for a main-thread
  sync call use a `Thread.isMainThread` guard + `DispatchQueue.main.sync`.
- 🔴 **`app/ios/` is gitignored** (`app/.gitignore:44`). Both Codex and I initially treated the
  generated `Info.plist` as the source of truth. **`app.json` is the tracked source**; the plist
  regenerates on prebuild. Never hand-edit the plist.
- **Instagram Stories needs a keyed pasteboard dictionary** (`com.instagram.sharedSticker.backgroundImage`)
  plus `LSApplicationQueriesSchemes`. RN's built-in `Share` cannot construct that — hence the module.
- **Tools that exit 0 on failure**: Expo/CocoaPods without a UTF-8 locale dies but exits 0, leaving
  a stale binary. Always `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`.
- **Two Metro instances deadlock on port 8081.** Kill all, then one clean run.
- **Harness**: `pkill -f "bin/postgres"` first, then `sleep 3`.
- ⚠ **The geo runner returned 37/1 once** under concurrent build load, then 38/0 on four
  consecutive runs. Recorded rather than dismissed — if you see it, it is probably load, but
  confirm rather than assume.
- **`check-rpc` parses no return types** and never removes a dropped signature — a changed return
  shape passes both gates and breaks at runtime.

## ⑧ Working with Codex

`codex` reviewed §D and §C in Sean's absence and earned it: it found the `addresses` grant hole
(§⑩), both feed-colophon falsehoods, and the `RunShareCard` duplication. It was **wrong once** —
it and I both asserted the iOS `Info.plist` was the tracked source when `app/ios/` is gitignored.
Prefix prompts with the skills/gstack filesystem boundary line; tell it to **execute attacks, not
read code**, and to rank findings without hedging.

```bash
source ~/.claude/skills/gstack/bin/gstack-codex-probe
_gstack_codex_timeout_wrapper 900 codex exec "<prompt>" -C /Users/sean/dev/daengrun -s read-only
```

## 🔴 ⑨ Two open P1s from this session's reviews

**P1 HONESTY — the feed is not a neighbourhood.** `fetchFeed()` (api.ts) has **no district filter
of any kind**, and `fetchClubOverview()` **hard-codes 반포동**, on a screen titled 동네 피드.
The colophon no longer *claims* neighbourhood scoping (fixed), so this is now a product gap rather
than a lie — but it also **blocks the story rail from ever meaning "our neighbourhood's dogs"**,
which is what Sean's Ⓑ① pick wants it to mean. Note the TODOS entry is partly stale: its clause ①
(fabricated run claims) **was closed by 0074's claim gate**; clause ② is what remains.

**P1 SECURITY — `addresses` has no column grants.** Pre-existing, verified, and **0073 deliberately
does not claim to fix it**. RLS is row-scoped; there are zero `grant`/`revoke` statements for
`addresses` in any migration, so `authenticated` holds Supabase's default full DML and a client can
PATCH any column of *its own* rows. Not cross-tenant (the policy's `USING` is reused as the UPDATE
check). The real exposure is **integrity**: `bookings.address_id` points at those rows, so editing
`addr` while keeping `lat/lng` produces a falsely-pinned address on a handoff screen — a safety
surface. Fix is its own slice: `revoke update on addresses from authenticated`, then move
`setAddressPin` and `setDefaultAddress` onto narrow RPCs the way 0073 already is.
⚠ **Do not do this half-way** — an RPC added while the grants stay open is security theater. I
declined to half-fix it this session for exactly that reason.

## 🔴 ⑩ Pending on Sean — nothing below can be done for you

**New this session:**
| Item | Detail |
|---|---|
| **Meta / Facebook App ID** | `source_application` currently falls back to the bundle id via `expo.extra.instagramAppId`. **An empty Instagram story editor on device is this.** |
| **Instagram device smoke test** | Cannot be done here — Instagram will not install on the iOS simulator. Physical device: open a completed run's 인증샷 → swipe to 볼트 블록 → confirm the coral **인스타 스토리로** button appears → tap → the card should arrive as the story background. |
| **Profit tab pick** | Four *different objects* in `docs/labs/profit-tab-lab.html`. Parked by you; pick by number. |
| **D12 font consistency** | Pre-reserve card vs the rest. Left open deliberately — it needs your eye, and it should run after the other picks land so it sweeps final shapes. |
| **Push `redesign-v4`?** | The branch is **44 commits ahead of `origin/redesign-v4`**, accumulated over several sessions. `CLAUDE.md` authorizes me to push, but a 44-commit push I did not accumulate is your call, not a handoff side-effect. Say the word and it goes. |

**Still outstanding from before — payments, the only thing between the app and its first ₩:**
사업자등록 (홈택스, same-day, free) → 통신판매업 신고 (~₩40,000/yr) → 토스페이먼츠 계약 (1–2wk) →
`TOSS_SECRET_KEY`. ~2–3 weeks from filing. ⚠ 예비창업패키지 2027 (~₩40M) closes the moment
사업자등록 lands. **The km model makes this more urgent, not less: paid km is stored value and
cannot ship without those filings.**

⚠ **Do NOT pre-delete `pay.tsx:334` (예약 확정하기) or `pay.tsx:299`** — `:334` is the only path a
booking has into `matching` today and `:299` is currently TRUE. Toss-plan step 3.

**Also yours:** NCP console + `NAVER_GEOCODE_SECRET` · counsel on the privacy-policy coordinates
rider · the `identity_verified` cleanup (9 of 9 runner rows fabricated) · TestFlight ·
**recruiting one real owner and one real runner.**

## ⑪ Next 1–3

**Sean's list, what's actually left (5 items, 3 of them his):**
1. **§A screens** — the km ledger table + pins, *then* the subscription/refill screen and the token
   icon. The model is settled; the sequencing rule in `km-token-model.md` is not negotiable.
2. **§D12** font consistency — needs Sean's eye.
3. **§F onboarding** (both roles) — nothing exists today; ties to A's free-5km grant.
4. **§F real sample routes** — `seed.sql` routes carry no `trace`; needs real GPS promoted from a
   completed `runs.trace`.
5. **§E/§F full design sweep** — after the remaining picks land, so it sweeps final shapes.

**Then, and this has not changed:** the next unit of progress is **a real two-person run followed
by a second booking**, not more building. `node scripts/pilot-metrics.mjs` exists and reports `—`
honestly. It needs people, not code.

**Also queued, not on Sean's list:** the two P1s in §⑨ · the 절취선 perforation renders **solid** on
iOS Fabric in 15 single-side usages (needs a shared `<Perforation />` primitive — the RN border
property cannot express this shape) · `my.tsx` and `cards.tsx` scroll under the status bar ·
`seed.sql:33-37` emoji rendering as colour emoji in prod data.

## ⑫ Environment & test data on prod

`s4kim2025` is the only account with bookings and is registered in `club_test_accounts`, so
`pilot-metrics.mjs` correctly excludes it and reports `—`. `push_tokens` has **1 row**.
Two 8/4 `runner_enroute` bookings are staged for map/cancel verification; the in-app cancel is the
honest way to clear them. **This account has no club**, so the club world is unreachable in the
simulator — club screens are gate-verified, never seen.

## ⑬ Verification commands

**Safe / read-only**
```bash
git -C /Users/sean/dev/daengrun log --oneline -7 && git -C /Users/sean/dev/daengrun status --porcelain
cd /Users/sean/dev/daengrun/app && ./node_modules/.bin/tsc --noEmit
cd /Users/sean/dev/daengrun/app && node scripts/check-rpc-contracts.mjs
bash /Users/sean/dev/daengrun/app/test/run-geo-tests.sh
cd /Users/sean/dev/daengrun && supabase migration list
node /Users/sean/dev/daengrun/scripts/pilot-metrics.mjs
```
**Expensive but non-destructive** — PG16 harness (~2.5 min; expect **356 / 0**)
```bash
pkill -f "bin/postgres"; sleep 3; cd /Users/sean/dev/daengrun/supabase/tests && PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash harness.sh 2>&1 | tail -3
```
**App on the simulator** (from `app/`) — the UTF-8 locale is load-bearing, see §⑦
```bash
cd /Users/sean/dev/daengrun/app && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 npx expo run:ios
```
**Destructive / changes the world — confirm with Sean first**
`supabase db push` · `supabase functions deploy <name>` · `node scripts/geocode-backfill.mjs --yes` ·
`node scripts/wipe-test-data.mjs` · `node scripts/migrate-private-media.mjs --yes --purge` ·
any in-app cancel of the 8/4 test bookings.
