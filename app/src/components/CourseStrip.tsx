import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { fetchMyDistrict, fetchRoutes, townOf } from '../lib/api';
import { RouteInfo } from '../store';
import { paper } from '../theme';
import { useNumFont } from '../lib/fonts';
import { worldOf } from './patch';
import { HeatTrace } from './runcard';
import { traceToBox } from '../lib/trace';

// 동네 코스 스트립 — 트레일 패치(스티커) 덱. 보호자 홈(러너 셸프 아래)·러너 홈 공유.
// 파스텔 로테이션 + 살짝 기운 스티커 + km 빕 + 점검 도장: 코스를 '수집하고 싶은 배지'처럼.
// 동네 범위: profiles.district 로 **질의를 좁힌다** (fetchRoutes 가 town 정규화·폴백까지 처리).
// 정렬만 하던 시절의 설명이 아니다 — 2026-08-26 이전에는 서울 전체를 받아 정렬만 했다.

// [V4] 파스텔 은퇴 — 코스는 거리 월드 컬러(P2 배지 월드와 동일 소스)로: 코스 = 경험
// [§3b] 구 FOREST 헤더 잉크(#0F1D13)는 헤더가 paper.ink로 통일되며 은퇴

// headerPad: 풀블리드 컨테이너(오너 홈)에서 헤더 텍스트만 안쪽 거터를 받는다 — 러너 홈(컨테이너 패딩 유지)은 0
// bleed: 패딩 있는 컨테이너(러너 홈)에서 §3b 코랄 룰을 음수 마진으로 화면 끝까지 뚫는 양 — 풀블리드 컨테이너는 0
export function CourseStrip({ title = '동네 코스', headerPad = 0, bleed = 0 }: { title?: string; headerPad?: number; bleed?: number }) {
  // [honesty 2026-08-20] `fetchRoutes().catch(() => [])` fed an early-return on `length === 0`,
  // so a failed load, a load still in flight, and "there are genuinely no offerable courses"
  // were ONE state: the whole 동네 코스 module disappeared from both homes without a word, and
  // nothing on either screen could ever bring it back (no retry exists for a module that is not
  // rendered). null = loading · failed = the fetch threw · [] = the server really returned none.
  const [routes, setRoutes] = useState<RouteInfo[] | null>(null);
  const [failed, setFailed] = useState(false);
  // [honesty 2026-08-26 · Sean] null until a load settles: whether the deck we are showing is
  // actually this owner's neighbourhood. The header is a CLAIM and it needs a fact behind it.
  const [local, setLocal] = useState(false);
  const nf = useNumFont();
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);

  // 🔴 [honesty 2026-08-26 · Sean, on a screenshot] This module is headed 동네 코스 and it was
  //    showing the whole city. `fetchRoutes()` was called with NO argument, so the deck was the
  //    six SHORTEST courses in Seoul, and district was used only to sort them — meaning a 성수
  //    owner read 「동네 코스」 over 송파동 and 잠실동 cards that print their own foreign town
  //    right on them. Same defect Sean already found once in the booking flow; it survived here
  //    because this file fetches its own routes.
  //
  //    ⚠ The sort was ALSO narrower than it looked, and not a no-op as it first appears:
  //      `b.area === district` matches exactly when district is '반포동' (7 routes carry that
  //      area) and never for '성수', because towns are uniformly suffixed. So of the five
  //      district values in production, ONE worked. A rule that works for the pilot district and
  //      silently does nothing for everyone else is the worst kind to leave in — it tests fine.
  //
  //    The fix is to pass the district, because `fetchRoutes` ALREADY does all of this properly
  //    and no caller here ever asked it to: exact town, then the 성수→성수동 normalisation
  //    (`townOf`), then a LOUD unfiltered fallback for the vocabularies that genuinely do not map
  //    (뚝섬·서울숲). The behaviour was written for this exact problem in 2026-08-20 and this
  //    strip simply never used it. District must be fetched FIRST now rather than in parallel —
  //    one extra serial round-trip on a tiny query, which is the correct price.
  const load = useCallback(() => {
    setFailed(false);
    fetchMyDistrict()
      // district failing is not the deck failing: fall back to the unscoped catalogue, and say
      // so in the header rather than calling someone else's neighbourhood theirs.
      .catch(() => null)
      .then((district) => fetchRoutes(district).then((rs) => ({ rs, district })))
      .then(({ rs, district }) => {
        if (!alive.current) return;
        // ⚠ The same question the query asked, asked of the ANSWER — `fetchRoutes` can fall back
        //   to the whole city without telling its caller, so a scoped REQUEST is not evidence of
        //   a scoped RESULT. `townOf` is imported rather than re-spelled here so the two sides
        //   cannot drift (both district spellings are accepted: '반포동' matches area directly).
        const t = townOf(district);
        const isLocal = (r: RouteInfo) => !!t && (r.area === t || r.area === district);
        const sorted = district ? [...rs].sort((a, b) => Number(isLocal(b)) - Number(isLocal(a))) : rs;
        setLocal(sorted.some(isLocal));
        setRoutes(sorted.slice(0, 6));
      }).catch((e) => {
        if (!alive.current) return;
        console.warn('[courses] load:', (e as Error)?.message ?? e);
        setFailed(true);
      });
  }, []);
  useEffect(() => { load(); }, [load]);

  // The failure row keeps the module's own header, so what failed is readable from the slot
  // it failed in. Loud-fail grammar copied from the neighbouring module on the same home
  // (clubcard.tsx s.cFail): canvas面 + critical hairlines + 14/700 ink + underlined 다시 시도.
  // The header names what is actually in the deck. 동네 코스 only when at least one card really
  // is in this owner's town; otherwise 추천 코스 — still a true sentence about the same list,
  // and the cards keep printing their own area so nothing is hidden, just no longer misnamed.
  // (The failure row below reuses this too, where the fallback title is the honest one: a load
  // that never landed cannot have established locality.)
  const heading = local ? title : '추천 코스';
  const header = (
    <View style={{ marginHorizontal: -bleed, paddingHorizontal: bleed + headerPad, marginBottom: 8 }}>
      <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink }}>{heading}</Text>
    </View>
  );

  if (failed) {
    return (
      <View style={{ marginTop: 18 }}>
        {header}
        <View style={{
          marginHorizontal: -bleed, paddingHorizontal: bleed + headerPad, paddingVertical: 11,
          flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
          backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
        }}>
          <Text style={{ flex: 1, fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical }}>
            코스를 불러오지 못했어요
          </Text>
          <Pressable onPress={load} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
            <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>
              다시 시도
            </Text>
          </Pressable>
        </View>
      </View>
    );
  }
  // Loading and a truly empty deck both stay silent: neither has a picture to draw, and
  // neither is a claim. Only the failure speaks.
  if (routes == null || routes.length === 0) return null;

  return (
    <View style={{ marginTop: 18 }}>
      {/* [2026-08-19 랩 ⑧] 모듈 헤더 = modh 문법 — 15/800 잉크 타이틀 한 줄. 구 문법의 풀블리드
          코랄 룰 + 20/800 타이틀은 Sean이 첫날 clutter라 부른 그 선이라 은퇴했다 (홈의 덩어리
          경계는 이제 여백 + 킥커 하나가 만든다). 'VERIFIED COURSES' 라틴 키커는 §3b에서 이미 은퇴. */}
      {header}
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
