// [0226 · codex s2 on 0224, EDGE half] `runner_accept`'s work-gate refusal names the REAL exit for
// every `waiting_on` the server can send — and fails closed for one it has never heard of.
//
//   deno test --allow-all --node-modules-dir=auto supabase/functions/_test
//
// ═══ THE FINDING, IN ITS OWN WORDS ═════════════════════════════════════════════════════════════
// 「Once either threshold is enabled, start_run/end_run reach … the edge accept path [which] also
//  falls through to its both-parties-return message (transition-booking/index.ts:209–214). Runners
//  are blocked from accepting work and directed to an action that cannot clear the block.」
// 0224 §E made `runner_work_gate` answer `waiting_on = start_run | end_run` for a stranded custody.
// The edge's ternary knew `owner` and `runner` and sent EVERYTHING else — including those two — to
// 「이전 러닝의 인계가 양측 확인으로 끝나지 않았어요 — 인계를 마치면…」: a runner whose run never
// started was told to finish a return.
//
// ═══ WHAT THIS FILE ASSERTS ════════════════════════════════════════════════════════════════════
//   ① the three words that existed before 0224 still get their sentences BYTE FOR BYTE (the brief:
//      the existing arms do not move — the client and the inbox have been reading them for weeks);
//   ② `start_run` and `end_run` each get their OWN sentence, naming the run action that is actually
//      owed, and neither is any return sentence;
//   ③ a word the server adds LATER (and a missing / NULL one) gets a NEUTRAL refusal — still 409,
//      never the return instruction, never an acceptance;
//   ④ every gated answer is refused BEFORE the accept's write: no PATCH reaches `bookings`.
// The CONTROL is the ungated runner, who is accepted (200) through the same handler and fixtures —
// without it every assertion above would also pass against a handler that refused everyone.
//
// ═══ WHAT IT DOES NOT CLAIM ════════════════════════════════════════════════════════════════════
// That the runner app draws these words well. The client strip's mapping of the two new words is
// another builder's slice (fix/custody-strand-client); this file owns the edge's sentence only.
import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { FetchMock } from "./fakedb.ts";

const RUNNER = "33333333-3333-3333-3333-333333333333";
const OWNER = "11111111-1111-1111-1111-111111111111";
const BOOKING = "b0000000-0000-0000-0000-0000000000e1";

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

// The sentences, spelled here and NOT read out of index.ts — a pin that reads its expected string
// out of the file under test can only ever agree with it.
const OWNER_MSG = "이전 러닝의 인계를 보호자가 아직 확인하지 않았어요 — 확인되면 바로 새 러닝을 받을 수 있어요";
const RUNNER_MSG = "이전 러닝의 인계 확인이 남아 있어요 — 인계를 확인하면 새 러닝을 받을 수 있어요";
const BOTH_MSG = "이전 러닝의 인계가 양측 확인으로 끝나지 않았어요 — 인계를 마치면 새 러닝을 받을 수 있어요";
const START_MSG = "인계받은 러닝이 아직 시작되지 않았어요 — 러닝을 시작하면 새 러닝을 받을 수 있어요";
const END_MSG = "진행 중인 러닝이 아직 종료되지 않았어요 — 러닝을 종료하고 반환 확인까지 마치면 새 러닝을 받을 수 있어요";
const NEUTRAL_MSG = "이전 러닝이 아직 마무리되지 않았어요 — 지금은 새 러닝을 받을 수 없어요";
const RETURN_SENTENCES = [OWNER_MSG, RUNNER_MSG, BOTH_MSG];

/** One accept by a real runner of an open-pool booking, with the work gate answering `gate`. */
async function accept(gate: Record<string, unknown>) {
  const fm = new FetchMock().install();
  fm.on((u) => u.includes("/auth/v1/user"), () => FetchMock.json({ id: RUNNER, aud: "authenticated", role: "authenticated" }));
  fm.on((u) => u.includes("/rest/v1/runners"), () => FetchMock.json({ profile_id: RUNNER, tier: "verified" }));
  fm.on((u) => u.includes("/rest/v1/rpc/runner_work_gate"), () => FetchMock.json(gate));
  fm.on((u) => u.includes("/rest/v1/bookings"), (call) => {
    if (call.method === "PATCH") return FetchMock.json([{ id: BOOKING }]);
    // the double-booking guard is a LIST query — no conflicts, so only the gate can refuse
    if (call.url.includes("runner_id=eq.")) return FetchMock.json([]);
    return FetchMock.json({
      id: BOOKING, owner_id: OWNER, runner_id: null, status: "matching",
      club_session_id: null, scheduled_at: "2026-09-24T02:00:00Z", km: 3,
    });
  });
  fm.on((u) => u.includes("/rest/v1/notifications"), () => FetchMock.json([{ id: "n1" }]));
  fm.on((u) => u.includes("/rest/v1/"), () => FetchMock.json([]));
  try {
    const res = await handler(
      new Request("https://proj.functions.supabase.co/transition-booking", {
        method: "POST",
        headers: { Authorization: "Bearer test_jwt", "Content-Type": "application/json" },
        body: JSON.stringify({ booking_id: BOOKING, action: "runner_accept" }),
      }),
    );
    return {
      status: res.status,
      body: await res.json(),
      gateCalls: fm.countTo("/rest/v1/rpc/runner_work_gate"),
      bookingWrites: fm.calls.filter((c) => c.url.includes("/rest/v1/bookings") && c.method === "PATCH").length,
    };
  } finally {
    fm.restore();
  }
}

// the server's own shape for a gated runner (0224 §E runner_work_gate), minus what the edge ignores
const gated = (waiting_on: unknown, exit?: string) =>
  ({ gated: true, booking_id: "b0000000-0000-0000-0000-0000000000f0", status: "active", waiting_on, ...(exit ? { exit } : {}) });

// ═══ the control — the gate is consulted and an ungated runner is accepted ═════════════════════
Deno.test("[0226 s2] control: an UNGATED runner is accepted through the same handler and fixtures", async () => {
  const r = await accept({ gated: false });
  assertEquals(r.status, 200, JSON.stringify(r.body));
  assertEquals(r.gateCalls, 1, "the accept never asked the work gate — the fixture is not reaching the arm under test");
  assert(r.bookingWrites > 0, "the accepted runner wrote nothing — the control does not reach the accept's write");
});

// ═══ ① the three pre-0224 words, byte for byte ═════════════════════════════════════════════════
for (const [word, exit, msg] of [
  ["owner", "owner_confirm_return", OWNER_MSG],
  ["runner", "runner_confirm_return", RUNNER_MSG],
  ["both", "both_confirm_return", BOTH_MSG],
] as const) {
  Deno.test(`[0226 s2] waiting_on=${word} keeps its sentence byte for byte (409, no accept write)`, async () => {
    const r = await accept(gated(word, exit));
    assertEquals(r.status, 409);
    assertEquals(r.body.error, msg);
    assertEquals(r.bookingWrites, 0, "a gated runner's accept reached the booking write");
  });
}

// ═══ ② the two words 0224 added, each with its own exit ═══════════════════════════════════════
Deno.test("[0226 s2] waiting_on=start_run names STARTING the run — not a return", async () => {
  const r = await accept(gated("start_run", "runner_start_run"));
  assertEquals(r.status, 409);
  assertEquals(r.body.error, START_MSG);
  assert(r.body.error.includes("러닝을 시작"), "the start_run refusal does not name starting the run");
  for (const s of RETURN_SENTENCES) assertNotEquals(r.body.error, s, "start_run was given a RETURN sentence");
  assertEquals(r.bookingWrites, 0);
});

Deno.test("[0226 s2] waiting_on=end_run names STOPPING the run — and does not promise work on stopping alone", async () => {
  const r = await accept(gated("end_run", "runner_end_run"));
  assertEquals(r.status, 409);
  assertEquals(r.body.error, END_MSG);
  assert(r.body.error.includes("러닝을 종료"), "the end_run refusal does not name stopping the run");
  // a stopped run still owes the return stamps (0092's arm holds the runner until both land), so a
  // sentence promising work the moment the run stops would be false
  assert(r.body.error.includes("반환 확인"), "the end_run refusal promises new work on stopping alone");
  for (const s of RETURN_SENTENCES) assertNotEquals(r.body.error, s, "end_run was given a RETURN sentence");
  assertEquals(r.bookingWrites, 0);
});

// ═══ ③ an unknown word fails CLOSED and NEUTRAL ════════════════════════════════════════════════
for (const [label, word] of [
  ["a word the server adds later", "hold_for_review"],
  ["NULL", null],
  ["missing", undefined],
] as const) {
  Deno.test(`[0226 s2] waiting_on ${label} → 409 with the neutral refusal, never the return instruction`, async () => {
    const r = await accept(gated(word));
    assertEquals(r.status, 409, "an unknown gate word was ACCEPTED — the gate must fail closed");
    assertEquals(r.body.error, NEUTRAL_MSG);
    for (const s of [...RETURN_SENTENCES, START_MSG, END_MSG]) {
      assertNotEquals(r.body.error, s, "an unknown word inherited another word's instruction");
    }
    assertEquals(r.bookingWrites, 0);
  });
}

// ═══ the six sentences are six ═════════════════════════════════════════════════════════════════
Deno.test("[0226 s2] every waiting_on gets a DISTINCT sentence", async () => {
  const words: unknown[] = ["owner", "runner", "both", "start_run", "end_run", "hold_for_review"];
  const seen = new Set<string>();
  for (const w of words) seen.add((await accept(gated(w))).body.error);
  assertEquals(seen.size, words.length, `two waiting_on values share a sentence: ${[...seen].join(" | ")}`);
});
