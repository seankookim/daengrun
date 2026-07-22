import { router, usePathname } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

// Prototype-style bottom nav. Swap for expo-router Tabs when flows stabilize.

const OWNER_TABS = [
  { icon: '⌂', label: '홈', path: '/owner/home' },
  { icon: '◎', label: '커뮤니티', path: '/owner/community' },
  { icon: '◈', label: '샵', path: '/owner/shop' },
  { icon: '☰', label: '마이', path: null },
] as const;

const RUNNER_TABS = [
  { icon: '⌂', label: '홈', path: '/runner/home' },
  { icon: '◎', label: '커뮤니티', path: '/owner/community' },
  { icon: '✉', label: '채팅', path: null },
  { icon: '₩', label: '수익', path: null },
] as const;

export function BottomNav({ role }: { role: 'owner' | 'runner' }) {
  const pathname = usePathname();
  const tabs = role === 'owner' ? OWNER_TABS : RUNNER_TABS;

  return (
    <View style={s.bar}>
      {tabs.map((t) => {
        const active = t.path === pathname;
        return (
          <Pressable
            key={t.label}
            style={s.tab}
            onPress={() => { if (t.path && !active) router.replace(t.path); }}
          >
            <Text style={[s.icon, active && { color: colors.ink }]}>{t.icon}</Text>
            <Text style={[s.label, active && s.labelActive]}>{t.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const s = StyleSheet.create({
  bar: { flexDirection: 'row', borderTopWidth: 1, borderTopColor: colors.line, backgroundColor: '#fff', paddingBottom: 22 },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 12 },
  icon: { fontSize: 18, color: colors.dim, marginBottom: 3 },
  label: { fontSize: 11, color: colors.dim, fontWeight: '500' },
  labelActive: { color: colors.ink, fontWeight: '700' },
});
