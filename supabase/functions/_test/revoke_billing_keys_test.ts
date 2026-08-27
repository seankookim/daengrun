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
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
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
