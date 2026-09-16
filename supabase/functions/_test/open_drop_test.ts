// open-drop unit tests — the suite the 2026-09-17 backend audit's L5 says did not exist.
//
//   deno test -A supabase/functions/_test/
//
// ⚠ WHY THE ABSENCE MATTERED, stated rather than implied: H1 (a receipt for rewards nobody checked
// were written), H2 (the drop is consumed before anything can pay it) and M3 (the choice whitelist
// ran AFTER the consuming write) all lived in one 68-line file with no gate of any kind behind it.
// Three defects, one file, zero tests — and two of the three are invisible to every other gate in
// the repo, because they are about what the function REPORTS rather than about what it writes.
//
// What this file can and cannot see, said plainly so nobody reads a green here as broader than it
// is: `FakeDb` has no CHECK constraints, so `drops_pick_opened_has_choice` — the constraint whose
// raw name M3 was printing into a Korean alert — cannot fire here. The M3 pin therefore asserts the
// property that makes the constraint unreachable (the whitelist runs BEFORE the CAS, and nothing is
// written when it refuses) rather than the constraint's own message. And H2 is NOT pinned at all:
// the loss it describes is that a consumed drop cannot be un-consumed, which is a statement about
// what the system will never do, and the fix for it is a SQL transaction this suite cannot reach.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { openDrop } from "../open-drop/handler.ts";
import { FakeDb, req, type Row } from "./fakedb.ts";

const RUNNER = "33333333-3333-3333-3333-333333333333";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const DROP = "dddddddd-dddd-dddd-dddd-dddddddddddd";

function scene(over: Row = {}) {
  const db = new FakeDb();
  db.users["runner_jwt"] = RUNNER;
  db.users["stranger_jwt"] = STRANGER;
  db.seed("drops", [{
    id: DROP,
    runner_id: RUNNER,
    kind: "mini",
    run_count_at: 5,
    opened_at: null,
    pick_choice: null,
    contents: { miles: 300 },
    ...over,
  }]);
  return db;
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

const drop = (db: FakeDb) => db.rows("drops")[0];

// ═══ M1 — a malformed body is the CALLER's 400, never our 500 ═══════════════════════════════════
Deno.test("[M1] a malformed body is 400 bad_body, not 500 internal — and the drop is untouched", async () => {
  for (const body of ["", "not json at all", "{", '{"drop_id":']) {
    const db = scene();
    const err = await expectHttpError(() => openDrop(rawReq(body), db as never));
    assertEquals(err.status, 400, `body ${JSON.stringify(body)} must be a 400`);
    assertEquals(err.message, "bad_body");
    // 🔴 The refusal is ABOVE every write, and on this function that is not a nicety: `opened_at`
    //    is frozen by 0106 §3, so anything that stamps it before deciding the request is valid has
    //    spent a reward on a request it was about to refuse.
    assertEquals(drop(db).opened_at, null);
    assertEquals(db.log.length, 0, `a refused body wrote something: ${JSON.stringify(db.log)}`);
  }
});

// ═══ M3 — the whitelist stands above the consuming CAS ══════════════════════════════════════════
Deno.test("[M3] a pick drop with a missing or bogus choice is refused BEFORE the consuming CAS", async () => {
  // `undefined` (the field absent), an explicit null, and a value that is not in the whitelist —
  // the three shapes `rewards.tsx` can actually produce, and all three used to reach the CAS.
  for (const pick of [undefined, null, "", "miles ", "MILES", "cash"]) {
    const db = scene({ kind: "pick", contents: {} });
    const err = await expectHttpError(() =>
      openDrop(req({ drop_id: DROP, pick_choice: pick }, "runner_jwt"), db as never)
    );
    assertEquals(err.status, 400, `pick_choice ${JSON.stringify(pick)} must be a 400`);
    assertEquals(err.message, "pick_choice required");

    // 🔴 THE ORDER IS THE FINDING, so the assertion is about the WRITE and not about the status.
    //    With the whitelist below the CAS, this same call stamped `opened_at`, wrote
    //    `pick_choice: null`, and was refused by the database — surfacing
    //    「violates check constraint "drops_pick_opened_has_choice"」 in a Korean alert while the
    //    drop was already spent. Nothing may be written on this path.
    assertEquals(drop(db).opened_at, null, `pick_choice ${JSON.stringify(pick)} consumed the drop`);
    assertEquals(db.log.length, 0, `a refused choice wrote: ${JSON.stringify(db.log)}`);
  }
});

Deno.test("[M3 control] the same whitelist does NOT refuse a mini drop, which has no choice", async () => {
  // Without this arm the pin above is satisfied by a handler that refuses everything, and the
  // entire mini path — the common case — would be dead with the suite still green.
  const db = scene();
  const out = await openDrop(req({ drop_id: DROP }, "runner_jwt"), db as never) as Row;
  assertEquals(out.applied, { miles: 300 });
  assert(drop(db).opened_at !== null, "a valid mini open must consume the drop");
});

// ═══ H1 — a key reaches `applied` only when its write landed ════════════════════════════════════
Deno.test("[H1] a writer that fails is named in `failed` and never appears in `applied`", async () => {
  // One case per writer, because each was a SEPARATE unbound `error` and a fix to one says nothing
  // about the other three (the finding's sentence covers all of them; the audit cited :34/:41/:51/:58).
  const cases: { name: string; drop: Row; failKey: string; appliedKey: string }[] = [
    { name: "mini card", drop: { kind: "mini", contents: { card: "레어 카드" } }, failKey: "cards_owned:upsert", appliedKey: "card" },
    { name: "mini gear", drop: { kind: "mini", contents: { gear: "러닝 조끼" } }, failKey: "gear_claims:insert", appliedKey: "gear" },
    { name: "mini miles", drop: { kind: "mini", contents: { miles: 300 } }, failKey: "miles_ledger:insert", appliedKey: "miles" },
  ];
  for (const c of cases) {
    const db = scene(c.drop).fail(c.failKey, "could not connect");
    const cap = captureErrors();
    let out: Row;
    try {
      out = await openDrop(req({ drop_id: DROP }, "runner_jwt"), db as never) as Row;
    } finally {
      cap.restore();
    }

    assertEquals(out.applied, {}, `${c.name}: a write that failed must not appear in the receipt`);
    assertEquals(out.failed, [c.appliedKey], `${c.name}: the failure must be named`);
    // The honest sentence rides in `error`, which `api.ts:3770` already checks at every invoke
    // site — so the existing client says 「오픈 실패」 instead of celebrating an empty receipt.
    assert(String(out.error).includes("적용되지 않았어요"), `${c.name}: no honest sentence: ${out.error}`);

    // 🔴 The drop IS consumed and stays consumed — this is H2, unfixed and deliberately pinned as
    //    the true current behaviour rather than as an aspiration. When `open_drop_tx` lands, this
    //    line is the one that must flip, and flipping it is the proof the transaction works.
    assert(drop(db).opened_at !== null, `${c.name}: the CAS ran, so the drop is spent`);

    // An operator is told, with the drop id — there is no sweep for a stamped drop with no reward,
    // so a log line that omits the id is a log line nobody can act on.
    assert(
      cap.lines.some((l) => l.includes(DROP) && l.includes("FAILED")),
      `${c.name}: no log line names the drop: ${JSON.stringify(cap.lines)}`,
    );
    assert(
      cap.lines.some((l) => l.includes("CONSUMED")),
      `${c.name}: the log never says the drop was spent: ${JSON.stringify(cap.lines)}`,
    );
  }
});

Deno.test("[H1] a pick drop's single writer is reported the same way", async () => {
  for (
    const [pick, failKey, key] of [
      ["boost", "boosts:insert", "boost_until"],
      ["miles", "miles_ledger:insert", "miles"],
      ["gear", "gear_claims:insert", "gear"],
    ] as const
  ) {
    const db = scene({ kind: "pick", contents: {} }).fail(failKey, "could not connect");
    const cap = captureErrors();
    let out: Row;
    try {
      out = await openDrop(req({ drop_id: DROP, pick_choice: pick }, "runner_jwt"), db as never) as Row;
    } finally {
      cap.restore();
    }
    assertEquals(out.applied, {}, `${pick}: nothing landed, so nothing may be claimed`);
    assertEquals(out.failed, [key]);
    assert(drop(db).opened_at !== null, `${pick}: the drop is spent (H2, unfixed)`);
  }
});

Deno.test("[H1] a PARTIAL mini drop reports what landed AND what did not, in one answer", async () => {
  // The case a thrown 500 cannot express and the old code could not see: two rewards written, one
  // lost. Throwing would have denied the runner the two they won; the old code would have claimed
  // all three.
  const db = scene({ contents: { miles: 300, card: "레어 카드", gear: "러닝 조끼" } })
    .fail("gear_claims:insert", "could not connect");
  const cap = captureErrors();
  let out: Row;
  try {
    out = await openDrop(req({ drop_id: DROP }, "runner_jwt"), db as never) as Row;
  } finally {
    cap.restore();
  }

  assertEquals(out.applied, { miles: 300, card: "레어 카드" });
  assertEquals(out.failed, ["gear"]);
  assert(String(out.error).includes("기어"), `the sentence must name the reward: ${out.error}`);
  // and the two that DID land are really in the database, not just in the receipt
  assertEquals(db.rows("miles_ledger").length, 1);
  assertEquals(db.rows("cards_owned").length, 1);
  assertEquals(db.rows("gear_claims").length, 0);
});

// ═══ happy paths — the receipt is complete and carries no failure vocabulary ════════════════════
Deno.test("happy path — a mini drop's receipt names every reward and omits `failed` entirely", async () => {
  const db = scene({ contents: { miles: 300, card: "레어 카드", gear: "러닝 조끼" } });
  const out = await openDrop(req({ drop_id: DROP }, "runner_jwt"), db as never) as Row;

  assertEquals(out.applied, { miles: 300, card: "레어 카드", gear: "러닝 조끼" });
  // `failed` and `error` are ABSENT, not empty — `api.ts` throws on a truthy `data.error`, so an
  // empty-string `error` on a success would turn every successful open into 「오픈 실패」.
  assertEquals(out.failed, undefined);
  assertEquals(out.error, undefined);

  assertEquals(db.rows("miles_ledger")[0].delta, 300);
  assertEquals(db.rows("miles_ledger")[0].ref_id, DROP);
  assertEquals(db.rows("cards_owned")[0].card_key, "drop-5");
  assertEquals(db.rows("gear_claims")[0].status, "claimable");
  assert(drop(db).opened_at !== null);
});

Deno.test("happy path — each pick choice applies exactly its own reward and is recorded on the row", async () => {
  for (const pick of ["boost", "miles", "gear"] as const) {
    const db = scene({ kind: "pick", contents: {} });
    const out = await openDrop(req({ drop_id: DROP, pick_choice: pick }, "runner_jwt"), db as never) as Row;
    const applied = out.applied as Row;

    assertEquals(out.failed, undefined);
    assertEquals(Object.keys(applied).length, 1, `${pick} applied ${JSON.stringify(applied)}`);
    assertEquals(db.rows("boosts").length, pick === "boost" ? 1 : 0);
    assertEquals(db.rows("miles_ledger").length, pick === "miles" ? 1 : 0);
    assertEquals(db.rows("gear_claims").length, pick === "gear" ? 1 : 0);
    if (pick === "boost") {
      // the receipt's value is the row's value, not a second computation of "now + 24h"
      assertEquals(applied.boost_until, db.rows("boosts")[0].ends_at);
    }
    if (pick === "miles") assertEquals(applied.miles, 5000);
    // the choice is on the drop row — it is the runner-motivation signal the pick drop exists for
    assertEquals(drop(db).pick_choice, pick);
  }
});

// ═══ the gates above the CAS — party and state, in that order ═══════════════════════════════════
Deno.test("the party, state and id gates all stand above the CAS and write nothing", async () => {
  // A stranger
  {
    const db = scene();
    const err = await expectHttpError(() => openDrop(req({ drop_id: DROP }, "stranger_jwt"), db as never));
    assertEquals(err.status, 403);
    assertEquals(db.log.length, 0);
  }
  // A drop that is already open — the second tap, which is the race the CAS exists for
  {
    const db = scene({ opened_at: "2026-09-17T00:00:00.000Z" });
    const err = await expectHttpError(() => openDrop(req({ drop_id: DROP }, "runner_jwt"), db as never));
    assertEquals(err.status, 409);
    assertEquals(db.log.length, 0);
  }
  // No id at all
  {
    const db = scene();
    const err = await expectHttpError(() => openDrop(req({}, "runner_jwt"), db as never));
    assertEquals(err.status, 400);
    assertEquals(err.message, "missing drop_id");
    assertEquals(db.log.length, 0);
  }
  // A drop that is not ours to find
  {
    const db = scene();
    const err = await expectHttpError(() =>
      openDrop(req({ drop_id: "00000000-0000-0000-0000-000000000000" }, "runner_jwt"), db as never)
    );
    assertEquals(err.status, 404);
  }
});

Deno.test("the CAS is the only thing that may stamp the drop — a lost race writes no reward", async () => {
  // The concurrent-open race the CAS was added for: the read said `opened_at` was null, and by the
  // time the update ran it was not. Modelled by a `drops:update` that matches zero rows.
  const db = scene();
  db.triggers["drops"] = () => {};
  db.rows("drops")[0].opened_at = null;
  // Make the CAS match nothing by moving the row out from under its `.eq("id", …)` filter after the
  // read — the fake resolves filters at exec time, which is exactly the window under test.
  const original = db.from.bind(db);
  let reads = 0;
  // deno-lint-ignore no-explicit-any
  (db as any).from = (table: string) => {
    if (table === "drops" && reads++ === 1) db.rows("drops")[0].opened_at = "2026-09-17T00:00:00.000Z";
    return original(table);
  };
  const err = await expectHttpError(() => openDrop(req({ drop_id: DROP }, "runner_jwt"), db as never));
  assertEquals(err.status, 409);
  assertEquals(err.message, "already opened");
  assertEquals(db.rows("miles_ledger").length, 0, "a lost race must not pay the reward twice");
});
