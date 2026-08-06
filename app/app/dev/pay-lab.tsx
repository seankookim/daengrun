// ═══ DEV 전용: 결제 페이즈 랩 — /owner/pay의 전 상태 스위치 ═══
// 슬라이스당 얇은 디버그 UI 독트린 (club-lab.tsx 선례) — 프로덕션 UI 아님.
// 왜 별도 라우트인가 (웨이브 2 리뷰 L2): 프로덕션 pay.tsx에 __DEV__ 분기를 두면 결제 화면 안에
// '진짜가 아닌 상태'를 만드는 코드가 상주하게 된다. 뷰만 import 해서 여기서 흔든다.
// 원칙: ① __DEV__ 빌드에서만 렌더 ② 서버 호출 0 (CTA는 Alert로 끝) ③ 픽스처는 픽스처라고 말한다.
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Redirect } from 'expo-router';
import { PayScreen, PayView } from '../owner/pay';
import { BookingCharge } from '../../src/lib/api';
import { paper } from '../../src/theme';

export default function PayLabScreen() {
  if (!__DEV__) return <Redirect href="/" />;
  return <PayLab />;
}

// M1의 9페이즈 + 통신 실패 한 칸 (error는 PayPhase가 아니라 화면 상태다)
const SCREENS: PayScreen[] = [
  'loading', 'not_found', 'mock_pending', 'authorizing', 'authorized',
  'disputed', 'failed', 'cancelled', 'refund_pending', 'error',
];

// 픽스처 — 서버 행 모양 그대로 (addons는 {key,price}, label 없음)
const FIXTURE: BookingCharge = {
  bookingId: 'fixture-0000',
  status: 'payment_hold',
  baseFare: 9900,
  distanceFare: 15000,
  addonFare: 5000,
  totalPrice: 29900,
  km: 5,
  addons: [{ key: 'river', price: 3000 }, { key: 'snack', price: 2000 }],
  scheduledAt: new Date(Date.now() + 3 * 3_600_000).toISOString(),
  dogName: '초코(픽스처)',
  routeName: '서울숲 루프(픽스처)',
};

function PayLab() {
  const [screen, setScreen] = useState<PayScreen>('mock_pending');
  const [busy, setBusy] = useState(false);
  // 청구가 없는 상태는 실제로도 charge=null이다 (테이블 자체가 안 그려진다)
  const charge = screen === 'loading' || screen === 'not_found' || screen === 'error' ? null : FIXTURE;
  const failReason = screen === 'failed'
    ? 'transition denied: payment_hold → matching (픽스처)'
    : screen === 'error' ? 'Network request failed (픽스처)' : null;
  const stub = (what: string) => Alert.alert('페이즈 랩', `${what} — 랩에서는 서버를 부르지 않아요`);

  return (
    <View style={{ flex: 1 }}>
      <View style={s.bar}>
        <Text style={s.barTitle}>PAY PHASE LAB · 서버 호출 없음</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6, paddingRight: 12 }}>
          {SCREENS.map((p) => (
            <Pressable key={p} onPress={() => setScreen(p)} style={[s.chip, screen === p && s.chipOn]}>
              <Text style={[s.chipTxt, screen === p && s.chipTxtOn]}>{p}</Text>
            </Pressable>
          ))}
          <Pressable onPress={() => setBusy((v) => !v)} style={[s.chip, busy && s.chipOn]}>
            <Text style={[s.chipTxt, busy && s.chipTxtOn]}>busy: {busy ? 'on' : 'off'}</Text>
          </Pressable>
        </ScrollView>
      </View>
      <View style={{ flex: 1 }}>
        <PayView
          screen={screen}
          charge={charge}
          busy={busy}
          failReason={failReason}
          onConfirm={() => stub('예약 확정하기')}
          onRetry={() => stub('다시 시도')}
          onReload={() => stub('다시 불러오기')}
          onBack={() => stub('뒤로')}
        />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  bar: { paddingTop: 54, paddingBottom: 10, paddingLeft: 12, backgroundColor: paper.canvasSoft, borderBottomWidth: 1, borderColor: paper.line },
  barTitle: { fontSize: 14, fontWeight: '800', color: paper.dim, marginBottom: 8, letterSpacing: 0.6 },
  chip: { paddingVertical: 7, paddingHorizontal: 11, borderWidth: 1, borderColor: paper.line, backgroundColor: paper.canvas },
  chipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  chipTxt: { fontSize: 14, fontWeight: '700', color: paper.text },
  chipTxtOn: { color: paper.canvas },
});
