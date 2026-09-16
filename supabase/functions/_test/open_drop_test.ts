// open-drop unit tests — the WIRING of `open_drop_tx` (0176), and only the wiring.
//
//   deno test -A supabase/functions/_test/
//
// ⚠ WHAT THIS SUITE CAN AND CANNOT SEE, said plainly so nobody reads a green here as broader than
// it is. Everything the old handler decided itself — party before state, the choice before the
// consuming CAS, one stamp, every reward in one transaction, a failing writer rolling the stamp
// back — now happens inside `open_drop_tx`, and is pinned by SQL suite 207 (0176-O1…O7) against a
// real database. `FakeDb` cannot reach any of it. What THIS file pins is the part only an edge can
// get wrong: that the RPC is called through the CALLER's client and never the service client, with
// exactly the argument names the migration declares; that each raise token becomes the status and
// sentence the client already keys on; that anything else is a hygienic 500; and — the pin this
// suite exists for — that the response body WRAPS the RPC's bare object as `{ applied }`, because
// `api.ts`'s openDrop unwraps one level and a bare wiring would re-open audit M4 with no gate able
// to see it. The old H1/H2 tests are gone with the handler arms they tested; H2's 「this line must
// flip」 flipped in SQL (207 0176-O5), not here.
import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { openDrop, RPC_TOKEN_MAP } from "../open-drop/handler.ts";
import { FakeDb, req, type Row } from "./fakedb.ts";

const RUNNER = "33333333-3333-3333-3333-333333333333";
const DROP = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const RECEIPT = { miles: 300, card: "레어 카드", gear: "러닝 조끼" };

/**
 * Two clients, as in production: `db` is the service client (only `caller()` may use it here) and
 * `udb` is the caller-bound client the RPC must go through. `mkUserDb` is what the handler is handed
 * instead of `callerBoundClient`; it records the request it was built from.
 */
function scene(rpc: (args: Row) => { data?: unknown; error?: { message: string } } = () => ({ data: RECEIPT })) {
  const db = new FakeDb();
  db.users["runner_jwt"] = RUNNER;
  const udb = new FakeDb();
  const calls: Row[] = [];
  udb.rpcs["open_drop_tx"] = (args: Row) => {
    calls.push(args);
    return rpc(args);
  };
  const builtFrom: Request[] = [];
  const mkUserDb = (r: Request) => {
    builtFrom.push(r);
    return udb as never;
  };
  return { db, udb, calls, builtFrom, mkUserDb };
}

/** A request whose body is NOT json — `req()` cannot express this, because it stringifies. */
function rawReq(body: string, jwt = "runner_jwt"): Request {
  return new Request("http://localhost/fn", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${jwt}` },
    body,
  });
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

/** Swallow the handler's log lines and hand them back, so "it told an operator" is checkable. */
function captureErrors() {
  const original = console.error;
  const lines: string[] = [];
  console.error = (...args: unknown[]) => void lines.push(args.map(String).join(" "));
  return { lines, restore: () => void (console.error = original) };
}

const writes = (db: FakeDb) => db.log.filter((l) => /insert|update|upsert|delete/.test(l));

// ═══ THE ENVELOPE — the pin this suite exists for ═══════════════════════════════════════════
Deno.test("[envelope] the body is { applied: <the RPC's object> } — wrapped, never bare", async () => {
  const s = scene();
  const out = await openDrop(req({ drop_id: DROP }, "runner_jwt"), s.db as never, s.mkUserDb) as Row;

  // The whole body, by value: one key, and that key holds the RPC's object unchanged.
  assertEquals(out, { applied: RECEIPT });
  assertEquals(Object.keys(out), ["applied"]);
  // The regression this guards, stated as its own assertion: a bare wiring returns the RPC's object
  // itself, `api.ts:3774` reads `.applied` off it, finds nothing, and every alert reads
  // 「보상이 적용됐어요」 again (audit M4). tsc cannot see that shape; this line can.
  assertNotEquals(out, RECEIPT as Row);
  assertEquals((out as Row).applied.miles, 300);
  // `failed` / `error` are gone with the arms that produced them — ABSENT, not empty, because
  // `api.ts` throws on a truthy `data.error`.
  assertEquals(out.failed, undefined);
  assertEquals(out.error, undefined);
});

// ═══ THE CALLER'S CLIENT, with the migration's own argument names ══════════════════════════
Deno.test("[caller client] the RPC goes through the caller-bound client with p_drop_id/p_pick_choice; the service client is never asked", async () => {
  const s = scene();
  const request = req({ drop_id: DROP }, "runner_jwt");
  await openDrop(request, s.db as never, s.mkUserDb);

  assertEquals(s.udb.log, ["rpc:open_drop_tx"], "exactly one call, on the user client");
  assert(!s.db.log.some((l) => l.startsWith("rpc:")), `the service client made an rpc call: ${JSON.stringify(s.db.log)}`);
  // The client was built from THIS request — the one carrying the runner's Authorization header.
  assertEquals(s.builtFrom.length, 1);
  assertEquals(s.builtFrom[0].headers.get("Authorization"), "Bearer runner_jwt");
  // Argument NAMES are the contract `check-rpc-contracts` checks statically; here they are checked
  // dynamically, with the values: a mini sends no choice, and "no choice" is NULL, not undefined.
  assertEquals(s.calls, [{ p_drop_id: DROP, p_pick_choice: null }]);
});

Deno.test("[caller client] a pick choice passes through unchanged", async () => {
  for (const pick of ["boost", "miles", "gear"]) {
    const s = scene(() => ({ data: { [pick === "boost" ? "boost_until" : pick]: 1 } }));
    await openDrop(req({ drop_id: DROP, pick_choice: pick }, "runner_jwt"), s.db as never, s.mkUserDb);
    assertEquals(s.calls, [{ p_drop_id: DROP, p_pick_choice: pick }]);
  }
});

// ═══ THE TOKEN MAP — each raise becomes the sentence the client already keys on ═════════════
Deno.test("[tokens] every raise token maps to its status and sentence, and the handler writes nothing", async () => {
  const expected: Record<string, [number, string]> = {
    not_signed_in: [401, "unauthorized"],
    drop_not_found: [404, "drop not found"],
    not_drop_owner: [403, "not yours"],
    already_opened: [409, "already opened"],
    bad_pick_choice: [400, "pick_choice required"],
    drop_pays_nothing: [409, "이 드랍에는 보상이 없어요 — 관리자 확인이 필요해요"],
  };
  // The map under test and the table above must name the same tokens — a token added to the
  // migration and to the map but not here would otherwise pass silently.
  assertEquals(Object.keys(RPC_TOKEN_MAP).sort(), Object.keys(expected).sort());

  for (const [token, [status, message]] of Object.entries(expected)) {
    const s = scene(() => ({ data: null, error: { message: token } }));
    const err = await expectHttpError(() =>
      openDrop(req({ drop_id: DROP, pick_choice: "boost" }, "runner_jwt"), s.db as never, s.mkUserDb)
    );
    assertEquals(err.status, status, `${token} must be ${status}`);
    assertEquals(err.message, message, `${token} must say ${message}`);
    assertEquals(err.code, undefined, `${token} is a 4xx contract token, not an internal error`);
    assertEquals(s.udb.log, ["rpc:open_drop_tx"], `${token}: exactly one rpc call`);
    assertEquals(writes(s.db), [], `${token}: the handler wrote through the service client`);
    assertEquals(writes(s.udb), [], `${token}: the handler wrote through the user client`);
  }
});

// ═══ EVERYTHING ELSE IS OURS — a hygienic 500 that keeps the database's sentence in the log ══
Deno.test("[500] an unmapped RPC error is `internal` with a code; the raw text reaches the log, never the client", async () => {
  // The exact shape a mis-wired service key produces (0176 revokes service_role): the caller must
  // not be told to "check permissions", and must not see Postgres text; the operator must.
  const raw = 'permission denied for function open_drop_tx';
  const s = scene(() => ({ data: null, error: { message: raw } }));
  const cap = captureErrors();
  let err: HttpError;
  try {
    err = await expectHttpError(() => openDrop(req({ drop_id: DROP }, "runner_jwt"), s.db as never, s.mkUserDb));
  } finally {
    cap.restore();
  }
  assertEquals(err.status, 500);
  assertEquals(err.message, "internal");
  assertEquals(err.code, "open_drop_tx");
  assert(!err.message.includes(raw));
  assert(cap.lines.some((l) => l.includes(raw) && l.includes(DROP) && l.includes(RUNNER)), `the log must carry the cause and the ids: ${JSON.stringify(cap.lines)}`);
});

Deno.test("[500] a success with no object is refused, not rendered as an empty receipt", async () => {
  // The RPC always returns a jsonb object. If it ever answers null (a broken wiring, a changed
  // return type), a `{ applied: {} }` would be a receipt for nothing — the honesty law says fail.
  for (const data of [null, undefined, "miles", [1]]) {
    const s = scene(() => ({ data }));
    const cap = captureErrors();
    let err: HttpError;
    try {
      err = await expectHttpError(() => openDrop(req({ drop_id: DROP }, "runner_jwt"), s.db as never, s.mkUserDb));
    } finally {
      cap.restore();
    }
    assertEquals(err.status, 500, `data=${JSON.stringify(data)}`);
    assertEquals(err.code, "open_drop_tx:shape");
  }
});

// ═══ THE GATES THAT STAY IN THE EDGE — token, body, id — all refuse BEFORE any rpc ═══════════
Deno.test("[M1] a malformed body is 400 bad_body, not 500 — and no rpc is made", async () => {
  for (const body of ["", "not json at all", "{", '{"drop_id":']) {
    const s = scene();
    const err = await expectHttpError(() => openDrop(rawReq(body), s.db as never, s.mkUserDb));
    assertEquals(err.status, 400, `body ${JSON.stringify(body)} must be a 400`);
    assertEquals(err.message, "bad_body");
    assertEquals(s.udb.log, [], `a refused body reached the rpc: ${JSON.stringify(s.udb.log)}`);
    assertEquals(s.builtFrom, [], "a refused body must not even build the user client");
  }
});

Deno.test("[gates] a missing drop_id is 400, and an unknown token is 401 — neither reaches the rpc", async () => {
  {
    const s = scene();
    const err = await expectHttpError(() => openDrop(req({}, "runner_jwt"), s.db as never, s.mkUserDb));
    assertEquals(err.status, 400);
    assertEquals(err.message, "missing drop_id");
    assertEquals(s.udb.log, []);
  }
  {
    const s = scene();
    const err = await expectHttpError(() => openDrop(req({ drop_id: DROP }, "stranger_jwt"), s.db as never, s.mkUserDb));
    assertEquals(err.status, 401);
    assertEquals(err.message, "unauthorized");
    assertEquals(s.udb.log, [], "an unauthenticated request must never reach the rpc");
    assertEquals(s.builtFrom, []);
  }
});

// ═══ NO ARM LEFT — the handler itself never touches a table ═════════════════════════════════
Deno.test("[no arms] on a full success the handler writes nothing through either client", async () => {
  const s = scene();
  await openDrop(req({ drop_id: DROP, pick_choice: "gear" }, "runner_jwt"), s.db as never, s.mkUserDb);
  assertEquals(writes(s.db), []);
  assertEquals(writes(s.udb), []);
  // and it never read the drop either — the RPC is the reader; a pre-read here would be a second
  // party/state gate judged by different code.
  assert(!s.db.log.some((l) => l.includes("drops")), `the handler read or wrote drops itself: ${JSON.stringify(s.db.log)}`);
});
