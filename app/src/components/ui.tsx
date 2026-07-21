import { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, TextStyle, View, ViewStyle } from 'react-native';
import { colors, radius } from '../theme';

// 댕런 shared UI kit — mirrors the prototype's design system.

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

export function Card({ children, dark, style }: { children: ReactNode; dark?: boolean; style?: ViewStyle }) {
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
  const bg = tone === 'green' ? '#e4f7c0' : tone === 'red' ? '#ffe4dc' : colors.ink;
  const fg = tone === 'green' ? '#4a7208' : tone === 'red' ? '#c2340f' : colors.volt;
  return (
    <View style={[s.badge, { backgroundColor: bg }]}>
      <Text style={{ fontSize: 11, fontWeight: '700', color: fg }}>{label}</Text>
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

export function StatBlock({ value, label, valueColor = colors.volt }: { value: string; label: string; valueColor?: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 28, fontWeight: '900', color: valueColor }}>{value}</Text>
      <Text style={{ fontSize: 11, color: '#9a987f', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

export function Row({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return <View style={[{ flexDirection: 'row', alignItems: 'center' }, style]}>{children}</View>;
}

export const text: Record<string, TextStyle> = {
  h1: { fontSize: 28, fontWeight: '900', color: colors.ink },
  h2: { fontSize: 18, fontWeight: '800', color: colors.ink },
  label: { fontSize: 13, fontWeight: '700', color: colors.ink },
  dim: { fontSize: 12, color: colors.dim },
  body: { fontSize: 13, color: colors.ink, lineHeight: 20 },
};

const s = StyleSheet.create({
  btn: { backgroundColor: colors.ink, borderRadius: radius.btn, padding: 17, alignItems: 'center' },
  btnGhost: { backgroundColor: 'transparent', borderWidth: 2, borderColor: colors.ink },
  btnText: { fontSize: 17, fontWeight: '800', color: colors.volt, letterSpacing: 0.5 },
  card: { backgroundColor: colors.card, borderRadius: radius.card, padding: 18, borderWidth: 1, borderColor: colors.line },
  cardDark: { backgroundColor: colors.ink, borderColor: colors.ink },
  chip: { paddingVertical: 8, paddingHorizontal: 14, borderRadius: radius.chip, borderWidth: 1.5, borderColor: colors.line, backgroundColor: '#fff' },
  chipSel: { backgroundColor: colors.ink, borderColor: colors.ink },
  chipText: { fontSize: 13, fontWeight: '500', color: colors.ink },
  badge: { paddingVertical: 3, paddingHorizontal: 9, borderRadius: 99, alignSelf: 'flex-start' },
});
