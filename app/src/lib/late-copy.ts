// ═══════════ 지각 알림 문장 (late/unresponsive reservation, stage 1) ═══════════
// 정본: docs/labs/late-booking-lab.html (Sean 승인 2026-08-21) · 계획 §15 T3.
//
// 이 파일이 하는 일 하나: 지각 판정과 보는 사람을 받아 화면이 그릴 문장을 고른다.
// 인계 전은 '불발'이라 말해도 되고 인계 후는 절대 안 된다 (0066:50 이 picked_up → no_show 를
// 거부한다 — 개가 러너에게 있는데 '불발'이라 부르는 건 DB가 거절하는 말을 화면이 하는 것).
//
// ⚠ 왜 src/lib 인가: 문장이 곧 법이다. react-native 를 import 하는 컴포넌트 안에 매핑을 두면
// .cjs 스위트가 실제 소스를 번들할 수 없어 이 인계선을 테스트로 핀 박을 수 없다. 판정은
// lateness.ts, 문장은 이 파일, 렌더링은 late-notice.tsx 가 맡는다.
import { sinceLabel, type Lateness } from './lateness';

export type LateSide = 'owner' | 'runner';

export type LateCopy = { kick: string; head: string; tone: 'warn' | 'critical'; strip?: string };

/** 상태 → 문장. 데이터만 돌려준다 — JSX도 화면 의존성도 없다. */
export function copyFor(
  late: Lateness,
  side: LateSide,
  names: { dog?: string; runner?: string },
): LateCopy {
  const dog = names.dog ?? '반려견';
  const runner = names.runner ?? '러너';
  const since = sinceLabel(late.sinceMs);

  // ── 인계 후: 개가 러너에게 있다. '불발'이라는 낱말은 여기서 금지어다. 확인과 도움만 말한다.
  if (late.custody === 'post') {
    // ⚠ [codex 2026-08-21] picked_up 과 active 를 한 문장으로 뭉치면 거짓말이 된다. 10:00 예약을
    // 10:11 에 인계받았는데 10:12 에 「아직 돌아오지 않았어요」가 뜬다 — 방금 데려간 개다.
    // picked_up = 아직 출발 안 함 · active = 나갔는데 안 돌아옴. 다른 사실, 다른 문장.
    // ⚠ [Sean 2026-08-21] 「확인이 필요해요」는 **누군가 확인할 것**이라는 뜻으로 읽힌다. 그런데
    // 인계 후에는 그 누군가가 없다: 0117 의 세 진입점이 전부 인계 전 전용이라(open_checkin ·
    // 스윕 두 팔), 이미 나가 있는 러닝은 프로토콜에 아예 들어오지 않는다. 끝나지 않는 러닝은
    // run-end recovery 를 넓히는 별도 슬라이스로 갔다.
    // 그래서 문장이 바뀐다: 지켜보는 주체를 암시하지 않고, 행동을 읽는 사람에게 준다.
    // 사실이 틀린 게 아니라(러닝은 정말 늦었다) '처리되고 있다'는 함의가 거짓이었다.
    if (late.custody === 'post' && !late.started) {
      return side === 'owner'
        ? { kick: '직접 확인해 주세요', head: `${dog}와의 러닝이\n아직 시작되지 않았어요`, tone: 'warn',
            strip: '자동으로 정리되지 않아요 — 러너에게 연락해 주세요.' }
        : { kick: `${since} 지남`, head: '아직 러닝을\n시작하지 않았어요', tone: 'warn' };
    }
    return side === 'owner'
      ? { kick: '직접 확인해 주세요', head: `${dog}가 아직\n돌아오지 않았어요`, tone: 'critical',
          strip: '자동으로 확인되지 않아요 — 러너에게 연락하거나 긴급 도움을 요청하세요.' }
      // [랩 교정 ⑥] 목업은 「아직 달리는 중인가요?」라는 질문이었다. stage 1 은 답을 받을 수
      // 없으므로 질문형은 작은 거짓말이다 (물어놓고 답 칸이 없다). 서술형으로 바꾼다.
      : { kick: `예상보다 ${since} 초과`, head: '러닝이\n길어지고 있어요', tone: 'warn',
          // 보호자도 같은 사실을 본다는 건 참이다. 다만 '그래서 누군가 처리한다'는 함의는 빼둔다 —
          // 인계 후 러닝을 지켜보는 서버 감시자는 아직 없다.
          strip: '보호자 화면에도 같은 사실이 보여요. 문제가 있으면 직접 알려주세요.' };
  }

  // ── 인계 전, 보호자를 기다리는 중 (러너가 도착 표시를 찍었다)
  if (late.waitingOn === 'owner') {
    return side === 'owner'
      // ⚠ [codex 2026-08-21] 첫 판은 양쪽에 「보상돼요」라고 적었다. 스테이지 1 은 그걸 줄 수 없다 —
      // 서버 보상은 보호자가 **실제로 runner_enroute 예약을 취소할 때만** 기록된다
      // (transition-booking/cancel_owner.ts:99). arrived_at 이 있다는 이유로 자동으로 생기지 않는다.
      // 막힌 리졸버가 주지 못하는 결과를 화면이 약속하면, 그건 오늘 아침 고친 수수료 거짓말과 같은 종류다.
      ? { kick: '지금 기다리는 중', head: `${runner}님이\n문 앞에서 기다려요`, tone: 'critical',
          strip: '지금 취소하면 취소 수수료가 붙어요 — 일정에서 조건을 확인하세요.' }
      // waitMs — 늦음이 아니라 **서 있던 시간**. sinceMs 를 쓰면 5분 기다린 러너에게 30분이라 말한다.
      : { kick: `${sinceLabel(late.waitMs)}째 대기 중`, head: '보호자가 아직\n나오지 않았어요', tone: 'warn',
          strip: '떠나기 전에 한 번 더 알려주세요.' };
  }

  // ── 천장을 넘겼다: 이건 '늦은 예약'이 아니라 끝난 일이다. 진행을 암시하지 않는다.
  // (resumable 은 여기서 소비된다 — 아무도 읽지 않는 필드는 아무도 검사하지 않는 계약이다,
  //  codex 2026-08-21. 인계 후는 위에서 이미 처리됐으므로 여기 도달하면 인계 전이다.)
  if (!late.resumable) {
    return side === 'owner'
      ? { kick: `${since} 지남`, head: '이 예약은\n진행되지 않았어요', tone: 'warn',
          strip: '지금은 진행할 수 없어요 — 일정에서 정리하거나 다시 예약해 주세요.' }
      : { kick: `${since} 지남`, head: '이 예약은\n진행할 수 없어요', tone: 'warn',
          strip: '너무 오래 지나 시작할 수 없어요.' };
  }

  // ── 인계 전, 러너를 기다리는 중
  return side === 'owner'
    ? { kick: '예약 시각이 지났어요', head: '러너가 아직\n도착하지 않았어요', tone: 'warn' }
    : { kick: `${since} 늦음`, head: `${dog}가\n기다리고 있어요`, tone: 'critical' };
}
