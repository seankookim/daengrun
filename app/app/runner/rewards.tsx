import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { DropRow, fetchDrops, fetchGearClaims, fetchMiles, fetchMyRunnerStatus, GearClaim, MilesInfo, MyRunnerStatus, openDrop } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { colors, layout, paper } from '../../src/theme';

// 리워드 센터 — 실화: 하이 포인트 잔액·드랍 오픈(open-drop)·기어 교환권. 목업 사다리 은퇴.
// 5회 보급 드랍(랜덤·바닥 보장) · 10회 픽 드랍(3택1 — 선택 데이터 = 러너 동기 시그널)
//
// [paper repaint 2026-08-11] forest/cream chrome scrapped → paper. Kept as artifacts:
// the points balance face and the unopened-drop cards stay DARK (paper.ink + volt edge —
// a drop is a ceremony object) with volt open/pick buttons (personal reward semantics).
// §3b: sections = coral rule + 20/800 (count folds into the title line), history cards
// lose the 0.75 opacity (explicit dim ink instead), Korean captions lose latin tracking.
// Ladder/cycle logic untouched. Behavior frozen: load fan-out, openDrop(pick), routes.
//
// [enh lab B① + B③ · Sean 2026-08-24, verbatim: "I like b1 but also show them what's next."]
//   B① 포인트 내역 — `fetchMiles()` already returns `recent[]` (10 real `miles_ledger` rows) on
//     every focus and this screen threw them away, while shop.tsx drew 2 of them and
//     leaderboard.tsx 3. The rewards centre, whose subject IS points, now draws its own ledger.
//     The earning-rules blurb is not deleted: it becomes the fallback when there is no history,
//     so a runner on day one still learns how points are earned. Sign comes from `delta`, never
//     from a '+' literal — `shop_spend` rows are negative (the leaderboard.tsx:76 point).
//   B③ what's next — the empty state did arithmetic and got the NOUN wrong: `5 - totalRuns % 5`
//     counts to the next multiple of five, but `settle_run_tx` (0083 §6:812-816) mints a 픽 drop
//     when the new total is a multiple of TEN and a mini only otherwise. At 17 완주 the screen
//     said 보급 and the server would mint 픽. Same arithmetic, one more test. Both the count and
//     the noun still render ONLY when `rs !== null` — a failed status fetch prints neither.
//     `runners.total_runs` increments on 완주 only (0083:796, `v_is_full`), which is the same gate
//     that mints the drop, so the two cannot drift.
// Neither variant adds a fetch, a column, a route, or a colour. No money is displayed on this
// screen at all — points are not currency and the 2026-08-24 margin rule does not reach here.

export default function Rewards() {
  const df = useDisplayFont(); // display font — screen title (1/screen budget)
  const nf = useNumFont();     // Oswald — points balance
  const [miles, setMiles] = useState<MilesInfo | null>(null);
  const [drops, setDrops] = useState<DropRow[]>([]);
  const [claims, setClaims] = useState<GearClaim[]>([]);
  const [rs, setRs] = useState<MyRunnerStatus | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // [honesty 2026-08-11] drops 실패가 "대기 중인 드랍이 없어요 + N번 더 완주"라는
  // 지어낸 빈 상태로 굳던 것 — 3상태 분리. miles/claims/rs는 이미 null→'—'/생략 처리라 soft 유지.
  const [dropsLoaded, setDropsLoaded] = useState(false);
  const [dropsErr, setDropsErr] = useState(false);
  const load = () => {
    setDropsErr(false);
    return Promise.all([
      fetchMiles().then(setMiles).catch(() => {}),
      fetchDrops()
        .then((d) => { setDrops(d); setDropsLoaded(true); })
        .catch((e) => { console.warn('[rewards] drops:', e?.message ?? e); setDropsErr(true); }),
      fetchGearClaims().then(setClaims).catch(() => {}),
      fetchMyRunnerStatus().then(setRs).catch(() => {}),
    ]);
  };
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
      Alert.alert('드랍 오픈!', parts.join('\n') || '보상이 적용됐어요');
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
  // [B③] 다음 드랍까지 남은 완주 수와 **그 드랍의 이름**. 서버(0083 §6:812-816)는 픽을 먼저 본다:
  // 새 누적이 10의 배수면 픽, 아니면(5의 배수면) 보급. 같은 순서로 판정한다 — 이름을 지어내지 않고
  // 서버가 실제로 만들 상자를 말한다. rs가 null이면 이 두 값은 화면에 나가지 않는다 (아래 게이트).
  const nextInRuns = 5 - cycle5;
  const nextIsPick = ((rs?.totalRuns ?? 0) + nextInRuns) % 10 === 0;
  // [B①] 포인트 내역 — fetchMiles가 이미 실어온 miles_ledger 10행. 비었으면(또는 못 불러왔으면)
  // 적립 규칙 한 줄이 그 자리를 지킨다: 0행짜리 내역을 그리는 것보다 규칙을 말하는 편이 정직하다.
  const recent = miles?.recent ?? [];

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 56, paddingBottom: 40 }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
    >
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={[{ fontSize: 23, fontWeight: '900', color: paper.ink }, df]}>리워드 센터</Text>
        <View style={{ width: 40 }} />
      </Row>

      {/* 하이 포인트 — dark balance face (artifact), volt numeral = personal reward */}
      <View style={s.milesCard}>
        <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>내 하이 포인트</Text>
        {/* Oswald balance — lineHeight 49 = 1.26× (BUG A) */}
        <Text style={[{ fontSize: 39, lineHeight: 49, fontWeight: '900', color: colors.volt, marginTop: 4, fontVariant: ['tabular-nums'] as const }, nf]}>
          {miles?.balance?.toLocaleString() ?? '—'}<Text style={{ fontSize: 15, color: '#BBBBBB' }}> 포인트</Text>
        </Text>
        {/* [B①] 잔액 아래는 그 잔액이 어떻게 만들어졌는지 — miles_ledger 실행들.
            부호는 delta가 진다: shop_spend는 음수이고, '+'를 붙여 그리면 쓴 돈이 번 돈이 된다. */}
        {recent.length > 0 ? (
          <View style={s.milesLedger}>
            {recent.map((m, i) => (
              <Row key={`${m.when}-${m.reason}-${i}`} style={s.mileRow}>
                <Text style={{ fontSize: 14.5, lineHeight: 20, color: '#BBBBBB', flex: 1 }} numberOfLines={1}>
                  {m.reason} · {m.when}
                </Text>
                {/* Oswald delta — lineHeight 20 = 1.33× (BUG A).
                    ⚠ 마이너스는 coralText(#d84a2f)가 아니라 tang(#FF5C3D)이다. coralText는 **흰
                    면 위의** 읽는 코랄이고, 이 카드는 잉크 면이다 — 역할이 뒤집힌다. 실측: #d84a2f
                    on #111111 = 4.48:1 (15pt 볼드는 큰 활자가 아니라 4.5 미달), tang = 6.24:1.
                    같은 이유로 플러스는 volt다 (14.99:1) — 이 화면의 개인 보상 색. 신규 색 0개. */}
                <Text style={[{ fontSize: 15, lineHeight: 20, fontWeight: '800', marginLeft: 10, color: m.delta < 0 ? colors.tang : colors.volt, fontVariant: ['tabular-nums'] as const }, nf]}>
                  {m.delta < 0 ? '−' : '+'}{Math.abs(m.delta).toLocaleString()}
                </Text>
              </Row>
            ))}
          </View>
        ) : (
          <Text style={{ fontSize: 14, lineHeight: 19, color: '#BBBBBB', marginTop: 6 }}>
            완주 +50 · 응가 도장 +30 · 드랍 보상 · 주간 TOP3 보너스
          </Text>
        )}
      </View>
      {recent.length > 0 && (
        <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 8 }}>최근 10건까지 보여요</Text>
      )}

      {/* 미오픈 드랍 — §3b section header */}
      <Row style={s.secWrap}>
        <Text style={s.secTitle}>도착한 드랍{unopened.length > 0 ? ` · ${unopened.length}` : ''}</Text>
      </Row>
      {!dropsLoaded && !dropsErr && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
        </View>
      )}
      {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
      {dropsErr && (
        <View style={s.failStrip}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>드랍을 불러오지 못했어요</Text>
          <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
          </Pressable>
        </View>
      )}
      {dropsLoaded && !dropsErr && unopened.length === 0 && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
            대기 중인 드랍이 없어요
            {/* run count claim only when the runner status actually arrived — no fabricated "5번 더".
                [B③] 상자의 이름도 같은 게이트 안에 있다: 10의 배수면 픽, 아니면 보급 (0083 §6). */}
            {rs != null ? `\n${nextInRuns}번 더 완주하면 ` : ''}
            {rs != null && (
              <Text style={{ fontWeight: '800', color: paper.ink }}>{nextIsPick ? '픽 드랍' : '보급 드랍'}</Text>
            )}
            {rs != null ? '이 도착해요' : ''}
          </Text>
          {/* 픽 드랍일 때만 한 줄 더 — 고를 수 있다는 사실이 픽의 전부다.
              세 선택지는 drops.contents.options 그대로 (0083 §6:814 minted ["boost","miles","gear"]). */}
          {rs != null && nextIsPick && (
            <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', lineHeight: 20, marginTop: 6 }}>
              픽 드랍은 부스트 · 5,000 포인트 · 기어 중 하나를 직접 골라요
            </Text>
          )}
        </View>
      )}
      {unopened.map((d) => (
        <View key={d.id} style={s.dropCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 17, fontWeight: '800', color: colors.volt }}>
              {d.kind === 'pick' ? '픽 드랍' : '보급 드랍'} · {d.runCountAt}회 달성
            </Text>
            <Text style={{ fontSize: 14, color: '#BBBBBB' }}>{d.when}</Text>
          </Row>
          {d.kind === 'pick' ? (
            <>
              {/* busy = hint-line label swap (the tapped choice is the card's action) */}
              <Text style={{ fontSize: 14.5, lineHeight: 19, color: '#BBBBBB', marginTop: 8 }}>
                {busy === d.id ? '적용 중...' : '셋 중 하나를 선택하세요 — 되돌릴 수 없어요'}
              </Text>
              <Row style={{ gap: 8, marginTop: 10 }}>
                {([['boost', '부스트'], ['miles', '5,000포인트'], ['gear', '기어']] as const).map(([k, label]) => (
                  <Pressable
                    key={k}
                    disabled={busy !== null}
                    onPress={() => open(d, k)}
                    style={({ pressed }) => [s.pickBtn, pressed && { backgroundColor: colors.voltDeep, transform: [{ scale: 0.96 }] }]}
                  >
                    <Text style={{ fontSize: 14, fontWeight: '800', color: '#111111' }}>{label}</Text>
                  </Pressable>
                ))}
              </Row>
            </>
          ) : (
            <Pressable
              disabled={busy !== null}
              onPress={() => open(d)}
              style={({ pressed }) => [s.openBtn, pressed && { backgroundColor: colors.voltDeep, transform: [{ scale: 0.96 }] }]}
            >
              <Text style={{ fontSize: 16, fontWeight: '800', color: '#111111' }}>{busy === d.id ? '여는 중...' : '상자 열기'}</Text>
            </Pressable>
          )}
        </View>
      ))}

      {/* 기어 교환권 */}
      {claims.length > 0 && (
        <>
          <Row style={s.secWrap}>
            <Text style={s.secTitle}>기어 교환권</Text>
          </Row>
          <View style={s.card}>
            {claims.map((g, i) => (
              <View key={g.id}>
                {i > 0 && <View style={s.div} />}
                <Row style={{ paddingVertical: 10, justifyContent: 'space-between' }}>
                  <View>
                    <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>{g.item}</Text>
                    <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>{g.milestone}회 달성 보상</Text>
                  </View>
                  <View style={[s.claimChip, g.status !== 'claimable' && { backgroundColor: '#F5F5F5' }]}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: g.status === 'claimable' ? '#3D6B1F' : paper.dim }}>
                      {g.status === 'claimable' ? '수령 가능 · 배송 연동 준비 중' : g.status}
                    </Text>
                  </View>
                </Row>
              </View>
            ))}
          </View>
        </>
      )}

      {/* 오픈 히스토리 — muted with explicit dim ink (opacity paint retired) */}
      {opened.length > 0 && (
        <>
          <Row style={s.secWrap}>
            <Text style={s.secTitle}>지난 드랍</Text>
          </Row>
          {opened.map((d) => (
            <View key={d.id} style={[s.card, { marginBottom: 8 }]}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 14.5, fontWeight: '700', color: paper.dim }}>
                  {/* 포인트가 실제로 들어 있을 때만 괄호를 연다 — '+0포인트'는 없는 적립을 그리는 것 */}
                  {d.kind === 'pick'
                    ? `픽 드랍 — ${d.pickChoice === 'miles' ? '5,000포인트' : d.pickChoice === 'boost' ? '부스트' : '기어'} 선택`
                    : typeof d.contents.miles === 'number' && d.contents.miles > 0
                      ? `보급 드랍 (+${d.contents.miles.toLocaleString()}포인트)`
                      : '보급 드랍'}
                </Text>
                <Text style={{ fontSize: 14, color: paper.dim }}>{d.when}</Text>
              </Row>
            </View>
          ))}
        </>
      )}

      <Pressable onPress={() => router.push('/leaderboard')} style={s.rankLink}>
        <Text style={{ fontSize: 14.5, fontWeight: '800', color: colors.coralText }}>주간 랭킹에서 보너스 노려보기 ›</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  // paper back button grammar — 40×40 square, canvas, 1px coral
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  milesCard: { backgroundColor: paper.ink, padding: 18, marginTop: 16 },
  // [B①] 잔액과 그 내역을 가르는 선 — 다크 면 위의 헤어라인. paper.text(#333333)를 면 색으로 쓴다:
  // 이 카드에서 유일하게 '잉크보다 한 단 밝은' 값이고, 새 헥스를 만들지 않는다.
  milesLedger: { marginTop: 10, borderTopWidth: 1, borderTopColor: paper.text, paddingTop: 6 },
  mileRow: { justifyContent: 'space-between', alignItems: 'baseline', paddingVertical: 5 },
  // §3b section header — full-bleed coral rule via negative gutter margins + 20/800 ink
  secWrap: {
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter,
    borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10, marginTop: 20, marginBottom: 8,
  },
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
  emptyBox: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 20 },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  // unopened drop — dark ceremony card, volt edge (artifact vocabulary survives)
  dropCard: { backgroundColor: paper.ink, padding: 16, marginBottom: 10, borderWidth: 1.5, borderColor: colors.volt },
  openBtn: { backgroundColor: colors.volt, alignItems: 'center', paddingVertical: 15, marginTop: 12 },
  pickBtn: { flex: 1, backgroundColor: colors.volt, alignItems: 'center', paddingVertical: 15 },
  card: { backgroundColor: paper.canvas, padding: 14, borderWidth: 1, borderColor: '#EEEEEE' },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  claimChip: { backgroundColor: '#E8F3D2', borderRadius: 0, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  rankLink: { alignItems: 'center', marginTop: 18, padding: 10 },
});
