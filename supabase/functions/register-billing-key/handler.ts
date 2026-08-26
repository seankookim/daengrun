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

export async function registerBillingKey(req: Request, db: SupabaseClient): Promise<unknown> {
  const uid = await caller(req, db);
  const body = (await req.json().catch(() => ({}))) as Body;

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
    if (wErr) throw new HttpError(500, `billing_key_swap failed: ${wErr.message}`);
    const swap = Array.isArray(swapRows) ? swapRows[0] : swapRows;

    if (!swap?.swapped) {
      // Deletion won the race. We hold a live billing key at Toss that now belongs to nobody —
      // say so rather than returning success, and record it so the revocation slice can find it.
      // The owner sees a refusal, which is the truthful outcome: their account is gone.
      console.error(
        `[register-billing-key] ORPHANED KEY — deletion won the race for profile ${uid}; ` +
          `a live Toss billing key exists with no owner and needs provider-side revocation`,
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
