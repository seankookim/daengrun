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
const fs = require('fs');
const path = require('path');
const {
  CONSOLE_CLASS, CLASS_LABELS, CLASS_ORDER, SELECTABLE_CLASSES, DORMANT_CLASSES, dormantNote,
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

// ══════════════════════════════════════════════════════════════════════════════════════════
// [gap sweep 2026-09-25 · ops-notifications-6] DORMANT CLASSES — a chip must not promise a page
// ══════════════════════════════════════════════════════════════════════════════════════════
// The roster sells thirteen alert classes and four have no emitter anywhere. The screen labels
// those four 「· 아직 발신 없음」 instead of hiding them (0208 §0c keeps every server class seatable).
// The set is not this file's opinion: it is re-derived from the EMITTERS on every run, and the
// comparison is two-sided — an emitter landing for a dormant class reddens here (shrink the set), and
// a class that loses its last emitter reddens here too (grow it). Comments are stripped first, and a
// `/* … */` or `--` quoting an emitter must not count as one (the standing comment-matching law).
//
// Where the scan looks, and why exactly there:
//   · `supabase/functions/**` (not `_test/`) — `notifyOps(<db>, "<class>"` is the edge's only door
//     into `ops_recipients_for`. `_test/` is excluded because `ops_routing_test.ts` CALLS notifyOps
//     with dormant classes to test the router; a test exercising a class is not an emitter of it.
//   · `supabase/migrations/*.sql` — `ops_recipients_for('<class>'` literals, and the routing
//     constants `… constant text := '<class>'` that every 0182+ writer passes as `c_ops_class`.
//     0208's `c_classes` allowlist names every class in one array literal, which is exactly why a
//     bare-literal scan would be wrong: it would find all thirteen and call every class emitted.
// MIGRATIONS_DIR / FUNCTIONS_DIR point the scan at a copy — the only way to plant an emitter without
// editing a landed migration (CLAUDE.md: never edit a live migration, even transiently).
{
  const REPO = path.resolve(__dirname, '../..');
  const MIG = process.env.MIGRATIONS_DIR || path.join(REPO, 'supabase/migrations');
  const FNS = process.env.FUNCTIONS_DIR || path.join(REPO, 'supabase/functions');

  // quote-aware SQL stripper: `--` to end of line only OUTSIDE a string literal
  const stripSql = (src) => {
    let out = '', i = 0, inStr = false;
    while (i < src.length) {
      const c = src[i];
      if (inStr) {
        out += c;
        if (c === "'") { if (src[i + 1] === "'") { out += "'"; i += 2; continue; } inStr = false; }
        i++; continue;
      }
      if (c === "'") { inStr = true; out += c; i++; continue; }
      if (c === '-' && src[i + 1] === '-') { while (i < src.length && src[i] !== '\n') i++; continue; }
      out += c; i++;
    }
    return out;
  };
  // TS: block comments, then `//` to end of line when it is not inside a "…" / '…' / `…` string
  const stripTs = (src) => {
    let out = '', i = 0, q = null;
    while (i < src.length) {
      const c = src[i];
      if (q) { out += c; if (c === '\\') { out += src[i + 1] || ''; i += 2; continue; } if (c === q) q = null; i++; continue; }
      if (c === '"' || c === "'" || c === '`') { q = c; out += c; i++; continue; }
      if (c === '/' && src[i + 1] === '*') { const e = src.indexOf('*/', i + 2); i = e < 0 ? src.length : e + 2; continue; }
      if (c === '/' && src[i + 1] === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
      out += c; i++;
    }
    return out;
  };
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((d) => {
    const p = path.join(dir, d.name);
    if (d.isDirectory()) return d.name === '_test' || d.name === 'node_modules' ? [] : walk(p);
    return /\.ts$/.test(d.name) ? [p] : [];
  });

  const sqlFiles = fs.readdirSync(MIG).filter((f) => /^\d{4}_.*\.sql$/.test(f));
  const sql = sqlFiles.map((f) => stripSql(fs.readFileSync(path.join(MIG, f), 'utf8'))).join('\n');
  const tsFiles = walk(FNS);
  const ts = tsFiles.map((f) => stripTs(fs.readFileSync(f, 'utf8'))).join('\n');

  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const emittersIn = (cls, tsSrc, sqlSrc) => {
    const hits = [];
    if (new RegExp(`notifyOps\\(\\s*[A-Za-z_$][\\w$]*\\s*,\\s*"${esc(cls)}"`).test(tsSrc)) hits.push('notifyOps');
    if (new RegExp(`ops_recipients_for\\(\\s*'${esc(cls)}'`).test(sqlSrc)) hits.push('ops_recipients_for literal');
    if (new RegExp(`constant\\s+text\\s*:=\\s*'${esc(cls)}'`).test(sqlSrc)) hits.push('routing constant');
    return hits;
  };
  const emitters = (cls) => emittersIn(cls, ts, sql);

  // ── controls: the scan read something, and it SEES the emitters that exist ──
  t('CONTROL · the scan read migrations and edge sources (an extractor that read nothing would call every class dormant)',
    sqlFiles.length > 100 && tsFiles.length > 10, `sql=${sqlFiles.length} ts=${tsFiles.length}`);
  t('CONTROL · the scan finds a known edge emitter (late_comp_failed, cancel_owner.ts)',
    emitters('late_comp_failed').includes('notifyOps'), JSON.stringify(emitters('late_comp_failed')));
  t('CONTROL · the scan finds a known SQL emitter (payout_due)',
    emitters('payout_due').length > 0, JSON.stringify(emitters('payout_due')));
  // ⚠ This control reads a FIXTURE, not the live tree. Its first version asserted
  //   `emitters('charge_dispatch_stale').length === 0` on the live sources — the same variable,
  //   through the same operator, as the dormant pin below — and a planted emitter reddened BOTH, so
  //   it was the dormant pin printed twice (measured in this slice's battery, LAB-P5). What the
  //   control has to establish is independent of any class's current state: that an allowlist
  //   ARRAY literal is not read as an emitter while a real routing call is.
  {
    const FIXTURE_SQL = "c_classes constant text[] := array['payout_due', 'x_class'];\n"
      + "select * from ops_recipients_for('y_class');\n  c_ops_class constant text := 'z_class';";
    t('CONTROL · an allowlist array literal is NOT an emitter; a routing call and a routing constant ARE (fixture)',
      emittersIn('x_class', '', FIXTURE_SQL).length === 0
      && emittersIn('y_class', '', FIXTURE_SQL).includes('ops_recipients_for literal')
      && emittersIn('z_class', '', FIXTURE_SQL).includes('routing constant')
      && emittersIn('w_class', 'await notifyOps(db, "w_class", {});', '').includes('notifyOps'));
    t('CONTROL · the live tree really does carry the allowlist literal the fixture models (0208 §C)',
      /'charge_dispatch_stale'/.test(sql) && /'incident_waive_pending'/.test(sql));
  }
  t('CONTROL · a comment quoting an emitter does not count (the stripper is doing work)',
    stripTs('// notifyOps(db, "x")\n/* notifyOps(db, "x") */ const a = "//not-a-comment";').indexOf('notifyOps') < 0
    && stripTs('const a = "//not-a-comment";').includes('//not-a-comment')
    && stripSql("select 1; -- ops_recipients_for('x')\nselect '--kept';").indexOf('ops_recipients_for') < 0
    && stripSql("select '--kept';").includes('--kept'));

  // ── the set itself ──
  t('DORMANT_CLASSES ⊂ CLASS_LABELS (every dormant class is a real, seatable server class)',
    DORMANT_CLASSES.size > 0 && [...DORMANT_CLASSES].every((c) => Object.prototype.hasOwnProperty.call(CLASS_LABELS, c)),
    JSON.stringify([...DORMANT_CLASSES]));
  t('dormant classes stay SELECTABLE (0208 §0c: labelled, never hidden)',
    [...DORMANT_CLASSES].every((c) => SELECTABLE_CLASSES.includes(c)));
  for (const c of DORMANT_CLASSES) {
    t(`🔴 ${c} has NO emitter anywhere — if one landed, delete it from DORMANT_CLASSES`,
      emitters(c).length === 0, JSON.stringify(emitters(c)));
  }
  for (const c of CLASS_ORDER.filter((x) => !DORMANT_CLASSES.has(x))) {
    t(`${c} HAS an emitter — a class that lost its last one must join DORMANT_CLASSES`,
      emitters(c).length > 0, JSON.stringify(emitters(c)));
  }
  t('a dormant chip says so; an emitted class carries no suffix',
    [...DORMANT_CLASSES].every((c) => dormantNote(c) === ' · 아직 발신 없음')
    && CLASS_ORDER.filter((x) => !DORMANT_CLASSES.has(x)).every((c) => dormantNote(c) === '')
    && dormantNote('written_by_psql') === '');
}

// ── the screen actually renders the suffix, in both places a chip is drawn ─────────────────────
{
  const screen = fs.readFileSync(path.join(__dirname, '..', 'app', 'ops', 'roster.tsx'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  t('roster.tsx renders dormantNote on the person rows AND in the 운영자 추가 sheet',
    (screen.match(/\{classLabel\(c\)\}\{dormantNote\(c\)\}/g) || []).length === 1
    && /\{chipLabel\(c, busy\)\}\{busy \? '' : dormantNote\(c\)\}/.test(screen),
    'dormantNote is not rendered in both chip lists');
  t('…and VoiceOver hears it too (both chips\' accessibilityLabel carry it)',
    (screen.match(/accessibilityLabel=\{`\$\{classLabel\(c\)\}\$\{dormantNote\(c\)\}/g) || []).length === 2);
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
