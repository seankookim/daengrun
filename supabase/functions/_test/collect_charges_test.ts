// collect-charges + the charge core's retry rules (toss-plan §0-ter).
//
//   deno test -A supabase/functions/_test/
//
// Two things are pinned here that exist nowhere else: the AUTH shape of a function that can move
// money in a batch with nobody logged in, and the ladder arithmetic (injected `now`, so the
// assertions are exact rather than "roughly an hour"). As with the other edge tests, Toss itself
// is hand-written — the sandbox matrix (§4-2) is what catches drift from the real API.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { dispatchCharge } from "../_shared/charge.ts";
import { collectCharges } from "../collect-charges/handler.ts";
import { FakeDb, FetchMock, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const CHARGE = 13900;
const CRON_KEY = "cron_secret_do_not_use";
const PAST = "2020-01-01T00:00:00.000Z";
const FUTURE = "2999-01-01T00:00:00.000Z";
const NOW = new Date("2026-08-13T12:00:00.000Z");

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");
Deno.env.set("CRON_COLLECT_KEY", CRON_KEY);

const isBilling = (u: string) => u.includes("api.tosspayments.com/v1/billing/");
const isOrders = (u: string) => u.includes("/v1/payments/orders/");

function payRow(over: Row = {}): Row {
  return {
    id: "pay-1", booking_id: BOOKING, order_id: "dr_1", amount: CHARGE,
    status: "failed", payment_key: null, refunded_amount: 0,
    raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST, next_retry_at: PAST },
    created_at: "2026-08-13T00:00:00Z", ...over,
  };
}

function scene(over: { payments?: Row[]; card?: boolean } = {}) {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("bookings", [{ id: BOOKING, owner_id: OWNER }]);
  db.seed("profiles", [{ id: OWNER, toss_customer_key: "cust_owner_1" }]);
  db.seed("billing_keys", over.card === false ? [] : [{ profile_id: OWNER, billing_key: "bkey_1" }]);
  db.seed("payments", over.payments ?? [payRow()]);
  db.seed("notifications", []);
  return db;
}

const chargeDone = (over: Record<string, unknown> = {}) => ({
  paymentKey: "tviva_charge_1", orderId: "dr_1", status: "DONE", totalAmount: CHARGE, ...over,
});

function tossOk(over: {
  billing?: (c: unknown, n: number) => Response | Error;
  orders?: (c: unknown, n: number) => Response | Error;
} = {}) {
  return new FetchMock()
    .on(isBilling, over.billing ?? (() => FetchMock.json(chargeDone())))
    .on(isOrders, over.orders ?? (() => FetchMock.json(chargeDone())))
    .install();
}

/** A cron-mode request: the header IS the credential (the function deploys --no-verify-jwt). */
function cronReq(key: string | null): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (key !== null) headers["X-Cron-Key"] = key;
  return new Request("http://localhost/fn", { method: "POST", headers, body: "{}" });
}

/**
 * Fire `mutate()` just before the Nth `payments` UPDATE the code under test issues, i.e. inside the
 * window between the read that decided on it and the write itself. N=1 is the dispatch claim, N=2
 * is the status flip that follows it — the only two moments where another dispatcher can beat us,
 * and the only way to make either CAS return 0 rows from the outside.
 */
function raceBeforePaymentUpdate(db: FakeDb, nth: number, mutate: () => void) {
  const orig = db.from.bind(db);
  let seen = 0;
  // deno-lint-ignore no-explicit-any
  (db as any).from = (table: string) => {
    const q = orig(table);
    if (table !== "payments") return q;
    return {
      ...q,
      // deno-lint-ignore no-explicit-any
      update: (payload: any) => {
        if (++seen === nth) mutate();
        return q.update(payload);
      },
    };
  };
}
const raceBeforeClaim = (db: FakeDb, mutate: () => void) => raceBeforePaymentUpdate(db, 1, mutate);
const raceBeforeFlip = (db: FakeDb, mutate: () => void) => raceBeforePaymentUpdate(db, 2, mutate);

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

const pay = (db: FakeDb, id = "pay-1") => db.rows("payments").find((r) => r.id === id)!;

// ═══ auth ══════════════════════════════════════════════════════════════════════════════════
Deno.test("no cron key and no JWT → 401, and nobody's card is touched", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() => collectCharges(cronReq(null), db as never));
    assertEquals(e.status, 401);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("a wrong X-Cron-Key → 401 and never falls back to the JWT path", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() => collectCharges(cronReq("guess"), db as never));
    assertEquals(e.status, 401);
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "failed");
  } finally {
    net.restore();
  }
});

Deno.test("CRON_COLLECT_KEY unset → 503; an unconfigured secret must not authenticate anyone", async () => {
  const db = scene();
  const net = tossOk();
  Deno.env.delete("CRON_COLLECT_KEY");
  try {
    const e = await expectHttpError(() => collectCharges(cronReq(""), db as never));
    assertEquals(e.status, 503);
    assertEquals(net.calls.length, 0);
  } finally {
    Deno.env.set("CRON_COLLECT_KEY", CRON_KEY);
    net.restore();
  }
});

Deno.test("the right cron key runs the batch", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.mode, "cron");
    assertEquals(out.processed, 1);
    assertEquals((out.results as Row[])[0].outcome, "confirmed");
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).payment_key, "tviva_charge_1");
  } finally {
    net.restore();
  }
});

// ═══ owner mode — party gate before everything ═════════════════════════════════════════════
Deno.test("owner mode without a booking_id → 400", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() => collectCharges(req({}, "owner_jwt"), db as never));
    assertEquals(e.status, 400);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("a stranger retrying someone else's booking → 403, no charge, no state leak", async () => {
  const db = scene();
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      collectCharges(req({ booking_id: BOOKING }, "stranger_jwt"), db as never)
    );
    assertEquals(e.status, 403);
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "failed");
  } finally {
    net.restore();
  }
});

Deno.test("no oracle: an unknown booking and someone else's give the SAME status and sentence", async () => {
  // 0054:73. Two different answers here would let anyone probe booking ids for existence through
  // a debt-retry button — and the ids are exactly what the debt screen puts on the clipboard.
  const answers: Array<{ status: number; message: string }> = [];
  for (const id of ["cccccccc-cccc-cccc-cccc-cccccccccccc", BOOKING]) {
    const db = scene();
    const net = tossOk();
    try {
      const e = await expectHttpError(() => collectCharges(req({ booking_id: id }, "stranger_jwt"), db as never));
      answers.push({ status: e.status, message: e.message });
      assertEquals(net.calls.length, 0);
      assertEquals(pay(db).status, "failed"); // nothing moved for either probe
    } finally {
      net.restore();
    }
  }
  assertEquals(answers[0].status, 403);
  assertEquals(answers[0], answers[1]);
});

Deno.test("the owner's CTA works even after the ladder is spent — it is not a dead button", async () => {
  const db = scene({
    payments: [payRow({ raw: { kind: "settle_charge", attempts: 3, dispatched_at: PAST, last_error: "400:REJECT" } })],
  });
  const net = tossOk();
  try {
    const out = await collectCharges(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
    assertEquals(out.mode, "owner");
    assertEquals((out.results as Row[])[0].outcome, "confirmed");
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).raw.attempts, 4); // the manual attempt is still counted honestly
  } finally {
    net.restore();
  }
});

Deno.test("the same spent row is skipped by the CRON, which is what 'stop' means", async () => {
  const db = scene({
    payments: [payRow({ raw: { kind: "settle_charge", attempts: 3, dispatched_at: PAST, last_error: "400:REJECT" } })],
  });
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.due, 0);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("owner mode ignores widget-era rows (no raw.kind) — nothing captured, nothing to retry", async () => {
  const db = scene({ payments: [payRow({ raw: {} })] });
  const net = tossOk();
  try {
    const out = await collectCharges(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
    assertEquals(out.processed, 0);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

// ═══ batch due-selection ═══════════════════════════════════════════════════════════════════
Deno.test("the sweep picks exactly the due rows and leaves the rest alone", async () => {
  const db = scene({
    payments: [
      payRow({ id: "due-failed", order_id: "dr_due" }),
      payRow({ id: "not-yet", order_id: "dr_future", raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST, next_retry_at: FUTURE } }),
      payRow({ id: "spent", order_id: "dr_spent", raw: { kind: "settle_charge", attempts: 3, dispatched_at: PAST } }),
      payRow({ id: "widget", order_id: "dr_widget", raw: {} }),
      payRow({ id: "pending-dispatched", order_id: "dr_disp", status: "pending", raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST } }),
      payRow({ id: "pending-fresh", order_id: "dr_fresh", status: "pending", raw: { kind: "settle_charge", attempts: 0 } }),
      payRow({ id: "relink", order_id: "dr_relink", raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST, next_retry_at: PAST, needs_card_relink: true } }),
      payRow({ id: "done", order_id: "dr_done", status: "confirmed", payment_key: "tviva_old" }),
    ],
  });
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    const touched = (out.results as Row[]).map((r) => r.payment_id).sort();
    assertEquals(touched, ["due-failed", "pending-fresh"]);
    // A dispatched pending is never RE-CHARGED by the ladder (§0-ter #2) — it is asked about
    // instead (the verification arm), which is a GET, not a charge.
    assertEquals(net.calls.filter((c) => isBilling(c.url)).length, 2);
    assertEquals((out.verified as Row[]).map((r) => r.payment_id), ["pending-dispatched"]);
    assertEquals(pay(db, "relink").status, "failed");
  } finally {
    net.restore();
  }
});

Deno.test("one row exploding does not 500 the batch — the others still collect", async () => {
  const db = scene({
    payments: [
      payRow({ id: "orphan", order_id: "dr_orphan", booking_id: "dddddddd-dddd-dddd-dddd-dddddddddddd" }),
      payRow({ id: "good", order_id: "dr_good" }),
    ],
  });
  const net = tossOk();
  const orig = console.error;
  console.error = () => {};
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    const byId = Object.fromEntries((out.results as Row[]).map((r) => [r.payment_id, r]));
    assertEquals(byId["orphan"].outcome, "error");
    assertStringIncludes(String(byId["orphan"].error), "not found");
    assertEquals(byId["good"].outcome, "confirmed");
    assertEquals(pay(db, "good").status, "confirmed");
  } finally {
    console.error = orig;
    net.restore();
  }
});

// ═══ the ladder, arithmetic-exact (injected now) ═══════════════════════════════════════════
Deno.test("ladder rung 1 → +1h, rung 2 → +24h, rung 3 → stop + a notification naming the decline", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk({
    billing: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "한도 초과예요" }, 400),
  });
  try {
    const r1 = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(r1.outcome, "failed");
    assertEquals(pay(db).status, "failed");
    assertEquals(pay(db).raw.attempts, 1);
    assertEquals(pay(db).raw.next_retry_at, "2026-08-13T13:00:00.000Z");
    assertEquals(db.rows("notifications").length, 0);

    const r2 = await dispatchCharge(db as never, "pay-1", { now: new Date("2026-08-13T13:00:00.000Z") });
    assertEquals(r2.outcome, "failed");
    assertEquals(pay(db).raw.attempts, 2);
    assertEquals(pay(db).raw.next_retry_at, "2026-08-14T13:00:00.000Z");
    assertEquals(db.rows("notifications").length, 0);

    const r3 = await dispatchCharge(db as never, "pay-1", { now: new Date("2026-08-14T13:00:00.000Z") });
    assertEquals(r3.outcome, "failed");
    assertEquals(pay(db).raw.attempts, 3);
    assertEquals(pay(db).raw.next_retry_at, undefined); // stop — no fourth rung
    assertEquals(r3.next_retry_at, null);
    // ...and only NOW is the owner told, in the card company's own words.
    const notes = db.rows("notifications");
    assertEquals(notes.length, 1);
    assertEquals(notes[0].profile_id, OWNER);
    assertEquals(notes[0].kind, "booking");
    assertStringIncludes(notes[0].body, "한도 초과예요");
    assertStringIncludes(notes[0].body, "13,900");
    // The one row never became three, and every attempt reused the one orderId...
    assertEquals(db.rows("payments").length, 1);
    const billed = net.calls.filter((c) => isBilling(c.url));
    assertEquals(billed.map((c) => c.body.orderId), ["dr_1", "dr_1", "dr_1"]);
    // ...under DISTINCT per-attempt idempotency keys. One key for all three rungs would have Toss
    // replay the first decline for 15 days, and the ladder would be theatre.
    assertEquals(billed.map((c) => c.headers["Idempotency-Key"]), ["dr_1_a1", "dr_1_a2", "dr_1_a3"]);
  } finally {
    net.restore();
  }
});

Deno.test("a failed→confirmed retry flips status and payment_key in ONE statement", async () => {
  const db = scene(); // seeded row is already 'failed' with attempts 1
  let updatesBeforeFetch = 0;
  let statusAtFetch = "";
  const net = tossOk({
    billing: () => {
      updatesBeforeFetch = db.log.filter((l) => l.startsWith("update:payments")).length;
      statusAtFetch = pay(db).status;
      return FetchMock.json(chargeDone());
    },
  });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "confirmed");
    assertEquals(statusAtFetch, "failed"); // the dispatch marker does not touch status
    assertEquals(updatesBeforeFetch, 1);
    assertEquals(db.log.filter((l) => l.startsWith("update:payments")).length, 2);
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).payment_key, "tviva_charge_1");
    assertEquals(pay(db).raw.next_retry_at, undefined); // nothing is due any more
    assertEquals(pay(db).raw.attempts, 2);
  } finally {
    net.restore();
  }
});

// ═══ error map ═════════════════════════════════════════════════════════════════════════════
Deno.test("an unusable billing key is a DISTINCT state with 카드 재연결 copy, not a generic decline", async () => {
  const db = scene();
  const net = tossOk({
    billing: () => FetchMock.json({ code: "INVALID_BILL_KEY_REQUEST", message: "빌링키 정보를 확인해주세요" }, 400),
  });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "needs_card_relink");
    assertEquals(pay(db).status, "failed");
    assertEquals(pay(db).raw.needs_card_relink, true);
    assertEquals(pay(db).raw.next_retry_at, undefined); // a dead key on a timer is just noise
    const notes = db.rows("notifications");
    assertEquals(notes.length, 1);
    assertEquals(notes[0].title, "카드 재연결이 필요해요");
    assertStringIncludes(notes[0].body, "카드를 다시 연결");
    assert(!notes[0].body.includes("승인되지 않았어요"), "relink copy fell back to the decline sentence");
  } finally {
    net.restore();
  }
});

Deno.test("every relink-class code stops the ladder; nothing else does", async () => {
  for (const code of ["INVALID_BILL_KEY_REQUEST", "NOT_MATCHES_CUSTOMER_KEY", "INVALID_CARD_EXPIRATION", "INVALID_STOPPED_CARD"]) {
    const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
    const net = tossOk({ billing: () => FetchMock.json({ code, message: "카드를 사용할 수 없어요" }, 400) });
    try {
      const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
      assertEquals(res.outcome, "needs_card_relink", `${code} was not classed as relink`);
      assertEquals(pay(db).raw.next_retry_at, undefined, `${code} left a retry scheduled`);
    } finally {
      net.restore();
    }
  }
});

Deno.test("an unrecognized code defaults to the LADDER, never to a stop", async () => {
  // The dangerous direction is the other one: a code we misread as terminal silently abandons a
  // collectable charge. Transient-by-default costs at most two extra attempts.
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk({ billing: () => FetchMock.json({ code: "SOME_CODE_TOSS_ADDED_LAST_TUESDAY", message: "알 수 없는 오류" }, 400) });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "failed");
    assertEquals(pay(db).raw.next_retry_at, "2026-08-13T13:00:00.000Z");
    assertEquals(pay(db).raw.needs_card_relink, undefined);
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("IDEMPOTENT_REQUEST_PROCESSING (in flight) leaves the row pending — a shrug is not a decline", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk({
    billing: () => FetchMock.json({ code: "IDEMPOTENT_REQUEST_PROCESSING", message: "처리 중이에요" }, 409),
  });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "unresolved");
    assertEquals(pay(db).status, "pending");
    assertEquals(pay(db).raw.next_retry_at, undefined);
    assertEquals(typeof pay(db).raw.dispatched_at, "string"); // reconciliation's third arm finds it
    assertStringIncludes(String(pay(db).raw.last_error), "IDEMPOTENT_REQUEST_PROCESSING");
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("already-processed → ask Toss what the order IS; DONE means the money moved (success)", async () => {
  const db = scene();
  const net = tossOk({
    billing: () => FetchMock.json({ code: "ALREADY_PROCESSED_PAYMENT", message: "이미 처리된 결제예요" }, 400),
    orders: () => FetchMock.json(chargeDone({ paymentKey: "tviva_earlier_attempt" })),
  });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "confirmed");
    assertEquals(pay(db).status, "confirmed");
    // The key comes from the LOOKUP — the charge call never returned one.
    assertEquals(pay(db).payment_key, "tviva_earlier_attempt");
    assertEquals(net.calls.filter((c) => isOrders(c.url)).length, 1);
    assertStringIncludes(net.calls.find((c) => isOrders(c.url))!.url, "/v1/payments/orders/dr_1");
    assertEquals(net.calls.find((c) => isOrders(c.url))!.method, "GET");
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("already-processed but the order is CANCELED → a real failure, on the ladder", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk({
    billing: () => FetchMock.json({ code: "ALREADY_PROCESSED_PAYMENT" }, 400),
    orders: () => FetchMock.json({ orderId: "dr_1", status: "CANCELED" }),
  });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "failed");
    assertEquals(pay(db).status, "failed");
    assertEquals(pay(db).payment_key, null);
    assertEquals(pay(db).raw.next_retry_at, "2026-08-13T13:00:00.000Z");
    assertStringIncludes(String(pay(db).raw.last_error), "CANCELED");
  } finally {
    net.restore();
  }
});

Deno.test("a 2xx without a payment key is never written as confirmed (settled_has_key)", async () => {
  const db = scene();
  const net = tossOk({ billing: () => FetchMock.json({ orderId: "dr_1", status: "DONE", totalAmount: CHARGE }) });
  const orig = console.error;
  console.error = () => {};
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "unresolved");
    assertEquals(pay(db).status, "failed"); // unchanged from its seeded state
    assertEquals(pay(db).payment_key, null);
    assertEquals(pay(db).raw.needs_manual_review, true);
  } finally {
    console.error = orig;
    net.restore();
  }
});

Deno.test("an already-confirmed row is never re-dispatched", async () => {
  const db = scene({ payments: [payRow({ status: "confirmed", payment_key: "tviva_old" })] });
  const net = tossOk();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "confirmed");
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).raw.attempts, 1); // untouched
  } finally {
    net.restore();
  }
});

Deno.test("a waived row is never dispatched — 0원 to a PG is a request for a decline", async () => {
  const db = scene({ payments: [payRow({ status: "waived", amount: 0, raw: { kind: "settle_charge" } })] });
  const net = tossOk();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "waived");
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("no billing key → skipped_no_card, and the row is left completely untouched", async () => {
  const db = scene({ card: false, payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "skipped_no_card");
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).raw.dispatched_at, undefined);
    assertEquals(pay(db).raw.attempts, 0);
    assertEquals(db.log.filter((l) => l.startsWith("update:payments")).length, 0);
  } finally {
    net.restore();
  }
});

// ═══ the dispatch CLAIM — two dispatchers, one charge ══════════════════════════════════════
Deno.test("concurrent dispatchers: the attempt-counter CAS lets exactly ONE of them charge", async () => {
  // The cron sweep and the owner's CTA can be inside dispatchCharge on the same row at the same
  // instant. They read the same attempts, and with a status-only CAS both would write attempts+1
  // and BOTH would charge the card — two calls to Toss recorded as one attempt.
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 1 } })] });
  const net = tossOk();
  try {
    const [a, b] = await Promise.all([
      dispatchCharge(db as never, "pay-1", { now: NOW }),
      dispatchCharge(db as never, "pay-1", { manual: true, now: NOW }),
    ]);
    const outcomes = [a.outcome, b.outcome].sort();
    assertEquals(outcomes, ["confirmed", "noop"]);
    const loser = a.outcome === "noop" ? a : b;
    assertEquals(loser.error, "row_moved");
    // ONE billing call. This is the whole assertion — the rest is bookkeeping about it.
    assertEquals(net.calls.filter((c) => isBilling(c.url)).length, 1);
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).raw.attempts, 2); // one dispatch, one increment
    assertEquals(db.rows("payments").length, 1);
  } finally {
    net.restore();
  }
});

Deno.test("a competitor claiming between our read and our claim → row_moved, and no card is touched", async () => {
  // The same race, made deterministic: someone else's claim lands in the window.
  const db = scene({ payments: [payRow({ status: "failed", raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST, next_retry_at: PAST } })] });
  raceBeforeClaim(db, () => {
    pay(db).raw = { ...pay(db).raw, attempts: 2, dispatched_at: NOW.toISOString() };
  });
  const net = tossOk();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "noop");
    assertEquals(res.error, "row_moved");
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).raw.attempts, 2); // the competitor's claim stands, un-overwritten
    assertEquals(pay(db).status, "failed");
  } finally {
    net.restore();
  }
});

// ═══ not-an-answer responses are not declines ══════════════════════════════════════════════
Deno.test("a 5xx from Toss is an OUTAGE, not a decline — unresolved, no ladder, no debt", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk({ billing: () => FetchMock.json({ code: "FAILED_INTERNAL_SYSTEM_PROCESSING", message: "내부 오류" }, 500) });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "unresolved");
    // The row stays a dispatched pending: reconciliation's, and the verification arm's.
    assertEquals(pay(db).status, "pending");
    assertEquals(pay(db).payment_key, null);
    assertEquals(pay(db).raw.next_retry_at, undefined);
    assertEquals(typeof pay(db).raw.dispatched_at, "string");
    assertStringIncludes(String(pay(db).raw.last_error), "500");
    // No decline notification — nobody's card said anything.
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("a 502 on the THIRD rung does not become a debt notification (the failure that lies)", async () => {
  // The dangerous version of the same bug: at attempts 2 the ladder would write the last rung,
  // notify the owner that their card was declined, and hand the row to the debt derivation —
  // all from an outage in which no card was ever asked.
  const db = scene({ payments: [payRow({ raw: { kind: "settle_charge", attempts: 2, dispatched_at: PAST, next_retry_at: PAST } })] });
  const net = tossOk({ billing: () => FetchMock.json({ message: "Bad Gateway" }, 502) });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "unresolved");
    assertEquals(db.rows("notifications").length, 0);
    assertEquals(pay(db).status, "failed"); // unchanged from its seeded state — never re-written
  } finally {
    net.restore();
  }
});

Deno.test("401/403 from Toss → unresolved + a log naming TOSS_SECRET_KEY, never the owner's problem", async () => {
  for (const status of [401, 403]) {
    const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
    const net = tossOk({ billing: () => FetchMock.json({ code: "UNAUTHORIZED_KEY", message: "인증되지 않은 시크릿 키" }, status) });
    const cap = captureLogs();
    try {
      const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
      assertEquals(res.outcome, "unresolved");
      assertEquals(pay(db).status, "pending");
      assertEquals(db.rows("notifications").length, 0);
      assert(
        cap.lines.some((l) => l.includes("TOSS_SECRET_KEY") && l.includes(String(status))),
        `a credential failure did not name its cause: ${cap.lines.join("|")}`,
      );
    } finally {
      cap.restore();
      net.restore();
    }
  }
});

Deno.test("an unparseable error body is not a verdict either", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = new FetchMock()
    .on(isBilling, () => new Response("<html>gateway timeout</html>", { status: 400 }))
    .on(isOrders, () => FetchMock.json(chargeDone()))
    .install();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "unresolved");
    assertEquals(pay(db).status, "pending");
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("the billing pair carries a timeout; the widget confirm path is left alone", async () => {
  const db = scene();
  const net = tossOk({
    billing: () => FetchMock.json({ code: "ALREADY_PROCESSED_PAYMENT" }, 400),
    orders: () => FetchMock.json(chargeDone()),
  });
  try {
    await dispatchCharge(db as never, "pay-1", { now: NOW });
    // Unattended calls: nobody is waiting, and a hung socket would pin the row (and, in cron mode,
    // everything queued behind it) forever.
    for (const c of net.calls) {
      assert(c.signal instanceof AbortSignal, `${c.url} was sent without a timeout`);
    }
  } finally {
    net.restore();
  }
});

// ═══ the sticky-flag bugs ══════════════════════════════════════════════════════════════════
Deno.test("relink → card relinked → a plain decline CLEARS needs_card_relink, so the ladder runs again", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  // Both dispatches are dated in the far past so the rung they schedule is already due against the
  // real clock the cron sweep reads — the point being tested is the FLAG, not the arithmetic.
  const then = new Date(PAST);
  // ① the stored card is dead → the distinct state, ladder stopped.
  let net = tossOk({ billing: () => FetchMock.json({ code: "INVALID_STOPPED_CARD", message: "정지된 카드" }, 400) });
  try {
    await dispatchCharge(db as never, "pay-1", { now: then });
    assertEquals(pay(db).raw.needs_card_relink, true);
    const idle = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(idle.due, 0); // correct: a dead key on a timer is noise
    assertEquals(net.calls.filter((c) => isBilling(c.url)).length, 1);
  } finally {
    net.restore();
  }
  // ② the owner relinks and taps the CTA; the new card is merely over its limit today.
  net = tossOk({ billing: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "한도 초과예요" }, 400) });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { manual: true, now: then });
    assertEquals(res.outcome, "failed");
    // The flag was a statement about a card that is no longer the card. Left behind, the due rule
    // would refuse this row forever and the debt would never be retried by anything but a human.
    assertEquals(pay(db).raw.needs_card_relink, undefined);
    assertEquals(pay(db).raw.next_retry_at, "2020-01-02T00:00:00.000Z"); // rung 2 (+24h)
    const sweep = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(sweep.due, 1); // ...and the timer owns the row again
  } finally {
    net.restore();
  }
});

Deno.test("a successful charge clears needs_card_relink too — a paid row never asks for a new card", async () => {
  const db = scene({
    payments: [payRow({ raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST, needs_card_relink: true } })],
  });
  const net = tossOk();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { manual: true, now: NOW });
    assertEquals(res.outcome, "confirmed");
    assertEquals(pay(db).raw.needs_card_relink, undefined);
  } finally {
    net.restore();
  }
});

Deno.test("a declined result carries the row's last_error, so the caller can name the decline", async () => {
  const db = scene({ payments: [payRow({ status: "pending", raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk({ billing: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "한도 초과예요" }, 400) });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "failed");
    assertEquals(res.error, pay(db).raw.last_error);
    assertStringIncludes(String(res.error), "한도 초과예요");
  } finally {
    net.restore();
  }
});

// ═══ the lost flip ═════════════════════════════════════════════════════════════════════════
Deno.test("losing the flip to a DIFFERENT payment_key is a double capture, never a plain 'confirmed'", async () => {
  const db = scene();
  const net = tossOk({
    // Our charge succeeds with our key...
    billing: () => FetchMock.json(chargeDone({ paymentKey: "tviva_ours" })),
  });
  // ...but between our claim and our flip, another dispatcher recorded a DIFFERENT capture.
  raceBeforeFlip(db, () => {
    const r = pay(db);
    r.status = "confirmed";
    r.payment_key = "tviva_theirs";
    r.raw = { ...r.raw, charge: { paymentKey: "tviva_theirs" } };
  });
  const cap = captureLogs();
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assert(res.outcome !== "confirmed", "a second capture was reported as a clean collection");
    assertEquals(res.outcome, "unresolved");
    assertStringIncludes(String(res.error), "double_capture");
    // The marker MERGES — the other dispatcher's evidence is still on the row.
    assertEquals(pay(db).raw.needs_manual_review, true);
    assertEquals((pay(db).raw.charge as Row).paymentKey, "tviva_theirs");
    assertEquals((pay(db).raw.double_capture as Row).ours, "tviva_ours");
    assertEquals(pay(db).payment_key, "tviva_theirs"); // never overwritten behind ops' back
    assert(cap.lines.some((l) => l.includes("DOUBLE CAPTURE")), `silent double capture: ${cap.lines.join("|")}`);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("losing the flip to the SAME payment_key is just the other dispatcher — plain confirmed", async () => {
  const db = scene();
  const net = tossOk();
  raceBeforeFlip(db, () => {
    const r = pay(db);
    r.status = "confirmed";
    r.payment_key = "tviva_charge_1"; // the same capture, recorded by the winner
  });
  try {
    const res = await dispatchCharge(db as never, "pay-1", { now: NOW });
    assertEquals(res.outcome, "confirmed");
    assertEquals(pay(db).raw.needs_manual_review, undefined);
  } finally {
    net.restore();
  }
});

// ═══ the unified due rule ══════════════════════════════════════════════════════════════════
Deno.test("a failed row with NO next_retry_at is DUE — the sweep-flipped no-card row is real debt", async () => {
  // The shape: a card-less owner's settle intent (never dispatched, no rung written) that the SQL
  // stale sweep flipped to 'failed'. Under a rule that required a next_retry_at it was invisible
  // to the collector forever, while `owner_has_unsettled_charge` counted it as debt — a locked
  // account with nothing on earth able to unlock it.
  const db = scene({ payments: [payRow({ raw: { kind: "settle_charge", attempts: 0 } })] });
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.due, 1);
    assertEquals((out.results as Row[])[0].outcome, "confirmed");
    assertEquals(pay(db).status, "confirmed");
  } finally {
    net.restore();
  }
});

Deno.test("...but the attempt cap and the relink flag still exempt a row without a rung", async () => {
  const db = scene({
    payments: [
      payRow({ id: "spent-norung", order_id: "dr_a", raw: { kind: "settle_charge", attempts: 3 } }),
      payRow({ id: "relink-norung", order_id: "dr_b", raw: { kind: "settle_charge", attempts: 1, needs_card_relink: true } }),
    ],
  });
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.due, 0);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

// ═══ BATCH_LIMIT bounds the CANDIDATES, not the table ══════════════════════════════════════
Deno.test("200 widget-era rows do not starve the batch — the one collectable row is still collected", async () => {
  // Widget-era pending/failed rows (no raw.kind) accumulate and never age out. Ordered by
  // created_at and filtered only in TS, they fill BATCH_LIMIT and every real charge behind them
  // is silently never attempted — which looks identical to "nothing was due".
  const rows: Row[] = [];
  for (let i = 0; i < 200; i++) {
    rows.push(payRow({
      id: `widget-${i}`, order_id: `dr_w${i}`, status: "pending", raw: {},
      created_at: `2026-08-01T00:00:${String(i % 60).padStart(2, "0")}Z`,
    }));
  }
  rows.push(payRow({ id: "real", order_id: "dr_real", created_at: "2026-08-13T00:00:00Z" }));
  const db = scene({ payments: rows });
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.scanned, 1); // the query itself refuses to spend the budget on widget rows
    assertEquals(out.due, 1);
    assertEquals((out.results as Row[])[0].payment_id, "real");
    assertEquals(pay(db, "real").status, "confirmed");
  } finally {
    net.restore();
  }
});

// ═══ the verification arm — the automatic resolver for an outage ═══════════════════════════
// `dispatched_at` is compared against the REAL clock (the cron passes no injected `now`), so the
// fixture uses a marker that is unambiguously older than the 15-minute window under any clock.
const stalePending = (over: Row = {}) =>
  payRow({
    status: "pending",
    raw: { kind: "settle_charge", attempts: 1, dispatched_at: PAST },
    ...over,
  });

Deno.test("verification: a long-dispatched pending that Toss says is DONE flips confirmed WITH the key", async () => {
  const db = scene({ payments: [stalePending()] });
  const net = tossOk({ orders: () => FetchMock.json(chargeDone({ paymentKey: "tviva_verified" })) });
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.due, 0); // it is NOT the ladder's row
    assertEquals(net.calls.filter((c) => isBilling(c.url)).length, 0); // and it is never re-charged
    assertEquals((out.verified as Row[])[0].outcome, "confirmed");
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).payment_key, "tviva_verified");
    // Status and key in ONE statement (payments_settled_has_key), and the marker's history stays.
    assertEquals(db.log.filter((l) => l.startsWith("update:payments")).length, 1);
    assertEquals(pay(db).raw.attempts, 1);
    assertEquals(typeof pay(db).raw.verified_at, "string");
  } finally {
    net.restore();
  }
});

Deno.test("verification: NOT_FOUND means the charge never reached Toss — the marker is cleared, attempts kept", async () => {
  const db = scene({ payments: [stalePending()] });
  const net = tossOk({ orders: () => FetchMock.json({ code: "NOT_FOUND_PAYMENT", message: "존재하지 않는 결제" }, 404) });
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals((out.verified as Row[])[0].outcome, "redispatchable");
    assertEquals(pay(db).status, "pending");
    assertEquals(pay(db).raw.dispatched_at, undefined); // the false statement is gone
    assertEquals(pay(db).raw.attempts, 1); // the try really happened; the budget is a count of tries
    assertEquals(net.calls.filter((c) => isBilling(c.url)).length, 0); // not re-charged in THIS sweep
  } finally {
    net.restore();
  }
  // ...and the next sweep picks it up through the normal never-dispatched-pending path.
  const net2 = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.due, 1);
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).raw.attempts, 2);
  } finally {
    net2.restore();
  }
});

Deno.test("verification: anything else leaves the row exactly where reconciliation expects it", async () => {
  for (const reply of [
    () => FetchMock.json({ code: "FAILED_INTERNAL_SYSTEM_PROCESSING" }, 500),
    () => FetchMock.json({ orderId: "dr_1", status: "IN_PROGRESS" }),
  ]) {
    const db = scene({ payments: [stalePending()] });
    const net = tossOk({ orders: reply });
    try {
      const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
      assertEquals((out.verified as Row[])[0].outcome, "unresolved");
      assertEquals(pay(db).status, "pending");
      assertEquals(typeof pay(db).raw.dispatched_at, "string"); // still dispatched-pending
      assertEquals(db.rows("notifications").length, 0);
    } finally {
      net.restore();
    }
  }
});

Deno.test("verification: a DONE order for a DIFFERENT amount is a dispute, not a collection", async () => {
  const db = scene({ payments: [stalePending()] });
  const net = tossOk({ orders: () => FetchMock.json(chargeDone({ totalAmount: 99000 })) });
  const cap = captureLogs();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals((out.verified as Row[])[0].outcome, "unresolved");
    assertEquals(pay(db).status, "pending");
    assertEquals(pay(db).payment_key, null);
    assertEquals(pay(db).raw.needs_manual_review, true);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("verification leaves a FRESHLY dispatched pending alone — it is simply in flight", async () => {
  const db = scene({
    payments: [stalePending({
      raw: { kind: "settle_charge", attempts: 1, dispatched_at: new Date(Date.now() - 60_000).toISOString() },
    })],
  });
  const net = tossOk();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    assertEquals(out.due, 0);
    assertEquals((out.verified as Row[]).length, 0);
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "pending");
  } finally {
    net.restore();
  }
});

Deno.test("one row's verification exploding does not 500 the batch", async () => {
  const db = scene({
    payments: [stalePending({ id: "bad", order_id: "dr_bad" }), stalePending({ id: "good", order_id: "dr_good" })],
  });
  const net = new FetchMock()
    .on((u) => u.includes("dr_bad"), () => new Error("connection reset"))
    .on(isOrders, () => FetchMock.json(chargeDone({ paymentKey: "tviva_verified" })))
    .install();
  const cap = captureLogs();
  try {
    const out = await collectCharges(cronReq(CRON_KEY), db as never) as Row;
    const byId = Object.fromEntries((out.verified as Row[]).map((r) => [r.payment_id, r]));
    assertEquals(byId["bad"].outcome, "error");
    assertEquals(byId["good"].outcome, "confirmed");
    assertEquals(pay(db, "good").status, "confirmed");
    assertEquals(pay(db, "bad").status, "pending");
  } finally {
    cap.restore();
    net.restore();
  }
});
