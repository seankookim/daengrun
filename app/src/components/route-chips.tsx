// 코스 제약 칩 — 술어·개수 배지·AND 의미·조명 자동켜짐의 **유일한 주인** (K5 · 0082).
//
// ═══ 왜 컴포넌트인가 ═══
// 이 규칙은 request.tsx와 course-map.tsx **두 곳에 복제돼** 있었다. 복제된 건 스타일이 아니라
// **술어**다 — 칩 라벨은 "흙길"이라고 말하는데 한쪽 술어만 60% 문턱을 들고 있으면, 그 순간부터
// 라벨이 거짓말을 시작한다. 필터가 거르는 것과 카피가 주장하는 것은 한 곳에서만 정의된다.
//
// 갈라져 있던 실제 증거 두 개(둘 다 여기서 닫힌다):
//  ① 라벨: request.tsx '그늘 많음' vs course-map.tsx '그늘'. 같은 술어(shade === 'high')에
//     이름이 둘이었다. '그늘 많음'으로 통일한다 — 술어를 말하는 쪽이 이긴다.
//  ② 조명 자동켜짐: request.tsx에만 있었다. 지도 화면은 **이미 슬롯이 정해진 뒤** 들어오는
//     화면인데, 새벽 05시 예약으로 들어와도 조명 필터가 꺼진 채였다. 안전 필터가 화면마다
//     달리 켜지는 것은 그 자체로 정직성 버그다. 훅이 draft를 읽으므로 양쪽에서 같이 켜진다.
//
// ═══ 하드 필터지 가중치가 아니다 ═══
// AND 의미. 가중 스코어링은 PR-0이 검증된 뒤의 일(T2)이고, 지금은 관측된 선호 데이터가 0이라
// 가중치가 곧 창업자의 직감이 된다.
import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { haptic } from '../lib/haptics';
import { RouteInfo, draft } from '../store';
import { paper } from '../theme';

export type RouteChips = { dirt: boolean; shade: boolean; lit: boolean };
export type ChipKey = keyof RouteChips;
export const NO_CHIPS: RouteChips = { dirt: false, shade: false, lit: false };

// terrain은 '흙길 70%' / '포장 90%' 형태의 자유 문자열이라 숫자를 뽑아 60% 문턱을 건다.
export const dirtPct = (t: string) => (t.startsWith('흙길') ? Number(t.replace(/[^0-9]/g, '')) || 0 : 0);

// 칩 정의 — 라벨·힌트·술어·빈 결과 수식어가 한 행에 붙어 있다. 라벨을 고치면서 술어를
// 안 고치는 일이 물리적으로 불가능하도록.
const CHIPS: { key: ChipKey; label: string; hint: string; modifier: string; ok: (r: RouteInfo) => boolean }[] = [
  { key: 'lit', label: '조명', hint: '야간 조명 있음', modifier: '조명 있는', ok: (r) => r.lighting === 'lit' },
  { key: 'shade', label: '그늘 많음', hint: '그늘 최상', modifier: '그늘 많은', ok: (r) => r.shade === 'high' },
  { key: 'dirt', label: '흙길', hint: '흙길 60% 이상', modifier: '흙길', ok: (r) => dirtPct(r.terrain) >= 60 },
];

/** AND. null(shade/lighting 미기록)은 '해당 없음'이 아니라 '모른다'이므로 통과시키지 않는다. */
export function matchesChips(r: RouteInfo, c: RouteChips): boolean {
  return CHIPS.every((x) => !c[x.key] || x.ok(r));
}

/** 이 칩을 **켜면** 몇 개가 남는지 — 0으로 만드는 칩을 누르기 전에 라벨에 보인다. */
export function chipCountIfOn(routes: RouteInfo[], c: RouteChips, key: ChipKey): number {
  return routes.filter((r) => matchesChips(r, { ...c, [key]: true })).length;
}

/** 예약 시각의 '어두운 슬롯' — 새벽(~07시) / 야간(21시~). */
export function isDarkSlot(iso: string | null | undefined): boolean {
  if (!iso) return false;
  const h = new Date(iso).getHours();
  return h < 7 || h >= 21;
}

/**
 * 결과가 0일 때의 카피. 켜진 칩을 **전부** 이름 대서 읽는다 — 예전 버전은 흙길+그늘을 켰을 때
 * '그늘 많은 코스가 아직 없어요'라고만 말해 흙길 조건을 통째로 숨겼고, 칩이 하나도 안 켜진
 * 빈 목록에도 '흙길 코스가 아직 없어요'라고 말했다(거짓). 둘 다 여기서 닫힌다.
 */
export function emptyChipCopy(c: RouteChips): string {
  const on = CHIPS.filter((x) => c[x.key]);
  if (on.length === 0) return '표시할 코스가 없어요';
  return `${on.map((x) => x.modifier).join(' ')} 코스가 아직 없어요`;
}

/**
 * 칩 상태 + 어두운 슬롯 자동켜짐. **훅이 규칙을 소유한다** — 화면은 값만 그린다.
 * 안전에 관한 유일한 필터를 opt-in으로 두면, 새벽 05시를 고른 보호자가 조명 없는 숲길을
 * 배정받고도 아무 말을 듣지 못한다. 사용자가 끄면 그 뜻은 존중된다(다시 켜지지 않는다).
 */
export function useRouteChips() {
  const [chips, setChips] = useState<RouteChips>(NO_CHIPS);
  const [litAuto, setLitAuto] = useState(false);
  // memo를 걸지 않는다: draft.scheduledAtIso는 스토어의 평범한 필드라 구독이 없고, 시각이
  // 바뀌면 그걸 바꾼 화면의 state가 어차피 리렌더를 부른다. 매 렌더 Date 하나 값이다.
  const darkSlot = isDarkSlot(draft.scheduledAtIso);

  useEffect(() => {
    if (darkSlot && !chips.lit) { setChips((c) => ({ ...c, lit: true })); setLitAuto(true); }
    if (!darkSlot && litAuto) { setChips((c) => ({ ...c, lit: false })); setLitAuto(false); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [darkSlot]);

  const toggle = (key: ChipKey) => {
    haptic('light');
    setChips((v) => ({ ...v, [key]: !v[key] }));
    if (key === 'lit') setLitAuto(false); // 손으로 만졌으면 더는 '자동'이 아니다
  };
  const clear = () => { setChips(NO_CHIPS); setLitAuto(false); };

  return { chips, toggle, clear, litAuto, darkSlot };
}

/**
 * 칩 행. 두 소비처는 **면**이 다르다(문서 위 / 지도 위 부유) — 그건 variant로 가르고,
 * 라벨·개수·a11y·선택 표현은 여기 한 곳에만 있다.
 */
export function RouteChipRow({
  routes, chips, litAuto, onToggle, variant = 'inline', style,
}: {
  routes: RouteInfo[];
  chips: RouteChips;
  litAuto?: boolean;
  onToggle: (key: ChipKey) => void;
  /** inline = 문서 위(코랄 1.5px) · floating = 지도 위(그림자 얹은 캔버스 칩) */
  variant?: 'inline' | 'floating';
  style?: ViewStyle;
}) {
  const floating = variant === 'floating';
  return (
    <View style={[s.row, style]}>
      {CHIPS.map((c) => {
        const on = chips[c.key];
        const n = chipCountIfOn(routes, chips, c.key);
        return (
          <Pressable
            key={c.key}
            onPress={() => onToggle(c.key)}
            accessibilityRole="button"
            accessibilityState={{ selected: on }}
            accessibilityLabel={`${c.label} — ${c.hint}, ${n}개 코스${on ? ', 적용됨' : ''}`}
            style={[floating ? s.floatChip : s.inlineChip, on && s.chipOn]}
          >
            <Text style={[s.chipTxt, on && { color: '#FFFFFF' }]}>{c.label} {n}</Text>
          </Pressable>
        );
      })}
      {chips.lit && litAuto && (
        <View style={floating ? s.autoPlate : undefined}>
          <Text style={s.autoTxt}>어두운 시간대라 켰어요</Text>
        </View>
      )}
    </View>
  );
}

const CHIP_BASE: ViewStyle = {
  paddingHorizontal: 12,
  minHeight: 44,            // 44pt 터치 타깃 (a11y 계약)
  justifyContent: 'center',
  alignSelf: 'flex-start',
};

const s = StyleSheet.create({
  row: { flexDirection: 'row', gap: 7, flexWrap: 'wrap', alignItems: 'center' },
  inlineChip: { ...CHIP_BASE, backgroundColor: '#FFFFFF', borderWidth: 1.5, borderColor: paper.line },
  floatChip: {
    ...CHIP_BASE, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EDEBE6',
    shadowColor: '#000', shadowOpacity: 0.07, shadowRadius: 8, shadowOffset: { width: 0, height: 2 }, elevation: 2,
  },
  // 잉크 fill = **선택 상태**지 누르는 면이 아니다 (paper-btn의 법과 같은 이유로 코랄 금지)
  chipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  chipTxt: { fontSize: 14, fontWeight: '800', color: paper.text },
  autoPlate: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EDEBE6',
    paddingHorizontal: 8, paddingVertical: 5, justifyContent: 'center',
  },
  autoTxt: { fontSize: 14, color: paper.dim, fontWeight: '700' },
});
