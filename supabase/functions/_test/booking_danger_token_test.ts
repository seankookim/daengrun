// [0119] The custody-gate refusal must SURVIVE THE TRIP to the client as a 409 carrying the token
// verbatim — the dog screen renders 미신고 as 「답해 주세요」, which it cannot do from a generic 500.
// The trigger raises the token as message_text, so the handler's mapping is the only thing between
// a rendered state and a dead-end error dialog. The negative control matters as much as the
// positive: an unrelated insert failure must STAY a 500, or every real outage would start
// masquerading as a polite refusal.
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { createBookingHold } from "../create-booking-hold/handler.ts";
import { FakeDb, req } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const DOG = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const RT_ACTIVE = "aaaaaaaa-0000-0000-0000-000000000001";
const SOON = new Date(Date.now() + 48 * 3600_000).toISOString();

function scene() {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.seed("dogs", [{ id: DOG, owner_id: OWNER }]);
  db.seed("addresses", []);
  db.seed("bookings", []);
  db.seed("slot_holds", []);
  db.seed("runners", []);
  db.seed("billing_keys", []);
  db.seed("routes", [{ id: RT_ACTIVE, status: "active" }]);
  db.rpcs["owner_has_unsettled_charge"] = () => ({ data: false });
  return db;
}

const body = () => ({ dog_id: DOG, scheduled_at: SOON, km: 2, addons: [] });

async function boom(db: FakeDb) {
  try {
    await createBookingHold(req(body(), "owner_jwt"), db as never);
    return null;
  } catch (e) {
    return e as HttpError;
  }
}

const TOKENS = [
  "dog_dangerous_undeclared",
  "dog_dangerous_custody_refused",
  "dog_dangerous_breed_conflict",
];

Deno.test("[0119] a custody-gate refusal reaches the client as a 409 carrying the token verbatim", async () => {
  for (const token of TOKENS) {
    const db = scene();
    // the trigger's raise surfaces as the insert error's message — the token embedded the way
    // postgres formats a P0001 (message_text plus context noise around it)
    db.failures["bookings:insert"] = `new row refused: ${token} — 0119 §D`;
    const err = await boom(db);
    assertEquals(err?.status, 409, `${token} must be a refusal, not a failure`);
    assertEquals(err?.message, token, "the token travels verbatim — the client switches on it");
  }
});

Deno.test("[0119] an unrelated insert failure STAYS a 500 — outages must not masquerade as refusals", async () => {
  const db = scene();
  db.failures["bookings:insert"] = 'duplicate key value violates unique constraint "bookings_pkey"';
  const err = await boom(db);
  assertEquals(err?.status, 500);
  assertStringIncludes(err!.message, "duplicate key");
});
