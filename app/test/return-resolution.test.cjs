// return-resolution.ts — the 운영팀 판정 strip three screens draw when ops resolved a stranded
// return (owner/report.tsx ⑫-bis, runner/return-seal.tsx, runner/done.tsx). Tests run against the
// REAL compiled source (see run-return-resolution-tests.sh), not a retyped copy, under three zones.
//
// THE PROPOSITIONS THIS FILE OWNS, each stated without reference to a mutation:
//   ① Absence draws nothing. No resolution ⇒ null, for every shape of absence — and an absent
//      read and an absent resolution are deliberately the same answer (a resolution is additive
//      information, not a gate).
//   ② The sentence is the SERVER's, passed through byte for byte. The module maps nothing: 0199
//      chose the copy server-side precisely so an un-rebuilt phone cannot meet an unmapped key.
//   ③ The date is KST and rides ALONGSIDE the sentence — a missing or unreadable instant costs
//      the DATE and never the sentence, and never prints Invalid Date / NaN.
//   ④ An empty sentence draws nothing: a bordered box asserting 「something happened」 without
//      saying what is worse than no box.
//   ⑤ The clock is KST for every device zone — identical output under UTC, New_York and Seoul.
//   ⑥ The two kickers are the screens' own chrome and are never folded into the sentence.
//
// The mutations that redden it: map `notePublic` through a client-side table · print
// `rescuedFrom` · drop the NaN guard · return a strip for an empty sentence · read the device
// clock instead of kst.ts.
const {
  returnResolutionStrip, RESOLUTION_KICKER, RESOLUTION_KICKER_SHORT,
} = require('./return-resolution.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// 2026-09-22 03:05 UTC = 12:05 KST on the 22nd. Chosen so the KST hour differs from the hour
// every one of the three test zones would print: UTC says 03, New_York says 23 (on the 21st),
// Seoul says 12. Only a KST-correct implementation prints 「9월 22일 12:05」 in all three runs.
const RESOLVED_AT = '2026-09-22T03:05:00.000Z';
// the two sentences 0199 §A's `case` actually produces, quoted here as the SERVER's copy
const NOTE_ACTIVE = '운영팀이 귀가를 확인 처리했어요';
const NOTE_INCIDENT = '운영팀이 검토 후 정산 처리했어요';

// ── ① absence draws nothing ───────────────────────────────────────────────────────────────────
for (const [label, v] of [['null', null], ['undefined', undefined]]) {
  t(`① no resolution (${label}) draws nothing`, returnResolutionStrip(v) === null);
}

// ── ② the sentence is the server's, verbatim, and the module maps nothing ────────────────────
{
  const a = returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: NOTE_ACTIVE });
  const i = returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: NOTE_INCIDENT });
  t('② the active-strand sentence comes through byte for byte', a && a.text === NOTE_ACTIVE, a && a.text);
  t('② the incident sentence comes through byte for byte', i && i.text === NOTE_INCIDENT, i && i.text);
  // the PAIR is what a constant cannot satisfy — a module that hard-wired either sentence passes
  // one of the two arms above and dies here.
  t('② …and the two are different sentences (no client-side constant)',
    a && i && a.text !== i.text, a && i && `${a.text} / ${i.text}`);
  // a sentence this client has never seen — 0199's `else` arm, or a later `from_status`. The
  // module must NOT know it, must not drop it, and must not translate it.
  const later = returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: '운영팀이 확인 후 처리했어요' });
  t('🔴 ② a sentence this build has never seen is rendered anyway',
    later && later.text === '운영팀이 확인 후 처리했어요', later && later.text);
}

// ── ③ the date rides alongside and never replaces the sentence ───────────────────────────────
{
  const s = returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: NOTE_ACTIVE });
  t('③ the date is a separate field, not concatenated into the copy',
    s && s.when === '9월 22일 12:05' && s.text === NOTE_ACTIVE, s && `${s.text} | ${s.when}`);
  for (const [label, v] of [['null', null], ['undefined', undefined], ['empty', ''], ['garbage', 'not-a-date']]) {
    const bad = returnResolutionStrip({ resolvedAt: v, notePublic: NOTE_ACTIVE });
    t(`🔴 ③ an unreadable instant (${label}) costs the DATE, never the sentence`,
      bad && bad.text === NOTE_ACTIVE && bad.when === null, bad && `${bad.text} | ${bad.when}`);
  }
  const nan = returnResolutionStrip({ resolvedAt: 'not-a-date', notePublic: NOTE_ACTIVE });
  t('③ …and never prints Invalid Date or NaN',
    nan && nan.when === null && !/NaN|Invalid/.test(String(nan.when)), nan && String(nan.when));
}

// ── ④ an empty sentence draws nothing ────────────────────────────────────────────────────────
for (const [label, v] of [['null', null], ['undefined', undefined], ['empty', ''], ['blank', '   ']]) {
  t(`④ an empty sentence (${label}) draws no strip at all`,
    returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: v }) === null);
}
t('④ …even though the same row with a real sentence does draw one (control)',
  returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: NOTE_ACTIVE }) !== null);

// ── ⑤ the clock is KST in every device zone ──────────────────────────────────────────────────
// These assertions are literal strings and the runner executes this file under UTC,
// America/New_York and Asia/Seoul. A device-clock read reddens two of the three runs — and, per
// the standing law, a Seoul-only run would have been green on the bug.
{
  const s = returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: NOTE_ACTIVE });
  t('⑤ the printed date is KST regardless of TZ=' + (process.env.TZ || '(unset)'),
    s && s.when === '9월 22일 12:05', s && s.when);
  // an instant whose KST calendar DAY differs from UTC's and New_York's, so a device read cannot
  // agree with this string in any of the three runs
  const lateNight = returnResolutionStrip({ resolvedAt: '2026-09-22T16:30:00.000Z', notePublic: NOTE_ACTIVE });
  t('⑤ …including an instant that crosses the KST day boundary',
    lateNight && lateNight.when === '9월 23일 01:30', lateNight && lateNight.when);
}

// ── ⑥ the kickers are chrome, and they are not inside the sentence ───────────────────────────
{
  const s = returnResolutionStrip({ resolvedAt: RESOLVED_AT, notePublic: NOTE_ACTIVE });
  t('⑥ the owner receipt kicker is the two-seal slot heading', RESOLUTION_KICKER === '반환 확인 · 운영팀 처리');
  t('⑥ the runner receipt kicker is the short one', RESOLUTION_KICKER_SHORT === '운영팀 처리');
  t('⑥ neither kicker is folded into the server sentence',
    s && !s.text.includes(RESOLUTION_KICKER) && !s.text.includes(RESOLUTION_KICKER_SHORT), s && s.text);
}

console.log('');
console.log(`${pass} pass / ${fail} fail`);
if (fail > 0) process.exit(1);
