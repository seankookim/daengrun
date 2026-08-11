import { Text, View, ViewStyle } from 'react-native';
import { PatchGrade } from '../lib/api';

// 코스 패치 배지 — 완료 카드 미니(40) · 패치 월(104) 공용.
// P2 배지 월드 (Sean 확정 컬러 리바이탈라이즈): 거리 등급 = 색 세계, 완주 횟수 등급 = 재질.
//   월드: 3K TRAIL 테라 → 5K FOREST 볼트 → 7K RIVER 스카이 → 10K NIGHT 바이올렛 → 하프+ GOLD
//   재질: basic(월드색 대시 스티치) → silver(×5 실버 솔리드) → gold(×10 골드 솔리드) →
//         master(×25 월드색 글로우 + ★)
//   수집욕 = 색을 모으는 욕구 — 패치 월이 진짜 배지 보드가 된다.

export interface PatchWorld { label: string; bg: string; tone: string; dim: string }
export const worldOf = (km: number): PatchWorld =>
  km <= 3.5 ? { label: 'TRAIL', bg: '#2A1811', tone: '#E08A5F', dim: 'rgba(224,138,95,.55)' }
  : km <= 5.5 ? { label: 'FOREST', bg: '#0F1D13', tone: '#C6F542', dim: 'rgba(198,245,66,.55)' }
  : km <= 8 ? { label: 'RIVER', bg: '#0F2029', tone: '#5BB8D4', dim: 'rgba(91,184,212,.55)' }
  : km <= 14 ? { label: 'NIGHT', bg: '#1A1433', tone: '#9B8CE8', dim: 'rgba(155,140,232,.55)' }
  : { label: 'HALF', bg: '#332D14', tone: '#F2DA96', dim: 'rgba(242,218,150,.55)' };

const stitchOf = (grade: PatchGrade, w: PatchWorld): { color: string; solid: boolean } =>
  grade === 'basic' ? { color: w.dim, solid: false }
  : grade === 'silver' ? { color: 'rgba(201,205,212,.9)', solid: true }
  : grade === 'gold' ? { color: 'rgba(242,218,150,.95)', solid: true }
  : { color: w.tone, solid: true }; // master — 월드색 풀 스티치

export function PatchBadge({ km, name, grade, size = 40, style }: {
  km: number; name?: string; grade: PatchGrade; size?: number; style?: ViewStyle;
}) {
  const w = worldOf(km);
  const st = stitchOf(grade, w);
  const glow = grade === 'master';
  const kmSize = size * 0.26;
  const nameSize = size * 0.085;
  return (
    <View
      style={[{
        width: size, height: size, borderRadius: size / 2, backgroundColor: w.bg,
        alignItems: 'center', justifyContent: 'center',
        shadowColor: glow ? w.tone : '#0F1D13',
        shadowOpacity: glow ? 0.6 : 0.3,
        shadowRadius: glow ? size * 0.16 : size * 0.08,
        shadowOffset: { width: 0, height: glow ? 0 : 2 },
      }, style]}
    >
      {/* 스티치 링 — 재질이 등급, 색이 월드 */}
      <View style={{
        position: 'absolute', top: size * 0.06, left: size * 0.06, right: size * 0.06, bottom: size * 0.06,
        borderRadius: size / 2, borderWidth: Math.max(1.2, size * 0.018),
        borderColor: st.color, borderStyle: st.solid ? 'solid' : 'dashed',
      }} />
      {grade === 'master' && (
        <Text style={{ position: 'absolute', top: -size * 0.13, fontSize: size * 0.2, color: st.color }}>★</Text>
      )}
      <Text style={{ fontSize: kmSize, fontWeight: '900', color: w.tone, lineHeight: kmSize * 1.1 }}>
        {km}K
      </Text>
      {size >= 60 && (
        <Text style={{ fontSize: Math.max(6, size * 0.075), fontWeight: '800', letterSpacing: 1.2, color: w.dim, marginTop: 1 }}>
          {w.label}
        </Text>
      )}
      {name != null && size >= 60 && (
        <Text numberOfLines={1} style={{ fontSize: Math.max(7, nameSize * 1.2), fontWeight: '800', color: '#c9d4c0', marginTop: 1, maxWidth: size * 0.8, textAlign: 'center' }}>
          {name}
        </Text>
      )}
    </View>
  );
}
