// 빌링 인증 시트 — 지연 로딩 래퍼. 실제 WebView는 ./billing-auth-sheet-impl 안에 있다.
//
// toss-sheet.tsx와 같은 이유, 같은 모양 (2026-08-13 launch-crash fix의 워크드 예제): impl은
// react-native-webview(네이티브 모듈)를 부르고, Expo Router는 모든 라우트 모듈을 앱 시작 시
// 평가하므로 모듈 스코프 import는 결제 화면을 한 번도 안 연 바이너리를 홈에서 죽인다.
// lazy()는 첫 RENDER에 import한다 — 그래서 아래 early return이 lazy 엘리먼트보다 위에 있는
// 순서가 하중을 진다. 순서를 바꾸면 원래 버그가 그대로 돌아온다.
import { lazy, Suspense } from 'react';
import { TOSS_CLIENT_KEY } from '../lib/toss';

export interface BillingAuthProps {
  visible: boolean;
  /** register-billing-key `prepare`가 돌려준 값 — 위젯이 카드 입력 세션을 이 키에 묶는다. */
  customerKey: string | null;
  /** 같은 `prepare`가 발급한 1회용 시도 토큰. 콜백 URL 양쪽에 실리고 `issue`가 되돌려받는다 —
   *  WebView 안의 페이지가 콜백을 위조해도 이 값을 모르면 발급까지 가지 못한다 (codex #3). */
  nonce: string | null;
  /** Toss가 authKey를 돌려줬다 — 아직 등록이 끝난 게 아니다. 서버 issue가 진실을 만든다. */
  onAuthKey: (authKey: string, customerKeyEcho: string | null) => void;
  /** Toss가 실패를 말했다 (사용자 취소 포함). message는 Toss의 문장 그대로. */
  onFail: (message: string) => void;
  /** 사용자가 시트를 닫았다 (시도 없음). */
  onDismiss: () => void;
}

const Impl = lazy(async () => ({ default: (await import('./billing-auth-sheet-impl')).BillingAuthSheet }));

export function BillingAuthSheet(props: BillingAuthProps) {
  if (!props.visible || props.customerKey == null || props.nonce == null || TOSS_CLIENT_KEY == null) return null;
  return <Suspense fallback={null}><Impl {...props} /></Suspense>;
}
