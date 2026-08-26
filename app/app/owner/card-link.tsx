// 카드 연결 — 랩 ① 「약속 한 줄」의 라우트 얼굴. 패널(card-link-panel.tsx)이 그림을 다 가지고,
// 이 파일은 두 가지만 한다: 어느 컨텍스트인지 읽어서 (미납이면 실측 금액을) 패널에 넘기고,
// 연결이 끝나면 미납 청구를 실제로 다시 쏜다.
//
// ⚠ 네이티브 최상위 import 없음 — WebView는 패널 → billing-auth-sheet의 lazy() 뒤에 있다.
//   이 라우트 모듈은 앱 시작 시 평가된다 (check-route-native-imports가 지키는 그 클래스).
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Pressable, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CardLinkPanel } from '../../src/components/card-link-panel';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { fetchMyPayments, fetchUnsettledCharge, retryCollect } from '../../src/lib/api';
import { paper } from '../../src/theme';

export default function CardLink() {
  // arrears는 주장이 아니라 실측이다: 잠금 플래그 + 실패 행이 실제로 있어야 그 얼굴을 그린다.
  // 파라미터로 「미납이라 치고」 들어오는 딥링크가 가짜 빨간 화면을 만들 수 없다.
  const params = useLocalSearchParams<{ ctx?: string }>();
  const [locked, setLocked] = useState<boolean | null>(null);
  const [dueAmount, setDueAmount] = useState<number | null>(null);
  const [failedIds, setFailedIds] = useState<string[]>([]);
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);

  useEffect(() => {
    Promise.all([
      fetchUnsettledCharge().catch(() => null),
      fetchMyPayments(30).catch(() => []),
    ]).then(([lk, rows]) => {
      if (!alive.current) return;
      setLocked(lk === true);
      const failed = rows.filter((r) => r.status === 'failed');
      setFailedIds(Array.from(new Set(failed.map((r) => r.bookingId))));
      // 합계는 실패 행의 실제 amount 합 — 화면의 유일한 숫자이고, 서버 행에서 온다.
      setDueAmount(failed.length > 0 ? failed.reduce((a, r) => a + r.amount, 0) : null);
    });
  }, []);

  const arrears = locked === true && failedIds.length > 0;

  const onLinked = useCallback(async (card: { brand: string | null; last4: string | null }) => {
    if (!arrears) {
      // 카드만 연결하러 온 방문 — 이름을 말하고 돌아간다.
      Alert.alert('카드가 연결됐어요', card.last4 ? `${card.brand ?? '카드'} ···· ${card.last4}` : undefined,
        [{ text: '확인', onPress: () => router.back() }]);
      return;
    }
    // 미납 컨텍스트의 약속은 「연결하고 결제하기」다 — 연결만 하고 떠나면 그 라벨이 거짓이 된다.
    // retryCollect는 서버가 이미 만든 행을 재집행할 뿐이라 두 번 나가도 이중 청구가 안 된다
    // (api.ts:796의 자기 설명). 200이 수금 완료를 뜻하지 않으므로 결과는 행을 다시 읽어 말한다.
    let failMsg: string | null = null;
    for (const bid of failedIds) {
      try { await retryCollect(bid); } catch (e) { failMsg = (e as Error).message; break; }
    }
    const fresh = await fetchMyPayments(30).catch(() => null);
    const stillFailed = (fresh ?? []).some((r) => r.status === 'failed');
    if (!alive.current) return;
    if (failMsg) { Alert.alert('결제를 다시 시도하지 못했어요', failMsg); return; }
    if (stillFailed) {
      Alert.alert('카드는 연결됐어요', '결제는 아직 처리되지 않았어요 — 결제 관리에서 다시 시도할 수 있어요',
        [{ text: '확인', onPress: () => router.back() }]);
    } else {
      Alert.alert('결제까지 끝났어요', '이제 바로 예약할 수 있어요',
        [{ text: '확인', onPress: () => router.back() }]);
    }
  }, [arrears, failedIds]);

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#FFFFFF' }} edges={['top', 'bottom']}>
      <View style={{ height: 48, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16 }}>
        <Pressable onPress={() => router.back()} hitSlop={10} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 19, color: paper.dim }}>‹</Text>
        </Pressable>
        <Text style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: '800', color: paper.ink, marginRight: 19 }}>
          카드 연결
        </Text>
      </View>
      <View style={{ flex: 1, paddingHorizontal: 20, paddingTop: 18, paddingBottom: 16 }}>
        {/* locked를 읽는 동안 clean 얼굴을 그린다 — 로딩 스피너로 잠금 여부를 기다리게 할 만큼
            두 얼굴이 다르지 않고, 잘못 그려도 clean 쪽이 항상 참인 문장이다 (약속은 동일하다). */}
        <CardLinkPanel
          context={arrears ? 'arrears' : (params.ctx === 'booking' ? 'booking' : 'settings')}
          dueAmount={dueAmount}
          onLinked={onLinked}
          onSkip={params.ctx === 'booking' ? () => router.back() : undefined}
        />
      </View>
      <StatusBarCover />
    </SafeAreaView>
  );
}
