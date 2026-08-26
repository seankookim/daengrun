// 카드 연결 패널 — 랩 ① 「약속 한 줄」, Sean 픽 (2026-08-26). 두 자리에서 쓰인다:
//   · owner/request.tsx의 게이트 모달 — 첫 예약, 요청 보내기 직전 (그의 배치 판정)
//   · owner/card-link.tsx 라우트 — 설정 › 결제 관리와 미납 잠금에서 들어오는 문
//
// ═══ BABY WORK (DESIGN.md §7a-bis) — 이 화면이 그 법의 워크드 예제다 ═══
// 헤드라인 하나 · 받침 문장 하나 · 문단 0 · dim은 CTA 아래 동의 한 줄뿐. 카드 브랜드 칩도,
// 안심 문장도 없다 — r3 랩이 다른 법을 다 지키고 이 법에서 죽었다.
//
// ═══ 동의는 길이가 아니라 독점이 만든다 ═══
// 가격 비공개 아래에서 이 화면은 보호자가 실측 기반 청구에 동의하는 유일한 자리다
// (card-registration-placement.md 이유 ③). 화면이 이 한 가지만 말하므로 스치듯 지나갈 수 없다.
//
// ═══ 왜 금액이 없나 ═══
// 러닝이 끝나야 정해진다. 미리 보여줄 수 있는 숫자는 존재하지 않고, 지어내지 않는다.
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Text, View } from 'react-native';
import { BillingAuthSheet } from './billing-auth-sheet';
import { PaperBtn } from './paper-btn';
import { Pressable } from 'react-native';
import { issueBillingKey, prepareBillingAuth } from '../lib/api';
import { useDisplayFont } from '../lib/displayFont';
import { useNumFont } from '../lib/fonts';
import { TOSS_CLIENT_KEY } from '../lib/toss';
import { paper } from '../theme';

export interface CardLinkPanelProps {
  /** booking = 요청 보내기 직전의 게이트 (스킵 있음) · settings = 결제 관리 · arrears = 미납 잠금 */
  context: 'booking' | 'settings' | 'arrears';
  /** arrears일 때만 — 실패한 청구의 실측 합계. null이면 금액 줄을 그리지 않는다 (0을 그리지 않는다). */
  dueAmount?: number | null;
  onLinked: (card: { brand: string | null; last4: string | null }) => void;
  /** booking 컨텍스트에서만 렌더된다 — F.1 판정 「allow them to book …」의 조용한 우회로. */
  onSkip?: () => void;
}

export function CardLinkPanel({ context, dueAmount, onLinked, onSkip }: CardLinkPanelProps) {
  const df = useDisplayFont();
  const nf = useNumFont();
  const [busy, setBusy] = useState(false);
  const [customerKey, setCustomerKey] = useState<string | null>(null);
  const [sheet, setSheet] = useState(false);
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);

  const arrears = context === 'arrears';

  const start = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    try {
      // prepare는 매번 새로 읽는다 — customer key는 불변이지만, 캐시했다가 계정 전환/삭제 뒤
      // 낡은 키로 토스 세션을 여는 것보다 요청 하나가 싸다.
      const ck = await prepareBillingAuth();
      if (!alive.current) return;
      setCustomerKey(ck);
      setSheet(true);
    } catch (e) {
      if (alive.current) Alert.alert('카드 연결 실패', (e as Error).message);
    } finally {
      if (alive.current) setBusy(false);
    }
  }, [busy]);

  const onAuthKey = useCallback(async (authKey: string) => {
    setSheet(false);
    setBusy(true);
    try {
      const card = await issueBillingKey(authKey);
      if (alive.current) onLinked(card);
    } catch (e) {
      // 토스/카드사의 문장 그대로 (서버 handler가 verbatim으로 넘긴다) — 우리가 지어낸 일반
      // 문구는 보호자가 자기 카드사에 확인할 단서를 지운다.
      if (alive.current) Alert.alert('카드 등록이 거절됐어요', (e as Error).message);
    } finally {
      if (alive.current) setBusy(false);
    }
  }, [onLinked]);

  // 키가 없으면 버튼을 그리지 않는다 — 열리지 않는 웹뷰를 여는 버튼은 죽은 버튼이다 (정직 법).
  // 결제 오픈(PG 계약)과 함께 키가 들어오면 이 분기는 스스로 사라진다.
  const ready = TOSS_CLIENT_KEY != null;

  return (
    <View style={{ flex: 1 }}>
      {arrears ? (
        <>
          <View style={{
            alignSelf: 'flex-start', borderWidth: 1.5, borderColor: paper.critical,
            paddingVertical: 5, paddingHorizontal: 10, marginBottom: 16,
          }}>
            <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical }}>새 예약 잠김</Text>
          </View>
          <Text style={[{ fontSize: 30, lineHeight: 38, color: '#221E3D' }, df]}>밀린 결제가{'\n'}있어요</Text>
          {dueAmount != null && (
            // Oswald 숫자 — 명시 lineHeight ≥1.2× (BUG A)
            <Text style={[{ fontSize: 44, lineHeight: 55, fontWeight: '600', color: paper.ink, marginTop: 14 }, nf]}>
              {dueAmount.toLocaleString()}<Text style={{ fontSize: 24, fontWeight: '700' }}> 원</Text>
            </Text>
          )}
        </>
      ) : (
        <>
          <Text style={[{ fontSize: 30, lineHeight: 38, color: '#221E3D' }, df]}>지금은{'\n'}결제되지{'\n'}않아요</Text>
          <Text style={{ fontSize: 19, lineHeight: 28, fontWeight: '500', color: paper.ink, marginTop: 16 }}>
            러닝이 끝나면 <Text style={{ fontWeight: '700' }}>뛴 만큼만</Text> 자동 결제돼요
          </Text>
        </>
      )}

      <View style={{ flex: 1, minHeight: 16 }} />

      {ready ? (
        <>
          <PaperBtn
            label={arrears ? '카드 연결하고 결제하기' : '카드 연결하기'}
            busyLabel="여는 중..."
            busy={busy}
            onPress={start}
          />
          <Text style={{ fontSize: 15, lineHeight: 21, color: paper.dim, textAlign: 'center', marginTop: 10 }}>
            {arrears ? '결제되면 바로 예약할 수 있어요' : '연결하면 이 방식에 동의하는 거예요'}
          </Text>
        </>
      ) : (
        // 키 부재 = 아직 결제사가 아니다. 그 사실을 말하고 멈춘다 — payments.tsx의 같은 문법.
        <Text style={{ fontSize: 15, lineHeight: 22, color: paper.dim, textAlign: 'center' }}>
          카드 연결은 결제 오픈과 함께 열려요
        </Text>
      )}

      {context === 'booking' && onSkip && (
        <Pressable onPress={onSkip} hitSlop={8} accessibilityRole="button" accessibilityLabel="카드 없이 보내기"
          style={{ alignSelf: 'center', marginTop: 14, paddingVertical: 4 }}>
          <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, textDecorationLine: 'underline' }}>
            카드 없이 보내기
          </Text>
        </Pressable>
      )}

      <BillingAuthSheet
        visible={sheet}
        customerKey={customerKey}
        onAuthKey={onAuthKey}
        onFail={(m) => { setSheet(false); Alert.alert('카드 연결 실패', m); }}
        onDismiss={() => setSheet(false)}
      />
    </View>
  );
}
