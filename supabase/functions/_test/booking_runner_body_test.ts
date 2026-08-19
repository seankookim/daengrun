// create-booking-hold — the request body may not nominate a runner (0111 §C.4, pins D-18/D-19).
//
//   deno test -A supabase/functions/_test/
//
// Why this file exists at all: `0111_booking_entry_rebuild.sql` closes the SQL half of the
// booking-party forgery (client INSERT on `bookings`, the client-writable `recurring_series`
// mirror the definer cron copies in). It cannot close THIS half, because this half is a branch in
// a TypeScript handler running as `service_role` — the SQL harness has no way to see it, which is
// exactly how the contract's first draft shipped C.4 unpinned.
//
// The hole it pins: `handler.ts` took `runner_id` from the REQUEST BODY, validated only that the
// row existed in `runners` (which the FK already enforced), and wrote it into both the booking and
// the `slot_holds` row. `runner_availability_rules` is readable by any logged-in user, so an
// attacker read a victim runner's published schedule, picked a passing slot, and landed
// `owner_id = attacker, runner_id = victim` at `matching` — a stronger position than the forged
// `draft` the SQL side gave, and `is_booking_party()` has no status filter, so it opened a chat
// thread to the victim, a review naming them, and an attacker-authored push on their phone.
//
// Two assertions, and the second is the non-negotiable one:
//   ① the request is REFUSED with 400 `runner_id_not_accepted_here`. Stripping the field and
//      carrying on would return a 200 with a booking id to a caller who believes the nomination
//      happened — a silent divergence between what was asked and what was done, which is the
//      shape this repo's honesty law is about. A 400 also gives the pin a positively-identifying
//      assertion rather than an absence.
//   ② NOTHING IS WRITTEN, and where rows are written by a legitimate call, `runner_id` is null in
//      BOTH the booking and the hold. These hold under any future answer to ①: if the 400 is ever
//      relaxed to a strip-and-continue, these are what still prove the field never reached the
//      insert.
//
// D-19 (the existing `booking_card_path_test.ts` and `booking_route_gate_test.ts` still pass,
// unmodified) is not re-implemented here — it IS those files, run by the same command. A green
// D-18 with a red D-19 would be a guard that broke the feature.
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { createBookingHold } from "../create-booking-hold/handler.ts";
import { FakeDb, req } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const DOG = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const ADDR = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
/** A REAL runner — the point is that existing-and-valid is not enough, so the fixture seeds one. */
const VICTIM = "99999999-9999-9999-9999-999999999999";
const SOON = new Date(Date.now() + 48 * 3600_000).toISOString();

function scene() {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.seed("dogs", [{ id: DOG, owner_id: OWNER }]);
  db.seed("addresses", [{ id: ADDR, owner_id: OWNER }]);
  db.seed("bookings", []);
  db.seed("slot_holds", []);
  db.seed("runners", [{ profile_id: VICTIM }]);   // a real runner, with a readable schedule
  db.seed("billing_keys", []);                    // card-less: today's pilot owner (widget path)
  db.seed("routes", []);
  db.rpcs["owner_has_unsettled_charge"] = () => ({ data: false });
  // If the handler ever asks this again, the nomination branch is back.
  db.rpcs["is_slot_available"] = () => ({ data: true });
  return db;
}

const body = (over: Record<string, unknown> = {}) => ({
  dog_id: DOG, address_id: ADDR, scheduled_at: SOON, km: 2, addons: [], ...over,
});

async function boom(db: FakeDb, over: Record<string, unknown> = {}) {
  try {
    await createBookingHold(req(body(over), "owner_jwt"), db as never);
    return null;
  } catch (e) {
    return e as HttpError;
  }
}

Deno.test("D-18 — a body naming a victim runner is refused 400, and writes nothing", async () => {
  const db = scene();
  const err = await boom(db, { runner_id: VICTIM });
  assertEquals(err?.status, 400, "a body-supplied runner_id must be refused, not silently dropped");
  assertStringIncludes(err!.message, "runner_id_not_accepted_here");
  // the row-level half — the part that must hold even if the 400 is ever relaxed
  assertEquals(db.rows("bookings").length, 0, "no booking may be written for a refused request");
  assertEquals(db.rows("slot_holds").length, 0, "no hold may be written for a refused request");
});

Deno.test("D-18 — the refusal precedes every DB read, so it cannot pass through a later failure", async () => {
  const db = scene();
  await boom(db, { runner_id: VICTIM });
  // Nothing at all — not even the ownership lookups. `log` records every mutating op; the
  // ownership/route/lock reads go through `rpc:` entries and table reads. The strongest available
  // statement with this fake is that no RPC ran: the account lock (`owner_has_unsettled_charge`)
  // is the first RPC the handler makes, and the guard sits above it.
  assertEquals(db.log.filter((l) => l.startsWith("rpc:")).length, 0);
});

Deno.test("D-18 — self-nomination and a nonexistent runner are refused the same way", async () => {
  // The refusal is about the FIELD, not about who it names — an existence check is what the old
  // code did, and it was worthless because the FK already enforced it.
  for (const target of [OWNER, "00000000-0000-0000-0000-0000000000ff"]) {
    const db = scene();
    const err = await boom(db, { runner_id: target });
    assertEquals(err?.status, 400, `runner_id=${target} should be refused`);
    assertStringIncludes(err!.message, "runner_id_not_accepted_here");
    assertEquals(db.rows("bookings").length, 0);
  }
});

Deno.test("D-18 — an explicit runner_id: null is NOT refused (it asks for what the server does)", async () => {
  // Deliberate: `null` asks for no runner, which is exactly what happens, so there is no
  // divergence between what the caller asked for and what was done — the only thing the 400
  // exists to prevent. Refusing it would break a future caller for no gain.
  const db = scene();
  const out = await createBookingHold(req(body({ runner_id: null }), "owner_jwt"), db as never);
  assertEquals(typeof out.booking_id, "string");
  assertEquals(db.rows("bookings")[0].runner_id, null);
});

Deno.test("D-18 — a legitimate booking writes runner_id null into BOTH the booking and the hold", async () => {
  const db = scene();
  const out = await createBookingHold(req(body(), "owner_jwt"), db as never);
  assertEquals(typeof out.booking_id, "string");
  assertEquals(out.paid_path, "widget");

  const bk = db.rows("bookings")[0];
  assertEquals(bk.runner_id, null, "the booking must not name a runner");
  assertEquals(bk.status, "payment_hold");
  // and the fares are still the server's, which is the half C.4 never needed to change
  assertEquals(bk.total_price, bk.base_fare + bk.distance_fare + bk.addon_fare);

  const hold = db.rows("slot_holds")[0];
  assertEquals(hold.runner_id, null, "the hold must not name a runner — it now blocks nobody");
  assertEquals(hold.booking_id, bk.id);
});

Deno.test("D-18 — the nomination branch is gone: is_slot_available is never called from here", async () => {
  // The old code called `is_slot_available(runner_id, …)` for a body-nominated runner. Nomination
  // now happens in `transition-booking request_runner`, which runs its own clash gate at the
  // moment it actually assigns. If this RPC reappears in this handler's log, the branch is back.
  const db = scene();
  await createBookingHold(req(body(), "owner_jwt"), db as never);
  assertEquals(db.log.filter((l) => l === "rpc:is_slot_available").length, 0);
});
