import { router, usePathname } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { session } from '../store';
import { lilac } from '../theme';
import { Icon } from './ui';

// Prototype-style bottom nav, role-aware via session. Swap for expo-router Tabs later.
// [V4 라일락 리페인트, 2026-08-03] 크림/포레스트 은퇴 → 라일락 글래스 도크.
//   active = 바이올렛 accent + 상단 인디케이터 룰 · idle = dim. dark prop은 나이트 라일락(#1C1837).

// Calendar decision (docs/calendar.md): owners get no calendar tab (home widget
// + booking CTA); runners get dedicated 캘린더 + 요청 tabs. 안심 lives in 마이,
// home quick-card, and live screens.
// 기록(/cards)은 탭에서 빠지고 홈 히어로/스탯에서 진입 — 예약 관리가 탭 자격 (사용자 피드백 2026-07)
// lucide: 새 빌드에서 실아이콘, 구 빌드에선 글리프 폴백
const OWNER_TABS = [
  { icon: '⌂', lucide: 'House', label: '홈', path: '/owner/home' },
  { icon: '▦', lucide: 'CalendarDays', label: '내 일정', path: '/owner/schedule' },
  { icon: '◎', lucide: 'Users', label: '커뮤니티', path: '/community' },
  { icon: '◈', lucide: 'ShoppingBag', label: '샵', path: '/shop' },
  { icon: '☰', lucide: 'CircleUserRound', label: '마이', path: '/my' },
] as const;

const RUNNER_TABS = [
  { icon: '⌂', lucide: 'House', label: '홈', path: '/runner/home' },
  { icon: '▦', lucide: 'CalendarDays', label: '캘린더', path: '/runner/calendar' },
  { icon: '✉', lucide: 'Inbox', label: '요청', path: '/runner/requests' },
  { icon: '₩', lucide: 'Wallet', label: '수익', path: '/runner/earnings' },
  { icon: '☰', lucide: 'CircleUserRound', label: '마이', path: '/my' },
] as const;

export function homePath(): '/owner/home' | '/runner/home' {
  return session.role === 'runner' ? '/runner/home' : '/owner/home';
}

export function BottomNav({ dark }: { dark?: boolean }) {
  const pathname = usePathname();
  const tabs = session.role === 'runner' ? RUNNER_TABS : OWNER_TABS;
  const activeColor = lilac.accent;
  const idleColor = dark ? '#8F86C2' : lilac.dim;

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
            {/* 액티브 인디케이터 룰 — 바이올렛 (D 셸 문법) */}
            <View style={[s.ind, active && { backgroundColor: lilac.accent }]} />
            <View style={{ marginBottom: 3 }}>
              <Icon name={t.lucide} glyph={t.icon} size={19} color={active ? activeColor : idleColor} />
            </View>
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
  bar: {
    flexDirection: 'row', borderTopWidth: 1, borderTopColor: lilac.hair,
    backgroundColor: lilac.glass, paddingBottom: 22,
  },
  barDark: { backgroundColor: '#1C1837', borderTopColor: '#2A2350' },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 12 },
  ind: { position: 'absolute', top: 0, width: 26, height: 2.5, borderRadius: 2, backgroundColor: 'transparent' },
  icon: { fontSize: 20.5, marginBottom: 3 },
  label: { fontSize: 12.5, fontWeight: '500' },
});
