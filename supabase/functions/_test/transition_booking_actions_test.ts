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

// [151 B6's other half / review finding 4] 0116 §D ⓑ gates runner_work_gate so a client may ask
// only about themselves — and pins it in SQL. What SQL cannot see is whether the ACCEPT PATH still
// consults the gate at all: delete the rpc("runner_work_gate", …) call from the accept arm and
// every SQL pin stays green while the ⑫ ruling ("don't let them take new runs until the dog is
// confirmed by both sides") silently stops being enforced. Same N8 precedent as 0115: a source pin
// where executing the arm would need infrastructure the fake deliberately lacks. It matches the
// CALL, not prose — a comment mentioning the gate does not satisfy it.
Deno.test("the ACCEPT ARM itself consults runner_work_gate (arm-scoped source pin, round 2 finding 8)", async () => {
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  // Scoped to the runner_accept arm — from its case label to the next case label — because the
  // reviewer showed a file-scoped match staying green with the accept gate deleted and the call
  // merely relocated. A call that exists elsewhere in the file must not satisfy this pin.
  const armStart = src.search(/case\s+["']runner_accept["']/);
  assert(armStart >= 0, "the runner_accept arm no longer exists by that name — re-scope this pin");
  const rest = src.slice(armStart);
  const nextCase = rest.slice(20).search(/case\s+["']/);
  const arm = nextCase >= 0 ? rest.slice(0, nextCase + 20) : rest;
  assert(/rpc\(\s*["']runner_work_gate["']/.test(arm),
    "the runner_accept arm no longer calls rpc('runner_work_gate') — the ⑫ gate is unenforced exactly where acceptance happens");
});

// ═══ [backend audit 2026-09-17 · M1] a malformed body is the CALLER's 400, never our 500 ════════
// This arm lives HERE rather than in `_test/bad-body.test.ts`, where the other five functions of
// the M1 class are pinned, for a mechanical reason: `transition-booking`'s handler is only reachable
// through the `Deno.serve` capture at the head of this file, and a second `await import` of the same
// module in another test file gets the CACHED module and captures nothing — a pin that would pass by
// never running. One rail, one file.
Deno.test("[M1] a malformed body is 400 bad_body — not the 500 the catch-all used to answer", async () => {
  for (const body of ["", "{", "not json at all"]) {
    const fm = wire(OWNER);
    try {
      const res = await handler(
        new Request("https://proj.functions.supabase.co/transition-booking", {
          method: "POST",
          headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
          body,
        }),
      );
      const parsed = await res.json();
      assertEquals(res.status, 400, `body ${JSON.stringify(body)} must be a 400, not a 5xx`);
      assertEquals(parsed.error, "bad_body");
      // Unparseable in, nothing out: the refusal is above the booking read and above every write.
      assertEquals(writes(fm.calls).length, 0, "a refused body wrote to the database");
    } finally {
      fm.restore();
    }
  }
});

Deno.test("[M1 control] a parseable body still reaches the action switch — the guard is not a blanket 400", async () => {
  // Without this, `throw new HttpError(400, "bad_body")` as the function's first line satisfies the
  // pin above while every action in the product is dead.
  const r = await post(OWNER, { booking_id: BOOKING, action: "not_a_real_action" });
  assertEquals(r.status, 400);
  assertEquals(r.body.error, "unknown action not_a_real_action", "the body was read, and the action was the problem");
});

// ═══ [backend audit 2026-09-17 · M2] A LOST NOTIFICATION IS A LOG LINE, NOT SILENCE ═════════════
// `notify` was fire-and-forget at 15 call sites: the insert's `error` was never bound, so a
// notification that failed to write was indistinguishable from one that was delivered. The worst of
// the 15 is 「인계 확인 요청」 — the only thing that asks the second party to confirm the handoff. A
// lost insert there means nobody is ever asked, nobody transitions, and the booking sits in a state
// no transition list can reach (the attack-INACTION shape), with both live screens still pointed
// at it (0181's sweep now re-sends the ask when the row is missing). `request_reschedule` is used here only because it is the
// cheapest arm that reaches the shared helper; the helper is the subject, not the action.
Deno.test("[M2] a notification insert that fails is logged with the site that lost it", async () => {
  const soon = new Date(Date.now() + 72 * 3600_000).toISOString();
  const fm = wire(OWNER, { status: "confirmed", scheduled_at: soon });
  // `/rest/v1/notifications` is deliberately left UNMOCKED — the rejected fetch is how postgrest-js
  // produces a `{ error }` without a live database, and it is the same shape a real outage gives.
  const original = console.error;
  const logs: string[] = [];
  console.error = (...a: unknown[]) => void logs.push(a.map(String).join(" "));
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({
          booking_id: BOOKING,
          action: "request_reschedule",
          meta: { new_time: new Date(Date.now() + 48 * 3600_000).toISOString() },
        }),
      }),
    );
    // ① NON-FATAL BY CONSTRUCTION, and that half matters as much as the log: the reschedule was
    //    written, so throwing here would report a transition that genuinely committed as a 500.
    assertEquals(res.status, 200);
    // ② …but it is not silent. The log names the booking AND the title, because the title is the
    //    only thing that says WHICH of the 15 sites lost its notification.
    const line = logs.find((l) => l.includes("notify failed"));
    assert(line, `a lost notification was silent: ${JSON.stringify(logs)}`);
    assert(line.includes(BOOKING), `the log cannot be resolved to a booking: ${line}`);
    assert(line.includes("일정 변경 요청"), `the log does not say which site lost it: ${line}`);
  } finally {
    console.error = original;
    fm.restore();
  }
});

Deno.test("[M2 control] a notification that SUCCEEDS logs nothing — the helper is not just noisy", async () => {
  // Without this arm, a `console.error` on every notification satisfies the pin above while burying
  // every real failure in a log nobody can read. The control is what makes the log line evidence.
  const soon = new Date(Date.now() + 72 * 3600_000).toISOString();
  const fm = wire(OWNER, { status: "confirmed", scheduled_at: soon });
  fm.on((u) => u.includes("/rest/v1/notifications"), () => FetchMock.json([{ id: "n1" }], 201));
  const original = console.error;
  const logs: string[] = [];
  console.error = (...a: unknown[]) => void logs.push(a.map(String).join(" "));
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({
          booking_id: BOOKING,
          action: "request_reschedule",
          meta: { new_time: new Date(Date.now() + 48 * 3600_000).toISOString() },
        }),
      }),
    );
    assertEquals(res.status, 200);
    assertEquals(logs.filter((l) => l.includes("notify failed")), []);
  } finally {
    console.error = original;
    fm.restore();
  }
});

// ═══ [0181] THE SWEEP RE-SENDS THE ASK UNDER THE EDGE'S EXACT STRINGS ═══════════════════════════
// `sweep_run_end_recovery` arm ⓒ (0181) matches a lost 「인계 확인 요청」 by TITLE and re-sends it
// with the same title and body, and `push.ts` routes the runner by exact title. Three files, one
// string, no shared constant they can import — so this pin reads the two server files and
// reddens if the spellings part. Comment lines are stripped first: a comment quoting the string
// must not satisfy a check for the code that writes it (the comment-quoting law).
Deno.test("[0181] the edge's confirm_handoff ask and the sweep's re-send spell the same title and body", async () => {
  const strip = (s: string, comment: RegExp) => s.split("\n").filter((l) => !comment.test(l.trim())).join("\n");
  const edge = strip(await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url)), /^\/\//);
  const sql = strip(await Deno.readTextFile(new URL("../../migrations/0181_handoff_ask_resend.sql", import.meta.url)), /^--/);
  // scoped to the confirm_handoff arm — `notify(target, …)` also appears in request_runner (지명)
  const armStart = edge.indexOf('case "confirm_handoff":');
  assert(armStart >= 0, "no confirm_handoff arm in transition-booking");
  const armEnd = edge.indexOf("\n    case ", armStart + 1);
  const arm = edge.slice(armStart, armEnd < 0 ? undefined : armEnd);
  // [0183] the ask gained a fourth argument (`{ handoff_cycle_id }`); the regex admits it
  const ask = arm.match(/notify\(target, "([^"]+)", "([^"]+)"(?:, \{[^}]*\})?\)/);
  assert(ask, "the edge's confirm_handoff arm no longer asks the counterparty with notify(target, title, body)");
  const [, title, body] = ask;
  assertEquals(title, "인계 확인 요청", "the edge's ask title moved — 0181's sweep matches on it and push.ts routes on it");
  assert(sql.includes(`c_ask_title constant text := '${title}'`), `0181's sweep does not spell the edge's title: ${title}`);
  assert(sql.includes(`c_ask_body  constant text := '${body}'`), `0181's sweep does not spell the edge's body: ${body}`);
});

// ═══ [0185] THE STAMP AND THE PROMOTION ARE ONE LOCKED RPC ══════════════════════════════════════
// 0184 stamped atomically and then promoted `picked_up` in a SECOND id-only PATCH authorised by the
// stamps the first had returned. Codex drove this handler with a reassignment between the two:
// runner A's stamp returned both stamps → the re-match voided them and minted cycle B → the handler
// marked the NEW pairing picked_up and told the OLD runner → the custody trigger recorded the new
// runner as custodian with neither confirmation. Suite-update law: the four `[0184]` pins that
// assumed the stamp-then-promote shape (a stamping PATCH carrying `select=…handoff_cycle_id` and a
// party filter; a picked_up PATCH after a two-sided returned row; the recipient from the PATCH's
// row; PGRST116 → 409) and the `[0183]` null-id pin are REPLACED by these: the edge makes ONE call,
// `rpc("confirm_handoff_tx")`, and every notification is decided by the row it returns. What SQL
// owns — the lock, the party and status gates on the locked row, the promotion condition, the
// cycle-boundary rule — is suite 216; the two-connection order is `90_race_check.sh`.
const CYCLE = "c0000000-0000-0000-0000-00000000c1c1";
const CYCLE_B = "c0000000-0000-0000-0000-00000000c2c2";
const RUNNER2 = "44444444-4444-4444-4444-444444444444";
const RPC = "/rest/v1/rpc/confirm_handoff_tx";
const confirmReq = (side: "owner" | "runner") =>
  new Request("https://proj.functions.supabase.co/transition-booking", {
    method: "POST",
    headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
    body: JSON.stringify({ booking_id: BOOKING, action: "confirm_handoff", meta: { side } }),
  });
/** The auth lookup, the pre-request booking read (GET only), the RPC's answer, and the notifications sink. */
function wireRpc(uid: string, answer: () => Response, snapshot: Record<string, unknown> = {}) {
  const fm = new FetchMock().install();
  fm.on((u) => u.includes("/auth/v1/user"), () => FetchMock.json({ id: uid, aud: "authenticated", role: "authenticated" }));
  fm.on((u) => u.includes(RPC), () => answer());
  fm.on((u) => u.includes("/rest/v1/bookings"), (call) =>
    call.method.toUpperCase() === "GET"
      ? FetchMock.json({ id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "confirmed", owner_confirmed_handoff_at: null, runner_confirmed_handoff_at: null, handoff_cycle_id: CYCLE, ...snapshot })
      : new Error(`the confirm_handoff arm wrote bookings directly: ${call.method} ${call.url}`));
  fm.on((u) => u.includes("/rest/v1/notifications"), () => FetchMock.json([{ id: "n1" }], 201));
  return fm;
}
const posts = (fm: FetchMock) => fm.calls.filter((c) => c.url.includes("/rest/v1/notifications") && c.method.toUpperCase() === "POST").map((c) => c.body);
const bookingWrites = (fm: FetchMock) => fm.calls.filter((c) => c.url.includes("/rest/v1/bookings") && c.method.toUpperCase() !== "GET").map((c) => `${c.method} ${c.url}`);
const returned = (over: Record<string, unknown>) => ({ unchanged: false, promoted: false, both: false, ask_to: OWNER, status: "confirmed", owner_id: OWNER, runner_id: RUNNER, handoff_cycle_id: CYCLE, ...over });
const refused = (name: string) => FetchMock.json({ code: "P0001", message: name, details: null, hint: null }, 400);

Deno.test("[0185] confirm_handoff is ONE rpc — confirm_handoff_tx carries the verified caller and the side; no PATCH to bookings, no promotion statement, no read after it", async () => {
  const fm = wireRpc(RUNNER, () => FetchMock.json(returned({})));
  try {
    const res = await handler(confirmReq("runner"));
    assertEquals(res.status, 200);
    const rpcs = fm.calls.filter((c) => c.url.includes(RPC));
    assertEquals(rpcs.length, 1, "exactly one confirm_handoff_tx call");
    assertEquals(rpcs[0].method.toUpperCase(), "POST");
    assertEquals(rpcs[0].body, { p_booking: BOOKING, p_uid: RUNNER, p_side: "runner" }, "the RPC must get the caller the edge verified and the side it resolved");
    assertEquals(bookingWrites(fm), [], "the edge wrote bookings itself — the stamp or the promotion left the locked transaction");
    const idx = fm.calls.indexOf(rpcs[0]);
    assertEquals(fm.calls.slice(idx + 1).filter((c) => c.url.includes("/rest/v1/bookings")).map((c) => c.url), [], "a bookings read after the RPC — a decision resting on a second transaction");
    const asks = posts(fm);
    assertEquals(asks.length, 1, "a one-sided confirm writes exactly one notification");
    assertEquals(asks[0].title, "인계 확인 요청");
    assertEquals(asks[0].profile_id, OWNER);
    assertEquals(asks[0].ref_id, BOOKING);
    assertEquals(asks[0].handoff_cycle_id, CYCLE);
  } finally {
    fm.restore();
  }
});

Deno.test("[0185] the reassignment that beat the lock: `not_party` → 409 in Korean, no promotion, no ask to the old runner, nothing written", async () => {
  // the snapshot still names RUNNER as the runner (the party gate above the switch passes); the
  // locked row does not — the re-match committed first. This is the regression the verdict asked
  // for: a reassignment between the stamp and the promotion cannot happen inside one statement, so
  // the only orders left are 「before the lock」 (this: refused by name) and 「after the commit」
  // (0048's already_handed_off on a picked_up row — SQL, suite 216 G2/G5).
  const fm = wireRpc(RUNNER, () => refused("not_party"));
  try {
    const res = await handler(confirmReq("runner"));
    assertEquals(res.status, 409);
    const body = await res.json();
    assert(typeof body.error === "string" && /[가-힣]/.test(body.error) && !body.error.includes("not_party"), `a raw refusal name reached the client: ${body.error}`);
    assertEquals(posts(fm), [], "somebody was notified about a confirmation the database refused");
    assertEquals(bookingWrites(fm), []);
  } finally {
    fm.restore();
  }
});

Deno.test("[0185] promoted: 「인계 완료」 goes to the owner and the runner ON THE RETURNED ROW — the snapshot's runner is stale — and nobody is asked", async () => {
  const fm = wireRpc(OWNER, () => FetchMock.json(returned({ promoted: true, both: true, ask_to: null, status: "picked_up", runner_id: RUNNER2 })));
  try {
    const res = await handler(confirmReq("owner"));
    assertEquals(res.status, 200);
    const rows = posts(fm);
    assertEquals(rows.map((r) => r.title), ["인계 완료", "인계 완료"], `a completed handoff tells both parties and asks nobody: ${JSON.stringify(rows.map((r) => r.title))}`);
    assertEquals(new Set(rows.map((r) => r.profile_id)), new Set([OWNER, RUNNER2]), "the runner told is the one on the row the RPC returned, not the pre-request snapshot's");
    assertEquals(bookingWrites(fm), [], "the promotion must not be a PATCH from the edge");
  } finally {
    fm.restore();
  }
});

Deno.test("[0185] one-sided: the ask goes to `ask_to` on the returned row, carrying the returned cycle — not the snapshot's counterparty, not a later read's cycle", async () => {
  const fm = wireRpc(OWNER, () => FetchMock.json(returned({ ask_to: RUNNER2, runner_id: RUNNER2, handoff_cycle_id: CYCLE_B })));
  try {
    const res = await handler(confirmReq("owner"));
    assertEquals(res.status, 200);
    const rows = posts(fm);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].title, "인계 확인 요청");
    assertEquals(rows[0].profile_id, RUNNER2, "the ask chased the runner the stale snapshot named");
    assertEquals(rows[0].handoff_cycle_id, CYCLE_B, "the ask carries a cycle other than the one the RPC returned");
  } finally {
    fm.restore();
  }
});

Deno.test("[0185] already handed off (both stamps, no promotion): 200 and silence — no ask, no 인계 완료", async () => {
  const fm = wireRpc(RUNNER, () => FetchMock.json(returned({ unchanged: true, both: true, ask_to: null, status: "picked_up" })));
  try {
    const res = await handler(confirmReq("runner"));
    assertEquals(res.status, 200);
    assertEquals(posts(fm), [], "a re-tap on a handed-off booking notified somebody");
  } finally {
    fm.restore();
  }
});

Deno.test("[0185] wrong_status is a Korean 409 with no ask; a refusal the edge does not know, or no row at all, FAILS CLOSED the same way", async () => {
  for (const [label, answer] of [
    ["wrong_status", () => refused("wrong_status")],
    ["an unknown refusal", () => refused("something_new")],
    ["no row", () => FetchMock.json(null)],
    ["a list instead of a row", () => FetchMock.json([])],
  ] as Array<[string, () => Response]>) {
    const fm = wireRpc(RUNNER, answer);
    try {
      const res = await handler(confirmReq("runner"));
      assertEquals(res.status, 409, `${label}: expected 409`);
      const body = await res.json();
      assert(typeof body.error === "string" && /[가-힣]/.test(body.error), `${label}: the client got a non-Korean sentence: ${body.error}`);
      assertEquals(posts(fm), [], `${label}: somebody was notified about a confirmation the database did not confirm`);
      assertEquals(bookingWrites(fm), []);
    } finally {
      fm.restore();
    }
  }
});

Deno.test("[0185] a booking the database has not identified yet: the ask carries null, never a made-up id", async () => {
  const fm = wireRpc(RUNNER, () => FetchMock.json(returned({ handoff_cycle_id: null })));
  try {
    const res = await handler(confirmReq("runner"));
    assertEquals(res.status, 200);
    const ask = posts(fm)[0];
    assert(ask, "no ask written");
    assert("handoff_cycle_id" in ask && ask.handoff_cycle_id === null, `expected an explicit null, got ${JSON.stringify(ask.handoff_cycle_id)}`);
  } finally {
    fm.restore();
  }
});

Deno.test("[0185] the confirm_handoff arm touches bookings only through confirm_handoff_tx (arm-scoped source pin, comments stripped)", async () => {
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  const armStart = src.indexOf('case "confirm_handoff":');
  assert(armStart >= 0, "no confirm_handoff arm in transition-booking");
  const armEnd = src.indexOf("\n    case ", armStart + 1);
  const arm = src.slice(armStart, armEnd < 0 ? undefined : armEnd);
  const code = arm.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  assert(/rpc\(\s*["']confirm_handoff_tx["']/.test(code), "the arm no longer calls rpc('confirm_handoff_tx')");
  assert(!/from\(\s*["']bookings["']\)/.test(code), "the arm reads or writes bookings directly — a decision outside the locked transaction");
  assert(!/\bset\(\s*\{/.test(code), "the arm calls set() — a promotion outside the locked transaction");
  assert(!/picked_up/.test(code), "the arm decides picked_up itself");
});

Deno.test("[0183 control] a notification from another arm carries NO handoff_cycle_id — the column is the ask's alone", async () => {
  const soon = new Date(Date.now() + 72 * 3600_000).toISOString();
  const fm = wire(OWNER, { status: "confirmed", scheduled_at: soon, handoff_cycle_id: CYCLE });
  fm.on((u) => u.includes("/rest/v1/notifications"), () => FetchMock.json([{ id: "n1" }], 201));
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({ booking_id: BOOKING, action: "request_reschedule", meta: { new_time: new Date(Date.now() + 48 * 3600_000).toISOString() } }),
      }),
    );
    assertEquals(res.status, 200);
    const rows = fm.calls.filter((c) => c.url.includes("/rest/v1/notifications") && c.method.toUpperCase() === "POST").map((c) => c.body);
    assert(rows.length >= 1, "the reschedule wrote no notification");
    for (const row of rows) assert(!("handoff_cycle_id" in row), `a non-ask notification carries handoff_cycle_id: ${JSON.stringify(row)}`);
  } finally {
    fm.restore();
  }
});

