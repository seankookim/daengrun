// register-billing-key unit tests — the card-registration slice's server half.
//
//   deno test -A supabase/functions/_test/
//
// Same caveat as every file here (confirm_payment_test.ts's header): these assert OUR handler
// against a hand-written Toss, not Toss itself. What they DO pin, and why each pin exists:
//   · the party/tombstone gate runs before anything talks to Toss (0123 §5 / 0133 posture);
//   · a Toss refusal writes NOTHING — a stored billing key whose issuance failed would be a
//     charging authority that does not exist, the worst possible row in this table;
//   · the stored card jsonb carries brand+last4 ONLY — `my_billing_card`'s whole contract, and
//     the reason a leaked billing_keys row is boring instead of a card number;
//   · upsert replaces, never accumulates — the charge core reads `.maybeSingle()` and a second
//     row per owner would turn every charge into a 500.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { registerBillingKey } from "../register-billing-key/handler.ts";
import { FakeDb, FetchMock, req } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const GHOST = "44444444-4444-4444-4444-444444444444";
const CKEY = "ck-owner-1";

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");

const isIssue = (u: string) => u.includes("/v1/billing/authorizations/issue");

function scene() {
  const db = new FakeDb();
  db.users["owner_jwt"] = OWNER;
  db.users["ghost_jwt"] = GHOST;
  db.seed("profiles", [
    { id: OWNER, toss_customer_key: CKEY, deleted_at: null },
    { id: GHOST, toss_customer_key: "ck-ghost", deleted_at: "2026-08-01T00:00:00Z" },
  ]);
  db.seed("billing_keys", []);
  return db;
}

const issued = (over: Record<string, unknown> = {}) => ({
  billingKey: "bill_abc123",
  cardCompany: "신한",
  card: { number: "433012******1234", cardType: "신용" },
  ...over,
});

Deno.test("no jwt → 401 and Toss is never called", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    let status = 0;
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak" }), db as never);
    } catch (e) {
      status = (e as HttpError).status;
    }
    assertEquals(status, 401);
    assertEquals(fm.calls.filter((c) => isIssue(c.url)).length, 0);
  } finally {
    fm.restore();
  }
});

Deno.test("tombstoned profile → 403 no_profile, before Toss (0123 §5 posture)", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    let msg = "";
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak" }, "ghost_jwt"), db as never);
    } catch (e) {
      msg = (e as HttpError).message;
    }
    assertEquals(msg, "no_profile");
    assertEquals(fm.calls.filter((c) => isIssue(c.url)).length, 0);
    assertEquals(db.rows("billing_keys").length, 0);
  } finally {
    fm.restore();
  }
});

Deno.test("prepare → returns the caller's customer key (0076 §B mint, no write)", async () => {
  const db = scene();
  const out = await registerBillingKey(req({ action: "prepare" }, "owner_jwt"), db as never) as { customer_key: string };
  assertEquals(out.customer_key, CKEY);
  assertEquals(db.rows("billing_keys").length, 0);
});

Deno.test("issue happy path → exchanges authKey with OUR customerKey, stores brand+last4 only", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const out = await registerBillingKey(
      req({ action: "issue", auth_key: "ak-1" }, "owner_jwt"), db as never,
    ) as { brand: string; last4: string };
    assertEquals(out.brand, "신한");
    assertEquals(out.last4, "1234");

    const sent = fm.calls.find((c) => isIssue(c.url))!;
    assertEquals(sent.body, { authKey: "ak-1", customerKey: CKEY });

    const rows = db.rows("billing_keys");
    assertEquals(rows.length, 1);
    assertEquals(rows[0].profile_id, OWNER);
    assertEquals(rows[0].billing_key, "bill_abc123");
    // The whole stored display surface. A masked number, an expiry, an owner name — none of it
    // is here, and this assertion is what fails if someone "helpfully" widens the jsonb.
    assertEquals(rows[0].card, { brand: "신한", last4: "1234" });
  } finally {
    fm.restore();
  }
});

Deno.test("Toss refusal → 402 with TOSS'S sentence, and NOTHING is written", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () =>
    FetchMock.json({ code: "INVALID_CARD", message: "정지된 카드예요" }, 400));
  fm.install();
  try {
    let err: HttpError | null = null;
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak-2" }, "owner_jwt"), db as never);
    } catch (e) {
      err = e as HttpError;
    }
    assertEquals(err?.status, 402);
    assertEquals(err?.message, "정지된 카드예요");
    assertEquals(db.rows("billing_keys").length, 0);
  } finally {
    fm.restore();
  }
});

Deno.test("re-issue REPLACES the row — one key per owner, structurally (.maybeSingle stays safe)", async () => {
  const db = scene();
  db.seed("billing_keys", [{
    profile_id: OWNER, billing_key: "bill_old", card: { brand: "국민", last4: "9999" },
  }]);
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    await registerBillingKey(req({ action: "issue", auth_key: "ak-3" }, "owner_jwt"), db as never);
    const rows = db.rows("billing_keys").filter((r) => r.profile_id === OWNER);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].billing_key, "bill_abc123");
  } finally {
    fm.restore();
  }
});

Deno.test("unknown action → 400, blank auth_key → 400", async () => {
  const db = scene();
  let s1 = 0, s2 = 0;
  try { await registerBillingKey(req({ action: "nope" }, "owner_jwt"), db as never); } catch (e) { s1 = (e as HttpError).status; }
  try { await registerBillingKey(req({ action: "issue", auth_key: "  " }, "owner_jwt"), db as never); } catch (e) { s2 = (e as HttpError).status; }
  assertEquals(s1, 400);
  assertEquals(s2, 400);
});

// keep the linter honest about the unused import when assert is tree-shaken
assert(true);
