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

## 3. Pending on Sean's side (ordered)

1. `supabase db push` — 0055·0056 if not yet pushed (0051–0054 confirmed pushed+deployed).
2. `supabase functions deploy transition-booking` — decline-ledger writer (with/after 0056).
3. Post-push definer audit in SQL editor (expect 0 rows):
   `select p.oid::regprocedure from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%pg_temp%';`
4. `git push` (redesign-v4 — device now ahead ≥4).
5. Device smoke, cumulative: matching roster (available-only, rookies bottom) · schedule sheet status matrix · decline→open-pool absence→direct re-request · runner home 이번 달/누적 + bell dot · owner home NEXT RUN sort + D-day chip + bell off when read · fitness morph/rail/3-states/fontScale · **NEW: receipt seal stamp (plays once per booking; check clipping on photo-less receipts) · drain rings at proposal/hold/check-in + expired-proposal branch · font floor legibility pass (esp. 320dp owner-home stamps)**.
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
