// revoke-billing-keys — the worker that drains the revocation outbox.
//
//   deno test -A supabase/functions/_test/
//
// 🔴 THIS FILE EXISTS BECAUSE ITS ABSENCE HID A CRITICAL BUG. The worker shipped calling
//    `POST /v1/billing/{key}/delete` — an endpoint that does not exist. Toss answers a missing
//    route with 404, the worker read 404 as 「already deleted, success」, and so the outbox drained
//    100% clean while **not one billing key was ever deleted at the payment gateway**. Nothing
//    pinned the URL or the method, so nothing could redden.
//    The first two tests below are the ones that would have caught it.
import { assert, assertEquals, assertMatch, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { revokeBillingKeys } from "../revoke-billing-keys/handler.ts";
import { FakeDb, FetchMock, type Row } from "./fakedb.ts";

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("CRON_COLLECT_KEY", "cron-secret");

const isBilling = (u: string) => u.includes("api.tosspayments.com/v1/billing/");

/** The cron's request shape — the ONLY authenticated way in. */
const cronReq = (key = "cron-secret") =>
  new Request("https://x/revoke-billing-keys", {
    method: "POST",
    headers: { "X-Cron-Key": key, "Content-Type": "application/json" },
    body: "{}",
  });

// The reports are collected OUTSIDE the fake rather than bolted onto it — FakeDb is shared with
// every other function test and must not grow a field for one caller's convenience.
function scene(rows: Row[] = [{ id: "rev-1", billing_key: "bill_X", claim_token: "tok-1" }]) {
  const db = new FakeDb();
  const reported: Row[] = [];
  db.rpcs["claim_billing_key_revocations"] = () => ({ data: rows });
  db.rpcs["report_billing_key_revocation"] = (a: Row) => { reported.push(a); return { data: true }; };
  return { db, reported };
}

Deno.test("🔴 calls DELETE on the REAL endpoint — no /delete suffix, no POST", async () => {
  const { db, reported } = scene();
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    await revokeBillingKeys(cronReq(), db as never);
    const call = fm.calls.find((c) => isBilling(c.url))!;
    // The two assertions the missing test would have made. Either one alone catches the bug:
    // the suffix was invented, and the helper hardcoded POST.
    assertEquals(call.method, "DELETE");
    assertEquals(call.url, "https://api.tosspayments.com/v1/billing/bill_X");
    assert(!call.url.includes("/delete"), "the /delete suffix does not exist in Toss's API");
  } finally { fm.restore(); }
});

Deno.test("🔴 a 404 is a FAILURE, not 'already deleted' — and it names the URL as the suspect", async () => {
  const { db, reported } = scene();
  // exactly what the WRONG url produced: a missing route
  const fm = new FetchMock().on(isBilling, () =>
    FetchMock.json({ code: "NOT_FOUND_HTTP_METHOD", message: "존재하지 않는 HTTP 메소드 접근입니다" }, 404));
  fm.install();
  try {
    const out = await revokeBillingKeys(cronReq(), db as never) as { revoked: number; failed: number };
    assertEquals(out.revoked, 0);
    assertEquals(out.failed, 1);
    const rep = reported[0];
    assertEquals(rep.p_ok, false);
    // Toss never documents the already-deleted response, so reading 404 as success was hope, not
    // measurement. The row must survive for a human to see.
    assertStringIncludes(String(rep.p_error), "CHECK THE URL");
  } finally { fm.restore(); }
});

Deno.test("an empty 200 body is SUCCESS — it is the documented shape, not a parse fault", async () => {
  const { db, reported } = scene();
  // Toss: 「비어있는 body에 200 응답만 내려갑니다」 — call() sets body={parse_error:true} here,
  // and judging on that instead of the status would fail every successful revocation.
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const out = await revokeBillingKeys(cronReq(), db as never) as { revoked: number };
    assertEquals(out.revoked, 1);
    assertEquals(reported[0].p_ok, true);
  } finally { fm.restore(); }
});

Deno.test("the claim token is carried into the report (compare-and-set)", async () => {
  const { db, reported } = scene();
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    await revokeBillingKeys(cronReq(), db as never);
    assertEquals(reported[0].p_token, "tok-1");
  } finally { fm.restore(); }
});

Deno.test("a lost lease (report refused) counts as stale, not as revoked", async () => {
  const { db, reported } = scene();
  db.rpcs["report_billing_key_revocation"] = () => ({ data: false });   // someone else owns it now
  void reported;
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const out = await revokeBillingKeys(cronReq(), db as never) as { revoked: number; stale: number };
    assertEquals(out.revoked, 0);
    assertEquals(out.stale, 1);
  } finally { fm.restore(); }
});

Deno.test("🔴 no cron key → 401, and Toss is never called", async () => {
  const { db, reported } = scene();
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    let status = 0;
    try {
      await revokeBillingKeys(new Request("https://x/revoke-billing-keys", { method: "POST" }), db as never);
    } catch (e) { status = (e as HttpError).status; }
    assertEquals(status, 401);
    assertEquals(fm.calls.filter((c) => isBilling(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 an UNSET cron secret authenticates nobody", async () => {
  const { db, reported } = scene();
  const saved = Deno.env.get("CRON_COLLECT_KEY")!;
  Deno.env.delete("CRON_COLLECT_KEY");
  try {
    let status = 0;
    try { await revokeBillingKeys(cronReq(""), db as never); } catch (e) { status = (e as HttpError).status; }
    // 503, never 200 — without this line a misconfigured deploy is an open, admin-powered,
    // credential-destroying endpoint (collect-charges' own comment, same hazard).
    assertEquals(status, 503);
  } finally { Deno.env.set("CRON_COLLECT_KEY", saved); }
});

// ═══ [0157 · codex billing #7] the cron secret is compared in constant time ═══════════════════
//
// 🔴 The finding: `cronKey !== expected` on an endpoint deployed with `verify_jwt = false`.
//    JS string equality short-circuits at the first differing byte, so the ONE thing standing
//    between the internet and a service-role, credential-destroying batch job leaked its own secret
//    through timing — and `CRON_COLLECT_KEY` is SHARED with `collect-charges`, so a compromise
//    reached here arms the sibling too.
//
// ⚠ **THE TIMING PROPERTY ITSELF IS NOT OBSERVABLE FROM A UNIT TEST AND NOTHING BELOW CLAIMS IT.**
//   A wall-clock assertion on two comparisons would be a coin flip on a loaded machine — a pin that
//   is a probability, which this repo already has a name for. The two behavioural tests pin the
//   semantics a digest-based comparison could plausibly break (same-length and different-length
//   wrong keys must both be 401), and the SOURCE pin below is what actually distinguishes the fixed
//   code from the unfixed code. Two kinds of evidence; neither is the other.
Deno.test("🔴 a wrong cron key of the SAME LENGTH as the real one → 401, and Toss is never called", async () => {
  const { db } = scene();
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const sameLength = "x".repeat("cron-secret".length);
    assertEquals(sameLength.length, "cron-secret".length);
    let status = 0;
    try { await revokeBillingKeys(cronReq(sameLength), db as never); } catch (e) { status = (e as HttpError).status; }
    assertEquals(status, 401);
    assertEquals(fm.calls.filter((c) => isBilling(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 a wrong cron key of a DIFFERENT length → 401, and Toss is never called", async () => {
  const { db } = scene();
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    let status = 0;
    try { await revokeBillingKeys(cronReq("cron-secret-plus-tail"), db as never); } catch (e) { status = (e as HttpError).status; }
    assertEquals(status, 401);
    assertEquals(fm.calls.filter((c) => isBilling(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 the CORRECT key still passes — the control, without which 401-always would pass everything above", async () => {
  const { db, reported } = scene();
  const fm = new FetchMock().on(isBilling, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const out = await revokeBillingKeys(cronReq(), db as never) as { revoked: number };
    assertEquals(out.revoked, 1);
    assertEquals(reported[0].p_ok, true);
  } finally { fm.restore(); }
});

Deno.test("🔴 BOTH cron endpoints go through the shared constant-time gate — no `!==` survives", async () => {
  // ⚠ COMMENTS ARE STRIPPED BEFORE MATCHING, and here that is load-bearing rather than hygiene:
  //   the comments this slice added to both handlers QUOTE the removed `!==` in order to explain
  //   why it went. Un-stripped, "documented the fix" and "did not make the fix" are the same string
  //   to grep — the standing comment-quoting law, and this file would be its next instance.
  const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
  for (const rel of ["../revoke-billing-keys/handler.ts", "../collect-charges/handler.ts"]) {
    const raw = await Deno.readTextFile(new URL(rel, import.meta.url));
    const src = strip(raw);
    // Fail LOUDLY if the strip ate the file or the file moved — an empty haystack makes every
    // `assert(!...)` below vacuously true, which is the exact false green this repo keeps meeting.
    assert(src.includes("X-Cron-Key"), `${rel}: source not found or over-stripped`);
    assert(src.includes("requireCronKey("), `${rel}: does not call the shared constant-time gate`);
    assert(!/cronKey\s*!==\s*expected/.test(src), `${rel}: still compares the secret with !==`);
    assert(!/Deno\.env\.get\("CRON_COLLECT_KEY"\)/.test(src), `${rel}: still reads the secret itself`);
  }
});

Deno.test("🔴 the deployment contract is COMMITTED, not typed — config.toml turns JWT verification off", async () => {
  // The tests above prove the handler refuses without `X-Cron-Key`. They are only load-bearing if
  // the request ever REACHES the handler: pg_net sends no JWT, and Supabase verifies JWTs by
  // default, so without this config entry every cron tick is rejected at the platform — silently,
  // because `dispatch_billing_key_revocations` fires and never reads the response.
  //
  // ⚠ The two halves are one decision. This pin exists so deleting the config entry reddens here
  //   rather than turning the revocation cron into a no-op nobody notices; the 401/503 pins above
  //   are the other half, and neither is safe without the other.
  const toml = await Deno.readTextFile(new URL("../../config.toml", import.meta.url));
  const section = toml.split(/^\[/m).find((s) => s.startsWith("functions.revoke-billing-keys]"));
  assert(section, "supabase/config.toml has no [functions.revoke-billing-keys] table");
  assertMatch(section, /^\s*verify_jwt\s*=\s*false\s*$/m);
});
