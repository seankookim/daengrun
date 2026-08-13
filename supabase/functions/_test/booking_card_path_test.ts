// create-booking-hold — the account lock and the card path (toss-plan §0-ter, findings #7/#15).
//
//   deno test -A supabase/functions/_test/
//
// Two things are pinned here and neither is about money moving (nothing is charged at booking
// time under post-pay):
//  ① the DEBT GATE runs after the ownership checks and before any write, for every owner;
//  ② a CARD-LINKED booking either reaches `matching` in this request or leaves NO ROWS BEHIND.
//     The second half is the whole point of §0-ter #7: e_hold's silent 30-minute death (0060,
//     pinned by 100 W7) is the WIDGET flow's designed ending, and a card owner has no widget to
//     come back to. A test that only checked the happy CAS would miss the failure that matters.
//
// The card-less path is asserted byte-for-byte against the pre-slice behaviour, because the pilot
// runs on it: every owner today has no billing key.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { createBookingHold } from "../create-booking-hold/handler.ts";
import { FakeDb, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const DOG = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const OTHER_DOG = "d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0";
const TOTAL = 13900; // 7,900 owner base + 3,000×2 (ctx.ts PRICING) — the price this fn computes

const SOON = new Date(Date.now() + 48 * 3600_000).toISOString();

function scene(over: { card?: boolean; locked?: boolean } = {}) {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("dogs", [{ id: DOG, owner_id: OWNER }, { id: OTHER_DOG, owner_id: STRANGER }]);
  db.seed("addresses", []);
  db.seed("bookings", []);
  db.seed("slot_holds", []);
  db.seed("runners", [{ profile_id: RUNNER }]);
  db.seed("billing_keys", over.card ? [{ profile_id: OWNER, billing_key: "bkey_1" }] : []);
  db.rpcs["owner_has_unsettled_charge"] = () => ({ data: over.locked ?? false });
  return db;
}

const body = (over: Record<string, unknown> = {}) => ({
  dog_id: DOG, scheduled_at: SOON, km: 2, addons: [], ...over,
});

const bookings = (db: FakeDb) => db.rows("bookings");
const holds = (db: FakeDb) => db.rows("slot_holds");
const updatesToBookings = (db: FakeDb) => db.log.filter((l) => l.startsWith("update:bookings"));

/**
 * Fire `mutate()` at the instant the handler asks to insert the slot hold — i.e. in the window
 * between the hold and the CAS. That is the real race (0060's expiry sweep, or a trigger changing
 * its mind), and it is the only way to make the CAS return 0 rows from the outside.
 */
function raceAfterHold(db: FakeDb, mutate: () => void) {
  const orig = db.from.bind(db);
  // deno-lint-ignore no-explicit-any
  (db as any).from = (table: string) => {
    const q = orig(table);
    if (table !== "slot_holds") return q;
    return {
      ...q,
      // deno-lint-ignore no-explicit-any
      insert: (payload: any) => {
        const built = q.insert(payload);
        mutate();
        return built;
      },
    };
  };
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

// ═══ the account lock ══════════════════════════════════════════════════════════════════════
Deno.test("debt gate — a locked owner is refused 409 and NOTHING is written (card or not)", async () => {
  for (const card of [false, true]) {
    const db = scene({ locked: true, card });
    const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
    assertEquals(e.status, 409);
    // The sentence has to name the fact and the way out — a bare "forbidden" would leave the
    // owner tapping 예약 forever.
    assertStringIncludes(e.message, "잠겨요");
    assertStringIncludes(e.message, "결제 관리");
    assert(db.log.includes("rpc:owner_has_unsettled_charge"), "the lock was never asked about");
    assertEquals(bookings(db).length, 0);
    assertEquals(holds(db).length, 0);
    assertEquals(db.log.filter((l) => l.startsWith("insert:")).length, 0);
  }
});

Deno.test("debt gate — false lets the booking through, and the gate precedes every write", async () => {
  const db = scene();
  const out = await createBookingHold(req(body(), "owner_jwt"), db as never) as Row;
  assertEquals(typeof out.booking_id, "string");
  const gate = db.log.indexOf("rpc:owner_has_unsettled_charge");
  const firstWrite = db.log.findIndex((l) => l.startsWith("insert:") || l.startsWith("update:"));
  assert(gate >= 0 && gate < firstWrite, `the lock was checked after a write: ${db.log.join(" ")}`);
});

Deno.test("ownership is validated BEFORE the lock — a stranger's dog learns nothing about debt", async () => {
  // Party gate before state gate (CLAUDE.md law). Reversed, a locked owner probing someone else's
  // dog_id would get the lock sentence and learn the dog exists.
  const db = scene({ locked: true });
  const e = await expectHttpError(() =>
    createBookingHold(req(body({ dog_id: OTHER_DOG }), "owner_jwt"), db as never)
  );
  assertEquals(e.status, 403);
  assert(!db.log.includes("rpc:owner_has_unsettled_charge"), "the lock ran before the ownership check");
});

Deno.test("the lock RPC failing refuses the booking (fail closed) — a money gate never fails open", async () => {
  const db = scene();
  db.rpcs["owner_has_unsettled_charge"] = () => ({ error: { message: "function does not exist" } });
  const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
  assertEquals(e.status, 500);
  assertEquals(bookings(db).length, 0);
});

// ═══ the card-less path — the pilot's path, unchanged ══════════════════════════════════════
Deno.test("no billing key → payment_hold exactly as before, paid_path 'widget', no CAS", async () => {
  const db = scene();
  const out = await createBookingHold(req(body(), "owner_jwt"), db as never) as Row;
  assertEquals(Object.keys(out).sort(), ["booking_id", "hold_expires_at", "paid_path", "total_price"]);
  assertEquals(out.paid_path, "widget");
  assertEquals(out.total_price, TOTAL);
  assertEquals(bookings(db).length, 1);
  assertEquals(bookings(db)[0].status, "payment_hold");
  assertEquals(bookings(db)[0].total_price, TOTAL);
  // draft → quoted → payment_hold and not one statement more: the instant CAS belongs to card
  // owners only, and adding it here would skip the widget the pilot still needs.
  assertEquals(updatesToBookings(db), ["update:bookings:1", "update:bookings:1"]);
  assertEquals(holds(db).length, 1);
  assertEquals(holds(db)[0].booking_id, bookings(db)[0].id);
  assertEquals(typeof out.hold_expires_at, "string");
});

Deno.test("the pre-slice gates still gate (clash, unknown addon, missing fields)", async () => {
  // Byte-path guard: the two new owner-level reads must not have moved anything below them.
  const db = scene();
  db.rows("bookings").push({
    id: "live-1", dog_id: DOG, owner_id: OWNER, status: "confirmed", scheduled_at: SOON, km: 2,
  });
  const clash = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
  assertEquals(clash.status, 409);
  assertStringIncludes(clash.message, "같은 아이의 예약");

  const db2 = scene();
  const addon = await expectHttpError(() =>
    createBookingHold(req(body({ addons: ["yacht"] }), "owner_jwt"), db2 as never)
  );
  assertEquals(addon.status, 400);
  assertEquals(bookings(db2).length, 0);

  const db3 = scene();
  const missing = await expectHttpError(() =>
    createBookingHold(req({ dog_id: DOG, addons: [] }, "owner_jwt"), db3 as never)
  );
  assertEquals(missing.status, 400);
  assert(!db3.log.includes("rpc:owner_has_unsettled_charge"));
});

// ═══ the card path ═════════════════════════════════════════════════════════════════════════
Deno.test("billing key → the same request CASes payment_hold → matching, after the hold", async () => {
  const db = scene({ card: true });
  const out = await createBookingHold(req(body(), "owner_jwt"), db as never) as Row;
  assertEquals(out.paid_path, "card");
  assertEquals(out.total_price, TOTAL); // the price is the same money; only the collection differs
  assertEquals(bookings(db).length, 1);
  assertEquals(bookings(db)[0].status, "matching");
  // Order is the contract (§0-ter #7): the slot is held FIRST, the CAS is last, so a failure has
  // something to compensate rather than a booking already announced to the matching pool.
  const hold = db.log.indexOf("insert:slot_holds");
  const cas = db.log.lastIndexOf("update:bookings:1");
  assert(hold >= 0 && cas > hold, `CAS did not follow the hold: ${db.log.join(" ")}`);
  assertEquals(updatesToBookings(db).length, 3); // quoted, payment_hold, matching
  assertEquals(holds(db).length, 1); // the hold stays — 0060 reaps it, matching is live
  // Nothing was charged and no payments row exists: booking is free under post-pay.
  assertEquals(db.rows("payments").length, 0);
});

Deno.test("card path, CAS finds 0 rows → compensating DELETE of the hold AND the booking (§0-ter #7)", async () => {
  const db = scene({ card: true });
  // The booking expires in the window between the hold insert and the CAS.
  raceAfterHold(db, () => {
    bookings(db)[0].status = "expired";
  });
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
    assertEquals(e.status, 500);
    // Honest: no charge happened (none ever does here) and no booking survives.
    assertStringIncludes(e.message, "예약을 만들지 못했어요");
    assertEquals(bookings(db).length, 0);
    assertEquals(holds(db).length, 0);
    // The hold goes first — it references the booking row.
    const dh = db.log.indexOf("delete:slot_holds:1");
    const dbk = db.log.indexOf("delete:bookings:1");
    assert(dh >= 0 && dbk > dh, `compensation order wrong: ${db.log.join(" ")}`);
    assert(
      cap.lines.some((l) => l.includes("card-path CAS failed") && l.includes("cas_zero_rows")),
      `the compensation was silent: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
  }
});

Deno.test("card path, the CAS statement itself erroring → same compensation, same honest error", async () => {
  const db = scene({ card: true });
  // A trigger refusal / connection error at the last statement, injected only for the CAS: the
  // three earlier booking updates have already run by the time the hold is inserted.
  raceAfterHold(db, () => db.fail("bookings:update", "enforce_booking_transition refused"));
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
    assertEquals(e.status, 500);
    assertEquals(bookings(db).length, 0);
    assertEquals(holds(db).length, 0);
    assert(
      cap.lines.some((l) => l.includes("enforce_booking_transition refused")),
      `the CAS error never reached the log: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
  }
});

Deno.test("card path never strands: a compensating delete that itself fails is LOUD, not silent", async () => {
  const db = scene({ card: true });
  raceAfterHold(db, () => {
    bookings(db)[0].status = "expired";
    db.fail("bookings:delete", "deadlock detected");
  });
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
    assertEquals(e.status, 500); // the caller still hears the truth about their request
    assertEquals(holds(db).length, 0); // the hold half did get released
    assert(
      cap.lines.some((l) => l.includes("booking cleanup failed") && l.includes("deadlock detected")),
      `a failed cleanup was swallowed: ${cap.lines.join("|")}`,
    );
    // ...and the SENTENCE tells the truth about what survived. The booking row is still there —
    // saying "남은 예약도 없어요" would be a lie the owner discovers on their own schedule screen.
    assertEquals(bookings(db).length, 1);
    assert(!e.message.includes("남은 예약도 없어요"), `the copy denied a booking that exists: ${e.message}`);
    assertStringIncludes(e.message, "청구된 금액은 없어요"); // still true, and still worth saying
    assertStringIncludes(e.message, "남을 수 있어요");
    assertStringIncludes(e.message, "자동 정리");
  } finally {
    cap.restore();
  }
});

Deno.test("...while a clean compensation keeps the flat 'nothing is left' sentence", async () => {
  const db = scene({ card: true });
  raceAfterHold(db, () => {
    bookings(db)[0].status = "expired";
  });
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
    assertEquals(bookings(db).length, 0);
    assertStringIncludes(e.message, "남은 예약도 없어요");
  } finally {
    cap.restore();
  }
});

Deno.test("a failed billing_keys read refuses BEFORE any write (nothing to compensate)", async () => {
  // Asking who is paying is the last thing done before the first insert on purpose: an unreadable
  // answer here must not become a booking that may or may not need a widget.
  const db = scene({ card: true });
  db.fail("billing_keys:select", "connection reset");
  const e = await expectHttpError(() => createBookingHold(req(body(), "owner_jwt"), db as never));
  assertEquals(e.status, 500);
  assertEquals(bookings(db).length, 0);
  assertEquals(holds(db).length, 0);
});
