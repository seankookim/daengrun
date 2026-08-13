// 토스 결제 시트 — 지연 로딩 래퍼. 실제 위젯은 ./toss-sheet-impl 안에 있다.
//
// WHY THIS FILE EXISTS (2026-08-13, launch-crash fix).
// `toss-sheet-impl` imports `@tosspayments/widget-sdk-react-native`, whose real work happens in
// `react-native-webview` — a NATIVE module. Expo Router registers every route module eagerly at
// startup, so a module-scope import of the impl anywhere under `app/app/` is evaluated on launch,
// before any navigation. `d1e2b9f` added the dep without a `pod install`, so the pod never reached
// `Podfile.lock`, and every binary built from this tree died on the HOME screen with
// `RNCWebViewModule` missing — having never opened a payment screen.
//
// The two guards that look like they should have prevented it, and why neither could:
//   · `TOSS_ENABLED=false` — a flag gates BEHAVIOUR. An import is evaluated at REGISTRATION.
//   · `if (!visible) return null` inside the component — same mistake one layer down. A component
//     that never renders still had its module evaluated to become importable.
//   · `pay-lab.tsx`'s `if (!__DEV__) return <Redirect/>` — a dev-only ROUTE still registers, so a
//     dev-only screen could crash a production launch. That is the widest version of this hazard.
//
// So the import has to move out of module scope, which is what `lazy()` does: the impl module is
// fetched on FIRST RENDER of the lazy element, and the early return below means that render never
// happens until a payment sheet is genuinely opening. Launch evaluates this file — which imports
// nothing native — and stops there.
//
// ⚠ The order of the guard and the lazy element is load-bearing. `React.lazy` triggers its import
// when the element is RENDERED, so the `return null` must sit ABOVE any `<Sheet …/>` in the tree.
// Wrapping the impl in a lazy component and then rendering it unconditionally with an internal
// guard re-creates the original bug exactly.
import { lazy, Suspense } from 'react';
import type { Fail, Success } from '@tosspayments/widget-sdk-react-native';
import type { PaymentIntent } from '../lib/api';
import { TOSS_CLIENT_KEY } from '../lib/toss';

// `import type` is erased at compile time — it costs nothing at runtime and keeps tsc honest
// about the widget's own Success/Fail shapes. Only VALUE imports evaluate the module.
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

const Impl = lazy(async () => ({ default: (await import('./toss-sheet-impl')).TossSheet }));

export function TossSheet(props: TossSheetProps) {
  // 위젯을 열 이유가 없으면 impl 모듈 자체를 부르지 않는다. 이 세 조건은 impl 안에도 있지만,
  // 여기 있어야 하는 이유가 다르다 — 저기서는 무엇을 그릴지의 문제고, 여기서는 네이티브 모듈을
  // 로드할지의 문제다. 같은 조건, 다른 층위.
  if (!props.visible || props.intent == null || TOSS_CLIENT_KEY == null) return null;
  // fallback이 null인 이유: 결제 시트는 모달이다. 스피너를 먼저 띄우면 사용자가 실제로 열리지
  // 않을 수도 있는 창을 기다리게 된다. 로딩은 0이 아니라는 법(정직법)은 화면에 이미 표시된
  // 상태에 대한 것이고, 아직 존재를 알리지 않은 모달에는 적용되지 않는다.
  return <Suspense fallback={null}><Impl {...props} /></Suspense>;
}
