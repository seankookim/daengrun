import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomNav } from '../src/components/bottomnav';
import { TabSwipe } from '../src/components/tabswipe';
import { Row } from '../src/components/ui';
import { DropRow, fetchActiveBoostLabel, fetchDrops, fetchGearClaims, fetchMiles, GearClaim, MilesInfo } from '../src/lib/api';
import { claimStatusLabel } from '../src/lib/claim-status';
import { products, session } from '../src/store';
import { colors, paper } from '../src/theme';

// 도그스하이 샵 셸 (2026-07-29) — '하이 포인트 사용처' 허브.
// 실데이터: 포인트 잔액(0027 RPC)·최근 적립·기어 교환권·도착한 드랍(러너).
// 상품 그리드는 실 SKU 전 미리보기 — 섹션 단위로 '오픈 준비 중'을 명시 (정직 폴리시).
// 은퇴: '멤버는 전 상품 10% 할인' 히어로 — 존재하지 않는 혜택의 확정 약속은 정직 원칙 위반.
//
// ⚠ [2026-09-15 죽은 버튼 은퇴] 이 화면에는 「준비 중」 얼럿만 띄우는 컨트롤이 넷 있었다 —
// 헤더의 장바구니 버튼 · 제품 검색 바 · 카드마다의 담기(+) 버튼 · 카드 탭. 넷 다 뒤에 아무
// RPC 도 없다 (api.ts 에 장바구니·검색·주문이 존재하지 않는다). 섹션 라벨('오픈 준비 중')이
// 덮는 것은 **상품이 예정이라는 사실**이지, 누르면 아무 일도 없는 컨트롤이 아니다 — 장바구니
// 아이콘과 검색 바는 그 자체로 「이 스토어는 지금 거래된다」는 주장이었다. 없는 동작은 얼럿으로
// 사과하는 게 아니라 그리지 않는다 (CLAUDE.md 정직 법: 죽은 버튼 금지). 미리보기 그리드는
// 그대로 남는다 — 예정가는 '예정' 라벨을 달고 있고, 그건 참인 문장이다.
// 되살리는 조건은 하나: 장바구니·검색·주문이 실제로 생기면 그때 컨트롤도 같이 온다.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const CATS = ['전체', '간식', '용품', '의류', '영양제'];

export default function Shop() {
  const insets = useSafeAreaInsets();
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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>{/* [페이퍼 크롬 2026-08-10] 테라 크래프트 배경 은퇴 → 백지 캔버스. 테라코타는 액센트·가격·CTA(부티크 보이스)로만 생존 */}
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: insets.top }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between', marginBottom: 16 }}>
          {/* 탭 루트 — 뒤로가기 없음 (표준 탭 헤더) */}
          {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A). 색은 이 화면의 월드 유지 */}
          <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>도그스하이 샵</Text>
        </Row>

        {/* 하이 포인트 히어로 — 화면의 다크 앵커 1개. 잔액은 실서버 집계(0027)만 그린다 */}
        <View style={s.hero}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', letterSpacing: 2, color: colors.volt }}>HIGH POINT</Text>
              <Text style={[{ fontSize: 34, fontWeight: '900', color: '#fff', marginTop: 5 }, nf]}>
                {miles ? miles.balance.toLocaleString() : '—'}
                <Text style={{ fontSize: 15, color: '#b8c4ae' }}> 포인트</Text>
              </Text>
            </View>
            {isRunner && (
              <Pressable onPress={() => router.push('/runner/rewards')} style={s.heroGo}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: paper.ink }}>리워드 센터 ›</Text>
              </Pressable>
            )}
          </Row>
          {miles && miles.recent.length > 0 ? (
            <View style={{ marginTop: 10, borderTopWidth: 1, borderTopColor: '#24382a', paddingTop: 9, gap: 4 }}>
              {miles.recent.slice(0, 2).map((r, i) => (
                <Row key={i} style={{ justifyContent: 'space-between' }}>
                  <Text style={{ fontSize: 15, color: '#8fa093' }}>{r.reason} · {r.when}</Text>
                  <Text style={{ fontSize: 15, fontWeight: '900', color: r.delta >= 0 ? colors.volt : colors.tang }}>
                    {r.delta >= 0 ? '+' : ''}{r.delta.toLocaleString()}
                  </Text>
                </Row>
              ))}
            </View>
          ) : (
            <Text style={{ fontSize: 15, color: '#8fa093', marginTop: 8 }}>
              완주 +50 · 응가 도장 +30 · 패치 승급 보너스 · 주간 TOP3
            </Text>
          )}
        </View>

        {/* 활성 부스트 (픽 드랍 보상, 실데이터) — 활성일 때만 그린다 */}
        {isRunner && boostUntil && (
          <View style={s.boostStrip}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#4a6d1f' }}>매칭 부스트 활성 · {boostUntil}까지</Text>
          </View>
        )}

        {/* 도착한 드랍 (러너, 실카운트) — 열 것이 있을 때만 그린다 */}
        {isRunner && unopened.length > 0 && (
          <Pressable onPress={() => router.push('/runner/rewards')} style={s.dropStrip}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: paper.ink }}>
              도착한 드랍 {unopened.length}개 — 열어보세요 ›
            </Text>
          </Pressable>
        )}

        {/* 기어 교환권 (실데이터) — 있을 때만 */}
        {claims.length > 0 && (
          <>
            <Row style={[s.secRow, { gap: 7, marginTop: 18, marginBottom: 8 }]}>
              <Text style={s.section}>내 기어 교환권</Text>
              {claimable.length > 0 && (
                <View style={s.countPill}><Text style={{ fontSize: 15, fontWeight: '900', color: '#3d5a2b' }}>{claimable.length}</Text></View>
              )}
            </Row>
            <View style={s.card}>
              {claims.map((g, i) => (
                <View key={g.id}>
                  {i > 0 && <View style={s.div} />}
                  <Row style={{ paddingVertical: 10, justifyContent: 'space-between' }}>
                    <View style={{ flex: 1, paddingRight: 8 }}>
                      <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>{g.item}</Text>
                      <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>{g.milestone}회 달성 보상</Text>
                    </View>
                    <View style={[s.claimPill, g.status !== 'claimable' && { backgroundColor: '#EEF0EA' }]}>
                      <Text style={{ fontSize: 15, fontWeight: '800', color: g.status === 'claimable' ? '#3d5a2b' : '#75806f' }}>
                        {/* claim_status is a closed pg enum of four (0001_init.sql:21) and this
                            line covered TWO of them — claimed/shipped printed the raw English
                            token on a Korean screen. Single source now: src/lib/claim-status.ts,
                            shared with runner/rewards.tsx, which covered only one. */}
                        {claimStatusLabel(g.status)}
                      </Text>
                    </View>
                  </Row>
                </View>
              ))}
            </View>
          </>
        )}

        {/* ---------- 스토어 미리보기 — 실 SKU 전, 섹션 단위 정직 라벨 ---------- */}
        <Row style={[s.secRow, { gap: 7, marginTop: 20, marginBottom: 2, alignItems: 'center' }]}>
          <View style={s.gearTag}><Text style={{ fontSize: 9.5, fontWeight: '900', letterSpacing: 1.5, color: '#fff' }}>DOGS HIGH GEAR</Text></View>
          <Text style={[s.section, { color: colors.terraInk }]}>부티크 미리보기</Text>
          <Text style={{ fontSize: 15, color: '#A87A62', fontWeight: '700' }}>· 오픈 준비 중</Text>
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
            <View key={p.id} style={[s.prod, { backgroundColor: '#fff', borderWidth: 1, borderColor: '#EEEEEE' }]}>{/* [페이퍼 크롬] 카드 = 샤프 1px #EEE (테라 틴트 보더 은퇴) */}
              <Text style={{ fontSize: 15, fontWeight: '900', color: p.fg }}>{p.tag}</Text>
              <Text style={s.prodName} numberOfLines={2}>{p.name}</Text>
              <Text style={{ fontSize: 15, color: '#A87A62', marginTop: 3 }}>{p.collab}</Text>
              {/* product visual placeholder */}
              <View style={s.prodVisual}>
                <Text style={{ fontSize: 34.5, fontWeight: '900', color: `${p.fg}33` }}>{p.tag}</Text>
              </View>
              <Row style={{ justifyContent: 'space-between', marginTop: 'auto' }}>
                <Text style={{ fontSize: 18.5, fontWeight: '900', color: colors.terraInk }}>
                  {p.price.toLocaleString()}원<Text style={{ fontSize: 15, color: '#A87A62', fontWeight: '700' }}> 예정</Text>
                </Text>
              </Row>
            </View>
          ))}
        </View>
      </ScrollView>
      </TabSwipe>
      <BottomNav />
    </View>
  );
}

// [페이퍼 크롬 2026-08-10] 샵 크롬 페이퍼 이행 — 라운드·테라 틴트 보더 은퇴, 카드 = 샤프 1px #EEE.
// 테라코타(gearTag·가격 잉크·활성 카테고리)와 볼트 리워드 스트립 필은 시맨틱으로 생존.
// (addBtn·circleBtn·search 스타일은 그 컨트롤들과 함께 은퇴 — 위 죽은 버튼 주석 참고.)
const s = StyleSheet.create({
  // 섹션 헤더 — 풀블리드 코랄 1px 룰 (스크롤 패딩 16을 음수 마진으로 뚫는다)
  secRow: { marginHorizontal: -16, paddingHorizontal: 16, borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 12 },
  hero: { backgroundColor: paper.ink, borderRadius: 0, padding: 18 }, // 다크 앵커는 아티팩트 — 코너만 샤프
  heroGo: { backgroundColor: colors.volt, borderRadius: 0, paddingVertical: 8, paddingHorizontal: 13 },
  dropStrip: { backgroundColor: '#eaf7c8', borderRadius: 0, padding: 14, marginTop: 10, borderWidth: 1, borderColor: '#c9dd8f', alignItems: 'center' }, // 볼트 워시 = 시맨틱 (보상 신호)
  boostStrip: { backgroundColor: '#fff', borderRadius: 0, padding: 12, marginTop: 10, borderWidth: 1, borderColor: '#c9dd8f', alignItems: 'center' },
  section: { fontSize: 17, fontWeight: '900', color: paper.ink },
  countPill: { minWidth: 20, height: 20, borderRadius: 0, backgroundColor: '#e3f0c4', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 5, alignSelf: 'center' },
  card: { backgroundColor: '#fff', borderRadius: 0, padding: 14, borderWidth: 1, borderColor: '#EEEEEE' },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  claimPill: { backgroundColor: '#eaf7c8', borderRadius: 0, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  cat: { borderRadius: 0, paddingVertical: 10, paddingHorizontal: 18, backgroundColor: '#fff', borderWidth: 1, borderColor: '#EEEEEE' },
  gearTag: { backgroundColor: colors.terra, borderRadius: 0, paddingVertical: 3, paddingHorizontal: 9 },
  prod: { width: '47.5%', borderRadius: 0, padding: 14, minHeight: 210 },
  prodName: { fontSize: 16.5, fontWeight: '900', color: '#4A2A18', marginTop: 6, lineHeight: 23 },
  prodVisual: { flex: 1, alignItems: 'center', justifyContent: 'center', marginVertical: 8 },
});
