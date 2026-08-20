// 결제 페이즈 머신 — 서버 진실(bookings.status)에서 결제 표면의 화면 페이즈를 파생하는 단 하나의 자리.
// owner/pay.tsx와 미래 PG 클라이언트(설계 phase ④)가 같은 머신을 import 한다 — 3차 리빌드 방지
// (웨이브 2 리뷰 H4/H5). 화면은 이 파일이 말한 것만 말한다: 상태를 지어내지 않는다.
//
// [C5 수정 확정] 리포트의 draft|quoted→'error(라우드)'는 타입 불능이었다 — M1이 error를 페이즈에서
// 제거했기 때문. 확정 해석: 도달 불가 상태 = '부재'(not_found, 재시도 문 없음). 리포트보다 이 줄이 이긴다.
// [어휘 분기 명문화 · H5] api.ts STATUS_MAP(fetchMyBookings 부근)은 '예약 목록 배지' 어휘(pending/confirmed/cancelled…)라
// refund_pending을 'cancelled'로 접는다 — 목록에서는 취소의 후속 단계로 보이는 게 정직하기 때문이다.
// 여기서는 접지 않는다: 결제 표면에서 '환불 진행 중'과 '취소됨'은 사용자가 지금 기다려야 하는지가
// 갈리는 서로 다른 사실이다. 두 매핑은 목적이 달라 일부러 갈라져 있다 — 통합하지 말 것.

// bookings.status enum 전체 16종 (supabase/migrations/0001_init.sql:9-14).
// 리터럴 유니언인 이유: 아래 Record가 누락을 tsc 에러로 만든다
// (웨이브 2 리뷰 C5 — 8종 미매핑 + no_show/incident_review가 '결제 완료'로 위장하던 사고).
export type BookingStatus =
  | 'draft' | 'quoted' | 'payment_hold' | 'matching' | 'runner_pending'
  | 'confirmed' | 'runner_enroute' | 'picked_up' | 'active' | 'completed'
  | 'cancelled_owner' | 'cancelled_runner' | 'expired' | 'no_show'
  | 'incident_review' | 'refund_pending';

// 9페이즈 확정 (웨이브 2 리뷰 M1 — 'partial' 삭제: 정산은 원자적이라 서버가 그 상태를 만들 수 없다).
// 통신 실패('error')는 여기 없다 — 그건 예약의 상태가 아니라 우리 쪽 실패다. 화면이 한 칸 더 갖는다.
export type PayPhase =
  | 'loading'        // 청구 fetch 중 — 숫자는 전부 '—', CTA 없음
  | 'not_found'      // 0행·없는 bid·남의 예약 — 재시도 없는 정직한 부재 (H3/M5)
  // [O-5 §E.5.1] '실전이(confirmPayment)'는 삭제됐다 — payment_hold에 남은 예약을 앞으로 미는
  // 클라이언트 호출이 더 이상 없다. 이 페이즈는 이제 '아직 접수되지 않음'을 말할 뿐이다.
  | 'mock_pending'   // PG 목업 · 접수 전 — 화면이 할 수 있는 일은 사실을 말하고 나가는 것뿐
  | 'authorizing'    // 미래 PG: 승인 요청 진행 중 — 취소 어포던스 없는 화면
  | 'authorized'     // 결제 홀드를 지난 예약 — 여기서는 종점, 다음 화면으로 보낸다
  | 'disputed'       // no_show·incident_review — '완료'로 위장하지 않는다 (C5)
  | 'failed'         // 전이 실패 / PG 거절 — 라우드 페일 + 재시도
  | 'cancelled'      // cancelled_* · expired — 종점
  | 'refund_pending';// 환불 진행 중 — 종점이지만 대기 중

// PG 시도 레코드 — 오늘 서버에 존재하지 않는다 (derivePayPhase의 attempt는 항상 undefined).
// PG 슬라이스가 붙을 때 이 인자만 채우면 authorizing/failed가 살아난다: 머신 재작성 없음 (H4).
// 승인 '성공'은 여기 없다 — 그건 서버 status가 말한다 (클라이언트가 결제 완료를 선언하지 않는다).
export type PayAttemptState = 'in_flight' | 'declined';
export interface PayAttempt { state: PayAttemptState; reason?: string | null }

// 상태 → 페이즈 (16종 전수). 새 enum 값이 생기면 tsc가 이 자리에서 막는다.
export const STATUS_PHASE: Record<BookingStatus, PayPhase> = {
  // draft·quoted: 이 라우트로 도달할 수 없다 — 홀드 생성(create-booking-hold)이 그 두 상태를
  // 한 요청 안에서 지나쳐 간다. 도달했다면 결제 표면이 말할 수 있는 사실이 없다는 뜻이라
  // '부재'로 떨어뜨린다 (재시도 문을 열지 않는다 — 없는 결제를 기다리게 하지 않는 쪽이 정직하다).
  draft: 'not_found',
  quoted: 'not_found',
  payment_hold: 'mock_pending',
  // 아래 7종은 이미 결제 홀드를 지난 예약이다 — 결제 표면의 할 일은 '다음 화면으로'뿐.
  // [M7] 클럽 예약은 payment_hold를 거치지 않고 곧장 이 구간으로 들어온다 → authorized로 렌더된다 (정상).
  matching: 'authorized',
  runner_pending: 'authorized',
  confirmed: 'authorized',
  runner_enroute: 'authorized',
  picked_up: 'authorized',
  active: 'authorized',
  completed: 'authorized',
  cancelled_owner: 'cancelled',
  cancelled_runner: 'cancelled',
  expired: 'cancelled',
  // 노쇼·사고 검토는 '결제 완료'가 아니다 — 사람이 확인 중인 예약이다 (C5).
  no_show: 'disputed',
  incident_review: 'disputed',
  refund_pending: 'refund_pending',
};

export function derivePayPhase(p: { status: BookingStatus; attempt?: PayAttempt | null }): PayPhase {
  const base: PayPhase | undefined = STATUS_PHASE[p.status];
  // 서버가 enum을 늘리면 런타임 문자열은 tsc가 못 잡는다 — 모르는 상태를 '결제 완료'로 위장하지 않고
  // 부재로 떨어뜨린다 (모르면 모른다고 말한다).
  if (!base) return 'not_found';
  if (!p.attempt) return base;              // 오늘의 유일한 경로 — attempt는 아직 서버에 없다
  if (base !== 'mock_pending') return base; // 홀드를 지난 예약은 시도 레코드보다 서버 상태가 최신이다
  return p.attempt.state === 'declined' ? 'failed' : 'authorizing';
}
