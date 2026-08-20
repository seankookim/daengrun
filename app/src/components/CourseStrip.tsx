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
      {/* [2026-08-19 랩 ⑧] 모듈 헤더 = modh 문법 — 15/800 잉크 타이틀 한 줄. 구 문법의 풀블리드
          코랄 룰 + 20/800 타이틀은 Sean이 첫날 clutter라 부른 그 선이라 은퇴했다 (홈의 덩어리
          경계는 이제 여백 + 킥커 하나가 만든다). 'VERIFIED COURSES' 라틴 키커는 §3b에서 이미 은퇴. */}
      <View style={{ marginHorizontal: -bleed, paddingHorizontal: bleed + headerPad, marginBottom: 8 }}>
        <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink }}>{title}</Text>
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
            {/* [14pt 플로어 2026-08-19] 이 줄은 'TRAIL · 포장 100%'를 통째로 8.5pt에 뒀다.
                레터스페이스 대문자 라틴 킥커만 플로어 면제인데, terrain은 실데이터이고 한글이
                섞인다 (routes.terrain — '포장 100%'). 킥커와 데이터를 갈라 각자의 법을 지운다:
                월드 라벨은 킥커 그대로, terrain은 14pt 데이터 줄로. '·'는 크기 차가 대신한다. */}
            <View style={{ flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 8 }}>
              <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 6, flexShrink: 1 }}>
                <Text style={{ fontSize: 8.5, fontWeight: '700', letterSpacing: 2.5, color: w.dim }}>{w.label}</Text>
                {r.terrain ? (
                  <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: w.dim, flexShrink: 1 }} numberOfLines={1}>
                    {r.terrain.toUpperCase?.() ?? r.terrain}
                  </Text>
                ) : null}
              </View>
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
                {/* checkedAt은 날짜이거나 '점검 예정'(한글)이다 — 도장 안이라고 면제되지 않는다.
                    9.5 → 14. 224pt 카드에서 도장 + '미리보기 ›'가 나란히 들어가는 폭은 남는다. */}
                {/* ⚠ The ✓ is gated on a real inspection. `checkedAt` is the string '점검 예정'
                    for candidates and for any route whose `checked_at` is null, so an
                    unconditional mark rendered 「✓ 점검 예정」 — a tick on an inspection that has
                    not happened. request.tsx gates the same mark on `status === 'active'` and
                    says why ("checkedAt이 null인데 ✓를 그리던 자리 = 하지 않은 점검의 주장").
                    Same gate here; the stamp still renders, it just stops claiming. */}
                <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: w.tone, letterSpacing: 0.4 }}>
                  {r.status === 'active' ? `✓ ${r.checkedAt}` : r.checkedAt}
                </Text>
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
