// notification-primer-gate.ts — tests run against the REAL compiled source (see
// run-notification-primer-gate-tests.sh), not a retyped copy.
//
// What this file is FOR: iOS grants exactly ONE notification alert per install, and
// `requestPermissionsAsync` on a denied account returns `denied` without showing anything. So the
// only interesting question this app asks about push is「may I spend the question, and should I」,
// and this module is the single place that answers it. A wrong answer is invisible in both
// directions — an unprimed ask looks like a working app, and a primer that never shows looks like
// a person who declined. Neither produces a bug report.
//
// The mutations that redden it: return 'primer' on granted (an alert for a permission we hold) ·
// return 'primer' when canAskAgain is false (a plate whose button cannot do anything) · let
// `dismissed` outrank `granted` (a granted install that stops registering its token) · read a
// missing/unknown status as a refusal · treat `canAskAgain: undefined` as false.
const { primerAction } = require('./notification-primer-gate.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const UNDETERMINED = { status: 'undetermined', canAskAgain: true };
const GRANTED = { status: 'granted', canAskAgain: false };
const DENIED_HARD = { status: 'denied', canAskAgain: false };

// ── the four cases the primer exists for ───────────────────────────────────────────────────────
t('undetermined, not yet dismissed → show the primer (the ONLY state where the question is still available AND unspent)',
  primerAction(UNDETERMINED, false) === 'primer', primerAction(UNDETERMINED, false));

t('granted → register, never a primer (there is nothing left to ask, and an alert we cannot show is a dead button)',
  primerAction(GRANTED, false) === 'register', primerAction(GRANTED, false));

t('denied and cannot ask again → skip (a plate whose 계속 fires nothing is a dead end, not a primer)',
  primerAction(DENIED_HARD, false) === 'skip', primerAction(DENIED_HARD, false));

t('already dismissed → skip (once per install: 나중에 and an answered system alert both write the flag)',
  primerAction(UNDETERMINED, true) === 'skip', primerAction(UNDETERMINED, true));

// ── order: granted must outrank dismissed ──────────────────────────────────────────────────────
// The expensive mistake. A person taps 나중에, turns notifications on in Settings a week later,
// and their token must still register — otherwise every push this product sends lands nowhere and
// nobody files a bug about a push they never saw.
t('granted BEATS dismissed — a dismissed install that later granted in Settings still registers',
  primerAction(GRANTED, true) === 'register', primerAction(GRANTED, true));
t('denied+cannot-ask is skip whether or not it was dismissed (the two reasons agree; neither is register)',
  primerAction(DENIED_HARD, true) === 'skip' && primerAction(DENIED_HARD, false) === 'skip');

// ── canAskAgain: only an explicit false closes the door ────────────────────────────────────────
// `push.ts` reads `canAskAgain !== false` for the same reason: a platform that does not report the
// field must not be read as a refusal. This arm is what stops the primer disappearing everywhere
// on a build whose permission object is shaped differently.
t('canAskAgain undefined is NOT a refusal — undetermined still primes',
  primerAction({ status: 'undetermined' }, false) === 'primer',
  primerAction({ status: 'undetermined' }, false));
t('canAskAgain null is NOT a refusal either',
  primerAction({ status: 'undetermined', canAskAgain: null }, false) === 'primer');
t('denied but still askable (Android first refusal) primes rather than skipping — the door is open',
  primerAction({ status: 'denied', canAskAgain: true }, false) === 'primer',
  primerAction({ status: 'denied', canAskAgain: true }, false));

// ── an unreadable permission is NOT a refusal, and must not be drawn as one ────────────────────
// null = expo-notifications missing (old build) or the read threw. The house rule for push is a
// silent skip, never a plate that tells someone they refused something they were never asked.
t('null permission → skip (old build / unreadable — a missing module is not a refusal)',
  primerAction(null, false) === 'skip', primerAction(null, false));
t('undefined permission → skip', primerAction(undefined, false) === 'skip');
t('an object with no status → skip (nothing to reason from)',
  primerAction({ canAskAgain: true }, false) === 'skip', primerAction({ canAskAgain: true }, false));
t('an empty-string status → skip (a falsy status must not fall through to primer)',
  primerAction({ status: '', canAskAgain: true }, false) === 'skip');
t('a non-string status → skip (never guess from a shape we do not recognise)',
  primerAction({ status: 1, canAskAgain: true }, false) === 'skip');

// ── the function returns only the three documented values ──────────────────────────────────────
const ALL = ['primer', 'register', 'skip'];
const CASES = [
  [UNDETERMINED, false], [UNDETERMINED, true], [GRANTED, false], [GRANTED, true],
  [DENIED_HARD, false], [DENIED_HARD, true], [null, false], [undefined, true],
  [{ status: 'provisional', canAskAgain: false }, false], [{}, false],
];
t('every case returns one of the three documented actions',
  CASES.every(([p, d]) => ALL.includes(primerAction(p, d))),
  JSON.stringify(CASES.map(([p, d]) => primerAction(p, d))));

// ⚠ `provisional` is iOS's quiet-delivery authorization. expo-notifications reports it as
// status 'granted' with an ios.status detail, so this literal never reaches us in practice — the
// arm is here to pin the FALLBACK, which must be skip (no alert) rather than primer.
t('an unrecognised non-granted status with canAskAgain false → skip, never a primer',
  primerAction({ status: 'provisional', canAskAgain: false }, false) === 'skip');

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
