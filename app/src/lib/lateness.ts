// ═══════════ 지각 판정 (late/unresponsive reservation, stage 1) ═══════════
// docs/plans/2026-08-21-late-booking-protocol.md §13.
//
// 이 파일이 하는 일 하나: "이 예약은 지금 늦었는가, 그리고 **누구를 기다리는가**".
// 서버 상태를 만들지 않는다 — fetchMyBookings 가 이미 싣고 오는 필드만으로 파생된다.
// 그래서 stage 1(클라이언트 전용)에서도 정직할 수 있고, stage 2(서버 시계)가 와도
// 화면이 무엇을 그릴지는 이 함수 하나가 계속 결정한다.
//
// ⚠ 왜 src/lib 인가 (2026-08-21 Sean, /plan-eng-review D4): 이 규칙은 **사람이 불발로
// 기록되는지**를 정하는 규칙이다. 화면 안에 두면 .cjs 스위트가 import 할 수 없어 영원히
// 테스트 밖에 남는다. route-pick·pace·geo 와 같은 자리에 두고 같은 방식으로 핀을 박는다.
//
// ⚠ 이 파일은 판정만 한다. 상태를 옮기지도, 돈을 움직이지도 않는다 — 침묵은 증거가 아니고
// (D5), 종점은 서버 resolver 의 몫이다 (§12).

/** 서버 원상태(enum 원문). 표시 어휘가 아니라 rawStatus 로 판정한다 (CLAUDE.md 법 3). */
export type LateInput = {
  scheduledAt: string | null;
  rawStatus: string | null | undefined;
  arrivedAt?: string | null;
  /** active 예약의 '끝났어야 할 시각' 산출용. 없으면 러닝 중 지각은 판정하지 않는다. */
  km?: number | null;
};

export type Custody = 'pre' | 'post';
export type WaitingOn = 'runner' | 'owner' | null;

export type Lateness = {
  late: boolean;
  /** 늦은 시간(ms). late=false 면 0. */
  sinceMs: number;
  custody: Custody;
  waitingOn: WaitingOn;
};

// ⚠ PROVISIONAL — 유예 시간은 Sean 미정 (플랜 §10 '해소되지 않음'). 상수로 박아두지 않고
// 인자로 받는 이유: 제품 숫자를 엔지니어가 정하지 않기 위해서다. 그가 답하면 이 기본값만 바뀐다.
export const LATENESS_GRACE_MS = 10 * 60_000;

/** 인계선 — 0066:50 이 그은 그 선. picked_up 부터는 개가 러너에게 있다. */
const POST_CUSTODY = new Set(['picked_up', 'active']);

/** 이 상태들만 '늦을 수' 있다. matching·runner_pending 은 expire-unmatched 크론의 몫이고,
 *  종료 상태(completed·cancelled_*·expired·no_show·incident_review·refund_pending)는 이미 끝났다. */
const CAN_BE_LATE = new Set(['confirmed', 'runner_enroute', 'picked_up', 'active']);

/** 실소요 = km×8 + 25분 — owner/request 의 slotAllowed·서버 수락 검증과 같은 식.
 *  두 벌로 갈라지면 '가능하다던 칸이 거절되는' 드리프트가 다시 생긴다. */
export const expectedDurationMs = (km: number) => Math.round(km * 8 + 25) * 60_000;

export function lateness(b: LateInput, now: number, graceMs = LATENESS_GRACE_MS): Lateness {
  const status = b.rawStatus ?? '';
  const custody: Custody = POST_CUSTODY.has(status) ? 'post' : 'pre';
  const none: Lateness = { late: false, sinceMs: 0, custody, waitingOn: null };

  if (!CAN_BE_LATE.has(status)) return none;
  const start = b.scheduledAt ? Date.parse(b.scheduledAt) : NaN;
  if (Number.isNaN(start)) return none; // 시각을 모르면 늦었다고 말하지 않는다 (정직 법)

  // active 는 '시작'이 아니라 '끝'을 기준으로 늦는다 — 달리는 중인 러닝은 예약 시각을 지나 있는
  // 게 정상이다. km 이 없으면 끝났어야 할 시각을 모르므로 판정을 포기한다 (추측 금지).
  let due = start;
  if (status === 'active') {
    if (b.km == null || !Number.isFinite(b.km)) return none;
    due = start + expectedDurationMs(b.km);
  }

  const deadline = due + graceMs;
  if (now <= deadline) return none;

  // 누구를 기다리는가.
  // runner_enroute + arrived_at → 러너는 제 몫을 했고 문 앞에 있다. 기다리는 쪽은 보호자다.
  // ⚠ arrived_at 은 여기서 **표시 근거**로만 쓴다. 게이트로 읽지 않는다 — 그 판정은 Sean 의
  // handoff-CTA A/B 에 유보돼 있고(플랜 §14), 게다가 self-attested 라 증거가 아니다.
  const waitingOn: WaitingOn =
    status === 'runner_enroute' && b.arrivedAt ? 'owner' : 'runner';

  return { late: true, sinceMs: now - deadline, custody, waitingOn };
}
