// ops-roster-seat.ts — tests run against the REAL compiled source (see
// run-ops-roster-seat-tests.sh), not a retyped copy.
//
// 🔴 THE DEFECT THESE EXIST FOR (codex client review, 2026-09-25 · c4, reproduced at
//    `app/app/ops/roster.tsx:125-146` before the fix): `seat()` set `saving` true and cleared it
//    ONLY in the `.catch`. The path that WORKED never cleared it — `closeSheet` does not touch
//    `saving` — so 「명단에 추가」 kept the busy label 「추가하는 중이에요…」 on a disabled fill for
//    the rest of the screen's life. A dead control, and the deadest kind: it looks like work in
//    progress forever.
//
// WHAT IS PINNED HERE AND WHAT IS NOT. `saving` is the screen's own state and `app/test/*.cjs`
// cannot import a route module, so these cases pin the two halves that ARE reachable: the
// sequencer's outcome for every path (so the screen has something to clear busy in a `finally`
// on), and the sentence a partial failure produces. That the screen actually uses a `finally` is
// pinned as SOURCE at the bottom — comments stripped, because this slice's own comment says the
// word `finally` and an un-stripped match would be measuring the documentation.
//
// The mutations that redden this file: stop at nothing and keep going after a refusal · run the
// classes in parallel · throw the refusal instead of returning it · drop `seated` from the
// outcome · report the refused class as seated · drop the server's own sentence in favour of the
// fallback · move `setSaving(false)` back out of the `finally`.
const path = require('path');
const fs = require('fs');
const { runSeat, seatRefusalText, SEAT_FALLBACK_REFUSAL } = require('./ops-roster-seat.build.cjs');
const { classLabel } = require('./ops-roster.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const CLASSES = ['payout_due', 'return_strand', 'handoff_unanswered'];

/** A server that accepts everything, recording the ORDER and whether calls overlapped. */
function acceptAll() {
  const calls = [];
  let inFlight = 0, overlapped = false;
  return {
    calls,
    get overlapped() { return overlapped; },
    set: (c) => {
      inFlight += 1;
      if (inFlight > 1) overlapped = true;
      calls.push(c);
      return new Promise((resolve) => setTimeout(() => { inFlight -= 1; resolve({ changed: true }); }, 1));
    },
  };
}

/** A server that refuses ONE named class with the Korean sentence `ops_roster_set` would fold. */
function refuseAt(bad, message) {
  const calls = [];
  return {
    calls,
    set: (c) => {
      calls.push(c);
      return c === bad ? Promise.reject(Object.assign(new Error(message), { code: 'P0001' }))
        : Promise.resolve({ changed: true });
    },
  };
}

const LAST_OPERATOR = '마지막 운영자는 해제할 수 없어요';

(async () => {
  // ── ① every class lands ───────────────────────────────────────────────────────────────────
  const ok = acceptAll();
  const okOut = await runSeat(CLASSES, ok.set);
  t('🔴 SUCCESS RESOLVES — the screen gets an outcome on the path that used to return nothing '
    + 'for it to clear busy on',
    okOut !== null && typeof okOut === 'object');
  t('every class is reported seated, in the order they were sent',
    JSON.stringify(okOut.seated) === JSON.stringify(CLASSES), JSON.stringify(okOut.seated));
  t('a clean run carries no refusal', okOut.refusal === null);
  t('the server saw each class exactly once',
    JSON.stringify(ok.calls) === JSON.stringify(CLASSES), JSON.stringify(ok.calls));
  t('🔴 the calls are SEQUENTIAL — `last_operator` is counted per call on the server, and a '
    + 'parallel burst makes a partial failure undescribable',
    ok.overlapped === false);
  t('a clean run has nothing to say', seatRefusalText(okOut, classLabel) === null);

  // ── ② a refusal on the SECOND class ───────────────────────────────────────────────────────
  const bad = refuseAt('return_strand', LAST_OPERATOR);
  const badOut = await runSeat(CLASSES, bad.set);
  t('🔴 A REFUSAL RESOLVES TOO — it is a VALUE, so the screen can render what landed AND why it '
    + 'stopped, which a rejected promise cannot carry',
    badOut.refusal !== null);
  t('the first class is reported seated — a refusal on the second does not undo the first',
    JSON.stringify(badOut.seated) === JSON.stringify(['payout_due']), JSON.stringify(badOut.seated));
  t('the refused class is named and is NOT counted as seated',
    badOut.refusal.eventClass === 'return_strand' && !badOut.seated.includes('return_strand'));
  t('🔴 the rest is NOT attempted — the server saw two calls, not three',
    JSON.stringify(bad.calls) === JSON.stringify(['payout_due', 'return_strand']),
    JSON.stringify(bad.calls));
  t('the error is carried verbatim, so the screen can log its RAW text',
    badOut.refusal.error instanceof Error && badOut.refusal.error.code === 'P0001');

  const said = seatRefusalText(badOut, classLabel);
  t("the sheet renders the SERVER's sentence, never one of ours",
    typeof said === 'string' && said.includes(LAST_OPERATOR));
  t('…and says where it stopped, in the chip\'s own label',
    said.includes(classLabel('return_strand')));
  t('🔴 …and says what ALREADY LANDED — the half of a partial failure an operator cannot see '
    + 'anywhere else',
    said.includes(classLabel('payout_due')) && said.includes('추가된 알림'));

  // ── ③ the first class refused — nothing landed ────────────────────────────────────────────
  const first = refuseAt('payout_due', LAST_OPERATOR);
  const firstOut = await runSeat(CLASSES, first.set);
  t('a refusal on the first class seats nothing and attempts nothing else',
    JSON.stringify(firstOut.seated) === JSON.stringify([])
    && JSON.stringify(first.calls) === JSON.stringify(['payout_due']));
  t('…and the sentence says so rather than listing an empty set',
    seatRefusalText(firstOut, classLabel).includes('추가된 알림은 없어요'));

  // ── ④ an error with no sentence of its own ────────────────────────────────────────────────
  const mute = await runSeat(['payout_due'], () => Promise.reject(new Error('')));
  t('an error carrying no sentence falls back to the product\'s own words, never to an empty strip',
    seatRefusalText(mute, classLabel).startsWith(SEAT_FALLBACK_REFUSAL));
  const thrown = await runSeat(['payout_due'], () => Promise.reject('네트워크'));
  t('a non-Error rejection is still a refusal with a readable sentence',
    thrown.refusal !== null && seatRefusalText(thrown, classLabel).startsWith(SEAT_FALLBACK_REFUSAL));

  // ── ⑤ nothing to do ───────────────────────────────────────────────────────────────────────
  const none = await runSeat([], () => Promise.reject(new Error('must not be called')));
  t('an empty selection resolves clean and calls nothing',
    none.refusal === null && none.seated.length === 0);

  // ── ⑥ the screen's busy flag, through the shape it actually uses ──────────────────────────
  // This models `seat()`'s promise chain: the ONLY place `saving` is cleared is the `finally`, so
  // both outcomes must clear it. Before the fix the success path had no clearer at all.
  const drive = async (server, classes) => {
    let saving = true, closed = false, shown = null;
    await runSeat(classes, server.set)
      .then((out) => {
        if (out.refusal !== null) shown = seatRefusalText(out, classLabel);
        else closed = true;
      })
      .finally(() => { saving = false; });
    return { saving, closed, shown };
  };
  const afterOk = await drive(acceptAll(), CLASSES);
  t('🔴 SUCCESS: the sheet closes and the button is usable again — the exact state the defect '
    + 'never reached',
    afterOk.saving === false && afterOk.closed === true && afterOk.shown === null);
  const afterBad = await drive(refuseAt('return_strand', LAST_OPERATOR), CLASSES);
  t('🔴 PARTIAL FAILURE: the sheet stays OPEN with the refusal on screen and the button usable',
    afterBad.saving === false && afterBad.closed === false
    && typeof afterBad.shown === 'string' && afterBad.shown.includes(LAST_OPERATOR));

  // ── ⑦ the screen itself, as SOURCE ────────────────────────────────────────────────────────
  // The two propositions above are about this module; neither is evidence that the SCREEN clears
  // busy. `app/test/*.cjs` cannot import a route module, so the only instrument left is the text
  // — read with comments stripped, because this slice documents the fix in a comment three lines
  // above the code, and documenting-a-fix and failing-to-make-it are identical to a raw grep.
  const strip = (src) => src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[^\n]*?\/\/[^\n]*$/gm, (line) => {
    const q = line.indexOf('//');
    // Keep code that precedes a trailing comment; drop the comment itself.
    return line.slice(0, q);
  });
  const FIXTURE = "const a = 1; // setSaving(false)\n/* .finally(() => setSaving(false)) */\nconst b = 2;";
  t('the comment stripper removes commented code (control) …',
    !strip(FIXTURE).includes('setSaving(false)'), JSON.stringify(strip(FIXTURE)));
  t('… and the crude version sees it, so the stripper is doing work',
    FIXTURE.includes('setSaving(false)') && strip(FIXTURE).includes('const b = 2'));

  const SCREEN = strip(fs.readFileSync(
    path.join(__dirname, '..', 'app', 'ops', 'roster.tsx'), 'utf8'));
  t('the roster screen is readable at all (an unreadable file must fail LOUDLY, never be skipped)',
    SCREEN.length > 500);
  const clears = SCREEN.split('setSaving(false)').length - 1;
  t('🔴 the screen clears busy in EXACTLY ONE place …', clears === 1, 'found ' + clears);
  t('🔴 … and that place is a `finally`, so no branch can be added that forgets it',
    /\.finally\(\s*\(\)\s*=>\s*setSaving\(false\)\s*\)/.test(SCREEN));
  t('the screen routes the sequence through this module rather than an inline loop',
    SCREEN.includes('runSeat(') && SCREEN.includes('seatRefusalText('));
  t('a refusal keeps the sheet open — `closeSheet()` is on the clean branch only',
    SCREEN.split('closeSheet()').length - 1 === 1);

  console.log('');
  console.log(pass + ' pass / ' + fail + ' fail');
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.log('FAIL harness threw - ' + (e && e.message)); process.exit(1); });
