// ═══ live-run-sheets — source pins for the owner live / meetup / runner run surfaces ═══
//
// Slice ui/live-run-sheets (sweep 2, 2026-09-25). Every property below lives in a `.tsx` route
// module (or a `.ts` the geo runner copies out of src/lib), which the `.cjs` suites cannot import —
// so a re-planted defect in any of these screens reddens NOTHING behavioural. This file reads the
// SOURCE, with comments removed by the Babel parser (never by a regex), because this repo documents
// its copy fixes in comments and a raw match would be satisfied by the explanation of a fix.
//
// ── WHAT EACH ARM PINS (the property, not the site) ─────────────────────────────────────────
//   LRS-A  the /safety destination is called 「안심 센터」 at every door in app/ + src/ (its own
//          title, safety.tsx), and both incident-hold strips offer it as a PaperBtn pair — no
//          hand-rolled ink plate (the primary paper-btn.tsx's matrix retired).
//   LRS-B  no hand-drawn grabber bar on a sheet (HIG reserves it for a RESIZABLE sheet; none of
//          these drag, so it promised a swipe that did nothing — paper-sheet.tsx header), and every
//          transparent Modal in the three files that had one still has its real exits: an
//          onRequestClose and a backdrop Pressable that carries a role.
//   LRS-C  the runner's photo auto-caption states no value for a metric the product computes.
//   LRS-D  no developer vocabulary in these screens' customer copy; owner/live's SDK-absent state
//          uses the shared MAP_LOAD_FAIL_KO sentence.
//   LRS-E  an owner cancel reaches the runner's meetup screen as 「보호자가 … 취소」, with no
//          compensation clause (fee-0 and waived cancels record none) — and the frozen allow-list
//          that gates that branch is byte-for-byte unchanged.
//   LRS-F  every Text in these screens that takes the display (df) or number (nf) font sets an
//          explicit lineHeight ≥ 1.2× its fontSize (DESIGN §3 「BUG A」: ascenders clip).
//   LRS-G  no name interpolation followed by a hard-coded alternating particle (가/이 · 를/을 ·
//          와/과 · 는/은 · 랑/이랑) in the six files; where a particle is needed it comes from
//          src/lib/particle.ts.
//   LRS-H  the delete-account sheet's open_incident refusal has a door (문의하기 → SUPPORT_MAIL),
//          and a table action actually renders in the refused phase.
//
// ── CONTROLS ─────────────────────────────────────────────────────────────────────────────────
//   LRS-X1 a comment QUOTING a retired form reddens nothing (the stripper is not decorative).
//   LRS-X2 the same text as CODE is seen (the stripper did not blank code).
//   Each pin also fails loudly when the thing it reads is absent (NO-SOURCE), so a renamed file or
//   anchor turns red instead of silently passing over an empty string.
//
// ── MUTATION BATTERY ─────────────────────────────────────────────────────────────────────────
// ROOT can be pointed at a COPY of app/ (LIVE_RUN_SHEETS_ROOT=<dir containing app/ and src/>) so a
// battery plants in a scratch tree, never in the live one. Measured on the slice's own run — see the
// commit message for the table.
//
// ⚠ NAMED LIMITS, prose not pins:
//   · LRS-B's grabber detector reads style OBJECTS (alignSelf 'center' + width ≤ 60 + height ≤ 6).
//     A grabber drawn from a width/height passed as props, or from an image, is invisible to it.
//   · The Codex batch lane (app/club/, app/shot/, …) is EXCLUDED from LRS-B by name, not by a
//     filter: Sean's 2026-09-23 split keeps that lane's forms, and measured on this slice's base
//     it carries four grabbers (club/console, club/run, club/session, shot/[bid]) that belong to it.
//   · LRS-G sees `${expr}가` and `{expr}가`. A particle glued to a name built by string concatenation
//     (`name + '가'`) is not seen — measured: zero such sites in the six files.
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

const ROOT = process.env.LIVE_RUN_SHEETS_ROOT || path.join(__dirname, '..');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

/** Blank every comment the parser finds (newlines kept, offsets kept). Throws on a parse failure —
 *  a file this cannot read must fail loudly, never be skipped. */
function stripComments(src, rel) {
  const ast = parser.parse(src, {
    sourceType: 'module',
    plugins: rel.endsWith('.tsx') ? ['typescript', 'jsx'] : ['typescript'],
  });
  const out = src.split('');
  for (const c of ast.comments || []) {
    for (let k = c.start; k < c.end; k++) if (out[k] !== '\n') out[k] = ' ';
  }
  return out.join('');
}

const read = (rel) => {
  const p = path.join(ROOT, rel);
  if (!fs.existsSync(p)) return null;
  const src = fs.readFileSync(p, 'utf8');
  try { return { src, code: stripComments(src, rel) }; } catch (e) { return { src, code: null, err: e.message }; }
};

function walk(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (/\.(ts|tsx)$/.test(e.name) && !e.name.endsWith('.d.ts')) out.push(p);
  }
  return out;
}

const OWNED = [
  'app/owner/live.tsx', 'app/owner/meetup.tsx', 'app/runner/meetup.tsx', 'app/runner/run.tsx',
  'src/lib/geo.ts', 'src/components/delete-account-sheet.tsx',
];
const F = {};
for (const rel of OWNED) {
  const r = read(rel);
  t(`NO-SOURCE · ${rel} exists and parses`, r && r.code != null, r ? r.err || '' : 'missing');
  F[rel] = r && r.code != null ? r.code : '';
}

const TREE = [...walk(path.join(ROOT, 'app')), ...walk(path.join(ROOT, 'src'))]
  .map((p) => path.relative(ROOT, p)).sort();
const CODE = new Map();
const unreadable = [];
for (const rel of TREE) {
  const r = read(rel);
  if (r && r.code != null) CODE.set(rel, r.code); else unreadable.push(rel);
}
t('NO-SOURCE · the tree walk found app/ + src/ (≥100 modules) and every one parsed',
  TREE.length >= 100 && unreadable.length === 0, `${TREE.length} files · unreadable: ${unreadable.join(' ')}`);

const lineOf = (s, off) => s.slice(0, off).split('\n').length;

/** End (exclusive) of the JSX opening tag that starts at `lt`, honouring `{…}` and quotes. */
function tagEnd(s, lt) {
  let depth = 0, i = lt + 1;
  while (i < s.length) {
    const c = s[i];
    if (c === '"' || c === "'") { const q = c; i++; while (i < s.length && s[i] !== q) i++; i++; continue; }
    if (c === '`') { i++; while (i < s.length && s[i] !== '`') i++; i++; continue; }
    if (c === '{') depth++;
    else if (c === '}') depth--;
    else if (c === '>' && depth === 0) return i + 1;
    i++;
  }
  return -1;
}

/** The `{ … }` body that opens at the first `{` at/after `from`, brace-matched. */
function braceBody(s, from) {
  const open = s.indexOf('{', from);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (c === "'" || c === '"') { const q = c; i++; while (i < s.length && s[i] !== q) { if (s[i] === '\\') i++; i++; } continue; }
    if (c === '`') { i++; while (i < s.length && s[i] !== '`') { if (s[i] === '\\') i++; i++; } continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return s.slice(open, i + 1); }
  }
  return null;
}

// ── LRS-A · 「안심 센터」 at every door, and the hold strips' two PaperBtns ─────────────────────
const RETIRED_NAME = '안전' + ' 센터'; // assembled so THIS file is not a grep hit for it
const wrongName = [];
let rightName = 0;
for (const [rel, code] of CODE) {
  let i = code.indexOf(RETIRED_NAME);
  while (i >= 0) { wrongName.push(`${rel}:${lineOf(code, i)}`); i = code.indexOf(RETIRED_NAME, i + 1); }
  rightName += (code.match(/안심 센터/g) || []).length;
}
t('LRS-A1 · 🔴 no door in app/ + src/ calls /safety by any name but 「안심 센터」', wrongName.length === 0, wrongName.join(' '));
t('LRS-A1 · the destination names itself 「안심 센터」 (safety.tsx) and the scan saw the doors (≥5)',
  (CODE.get('app/safety.tsx') || '').includes('안심 센터') && rightName >= 5, `${rightName} code hits`);

// The hold strip is anchored on its own body text, not on every /safety push: owner/meetup also has
// a quiet 「펫보험 … 안심 센터」 LINK row (accessibilityRole="link"), which is a different door with
// a different job and is correctly a bare Pressable.
const HOLD_ANCHOR = { 'app/owner/live.tsx': '{heldCopy.strip}', 'app/owner/meetup.tsx': 'style={s.holdBody}' };
for (const [rel, anchor] of Object.entries(HOLD_ANCHOR)) {
  const s = F[rel];
  const at = s.indexOf(anchor);
  const rowStart = at >= 0 ? s.indexOf('<Row', at) : -1;
  const rowEnd = rowStart >= 0 ? s.indexOf('</Row>', rowStart) : -1;
  const row = rowStart >= 0 && rowEnd > rowStart ? s.slice(rowStart, rowEnd) : '';
  t(`LRS-A2 · NO-SOURCE · ${rel} still has its incident-hold strip and its button row`, row.length > 0);
  const btns = [];
  const re = /<([A-Z]\w*)\b/g; let m;
  while ((m = re.exec(row)) !== null) {
    if (m[1] === 'Row') continue;
    const end = tagEnd(row, m.index);
    btns.push({ tag: m[1], el: end > 0 ? row.slice(m.index, end) : '' });
  }
  const safety = btns.filter((b) => b.el.includes("router.push('/safety')"));
  const chat = btns.filter((b) => /pathname: '\/chat'/.test(b.el));
  t(`LRS-A2 · 🔴 ${rel} hold strip: the /safety door is a PaperBtn primary labelled 「안심 센터 열기」`,
    safety.length === 1 && safety[0].tag === 'PaperBtn' && safety[0].el.includes('label="안심 센터 열기"')
      && !/\bvariant=/.test(safety[0].el),
    safety.map((b) => `<${b.tag}> ${b.el.slice(0, 100)}`).join(' | ').replace(/\s+/g, ' '));
  t(`LRS-A3 · ${rel} hold strip: exactly two elements, the other a secondary PaperBtn chat door`,
    btns.length === 2 && chat.length === 1 && chat[0].tag === 'PaperBtn' && /variant="secondary"/.test(chat[0].el),
    btns.map((b) => `<${b.tag}>`).join(' '));
  t(`LRS-A3 · ${rel} carries none of the retired hold-button styles`, !/\bholdBtn\w*/.test(s), (s.match(/\bholdBtn\w*/) || [''])[0]);
}

// ── LRS-B · no fake grabber; the sheets keep their real exits ─────────────────────────────────
const LANE = ['app/club/', 'app/community.tsx', 'app/shot/', 'app/settings.tsx', 'app/my.tsx'];
const grabbers = [];
const laneGrabbers = [];
const num = (body, key) => { const m = body.match(new RegExp(`\\b${key}:\\s*(\\d+(?:\\.\\d+)?)\\b`)); return m ? Number(m[1]) : null; };
for (const [rel, code] of CODE) {
  const re = /\{[^{}]*\}/g; let m;
  while ((m = re.exec(code)) !== null) {
    const body = m[0];
    if (!/alignSelf:\s*'center'/.test(body)) continue;
    const w = num(body, 'width'), h = num(body, 'height');
    if (w == null || h == null || w > 60 || h > 6) continue;
    (LANE.some((x) => rel.startsWith(x)) ? laneGrabbers : grabbers).push(`${rel}:${lineOf(code, m.index)}`);
  }
}
t('LRS-B1 · 🔴 no grabber-shaped bar (centred, ≤60 wide, ≤6 tall) outside the Codex lane', grabbers.length === 0, grabbers.join(' '));
console.log(`INFO LRS-B1 · Codex-lane grabbers (excluded by name, not fixed here): ${laneGrabbers.join(' ')}`);
t('LRS-B1 · CONTROL · the detector sees the lane\'s own grabbers (it is not blind by construction)',
  laneGrabbers.length >= 1, `${laneGrabbers.length}: ${laneGrabbers.join(' ')}`);

for (const rel of ['app/owner/live.tsx', 'app/runner/run.tsx', 'src/components/delete-account-sheet.tsx']) {
  const s = F[rel];
  const re = /<Modal\b/g; let m, n = 0;
  while ((m = re.exec(s)) !== null) {
    const end = tagEnd(s, m.index);
    const opener = end > 0 ? s.slice(m.index, end) : '';
    if (!/\btransparent\b/.test(opener)) continue;
    n++;
    const next = /<([A-Z]\w*)\b/g; next.lastIndex = end;
    const nm = next.exec(s);
    const nEnd = nm ? tagEnd(s, nm.index) : -1;
    const backdrop = nm && nEnd > 0 ? s.slice(nm.index, nEnd) : '';
    t(`LRS-B2 · ${rel}:${lineOf(s, m.index)} transparent Modal keeps onRequestClose and a role-bearing backdrop Pressable`,
      /\bonRequestClose=/.test(opener) && nm && nm[1] === 'Pressable'
        && /\baccessibilityRole=/.test(backdrop) && /\bonPress=/.test(backdrop),
      `${opener.slice(0, 90)} → <${nm ? nm[1] : '?'}>`);
  }
  t(`LRS-B2 · ${rel} still has its transparent sheet (NO-SOURCE if 0)`, n >= 1, `${n} found`);
}

// ── LRS-C · no fake number for a real metric in the auto-sent caption ─────────────────────────
{
  const s = F['app/runner/run.tsx'];
  t('LRS-C1 · NO-SOURCE · run.tsx still auto-sends funLine() to the owner chat (the surface this pins)',
    /sendChatMessage\(\s*threadId\s*,\s*funLine\(\)\s*\)/.test(s));
  t('LRS-C1 · 🔴 run.tsx states nothing about 체력 나이 (a metric owner/fitness.tsx really computes)',
    !s.includes('체력 나이'));
  t('LRS-C1 · 🔴 run.tsx states no signed age delta (「±N살」)', !/[+\-−]\s?\d+(?:\.\d+)?살/.test(s),
    (s.match(/[+\-−]\s?\d+(?:\.\d+)?살/) || [''])[0]);
}

// ── LRS-D · no developer vocabulary; the SDK-absent sentence is the shared one ────────────────
{
  const live = F['app/owner/live.tsx'];
  t('LRS-D1 · owner/live imports MAP_LOAD_FAIL_KO from lib/copy and renders it',
    /import \{[^}]*\bMAP_LOAD_FAIL_KO\b[^}]*\} from '[^']*lib\/copy'/.test(live) && live.includes('{MAP_LOAD_FAIL_KO}'));
  t('LRS-D1 · 🔴 owner/live says nothing about a 개발 빌드', !live.includes('개발 빌드'));
  const DEV = ['실예약', '실지도'];
  const devHits = [];
  for (const rel of OWNED) for (const w of DEV) { const i = F[rel].indexOf(w); if (i >= 0) devHits.push(`${rel}:${lineOf(F[rel], i)} ${w}`); }
  t('LRS-D1 · 🔴 no 실예약 / 실지도 in the six files\' code', devHits.length === 0, devHits.join(' '));
}

// ── LRS-E · the runner is told who cancelled, and nothing about compensation ──────────────────
{
  const s = F['app/runner/meetup.tsx'];
  const at = s.indexOf("'예약 상태가 바뀌었어요'");
  const callAt = at >= 0 ? s.lastIndexOf('Alert.alert(', at) : -1;
  const close = callAt >= 0 ? s.indexOf(');', at) : -1;
  const call = callAt >= 0 && close > 0 ? s.slice(callAt, close) : '';
  t('LRS-E1 · NO-SOURCE · runner/meetup\'s terminal Alert is where it was', call.length > 0);
  const own = call.match(/s2\.status === 'cancelled_owner' \? '([^']*)'/);
  t('LRS-E1 · 🔴 cancelled_owner names 보호자', !!own && own[1].includes('보호자'), own ? own[1] : 'no arm');
  t('LRS-E1 · cancelled_runner has its own sentence', /s2\.status === 'cancelled_runner' \? '[^']+'/.test(call));
  t('LRS-E1 · 🔴 the terminal Alert promises no 보상 (fee-0 / waived cancels record none)', !call.includes('보상'));
  t('LRS-E2 · FREEZE · the terminal allow-list is unchanged (copy edits only in the meetup machine)',
    s.includes("if (!['confirmed', 'runner_enroute', 'picked_up', 'active'].includes(s2.status)) {")
      && /closingRef\.current = true;[\s\S]{0,1200}Alert\.alert\([\s\S]{0,700}goBackOrHome\(\);\s*return;/.test(s));
}

// ── LRS-F · display/number fonts carry an explicit lineHeight (BUG A) ─────────────────────────
for (const rel of ['app/owner/live.tsx', 'app/owner/meetup.tsx', 'app/runner/meetup.tsx', 'app/runner/run.tsx']) {
  const s = F[rel];
  const re = /style=\{\[\s*(?:s\.(\w+)|\{([^{}]*)\})\s*,\s*(df|nf)\s*\]\}/g; let m, n = 0;
  while ((m = re.exec(s)) !== null) {
    n++;
    let body = m[2];
    if (m[1]) { const d = s.match(new RegExp(`\\b${m[1]}:\\s*\\{([^{}]*)\\}`)); body = d ? d[1] : null; }
    const fsz = body ? num(body, 'fontSize') ?? (body.match(/fontSize:[^,]*?(\d+(?:\.\d+)?)/) || [])[1] : null;
    const lh = body ? num(body, 'lineHeight') ?? (body.match(/lineHeight:[^,]*?(\d+(?:\.\d+)?)/) || [])[1] : null;
    t(`LRS-F1 · ${rel}:${lineOf(s, m.index)} ${m[3]} text${m[1] ? ` (s.${m[1]})` : ''} sets lineHeight ≥ 1.2× fontSize`,
      fsz != null && lh != null && Number(lh) >= 1.2 * Number(fsz), `fontSize ${fsz} · lineHeight ${lh}`);
  }
  t(`LRS-F1 · ${rel} has df/nf text to check (NO-SOURCE if 0)`, n >= 1, `${n} found`);
}

// ── LRS-G · particles agree with the name ─────────────────────────────────────────────────────
const PARTICLE = '(가|이|를|을|와|과|는|은|랑|이랑)(?![가-힣])';
// `${expr}가` inside a template · `{expr}가` as a JSX child — the lookbehind stops the second from
// re-matching the tail of the first (measured: without it every template site counted twice).
const TEMPLATE_P = `\\$\\{[^{}]*\\}${PARTICLE}`;
const JSX_P = `(?<!\\$)\\{[A-Za-z_$][\\w$.?]*\\}${PARTICLE}`;
const hard = [];
for (const rel of OWNED) {
  const s = F[rel];
  for (const re of [new RegExp(TEMPLATE_P, 'g'), new RegExp(JSX_P, 'g')]) {
    let m;
    while ((m = re.exec(s)) !== null) hard.push(`${rel}:${lineOf(s, m.index)} ${m[0]}`);
  }
  if (/\bwithParticle\(/.test(s)) {
    t(`LRS-G2 · ${rel} takes withParticle from src/lib/particle (one rule, not a copy)`,
      /import \{[^}]*\bwithParticle\b[^}]*\} from '[^']*lib\/particle'/.test(s) && !/function withParticle\b/.test(s));
  }
}
t('LRS-G1 · 🔴 no name interpolation followed by a hard-coded 가/를/와/는/랑 in the six files', hard.length === 0, hard.join(' | '));
t('LRS-G1 · CONTROL · the owner live pill and the handoff label now go through withParticle',
  /withParticle\(dogName, '가\/이'\)/.test(F['app/owner/live.tsx'])
    && /withParticle\(dogName, '를\/을'\)/.test(F['app/owner/meetup.tsx']));

// ── LRS-H · the open_incident refusal has a door ──────────────────────────────────────────────
{
  const s = F['src/components/delete-account-sheet.tsx'];
  const entry = (tok) => { const at = s.indexOf(`${tok}: {`); return at >= 0 ? braceBody(s, at) : null; };
  const ACTION = /action:\s*\{\s*label:\s*'문의하기',\s*href:\s*SUPPORT_MAIL\s*\}/;
  t('LRS-H1 · CONTROL · the parser reads km_balance\'s 문의하기 door (the shape open_incident copies)',
    ACTION.test(entry('km_balance') || ''));
  t('LRS-H1 · 🔴 open_incident has a door: 문의하기 → SUPPORT_MAIL (nothing in the product resolves it)',
    ACTION.test(entry('open_incident') || ''), entry('open_incident') || 'NO-SOURCE');
  t('LRS-H1 · SUPPORT_MAIL is a mailto: (the door is real)', /const SUPPORT_MAIL = 'mailto:[^']+'/.test(s));
  t('LRS-H2 · the refused phase RENDERS a table action (what H1 depends on)',
    /\{refusal\.action && \([\s\S]{0,300}onPress=\{\(\) => go\(refusal\.action!\.href\)\}/.test(s));
}

// ── CONTROLS — the stripper is doing work, in both directions ────────────────────────────────
{
  const quoted = stripComments("// " + RETIRED_NAME + " · 체력 나이 -0.01살\n/* {dogName}를 */\nconst a = 1;\n", 'x.tsx');
  t('LRS-X1 · CONTROL · a COMMENT quoting the retired forms reddens nothing',
    !quoted.includes(RETIRED_NAME) && !quoted.includes('체력 나이') && !quoted.includes('{dogName}를'));
  const live = stripComments("const a = '" + RETIRED_NAME + "';\nconst b = <Text>{dogName}를</Text>;\n", 'x.tsx');
  t('LRS-X2 · CONTROL · the same text as CODE is seen',
    live.includes(RETIRED_NAME) && new RegExp(JSX_P).test(live) && new RegExp(TEMPLATE_P).test('`${dogName}와`'));
}

console.log(`\nlive-run-sheets: ${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
