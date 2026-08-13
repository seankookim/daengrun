// 토스페이먼츠 REST 클라이언트 — the ONLY place the secret key is read (toss-plan §2-3).
//
// Two calls live here, both money paths: confirm (capture) and cancel (release). The refund
// slice (§5-4) reuses `tossCancel` rather than writing a second cancel call — that is why this
// is `_shared` and not a file inside `confirm-payment/`.
//
// Neither function throws on an HTTP error: the caller must be able to tell "Toss refused"
// (nothing captured) apart from "we could not reach Toss" (unknown), and those two need
// opposite handling after capture. A thrown Error means the request never completed.
import { HttpError } from "./ctx.ts";

export const TOSS_BASE = "https://api.tosspayments.com/v1";

export interface TossResult {
  ok: boolean;
  httpStatus: number;
  body: Record<string, unknown>;
}

// Basic auth = base64(secretKey + ":") — Toss's documented scheme (the password half is empty).
// The key is read per call, never cached in module scope: a module-level read would freeze a
// stale value across a secret rotation for the life of the isolate.
function authHeader(): string {
  const key = Deno.env.get("TOSS_SECRET_KEY");
  // No key = we are not a payments company yet. Say that instead of sending an unauthenticated
  // request to a live money endpoint and interpreting its 401 as a payment failure.
  if (!key) throw new HttpError(503, "결제 준비가 아직 끝나지 않았어요 — 잠시 후 다시 시도해주세요");
  return `Basic ${btoa(`${key}:`)}`;
}

// The unattended paths' ceiling. NOT applied to confirm/cancel: those run while a human waits on
// the payment screen and their timing is pinned by 0076's tests — a widget confirm that we abandon
// at 10s while Toss captures anyway is the worst possible trade. The billing pair is the opposite
// case: nobody is watching, an abandoned request lands in the `unresolved` arm (dispatched pending
// → reconciliation, same order_id, no double charge), and a socket that hangs forever pins an
// isolate and stalls the whole batch behind it.
const BILLING_TIMEOUT_MS = 10_000;

async function call(url: string, idempotencyKey: string, payload: unknown, timeoutMs?: number): Promise<TossResult> {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": authHeader(),
      "Content-Type": "application/json",
      // Toss dedupes on this header. Our order_id is server-minted and unique per intent
      // (0071's order_id unique index), so a retried confirm can never become a second charge
      // even if our own idempotency check somehow misses.
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify(payload),
    ...(timeoutMs ? { signal: AbortSignal.timeout(timeoutMs) } : {}),
  });
  let body: Record<string, unknown> = {};
  try {
    body = await res.json();
  } catch {
    // A non-JSON body from a money endpoint is itself the evidence — keep it rather than
    // pretending the response was empty.
    body = { parse_error: true };
  }
  return { ok: res.ok, httpStatus: res.status, body };
}

// 승인 — 이 호출이 2xx로 돌아오면 **돈은 이미 움직였다**. 그 뒤의 모든 실패는 보상해야 한다.
export function tossConfirm(p: { paymentKey: string; orderId: string; amount: number }): Promise<TossResult> {
  return call(`${TOSS_BASE}/payments/confirm`, p.orderId, {
    paymentKey: p.paymentKey,
    orderId: p.orderId,
    // 금액은 항상 우리 인텐트 행에서 온다 — 호출자가 클라 본문을 넘기지 못하도록 타입이 number다.
    amount: p.amount,
  });
}

// 취소 — cancelAmount를 싣지 않으면 전액 취소가 Toss의 계약이다. 부분 취소는 이 슬라이스에
// 존재하지 않는다(§5-4). 멱등 키를 confirm과 다르게 두는 이유: 같은 키로 다른 엔드포인트를
// 때리면 Toss가 앞선 confirm 응답을 그대로 되돌려줄 수 있고, 그러면 취소가 '성공'해 보인다.
export function tossCancel(paymentKey: string, p: { orderId: string; reason: string }): Promise<TossResult> {
  return call(`${TOSS_BASE}/payments/${encodeURIComponent(paymentKey)}/cancel`, `cancel_${p.orderId}`, {
    cancelReason: p.reason,
  });
}

// ── 자동결제(빌링) — the post-pay slice (toss-plan §0-ter) ─────────────────────────────────
// The billing charge: no widget, no owner present, no client input. The card was verified once
// at link time and the key stands in for it from then on, so this is the only call in the file
// that can move money with nobody watching. Everything it sends comes from our own rows.
//
// ⚠ The Idempotency-Key is a PARAMETER here, unlike `tossConfirm` where it is the orderId. That
// is not an inconsistency — see `_shared/charge.ts`, which owns the reasoning: Toss retains a key
// for 15 days and REPLAYS the first response for it, so re-sending the +1h and +24h rungs under
// one key would replay the original decline and make the ladder a silent no-op. The caller mints
// a per-attempt key; double-charge safety comes from the constant orderId instead.
export function tossBillingCharge(
  billingKey: string,
  p: { customerKey: string; orderId: string; amount: number; orderName: string; idempotencyKey: string },
): Promise<TossResult> {
  return call(`${TOSS_BASE}/billing/${encodeURIComponent(billingKey)}`, p.idempotencyKey, {
    customerKey: p.customerKey,
    // Our row's number. There is no request body anywhere in the post-pay path — the owner is
    // not even in the loop — so an amount dispute is impossible by construction.
    amount: p.amount,
    orderId: p.orderId,
    orderName: p.orderName,
    // A timeout here throws, and a throw is already the honest arm in `charge.ts`: the row stays a
    // dispatched pending ("we do not know"), never a decline.
  }, BILLING_TIMEOUT_MS);
}

// The already-processed arm's evidence source (§0-ter #8). When Toss refuses a charge because the
// order was already processed, "refused" is the wrong reading: the money may well have moved on an
// earlier attempt. We ask Toss what the order actually is before writing anything down.
//
// No Idempotency-Key: this is a read, and reusing the charge's key on a different endpoint is the
// mistake `tossCancel`'s comment already names.
export async function tossGetByOrderId(orderId: string): Promise<TossResult> {
  const res = await fetch(`${TOSS_BASE}/payments/orders/${encodeURIComponent(orderId)}`, {
    method: "GET",
    headers: { "Authorization": authHeader() },
    // Same ceiling as the charge it resolves — this read runs unattended too (the already-processed
    // arm and collect-charges' verification sweep), and a hung read there stalls a batch.
    signal: AbortSignal.timeout(BILLING_TIMEOUT_MS),
  });
  // Parsed the same way `call` parses, and deliberately not refactored into a shared helper:
  // `call` is on the capture path and stays byte-identical to what 0076's tests pinned.
  let body: Record<string, unknown> = {};
  try {
    body = await res.json();
  } catch {
    body = { parse_error: true };
  }
  return { ok: res.ok, httpStatus: res.status, body };
}
