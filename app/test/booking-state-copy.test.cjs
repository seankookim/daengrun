// booking-state-copy.ts — tests run against the REAL compiled source (see
// run-booking-state-copy-tests.sh), not a retyped copy, plus a SOURCE DRIFT gate that walks
// `owner/schedule.tsx` and `owner/report.tsx` as text.
//
// WHAT THIS FILE IS FOR. Two things that cannot be reached the same way:
//
//  ① THE WORD TABLE (behavioural). Two owner screens carried two different tables for the same
//     raw booking states, so one booking had two names depending on which screen was open. The
//     arms below pin the arbitration — schedule.tsx's words as canon, report.tsx's words for the
//     three states STATUS_MAP flattens — and, more importantly, pin that an UNKNOWN state returns
//     `null` rather than the nearest sentence. A stale binary meeting a server word it has never
//     heard of must ADMIT, and the caller owns the fallback.
//  ② THE PREDICATE (behavioural). `reportShowsInProgress` decides whether the report draws a
//     record or an in-progress face. Its four conjuncts are four different facts and each one is
//     attacked on its own below; the `runEndedAt` arm is the one that stops the screen saying
//     「러닝 진행 중」 over a dog that is already home.
//  ③ THE DRIFT GATE (source). A `.cjs` suite can import `src/lib/*.ts` and can NEVER import a
//     `.tsx` route module, so nothing here renders either screen — these arms read them as TEXT,
//     the way `tab-parent.test.cjs` does, and they only prove that the retired placeholders are
//     gone and that both screens call the shared table. They do NOT prove the screens render it
//     well; only a device does that. Source arm and behavioural arm prove different things and
//     neither is evidence for the other.
//
// 🔴 THE DRIFT GATE'S OWN HAZARD, and the reason for the CONTROL arm at the bottom. The artifact
// closest to the truth — the screen's source — is the one artifact that carries our own prose
// inside it, and this repo documents its fixes in comments. A check for the ABSENCE of a
// placeholder would be reddened by a comment EXPLAINING its removal, and the better the
// explanation the more certainly. So comments are stripped before every match, and the control
// arm asserts that a comment quoting the retired placeholder does NOT move the count.
//
// The mutations that redden it: delete the `expired` row from the table (or any other row) ·
// return a word instead of `null` for an unknown state · invert or delete any conjunct of
// `reportShowsInProgress` · put the retired course-map placeholder back into schedule.tsx ·
// restore the screen-local status word table in report.tsx · re-add the unconditional
// 새 러닝 예약하기 footer.
const fs = require('fs');
const path = require('path');
const { bookingStateLabel, reportShowsInProgress } = require('./booking-state-copy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const ROOT = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');

// ── comment stripper (copy-forms.test.cjs's, verbatim in behaviour) ───────────────────────────
// Blanks `//` and `/* */` while LEAVING string and template contents in place — the copy this
// gate judges is JSX text and string literals, and only our prose is noise.
function stripComments(src) {
  const out = src.split('');
  let i = 0; const n = src.length;
  const blank = (a, b) => { for (let k = a; k < b; k++) if (out[k] !== '\n') out[k] = ' '; };
  while (i < n) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') { let j = i; while (j < n && src[j] !== '\n') j++; blank(i, j); i = j; continue; }
    if (c === '/' && src[i + 1] === '*') { let j = i + 2; while (j < n && !(src[j] === '*' && src[j + 1] === '/')) j++; blank(i, Math.min(j + 2, n)); i = j + 2; continue; }
    if (c === "'" || c === '"') { let j = i + 1; while (j < n && src[j] !== c) { if (src[j] === '\\') j++; if (src[j] === '\n') break; j++; } i = j + 1; continue; }
    if (c === '`') { let j = i + 1; while (j < n && src[j] !== '`') { if (src[j] === '\\') j++; j++; } i = j + 1; continue; }
    i++;
  }
  return out.join('');
}

const count = (hay, needle) => hay.split(needle).length - 1;

// ══════════════════ ① THE WORD TABLE ══════════════════

// The exact caption for every raw state this table names. Retyping one of these words on a screen
// is the defect the file closes, so the words live here and the screens read them.
const CANON = [
  ['matching', '러너 매칭 중'],
  ['runner_pending', '러너 응답 대기'],
  ['confirmed', '예약 확정'],
  ['runner_enroute', '러너 이동 중'],
  ['picked_up', '인계 완료 · 시작 대기'],
  ['active', '러닝 중 · LIVE'],
  ['completed', '완료'],
  ['cancelled_owner', '취소됨'],
  ['cancelled_runner', '취소됨'],
  ['refund_pending', '취소됨'],
  ['expired', '매칭 만료'],
  ['no_show', '불발'],
  ['incident_review', '확인 중'],
];
for (const [raw, word] of CANON) {
  t(`${raw} → ${word}`, bookingStateLabel(raw) === word, String(bookingStateLabel(raw)));
}

// 🔴 THE THREE THAT THE FLATTENED VOCABULARY GOT WRONG, named again on their own because each one
// is a sentence an owner reads about their own booking and each one used to be a different
// sentence on the other screen.
t('expired is 매칭 만료 — nobody cancelled it, we failed to find a runner',
  bookingStateLabel('expired') === '매칭 만료');
t('no_show is 불발, never 러너 응답 대기 (the STATUS_MAP fallback it used to wear)',
  bookingStateLabel('no_show') === '불발');
t('incident_review is 확인 중', bookingStateLabel('incident_review') === '확인 중');
t('picked_up carries schedule.tsx\'s middot form, not report.tsx\'s em dash',
  bookingStateLabel('picked_up') === '인계 완료 · 시작 대기'
  && !bookingStateLabel('picked_up').includes('—'));

// ── an unknown word ADMITS ─────────────────────────────────────────────────────────────────────
// A server state newer than this binary, and the three pre-quote states neither screen ever
// named. Returning the nearest sentence would be a stale app asserting something false.
for (const unknown of ['draft', 'quoted', 'payment_hold', 'teleported', '', 'ACTIVE']) {
  t(`unknown '${unknown}' returns null, never a guess`, bookingStateLabel(unknown) === null,
    String(bookingStateLabel(unknown)));
}
t('null/undefined return null', bookingStateLabel(null) === null && bookingStateLabel(undefined) === null);

// No raw server vocabulary may reach the caption — the table's VALUES are Korean copy, and an
// underscore is the tell of a leaked enum word.
t('no caption leaks a raw server word',
  CANON.every(([, word]) => !/[a-z_]{4,}/.test(word)),
  CANON.map(([, w]) => w).join('|'));

// ══════════════════ ② reportShowsInProgress ══════════════════

const live = { hasRunRow: true, endReason: null, status: 'active', runEndedAt: null };

t('a run row + no end reason + active + not stopped ⇒ in progress',
  reportShowsInProgress(live) === true);

// One conjunct at a time. Each of these is a DIFFERENT real state, not a variation of one.
t('completed booking ⇒ not in progress',
  reportShowsInProgress({ ...live, status: 'completed', endReason: 'completed' }) === false);
t('completed booking, even with the run row still shaped like a live one ⇒ not in progress',
  reportShowsInProgress({ ...live, status: 'completed' }) === false);
t('🔴 run_ended_at stamped while the booking is STILL active ⇒ not in progress (the dog is home)',
  reportShowsInProgress({ ...live, runEndedAt: '2026-09-25T09:00:00Z' }) === false);
t('an end reason ⇒ not in progress',
  reportShowsInProgress({ ...live, endReason: 'dog_condition' }) === false);
t('an end reason of completed ⇒ not in progress',
  reportShowsInProgress({ ...live, endReason: 'completed' }) === false);
t('no run row ⇒ not in progress (the pre-run placeholder owns that state)',
  reportShowsInProgress({ ...live, hasRunRow: false }) === false);
for (const s of ['confirmed', 'picked_up', 'incident_review', 'cancelled_owner', 'expired', 'no_show', 'refund_pending']) {
  t(`status ${s} ⇒ not in progress`, reportShowsInProgress({ ...live, status: s }) === false);
}
t('an unanswered seal read (undefined) does not block the in-progress face',
  reportShowsInProgress({ ...live, runEndedAt: undefined }) === true);
t('a null/undefined status ⇒ not in progress',
  reportShowsInProgress({ ...live, status: null }) === false
  && reportShowsInProgress({ ...live, status: undefined }) === false);

// ══════════════════ ③ SOURCE DRIFT GATE ══════════════════

const SCHEDULE = 'app/owner/schedule.tsx';
const REPORT = 'app/owner/report.tsx';
const schedRaw = read(SCHEDULE);
const schedSrc = stripComments(schedRaw);
const reportSrc = stripComments(read(REPORT));

// Both screens must READ the table rather than carry their own.
t('schedule.tsx imports the shared table', /booking-state-copy/.test(schedSrc), 'no import');
t('report.tsx imports the shared table', /booking-state-copy/.test(reportSrc), 'no import');

// The screen-local table report.tsx used to carry is gone — it is the second half of the drift.
t('report.tsx no longer declares its own status word table',
  !/STATUS_LABEL/.test(reportSrc), 'STATUS_LABEL still present in executable source');

// 🔴 EXACTLY ONE 준비 중 SURVIVES in schedule.tsx, and it is the 바디캠 line — Sean's D3=B ruling,
// the single place in the app that calls the body-cam a forthcoming thing. The course-map plate
// that used to sit beside it promised a map for a route the app can already draw.
const pendingHits = count(schedSrc, '준비 중');
t('schedule.tsx keeps exactly one 준비 중 in executable source (the 바디캠 line)',
  pendingHits === 1, `found ${pendingHits}`);
t('…and that one is the 바디캠 line', /바디캠[^\n]*준비 중/.test(schedSrc));

// The empty state states one fact; the direction is the header's ＋, which sits on this screen.
t('schedule.tsx no longer sends the owner back to home for a door it has itself',
  !/홈의 지금 찾기/.test(schedSrc));
t('schedule.tsx no longer draws the unconditional new-booking footer',
  !/emptyCta/.test(schedSrc), 'emptyCta still referenced');

// ── CONTROL: prose must not be able to satisfy or redden a source arm ──────────────────────────
// Append a comment that QUOTES the retired placeholder to a COPY of the source. If the stripper
// works, the executable count does not move; if it were reading raw text, documenting the fix
// would look exactly like failing to make it.
const planted = schedRaw + '\n// 코스 지도 준비 중 — the retired plate, quoted in prose only.\n';
t('CONTROL a comment quoting the retired plate does NOT move the executable count',
  count(stripComments(planted), '준비 중') === pendingHits,
  `${count(stripComments(planted), '준비 중')} vs ${pendingHits}`);
// …and the crude version DOES move, which is what makes the control informative rather than a
// second printing of the first measurement.
t('CONTROL the crude raw-text version is fooled by that same comment (so the stripper is load-bearing)',
  count(planted, '준비 중') === count(schedRaw, '준비 중') + 1);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
