// settle-run refuses a run that is STOPPING — 0168's two-phase stop, edge half.
//
//   deno test -A supabase/functions/_test/
//
// The defect this owns: 0168 splits the host's 러닝 종료 into two phases, and between them the
// booking carries `run_stopping_at` with `run_ended_at` still NULL. `handler.ts:90` keys the whole
// frozen path on `run_ended_at`, so **without a gate that window settles at the CLIENT's numbers**
// — the stale-trace defect moved one step later rather than fixed. It is live money and it is not
// behind a flag: the runner's `ledger_items` row is written with `payments_live_since` NULL
// (`0083:754`).
//
// ⚠ THE CONTROL IS NOT OPTIONAL AND IT IS THE SECOND TEST HERE. A handler that refused EVERY
//   settle would pass the refusal test perfectly and strand every runner in the product. So the
//   same fixture is re-run with `run_stopping_at` absent, and with it present alongside a stamped
//   `run_ended_at` (the ordinary post-sweep state) — both must settle normally. Name the failure
//   each arm is blind to and the lists differ, which is what makes them measurements rather than
//   one assertion written three times.
//
// ⚠ The refusal is asserted on the STATUS and the SENTENCE, plus the server log token. There is no
//   machine-readable error code on this wire (the file's other refusals are the same shape), so
//   the Korean copy IS the contract with the client — §5 of the contract names it, and
//   `club/run/[sid].tsx` renders exactly this state.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { settleRun } from "../settle-run/handler.ts";
import { FakeDb, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const STOPPING_AT = "2026-09-15T03:00:00.000Z";
const ENDED_AT = "2026-09-15T03:00:00.000Z";

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");

function scene(over: Row = {}) {
  const db = new FakeDb();
  db.users["runner_jwt"] = RUNNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "active",
    km: 2, min_fare: 9900, addons: [], base_fare: 7900, distance_fare: 6000, addon_fare: 0,
    total_price: 13900, run_stopping_at: null, run_ended_at: null, ...over,
  }]);
  db.seed("runners", [{ profile_id: RUNNER, commission_rate: 0.33 }]);
  db.seed("profiles", [{ id: OWNER, toss_customer_key: "cust_owner_1" }]);
  db.seed("billing_keys", []);
  db.seed("payments", []);
  db.seed("notifications", []);
  db.seed("runs", [{
    booking_id: BOOKING, actual_km: 2, end_reason: "completed", duration_sec: 1200,
    condition_note: null,
  }]);
  db.rpcs["settle_run_tx"] = () => ({ data: { total_runs: 5, drop: null } });
  db.rpcs["compute_runner_payout"] = () => ({
    data: [{ base: 9900, distance: 6000, addon: 0, guarantee: 0, gross: 15900, fee: 5247 }],
  });
  // charging is not live (production state, verified NULL 2026-08-28) — the mint returns no rows
  db.rpcs["mint_settle_charge_intent"] = () => ({ data: [] });
  return db;
}

const body = (over: Record<string, unknown> = {}) => ({
  booking_id: BOOKING, end_reason: "completed", actual_km: 2, duration_sec: 1200, ...over,
});

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

// ═══ THE REFUSAL ═══════════════════════════════════════════════════════════════════════════
Deno.test("0168: a booking in `stopping` is refused with 409 and NOTHING is written", async () => {
  const db = scene({ run_stopping_at: STOPPING_AT, run_ended_at: null });
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => settleRun(req(body(), "runner_jwt"), db as never));
    assertEquals(e.status, 409);
    // §5 of the contract, verbatim. The sentence IS the wire contract on this endpoint.
    assertEquals(e.message, "기록을 확정하고 있어요 — 잠시 뒤 정산할 수 있어요");
    // 🔴 and the refusal happened BEFORE anything was computed or written. A 409 that still ran
    // `settle_run_tx` would be a refusal in the response and a settlement in the database.
    assert(
      !db.log.includes("rpc:settle_run_tx"),
      `the tx ran under a refusal: ${db.log.join(" ")}`,
    );
    assert(
      !db.log.includes("rpc:compute_runner_payout"),
      `a price was computed for a run with no numbers: ${db.log.join(" ")}`,
    );
    assert(
      !db.log.includes("rpc:mint_settle_charge_intent"),
      `the owner was charged for a run that has not ended: ${db.log.join(" ")}`,
    );
    assertEquals(db.rows("payments").length, 0);
    // the greppable server-side token — the Korean sentence is for the runner, this is for us
    assert(
      cap.lines.some((l) => l.includes("[settle-run] refused run_stopping booking=")),
      `no refusal log line: ${cap.lines.join(" | ")}`,
    );
  } finally {
    cap.restore();
  }
});

// ═══ CONTROL ① — the ordinary un-stopped run still settles ════════════════════════════════
// Blind to: over-refusal. The test above cannot see a handler that refuses everything; this can.
Deno.test("0168 CONTROL: a run with no stopping stamp settles exactly as before", async () => {
  const db = scene();
  const out = await settleRun(req(body(), "runner_jwt"), db as never) as Row;
  assertEquals(Object.keys(out).sort(), ["drop", "net", "total_runs"]);
  assertEquals(out.net, 15900 - 5247);
  assert(db.log.includes("rpc:settle_run_tx"), `the tx did not run: ${db.log.join(" ")}`);
});

// ═══ CONTROL ② — the POST-SWEEP state settles, and on the SERVER's numbers ════════════════
// This is the state every real run passes through after phase 2, and it is the one a naive gate
// (`if (bk.run_stopping_at) refuse`) would break permanently: `run_stopping_at` is NOT cleared by
// the freeze, so a gate that ignored `run_ended_at` would refuse every settle for ever, silently,
// for every club run — a defect that arms on the first sweep and looks like the fix working.
Deno.test("0168 CONTROL: a stopping stamp that has been FROZEN settles, on the frozen numbers", async () => {
  const db = scene({ run_stopping_at: STOPPING_AT, run_ended_at: ENDED_AT });
  const seen: Row[] = [];
  db.rpcs["settle_run_tx"] = (args: Row) => {
    seen.push(args);
    return { data: { total_runs: 5, drop: null } };
  };
  // the body carries a DIFFERENT km from the frozen row, exactly as a stale client would
  const out = await settleRun(req(body({ actual_km: 9.99 }), "runner_jwt"), db as never) as Row;
  assertEquals(Object.keys(out).sort(), ["drop", "net", "total_runs"]);
  // the frozen path read the row and ignored the body — 0083 §6-ⓔ, untouched by 0168
  assertEquals(seen.length, 1);
  assertEquals(seen[0].p_actual_km, 2);
});

// ═══ THE PARTY GATE STILL COMES FIRST ═════════════════════════════════════════════════════
// A stranger must learn NOTHING about this booking's stop state. The refusal above sits after the
// 403 on purpose (the file's own comment at :101 makes the same argument about the reason lists),
// and this is the arm that proves the order rather than asserting it in a comment.
Deno.test("0168: a stranger gets 403 on a stopping booking, never the 409", async () => {
  const db = scene({ run_stopping_at: STOPPING_AT, run_ended_at: null });
  const cap = captureLogs();
  try {
    const e = await expectHttpError(() => settleRun(req(body(), "stranger_jwt"), db as never));
    assertEquals(e.status, 403);
    assertStringIncludes(e.message, "assigned runner only");
    assert(
      !cap.lines.some((l) => l.includes("refused run_stopping")),
      "the stop state leaked to a non-party through the log path",
    );
  } finally {
    cap.restore();
  }
});
