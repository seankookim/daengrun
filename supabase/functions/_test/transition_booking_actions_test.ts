// [O-5 §C.2 / N9 · N2] `payment_ok` IS GONE, AND THE SERVER SAYS SO.
//
//   deno test -A supabase/functions/_test/
//
// ⚠ THIS FILE IS THE ONLY ASSERTION THE DELETION LEAVES BEHIND, and that is exactly why it exists.
// Measured before the removal: **nothing in this repo asserted `payment_ok`** — not one SQL suite,
// not one Deno test. (`146_booking_entry_suite.sql` D-15 was twice described as pinning it; it pins
// `request_runner`'s CAS, `146:797`. The only hit under `supabase/tests/` was prose in
// `harness.sh:184`.) So the removal deleted behaviour that no gate in the repo could see. Without
// this file the next reader has no way to tell "deliberately deleted" from "never existed", and a
// well-meaning revert would go green.
//
// Contract: `docs/contracts/pay-after-run-contract.md` §C.2, pins N9 and N2.
//
// ═══ Why this drives the real HTTP handler instead of importing an arm ════════════════════════
// `transition-booking/index.ts` has `Deno.serve` at module top level, which is the stated reason
// `cancel_owner.ts` and `start_run.ts` are separate importable files. The contract's §D explicitly
// refused to extract anything for this pin ("N9 and N2 are HTTP-level assertions... Do not create
// either module") — creating a `payment_ok.ts` in one move to delete it in the next was the cost of
// a two-move plan that was abandoned.
//
// So this file gets at the handler the honest way: it swaps `Deno.serve` for a recorder **before**
// the dynamic import, keeps the function `handle()` produced, and calls it with real `Request`
// objects. Both refusals under test happen ABOVE any database write — the party gate at `:19` and
// the `default:` arm at the bottom of the switch — so the only I/O that has to exist is the auth
// lookup and the booking read, and those are what `FetchMock` stands in for. Every OTHER fetch is
// deliberately unmocked, which makes "the deleted action writes nothing" a checkable claim rather
// than an assumption: a resurrected `payment_ok` would try to PATCH and blow up on an unmocked URL.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { FetchMock } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const BOOKING = "b0000000-0000-0000-0000-00000000000b";

Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "svc_test_do_not_use");

// ── capture the handler `Deno.serve` would have been given ────────────────────────────────────
type Handler = (req: Request) => Promise<Response>;
let handler: Handler;
{
  const original = Deno.serve;
  let captured: Handler | null = null;
  // deno-lint-ignore no-explicit-any
  (Deno as any).serve = (fn: Handler) => {
    captured = fn;
    return {
      finished: Promise.resolve(),
      shutdown: () => Promise.resolve(),
      ref() {},
      unref() {},
      addr: { transport: "tcp", hostname: "127.0.0.1", port: 0 },
    };
  };
  try {
    await import("../transition-booking/index.ts");
  } finally {
    // deno-lint-ignore no-explicit-any
    (Deno as any).serve = original;
  }
  assert(captured, "transition-booking/index.ts no longer registers a handler with Deno.serve");
  handler = captured!;
}

/**
 * Answer exactly two questions — "who is calling" and "what is this booking" — and nothing else.
 * The unmocked remainder is the point: any write attempt rejects loudly instead of passing.
 */
function wire(uid: string, booking: Record<string, unknown> = {}) {
  const fm = new FetchMock().install();
  fm.on((u) => u.includes("/auth/v1/user"), () => FetchMock.json({ id: uid, aud: "authenticated", role: "authenticated" }));
  fm.on(
    (u) => u.includes("/rest/v1/bookings"),
    () => FetchMock.json({ id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "matching", ...booking }),
  );
  return fm;
}

async function post(uid: string, body: Record<string, unknown>, booking?: Record<string, unknown>) {
  const fm = wire(uid, booking);
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify(body),
      }),
    );
    return { status: res.status, body: await res.json(), calls: fm.calls };
  } finally {
    fm.restore();
  }
}

/** Every call this handler made that was not a read. A deleted action must make none. */
const writes = (calls: { method: string }[]) =>
  calls.filter((c) => ["POST", "PATCH", "PUT", "DELETE"].includes(c.method.toUpperCase()));

// ═══ N9 — the owner's answer is 400, not 200 and not a 409 about expiry ════════════════════════
Deno.test("[O-5 N9] the booking's OWNER sending payment_ok gets 400 `unknown action payment_ok`", async () => {
  const r = await post(OWNER, { booking_id: BOOKING, action: "payment_ok" });
  assertEquals(r.status, 400);
  assertEquals(r.body.error, "unknown action payment_ok");
  // Not 200 (the step did not silently succeed), not 409 (it is not an expiry — there is no hold
  // to expire), not 403 (the owner IS a party; refusing them for the wrong reason would send the
  // next reader hunting a permissions bug). One refusal, one reason.
  assert(r.status !== 200, "payment_ok still succeeds — the pre-run payment step is back");
  assertEquals(writes(r.calls).length, 0, "a deleted action wrote to the database");
});

Deno.test("[O-5 N9] payment_ok is refused for a booking sitting in `payment_hold`, too", async () => {
  // The state the deleted arm existed to move. Nothing moves it from here any more — which is
  // fine, because after §C.1 nothing in the product produces this state (a lost card CAS whose
  // compensate() failed is the one residual, and `e_hold` owns that row).
  const r = await post(OWNER, { booking_id: BOOKING, action: "payment_ok" }, { status: "payment_hold" });
  assertEquals(r.status, 400);
  assertEquals(r.body.error, "unknown action payment_ok");
  assertEquals(writes(r.calls).length, 0);
});

Deno.test("[O-5 N9] `payment_ok` is not special-cased — it is refused exactly like any nonsense", async () => {
  // If a future edit re-adds the string anywhere (a shim, a 410, a friendly redirect) these two
  // answers stop being identical. Identical IS the assertion: the action does not exist.
  const gone = await post(OWNER, { booking_id: BOOKING, action: "payment_ok" });
  const nonsense = await post(OWNER, { booking_id: BOOKING, action: "not_a_real_action" });
  assertEquals(gone.status, nonsense.status);
  assertEquals(gone.body.error, "unknown action payment_ok");
  assertEquals(nonsense.body.error, "unknown action not_a_real_action");
});

// ═══ N2 — deleting the arm did not widen the door ══════════════════════════════════════════════
Deno.test("[O-5 N2] a STRANGER sending payment_ok gets 403 `not a party` — not the 400", async () => {
  // The deleted arm carried its own `if (!isOwner) throw 403 "owner only"` gate, so the pin has to
  // show what is LEFT: the party gate at `index.ts:19` runs BEFORE the switch, so a stranger never
  // reaches the default arm at all. Two different refusals for two different reasons, and the
  // difference is not cosmetic — 400 tells a caller the action is gone, 403 tells them nothing
  // about this booking. Collapsing them either way leaks or misleads.
  const r = await post(STRANGER, { booking_id: BOOKING, action: "payment_ok" });
  assertEquals(r.status, 403);
  assertEquals(r.body.error, "not a party");
  assertEquals(writes(r.calls).length, 0);
});

Deno.test("[O-5 N2] the party gate still precedes the switch for an unknown action generally", async () => {
  const r = await post(STRANGER, { booking_id: BOOKING, action: "not_a_real_action" });
  assertEquals(r.status, 403);
  assertEquals(r.body.error, "not a party");
});

// ═══ the control — proof this harness actually reaches the switch ══════════════════════════════
Deno.test("[O-5] control: a REAL action still lands in its own arm, so 400 means 'gone', not 'broken'", async () => {
  // Without this, every assertion above would also pass against a handler that fell over before the
  // switch for some unrelated reason. `request_reschedule` is owner-gated and state-gated and its
  // refusal sentence is distinctive, so reaching it proves the party gate passed, the booking was
  // read, and the switch was entered.
  const r = await post(OWNER, { booking_id: BOOKING, action: "request_reschedule", meta: {} });
  assertEquals(r.status, 409);
  assertEquals(r.body.error, "확정된 예약만 변경 요청이 가능해요");
});

Deno.test("[O-5] control: the action list in the file header no longer advertises payment_ok", async () => {
  // The header is what a reader greps before they read the switch, and a header that still lists a
  // deleted action is the artifact this repo keeps getting bitten by (contract §E.6a).
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  const actionsLine = src.split("\n").find((l) => l.startsWith("// actions:"));
  assert(actionsLine, "transition-booking/index.ts lost its `// actions:` header line");
  assert(
    !actionsLine!.includes("payment_ok"),
    `the header still advertises a deleted action: ${actionsLine}`,
  );
  // And no `case "payment_ok"` survives anywhere in the switch, under any spelling of the quotes.
  // ⚠ Comments are stripped first, and that is not a convenience: the deletion deliberately leaves
  // a gravestone comment ("`case \"payment_ok\"` stood HERE") so the next reader knows the arm was
  // removed on purpose. A naive grep matches its own documentation and fails green-by-mistake.
  const code = src.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  assert(
    !/case\s+["']payment_ok["']/.test(code),
    "a `case \"payment_ok\"` arm is back in transition-booking",
  );
});
