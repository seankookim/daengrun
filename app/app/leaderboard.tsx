import { useDisplayFont } from '../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../src/components/ui';
import { BoardRow, fetchLeaderboards, fetchMiles, MilesInfo } from '../src/lib/api';
import { colors } from '../src/theme';

// 동네 랭킹 — 주간 리더보드 (강아지 km / 러너 러닝 수) + 내 하이 포인트.
// 서버 집계 함수(0012) 기반 — 개인 데이터는 비공개, 이름·사진·주간 합계만.

const FOREST = '#0F1D13';
const MEDAL = ['🥇', '🥈', '🥉'];

export default function Leaderboard() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [tab, setTab] = useState<'dogs' | 'runners'>('dogs');
  const [boards, setBoards] = useState<{ dogs: BoardRow[]; runners: BoardRow[] }>({ dogs: [], runners: [] });
  const [miles, setMiles] = useState<MilesInfo | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = () => Promise.all([
    fetchLeaderboards().then(setBoards).catch((e) => console.warn('[board]:', e?.message ?? e)),
    fetchMiles().then(setMiles).catch(() => {}),
  ]);
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const rows = boards[tab];

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 23, fontWeight: '900', color: FOREST }, df]}>동네 랭킹</Text>
          <View style={{ width: 40 }} />
        </Row>
        <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', marginTop: 6 }}>
          이번 주 · 월요일마다 새로 시작해요
        </Text>

        {/* 내 하이 포인트 */}
        <View style={s.milesCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 12.5, color: '#b8c4ae', letterSpacing: 1.5 }}>내 하이 포인트</Text>
              <Text style={{ fontSize: 37, fontWeight: '900', color: colors.volt, marginTop: 4 }}>
                {miles?.balance?.toLocaleString() ?? '—'}<Text style={{ fontSize: 15, color: '#b8c4ae' }}> 마일</Text>
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end', justifyContent: 'center' }}>
              <Text style={{ fontSize: 12, color: '#b8c4ae', lineHeight: 18.5, textAlign: 'right' }}>
                러닝 완주 +50{'\n'}응가 도장 +30
              </Text>
            </View>
          </Row>
          {miles && miles.recent.length > 0 && (
            <Row style={{ gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
              {miles.recent.slice(0, 3).map((m, i) => (
                <Text key={i} style={{ fontSize: 12, color: '#8fa093' }}>
                  {m.reason} +{m.delta}
                </Text>
              ))}
            </Row>
          )}
        </View>

        {/* tabs */}
        <View style={s.tabWrap}>
          {([['dogs', '🐕 강아지 (거리)'], ['runners', '🏃 러너 (러닝 수)']] as const).map(([k, label]) => (
            <Pressable key={k} onPress={() => setTab(k)} style={[s.tab, tab === k && { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: tab === k ? '#fff' : '#49524a' }}>{label}</Text>
            </Pressable>
          ))}
        </View>

        {/* board */}
        {rows.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 23 }}>
              이번 주 완주 기록이 아직 없어요{'\n'}첫 러닝이 1위가 되는 주예요 — 지금이 기회!
            </Text>
          </View>
        )}
        {rows.map((r, i) => (
          <View key={`${r.name}-${i}`} style={[s.row, i < 3 && { borderColor: '#e2c56b', borderWidth: 1.5 }]}>
            <Text style={{ width: 34, fontSize: i < 3 ? 20 : 14, fontWeight: '900', color: '#49524a', textAlign: 'center' }}>
              {MEDAL[i] ?? i + 1}
            </Text>
            <Avatar url={r.photoUrl} char={r.name[0]} bg={tab === 'dogs' ? '#c9a86e' : '#5a7a3c'} size={40} />
            <Text style={{ flex: 1, fontSize: 16.5, fontWeight: '800', color: FOREST, marginLeft: 10 }} numberOfLines={1}>
              {r.name}
            </Text>
            <Text style={{ fontSize: 17, fontWeight: '900', color: '#5a7a3c' }}>
              {tab === 'dogs' ? `${r.km}km` : `${r.runs}회`}
            </Text>
          </View>
        ))}

        <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginTop: 16, lineHeight: 17 }}>
          주간 TOP 3 시즌 보상은 곧 공개돼요{'\n'}랭킹은 완주한 러닝만 집계해요
        </Text>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  milesCard: { backgroundColor: FOREST, borderRadius: 20, padding: 18, marginTop: 16 },
  tabWrap: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 99, padding: 4, marginTop: 16, borderWidth: 1, borderColor: '#DCD6C4' },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 10, borderRadius: 99 },
  emptyBox: { marginTop: 20, backgroundColor: '#f4f2ea', borderRadius: 16, padding: 18 },
  row: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff',
    borderRadius: 16, padding: 12, borderWidth: 1, borderColor: '#DCD6C4', marginTop: 8,
  },
});
