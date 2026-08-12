// Toss payments — client-side config for the real-money path (payments-toss-plan.md §3).
//
// THE FLAG: TOSS_ENABLED is false. Today's pay surface still runs the simulated path
// (transition-booking {action:'payment_ok'}), which is the ONLY route a booking has into
// `matching`. Nothing here may change that until confirm-payment is live and the sandbox
// matrix (plan §4-2) has passed — the plan's own correction note is explicit that flipping
// early bricks the app.
//
// Flipping the flag is NOT a JS-only change: the widget renders inside react-native-webview,
// so a native rebuild (expo prebuild + device build) must ship first.
// (typed `boolean`, not the literal `false`, so tsc keeps type-checking BOTH branches of every
// `TOSS_ENABLED ? …` — the flag must flip without waking a single new type error.)
export const TOSS_ENABLED: boolean = false;

// 결제위젯 클라이언트 키. Public by design (it identifies the merchant to the widget, it does
// not authorize anything) — the SECRET key never leaves the server (`supabase secrets`).
// Absent key ⇒ the sheet refuses to open rather than rendering a broken widget.
export const TOSS_CLIENT_KEY = process.env.EXPO_PUBLIC_TOSS_CLIENT_KEY ?? null;

// 결제수단 제한 (plan §2-8: 카드 + 간편결제 only, NO 가상계좌).
// ⚠ V1 결제위젯 does NOT take a method list as a client parameter — the enabled methods are
// configured per variantKey in the Toss 개발자센터 (결제위젯 관리). This constant only selects
// WHICH configured variant renders; the restriction itself is a dashboard setting and must be
// verified there. Client-side guard (assertInstantConfirmMethod below) and the server's
// non-DONE → auto-cancel branch are the defenses in depth, not the primary control.
export const TOSS_VARIANT_KEY = process.env.EXPO_PUBLIC_TOSS_VARIANT_KEY ?? undefined;

// Our own scheme (app.json `scheme`) — handed to requestPayment so a card app can return here.
export const APP_SCHEME = 'daengrun';
export const TOSS_APP_SCHEME = `${APP_SCHEME}://`;

// Methods that finalize instantly. 가상계좌/계좌이체 finalize by webhook hours later, while the
// 30-minute payment_hold expires — this slice has no webhook endpoint, so those states must be
// unreachable (plan §2-8). `method` strings are Toss's Korean labels (PaymentMethod.method).
const INSTANT_CONFIRM_METHODS = ['카드', '간편결제'];

export function isInstantConfirmMethod(method: string | undefined): boolean {
  return method != null && INSTANT_CONFIRM_METHODS.includes(method);
}

// Order name shown in the widget and on the card statement. Kept short and factual.
export function tossOrderName(dogName: string, km: number): string {
  return `${dogName} 러닝 ${km}km`;
}
