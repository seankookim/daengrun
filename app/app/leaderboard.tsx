import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Avatar, Row, ScreenHead } from '../src/components/ui';
import { boardKmLabel, BoardRow, fetchLeaderboards, fetchMiles, MilesInfo } from '../src/lib/api';
import { colors, layout, paper } from '../src/theme';

// 주간 랭킹 — 주간 리더보드 (강아지 km / 러너 러닝 수) + 내 하이 포인트.
// 서버 집계 함수(0012) 기반 — 개인 데이터는 비공개, 이름·사진·주간 합계만.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const BIB_BAND = ['#F2DA96', '#dfe3e8', '#f3cba8']; // 골드 · 실버 · 브론즈 파스텔 밴드 — 메달 이모지 은퇴, 밴드 색이 순위를 말한다

export default function Leaderboard() {
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState<'dogs' | 'runners'>('dogs');
  const [boards, setBoards] = useState<{ dogs: BoardRow[]; runners: BoardRow[] }>({ dogs: [], runners: [] });
  const [miles, setMiles] = useState<MilesInfo | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // [honesty 2026-08-11] silent board catch + no loading state rendered "지금이
  // 기회!" (fake fresh-week empty) while loading AND on failure. Three states now.
  // fetchMiles stays soft — the hero already renders '—' for missing balance.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const load = () => {
    setLoadErr(false);
    return Promise.all([
      fetchLeaderboards()
        .then((b) => { setBoards(b); setLoaded(true); })
        .catch((e) => { console.warn('[board]:', e?.message ?? e); setLoadErr(true); }),
      fetchMiles().then(setMiles).catch(() => {}),
    ]);
  };
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const rows = boards[tab];

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top, paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* Chrome header (DESIGN.md §3b). The title no longer borrows the display face: a pushed
            sub-screen's header is the shared 23/900 chrome title on every screen. */}
        <ScreenHead title="주간 랭킹" />
        <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 6 }}>
          이번 주 · 월요일마다 새로 시작해요
        </Text>

        {/* 내 하이 포인트 */}
        <View style={s.milesCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 15, color: '#b8c4ae', letterSpacing: 1.5 }}>내 하이 포인트</Text>
              <Text style={{ fontSize: 37, fontWeight: '900', color: colors.volt, marginTop: 4 }}>
                {miles?.balance?.toLocaleString() ?? '—'}<Text style={{ fontSize: 15, color: '#b8c4ae' }}> 포인트</Text>
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end', justifyContent: 'center' }}>
              <Text style={{ fontSize: 15, color: '#b8c4ae', lineHeight: 18.5, textAlign: 'right' }}>
                러닝 완주 +50{'\n'}응가 도장 +30
              </Text>
            </View>
          </Row>
          {/* 부호는 실델타에서 나온다 — shop_spend(음수)가 붙는 날 '+-500'이 되지 않게 */}
          {miles && miles.recent.length > 0 && (
            <Row style={{ gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
              {miles.recent.slice(0, 3).map((m, i) => (
                <Text key={i} style={{ fontSize: 15, color: '#8fa093' }}>
                  {m.reason} {m.delta > 0 ? '+' : ''}{m.delta}
                </Text>
              ))}
            </Row>
          )}
        </View>

        {/* tabs */}
        <View style={s.tabWrap}>
          {([['dogs', '강아지 (거리)'], ['runners', '러너 (러닝 수)']] as const).map(([k, label]) => (
            <Pressable key={k} onPress={() => setTab(k)} style={[s.tab, tab === k && { backgroundColor: paper.ink }]}
              accessibilityRole="tab" accessibilityState={{ selected: tab === k }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: tab === k ? '#fff' : paper.text }}>{label}</Text>
            </Pressable>
          ))}
        </View>

        {/* board — loading / error+retry / honest empty (never a fake fresh week) */}
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>랭킹 불러오는 중…</Text>
          </View>
        )}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>랭킹을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={s.retryTxt}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && rows.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 23 }}>
              이번 주 완주 기록이 아직 없어요{'\n'}첫 러닝이 1위가 되는 주예요 — 지금이 기회!
            </Text>
          </View>
        )}
        {/* ---------- 톱3 포디움 빕 — 시상대 배치 (2·1·3), 1위가 가장 크다 ---------- */}
        {rows.length > 0 && (
          <Row style={{ gap: 8, marginTop: 14, alignItems: 'flex-end' }}>
            {[1, 0, 2].map((rank) => {
              const r = rows[rank];
              if (!r) return <View key={`empty-${rank}`} style={{ flex: 1 }} />;
              const first = rank === 0;
              return (
                <View key={`${r.name}-${rank}`} style={[s.bib, first && s.bibFirst]}>
                  {/* 상단 밴드 + 펀치홀 — 레이스 빕 조형 (미니 빕 스탯과 같은 모티프) */}
                  <View style={[s.bibBand, { backgroundColor: BIB_BAND[rank] }]}>
                    <Text style={{ fontSize: 10, fontWeight: '900', color: paper.ink, letterSpacing: 1.5 }}>NO.{rank + 1}</Text>
                  </View>
                  <Row style={{ justifyContent: 'space-between', paddingHorizontal: 14, marginTop: -5 }}>
                    <View style={s.bibHole} /><View style={s.bibHole} />
                  </Row>
                  <View style={{ alignItems: 'center', paddingTop: 4, paddingBottom: first ? 14 : 11 }}>
                    <Avatar url={r.photoUrl} char={r.name[0]} bg={tab === 'dogs' ? '#c9a86e' : '#5a7a3c'} size={first ? 46 : 38} />
                    {/* 15pt floor: a Korean name never rides below it, so 1st steps UP (16) rather
                        than 2nd/3rd stepping down (the old 14). */}
                    <Text style={{ fontSize: first ? 16 : 15, fontWeight: '900', color: paper.ink, marginTop: 6 }} numberOfLines={1}>
                      {r.name}
                    </Text>
                    {/* [0158] The board summed `coalesce(sum(actual_km), 0)`, so a dog whose only
                        run this week was never measured was published to the neighbourhood as
                        having run 0km. `boardKmLabel` says the three true things instead: a total,
                        a lower bound (「n km 이상」), or 「기록 없음」. A run MEASURED at 0.00 still
                        prints 0km — the honest zero is the thing this must not destroy. */}
                    <Text style={{ fontSize: first ? 19 : 16, fontWeight: '900', color: '#5a7a3c', marginTop: 2 }}>
                      {tab === 'dogs' ? boardKmLabel(r) : `${r.runs}회`}
                    </Text>
                  </View>
                </View>
              );
            })}
          </Row>
        )}
        {rows.length > 3 && <View style={s.listTop} />}
        {rows.slice(3).map((r, i) => (
          <View key={`${r.name}-${i + 3}`} style={s.row}>
            <Text style={{ width: 34, fontSize: 15, fontWeight: '900', color: paper.text, textAlign: 'center' }}>
              {i + 4}
            </Text>
            <Avatar url={r.photoUrl} char={r.name[0]} bg={tab === 'dogs' ? '#c9a86e' : '#5a7a3c'} size={40} />
            <Text style={{ flex: 1, fontSize: 16.5, fontWeight: '800', color: paper.ink, marginLeft: 10 }} numberOfLines={1}>
              {r.name}
            </Text>
            <Text style={{ fontSize: 17, fontWeight: '900', color: '#5a7a3c' }}>
              {tab === 'dogs' ? boardKmLabel(r) : `${r.runs}회`}
            </Text>
          </View>
        ))}

        {/* [0158] The board-level half of the same honesty: a row's own label says whether ITS
            total is partial, and this line says the ranking's own rule — an unmeasured total is
            ordered last (`nulls last`) rather than treated as the smallest number, which is what
            「모르는 거리는 순위에 넣지 않아요」 tells a reader whose dog is sitting at the bottom. */}
        <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 16, lineHeight: 20 }}>
          주간 TOP 3 시즌 보상은 곧 공개돼요{'\n'}랭킹은 완주한 러닝만 집계해요
          {tab === 'dogs' && rows.some((r) => r.km == null || (r.unmeasured ?? 0) > 0)
            ? `\n거리 기록이 없는 러닝은 합계와 순위에 들어가지 않았어요` : ''}
        </Text>
      </ScrollView>
    </View>
  );
}

// Paper grammar (DESIGN.md §2 · §3b): radius 0, neutral #EEE for rows and boxes. The miles card
// stays an INK plate (a dark artifact on a paper screen), so its dim-on-dark greys are correct and
// stay; only its corners squared. The podium bibs keep their art — medal bands, punch holes, gold
// edge on 1st — with square corners like every other card.
const s = StyleSheet.create({
  milesCard: { backgroundColor: paper.ink, padding: 18, marginTop: 16 },
  tabWrap: { flexDirection: 'row', backgroundColor: paper.canvas, padding: 4, marginTop: 16, borderWidth: 1, borderColor: '#EEEEEE' },
  // selected tab = ink fill: ink is STATE (a selected chip), never an action (paper-btn.tsx)
  tab: { flex: 1, alignItems: 'center', paddingVertical: 10 },
  emptyBox: { marginTop: 20, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 18 },
  // loud-fail strip — criticalWash ground, critical ink, underlined retry ≥44pt (house grammar)
  failStrip: { marginTop: 20, backgroundColor: paper.criticalWash, padding: 13 },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // ranks 4+ are a LIST, not a stack of cards: one #EEE hairline above, one under each row
  listTop: { height: 1, backgroundColor: '#EEEEEE', marginTop: 14 },
  row: {
    flexDirection: 'row', alignItems: 'center', paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  // 포디움 빕 — 흰 몸통 + 메달 파스텔 밴드 + 펀치홀
  bib: {
    flex: 1, backgroundColor: paper.canvas, overflow: 'hidden',
    borderWidth: 1, borderColor: '#EEEEEE',
    shadowColor: paper.ink, shadowOpacity: 0.08, shadowRadius: 7, shadowOffset: { width: 0, height: 4 },
  },
  bibFirst: { borderColor: '#e2c56b', borderWidth: 1.5, shadowOpacity: 0.14 },
  bibBand: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 10, paddingVertical: 6 },
  // the punch hole is a circle by nature (circles are the one radius exception, DESIGN.md §4)
  bibHole: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#EEEEEE' },
});
