# SESSION HANDOFF — 2026-08-05 (motions ②④ + font floor 14 + rewards ceremony resolved)

English from here on (Sean: "use english"). In-app UI copy stays Korean (product language); commit messages stay Korean.

## ⓪ STATUS — 2026-08-05 batch (this commit)

- **Motions ② (seal stamp) + ④ (drain ring): DONE** — Sean picked "2 and 4" from choreography lab, implemented with real deadline bindings, adversarially reviewed, all 8 review fixes applied and boss-verified.
- **Font floor 12→14: DONE** — Sean chose "Floor 12 → 14–15pt" (NOT literal 2x). 506 sites bumped app-wide; 162 repo-wide survivors are all legitimately decorative-class (letterspaced caps ≥1, textTransform uppercase kickers, glyphs, FINISHER/DOGS HIGH serials) — verified by boss grep, no action needed. Coupled constants recomputed (fitness HERO_BIG 619 / COLLAPSE 542, owner-home HEADER_H 123 / HERO_SMALL 199, STAMP_CELL/STAMP_FONT 320dp guard).
- **Rewards office hours: ALL THREE directions approved by Sean** — see `docs/gstack/rewards-office-hours.md` §4. ① surface earning moments (this sprint) · ② passport stamps (next sprint, joins glow-up lab) · ③ spendable points (queued behind take-rate). Plus: owner-side points named **하이 포인트** (unified with runner), **home beacon revival approved** (real balance + patch progress ONLY — `claimable` lie stays banned).
- **gstack adopted as process layer** (garrytan/gstack; source mirror /tmp/gstack — container path, dies with container; re-clone if needed). Sprint = Think→Plan→Build→Review→Test→Ship→Reflect; office-hours premise challenge + plan-ceo-review ceremonies via AskUserQuestion. /browse /qa /ship don't apply (native app, Sean-only pushes).
- Commit stack this session: 0ed2709 (0054, pushed+deployed) → 725bf78 (0055/0056) → 567cdb7 (earnings/D-day/bell) → b0daea2 (W4 hero) → 2162b90 (choreography lab) → [this commit].
- **UNANSWERED Sean question**: add a gstack section to CLAUDE.md? Say "claude.md yes/no" in passing.

Opener for next session: **"read docs/session-handoff.md fully, then continue"**.

## 1. This batch in detail

- **Motion ④ — DrainRing** (`app/src/components/drainring.tsx`, NEW): View-dot deadline ring, no Animated, parent-tick driven, internal lerpHex ramp accent→coral→coralDeep, props `{leftMs, totalMs, size?, dots?, showTime?}`, min 1 lit dot while alive, mmss center 22/27. Wired in club session sheet at proposal (PROPOSAL_MS 5min/0047), hold (HOLD_MS 20min/0043), check-in window (0030, size 26 no numeral) + console inline (size 28). Expired-proposal branch added: accept CTA disabled + honest copy '제안이 소멸했어요 — 호스트가 다시 제안해야 해요'.
- **Motion ② — gold seal stamp** (`app/app/club/receipt/[bid].tsx`): once-per-booking via `sealStampFresh(bid)` module-Set in api.ts (beside `_patchPopSeen` precedent). Consume effect gated on `report?.run` + consumedRef (P1 fix: was consumed during loading render → animation lost if user backed out pre-load). Seq: 350ms delay → bezier(0.5,0,0.7,0.35) 340ms scale 2.6→1 rotate -14→-8deg + ripple + dip translateY on wrapper OUTSIDE cardRef (share capture unaffected); share gated on `stamping`.
- **Font sweep**: 51 client files touched. club-ui.tsx gains `vkTitle` token (14/700/ls 0.5/accent); vk 8.5 kept latin-kicker-only (zero callers now — retire or keep, deferred). Deferred design calls: ClubTag 9.5 mixed-class token · FEATURED RUNNER/tickerLead costume kickers · vk zero-callers.
- **Rewards doc** rewritten in English with Sean's decisions recorded.

## 2. Standing doctrines (Sean's invariants — all prior ones remain in force)

- Sean-only: db push, functions deploy, git push. Never claim device-visual success — Sean smoke-tests.
- Honesty: no mockups/fake numbers; bind real fields or omit; failures shown as failures; loading≠0; no dead buttons. Display vocab unreliable → gate on rawStatus.
- Commit gate: device `tsc --noEmit` + `node scripts/check-rpc-contracts.mjs`.
- Migrations/security → Opus 5-agent adversarial cycle + container harness (224/224; PG16 at tests/.pgtest; pg_ctl must start in SAME Bash call). New definer functions: `set search_path = public, pg_temp` IN BODY (98 H1 watches).
- **Font law update: detail-text floor is now 14pt** (was 12). Exempt: decorative class only (letterspaced caps, serials, glyphs). Oswald numerals need explicit lineHeight ≥1.2× ("BUG A").
- Device bridge: staging cache serves STALE files (proven 4×) — md5-verify against device; recently-changed files travel via `tar czf - files | base64 -w0` through device_bash → decode from tool-result file. git lock ritual: `mv .git/*.lock _to_delete/git-locks/` (device_bash cannot rm).
- Respond to Sean in English; code comments/commits Korean; commands as explicit lists without inline comments; SQL=editor, shell=terminal. Docs/discussion artifacts in English (new).
- Owner-home + fitness morph pattern DO-NOT-REFACTOR: pinned absolute overlay + paddingTop reservation + transform/opacity native-driver only.

## 2b. Glow-up batch — IMPLEMENTED (Sean picked A2×A4 + B1-with-color-progression)

Lab was delivered, Sean picked: **Ⓐ② Night Stub shell carrying Ⓐ④'s seat map** + **Ⓑ① Red Core with a color progression** ("red for starters, blue when searching, soft green when confirmed"). Implemented via 3 Opus builders + 1 adversarial reviewer (0 P0, 4 P1 + 11 P2 all fixed):

- **clubcard.tsx ClubBanner**: night-lilac #1C1837 stub card — 84dp dashed stub column (HOST chip / D-day BHS numeral / RSVP ✓ dot when joined; collecting → interestCount/WAITING; no-session → memberCount/MEMBERS), holo monogram + edge (foil = exactly 2), seat-pip grid rendering N=capacity (clamp 24) filled=rsvpCount with 자리/마감 임박/마감 label, ghost CTA. Logic frozen, single door → /club/[id]. Reviewer verdict: ACCEPT clean.
- **owner/home.tsx GO disc**: 122px disc at ring bullseye inside the frozen center layer. State→color law (comment block at GO constants): coral=your turn (none "GO 러너 찾기", active "● LIVE" breathing) · blue=waiting (searching #5B82E8 pulse → radar, directed #4468CC → schedule) · sage #3F9A75=ready (confirmed D-day → meetup, handoff 시작 대기 → meetup). km one-liner above (halo pill, weekChip moved right:14), 체력 나이 chip below. stopPropagation vs hero; heroCollapsed touch guard (threshold 0.15·onContentSizeChange resync); goSub ink plate; NEW honesty fix: liveNext now excludes rawStatus no_show/incident_review (they rendered as 지명 대기 — lie; schedule.tsx owns their display).
- **meetup ×2 (owner+runner)**: full lilac repaint (85 swamp refs → 0) + 이중 봉인 dual-seal ceremony — two seal slots on a perforated stub band, fill ONLY on server truth (expressions character-identical to old Step done), gold seal vocabulary from receipt, SEALED ribbon at 2/2, timeline rail steps, big coral CTA, honest waiting states. Hydration guard = stamp animates only on post-first-sync transitions (once-law). P1-4 honesty fix: confirmHandoff failure now Alerts + stays 'arrived' (retry) instead of landing a fake seal. P2-11: fabricated '도보 8분 · 0.8km' ETA replaced with stage-bound truth.
- **club/[id].tsx**: detail bump 14→15/16 (34+ CLUB15 markers) + P1-2 floor rescue (doorSub 9.5→14/19, tile labels 8.5→14, host line 9→14, unit suffix →12) + 5 display lineHeights (BUG A) + door row stretch + numberOfLines={2} sublines (director call: show fare terms fully over truncation).

**gstack Reflect (retro)**: premise challenge caught that meetup screens were never lilac-repainted (Sean's "intermediary screen" instinct was right); adversarial review caught 2 honesty bugs (fake seal on failed write, fabricated ETA) that builders had flagged but not fixed — the review-executes-attacks law keeps paying. Known cost accepted: 위탁하기 door subline can wrap to 2 lines; tile stat labels grow tiles ~28dp at 320dp when both render.

**Deferred design calls (unchanged)**: ClubTag 9.5 mixed token · FEATURED RUNNER/tickerLead kickers · vk zero-callers. NEW: club/[id] hhmm/attendance display pass could go bigger (Sean may ask); GO compact-state echo deliberately omitted (ticket + island carry state when collapsed).

**Follow-up (Sean, same day)**: hero card background now carries a ~95% white wash of the GO state color (`GO_TINT` map — coral/blue/sage washes; halos tint in lockstep; discrete swap, bg animation would need non-native driver). **CLAUDE.md created at repo root** (Sean: "yes to claude.md") — permanent laws now infrastructure; handoff stays the session-state bridge. gstack visibility promise: sprint phases labeled explicitly in responses from now on. Also `docs/gstack/gstack-map.md` — invocation guide + 55-skill applicability map.

## 2c. Rewards ① — IMPLEMENTED (zero migrations, scout-verified)

Scout confirmed the office-hours claim and found it stronger: **miles_ledger.ref_id = booking id** for all settlement rows (harness 10_settle_suite queries it that way), RLS "miles self read" scopes to caller, `my_miles_balance()` RPC pre-existing. Built by 2 Opus builders + adversarial review (P0 0 · P1 2 · P2 10, all approved fixes applied):

- **api.ts**: `fetchRunEarning(bid)` — miles_ledger by ref_id, `.in(reason, SETTLE_REASONS)` whitelist (ref_id is polymorphic — drops write drop_ids), profile_id double-guard per 0027 doctrine, 0 rows → null. `fetchRewardBeacon()` — balance + **nearest-promotion** course (director fix: min toNext, not max count — a course 1-from-실버 beats one 14-from-마스터). `fetchCoursePatches` now throws on routes-query error (was swallowed; beacon made it load-bearing).
- **report.tsx** (the ONLY 1:1 earning surface — live/meetup both terminate here): 하이 포인트 적립 strip between map and 순간 스탬프, gated `earningLoaded && earning && endReason==='completed'` (mirrors server v_is_full; early termination → section absent, never +0). No animation — patch pop stays sole celebration. Contrast fixes: READ_VIOLET kicker (7.50:1), lilac.text unit.
- **receipt.tsx**: earning line INSIDE cardRef (share PNG carries it) between numRow and credits; condensed real-rows-only (`완주 +50 · 응가 +30 · 골드 패치 +200`); no skeleton in captured card; share gate unchanged (pre-load share → PNG honestly lacks the line).
- **home.tsx beacon revived** in the dead beacon's slot (under 예약하기): quiet hairline two-cell — 하이 포인트 balance → `샵 보기 ›` (/shop; NOT "쓰기" — no redemption exists yet, P1-2) + **다음 승급** `{실버|골드|마스터}까지 N회` + course name → 카드 보기 › (/cards). P1-1 fix: copy says 승급 not 패치 (earned courses already own their patch). NO pulse/urgency (the ui-audit P0 stays honored). Renders only when loaded AND (balance>0 OR next) — 0-balance silence. Fetch isolated from home's other loads. **Retired**: claimable/gift/pulse machinery, orphaned milestone-ladder sheet + ownerGearLadder mock + n7 '120P' noti + Noti.badge field.
- **Naming unified**: 마일 → 포인트 (leaderboard, runner rewards); leaderboard sign-aware delta (pre-③ bug); kickers keep 하이 포인트/HIGH POINT identity.

**Reflect (retro)**: scout-first paid again — ref_id=booking discovery turned a "maybe time-window match" into a direct read; reviewer caught two false-copy P1s in fresh code (승급≠패치, 쓰기≠보기) — honesty review must cover COPY, not just data binding. Deferred: runnerGearLadder dead mock (zero consumers, runner-side vocab — retire in a runner-side pass); no ref_id index (pilot-scale fine); receipt total unreachable-negative case now guarded anyway.

**NEW smoke items**: report earning strip (completed run vs early-terminated → absent vs pre-settlement → absent) · receipt earning line at 320dp + share PNG includes it + seal still lands on taller card · home beacon (real balance, 승급 copy, silence at 0-balance-no-progress, dark mode affordance color) · leaderboard/rewards 포인트 naming.

## 2d. Rewards ② — scouted, honesty batch shipped, LAB DELIVERED (awaiting numbers)

**Scout findings (a19f4a7)**: cards_owned path is NOT zero-migration (edge-fn writer exists but owners can never earn rows — struck; derived stamps are the only zero-migration path) · run-end lands on report.tsx, never my.tsx · app has no client persistence (one AsyncStorage UI pref) · verified derivable taxonomy: 첫 러닝·5/10/25회 완주·N번째 코스·첫 클럽 출석·연속 2주(historical max — monotonic)·응가 도장(per-RUN count)·첫 자랑·첫 후기. Balance-milestone stamps EXCLUDED (can un-earn; violates forever contract).

**Honesty batch (9174398, shipped)**: six mock cards (myCards) fully retired — owner home's 최근 기록 rendered a FABRICATED 5.02km run; cards.tsx is now the pure real patch wall; RunCard/CardStat retired (carried 조작 컨디션/+12%/24° strings), HeatTrace survives (report.tsx). my.tsx record face: 총 거리/총 횟수 labels showed WEEKLY data (Fitness has no total fields; f:any hid it) → owner shows weekly numbers with weekly labels; runner keeps real server totals with 총. Real owner totals come with ② implementation.

**Sean's ② decisions (all Recommended picked)**: ceremony on report.tsx (with patch pop — queue or merge, lab decides) · collections MERGE into passport world (/cards reborn lilac as the annex, back → 마이) · stamps are FOREVER (monotonic only) · 첫 클럽 = ATTENDED (session_people checked-in).

**Lab (docs/labs/passport-stamp-lab.html)**: Ⓐ stamp wall ① §③ 도장면 visa page ② 기록면 strip ③ 여권 펼침 spread · Ⓑ merged collection ① 부속서 two-section ② 통합 그리드 · Ⓒ ceremony ① queue-behind-patch-pop ② merged single overlay. Ink law chosen: violet #4A3DA8 stamps, coral only as 첫-family ring+dot, gold stays in the receipt, zero new foil (my.tsx budget spent). Lab recommends **Ⓐ①×Ⓑ①×Ⓒ②**. Reply "A1 B1 C2" style. Lab-found defects to fix with implementation: PatchPopOverlay backdrop too transparent for report.tsx's new content · cards.tsx renders course name twice (once at ~8.6px inside PatchBadge).

## 3. Pending on Sean's side (ordered)

1. `supabase db push` — 0055·0056 if not yet pushed (0051–0054 confirmed pushed+deployed).
2. `supabase functions deploy transition-booking` — decline-ledger writer (with/after 0056).
3. Post-push definer audit in SQL editor (expect 0 rows):
   `select p.oid::regprocedure from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%pg_temp%';`
4. `git push` (redesign-v4 — device now ahead ≥4).
5. Device smoke, cumulative: matching roster (available-only, rookies bottom) · schedule sheet status matrix · decline→open-pool absence→direct re-request · runner home 이번 달/누적 + bell dot · owner home NEXT RUN sort + D-day chip + bell off when read · fitness morph/rail/3-states/fontScale · receipt seal stamp (once per booking; clipping on photo-less receipts) · drain rings ×3 + expired-proposal branch · font floor legibility (320dp stamps) · **NEW: GO disc all 6 states + colors (coral/blue/sage), disc tap ≠ hero tap, collapse leaves no dead touch zone, night club card + seat pips at 320dp, meetup dual-seal both sides (stamp animates on live confirm, NOT on re-entry; failed confirm → Alert + retry), club home text pass**.
6. "claude.md yes/no" (gstack section in CLAUDE.md).

## 4. Next 1–3 steps

1. **Glow-up lab (top of queue, Sean-requested)**: club widget creative emphasis ("bland right now") + red GO button in the morph ring center, synced to Live run widget, showing accumulated km or age — now also carrying rewards-① candidates (real 하이 포인트 balance / next-patch progress) as detail options. HTML lab → Sean picks by number. Beacon revival rides this.
2. **Rewards ① implementation**: report.tsx + receipt.tsx earning lines (real miles_ledger reads for that run), home beacon = balance + N-to-next-patch, owner-side 하이 포인트 naming. Zero migrations.
3. Rewards ② (passport stamps) next sprint via lab; ③ blocked on take-rate — do not start.

## 5. Known bugs / gotchas

- Prior list remains (5pm mystery → 409 will confess post-deploy · roster font clipping [device] · .fuse_hidden ignore · refund_pending is a terminal state — Sean to sanity-check product-wise).
- `cards_owned` still has zero readers (rewards ② will be its first).
- app/client-md5-manifest.txt on device — moved to _to_delete/ this batch (or move it if the mv failed).

## 6. Verification commands

Read-only: `git log --oneline -6` · `git status --short` · device tsc `cd app && ./node_modules/.bin/tsc --noEmit` · `node scripts/check-rpc-contracts.mjs` · container harness `cd /tmp/daengrun/supabase/tests && runuser -u postgres -- bash harness.sh 2>&1 | tail -3` (expect 224/224).
Expensive/destructive (Sean only): db push, functions deploy, git push.
