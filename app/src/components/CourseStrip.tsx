import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { fetchMyDistrict, fetchRoutes } from '../lib/api';
import { RouteInfo } from '../store';
import { colors } from '../theme';
import { HeatTrace } from './runcard';

// 동네 코스 스트립 — 보호자 홈(동네 러너 아래)과 러너 홈이 공유하는 코스 발견 진입점.
// 로컬 우선: profiles.district와 area가 일치하는 코스를 앞으로 (지오 거리 정렬은 실좌표 v2).
// 탭 → /course/[id] 미리보기 (트레이스·설명·점검일·우리 기록).

const FOREST = '#0F1D13';

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
        <Text style={{ fontSize: 12, color: '#49524a' }}>· 점검된 안심 코스</Text>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 11, paddingRight: 12 }}>
        {routes.map((r) => (
          <Pressable
            key={r.id}
            onPress={() => router.push(`/course/${r.id}`)}
            style={{
              width: 208, backgroundColor: '#fff', borderRadius: 18, padding: 12,
              borderWidth: 1, borderColor: '#DCD6C4',
              shadowColor: FOREST, shadowOpacity: 0.06, shadowRadius: 8, shadowOffset: { width: 0, height: 4 },
            }}
          >
            <View style={{ backgroundColor: FOREST, borderRadius: 12, overflow: 'hidden', paddingVertical: 6, paddingHorizontal: 4 }}>
              <HeatTrace points={r.trace} width={176} height={72} />
            </View>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST, marginTop: 9 }} numberOfLines={1}>{r.name}</Text>
            <Text style={{ fontSize: 12, color: '#49524a', marginTop: 3 }} numberOfLines={1}>
              {r.area} · {r.km}km · {r.terrain}
            </Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 7 }}>
              <View style={{ backgroundColor: '#DDF0A6', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7 }}>
                <Text style={{ fontSize: 10, fontWeight: '900', color: '#3d5a2b' }}>✓ {r.checkedAt}</Text>
              </View>
              <View style={{ flex: 1 }} />
              <Text style={{ fontSize: 12, fontWeight: '800', color: colors.voltDeep }}>미리보기 ›</Text>
            </View>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}
