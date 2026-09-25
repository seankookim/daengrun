// The one door from a caught error to a failure Alert. Folds through `foldRpcError`, so no
// PostgREST / Supabase / network sentence in English is ever drawn inside a Korean product, and
// logs the ORIGINAL first, so the diagnosis moves to the log instead of being destroyed.
//
// ═══ WHY THIS EXISTS — MEASURED, NOT ANTICIPATED ═══
// 2026-09-25 finish-line sweep (copy-hierarchy-1): 81 executable `Alert.alert(…, (e as
// Error).message)` sites rendered whatever the throw carried. `foldRpcError` (rpc-error.ts) had
// existed since 2026-09-22 and was house law for NEW wrappers only, so every older screen still
// printed 「new row violates row-level security policy …」 or 「Network request failed」 as the
// body of a Korean dialog. Converting each site to `foldRpcError(e).message` by hand would have
// dropped the log line at every one of them (the folded message is Korean by construction — a
// `console.warn` of it has thrown the diagnosis away), so the two halves live here together.
//
// ═══ WHY IT IS NOT IN rpc-error.ts ═══
// rpc-error.ts is deliberately PURE: `test/run-rpc-error-fold-tests.sh` esbuild-bundles the real
// source into node, and a `react-native` import in its graph breaks that bundle. This module is
// the thin impure edge; the rule itself stays in the pure module.
//
// ⚠ WHAT IT DOES NOT DO: a message that already carries Hangul passes through UNCHANGED — the
// server (or a wrapper) raised copy we wrote, and a named refusal (「이 교환권은 회원님의 것이
// 아니에요」) tells a person what to do in a way the generic fold does not. That is also what keeps
// `card-link-panel.tsx`'s deliberate 「the card company's own sentence, verbatim」 rule intact: a
// Toss refusal arrives in Korean and is drawn as sent; only the database's English is folded.
//
// The sweep that keeps the old form from coming back is `test/alert-fail-sweep.test.cjs`.
import { Alert, type AlertButton } from 'react-native';
import { foldRpcError, rpcRaw, type FoldOpts } from './rpc-error';

export interface AlertFailOpts {
  /** Handed to `foldRpcError` unchanged — the caller's refusal table (`tokens`), its domain
   *  sentence for an error with no message at all (`empty`), the RPC name for the skew check. */
  fold?: FoldOpts;
  /** The Alert's buttons, unchanged (a 「다시 시도」 door lives here). Omit for the default OK. */
  buttons?: AlertButton[];
}

/**
 * Show a failure Alert for a caught error.
 *
 * @param title Short noun form — `<대상> 실패` (the house title grammar; the body carries the
 *              one 해요체 sentence).
 * @param e     Whatever the `catch` received. Never rendered raw.
 * @param tail  An extra line under the folded sentence (e.g. SOS's 「위급 상황이면 즉시 112/119에
 *              연락하세요.」). Joined with a single newline; start it with `\n` for a blank line.
 */
export function alertFail(title: string, e: unknown, tail?: string | null, opts: AlertFailOpts = {}): void {
  // The raw text FIRST and under its own tag: after the fold, the Alert and the log diverge on
  // purpose, and this line is the only place the database's own words survive.
  console.warn('[alert-fail]', title, rpcRaw(e));
  const m = foldRpcError(e, opts.fold).message;
  Alert.alert(title, tail ? `${m}\n${tail}` : m, opts.buttons);
}
