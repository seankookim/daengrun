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
    return { customer_key: customerKey };
  }

  if (body.action === "issue") {
    const authKey = (body.auth_key ?? "").trim();
    if (!authKey) throw new HttpError(400, "auth_key_required");

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

    // UPSERT on the profile_id PK — 「한 번만, 그 뒤엔 설정에서 교체」(Sean). Replacing a card is
    // the same write as linking the first one; there is never a second row per owner, so the
    // charge core's `.maybeSingle()` read stays structurally single.
    const { error: wErr } = await db.from("billing_keys").upsert({
      profile_id: uid,
      billing_key: billingKey,
      card: { brand, last4: last4 || null },
      updated_at: new Date().toISOString(),
    });
    if (wErr) throw new HttpError(500, `billing_keys write failed: ${wErr.message}`);

    return { brand, last4: last4 || null };
  }

  throw new HttpError(400, "unknown action");
}
