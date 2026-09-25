// work-gate-door.ts — tests run against the REAL compiled source (see run-work-gate-door-tests.sh),
// never a retyped copy.
//
// WHAT THIS FILE IS FOR (Codex 2026-09-25 client verdict c2). `runner/requests.tsx` held the work
// gate as `gate` + `gateKnown` and derived `gated = gateKnown && gate !== null && gate.gated`. A
// FAILED read cleared both, so `gated` was false: every 수락 door went live and the gate strip —
// the only explanation on the screen — disappeared. The decision now lives in `workGateDoor()`,
// and the thing worth pinning is THE STATE → DOOR MAPPING, all four inputs:
//     'loading'   → doors shut, a quiet 「확인하는 중」 line, no control
//     'error'     → doors shut, 「…확인하지 못했어요」 + 다시 시도          ← c2
//     null        → the read answered with no gate object: the same as a failure
//     { gated }   → true: doors shut + the strip's reason · false: the ONLY open door
//
// 🔴 THE PROPERTY, stated without reference to any mutation: `acceptOpen` is true for exactly one
// input — a gate object whose `gated` is `false` — and every shut door carries a reason.
//
// THE MUTATIONS THAT REDDEN IT: make 'error' open the door (the c2 defect itself) · make null open
// it · treat a truthy-but-not-boolean `gated` as open · drop the retry from the failed arm · drop
// the reason from any shut arm · in the screen: fold the catch back into anything but 'error',
// check `accept()` against anything but `door.acceptOpen`, or drop the failed line's 다시 시도.
//
// The second half reads `requests.tsx` as TEXT (the tab-parent idiom — no test in this chain can
// render a route module, and a helper nobody calls changed nothing). Every read strips comments
// first, and the stripper is control-tested before it is trusted, because this slice's own
// comments name `gateKnown` — the very identifier a pin below asserts is gone.
const fs = require('node:fs');
const path = require('node:path');
const {
  workGateDoor, GATE_CHECKING_KO, GATE_FAILED_KO, GATE_RETRY_KO, GATE_SHUT_REASON_KO,
} = require('./work-gate-door.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const J = (x) => JSON.stringify(x);

const OPEN = { gated: false, bookingId: null, rawStatus: null, waitingOn: null };
const SHUT = { gated: true, bookingId: 'bk-1', rawStatus: 'completed', waitingOn: 'runner' };

// ── ① the four inputs, each on its own ──────────────────────────────────────────────────────────
{
  const d = workGateDoor(OPEN);
  t('🔴 known OPEN (gated === false) is the one input that opens the accept door',
    d.acceptOpen === true && d.notice === 'none' && d.doorReason === null && d.lead === null && d.retry === null, J(d));
}
{
  const d = workGateDoor(SHUT);
  t('known GATED → door shut, the strip draws the reason, and the door says why to VoiceOver',
    d.acceptOpen === false && d.notice === 'gated' && d.doorReason === GATE_SHUT_REASON_KO && d.retry === null, J(d));
}
{
  const d = workGateDoor('error');
  t('🔴 c2 · a FAILED read keeps every accept door SHUT (it used to fold into 「not gated」 and open them)',
    d.acceptOpen === false, J(d));
  t('🔴 c2 · …and says the check failed, with 다시 시도 — a shut door is never shut silently',
    d.notice === 'failed' && d.lead === GATE_FAILED_KO && d.retry === GATE_RETRY_KO
    && d.doorReason === GATE_FAILED_KO, J(d));
  t('c2 · the failed line is the house shape 「…확인하지 못했어요」 + 다시 시도',
    /확인하지 못했어요$/.test(GATE_FAILED_KO) && GATE_RETRY_KO === '다시 시도', GATE_FAILED_KO);
}
{
  const d = workGateDoor('loading');
  t('loading → doors shut, a line that says the check is running, and NO control (a door to nowhere during a fetch)',
    d.acceptOpen === false && d.notice === 'checking' && d.lead === GATE_CHECKING_KO && d.retry === null
    && d.doorReason === GATE_CHECKING_KO, J(d));
}
{
  const d = workGateDoor(null);
  t('🔴 a read that answered with NO gate object is not 「not gated」 — same as a failure',
    d.acceptOpen === false && d.notice === 'failed' && d.retry === GATE_RETRY_KO, J(d));
}

// ── ② totality: only `gated === false` opens, and every shut door has a reason ──────────────────
{
  const inputs = ['loading', 'error', null, undefined, SHUT, OPEN, { gated: 'false' }, { gated: 0 },
    { gated: 1 }, { gated: null }, {}, 'something-else'];
  const opened = inputs.filter((x) => workGateDoor(x).acceptOpen);
  t('🔴 exactly ONE of twelve inputs opens the door, and it is the known-open gate',
    opened.length === 1 && opened[0] === OPEN, J(opened));
  t('a non-boolean `gated` ("false", 0, null, missing) is unreadable → the failed arm, never a live door and never a strip claiming an unsealed return',
    [{ gated: 'false' }, { gated: 0 }, { gated: null }, {}].every((x) => {
      const d = workGateDoor(x);
      return d.acceptOpen === false && d.notice === 'failed';
    }));
  t('every shut door carries a non-empty reason (VoiceOver can say why it is disabled)',
    inputs.every((x) => {
      const d = workGateDoor(x);
      return d.acceptOpen || (typeof d.doorReason === 'string' && d.doorReason.length > 0);
    }));
  t('a retry control appears on the failed arm and nowhere else',
    inputs.every((x) => {
      const d = workGateDoor(x);
      return (d.retry !== null) === (d.notice === 'failed');
    }));
  t('every Korean line ends in 요 (house copy), and none uses "..."',
    [GATE_CHECKING_KO, GATE_FAILED_KO, GATE_SHUT_REASON_KO].every((s) => /요$/.test(s) && !s.includes('...')));
}

// ── ③ the comment stripper, control-tested BEFORE anything is asserted with it ────────────────
// Same stripper as runner-application-copy.test.cjs (quote-aware, so `https://` in a string is
// not a comment). Reading requests.tsx UN-stripped would let this slice's own comment — which
// names `gateKnown` to explain its removal — satisfy or defeat the pins below by prose alone.
function stripComments(src) {
  let out = '';
  let i = 0;
  let quote = null;
  while (i < src.length) {
    const c = src[i];
    const nx = src[i + 1];
    if (quote) {
      if (c === '\\') { out += '  '; i += 2; continue; }
      if (c === quote) quote = null;
      out += c; i += 1; continue;
    }
    if (c === '\'' || c === '"' || c === '`') { quote = c; out += c; i += 1; continue; }
    if (c === '/' && nx === '/') {
      while (i < src.length && src[i] !== '\n') { out += ' '; i += 1; }
      continue;
    }
    if (c === '/' && nx === '*') {
      i += 2;
      out += '  ';
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i += 1;
      }
      out += '  '; i += 2; continue;
    }
    out += c; i += 1;
  }
  return out;
}
const reqPath = path.join(__dirname, '..', 'app', 'runner', 'requests.tsx');
const raw = fs.readFileSync(reqPath, 'utf8');
if (raw.length < 500) throw new Error(`NO-SOURCE(app/runner/requests.tsx) — read back ${raw.length} bytes`);
const code = stripComments(raw);

// Two-sided control on the REAL file: `gateKnown` survives ONLY in the comment recording its
// removal (so the raw text has it and the stripped text must not), and `workGateDoor(` is a real
// call (so the stripper must not eat it).
t('CONTROL ⓐ the stripper removes prose — `gateKnown` is in requests.tsx only inside the comment that records its removal',
  raw.includes('gateKnown') && !code.includes('gateKnown'),
  `raw=${raw.includes('gateKnown')} stripped=${code.includes('gateKnown')}`);
t('CONTROL ⓑ the stripper preserves executable text — the `workGateDoor(` call survives',
  code.includes('workGateDoor(gateRead)'), 'the stripper ate a real call, or the call is gone');

// ── ④ the screen uses the helper, everywhere the old flag was read ─────────────────────────────
t('🔴 c2 · the gate read\'s failure is recorded AS a failure (`setGateRead(\'error\')` in the catch)',
  /fetchRunnerWorkGate\(\)[\s\S]{0,120}\.catch\([^\n]*setGateRead\('error'\)/.test(code),
  'the catch folds the failure into something else');
t('c2 · the two-flag representation is gone from executable code (no `gateKnown`, no bare `gated`)',
  !/\bgateKnown\b/.test(code) && !/\bconst gated\b/.test(code) && !/[|&!(]\s*gated\b/.test(code),
  'the old flag is still read somewhere');
// The refusal must sit BETWEEN accept()'s head and its confirm Alert — anywhere else it guards
// nothing. Sliced by position so the pin cannot be satisfied by the same line elsewhere.
const acceptHead = code.indexOf('const accept = (req: OpenRequest) => {');
const acceptAlert = code.indexOf("Alert.alert('요청 수락'", acceptHead);
t('🔴 c2 · accept() refuses to open the confirm Alert unless the gate is KNOWN open',
  acceptHead >= 0 && acceptAlert > acceptHead
  && code.slice(acceptHead, acceptAlert).includes('if (!door.acceptOpen) return;'),
  `head=${acceptHead} alert=${acceptAlert} — the Alert can open on an unknown gate`);
t('c2 · the accept door is disabled in STATE as well as paint, on the same flag',
  /disabled=\{busyAny !== null \|\| !door\.acceptOpen\}/.test(code)
  && /accessibilityState=\{\{ disabled: busyAny !== null \|\| !door\.acceptOpen, busy: acceptActing \}\}/.test(code),
  'the door is live under the grey');
t('c2 · the paint follows the same flag (inert and coral both read door.acceptOpen)',
  /const inert = \(busyAny !== null && !acceptActing\) \|\| !door\.acceptOpen;/.test(code)
  && /const coral = req\.bookingId === coralDirected && door\.acceptOpen;/.test(code));
t('🔴 c2 · the failed line is drawn, and its 다시 시도 re-runs the read (onPress={load})',
  /door\.notice === 'failed'[\s\S]{0,400}onPress=\{load\}[\s\S]{0,300}\{door\.retry\}/.test(code),
  'a failed read shuts the doors with no reason and no way out');
t('c2 · the gate strip is keyed on the helper\'s `gated` notice, not on a separate flag',
  /door\.notice === 'gated' && gate !== null/.test(code));

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
