// review-gate.ts — tests run against the REAL compiled source (see run-review-gate-tests.sh).
//
// WHAT THIS FILE IS FOR. Two decisions that were made wrongly in shipped code:
//
//  ① WHICH BOOKING the runner review is for. `runner/review.tsx` read `runResult.bookingId` and no
//     params at all, so a runner who left `runner/done` could never review that run again, and a
//     STALE store filed the stars against the WRONG booking (the insert writes `booking_id`
//     verbatim). The pins below fix the precedence — a param ALWAYS wins — and the asymmetry that
//     makes the store safe: a store-sourced id whose booking could not be READ never reaches a
//     submit button, while a param-sourced one does (the caller named it from a server row).
//
//  ② WHETHER the completed ticket draws a second door. The gate must read `rawStatus`, never the
//     flattened display word, and must hide the door on BOTH 「loading」 and 「the read failed」 —
//     neither licenses the sentence 「you have not reviewed this run」.
//
// The mutations that redden it: let the store win over a param · treat `absent` as `form` ·
// collapse `absent` and `failed` into one · let a store id reach the form on a failed read ·
// gate ② on anything but `completed` · show the door on `loading` or `err`.
const {
  resolveReviewBooking, reviewSurface, reviewDoor,
} = require('./review-gate.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── ① which booking ───────────────────────────────────────────────────────────────────────────
t('a param wins over the store — this is the whole fix',
  JSON.stringify(resolveReviewBooking('param-b', 'store-b')) ===
  JSON.stringify({ bookingId: 'param-b', source: 'param' }));
t('a param wins even when the store agrees (the SOURCE still matters downstream)',
  resolveReviewBooking('same', 'same').source === 'param');
t('the store is the fallback when there is no param',
  JSON.stringify(resolveReviewBooking(undefined, 'store-b')) ===
  JSON.stringify({ bookingId: 'store-b', source: 'store' }));
t('an empty-string param is not a param',
  resolveReviewBooking('', 'store-b').source === 'store');
t('an array param (expo-router repeats a key) is not taken as an id',
  resolveReviewBooking(['a', 'b'], 'store-b').source === 'store');
t('neither ⇒ none', JSON.stringify(resolveReviewBooking(null, null)) ===
  JSON.stringify({ bookingId: null, source: 'none' }));
t('an empty-string store value is not a booking',
  resolveReviewBooking(null, '').source === 'none');

// ── ① which face ──────────────────────────────────────────────────────────────────────────────
t('no booking ⇒ no form, whatever the read says',
  reviewSurface({ source: 'none', read: 'ok' }) === 'no-booking');
t('a param mid-read ⇒ loading (loading is not a form)',
  reviewSurface({ source: 'param', read: 'loading' }) === 'loading');
t('a store id mid-read ⇒ loading',
  reviewSurface({ source: 'store', read: 'loading' }) === 'loading');
t('a param whose booking READ fine ⇒ form',
  reviewSurface({ source: 'param', read: 'ok' }) === 'form');
t('a store id whose booking READ fine ⇒ form (verification is what makes it safe)',
  reviewSurface({ source: 'store', read: 'ok' }) === 'form');
t('a param naming nothing readable ⇒ no form (an id that resolves to nothing names nothing)',
  reviewSurface({ source: 'param', read: 'absent' }) === 'no-booking');
t('a store id naming nothing readable ⇒ no form',
  reviewSurface({ source: 'store', read: 'absent' }) === 'no-booking');
// The asymmetry, stated twice so a "simplification" reddens something.
t('a PARAM booking survives a failed read — the caller named it from a server row',
  reviewSurface({ source: 'param', read: 'failed' }) === 'form');
t('a STORE booking does NOT survive a failed read — no submit over an unverified id',
  reviewSurface({ source: 'store', read: 'failed' }) === 'read-failed');
t('`absent` and `failed` are never the same answer for a store id',
  reviewSurface({ source: 'store', read: 'absent' }) !== reviewSurface({ source: 'store', read: 'failed' }));

// ── ② the second door ─────────────────────────────────────────────────────────────────────────
t('a settled run with no review draws the door',
  reviewDoor({ rawStatus: 'completed', read: 'ready', reviewed: false }).show === true);
t('a settled run that is already reviewed does NOT draw it (no door onto a duplicate insert)',
  JSON.stringify(reviewDoor({ rawStatus: 'completed', read: 'ready', reviewed: true })) ===
  JSON.stringify({ show: false, why: 'already_reviewed' }));
t('a failed reviews read HIDES the door — it cannot assert 「you have not reviewed this」',
  JSON.stringify(reviewDoor({ rawStatus: 'completed', read: 'err', reviewed: false })) ===
  JSON.stringify({ show: false, why: 'unknown' }));
t('loading HIDES the door — loading is not zero',
  reviewDoor({ rawStatus: 'completed', read: 'loading', reviewed: false }).show === false);
// The gate is `rawStatus`, never a display word. Every non-settled state, including the ones a
// flattened vocabulary would call "완료".
for (const st of ['active', 'picked_up', 'incident_review', 'refund_pending', 'cancelled', 'matching', 'confirmed']) {
  t(`${st} is not settled ⇒ no door`,
    JSON.stringify(reviewDoor({ rawStatus: st, read: 'ready', reviewed: false })) ===
    JSON.stringify({ show: false, why: 'not_settled' }));
}
t('a null status ⇒ no door', reviewDoor({ rawStatus: null, read: 'ready', reviewed: false }).show === false);
t('the display word "completed" is the ONLY accepted value — 완료 is not a status',
  reviewDoor({ rawStatus: '완료', read: 'ready', reviewed: false }).show === false);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
