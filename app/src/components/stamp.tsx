import { StyleSheet, Text, TextStyle, View } from 'react-native';
import { Dimensions } from 'react-native';
import { StampInfo } from '../lib/api';
import { lilac } from '../theme';

// ══════════ 도장 프리미티브 (리워드 ② · 랩 Ⓐ①) — 마이 §③ · 컬렉션 부속서 공용 ══════════
// [추출 2026-08-05] StampCell이 my.tsx·cards.tsx에 바이트 동일 2벌 존재했고, 병렬 빌더가 각자
// 기울기를 해시해 11/12 도장이 화면마다 다르게 기울던 사고의 재발 방지 — 프리미티브는 한 곳에만 산다.
// (report.tsx의 StampDisc는 나이트 세리머니 변형 — 애니메이션 배선이 달라 별도 유지, 각도만 같은 정본을 쓴다.)
//
// 잉크 법(랩 확정): 바이올렛 #4A3DA8이 유일한 도장 잉크 · 코랄은 첫-가족의 '엣지+도트'로만 ·
// 골드는 영수증 소인 전용 · 포일 0. 사다리는 색조가 아니라 링 개수로 오른다 (1 첫 등급 · 2 마일스톤 · 3 꼭대기).
export const STAMP_INK = '#4A3DA8'; // 읽는 바이올렛 — 흰 카드 위 8.32:1
export const STAMP_INK_FILL = 'rgba(108,92,231,0.05)'; // accent 5% — 종이에 잉크가 스민 자국

// 도장 그리드 폭 예산 (두 화면이 같은 산술을 쓰므로 여기가 정본):
//   스크롤 패딩 16*2 · 카드 보더 1*2 · 내부 마진 9*2 · 내부 보더 1*2 · 내부 패딩 11*2 = W-76
//   320dp: 244 → 칸 74 · 디스크 68 (3*74+2*10 = 242 ≤ 244 ✓) · 360dp: 284/87/76 ✓ · 390dp: 314/97/76 (랩 실측) ✓
//   디스크가 68까지 줄어도 내부 활자(27+1+17 = 45)는 15pt 플로어 아래로 내려가지 않는다.
export const STAMP_GAP = 10;
export const STAMP_CELL_W = Math.floor((Dimensions.get('window').width - 76 - STAMP_GAP * 2 - 1) / 3);
export const STAMP_DISC = Math.min(76, STAMP_CELL_W - 6);

// 도장 한 칸. v1에서 눌리지 않는다 — 상세 화면이 없고, 목적지 없는 탭은 죽은 버튼이다.
// 기울기는 deriveStamps의 고정 각도(info.angle) 그대로 — 화면이 따로 계산하면 같은 도장이 다르게 기운다.
// 받은 칸은 이름을, 빈 칸은 실진행(있으면)을, 진행이 뜻없는 1회짜리는 조건을 말한다.
export function StampCell({ info, nf }: { info: StampInfo; nf: TextStyle | null }) {
  const on = info.earned;
  return (
    <View style={s.scell}>
      <View
        style={[
          s.disc,
          on ? (info.coral ? s.discCoral : s.discOn) : s.discOff,
          on && { transform: [{ rotate: `${info.angle}deg` }] },
        ]}
      >
        {on && info.rings >= 2 && <View style={[s.ring2, info.rings >= 3 && s.ring2Top, info.coral && s.ring2Coral]} />}
        {on && info.rings >= 3 && <View style={s.ring3} />}
        {on && info.coral && <View style={s.dot1} />}
        <Text style={[s.discN, nf, !on && s.discInkOff]}>{info.num}</Text>
        <Text style={[s.discW, !on && s.discInkOff]}>{info.word}</Text>
      </View>
      <Text style={[s.scellCond, on && s.scellCondOn]} numberOfLines={2}>
        {on ? info.label : (info.prog ?? info.cond)}
      </Text>
    </View>
  );
}

const s = StyleSheet.create({
  // minHeight는 두 화면의 기존 값(마이 +46 / 부속서 +48) 중 넉넉한 쪽으로 통일 — 스크롤 콘텐츠라 예산 무관
  scell: { width: STAMP_CELL_W, minHeight: STAMP_DISC + 48, alignItems: 'center' },
  disc: { width: STAMP_DISC, height: STAMP_DISC, borderRadius: STAMP_DISC / 2, alignItems: 'center', justifyContent: 'center' },
  discOn: { borderWidth: 2, borderColor: STAMP_INK, backgroundColor: STAMP_INK_FILL },
  discCoral: { borderWidth: 2, borderColor: lilac.coralDeep, backgroundColor: STAMP_INK_FILL }, // 첫-가족 — 코랄은 엣지로만
  discOff: { borderWidth: 1.5, borderStyle: 'dashed', borderColor: lilac.hair },
  ring2: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderRadius: (STAMP_DISC - 8) / 2, borderWidth: 1.5, borderColor: STAMP_INK, opacity: 0.85 },
  ring2Top: { opacity: 0.9 },
  ring2Coral: { borderColor: lilac.coralDeep, opacity: 0.34 },
  ring3: { position: 'absolute', top: -5, left: -5, right: -5, bottom: -5, borderRadius: (STAMP_DISC + 10) / 2, borderWidth: 1.5, borderColor: STAMP_INK, opacity: 0.55 },
  dot1: { position: 'absolute', top: -3.5, left: (STAMP_DISC - 7) / 2, width: 7, height: 7, borderRadius: 3.5, backgroundColor: lilac.coralDeep },
  discN: { fontSize: 22, lineHeight: 27, fontWeight: '800', color: STAMP_INK }, // Oswald — lineHeight 1.23× (BUG A)
  discW: { fontSize: 15, lineHeight: 18, fontWeight: '800', color: STAMP_INK, marginTop: 1 },
  discInkOff: { color: lilac.dim }, // 미획득 잉크 — 랩의 #A9A3C8(2.40:1) 대신 lilac.dim(4.24:1)
  scellCond: { fontSize: 15, lineHeight: 18, fontWeight: '600', color: lilac.dim, marginTop: 6, textAlign: 'center' },
  scellCondOn: { fontWeight: '700', color: lilac.head },
});
