# Session Handoff — 2026-07-30 (v4: P-C delegation backend complete, UI lab next)

> **Companion docs to read first**: `docs/hi-club-plan.md` (하이클럽 v2.1 final spec), `docs/todo.md` (master work list),
> `docs/design/final-system-lab.html` (V4 design system — the agreed 6 rules), `docs/design/delegation-lab.html` (P-C UI mockups, if present),
> `docs/design/app-upheaval-lab.html` (V1/V2/V3 originals). This file supersedes the v3 handoff.
> **Language convention**: handoff & docs in English (Sean's preference); code comments & commit messages in Korean.

---

## 1. Goal & current state

DOGS HIGH (도그스하이, repo `daengrun`) — a dog-fitness marketplace where certified runners run customers' dogs.
React Native/Expo + Supabase. Sean is solo-testing with a single account (he's the club host).

**Workstream status**:
- **P-C delegation BACKEND** [verified-now]: **complete** — slice 1 (0037, commit 5794130) + slice 2 (0038, commit c5a07ab).
  Harness 107/107 (was 83). Remaining P-C work is **UI only** (§10).
- **V4 full redesign** [verified-now]: branch `redesign-v4` (90b909d→c5a07ab). Sean: "I like this look much more than the original."
  On-device review still pending; merge to main after review.
- **Deploys** [stated 2026-07-30]: Sean ran `npx supabase db push` (0032–0038) and `git push` — remote DB and origin are current.
- **HIGH CLUB P-A + P-B** [verified-now]: complete (0030–0036).
- **Real-device club full-loop test** [uncertain]: RSVP→check-in→recap from a second account never verified; delegation loop
  (delegate→approve→assign→handoff→run→settle) also never device-verified — needs two accounts.

## 2. Standing doctrines (Sean's invariant rules — outlive any task)

- **Honesty principle**: never fabricate data or fake activity. Render only when real data exists. No ghost clubs. No first-finish
  fanfare. Never promise benefits that don't exist. **No money before approval** (P-C extension of this rule).
- **Harness gate**: no migration ships without passing `supabase/tests/harness.sh` (currently 107 pass). Test expectations must be
  data-driven, never hardcoded counts.
- **Commits**: detailed Korean commit messages; `tsc --noEmit` clean before every commit; git-lock mv ritual after every commit (§8).
  Sean does all pushes/deploys.
- **Language**: conversation and docs in English; code comments and commits in Korean.
- **Commands**: always give Sean the exact commands he needs to run.
- **Naver Cloud secret**: the client secret (3yobs…) must NEVER enter the app or repo — root `.env`, server-side only.
- **New design surfaces**: big UI decisions get an HTML lab first → Sean picks by number → then implement.

## 3. Working-relationship norms (brief a new teammate)

- Sean sometimes gives feedback by voice transcription (rambly-looking but every clause carries intent — decompose carefully).
- Aesthetic decisions must be visual: "let's see it html first." Prefers 3–5 options + one recommendation; picks by number.
- Rhythm: implement → he checks on device → precise micro-adjustments ("1.2x", "more left and up"). Apply immediately.
- Hates: pastels, beige, rounded-card soup, system/default fonts, "AI-looking" uniformity, blandness, bib numbers (retired).
- Loves: sharp corners, dark contrast (V2), stamp & ticket motifs, club violet, worn-out textures, highlighter marks,
  3D hard shadows (sparingly), Oswald numerals.
- Autonomy: frequently delegates order ("go ahead"), but direction changes are his call.

## 4. Decision log (with WHY)

**P-C (2026-07-30, this session)**:
- **Booking created at APPROVAL, not registration** — registration is a demand queue; money is only promised once the host
  says yes (honesty principle). Booking = status `matching`, `runner_id` null until day-of assignment.
- **`bookings.club_session_id`** — isolates club bookings from the general open pool (api.ts inbox/open-request queries filter
  `.is('club_session_id', null)`; 0017 expiry cron skips them — session lifecycle owns club-booking fate).
- **Tier caps min(2,tier)**: certified 1 · veteran/master 2 · applicant rejected. Session delegated capacity = sum of
  COMMITTED runner caps, re-derived on every commit/withdraw (never stale — dynamic capacity doctrine).
- **Withdraw stranding**: excess approved dogs revert to pending latest-registered-first (via `session_dogs.seq` — monotonic
  sequence because harness DO blocks freeze `now()`), bookings fully refunded, both sides notified. No silent stranding.
- **Min attendance = host notification only** (cron :40, once per session) — no destructive auto-cancel; "a human opens sessions,
  a human closes them". Also avoids ambushing Sean's solo testing.
- **Custody transition = trigger on bookings**, not a new mechanism — reuses the per-booking two-sided handoff confirmation
  (insurance anchor). `picked_up` → responsible=runner + dog checked in; `completed` → checked out + responsible back to owner.
  Server owns the invariant regardless of which path drives the transition (0034 trigger precedent).
- **Assignment day-of by host** (`session_assign_dog`), check-in window (-2h..+6h), runner must be committed AND checked in,
  per-runner cap re-verified at assignment. Reassignment only until handoff (`already_handed_off`).
- **Shared trace fan-out**: `club_start_delegated_runs` + `club_save_run_trace` fan out to all the runner's dogs; run EVENTS
  stay per-booking (a poop stamp is a fact about one dog).
- **Per-dog settlement unchanged** — existing settle-run per booking; early per-dog dropout falls out naturally. Completion logs
  `participant_activities` as `gps_verified` (runs trigger) — measurement-source doctrine schematized.
- **Confirmed-booking refunds are two-step** `cancelled_runner → refund_pending` — transition map untouched (safer than enum/map surgery).
- **Caught regression worth remembering**: first draft of 0037 extended `club_finish_session` from the 0030 body and silently
  erased the 0031 recap logic — harness S5 caught it. **Rule: before redefining a function, grep which migration holds the
  LATEST definition and extend that.**

**V4 design (2026-07-29, unchanged)**: 6 rules — ① body=V1 white×ink rules×bands ② punch=V3 (ONE 3D coral action/screen,
highlighter on one hero word) ③ night=V2 (live running, club, shot studio, pass — day/night switch is the brand rhythm)
④ softness exception: only living things and stamps are round ⑤ 3-tier type (Black Han Sans / Oswald / IBM Plex Sans KR /
Plex Mono labels) ⑥ color map: volt=individual, coral=urgency, amber=pending, blue=completed, violet=club, gold=records, terra=shop.
Other standing decisions (token revolution, runner discovery, radar=coral, club C1 violet, T3 seal in-flow, bibs retired,
`club_session_detail` host-first tie-break) — see v3 log if needed; all still true.

## 5. Architecture & contracts

- **Migrations 0030–0038** [verified-now, all pushed]: 0030 club core / 0031 search·recap·stats / 0032 demand board /
  0033 collar / 0034 record trigger / 0035 series (cron :20) / 0036 isMe / **0037 delegation S1** (commit/withdraw/delegate/
  approve/cancel-fanout/min-attendance cron :40/format plumbing/`club_session_id`) / **0038 custody S2** (assign/custody
  trigger/start+trace fan-out/activity trigger/gap fixes).
- **P-C RPC surface (for UI work)**: owner `session_delegate_dog(session, dog)` · host `session_approve_dog(session_dog, bool)`,
  `session_assign_dog(session_dog, runner)`, `club_cancel_session(session)` · runner `session_runner_commit/withdraw(session)`,
  `club_start_delegated_runs(session)`, `club_save_run_trace(session, trace)`. Handoff & settle reuse existing
  transition-booking `confirm_handoff` and settle-run edge functions per booking.
- **Harness**: `supabase/tests/harness.sh` — local PG16, all migrations from zero + suites 10/20/30/40/50/60 = 107 cases.
  Container runs as root → `runuser -u postgres -- bash harness.sh`. Container mirror at `/tmp/daengrun/supabase` (verify md5!).
- **Club writes = RPC-only**; participant names flow through SECURITY DEFINER. Errors are text codes (`no_capacity`,
  `reassign_dogs_first`, `session_in_flight`, `already_handed_off`, `dog_slot_clash`, `format_closed`, `route_required`…).
- **Pricing constants duplicated** in `functions/_shared/ctx.ts` PRICING and 0037 `session_approve_dog` (9900 + km×3000) —
  change together.
- **settle-run trust boundary**: km clamped 0..planned×2+2; completion requires ≥50% of planned km.
- **Font loading grammar** (DO-NOT-REFACTOR): `displayFont.ts` / `fonts.ts` — lazy load with silent system fallback.
- **V4 night tokens**: nightBg #0D0A1E · nightCard #14102B (club) / #121712 (runner) · nightEdge #2A2350 · nightDim #8F86C2 ·
  neon #9F8FFF. Day tokens in `app/src/theme.ts` (cream=#FFFFFF paper, volt #C6F542, tang #FF5C3D, club #7B6CDF, radius 6/6/4).
- **`noti_kind` enum**: booking/community/shop/safety/reward/system — P-C uses `booking` for money events (approval, assignment,
  refunds, run start) and `community` for club-social events (requests, rejections, min-attendance, cancellations).

## 6. File map (this session)

- `supabase/migrations/0037_club_delegation.sql` — S1: commit/withdraw/delegate/approve/cancel/min-attendance/format/`club_session_id`
- `supabase/migrations/0038_club_custody.sql` — S2: assign/custody trigger/run fan-out/activity trigger/gap fixes
- `supabase/tests/50_delegation_suite.sql` (D1–D14) · `supabase/tests/60_custody_suite.sql` (E1–E10) · `harness.sh` (+2 suites)
- `app/src/lib/api.ts` — two open-pool queries now filter `.is('club_session_id', null)` (⚠ edited on-device via python)
- V4 session files (2026-07-29) unchanged — see v3 §6 if needed; key ones: `app/src/theme.ts` (all tokens),
  `app/src/components/clubcard.tsx`, `app/app/club/[id].tsx`, `club/session/[sid].tsx`, `club/pass/[sid].tsx`.

## 7. Pending on Sean's side

- **[needs-user] V4 on-device review** → micro-adjustments → `git checkout main && git merge redesign-v4`.
- **[needs-user] Two-account verification**: club social loop (RSVP→check-in→recap) AND delegation loop
  (delegate→approve→assign→handoff→start→settle→refund paths).
- ~~db push 0032–0038~~ done 2026-07-30 [stated]. ~~git push~~ done [stated].
- KIPRIS trademark manual check (todo §E) [from-history].

## 8. Environment traps (must know)

- **Device git locks**: every commit leaves `.git/index.lock` / `HEAD.lock` / `tmp_obj_*` that cannot be unlinked → mv into
  `_to_delete/git-locks/` after EVERY commit; also check BEFORE committing (`git status` itself can create index.lock).
- **Staging cache corruption** ⚠⚠: `device_stage_files` intermittently returns stale versions — **always md5-compare against
  the device before editing anything staged**. On mismatch, edit on-device via python heredoc.
- **Container mirror** `/tmp/daengrun` — re-verify md5 at session start (this session: full re-stage, all 44 files matched).
- **Harness in container**: `runuser -u postgres -- bash harness.sh`; wedged postmaster → `rm -rf .pgtest`.
- **tsc on the device**: `cd app && npx tsc --noEmit` (never chained).
- **Function redefinition trap**: grep for the LATEST definition across migrations before `create or replace` (S5 lesson, §4).
- **RN constraints**: `Row` style prop takes no arrays · avoid `StyleSheet.absoluteFillObject` · no gradient lib · rn-svg
  strokeDashoffset needs JS driver.
- **Harness DO blocks = single transaction**: `now()` frozen → use sequences (`session_dogs.seq`) for order, not timestamps.

## 9. Ideas discussed but not built

- **P-C UI** — the active work item, see §10.
- **V4 remainder**: home masthead + ink-rule hero, highlighter hero word, 3D coral CTA rollout, body-font rollout,
  V4 passes on request/report/live/shot-studio screens. Lab first when Sean asks.
- **runner-profile → athlete page** (step 2 of runner-PR flow).
- **P-B polish leftovers**: club patch visualization, story/Kakao share formats.
- **P3 gold UI surfaces**: report PB hero, feed milestone cards (detection live in 0034; no surfaces).
- **Demand threshold (10 teams)**: product constant with no behavior yet.
- **Compatibility (궁합) flow**: host sees dog info at approval; a real matching-hint system is future UI work.
- **Owner no-show policy**: currently full refund via finish-cleanup — a stricter policy is undecided [design].

## 10. Next 1–3 steps

1. **[in progress] P-C UI lab** — `docs/design/delegation-lab.html`: 3 versions × 3 screens (owner delegate flow in session
   detail · host console: approve/capacity/assign · runner multi-dog handling run). V4 rules apply; club = violet night world;
   Sean picks by number, then implement in app.
2. **[local-edit] Implement picked version**: api.ts wrappers for the P-C RPC surface (§5) + screens. Run-screen integration
   (start/trace fan-out + settle-run×N) is the trickiest part — the existing run screen is single-booking.
3. **[needs-user] After V4 review passes: merge to main**, then two-account full-loop verification (§7).

## 11. Verification commands

Read-only (safe):
```bash
# Device (device_bash, cd /sessions/<sess>/mnt/daengrun)
git branch --show-current && git log --oneline -8
cd app && npx tsc --noEmit
md5sum app/src/lib/api.ts app/src/theme.ts   # staging-freshness check before any edit
# Container (Bash)
cd /tmp/daengrun/supabase/tests && chown -R postgres:postgres .. && runuser -u postgres -- bash harness.sh 2>&1 | tail -3
```
Destructive / costly (Sean's approval first):
```bash
git checkout main && git merge redesign-v4   # only after device review
rm -rf .pgtest                                # harness reset (container)
```
