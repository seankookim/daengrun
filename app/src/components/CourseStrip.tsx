import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { fetchMyDistrict, fetchRoutes } from '../lib/api';
import { RouteInfo } from '../store';
import { paper } from '../theme';
import { useNumFont } from '../lib/fonts';
import { worldOf } from './patch';
import { HeatTrace } from './runcard';
import { traceToBox } from '../lib/trace';

// 동네 코스 스트립 — 트레일 패치(스티커) 덱. 보호자 홈(동네 러너 아래)·러너 홈 공유.
// 파스텔 로테이션 + 살짝 기운 스티커 + km 빕 + 점검 도장: 코스를 '수집하고 싶은 배지'처럼.
// 로컬 우선: profiles.district = area 일치 코스 앞으로 (지오 거리 정렬은 실좌표 v2).

// [V4] 파스텔 은퇴 — 코스는 거리 월드 컬러(P2 배지 월드와 동일 소스)로: 코스 = 경험
// [§3b] 구 FOREST 헤더 잉크(#0F1D13)는 헤더가 paper.ink로 통일되며 은퇴

// headerPad: 풀블리드 컨테이너(오너 홈)에서 헤더 텍스트만 안쪽 거터를 받는다 — 러너 홈(컨테이너 패딩 유지)은 0
// bleed: 패딩 있는 컨테이너(러너 홈)에서 §3b 코랄 룰을 음수 마진으로 화면 끝까지 뚫는 양 — 풀블리드 컨테이너는 0
export function CourseStrip({ title = '동네 코스', headerPad = 0, bleed = 0 }: { title?: string; headerPad?: number; bleed?: number }) {
  const [routes, setRoutes] = useState<RouteInfo[]>([]);
  const nf = useNumFont();

  useEffect(() => {
    let alive = true;
    Promise.all([
      fetchRoutes().catch(() => [] as RouteInfo[]),
      fetchMyDistrict().catch(() => null),
    ]).then(([rs, district]) => {
      if (!alive) return;
      const sorted = district ? [...rs].sort((a, b) => Number(b.area === district) - Number(a.area === district)) : rs;
      setRoutes(sorted.slice(0, 6));
    });
    return () => { alive = false; };
  }, []);

  if (routes.length === 0) return null; // 없는 데이터는 그리지 않는다

  return (
    <View style={{ marginTop: 18 }}>
      {/* [§3b 2026-08-11] 단일 섹션 헤더 그램마 — 풀블리드 코랄 룰 위 + 타이틀 20/800 잉크.
          'VERIFIED COURSES' 라틴 키커는 DESIGN.md §3b가 이름 불러 은퇴시킨 바로 그 사례. FOREST 2.5px
          언더라인도 헤더 크롬에서 은퇴 (코스 카드 안 월드 컬러는 시맨틱으로 생존). */}
      <View style={{ marginHorizontal: -bleed, paddingHorizontal: bleed + headerPad, borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10, marginBottom: 9 }}>
        <Text style={{ fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink }}>{title}</Text>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10, paddingLeft: headerPad, paddingRight: 12 }}>
        {routes.map((r) => {
          const w = worldOf(r.km); // [V4] 거리 = 색 세계 (TRAIL 테라 · FOREST 볼트 · RIVER 스카이 · NIGHT 바이올렛)
          return (
          <Pressable
            key={r.id}
            onPress={() => router.push(`/course/${r.id}`)}
            style={{ width: 224, backgroundColor: w.bg, padding: 13, overflow: 'hidden' }}
          >
            {/* 월드 킥커 + km 대활자 */}
            <View style={{ flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 8.5, fontWeight: '700', letterSpacing: 2.5, color: w.dim }}>{w.label} · {r.terrain.toUpperCase?.() ?? r.terrain}</Text>
              <Text style={[{ fontSize: 24, lineHeight: 30, fontWeight: '900', color: w.tone }, nf]}>{r.km}<Text style={{ fontSize: 14 }}>K</Text></Text>
            </View>

            {/* 트레이스 — 월드 톤으로 발광. [리뷰 F2] 빈 트레이스는 지도인 척하는 그리드+블롭을 그리지
                않는다 — 정직한 준비 중 슬롯 (실 trace가 오면 그때 발광) */}
            <View style={{ marginTop: 6, marginHorizontal: -3 }}>
              {r.trace.length > 1 ? (
                <HeatTrace points={traceToBox(r.trace)} width={204} height={72} tint={w.tone} />
              ) : (
                <View style={{ width: 204, height: 72, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: w.tone }}>
                  <Text style={{ fontSize: 14, fontWeight: '700', color: w.dim }}>코스 지도 준비 중</Text>
                </View>
              )}
            </View>

            <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff', marginTop: 8 }} numberOfLines={1}>{r.name}</Text>
            <Text style={{ fontSize: 14, color: w.dim, marginTop: 2 }} numberOfLines={1}>
              {r.area}{r.features.length > 0 ? ` · ${r.features.slice(0, 3).map((f) => f.g).join(' ')}` : ''}
            </Text>

            <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 10 }}>
              {/* 점검 도장 — 여권 스탬프 (원형 규칙 ④ 생존) */}
              <View style={{
                borderWidth: 1.5, borderColor: w.tone, borderRadius: 6, paddingVertical: 2, paddingHorizontal: 7,
                transform: [{ rotate: '-5deg' }], opacity: 0.9,
              }}>
                <Text style={{ fontSize: 9.5, fontWeight: '900', color: w.tone, letterSpacing: 0.4 }}>✓ {r.checkedAt}</Text>
              </View>
              <View style={{ flex: 1 }} />
              <View style={{ borderWidth: 1.2, borderColor: w.tone, paddingVertical: 5, paddingHorizontal: 11 }}>
                <Text style={{ fontSize: 14, fontWeight: '900', color: w.tone }}>미리보기 ›</Text>
              </View>
            </View>
          </Pressable>
        ); })}
      </ScrollView>
    </View>
  );
}
