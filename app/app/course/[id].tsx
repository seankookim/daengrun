import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Dimensions, Easing, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { CourseDetailBody, traceKind } from '../../src/components/course-detail';
import { PaperBtn } from '../../src/components/paper-btn';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { HeatTrace } from '../../src/components/runcard';
import { traceToBox } from '../../src/lib/trace';
import { getNaverMap } from '../../src/lib/geo';
import { fetchRouteById } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { goBackOrHome } from '../../src/lib/nav';
import { useReducedMotion } from '../../src/lib/reducedMotion';
import { RouteInfo, session } from '../../src/store';
import { colors, lilac, paper } from '../../src/theme';

// 코스 미리보기 — 보호자·러너 공용 (코스는 공개 콘텐츠).
// 히어로: **실지도**(K4 ③, 2026-08-14) — 시드 지오메트리가 들어오기 전까지는 그릴 코스가 없어서
// 만들 수 없던 화면이다. 스키마틱 트레이스 + 볼트 도트는 은퇴가 아니라 **네이티브 지도 없는
// 빌드의 폴백**으로 남는다 ('지도를 못 그린다'와 '그릴 코스가 없다'는 다른 사실이므로 3갈래).
//
// [2026-08-13 dedup] 본문(메타 3축·설명·특징·점검·우리 기록)은 `components/course-detail`로
// 나갔다 — 코스 지도 시트의 DETAIL 단이 같은 본문을 각자 그리고 있었고, 이미 갈라져 있었다
// (여기엔 그늘/조명이 없었고, 시트엔 특징·태그·사진이 없었다). 이 화면이 소유하는 것은
// 히어로와 CTA뿐이다.
// 크롬도 함께 페이퍼 문법으로 옮긴다: 공용 본문만 페이퍼로 두고 크림·r22 잔재 위에 얹으면
// 한 화면 안에 세계가 둘이 된다.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const W = Dimensions.get('window').width;
const TRACE_W = W - 60;
const TRACE_H = 190;

// 트레이스를 따라 도는 볼트 도트 — '살아있는 코스' 연출.
// 누적 거리 비율을 inputRange로 쓰는 순수 interpolate (네이티브 드라이버, setState 없음)
function LiveDot({ points }: { points: { x: number; y: number }[] }) {
  const progress = useRef(new Animated.Value(0)).current;
  // [2026-08-11 §7c] Reduced motion stops idle loops outright — a decorative dot
  // that claims nothing is exactly the motion the setting exists to remove.
  const reduce = useReducedMotion();
  useEffect(() => {
    if (reduce) { progress.setValue(0); return; }
    const loop = Animated.loop(
      Animated.timing(progress, { toValue: 1, duration: 7000, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [progress, reduce]);

  const path = useMemo(() => {
    // 0길이 세그먼트 제거 — interpolate inputRange는 순증가여야 한다
    const pts = points.filter((p, i) => i === 0 || Math.hypot(p.x - points[i - 1].x, p.y - points[i - 1].y) > 1e-6);
    if (pts.length < 2) return null;
    const cum = [0];
    for (let i = 1; i < pts.length; i++) {
      cum.push(cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y));
    }
    const total = cum[cum.length - 1] || 1;
    return {
      input: cum.map((c) => c / total),
      xs: pts.map((p) => p.x * TRACE_W),
      ys: pts.map((p) => p.y * TRACE_H),
    };
  }, [points]);

  if (!path) return null;
  return (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', top: -7, left: -7, width: 14, height: 14, borderRadius: 7,
        backgroundColor: colors.volt, borderWidth: 2, borderColor: '#fff',
        shadowColor: colors.volt, shadowOpacity: 0.9, shadowRadius: 6, shadowOffset: { width: 0, height: 0 },
        transform: [
          { translateX: progress.interpolate({ inputRange: path.input, outputRange: path.xs }) },
          { translateY: progress.interpolate({ inputRange: path.input, outputRange: path.ys }) },
        ],
      }}
    />
  );
}

const ROUTE_ANCHOR = require('../../assets/route-anchor.png');
const ROUTE_CHEVRON = require('../../assets/route-chevron.png');

/** 두 점 사이 방위각(도, 북=0). 셰브론을 코스가 나아가는 쪽으로 돌린다. */
function bearing(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const r = Math.PI / 180, y = Math.sin((b.lng - a.lng) * r) * Math.cos(b.lat * r);
  const x = Math.cos(a.lat * r) * Math.sin(b.lat * r) - Math.sin(a.lat * r) * Math.cos(b.lat * r) * Math.cos((b.lng - a.lng) * r);
  return (Math.atan2(y, x) / r + 360) % 360;
}

/**
 * 코스 지도 증거 (K4 ③). 스키마틱 실루엣이 아니라 **진짜 지도** — 브리핑은 "예쁜 모양"이 아니라
 * "여기가 어디인지"를 알려줘야 하고, 그건 타일 없이는 불가능하다.
 *
 * 카메라는 bbox 두 모서리로 한 번 맞춘다 (K7 스파이크가 측정한 animateCameraWithTwoCoords —
 * 컨트롤드 프롭이 아니라 명령형 1회). 제스처는 **켠다**: 브리핑은 들여다보는 화면이라
 * 팬·줌이 필요하다. 기울기·회전은 끈다 (평면 지도가 코스 모양을 가장 정직하게 보여준다).
 *
 * 선의 문법은 course-map·run과 **같다**. ⚠ 대시 인코딩은 f0ceed4에서 은퇴했다 —
 * 예정도 실측도 **같은 실선**이고, 둘을 가르는 건 이제 오직 카피다. 그래서 카피가 선의
 * 생김새를 주장하면 그 카피는 곧 거짓이 된다(범례가 '점선'이라 말하던 자리가 여기였다).
 * 화면마다 다른 어휘를 쓰면 사용자는 매번 다시 배워야 한다.
 */
function CourseMapHero({ route, maps }: { route: RouteInfo; maps: NonNullable<ReturnType<typeof getNaverMap>> }) {
  const ref = useRef<{ animateCameraWithTwoCoords: (p: any) => void } | null>(null);
  const coords = useMemo(() => route.trace.map((p) => ({ latitude: p.lat, longitude: p.lng })), [route.trace]);
  const box = useMemo(() => {
    let n = -90, s = 90, e = -180, w = 180;
    coords.forEach((c) => {
      n = Math.max(n, c.latitude); s = Math.min(s, c.latitude);
      e = Math.max(e, c.longitude); w = Math.min(w, c.longitude);
    });
    return { nw: { latitude: n, longitude: w }, se: { latitude: s, longitude: e } };
  }, [coords]);
  const start = route.trace[0];
  const kind = traceKind(route);
  const planned = kind === 'planned';
  // 셰브론은 앵커 **위에** 두지 않는다 — 같은 점에 두 마커를 겹치면 다이아몬드와 삼각형이
  // 한 덩어리로 뭉개져서 둘 다 못 읽는다 (시뮬레이터에서 확인). 경로를 조금 따라간 지점에
  // 놓고 그 지점의 진행 방향으로 돌린다: "여기서 시작해서 이쪽으로 돈다"가 한눈에 읽힌다.
  const chevron = useMemo(() => {
    const t = route.trace;
    if (t.length < 3) return null;
    const i = Math.min(Math.max(2, Math.round(t.length * 0.06)), t.length - 2);
    return { at: t[i], angle: bearing(t[i - 1], t[i + 1]) };
  }, [route.trace]);

  const fit = useCallback(() => {
    ref.current?.animateCameraWithTwoCoords({ coord1: box.nw, coord2: box.se, duration: 500 });
  }, [box]);

  return (
    <View style={s.mapHero}>
      <maps.NaverMapView
        ref={ref}
        style={{ width: '100%', height: TRACE_H + 40 }}
        initialCamera={{ latitude: (box.nw.latitude + box.se.latitude) / 2, longitude: (box.nw.longitude + box.se.longitude) / 2, zoom: 14 }}
        mapPadding={{ top: 18, bottom: 18, left: 18, right: 18 }}
        isShowLocationButton={false}
        isShowCompass={false}
        isShowScaleBar
        isShowZoomControls={false}
        isTiltGesturesEnabled={false}
        isRotateGesturesEnabled={false}
        onInitialized={fit}
      >
        <maps.NaverMapPathOverlay
          coords={coords}
          width={3.5}
          color={lilac.accent}
          outlineWidth={1}
          outlineColor="#FFFFFF"
          zIndex={0}
        />
        {start && (
          <maps.NaverMapMarkerOverlay
            latitude={start.lat} longitude={start.lng}
            anchor={{ x: 0.5, y: 0.5 }} width={26} height={26}
            image={ROUTE_ANCHOR} zIndex={2}
          />
        )}
        {/* 진행 방향 셰브론 — 같은 루프도 어느 쪽으로 도는지가 브리핑에선 다른 코스다 */}
        {chevron && (
          <maps.NaverMapMarkerOverlay
            latitude={chevron.at.lat} longitude={chevron.at.lng}
            anchor={{ x: 0.5, y: 0.5 }} width={20} height={20}
            image={ROUTE_CHEVRON} angle={chevron.angle} zIndex={3}
          />
        )}
      </maps.NaverMapView>
      <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 9 }}>
        <Text style={{ fontSize: 14, color: paper.dim, flex: 1 }} numberOfLines={2}>
          {planned ? '선 = 예정 경로 · ◆ 만남 장소' : '◆ 만남 장소 · 실측 코스'}
        </Text>
        <Pressable onPress={fit} hitSlop={8} accessibilityRole="button" accessibilityLabel="코스 전체 보기" style={s.fitBtn}>
          <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>전체 보기</Text>
        </Pressable>
      </Row>
    </View>
  );
}

export default function CourseScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const df = useDisplayFont();
  const [route, setRoute] = useState<RouteInfo | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!id) { setErr('코스 정보가 없어요'); return; }
    // fetchRouteById — 디스커버리 목록에서 find하지 않는다. 그러면 예약된 candidate가 다른
    // 코스의 활성화와 동시에 브리핑 페이지를 잃고, 정지된 코스는 어제 예약해 놓고도 '찾을 수
    // 없음'으로 뜬다. 없는 코스(null)와 불러오기 실패(throw)는 다른 사실이라 분기도 다르다.
    fetchRouteById(id)
      .then((r) => { if (r) setRoute(r); else setErr('코스를 찾을 수 없어요'); })
      .catch((e) => setErr(e?.message ?? '불러오기 실패'));
    // 사진은 CourseDetailBody가 소유한다 (실패해도 코스는 뜬다)
  }, [id]);

  // 실좌표 → 박스 좌표 한 번만. 세 소비처(HeatTrace·시작 핀·LiveDot)가 같은 투영을 공유해야
  // 점이 선 위에 앉는다. 예전엔 route.trace가 이미 {x,y}라 그냥 읽었지만 이제 실좌표다.
  const boxTrace = useMemo(() => traceToBox(route?.trace), [route]);

  const maps = getNaverMap();            // 네이티브 지도 미탑재 빌드는 스키마틱으로 폴백
  const hasTrace = (route?.trace.length ?? 0) > 1;
  const isOwner = session.role === 'owner';

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvasSoft }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: isOwner ? 120 : 40 }}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56 }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 23, fontWeight: '900', color: paper.ink }, df]}>코스 미리보기</Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && <View style={s.emptyBox}><Text style={{ fontSize: 14.5, color: paper.dim }}>{err}</Text></View>}

        {route && (
          <View style={{ paddingHorizontal: 12 }}>
            {/* ---------- 히어로 ----------
                실지도(K4 ③) → SDK 없으면 스키마틱 → 트레이스 없으면 정직한 준비 중.
                세 갈래인 게 핵심이다: '지도를 못 그린다'와 '그릴 코스가 없다'는 다른 사실이고,
                스키마틱은 버리는 게 아니라 **네이티브 없는 빌드의 폴백**으로 계속 일한다. */}
            {hasTrace && maps ? (
              <CourseMapHero route={route} maps={maps} />
            ) : hasTrace ? (
              <View style={s.hero}>
                <View style={{ width: TRACE_W, height: TRACE_H, alignSelf: 'center' }}>
                  <HeatTrace points={boxTrace} width={TRACE_W} height={TRACE_H} />
                  <View style={[s.pin, { left: boxTrace[0].x * TRACE_W - 5, top: boxTrace[0].y * TRACE_H - 5, backgroundColor: colors.volt }]} />
                  <View style={[s.pin, { left: boxTrace[boxTrace.length - 1].x * TRACE_W - 5, top: boxTrace[boxTrace.length - 1].y * TRACE_H - 5, backgroundColor: colors.tang }]} />
                  <LiveDot points={boxTrace} />
                </View>
                <Row style={{ justifyContent: 'space-between', marginTop: 10 }}>
                  <Text style={{ fontSize: 14, color: '#B9BCB6' }}>● 출발 <Text style={{ color: colors.tang }}>● 도착</Text> — 스키마틱 코스도예요</Text>
                  <View style={s.kmPlate}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt }}>{route.km}km</Text>
                  </View>
                </Row>
              </View>
            ) : (
              /* [리뷰 F5] 트레이스 없으면 히어로가 말없이 증발했다 — 정직한 준비 중 슬롯 */
              <View style={[s.hero, { alignItems: 'center', justifyContent: 'center', minHeight: 120 }]}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: '#B9BCB6' }}>코스 지도 준비 중</Text>
              </View>
            )}

            {/* ---------- 이름 + 지역 ---------- */}
            <Text style={[{ fontSize: 27, color: paper.ink, marginTop: 16, fontWeight: '900' }, df]}>{route.name}</Text>
            <Text style={{ fontSize: 14, color: paper.dim, fontWeight: '700', marginTop: 4 }}>{route.area}</Text>

            {/* ---------- 본문 — 시트 DETAIL 단과 같은 컴포넌트 ---------- */}
            <CourseDetailBody route={route} style={{ marginTop: 6 }} />
          </View>
        )}
      </ScrollView>
      {/* 시스템 바 스트립 — 이 화면은 sticky 헤더가 없어 히어로 지도와 타이틀이 시계 뒤로 지나갔다 */}
      <StatusBarCover color={paper.canvasSoft} />

      {/* ---------- CTA (보호자만) — 코스에서 바로 예약으로 ----------
          [2026-08-19] 은퇴·정지 코스는 예약 문을 열지 않는다. 예전 분기는 candidate 하나만
          갈랐고 나머지를 전부 '이 코스로 예약하기'로 묶어서, 본문이 "더 이상 운영하지 않는
          코스예요"라고 말하는 화면이 바로 아래에서 그 코스를 예약하라고 권했다 —
          같은 화면 안의 두 문장이 서로를 반박하고, 눌러도 서버가 거절한다(auto-pick은
          status='active' 게이트). 숨기지 않고 **사실 + 실제 목적지**로 바꾼다: 코스 지도. */}
      {route && isOwner && (
        <View style={s.ctaBar}>
          {route.status === 'retired' || route.status === 'suspended' ? (
            <PaperBtn
              variant="secondary"
              label={route.status === 'retired' ? '운영 종료된 코스예요 — 다른 코스 보기 ›' : '점검 중인 코스예요 — 다른 코스 보기 ›'}
              onPress={() => router.push('/owner/course-map')}
            />
          ) : (
            <PaperBtn
              label={route.status === 'candidate' ? '점검 전 코스로 예약' : '이 코스로 예약하기'}
              onPress={() => router.push({ pathname: '/owner/request', params: { routeId: route.id } })}
            />
          )}
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  emptyBox: { margin: 16, backgroundColor: paper.canvas, padding: 20, alignItems: 'center', borderWidth: 1, borderColor: '#EDEBE6' },
  // 다크 히어로는 남는다 — 코스 실루엣은 이 앱의 다크 아티팩트 계열(정산 티켓·캘린더 보드)이다.
  // 바뀐 것은 라운드뿐: 샤프 코너 + 잉크 프레임.
  hero: { backgroundColor: paper.ink, padding: 15, marginTop: 14, overflow: 'hidden' },
  kmPlate: { backgroundColor: '#2A2A2A', paddingVertical: 3, paddingHorizontal: 9 },
  pin: { position: 'absolute', width: 10, height: 10, borderRadius: 5, borderWidth: 1.5, borderColor: '#fff' },
  // 실지도 히어로 — 라이트 크롬 + 2px 잉크 프레임 (DESIGN: '다크는 아티팩트'이므로 지도는 밝게)
  mapHero: { marginTop: 14, borderWidth: 2, borderColor: paper.ink, padding: 0, overflow: 'hidden' },
  fitBtn: { minHeight: 44, justifyContent: 'center', paddingHorizontal: 12, borderWidth: 1.5, borderColor: paper.line, marginLeft: 8 },
  ctaBar: { position: 'absolute', left: 12, right: 12, bottom: 26 },
});
