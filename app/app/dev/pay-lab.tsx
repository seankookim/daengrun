// ═══ DEV 전용: 결제 페이즈 랩 — /owner/pay의 전 상태 스위치 + 청구 예외 상태 ═══
// 슬라이스당 얇은 디버그 UI 독트린 (club-lab.tsx 선례) — 프로덕션 UI 아님.
// 왜 별도 라우트인가 (웨이브 2 리뷰 L2): 프로덕션 pay.tsx에 __DEV__ 분기를 두면 결제 화면 안에
// '진짜가 아닌 상태'를 만드는 코드가 상주하게 된다. 뷰만 import 해서 여기서 흔든다.
// 원칙: ① __DEV__ 빌드에서만 렌더 ② 서버 호출 0 (CTA는 Alert로 끝) ③ 픽스처는 픽스처라고 말한다.
//
// [charge slice 2026-08-13] 두 번째 탭 '청구 예외' 추가. post-pay 모델의 거절·카드 재연결·
// 계정 잠금 상태는 실제로는 카드가 실패해야만 볼 수 있다 — 리뷰 가능한 자리가 여기뿐이다.
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Redirect } from 'expo-router';
import { PayScreen, PayView } from '../owner/pay';
import { ChargeBanner, PaymentRow } from '../../src/components/charge-states';
import { BookingCharge, PaymentRecord } from '../../src/lib/api';
import { paper } from '../../src/theme';

export default function PayLabScreen() {
  if (!__DEV__) return <Redirect href="/" />;
  return <PayLab />;
}

// M1의 9페이즈 + 통신 실패 한 칸 (error는 PayPhase가 아니라 화면 상태다)
// [codex #11/#12 · 2026-08-28] +5: 예약 상태만으로는 도달할 수 없고 payments 행을 함께 읽어야
// 나오는 칸들. 실제로 보려면 카드가 실패해야 하므로 — 청구 예외 탭과 같은 이유로 — 검수 가능한
// 자리는 여기뿐이다.
const SCREENS: PayScreen[] = [
  'loading', 'not_found', 'mock_pending', 'authorizing', 'authorized',
  'disputed', 'failed', 'cancelled', 'refund_pending',
  'not_charged', 'paid', 'collect_pending', 'collect_failed', 'charge_unknown', 'error',
];

// 픽스처 — 서버 행 모양 그대로 (addons는 {key,price}, label 없음)
// [D2 2026-08-13] baseFare 9,900 → 7,900: 9,900은 이제 러너 정산 기준이고 보호자 기본요금이
// 아니다 (theme.ts pricing.ownerBaseFare / runnerCompBase 분리). 합계도 함께 내려간다.
const FIXTURE: BookingCharge = {
  bookingId: 'fixture-0000',
  status: 'payment_hold',
  baseFare: 7900,
  distanceFare: 15000,
  addonFare: 5000,
  totalPrice: 27900,
  km: 5,
  addons: [{ key: 'river', price: 3000 }, { key: 'snack', price: 2000 }],
  scheduledAt: new Date(Date.now() + 3 * 3_600_000).toISOString(),
  dogName: '초코(픽스처)',
  routeName: '서울숲 루프(픽스처)',
};

// payments 행 픽스처 — 6종 status 전수 + raw에서 꺼내는 세 조각(재연결·거절 사유·검토 표식).
const day = (d: number) => new Date(Date.now() - d * 86400_000).toISOString();
const payFixture = (over: Partial<PaymentRecord>): PaymentRecord => ({
  bookingId: 'fixture-0000', orderId: `dr_fixture_${Math.random().toString(36).slice(2, 8)}`,
  amount: 22900, status: 'confirmed', refundedAmount: 0, createdAt: day(1),
  needsCardRelink: false, underReview: false, lastError: null, dogName: '초코(픽스처)', scheduledAt: day(1),
  ...over,
});
const PAY_ROWS: PaymentRecord[] = [
  payFixture({ status: 'confirmed', amount: 22900 }),
  payFixture({ status: 'pending', amount: 19900, createdAt: day(0), scheduledAt: day(0) }),
  payFixture({ status: 'failed', amount: 25900, createdAt: day(2), scheduledAt: day(2), lastError: 'REJECT_CARD_COMPANY · 카드사 승인 거절 (픽스처)' }),
  payFixture({ status: 'failed', amount: 13900, createdAt: day(3), scheduledAt: day(3), needsCardRelink: true, lastError: 'INVALID_BILL_KEY_REQUEST (픽스처)' }),
  payFixture({ status: 'waived', amount: 0, createdAt: day(5), scheduledAt: day(5) }),
  // 검토 중인 0원 — 확정된 무청구와 **같은 말이면 안 된다**. 0084 §B의 raw.review 표식이
  // 없으면 화면이 열린 사건을 종결된 것처럼 말한다.
  payFixture({ status: 'waived', amount: 0, underReview: true, createdAt: day(1) }),
  payFixture({ status: 'partial_canceled', amount: 27900, refundedAmount: 9000, createdAt: day(8), scheduledAt: day(8) }),
  payFixture({ status: 'canceled', amount: 15900, createdAt: day(11), scheduledAt: day(11) }),
];

type LabTab = 'pay' | 'charge';

function PayLab() {
  const [tab, setTab] = useState<LabTab>('pay');
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
          <Pressable onPress={() => setTab('pay')} style={[s.chip, tab === 'pay' && s.chipOn]}>
            <Text style={[s.chipTxt, tab === 'pay' && s.chipTxtOn]}>결제 페이즈</Text>
          </Pressable>
          <Pressable onPress={() => setTab('charge')} style={[s.chip, tab === 'charge' && s.chipOn]}>
            <Text style={[s.chipTxt, tab === 'charge' && s.chipTxtOn]}>청구 예외</Text>
          </Pressable>
        </ScrollView>
        {tab === 'pay' && (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6, paddingRight: 12, marginTop: 6 }}>
            {SCREENS.map((p) => (
              <Pressable key={p} onPress={() => setScreen(p)} style={[s.chip, screen === p && s.chipOn]}>
                <Text style={[s.chipTxt, screen === p && s.chipTxtOn]}>{p}</Text>
              </Pressable>
            ))}
            <Pressable onPress={() => setBusy((v) => !v)} style={[s.chip, busy && s.chipOn]}>
              <Text style={[s.chipTxt, busy && s.chipTxtOn]}>busy: {busy ? 'on' : 'off'}</Text>
            </Pressable>
          </ScrollView>
        )}
      </View>
      <View style={{ flex: 1 }}>
        {tab === 'pay' ? (
          <PayView
            screen={screen}
            charge={charge}
            busy={busy}
            failReason={failReason}
            /* [O-5 §E.5.1] onConfirm/onRetry는 PayView에서 사라졌다 — 결제 확정 경로가
               삭제됐고(payment_ok 없음), 이 화면은 읽기 전용이다. 랩은 남은 두 액션만 흔든다. */
            onReload={() => stub('다시 불러오기')}
            onBack={() => stub('뒤로')}
          />
        ) : (
          <ChargeLab busy={busy} onBusy={() => setBusy((v) => !v)} stub={stub} />
        )}
      </View>
    </View>
  );
}

// 청구 예외 — 설정 › 결제 관리와 예약 상세가 쓰는 바로 그 컴포넌트를 픽스처로 흔든다.
// (여기서 복제본을 만들면 실화면과 카피가 갈라진다 — 랩의 존재 이유가 사라진다)
function ChargeLab({ busy, onBusy, stub }: { busy: boolean; onBusy: () => void; stub: (what: string) => void }) {
  return (
    <ScrollView style={{ flex: 1, backgroundColor: paper.canvas }} contentContainerStyle={{ paddingBottom: 40 }}>
      <Text style={s.labNote}>아래는 전부 픽스처예요 — 서버를 부르지 않고, 실제 청구도 없어요</Text>

      <Text style={s.labHead}>배너 · debt (계정 잠금)</Text>
      <ChargeBanner
        kind="debt"
        cta="다시 시도"
        busyCta="다시 청구하는 중..."
        busy={busy}
        onPress={() => stub('다시 시도')}
      />
      <Pressable onPress={onBusy} style={s.labBtn}>
        <Text style={s.labBtnTxt}>busy 토글: {busy ? 'on' : 'off'} (라벨 스왑 확인)</Text>
      </Pressable>

      <Text style={s.labHead}>배너 · debt + 재시도 후에도 미해결</Text>
      <ChargeBanner kind="debt" detail="방금 다시 시도했지만 아직 처리되지 않았어요" />

      <Text style={s.labHead}>배너 · relink (빌링키 만료·해지)</Text>
      <ChargeBanner kind="relink" cta="문의하기" onPress={() => stub('문의하기')} />

      <Text style={s.labHead}>배너 · declined (이번 청구 거절)</Text>
      <ChargeBanner
        kind="declined"
        detail="REJECT_CARD_COMPANY · 카드사 승인 거절 (픽스처)"
        cta="다시 시도"
        busyCta="다시 청구하는 중..."
        busy={busy}
        onPress={() => stub('다시 시도')}
      />

      <Text style={s.labHead}>결제 내역 행 · status 6종</Text>
      <View style={{ paddingHorizontal: 16 }}>
        {PAY_ROWS.map((p) => <PaymentRow key={p.orderId} p={p} />)}
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  bar: { paddingTop: 54, paddingBottom: 10, paddingLeft: 12, backgroundColor: paper.canvasSoft, borderBottomWidth: 1, borderColor: paper.line },
  barTitle: { fontSize: 15, fontWeight: '800', color: paper.dim, marginBottom: 8, letterSpacing: 0.6 },
  chip: { paddingVertical: 7, paddingHorizontal: 11, borderWidth: 1, borderColor: paper.line, backgroundColor: paper.canvas },
  chipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  chipTxt: { fontSize: 15, fontWeight: '700', color: paper.text },
  chipTxtOn: { color: paper.canvas },
  labNote: { fontSize: 15, fontWeight: '700', color: paper.dim, paddingHorizontal: 16, paddingTop: 14 },
  labHead: { fontSize: 15, fontWeight: '800', color: paper.ink, paddingHorizontal: 16, marginTop: 22, marginBottom: 8 },
  labBtn: { alignSelf: 'flex-start', marginLeft: 16, marginTop: 8, minHeight: 44, justifyContent: 'center' },
  labBtnTxt: { fontSize: 15, fontWeight: '800', color: paper.text, textDecorationLine: 'underline' },
});
