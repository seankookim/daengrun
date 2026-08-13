// 결제 승인 — 우리 인텐트를 **완성**하고, 실패하면 같은 요청 안에서 돈을 되돌린다.
// (toss-plan §2 steps 1-6 + §2-5b + §2-7. 계획이 잠긴 뒤 그대로 구현한 파일이다.)
//
// input:  { order_id, payment_key, meta?: { preferred_runner_id?, recurring? } }
//         (Toss 위젯이 돌려주는 camelCase orderId/paymentKey도 받는다 — 클라가 그 이름을 그대로
//          들고 오는 것이 가장 흔한 실수 경로이고, 여기서 400을 주면 캡처 직전에 막히는 게 아니라
//          위젯이 이미 승인해둔 결제가 고아가 된다.)
// output: { ok, booking_id, order_id, amount, post: { recurring, nomination } }
//
// ═══ 이 함수가 지키는 순서 (계획 §2, 바꾸지 말 것) ═══
//  1. caller() — 익명은 401
//  2. order_id로 인텐트 조회 → 그 부킹으로 파티 게이트 (상태 게이트보다 **먼저**)
//  3. 멱등 확인을 **그 다음, Toss보다 먼저** — 이미 confirmed면 무동작 성공. 두 번째 청구 금지
//  4. Toss 승인 (서버 시크릿). 클라의 말은 증거가 아니다 — 금액은 우리 인텐트 행에서만 온다
//  5. 금액 일치 && status === 'DONE' 검증
//  6. 인텐트 행 → confirmed (payment_key + raw 기록). 부킹보다 **먼저** — 돈의 지역 흔적이
//     언제나 전이보다 앞서야 한다
//  7. bookings CAS payment_hold → matching (transition-booking:42-46과 같은 문장)
//  8. 캡처 이후의 어떤 실패든 → §2-7 자동 취소 기계
//  9. CAS 성공 뒤에만 §2-5b 후처리 (반복·지명) — **비치명적**
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, HttpError } from "../_shared/ctx.ts";
import { tossCancel, tossConfirm } from "../_shared/toss.ts";

// 0077 호출자 독트린: 소유자 게이트를 가진 클라이언트 RPC(create_recurring_series)는
// service_role이 아니라 **호출자의 JWT로** 호출한다 — RPC의 not_signed_in/is-distinct
// 게이트가 실제로 발화하도록. (0077_recurring_guard.sql 헤더가 이 법의 정본.)
export function callerBoundClient(req: Request): SupabaseClient {
  const authz = req.headers.get("Authorization");
  if (!authz) throw new HttpError(401, "no caller token"); // caller()가 먼저 401을 냈어야 정상
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authz } } },
  );
}

// 계획 §2-7이 지정한 문장 그대로. 만료와 자동취소를 한 문장에 담는 이유: 보호자가 알아야 할
// 사실이 둘이고(예약이 죽었다 / 돈은 돌아온다), 둘 중 하나만 말하면 나머지는 상상하게 된다.
const HONEST_AUTOCANCELED =
  "결제 시간이 만료됐어요 — 결제는 자동 취소됐어요. 예약을 다시 만들어주세요";

// ⚠ 자동 취소마저 실패했을 때는 **위 문장을 쓰지 않는다.** 취소되지 않은 결제를 "자동 취소됐어요"
// 라고 말하는 것은 정직법 위반이고, 그 거짓말은 하필 돈이 걸린 화면에서 발생한다. 사실만 말한다:
// 아직 취소되지 않았다, 사람이 보고 있다, 그리고 문의할 수 있도록 주문번호를 준다.
const honestNeedsManual = (orderId: string) =>
  `결제 시간이 만료됐어요 — 결제 취소가 자동으로 처리되지 않아 담당자가 확인 중이에요. 확인 후 환불해드릴게요 (주문번호 ${orderId})`;

interface Intent {
  id: string;
  booking_id: string;
  order_id: string;
  amount: number;
  status: string;
  payment_key: string | null;
  raw: Record<string, unknown> | null;
}

// 후불(빌링키) 인텐트의 표식 — `raw.kind`('settle_charge' | 'cancel_fee'). 위젯 인텐트에는 없다.
// (toss-plan §0-ter. 정본은 _shared/charge.ts의 헤더.)
const NOT_A_WIDGET_ORDER =
  "이 주문은 위젯 결제 대상이 아니에요 — 결제 내역에서 확인해주세요";

export async function confirmPayment(
  req: Request,
  db: SupabaseClient,
  mkUserDb: (req: Request) => SupabaseClient = callerBoundClient,
) {
  // ── 1. 호출자 (익명 401) ──────────────────────────────────────────────────────────────
  const uid = await caller(req, db);
  const body = await req.json();
  const orderId: string | undefined = body.order_id ?? body.orderId;
  const paymentKey: string | undefined = body.payment_key ?? body.paymentKey;
  const meta = body.meta ?? {};
  if (!orderId || !paymentKey) throw new HttpError(400, "missing fields");
  // 본문의 amount는 **읽지 않는다.** 클라의 말은 증거가 아니다 (payments.md 클라 금액 불신 원칙).

  // ── 2. 인텐트 조회 + 파티 게이트 (상태 게이트보다 먼저) ────────────────────────────────
  const { data: intentRow, error: iErr } = await db.from("payments")
    .select("id, booking_id, order_id, amount, status, payment_key, raw")
    .eq("order_id", orderId).maybeSingle();
  if (iErr) throw new HttpError(500, iErr.message);
  // 인텐트가 없으면 이 confirm은 우리가 만든 주문이 아니다. 승인하지 않는다 — 승인하면
  // 이 함수가 '아무 주문번호나 돈으로 바꿔주는' 엔드포인트가 된다.
  if (!intentRow) throw new HttpError(404, "결제 정보를 찾을 수 없어요 — 결제를 다시 시작해주세요");
  const intent = intentRow as Intent;

  const { data: bk, error: bErr } = await db.from("bookings")
    .select("id, owner_id, status, total_price").eq("id", intent.booking_id).maybeSingle();
  if (bErr) throw new HttpError(500, bErr.message);
  if (!bk) throw new HttpError(404, "booking not found");
  if (bk.owner_id !== uid) throw new HttpError(403, "owner only");

  // ── 2-bis. 이 주문은 위젯의 것인가? (파티 게이트 **다음**, 상태 게이트보다 먼저) ────────
  // 후불 슬라이스(§0-ter)가 서버에서 민팅하는 청구 인텐트는 `raw.kind`를 달고 있다. 그 행은
  // 빌링키로 청구되며 payment_key도 orderId도 위젯을 거치지 않는다. 그런 order_id로 여기에
  // 들어오면 — 소유자 본인이라도 — 승인해선 안 된다: 클라가 들고 온 paymentKey가 그 주문에
  // 붙어버리고, 자동 청구 기계는 같은 orderId로 이미 처리된 결제를 만나 자기 사다리를 잃는다.
  // 무엇보다 이 함수의 §2-7 자동취소 기계는 '위젯 홀드'를 전제로 쓰였다. 사실을 말하고 멈춘다.
  if ((intent.raw ?? {}).kind) throw new HttpError(409, NOT_A_WIDGET_ORDER);

  // ── 3. 멱등 — Toss를 때리기 **전에** ──────────────────────────────────────────────────
  // 네트워크 재시도·유저 더블탭·앱 재진입이 두 번째 청구가 되어선 안 된다. 이미 완결된 주문에
  // 대한 재호출은 거짓 409가 아니라 무동작 성공이다 (transition-booking의 `unchanged` 관용구).
  if (intent.status === "confirmed") {
    return {
      ok: true, idempotent: true,
      booking_id: intent.booking_id, order_id: intent.order_id, amount: intent.amount,
      post: { recurring: "skipped", nomination: "skipped" },
    };
  }
  if (intent.status !== "pending") {
    // canceled / failed — 이미 닫힌 주문이다. 다시 승인하면 취소된 결제를 되살리는 셈이 된다.
    throw new HttpError(409, "이 결제는 이미 종료됐어요 — 예약을 다시 만들어주세요");
  }
  // 같은 payment_key가 **다른 주문**에 이미 붙어 있으면 그건 재시도가 아니라 키 재사용이다.
  // 무동작 성공으로 접으면 한 번의 승인으로 두 부킹이 결제된 것처럼 보인다. 사실을 말하고 멈춘다.
  const { data: keyOwner, error: kErr } = await db.from("payments")
    .select("id, order_id").eq("payment_key", paymentKey).maybeSingle();
  if (kErr) throw new HttpError(500, kErr.message);
  if (keyOwner && keyOwner.id !== intent.id) {
    throw new HttpError(409, "이미 사용된 결제예요 — 결제를 다시 시작해주세요");
  }

  // ── 4. Toss 승인 — 서버 시크릿으로, 우리 금액으로 ─────────────────────────────────────
  const confirmed = await tossConfirm({
    paymentKey,
    orderId: intent.order_id,
    amount: intent.amount, // 우리 인텐트 행. 요청 본문이 아니다.
  });

  if (!confirmed.ok) {
    // 승인 자체가 거절됐다 = **아무 돈도 움직이지 않았다.** 여기서 취소 API를 부르면 존재하지
    // 않는 결제를 취소하려 드는 것이고, 그 실패가 needs_manual_cancel 노이즈가 된다.
    // 인텐트는 failed로 닫는다 (payment_key는 붙이지 않는다 — 0076의 settled_has_key 참고).
    // raw는 **병합**한다. 통째로 덮으면 그 행이 이미 들고 있던 사실(민팅 표식, 조정 마커,
    // 이전 시도의 기록)이 실패 한 번에 사라진다 — 장부에서 지워진 사실은 복구할 방법이 없다.
    await db.from("payments").update({
      status: "failed",
      raw: { ...(intent.raw ?? {}), confirm_error: confirmed.body, http_status: confirmed.httpStatus },
      updated_at: new Date().toISOString(),
    }).eq("id", intent.id).eq("status", "pending");
    const msg = typeof confirmed.body?.message === "string"
      ? confirmed.body.message
      : "결제가 승인되지 않았어요 — 다시 시도해주세요";
    throw new HttpError(402, msg);
  }

  // ══ 이 지점부터 돈은 움직였다. 아래의 모든 실패는 보상해야 한다 (§2-7). ══

  const raw = confirmed.body;

  // ── 5. 서버 진실과 대조 ───────────────────────────────────────────────────────────────
  // totalAmount가 승인 총액이다. Number()로 감싸는 이유: PG 응답의 숫자 타입을 신뢰하지 않는다.
  const paid = Number(raw.totalAmount);
  if (!Number.isFinite(paid) || paid !== intent.amount) {
    return await autoCancel(db, intent, paymentKey, raw, "amount_mismatch");
  }
  // 계획 §2-8: DONE이 아닌 모든 상태(가상계좌 WAITING_FOR_DEPOSIT 등)는 캡처 이후 실패로 취급한다.
  // 위젯이 그런 수단을 제공하지 않도록 구성돼 있지만, 그 구성은 클라에 있다 = 방어가 아니다.
  if (raw.status !== "DONE") {
    return await autoCancel(db, intent, paymentKey, raw, `unexpected_status_${String(raw.status)}`);
  }

  // ── 6. 인텐트 완결 — 부킹보다 먼저 ────────────────────────────────────────────────────
  // CAS(.eq status pending)인 이유: 같은 주문의 두 요청이 여기까지 나란히 오면(Toss는 멱등 키로
  // 둘 다 승인 응답을 준다) 진 쪽이 0행을 받는다. 그 0행은 실패가 아니라 '남이 먼저 완결했다'이고,
  // 그때 자동 취소를 걸면 이긴 쪽의 정상 결제를 취소하게 된다. 재조회해서 사실을 확인한다.
  const { data: settled, error: sErr } = await db.from("payments").update({
    status: "confirmed",
    payment_key: paymentKey,
    raw,
    updated_at: new Date().toISOString(),
  }).eq("id", intent.id).eq("status", "pending").select("id");
  if (sErr) throw new HttpError(500, sErr.message);
  if (!settled || settled.length === 0) {
    const { data: fresh } = await db.from("payments").select("status").eq("id", intent.id).maybeSingle();
    if (fresh?.status === "confirmed") {
      return {
        ok: true, idempotent: true,
        booking_id: intent.booking_id, order_id: intent.order_id, amount: intent.amount,
        post: { recurring: "skipped", nomination: "skipped" },
      };
    }
    return await autoCancel(db, intent, paymentKey, raw, "intent_write_lost");
  }

  // ── 7. 부킹 CAS — transition-booking:42-46과 같은 문장 ────────────────────────────────
  // 0060의 30분 e_hold와 경합한다. 0행 = 홀드가 만료됐다 = 돈을 먼저 돌려준 뒤에야 그 사실을
  // 말할 수 있다(§2-7). 그래서 여기서 던지지 않고 자동 취소 기계로 넘긴다.
  const { data: moved, error: mErr } = await db.from("bookings")
    .update({ status: "matching" })
    .eq("id", intent.booking_id).eq("status", "payment_hold").select("id");
  if (mErr) return await autoCancel(db, intent, paymentKey, raw, `cas_error_${mErr.message}`);
  if (!moved || moved.length === 0) {
    return await autoCancel(db, intent, paymentKey, raw, "hold_expired");
  }

  // ── 9. §2-5b 후처리 — 서버에서, 비치명적으로 ──────────────────────────────────────────
  const post = await postConfirm(req, db, mkUserDb, {
    bookingId: intent.booking_id, ownerId: bk.owner_id,
    preferredRunnerId: meta.preferred_runner_id ?? null,
    recurring: meta.recurring === true || meta.recurring === "1",
  });

  return {
    ok: true,
    booking_id: intent.booking_id,
    order_id: intent.order_id,
    amount: intent.amount,
    post,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════════════
// §2-7 자동 취소 기계 — 캡처 이후 실패의 유일한 출구
// ═══════════════════════════════════════════════════════════════════════════════════════
// 항상 throw한다 (반환 타입이 never인 이유). 성공 경로로 빠져나갈 수 있는 문이 하나라도 있으면
// '돈은 취소됐는데 예약은 확정된 것처럼 보이는' 상태가 만들어진다.
async function autoCancel(
  db: SupabaseClient,
  intent: Intent,
  paymentKey: string,
  confirmRaw: Record<string, unknown>,
  why: string,
): Promise<never> {
  let lastError = "";
  // 두 번 시도 = 계획의 "retry once". 세 번이 아닌 이유: 이 루프는 사용자가 결제 화면에서
  // 기다리는 동안 돈다. 두 번 실패하면 그건 일시적 문제가 아니고, 사람이 봐야 한다.
  for (let attempt = 1; attempt <= 2; attempt++) {
    let res;
    try {
      res = await tossCancel(paymentKey, { orderId: intent.order_id, reason: why });
    } catch (e) {
      lastError = `attempt${attempt}:${e instanceof Error ? e.message : String(e)}`;
      continue;
    }
    if (res.ok) {
      // 전액 취소가 성공했다 = 이 결제는 없던 일이 됐다. refunded_amount를 채우는 이유:
      // 0071은 "이번 슬라이스는 refunded_amount를 쓰지 않는다"고 적었지만, 그건 **환불 기능**
      // 이야기였다. 자동 취소는 전액이 실제로 돌아간 사건이고, 그걸 0으로 두면 장부가
      // "24,900원을 받고 0원을 돌려줬다"고 말하게 된다. 정확한 숫자가 이긴다.
      await db.from("payments").update({
        status: "canceled",
        payment_key: paymentKey,
        refunded_amount: intent.amount,
        raw: { confirm: confirmRaw, cancel: res.body, auto_cancel_reason: why },
        updated_at: new Date().toISOString(),
      }).eq("id", intent.id);
      throw new HttpError(409, HONEST_AUTOCANCELED);
    }
    lastError = `attempt${attempt}:${res.httpStatus}:${JSON.stringify(res.body)}`;
  }

  // 두 번 다 실패 — 돈은 Toss에 남아 있다. 행을 canceled로 적으면 장부가 거짓말을 한다.
  // confirmed 그대로 두고 마커를 남긴다: 0076 §D의 조정 질의가 orphan_capture로 이 행을 집는다
  // (부킹은 payment_hold/expired에 머물러 있으므로).
  await db.from("payments").update({
    status: "confirmed",
    payment_key: paymentKey,
    raw: {
      confirm: confirmRaw,
      needs_manual_cancel: true,
      auto_cancel_reason: why,
      cancel_error: lastError,
    },
    updated_at: new Date().toISOString(),
  }).eq("id", intent.id);

  await notifyOps(db, intent, why, lastError);
  throw new HttpError(409, honestNeedsManual(intent.order_id));
}

// 운영(Sean)에게 알린다 — **보호자에게가 아니다.** 보호자가 할 수 있는 일이 없는 사건을
// 보호자의 알림함에 넣으면 불안만 배달된다. 처리 주체는 사람이고, 그 사람은 운영자다.
// OPS_PROFILE_ID가 없으면 조용히 넘기지 않고 크게 로그한다 — 조정 질의(0076 §D)가 진짜
// 소비자이므로 알림이 없어도 이 행은 발견된다. 알림은 속도지 유일한 안전망이 아니다.
//
// ⚠ THE NOTIFICATION BODY CARRIES NO FINANCIAL DETAIL — deliberately (2026-08-13 hardening).
// OPS_PROFILE_ID is an env var holding a raw uuid. A typo that still parses as a valid
// profile id delivers this row to a REAL USER, and 0024's insert trigger pushes the body
// verbatim to their lock screen — i.e. one bad env value turns an ops alert into another
// customer's order number and amount on a stranger's phone. Adding a second env var to
// cross-check the first only moves the question (now two values must be right). Removing
// the payload removes the class: the alert says WHAT happened and WHERE to look, the
// identifiers live in console.error (ops-only) and in payments_reconciliation(), which is
// the actual consumer. A misdelivered alert is then merely confusing, never disclosing.
async function notifyOps(db: SupabaseClient, intent: Intent, why: string, lastError: string) {
  const ops = Deno.env.get("OPS_PROFILE_ID");
  const line =
    `[payments] auto-cancel FAILED order=${intent.order_id} payment=${intent.id} amount=${intent.amount} why=${why} err=${lastError}`;
  if (!ops) {
    console.error(`${line} — OPS_PROFILE_ID unset, no notification sent`);
    return;
  }
  const { error } = await db.from("notifications").insert({
    profile_id: ops,
    kind: "system",
    title: "결제 자동 취소 실패 — 수동 취소 필요",
    body: "payments_reconciliation()에서 orphan_capture 행을 확인해주세요 (주문번호·금액은 조정 질의에 있어요)",
    // ref_id stays: it is a bare uuid with no meaning outside our own tables, and the ops
    // surface needs a handle. It is not rendered in the push body.
    ref_id: intent.booking_id,
  });
  // 알림 실패도 삼키지 않는다. 다만 여기서 throw하면 이미 확정된 실패 응답을 500으로 바꿔
  // 보호자에게 잘못된 문장을 준다 — 로그가 옳은 자리다.
  if (error) console.error(`${line} — ops notify failed: ${error.message}`);
}

// ═══════════════════════════════════════════════════════════════════════════════════════
// §2-5b 후처리 — pay.tsx:108의 postConfirm이 서버로 옮겨온 자리
// ═══════════════════════════════════════════════════════════════════════════════════════
// 왜 옮겼나 (외부 목소리 X3): 캡처 직후 앱이 죽으면 결제한 사람이 고른 러너와 매주 반복이
// 조용히 사라졌다. 클라에만 있던 두 호출은 '성공한 결제의 일부'지 화면 로직이 아니다.
//
// 비치명적이 절대 원칙이다: 여기서 던지면 이미 청구되고 이미 전이된 예약이 실패로 보고된다.
// 실패는 알림으로 말하고(오늘 Alert가 하던 일), 응답 본문에도 실어 화면이 같은 문장을 쓴다.
//
// ⚠ 지명은 transition-booking을 **HTTP로 다시 부른다.** 클라 JWT를 그대로 전달한다.
//   대안은 request_runner의 충돌 가드·CAS·양측 알림(~50줄)을 여기에 복제하는 것이었고,
//   돈 인접 게이트의 두 번째 사본은 언젠가 반드시 갈라진다. 왕복 한 번의 대가로 단일 진실을 산다.
//   (create_recurring_series는 RPC 한 줄이지만 **호출자 JWT로** 부른다 — 0077 독트린.)
async function postConfirm(
  req: Request,
  db: SupabaseClient,
  mkUserDb: (req: Request) => SupabaseClient,
  p: { bookingId: string; ownerId: string; preferredRunnerId: string | null; recurring: boolean },
) {
  const out = { recurring: "skipped", nomination: "skipped" };

  if (p.recurring) {
    try {
      // create_recurring_series(0077 정본)는 not_signed_in 선두 가드 + is-distinct 게이트를
      // 지녔다 — service_role(auth.uid()=NULL) 호출은 not_signed_in으로 거부된다. 그래서
      // 호출자 JWT 바인딩 클라이언트로 부른다: RPC 안의 auth.uid()가 소유자가 되어 게이트가
      // 제 역할을 하고, §2의 파티 게이트는 벨트로 남는다. (이전 판은 NULL 통과에 기대는
      // 사고였다 — 0077 헤더의 호출자 독트린이 정본.)
      const userDb = mkUserDb(req);
      const { error } = await userDb.rpc("create_recurring_series", { p_booking: p.bookingId });
      if (error) throw new Error(error.message);
      out.recurring = "ok";
    } catch (e) {
      out.recurring = "failed";
      await notifyOwner(db, p.ownerId, p.bookingId, "반복 설정 실패",
        `이번 예약은 확정됐지만 매주 반복 설정에 실패했어요 — 다음 예약 때 다시 켜주세요 (${msgOf(e)})`);
    }
  }

  if (p.preferredRunnerId) {
    try {
      await invokeTransition(req, {
        booking_id: p.bookingId,
        action: "request_runner",
        meta: { runner_id: p.preferredRunnerId },
      });
      out.nomination = "ok";
    } catch (e) {
      out.nomination = "failed";
      // 조용한 삼킴 금지 (웨이브 2 C3) — 지명이 실패했다는 사실을 알아야 다음 선택을 한다.
      // 매칭 화면(matching.tsx:191)이 같은 지명을 한 번 더 시도하므로 이건 막다른 길이 아니다.
      await notifyOwner(db, p.ownerId, p.bookingId, "지명 요청 실패",
        `우선 요청을 보내지 못했어요 — 매칭 화면에서 다시 골라주세요 (${msgOf(e)})`);
    }
  }

  return out;
}

async function invokeTransition(req: Request, payload: unknown) {
  const base = Deno.env.get("SUPABASE_URL");
  if (!base) throw new Error("SUPABASE_URL unset");
  const authz = req.headers.get("Authorization");
  if (!authz) throw new Error("no caller token to forward");
  const headers: Record<string, string> = { "Authorization": authz, "Content-Type": "application/json" };
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (anon) headers["apikey"] = anon;
  const res = await fetch(`${base}/functions/v1/transition-booking`, {
    method: "POST", headers, body: JSON.stringify(payload),
  });
  const body = await res.json().catch(() => ({}));
  // transition-booking은 200 본문에 { error } 를 실어 보내지 않지만(handle이 상태코드를 쓴다),
  // 클라 래퍼(api.ts)가 두 경우를 모두 검사하므로 여기서도 같은 폭을 본다.
  if (!res.ok || body?.error) throw new Error(String(body?.error ?? `transition ${res.status}`));
  return body;
}

function notifyOwner(db: SupabaseClient, ownerId: string, bookingId: string, title: string, body: string) {
  return db.from("notifications")
    .insert({ profile_id: ownerId, kind: "booking", title, body, ref_id: bookingId });
}

function msgOf(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
