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
**Client cites (`app/**`) are re-measured against `origin/redesign-v4` at `58c20c2`** — ui2 landed
`68a4257` (request.tsx rebuild) mid-scout and trunk moved again to `58c20c2` (0110). Everything in
§A.7 and §E.5 was re-read from origin, not from this worktree; the two client facts that **changed
during the scout** are flagged inline (`⟳`) rather than silently corrected, because a reader
comparing against an older handoff will otherwise think one of us is wrong.

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
`app/src/lib/api.ts:399-405`, `body: { booking_id: bookingId, action: 'payment_ok' }`, called
from `app/app/owner/pay.tsx:171` only. One more caller outside the app: `scripts/e2e.mjs:232-234`.

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

### A.7 The client, today — re-measured against `origin/redesign-v4` @ `58c20c2`

- **`app/app/owner/request.tsx` is the ONE hold-creation entry point in the whole app.** Measured
  by enumerating every `.ts`/`.tsx` blob on origin: `createBookingHold` is called at
  **`request.tsx:445`** and nowhere else (the only other hit is its own import at `:6`). The
  response is narrowed at `:467-468` to `booking_id` + `hold_expires_at`, and the push is
  **`request.tsx:493`**: `router.push({ pathname: '/owner/pay', params: { bid, …recurring, …exp } })`.
  The file states the hand-off in its own words at `:465` (*"홀드까지가 요청 화면의 몫이고, 확정과
  그 이후(리커링·지명·라우팅)는 /owner/pay가…"*) and again at `:562`.
- ⟳ **The Find-Now second entry point is GONE, and this correction is load-bearing.** At this
  worktree's base (`8d33cde`) `app/app/owner/home.tsx:599/:623` created its own hold and pushed
  `/owner/pay` — a second stranding path. On origin at `58c20c2` home.tsx (674 lines, rebuilt by
  ui2) has **no** `createBookingHold` and **no** `/owner/pay` route; its only booking route is
  `:261` / `:544` → `/owner/request`. So §E.5's client change is **one file, not two**. Recorded
  rather than silently deleted: any handoff or lab doc written before `68a4257` still describes
  two entry points and a push at `:395`/`:406`, and that is doc drift (§G.10) — cite `:493`.
- `app/app/owner/pay.tsx`: loads `fetchBookingCharge` (`:95-108`), derives phase from server
  status via `src/lib/payphase.ts:47` (`payment_hold: 'mock_pending'`), primary button reads
  **`예약 확정하기`** with `TOSS_ENABLED=false` (`:447`), and calls `confirmPayment(bookingId)`
  at `:171`. No timer; `exp` is a static string (`:80-83`). Copy at `:391-393`: *"결제 수단 연동
  준비 중 — 파일럿 기간에는 확정 시 실결제가 발생하지 않아요"*. No cancel CTA, and the file says
  why (`:455`): `payment_hold → cancelled_owner` is not in the map.
- `app/src/lib/api.ts` is **unchanged by the rebuild** at every line this contract depends on:
  `HoldResult` at `:357` (still no `paid_path`), `confirmPayment` at `:399-405` with
  `action: 'payment_ok'` at `:401`, and `fetchMyBookings`'s
  `.not('status','in','(draft,quoted,payment_hold)')` at **`:3732`** — **a booking sitting in
  `payment_hold` is invisible in 내 일정.**
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
`request.tsx:493` and every pilot booking — every owner has no billing key (production
`billing_keys` = 0 rows), so every booking is widget path — sits at `payment_hold`, where:

1. it is **not** in `marketplace_open_requests` (the view requires `status = 'matching'`,
   `0056_decline_log.sql:64-65`), so no runner ever sees it;
2. it is **invisible in the owner's 내 일정** (`api.ts:3732`);
3. `e_hold` reaps it **silently** at 30 minutes (`0080:948-953`; the silence is pinned by 100 W7).

The owner watches a radar for a run that no runner can see, and 30 minutes later it is gone
without a word. **That is the strand, and it is why ui correctly declined to reroute alone**
(`docs/handoff-announcer.md:80`, `:118-122`).

**B.5 A transitional hazard the ordering must handle.** If the server starts landing bookings in
`matching` while a build that still calls `confirmPayment` is on a phone, that call hits the CAS
with the row already at `matching` → 0 rows → the existing 409 *"결제 시간이 만료됐어요 — 예약을
다시 만들어주세요"* on a booking that is perfectly healthy. A false expiry message is exactly the
class of lie the honesty laws forbid. Shipped population is zero today
(`docs/decisions/awaiting-sean.md` §0-duodecies), which makes this cheap to get right now and
expensive later.

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

`service_role` holds SELECT on `ops_flags` (measured against production), so no grant change and
no RPC is needed.

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

### C.2 [REC] `payment_ok` stops being a client step — in two moves, not one

**Move 1 (ships with C.1).** Make the arm idempotent-success when the booking is already at or
past `matching`, using the repo's own established re-tap idiom (`enroute`,
`transition-booking/index.ts:252-257`; `arrived`, `:281-286`; `runner_accept`, `:58`):

- owner gate first, unchanged (`:30`);
- CAS on `payment_hold`, unchanged;
- 0 rows → **re-read** the row (never trust the stale `bk` snapshot — the `arrived` lesson at
  `:281-282`): if the status is `matching` or later, `return { unchanged: true }`; otherwise keep
  the existing honest 409 (`expired`, `draft`, cancelled … really are refusals).

This is honest — the caller asked for the booking to be at `matching` and it is — and it removes
the B.5 hazard **in both deploy orders**.

**Move 2 (after ui2's build ships).** Delete the `case "payment_ok"` block entirely. It then
falls to `index.ts:397-398` `unknown action payment_ok` → 400, and the action leaves the header
list at `index.ts:3`. Delete `confirmPayment` from `app/src/lib/api.ts:399-405` in the same
breath.

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
- The pre-flight order is unchanged and already written:
  `docs/biz/payments-paperwork-checklist.md` §5 and `docs/pre-charging-checklist.md` §2.1–2.6.

### C.5 What is NOT touched

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
- **N2 — `payment_ok` by a non-owner is refused.** Runner on their own booking, and a stranger →
  403 (`index.ts:19` party gate, `index.ts:30` owner gate). Deno.
- **N3 — `payment_ok` on a booking that is neither in `payment_hold` nor at/past `matching` is
  refused, not silently succeeded.** `expired`, `draft`, `cancelled_owner` → 409 with the existing
  sentence. Deno. *(This is the pin that keeps Move 1 from becoming "always return unchanged".)*
- **N4 — no charge exists while charging is off.** After a full booking→run→settle cycle with
  `payments_live_since` NULL: `select count(*) from payments` = 0, and `settle-run` reports
  `collection: "skipped_not_live"` (`settle-run/handler.ts:308-310`). SQL + Deno.
- **N5 — hold expiry still works, both arms, and `e_hold` is still silent.**
  `100_wave3_suite.sql` W7 must stay green unmodified. Add a new arm: a genuinely stuck
  `payment_hold` row (club booking, or a lost card CAS) older than 30 minutes is still reaped by
  `e_hold` (`0080:948-953`) with **zero notifications**, while a `matching` booking past its
  `scheduled_at` is reaped by `e_match` with the post-pay sentence (`0080:944`).
- **N6 — the post-flip card-less refusal writes nothing.** With `payments_live_since` set and no
  billing key: 409 `card_required`, and `bookings` / `slot_holds` row counts are **unchanged**.
  Deno (faked flag).
- **N7 — the transition map is unchanged.** `109_payments_suite.sql` P6 (`:232-255`) must stay
  green **unmodified**: `payment_hold → matching` survives and `payment_hold → completed` is still
  refused. If P6 needs editing, the change has grown beyond this contract — stop.
- **N8 — the card path's compensating delete still fires.** Force the CAS to 0 rows; assert both
  the booking and the hold are gone and the error sentence is the "남은 예약도 없어요" variant
  (`handler.ts:261-266`). Existing Deno coverage; must stay green for the widget path too.

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
  (`api.ts:3731-3732`); a `matching` booking passes. Client-observable; assert at the query level.

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
3. New `payment_ok_test.ts` — **and this requires a small extraction.** The arm lives in
   `transition-booking/index.ts`, which has `Deno.serve` at module top level and therefore
   **cannot be imported by a test** (the stated reason `cancel_owner.ts` and `start_run.ts` are
   separate files — `index.ts:326-328`, `:334-337`). Move the arm to
   `transition-booking/payment_ok.ts` in Move 1, pin N2/N3 and the `{unchanged:true}` idiom, and
   delete the module in Move 2.
4. `settle_charge_test.ts` — must stay green unmodified; it owns "settlement happens, collection
   is skipped" and this contract must not perturb it.

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

**E.1 — `transition-booking` FIRST (Move 1).** The idempotent `payment_ok`. Deploying this first
means the C.1 change is safe in either order and cannot produce B.5's false-expiry message. Verify
live afterwards by reading the function version (`supabase functions list` → v34) — **never by
invoking it**; the behavioural check belongs to the Deno pins and to E.4's single controlled run.

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

**E.5 — ui2's client follow-up, sequenced so nothing strands.** `app/app/owner/request.tsx` and
`app/app/owner/home.tsx` are **ui2's exclusive** surfaces (REGISTRY in-flight table);
`app/src/lib/api.ts` is shared at function level, tell-before-edit. **ui2 must not start before
E.2 is verified live.** Named as a separate item, not part of this contract's build:

1. `request.tsx:493` (origin @ `58c20c2` — **not** `:395`/`:406`, which older docs still say) —
   stop pushing `/owner/pay`; go straight to the radar. Its own comments at `:465` and `:562`
   describe the hand-off being removed, so they move with it. The 예상 금액 is shown **once**,
   earlier in the flow, per ruling #1 — it is `bookings.total_price`, a real frozen number, and it
   must not be styled as a receipt.
2. ⟳ **`home.tsx` needs nothing** — its Find-Now hold + `/owner/pay` push are already gone on
   origin (A.7). **Re-grep before building anyway** (`createBookingHold` across `app/`), because
   this is exactly the fact that changed under a scout mid-flight; a subagent's finding is a
   snapshot. At `58c20c2` the answer is one call site, `request.tsx:445`.
3. `api.ts:357` — add `booking_status` (and `paid_path`) to `HoldResult`, and **branch on it**:
   if the server ever returns `payment_hold`, the client must say so rather than assume.
4. Ship a build. **Only then** does Move 2 (delete the `payment_ok` case; delete
   `confirmPayment`) become safe.
5. `pay.tsx`'s role post-pilot is ui2's + Sean's design call, not this contract's (§F.3). Note
   for whoever retires it: `app/app/dev/pay-lab.tsx:12` imports from it, and a dev route can crash
   a production launch (CLAUDE.md, `check-route-native-imports.mjs`).
6. `scripts/e2e.mjs:232-234` calls `payment_ok` as a required step and must be updated with
   Move 2, or the e2e script starts failing for a correct reason.

**E.6 — claim an in-flight row before any edit.** Path-keyed, tree named:
`supabase/functions/transition-booking/index.ts` (+ the new `payment_ok.ts`),
`supabase/functions/create-booking-hold/handler.ts`,
`supabase/functions/_test/booking_card_path_test.ts`, `supabase/tests/147_*.sql`,
`supabase/tests/146_booking_entry_suite.sql` (comment only). Edge-function work has no migration
number and no hook — the in-flight table is the only interlock it has.

**E.7 — the gate sequence this slice owes** (money-adjacent state machine): contract →
adversarial reviewer ≠ author who **executes** the attacks in D → fixes → harness (all suites,
plus 147) → Deno ≥ 191 + the new pins → mutation-verify at least N4, N6 and N7 → land on trunk →
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

**F.2 — is the pilot's manual transfer arranged before or after the run?** Ruling #1 places the
*screen* after the run. The money is moved off-app by Sean, so only he knows whether the owner is
asked to transfer before the first run or after each one. It changes copy, not code — but the
copy is a money statement and the honesty laws bind it.

**F.3 — does `pay.tsx` become the post-run receipt/notice screen, or is it deleted?** Ruling #1
says *"the pay/notice screen moves to the END of the journey"* — a notice screen after the report
is a design he may want, or the report card may absorb it. ui2 + Sean; named here only so the
server side does not assume the route disappears.

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
pass cited `:406`, from `8d33cde`); on origin at `58c20c2` it is **`:493`**. Worse for anyone
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
