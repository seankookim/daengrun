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

// 🔴 정확 파싱 — `startsWith` 는 경계가 아니다 (codex #3). `https://daengrun.invalid/billing-ok`
//    로 시작하는 URL 은 `…/billing-ok.evil.com/…` 도 포함하고, 무엇보다 WebView 의 기본 정책은
//    모든 http(s) 이동을 허용하므로 **이 콜백 URL 자체가 출처 경계가 아니다**. 프로토콜·호스트·
//    경로를 각각 비교하고, 그 위에 nonce 를 얹는다.
const CB_HOST = 'daengrun.invalid';
function callbackKind(raw: string): 'ok' | 'fail' | null {
  try {
    const u = new URL(raw);
    if (u.protocol !== 'https:' || u.hostname !== CB_HOST) return null;
    if (u.pathname === '/billing-ok') return 'ok';
    if (u.pathname === '/billing-fail') return 'fail';
    return null;
  } catch { return null; }
}

// 토스 흐름이 실제로 도는 호스트만 허용한다. 나머지 이동은 막는다 — 카드 입력 페이지 안에서
// 임의의 사이트로 나갈 이유가 없고, 나갈 수 있으면 그 페이지가 콜백을 위조할 무대가 된다.
const ALLOWED_HOSTS = /(^|\.)tosspayments\.com$|(^|\.)toss\.im$/;

export function BillingAuthSheet({ visible, customerKey, nonce, onAuthKey, onFail, onDismiss }: BillingAuthProps) {
  // 한 세션에 한 결과 — 토스 페이지가 리다이렉트를 두 번 밀어도 (뒤로가기/재시도 조합에서
  // 실제로 일어난다) authKey 콜백은 한 번만 나간다. 두 번 나가면 서버 issue가 두 번 뜨고,
  // 두 번째는 이미 쓰인 authKey로 402가 떠서 성공 직후에 에러 얼럿이 겹친다.
  const settled = useRef(false);

  const intercept = useCallback((nav: WebViewNavigation): boolean => {
    const url = nav.url ?? '';
    const kind = callbackKind(url);
    if (kind === 'ok') {
      if (!settled.current) {
        settled.current = true;
        const q = new URL(url).searchParams;
        // nonce 는 서버가 이 시도를 위해 발급한 값이다. 없거나 다르면 이 콜백은 우리가 연 흐름의
        // 것이 아니다 — 서버도 `issue` 에서 같은 값을 요구하므로 이건 두 번째 벨트다.
        if (q.get('nonce') !== nonce) { onFail('카드 등록을 확인하지 못했어요'); return false; }
        const authKey = q.get('authKey');
        if (authKey) onAuthKey(authKey, q.get('customerKey'));
        else onFail('토스가 인증 키를 돌려주지 않았어요');
      }
      return false;
    }
    if (kind === 'fail') {
      if (!settled.current) {
        settled.current = true;
        const q = new URL(url).searchParams;
        // ⚠ 위조된 실패 URL 은 **공격자가 쓴 문장을 우리 네이티브 얼럿에** 띄울 수 있다
        //    (codex #3). nonce 가 맞을 때만 토스의 문장을 그대로 쓰고, 아니면 우리 문장을 쓴다.
        onFail(q.get('nonce') === nonce
          ? (q.get('message') ?? '카드 등록이 취소됐어요')
          : '카드 등록이 취소됐어요');
      }
      return false;
    }
    // 콜백이 아닌 이동: 토스 도메인 안에서만 허용한다. about:blank 등 스킴 없는 초기 로드는
    // URL 파싱에 실패하므로 통과시킨다 (첫 프레임이 여기로 온다).
    try {
      const u = new URL(url);
      if (u.protocol !== 'https:' && u.protocol !== 'http:') return true;
      return ALLOWED_HOSTS.test(u.hostname);
    } catch { return true; }
  }, [onAuthKey, onFail, nonce]);

  if (!visible || customerKey == null || nonce == null || TOSS_CLIENT_KEY == null) return null;

  // V1 SDK — requestBillingAuth는 위젯 v2 RN SDK에 없다 (그 SDK는 결제위젯 전용). 페이지는
  // 로드 즉시 토스의 카드 입력 UI로 전환되므로 이 HTML 자체는 한 프레임도 보이지 않는다.
  const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://js.tosspayments.com/v1/payment"></script></head>
<body><script>
  TossPayments(${JSON.stringify(TOSS_CLIENT_KEY)}).requestBillingAuth('카드', {
    customerKey: ${JSON.stringify(customerKey)},
    successUrl: ${JSON.stringify(`${SUCCESS_URL}?nonce=${encodeURIComponent(nonce)}`)},
    failUrl: ${JSON.stringify(`${FAIL_URL}?nonce=${encodeURIComponent(nonce)}`)},
  }).catch(function (e) {
    location.href = ${JSON.stringify(`${FAIL_URL}?nonce=${encodeURIComponent(nonce)}`)} + '&message=' + encodeURIComponent(e.message || '카드 등록을 열지 못했어요');
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
