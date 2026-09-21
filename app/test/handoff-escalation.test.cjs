// handoff-escalation.ts — the strip both meetup screens draw when a pickup handoff has stalled.
// Tests run against the REAL compiled source (see run-handoff-escalation-tests.sh), not a
// retyped copy, and under three timezones.
//
// THE PROPOSITIONS THIS FILE OWNS, each stated without reference to a mutation:
//   ① Absence draws nothing. No escalation ⇒ null, for every shape of absence.
//   ② An escalation with NO ops alert says what actually happened — 「인계 확인이 멈춰 있어요」,
//      the same words arm ⓓ pushed — and **never** claims the ops team was told.
//   ③ An ops alert says 「운영팀에 알렸어요」 and takes its clock from the OPS instant, not from
//      the escalation instant. The two differ in the fixture, so a function that printed the
//      wrong one is visible.
//   ④ The pair completing retires the strip. Nothing here expires on a clock.
//   ⑤ An unparseable instant costs the TIME, never the SENTENCE, and never prints Invalid/NaN.
//   ⑥ The clock is KST for every device zone — identical output under UTC, New_York and Seoul.
//
// The mutations that redden it: bind the 운영팀 sentence to `escalatedAt` · take the ops clock
// from `escalatedAt` · drop the `bothConfirmed` gate · let an unparseable instant through to
// `toLocaleTimeString` · read the device clock instead of kst.ts.
const {
  handoffEscalationStrip, OPS_ALERTED_TEXT, PARTIES_TOLD_TEXT,
} = require('./handoff-escalation.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// 2026-09-22 03:05 UTC = 12:05 KST. Chosen so the KST hour differs from the hour every one of
// the three test zones would print: UTC says 03, New_York says 23 (and the PREVIOUS day), Seoul
// says 12. Only a KST-correct implementation prints 12:05 in all three runs.
const ESCALATED = '2026-09-22T03:05:00.000Z';   // → 12:05 KST
const OPS_ALERT = '2026-09-22T05:40:00.000Z';   // → 14:40 KST, deliberately a DIFFERENT hour

// ── ① absence draws nothing ───────────────────────────────────────────────────────────────────
for (const [label, v] of [['null', null], ['undefined', undefined], ['empty string', '']]) {
  t(`① no escalation (${label}) draws nothing`,
    handoffEscalationStrip(v, null, false) === null);
  t(`① no escalation (${label}) draws nothing even if an ops alert somehow exists`,
    handoffEscalationStrip(v, OPS_ALERT, false) === null,
    'an ops alert without an escalation is not a state the server produces; the strip is anchored on the escalation');
}

// ── ② escalated, roster EMPTY: say what happened, claim nothing about ops ─────────────────────
// 0183:86 — `handoff_ops_alerted_at` NULL while `handoff_escalated_at` is set means the roster
// was empty and the ops escalation is still PENDING. 0155 records that nobody is subscribed in
// production, so this is the arm the pilot actually runs.
{
  const s = handoffEscalationStrip(ESCALATED, null, false);
  t('② an escalation with no ops alert still draws a strip', !!s);
  t('② …bound to the escalation, not to the ops column', s && s.kind === 'parties_told', s && s.kind);
  t('② …and the sentence is the one arm ⓓ pushed', s && s.text.startsWith(PARTIES_TOLD_TEXT), s && s.text);
  t('🔴 ② …and it NEVER claims the ops team was told',
    s && !s.text.includes(OPS_ALERTED_TEXT) && !s.text.includes('운영팀'), s && s.text);
  t('② …with the escalation instant as a KST wall clock', s && s.text === `${PARTIES_TOLD_TEXT} · 12:05`, s && s.text);
  t('② …hasTime is true', s && s.hasTime === true);
}

// ── ③ ops alerted: the other sentence, and the OPS clock ─────────────────────────────────────
{
  const s = handoffEscalationStrip(ESCALATED, OPS_ALERT, false);
  t('③ an ops alert says 운영팀에 알렸어요', s && s.text.startsWith(OPS_ALERTED_TEXT), s && s.text);
  t('③ …kind is ops_alerted', s && s.kind === 'ops_alerted', s && s.kind);
  t('🔴 ③ …and the clock is the OPS instant (14:40), not the escalation instant (12:05)',
    s && s.text === `${OPS_ALERTED_TEXT} · 14:40`, s && s.text);
  t('③ …so the two sentences are genuinely different strings',
    OPS_ALERTED_TEXT !== PARTIES_TOLD_TEXT);
}

// ── ④ the pair completing retires the strip ──────────────────────────────────────────────────
t('④ both stamps in ⇒ no strip, even with an escalation',
  handoffEscalationStrip(ESCALATED, null, true) === null);
t('④ both stamps in ⇒ no strip, even with an ops alert',
  handoffEscalationStrip(ESCALATED, OPS_ALERT, true) === null);
t('④ CONTROL: the same inputs with the pair INCOMPLETE do draw one',
  handoffEscalationStrip(ESCALATED, OPS_ALERT, false) !== null,
  'without this arm, "always null" passes every ④ case');

// ── ⑤ an unparseable instant costs the time, never the sentence ──────────────────────────────
{
  const s = handoffEscalationStrip('not-a-date', null, false);
  t('⑤ an unparseable escalation still draws the sentence', !!s && s.text === PARTIES_TOLD_TEXT, s && s.text);
  t('⑤ …hasTime is false', s && s.hasTime === false);
  t('⑤ …and nothing that looks like a broken date is rendered',
    s && !/Invalid|NaN|undefined|null/.test(s.text), s && s.text);
}
{
  const s = handoffEscalationStrip(ESCALATED, 'not-a-date', false);
  t('⑤ an unparseable OPS instant keeps the ops SENTENCE (the fact is present; only the clock is not)',
    s && s.kind === 'ops_alerted' && s.text === OPS_ALERTED_TEXT, s && JSON.stringify(s));
  t('⑤ …hasTime is false there too', s && s.hasTime === false);
}

// ── ⑥ the clock is KST in every device zone ──────────────────────────────────────────────────
// This assertion is a literal string, and the runner executes this file under UTC,
// America/New_York and Asia/Seoul. A device-clock read reddens two of the three runs — and, per
// the standing law, a Seoul-only run would have been green on the bug.
{
  const s = handoffEscalationStrip(ESCALATED, OPS_ALERT, false);
  t('⑥ the printed clock is KST regardless of TZ=' + (process.env.TZ || '(unset)'),
    s && s.text === `${OPS_ALERTED_TEXT} · 14:40`, s && s.text);
  // an instant whose KST calendar DAY differs from the device's, so a device read cannot agree
  const lateNight = handoffEscalationStrip('2026-09-22T16:30:00.000Z', null, false); // → 01:30 KST, next day
  t('⑥ …including an instant that crosses the KST day boundary',
    lateNight && lateNight.text === `${PARTIES_TOLD_TEXT} · 01:30`, lateNight && lateNight.text);
}

console.log('');
console.log(`${pass} pass / ${fail} fail`);
if (fail > 0) process.exit(1);
