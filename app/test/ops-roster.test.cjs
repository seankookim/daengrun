// ops-roster.ts — tests run against the REAL compiled source (see run-ops-roster-tests.sh), not
// a retyped copy.
//
// What this file is FOR, since a table of labels can be pinned pointlessly: two of these arms are
// server CONTRACTS and the rest are honesty arms.
//   · the KEY SET is 0208 §C's `c_classes` — a label here the server does not know is a chip whose
//     tap is refused, and a class the server knows and this table omits is a desk nobody can be
//     seated at from the product. Pinned in BOTH directions against a literal copy of the
//     migration's list.
//   · `wouldStrandConsole` mirrors 0208 §C's `last_operator`, and the two ways it can be wrong are
//     asymmetric: saying 「stranded」 when it is not costs a chip that refuses a legal change;
//     saying 「fine」 when it is not costs one round trip and a server refusal. The arms below pin
//     the scope (`payout_due` only) and the already-off case, which are the two the screen's copy
//     depends on.
//   · `groupRoster` must keep a person whose every row is INACTIVE — 0084 keeps the row so that
//     「who used to be on call」 survives, and dropping them here means re-typing a uuid.
//   · `classLabel` must fall back to the RAW class, because `ops_roster()` returns rows whose
//     class this table does not know (0084 §E puts no CHECK on the column).
//
// The mutations that redden it: drop a class from CLASS_LABELS · add one the server has no arm
// for · make `wouldStrandConsole` class-agnostic · make it fire on an already-off row · make
// `groupRoster` drop inactive-only people · make `classLabel` return '' or a placeholder for an
// unknown class · make `chipLabel` return the same string busy and idle.
const {
  CONSOLE_CLASS, CLASS_LABELS, CLASS_ORDER, SELECTABLE_CLASSES,
  classLabel, chipLabel, groupRoster, activeConsoleOperators, wouldStrandConsole, personSummary,
} = require('./ops-roster.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the key set IS 0208 §C's allowlist ─────────────────────────────────────────────────────────
// A literal copy of `c_classes` in `supabase/migrations/0208_ops_roster.sql`. It is a SECOND copy
// on purpose: both were derived from the emitters (the five SQL literals plus the eight members of
// `supabase/functions/_shared/ops.ts`'s `OpsEventClass` union), and a name dropped from either
// side reddens here. It is not evidence that the list is RIGHT — only that the two agree.
const SERVER_CLASSES = [
  'payout_due', 'return_strand', 'handoff_unanswered', 'billing_key_revocation_abandoned',
  'club_fee_mint_failed', 'payment_manual_cancel', 'charge_ladder_exhausted',
  'charge_dispatch_stale', 'settled_without_payment', 'enroute_comp_failed',
  'late_comp_failed', 'incident_waive_pending', 'payment_marker_lost',
];

t('every class the server accepts has a chip (no desk the product cannot seat anyone at)',
  SERVER_CLASSES.every((c) => Object.prototype.hasOwnProperty.call(CLASS_LABELS, c)),
  SERVER_CLASSES.filter((c) => !CLASS_LABELS[c]).join(','));
t('every chip is a class the server accepts (no chip whose tap is refused)',
  Object.keys(CLASS_LABELS).every((c) => SERVER_CLASSES.includes(c)),
  Object.keys(CLASS_LABELS).filter((c) => !SERVER_CLASSES.includes(c)).join(','));
t('the two sets are the same size (neither direction hides a mismatch)',
  Object.keys(CLASS_LABELS).length === SERVER_CLASSES.length,
  Object.keys(CLASS_LABELS).length + ' vs ' + SERVER_CLASSES.length);
t('every label is a non-empty Korean sentence, not the raw class echoed back',
  Object.entries(CLASS_LABELS).every(([k, v]) => typeof v === 'string' && v.length > 0 && v !== k));
t('the console class is the one every shipped ops door gates on', CONSOLE_CLASS === 'payout_due');
t('the console class has a chip and comes first', CLASS_ORDER[0] === CONSOLE_CLASS);
t('the add sheet offers exactly the chips the list draws',
  JSON.stringify([...SELECTABLE_CLASSES]) === JSON.stringify([...CLASS_ORDER]));

// ── an UNKNOWN class renders as itself ─────────────────────────────────────────────────────────
// 0084 §E deliberately puts no CHECK on `ops_recipients.event_class`, and `ops_roster()` returns
// every row. A label table that swallowed the unknown one would make the roster lie about who is
// on call — which is the one thing a roster may not do.
t('an unknown class falls back to its raw name', classLabel('written_by_psql') === 'written_by_psql');
t('a known class uses its label', classLabel('payout_due') === CLASS_LABELS.payout_due);

// ── the busy label is a SWAP, never the old text ───────────────────────────────────────────────
t('a busy chip does not read as the settled state',
  chipLabel('payout_due', true) !== chipLabel('payout_due', false));
t('a busy chip still names its class',
  chipLabel('payout_due', true).includes(CLASS_LABELS.payout_due));

// ── grouping ───────────────────────────────────────────────────────────────────────────────────
const row = (profileId, eventClass, active, name = '가나다', role = 'owner') =>
  ({ profileId, name, role, eventClass, active, createdAt: '2026-09-01T00:00:00Z' });

const ROWS = [
  row('p2', 'payout_due', true, '나운영'),
  row('p1', 'return_strand', false, '가운영'),
  row('p1', 'payout_due', true, '가운영'),
  row('p3', 'handoff_unanswered', false, '다운영'),
  row('p4', 'payout_due', false, null, null),
];
const grouped = groupRoster(ROWS);

t('one entry per person', grouped.length === 4, JSON.stringify(grouped.map((g) => g.profileId)));
t('people are ordered by name, and a nameless row sorts last',
  JSON.stringify(grouped.map((g) => g.profileId)) === JSON.stringify(['p1', 'p2', 'p3', 'p4']),
  JSON.stringify(grouped.map((g) => g.profileId)));
t('a person keeps every row, active or not',
  grouped[0].classes.length === 2 && grouped[0].profileId === 'p1');
t('classes are drawn in the chip order, not the wire order',
  JSON.stringify(grouped[0].classes.map((c) => c.eventClass))
    === JSON.stringify(['payout_due', 'return_strand']));
t('activeClasses carries only the active ones',
  JSON.stringify(grouped[0].activeClasses) === JSON.stringify(['payout_due']));
t('a person whose every row is INACTIVE survives (0084: who used to be on call is an audit fact)',
  grouped.some((g) => g.profileId === 'p3' && g.activeClasses.length === 0
    && g.classes.length === 1));
t('a row whose profile is gone is kept with a null name, never dropped',
  grouped[3].profileId === 'p4' && grouped[3].name === null);
t('the summary of a person with no active desk says so instead of printing nothing',
  personSummary(grouped.find((g) => g.profileId === 'p3')).length > 0
  && personSummary(grouped.find((g) => g.profileId === 'p3')).includes('담당 없음'));
t('the summary of an active person names their desks',
  personSummary(grouped[0]) === CLASS_LABELS.payout_due);

// ── who can open the console ───────────────────────────────────────────────────────────────────
t('active console operators are counted by PERSON, not by row',
  JSON.stringify(activeConsoleOperators(ROWS).sort()) === JSON.stringify(['p1', 'p2']),
  JSON.stringify(activeConsoleOperators(ROWS)));
t('an inactive payout_due row is not an operator',
  !activeConsoleOperators(ROWS).includes('p4'));

// ── the last-operator MIRROR ───────────────────────────────────────────────────────────────────
const ONE = [row('solo', 'payout_due', true, '혼자'), row('solo', 'return_strand', true, '혼자')];
t('with one console operator, turning them off is flagged',
  wouldStrandConsole(ONE, 'solo', 'payout_due', false) === true);
t('the flag is payout_due only — emptying another class is not a lockout (0084 §E)',
  wouldStrandConsole(ONE, 'solo', 'return_strand', false) === false);
t('turning someone ON is never flagged',
  wouldStrandConsole(ONE, 'solo', 'payout_due', true) === false);
t('with two console operators, neither is flagged',
  wouldStrandConsole(ROWS, 'p1', 'payout_due', false) === false
  && wouldStrandConsole(ROWS, 'p2', 'payout_due', false) === false);
t('a row that is ALREADY off is not flagged (the server does not refuse it either)',
  wouldStrandConsole(ROWS, 'p4', 'payout_due', false) === false);
t('a person with no row at all is not flagged',
  wouldStrandConsole(ONE, 'stranger', 'payout_due', false) === false);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
