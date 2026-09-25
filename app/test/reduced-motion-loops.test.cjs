// Reduce Motion vs. looping animation — slice F4 (cloud/reduced-motion-loops).
//
// WHAT THIS FILE PINS, AND WHY IT IS TWO KINDS OF TEST
// Four decorative loops ran regardless of the OS Reduce Motion setting: runner/home PulseRings,
// the 대기 호흡 pulse on BOTH meetup screens, and the owner radar Ripple. Each now builds its loop
// inside `loopUnlessReduced(make, rest)` (src/lib/reducedMotion.ts), which starts nothing until the
// platform has ANSWERED (the A7 settled-aware lesson) and parks the value at `rest` under Reduce
// Motion. Two different propositions need two different instruments, and neither is evidence for
// the other:
//
//   S — SOURCE: every loop reference in the four route files is the direct concise body of the
//       first argument of an IMPORTED `loopUnlessReduced` with a `rest` callback. The test chain
//       cannot import a `.tsx` route module, so re-planting an ungated loop into any of them
//       reddens nothing behavioural — only a source read can see it. Babel-parsed, so a comment
//       QUOTING a loop (or quoting the gated form) is not code; see the scanner controls K*.
//   B — BEHAVIOUR: the helper itself, compiled from the REAL source with esbuild and run against a
//       stubbed AccessibilityInfo. The A7 race is the thing it exists for: nothing may start
//       before the platform answers.
//   X — CRUDE vs CAREFUL: the scanner's count is reconciled against a raw regex per file, every
//       difference attributed in BOTH directions (comment hits, string hits, AST-only hits), per
//       CLAUDE.md's standing rule for a new detector.
//
// What this file does NOT prove (prose, not pins): that the `rest` phases look right on a device
// (0.6/0.8 rings outside the 28px tile, radar rings at 0.2/0.4/0.6 outside the 54 core). That is a
// device-visual claim and belongs on Sean's smoke list.
//
// Mutations that redden it (measured in an isolated lab, see the slice report): unwrap any one of
// the four gates back to a bare `.start()` · a local no-op `loopUnlessReduced` shadowing the import ·
// a factory that starts its own loop · helper starting before the answer · helper ignoring a
// reduce=true answer · helper dropping the live listener · cleanup that does not stop the loop.
// Fix round (executing review, 2026-09-26), each gated-planted: helper not recording `settled` (B4b) ·
// helper not calling `from` before a restart (B11) · a site dropping its `from` callback (S2) · a
// site discarding the gate's cleanup, on each of the four (S4) · runner/home dropping one stop from
// its cleanup (S4) · an ungated loop through `const Anim = Animated` (S1/S2).
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond === true) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const APP = path.resolve(__dirname, '..');
const FILES = [
  'app/runner/home.tsx',
  'app/runner/meetup.tsx',
  'app/owner/meetup.tsx',
  'app/owner/radar.tsx',
];
// How many loop references each file is expected to hold. A file dropping to 0 must FAIL loudly:
// a scanner that finds nothing in a file it is supposed to guard passes every other arm vacuously.
const EXPECTED_LOOPS = {
  'app/runner/home.tsx': 1,
  'app/runner/meetup.tsx': 1,
  'app/owner/meetup.tsx': 1,
  'app/owner/radar.tsx': 1,
};
const GATE = 'loopUnlessReduced';
const GATE_MODULE = /(^|\/)src\/lib\/reducedMotion$/;

function parse(src) {
  return parser.parse(src, {
    sourceType: 'module',
    plugins: ['typescript', 'jsx'],
    ranges: true,
  });
}

// Plain recursive walk with a parent chain (the check-a11y-roles.mjs idiom — no @babel/traverse).
function walk(node, visit, parents = []) {
  if (!node || typeof node.type !== 'string') return;
  visit(node, parents);
  const next = parents.concat([node]);
  for (const key of Object.keys(node)) {
    if (key === 'loc' || key === 'range' || key === 'leadingComments' || key === 'trailingComments'
      || key === 'innerComments' || key === 'extra') continue;
    const v = node[key];
    if (Array.isArray(v)) { for (const c of v) if (c && typeof c.type === 'string') walk(c, visit, next); }
    else if (v && typeof v.type === 'string') walk(v, visit, next);
  }
}

const propIs = (m, name) => (!m.computed && m.property.type === 'Identifier' && m.property.name === name)
  || (m.computed && m.property.type === 'StringLiteral' && m.property.value === name);

// Names through which the `Animated` namespace is reachable (review finding, 2026-09-26: the first
// scanner matched only the literal identifier `Animated`, so `const Anim = Animated; Anim.loop(…)`
// scanned as ZERO loops — and the crude regex shares that blind spot, so X1 balanced while both were
// blind). Collected before the main walk: `const X = Animated` (chains too), `import { Animated as X }`,
// `const { Animated: X } = …`, and `import * as RN from 'react-native'` (→ `RN.Animated.loop`).
// NOT covered, written here as prose rather than as a pin: `Animated` passed as an ARGUMENT to a
// function that calls `.loop` on its parameter — a source scanner cannot follow a value through a
// call without becoming a type checker.
function animatedNames(ast) {
  const names = new Set(['Animated']);
  const ns = new Set();
  let grew = true;
  while (grew) {
    grew = false;
    const add = (x) => { if (!names.has(x)) { names.add(x); grew = true; } };
    walk(ast.program, (n) => {
      if (n.type === 'ImportDeclaration' && n.source.value === 'react-native') {
        for (const s of n.specifiers) {
          if (s.type === 'ImportSpecifier' && s.imported && s.imported.name === 'Animated') add(s.local.name);
          if (s.type === 'ImportNamespaceSpecifier' || s.type === 'ImportDefaultSpecifier') ns.add(s.local.name);
        }
      }
      if (n.type === 'VariableDeclarator' && n.id.type === 'Identifier' && n.init
        && n.init.type === 'Identifier' && names.has(n.init.name)) add(n.id.name);
      if (n.type === 'VariableDeclarator' && n.id.type === 'ObjectPattern') {
        for (const p of n.id.properties) {
          if (p.type === 'ObjectProperty' && p.key.type === 'Identifier' && p.key.name === 'Animated'
            && p.value.type === 'Identifier') add(p.value.name);
        }
      }
    });
  }
  return { names, ns };
}

/**
 * The careful scanner. Returns every loop REFERENCE (not only calls: an alias
 * `const L = Animated.loop` or a destructured `{ loop } = Animated` is a way to start a loop
 * the gate never sees) and whether each is gated, plus facts about the gate's binding, plus every
 * gate CALL and whether its return value (the cleanup) reaches the effect's cleanup (S4).
 */
function scan(src) {
  const ast = parse(src);
  const { names: animNames, ns: rnNs } = animatedNames(ast);
  const isAnimatedObj = (o) => (o.type === 'Identifier' && animNames.has(o.name))
    || (o.type === 'MemberExpression' && o.object.type === 'Identifier' && rnNs.has(o.object.name)
      && propIs(o, 'Animated'));
  const isAnimatedLoopMember = (n) => n && n.type === 'MemberExpression' && isAnimatedObj(n.object)
    && propIs(n, 'loop');
  const refs = [];
  const gateCalls = [];
  let gateImported = false;
  const gateLocalDecls = [];
  walk(ast.program, (n, parents) => {
    if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && n.callee.name === GATE) {
      gateCalls.push({ node: n, parents });
    }
    if (n.type === 'ImportDeclaration' && GATE_MODULE.test(n.source.value)) {
      for (const s of n.specifiers) {
        if (s.type === 'ImportSpecifier' && s.imported.name === GATE && s.local.name === GATE) gateImported = true;
      }
    }
    // Any other binding of the gate's name would shadow the import (a local no-op gate).
    if ((n.type === 'VariableDeclarator' && n.id.type === 'Identifier' && n.id.name === GATE)
      || ((n.type === 'FunctionDeclaration' || n.type === 'FunctionExpression') && n.id && n.id.name === GATE)
      || ((n.type === 'ArrowFunctionExpression' || n.type === 'FunctionExpression' || n.type === 'FunctionDeclaration')
        && n.params.some((p) => p.type === 'Identifier' && p.name === GATE))) {
      gateLocalDecls.push(n.start);
    }
    if (n.type === 'VariableDeclarator' && n.init && isAnimatedObj(n.init)
      && n.id.type === 'ObjectPattern'
      && n.id.properties.some((p) => p.type === 'ObjectProperty' && p.key.type === 'Identifier' && p.key.name === 'loop')) {
      refs.push({ start: n.start, kind: 'destructure', gated: false, why: 'destructured from Animated' });
    }
    if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && n.callee.name === 'withRepeat') {
      refs.push({ start: n.start, kind: 'withRepeat', gated: false, why: 'reanimated withRepeat has no gate here' });
    }
    if (!isAnimatedLoopMember(n)) return;
    const parent = parents[parents.length - 1];
    const call = parent && parent.type === 'CallExpression' && parent.callee === n ? parent : null;
    if (!call) { refs.push({ start: n.start, kind: 'alias', gated: false, why: 'referenced but not called in place' }); return; }
    // Gated iff: call is the concise body of an arrow that is argument[0] of a `loopUnlessReduced`
    // call which also has function arguments [1] (rest: the parked phase) and [2] (from: the start
    // phase, re-applied before every (re)start — review finding 3, the native loop does not reset).
    const fn = parents[parents.length - 2];
    const gateCall = parents[parents.length - 3];
    let gated = false, why = 'not the direct body of a gate factory';
    if (fn && fn.type === 'ArrowFunctionExpression' && fn.body === call && fn.params.length === 0
      && gateCall && gateCall.type === 'CallExpression'
      && gateCall.callee.type === 'Identifier' && gateCall.callee.name === GATE
      && gateCall.arguments[0] === fn) {
      const isFn = (a) => !!a && (a.type === 'ArrowFunctionExpression' || a.type === 'FunctionExpression');
      if (gateCall.arguments.length === 3 && isFn(gateCall.arguments[1]) && isFn(gateCall.arguments[2])) {
        gated = true; why = '';
      } else {
        why = 'gate call lacks its rest and from callbacks';
      }
    }
    refs.push({ start: n.start, kind: 'call', gated, why });
  });
  const cleanup = gateCalls.map(({ node, parents }) => {
    const r = reachesCleanup(ast, node, parents, 0);
    return { start: node.start, ok: r.ok, why: r.why };
  });
  const commentText = (ast.comments || []).map((c) => c.value);
  const strings = [];
  walk(ast.program, (n) => {
    if (n.type === 'StringLiteral') strings.push(n.value);
    if (n.type === 'TemplateElement') strings.push(n.value.raw);
  });
  return { refs, cleanup, gateImported, gateLocalDecls, commentText, strings, src };
}

// ── S4's reachability: does a gate call's RETURN VALUE (its cleanup) reach the effect's cleanup? ──
// Review finding 2 (2026-09-26): `return loopUnlessReduced(…)` → `loopUnlessReduced(…)` left every
// arm green while the loop AND its reduceMotionChanged listener outlived the effect. The trunk code
// this replaced had an explicit `return () => loop.stop()`; this is that property, pinned.
// A gate call's value reaches cleanup iff ONE of:
//   (a) it is the argument of a `return` whose nearest function is a useEffect/useLayoutEffect
//       callback — or the concise body of that callback;
//   (b) it initialises `const X`, in that callback, and a `return` of that callback returns `X` or a
//       function that CALLS `X` (the runner/home stop1/stop2 shape);
//   (c) it is returned (or is the concise body) of a local helper `const F = (…) => …`, and EVERY call
//       of F reaches cleanup by (a)–(c), with at least one call (a helper nobody calls starts nothing
//       and cleans nothing — it must not pass vacuously).
const FN_TYPES = new Set(['ArrowFunctionExpression', 'FunctionExpression', 'FunctionDeclaration']);
const EFFECTS = new Set(['useEffect', 'useLayoutEffect']);
function nearestFn(parents) {
  for (let i = parents.length - 1; i >= 0; i--) if (FN_TYPES.has(parents[i].type)) return { fn: parents[i], i };
  return null;
}
function isEffectCallback(fn, parentOfFn) {
  if (!parentOfFn || parentOfFn.type !== 'CallExpression' || parentOfFn.arguments[0] !== fn) return false;
  const c = parentOfFn.callee;
  return (c.type === 'Identifier' && EFFECTS.has(c.name))
    || (c.type === 'MemberExpression' && !c.computed && c.property.type === 'Identifier' && EFFECTS.has(c.property.name));
}
function helperName(fn, parentOfFn) {
  if (fn.type === 'FunctionDeclaration' && fn.id) return fn.id.name;
  if (parentOfFn && parentOfFn.type === 'VariableDeclarator' && parentOfFn.init === fn && parentOfFn.id.type === 'Identifier') {
    return parentOfFn.id.name;
  }
  return null;
}
// `return` statements whose nearest enclosing function is `fn` itself (not a nested one).
function ownReturns(fn) {
  const out = [];
  if (fn.body.type !== 'BlockStatement') return out;
  walk(fn.body, (n, parents) => {
    if (n.type === 'ReturnStatement' && !parents.some((p) => FN_TYPES.has(p.type))) out.push(n);
  });
  return out;
}
function callsIdent(root, name) {
  let hit = false;
  walk(root, (n) => { if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && n.callee.name === name) hit = true; });
  return hit;
}
function reachesCleanup(ast, expr, parents, depth) {
  if (depth > 3) return { ok: false, why: 'helper chain deeper than 3' };
  const parent = parents[parents.length - 1];
  const nf = nearestFn(parents);
  if (!nf) return { ok: false, why: 'not inside any function' };
  const fnParent = parents[nf.i - 1];
  const returned = (parent.type === 'ReturnStatement' && parent.argument === expr)
    || (parent === nf.fn && nf.fn.type === 'ArrowFunctionExpression' && nf.fn.body === expr);
  if (returned) {
    if (isEffectCallback(nf.fn, fnParent)) return { ok: true, why: '' };
    const F = helperName(nf.fn, fnParent);
    if (!F) return { ok: false, why: 'returned from a function that is neither the effect nor a named helper' };
    const calls = [];
    walk(ast.program, (n, ps) => { if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && n.callee.name === F) calls.push({ n, ps }); });
    if (calls.length === 0) return { ok: false, why: `helper ${F} is never called` };
    for (const c of calls) {
      const r = reachesCleanup(ast, c.n, c.ps, depth + 1);
      if (!r.ok) return { ok: false, why: `${F}(…) at offset ${c.n.start}: ${r.why}` };
    }
    return { ok: true, why: '' };
  }
  if (parent.type === 'VariableDeclarator' && parent.init === expr && parent.id.type === 'Identifier') {
    const X = parent.id.name;
    if (!isEffectCallback(nf.fn, fnParent)) return { ok: false, why: `${X} is bound outside an effect callback` };
    const ok = ownReturns(nf.fn).some((r) => r.argument && (
      (r.argument.type === 'Identifier' && r.argument.name === X)
      || ((r.argument.type === 'ArrowFunctionExpression' || r.argument.type === 'FunctionExpression') && callsIdent(r.argument, X))));
    return ok ? { ok: true, why: '' } : { ok: false, why: `${X} is never called in the effect's returned cleanup` };
  }
  return { ok: false, why: 'return value discarded (neither returned nor bound for the cleanup)' };
}

const lineOf = (src, off) => src.slice(0, off).split('\n').length;
const CRUDE = /Animated\.loop\(/g;
const count = (s, re) => (s.match(re) || []).length;

// ── K: scanner controls, on synthetic sources (independent of the four files) ────────────────
{
  const imp = "import { loopUnlessReduced } from '../../src/lib/reducedMotion';\n";
  const gatedOk = imp + 'useEffect(() => loopUnlessReduced(() => Animated.loop(x), () => v.setValue(0.4), () => v.setValue(0)), []);\n';
  const s1 = scan(gatedOk);
  t('K1 control: a correctly gated loop scans as ONE gated reference',
    s1.refs.length === 1 && s1.refs[0].gated === true && s1.gateImported === true && s1.gateLocalDecls.length === 0
      && s1.cleanup.length === 1 && s1.cleanup[0].ok === true,
    JSON.stringify({ refs: s1.refs, cleanup: s1.cleanup }));

  const s2 = scan(imp + 'const l = Animated.loop(x); l.start();\n');
  t('K2 a bare Animated.loop(...).start() scans as UNGATED',
    s2.refs.length === 1 && s2.refs[0].gated === false, JSON.stringify(s2.refs));

  const s3 = scan('// Animated.loop(Animated.timing(v, {...})).start()  ← quoted in a comment\nconst a = 1;\n');
  t('K3 a comment QUOTING a loop is not a loop (0 references)', s3.refs.length === 0, JSON.stringify(s3.refs));

  const s4 = scan(imp + '// loopUnlessReduced(() => Animated.loop(x), () => v.setValue(0), () => v.setValue(0))\nAnimated.loop(x).start();\n');
  t('K4 a comment quoting the GATED form above an ungated loop does not gate it',
    s4.refs.length === 1 && s4.refs[0].gated === false, JSON.stringify(s4.refs));

  const s5 = scan(imp + 'loopUnlessReduced(() => { const l = Animated.loop(x); l.start(); return l; }, () => {}, () => {});\n');
  t('K5 a factory that builds-and-starts inside a block body is NOT gated',
    s5.refs.length === 1 && s5.refs[0].gated === false, JSON.stringify(s5.refs));

  const s6 = scan(imp + 'loopUnlessReduced(() => Animated.loop(x));\n');
  t('K6 a gate call without a rest callback is NOT gated (the element must be parked somewhere)',
    s6.refs.length === 1 && s6.refs[0].gated === false, JSON.stringify(s6.refs));
  const s6b = scan(imp + 'loopUnlessReduced(() => Animated.loop(x), () => v.setValue(0.4));\n');
  t('K6b a gate call with rest but no from callback is NOT gated (a restart would begin at the parked phase)',
    s6b.refs.length === 1 && s6b.refs[0].gated === false, JSON.stringify(s6b.refs));

  const s7 = scan('const loopUnlessReduced = (m, r, f) => { m().start(); return () => {}; };\n'
    + 'loopUnlessReduced(() => Animated.loop(x), () => {}, () => {});\n');
  t('K7 a LOCAL gate of the same name is seen (not imported + a local declaration)',
    s7.gateImported === false && s7.gateLocalDecls.length === 1, JSON.stringify({ imp: s7.gateImported, decl: s7.gateLocalDecls }));

  const s8 = scan(imp + 'const L = Animated.loop; L(x).start();\nconst { loop } = Animated;\n');
  t('K8 an alias and a destructure of Animated.loop are both counted as ungated references',
    s8.refs.length === 2 && s8.refs.every((r) => r.gated === false), JSON.stringify(s8.refs));

  const s9 = scan(imp + 'const s = "Animated.loop(";\nAnimated\n  .loop(x).start();\n');
  t('K9 a string holding the pattern is not a loop, and a line-broken call IS one',
    s9.refs.length === 1 && s9.refs[0].gated === false, JSON.stringify(s9.refs));

  // K10 — namespace aliases (review finding 4). Each form is one ungated loop the old scanner
  // scanned as zero; the gated alias form must still scan as gated.
  const aliasForms = {
    'const alias': 'const Anim = Animated;\nAnim.loop(x).start();\n',
    'alias chain': 'const A1 = Animated; const A2 = A1;\nA2.loop(x).start();\n',
    'import as': "import { Animated as Anim } from 'react-native';\nAnim.loop(x).start();\n",
    'destructure rename': "const { Animated: Anim } = require('react-native');\nAnim.loop(x).start();\n",
    'namespace import': "import * as RN from 'react-native';\nRN.Animated.loop(x).start();\n",
    'computed on alias': "const Anim = Animated;\nAnim['loop'](x).start();\n",
  };
  for (const [label, body] of Object.entries(aliasForms)) {
    const sa = scan(imp + body);
    t(`K10 ${label}: an ungated loop through a namespace alias scans as ONE ungated reference`,
      sa.refs.length === 1 && sa.refs[0].gated === false, JSON.stringify(sa.refs));
  }
  const sag = scan(imp + 'const Anim = Animated;\nuseEffect(() => loopUnlessReduced(() => Anim.loop(x), () => {}, () => {}), []);\n');
  t('K10 control: a GATED loop through an alias scans as one gated reference',
    sag.refs.length === 1 && sag.refs[0].gated === true, JSON.stringify(sag.refs));
  const san = scan(imp + 'const Anim = Animated;\nconst v = new Anim.Value(0); Anim.timing(v, {}).start();\n');
  t('K10 control: an alias used for NON-loop members is not a loop (0 references)', san.refs.length === 0, JSON.stringify(san.refs));

  // K11–K16 — S4's reachability, one control per rule and one per way to break it (review finding 2).
  const G = 'loopUnlessReduced(() => Animated.loop(x), () => {}, () => {})';
  const cl = (body) => scan(imp + body).cleanup;
  const oneOk = (c) => c.length === 1 && c[0].ok === true;
  const allOk = (c) => c.length > 0 && c.every((r) => r.ok === true);
  const oneBad = (c) => c.length === 1 && c[0].ok === false;
  t('K11 control (a): `return gate(...)` inside the effect callback reaches cleanup',
    oneOk(cl(`useEffect(() => { if (!w) return; return ${G}; }, [w]);\n`)), JSON.stringify(cl(`useEffect(() => { if (!w) return; return ${G}; }, [w]);\n`)));
  t('K11b control (a): the effect callback\'s concise body reaches cleanup',
    oneOk(cl(`React.useEffect(() => ${G}, []);\n`)));
  t('K12 a gate call whose return value is DISCARDED does not reach cleanup',
    oneBad(cl(`useEffect(() => { ${G}; }, []);\n`)), JSON.stringify(cl(`useEffect(() => { ${G}; }, []);\n`)));
  t('K13 control (b): bound and called in the returned cleanup reaches it',
    oneOk(cl(`useEffect(() => { const s = ${G}; return () => { s(); }; }, []);\n`)));
  t('K13b control (b): bound and returned bare reaches it',
    oneOk(cl(`useEffect(() => { const s = ${G}; return s; }, []);\n`)));
  t('K14 bound but NOT called in the returned cleanup does not reach it',
    oneBad(cl(`useEffect(() => { const s = ${G}; return () => { other(); }; }, []);\n`)));
  t('K14b bound and called only in a NESTED function\'s return does not count',
    oneBad(cl(`useEffect(() => { const s = ${G}; later(() => { return () => s(); }); }, []);\n`)));
  t('K15 control (c): a helper whose every call is bound and stopped reaches cleanup',
    allOk(cl(`useEffect(() => { const mk = (v) => ${G}; const s1 = mk(a); const s2 = mk(b); return () => { s1(); s2(); }; }, []);\n`)));
  t('K15b a helper with ONE call whose stop is dropped from the cleanup does not reach it',
    oneBad(cl(`useEffect(() => { const mk = (v) => ${G}; const s1 = mk(a); const s2 = mk(b); return () => { s1(); }; }, []);\n`)));
  t('K15c a helper nobody calls does not pass vacuously',
    oneBad(cl(`useEffect(() => { const mk = (v) => ${G}; return () => {}; }, []);\n`)));
  t('K16 returned from a nested callback (not the effect) does not reach cleanup',
    oneBad(cl(`useEffect(() => { later(() => { return ${G}; }); }, []);\n`)));
  t('K16b returned from an effect-LIKE hook that is not useEffect does not count',
    oneBad(cl(`useMemo(() => ${G}, []);\n`)));
}

// ── S: the four route files ───────────────────────────────────────────────────────────────────
const scans = {};
for (const rel of FILES) {
  const abs = path.join(APP, rel);
  let src = null;
  try { src = fs.readFileSync(abs, 'utf8'); } catch (e) { src = null; }
  t(`S0 ${rel} exists and is readable (a missing file must FAIL, never skip)`, typeof src === 'string');
  if (typeof src !== 'string') continue;
  let s = null;
  try { s = scan(src); } catch (e) { s = null; t(`S0 ${rel} parses`, false, e && e.message); continue; }
  scans[rel] = s;
  const n = s.refs.length;
  t(`S1 ${rel} holds exactly ${EXPECTED_LOOPS[rel]} loop reference(s) — the scanner found its target`,
    n === EXPECTED_LOOPS[rel], `found ${n}`);
  const bad = s.refs.filter((r) => r.gated !== true);
  t(`S2 ${rel}: every loop is the direct body of a loopUnlessReduced factory with rest and from callbacks`,
    n > 0 && bad.length === 0,
    bad.map((r) => `line ${lineOf(src, r.start)}: ${r.kind} — ${r.why}`).join('; '));
  t(`S3 ${rel}: loopUnlessReduced is IMPORTED from src/lib/reducedMotion and not shadowed locally`,
    s.gateImported === true && s.gateLocalDecls.length === 0,
    `imported=${s.gateImported} localDecls=${s.gateLocalDecls.map((o) => lineOf(src, o)).join(',')}`);
  const lost = s.cleanup.filter((c) => c.ok !== true);
  t(`S4 ${rel}: every loopUnlessReduced call's cleanup reaches the effect's cleanup (loop + listener die with the effect)`,
    s.cleanup.length > 0 && lost.length === 0,
    `gateCalls=${s.cleanup.length} ` + lost.map((c) => `line ${lineOf(src, c.start)}: ${c.why}`).join('; '));
}

// ── X: crude vs careful, per file, every delta attributed in both directions ───────────────────
// crude   = raw regex count of `Animated.loop(` over the whole text
// careful = the scanner's reference count
// crude − careful = hits inside comments + hits inside string/template literals − AST-only hits
//                   (a line-broken, computed or namespace-ALIASED form the regex cannot see)
//                   − non-call references
// X0 — the reconciliation's own control. On the real tree every term is 0 (measured: 8 = 8 with
// no deltas either way), so the equation is only worth anything if a source where EACH term is
// non-zero still balances — and balances term by term, not merely in total.
{
  const src = [
    '// Animated.loop( quoted in a comment',            // comment hit: crude +1, careful 0
    'const s = "Animated.loop(";',                       // string hit:  crude +1, careful 0
    'Animated.loop(x).start();',                         // plain call:  crude +1, careful +1
    'Animated\n  .loop(y).start();',                     // AST-only:    crude 0,  careful +1
    'const L = Animated.loop;',                          // non-call:    crude 0,  careful +1
    'const Anim = Animated; Anim.loop(z).start();',     // alias call:  crude 0,  careful +1 (AST-only)
  ].join('\n');
  const s = scan(src);
  const crude = count(src, CRUDE);
  const comm = s.commentText.reduce((a, c) => a + count(c, CRUDE), 0);
  const str = s.strings.reduce((a, c) => a + count(c, CRUDE), 0);
  const ast = s.refs.filter((r) => r.kind === 'call' && !/^Animated\.loop\(/.test(src.slice(r.start, r.start + 14))).length;
  const non = s.refs.filter((r) => r.kind !== 'call').length;
  t('X0 control: each reconciliation term is measured independently (crude 3, comment 1, string 1, AST-only 2, non-call 1, careful 4)',
    crude === 3 && comm === 1 && str === 1 && ast === 2 && non === 1 && s.refs.length === 4,
    JSON.stringify({ crude, comm, str, ast, non, careful: s.refs.length }));
}
for (const rel of FILES) {
  const s = scans[rel];
  if (!s) { t(`X ${rel} reconciled`, false, 'not scanned'); continue; }
  const crude = count(s.src, CRUDE);
  const careful = s.refs.length;
  const inComments = s.commentText.reduce((a, c) => a + count(c, CRUDE), 0);
  const inStrings = s.strings.reduce((a, c) => a + count(c, CRUDE), 0);
  const astOnly = s.refs.filter((r) => r.kind === 'call' && !/^Animated\.loop\(/.test(s.src.slice(r.start, r.start + 14))).length;
  const nonCall = s.refs.filter((r) => r.kind !== 'call').length;
  const reconciled = crude - inComments - inStrings + astOnly + nonCall;
  console.log(`  ${rel}: crude=${crude} careful=${careful} comments=${inComments} strings=${inStrings} astOnly=${astOnly} nonCall=${nonCall}`);
  t(`X1 ${rel}: careful = crude − comment hits − string hits + AST-only + non-call refs`,
    careful === reconciled, `careful=${careful} reconciled=${reconciled}`);
}

// X2 — the same reconciliation over every client module (app/ + src/). The four guarded files
// carry no comment/string/AST-only deltas, so X1 alone would reconcile 1 = 1 four times and never
// exercise the terms; the whole tree is where the deltas actually live. This arm asserts the
// SCANNER's accounting, not any gating — the other files are other slices' (see notesForSean).
{
  const roots = ['app', 'src'].map((d) => path.join(APP, d));
  const files = [];
  const visit = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (e.name !== 'node_modules') visit(p); }
      else if (/\.(tsx?|jsx?)$/.test(e.name)) files.push(p);
    }
  };
  roots.forEach(visit);
  let crudeT = 0, carefulT = 0, commT = 0, strT = 0, astT = 0, nonT = 0, unparsed = [];
  const deltas = [];
  for (const abs of files) {
    const src = fs.readFileSync(abs, 'utf8');
    let s;
    try { s = scan(src); } catch (e) { unparsed.push(path.relative(APP, abs)); continue; }
    const crude = count(src, CRUDE);
    const careful = s.refs.filter((r) => r.kind !== 'withRepeat').length;
    const comm = s.commentText.reduce((a, c) => a + count(c, CRUDE), 0);
    const str = s.strings.reduce((a, c) => a + count(c, CRUDE), 0);
    const ast = s.refs.filter((r) => r.kind === 'call' && !/^Animated\.loop\(/.test(src.slice(r.start, r.start + 14))).length;
    const non = s.refs.filter((r) => r.kind === 'alias' || r.kind === 'destructure').length;
    crudeT += crude; carefulT += careful; commT += comm; strT += str; astT += ast; nonT += non;
    if (crude !== careful) deltas.push(`${path.relative(APP, abs)} crude=${crude} careful=${careful} comments=${comm} strings=${str} astOnly=${ast} nonCall=${non}`);
  }
  console.log(`  tree: files=${files.length} crude=${crudeT} careful=${carefulT} comments=${commT} strings=${strT} astOnly=${astT} nonCall=${nonT}`);
  deltas.forEach((d) => console.log('    Δ ' + d));
  t('X2 every client module parses (an unreadable file must FAIL, never be skipped)', unparsed.length === 0, unparsed.join(', '));
  t('X2 tree-wide: careful = crude − comment hits − string hits + AST-only + non-call refs',
    carefulT === crudeT - commT - strT + astT + nonT,
    `careful=${carefulT} reconciled=${crudeT - commT - strT + astT + nonT}`);
}

// ── B: the helper's behaviour, compiled from the real source ───────────────────────────────────
function loadHelper() {
  const SRC = path.resolve(__dirname, '../src/lib/reducedMotion.ts');
  const bundle = require('child_process').execFileSync(
    'npx', ['esbuild', SRC, '--bundle', '--platform=node', '--format=cjs', '--log-level=error',
      '--external:react', '--external:react-native'],
    { encoding: 'utf8', cwd: __dirname },
  );
  const rn = {
    AccessibilityInfo: {
      _answer: null, _listeners: [], _removed: 0,
      isReduceMotionEnabled() { return rn.AccessibilityInfo._answer(); },
      addEventListener(ev, fn) {
        if (ev !== 'reduceMotionChanged') throw new Error('unexpected event ' + ev);
        rn.AccessibilityInfo._listeners.push(fn);
        return { remove() { rn.AccessibilityInfo._removed++; rn.AccessibilityInfo._listeners = rn.AccessibilityInfo._listeners.filter((f) => f !== fn); } };
      },
    },
  };
  const m = new module.constructor();
  m.paths = module.paths;
  const realRequire = m.require.bind(m);
  m.require = (id) => (id === 'react-native' ? rn : id === 'react' ? { useEffect() {}, useState() {} } : realRequire(id));
  m._compile(bundle, SRC + '.build.cjs');
  return { mod: m.exports, AI: rn.AccessibilityInfo };
}

const tick = () => new Promise((r) => setImmediate(r));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// `value` stands in for the Animated.Value: `rest` parks it at 0.4, `from` returns it to 0, and every
// start() records the value the loop begins from (a native loop begins from whatever it finds).
function harness(AI) {
  const log = { made: 0, starts: 0, stops: 0, rests: 0, froms: 0, value: 0, startedAt: [] };
  const make = () => { log.made++; return { start() { log.starts++; log.startedAt.push(log.value); }, stop() { log.stops++; } }; };
  const rest = () => { log.rests++; log.value = 0.4; };
  const from = () => { log.froms++; log.value = 0; };
  AI._listeners = []; AI._removed = 0;
  return { log, make, rest, from };
}
function deferred() {
  let resolve, reject;
  const p = new Promise((a, b) => { resolve = a; reject = b; });
  return { p, resolve, reject };
}

(async () => {
  let h = null;
  try { h = loadHelper(); } catch (e) { h = null; console.log('  (reducedMotion.ts did not compile: ' + (e && e.message) + ')'); }
  t('B0 reducedMotion.ts compiled and exports loopUnlessReduced (a missing helper must FAIL loudly)',
    !!h && typeof h.mod.loopUnlessReduced === 'function');
  if (h) {
    const { mod, AI } = h;
    const L = mod.loopUnlessReduced;

    // B1 — the A7 race: before the platform answers, nothing starts.
    { const d = deferred(); AI._answer = () => d.p; const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from); await tick();
      t('B1 nothing is built or started before the platform answers (settled-aware)',
        log.made === 0 && log.starts === 0 && log.rests === 0, JSON.stringify(log));
      d.resolve(false); await tick();
      t('B2 answer=false → exactly one loop built and started, nothing parked',
        log.made === 1 && log.starts === 1 && log.rests === 0, JSON.stringify(log));
      stop();
      t('B3 cleanup stops the running loop and removes the listener',
        log.stops === 1 && AI._removed === 1 && AI._listeners.length === 0, JSON.stringify({ log, removed: AI._removed })); }

    // B4 — Reduce Motion on: never built, parked at rest.
    { AI._answer = () => Promise.resolve(true); const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from); await tick();
      t('B4 answer=true → never built or started, rest applied once',
        log.made === 0 && log.starts === 0 && log.rests === 1, JSON.stringify(log));
      stop(); }

    // B4b — review finding 1: the answer must SETTLE the gate. B4 asserts one tick in and then stops,
    // which clears the fallback timer before it can fire — so a helper that never records the answer
    // passed B4 while, on a live screen, its 400 ms fallback started the loop on a Reduce Motion
    // device. Here the handle stays alive PAST the fallback (SETTLE_FALLBACK_MS = 400).
    { AI._answer = () => Promise.resolve(true); const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from);
      await sleep(550);
      t('B4b answer=true, screen still mounted past the 400 ms fallback → still never built or started, parked once',
        log.made === 0 && log.starts === 0 && log.rests === 1, JSON.stringify(log));
      stop(); }

    // B5 — live toggle both ways, with a FRESH loop on the way back.
    { AI._answer = () => Promise.resolve(false); const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from); await tick();
      AI._listeners.forEach((f) => f(true));
      t('B5 a live ON-toggle stops the running loop and parks it',
        log.stops === 1 && log.rests === 1, JSON.stringify(log));
      AI._listeners.forEach((f) => f(false));
      t('B6 a live OFF-toggle builds a FRESH loop and starts it (a stopped loop does not restart on the JS driver)',
        log.made === 2 && log.starts === 2, JSON.stringify(log));
      // B11 — review finding 3: the restart must begin from the START phase, not the parked one. A
      // native-driver loop takes its first iteration's from-value from the node as it finds it, so
      // without `from` the radar rings would loop from 0.2/0.4/0.6 forever after an OFF-toggle.
      t('B11 every start begins at the start phase — including the restart after a live ON→OFF toggle',
        log.startedAt.length === 2 && log.startedAt.every((v) => v === 0) && log.froms === 2, JSON.stringify(log));
      stop();
      t('B7 cleanup after the toggles stops the second loop', log.stops === 2, JSON.stringify(log)); }

    // B8 — a late answer after cleanup does nothing (an unmounted screen must not start a loop).
    { const d = deferred(); AI._answer = () => d.p; const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from); stop(); d.resolve(false); await tick();
      t('B8 an answer arriving after cleanup builds and parks nothing',
        log.made === 0 && log.rests === 0, JSON.stringify(log)); }

    // B9 — a platform that rejects keeps motion (the hook's rule).
    { AI._answer = () => Promise.reject(new Error('unsupported')); const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from); await tick(); await tick();
      t('B9 a rejected read keeps motion (starts once)', log.made === 1 && log.starts === 1, JSON.stringify(log));
      stop(); }

    // B10 — a platform that never answers: the fallback timeout starts motion, and a LATE true still parks it.
    { const d = deferred(); AI._answer = () => d.p; const { log, make, rest, from } = harness(AI);
      const stop = L(make, rest, from);
      await sleep(150);
      t('B10a no answer yet at 150 ms → still nothing started', log.made === 0, JSON.stringify(log));
      await sleep(400);
      t('B10b no answer by the fallback → motion starts once', log.made === 1 && log.starts === 1, JSON.stringify(log));
      d.resolve(true); await tick();
      t('B10c a late answer=true after the fallback still stops and parks', log.stops === 1 && log.rests === 1, JSON.stringify(log));
      stop(); }
  }

  console.log(`\nreduced-motion-loops: ${pass} pass / ${fail} fail`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.log('FAIL reduced-motion-loops crashed - ' + (e && e.stack)); process.exit(1); });
