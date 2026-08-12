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

async function call(url: string, idempotencyKey: string, payload: unknown): Promise<TossResult> {
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
