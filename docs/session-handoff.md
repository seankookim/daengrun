# Session Handoff — 2026-07-29 (v3: major UI upheaval + HIGH CLUB P-B completion session)

> **Companion docs to read first**: `docs/hi-club-plan.md` (하이클럽 v2.1 final spec), `docs/todo.md` (master work list),
> `docs/design/final-system-lab.html` (V4 design system — the agreed 6 rules), `docs/design/app-upheaval-lab.html` (V1/V2/V3 originals),
> `docs/design/club-customer-flow.html` (customer club journey replica). This file supersedes the previous handoff.
> **Language convention**: handoff & docs in English (Sean's preference); code comments & commit messages in Korean.

---

## 1. Goal & current state

DOGS HIGH (도그스하이, repo `daengrun`) — a dog-fitness marketplace where certified runners run customers' dogs.
React Native/Expo + Supabase. Sean is solo-testing with a single account (he's the club host).

**Workstream status**:
- **V4 full redesign** [verified-now]: 5 commits on branch `redesign-v4` (90b909d→a57860d). Sean: "I like this look much more than the original." Awaiting his on-device review before merging to main. **In progress.**
- **HIGH CLUB P-A + P-B** [verified-now]: complete. Migrations 0030–0036, harness 83/83. Demand board, recurring series, recap feed, and the show-the-host pass screen all implemented.
- **Color revitalization P1–P5** [verified-now]: all shipped (dog collar colors, postmark inks, record gold, badge worlds, shop terracotta).
- **P-C (delegation)** [from-history]: not started. Schema pre-exists in 0030 (`session_runner_assignments`).
- **Real-device club full-loop test** [uncertain]: RSVP→check-in→recap from a second (customer) account never verified. Currently substituted by the HTML replica.

## 2. Standing doctrines (Sean's invariant rules — outlive any task)

- **Honesty principle**: never fabricate data or fake activity. Render only when real data exists. No ghost clubs (a collecting club shows as "waiting", never as fake activity). No first-finish fanfare (a record needs something to beat). Never promise benefits that don't exist.
- **Harness gate**: no migration ships without passing `supabase/tests/harness.sh` (currently 83 pass). Test expectations must be data-driven, never hardcoded counts (lesson from case S10).
- **Commits**: detailed Korean commit messages; `tsc --noEmit` clean before every commit; git-lock mv ritual after every commit (§8). Sean does all pushes/deploys.
- **Language**: conversation and docs in English; code comments and commits in Korean.
- **Commands**: always give Sean the exact commands he needs to run.
- **Naver Cloud secret**: the client secret (3yobs…) must NEVER enter the app or repo — root `.env`, server-side only. The client id (3vpkxtglpe) is fine in app.json.
- **New design surfaces**: big UI decisions get an HTML lab first → Sean picks → then implement.

## 3. Working-relationship norms (brief a new teammate)

- Sean sometimes gives feedback by voice transcription (rambly-looking but every clause carries intent — decompose carefully). Occasionally sends GPT-structured briefs.
- Aesthetic decisions must be visual: "let's see it html first." Prefers 3–5 options + one recommendation; picks by number.
- Rhythm: implement → he checks on device → precise micro-adjustments ("make the button much bigger", "1.2x", "more left and up"). Apply micro-adjustments immediately.
- Hates: pastels, beige, rounded-card soup, system/default fonts, "AI-looking" uniformity, bib numbers (retired), small generic modules.
- Loves: sharp corners, dark contrast (V2), stamp & ticket motifs, club violet, worn-out textures, highlighter marks, 3D hard shadows (used sparingly), Oswald numerals.
- Autonomy: frequently delegates order ("go ahead in whichever order you like"), but direction changes are his call.

## 4. Decision log (with WHY)

- **V4 design — 6 rules** [verified-now]: ① body = V1 (white × ink rules × full-width bands) ② punch = V3 (3D hard shadow on exactly ONE primary action per screen; coral = dopamine/urgency; highlighter mark on one hero word per screen) ③ night = V2 (live running, club, shot studio, pass screen — the day/night switch is itself the brand rhythm) ④ softness exception = only living things and stamps stay round ⑤ 3-tier type (Black Han Sans display / Oswald numerals / IBM Plex Sans KR body / Plex Mono labels) ⑥ color map preserved. — Result of Sean's synthesis: V1/V3 "too crisp alone", V2 "definitely somewhere".
- **Branch strategy**: `redesign-v4` branch because Sean asked for an easy way back. `git checkout main` = instant rollback.
- **Token revolution method**: changed the *value* of `cream` to #FFFFFF (name kept for compatibility) to de-beige the whole app at once, instead of per-screen rework; paired with a literal sweep for hardcoded beiges.
- **Color map**: volt=individual/brand, coral=urgency/dopamine, amber=pending, blue=completed, violet=club (C1 chosen — teal too close to volt, berry competes with coral), gold=records (scarcity is the point), terra=shop, 8 collar colors=per-dog personal.
- **Runner discovery**: dedicated tab rejected (fragments nav for a booking-adjacent behavior) → featured-runner card + roster rail on home → runner-profile to be upgraded into an "athlete page" next.
- **Radar = coral**: switched from volt grid — "coral as the complementary energy to purple" (Sean's direction).
- **HIGH CLUB core invariant**: mixed events + every dog has exactly one explicit responsible person (NOT session segregation — accepted from ChatGPT critique). P-C "extends the schema, not a redesign". Ghost clubs forbidden. RSVP = membership. Recap only when ≥1 team checked in.
- **Record detection = trigger on `runs`** (0034): instead of rewriting settle_run_tx — commits inside the settlement transaction without duplicating the function.
- **`club_session_detail` ordering** (0036): created_at ties break host-first — discovered because harness DO blocks are one transaction (frozen `now()`), making the sort unstable.
- **Completed-card stamp = T3 circular seal, 84px, in-flow** — absolute positioning caused overlap accidents; in-flow makes overlap structurally impossible. The 3K neon patch circle was retired from completed cards (Sean: "don't add that").
- **Bib numbers retired**: roster shows avatar+name; pass screen's BIB box became a TEAMS n/cap counter ("they look awful").

## 5. Architecture & contracts

- **Migrations 0030–0036** [verified-now]: 0030 club core / 0031 search·recap·stats / 0032 `club_demand_board()` / 0033 `dogs.collar` / 0034 record trigger (`_detect_dog_records`, kind='reward') / 0035 recurring club series (cron `club-series-gen` hourly :20; 72h window, 2h min notice, ±1h dedup) / 0036 session_detail `isMe`.
- **Harness**: `supabase/tests/harness.sh` — local PG16, applies ALL migrations from zero + suites 10/20/30/40 = 83 cases. Container runs as root → use `runuser -u postgres -- bash harness.sh`. Container mirror lives at `/tmp/daengrun/supabase`.
- **Club writes = RPC-only** (no direct table write policies). Participant names flow through SECURITY DEFINER.
- **settle-run trust boundary**: km clamped 0..planned×2+2; completion requires ≥50% of planned km.
- **Font loading grammar** (DO-NOT-REFACTOR): `displayFont.ts` / `fonts.ts` — lazy load with silent system fallback (old builds must not crash). Hooks return null on fallback; null in a style array is ignored.
- **HeatTrace `tint` prop**: solid color overrides the heat gradient (used by collar colors & course worlds).
- **`worldOf(km)`** (patch.tsx): single source for distance→color-world — shared by patches and course cards.
- **V4 night tokens**: nightBg #0D0A1E · nightCard #14102B (club) / #121712 (runner) · nightEdge #2A2350 · nightDim #8F86C2 · neon #9F8FFF.
- **`noti_kind` enum**: booking/community/shop/safety/reward/system — no 'record'; records reuse `reward` (avoided enum surgery).
- **Alert postmark inks**: `inkFor(kind, title)` in alerts.tsx — title heuristics (경신/달성/돌파 = gold, etc.).

## 6. File map (touched this session, one-line role each)

App:
- `app/src/theme.ts` — all V4 tokens (paper, night, club, gold, terra, 8 collar colors, radius 6/6/4, font constants)
- `app/src/lib/fonts.ts` — useNumFont/useBodyFont (lazy Oswald & Plex Sans KR)
- `app/src/components/clubcard.tsx` — entire club home module (search, night banner, demand ticket/strip/league, worn stamp)
- `app/src/components/patch.tsx` — badge worlds (worldOf + grade materials)
- `app/src/components/CourseStrip.tsx` — course world cards (world-tone traces)
- `app/src/components/ui.tsx` — StatBlock upgraded to Oswald
- `app/app/owner/home.tsx` — ruled stat cells, coral radar, stadium roster (1200 lines; beware the morphing hero)
- `app/app/owner/schedule.tsx` — bands + T3 seal + share row (Sean said keep as-is — no big changes)
- `app/app/community.tsx` — Strava stat bars, violet recap stubs, collar dots
- `app/app/my.tsx` — domain-ink menu
- `app/app/shop.tsx` — terracotta boutique (keep as-is per Sean)
- `app/app/alerts.tsx` — postmark ink system
- `app/app/club/[id].tsx`, `club/session/[sid].tsx`, `club/pass/[sid].tsx` — violet night world + pass screen
- `app/app/owner/dog.tsx` — collar color picker
- `app/app/runner/requests.tsx` — demand strip (R1-C)
- `app/src/lib/api.ts` — club/demand/series/collar APIs (⚠ this file was edited directly on-device via python)
- `app/src/lib/push.ts` — reward/community deep-link routing

Design labs (docs/design/): final-system-lab, app-upheaval-lab, club-premium-lab, club-customer-flow, color-vitalize-lab, club-color-lab, demand-board-lab, schedule-stamp-lab, club-stamp-lab, club-emphasis-lab, glowup-lab, hi-club-lab.

## 7. Pending on Sean's side

- **[needs-user] `npx supabase db push`** — 0032/0033/0034/0035/0036 application status [uncertain] (0030·0031 applied [from-history]). Demand board, series, records, collar, and pass screen show no data until pushed.
- **[needs-user] `git push`** — both main and redesign-v4.
- **[needs-user] Redesign review** on device (npm install for fonts confirmed done [verified-now]). If satisfied: `git checkout main && git merge redesign-v4`.
- **[needs-user] Second account** for the club full loop (RSVP → pass → check-in → finish → recap in feed).
- KIPRIS trademark manual check (todo §E) [from-history].

## 8. Environment traps (must know)

- **Device git locks**: every commit leaves `.git/index.lock` / `tmp_obj_*` that cannot be unlinked → mv them into `_to_delete/git-locks/` after EVERY commit (rm is impossible on the mount; only mv works). Also check for a stale lock BEFORE committing.
- **Staging cache corruption** ⚠⚠: `device_stage_files` **intermittently returns stale file versions** (md5 mismatch — actually happened with api.ts, theme.ts, shop.tsx). **Always compare md5 against the device before editing anything staged.** On mismatch, edit directly on-device via python heredoc. This trap caused the earlier text-sweep rollback accident (commit df66d94).
- **Container mirror** `/tmp/daengrun` — partial and possibly stale. Never trust without md5 verification.
- **Harness runs in the container**: root can't initdb → `runuser -u postgres`. If a stale postmaster wedges it, `rm -rf .pgtest` and rerun.
- **tsc runs on the device**: `cd app && npx tsc --noEmit` (never chained with other commands).
- **RN constraints**: `Row` component style prop takes no arrays (use object spread) · `StyleSheet.absoluteFillObject` has a type-error history (use explicit position props) · no gradient library (use solid + glow shadow) · rn-svg strokeDashoffset animation needs the JS driver.
- **Harness DO blocks = single transaction**: `now()` is frozen → why created_at needed a tie-breaker.

## 9. Ideas discussed but not built

- **V4 remainder**: home masthead + ink-rule hero, highlighter mark ("오늘도 <하이> 찍자"), 3D coral CTA (slider only got sharpened), body-font rollout to all screens, V4 passes on request/report/live/shot-studio, club page D1 masthead. Sean: "later later I want to ask you again to show me this style in other screens" — lab first when he does.
- **runner-profile upgrade** — destination of the featured-runner card; make it an "athlete page" (step 2 of the runner-PR flow).
- **P-B polish leftovers**: club patch visualization (reuse the ladder), story/Kakao share formats (via the 인증샷 pipeline).
- **P-C delegation**: existing booking + session_id extension approach. Harness scenarios mandatory. Re-read hi-club-plan.md before starting.
- **P3 gold UI surfaces**: report PB hero, feed milestone cards (detection ships in 0034; surfaces don't exist yet).
- **Demand threshold (10 teams)**: a product constant with no behavior yet — what actually happens at 10 (notification? runner broadcast?) is undefined.
- **Community composer**: a "+ 자랑하기" entry point discussed only (sharing currently goes through the schedule tab).

## 10. Next 1–3 steps

1. **[needs-user → read-only]** Receive Sean's device review → micro-adjust. Expected friction points: coral radar vs violet club coexisting on one screen; featured-runner card with only one runner (featured only, no rail); Oswald numerals sitting next to Korean text.
2. **[local-edit]** V4 remainder screens (§9 first item) — when Sean asks to "see this style on other screens", lab first.
3. **[needs-deploy]** After review passes: merge to main + full db push + guide the two-account club loop verification.

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
npx supabase db push      # applies 0032–0036
git checkout main && git merge redesign-v4   # only after review
rm -rf .pgtest            # harness reset (container)
```
