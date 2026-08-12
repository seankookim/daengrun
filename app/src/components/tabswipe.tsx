import { router, usePathname } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Animated, Dimensions, Easing, Image, PanResponder, StyleSheet, View } from 'react-native';
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
// 저항한다 (§7c: 경계에서 하드스톱 대신 고무줄).
//
// ── 커밋 안무 = 스냅샷 인계 (Sean 2026-08-12: "add the swipe between screens fluidity") ──
// 예전엔 커밋이 **두 동작**이었다: 나가는 화면이 끝까지 밀려나가고(170ms) → replace → 들어오는
// 화면이 반대편에서 스프링. 그 사이에 빈 구간이 생겨 한 동작으로 읽히지 않았다.
// 지금은 하나다. 커밋되는 순간 나가는 화면을 **찍어서**(captureRef, tmpfile jpg) 모듈 쪽지에
// {uri, fromX, from}으로 남기고 **나가는 애니메이션 없이 즉시** replace한다. 새로 마운트된
// TabSwipe가 쪽지를 읽어 나머지 절반을 이어 달린다 — 애니메이션 값 하나(x)가 `from*W + fromX`
// 에서 0으로 스프링하고, 스냅샷은 **같은 값**에서 from*W를 뺀 자리에 붙는다. 두 표면이 늘 정확히
// 한 화면 폭만큼 떨어진 채 함께 움직인다 = 페이저 착시. 스냅샷은 타이머가 아니라 스프링 콜백에서
// 내린다.
// 왜 굳이 스냅샷인가: ②의 플랫 Stack + replace라 **두 화면이 동시에 마운트되는 순간이 없다.**
// 이웃 화면을 실제로 옆에 놓을 방법이 없으니, 옆에 놓을 수 있는 건 방금 찍은 나가는 화면뿐이다.
// 실패 경로: view-shot이 안 들어간 빌드거나 캡처가 던지면 예전 안무(밀어내기 170ms → replace)로
// 그대로 폴백한다 — 캡처 실패가 화면을 어중간한 오프셋에 붙잡아 두는 일은 없다.
// tmpfile은 스프링이 끝난 뒤 view-shot의 releaseCapture로 지운다(새 의존성 없음 — 같은 패키지가
// 내보내는 함수다). 실패해도 OS가 tmp를 비우므로 스와이프가 jpg를 쌓아두진 않는다.
// transform만 쓰고 전부 네이티브 드라이버 — §6 모션법(레이아웃/배경색 애니메이션 금지) 준수.

const { width: W } = Dimensions.get('window');
const EDGE = 24;          // 캡처 무장 밴드 (화면 양끝)
const ARM_DX = 12;        // 엣지: 이만큼 가로로 움직여야 (탭·짧은 흔들림 제외)
const ARM_RATIO = 1.75;   // 엣지: 세로보다 이 배 이상 가로여야 — 엣지에서 시작한 세로 스크롤을 살린다
const COMMIT = W * 0.28;
const COMMIT_V = 0.45;  // 빠른 플릭은 거리가 짧아도 커밋 (§7c 속도 인계)

// 나가는 화면이 들어오는 화면에게 남기는 쪽지. 모듈 스코프인 이유: 두 화면은 서로를 모르고,
// 라우터는 파라미터를 실어주지 않는다. 읽는 즉시 소각한다 — 탭바로 들어온 전환은 정지 상태여야 한다.
type Handoff = {
  uri: string | null;  // 나가는 화면 스냅샷. null = 캡처 실패, 폴백 안무로 이미 밀어낸 뒤라는 뜻
  fromX: number;       // 손가락을 뗀 지점 = 스냅샷이 이어받을 자리 (폴백은 0)
  from: -1 | 1;        // 들어오는 화면이 오는 쪽. 1 = 오른쪽에서, -1 = 왼쪽에서
};
let handoff: Handoff | null = null;

export function TabSwipe({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const x = useRef(new Animated.Value(0)).current;
  const view = useRef<View>(null);  // captureRef 대상 = 나가는 화면 본체 (collapsable={false} 필수)
  const [snap, setSnap] = useState<{ uri: string; from: -1 | 1 } | null>(null);
  // PanResponder는 ref로 1회 생성되므로 최신 이웃을 클로저로 굳히면 스테일이 된다
  // (club-ui.tsx SealSlide가 남긴 교훈 — stateRef 경유로 읽는다).
  const nav = useRef<[string | null, string | null]>([null, null]);
  nav.current = tabNeighbors(pathname);

  // 들어오는 쪽 절반 — 나가는 화면(=스냅샷)과 **한 값으로** 묶여 제자리로 온다.
  useEffect(() => {
    const note = handoff;
    handoff = null;  // 읽는 즉시 소각: 두 번 소비될 수 없다 (연속 스와이프·재마운트 대비)
    if (!note) return;
    x.setValue(note.from * W + note.fromX);  // 폴백(fromX=0)이면 예전처럼 정확히 한 칸 밖에서 출발
    const uri = note.uri;
    if (uri) setSnap({ uri, from: note.from });
    Animated.spring(x, { toValue: 0, useNativeDriver: true, damping: 22, stiffness: 220, mass: 0.9 })
      // finished=false(손가락이 스프링을 도중에 잡아챈 경우)에도 내린다 — 안 그러면 스냅샷이
      // 다음 제스처를 따라다니는 유령이 된다.
      .start(() => {
        setSnap(null);
        // 임시 jpg 회수. 500ms 미루는 건 라이브러리 자신의 방식이다(ViewShot 컴포넌트도 이렇게
        // 미뤄 부른다) — 이미지가 화면에서 내려간 뒤에 지운다. catch가 비어 있는 건 정직법 위반이
        // 아니다: 여기까지 왔다는 건 require가 이미 성공했다는 뜻이고, 실패해도 사용자에게
        // 보이는 결과가 없다(OS tmp 청소로 끝난다).
        if (uri) setTimeout(() => { try { require('react-native-view-shot').releaseCapture(uri); } catch {} }, 500);
      });
  }, [pathname, x]);

  const settle = () => Animated.spring(x, {
    toValue: 0, useNativeDriver: true, damping: 20, stiffness: 200, mass: 0.9,
  }).start();

  // 폴백 안무 (2026-08-12 이전의 그 두 동작). 캡처가 불가능할 때만 쓴다 — 살려두는 이유는
  // view-shot 네이티브 모듈이 없는 개발 빌드가 실재하기 때문이다(shot/[bid].tsx 선례).
  const fallback = (dir: -1 | 1, target: string, from: -1 | 1) => {
    Animated.timing(x, { toValue: dir * W, duration: 170, easing: Easing.out(Easing.cubic), useNativeDriver: true })
      .start(() => {
        handoff = { uri: null, fromX: 0, from };
        router.replace(target as never);
        x.setValue(0); // 이 화면은 곧 언마운트 — 잔상 방지
      });
  };

  const commit = (dir: -1 | 1, target: string, dx: number) => {
    // dir = 손가락이 간 방향. 왼쪽으로 밀면(-1) 오른쪽 탭이 오고, 들어오는 화면은 반대편(from)에서 온다.
    const from = (dir === -1 ? 1 : -1) as -1 | 1;
    // dx = 손을 뗀 오프셋. 이웃이 있는 방향이므로 러버밴딩이 걸리지 않아 x와 1:1로 같다.
    try {
      const VS = require('react-native-view-shot');
      const shot: Promise<string | null> = VS.captureRef(view, { result: 'tmpfile', format: 'jpg', quality: 0.85 });
      shot.then((uri) => {
        if (!uri) return fallback(dir, target, from);
        handoff = { uri, fromX: dx, from };
        // 나가는 화면은 애니메이션하지 않는다. 여기서부터 이 화면을 연기하는 건 스냅샷이다.
        router.replace(target as never);
      }).catch(() => fallback(dir, target, from));
    } catch {
      fallback(dir, target, from);  // view-shot 미탑재 빌드 — require 자체가 던진다
    }
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
      if ((far || fast) && g.dx < 0 && right) return commit(-1, right, g.dx);
      if ((far || fast) && g.dx > 0 && left) return commit(1, left, g.dx);
      settle();
    },
    onPanResponderTerminate: () => settle(),
  })).current;

  // 탭이 아닌 화면(이웃 둘 다 null)에서는 제스처를 아예 달지 않는다 — 죽은 핸들러를 남기지 않는다.
  const isTab = nav.current[0] !== null || nav.current[1] !== null;
  if (!isTab) return <View style={{ flex: 1 }}>{children}</View>;

  return (
    // 래퍼는 스냅샷이 없을 때도 항상 있다 — 트리 모양이 바뀌면 children이 통째로 리마운트된다.
    <View style={{ flex: 1 }}>
      <Animated.View
        ref={view}
        collapsable={false}
        style={{ flex: 1, transform: [{ translateX: x }] }}
        {...pan.panHandlers}
      >
        {children}
      </Animated.View>
      {snap && (
        // 스냅샷은 **번역된 화면 밖**에 산다: 안에 넣으면 x가 두 번 먹는다.
        // translateX = x − from*W. 검산: from=1이면 x가 W+fromX→0, 스냅샷은 fromX→−W (왼쪽으로 퇴장).
        // from=−1이면 x가 −W+fromX→0, 스냅샷은 fromX→+W. 어느 쪽이든 두 면이 한 폭 간격으로 붙어 간다.
        // pointerEvents는 ImageProps에 없어서(ViewProps 상속 아님) Animated.View가 쓴다 — 전환 중
        // 스냅샷이 탭을 먹으면 죽은 화면을 누르는 셈이 된다.
        <Animated.View
          pointerEvents="none"
          style={[StyleSheet.absoluteFill, {
            transform: [{
              translateX: x.interpolate({
                inputRange: [0, W], outputRange: [-snap.from * W, W - snap.from * W],
              }),
            }],
          }]}
        >
          {/* fadeDuration=0: 안드로이드 기본 300ms 페이드인이 붙으면 스냅샷이 '나타나' 버린다 */}
          <Image source={{ uri: snap.uri }} fadeDuration={0} resizeMode="cover" style={StyleSheet.absoluteFill} />
        </Animated.View>
      )}
    </View>
  );
}
