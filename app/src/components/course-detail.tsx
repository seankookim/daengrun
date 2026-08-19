// 코스 상세 본문 — 시트 DETAIL 단과 `course/[id]`의 **유일한 주인** (K6/T1 빌드 스펙).
//
// ═══ 왜 컴포넌트인가 ═══
// 두 화면이 같은 사실(노면·그늘·조명·설명·특징·점검·우리 기록)을 각자 그리고 있었고, 이미
// 서로 다른 것을 그리고 있었다: 시트는 메타 3축 밴드를 그렸지만 특징·태그·사진이 없었고,
// `course/[id]`는 특징·태그·사진을 그렸지만 그늘/조명을 아예 말하지 않았다 — 어두운 시간대
// 안전 축을 칩으로 필터링해 놓고 상세 화면에서는 그 값을 볼 수 없었다는 뜻이다.
// 본문이 하나가 되면 그 구멍이 구조적으로 닫힌다.
//
// 화면이 소유하는 것(여기 없는 것): 히어로(한쪽은 실지도, 한쪽은 스키마틱)와 CTA.
// 둘 다 문맥이 다르고, 화면당 primary 하나 법은 호출자가 지킨다.
import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { fetchMyRoutePhotos } from '../lib/api';
import { MediaImage } from '../lib/media';
import { RouteInfo } from '../store';
import { paper } from '../theme';

const SHADE_BAR: Record<string, string> = { high: '▮▮▮', mid: '▮▮▯', low: '▮▯▯' };
/** 누적 오르막이 이 값 이상이면 '언덕 많음'. Sean 2026-08-19 판정(질문 7 = A, "~40 m"). */
const HILL_MIN_M = 40;
const LIGHT_TXT: Record<string, string> = { lit: '조명', partial: '부분', none: '없음' };

/**
 * 이 코스의 선이 **무엇을 주장할 수 있는지**. 화면마다 다시 유도하지 않도록 여기 한 곳에 둔다.
 *
 * 예전엔 모든 화면이 `trace.length > 1`을 '실측'과 같다고 봤다. 트레이스가 전부 비어 있던
 * 동안에는 그 등식이 우연히 참이었지만, 시드 지오메트리(`source='algo'`)가 들어오는 순간
 * **거짓말이 된다** — 아무도 달려보지 않은 선을 실측 지도로 그리게 되기 때문이다.
 * 실측의 유일한 근거는 승격(status==='active')이다. 0082가 이 어휘를 미리 깔아 뒀다.
 */
export type TraceKind = 'verified' | 'planned' | 'none';
export function traceKind(r: { status: RouteInfo['status']; source: RouteInfo['source']; trace: unknown[] }): TraceKind {
  if (r.trace.length < 2) return 'none';
  return r.status === 'active' ? 'verified' : 'planned';
}
/** 지도 위/옆에서 선이 무엇인지 한 줄로. verified면 아무 말도 하지 않는다 — 기본값이므로. */
export const TRACE_NOTE: Record<TraceKind, string | null> = {
  verified: null,
  planned: '지도의 선은 예정 경로예요 — 첫 반려견 동반 러닝이 실측 지도를 만들어요',
  none: null,
};

/** 라이프사이클 줄 — 색만으로 말하지 않는다(a11y 계약): 항상 문장이 함께 간다. */
export function CourseLifecycleLine({ route }: { route: RouteInfo }) {
  if (route.status === 'suspended') {
    return (
      <View style={[s.strip, { borderColor: paper.critical, backgroundColor: paper.criticalWash }]}>
        <Text style={[s.stripTxt, { color: paper.critical }]}>이 코스는 점검을 위해 일시 중단됐어요</Text>
      </View>
    );
  }
  if (route.status === 'retired') {
    return (
      <View style={s.strip}>
        <Text style={s.stripTxt}>더 이상 운영하지 않는 코스예요 — 기록으로만 남아 있어요</Text>
      </View>
    );
  }
  if (route.status === 'candidate') {
    return (
      <View style={[s.strip, { borderColor: paper.pending }]}>
        <Text style={[s.stripTxt, { color: paper.pending }]}>파운더 점검 전 코스예요 — 점검 후 실지도가 붙어요</Text>
      </View>
    );
  }
  return null;
}

export function CourseDetailBody({ route, style }: { route: RouteInfo; style?: ViewStyle }) {
  // '우리 기록'은 이 컴포넌트가 소유한다 — 실패해도 코스는 뜬다(사일런트 부분 실패는
  // 여기서만 허용된다: 내 사진이 없는 것과 못 불러온 것은 화면의 주장이 아니다).
  const [photos, setPhotos] = useState<string[]>([]);
  useEffect(() => {
    let alive = true;
    setPhotos([]);
    fetchMyRoutePhotos(route.id).then((p) => { if (alive) setPhotos(p); }).catch(() => {});
    return () => { alive = false; };
  }, [route.id]);

  return (
    <View style={style}>
      <CourseLifecycleLine route={route} />

      {/* 메타 축 — 노면·그늘·조명은 칩이 거르는 축과 **같은 세 축**이라 필터와 상세가 같은 말을 한다.
          오르막(0098)은 네 번째이고 **여기에만** 산다: 목록·캐러셀·칩은 이 값을 쓰지 않는다.
          ⚠ CLIMB 은 이 띠에서 유일하게 '—'가 두 가지를 뜻하지 않는 칸이다. 나머지 셀의 '—'는
          '기록 없음'이고, 여기서는 '이 지오메트리에 대해 재지 않았다'이다 — 그리고 **0m 은 실제
          측정값이라 '—'로 접으면 안 된다**(프로덕션에 0m 코스가 있다). */}
      <Text style={s.sect}>노면 · 그늘 · 조명 · 오르막</Text>
      <View style={s.metaBand}>
        {([
          ['SURFACE', route.terrain || '—', false],
          ['SHADE', (route.shade && SHADE_BAR[route.shade]) || '—', false],
          ['LIGHT', (route.lighting && LIGHT_TXT[route.lighting]) || '—', route.lighting === 'none'],
          ['CLIMB', route.elevationGainM != null ? `${Math.round(route.elevationGainM)}m` : '—', false],
        ] as [string, string, boolean][]).map(([k, v, warn], i, arr) => (
          <View key={k} style={[s.metaCell, i < arr.length - 1 && s.metaDiv]}>
            <Text style={s.metaK}>{k}</Text>
            <Text style={[s.metaV, warn && { color: paper.critical }]}>{v}</Text>
          </View>
        ))}
      </View>
      {/* 언덕 표기 (Sean 2026-08-19, 질문 7 = A: "hill notes: yes, ~40 m").
          ⚠ 문턱은 **절대 상승**이다 — 그게 Sean이 답한 질문이다. 다만 0098 데이터가 들어온 뒤
          측정된 사실 하나를 함께 남긴다: 이 규칙은 카탈로그에서 가장 가파른 코스를 놓친다.
          몽마르뜨 언덕 루프(1.6km)는 34m라 문턱 아래인데 km당 21.3m로 2위의 두 배 이상이고,
          도곡 매봉산(63m)은 문턱을 넘지만 7.66km에 걸쳐 km당 8.2m로 완만하다. 경사로 바꾸려면
          아래 한 줄(HILL_MIN_M → km당 임계)만 바꾸면 된다. 바꾸는 건 Sean의 판정이지 우리 것이 아니다.
          NULL에는 절대 붙지 않는다: 재지 않은 것은 평지도 언덕도 아니다. */}
      {route.elevationGainM != null && route.elevationGainM >= HILL_MIN_M && (
        <Text style={s.hill}>언덕 많음</Text>
      )}

      {route.desc ? (
        <>
          <Text style={s.sect}>코스</Text>
          <Text style={s.body}>{route.desc}</Text>
        </>
      ) : null}

      {route.features.length > 0 && (
        <>
          <Text style={s.sect}>코스 특징</Text>
          <View style={s.wrapRow}>
            {route.features.map((f) => (
              <View key={f.label} style={s.feat}>
                <Text style={{ fontSize: 17 }}>{f.g}</Text>
                <Text style={s.featTxt}>{f.label}</Text>
              </View>
            ))}
          </View>
          {route.tags.length > 0 && (
            <View style={[s.wrapRow, { marginTop: 8 }]}>
              {route.tags.map((t) => (
                <View key={t} style={s.tag}><Text style={s.tagTxt}>#{t}</Text></View>
              ))}
            </View>
          )}
        </>
      )}

      <Text style={s.sect}>점검</Text>
      <Text style={s.body}>
        {route.status === 'candidate'
          ? '아직 반려견과 함께 달려본 적이 없는 코스예요. 첫 러닝이 이 코스의 점검이 됩니다.'
          : route.checkedAt}
      </Text>

      {/* 우리 기록 — 내가 당사자였던 러닝의 실사진만. 타인 사진은 RLS가 막는다 */}
      {photos.length > 0 && (
        <>
          <Text style={s.sect}>이 코스에서의 우리 기록</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6 }}>
            {photos.map((url) => (
              <MediaImage key={url} source={url} style={s.photo} />
            ))}
          </ScrollView>
        </>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  strip: {
    borderWidth: 1.5, borderColor: paper.line, paddingVertical: 9, paddingHorizontal: 11, marginBottom: 4,
  },
  stripTxt: { fontSize: 14, fontWeight: '800', color: paper.text, lineHeight: 20 },

  sect: { fontSize: 14, fontWeight: '800', color: paper.dim, marginTop: 16, marginBottom: 7 },
  body: { fontSize: 14.5, color: paper.text, lineHeight: 22 },

  metaBand: { flexDirection: 'row', borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#F0EEE9' },
  metaCell: { flex: 1, paddingVertical: 9, alignItems: 'center' },
  metaDiv: { borderRightWidth: 1, borderRightColor: '#F0EEE9' },
  metaK: { fontSize: 14, color: paper.faint, fontWeight: '700' },
  metaV: { fontSize: 14.5, fontWeight: '800', color: paper.ink, marginTop: 3 },
  // 앰버 = 대기/주의의 기존 시맨틱 토큰(candidate 포스처와 같은 색). 새 색을 만들지 않는다.
  hill: { fontSize: 14, fontWeight: '800', color: paper.pending, marginTop: 8 },

  wrapRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 7 },
  feat: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EDEBE6',
    paddingVertical: 9, paddingHorizontal: 12, alignItems: 'center', minWidth: 76,
  },
  featTxt: { fontSize: 14, fontWeight: '800', color: paper.ink, marginTop: 3 },
  tag: { backgroundColor: paper.wash, paddingVertical: 5, paddingHorizontal: 10 },
  tagTxt: { fontSize: 14, fontWeight: '700', color: paper.actionInk },

  photo: { width: 108, height: 108, backgroundColor: '#F0EEE9' },
});
