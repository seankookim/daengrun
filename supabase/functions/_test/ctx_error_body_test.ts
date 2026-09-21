// `_shared/ctx.ts` — the ERROR BODY that 24 edge functions return.
//
//   deno test -A supabase/functions/_test/
//
// ═══ WHY THIS FILE EXISTS, AND WHY IT ARRIVES ONLY NOW ═══════════════════════════════════════
// `handle()`'s error arm is the single most widely shared line in `supabase/functions`, and until
// 0191 nothing pinned it. That was survivable while it built exactly one shape; it stops being
// survivable the moment the shape is CONDITIONAL, because the failure mode of a conditional body
// is invisible from every individual function: a stray `detail: undefined` on a 500 from
// `settle-run` breaks nobody's test and changes what 24 clients receive.
//
// The propositions, and they are four because they fail independently:
//   ① a plain HttpError yields `{ error }` — ONE key, byte-identical to what every existing
//      caller has always returned. This is the compatibility claim and it is the important one.
//   ② `code` alone yields `{ error, code }` — `internalError()`'s shape (audit 2026-09-17 · L1),
//      unchanged by 0191.
//   ③ `detail` alone yields `{ error, detail }` — 0191's addition.
//   ④ an EMPTY `detail` (or an empty `code`) yields NO key. The spread is truthiness-gated and
//      that is load-bearing rather than idiomatic: `delete_my_account_tx` emits `''` when it
//      refuses and could not name the blocking row (plpgsql refuses a null RAISE option, and the
//      id is read by a second statement a concurrent commit can outrun). "There is a blocker and
//      I cannot name it" must arrive as an ABSENT key, so the client renders no deep link rather
//      than a button pointed at nothing.
//
// ⚠ The status and the body are asserted TOGETHER on every arm. A body-only test would pass on a
// handler that returned the right JSON with the wrong status, which is precisely the bug the
// `not_authenticated` 401/409 split exists to prevent one layer up.
import { assertEquals } from "jsr:@std/assert@1";
import { handle, HttpError } from "../_shared/ctx.ts";

Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "svc_test_do_not_use");

const ROW = "5e551011-0000-4000-8000-00000000cafe";
const post = () => new Request("https://x/fn", { method: "POST", body: "{}" });

async function bodyOf(thrown: unknown): Promise<{ status: number; body: Record<string, unknown> }> {
  const res = await handle(() => {
    throw thrown;
  })(post());
  return { status: res.status, body: await res.json() };
}

Deno.test("ctx handle(): a plain HttpError is still ONE key — the 24-function contract, unchanged", async () => {
  const { status, body } = await bodyOf(new HttpError(409, "active_booking"));
  assertEquals(status, 409);
  assertEquals(body, { error: "active_booking" });
  assertEquals(Object.keys(body), ["error"], "no `code`, no `detail`, no undefined-valued key");
});

Deno.test("ctx handle(): `code` alone is `{ error, code }` — internalError()'s shape, untouched by 0191", async () => {
  const { status, body } = await bodyOf(new HttpError(500, "internal", "start_run_tx"));
  assertEquals(status, 500);
  assertEquals(body, { error: "internal", code: "start_run_tx" });
  assertEquals(Object.keys(body).sort(), ["code", "error"]);
});

Deno.test("ctx handle(): `detail` alone is `{ error, detail }` — 0191's addition, and the token stays bare", async () => {
  const { status, body } = await bodyOf(new HttpError(409, "club_custody_owner", undefined, ROW));
  assertEquals(status, 409);
  assertEquals(body, { error: "club_custody_owner", detail: ROW });
  // the id must NOT have been folded into the token — `api.ts`'s REFUSALS lookup is exact-match
  assertEquals(body.error, "club_custody_owner");
});

Deno.test("ctx handle(): both is `{ error, code, detail }`", async () => {
  const { status, body } = await bodyOf(new HttpError(409, "tok", "c1", ROW));
  assertEquals(status, 409);
  assertEquals(body, { error: "tok", code: "c1", detail: ROW });
});

Deno.test("ctx handle(): an EMPTY detail or code produces NO key — an absent field, never an empty one", async () => {
  // 🔴 The reason the spread is truthiness-gated. `''` is what `delete_my_account_tx` emits when a
  // refusal is real but the row could not be named, and a rendered `detail: ""` would hand every
  // client an empty handle it has to special-case. Absence is already the honest signal.
  for (const [code, detail] of [["", ROW], [undefined, ""], ["", ""]] as const) {
    const { body } = await bodyOf(new HttpError(409, "active_run", code, detail));
    assertEquals(body.error, "active_run");
    assertEquals("code" in body, code === "" ? false : code !== undefined);
    assertEquals("detail" in body, detail !== "");
  }
});

Deno.test("ctx handle(): a non-HttpError throw is still `{ error: 'internal' }` at 500", async () => {
  // The catch-all is what keeps a raw Postgres sentence out of a Korean alert box. 0191 must not
  // have widened it — a `detail` on this arm would be an unaudited field on every unhandled throw.
  const { status, body } = await bodyOf(new TypeError("column bank_accounts.holder does not exist"));
  assertEquals(status, 500);
  assertEquals(body, { error: "internal" });
});

Deno.test("ctx handle(): a success body is untouched", async () => {
  const res = await handle(() => Promise.resolve({ ok: true, n: 2 }))(post());
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true, n: 2 });
});
