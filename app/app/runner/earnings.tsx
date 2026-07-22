import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { ledger, ledgerNet, payoutInfo } from '../../src/store';
import { colors } from '../../src/theme';

// 수익 — weekly settlement, bank account, per-run ledger.
// Schema seed: ledger_items, payouts, bank_accounts tables.

const FOREST = '#132117';

export default function Earnings() {
  const weekSum = ledger.reduce((sum, l) => sum + ledgerNet(l), 0);
  const tax = Math.round(weekSum * payoutInfo.taxRate);

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 60, paddingBottom: 30 }}>
        <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>수익</Text>

        {/* settlement card */}
        <View style={s.settleCard}>
          <Text style={{ fontSize: 11, color: '#b8c4ae', letterSpacing: 1.5 }}>이번 주 정산 예정</Text>
          <Text style={{ fontSize: 38, fontWeight: '900', color: colors.volt, marginTop: 6 }}>
            {weekSum.toLocaleString()}원
          </Text>
          <Row style={{ justifyContent: 'space-between', marginTop: 10 }}>
            <Text style={{ fontSize: 11.5, color: '#b8c4ae' }}>다음 정산일 {payoutInfo.nextDate}</Text>
            <Text style={{ fontSize: 11.5, color: '#b8c4ae' }}>원천징수 3.3% 약 −{tax.toLocaleString()}원</Text>
          </Row>
          <Pressable style={s.settleBtn} onPress={() => Alert.alert('빠른 정산', '수수료 500원으로 즉시 정산 (목업)')}>
            <Text style={{ fontSize: 12.5, fontWeight: '900', color: FOREST }}>⚡ 빠른 정산 신청</Text>
          </Pressable>
        </View>

        {/* bank account */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>정산 계좌</Text>
              <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>
                {payoutInfo.bank} ····{payoutInfo.last4} · {payoutInfo.holder}
              </Text>
            </View>
            <Pressable style={s.changeChip} onPress={() => Alert.alert('계좌 변경', '본인 명의 계좌만 등록 가능 (목업)')}>
              <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d453d' }}>변경</Text>
            </Pressable>
          </Row>
        </View>

        {/* ledger */}
        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 10 }}>러닝별 내역</Text>
        {ledger.map((l) => (
          <View key={l.id} style={[s.card, { marginBottom: 8 }]}>
            <Row style={{ justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>
                {l.date} · {l.dogName} {l.km}km
              </Text>
              <Text style={{ fontSize: 16, fontWeight: '900', color: '#5a7a3c' }}>
                +{ledgerNet(l).toLocaleString()}원
              </Text>
            </Row>
            <Row style={{ gap: 10, marginTop: 7, flexWrap: 'wrap' }}>
              <Bd label="기본" v={l.base} />
              <Bd label="거리" v={l.distancePay} />
              {l.addonPay > 0 && <Bd label="옵션" v={l.addonPay} />}
              {l.tip > 0 && <Bd label="팁" v={l.tip} accent />}
              <Bd label="수수료" v={-l.fee} coral />
            </Row>
          </View>
        ))}

        <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 12, lineHeight: 15 }}>
          정산은 매주 수요일 · 사업소득 3.3% 원천징수 후 지급{'\n'}연말 소득 자료는 마이 → 세금 서류에서 (준비 중)
        </Text>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function Bd({ label, v, coral, accent }: { label: string; v: number; coral?: boolean; accent?: boolean }) {
  return (
    <Text style={{ fontSize: 11, color: coral ? '#d84a2f' : accent ? '#5a7a3c' : colors.dim }}>
      {label} {v >= 0 ? '' : '−'}{Math.abs(v).toLocaleString()}
    </Text>
  );
}

const s = StyleSheet.create({
  settleCard: { backgroundColor: FOREST, borderRadius: 20, padding: 18, marginTop: 16 },
  settleBtn: { backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11, marginTop: 14 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 12 },
  changeChip: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12, alignSelf: 'center' },
});
