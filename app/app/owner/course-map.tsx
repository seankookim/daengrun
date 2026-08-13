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
import { fetchMyProfile, fetchRoutes } from '../../src/lib/api';
import { CourseDetailBody } from '../../src/components/course-detail';
import { emptyChipCopy, matchesChips, RouteChipRow, useRouteChips } from '../../src/components/route-chips';
import { getNaverMap } from '../../src/lib/geo';
import { haptic } from '../../src/lib/haptics';
import { RouteInfo, draft } from '../../src/store';
import { paper } from '../../src/theme';

const { height: SCREEN_H } = Dimensions.get('window');
const PEEK = 148;                          // 이름 + km + CTA 만
const LIST = Math.round(SCREEN_H * 0.55);
const DETAIL = Math.round(SCREEN_H * 0.88);
type Detent = 'peek' | 'list' | 'detail';
const HEIGHT: Record<Detent, number> = { peek: PEEK, list: LIST, detail: DETAIL };

// 반포 중심 — 코스가 하나도 없을 때의 초기 카메라. 전부 candidate여도 앵커는 찍히므로
// 지도가 빈 채로 열리는 경우는 '코스 0개'뿐이고, 그건 아래 emptyCard가 말한다.
const FALLBACK_CAM = { latitude: 37.5069, longitude: 126.9954, zoom: 13.4 };

// 칩 술어·개수·조명 자동켜짐은 `components/route-chips`가 소유한다 (K5와 **같은 정의** —
// 복제돼 있던 시절 라벨이 이미 갈라졌었다: 여기는 '그늘', 요청 화면은 '그늘 많음').

/** 트레이스 → 카메라가 담을 수 있는 중심. 실좌표라 평균이면 충분하다(코스 하나는 수백 m 규모). */
function centerOf(r: RouteInfo | null): { latitude: number; longitude: number } | null {
  if (!r) return null;
  if (r.trace.length > 0) {
    const la = r.trace.reduce((s, p) => s + p.lat, 0) / r.trace.length;
    const ln = r.trace.reduce((s, p) => s + p.lng, 0) / r.trace.length;
    return { latitude: la, longitude: ln };
  }
  return null; // 앵커 좌표는 RouteInfo에 없다 — 없는 값을 지어내지 않는다
}

export default function CourseMap() {
  const maps = getNaverMap();
  const [routes, setRoutes] = useState<RouteInfo[]>([]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [selId, setSelId] = useState<string | null>(draft.routeId || null);
  // 지도 화면은 **슬롯이 정해진 뒤** 들어오는 화면이다 — 훅을 쓰면서 조명 자동켜짐이
  // 여기에도 생겼다(전에는 요청 화면에만 있었다). 안전 필터가 화면마다 다르게 켜지면
  // 그건 필터가 아니라 우연이다.
  const { chips, toggle: toggleChip, clear: clearChips, litAuto } = useRouteChips();
  const [detent, setDetent] = useState<Detent>('peek');
  const [mapReady, setMapReady] = useState(false);

  const h = useRef(new Animated.Value(PEEK)).current;
  const hFrom = useRef(PEEK);

  // ── 데이터 ────────────────────────────────────────────────────────────────
  const load = useCallback(() => {
    setState('loading');
    fetchMyProfile()
      .then((p) => fetchRoutes(p?.district ?? null))
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

  const shown = useMemo(() => routes.filter((r) => matchesChips(r, chips)), [routes, chips]);
  const sel = useMemo(() => routes.find((r) => r.id === selId) ?? null, [routes, selId]);

  // ── 시트 ──────────────────────────────────────────────────────────────────
  const snap = useCallback((to: Detent) => {
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
  const cam = useMemo(() => centerOf(sel) ?? FALLBACK_CAM, [sel]);
  const withTrace = shown.filter((r) => r.trace.length > 1);

  const mapNode = !maps ? (
    <View style={[StyleSheet.absoluteFill, s.center]}>
      <View style={s.infoCard}><Text style={s.infoTitle}>지도를 불러올 수 없어요</Text>
        <Text style={s.infoBody}>앱을 업데이트하면 지도가 표시돼요. 코스 목록은 아래에서 그대로 볼 수 있어요.</Text></View>
    </View>
  ) : (
    <maps.NaverMapView
      style={StyleSheet.absoluteFill}
      camera={{ ...cam, zoom: sel?.trace.length ? 15 : FALLBACK_CAM.zoom }}
      mapPadding={{ top: 116, bottom: PEEK, left: 0, right: 0 }}
      isShowLocationButton={false}
      isShowCompass={false}
      isShowScaleBar
      isShowZoomControls={false}
      isTiltGesturesEnabled={false}
      isRotateGesturesEnabled={false}
      onInitialized={() => setMapReady(true)}
    >
      {/* 고스트 — 선택 아닌 모든 실측 코스. 케이싱 없이 얇게: 문맥이지 내용이 아니다 */}
      {withTrace.filter((r) => r.id !== selId).map((r) => (
        <maps.NaverMapPolylineOverlay
          key={`g-${r.id}`}
          coords={r.trace.map((p) => ({ latitude: p.lat, longitude: p.lng }))}
          width={3}
          color={paper.faint}
        />
      ))}
      {/* 선택 — 화면에서 유일하게 채도를 가진 획 */}
      {sel && sel.trace.length > 1 && (
        <maps.NaverMapPathOverlay
          coords={sel.trace.map((p) => ({ latitude: p.lat, longitude: p.lng }))}
          width={6}
          color={paper.line}
          outlineWidth={2}
          outlineColor="#FFFFFF"
        />
      )}
      {/* 앵커 — 트레이스가 없어도 여긴 진짜다. 캡션은 선택된 것에만(라벨 충돌 방지) */}
      {withTrace.map((r) => (
        <maps.NaverMapMarkerOverlay
          key={`a-${r.id}`}
          latitude={r.trace[0].lat}
          longitude={r.trace[0].lng}
          anchor={{ x: 0.5, y: 0.5 }}
          width={r.id === selId ? 18 : 12}
          height={r.id === selId ? 18 : 12}
          caption={r.id === selId ? { text: r.name } : undefined}
          onTap={() => pick(r)}
        />
      ))}
    </maps.NaverMapView>
  );

  // ── 시트 본문 ─────────────────────────────────────────────────────────────
  const isCand = sel?.status === 'candidate';

  return (
    <View style={s.root}>
      {mapNode}

      {/* 상단 크롬 — 검색 자리(뒤로)와 필터 칩. 지도 위 떠 있는 층은 이 하나뿐 */}
      <View style={s.top}>
        <View style={s.search}>
          <Pressable onPress={() => router.back()} hitSlop={10} accessibilityRole="button" accessibilityLabel="뒤로" style={s.backBtn}>
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
      </View>

      {/* 실측 코스가 하나도 없을 때 — 빈 판정이 아니라 사실과 다음 행동 */}
      {state === 'ready' && withTrace.length === 0 && (
        <View style={s.infoWrap} pointerEvents="none">
          <View style={s.infoCard}>
            <Text style={s.infoTitle}>아직 실측된 코스가 없어요</Text>
            <Text style={s.infoBody}>
              {routes.length}개 코스의 만남 장소는 정해져 있고, 첫 반려견 동반 러닝이 그 코스의 지도를 만듭니다.
            </Text>
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
            <Text style={s.name} numberOfLines={1}>{sel?.name ?? '코스를 선택해주세요'}</Text>
          </View>
          {sel && <Text style={s.km}>{sel.km}<Text style={s.kmUnit}>km</Text></Text>}
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
                  <Text style={s.liKm}>{r.km}</Text>
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
  searchTxt: { flex: 1, fontSize: 14, fontWeight: '700', color: paper.text },

  infoWrap: { position: 'absolute', left: 14, right: 14, top: Platform.OS === 'ios' ? 170 : 132, zIndex: 5 },
  infoCard: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EDEBE6', padding: 13,
    shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 14, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  infoTitle: { fontSize: 14, fontWeight: '800', color: paper.ink },
  infoBody: { fontSize: 14, color: paper.dim, marginTop: 5, lineHeight: 20 },
  retry: { marginTop: 10, borderWidth: 1.5, borderColor: paper.ink, paddingVertical: 10, alignItems: 'center', minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 14, fontWeight: '800', color: paper.ink },

  sheet: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    shadowColor: '#000', shadowOpacity: 0.13, shadowRadius: 26, shadowOffset: { width: 0, height: -6 }, elevation: 12, zIndex: 7,
  },
  rule: { height: 2, backgroundColor: paper.line },   // 브랜드 선 — 시트의 머리
  grabZone: { paddingVertical: 9, alignItems: 'center' },
  grab: { width: 38, height: 4, borderRadius: 99, backgroundColor: '#E2E0DA' },
  head: { flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 14, paddingBottom: 4, minHeight: 44 },
  kick: { fontSize: 14, color: paper.dim, fontWeight: '700' },
  name: { fontSize: 19, fontWeight: '800', color: paper.ink, marginTop: 3 },
  km: { fontSize: 26, fontWeight: '800', color: paper.ink, marginLeft: 10 },
  kmUnit: { fontSize: 12, color: paper.faint, fontWeight: '700' },

  cta: { backgroundColor: paper.action, paddingVertical: 15, alignItems: 'center', marginTop: 12, minHeight: 44, justifyContent: 'center' },
  ctaTxt: { fontSize: 15, fontWeight: '800', color: '#FFFFFF' },

  li: { flexDirection: 'row', alignItems: 'center', paddingVertical: 13, borderBottomWidth: 1, borderBottomColor: '#F0EEE9', minHeight: 44 },
  liOn: { backgroundColor: paper.wash, borderLeftWidth: 3, borderLeftColor: paper.line, marginHorizontal: -14, paddingHorizontal: 14 },
  liName: { fontSize: 14.5, fontWeight: '800', color: paper.ink, flexShrink: 1 },
  liSub: { fontSize: 14, color: paper.dim, marginTop: 2 },
  liKm: { fontSize: 16, fontWeight: '800', color: paper.text, marginLeft: 10 },
  candTag: { fontSize: 14, color: paper.pending, fontWeight: '800', marginLeft: 6 },

  emptyTxt: { fontSize: 14, color: paper.text, fontWeight: '700' },
  detailHint: { fontSize: 14, color: paper.dim, marginTop: 6, lineHeight: 20 },
  clearBtn: { marginTop: 10, borderWidth: 1.5, borderColor: paper.line, paddingVertical: 10, paddingHorizontal: 14, alignSelf: 'flex-start', minHeight: 44, justifyContent: 'center' },
  clearTxt: { fontSize: 14, fontWeight: '800', color: paper.ink },

});
