// run-ended-check — source pins for runner/run.tsx's ended-check (codex client review wave 4 · c3).
//
// THE DEFECT (Codex, READ): `fetchReturnSeal` failing resolved the ended-check to `false` — 「not
// ended」 — and every later start reused that cached answer. On an ended-but-still-active booking
// (0188 keeps it `active` until the seals), one transient read failure let `startRunServer`
// succeed (`start_run_tx` accepts an active row idempotently), the screen set running and recorded
// again instead of opening the return ceremony, and the edge re-sent 「러닝 시작」 to the owner.
// THE FIX: three answers, not two. 'failed' blocks start and resume, hides the CTA (a door that
// refuses every tap is a dead button) and puts 다시 시도 in the strip lane, which re-reads; 'ended'
// routes to the return-seal screen; only 'live' lets a start through.
//
// WHY SOURCE PINS: run.tsx is a route module, which no node test can import (the chain's standing
// division — `check-a11y-roles`, `live-run-sheets`). These pins read the file with comments removed
// by the Babel PARSER, never a regex, because this slice documents the old `return false` in the
// comments beside the fix, and an un-stripped match would be measuring that documentation.
// Neither this file nor a device run is evidence for the other: the strip's look and VoiceOver's
// reading of it are on Sean's smoke list, unverified here.
//
// The mutations that redden it: resolve a failed read to 'live' (or back to a boolean false) ·
// let startRunInner proceed on 'failed' · drop the failed strip or its 다시 시도 · draw the CTA while
// the check is failed · stop routing an 'ended' retry to the return-seal screen.
//
// Every pin fails LOUDLY when its anchor is absent (a renamed function reads as NO-SOURCE, red),
// so an extractor that matched nothing cannot make an arm vacuous.
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

const ROOT = process.env.RUN_ENDED_CHECK_ROOT || path.join(__dirname, '..');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

/** Blank every comment the parser finds (offsets kept). Throws on a parse failure. */
function stripComments(src, tsx) {
  const ast = parser.parse(src, { sourceType: 'module', plugins: tsx ? ['typescript', 'jsx'] : ['typescript'] });
  const out = src.split('');
  for (const c of ast.comments || []) for (let k = c.start; k < c.end; k++) if (out[k] !== '\n') out[k] = ' ';
  return out.join('');
}

/** The brace-balanced block that starts at the first `{` after `signature`, or null. */
function bodyOf(src, signature, opener = '{') {
  const start = src.indexOf(signature);
  if (start < 0) return null;
  // `opener` lets a caller skip a type annotation's braces (`(): { text: string } | null => {`).
  const at = src.indexOf(opener, start);
  if (at < 0) return null;
  let i = at + opener.length - 1;
  if (i < 0) return null;
  const from = i;
  let depth = 0, quote = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (quote) { if (c === '\\') { i++; continue; } if (c === quote) quote = null; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(from, i + 1); }
  }
  return null;
}

// ── controls: the stripper is doing work, and it keeps code ──────────────────────────────────
const FIX = "// .catch(() => false) was the defect\nconst a = () => 'failed';\n/* return false; */";
const strippedFix = stripComments(FIX, false);
t('control — a comment QUOTING the retired form is removed (it would otherwise satisfy a hunt for it)',
  !strippedFix.includes('return false') && !strippedFix.includes('=> false'));
t('control — the same text as CODE is kept', strippedFix.includes("'failed'"));

let SRC = null;
try {
  const raw = fs.readFileSync(path.join(ROOT, 'app', 'runner', 'run.tsx'), 'utf8');
  SRC = stripComments(raw, true);
} catch (e) {
  t('NO-SOURCE(app/runner/run.tsx) — the file must exist and parse', false, e.message);
}

if (SRC !== null) {
  t('run.tsx parsed and is not trivially small', SRC.length > 20000, String(SRC.length));

  t('🔴 [c3] the ended-check answers THREE ways — unknown has its own value',
    /type EndedVerdict = 'ended' \| 'live' \| 'failed';/.test(SRC)
    && SRC.includes('useRef<Promise<EndedVerdict> | null>(null)'));

  const check = bodyOf(SRC, 'const runEndedCheck = useCallback(');
  t('NO-SOURCE(runEndedCheck) — the check function is present', typeof check === 'string');
  const catchArm = check ? bodyOf(check, '.catch(', '=> {') : null;
  t('🔴 [c3] a FAILED read resolves to \'failed\' — never to a value that reads as 「not ended」',
    typeof catchArm === 'string' && catchArm.includes("return 'failed'") && !/return (false|'live'|null|undefined)/.test(catchArm),
    JSON.stringify(catchArm));
  t('[c3] only a returned run_ended_at reads as ended; a returned row without one is live',
    check !== null && check.includes("r?.runEndedAt ? 'ended' : 'live'"));
  t('[c3] the check is cached where startRun reads it, and mirrored into render state',
    check !== null && check.includes('endedCheck.current = check') && check.includes('setEndedState('));

  const inner = bodyOf(SRC, 'const startRunInner = async () =>');
  t('NO-SOURCE(startRunInner)', typeof inner === 'string');
  const gate = inner ? inner.indexOf("if (verdict !== null && verdict !== 'live')") : -1;
  const track = inner ? inner.indexOf('startTracking(') : -1;
  const server = inner ? inner.indexOf('startRunServer(') : -1;
  t('🔴 [c3] a start goes through ONLY on a \'live\' answer, and the gate precedes both tracking and the server start',
    gate >= 0 && track > gate && server > gate
    && inner.includes('const verdict = endedCheck.current ? await endedCheck.current : null;'),
    `gate=${gate} track=${track} server=${server}`);
  t('[c3] the retired boolean gate is gone (a truthy-only test lets 「failed」 and 「live」 both through)',
    inner !== null && !inner.includes('await endedCheck.current) return'));

  const strip = bodyOf(SRC, 'const blockStrip = ()', '| null => {');
  t('NO-SOURCE(blockStrip)', typeof strip === 'string' && strip.length > 200);
  const failedArm = strip ? strip.slice(strip.indexOf("endedState === 'failed'"), strip.indexOf('if (trackMode == null')) : '';
  t('🔴 [c3] a failed check puts a failure strip on screen with 다시 시도, which re-reads',
    strip !== null && failedArm.includes("'다시 시도'") && failedArm.includes('retryEndedCheck()')
    && failedArm.includes('러닝 상태를 확인하지 못했어요'),
    JSON.stringify(failedArm.slice(0, 300)));
  t('[c3] busy is a LABEL SWAP on the same strip, with the busy state — not a strip that vanishes',
    failedArm.includes("endedRetrying ? '확인 중…' : '다시 시도'") && failedArm.includes('busy: endedRetrying')
    && /accessibilityState=\{\{ busy: !!strip\.busy \}\}/.test(SRC));
  t('[c3] the failed strip outranks every tracking strip (it is checked before them) but not the ceiling',
    strip !== null && strip.indexOf('if (ceilingHit)') < strip.indexOf("endedState === 'failed'")
    && strip.indexOf("endedState === 'failed'") < strip.indexOf('if (trackMode == null'));

  t('🔴 [c3] the CTA is not drawn while the check is failed — a door that refuses every tap is a dead button',
    SRC.includes("!((endedState === 'failed' || endedRetrying) && !running) && ("));

  const retry = bodyOf(SRC, 'const retryEndedCheck = useCallback(');
  t('🔴 [c3] a retry that finds the run ENDED routes to the return-seal screen',
    retry !== null && retry.includes('await runEndedCheck(bid)')
    && /if \(v === 'ended'\) router\.replace\(\{ pathname: '\/runner\/return-seal'/.test(retry));
  t('[c3] a retry that fails again is SAID — the runner just tapped',
    retry !== null && /else if \(v === 'failed'\) announce\(/.test(retry));

  t('🔴 [c3] the hydrate routes an ended run to the seal screen FIRST, through the same three-way check',
    /if \(await runEndedCheck\(bid\) === 'ended'\) \{\s*router\.replace\(\{ pathname: '\/runner\/return-seal', params: \{ bid \} \}\);\s*return;/.test(SRC)
    && SRC.indexOf('await runEndedCheck(bid)') < SRC.indexOf('loadInfo(bid);'));
  t('[c3] there is ONE place that reads fetchReturnSeal for this check (no second, two-valued copy)',
    (SRC.match(/fetchReturnSeal\(/g) || []).length === 1);
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
