# Plan — real payments via 토스페이먼츠

Branch `redesign-v4`. Written 2026-08-11. Supersedes `payments-bridge-plan.md`.
Status: **THE ACTIVE MONEY TRACK (T3 parking verdict, 2026-08-12) — filings gate LIVE keys
only; §5-1b is buildable NOW with TEST keys.** The level-token model
(`~/.gstack/projects/seankookim-daengrun/sean-claude-token-payments-model-891c11-design-20260812-134138.md`)
is APPROVED DESIGN — PARKED behind this slice's real conversion data. (An outside-voice
reviewer without this banner concluded this plan "builds the wrong product" from the old
km doc — the banner exists so neither humans nor models repeat that.)

Sean's decision (2026-08-11): **register (사업자등록) rather than route around it.** That deletes
the manual bank-transfer bridge and puts us on the real PG track.

## 0-bis. DIRECTION AMENDMENT (Sean, 2026-08-12 evening — two-way payments, invisible per-run)

**The payment ceremony at booking is friction (Sean: "payment just before searching for
runners is friction"). The model becomes two-way:**

**Way 1 — per-run, INVISIBLE, POST-PAY at settlement (D1=C, "Uber style" — Sean
superseded the brief charge-at-accept pick within the hour).** Card linked ONCE via the
widget's 빌링키 발급 flow (`/v1/billing/authorizations/...`; issuing the key verifies the
card). After that NOTHING is charged before or during service: booking is free, matching
is free, the run happens, and **the charge fires in `settle-run` on ACTUALS**
(`9,900 + 3,000 × actual` — the formula settle-run already computes). Consequences:
- **Under-run/over-run refunds dissolve** — you pay what happened, once, after. Matching
  expiry charges nothing. The X2 refund gate narrows to post-charge disputes/incident
  settlements (0072); **G1 (emergency stop) reframes from a refund problem to a
  charge-composition question** — what an aborted run is charged (waive vs base+actual)
  is a product decision expressed at settle, not a refund flow.
- **Cancel fees become small CHARGES, not refunds** — 0066's en-route 50% fee is a
  billing-key charge of the fee itself. The refund machinery shrinks to disputes only.
- **The cost, engineered on day one (not deferred): decline-after-service machinery.**
  Retry ladder (immediate → +1h → +24h), a booking-debt state, account lock (no new
  bookings until settled), honest owner copy naming the decline, and **the runner is
  paid by the platform regardless of collection** — collection risk is the marketplace's,
  never the runner's. Pilot exposure is bounded: ≤ one run's fare per owner
  (account-locked after the first failure), card pre-verified at link.
- ⚠ Transition-map touches remain, relocated: card-linked bookings skip `payment_hold`
  (create → matching needs its edge or a server-side immediate transition), and the
  debt/locked states need homes. **NEEDS-ENG-PASS: the settle-time charge + debt state
  machine, before build.** The X1 intent/write-order rails port to the settle moment
  (pending intent minted before the billing call — a crash never leaves a charge without
  a row).
- 자동결제(빌링) requires its own 심사 — Sean requests it IN the same Toss application.
- The §2/§3 widget-per-payment flow below is DEMOTED to the fallback path (owner with no
  card linked yet, or if 빌링 심사 lags — a pre-pay path by nature) and becomes the
  BUNDLE purchase mechanism later — the built scaffold and confirm-payment work are not
  wasted.

**PRICE-INVISIBILITY DOCTRINE (Sean, 2026-08-12 late — the Kakao T rule).** The price
appears exactly ONCE in the happy path: on the request/preference screen, small font,
alongside the options (that surface already exists). After that the owner never sees a
number again: booking confirmation carries NO money, the post-run moment is the RECORD
CARD (the dog, never the charge), and the card issuer's own 승인 알림 does the
announcing. Money UI exists in exactly two modes: **on demand** (booking detail →
결제 내역, 설정 → 결제 관리 — receipts must exist and be accurate there, 전자상거래법
footer included) and **on exception** (decline/debt/account-lock states — those cannot
be hidden and stay loud). This is honest: consent happened at request (price shown),
actuals-based charging was disclosed at card link, and the receipt is one tap away.
Honest ≠ loud. **This achieves what the token model's psychology was FOR** — recorded
plainly: it weakens the un-park case further.

**Way 2 — bundles/tokens: DEMOTED to optional (Sean: "not sure tokens and bundles are
necessary... keep them as an option").** Not designed-for-build anymore; a later option
behind the same filings + G1–G4, revisited only if per-run data asks for it.

Pay screen implication: pay.tsx keeps its EXISTING design (Sean, rejecting the Ⓟ lab
drift) — the work is a mechanism swap: card-link flow, a no-ceremony booking confirmation,
the fix-card state, receipts. 최소 pace/threshold copy per the A-17 amendment
(distance-only completion, suggested pace 8 min/km).

## 0. Why this is dramatically smaller than the bridge was

The bridge needed a new booking status because a human had to sit in the middle for hours. Toss
does not: the widget returns in seconds, inside the existing 30-minute `payment_hold` window.

**So this track needs NO new enum value, NO transition-map change, and NO change to
`enforce_booking_transition`.** `payment_hold → matching` already exists and is already pinned.
Everything the review flagged as expensive — the two-file enum migration, the 9 client
status-vocabulary update sites, the deposit identifier, the fee-ladder tier, the cancel-edge
copy problem, the same-dog clash guards — **evaporates**. That was the review's real payoff.

What remains is: swap the *mechanism* that proves money moved.

```
today   client → transition-booking {action:'payment_ok'}  → payment_hold → matching   (no money)
target  client → Toss widget → confirm-payment (verifies with Toss secret, server-side)
                                                            → payment_hold → matching
```

## 1. Sean's filings — the blocking path

| Step | Detail | Blocks |
|---|---|---|
| 사업자등록 | 홈택스, same-day, free. 개인사업자 is fine to start. | everything below |
| 통신판매업 신고 | 시/군/구, after 사업자등록. ~₩40,000 등록면허세/yr. Required for an intermediary. | PG contract |
| 토스페이먼츠 계약 | 1–2 week review (`payments.md:8`). Needs both documents above. | the live switch |
| Secret key | `supabase secrets set TOSS_SECRET_KEY=...` — **Sean only, never relayed.** | `confirm-payment` |

⚠ **The 예비창업패키지 2027 option (~₩40M) closes the moment 사업자등록 lands.** Sean has decided;
recorded here so it is not rediscovered as a surprise. `초창패/청창사` (≤3yr corps) remain open —
`marketing-fundraising.md:128`.

## 2. Server

### `confirm-payment` edge function (new)
Mirrors `transition-booking`'s shape. Steps, in order:
1. `caller(req, db)` → 401 for anon (existing `_shared/ctx.ts` idiom).
2. Party gate before state gate (CLAUDE.md law): caller must be the booking's owner.
3. **Verify with Toss server-side** — `POST /v1/payments/confirm` with `paymentKey`, `orderId`,
   `amount`, authenticated by the secret key. The client's word is never evidence.
4. **Amount check against server truth**: Toss's confirmed amount must equal `bookings.total_price`.
   Mismatch ⇒ refuse and do not transition. (`payments.md` names this: 클라 금액 불신 원칙.)
5. **CAS the transition** exactly as `payment_ok` does (`transition-booking:42-46`):
   `.eq('status','payment_hold')`, and on 0 rows return the honest sentence VIA the §2-7
   auto-cancel (the money must be released before the sentence is spoken). The 30-minute
   `e_hold` cron (`0060:121`) is unchanged and still governs.
5b. **Post-confirm side effects move SERVER-SIDE (outside-voice X3, completes wave-2
   C3/C4):** confirm-payment accepts `meta { preferred_runner_id?, recurring? }` and, after
   a successful CAS, performs runner nomination and recurring-series creation server-side —
   **non-fatally** (their failure never fails the payment; failures notify, matching the
   current Alert semantics). `pay.tsx`'s `postConfirm` (pay.tsx:108) shrinks to display
   logic. An app killed after capture can no longer silently lose a paying user's chosen
   runner or weekly repeat.
6. Idempotency: a repeat call with the same `paymentKey` must be a no-op success, not a second
   charge and not a false 409. Copy `payment_attempts`' unique-index idiom (`0041:28`).
7. **Payment INTENT + compensation state machine (eng review A1, upgraded by outside-voice
   X1, 2026-08-12).** The money moves at Toss confirm but the transition happens later, the
   30-min e_hold clock keeps ticking inside the widget, and a crash between capture and our
   INSERT must never leave money without a local trace. Therefore:
   - **The server creates the intent BEFORE money can move.** A new small migration
     (`0076`-class) widens 0071's status check to include `'pending'` and adds
     `profiles.toss_customer_key uuid` (random, never the profile id — Toss FAQ). Before
     the widget opens, the server inserts a `payments` row: `status='pending'`,
     `booking_id`, `amount = total_price`, **server-minted `order_id`**. The intent binds
     owner + booking + amount before Toss ever hears about it.
   - **confirm-payment completes the intent, never invents one:** look up the pending row
     by `order_id` (party gate via its booking), check an existing confirmed row for
     idempotent no-op FIRST, then Toss confirm, then UPDATE the row to `confirmed`
     (recording `payment_key`), then CAS.
   - **ANY post-capture failure auto-cancels in the same request:** CAS 0 rows (hold
     expired) / confirmed amount ≠ intent amount / non-DONE status → Toss 취소 API for the
     full amount, row → `canceled`, honest copy: "결제 시간이 만료됐어요 — **결제는 자동
     취소됐어요.** 예약을 다시 만들어주세요."
   - **If the auto-cancel itself fails:** retry once; then leave the row `confirmed` with a
     `raw` marker AND insert a notifications row to ops (Sean). **The consumer is a pinned
     reconciliation query** (suite pin: confirmed payments whose booking is not in a paid
     state, plus pendings older than 1h) — reviewed as part of pilot ops, not a marker
     nobody reads.
   - **Stale-pending sweep:** pendings older than 1 hour are closed `failed` by the
     existing sweep machinery pattern (0060 idiom) — a crash mid-widget leaves a pending
     row that reconciles itself.
   - **Two windows differ ON PURPOSE (outside-voice #2, verified and kept):** the 5-min
     `slot_hold` (checkout exclusivity, `create-booking-hold:92`) and the 30-min
     `payment_hold` expiry are different clocks by design — `matching` is runner-search,
     not a reserved slot; the pay screen already prints the honest reopen copy and
     `runner_accept`'s overlap guard blocks double-contracts. Do not "align" them.
8. **Payment methods: INSTANT-CONFIRM ONLY for the pilot (eng review A2).** The widget is
   configured to offer 카드 + 간편결제 (카카오페이/네이버페이/토스페이) only — NO 가상계좌
   or other async-deposit methods. **Mechanism (SDK spike finding): the V1 결제위젯 takes
   no method list as a client parameter — the restriction is a 개발자센터 setting per
   `variantKey`. Sean sets it in the dashboard; the client method-check and the server's
   non-DONE guard are defense in depth, not the control.** Rationale: async methods finalize via webhook hours
   later while the 30-min e_hold expires; this slice has no webhook endpoint, so the
   WAITING_FOR_DEPOSIT state must be unreachable by construction. Defense in depth:
   confirm-payment treats any confirm response whose status is not DONE as a post-capture
   failure → the §2-7 auto-cancel machine. **A signed webhook endpoint (with replay
   defense + its own adversarial cycle) is the recorded prerequisite for ever enabling
   async methods.**

### Migration ~~`0067_payments.sql`~~ **`0071_payments.sql` — SHIPPED 2026-08-11** (0067 was taken by the incident subject gate)
`payments` (booking_id, provider, payment_key unique, order_id, amount, status, raw jsonb,
created_at). This closes review finding **R7**: today `ledger_items` records only runner *payout*,
so there is **no accounting artifact for money coming in at all** — no revenue record, no tax
record, no refund handle. That gap predates this plan and is the one thing here that genuinely
needs a migration.

RLS: enabled, owner-read-own only, no client write. ⚠ **Do NOT add it to the sealed-table array
in `68_adversarial_suite.sql:8`** — that pin asserts **policy count = 0**, and this table
deliberately carries one so an owner can read their own receipt. Adding it there fails the harness
for the wrong reason. `109_payments_suite.sql` pins the stricter shape instead: exactly one policy,
SELECT-only, every client write refused including the owner's own. No definer functions were needed.

**As shipped:** `refunded_amount` (with a `<= amount` check) is present so the refund handle R7 asks
for exists on day one, but nothing writes it — the refund path keeps its own adversarial cycle
(§5-4). The runner is deliberately not a reader: their money view is `ledger_items`, and `raw`
carries the payer's own card metadata. Pins P1-P6; P4/P5 mutation-proven, P1/P2/P3 shown to cascade
correctly (a `using(true)` policy leaks to anon too). Harness 324 → 330/0.

### Cancel/refund
`cancel_owner` already computes the fee via `marketplace_cancel_fee` (0066). Wire the refund side
to Toss's 취소 API for the `refund = total_price - fee` amount, AND wire matching-expiry
(`e_match`, 0060) to a full auto-refund — its shipped copy "전액 환불 처리돼요" becomes a live
promise the moment charges are real. **This is a money path ⇒ its own adversarial cycle and its
own pins.** Do not bundle it with the charge path's cycle — but per §5-4 it IS part of the
go-live gate: no real charge before both refund paths are wired.

## 3. Client

`app/app/owner/pay.tsx` — the file already owns a real failure machine; this replaces its
mechanism, not its architecture.
- **SDK strategy (eng review A3): time-boxed spike, named fallback.** The RN widget SDK is
  a legacy V1 line (Toss's V2 is JS-only) with community reports of install 404s and
  native module failures (RNCTPWebViewModule, Android build errors). One-session spike of
  `@tosspayments/widget-sdk-react-native` against Toss TEST keys — runnable NOW, before
  the contract. If it fights back, switch to the fallback without debugging further:
  **WebView + V2 JS widget**, whose one sharp edge is 카드사/ISP app-scheme redirects —
  whitelist schemes in `onShouldStartLoadWithRequest` (kb-acp, ispmobile, hdcardappcardansimclick
  등 — enumerate at build from Toss's scheme list). Either path ⇒ **native rebuild**
  (`expo prebuild` + the UTF-8 locale law, handoff §⑪). **Fallback full spec (outside-voice
  #9 — priced so the A3 spike compares honestly):** iOS `LSApplicationQueriesSchemes` +
  Android `<queries>` entries for the 카드사/간편결제 app schemes; success/fail redirect
  URLs are app deep links whose params are VALIDATED server-side (the client's word is
  never evidence — confirmation still flows through §2's intent lookup); resume recovery =
  re-entering pay.tsx with a pending intent shows retry, never a blank screen. None of
  these exist in app.json today.
- **Delete `pay.tsx:334`'s free 예약 확정하기 button** and `api.ts:230`'s `payment_ok` call. Leaving
  a button that grants a paid state for free once real money exists is the worst dead-button case
  in the app.
- **Delete `pay.tsx:299-302`'s "파일럿 기간이라 실결제는 발생하지 않았어요."** It becomes false the
  day this ships, on the screen of every person who actually paid.
- Retire the `mock_pending` phase and its `MOCK · 준비 중` kicker (`pay.tsx:27`).
- `payphase.ts:15/41`, `pay.tsx:24` `CHIP`, `pay.tsx:37` `HEAD` are exhaustive `Record`s — tsc
  will force these edits. Good. `api.ts:333` `STATUS_MAP` is `Record<string,…>` and will **not** —
  it needs no change here (no new status) but the asymmetry is worth remembering.
- 전자상거래법: the payment screen must carry **사업자 정보 + 통신판매업 신고번호**. Add once the
  numbers exist; this is a legal requirement of the screen, not decoration.
- `dev/pay-lab.tsx` gains the new phases — the only place these states are reviewable.

## 4. Pins — extend `109_payments_suite.sql` (106 is the incident suite — stale name fixed at eng review; wire additions into `harness.sh`, or they are a silent zero)

The charge path is mostly edge-function logic, which the SQL harness cannot reach — the same
limitation `0066 §2` names ("a money constant that lives solely in a Deno function is a money
constant no pin can protect"). **Test rail (eng review T1): BOTH of the following.**

1. **Deno unit tests with a mocked Toss API** — the repo's first edge-fn test infra
   (pays forward to settle-run). Every §2-7 branch gets an automated test: happy
   confirm→insert→CAS; anon 401 / non-owner 403; amount mismatch → auto-cancel; CAS
   0-rows → auto-cancel + honest copy; idempotent re-call (same paymentKey) → no-op
   success; non-DONE confirm status → auto-cancel; auto-cancel failure → retry once →
   `needs_manual_cancel` marker row. Mock drift risk accepted and noted.
2. **Sandbox test matrix** (Toss TEST keys, executed through `dev/pay-lab.tsx` + the real
   widget): the pre-deletion E2E gate. The pay.tsx:334 deletion removes the ONLY path
   into `matching` (REGRESSION class) — the new path must pass this matrix in sandbox
   BEFORE step 3's deletions land. Matrix rows: full pay happy path per enabled method,
   double-tap pay, app-killed-mid-widget → reopen → retry, slow-confirm (10s+) UI,
   hold-expires-while-widget-open → auto-cancel copy shown.

Pin what SQL can hold:
- `payments` is sealed from anon and from an authenticated non-owner (INSERT/UPDATE/DELETE too,
  not just SELECT — the review showed a read-only assertion passes while writes stay open).
- `payment_key` unique index rejects a duplicate confirm.
- `payment_hold → matching` still legal; the surrounding map is undamaged (the `105 E7` idiom).
- The 30-minute `e_hold` expiry is unchanged and still silent (`100 W7`).

## 5. Sequencing

1. ~~**Now, unblocked:** the `payments` table + RLS + pins. Nothing else.~~ **DONE 2026-08-11**
   (`0071` + `109`).
1b. **BUILDABLE NOW, before the contract (eng review #11 — TEST keys don't need filings):**
   the intent migration (+ pins), `confirm-payment` with Deno unit tests (mocked Toss),
   the A3 SDK spike against TEST keys, client wiring behind the existing phases, the
   sandbox matrix dry run, and the refund path's build. **The filing wait is build time,
   not idle time.**
2. **On contract (live keys):** live-key secrets, 사업자 정보 + 통신판매업 신고번호 copy,
   sandbox matrix re-run against live-mode test amounts per Toss guidance.
3. **Only once `confirm-payment` is live and verified:** the pay.tsx deletions in §3.
4. **Refund/cancel path is part of the GO-LIVE GATE (outside-voice X2), not an afterthought:**
   built as its own adversarial cycle (reusing §2-7's Toss cancel call), and **no real
   charge happens before matching-expiry auto-refund + `cancel_owner` refund are wired** —
   0060's e_match copy already promises "전액 환불 처리돼요" and the moment money is real,
   an unwired refund makes that shipped sentence a lie.

> ⚠ **Correction to an earlier draft of this file, which said the pay.tsx deletions could land
> immediately. They cannot, and doing so would brick the app.**
> `pay.tsx:334` → `api.ts:230` `payment_ok` is **the only path a booking has into `matching`
> today**. Deleting it before `confirm-payment` exists means no booking can ever be confirmed.
> And `pay.tsx:299`'s "파일럿 기간이라 실결제는 발생하지 않았어요" is **currently true** — it only
> becomes a lie the day real charges start. Both are correct *today* and become wrong at the
> same instant: the moment `confirm-payment` goes live. They are step 3, not step 1.
> The honesty law cuts both ways — removing an accurate statement is not a fix.

## 6. Carried over from the bridge review — still unsolved

- **R5** — the PMF metric. Real payment friction is the honest version of this, so the bridge's
  24h dead-zone objection dies with it. No action.
- **R7** — solved by §2's `payments` table.
- **R6** — club delegation (`session_pay_delegation`) is a separate, still-simulated money path
  that bypasses `payment_hold` entirely. **Explicitly out of scope**; say so rather than let the
  next reader assume coverage.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | ISSUES_OPEN | mode: HOLD_SCOPE, 2 critical gaps (token-track parking gates — not this slice) |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | **CLEAN** | 9 issues, 0 critical gaps — ALL folded into this plan |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

Eng review 2026-08-12 (session with /office-hours → /plan-ceo-review → this): findings A1
(payment intent + post-capture auto-cancel machine, §2-7), A2 (instant-confirm methods only,
§2-8), A3 (SDK spike + priced WebView fallback, §3), T1 (Deno tests + sandbox matrix, §4);
outside voice (codex, 11 findings): X1 intent design absorbed into §2-7, X2 refunds join the
go-live gate (§5-4), X3 postConfirm server-side (§2-5b), X4 text batch (§4 header 106→109,
§5-1b buildable-now, reconciliation pin, fallback spec, two-windows note); codex #1 REJECTED
(read the superseded km doc — the ACTIVE-track banner above now prevents that), #2 REJECTED
as designed behavior (5-min slot hold vs 30-min payment window, noted in §2-7).

CROSS-MODEL: Claude review + codex converged on the post-capture money-safety class (A1 ↔
codex #3/#4); codex's intent framing was adopted over the review's write-ordering fix.

VERDICT: ENG CLEARED — plan locked; §5-1b work is buildable now with TEST keys. Test plan
artifact: `~/.gstack/projects/seankookim-daengrun/sean-claude-token-payments-model-891c11-eng-review-test-plan-20260812-154500.md`.

**UNRESOLVED DECISIONS:**
- + 5 unresolved from prior reviews (the CEO review's token-track parking gates G1–G4 + runner tier fate — they block TOKEN code, not this Toss slice)
