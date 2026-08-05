import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { DropRow, fetchActiveBoostLabel, fetchDrops, fetchGearClaims, fetchMiles, GearClaim, MilesInfo } from '../src/lib/api';
import { products, session } from '../src/store';
import { colors } from '../src/theme';

// 도그스하이 샵 셸 (2026-07-29) — '하이 포인트 사용처' 허브.
// 실데이터: 포인트 잔액(0027 RPC)·최근 적립·기어 교환권·도착한 드랍(러너).
// 상품 그리드는 실 SKU 전 미리보기 — 섹션 단위로 '오픈 준비 중'을 명시 (정직 폴리시).
// 은퇴: '멤버는 전 상품 10% 할인' 히어로 — 존재하지 않는 혜택의 확정 약속은 정직 원칙 위반.

const FOREST = '#0F1D13';
const CATS = ['전체', '간식', '용품', '의류', '영양제'];

export default function Shop() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const nf = useNumFont(); // [V4] 포인트 잔액 = Oswald
  const [miles, setMiles] = useState<MilesInfo | null>(null);
  const [claims, setClaims] = useState<GearClaim[]>([]);
  const [drops, setDrops] = useState<DropRow[]>([]);
  const [boostUntil, setBoostUntil] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const isRunner = session.role === 'runner';
  const load = () => Promise.all([
    fetchMiles().then(setMiles).catch(() => {}), // 미로그인/RPC 미배포 → 잔액 미표시 (가짜 0 금지)
    fetchGearClaims().then(setClaims).catch(() => {}),
    isRunner ? fetchDrops().then(setDrops).catch(() => {}) : Promise.resolve(),
    isRunner ? fetchActiveBoostLabel().then(setBoostUntil).catch(() => {}) : Promise.resolve(),
  ]);
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const unopened = drops.filter((d) => !d.openedAt);
  const claimable = claims.filter((g) => g.status === 'claimable');

  return (
    <View style={{ flex: 1, backgroundColor: colors.terraCraft }}>{/* 크래프트 종이 — 샵 = 부티크 (P5) */}
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 56 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between', marginBottom: 16 }}>
          {/* 탭 루트 — 뒤로가기 없음 (표준 탭 헤더) */}
          <Text style={[{ fontSize: 30, fontWeight: '900', color: FOREST }, df]}>도그스하이 샵</Text>
          <Pressable style={s.circleBtn} onPress={() => Alert.alert('준비 중', '스토어 오픈 시 장바구니가 열려요')}>
            <Text style={{ fontSize: 17, color: FOREST }}>◱</Text>
          </Pressable>
        </Row>

        {/* 검색 — 스토어 오픈 전이라 정직하게 안내 */}
        <Pressable onPress={() => Alert.alert('준비 중', '스토어 오픈 시 검색이 열려요')} style={s.search}>
          <Text style={{ fontSize: 15, color: '#9a978a' }}>⌕  제품 검색</Text>
        </Pressable>

        {/* 하이 포인트 히어로 — 화면의 다크 앵커 1개. 잔액은 실서버 집계(0027)만 그린다 */}
        <View style={s.hero}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', letterSpacing: 2, color: colors.volt }}>HIGH POINT</Text>
              <Text style={[{ fontSize: 34, fontWeight: '900', color: '#fff', marginTop: 5 }, nf]}>
                {miles ? miles.balance.toLocaleString() : '—'}
                <Text style={{ fontSize: 14, color: '#b8c4ae' }}> 포인트</Text>
              </Text>
            </View>
            {isRunner && (
              <Pressable onPress={() => router.push('/runner/rewards')} style={s.heroGo}>
                <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>리워드 센터 ›</Text>
              </Pressable>
            )}
          </Row>
          {miles && miles.recent.length > 0 ? (
            <View style={{ marginTop: 10, borderTopWidth: 1, borderTopColor: '#24382a', paddingTop: 9, gap: 4 }}>
              {miles.recent.slice(0, 2).map((r, i) => (
                <Row key={i} style={{ justifyContent: 'space-between' }}>
                  <Text style={{ fontSize: 14.5, color: '#8fa093' }}>{r.reason} · {r.when}</Text>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: r.delta >= 0 ? colors.volt : colors.tang }}>
                    {r.delta >= 0 ? '+' : ''}{r.delta.toLocaleString()}
                  </Text>
                </Row>
              ))}
            </View>
          ) : (
            <Text style={{ fontSize: 14.5, color: '#8fa093', marginTop: 8 }}>
              완주 +50 · 응가 도장 +30 · 패치 승급 보너스 · 주간 TOP3
            </Text>
          )}
        </View>

        {/* 활성 부스트 (픽 드랍 보상, 실데이터) — 활성일 때만 그린다 */}
        {isRunner && boostUntil && (
          <View style={s.boostStrip}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: '#4a6d1f' }}>⚡ 매칭 부스트 활성 · {boostUntil}까지</Text>
          </View>
        )}

        {/* 도착한 드랍 (러너, 실카운트) — 열 것이 있을 때만 그린다 */}
        {isRunner && unopened.length > 0 && (
          <Pressable onPress={() => router.push('/runner/rewards')} style={s.dropStrip}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>
              🎁 도착한 드랍 {unopened.length}개 — 열어보세요 ›
            </Text>
          </Pressable>
        )}

        {/* 기어 교환권 (실데이터) — 있을 때만 */}
        {claims.length > 0 && (
          <>
            <Row style={{ gap: 7, marginTop: 18, marginBottom: 8 }}>
              <Text style={s.section}>내 기어 교환권</Text>
              {claimable.length > 0 && (
                <View style={s.countPill}><Text style={{ fontSize: 14, fontWeight: '900', color: '#3d5a2b' }}>{claimable.length}</Text></View>
              )}
            </Row>
            <View style={s.card}>
              {claims.map((g, i) => (
                <View key={g.id}>
                  {i > 0 && <View style={s.div} />}
                  <Row style={{ paddingVertical: 10, justifyContent: 'space-between' }}>
                    <View style={{ flex: 1, paddingRight: 8 }}>
                      <Text style={{ fontSize: 15.5, fontWeight: '800', color: FOREST }}>{g.item}</Text>
                      <Text style={{ fontSize: 14, color: colors.dim, marginTop: 2 }}>{g.milestone}회 달성 보상</Text>
                    </View>
                    <View style={[s.claimPill, g.status !== 'claimable' && { backgroundColor: '#EEF0EA' }]}>
                      <Text style={{ fontSize: 14, fontWeight: '800', color: g.status === 'claimable' ? '#3d5a2b' : '#75806f' }}>
                        {g.status === 'claimable' ? '수령 가능 · 배송 연동 준비 중' : g.status === 'locked' ? '잠김' : g.status}
                      </Text>
                    </View>
                  </Row>
                </View>
              ))}
            </View>
          </>
        )}

        {/* ---------- 스토어 미리보기 — 실 SKU 전, 섹션 단위 정직 라벨 ---------- */}
        <Row style={{ gap: 7, marginTop: 20, marginBottom: 2, alignItems: 'center' }}>
          <View style={s.gearTag}><Text style={{ fontSize: 9.5, fontWeight: '900', letterSpacing: 1.5, color: '#fff' }}>DOGS HIGH GEAR</Text></View>
          <Text style={[s.section, { color: colors.terraInk }]}>부티크 미리보기</Text>
          <Text style={{ fontSize: 14.5, color: '#A87A62', fontWeight: '700' }}>· 오픈 준비 중</Text>
        </Row>

        {/* categories */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginVertical: 12 }} contentContainerStyle={{ gap: 8 }}>
          {CATS.map((c, i) => (
            <View key={c} style={[s.cat, i === 0 && { backgroundColor: colors.terraDeep, borderColor: colors.terraDeep }]}>
              <Text style={{ fontSize: 15, fontWeight: '700', color: i === 0 ? '#fff' : '#3d453d' }}>{c}</Text>
            </View>
          ))}
        </ScrollView>

        {/* product grid — 예정 상품 미리보기 (가격은 예정가) */}
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
          {products.map((p) => (
            <Pressable key={p.id} style={[s.prod, { backgroundColor: '#fff', borderWidth: 1.5, borderColor: '#E8CDBE' }]} onPress={() => Alert.alert(p.name, '스토어 오픈 준비 중이에요')}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: p.fg }}>{p.tag}</Text>
              <Text style={s.prodName} numberOfLines={2}>{p.name}</Text>
              <Text style={{ fontSize: 14, color: '#A87A62', marginTop: 3 }}>{p.collab}</Text>
              {/* product visual placeholder */}
              <View style={s.prodVisual}>
                <Text style={{ fontSize: 34.5, fontWeight: '900', color: `${p.fg}33` }}>{p.tag}</Text>
              </View>
              <Row style={{ justifyContent: 'space-between', marginTop: 'auto' }}>
                <Text style={{ fontSize: 18.5, fontWeight: '900', color: colors.terraInk }}>
                  {p.price.toLocaleString()}원<Text style={{ fontSize: 14, color: '#A87A62', fontWeight: '700' }}> 예정</Text>
                </Text>
                <Pressable style={s.addBtn} onPress={() => Alert.alert('준비 중', '스토어 오픈 시 담을 수 있어요')}>
                  <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>+</Text>
                </Pressable>
              </Row>
            </Pressable>
          ))}
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  search: { backgroundColor: '#fff', borderRadius: 6, paddingVertical: 12, paddingHorizontal: 14, borderWidth: 1, borderColor: '#E5D5C6', marginBottom: 12 },
  circleBtn: { width: 40, height: 40, borderRadius: 6, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#D8DAD2' },
  hero: { backgroundColor: FOREST, borderRadius: 6, padding: 18 },
  heroGo: { backgroundColor: colors.volt, borderRadius: 4, paddingVertical: 8, paddingHorizontal: 13 },
  dropStrip: { backgroundColor: '#eaf7c8', borderRadius: 6, padding: 14, marginTop: 10, borderWidth: 1.5, borderColor: '#c9dd8f', alignItems: 'center' },
  boostStrip: { backgroundColor: '#fff', borderRadius: 6, padding: 12, marginTop: 10, borderWidth: 1.5, borderColor: '#c9dd8f', alignItems: 'center' },
  section: { fontSize: 17, fontWeight: '900', color: FOREST },
  countPill: { minWidth: 20, height: 20, borderRadius: 4, backgroundColor: '#e3f0c4', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 5, alignSelf: 'center' },
  card: { backgroundColor: '#fff', borderRadius: 6, padding: 14, borderWidth: 1, borderColor: '#D8DAD2' },
  div: { height: 1, backgroundColor: '#EEF0EA' },
  claimPill: { backgroundColor: '#eaf7c8', borderRadius: 4, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  cat: { borderRadius: 4, paddingVertical: 10, paddingHorizontal: 18, backgroundColor: '#fff', borderWidth: 1, borderColor: '#E5D5C6' },
  gearTag: { backgroundColor: colors.terra, borderRadius: 4, paddingVertical: 3, paddingHorizontal: 9 },
  prod: { width: '47.5%', borderRadius: 6, padding: 14, minHeight: 210 },
  prodName: { fontSize: 16.5, fontWeight: '900', color: '#4A2A18', marginTop: 6, lineHeight: 23 },
  prodVisual: { flex: 1, alignItems: 'center', justifyContent: 'center', marginVertical: 8 },
  addBtn: { width: 30, height: 30, borderRadius: 6, backgroundColor: colors.terra, alignItems: 'center', justifyContent: 'center' },
});
