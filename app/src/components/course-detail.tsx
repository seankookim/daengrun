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

      {/* 메타 3축 — 노면·그늘·조명. 칩이 거르는 축과 **같은 세 축**이라 필터와 상세가 같은 말을 한다 */}
      <Text style={s.sect}>노면 · 그늘 · 조명</Text>
      <View style={s.metaBand}>
        {([
          ['SURFACE', route.terrain || '—', false],
          ['SHADE', (route.shade && SHADE_BAR[route.shade]) || '—', false],
          ['LIGHT', (route.lighting && LIGHT_TXT[route.lighting]) || '—', route.lighting === 'none'],
        ] as [string, string, boolean][]).map(([k, v, warn], i) => (
          <View key={k} style={[s.metaCell, i < 2 && s.metaDiv]}>
            <Text style={s.metaK}>{k}</Text>
            <Text style={[s.metaV, warn && { color: paper.critical }]}>{v}</Text>
          </View>
        ))}
      </View>

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
