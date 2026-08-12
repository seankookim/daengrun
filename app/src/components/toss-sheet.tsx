// 토스페이먼츠 결제 시트 — the widget surface behind pay.tsx's phase machine (plan §3).
//
// SPIKE VERDICT (A3, 2026-08-12): the SDK path is what this file drives.
// @tosspayments/widget-sdk-react-native@1.5.2 installs clean, autolinks on both platforms and
// its pod graph resolves against Expo SDK 57 / RN 0.86 (evidence in the spike report). What it
// actually IS, under the hood, is exactly the priced WebView fallback: the shipped native code
// is a vestigial template ViewManager that no JS ever touches (grep: zero requireNativeComponent
// / NativeModules references in the package). Everything real happens in react-native-webview —
// which Expo 57 already bundles at 13.16.1, inside the SDK's peer range >=13.3.0 <14.0.0.
// So the fallback's one sharp edge (카드사 앱 스킴 리다이렉트) is handled inside the SDK by
// ConvertUrl.launchApp() + onShouldStartLoadWithRequest, and our job is only to make those
// schemes reachable natively — plugins/withKoreanPayApps.js does that from one scheme list.
//
// What is NOT proven yet: a device build and one real TEST-key payment. See the report.
//
// This component is rendered ONLY when TOSS_ENABLED is true. It is imported statically so tsc
// checks it, but never mounted today — react-native-webview needs a native rebuild first.
import { useCallback, useRef, useState } from 'react';
import { Modal, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';
import {
  AgreementWidget,
  PaymentMethodWidget,
  PaymentWidgetProvider,
  usePaymentWidget,
  type Fail,
  type PaymentMethodWidgetControl,
  type Success,
} from '@tosspayments/widget-sdk-react-native';
import { PaperBtn } from './paper-btn';
import type { PaymentIntent } from '../lib/api';
import { isInstantConfirmMethod, TOSS_APP_SCHEME, TOSS_CLIENT_KEY, TOSS_VARIANT_KEY } from '../lib/toss';
import { paper } from '../theme';

const METHODS = 'payment-methods';
const AGREEMENT = 'agreement';

export interface TossSheetProps {
  visible: boolean;
  intent: PaymentIntent | null;
  /** 위젯이 승인 결과를 돌려줬다 — 아직 결제가 끝난 게 아니다. 서버 confirm이 진실을 만든다. */
  onSuccess: (s: Success) => void;
  /** 위젯이 실패/거절을 말했다 (사용자 취소 포함 — code 'USER_CANCEL'). */
  onFail: (f: Fail) => void;
  /** 사용자가 시트를 닫았다 (결제 시도 없음). */
  onDismiss: () => void;
}

export function TossSheet({ visible, intent, onSuccess, onFail, onDismiss }: TossSheetProps) {
  // 키가 없으면 위젯을 열지 않는다 — 반쯤 그려진 결제창보다 정직한 부재가 낫다.
  if (!visible || intent == null || TOSS_CLIENT_KEY == null) return null;

  return (
    <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={onDismiss}>
      <SafeAreaView style={s.root}>
        <PaymentWidgetProvider clientKey={TOSS_CLIENT_KEY} customerKey={intent.customerKey}>
          <SheetBody intent={intent} onSuccess={onSuccess} onFail={onFail} onDismiss={onDismiss} />
        </PaymentWidgetProvider>
      </SafeAreaView>
    </Modal>
  );
}

// usePaymentWidget()'s control is bound to THIS component instance (the SDK stores the active
// widget ref in hook state set by renderPaymentMethods) — renderPaymentMethods and
// requestPayment must therefore live in the same component. Do not split them.
function SheetBody({
  intent, onSuccess, onFail, onDismiss,
}: { intent: PaymentIntent } & Omit<TossSheetProps, 'visible' | 'intent'>) {
  const widget = usePaymentWidget();
  const [ready, setReady] = useState({ methods: false, agreement: false });
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const rendered = useRef(false);
  const methodControl = useRef<PaymentMethodWidgetControl | null>(null);
  const inFlight = useRef(false); // 더블탭 동기 가드 (pay.tsx의 같은 관용구)

  const onMethodsLoaded = useCallback(async () => {
    if (rendered.current) return;
    rendered.current = true;
    try {
      // 금액은 서버가 만든 intent.amount 하나 — 화면이 재계산하지 않는다.
      methodControl.current = await widget.renderPaymentMethods(
        METHODS, { value: intent.amount }, { variantKey: TOSS_VARIANT_KEY },
      );
      setReady((r) => ({ ...r, methods: true }));
    } catch (e) {
      onFail({ code: 'WIDGET_RENDER_FAILED', message: msgOf(e), orderId: intent.orderId });
    }
  }, [widget, intent, onFail]);

  const onAgreementLoaded = useCallback(async () => {
    try {
      await widget.renderAgreement(AGREEMENT, { variantKey: TOSS_VARIANT_KEY });
      setReady((r) => ({ ...r, agreement: true }));
    } catch {
      // 약관 위젯 실패는 결제를 막지 않는다 — 결제수단 위젯이 이 화면의 필수 부품이다.
      setReady((r) => ({ ...r, agreement: true }));
    }
  }, [widget]);

  const pay = useCallback(async () => {
    if (busy || inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    setNote(null);
    try {
      // [plan §2-8 방어선 1/3] 즉시승인 수단만. 가상계좌는 웹훅으로 몇 시간 뒤 확정되는데
      // payment_hold는 30분이면 만료된다 — 이 슬라이스에 웹훅 엔드포인트가 없으므로
      // WAITING_FOR_DEPOSIT은 도달 불가여야 한다. 진짜 통제는 개발자센터의 위젯 설정(variantKey)이고,
      // 최후 방어선은 서버(confirm 응답이 DONE이 아니면 자동취소)다. 여기는 그 사이의 한 겹이다.
      const selected = await methodControl.current?.getSelectedPaymentMethod();
      if (!isInstantConfirmMethod(selected?.method)) {
        setNote('이 결제수단은 아직 지원하지 않아요 — 카드나 간편결제를 선택해주세요');
        return;
      }

      const result = await widget.requestPayment({
        orderId: intent.orderId,     // 서버가 만든 값 (클라가 만들지 않는다)
        orderName: intent.orderName,
        appScheme: TOSS_APP_SCHEME,  // 카드사 앱에서 우리 앱으로 복귀
      });
      if (result?.success) onSuccess(result.success);
      else if (result?.fail) onFail(result.fail);
      // result가 비어 있으면 위젯이 아무 말도 하지 않은 것 — 사용자가 시트를 다시 시도하게 둔다.
    } catch (e) {
      onFail({ code: 'REQUEST_PAYMENT_FAILED', message: msgOf(e), orderId: intent.orderId });
    } finally {
      setBusy(false);
      inFlight.current = false;
    }
  }, [busy, widget, intent, onSuccess, onFail]);

  return (
    <View style={s.root}>
      <View style={s.headRow}>
        <Text style={s.kicker}>PAYMENT</Text>
        <Pressable onPress={onDismiss} hitSlop={10} accessibilityRole="button" accessibilityLabel="닫기">
          <Text style={s.close}>✕</Text>
        </Pressable>
      </View>
      <Text style={s.headline}>{intent.orderName}</Text>
      <Text style={s.amount}>{intent.amount.toLocaleString('ko-KR')}원</Text>

      <ScrollView style={{ flex: 1 }}>
        <PaymentMethodWidget selector={METHODS} onLoadEnd={onMethodsLoaded} />
        <AgreementWidget selector={AGREEMENT} onLoadEnd={onAgreementLoaded} />
      </ScrollView>

      {note && <Text style={s.note}>{note}</Text>}

      <View style={s.footer}>
        <PaperBtn
          label="결제하기"
          busyLabel="결제창 여는 중..."
          busy={busy}
          disabled={!ready.methods}
          onPress={pay}
        />
      </View>
    </View>
  );
}

const msgOf = (e: unknown) => (e instanceof Error ? e.message : String(e));

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  headRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 18, paddingTop: 14 },
  kicker: { fontSize: 11.5, fontWeight: '800', letterSpacing: 2.6, color: paper.faint },
  close: { fontSize: 20, lineHeight: 24, color: paper.ink },
  headline: { fontSize: 18, lineHeight: 24, fontWeight: '800', color: paper.ink, paddingHorizontal: 18, marginTop: 10 },
  amount: { fontSize: 30, lineHeight: 38, fontWeight: '900', color: paper.ink, paddingHorizontal: 18, marginTop: 2, fontVariant: ['tabular-nums'] },
  note: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical, paddingHorizontal: 18, paddingVertical: 10, backgroundColor: paper.criticalWash },
  footer: { paddingHorizontal: 18, paddingTop: 14, paddingBottom: 24, borderTopWidth: 1, borderColor: paper.line },
});
