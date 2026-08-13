// transition-booking `start_run` — the run opens through ONE server transaction (0087 §2).
//
//   deno test -A supabase/functions/_test/
//
// The invariant every test here defends: **THE SERVER CHOOSES THE CLOCK, AND A FAILED START IS
// NEVER A SILENT ONE.** The shape this replaced was:
//     await set({ status: "active" });
//     await db.from("runs").insert({ booking_id, started_at: new Date().toISOString() });
// — two commits, a client-supplied timestamp, and an insert whose error was never bound to a
// variable. That last part is the TypeScript half of 0087 §0 ①: an assigned runner planted a
// `runs` row through the RLS insert policy, this insert failed on the unique `booking_id`,
// nobody noticed, and the run went live carrying `started_at = '2000-01-01'` — permanently
// `< return_seal_since`, so it settled with no return seal.
//
// So the pins are: no `runs` table write from Deno at all, no timestamp on the wire, and an RPC
// error that reaches the caller as a 409 instead of being discarded. The SQL half (the policy
// drop, the atomic claim, the BEFORE INSERT guard) is pinned by `123_run_insert_seal_suite.sql`;
// nothing here re-asserts it, exactly as settle_charge_test.ts leaves the money to SQL.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { startRun } from "../transition-booking/start_run.ts";
import { FakeDb, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const STRANGER = "55555555-5555-5555-5555-555555555555";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

function scene(over: { rpc?: (args: Row) => { data?: unknown; error?: { message: string } } } = {}) {
  const db = new FakeDb();
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "picked_up", km: 5,
  }]);
  db.seed("runs", []);
  db.seed("notifications", []);
  db.rpcs["start_run_tx"] = over.rpc ??
    (() => ({ data: { unchanged: false, started_at: "2026-08-13T01:00:00.000Z" } }));
  return db;
}

const notifier = (db: FakeDb) => (profile_id: string, title: string, body: string) =>
  db.from("notifications").insert({ profile_id, kind: "booking", title, body, ref_id: BOOKING });

const bk = (db: FakeDb) => db.rows("bookings")[0];

Deno.test("start_run: the start goes through start_run_tx — Deno writes no runs row and sends no clock", async () => {
  const db = scene();
  await startRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) });

  // The RPC is the only mutation of booking state. The retired two-step is visible in the log as
  // `update:bookings` + `insert:runs`; neither may appear.
  assert(db.log.includes("rpc:start_run_tx"), `expected the RPC, got ${JSON.stringify(db.log)}`);
  assertEquals(db.log.filter((l) => l.startsWith("insert:runs")).length, 0, "Deno must not insert into runs");
  assertEquals(db.log.filter((l) => l.startsWith("update:bookings")).length, 0, "Deno must not set status directly");
  assertEquals(db.rows("runs").length, 0);

  // And the booking is untouched from this side — the definer moved it, not us.
  assertEquals(bk(db).status, "picked_up");
});

Deno.test("start_run: no timestamp crosses the wire — the RPC takes the booking id and nothing else", async () => {
  const db = scene();
  let seen: Row | null = null;
  db.rpcs["start_run_tx"] = (args: Row) => {
    seen = args;
    return { data: { unchanged: false, started_at: "2026-08-13T01:00:00.000Z" } };
  };
  await startRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) });

  assertEquals(Object.keys(seen!).sort(), ["p_booking"]);
  assertEquals(seen!.p_booking, BOOKING);
  // Stated as a key-set assertion rather than "no started_at": a start time the client picked is
  // not a start time, and the only way to keep that true is for there to be no parameter for it.
  assert(!JSON.stringify(seen).includes("started_at"), "a client clock must not be sendable");
});

Deno.test("start_run: a refused start is a 409 carrying the server's reason — never swallowed", async () => {
  // THE REGRESSION THIS FILE EXISTS FOR. The old code discarded the insert's error entirely; the
  // run then appeared to start while the row it needed did not exist (or, worse, a planted one
  // survived). Each refusal below is a real state start_run_tx raises.
  for (const reason of ["not_picked_up", "not_run_runner", "not_found"]) {
    const db = scene({ rpc: () => ({ error: { message: reason } }) });
    const e = await assertRejects(
      () => startRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) }),
      HttpError,
    );
    assertEquals(e.status, 409);
    assertStringIncludes(e.message, reason);
    // and nothing after the failure ran — no "러닝 시작" for a run that did not start
    assertEquals(db.rows("notifications").length, 0, `notified on a failed start (${reason})`);
  }
});

Deno.test("start_run: the party gate refuses a non-runner before it reaches the RPC", async () => {
  const db = scene();
  const e = await assertRejects(
    () => startRun(db as never, { bookingId: BOOKING, uid: STRANGER, bk: bk(db), notify: notifier(db) }),
    HttpError,
  );
  assertEquals(e.status, 403);
  assertEquals(db.log.filter((l) => l === "rpc:start_run_tx").length, 0, "party gate must precede the state gate");
});

Deno.test("start_run: the owner's notification is byte-identical to the retired two-step's", async () => {
  // 0087 §0c: behaviour preserved EXACTLY, including on an idempotent re-start. The copy is
  // asserted literally because a notification title is a routing key (push.ts's registry), not
  // decoration — changing it silently re-routes the owner's tap.
  for (const unchanged of [false, true]) {
    const db = scene({ rpc: () => ({ data: { unchanged, started_at: "2026-08-13T01:00:00.000Z" } }) });
    await startRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) });
    const n = db.rows("notifications");
    assertEquals(n.length, 1, `re-start (unchanged=${unchanged}) must still notify, as the two-step did`);
    assertEquals(n[0].profile_id, OWNER);
    assertEquals(n[0].title, "러닝 시작");
    assertEquals(n[0].body, "5km 러닝이 시작됐어요 — 실시간으로 지켜보세요");
    assertEquals(n[0].kind, "booking");
    assertEquals(n[0].ref_id, BOOKING);
  }
});
