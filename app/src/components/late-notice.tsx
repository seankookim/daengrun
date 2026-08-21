// ═══════════ 지각 알림 — 예약이 늦었을 때 양쪽이 보는 한 덩어리 ═══════════
// 정본: docs/labs/late-booking-lab.html (Sean 승인 2026-08-21) · 계획 §15 T3.
//
// 화면 여섯 개가 아니라 **컴포넌트 하나**인 이유: 문장이 곧 법이기 때문이다.
// 인계 전은 '불발'이라 말해도 되고 인계 후는 절대 안 된다 (0066:50 이 picked_up → no_show 를
// 거부한다 — 개가 러너에게 있는데 '불발'이라 부르는 건 DB가 거절하는 말을 화면이 하는 것).
// 이 매핑이 네 화면에 복제되면 한 곳만 고쳐지고 나머지가 거짓말하는 날이 온다.
// (오늘 아침 E6 가 정확히 그렇게 세 입구 중 둘만 고쳐졌다.)
//
// ⚠ 이 컴포넌트는 **답을 받지 않는다.** 「아직 진행하나요?」 확인은 stage 2 다 — 답을 저장할
// booking_checkins 가 아직 없다. 여기 있는 버튼은 전부 오늘 이미 동작하는 것들이고,
// 호출자가 넘긴다. 없는 동작을 그리면 그게 죽은 버튼이다 (C1 법).
//
// ⚠ 코랄 하나 법: 이 컴포넌트는 primary 를 **스스로 만들지 않는다**. actions 를 호출자가
// 조립하므로 화면당 코랄 한 개를 지키는 책임도 호출자에게 있다 (PaperBtn 의 계약과 동일).
import { StyleSheet, Text, View } from 'react-native';
import { sinceLabel, type Lateness } from '../lib/lateness';
import { paper } from '../theme';

export type LateSide = 'owner' | 'runner';

type Copy = { kick: string; head: string; tone: 'warn' | 'critical'; strip?: string };

/** 상태 → 문장. 이 함수가 이 파일의 전부다. */
function copyFor(late: Lateness, side: LateSide, names: { dog?: string; runner?: string }): Copy {
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

  // ── 인계 전, 러너를 기다리는 중
  return side === 'owner'
    ? { kick: '예약 시각이 지났어요', head: '러너가 아직\n도착하지 않았어요', tone: 'warn' }
    : { kick: `${since} 늦음`, head: `${dog}가\n기다리고 있어요`, tone: 'critical' };
}

// ⚠ whenLabel·actions 프롭 제거 (codex 2026-08-21): 네 마운트 어디서도 넘기지 않는 죽은 계약이었다.
// 아무도 쓰지 않는 프롭은 아무도 검사하지 않는 약속이다. 필요해지면 그때 되살린다.
export function LateNotice({ late, side, dogName, runnerName }: {
  late: Lateness;
  side: LateSide;
  dogName?: string;
  runnerName?: string;
}) {
  if (!late.late) return null; // 늦지 않았으면 아무것도 그리지 않는다
  const c = copyFor(late, side, { dog: dogName, runner: runnerName });
  const accent = c.tone === 'critical' ? paper.critical : paper.pending;

  return (
    <View style={s.wrap} accessibilityRole="summary">
      <View style={s.kickRow}>
        <View style={[s.dot, { backgroundColor: accent }]} />
        <Text style={[s.kick, { color: accent }]}>{c.kick}</Text>
      </View>
      <Text style={s.head}>{c.head}</Text>
      {c.strip ? (
        <View style={[s.strip, { backgroundColor: c.tone === 'critical' ? paper.criticalWash : '#FBEED9',
          borderColor: c.tone === 'critical' ? '#F0CFC6' : '#F2DFC2' }]}>
          <Text style={[s.stripText, { color: c.tone === 'critical' ? '#8C3722' : '#7A4A0C' }]}>{c.strip}</Text>
        </View>
      ) : null}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { paddingVertical: 14 },
  kickRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 5 },
  dot: { width: 7, height: 7, borderRadius: 3.5 },
  kick: { fontSize: 12, fontWeight: '800', letterSpacing: 0.6 },
  head: { fontSize: 25, fontWeight: '900', letterSpacing: -0.5, lineHeight: 30, color: paper.ink },
  strip: { borderWidth: 1, padding: 10, marginTop: 11 },
  stripText: { fontSize: 12.5, lineHeight: 18, fontWeight: '600' },
});
