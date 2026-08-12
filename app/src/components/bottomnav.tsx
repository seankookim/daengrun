import { router, usePathname } from 'expo-router';
import { Pressable, StyleSheet, View } from 'react-native';
import { session } from '../store';
import { paper } from '../theme';
import { Icon } from './ui';

// Prototype-style bottom nav, role-aware via session. Swap for expo-router Tabs later.
// [paper chrome 2026-08-10] 라일락 글래스 도크 은퇴 → 순백 도크 + 코랄 풀블리드 톱 헤어라인
//   (섹션 분리 법을 도크에 적용). active = ink 아이콘+라벨 + 코랄 스퀘어 인디케이터 · idle = dim.
//   dark prop은 나이트 클럽 월드(아티팩트) — 다크 변형은 기존 그대로 유지.

// Calendar decision (docs/calendar.md): owners get no calendar tab (home widget
// + booking CTA); runners get dedicated 캘린더 + 요청 tabs. 안심 lives in 마이,
// home quick-card, and live screens.
// 기록(/cards)은 탭에서 빠지고 홈 히어로/스탯에서 진입 — 예약 관리가 탭 자격 (사용자 피드백 2026-07)
// lucide: 새 빌드에서 실아이콘, 구 빌드에선 글리프 폴백
// [홈 센터 2026-08-11, Sean] 홈이 5탭의 한가운데(index 2)로 이동. 나머지 탭의 상대 순서는
//   그대로 — 홈만 앞에서 가운데로 옮겼다 (엄지 사정거리 법: 가장 자주 누르는 목적지가 호의 중심).
//   ⚠ 순서 재배치가 안전한 이유를 확인해두었다: 액티브 인디케이터는 각 탭의 flex:1 박스 안에
//   absolute로 그려지므로 인덱스 산술이 없고, 탭 전환은 전부 경로 문자열(router.replace(t.path))이라
//   순번에 기대는 호출부가 없다. 배열 순서 = 화면 순서, 그 이상의 계약은 없다.
// [아이콘 도크 2026-08-12, Sean] "탭 아이콘 밑 글자 빼고 아이콘 키워라" → 라벨 <Text> 제거, 아이콘 19 → 26.
//   라벨이 사라진 만큼 액티브는 아이콘 색 + 코랄 스퀘어 인디케이터 둘로만 말한다 (배경 알약·필 금지 —
//   도크의 유일한 장식은 §3b 섹션 법과 같은 톱 헤어라인이다). 인디케이터 26 → 34: 커진 아이콘보다 살짝
//   넓어야 '밑줄'이 아니라 헤어라인으로 읽힌다.
//   보이는 라벨이 없어져도 배열의 label 필드는 남는다 — 스크린리더가 그걸 읽는다. Pressable이
//   accessibilityRole="tab" + accessibilityLabel + selected 상태를 반드시 들고 있어야 하는 이유.
//   높이 보존: 라벨(14) + 간격(3)이 빠진 만큼 탭 paddingVertical 12 → 18 (탭 높이 ≈63 → 62, 도크 총높이
//   거의 그대로, 터치 타깃 44pt 법은 여유 통과).
//   ⚠ 샵 아이콘은 건드리지 않았다 — 이미 lucide ShoppingBag이고 시뮬레이터 실빌드에서 렌더 확인했다.
//   "쇼핑백으로 바꿔라"는 지시는 19pt에 라벨까지 붙어 백이 안 읽혔던 문제지 아이콘 이름이 틀린 게
//   아니었다. 다음 세션이 이름을 다시 갈아엎지 않도록 적어둔다.
const OWNER_TABS = [
  { icon: '▦', lucide: 'CalendarDays', label: '내 일정', path: '/owner/schedule' },
  { icon: '◎', lucide: 'Users', label: '커뮤니티', path: '/community' },
  { icon: '⌂', lucide: 'House', label: '홈', path: '/owner/home' },
  { icon: '◈', lucide: 'ShoppingBag', label: '샵', path: '/shop' },
  { icon: '☰', lucide: 'CircleUserRound', label: '마이', path: '/my' },
] as const;

const RUNNER_TABS = [
  { icon: '▦', lucide: 'CalendarDays', label: '캘린더', path: '/runner/calendar' },
  { icon: '✉', lucide: 'Inbox', label: '요청', path: '/runner/requests' },
  { icon: '⌂', lucide: 'House', label: '홈', path: '/runner/home' },
  { icon: '₩', lucide: 'Wallet', label: '수익', path: '/runner/earnings' },
  { icon: '☰', lucide: 'CircleUserRound', label: '마이', path: '/my' },
] as const;

export function homePath(): '/owner/home' | '/runner/home' {
  return session.role === 'runner' ? '/runner/home' : '/owner/home';
}

// [2026-08-12] 탭 순서를 밖으로 낸다 — 좌우 스와이프(TabSwipe)가 '이웃 탭'을 알아야 하고,
// 그 순서의 정본은 이 배열 하나여야 한다. 두 벌이 되는 순간 도크와 제스처가 다른 곳으로 간다.
// 반환: [왼쪽 이웃, 오른쪽 이웃] — 양끝은 null (없는 이웃으로는 넘어가지 않는다).
export function tabNeighbors(pathname: string): [string | null, string | null] {
  const tabs = session.role === 'runner' ? RUNNER_TABS : OWNER_TABS;
  const i = tabs.findIndex((t) => t.path === pathname);
  if (i < 0) return [null, null]; // 탭이 아닌 화면 = 스와이프 대상 아님
  return [i > 0 ? tabs[i - 1].path : null, i < tabs.length - 1 ? tabs[i + 1].path : null];
}

export function BottomNav({ dark }: { dark?: boolean }) {
  const pathname = usePathname();
  const tabs = session.role === 'runner' ? RUNNER_TABS : OWNER_TABS;
  // 다크(나이트 클럽) 변형은 아티팩트 — 기존 바이올렛 액티브 유지. 라이트 = 페이퍼: ink/dim.
  const activeColor = dark ? '#6C5CE7' : paper.ink;
  const idleColor = dark ? '#8F86C2' : paper.dim;
  const indColor = dark ? '#6C5CE7' : paper.line;

  return (
    <View style={[s.bar, dark && s.barDark]}>
      {tabs.map((t) => {
        const active = t.path === pathname;
        return (
          <Pressable
            key={t.label}
            style={s.tab}
            onPress={() => { if (t.path && !active) router.replace(t.path); }}
            // 라벨이 화면에서 사라졌으니 접근성 이름은 여기서만 나온다 — 지우지 말 것.
            accessibilityRole="tab"
            accessibilityLabel={t.label}
            accessibilityState={{ selected: active }}
          >
            {/* 액티브 인디케이터 룰 — 스퀘어 (라이트 = 코랄, 다크 = 기존 바이올렛) */}
            <View style={[s.ind, active && { backgroundColor: indColor }]} />
            <Icon name={t.lucide} glyph={t.icon} size={26} color={active ? activeColor : idleColor} />
          </Pressable>
        );
      })}
    </View>
  );
}

const s = StyleSheet.create({
  bar: {
    // 톱 헤어라인 = 솔리드 코랄 1px 풀블리드 (페이퍼 섹션 법의 도크 적용) · 순백 면
    flexDirection: 'row', borderTopWidth: 1, borderTopColor: paper.line,
    backgroundColor: paper.canvas, paddingBottom: 22,
  },
  barDark: { backgroundColor: '#1C1837', borderTopColor: '#2A2350' },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 18 },
  ind: { position: 'absolute', top: 0, width: 34, height: 2.5, backgroundColor: 'transparent' },
});
