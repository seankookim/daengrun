// [0214 F4 — executing review 2026-09-23] `runner_accept` authorizes BEFORE it reads a booking.
//
//   deno test --allow-all --node-modules-dir=auto supabase/functions/_test
//
// ═══ THE FINDING, IN ITS OWN WORDS ═════════════════════════════════════════════════════════════
// 「`index.ts:96` exempts `runner_accept` and `resolve_return` from the party gate, the booking read
//  at `index.ts:86` precedes both, and only one of the two got a gate of its own. Any signed-in
//  caller can therefore tell a booking uuid from a non-booking uuid, and the privileged read
//  happens either way.」
//
// Measured by that reviewer, with a signed-in NON-RUNNER:
//     present = 403 {"error":"runner only"}
//     absent  = 404 {"error":"booking not found"}
//     privileged fetches for the ABSENT id: ["…/rest/v1/bookings?select=*&id=eq.<absent>"]
//
// This file is the sibling of `resolve_return_gate_test.ts` and deliberately copies its shape: the
// two exemptions are one sentence at two sites, and 0201 §C closed the first of them. Pinning the
// second the same way is what stops the pair drifting apart again.
//
// ═══ WHAT THIS FILE ASSERTS, AND WHY 「IDENTICAL」 RATHER THAN 「403」 ═════════════════════════════
// A pin that only asserted 403 would stay green under a handler that answered 403 for a real
// booking and 404 for a missing one — which IS the oracle, wearing a refusal's costume. So the two
// responses are compared to EACH OTHER, status and body, across the two worlds that used to answer
// differently. And the strongest arm is not about the answer at all: a non-runner must make NO
// request to `/rest/v1/bookings`. A response can be made uniform while the privileged read still
// happens, and only the call log separates 「refused」 from 「refused after reading」.
//
// ═══ THE CONTROLS, AND THERE ARE TWO ═══════════════════════════════════════════════════════════
//   ① A REAL RUNNER still accepts — same handler, same fixtures — so 「it refuses everyone」 is
//      excluded. Without it every assertion here would also pass against a handler that threw 403
//      at the top of the function for its own unrelated reason.
//   ② A real runner gets DIFFERENT answers for the two worlds (200 vs 404). That is what makes the
//      non-runner's two being identical a fact about AUTHORIZATION rather than about the fixtures.
//
// ═══ WHAT IT DOES NOT CLAIM ════════════════════════════════════════════════════════════════════
// A registered runner can still distinguish a real booking id from an absent one, and that is
// inherent: the exemption exists so a runner can accept a booking they are not yet a party to. The
// oracle is reduced from 「any signed-in account」 to 「a runner row」, not removed — `index.ts` says
// so at the fix and control ② measures exactly that difference rather than hiding it.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { FetchMock } from "./fakedb.ts";

const STRANGER = "44444444-4444-4444-4444-444444444444";   // signed in, no `runners` row
const RUNNER = "33333333-3333-3333-3333-333333333333";
const OWNER = "11111111-1111-1111-1111-111111111111";
const PRESENT = "b0000000-0000-0000-0000-0000000000d1";
const ABSENT = "b0000000-0000-0000-0000-0000000000d2";

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
 * THE TWO WORLDS. `PRESENT` is an open-pool booking a real runner can genuinely accept; `ABSENT`
 * is a uuid with no row. The difference between them is precisely what the finding says a
 * non-runner could read off the response.
 *
 * `isRunner` decides whether `/rest/v1/runners?profile_id=eq.<uid>` answers with a row. That table
 * is read for TWO different questions in this handler — the eligibility check and, in other code
 * paths, a commission rate — so the mock keys on the caller rather than on the URL.
 */
function wire(uid: string, isRunner: boolean) {
  const fm = new FetchMock().install();
  fm.on((u) => u.includes("/auth/v1/user"), () => FetchMock.json({ id: uid, aud: "authenticated", role: "authenticated" }));
  fm.on((u) => u.includes("/rest/v1/runners"), () =>
    isRunner
      ? FetchMock.json({ profile_id: uid, tier: "verified" })
      // PostgREST's `.single()` over zero rows — the shape `index.ts` turns into 403.
      : FetchMock.json({ message: "JSON object requested, multiple (or no) rows returned" }, 406));
  fm.on((u) => u.includes("/rest/v1/bookings"), (call) => {
    if (call.url.includes(ABSENT)) {
      return FetchMock.json({ message: "JSON object requested, multiple (or no) rows returned" }, 406);
    }
    if (call.method === "PATCH") return FetchMock.json([{ id: PRESENT }]);
    // The double-booking guard (`runner_id=eq.<uid>` + `status=in.(…)`) is a LIST query, so it must
    // answer with an array — an object here becomes `(mine ?? []).find is not a function` and the
    // control fails for a reason that has nothing to do with the gate. No conflicts: the arm this
    // file owns is authorization, and a 409 from an overlapping run would mask the 200.
    if (call.url.includes("runner_id=eq.")) return FetchMock.json([]);
    return FetchMock.json({
      id: PRESENT,
      owner_id: OWNER,
      runner_id: null,
      status: "matching",
      club_session_id: null,
      scheduled_at: "2026-09-24T02:00:00Z",
      km: 3,
    });
  });
  // The work gate (0092 ⑫) and the notification insert are on the SUCCESS path only. They are
  // mocked rather than left out so control ① measures an acceptance that completes, not one that
  // dies on an unmocked fetch.
  fm.on((u) => u.includes("/rest/v1/rpc/runner_work_gate"), () => FetchMock.json({ gated: false, waiting_on: null }));
  fm.on((u) => u.includes("/rest/v1/notifications"), () => FetchMock.json([{ id: "n1" }]));
  fm.on((u) => u.includes("/rest/v1/"), () => FetchMock.json([]));
  return fm;
}

async function post(uid: string, bookingId: string, isRunner: boolean) {
  const fm = wire(uid, isRunner);
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({ booking_id: bookingId, action: "runner_accept" }),
      }),
    );
    return { status: res.status, body: await res.json(), calls: fm.calls };
  } finally {
    fm.restore();
  }
}

/** Every booking read the handler made. The eligibility check itself is not privileged: it reads
 *  one row keyed on the caller's OWN id and tells them nothing they did not supply. */
const bookingReads = (calls: { url: string }[]) =>
  calls.filter((c) => c.url.includes("/rest/v1/bookings")).map((c) => c.url);

// ═══ the finding, reproduced as an equality ════════════════════════════════════════════════════
Deno.test("[0214 F4] a NON-RUNNER gets the identical answer for a real booking id and an absent one", async () => {
  const p = await post(STRANGER, PRESENT, false);
  const a = await post(STRANGER, ABSENT, false);

  assertEquals(p.status, 403);
  assertEquals(a.status, p.status);
  assertEquals(JSON.stringify(a.body), JSON.stringify(p.body));
  // …and it is the eligibility refusal, not the party gate's sentence and not a 404
  assertEquals(p.body.error, "runner only");
});

Deno.test("[0214 F4] a NON-RUNNER causes NO booking read at all — for either id", async () => {
  // The response can be made uniform while the read still happens; only the call log separates
  // 「refused」 from 「refused after reading a stranger's booking」. This is the arm the finding is
  // actually about, and it is the one that would have caught the shipped behaviour.
  for (const id of [PRESENT, ABSENT]) {
    const r = await post(STRANGER, id, false);
    assertEquals(
      bookingReads(r.calls),
      [],
      `a non-runner reached bookings for ${id}: ${bookingReads(r.calls).join(", ")}`,
    );
  }
});

// ═══ the controls — this is a gate and not a wall ══════════════════════════════════════════════
Deno.test("[0214 F4] control ①: a real RUNNER still accepts the open-pool booking", async () => {
  const r = await post(RUNNER, PRESENT, true);
  assertEquals(r.status, 200);
  assert(
    bookingReads(r.calls).length > 0,
    "the runner path never read the booking — the fixture is not exercising the accept",
  );
});

Deno.test("[0214 F4] control ②: a real RUNNER gets DIFFERENT answers for the two worlds", async () => {
  // Without this, 「the non-runner's two answers are identical」 could be a fact about the fixtures
  // (e.g. both ids resolving the same way) rather than about authorization.
  const present = await post(RUNNER, PRESENT, true);
  const absent = await post(RUNNER, ABSENT, true);
  assertEquals(absent.status, 404);
  assert(
    present.status !== absent.status,
    `the two worlds are indistinguishable even for a runner (${present.status} vs ${absent.status}) — the fixture cannot see this class`,
  );
});

// ═══ the ordering, held in SOURCE as well as in behaviour ══════════════════════════════════════
Deno.test("[0214 F4] the runner eligibility check literally precedes the booking read in index.ts", async () => {
  // The behavioural arms above are the real pins. This one exists because the ORDER is the
  // property and a future edit could restore the read above the check while every response stayed
  // correct for the fixtures here. Comments are stripped first: this file's prose and index.ts's
  // both explain the check at length, and an un-stripped match is satisfied by the paragraph
  // rather than by the code (the standing comment-matching law).
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  const code = src.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  const check = code.indexOf('from("runners")');
  const read = code.indexOf('from("bookings")');
  assert(check >= 0, "index.ts no longer reads `runners` — re-scope this pin");
  assert(read >= 0, "index.ts no longer reads the booking — re-scope this pin");
  assert(
    check < read,
    "the runner eligibility check no longer precedes the booking read (executing review 2026-09-23 F4 is back)",
  );
  // …and it is keyed on the VERIFIED caller, never on a value out of the body.
  assert(
    /from\("runners"\)[\s\S]{0,120}eq\("profile_id",\s*uid\)/.test(code),
    "the runner lookup is no longer keyed on the verified `uid`",
  );
  // ONE read, not two: the pre-flight must be a MOVE, not an added round trip beside a surviving
  // in-case lookup. ⚠ Counting `from("runners")` across the whole file is the WRONG detector and
  // was caught by running it: `request_runner` has its own, unrelated `runners` lookup keyed on
  // `meta.runner_id`, so a file-wide count of 1 would be false for correct code and would force a
  // later session to delete something it should not. The question is about the `runner_accept`
  // case BODY, so that is what is sliced out and asked.
  const caseStart = code.indexOf('case "runner_accept":');
  assert(caseStart >= 0, "the runner_accept case is gone — re-scope this pin");
  const caseEnd = code.indexOf('case "', caseStart + 10);
  const caseBody = code.slice(caseStart, caseEnd > 0 ? caseEnd : code.length);
  assert(
    !caseBody.includes('from("runners")'),
    "the runner_accept case still looks `runners` up for itself — the pre-flight was added beside the old read instead of replacing it, which is an extra round trip and a second place for the two to drift",
  );
});

// ═══ the sibling did not move ══════════════════════════════════════════════════════════════════
Deno.test("[0214 F4] both exemptions are still gated, and the party gate still names both", async () => {
  // 0201 §C and 0214 F4 are one sentence at two sites. This arm fails if a later edit removes one
  // exemption's pre-flight while leaving it in the party gate's `if` — the exact state this slice
  // found and closed.
  const src = await Deno.readTextFile(new URL("../transition-booking/index.ts", import.meta.url));
  const code = src.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  const partyGate = code.indexOf("not a party");
  assert(partyGate >= 0, "the party gate is gone — re-scope this pin");
  for (const exempt of ["runner_accept", "resolve_return"]) {
    assert(
      code.includes(`action !== "${exempt}"`),
      `${exempt} is no longer exempt from the party gate — if that is deliberate, delete its pre-flight too`,
    );
  }
  assert(
    code.indexOf('rpc("ops_is_member"') >= 0 && code.indexOf('rpc("ops_is_member"') < partyGate,
    "resolve_return's own gate no longer precedes the party gate (0201 §C)",
  );
  assert(
    code.indexOf('from("runners")') < partyGate,
    "runner_accept's own gate no longer precedes the party gate",
  );
});
