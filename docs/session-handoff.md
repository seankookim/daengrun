# SESSION HANDOFF — 2026-08-06 (END: 0059 take-rate · 순백/코랄 pivot · honesty waves 1+2 · 정기 구독 decision)

English body (Sean: "use english") · in-app copy Korean · commit messages English.
**Opener for next session: "read docs/session-handoff.md fully, then continue."**
CLAUDE.md at repo root is the permanent law book. The prior detailed §2b–§2j reference
(rewards/passport/security history) lives in `docs/session-handoff-archive-20260805.md`.

**Orchestration standing order (Sean, 2026-08-06): Fable 5 = boss/orchestrator, Opus 5 =
builder + reviewer agents.** Every build wave runs: plan or eng review first → Opus builders on
DISJOINT file surfaces → Opus adversarial reviewer (attacks EXECUTED, not read) → gates → commit.

**Environment quirk: BUILD IN THE MAIN CHECKOUT `/Users/sean/dev/daengrun` (branch redesign-v4).**
Claude worktrees under `.claude/worktrees/` are STALE snapshots (migrations stop ~0036) — never
build or gate there. The gstack skill suite is installed (`/qa /investigate /ship /office-hours`
etc.); `/browse` for all web browsing, never mcp__claude-in-chrome__*.

---

## ⓪+ WAVE 2.5 SHIPPED — 2026-08-07 (client honesty, claim-scoped; /autoplan full pipeline)

**What shipped (this commit):** ensureDog() DELETED (dog-less pay no longer writes mock 초코 +
fabricated medical memo into the DB; pay gates via `반려견부터 ›` label swap) · request.tsx dog
block honest 4-state (fetchMyDogs now THROWS on error — was silently "no dog") · both meetup
screens: arrival-promise lies → departure-only truth, labels matched to the frozen stage
machine (enroute=출발 대기), 준비 중 overlays on the decorative map plates · bodycam GPS-only
truth ×3 + ONE approved 준비 중 line (schedule; Sean D3=B) · transition-booking owner notify
no longer promises uncontracted insurance · safety.tsx insurance/신원 claims softened; schedule
신원인증 badge retired · ui.tsx: Btn opacity-disabled → explicit fills, Avatar/Monogram sharp
corners (radius 0 app-wide) + hooks-safe error fallback · e2e pins no-보험 + notification
existence · dead mock feed/imports/fossil swept. Livecam addon KEPT as-is (Sean D4=C).
Review trail: docs/plans/honesty-wave-2p5-deferred-plan.md (38-decision audit, 3 voices,
adversarial FIX-THEN-SHIP all cleared). Gates green: tsc · check-rpc · e2e syntax.

### 🔴 SEAN — new queue items (post-wave-2.5)
1. `supabase functions deploy transition-booking` — picks up the honest 인계 notify copy.
2. Device smoke: ~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-eng-review-test-plan-
   20260807-004920.md — highlights: dog-less pay → /owner/dog with NO dogs row created ·
   airplane-mode request → 다시 시도 strip (NOT 등록 CTA) · avatar sharp corners one screen per
   world · meetup 준비 중 map overlays · recycled-list avatar after one dead URL.
3. `git push` when satisfied.
NOTE: `git add -A` is FORBIDDEN in this tree — untracked `supabase/.temp/start-secrets/`
holds real secrets and is NOT gitignored (rider: add to .gitignore + un-track .temp).

**Next session (D2=A, Sean-confirmed): WAVE 3 — now UNBLOCKED** (0055-0059 + both functions
verified deployed 2026-08-06 22:42). Scope: 0060 booking_pickup_address definer RPC +
payment_hold expiry (spec: honesty-batch-sunbaek-spec.md WAVE 3) + arrival push + owner stage
freshness + create-booking-hold ownership check + real meetup map. Full adversarial cycle +
harness (235+N pins). Riders ledger: see plan doc "Build + adversarial review record".

---

## ⓪ STATUS — 2026-08-06 END OF DAY

**Everything below is COMMITTED LOCAL on `redesign-v4`, gate-clean (app tsc + check-rpc; SQL
harness 235/0 at 0059). Branch is 10 commits ahead of origin. NOTHING pushed/deployed — all
Sean-only.** Today's arc (commit order): 0059 take-rate 33% (34169f8) → 순백/코랄 role screen
(76bf335) → owner-home full-bleed + soft-white + bigger GO disc (ffbf3c8, 28c1189) → 정기 구독
decision + km-coin parked (43947a0) → money CTA label → **다음 하이 미리 예약** (05aab35) →
honesty batch wave 1 (d06969e) → honesty batch wave 2 (c39c997).

### 🔴 SEAN'S QUEUE — deploy is the top priority (remotely-exploitable P0s still live on prod)
Run from `~/dev/daengrun`. Order: db push → functions deploy → prod check → git push.
1. **`supabase db push`** — carries **0055·0056·0057·0058·0059** together (0058 depends on 0057;
   0059 needs 0057's K-1 commission_rate server-only). The 0057/0058 security fixes close
   remotely-exploitable P0s (custody transfer callable by the anon key in the bundle) — the
   audit attacks were EXECUTED; both proven closed by re-executed attacks, harness 235/0.
2. **`supabase functions deploy transition-booking && supabase functions deploy settle-run`** —
   settle-run is NEW to the queue (0059 changed its fallback 0.2→0.33). transition-booking
   carries the 0057 tier gate ↔ K-3 applicant mint coupling.
3. **Prod check (SQL editor, must be 0 rows):**
   `select oid::regprocedure from pg_proc where prosecdef and has_function_privilege('anon',oid,'execute');`
4. **`git push`** (redesign-v4, 10 ahead).
5. **Business/manual:** send 3 affiliate applications (네이버 쇼핑커넥트 · Coupang Partners ·
   무신사 큐레이터) · ask 5 owners the two anchor-free price questions (라이브 캠 per-run + 정기
   구독 monthly, asked BEFORE naming a number) · growth-model.xlsx Assumptions!B13 → 0.33
   (breakeven/plateau re-derive — one-pager + financial-slides cite it).
6. Optional pre-push verify (Sean CAN run): `export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
   LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 && cd supabase/tests && rm -rf .pgtest && bash harness.sh`
   → 235/0.

### Device smoke (Sean — nothing shipped is device-verified beyond simulator screenshots)
- Role select (보호자 top / 러너 bottom, full-bleed 순백/코랄) · owner home (soft-white, 3-box
  stat row gone, full-bleed, GO disc enlarged 144, club widget = only side-margined widget) ·
  money CTA reads "다음 하이 미리 예약".
- Honesty wave 1: /owner/live never fakes a run (empty draft → honest resolve/empty, not mock
  pay) · review save failure = loud + retry · owner-home fitness tri-state in airplane mode
  (loading '—' ≠ error strip ≠ real 0) · no 적합도% anywhere · insurance copy = 협의 중 · course
  "준비 중" slots · pickup no longer hardcoded 서울숲.
- Honesty wave 2: pay 9-phase machine via `/dev/pay-lab` (all phases incl. authorizing/disputed) ·
  booking → hold → /owner/pay → 예약 확정 → nomination/recurring carried · meetup dark seal band
  in white chrome, stamp animates on live confirm NOT re-entry (once-law), 320dp band no clip.

---

## Decisions LOCKED today (durable — in gstack decision log + the docs below)

1. **Take-rate 33% flat** (0059, shipped). commission_rate server-only (0057 K-1). Rewards ③ and
   brand-deals ⑤ unblocked. Docs swept (recruitment/investor/instagram) to 33% economics.
2. **Design language: 순백/코랄, FROZEN until 50 paying dogs.** Canvas #FFFFFF (home body =
   soft-white #FBFAF7) · ink #111 · **solid coral #E8552F 1px hairlines, full-bleed (no side
   margins)** · sharp corners · Oswald numerals = the one type jump · ink-fill CTA (PaperBtn
   matrix). Tokens in theme.ts `paper` block (+ critical/criticalWash/disabledFill/inkPressed/
   pending). "dark is the artifact, light is the screen" — passport/club/seal ceremony stays
   dark inside the light app. Volt world dying on touched screens only (role screen retired it).
   Design-review laws (two surface classes, seam rule, ink ramp floors, loud-failure token):
   docs/plans/next-phase-style-shop-rewards-plan.md. Shop shotgun pick: 순백×코랄 (docs/labs/
   shop-shotgun-lab.html); shop BUILD gated on first affiliate link.
3. **Membership = 정기 구독 (monthly fee via 정기결제, first month free) + 정기 러닝 standing slot,
   billed PER-RUN — NOT prepaid.** km-coins PARKED (ledger-contracts §3 dormant; 선불 counsel Q
   off critical path). Member discount PLATFORM-ABSORBED (runner pay never shrinks). Milestone
   redefined: "예약의 40%가 정기 일정에서". Numbers (₩9,900 / 10% / ×1.5) = WORKING HYPOTHESES →
   dedicated pricing gate after owner interviews, before build. Design doc:
   ~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-design-20260806-170000.md. PG selection
   now requires 정기결제/빌링키.
4. **라이브 캠** = runner-funded opt-in premium (phone+chest-mount, owner-only stream, delivery-
   gated billing ≥70% actual duration, 50/50 split as a NEW settlement class outside min_fare
   clamp, ratio snapshotted at booking). Contract in ledger-contracts §2. Design doc:
   sean-redesign-v4-design-20260806-150000.md.

## Contract docs drafted (NOT built — gated on PG + Sean approval)
`docs/specs/ledger-contracts-draft.md`: §1 rewards ③ fee-side (1P=₩1, owner-side, platform-funded),
§2 라이브 캠 50/50, §3 km-coin PARKED. Three SEPARATE future adversarial cycles (0059 isolation
doctrine). Subscription money surface claimed the freed §3 cycle slot.

---

## Next work order (client-first, all client-only until Sean deploys the server)
1. **Honesty batch wave 3** — real pickup address via a `booking_pickup_address` definer RPC
   (addresses RLS is owner-only; runner client join returns NULL) + `payment_hold` expiry
   extension (spec Item 9). Needs a server slice → adversarial cycle → waits on the 0055-0059
   deploy. Spec: docs/plans/honesty-batch-sunbaek-spec.md WAVE 3.
2. **Deferred from waves 1+2** (client-only, any time): runner meetup ':318' 도착 알림 copy is a
   NEW P1 lie (says 알림 전송돼요, sends nothing — no server write) · bodycam copy ×3
   (owner/schedule:350, owner/report:333, runner/meetup:396 — no pipeline) · shared `Btn` opacity
   trick in src/components/ui.tsx (O1 — the last opacity-disabled; PaperBtn is the replacement) ·
   Monogram/Avatar rounded corners vs sharp law · my.tsx / request.tsx residual mock `dog` (초코)
   fallbacks in non-fitness regions.
3. **Then (all gated on Sean):** 정기 구독 build (after pricing gate + PG) · rewards ③ build
   (after PG + first real settlements) · shop build (after first affiliate link) · 라이브 캠
   (after stream infra decision — TURN/SFU, per the design doc's open Q).

## Standing doctrines (Sean's invariants — CLAUDE.md is authoritative; compact reminders here)
- Sean-only: db push, functions deploy, git push. Never claim device-visual success — Sean smokes.
- Honesty: no mock/fake numbers; bind real fields or omit; failures shown as failures; loading≠0;
  no dead buttons; gate display on rawStatus not display vocab.
- Commit gate (every commit): `cd app && ./node_modules/.bin/tsc --noEmit` + `node
  scripts/check-rpc-contracts.mjs`. check-rpc only covers `supabase.rpc()` — `.from().select()`
  needs an e2e.mjs assertion (see the fetchBookingCharge step, added wave 2).
- Migrations/security → Opus adversarial cycle + PG16 container harness (235/0; macOS invocation
  needs the PATH+LC_ALL export above). New definer fns: `set search_path=public,pg_temp` IN BODY
  (98 H1 watches). Money-arithmetic changes get their OWN migration + own cycle (0059 isolation).
- Font floor 14pt (decorative letterspaced-caps kicker class exempt); Oswald numerals need
  explicit lineHeight ≥1.2×.
- DO-NOT-REFACTOR: owner-home collapsing-hero morph (pinned overlay + transform/opacity native-
  driver only) · meetup stage machine / polling / confirmHandoff / useStamp once-law hydration
  ordering — style/copy only, hook order byte-identical.
- Respond to Sean in English; code comments + commits Korean; commands as explicit lists.

## ⓪+++ RUNNER FUNNEL SHIPPED — 2026-08-08 (cf6d93a, migration 0062)

**A runner can finally become bookable.** Before this the owner-facing runner list was
structurally empty — no submit button, no applicant→certified path, and two independent gates
filtering applicants out. Critical-path blocker #1 of 2 is closed in code.

`runner_applications` (RLS on, zero policies, all access via definer RPCs) · 3 applicant RPCs +
3 ops RPCs · `scripts/runner-ops.mjs` service-role queue · `/runner/apply` as a real 10-state
funnel · honest `safety.tsx` identity copy · applicant-aware `/runner/home`.
Harness **266/0**, 7 mutation proofs executed. Plan: `docs/plans/runner-funnel-plan.md`.

**Two defects the build itself surfaced:**
1. The plan's `ops_only` belt-and-braces check was **dead code** — inside SECURITY DEFINER,
   `current_user` is always the function owner. The pin that actually granted EXECUTE (rather
   than reasoning about it) caught a client role approving an application. Schema swept: no
   other definer relied on the broken idiom.
2. **My own 0061 bug**: it coerced `commission_rate` to 0.20 from the 0001 table definition,
   but 0059 moved the default to 0.33 — 13 points of take rate on every normally-created runner,
   on a column settle-run reads for real money. **Caught before 0061 shipped** (0060 is deployed,
   0061 is not). Pin S7 now compares the trigger's written value against the catalog default with
   no literal on either side.

### 🔴 SEAN — funnel queue (after the 0061 push below)
1. `supabase db push` carries **0061 + 0062** together.
2. Approve your first runners: `node scripts/runner-ops.mjs list` → `review <id> <you>` →
   `approve <id> <you> "<what you verified on the call>"`. The note is required on purpose —
   it is the record that the video call happened, and `safety.tsx` now promises owners it did.
3. **Decide on the seed runners before any real owner opens the app** (see 0061 block below).
4. Device smoke: apply → submit → withdraw → re-apply · applicant home shows the funnel route,
   not "requests will arrive" · approved runner sees the online/offline line matching their
   real switch.

## 🚨 0061 — P0 LIVE VULNERABILITY SEALED (2f113d8) — DEPLOY THIS FIRST

**Any authenticated user can currently make themselves a master-tier runner with zero
commission and forged identity verification, on production, right now.** One free signup, no
prior state. Found by the runner-funnel scout, reproduced by execution:

```
insert into runners (profile_id, tier, commission_rate, identity_verified)
values (auth.uid(), 'master', 0, true);   -- SUCCEEDED
```

Cause: the RLS insert policy (0002:71) checks only ownership, and `_guard_runner_cols` (0057)
is `before update` only — the same migration got it right for `runner_documents`.
Impact: (1) an unvetted stranger can accept bookings and take custody of a dog, (2) zero
commission = payout theft, (3) `identity_verified=true` forges the claim the safety copy rests
on. Fix coerces privileged columns to defaults on client INSERT; the legitimate `ensureRunner`
payload is unchanged, so no shipped build breaks. Harness 252/0, two mutation proofs executed.

**Sean: `supabase db push` for 0061 ahead of everything else.** Then check prod for anyone who
already used it:
```sql
select profile_id, tier, commission_rate, identity_verified, created_at from runners
where tier <> 'applicant' or commission_rate <> 0.20 or identity_verified;
```
Expect only the six `@daengrun.seed` accounts from `scripts/seed-runners.mjs` (which mints
fabricated certified/veteran/master runners via the service role). **If those seeds are in
production they are fake certified runners visible to owners — decide whether to wipe them
before real users see the list.** Anything else in that result set is an exploited account.

## ⓪++ WAVE 3 SHIPPED — 2026-08-08 (ac936f5, server slice)

0060 + 2 edge functions + client rebind. Harness **246/0** (11 new pins, 5 mutation-proofed),
tsc · check-rpc 70/99 · e2e syntax all green. Adversarial pass executed its own attacks
(FIX-THEN-SHIP → all blockers fixed before commit).

**The P1 the reviewer caught and executed:** the 24h address window was decorative — `enroute`
had no time gate and the runner meetup screen calls it on mount, so one tap on a job weeks out
flipped the booking to `runner_enroute` and returned the owner's home address. Fixed at the
edge function (the boundary), pinned in e2e both directions.

### 🔴 SEAN — wave-3 queue
0. **Measure first** (SQL editor, before push): `select count(*), min(created_at) from bookings
   where status='payment_hold' and created_at < now() - interval '30 minutes';` — the first cron
   run silently expires all of them. Fine at N=12, a conversation at N=1200.
1. `supabase db push` (0060) · `supabase functions deploy transition-booking create-booking-hold`
2. Prod check (must be 0 rows): `select oid::regprocedure from pg_proc where prosecdef and
   has_function_privilege('anon',oid,'execute');`
3. `git push` (2 commits: 8151139 wave 2.5, ac936f5 wave 3)
4. Device smoke: runner pickup card shows the REAL address in-window · far-out confirmed job
   shows no address and NO red error strip · 도착 확인 → owner gets exactly one push, survives
   app restart · owner meetup shows 러너 도착 · parked pay screen after 30min → honest 409.
   e2e steps pass only AFTER the deploy (they assert the new actions).

**Riders (named, not done):** enroute double-fire on remount · push `bid` dropped on historical
inbox rows routed to /owner/meetup · runner/meetup stage-restore has no inverse (replaced runner
keeps the handoff CTA) · 9 tracked `supabase/.temp` version files (not secrets; new ones now
gitignored) · harness.sh never stops its cluster (orphan postgres after repeat runs).

## Launch checklist (NEW 2026-08-08)
`docs/launch-checklist.md` — everything required before the Banpo pilot, grouped (legal / money /
supply / validation / product / distribution) with what's verified vs. documented. **Critical path
finding: the two things actually blocking a paying customer are (1) no runner can become certified
— /runner/apply has no submit and no applicant→certified path exists server-side, while
transition-booking:103 + api.ts:543 both gate on certified, so the owner-facing runner list is
structurally empty; and (2) GPS dies on screen lock (geo.ts:23 is foreground-only).** Neither is
legal or store-related. Also: the pilot does NOT need the App Store (TestFlight external = 10k
testers), and todo.md's TestFlight command was wrong (preview = ad-hoc; use production + submit).

## Key artifacts
- Plans: docs/plans/next-phase-style-shop-rewards-plan.md (style pivot + reviews) ·
  honesty-batch-sunbaek-spec.md (waves 1-3 + wave-2 GSTACK REVIEW REPORT) ·
  0059-take-rate-33-plan.md.
- Specs: docs/specs/ledger-contracts-draft.md.
- Design docs (~/.gstack/projects/seankookim-daengrun/): -150000 (라이브 캠 + km-coin superseded),
  -170000 (정기 구독). Boards: docs/labs/shop-shotgun-lab.html.
- Research: docs/biz/ (affiliate + bodycam findings recorded in the -150000/-170000 docs).
