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
  /** runs.started_at. active 의 기준점 — 없으면 scheduled_at 으로 떨어진다. */
  startedAt?: string | null;
};

export type Custody = 'pre' | 'post';
export type WaitingOn = 'runner' | 'owner' | null;

export type Lateness = {
  late: boolean;
  /** 늦은 시간(ms). late=false 면 0. */
  sinceMs: number;
  custody: Custody;
  waitingOn: WaitingOn;
  /** 아직 이대로 진행될 수 있는가. 천장을 넘기면 false — 화면은 '진행' 문을 그리지 않는다. */
  resumable: boolean;
  /** 러닝이 실제로 시작됐는가 (status === 'active'). picked_up 은 개를 데려갔지만 아직 출발 전이다. */
  started: boolean;
  /** 기다리는 쪽이 **실제로 기다린** 시간(ms). arrived_at 이 있으면 그 시각부터, 없으면 sinceMs 와 같다.
   *  ⚠ sinceMs 와 다른 값이다: sinceMs 는 '예약보다 얼마나 늦었나', 이건 '문 앞에서 얼마나 서 있었나'.
   *  10:00 예약에 10:25 도착, 지금 10:30 이면 늦음은 30분이지만 러너가 기다린 건 5분이다.
   *  둘을 뭉치면 화면이 「30분째 대기 중」이라고 사람을 잘못 비난한다. */
  waitMs: number;
};

// 유예 30분 · 천장 3시간 — Sean, 2026-08-21 (announcer 경유 전달). 제품 숫자이지 엔지니어의
// 숫자가 아니라서 처음부터 인자로 빼뒀고, 이제 그 기본값이 채워졌다. 여전히 주입 가능하다.
export const LATENESS_GRACE_MS = 30 * 60_000;

// 천장 — 이 시간을 넘기면 이 예약은 '늦은 예약'이 아니라 '끝난 일'이다.
// 왜 필요한가: 천장이 없으면 두 번의 탭으로 16일 된 예약이 되살아난다 (codex 지적, 플랜 §4.3).
// 넘긴 뒤에는 화면이 '진행' 계열 동작을 제안하지 않는다 — 종점만 남는다.
// 인계 후에도 같다: 3시간을 넘긴 러닝은 정상 러닝이 아니라 확인이 필요한 사건이다.
export const LATENESS_CEILING_MS = 3 * 3_600_000;

/** 지각 시간을 사람 말로. 분 아래를 '곧'으로 뭉개지 않는다 — 반올림이 거짓이 되지 않게. */
export const sinceLabel = (ms: number): string => {
  const min = Math.floor(ms / 60_000);
  if (min < 60) return `${min}분`;
  const h = Math.floor(min / 60);
  const rem = min % 60;
  if (h < 24) return rem ? `${h}시간 ${rem}분` : `${h}시간`;
  return `${Math.floor(h / 24)}일`;
};

/** 인계선 — 0066:50 이 그은 그 선. picked_up 부터는 개가 러너에게 있다. */
const POST_CUSTODY = new Set(['picked_up', 'active']);

/** 이 상태들만 '늦을 수' 있다. matching·runner_pending 은 expire-unmatched 크론의 몫이고,
 *  종료 상태(completed·cancelled_*·expired·no_show·incident_review·refund_pending)는 이미 끝났다. */
const CAN_BE_LATE = new Set(['confirmed', 'runner_enroute', 'picked_up', 'active']);

/** 실소요 = km×8 + 25분 — owner/request 의 slotAllowed·서버 수락 검증과 같은 식.
 *  두 벌로 갈라지면 '가능하다던 칸이 거절되는' 드리프트가 다시 생긴다. */
export const expectedDurationMs = (km: number) => Math.round(km * 8 + 25) * 60_000;

// `now` 는 기본값을 갖는다. 화면이 렌더 중에 Date.now() 를 부르면 react-hooks/purity 가 잡고,
// 그걸 피하려고 상태로 올리면 이번엔 컴파일러가 다른 데서 체한다 (실측 2026-08-21). 시계를
// 이 함수 안에 두면 호출부는 순수해지고, 테스트는 계속 명시적으로 주입한다 — 양쪽 다 만족한다.
export function lateness(
  b: LateInput, now: number = Date.now(),
  graceMs = LATENESS_GRACE_MS, ceilingMs = LATENESS_CEILING_MS,
): Lateness {
  const status = b.rawStatus ?? '';
  const custody: Custody = POST_CUSTODY.has(status) ? 'post' : 'pre';
  const started = status === 'active';
  const none: Lateness = { late: false, sinceMs: 0, custody, waitingOn: null, resumable: true, started, waitMs: 0 };

  if (!CAN_BE_LATE.has(status)) return none;
  const start = b.scheduledAt ? Date.parse(b.scheduledAt) : NaN;
  if (Number.isNaN(start)) return none; // 시각을 모르면 늦었다고 말하지 않는다 (정직 법)

  // active 는 '시작'이 아니라 '끝'을 기준으로 늦는다 — 달리는 중인 러닝은 예약 시각을 지나 있는
  // 게 정상이다. km 이 없으면 끝났어야 할 시각을 모르므로 판정을 포기한다 (추측 금지).
  let due = start;
  if (status === 'active') {
    if (b.km == null || !Number.isFinite(b.km)) return none;
    // ⚠ 실제 출발 시각부터 잰다. 예약 시각을 기준으로 하면 20분 늦게 출발한 러닝이 20분 일찍
    // '초과'가 되고, 일찍 출발한 러닝은 실제로 길어졌는데도 정상으로 보인다. started_at 은
    // 서버가 쓰는 값이라(runs) 클라이언트 추정보다 신뢰도가 높다. 없으면 예약 시각으로 폴백.
    const startedMs = b.startedAt ? Date.parse(b.startedAt) : NaN;
    const base = Number.isNaN(startedMs) ? start : startedMs;
    due = base + expectedDurationMs(b.km);
  }

  const deadline = due + graceMs;
  if (now <= deadline) return none;

  // 누구를 기다리는가.
  // runner_enroute + arrived_at → 러너는 제 몫을 했고 문 앞에 있다. 기다리는 쪽은 보호자다.
  // ⚠ arrived_at 은 여기서 **표시 근거**로만 쓴다. 게이트로 읽지 않는다 — 그 판정은 Sean 의
  // handoff-CTA A/B 에 유보돼 있고(플랜 §14), 게다가 self-attested 라 증거가 아니다.
  const waitingOn: WaitingOn =
    status === 'runner_enroute' && b.arrivedAt ? 'owner' : 'runner';

  const sinceMs = now - deadline;
  const arrivedMs = b.arrivedAt ? Date.parse(b.arrivedAt) : NaN;
  const waitMs = waitingOn === 'owner' && !Number.isNaN(arrivedMs)
    ? Math.max(0, now - arrivedMs)   // 러너가 실제로 문 앞에 서 있던 시간
    : sinceMs;
  return { late: true, sinceMs, custody, waitingOn, resumable: sinceMs <= ceilingMs, started, waitMs };
}
