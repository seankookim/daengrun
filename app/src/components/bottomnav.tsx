import { router, usePathname } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { session } from '../store';
import { colors } from '../theme';

// Prototype-style bottom nav, role-aware via session. Swap for expo-router Tabs later.

const OWNER_TABS = [
  { icon: '⌂', label: '홈', path: '/owner/home' },
  { icon: '◎', label: '커뮤니티', path: '/community' },
  { icon: '◈', label: '샵', path: '/shop' },
  { icon: '☰', label: '마이', path: null },
] as const;

const RUNNER_TABS = [
  { icon: '⌂', label: '홈', path: '/runner/home' },
  { icon: '◎', label: '커뮤니티', path: '/community' },
  { icon: '✉', label: '채팅', path: null },
  { icon: '₩', label: '수익', path: null },
] as const;

export function homePath(): '/owner/home' | '/runner/home' {
  return session.role === 'runner' ? '/runner/home' : '/owner/home';
}

export function BottomNav() {
  const pathname = usePathname();
  const tabs = session.role === 'runner' ? RUNNER_TABS : OWNER_TABS;

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
