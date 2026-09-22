// payment-state.ts — tests run against the REAL compiled source (see run-payment-state-tests.sh),
// not a retyped copy.
//
// WHAT THIS FILE IS FOR, since a table of copy can be pinned pointlessly: every sentence here is a
// CLAIM ABOUT MONEY made to the person who pays it, and the whole slice exists because one of
// those sentences was false. `owner/schedule.tsx` used to count `payments` rows and render
// 「아직 청구 내역이 없어요 — 정산이 끝나면 여기에 표시돼요」 for zero, which reads as 「free」 on a
// booking the server has already put on the operations board (0173 arm eight). So the arms that
// matter are the honesty arms:
//   · no state that means 「a charge is outstanding」 may use the word 아직, and none may claim the
//     charge is coming on its own;
//   · no state without a server amount may print a number;
//   · the raw server vocabulary (`state`, `reason`) must never reach the copy;
//   · an unknown state must ADMIT, never fall through to the nearest sentence.
//
// The mutations that redden it: delete a `case` (it falls to the default and the admission arm
// fires) · make `settled_without_payment` say 아직/없어요 · let any no-amount state print a number
// · return a non-null face for a null read · map `card_relink` to the generic arrears copy ·
// drop a state from PAYMENT_STATES_THAT_SPEAK · add `awaiting_settlement` to it · read the device
// clock instead of kst.ts (the three-zone runner catches that one).
const {
  paymentFace, paymentDay, PAYMENT_STATES_THAT_SPEAK,
} = require('./payment-state.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const row = (state, over = {}) => ({
  state, amountWon: null, chargedAt: null, intentAt: null, reason: null, ...over,
});

// The eleven states `my_booking_payment_state` can return (0207 §0a). A twelfth added server-side
// without a `case` here must reach the admission arm, which is what the last block measures.
const SERVER_STATES = [
  'no_charge', 'awaiting_settlement', 'settling', 'settled_without_payment',
  'charge_pending', 'charge_retrying', 'arrears', 'charged', 'waived', 'refunded', 'unknown',
];

// ── every state produces a face, and a null read produces none ────────────────────────────────
t('a null read draws nothing (that is LOADING, and the caller owns it)',
  paymentFace(null) === null && paymentFace(undefined) === null);
for (const s of SERVER_STATES) {
  const f = paymentFace(row(s));
  t(`${s}: has a non-empty headline`, !!f && typeof f.text === 'string' && f.text.trim().length > 0,
    JSON.stringify(f));
  t(`${s}: tone is one of done/wait/alert`, !!f && ['done', 'wait', 'alert'].includes(f.tone),
    f && f.tone);
}

// ── 🔴 THE HONESTY ARM THE SLICE EXISTS FOR ───────────────────────────────────────────────────
// `settled_without_payment` is the state the old copy was false about. It may not say 아직 (which
// means 「it is coming」), it may not say 없어요 (which reads as 「there was no charge」), and it may
// not promise the charge will appear by itself — a person is looking at it.
{
  const f = paymentFace(row('settled_without_payment', { reason: 'unpriced' }));
  const all = f.text + ' ' + (f.sub ?? '');
  t('settled_without_payment never says 아직 (the word that means "it is coming")',
    !all.includes('아직'), all);
  t('settled_without_payment never says 청구 내역이 없어요 (which reads as "free")',
    !all.includes('없어요'), all);
  t('settled_without_payment is an ALERT, not a wait — a person has to look',
    f.tone === 'alert', f.tone);
  t('settled_without_payment says someone is looking at it',
    all.includes('운영팀') || all.includes('확인'), all);
  t('settled_without_payment offers NO retry button — nothing the owner taps can price a run',
    f.canRetry === false);
}

// ── 🔴 NO STATE WITHOUT A SERVER AMOUNT MAY PRINT A NUMBER ────────────────────────────────────
// 0173:100-101: nobody could price these rows, so a number here would be fabricated. Measured as
// "no digits anywhere in the rendered face" rather than as "we did not call won()", because the
// second is a fact about this file and the first is a fact about the screen.
const NO_AMOUNT_STATES = ['no_charge', 'awaiting_settlement', 'settling',
                          'settled_without_payment', 'unknown'];
for (const s of NO_AMOUNT_STATES) {
  // the server sends null; and even if a future server sent a number for one of these, the copy
  // must not print it — so the hostile input is the interesting one.
  for (const amt of [null, 24900]) {
    const f = paymentFace(row(s, { amountWon: amt }));
    const all = f.text + ' ' + (f.sub ?? '');
    t(`${s} prints no number (amountWon=${amt})`, !/[0-9]/.test(all), all);
  }
}

// ── the states that DO carry a number carry the server's, unrounded and unrecomputed ──────────
{
  const f = paymentFace(row('charged', { amountWon: 24900, chargedAt: '2026-09-22T05:30:00Z' }));
  const all = f.text + ' ' + (f.sub ?? '');
  t('charged prints the server amount', all.includes('24,900'), all);
  t('charged prints a KST date', all.includes('9월 22일'), all);
  t('charged is done', f.tone === 'done' && f.canRetry === false);
}
{
  // 05:30Z is 14:30 KST the SAME day; 20:00Z is 05:00 KST the NEXT day. The second is the one a
  // device-clock read gets wrong, and it is wrong in a way a Seoul-only run cannot see.
  const f = paymentFace(row('charged', { amountWon: 1000, chargedAt: '2026-09-22T20:00:00Z' }));
  t('charged uses KST, not the device zone (20:00Z is the 23rd in Seoul)',
    f.text.includes('9월 23일'), f.text);
}
t('paymentDay returns null rather than 「NaN월 NaN일」 on an unreadable instant',
  paymentDay('not-a-date') === null && paymentDay(null) === null && paymentDay('') === null);

// ── the two arrears reasons are two different products ────────────────────────────────────────
{
  const relink = paymentFace(row('arrears', { amountWon: 24900, reason: 'card_relink' }));
  const spent  = paymentFace(row('arrears', { amountWon: 24900, reason: 'ladder_exhausted' }));
  t('card_relink tells the owner to relink the card', relink.text.includes('결제 수단'), relink.text);
  t('ladder_exhausted does NOT tell the owner to relink a card that may be fine',
    !spent.text.includes('결제 수단'), spent.text);
  t('the two arrears reasons are different copy', relink.text !== spent.text);
  t('both arrears faces are alert + retryable (the owner has a real action)',
    relink.tone === 'alert' && spent.tone === 'alert'
    && relink.canRetry === true && spent.canRetry === true);
}

// ── retry is offered ONLY where the owner has a real action (the dead-button law) ──────────────
for (const s of SERVER_STATES) {
  if (s === 'arrears') continue;
  t(`${s} offers no retry button`, paymentFace(row(s, { amountWon: 24900 })).canRetry === false);
}

// ── waived: a DECISION at zero, and the open review is its own sentence ───────────────────────
{
  const open = paymentFace(row('waived', { amountWon: 0, reason: 'incident_review' }));
  const plain = paymentFace(row('waived', { amountWon: 0 }));
  t('an open incident review says so', (open.sub ?? '').includes('검토'), open.sub);
  t('a resolved waive does not claim a review is open',
    !(plain.sub ?? '').includes('검토'), plain.sub);
  t('waived is done, never alert', open.tone === 'done' && plain.tone === 'done');
}

// ── refunded names which kind ─────────────────────────────────────────────────────────────────
{
  const full = paymentFace(row('refunded', { amountWon: 24900, reason: 'canceled' }));
  const part = paymentFace(row('refunded', { amountWon: 24900, reason: 'partial_canceled' }));
  t('a full refund and a partial refund are different sentences', full.text !== part.text);
  t('partial says 일부', part.text.includes('일부'), part.text);
}

// ── 🔴 THE RAW SERVER VOCABULARY NEVER REACHES THE COPY (the STATUS_MAP law) ──────────────────
const RAW_WORDS = [
  ...SERVER_STATES,
  'missing_end_reason', 'missing_actual_km', 'unpriced', 'ladder_exhausted', 'card_relink',
  'incident_review', 'not_charging', 'canceled', 'partial_canceled',
];
for (const s of SERVER_STATES) {
  for (const r of [null, 'unpriced', 'card_relink', 'incident_review', 'not_charging',
                   'partial_canceled']) {
    const f = paymentFace(row(s, { amountWon: 1000, reason: r, chargedAt: '2026-09-22T05:30:00Z',
                                   intentAt: '2026-09-22T05:30:00Z' }));
    const all = f.text + ' ' + (f.sub ?? '');
    const leaked = RAW_WORDS.filter((w) => all.includes(w));
    t(`${s}/${r}: no raw server token in the copy`, leaked.length === 0, leaked.join(','));
  }
}

// ── a state the server KNOWS must not be answered with an admission ───────────────────────────
// `awaiting_settlement` is the one state the shipped copy was ever honest about; answering it
// with 「결제 상태를 확인하고 있어요」 would confess ignorance about a booking nothing is wrong with.
{
  const known = paymentFace(row('awaiting_settlement'));
  const admission = paymentFace(row('SOMETHING_THE_BINARY_PREDATES'));
  t('awaiting_settlement has its own sentence, not the admission',
    known.text !== admission.text, known.text);
  t('awaiting_settlement says the charge follows settlement',
    known.text.includes('정산') && known.tone === 'wait', known.text);
}

// ── 🔴 AN UNKNOWN STATE ADMITS; IT DOES NOT FALL THROUGH TO THE NEAREST SENTENCE ──────────────
// An old binary meeting a server word it was built before. The dangerous failure is not a blank
// line — it is a confident wrong sentence about money.
{
  const admission = paymentFace(row('unknown'));
  for (const bogus of ['', 'settled', 'charge', 'paid', 'partially_refunded', 'ZZZ']) {
    const f = paymentFace(row(bogus));
    t(`an unrecognised state (${bogus || '<empty>'}) reaches the admission arm`,
      f !== null && f.text === admission.text, f && f.text);
    t(`an unrecognised state (${bogus || '<empty>'}) claims nothing about the money`,
      !/[0-9]/.test(f.text + ' ' + (f.sub ?? ''))
      && !(f.text + (f.sub ?? '')).includes('완료'), f && f.text);
    t(`an unrecognised state (${bogus || '<empty>'}) offers no button`, f.canRetry === false);
  }
}

// ── the section-visibility list is a contract with the screen ─────────────────────────────────
t('awaiting_settlement is NOT in the speaking list (a booking that has not settled has nothing to report)',
  !PAYMENT_STATES_THAT_SPEAK.includes('awaiting_settlement'));
t('every other server state IS in the speaking list',
  SERVER_STATES.filter((s) => s !== 'awaiting_settlement')
    .every((s) => PAYMENT_STATES_THAT_SPEAK.includes(s)),
  SERVER_STATES.filter((s) => s !== 'awaiting_settlement'
    && !PAYMENT_STATES_THAT_SPEAK.includes(s)).join(','));
t('🔴 settled_without_payment speaks — it is the whole point of the slice',
  PAYMENT_STATES_THAT_SPEAK.includes('settled_without_payment'));

// ── hostile inputs cost the DETAIL, never the sentence ────────────────────────────────────────
for (const amt of [NaN, Infinity, -Infinity, null, undefined]) {
  const f = paymentFace(row('charged', { amountWon: amt, chargedAt: '2026-09-22T05:30:00Z' }));
  t(`charged survives amountWon=${String(amt)} with a real headline`,
    f.text.includes('결제 완료'), f.text);
  t(`charged prints no 「NaN」 for amountWon=${String(amt)}`,
    !(f.text + (f.sub ?? '')).includes('NaN'), f.sub);
}
{
  const f = paymentFace(row('charged', { amountWon: 24900, chargedAt: 'garbage' }));
  t('an unreadable charge instant costs the date and keeps the sentence',
    f.text === '결제 완료' && (f.sub ?? '').includes('24,900'), JSON.stringify(f));
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
