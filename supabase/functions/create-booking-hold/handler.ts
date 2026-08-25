// 원자적 슬롯 홀드 + 서버 가격 산정 (calendar.md 더블부킹 방지).
// input: { dog_id, route_id?, address_id?, scheduled_at, km, pace_label?, addons: string[] }
//        ⚠ NO `runner_id` — see the §0111 block below. A body carrying one is a 400.
// out:   { booking_id, hold_expires_at, total_price, paid_path, booking_status }
//        `booking_status` is what the row IS when this function returns ("matching" | "payment_hold").
//        A client must never have to infer whether a further call is required — see the §O-5 block.
//
// ═══ [0111] THIS FUNCTION NO LONGER NOMINATES A RUNNER ═══════════════════════════════════════
// It used to take `runner_id` from the REQUEST BODY and, after an existence check against
// `runners` that the FK already enforced, write it into both the booking and the `slot_holds` row
// — as `service_role`, so nothing else stood behind it. That is the same forgery `0111` closes on
// the SQL side (`bookings owner insert` / the `recurring_series` mirror), reached through a
// trusted path instead of a client one: `runner_availability_rules` is readable by any logged-in
// user, so an attacker read a victim's published schedule, picked a passing slot, and landed
// `owner_id = attacker, runner_id = victim` — which is what `is_booking_party()` reads.
//
// Blast radius MEASURED, not reasoned: no call site sends the field. The parameter type at
// `app/src/lib/api.ts:359-378` has no `runner_id`, and neither caller
// (`app/app/owner/request.tsx:358-375`, `app/app/owner/home.tsx:599-611`) sends one. Nomination
// happens AFTER payment, through `transition-booking` action `request_runner` — owner-gated,
// state-gated, real-runner-checked, clash-checked, atomic CAS. `transition-booking:37-42` already
// records that the `payment_hold → runner_pending` branch was dead code because the transition map
// forbids it, i.e. a body-supplied `runner_id` never had a legitimate destination anyway.
//
// ⚠ REAL SEMANTIC CHANGE, stated here rather than discovered later: **the hold row no longer names
// a runner.** A nominated hold used to block that runner's slot through `is_slot_available`
// (`0003_availability.sql:58+`); it now blocks nobody. That is a no-op in practice (no client ever
// nominated at hold time) but it is a genuine change to what a `slot_holds` row means.
//
// Split out of index.ts for the same reason confirm-payment (0076) and settle-run were: while
// `Deno.serve` runs at module top level no test can import this code. The pre-slice body below is
// unchanged — the charge slice added two owner-level facts near the top (the debt lock and the
// billing-key lookup), O-5 added a third (the cutover flag), and the instant CAS lives at the
// bottom.
//
// ═══ [O-5] PAY AFTER THE RUN — the pilot has no pre-run payment step ═════════════════════════
// Sean's journey ruling #1 (2026-08-19): *"Payment comes AFTER the run and after handoff-back.
// Not between reserve and live."* Contract: `docs/contracts/pay-after-run-contract.md` §C.1/§C.3.
//
// The rule this function now implements, in one line: **while `ops_flags.payments_live_since` is
// NULL, a booking is free to make, so BOTH paths CAS `payment_hold → matching` in this request.**
//
//  · charging OFF (the pilot, and the state of production today) — widget AND card both land in
//    `matching` before this function returns. `payment_hold` is a transient instant state for
//    everyone, exactly as it already was for the card path. No new transition-map edge (105 E7 /
//    109 P6 unchanged), no migration, no enum value.
//  · charging ON, card    — unchanged: CAS to `matching`, and the money moves at settle time via
//    `mint_settle_charge_intent`. NOTHING is charged here, ever, by any path.
//  · charging ON, widget  — REFUSED before any write, `card_required` (§C.3). It must not silently
//    become a stranded `payment_hold` again: the screen that used to move that row is deleted.
//
// ⚠ What this deliberately gives up, stated rather than discovered (§C.1a): an abandoned booking
// used to die SILENTLY at 30 minutes (`e_hold`, 0080:948-955, pinned by 100 W7). It is now
// `matching` from hold-creation, so it is in `marketplace_open_requests` immediately and instead
// expires at `scheduled_at` via `e_match` WITH a notification whose post-pay arm already says the
// honest thing (0080:944-946). The owner is not trapped: `matching → cancelled_owner` is in the map
// and `marketplace_cancel_fee` returns 0 on an unmatched booking (0066:46/:77) — under the old flow
// they had no cancel CTA at all. Accepted with the exit pinned (contract P6/P7).
//
// ⚠ `e_hold` therefore has no pilot input any more. Its pin stays green because 100 W7 inserts its
// fixtures directly in SQL; the reaper is still correct, the product just stopped producing rows
// for it (a lost card CAS whose `compensate()` fails is the one residual that still can).
//
// ⚠ This is NOT the only entry that skips the hold, and it never was: `generate_recurring_bookings`
// (0111:369-376) has inserted straight at `matching`/`runner_pending` since 0026. C.1 does not
// invent a shape — it makes this function CONSISTENT with the one the product already had.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, HttpError, PRICING } from "../_shared/ctx.ts";

export async function createBookingHold(req: Request, db: SupabaseClient) {
  const uid = await caller(req, db);
  const b = await req.json();

  // ── [0111] the body may not nominate a runner — REFUSED, not stripped ────────────────────────
  // Refused at the validation head, before any DB work, so this can never pass by accident through
  // a later failure. Silently dropping the field is what "delete the `if (b.runner_id)` block"
  // literally produces, and it is worse than it looks: a caller that sends `runner_id` and gets a
  // 200 WITH A BOOKING ID has every reason to believe the nomination happened, and nothing in the
  // response says otherwise. This repo's honesty law is about exactly that shape. No client sends
  // the field today (measured: zero call sites), so a 400 cannot break anyone — it can only catch
  // a future caller, or someone probing the surface, at the moment they are wrong instead of an
  // hour later.
  // An explicit `runner_id: null` is deliberately NOT refused: it asks for no runner, which is
  // exactly what the server now always does, so there is no divergence between what the caller
  // asked for and what happened — the only thing this 400 exists to prevent.
  if (b.runner_id !== undefined && b.runner_id !== null) {
    throw new HttpError(400, "runner_id_not_accepted_here");
  }

  if (!b.dog_id || !b.scheduled_at || !b.km) throw new HttpError(400, "missing fields");

  // ── km bounds (0082 review) ───────────────────────────────────────────────────────────────────
  // `km` was truthy-checked and then multiplied straight into money (`PRICING.perKm` below) and
  // into the slot window. A string, a NaN, a negative or a 500 sailed through: `!b.km` only
  // rejects 0/undefined. The dial the client actually offers is 1–10km in 0.5 steps
  // (app/app/owner/request.tsx KM_MIN/KM_MAX/KM_STEP) and `bookings.km` is numeric(4,1), so
  // anything else is either a broken client or someone poking the endpoint — 400 either way.
  // Strict on TYPE, not just value. Coercing (`Number(b.km)`) would silently accept "5" — the
  // arithmetic downstream happens to survive it, so the bug would be invisible until some path
  // concatenates instead of adds. The endpoint's contract says number, the real client always
  // sends one (KM_VALUES are numbers), and a string here means a broken caller worth telling.
  const km = b.km;
  if (typeof km !== "number" || !Number.isFinite(km) || km < 1 || km > 10 ||
      Math.round(km * 2) !== km * 2) {
    throw new HttpError(400, "km out of range");
  }

  // ── 소유권 검증 (웨이브 3) — 이 함수는 서비스롤로 쓰므로 RLS가 대신 막아주지 않는다.
  // dog_id가 진짜 구멍이다: 0042 마켓플레이스 뷰가 dogs를 조인해 이름·견종·체중·메모·사진·성향·
  // 접종 이력을 '모든 활성 러너'에게 노출한다 → 검증 없는 dog_id는 남의 강아지 신상을 오픈 풀에
  // 게시하는 경로이자, 아래 같은-강아지 중복 예약 가드를 이용한 가용성 DoS다. 수락도 필요 없다.
  // address_id는 여기서 한 번, 0060 픽업 주소 RPC의 `a.owner_id = b.owner_id` 재검증에서 또 한 번 막힌다.
  // 메시지는 없는 행과 남의 행이 **같은 문장** — 존재 여부를 알려주는 열거 오라클 금지 (0054:73).
  // (비정형 uuid는 22P02로 0행처럼 도착한다 = '내 것이 아니다'로 접는 게 사실이다 —
  //  api.ts fetchBookingCharge의 22P02='부재' 판정과 같은 결론. 이 게이트는 페일-클로즈드다.)
  const { data: myDog } = await db.from("dogs")
    .select("id").eq("id", b.dog_id).eq("owner_id", uid).maybeSingle();
  if (!myDog) throw new HttpError(403, "forbidden");
  if (b.address_id) {
    const { data: myAddr } = await db.from("addresses")
      .select("id").eq("id", b.address_id).eq("owner_id", uid).maybeSingle();
    if (!myAddr) throw new HttpError(403, "forbidden");
  }

  // ── the route gate (0082) ─────────────────────────────────────────────────────────────────────
  // `route_id` was the last client-supplied FK this function inserted RAW, while its siblings above
  // are all checked — and the comment at :27 already says why that matters here: service role, so
  // RLS does not stand behind us. Three things were reachable: a nonexistent uuid became a 500 with
  // a raw Postgres message, a SUSPENDED route stayed bookable (which is what made 0082's one-line
  // 2am suspension advisory rather than real), and the candidate ceremony the plan specifies lived
  // only in the client, where it is a suggestion.
  //
  // Placed with the ownership checks, i.e. long before the insert and the card CAS at the bottom:
  // a route refusal must never be the thing that strands a card-linked booking in `payment_hold`
  // (§0-ter #7 — the failure mode `compensate()` exists to clean up after).
  let routeStatus: string | null = null;
  if (b.route_id) {
    const { data: route, error: rtErr } = await db.from("routes")
      .select("id, status").eq("id", b.route_id).maybeSingle();
    if (rtErr) throw new HttpError(500, rtErr.message);
    if (!route) throw new HttpError(400, "unknown route");
    routeStatus = route.status;

    if (route.status === "suspended" || route.status === "retired") {
      // The teeth behind `update routes set status='suspended'`. Without this the operator
      // suspends a flooded course and bookings keep arriving on it.
      throw new HttpError(
        409,
        "이 코스는 지금 예약할 수 없어요 — 점검을 위해 잠시 중단됐어요. 다른 코스를 골라주세요",
      );
    }
    // A candidate is bookable, but only ON PURPOSE (plan D-VIS=A): the client shows the amber
    // '점검 전 코스로 예약' confirm and sends the acknowledgement. Enforced here because a gate
    // that only exists in the client is not a gate — and because an owner must never be
    // auto-assigned a loop no dog has run.
    if (route.status === "candidate" && b.candidate_ack !== true) {
      throw new HttpError(409, "candidate_ack_required");
    }
  }

  // Analytics-grade, never money-bearing (0082 §C). `selection_origin` is the client's account of
  // HOW the owner got here, so it is range-checked but trusted; the exposure class is not — it is
  // read off routes.status above, because that is the number the PR-0 kill line divides by.
  const ORIGINS = ["auto", "carousel", "detail_cta", "quick_book"];
  if (b.selection_origin && !ORIGINS.includes(b.selection_origin)) {
    throw new HttpError(400, `unknown selection_origin ${b.selection_origin}`);
  }

  // ── the account lock (§0-ter, 0080 §F) — asked FIRST, before anything is computed or written ──
  // Derived, never cached: a failed charge (or a dispatched pending we never heard back about) on
  // a settled or cancelled-with-fee booking of this owner. It applies to EVERY owner and is not
  // keyed on the cutover flag, because pre-cutover the derivation is false by construction —
  // nothing is ever minted while `ops_flags.payments_live_since` is null, so the pilot's card-less
  // owners cannot accrue the rows this query looks for.
  // An RPC error refuses the booking, the same fail-closed shape `is_slot_available` below uses:
  // a money gate that fails open is not a gate. (Deploy order therefore matters — 0080 lands
  // before this function does.)
  const { data: locked, error: lockErr } = await db.rpc("owner_has_unsettled_charge", { p_owner: uid });
  if (lockErr) throw new HttpError(500, lockErr.message);
  if (locked) {
    throw new HttpError(
      409,
      "지금은 새 예약을 만들 수 없어요 — 정산이 끝날 때까지 새 예약이 잠겨요. 설정 > 결제 관리에서 결제 문제를 해결하면 다시 예약할 수 있어요",
    );
  }

  // Which path this booking takes is decided HERE, before a single row is written. Asking after
  // the insert would mean a failed read either strands a card-linked booking in `payment_hold`
  // (§0-ter #7) or needs a compensating delete for a question we could have asked first.
  // The key itself is never read — only its existence. (billing_keys is server-only, RLS-sealed.)
  const { data: card, error: cardErr } = await db.from("billing_keys")
    .select("profile_id").eq("profile_id", uid).maybeSingle();
  if (cardErr) throw new HttpError(500, cardErr.message);
  const paidPath: "card" | "widget" = card ? "card" : "widget";

  // ── [O-5 §C.1] the cutover flag — asked HERE, beside the billing key, before any write ────────
  // This is a NEW HARD DEPENDENCY and it is said out loud rather than left in the diff: before
  // O-5 this function never touched `ops_flags`, and after it **every booking in the product**
  // depends on that one row being readable. `service_role` holds SELECT on it (verified against
  // production), so no grant change and no RPC is needed.
  //
  // FAIL-CLOSED, the same shape as the debt lock above: a read error is a 500 and no booking is
  // created. Swallowing it into "assume charging is off" would be a money gate failing open —
  // it would hand out free bookings on the strength of a failed query. Pinned (contract N10),
  // not assumed, and mutation-verified.
  //
  // ⚠ Do NOT describe `ops_flags` as "sealed" in a privilege sense. `anon`/`authenticated` still
  // hold table-level DML on it; RLS-enabled-with-ZERO-policies (0080:187) is the only thing
  // standing there — the same shape as 0111's R5 finding on `slot_holds`. Nothing in this slice
  // changes that, and nothing in this slice may claim credit for it.
  const { data: flags, error: fErr } = await db.from("ops_flags").select("payments_live_since").maybeSingle();
  if (fErr) throw new HttpError(500, fErr.message);
  const chargingLive = !!flags?.payments_live_since;

  // ── [O-5 §C.3] post-flip, a card-less owner is REFUSED — never silently held ──────────────────
  // The day Sean sets `payments_live_since`, a widget-path booking would start stopping at
  // `payment_hold` again — with the screen that used to move it deleted. That is the original
  // strand rebuilt on a timer. So it refuses HERE, with the other pre-write gates: no booking row,
  // no `slot_holds` row, nothing to strand and nothing to compensate.
  //
  // The token comes first so a client can branch on it (`candidate_ack_required`'s shape), and the
  // sentence follows so a client that does not know the token still tells the owner something true.
  // The product answer is a one-step consent sheet inline at first booking, not an onboarding step
  // (`docs/decisions/card-registration-placement.md:6`).
  //
  // ⚠ UNREACHABLE TODAY (the flag is NULL in production) and pinned as defence against the flip
  // (contract N6). Whether refusing is the right product answer post-flip — versus letting them
  // book and catching them with the debt lock after one uncollected run — is Sean's open question
  // (contract §F.1), and his answer must be applied to `generate_recurring_bookings` in the same
  // breath: that surface PAUSES with a notification instead (0111:339-355), deliberately, because
  // a cron has no screen on which to show a card sheet.
  //
  // ⚠ What this does NOT cover: the bookings that already exist on flip day. The mint keys on RUN
  // END (0084:265-266), not on booking creation, so every in-flight card-less booking whose run
  // finishes after the flip becomes a failed charge → an owner notification → a debt lock. That
  // needs its own cut-over rule and it is the money session's slice (contract §C.3a).
  if (chargingLive && paidPath === "widget") {
    throw new HttpError(
      409,
      "card_required — 결제 카드를 먼저 등록해주세요. 카드를 등록하면 바로 예약할 수 있어요",
    );
  }

  const start = new Date(b.scheduled_at);
  // An unparseable date became `Invalid Date`, whose toISOString() throws a RangeError — a 500
  // with a stack instead of a 400 with a reason. Same class as the km bounds above.
  if (Number.isNaN(start.getTime())) throw new HttpError(400, "bad scheduled_at");
  const durMin = km * 8 + 25; // 러닝 + 픽업·인계 버퍼 (validated km — b.km may be a string)
  const end = new Date(start.getTime() + durMin * 60_000);

  // 같은 강아지 중복 예약 가드 — 겹치는 시간대의 살아있는 예약이 있으면 거절.
  // (라이브 커밋 상태만 검사 — draft/payment_hold 잔재나 종결 상태는 차단 사유가 아니다)
  //
  // [O-5 §C.1b] The LIVE list still deliberately excludes `payment_hold`, and that is still
  // correct: a stale hold must never block a retry. But it had a consequence nobody designed —
  // TWO overlapping holds for the same dog could both be created, because neither was `matching`
  // yet when the other ran this guard, and the second only failed later, if at all.
  // After §C.1 the first booking is ALREADY `matching` when the second request reaches this line,
  // so the second is refused below with the sentence that was always there. An undesigned
  // improvement is exactly the kind a later refactor removes without noticing it existed, so it is
  // pinned as a POSITIVE (contract P8) rather than left as a footnote. Do not "tidy" the list by
  // adding `payment_hold` to it — that would re-block the retry this exclusion exists to allow.
  const LIVE = ["matching", "runner_pending", "confirmed", "runner_enroute", "picked_up", "active"];
  const { data: near, error: nearErr } = await db.from("bookings")
    .select("id, scheduled_at, km")
    .eq("dog_id", b.dog_id).in("status", LIVE)
    .gte("scheduled_at", new Date(start.getTime() - 6 * 3600_000).toISOString())
    .lte("scheduled_at", new Date(end.getTime() + 6 * 3600_000).toISOString());
  if (nearErr) throw new HttpError(500, nearErr.message);
  const clash = (near ?? []).some((c) => {
    const cs = new Date(c.scheduled_at).getTime();
    const ce = cs + (Number(c.km) * 8 + 25) * 60_000; // 동일 실소요 공식
    return cs < end.getTime() && ce > start.getTime();
  });
  if (clash) throw new HttpError(409, "이 시간대에 같은 아이의 예약이 이미 있어요");

  // [0111] the body's 지정 러너 availability check lived here and is GONE, together with the
  // `runner_id` it read — see the file header. Nomination is `request_runner`'s job, and it runs
  // its own availability/clash gate at the moment it actually assigns.

  // 서버 가격 — 클라이언트 금액은 신뢰하지 않음
  const addons: string[] = Array.isArray(b.addons) ? b.addons : [];
  const addonFare = addons.reduce((s, k) => {
    if (!(k in PRICING.addons)) throw new HttpError(400, `unknown addon ${k}`);
    return s + PRICING.addons[k];
  }, 0);
  const distanceFare = Math.round(km * PRICING.perKm);
  const total = PRICING.ownerBaseFare + distanceFare + addonFare;

  // booking(draft→quoted→payment_hold) + hold, 한 흐름으로
  const { data: booking, error: bErr } = await db.from("bookings").insert({
    // [0111] runner_id is a LITERAL null, never `b.runner_id ?? null` — the body cannot reach this
    // column, and writing the expression would leave the field one careless edit from returning.
    owner_id: uid, dog_id: b.dog_id, runner_id: null,
    route_id: b.route_id ?? null, address_id: b.address_id ?? null,
    status: "draft", scheduled_at: start.toISOString(), km,
    pace_label: b.pace_label ?? null,
    addons: addons.map((k) => ({ key: k, price: PRICING.addons[k] })),
    base_fare: PRICING.ownerBaseFare, distance_fare: distanceFare,
    addon_fare: addonFare, total_price: total, min_fare: PRICING.minFare,
    // selection snapshot (0082 §C) — recommended_route_id is what the app would have picked on
    // its own, so override is DERIVED later as `route_id is distinct from recommended_route_id`
    // rather than asserted by the client. route_status_at_booking is written from the row we
    // just read, never from the body.
    recommended_route_id: b.recommended_route_id ?? null,
    selection_origin: b.selection_origin ?? null,
    route_status_at_booking: routeStatus,
    route_chips: b.route_chips ?? {},
  }).select("id").single();
  // [0119] A custody-gate refusal is the SERVER answering, not the server failing — it must reach
  // the client as a 409 with the token verbatim (the dog screen renders 미신고 as 「답해 주세요」,
  // which it cannot do from a generic 500). Every other insert error stays a 500: those ARE
  // failures. The token IS the message text because the trigger raises it as message_text.
  if (bErr) {
    const dangerTokens = [
      "dog_dangerous_undeclared",
      "dog_dangerous_custody_refused",
      "dog_dangerous_breed_conflict",
    ];
    const hit = dangerTokens.find((t) => bErr.message?.includes(t));
    if (hit) throw new HttpError(409, hit);
    throw new HttpError(500, bErr.message);
  }

  for (const s of ["quoted", "payment_hold"]) {
    const { error } = await db.from("bookings").update({ status: s }).eq("id", booking.id);
    if (error) throw new HttpError(500, error.message);
  }

  const expires = new Date(Date.now() + 5 * 60_000);
  const { error: hErr } = await db.from("slot_holds").insert({
    runner_id: null, owner_id: uid,   // [0111] the hold names no runner — see the file header
    starts_at: start.toISOString(), ends_at: end.toISOString(),
    expires_at: expires.toISOString(), booking_id: booking.id,
  });
  if (hErr) throw new HttpError(500, hErr.message);

  // What the row IS when we return. Derived from what actually happened below, never asserted:
  // if the CAS is skipped the answer is the truth (`payment_hold`), and the client is told so
  // instead of being left to infer it from `paid_path`.
  let bookingStatus: "matching" | "payment_hold" = "payment_hold";

  // ── the hold is in place, so close the (non-)payment step in this same request ────────────────
  // [O-5 §E.6a] This CAS is the statement `payment_ok` USED to share — `payment_ok` is deleted
  // (§C.2) and this is now the only writer of `payment_hold → matching` on this path. **The
  // statement outlived its other caller**; the edge itself is untouched and still pinned by
  // 109 P6. It is a CAS rather than a plain write for the same reason it always was: only a row
  // still sitting in `payment_hold` may move, so a lost race (0060's expiry sweep, a concurrent
  // sweep) shows up as 0 rows instead of quietly reviving a dead booking.
  //
  // WHO takes it: a card owner always, and — while charging is off — everyone else too (§C.1).
  // Written as two named conditions rather than `true` on purpose. Today the §C.3 gate above makes
  // `chargingLive && widget` unreachable, so this branch is in fact always taken; the day Sean
  // answers §F.1 with "let them book, the debt lock handles it" that gate is deleted and
  // `!chargingLive` becomes the load-bearing half. Collapsing this to an unconditional CAS now
  // would silently book card-less owners for free post-flip (contract Alt-3, rejected for this
  // slice) and there would be nothing left in the code saying a decision had ever been made.
  if (paidPath === "card" || !chargingLive) {
    const { data: matched, error: casErr } = await db.from("bookings")
      .update({ status: "matching" })
      .eq("id", booking.id).eq("status", "payment_hold").select("id");
    if (casErr || !matched || matched.length === 0) {
      // §0-ter #7/#15. A booking that takes this branch may NEVER be left in `payment_hold` — the
      // row would expire unspoken 30 minutes from now (e_hold, 0060/0080:948-955) with a slot held
      // against it. The reason used to be "a card owner has no widget to come back to"; after O-5
      // §C.1 it is stronger and simpler: **NOBODY has a widget to come back to**, `payment_ok` is
      // deleted and no client screen moves that row any more. So undo what this request made: the
      // hold first (it references the booking), then the booking. Then say so, out loud, instead of
      // returning a booking id that is about to rot.
      //
      // This is also the one residual that still feeds `e_hold` at all: a lost CAS whose
      // `compensate()` itself fails leaves a genuine stuck `payment_hold` row for the reaper.
      const cleaned = await compensate(db, booking.id, casErr?.message ?? "cas_zero_rows");
      // Two different truths, two different sentences. Claiming "남은 예약도 없어요" after a
      // compensating delete that ERRORED is a lie told on a money screen (honesty law) — and the
      // owner would then find a booking they were told does not exist. Nothing was charged either
      // way (nothing ever is here); the difference is whether anything survived.
      throw new HttpError(
        500,
        cleaned
          ? "예약을 만들지 못했어요 — 청구된 금액도, 남은 예약도 없어요. 잠시 후 다시 시도해주세요"
          : "예약을 만들지 못했어요 — 청구된 금액은 없어요. 다만 만들다 만 예약이 목록에 잠시 남을 수 있어요 (결제되지 않은 상태로 자동 정리돼요). 그대로 두고 다시 시도해주세요",
      );
    }
    bookingStatus = "matching";
  }

  return {
    booking_id: booking.id,
    hold_expires_at: expires.toISOString(),
    total_price: total,
    paid_path: paidPath,
    // [O-5 §C.1] Which path the owner is on (`paid_path`) and what the row IS (`booking_status`)
    // are two different questions, and the client used to be able to ask neither — it dropped
    // `paid_path` entirely and inferred the rest. A client must never have to GUESS whether a
    // further call is required, so the server states it.
    booking_status: bookingStatus,
  };
}

/**
 * Undo a half-made booking whose closing CAS did not land. (Named "card-path" before O-5 §C.1,
 * when the card path was the only one that CASed; the widget path takes this branch too now.)
 * Best-effort on each statement and loud on failure: the
 * caller is already about to throw, and turning a failed cleanup into a different exception would
 * only replace an honest error with a confusing one. A leftover row here is visible (a
 * `payment_hold` booking with no owner-facing id) and 0060's sweep still reaps it.
 *
 * Returns whether BOTH deletes succeeded — the caller's sentence is a claim about what is left,
 * and it may only make that claim when this function actually left nothing.
 */
async function compensate(db: SupabaseClient, bookingId: string, why: string): Promise<boolean> {
  console.error(`[create-booking-hold] card-path CAS failed booking=${bookingId} why=${why} — compensating`);
  const { error: hErr } = await db.from("slot_holds").delete().eq("booking_id", bookingId);
  if (hErr) console.error(`[create-booking-hold] hold cleanup failed booking=${bookingId}: ${hErr.message}`);
  const { error: bErr } = await db.from("bookings").delete().eq("id", bookingId);
  if (bErr) console.error(`[create-booking-hold] booking cleanup failed booking=${bookingId}: ${bErr.message}`);
  return !hErr && !bErr;
}
