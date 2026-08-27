// 코스 지도 브라우즈 — 풀블리드 지도 + 3단 시트 (K6/T1, Sean A안 2026-08-13)
//
// ═══ 이 화면의 관점 ═══
// 브리프는 "스트라바 히트맵 같은 경로의 무리"였지만, 그건 n=9에서 성립하지 않는다 — 히트맵이
// 밀도장으로 읽히는 건 수천 개가 겹쳐서고, 아홉 개를 반투명으로 깔면 회색 지렁이 뭉치가 된다.
// 게다가 반포 시드 9개는 지금 전부 trace='[]'라, 트레이스를 1차 레이어로 삼으면 출시 시점의
// 지도는 **비어 있다**. 그래서 이 화면은 **앵커 지도가 트레이스를 길러 나가는** 구조다:
// 앵커는 첫날부터 진짜(만남 장소는 실제로 정해져 있다), 선은 파운더 워크가 벌어서 채운다.
// 부수 효과로 속 빈 앵커 vs 실선의 대비가 그대로 워크 진척 계기판이 된다.
//
// ═══ 강조 예산 (DESIGN.md §8) ═══
// 화면에서 채도를 가진 획은 **선택된 코스 하나**뿐이다. 그게 paper.line — 이 앱의 브랜드 선이다.
// 나머지 경로는 전부 faint 회색: 문맥이지 내용이 아니다. CTA 하나 + 코랄 선 하나 = 예산 정확히 소진.
//
// ═══ 시트가 목록이다 ═══
// 부유 목록을 따로 띄우지 않는다. 검색·칩·레일·시트 네 층이 지도를 조이면 '낮은 정보 밀도'라는
// 요구와 정면으로 충돌한다. 시트가 peek→list→detail 세 일을 순서대로 맡는다 (지도 앱 3사 공통
// 문법이라 학습 비용 0 — Jakob).
import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Animated, Dimensions, PanResponder, Platform, Pressable, ScrollView, StyleSheet, Text, View,
} from 'react-native';
import { fetchAddresses, fetchRoutes } from '../../src/lib/api';
import { CourseDetailBody, traceKind, TRACE_NOTE } from '../../src/components/course-detail';
import { emptyChipCopy, matchesChips, RouteChipRow, useRouteChips } from '../../src/components/route-chips';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { useNumFont } from '../../src/lib/fonts';
import { getNaverMap } from '../../src/lib/geo';
import { boundsOfTraces, orderByProximity, totalKmFor } from '../../src/lib/route-pick';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { GeoRoutePoint, RouteInfo, draft } from '../../src/store';
import { lilac, paper } from '../../src/theme';

const { height: SCREEN_H } = Dimensions.get('window');
// Peek detent = kick + name + (optional 이동 포함 총거리 line) + CTA, nothing else. The height is
// FIXED while the head is not: ruling #15 added a 14pt line that only appears once a pickup pin
// exists, and at 148 it pushed the CTA past the bottom edge — a primary button clipped out of sight
// on exactly the screens that had the most information. Budget: rule 2 + grab 22 + head ~72 + CTA
// block ~62 + slack.
const PEEK = 170;
const LIST = Math.round(SCREEN_H * 0.55);
const DETAIL = Math.round(SCREEN_H * 0.88);
type Detent = 'peek' | 'list' | 'detail';
const HEIGHT: Record<Detent, number> = { peek: PEEK, list: LIST, detail: DETAIL };

// 반포 중심 — 코스가 하나도 없을 때의 초기 카메라. 전부 candidate여도 앵커는 찍히므로
// 지도가 빈 채로 열리는 경우는 '코스 0개'뿐이고, 그건 아래 emptyCard가 말한다.
const FALLBACK_CAM = { latitude: 37.5069, longitude: 126.9954, zoom: 13.4 };

const PICKUP_HOUSE = require('../../assets/pickup-house.png');
const ROUTE_ANCHOR = require('../../assets/route-anchor.png');

// 칩 술어·개수·조명 자동켜짐은 `components/route-chips`가 소유한다 (K5와 **같은 정의** —
// 복제돼 있던 시절 라벨이 이미 갈라졌었다: 여기는 '그늘', 요청 화면은 '그늘 많음').

// 네이버 지도의 Region — south-west 모서리 + 위/경도 스팬. 네이티브 패키지에서 타입을
// 가져오지 않고 여기 적는다: 라우트가 모듈 스코프에서 네이티브 전용 패키지를 건드리면
// check-route-native-imports가 (정당하게) 거절한다.
interface MapRegion { latitude: number; longitude: number; latitudeDelta: number; longitudeDelta: number }

// ── Anchor size — scales with the camera zoom (decided 2026-08-19, overnight grant) ──
// Sean asked to SEE 18 pt anchors against the 44 pt HIG floor before ruling
// (docs/labs/anchor-tap-target-lab.html holds the frames). Measured on the simulator:
// at the Banpo cluster (500 m scale) 44 pt glyphs overlap each other; 18 pt stays
// readable but is 17 % of the HIG target area. The "18 pt glyph with an invisible
// 44 pt hit box" option does NOT exist on this SDK — a Naver marker's tap area IS its
// icon box (no hitSlop), and the only workaround (custom-React-View marker) dropped most
// markers on iOS when photographed. So the anchor scales with zoom instead: small where
// anchors are dense, the full 44 pt floor where they have room. Selected keeps +8.
// Sean flips this with a word; record lives in RULINGS-2026-08-19-journey.md.
const ANCHOR_SEL_BUMP = 8;   // selected anchor is 8 pt larger
const ANCHOR_FLOOR = 44;     // the HIG/Fitts target floor (DESIGN.md §"Fitts / HIG")
function anchorSizeForZoom(zoom: number): number {
  if (zoom >= 16) return ANCHOR_FLOOR; // street level — anchors are metres apart on screen
  if (zoom >= 14) return 30;           // neighbourhood — the Banpo cluster at 500 m scale
  return 18;                           // city / fit-all — dozens of anchors, keep them glyphs
}

// 아주 짧은 코스에서 건물 단위까지 파고드는 것을 막는 하한 (~400m).
const MIN_SPAN = 0.0035;
// 가장자리 여백. 선이 화면 테두리에 닿으면 '잘렸다'로 읽힌다.
const PAD = 1.35;

/**
 * 트레이스 전체를 담는 지도 영역.
 *
 * ⚠ 왜 `camera`(중심 + 고정 줌)를 버렸는가 — 시뮬레이터에서 측정한 고장이다. 줌 15가 박혀
 * 있어서 3km 코스는 양옆이 잘리고 **7km 코스는 네 변을 모두 넘어갔다**: 보호자가 코스를
 * 고르면 화면 밖으로 나가는 보라색 선만 보이고 코스의 모양을 볼 수 없었다. 길이가 2.78km에서
 * 7km까지 흩어져 있는 카탈로그에서 고정 줌이 맞을 수 있는 코스는 없다.
 *
 * 사각형으로 맞추면 길이와 무관하게 전체가 들어온다. 담을 점이 하나도 없으면 **영역을
 * 지어내지 않고** null을 준다 — 호출측이 폴백 카메라로 떨어진다.
 */
function regionOf(traces: GeoRoutePoint[][]): MapRegion | null {
  const b = boundsOfTraces(traces);
  if (!b) return null;
  const cLat = (b.minLat + b.maxLat) / 2;
  const cLng = (b.minLng + b.maxLng) / 2;
  const dLat = Math.max((b.maxLat - b.minLat) * PAD, MIN_SPAN);
  const dLng = Math.max((b.maxLng - b.minLng) * PAD, MIN_SPAN);
  return { latitude: cLat - dLat / 2, longitude: cLng - dLng / 2, latitudeDelta: dLat, longitudeDelta: dLng };
}

export default function CourseMap() {
  const maps = getNaverMap();
  // 숫자 서체 — 랩의 `.numf`가 km 숫자에 걸려 있는데 출하 코드에는 없었다 (Sean 2026-08-24:
  // "make sure the actual ui is what I see in the mock"). 폴백이면 조용히 시스템 서체다.
  const nf = useNumFont();
  // Anchor size follows the camera (see anchorSizeForZoom). The initial zoom is whatever the
  // region fit resolves to; until the first onCameraIdle we assume a city-level fit (18 pt).
  const [camZoom, setCamZoom] = useState<number>(FALLBACK_CAM.zoom);
  const anchorBox = anchorSizeForZoom(camZoom);
  const [routes, setRoutes] = useState<RouteInfo[]>([]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [selId, setSelId] = useState<string | null>(draft.routeId || null);
  // 지도 화면은 **슬롯이 정해진 뒤** 들어오는 화면이다 — 훅을 쓰면서 조명 자동켜짐이
  // 여기에도 생겼다(전에는 요청 화면에만 있었다). 안전 필터가 화면마다 다르게 켜지면
  // 그건 필터가 아니라 우연이다.
  const { chips, toggle: toggleChip, clear: clearChips, litAuto } = useRouteChips();
  const [detent, setDetent] = useState<Detent>('peek');
  // 픽업지(집) — 거리 정렬의 기준점이자 지도 위의 기준 마커. 실패는 조용히 넘긴다:
  // 주소를 못 읽는 건 코스를 못 보여줄 이유가 아니고, 그때는 정렬이 예전 순서로 돌아갈 뿐이다.
  const [pickup, setPickup] = useState<{ lat: number; lng: number } | null>(null);
  useEffect(() => {
    fetchAddresses()
      .then((as) => {
        const a = as.find((x) => x.isDefault && x.lat != null) ?? as.find((x) => x.lat != null);
        if (a?.lat != null && a.lng != null) setPickup({ lat: a.lat, lng: a.lng });
      })
      .catch(() => {});
  }, []);
  const [mapReady, setMapReady] = useState(false);
  // 상단 크롬의 실측 높이 → mapPadding. 초기값은 칩 한 줄 기준의 종전 값이라, 첫 프레임에도
  // 지도가 말이 되는 상태로 뜬다. (top 오프셋 54를 포함한 화면 상단부터의 높이)
  const [chromeH, setChromeH] = useState(116);

  const h = useRef(new Animated.Value(PEEK)).current;
  const hFrom = useRef(PEEK);

  // ── 데이터 ────────────────────────────────────────────────────────────────
  const load = useCallback(() => {
    setState('loading');
    // Whole catalog, like request.tsx — ruling #14/#15: discovery is ranked by distance from the
    // PICKUP (orderByProximity below), not fenced by profiles.district. Two screens on two different
    // queries also dropped course-map picks that request.tsx could not find in its own list (review
    // 2026-08-19). The camera, not the query, keeps the view local (see `region`).
    fetchRoutes()
      .then((rs) => {
        setRoutes(rs);
        setState('ready');
        // 목록이 바뀌어 선택이 사라졌으면 첫 **active**만 자동 선택한다. candidate는 절대
        // 자동 선택하지 않는다 — 서버가 candidate_ack 없이 거절하므로, 고른 적 없는 코스로
        // 에러를 보게 된다. active가 없으면 선택 없음(코스 미정)이 정직한 상태다.
        setSelId((cur) => {
          if (cur && rs.some((r) => r.id === cur)) return cur;
          return rs.find((r) => r.status === 'active')?.id ?? null;
        });
      })
      .catch((e) => { console.warn('[course-map] routes:', e?.message ?? e); setState('error'); });
  }, []);
  useEffect(load, [load]);

  // 목록도 **픽업지에서 가까운 순**. 요청 화면 캐러셀과 같은 규칙을 쓴다 — 두 화면이 같은
  // 카탈로그를 다른 순서로 보여주면 사용자는 어느 쪽을 믿어야 할지 알 수 없다.
  const shown = useMemo(
    () => orderByProximity(routes.filter((r) => matchesChips(r, chips)), pickup),
    [routes, chips, pickup?.lat, pickup?.lng],
  );
  const sel = useMemo(() => routes.find((r) => r.id === selId) ?? null, [routes, selId]);

  // ── 시트 ──────────────────────────────────────────────────────────────────
  // 고른 코스가 있는가를 **ref로** 들고 있는 이유: 아래 `pan`은 useRef로 한 번만 만들어져서
  // 첫 렌더의 `snap` 클로저를 영구히 붙잡는다. `snap`이 `sel`을 직접 읽으면 드래그는 세션
  // 내내 "선택 없음"만 보게 된다 — 조용히 틀리는 종류의 고장이다.
  const hasSel = useRef(false);
  useEffect(() => { hasSel.current = !!sel; }, [sel]);

  const snap = useCallback((to: Detent) => {
    // 고른 코스가 없을 때 detail은 **막다른 골목**이다: 88% 높이의 흰 판이 지도와 목록을
    // 둘 다 덮은 채 "지도의 앵커를 탭하거나 목록에서 고르라"고 말한다 — 자기가 가린 것을
    // 가리키는 안내다. 상세가 없는 대상의 상세는 없다. 목록에서 멈춘다.
    if (to === 'detail' && !hasSel.current) to = 'list';
    setDetent(to);
    hFrom.current = HEIGHT[to];
    // 스프링 — 손가락이 언제든 가로챌 수 있어야 한다 (DESIGN.md §7c 상호작용 최고법).
    Animated.spring(h, { toValue: HEIGHT[to], useNativeDriver: false, bounciness: 3, speed: 14 }).start();
  }, [h]);

  const pan = useRef(
    PanResponder.create({
      onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dy) > 4,
      onPanResponderGrant: () => { h.stopAnimation((v: number) => { hFrom.current = v; }); },
      onPanResponderMove: (_e, g) => {
        const next = Math.min(DETAIL, Math.max(PEEK, hFrom.current - g.dy));
        h.setValue(next);
      },
      onPanResponderRelease: (_e, g) => {
        const cur = Math.min(DETAIL, Math.max(PEEK, hFrom.current - g.dy));
        // 속도를 존중한다: 빠른 플릭은 위치보다 의도를 더 잘 말한다
        const flick = g.vy < -0.6 ? 1 : g.vy > 0.6 ? -1 : 0;
        const order: Detent[] = ['peek', 'list', 'detail'];
        let idx = cur > (LIST + DETAIL) / 2 ? 2 : cur > (PEEK + LIST) / 2 ? 1 : 0;
        if (flick) idx = Math.min(2, Math.max(0, idx + flick));
        snap(order[idx]);
      },
    }),
  ).current;

  const pick = (r: RouteInfo) => {
    haptic('light');
    setSelId(r.id);
    snap('peek');   // 지도를 즉시 돌려준다 — 고른 결과를 보는 게 다음 행동이다
  };

  const book = () => {
    if (!sel) return;
    // 선택만 전달한다. candidate 확인 의식과 스냅샷 스탬프는 요청 화면이 소유한다
    // (게이트가 두 곳에 흩어지면 둘 다 반쪽이 된다).
    draft.routeId = sel.id;
    router.back();
  };

  // ── 지도 ──────────────────────────────────────────────────────────────────
  // useMemo: `shown`이 이미 메모돼 있으므로 이것도 안정적이고, 아래 region의 의존성이
  // **정적으로 검사 가능한 단순 식**이 된다 (eslint react-hooks/use-memo).
  const withTrace = useMemo(() => shown.filter((r) => r.trace.length > 1), [shown]);

  // 고른 코스가 있으면 그 코스에, 없으면 **보이는 코스 전부**에 맞춘다.
  // 후자가 중요해진 이유: 카탈로그가 반포를 넘어 잠원·성수·압구정·이촌까지 늘었는데
  // 폴백 카메라는 반포 고정이라, 반포 밖 코스는 목록에 있으면서 지도에는 한 번도 보이지
  // 않았다 — 27개를 세어 놓고 8개만 보여주는 지도였다.
  // ⚠ 이전 의존성은 `withTrace.map(r => r.id).join(',')` 였다 — id만 추적하는 키라,
  // **id가 그대로인 채 트레이스 내용만 바뀌면 카메라가 다시 맞지 않는다**(카탈로그가 코스를
  // 다시 자르고 재조회한 경우가 정확히 그 모양이다). 게다가 복합식이라 린터가 검사할 수도 없었다.
  // eslint react-hooks/exhaustive-deps 가 잡아 준 실제 결함이다.
  // Camera: the selected course, else — when a pickup pin exists — the pin plus the nearest few courses
  // (withTrace is already ordered by distance from the pickup), else everything. Fitting all 50+ routes
  // gave a city-wide view where anchors are dots; the owner's question is "what is near my pickup".
  const NEAR_FIT = 6;
  const region = useMemo(() => {
    if (sel) return regionOf([sel.trace]);
    if (pickup && withTrace.length > 0) {
      const near = withTrace.slice(0, NEAR_FIT).map((r) => r.trace);
      return regionOf([...near, [{ lat: pickup.lat, lng: pickup.lng }]]);
    }
    return regionOf(withTrace.map((r) => r.trace));
  }, [sel, withTrace, pickup]);

  const mapNode = !maps ? (
    <View style={[StyleSheet.absoluteFill, s.center]}>
      <View style={s.infoCard}><Text style={s.infoTitle}>지도를 불러올 수 없어요</Text>
        <Text style={s.infoBody}>앱을 업데이트하면 지도가 표시돼요. 코스 목록은 아래에서 그대로 볼 수 있어요.</Text></View>
    </View>
  ) : (
    <maps.NaverMapView
      style={StyleSheet.absoluteFill}
      // ⚠ `region`과 `camera`를 **함께** 주면 안 된다 — 패키지 문서: "region이 존재해도
      // camera가 설정되면 동작하지 않습니다". 담을 지오메트리가 없을 때만 카메라로 떨어진다.
      {...(region ? { region } : { camera: FALLBACK_CAM })}
      // 상단 크롬은 칩이 몇 줄로 감기느냐에 따라 자란다(어두운 슬롯의 조명 자동켜짐 문구가
      // 정확히 그 경우다). 높이를 **재서** 넣는다 — 116은 칩이 한 줄일 때만 맞는 숫자였고,
      // 두 줄이 되는 순간 맞춘 코스의 윗부분이 고지 카드 밑으로 들어갔다.
      mapPadding={{ top: chromeH, bottom: PEEK, left: 0, right: 0 }}
      isShowLocationButton={false}
      isShowCompass={false}
      isShowScaleBar
      isShowZoomControls={false}
      isTiltGesturesEnabled={false}
      isRotateGesturesEnabled={false}
      onInitialized={() => setMapReady(true)}
      // Anchor size follows zoom (anchorSizeForZoom). Idle, not Changed: one re-render per
      // gesture instead of one per frame, and the size only matters once the camera rests.
      onCameraIdle={(c: { zoom: number }) => { if (Number.isFinite(c.zoom)) setCamZoom(c.zoom); }}
    >
      {/* 고스트 — 선택 아닌 모든 실측 코스. 케이싱 없이 얇게: 문맥이지 내용이 아니다 */}
      {withTrace.filter((r) => r.id !== selId).map((r) => (
        <maps.NaverMapPolylineOverlay
          key={`g-${r.id}`}
          coords={r.trace.map((p) => ({ latitude: p.lat, longitude: p.lng }))}
          width={2}
          color={paper.faint}
        />
      ))}
      {/* 선택 — 화면에서 유일하게 채도를 가진 획.
          ⚠ 실선 = 실측(승격된 코스), 점선 = 예정 경로. 카피만으로 "이건 예정입니다"라고 하고
          선은 실측과 똑같이 자신 있게 그리면, 사람은 카피가 아니라 선을 믿는다. K7 러너 지도와
          같은 어휘다: 점선 = 인쇄된 코스, 실선 = 지금 그어지고 있는 잉크. */}
      {sel && sel.trace.length > 1 && (
        <maps.NaverMapPathOverlay
          coords={sel.trace.map((p) => ({ latitude: p.lat, longitude: p.lng }))}
          width={3.5}
          color={lilac.accent}
          outlineWidth={1}
          outlineColor="#FFFFFF"
        />
      )}
      {/* 앵커 — 트레이스가 없어도 여긴 진짜다. 캡션은 선택된 것에만(라벨 충돌 방지) */}
      {withTrace.map((r) => {
        const on = r.id === selId;
        // The selected anchor keeps its +8 pt emphasis in every variant — the size
        // question is about the base, and dropping the emphasis would change a
        // second thing at the same time.
        const box = anchorBox + (on ? ANCHOR_SEL_BUMP : 0);
        return (
          <maps.NaverMapMarkerOverlay
            key={`a-${r.id}`}
            latitude={r.trace[0].lat}
            longitude={r.trace[0].lng}
            anchor={{ x: 0.5, y: 0.5 }}
            width={box}
            height={box}
            // 회전 사각형(다이아몬드) — 기본 네이버 핀은 '검색 결과'를 뜻해서 만남 장소로 읽히지
            // 않는다. K7 러너 지도와 **같은 에셋**이라 두 화면에서 앵커가 같은 모양이다.
            image={ROUTE_ANCHOR}
            caption={on ? { text: r.name } : undefined}
            onTap={() => pick(r)}
          />
        );
      })}
      {/* 픽업지 = 집. "가까운 순"이 말이 되려면 기준점이 지도에 보여야 한다 —
          보이지 않는 기준으로 매긴 순위는 사용자가 검증할 수 없다. (Sean 2026-08-14) */}
      {pickup && (
        <maps.NaverMapMarkerOverlay
          latitude={pickup.lat} longitude={pickup.lng}
          anchor={{ x: 0.5, y: 0.5 }} width={30} height={30}
          image={PICKUP_HOUSE} caption={{ text: '픽업' }} zIndex={4}
        />
      )}
    </maps.NaverMapView>
  );

  // ── 시트 본문 ─────────────────────────────────────────────────────────────
  const isCand = sel?.status === 'candidate';

  // 왕복 이동을 포함한 총거리 (Sean ruling #15) — 픽업 핀에서 트레이스 위 최근접점까지의
  // **직선** 거리를 왕복으로 세어 코스 km에 더한 **추정치**. 그래서 '약'이고, 라우팅 엔진이
  // 없으므로 약속이 아니다. 핀이 없으면(pickup null) 아무 주장도 하지 않는다.
  const totalKm = sel && pickup ? totalKmFor(sel, pickup)?.totalKm ?? null : null;
  const totalLine = totalKm == null ? null
    : `이동 포함 약 ${Number.isInteger(totalKm) ? totalKm : totalKm.toFixed(1)}km`;

  return (
    <View style={s.root}>
      {mapNode}
      {/* 시스템 바 스트립 — 지도가 시계·노치 뒤로 번지던 것 (실측). 지도 **위**,
          상단 크롬 **아래**: 아래 검색줄 카드는 안전 영역보다 위에서 시작하므로 순서가 뒤집히면
          카드 머리가 스트립에 먹힌다. */}
      <StatusBarCover />

      {/* 상단 크롬 — 검색 자리(뒤로)와 필터 칩. 지도 위 떠 있는 층은 이 하나뿐 */}
      {/* 상단 크롬 = 하나의 흐르는 컬럼(검색줄 → 칩 → 고지 카드). box-none 이라 컨테이너 자체는
          터치를 통과시키고, 자식(칩·재시도 버튼)만 받는다 — 지도 제스처를 죽이지 않는다. */}
      <View
        style={s.top}
        pointerEvents="box-none"
        onLayout={(e) => {
          const top = Platform.OS === 'ios' ? 54 : 16;
          const next = Math.round(top + e.nativeEvent.layout.height + 8);
          setChromeH((cur) => (Math.abs(cur - next) > 1 ? next : cur));   // 재렌더 루프 방지
        }}
      >
        <View style={s.search}>
          <Pressable onPress={goBackOrHome} hitSlop={10} accessibilityRole="button" accessibilityLabel="뒤로" style={s.backBtn}>
            <Text style={{ fontSize: 19, fontWeight: '900', color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={s.searchTxt} numberOfLines={1}>
            {state === 'ready' ? `${shown.length}개 코스` : state === 'loading' ? '코스 불러오는 중' : '코스를 불러오지 못했어요'}
          </Text>
        </View>
        <RouteChipRow
          routes={routes} chips={chips} litAuto={litAuto}
          onToggle={toggleChip} variant="floating" style={{ marginTop: 8 }}
        />
        {/* 실측 코스가 하나도 없을 때 — 빈 판정이 아니라 사실과 다음 행동 */}
        {/* 코스가 0개인 것과 '실측 전'인 것은 다른 사실이다. 예전엔 둘 다 같은 카드로 그려서
            코스가 하나도 없을 때 "**0개** 코스의 만남 장소는 정해져 있고…"라고, 0개에 대해
            무언가를 주장하는 문장이 나왔다. 개수를 본문에 끼워 넣으면 0이 들어올 수 있다. */}
        {state === 'ready' && routes.length === 0 && (
          <View style={s.infoWrap} pointerEvents="none">
            <View style={s.infoCard}>
              <Text style={s.infoTitle}>등록된 코스가 없어요</Text>
              <Text style={s.infoBody}>아직 이 지역에 코스가 없어요. 코스 없이도 예약은 접수돼요.</Text>
            </View>
          </View>
        )}
        {/* 선이 하나도 없을 때 */}
        {state === 'ready' && routes.length > 0 && withTrace.length === 0 && (
          <View style={s.infoWrap} pointerEvents="none">
            <View style={s.infoCard}>
              <Text style={s.infoTitle}>아직 실측된 코스가 없어요</Text>
              <Text style={s.infoBody}>
                {routes.length}개 코스의 만남 장소는 정해져 있고, 첫 반려견 동반 러닝이 그 코스의 지도를 만듭니다.
              </Text>
            </View>
          </View>
        )}
        {/* 선은 있는데 아직 아무도 달려보지 않았을 때 — 세 번째 상태다. 선이 그려졌다는 이유만으로
            '실측'이라고 말하면 그게 곧 조작이 된다 (0082 source='algo' = 예정 경로). */}
        {state === 'ready' && withTrace.length > 0 && withTrace.every((r) => traceKind(r) !== 'verified') && (
          <View style={s.infoWrap} pointerEvents="none">
            <View style={s.infoCard}>
              <Text style={s.infoTitle}>예정 경로를 보고 있어요</Text>
              <Text style={s.infoBody}>{TRACE_NOTE.planned}</Text>
            </View>
          </View>
        )}
        {state === 'error' && (
          <View style={s.infoWrap}>
            <View style={[s.infoCard, { borderColor: paper.critical }]}>
              <Text style={[s.infoTitle, { color: paper.critical }]}>코스를 불러오지 못했어요</Text>
              <Pressable onPress={load} style={s.retry} accessibilityRole="button"><Text style={s.retryTxt}>다시 시도</Text></Pressable>
            </View>
          </View>
        )}
      </View>

      {/* ── 3단 시트 ── */}
      <Animated.View style={[s.sheet, { height: h }]}>
        <View style={s.rule} />
        <View {...pan.panHandlers} style={s.grabZone} accessibilityRole="adjustable"
          accessibilityLabel={`코스 시트, ${detent === 'peek' ? '접힘' : detent === 'list' ? '목록' : '상세'}`}>
          <View style={s.grab} />
        </View>

        {/* PEEK — 어느 단이든 항상 보이는 머리 */}
        <Pressable onPress={() => snap(detent === 'peek' ? 'list' : 'peek')} style={s.head}>
          <View style={{ flex: 1 }}>
            <Text style={[s.kick, isCand && { color: paper.pending }]} numberOfLines={1}>
              {sel ? (isCand ? `점검 예정 · ${sel.area}` : `${sel.area} · ${sel.terrain}`) : '코스 미정'}
            </Text>
            {/* 이름 옆 칸이 km을 말한다 — 이름에 박힌 길이까지 그리면 같은 양의 숫자가 둘이 되고,
                반올림 때문에 서로 다르다(`4.97km` 옆에 `5`). 요금의 권위는 km 컬럼이다(T-KM). */}
            <Text style={s.name} numberOfLines={1}>{sel?.name ?? '코스를 선택해주세요'}</Text>
            {/* 왕복 이동을 포함한 총거리 (ruling #15) — 옆 칸의 코스 km을 **대체하지 않는다**.
                핀이 없거나 진입점을 잴 수 없으면 아예 나오지 않는다: 못 재는 추정치를 0으로 그리지 않는다. */}
            {totalLine && <Text style={s.total} numberOfLines={1}>{totalLine}</Text>}
          </View>
          {sel && <Text style={[s.km, nf]}>{sel.km}<Text style={s.kmUnit}>km</Text></Text>}
        </Pressable>

        {detent === 'peek' && (
          <View style={{ paddingHorizontal: 14 }}>
            <Pressable
              onPress={book}
              disabled={!sel}
              accessibilityRole="button"
              style={({ pressed }) => [s.cta, isCand && { backgroundColor: paper.pending },
                !sel && { backgroundColor: paper.disabledFill }, pressed && { opacity: 0.92 }]}
            >
              <Text style={[s.ctaTxt, !sel && { color: paper.dim }]}>
                {!sel ? '코스를 선택해주세요' : isCand ? '점검 전 코스로 예약' : '이 코스로 예약하기'}
              </Text>
            </Pressable>
          </View>
        )}

        {/* LIST — 시트의 중간 단이 곧 '부유 목록' */}
        {detent === 'list' && (
          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 14, paddingBottom: 20 }}>
            {shown.length === 0 ? (
              <View style={{ paddingTop: 8 }}>
                <Text style={s.emptyTxt}>{emptyChipCopy(chips)}</Text>
                <Pressable onPress={clearChips} style={s.clearBtn} accessibilityRole="button">
                  <Text style={s.clearTxt}>필터 해제</Text>
                </Pressable>
              </View>
            ) : shown.map((r) => {
              const on = r.id === selId;
              return (
                <Pressable key={r.id} onPress={() => pick(r)} accessibilityRole="button"
                  accessibilityState={{ selected: on }}
                  style={[s.li, on && s.liOn]}>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                      <Text style={s.liName} numberOfLines={1}>{r.name}</Text>
                      {r.status === 'candidate' && <Text style={s.candTag}>점검 예정</Text>}
                    </View>
                    <Text style={s.liSub} numberOfLines={1}>
                      {[r.terrain, r.shade === 'high' ? '그늘 최상' : null, r.lighting === 'lit' ? '조명' : r.lighting === 'none' ? '조명 없음' : null]
                        .filter(Boolean).join(' · ')}
                    </Text>
                  </View>
                  {/* [Sean 2026-08-24] "course map's listed maps should have km unit on the right
                      side not just a number." 벌거벗은 숫자는 무엇의 5인지 말하지 않는다 —
                      단위가 숫자 오른쪽에 붙어 한 덩어리로 읽힌다 (live.tsx의 km 스탯과 같은 문법).
                      ⚠ 여기 오는 값은 **코스 길이 하나**다. 이동 포함 총거리(totalKmFor)는
                      머리(peek)에만 '이동 포함 약 …'이라는 라벨을 달고 남는다: 라벨 없는 두 개의
                      km이 한 화면에서 나란해지는 순간 어느 쪽이 코스 길이인지 알 수 없어진다. */}
                  <Text style={[s.liKm, nf]}>{r.km}<Text style={s.liKmUnit}> km</Text></Text>
                </Pressable>
              );
            })}
          </ScrollView>
        )}

        {/* DETAIL — 앵커·시간대·메타. 지도는 위에 남아 맥락을 잃지 않는다 */}
        {/* DETAIL을 열었는데 고른 코스가 없을 때. 예전엔 88% 시트가 통째로 흰 판이었다 —
            아무것도 주장하지 않으니 정직하긴 했지만, 화면이 말을 안 하는 것과 정직한 것은 다르다.
            그리고 **고를 코스가 없을 때 '고르세요'라고 하면 그건 또 다른 거짓말**이라, 세 경우를
            갈라서 말한다: 못 불러왔다 / 조건에 맞는 게 없다 / 아직 안 골랐다. */}
        {detent === 'detail' && !sel && (
          <View style={{ paddingHorizontal: 14, paddingTop: 4 }}>
            <Text style={s.emptyTxt}>
              {state === 'error' ? '코스를 불러오지 못해서 상세를 열 수 없어요'
                : state === 'loading' ? '코스를 불러오는 중이에요'
                : shown.length === 0 ? emptyChipCopy(chips)
                : '아직 고른 코스가 없어요'}
            </Text>
            {state === 'ready' && shown.length > 0 && (
              <Text style={s.detailHint}>지도의 앵커를 탭하거나 목록에서 고르면 여기에 상세가 열려요</Text>
            )}
            {state === 'error' && (
              <Pressable onPress={load} style={s.clearBtn} accessibilityRole="button">
                <Text style={s.clearTxt}>다시 시도</Text>
              </Pressable>
            )}
          </View>
        )}

        {detent === 'detail' && sel && (
          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 14, paddingBottom: 28 }}>
            {/* 본문은 `course/[id]`와 **같은 컴포넌트**다 — 두 화면이 같은 코스에 대해 다른
                말을 하지 않도록. 지도는 위에 남아 맥락을 잃지 않는다 */}
            <CourseDetailBody route={sel} />
            <Pressable onPress={book} accessibilityRole="button"
              style={({ pressed }) => [s.cta, isCand && { backgroundColor: paper.pending }, pressed && { opacity: 0.92 }]}>
              <Text style={s.ctaTxt}>{isCand ? '점검 전 코스로 예약' : '이 코스로 예약하기'}</Text>
            </Pressable>
          </ScrollView>
        )}
      </Animated.View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  center: { alignItems: 'center', justifyContent: 'center' },

  top: { position: 'absolute', left: 0, right: 0, top: Platform.OS === 'ios' ? 54 : 16, paddingHorizontal: 12, zIndex: 6 },
  search: {
    flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: paper.canvas,
    borderWidth: 1, borderColor: '#EDEBE6', paddingVertical: 9, paddingHorizontal: 10,
    shadowColor: '#000', shadowOpacity: 0.09, shadowRadius: 12, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  backBtn: { width: 30, height: 30, alignItems: 'center', justifyContent: 'center' },
  searchTxt: { flex: 1, fontSize: 15, fontWeight: '700', color: paper.text },

  // ⚠ 고정 top 금지. 예전엔 `top: 170`이었는데, 칩 행이 두 줄로 감기면(조명 자동켜짐 문구가
  // 붙는 어두운 슬롯이 정확히 그 경우다) 위 크롬이 자라서 이 카드를 덮어썼다 — 시뮬레이터에서
  // 실제로 제목이 가려졌다. 이제 상단 크롬 컬럼 **안에서 흐른다**: 칩이 몇 줄이든 카드는 항상
  // 그 아래다. 매직 넘버를 키우는 건 다음 줄바꿈까지만 사는 수정이다.
  infoWrap: { marginTop: 8 },
  infoCard: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EDEBE6', padding: 13,
    shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 14, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  infoTitle: { fontSize: 16, fontWeight: '800', color: paper.ink },
  infoBody: { fontSize: 15, color: paper.dim, marginTop: 5, lineHeight: 20 },
  retry: { marginTop: 10, borderWidth: 1.5, borderColor: paper.ink, paddingVertical: 10, alignItems: 'center', minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 15, fontWeight: '800', color: paper.ink },

  sheet: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    shadowColor: '#000', shadowOpacity: 0.13, shadowRadius: 26, shadowOffset: { width: 0, height: -6 }, elevation: 12, zIndex: 7,
  },
  rule: { height: 2, backgroundColor: paper.line },   // 브랜드 선 — 시트의 머리
  grabZone: { paddingVertical: 9, alignItems: 'center' },
  grab: { width: 38, height: 4, borderRadius: 99, backgroundColor: '#E2E0DA' },
  head: { flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 14, paddingBottom: 4, minHeight: 44 },
  kick: { fontSize: 15, color: paper.dim, fontWeight: '700' },
  name: { fontSize: 19, fontWeight: '800', color: paper.ink, marginTop: 3 },
  total: { fontSize: 15, color: paper.faint, fontWeight: '700', marginTop: 2 },
  // Oswald는 lineHeight를 명시하지 않으면 어센더가 잘린다 (BUG A) — 26 × 1.23 = 32.
  km: { fontSize: 26, lineHeight: 32, fontWeight: '800', color: paper.ink, marginLeft: 10 },
  kmUnit: { fontSize: 15, color: paper.faint, fontWeight: '700' },

  cta: { backgroundColor: paper.action, paddingVertical: 15, alignItems: 'center', marginTop: 12, minHeight: 44, justifyContent: 'center' },
  ctaTxt: { fontSize: 15, fontWeight: '800', color: '#FFFFFF' },

  li: { flexDirection: 'row', alignItems: 'center', paddingVertical: 13, borderBottomWidth: 1, borderBottomColor: '#F0EEE9', minHeight: 44 },
  liOn: { backgroundColor: paper.wash, borderLeftWidth: 3, borderLeftColor: paper.line, marginHorizontal: -14, paddingHorizontal: 14 },
  liName: { fontSize: 16, fontWeight: '800', color: paper.ink, flexShrink: 1 },
  liSub: { fontSize: 15, color: paper.dim, marginTop: 2 },
  liKm: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: paper.text, marginLeft: 10 },
  // 단위도 데이터의 일부다 — 15pt 플로어를 받는다 (글리프 예외가 아니다). dim = 5.7:1.
  liKmUnit: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.dim },
  candTag: { fontSize: 15, color: paper.pending, fontWeight: '800', marginLeft: 6 },

  emptyTxt: { fontSize: 15, color: paper.text, fontWeight: '700' },
  detailHint: { fontSize: 15, color: paper.dim, marginTop: 6, lineHeight: 20 },
  clearBtn: { marginTop: 10, borderWidth: 1.5, borderColor: paper.line, paddingVertical: 10, paddingHorizontal: 14, alignSelf: 'flex-start', minHeight: 44, justifyContent: 'center' },
  clearTxt: { fontSize: 15, fontWeight: '800', color: paper.ink },

});
