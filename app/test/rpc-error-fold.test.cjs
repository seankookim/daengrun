// rpc-error.ts — tests run against the REAL compiled source (see run-rpc-error-fold-tests.sh),
// not a retyped copy, so the two sentences these cases pin are the ones the app renders.
//
// ═══ THE PROPERTY, STATED WITHOUT REFERENCE TO ANY MUTATION ═══
// No failure of a Supabase RPC may reach a Korean screen as English. Three sub-properties, and
// they are DIFFERENT claims that a single arm would blur:
//   ① a function this build knows is undeployed says so specifically (the version-mismatch
//      sentence), and ONLY such a function does — a typo must not borrow that sentence;
//   ② a refusal the server raised by name keeps its own Korean, because 「이 교환권은 회원님의
//      것이 아니에요」 tells a person what to do and the generic fold does not;
//   ③ everything else that carries no Hangul becomes the fold sentence, with the original
//      recoverable on `cause` and `raw` — the diagnosis moves to the log, it is not destroyed.
// Plus the symmetry that makes ③ safe: a message that IS Korean passes through untouched.
//
// ═══ WHAT WOULD REDDEN IT ═══
// delete the `hasHangul` guard (③ collapses and English ships) · invert it (Korean copy gets
// folded into the generic sentence and every named refusal in the product disappears) · drop
// `raw`/`cause` (the fold becomes a silent catch) · drop the `fn` gate on the skew branch (every
// PGRST202 becomes 「앱과 서버 버전이 맞지 않아…」 and a developer's typo is buried) · reorder
// `matchToken` to insertion order (a future `not_ops_admin` reports as `not_ops`) · change either
// house sentence away from the one `clubRpc` / `invokeTransition` ship.
//
// ⚠ WHAT THIS FILE CANNOT REACH, said plainly rather than pinned with an unfalsifiable arm:
// `api.ts` imports `supabase`, so a .cjs suite cannot load it and cannot assert that any given
// wrapper CALLS this module — the same structural division as `check-device-clock` beside the 33
// KST pins. In particular `custodyPing` is deliberately NOT folded (its caller reads the refusal
// TOKEN out of the message to decide whether the heartbeat stops permanently), and that exception
// is documented at the function and is NOT verified here. Reading `api.ts` as TEXT to check it
// would measure the comment, not the code — this repo has paid for that mistake more than once.

const {
  foldRpcError, matchToken, hasHangul, rawMessage, rpcRaw,
  PENDING_DEPLOY_KO, RPC_FOLD_KO,
} = require('./rpc-error.build.cjs');

let pass = 0, fail = 0;
const t = (n, f) => { try { f(); console.log('PASS ' + n); pass++; } catch (e) { console.log('FAIL ' + n + ' — ' + e.message); fail++; } };
const ok = (c, m) => { if (!c) throw new Error(m || 'not ok'); };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

// The exact shape PostgREST sends when the schema cache has no such function. Copied from the
// message a Release build printed at `daengrun://ops` on 2026-09-22 — the defect this module
// exists for. Note the `without parameters` wording: an argument-less RPC does not render
// `ops_me()`, which is why the skew check's `fn + '('` conjunct cannot match it and why this
// error correctly reaches the GENERIC fold rather than the version-mismatch sentence.
const PGRST202 = {
  code: 'PGRST202',
  message: 'Could not find the function public.ops_me without parameters in the schema cache',
};
// The other PostgREST spelling, for a function that does take arguments.
const NOT_FOUND = (fn, args) =>
  `Could not find the function public.${fn}(${args}) in the schema cache`;

// ── ① deploy skew ───────────────────────────────────────────────────────────────────────────

t('🔴 an ALLOWLISTED function with PGRST202 gets the version-mismatch sentence', () => {
  // `rpc-skew.ts`'s real list is EMPTY at rest (that is its correct resting state), so this arm
  // cannot be exercised through the shipped list. It is exercised by monkey-patching nothing and
  // instead asserting the branch through the module that owns it — see the companion arm below,
  // which pins that an unlisted function is NEVER given the sentence. The positive direction of
  // `isPendingDeploy` itself is pinned against a synthetic list by `rpc-skew.test.cjs`.
  // What is pinned HERE is that `foldRpcError` exposes the sentence at all, byte-exact.
  // [fix/alert-fold-copy 2026-09-25] Spacing normalised to the closed 「시도해주세요」 — one retry
  // sentence, one spelling: RPC_FOLD_KO four lines below it in rpc-error.ts already said
  // 「다시 시도해주세요」, so two consecutive failures rendered two spellings of the same
  // instruction. `clubRpc` imports this constant (api.ts), so there is no second literal to move.
  eq(PENDING_DEPLOY_KO, '앱과 서버 버전이 맞지 않아 지금은 쓸 수 없어요 — 잠시 후 다시 시도해주세요',
    'the version-mismatch sentence drifted from the one clubRpc ships');
});

t('🔴 a PGRST202 for a function NOT on the allowlist is NOT given the skew sentence', () => {
  // This is the narrowness `rpc-skew.ts` argues for: a typo and a missing deploy look identical
  // on the wire, and dressing a typo as 「앱과 서버 버전이 맞지 않아…」 buries a developer's bug
  // in a reassuring message. The honest answer is the generic fold.
  const e = foldRpcError(PGRST202, { fn: 'ops_me' });
  eq(e.message, RPC_FOLD_KO);
  ok(e.message !== PENDING_DEPLOY_KO, 'a non-allowlisted PGRST202 borrowed the skew sentence');
});

t('the measured production error folds to Korean — the defect, in one line', () => {
  // 2026-09-22, Release build against production at 0156: this exact string was rendered.
  const e = foldRpcError(PGRST202, { fn: 'ops_me', tokens: { not_ops: '운영자 권한이 없어요' } });
  ok(hasHangul(e.message), 'the ops refusal face would still print English');
  eq(e.message, RPC_FOLD_KO);
  eq(e.raw, PGRST202.message, 'the original was destroyed rather than moved');
  eq(e.cause, PGRST202, 'the cause was not carried');
});

t('a PGRST202 for a DIFFERENT new RPC folds the same way (the class, not the instance)', () => {
  for (const fn of ['my_ledger_unpaid_total', 'my_bank_account', 'claim_gear_tx',
                    'ops_payouts_due', 'ops_bank_account', 'ops_mark_gear_shipped']) {
    const e = foldRpcError({ code: 'PGRST202', message: NOT_FOUND(fn, 'p_x') }, { fn });
    ok(hasHangul(e.message), fn + ' reached a screen as English');
  }
});

// ── ② known tokens ──────────────────────────────────────────────────────────────────────────

const OPS = {
  not_signed_in: '세션이 만료된 것 같아요 — 다시 로그인해주세요',
  not_ops: '운영자 권한이 없어요 — 이 작업은 운영 담당자만 할 수 있어요',
  amount_mismatch: '입력한 금액과 선택한 행의 합계가 달라요',
};

t('a named refusal keeps its OWN Korean and is never flattened into the fold', () => {
  const e = foldRpcError({ message: 'not_ops' }, { fn: 'ops_me', tokens: OPS });
  eq(e.message, OPS.not_ops);
  eq(e.raw, 'not_ops');
});

t('the token is matched as a SUBSTRING of the server message, as postgres sends it', () => {
  const e = foldRpcError({ code: 'P0001', message: 'amount_mismatch' }, { tokens: OPS });
  eq(e.message, OPS.amount_mismatch);
});

t('🔴 matchToken runs LONGEST-FIRST — a longer token containing a shorter one wins', () => {
  // The substring-detector class: the day someone adds `not_ops_admin` beside `not_ops`, an
  // insertion-ordered loop reports the wrong refusal and an operator is sent to ask for a
  // permission they already hold. Reverting the sort reddens this.
  const tokens = { not_ops: 'SHORT', not_ops_admin: 'LONG' };
  eq(matchToken('not_ops_admin', tokens), 'LONG');
  eq(matchToken('not_ops', tokens), 'SHORT');
});

t('an unknown token is NOT dressed as a known one', () => {
  const e = foldRpcError({ message: 'some_token_nobody_mapped' }, { tokens: OPS });
  ok(e.message !== OPS.not_ops && e.message !== OPS.not_signed_in,
    'an unmapped refusal borrowed a mapped sentence');
  eq(e.message, RPC_FOLD_KO);
});

// ── ③ the fold ──────────────────────────────────────────────────────────────────────────────

t('🔴 an unknown ENGLISH sentence becomes the fold sentence and keeps `raw`', () => {
  const src = new Error('permission denied for table ledger_items');
  const e = foldRpcError(src);
  eq(e.message, RPC_FOLD_KO);
  eq(e.raw, 'permission denied for table ledger_items');
  eq(e.cause, src);
});

t('the fold sentence is byte-identical to the one invokeTransition ships', () => {
  eq(RPC_FOLD_KO, '요청을 처리하지 못했어요 — 다시 시도해주세요');
});

t('every English shape this surface can produce folds — none of them reaches a screen', () => {
  for (const m of [
    'Could not find the table public.payouts in the schema cache',
    'column payouts.net does not exist',
    'JWT expired',
    'Network request failed',
    'TypeError: Failed to fetch',
    'new row violates row-level security policy for table "bank_accounts"',
    'permission denied for function ops_bank_account',
  ]) {
    const e = foldRpcError({ message: m });
    ok(hasHangul(e.message), m + ' reached a screen as English');
    eq(e.raw, m, 'raw lost for: ' + m);
  }
});

t('🔴 a HANGUL message passes through UNCHANGED — the fold never eats our own copy', () => {
  const src = new Error('이 교환권은 회원님의 것이 아니에요');
  const e = foldRpcError(src);
  eq(e.message, '이 교환권은 회원님의 것이 아니에요');
  ok(e === src, 'an already-Korean Error was needlessly rebuilt, losing its identity');
});

t('a MIXED message containing Hangul is left alone — partial Korean is still ours', () => {
  const e = foldRpcError({ message: '정산 계좌 not_found' });
  eq(e.message, '정산 계좌 not_found');
});

t('an error with NO message at all gets the caller\'s domain sentence, not the generic one', () => {
  // 「정산 계좌를 처리하지 못했어요」 names which thing failed; the generic fold cannot. There is
  // no diagnosis to preserve in this case, so nothing is lost by being specific.
  eq(foldRpcError({}, { empty: '정산 계좌를 처리하지 못했어요' }).message, '정산 계좌를 처리하지 못했어요');
  eq(foldRpcError(null, { empty: '정산 내역을 불러오지 못했어요' }).message, '정산 내역을 불러오지 못했어요');
  eq(foldRpcError(undefined).message, RPC_FOLD_KO, 'no `empty` given → the generic fold');
});

// ── the log side: the diagnosis must survive the fold ────────────────────────────────────────

t('🔴 rpcRaw recovers the server text from a folded error — the fold moves it, never deletes it', () => {
  const folded = foldRpcError({ code: 'PGRST202', message: PGRST202.message }, { fn: 'ops_me' });
  eq(rpcRaw(folded), PGRST202.message);
});

t('rpcRaw degrades to the message for an error this module never touched', () => {
  eq(rpcRaw(new Error('raw thing')), 'raw thing');
  eq(rpcRaw({ message: 'plain object' }), 'plain object');
  eq(rpcRaw('a string throw'), 'a string throw');
});

t('rawMessage reads the supabase error shape and never throws on junk', () => {
  eq(rawMessage({ message: 'x' }), 'x');
  eq(rawMessage(null), '');
  eq(rawMessage(undefined), '');
  eq(rawMessage({}), '');
});

// ── hasHangul, the one predicate everything above rests on ───────────────────────────────────

t('hasHangul is true for Korean syllables and false for latin, digits and jamo-less text', () => {
  ok(hasHangul('요청을 처리하지 못했어요'));
  ok(hasHangul('계좌'));
  ok(!hasHangul('Could not find the function public.ops_me'));
  ok(!hasHangul(''));
  ok(!hasHangul('12345 — ok'));
  // ⚠ An em dash and the middle dot are punctuation we use INSIDE Korean copy; neither is Korean
  // on its own, and a predicate that said otherwise would let a punctuated English string through.
  ok(!hasHangul('— · …'));
});

t('the returned object is a real Error, so every existing `(e as Error).message` still works', () => {
  const e = foldRpcError({ message: 'anything english' });
  ok(e instanceof Error, 'callers narrowing to Error would silently get undefined');
  eq(typeof e.message, 'string');
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
