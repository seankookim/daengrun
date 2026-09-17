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
// for it. (Before 0179 one residual remained — a lost card CAS whose `compensate()` failed. The
// CAS now runs inside `create_booking_hold_tx` and cannot lose, so that residual is gone too.)
//
// ⚠ This is NOT the only entry that skips the hold, and it never was: `generate_recurring_bookings`
// (0111:369-376) has inserted straight at `matching`/`runner_pending` since 0026. C.1 does not
// invent a shape — it makes this function CONSISTENT with the one the product already had.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
// [backend audit 2026-09-17 · L1] `internalError` keeps raw Postgres text out of the response
// body at the eight 500s below. The text still reaches the server log, where it was always the
// only audience that could use it; a constraint name in a Korean alert helps nobody and
// describes our schema to anyone who asks for it.
import { caller, HttpError, internalError, PRICING } from "../_shared/ctx.ts";

export async function createBookingHold(req: Request, db: SupabaseClient) {
  const uid = await caller(req, db);
  // A malformed or absent body is the CALLER's mistake, so it must not wear our 500 (backend audit
  // 2026-09-17 · M1). Unguarded, `req.json()` threw a SyntaxError straight past this function into
  // `handle()`'s catch-all and answered `500 internal` — a sentence that says our server broke when
  // nothing did, and one that sends the caller retrying a request that can never succeed. Same
  // guarded-parse idiom as `collect-charges/handler.ts:79` and `register-billing-key/handler.ts:295`.
  const b = await req.json().catch(() => { throw new HttpError(400, "bad_body"); }) ?? {};

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

  // ── [0179] the idempotency key — OPTIONAL server-side, validated when present ─────────────────
  // A double-submit used to make two bookings (backend audit 2026-09-17 §(a) #3). The client now
  // mints a v4 uuid per submit attempt and reuses it on a retry of the same payload; the
  // transaction below answers a replayed key with the SAME row. ⚠ Absent is allowed on purpose:
  // installed builds do not update on our schedule, and a 400 here would break every one of them
  // the day this deploys. NULL means 「no idempotency」 — the pre-slice behaviour, exactly. The 400
  // is owed the day the build carrying the client half is the oldest build in use (0179 header).
  // Present-but-garbage IS refused: a key we cannot store is a key we cannot replay, and saying so
  // beats silently creating an unreplayable booking.
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let clientRequestId: string | null = null;
  if (b.client_request_id !== undefined && b.client_request_id !== null) {
    if (typeof b.client_request_id !== "string" || !UUID_RE.test(b.client_request_id)) {
      throw new HttpError(400, "bad client_request_id");
    }
    clientRequestId = b.client_request_id;
  }

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
  // Placed with the ownership checks, i.e. long before the transaction at the bottom: a route
  // refusal must never be the thing that strands a card-linked booking in `payment_hold`
  // (§0-ter #7 — since 0179 the transaction rolls back rather than strands, but a refusal that
  // never reaches it is still the cheaper and the clearer answer).
  let routeStatus: string | null = null;
  if (b.route_id) {
    const { data: route, error: rtErr } = await db.from("routes")
      .select("id, status").eq("id", b.route_id).maybeSingle();
    if (rtErr) throw internalError(rtErr, "route_read");
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
  if (lockErr) throw internalError(lockErr, "debt_lock");
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
  if (cardErr) throw internalError(cardErr, "card_read");
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
  if (fErr) throw internalError(fErr, "flag_read");
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

  // ── [0179] THE WRITES ARE ONE TRANSACTION NOW: `create_booking_hold_tx` ══════════════════════
  // Everything from here down used to be this file's: the same-dog clash guard, the booking
  // insert, the draft → quoted → payment_hold ladder, the hold insert, the closing CAS, and a
  // `compensate()` that deleted what it could when the CAS lost — four statements plus a CAS, no
  // transaction, no idempotency key. Now the function does all of it in ONE transaction, keyed by
  // (owner, client_request_id): the same key names the same row (`unchanged: true`), a reused key
  // with a different slot or price is `request_mismatch`, the clash guard is atomic with the
  // insert it guards (an advisory lock per dog), and a raise anywhere rolls the whole hold back —
  // so there is nothing left to compensate, and the honest 500 below can say 「nothing is left」
  // and be right every time. The gates ABOVE this line stay here, in their pinned order.
  //
  // The function is service_role-only and takes the OWNER from us (the settle_run_tx shape): the
  // JWT was validated at the top of this function, and the body can never name the owner.
  // 서버 가격 — 클라이언트 금액은 신뢰하지 않음 (unchanged; the transaction stores what we hand it)
  const addons: string[] = Array.isArray(b.addons) ? b.addons : [];
  const addonFare = addons.reduce((s, k) => {
    if (!(k in PRICING.addons)) throw new HttpError(400, `unknown addon ${k}`);
    return s + PRICING.addons[k];
  }, 0);
  const distanceFare = Math.round(km * PRICING.perKm);
  const total = PRICING.ownerBaseFare + distanceFare + addonFare;

  const addonRows = addons.map((k) => ({ key: k, price: PRICING.addons[k] }));
  const routeChips = b.route_chips ?? {};
  // WHO closes payment_hold → matching: a card owner always, and — while charging is off — everyone
  // else too (O-5 §C.1). Two named conditions rather than `true`, for the reason the old CAS gave:
  // the day Sean answers §F.1 the card_required gate above is deleted and `!chargingLive` becomes
  // the load-bearing half; collapsing this to `true` now would book card-less owners for free
  // post-flip with nothing in the code saying a decision had been made.
  const closeToMatching = paidPath === "card" || !chargingLive;

  const { data: tx, error: txErr } = await db.rpc("create_booking_hold_tx", {
    p_owner: uid,
    p_dog: b.dog_id,
    p_scheduled_at: start.toISOString(),
    p_km: km,
    p_addons: addonRows,
    p_base_fare: PRICING.ownerBaseFare,
    p_distance_fare: distanceFare,
    p_addon_fare: addonFare,
    p_total_price: total,
    p_min_fare: PRICING.minFare,
    p_close_to_matching: closeToMatching,
    p_client_request_id: clientRequestId,
    p_route: b.route_id ?? null,
    p_address: b.address_id ?? null,
    p_pace_label: b.pace_label ?? null,
    p_recommended_route: b.recommended_route_id ?? null,
    p_selection_origin: b.selection_origin ?? null,
    p_route_status: routeStatus,
    p_route_chips: routeChips,
  });
  if (txErr) {
    // The function's raise tokens → the sentences the client already keys on (the clash sentence
    // is the one that was always here; `forbidden` is the ownership belt's word, above).
    switch (txErr.message) {
      case "forbidden":
        throw new HttpError(403, "forbidden");
      case "dog_slot_clash":
        throw new HttpError(409, "이 시간대에 같은 아이의 예약이 이미 있어요");
      case "request_mismatch":
        // The same key with a different slot or price: the client changed the request without
        // minting a new key. Not retryable as-is — the token first so a client can branch, the
        // sentence so an older one still says something true.
        throw new HttpError(409, "request_mismatch — 같은 요청으로 다른 내용의 예약을 만들 수 없어요. 처음부터 다시 시도해주세요");
      case "hold_close_failed":
        // The closing CAS moved 0 rows inside the transaction — unreachable on a row the same
        // transaction inserted, kept as the loud belt it always was. The whole hold rolled back,
        // so the flat sentence is TRUE now on every path: no charge (there never is here) and no
        // row survives. The old two-sentence split (「남을 수 있어요」) died with compensate().
        throw new HttpError(500, "예약을 만들지 못했어요 — 청구된 금액도, 남은 예약도 없어요. 잠시 후 다시 시도해주세요");
      case "not_signed_in":
        throw new HttpError(401, "unauthorized");
      case "missing_fields":
      case "km_out_of_range":
        throw new HttpError(400, txErr.message);
      default:
        throw internalError(txErr, "hold_tx");
    }
  }
  const row = tx as {
    booking_id?: unknown; hold_expires_at?: unknown; total_price?: unknown;
    booking_status?: unknown; unchanged?: unknown;
  } | null;
  if (!row || typeof row !== "object" || typeof row.booking_id !== "string" || typeof row.booking_status !== "string") {
    // A success with no booking id is not a receipt anyone may render (the honesty law).
    throw internalError({ message: `create_booking_hold_tx returned ${JSON.stringify(tx)}` }, "hold_tx:shape");
  }

  return {
    booking_id: row.booking_id,
    hold_expires_at: typeof row.hold_expires_at === "string" ? row.hold_expires_at : null,
    total_price: typeof row.total_price === "number" ? row.total_price : total,
    paid_path: paidPath,
    // [O-5 §C.1] Which path the owner is on (`paid_path`) and what the row IS (`booking_status`)
    // are two different questions; the server states both. On a REPLAY the status is whatever
    // the row has become since (it may be past `matching`), which is the truth the client needs.
    booking_status: row.booking_status,
    // [0179] present ONLY on a replay — absent, not false, so `Object.keys` of a fresh hold is
    // unchanged and no client learns a new field it did not ask about.
    ...(row.unchanged === true ? { unchanged: true } : {}),
  };
}
