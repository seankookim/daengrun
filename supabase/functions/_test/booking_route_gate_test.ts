// create-booking-hold — the route gate and the input bounds (0082).
//
//   deno test -A supabase/functions/_test/
//
// `route_id` was the last client-supplied FK this function inserted raw, while dog_id,
// address_id and runner_id were all checked. Under service role that is the whole difference
// between a gate and a suggestion. Three things are pinned here:
//   ① a SUSPENDED route is refused — this is what makes 0082's one-line 2am suspension real
//      rather than advisory. Without it the operator suspends a flooded course and bookings
//      keep landing on it.
//   ② a CANDIDATE route is bookable only with the explicit acknowledgement (plan D-VIS=A), so
//      no owner is ever auto-assigned a loop that no dog has run.
//   ③ the exposure class written to the booking comes from routes.status, NOT from the body —
//      the PR-0 kill line divides by that number, so a client must not be able to author it.
// Plus the input bounds the review found on the way past: km fed straight into money and into
// the slot window with only a truthy check, and an unparseable date reached toISOString().
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { createBookingHold } from "../create-booking-hold/handler.ts";
import { FakeDb, req } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const DOG = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const RT_ACTIVE = "aaaaaaaa-0000-0000-0000-000000000001";
const RT_CANDIDATE = "aaaaaaaa-0000-0000-0000-000000000002";
const RT_SUSPENDED = "aaaaaaaa-0000-0000-0000-000000000003";
const RT_RETIRED = "aaaaaaaa-0000-0000-0000-000000000004";
const SOON = new Date(Date.now() + 48 * 3600_000).toISOString();

function scene() {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.seed("dogs", [{ id: DOG, owner_id: OWNER }]);
  db.seed("addresses", []);
  db.seed("bookings", []);
  db.seed("slot_holds", []);
  db.seed("runners", []);
  db.seed("billing_keys", []);          // card-less: today's pilot owner
  db.seed("routes", [
    { id: RT_ACTIVE, status: "active" },
    { id: RT_CANDIDATE, status: "candidate" },
    { id: RT_SUSPENDED, status: "suspended" },
    { id: RT_RETIRED, status: "retired" },
  ]);
  db.rpcs["owner_has_unsettled_charge"] = () => ({ data: false });
  return db;
}

const body = (over: Record<string, unknown> = {}) => ({
  dog_id: DOG, scheduled_at: SOON, km: 2, addons: [], ...over,
});

async function boom(db: FakeDb, over: Record<string, unknown> = {}) {
  try {
    await createBookingHold(req(body(over), "owner_jwt"), db as never);
    return null;
  } catch (e) {
    return e as HttpError;
  }
}

Deno.test("route gate — a suspended route is refused, and so is a retired one", async () => {
  for (const [id, label] of [[RT_SUSPENDED, "suspended"], [RT_RETIRED, "retired"]] as const) {
    const db = scene();
    const err = await boom(db, { route_id: id });
    assertEquals(err?.status, 409, `${label} should be refused`);
    assertStringIncludes(err!.message, "점검을 위해 잠시 중단");
    // and nothing was written — the refusal precedes every insert
    assertEquals(db.rows("bookings").length, 0);
    assertEquals(db.rows("slot_holds").length, 0);
  }
});

Deno.test("route gate — a candidate needs the explicit acknowledgement", async () => {
  const db = scene();
  const err = await boom(db, { route_id: RT_CANDIDATE });
  assertEquals(err?.status, 409);
  assertStringIncludes(err!.message, "candidate_ack_required");
  assertEquals(db.rows("bookings").length, 0);
});

Deno.test("route gate — a candidate WITH the acknowledgement books, and is stamped as one", async () => {
  const db = scene();
  const out = await createBookingHold(
    req(body({ route_id: RT_CANDIDATE, candidate_ack: true, selection_origin: "carousel" }), "owner_jwt"),
    db as never,
  );
  assertEquals(typeof out.booking_id, "string");
  const bk = db.rows("bookings")[0];
  // the exposure class is the server's reading of routes.status, not anything the body said
  assertEquals(bk.route_status_at_booking, "candidate");
  assertEquals(bk.selection_origin, "carousel");
});

Deno.test("route gate — the exposure class is NOT client-authored", async () => {
  const db = scene();
  await createBookingHold(
    req(body({
      route_id: RT_ACTIVE,
      // a client claiming to be a candidate booking (or anything else) must not move the number
      // the PR-0 denominator is built from
      route_status_at_booking: "candidate",
      selection_origin: "detail_cta",
      recommended_route_id: RT_CANDIDATE,
    }), "owner_jwt"),
    db as never,
  );
  const bk = db.rows("bookings")[0];
  assertEquals(bk.route_status_at_booking, "active");
  // recommended_route_id IS the client's to report — override is derived from the pair later
  assertEquals(bk.recommended_route_id, RT_CANDIDATE);
  assertEquals(bk.route_id, RT_ACTIVE);
});

Deno.test("route gate — an unknown route is a 400, not a raw Postgres 500", async () => {
  const db = scene();
  const err = await boom(db, { route_id: "aaaaaaaa-0000-0000-0000-00000000dead" });
  assertEquals(err?.status, 400);
  assertStringIncludes(err!.message, "unknown route");
});

Deno.test("route gate — an unknown selection_origin is refused", async () => {
  const db = scene();
  const err = await boom(db, { route_id: RT_ACTIVE, selection_origin: "hand_typed" });
  assertEquals(err?.status, 400);
  assertStringIncludes(err!.message, "unknown selection_origin");
});

Deno.test("input bounds — km outside the dial, non-numeric, or off-step is refused", async () => {
  for (const bad of [-2, 0.3, 11, 2.25, "5", NaN, Infinity]) {
    const db = scene();
    const err = await boom(db, { km: bad });
    assertEquals(err?.status, 400, `km=${String(bad)} should be refused`);
    assertEquals(db.rows("bookings").length, 0, `km=${String(bad)} must write nothing`);
  }
});

Deno.test("input bounds — an unparseable scheduled_at is a 400, not a RangeError", async () => {
  const db = scene();
  const err = await boom(db, { scheduled_at: "next tuesday" });
  assertEquals(err?.status, 400);
  assertStringIncludes(err!.message, "bad scheduled_at");
});

Deno.test("route gate — a booking with no route at all still works (route_id is optional)", async () => {
  const db = scene();
  const out = await createBookingHold(req(body(), "owner_jwt"), db as never);
  assertEquals(typeof out.booking_id, "string");
  assertEquals(db.rows("bookings")[0].route_status_at_booking, null);
});
