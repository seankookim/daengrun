import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Dimensions, Easing, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { HeatTrace } from '../../src/components/runcard';
import { fetchMyRoutePhotos, fetchRoutes } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { RouteInfo, session } from '../../src/store';
import { colors } from '../../src/theme';

// 코스 미리보기 — 보호자·러너 공용 (코스는 공개 콘텐츠).
// 히어로: 스키마틱 트레이스 + 볼트 러너 도트 애니메이션 (실좌표 지도는 v2 — 네이티브 지도 SDK 없이).
// '우리 기록': 이 코스에서 내가 당사자였던 러닝의 실사진만 (타인 사진 공개는 v2 동의 UI와 함께).

const FOREST = '#0F1D13';
const W = Dimensions.get('window').width;
const TRACE_W = W - 60;
const TRACE_H = 190;

// 트레이스를 따라 도는 볼트 도트 — '살아있는 코스' 연출.
// 누적 거리 비율을 inputRange로 쓰는 순수 interpolate (네이티브 드라이버, setState 없음)
function LiveDot({ points }: { points: { x: number; y: number }[] }) {
  const progress = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(progress, { toValue: 1, duration: 7000, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [progress]);

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

export default function CourseScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const df = useDisplayFont();
  const [route, setRoute] = useState<RouteInfo | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [photos, setPhotos] = useState<string[]>([]);

  useEffect(() => {
    if (!id) { setErr('코스 정보가 없어요'); return; }
    fetchRoutes()
      .then((rs) => {
        const r = rs.find((x) => x.id === id);
        if (r) setRoute(r); else setErr('코스를 찾을 수 없어요');
      })
      .catch((e) => setErr(e?.message ?? '불러오기 실패'));
    fetchMyRoutePhotos(id).then(setPhotos).catch(() => {}); // 사진은 실패해도 코스는 뜬다
  }, [id]);

  const isOwner = session.role === 'owner';

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: isOwner ? 120 : 40 }}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 23, fontWeight: '900', color: FOREST }, df]}>코스 미리보기</Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && <View style={s.emptyBox}><Text style={{ fontSize: 14.5, color: colors.dim }}>{err}</Text></View>}

        {route && (
          <View style={{ paddingHorizontal: 12 }}>
            {/* ---------- 히어로: 살아있는 트레이스 ---------- */}
            {route.trace.length > 1 && (
              <View style={s.hero}>
                <View style={{ width: TRACE_W, height: TRACE_H, alignSelf: 'center' }}>
                  <HeatTrace points={route.trace} width={TRACE_W} height={TRACE_H} />
                  {/* 출발·도착 핀 */}
                  <View style={[s.pin, { left: route.trace[0].x * TRACE_W - 5, top: route.trace[0].y * TRACE_H - 5, backgroundColor: colors.volt }]} />
                  <View style={[s.pin, { left: route.trace[route.trace.length - 1].x * TRACE_W - 5, top: route.trace[route.trace.length - 1].y * TRACE_H - 5, backgroundColor: colors.tang }]} />
                  <LiveDot points={route.trace} />
                </View>
                <Row style={{ justifyContent: 'space-between', marginTop: 10 }}>
                  <Text style={{ fontSize: 14, color: '#8fa093' }}>● 출발 <Text style={{ color: '#FF5C3D' }}>● 도착</Text> — 스키마틱 코스도예요</Text>
                  <View style={{ backgroundColor: '#2c4034', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 9 }}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt }}>{route.km}km</Text>
                  </View>
                </Row>
              </View>
            )}

            {/* ---------- 이름 + 핵심 정보 ---------- */}
            {/* [리뷰 F5] 트레이스 없으면 히어로가 말없이 증발했다 — 정직한 준비 중 슬롯 */}
            {route.trace.length <= 1 && (
              <View style={[s.hero, { alignItems: 'center', justifyContent: 'center', minHeight: 120 }]}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: '#75806f' }}>코스 지도 준비 중</Text>
              </View>
            )}
            <Text style={[{ fontSize: 27, color: FOREST, marginTop: 16, fontWeight: '900' }, df]}>{route.name}</Text>
            <Row style={{ gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              <View style={s.infoChip}><Text style={s.infoChipText}>{route.area}</Text></View>
              <View style={s.infoChip}><Text style={s.infoChipText}>{route.terrain}</Text></View>
              <View style={[s.infoChip, { backgroundColor: '#DDF0A6' }]}>
                <Text style={[s.infoChipText, { color: '#3d5a2b' }]}>✓ {route.checkedAt}</Text>
              </View>
            </Row>

            {/* ---------- 설명 ---------- */}
            <Text style={{ fontSize: 15.5, color: '#3d453d', lineHeight: 24, marginTop: 14 }}>{route.desc}</Text>

            {/* ---------- 코스 특징 (발바닥 체크) ---------- */}
            {route.features.length > 0 && (
              <View style={s.section}>
                <Text style={s.sectionTitle}>코스 특징</Text>
                <Row style={{ gap: 7, flexWrap: 'wrap' }}>
                  {route.features.map((f) => (
                    <View key={f.label} style={s.featCard}>
                      <Text style={{ fontSize: 17 }}>{f.g}</Text>
                      <Text style={{ fontSize: 14, fontWeight: '800', color: FOREST, marginTop: 3 }}>{f.label}</Text>
                    </View>
                  ))}
                </Row>
                {route.tags.length > 0 && (
                  <Row style={{ gap: 5, marginTop: 9, flexWrap: 'wrap' }}>
                    {route.tags.map((t) => (
                      <View key={t} style={s.tagChip}><Text style={{ fontSize: 14, fontWeight: '700', color: '#49524a' }}>#{t}</Text></View>
                    ))}
                  </Row>
                )}
              </View>
            )}

            {/* ---------- 우리 기록 — 내가 당사자였던 러닝의 실사진만 ---------- */}
            {photos.length > 0 && (
              <View style={s.section}>
                <Text style={s.sectionTitle}>이 코스에서의 우리 기록</Text>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6 }}>
                  {photos.map((url) => (
                    <Image key={url} source={{ uri: url }} style={{ width: 108, height: 108, borderRadius: 12, backgroundColor: '#DCD6C4' }} />
                  ))}
                </ScrollView>
              </View>
            )}
          </View>
        )}
      </ScrollView>

      {/* ---------- CTA (보호자만) — 코스에서 바로 예약으로 ---------- */}
      {route && isOwner && (
        <View style={s.ctaBar}>
          <Pressable
            onPress={() => router.push({ pathname: '/owner/request', params: { routeId: route.id } })}
            style={s.ctaBtn}
          >
            <Text style={[{ fontSize: 17, fontWeight: '900', color: FOREST }, df]}>이 코스로 예약하기 ›</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  emptyBox: { margin: 16, backgroundColor: '#fff', borderRadius: 16, padding: 20, alignItems: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  hero: { backgroundColor: FOREST, borderRadius: 22, padding: 15, marginTop: 14, overflow: 'hidden' },
  pin: { position: 'absolute', width: 10, height: 10, borderRadius: 5, borderWidth: 1.5, borderColor: '#fff' },
  infoChip: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 11, borderWidth: 1, borderColor: '#DCD6C4' },
  infoChipText: { fontSize: 14.5, fontWeight: '800', color: '#49524a' },
  section: { marginTop: 22 },
  sectionTitle: { fontSize: 16.5, fontWeight: '900', color: FOREST, marginBottom: 10 },
  featCard: { backgroundColor: '#fff', borderRadius: 14, paddingVertical: 10, paddingHorizontal: 13, alignItems: 'center', borderWidth: 1, borderColor: '#DCD6C4', minWidth: 76 },
  tagChip: { backgroundColor: '#EDE8DA', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  ctaBar: { position: 'absolute', left: 10, right: 10, bottom: 26 },
  ctaBtn: {
    backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 16,
    shadowColor: FOREST, shadowOpacity: 0.3, shadowRadius: 10, shadowOffset: { width: 0, height: 5 },
  },
});
