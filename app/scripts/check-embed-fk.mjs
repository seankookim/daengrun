#!/usr/bin/env node
// PostgREST embed-FK check — catches the "ambiguous join kills the whole SELECT" class at commit time.
// Run: node scripts/check-embed-fk.mjs  (from app/) — a commit gate alongside tsc, check-rpc and
// check-route-native-imports.
//
// WHY (2026-08-20, measured). `bookings` references `routes` TWICE:
//   · `route_id`             (0001_init.sql:169)
//   · `recommended_route_id` (0082_route_ladder.sql:143)
// So `.select('… routes(name) …')` gives PostgREST no way to pick an FK; it refuses the request
// with PGRST201 and returns ZERO rows. Not a partial failure — the entire query dies.
//
// The reason this gate exists is not the bug itself, it is why nobody saw it:
//   · On 2026-08-19 commit 4141efc knew about this class and fixed five of six sites. One survived
//     (REQ_SELECT in api.ts).
//   · That surviving site was the nomination (runner_pending) leg of the runner inbox, and that
//     leg's error is swallowed ON PURPOSE — a resilience choice so a dead open pool cannot take
//     nomination down with it (see the `[내성]` comment in api.ts).
//   · Result: the runner inbox looked normal while nomination had NEVER worked in production.
// Instead of asking a human to remember all six sites, the build now fails the moment a seventh
// appears.
//
// How to fix a hit: name the FK — `routes!bookings_route_id_fkey(name)`.
// (For the recommendation column, `routes!bookings_recommended_route_id_fkey(...)`.)
//
// The scope is deliberately narrow: only AMBIGUOUS pairs are checked. Single-FK embeds (dogs,
// runners, runs …) need no FK name, and warning about them would make this gate noise, which is
// how gates get ignored.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const appRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const srcDir = join(appRoot, 'src');
const routesDir = join(appRoot, 'app');

// An ambiguous embed = a parent table that references the child table more than once.
// ⚠ When adding an entry, cite migration:line. An entry without evidence gets deleted by the
// next person who reads this.
const AMBIGUOUS = [
  {
    parent: 'bookings',
    child: 'routes',
    fks: ['bookings_route_id_fkey', 'bookings_recommended_route_id_fkey'],
    why: 'route_id (0001:169) + recommended_route_id (0082:143)',
  },
];

const SRC_EXT = ['.tsx', '.ts'];
const walk = (dir, out = []) => {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (SRC_EXT.some((x) => p.endsWith(x))) out.push(p);
  }
  return out;
};

const files = [...walk(srcDir), ...walk(routesDir)];
const problems = [];

for (const file of files) {
  const text = readFileSync(file, 'utf8');
  const lines = text.split('\n');

  for (const rule of AMBIGUOUS) {
    // Embed syntax is `child(` or `child!fk(`. Only the `!`-qualified form is safe.
    // Select strings are sometimes split across lines or hoisted into consts, so this scans line
    // by line rather than parsing: this gate is a tripwire, not a proof.
    lines.forEach((line, i) => {
      // Skip comment lines so this file's own prose cannot redden itself.
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) return;
      // Match `routes(`, let `routes!...(` through.
      const bare = new RegExp(`(?<![!\\w])${rule.child}\\s*\\(`);
      if (!bare.test(line)) return;
      // Confirm it is roughly a select context — near `.select(`, a `_SELECT` or a `_COLS` const.
      const context = lines.slice(Math.max(0, i - 6), i + 1).join('\n');
      if (!/\.select\(|_SELECT|_COLS/.test(context)) return;
      problems.push({
        file: relative(appRoot, file),
        line: i + 1,
        rule,
        text: trimmed.slice(0, 120),
      });
    });
  }
}

if (problems.length > 0) {
  console.error('❌ Ambiguous PostgREST embed — the FK must be named (PGRST201 kills the whole SELECT)\n');
  for (const p of problems) {
    console.error(`  ${p.file}:${p.line}`);
    console.error(`    ${p.text}`);
    console.error(`    ${p.rule.parent} → ${p.rule.child}: ${p.rule.why}`);
    console.error(`    fix: ${p.rule.child}!${p.rule.fks[0]}(...)\n`);
  }
  process.exit(1);
}

console.log(`✅ No ambiguous embeds (${AMBIGUOUS.length} pair checked · ${files.length} files)`);
