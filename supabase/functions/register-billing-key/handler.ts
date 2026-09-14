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
import { caller, HttpError } from "../_shared/ctx.ts";
import { tossBillingIssue, tossBillingRevoke } from "../_shared/toss.ts";
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
 *    is not, every compensation would fail into `compensateUntrackedKey`'s inline Toss DELETE,
 *    which may destroy a key the swap actually stored. A raw insert is safe in both deploy orders.
 *    The cost is that the second enqueue's REASON is not merged; the row already names the key,
 *    which is the only field the sweep needs.
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

/** Compensation for a key Toss issued and we could not persist.
 *
 *  ⚠ THE ORDER IS DELIBERATE AND IT IS NOT 「revoke first」. When the swap fails with a TIMEOUT we
 *    do not know whether it committed — the key may already BE somebody's live card — and a blind
 *    DELETE at Toss would destroy it, leaving a `billing_keys` row pointing at nothing and a
 *    decline weeks later with nothing in our data to explain it. The outbox does not have that
 *    problem: `claim_billing_key_revocations` (0143 §B) abandons any row whose key is currently in
 *    `billing_keys`, so ENQUEUEING RESOLVES THE AMBIGUITY against the authoritative table while an
 *    inline DELETE can only guess. Enqueue first; revoke inline only when we cannot enqueue.
 */
async function compensateUntrackedKey(
  db: SupabaseClient, uid: string, customerKey: string, billingKey: string, why: string,
): Promise<void> {
  if (await enqueueUntrackedKey(db, uid, billingKey, why)) return;

  // Our durable store is unreachable and Toss answered us milliseconds ago, so the provider is the
  // one party still likely to be reachable — discharge the obligation there instead of recording
  // it. ⚠ This arm may be destroying a key the swap actually stored; we cannot tell, because the
  // store that would tell us is the one that is down. We take that over a live credential nobody
  // can find: the owner is being told registration FAILED, so a key that still charges contradicts
  // what we told them, while a key that does not is the retry they already expect.
  let revokeErr = "";
  try {
    const res = await tossBillingRevoke(billingKey);
    if (res.ok) return;
    revokeErr = `toss ${res.httpStatus}`;
  } catch (e) {
    revokeErr = `unreachable: ${(e as Error).message}`;
  }

  // One more try at the record: the revoke just spent up to BILLING_TIMEOUT_MS, which is plenty of
  // time for a transient PostgREST failure to clear, and a row is worth more than a log line.
  if (await enqueueUntrackedKey(db, uid, billingKey, `${why}; revoke failed (${revokeErr})`)) return;

  // 🔴 EVERY DURABLE OPTION IS EXHAUSTED. This is a confession, NOT a record — 0138 already proved
  //    that a `console.error` about an orphaned key is read by nobody and reconciled by nothing,
  //    which is why 0141 §A moved that case into the outbox. It is here because the alternative is
  //    saying nothing at all. The customer key is the coordinate Toss knows this owner by and is
  //    what a provider-side reconciliation must be keyed on; the billing key itself stays out of
  //    the log — a live charging credential in a log line is a second copy of it, and
  //    `tossBillingRevoke`'s own comment already refuses that trade for a smaller benefit.
  console.error(
    `[register-billing-key] UNTRACKED LIVE KEY — profile ${uid}, customer_key ${customerKey}: ` +
      `Toss issued a billing key, the swap failed (${why}), revocation failed (${revokeErr}), and ` +
      `the outbox is unreachable. A live charging credential exists that nothing in our data names.`,
  );
}

export async function registerBillingKey(req: Request, db: SupabaseClient): Promise<unknown> {
  const uid = await caller(req, db);
  const body = (await req.json().catch(() => ({}))) as Body;

  // 🔴 THE SERVER-OWNED GATE (codex #7). The booking gate reads `TOSS_ENABLED`, a CLIENT
  //    constant, and the settings door reads whether a client key is configured — neither binds
  //    a modified client, and neither binds a build shipped with a test key. A protection that
  //    exists only in the client is a convention, not a protection. `card_registration_live()`
  //    (0138 §D) is the one that can refuse, and it is closed until Sean opens it: a NULL flag
  //    reads false, because defaulting a money-adjacent capability to ON because nobody set it
  //    is the 0116:425 fail-open with a different shape.
  //    Checked AFTER authentication so an unauthenticated caller still learns nothing about our
  //    rollout state, and BEFORE prepare/issue so neither a nonce nor a Toss call is spent.
  const { data: live, error: fErr } = await db.rpc("card_registration_live");
  if (fErr) throw new HttpError(500, `flag read failed: ${fErr.message}`);
  if (live !== true) throw new HttpError(503, "card_registration_not_live");

  // Party gate before anything else, and the tombstone refusal with it (0123 §5 / 0133 posture:
  // a deleted account must not be able to re-attach a charging authority).
  const { data: prof, error: pErr } = await db.from("profiles")
    .select("toss_customer_key, deleted_at").eq("id", uid).maybeSingle();
  if (pErr) throw new HttpError(500, `profile read failed: ${pErr.message}`);
  if (!prof || prof.deleted_at != null) throw new HttpError(403, "no_profile");
  const customerKey = prof.toss_customer_key as string;

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

    const res = await tossBillingIssue({ authKey, customerKey });
    if (!res.ok) {
      // Toss's own message verbatim where present — the owner typed their card into Toss's page,
      // so Toss's sentence about it ("한도 초과", "정지된 카드") is the honest one; ours would be
      // a guess. A silent generic here is the funnel's most expensive dead end.
      const msg = (res.body?.message as string) ?? "카드사가 등록을 거절했어요";
      throw new HttpError(402, msg);
    }

    const billingKey = res.body?.billingKey as string | undefined;
    if (!billingKey) throw new HttpError(502, "toss_no_billing_key");

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
    const { data: swapRows, error: wErr } = await db
      .rpc("billing_key_swap", {
        p_profile: uid,
        p_billing_key: billingKey,
        p_card: { brand, last4: last4 || null },
      });
    if (wErr) {
      // 🔴 TOSS HAS ALREADY ISSUED A REAL, LIVE CHARGING CREDENTIAL BY THIS LINE. Throwing on its
      //    own left that key recorded NOWHERE — not in `billing_keys` (the write is what failed)
      //    and not in the outbox (only the swap writes there) — so a network blip, an RPC error or
      //    a timeout produced a standing authority to charge that we could neither see nor stop.
      //    The compensation runs BEFORE the throw and cannot change the outcome: this request
      //    failed, and it still says so.
      await compensateUntrackedKey(db, uid, customerKey, billingKey, `billing_key_swap failed: ${wErr.message}`);
      throw new HttpError(500, `billing_key_swap failed: ${wErr.message}`);
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
        `[register-billing-key] refused for profile ${uid} (${why}); the displaced key is ` +
          `enqueued for provider-side revocation by the definer`,
      );
      throw new HttpError(403, "no_profile");
    }

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
