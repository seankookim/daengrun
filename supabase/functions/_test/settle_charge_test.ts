// settle-run's collection branch — the ordering law and every §0-ter rule it touches.
//
//   deno test -A supabase/functions/_test/
//
// What these tests are NOT: proof that Toss behaves as mocked (plan §4-1 — the sandbox matrix
// §4-2 is that half of the rail), and not a pin on the charge AMOUNT. The amount is computed by
// `compute_owner_charge`/`mint_settle_charge_intent` in SQL on purpose (0066 lesson: money logic
// in Deno is unpinnable), so what is pinned here is that settle-run passes the right ARGUMENTS
// and charges whatever SQL returned — never a number of its own.
//
// ⚠ Read this before "improving" an assertion: the collection outcome is asserted on the DB row
// and the server LOG, never on the response body, because the caller of settle-run is the RUNNER
// and the owner's card state is not theirs. A test that reads `out.collection` would be pinning a
// privacy leak.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { settleRun } from "../settle-run/handler.ts";
import { FakeDb, FetchMock, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const PAY = "pay-mint-1";
const ORDER = "dr_mint_1";
const CHARGE = 13900; // 7,900 + 3,000×2 — the owner side (ctx.ts ownerBaseFare), computed in SQL

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");

const isBilling = (u: string) => u.includes("api.tosspayments.com/v1/billing/");
const isOrders = (u: string) => u.includes("/v1/payments/orders/");

function scene(over: { booking?: Row; card?: boolean } = {}) {
  const db = new FakeDb();
  db.users["runner_jwt"] = RUNNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "active",
    km: 2, min_fare: 9900, addons: [], base_fare: 7900, distance_fare: 6000, addon_fare: 0,
    total_price: CHARGE, ...over.booking,
  }]);
  db.seed("runners", [{ profile_id: RUNNER, commission_rate: 0.33 }]);
  db.seed("profiles", [{ id: OWNER, toss_customer_key: "cust_owner_1" }]);
  db.seed("billing_keys", over.card === false ? [] : [{ profile_id: OWNER, billing_key: "bkey_1" }]);
  db.seed("payments", []);
  db.seed("notifications", []);
  db.rpcs["settle_run_tx"] = () => ({ data: { total_runs: 5, drop: null } });
  return db;
}

/**
 * Stand-in for 0080's `mint_settle_charge_intent` (Unit A). It writes the row the real function
 * writes and returns the real function's shape — `returns table(...)`, so an ARRAY. The args it
 * was called with are handed back so tests can pin what settle-run passed it.
 */
function installMint(db: FakeDb, over: { status?: string; amount?: number; minted?: boolean; notLive?: boolean } = {}) {
  const seen: Row[] = [];
  db.rpcs["mint_settle_charge_intent"] = (args: Row) => {
    seen.push(args);
    // `notLive` is the amended contract's cutover arm: charging off (ops_flags.payments_live_since
    // null) or a run that ended before the cutover instant → the function mints NOTHING and
    // returns ZERO ROWS. An empty array is what PostgREST hands back for that.
    if (over.notLive) return { data: [] };
    const status = over.status ?? "pending";
    const amount = over.amount ?? CHARGE;
    db.rows("payments").push({
      id: PAY,
      booking_id: args.p_booking,
      order_id: ORDER,
      amount,
      status,
      payment_key: status === "confirmed" ? "tviva_prepaid" : null,
      refunded_amount: 0,
      raw: { kind: "settle_charge", attempts: 0 },
      created_at: "2026-08-13T00:00:00Z",
    });
    return { data: [{ payment_id: PAY, order_id: ORDER, amount, status, minted: over.minted ?? true }] };
  };
  return seen;
}

const chargeDone = (over: Record<string, unknown> = {}) => ({
  paymentKey: "tviva_charge_1", orderId: ORDER, status: "DONE", totalAmount: CHARGE, ...over,
});

function tossOk(over: { billing?: (c: unknown, n: number) => Response | Error } = {}) {
  return new FetchMock()
    .on(isBilling, over.billing ?? (() => FetchMock.json(chargeDone())))
    .on(isOrders, () => FetchMock.json(chargeDone()))
    .install();
}

const body = (over: Record<string, unknown> = {}) => ({
  booking_id: BOOKING, end_reason: "completed", actual_km: 2, duration_sec: 1200, ...over,
});
const pay = (db: FakeDb) => db.rows("payments")[0];

/** The collection verdict is server-side only, so the log IS the observation surface. */
function captureLogs() {
  const lines: string[] = [];
  const log = console.log, err = console.error;
  console.log = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  console.error = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  return { lines, restore: () => { console.log = log; console.error = err; } };
}
function collectionLine(lines: string[]): string {
  // "collection booking=" and not just "collection ", so the error line
  // ("[settle-run] collection branch failed …") cannot be mistaken for the verdict line.
  const l = lines.find((x) => x.includes("[settle-run] collection booking="));
  assert(l, `no collection log line: ${lines.join(" | ")}`);
  return l;
}

// The runner-facing response, byte-for-byte the pre-charge-slice shape.
const SETTLE_KEYS = ["drop", "fee", "gross", "guarantee", "net", "total_runs"];
function assertRunnerShape(out: Row) {
  assertEquals(Object.keys(out).sort(), SETTLE_KEYS);
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

// ═══ happy path ════════════════════════════════════════════════════════════════════════════
Deno.test("charge fires AFTER settle_run_tx and the row lands confirmed with the payment key", async () => {
  const db = scene();
  installMint(db);
  let logAtFetch: string[] = [];
  const net = tossOk({
    billing: () => {
      logAtFetch = db.log.slice();
      return FetchMock.json(chargeDone());
    },
  });
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    // The settlement half is untouched by any of this.
    assertEquals(out.gross, 15900); // 9,900 runner base + 3,000×2 — the RUNNER side, not the owner's
    assertEquals(out.total_runs, 5);
    // Ordering law: the ledger transaction is committed before the charge is even minted.
    const tx = db.log.indexOf("rpc:settle_run_tx");
    const mint = db.log.indexOf("rpc:mint_settle_charge_intent");
    assert(tx >= 0 && mint > tx, `charge minted before settlement: ${db.log.join(" ")}`);
    assert(logAtFetch.includes("rpc:settle_run_tx"), "billing call happened before settle_run_tx");
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).payment_key, "tviva_charge_1");
    assertEquals(pay(db).raw.kind, "settle_charge"); // the mint's marker survives the flip
    assertEquals(pay(db).raw.next_retry_at, undefined);
    // The outcome exists exactly once, in the server log.
    assertStringIncludes(collectionLine(cap.lines), "collection=confirmed detail=confirmed");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("PRIVACY: the runner's response never carries the owner's collection outcome", async () => {
  // The runner is paid either way (ordering law), so the card outcome is nothing they can act on —
  // it is only something they would learn about a client. The response shape is the pre-slice one.
  for (const arm of [{}, { status: "waived", amount: 0 }, { notLive: true }] as const) {
    const db = scene();
    installMint(db, arm);
    const net = tossOk({ billing: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "거절" }, 400) });
    const cap = captureLogs();
    try {
      const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
      assertRunnerShape(out);
      assertEquals(out.collection, undefined);
      assertEquals(out.collection_detail, undefined);
      assertEquals(JSON.stringify(out).includes("collection"), false);
    } finally {
      cap.restore();
      net.restore();
    }
  }
});

Deno.test("charging not live yet (mint returns ZERO ROWS) — nothing minted, nothing dispatched", async () => {
  const db = scene();
  const seen = installMint(db, { notLive: true });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    // The settlement is exactly as it was before this slice existed — the card-less pilot's run.
    assertEquals(out.gross, 15900);
    assertRunnerShape(out);
    assertEquals(seen.length, 1); // SQL was asked; SQL is the one that said "not live"
    assertEquals(net.calls.length, 0);
    // No row at all: not a pending waiting to be swept, not a debt, not a false unsettled charge.
    assertEquals(db.rows("payments").length, 0);
    assertEquals(db.rows("notifications").length, 0);
    assertStringIncludes(collectionLine(cap.lines), "collection=skipped_not_live detail=not_live");
    assert(!cap.lines.some((l) => l.includes("collection branch failed")), "zero rows was treated as an error");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("dispatched_at + attempts are written to the row BEFORE the HTTP call (§0-ter #2)", async () => {
  const db = scene();
  installMint(db);
  let rawAtFetch: Row = {};
  let updatesBeforeFetch = 0;
  const net = tossOk({
    billing: () => {
      rawAtFetch = { ...pay(db).raw };
      updatesBeforeFetch = db.log.filter((l) => l.startsWith("update:payments")).length;
      return FetchMock.json(chargeDone());
    },
  });
  const cap = captureLogs();
  try {
    await settleRun(req(body(), "runner_jwt"), db as never);
    assertEquals(typeof rawAtFetch.dispatched_at, "string");
    assertEquals(rawAtFetch.attempts, 1);
    assertEquals(updatesBeforeFetch, 1); // exactly the marker, nothing else
    // ...and the flip that follows is ONE more statement, carrying status + payment_key together
    // (payments_settled_has_key would reject any two-statement version of this).
    assertEquals(db.log.filter((l) => l.startsWith("update:payments")).length, 2);
    assertEquals(pay(db).status, "confirmed");
    assertEquals(pay(db).payment_key, "tviva_charge_1");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("the billing call carries a per-attempt Idempotency-Key, our order_id, and SQL's amount", async () => {
  const db = scene();
  installMint(db, { amount: 11111 }); // a number no Deno code could have computed
  const net = tossOk({ billing: () => FetchMock.json(chargeDone({ totalAmount: 11111 })) });
  const cap = captureLogs();
  try {
    await settleRun(req(body(), "runner_jwt"), db as never);
    const call = net.calls.find((c) => isBilling(c.url))!;
    assertStringIncludes(call.url, "/v1/billing/bkey_1");
    // Attempt-scoped: a 15-day key replay would otherwise turn rungs 2 and 3 into no-ops.
    assertEquals(call.headers["Idempotency-Key"], `${ORDER}_a1`);
    // ...while the orderId — the thing that actually forbids a second charge — is constant.
    assertEquals(call.body.orderId, ORDER);
    assertEquals(call.body.amount, 11111);
    assertEquals(call.body.customerKey, "cust_owner_1");
    assertEquals(call.body.orderName, "댕런 산책 이용료");
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ the ordering law under failure ════════════════════════════════════════════════════════
Deno.test("a declined card NEVER unwinds the settlement — 200 with the runner's money intact", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk({
    billing: () => FetchMock.json({ code: "REJECT_CARD_COMPANY", message: "한도 초과예요" }, 400),
  });
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    assertEquals(out.gross, 15900);
    assertEquals(out.net, 15900 - Math.round(15900 * 0.33));
    assertEquals(out.total_runs, 5);
    assertRunnerShape(out); // the decline is invisible to the runner, by design
    assertStringIncludes(collectionLine(cap.lines), "collection=failed");
    // ...but the server log NAMES it. The outcome word alone ('failed') cannot distinguish a card
    // company's refusal from a mint that exploded, and this line is the only place the operator
    // sees the difference without opening the table.
    assertStringIncludes(collectionLine(cap.lines), "REJECT_CARD_COMPANY");
    assertStringIncludes(collectionLine(cap.lines), "한도 초과예요");
    assertEquals(pay(db).status, "failed");
    assertEquals(pay(db).payment_key, null); // payments_settled_has_key stays satisfiable
    assertEquals(pay(db).raw.attempts, 1);
    assertStringIncludes(String(pay(db).raw.last_error), "REJECT_CARD_COMPANY");
    // First rung: +1h, and the owner is NOT notified yet (the ladder still has road left).
    const dt = Date.parse(String(pay(db).raw.next_retry_at)) - Date.now();
    assert(Math.abs(dt - 3600_000) < 5000, `first rung is not +1h: ${dt}ms`);
    assertEquals(db.rows("notifications").length, 0);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("the mint RPC exploding does not fail the settlement either", async () => {
  const db = scene();
  db.rpcs["mint_settle_charge_intent"] = () => ({ error: { message: "unknown end_reason" } });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    assertEquals(out.gross, 15900);
    assertRunnerShape(out);
    assertEquals(net.calls.length, 0); // nothing was charged against a row that does not exist
    assert(
      cap.lines.some((l) => l.includes("collection branch failed")),
      `silent swallow: ${cap.lines.join("|")}`,
    );
    assertStringIncludes(collectionLine(cap.lines), "collection=failed detail=error");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("network throw mid-charge → dispatched pending, NOT a failure (unknown ≠ declined)", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk({ billing: () => new Error("connection reset") });
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    assertRunnerShape(out);
    // coarse 'failed' = not collected; the detail says which kind of not-collected.
    assertStringIncludes(collectionLine(cap.lines), "collection=failed detail=unresolved");
    assertEquals(pay(db).status, "pending"); // ← the pin: never auto-failed
    assertEquals(typeof pay(db).raw.dispatched_at, "string");
    assertEquals(pay(db).raw.next_retry_at, undefined); // reconciliation's row, not the ladder's
    assertStringIncludes(String(pay(db).raw.last_error), "connection reset");
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ what SQL decides, settle-run obeys ════════════════════════════════════════════════════
Deno.test("dog_condition (G1) — mint returns waived, so nothing is charged at all", async () => {
  const db = scene();
  const seen = installMint(db, { status: "waived", amount: 0 });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await settleRun(
      req(body({ end_reason: "dog_condition", condition_note: "다리를 절어요" }), "runner_jwt"),
      db as never,
    ) as Row;
    assertRunnerShape(out);
    assertStringIncludes(collectionLine(cap.lines), "collection=waived detail=waived");
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "waived");
    assertEquals(pay(db).amount, 0);
    assertEquals(seen[0].p_end_reason, "dog_condition");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("runner_personal — the reason and the actual km go to SQL; Deno computes no basis", async () => {
  const db = scene();
  // 3,000×1.2 = 3,600: distance ONLY, no 7,900 base, no addons (§0-ter #10). The number comes
  // from the mint; this test pins that settle-run charges exactly what it was handed.
  const seen = installMint(db, { amount: 3600 });
  const net = tossOk({ billing: () => FetchMock.json(chargeDone({ totalAmount: 3600 })) });
  const cap = captureLogs();
  try {
    const out = await settleRun(
      req(body({ end_reason: "runner_personal", actual_km: 1.2 }), "runner_jwt"),
      db as never,
    ) as Row;
    assertRunnerShape(out);
    assertStringIncludes(collectionLine(cap.lines), "collection=confirmed");
    assertEquals(seen.length, 1);
    assertEquals(seen[0].p_booking, BOOKING);
    assertEquals(seen[0].p_end_reason, "runner_personal");
    assertEquals(seen[0].p_actual_km, 1.2);
    assertEquals(net.calls.find((c) => isBilling(c.url))!.body.amount, 3600);
    assertEquals(pay(db).amount, 3600);
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("an over-run passes the ACTUAL km to SQL — the min(actual, planned) ceiling is SQL's", async () => {
  const db = scene();
  // 5km actual on a 2km plan: settle-run must NOT clamp anything on its way to the mint (the
  // runner is paid on the actual within the band), and the owner's ceiling is applied in SQL.
  const seen = installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body({ actual_km: 5 }), "runner_jwt"), db as never) as Row;
    assertEquals(seen[0].p_actual_km, 5);
    assertRunnerShape(out);
    assertStringIncludes(collectionLine(cap.lines), "collection=confirmed");
    assertEquals(net.calls.find((c) => isBilling(c.url))!.body.amount, CHARGE); // the capped number SQL returned
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("a prepaid (widget-era) booking is never charged twice", async () => {
  const db = scene();
  installMint(db, { status: "confirmed", minted: false });
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    assertRunnerShape(out);
    assertStringIncludes(collectionLine(cap.lines), "collection=prepaid detail=prepaid");
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "confirmed");
  } finally {
    cap.restore();
    net.restore();
  }
});

Deno.test("no billing key → skipped_no_card, and the row stays a NEVER-dispatched pending", async () => {
  const db = scene({ card: false });
  installMint(db);
  const net = tossOk();
  const cap = captureLogs();
  try {
    const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
    assertRunnerShape(out);
    assertStringIncludes(collectionLine(cap.lines), "collection=skipped_no_card");
    assertEquals(net.calls.length, 0);
    assertEquals(pay(db).status, "pending");
    // No dispatch marker: this is the only pending shape the stale sweep may close (§0-ter #2),
    // and the debt derivation still finds it. A marker here would hide it from both.
    assertEquals(pay(db).raw.dispatched_at, undefined);
    assertEquals(pay(db).raw.attempts, 0);
  } finally {
    cap.restore();
    net.restore();
  }
});

// ═══ gates ═════════════════════════════════════════════════════════════════════════════════
Deno.test("an end_reason outside the enum → 400, and NOTHING is settled or charged", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      settleRun(req(body({ end_reason: "vibes" }), "runner_jwt"), db as never)
    );
    assertEquals(e.status, 400);
    assertStringIncludes(e.message, "종료 사유");
    assert(!db.log.includes("rpc:settle_run_tx"), "an unknown reason reached the settlement tx");
    assert(!db.log.includes("rpc:mint_settle_charge_intent"));
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("the party gate still runs before the reason whitelist (a stranger learns nothing)", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk();
  try {
    const e = await expectHttpError(() =>
      settleRun(req(body({ end_reason: "vibes" }), "stranger_jwt"), db as never)
    );
    assertEquals(e.status, 403);
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

// ═══ ruling ①: WHO may declare an end_reason ═══════════════════════════════════════════════
// Sean's ruling ① (2026-08-13, docs/decisions-open-money.md — "verify incident first to avoid
// abuse of this feature") makes `incident` mean the owner is charged NOTHING. settle-run is a
// public HTTP endpoint whose caller is the assigned runner, so a whitelist that accepted the whole
// enum would be a self-serve free-run button: POST `end_reason: 'incident'` and the run is free.
// The accepted set is now the four the client type offers (api.ts:981); `incident` belongs to the
// custody path (0045) and `owner_forced` to ops.
//
// ⚠ These two tests are the guard on that gap. Adding "incident"/"owner_forced" back to
// settle-run's whitelist — the obvious "fix" for a reader who notices it does not match the enum —
// reddens exactly here.
for (const reason of ["incident", "owner_forced"]) {
  Deno.test(`a runner declaring '${reason}' is refused 400 — nothing settled, nothing charged`, async () => {
    const db = scene();
    installMint(db);
    const net = tossOk();
    try {
      const e = await expectHttpError(() =>
        settleRun(req(body({ end_reason: reason, condition_note: "x" }), "runner_jwt"), db as never)
      );
      assertEquals(e.status, 400);
      // Honest about WHY: the server knows this reason and refuses it. "Update your app" would be
      // a lie that sends the runner chasing a version which will never accept it.
      assertStringIncludes(e.message, "이 사유로는 정산할 수 없어요");
      assert(!e.message.includes("최신 버전"), `refusal pretends the reason is unknown: ${e.message}`);
      // The run is not settled, the runner is not paid on this reason, and no waived row exists.
      assert(!db.log.includes("rpc:settle_run_tx"), `'${reason}' reached the settlement tx`);
      assert(!db.log.includes("rpc:mint_settle_charge_intent"), `'${reason}' reached the mint`);
      assertEquals(db.rows("payments").length, 0);
      assertEquals(net.calls.length, 0);
    } finally {
      net.restore();
    }
  });

  Deno.test(`'${reason}' refusal happens AFTER the party gate — never an oracle`, async () => {
    // A stranger probing which reasons the server treats specially must get the same 403 they get
    // for any other body. If this returned 400 it would confirm both that the booking exists and
    // that this reason is special, from an unauthenticated-for-this-booking caller.
    const db = scene();
    installMint(db);
    const net = tossOk();
    try {
      const e = await expectHttpError(() =>
        settleRun(req(body({ end_reason: reason }), "stranger_jwt"), db as never)
      );
      assertEquals(e.status, 403);
      assertEquals(e.message, "assigned runner only");
      assertEquals(net.calls.length, 0);
    } finally {
      net.restore();
    }
  });
}

Deno.test("all four client reasons still settle — the fix narrows, it does not break the app", async () => {
  // api.ts:981's union, exactly. If one of these ever 400s, every runner ending a run that way is
  // stuck holding a dog with no way to close the job.
  const cases = [
    { end_reason: "completed" },
    { end_reason: "dog_condition", condition_note: "다리를 절어요" },
    { end_reason: "owner_request" },
    { end_reason: "runner_personal" },
  ];
  for (const c of cases) {
    const db = scene();
    const seen = installMint(db);
    const net = tossOk();
    const cap = captureLogs();
    try {
      const out = await settleRun(req(body(c), "runner_jwt"), db as never) as Row;
      assertRunnerShape(out);
      assert(db.log.includes("rpc:settle_run_tx"), `${c.end_reason} never settled`);
      assertEquals(seen.length, 1);
      assertEquals(seen[0].p_end_reason, c.end_reason); // the reason reaches SQL unmodified
    } finally {
      cap.restore();
      net.restore();
    }
  }
});

Deno.test("settle_run_tx refusing (not_active) → 409 and the charge machine never starts", async () => {
  const db = scene();
  installMint(db);
  db.rpcs["settle_run_tx"] = () => ({ error: { message: "not_active" } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() => settleRun(req(body(), "runner_jwt"), db as never));
    assertEquals(e.status, 409);
    assert(!db.log.includes("rpc:mint_settle_charge_intent"), "a failed settlement minted a charge");
    assertEquals(net.calls.length, 0);
    assertEquals(db.rows("payments").length, 0);
  } finally {
    net.restore();
  }
});

Deno.test("the km validity band still rejects a 999km claim before any of this", async () => {
  const db = scene();
  installMint(db);
  const net = tossOk();
  try {
    const e = await expectHttpError(() => settleRun(req(body({ actual_km: 999 }), "runner_jwt"), db as never));
    assertEquals(e.status, 400);
    assert(!db.log.includes("rpc:settle_run_tx"));
    assertEquals(net.calls.length, 0);
  } finally {
    net.restore();
  }
});

// ═══════════════════════════════════════════════════════════════════════════════════════════
// 0083 §6-ⓔ — the FROZEN path: after `end_run_tx`, the body is not a financial input
// ═══════════════════════════════════════════════════════════════════════════════════════════
// These exist because the migration's gate alone was not enough. The gate refuses a mismatch;
// this half makes a mismatch impossible from the shipping caller by reading the frozen row. The
// distinction matters: a refusal leaves the runner unpaid, a read pays them the right amount.

/** A booking that went through `end_run_tx`: stop stamped, run row frozen. */
function frozenScene(frozen: Row = {}) {
  const db = scene({ booking: { run_ended_at: "2026-08-13T10:00:00Z" } });
  db.seed("runs", [{
    booking_id: BOOKING, actual_km: 3.25, end_reason: "completed",
    duration_sec: 1800, condition_note: null, ...frozen,
  }]);
  return db;
}

Deno.test("frozen: an inflated body is IGNORED — tx and mint both get the frozen numbers", async () => {
  const db = frozenScene();
  const mint = installMint(db);
  let txArgs: Row = {};
  db.rpcs["settle_run_tx"] = (a: Row) => { txArgs = a; return { data: { total_runs: 5, drop: null } }; };
  const net = tossOk();
  try {
    // The attack from the adversarial review: stop at 3.25km, then claim 9.9km + owner_request
    // (which would also add the 50% guarantee and bill the owner the full planned distance).
    await settleRun(req(body({ actual_km: 9.9, end_reason: "owner_request" }), "runner_jwt"), db as never);
    assertEquals(txArgs.p_actual_km, 3.25, "settlement used the body's km, not the frozen one");
    assertEquals(txArgs.p_end_reason, "completed", "settlement used the body's reason");
    assertEquals(mint[0].p_actual_km, 3.25, "the CHARGE used the body's km");
    assertEquals(mint[0].p_end_reason, "completed", "the CHARGE used the body's reason");
  } finally {
    net.restore();
  }
});

Deno.test("frozen: no guarantee is paid for a body-claimed owner_request the freeze never recorded", async () => {
  const db = frozenScene();
  installMint(db);
  const net = tossOk();
  try {
    const out = await settleRun(
      req(body({ actual_km: 9.9, end_reason: "owner_request" }), "runner_jwt"), db as never,
    ) as { guarantee: number };
    assertEquals(out.guarantee, 0, "the body bought itself the owner_request guarantee");
  } finally {
    net.restore();
  }
});

Deno.test("frozen: a body reason this endpoint would normally REFUSE is simply ignored", async () => {
  // Not a refusal: on a frozen run the whitelist is irrelevant, because `end_run_tx` already
  // whitelisted at the freeze. Refusing here would strand a runner over a stale client build.
  const db = frozenScene();
  installMint(db);
  const net = tossOk();
  try {
    const out = await settleRun(
      req(body({ end_reason: "incident" }), "runner_jwt"), db as never,
    ) as { total_runs: number };
    assertEquals(out.total_runs, 5, "a frozen run was refused because the BODY said 'incident'");
  } finally {
    net.restore();
  }
});

Deno.test("frozen: a stamped booking with no runs row fails LOUDLY, never falls back to the body", async () => {
  const db = scene({ booking: { run_ended_at: "2026-08-13T10:00:00Z" } });
  db.seed("runs", []);
  installMint(db);
  const net = tossOk();
  try {
    const e = await expectHttpError(() => settleRun(req(body({ actual_km: 9.9 }), "runner_jwt"), db as never));
    assertEquals(e.status, 500);
    assert(!db.log.includes("rpc:settle_run_tx"), "settled from the body when the frozen row was missing");
  } finally {
    net.restore();
  }
});

// ── the three refusals get their own status and sentence, not a generic 500 ────────────────
Deno.test("return_not_sealed → 409 and the dog-is-not-home sentence, not a retry prompt", async () => {
  const db = frozenScene();
  installMint(db);
  db.rpcs["settle_run_tx"] = () => ({ error: { message: 'return_not_sealed' } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() => settleRun(req(body(), "runner_jwt"), db as never));
    assertEquals(e.status, 409);
    assert(e.message.includes("인계가 확인되지 않았어요"), `wrong sentence: ${e.message}`);
    assert(!e.message.includes("재시도"), "told the runner to retry a state only a PERSON can change");
    assert(!db.log.includes("rpc:mint_settle_charge_intent"), "an unsealed run reached the charge machine");
  } finally {
    net.restore();
  }
});

Deno.test("run_not_ended → 400 telling an old build to update, never a 500 that reads as our bug", async () => {
  const db = scene();
  installMint(db);
  db.rpcs["settle_run_tx"] = () => ({ error: { message: 'run_not_ended' } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() => settleRun(req(body(), "runner_jwt"), db as never));
    assertEquals(e.status, 400);
    assert(e.message.includes("업데이트"), `wrong sentence: ${e.message}`);
  } finally {
    net.restore();
  }
});

Deno.test("frozen_measurement_mismatch → 409 with the migration's sentence (server-bug path)", async () => {
  const db = frozenScene();
  installMint(db);
  db.rpcs["settle_run_tx"] = () => ({ error: { message: 'frozen_measurement_mismatch' } });
  const net = tossOk();
  try {
    const e = await expectHttpError(() => settleRun(req(body(), "runner_jwt"), db as never));
    assertEquals(e.status, 409);
    assert(e.message.includes("동결") || e.message.includes("기록된 거리"), `wrong sentence: ${e.message}`);
  } finally {
    net.restore();
  }
});

// ═══════════════════════════════════════════════════════════════════════════════════════════
// THE JOIN — the TS↔SQL error contract, single-sourced by verification
// ═══════════════════════════════════════════════════════════════════════════════════════════
// Every test above fakes `settle_run_tx`, so they assert that the STRING 'return_not_sealed'
// maps to a 409 — never that the migration actually raises that string. Rename the exception in
// SQL, update only `119`, and this whole file stays green while the mapping is dead code. That
// is the same gap the ⑩ author found in `0085` on the same day (their pins call the SQL function
// directly; the shipping path goes through an RPC their deno side fakes), which makes it a class
// rather than an incident: **the suite pins the primitive, the product ships the path, and
// nothing tests the join.**
//
// A fake cannot be made to tell the truth about the thing it replaces. So instead of pretending,
// this reads the migration and checks the two halves against each other — the contract stays in
// one place (the SQL) and TS is verified against it rather than duplicating it on trust.
const MIGRATION = new URL("../../migrations/0083_run_end_flow.sql", import.meta.url);
const HANDLER = new URL("../settle-run/handler.ts", import.meta.url);

Deno.test("join: every error code the handler maps is one the migration actually raises", async () => {
  const sql = await Deno.readTextFile(MIGRATION);
  const ts = await Deno.readTextFile(HANDLER);
  // The codes the handler gives their own status + sentence (not_active/not_found predate 0083
  // and are raised by 0028's body, which this migration reproduces).
  for (const code of ["return_not_sealed", "run_not_ended", "frozen_measurement_mismatch"]) {
    assert(
      ts.includes(`msg.includes("${code}")`),
      `handler stopped mapping ${code} — it now falls to the generic 500 that reads as our bug`,
    );
    assert(
      sql.includes(`raise exception '${code}'`),
      `handler maps ${code} but the migration no longer raises it — the mapping is dead code`,
    );
  }
});

Deno.test("join: the Korean the runner sees is the migration's own `using detail`, not a copy", async () => {
  const sql = await Deno.readTextFile(MIGRATION);
  const ts = await Deno.readTextFile(HANDLER);
  // `raise exception 'code'\n  using detail = '...'` — the sentence the migration authored.
  const pairs = [...sql.matchAll(/raise exception '(\w+)'\s*\n\s*using detail = '([^']*)'/g)];
  const seen: string[] = [];
  for (const [, code, detail] of pairs) {
    if (!["return_not_sealed", "run_not_ended", "frozen_measurement_mismatch"].includes(code)) continue;
    seen.push(code);
    assert(
      ts.includes(detail),
      `${code}: the handler's sentence has drifted from the migration's.\n  migration: ${detail}`,
    );
  }
  // If the migration stops carrying details, this test must fail rather than vacuously pass.
  assertEquals(seen.sort(), ["frozen_measurement_mismatch", "return_not_sealed", "run_not_ended"]);
});
