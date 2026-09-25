// home-hero-route.ts pins — WHICH DOOR THE OWNER HOME HERO OPENS, arm by arm; and, since
// fix/owner-inflight-truth, WHICH BOOKING it names (⑦), what 내 일정's 지금 band says (⑧), the one
// return predicate (⑨), 내 일정's `?bid=` rule (⑩) and the screens' wiring to all of it (⑪).
//
// The module is bundled from the REAL source (the run-notification-prefs idiom), not retyped, so
// what these cases pin is the function `app/src/components/home-hero.tsx` actually calls.
// `home-hero-route.ts` imports only two pure siblings (`particle.ts`, `lateness.ts`), which esbuild
// bundles in — no stubbing, no React, no expo-router.
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
const {
  heroDestination, heroPick, heroState, heroRank, returnOwed, returnSentence, nowBandLine,
  elapsedLabel, deepLinkStep, scheduleDoor, RETURN_PHASE_LABEL,
  ownerReturnOwed, ownerReturnWaitLine, OWNER_RETURN_WAIT_KO, RETURN_BOTH_STAMPED_KO,
} = require('./home-hero-route.build.cjs');
const fs = require('fs');
const path = require('path');

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
// [fix/owner-inflight-truth · owner-journey-5] 내 일정 reads `bid` now, so the lateness arm (③)
// carries the booking: the hero's button there reads 「일정에서 정리하기 · 취소 조건을 확인하고
// 닫아요」 and those conditions live in THAT booking's sheet. Every case below that used to compare
// against the bare '/owner/schedule' compares against this instead.
const isSched = (d, bid = 'bk-1') => eq(d, { pathname: '/owner/schedule', params: { bid } });

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
  isSched(D({ state: 'confirmed', isLate: true, arrivedWaiting: true, resumable: false })));
// The `arrivedWaiting` conjunct, alone. A runner who never showed has nothing to meet about.
t('confirmed + NOT arrived + isLate → 내 일정',
  isSched(D({ state: 'confirmed', isLate: true, arrivedWaiting: false })));
// ⚠ The arm is scoped to `confirmed`. `arrivedWaiting` is derived from
// `rawStatus === 'runner_enroute'`, which STATUS_MAP flattens to the display word `confirmed`, so
// no other state can honestly carry it — and an arm that fired on any state would be a second,
// unreviewed door. Deleting `state === 'confirmed'` from the arm reddens this case.
t('searching + arrived + resumable + isLate → 내 일정 (arm ② is confirmed-only)',
  isSched(D({ state: 'searching', isLate: true, arrivedWaiting: true })));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ③ lateness still closes everything else — the 2026-08-21 rule, narrowed and not deleted
// ══════════════════════════════════════════════════════════════════════════════════════════════
t('confirmed + isLate (plain) → 내 일정', isSched(D({ state: 'confirmed', isLate: true })));
t('searching + isLate → 내 일정, not the radar', isSched(D({ state: 'searching', isLate: true })));
t('directed + isLate → 내 일정', isSched(D({ state: 'directed', isLate: true })));
t('none + isLate → 내 일정', isSched(D({ state: 'none', isLate: true })));
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
  isSched(D({ state: 'confirmed', isLate: true })));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑥ the shape of what comes back — the caller hands this straight to `router.push`
// ══════════════════════════════════════════════════════════════════════════════════════════════
// [owner-journey-5] This case read 「every non-report destination is a bare string」. The late arm
// now returns 내 일정 WITH the booking, so the property is split in two: the not-late switch is
// still bare strings, and every late non-returning, non-handoff, non-arrived state is the booking.
t('every NOT-late non-report destination is a bare string (a push target, not an object)',
  ['none', 'searching', 'directed', 'confirmed', 'handoff', 'active'].every((state) =>
    typeof D({ state, isLate: false }) === 'string'));
t('every LATE state the lateness arm owns lands on 내 일정 carrying the booking it was given',
  ['none', 'searching', 'directed', 'confirmed', 'active'].every((state) =>
    isSched(D({ state, isLate: true, bid: 'bk-Q' }), 'bk-Q')));
t('a late booking with NO id falls back to the bare list (never ?bid= with an empty value)',
  D({ state: 'confirmed', isLate: true, bid: null }) === '/owner/schedule'
  && D({ state: 'confirmed', isLate: true, bid: '' }) === '/owner/schedule');
t('the report destination carries the booking id it was given, verbatim',
  eq(D({ state: 'returning', bid: 'bk-ZZZ' }), { pathname: '/owner/report', params: { bid: 'bk-ZZZ' } }));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑦ [fix/owner-inflight-truth · owner-journey-1] WHICH BOOKING the hero names — heroPick / heroState
// ══════════════════════════════════════════════════════════════════════════════════════════════
// The pick used to live in owner/home.tsx's loader and dropped EVERY `incident_review` row. 0226
// moves an `active` run nobody stamped to `incident_review` WITH `run_ended_at` set, and the report
// still draws the owner's return stamp for it — so dropping it left 「비어 있어요」 over an
// unconfirmed return, reachable only from the push. These cases sit where the old rule (drop every
// review) and the new rule (keep the one with an owed return) DISAGREE; a fixture in the agreement
// zone could not tell them apart.
const NOW = Date.parse('2026-09-25T12:00:00Z');
const H = 3_600_000;
const iso = (ms) => new Date(ms).toISOString();
const row = (over) => ({ id: 'r', status: 'pending', rawStatus: 'matching', runEndedAt: null,
  scheduledAt: iso(NOW + 24 * H), matched: false, ...over });
// incident_review reaches the client as the display word 'pending' (STATUS_MAP has no entry) and a
// runner is attached (`matched`) — so a pick that read the word would call it 「지명 대기」.
const REVIEW_ENDED = row({ id: 'rv-ended', status: 'pending', rawStatus: 'incident_review', matched: true,
  runEndedAt: iso(NOW - 2 * H), scheduledAt: iso(NOW - 4 * H) });
const REVIEW_OPEN = row({ id: 'rv-open', status: 'pending', rawStatus: 'incident_review', matched: true,
  runEndedAt: null, scheduledAt: iso(NOW - 4 * H) });

{
  const p = heroPick([REVIEW_ENDED], NOW);
  t('0-ir · an incident_review row WITH run_ended_at is the hero (the owner owes the return stamp)',
    p.next && p.next.id === 'rv-ended', JSON.stringify(p.next));
  t('0-ir · …and its frame is `returning`, not the display word\'s 「지명 대기」',
    heroState(p.next) === 'returning', heroState(p.next));
  t('0-ir · …and the hero\'s one button opens the bid-scoped report for THAT booking (heroDestination ①)',
    !!p.next && eq(heroDestination({ state: heroState(p.next), isLate: true, arrivedWaiting: false, resumable: false, bid: p.next.id }),
      { pathname: '/owner/report', params: { bid: 'rv-ended' } }));
  t('0-ir · it is not also the review line (an owed return is the hero, not a case to point at)',
    p.review === null, JSON.stringify(p.review));
}
{
  const p = heroPick([REVIEW_OPEN], NOW);
  t('0-ir · an incident_review row WITHOUT run_ended_at is NOT the hero (nothing for the owner to stamp)',
    p.next === null && heroState(p.next) === 'none', JSON.stringify(p.next));
  t('0-ir · …it comes back as `review`, so home can say 「확인이 진행 중인 일정이 있어요」 instead of 「비어 있어요」',
    p.review && p.review.id === 'rv-open', JSON.stringify(p.review));
  t('0-ir · …and it is never on the rail (a case is not an upcoming run)', p.upcoming.length === 0);
}
{
  // ⚔ RANKING: the owed return must outrank a live search even though BOTH carry the word 'pending'
  // and the search is sooner. Ranked by the display word, the search would win.
  const SEARCH = row({ id: 'search', scheduledAt: iso(NOW + 2 * H) });
  const p = heroPick([SEARCH, REVIEW_ENDED], NOW);
  t('0-ir · ⚔ an owed return outranks a 「러너 찾는 중」 booking (ranked like `active`)',
    p.next && p.next.id === 'rv-ended', JSON.stringify(p.next && p.next.id));
  t('0-ir · …and the search is on the rail instead', p.upcoming.map((b) => b.id).join() === 'search');
  t('0-ir · heroRank puts the owed return at active\'s rank, and an open review nowhere',
    heroRank(REVIEW_ENDED) === heroRank(row({ status: 'active', rawStatus: 'active' })) && heroRank(REVIEW_OPEN) === null);
}
{
  // The pre-existing active+run_ended_at return is unchanged by the widening.
  const ACTIVE_ENDED = row({ id: 'a-ended', status: 'active', rawStatus: 'active', matched: true, runEndedAt: iso(NOW - H) });
  const ACTIVE_LIVE = row({ id: 'a-live', status: 'active', rawStatus: 'active', matched: true });
  t('0-ir · active + run_ended_at is still `returning`', heroState(ACTIVE_ENDED) === 'returning');
  t('0-ir · active without run_ended_at is still `active` (a run in progress)', heroState(ACTIVE_LIVE) === 'active');
  t('0-ir · no_show is never the hero and never the review line',
    (() => { const p = heroPick([row({ id: 'ns', rawStatus: 'no_show', runEndedAt: iso(NOW - H) })], NOW); return p.next === null && p.review === null; })());
  t('0-ir · the six display frames are unchanged arm for arm (confirmed · handoff · directed · searching · none)',
    heroState(row({ status: 'confirmed', rawStatus: 'confirmed' })) === 'confirmed'
    && heroState(row({ status: 'handoff', rawStatus: 'picked_up' })) === 'handoff'
    && heroState(row({ status: 'pending', matched: true, rawStatus: 'runner_pending' })) === 'directed'
    && heroState(row({ status: 'pending', matched: false })) === 'searching'
    && heroState(null) === 'none');
}
{
  // The review line names the MOST RECENT open case, and only open ones.
  const OLDER = row({ id: 'rv-older', rawStatus: 'incident_review', matched: true, scheduledAt: iso(NOW - 48 * H) });
  const p = heroPick([OLDER, REVIEW_OPEN, REVIEW_ENDED], NOW);
  t('0-ir · with an owed return AND open cases, the return is the hero and the newest open case is `review`',
    !!p.next && p.next.id === 'rv-ended' && !!p.review && p.review.id === 'rv-open', `${p.next && p.next.id} / ${p.review && p.review.id}`);
}
{
  // The rail's rules, unchanged: future confirmed/pending only, the hero excluded, nearest two.
  const C1 = row({ id: 'c1', status: 'confirmed', rawStatus: 'confirmed', matched: true, scheduledAt: iso(NOW + 5 * H) });
  const C2 = row({ id: 'c2', status: 'confirmed', rawStatus: 'confirmed', matched: true, scheduledAt: iso(NOW + 30 * H) });
  const C3 = row({ id: 'c3', status: 'confirmed', rawStatus: 'confirmed', matched: true, scheduledAt: iso(NOW + 60 * H) });
  const PAST = row({ id: 'past', status: 'confirmed', rawStatus: 'confirmed', matched: true, scheduledAt: iso(NOW - 30 * H) });
  const p = heroPick([C3, PAST, C2, C1], NOW);
  t('rail · the hero is the nearest upcoming confirmed (a 30h-old one sorts behind it)', !!p.next && p.next.id === 'c1', p.next && p.next.id);
  t('rail · the rail is the next two, nearest first, the hero excluded', p.upcoming.map((b) => b.id).join() === 'c2,c3',
    p.upcoming.map((b) => b.id).join());
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑧ [owner-journey-2] 내 일정's 지금 band — a run that ENDED is not 「달리는 중」
// ══════════════════════════════════════════════════════════════════════════════════════════════
{
  const base = { rawStatus: 'active', dogName: '콩', runnerName: '민준', startedAt: iso(NOW - 70 * 60_000), arrivedAt: null };
  const ended = nowBandLine({ ...base, runEndedAt: iso(NOW - 5 * 60_000) }, NOW);
  t('0-band · active + run_ended_at: no 「달리는 중」', !ended.line.includes('달리는 중'), ended.line);
  t('0-band · …no elapsed clause (the clock off runs.started_at would count a finished run forever)',
    !/째/.test(ended.line) && !/분|시간/.test(ended.line), ended.line);
  t('0-band · …no live door (no 실시간 보기 button, no VoiceOver live action)', ended.liveDoor === false);
  t('0-band · …the hero\'s return sentence, particles agreeing with 콩',
    ended.line === returnSentence('민준 러너', '콩') && ended.line === '민준 러너가 콩을 돌려주고 있어요', ended.line);
  // CONTROL — the same row without run_ended_at is a run in progress and keeps all three. Without
  // this arm, a band that simply stopped drawing 달리는 중 for EVERY active row would pass above.
  const live = nowBandLine({ ...base, runEndedAt: null }, NOW);
  t('0-band · CONTROL · active WITHOUT run_ended_at still says 달리는 중, with the elapsed clause, and offers the live door',
    live.line === '콩이 민준 러너와 1시간 10분째 달리는 중이에요' && live.liveDoor === true, live.line);
  t('0-band · picked_up · particle agrees (콩을), no live door yet',
    (() => { const b = nowBandLine({ ...base, rawStatus: 'picked_up', runEndedAt: null }, NOW);
      return b.line === '민준 러너가 콩을 데리고 있어요' && !b.liveDoor; })());
  t('0-band · runner_enroute + arrived · the door-wait clause, no live door',
    (() => { const b = nowBandLine({ ...base, rawStatus: 'runner_enroute', arrivedAt: iso(NOW - 6 * 60_000), runEndedAt: null }, NOW);
      return b.line === '민준 러너가 도착했어요 · 6분째 문 앞이에요' && !b.liveDoor; })());
  t('0-band · the elapsed rule is the hero\'s: under a minute, unknown or unparseable → no clause',
    elapsedLabel(iso(NOW - 30_000), NOW) === null && elapsedLabel(null, NOW) === null && elapsedLabel('nope', NOW) === null);
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑨ returnOwed — the sheet's 「반환 확인하기」 door and the hero's `returning`, one predicate
// ══════════════════════════════════════════════════════════════════════════════════════════════
// `confirm_return_tx` accepts exactly active and incident_review (0096 §2); without run_ended_at
// neither has a return to confirm. Each arm below is a place the two readings of 「returning」 differ.
t('owed · active + run_ended_at → the door', returnOwed({ rawStatus: 'active', runEndedAt: iso(NOW) }) === true);
t('owed · incident_review + run_ended_at → the door', returnOwed({ rawStatus: 'incident_review', runEndedAt: iso(NOW) }) === true);
t('owed · active WITHOUT run_ended_at → no door (a run in progress)', returnOwed({ rawStatus: 'active', runEndedAt: null }) === false);
t('owed · incident_review WITHOUT run_ended_at → no door (a case, nothing to stamp)',
  returnOwed({ rawStatus: 'incident_review', runEndedAt: null }) === false);
t('owed · a status the server refuses (completed, refund_pending) → no door even with the stamp',
  returnOwed({ rawStatus: 'completed', runEndedAt: iso(NOW) }) === false
  && returnOwed({ rawStatus: 'refund_pending', runEndedAt: iso(NOW) }) === false);

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑩ [owner-journey-5] 내 일정's `?bid=` — open THAT booking once
// ══════════════════════════════════════════════════════════════════════════════════════════════
{
  const rows = [{ id: 'A' }, { id: 'B' }];
  const before = deepLinkStep({ loaded: false, bid: 'B', handled: null, rows: [] });
  t('0-bid · nothing happens before the first successful load (an empty seed is not 「no such booking」)',
    before.open === null && before.clear === false && before.handled === null);
  const first = deepLinkStep({ loaded: true, bid: 'B', handled: before.handled, rows });
  t('0-bid · after the load, the matching booking opens and the param is to be cleared',
    first.open && first.open.id === 'B' && first.clear === true && first.handled === 'B');
  const rerender = deepLinkStep({ loaded: true, bid: 'B', handled: first.handled, rows });
  t('0-bid · a re-render (or a refetch) before the param is gone does NOT reopen it',
    rerender.open === null && rerender.clear === false && rerender.handled === 'B');
  const cleared = deepLinkStep({ loaded: true, bid: undefined, handled: rerender.handled, rows });
  t('0-bid · once the param is gone (coming back to the screen), nothing opens and the guard re-arms',
    cleared.open === null && cleared.handled === null);
  const again = deepLinkStep({ loaded: true, bid: 'B', handled: cleared.handled, rows });
  t('0-bid · a LATER door carrying the same booking opens it again', again.open && again.open.id === 'B');
  const unknown = deepLinkStep({ loaded: true, bid: 'ZZZ', handled: null, rows });
  t('0-bid · an id not in the list opens NOTHING (never a guess at another booking) and is still consumed',
    unknown.open === null && unknown.clear === true && unknown.handled === 'ZZZ');
  t('0-bid · an empty or non-string param is no param',
    deepLinkStep({ loaded: true, bid: '', handled: null, rows }).open === null
    && deepLinkStep({ loaded: true, bid: ['B'], handled: null, rows }).open === null);
  t('0-bid · scheduleDoor carries the id, and a missing id is the bare list',
    eq(scheduleDoor('B'), { pathname: '/owner/schedule', params: { bid: 'B' } })
    && scheduleDoor(null) === '/owner/schedule' && scheduleDoor('') === '/owner/schedule');
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑫ [owner-return-frame · R1 c1] THE OWNER'S OWN RETURN STAMP
// ══════════════════════════════════════════════════════════════════════════════════════════════
// Before this, every owner surface read only the PHASE (`returnOwed`), so after the owner stamped,
// the hero stayed coral 「반환 확인하기」, the band kept 「받으셨으면 확인해주세요」 and the schedule
// sheet kept a primary 「반환 확인하기」 — while the report already said 「러너 확인을 기다리고
// 있어요」. On incident_review (nothing seals, 0193 §B) that lasted until ops resolved the case, and
// the case held the hero over the owner's next booking.
// The one new conjunct is `!b.ownerReturnAt` in `ownerReturnOwed`; `ownerReturnWaitLine` is written
// in terms of it. Every fixture below sits where the old rule and the new rule DISAGREE (the owner
// has stamped), and each one has an unstamped CONTROL twin where they agree.
{
  const STAMP = iso(NOW - 10 * 60_000);
  const TOMORROW = row({ id: 'tmrw', status: 'confirmed', rawStatus: 'confirmed', matched: true, scheduledAt: iso(NOW + 24 * H) });
  // A — owner-stamped ACTIVE row: the run ended, the owner stamped, the runner has not.
  const A_STAMPED = row({ id: 'a-st', status: 'active', rawStatus: 'active', matched: true,
    runEndedAt: iso(NOW - H), scheduledAt: iso(NOW - 3 * H), ownerReturnAt: STAMP, runnerReturnAt: null });
  const A_OWED = { ...A_STAMPED, id: 'a-owed', ownerReturnAt: null };
  t('orf-1 · owner-stamped active: the owner\'s move is NOT owed', ownerReturnOwed(A_STAMPED) === false);
  t('orf-1 · …but the phase is still open (the run ended; never the live frame)',
    returnOwed(A_STAMPED) === true && heroState(A_STAMPED) === 'returning', heroState(A_STAMPED));
  t('orf-1 · …and the waiting sentence is the report\'s, verbatim',
    ownerReturnWaitLine(A_STAMPED) === '러너 확인을 기다리고 있어요' && OWNER_RETURN_WAIT_KO === '러너 확인을 기다리고 있어요',
    String(ownerReturnWaitLine(A_STAMPED)));
  const bandBase = { dogName: '콩', runnerName: '민준', startedAt: iso(NOW - 70 * 60_000), arrivedAt: null };
  const bSt = nowBandLine({ ...bandBase, rawStatus: 'active', runEndedAt: iso(NOW - H), ownerReturnAt: STAMP, runnerReturnAt: null }, NOW);
  t('orf-1 · band: no 「받으셨으면 확인해주세요」 after the owner stamped; the waiting sentence instead, no live door',
    bSt.sub === '러너 확인을 기다리고 있어요' && !/확인해주세요/.test(bSt.sub) && bSt.liveDoor === false, String(bSt.sub));
  // CONTROL twin — the same row unstamped is exactly what shipped.
  t('orf-1 · CONTROL · unstamped active: move owed, no wait line, same frame',
    ownerReturnOwed(A_OWED) === true && ownerReturnWaitLine(A_OWED) === null && heroState(A_OWED) === 'returning');
  const bOw = nowBandLine({ ...bandBase, rawStatus: 'active', runEndedAt: iso(NOW - H), ownerReturnAt: null }, NOW);
  t('orf-1 · CONTROL · band unstamped still asks: 「러닝이 끝났어요 · 받으셨으면 확인해주세요」',
    bOw.sub === '러닝이 끝났어요 · 받으셨으면 확인해주세요', String(bOw.sub));
  t('orf-1 · a reader that does not carry the stamp (undefined) keeps the pre-existing ask',
    ownerReturnOwed({ rawStatus: 'active', runEndedAt: iso(NOW - H) }) === true);

  // B — owner-stamped INCIDENT_REVIEW + a confirmed booking tomorrow. The DECISION: the case no
  // longer holds the hero; tomorrow's booking does, and the case is the quiet review line.
  const IR_STAMPED = row({ id: 'ir-st', status: 'pending', rawStatus: 'incident_review', matched: true,
    runEndedAt: iso(NOW - 2 * H), scheduledAt: iso(NOW - 4 * H), ownerReturnAt: STAMP, runnerReturnAt: null });
  const IR_OWED = { ...IR_STAMPED, id: 'ir-owed', ownerReturnAt: null };
  {
    const p = heroPick([IR_STAMPED, TOMORROW], NOW);
    t('orf-2 · ⚔ owner-stamped incident_review + a booking tomorrow → the hero is TOMORROW\'s booking',
      !!p.next && p.next.id === 'tmrw' && heroState(p.next) === 'confirmed', `${p.next && p.next.id}/${heroState(p.next)}`);
    t('orf-2 · …the stamped case is the review line (visible, not the hero), with its waiting sentence',
      !!p.review && p.review.id === 'ir-st' && ownerReturnWaitLine(p.review) === '러너 확인을 기다리고 있어요',
      JSON.stringify(p.review && p.review.id));
    t('orf-2 · …and heroRank puts it nowhere (it drops to the incident_review arm)', heroRank(IR_STAMPED) === null);
  }
  {
    // CONTROL twin — unstamped, the owed return still outranks tomorrow (the shipped behaviour).
    const p = heroPick([IR_OWED, TOMORROW], NOW);
    t('orf-2 · CONTROL · unstamped incident_review + tomorrow → the case is still the hero (owed, ranked like active)',
      !!p.next && p.next.id === 'ir-owed' && heroState(p.next) === 'returning' && p.review === null,
      `${p.next && p.next.id}/${p.review && p.review.id}`);
    t('orf-2 · CONTROL · …tomorrow is on the rail', p.upcoming.map((b) => b.id).join() === 'tmrw');
  }
  {
    // Alone (no booking ahead): the empty hero with the review line, never 「비어 있어요」 silently.
    const p = heroPick([IR_STAMPED], NOW);
    t('orf-2 · owner-stamped case alone → empty hero + the review line (home says 확인이 진행 중인 일정이 있어요)',
      p.next === null && heroState(p.next) === 'none' && !!p.review && p.review.id === 'ir-st');
  }
  // C — both stamps landed and the row is still open (incident_review seals nothing; an active row
  // sealed-not-settled is the stranded state). 「waiting for the runner」 would be false there.
  const BOTH = { ...IR_STAMPED, id: 'ir-both', runnerReturnAt: STAMP };
  t('orf-3 · both stamped → the report\'s both-stamped sentence, never 「러너 확인을 기다리고 있어요」',
    ownerReturnWaitLine(BOTH) === RETURN_BOTH_STAMPED_KO
    && RETURN_BOTH_STAMPED_KO === '양측 확인이 끝났어요 — 정산은 담당자 확인 뒤에 진행돼요', String(ownerReturnWaitLine(BOTH)));
  t('orf-3 · no wait line outside the phase (a run in progress, a completed row) even with a stamp',
    ownerReturnWaitLine({ rawStatus: 'active', runEndedAt: null, ownerReturnAt: STAMP }) === null
    && ownerReturnWaitLine({ rawStatus: 'completed', runEndedAt: iso(NOW - H), ownerReturnAt: STAMP }) === null);
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑪ SOURCE — the screens CALL these rules (no .cjs suite can import a route module)
// ══════════════════════════════════════════════════════════════════════════════════════════════
// Comments are stripped first (block, JSX-block and line): this slice's own comments quote the
// retired code — 「${name}가」, `ghostAction`, the old coral hexes — and a check for code must not be
// satisfied, or reddened, by the prose that documents its removal (the standing comment-quoting
// law). CONTROL at the end proves the stripper is load-bearing.
const stripTs = (src) => src
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n');
const APP = path.join(__dirname, '..');
const readApp = (rel) => {
  const raw = fs.readFileSync(path.join(APP, rel), 'utf8');
  t(`source · ${rel} is readable and non-empty (absence must fail LOUDLY)`, raw.length > 0);
  return raw;
};
const homeRaw = readApp('app/owner/home.tsx');
const home = stripTs(homeRaw);
const sched = stripTs(readApp('app/owner/schedule.tsx'));
const radar = stripTs(readApp('app/owner/radar.tsx'));
const heroRaw = readApp('src/components/home-hero.tsx');
const hero = stripTs(heroRaw);
const count = (src, re) => (src.match(re) || []).length;

t('source · home.tsx picks with heroPick and frames with heroState (no inline copy of the ladder)',
  /heroPick\(rows\)/.test(home) && /heroState\(liveNext\)/.test(home) && !/const RANK\b/.test(home), '');
t('source · home.tsx hands the empty hero the review door', /onOpenReview=\{reviewRow \?/.test(home));
t('source · home.tsx no longer prints 「예정된 러닝이 없어요」 (less-is-more-6) and gates 오늘 on lastDone',
  !/예정된 러닝이 없어요/.test(home) && /goState === 'none' && bookingsLoaded && !bookingsErr && lastDone &&/.test(home));
t('source · home.tsx rail rows carry their booking to 내 일정', /onPress=\{\(\) => openSchedule\(b\.id\)\}/.test(home));
t('source · home.tsx 「대기 중인 러너」 has no trailing leaderboard link (less-is-more-5)',
  /<ModH title="대기 중인 러너" \/>/.test(home) && !/주간 랭킹 ›/.test(home));
t('source · home.tsx no longer prints a latin 「RUNS」 unit', !/ RUNS</.test(home));
t('source · schedule.tsx reads `bid` and consumes it through deepLinkStep',
  /useLocalSearchParams<\{ bid\?: string \}>\(\)/.test(sched) && /deepLinkStep\(\{ loaded, bid: bidParam/.test(sched)
  && /router\.setParams\(\{ bid: undefined \}\)/.test(sched));
// ⚠ Measured in this slice's battery (P16): the first version matched a bare `band.liveDoor &&`,
// which ALSO occurs inside the a11y-action handler — so re-gating the button on the raw word
// left the pattern present and this arm green. A pattern present in both states is not a check.
t('source · schedule.tsx draws the 지금 band from nowBandLine and gates the live door on it',
  /nowBandLine\(b\)/.test(sched) && /\{band\.liveDoor && \(\s*<Pressable/.test(sched)
  && /accessibilityActions=\{band\.liveDoor \?/.test(sched)
  // …and the raw word no longer gates a live door or action anywhere in the band's row
  && !/\{b\.rawStatus === 'active' && \(\s*<Pressable/.test(sched)
  && !/accessibilityActions=\{b\.rawStatus === 'active' \?/.test(sched));
// [owner-return-frame] Updated: this arm counted `returnOwed(selected)` ≥ 2 because the review arm's
// door used the phase predicate. That door is now keyed on the owner's MOVE (`ownerReturnOwed`), so
// the phase appears once (the active arm's key) and the ownership of 「반환 확인하기」 moved to the
// orf-src pin below.
t('source · schedule.tsx: the sheet\'s return arm precedes the live arm (keyed on the PHASE), and the review arm has the same door',
  /selected\.status === 'active' && returnOwed\(selected\) \?/.test(sched)
  && count(sched, /label="반환 확인하기"/g) === 2);
t('source · schedule.tsx: the status caption of an active row whose run ENDED is the return phase, not 「러닝 중 · LIVE」',
  /if \(b\.rawStatus === 'active' && returnOwed\(b\)\) return \{ label: RETURN_PHASE_LABEL/.test(sched)
  && !/러닝 중|LIVE|달리는/.test(RETURN_PHASE_LABEL), RETURN_PHASE_LABEL);
t('source · schedule.tsx: no text drawn in the retired live inks (#d84a2f 3.64:1 · #b06a56 3.57:1)',
  !/#d84a2f/i.test(sched) && !/#b06a56/i.test(sched));
t('source · schedule.tsx: the live FACE is kept (#ffe9e2 ground, #ffc9b8 border)',
  /#ffe9e2/.test(sched) && /#ffc9b8/.test(sched));
t('source · schedule.tsx: `ghostAction` is gone from executable code (ui-consistency-10)', !/ghostAction/.test(sched));
t('source · schedule.tsx: the TRUE empty draws 「러닝 예약하기」, guarded on no bookings at all',
  /liveBookings\.length === 0 && \(\s*<PaperBtn label="러닝 예약하기"/.test(sched) && count(sched, /label="러닝 예약하기"/g) === 1);
t('source · radar.tsx wears ScreenHead and hand-rolls no back key',
  /<ScreenHead title=\{title\}/.test(radar) && !/accessibilityLabel="뒤로"/.test(radar) && !/>‹</.test(radar));
t('source · radar.tsx: every exit to 내 일정 carries the booking',
  count(radar, /exitTo\(scheduleHref\(bookingId\)/g) === 3 && !/exitTo\('\/owner\/schedule'/.test(radar));
t('source · home-hero.tsx: the returning button says 반환 확인하기 (copy-hierarchy-8)',
  /title="반환 확인하기"/.test(hero) && /accessibilityLabel="반환 확인하기"/.test(hero) && !/인계 확인하기/.test(hero));
t('source · home-hero.tsx: no hard-coded particle after an interpolated name (copy-hierarchy-1)',
  !/name\}(가|를|와|는)[\s`<]/.test(hero) && /withParticle\(name, '가\/이'\)/.test(hero) && /returnSentence\(runner, name\)/.test(hero));
t('source · home.tsx: no hard-coded 가 after the dog name (the live sentence and widget)',
  !/'아이'\}가/.test(home) && count(home, /withParticle\(liveNext\.dogName \?\? dogName \?\? '아이', '가\/이'\)/g) === 2);
// [owner-return-frame · R1 c1] The owner's-move surfaces no behavioural test can reach (route and
// component modules). Comment-stripped like everything in ⑪: this slice's comments NAME the
// buttons and predicates they gate, and a comment must not satisfy a check for code.
const api = stripTs(readApp('src/lib/api.ts'));
t('orf-src · schedule.tsx: BOTH 「반환 확인하기」 primaries are keyed on the owner\'s MOVE, and there is no third',
  count(sched, /\{ownerReturnOwed\(selected\) \? \(\s*<PaperBtn\s+label="반환 확인하기"/g) === 2
  && count(sched, /label="반환 확인하기"/g) === 2,
  `gated=${count(sched, /\{ownerReturnOwed\(selected\) \? \(\s*<PaperBtn\s+label="반환 확인하기"/g)}`);
t('orf-src · schedule.tsx: after the owner stamps, both arms say the report\'s waiting sentence',
  /러닝이 끝났어요 — \{ownerReturnWaitLine\(selected\) \?\? returnSentence\(/.test(sched)
  && /\) : ownerReturnWaitLine\(selected\) \? \(/.test(sched));
t('orf-src · home-hero.tsx: the coral 「반환 확인하기」 is the else-arm of `returnWait`, and appears once',
  /\{returnWait \? \(\s*<DrawButton title="리포트 보기"[^>]*ground="blue"[\s\S]*?\) : \(\s*<DrawButton title="반환 확인하기"[^>]*ground="coral"/.test(hero)
  && count(hero, /title="반환 확인하기"/g) === 1);
t('orf-src · home-hero.tsx: the returning chip is coral only without a wait, and the sub reads the wait first',
  /state === 'returning' \? \(returnWait \? \{ c: WAIT_BLUE, t: '확인 대기' \} : \{ c: paper\.action, t: '내 차례' \}\)/.test(hero)
  && /\{returnWait \?\? `\$\{returnSentence\(runner, name\)\} · 받으셨으면 확인해주세요`\}/.test(hero)
  && /const returnWait = state === 'returning' \? next\?\.returnWait \?\? null : null;/.test(hero));
t('orf-src · home-hero.tsx: the in-flight frames carry a stamped case as one quiet line (pending dot, a role)',
  /\{inFlight && reviewWait && onOpenReview \? \(\s*<Pressable onPress=\{onOpenReview\} style=\{s\.alertRow\} accessibilityRole="button"/.test(hero));
t('orf-src · home.tsx hands the hero both wait lines, computed from the real rows',
  /returnWait: ownerReturnWaitLine\(liveNext\),/.test(home)
  && /reviewWait=\{reviewRow \? ownerReturnWaitLine\(reviewRow\) : null\}/.test(home));
{
  const sel = (api.match(/const MY_BOOKING_SELECT =\s*'([^']*)'/) || [])[1] || '';
  const mapper = (api.match(/function mapMyBooking\(r: any\): Booking \{[\s\S]*?\n\}\n/) || [])[0] || '';
  t('orf-src · api.ts: the owner booking select carries BOTH return stamps (exact column names)',
    /(^|[\s,])owner_confirmed_return_at(,|$)/.test(sel) && /(^|[\s,])runner_confirmed_return_at(,|$)/.test(sel), sel.slice(0, 60));
  t('orf-src · api.ts: mapMyBooking maps them (the runner reader\'s identical line elsewhere does not count)',
    mapper.length > 0
    && /ownerReturnAt: r\.owner_confirmed_return_at \?\? null,/.test(mapper)
    && /runnerReturnAt: r\.runner_confirmed_return_at \?\? null,/.test(mapper), `mapper=${mapper.length}`);
}

// CONTROL — the stripper is what keeps prose out. Appending a comment that QUOTES the retired
// particle to a copy of the source must not move the executable read; the crude raw read must move.
{
  const planted = heroRaw + '\n// retired: `${name}가 달려요` — quoted in prose only\n';
  t('CONTROL · a comment quoting the retired particle does NOT redden the executable read',
    !/name\}(가|를|와|는)[\s`<]/.test(stripTs(planted)));
  t('CONTROL · …and the crude raw-text read IS fooled by it (so the stripper is load-bearing)',
    /name\}(가|를|와|는)[\s`<]/.test(planted));
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
