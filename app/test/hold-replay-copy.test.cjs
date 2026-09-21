// hold-replay-copy.ts — tests run against the REAL compiled source (see
// run-hold-replay-copy-tests.sh).
//
// WHAT THIS FILE IS FOR. `create-booking-hold` has answered a replayed `client_request_id` with
// `unchanged: true` since 0179, and `owner/request.tsx` has sent the key since then — but nothing
// rendered the flag. So a double-tapped 예약하기, or the far more common lost-response-then-다시
// 시도, showed the owner the FIRST booking under the line 「● 서버 홀드 확보 — 예약이
// 생성됐어요」: a sentence that is false at the moment it is printed, and a ceremony replaying for
// something that happened once.
//
// The arms are about one property: a replay must never be told a booking was CREATED.
// The mutations that redden it: make the replayed line claim creation · return a notice on a fresh
// booking · drop the in-flight state and claim success before the server answered.
const { holdStatusLine, holdReplayNotice } = require('./hold-replay-copy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const CREATED = '생성됐어요';

// ── the modal's line ──────────────────────────────────────────────────────────────────────────
t('in flight says so, and claims nothing',
  holdStatusLine({ live: null, replayed: false }) === '서버 연결 중...');
t('in flight says the same thing even if a previous attempt was a replay',
  holdStatusLine({ live: null, replayed: true }) === '서버 연결 중...');
t('a FRESH hold keeps the sentence that was always true for it',
  holdStatusLine({ live: true, replayed: false }) === '● 서버 홀드 확보 — 예약이 생성됐어요');
t('🔴 a REPLAY never claims a booking was created',
  !holdStatusLine({ live: true, replayed: true }).includes(CREATED),
  holdStatusLine({ live: true, replayed: true }));
t('a REPLAY says the booking already exists',
  holdStatusLine({ live: true, replayed: true }).includes('이미 접수된 예약'),
  holdStatusLine({ live: true, replayed: true }));
t('the two answered lines are different sentences',
  holdStatusLine({ live: true, replayed: true }) !== holdStatusLine({ live: true, replayed: false }));
t('`live: false` is not a success (the state is unused, but it must not read as one)',
  !holdStatusLine({ live: false, replayed: false }).includes(CREATED));

// ── the one line the owner is told ────────────────────────────────────────────────────────────
t('a fresh booking gets NO notice — a booking that was just made needs no explanation',
  holdReplayNotice(false) === null);
const n = holdReplayNotice(true);
t('a replay gets a notice', n !== null);
t('the notice names the fact: this request was already accepted',
  n.title.includes('이미 접수된 예약'), JSON.stringify(n));
t('the notice names the CAUSE: the same request was pressed twice',
  n.body.includes('두 번 눌렸어요'), JSON.stringify(n));
t('the notice says no new booking was made',
  n.body.includes('새 예약은 만들어지지 않았어요'), JSON.stringify(n));
t('the notice never claims a creation', !n.title.includes(CREATED) && !n.body.includes(CREATED));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
