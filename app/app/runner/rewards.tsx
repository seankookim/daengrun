import { useDisplayFont } from '../../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { DropRow, fetchDrops, fetchGearClaims, fetchMiles, fetchMyRunnerStatus, GearClaim, MilesInfo, MyRunnerStatus, openDrop } from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { colors } from '../../src/theme';

// 리워드 센터 — 실화: 하이 포인트 잔액·드랍 오픈(open-drop)·기어 교환권. 목업 사다리 은퇴.
// 5회 보급 드랍(랜덤·바닥 보장) · 10회 픽 드랍(3택1 — 선택 데이터 = 러너 동기 시그널)

const FOREST = '#0F1D13';

export default function Rewards() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [miles, setMiles] = useState<MilesInfo | null>(null);
  const [drops, setDrops] = useState<DropRow[]>([]);
  const [claims, setClaims] = useState<GearClaim[]>([]);
  const [rs, setRs] = useState<MyRunnerStatus | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = () => Promise.all([
    fetchMiles().then(setMiles).catch(() => {}),
    fetchDrops().then(setDrops).catch((e) => console.warn('[rewards] drops:', e?.message ?? e)),
    fetchGearClaims().then(setClaims).catch(() => {}),
    fetchMyRunnerStatus().then(setRs).catch(() => {}),
  ]);
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const open = async (d: DropRow, pick?: string) => {
    setBusy(d.id);
    try {
      const applied = await openDrop(d.id, pick);
      haptic('success');
      const parts: string[] = [];
      if (applied.miles) parts.push(`+${(applied.miles as number).toLocaleString()} 하이 포인트`);
      if (applied.card) parts.push(`카드 「${applied.card}」`);
      if (applied.gear) parts.push(`기어: ${applied.gear}`);
      if (applied.boost_until) parts.push('부스트 24시간 활성');
      Alert.alert('드랍 오픈! 🎉', parts.join('\n') || '보상이 적용됐어요');
      load();
    } catch (e) {
      Alert.alert('오픈 실패', (e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  const unopened = drops.filter((d) => !d.openedAt);
  const opened = drops.filter((d) => d.openedAt);
  const cycle5 = (rs?.totalRuns ?? 0) % 5;

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.cream }}
      contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
    >
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Text style={[{ fontSize: 23, fontWeight: '900', color: FOREST }, df]}>리워드 센터</Text>
        <View style={{ width: 40 }} />
      </Row>

      {/* 하이 포인트 */}
      <View style={s.milesCard}>
        <Text style={{ fontSize: 14.5, color: '#b8c4ae', letterSpacing: 1.5 }}>내 하이 포인트</Text>
        <Text style={{ fontSize: 39, fontWeight: '900', color: colors.volt, marginTop: 4 }}>
          {miles?.balance?.toLocaleString() ?? '—'}<Text style={{ fontSize: 15, color: '#b8c4ae' }}> 포인트</Text>
        </Text>
        <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 6 }}>
          완주 +50 · 응가 도장 +30 · 드랍 보상 · 주간 TOP3 보너스
        </Text>
      </View>

      {/* 미오픈 드랍 */}
      <Text style={s.section}>도착한 드랍 {unopened.length > 0 ? `(${unopened.length})` : ''}</Text>
      {unopened.length === 0 && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 14.5, color: colors.dim, textAlign: 'center', lineHeight: 22 }}>
            대기 중인 드랍이 없어요{'\n'}{5 - cycle5}번 더 완주하면 보급 드랍이 도착해요
          </Text>
        </View>
      )}
      {unopened.map((d) => (
        <View key={d.id} style={s.dropCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: colors.volt }}>
              {d.kind === 'pick' ? '🎁 픽 드랍' : '▣ 보급 드랍'} · {d.runCountAt}회 달성
            </Text>
            <Text style={{ fontSize: 14, color: '#8fa093' }}>{d.when}</Text>
          </Row>
          {d.kind === 'pick' ? (
            <>
              <Text style={{ fontSize: 15, color: '#b8c4ae', marginTop: 8 }}>셋 중 하나를 선택하세요 — 되돌릴 수 없어요</Text>
              <Row style={{ gap: 8, marginTop: 10 }}>
                {([['boost', '⚡ 부스트'], ['miles', '◈ 5,000포인트'], ['gear', '👕 기어']] as const).map(([k, label]) => (
                  <Pressable key={k} disabled={busy !== null} onPress={() => open(d, k)} style={[s.pickBtn, busy === d.id && { opacity: 0.5 }]}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>{label}</Text>
                  </Pressable>
                ))}
              </Row>
            </>
          ) : (
            <Pressable disabled={busy !== null} onPress={() => open(d)} style={[s.openBtn, busy === d.id && { opacity: 0.5 }]}>
              <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>{busy === d.id ? '여는 중...' : '상자 열기'}</Text>
            </Pressable>
          )}
        </View>
      ))}

      {/* 기어 교환권 */}
      {claims.length > 0 && (
        <>
          <Text style={s.section}>기어 교환권</Text>
          <View style={s.card}>
            {claims.map((g, i) => (
              <View key={g.id}>
                {i > 0 && <View style={s.div} />}
                <Row style={{ paddingVertical: 10, justifyContent: 'space-between' }}>
                  <View>
                    <Text style={{ fontSize: 15.5, fontWeight: '800', color: FOREST }}>{g.item}</Text>
                    <Text style={{ fontSize: 14, color: colors.dim, marginTop: 2 }}>{g.milestone}회 달성 보상</Text>
                  </View>
                  <View style={s.claimPill}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: g.status === 'claimable' ? '#3d5a2b' : '#75806f' }}>
                      {g.status === 'claimable' ? '수령 가능 · 배송 연동 준비 중' : g.status}
                    </Text>
                  </View>
                </Row>
              </View>
            ))}
          </View>
        </>
      )}

      {/* 오픈 히스토리 */}
      {opened.length > 0 && (
        <>
          <Text style={s.section}>지난 드랍</Text>
          {opened.map((d) => (
            <View key={d.id} style={[s.card, { marginBottom: 8, opacity: 0.75 }]}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>
                  {/* 포인트가 실제로 들어 있을 때만 괄호를 연다 — '+0포인트'는 없는 적립을 그리는 것 */}
                  {d.kind === 'pick'
                    ? `픽 드랍 — ${d.pickChoice === 'miles' ? '5,000포인트' : d.pickChoice === 'boost' ? '부스트' : '기어'} 선택`
                    : typeof d.contents.miles === 'number' && d.contents.miles > 0
                      ? `보급 드랍 (+${d.contents.miles.toLocaleString()}포인트)`
                      : '보급 드랍'}
                </Text>
                <Text style={{ fontSize: 14, color: colors.dim }}>{d.when}</Text>
              </Row>
            </View>
          ))}
        </>
      )}

      <Pressable onPress={() => router.push('/leaderboard')} style={s.rankLink}>
        <Text style={{ fontSize: 14.5, fontWeight: '800', color: colors.tang }}>🏆 동네 랭킹에서 주간 보너스 노려보기 ›</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  milesCard: { backgroundColor: FOREST, borderRadius: 20, padding: 18, marginTop: 16 },
  section: { fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 8 },
  emptyBox: { backgroundColor: '#f4f2ea', borderRadius: 16, padding: 20 },
  dropCard: { backgroundColor: FOREST, borderRadius: 18, padding: 16, marginBottom: 10, borderWidth: 1.5, borderColor: colors.volt },
  openBtn: { backgroundColor: colors.volt, borderRadius: 13, alignItems: 'center', paddingVertical: 12, marginTop: 12 },
  pickBtn: { flex: 1, backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11 },
  card: { backgroundColor: '#fff', borderRadius: 16, padding: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  claimPill: { backgroundColor: '#eaf7c8', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  rankLink: { alignItems: 'center', marginTop: 18, padding: 10 },
});
