// ═══════════ 지각 알림 — 예약이 늦었을 때 양쪽이 보는 한 덩어리 ═══════════
// 정본: docs/labs/late-booking-lab.html (Sean 승인 2026-08-21) · 계획 §15 T3.
//
// 화면 여섯 개가 아니라 **컴포넌트 하나**인 이유: 문장이 곧 법이기 때문이다.
// 문장 매핑은 lib/late-copy 에서 한 번만 고른다. 이 컴포넌트가 네 화면에 복제되면 한 곳만
// 고쳐지고 나머지가 거짓말하는 날이 온다.
// (오늘 아침 E6 가 정확히 그렇게 세 입구 중 둘만 고쳐졌다.)
//
// ⚠ 이 컴포넌트는 **답을 받지 않는다.** 「아직 진행하나요?」 확인은 stage 2 다 — 답을 저장할
// booking_checkins 가 아직 없다. 여기 있는 버튼은 전부 오늘 이미 동작하는 것들이고,
// 호출자가 넘긴다. 없는 동작을 그리면 그게 죽은 버튼이다 (C1 법).
//
// ⚠ 코랄 하나 법: 이 컴포넌트는 primary 를 **스스로 만들지 않는다**. actions 를 호출자가
// 조립하므로 화면당 코랄 한 개를 지키는 책임도 호출자에게 있다 (PaperBtn 의 계약과 동일).
import { StyleSheet, Text, View } from 'react-native';
import { copyFor, type LateSide } from '../lib/late-copy';
import type { Lateness } from '../lib/lateness';
import { paper } from '../theme';

export type { LateSide } from '../lib/late-copy';

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
