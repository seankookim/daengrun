<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260811-133205.md -->
# Plan — pilot payments bridge (`awaiting_transfer`)

Branch `redesign-v4`. Written 2026-08-11, **revised after /autoplan review**.
Status: **PAUSED at Sean's direction (2026-08-11), pending D-A. Not approved, not implemented.**

> **BUILD IS BLOCKED ON D-A.** Sean's ruling at the /autoplan gate: resolve the registration fork
> with counsel **before** any code is written. If the answer is "register anyway," delete this plan
> and scope the Toss integration instead. Do not start the sprint until D-A is answered.
>
> **D-C (settled at the same gate):** if the bridge does proceed, **매주 반복 and runner nomination
> are disabled when 계좌이체 is chosen** — the affordances grey out rather than persisting the
> intent server-side (see R4). Simplest honest fix; revisit only if the pilot demands it.

Sean's decisions this session (settled — do not re-litigate):
1. Full payments sprint now, not a day-sized script.
2. The manual bank-transfer bridge gets its **own booking status `awaiting_transfer`**,
   invisible to the 30-minute `payment_hold` expiry, with its own ~24h window.

Review: 3 independent voices (CEO / design / eng). Codex unavailable (binary not installed)
so this ran `[subagent-only]`. Every finding cited below was **independently re-verified against
the code by the lead** — the agents' claims were not taken on trust.

---

## 0.5 OPEN DECISIONS — these gate the build

### D-A. The registration fork (raised by the CEO voice; **this may delete the whole plan**)
The bridge exists only to avoid 사업자등록. That is a same-day, free 홈택스 filing, and the PG
review it unblocks is 1–2 weeks (`docs/payments.md:8`) — so **the bridge's entire useful life is
~2–3 weeks**, covering an estimated 10–40 transactions.

The reason for avoiding it is 예비창업패키지 2027 (~₩40M, requires no 사업자등록).
`docs/marketing-fundraising.md:128` names an alternative the plan never considered: incorporate
now and target 초창패/청창사 (both accept ≤3yr corps). `docs/sean-commands.md:200` still lists this
fork as **open**, not settled.

The sharper form of the argument: collecting pilot revenue as an unregistered individual is
무등록 사업, which may itself contest the 예비창업자 status the bridge was built to protect. **The
bridge could destroy the thing it exists to preserve.**

→ **Not my call.** One 세무사/변호사 conversation resolves it. If the answer is "register anyway,"
this plan is deleted and we go straight to Toss.

### D-B. Legal is a BUILD gate, not the ship gate I filed it as
The v1 plan put legal in §7 open risks. Three specifics move it forward:
- 전자상거래법 requires 사업자 정보 / 통신판매업 신고번호 **on the payment screen**. §4 builds that
  screen. Shipping it without those is the violation.
- Taking the full fare and settling to runners is 대금 정산 대행, near 전자금융거래법's
  전자지급결제대행업 line. This is what PGs exist to absorb.
- No 현금영수증 is possible. The first five paying customers get no receipt.

→ Get the opinion **before** the sprint. If counsel says no, four days are saved.

---

## 1. Why this exists

`payment_ok` is a simulation. Two verified facts shape the design:
- `transition-booking/index.ts:28` — `payment_ok` is `403 "owner only"`; no admin role exists anywhere.
- `0060_wave3_server_honesty.sql:121` — a cron expires `payment_hold` after **30 minutes**, far
  shorter than a bank-transfer loop. Hence a new status, not a widened hold.

## 2. Contracts

- **C1** — `awaiting_transfer` is a *pre-payment* state. No money captured, nothing refundable.
  Every message emitted must be true under "we have received nothing."
- **C2** — only the operator can assert receipt. The real enforcement is **`0058_security_hardening_2.sql:263`
  `_guard_booking_cols`** (deny-all on `bookings` for `authenticated`/`anon`), not the
  `payment_ok` owner-gate the v1 plan wrongly cited.
- **C3** — the amount is server truth, reconciled by **deposit code** (§5), not by amount alone.
- **C4** — additive to the PG track. **Corrected:** the bridge's *behavior* is removable; its
  **schema footprint is permanent** — Postgres cannot drop an enum value. `awaiting_transfer`,
  `transfer_requested_at`, and `transfer_confirmations` outlive the bridge forever.
- **C5 — REVISED.** `0060:97`'s silence law is "결제된 적이 없는 홀드에 **환불은** 거짓말이다" — the
  banned thing is a false *refund* claim, not speech. An `awaiting_transfer` owner was handed an
  account number; silence there is abandonment. **All three voices independently ruled: notify.**
  `e_transfer` gets its own `noti` sibling with assumption-free copy.

## 3. Migrations — TWO files, and the harness cannot tell you why

`bookings.status` is a **Postgres enum** (`0001_init.sql:9-14`), not a CHECK. **Zero migrations in
this repo have ever added an enum value** — no precedent to copy.

> **The gate lies here.** `supabase/tests/harness.sh` runs `psql -f` per suite with **no
> `--single-transaction`** (verified: zero occurrences) — statement-level autocommit. `supabase db
> push` applies each migration file **inside a transaction**. `ALTER TYPE … ADD VALUE` followed by
> same-transaction *use* of the value raises `unsafe use of new value of enum type`. So a
> single-file migration would go **green on the harness and fail on push**. `marketplace_cancel_fee`
> is `language sql` (`0066:73`) → its body is parsed at CREATE → it is exactly the failing shape.
> `enforce_booking_transition` is plpgsql (`0066:37`) → would survive. The split is **mandatory,
> not stylistic**, and no gate we own will catch a regression.

**`0067_awaiting_transfer_enum.sql`** — one statement:
```sql
alter type booking_status add value if not exists 'awaiting_transfer' after 'payment_hold';
```

**`0068_awaiting_transfer.sql`** — everything else:

**§1 transition map** (base 0066):
```
when 'payment_hold'      then new.status in ('matching','expired','refund_pending','awaiting_transfer')
when 'awaiting_transfer' then new.status in ('matching','expired','refund_pending')
```
`→ cancelled_owner` is **dropped** (was in v1). `cancel_owner` (`transition-booking:307-341`) has
**no status gate** — it quotes the fee and returns `{refund: total_price - fee}`, which
`schedule.tsx:544,552` renders as **"취소하고 24,900원 환불받기"** and "결제 실연동 후엔 3일 내 환불
처리돼요" — promising a bank refund of money never received. Direct C1 violation. `payment_hold`
has no cancel edge for this exact reason; the 24h expiry is the exit.

**§2 fee ladder** — the `awaiting_transfer` arm must be the **first** `when`. Appended after the
24h arm, a nominated booking starting in <24h is charged 10% of money never received.

**§3 expiry** — third sibling CTE, `coalesce(transfer_requested_at, created_at)` (a NULL column
makes the row immortal — the ghost class `0060:90` exists to kill), its own `noti` sibling per C5,
and `+ (select count(*) from e_transfer)` added to the return count (`0060:125`).

**§4 audit** — `transfer_confirmations` with an **idempotency key + unique index**, copying
`payment_attempts_idem_uni` (`0041:28`). RLS enabled, zero policies, and **added to the sealed-table
array in `68_adversarial_suite.sql:8`** or nothing pins it in perpetuity.

**§5 column** — `bookings.transfer_requested_at`, plus the deposit code (§5 below).

**Definer law:** `set search_path = public, pg_temp` re-typed **in the body** of every replaced
function — `create or replace` resets it (`0060:9`). Note 98 H1 only inspects `prosecdef`, so
`marketplace_cancel_fee`'s header (`stable`, not definer) is **unpinned** — copy it byte-for-byte.

## 4. Update sites OUTSIDE the migration — the v1 plan's worst omission

v1 said "this adds one branch, it does not rewrite the screen." That was wrong.
`awaiting_transfer` is a *booking status*, so every surface reading `bookings.status` inherits it.

| Site | What breaks today |
|---|---|
| `api.ts:3139` | not in the `.not(status in …)` exclusion → unpaid booking appears in 내 일정 |
| `api.ts:333` `STATUS_MAP` | no key → `?? 'pending'`. **The file's own comment says this produces "'러너 응답 대기' 배지 + 죽은 러너 변경 버튼"** — the codebase already learned this for `refund_pending`. `Record<string,…>` gives no tsc gate. |
| `home.tsx:487,522` | `fnSearching` true → GO disc turns periwinkle, reads 매칭 중, and **breathes** — animating a runner search while holding none of the owner's money (§6 violation) |
| `schedule.tsx:30,79` | 러너 응답 대기 badge; tap pops `Alert('매칭 중','러너를 찾고 있어요')` and returns before the sheet |
| `pay.tsx:299` | after a **real** confirmed transfer, tells that owner "파일럿 기간이라 실결제는 발생하지 않았어요" |
| `pay.tsx:334` | the free 예약 확정하기 button still walks `payment_hold → matching` — must be retired |
| `payphase.ts:15,41` / `pay.tsx:24,37` | tsc-gated `Record`s — will force edits (good), but unknown-status runtime fallback → `결제 정보를 찾을 수 없어요` on an old client build |
| `create-booking-hold:36` `LIVE` | `awaiting_transfer` absent → same dog, same slot, two live bookings, two runners (24h window with **no slot hold** — `create-booking-hold:92` is **5 minutes**) |
| `0026:104` + 4 more SQL clash guards | same hole, recurring-cron side |
| `harness.sh` | new suite needs its own `psql -f` line or it is a **silent zero** |
| `dev/pay-lab.tsx:20` | the only place these states are reviewable |

## 5. Deposit identifier — all three voices flagged this independently

Without it the operator **cannot attribute a deposit to a booking**: the bank statement shows an
amount and a 입금자명 (often a spouse's name). Two 24,900 bookings the same day are
indistinguishable. This is the mechanism behind adversarial #1 and #3.

Per-booking deposit code rendered as the required 입금자명 (e.g. `홍길동-4F2A`), stored on the row,
reconciled on exactly. Belt: partial unique index — one open transfer per owner.

## 6. Server write path (absent from v1 entirely)

pay.tsx **cannot** write this status (C2). Required: a new `transition-booking` action
`request_transfer`, with `payment_ok`'s CAS shape verbatim (`transition-booking:42-46`) —
`.eq('status','payment_hold')` — so an owner tapping at minute 31 gets
`"결제 시간이 만료됐어요"`, not a raw trigger exception. Sets `transfer_requested_at` server-side.
Needs a `functions deploy`, which carries the migration-before-deploy ordering constraint.

## 7. Operator path — one revoked definer RPC, not raw writes

v1's raw `insert` + `update` abandons the precedent it claimed to copy: `runner-ops.mjs:14`
states *"There is no raw update statement anywhere in this file, so the script cannot do anything
the state machine would not do."* Raw writes lose atomicity (two REST calls), idempotency
(re-running inserts a second receipt and silently no-ops the status), and **pinnability** — an
`amount ≠ total_price` rule in a `.mjs` is exactly the anti-pattern `0066:14` was written to fix.

`transfer_confirm(p_booking, p_amount, p_operator, p_note, p_force default false)` —
security definer, revoked from public/anon/authenticated, granted to service_role. Inserts the
receipt and CASes `awaiting_transfer → matching` in one statement. Raises `amount_mismatch` and
`not_awaiting`. `scripts/payments-ops.mjs` becomes a keyboard over it, with
`Number.isInteger(amount) && amount > 0` validation (`runner-ops.mjs:71`'s `flag()` silently
swallows the next flag on a missing value).

The confirm path must also **re-check `is_slot_available`** for nominated bookings — 24 hours
have passed and the runner may be double-booked.

## 8. Client states — nine, not three

Beyond choose / awaiting_transfer / expired, each of these has a *wrong default today*:
requesting (failure renders "결제가 완료되지 않았어요" — nothing was attempted) · confirmed-while-open
(`pay.tsx:101` is a one-shot `useEffect` — needs `useFocusEffect` + `AppState`) · returns-days-later
(**`/owner/pay` has no inbound route from 일정/알림/home — the owner may never find the account
number again**) · wrong-amount (no client-visible channel exists; ops script has no notify verb) ·
moved-to-matching-while-away · void→refund_pending (`pay.tsx:313` promises a refund we have no
owner bank account for) · cancel-after-sending · expired-which-kind (`expired` collapses three
causes; `fetchBookingCharge` doesn't even select `transfer_requested_at`).

**There is no moment where we say 받았어요.** `confirm` must insert a `booking` notification —
입금 확인했어요 · 이제 러너를 찾을게요. Cheapest item in this review and it closes the arc.

Honesty corrections: "입금이 확인되면 매칭이 시작돼요" is passive and builds the false model that we
watch a bank feed — every 무통장입금 flow a Korean owner has used confirms in seconds. Name the
human and the window. The screen must also state the negative fact that **the slot is not held**,
and render 은행명 · 계좌번호 · **예금주** (if personal, say why — volunteering it is what earns the
transfer). Deadline = `min(transfer_requested_at + 24h, scheduled_at − lead)`, in **KST** — note
`pay.tsx:76` uses device-local `getHours()` 18 lines below the file's own KST law; do not copy it.
`expo-clipboard` is **not installed** — copy-to-clipboard is a native module + dev-client rebuild.

## 9. Harness pins — `106_awaiting_transfer_suite.sql` (wired into harness.sh)

Corrections to v1's eight: **T4 was green under a broken implementation** — an `awaiting_transfer`
row with `runner_id is null` already returns 0 via the ladder's *first* arm, so deleting the new
tier leaves T4 green. Fixture must set `runner_id` non-null AND `scheduled_at < now() + 24h`.
**T5 likewise** — its fixture sets `transfer_requested_at`, so it is green under the NULL-immortality
bug. Add: NULL-column row still expires · `expired → matching` raises · `→ confirmed` and
`→ runner_pending` raise · `quoted → awaiting_transfer` raises · `transfer_requested_at` is
client-unwritable (the `100 W9/W11` idiom) · the expiry return count · `transfer_confirmations` in
the `68_adversarial_suite:8` sealed array (T8's read-only check passes while INSERT/UPDATE stay open).

## 10. Open risks

- **R2 — pay-then-expire.** `expired → matching` is illegal and should stay so. Remedy is
  operational: surface last-2-hours rows as urgent, or widen to 48h. Must be decided, not deferred.
- **R4 — recurring + nomination silently dropped.** `pay.tsx:108-140` runs `createRecurringSeries`
  and `requestRunner` at confirmation — which now happens hours later in a script that has never
  seen `draft.preferredRunnerId` or `recurring=1` (client memory + route params). Either persist
  the intent server-side or **disable those affordances when 계좌이체 is chosen**.
- **R5 — the bridge contaminates the PMF metric.** A 24h human-gated dead zone sits between
  "I want a run" and "a runner is being found." Whatever M1 rebooking rate the pilot measures is
  measuring a product we will never ship, at n=5.
- **R6 — club delegation** is a separate, still-simulated money path bypassing `payment_hold`
  entirely. In or out of the bridge? Unstated.
- **R7 — no accounting artifact for money coming IN.** `ledger_items` is runner-payout only.
  No revenue record, no tax record, no refund runbook.

## 11. Effort — revised

v1 said 3–4 human days / 2 CC sessions. Actual surface: 2 migrations, 1 definer RPC, 1 edge action
+ deploy, 9 client update sites, deposit-code design, clipboard native module, ~14 pins, harness
wiring. **Closer to 3 CC sessions, one of which is design, not code** — and that is before D-A/D-B.
