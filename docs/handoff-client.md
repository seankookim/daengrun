# HANDOFF — client domain (`app/`), written 2026-08-21 morning

**Read with this, in order:** `docs/plans/2026-08-20-client-gap-straightening.md` (the 60-item gap
inventory + its ENDING STATE section + Q7–Q10 queue) · `docs/decisions/awaiting-sean.md` (his live
decision queue; §0-duodetricies and §0-undetricies are recent) · `DESIGN.md` (tokens, laws) ·
`CLAUDE.md` (permanent laws) · `docs/labs/RULINGS-2026-08-19-journey.md` (his verbatim rulings) ·
`docs/session-handoff.md` (fleet-wide, announcer-owned — **do not edit**).

Domain: **client — all of `app/`**. Never write a migration or touch `supabase/`.
This file **replaces** the 2026-08-20-afternoon version; git history is the archive
(`git log --follow docs/handoff-client.md`). ⚠ A *second* client session wrote the version this
replaces; it went offline overnight. Its content is preserved in git and its facts are folded in
below where still true.

---

## 1. Status table

| System | State | Tag |
|---|---|---|
| Trunk | `redesign-v4` @ **`13749af`**; my branch `claude/client-redesign-v4-267d6b` **0 ahead / 0 behind / clean** | **[verified-now]** |
| MAIN CHECKOUT `/Users/sean/dev/daengrun` | **clean, 0 ahead / 0 behind** at `f82e779`→ now trunk. Was stuck mid-merge; I abandoned it deliberately (§6) | **[verified-now]** |
| `tsc --noEmit` | clean | **[verified-now]** |
| `check-rpc-contracts.mjs` | ✅ all calls match signatures | **[verified-now]** |
| `check-route-native-imports.mjs` | ✅ **57 routes**, none | **[verified-now]** |
| `check-embed-fk.mjs` | ✅ 1 pair checked · 109 files — **NEW GATE, written this session** | **[verified-now]** |
| `npm run lint --quiet` | **270 problems, 6 errors** = baseline (was 279/6 at session start — net −9 warnings). A 7th error is yours | **[verified-now]** |
| Migrations (production) | applied through **0115** (0105 absent by design — superseded) | **[verified-now]** |
| Edge functions | create-booking-hold v10 · transition-booking v34 · settle-run v14 · open-drop v8 · geocode-address v1 · collect-charges v1 · confirm-payment v1 · delete-account v1 — all ACTIVE | **[verified-now]** |
| iOS device | 🔴 **nothing has ever run on hardware.** Simulator only (iPhone 17 Pro `F2FDB7D7-A669-4BBC-8EF4-677597F3851A`). TestFlight zero builds | **[verified-now]** |
| Bundle id | **`com.seankookim.dogshigh`** (renamed by another session at `b6ee192`, Sean's call). `app.json` `scheme` remains `"daengrun"` — different thing, must stay | **[verified-now]** |
| Other sessions | **announcer-v3 is ONLINE** (started ~1h ago). Route-geometry, marketing, and the 2nd client session are all gone | **[verified-now]** |

---

## 2. Goal & current state

Banpo pilot, PMF gate M1 rebooking 60%. This session ran overnight under Sean's second grant, then
interactively with him this morning.

| Workstream | State |
|---|---|
| Gap straightening (60 items) | **~40 fixed and pushed.** Remainder is low-severity tail + Sean-gated |
| Runner home ① redesign | **SHIPPED** (`65a9ca5`) — his pick, four additions, coral rule flipped |
| Runner ticket info (A·B·C·D) | **SHIPPED** in the same commit |
| Handoff dog card (tags/vaccines) | **SHIPPED**; the rest of "E" was **withdrawn as duplicate** (§6) |
| Back-button trap class | **CLOSED** — 45 screens, one shared guard |
| Raw-English-to-Korean-user class | **CLOSED** — no path can print PostgREST English now |
| Naver appname vs bundle id | **FIXED** (`13749af`) — device-unverifiable |
| Coral CTA ground A/B | **BLOCKED on Sean** (`§0-duodetricies`) |
| Handoff-CTA gating | **BLOCKED on Sean.** Plumbing landed (`arrived_at` threaded, `goState` untouched) |
| TestFlight | **BLOCKED on Sean's 2FA.** Sean chose "keep building, Build 0 later" (`4d7f57d`) |

---

## 3. What shipped this session (by theme)

**Criticals.** Runner nomination had **never worked in production** — `REQ_SELECT` carried a bare
`routes(name)` and `bookings` has two FKs to `routes`, so PostgREST answered PGRST201 and the
directed-inbox leg swallowed the error by design. Fixed + a new gate (`check-embed-fk.mjs`) that
makes the class impossible. Also: SOS resolved the wrong party on a cold Live Activity deep link
(silently telling a runner holding a dog that no run was in progress); the checkout fee card said
「취소 수수료 없음」 against the real 10%/50% ladder; a ₩3,900 라이브캠 add-on was purchasable with no
transport code; runner payout estimates used the OWNER's base fare (8% low on the accept screen);
and `isOfferable` would have emptied a town's catalog on the first route promotion.

**Journey flow.** The handoff push landed the runner on the request inbox instead of the meetup
screen (`title.includes('요청')` — now an exact-title table). A searching booking had **no management
path anywhere in the app**. `/owner/live` was a cold-entry trap. The radar stranded forever on four
statuses. The meetup cancel guard was armed one line after its own `await`.

**Incident states.** Both custody screens ran the ceremony **backwards** during an incident (seals
un-drawing 2/2 → 1/2 while something had gone wrong with the dog); `owner/live` never left, clock
counting forever under a network-trouble sentence; `runner/run` had zero booking-status reads.

**Realtime + honesty.** Dead channels cached as healthy forever; chat claimed a connection it never
verified and had no fallback; home's hero had no refresh path at all; seven screens rendered
failures as facts; coral CTA contrast was 3.70:1.

**Structure.** 45 trap screens (`src/lib/nav.ts`), `+not-found.tsx`, `payments` returnTo allowlist,
a photo-gallery **wipe** on a failed read, week-stats phantom km, past-dated inbox requests, dead
launch-screen buttons during the auth window, club a11y.

**Runner home ①** (`65a9ca5`) + **labs**: `runner-home-glance-lab.html`, `runner-ticket-info-lab.html`.

---

## 4. Standing doctrines (canonical: `CLAUDE.md`, `DESIGN.md`)

1. **FIVE gates before every commit**, from `app/`: tsc · check-rpc-contracts ·
   check-route-native-imports · **check-embed-fk** · `npm run lint --quiet` (**must stay 6 errors**).
   ⚠ The plan file's own P5 listed four until I corrected it — a written gate list goes stale the
   moment a gate is added.
2. **Honesty**: bind real fields or omit; failures shown as failures; loading is not 0; no dead
   buttons; **error and not-found are different states with different sentences**.
3. **Gate on `rawStatus`, never on STATUS_MAP display vocabulary.**
4. **One coral per frame**; coral = your turn. On runner home it now belongs to the **in-flight job**.
5. **DO-NOT-REFACTOR**: `owner/fitness.tsx` collapsing hero · both meetup stage machines ·
   `run.tsx`'s in-file freezes · the three availability predicates.
6. **English comments everywhere.** Korean only inside user-facing strings.

---

## 5. Working-relationship norms

- **Terse, by number.** "①", "A", "sure.", "let's work with 1".
- **He checks the running app, and he is right when he does.** He challenged my proposed 인계 card
  with *"doesnt the 인계 screen clash with the already existing one? check with the current app ui"* —
  it did, and two of my claims were false. **When he says check, check the running app, not the code.**
- **Labs first, he picks by number** (`DESIGN.md`: labs are the sanctioned mockup arena). He once
  corrected a session for shipping code when he wanted a mock. Do not skip the lab.
- **He grants wide autonomy overnight** and expects work to continue without permission-asking —
  but credential VALUES, his account, and product calls with real-world consequences stay his.
- **English replies.** In-app copy stays Korean.

---

## 6. Decision log with WHY

**Sean's decisions this session:** ① (runner home, "let's work with 1") · chat directly beneath the
coral, which forced chat to be **ink outline** not a second coral (two corals breaks the glance) ·
the four ticket additions together · "keep building, Build 0 later" (`4d7f57d`) · the bundle rename
(`b6ee192`).

**My reversals / corrections — five, all against things already committed:**
1. **react-doctor "trigger = absent node_modules"** — I called it measured. It was a bad A/B (removing
   the symlink varied two things at once). A peer falsified it with a counterexample. **Trigger is
   now OPEN**; see Q10.
2. **"These analyzer flags share one shape"** — three sites, three structures. Wrong mechanism.
3. **Clearing four analyzer findings I had not read** — "not on tonight's edits" ≠ "false".
   `tabswipe.tsx` then turned out to be a **real bug**.
4. **My own comment on my own fix** claiming a teardown covers a callback it cannot reach.
5. **The 인계 card (E)** — ~90% duplicate of a shipped screen. Withdrawn. Two claims inside it were
   false: the memo does NOT disappear on accept, and a map/navigation handoff already exists.

**Refusals:**
- **Did not implement the handoff-CTA gating** — Sean reserved it; a peer wanted to build it and I
  flagged that a general grant is not authority to reverse a specific reservation. They stood down.
- **Did not repair the react-doctor hook** — trigger unknown; a working hook rewritten on a wrong
  diagnosis is its own defect.
- **Did not resolve the routes.json rebase conflict** — route data, not my domain to adjudicate.
- **Did not touch `supabase/`** at any point.

**The merge decision (this morning), stated deliberately:** the main checkout was mid-merge
(MERGE_HEAD `94e46fb`, 2 unresolved, 103 staged). I patch-id'd its 4 local commits: **3 already
upstream**, 1 genuinely unpushed (`45de013`, routes). Finishing would have produced a merge commit
for landed work → **ABANDONED**. `merge --abort` (non-destructive), then rebase — which conflicted
on the unpushed one against much newer route data. Preserved it as branch
**`rescue/routes-basemap-45de013`** and reset the main checkout to origin. **Nothing lost; main
checkout finally clean.** Backup existed at `/Users/sean/dev/daengrun-rescue-2026-08-20/`.

---

## 7. Architecture & contracts

- **`src/lib/nav.ts` (NEW)** — `goBackOrHome()`. `router.back()` is a no-op on an empty stack and
  this app manufactures them (every route is `daengrun://<path>`, pushes deep-link, two Live
  Activities open from the lock screen) while the root Stack has **no header and no back-swipe**.
  Fallback is role-aware. ⚠ Inherits the `session.role` module-state limitation.
- **`scripts/check-embed-fk.mjs` (NEW, 5th gate)** — refuses an unqualified `routes(` inside a
  `bookings` select. Mutation-verified: reverting the one-line fix reddens it.
- **`NOT_FOUND` token (`api.ts`)** — zero rows is not an error. Screens pick between
  「…을 찾을 수 없어요」 (no retry — retrying cannot conjure a row) and 「…을 불러오지 못했어요」 + 다시 시도.
- **`relWhen()` (`runner/home.tsx`)** — relative time, **clamped both ends**: >12h late reads
  「지난 예약」, >24h ahead falls back to the date. The clamp exists because the device rendered
  「400시간 59분 늦음」 in critical red. **Do not remove the clamp.**
- **`liveOwnsCoral` (`runner/home.tsx`)** — widened from `active` to **any in-flight job**. This is
  the ① rule. Reverting it reintroduces "no coral anywhere when the inbox is empty".
- **⚠ `appname` vs `scheme`** (`runner/meetup.tsx:271` / `app.json:42`) — `appname` must equal the
  **bundle id** (`com.seankookim.dogshigh`); `scheme` is our own protocol and stays `"daengrun"`.
  They look alike and are unrelated. A stale `appname` does not fail loudly — Naver opens and the
  runner has no route back.
- **`subscribeShared` retire is CONDITIONAL** (`!joined && isConnected()`) — phoenix errors every
  channel on backgrounding and heals via rejoin; unconditional retiring would leave the app
  poll-only after the first background cycle. **DO-NOT-REFACTOR** without reading that reasoning.
- **`RunnerWeekStats.runs`/`.km` are nullable, `net` is not** — they need a second read that can fail
  independently; `net` comes straight from the ledger.
- Carried forward, still true: `owner/home.tsx`'s header must NOT become pinned · `StatusBarCover`
  mounts LAST · `routes` embeds MUST name the FK · the drop-law layout in `home-hero.tsx`.

---

## 8. File map (this session)

| Path | Role |
|---|---|
| `app/src/lib/nav.ts` | **NEW** — the shared back guard |
| `app/scripts/check-embed-fk.mjs` | **NEW** — 5th commit gate |
| `app/app/+not-found.tsx` | **NEW** — Korean not-found, role-aware exit |
| `app/src/lib/api.ts` | NOT_FOUND · subscribeShared status · payout constant · isOfferable gate · REQ_SELECT FK · ledger/week-stats truth · photo-wipe guard · inbox time filter · `RunnerJob.dogPhotoUrl` · `MeetupInfo` tags/vaccines |
| `app/app/runner/home.tsx` | ① rule + ticket A·B·C·D + `relWhen` + availability three-state |
| `app/app/runner/meetup.tsx` | tags/vaccines line · appname fix · back guard |
| `app/app/owner/{live,meetup,radar,schedule,report,reschedule}.tsx` | incident arms · terminal states · sheet reachability · not-found split |
| `app/app/chat.tsx` | real SUBSCRIBED indicator · poll fallback · leak fix |
| `docs/plans/2026-08-20-client-gap-straightening.md` | the inventory, audit trail, ENDING STATE, Q7–Q10 |
| `docs/labs/runner-home-glance-lab.html` | ①–④ + thumb dock (artifact `2c120fff…`) |
| `docs/labs/runner-ticket-info-lab.html` | A–D drawn separately + the correction (artifact `4246799d…`) |

---

## 9. Pending on Sean

### Ops (only he can)
1. 🔴 **TestFlight** — `npx eas-cli build --platform ios --profile testflight`. **His 2FA.** He chose
   to defer ("keep building, Build 0 later", `4d7f57d`) — deferred, **not** closed.
2. **Disable email signup** — Supabase dashboard → Auth → Providers. **[from-history]**

### Decisions (each blocks something)
1. **Coral CTA ground A/B** (`§0-duodetricies`) — `paper.wash` on the current coral is 4.55:1, which
   is the ceiling-bound maximum; darkening the ground to the existing `edge` token buys real
   headroom but visibly deepens a CTA he approved by number. *Blocks: nothing urgent; it is a
   taste call with measurements attached.*
2. **Handoff-CTA gating** — move the coral 인계하기 to `runner_enroute` + `arrived_at`? Plumbing is
   landed. *Blocks: the owner CTA still fires one state late.*
3. **react-doctor hook** (Q10) — three separable parts: repair the path lookup · add the missing
   `exit 1` · choose the blocking level against a 347-warning backlog. **Nobody should touch it
   until the config-error trigger is known.**
4. **Runner home leftovers** — B (dog face) is currently ON the ticket per his "four together"; my
   own recommendation had been face-on-handoff-only. He may want to revisit after seeing it.

---

## 10. Known bugs, gotchas, failure modes

- **⚠ JSX comments cannot be the first child of `&&`** — I hit this AGAIN this session (club-ui).
  Parse error, ~7 cascading tsc errors starting far from the real line.
- **⚠ react-doctor's pre-commit hook cannot block** — `grep -n exit .githooks/pre-commit` returns
  NOTHING. It reports and exits 0 always. Its config error is **conditional, trigger UNKNOWN**.
  Run it manually: from `app/`, `./node_modules/.bin/react-doctor <dir>` (takes a DIRECTORY).
- **⚠ `effect-needs-cleanup` is low-precision here** — 2 confirmed false positives (`radar.tsx:141`,
  `ring.tsx:36`, both read and cleared) and 1 confirmed **real** bug (`tabswipe.tsx`). The real one
  was the flag both sessions were most confident was noise. **Read every flag.**
- **This worktree has NO `node_modules`** — it is a symlink I create for gates and delete before
  each commit: `ln -sfn /Users/sean/dev/daengrun/app/node_modules node_modules`. Metro needs it too.
- **The simulator can go to Shutdown** and screenshots then fail with "No Image available to
  encode" / "Timeout waiting for screen surfaces". `xcrun simctl boot <UDID>`, wait ~30s, relaunch.
- **A downscaled screenshot lies about contrast** — crop one specimen at full resolution.
- **The 6 lint errors are baseline** (all `exhaustive-deps`, none in files I touched).

---

## 11. Known-good — do not "fix" these

- The **`relWhen` clamp** and the **`liveOwnsCoral` widening** — both are the fix, not incidental.
- **Measured contrast values** in `draw-button.tsx`, including the coral row's new `// 4.84 / 4.55`.
  `paper.wash` was chosen over a new literal deliberately (existing token, zero new colours).
- **Chat as ink outline, not coral** — Sean's instruction plus the one-coral law.
- The **conditional `subscribeShared` retire** (see §7).
- **`runner/meetup.tsx`'s existing dog card, memo, map and 길찾기** — all already correct. My
  proposed replacement was withdrawn as duplicate.
- The **three-state fetch idiom** applied across ~15 screens; **the drop-law layout**; **route names
  render raw**; **`status='active'` filtering is a gate**; **`actual_km` = whole tracked buffer**.

---

## 12. Ideas & discussions not yet built

- **④ thumb dock** — drawn in the lab, Sean chose ① instead. If scroll depth ever becomes a real
  problem, promoting ① → ④ is a small move. Needs a show/hide rule for when no job is in flight.
- **맹견 flag** — absent from the schema entirely. Legal flagged it as real before real owners.
  Server work.
- **Owner phone / PASS** — `profiles.phone` is NULL for everyone. Any call button would be a dead
  button. Do not add one.
- **Route selection showing lap + approach total** (ruling #15) — `route-pick.ts` implements it;
  worth re-verifying it reaches every surface.
- Carried forward and still unbuilt: 기록증 (the certificate) · ② 동네 기록소 · five signature motions ·
  App Store icon still wears the retired palette · 채팅 as a home row · post-first-run profile nudge.

---

## 13. Strategic read (my recommendation)

**The next real move is a hardware build, and everything else is second.** ~40 defects are fixed and
none of it changes the one fact that decides whether the pilot can start: nothing has ever run on a
phone. Sean deferred Build 0 deliberately this session, which is his call — but every screen shipped
before that binary increases what the first device session can invalidate. Four whole classes of
this session's work are **not simulator-testable**: push routing, Live Activity cold-launch, realtime
under network churn, and the Naver callback. They are code-verified and could all be wrong.

**The argument against me:** the app was genuinely full of lies a week before a pilot, several of
them safety-path (SOS resolving the wrong party, the ceremony running backwards during an incident,
nomination dead in production). Shipping a binary that does those things confidently would have been
worse than shipping it late. That argument is why I did the work in the order I did.

**So:** build the binary, then work the hardware smoke list, and treat the remaining tail as filler
between device sessions rather than as the main line.

---

## 14. Next 1–3 steps

1. **[read-only]** Verify the status table's first three rows yourself (§15). Then read
   `docs/plans/2026-08-20-client-gap-straightening.md` — the ENDING STATE section and Q7–Q10.
2. **[needs-user]** TestFlight, or Sean's ruling on any of §9's four decisions. The coral A/B and the
   handoff-CTA gating are both one word from him.
3. **[local-edit]** If continuing without him: the remaining tail is E6 (device-local time on
   booking writes — latent on KST hardware), B9 (hero live booking can fall off a 20-row list),
   B10 (`sealStampFresh` consumed on call, not on render). All low-severity; none user-visible today.

---

## 15. Verification commands

Safe (read-only):
```
git -C /Users/sean/dev/daengrun status -sb
cd app && ln -sfn /Users/sean/dev/daengrun/app/node_modules node_modules
cd app && ./node_modules/.bin/tsc --noEmit
cd app && node scripts/check-rpc-contracts.mjs && node scripts/check-route-native-imports.mjs && node scripts/check-embed-fk.mjs
cd app && npm run lint --quiet                    # must stay at 6 errors
cd app && ./node_modules/.bin/react-doctor app    # takes a DIRECTORY; advisory only
supabase migration list --linked
supabase functions list
xcrun simctl openurl F2FDB7D7-A669-4BBC-8EF4-677597F3851A "daengrun://runner/home"
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

Nothing seeded or deleted by me. **Production reads only.** Sean's account still holds the stale
**8월 4일 (화) 오후 3:30** booking (`runner_enroute`) — it is why the runner ticket renders 「지난 예약」
and it is the only reason several states could be verified at all. Measured this session: 0 open
requests, 0 past-dated, 0 phantom ledger rows, 0 active routes, `payments`/`billing_keys` = 0.
Metro is running on :8081 pointed at this worktree. The simulator is on `runner/home`.
The scratchpad (screenshots, downloaded function source) is **ephemeral**; labs are committed.

## Agent work

Six subagents ran: 4 read-only scouts (state machines · UI honesty · navigation · data contracts)
that produced the 59-item inventory, then implementer agents for the four overnight lanes, the
not-found/data-truth batch, and the back-button sweep. **I re-read every diff and re-ran every gate
myself** rather than trusting reports — two agents overruled my instructions with evidence and were
right both times (the run-trace freeze, the phoenix rejoin). Raw agent outputs are gone with the
scratchpad; everything load-bearing is in commit messages.

**Coverage gaps, named:** the club domain (~9 screens, ~4,000 lines) was triaged, not audited —
only its navigation and the components it shares. `owner/request.tsx` (1,530 lines) and
`owner/pay.tsx` were triaged; the request screen's hold countdown and payphase machine deserve their
own pass when charging flips. No test suite was written; `app/test/` was not extended.

---

## Opener for the next session

> Client domain (all of `app/`) on daengrun. Work in a worktree cut from `origin/redesign-v4` —
> the MAIN CHECKOUT is clean and in sync as of 2026-08-21, keep it that way.
>
> Read `docs/handoff-client.md` fully, then `docs/plans/2026-08-20-client-gap-straightening.md`
> (ENDING STATE + Q7–Q10). ~40 defects were fixed and pushed; trunk is `13749af`.
>
> Five gates before every commit, from `app/`: tsc · check-rpc-contracts ·
> check-route-native-imports · **check-embed-fk** · `npm run lint --quiet` (**must stay 6 errors**).
> This worktree has no `node_modules` — symlink it from the main checkout, and delete it before
> committing.
>
> Settled, do not re-litigate: runner home is **①** (coral belongs to the in-flight job, chat is ink
> outline beneath it) · the ticket carries relative time / face / payout / door-level address · the
> `relWhen` clamp and `liveOwnsCoral` widening are the fix, not incidental · the 인계 screen's
> existing dog card, memo and 길찾기 are correct and must not be "replaced".
>
> Four things wait on Sean: TestFlight (his 2FA), the coral CTA ground A/B, the handoff-CTA gating,
> and the react-doctor hook — **which nobody should repair until its trigger is known.**
>
> ⚠ Nothing has ever run on hardware. Push routing, Live Activity cold-launch, realtime, and the
> Naver callback are all code-verified only. Never create a booking on Sean's account; never press
> the onboarding CTA. Reply in English; in-app copy stays Korean.
