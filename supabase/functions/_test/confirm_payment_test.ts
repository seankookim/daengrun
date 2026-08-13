// confirm-payment unit tests — every §2-7 branch (toss-plan §4-1, eng review T1).
//
//   deno test -A supabase/functions/_test/
//
// Mock drift is a known, accepted risk (plan §4-1): these assert OUR state machine against a
// hand-written Toss, not Toss itself. The sandbox matrix (§4-2) is the other half of the rail
// and is the thing that catches drift. Nothing here should ever be read as "the integration works".
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { confirmPayment } from "../confirm-payment/handler.ts";
import { FakeDb, FetchMock, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const OPS = "99999999-9999-9999-9999-999999999999";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const ORDER = "dr_order_1";
const KEY = "tviva_key_1";
const AMOUNT = 24900;

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");
Deno.env.set("OPS_PROFILE_ID", OPS);

const CONFIRM_URL = "api.tosspayments.com/v1/payments/confirm";
const isConfirm = (u: string) => u.includes(CONFIRM_URL);
const isCancel = (u: string) => u.includes("api.tosspayments.com") && u.endsWith("/cancel");
const isTransition = (u: string) => u.includes("/functions/v1/transition-booking");

function scene(over: { intent?: Row; booking?: Row } = {}) {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("payments", [{
    id: "pay-1", booking_id: BOOKING, order_id: ORDER, amount: AMOUNT,
    status: "pending", payment_key: null, refunded_amount: 0, raw: {},
    created_at: "2026-08-12T00:00:00Z", ...over.intent,
  }]);
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, status: "payment_hold", total_price: AMOUNT, ...over.booking,
  }]);
  db.seed("notifications", []);
  // 0077 독트린: create_recurring_series는 서비스 클라이언트에 절대 등록하지 않는다 —
  // 코드가 잘못 서비스 db로 부르면 `no rpc` 에러가 나 테스트가 그 실수를 즉시 드러낸다.
  return db;
}

/** 0077: 호출자 JWT 바인딩 클라이언트의 페이크 — recurring RPC는 이쪽으로만 온다. */
function userScene() {
  const udb = new FakeDb();
  udb.rpcs["create_recurring_series"] = () => ({ data: "series-1" });
  return udb;
}

const doneBody = (over: Record<string, unknown> = {}) => ({
  paymentKey: KEY, orderId: ORDER, status: "DONE", totalAmount: AMOUNT, method: "카드", ...over,
});

/** Default happy Toss: confirm → DONE, cancel → 200, transition-booking → 200. */
function tossOk(over: { confirm?: () => Response; cancel?: (n: number) => Response | Error; transition?: () => Response } = {}) {
  return new FetchMock()
    .on(isConfirm, over.confirm ?? (() => FetchMock.json(doneBody())))
    .on(isCancel, over.cancel ? ((_c, n) => over.cancel!(n)) : (() => FetchMock.json({ status: "CANCELED" })))
    .on(isTransition, over.transition ?? (() => FetchMock.json({ ok: true })))
    .install();
}

async function expectHttpError(fn: () => Promise<unknown>): Promise<HttpError> {
  try {
    await fn();
  } catch (e) {
    assert(e instanceof HttpError, `expected HttpError, got ${e}`);
    return e;
  }
  throw new Error("expected a throw, got a resolved value");
}

const pay = (db: FakeDb) => db.rows("payments")[0];

// ═══ happy path ════════════════════════════════════════════════════════════════════════════
Deno.test("happy path — confirms the intent, then CASes the booking payment_hold → matching", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const out = await confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never) as Row;
    assertEquals(out.ok, true);
    assertEquals(out.amount, AMOUNT);
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).payment_key, KEY);
    assertEquals(pay(db).raw.status, "DONE");
    assertEquals(db.rows("bookings")[0].status, "matching");
    // The intent row must be written BEFORE the booking moves — money always leaves a local
    // trace first. The op log is the only place that ordering is observable.
    const order = db.log.filter((l) => l.startsWith("update:"));
    assertEquals(order[0], "update:payments:1");
    assertEquals(order[1], "update:bookings:1");
    // Nothing was cancelled and the amount we sent came from our row, not the request body.
    assertEquals(net.countTo("/cancel"), 0);
    assertEquals(net.calls.find((c) => isConfirm(c.url))!.body.amount, AMOUNT);
  } finally {
    net.restore();
  }
});

Deno.test("happy path — the amount is OUR intent's, never the caller's", async () => {
  const db = scene();
  const net = tossOk();
  try {
    // A caller who says the price is ₩100 gets charged ₩24,900 anyway.
    await confirmPayment(req({ order_id: ORDER, payment_key: KEY, amount: 100 }, "owner_jwt"), db as never);
    assertEquals(net.calls.find((c) => isConfirm(c.url))!.body.amount, AMOUNT);
    assertEquals(pay(db).status, "confirmed");
  } finally {
    net.restore();
  }
});

Deno.test("happy path — Idempotency-Key is sent and is the server-minted order_id", async () => {
  const db = scene();
  const net = tossOk();
  try {
    await confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never);
    assertEquals(net.calls.find((c) => isConfirm(c.url))!.headers["Idempotency-Key"], ORDER);
    assertStringIncludes(net.calls.find((c) => isConfirm(c.url))!.headers["Authorization"], "Basic ");
  } finally {
    net.restore();
  }
});

// ═══ auth / party gates ════════════════════════════════════════════════════════════════════
Deno.test("anon → 401, and Toss is never touched", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() => confirmPayment(req({ order_id: ORDER, payment_key: KEY }), db as never));
    assertEquals(e.status, 401);
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "pending");
  } finally {
    net.restore();
  }
});

Deno.test("non-owner → 403 (party gate runs before the state gate and before Toss)", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "stranger_jwt"), db as never)
    );
    assertEquals(e.status, 403);
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "pending");
  } finally {
    net.restore();
  }
});

Deno.test("unknown order_id → 404 — this function completes intents, it never invents them", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: "dr_not_ours", payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 404);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("missing fields → 400", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() => confirmPayment(req({ order_id: ORDER }, "owner_jwt"), db as never));
    assertEquals(e.status, 400);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

// ═══ idempotency ═══════════════════════════════════════════════════════════════════════════
Deno.test("idempotent re-call — already-confirmed intent is a no-op success, not a second charge", async () => {
  const db = scene({ intent: { status: "confirmed", payment_key: KEY, raw: doneBody() } });
  const net = tossOk();
  try {
    const out = await confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never) as Row;
    assertEquals(out.ok, true);
    assertEquals(out.idempotent, true);
    // The whole point: no confirm call, so no second capture, and no false 409 either.
    assertEquals(net.calls.length, 0);
    assertEquals(db.rows("bookings")[0].status, "payment_hold"); // untouched — we did nothing
  } finally {
    net.restore();
  }
});

Deno.test("camelCase body (what the Toss widget hands back) is accepted", async () => {
  const db = scene({ intent: { status: "confirmed", payment_key: KEY } });
  const net = tossOk();
  try {
    const out = await confirmPayment(req({ orderId: ORDER, paymentKey: KEY }, "owner_jwt"), db as never) as Row;
    assertEquals(out.idempotent, true);
  } finally {
    net.restore();
  }
});

Deno.test("a payment_key already bound to another order → 409, never a silent no-op success", async () => {
  const db = scene();
  db.rows("payments").push({
    id: "pay-2", booking_id: BOOKING, order_id: "dr_other", amount: AMOUNT,
    status: "confirmed", payment_key: KEY, refunded_amount: 0, raw: {},
  });
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 409);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("an already-closed (canceled) intent → 409, not a resurrection", async () => {
  const db = scene({ intent: { status: "canceled", payment_key: KEY } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: "another_key" }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 409);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

// ═══ Toss refused BEFORE capture — no cancel, because nothing moved ════════════════════════
Deno.test("Toss refuses the confirm → 402, intent failed, and NO cancel call is made", async () => {
  const db = scene();
  const net = tossOk({ confirm: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "카드사에서 거절했어요" }, 400) });
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 402);
    assertStringIncludes(e.message, "카드사");
    assertEquals(pay(db).status, "failed");
    assertEquals(pay(db).payment_key, null); // 0076 payments_settled_has_key stays satisfiable
    assertEquals(net.countTo("/cancel"), 0); // cancelling a capture that never happened = noise
    assertEquals(db.rows("bookings")[0].status, "payment_hold");
  } finally {
    net.restore();
  }
});

Deno.test("Toss refuses → the failure write MERGES into the existing raw, never replaces it", async () => {
  // The row's `raw` is a ledger of facts about this order. Overwriting it with just the error
  // erases whatever was already recorded there (a mint marker, a reconciliation note, an earlier
  // attempt) — and an erased fact has no recovery path.
  const db = scene({ intent: { raw: { mint_note: "keep me", attempts: 0 } } });
  const net = tossOk({ confirm: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "카드사에서 거절했어요" }, 400) });
  try {
    await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(pay(db).status, "failed");
    assertEquals(pay(db).raw.mint_note, "keep me");
    assertEquals(pay(db).raw.attempts, 0);
    assertEquals(pay(db).raw.http_status, 400);
    assertEquals((pay(db).raw.confirm_error as Row).code, "REJECT_CARD_COMPANY");
  } finally {
    net.restore();
  }
});

// ═══ the post-pay era — a server-minted charge intent is not the widget's to confirm ═══════
Deno.test("a server charge intent (raw.kind) → 409, and NOTHING is written or captured", async () => {
  // `raw.kind` marks an intent the server mints for a billing-key charge (§0-ter). It has no
  // widget session, no payment_hold booking, and its own retry ladder keyed on the order_id. A
  // confirm here would bind a client-supplied paymentKey to that order and leave the charge
  // machine facing an already-processed order it never made.
  for (const kind of ["settle_charge", "cancel_fee"]) {
    const db = scene({
      intent: { raw: { kind, attempts: 1 } },
      booking: { status: "completed" },
    });
    const net = tossOk();
    try {
      const e = await expectHttpError(() =>
        confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
      );
      assertEquals(e.status, 409);
      assertStringIncludes(e.message, "위젯 결제 대상이 아니에요");
      assertEquals(net.calls.length, 0); // Toss is never asked
      // Nothing written: same status, same key, same raw, no booking transition.
      assertEquals(pay(db).status, "pending");
      assertEquals(pay(db).payment_key, null);
      assertEquals(pay(db).raw.kind, kind);
      assertEquals(pay(db).raw.attempts, 1);
      assertEquals(db.log.filter((l) => l.startsWith("update:") || l.startsWith("insert:")).length, 0);
      assertEquals(db.rows("bookings")[0].status, "completed");
    } finally {
      net.restore();
    }
  }
});

Deno.test("the kind gate runs AFTER the party gate — a stranger still gets 403, not a hint", async () => {
  const db = scene({ intent: { raw: { kind: "settle_charge" } } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "stranger_jwt"), db as never)
    );
    assertEquals(e.status, 403);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("the widget confirm is NOT given a timeout — the billing pair's ceiling is not this path's", async () => {
  // toss.ts applies AbortSignal.timeout to the unattended billing calls only. Abandoning a capture
  // that a human is waiting on (while Toss may complete it anyway) is the one trade never worth
  // making here: §2-7's machine assumes it knows whether the money moved.
  const db = scene();
  const net = tossOk();
  try {
    await confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never);
    assertEquals(net.calls.find((c) => isConfirm(c.url))!.signal, null);
  } finally {
    net.restore();
  }
});

// ═══ post-capture failures — the §2-7 auto-cancel machine ══════════════════════════════════
Deno.test("amount mismatch → auto-cancel, row canceled, honest copy", async () => {
  const db = scene();
  const net = tossOk({ confirm: () => FetchMock.json(doneBody({ totalAmount: 9900 })) });
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 409);
    assertEquals(e.message, "결제 시간이 만료됐어요 — 결제는 자동 취소됐어요. 예약을 다시 만들어주세요");
    assertEquals(net.countTo("/cancel"), 1);
    assertEquals(pay(db).status, "canceled");
    assertEquals(pay(db).refunded_amount, AMOUNT); // the whole capture came back
    assertEquals(pay(db).raw.auto_cancel_reason, "amount_mismatch");
    assertEquals(db.rows("bookings")[0].status, "payment_hold"); // never transitioned
  } finally {
    net.restore();
  }
});

Deno.test("non-DONE status (async deposit method leaked through) → auto-cancel", async () => {
  const db = scene();
  const net = tossOk({ confirm: () => FetchMock.json(doneBody({ status: "WAITING_FOR_DEPOSIT" })) });
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 409);
    assertEquals(net.countTo("/cancel"), 1);
    assertEquals(pay(db).status, "canceled");
    assertStringIncludes(String(pay(db).raw.auto_cancel_reason), "WAITING_FOR_DEPOSIT");
  } finally {
    net.restore();
  }
});

Deno.test("CAS 0 rows (the 30-min hold expired mid-widget) → auto-cancel + the honest sentence", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(e.status, 409);
    assertEquals(e.message, "결제 시간이 만료됐어요 — 결제는 자동 취소됐어요. 예약을 다시 만들어주세요");
    assertEquals(pay(db).status, "canceled");
    assertEquals(pay(db).raw.auto_cancel_reason, "hold_expired");
    assertEquals(db.rows("bookings")[0].status, "expired"); // the expiry stands
  } finally {
    net.restore();
  }
});

Deno.test("cancel fails once then succeeds — exactly one retry, and the row still lands canceled", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk({ cancel: (n) => n === 1 ? FetchMock.json({ message: "일시 오류" }, 500) : FetchMock.json({ status: "CANCELED" }) });
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(net.countTo("/cancel"), 2);
    assertEquals(e.message, "결제 시간이 만료됐어요 — 결제는 자동 취소됐어요. 예약을 다시 만들어주세요");
    assertEquals(pay(db).status, "canceled");
  } finally {
    net.restore();
  }
});

Deno.test("cancel fails twice → confirmed + needs_manual_cancel marker + OPS notification (never the owner)", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk({ cancel: () => FetchMock.json({ message: "취소 불가" }, 500) });
  try {
    const e = await expectHttpError(() =>
      confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never)
    );
    assertEquals(net.countTo("/cancel"), 2); // one try + one retry, then stop
    // The row stays `confirmed` because the money is still at Toss. Writing `canceled` here
    // would make the ledger lie, and 0076's reconciliation query is what picks this up.
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).raw.needs_manual_cancel, true);
    assertEquals(pay(db).payment_key, KEY);
    // OPS gets the notification. The owner does not — they can do nothing about it.
    const notes = db.rows("notifications");
    assertEquals(notes.length, 1);
    assertEquals(notes[0].profile_id, OPS);
    assertEquals(notes[0].kind, "system");
    // ...and the copy does NOT claim an auto-cancel that did not happen (honesty law).
    assert(!e.message.includes("자동 취소됐어요"), `copy lies about the cancel: ${e.message}`);
    assertStringIncludes(e.message, "담당자가 확인 중");
    assertStringIncludes(e.message, ORDER);
  } finally {
    net.restore();
  }
});

Deno.test("cancel throws (network down) twice → same marker path", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk({ cancel: () => new Error("connection reset") });
  try {
    await expectHttpError(() => confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never));
    assertEquals(net.countTo("/cancel"), 2);
    assertEquals(pay(db).raw.needs_manual_cancel, true);
    assertStringIncludes(String(pay(db).raw.cancel_error), "connection reset");
  } finally {
    net.restore();
  }
});

// 2026-08-13 hardening pin. OPS_PROFILE_ID is a raw uuid in an env var: a typo that still
// parses as a valid profile id delivers this row to a real user, and 0024's insert trigger
// pushes `body` verbatim to their lock screen. So the body must never carry the order
// number, the amount, or any booking identifier — those live in console.error and in
// payments_reconciliation(). Reverting the body to the old interpolated string reddens this.
Deno.test("ops notification carries no financial detail (misdelivery must not disclose)", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk({ cancel: () => FetchMock.json({}, 500) });
  try {
    await expectHttpError(() => confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never));
    const notes = db.rows("notifications");
    assertEquals(notes.length, 1);
    const n = notes[0];
    assertEquals(n.profile_id, OPS);
    const text = `${n.title} ${n.body}`;
    for (const secret of [ORDER, String(AMOUNT), "24,900", KEY, BOOKING]) {
      assert(!text.includes(secret), `ops body leaked ${secret}: ${text}`);
    }
    // It still has to be actionable — name where the detail lives.
    assert(n.body.includes("payments_reconciliation"), `ops body not actionable: ${n.body}`);
  } finally {
    net.restore();
  }
});

// Ruling ③ wiring pin. The refactor into `_shared/ops.ts` moved the recipient decision out of this
// file, so what is left to pin HERE is the one thing only this call site knows: which event class
// this event is. A copy-paste that emitted `enroute_comp_failed` from the auto-cancel path would
// route captured money to whoever subscribed to runner safety, and every other test would pass.
Deno.test("the auto-cancel failure routes as payment_manual_cancel, to the class's recipients", async () => {
  const ROUTED = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  const db = scene({ booking: { status: "expired" } });
  const classes: string[] = [];
  db.rpcs["ops_recipients_for"] = (args: Row) => {
    classes.push(String(args.p_event_class));
    return { data: args.p_event_class === "payment_manual_cancel" ? [ROUTED] : [] };
  };
  const net = tossOk({ cancel: () => FetchMock.json({}, 500) });
  try {
    await expectHttpError(() => confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never));
    assertEquals(classes, ["payment_manual_cancel"]);
    // The table won, so the env-var operator is not also pinged.
    assertEquals(db.rows("notifications").map((n) => n.profile_id), [ROUTED]);
    assertEquals(db.rows("notifications")[0].ref_id, BOOKING);
  } finally {
    net.restore();
  }
});

Deno.test("no OPS_PROFILE_ID → loud log instead of a notification, and no crash", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk({ cancel: () => FetchMock.json({}, 500) });
  Deno.env.delete("OPS_PROFILE_ID");
  const errs: string[] = [];
  const origError = console.error;
  console.error = (...a: unknown[]) => errs.push(a.map(String).join(" "));
  try {
    await expectHttpError(() => confirmPayment(req({ order_id: ORDER, payment_key: KEY }, "owner_jwt"), db as never));
    assertEquals(db.rows("notifications").length, 0);
    assert(errs.some((l) => l.includes("OPS_PROFILE_ID unset")), `no loud log: ${errs.join("|")}`);
    assertEquals(pay(db).raw.needs_manual_cancel, true);
  } finally {
    console.error = origError;
    Deno.env.set("OPS_PROFILE_ID", OPS);
    net.restore();
  }
});

// ═══ §2-5b post-confirm — server-side and NON-FATAL ════════════════════════════════════════
Deno.test("postConfirm — recurring + nomination both run server-side after a successful CAS", async () => {
  const db = scene();
  const udb = userScene();
  const net = tossOk();
  try {
    const out = await confirmPayment(
      req({ order_id: ORDER, payment_key: KEY, meta: { recurring: true, preferred_runner_id: RUNNER } }, "owner_jwt"),
      db as never,
      () => udb as never,
    ) as Row;
    assertEquals(out.ok, true);
    assertEquals(out.post, { recurring: "ok", nomination: "ok" });
    // 0077 호출자 독트린: recurring RPC는 호출자 JWT 클라이언트로만 나간다 — 서비스
    // 클라이언트 로그에 있으면 not_signed_in 게이트를 우회하려던 옛 사고의 재발이다.
    assert(udb.log.includes("rpc:create_recurring_series"));
    assert(!db.log.includes("rpc:create_recurring_series"), "recurring went through the SERVICE client");
    const t = net.calls.find((c) => isTransition(c.url))!;
    assertEquals(t.body.action, "request_runner");
    assertEquals(t.body.meta.runner_id, RUNNER);
    // The caller's own token is forwarded — transition-booking re-runs its own party gate.
    assertEquals(t.headers["Authorization"], "Bearer owner_jwt");
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("postConfirm recurring failure is NON-FATAL — the payment still succeeds, the owner is told", async () => {
  const db = scene();
  const udb = userScene();
  udb.rpcs["create_recurring_series"] = () => ({ error: { message: "series exploded" } });
  const net = tossOk();
  try {
    const out = await confirmPayment(
      req({ order_id: ORDER, payment_key: KEY, meta: { recurring: "1" } }, "owner_jwt"),
      db as never,
      () => udb as never,
    ) as Row;
    assertEquals(out.ok, true); // <- the whole point of "non-fatal"
    assertEquals((out.post as Row).recurring, "failed");
    assertEquals(pay(db).status, "confirmed");
    assertEquals(db.rows("bookings")[0].status, "matching");
    const notes = db.rows("notifications");
    assertEquals(notes.length, 1);
    assertEquals(notes[0].profile_id, OWNER); // the owner CAN act on this one
    assertStringIncludes(notes[0].body, "series exploded");
  } finally {
    net.restore();
  }
});

Deno.test("postConfirm nomination failure is NON-FATAL and is not swallowed silently (C3)", async () => {
  const db = scene();
  const net = tossOk({ transition: () => FetchMock.json({ error: "그 시간에 다른 일정이 있는 러너예요" }, 409) });
  try {
    const out = await confirmPayment(
      req({ order_id: ORDER, payment_key: KEY, meta: { preferred_runner_id: RUNNER } }, "owner_jwt"),
      db as never,
    ) as Row;
    assertEquals(out.ok, true);
    assertEquals((out.post as Row).nomination, "failed");
    assertEquals(db.rows("bookings")[0].status, "matching");
    const notes = db.rows("notifications");
    assertEquals(notes.length, 1);
    assertEquals(notes[0].title, "지명 요청 실패");
    assertStringIncludes(notes[0].body, "다른 일정이 있는 러너");
  } finally {
    net.restore();
  }
});

Deno.test("postConfirm runs only AFTER the CAS — an expired hold never creates a weekly series", async () => {
  const db = scene({ booking: { status: "expired" } });
  const net = tossOk();
  try {
    await expectHttpError(() =>
      confirmPayment(
        req({ order_id: ORDER, payment_key: KEY, meta: { recurring: true, preferred_runner_id: RUNNER } }, "owner_jwt"),
        db as never,
      )
    );
    assert(!db.log.includes("rpc:create_recurring_series"), "a cancelled payment created a series");
    assertEquals(net.calls.filter((c) => isTransition(c.url)).length, 0);
  } finally {
    net.restore();
  }
});
