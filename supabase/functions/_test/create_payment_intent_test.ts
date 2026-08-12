// create-payment-intent unit tests (toss-plan §2-7, §4-1).
//
//   deno test -A supabase/functions/_test/
//
// This function never talks to Toss, so there is no fetch to mock — which is itself the pin:
// if a future edit makes it call out to a PG before the intent row exists, the unmocked-fetch
// rejection in FakeDb's sibling harness would surface it. What matters here is that the row is
// written first, that its amount comes from `bookings.total_price`, and that the gates run in
// the repo's mandated order (party before state).
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { createPaymentIntent } from "../create-payment-intent/handler.ts";
import { FakeDb, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const CUSTOMER_KEY = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const AMOUNT = 24900;

function scene(over: { booking?: Row; payments?: Row[] } = {}) {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, status: "payment_hold", total_price: AMOUNT, ...over.booking,
  }]);
  db.seed("profiles", [
    { id: OWNER, toss_customer_key: CUSTOMER_KEY },
    { id: STRANGER, toss_customer_key: "dddddddd-dddd-dddd-dddd-dddddddddddd" },
  ]);
  db.seed("payments", over.payments ?? []);
  return db;
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

Deno.test("mints a pending intent before any money can move", async () => {
  const db = scene();
  const out = await createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;

  assertEquals(out.amount, AMOUNT);
  assertEquals(out.customer_key, CUSTOMER_KEY);
  assertEquals(out.reused, false);
  const row = db.rows("payments")[0];
  assertEquals(row.status, "pending");
  assertEquals(row.booking_id, BOOKING);
  assertEquals(row.amount, AMOUNT);
  assertEquals(row.order_id, out.order_id);
  // The intent exists with no payment_key — that is exactly what 0076 made nullable, and the
  // reason the whole file exists.
  assertEquals(row.payment_key, undefined);
});

Deno.test("order_id is server-minted and satisfies Toss's orderId grammar (6-64, alnum/-/_)", async () => {
  const db = scene();
  const a = await createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
  const id = String(a.order_id);
  assertStringIncludes(id, "dr_");
  assert(id.length >= 6 && id.length <= 64, `order_id length ${id.length}`);
  assert(/^[A-Za-z0-9_-]+$/.test(id), `order_id has illegal characters: ${id}`);
});

Deno.test("the amount comes from bookings.total_price, never from the request body", async () => {
  const db = scene();
  const out = await createPaymentIntent(
    req({ booking_id: BOOKING, amount: 100, total_price: 100 }, "owner_jwt"),
    db as never,
  ) as Row;
  assertEquals(out.amount, AMOUNT);
  assertEquals(db.rows("payments")[0].amount, AMOUNT);
});

Deno.test("anon → 401", async () => {
  const db = scene();
  const e = await expectHttpError(() => createPaymentIntent(req({ booking_id: BOOKING }), db as never));
  assertEquals(e.status, 401);
  assertEquals(db.rows("payments").length, 0);
});

Deno.test("non-owner → 403, and the state of someone else's booking is not leaked", async () => {
  const db = scene({ booking: { status: "completed" } });
  const e = await expectHttpError(() =>
    createPaymentIntent(req({ booking_id: BOOKING }, "stranger_jwt"), db as never)
  );
  // Party gate runs BEFORE the state gate — a stranger gets 403, not "지금은 결제할 수 없는 상태예요".
  assertEquals(e.status, 403);
  assertEquals(db.rows("payments").length, 0);
});

Deno.test("unknown booking → 404", async () => {
  const db = scene();
  const e = await expectHttpError(() =>
    createPaymentIntent(req({ booking_id: "00000000-0000-0000-0000-000000000000" }, "owner_jwt"), db as never)
  );
  assertEquals(e.status, 404);
});

Deno.test("missing booking_id → 400", async () => {
  const db = scene();
  const e = await expectHttpError(() => createPaymentIntent(req({}, "owner_jwt"), db as never));
  assertEquals(e.status, 400);
});

Deno.test("booking not in payment_hold → 409, no intent minted", async () => {
  const db = scene({ booking: { status: "matching" } });
  const e = await expectHttpError(() => createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never));
  assertEquals(e.status, 409);
  assertEquals(db.rows("payments").length, 0);
});

Deno.test("a priced-at-zero booking is refused rather than turned into a free reservation", async () => {
  const db = scene({ booking: { total_price: 0 } });
  const e = await expectHttpError(() => createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never));
  assertEquals(e.status, 500);
  assertEquals(db.rows("payments").length, 0);
});

Deno.test("re-entry reuses the live intent instead of piling up pendings", async () => {
  const db = scene();
  const first = await createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
  const second = await createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
  assertEquals(second.order_id, first.order_id);
  assertEquals(second.reused, true);
  assertEquals(db.rows("payments").length, 1);
});

Deno.test("a stale pending with a different amount is closed and replaced, not reused", async () => {
  const db = scene({
    payments: [{
      id: "pay-old", booking_id: BOOKING, order_id: "dr_old", amount: 9900,
      status: "pending", payment_key: null, refunded_amount: 0, raw: {},
      created_at: "2026-08-11T00:00:00Z",
    }],
  });
  const out = await createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
  assertEquals(out.reused, false);
  assertEquals(out.amount, AMOUNT);
  const old = db.rows("payments").find((r) => r.id === "pay-old")!;
  assertEquals(old.status, "failed");
  assertEquals(db.rows("payments").length, 2);
});

Deno.test("a confirmed payment on the booking does not count as a live intent", async () => {
  const db = scene({
    payments: [{
      id: "pay-done", booking_id: BOOKING, order_id: "dr_done", amount: AMOUNT,
      status: "confirmed", payment_key: "k1", refunded_amount: 0, raw: {},
      created_at: "2026-08-11T00:00:00Z",
    }],
  });
  const out = await createPaymentIntent(req({ booking_id: BOOKING }, "owner_jwt"), db as never) as Row;
  assertEquals(out.reused, false);
  assert(out.order_id !== "dr_done");
});
