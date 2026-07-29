import { ReactNode } from 'react';
import { Image, Pressable, StyleProp, StyleSheet, Text, TextStyle, View, ViewStyle } from 'react-native';
import { colors, radius } from '../theme';

// 도그스하이 shared UI kit — mirrors the prototype's design system.

export function Btn({
  label, onPress, variant = 'ink', disabled, style,
}: {
  label: string; onPress?: () => void; variant?: 'ink' | 'volt' | 'ghost'; disabled?: boolean; style?: ViewStyle;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        s.btn,
        variant === 'volt' && { backgroundColor: colors.volt },
        variant === 'ghost' && s.btnGhost,
        disabled && { opacity: 0.4 },
        pressed && { transform: [{ scale: 0.97 }] },
        style,
      ]}
    >
      <Text style={[s.btnText, variant === 'volt' && { color: colors.ink }, variant === 'ghost' && { color: colors.ink }]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function Card({ children, dark, style }: { children: ReactNode; dark?: boolean; style?: StyleProp<ViewStyle> }) {
  return <View style={[s.card, dark && s.cardDark, style]}>{children}</View>;
}

export function Chip({
  label, selected, onPress, style,
}: { label: string; selected?: boolean; onPress?: () => void; style?: ViewStyle }) {
  return (
    <Pressable onPress={onPress} style={[s.chip, selected && s.chipSel, style]}>
      <Text style={[s.chipText, selected && { color: colors.volt }]}>{label}</Text>
    </Pressable>
  );
}

export function Badge({ label, tone = 'green' }: { label: string; tone?: 'green' | 'red' | 'ink' }) {
  const bg = tone === 'green' ? '#DDE8D4' : tone === 'red' ? '#ffe4dc' : colors.ink;
  const fg = tone === 'green' ? '#2f4a35' : tone === 'red' ? '#c2340f' : colors.volt;
  return (
    <View style={[s.badge, { backgroundColor: bg }]}>
      <Text style={{ fontSize: 12.5, fontWeight: '700', color: fg }}>{label}</Text>
    </View>
  );
}

export function Monogram({ char, bg, size = 52 }: { char: string; bg: string; size?: number }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size * 0.3, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontFamily: undefined, fontSize: size * 0.42, fontWeight: '800', color: '#fff' }}>{char}</Text>
    </View>
  );
}

// 아이콘 — lucide(새 빌드) 지연 로드, 없으면 텍스트 글리프 폴백. 리빌드하면 자동 업그레이드.
let Lucide: any = null;
try { Lucide = require('lucide-react-native'); } catch { /* 구 빌드 — 글리프 폴백 */ }

export function Icon({ name, glyph, size = 18, color }: { name: string; glyph: string; size?: number; color: string }) {
  const L = Lucide?.[name];
  if (L) return <L size={size} color={color} strokeWidth={1.8} />;
  return <Text style={{ fontSize: size * 0.9, color }}>{glyph}</Text>;
}

// 스켈레톤 — '불러오는 중...' 텍스트 대체 (은은한 펄스)
export function Skeleton({ width, height, radius: r = 12, style }: { width: number | `${number}%`; height: number; radius?: number; style?: ViewStyle }) {
  return <View style={[{ width, height, borderRadius: r, backgroundColor: '#e8e5d8', opacity: 0.7 }, style]} />;
}

// 실사진 아바타 — url 없으면 Monogram 폴백. 신뢰 표면 전부가 이걸 쓴다.
export function Avatar({ url, char, bg, size = 52 }: { url?: string | null; char: string; bg: string; size?: number }) {
  if (!url) return <Monogram char={char} bg={bg} size={size} />;
  return (
    <Image
      source={{ uri: url }}
      style={{ width: size, height: size, borderRadius: size * 0.3, backgroundColor: '#DCD6C4' }}
    />
  );
}

export function StatBlock({ value, label, valueColor = colors.volt }: { value: string; label: string; valueColor?: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 32, fontWeight: '900', color: valueColor }}>{value}</Text>
      <Text style={{ fontSize: 14.5, color: '#8fa093', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

export function Row({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return <View style={[{ flexDirection: 'row', alignItems: 'center' }, style]}>{children}</View>;
}

export const text: Record<string, TextStyle> = {
  h1: { fontSize: 32, fontWeight: '900', color: colors.ink },
  h2: { fontSize: 20.5, fontWeight: '800', color: colors.ink },
  label: { fontSize: 15, fontWeight: '700', color: colors.ink },
  dim: { fontSize: 14, color: colors.dim },
  body: { fontSize: 15, color: colors.ink, lineHeight: 23 },
};

const s = StyleSheet.create({
  btn: { backgroundColor: colors.ink, borderRadius: radius.btn, padding: 17, alignItems: 'center' },
  btnGhost: { backgroundColor: 'transparent', borderWidth: 2, borderColor: colors.ink },
  btnText: { fontSize: 19.5, fontWeight: '800', color: colors.volt, letterSpacing: 0.5 },
  card: { backgroundColor: colors.card, borderRadius: radius.card, padding: 18, borderWidth: 1, borderColor: colors.line },
  cardDark: { backgroundColor: colors.ink, borderColor: colors.ink },
  chip: { paddingVertical: 8, paddingHorizontal: 14, borderRadius: radius.chip, borderWidth: 1.5, borderColor: colors.line, backgroundColor: '#fff' },
  chipSel: { backgroundColor: colors.ink, borderColor: colors.ink },
  chipText: { fontSize: 15, fontWeight: '500', color: colors.ink },
  badge: { paddingVertical: 3, paddingHorizontal: 9, borderRadius: 99, alignSelf: 'flex-start' },
});
