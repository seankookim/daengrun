// ═══════════ 프로필 빈칸 행 — ruling #3, Sean 선택 ② (2026-08-21) ═══════════
// 정본: docs/labs/profile-nudge-lab.html ②.
//
// ⚠ 왜 코랄이 아닌가: ②는 홈에 사는 행이고, 홈의 코랄은 이미 예약 CTA 가 갖고 있다. 화면당
// 코랄 하나 법(DESIGN.md §5)이 그대로 적용되므로 이 행은 **잉크 아웃라인**이다 — 러너 홈에서
// 채팅이 코랄 대신 잉크가 된 것과 같은 해법이다. 랩의 ② 평결 상자가 이 충돌을 미리 적어뒀고,
// Sean 은 그걸 읽고 ②를 골랐다.
//
// ⚠ 첫 러닝 **후에만**, 그리고 차단하지 않는다 (ruling #3 의 세 조건 중 둘). 호출부가 지킨다.
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ProfileGap } from '../lib/api';
import { paper } from '../theme';
import { haptic } from '../lib/haptics';

/** 각 빈칸이 **러너에게 무엇을 바꾸는지**. 「프로필을 완성하세요」가 스팸인 이유는 이걸 말하지
 *  않기 때문이다 — 셋 다 러너가 실제로 보는 화면을 가리킨다. */
const GAP_LABEL: Record<ProfileGap, { t: string; s: string }> = {
  photo:      { t: '사진',      s: '러너 티켓에 얼굴이 떠요' },
  vaccines:   { t: '백신 정보', s: '인계할 때 러너가 확인해요' },
  doorDetail: { t: '현관 상세', s: '문 앞에서 헤매지 않아요' },
};

const TOTAL = 3;

// ⚠ 닫기 없음 (Sean 2026-08-21). 처음엔 일주일 스누즈를 달았는데 그가 뺐다 — 옳다: 이 세 칸은
// 러너가 실제로 겪는 결핍이고, 채워지면 행이 스스로 사라진다. 사라지는 조건이 이미 있는데 닫기를
// 더하면 '해결'과 '숨김'이 같은 모양이 된다.
export function ProfileGaps({ gaps, onOpen }: {
  gaps: ProfileGap[];
  onOpen: () => void;
}) {
  if (gaps.length === 0) return null; // 다 채워졌으면 사라진다 — 축하 배너를 만들지 않는다
  const done = TOTAL - gaps.length;

  return (
    <View style={s.wrap}>
      <Pressable
        onPress={() => { haptic('light'); onOpen(); }}
        style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
        accessibilityRole="button"
        accessibilityLabel={`프로필 ${gaps.length}칸 남았어요. ${gaps.map((g) => GAP_LABEL[g].t).join(', ')}`}
      >
        <View style={s.count}><Text style={s.countTx}>{gaps.length}</Text></View>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>프로필 {gaps.length}칸 남았어요</Text>
          <Text style={s.sub} numberOfLines={2}>
            {gaps.map((g) => GAP_LABEL[g].t).join(' · ')} — 러너가 보는 것들이에요
          </Text>
          {/* 진행 막대는 장식이 아니라 사실이다: 3칸 중 몇 칸. 0칸일 때는 이 행 자체가 없다. */}
          <View style={s.bar}><View style={[s.barFill, { width: `${(done / TOTAL) * 100}%` }]} /></View>
        </View>
        <Text style={s.chev}>›</Text>
      </Pressable>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { marginTop: 10 },
  // 잉크 아웃라인 — 코랄은 예약 CTA 의 것이다 (위 주석).
  row: {
    flexDirection: 'row', alignItems: 'center', gap: 11,
    borderWidth: 1.5, borderColor: paper.ink, backgroundColor: paper.canvas,
    paddingVertical: 12, paddingHorizontal: 13,
  },
  count: {
    width: 26, height: 26, borderWidth: 1.5, borderColor: paper.ink,
    alignItems: 'center', justifyContent: 'center',
  },
  countTx: { fontSize: 14, fontWeight: '900', color: paper.ink },
  title: { fontSize: 15.5, fontWeight: '800', color: paper.ink, letterSpacing: -0.2 },
  sub: { fontSize: 12.5, color: paper.dim, marginTop: 2, lineHeight: 17 },
  bar: { height: 4, backgroundColor: '#EDECE7', marginTop: 7 },
  barFill: { height: 4, backgroundColor: paper.action },
  chev: { fontSize: 19, color: paper.faint, alignSelf: 'center' },
});
