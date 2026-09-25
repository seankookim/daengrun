// check-a11y-roles.mjs — tests of THE GATE ITSELF, run against the real script in a lab of
// fixture files (never against the live tree, which churns daily and would make these pins
// measure today's screens rather than the gate's rules).
//
// 🔴 WHY THIS FILE EXISTS, AND IT IS A THIRD PROPOSITION — not the gate's and not the chain's.
//    `check-a11y-roles` exists because the test chain cannot ask a `.tsx` route anything about
//    accessibility (measured 2026-09-23: re-planting a bare `<Pressable>` into `alerts.tsx` left
//    `npm test` byte-identical while the gate exited 1). That argument says nothing about whether
//    the GATE still fails on the trees it must. On 2026-09-25 codex measured that it did not:
//    removing the role from `owner/schedule.tsx`'s 다시 시도 button made v1 exit 1, and ALSO
//    adding a role to a different bare Pressable in the same file made **that same regression
//    exit 0** — the per-file count nets to zero, which v1's own header had named as a blind spot
//    and declined to close. `THE BALANCED MUTATION` below is that exact tree, and it is the
//    reason this file was written.
//
// 🔴 The propositions, each stated without reference to any mutation:
//   · A control that STOPS announcing itself fails the gate, whatever else changed in its file.
//   · A control that is FIXED obliges its ledger line to go — the ledger can only shrink.
//   · The ledger survives edits that move lines, and says so loudly when a fingerprint genuinely
//     moves (a rename), rather than going quietly green or quietly red.
//   · A `<Pressable` written inside a COMMENT is not an element. (Documenting a fix and failing
//     to make it must not look identical — the standing comment-quoting law.)
//   · A file the parser cannot read FAILS. A gate that skips what it could not read reports
//     「nothing found」 for a file nobody checked.
//   · `--rewrite-baseline` can shrink the ledger and can never grow it, so re-emitting after a
//     rename is safe and cannot be used to absorb new debt.
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const APP = path.join(__dirname, '..');
const GATE = path.join(APP, 'scripts', 'check-a11y-roles.mjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the lab ───────────────────────────────────────────────────────────────────────────────────
const labs = [];
function makeLab(files) {
  const lab = fs.mkdtempSync(path.join(os.tmpdir(), 'a11y-gate-'));
  labs.push(lab);
  fs.mkdirSync(path.join(lab, 'app'));
  fs.mkdirSync(path.join(lab, 'src'));
  fs.mkdirSync(path.join(lab, 'scripts'));
  fs.copyFileSync(GATE, path.join(lab, 'scripts', 'check-a11y-roles.mjs'));
  // so `@babel/parser` resolves from the copied script; `walk()` never descends here.
  fs.symlinkSync(path.join(APP, 'node_modules'), path.join(lab, 'node_modules'));
  for (const [rel, body] of Object.entries(files)) fs.writeFileSync(path.join(lab, rel), body, 'utf8');
  return lab;
}
const ledgerPath = (lab) => path.join(lab, 'scripts', 'check-a11y-roles-baseline.txt');
const readLedger = (lab) => fs.readFileSync(ledgerPath(lab), 'utf8');
const writeLedger = (lab, body) => fs.writeFileSync(ledgerPath(lab), body, 'utf8');
const readFile = (lab, rel) => fs.readFileSync(path.join(lab, rel), 'utf8');

/** Edit a lab file, asserting the edit LANDED — a mutation that did not land would otherwise be
 *  recorded as 「the gate held」, which is the whole §sed-exits-0 family. */
function edit(lab, rel, old, next) {
  const full = path.join(lab, rel);
  const src = fs.readFileSync(full, 'utf8');
  if (src.split(old).length - 1 !== 1) throw new Error(`mutation target not unique in ${rel}: ${old}`);
  fs.writeFileSync(full, src.replace(old, next), 'utf8');
  if (!fs.readFileSync(full, 'utf8').includes(next)) throw new Error(`mutation did not land in ${rel}`);
}

function run(lab, args = []) {
  const r = spawnSync(process.execPath, [path.join(lab, 'scripts', 'check-a11y-roles.mjs'), ...args], { encoding: 'utf8' });
  return { code: r.status, out: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}

// ── the fixtures ──────────────────────────────────────────────────────────────────────────────
// `app/screen.tsx`: one control that ANNOUNCES itself, two that do not, in one component, plus a
// third bare one in a differently-named ancestor. That shape is the whole point — the balanced
// mutation needs a roled element to break and a bare element to fix, in ONE file.
const SCREEN = `import { Pressable, Text, View } from 'react-native';

export default function Screen() {
  return (
    <View>
      <Pressable onPress={retry} accessibilityRole="button">
        <Text>다시 시도</Text>
      </Pressable>
      <Pressable onPress={openOne}>
        <Text>첫째</Text>
      </Pressable>
      <Pressable onPress={openTwo}>
        <Text>둘째</Text>
      </Pressable>
    </View>
  );
}

export const Chip = () => (
  <Pressable onPress={pick}>
    <Text>칩</Text>
  </Pressable>
);
`;

const THING = `import { Pressable, Text } from 'react-native';

export function Thing() {
  return (
    <Pressable onPress={go}>
      <Text>하나</Text>
    </Pressable>
  );
}
`;

// A file with NOTHING in the ledger, so anything the gate wrongly counts here fails loudly as new
// debt rather than hiding inside an existing allowance.
const QUIET = `import { Pressable, Text } from 'react-native';

export function Quiet() {
  return (
    <Pressable onPress={ok} accessibilityRole="button">
      <Text>확인</Text>
    </Pressable>
  );
}
`;

const FILES = { 'app/screen.tsx': SCREEN, 'app/quiet.tsx': QUIET, 'src/thing.tsx': THING };
const HEADER = '# lab ledger for a11y-gate.test.cjs — fixtures only, never the live tree.\n';
const SEED_V1 = 'app/screen.tsx 3\nsrc/thing.tsx 1';

/** A lab whose ledger has been migrated from v1 counts to v2 fingerprints — the same one-time
 *  path the real ledger took on 2026-09-25, so this bootstrap is itself the migration under test. */
function seededLab(files = FILES) {
  const lab = makeLab(files);
  writeLedger(lab, `${HEADER}\n${SEED_V1}\n`);
  const r = run(lab, ['--rewrite-baseline']);
  if (r.code !== 0) throw new Error(`lab bootstrap failed (exit ${r.code}):\n${r.out}`);
  return lab;
}
const ledgerLines = (lab) => readLedger(lab).split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));

try {
  // ── the migration itself, and the CONTROL: the lab can be green ─────────────────────────────
  {
    const lab = seededLab();
    const lines = ledgerLines(lab);
    t('migration · v1 per-file counts (3 + 1) become exactly 4 per-element fingerprints',
      lines.length === 4, JSON.stringify(lines));
    t('migration · every emitted line is `path :: ancestor :: 8-hex :: n`',
      lines.every((l) => /^\S+ :: \S+ :: [0-9a-f]{8} :: \d+$/.test(l)), JSON.stringify(lines));
    t('migration · the ancestor is the nearest NAMED one, not the file and not an anonymous arrow',
      lines.some((l) => l.includes(' :: Screen :: ')) && lines.some((l) => l.includes(' :: Chip :: '))
      && lines.some((l) => l.includes(' :: Thing :: ')), JSON.stringify(lines));
    const r = run(lab);
    t('🔴 CONTROL · the gate PASSES on the emitted ledger (a control that cannot pass is as useless as one that cannot fail)',
      r.code === 0, `exit ${r.code}: ${r.out}`);
    t('control · and it says how many role-less elements it is holding',
      /역할 없는 탭 요소 4건/.test(r.out), r.out.trim());
  }

  // ── the crude-vs-careful control, carried WITH the gate rather than only written down ───────
  {
    const lab = seededLab();
    const raw = Object.values(FILES).join('\n').match(/<Pressable/g).length;
    const r = run(lab);
    const parsed = Number(/전체 탭 요소 (\d+)건/.exec(r.out)?.[1]);
    // The load-bearing half is the EQUALITY (a parser that dropped elements would read low); the
    // literal 6 is only a fixture-drift guard, so that a shrunken fixture cannot make the
    // equality trivially true.
    t('🔴 crude-vs-careful · the parsed element population EQUALS the crudest possible count (`<Pressable` occurrences)',
      parsed === raw && raw === 6, `raw ${raw} · parsed ${parsed}`);
  }

  // ── THE BALANCED MUTATION — the reproduction of codex #4 ────────────────────────────────────
  {
    const lab = seededLab();
    edit(lab, 'app/screen.tsx', '<Pressable onPress={retry} accessibilityRole="button">', '<Pressable onPress={retry}>');
    edit(lab, 'app/screen.tsx', '<Pressable onPress={openOne}>', '<Pressable onPress={openOne} accessibilityRole="button">');
    const r = run(lab);
    t('🔴 THE BALANCED MUTATION · a control that stopped announcing itself FAILS the gate even though another was fixed in the same file (v1 exited 0 here)',
      r.code === 1, `exit ${r.code}: ${r.out}`);
    t('🔴 the balanced mutation · the per-file COUNT is unchanged — exactly one new element and exactly one stale line, which is why a count-keyed ledger could not see it',
      /대장에 없는[^\n]*1건/.test(r.out) && /대장이 낡았다 1건/.test(r.out), r.out);
    t('the balanced mutation · the regressed element is named by file and LINE, so the fix is one jump',
      /app\/screen\.tsx:6/.test(r.out), r.out);
  }

  // ── each half of the rule, on its own ───────────────────────────────────────────────────────
  {
    const lab = seededLab();
    const target = ledgerLines(lab).find((l) => l.startsWith('src/thing.tsx'));
    writeLedger(lab, readLedger(lab).split('\n').filter((l) => l.trim() !== target).join('\n'));
    const r = run(lab);
    t('new debt · a bare element with NO ledger line fails, and the ledger line it wanted is printed verbatim',
      r.code === 1 && r.out.includes('대장에 없는') && r.out.includes(target), `exit ${r.code}: ${r.out}`);
    t('new debt · and it is NOT reported as a stale line (the two halves are distinguishable)',
      !/대장이 낡았다/.test(r.out), r.out);
  }
  {
    const lab = seededLab();
    edit(lab, 'src/thing.tsx', '<Pressable onPress={go}>', '<View onPress={go}>');
    edit(lab, 'src/thing.tsx', '</Pressable>', '</View>');
    const r = run(lab);
    t('stale · an element that is GONE leaves its ledger line failing until someone deletes it (the ledger can only shrink)',
      r.code === 1 && /대장이 낡았다 1건/.test(r.out), `exit ${r.code}: ${r.out}`);
    t('stale · and it is NOT reported as new debt',
      !/대장에 없는/.test(r.out), r.out);
  }
  {
    const lab = seededLab();
    edit(lab, 'app/screen.tsx', '<Pressable onPress={openTwo}>', '<Pressable onPress={openTwo} accessibilityRole="button">');
    const r = run(lab);
    t('stale · FIXING a control is also a stale line — the ledger must be lowered in the same commit',
      r.code === 1 && /대장이 낡았다 1건/.test(r.out), `exit ${r.code}: ${r.out}`);
  }

  // ── the stability the fingerprint was chosen FOR, and the churn it deliberately does not survive ──
  {
    const lab = seededLab();
    edit(lab, 'app/screen.tsx', 'export default function Screen() {', `${'// churn\n'.repeat(30)}export default function Screen() {`);
    const r = run(lab);
    t('🔴 stability · 30 lines inserted above every element changes NOTHING — a `path:line` ledger would have gone fully red here, which is how a gate earns --no-verify',
      r.code === 0, `exit ${r.code}: ${r.out}`);
  }
  {
    const lab = seededLab();
    edit(lab, 'src/thing.tsx', 'export function Thing() {', 'export function Widget() {');
    const r = run(lab);
    t('trade-off · renaming the enclosing component MOVES the fingerprint and the gate says so (one stale + one new), rather than going quietly green',
      r.code === 1 && /대장이 낡았다 1건/.test(r.out) && /대장에 없는[^\n]*1건/.test(r.out), `exit ${r.code}: ${r.out}`);
    const rw = run(lab, ['--rewrite-baseline']);
    t('trade-off · and `--rewrite-baseline` repairs it in place, because the count did not grow',
      rw.code === 0 && ledgerLines(lab).length === 4, `exit ${rw.code}: ${rw.out}`);
    t('trade-off · after the re-emit the gate is green again',
      run(lab).code === 0);
  }

  // ── `--rewrite-baseline` can shrink and can never grow ──────────────────────────────────────
  {
    const lab = seededLab();
    edit(lab, 'app/quiet.tsx', '<Pressable onPress={ok} accessibilityRole="button">', '<Pressable onPress={ok}>');
    const r = run(lab);
    t('new debt · a brand-new role-less element in a file with no ledger lines at all fails',
      r.code === 1 && /app\/quiet\.tsx/.test(r.out), `exit ${r.code}: ${r.out}`);
    const rw = run(lab, ['--rewrite-baseline']);
    t('🔴 --rewrite-baseline · REFUSES to grow the ledger, so re-emitting can never be used to absorb new debt',
      rw.code === 1 && /늘어날 수 없다/.test(rw.out), `exit ${rw.code}: ${rw.out}`);
    t('--rewrite-baseline · and it leaves the ledger untouched when it refuses',
      ledgerLines(lab).length === 4, JSON.stringify(ledgerLines(lab)));
  }
  {
    const lab = seededLab();
    edit(lab, 'app/screen.tsx', '<Pressable onPress={openTwo}>', '<Pressable onPress={openTwo} accessibilityRole="button">');
    const rw = run(lab, ['--rewrite-baseline']);
    t('--rewrite-baseline · SHRINKS freely (4 → 3) once a control has been fixed',
      rw.code === 0 && ledgerLines(lab).length === 3, `exit ${rw.code}: ${JSON.stringify(ledgerLines(lab))}`);
    t('--rewrite-baseline · keeps the file\'s prose header rather than overwriting it with its own',
      readLedger(lab).startsWith(HEADER.trim()), readLedger(lab).slice(0, 60));
  }

  // ── the escape hatch, both ways ─────────────────────────────────────────────────────────────
  {
    const lab = seededLab();
    const target = ledgerLines(lab).find((l) => l.startsWith('src/thing.tsx'));
    edit(lab, 'src/thing.tsx', '<Pressable onPress={go}>', '<Pressable // a11y-role-ok: 제스처 캐처\n      onPress={go}>');
    writeLedger(lab, readLedger(lab).split('\n').filter((l) => l.trim() !== target).join('\n'));
    const r = run(lab);
    t('hatch · `// a11y-role-ok: <reason>` exempts the element permanently (and its ledger line then has to go)',
      r.code === 0 && /마커 면제 1/.test(r.out), `exit ${r.code}: ${r.out}`);
  }
  {
    const lab = seededLab();
    edit(lab, 'src/thing.tsx', '<Pressable onPress={go}>', '<Pressable // a11y-role-ok:\n      onPress={go}>');
    const r = run(lab);
    t('hatch · a BARE marker with no reason is refused — an unexplained exemption is how a ledger of debt turns into a list nobody reads',
      r.code === 1 && /이유 없는 a11y-role-ok 1건/.test(r.out), `exit ${r.code}: ${r.out}`);
  }

  // ── the controls that must NOT redden ───────────────────────────────────────────────────────
  {
    const lab = seededLab();
    edit(lab, 'app/quiet.tsx', 'export function Quiet() {',
      '// <Pressable onPress={ok}> ← quoted, not code\nexport function Quiet() {');
    const r = run(lab);
    t('🔴 CONTROL · a `<Pressable` written inside a COMMENT is not an element — documenting a fix and failing to make it must not look identical to the gate',
      r.code === 0, `exit ${r.code}: ${r.out}`);
  }

  // ── a file the parser cannot read FAILS, loudly ─────────────────────────────────────────────
  {
    const lab = seededLab();
    fs.writeFileSync(path.join(lab, 'app', 'broken.tsx'), 'export function B() { return <View ; }\n', 'utf8');
    const r = run(lab);
    t('🔴 unreadable · a file the parser cannot read FAILS by name — a gate that skips it reports 「nothing found」 for a file nobody checked',
      r.code === 1 && /파싱 실패 app\/broken\.tsx/.test(r.out), `exit ${r.code}: ${r.out}`);
    const rw = run(lab, ['--rewrite-baseline']);
    t('unreadable · and the ledger cannot be re-emitted over a file that failed to parse',
      rw.code === 1, `exit ${rw.code}: ${rw.out}`);
  }

  // ── a ledger left in v1 format is a loud migration error, never a silent pass ───────────────
  {
    const lab = makeLab(FILES);
    writeLedger(lab, `${HEADER}\n${SEED_V1}\n`);
    const r = run(lab);
    t('migration · a ledger still in v1 per-file-count format FAILS and names the command that migrates it',
      r.code === 1 && /v1 형식/.test(r.out) && /--rewrite-baseline/.test(r.out), `exit ${r.code}: ${r.out}`);
  }
  {
    const lab = makeLab(FILES);
    writeLedger(lab, `${HEADER}\nthis is not a ledger line at all\n`);
    const r = run(lab);
    t('ledger · an unparseable ledger line FAILS rather than being skipped',
      r.code === 1 && /형식이 틀렸다/.test(r.out), `exit ${r.code}: ${r.out}`);
  }
} finally {
  for (const lab of labs) {
    if (!lab.includes('a11y-gate-') || !lab.startsWith(os.tmpdir())) continue;
    // Unlink the node_modules symlink EXPLICITLY before removing the tree — never risk a
    // recursive delete walking into the real one.
    try { fs.unlinkSync(path.join(lab, 'node_modules')); } catch { /* already gone */ }
    fs.rmSync(lab, { recursive: true, force: true });
  }
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
