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
import { colors, paper, secTitle } from '../src/theme';

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
//
// [2026-09-25] The category chip row (전체 · 간식 · 용품 · 의류 · 영양제) is gone too. It was five
// plain <View>s with the first one painted as the SELECTED filter — a filter affordance with no
// onPress, no state and no filtering behind it, i.e. the same false claim the 2026-09-15 retirement
// above removed from the cart and search bar, which that pass missed. It comes back with a real
// catalog filter, not before.

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
  // [honesty 2026-09-17] All four reads were `.catch(() => {})` — no state, no console, no retry —
  // so a FAILED read rendered as the settled face: the earn-rate blurb ("you have no recent
  // points"), the 교환권 section absent ("you own none"), the drop and boost strips absent
  // ("nothing arrived"). Loading, failure and empty were one face. Each read now owns a flag and
  // a failed one renders a strip with a retry, the runner/rewards.tsx drops grammar.
  // ⚠ Last-known rows stay on screen beside the strip — setters only run on success, so a failed
  // refresh never erases data that did arrive. The strip says the READ failed, not that it is 0.
  const [milesErr, setMilesErr] = useState(false);
  const [claimsErr, setClaimsErr] = useState(false);
  const [dropsErr, setDropsErr] = useState(false);
  const [boostErr, setBoostErr] = useState(false);
  const load = () => {
    setMilesErr(false); setClaimsErr(false); setDropsErr(false); setBoostErr(false);
    return Promise.all([
      fetchMiles().then(setMiles)
        .catch((e) => { console.warn('[shop] miles:', (e as Error)?.message ?? e); setMilesErr(true); }),
      fetchGearClaims().then(setClaims)
        .catch((e) => { console.warn('[shop] claims:', (e as Error)?.message ?? e); setClaimsErr(true); }),
      isRunner
        ? fetchDrops().then(setDrops)
            .catch((e) => { console.warn('[shop] drops:', (e as Error)?.message ?? e); setDropsErr(true); })
        : Promise.resolve(),
      isRunner
        ? fetchActiveBoostLabel().then(setBoostUntil)
            .catch((e) => { console.warn('[shop] boost:', (e as Error)?.message ?? e); setBoostErr(true); })
        : Promise.resolve(),
    ]);
  };
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
              <Text style={{ fontSize: 12.5, fontWeight: '800', letterSpacing: 2, color: colors.volt }}>HIGH POINT</Text>{/* floor-exempt: latin-kicker — hero kicker over the balance */}
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
          {/* Four faces, never one. The earn-rate blurb is the SETTLED face — it means "the read
              arrived and there is no recent activity" — so a failure and a pending read must never
              print it. 잔액 above stays — while the balance is unknown; a 0 would be a lie.
              Ink on this dark anchor uses the hero's own vocabulary (tang · volt), not paper.critical. */}
          {milesErr ? (
            <View style={{ marginTop: 10, borderTopWidth: 1, borderTopColor: '#24382a', paddingTop: 9 }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: colors.tang }}>하이 포인트를 불러오지 못했어요</Text>
              <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
                <Text style={{ fontSize: 16, fontWeight: '800', color: colors.volt, textDecorationLine: 'underline' }}>다시 시도</Text>
              </Pressable>
            </View>
          ) : miles == null ? (
            <Text style={{ fontSize: 15, color: '#8fa093', marginTop: 8 }}>불러오는 중…</Text>
          ) : miles.recent.length > 0 ? (
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

        {/* A failed boost read used to be indistinguishable from "no boost is active" — the strip
            simply did not render. Say which one it is. */}
        {isRunner && boostErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>매칭 부스트를 확인하지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* 활성 부스트 (픽 드랍 보상, 실데이터) — 활성일 때만 그린다 */}
        {isRunner && boostUntil && (
          <View style={s.boostStrip}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#4a6d1f' }}>매칭 부스트 활성 · {boostUntil}까지</Text>
          </View>
        )}

        {/* Same for drops: an absent strip meant "nothing arrived", and a failed read said exactly
            that. Strip sits above the real one, so a stale-but-true count still shows beside it. */}
        {isRunner && dropsErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>드랍을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
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

        {/* 기어 교환권 — a failed read used to render as "you own none" (the section vanished). */}
        {claimsErr && (
          <>
            <Row style={[s.secRow, { gap: 7, marginTop: 18, marginBottom: 8 }]}>
              <Text style={s.section}>내 기어 교환권</Text>
            </Row>
            <View style={s.failStrip}>
              <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>교환권을 불러오지 못했어요</Text>
              <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
                <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
              </Pressable>
            </View>
          </>
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
          <View style={s.gearTag}><Text style={{ fontSize: 9.5, fontWeight: '900', letterSpacing: 1.5, color: '#fff' }}>DOGS HIGH GEAR</Text></View>{/* floor-exempt: latin-kicker — terracotta boutique tag */}
          <Text style={[s.section, { color: colors.terraInk }]}>부티크 미리보기</Text>
          <Text style={{ fontSize: 15, color: '#A87A62', fontWeight: '700' }}>· 오픈 준비 중</Text>
        </Row>

        {/* product grid — 예정 상품 미리보기 (가격은 예정가). marginTop 12 = the gap the chip row's
            marginVertical used to leave above the grid. */}
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginTop: 12 }}>
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
// Terracotta (gearTag · price ink) and the volt reward-strip fills survive as semantics. The lit
// category chip retired on 2026-09-25 with its row (see the header note).
// (addBtn·circleBtn·search 스타일은 그 컨트롤들과 함께 은퇴 — 위 죽은 버튼 주석 참고.)
const s = StyleSheet.create({
  // 섹션 헤더 — 풀블리드 코랄 1px 룰 (스크롤 패딩 16을 음수 마진으로 뚫는다)
  secRow: { marginHorizontal: -16, paddingHorizontal: 16, borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 12 },
  hero: { backgroundColor: paper.ink, borderRadius: 0, padding: 18 }, // 다크 앵커는 아티팩트 — 코너만 샤프
  heroGo: { backgroundColor: colors.volt, borderRadius: 0, paddingVertical: 8, paddingHorizontal: 13 },
  dropStrip: { backgroundColor: '#eaf7c8', borderRadius: 0, padding: 14, marginTop: 10, borderWidth: 1, borderColor: '#c9dd8f', alignItems: 'center' }, // 볼트 워시 = 시맨틱 (보상 신호)
  boostStrip: { backgroundColor: '#fff', borderRadius: 0, padding: 12, marginTop: 10, borderWidth: 1, borderColor: '#c9dd8f', alignItems: 'center' },
  // §3b section title — theme.secTitle (was 17/900: one of five section sizes shipping app-wide).
  // secRow above already draws the full-bleed coral rule.
  section: { ...secTitle },
  countPill: { minWidth: 20, height: 20, borderRadius: 0, backgroundColor: '#e3f0c4', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 5, alignSelf: 'center' },
  card: { backgroundColor: '#fff', borderRadius: 0, padding: 14, borderWidth: 1, borderColor: '#EEEEEE' },
  // loud-fail strip — runner/rewards.tsx grammar (criticalWash ground, critical ink, underlined
  // retry at ≥44pt). No ink border: it fights the critical ink inside the wash.
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 0, padding: 13, marginTop: 10 },
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  claimPill: { backgroundColor: '#eaf7c8', borderRadius: 0, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  gearTag: { backgroundColor: colors.terra, borderRadius: 0, paddingVertical: 3, paddingHorizontal: 9 },
  prod: { width: '47.5%', borderRadius: 0, padding: 14, minHeight: 210 },
  prodName: { fontSize: 16.5, fontWeight: '900', color: '#4A2A18', marginTop: 6, lineHeight: 23 },
  prodVisual: { flex: 1, alignItems: 'center', justifyContent: 'center', marginVertical: 8 },
});
