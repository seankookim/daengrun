import { Text, View, ViewStyle } from 'react-native';
import { PatchGrade } from '../lib/api';
import { colors } from '../theme';

// 코스 패치 배지 — 완료 카드 미니(40) · 패치 월(104) 공용.
// 등급: basic(볼트 스티치) → silver(×5) → gold(×10) → master(×25, 볼트 글로우+👑)

const GRADE_STYLE: Record<PatchGrade, { bg: string; stitch: string; km: string; solid?: boolean; glow?: boolean }> = {
  basic: { bg: '#0F1D13', stitch: 'rgba(198,245,66,.6)', km: '#FF5C3D' },
  silver: { bg: '#0F1D13', stitch: 'rgba(201,205,212,.85)', km: '#C9CDD4' },
  gold: { bg: '#332d14', stitch: 'rgba(242,218,150,.9)', km: '#F2DA96', solid: true },
  master: { bg: '#1a2a12', stitch: colors.volt, km: colors.volt, solid: true, glow: true },
};

export function PatchBadge({ km, name, grade, size = 40, style }: {
  km: number; name?: string; grade: PatchGrade; size?: number; style?: ViewStyle;
}) {
  const g = GRADE_STYLE[grade];
  const kmSize = size * 0.26;
  const nameSize = size * 0.085;
  return (
    <View
      style={[{
        width: size, height: size, borderRadius: size / 2, backgroundColor: g.bg,
        alignItems: 'center', justifyContent: 'center',
        shadowColor: g.glow ? colors.volt : '#0F1D13',
        shadowOpacity: g.glow ? 0.6 : 0.3,
        shadowRadius: g.glow ? size * 0.16 : size * 0.08,
        shadowOffset: { width: 0, height: g.glow ? 0 : 2 },
      }, style]}
    >
      {/* 스티치 링 */}
      <View style={{
        position: 'absolute', top: size * 0.06, left: size * 0.06, right: size * 0.06, bottom: size * 0.06,
        borderRadius: size / 2, borderWidth: Math.max(1.2, size * 0.018),
        borderColor: g.stitch, borderStyle: g.solid ? 'solid' : 'dashed',
      }} />
      {grade === 'master' && (
        <Text style={{ position: 'absolute', top: -size * 0.13, fontSize: size * 0.2 }}>👑</Text>
      )}
      <Text style={{ fontSize: kmSize, fontWeight: '900', color: g.km, lineHeight: kmSize * 1.1 }}>
        {km}K
      </Text>
      {name != null && size >= 60 && (
        <Text numberOfLines={1} style={{ fontSize: Math.max(7, nameSize * 1.2), fontWeight: '800', color: '#c9d4c0', marginTop: 2, maxWidth: size * 0.8, textAlign: 'center' }}>
          {name}
        </Text>
      )}
    </View>
  );
}
