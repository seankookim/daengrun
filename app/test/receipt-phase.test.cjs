// receipt-phase.ts — tests run against the REAL compiled source (see run-runner-live-run-tests.sh).
//
// WHAT THIS FILE IS FOR (runner-journey-3, 2026-09-25 sweep). `runner/done.tsx` drew one face for
// four moments: 「인계해 주세요」 on SETTLED runs, 「러닝 화면에서 다시 정산하면」 during the return
// ceremony, and a coral 「다음 요청 보기」 while the work gate held the runner. The screen now renders
// per phase, and this file pins the phase decision.
//
// The mutations that redden it: swap the settled/custody order · let a missing param fall into a
// server phase · widen custody to incident_review · read the display word instead of rawStatus.
const { receiptPhase } = require('./receipt-phase.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const P = (paramBid, settled, rawStatus) => receiptPhase({ paramBid, settled, rawStatus });

// ── the four phases ─────────────────────────────────────────────────────────────────────────
t('no booking param ⇒ estimate (run.tsx\'s freeze-failed route; the in-memory estimate is honest there)',
  P(null, false, null) === 'estimate', P(null, false, null));
t('an empty-string param is not a param ⇒ estimate', P('', false, 'active') === 'estimate');
t('a param + settled ⇒ settled', P('b', true, 'completed') === 'settled');
t('a param + active, not settled ⇒ custody (the dog is still with the runner)', P('b', false, 'active') === 'custody');
t('a param + picked_up, not settled ⇒ custody', P('b', false, 'picked_up') === 'custody');
t('a param + incident_review ⇒ pending (a person has to look; no door the runner can press)',
  P('b', false, 'incident_review') === 'pending');
t('a param + refund_pending ⇒ pending', P('b', false, 'refund_pending') === 'pending');
t('a param + a null status ⇒ pending, never custody (no read, no custody claim)', P('b', false, null) === 'pending');

// ── precedence ──────────────────────────────────────────────────────────────────────────────
// 🔴 SETTLED BEATS CUSTODY. ⚠ Honest scope: through today's only caller the two inputs are
// exclusive (done.tsx computes settled as rawStatus === 'completed', and custody is picked_up/active),
// so this arm pins the FUNCTION's contract, not a state the product produces today. It is what keeps
// a future `settled` source (a ledger row, a sealed flag) from ever re-drawing 「인계해 주세요」 over a
// settled run — the exact sentence this slice removed from settled receipts.
t('🔴 settled beats custody — a settled receipt never asks for a handoff', P('b', true, 'active') === 'settled', P('b', true, 'active'));
t('the param beats everything — no param is estimate even when "settled" is claimed',
  P(null, true, 'completed') === 'estimate');

// ── CONTROLS ────────────────────────────────────────────────────────────────────────────────
// (a) raw vocabulary only: the display word for an in-flight job is not a custody status.
t('CONTROL · the display word "in_progress" is not custody', P('b', false, 'in_progress') === 'pending');
// (b) the fail strip's gate: of the four phases only estimate may draw 「러닝 화면에서 다시 정산」 —
//     a phase function that returned estimate for any server-backed receipt would re-open it.
t('CONTROL · no server-backed receipt is ever estimate',
  ['completed', 'active', 'picked_up', 'incident_review', 'refund_pending', null]
    .every((st) => P('b', st === 'completed', st) !== 'estimate'));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
