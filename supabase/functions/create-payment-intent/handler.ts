// 결제 인텐트 생성 — 위젯이 열리기 **전에** 서버가 주문을 확정한다 (toss-plan §2-7, 0076).
// input:  { booking_id }
// output: { order_id, amount, customer_key, reused }
//
// Why this exists at all: without it, the first row that says "money moved" is written AFTER
// Toss captures. A crash in that window leaves a charged card with no local trace and no
// payment_key to cancel against. Here the server binds owner + booking + amount + order_id
// before Toss has ever heard of this payment, so every later step is a completion of a record
// that already exists rather than an invention of one.
//
// The handler is exported separately from `index.ts` so `handler_test.ts` can drive it with an
// injected db — explicit over clever (toss-plan §4-1: this is the repo's first edge-fn test rail).
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, HttpError } from "../_shared/ctx.ts";

export async function createPaymentIntent(req: Request, db: SupabaseClient) {
  const uid = await caller(req, db);
  const { booking_id } = await req.json();
  if (!booking_id) throw new HttpError(400, "missing fields");

  const { data: bk, error: bErr } = await db.from("bookings")
    .select("id, owner_id, status, total_price").eq("id", booking_id).maybeSingle();
  if (bErr) throw new HttpError(500, bErr.message);
  if (!bk) throw new HttpError(404, "booking not found");

  // ── 파티 게이트가 상태 게이트보다 먼저 (CLAUDE.md 법). 순서가 뒤집히면 "지금은 결제할 수
  // 없는 상태예요"가 남의 예약 상태를 알려주는 열거 오라클이 된다.
  if (bk.owner_id !== uid) throw new HttpError(403, "owner only");
  if (bk.status !== "payment_hold") {
    throw new HttpError(409, "지금은 결제할 수 없는 상태예요 — 예약을 다시 만들어주세요");
  }
  // 가격은 create-booking-hold가 서버에서 만든 숫자다. 없으면 청구할 진실이 없는 것이고,
  // 그때 0원짜리 인텐트를 만드는 것은 조용한 무료 예약 경로다.
  if (typeof bk.total_price !== "number" || bk.total_price <= 0) {
    throw new HttpError(500, "booking has no price");
  }

  const { data: prof, error: pErr } = await db.from("profiles")
    .select("toss_customer_key").eq("id", uid).maybeSingle();
  if (pErr) throw new HttpError(500, pErr.message);
  if (!prof?.toss_customer_key) throw new HttpError(500, "profile not found");

  // ── 살아있는 인텐트 재사용 (멱등 친화) ────────────────────────────────────────────────
  // 결제 화면 재진입·뒤로가기·더블탭은 정상 동선이다. 그때마다 새 order_id를 찍으면 한 부킹에
  // pending이 쌓이고, 조정 질의(0076 §D)는 그 더미를 매번 사람에게 보여준다. 같은 주문을
  // 돌려주는 편이 사실에도 맞다 — 아직 아무 돈도 움직이지 않았고, 주문은 하나다.
  const { data: live, error: lErr } = await db.from("payments")
    .select("id, order_id, amount")
    .eq("booking_id", booking_id).eq("status", "pending")
    .order("created_at", { ascending: false }).limit(1);
  if (lErr) throw new HttpError(500, lErr.message);
  const open = live?.[0];
  if (open) {
    if (open.amount === bk.total_price) {
      return { order_id: open.order_id, amount: open.amount, customer_key: prof.toss_customer_key, reused: true };
    }
    // 금액이 어긋난 인텐트는 재사용하지 않는다 — 낡은 금액으로 위젯을 열면 confirm 단계의
    // 금액 검증(§2-4)에서 캡처 이후에 터진다. 캡처 전에 닫는 편이 언제나 싸다.
    // (오늘 total_price를 바꾸는 경로는 없다. 그래서 이건 방어지 기능이 아니다.)
    const { error: cErr } = await db.from("payments")
      .update({ status: "failed", updated_at: new Date().toISOString() })
      .eq("id", open.id).eq("status", "pending");
    if (cErr) throw new HttpError(500, cErr.message);
  }

  // order_id는 **우리가** 만든다. 클라가 만든 주문번호는 우리 쪽 멱등(0071의 order_id unique)을
  // 클라에게 넘기는 것과 같다. `dr_` + uuid = 39자로 Toss orderId 규칙(6~64자, 영숫자·-·_) 안.
  const order_id = `dr_${crypto.randomUUID()}`;
  const { data: row, error: iErr } = await db.from("payments").insert({
    booking_id,
    status: "pending",
    // 금액은 우리 테이블에서만 온다. 요청 본문에 amount가 실려 와도 이 함수는 읽지 않는다.
    amount: bk.total_price,
    order_id,
  }).select("order_id, amount").single();
  if (iErr) throw new HttpError(500, iErr.message);

  return { order_id: row.order_id, amount: row.amount, customer_key: prof.toss_customer_key, reused: false };
}
