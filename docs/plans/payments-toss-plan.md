# Plan — real payments via 토스페이먼츠

Branch `redesign-v4`. Written 2026-08-11. Supersedes `payments-bridge-plan.md`.
Status: **SCOPE — blocked on Sean's filings, buildable in parallel.**

Sean's decision (2026-08-11): **register (사업자등록) rather than route around it.** That deletes
the manual bank-transfer bridge and puts us on the real PG track.

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
   `.eq('status','payment_hold')`, and on 0 rows return the existing honest sentence
   `"결제 시간이 만료됐어요 — 예약을 다시 만들어주세요"`. The 30-minute `e_hold` cron
   (`0060:121`) is unchanged and still governs.
6. Idempotency: a repeat call with the same `paymentKey` must be a no-op success, not a second
   charge and not a false 409. Copy `payment_attempts`' unique-index idiom (`0041:28`).

### Migration `0067_payments.sql` — one table, no transition changes
`payments` (booking_id, provider, payment_key unique, order_id, amount, status, raw jsonb,
created_at). This closes review finding **R7**: today `ledger_items` records only runner *payout*,
so there is **no accounting artifact for money coming in at all** — no revenue record, no tax
record, no refund handle. That gap predates this plan and is the one thing here that genuinely
needs a migration.

RLS: enabled, owner-read-own only, no client write. Add to the sealed-table array in
`68_adversarial_suite.sql:8`. Definer functions (if any) carry `set search_path = public, pg_temp`
**in the body**.

### Cancel/refund
`cancel_owner` already computes the fee via `marketplace_cancel_fee` (0066). Wire the refund side
to Toss's 취소 API for the `refund = total_price - fee` amount. **This is a money path ⇒ its own
adversarial cycle and its own pins.** Do not bundle it with the charge path.

## 3. Client

`app/app/owner/pay.tsx` — the file already owns a real failure machine; this replaces its
mechanism, not its architecture.
- Install `@tosspayments/widget-sdk-react-native` ⇒ **native rebuild** (`expo prebuild` + the
  UTF-8 locale law, handoff §⑪).
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

## 4. Pins — `106_payments_suite.sql` (wire into `harness.sh`, or it is a silent zero)

The charge path is mostly edge-function logic, which the SQL harness cannot reach — the same
limitation `0066 §2` names ("a money constant that lives solely in a Deno function is a money
constant no pin can protect"). Pin what SQL can hold:
- `payments` is sealed from anon and from an authenticated non-owner (INSERT/UPDATE/DELETE too,
  not just SELECT — the review showed a read-only assertion passes while writes stay open).
- `payment_key` unique index rejects a duplicate confirm.
- `payment_hold → matching` still legal; the surrounding map is undamaged (the `105 E7` idiom).
- The 30-minute `e_hold` expiry is unchanged and still silent (`100 W7`).

## 5. Sequencing

1. **Now, unblocked:** the `payments` table + RLS + pins. Nothing else.
2. **On contract:** `confirm-payment`, widget SDK, native rebuild, 사업자 정보 copy.
3. **Only once `confirm-payment` is live and verified:** the pay.tsx deletions in §3.
4. **After the charge path is verified:** the refund/cancel path, as its own cycle.

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
