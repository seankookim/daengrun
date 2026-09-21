// tab-parent.ts — tests run against the REAL compiled source (see run-tab-parent-tests.sh), not a
// retyped copy, plus a DRIFT GATE that reads `bottomnav.tsx` and the three route files as text.
//
// What this file is FOR: the failure it guards is silent in both directions. A parent path that
// stops being a tab path does not throw, does not fail tsc and does not fail any other gate — the
// dock simply goes back to having no selected tab, which is the exact defect (HIG N3) this module
// was added to fix and which nobody notices without opening the screen. And the mirror failure is
// worse: if `tabNeighbors` ever starts resolving parents too, a left-swipe on 알림 silently lands
// on 수익, a tab the person never chose.
//
// The mutations that redden it: point a parent at a path that is in neither tab array · point the
// owner's /cards at a runner-only tab · add a route to the map that IS a tab · make tabNeighbors
// call parentTabPath · drop <BottomNav> from one of the three screens (then the map's entry is
// fiction) · gate BottomNav's onPress on `active` instead of `here`.
const fs = require('fs');
const path = require('path');
const { TAB_PARENTS, parentTabPath } = require('./tab-parent.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the resolution itself ──────────────────────────────────────────────────────────────────────
t('/alerts resolves to 마이 for an owner', parentTabPath('/alerts', 'owner') === '/my', parentTabPath('/alerts', 'owner'));
t('/alerts resolves to 마이 for a runner', parentTabPath('/alerts', 'runner') === '/my', parentTabPath('/alerts', 'runner'));
t('/safety resolves to 마이 for an owner', parentTabPath('/safety', 'owner') === '/my');
t('/safety resolves to 마이 for a runner', parentTabPath('/safety', 'runner') === '/my');

// The one role split, and the reason this function takes a role at all: Sean deleted the runner's
// 마이 › 내 러닝 기록 row on 2026-08-11 and moved that door to runner home, so for a runner the hub
// that owns /cards is 홈. An owner's 마이 › 기록 row (my.tsx:203) is still there.
t('/cards resolves to 마이 for an owner (my.tsx keeps the owner 기록 row)',
  parentTabPath('/cards', 'owner') === '/my', parentTabPath('/cards', 'owner'));
t('/cards resolves to 러너 홈 for a runner (their 마이 row was deleted; home owns 내 기록)',
  parentTabPath('/cards', 'runner') === '/runner/home', parentTabPath('/cards', 'runner'));
t('the two roles genuinely DISAGREE on /cards — if they ever agree, the role argument is dead weight',
  parentTabPath('/cards', 'owner') !== parentTabPath('/cards', 'runner'));

// ── everything else resolves to null ───────────────────────────────────────────────────────────
// null is what keeps the dock from ever selecting two tabs: a real tab route must fall through to
// BottomNav's exact-path match, never also match a parent.
for (const p of ['/my', '/owner/home', '/runner/home', '/community', '/shop', '/owner/schedule',
  '/runner/requests', '/runner/calendar', '/runner/earnings']) {
  t(`${p} has no parent (it is a tab, or is not a dock screen)`, parentTabPath(p, 'owner') === null
    && parentTabPath(p, 'runner') === null, String(parentTabPath(p, 'owner')));
}
t('an unknown route has no parent', parentTabPath('/nope', 'owner') === null);
t('an empty pathname has no parent', parentTabPath('', 'runner') === null);
t('a route that merely CONTAINS a mapped path is not matched (exact keys only — /alerts/3 is not /alerts)',
  parentTabPath('/alerts/3', 'owner') === null, String(parentTabPath('/alerts/3', 'owner')));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIFT GATE — three artifacts, read as TEXT, compared in both directions
// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⚠ COMMENTS ARE STRIPPED FROM bottomnav.tsx BEFORE MATCHING. Its header documents this very
// mechanism and names every one of these paths in prose, so an un-stripped read would be satisfied
// by the explanation rather than by the code — the standing comment-quoting law, mechanical here
// rather than a note asking the next reader to be careful.
const stripTs = (src) => src
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n');

const appDir = path.join(__dirname, '..');
const navRaw = fs.readFileSync(path.join(appDir, 'src', 'components', 'bottomnav.tsx'), 'utf8');
const nav = stripTs(navRaw);

// ① the tab arrays, parsed out of bottomnav.tsx by name
const tabPaths = (name) => {
  const m = nav.match(new RegExp(`const ${name} = \\[([\\s\\S]*?)\\] as const;`));
  if (!m) return null;
  return [...m[1].matchAll(/path:\s*'([^']+)'/g)].map((x) => x[1]);
};
const OWNER = tabPaths('OWNER_TABS');
const RUNNER = tabPaths('RUNNER_TABS');
t('OWNER_TABS is parseable out of bottomnav.tsx (a missing array must fail LOUDLY, not read as "nothing to compare")',
  Array.isArray(OWNER) && OWNER.length > 0, JSON.stringify(OWNER));
t('RUNNER_TABS is parseable out of bottomnav.tsx',
  Array.isArray(RUNNER) && RUNNER.length > 0, JSON.stringify(RUNNER));

// ② every parent must be a real tab path FOR THAT ROLE. This is the arm that actually protects the
//    fix: a parent that is not in the array selects nothing and the dock is blank again.
if (Array.isArray(OWNER) && Array.isArray(RUNNER)) {
  const byRole = { owner: OWNER, runner: RUNNER };
  for (const [route, row] of Object.entries(TAB_PARENTS)) {
    for (const role of ['owner', 'runner']) {
      t(`${route}'s ${role} parent ${row[role]} is a real ${role} tab`,
        byRole[role].includes(row[role]),
        `tabs=${JSON.stringify(byRole[role])}`);
    }
  }
  // ③ the other direction: a mapped route must NOT itself be a tab, or the dock would match twice.
  for (const route of Object.keys(TAB_PARENTS)) {
    t(`${route} is not itself a tab path in either array (a tab needs no parent)`,
      !OWNER.includes(route) && !RUNNER.includes(route));
  }
}

// ④ tabNeighbors must stay exact-path. The swipe and the highlight are different questions, and
//    the cost of merging them is a gesture that lands on a tab the person never chose.
const neighborsBody = (() => {
  const i = nav.indexOf('export function tabNeighbors');
  if (i < 0) return null;
  const j = nav.indexOf('\n}', i);
  return j < 0 ? null : nav.slice(i, j);
})();
t('tabNeighbors is present in bottomnav.tsx', typeof neighborsBody === 'string', String(neighborsBody));
t('tabNeighbors does NOT consult parentTabPath — a swipe on a non-tab screen must go nowhere',
  typeof neighborsBody === 'string' && !neighborsBody.includes('parentTabPath'),
  String(neighborsBody));
t('tabNeighbors still returns [null, null] for a non-tab screen, in executable source',
  typeof neighborsBody === 'string' && /if \(i < 0\) return \[null, null\];/.test(neighborsBody));

// ⑤ BottomNav must gate NAVIGATION on the exact match and DRAW on the parent match. Gating the
//    press on `active` would make the highlighted tab a dead button on exactly the three screens
//    this module exists for.
t('BottomNav computes an exact-path `here` and an `active` that also accepts the parent',
  /const here = t\.path === pathname;/.test(nav) && /const active = here \|\| t\.path === parent;/.test(nav),
  'bottomnav.tsx');
t('the press handler gates on `here`, never on `active` (no dead tab on /alerts · /cards · /safety)',
  /onPress=\{\(\) => \{ if \(t\.path && !here\) router\.replace\(t\.path\); \}\}/.test(nav));
t('BottomNav actually calls parentTabPath in executable source (not only in a comment about it)',
  /const parent = parentTabPath\(/.test(nav) && navRaw.includes("from '../lib/tab-parent'"));

// ⑥ the map only makes sense for screens that DRAW the dock. A route here that stopped rendering
//    <BottomNav> would be an entry nothing can ever use — dead data dressed as a rule.
const FILES = { '/alerts': 'alerts.tsx', '/cards': 'cards.tsx', '/safety': 'safety.tsx' };
for (const [route, file] of Object.entries(TAB_PARENTS).map(([r]) => [r, FILES[r]])) {
  t(`${route} maps to a known route file`, typeof file === 'string', String(file));
  if (typeof file !== 'string') continue;
  const src = stripTs(fs.readFileSync(path.join(appDir, 'app', file), 'utf8'));
  t(`${file} still renders <BottomNav> (the parent map is pointless on a screen with no dock)`,
    /<BottomNav\s*\/?>/.test(src), file);
  t(`${file} does NOT render <TabSwipe> (a non-tab screen must not carry the tab gesture)`,
    !/<TabSwipe[\s>]/.test(src), file);
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
