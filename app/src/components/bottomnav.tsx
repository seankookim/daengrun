import { router, usePathname } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { session } from '../store';
import { colors } from '../theme';

// Prototype-style bottom nav, role-aware via session. Swap for expo-router Tabs later.

const OWNER_TABS = [
  { icon: '⌂', label: '홈', path: '/owner/home' },
  { icon: '◎', label: '커뮤니티', path: '/community' },
  { icon: '⌗', label: '기록', path: '/cards' },
  { icon: '◈', label: '샵', path: '/shop' },
  { icon: '✚', label: '안심', path: '/safety' },
] as const;

const RUNNER_TABS = [
  { icon: '⌂', label: '홈', path: '/runner/home' },
  { icon: '◎', label: '커뮤니티', path: '/community' },
  { icon: '⌗', label: '기록', path: '/cards' },
  { icon: '✚', label: '안심', path: '/safety' },
  { icon: '₩', label: '수익', path: null },
] as const;

export function homePath(): '/owner/home' | '/runner/home' {
  return session.role === 'runner' ? '/runner/home' : '/owner/home';
}

export function BottomNav({ dark }: { dark?: boolean }) {
  const pathname = usePathname();
  const tabs = session.role === 'runner' ? RUNNER_TABS : OWNER_TABS;
  const activeColor = dark ? colors.volt : colors.ink;
  const idleColor = dark ? colors.dimDark : colors.dim;

  return (
    <View style={[s.bar, dark && s.barDark]}>
      {tabs.map((t) => {
        const active = t.path === pathname;
        return (
          <Pressable
            key={t.label}
            style={s.tab}
            onPress={() => { if (t.path && !active) router.replace(t.path); }}
          >
            <Text style={[s.icon, { color: active ? activeColor : idleColor }]}>{t.icon}</Text>
            <Text style={[s.label, { color: active ? activeColor : idleColor }, active && { fontWeight: '700' }]}>
              {t.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const s = StyleSheet.create({
  bar: { flexDirection: 'row', borderTopWidth: 1, borderTopColor: colors.line, backgroundColor: '#fff', paddingBottom: 22 },
  barDark: { backgroundColor: '#111c14', borderTopColor: colors.lineDark },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 12 },
  icon: { fontSize: 18, marginBottom: 3 },
  label: { fontSize: 11, fontWeight: '500' },
});
