// [0214 §A/§B] The `kind='system'` title ledger, re-derived from the WRITERS on every run.
//
//   node test/ops-system-titles.test.cjs          (or: bash test/run-ops-system-titles-tests.sh)
//
// ═══ WHY THIS FILE EXISTS, AND WHY IT IS ON THE CLIENT SIDE ════════════════════════════════════
// 0210 §B moved `kind='system'` out of the undisableable `safety` category on an enumeration of
// FOUR titles. The measured set is ELEVEN, and `0210-O2`'s four-element array could not see the
// other seven — it would have stayed green as the set grew (executing review 2026-09-23, F1).
// 0214 §A puts the eleven in the database as `_noti_ops_titles()` and §B makes the classifier's
// `system` arm consult it, so a title in the ledger is the operator's category and anything else
// falls to `booking`.
//
// 🔴 **The SQL suite cannot close this loop and says so in its own header.** 245 `0214-T1` compares
// the deployed array against a list spelled out in the suite — two copies of one list, which is the
// same claim counted twice — and `0214-T4` can only see DEPLOYED FUNCTIONS, so it is structurally
// blind to `supabase/functions/_shared/ops.ts`, where FIVE of the eleven are written. Five of
// eleven invisible to every SQL pin is what makes this file load-bearing rather than belt-and-braces.
//
// This one re-derives the set from the writers' own source — every migration, plus `ops.ts` — and
// compares it to the ledger as 0214 spells it. A new `system` writer in a later migration, or a
// sixth entry in `ops.ts`'s `COPY`, reddens here until its title is ledgered.
//
// ═══ THE DERIVATION, AND THE THREE THINGS THAT MAKE IT NOT A GREP ══════════════════════════════
//  ① **Comments are stripped, quote-aware.** A comment that quotes a removed insert matches every
//     grep that hunts for that insert (the standing law), and `_noti_ops_titles()` itself carries a
//     trailing `-- writer:line` comment on every entry. A naive line-prefix stripper leaves those,
//     and a naive `--`-to-EOL stripper would eat the inside of any string containing `--`.
//  ② **Latest declaration wins.** `sweep_run_end_recovery` is declared in five migrations and
//     `ops_payouts_stuck_sweep` in three; only the last one is deployed. Counting every declaration
//     would still be CORRECT for titles today (control ② below measures exactly that) but would
//     start over-reporting the moment a re-declaration retires a title.
//  ③ **`'system'` is matched with the cast OPTIONAL.** `0118:674` writes a bare `'system'` literal
//     with an implicit cast, which is precisely why a `'system'::noti_kind` grep misses it — the
//     miss that produced the four-title enumeration in the first place.
//
// ═══ THE CONTROLS ══════════════════════════════════════════════════════════════════════════════
//  ① The derivation must find a NON-EMPTY set in each source. An extractor that silently stopped
//     matching would otherwise agree with a ledger it never read — a zero from a filtered sweep is
//     the easiest false negative there is, and it reads as good news.
//  ② The crude counterpart runs beside it and BOTH directions are explained: every-declaration vs
//     latest-only must produce the SAME title set (more sites, same titles), and the SQL-only sweep
//     must be exactly the set minus `ops.ts`'s five.
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const MIG = path.resolve(__dirname, '../../supabase/migrations');
const OPS_TS = path.resolve(__dirname, '../../supabase/functions/_shared/ops.ts');
// [0224] The ledger and the classifier are read out of their LATEST declarations (③ below), not
// out of 0214 by file name. A new `system` writer can only be ledgered by RE-DECLARING
// `_noti_ops_titles()` in a new migration (a landed one is never edited), so a file-name read
// would have reddened on every correct ledger change forever — or, worse, stayed green on a
// superseded array. Latest-wins is the rule ② already applies to the writers.

// ── ① the quote-aware comment stripper ────────────────────────────────────────────────────────
// Walks the text tracking single-quote state (with SQL's `''` escape) and drops `--` to end of
// line only when it is genuinely outside a string. A `--` inside a Korean sentence in a literal
// stays; a `-- writer:line` note after a literal goes.
function stripSqlComments(src) {
  let out = '', i = 0, inStr = false;
  while (i < src.length) {
    const c = src[i];
    if (inStr) {
      out += c;
      if (c === "'") {
        if (src[i + 1] === "'") { out += "'"; i += 2; continue; }
        inStr = false;
      }
      i++;
      continue;
    }
    if (c === "'") { inStr = true; out += c; i++; continue; }
    if (c === '-' && src[i + 1] === '-') {
      while (i < src.length && src[i] !== '\n') i++;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

/** Every `'...'` literal in a slice of SQL, `''` unescaped. */
function sqlLiterals(slice) {
  const out = [];
  let i = 0;
  while (i < slice.length) {
    if (slice[i] !== "'") { i++; continue; }
    i++;
    let s = '';
    while (i < slice.length) {
      if (slice[i] === "'") {
        if (slice[i + 1] === "'") { s += "'"; i += 2; continue; }
        i++; break;
      }
      s += slice[i]; i++;
    }
    out.push(s);
  }
  return out;
}

// ── ② the writers ─────────────────────────────────────────────────────────────────────────────
const files = fs.readdirSync(MIG).filter((f) => /^\d{4}_.*\.sql$/.test(f)).sort();
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** name -> { file, body }, LATEST declaration wins (files are numerically sorted). */
function declarations() {
  const latest = new Map();
  for (const f of files) {
    const src = stripSqlComments(fs.readFileSync(path.join(MIG, f), 'utf8'));
    const re = /create\s+(?:or\s+replace\s+)?function\s+([a-zA-Z0-9_]+)\s*\(/gi;
    const marks = [];
    let m;
    while ((m = re.exec(src))) marks.push({ name: m[1], at: m.index });
    for (let i = 0; i < marks.length; i++) {
      latest.set(marks[i].name, {
        file: f,
        body: src.slice(marks[i].at, i + 1 < marks.length ? marks[i + 1].at : src.length),
      });
    }
  }
  return latest;
}

/** Every `kind='system'` title written inside one comment-stripped function body. */
function systemTitlesIn(body) {
  const out = [];
  let idx = 0;
  for (;;) {
    const at = body.indexOf('insert into notifications', idx);
    if (at < 0) break;
    idx = at + 1;
    const end = body.indexOf(';', at);
    const stmt = body.slice(at, end < 0 ? body.length : end).replace(/\s+/g, ' ');
    // ③ the cast is OPTIONAL — 0118 writes a bare literal.
    const sm = /'system'(?:::noti_kind)?\s*,\s*([^,]+),/.exec(stmt);
    if (!sm) continue;
    const expr = sm[1].trim();
    if (expr.charAt(0) === "'") { out.push(sqlLiterals(expr)[0]); continue; }
    // a plpgsql `constant text` holding the title — resolve it in the same body
    const cm = new RegExp(esc(expr) + "\\s+constant\\s+text\\s*:=\\s*('(?:[^']|'')*')").exec(body);
    out.push(cm ? sqlLiterals(cm[1])[0] : 'UNRESOLVED(' + expr + ')');
  }
  return out;
}

const latest = declarations();
const sqlWriters = new Map();      // title -> [function names]
for (const [name, d] of latest) {
  for (const title of systemTitlesIn(d.body)) {
    if (!sqlWriters.has(title)) sqlWriters.set(title, []);
    sqlWriters.get(title).push(name + ' (' + d.file + ')');
  }
}

// `_shared/ops.ts`: `notifyOps` writes `kind: "system"` for EVERY entry of COPY plus generic().
const opsSrc = fs.readFileSync(OPS_TS, 'utf8')
  .split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
const edgeTitles = [...opsSrc.matchAll(/title:\s*"([^"]+)"/g)].map((m) => m[1]);

const derived = new Set([...sqlWriters.keys(), ...edgeTitles]);

// ── ③ the ledger, read out of its LATEST declaration (0214 §A, re-declared since by 0224 §G) ───
const ledgerDecl = latest.get('_noti_ops_titles');
const LEDGER_FILE = ledgerDecl ? ledgerDecl.file : null;
const ledgerBody = ledgerDecl ? ledgerDecl.body : '';
const arrStart = ledgerBody.indexOf('array[');
const arrEnd = ledgerBody.indexOf(']::text[]', arrStart);
const ledger = arrStart >= 0 && arrEnd > arrStart ? sqlLiterals(ledgerBody.slice(arrStart, arrEnd)) : [];
console.log(`  (ledger read from ${LEDGER_FILE})`);

// ═══ control ① — the derivation found something in every source ════════════════════════════════
t('CONTROL: the migration sweep found SQL `system` writers at all (an extractor that stopped matching would agree with a ledger it never read)',
  sqlWriters.size > 0, 'sqlWriters=' + sqlWriters.size);
t('CONTROL: `_shared/ops.ts` yielded titles (five of the eleven live there and NO SQL pin can see them)',
  edgeTitles.length > 0, 'edgeTitles=' + edgeTitles.length);
t('CONTROL: the latest `_noti_ops_titles()` array was parsed out of its migration',
  ledger.length > 0, 'file=' + LEDGER_FILE + ' ledger=' + JSON.stringify(ledger));
t('CONTROL: no title failed to resolve to a literal (a plpgsql constant this extractor cannot follow would be silent otherwise)',
  ![...derived].some((x) => x.startsWith('UNRESOLVED(')),
  [...derived].filter((x) => x.startsWith('UNRESOLVED(')).join(', '));

// ═══ the drift gate, both directions ═══════════════════════════════════════════════════════════
for (const title of derived) {
  t(`every writer's title is LEDGERED: 「${title}」`,
    ledger.includes(title),
    `written by ${sqlWriters.get(title) ? sqlWriters.get(title).join(' + ') : '_shared/ops.ts notifyOps'} `
    + 'but absent from _noti_ops_titles() — a system row with this title now classifies as `booking`, '
    + 'so an operator who turned `booking` off would not be pushed. Add it to a new re-declaration of '
    + '_noti_ops_titles() (latest now: ' + LEDGER_FILE + '), to 245\'s OPS_TITLES, and to SYSTEM_WRITERS '
    + 'if the writer is new.');
}
for (const title of ledger) {
  t(`every LEDGERED title still has a writer: 「${title}」`,
    derived.has(title),
    'no `kind=system` writer in any latest function declaration or in _shared/ops.ts writes this '
    + 'title any more — remove it from _noti_ops_titles() rather than leaving a dead entry, or '
    + 'find out which re-declaration dropped it');
}
t('the ledger holds no duplicates',
  new Set(ledger).size === ledger.length, JSON.stringify(ledger));

// ═══ control ② — the crude counterpart, both directions explained ══════════════════════════════
{
  // (a) EVERY declaration, superseded ones included. More sites, and it must be the SAME titles:
  //     a difference means a re-declaration retired or introduced a title, which is exactly the
  //     event the latest-wins rule exists to track and which nobody should discover by accident.
  const crude = new Set();
  let crudeSites = 0, refinedSites = 0;
  for (const f of files) {
    const src = stripSqlComments(fs.readFileSync(path.join(MIG, f), 'utf8'));
    const re = /create\s+(?:or\s+replace\s+)?function\s+([a-zA-Z0-9_]+)\s*\(/gi;
    const marks = [];
    let m;
    while ((m = re.exec(src))) marks.push({ at: m.index });
    for (let i = 0; i < marks.length; i++) {
      const body = src.slice(marks[i].at, i + 1 < marks.length ? marks[i + 1].at : src.length);
      for (const ti of systemTitlesIn(body)) { crude.add(ti); crudeSites++; }
    }
  }
  for (const [, d] of latest) refinedSites += systemTitlesIn(d.body).length;

  const onlyCrude = [...crude].filter((x) => !sqlWriters.has(x));
  const onlyRefined = [...sqlWriters.keys()].filter((x) => !crude.has(x));
  t('CONTROL ②a: latest-declaration-wins drops SITES but loses no TITLE (both directions accounted for)',
    onlyCrude.length === 0 && onlyRefined.length === 0,
    `crude=${crudeSites} sites/${crude.size} titles · refined=${refinedSites} sites/${sqlWriters.size} titles`
    + ` · only-crude=[${onlyCrude.join(', ')}] only-refined=[${onlyRefined.join(', ')}]`);
  t('CONTROL ②a: the crude sweep really does see MORE sites (otherwise the two are the same query and this control is the first one printed twice)',
    crudeSites > refinedSites, `crude=${crudeSites} refined=${refinedSites}`);

  // (b) the SQL-only view is the whole set minus ops.ts's — i.e. the five edge titles are genuinely
  //     invisible to any migration sweep, which is the argument for this file existing.
  const sqlOnlyMissing = edgeTitles.filter((x) => !sqlWriters.has(x));
  t('CONTROL ②b: none of `_shared/ops.ts`\'s titles is reachable from a migration sweep',
    sqlOnlyMissing.length === edgeTitles.length,
    `${edgeTitles.length - sqlOnlyMissing.length} of ${edgeTitles.length} edge titles also appear in SQL`);
}

// ═══ the ledger is LOAD-BEARING in the deployed classifier, not decoration ══════════════════════
{
  // Without this, every arm above could pass while `_noti_push_category` still keyed on the kind
  // alone — a ledger nothing consults, which is a list in a costume. Comments are stripped first:
  // 0214's own header explains the arm at length. [0224] Read from the classifier's LATEST
  // declaration, for ③'s reason.
  const clsDecl = latest.get('_noti_push_category');
  const cls = clsDecl ? clsDecl.body : '';
  const body = cls.slice(0, cls.indexOf('$$;') + 3).replace(/\s+/g, ' ');
  // ⚠ The arms are PARSED rather than matched as one literal line, so writing the two conjuncts in
  // the other order — a legitimate, behaviour-identical respelling — does not redden this file. A
  // gate that cries on correct code is `--no-verify`'d within a day and protects nothing after.
  const arms = body.split(/\bwhen\b/).slice(1).map((chunk) => {
    const m = /then\s*'([a-z]+)'/.exec(chunk);
    return m ? { cond: chunk.slice(0, m.index), to: m[1] } : null;
  }).filter(Boolean);
  const ledgered = arms.findIndex((a) => /p_kind = 'system'/.test(a.cond) && /_noti_ops_titles\(\)/.test(a.cond));
  const other = arms.findIndex((a) => /p_kind = 'system'/.test(a.cond) && !/_noti_ops_titles\(\)/.test(a.cond));
  const urgent = arms.findIndex((a) => /_noti_urgent_noti_titles\(\)/.test(a.cond));
  t('the classifier consults the ledger (the `system` arm is title-keyed, not kind-keyed)',
    ledgered >= 0 && arms[ledgered].to === 'ops', body.slice(0, 400));
  t('an unledgered `system` title falls to `booking` — the least-privileged DISABLEABLE category, never to `ops` and never to `safety`',
    other >= 0 && arms[other].to === 'booking', body.slice(0, 400));
  t('the ledgered arm is read BEFORE the catch-all `system` arm (below it, every system row would be booking and the ops column would gate nothing)',
    ledgered >= 0 && other >= 0 && ledgered < other, `ledgered@${ledgered} other@${other}`);
  t('the urgent-title arm still sits ABOVE both `system` arms (an ops writer borrowing an urgent title stays always-on)',
    urgent >= 0 && ledgered >= 0 && urgent < ledgered && urgent < other,
    `urgent@${urgent} ledgered@${ledgered} other@${other}`);
}

// ═══ `notifyOps` really does write `kind: "system"` — the premise of the ops.ts half ════════════
t('every `_shared/ops.ts` title above is written as kind="system" by notifyOps',
  /kind:\s*"system"/.test(opsSrc),
  'notifyOps no longer writes kind="system" — if that is deliberate, the five ops.ts titles leave the ledger');
t('`_shared/ops.ts` addresses the OPS ROSTER, which is what makes these titles `ops` rather than a consumer category',
  /ops_recipients_for/.test(opsSrc) && /OPS_PROFILE_ID/.test(opsSrc));

console.log(`\n${pass} pass / ${fail} fail`);
if (fail > 0) process.exit(1);
