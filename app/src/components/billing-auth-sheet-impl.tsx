// 빌링 인증 — Toss의 카드 입력 페이지를 WebView로 연다. 카드 번호는 토스 페이지에 입력되고,
// 우리 클라이언트·서버·로그 어디에도 닿지 않는다. 우리가 받는 것은 일회용 authKey 하나다.
//
// 흐름 (register-billing-key handler.ts의 ①②③ 중 ②):
//   HTML 한 장이 Toss V1 JS SDK를 로드해 requestBillingAuth('카드', {customerKey, successUrl,
//   failUrl})를 부른다 → 사용자가 토스 페이지에서 카드를 입력한다 → 토스가 successUrl로
//   ?authKey=...&customerKey=... 리다이렉트한다 → onShouldStartLoadWithRequest가 그 네비게이션을
//   가로채 authKey를 위로 넘기고 로드는 막는다 (그 URL엔 서버가 없다 — 로드되면 에러 페이지다).
//
// successUrl/failUrl이 https://daengrun.invalid인 이유: 존재하지 않는 게 보장된 예약 TLD(.invalid,
// RFC 2606)라서, 가로채기를 놓쳐도 아무 서버에도 authKey가 도착하지 않는다. 딥링크 스킴을 쓰지
// 않는 이유: WebView 안에서 커스텀 스킴 리다이렉트는 OS·버전에 따라 조용히 삼켜지는 경우가
// 있고(측정된 클래스), http(s) URL 가로채기는 전 플랫폼에서 동작이 하나다.
import { useCallback, useRef } from 'react';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { WebView, type WebViewNavigation } from 'react-native-webview';
import { TOSS_CLIENT_KEY } from '../lib/toss';
import { paper } from '../theme';
import type { BillingAuthProps } from './billing-auth-sheet';

const SUCCESS_URL = 'https://daengrun.invalid/billing-ok';
const FAIL_URL = 'https://daengrun.invalid/billing-fail';

export function BillingAuthSheet({ visible, customerKey, onAuthKey, onFail, onDismiss }: BillingAuthProps) {
  // 한 세션에 한 결과 — 토스 페이지가 리다이렉트를 두 번 밀어도 (뒤로가기/재시도 조합에서
  // 실제로 일어난다) authKey 콜백은 한 번만 나간다. 두 번 나가면 서버 issue가 두 번 뜨고,
  // 두 번째는 이미 쓰인 authKey로 402가 떠서 성공 직후에 에러 얼럿이 겹친다.
  const settled = useRef(false);

  const intercept = useCallback((nav: WebViewNavigation): boolean => {
    const url = nav.url ?? '';
    if (url.startsWith(SUCCESS_URL)) {
      if (!settled.current) {
        settled.current = true;
        const authKey = new URL(url).searchParams.get('authKey');
        if (authKey) onAuthKey(authKey);
        else onFail('토스가 인증 키를 돌려주지 않았어요');
      }
      return false;
    }
    if (url.startsWith(FAIL_URL)) {
      if (!settled.current) {
        settled.current = true;
        // Toss가 실어 보낸 문장 그대로 — 카드는 토스 페이지에 입력됐으므로 그 카드에 대한
        // 문장도 토스의 것이 정직하다. USER_CANCEL도 이 경로로 온다.
        onFail(new URL(url).searchParams.get('message') ?? '카드 등록이 취소됐어요');
      }
      return false;
    }
    return true;
  }, [onAuthKey, onFail]);

  if (!visible || customerKey == null || TOSS_CLIENT_KEY == null) return null;

  // V1 SDK — requestBillingAuth는 위젯 v2 RN SDK에 없다 (그 SDK는 결제위젯 전용). 페이지는
  // 로드 즉시 토스의 카드 입력 UI로 전환되므로 이 HTML 자체는 한 프레임도 보이지 않는다.
  const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://js.tosspayments.com/v1/payment"></script></head>
<body><script>
  TossPayments(${JSON.stringify(TOSS_CLIENT_KEY)}).requestBillingAuth('카드', {
    customerKey: ${JSON.stringify(customerKey)},
    successUrl: ${JSON.stringify(SUCCESS_URL)},
    failUrl: ${JSON.stringify(FAIL_URL)},
  }).catch(function (e) {
    location.href = ${JSON.stringify(FAIL_URL)} + '?message=' + encodeURIComponent(e.message || '카드 등록을 열지 못했어요');
  });
</script></body></html>`;

  return (
    <Modal visible transparent={false} animationType="slide" onRequestClose={onDismiss}>
      <SafeAreaView style={s.wrap} edges={['top', 'bottom']}>
        <View style={s.bar}>
          <Text style={s.barT}>카드 연결</Text>
          <Pressable onPress={onDismiss} hitSlop={10} accessibilityRole="button" accessibilityLabel="닫기">
            <Text style={s.barX}>✕</Text>
          </Pressable>
        </View>
        <WebView
          source={{ html, baseUrl: 'https://daengrun.app' }}
          onShouldStartLoadWithRequest={intercept}
          // 인증 페이지는 토스 도메인 안에서만 움직인다 — 그 밖의 이동은 위 intercept가 결정한다.
          javaScriptEnabled
          domStorageEnabled
          style={{ flex: 1 }}
        />
      </SafeAreaView>
    </Modal>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: '#FFFFFF' },
  bar: {
    height: 48, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  barT: { fontSize: 17, fontWeight: '800', color: paper.ink },
  barX: { fontSize: 19, color: paper.dim },
});
