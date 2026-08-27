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
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { registerBillingKey } from "../register-billing-key/handler.ts";
import { FakeDb, FetchMock, req, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const GHOST = "44444444-4444-4444-4444-444444444444";
const CKEY = "ck-owner-1";

Deno.env.set("TOSS_SECRET_KEY", "test_sk_do_not_use");
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co");

const isIssue = (u: string) => u.includes("/v1/billing/authorizations/issue");

function scene() {
  const db = new FakeDb();
  // billing_key_swap (0137) — the fake models the property that matters: the swap REFUSES on a
  // tombstoned profile and reports the displaced key. The real function's lock is what makes it
  // atomic; a fake cannot model a lock, so the RACE itself is pinned by the SQL suite (170) and
  // this only pins that the handler HONOURS a refusal instead of reporting success.
  // [0138 §D] the server-owned registration gate. OPEN in the default scene so the existing pins
  // keep testing what they were written to test; the closed case gets its own pin below.
  db.rpcs["card_registration_live"] = () => ({ data: true });
  db.rpcs["billing_key_swap"] = (args: Row) => {
    const prof = db.rows("profiles").find((r) => r.id === args.p_profile);
    if (!prof || prof.deleted_at != null) return { data: [{ swapped: false, displaced_key: null }] };
    const store = db.rows("billing_keys");
    const prev = store.find((r) => r.profile_id === args.p_profile);
    const displaced = prev ? prev.billing_key : null;
    if (prev) { prev.billing_key = args.p_billing_key; prev.card = args.p_card; }
    else store.push({ profile_id: args.p_profile, billing_key: args.p_billing_key, card: args.p_card });
    return { data: [{ swapped: true, displaced_key: displaced }] };
  };
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
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce: "any" }, "ghost_jwt"), db as never);
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

async function prep(db: FakeDb): Promise<string> {
  const p = await registerBillingKey(req({ action: "prepare" }, "owner_jwt"), db as never) as
    { customer_key: string; nonce: string };
  return p.nonce;
}

Deno.test("issue happy path → exchanges authKey with OUR customerKey, stores brand+last4 only", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const nonce = await prep(db);
    const out = await registerBillingKey(
      req({ action: "issue", auth_key: "ak-1", nonce }, "owner_jwt"), db as never,
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
      const nonce = await prep(db);
      await registerBillingKey(req({ action: "issue", auth_key: "ak-2", nonce }, "owner_jwt"), db as never);
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
    const nonce = await prep(db);
    await registerBillingKey(req({ action: "issue", auth_key: "ak-3", nonce }, "owner_jwt"), db as never);
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


Deno.test("🔴 codex #3 — a forged callback has no nonce: issue refuses BEFORE calling Toss", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    let err: HttpError | null = null;
    try {
      // no nonce at all — what a page inside the WebView can produce by navigating to our URL
      await registerBillingKey(req({ action: "issue", auth_key: "forged" }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.message, "stale_attempt");
    // the refusal costs nothing: Toss was never called and nothing was written
    assertEquals(fm.calls.filter((c) => isIssue(c.url)).length, 0);
    assertEquals(db.rows("billing_keys").length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 codex #3 — a nonce is SINGLE USE: replaying the real one is refused", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const nonce = await prep(db);
    await registerBillingKey(req({ action: "issue", auth_key: "ak-a", nonce }, "owner_jwt"), db as never);
    let err: HttpError | null = null;
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak-b", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.message, "stale_attempt");
  } finally { fm.restore(); }
});

Deno.test("🔴 codex #3 — a callback echoing SOMEONE ELSE'S customer key is refused", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const nonce = await prep(db);
    let err: HttpError | null = null;
    try {
      await registerBillingKey(
        req({ action: "issue", auth_key: "ak", nonce, customer_key: "ck-someone-else" }, "owner_jwt"),
        db as never,
      );
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.message, "customer_key_mismatch");
    assertEquals(fm.calls.filter((c) => isIssue(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 codex #2 — deletion wins the race: the swap refuses and issue does NOT report success", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const nonce = await prep(db);
    // the profile is tombstoned AFTER prepare and AFTER the (mocked) Toss round trip would have
    // started — which is exactly the window the edge function could not close on its own.
    db.rows("profiles").find((r) => r.id === OWNER)!.deleted_at = "2026-08-26T00:00:00Z";
    let err: HttpError | null = null;
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.message, "no_profile");
    // and NOTHING is written — a charging credential must not survive its account
    assertEquals(db.rows("billing_keys").length, 0);
  } finally { fm.restore(); }
});

Deno.test("codex #4 — a replacement REPORTS the displaced key rather than losing it silently", async () => {
  const db = scene();
  db.seed("billing_keys", [{ profile_id: OWNER, billing_key: "bill_old", card: { brand: "국민", last4: "9999" } }]);
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const nonce = await prep(db);
    await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    const rows = db.rows("billing_keys").filter((r) => r.profile_id === OWNER);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].billing_key, "bill_abc123");
  } finally { fm.restore(); }
});


Deno.test("🔴 codex #7 — the SERVER gate refuses even a well-formed call, and before Toss", async () => {
  const db = scene();
  db.rpcs["card_registration_live"] = () => ({ data: false });   // Sean has not opened it
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    let prepStatus = 0, issueStatus = 0;
    try { await registerBillingKey(req({ action: "prepare" }, "owner_jwt"), db as never); }
    catch (e) { prepStatus = (e as HttpError).status; }
    try { await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce: "n" }, "owner_jwt"), db as never); }
    catch (e) { issueStatus = (e as HttpError).status; }
    // BOTH actions refuse — a gate that only guarded `issue` would still let a client burn a
    // prepare and open a Toss page that can never complete, which is the dead-end shape.
    assertEquals(prepStatus, 503);
    assertEquals(issueStatus, 503);
    assertEquals(fm.calls.filter((c) => isIssue(c.url)).length, 0);
    assertEquals(db.rows("billing_keys").length, 0);
  } finally { fm.restore(); }
});


// ── the issued-but-unpersisted key (codex: "issuance can still create an untracked provider key")
//
// Every test below starts AFTER Toss has issued a real billing key. The question each one asks is
// the same: when our own write fails, does that live charging credential end up somewhere a sweep
// can reach it? Before this slice the answer was 「no, and nothing said so」 — the handler threw and
// the key existed at the PG, unrecorded, forever.
const isRevoke = (u: string) => u.includes("/v1/billing/bill_abc123");

/** Toss issues fine; `billing_key_swap` is the thing that breaks. */
function brokenSwap(db: FakeDb, message = "fetch failed") {
  db.rpcs["billing_key_swap"] = () => ({ error: { message } });
  db.seed("billing_key_revocations", []);
}

Deno.test("🔴 a failed swap ENQUEUES the untracked key — and still fails the request", async () => {
  const db = scene();
  brokenSwap(db);
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }

    // The failure is still a failure — compensation never turns a broken write into a success.
    assertEquals(err?.status, 500);
    assertEquals(db.rows("billing_keys").length, 0);

    const out = db.rows("billing_key_revocations");
    assertEquals(out.length, 1);
    assertEquals(out[0].billing_key, "bill_abc123");
    assertEquals(out[0].profile_id, OWNER);
    assertEquals(out[0].reason, "issued_unpersisted");

    // ⚠ AND TOSS IS NOT CALLED. An inline DELETE here would be a guess: a timed-out swap may have
    //   COMMITTED, in which case the key is the owner's live card. The outbox worker settles that
    //   against `billing_keys` (0143 §B) — this pin is what stops a later session "simplifying"
    //   the enqueue into a straight revoke.
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 outbox unreachable → the key is revoked at Toss inline, with DELETE on the real URL", async () => {
  const db = scene();
  brokenSwap(db);
  db.fail("billing_key_revocations:insert", "could not connect");
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));   // documented empty-200 success shape
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.status, 500);

    const call = fm.calls.find((c) => isRevoke(c.url))!;
    assertEquals(call.method, "DELETE");
    assertEquals(call.url, "https://api.tosspayments.com/v1/billing/bill_abc123");
    // Discharged at the provider — nothing left to record, so nothing is recorded.
    assertEquals(db.rows("billing_key_revocations").length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 revoke fails but the DB comes back → the record is retried AFTER the revoke", async () => {
  const db = scene();
  brokenSwap(db);
  db.fail("billing_key_revocations:insert", "could not connect");
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => {
      // The outage clears while we are on the phone to Toss — the whole reason the second attempt
      // exists. Without it this run ends in a console.error, which is not a record.
      delete db.failures["billing_key_revocations:insert"];
      return FetchMock.json({ code: "FORBIDDEN_REQUEST", message: "삭제할 수 없어요" }, 403);
    });
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.status, 500);

    const out = db.rows("billing_key_revocations");
    assertEquals(out.length, 1);
    assertEquals(out[0].billing_key, "bill_abc123");
    // The row carries BOTH failures, so a human reading it knows the key was never revoked.
    assertStringIncludes(String(out[0].last_error), "billing_key_swap failed");
    assertStringIncludes(String(out[0].last_error), "revoke failed (toss 403)");
  } finally { fm.restore(); }
});

Deno.test("🔴 every durable option down → still a 500, and nothing is fabricated", async () => {
  const db = scene();
  brokenSwap(db);
  db.fail("billing_key_revocations:insert", "could not connect");
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Error("network unreachable"));
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    // The worst case is the one most likely to be papered over. It must stay a failure, and the
    // handler's own message must survive the compensation rather than be replaced by it.
    assertEquals(err?.status, 500);
    assertStringIncludes(String(err?.message), "billing_key_swap failed");
    assertEquals(db.rows("billing_keys").length, 0);
    assertEquals(db.rows("billing_key_revocations").length, 0);
  } finally { fm.restore(); }
});

Deno.test("the happy path records NOTHING in the outbox — compensation is failure-only", async () => {
  const db = scene();
  db.seed("billing_key_revocations", []);
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const nonce = await prep(db);
    await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    // A control: without it, an enqueue that fired unconditionally would pass every test above.
    assertEquals(db.rows("billing_key_revocations").length, 0);
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 an FK violation costs the PROVENANCE, never the KEY", async () => {
  const db = scene();
  brokenSwap(db);
  // The profile is hard-deleted between this request's profile read and the outbox insert, so the
  // `profiles(id)` reference fails — and a lost row here would mean a live credential nobody can
  // name. 0141 §A makes the same trade inside the definer; this is its edge-side twin.
  db.fail("billing_key_revocations:insert", (p) => p.profile_id ? 'violates foreign key "profile_id"' : null);
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.status, 500);

    const out = db.rows("billing_key_revocations");
    assertEquals(out.length, 1);
    assertEquals(out[0].billing_key, "bill_abc123");   // the field the sweep needs
    assertEquals(out[0].profile_id, null);             // the field we admit we lost
    // The retry succeeded, so nothing was revoked inline — the worker still owns that decision.
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});


// ── the three refusals (0143) ────────────────────────────────────────────────────────────────
//
// 🔴 Until 0143 `swapped=false` had exactly ONE cause, so the handler mapped it to `403
//    no_profile` and was right every time. 0143 added two more — the rollout gate closing
//    mid-flight, and the key being actively revoked — and that same mapping then tells an owner
//    with a perfectly good account that they have no profile.
//
// ⚠ These pins exist because that break needs NO EDIT TO THE HANDLER to happen. Widening the
//   causes in SQL is sufficient on its own, and nothing in the TypeScript would look wrong
//   afterwards. Each arm asserts the STATUS, because the status is what decides whether a client
//   may retry — 403 says never, 503 says later, 409 says now.

/** Force `billing_key_swap` to refuse with a specific reason, after Toss has issued a real key. */
function refusingSwap(reason: string | null) {
  const db = scene();
  db.rpcs["billing_key_swap"] = () => ({
    data: [{ swapped: false, displaced_key: null, refusal: reason }],
  });
  return db;
}

async function statusOfIssue(db: ReturnType<typeof scene>): Promise<number> {
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    // `prep` mints a real nonce. A hand-written one returns 400 at the replay guard, which would
    // make every arm below "fail" for a reason that has nothing to do with what they measure —
    // four reds that look like four findings.
    const nonce = await prep(db);
    await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    return 200;
  } catch (e) { return (e as HttpError).status; }
  finally { fm.restore(); }
}

Deno.test("0143 — a tombstoned account still refuses 403 (the pre-0143 behaviour is preserved)", async () => {
  assertEquals(await statusOfIssue(refusingSwap("deleted_account")), 403);
});

Deno.test("0143 — the gate closing MID-FLIGHT is 503, not 403", async () => {
  // The owner's account is fine; Sean closed registration while we were awaiting Toss. Reusing
  // the same 503 the pre-Toss check emits, because it is the same fact arriving later.
  assertEquals(await statusOfIssue(refusingSwap("gate_closed")), 503);
});

Deno.test("0143 — a key being revoked is 409, so the caller knows it MAY retry", async () => {
  // Nothing is orphaned here and nothing is lost: Toss allows duplicate issuance, so a retry
  // produces a usable key. 403 would deny exactly the retry that fixes it.
  assertEquals(await statusOfIssue(refusingSwap("key_busy")), 409);
});

Deno.test("0143 — a refusal with NO reason falls back to 403, never to success", async () => {
  // Version skew in the other direction: an OLD definer that returns two columns. The absent
  // `refusal` must fail CLOSED to the strictest answer, not open into a 200.
  assertEquals(await statusOfIssue(refusingSwap(null)), 403);
});
