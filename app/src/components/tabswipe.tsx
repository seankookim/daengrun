import { router, usePathname } from 'expo-router';
import { useEffect, useRef } from 'react';
import { Animated, Dimensions, Easing, PanResponder, View } from 'react-native';
import { tabNeighbors } from './bottomnav';

// 탭 간 좌우 스와이프 (Sean: "make screens slidable between different tabs").
//
// ── 왜 페이저 라이브러리가 아닌가 (2026-08-11 스코핑에서 실측한 네 가지) ──
// ① package.json에 gesture-handler·reanimated·pager-view가 **없다**. 어느 것이든 expo prebuild +
//    네이티브 재빌드를 부른다 (그리고 UTF-8 로케일 함정, 핸드오프 §⑧).
// ② 감쌀 탭 컨테이너가 없다. 모든 탭 화면이 각자 <BottomNav />를 그리고 전환은 플랫 Stack 위의
//    router.replace다 — 진짜 페이저는 이웃 탭을 동시에 마운트하는 부모를 요구하므로 라우터
//    아키텍처 이전이 된다.
// ③ 탭 화면에 이미 가로 제스처가 4곳 산다 (owner/home 코스 스트립 ×2, schedule, shop).
// ④ 🔴 이 충돌은 이 앱을 이미 한 번 물었고 결론은 '제스처를 지운다'였다: _layout.tsx의
//    gestureEnabled:false 주석이 "back-swipe conflicted with the slider"다. 그리고 SealSlide
//    (club-ui.tsx)는 캡처로 가로를 강탈하고 종료 요청을 거부한다 — 협상으로 공존이 불가능하다.
//
// 그래서 이 구현은 **엣지 스와이프**다: 손가락이 화면 가장자리 EDGE(24pt) 안에서 출발했을 때만
// 무장한다. ③의 네 스크롤러는 전부 거터(15) 안쪽 콘텐츠라 출발점이 겹치지 않고, ④가 비워둔
// 자리를 그대로 쓴다 (iOS 뒤로가기 스와이프는 이 앱에서 이미 꺼져 있다).
//
// 모션은 진짜 1:1이다 — 트래킹 중 화면이 손가락을 따라오고, 이웃이 없는 쪽은 러버밴딩으로
// 저항한다 (§7c: 경계에서 하드스톱 대신 고무줄). 커밋되면 나가는 화면이 끝까지 밀려나고,
// 들어오는 화면은 반대편에서 들어온다 (enterFrom 모듈 변수 = 두 화면이 한 동작을 나눠 갖는 방법).
// transform만 쓰고 전부 네이티브 드라이버 — §6 모션법(레이아웃/배경색 애니메이션 금지) 준수.

const { width: W } = Dimensions.get('window');
const EDGE = 24;          // 캡처 무장 밴드 (화면 양끝)
const ARM_DX = 12;        // 엣지: 이만큼 가로로 움직여야 (탭·짧은 흔들림 제외)
const ARM_RATIO = 1.75;   // 엣지: 세로보다 이 배 이상 가로여야 — 엣지에서 시작한 세로 스크롤을 살린다
const COMMIT = W * 0.28;
const COMMIT_V = 0.45;  // 빠른 플릭은 거리가 짧아도 커밋 (§7c 속도 인계)

// 나가는 화면이 들어오는 화면에게 남기는 쪽지. -1 = 왼쪽에서 들어옴, 1 = 오른쪽에서 들어옴.
// 모듈 스코프인 이유: 두 화면은 서로를 모르고, 라우터는 파라미터를 실어주지 않는다.
let enterFrom: -1 | 0 | 1 = 0;

export function TabSwipe({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const x = useRef(new Animated.Value(0)).current;
  // PanResponder는 ref로 1회 생성되므로 최신 이웃을 클로저로 굳히면 스테일이 된다
  // (club-ui.tsx SealSlide가 남긴 교훈 — stateRef 경유로 읽는다).
  const nav = useRef<[string | null, string | null]>([null, null]);
  nav.current = tabNeighbors(pathname);

  // 들어오는 쪽 절반 — 반대편에서 제자리로. 쪽지는 읽는 즉시 지운다(탭바로 들어온 전환은 정지).
  useEffect(() => {
    if (enterFrom === 0) return;
    x.setValue(enterFrom * W);
    enterFrom = 0;
    Animated.spring(x, { toValue: 0, useNativeDriver: true, damping: 22, stiffness: 220, mass: 0.9 }).start();
  }, [pathname, x]);

  const settle = () => Animated.spring(x, {
    toValue: 0, useNativeDriver: true, damping: 20, stiffness: 200, mass: 0.9,
  }).start();

  const commit = (dir: -1 | 1, target: string) => {
    // dir = 손가락이 간 방향. 왼쪽으로 밀면(-1) 오른쪽 탭이 온다.
    Animated.timing(x, { toValue: dir * W, duration: 170, easing: Easing.out(Easing.cubic), useNativeDriver: true })
      .start(() => {
        enterFrom = (dir === -1 ? 1 : -1) as -1 | 1; // 들어오는 화면은 반대편에서
        router.replace(target as never);
        x.setValue(0); // 이 화면은 곧 언마운트 — 잔상 방지
      });
  };

  // 🔴 [측정으로 확정 2026-08-12] **캡처만 쓴다. 버블 핸들러는 절대 불리지 않는다.**
  // 화면 한가운데서도 스와이프가 되게 하려고 `onMoveShouldSetPanResponder`(버블)를 한 번 달아봤다.
  // 시뮬레이터에서 검증: **아무 일도 일어나지 않았다.** 이유는 RN 리스폰더 협상 순서다 —
  // ScrollView는 터치 **다운 시점에** 리스폰더를 가져간다(스크롤을 시작할 수 있어야 하니까).
  // 버블 단계는 '아직 아무도 안 잡았을 때' 자식→부모로 올라오는 절차라, 이미 ScrollView가 잡은
  // 뒤에는 부모에게 물어보는 일 자체가 없다. 그래서 버블 핸들러는 죽은 코드였고 지웠다
  // (불릴 수 없는 핸들러를 남기면 다음 사람이 '되는 줄' 안다 — 이 저장소가 가장 싫어하는 종류).
  //
  // 결론: 자식에게서 제스처를 가져올 방법은 **캡처뿐**이고, 캡처를 화면 전체에 걸면 코스 스트립
  // 같은 가로 스크롤러를 못 쓰게 된다. 그래서 캡처는 엣지 밴드로 제한한다 — 이게 gesture-handler
  // 없이 도달 가능한 정직한 최대치다. 화면 어디서나 미는 진짜 페이저는 (a)안(네이티브 재빌드).
  const armed = (g: { dx: number; dy: number }) =>
    Math.abs(g.dx) > ARM_DX && Math.abs(g.dx) > Math.abs(g.dy) * ARM_RATIO;

  const pan = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => false, // 탭은 언제나 자식 몫
    onMoveShouldSetPanResponderCapture: (e, g) => {
      const x0 = e.nativeEvent.pageX - g.dx; // 제스처 시작점 (g.x0는 캡처 전엔 신뢰하지 않는다)
      const onEdge = x0 <= EDGE || x0 >= W - EDGE;
      return onEdge && armed(g);
    },
    onPanResponderMove: (_e, g) => {
      const [left, right] = nav.current;
      // 이웃이 없는 방향은 러버밴딩 (0.28 계수) — 벽이 있다는 걸 몸으로 알려준다
      const blocked = (g.dx > 0 && !left) || (g.dx < 0 && !right);
      x.setValue(blocked ? g.dx * 0.28 : g.dx);
    },
    onPanResponderTerminationRequest: () => false,
    onPanResponderRelease: (_e, g) => {
      const [left, right] = nav.current;
      const far = Math.abs(g.dx) > COMMIT;
      const fast = Math.abs(g.vx) > COMMIT_V;
      if ((far || fast) && g.dx < 0 && right) return commit(-1, right);
      if ((far || fast) && g.dx > 0 && left) return commit(1, left);
      settle();
    },
    onPanResponderTerminate: () => settle(),
  })).current;

  // 탭이 아닌 화면(이웃 둘 다 null)에서는 제스처를 아예 달지 않는다 — 죽은 핸들러를 남기지 않는다.
  const isTab = nav.current[0] !== null || nav.current[1] !== null;
  if (!isTab) return <View style={{ flex: 1 }}>{children}</View>;

  return (
    <Animated.View style={{ flex: 1, transform: [{ translateX: x }] }} {...pan.panHandlers}>
      {children}
    </Animated.View>
  );
}
