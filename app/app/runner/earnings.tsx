import { useDisplayFont } from '../../src/lib/displayFont';
import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { fetchLedger, LiveLedgerItem } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 수익 — 실원장(ledger_items)만 표시. 정산·계좌는 백엔드 후속.

const FOREST = '#0F1D13';

function nextWednesday(): string {
  const d = new Date();
  const add = (3 - d.getDay() + 7) % 7 || 7;
  const w = new Date(d.getTime() + add * 86400_000);
  return `${w.getMonth() + 1}월 ${w.getDate()}일 (수)`;
}

export default function Earnings() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [ledger, setLedger] = useState<LiveLedgerItem[]>([]);

  const load = () => fetchLedger().then(setLedger).catch((e) => console.warn('[earnings] ledger:', e?.message ?? e));
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const pendingSum = ledger.reduce((sum, l) => sum + l.net, 0);
  const tax = Math.round(pendingSum * 0.033);

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ gap: 6 }}>
          <Text style={[{ fontSize: 26, fontWeight: '900', color: FOREST }, df]}>수익</Text>
          <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }}>
            <Text style={{ fontSize: 8.5, fontWeight: '900', color: '#fff' }}>● LIVE</Text>
          </View>
        </Row>

        {/* settlement card */}
        <View style={s.settleCard}>
          <Text style={{ fontSize: 11, color: '#b8c4ae', letterSpacing: 1.5 }}>정산 예정 (원장 합계)</Text>
          <Text style={{ fontSize: 38, fontWeight: '900', color: colors.volt, marginTop: 6 }}>
            {pendingSum.toLocaleString()}원
          </Text>
          <Row style={{ justifyContent: 'space-between', marginTop: 10 }}>
            <Text style={{ fontSize: 11.5, color: '#b8c4ae' }}>다음 정산일 {nextWednesday()}</Text>
            <Text style={{ fontSize: 11.5, color: '#b8c4ae' }}>원천징수 3.3% 약 −{tax.toLocaleString()}원</Text>
          </Row>
          <Pressable style={s.settleBtn} onPress={() => Alert.alert('빠른 정산', '정산 자동화(오픈뱅킹) 연동 후 제공돼요')}>
            <Text style={{ fontSize: 12.5, fontWeight: '900', color: FOREST }}>⚡ 빠른 정산 신청</Text>
          </Pressable>
        </View>

        {/* bank account */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>정산 계좌</Text>
              <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>아직 등록된 계좌가 없어요</Text>
            </View>
            <Pressable style={s.changeChip} onPress={() => Alert.alert('계좌 등록', '본인 명의 계좌 인증과 함께 제공 예정')}>
              <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d453d' }}>등록</Text>
            </Pressable>
          </Row>
        </View>

        {/* ledger */}
        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 10 }}>러닝별 내역</Text>
        {ledger.length === 0 && (
          <View style={{ backgroundColor: '#fff', borderRadius: 16, padding: 18, alignItems: 'center', borderWidth: 1, borderColor: '#DCD6C4' }}>
            <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 20 }}>
              아직 정산 내역이 없어요{'\n'}러닝을 완료하면 여기에 기록돼요
            </Text>
          </View>
        )}
        {ledger.map((l) => (
          <View key={l.id} style={[s.card, { marginBottom: 8, marginTop: 0 }]}>
            <Row style={{ justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>
                {l.when} · {l.dogName} {l.km}km
              </Text>
              <Text style={{ fontSize: 16, fontWeight: '900', color: '#5a7a3c' }}>
                +{l.net.toLocaleString()}원
              </Text>
            </Row>
            <Row style={{ gap: 10, marginTop: 7, flexWrap: 'wrap' }}>
              <Bd label="기본" v={l.base} />
              <Bd label="거리" v={l.distancePay} />
              {l.addonPay > 0 && <Bd label="옵션" v={l.addonPay} />}
              {l.guarantee > 0 && <Bd label="잔여 보장" v={l.guarantee} accent />}
              {l.tip > 0 && <Bd label="팁" v={l.tip} accent />}
              <Bd label="수수료" v={-l.fee} coral />
            </Row>
          </View>
        ))}

        <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 12, lineHeight: 15 }}>
          정산은 매주 수요일 · 사업소득 3.3% 원천징수 후 지급
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
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#DCD6C4', marginTop: 12 },
  changeChip: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12, alignSelf: 'center' },
});
