// transition-booking `cancel_owner` — the cancel-fee machine (toss-plan §0-ter #5/#13).
//
//   deno test -A supabase/functions/_test/
//
// The invariant every test here defends: THE CANCEL IS COMMITTED BY THE CAS AND NOTHING AFTER IT
// MAY FAIL. A declined card, a dead mint, an ops-only ledger failure — each of them is a log line
// and a 200, never a 500 handed to an owner whose booking is already cancelled. Money has a
// recovery path (ladder → derived debt → account lock); an owner told "cancel failed" about a
// completed cancel does not.
//
// The second pin is the RETIRED `refund` field. Under post-pay nothing was ever captured, so
// `refund: total_price - fee` was a promise about money we never took (§0-ter #5). The response
// key set is asserted EXACTLY, in both the prepaid and post-pay eras.
//
// As in settle_charge_test.ts, no amount is computed here: `marketplace_cancel_fee` (0066) and
// `mint_cancel_fee_intent` (0080) own the money, and these tests pin that Deno passes the right
// booking id and charges whatever SQL returned.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { cancelOwner } from "../transition-booking/cancel_owner.ts";
import { FakeDb, FetchMock, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const OPS = "99999999-9999-9999-9999-999999999999";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const PAY = "pay-cancel-1";
const ORDER = "dr_cancel_1";
const TOTAL = 13900;
const FEE_10 = 1390; // <24h tier
const FEE_50 = 6950; // runner_enroute tier — the whole thing is runner compensation (Sean 2026-08-11)

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");
Deno.env.set("OPS_PROFILE_ID", OPS);

const isBilling = (u: string) => u.includes("api.tosspayments.com/v1/billing/");
const isOrders = (u: string) => u.includes("/v1/payments/orders/");

function scene(over: { status?: string; card?: boolean; prepaid?: boolean } = {}) {
  const db = new FakeDb();
  const status = over.status ?? "confirmed";
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status,
    total_price: TOTAL, cancel_fee: null, cancel_reason: null,
  }]);
  db.seed("profiles", [{ id: OWNER, toss_customer_key: "cust_owner_1" }]);
  db.seed("billing_keys", over.card === false ? [] : [{ profile_id: OWNER, billing_key: "bkey_1" }]);
  db.seed("payments", over.prepaid
    ? [{
      id: "pay-widget-1", booking_id: BOOKING, order_id: "dr_widget_1", amount: TOTAL,
      status: "confirmed", payment_key: "tviva_widget", refunded_amount: 0, raw: {},
      created_at: "2026-08-01T00:00:00Z",
    }]
    : []);
  db.seed("notifications", []);
  db.seed("ledger_items", []);
  // 0066's ladder, in SQL. `returns table(fee, status)` → an array through PostgREST.
  db.rpcs["marketplace_cancel_fee"] = () => ({
    data: [{ fee: status === "runner_enroute" ? FEE_50 : FEE_10, status }],
  });
  return db;
}

/** index.ts's notify helper, recorded so the runner-facing copy is checkable. */
function notifier(db: FakeDb) {
  return (profile_id: string, title: string, body: string) =>
    db.from("notifications").insert({ profile_id, kind: "booking", title, body, ref_id: BOOKING });
}

const call = (db: FakeDb, over: { uid?: string } = {}) =>
  cancelOwner(db as never, {
    bookingId: BOOKING,
    uid: over.uid ?? OWNER,
    bk: db.rows("bookings")[0],
    notify: notifier(db),
  });

/**
 * Stand-in for 0080's `mint_cancel_fee_intent` (Unit A): writes the row the real function writes,
 * returns its shape (`returns table(...)` → array), and records the args it was handed.
 * `notLive` is the cutover arm — `ops_flags.payments_live_since` null → ZERO ROWS, nothing minted.
 */
function installMint(db: FakeDb, over: { status?: string; amount?: number; notLive?: boolean } = {}) {
  const seen: Row[] = [];
  db.rpcs["mint_cancel_fee_intent"] = (args: Row) => {
    seen.push(args);
    if (over.notLive) return { data: [] };
    const status = over.status ?? "pending";
    const amount = over.amount ?? FEE_10;
    db.rows("payments").push({
      id: PAY, booking_id: args.p_booking, order_id: ORDER, amount, status,
      payment_key: null, refunded_amount: 0,
      raw: { kind: "cancel_fee", attempts: 0 },
      created_at: "2026-08-13T00:00:00Z",
    });
    return { data: [{ payment_id: PAY, order_id: ORDER, amount, status, minted: true }] };
  };
  return seen;
}

/** Stand-in for 0080's `record_enroute_cancel_comp` — writes the runner's ledger row. */
function installComp(db: FakeDb, over: { fail?: string; written?: boolean } = {}) {
  const seen: Row[] = [];
  db.rpcs["record_enroute_cancel_comp"] = (args: Row) => {
    seen.push(args);
    if (over.fail) return { error: { message: over.fail } };
    const written = over.written ?? true;
    if (written) {
      db.rows("ledger_items").push({
        runner_id: RUNNER, booking_id: args.p_booking, base: 0, distance_pay: 0,
        addon_pay: 0, tip: 0, remaining_guarantee: FEE_50, platform_fee: 0,
      });
    }
    return { data: [{ comp: FEE_50, written }] };
  };
  return seen;
}

const chargeDone = (over: Record<string, unknown> = {}) => ({
  paymentKey: "tviva_fee_1", orderId: ORDER, status: "DONE", totalAmount: FEE_10, ...over,
});

function tossOk(over: { billing?: (c: unknown, n: number) => Response | Error } = {}) {
  return new FetchMock()
    .on(isBilling, over.billing ?? (() => FetchMock.json(chargeDone())))
    .on(isOrders, () => FetchMock.json(chargeDone()))
    .install();
}

function captureLogs() {
  const lines: string[] = [];
  const log = console.log, err = console.error;
  console.log = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  console.error = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  return { lines, restore: () => { console.log = log; console.error = err; } };
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

const bk = (db: FakeDb) => db.rows("bookings")[0];
const pay = (db: FakeDb) => db.rows("payments").find((p) => p.id === PAY);
const updatesToBookings = (db: FakeDb) => db.log.filter((l) => l.startsWith("update:bookings"));
/** The owner-facing shape after this slice: the fee, and nothing else. */
function assertCancelShape(out: Row) {
  assertEquals(Object.keys(out), ["cancel_fee"]);
  assertEquals(out.refund, undefined);
}

// ═══ prepaid (widget era) — recorded, never re-minted ══════════════════════════════════════
Deno.test("prepaid booking → fee recorded, NO mint, and the retired `refund` field is gone", async () => {
  const db = scene({ prepaid: true });
  const seen = installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, FEE_10);
    assertEquals(bk(db).status, "cancelled_owner");
    assertEquals(bk(db).cancel_fee, FEE_10);
    // The money was already captured by the widget: minting a charge here would bill it twice,
    // and refunding is the widget path's own gate, not this function's promise to make.
    assertEquals(seen.length, 0);
    assert(!db.log.includes("rpc:mint_cancel_fee_intent"));
    assertEquals(net.calls.length, 0);
    assertEquals(db.rows("payments").length, 1); // the untouched widget capture
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ post-pay — the fee rides the settle machine's rails ═══════════════════════════════════
Deno.test("post-pay, fee > 0 → mint + one immediate dispatch, and the row lands confirmed", async () => {
  const db = scene();
  const seen = installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, FEE_10);
    assertEquals(bk(db).status, "cancelled_owner");
    // The mint is asked about the booking and nothing else — the amount is SQL's (bookings.cancel_fee).
    assertEquals(seen.length, 1);
    assertEquals(seen[0].p_booking, BOOKING);
    // ...and the cancel is written BEFORE the fee is minted: the fee's source is that written row.
    const cas = db.log.indexOf("update:bookings:1");
    const mint = db.log.indexOf("rpc:mint_cancel_fee_intent");
    assert(cas >= 0 && mint > cas, `minted before the cancel was committed: ${db.log.join(" ")}`);
    const billing = net.calls.find((c) => isBilling(c.url))!;
    assertEquals(billing.body.amount, FEE_10);
    assertEquals(billing.body.orderId, ORDER);
    assertEquals(billing.body.orderName, "댕런 예약 취소 수수료"); // not "산책 이용료" — no run happened
    assertEquals(pay(db)!.status, "confirmed");
    assertEquals(pay(db)!.payment_key, "tviva_fee_1");
    assertStringIncludes(cap.lines.join("|"), "cancel fee booking=");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("fee 0 (unmatched / ≥24h) mints NOTHING at all (§0-ter #13)", async () => {
  const db = scene({ status: "matching" });
  db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: 0, status: "matching" }] });
  const seen = installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, 0);
    assertEquals(bk(db).status, "cancelled_owner");
    // Nothing was ever charged for a booking that never matched — a zero row would be a receipt
    // for nothing and a permanent visitor in the debt query's scope.
    assertEquals(seen.length, 0);
    assertEquals(db.rows("payments").length, 0);
    assertEquals(net.calls.length, 0);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("charging not live (mint returns ZERO ROWS) → fee stays recorded-only, nothing dispatched", async () => {
  const db = scene();
  const seen = installMint(db, { notLive: true });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, FEE_10);
    assertEquals(bk(db).cancel_fee, FEE_10); // today's behaviour: recorded on the booking
    assertEquals(seen.length, 1); // SQL was asked; SQL is the one that said "not live"
    assertEquals(db.rows("payments").length, 0); // no pending to be swept into false debt
    assertEquals(net.calls.length, 0);
    assertStringIncludes(cap.lines.join("|"), "outcome=not_live");
    assert(!cap.lines.some((l) => l.includes("collection failed")), "zero rows was treated as an error");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("an existing non-pending intent is never re-dispatched (mint's exists-check wins)", async () => {
  const db = scene();
  installMint(db, { status: "failed" });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(net.calls.length, 0); // the ladder owns a failed row, not this request
    assertStringIncludes(cap.lines.join("|"), "outcome=existing_failed");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("no billing key → the intent waits as a never-dispatched pending; the cancel is fine", async () => {
  const db = scene({ card: false });
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db)!.status, "pending");
    assertEquals(pay(db)!.raw.dispatched_at, undefined);
    assertStringIncludes(cap.lines.join("|"), "outcome=skipped_no_card");
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ collection failure never touches the cancel ═══════════════════════════════════════════
Deno.test("a declined card does NOT fail the cancel — 200 with the fee, ladder on the row", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk({ billing: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "한도 초과예요" }, 400) });
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, FEE_10);
    assertEquals(bk(db).status, "cancelled_owner"); // committed, and it stays committed
    assertEquals(pay(db)!.status, "failed");
    assertEquals(pay(db)!.raw.attempts, 1);
    assertEquals(typeof pay(db)!.raw.next_retry_at, "string"); // +1h — the ladder has it now
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("the mint RPC exploding does not fail the cancel either (loud log, 200)", async () => {
  const db = scene();
  db.rpcs["mint_cancel_fee_intent"] = () => ({ error: { message: "relation ops_flags does not exist" } });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(bk(db).status, "cancelled_owner");
    assertEquals(net.calls.length, 0);
    assert(
      cap.lines.some((l) => l.includes("cancel fee collection failed") && l.includes("ops_flags")),
      `silent swallow: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("a THROWN dispatch (unreadable payments row) is caught — the cancel still returns 200", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    // Breaks both the prepaid probe and `dispatchCharge`'s own read. The probe's failure must
    // fall through to the post-pay arm (SQL's exists-check is the real prepaid guard), and the
    // dispatch's throw must not reach the caller.
    db.fail("payments:select", "connection reset");
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(bk(db).status, "cancelled_owner");
    assert(cap.lines.some((l) => l.includes("prepaid check failed")), `probe failure was silent: ${cap.lines.join("|")}`);
    assert(
      cap.lines.some((l) => l.includes("cancel fee collection failed") && l.includes("payments read failed")),
      `dispatch throw was silent: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ the en-route tier — the runner's half ═════════════════════════════════════════════════
Deno.test("en-route cancel → comp RPC exactly once, before the runner is told, with the fee owed", async () => {
  const db = scene({ status: "runner_enroute" });
  const compSeen = installComp(db);
  installMint(db, { amount: FEE_50 });
  const net = tossOk({ billing: () => FetchMock.json(chargeDone({ totalAmount: FEE_50 })) });
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, FEE_50);
    assertEquals(bk(db).cancel_reason, "owner_cancel_enroute"); // the tier marker the SQL gate reads
    assertEquals(compSeen.length, 1); // exactly once — SQL is idempotent, but we do not lean on it
    assertEquals(compSeen[0].p_booking, BOOKING);
    assertEquals(db.rows("ledger_items").length, 1);
    assertEquals(db.rows("ledger_items")[0].remaining_guarantee, FEE_50);
    assertEquals(db.rows("ledger_items")[0].platform_fee, 0);
    // The runner's notification says the compensation is recorded, so it is written first.
    const comp = db.log.indexOf("rpc:record_enroute_cancel_comp");
    const noti = db.log.indexOf("insert:notifications");
    assert(comp >= 0 && noti > comp, `the runner was told before the ledger row existed: ${db.log.join(" ")}`);
    const msg = db.rows("notifications")[0];
    assertEquals(msg.profile_id, RUNNER);
    assertStringIncludes(msg.body, "러너 보상으로 기록됐어요");
    // ...and the owner's side of the same fee rides the normal rails.
    assertEquals(net.calls.find((c) => isBilling(c.url))!.body.amount, FEE_50);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("comp RPC failing is non-fatal but NEVER silent — loud log + ops notification", async () => {
  const db = scene({ status: "runner_enroute" });
  installComp(db, { fail: "deadlock detected" });
  installMint(db, { amount: FEE_50 });
  const net = tossOk({ billing: () => FetchMock.json(chargeDone({ totalAmount: FEE_50 })) });
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out); // the owner's cancel succeeded; the runner's ledger row is ops' problem
    assertEquals(bk(db).status, "cancelled_owner");
    assertEquals(db.rows("ledger_items").length, 0);
    assert(
      cap.lines.some((l) => l.includes("enroute comp FAILED") && l.includes("deadlock detected")),
      `comp failure was silent: ${cap.lines.join("|")}`,
    );
    // No sweep looks for a missing compensation row — a human has to. Ops, not the owner.
    const ops = db.rows("notifications").find((n) => n.profile_id === OPS);
    assert(ops, `no ops notification: ${JSON.stringify(db.rows("notifications"))}`);
    assertEquals(ops!.kind, "system");
    assertStringIncludes(String(ops!.body), "record_enroute_cancel_comp");
    // The runner is still told about the cancel — losing their notification too would be worse.
    assert(db.rows("notifications").some((n) => n.profile_id === RUNNER));
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("comp failed → the runner is told about the CANCEL, never that a missing record exists", async () => {
  const db = scene({ status: "runner_enroute" });
  installComp(db, { fail: "deadlock detected" });
  installMint(db, { amount: FEE_50 });
  const net = tossOk({ billing: () => FetchMock.json(chargeDone({ totalAmount: FEE_50 })) });
  const cap = captureLogs();
  try {
    await call(db);
    const msg = db.rows("notifications").find((n) => n.profile_id === RUNNER)!;
    // "기록됐어요" is a receipt. There is no ledger row to be a receipt FOR — ops has been asked to
    // write it by hand, and until they do, the sentence would be the app telling a runner their
    // money is recorded when it is not (honesty law). The generic sentence is true either way.
    assert(
      !String(msg.body).includes("기록됐어요"),
      `the runner was handed a receipt for an unwritten ledger row: ${msg.body}`,
    );
    assertEquals(msg.body, "보호자가 예약을 취소했어요");
    assertEquals(db.rows("ledger_items").length, 0);
    // ...and ops still hears about it — this is the notification that gets the row written.
    assert(db.rows("notifications").some((n) => n.profile_id === OPS));
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ the double tap ════════════════════════════════════════════════════════════════════════
Deno.test("cancelling an already-cancelled booking is a NO-OP that returns the recorded fee", async () => {
  // 0066's quote reads the row's CURRENT status, so it happily quotes a fresh fee for a cancelled
  // booking — and the CAS (`status = 'cancelled_owner'` → 'cancelled_owner') MATCHES. A slow
  // button, tapped twice, would re-write cancel_fee to a different number, mint and DISPATCH a
  // second fee charge, and notify the runner again.
  const RECORDED = 990;
  const db = scene({ status: "cancelled_owner" });
  bk(db).cancel_fee = RECORDED;
  const seen = installMint(db);
  const compSeen = installComp(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, RECORDED); // what was actually charged, not what a re-quote says
    assertEquals(bk(db).cancel_fee, RECORDED); // untouched
    assertEquals(updatesToBookings(db).length, 0); // no CAS at all
    assertEquals(seen.length, 0); // no second fee intent
    assertEquals(compSeen.length, 0); // no second compensation
    assertEquals(net.calls.length, 0); // no second charge
    assertEquals(db.rows("notifications").length, 0); // no second "예약 취소됨" push
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("a cancelled booking that never recorded a fee answers 0, not null", async () => {
  const db = scene({ status: "cancelled_owner" }); // cancel_fee seeded null
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, 0);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("non-en-route tiers never call the comp RPC", async () => {
  for (const status of ["confirmed", "matching"]) {
    const db = scene({ status });
    db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: status === "matching" ? 0 : FEE_10, status }] });
    installComp(db);
    installMint(db);
    const net = tossOk();
    const cap = captureLogs();
    try {
      await call(db);
      assert(!db.log.includes("rpc:record_enroute_cancel_comp"), `${status} paid an en-route comp`);
      assertEquals(db.rows("ledger_items").length, 0);
      assertEquals(bk(db).cancel_reason, null);
    } finally {
      cap.restore();
      net.restore();
    }
  }
});

// ═══ gates ═════════════════════════════════════════════════════════════════════════════════
Deno.test("party gate before state gate — a non-owner is refused before the quote is even asked", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk();
  try {
    const e = await expectHttpError(() => call(db, { uid: RUNNER }));
    assertEquals(e.status, 403);
    // Not one word about the booking's cancellability leaks (CLAUDE.md law).
    assert(!db.log.includes("rpc:marketplace_cancel_fee"), `the quote ran for a stranger: ${db.log.join(" ")}`);
    assertEquals(bk(db).status, "confirmed");
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("the CAS losing its race → 409, and no fee is minted or compensated", async () => {
  const db = scene();
  // Quoted as `confirmed`, but the row moved to `runner_enroute` between quote and write — the
  // 0066 race the CAS exists for. A 10% fee must not land on a runner who already set out.
  bk(db).status = "runner_enroute";
  installMint(db);
  installComp(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => call(db));
    assertEquals(e.status, 409);
    assertStringIncludes(e.message, "다시 시도해주세요");
    assertEquals(bk(db).status, "runner_enroute"); // untouched
    assertEquals(bk(db).cancel_fee, null);
    assert(!db.log.includes("rpc:mint_cancel_fee_intent"));
    assert(!db.log.includes("rpc:record_enroute_cancel_comp"));
    assertEquals(net.calls.length, 0);
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("the quote RPC failing → 409 and nothing is cancelled", async () => {
  const db = scene();
  db.rpcs["marketplace_cancel_fee"] = () => ({ error: { message: "booking not found" } });
  installMint(db);
  const net = tossOk();
  try {
    const e = await expectHttpError(() => call(db));
    assertEquals(e.status, 409);
    assertEquals(bk(db).status, "confirmed");
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});
