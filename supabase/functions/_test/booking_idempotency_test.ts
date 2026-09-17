// create-booking-hold — the idempotency key's EDGE half (0179; backend audit 2026-09-17 §(a) #3).
//
//   deno test -A supabase/functions/_test/
//
// What this file pins is the wiring: the key is parsed and passed through under the migration's
// argument name, absent is allowed (installed builds), garbage is refused before any call, the
// owner comes from the JWT and never from the body, the transaction's refusal tokens become the
// sentences the client keys on, and a replay is reported as `unchanged: true` with the same id.
// What it does NOT pin is the transaction itself — the same-key race, the locks, the clash guard's
// atomicity, the rollback — which SQL suite 210 (0179-K1…K8) owns against a real database; the
// fake in `hold_tx_fake.ts` replays only the contract.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { createBookingHold } from "../create-booking-hold/handler.ts";
import { FakeDb, req, type Row } from "./fakedb.ts";
import { installHoldTx } from "./hold_tx_fake.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const DOG = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const KEY = "8f0c5a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b";
const KEY2 = "9a1d6b4f-2d3e-4f60-9b0c-1d2e3f4a5b6c";
const SOON = new Date(Date.now() + 48 * 3600_000).toISOString();
const LATER = new Date(Date.now() + 72 * 3600_000).toISOString();

function scene() {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.seed("dogs", [{ id: DOG, owner_id: OWNER }]);
  db.seed("addresses", []);
  db.seed("bookings", []);
  db.seed("slot_holds", []);
  db.seed("runners", []);
  db.seed("billing_keys", []);
  db.seed("routes", []);
  db.rpcs["owner_has_unsettled_charge"] = () => ({ data: false });
  const sent = installHoldTx(db);
  return { db, sent };
}
const body = (over: Record<string, unknown> = {}) => ({ dog_id: DOG, scheduled_at: SOON, km: 2, addons: [], ...over });

async function expectHttpError(fn: () => Promise<unknown>): Promise<HttpError> {
  try { await fn(); } catch (e) { assert(e instanceof HttpError, `expected HttpError, got ${e}`); return e; }
  throw new Error("expected a throw, got a resolved value");
}

Deno.test("🔴 [0179] a replayed key returns the SAME booking id with unchanged:true and creates nothing new", async () => {
  const { db, sent } = scene();
  const first = await createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never) as Row;
  const again = await createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never) as Row;
  assertEquals(again.booking_id, first.booking_id);
  assertEquals(again.unchanged, true);
  assertEquals(first.unchanged, undefined, "a fresh hold must not carry the field at all");
  assertEquals(Object.keys(first).sort(), ["booking_id", "booking_status", "hold_expires_at", "paid_path", "total_price"]);
  assertEquals(db.rows("bookings").length, 1);
  assertEquals(db.rows("slot_holds").length, 1);
  assertEquals(sent.length, 2);
  assertEquals(sent[0].p_client_request_id, KEY);
  assertEquals(sent[1].p_client_request_id, KEY);
});

Deno.test("🔴 [0179] the same key with a different payload is 409 request_mismatch, and nothing new is written", async () => {
  const { db } = scene();
  await createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never);
  const e = await expectHttpError(() =>
    createBookingHold(req(body({ client_request_id: KEY, km: 2.5 }), "owner_jwt"), db as never)
  );
  assertEquals(e.status, 409);
  assertStringIncludes(e.message, "request_mismatch");
  assertEquals(db.rows("bookings").length, 1);
});

Deno.test("[0179] two different keys make two bookings (non-overlapping); no key is still allowed and passes NULL", async () => {
  const { db, sent } = scene();
  const a = await createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never) as Row;
  const b = await createBookingHold(req(body({ client_request_id: KEY2, scheduled_at: LATER }), "owner_jwt"), db as never) as Row;
  assert(a.booking_id !== b.booking_id);
  assertEquals(db.rows("bookings").length, 2);
  // absent key: the installed-build contract — the call goes out with p_client_request_id null
  const later2 = new Date(Date.now() + 96 * 3600_000).toISOString();
  const c = await createBookingHold(req(body({ scheduled_at: later2 }), "owner_jwt"), db as never) as Row;
  assertEquals(typeof c.booking_id, "string");
  assertEquals(sent[2].p_client_request_id, null);
  assertEquals(db.rows("bookings").length, 3);
});

Deno.test("🔴 [0179] a garbage key is 400 before any transaction call; a null key is accepted", async () => {
  for (const bad of ["not-a-uuid", 42, "", {}, "8f0c5a3e-1c2d-4e5f-8a9b"]) {
    const { db, sent } = scene();
    const e = await expectHttpError(() =>
      createBookingHold(req(body({ client_request_id: bad }), "owner_jwt"), db as never)
    );
    assertEquals(e.status, 400, `key ${JSON.stringify(bad)} must be a 400`);
    assertEquals(e.message, "bad client_request_id");
    assertEquals(sent, [], `key ${JSON.stringify(bad)} reached the transaction`);
    assertEquals(db.rows("bookings").length, 0);
  }
  const { db, sent } = scene();
  await createBookingHold(req(body({ client_request_id: null }), "owner_jwt"), db as never);
  assertEquals(sent[0].p_client_request_id, null);
});

Deno.test("🔴 [0179] the owner the transaction receives is the JWT's, never the body's; the arguments carry the migration's names", async () => {
  const { db, sent } = scene();
  await createBookingHold(req(body({ client_request_id: KEY, owner_id: "22222222-2222-2222-2222-222222222222", p_owner: "x" }), "owner_jwt"), db as never);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].p_owner, OWNER);
  // the migration's parameter names, exactly and only — sorted on BOTH sides so the pin is about
  // the set, not about anyone's idea of alphabetical order
  assertEquals(Object.keys(sent[0]).sort(), [
    "p_owner", "p_dog", "p_scheduled_at", "p_km", "p_addons", "p_base_fare", "p_distance_fare", "p_addon_fare",
    "p_total_price", "p_min_fare", "p_close_to_matching", "p_client_request_id", "p_route", "p_address",
    "p_pace_label", "p_recommended_route", "p_selection_origin", "p_route_status", "p_route_chips",
  ].sort());
  assertEquals(sent[0].p_close_to_matching, true);   // no card, charging off ⇒ close in this request (O-5 §C.1)
  assertEquals(sent[0].p_total_price, 13900);
});

Deno.test("[0179] each transaction refusal becomes the sentence the client keys on, and the edge writes nothing", async () => {
  const cases: [string, number, string][] = [
    ["forbidden", 403, "forbidden"],
    ["dog_slot_clash", 409, "같은 아이의 예약"],
    ["request_mismatch", 409, "request_mismatch"],
    ["hold_close_failed", 500, "남은 예약도 없어요"],
    ["not_signed_in", 401, "unauthorized"],
    ["km_out_of_range", 400, "km_out_of_range"],
    ["missing_fields", 400, "missing_fields"],
  ];
  for (const [token, status, text] of cases) {
    const { db } = scene();
    db.rpcs["create_booking_hold_tx"] = () => ({ error: { message: token } });
    const e = await expectHttpError(() => createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never));
    assertEquals(e.status, status, token);
    assertStringIncludes(e.message, text, token);
    assertEquals(e.code, undefined, `${token} is a contract token, not an internal error`);
    assertEquals(db.log.filter((l) => /^(insert|update|delete):/.test(l)), [], `${token}: the edge wrote something`);
  }
});

Deno.test("[0179] a replay reports the row's CURRENT status, not the status of the first answer", async () => {
  const { db } = scene();
  const first = await createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never) as Row;
  db.rows("bookings")[0].status = "confirmed";          // a runner accepted in between
  const again = await createBookingHold(req(body({ client_request_id: KEY }), "owner_jwt"), db as never) as Row;
  assertEquals(again.booking_id, first.booking_id);
  assertEquals(again.unchanged, true);
  assertEquals(again.booking_status, "confirmed");
});
