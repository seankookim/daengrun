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
  /** 양측 인계 소인 (bookings.owner_confirmed_handoff_at · runner_confirmed_handoff_at).
   *  ⚠ [F7 2026-08-24] 커스터디 판정의 **필수 입력**이다. 두 값을 싣지 못하는 리더는 커스터디에
   *  기대는 문장을 그리면 안 된다 (§13 C2) — 그래서 fetchMyBookings · fetchRunnerJobs ·
   *  fetchMeetupInfo 세 셀렉트가 전부 이 두 컬럼을 싣도록 같은 슬라이스에서 바꿨다.
   *  undefined 는 '아직 안 실었다'가 아니라 '없다'로 취급된다 — 새 리더가 생기면 셀렉트에
   *  두 컬럼을 더하는 것이 계약이다. */
  ownerHandoffAt?: string | null;
  runnerHandoffAt?: string | null;
};

export type Custody = 'pre' | 'post';
export type WaitingOn = 'runner' | 'owner' | null;

export type Lateness = {
  late: boolean;
  /** 늦은 시간(ms) — **약속 시각 기준**이지 유예 마감 기준이 아니다. late=false 면 0.
   *  ⚠ 왜 유예를 빼지 않는가 (codex 2026-08-21): runner/home 의 티켓은 relWhen() 으로 예약 시각부터
   *  세고, 이 값은 유예 마감부터 셌다. 그래서 한 화면에서 티켓은 「60분 늦음」, 알림은 「30분 늦음」
   *  이라고 말했다 — 둘 다 참인데 사용자에겐 그냥 버그다. 유예는 '늦었다고 말할지'를 정하는 문턱이지
   *  '얼마나 늦었는지'의 원점이 아니다. 사람이 늦은 정도는 약속으로부터 잰다. */
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

// 천장 — 약속 시각으로부터 이 시간을 넘기면 '늦은 예약'이 아니라 '끝난 일'이다.
//   (sinceMs 와 같은 원점을 쓴다 — 문턱과 원점이 다르면 두 숫자가 생긴다.)
// 왜 필요한가: 천장이 없으면 두 번의 탭으로 16일 된 예약이 되살아난다 (codex 지적, 플랜 §4.3).
// 인계 후에도 같다: 3시간을 넘긴 러닝은 정상 러닝이 아니라 확인이 필요한 사건이다.
//
// ⚠ [정정 2026-08-24] 이 자리에 「넘긴 뒤에는 화면이 '진행' 계열 동작을 제안하지 않는다 — 종점만
// 남는다」라고 적혀 있었다. **그 시점엔 참이 아니었다.** resumable 의 소비자가 이 파일 자신과
// late-copy 의 문장 한 갈래뿐이었고, 마운트해서 이 값을 읽는 화면이 하나도 없었다. 그래서 러너 홈은
// 「이 예약은 진행할 수 없어요」 82줄 아래에 코랄 「픽업 이동 시작」을 나란히 그리고 있었다.
// 지금은 절반만 참이다: runner/meetup 의 pastCeiling 이 러너의 **탭 문**(장비 체크 · 도착 확인 ·
// 인계 받기)을 실제로 닫는다. 아직 참이 아닌 쪽 — 보호자 화면엔 닫을 문이 없고(권고만 준다),
// runner/meetup 의 마운트 effect 는 info 보다 먼저 돌아 runnerEnroute 를 게이트 밖에서 쏜다.
// **서버는 천장을 아예 모른다.** 그래서 late-copy 의 문장은 '불가능'이라고 말하지 않는다 —
// 시스템이 해낼 수 있는 일을 화면이 못 한다고 말하면 그게 이 파일이 막으려는 그 거짓말이다.
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

/** 인계선 — 0066:50 이 그은 그 선. picked_up 부터는 개가 러너에게 있다.
 *
 * ⚠ [F7 2026-08-24] 이건 **상태만 보는 한 갈래짜리 술어**였고, 서버(0117:159-170 `_checkin_custody`)는
 * 두 갈래로 긋는다. 같은 예약을 두고 클라이언트와 서버가 D3 선을 서로 다른 자리에 그었다는 뜻이다.
 *
 * 갈라지는 실제 경우: transition-booking/index.ts:315-322 는 소인을 찍고, 다시 읽지 않은 채,
 * 두 번째 호출로 status='picked_up' 을 쓴다. 두 소인은 남고 승격만 실패하는 찢어진 쓰기가 가능하다.
 * 그러면 status 는 runner_enroute, 소인은 둘 다 있다 →
 *   서버: 'post'  (개는 러너 손에 있다고 본다. no_show 를 거부하고 「확인이 필요해요」를 보낸다)
 *   옛 클라: 'pre' (그래서 보호자는 「러너님이 문 앞에서 기다려요」를, 러너는 「보호자가 아직
 *                  나오지 않았어요」를 읽는다 — 개는 이미 러너에게 있는데.)
 * 게다가 owner/meetup:219 가 승격을 재시도할 유일한 컨트롤을 숨겨서 그 상태가 영구히 남는다.
 *
 * 그래서 서버 술어를 **그대로** 옮긴다. 규칙은 하나, 구현은 둘이다 (§13 C2).
 * (서버의 네 번째 갈래 'out' 은 옮기지 않는다 — 그 상태들은 아래 CAN_BE_LATE 에서 이미 걸러져
 *  none 으로 나가므로 화면에 커스터디 문장이 뜨지 않는다. 값을 하나 더 만들면 새 표면이 된다.) */
const POST_CUSTODY_STATUS = new Set(['picked_up', 'active']);
const CUSTODY_LIVE = new Set(['confirmed', 'runner_enroute', 'picked_up', 'active']);

/** 0117:163-169 의 case 식과 같은 답을 낸다. */
export const custodyOf = (
  status: string,
  ownerHandoffAt?: string | null,
  runnerHandoffAt?: string | null,
): Custody =>
  (CUSTODY_LIVE.has(status) && !!ownerHandoffAt && !!runnerHandoffAt) || POST_CUSTODY_STATUS.has(status)
    ? 'post'
    : 'pre';

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
  const custody: Custody = custodyOf(status, b.ownerHandoffAt, b.runnerHandoffAt);
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
    // ⚠ 실제 출발 시각부터 잰다. 예약 시각으로 재면 20분 늦게 출발한 러닝이 20분 일찍 '초과'가 된다.
    // started_at 이 없으면 **판정하지 않는다** — 예약 시각으로 폴백하지 않는다.
    // 왜: start_run_tx 는 status='active' 와 runs.started_at 을 같은 트랜잭션에서 쓴다
    // (0087:193-214). 그러니 active 인데 started_at 이 없다는 건 정상적인 지연 도착이 아니라
    // **임베드나 RLS 가 깨졌다는 뜻**이다. 그때 예약 시각으로 조용히 되돌아가면 두 가지를 동시에
    // 잃는다: 방금 고친 버그가 되살아나고, 깨졌다는 신호가 영원히 묻힌다.
    // 시각을 모르면 늦었다고 말하지 않는다는 이 파일의 규칙(위 scheduledAt 분기)과 같은 처리다.
    const startedMs = b.startedAt ? Date.parse(b.startedAt) : NaN;
    if (Number.isNaN(startedMs)) return none;
    due = startedMs + expectedDurationMs(b.km);
  }

  const deadline = due + graceMs;
  if (now <= deadline) return none;

  // 누구를 기다리는가.
  // runner_enroute + arrived_at → 러너는 제 몫을 했고 문 앞에 있다. 기다리는 쪽은 보호자다.
  // ⚠ arrived_at 은 여기서 **표시 근거**로만 쓴다. 게이트로 읽지 않는다 — 그 판정은 Sean 의
  // handoff-CTA A/B 에 유보돼 있고(플랜 §14), 게다가 self-attested 라 증거가 아니다.
  const waitingOn: WaitingOn =
    status === 'runner_enroute' && b.arrivedAt ? 'owner' : 'runner';

  const sinceMs = now - due;   // 약속(또는 예상 종료)으로부터. 유예는 위 문턱에서 이미 제 몫을 했다.
  const arrivedMs = b.arrivedAt ? Date.parse(b.arrivedAt) : NaN;
  const waitMs = waitingOn === 'owner' && !Number.isNaN(arrivedMs)
    ? Math.max(0, now - arrivedMs)   // 러너가 실제로 문 앞에 서 있던 시간
    : sinceMs;
  return { late: true, sinceMs, custody, waitingOn, resumable: sinceMs <= ceilingMs, started, waitMs };
}
