import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { fetchMyDistrict, fetchRoutes } from '../lib/api';
import { RouteInfo } from '../store';
import { colors } from '../theme';
import { HeatTrace } from './runcard';

// 동네 코스 스트립 — 트레일 패치(스티커) 덱. 보호자 홈(동네 러너 아래)·러너 홈 공유.
// 파스텔 로테이션 + 살짝 기운 스티커 + km 빕 + 점검 도장: 코스를 '수집하고 싶은 배지'처럼.
// 로컬 우선: profiles.district = area 일치 코스 앞으로 (지오 거리 정렬은 실좌표 v2).

const FOREST = '#0F1D13';
const PALETTE = ['#DDF0A6', '#C3D9AE', '#FFCDB6', '#F2DA96']; // matching 카드와 같은 파스텔 계열

export function CourseStrip({ title = '동네 코스' }: { title?: string }) {
  const [routes, setRoutes] = useState<RouteInfo[]>([]);

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
    <View style={{ marginTop: 14 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 9 }}>
        <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{title}</Text>
        <Text style={{ fontSize: 14, color: '#49524a' }}>· 점검된 안심 코스</Text>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingRight: 12, paddingVertical: 6 }}>
        {routes.map((r, i) => (
          <Pressable
            key={r.id}
            onPress={() => router.push(`/course/${r.id}`)}
            style={{
              width: 212, backgroundColor: PALETTE[i % 4], borderRadius: 20, padding: 12, paddingBottom: 11,
              borderWidth: 1, borderColor: 'rgba(15,29,19,0.14)',
              // 스티커 필: 카드마다 반대로 살짝 기움 (수집 배지 느낌)
              transform: [{ rotate: i % 2 === 0 ? '-1.1deg' : '1.1deg' }],
              shadowColor: FOREST, shadowOpacity: 0.1, shadowRadius: 7, shadowOffset: { width: 0, height: 4 },
            }}
          >
            {/* 맵 창 + 겹치는 km 빕 */}
            <View style={{ backgroundColor: FOREST, borderRadius: 14, overflow: 'hidden', paddingVertical: 6, paddingHorizontal: 4 }}>
              <HeatTrace points={r.trace} width={180} height={74} />
            </View>
            <View style={{
              position: 'absolute', top: 4, right: 4, width: 42, height: 42, borderRadius: 21,
              backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center',
              borderWidth: 2.5, borderColor: '#fff', transform: [{ rotate: '8deg' }],
              shadowColor: FOREST, shadowOpacity: 0.25, shadowRadius: 4, shadowOffset: { width: 0, height: 2 },
            }}>
              <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{r.km}K</Text>
            </View>

            {/* 특징 글리프 버블 — 맵 창 하단에 반쯤 걸침 */}
            {r.features.length > 0 && (
              <View style={{ flexDirection: 'row', gap: 4, marginTop: -13, marginLeft: 6 }}>
                {r.features.slice(0, 4).map((f) => (
                  <View key={f.label} style={{
                    width: 26, height: 26, borderRadius: 13, backgroundColor: '#fff',
                    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: 'rgba(15,29,19,0.12)',
                  }}>
                    <Text style={{ fontSize: 12.5, color: FOREST }}>{f.g}</Text>
                  </View>
                ))}
              </View>
            )}

            <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST, marginTop: 7 }} numberOfLines={1}>{r.name}</Text>
            <Text style={{ fontSize: 12, color: '#3d453d', marginTop: 2 }} numberOfLines={1}>
              {r.area} · {r.terrain}
            </Text>

            <View style={{ flexDirection: 'row', alignItems: 'flex-end', marginTop: 8 }}>
              {/* 점검 도장 — 여권 스탬프처럼 비스듬히 */}
              <View style={{
                borderWidth: 1.5, borderColor: '#3d6a2b', borderRadius: 7, paddingVertical: 2, paddingHorizontal: 7,
                transform: [{ rotate: '-5deg' }], backgroundColor: 'rgba(255,255,255,0.55)',
              }}>
                <Text style={{ fontSize: 10, fontWeight: '900', color: '#3d6a2b', letterSpacing: 0.4 }}>✓ {r.checkedAt}</Text>
              </View>
              <View style={{ flex: 1 }} />
              <View style={{ backgroundColor: FOREST, borderRadius: 99, paddingVertical: 5, paddingHorizontal: 11 }}>
                <Text style={{ fontSize: 11.5, fontWeight: '900', color: colors.volt }}>미리보기 ›</Text>
              </View>
            </View>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}
