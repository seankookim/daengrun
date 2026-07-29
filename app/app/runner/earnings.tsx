import { useDisplayFont } from '../../src/lib/displayFont';
import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { fetchLedger, fetchLedgerTotal, LiveLedgerItem } from '../../src/lib/api';
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
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ gap: 6 }}>
          <Text style={[{ fontSize: 30, fontWeight: '900', color: FOREST }, df]}>수익</Text>
          <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }}>
            <Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>● LIVE</Text>
          </View>
        </Row>

        {/* settlement ticket — 결제 티켓(보호자)과 같은 오브젝트: 한 거래의 양면 (티켓 모티프) */}
        <View style={s.settleCard}>
          <Text style={{ fontSize: 14.5, color: '#b8c4ae', letterSpacing: 1.5 }}>정산 예정 (원장 합계)</Text>
          <Text style={{ fontSize: 43.5, fontWeight: '900', color: colors.volt, marginTop: 6 }}>
            {pendingSum.toLocaleString()}원
          </Text>
          {/* 절취선 + 노치 */}
          <View style={{ marginVertical: 14, height: 1 }}>
            <View style={s.tickDash} />
            <View style={[s.notch, { left: -32 }]} />
            <View style={[s.notch, { right: -32 }]} />
          </View>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 15, color: '#b8c4ae' }}>다음 정산일 {nextWednesday()}</Text>
            <Text style={{ fontSize: 15, color: '#b8c4ae' }}>원천징수 3.3% 약 −{tax.toLocaleString()}원</Text>
          </Row>
          <Pressable style={s.settleBtn} onPress={() => Alert.alert('빠른 정산', '정산 자동화(오픈뱅킹) 연동 후 제공돼요')}>
            <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>⚡ 빠른 정산 신청</Text>
          </Pressable>
        </View>

        {/* bank account */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>정산 계좌</Text>
              <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>아직 등록된 계좌가 없어요</Text>
            </View>
            <Pressable style={s.changeChip} onPress={() => Alert.alert('계좌 등록', '본인 명의 계좌 인증과 함께 제공 예정')}>
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#3d453d' }}>등록</Text>
            </Pressable>
          </Row>
        </View>

        {/* ledger */}
        <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 10 }}>러닝별 내역</Text>
        {ledger.length === 0 && (
          <View style={{ backgroundColor: '#fff', borderRadius: 16, padding: 18, alignItems: 'center', borderWidth: 1, borderColor: '#DCD6C4' }}>
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 23 }}>
              아직 정산 내역이 없어요{'\n'}러닝을 완료하면 여기에 기록돼요
            </Text>
          </View>
        )}
        {/* 러닝 하나 = 티켓 스텁 하나 — 세로 절취선 왼쪽은 러닝, 오른쪽은 실수령 */}
        {ledger.map((l) => (
          <View key={l.id} style={s.stub}>
            <Row>
              <View style={{ flex: 1, paddingRight: 11 }}>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#5a7a3c' }}>{l.when}</Text>
                <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST, marginTop: 2 }}>
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
                <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#5a7a3c' }}>+{l.net.toLocaleString()}</Text>
                <Text style={{ fontSize: 12, color: colors.dim, marginTop: 2, letterSpacing: 1 }}>실수령</Text>
              </View>
            </Row>
          </View>
        ))}

        <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 12, lineHeight: 17 }}>
          정산은 매주 수요일 · 사업소득 3.3% 원천징수 후 지급
        </Text>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function Bd({ label, v, coral, accent }: { label: string; v: number; coral?: boolean; accent?: boolean }) {
  return (
    <Text style={{ fontSize: 14.5, color: coral ? '#d84a2f' : accent ? '#5a7a3c' : colors.dim }}>
      {label} {v >= 0 ? '' : '−'}{Math.abs(v).toLocaleString()}
    </Text>
  );
}

const s = StyleSheet.create({
  settleCard: { backgroundColor: FOREST, borderRadius: 20, padding: 18, marginTop: 16, overflow: 'hidden' },
  tickDash: { height: 1, borderWidth: 0.7, borderColor: '#3a4a3e', borderStyle: 'dashed', borderRadius: 1 },
  notch: { position: 'absolute', top: -14, width: 28, height: 28, borderRadius: 14, backgroundColor: '#F8F6F0' },
  stub: { backgroundColor: '#fff', borderRadius: 16, padding: 13, borderWidth: 1, borderColor: '#DCD6C4', marginBottom: 8, overflow: 'hidden' },
  stubDivWrap: { width: 1, alignSelf: 'stretch', marginRight: 11 },
  stubDash: { flex: 1, width: 1, borderWidth: 0.7, borderColor: '#DCD6C4', borderStyle: 'dashed', borderRadius: 1 },
  stubNotch: { position: 'absolute', left: -12.5, width: 26, height: 26, borderRadius: 13, backgroundColor: '#F8F6F0' },
  settleBtn: { backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11, marginTop: 14 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#DCD6C4', marginTop: 12 },
  changeChip: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12, alignSelf: 'center' },
});
