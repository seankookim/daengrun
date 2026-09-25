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
//   · handoff ABOVE lateness [c4] — move the `handoff` arm back below `isLate` and a sealed pickup
//     that went late opens 내 일정 under a button that promises 「인계 기록」 (section ⑤).
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
// ⑤ the sealed handoff's record outranks lateness — the call case ⑤ left open, now made
// ══════════════════════════════════════════════════════════════════════════════════════════════
// 🔴 [fix/client-review-3 · Codex 2026-09-25 c4] This case used to pin `handoff + isLate → 내 일정`
// as the PRE-EXISTING behaviour, with a note that changing it was a deliberate call for the next
// session. Codex MEASURED the gap that note described: the hero's handoff button reads
// 「티켓 보기 · 인계 기록을 확인해요」, and on this input it opened 내 일정, whose handoff branch
// (`owner/schedule.tsx` ~1130) shows a waiting line and no record door. The call is made: the
// sealed record is the meetup (`picked_up` → the SEALED block, no action), so `handoff` routes
// there ABOVE the lateness arm and the label is true in every lateness state. Moving the `handoff`
// arm back below `isLate` reddens the ⚔ cases here.
// ⚔ ORDERING: both the `handoff` arm and the `isLate` arm match.
t('🔴 c4 · handoff + isLate → /owner/meetup, the sealed record the button promises (NOT 내 일정)',
  D({ state: 'handoff', isLate: true }) === '/owner/meetup',
  JSON.stringify(D({ state: 'handoff', isLate: true })));
// ⚔ ORDERING + the ceiling: `resumable` is a statement about resuming a RUN that has not started
// its handoff. The handoff is already sealed and the meetup offers nothing to do on it, so past
// the ceiling the record is still the honest destination — same reasoning as `returning` in ①.
t('🔴 c4 · handoff + isLate + past the 3h ceiling → still the record',
  D({ state: 'handoff', isLate: true, resumable: false }) === '/owner/meetup');
t('c4 · handoff is label-true in EVERY lateness × ceiling × arrival combination',
  [true, false].every((isLate) => [true, false].every((resumable) => [true, false].every((arrivedWaiting) =>
    D({ state: 'handoff', isLate, resumable, arrivedWaiting }) === '/owner/meetup'))));
// ⚠ And the arm is scoped to `handoff`: lateness still closes `confirmed`, which is the case the
// 2026-08-21 redirect exists for (a 16-day-old booking must not re-enter the meetup's handoff CTA).
// A `handoff` arm widened to every state would silently delete ③; this case notices.
t('c4 · the new arm did not swallow ③ — a plain late `confirmed` still goes to 내 일정',
  D({ state: 'confirmed', isLate: true }) === '/owner/schedule');

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
