import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
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
// No ink primary on this screen — 빠른 정산/계좌 등록 are announcement doors (backend
// pending), styled quiet so the money numeral keeps the emphasis budget.
// Behavior frozen: fetchLedger/fetchLedgerTotal, pendingSum fallback, tax calc, alerts.

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
  const load = () => Promise.all([
    fetchLedger().then(setLedger),
    fetchLedgerTotal().then(setTotal),
  ]).catch((e) => console.warn('[earnings] ledger:', e?.message ?? e));
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // 정산 예정 = 원장 전체 누적 (30행 캡 합계가 31번째 러닝부터 오히려 줄어들던 버그 — 로드 전엔 표시 리스트 합으로 폴백)
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
            {pendingSum.toLocaleString()}원
          </Text>
          {/* 절취선 + 노치 — notches punch the real canvas (stale beige #F8F6F0 fixed) */}
          <View style={{ marginVertical: 14, height: 1 }}>
            <View style={s.tickDash} />
            <View style={[s.notch, { left: -32 }]} />
            <View style={[s.notch, { right: -32 }]} />
          </View>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>다음 정산일 {nextWednesday()}</Text>
            <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>원천징수 3.3% 약 −{tax.toLocaleString()}원</Text>
          </Row>
          {/* quiet on-artifact door — the tap only announces the open-banking timeline, so it
              must not read as the screen's money CTA (emphasis budget stays on the numeral) */}
          <Pressable
            style={({ pressed }) => [s.settleBtn, pressed && { backgroundColor: '#2A2A2A' }]}
            onPress={() => Alert.alert('빠른 정산', '정산 자동화(오픈뱅킹) 연동 후 제공돼요')}
          >
            <Text style={{ fontSize: 16, fontWeight: '800', color: '#FFFFFF' }}>빠른 정산 신청</Text>
          </Pressable>
        </View>

        {/* bank account */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>정산 계좌</Text>
              <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3 }}>아직 등록된 계좌가 없어요</Text>
            </View>
            <Pressable
              style={({ pressed }) => [s.changeChip, pressed && { backgroundColor: paper.wash }]}
              onPress={() => Alert.alert('계좌 등록', '본인 명의 계좌 인증과 함께 제공 예정')}
            >
              <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>등록</Text>
            </Pressable>
          </Row>
        </View>

        {/* ledger — §3b section header: full-bleed coral rule + 20/800 ink */}
        <Row style={s.secWrap}>
          <Text style={s.secTitle}>러닝별 내역</Text>
        </Row>
        {ledger.length === 0 && (
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
          정산은 매주 수요일 · 사업소득 3.3% 원천징수 후 지급
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
  settleBtn: { borderWidth: 1, borderColor: '#555555', alignItems: 'center', paddingVertical: 12, marginTop: 14 },
  card: { backgroundColor: paper.canvas, padding: 15, borderWidth: 1, borderColor: '#EEEEEE', marginTop: 12 },
  changeChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 8, paddingHorizontal: 13, alignSelf: 'center' },
  emptyBox: { backgroundColor: paper.canvas, padding: 18, alignItems: 'center', borderWidth: 1, borderColor: '#EEEEEE' },
  // §3b section header — full-bleed coral rule via negative gutter margins
  secWrap: {
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter,
    borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10, marginTop: 20, marginBottom: 10,
  },
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
});
