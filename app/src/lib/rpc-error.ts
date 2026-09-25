// The one rule for turning a PostgREST/Supabase throw into something a Korean app may render.
// Pure except for `rpc-skew.ts` (itself pure), so `test/rpc-error-fold.test.cjs` can bundle the
// REAL source with esbuild rather than a retyped copy — the same idiom as rpc-skew / bank-account.
//
// ═══ WHY THIS EXISTS — MEASURED, NOT ANTICIPATED ═══
// 2026-09-22, Release build of trunk on the simulator against production (still at migration
// 0156): `daengrun://ops` drew the ops layout's refusal face correctly and then printed
// 「Could not find the function public.ops_me without parameters in the schema cache」 — an
// English database sentence inside a Korean product. Every wrapper written that night calls an
// RPC that production does not have yet, so every one of them had the same defect, and the window
// is real for shipped builds too: a store binary lives between its own release and the `db push`,
// and a rollback re-opens it.
//
// The repo had already fixed this class twice — `invokeTransition` folds any non-Hangul message,
// `clubRpc` maps deploy skew — and both fixes were local to one call path. This module is those
// two rules in one place so a NEW wrapper inherits them instead of re-discovering the defect.
//
// ═══ THE THREE STAGES, IN ORDER ═══
//   (a) deploy skew  → `PENDING_DEPLOY_KO`, but ONLY for a function `rpc-skew.ts` lists. That
//                      list is deliberately narrow and deliberately EMPTY at rest; read its
//                      header for why a blanket PGRST202 → friendly-sentence rule is worse than
//                      nothing (it buries a developer's typo in a reassuring message).
//   (b) known token  → the caller's own Korean table, longest token first.
//   (c) anything else that carries no Hangul → `RPC_FOLD_KO`, with the original kept on `cause`
//                      and on `raw` so a log still names the real fault.
// A message that already contains Hangul is returned untouched: the server raised copy we wrote.

import { isPendingDeploy } from './rpc-skew';

/** ⚠ The sentence `clubRpc` has shipped since the 0134 skew (api.ts imports THIS constant, so there
 *  is one literal, not two to keep in step). One wording for one state — a second phrasing of the
 *  same fact is a second product. Spacing closed to 「시도해주세요」 on 2026-09-25 so it matches
 *  `RPC_FOLD_KO` below: two consecutive failures used to spell the same instruction two ways. */
export const PENDING_DEPLOY_KO =
  '앱과 서버 버전이 맞지 않아 지금은 쓸 수 없어요 — 잠시 후 다시 시도해주세요';

/** ⚠ Byte-identical to `invokeTransition`'s fold, for the same reason. It promises nothing about
 *  the retry succeeding — it only refuses to show a person a database sentence. */
export const RPC_FOLD_KO = '요청을 처리하지 못했어요 — 다시 시도해주세요';

/** Does this string contain Korean? The test for 「is this ours or the database's」. */
export const hasHangul = (s: string): boolean => /[가-힣]/.test(s);

/**
 * The message as the server sent it, before any mapping.
 *
 * ⚠ IT DOES NOT `String(e)` A MESSAGE-LESS OBJECT, and every helper this module replaced did.
 * `String(error ?? '')` on `{ code: 'PGRST301' }` yields the literal text `[object Object]` —
 * which carries no Hangul, so it would be indistinguishable from a real English fault: the fold
 * would fire, the domain sentence a caller passed as `empty` would be skipped, and `raw` would
 * record a diagnosis of `[object Object]` in the log. Found by this module's own pins while they
 * were being written, not reasoned about afterwards. An object with no message has nothing to
 * say; the honest value is the empty string, which routes it to the caller's `empty` sentence.
 */
export const rawMessage = (e: unknown): string => {
  if (e === null || e === undefined) return '';
  const m = (e as { message?: unknown }).message;
  if (typeof m === 'string') return m;
  if (typeof e === 'string') return e;
  if (typeof e === 'number' || typeof e === 'boolean') return String(e);
  return '';
};

/** An error this module produced carries the original text here; everything else falls back to
 *  its own message. Log THIS, render `e.message` — the whole point of folding is that the two
 *  diverge, and a `console.warn` that prints the folded Korean has thrown the diagnosis away. */
export const rpcRaw = (e: unknown): string => {
  const r = (e as { raw?: unknown } | null | undefined)?.raw;
  return typeof r === 'string' && r ? r : rawMessage(e);
};

/**
 * Longest token first. ⚠ The sort is the load-bearing part, not the lookup: these are SUBSTRING
 * matches against the server's message, so the day someone adds `not_ops_admin` beside `not_ops`
 * an insertion-ordered loop reports the wrong one — the substring-detector class this house has
 * been bitten by repeatedly. No token contains another today; the sort is what keeps that from
 * mattering the day one does.
 */
export function matchToken(raw: string, tokens: Record<string, string>): string | null {
  const keys = Object.keys(tokens).sort((a, b) => b.length - a.length);
  for (const k of keys) if (raw.includes(k)) return tokens[k];
  return null;
}

export interface FoldOpts {
  /** The RPC name actually called, for the deploy-skew check. Omit for a table read — PGRST202
   *  is a FUNCTION-not-found code and naming a table here would ask a question that cannot be
   *  answered true. */
  fn?: string | null;
  /** The caller's own refusal table, token → Korean. */
  tokens?: Record<string, string>;
  /** What to say when the error carries NO message at all. Domain-specific, because
   *  「정산 계좌를 처리하지 못했어요」 tells a person which thing failed and the generic fold does
   *  not. Defaults to `RPC_FOLD_KO`. */
  empty?: string;
}

/** Build the thrown Error, keeping the original both ways. `cause` carries code/details/hint/
 *  stack for a redbox; `raw` is the flat string a `console.warn` can print. */
function folded(message: string, cause: unknown, raw: string): Error {
  const out = new Error(message, { cause }) as Error & { raw: string };
  out.raw = raw;
  return out;
}

/**
 * The boundary rule. Call it instead of `throw error` in any wrapper whose failure can reach a
 * screen.
 *
 * ⚠ It returns an Error rather than throwing, so a call site reads `throw foldRpcError(...)` and
 * the control flow stays visible where the RPC is.
 *
 * ⚠ A Hangul message passes through UNCHANGED, including its identity when it is already an
 * Error — a caller that raised its own Korean copy has said what it meant.
 */
export function foldRpcError(e: unknown, opts: FoldOpts = {}): Error {
  const raw = rawMessage(e);

  // (a) 배포 스큐 — narrow by construction: `isPendingDeploy` refuses any function not on
  //     `rpc-skew.ts`'s allowlist, so a typo or a signature mismatch still reaches (c) as the
  //     generic fold and a developer can still find it by its `raw`.
  if (opts.fn && isPendingDeploy(opts.fn, e as { code?: string | null; message?: string | null })) {
    return folded(PENDING_DEPLOY_KO, e, raw);
  }

  // (b) 서버가 이름으로 말한 거절
  if (opts.tokens) {
    const ko = matchToken(raw, opts.tokens);
    if (ko) return folded(ko, e, raw);
  }

  // An error with nothing to say at all. Not the same as an English one: there is no diagnosis to
  // preserve, so the domain sentence is the most useful thing available.
  if (raw === '') return folded(opts.empty ?? RPC_FOLD_KO, e, raw);

  // (c) the fold — anything left that is not Korean is the database talking.
  if (!hasHangul(raw)) return folded(RPC_FOLD_KO, e, raw);

  return e instanceof Error ? e : new Error(raw);
}
