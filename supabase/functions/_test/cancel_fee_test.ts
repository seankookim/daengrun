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
/**
 * [0085 ⑩] The 10% tier's half. Mirrors installComp: records the call, writes the ledger row the
 * real SQL would write, and can be made to fail so the caller's honesty gate is testable.
 */
function installShare(db: FakeDb, over: { fail?: string; written?: boolean } = {}) {
  const seen: Row[] = [];
  db.rpcs["record_late_cancel_share"] = (args: Row) => {
    seen.push(args);
    if (over.fail) return { error: { message: over.fail } };
    const written = over.written ?? true;
    const share = Math.round(FEE_10 * 0.5);
    if (written) {
      db.rows("ledger_items").push({
        runner_id: RUNNER, booking_id: args.p_booking, base: 0, distance_pay: 0,
        addon_pay: 0, tip: 0, remaining_guarantee: share, platform_fee: 0,
      });
    }
    return { data: [{ comp: share, written }] };
  };
  return seen;
}

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

// ═══ club bookings are not on this ladder ══════════════════════════════════════════════════
// A club-delegated booking reaches /owner/schedule and its cancel button lands in cancelOwner,
// where 0066's marketplace ladder would quote a rate the club never agreed to, write
// bookings.cancel_fee, mint a fee intent post-cutover, and leave the club side (club_fee_items,
// host notification, assignment revocation) untouched. The club has its own exit. Deleting the
// guard reddens this: the fee quote runs and a booking update lands.
Deno.test("club booking → refused before any money is quoted or written", async () => {
  const db = scene();
  db.rows("bookings")[0].club_session_id = "cccccccc-cccc-cccc-cccc-cccccccccccc";
  const seen = installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const err = await cancelOwner(db as never, {
      bookingId: BOOKING, uid: OWNER, bk: db.rows("bookings")[0], notify: notifier(db),
    }).then(() => null, (e) => e);
    assert(err, "club cancel should have been refused");
    assertEquals((err as { status?: number }).status, 409);
    const msg = String((err as Error).message);
    assert(msg.includes("클럽 세션 화면"), `refusal must name where to go: ${msg}`);
    // It must NOT promise the cancel will succeed there: session_cancel_delegation
    // (0057:190) refuses past `confirmed` with already_handed_off, so an en-route club
    // booking has no cancel at all — past handoff it is a case. Promising 취소 would be
    // a lie told one screen before it is discovered.
    assert(!msg.includes("취소해주세요"), `refusal must not promise a cancel: ${msg}`);
    // Nothing quoted, nothing written, nothing charged, nobody notified.
    assertEquals(db.log.filter((l) => l === "rpc:marketplace_cancel_fee").length, 0);
    assertEquals(updatesToBookings(db).length, 0);
    assertEquals(db.rows("bookings")[0].cancel_fee, null);
    assertEquals(seen.length, 0);
    assertEquals(net.countTo("api.tosspayments.com"), 0);
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    cap.restore();
    net.restore();
  }
});

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
    assertEquals(billing.body.orderName, "도그스하이 예약 취소 수수료"); // Sean 2026-08-25: 도그스하이; not the run fee — no run happened
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

// Ruling ③ wiring pin — the mirror of confirm_payment_test's. `_shared/ops.ts` owns the recipient
// ladder and the redaction; the one fact only this call site knows is the event class, and getting
// it wrong would silently deliver a runner-safety event to money's operator (or to nobody).
Deno.test("the comp failure routes as enroute_comp_failed, to that class's recipients", async () => {
  const SAFETY_OPS = "cccccccc-cccc-cccc-cccc-cccccccccccc";
  const db = scene({ status: "runner_enroute" });
  installComp(db, { fail: "deadlock detected" });
  installMint(db, { amount: FEE_50 });
  const classes: string[] = [];
  db.rpcs["ops_recipients_for"] = (args: Row) => {
    classes.push(String(args.p_event_class));
    return { data: args.p_event_class === "enroute_comp_failed" ? [SAFETY_OPS] : [] };
  };
  const net = tossOk({ billing: () => FetchMock.json(chargeDone({ totalAmount: FEE_50 })) });
  const cap = captureLogs();
  try {
    await call(db);
    assertEquals(classes, ["enroute_comp_failed"]);
    const ops = db.rows("notifications").filter((n) => n.kind === "system");
    assertEquals(ops.map((n) => n.profile_id), [SAFETY_OPS]);
    assertEquals(ops[0].ref_id, BOOKING);
    // The env-var operator is the fallback, not a second copy.
    assert(!db.rows("notifications").some((n) => n.profile_id === OPS), "the env fallback fired too");
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

Deno.test("the en-route comp RPC is never called off its own tier", async () => {
  // [0085 ⑩] AMENDED. This case used to assert that a non-en-route cancel wrote NO ledger row
  // and NO cancel_reason. That was the defect, not the contract: the <24h tier charges the owner
  // 10% and the cancel sheet promises the runner half of it. Sean ruled "pay the runner and let
  // them know" (docs/decisions/cancel-fee-runner-share.md), so the confirmed tier now DOES write
  // a reason and a ledger row — through record_late_cancel_share, never through the en-route one.
  // What survives unchanged is the property this case actually guards: 0080's comp is en-route-only.
  for (const status of ["confirmed", "matching"]) {
    const db = scene({ status });
    db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: status === "matching" ? 0 : FEE_10, status }] });
    installComp(db);
    installShare(db);
    installMint(db);
    const net = tossOk();
    const cap = captureLogs();
    try {
      await call(db);
      assert(!db.log.includes("rpc:record_enroute_cancel_comp"), `${status} paid an en-route comp`);
    } finally {
      cap.restore();
      net.restore();
    }
  }
});

Deno.test("[0085 ⑩] a free cancel pays nobody and marks nothing", async () => {
  // The unmatched/≥24h arm: fee 0, so there is no half to share. No marker (0085's gate would
  // otherwise look at the row), no ledger row, neither comp RPC called.
  const db = scene({ status: "matching" });
  db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: 0, status: "matching" }] });
  installComp(db);
  installShare(db);
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    await call(db);
    assert(!db.log.includes("rpc:record_late_cancel_share"), "a free cancel called the share RPC");
    assertEquals(db.rows("ledger_items").length, 0);
    assertEquals(bk(db).cancel_reason, null);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("[0085 ⑩] the <24h tier marks the tier, pays the runner half, and says so as a reward", async () => {
  const db = scene({ status: "confirmed" });
  db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: FEE_10, status: "confirmed" }] });
  installComp(db);
  const seen = installShare(db);
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    await call(db);
    // the tier marker the SQL gate reads — the sibling of owner_cancel_enroute
    assertEquals(bk(db).cancel_reason, "owner_cancel_late");
    assertEquals(seen.length, 1);
    // exactly one ledger row, the runner's half, shaped so my_ledger_total actually pays it
    assertEquals(db.rows("ledger_items").length, 1);
    const li = db.rows("ledger_items")[0] as Row;
    assertEquals(li.remaining_guarantee, Math.round(FEE_10 * 0.5));
    assertEquals(li.platform_fee, 0); // platform_fee SUBTRACTS in my_ledger_total (0027:13)
    // and the runner is told, in the voice of good news, with the amount that is backed
    const noti = db.rows("notifications").at(-1) as Row;
    assertStringIncludes(String(noti.title), "보상");
    assertStringIncludes(String(noti.body), String(Math.round(FEE_10 * 0.5)));
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("[0085 ⑩] the tier markers are ONE contract, verified against the migrations", async () => {
  // 121's header named this gap; this closes it. The marker string lived in THREE places —
  // cancel_owner.ts writes it, 0085 gates on it, and this file asserted the TS value — so a
  // rename in the SQL reddened nothing: TS would keep writing the old literal, the gate would
  // stop matching, and the runner's share would silently never be recorded. That is the exact
  // defect ⑩ exists to fix, reintroduced through its own contract surface.
  //
  // The lesson from the run-end-flow session, whose own hour-old code had the same class:
  //   "A fake cannot be made to tell the truth about the thing it replaces."
  // Every test here fakes the RPC, so no fake will ever catch a SQL-side rename. The answer is
  // not a better fake — it is to stop duplicating the contract and VERIFY against it. The SQL
  // is the single source; TypeScript is checked against it, in BOTH directions, with the fakes
  // left exactly as they are.
  // ⚠ DO NOT "TIDY" THIS BY HOISTING THE LITERAL INTO A TS CONSTANT. Reading the migration
  // text at test time is the entire mechanism: the contract lives in exactly ONE place (the
  // SQL) and TypeScript is verified against it. The moment a named constant holds
  // 'owner_cancel_late' on this side, the test starts passing against the copy and the join is
  // open again — the exact defect this pin closes, reintroduced by an edit that reads as
  // cleanup and would pass review, because hoisting a repeated string is normally correct.
  // Here it is backwards. The technique's precondition is that the owning side stays the only
  // copy; a cache on the reading side is synchronising copies with extra steps.
  const read = (rel: string) => Deno.readTextFile(new URL(rel, import.meta.url));
  const [ts, sql85, sql80] = await Promise.all([
    read("../transition-booking/cancel_owner.ts"),
    read("../../migrations/0085_cancel_share.sql"),
    read("../../migrations/0080_charge_machine.sql"),
  ]);

  // Which markers do the migrations actually gate on? (the contract, read from its one home)
  const gated = new Set(
    [...`${sql80}\n${sql85}`.matchAll(/cancel_reason is (?:not )?distinct from '([a-z_]+)'/g)]
      .map((m) => m[1]),
  );
  assert(gated.has("owner_cancel_late"), "0085 no longer gates on owner_cancel_late — the contract moved");
  assert(gated.has("owner_cancel_enroute"), "0080 no longer gates on owner_cancel_enroute");

  // → forward: every gated marker must be written by the handler, or the gate is unreachable
  //   and the comp it guards can never fire.
  const written = new Set(
    [...ts.matchAll(/cancel_reason: "([a-z_]+)"/g)].map((m) => m[1]),
  );
  for (const marker of gated) {
    assert(written.has(marker), `0080/0085 gate on '${marker}' but cancel_owner.ts never writes it`);
  }
  // ← reverse: every marker the handler writes must be gated by a migration, or it is a
  //   tier that pays nobody — the shape of the original ⑩ defect.
  for (const marker of written) {
    assert(gated.has(marker), `cancel_owner.ts writes '${marker}' but no migration gates on it`);
  }
});

Deno.test("[0085 ⑩] a late-tier comp failure routes as late_comp_failed, NOT the en-route class", async () => {
  // Found reviewing the merged slice: both failure paths pinged `enroute_comp_failed`, whose
  // copy names `record_enroute_cancel_comp` — a function that REFUSES a late-tier booking by
  // design (0080:1137 gates on 'owner_cancel_enroute'). The operator would run a no-op, mark
  // the alert handled, and the runner would never be paid: silent non-payment behind a green
  // ops queue, which is the exact failure ⑩ exists to prevent. A remedy that refuses by design
  // is worse than none, because it closes the queue item.
  const MONEY_OPS = "dddddddd-dddd-dddd-dddd-dddddddddddd";
  const db = scene({ status: "confirmed" });
  db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: FEE_10, status: "confirmed" }] });
  installComp(db);
  installShare(db, { fail: "deadlock detected" });
  installMint(db);
  const classes: string[] = [];
  db.rpcs["ops_recipients_for"] = (args: Row) => {
    classes.push(String(args.p_event_class));
    return { data: args.p_event_class === "late_comp_failed" ? [MONEY_OPS] : [] };
  };
  const net = tossOk();
  const cap = captureLogs();
  try {
    await call(db);
    assertEquals(classes, ["late_comp_failed"]);
    const ops = db.rows("notifications").filter((n) => n.kind === "system");
    assertEquals(ops.map((n) => n.profile_id), [MONEY_OPS]);
    assertEquals(ops[0].ref_id, BOOKING);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("[0085 ⑩] a failed share write never names a number the ledger cannot back", async () => {
  // Same honesty gate the en-route arm has: ops is told, the cancel still succeeds, and the
  // runner hears the true generic sentence rather than a receipt for a row that is not there.
  const db = scene({ status: "confirmed" });
  db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: FEE_10, status: "confirmed" }] });
  installComp(db);
  installShare(db, { fail: "deadlock detected" });
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await call(db) as Row;
    assertCancelShape(out);
    assertEquals(out.cancel_fee, FEE_10);
    assertEquals(db.rows("ledger_items").length, 0);
    const noti = db.rows("notifications").at(-1) as Row;
    assertEquals(noti.title, "예약 취소됨");
    assert(!String(noti.body).includes("보상"), "promised a compensation that was not recorded");
    // …and ops is told with the class whose REMEDY actually works on this tier. Routing it as
    // enroute_comp_failed would name record_enroute_cancel_comp, which refuses a late-tier
    // booking by design — the operator runs a no-op, closes the alert, and the runner stays
    // unpaid. Found in review of the merged slice, 2026-08-13.
    assertStringIncludes(cap.lines.join("|"), "late cancel share FAILED");
  } finally {
    cap.restore();
    net.restore();
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
