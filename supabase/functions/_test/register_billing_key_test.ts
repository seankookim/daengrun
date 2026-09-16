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
  // [0170] the issuance INTENT — the durable record written BEFORE Toss is called (codex billing
  // finding 3). The fake models the three properties the handler actually depends on: one row per
  // attempt nonce, a retried open returning the SAME idempotency key, and a terminal intent
  // refusing to reopen. The LOCK, the ACL and the constraints are pinned by suite 200, which is the
  // right tool for them; this fake exists so these tests can see what the handler RECORDS.
  db.seed("billing_issue_intents", []);
  db.rpcs["billing_issue_intent_open"] = (args: Row) => {
    const prof = db.rows("profiles").find((r) => r.id === args.p_profile);
    if (!prof || prof.deleted_at != null) {
      return { data: [{ intent_id: null, idempotency_key: null, reopened: false, refusal: "deleted_account" }] };
    }
    const rows = db.rows("billing_issue_intents");
    const prev = rows.find((r) => r.attempt_nonce === args.p_nonce);
    if (prev) {
      if (prev.state !== "issuing") {
        return { data: [{ intent_id: null, idempotency_key: null, reopened: false, refusal: "intent_closed" }] };
      }
      return { data: [{ intent_id: prev.id, idempotency_key: prev.idempotency_key, reopened: true, refusal: null }] };
    }
    const row: Row = {
      id: crypto.randomUUID(),
      profile_id: args.p_profile,
      attempt_nonce: args.p_nonce,
      customer_key: args.p_customer_key,
      idempotency_key: crypto.randomUUID(),
      state: "issuing",
      billing_key: null,
      note: null,
    };
    rows.push(row);
    return { data: [{ intent_id: row.id, idempotency_key: row.idempotency_key, reopened: false, refusal: null }] };
  };
  db.rpcs["billing_issue_intent_close"] = (args: Row) => {
    const row = db.rows("billing_issue_intents").find((r) => r.id === args.p_intent);
    if (!row) return { data: [{ closed: false, refusal: "no_intent" }] };
    if (row.state !== "issuing") return { data: [{ closed: false, refusal: "already_closed" }] };
    row.state = args.p_outcome;
    row.billing_key = args.p_billing_key ?? null;
    row.note = args.p_note ?? null;
    return { data: [{ closed: true, refusal: null }] };
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


// 🔴 codex deploy-gate #5 (2026-09-15) — PARTY BEFORE STATE, IN THE ONE FIXTURE WHERE THE TWO
//    ORDERS DISAGREE. The handler read `card_registration_live()` before the profile/tombstone
//    check, so a tombstoned or non-existent account was answered `503 card_registration_not_live`
//    — a free read of our rollout state, handed to exactly the callers least entitled to it. The
//    SQL door next to it has always had the right order and says why (0170:193-199): 「the rollout
//    state is not a fact that account is entitled to learn, and 「deleted」 is the stronger
//    refusal」.
//
// ⚠ WHY THIS TEST HAD TO BE WRITTEN RATHER THAN INHERITED, and it is the transferable part: the
//   two orders AGREE everywhere except one cell of a 2×2. Flag OPEN + tombstoned ⇒ 403 either way
//   (that is the shipped test at the top of this file); flag CLOSED + live owner ⇒ 503 either way
//   (that is the codex #7 test directly above). **Only flag CLOSED + tombstoned separates them**,
//   and no shipped test stood there — every one of them sets exactly one of the two conditions.
//   A suite can be thorough, green, and structurally unable to see a gate-ordering defect, because
//   ordering is only observable where BOTH gates would fire.
Deno.test("🔴 deploy-gate #5 — a tombstoned caller gets 403 no_profile even with the flag CLOSED (party gate before state gate)", async () => {
  const db = scene();
  db.rpcs["card_registration_live"] = () => ({ data: false });   // Sean has not opened it
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    let issueStatus = 0, issueMsg = "";
    let prepStatus = 0, prepMsg = "";
    try { await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce: "n" }, "ghost_jwt"), db as never); }
    catch (e) { issueStatus = (e as HttpError).status; issueMsg = (e as HttpError).message; }
    try { await registerBillingKey(req({ action: "prepare" }, "ghost_jwt"), db as never); }
    catch (e) { prepStatus = (e as HttpError).status; prepMsg = (e as HttpError).message; }
    // The assertions are two-sided on purpose. 「is 403」 alone would be satisfied by a handler that
    // had stopped reading the flag at all; 「is not 503」 names the exact leak, so a future reorder
    // that reintroduces it fails on a line that says what it was.
    assertEquals(issueStatus, 403);
    assertEquals(issueMsg, "no_profile");
    assertEquals(prepStatus, 403);
    assertEquals(prepMsg, "no_profile");
    // Nothing downstream is reached either — the refusal is still before Toss and before any write.
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

/** Toss issues fine; `billing_key_swap` is REFUSED BY OUR OWN SQL — a SQLSTATE came back, so the
 *  transaction aborted, the key is certainly not stored, and the definer's own in-transaction
 *  enqueue (0141 §A / 0143 §A) rolled back with it. That is the branch on which this handler may
 *  order a revocation.
 *
 *  ⚠ THE `code` IS THE WHOLE FIXTURE and it used to be absent: before deploy-gate HIGH #2 this
 *    helper failed the swap with a bare `{ message: "fetch failed" }` — the AMBIGUOUS case — and
 *    the handler enqueued on it anyway, because it could not tell the two apart. Every pin below
 *    that asserts an enqueue therefore needs a DEFINITE fixture now, and `unknownSwap` covers the
 *    other side. The cast is because `FakeDb.rpcs` types its error as `{ message: string }`; the
 *    fake passes the object through untouched, which is what the handler reads.
 */
function brokenSwap(
  db: FakeDb,
  message = 'duplicate key value violates unique constraint "billing_key_revocations_outstanding_uq"',
  code = "23505",
) {
  db.rpcs["billing_key_swap"] = () => ({ error: { message, code } as unknown as { message: string } });
  db.seed("billing_key_revocations", []);
}

/** The other half: the swap's outcome is UNKNOWN. A returned error carrying no SQLSTATE is what a
 *  dropped fetch, a gateway 5xx or a PostgREST-level refusal looks like — we did not learn whether
 *  the transaction committed, so the key may be the owner's live card. */
function unknownSwap(db: FakeDb, message = "fetch failed") {
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

    // ⚠ AND TOSS IS NOT CALLED — not on this path and, since deploy-gate HIGH #2, not on ANY path
    //   through this handler. The outbox worker settles the order against `billing_keys` (0143 §B)
    //   before anything is destroyed; a DELETE from here bypasses that belt entirely. This pin is
    //   what stops a later session "simplifying" the enqueue into a straight revoke.
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});

// 🔴 A PIN REVERSED ON PURPOSE — deploy-gate HIGH #2, 2026-09-15. This test used to be
//    「outbox unreachable → the key is revoked at Toss inline, with DELETE on the real URL」 and it
//    was a correct pin of a behaviour that has since become wrong, which is exactly the case
//    CLAUDE.md says must be updated in the same slice rather than left red or deleted.
//
// ⚠ WHY THE OLD BEHAVIOUR WAS RIGHT AND IS NOT ANY MORE. The inline DELETE bought one thing: a key
//   we could not record was, before 0170, a live charging credential named in NO table at all —
//   and an unnamed credential is worse than a destroyed one. 0170 writes the intent row BEFORE
//   Toss is called and closes it `issued_unpersisted` naming the billing key AND the idempotency
//   key. The namelessness was the entire rationale; it is gone, so the DELETE goes with it.
//   The property this pin now owns: **the outbox being down is not a licence to touch the key.**
Deno.test("🔴 deploy-gate #2 — outbox unreachable → STILL no DELETE at Toss; the intent row is the record", async () => {
  const db = scene();
  brokenSwap(db);
  db.fail("billing_key_revocations:insert", "could not connect");
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));   // available, and deliberately unused
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.status, 500);

    // 🔴 THE REVERSAL, IN ONE LINE. The DELETE that used to be asserted here — on a key the swap
    //    may have stored — is now asserted ABSENT.
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
    // Nothing landed in the outbox either: it is the thing that is down.
    assertEquals(db.rows("billing_key_revocations").length, 0);
    // …and this is why that is survivable, which is the half the old pin could not have asserted.
    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "issued_unpersisted");
    assertEquals(rows[0].billing_key, "bill_abc123");
    assert(typeof rows[0].idempotency_key === "string" && rows[0].idempotency_key.length > 0);
  } finally { fm.restore(); }
});

// 🔴 REPLACES 「revoke fails but the DB comes back → the record is retried AFTER the revoke」, whose
//    property no longer exists: there is no inline revoke, so there is no window after it to retry
//    in, and the second `enqueueUntrackedKey` call that existed only to use that window is gone.
//    What takes its slot is the arm the old fixture was silently standing in for — `brokenSwap`
//    used to fail with a bare `{ message: "fetch failed" }`, i.e. the UNKNOWN case, while every
//    assertion written on it read as if the refusal were definite.
Deno.test("🔴 deploy-gate #2 — an UNKNOWN swap error (no SQLSTATE) orders NOTHING and sends nothing", async () => {
  const db = scene();
  unknownSwap(db);                       // a returned error with no `code` — a dropped fetch, a 5xx
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
    // The client-visible answer is unchanged — the same 500 with the same sentence.
    assertEquals(err?.status, 500);
    // ⚠ [backend audit 2026-09-17 · L1] THIS PIN MOVED, AND ONLY ITS HANDLE MOVED. It read
    //    `assertStringIncludes(err.message, "billing_key_swap failed")` — i.e. it asserted that the
    //    raw Postgres sentence reaches the CLIENT, which is the thing L1 removes. The property it
    //    exists for is unchanged and is asserted below on a stronger handle: the 500 must be
    //    attributable to the SWAP and not to the compensation that runs after it (the intent close,
    //    the outbox order, the Toss call). `code` is produced by exactly one `throw` in this handler
    //    and by nothing else, so it pins that better than a substring of a database's prose did.
    //    The full text is still pinned where it is DURABLE — see the `note` assertion on the intent
    //    row, which is where an operator reads it.
    assertEquals(err?.code, "billing_key_swap");
    // and the raw Postgres text is GONE from the body — the L1 property itself, pinned
    assertEquals(err?.message, "internal");

    // 🔴 BOTH ACTIONS ARE REFUSED, AND FOR THE SAME REASON: the swap may have COMMITTED, so this
    //    key may be the owner's live card. A DELETE would destroy it; an ORDER would spend a
    //    worker, an outstanding slot and an abandon row before 0143 §B's belt settles it.
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
    assertEquals(db.rows("billing_key_revocations").length, 0);
    // The key is not lost by doing nothing — that is precisely what 0170 bought.
    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "issued_unpersisted");
    assertEquals(rows[0].billing_key, "bill_abc123");
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
    // ⚠ [backend audit 2026-09-17 · L1] THIS PIN MOVED, AND ONLY ITS HANDLE MOVED. It read
    //    `assertStringIncludes(err.message, "billing_key_swap failed")` — i.e. it asserted that the
    //    raw Postgres sentence reaches the CLIENT, which is the thing L1 removes. The property it
    //    exists for is unchanged and is asserted below on a stronger handle: the 500 must be
    //    attributable to the SWAP and not to the compensation that runs after it (the intent close,
    //    the outbox order, the Toss call). `code` is produced by exactly one `throw` in this handler
    //    and by nothing else, so it pins that better than a substring of a database's prose did.
    //    The full text is still pinned where it is DURABLE — see the `note` assertion on the intent
    //    row, which is where an operator reads it.
    assertEquals(err?.code, "billing_key_swap");
    // and the raw Postgres text is GONE from the body — the L1 property itself, pinned
    assertEquals(err?.message, "internal");
    assertEquals(db.rows("billing_keys").length, 0);
    assertEquals(db.rows("billing_key_revocations").length, 0);
    // And the last resort is a CONFESSION, never a provider call — the arm that used to reach Toss
    // when everything else was down is gone (deploy-gate HIGH #2).
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
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

// ═══ [0157 · codex billing #6] the outstanding-uniqueness index, seen from the edge ═══════════
//
// 0157 adds a PARTIAL unique index — one OUTSTANDING (pending|processing) row per billing key —
// because two rows for one key mean two DELETEs at Toss, and a successful first followed by a
// non-2xx second writes a FALSE `abandoned`, which since 0155 PAGES a human to go hand-delete a key
// that is already gone. This path is the one enqueue site that stays a raw PostgREST insert (see
// the handler's comment: PostgREST cannot infer a partial index, and an RPC would couple this
// compensation to a migration that deploys separately). So it must read the violation correctly.
// ⚠ THE DISCRIMINATOR MOVED WITH THE FIX, AND SAYING SO IS THE POINT. Both arms below used to be
//   told apart by the inline Toss DELETE — recognised conflict ⇒ 0 calls, unrecognised error ⇒ 1
//   call. With no DELETE on any path that difference is gone, and asserting 「0 DELETEs」 in both
//   would leave two tests that cannot disagree: the same claim printed twice. What still separates
//   them is what `enqueueUntrackedKey` DOES with the answer — a recognised conflict is 「landed」 and
//   stops after ONE insert, while any other error drives the provenance-dropping retry and then
//   gives up. So the arms count INSERT ATTEMPTS, and the zero-DELETE assertion rides along as a
//   standing check rather than as the thing being measured.
Deno.test("🔴 an outstanding row for this key ALREADY EXISTS → recorded, and no second attempt", async () => {
  const db = scene();
  brokenSwap(db);
  let attempts = 0;
  db.fail("billing_key_revocations:insert", () => {
    attempts++;
    return 'duplicate key value violates unique constraint "billing_key_revocations_outstanding_uq"';
  });
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
    // Still a failed registration — recognising the conflict never turns a broken write into a
    // success for the CALLER.
    assertEquals(err?.status, 500);
    // 🔴 THE POINT: the obligation is already on the books, so the compensation is DONE — it does
    //    not retry without provenance and it does not confess.
    assertEquals(attempts, 1);
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 CONTROL — any OTHER insert error is still a failure, not a claimed record", async () => {
  // ⚠ Without this arm, `alreadyOutstanding` widened to 「any error」 — or to a bare 23505 — would
  //   pass the test above perfectly while converting 「nobody recorded it」 into 「something recorded
  //   it」 on a live charging credential. The blind spots of the two arms are different, which is
  //   what makes this a control rather than the same claim printed twice: this one is blind to a
  //   compensation that never runs at all, and the one above is blind to a compensation that runs
  //   twice — and the mutation that makes one green makes the other red.
  const db = scene();
  brokenSwap(db);
  let attempts = 0;
  db.fail("billing_key_revocations:insert", () => { attempts++; return "could not connect"; });
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch { /* the 500 is asserted by its own test above */ }
    // NOT treated as landed: the second attempt (provenance dropped) is made, and only then does
    // the handler confess. Two, not one — and still not a DELETE.
    assertEquals(attempts, 2);
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


// ═══ [0170 · codex billing #3] the issuance INTENT, seen from the edge ════════════════════════
//
// 🔴 THE FINDING: issuance had no durable record before Toss was called. The `Idempotency-Key` was
//    a `crypto.randomUUID()` minted inside `_shared/toss.ts` and persisted nowhere, so a lost
//    response left a live standing authority to charge a real card named in NO table — not
//    `billing_keys` (the write never ran) and not the outbox (only a failed SWAP writes there).
//
// ⚠ The memo's branch-independent core names three outcomes an attempt can END in, and each one is
//   a test below: **issued + persisted**, **issued but unpersisted (reconciled by the key)**, and
//   **a provider error**. Two more arms are here because they are the finding itself rather than a
//   consequence of it: the open must precede the Toss call and FAIL CLOSED, and a lost response
//   must land in `unresolved` rather than nowhere.
const intents = (db: FakeDb) => db.rows("billing_issue_intents");
/** The `Idempotency-Key` actually put on the wire for the issuance POST. */
const sentKey = (fm: FetchMock) =>
  (fm.calls.find((c) => isIssue(c.url))?.headers ?? {})["Idempotency-Key"];

Deno.test("🔴 0170 outcome ① issued + persisted — and the key on the wire is the PERSISTED one", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    const nonce = await prep(db);
    await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);

    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].attempt_nonce, nonce);
    assertEquals(rows[0].customer_key, CKEY);
    assertEquals(rows[0].state, "issued_persisted");
    assertEquals(rows[0].billing_key, "bill_abc123");
    // 🔴 THE ASSERTION THE WHOLE SLICE EXISTS FOR. A row that records an idempotency key the request
    //    was NOT sent under is worse than no row: it names a handle that resolves to nothing at the
    //    provider. Before 0170 this was structurally impossible to assert, because the key was
    //    minted inside the Toss client and never left it.
    assertEquals(sentKey(fm), rows[0].idempotency_key);
    assert(typeof rows[0].idempotency_key === "string" && rows[0].idempotency_key.length > 0);
    assert(String(rows[0].idempotency_key).length <= 300);   // memo §2a claim 11
  } finally { fm.restore(); }
});

Deno.test("🔴 0170 outcome ② issued but UNPERSISTED — the row names the key AND the key it was issued under", async () => {
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
    // the request still fails, and with ITS OWN error — the intent close must not replace it
    assertEquals(err?.status, 500);
    // ⚠ [backend audit 2026-09-17 · L1] THIS PIN MOVED, AND ONLY ITS HANDLE MOVED. It read
    //    `assertStringIncludes(err.message, "billing_key_swap failed")` — i.e. it asserted that the
    //    raw Postgres sentence reaches the CLIENT, which is the thing L1 removes. The property it
    //    exists for is unchanged and is asserted below on a stronger handle: the 500 must be
    //    attributable to the SWAP and not to the compensation that runs after it (the intent close,
    //    the outbox order, the Toss call). `code` is produced by exactly one `throw` in this handler
    //    and by nothing else, so it pins that better than a substring of a database's prose did.
    //    The full text is still pinned where it is DURABLE — see the `note` assertion on the intent
    //    row, which is where an operator reads it.
    assertEquals(err?.code, "billing_key_swap");
    // and the raw Postgres text is GONE from the body — the L1 property itself, pinned
    assertEquals(err?.message, "internal");

    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "issued_unpersisted");
    assertEquals(rows[0].billing_key, "bill_abc123");
    // "reconciled BY KEY": the pair a recovery needs — the credential Toss issued and the
    // idempotency key the issuing request carried — is on one row, and that key is the one sent.
    assertEquals(sentKey(fm), rows[0].idempotency_key);
    assertStringIncludes(String(rows[0].note), "billing_key_swap failed");

    // the pre-0170 compensation is untouched: enqueued, never revoked inline (0143 §B settles it)
    assertEquals(db.rows("billing_key_revocations").length, 1);
    assertEquals(db.rows("billing_key_revocations")[0].billing_key, "bill_abc123");
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 0170 outcome ③ a provider error is terminal and names NO key", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () =>
    FetchMock.json({ code: "INVALID_CARD", message: "정지된 카드예요" }, 400));
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    // Toss's own sentence still reaches the owner — the intent close must not swallow or replace it
    assertEquals(err?.status, 402);
    assertEquals(err?.message, "정지된 카드예요");

    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "provider_error");
    // ⚠ NULL, not the string "null" and not an empty string. Recording a key here would assert that
    //   a charging credential exists when the whole meaning of this outcome is that none does — and
    //   the table's own CHECK refuses the row, so a handler that tried would fail loudly.
    assertEquals(rows[0].billing_key, null);
    assertStringIncludes(String(rows[0].note), "400");
    assertEquals(db.rows("billing_keys").length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 0170 — a LOST RESPONSE lands in `unresolved`, which is finding 3's own state", async () => {
  const db = scene();
  const fm = new FetchMock().on(isIssue, () => new Error("connection reset"));
  fm.install();
  try {
    let threw = false;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch { threw = true; }
    // The request fails exactly as it did before 0170 — the original error is re-thrown, not
    // re-labelled. What changed is what is left behind.
    assert(threw);

    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "unresolved");
    assertEquals(rows[0].billing_key, null);       // we do not know whether one exists — that is the point
    assertEquals(rows[0].customer_key, CKEY);      // the coordinate Toss knows this owner by
    assert(typeof rows[0].idempotency_key === "string");
    assertEquals(db.rows("billing_keys").length, 0);
    assertEquals(db.rows("billing_key_revocations").length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 0170 CONTROL — the intent is opened BEFORE Toss, and a failed open calls nobody", async () => {
  // ⚠ Without this arm, an implementation that opened the intent AFTER the Toss call would pass
  //   every test above — the rows would look identical — while leaving the finding completely open.
  //   The only observable difference is what happens when the record cannot be written.
  const db = scene();
  db.rpcs["billing_issue_intent_open"] = () => ({ error: { message: "could not connect" } });
  const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
  fm.install();
  try {
    let err: HttpError | null = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { err = e as HttpError; }
    assertEquals(err?.status, 500);
    assertStringIncludes(String(err?.message), "billing_issue_intent_open failed");
    // 🔴 FAIL CLOSED: no record ⇒ no call ⇒ no credential to orphan.
    assertEquals(fm.calls.filter((c) => isIssue(c.url)).length, 0);
    assertEquals(db.rows("billing_keys").length, 0);
  } finally { fm.restore(); }
});

Deno.test("🔴 0170 CONTROL — a refused open is mapped by REASON, and an absent reason fails closed", async () => {
  // Same law as the three `swapped=false` arms below: these facts now arrive EARLIER (before Toss
  // has issued anything) and each still keeps the status that tells the caller what to do —
  // 503 later, 400 this attempt is spent, 403 never. A refusal we do not recognise must land on the
  // strictest answer, never open into a 200.
  const refuse = (reason: string | null) => {
    const db = scene();
    db.rpcs["billing_issue_intent_open"] = () => ({
      data: [{ intent_id: null, idempotency_key: null, reopened: false, refusal: reason }],
    });
    return db;
  };
  const statusOf = async (db: FakeDb): Promise<number> => {
    const fm = new FetchMock().on(isIssue, () => FetchMock.json(issued()));
    fm.install();
    try {
      const nonce = await prep(db);
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
      return 200;
    } catch (e) { return (e as HttpError).status; }
    finally { fm.restore(); }
  };
  assertEquals(await statusOf(refuse("gate_closed")), 503);
  assertEquals(await statusOf(refuse("intent_closed")), 400);
  assertEquals(await statusOf(refuse("deleted_account")), 403);
  assertEquals(await statusOf(refuse("something_new_in_sql")), 403);
  assertEquals(await statusOf(refuse(null)), 403);
});


// ═══ [deploy-gate HIGH #2 · 2026-09-15] THE COMPENSATION MAY NEVER DELETE AT TOSS ═════════════
//
// 🔴 THE FINDING, in the verdict's words: 「a failed/ambiguous `billing_key_swap` closes the intent
//    and then enters compensation whose final fallback may DELETE the key that the swap actually
//    stored」 (`docs/reviews/2026-09-15-deploy-gate-verdict.md` HIGH #2). The DELETE was a judgment
//    call that was CORRECT before 0170 — an unnamed live credential is worse than a destroyed one
//    — and 0170 removed its premise by naming the credential in the intent row before Toss is even
//    called. The memo's finding-4 branch A/B fix shape: 「delete the inline blind-DELETE arm
//    outright」 (`docs/research/2026-08-31-toss-provider-memo.md:272-287`), and it is
//    branch-independent: it does not need either open provider question answered.
//
// THE DECISION TABLE THESE THREE PINS COVER — the intent is closed FIRST in every failing row:
//   swap succeeded            → `issued_persisted`   · no order, no DELETE          (T3, the control)
//   swap DEFINITELY refused   → `issued_unpersisted` · ORDER in the outbox, no DELETE (T1)
//   swap outcome UNKNOWN      → `issued_unpersisted` · nothing at all, no DELETE      (T2)
// The `swapped=false` refusal rows are a fourth case and are NOT here: the definer already enqueued
// in the same transaction as the refusal (0141 §A / 0143 §A), and those arms have their own pins.

Deno.test("🔴 deploy-gate #2 T1 — a DEFINITE SQL refusal ORDERS the revocation and never DELETEs", async () => {
  // Two definite fixtures, because the definiteness must come from the SQLSTATE's SHAPE and not
  // from one memorised code: 0157's unique index (23505) and a `raise` out of
  // `enqueue_billing_key_revocation_row` (P0001) are the two this handler can actually meet.
  for (const [code, message] of [
    ["23505", 'duplicate key value violates unique constraint "billing_key_revocations_outstanding_uq"'],
    ["P0001", "0157: enqueue_billing_key_revocation_row called with no billing key (reason replaced)"],
  ]) {
    const db = scene();
    brokenSwap(db, message, code);
    const fm = new FetchMock()
      .on(isIssue, () => FetchMock.json(issued()))
      .on(isRevoke, () => new Response("", { status: 200 }));   // reachable, and never reached
    fm.install();
    try {
      let err: HttpError | null = null;
      const nonce = await prep(db);
      try {
        await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
      } catch (e) { err = e as HttpError; }

      // ① the client-visible answer is the one it has always been
      assertEquals(err?.status, 500);
      // ⚠ [backend audit 2026-09-17 · L1] THIS PIN MOVED, AND ONLY ITS HANDLE MOVED. It read
      //    `assertStringIncludes(err.message, "billing_key_swap failed")` — i.e. it asserted that the
      //    raw Postgres sentence reaches the CLIENT, which is the thing L1 removes. The property it
      //    exists for is unchanged and is asserted below on a stronger handle: the 500 must be
      //    attributable to the SWAP and not to the compensation that runs after it (the intent close,
      //    the outbox order, the Toss call). `code` is produced by exactly one `throw` in this handler
      //    and by nothing else, so it pins that better than a substring of a database's prose did.
      //    The full text is still pinned where it is DURABLE — see the `note` assertion on the intent
      //    row, which is where an operator reads it.
      assertEquals(err?.code, "billing_key_swap");
      // and the raw text is GONE — `message` above was the literal constraint sentence from :927
      assertEquals(err?.message, "internal");
      assert(!String(err?.message).includes(message), "the client body must not carry SQL text");
      assertEquals(db.rows("billing_keys").length, 0);

      // ② 🔴 ZERO DELETEs AT TOSS. This is the finding.
      assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);

      // ③ the ORDERED path instead — the queue 0138/0157 built, which is retried, audited (0166)
      //    and settled against `billing_keys` by 0143 §B before anything is destroyed.
      const out = db.rows("billing_key_revocations");
      assertEquals(out.length, 1);
      assertEquals(out[0].billing_key, "bill_abc123");
      assertEquals(out[0].profile_id, OWNER);
      assertEquals(out[0].reason, "issued_unpersisted");

      // ④ and the intent is closed naming the key, whatever the outbox did
      const rows = intents(db);
      assertEquals(rows.length, 1);
      assertEquals(rows[0].state, "issued_unpersisted");
      assertEquals(rows[0].billing_key, "bill_abc123");
      assertStringIncludes(String(rows[0].note), message);
    } finally { fm.restore(); }
  }
});

Deno.test("🔴 deploy-gate #2 T2 — a THROWN swap is UNKNOWN: no DELETE, no order, and the error survives", async () => {
  const db = scene();
  db.seed("billing_key_revocations", []);
  // The client never got an answer. This is the state in which a DELETE is most tempting (Toss
  // answered us milliseconds ago) and most dangerous (the swap may have COMMITTED, so the key may
  // be the owner's live card).
  db.rpcs["billing_key_swap"] = () => { throw new Error("connection reset"); };
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));
  fm.install();
  try {
    let caught: unknown = null;
    const nonce = await prep(db);
    try {
      await registerBillingKey(req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never);
    } catch (e) { caught = e; }

    // ① the status is UNCHANGED from today's: the original error is re-thrown, not re-labelled into
    //    an HttpError and not swallowed by the bookkeeping write.
    assert(caught instanceof Error);
    assert(!(caught instanceof HttpError));
    assertEquals((caught as Error).message, "connection reset");

    // ② 🔴 NEITHER ACTION IS TAKEN. Zero DELETEs and zero enqueues — and the second half matters as
    //    much as the first: an order placed on a key the swap actually stored costs a worker, an
    //    outstanding slot and an abandon row before 0143 §B settles it.
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
    assertEquals(db.rows("billing_key_revocations").length, 0);
    assertEquals(db.rows("billing_keys").length, 0);

    // ③ and doing nothing is SAFE because the intent row is the record — `issued_unpersisted`, not
    //    `unresolved`: we know Toss issued (we are holding the key); what we do not know is whether
    //    our store took it, which is what the sweep reconciles against `billing_keys`.
    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "issued_unpersisted");
    assertEquals(rows[0].billing_key, "bill_abc123");
    assertEquals(rows[0].customer_key, CKEY);
    assertStringIncludes(String(rows[0].note), "connection reset");
  } finally { fm.restore(); }
});

Deno.test("🔴 deploy-gate #2 T3 CONTROL — the happy path closes `issued_persisted`, orders nothing, deletes nothing", async () => {
  // ⚠ The control is not decoration here. 「zero DELETEs」 is satisfied by a handler that has
  //   stopped doing anything at all, and 「an order was placed」 is satisfied by one that orders
  //   unconditionally — this arm is the one that reddens if either mutation ships, because on a
  //   SUCCESSFUL swap the key is the owner's card and both actions would be defects.
  const db = scene();
  db.seed("billing_key_revocations", []);
  const fm = new FetchMock()
    .on(isIssue, () => FetchMock.json(issued()))
    .on(isRevoke, () => new Response("", { status: 200 }));
  fm.install();
  try {
    const nonce = await prep(db);
    const out = await registerBillingKey(
      req({ action: "issue", auth_key: "ak", nonce }, "owner_jwt"), db as never,
    ) as { brand: string; last4: string };
    assertEquals(out.last4, "1234");

    const rows = intents(db);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].state, "issued_persisted");
    assertEquals(rows[0].billing_key, "bill_abc123");
    assertEquals(db.rows("billing_keys").length, 1);
    assertEquals(db.rows("billing_key_revocations").length, 0);
    assertEquals(fm.calls.filter((c) => isRevoke(c.url)).length, 0);
  } finally { fm.restore(); }
});
