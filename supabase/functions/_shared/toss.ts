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

async function call(
  url: string,
  idempotencyKey: string | null,
  payload: unknown,
  timeoutMs?: number,
  // ⚠ METHOD IS A PARAMETER, and it defaults to POST so every existing caller is unchanged.
  //   It exists because `DELETE /v1/billing/{key}` and `POST /v1/billing/{key}` are the SAME URL
  //   with opposite meanings — delete the key, or charge the card. A helper that hardcodes the
  //   verb turns a one-character URL fix into a request against a live money endpoint.
  method: "POST" | "DELETE" = "POST",
): Promise<TossResult> {
  const headers: Record<string, string> = { "Authorization": authHeader() };
  if (payload !== undefined) headers["Content-Type"] = "application/json";
  // Toss dedupes on this header. Our order_id is server-minted and unique per intent
  // (0071's order_id unique index), so a retried confirm can never become a second charge
  // even if our own idempotency check somehow misses.
  // ⚠ POST only — Toss documents the idempotency header as POST-only and guarantees other
  //   methods are idempotent themselves. Sending it on DELETE is at best noise.
  if (idempotencyKey !== null) headers["Idempotency-Key"] = idempotencyKey;
  const res = await fetch(url, {
    method,
    headers,
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
    ...(timeoutMs ? { signal: AbortSignal.timeout(timeoutMs) } : {}),
  });
  let body: Record<string, unknown> = {};
  try {
    body = await res.json();
  } catch {
    // A non-JSON body from a money endpoint is itself the evidence — keep it rather than
    // pretending the response was empty.
    // ⚠ For DELETE this is the DOCUMENTED SUCCESS shape: 「비어있는 body에 200 응답만
    //   내려갑니다」. So `parse_error` here is not necessarily a fault — callers must judge on
    //   `ok`/`httpStatus`, never on the body being parseable.
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

// 빌링키 폐기 — 교체·탈퇴로 주인을 잃은 키를 PG 쪽에서 없앤다 (0138 아웃박스가 부른다).
// 토스는 미사용 빌링키의 삭제를 제공하고, 중복 발급 자체는 허용한다 — 그래서 「교체했으니
// 옛 키는 알아서 죽는다」는 성립하지 않고, 지우지 않으면 살아 있는 채로 남는다.
// 멱등 키는 빌링키에서 파생한다: 같은 키에 대한 재시도는 같은 요청이므로 같은 키를 쓰는 것이
// 옳고, 빌링키 자체를 헤더에 복사하지는 않는다 (자격증명 사본을 한 곳 더 만들지 않는다).
export function tossBillingRevoke(billingKey: string): Promise<TossResult> {
  // 🔴 이 함수의 첫 버전은 **존재하지 않는 엔드포인트**를 불렀다: `POST /v1/billing/{key}/delete`.
  //    토스 문서에 `/delete` 경로 조각은 없다 — 빌링 엔드포인트는 정확히 넷이고, 삭제는
  //    `DELETE /v1/billing/{billingKey}` 다 (docs.tosspayments.com/reference, 원문 HTML 확인).
  //
  // 🔴 그리고 그 버그는 **스스로를 숨겼다.** 없는 라우트에 POST 하면 토스는 404
  //    (`NOT_FOUND_HTTP_METHOD`) 를 준다. 워커는 404 를 「이미 지워짐 = 성공」으로 읽었으므로
  //    아웃박스는 100% 깨끗하게 비워지고, 모든 행이 `done` 이 되고, **단 하나의 빌링키도 실제로
  //    삭제되지 않는다.** 성공 탐지기가 실패 상태와 정확히 일치했다 — 푸시 탐지기·codex 판정문
  //    법과 같은 모양이고, 이번엔 살아 있는 결제 자격증명에 걸렸다.
  //
  // ⚠ URL 만 고치면 더 나빠진다. 아래 `call()` 은 method 를 POST 로 **하드코딩**한다. `/delete`
  //   만 떼면 요청은 `POST /v1/billing/{billingKey}` 가 되는데 그건 **결제(청구) 엔드포인트**다.
  //   amount/orderId/customerKey 가 없어 실패하겠지만, 살아 있는 머니 경로에 의도치 않은 요청을
  //   보내는 것 자체가 배포되어선 안 된다. 그래서 method 를 파라미터로 올린다.
  //
  // ⚠ 멱등키를 보내지 않는다. 토스 문서: 멱등키 헤더는 **POST 전용**이고 그 외 메서드는 자체적으로
  //   멱등성을 보장한다. 게다가 이전 값 `revoke_${'${billingKey.slice(-12)}'}` 는 자격증명 12자를
  //   헤더에 복사했다 — 바로 위 주석이 하지 않겠다고 적어 둔 그 일이다.
  return call(
    `${TOSS_BASE}/billing/${encodeURIComponent(billingKey)}`,
    null,                 // no Idempotency-Key on DELETE
    undefined,            // no body — the spec documents none
    BILLING_TIMEOUT_MS,
    "DELETE",
  );
}

// The already-processed arm's evidence source (§0-ter #8). When Toss refuses a charge because the
// order was already processed, "refused" is the wrong reading: the money may well have moved on an
// earlier attempt. We ask Toss what the order actually is before writing anything down.
//
// No Idempotency-Key: this is a read, and reusing the charge's key on a different endpoint is the
// mistake `tossCancel`'s comment already names.
// 빌링키 발급 — the authKey→billingKey exchange (register-billing-key's ③). The authKey is
// ONE-SHOT and expires in minutes, so there is no replay window to manage and no Idempotency-Key
// semantics to reason about — Toss refuses a spent key on its own. It still goes through call()
// (which requires a key) with the authKey itself: unique per attempt by construction.
// BILLING_TIMEOUT_MS applies — unlike confirm, the human is watching a spinner WE drew, not
// Toss's page, so a hung socket must resolve into a visible failure rather than pin the isolate.
export function tossBillingIssue(p: { authKey: string; customerKey: string }): Promise<TossResult> {
  // ⚠ The idempotency key is a DERIVED value, not the authKey itself (codex #3 tail). The authKey
  // is a bearer credential for this one issuance; copying it into a second header multiplies the
  // places it can be logged, mirrored by a proxy, or land in an error report — for no benefit,
  // because issuance has no replay semantics to protect (a spent authKey is refused by Toss on
  // its own). A per-attempt uuid gives the header a unique value without a second copy of the
  // secret. It is still unique per call, which is all `call()` needs.
  return call(`${TOSS_BASE}/billing/authorizations/issue`, crypto.randomUUID(), {
    authKey: p.authKey,
    customerKey: p.customerKey,
  }, BILLING_TIMEOUT_MS);
}

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
