import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { fetchLedger, fetchLedgerTotal, LiveLedgerItem } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { colors, layout, paper } from '../../src/theme';

// 수익 — 실원장(ledger_items)만 표시. 정산·계좌는 백엔드 후속.
//
// [paper repaint 2026-08-11] forest/cream/volt chrome scrapped → paper. Kept as artifact:
// the settlement ticket (dark ink face — the other side of the owner's payment ticket),
// now sharp with Oswald money numerals + explicit lineHeight (BUG A). Fixed in passing:
// the ticket/stub notches were still painted stale beige #F8F6F0 against the white canvas
// — they punch paper.canvas now. Korean captions lose their latin letterspacing (§3).
// [honesty audit 2026-08-11 · P1 #3] 빠른 정산 신청 / 계좌 등록 buttons retired — both were dead
// doors firing "준비 중" alerts (demoting them to quiet outlines didn't change the lie). There is
// no real store for a waitlist/notify intent (no such table, and we don't invent schema), so an
// honest waitlist conversion is impossible today — removed until the feature exists. The missing
// account is stated as a non-pressable info sentence (the sanctioned settings.tsx 준비-중 pattern).
// Behavior frozen: fetchLedger/fetchLedgerTotal, pendingSum fallback, tax calc.

const MONEY_GREEN = '#3D6B1F'; // reading green for money-positive text on paper (volt stays display-only)

function nextWednesday(): string {
  const d = new Date();
  const add = (3 - d.getDay() + 7) % 7 || 7;
  const w = new Date(d.getTime() + add * 86400_000);
  return `${w.getMonth() + 1}월 ${w.getDate()}일 (수)`;
}

export default function Earnings() {
  const df = useDisplayFont(); // display font — screen title (1/screen budget)
  const nf = useNumFont();     // Oswald — settlement sum, per-run nets
  const [ledger, setLedger] = useState<LiveLedgerItem[]>([]);

  const [total, setTotal] = useState<number | null>(null);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "0원" + "아직
  // 정산 내역이 없어요" in flight and on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const load = () => {
    setLoadErr(false);
    return Promise.all([
      fetchLedger().then(setLedger),
      fetchLedgerTotal().then(setTotal),
    ]).then(() => setLoaded(true))
      .catch((e) => { console.warn('[earnings] ledger:', e?.message ?? e); setLoadErr(true); });
  };
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // 정산 예정 = 원장 전체 누적 (30행 캡 합계가 31번째 러닝부터 오히려 줄어들던 버그 — 로드 전엔 표시 리스트 합으로 폴백)
  // [honesty 2026-08-11] sumKnown 전에는 '—' — 로딩/실패를 0원으로 위장하지 않는다.
  const sumKnown = loaded || total != null;
  const pendingSum = total ?? ledger.reduce((sum, l) => sum + l.net, 0);
  const tax = Math.round(pendingSum * 0.033);

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ gap: 8 }}>
          <Text style={[{ fontSize: 30, fontWeight: '900', color: paper.ink }, df]}>수익</Text>
          {/* live-ledger chip — §3b: 16/800, tinted fill, no border, beside its datum */}
          <View style={s.liveChip}>
            <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: MONEY_GREEN }}>● LIVE</Text>
          </View>
        </Row>

        {/* settlement ticket — 결제 티켓(보호자)과 같은 오브젝트: 한 거래의 양면.
            Dark artifact face (paper.ink), sharp; volt numeral = personal money */}
        <View style={s.settleCard}>
          <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>정산 예정 (원장 합계)</Text>
          {/* Oswald settlement sum — lineHeight 54 = 1.24× (BUG A) */}
          <Text style={[{ fontSize: 43.5, lineHeight: 54, fontWeight: '900', color: colors.volt, marginTop: 6, fontVariant: ['tabular-nums'] as const }, nf]}>
            {sumKnown ? `${pendingSum.toLocaleString()}원` : '—'}
          </Text>
          {/* 절취선 + 노치 — notches punch the real canvas (stale beige #F8F6F0 fixed) */}
          <View style={{ marginVertical: 14, height: 1 }}>
            <View style={s.tickDash} />
            <View style={[s.notch, { left: -32 }]} />
            <View style={[s.notch, { right: -32 }]} />
          </View>
          <Row style={{ justifyContent: 'space-between' }}>
            {/* [2026-08-11] '다음 정산일 <수요일>'은 존재하지 않는 지급 운영의 날짜를 못박았다.
                실결제도 러너 지급 코드도 아직 없다 — 원천징수 추정치는 계산이라 남기고, 날짜는 지운다. */}
            <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>지급 일정 미정</Text>
            <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>원천징수 3.3% 약 −{sumKnown ? tax.toLocaleString() : '—'}원</Text>
          </Row>
        </View>

        {/* bank account — honest info row, not a door: registration ships with open banking */}
        <View style={s.card}>
          <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>정산 계좌</Text>
          <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3, lineHeight: 19 }}>
            아직 등록된 계좌가 없어요 — 계좌 등록은 오픈뱅킹 연동과 함께 제공돼요
          </Text>
        </View>

        {/* ledger — §3b section header: full-bleed coral rule + 20/800 ink */}
        <Row style={s.secWrap}>
          <Text style={s.secTitle}>러닝별 내역</Text>
        </Row>
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>정산 내역을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && ledger.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              아직 정산 내역이 없어요{'\n'}러닝을 완료하면 여기에 기록돼요
            </Text>
          </View>
        )}
        {/* 러닝 하나 = 티켓 스텁 하나 — 세로 절취선 왼쪽은 러닝, 오른쪽은 실수령 */}
        {ledger.map((l) => (
          <View key={l.id} style={s.stub}>
            <Row>
              <View style={{ flex: 1, paddingRight: 11 }}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: paper.dim }}>{l.when}</Text>
                <Text style={{ fontSize: 16.5, fontWeight: '800', color: paper.ink, marginTop: 2 }}>
                  {l.dogName} · {l.km}km
                </Text>
                <Row style={{ gap: 9, marginTop: 6, flexWrap: 'wrap' }}>
                  <Bd label="기본" v={l.base} />
                  <Bd label="거리" v={l.distancePay} />
                  {l.addonPay > 0 && <Bd label="옵션" v={l.addonPay} />}
                  {l.guarantee > 0 && <Bd label="잔여 보장" v={l.guarantee} accent />}
                  {l.tip > 0 && <Bd label="팁" v={l.tip} accent />}
                  <Bd label="수수료" v={-l.fee} coral />
                </Row>
              </View>
              <View style={s.stubDivWrap}>
                <View style={s.stubDash} />
                <View style={[s.stubNotch, { top: -26 }]} />
                <View style={[s.stubNotch, { bottom: -26 }]} />
              </View>
              <View style={{ width: 92, alignItems: 'center', justifyContent: 'center' }}>
                {/* Oswald net — lineHeight 21 = 1.27× (BUG A) */}
                <Text style={[{ fontSize: 16.5, lineHeight: 21, fontWeight: '900', color: MONEY_GREEN, fontVariant: ['tabular-nums'] as const }, nf]}>
                  +{l.net.toLocaleString()}
                </Text>
                <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>실수령</Text>
              </View>
            </Row>
          </View>
        ))}

        <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 12, lineHeight: 19 }}>
          {/* 같은 이유: 주기·지급을 약속하지 않는다. 세율은 제도이고, 일정은 아직 우리가 못 지킨다. */}
          기록된 금액이에요 — 지급 일정은 결제 연동 후 안내드려요 (사업소득 3.3% 원천징수 예정)
        </Text>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function Bd({ label, v, coral, accent }: { label: string; v: number; coral?: boolean; accent?: boolean }) {
  return (
    <Text style={{ fontSize: 14.5, color: coral ? colors.coralText : accent ? MONEY_GREEN : paper.dim }}>
      {label} {v >= 0 ? '' : '−'}{Math.abs(v).toLocaleString()}
    </Text>
  );
}

const s = StyleSheet.create({
  liveChip: { backgroundColor: '#E8F3D2', borderRadius: 0, paddingVertical: 2, paddingHorizontal: 8, alignSelf: 'center' },
  settleCard: { backgroundColor: paper.ink, padding: 18, marginTop: 16, overflow: 'hidden' },
  tickDash: { height: 1, borderWidth: 0.7, borderColor: '#444444', borderStyle: 'dashed' },
  notch: { position: 'absolute', top: -14, width: 28, height: 28, borderRadius: 14, backgroundColor: paper.canvas },
  stub: { backgroundColor: paper.canvas, padding: 13, borderWidth: 1, borderColor: '#EEEEEE', marginBottom: 8, overflow: 'hidden' },
  stubDivWrap: { width: 1, alignSelf: 'stretch', marginRight: 11 },
  stubDash: { flex: 1, width: 1, borderWidth: 0.7, borderColor: '#DDDDDD', borderStyle: 'dashed' },
  stubNotch: { position: 'absolute', left: -12.5, width: 26, height: 26, borderRadius: 13, backgroundColor: paper.canvas },
  card: { backgroundColor: paper.canvas, padding: 15, borderWidth: 1, borderColor: '#EEEEEE', marginTop: 12 },
  emptyBox: { backgroundColor: paper.canvas, padding: 18, alignItems: 'center', borderWidth: 1, borderColor: '#EEEEEE' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  // §3b section header — full-bleed coral rule via negative gutter margins
  secWrap: {
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter,
    borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10, marginTop: 20, marginBottom: 10,
  },
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
});
