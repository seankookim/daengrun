// a11y-announce-gate.ts — the de-dupe + rate-limit decision behind every VoiceOver announcement
// added for HIG A3/A6. Runs against the REAL compiled source (see run-a11y-announce-tests.sh),
// not a retyped copy.
//
// What this file is FOR. The gate is the only thing standing between a screen that moves by itself
// and a screen reader that narrates every intermediate frame. Its two properties are cheap to
// state and easy to break silently by "simplifying":
//   ① the same sentence is never spoken twice in a row, and
//   ② at most one utterance per window, with the LAST offer winning rather than the first.
// Break ① and a re-render narrates a change that did not happen. Break ② into a QUEUE instead of
// a replacement and the user hears a stale sentence describing a state that is already gone —
// which is worse than silence, because it is wrong rather than missing.
//
// The mutations that redden it: drop the `text === lastSpoken` arm (①) · make `offer` inside the
// window queue instead of replace (②) · let the re-offer arm restart the window · let an empty
// string through · let `flush` speak without re-checking the window · drop the flap-back
// cancellation · change ANNOUNCE_MIN_GAP_MS without changing the screens that assume it.
//
// ⚠ Every case drives the clock explicitly. A test that read Date.now() could not distinguish
// 「the window is respected」 from 「the machine was slow enough」.
const { createAnnounceGate, ANNOUNCE_MIN_GAP_MS } = require('./a11y-announce.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const GAP = ANNOUNCE_MIN_GAP_MS;

// ── the window is a contract, not an implementation detail ─────────────────────────────────────
// The screens do not set it; they inherit it. If it moves, the burst behaviour of every
// self-updating screen moves with it, so the value is pinned here rather than left to drift.
t('window is 1500ms', GAP === 1500, 'got ' + GAP);

// ── ① never the same sentence twice in a row ───────────────────────────────────────────────────
{
  const g = createAnnounceGate();
  const first = g.offer('러너가 출발했어요', 0);
  t('first offer speaks', first.action === 'speak' && first.text === '러너가 출발했어요');

  // Immediately: identical text. This is the ordinary case — a re-render with an unchanged label.
  const again = g.offer('러너가 출발했어요', 10);
  t('identical text inside the window drops', again.action === 'drop' && again.text === null);

  // And de-dupe is NOT time-limited. A screen that re-renders the same label ten minutes later
  // has still not changed state, and the user has still already heard it.
  const muchLater = g.offer('러너가 출발했어요', 10 * 60_000);
  t('identical text after the window still drops', muchLater.action === 'drop');
  t('  …and did not re-stamp the clock', g.spoken() === '러너가 출발했어요');
}

// ── ② one utterance per window, LAST offer wins ────────────────────────────────────────────────
{
  const g = createAnnounceGate();
  t('A speaks', g.offer('픽업 완료', 0).action === 'speak');

  const b = g.offer('러닝 중', 100);
  t('B inside the window defers', b.action === 'defer' && b.text === '러닝 중');
  t('  …with the remaining window', b.waitMs === GAP - 100, 'got ' + b.waitMs);
  t('  …and B is pending', g.pending() === '러닝 중');

  // The state moved on again before the window closed. B is now history — it must be REPLACED,
  // not queued behind. This is the arm that separates 「the user hears where they are」 from
  // 「the user hears where they were」.
  const c = g.offer('귀가 확인 요청', 500);
  t('C replaces B (last one wins)', c.action === 'defer' && g.pending() === '귀가 확인 요청');
  t('  …and B is gone, not queued', g.pending() !== '러닝 중');

  // Timer fires before the window closes — re-defer, never speak early.
  const early = g.flush(1000);
  t('flush before the window re-defers', early.action === 'defer' && early.waitMs === GAP - 1000);
  t('  …and nothing was spoken', g.spoken() === '픽업 완료');

  const done = g.flush(GAP);
  t('flush at the window speaks the LAST offer', done.action === 'speak' && done.text === '귀가 확인 요청');
  t('  …and B was never spoken', g.spoken() === '귀가 확인 요청');
  t('  …and the queue is empty', g.pending() === null);
}

// ── re-offering the pending text must not restart the window ───────────────────────────────────
// A screen re-renders constantly. If each render reset the timer, a value that changed once and
// then stayed put would be deferred forever and never announced at all.
{
  const g = createAnnounceGate();
  g.offer('첫 문장', 0);
  const d1 = g.offer('두 번째 문장', 200);
  const d2 = g.offer('두 번째 문장', 900);
  t('re-offering the pending text keeps deferring', d2.action === 'defer' && d2.text === '두 번째 문장');
  t('  …and the wait SHRINKS rather than resetting', d2.waitMs < d1.waitMs && d2.waitMs === GAP - 900,
    'd1=' + d1.waitMs + ' d2=' + d2.waitMs);
  t('  …so it still speaks on time', g.flush(GAP).action === 'speak');
}

// ── flapping back to what was just spoken cancels the pending intermediate ──────────────────────
// Measured shape this guards: a status polls B then immediately back to A. The user already heard
// A. Announcing B afterwards narrates a change the screen no longer shows.
{
  const g = createAnnounceGate();
  g.offer('러너 찾는 중', 0);
  g.offer('응답 대기', 300);
  t('B is pending before the flap', g.pending() === '응답 대기');
  const back = g.offer('러너 찾는 중', 600);
  t('flapping back to the spoken text drops', back.action === 'drop');
  t('  …and cancels the pending intermediate', g.pending() === null);
  t('  …so the flush says nothing', g.flush(GAP).action === 'drop');
}

// ── the window re-arms on the DEFERRED utterance, not on the one before it ─────────────────────
// After a flush speaks, the clock restarts from that utterance. The next sentence therefore waits
// a full window from the flush, not from the original speak — otherwise a deferred announcement
// and the one behind it land back to back and the gap the window exists to create never happens.
{
  const g = createAnnounceGate();
  g.offer('A', 0);              // spoken at 0
  g.offer('B', 100);            // deferred
  t('B speaks at the flush', g.flush(GAP).action === 'speak');
  // C arrives 10ms after B was SPOKEN. Measured from A it is outside the window; measured from B
  // it is 10ms in. It must defer — which is only true if the flush re-armed the clock.
  const c = g.offer('C', GAP + 10);
  t('the next sentence defers from the FLUSH, not the first speak',
    c.action === 'defer' && c.waitMs === GAP - 10, 'got ' + c.action + '/' + c.waitMs);
  t('C speaks one full window after B', g.flush(GAP * 2 + 10).action === 'speak');
  t('  …and C is what was spoken', g.spoken() === 'C');
}

// ── an empty sentence is not a state ───────────────────────────────────────────────────────────
// `null`/'' is what a screen produces when it has no honest label for the state it is in. It must
// neither be uttered nor displace a real sentence that is waiting.
{
  const g = createAnnounceGate();
  g.offer('실제 문장', 0);
  g.offer('다음 문장', 100);
  t('empty string drops', g.offer('', 200).action === 'drop');
  t('whitespace-only drops', g.offer('   ', 250).action === 'drop');
  t('  …and did NOT displace the pending sentence', g.pending() === '다음 문장');
  t('non-string drops', g.offer(null, 300).action === 'drop');
  t('  …and still did not displace it', g.pending() === '다음 문장');
  t('the real sentence still speaks', g.flush(GAP).text === '다음 문장');
}

// ── flush with nothing pending ─────────────────────────────────────────────────────────────────
{
  const g = createAnnounceGate();
  t('flush on an untouched gate drops', g.flush(0).action === 'drop');
  g.offer('말', 0);
  t('flush after a bare speak drops', g.flush(GAP * 3).action === 'drop');
}

// ── a distinct sentence AFTER the window speaks immediately ────────────────────────────────────
// The window is a floor on the gap between utterances, not a delay on every one of them. A state
// that changes once a minute must be announced the moment it changes.
{
  const g = createAnnounceGate();
  g.offer('출발', 0);
  const later = g.offer('도착', GAP);
  t('a distinct sentence at the window speaks at once', later.action === 'speak' && later.text === '도착');
  const muchLater = g.offer('완료', GAP * 10);
  t('  …and so does the next one', muchLater.action === 'speak');
}

// ── waitMs is never 0 ──────────────────────────────────────────────────────────────────────────
// The caller turns this into setTimeout. A 0 there is a spin, and the deferred sentence is the one
// that would spin — the busiest case, on the screen with a GPS fix arriving every second.
{
  const g = createAnnounceGate();
  g.offer('하나', 0);
  const edge = g.offer('둘', GAP - 1);
  t('waitMs at the very edge is ≥ 1', edge.action === 'defer' && edge.waitMs >= 1, 'got ' + edge.waitMs);
  const reflush = g.flush(GAP - 1);
  t('flush at the edge re-defers with ≥ 1', reflush.action !== 'speak' ? reflush.waitMs >= 1 : true);
}

// ── custom window, and gates are independent ───────────────────────────────────────────────────
{
  const fast = createAnnounceGate(100);
  fast.offer('x', 0);
  t('custom window honoured', fast.offer('y', 50).waitMs === 50);
  t('  …and opens on time', fast.flush(100).action === 'speak');

  const a = createAnnounceGate();
  const b = createAnnounceGate();
  a.offer('같은 문장', 0);
  t('a second gate does not inherit the first gate\'s history',
    b.offer('같은 문장', 0).action === 'speak');
}

// ── reset ──────────────────────────────────────────────────────────────────────────────────────
{
  const g = createAnnounceGate();
  g.offer('문장', 0);
  g.offer('다른 문장', 10);
  g.reset();
  t('reset clears the pending text', g.pending() === null);
  t('reset clears the spoken text', g.spoken() === null);
  t('reset re-opens the window', g.offer('문장', 20).action === 'speak');
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
