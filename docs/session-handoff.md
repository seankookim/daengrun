# SESSION HANDOFF — 2026-08-12 (PM, the money-model day) · redesign-v4 @ d89af7c

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**

Companion docs, in reading order:
1. `docs/plans/payments-toss-plan.md` — **THE ACTIVE MONEY TRACK.** §0-bis (post-pay +
   price-invisibility) overrides §2/§3's widget-per-payment flow, which is now fallback.
2. `~/.gstack/projects/seankookim-daengrun/sean-claude-token-payments-model-891c11-design-20260812-134138.md`
   — the level-token model: APPROVED DESIGN — **PARKED**. Read its LATE AMENDMENTS +
   BLOCKING GAPS blocks first; the terminal GSTACK REVIEW REPORT is the audit trail.
3. `docs/labs/` — four labs current: `onboarding-level-lab.html`, `record-card-lab.html`,
   `pay-rebuild-lab.html` (v3), `km-token-lab.html` (historic). Sean picks by number.
4. `docs/session-handoff-archive-20260812-am.md` — the morning session (sections B/C/D/E,
   prod state); this document supersedes it for money-model matters only.
5. `TODOS.md` — new entries from tonight at the top.

---

## 1. Status table

| System | State | Provenance |
|---|---|---|
| main checkout `/Users/sean/dev/daengrun` | branch `redesign-v4` @ `d89af7c`; tree has session doc edits staged-for-commit by this handoff's commit; other untracked files (`.agents/`, `docs/b2b-revenue.md`, …) belong to OTHER sessions — do not touch | [verified-now] |
| SQL harness (main) | **383 pass / 0 fail** incl. new `[rgd]` R1–R4; run with `PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH LC_ALL=C bash harness.sh` from `supabase/tests/` | [verified-now] |
| Backend agent branch `worktree-agent-a8055198b70c23b64` @ `00e18bc` | rebased ON d89af7c; 0076 intent migration + create-payment-intent + confirm-payment + Deno tests; **deno 35/35, harness 388/0** | [verified-now — I ran both after my JWT fix] |
| SDK agent branch `worktree-agent-a38f8c5204d989c7b` @ `d1e2b9f` | based on redesign-v4 @10d7b76 (pre-0077); Toss RN SDK scaffold behind `TOSS_ENABLED=false`; install/prebuild/pod/tsc all clean | [reported — agent output; no device build has EVER run] |
| Prod DB | on 0074 per the morning handoff; 0075 pushed but UNWIRED (nothing calls it); 0076/0077 NOT pushed | [from-history — recheck `supabase migration list` before any push] |
| Real payments | ZERO ever charged; `pay.tsx` "실결제는 발생하지 않았어요" is TRUE | [verified-now — code read] |
| Filings | 사업자등록 NOT filed; blocks live keys, legal footer numbers, everything | [from-history — Sean-only] |
| Design labs | 4 files in `docs/labs/`, updated tonight, committed by this handoff's commit | [verified-now] |

## 2. Goal & current state

Goal: daengrun's money model, end to end. Today produced two layers:
- **ACTIVE (build next): per-run post-pay** on the existing booking flow — card linked
  once (Toss 빌링키), nothing charged before/during service, `settle-run` charges actuals,
  price visible exactly once (request screen, small). Phase: eng-reviewed with a
  **NEEDS-ENG-PASS remaining on the settle-time charge + debt state machine** (§0-bis).
- **PARKED (design complete, do not build): level-token 회수권** — un-parks only on real
  conversion data + blocking gaps G1–G4 resolved on paper, and tonight's invisibility
  doctrine + Way-2 demotion weakened the un-park case further.

Workstreams: backend Toss slice = built-on-branch, untrusted-until-adversarial-cycle ·
SDK spike = done, verdict conditional-yes · design labs = current, awaiting picks ·
0077 guard = done, committed, mutation-proven · filings = stopped (Sean).

## 3. What shipped this session (by theme)

**Model decisions (in `~/.gstack` design doc + decision log, `gstack-decision-search`):**
the full D1–D8 office-hours chain (level token, dual threshold→later reversed, session
pay 25%, 회수권 ladder), CEO parking verdict T3, eng review A1–A3/T1/X1–X4, evening
amendments A-17/A-18/A-19, D1=C post-pay, price-invisibility doctrine, run-end semantics.

**Code (committed):**
- `d89af7c` on redesign-v4: `supabase/migrations/0077_recurring_guard.sql` +
  `supabase/tests/114_recurring_guard_suite.sql` + harness wiring. Mutation results in
  the suite header — all four reverts executed.
- `00e18bc` on the backend agent branch: `0076_payment_intent.sql` (status `'pending'`,
  `profiles.toss_customer_key`), `supabase/functions/create-payment-intent/`,
  `supabase/functions/confirm-payment/` (intent lookup → idempotent-first → Toss confirm
  → §2-7 auto-cancel machine → CAS → server-side postConfirm), `_shared/toss.ts`,
  `_test/` Deno suite (35 tests), 109 suite P7–P11. **⚠ Under §0-bis this whole flow is
  now the FALLBACK path** (no card linked) + future bundle rail — still worth merging,
  not the primary flow anymore.
- `d1e2b9f` on the SDK agent branch: `@tosspayments/widget-sdk-react-native@1.5.2`
  scaffold, `app/src/lib/toss.ts` (flag), `app/src/components/toss-sheet.tsx`,
  `app/plugins/withKoreanPayApps.js` + `korean-pay-schemes.json` (39 schemes, both
  platforms), api.ts client contract.

**Docs (committed by this handoff):** plan amendments (§0-bis two-way/post-pay/invisibility,
§2-7 intent machine, §2-8 methods, §3 SDK spike + fallback spec, §4 test rail 109-fix,
§5 buildable-now + refund gate), supersession banners on `km-token-model.md` and
`0059-take-rate-33-plan.md`, TODOS entries, four labs.

## 4. Standing doctrines (the five that bite)

Canonical: repo `CLAUDE.md`, `DESIGN.md`, migration headers. Most load-bearing today:
1. **Honesty law** — no UI claim the system can't back; loading ≠ 0; removing a TRUE
   sentence is also a lie (pay.tsx:299 stays until charges are real).
2. **Money paths**: own migration + adversarial cycle + mutation-proven pins, each pin
   red under a named revert that is ACTUALLY RUN. `_fail` args pre-computed. Definer
   `set search_path = public, pg_temp` in the body (98 H1).
3. **클라 불신**: the client's word is never evidence — amounts from server truth,
   classifications server-derived.
4. **0077 caller doctrine (NEW)**: server code calls owner-gated RPCs with the CALLER's
   JWT, never service_role; service-role needs = explicit-param server-only functions.
5. **Style freeze** until 50 paying dogs: 순백/코랄 language; primary CTA = theme.ts
   action token `#C6472C` (DESIGN.md §3b's ink-primary table is STALE — needs reconcile,
   flagged twice by agents).

## 5. Working-relationship norms

Sean picks **by number from labs** — never build screens from prose. He kills designs
with one sentence of taste ("dont like that the session and km is separated") and is
usually right; don't defend, synthesize. He reverses his own decisions fast when shown
evidence (D1=B→C within the hour) — reversals are normal, log them, don't re-litigate.
He reviews reviews (brought a 17-point critique of my own review, then a meta-review
grading its prioritization) — bring him findings ranked by severity, precision matters.
Quality bar phrases: "too dull", "too dense", "AI look" = redo it. English in chat,
Korean in-app copy. Sean-only: push, deploy, filings, secrets. Effort labels both
scales (human vs CC).

## 6. Decision log with WHY (chronological; ▸ = supersession)

- **Level-token 회수권 model** (D1–D8): distance is a dog attribute (level), 1회 = one
  run; chosen over ₩-wallet (kills the never-think-in-won premise) and two-token
  (Sean rejected the separation). Session-based runner pay 0.75×face (fixes slow-dog
  underpay ₩8,442≈1.2x min wage; deletes km-padding incentive); take 33%→25% to keep the
  doubleish-min-wage pitch. Honor-gift at level-up **REJECTED after Sean's critique #4**
  — uncapped negative margin (₩15,900 token paying ₩18,675 comp); replaced by
  token-buys-its-own-level.
- **T3 PARKING** ▸ supersedes "build after interviews": three independent reviews
  (codex, outside voice, Sean's 17 points) converged — validate real payment before
  pricing psychology. 8 runs, all Sean's.
- **D1 charge moment: B (at accept)** ▸ **SUPERSEDED minutes later to C (post-pay,
  "uber style", Sean verbatim: "no let's go uber style")** — charge actuals at settle;
  decline machinery (retry 0/+1h/+24h, debt state, account lock, runner paid regardless)
  is day-one scope, not deferred.
- **A-17 dual threshold** ▸ **REVERSED same evening**: completion = minimum distance
  ONLY. Sean's physical proof: routes are loops sized to the distance — a timer fires
  mid-route with the dog away from home. Time = one-directional encourager only
  (fast finish → "더 뛰어도 좋아요" + level-up signal). Pace = suggested minimum,
  default 8 min/km, band 7~9, prefs-set, never money-bearing, never ranked.
- **Price-invisibility doctrine (Kakao T rule)**: price once, small, request screen;
  no money on booking confirm; post-run = record card; card issuer announces; money UI
  on-demand (설정→결제 관리 — SCREEN DOES NOT EXIST YET, blocking) or on-exception.
  Sean: "remove the thought of price… the entire point of the tokens."
- **Way 2 bundles** ▸ demoted decided→optional ("not sure tokens and bundles are
  necessary… keep them as an option").
- **Run-end flow**: stop → confirm dialog → 귀가 intermediary (stats frozen, GPS on,
  un-charged) → return handoff (MISSING in marketplace — mirror of confirm_handoff)
  → record card. Money meter cuts at run-stop.
- **Refusals that carry reasoning**: refused to reuse the auto-cancel copy on the
  cancel-FAILED path (would tell a user money returned when it didn't — backend agent's
  correct override, kept); refused fabricated data everywhere in labs (percentiles,
  durations without formulas); refused to scrub time-threshold wording from the labs'
  RETRACTION records (they exist to stop the idea creeping back).

## 7. Architecture & contracts

- **Post-pay flow (target)**: card link (빌링키, verifies card) → book (NO charge;
  card-linked bookings need a create→matching edge — payment_hold is for the fallback
  path) → run → **settle-run charges actuals** `9,900+3,000×actual` via billing API,
  X1 intent rails ported to settle (pending row BEFORE the billing call). Decline →
  retry ladder → debt state → account lock. **NEEDS-ENG-PASS before build.**
- **Intent machine (built, now fallback-path)**: pending intent binds
  owner+booking+amount pre-widget; confirm completes/cancels; ANY post-capture failure
  auto-cancels same-request; reconciliation query is the consumer of failed cancels.
- **0077**: `create_recurring_series` double-belted; DO-NOT-REVERT the textual R4 pin
  (belt ⓒ is behaviorally shadowed by ⓑ — the header explains).
- **DO-NOT-REFACTOR / deliberate look-wrong**: 5-min `slot_hold` vs 30-min payment
  window (two clocks ON PURPOSE — matching is runner-search, accept-guard protects);
  two price constants `PRICING` vs `km_face_price()` (different sides); `payments` NOT
  in 68's sealed array (it deliberately has one SELECT policy).
- **Ordering constraints**: 설정 결제 관리 screen ships WITH the money-free booking
  screen or it's concealment (T6) · refunds (e_match auto-refund + cancel_owner) gate
  go-live of ANY real charge (X2) · pay.tsx:334 deletion only AFTER the new path passes
  the sandbox matrix (it is the only door into `matching`) · 0076 before wiring ·
  자동결제 심사 requested IN the same Toss application.

## 8. File map (touched/created; run commands included)

Main checkout: `supabase/migrations/0077_recurring_guard.sql` (guard),
`supabase/tests/114_recurring_guard_suite.sql` (pins R1–R4), `supabase/tests/harness.sh`
(+114 line; run: `cd supabase/tests && PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH
LC_ALL=C bash harness.sh`), `docs/plans/payments-toss-plan.md` (§0-bis is the law),
`docs/plans/km-token-model.md` + `docs/plans/0059-take-rate-33-plan.md` (banners),
`TODOS.md`, `docs/labs/{onboarding-level,record-card,pay-rebuild}-lab.html`.
Backend branch adds: `supabase/functions/{create-payment-intent,confirm-payment}/`,
`supabase/functions/_shared/toss.ts`, `supabase/functions/_test/` (run: `deno test -A
supabase/functions/_test/` — deno 2.9.5 lives in a session scratchpad, reinstall if gone),
`supabase/migrations/0076_payment_intent.sql`, 109 suite P7–P11.
SDK branch adds: `app/src/lib/toss.ts`, `app/src/components/toss-sheet.tsx`,
`app/plugins/withKoreanPayApps.js`, `app/korean-pay-schemes.json`, api.ts contract.
gstack artifacts: design doc + test plans + tasks JSONLs under
`~/.gstack/projects/seankookim-daengrun/`.

## 9. Pending on Sean's side

**Ops (only Sean can):**
1. **사업자등록 (홈택스, same-day, free) — THE critical path.** Then 통신판매업
   (~₩40k/yr) → Toss contract (1–2wk) **requesting 일반 + 자동결제(빌링) in one
   application**. Also: real 사업자등록번호/신고번호 gate the legal footer (currently
   ○-placeholders = the receipt's legal block is a lie until then).
2. Toss 개발자센터 once access exists: TEST keys into `.env`
   (`EXPO_PUBLIC_TOSS_CLIENT_KEY`), and **variantKey methods = 카드+간편결제, 가상계좌
   OFF** (dashboard setting — not enforceable client-side).
3. Merge the two agent branches into redesign-v4 when reviewed (disjoint dirs, both
   based on d89af7c-lineage; backend branch is current, SDK branch predates 0077 —
   rebase it or merge-order backend first). Push/deploy remain Sean-only.

**Decisions (each blocks the named work):**
1. **Lab picks** — Ⓡ①②③ + Ⓖ rule (record card; note: odometer news-value decays under
   distance-only → Ⓖ earlier) · D-1 price-line placement ① inline vs ② fee-card+legal ·
   D-2 KmDial live fare keep/delete/demote · Ⓛ③ spec-plate graft + ₩ vs 원. Blocks:
   screen implementation.
2. **D-3 silent-charge users** (issuer 알림 off → never told): accept vs monthly summary
   (couples to 전자상거래법 record duty — counsel). Blocks: nothing yet; decide by launch.
3. **GPS-loss "판정 보류" settlement meaning** (charge nothing pending review?). Blocks:
   settle slice. Sits with G1.
4. **OPS_PROFILE_ID**: env var vs real admin role. Blocks: reconciliation notify wiring.
5. **DESIGN.md §3b reconcile** (ink-primary table vs shipped action token) + legal-footer
   12pt exemption ruling. Blocks: design-law cleanliness only.

## 10. Known bugs, gotchas, failure modes

- Harness runs ONLY with PG16 on PATH + `LC_ALL=C`; agents proved it also runs from
  worktrees (memory said main-only — update: worktrees OK) [verified-now].
- `docs/plans/` and `docs/labs/` are working-tree-only in some worktrees (this session's
  conversation worktree lacks them) — agents must read them via absolute main-checkout
  paths [verified-now].
- **Conversation worktree `claude/token-payments-model-891c11` is design-lineage** —
  its supabase/ stops at 0036. Both build agents had to fast-forward to redesign-v4.
  Any future agent worktree from this branch inherits the trap.
- Codex `exec` timed out (5 min) on both long-prompt runs; the short-prompt run
  succeeded. Prefer Claude-subagent outside voice for long inputs.
- `plutil -extract … json FILE` without `-o -` REWRITES the file (SDK agent's
  self-inflicted scare) — false-corruption signal.
- 0058 §5's "assessed-safe" class silently fails open under service_role (auth.uid()
  NULL) — the entire pattern class; 0077 fixed only the function that gained a server
  caller. If server code ever calls another owner-gated RPC, re-audit first.
- False-success traps: a suite not wired into harness.sh is a silent zero; `_fail` with
  a subquery arg only explodes when the pin FAILS.

## 11. Known-good — do not "fix"

- The A1/X1 intent + auto-cancel machine and its Deno suite (35/35) — including the
  cancel-failed path's DIFFERENT honest copy (deliberate, tested by absence-assertion).
- 0077's belt pair incl. the textual R4 pin (shadowed belt, documented).
- The 5-min/30-min two-clock design; runner_accept's overlap guard.
- pay.tsx's existing visual grammar (Sean explicitly likes it — labs now conform).
- The four labs as of tonight; `payment_hold→matching` CAS with its honest 0-row sentence.
- 109/113/114 suites and their mutation maps.

## 12. Ideas discussed, not built

- **Live-cam subscription package** (Sean): dog-mounted cam as subscribe thank-you,
  live widget in running screen; needs 빌링키 (shared rail), streaming infra, harness
  safety, pricing. TODOS P3.
- **Pace-state UI**: green/yellow vs suggested pace on owner+runner+Live Activities.
  TODOS P2.
- **Fast-finish level-up detection** (record-card breadcrumb exists in the lab; the
  detection rule "3 consecutive early finishes" is Open Q9 in the parked doc).
- **Monthly usage summary** (D-3 option) · **회수권/bundles as optional Way 2** ·
  parked-doc extras: 장거리 tier, 적립 re-derivation, runner tier ladder fate.
- Sean's onboarding-cadence question (주 며칠) still ships — it survived every model.

## 13. Strategic read (my recommendation)

The model converged to something genuinely strong: both sides settle on actuals from
one formula, and the price thought exists for one small moment. The danger now is
drift-by-enthusiasm — tonight produced four doctrine-grade decisions in three hours,
and each was RIGHT, but the settle-time charge machine has not had its eng pass and the
backend branch implements the *fallback* flow, not the primary one. So: **freeze model
churn; spend the next session making the post-pay skeleton real** (eng pass → 0078-class
settle-charge migration + debt states → 설정 결제 관리 screen). If Sean pushes to build
screens first: the labs are pickable but every payment surface depends on the settle
machine's states — screens built before the eng pass will be rebuilt. And nothing—
literally nothing—beats 30 minutes at 홈택스 for unblocking value per minute.

## 14. Next 1–3 steps

1. **[needs-user]** Sean: 사업자등록 + lab picks (§9). Verify first: nothing — paper.
2. **[read-only → local-edit]** Eng pass on §0-bis's settle-time charge + debt state
   machine (transition-map deltas: card-linked create→matching, debt states, meter-cut
   at run-stop). Output: amended plan §2 for post-pay-primary. Verify first: re-read
   §0-bis + 0060's sweeps + settle-run.
3. **[local-edit]** Then the 0078-class slice: settle-charge + debt states + 설정 결제
   관리 screen + G1 abort-charge composition, own adversarial cycle. Verify first:
   backend branch merged; harness green at merge.

## 15. Verification commands

Safe/read-only: `git log --oneline -5` (each tree) · `gstack-decision-search --recent 10` ·
`deno test -A supabase/functions/_test/` (backend branch) · harness (see §8 — rebuilds a
LOCAL test DB only, never prod) · `grep -n "TOSS_ENABLED" app/src/lib/toss.ts` (SDK branch).
Expensive/destructive — do NOT run casually: `supabase db push` (Sean-only; 0076/0077
would go live) · `expo prebuild` (mutates ios/android) · any `git push`.
