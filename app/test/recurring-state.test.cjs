// recurring-state.ts — tests run against the REAL compiled source (see
// run-recurring-state-tests.sh), not a retyped copy. Same idiom as run-notification-prefs-tests.sh.
//
// WHAT THIS FILE IS FOR, since a copy table can be pinned pointlessly: every sentence this module
// produces is a CLAIM ABOUT WHAT THE HOURLY CRON WILL DO. 「매주 수요일 19:30」 says a booking will
// appear; 「다음 예약 9월 30일 19:30」 names a row that must exist; 「반복이 멈춰 있어요」 attributes
// a cause. Each of those can be wrong in a way nothing on screen contradicts, so the arms below are
// bound to `generate_recurring_bookings`'s actual behaviour (latest definition
// `0180_cron_dog_lock_and_tick_split.sql`):
//
//   · `v_dow := (s.rule->'weekdays'->>0)::int` (0180:109) — ONE weekday, the first. A second entry
//     in the array is never acted on, so rendering it would promise a run that cannot happen.
//   · `if v_dow is null or v_time is null then continue` (0180:111) — an unreadable rule is a DEAD
//     series. It must not print 「매주」 with a hole in it, and it must not offer 다시 시작, which
//     would restart something that still creates nothing.
//   · `where not paused` (0180:107) — and NOTHING on the server ever writes `paused = true`. The
//     money gate at 0180:174-181 sends a notification titled 「반복 예약 일시 중지」 and `continue`s;
//     it does not touch the column. So a paused series was paused by its owner, and the copy must
//     not blame a payment.
//   · `owner_has_unsettled_charge(s.owner_id)` (0180:169) is the debt gate, and
//     `my_unsettled_charge()` (0080:541) is the same predicate for `auth.uid()`. `true` is the one
//     value that licenses the 결제 문제 line; `false` and `null` (not asked / read failed) both say
//     nothing.
//
// THE ZONE ARMS. Every date this module prints goes through `kst.ts` (fixed +9, no Intl), and the
// runner executes this file under UTC · America/New_York · Asia/Seoul. The labels are literal, so
// all three runs must print identical output — a device-clock read anywhere in the path reddens
// New_York while staying green in Seoul, which is precisely the class a Seoul-only run cannot see.
// The 19:30 KST fixture is deliberate: it is the evening slot where UTC and KST agree on the
// weekday and New_York does not.
const {
  describeSeries, ruleWeekdayAndTime, WEEKDAY_KO, CREATE_SERIES_TOKENS,
  PENDING_NEXT, PAUSED_NOTE, DEBT_NOTE, BROKEN_LINE,
} = require('./recurring-state.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// 2026-09-23 19:30 KST = 2026-09-23T10:30:00Z (Wednesday in Seoul; still Wednesday 06:30 in
// New_York, but 2026-09-30T10:30:00Z read device-locally in New_York is a different calendar DAY
// than in Seoul — which is what the zone arms exist to catch).
const NOW = Date.parse('2026-09-23T10:30:00Z');
const NEXT_WED = '2026-09-30T10:30:00Z';           // +7d, same wall clock
const base = { paused: false, weekday: 3, time: '19:30', nextBookingAt: null, unsettledCharge: null };
const d = (over) => describeSeries({ ...base, ...over }, NOW);

// ── the running series ─────────────────────────────────────────────────────────────────────────
t('a running series with a booking already made names it: 매주 + the booking\'s own KST date and time',
  d({ nextBookingAt: NEXT_WED }).line === '매주 수요일 19:30 · 다음 예약 9월 30일 19:30',
  d({ nextBookingAt: NEXT_WED }).line);
t('a running series with NOTHING made yet states the 72h rule instead of implying something is wrong',
  d({}).line === `매주 수요일 19:30 · ${PENDING_NEXT}`, d({}).line);
t('a running series offers no 다시 시작 and no note',
  d({ nextBookingAt: NEXT_WED }).canResume === false && d({ nextBookingAt: NEXT_WED }).note === null);

// ── the next booking must be IN THE FUTURE ────────────────────────────────────────────────────
// A read a few seconds stale, or a row that slipped past while the sheet was open, must never be
// printed under the words 다음 예약. This is the one thing `nowMs` decides.
t('a PAST instant is not called 다음 예약 — the pending line takes over',
  d({ nextBookingAt: '2026-09-16T10:30:00Z' }).line === `매주 수요일 19:30 · ${PENDING_NEXT}`,
  d({ nextBookingAt: '2026-09-16T10:30:00Z' }).line);
t('an UNPARSEABLE instant is not called 다음 예약 either (never NaN, never Invalid Date on screen)',
  d({ nextBookingAt: 'not-a-date' }).line === `매주 수요일 19:30 · ${PENDING_NEXT}`,
  d({ nextBookingAt: 'not-a-date' }).line);

// ── paused ─────────────────────────────────────────────────────────────────────────────────────
t('a paused series can be resumed and says so',
  d({ paused: true }).canResume === true && d({ paused: true }).note === PAUSED_NOTE);
t('🔴 the paused note blames NOBODY — nothing on the server writes paused=true, so a payment cause would be invented',
  !PAUSED_NOTE.includes('결제'));
t('a paused series STILL names a booking the cron already made (pausing does not cancel it — the 해지 confirmation says so)',
  d({ paused: true, nextBookingAt: NEXT_WED }).line === '매주 수요일 19:30 · 다음 예약 9월 30일 19:30',
  d({ paused: true, nextBookingAt: NEXT_WED }).line);
t('a paused series with nothing scheduled drops the 다음 예약 clause rather than printing 없음 (the note already says why)',
  d({ paused: true }).line === '매주 수요일 19:30', d({ paused: true }).line);
t('🔴 a paused series NEVER shows the pending-72h promise — it is not going to make one',
  !d({ paused: true }).line.includes(PENDING_NEXT));

// ── the debt gate ──────────────────────────────────────────────────────────────────────────────
t('unsettled charge TRUE on a running series → the 결제 문제 line, pointing at 결제 관리',
  d({ unsettledCharge: true }).note === DEBT_NOTE);
t('unsettled charge FALSE says nothing (a 문제 없음 line would be noise on a healthy series)',
  d({ unsettledCharge: false }).note === null);
t('🔴 unsettled charge NULL — not asked, or the read failed — says nothing. Unknown is never rendered as a problem',
  d({ unsettledCharge: null }).note === null && d({ unsettledCharge: undefined }).note === null);
t('a PAUSED series shows the pause note, not the debt note, even when debt is also true (the cron never reached the money gate — `where not paused` came first)',
  d({ paused: true, unsettledCharge: true }).note === PAUSED_NOTE);

// ── the dead series (the cron's `continue`) ────────────────────────────────────────────────────
for (const [what, over] of [
  ['no weekday', { weekday: null }],
  ['no time', { time: null }],
  ['a weekday out of range', { weekday: 7 }],
  ['a negative weekday', { weekday: -1 }],
  ['a time that is not HH:MM', { time: '7pm' }],
  ['a time with an impossible hour', { time: '25:00' }],
]) {
  const v = d(over);
  t(`a rule the cron cannot read (${what}) is said to be broken, never printed as 매주 with a hole`,
    v.broken === true && v.line === BROKEN_LINE && v.note === null, v.line);
  t(`… and offers no 다시 시작 (${what}) — resuming would restart a series that still creates nothing`,
    v.canResume === false);
}
t('a broken PAUSED series is still broken (brokenness wins — resuming it would be a dead button)',
  d({ paused: true, weekday: null }).canResume === false && d({ paused: true, weekday: null }).broken === true);

// ── every weekday reads back as the cron's own convention ─────────────────────────────────────
// `extract(dow …)` is 0=Sunday (0077:53), and this is the mapping the whole line rests on: an
// off-by-one here tells an owner their dog runs on the wrong day, every week, with nothing on
// screen to contradict it.
t('0=일 … 6=토, the extract(dow) convention create_recurring_series writes',
  JSON.stringify(WEEKDAY_KO) === JSON.stringify(['일', '월', '화', '수', '목', '금', '토']));
for (let wd = 0; wd <= 6; wd++) {
  t(`weekday ${wd} renders 매주 ${WEEKDAY_KO[wd]}요일`,
    d({ weekday: wd }).line.startsWith(`매주 ${WEEKDAY_KO[wd]}요일 19:30`), d({ weekday: wd }).line);
}

// ── the rule parser ────────────────────────────────────────────────────────────────────────────
t('the rule create_recurring_series actually writes parses (a one-element weekdays array + HH:MM)',
  JSON.stringify(ruleWeekdayAndTime({ weekdays: [3], time: '19:30', tz: 'Asia/Seoul' }))
  === JSON.stringify({ weekday: 3, time: '19:30' }));
t('🔴 only the FIRST weekday is read — the cron reads rule->weekdays->>0 and acts on nothing else, so a second entry must not reach the screen',
  ruleWeekdayAndTime({ weekdays: [3, 5], time: '19:30' }).weekday === 3);
t('an empty weekdays array is no weekday (not 0, which would print 일요일)',
  ruleWeekdayAndTime({ weekdays: [], time: '19:30' }).weekday === null);
t('a weekday that is not an integer in 0..6 is no weekday',
  ruleWeekdayAndTime({ weekdays: ['x'], time: '19:30' }).weekday === null
  && ruleWeekdayAndTime({ weekdays: [3.5], time: '19:30' }).weekday === null
  && ruleWeekdayAndTime({ weekdays: [9], time: '19:30' }).weekday === null);
t('a missing / non-HH:MM time is no time',
  ruleWeekdayAndTime({ weekdays: [3] }).time === null
  && ruleWeekdayAndTime({ weekdays: [3], time: '19:3' }).time === null
  && ruleWeekdayAndTime({ weekdays: [3], time: 1930 }).time === null);
t('a null / undefined / non-object rule parses to nothing rather than throwing (a screen must not crash on a bad row)',
  ruleWeekdayAndTime(null).weekday === null && ruleWeekdayAndTime(undefined).time === null
  && ruleWeekdayAndTime('nonsense').weekday === null);
t('a parsed rule feeds describeSeries directly — the two halves agree on what 「readable」 means',
  d(ruleWeekdayAndTime({ weekdays: [3], time: '19:30' })).broken === false
  && d(ruleWeekdayAndTime({ weekdays: [], time: '19:30' })).broken === true);

// ── the refusal table IS a server contract ─────────────────────────────────────────────────────
// `create_recurring_series` (0077:32-63) raises exactly these three. A fourth key here would be a
// Korean sentence for a refusal the server cannot give; a missing one folds to the generic line.
t('the create refusals are exactly 0077\'s three tokens',
  JSON.stringify(Object.keys(CREATE_SERIES_TOKENS).sort())
  === JSON.stringify(['forbidden', 'not_found', 'not_signed_in']),
  JSON.stringify(Object.keys(CREATE_SERIES_TOKENS)));
t('every refusal is Korean and says what to do or what is wrong — never a token echoed at a person',
  Object.values(CREATE_SERIES_TOKENS).every((v) => /[가-힣]/.test(v) && !/[a-z_]{6,}/.test(v)),
  JSON.stringify(CREATE_SERIES_TOKENS));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
