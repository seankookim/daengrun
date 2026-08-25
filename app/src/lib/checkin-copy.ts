// ═══════════ 지각 체크인 문장 — 「왜 멈췄나요」 (stop-reason ask) ═══════════
// 정본: docs/plans/2026-08-21-late-booking-protocol.md §8-bis (Sean 2026-08-21: "ask why they
// stopped." · 콘솔 룰링 #18 2026-08-25 "approve on everything") · docs/labs/stop-reason-lab.html
// ③ + ③-A, 사유 하나는 ③-C 에서 빌린다. 서버 계약: supabase/migrations/0117 §6/§7.
//
// This file holds sentences and nothing else — the verdicts live in checkin.ts and the pixels in
// components/checkin-answer.tsx. Same split, same reason, as lateness / late-copy / late-notice:
// 문장이 곧 법이고, 컴포넌트 안에 있는 법은 .cjs 스위트가 번들할 수 없어 영원히 테스트 밖에 남는다.
//
// ⚠ THREE THINGS THIS FILE MAY NEVER SAY, each learned at a cost:
//  1. 상대방의 사유 텍스트. 4B 룰링(0117:1080-1113): 사유는 **본인만** 읽는다. 이 파일은
//     `theirHasReason` 불리언만 받고 텍스트는 인자로 받지도 않는다 — 못 하는 게 아니라 **손에
//     들어오지 않는다**. 실수할 자리를 없애는 쪽이 실수하지 않겠다는 다짐보다 낫다.
//  2. 「이 예약은 진행할 수 없어요」 류의 예약 단위 불가능 단언 (late-copy F3a). 천장을 넘겨도
//     서버가 거부하는 것은 **이 프로토콜의 'proceeding' 답**뿐이다 (§6 checkin_past_ceiling);
//     러너 화면에서 러닝을 시작하는 문은 여전히 열려 있다. 그래서 문장은 '답'을 주어로 쓴다.
//  3. 침묵에 대한 위협. §8-bis 의 정책 불변식: **사유 없음은 그 자체로 불리한 추정이나 다른
//     요금을 만들지 않는다.** 답을 안 하면 손해라고 읽히는 문장 하나면 "답은 선택"이 거짓이 된다.

import type { Affordance, CheckinAnswerValue, CheckinCustody, CheckinSide, CheckinState, CheckinToken } from './checkin';
import { affordancesFor, checkinTokenFrom, myAnswerOf, myReasonOf, theirAnswerOf, theirHasReason } from './checkin';

// ═══ ③-A: 중단 사유 — 런엔드가 이미 쓰는 그 행들 ═══════════════════════════════════════════
// ③-A 의 요지: 이 앱에는 같은 두 단계 사유 플로우가 **두 번** 있다 (club/run/[sid].tsx:47,
// runner/run.tsx:1559). 탭 수는 전역 선택이 아니라 **사유마다** 다르고, 그 결정은 서버가 무엇을
// 증거로 요구하는가에 묶여 있다 (settle-run:74 는 컨디션 종료에 노트 없이는 거부한다). 새 문법을
// 만들 자리가 아니라 있는 문법을 그대로 쓰는 자리다.
//
// ⚠ 여기서 ③-A 를 **그대로** 베끼지 않는 두 지점, 둘 다 계획 §8-bis 가 명시한다:
//  · 추가 (③-C 에서 빌린 하나): 「상대방과 연락이 안 돼요」. 런엔드 어휘에는 없다 — 러닝의 끝에는
//    잃어버릴 상대가 없기 때문이고, 지각 프로토콜에서는 이게 가장 흔한 사유일 수 있다.
//  · 재작성: 「보호자 요청」은 체크인 맥락에서 잘못 읽힌다. 보호자가 응답을 안 하는 것이 **멈추는
//    이유**일 수 있는 화면에서 「보호자 요청」은 '연락이 안 됨'과 구별되지 않는다. 그래서 요청이
//    실제로 있었다는 사실을 문장이 직접 말한다: 「보호자가 중단을 요청했어요」.
export type StopReasonKey =
  | 'dog_condition'      // 런엔드 enum 공유 (end_reason)
  | 'owner_request'      // 런엔드 enum 공유 — 라벨은 읽는 쪽에 따라 다르다 (아래 주석)
  | 'runner_personal'    // 런엔드 enum 공유
  | 'peer_unreachable'   // ③-C 에서 빌린 하나 — 체크인에만 있는 진짜 사유
  | 'other';

export type StopReason = {
  key: StopReasonKey;
  label: string;
  /** true = 한 단계 더 (노트). ③-A: 탭 수는 사유마다 다르다. */
  needsNote: boolean;
};

// ⚠ 왜 목록이 읽는 쪽에 따라 다른가. `owner_request` 와 `runner_personal` 은 **누구의 사정인가**를
// 가르는 키다. 러너에게 「러너 개인 사정」은 자기 진술이지만, 보호자에게는 남의 사정에 대한 주장이고
// 그건 사유가 아니라 **다른 답**이다 (`other_side_absent`). 죽은 칩을 그리지 않는 것과 같은 법:
// 그 사람이 진실로 말할 수 없는 문장은 목록에 없다.
const RUNNER_REASONS: StopReason[] = [
  // END_REASONS 그대로 (club/run/[sid].tsx:48) — 「· 내용 필요」 표기까지 ③-A 프레임과 같다.
  { key: 'dog_condition', label: '아이 컨디션이 걱정돼요', needsNote: true },
  // 재작성된 한 줄. 원문은 「보호자 요청」.
  { key: 'owner_request', label: '보호자가 중단을 요청했어요', needsNote: false },
  { key: 'runner_personal', label: '러너 개인 사정', needsNote: false },
  // ③-C 에서 빌린 하나.
  { key: 'peer_unreachable', label: '상대방과 연락이 안 돼요', needsNote: false },
  { key: 'other', label: '그 외 — 직접 입력', needsNote: true },
];

const OWNER_REASONS: StopReason[] = [
  { key: 'dog_condition', label: '아이 컨디션이 걱정돼요', needsNote: true },
  // 보호자 쪽 `owner_request` = **자기** 사정. 3인칭 「보호자 요청」을 보호자에게 보여주면 자기
  // 이야기를 남의 이름으로 읽게 된다. ③-C 의 자기 진술 문형을 그대로 쓴다.
  { key: 'owner_request', label: '제 사정이 생겼어요', needsNote: false },
  { key: 'peer_unreachable', label: '상대방과 연락이 안 돼요', needsNote: false },
  { key: 'other', label: '그 외 — 직접 입력', needsNote: true },
];

export const stopReasonsFor = (side: CheckinSide): StopReason[] =>
  side === 'owner' ? OWNER_REASONS : RUNNER_REASONS;

export const stopReasonFor = (side: CheckinSide, key: StopReasonKey): StopReason | null =>
  stopReasonsFor(side).find((r) => r.key === key) ?? null;

/**
 * `p_reason` 에 실제로 실려 가는 문자열.
 *
 * ⚠ 결정 (이 슬라이스, 기록해 둔다): **사람이 실제로 고르고 쓴 말을 그대로 저장한다.** 키 코드를
 * 저장하지 않는 이유는 두 가지다. (1) §7 이 본인에게 자기 사유를 되돌려주고 surface 가 그걸
 * 그대로 보여준다 — 「runner_personal」이 돌아오면 그건 본인의 말이 아니라 우리 코드다.
 * (2) 0117 헤더가 이 컬럼의 목적을 「응급 중단과 변심을 나중에 사람이 구별할 수 있게」라고 적었고,
 * 그 독자는 사람이다 (`booking_faults.reason` 은 오늘 아무 코드도 읽지 않는다 — 0117:113-116).
 * 대가는 라벨이 바뀌면 과거 행과 문구가 갈린다는 것이고, 그건 아래 목록이 한 벌뿐이라는 사실과
 * 이 파일의 핀으로 관리한다.
 */
export function reasonTextFor(side: CheckinSide, key: StopReasonKey, note?: string | null): string | null {
  const r = stopReasonFor(side, key);
  if (r == null) return null;
  const body = (note ?? '').trim();
  if (!r.needsNote) return r.label;
  if (body.length === 0) return null;         // 노트가 필요한 사유는 노트 없이 보내지 않는다
  // 직접 입력은 사람의 문장이 곧 사유다 — 「그 외 —」를 앞에 붙이면 남의 말이 섞인다.
  return key === 'other' ? body : `${r.label} · ${body}`;
}

// ═══ 남은 시간 ═════════════════════════════════════════════════════════════════════════════
// lateness.sinceLabel 과 같은 문법이되 0 을 인쇄하지 않는다: 카운트다운에서 「0분 뒤 마감」은
// 반올림이 만든 거짓이고, 마감 직전이 정확히 사람이 서두르는 순간이다.
export function remainLabel(ms: number): string {
  if (ms <= 0) return '마감 시각이 지났어요';
  const min = Math.floor(ms / 60_000);
  if (min < 1) return '1분 미만';
  if (min < 60) return `${min}분`;
  const h = Math.floor(min / 60);
  const rem = min % 60;
  if (h < 24) return rem ? `${h}시간 ${rem}분` : `${h}시간`;
  return `${Math.floor(h / 24)}일`;
}

// ═══ 화면이 그리는 모든 문장, 한 함수에서 ═══════════════════════════════════════════════════
export type CheckinOption = { key: Affordance; label: string };

export type CheckinCopy = {
  kick: string;
  head: string;
  /** 마감까지 남은 시간. 모르면 null — 지어낸 카운트다운을 그리지 않는다. */
  sub: string | null;
  /** D5 불변식. 어떤 상태에서도 참이고 어떤 상태에서도 빠지지 않는다. */
  strip: string;
  /** 인계 전에만. 인계 후 `active` 는 마감이 아무것도 하지 않는다(superseded) — 그래서 생략한다. */
  terminalNote: string | null;
  options: CheckinOption[];
  /** 보호자 `cannot_proceed` 가 §6 에서 막히는 자리의 안내. 버튼이 아니라 문장이다. */
  cancelNote: string | null;
  /** 내 답이 이미 기록됐을 때. reason 은 **내 것**이므로 되돌려 보여준다. */
  mine: { line: string; reason: string | null; immutable: string } | null;
  /** 상대방이 무엇을 했는지. 텍스트는 절대 오지 않는다 (4B). */
  theirs: string | null;
  theirsReason: string | null;
};

const OTHER_LABEL: Record<CheckinSide, string> = { owner: '러너', runner: '보호자' };

const ABSENT_LABEL: Record<CheckinSide, string> = {
  owner: '러너가 오지 않았어요',
  runner: '보호자가 나오지 않았어요',
};

function optionLabel(a: Affordance, side: CheckinSide): string {
  if (a === 'proceeding') return '그대로 진행할게요';
  if (a === 'other_side_absent') return ABSENT_LABEL[side];
  return '진행할 수 없어요';
}

// 내 답의 메아리. 문자열 조작으로 만들지 않는다 — 조사 하나 틀리면 사람 이야기가 기계 말이 되고,
// 그 버그는 컴파일러가 절대 잡아주지 않는다. 네 문장을 그대로 적는다.
const MINE_ABSENT: Record<CheckinSide, string> = {
  owner: '러너가 오지 않았다고 답했어요',
  runner: '보호자가 나오지 않았다고 답했어요',
};

function mineLine(a: CheckinAnswerValue, side: CheckinSide): string {
  if (a === 'proceeding') return '진행하겠다고 답했어요';
  if (a === 'other_side_absent') return MINE_ABSENT[side];
  return '진행할 수 없다고 답했어요';
}

function theirsLine(a: CheckinAnswerValue | null, side: CheckinSide): string {
  const who = OTHER_LABEL[side];
  if (a == null) return `${who}는 아직 답하지 않았어요`;
  if (a === 'proceeding') return `${who}는 진행하겠다고 답했어요`;
  if (a === 'cannot_proceed') return `${who}는 진행할 수 없다고 답했어요`;
  // 거울 문장 — 상대가 지목한 것은 **나**다. 그걸 흐리면 화면이 사실을 감춘 게 된다.
  return side === 'owner' ? '러너는 보호자가 나오지 않았다고 답했어요' : '보호자는 러너가 오지 않았다고 답했어요';
}

/**
 * @param remainingMs `checkin.remainMs()` 의 결과 — 서버 시계에서 나온 값이다. 이 파일은 시계를
 *        갖지 않는다 (Date.now() 가 이 파일에 없는 이유).
 */
export function checkinCopy(
  state: CheckinState,
  side: CheckinSide,
  rawStatus: string | null | undefined,
  remainingMs: number | null,
): CheckinCopy | null {
  const row = state.row;
  if (row == null) return null;                        // 시계가 이 예약을 건드린 적이 없다
  if (!state.open || row.resolvedAt != null) return null; // 창은 닫혔다 — 이 표면은 답을 받는 표면이다

  const options = affordancesFor(state, side, rawStatus).map((key) => ({ key, label: optionLabel(key, side) }));
  const past = state.pastCeiling;
  const custody: CheckinCustody = state.custody;
  const mineAnswer = myAnswerOf(row, side);

  const kick = custody === 'post' ? '러닝을 멈출 수 있어요' : '예약 확인';
  const head = past
    // 천장을 넘겼다. 주어는 **답**이다 — 예약이 아니다 (파일 머리 2번).
    ? '예약 시각에서\n너무 오래 지났어요'
    : side === 'owner'
      ? '이 예약을\n그대로 진행하시나요?'
      : '이 러닝을\n그대로 진행하시나요?';

  const sub = past
    ? '이제는 진행하겠다는 답을 받을 수 없어요. 어떻게 됐는지만 알려주세요.'
    : remainingMs == null ? null : `${remainLabel(remainingMs)} 뒤 마감`;

  // D5 + 리졸버는 돈을 쓰지 않는다 (0117 §5). 침묵도, 답도, 이 프로토콜에서는 요금이 되지 않는다.
  const strip = '답하지 않아도 과실로 기록되지 않고, 수수료도 청구되지 않아요.';

  // 인계 전 마감은 언제나 종점을 쓴다(no_show 또는 incident_review) — 어느 쪽이든 이 예약은 더
  // 진행되지 않는다. 인계 후 `active` 는 마감이 아무것도 하지 않으므로(superseded) 말하지 않는다.
  const terminalNote = custody === 'pre' ? '마감되면 이 예약은 더 진행되지 않아요.' : null;

  // §6 의 use_cancel_path 를 미리 말해준다. 문 이름을 대되 그 문을 여기서 그리지는 않는다 —
  // 이 표면이 마운트된 화면이 이미 그 문을 갖고 있고, 여기에 또 그리면 값을 모르는 두 번째 출구다.
  const cancelNote =
    side === 'owner' && rawStatus === 'runner_enroute' && custody === 'pre' && mineAnswer == null
      ? '러너가 이미 출발했어요. 지금 중단하려면 예약 취소로 진행해 주세요 — 그래야 러너 보상이 함께 계산돼요.'
      : null;

  const mine = mineAnswer == null ? null : {
    line: mineLine(mineAnswer, side),
    // 내 사유는 내 것이다 — 되돌려 보여준다. 안 남겼으면 안 남겼다고만 말한다 (불리한 함의 금지).
    reason: mineAnswer === 'cannot_proceed'
      ? (myReasonOf(row, side) ?? '사유는 남기지 않았어요')
      : null,
    immutable: '한 번 보낸 답은 바꿀 수 없어요.',
  };

  const theirAnswer = theirAnswerOf(row, side);
  return {
    kick, head, sub, strip, terminalNote, options, cancelNote, mine,
    theirs: theirsLine(theirAnswer, side),
    // ⚠ 4B — **남겼다는 사실**만. 이 함수는 상대 텍스트를 인자로도 받지 않는다.
    theirsReason: theirHasReason(row, side) ? `${OTHER_LABEL[side]}가 사유를 남겼어요 — 내용은 본인만 볼 수 있어요.` : null,
  };
}

// ═══ 답을 막 보낸 직후 ═════════════════════════════════════════════════════════════════════
// `cannot_proceed` 는 같은 트랜잭션에서 체크인을 **해소**하므로, 답이 성공한 순간 `open` 은
// false 가 되고 위 checkinCopy 는 null 을 돌려준다. 그 자리에 아무것도 안 그리면 방금 답한 사람은
// **표면이 사라지는 것**만 본다 — 성공이 실패와 똑같이 생긴다. 그래서 이 함수가 있다.
//
// ⚠ 세션에서 방금 답했을 때만 그린다 (호출부의 로컬 플래그). 지난주에 종결된 예약의 시트를 열 때마다
// 이 블록이 뜨는 건 확인이 아니라 이력이고, 이력은 이 표면의 일이 아니다.
export type RecordedCopy = { head: string; line: string; reason: string | null; note: string | null };

export function recordedCopy(state: CheckinState, side: CheckinSide): RecordedCopy | null {
  const row = state.row;
  if (row == null) return null;
  const a = myAnswerOf(row, side);
  if (a == null) return null;

  // 해소 결과 → 문장. **서버가 실제로 쓰는 종점만** 말한다 (0117:645-683).
  //  · cannot_proceed + 인계 전 → no_show   · cannot_proceed + 인계 후(picked_up) → incident_review
  //  · void/ceiling → 종점이 no_show 이거나 incident_review 다 (증거 유무). 클라이언트는 어느 쪽인지
  //    알 수 없으므로 **어느 쪽이든 참인 말**만 한다 — 둘 중 하나를 고르면 절반은 거짓말이 된다.
  //  · superseded → 러닝이 이미 시작됐거나 다른 경로가 가져갔다. 이 체크인은 아무것도 바꾸지 않았다.
  let note: string | null = null;
  if (row.resolvedAt != null) {
    const r = row.resolution;
    if (r === 'cannot_proceed') {
      note = state.custody === 'post'
        ? '확인이 필요한 건으로 넘어갔어요 — 아이 상태를 확인해 주세요.'
        : '이 예약은 불발로 종결됐어요. 수수료는 청구되지 않았어요.';
    } else if (r === 'superseded') {
      note = '이 예약은 다른 경로로 이미 정리돼 있어서, 이 확인은 상태를 바꾸지 않았어요.';
    } else {
      note = '이 예약은 여기서 정리됐어요. 수수료는 청구되지 않았어요.';
    }
  } else {
    note = theirAnswerOf(row, side) == null ? '상대방의 답을 기다리는 중이에요.' : theirsLine(theirAnswerOf(row, side), side);
  }

  return {
    head: '답을 보냈어요',
    line: mineLine(a, side),
    reason: a === 'cannot_proceed' ? (myReasonOf(row, side) ?? '사유는 남기지 않았어요') : null,
    note,
  };
}

/** 스위트가 훑을 수 있게, 이 카피가 화면에 내보내는 문자열 전부. */
export function checkinCopyStrings(c: CheckinCopy): string[] {
  const out = [c.kick, c.head, c.strip, ...c.options.map((o) => o.label)];
  for (const v of [c.sub, c.terminalNote, c.cancelNote, c.theirs, c.theirsReason]) if (v) out.push(v);
  if (c.mine) { out.push(c.mine.line, c.mine.immutable); if (c.mine.reason) out.push(c.mine.reason); }
  return out;
}

export function recordedCopyStrings(c: RecordedCopy): string[] {
  const out = [c.head, c.line];
  if (c.reason) out.push(c.reason);
  if (c.note) out.push(c.note);
  return out;
}

// ═══ ③ 1단계: 위급 먼저 ═══════════════════════════════════════════════════════════════════
// Sean 이 고른 ③ 의 뼈대: 「지금 도움이 필요한가요?」를 **먼저** 묻는다. 사용자와 도움 사이에
// 게이트를 두지 않는다 — 위급을 구조적으로 앞에 두고, 가장 급한 사람이 가장 큰 버튼을 본다.
//
// ⚠ 여기 적힌 두 문장은 **오늘 아침 랩에서 한 번 거짓이었던 자리**다 (§8-bis 가 그 사고를 기록해
// 뒀다: 「운영팀이 바로 확인해요」). 진실은 정확히 이만큼이다:
//   · 119 는 `tel:` 링크일 때만 정직하다 — 기기 다이얼러가 열리는 것이지 앱이 신고하지 않는다.
//   · sendSOS 가 하는 전부는 상대방 `notifications` 행 하나다 (api.ts:3104). 운영팀은 없다.
export const TRIAGE = {
  head: '지금 도움이\n필요한가요?',
  sub: '아이나 러너가 다쳤다면 먼저 알려주세요.',
  callLabel: '119 전화',
  callSub: '전화 앱이 열려요 — 앱이 대신 신고하지는 않아요',
  sosLabel: '상대방에게 긴급 알림',
  sosSub: '상대방에게 알림 하나가 바로 가요',
  sosSending: '보내는 중...',
  sosSent: '상대방에게 긴급 알림을 보냈어요.',
  // 실패는 실패로 그린다 — 조용히 삼키면 화면이 '보냈다'고 읽힌다.
  sosFailed: '긴급 알림을 보내지 못했어요. 119 또는 직접 연락을 이용해 주세요.',
  /** ③ 프레임 그대로. */
  next: '아니요, 다른 이유예요',
  // SOS 를 이미 보냈다면 「아니요」는 거짓이 된다 — 그 사람은 방금 '네'라고 답했다. 라벨 하나가
  // 상태를 따라간다.
  nextAfterSos: '사유를 고를게요',
  /** ③ 원안은 「지금은 말하기 어려워요」였다. 랩이 스스로 정정했다: '지금은'은 나중에 쓸 수 있다는
   *  뜻인데 사유는 진술과 함께 **불변**이다. ③-A 프레임의 문구를 쓴다. */
  skip: '사유 없이 중단 알리기',
} as const;

/** ③-A 2단계 · 3단계(노트)의 문장. */
export const REASON_STEP = {
  kicker: '중단 사유',
  noteMark: '· 내용 필요',
  skip: TRIAGE.skip,
  back: '이유 다시 고르기',
  submit: '중단 알리기',
  submitting: '보내는 중...',
} as const;

export function noteStepFor(key: StopReasonKey): { head: string; label: string; placeholder: string } {
  if (key === 'dog_condition') {
    return {
      // runner/run.tsx:1600 과 **같은 문장**이다. 같은 것을 묻는 두 화면이 다른 말을 쓰면
      // 사람은 다른 것을 묻는다고 읽는다.
      head: '무엇을 보고 멈췄나요?',
      label: '관찰한 내용',
      placeholder: '예: 3km 지점부터 헐떡임이 심해지고 걸음을 멈춰서 그늘에서 쉬었어요',
    };
  }
  return { head: '어떤 이유인가요?', label: '직접 입력', placeholder: '예: 문 앞에서 20분 기다렸는데 아무도 나오지 않았어요' };
}

// ═══ §6 거부 토큰 → 화면 상태 ══════════════════════════════════════════════════════════════
// 일곱 토큰은 전부 **그려지는 상태**가 된다. 서버 문자열을 그대로 띄우는 알럿은 사용자에게
// 아무것도 알려주지 않으면서 앱이 부서진 것처럼 보이게 만든다.
export type CheckinRefusal = { token: CheckinToken; title: string; body: string };

const REFUSALS: Record<CheckinToken, { title: string; body: string }> = {
  // 창이 없다. 열린 적이 없거나(시계가 아직 안 켜졌다), 이미 사라졌다.
  checkin_not_open: {
    title: '지금은 확인 중인 질문이 없어요',
    body: '이 예약에 열린 확인이 없어요. 화면을 새로고침하면 최신 상태가 보여요.',
  },
  // 창이 닫혔다 — 늦은 답은 이미 난 결론을 되돌리지 않는다 (FM8).
  checkin_resolved: {
    title: '이 확인은 이미 정리됐어요',
    body: '마감이나 상대방의 답으로 확인이 끝나서 답이 기록되지 않았어요. 예약 상태를 확인해 주세요.',
  },
  // 한 번 쓴 답은 그대로 남는다 (per-side immutable, first write wins).
  answer_immutable: {
    title: '이미 답한 확인이에요',
    body: '먼저 보낸 답이 그대로 남아 있어요. 답은 한 번만 기록돼요.',
  },
  // 주어는 '답'이다 — 예약이 아니다 (파일 머리 2번).
  checkin_past_ceiling: {
    title: '진행하겠다는 답은 받을 수 없어요',
    body: '예약 시각에서 너무 오래 지났어요. 어떻게 됐는지 알려주는 답은 그대로 보낼 수 있어요.',
  },
  // 다른 경로가 이 예약을 이미 가져갔다 (취소·인계 등). 시끄럽게 거부되는 편이 조용히
  // 삼켜지는 것보다 낫다 — 삼켜지면 '고려된 것처럼' 읽힌다.
  not_late_eligible: {
    title: '이 예약은 이미 정리됐어요',
    body: '다른 경로로 예약 상태가 바뀌어서 확인에 답할 수 없어요. 최신 상태를 확인해 주세요.',
  },
  // 여기 도달하면 클라이언트 버그다. 그래도 사람에게는 사람 말로 말한다.
  reason_not_applicable: {
    title: '사유를 함께 보낼 수 없는 답이에요',
    body: '사유는 「진행할 수 없어요」에만 함께 기록돼요. 사유 없이 다시 답해 주세요.',
  },
  // §6 이 이름을 대준 문. 여기에 버튼을 만들지 않는 이유는 checkinCopy 의 cancelNote 와 같다.
  use_cancel_path: {
    title: '예약 취소로 진행해 주세요',
    body: '러너가 이미 출발해서, 여기서 끝내면 러너 보상이 계산되지 않아요. 예약 취소를 이용하면 수수료와 러너 보상이 함께 정리돼요.',
  },
};

export const refusalFor = (token: CheckinToken): CheckinRefusal => ({ token, ...REFUSALS[token] });

/** 실패 → 문장. 아는 토큰이 아니면 null 이고, 호출부는 자기 기존 실패 경로를 쓴다. */
export function checkinRefusalFrom(err: unknown): CheckinRefusal | null {
  const token = checkinTokenFrom(err);
  return token ? refusalFor(token) : null;
}
