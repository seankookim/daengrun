// [0201 §C — codex 2026-09-22 #5] `resolve_return` authorizes BEFORE it reads or prices anything.
//
//   deno test --allow-all --node-modules-dir=auto supabase/functions/_test
//
// ═══ THE FINDING, IN ITS OWN WORDS ═════════════════════════════════════════════════════════════
// 「The new action bypasses the outer party gate and calls quoteFor before checking ops membership.
//  A targeted Deno probe produced 503 for an unpriceable victim run and 403 not_ops for a priceable
//  one using the same stranger identity. Thus anyone with a booking ID can distinguish its
//  pricing/frozen-run state and invoke privileged pricing work.」
//
// `resolve_return` is the ONE action deliberately exempt from `index.ts`'s party gate (an operator
// is not a party), which is exactly why it needed a gate of its own in front of the booking read.
// It now has one: `ops_is_member('return_strand', uid)`, on the id `caller()` verified.
//
// ═══ WHAT THIS FILE ASSERTS, AND WHY THE SHAPE IS 「IDENTICAL」 RATHER THAN 「403」 ════════════════
// A pin that only asserted 403 would stay green under a handler that answered 403 for a priceable
// booking and 404 for a missing one — which is the oracle, wearing a refusal's costume. So the
// three responses are compared to EACH OTHER, byte for byte (status + body), across three
// deliberately different worlds: a booking that prices, a booking that cannot be priced (no
// `runs.actual_km`), and a booking id that does not exist at all. The fixtures are what make the
// comparison mean something — they are the three worlds that used to answer differently.
//
// And the strongest arm is not about the answer at all: a non-ops caller must make NO REQUEST to
// `/rest/v1/bookings`, `/rest/v1/runs` or `/rest/v1/rpc/compute_runner_payout`. The response could
// be made uniform while the privileged work still happened; only the call log can tell those apart.
//
// ═══ THE CONTROL ═══════════════════════════════════════════════════════════════════════════════
// An OPS caller still resolves — same handler, same fixtures, same harness — so 「refuses everyone」
// is excluded. Without it every assertion here would also pass against a handler that threw 403 at
// the top of the function for its own unrelated reason.
//
// ═══ HOW IT REACHES THE HANDLER ════════════════════════════════════════════════════════════════
// `transition-booking/index.ts` calls `Deno.serve` at module top level, so the module cannot be
// imported for its arms. Same trick `transition_booking_actions_test.ts` uses and for the same
// reason: swap `Deno.serve` for a recorder before the dynamic import, keep the handler it is given,
// and drive it with real `Request` objects over a `FetchMock`. Every fetch the handler is allowed
// to make is declared; anything else rejects loudly, which is what makes 「it did no privileged
// work」 a measurement instead of an assumption.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { FetchMock } from "./fakedb.ts";

const OPS = "0bbb0000-0000-0000-0000-0000000000b5";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const PRICEABLE = "b0000000-0000-0000-0000-00000000000a";
const UNPRICEABLE = "b0000000-0000-0000-0000-00000000000b";
const ABSENT = "b0000000-0000-0000-0000-00000000000c";

Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "svc_test_do_not_use");

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
 * THE THREE WORLDS. `booking` decides which one this request lands in, and the difference between
 * them is precisely what the finding says a stranger could read off the response:
 *   PRICEABLE   — a stopped run with `actual_km` and `end_reason`, so `quoteFor` succeeds and the
 *                 RPC is reached (an ops caller gets a resolution; a stranger used to get 403).
 *   UNPRICEABLE — the booking exists, the run row has no measurement, so `quoteFor` returns null
 *                 and the handler fails closed with 503 (what a stranger used to get).
 *   ABSENT      — no such booking (404).
 */
function wire(uid: string, isOps: boolean) {
  const fm = new FetchMock().install();
  fm.on((u) => u.includes("/auth/v1/user"), () => FetchMock.json({ id: uid, aud: "authenticated", role: "authenticated" }));
  fm.on(
    (u) => u.includes("/rest/v1/rpc/ops_is_member"),
    () => FetchMock.json(isOps),
  );
  fm.on((u) => u.includes("/rest/v1/bookings"), (call) => {
    if (call.url.includes(ABSENT)) {
      // PostgREST's `.single()` over zero rows — the shape `index.ts` turns into 404.
      return FetchMock.json({ message: "JSON object requested, multiple (or no) rows returned" }, 406);
    }
    const id = call.url.includes(UNPRICEABLE) ? UNPRICEABLE : PRICEABLE;
    return FetchMock.json({
      id,
      owner_id: OWNER,
      runner_id: RUNNER,
      status: "active",
      club_session_id: null,
      run_ended_at: "2026-09-22T01:00:00Z",
      settlement_ready_at: null,
      runner_confirmed_return_at: "2026-09-22T01:05:00Z",
      owner_confirmed_return_at: null,
    });
  });
  fm.on((u) => u.includes("/rest/v1/runs"), (call) =>
    FetchMock.json(
      call.url.includes(UNPRICEABLE)
        ? { actual_km: null, end_reason: null }
        : { actual_km: 4.2, end_reason: "completed" },
    ));
  fm.on((u) => u.includes("/rest/v1/runners"), () => FetchMock.json({ commission_rate: 0.33 }));
  fm.on(
    (u) => u.includes("/rest/v1/rpc/compute_runner_payout"),
    () => FetchMock.json([{ base: 9900, distance: 12600, addon: 0, guarantee: 0, fee: 4500 }]),
  );
  // 🔴 THE SQL GATE IS MODELLED, NOT ASSUMED AWAY. `ops_resolve_return_tx` refuses a non-operator
  // with `not_ops` (0193 §C-b ②, unchanged by 0201) and the edge maps that to 403. Stubbing it as
  // an unconditional success would make a handler WITHOUT the pre-flight answer 200 here — a
  // defect this repo does not have, and a reproduction that over-states the finding is as useless
  // as one that under-states it. With the refusal modelled, deleting the pre-flight reproduces
  // codex's measurement exactly: 403 for a priceable booking, 503 for an unpriceable one.
  fm.on(
    (u) => u.includes("/rest/v1/rpc/ops_resolve_return_tx"),
    () =>
      isOps
        ? FetchMock.json({ resolved: true, settled: true, unchanged: false, resolution_id: "r1", from_status: "active" })
        : FetchMock.json({ message: "not_ops" }, 400),
  );
  // `collectAfterSettle` runs after a successful settle and is allowed to fail — its own catch owns
  // that. It is mocked as a refusal rather than left unmocked so the control's 200 is about the
  // resolution and not about collection happening to work.
  fm.on((u) => u.includes("/rest/v1/rpc/"), () => FetchMock.json({ message: "not mocked" }, 400));
  return fm;
}

async function post(uid: string, bookingId: string, isOps: boolean, memo = "확인 완료") {
  const fm = wire(uid, isOps);
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({ booking_id: bookingId, action: "resolve_return", meta: { memo } }),
      }),
    );
    return { status: res.status, body: await res.json(), calls: fm.calls };
  } finally {
    fm.restore();
  }
}

/** Every request the handler made to something other than auth and the membership check. */
const privileged = (calls: { url: string }[]) =>
  calls.filter((c) =>
    !c.url.includes("/auth/v1/user") && !c.url.includes("/rest/v1/rpc/ops_is_member")
  ).map((c) => c.url);

// ═══ the finding, reproduced as an equality ════════════════════════════════════════════════════
Deno.test("[0201 #5] a NON-OPS caller gets the identical answer for priceable / unpriceable / absent", async () => {
  const p = await post(STRANGER, PRICEABLE, false);
  const u = await post(STRANGER, UNPRICEABLE, false);
  const a = await post(STRANGER, ABSENT, false);

  // status AND body, compared to each other — 「all 403」 alone would not catch a handler that
  // answered 403 with two different sentences.
  assertEquals(p.status, 403);
  assertEquals([u.status, a.status], [p.status, p.status]);
  assertEquals(JSON.stringify(u.body), JSON.stringify(p.body));
  assertEquals(JSON.stringify(a.body), JSON.stringify(p.body));
  // and it is the ops refusal, not the party gate's sentence and not a 404
  assertEquals(p.body.error, "담당자만 반환을 대신 정리할 수 있어요");
});

Deno.test("[0201 #5] a NON-OPS caller causes NO privileged work — no booking read, no pricing", async () => {
  // The response can be made uniform while the work still happens; only the call log separates
  // 「refused」 from 「refused after doing everything」. This is the arm the finding is actually about.
  for (const id of [PRICEABLE, UNPRICEABLE, ABSENT]) {
    const r = await post(STRANGER, id, false);
    assertEquals(
      privileged(r.calls),
      [],
      `a non-ops caller reached the database for ${id}: ${privileged(r.calls).join(", ")}`,
    );
  }
});

Deno.test("[0201 #5] the refusal precedes even the memo check — a blank memo answers the same 403", async () => {
  // `resolve_return.ts` refuses an empty memo with 400 before it prices. If the ops gate sat after
  // that, a stranger could still tell 「this endpoint knows about memos」 apart from anything else,
  // and more importantly the ordering would be one edit away from drifting back.
  const blank = await post(STRANGER, PRICEABLE, false, "   ");
  const withMemo = await post(STRANGER, PRICEABLE, false);
  assertEquals(blank.status, withMemo.status);
  assertEquals(JSON.stringify(blank.body), JSON.stringify(withMemo.body));
  assertEquals(privileged(blank.calls), []);
});

// ═══ the control — an operator still gets through, so this is a gate and not a wall ════════════
Deno.test("[0201 #5] control: an OPS caller resolves the priceable booking and the work happens", async () => {
  const r = await post(OPS, PRICEABLE, true);
  assertEquals(r.status, 200);
  assertEquals(r.body.resolved, true);
  const urls = privileged(r.calls);
  assert(urls.some((u) => u.includes("/rest/v1/bookings")), "the ops path never read the booking");
  assert(
    urls.some((u) => u.includes("/rest/v1/rpc/compute_runner_payout")),
    "the ops path never priced the run",
  );
  assert(
    urls.some((u) => u.includes("/rest/v1/rpc/ops_resolve_return_tx")),
    "the ops path never called the resolver",
  );
});

Deno.test("[0201 #5] control: an OPS caller still gets 503 on an unpriceable run (fail-closed intact)", async () => {
  // The fix must not have turned the pricing refusal into an authorization refusal. This is the
  // 503 the finding used as one half of its oracle — it is CORRECT, for an authorized caller.
  const r = await post(OPS, UNPRICEABLE, true);
  assertEquals(r.status, 503);
  assert(
    !r.body.error.includes("담당자만"),
    `an unpriceable run answered with the ops refusal: ${r.body.error}`,
  );
});

Deno.test("[0201 #5] control: an OPS caller gets 404 for a booking that does not exist", async () => {
  // …and the three answers an OPERATOR gets are DIFFERENT from each other, which is what makes the
  // stranger's three being identical a fact about authorization rather than about the fixtures.
  const r = await post(OPS, ABSENT, true);
  assertEquals(r.status, 404);
});

// ═══ fail closed ═══════════════════════════════════════════════════════════════════════════════
Deno.test("[0201 #5] an ops_is_member that ERRORS refuses, and reads nothing", async () => {
  // A database that predates 0201 has no such function, and a transport failure looks the same. The
  // failure direction must be 「an operator retries」, never 「a stranger is priced」.
  const fm = new FetchMock().install();
  fm.on((u) => u.includes("/auth/v1/user"), () => FetchMock.json({ id: OPS, aud: "authenticated", role: "authenticated" }));
  fm.on(
    (u) => u.includes("/rest/v1/rpc/ops_is_member"),
    () => FetchMock.json({ message: "function public.ops_is_member(text, uuid) does not exist" }, 404),
  );
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({ booking_id: PRICEABLE, action: "resolve_return", meta: { memo: "x" } }),
      }),
    );
    assertEquals(res.status, 403);
    // nothing but auth + the failed check was attempted — an unmocked `/rest/v1/bookings` would
    // have rejected and surfaced as a 500 here, which is itself a second witness
    assertEquals(privileged(fm.calls), []);
  } finally {
    fm.restore();
  }
});

// ═══ the ordering, held in SOURCE as well as in behaviour ══════════════════════════════════════
Deno.test("[0201 #5] the ops check literally precedes the booking read in index.ts", async () => {
  // The behavioural arms above are the real pins. This one exists because the ORDER is the property
  // and a future edit could restore the read above the check while every response stayed correct
  // for the fixtures here. Comments are stripped first: this file's own prose and index.ts's
  // explain the check at length, and an un-stripped match is satisfied by the paragraph rather than
  // by the code (the standing comment-matching law).
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  const code = src.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  const check = code.indexOf('rpc("ops_is_member"');
  const read = code.indexOf('from("bookings")');
  assert(check >= 0, "index.ts no longer calls ops_is_member — the pre-flight gate is gone");
  assert(read >= 0, "index.ts no longer reads the booking — re-scope this pin");
  assert(
    check < read,
    "the ops membership check no longer precedes the booking read (codex 2026-09-22 #5 is back)",
  );
  // …and it is passed the VERIFIED caller, never a value out of the body (`resolve_return.ts` §2).
  assert(
    /p_actor:\s*uid/.test(code),
    "ops_is_member is no longer called with the verified `uid`",
  );
});
