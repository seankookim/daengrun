// Owner Live Activity — phase → face pins.
//
// THE DEFECT THESE EXIST FOR (measured on trunk 6d02769, 2026-09-23). The widget's phase union
// stopped at 'ended' and its pill/title/foot chains all ended in a bare `else`. The server has
// pushed `phase: 'homeward'` since 0083 (`_owner_la_run_end_tg`, and the 귀가 arm of
// `owner_la_sweep_stale`), so every walk home landed in that `else` and drew pill **ENDED**,
// title 「위치 수신 대기 중」, foot 「러너가 달리기 시작하면 거리가 표시돼요」 — the lock screen told the
// owner their dog's walk had ENDED and that the run had not started, at the same time, while the
// dog was being walked back.
//
// WHAT IS EXECUTED HERE, because it decides what a green means:
//   · `src/lib/live-activity-face.ts` — the pure module, bundled and called directly.
//   · `src/activities/OwnerRunActivity.tsx` — the REAL widget body, bundled with SwiftUI and
//     expo-widgets stubbed and JSX compiled to a plain object factory, then CALLED with a payload.
//     The pins read the words it actually draws. Nothing here matches source text, so a comment
//     documenting a face cannot satisfy a pin that wants the face (the standing comment-quoting law).
//   · every `'phase', '<x>'` literal in `supabase/migrations/` — comment-stripped — so a phase the
//     server starts sending without a face here reddens this gate rather than reaching a lock screen.
//
// WHY TWO COPIES OF THE TABLE EXIST AT ALL: the widget function is stringified and executed inside
// the widget extension, where module scope does not exist (its own header records the CORAL
// ReferenceError). It therefore cannot import the module. Executing both and comparing is the only
// thing that stops them drifting.
//
// THE MUTATIONS THAT REDDEN THIS FILE: restore the `else`-chain in the widget · change one face
// string in either copy and not the other · delete a phase from the table while the server still
// pushes it · let an unknown phase inherit a terminal pill · make 귀가 compose its own minute count
// instead of printing the server's sentence · let 귀가 or 마무리 draw the hero number.
const fs = require('fs');
const path = require('path');

const {
  OWNER_RUN_FACES, OWNER_RUN_FACE_UNKNOWN, OWNER_RUN_PHASES, ownerRunFace,
} = require('./live-activity-face.build.cjs');
const widget = require('./owner-run-activity.build.cjs').default;

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the widget harness ────────────────────────────────────────────────────────────────────────
// Collect every string the banner would draw, in order. `children` is either a string (a leaf
// Text) or an array of nodes; the JSX shim keeps both on the node itself.
function texts(node, out = []) {
  if (typeof node === 'string') { out.push(node); return out; }
  if (Array.isArray(node)) { for (const n of node) texts(n, out); return out; }
  if (node && typeof node === 'object') texts(node.children, out);
  return out;
}
// The pill is the first Text in the banner; its background modifier carries the tone's colour.
function pillBackground(banner) {
  let found = null;
  (function walk(n) {
    if (found || !n || typeof n !== 'object') return;
    if (Array.isArray(n)) { for (const c of n) walk(c); return; }
    if (n.type === 'Text' && Array.isArray(n.props && n.props.modifiers)) {
      const bg = n.props.modifiers.find((m) => m && m.modifier === 'background');
      if (bg) { found = bg.arg; return; }
    }
    walk(n.children);
  })(banner);
  return found;
}
const PAYLOAD = (over) => Object.assign({
  phase: 'running', dogName: '초코', runnerName: '민준',
  km: '', targetKm: '', pace: '', elapsed: '', statusLine: '',
}, over);
const banner = (p) => widget.render(p, { colorScheme: 'dark' });
const drawn = (p) => texts(banner(p).banner);

// ── ① the widget bundle is alive ──────────────────────────────────────────────────────────────
// A dead harness and a harness that agrees with everything are indistinguishable in a summary
// line, and the second reads as success. Assert the widget rendered SOMETHING recognisable before
// reading a single comparison off it.
t('the widget harness actually rendered the banner (control — a dead bundle cannot pass this)',
  drawn(PAYLOAD({ phase: 'running', km: '2.34', targetKm: '3' })).includes('초코 · 민준 러너'));

// ── ② the server's phase vocabulary is covered ────────────────────────────────────────────────
// Comments are stripped first. `0063:315-318` documents the phases in prose right beside the code
// that builds them, so an un-stripped read would be measuring the documentation — the class this
// repo has met three times.
function stripSqlComments(src) {
  let out = '', i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === "'") {                                  // string literal ('' escapes a quote)
      out += c; i++;
      while (i < src.length) {
        if (src[i] === "'" && src[i + 1] === "'") { out += "''"; i += 2; continue; }
        if (src[i] === "'") { out += "'"; i++; break; }
        out += src[i]; i++;
      }
      continue;
    }
    if (c === '-' && src[i + 1] === '-') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') {
      i += 2; let depth = 1;
      while (i < src.length && depth > 0) {
        if (src[i] === '/' && src[i + 1] === '*') { depth++; i += 2; }
        else if (src[i] === '*' && src[i + 1] === '/') { depth--; i += 2; }
        else i++;
      }
      continue;
    }
    out += c; i++;
  }
  return out;
}
// Dollar-quoted function bodies are deliberately NOT treated as opaque strings: almost every
// phase literal lives inside a `$$ … $$` plpgsql body, and so do the `--` comments that must be
// stripped from it.

// The stripper's own control. A pin that reads a comment as code is the failure mode here, so
// prove the stripper removes one — and, in the other direction, that it does not eat a real
// literal that merely sits on a commented line.
const STRIPPER_FIXTURE = [
  "-- a comment that mentions 'phase', 'ghostline'",
  "/* a block that mentions 'phase', 'ghostblock' */",
  "  'phase', 'realone',   -- trailing comment naming 'phase', 'ghosttrail'",
  "  'phase', 'realtwo'",
].join('\n');
const PHASE_RE = /'phase'\s*,\s*'([a-z_]+)'/g;
const phasesIn = (sql) => {
  const found = new Set();
  let m; const re = new RegExp(PHASE_RE.source, 'g');
  while ((m = re.exec(sql)) !== null) found.add(m[1]);
  return found;
};
const stripped = phasesIn(stripSqlComments(STRIPPER_FIXTURE));
const crudeFixture = phasesIn(STRIPPER_FIXTURE);
t('the comment stripper removes a phase literal written inside a comment',
  !stripped.has('ghostline') && !stripped.has('ghostblock') && !stripped.has('ghosttrail'),
  [...stripped].join(','));
t('the comment stripper keeps real phase literals, including one on a commented line',
  stripped.has('realone') && stripped.has('realtwo'));
t('the crude (un-stripped) version DOES pick the comments up — so the stripper is doing work, not nothing',
  crudeFixture.has('ghostline') && crudeFixture.has('ghostblock') && crudeFixture.has('ghosttrail'),
  [...crudeFixture].join(','));

const MIG_DIR = path.join(__dirname, '..', '..', 'supabase', 'migrations');
const serverPhases = new Set();
const crudePhases = new Set();
for (const f of fs.readdirSync(MIG_DIR).filter((n) => n.endsWith('.sql'))) {
  const raw = fs.readFileSync(path.join(MIG_DIR, f), 'utf8');
  for (const p of phasesIn(stripSqlComments(raw))) serverPhases.add(p);
  for (const p of phasesIn(raw)) crudePhases.add(p);
}

// The sweep's own control. A regex that quietly matches nothing returns an empty set, and an
// empty set satisfies "every server phase has a face" by vacuity — the cleanest false green
// available. These six were measured by hand on 2026-09-23; the sweep has to find at least them.
const MEASURED_2026_09_23 = ['running', 'stale', 'homeward', 'stopping', 'done', 'ended'];
t('the migration sweep found the phases measured by hand (control — a broken regex passes the next pin vacuously)',
  MEASURED_2026_09_23.every((p) => serverPhases.has(p)),
  'found: ' + [...serverPhases].sort().join(','));
t('the careful sweep is a subset of the crude one (the stripper only ever removes)',
  [...serverPhases].every((p) => crudePhases.has(p)),
  'careful: ' + [...serverPhases].sort().join(',') + ' | crude: ' + [...crudePhases].sort().join(','));

// THE LOAD-BEARING PIN. ⚠ Its scope is deliberately WIDER than the Live Activity: it matches every
// `'phase', '<x>'` in every migration, which includes `club_end_pack_runs`'s RPC RETURN shape
// (0168) as well as the `_owner_la_push` payloads. `stopping` reaches this set that way and is NOT
// pushed to the activity by anything today. Over-inclusion is the safe direction for a coverage
// pin: it means the banner has a face ready for any phase string the server's vocabulary already
// contains, rather than only the ones someone remembered to wire.
for (const p of [...serverPhases].sort()) {
  t(`the server phase '${p}' has a face (never the neutral fallback)`,
    Object.prototype.hasOwnProperty.call(OWNER_RUN_FACES, p) && ownerRunFace(PAYLOAD({ phase: p })).known);
}

// ── ③ an unknown phase is not a terminal claim ────────────────────────────────────────────────
const unknown = ownerRunFace(PAYLOAD({ phase: 'a-phase-this-build-never-heard-of' }));
t('an unknown phase is reported as unknown', unknown.known === false);
t('an unknown phase draws the neutral face', unknown.pill === OWNER_RUN_FACE_UNKNOWN.pill && unknown.pill === '상태 확인 중');
t('an unknown phase never inherits ENDED',
  unknown.pill !== 'ENDED' && unknown.title !== '러닝이 종료됐어요');
t('an unknown phase never claims the run has not started either',
  unknown.title !== '위치 수신 대기 중' && unknown.foot !== '러너가 달리기 시작하면 거리가 표시돼요');
t('an unknown phase never draws a number, even when the payload carries one',
  ownerRunFace(PAYLOAD({ phase: 'zzz', km: '9.99' })).hasNum === false);
// A phase string that resolves through Object.prototype is the one input that makes a truthy
// lookup hand the banner an object with no pill.
for (const evil of ['constructor', 'toString', 'hasOwnProperty', '__proto__']) {
  t(`a phase of '${evil}' resolves to the neutral face, not to Object.prototype`,
    ownerRunFace(PAYLOAD({ phase: evil })).known === false
    && ownerRunFace(PAYLOAD({ phase: evil })).pill === '상태 확인 중');
}
const unknownDrawn = drawn(PAYLOAD({ phase: 'a-phase-this-build-never-heard-of' }));
t('the WIDGET also draws the neutral face for an unknown phase',
  unknownDrawn.includes('상태 확인 중') && !unknownDrawn.includes('ENDED'),
  JSON.stringify(unknownDrawn));

// ── ④ 귀가 — the phase that was lying ─────────────────────────────────────────────────────────
const HOMEWARD = PAYLOAD({ phase: 'homeward', km: '3.21', elapsed: '24:10', statusLine: '집으로 가는 중' });
const homewardFace = ownerRunFace(HOMEWARD);
t('귀가 has its own pill', homewardFace.pill === '귀가 중');
t('귀가 is not ENDED', homewardFace.pill !== 'ENDED');
t('귀가 takes its title from the server statusLine', homewardFace.title === '집으로 가는 중');
t('귀가 puts the frozen km and elapsed in the foot', homewardFace.foot === '3.21km · 24:10');
t('귀가 never draws the hero number (0083 froze it and dropped the target — a hero number reads as a live measurement)',
  homewardFace.hasNum === false);

// The stale 귀가 sentence is the SERVER's (owner_la_sweep_stale's 귀가 arm). The client must print
// it, never compose a minute count of its own — it has no trustworthy clock for one.
const HOMEWARD_STALE = PAYLOAD({ phase: 'homeward', km: '3.21', elapsed: '24:10', statusLine: '7분째 위치 신호가 없어요' });
t('귀가 prints the server\'s own stale sentence as the title',
  ownerRunFace(HOMEWARD_STALE).title === '7분째 위치 신호가 없어요');
t('귀가 keeps the frozen numbers in the foot while the signal is stale',
  ownerRunFace(HOMEWARD_STALE).foot === '3.21km · 24:10');
t('귀가 with no statusLine falls back to its own copy rather than drawing an empty title',
  ownerRunFace(PAYLOAD({ phase: 'homeward', km: '3.21' })).title === '집으로 가는 중');
t('귀가 omits a part the payload did not carry (km only)',
  ownerRunFace(PAYLOAD({ phase: 'homeward', km: '3.21' })).foot === '3.21km');
t('귀가 omits a part the payload did not carry (elapsed only)',
  ownerRunFace(PAYLOAD({ phase: 'homeward', elapsed: '24:10' })).foot === '24:10');
t('귀가 with neither number falls back to its own copy, never to an empty line',
  ownerRunFace(PAYLOAD({ phase: 'homeward' })).foot === '앱에서 자세히 확인하세요');

// The defect, stated directly against the artifact that had it.
const homewardDrawn = drawn(HOMEWARD);
t('THE DEFECT: the widget no longer draws ENDED for 귀가', !homewardDrawn.includes('ENDED'), JSON.stringify(homewardDrawn));
t('THE DEFECT: the widget no longer claims 귀가 is waiting for a first fix',
  !homewardDrawn.includes('위치 수신 대기 중')
  && !homewardDrawn.includes('러너가 달리기 시작하면 거리가 표시돼요'), JSON.stringify(homewardDrawn));
t('THE DEFECT: the widget draws the 귀가 face', homewardDrawn.includes('귀가 중') && homewardDrawn.includes('집으로 가는 중'));
const smallHomeward = texts(banner(HOMEWARD).bannerSmall);
t('the small banner (watch · CarPlay) carries the 귀가 title too, not ENDED',
  smallHomeward.includes('집으로 가는 중') && !smallHomeward.includes('ENDED'), JSON.stringify(smallHomeward));

// ── ⑤ 마무리 (0168's two-phase stop vocabulary) ───────────────────────────────────────────────
const stoppingFace = ownerRunFace(PAYLOAD({ phase: 'stopping', km: '3.21', targetKm: '5' }));
t('마무리 has its own pill', stoppingFace.pill === '마무리 중');
t('마무리 is not ENDED', stoppingFace.pill !== 'ENDED');
t('마무리 draws no number even if one arrives (0168 writes km as explicit NULL — phase 1 does not know it)',
  stoppingFace.hasNum === false);

// ── ⑥ the phases that already worked keep working ─────────────────────────────────────────────
const RUNNING = PAYLOAD({ phase: 'running', km: '2.34', targetKm: '3', pace: "7'02\"", elapsed: '23:41', statusLine: '방금 업데이트' });
const runningFace = ownerRunFace(RUNNING);
t('running draws the number with its target', runningFace.hasNum === true && runningFace.numUnit === '/ 3km');
t('running folds pace and elapsed into the left datum', runningFace.footLeft === "7'02\" · 23:41");
t('running shows the server status on the right', runningFace.footRight === '방금 업데이트');
const STALE = PAYLOAD({ phase: 'stale', km: '2.34', targetKm: '3', statusLine: '3분째 위치가 갱신되지 않았어요' });
t('stale still says how long, from the server', ownerRunFace(STALE).footRight === '3분째 위치가 갱신되지 않았어요');
t('stale still draws its number (it greys, it does not vanish)', ownerRunFace(STALE).hasNum === true);
const DONE = PAYLOAD({ phase: 'done', km: '4.02', elapsed: '31:08', statusLine: '사진 4장' });
t('done labels the number as a completed distance', ownerRunFace(DONE).numUnit === 'km 완주');
t('done offers the report', ownerRunFace(DONE).footRight === '리포트 보기 ›');
t('done folds the photo count into the left datum', ownerRunFace(DONE).footLeft === '31:08 · 사진 4장');
t('pre never draws a number (the no-0.00 law)', ownerRunFace(PAYLOAD({ phase: 'pre', km: '0.00' })).hasNum === false);
t('ended, as the server sends it, is numberless and says so',
  ownerRunFace(PAYLOAD({ phase: 'ended' })).title === '러닝이 종료됐어요');
// A goal that does not exist is omitted rather than printed as a naked slash.
t('a missing target renders a bare unit, never "/ km"',
  ownerRunFace(PAYLOAD({ phase: 'stale', km: '2.34' })).numUnit === 'km');

// ── ⑦ the widget and the module agree, phase by phase ─────────────────────────────────────────
// This is the pin that makes the two copies of the table safe. Every phase the module knows is
// rendered through the REAL widget and compared to what the module says it should draw. A face
// edited in one file and not the other reddens here.
//
// `paceState` is deliberately absent: the pace pill is a running-only branch with its own layout
// and it is not what this slice changed. One arm below covers it.
const TONE_BG = { live: '#E8552F', settled: '#8FB573', muted: '#6b6478' };
for (const phase of OWNER_RUN_PHASES) {
  const p = PAYLOAD({
    phase, km: '3.21', targetKm: '5', pace: "6'40\"", elapsed: '21:07', statusLine: '상태 문장',
  });
  const f = ownerRunFace(p);
  const meta = '초코 · 민준 러너';
  const want = f.hasNum
    ? [f.pill, meta, p.km, f.numUnit, f.footLeft, f.footRight]
    : [f.pill, meta, f.title, f.foot];
  t(`the widget draws exactly what the module says for '${phase}'`,
    JSON.stringify(drawn(p)) === JSON.stringify(want),
    'widget: ' + JSON.stringify(drawn(p)) + ' module: ' + JSON.stringify(want));
  t(`the widget paints '${phase}' with its tone (${f.tone})`,
    pillBackground(banner(p).banner) === TONE_BG[f.tone],
    'bg: ' + pillBackground(banner(p).banner) + ' want ' + TONE_BG[f.tone]);
}
// The pace-pill branch is a different layout; check it still renders the running datum.
const PACED = Object.assign(PAYLOAD({ phase: 'running', km: '2.34', targetKm: '3', pace: "7'02\"", elapsed: '23:41', statusLine: '방금 업데이트' }), { paceState: 'good' });
t('the running pace pill branch is untouched', JSON.stringify(drawn(PACED))
  === JSON.stringify(['RUNNING', '초코 · 민준 러너', '2.34', '/ 3km', "7'02\"", '양호', '· 23:41', '방금 업데이트']),
  JSON.stringify(drawn(PACED)));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
