// recurring-state.ts — tests run against the REAL compiled source (see
// run-recurring-state-tests.sh), not a retyped copy. Same idiom as run-notification-prefs-tests.sh.
//
// WHAT THIS FILE IS FOR, since a copy table can be pinned pointlessly: every sentence this module
// produces is a CLAIM ABOUT WHAT THE HOURLY CRON WILL DO. 「매주 수요일 오후 7:30」 says a booking will
// appear; 「다음 예약 9월 30일 오후 7:30」 names a row that must exist; 「반복이 멈춰 있어요」 attributes
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
  d({ nextBookingAt: NEXT_WED }).line === '매주 수요일 오후 7:30 · 다음 예약 9월 30일 오후 7:30',
  d({ nextBookingAt: NEXT_WED }).line);
t('a running series with NOTHING made yet states the 72h rule instead of implying something is wrong',
  d({}).line === `매주 수요일 오후 7:30 · ${PENDING_NEXT}`, d({}).line);
t('a running series offers no 다시 시작 and no note',
  d({ nextBookingAt: NEXT_WED }).canResume === false && d({ nextBookingAt: NEXT_WED }).note === null);

// ── the next booking must be IN THE FUTURE ────────────────────────────────────────────────────
// A read a few seconds stale, or a row that slipped past while the sheet was open, must never be
// printed under the words 다음 예약. This is the one thing `nowMs` decides.
t('a PAST instant is not called 다음 예약 — the pending line takes over',
  d({ nextBookingAt: '2026-09-16T10:30:00Z' }).line === `매주 수요일 오후 7:30 · ${PENDING_NEXT}`,
  d({ nextBookingAt: '2026-09-16T10:30:00Z' }).line);
t('an UNPARSEABLE instant is not called 다음 예약 either (never NaN, never Invalid Date on screen)',
  d({ nextBookingAt: 'not-a-date' }).line === `매주 수요일 오후 7:30 · ${PENDING_NEXT}`,
  d({ nextBookingAt: 'not-a-date' }).line);

// ── paused ─────────────────────────────────────────────────────────────────────────────────────
t('a paused series can be resumed and says so',
  d({ paused: true }).canResume === true && d({ paused: true }).note === PAUSED_NOTE);
t('🔴 the paused note blames NOBODY — nothing on the server writes paused=true, so a payment cause would be invented',
  !PAUSED_NOTE.includes('결제'));
t('a paused series STILL names a booking the cron already made (pausing does not cancel it — the 해지 confirmation says so)',
  d({ paused: true, nextBookingAt: NEXT_WED }).line === '매주 수요일 오후 7:30 · 다음 예약 9월 30일 오후 7:30',
  d({ paused: true, nextBookingAt: NEXT_WED }).line);
t('a paused series with nothing scheduled drops the 다음 예약 clause rather than printing 없음 (the note already says why)',
  d({ paused: true }).line === '매주 수요일 오후 7:30', d({ paused: true }).line);
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
    d({ weekday: wd }).line.startsWith(`매주 ${WEEKDAY_KO[wd]}요일 오후 7:30`), d({ weekday: wd }).line);
}

// ── one clock vocabulary (sweep 2 · copy-hierarchy-5) ─────────────────────────────────────────
// This block renders on owner/schedule.tsx directly above rows that say 「오후 7:30」 (api.ts kstParts
// → kst.ts kstAmPm). It printed 24h 「19:30」 — one booking, two spellings, one screen. The arms below
// pin the 12h form on BOTH halves of the line (the rule's time and the next booking's own instant),
// and kstAmPm's conventions at the edges: hour unpadded, minute padded, 0시 and 12시 both print 12.
t('🔴 no 24h clock survives on a 19:30 line — neither the rule nor the next booking',
  !/\b\d{2}:\d{2}\b/.test(d({ nextBookingAt: NEXT_WED }).line), d({ nextBookingAt: NEXT_WED }).line);
t('a morning rule reads 오전 with an unpadded hour and a padded minute',
  d({ time: '07:05' }).line === `매주 수요일 오전 7:05 · ${PENDING_NEXT}`, d({ time: '07:05' }).line);
t('noon is 오후 12 and midnight is 오전 12 (kstAmPm\'s convention, byte-identical to the schedule rows)',
  d({ time: '12:30' }).line.startsWith('매주 수요일 오후 12:30')
  && d({ time: '00:15' }).line.startsWith('매주 수요일 오전 12:15'),
  `${d({ time: '12:30' }).line} | ${d({ time: '00:15' }).line}`);
// 2026-09-29T22:05:00Z = 2026-09-30 07:05 KST. In New_York that instant is 18:05 on 09-29, so a
// device-clock read here would print BOTH a different day and 오후 — the zone arm sees it.
t('the next booking\'s OWN instant is spelled in the same vocabulary, in KST (a morning one: 오전)',
  d({ time: '07:05', nextBookingAt: '2026-09-29T22:05:00Z' }).line === '매주 수요일 오전 7:05 · 다음 예약 9월 30일 오전 7:05',
  d({ time: '07:05', nextBookingAt: '2026-09-29T22:05:00Z' }).line);

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

// ══ THE REBOOK DOOR — owner/request.tsx's 「자동 매칭으로」 (sweep 2 · owner-journey-3) ══════════════
// WHY THESE LIVE HERE. This file is the rebook loop's suite (report → 재예약 / 매주 반복 → request),
// and the chain cannot import a route module (`.tsx` pulls react-native), so the property below can
// only be reached as SOURCE. A new test file would need a line in package.json's chain, which
// another slice serialises; these arms read request.tsx from here instead.
//
// THE PROPERTY, stated without reference to any mutation: rebooking pre-fills the last runner
// (report.tsx rebook()), slotAllowed then limits every slot to that runner's rules, and when none
// passes the owner must have a control that returns the booking to open matching — and that
// control must STICK: the draft pay() reads, the screen's state, and the focus-sync effect's memory
// of what it last consumed must all agree afterwards, or re-picking the same runner in matching comes
// back as 「no change」 (draft holds the runner, screen says 자동 매칭, pay() sends a 지명 anyway).
//
// ⚠ LIMITATION, as prose rather than as a pin: these arms prove the WRITES are present and the
// effect still READS what dropNomination writes. They cannot prove the rendered screen — whether
// the row is visible, whether VoiceOver reaches it, whether the Alert shows — which only a device
// run can (Sean's smoke list). Comments are stripped before every match (CLAUDE.md: a comment
// explaining a fix must not satisfy a pin for the fix).
const fs = require('fs');
const path = require('path');
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
// The body of `const <name> = (…) => { … };` in stripped source, or null. Braces inside quoted
// strings are skipped so a label like '{x}' cannot close the body early.
function arrowBody(src, name) {
  const at = src.indexOf(`const ${name} = (`);
  if (at < 0) return null;
  const open = src.indexOf('=> {', at);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open + 3; i < src.length; i++) {
    const c = src[i];
    if (c === "'" || c === '"' || c === '`') { const q = c; i++; while (i < src.length && src[i] !== q) { if (src[i] === '\\') i++; i++; } continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(open + 3, i + 1); }
  }
  return null;
}
const REQ_RAW = fs.readFileSync(path.join(__dirname, '..', 'app', 'owner', 'request.tsx'), 'utf8');
const REQ = stripComments(REQ_RAW);

// Each predicate takes a stripped source so the CONTROLS below can feed it a planted copy.
const has = (body, needle) => !!body && body.includes(needle);
const clearsDraft = (src) => { const b = arrowBody(src, 'dropNomination');
  return has(b, 'draft.preferredRunnerId = null;') && has(b, 'draft.preferredRunnerName = null;'); };
const clearsSyncMemory = (src) => { const b = arrowBody(src, 'dropNomination');
  return has(b, 'seenDraft.current.pref = null;') && has(b, 'rulesApplied.current = null;'); };
const clearsState = (src) => { const b = arrowBody(src, 'dropNomination');
  return has(b, 'setPreferred(null);') && has(b, 'setPreferredName(null);'); };
const picksWithoutDroppedRules = (src) => has(arrowBody(src, 'dropNomination'), 'pickEarliest(null)');

t('rebook-door · NO-SOURCE guard: dropNomination is defined in executable request.tsx (every arm below reads its body)',
  arrowBody(REQ, 'dropNomination') !== null);
t('rebook-door · 🔴 the clear reaches the DRAFT — pay() ③ reads draft.preferredRunnerId after the hold',
  clearsDraft(REQ));
t('rebook-door · 🔴 the clear reaches the focus-sync MEMORY (seenDraft.pref) and the once-per-runner rules latch',
  clearsSyncMemory(REQ));
t('rebook-door · …and the effect still READS the memory it writes — the draft is compared against seenDraft.current.pref',
  REQ.includes('draft.preferredRunnerId !== seenDraft.current.pref'));
t('rebook-door · the clear reaches screen STATE (chip, quiet note, 러너 불가, the rules fetch all key off it)',
  clearsState(REQ));
t('rebook-door · the clear picks with rules=null — the state reset lands next render, so a bare pickEarliest() would re-ask the dropped runner and find the same zero slots',
  picksWithoutDroppedRules(REQ));
t('rebook-door · the 러너 row offers the control when a runner is nominated, called with NO argument',
  /\{preferred && \([\s\S]{0,400}?onPress=\{\(\) => dropNomination\(\)\}/.test(REQ));
t('rebook-door · 🔴 never a bare onPress={dropNomination} — the press event is truthy and would read as thenEarliest',
  !/onPress[=:]\s*\{?\s*dropNomination\s*[},]/.test(REQ));
t('rebook-door · the no-slot Alert CARRIES the action (a button that clears, then picks the earliest)',
  REQ.includes("{ text: '자동 매칭으로 바꾸기', onPress: () => dropNomination(true) }"));
t('rebook-door · 🔴 the instruction with no control behind it is gone from executable source',
  !REQ.includes('지명을 해제해주세요'));
t('rebook-door · a runner\'s rules that land AFTER the nomination moved on are dropped (alive guard on both arms)',
  /fetchRunnerAvailability\(preferred\)\s*\.then\(\(r\) => \{ if \(alive\) setPrefRules\(r\); \}\)\s*\.catch\(\(\) => \{ if \(alive\) setPrefRules\(null\); \}\);\s*return \(\) => \{ alive = false; \};/.test(REQ));

// CONTROLS — each names the failure it exists to catch.
// (1) A comment QUOTING the write must not satisfy the pin: comment out the seenDraft write in a
//     COPY and run the same predicate. Blind to: a stripper that reads raw text.
const plantedComment = stripComments(REQ_RAW.replace('    seenDraft.current.pref = null;\n', '    // seenDraft.current.pref = null;\n'));
t('rebook-door · CONTROL · the planted copy actually differs (the plant landed)', plantedComment !== REQ);
t('rebook-door · 🔴 CONTROL · a commented-out seenDraft write does NOT satisfy the sync-memory arm',
  clearsSyncMemory(plantedComment) === false);
// (2) The same write moved OUTSIDE dropNomination must not satisfy it either. Blind to: a
//     predicate that searches the whole file instead of the function body.
const movedOut = stripComments(REQ_RAW.replace('    seenDraft.current.pref = null;\n', '').replace('const payBusy = useRef(false);', 'const payBusy = useRef(false); seenDraft.current.pref = null;'));
t('rebook-door · 🔴 CONTROL · the write elsewhere in the file does NOT count — only dropNomination\'s own body does',
  movedOut !== REQ && clearsSyncMemory(movedOut) === false);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
