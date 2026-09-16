// 빌링키 발급·저장 — the ONE write path into `billing_keys` (card-registration slice, Sean's
// 2026-08-26 placement ruling: once, at the last gate of the first booking; managed afterwards
// in 설정 › 결제 관리).
//
// WHY THIS FUNCTION EXISTS AT ALL: `billing_keys` has RLS enabled with ZERO policies, so
// `anon`/`authenticated` are deny-all by construction (their table grants are inert) and only
// `service_role` can write. That seal is correct — a billing key is the standing authority to
// charge with nobody watching (charge.ts's own words) — and this function is the door through
// it, the same shape as `set_my_phone` over the phone-column seal (0133).
//
// The flow, and where each secret lives:
//   ① client `prepare`  → we hand back the caller's `toss_customer_key` (0076 §B: minted at
//      profile creation precisely so the PG never learns our profile ids; create-payment-intent
//      already discloses it to its own caller, so this is not a new disclosure class).
//   ② client opens Toss's billing-auth page (client key only) → owner types the card INTO TOSS.
//      Card numbers never touch our client, our server, or our logs — we never see them.
//   ③ Toss redirects with a one-shot `authKey` → client `issue` → WE exchange it server-side
//      (secret key, _shared/toss.ts) for the billing key and store it with the card's masked
//      display fields. `my_billing_card` (the read RPC) shows brand+last4 and nothing else.
import { caller, HttpError, internalError } from "../_shared/ctx.ts";
import { tossBillingIssue } from "../_shared/toss.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

interface Body {
  action?: string;
  auth_key?: string;
  nonce?: string;
  customer_key?: string;
}

// 🔴 THE ATTEMPT NONCE — codex #3. The WebView intercept recognises Toss's callback by URL, and
// React Native WebView's default policy admits any http(s) navigation, so the callback URL is not
// an origin boundary: a page inside that WebView can navigate to our success/fail URL and forge
// either outcome. A nonce minted HERE, embedded in both callback URLs, and required back on
// `issue` means a forged navigation cannot produce an issuance — the attacker would have to
// already know a value that only this server and this session's Toss page hold.
//
// In-memory and per-isolate ON PURPOSE. It is a defence against a page in the user's OWN WebView,
// not against a network attacker, and its whole lifetime is one card-link attempt (a Toss page is
// open, a human is typing). A table would add a write path, a cleanup job, and a second thing to
// get wrong for a value that is worthless sixty seconds later. An isolate recycling mid-attempt
// costs the user one retry and refuses nothing that should have succeeded.
const NONCE_TTL_MS = 10 * 60 * 1000;
const nonces = new Map<string, { uid: string; at: number }>();

function mintNonce(uid: string): string {
  const now = Date.now();
  for (const [k, v] of nonces) if (now - v.at > NONCE_TTL_MS) nonces.delete(k);
  const n = crypto.randomUUID();
  nonces.set(n, { uid, at: now });
  return n;
}

/** Single-use: a nonce is consumed by the first `issue` that presents it, so a replayed forgery
 *  cannot ride a nonce the real flow already spent. */
function consumeNonce(n: string | undefined, uid: string): boolean {
  if (!n) return false;
  const hit = nonces.get(n);
  if (!hit) return false;
  nonces.delete(n);
  return hit.uid === uid && Date.now() - hit.at <= NONCE_TTL_MS;
}

/** 🔴 [0157 · codex billing #6] The outbox now carries a PARTIAL unique index —
 *  `billing_key_revocations_outstanding_uq`, one OUTSTANDING (pending|processing) row per billing
 *  key — because two rows for one key mean two DELETEs at Toss, and a successful first followed by
 *  a non-2xx second writes a FALSE `abandoned`, which since 0155 pages a human to go delete a key
 *  by hand that is already gone.
 *
 *  A violation of THAT index is not a failure to record: it says an obligation to destroy this key
 *  is already recorded, which is precisely what this function is trying to achieve. So it counts as
 *  landed.
 *
 *  ⚠ MATCHED BY INDEX NAME, NEVER BY SQLSTATE ALONE, and the direction of the failure is the
 *    reason. Treating a broad `23505` — or worse, any error — as success would convert 「nobody
 *    recorded it」 into 「something recorded it」 on a live charging credential: a false green on the
 *    one path whose entire job is durability. If PostgREST ever stops naming the constraint, this
 *    returns false and the caller falls back to the inline revoke exactly as it did before 0157 —
 *    the pre-existing behaviour, not a new hazard.
 *
 *  ⚠ THE SQL ENQUEUE SITES DO NOT COME THROUGH HERE. They call `enqueue_billing_key_revocation_row`
 *    (0157 §B.1), which MERGES provenance via `ON CONFLICT`. This path cannot: PostgREST emits
 *    `ON CONFLICT (col) DO UPDATE` with no index predicate and so cannot infer a partial index, and
 *    calling the definer by RPC would couple this compensation to a migration that deploys
 *    SEPARATELY from this function — in the window where the function is deployed and the migration
 *    is not, every enqueue here would fail and the obligation would degrade to a console line. A
 *    raw insert is safe in both deploy orders. The cost is that the second enqueue's REASON is not
 *    merged; the row already names the key, which is the only field the sweep needs.
 *    ⚠ That sentence used to end 「…would fail into `compensateUntrackedKey`'s inline Toss DELETE,
 *    which may destroy a key the swap actually stored」. The DELETE is gone (deploy-gate HIGH #2,
 *    2026-09-15 — see the block above `orderUntrackedKeyRevocation`); the deploy-order argument for
 *    a raw insert survives it, the consequence it named does not.
 */
const OUTSTANDING_UQ = "billing_key_revocations_outstanding_uq";
function alreadyOutstanding(error: { message?: string } | null): boolean {
  return String(error?.message ?? "").includes(OUTSTANDING_UQ);
}

/** One durable write into the revocation outbox. Returns whether a row actually landed.
 *
 *  ⚠ PROVENANCE IS DROPPED BEFORE THE KEY IS. `billing_key_revocations.profile_id` references
 *    `profiles(id)`, and the profile can be hard-deleted between this request's profile read and
 *    this insert — an FK violation would lose the BILLING KEY, which is the only field the sweep
 *    needs. 0141 §A makes exactly this trade inside the definer (「keeps the KEY while admitting
 *    we do not know whose it was」); this is its edge-side twin. The retry is unconditional rather
 *    than keyed on an error code: we do not need to know WHY the first insert failed to know that
 *    a row without provenance beats no row at all.
 *
 *  `last_error` carries the reason the key ended up here. The column exists for the worker's
 *  failure text and nothing branches on it, so seeding it costs nothing and is the only place
 *  this fact fits without a schema change — `reason` is the short domain token ('replaced',
 *  'account_deleted', 'orphaned_by_deletion'), and this is a fourth one.
 */
async function enqueueUntrackedKey(
  db: SupabaseClient, uid: string, billingKey: string, why: string,
): Promise<boolean> {
  const row = { billing_key: billingKey, reason: "issued_unpersisted", last_error: why.slice(0, 300) };
  for (const profile_id of [uid, null]) {
    try {
      const { error } = await db.from("billing_key_revocations").insert({ profile_id, ...row });
      if (!error) return true;
      if (alreadyOutstanding(error)) return true;
    } catch {
      // A THROWN client error is the same fact as a returned one — the row did not land. It is
      // swallowed only to reach the next escalation: this function's `false` is the failure, and
      // the caller acts on it. Nothing here can turn a failed registration into a success.
    }
  }
  return false;
}

/** 🔴 IS THIS SWAP FAILURE A **DEFINITE REFUSAL BY OUR OWN DATABASE**, OR MERELY AN OUTCOME WE DID
 *  NOT LEARN? Deploy-gate HIGH #2 (2026-09-15) turns on exactly this distinction, because only the
 *  first licenses touching the key at all.
 *
 *  `billing_key_swap` is ONE transaction. When Postgres itself answers with a SQLSTATE — 0157's
 *  `23505` on the outstanding-revocations index, a `P0001` raise out of
 *  `enqueue_billing_key_revocation_row`, a check violation — that transaction ABORTED: the
 *  `billing_keys` upsert did not commit, and neither did the definer's own in-transaction enqueue
 *  (0141 §A, 0143 §A). So the key is live at Toss, is certainly NOT ours, and no revocation was
 *  recorded for it. Ordering one is then a fact we are writing down, not a guess.
 *
 *  Everything else — a fetch that never answered, a gateway 5xx, a PostgREST-level code, a dropped
 *  connection — says only that WE did not learn the outcome. The swap may have COMMITTED, in which
 *  case that key is the owner's live card.
 *
 *  ⚠ THE AMBIGUOUS CLASSES ARE ENUMERATED AND THE DEFAULT IS 「UNKNOWN」, which is the direction the
 *    doubt runs: a connection/shutdown/internal error can arrive AFTER the COMMIT was sent, so its
 *    SQLSTATE is evidence about the CONNECTION rather than about the TRANSACTION. Anything that is
 *    not SQLSTATE-shaped at all (`''` from a thrown fetch, `PGRST…` from PostgREST) fails to
 *    UNKNOWN by construction rather than by remembering to list it.
 */
const AMBIGUOUS_SQLSTATE_CLASSES = new Set([
  "08",   // connection_exception — may have been raised after COMMIT was sent
  "53",   // insufficient_resources — including a disk/memory failure during commit
  "57",   // operator_intervention — query_canceled, admin_shutdown, crash_shutdown
  "58",   // system_error — external to Postgres itself
  "XX",   // internal_error / data_corrupted — the server's own state is in doubt
]);
function swapDefinitelyRefused(error: { code?: string } | null | undefined): boolean {
  const code = String(error?.code ?? "");
  if (!/^[0-9A-Z]{5}$/.test(code)) return false;
  return !AMBIGUOUS_SQLSTATE_CLASSES.has(code.slice(0, 2));
}

/** 🔴 THE ONLY ACTION THIS HANDLER MAY TAKE ON AN ISSUED-BUT-UNSTORED KEY: **ORDER** its revocation
 *  in the outbox. It may never DELETE at Toss, and that is the whole of deploy-gate HIGH #2.
 *
 *  ⚠ WHAT WAS HERE BEFORE, AND WHY IT IS GONE. This function used to try the outbox and then, when
 *    the outbox was unreachable, call `tossBillingRevoke` inline — a blind DELETE its own comment
 *    admitted 「may be destroying a key the swap actually stored」. That trade was correct exactly
 *    once: before 0170, a key we could not record was a credential named in NO table at all, and an
 *    unnamed live credential is worse than a destroyed one. **0170 ended that.** The intent row is
 *    written BEFORE Toss is called and is closed `issued_unpersisted` naming the billing key AND
 *    the idempotency key it was issued under, so the key is named whatever the outbox does. The
 *    rationale for the DELETE was the namelessness; the namelessness is gone, so the DELETE goes
 *    with it (memo §4 finding 4, branches A/B: 「delete the inline blind-DELETE arm outright」).
 *
 *  ⚠ THE OUTBOX IS ORDERED, RETRIED, AUDITED AND REPORTED, AND AN INLINE DELETE IS NONE OF THOSE.
 *    `claim_billing_key_revocations` (0143 §B) abandons any outstanding row whose key is currently
 *    in `billing_keys`, so the queue RESOLVES the question against the authoritative table before
 *    anything is destroyed; 0157 keeps at most one outstanding order per key; 0166 classifies an
 *    abandon and notifies. A DELETE from here bypasses every one of those.
 *
 *  Called ONLY on the definite-refusal branch (`swapDefinitelyRefused`). A failure to record is a
 *  confession, not a fallback — there is no longer anything to fall back to.
 */
async function orderUntrackedKeyRevocation(
  db: SupabaseClient, uid: string, customerKey: string, billingKey: string, why: string,
  intentId: string,
): Promise<void> {
  if (await enqueueUntrackedKey(db, uid, billingKey, why)) return;

  // 🔴 THE OUTBOX IS UNREACHABLE. This is a confession, NOT a record — 0138 already proved that a
  //    `console.error` about an orphaned key is read by nobody and reconciled by nothing, which is
  //    why 0141 §A moved that case into the outbox. It is here because the alternative is saying
  //    nothing at all — and since 0170 it is no longer the only thing left: the intent row closed
  //    just before this call names the key and the idempotency key, so the sweep has a coordinate
  //    even when this line is the only thing a human ever sees. The intent id is in the message for
  //    exactly that reason. The customer key is what a provider-side reconciliation must be keyed
  //    on; the billing key itself stays out of the log — a live charging credential in a log line
  //    is a second copy of it, and `tossBillingRevoke`'s own comment refuses that trade.
  console.error(
    `[register-billing-key] intent ${intentId} — UNTRACKED LIVE KEY, profile ${uid}, ` +
      `customer_key ${customerKey}: Toss issued a billing key, the swap definitively refused ` +
      `(${why}), and the revocation outbox is unreachable. Nothing was sent to Toss. The intent ` +
      `row names the key and the idempotency key it was issued under.`,
  );
}

/** 🔴 THE ISSUANCE INTENT — codex billing finding 3, and the Toss provider memo's
 *  branch-independent core (`docs/research/2026-08-31-toss-provider-memo.md` §4 core #1).
 *
 *  Before 0170 this handler called `tossBillingIssue` with everything before it a READ, under an
 *  `Idempotency-Key` minted inside `_shared/toss.ts` and persisted NOWHERE. If the response never
 *  came back, Toss could hold a live standing authority to charge a real card and we held no row
 *  naming it — not in `billing_keys` (the write never ran) and not in the outbox (only a FAILED
 *  swap writes there). The compensation (now `orderUntrackedKeyRevocation`) cannot help: it runs
 *  only when the response WAS received.
 *
 *  ⚠ **THIS IS THE SAME MOVE UNDER EVERY ANSWER TO THE TWO OPEN TOSS QUESTIONS** (memo §3), which
 *    is why it may be built while they are open: under 「replay works」 the row is what a recovery
 *    re-POST replays; under 「a lookup API exists」 it is what the lookup is keyed on; under
 *    「neither」 it IS the durable record, turning 「in no table at all」 into 「named by an
 *    `unresolved` intent」 with `customer_key` as the coordinate Toss knows this owner by. What is
 *    NOT built here is the recovery sweep's RESOLUTION arm — re-POST vs query vs escalate — because
 *    that is exactly the thing the review forbids designing around by guessing.
 *
 *  ⚠ **THE ATTEMPT NONCE IS STILL ISOLATE-LOCAL MEMORY AND THIS DOES NOT CHANGE THAT.** `consumeNonce`
 *    above runs FIRST and is still the belt; this row only uses the nonce's VALUE as the attempt's
 *    NAME, so the open edge-affinity question (`review:132-134`) is untouched and still open.
 */
async function openIssueIntent(
  db: SupabaseClient, uid: string, attemptNonce: string, customerKey: string,
): Promise<{ id: string; key: string }> {
  const { data, error } = await db.rpc("billing_issue_intent_open", {
    p_profile: uid,
    p_nonce: attemptNonce,
    p_customer_key: customerKey,
  });
  // 🔴 FAIL CLOSED. If we cannot write the record, we do not make the call — the whole point of the
  //    row is that it exists BEFORE a credential can. Nothing is issued, so nothing is orphaned.
  if (error) throw new HttpError(500, `billing_issue_intent_open failed: ${error.message}`);
  const row = (Array.isArray(data) ? data[0] : data) as
    { intent_id?: string; idempotency_key?: string; refusal?: string } | null;
  if (row?.intent_id && row?.idempotency_key) return { id: row.intent_id, key: row.idempotency_key };

  // ⚠ EACH REFUSAL MAPPED, AND AN ABSENT ONE FAILS CLOSED (CLAUDE.md §④). These are the same facts
  //   `billing_key_swap` reports, arriving EARLIER — before Toss has issued anything — so each one
  //   keeps the status the caller already knows: 503 says later, 400 says this attempt is spent,
  //   403 says never.
  const why = row?.refusal ?? "deleted_account";
  if (why === "gate_closed") throw new HttpError(503, "card_registration_not_live");
  // The attempt has already been resolved once. Reusing its key would re-send a request whose
  // outcome we have written down — and under the replay branch Toss would answer with that recorded
  // outcome, so the retry would look like a fresh success.
  if (why === "intent_closed") throw new HttpError(400, "stale_attempt");
  throw new HttpError(403, "no_profile");
}

/** Records the outcome and closes the intent. **NEVER THROWS, and that is a decision, not a
 *  swallow.** On the success path the card IS registered by the time this runs, so failing the
 *  request because the bookkeeping write failed would tell an owner their registration failed while
 *  their card charges; on every failure path the handler already has a truer error to throw and
 *  replacing it with this one would lose it. An intent left `issuing` is exactly the state the
 *  recovery sweep is built to reconcile against `billing_keys` — which it must do anyway, because a
 *  replayed 200 is 「what happened then」, never 「state now」 (memo §3 U3).
 */
async function closeIssueIntent(
  db: SupabaseClient, intentId: string, outcome: string, billingKey: string | null, note: string,
): Promise<void> {
  try {
    const { data, error } = await db.rpc("billing_issue_intent_close", {
      p_intent: intentId,
      p_outcome: outcome,
      p_billing_key: billingKey,
      p_note: note.slice(0, 500),
    });
    const row = (Array.isArray(data) ? data[0] : data) as { closed?: boolean; refusal?: string } | null;
    if (error || row?.closed !== true) {
      console.error(
        `[register-billing-key] intent ${intentId} NOT closed as ${outcome} ` +
          `(${error?.message ?? row?.refusal ?? "unknown"}) — it stays open for the recovery sweep`,
      );
    }
  } catch (e) {
    console.error(
      `[register-billing-key] intent ${intentId} close threw (${(e as Error).message}) — it stays open`,
    );
  }
}

export async function registerBillingKey(req: Request, db: SupabaseClient): Promise<unknown> {
  const uid = await caller(req, db);
  const body = (await req.json().catch(() => ({}))) as Body;

  // ── PARTY GATE, and it is FIRST — auth → party → state (codex deploy-gate #5, 2026-09-15).
  //    The tombstone refusal rides with it (0123 §5 / 0133 posture: a deleted account must not be
  //    able to re-attach a charging authority), and absent and tombstoned are the SAME answer
  //    (0137's argument unchanged).
  //    🔴 THIS BLOCK USED TO SIT BELOW THE FLAG READ, and moving it is the whole of the fix. With
  //    the flag first, a tombstoned or non-existent profile got `503 card_registration_not_live`
  //    while an ordinary owner got `403 no_profile` — so the 503 was a free read of **our rollout
  //    state**, handed to precisely the callers least entitled to it, and the divergence is
  //    visible only while the flag is CLOSED (with it open both orders answer 403, which is why
  //    the shipped tests could not see this). Same law 0170:193-199 states at the SQL door:
  //    「the rollout state is not a fact that account is entitled to learn, and 「deleted」 is the
  //    stronger refusal」. The handler now matches the RPC it calls instead of contradicting it.
  //    ⚠ It does not make the handler's read authoritative: a tombstone landing between this read
  //    and the issue call is caught by `billing_issue_intent_open`'s `for update` (0170:200).
  //    This gate is about what we DISCLOSE; that one is about what we DO.
  const { data: prof, error: pErr } = await db.from("profiles")
    .select("toss_customer_key, deleted_at").eq("id", uid).maybeSingle();
  if (pErr) throw new HttpError(500, `profile read failed: ${pErr.message}`);
  if (!prof || prof.deleted_at != null) throw new HttpError(403, "no_profile");
  const customerKey = prof.toss_customer_key as string;

  // ── STATE GATE — 🔴 THE SERVER-OWNED GATE (codex #7). The booking gate reads `TOSS_ENABLED`, a
  //    CLIENT constant, and the settings door reads whether a client key is configured — neither
  //    binds a modified client, and neither binds a build shipped with a test key. A protection
  //    that exists only in the client is a convention, not a protection. `card_registration_live()`
  //    (0138 §D) is the one that can refuse, and it is closed until Sean opens it: a NULL flag
  //    reads false, because defaulting a money-adjacent capability to ON because nobody set it
  //    is the 0116:425 fail-open with a different shape.
  //    Checked AFTER authentication AND after the party gate above, so neither an unauthenticated
  //    caller nor a tombstoned one learns anything about our rollout state — and still BEFORE
  //    prepare/issue, so neither a nonce nor a Toss call is spent.
  const { data: live, error: fErr } = await db.rpc("card_registration_live");
  if (fErr) throw new HttpError(500, `flag read failed: ${fErr.message}`);
  if (live !== true) throw new HttpError(503, "card_registration_not_live");

  if (body.action === "prepare") {
    return { customer_key: customerKey, nonce: mintNonce(uid) };
  }

  if (body.action === "issue") {
    const authKey = (body.auth_key ?? "").trim();
    if (!authKey) throw new HttpError(400, "auth_key_required");

    // The nonce proves this callback came from the flow WE started for THIS caller, not from a
    // page that guessed our callback URL. Checked before the Toss call so a forgery costs nothing.
    if (!consumeNonce(body.nonce, uid)) throw new HttpError(400, "stale_attempt");

    // Toss echoes the customerKey back on the callback. It must be the one WE issued: a callback
    // carrying someone else's customer key is either a forgery or a crossed session, and both are
    // refusals. (Issuance would very likely fail at Toss anyway — it binds authKey to customerKey
    // — but 「the vendor would probably reject it」 is not a gate we get to rely on.)
    if (body.customer_key != null && body.customer_key !== customerKey) {
      throw new HttpError(400, "customer_key_mismatch");
    }

    // 🔴 THE DURABLE RECORD, BEFORE THE PROVIDER CALL. Everything above this line is a read; from
    //    here on a live charging credential can exist, and from here on one cannot exist unnamed.
    const attemptNonce = body.nonce as string;      // non-empty: `consumeNonce` above accepted it
    const intent = await openIssueIntent(db, uid, attemptNonce, customerKey);

    let res: Awaited<ReturnType<typeof tossBillingIssue>>;
    try {
      res = await tossBillingIssue({ authKey, customerKey, idempotencyKey: intent.key });
    } catch (e) {
      // 🔴 THE FINDING'S OWN STATE. A throw is a timeout, a dead socket, an isolate that never got
      //    its answer — we do NOT know whether Toss executed. `unresolved` says exactly that, and
      //    the row names the idempotency key the request was sent under, which is the only handle
      //    any recovery (replay, lookup, or a support ticket keyed on `customer_key`) can use.
      //    The original error is re-thrown unchanged: this request fails exactly as it did before.
      await closeIssueIntent(db, intent.id, "unresolved", null, `no response from Toss: ${(e as Error).message}`);
      throw e;
    }

    if (!res.ok) {
      // PROVISIONAL (memo §3 U6) — closing on a provider refusal is terminal here because Toss's
      // English guide says error responses are REPLAYED for the key's 15-day window, so re-sending
      // this key can only return this same error. The Korean 멱등키 guide is silent and no
      // experiment has been run, so if U6 comes back negative this becomes a retryable state
      // rather than a terminal one — the state value would change, nothing else would.
      const code = (res.body?.code as string) ?? "";
      await closeIssueIntent(db, intent.id, "provider_error", null, `toss ${res.httpStatus} ${code}`.trim());
      // Toss's own message verbatim where present — the owner typed their card into Toss's page,
      // so Toss's sentence about it ("한도 초과", "정지된 카드") is the honest one; ours would be
      // a guess. A silent generic here is the funnel's most expensive dead end.
      const msg = (res.body?.message as string) ?? "카드사가 등록을 거절했어요";
      throw new HttpError(402, msg);
    }

    const billingKey = res.body?.billingKey as string | undefined;
    if (!billingKey) {
      // ⚠ `unresolved`, NOT `provider_error`. Toss answered 2xx, so it may well have issued a key —
      //   we simply cannot name it. `provider_error` would assert no credential exists, and the
      //   table refuses to record that outcome with no key precisely so this case cannot be
      //   mislabelled into it.
      await closeIssueIntent(db, intent.id, "unresolved", null, `toss ${res.httpStatus} 2xx with no billingKey`);
      throw new HttpError(502, "toss_no_billing_key");
    }

    // Display fields only. `card.number` from Toss is already masked (e.g. 433012******1234) —
    // we still store ONLY the last4, never the masked string: a jsonb that carries six real
    // digits is six more than the display needs, and `my_billing_card`'s contract is brand+last4.
    const rawCard = (res.body?.card ?? {}) as Record<string, unknown>;
    const masked = typeof rawCard.number === "string" ? rawCard.number : "";
    const last4 = masked.replace(/[^0-9*]/g, "").slice(-4);
    const brand = (res.body?.cardCompany as string) ?? (rawCard.issuerCode as string) ?? null;

    // 🔴 THE WRITE GOES THROUGH `billing_key_swap` (0137), NOT A DIRECT UPSERT — codex Critical
    //    #2. The eligibility check above happened BEFORE the Toss round trip; a direct upsert
    //    here would re-apply a decision made hundreds of milliseconds ago, and
    //    `delete_my_account_tx` can tombstone the profile inside that window. The definer locks
    //    the profile row and makes the check and the write one statement, so deletion and
    //    issuance can no longer interleave. A check-then-act across an external await cannot be
    //    fixed by ordering the two statements more carefully; it has to stop being two.
    type SwapRow = { swapped?: boolean; displaced_key?: string | null; refusal?: string | null };
    let swapRows: SwapRow | SwapRow[] | null = null;
    let wErr: { message?: string; code?: string } | null = null;
    try {
      const swapRes = await db.rpc("billing_key_swap", {
        p_profile: uid,
        p_billing_key: billingKey,
        p_card: { brand, last4: last4 || null },
      });
      swapRows = swapRes.data;
      wErr = swapRes.error;
    } catch (e) {
      // 🔴 A THROW IS THE PUREST UNKNOWN. The client never got an answer, so the swap may well have
      //    COMMITTED — this key may be the owner's live card. The intent is closed
      //    `issued_unpersisted` because we DO know Toss issued (we are holding the key); what we do
      //    not know is whether our store took it, and the sweep reconciles that against
      //    `billing_keys`. Nothing is ordered and nothing is sent to Toss. The original error is
      //    re-thrown unchanged: this request fails exactly as it did before.
      const msg = (e as Error).message;
      await closeIssueIntent(db, intent.id, "issued_unpersisted", billingKey, `billing_key_swap threw: ${msg}`);
      console.error(
        `[register-billing-key] intent ${intent.id} — billing_key_swap outcome UNKNOWN (threw: ` +
          `${msg}). No revocation ordered and nothing sent to Toss: the swap may have committed. ` +
          `The intent row names the key for the recovery sweep.`,
      );
      throw e;
    }
    if (wErr) {
      // 🔴 TOSS HAS ALREADY ISSUED A REAL, LIVE CHARGING CREDENTIAL BY THIS LINE. Throwing on its
      //    own left that key recorded NOWHERE — not in `billing_keys` (the write is what failed)
      //    and not in the outbox (only the swap writes there) — so a network blip, an RPC error or
      //    a timeout produced a standing authority to charge that we could neither see nor stop.
      //    Whatever is done here runs BEFORE the throw and cannot change the outcome: this request
      //    failed, and it still says so.
      //
      // ⚠ THE INTENT IS CLOSED FIRST, AND THE ORDER IS DELIBERATE — recording what we know before
      //   acting on it is the difference between an incident with a row and an incident without
      //   one. Since 0170 it is also what makes the branch below SAFE to be a no-op: the key is
      //   named whether or not anything else succeeds.
      //
      // 🔴 THEN, AND ONLY THEN, THE TWO OUTCOMES ARE TREATED DIFFERENTLY (deploy-gate HIGH #2):
      //    · DEFINITE refusal by our own SQL ⇒ the transaction aborted, the key is certainly not
      //      stored and certainly not yet enqueued ⇒ ORDER its revocation in the outbox.
      //    · UNKNOWN ⇒ do NOTHING further. Not a DELETE (it could destroy a stored card), and not
      //      an enqueue either: an order placed on a key the swap actually stored is settled by
      //      0143 §B's belt only after it has been claimed, and it spends a worker, an outstanding
      //      slot and an abandon row on a card that is working fine. The intent row already carries
      //      the key for the sweep and for ops, which is what 0170 bought.
      //    The client-visible status is the same 500 in both arms — the caller's registration
      //    failed, and which of our internals knows why is not their business.
      const why = `billing_key_swap failed: ${wErr.message}`;
      await closeIssueIntent(db, intent.id, "issued_unpersisted", billingKey, why);
      if (swapDefinitelyRefused(wErr)) {
        await orderUntrackedKeyRevocation(db, uid, customerKey, billingKey, why, intent.id);
      } else {
        console.error(
          `[register-billing-key] intent ${intent.id} — billing_key_swap outcome UNKNOWN ` +
            `(${wErr.code ? `sqlstate ${wErr.code}` : "no sqlstate"}: ${wErr.message}). No ` +
            `revocation ordered and nothing sent to Toss: the swap may have committed. The intent ` +
            `row names the key for the recovery sweep.`,
        );
      }
      // [backend audit 2026-09-17 · L1] `why` still carries the full SQL text everywhere it is
      // DURABLE — the intent close above (`:461`) and the outbox order (`:463`) — because that is
      // where an operator reads it. Only the client's copy is sanitised, which is exactly what the
      // paragraph above already promised: "which of our internals knows why is not their business".
      throw internalError(wErr, "billing_key_swap");
    }
    const swap = Array.isArray(swapRows) ? swapRows[0] : swapRows;

    if (!swap?.swapped) {
      // 🔴 [0143] `swapped=false` HAS THREE CAUSES NOW AND THEY ARE NOT THE SAME ANSWER. Until
      //    0143 the only way to be refused was a tombstoned account, so mapping this to
      //    `no_profile` was right every time. 0143 added two more — the rollout gate closing
      //    while we were awaiting Toss, and the key being actively revoked — and the old mapping
      //    would then tell an owner with a perfectly good account that they have no profile.
      //
      // ⚠ In ALL three cases the definer has already recorded what to revoke, in the same
      //   transaction as the refusal (0141 §A, 0143 §A). So this is diagnostics, NOT the record —
      //   the previous comment here said "record it so the revocation slice can find it", which
      //   described the code as it stood before 0141 and had quietly become false.
      const why = swap?.refusal ?? "deleted_account";
      // All three refusals share one physical fact: Toss issued a key and it is NOT in
      // `billing_keys`. The definer has already enqueued its revocation in the same transaction as
      // the refusal (0141 §A, 0143 §A), and this row is the other half — it names the key AND the
      // idempotency key it was issued under, which the outbox row does not carry.
      await closeIssueIntent(db, intent.id, "issued_unpersisted", billingKey, `swap refused: ${why}`);
      if (why === "gate_closed") {
        // Sean closed registration mid-flight. Retryable if he reopens it; the same 503 the
        // pre-Toss check uses, because it is the same fact arriving later.
        throw new HttpError(503, "card_registration_not_live");
      }
      if (why === "key_busy") {
        // A worker is revoking this exact key. Nothing is orphaned and nothing is lost — Toss
        // allows duplicate issuance, so retrying produces a usable key. 409, not 403: the caller
        // MAY retry, which `no_profile` actively denies.
        throw new HttpError(409, "billing_key_busy");
      }
      console.error(
        `[register-billing-key] intent ${intent.id} — refused for profile ${uid} (${why}); the ` +
          `displaced key is enqueued for provider-side revocation by the definer`,
      );
      throw new HttpError(403, "no_profile");
    }

    // The attempt is finished and nothing is owed: Toss issued and `billing_key_swap` stored it.
    await closeIssueIntent(db, intent.id, "issued_persisted", billingKey, "stored by billing_key_swap");

    if (swap.displaced_key) {
      // codex #4: replacing a card leaves the PREVIOUS key live at Toss. Narrowed here from
      // silent to VISIBLE; closing it needs a revocation outbox (its own slice — an outbound
      // call belongs neither in this request's critical path nor inside the lock).
      console.warn(
        `[register-billing-key] displaced a previous billing key for profile ${uid} — ` +
          `it remains live at the PG until the revocation slice lands`,
      );
    }

    return { brand, last4: last4 || null };
  }

  throw new HttpError(400, "unknown action");
}
