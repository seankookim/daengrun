// availability-exceptions.ts — run against the REAL compiled source (see
// run-availability-exceptions-tests.sh), never a retyped copy.
//
// WHAT THIS FILE IS FOR, since a table of constants can be pinned pointlessly:
//
//  ① **The refusal vocabulary is a CONTRACT with `0203_availability_exceptions.sql`.** The server
//     raises nine tokens by name; a token that reaches a person is an English database word in a
//     Korean product. The key set is pinned as a set, so adding a server refusal without its
//     sentence reddens here instead of shipping.
//  ② **The limits are a MIRROR, and a mirror that drifts is worse than no mirror** — the sheet
//     would refuse something the server allows, or (worse) allow something the server refuses and
//     spend a round trip to say so. Both boundaries are pinned on BOTH sides: 90 days passes and
//     91 refuses, 40 chars passes and 41 refuses.
//  ③ **`extraIsShadowed` is the product fact**, not a nicety: `is_slot_available` §2 runs its
//     blackout gate independently of §1, so a 추가 근무 inside a 휴가 opens nothing. If this goes
//     wrong the screen lists a row that does nothing — the dead-element half of the honesty law.
//  ④ **THREE ZONES.** Every label here is a KST wall-clock fact. A device-clock read inside the
//     module would be invisible on developer hardware in Seoul and wrong on every other phone —
//     the exact class `check-device-clock` and `run-kst-tests.sh` exist for. The labels asserted
//     below are LITERAL strings, so any zone that disagrees reddens by value rather than by shape.
//
// The mutations that redden it: drop a refusal key · move a limit by one · make `validateDraft`
// check the window before the range (the order is the server's) · let `extraIsShadowed` return
// true for a blackout · drop the `o.id !== ex.id` self-exclusion · read the device clock for a
// label · let `exceptionDateLabel` print NaN for a bad date instead of ''.
const {
  EXCEPTION_REFUSAL_KO, MAX_RANGE_DAYS, MAX_NOTE_CHARS, MAX_LIVE_EXCEPTIONS,
  calOfYmd, ymdOfCal, dayIndexOfYmd, addDaysYmd, hhmm,
  validateDraft, liveExceptions, atExceptionCap, rangesOverlap, extraIsShadowed,
  kindLabel, exceptionDateLabel, exceptionEffectLabel, sortExceptions, deleteConfirmMessage,
} = require('./availability-exceptions.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const ex = (o) => Object.assign(
  { id: 'x', kind: 'blackout', startsOn: '2026-10-05', endsOn: '2026-10-05', startMin: null, endMin: null, note: null },
  o,
);
const draft = (o) => { const e = ex(o); delete e.id; return e; };

// ── ① the refusal vocabulary IS the server's ──────────────────────────────────────────────────
const SERVER_TOKENS = [
  'not_authenticated', 'not_runner', 'bad_kind', 'bad_range',
  'range_too_long', 'bad_window', 'note_too_long', 'too_many', 'not_found',
];
t('every token 0203 raises has exactly one Korean sentence',
  JSON.stringify(Object.keys(EXCEPTION_REFUSAL_KO).sort()) === JSON.stringify([...SERVER_TOKENS].sort()),
  JSON.stringify(Object.keys(EXCEPTION_REFUSAL_KO)));
t('no sentence is empty, and none of them is the raw token',
  SERVER_TOKENS.every((k) => typeof EXCEPTION_REFUSAL_KO[k] === 'string'
    && EXCEPTION_REFUSAL_KO[k].trim().length > 0 && EXCEPTION_REFUSAL_KO[k] !== k));
t('every sentence is Korean — an English database word never reaches a person',
  SERVER_TOKENS.every((k) => /[가-힣]/.test(EXCEPTION_REFUSAL_KO[k])));
t('the two sentences with a number quote the limit the server enforces',
  EXCEPTION_REFUSAL_KO.range_too_long.includes(String(MAX_RANGE_DAYS))
  && EXCEPTION_REFUSAL_KO.note_too_long.includes(String(MAX_NOTE_CHARS))
  && EXCEPTION_REFUSAL_KO.too_many.includes(String(MAX_LIVE_EXCEPTIONS)));

// ── ② the limits mirror 0203 §C, on BOTH sides of each boundary ───────────────────────────────
t('the three limits are the server\'s numbers', MAX_RANGE_DAYS === 90 && MAX_NOTE_CHARS === 40 && MAX_LIVE_EXCEPTIONS === 20,
  `${MAX_RANGE_DAYS}/${MAX_NOTE_CHARS}/${MAX_LIVE_EXCEPTIONS}`);

const v = (d) => validateDraft(d);
t('a plain one-day 휴가 passes (the CONTROL — without it every refusal below could be a blanket no)',
  v(draft({})).ok === true, JSON.stringify(v(draft({}))));
t('a plain 추가 근무 passes (CONTROL, the other kind)',
  v(draft({ kind: 'extra', startMin: 300, endMin: 380 })).ok === true);

t('bad_kind — an unknown kind', v(draft({ kind: 'vacation' })).reason === 'bad_kind');
t('bad_range — end before start', v(draft({ endsOn: '2026-10-04' })).reason === 'bad_range');
t('bad_range — a date that does not exist (2026-02-31 must not roll into March)',
  v(draft({ startsOn: '2026-02-31', endsOn: '2026-02-31' })).reason === 'bad_range');
t('bad_range — a garbage string', v(draft({ startsOn: 'tomorrow', endsOn: 'tomorrow' })).reason === 'bad_range');

t(`range_too_long — ${MAX_RANGE_DAYS + 1} inclusive days`,
  v(draft({ startsOn: '2026-10-05', endsOn: addDaysYmd('2026-10-05', MAX_RANGE_DAYS) })).reason === 'range_too_long');
t(`CONTROL — exactly ${MAX_RANGE_DAYS} inclusive days passes (a >= / > slip reddens one of these two)`,
  v(draft({ startsOn: '2026-10-05', endsOn: addDaysYmd('2026-10-05', MAX_RANGE_DAYS - 1) })).ok === true);

t('bad_window — 추가 근무 spanning two days', v(draft({ kind: 'extra', endsOn: '2026-10-06', startMin: 300, endMin: 380 })).reason === 'bad_window');
t('bad_window — 추가 근무 with no window', v(draft({ kind: 'extra' })).reason === 'bad_window');
t('bad_window — start === end', v(draft({ kind: 'extra', startMin: 600, endMin: 600 })).reason === 'bad_window');
t('bad_window — start after end', v(draft({ kind: 'extra', startMin: 700, endMin: 600 })).reason === 'bad_window');
t('bad_window — past midnight (end > 1440)', v(draft({ kind: 'extra', startMin: 1400, endMin: 1500 })).reason === 'bad_window');
t('bad_window — 휴가 carrying a window is REFUSED, not silently stripped',
  v(draft({ startMin: 600, endMin: 700 })).reason === 'bad_window');

t(`note_too_long — ${MAX_NOTE_CHARS + 1} chars`, v(draft({ note: '가'.repeat(MAX_NOTE_CHARS + 1) })).reason === 'note_too_long');
t(`CONTROL — exactly ${MAX_NOTE_CHARS} chars passes`, v(draft({ note: '가'.repeat(MAX_NOTE_CHARS) })).ok === true);
t('a note of spaces is trimmed to nothing and does not trip the cap',
  v(draft({ note: ' '.repeat(MAX_NOTE_CHARS + 5) })).ok === true);

// 🔴 the ORDER is the server's. A draft that breaks range AND window must hear about the range
// first, or the sheet and the server disagree about which sentence to show.
t('range is checked BEFORE window — a two-day 추가 근무 that is also 91 days long says range_too_long',
  v(draft({ kind: 'extra', startsOn: '2026-10-05', endsOn: addDaysYmd('2026-10-05', MAX_RANGE_DAYS), startMin: 300, endMin: 380 })).reason === 'range_too_long');
t('kind is checked BEFORE range — a bad kind with a bad range says bad_kind',
  v(draft({ kind: 'nope', endsOn: '2026-01-01' })).reason === 'bad_kind');
t('every refusal carries the sentence its token maps to',
  v(draft({ kind: 'nope' })).ko === EXCEPTION_REFUSAL_KO.bad_kind);

// ── date arithmetic, with no clock ────────────────────────────────────────────────────────────
t('calOfYmd → ymdOfCal round-trips', ymdOfCal(calOfYmd('2026-01-09')) === '2026-01-09');
t('calOfYmd refuses a rolled date', calOfYmd('2026-02-31') === null);
t('calOfYmd refuses a short string', calOfYmd('2026-2-3') === null);
t('calOfYmd refuses empty/undefined', calOfYmd('') === null && calOfYmd(undefined) === null);
t('dayIndexOfYmd difference is a calendar day count across a month boundary',
  dayIndexOfYmd('2026-11-01') - dayIndexOfYmd('2026-10-31') === 1);
t('…and across a year boundary', dayIndexOfYmd('2027-01-01') - dayIndexOfYmd('2026-12-31') === 1);
t('…and over a leap day (2028-02-29 exists)',
  calOfYmd('2028-02-29') !== null && dayIndexOfYmd('2028-03-01') - dayIndexOfYmd('2028-02-28') === 2);
t('addDaysYmd crosses a month boundary', addDaysYmd('2026-10-31', 1) === '2026-11-01');
t('addDaysYmd crosses a year boundary', addDaysYmd('2026-12-31', 1) === '2027-01-01');
t('addDaysYmd goes backwards', addDaysYmd('2026-01-01', -1) === '2025-12-31');
t('hhmm pads both halves', hhmm(0) === '00:00' && hhmm(305) === '05:05' && hhmm(1439) === '23:59');

// ── ④ labels, by LITERAL value, in whatever zone this process is running ──────────────────────
// 2026-10-05 is a Monday. Cross-checked below against an independent UTC read so a wrong literal
// here is caught rather than pinned.
t('the fixture date really is a Monday (cross-check, independent of the module)',
  new Date(Date.UTC(2026, 9, 5)).getUTCDay() === 1);
t('one-day 휴가 → 「10월 5일 (월)」',
  exceptionDateLabel(ex({})) === '10월 5일 (월)', exceptionDateLabel(ex({})));
t('ranged 휴가 → both ends plus the inclusive day count',
  exceptionDateLabel(ex({ endsOn: '2026-10-09' })) === '10월 5일 (월) ~ 10월 9일 (금) · 5일',
  exceptionDateLabel(ex({ endsOn: '2026-10-09' })));
t('추가 근무 → the date plus the window',
  exceptionDateLabel(ex({ kind: 'extra', startMin: 300, endMin: 380 })) === '10월 5일 (월) · 05:00–06:20',
  exceptionDateLabel(ex({ kind: 'extra', startMin: 300, endMin: 380 })));
t('a bad date renders NOTHING rather than 「NaN월 NaN일」',
  exceptionDateLabel(ex({ startsOn: 'nope', endsOn: 'nope' })) === '');
t('an 추가 근무 row with no window still renders its date (never a dangling separator)',
  exceptionDateLabel(ex({ kind: 'extra' })) === '10월 5일 (월)');
t('kindLabel is the chip word', kindLabel('blackout') === '휴가' && kindLabel('extra') === '추가 근무');

// ── ③ the shadow rule — the product fact 0203 §D makes true ───────────────────────────────────
const bo = ex({ id: 'b', kind: 'blackout', startsOn: '2026-10-05', endsOn: '2026-10-09' });
const inside = ex({ id: 'e1', kind: 'extra', startsOn: '2026-10-06', endsOn: '2026-10-06', startMin: 300, endMin: 420 });
const outside = ex({ id: 'e2', kind: 'extra', startsOn: '2026-10-12', endsOn: '2026-10-12', startMin: 300, endMin: 420 });
t('an 추가 근무 inside a 휴가 is shadowed', extraIsShadowed(inside, [bo, inside, outside]) === true);
t('an 추가 근무 outside every 휴가 is not', extraIsShadowed(outside, [bo, inside, outside]) === false);
t('CONTROL — remove the 휴가 and the same row is no longer shadowed (so the true above is caused by the blackout)',
  extraIsShadowed(inside, [inside, outside]) === false);
t('a 휴가 is never 「shadowed」 by another 휴가 — a union means nothing to anybody',
  extraIsShadowed(bo, [bo, ex({ id: 'b2', startsOn: '2026-10-01', endsOn: '2026-10-31' })]) === false);
// 🔴 The `o.kind === 'blackout'` filter is load-bearing and was NOT pinned in the first draft:
// two 추가 근무 rows on the same date must not shadow each other, and until this case existed a
// mutation deleting the filter reddened nothing. (The first draft also carried an `o.id !== ex.id`
// self-exclusion; deleting it reddened nothing in any zone because it is UNREACHABLE — an `extra`
// can never be its own blackout — so the conjunct was removed from the module rather than pinned.)
const alsoInside = ex({ id: 'e3', kind: 'extra', startsOn: '2026-10-06', endsOn: '2026-10-06', startMin: 600, endMin: 700 });
t('two 추가 근무 on the same day do not shadow each other — only a 휴가 shadows',
  extraIsShadowed(inside, [inside, alsoInside]) === false
  && extraIsShadowed(alsoInside, [inside, alsoInside]) === false);
t('the effect sentence changes when the row is shadowed — 「적용돼요」 would be false there',
  exceptionEffectLabel(inside, [bo, inside]) === '휴가 기간과 겹쳐서 적용되지 않아요'
  && exceptionEffectLabel(inside, [inside]) === '이 시간에도 예약을 받아요'
  && exceptionEffectLabel(bo, [bo]) === '이 기간에는 예약을 받지 않아요');

t('rangesOverlap is inclusive on both ends', rangesOverlap('2026-10-05', '2026-10-09', '2026-10-09', '2026-10-20') === true);
t('rangesOverlap is false when they touch without overlapping', rangesOverlap('2026-10-05', '2026-10-08', '2026-10-09', '2026-10-20') === false);
t('rangesOverlap refuses to guess on a bad date', rangesOverlap('nope', '2026-10-09', '2026-10-05', '2026-10-20') === false);

// ── the cap, counted the way the server counts it ─────────────────────────────────────────────
const past = ex({ id: 'p', startsOn: '2026-01-01', endsOn: '2026-01-02' });
const future = ex({ id: 'f', startsOn: '2026-12-01', endsOn: '2026-12-02' });
t('liveExceptions drops rows that ended before today and keeps one ending TODAY',
  liveExceptions([past, future, ex({ id: 'today', startsOn: '2026-10-05', endsOn: '2026-10-05' })], '2026-10-05')
    .map((e) => e.id).join(',') === 'f,today');
const twenty = Array.from({ length: MAX_LIVE_EXCEPTIONS }, (_, i) => ex({ id: 'n' + i, startsOn: '2026-12-01', endsOn: '2026-12-01' }));
t(`atExceptionCap is false at ${MAX_LIVE_EXCEPTIONS - 1} and true at ${MAX_LIVE_EXCEPTIONS}`,
  atExceptionCap(twenty.slice(1), '2026-10-05') === false && atExceptionCap(twenty, '2026-10-05') === true);
t('past rows do not use up the allowance (the server counts ends_on >= today, and so does this)',
  atExceptionCap([...twenty.slice(1), past, past, past], '2026-10-05') === false);

// ── ordering + the destructive confirm ────────────────────────────────────────────────────────
t('a runner reads their calendar forwards, and same-day rows go by start time',
  sortExceptions([
    ex({ id: 'c', startsOn: '2026-10-09' }),
    ex({ id: 'b', kind: 'extra', startsOn: '2026-10-05', startMin: 600, endMin: 700 }),
    ex({ id: 'a', kind: 'extra', startsOn: '2026-10-05', startMin: 300, endMin: 400 }),
  ]).map((e) => e.id).join(',') === 'a,b,c');
t('sortExceptions does not mutate its input',
  (() => { const l = [ex({ id: 'z', startsOn: '2026-10-09' }), ex({ id: 'y' })]; sortExceptions(l); return l[0].id === 'z'; })());
t('the delete confirm NAMES the row rather than asking about an unnamed thing',
  deleteConfirmMessage(ex({})) === '휴가 · 10월 5일 (월)');
t('…and degrades to the kind alone when the date cannot be rendered',
  deleteConfirmMessage(ex({ startsOn: 'nope', endsOn: 'nope' })) === '휴가 일정을 지울까요?');

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
