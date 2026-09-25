// transition-booking `resolve_return` — the runner is TOLD when ops resolves their stranded return
// (gap sweep 2, ops-notifications-3, 2026-09-25).
//
//   deno test --allow-all --node-modules-dir=auto _test
//
// A stranded return blocks the runner's new work (`_runner_work_gate_blocking`, 0092) and the
// sweep told them 「…확인되면 정산이…」 (0226) — and then nothing told them it was over: the only
// notification on this path was settle_run_tx's 「러닝 완료」 to the OWNER (0169). These pins hold
// the one push the runner now gets, and the three ways it must NOT be sent.
//
// The mutations that redden it: delete the notify call (the brief's plant) · drop `!res.unchanged`
// (a re-call on a completed booking pushes again) · address it to the owner · move it above the
// RPC (a refusal would push).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { resolveReturn } from "../transition-booking/resolve_return.ts";
import { RETURN_SEALED_TITLE } from "../transition-booking/confirm_return.ts";
import { FakeDb } from "./fakedb.ts";

const OPS = "99999999-9999-9999-9999-999999999999";
const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

type Answer = { data?: unknown; error?: { message: string } };

function scene(answer: Answer, over: { priced?: boolean } = {}) {
  const db = new FakeDb();
  db.seed("runs", over.priced === false ? [] : [{ booking_id: BOOKING, actual_km: 4.2, end_reason: "completed" }]);
  db.seed("runners", [{ profile_id: RUNNER, commission_rate: 0.33 }]);
  db.rpcs["compute_runner_payout"] = () => ({ data: [{ base: 9900, distance: 12600, addon: 0, guarantee: 0, fee: 4500 }] });
  db.rpcs["ops_resolve_return_tx"] = () => answer as { data?: unknown; error?: { message: string } };
  // collection is allowed to fail on its own (its own catch owns it) — mocked as not-live.
  db.rpcs["mint_settle_charge_intent"] = () => ({ data: [] });
  return db;
}

/** index.ts's `notify`, recorded. It never throws; it returns the insert error or null. */
function recorder(db: FakeDb, fail: string | null = null) {
  const sent: { to: string; title: string; body: string; afterRpc: boolean }[] = [];
  const fn = (to: string, title: string, body: string) => {
    sent.push({ to, title, body, afterRpc: db.log.includes("rpc:ops_resolve_return_tx") });
    return Promise.resolve(fail ? { message: fail } : null);
  };
  return { sent, fn };
}

const bk = (runner: string | null = RUNNER) => ({ id: BOOKING, owner_id: OWNER, runner_id: runner, status: "active" });

function quiet<T>(fn: () => Promise<T>): Promise<T> {
  const log = console.log, err = console.error;
  console.log = () => {};
  console.error = () => {};
  return fn().finally(() => { console.log = log; console.error = err; });
}

async function run(db: FakeDb, n: ReturnType<typeof recorder>, runner: string | null = RUNNER) {
  return await quiet(() =>
    resolveReturn(db as never, { bookingId: BOOKING, uid: OPS, bk: bk(runner), meta: { memo: "현장 확인" }, notify: n.fn })
  );
}

async function refusal(db: FakeDb, n: ReturnType<typeof recorder>, memo = "현장 확인"): Promise<HttpError> {
  try {
    await quiet(() =>
      resolveReturn(db as never, { bookingId: BOOKING, uid: OPS, bk: bk(), meta: { memo }, notify: n.fn })
    );
  } catch (e) {
    assert(e instanceof HttpError, `expected HttpError, got ${e}`);
    return e;
  }
  throw new Error("expected a refusal, got a resolved value");
}

Deno.test("[ops-notifications-3] a resolution that happened tells the RUNNER once — sealed title, the settled sentence", async () => {
  const db = scene({ data: { resolved: true, settled: true, unchanged: false, resolution_id: "r1", from_status: "active" } });
  const n = recorder(db);
  const res = await run(db, n);
  assertEquals(res.resolved, true);
  assertEquals(n.sent.length, 1, `expected exactly one notification: ${JSON.stringify(n.sent)}`);
  assertEquals(n.sent[0].to, RUNNER);
  assertEquals(n.sent[0].title, RETURN_SEALED_TITLE);
  assertEquals(n.sent[0].body, "담당자가 반환을 확인했어요 — 러닝이 마무리됐어요");
  assert(n.sent[0].afterRpc, "the runner was told before the resolution was committed");
  assert(!n.sent.some((s) => s.to === OWNER), "this path addressed the owner (0169's 러닝 완료 already does)");
});

Deno.test("[ops-notifications-3] resolved but not settled → the runner hears that settlement waits", async () => {
  const db = scene({ data: { resolved: true, settled: false, unchanged: false, resolution_id: "r2", from_status: "incident_review" } });
  const n = recorder(db);
  await run(db, n);
  assertEquals(n.sent.length, 1);
  assertEquals(n.sent[0].title, RETURN_SEALED_TITLE);
  assertEquals(n.sent[0].body, "담당자가 반환을 확인했어요 — 정산은 담당자 확인 뒤에 진행돼요");
});

Deno.test("[ops-notifications-3] a re-call on an already-completed booking (unchanged) pushes NOTHING", async () => {
  const db = scene({ data: { resolved: false, settled: true, unchanged: true } });
  const n = recorder(db);
  const res = await run(db, n);
  assertEquals(res.unchanged, true);
  assertEquals(n.sent.length, 0, `an unchanged re-call pushed: ${JSON.stringify(n.sent)}`);
});

Deno.test("[ops-notifications-3] resolved:true with unchanged:true still pushes nothing (the conjunct is load-bearing on its own)", async () => {
  // `_settle_sealed_run` answers unchanged only for a completed row, which ops_resolve_return_tx
  // returns before resolving — so this pairing is not produced today. It is asserted because the
  // gate names BOTH facts, and a gate that silently dropped one would pass every reachable fixture.
  const db = scene({ data: { resolved: true, settled: true, unchanged: true, resolution_id: "r3" } });
  const n = recorder(db);
  await run(db, n);
  assertEquals(n.sent.length, 0);
});

Deno.test("[ops-notifications-3] a REFUSAL pushes nothing — not_ops, already_sealed, a missing memo, an unpriceable run", async () => {
  for (const [msg, status] of [["not_ops", 403], ["already_sealed", 409], ["not_resolvable", 409]] as const) {
    const db = scene({ error: { message: msg } });
    const n = recorder(db);
    const e = await refusal(db, n);
    assertEquals(e.status, status, `${msg} mapped to ${e.status}`);
    assertEquals(n.sent.length, 0, `${msg} pushed: ${JSON.stringify(n.sent)}`);
  }
  {
    const db = scene({ data: { resolved: true, settled: true, unchanged: false } });
    const n = recorder(db);
    const e = await refusal(db, n, "   ");
    assertEquals(e.status, 400);
    assertEquals(n.sent.length, 0);
  }
  {
    const db = scene({ data: { resolved: true, settled: true, unchanged: false } }, { priced: false });
    const n = recorder(db);
    const e = await refusal(db, n);
    assertEquals(e.status, 503);
    assertEquals(n.sent.length, 0);
    assert(!db.log.includes("rpc:ops_resolve_return_tx"), "an unpriceable run reached the resolver");
  }
});

Deno.test("[ops-notifications-3] no runner on the row → no push, and the resolution still answers", async () => {
  const db = scene({ data: { resolved: true, settled: true, unchanged: false, resolution_id: "r4" } });
  const n = recorder(db);
  const res = await run(db, n, null);
  assertEquals(res.resolved, true);
  assertEquals(n.sent.length, 0);
});

Deno.test("[ops-notifications-3] a lost notification does not change the operator's answer", async () => {
  // index.ts's notify returns the insert error rather than throwing (and logs it with its title);
  // the resolution has committed, so the response must still say so.
  const db = scene({ data: { resolved: true, settled: true, unchanged: false, resolution_id: "r5" } });
  const n = recorder(db, "insert failed");
  const res = await run(db, n);
  assertEquals(res.resolved, true);
  assertEquals(n.sent.length, 1);
});

Deno.test("[ops-notifications-3] index.ts hands resolve_return its notify helper (a dropped argument would type-check as missing)", async () => {
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  const code = src.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  assert(
    /resolveReturn\(db, \{[^}]*\bnotify\b[^}]*\}\)/.test(code),
    "index.ts no longer passes `notify` to resolveReturn",
  );
});
