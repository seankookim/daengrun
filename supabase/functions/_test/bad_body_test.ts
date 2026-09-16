// M1 — a malformed request body is the CALLER's 400, never our 500. Pinned as a CLASS.
//
//   deno test -A supabase/functions/_test/
//
// ⚠ THE PIN IS TABLE-DRIVEN ON PURPOSE, AND THE SHAPE IS THE POINT. The 2026-09-17 backend audit
// found this in SIX of eleven functions at once (`M1`), which is what a class defect looks like: not
// one author forgetting once, but one idiom — `const x = await req.json()` — copied into every new
// handler because it reads as obviously correct. A per-handler pin in a per-handler suite would
// close the six that exist and say nothing about the seventh, so the assertion lives in one place
// that enumerates the handlers and can be extended by one line.
//
// What it costs to get wrong, since "a 500 instead of a 400" sounds cosmetic: `handle()`'s
// catch-all answers `500 internal`, which tells the caller OUR SERVER BROKE when in fact nothing
// did, and a 5xx is the one class of answer a client is entitled to retry. So a permanently
// malformed request became an infinitely retryable one, and every retry logged an unhandled
// exception that an operator had to rule out as a real fault.
//
// ⚠ `transition-booking` is the sixth function and is NOT here: its handler lives behind a
// module-top-level `Deno.serve`, and the capture rail that reaches it already exists in
// `transition_booking_actions_test.ts` (a second `await import` of the same module would get the
// cached one and capture nothing). Its arm is in that file, beside the rail it needs.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { FakeDb } from "./fakedb.ts";

import { confirmPayment } from "../confirm-payment/handler.ts";
import { createBookingHold } from "../create-booking-hold/handler.ts";
import { createPaymentIntent } from "../create-payment-intent/handler.ts";
import { openDrop } from "../open-drop/handler.ts";
import { settleRun } from "../settle-run/handler.ts";

const UID = "11111111-1111-1111-1111-111111111111";

/** `req()` stringifies, so it cannot express a body that is not json. This can. */
function rawReq(body: string): Request {
  return new Request("http://localhost/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": "Bearer jwt" },
    body,
  });
}

// The three shapes a real caller produces: an empty body (an `invoke` with no `body:` at all), a
// truncated one (a dropped connection mid-POST), and a non-json one (a proxy's error page).
//
// ⚠ `"null"` IS NOT IN THIS LIST, and working out why was worth more than the pin. It was — and it
// failed, because `null` is VALID JSON: it parses, so the `.catch` never fires, and the handler
// answers `400 missing drop_id` instead. That answer is the correct one and the pin was the thing
// that was wrong: `bad_body` claims "I could not read your body", which would be a lie about a body
// we read perfectly. It has its own arm at the foot of this file, because the `?? {}` that makes it
// a clean 400 rather than a TypeError-driven 500 is a real guard and deserves a real pin.
const MALFORMED = ["", "{", "not json at all"];

const HANDLERS: [string, (req: Request, db: FakeDb) => Promise<unknown>][] = [
  ["open-drop", (r, db) => openDrop(r, db as never)],
  ["create-booking-hold", (r, db) => createBookingHold(r, db as never)],
  ["create-payment-intent", (r, db) => createPaymentIntent(r, db as never)],
  ["confirm-payment", (r, db) => confirmPayment(r, db as never)],
  ["settle-run", (r, db) => settleRun(r, db as never)],
];

Deno.test("[M1] every guarded handler answers 400 bad_body to a malformed body — never 500", async () => {
  for (const [name, call] of HANDLERS) {
    for (const body of MALFORMED) {
      const db = new FakeDb();
      db.users["jwt"] = UID;
      let err: unknown = null;
      try {
        await call(rawReq(body), db);
      } catch (e) {
        err = e;
      }
      const where = `${name} on ${JSON.stringify(body)}`;
      assert(err instanceof HttpError, `${where}: expected HttpError, got ${err}`);
      assertEquals((err as HttpError).status, 400, `${where}: must be a 400`);
      assertEquals((err as HttpError).message, "bad_body", `${where}: must name the body`);

      // 🔴 AND IT REFUSES BEFORE IT WRITES. A 400 that arrives after a row has been inserted is a
      //    correct status attached to an incorrect world — `create-booking-hold` inserts a booking,
      //    `create-payment-intent` mints an order, `open-drop` spends a drop that 0106 §3 freezes.
      assertEquals(db.log.length, 0, `${where}: a refused body wrote ${JSON.stringify(db.log)}`);
    }
  }
});

Deno.test("[M1 control] a WELL-FORMED body is not refused as bad_body — the guard catches only the parse", async () => {
  // Without this arm, `throw new HttpError(400, "bad_body")` on the first line of every handler
  // satisfies the pin above and the whole product is dead with the suite green. Each handler is
  // given a body it can parse but not satisfy, so it must get PAST the parse and refuse for its own
  // reason — any status, any token, as long as it is not this one.
  const cases: [string, (db: FakeDb) => Promise<unknown>][] = [
    ["open-drop", (db) => openDrop(json({}), db as never)],
    ["create-booking-hold", (db) => createBookingHold(json({}), db as never)],
    ["create-payment-intent", (db) => createPaymentIntent(json({}), db as never)],
    ["confirm-payment", (db) => confirmPayment(json({}), db as never)],
    ["settle-run", (db) => settleRun(json({}), db as never)],
  ];
  for (const [name, call] of cases) {
    const db = new FakeDb();
    db.users["jwt"] = UID;
    let err: unknown = null;
    try {
      await call(db);
    } catch (e) {
      err = e;
    }
    assert(err instanceof HttpError, `${name}: expected HttpError, got ${err}`);
    assert(
      (err as HttpError).message !== "bad_body",
      `${name}: a parseable body was reported as unparseable`,
    );
  }
});

Deno.test("[M1] a body of literal `null` parses, so it is refused for its own reason — not bad_body", async () => {
  // 🔴 This is the arm that pins `?? {}`, and without it that operator looks like defensive noise a
  //    later reader would delete. `JSON.parse("null")` succeeds and returns `null`; destructuring
  //    `null` throws a TypeError, which `handle()` turns into `500 internal` — the EXACT defect M1
  //    is about, arriving through the one body shape the `.catch` cannot see. So the guard is two
  //    halves (`.catch` for unparseable, `?? {}` for parseable-but-empty) and each half owns a body
  //    shape the other is blind to.
  for (const [name, call] of HANDLERS) {
    const db = new FakeDb();
    db.users["jwt"] = UID;
    let err: unknown = null;
    try {
      await call(rawReq("null"), db);
    } catch (e) {
      err = e;
    }
    assert(err instanceof HttpError, `${name}: a null body must not escape as a raw TypeError: ${err}`);
    assertEquals((err as HttpError).status, 400, `${name}: a null body is the caller's mistake`);
    assert(
      (err as HttpError).message !== "bad_body",
      `${name}: \`null\` parses, so claiming we could not read it is a lie about our own read`,
    );
    assertEquals(db.log.length, 0, `${name}: a refused null body wrote ${JSON.stringify(db.log)}`);
  }
});

function json(body: unknown): Request {
  return new Request("http://localhost/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": "Bearer jwt" },
    body: JSON.stringify(body),
  });
}
