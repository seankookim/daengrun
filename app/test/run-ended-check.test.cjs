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
// Added after the executing review (APPROVE-WITH-FIXES), each one a plant that stayed green before:
// drop the verdict's mirror into render state (A5 — the strip never appears, the CTA is a dead
// button) · drop `setEndedRetrying(false)` from the retry's finally (A6 — the strip sticks on
// 확인 중… forever) · defang the strip's onAction (A7) · read a not-yet-started check as permission
// while the booking id is still resolving (the review's third finding) · count a FAILED booking
// resolution as 「no booking」 · make the retry return early when no id was resolved.
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

  t('🔴 [c3] the ended-check answers with separate values — unknown has its own, apart from 「no booking」',
    /type EndedVerdict = 'ended' \| 'live' \| 'failed' \| 'none';/.test(SRC)
    && SRC.includes('useRef<Promise<EndedVerdict> | null>(null)'));

  const check = bodyOf(SRC, 'const runEndedCheck = useCallback(');
  t('NO-SOURCE(runEndedCheck) — the check function is present', typeof check === 'string');
  const catchArm = check ? bodyOf(check, '.catch(', '=> {') : null;
  t('🔴 [c3] a FAILED read resolves to \'failed\' — never to a value that reads as 「not ended」',
    typeof catchArm === 'string' && catchArm.includes("return 'failed'") && !/return (false|'live'|null|undefined)/.test(catchArm),
    JSON.stringify(catchArm));
  t('[c3] only a returned run_ended_at reads as ended; a returned row without one is live',
    check !== null && check.includes("r?.runEndedAt ? 'ended' : 'live'"));
  // [review A5] The pin used to accept any `setEndedState(` — which `setEndedState('checking')` at
  // the top of the same function satisfies, so deleting the MIRROR (the only line that ever puts
  // 'failed' on screen) stayed green. Pinned now as the exact statement.
  t('🔴 [c3] the check is cached where startRun reads it, and its ANSWER is mirrored into render state',
    check !== null && check.includes('endedCheck.current = check;')
    && /void check\.then\(\(v\) => \{ if \(endedCheck\.current === check\) setEndedState\(v\); \}\);/.test(check),
    JSON.stringify(check && check.slice(-260)));
  // [review · null-check race] The booking id is resolved INSIDE the check, and a failed resolution
  // is unknown ('failed'), never 「no booking」 ('none').
  const resolveArm = check ? check.slice(check.indexOf('if (!runnerJob.bookingId)'), check.indexOf('const bid = runnerJob.bookingId;')) : '';
  t('🔴 [c3] the check resolves the booking itself, and a FAILED resolution is \'failed\'',
    check !== null && resolveArm.includes('await fetchCurrentRunnerJobId()')
    && /catch \(e\) \{[^}]*return 'failed';\s*\}/.test(resolveArm)
    && !/return 'none'|return 'live'/.test(resolveArm)
    && /if \(!bid\) return 'none';/.test(check),
    JSON.stringify(resolveArm));
  t('[c3] the booking is resolved in ONE place — the check (no second, unchecked resolution)',
    (SRC.match(/fetchCurrentRunnerJobId\(/g) || []).length === 1);
  const hydrate = (() => {
    const i = SRC.indexOf('resetTrace();');
    const j = SRC.indexOf('await hydrateBooking(bid);', i);
    return i > 0 && j > i ? SRC.slice(i, j + 30) : null;
  })();
  t('NO-SOURCE(hydrate effect)', typeof hydrate === 'string');
  t('🔴 [c3] the hydrate starts the check SYNCHRONOUSLY — before its first await, so no tap sees 「no check」',
    hydrate !== null && hydrate.indexOf('const check = runEndedCheck();') >= 0
    && hydrate.indexOf('const check = runEndedCheck();') < hydrate.indexOf('await'),
    JSON.stringify(hydrate && hydrate.slice(0, 300)));

  const inner = bodyOf(SRC, 'const startRunInner = async () =>');
  t('NO-SOURCE(startRunInner)', typeof inner === 'string');
  const gate = inner ? inner.indexOf("if (verdict !== 'live' && verdict !== 'none')") : -1;
  const track = inner ? inner.indexOf('startTracking(') : -1;
  const server = inner ? inner.indexOf('startRunServer(') : -1;
  t('🔴 [c3] a start goes through ONLY on an ANSWER (\'live\' / \'none\'), and the gate precedes both tracking and the server start',
    gate >= 0 && track > gate && server > gate,
    `gate=${gate} track=${track} server=${server}`);
  // [review · null-check race] A missing check is NOT permission: the old `endedCheck.current ? … :
  // null` let a tap during the booking's resolution through with no verdict at all.
  t('🔴 [c3] startRunInner always awaits a real verdict — a check not yet started is started, never read as 「go」',
    inner !== null && inner.includes('const verdict = await (endedCheck.current ?? runEndedCheck());')
    && !/endedCheck\.current \? await endedCheck\.current : null/.test(inner));
  t('[c3] the retired boolean gate is gone (a truthy-only test lets 「failed」 and 「live」 both through)',
    inner !== null && !inner.includes('await endedCheck.current) return'));

  const strip = bodyOf(SRC, 'const blockStrip = ()', '| null => {');
  t('NO-SOURCE(blockStrip)', typeof strip === 'string' && strip.length > 200);
  const failedArm = strip ? strip.slice(strip.indexOf("endedState === 'failed'"), strip.indexOf('if (trackMode == null')) : '';
  // [review A7] `includes('retryEndedCheck()')` was satisfied by `void 0 && retryEndedCheck()`.
  t('🔴 [c3] a failed check puts a failure strip on screen with 다시 시도, which re-reads',
    strip !== null && failedArm.includes("'다시 시도'")
    && failedArm.includes('onAction: () => { if (!endedRetrying) void retryEndedCheck(); },')
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
    retry !== null && retry.includes('const v = await runEndedCheck();')
    && /if \(v === 'ended' && bid\) router\.replace\(\{ pathname: '\/runner\/return-seal'/.test(retry));
  // [review A6] Without the reset in `finally` the strip sticks on 확인 중… and the CTA stays hidden
  // even after a 'live' answer — permanently.
  t('🔴 [c3] the retry\'s busy state is set before the read and cleared in a FINALLY',
    retry !== null
    && /setEndedRetrying\(true\);\s*try \{/.test(retry)
    && /\} finally \{\s*setEndedRetrying\(false\);\s*\}/.test(retry),
    JSON.stringify(retry));
  t('[c3] the retry re-runs the whole check (resolution included) — no early return on a missing id, which would make 다시 시도 dead',
    // Property: every tap reaches the check — NO return of any shape precedes the call. (The first
    // draft matched only `if (!bid) return` and stayed green on `if (!runnerJob.bookingId) return;`,
    // measured in this slice's battery as R4; restated as the property, not the plant.)
    retry !== null && retry.indexOf('runEndedCheck()') > 0
    && !/\breturn\b/.test(retry.slice(0, retry.indexOf('runEndedCheck()')))
    && retry.indexOf('setEndedRetrying(true)') < retry.indexOf('runEndedCheck()'));
  t('[c3] a retry that fails again is SAID — the runner just tapped',
    retry !== null && /else if \(v === 'failed'\) announce\(/.test(retry));

  t('🔴 [c3] the hydrate routes an ended run to the seal screen FIRST, through the same check',
    hydrate !== null
    && /const verdict = await check;[\s\S]*if \(verdict === 'ended'\) \{\s*router\.replace\(\{ pathname: '\/runner\/return-seal', params: \{ bid \} \}\);\s*return;\s*\}\s*await hydrateBooking\(bid\);/.test(hydrate));
  t('[c3] there is ONE place that reads fetchReturnSeal for this check (no second, two-valued copy)',
    (SRC.match(/fetchReturnSeal\(/g) || []).length === 1);
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
