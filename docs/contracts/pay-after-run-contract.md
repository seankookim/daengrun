# Contract — pay after the run (server mechanism for Sean's journey ruling #1)

**Status: CONTRACT ONLY. Nothing is built. Nothing is deployed.** Written by a read-only scout
under the overnight grant, decision **O-5** (`docs/decisions/awaiting-sean.md` §0-overnight):
*"contract first, tonight; build only after it is attacked."*

**Scope:** the server half of "payment moves AFTER the run." The client half is a separate,
sequenced item owned by **ui2** (§E.5) and must not start before §E.1–E.2 are deployed.

**Every fact below is cited `file:line` and was measured on 2026‑08‑19/20 against **production,
SELECT-only**, and against the repo. No edge function was invoked. Where a claim is inference
rather than measurement it says so.

⚠ **Two different trees, stated so no citation is ambiguous.** Server cites (`supabase/**`,
migrations, suites) are from this worktree at **`8d33cde`**, which matches origin for those paths.
**Client cites (`app/**`) are re-measured against `origin/redesign-v4` at `cf162b1`** — ui2 landed
`68a4257` (request.tsx rebuild) mid-scout, trunk moved to `58c20c2` (0110), and then `cf162b1`
rebuilt the radar and made the pay screen route onward with `after: 'radar'`. Everything in §A.7
and §E.5 was re-read from origin at `cf162b1`, not from this worktree; the client facts that
**changed during the scout** are flagged inline (`⟳`) rather than silently corrected, because a
reader comparing against an older handoff will otherwise think one of us is wrong.

**Revision 2 (2026‑08‑19 night): this file has been through an adversarial review that executed
its own measurements and returned FIX-CONTRACT-FIRST.** Every finding is applied below and the
findings themselves are listed in **§H — Review log**, together with the two announcer decisions
that closed the forks the reviewer opened. Read §H first if you are comparing this against an
older copy: the two structural changes are that **`payment_ok` is removed in ONE move, not two**
(§C.2), and that **the three non-payment side effects hiding in `pay.tsx` move into
`request.tsx`** (§E.5.1) rather than quietly disappearing with the screen.

---

## A. Measured state

### A.1 The status machine around `payment_hold`

The enum is `0001_init.sql:9-14`. The live transition map is the fourth `create or replace` of
`enforce_booking_transition` — `0066_enroute_cancel.sql:37-63` (earlier: `0001:194`, `0005:4`,
`0047:25`; none later). The rows that matter:

    0066:44   when 'quoted'         then new.status in ('payment_hold','expired')
    0066:45   when 'payment_hold'   then new.status in ('matching','expired','refund_pending')
    0066:46   when 'matching'       then new.status in ('runner_pending','confirmed','expired','refund_pending','cancelled_owner')
    0066:47   when 'runner_pending' then new.status in ('confirmed','matching','expired','cancelled_owner')

**`payment_hold → matching` is the only forward edge out of the hold.** There is no
`payment_hold → runner_pending` — `transition-booking/index.ts:36-41` records that the old
`bk.runner_id ? "runner_pending" : "matching"` branch was **dead code** for exactly that reason.

Client writes to `bookings` are impossible regardless of grants. Production grants
`authenticated` table-level UPDATE on `bookings` including `status` (measured:
`has_column_privilege('authenticated','bookings','status','UPDATE') = true`), but
`_guard_booking_cols` (`0058_security_hardening_2.sql:264-278`, SECURITY **INVOKER** on purpose)
raises `booking_protected_columns` on *any* column change when `current_user in
('authenticated','anon')`. Server paths (`service_role`, definer RPCs) never enter that branch.

### A.2 What `create-booking-hold` writes today — widget vs card

Deployed **v9** (`supabase functions list`, measured), source
`supabase/functions/create-booking-hold/handler.ts`.

Path selection, before any write, at `handler.ts:165-168`:

    const { data: card } = await db.from("billing_keys").select("profile_id").eq("profile_id", uid).maybeSingle();
    const paidPath: "card" | "widget" = card ? "card" : "widget";

Both paths write the same ladder — insert `draft` (`handler.ts:207-225`), then
`handler.ts:228-231`:

    for (const s of ["quoted", "payment_hold"]) { … }

then the `slot_holds` row (`handler.ts:234-238`, `runner_id: null` since 0111, 5-minute
`expires_at`). Then, **card path only**, `handler.ts:246-249`:

    if (paidPath === "card") {
      const { data: matched, error: casErr } = await db.from("bookings")
        .update({ status: "matching" })
        .eq("id", booking.id).eq("status", "payment_hold").select("id");

**CONFIRMED: the card path lands in `matching` inside the same request** — `payment_hold` is a
transient instant state for it, no new transition edge (`handler.ts:37-40`). On a lost CAS it
`compensate()`s (deletes hold then booking) and throws honestly (`handler.ts:250-267`,
`:287-294`), because a card owner "has no widget to come back to."

**The widget path stops at `payment_hold`** and, if nobody moves it, dies silently at 30 minutes
(`handler.ts:34-36`). The function returns `paid_path` (`handler.ts:274`) — and **the client
drops it**: `app/src/lib/api.ts:357` declares `HoldResult` with only
`{ booking_id, hold_expires_at, total_price }`; the string `paid_path` appears **nowhere** under
`app/`. So the client cannot today tell the two paths apart.

Preconditions already enforced before any write: `runner_id` in the body → 400
(`handler.ts:60-62`, 0111), dog/address ownership (`:90-97`), route status gate (`:110-133`),
**the debt lock** `owner_has_unsettled_charge` (`:152-159`, fail-closed on RPC error), km bounds
(`:76-80`), same-dog clash (`:180-191`).

### A.3 What `payment_ok` verifies — nothing about payment

`supabase/functions/transition-booking/index.ts:29-49`. Deployed **v33**. The whole arm:

    case "payment_ok": {
      if (!isOwner) throw new HttpError(403, "owner only");
      const { data: paid, error: pe } = await db.from("bookings")
        .update({ status: "matching" })
        .eq("id", booking_id).eq("status", "payment_hold").select("id");
      if (pe) throw new HttpError(409, pe.message);
      if (!paid || paid.length === 0) throw new HttpError(409, "결제 시간이 만료됐어요 — 예약을 다시 만들어주세요");
      break;
    }

**A bare owner-gated CAS. It reads no `payments` row, no `billing_keys` row, no `ops_flags`, no
amount, no Toss anything.** Independently recorded as such by the 0111 reviewer
(`supabase/migrations/0111_booking_entry_rebuild.sql:66`, `:77`;
`docs/security-booking-party-forgery.md:122`) and in REGISTRY's 0111 row ("a bare CAS that
verifies NOTHING about payment, zero money moved").

Client callers, measured across the whole `app/` tree: exactly one —
`app/src/lib/api.ts:402-408`, `body: { booking_id: bookingId, action: 'payment_ok' }` (`:404`),
called from `app/app/owner/pay.tsx:171` only. One more caller outside the app:
`scripts/e2e.mjs:232-236` (a `step('payment_ok → matching')` that asserts the booking reaches
`matching` — it is a **required** step of the script, not an optional probe).

`confirm-payment` does **not** use `payment_ok`: it CASes the booking itself
(`supabase/functions/confirm-payment/handler.ts:192-198`, same `.eq('status','payment_hold')`
statement).

### A.4 The four off-switches and `payments_live_since`

Production, read directly (`supabase db query --linked`, one statement per call):

| layer | measured now | source |
|---|---|---|
| `ops_flags.payments_live_since` | **NULL** (`pls_null = true`; `return_seal_since` also NULL) | `0080_charge_machine.sql:183` |
| `billing_keys` | **0 rows** | — |
| `payments` | **0 rows** | — |
| `TOSS_SECRET_KEY` / `CRON_COLLECT_KEY` | unset | `docs/pre-charging-checklist.md:40-46`, §2.1/2.2 |
| Vault `charge_dispatch` | absent (0 secrets of any name) | `docs/pre-charging-checklist.md:90-93` |

`bookings` = 28 rows; `slot_holds` = 0; **`bookings` in `payment_hold` = 0**. Status spread:
expired 14, completed 8, refund_pending 2, runner_enroute 2, incident_review 1, cancelled_owner 1.

Cron: 17 jobs, all `active = true`, including `dispatch-due-charges` `4-59/5 * * * *`,
`sweep-settled-charges` `2-57/5 * * * *`, `expire-unmatched` `*/5 * * * *`, `purge-holds`
`1-56/5 * * * *`, `sweep-payment-intents` `3-58/5 * * * *`. They fire and do nothing by gate
(`0080:1214` `if v_due = 0 then return 0;` — before the Vault read at `0080:1216`).

The flag gate lives inside the mint, not at the caller:

    0084_g1_ops_cutover.sql:263-266   (live copy; byte-identical original at 0080:360-363)
      select f.payments_live_since into v_since from ops_flags f where f.id;
      if v_since is null then return; end if;                    -- charging is off: write nothing
      select coalesce(r.ended_at, now()) into v_ended from runs r where r.booking_id = p_booking;
      if coalesce(v_ended, now()) < v_since then return; end if;  -- pilot-era run: free, forever

Setter refuses the past: `0084:476-479` `cutover_must_be_future`.

Deployed edge functions (measured, `functions list`): `create-booking-hold` v9,
`transition-booking` v33, `settle-run` v14, `confirm-payment` v1, `collect-charges` v1,
`open-drop` v8, `geocode-address` v1. **`create-payment-intent` is NOT deployed** — so the Toss
widget path could not complete in production even if the client's `TOSS_ENABLED`
(`app/src/lib/toss.ts:13`, hard `false`) were flipped.

### A.5 Where an owner is charged — at settle, never at confirm

`settle-run/handler.ts`: party gate `:54-60` → runner price `compute_runner_payout` `:150-155`
→ **the settlement** `settle_run_tx` `:173-184` → `:216` (`// 정산은 여기서 끝났다. 아래는
수금이고, 수금은 정산을 되돌리지 않는다.`) → **the charge branch** `:221`
`collectAfterSettle(...)` → `mint_settle_charge_intent` `:297-301` → `dispatchCharge`
`:326` → the actual card call `supabase/functions/_shared/charge.ts:231-239`. Whole collection
branch inside try/catch (`:296`, `:328-332`); with the flag null the mint returns 0 rows and the
function reports `collection: "skipped_not_live"` (`:308-310`).

**The runner is paid regardless.** `ledger_items` is written inside `settle_run_tx`
(`0083_run_end_flow.sql:754-755`) from `compute_runner_payout` (live definition
`0102_payout_commission_guard.sql:41`), which reads only `bookings` — never `payments`, never
`ops_flags`. Pre-cutover every run still writes a full ledger row and mints nothing.

**And settlement already waits for the RETURN handoff.** `settle_run_tx` refuses with
`return_not_sealed` when the run has ended and the dog is not confirmed home
(`0083:681-687`): *"아직 인계가 확인되지 않았어요 — 강아지가 집에 도착한 뒤 정산돼요"*. So the
charge point the machine already implements is **after the run *and* after the return handoff** —
which is precisely where ruling #1 puts payment. Nothing in this contract has to move it.

Every writer that INSERTs `payments`, measured: `create-payment-intent/handler.ts:69` (widget,
pre-run, **not deployed**, unreachable while `TOSS_ENABLED=false`), `mint_settle_charge_intent`
(`0084:295`, superseding `0080:392`) at settle and via the `sweep_settled_without_payments`
backfill (`0080:618`), and `mint_cancel_fee_intent` (`0080:467`) at owner cancel. **No path
creates a `payments` row at booking time, at `payment_hold`, or on `payment_ok`.**

### A.6 Hold expiry

Live definition is 0080's, not 0060's: `expire_unmatched_bookings` at
`0080_charge_machine.sql:928-958` (cron `expire-unmatched`, `*/5 * * * *`). Two deliberately
disjoint sibling CTEs — merging them is a declared contract violation (`0080:921-923`):

- `e_match` (`0080:932-937`): `status in ('matching','runner_pending') and scheduled_at < now()`
  → `expired`, **with a notification** whose body is already post-pay aware (`0080:941-946`):
  a booking with no `confirmed` payment gets *"…결제된 금액이 없어 청구되지 않아요"*.
- `e_hold` (`0080:948-953`): `status = 'payment_hold' and created_at < now() - interval '30
  minutes'` → `expired`, **silent by design** (pinned by `100_wave3_suite.sql` W7).

`slot_holds` rows carry a 5-minute `expires_at` (`create-booking-hold/handler.ts:233`) and are
reaped by `purge-holds`. Since 0111 they name no runner, so they block nobody.

### A.7 The client, today — re-measured against `origin/redesign-v4` @ `cf162b1`

- **`app/app/owner/request.tsx` is the ONE hold-creation entry point in the whole app.** Measured
  by enumerating every `.ts`/`.tsx` blob on origin: `createBookingHold` is called at
  **`request.tsx:449`** and nowhere else (the only other hit is its own import at `:6`). The
  response is narrowed at `:471-472` to `booking_id` + `hold_expires_at`, and the push is
  **`request.tsx:500`**:
  `router.push({ pathname: '/owner/pay', params: { bid, after: 'radar', …recurring, …exp } })`.
  **The push already carries `after: 'radar'`** (added by `cf162b1`, explained in its own comment
  at `:495-497`: *"once pay.tsx confirms the hold with NO nomination, land on the rebuilt radar"*)
  — so the destination after the hold is already decided and only the screen in between is being
  deleted. The file states the hand-off in its own words at `:469-470` (*"홀드까지가 요청 화면의
  몫이고, 확정과 그 이후(리커링·지명·라우팅)는 /owner/pay가…"*) and again at `:569`. **That
  sentence is the law §E.5.1 has to repeal**, not a stray comment: the three things it names
  (리커링 · 지명 · 라우팅) are the three things `pay.tsx` does that are not payment.
- **`request.tsx` owns the 매주 반복 toggle and it is a real control.** `recurringOn` state at
  `:262`, the toggle UI at `:942-955`, the fold summary that refuses to hide a live value at
  `:565`, and the parameter handoff at `:500` (`...(recurringOn ? { recurring: '1' } : {})`).
  **The screen that consumes that parameter is the screen being deleted** (§E.5.1 / F1).
- ⟳ **The Find-Now second entry point is GONE, and this correction is load-bearing.** At this
  worktree's base (`8d33cde`) `app/app/owner/home.tsx:599/:623` created its own hold and pushed
  `/owner/pay` — a second stranding path. On origin at `cf162b1` home.tsx has **no**
  `createBookingHold` and **no** `/owner/pay` route; its only booking route is → `/owner/request`.
  So §E.5's client change is **one file, not two**. Recorded rather than silently deleted: any
  handoff or lab doc written before `68a4257` still describes two entry points and a push at
  `:395`/`:406`, and that is doc drift (§G.10) — cite `:500`.
- **`app/app/owner/pay.tsx` is not only a payment screen, and this is the single most important
  client fact in the file** (F1). It loads `fetchBookingCharge` (`:96-113`), derives phase from
  server status via `src/lib/payphase.ts:47` (`payment_hold: 'mock_pending'`), its primary button
  reads **`예약 확정하기`** with `TOSS_ENABLED=false` (`:447`), and it calls
  `confirmPayment(bookingId)` at `:171`. No timer; `exp` is a static string (`:80-83`). Copy at
  `:391-393`: *"결제 수단 연동 준비 중 — 파일럿 기간에는 확정 시 실결제가 발생하지 않아요"*. No
  cancel CTA, and the file says why (`:455`): `payment_hold → cancelled_owner` is not in the map.
  **But `postConfirm` (`:126-166`) runs three effects that have nothing to do with payment** —
  enumerated in §E.5.1, all three of which die with the screen unless they are moved.
- `app/src/lib/api.ts` is **unchanged by the rebuild** at every line this contract depends on:
  `HoldResult` at `:360` (still no `paid_path`), `createRecurringSeries` at `:390`, `confirmPayment`
  at `:402-408` with `action: 'payment_ok'` at `:404`, and `fetchMyBookings`'s
  `.not('status','in','(draft,quoted,payment_hold)')` at **`:3767`** (with the comment at `:3766`
  saying why: *"결제 미완 유령(draft/quoted/payment_hold)은 일정이 아니다"*) — **a booking sitting
  in `payment_hold` is invisible in 내 일정.**
- **`app/app/owner/radar.tsx` requires `draft.bookingId`, and bounces to home without it.**
  `:68` `const bookingId = (typeof bidParam === 'string' && bidParam) || draft.bookingId;` and
  `:83-86` *"부킹 없이 진입하면 홈으로"* → `router.replace('/owner/home')`. `request.tsx` never sets
  `draft.bookingId` on success (only clears it on failure, `:477`); `pay.tsx:127` is the only
  writer. **So routing to the radar without first setting `draft.bookingId` is a bounce to home,
  not a radar.** This is the hard requirement §E.5.1 is built around.
- `app/app/owner/matching.tsx` gates its whole live mode on the same field: `:141`
  `const live = !!draft.bookingId;` (and `:169`, `:172`, `:175`, `:211`).
- ⟳ request.tsx also now carries route-pick nearest-point ranking and a `totalKm` including the
  approach leg (rulings #14/#15). **Irrelevant to payment mechanics** — noted only so a reader
  diffing the file does not mistake it for scope creep in this slice.
- `app/app/dev/pay-lab.tsx:12` imports `PayScreen, PayView` from `../owner/pay` (dev route —
  relevant to the route-native-import law when pay.tsx is eventually retired).

---

## B. The problem, precisely

**B.1 Payment is a costume.** `payment_ok` is named for money and moves no money and checks no
money (A.3). The screen that calls it is titled 예약 확정 and its own button says 예약 확정하기
(A.7). The step exists because `docs/payments.md:20-22` planned a Toss widget there in 2026‑07,
and that plan was itself superseded four weeks later by Sean's own post‑pay amendment
(`docs/plans/payments-toss-plan.md` §0-bis: *"NOTHING is charged before or during service:
booking is free, matching is free, the run happens, and the charge fires in `settle-run` on
ACTUALS"*). The card path was rebuilt to that model; **the widget path was left behind and is
now the only pre-run payment step in the product.**

**B.2 The pilot has no real charge, at four independent layers** (A.4). `payments` is empty,
`billing_keys` is empty, the Toss secret and the cron key are unset, the Vault secret does not
exist, and the flag is NULL. `docs/pre-charging-checklist.md` §4-bis states it as the money
owner's fact: *"Nothing is charged, ever, by any path."* So the pre-run step collects nothing
from anyone and cannot.

**B.3 Sean's ruling** (`docs/labs/RULINGS-2026-08-19-journey.md:6-10`, verbatim heading and text):

> **Payment comes AFTER the run and after handoff-back.** Not between reserve and live.
> → The pay/notice screen moves to the END of the journey (after report / return handoff). The
> reservation path is: home → [slots] → **예상 금액 shown once** → radar. No money screen mid-flow.
> → He asked why the current UI shows a price at all pre-run. Answer: it is the frozen quote from
> `create-booking-hold`; showing it is fine ONCE as 예상 금액, but it was styled like a receipt.

and the answer recorded in the same file (`:42-44`):

> "why is payment between reserve and live?" → because `owner/pay` is pushed from request step 3
> today (request.tsx → /owner/pay). That is a leftover of the Toss-widget plan; the pilot is
> manual transfer, so there is nothing to collect pre-run. Moving it post-run matches money §4-bis.

**B.4 What strands if only the client reroutes.** `payment_ok`'s CAS is the *only* thing that
moves a widget-path booking out of `payment_hold` (A.1, A.3). Delete the `/owner/pay` push at
`request.tsx:500` and every pilot booking — every owner has no billing key (production
`billing_keys` = 0 rows), so every booking is widget path — sits at `payment_hold`, where:

1. it is **not** in `marketplace_open_requests` (the view requires `status = 'matching'`,
   `0056_decline_log.sql:63-64`), so no runner ever sees it;
2. it is **invisible in the owner's 내 일정** (`api.ts:3767`);
3. `e_hold` reaps it **silently** at 30 minutes (`0080:948-953`; the silence is pinned by 100 W7).

The owner watches a radar for a run that no runner can see, and 30 minutes later it is gone
without a word. **That is the strand, and it is why ui correctly declined to reroute alone**
(`docs/handoff-announcer.md:80`, `:118-122`).

**B.5 What an OLD build actually does against the NEW server — corrected (F2).**

Revision 1 of this file claimed the hazard was a **false expiry 409**: an old build calls
`confirmPayment` on a row already at `matching`, the CAS returns 0 rows, and the owner is told
*"결제 시간이 만료됐어요"* about a perfectly healthy booking. **That is wrong, and the reviewer
executed the real path.** `payment_ok` is never called at all, because the old build never renders
the button that calls it:

1. `create-booking-hold` (post-C.1) lands the booking in `matching` inside the request.
2. `pay.tsx:104` derives the phase **on load** from the server status — `const phase =
   derivePayPhase({ status: c.status, attempt: attempt.current })`.
3. `src/lib/payphase.ts:50` maps `matching → 'authorized'` (as do `runner_pending`, `confirmed`,
   `runner_enroute`, `picked_up` at `:51-54`). The comment at `:49` already anticipated a booking
   arriving past the hold — it was written for club bookings, which never pass through
   `payment_hold` at all.
4. The `'authorized'` footer is a single CTA: **`내 일정에서 확인하기`** (`pay.tsx:467-469`). The
   `예약 확정하기` button only renders under `screen === 'mock_pending'` (`:445-452`), which
   requires `status = 'payment_hold'`. **It is never drawn.**

So the old build produces a **benign confirmation screen** — no 409, no false expiry, no error of
any kind. What it produces instead is a **silent omission**, and that is the real hazard:
`postConfirm` (`pay.tsx:126-166`) never runs, so that booking gets **no `draft.bookingId`, no
recurring series, and no runner nomination** — the three effects of F1 — and the owner is told
nothing, because from the screen's point of view everything succeeded. Tapping the CTA lands them
in 내 일정 where the booking really is (it is `matching`, so `api.ts:3767` lets it through).

🔵 **ANNOUNCER DECISION (a) — this is a smoke-list line, not a mitigation.** Shipped population is
**zero**: `docs/decisions/awaiting-sean.md` §0-octies records *"forced-upgrade population = 0 (no
build ever shipped)"* (`:502`) and the EAS build count was re-verified as 0 earlier tonight. There
is no phone in the world running a pre-change build, so **no code is written to defend against
one.** What is owed instead is one line on Sean's hardware smoke list, because his own device is
the one place a stale binary can appear:

> **Smoke list:** *a pre-change build shows 예약이 확정됐어요 with no recurring series and no
> nomination — silently, with no error. That is the old binary meeting the new server, not a
> regression. Update the build.*

**Consequence for the ordering (§E) and for §C.2:** the entire justification for shipping
`payment_ok` in two moves was to protect this population. There is no population, the failure mode
is not the one that was feared, and the idempotent-success shim would not have helped anyway — the
call it was meant to soften is never made. **Move 1 is deleted; `payment_ok` is removed in ONE
move** (§C.2).

---

## C. Target end state — **[REC]**

The minimal server change that makes "pay after the run" TRUE for the pilot, with **zero change
to the charge machine's money semantics, zero migrations, and zero transition-map edges.**

### C.1 [REC] `create-booking-hold`: while charging is off, BOTH paths land in `matching`

Read the cutover flag beside the billing-key lookup — i.e. **before any write**, in the same
"ask everything first" block the card path already established (`handler.ts:161-168`) — and make
the instant CAS unconditional while the flag is NULL.

    // beside handler.ts:165-168, before the insert
    const { data: flags, error: fErr } = await db.from("ops_flags").select("payments_live_since").maybeSingle();
    if (fErr) throw new HttpError(500, fErr.message);          // fail-closed, same shape as the debt lock (:152-153)
    const chargingLive = !!flags?.payments_live_since;

    // replacing handler.ts:246
    if (paidPath === "card" || !chargingLive) { …existing CAS + compensate()… }

`service_role` holds SELECT on `ops_flags` (**verified** against production), so no grant change
and no RPC is needed.

**This read is a NEW HARD DEPENDENCY, and that must be stated rather than buried in a diff (F6).**
Today `create-booking-hold` does not touch `ops_flags` at all; after C.1 **every booking in the
product depends on that one row being readable**. Fail-closed (500, no booking created) is the
right answer for a money-adjacent gate — the same shape the debt lock already uses at
`handler.ts:152-159` — but "right" is not the same as "obvious", so it is **pinned, not assumed**:

> **Deno pin (D.10)** — with the `ops_flags` SELECT stubbed to return an error, the call returns
> **500** and the `bookings` and `slot_holds` row counts are **unchanged**. A booking must never be
> created by a request that could not read the flag, and a flag read failure must never be
> swallowed into "assume charging is off".

⚠ **`ops_flags` is not "sealed" in a privilege sense — do not describe it that way (F15).** RLS is
enabled on it (`0080:187`) with **zero policies**, and that — not a revoke — is what closes it to
`anon`/`authenticated`. The table-level DML grants are still held by those roles; RLS is the only
thing standing there. It is the same shape as 0111's R5 finding on `slot_holds`. Nothing in this
slice changes it, and nothing in this slice may claim credit for it.

Everything else is untouched: the same `draft → quoted → payment_hold` ladder
(`handler.ts:228-231`), the same `slot_holds` row, the same CAS statement, the same
`compensate()` and the same two honest failure sentences (`handler.ts:250-267`). `payment_hold`
becomes a transient instant state for the pilot exactly as it already is for the card path —
**the edge, its pin (109 P6) and the enum are all unchanged.**

`paid_path` in the response keeps its meaning (which path the owner is on) and gains a companion
so the client is not left inferring: **return `booking_status: "matching" | "payment_hold"`.** A
client must never have to guess whether a further call is required.

**Why flag-gated rather than unconditional:** it makes the pilot behaviour self-describing and
keeps the money session's post-flip surface theirs to design. See C.3 for the arm that must NOT
be a silent revert.

#### C.1a — 🔵 Accepted consequence: **abandonment stops being silent** (F9)

C.1 does not only shorten a ladder; it **changes what a half-finished booking means**, and the
reviewer was right that shipping this without naming the change would be shipping a surprise.
Today a booking that dies at `payment_hold` is invisible to everyone and vanishes without a word.
After C.1 the booking is **`matching` at hold-creation time**, which means it is in
`marketplace_open_requests` **immediately** — and that view publishes the dog's name, breed,
weight, memo, photo, preferences and vaccinations (`0056:44-58`, columns carried verbatim from
0042) to **every active runner** (`is_active_runner()`, `0056:65`), and keeps publishing until
`scheduled_at` passes and `e_match` expires it.

Concretely, the three things that change:

- **A force-quit during the hold modal can now get you a matched runner.** The owner who closed
  the app mid-flow used to have nothing; now they have a live open request, and a runner may
  accept it while they are not looking.
- **`e_hold` becomes unreachable for the pilot** (`0080:948-955`). Nothing lands in `payment_hold`
  and stays, so the 30-minute silent reaper has nothing to reap. Its pin (100 W7) stays green
  because the suite inserts its fixtures directly in SQL (N5), but the *product* no longer
  produces its input.
- **The disappearance moves from silent to spoken.** An abandoned booking now expires via
  `e_match` at `scheduled_at` **with a notification** whose post-pay arm already says the honest
  thing — *"시작 시간까지 러너를 찾지 못했어요 — 결제된 금액이 없어 청구되지 않아요"*
  (`0080:944-946`).

🔵 **The announcer accepts this consequence under the overnight grant**, on three grounds: it is
the *unavoidable* shape of "a booking is free to make" (there is no version of pay-after-run in
which a booking waits for a payment that does not exist); the honesty laws prefer a spoken ending
to a silent one; and **the owner is not trapped** — P6/P7 pin the exit that C.1 creates
(`matching → cancelled_owner` is in the map at `0066:46`, `marketplace_cancel_fee` returns 0 on an
unmatched booking at `0066:77`, and the booking is now visible in 내 일정 to cancel *from*). Under
the old flow the owner had no cancel CTA at all (`pay.tsx:455`). **The mitigation is the exit, and
the exit is pinned.**

#### C.1b — a hole C.1 closes for free, which must be pinned as a positive (F11)

The same-dog clash guard (`create-booking-hold/handler.ts:177-191`) checks a **LIVE list that
deliberately excludes `payment_hold`**: `["matching","runner_pending","confirmed","runner_enroute",
"picked_up","active"]` (`:179`), with the comment at `:177-178` saying why (*"draft/payment_hold
잔재나 종결 상태는 차단 사유가 아니다"*). That is correct today — a stale hold must not block a
retry — but it means **two overlapping holds for the same dog can both be created right now**, and
the second only fails later, if at all. After C.1 the first booking is already `matching` when the
second request runs its guard, so **the second is refused at `:191`** with the existing honest
sentence *"이 시간대에 같은 아이의 예약이 이미 있어요"*. This is a real improvement, it was not
designed for, and an undesigned improvement is exactly the kind that gets refactored away by
someone who did not know it existed — so it gets a **positive pin (P8)**, not a footnote.

### C.2 [REC] `payment_ok` is deleted — 🔵 in ONE move, with C.1 (revised, F2)

**Revision 1 sequenced this as two moves: an idempotent-success shim first, the deletion later.
That shim is deleted from the plan.** It existed solely to protect an old build from a false
expiry 409, and §B.5 measured that the old build never makes the call at all — the button that
would make it is never rendered, because `payphase.ts:50` maps `matching → 'authorized'`. A shim
that softens a call nobody makes is dead code shipped on purpose, plus an extra deploy, plus a
`payment_ok.ts` extraction and a `payment_ok_test.ts` that exist only to be deleted a week later.
🔵 **ANNOUNCER DECISION: one move.**

**The single move, shipped with C.1:**

- delete the `case "payment_ok"` block, `transition-booking/index.ts:29-51`;
- drop `payment_ok` from the action list in the file header, `index.ts:3`;
- delete `confirmPayment` from `app/src/lib/api.ts:402-408`;
- update `scripts/e2e.mjs:232-236` in the same slice (F14 — see §E.5.2). It calls `payment_ok` as
  a **required** step, so it breaks at exactly one moment, and because there is now only one
  moment there is only one thing to keep in sync.

The action then falls through to the default at `index.ts:397-398` — `throw new HttpError(400,
\`unknown action ${action}\`)` — which is the correct answer to a caller asking for a step that no
longer exists.

**No extraction is needed any more.** Revision 1 required moving the arm into
`transition-booking/payment_ok.ts` because `index.ts` has `Deno.serve` at module top level and
cannot be imported by a test (`index.ts:326-328`, `:334-337` — the stated reason `cancel_owner.ts`
and `start_run.ts` are separate files). With no shim to pin, there is nothing to extract and
`payment_ok.ts` / `payment_ok_test.ts` are **never created**.

**What survives the deletion is one pin (F7/F13), and it matters more than it looks.** The
reviewer established that **nothing in the repo asserts `payment_ok` today** — not one SQL suite,
not one Deno test (`grep -rn payment_ok supabase/tests/ supabase/functions/_test/` returns only a
prose mention inside `harness.sh:184`). In particular `146_booking_entry_suite.sql` **D-15**, which
two contracts described as pinning the bare `payment_ok` CAS, actually pins **`request_runner`'s**
CAS (`146:776`, `:797` — *"request_runner의 한 문장 CAS(service_role)는 그대로 1행"*). That claim
is corrected in both files (§H/F13).

So this deletion removes behaviour **that nothing asserts** — which is precisely why the slice must
leave an assertion behind rather than a hole:

> **New Deno pin (N9)** — `action: 'payment_ok'` on a real booking, as its real owner, returns
> **400 `unknown action payment_ok`** (`index.ts:397-398`). Not 403, not 409, not 200. The step is
> gone and the server says so.

**Why removal and not "keep it, it's harmless":** an action named for a payment that verifies
nothing about payment and takes no money is a costume, and this repo's honesty law is about
exactly that shape (`create-booking-hold/handler.ts:48-56` argues the same point for a different
field). Keeping it also keeps a second, redundant writer of the one edge that matters.

⚠ **What removing `payment_ok` does NOT do: it does not close /cso #2's F2 (B-11).** The
nomination chain becomes *shorter*, not narrower — `create-booking-hold` (own dog) →
`request_runner` (any real runner) still yields `runner_id = victim` at `runner_pending` with no
acceptance, because `is_booking_party` has no status filter (`0002:15-22`;
`docs/security-booking-party-forgery.md` §E.9). That slice is Sean's D1/D2 → O-4's **D2-narrow**
and is a **different** piece of work. Nobody may report a security win from this contract.

### C.3 [REC] The post-flip arm must be a refusal, never a silent revert

If C.1 is flag-gated and nothing else changes, then the day Sean sets `payments_live_since` a
card-less owner's booking silently starts stopping at `payment_hold` again — with the screen that
used to move it deleted. That is B.4 rebuilt on a timer. So the same slice must make the
post-flip, card-less case **refuse before any write**, with a named error:

    if (chargingLive && paidPath === "widget") throw new HttpError(409, "card_required" /* + Korean copy */);

placed with the other pre-write gates (`handler.ts:110-168`), so **no booking and no hold row are
created** — nothing to strand, nothing to compensate. This matches the already-agreed placement
decision: card registration is *"inline at first booking"*, a one-step consent sheet, not an
onboarding step (`docs/decisions/card-registration-placement.md:6`, `:20-22`).

It is **unreachable today** (flag NULL) and is therefore defence against a future flip, pinned by
a Deno test with a faked flag (D.9). Whether *refusal* is the right product answer post-flip —
versus letting the owner book and catching them with the debt lock after one uncollected run — is
**Sean's** call (§F.1); what is not negotiable is that it must not silently become `payment_hold`.

#### C.3a — ⚠ the flip-day exposure is the IN-FLIGHT stock, and C.3 does not touch it (F4)

Revision 1 framed the flip-day risk as *"card-less owners silently landing back in
`payment_hold`."* **The reviewer measured the larger one, which is the bookings that already
exist when the flag is set**, and it needs naming here even though the fix is not this slice's.

**The mint keys on RUN END, not on booking creation.** `0084:265-266`:

    select coalesce(r.ended_at, now()) into v_ended from runs r where r.booking_id = p_booking;
    if coalesce(v_ended, now()) < v_since then return; end if;   -- pilot-era run: free, forever

The comment says *"pilot-era run: free, forever"*, and for a run that **ended before** the flip
that is exactly true. But a booking created before the flip whose run ends **after** it is not a
pilot-era run by this predicate. So on flip day, every already-`matching`/`confirmed` booking held
by a card-less owner walks this chain:

1. run ends after `payments_live_since` → `mint_settle_charge_intent` mints a **pending** row;
2. `dispatchCharge` finds no billing key → returns `skipped_no_card` and deliberately writes **no**
   dispatch marker (`_shared/charge.ts:184-190`, and the comment says why: the never-dispatched
   pending is the only shape the stale sweep may close);
3. one hour later `sweep_stale_payment_intents` flips it to **`failed`** — and because the row is
   server-minted (`raw->>'kind'` is non-null) it fires **an owner notification**:
   *"지난 러닝 이용료 결제를 시도하지 못했어요 — 설정 > 결제 관리에서 확인해주세요"* (`0080:818-837`);
4. `owner_has_unsettled_charge` now returns true for that owner (`0080:511-528`: `status='failed'`
   + kind non-null + a `runs` row with `ended_at`), and **the debt lock locks them out** of
   creating any new booking (`create-booking-hold/handler.ts:152-159`).

**C.3 does not help with any of this, and §F.1(a) bounds NEW ENTRIES ONLY.** A refusal at
booking-creation time cannot reach a booking that was created yesterday. The owners hit by this are
precisely the ones who did nothing wrong: they booked while booking was free.

**[REC] — the flip procedure must carry a cut-over rule for in-flight bookings.** This contract
does not choose it; it refuses to let the flip ship without one. The candidate shapes:

- **(i)** `payments_live_since` applies to bookings **CREATED** after it — i.e. the mint gains a
  `bookings.created_at >= v_since` arm alongside the run-end arm. Cleanest semantics ("the deal you
  booked under is the deal you get"), and it changes a definer function, so it is a migration.
- **(ii)** the money session **drains** in-flight bookings before flipping — pick a flip moment
  with no unfinished runs, which the pilot's volume makes realistic.
- **(iii)** the money session **annotates** them — mark the pre-flip stock and have the mint skip
  it, which is (i) with an explicit column instead of a derived predicate.

⚠ **This is the money session's slice, not this one.** It is recorded here because this contract is
where the flip's blast radius was measured, and a measured hazard that lives only in a review
thread is a hazard nobody owns. Nothing in §C is blocked on it — the flag is NULL, `payments` and
`billing_keys` are both 0 rows, and every one of these paths is unreachable until Sean flips it.

### C.4 What changes when charging flips — **the money session's slice, not this one**

Named here so nobody re-derives it, and explicitly **out of scope**:

- The **card path is already the post-flip design** and needs nothing: booking free → run →
  `settle_run_tx` (after the return seal) → `mint_settle_charge_intent` →
  `dispatchCharge` → Toss billing key. C.1 does not touch it.
- The **Toss widget's job moves** from "pay for this run" to "link a card once"
  (빌링키 발급) — `docs/plans/payments-toss-plan.md` §0-bis. That is the **card-register slice**,
  already owned by money and already blocked on Sean's Ⓐ lab pick
  (`docs/decisions/card-registration-placement.md:20`). `create-payment-intent` is not even
  deployed today (A.4).
- C.3's `card_required` refusal is the seam between the two, and the money session may replace it
  with anything that is not a silent `payment_hold`.
- **The in-flight cut-over rule (C.3a) is theirs, and it is a precondition of the flip, not a
  follow-up to it.** `payments_live_since` currently keys the mint on **run end**, so flipping it
  with unfinished card-less bookings on the books converts each of them into a failed charge, an
  owner notification, and a debt lock. One of C.3a's three shapes must be chosen and pinned before
  the flag is ever set. This contract does not choose; it refuses to let the choice go unmade.
- The pre-flight order is unchanged and already written:
  `docs/biz/payments-paperwork-checklist.md` §5 and `docs/pre-charging-checklist.md` §2.1–2.6.

### C.5 What is NOT touched

#### C.5.0 First, a premise this contract had wrong — **not every booking passed through a hold** (F10)

Revision 1 argued C.1 as *"the hold ladder stops being a two-step for the pilot."* That framing
implied every booking in the product is born at `payment_hold`. **It is not, and it has not been
since 0026.** `generate_recurring_bookings` (`0111:272-386`, cron `recurring-gen` `7 * * * *`,
active) inserts **directly** at `matching` or `runner_pending`:

    0111:369-376   insert into bookings (…, status, …) values
                     (…, (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status, …)

— no `slot_holds` row, no hold window, no `payment_hold`, no `payment_ok`. 0026's own header said so
at the time (`0026_recurring.sql:10`): *"결제: 현재 payment_ok 모의 단계라 크론 생성 예약은 결제
단계 없이 matching/runner_pending 직행."*

**So C.1 does not invent a shape; it makes `create-booking-hold` CONSISTENT with a shape the
product has always had on its other entry.** That is a materially stronger argument than the one
revision 1 made, and it retires Alt‑1's implied objection entirely.

**The two surfaces do differ post-flip, and the difference is deliberate.** `generate_recurring_bookings`
reads the same flag (`0111:288`) and applies the same money gates (0080 §0-ter #3 ⓑ/ⓒ,
`0111:339-355`) — but a card-less owner post-flip is **BLOCKED WITH A NOTIFICATION**
(*"반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요"*, `0111:347-351`) and
the loop `continue`s, whereas C.3 **refuses at entry** with `card_required`. Both are honest; they
differ because **a refusal can be shown on a screen and a background sweep has no screen** — an
hourly cron cannot open a card-registration sheet, so its only honest move is to pause and say so.

⚠ **Therefore §F.1's answer must be stated ONCE and applied to BOTH surfaces.** If Sean answers
F.1 with (b) *"let them book, the debt lock handles it"*, then C.3 is deleted **and** `0111`'s ⓒ
`no_card` arm becomes wrong in the same breath — it would be pausing recurring bookings for a
condition the product has decided is not blocking. Answering for one surface and not the other is
how the two drift apart.

#### C.5.1 The boundary list

Stated as a boundary, not as an aside — a reviewer should be able to check each one by grep:

- **Settle math** — `compute_owner_charge` (`0080:236`), `compute_runner_payout`
  (`0102:41`), `settle_run_tx` (`0083:628`), the charge-basis table
  (`payments-toss-plan.md` §0-ter).
- **Payouts / `ledger_items`** — `0083:754-755`. Untouched; and independent of collection by
  construction (A.5).
- **The `min_fare` floor** — `bookings.min_fare` (`0001:181`), the km floor (`0075:90`),
  `compute_runner_payout`'s use of it (`0102:62`), and `0086:66`'s deliberate non-application.
- **The club money path** — `club_incident_settle` (`0080:977`), `club_release_payouts`
  (0045/0072), `0081_club_money_gates.sql`. R6, out of scope, as it has been in every money slice.
- **The meetup stage machine, polling, `confirmHandoff`** — frozen by CLAUDE.md DO-NOT-REFACTOR.
- **The transition map / the enum** — no edge added, none removed, no new value.
- **`confirm-payment`, `collect-charges`, `_shared/charge.ts`, the cron ladder, the debt
  derivation** — all untouched.
- **The four off-switches** — untouched; the change reads the flag and never writes it.

### C.6 Alternatives considered, and why not

**Alt‑1 — keep `payment_hold` and auto-advance it (a new cron, or a trigger on insert).**
Rejected. It adds a moving part to reach a state the same request could have reached, and it
opens a window in which the booking exists but is invisible to every runner. The card path
already proves the in-request CAS is the right shape (`handler.ts:37-40`), and a cron that
advances money-adjacent state is a new thing to reason about at 3 a.m. for zero gain.

**Alt‑2 — leave the server alone and have the client call `payment_ok` immediately after
`createBookingHold`.** Rejected, and it is the **dishonest** option under the honesty laws. It
keeps a call named `payment_ok` in the product for a payment that does not exist, in a place where
its name now describes nothing at all — the "no dead buttons / no fake states" law and the
"failures are shown as failures" law are both about a UI whose vocabulary is not what the server
does. It also keeps two round-trips and a real failure window (network loss between the two calls
strands the booking in `payment_hold` exactly as B.4 describes) in exchange for saving one edge
function deploy. And it leaves `payment_ok` reachable as B-11's second link.

**Alt‑3 — make the CAS unconditional (drop the flag read entirely).** Tempting: less code, and it
states the model ("a booking is free to make") without a condition. Rejected for this slice
because post-flip it silently books card-less owners for free and only catches them via
`owner_has_unsettled_charge` *after* a run has been given away — a real, bounded money hole
created by an engineering simplification rather than a decision. If Sean answers §F.1 with "let
them book, the debt lock handles it," Alt‑3 becomes correct and C.3 is deleted; the diff is small
in both directions.

**Alt‑4 — move `payment_ok` post-run (make it the thing the owner taps after the report).**
Rejected. Named in `docs/handoff-announcer.md:120` as one of two candidate shapes, so it is
answered here rather than left open: there is nothing for the owner to tap, because the charge is
server-initiated at settle and *"invisible per-run"* by Sean's own 2026‑08‑12 amendment
(§0-bis). Introducing an owner-tapped post-run payment step would contradict the ruling it is
meant to implement.

**Alt‑5 — a new status (`awaiting_transfer`-style) for the pilot.** Rejected, with a precedent:
`docs/plans/payments-bridge-plan.md` is **SUPERSEDED — NOT BUILT, DO NOT BUILD**, and its §C-4
records why the cost is permanent — *"Postgres cannot drop an enum value."* Nothing here needs a
new state.

---

## D. Attack / behaviour pins

All SQL pins go in **one new suite, next free number `147`** (measured from origin:
`supabase/tests/` tops out at 146; `grep -oE '^[0-9]+' | sort -n | tail -1`, never `ls | sort`).
Deno pins extend `supabase/functions/_test/`. **No migration is required**, so no REGISTRY
migration row is claimed; the edge-function work **must** claim an in-flight row (§E.6).

### Negative — the things that must stay impossible

- **N1 — a client cannot move a booking past `matching` by any direct write.**
  As `authenticated` with a real claim: `update bookings set status='confirmed'` → refused
  `booking_protected_columns` (`0058:264-278`), rolled back. Also assert the *grant* is still
  present (`has_column_privilege('authenticated','bookings','status','UPDATE') = true`) so the
  pin proves the **trigger** is load-bearing and not an accidentally-revoked grant.
- **N2 — deleting the arm does not widen the door.** `payment_ok`'s own owner gate
  (`index.ts:30`) disappears with it, so pin what is left: the **party gate runs before the
  switch** (`index.ts:19`, `if (!isOwner && !isRunner && action !== "runner_accept") throw 403`),
  and a stranger sending `payment_ok` still gets **403 `not a party`** — not 400 — because they
  never reach the default arm. The booking's owner gets **400** (N9). Two different refusals for
  two different reasons, and neither is a 200. Deno.
- **N3 — no "at or past `matching`", ever: the set is ENUMERATED (F8).** `booking_status` is a
  Postgres enum with **no ordering** — `matching < confirmed` is not a thing you may write, and
  revision 1's phrase *"`matching` or later"* was an ordering assumption dressed as a fact. Wherever
  this contract or the client needs "the booking is past the hold", the set is these **seven,
  written out**, matching `payphase.ts:50-56` exactly:

      matching · runner_pending · confirmed · runner_enroute · picked_up · active · completed

  and the three that are emphatically **not** in it, each with its own behaviour, because the last
  time they were lumped in it was a recorded incident (payphase.ts's own header, `:14` — *"웨이브 2
  리뷰 C5 — 8종 미매핑 + no_show/incident_review가 '결제 완료'로 위장하던 사고"*):

  | status | phase | why it is not in the set |
  |---|---|---|
  | `refund_pending` | `refund_pending` (`:64`) | a refund in progress is a terminal-but-waiting state, not a booking that proceeded |
  | `no_show` | `disputed` (`:62`) | a human is reviewing it; rendering it as 완료 is the C5 lie |
  | `incident_review` | `disputed` (`:63`) | same |

  **The pin:** `STATUS_PHASE` covers all 16 enum values (it is a `Record<BookingStatus, PayPhase>`,
  so `tsc` fails on a new value — `:41`), `derivePayPhase` drops an **unknown runtime** string to
  `not_found` rather than to a success phase (`:70-71`), and the seven above are the exact set
  mapping to `authorized`. Assert the map, not a comparison. *(This pin is why §B.5's "benign
  confirmation screen" claim is checkable rather than a guess.)*
- **N4 — no charge exists while charging is off.** After a full booking→run→settle cycle with
  `payments_live_since` NULL: `select count(*) from payments` = 0, and `settle-run` reports
  `collection: "skipped_not_live"` (`settle-run/handler.ts:308-310`). SQL + Deno.
- **N5 — hold expiry still works, both arms, and `e_hold` is still silent.**
  `100_wave3_suite.sql` W7 must stay green unmodified. Add a new arm: a genuinely stuck
  `payment_hold` row older than 30 minutes is still reaped by `e_hold` (`0080:948-955`) with
  **zero notifications**, while a `matching` booking past its `scheduled_at` is reaped by `e_match`
  with the post-pay sentence (`0080:944-946`).

  ⚠ **The stuck fixture must NOT be a club booking (F3).** Revision 1 offered *"club booking, or a
  lost card CAS"* as interchangeable examples. They are opposites: `expire_unmatched_bookings`
  carries `and club_session_id is null` in **both** CTEs (`0080:937` in `e_match`, `0080:954` in
  `e_hold`; the production function definition confirms it), and `100_wave3_suite.sql` **pins a
  club `payment_hold` booking as STAYING `payment_hold`** — fixture `bh_club`, `:349-381`, whose
  own comment names the regression it catches: *"bh_club(31분 · 클럽 세션) → payment_hold 유지 ←
  club_session_id is null 누락"*. A club booking is the one thing `e_hold` is guaranteed **not** to
  reap, so using it as the "still gets reaped" fixture would assert the exact inverse of a pinned
  law and fail the harness for a correct reason.

  **Use instead:** a row stranded by a **lost card CAS / a `compensate()` failure** — a
  `payment_hold` row with `club_session_id is null` that no longer has a live path forward. That is
  a genuine post-C.1 residual (the card path's CAS can still lose to a concurrent sweep,
  `handler.ts:250-267`), it is exactly what `e_hold` exists for, and it keeps the pin honest about
  which rows the reaper owns.
- **N6 — the post-flip card-less refusal writes nothing.** With `payments_live_since` set and no
  billing key: 409 `card_required`, and `bookings` / `slot_holds` row counts are **unchanged**.
  Deno (faked flag).
- **N7 — the transition map is unchanged.** `109_payments_suite.sql` P6 (`:232-255`) must stay
  green **unmodified**: `payment_hold → matching` survives and `payment_hold → completed` is still
  refused. If P6 needs editing, the change has grown beyond this contract — stop.
- **N8 — the card path's compensating delete still fires.** Force the CAS to 0 rows; assert both
  the booking and the hold are gone and the error sentence is the "남은 예약도 없어요" variant
  (`handler.ts:261-266`). Existing Deno coverage; must stay green for the widget path too.
- **N9 — `payment_ok` is gone and the server says so (F7/F13).** As the booking's real **owner**,
  `{ action: 'payment_ok' }` → **400 `unknown action payment_ok`** (`index.ts:397-398`). Deno.
  **This is the only assertion the deletion leaves behind, and it is load-bearing precisely because
  the deletion removes behaviour that nothing currently asserts** — no SQL suite and no Deno test
  references `payment_ok` today (measured: the only hit under `supabase/tests/` is prose inside
  `harness.sh:184`; `146` D-15 pins `request_runner`, not this). Without N9 the removal is
  invisible to every gate in the repo, and the next reader has no way to tell "deliberately
  deleted" from "never existed".
- **N10 — the `ops_flags` read fails closed (F6).** Stub the `ops_flags` SELECT to return an error:
  the call returns **500**, and `bookings` / `slot_holds` row counts are **unchanged**. Mutation-
  verify by flipping the handler to swallow the error (`chargingLive = false` on failure) — the pin
  must go red. Deno. *(`service_role` SELECT on `ops_flags` is verified in production; this pin is
  about the day it is not.)*

### Positive — the things that must start working

- **P1 — a widget-path hold lands in `matching`.** No billing key, flag NULL → booking
  `status='matching'`, `runner_id` null, exactly one `slot_holds` row with `runner_id` null,
  fares from the server formula, response `paid_path: 'widget'` **and** `booking_status:
  'matching'`. Deno + SQL.
- **P2 — it is visible in `marketplace_open_requests`** to an `is_active_runner()` caller and
  invisible to a non-runner (`0056:43-75`). SQL, as `authenticated` with a runner claim.
- **P3 — `request_runner` works on it:** `matching → runner_pending`, the target notified once,
  re-nomination of the same runner is `{ unchanged: true }` (`index.ts:148-199`).
- **P4 — a runner accepts:** open-pool CAS `matching → confirmed` under the tier/club gates
  (`index.ts:122-135`), and a second concurrent accept loses with "이미 다른 러너가 수락했어요".
- **P5 — the run completes and settles:** enroute → arrived → both handoffs → `picked_up` →
  `start_run` → end → **return seal** → `settle_run_tx` writes the `runs` row and a full
  `ledger_items` row (`0083:754-755`) with **zero** `payments` rows. This is the pin that proves
  the runner is still paid with charging off.
- **P6 — the owner's free exit still exists, and is now reachable.** `marketplace_cancel_fee` on
  a `matching`/`runner_id is null` booking returns **0** (`0066:77`), and
  `matching → cancelled_owner` is in the map (`0066:46`). Under the old flow the owner had *no*
  cancel CTA at all (`pay.tsx:455`), so this is a real improvement and must be pinned as one.
- **P7 — the booking is now visible in 내 일정.** `fetchMyBookings` excludes `payment_hold`
  (`api.ts:3766-3767`); a `matching` booking passes. Client-observable; assert at the query level.
  Together with P6 this is the whole mitigation for C.1a's accepted consequence: the owner can see
  the booking they abandoned, and can cancel it for free.
- **P8 — the same-dog double-hold hole is closed (F11).** Create a hold for a dog at time T; create
  a second overlapping one for the **same dog** in the same window. Today both succeed, because the
  clash guard's LIVE list deliberately excludes `payment_hold` (`handler.ts:179`). After C.1 the
  first booking is already `matching` when the second request runs its guard, so the second is
  **refused at `handler.ts:191`** with *"이 시간대에 같은 아이의 예약이 이미 있어요"* — and the
  second booking and its `slot_holds` row are **never created**. Deno. Pinned as a **positive**
  because it is an unintended improvement, and an unintended improvement with no pin is the kind a
  later refactor removes without anyone noticing it was there.

### Deno tests for the edge functions

Run: `deno test --allow-all supabase/functions/_test/`. Baseline to beat: **191 / 0** (REGISTRY
0111 row). `FakeDb` (`_test/fakedb.ts`) needs an `ops_flags` seed — one table, one row.

1. **`booking_card_path_test.ts` MUST be updated in the same slice — it pins the exact behaviour
   this contract changes.** `:138-147` (`"no billing key → payment_hold exactly as before,
   paid_path 'widget', no CAS"`, `assertEquals(bookings(db)[0].status, "payment_hold")`) becomes
   false, as does the header claim at `:12-13` (*"The card-less path is asserted byte-for-byte
   against the pre-slice behaviour"*). Per CLAUDE.md: **update the pin, say WHY in a comment, and
   name which new pin owns the new property.** Do not delete it — rewrite it as "no billing key,
   charging off → `matching` in this request" and keep a separate arm for "no billing key,
   charging **on** → refused before any write" (N6).
2. New `booking_postpay_test.ts` (or arms in the file above): flag NULL vs flag set × card vs
   no card = four cases; assert write counts, not just final status (the existing file's
   `updatesToBookings(db).length === 3` idiom at `:193`).
3. **No `payment_ok.ts` and no `payment_ok_test.ts` — revised (F2).** Revision 1 required
   extracting the arm into `transition-booking/payment_ok.ts` so a test could import it, because
   `index.ts` has `Deno.serve` at module top level and cannot be imported (`index.ts:326-328`,
   `:334-337` — the stated reason `cancel_owner.ts` and `start_run.ts` are separate files). With
   the shim deleted there is nothing to pin in isolation: **N9 and N2 are HTTP-level assertions**
   (400 for the owner, 403 for a stranger) and need no extraction at all. **Do not create either
   module.** Creating a file in one move to delete it in the next was the two-move plan's cost, and
   the two-move plan is gone.
4. `settle_charge_test.ts` — must stay green unmodified; it owns "settlement happens, collection
   is skipped" and this contract must not perturb it.
5. New arm for **N10** (`ops_flags` read failure → 500, zero writes) and **P8** (same-dog
   double-hold refused post-C.1) in the `create-booking-hold` test file.

### Existing suites: green, or moved, with the reason

| suite | verdict |
|---|---|
| `109_payments_suite.sql` P6 (`:232-255`) | **green, unmodified.** The load-bearing proof that no map change happened (N7). |
| `100_wave3_suite.sql` W7 / W10 | **green, unmodified.** `e_hold` silence + ACL preservation (N5). |
| `116_charge_suite.sql` (`:451` fixture) | **green.** Its `payment_hold` booking is inserted directly in SQL to exercise the debt derivation; it never calls the edge function. |
| `117_club_money_suite.sql` | **green.** Club money path untouched (C.5). |
| `50_delegation_suite.sql` | **green.** Delegation/club path untouched. |
| `119_run_end_suite.sql` (ren R2) · `125_return_force_ops_suite.sql` (frc F5) | **green.** Both were already moved to `service_role` by 0111; nothing here re-touches `bookings` grants. |
| `146_booking_entry_suite.sql` D-11 (`:382-410`) | **green as an assertion, but its comment goes stale.** It performs the ladder as `service_role` and asserts the row is `payment_hold` — still true of the ladder, but the header calls this "the `create-booking-hold` shape". Update the comment in the same slice and point it at the new pin. |
| `146_booking_entry_suite.sql` **D-15** (`:776-798`) | **green, unmodified — and it does NOT pin `payment_ok` (F13).** Two contracts claimed it did. It pins **`request_runner`'s** one-statement CAS (`:797`: *"request_runner의 한 문장 CAS(service_role)는 그대로 1행"*). Nothing in the repo pins `payment_ok` — which is why C.2's deletion must leave **N9** behind. Corrected in `party-membership-status-filter-contract.md` too. |
| `120_g1_ops_cutover_suite.sql` | **green.** Cutover semantics unchanged. |

### The one measurement that would falsify the plan

If any pin shows a booking reaching a state the transition map forbids, or `payments` gaining a
row with the flag NULL, the shape is wrong — stop and re-contract. Both are cheap to check and
both are in D.

---

## E. Ordering and deploy

**Edge functions only. No migration. So the `scripts/deploy-migrations.sh` wrapper is not
involved** — but its precondition still holds: **deploy from trunk, after landing on trunk**
(0098/0099 drift lesson, `docs/handoff-announcer.md:157-161`). Commit gate first, from `app/`:
`tsc --noEmit`, `check-rpc-contracts.mjs`, `check-route-native-imports.mjs`.

**E.0 — the ordering premise, restated (F2).** Revision 1's order existed to protect a shipped
population from a false-expiry 409. **There is no shipped population** (§B.5; `awaiting-sean.md`
§0-octies `:502` *"no build ever shipped"*, EAS builds re-verified at 0) **and there is no
false-expiry 409** (an old build never renders the button that would send the call). So the order
below is chosen for tidiness, not for safety, and **the whole sequence — both functions, the
client, and `scripts/e2e.mjs` — lands in ONE session.**

**E.1 — `transition-booking` FIRST (the C.2 deletion).** Still fine to go first, for the reason
that is now measured rather than assumed: **no client calls it.** Today's build only reaches
`payment_ok` from `pay.tsx:171`, and only under `screen === 'mock_pending'`, i.e. only for a
booking sitting in `payment_hold` — which after E.2 nothing produces, and before E.2 is produced
only by a build nobody is running. Verify live afterwards by reading the function version
(`supabase functions list` → v34) — **never by invoking it**; the behavioural check belongs to the
Deno pins (N2, N9) and to E.4's single controlled run.

⚠ **Between E.1 and E.2 there is a real, narrow window** and it should be named rather than
discovered: a widget-path hold created in that gap lands in `payment_hold` with `payment_ok`
already deleted, so nothing can move it and `e_hold` reaps it silently at 30 minutes (B.4's exact
strand). With zero installed builds nobody can enter it, but **keep the gap to minutes, not
hours** — deploy E.2 immediately after E.1, and do not stop for review between them. If the two
must be separated for any reason, invert the order: E.2 first is strictly safer, and E.1's only
cost of going second is that `payment_ok` briefly still exists while nothing calls it.

**E.2 — `create-booking-hold` SECOND (C.1 + C.3).** Deploy → `functions list` shows v10.
`functions deploy` printing "No change found" is the parity oracle if you need to confirm what is
running (`docs/pre-charging-checklist.md` §3 / production-verification memo).

**E.3 — verify live, SELECT-only.** In this order, stopping at the first surprise:

1. `select payments_live_since from ops_flags;` → still NULL. *(The change is inert if this is
   ever non-NULL; know before you interpret anything.)*
2. `select count(*) from payments;` → **0**, before and after.
3. `select count(*) from billing_keys;` → **0** (i.e. every owner is on the widget path).
4. `select status, count(*) from bookings group by status;` → compare against A.4's baseline;
   `payment_hold` must be **0** and stay 0.
5. `select count(*) from slot_holds;` → holds are still created and still reaped by `purge-holds`.
6. `functions list` → `transition-booking` v34, `create-booking-hold` v10.

**E.4 — one controlled end-to-end, on a throwaway user, self-cleaning** (the 0111 D-10 idiom:
create, assert, delete, verify the delete). This is the only place a function is invoked, and it
is invoked as the *product*, not as a probe of the charge machine. ⚠ **Never call
`collect-charges` directly — it mints and charges** (`docs/pre-charging-checklist.md:271-273`).
Assert: booking reaches `matching`, appears in `marketplace_open_requests` for a runner claim, 0
`payments` rows throughout.

### E.5 — ui2's client follow-up

`app/app/owner/request.tsx`, `app/app/owner/pay.tsx` and `app/app/owner/home.tsx` are **ui2's
exclusive** surfaces (REGISTRY in-flight table); `app/src/lib/api.ts` is shared at function level,
tell-before-edit. **ui2 must not start before E.2 is verified live.**

#### 🔴 E.5.1 — `/owner/pay` is the only place THREE non-payment effects run (F1)

**This is the finding that made the reviewer return FIX-CONTRACT-FIRST, and revision 1 missed it
entirely.** Revision 1 described the client change as *"stop pushing `/owner/pay`; go straight to
the radar"* — one line. **It is not one line.** `postConfirm` (`pay.tsx:126-166`) is the only place
in the app where three effects happen, none of which is a payment, and all three die with the
screen unless they are deliberately moved.

The block's own header says so (`pay.tsx:116-120`): *"request.tsx의 결제 직후 로직이 통째로 여기로
옮겨왔다"* — the logic was moved **into** `pay.tsx` during the wave-2 review, to fix C3 and C4. It
has to move back out, and the C3/C4 reasons no longer apply because after C.1 the booking is
already `matching` when the hold returns.

**(i) `draft.bookingId = bookingId` — `pay.tsx:127`.**
`request.tsx` **never sets it on success.** It sets `holdBid.current` (`:471`) and clears
`draft.bookingId = null` only on failure (`:477`). `pay.tsx:127` is the sole writer.
**This is the hard requirement:** `radar.tsx:68` reads
`(typeof bidParam === 'string' && bidParam) || draft.bookingId`, and `radar.tsx:83-86` bounces to
`/owner/home` when it is empty (*"부킹 없이 진입하면 홈으로"*). **So a `request.tsx` that routes to
the radar without setting `draft.bookingId` does not show a radar — it shows the home screen**,
which is the most visible possible regression and the easiest to ship by accident.
`matching.tsx:141` (`const live = !!draft.bookingId`) fails the same way.
*(Passing `bid` as a route param also satisfies `radar.tsx:68` — but `matching.tsx` reads only the
draft, so set the draft regardless. Do not rely on the param alone.)*

**(ii) `createRecurringSeries(bookingId)` — `pay.tsx:139`. The ONLY call site in the app.**
Measured: `grep -rn createRecurringSeries app/` returns the definition (`api.ts:390`), the import
and this one call. Meanwhile **`request.tsx` renders the 매주 반복 toggle** (`:942-955`, state at
`:262`) and passes `recurring: '1'` through the push at `:500`. **Delete the screen without moving
this and the toggle becomes a DEAD CONTROL** — a visible switch the user turns on that has no
effect anywhere in the product. That is a direct hit on the honesty law (*"No dead buttons — every
visible action has a real route/effect in every state"*), and the repo has the regression on record:
`pay.tsx:116-120` names it **C4** — *"createRecurringSeries가 확정 전에 돌아 미결제 주간 예약이
생성됐고"*. Shipping the toggle with nothing behind it is a worse C4 than the original.

**(iii) `requestRunner(bookingId, draft.preferredRunnerId)` — `pay.tsx:149`. The 「이 러너와
예약하기」 promise.** `draft.preferredRunnerId` is set in four places —
`app/app/runner-profile/[id].tsx:159` and `:505` (the leaderboard → profile → book path),
`home.tsx:256` (rebook the last runner), `report.tsx:482` (book this runner again) — and
`pay.tsx:149` is where that promise is **kept**. Drop it and every one of those four entry points
silently becomes an ordinary open-pool booking: the owner picked a runner, was told nothing, and
got the pool.

⚠ **`matching.tsx`'s auto-nominate is NOT a safety net — do not rely on it.** It exists
(`matching.tsx:208-223`: `autoRef`, `requestRunner(draft.bookingId, pref)`) and revision 1 would
have let a reader assume it catches this. **It is not reached under trunk's flow**, because the
push carries `after: 'radar'` (`request.tsx:500`, added by `cf162b1`) and the owner lands on
`/owner/radar`, not `/owner/matching`. It also gates on `!!draft.bookingId` (`:141`, `:211`) —
which (i) has just established is unset. Two independent reasons it does not fire.

🔵 **ANNOUNCER DECISION — all three move into `request.tsx`, immediately after a successful hold.**
Not into the radar, not into a new screen, and not left to the server. The hold response now means
the booking is **already `matching`** (C.1), so every C3/C4 objection that justified moving them to
`pay.tsx` is gone: there is no unpaid window to create a series in, and no `payment_hold` state for
a nomination to 409 against. **The four moves, in this order, in `request.tsx` right after the
`createBookingHold` await (`:449-472`):**

1. **`draft.bookingId = res.booking_id`** — unconditional, first, before any await that could
   throw. Everything downstream reads it.
2. **if `recurringOn` → `await createRecurringSeries(bookingId)`** — keeping `pay.tsx:136-143`'s
   error shape verbatim: a failure **must not** block the booking (it already exists) and **must
   not** be swallowed. Reuse the existing Alert copy: *"이번 예약은 확정됐지만 매주 반복 설정에
   실패했어요 — 다음 예약 때 다시 켜주세요"*.
3. **if `draft.preferredRunnerId` → `await requestRunner(bookingId, draft.preferredRunnerId)`** —
   keeping `pay.tsx:144-159`'s shape: clear `preferredRunnerId`/`preferredRunnerName` on success,
   and on failure **tell the user** (*"…우선 요청을 보내지 못했어요 — 매칭 화면에서 다시
   골라주세요"*) rather than warn-swallowing. That is the recorded **C3** regression.
4. **Route per `after`** — default `'radar'`, exactly as `request.tsx:500` already decides. Keep
   `pay.tsx:160-165`'s one branch that is not routing-by-`after`: a **successful nomination** goes
   to `/owner/schedule` with the 지명 요청 전송 alert, because there is nothing to watch a radar for
   when a specific runner has been asked.

**Net:** `request.tsx` gains what `pay.tsx:126-166` already does, minus `confirmPayment`, minus the
`owner === 'server'` Toss branch (`:128-135` — dead while `TOSS_ENABLED=false`, and it belongs to
the money session's card-register slice if it is ever revived).

**`pay.tsx`: `예약 확정하기` dies, and the screen becomes unreachable for the pilot.** Nothing
routes to `/owner/pay` once `request.tsx:500` stops pushing it. Whether the file is deleted or kept
as a post-run receipt is **not this contract's call and not ui2's alone** — see §F.3. Note for
whoever retires it: `app/app/dev/pay-lab.tsx:12` imports `PayScreen, PayView` from it, and **a
dev-only screen can crash a production launch** (CLAUDE.md; `check-route-native-imports.mjs`).

#### E.5.2 — the rest of the client slice

1. `request.tsx:500` (origin @ `cf162b1` — **not** `:395`/`:406`/`:493`, which older docs say) —
   stop pushing `/owner/pay`. The 예상 금액 is shown **once**, earlier in the flow, per ruling #1 —
   it is `bookings.total_price`, a real frozen number, and it must not be styled as a receipt.
2. ⟳ **`home.tsx` needs nothing** — its Find-Now hold + `/owner/pay` push are already gone on
   origin (A.7). **Re-grep before building anyway** (`createBookingHold` across `app/`), because
   this is exactly the fact that changed under a scout mid-flight; a subagent's finding is a
   snapshot. At `cf162b1` the answer is one call site, `request.tsx:449`.
3. `api.ts:360` — add `booking_status` (and `paid_path`) to `HoldResult`, and **branch on it**: if
   the server ever returns `payment_hold`, the client must say so rather than assume. This is what
   makes E.5.1's four moves conditional on a real fact instead of an assumption about C.1.
4. `api.ts:402-408` — delete `confirmPayment`, in the same slice as the server deletion (C.2).
5. **`scripts/e2e.mjs:232-236` moves in this same slice (F14).** It calls `payment_ok` as a
   **required** step and asserts the booking reaches `matching`. Under the one-move removal it
   breaks at exactly one moment, so there is exactly one thing to keep in sync: delete the
   `payment_ok` step and assert instead that the booking is **already `matching` when
   `create-booking-hold` returns** — which is a strictly better assertion, because it tests C.1's
   actual contract rather than a step that used to compensate for its absence.

**E.6 — claim an in-flight row before any edit.** Path-keyed, tree named:
`supabase/functions/transition-booking/index.ts`,
`supabase/functions/create-booking-hold/handler.ts`,
`supabase/functions/_test/booking_card_path_test.ts`, `supabase/tests/147_*.sql`,
`supabase/tests/146_booking_entry_suite.sql` (comment only), `scripts/e2e.mjs`. Client surfaces
(`request.tsx`, `pay.tsx`, `api.ts`) are ui2's rows to claim. **No `payment_ok.ts` row** — that
file is no longer created (C.2). Edge-function work has no migration number and no hook — the
in-flight table is the only interlock it has.

**E.6a — the comment fixes this slice owes (F12).** Six comments describe `payment_ok` as a live
step and become false the moment C.2 lands. They are **comment fixes inside this slice**, not
follow-up work, because a comment that names a deleted function is exactly the artifact this repo
keeps getting bitten by:

| file:line | what it says today |
|---|---|
| `app/src/lib/toss.ts:4` | *"the simulated path (transition-booking {action:'payment_ok'}), which is the ONLY route a booking has into `matching`"* — false twice over after C.1 |
| `app/app/owner/schedule.tsx:610` | *"TOSS_ENABLED=false, payment_ok writes no payments row"* — the conclusion survives, the mechanism named does not |
| `app/app/owner/pay.tsx:243` | *"오늘: 시뮬레이션 경로(transition-booking payment_ok) — 예약이 matching으로 가는 유일한 문"* — dies with the button |
| `supabase/migrations/0026_recurring.sql:10` | *"현재 payment_ok 모의 단계라 크론 생성 예약은 결제 단계 없이 matching/runner_pending 직행"* — ⚠ **a shipped migration: do NOT edit the file.** Note it in 147's header instead (C.5.0 is where its fact now lives) |
| `supabase/functions/create-booking-hold/handler.ts:35` | *"§2's Toss widget (today: the mock `payment_ok`) moves it"* — the §G.3 rewrite |
| `supabase/functions/create-booking-hold/handler.ts:242` | *"The CAS is the statement `payment_ok` uses (transition-booking:42-46)"* — the statement outlives the caller; say that instead |
| `supabase/functions/transition-booking/index.ts:3` | the action list in the file header (deleted by C.2 itself) |

**E.7 — the gate sequence this slice owes** (money-adjacent state machine): contract →
adversarial reviewer ≠ author who **executes** the attacks in D → fixes → harness (all suites,
plus 147) → Deno ≥ 191 + the new pins → mutation-verify at least N4, N6, N7, **N9, N10 and P8**
(the three that exist only because the review found them, and are therefore the three most likely
to be written green-by-default) → land on trunk →
deploy E.1/E.2 → verify E.3/E.4 → record. `/autoplan` is the standing gate for money-path changes
(0059 doctrine); this is money-adjacent rather than money-moving, and the cheap answer is to run
it anyway.

---

## F. Facts only Sean holds — true lookups, nothing else

Three, and they are genuinely his. **Nothing in §C waits on them except C.3's shape**; the pilot
change (C.1, C.2) is fully determined by ruling #1 and can proceed.

**F.1 — post-flip, may an owner with no linked card create a booking?**
- **(a)** Refuse at booking with an inline card-link step (this contract's C.3; matches
  `card-registration-placement.md:6` — *"inline at first booking"*).
- **(b)** Let them book; the run happens; the settle charge fails on "no billing key" and
  `owner_has_unsettled_charge` locks the account until they fix it (Alt‑3). One run is given away
  per owner, bounded and recoverable.

Both are defensible. It only needs answering before the flip, and it decides whether C.3 exists.

⚠ **Two things the reviewer established that this question must be asked WITH, or the answer will
be half an answer:**

- **(a) bounds NEW ENTRIES ONLY (F4).** A refusal at booking-creation cannot reach the bookings
  that already exist on flip day. The mint keys on **run end** (`0084:265-266`), so every in-flight
  card-less booking whose run finishes after the flip becomes a failed charge → an owner
  notification → a debt lock, no matter which way F.1 is answered. **That needs its own cut-over
  rule** (C.3a's shapes (i)/(ii)/(iii)) and it is the **money session's** slice.
- **The answer applies to TWO surfaces, not one (F10).** `generate_recurring_bookings` runs the
  same money gate in the background (`0111:339-355`) and answers it differently **on purpose** —
  it **pauses with a notification** rather than refusing, because a cron has no screen on which to
  show a card sheet. If F.1 is answered **(b)**, C.3 is deleted **and** 0111's ⓒ `no_card` arm must
  change with it. State the answer once, apply it to both, and say which surface expresses it how.

**F.2 — is the pilot's manual transfer arranged before or after the run?** Ruling #1 places the
*screen* after the run. The money is moved off-app by Sean, so only he knows whether the owner is
asked to transfer before the first run or after each one. It changes copy, not code — but the
copy is a money statement and the honesty laws bind it.

**F.3 — re-scoped (F1): where do 리커링 and 지명 live once the screen is gone?** Revision 1 asked
this as *"does `pay.tsx` become a receipt or is it deleted?"* — which quietly left the screen's
**three non-payment effects** unowned, as if deleting the file only deleted a payment step. It does
not (§E.5.1).

**The part that is NOT Sean's, and is answered here: 리커링 · 지명 · `draft.bookingId` · routing all
move to `request.tsx`, immediately after a successful hold.** 🔵 Announcer decision, recorded in
§E.5.1 with the exact order and the error shapes to preserve. Nobody needs to ask about this again,
and nobody may ship the reroute without it — the 매주 반복 toggle becoming a dead control is a
straight honesty-law violation, and a nomination silently degrading to open-pool matching is worse
because the owner was told it worked.

**The part that IS his — and it is now a smaller question:** with the side effects moved out and
`예약 확정하기` dead, `/owner/pay` becomes **unreachable for the pilot**. Does the file get deleted,
or kept as a **post-flip receipt** surface? Ruling #1 says *"the pay/notice screen moves to the END
of the journey"* — a notice screen after the report is a design he may want, or the report card may
absorb it. Nothing in this contract depends on the answer; it is safe to leave the file in place
and unreachable until the money session's card-register slice needs a receipt surface, at which
point the decision is theirs and Sean's together. **The money session's call, later** — the server
side does not assume the route disappears either way.

**Explicitly NOT for him:** §0-sexies is already answered (**option A**, 2026‑08‑15 — paperwork
started, charge machine kept, `docs/biz/payments-paperwork-checklist.md:8`). The 빌링키
charge-notice obligation is **counsel's**, riding in
`docs/biz/location-law-counsel-brief.md`. §0-nonies (price revision repaying unsettled work at
the new rate) is a real open money policy but is **independent of this contract** — nothing here
touches `compute_runner_payout`'s constants.

---

## G. Contradictions between artifacts

Found while measuring. Listed with what is true, so the next reader does not have to re-derive it.

**G.1 — `docs/payments.md` describes the deleted model as current, in four places.**
`:3` (*"현 상태: 결제는 시뮬레이션 (… confirmPayment = payment_ok 전이)"*), `:20-22` (widget at
"request pay" → `payment_ok`), `:27` (the manual bridge: operator calls `payment_ok` after
confirming a deposit — i.e. **payment before the run**), `:32`. All of it predates Sean's
2026‑08‑12 post-pay amendment **and** his 2026‑08‑19 ruling. **The file needs a superseded banner
or a rewrite**; `:27`'s operator step in particular is impossible as written (`payment_ok` is
`403 "owner only"` and no admin role exists — `payments-bridge-plan.md:70`).

**G.2 — `docs/plans/payments-toss-plan.md` contradicts itself, and the stale half is the one with
the diagram.** §0-bis (`:16-25`) is Sean's post-pay direction: nothing charged before or during
service. But §2's flow diagram at `:238-240` still shows `target: client → Toss widget →
confirm-payment → payment_hold → matching` — the pre-run model — and §0-ter at `:106-108` says
*"The fallback (no card) stops at payment_hold and takes §2's widget flow."* **That sentence is
the entire residue this contract deletes.** The plan is the design of record and should carry an
amendment line at §2 pointing at §0-bis and at this file.

**G.3 — `create-booking-hold/handler.ts` carries both models simultaneously, by design at the
time.** `:38-40` states the post-pay model for the card path (*"NOTHING is charged here. Under
post-pay the money moves at settle time; a booking is free to make, which is the whole model"*)
while `:34-36` keeps the widget path's pre-run step. Not a defect — it was written while both were
live. After C.1 the header must be rewritten, or it becomes the misleading artifact.

**G.4 — the ruling says "after handoff-back"; the charge machine already agrees, and no artifact
said so.** `settle_run_tx` refuses with `return_not_sealed` until the dog is confirmed home
(`0083:681-687`). Every artifact describing the charge point says "at settle" or "at run end";
none says "after the return handoff." **They are the same moment**, and that is a *confirmation*
of ruling #1, not a conflict — recorded because a reader checking "does the charge really happen
after handoff-back?" would otherwise conclude it does not.

**G.5 — `docs/handoff-announcer.md:120` leaves two shapes open; one of them is answered here.**
*"either the hold lands in `matching` directly for the pilot, or `payment_ok` becomes post-run and
something else gates matching."* The second is rejected (Alt‑4): there is nothing for the owner to
tap, because the charge is server-initiated and invisible per §0-bis.

**G.6 — `pay.tsx` is a booking-confirm screen wearing payment clothing, and a superseded plan
already said so.** Button `예약 확정하기` (`:447`) on a screen whose phase is `mock_pending`
and whose chip reads `MOCK · 준비 중` (`:31`). `docs/plans/payments-bridge-plan.md:17-18` — a file
that is otherwise **SUPERSEDED — DO NOT BUILD** — recorded the surviving finding: *"the '실결제는
발생하지 않았어요' line and the free 예약 확정하기 button must die on the Toss track too."* It is
still there.

**G.7 — pins and comments that will describe a world that no longer exists.**
`supabase/functions/_test/booking_card_path_test.ts:12-13` and `:138-147` (**this one actually
fails**, D.9.1) and `supabase/tests/146_booking_entry_suite.sql:382-410`'s D-11 header (assertion
survives, comment goes stale). Both are same-slice edits under CLAUDE.md's rule.

**G.8 — `docs/mock-status.md:62` and `docs/todo.md:56`** both list `payment_ok` as the booking
pipeline's payment step. Documentation drift; fix opportunistically.

**G.10 — every artifact naming a `/owner/pay` push line is now wrong, and one names a screen that
no longer exists.** The labs and handoff docs cite `request.tsx:395` (and this scout's own first
pass cited `:406`, from `8d33cde`; revision 1 then cited `:493`, from `58c20c2`). On origin at
`cf162b1` it is **`:500`**, and it now carries `after: 'radar'`. Worse for anyone
planning the client slice: `app/app/owner/home.tsx`'s Find-Now hold + push, which every artifact
written before `68a4257` lists as a second stranding path, **does not exist any more** (A.7).
Cite the live line, and re-grep `createBookingHold` before editing — this is the one fact in this
contract that changed while it was being written, which is precisely why it is written down
instead of quietly fixed.

**G.9 — stale `file:line` cross-references inside 0080/0101/0102 comments** (measured in
passing, none of them load-bearing here): `0080:1182`/`:1253` cite `collect-charges/handler.ts:107`
for `isDue` (actually `:152`); `0080:1202` cites `:110` (actually `:155`); `0080:504` cites `:75`
(actually `:98`); `0080:56` cites `settle-run/handler.ts:187` (the catch is at `:328`);
`0101:6`/`:41` cite arithmetic in `settle-run/handler.ts:135-187` that has since been deleted.
The **predicates** still agree; only the pointers rotted. Not this slice's to fix — recorded so a
future reader does not mistake a rotted pointer for a behavioural divergence.

---

## H. Review log — adversarial review, 2026‑08‑19 night

**Verdict: FIX-CONTRACT-FIRST.** A reviewer that was not the author re-measured this contract's
claims against the repo and production and returned 16 findings, two of them **BLOCK**. Every
finding is applied above. The contract was **not** rejected — its server shape (C.1, C.3, the
zero-migration boundary) survived intact; what failed was its account of the **client** and its
account of what an **old build** does. Both were wrong in the same direction: they assumed
`/owner/pay` was a payment screen, and it is a payment screen **plus three other things**.

| # | finding | resolution |
|---|---|---|
| **F1** | 🔴 **BLOCK.** `/owner/pay`'s `postConfirm` (`pay.tsx:126-166`) is the ONLY place three non-payment effects run: `draft.bookingId` (radar/matching depend on it), `createRecurringSeries` (the app's only call site — the 매주 반복 toggle dies without it), `requestRunner` (the 「이 러너와 예약하기」 promise, four entry points). `matching.tsx` auto-nominate does not catch it. | §E.5.1 rewritten as the four moves into `request.tsx` post-hold; §A.7 and §F.3 rewritten to match. 🔵 decision below. |
| **F2** | 🔴 **BLOCK.** B.5's stated mechanism was wrong. An old build never calls `payment_ok` — `payphase.ts:50` maps `matching → 'authorized'`, whose footer is `내 일정에서 확인하기` (`pay.tsx:467-469`); `예약 확정하기` is never rendered. The real failure is a **silent omission**, not a false 409. | §B.5 rewritten with the measured path; §C.2 collapsed to one move; §E.0/E.1 re-justified. 🔵 decision below. |
| **F3** | N5's stuck fixture must not be a club booking — `expire_unmatched_bookings` excludes them in both CTEs (`0080:937`, `:954`) and `100_wave3_suite.sql:349-381` pins `bh_club` as **staying** `payment_hold`. | N5 rewritten; fixture is now a lost-CAS / `compensate()` failure row. |
| **F4** | The flip-day exposure is the **in-flight stock**, not `payment_hold`: the mint keys on run end (`0084:265-266`) → `skipped_no_card` (`charge.ts:184-190`) → sweep to `failed` **with a notification** (`0080:818-837`) → debt lock (`0080:511-528`). F.1(a) bounds new entries only. | New §C.3a with three cut-over shapes, [REC] into §C.4 and §F.1. **Money session's slice.** |
| **F5** | Client line cites stale (trunk moved to `cf162b1`). | `request.tsx:449`/`:500`, `api.ts:360`/`:402-408`/`:3767` throughout; §A.7 now records that `:500` already carries `after: 'radar'`. |
| **F6** | The `ops_flags` read is a new hard dependency; fail-closed is right for money but must be **stated and pinned**. | Stated in §C.1; new pin **N10** (read error → 500, zero writes), mutation-verified in E.7. `service_role` SELECT verified. |
| **F7** | The deletion needs a surviving assertion. | New pin **N9** — `payment_ok` → 400 `unknown action` (`index.ts:397-398`). Merged into §C.2. |
| **F8** | No *"or later"* on an unordered enum. | N3 rewritten as an explicit seven-value allowlist matching `payphase.ts:50-56`, with `refund_pending` / `no_show` / `incident_review` handled by name. |
| **F9** | Abandonment stops being silent: the booking is in `marketplace_open_requests` (dog name/breed/weight/memo/photo/preferences/vaccinations, `0056:44-58`) from hold-creation; a force-quit can get a matched runner; `e_hold` becomes unreachable. | New **§C.1a**, named as an accepted consequence; mitigation is the owner's exit (P6 + P7). 🔵 accepted under the grant. |
| **F10** | *"Every booking passes through a hold"* was already false — `generate_recurring_bookings` (`0111:369-386`) inserts straight at `matching`/`runner_pending`. Post-flip it **pauses with a notification** (`0111:339-355`) rather than refusing. | New **§C.5.0**; the two surfaces differ deliberately (a cron has no screen); §F.1's answer must be stated once for both. |
| **F11** | C.1 closes the same-dog double-hold hole (`handler.ts:179` LIVE list excludes `payment_hold`; after C.1 the second is refused at `:191`). | New positive pin **P8**. |
| **F12** | Seven comments name `payment_ok` as live. | New **§E.6a** table — comment fixes **inside** this slice; `0026_recurring.sql:10` is a shipped migration and is noted in 147's header instead of edited. |
| **F13** | `party-membership-status-filter-contract.md` claimed 146 D-15 pins the bare `payment_ok` CAS. **False** — D-15 pins `request_runner` (`146:776`, `:797`); **nothing** pins `payment_ok`. | Fixed in both contracts; the O-5 side now says the removal deletes something nothing asserts → hence N9. |
| **F14** | `scripts/e2e.mjs:232-236` breaks at the removal. | Moves in the same slice (§E.5.2 item 5), and its replacement assertion is better: the booking is already `matching` when the hold returns. |
| **F15** | Do not call `ops_flags` "sealed" in a privilege sense — `anon`/`authenticated` hold DML; RLS-with-zero-policies (`0080:187`) is what closes it, same shape as 0111's R5 on `slot_holds`. | Stated in §C.1. Not this slice's to change, and this slice claims no credit for it. |
| **F16** | Contract-level: revision 1 read as finished when its client half was a sketch. | This log exists, and §E.5.1 is marked 🔴 so the next reader cannot skim past it. |

### The two announcer decisions

🔵 **Decision 1 — `payment_ok` is removed in ONE move, not two.** The two-move plan (idempotent
shim, then delete) existed solely to protect installed builds from a false-expiry 409. F2 measured
that **no such call is ever made** — the button is never rendered — and §B.5 establishes there are
**zero installed builds** (`awaiting-sean.md` §0-octies `:502`; EAS builds re-verified at 0). The
shim would have cost an extra deploy, a `payment_ok.ts` extraction, and a test file created to be
deleted. One move: the arm, the header line, `confirmPayment`, and `scripts/e2e.mjs` together,
with **N9** left behind as the assertion the deletion earns.

🔵 **Decision 2 — the three side effects move to `request.tsx`, immediately after a successful
hold.** Not to the radar, not to a new screen, not to the server. After C.1 the booking is already
`matching` when the hold returns, so the C3/C4 reasons that put them in `pay.tsx` in the first
place no longer hold. Four moves in order: set `draft.bookingId` → recurring if on → nomination if
present → route per `after` (radar default, schedule on a successful nomination). Full text and
error shapes in §E.5.1. **Consequence, accepted:** `pay.tsx`'s `예약 확정하기` dies and the screen
becomes unreachable for the pilot; whether it returns as a post-flip receipt is the money
session's call with Sean, not a blocker (§F.3).

### 📋 Smoke-list line for Sean's first hardware build

> **A pre-change build shows 예약이 확정됐어요 with no recurring series and no nomination —
> silently, with no error message at all.** That is the old binary meeting the new server
> (`payphase.ts` maps `matching → authorized`, so the confirm button is never drawn and
> `postConfirm` never runs), **not a regression. Update the build.** Nothing is written to defend
> against this in code, because the shipped population is zero and your device is the only place
> a stale binary can exist.
