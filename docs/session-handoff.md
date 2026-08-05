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

**Lab**: docs/labs/passport-stamp-lab.html — Sean picked **A1 B1 C2**.

## 2e. Rewards ② — IMPLEMENTED (A1×B1×C2, zero migrations)

2 Opus builders + adversarial review (P0 0 · P1 5 · P2 7, all approved fixes applied):

- **api.ts stamp engine** (~:833-1041): `fetchStampStats()` — 7 parallel RLS'd reads (완주 count via runs!inner end_reason gate · courses via fetchCoursePatches · club attended with MANDATORY profile_id self-filter (session_people RLS is open to all authed) · max-historical KST week streak (monotonic 'ever') · poop_bonus run count · feed shares · reviews). `deriveStamps()` — 12 slots matching the lab 1:1 (run 1/5/10/25 · course 2/3 · club 1 · streak 2 · poop 1/10 · share 1 · review 1), carries label/cond/prog(real progress strings)/rings/coral/**angle (canonical per-key tilt — screens must NOT compute their own; the seam where two builders diverged on 11/12 keys was the review's headline catch)**. `fetchStampPop(bid)` — fetchPatchPop idiom: newest-completed-booking guard + module Set; only run-ladder/course/poop crossings can announce (club/자랑/후기/streak silent by design — announcing them at run end would lie).
- **report.tsx Ⓒ② merged ceremony**: HaulOverlay replaces PatchPopOverlay — night-lilac 0.94 backdrop (fixes the 0.72 transparency defect), patch springs → stamps stagger-slam at canonical angles, HAUL_CAP 3/≥377dp else 2 (+ 외 N개), one CTA 컬렉션 보기 → /cards. Forest-era overlay colors retired. Earning strip untouched.
- **my.tsx §③ 도장면 (Ⓐ①)**: the vacant §③ slot filled — visa-page card, 12 discs (violet #4A3DA8 ink, ring-count ladder, coral edge+dot for 첫-family), earned shows NAME / unearned shows real progress (`7 / 10 완주`) else condition, N/12 Oswald chip, calm (zero animation, ceremony lives on report), renders nothing pre-load/error (never 0/12), refetch on focus, zero new foil/BHS. Record face now shows '—' while loading (was 0.0km — loading≠0).
- **cards.tsx Ⓑ① annex**: full lilac repaint (useTheme/volt retired), 컬렉션/ANNEX masthead, back = canGoBack→back else home (all 6 entries are push), §도장 grid + §코스 패치 in night-lilac well (locked-patch chrome lifted for dark-ground contrast, measured), PatchBadge inner name suppressed here (was 7.75px double-render; patch.tsx untouched — name was already optional), split stampErr/patchErr with honest inline fail notes (half-failure no longer silent).
- **Honesty copy law extended**: "도장은 한번 찍히면 지워지지 않아요" was FALSE (two accepted decay vectors: 자랑 post deletion un-earns share1; route deactivation shrinks course counts) → all surfaces say '기록이 남아 있는 한 도장은 그대로예요'; api.ts contract comment names both vectors.

**Reflect (retro)**: parallel builders on a shared contract MUST also share derived constants — the angle table existed in the contract but both walls hashed their own; pin presentational derivations in the contract next time. Copy is honesty surface #1 again (3rd consecutive cycle a reviewer caught overpromising copy). Deferred: 자랑/코스 decay vectors need a server persistence table if Sean ever wants literal-forever.

## 2g. Take-rate DECIDED + biz research + apply.tsx truth + cert-funnel spec (2026-08-05, Sean directives)

**TAKE-RATE = 33% (Sean decision).** Current state: client `pricing.commission = 0.2` (theme.ts:152), server `runners.commission_rate default 0.20` (0001:75), settle-run trusts the runner row. Implementation = NEXT SESSION's 5-agent cycle (0057+), bundled with the security hardening below — Sean explicitly said don't get ahead of the backend. Unblocked by this decision: rewards ③ (point-spend) and brand-deals ⑤.

**⚠ SECURITY (found by cert-funnel scout, fix FIRST next session)**: H-1 `runners self write` RLS (0002:70) has no with-check/column restriction — any runner can self-set tier/total_runs/**commission_rate=0** (settle-run trusts it → payout theft). H-2 runner_documents `for all` lets applicants self-verify. H-3 `ensureRunner()` mints tier='certified'/identity_verified=true on the production path. Full analysis in docs/specs/runner-cert-funnel-spec.md §2.

**apply.tsx honest repaint SHIPPED**: mock funnel ('인증 러너'·'36회 남음'·fake checkmarks) retired with `applyStatus`; screen now shows real `runners` row (tier/total_runs/total_km/commission_rate via new `fetchMyRunnerCert`), the cert process as a static explainer (no personal states), an honest 준비 중 card, lilac repaint (swamp 0). Deliberately NOT rendered: funnel_step/identity_verified/education_modules_done (ensureRunner bootstrap pollutes them).

**docs/specs/runner-cert-funnel-spec.md** (621 lines, design-only): state machine, schema (runner_applications/education/trial/KYC artifacts), RLS + server-only transitions, attack surfaces, 5-agent cycle scope. 8 open questions for Sean (KYC provider · education content · trial evaluator supply · 범죄경력회보서 legal handling → counsel · re-application policy · WHICH tier ladder is real (3 unbacked ladders coexist; commission_rate not actually linked to tier) · ops surface · applicant visibility).

**docs/biz/brand-outreach-research.md** (web-verified 2026-08-05): 페티즌·댕러민 DO NOT EXIST (dead leads from old docs). Real top targets: 바잇미 (₩22bn GMV, runs 체험단+affiliate+B2B already — pitch R2+R3), 아르르 (Dongwon F&B, Seocho-registered), 페스룸 (public partnership intake board — no cold outreach needed), 커고코리아 (Kurgo running-gear distributor, Dongjak), 카디날코리아, 닥터바이, DogFit. Surprises: Seoul's free 7979 러닝크루 runs Thursdays at 반포한강공원 through Oct (R1 thesis proven in our geography; 2023 had a dog-run session); 펫피 already sells app-based sampling (differentiate on verification+moment+photo proof); insurance precedent exists but later-rung.

**docs/biz/affiliate-product-research.md**: Coupang Partners is the wrong default (≈3%→~2% effective, 24h cookie, API gated behind ₩150k cumulative sales). Better: 무신사 큐레이터 (up to 10%+, Ruffwear+HOWLPOT are official Musinsa brands) + 네이버 쇼핑 커넥트 (seller-set 3–50%). No Korean premium pet mall runs a public affiliate program → direct 제휴 priced on run data is the real opening. First shelf: 10 picks (Ruffwear harness/lead/treat-pouch/cooling vest/shoes, HOWLPOT 라일락 harness, LILA LOVES IT paw balm, Aesop 애니멀, hip pack, SmartTag2+pet strap). Category expansion: ratify E1 owner gear/E2 post-run care/E4 SmartTag; E3 nutrition editorial-only; reject E5–E8 (commodity). Corrections: 하울팟 is lifestyle not fresh-food; Julius-K9 no KR importer; Coupang Ruffwear pricing suggests parallel imports (warranty caution).

## 2h. Shop redesign lab — DELIVERED (awaiting Sean's numbers)

`docs/labs/shop-redesign-lab.html` — Ⓢ shell 3종 (① 면세점/듀티프리 gates · ② 러닝 전문점 racks 전/중/후 with run-data rails · ③ 매거진 weekly shelf) × Ⓔ card 2종 (① 태그/러기지 카드 + outbound handoff sheet with Coupang disclosure verbatim · ② 선반 카드 with optional 기록 editorial slot). Sample inventory = the researched 10-item first shelf at real prices. Every priced card carries 제휴/광고 chip (38/38 verified); point-payment affordances absent (⑤ blocked — balance demoted from wallet-hero to 통장 strip with 적립만 돼요); "◈ Show deal-gated parts" toggle outlines all 64 nodes that may not render before a signed deal. Bindings legend with IN/OUT honesty rows: weather = NO SOURCE (month/hour stand-in), paw stress = NO SOURCE (routes.terrain exposure phrasing), ratings/reviews/stock/discounts = banned, affiliate URLs = NOT YET (hence day-0 준비 중 states). Boss-review correction applied: 누적 km binding split — dogs.cumulative_km has NO WRITER (seed-only); course count real. Lab recommends **Ⓢ②×Ⓔ②** (Ⓔ① for 2-col surfaces). Reply "S2 E2" style. Implementation gates: Sean ratifies category expansions (E1/E2/E4 recommended) · Coupang Partners/무신사 큐레이터 applications · first real link before any card goes live.

**⚠ Bridge note**: desktop bridge dropped mid-batch — apply.tsx/api/store/my + 2 research docs + cert-funnel spec + this handoff + shop lab are delivered via chat but NOT yet written to device/committed. Next bridge connection: device_commit_files the batch, run tsc+check-rpc, commit (suggested: two commits — ① 33%+apply+spec+research ② shop lab).

## 2f. Cleanup pass — DONE (same day)

- **stamp.tsx extraction**: StampCell + ink law + width budget now live ONLY in `src/components/stamp.tsx` (exports STAMP_INK/STAMP_INK_FILL/STAMP_GAP/STAMP_CELL_W/STAMP_DISC/StampCell); my.tsx §③ and cards.tsx consume. The 11/12-tilt-divergence class of bug is now structurally impossible between the two walls. report.tsx's StampDisc stays local (night ceremony variant, different animation wiring) but reads the same canonical angle.
- **Runner-side dead mocks retired** (all zero-consumer verified): `runnerGearLadder` + `GearStep` (carried fake '수령 완료' items), `currentDrop` (mock roll), `streakRanking` (fabricated people). Real sources: rewards.tsx server drops/gear_claims.
- **Found, deferred (needs design decision)**: `applyStatus` in store.ts IS consumed by runner/apply.tsx and renders fabricated funnel data ('인증 러너'·'36회 남음') as real — plus apply.tsx still carries swamp-era colors (#b8c4ae, colors.volt). The honest fix needs a real cert-funnel data source (doesn't exist server-side) or honest '준비 중' copy → product call for a future runner-side slice. Also `daengMiles: 12400` mock field (1 ref inside store's own dog mock — harmless).

**NEW smoke (rewards ②)**: passport §③ (12 slots, earned names vs progress lines, silence pre-load, 320dp 3-col grid) · 컬렉션 annex (back returns to pusher, night well patches, half-failure notes) · merged ceremony on a fresh completed run (patch+stamps together, ≤375dp shows 2+외N, no replay on re-entry, old reports silent) · record face '—' while loading.

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
