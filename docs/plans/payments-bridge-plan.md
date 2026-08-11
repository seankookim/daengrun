<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260811-133205.md -->
# Plan — pilot payments bridge (`awaiting_transfer`)

Branch `redesign-v4`. Written 2026-08-11. Status: **DRAFT, pre-review**.

Sean's decisions this session (settled — do not re-litigate):
1. Full payments sprint now, not a day-sized script.
2. The manual bank-transfer bridge gets its **own booking status `awaiting_transfer`**,
   invisible to the 30-minute `payment_hold` expiry, with its own ~24h window.

## 0. Why this exists

`payment_ok` is a simulation: `create-booking-hold` fixes the server price, the client calls
`transition-booking` with `action: 'payment_ok'`, and the booking moves `payment_hold → matching`
with **no money involved**. The PG track (토스페이먼츠, `docs/payments.md`) is blocked on
사업자등록 + 1–2 week review. The bridge takes real money from the pilot's first owners by bank
transfer while that clears.

**Two verified facts that shape the whole design:**

- `transition-booking/index.ts:28` — `payment_ok` throws `403 "owner only"`. An operator cannot
  flip another person's booking through the edge function. There is **no admin/operator role
  anywhere in the schema**.
- `0060_wave3_server_honesty.sql:121` — a cron expires any `payment_hold` older than **30 minutes**.
  A bank transfer (see account → open bank app → send → operator checks → operator confirms) is an
  hours-long loop. Every manual transfer would be expired out from under the owner. This is why the
  new status exists rather than a widened hold.

## 1. Contracts

### C1 — `awaiting_transfer` is a *pre-payment* state, exactly like `payment_hold`
No money has been captured. Nothing is refundable from it. Every message the system emits about
this state must be true under "we have not received anything yet."

### C2 — the operator is the only party who can assert receipt
An owner claiming "I sent it" is not evidence. Only a human who looked at the bank statement moves
the booking forward. There is no client-callable path into `matching` from `awaiting_transfer`.

### C3 — the amount is server truth
Reconciliation compares the received amount to `bookings.total_price`. The client never supplies
an amount. A mismatch is an operator decision, not an automatic pass.

### C4 — additive to the PG track
`payment_hold → matching` (the future `confirm-payment` path) is untouched. `awaiting_transfer` is
a parallel branch off `payment_hold`. When Toss lands, the bridge is deleted by removing one
transition and one client branch; no PG code has to route around it.

### C5 — expiry is silent, like `e_hold`
`0060` deliberately gives `e_hold` **no notification** because "결제된 적이 없는 홀드에 환불은
거짓말이다" (pin 100 W7 enforces that silence). `awaiting_transfer` expiry inherits the rule for
the same reason. **But see R1 — this is the plan's sharpest open risk.**

## 2. Migration `0067_awaiting_transfer.sql`

### §1 transition-map delta (`enforce_booking_transition`, base = 0066)

```
when 'payment_hold'      then new.status in ('matching','expired','refund_pending','awaiting_transfer')
when 'awaiting_transfer' then new.status in ('matching','expired','refund_pending','cancelled_owner')
```

Rationale per edge:
- `payment_hold → awaiting_transfer` — owner picks bank transfer on pay.tsx.
- `awaiting_transfer → matching` — operator confirmed receipt. The only forward edge.
- `awaiting_transfer → expired` — 24h window passed, nothing arrived.
- `awaiting_transfer → refund_pending` — money arrived but the booking must be voided
  (duplicate transfer, owner changed mind after sending, wrong amount the operator won't accept).
  Without this edge, a real transfer that must be returned has nowhere to go.
- `awaiting_transfer → cancelled_owner` — owner backs out before sending. Fee must be **0**.

`awaiting_transfer` is deliberately **not** reachable from `quoted` — the price must be fixed by
`create-booking-hold` first, so the owner is always told an exact amount to send.

### §2 fee ladder (`marketplace_cancel_fee`, from 0066)
Add an `awaiting_transfer` tier returning **0**. Nothing was captured; any nonzero fee would be a
charge against money we never received.

### §3 expiry (`expire_unmatched_bookings`, from 0060)
Add a **third sibling CTE** `e_transfer`:
```sql
), e_transfer as (
  update bookings set status = 'expired'
  where status = 'awaiting_transfer'
    and transfer_requested_at < now() - interval '24 hours'
    and club_session_id is null
  returning id
)
```
**The three-sibling structure is a contract** (0060's own comment): merging the UPDATEs makes the
classes indistinguishable under PG16 `RETURNING`, and the `noti` CTE would then send
"전액 환불 처리돼요" to owners who were never charged. Predicates stay disjoint.

New column `bookings.transfer_requested_at timestamptz` — the 24h clock must start when the owner
was *shown the account*, not at `created_at` (the booking may have sat in `payment_hold` first).

### §4 audit
New table `transfer_confirmations` (booking_id, confirmed_by, amount_received, note, created_at).
The operator's assertion is a record, not a status side effect. RLS: no client access at all;
service-role only.

## 3. Operator path

**Decision: a service-role ops script, not an edge-function admin action.**
No operator role exists in the schema, and inventing an auth tier for a 5-owner pilot is the more
expensive and more dangerous option (a mis-scoped admin gate on a money path is a worse failure
than a script only Sean can run).

`scripts/payments-ops.mjs`, modeled on the existing `scripts/runner-ops.mjs`:
- `list` — every `awaiting_transfer` booking with owner name, amount, hours remaining.
- `confirm <booking_id> --amount <krw>` — writes `transfer_confirmations`, then moves the booking to
  `matching`. **Refuses** when `amount ≠ total_price` unless `--force-amount` with a required
  `--note`. Dry-run by default; `--yes` to write (the `geocode-backfill.mjs` precedent).
- `void <booking_id> --reason` — `awaiting_transfer → refund_pending` for money that must go back.

The `bookings` UPDATE still passes through `enforce_booking_transition`, so the script cannot make
an illegal move even with service-role.

## 4. Client states (`owner/pay.tsx`)

pay.tsx already owns a real failure machine (stale charge under a loud-fail strip, verbatim server
errors, phase-re-deriving retry). This adds one branch, it does not rewrite the screen.

| State | What the owner sees |
|---|---|
| choose | Two doors: 카드 결제 (disabled, honest "준비 중" — it genuinely is) and 계좌이체. |
| awaiting_transfer | Account number, **exact** amount, deadline timestamp, and one true sentence: 입금이 확인되면 매칭이 시작돼요. Copy-to-clipboard on the account. |
| expired | Names the real cause (24h passed, nothing received) and offers re-request. |

Honesty constraints, from DESIGN.md §7:
- The screen may **never** say 결제 완료 — it says 입금 확인 대기. We do not know money moved.
- No "확인 중..." spinner implying the system is watching a bank feed. It is not. A human checks.
- The deadline is rendered from `transfer_requested_at + 24h`, never a hardcoded string.
- No dead buttons: there is no client action that advances this state, so none is drawn.

Design law: paper world, §3b component spec (17/800 primary, 16/800 secondary, radius 0, busy =
label swap). Amounts in Oswald with explicit `lineHeight` (BUG A).

## 5. Harness pins — `supabase/tests/106_awaiting_transfer_suite.sql`

Each pin documents the single revert that makes it red (0059 doctrine).

| Pin | Asserts | Red under |
|---|---|---|
| T1 | `payment_hold → awaiting_transfer` is legal | removing the map edge |
| T2 | `awaiting_transfer → matching` is legal | removing the map edge |
| T3 | `awaiting_transfer → picked_up` / `→ active` / `→ completed` **raise** | widening the map |
| T4 | `marketplace_cancel_fee('awaiting_transfer', …)` returns exactly **0** | any nonzero tier |
| T5 | the 24h cron expires a 25h-old row and **leaves a 23h-old row alone** | changing the interval |
| T6 | expiry emits **no** notification for `e_transfer` (extends 100 W7) | adding it to the `noti` CTE |
| T7 | `e_transfer` does not touch `payment_hold` or `matching` rows (disjoint predicates) | merging the CTEs |
| T8 | `transfer_confirmations` is unreadable by anon and by an authenticated non-owner | dropping the revoke |

T4 and T6 are the money/honesty pins and must be mutation-proven (go red under one named revert,
demonstrated, not asserted).

## 6. Adversarial review targets

Reviewers must **execute** these, not reason about them:
1. **Double-spend the transfer** — owner opens two bookings, sends one payment, operator confirms
   both. What stops it? (Today: nothing. Needs an answer.)
2. **Expire-after-send race** — transfer lands at hour 23:58, cron fires at 24:00, operator confirms
   at 24:05. The booking is `expired`; is `expired → matching` legal? (It is not.) The owner has
   paid and has no booking. **This is the highest-severity path in the plan.**
3. **Amount mismatch** — owner sends 24,000 on a 24,900 booking. Does the script's refusal actually
   hold, and is the owner told anything?
4. **Slot theft** — the runner's slot is not held during `awaiting_transfer`. After 24h of waiting,
   confirmation drops the owner into `matching` for a time that may be gone.
5. **Service-role blast radius** — can `payments-ops.mjs` be made to move a booking it was not
   pointed at (arg parsing, missing `--yes` guard)?
6. **Anon reach** — `transfer_confirmations` and `transfer_requested_at` under anon and a foreign
   authenticated user.

## 7. Open risks (flagged, not solved)

- **R1 — the silent expiry is the plan's weakest joint.** `e_hold`'s silence is correct because
  nobody was ever asked for money. An `awaiting_transfer` owner **was handed an account number**.
  Expiring them silently is defensible only if no money arrived, and we cannot know that from the
  database. Candidate fix: expiry notifies with copy that assumes nothing
  ("입금이 확인되지 않아 예약이 만료됐어요 — 이미 보내셨다면 문의해주세요"). This contradicts C5 and
  needs a ruling.
- **R2 — R2 (expire-after-send) has no automatic remedy.** Options: widen the window to 48h,
  have the cron skip rows with a pending operator note, or accept manual recovery via a new booking.
- **R3 — legal.** Taking money by personal bank transfer has 전자상거래법 / tax implications the
  launch-checklist has not cleared. `docs/legal/*` says nothing about it. Counsel item, and it
  gates *shipping* the bridge, not building it.
- **R4 — slot integrity** (see adversarial #4). The pilot may accept it; it should be a decision.

## 8. Effort

Human ~3–4 days / CC ~2 sessions. Migration + pins is one session with the adversarial cycle;
ops script + pay.tsx branch is the second.
