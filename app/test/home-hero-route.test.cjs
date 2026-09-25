// home-hero-route.ts pins — WHICH DOOR THE OWNER HOME HERO OPENS, arm by arm.
//
// The module is bundled from the REAL source (the run-notification-prefs idiom), not retyped, so
// what these cases pin is the function `app/src/components/home-hero.tsx` actually calls.
// `home-hero-route.ts` imports nothing — no stubbing, no React, no expo-router.
//
// ═══ WHY THIS EXISTS AT ALL ═══
// The rule was three lines inside a render function, and `app/test/*.cjs` cannot import a `.tsx`
// module — so the ordering that decides whether an owner can reach the handoff seal was, for its
// whole life, unreachable by any test in this repo. That is the same argument `lateness.ts` makes
// in its own header, and this is the same remedy.
//
// ═══ WHAT EACH CASE IS FOR, and the mutation that reddens it ═══
//   · returning FIRST — move the `isLate` arm above it and the late-return cases go to 내 일정,
//     which cannot close a return (the ⑫ gate is on the bid-scoped report, 0188).
//   · confirmed + arrived + resumable — delete that arm and the exact defect owner-journey-1
//     names is back: a runner standing at the door 31 minutes past the slot, and no door to
//     /owner/meetup anywhere in the app (it has two callers in total).
//   · `resumable` inside that arm — delete the conjunct and the two taps that resurrect a 16-day
//     -old booking are back, which is the thing the 3h ceiling exists for.
//   · `isLate` still reaching 내 일정 for everything else — delete the arm and a stale booking
//     re-enters the meetup flow.
//   · the four unchanged arms — they are copied verbatim from the code this replaced, so a case
//     each, or nothing notices when a refactor quietly drops one.
//
// ⚠ These are ORDERING pins. Every case below fixes MORE than one input at a time on purpose:
// an ordering bug is only visible where two arms both match, so a case whose inputs satisfy
// exactly one arm cannot see it. The pairs that matter are marked ⚔ below.
const { heroDestination } = require('./home-hero-route.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// The defaults are the NOT-LATE, NOT-ARRIVED, RESUMABLE world — i.e. an ordinary booking. Every
// case says only what it changes, so what a case is testing is what the case writes down.
const D = (over) => heroDestination({
  state: 'none', isLate: false, arrivedWaiting: false, resumable: true, bid: 'bk-1', ...over,
});
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const REPORT = { pathname: '/owner/report', params: { bid: 'bk-1' } };

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ① returning outranks lateness — the return ceremony's own screen, late or not
// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⚔ ORDERING: both the `returning` arm and the `isLate` arm match here. This is the case that
// fails if anyone puts lateness back on top.
t('returning + isLate → the bid-scoped report, NOT 내 일정',
  eq(D({ state: 'returning', isLate: true }), REPORT),
  JSON.stringify(D({ state: 'returning', isLate: true })));
t('returning + not late → the same report (lateness changes nothing here)',
  eq(D({ state: 'returning' }), REPORT));
// ⚔ ORDERING + the fallback: past the ceiling a return STILL goes to the report. `resumable` is a
// statement about resuming a RUN; the return is already over and cannot be resumed or abandoned.
t('returning + isLate + past the 3h ceiling → still the report',
  eq(D({ state: 'returning', isLate: true, resumable: false }), REPORT));
// A report that cannot be addressed is a bounce, so that one arm falls back rather than pushing.
t('returning with no booking id → 내 일정 (a bid-less report cannot be opened)',
  D({ state: 'returning', isLate: true, bid: null }) === '/owner/schedule');

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ② the arrived-and-resumable door — owner-journey-1's whole content
// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⚔ ORDERING: `isLate` is true, so the old code returned 내 일정 here and this case was the defect.
t('confirmed + runner ARRIVED + resumable + isLate → /owner/meetup',
  D({ state: 'confirmed', isLate: true, arrivedWaiting: true }) === '/owner/meetup',
  D({ state: 'confirmed', isLate: true, arrivedWaiting: true }));
// The `resumable` conjunct, alone. Same inputs as the case above except the ceiling verdict.
t('confirmed + ARRIVED + PAST THE CEILING + isLate → 내 일정 (the door is genuinely shut)',
  D({ state: 'confirmed', isLate: true, arrivedWaiting: true, resumable: false }) === '/owner/schedule');
// The `arrivedWaiting` conjunct, alone. A runner who never showed has nothing to meet about.
t('confirmed + NOT arrived + isLate → 내 일정',
  D({ state: 'confirmed', isLate: true, arrivedWaiting: false }) === '/owner/schedule');
// ⚠ The arm is scoped to `confirmed`. `arrivedWaiting` is derived from
// `rawStatus === 'runner_enroute'`, which STATUS_MAP flattens to the display word `confirmed`, so
// no other state can honestly carry it — and an arm that fired on any state would be a second,
// unreviewed door. Deleting `state === 'confirmed'` from the arm reddens this case.
t('searching + arrived + resumable + isLate → 내 일정 (arm ② is confirmed-only)',
  D({ state: 'searching', isLate: true, arrivedWaiting: true }) === '/owner/schedule');

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ③ lateness still closes everything else — the 2026-08-21 rule, narrowed and not deleted
// ══════════════════════════════════════════════════════════════════════════════════════════════
t('confirmed + isLate (plain) → 내 일정', D({ state: 'confirmed', isLate: true }) === '/owner/schedule');
t('searching + isLate → 내 일정, not the radar', D({ state: 'searching', isLate: true }) === '/owner/schedule');
t('directed + isLate → 내 일정', D({ state: 'directed', isLate: true }) === '/owner/schedule');
t('none + isLate → 내 일정', D({ state: 'none', isLate: true }) === '/owner/schedule');
// `resumable: false` on its own is NOT a redirect — it only ever narrows arm ②. Without this case
// nothing distinguishes 「resumable gates arm ②」 from 「resumable gates the whole function」.
t('confirmed + NOT late + past the ceiling → the meetup, unchanged (resumable gates arm ② only)',
  D({ state: 'confirmed', resumable: false }) === '/owner/meetup');

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ④ the four pre-existing arms, verbatim — a regression fence, not new behaviour
// ══════════════════════════════════════════════════════════════════════════════════════════════
t('handoff + not late → /owner/meetup (the sealed handoff record)',
  D({ state: 'handoff' }) === '/owner/meetup');
t('confirmed + not late → /owner/meetup', D({ state: 'confirmed' }) === '/owner/meetup');
t('active + not late → /owner/live', D({ state: 'active' }) === '/owner/live');
t('searching → the radar', D({ state: 'searching' }) === '/owner/radar');
t('directed → the radar', D({ state: 'directed' }) === '/owner/radar');
t('none → the radar (the fall-through)', D({ state: 'none' }) === '/owner/radar');

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑤ the ONE case this slice deliberately did not change, pinned so it is a decision and not
//    an accident
// ══════════════════════════════════════════════════════════════════════════════════════════════
// 🔴 `handoff` (= server `picked_up`, both handoff stamps landed) that has gone late routes to
// 내 일정, because arm ③ sits above the `handoff` arm. That is the PRE-EXISTING behaviour, carried
// over unchanged: the sweep's verifier confirmed exactly one of the three arms owner-journey-1
// named, and this was not it. It is pinned rather than left silent because the hero's handoff
// button now reads 「티켓 보기 · 인계 기록을 확인해요」, and on this one input its destination is
// 내 일정 rather than the record — a label/destination gap that is a product call (whether a
// sealed handoff can still be 「late」 at all is upstream of the router). Moving the `handoff` arm
// above arm ③ reddens this case, which is the point: the next session changes it on purpose.
t('handoff + isLate → 내 일정 (pre-existing, see the comment above — NOT a new rule)',
  D({ state: 'handoff', isLate: true }) === '/owner/schedule');

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑥ the shape of what comes back — the caller hands this straight to `router.push`
// ══════════════════════════════════════════════════════════════════════════════════════════════
t('every non-report destination is a bare string (a push target, not an object)',
  ['none', 'searching', 'directed', 'confirmed', 'handoff', 'active'].every((state) =>
    [true, false].every((isLate) => typeof D({ state, isLate }) === 'string')));
t('the report destination carries the booking id it was given, verbatim',
  eq(D({ state: 'returning', bid: 'bk-ZZZ' }), { pathname: '/owner/report', params: { bid: 'bk-ZZZ' } }));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
