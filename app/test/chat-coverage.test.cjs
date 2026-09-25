// chat-coverage — FETCHED COVERAGE and the read ceiling it licenses (codex client review wave 4 · c1).
//
// Runs against the REAL compiled source: run-chat-coverage-tests.sh bundles chat-messages.ts,
// chat-read.ts and chat-window.ts with esbuild, and every decision below is one of theirs.
//
// THE DEFECT, measured by the reviewer on the compiled helpers and reproduced here as a CONTROL:
// the screen holds FETCHED message 1 and REALTIME-ONLY message 102 (the channel dropped 2–101 across
// a reconnect); the next poll returns the newest window, 102–201. `snapshotGap` anchors on ANY held
// message, finds 102, and answers `null` — no hole, no door, no ceiling — and the acknowledgement
// then names 201, across 2–101, which no fetch returned and no screen drew.
//
// ⚠ HONEST ABOUT WHAT THIS IS: `screen` below is a DRIVER over the real functions, composed the way
//   `app/app/chat.tsx` composes them (initial window → realtime arrival → snapshot → bounded fill →
//   acknowledgement). It proves the decisions compose; that chat.tsx actually calls them in that
//   shape is the SOURCE pins in chat-window.test.cjs ⑨/⑩, and NEITHER IS EVIDENCE FOR THE OTHER.
//
// THE MUTATIONS THAT REDDEN THIS FILE: merge every stretch into one (coverage = 「everything I have
//   seen」) · read the ceiling off the HIGHEST stretch instead of the lowest · let a realtime arrival
//   join the coverage · merge stretches that merely touch · let an older page vouch past its cursor
//   · drop the `ceiling` arm from `newestPeerMessageId`.
const {
  mergeMessageSnapshot, snapshotGap, windowSpan, olderPageSpan, addCoverage, coverageCeiling,
  coverageHole, compareMessageOrder,
} = require('./chat-coverage.messages.build.cjs');
const { newestPeerMessageId } = require('./chat-coverage.read.build.cjs');
const { CHAT_PAGE_SIZE, pageIsLast } = require('./chat-coverage.window.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const show = (v) => JSON.stringify(v);

/** A real server instant for message n — one second apart, so id order IS server order here. */
const at = (n) => new Date(Date.UTC(2026, 8, 25, 10, 0, 0) + n * 1000).toISOString();
const peer = (id) => ({ id, createdAt: at(id), mine: false, body: 'm' + id });
const range = (a, b) => { const out = []; for (let id = a; id <= b; id += 1) out.push(peer(id)); return out; };

/** The server: the newest window of what exists, and 「strictly older than the cursor」 pages. */
const server = (last) => {
  const all = range(1, last);
  const byPair = (x, y) => compareMessageOrder(x, y);
  return {
    newest: () => all.slice(-CHAT_PAGE_SIZE),
    older: (cursor) => all.filter((m) => byPair(m, cursor) < 0).sort(byPair).slice(-CHAT_PAGE_SIZE),
  };
};

/** The screen, as chat.tsx composes the helpers. */
const screen = () => {
  const s = { msgs: [], fetched: new Set(), cov: [] };
  const vouch = (page) => { for (const m of page) s.fetched.add(m.id); };
  s.open = (history) => {
    vouch(history);
    s.cov = addCoverage([], windowSpan(history, pageIsLast(history.length, CHAT_PAGE_SIZE)));
    s.msgs = mergeMessageSnapshot(s.msgs, history);
  };
  // Realtime: the message goes on screen. It vouches for nothing.
  s.realtime = (m) => { s.msgs = mergeMessageSnapshot([...s.msgs.filter((x) => x.id !== m.id), m], []); };
  s.snapshot = (page) => {
    vouch(page);
    s.msgs = mergeMessageSnapshot(s.msgs, page);
    s.cov = addCoverage(s.cov, windowSpan(page, pageIsLast(page.length, CHAT_PAGE_SIZE)));
  };
  s.fill = (older, maxPages) => {
    let pages = 0;
    for (let i = 0; i < maxPages; i += 1) {
      const hole = coverageHole(s.cov);
      if (hole === null) break;
      const page = older(hole.cursor); // a throwing server leaves everything as it was
      pages += 1;
      vouch(page);
      s.msgs = mergeMessageSnapshot(s.msgs, page);
      s.cov = addCoverage(s.cov, olderPageSpan(page, hole.cursor, pageIsLast(page.length, CHAT_PAGE_SIZE)));
    }
    return pages;
  };
  s.target = () => {
    const ceiling = coverageCeiling(s.cov);
    return ceiling === null ? null : newestPeerMessageId(s.msgs, { ceiling, fetchedIds: s.fetched });
  };
  return s;
};

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ① THE REVIEWER'S SEQUENCE — control first, then the fix
// ══════════════════════════════════════════════════════════════════════════════════════════════
{
  const s = screen();
  s.open(server(1).newest());            // the thread had one message when the screen opened
  s.realtime(peer(102));                 // reconnect: 2–101 dropped, 102 delivered
  const held = s.msgs;
  const snap = server(201).newest();     // the poll: the newest window, 102–201
  t('fixture — the snapshot is exactly 102–201, the window the reviewer measured',
    snap.length === 100 && snap[0].id === 102 && snap[99].id === 201);

  // CONTROL: the OLD mechanism, on the same fixture. If this does not reproduce, the pins below
  // would be proving a fix for a hole the fixture never had.
  t('control — the old detector sees NO hole (102 is held, realtime-only): the defect reproduces',
    snapshotGap(held, snap) === null);
  const oldFetched = new Set([1, ...snap.map((m) => m.id)]);
  const oldTarget = newestPeerMessageId(mergeMessageSnapshot(held, snap), { ceilingId: null, fetchedIds: oldFetched });
  t('control — and the old acknowledgement names 201, across 2–101 that nobody drew',
    oldTarget === 201, String(oldTarget));

  s.snapshot(snap);
  const hole = coverageHole(s.cov);
  t('🔴 [c1] coverage sees the hole the held list hides: between fetched 1 and fetched 102',
    hole !== null && hole.afterId === 1 && hole.cursor.id === 102, show(hole));
  t('🔴 [c1] the read ceiling is message 1 — the top of the stretch fetches returned in full',
    coverageCeiling(s.cov) !== null && coverageCeiling(s.cov).id === 1, show(coverageCeiling(s.cov)));
  t('🔴 [c1] …so the acknowledgement names 1, NOT 201 — nothing in 2–101 is claimed read',
    s.target() === 1, String(s.target()));

  // The fill closes it — and only then does the acknowledgement advance.
  const oneMore = screen(); Object.assign(oneMore, { msgs: s.msgs, fetched: new Set(s.fetched), cov: s.cov });
  const pages = s.fill(server(201).older, 3);
  t('the bounded fill closes the hole (two pages: 2–101, then 1 — touching is not overlapping)',
    coverageHole(s.cov) === null && pages === 2, `pages=${pages} cov=${show(s.cov)}`);
  t('…the thread on screen is unbroken 1–201',
    s.msgs.length === 201 && s.msgs.every((m, i) => m.id === i + 1));
  t('…and NOW the acknowledgement reaches 201', s.target() === 201, String(s.target()));

  // A bound that runs out keeps the ceiling where it was.
  oneMore.fill(server(201).older, 1);
  const still = coverageHole(oneMore.cov);
  t('a fill cut short by its bound leaves the hole open, its cursor further back (the door resumes)',
    still !== null && still.afterId === 1 && still.cursor.id === 2, show(still));
  t('…and the acknowledgement stays at 1', oneMore.target() === 1, String(oneMore.target()));

  // A fill that FAILS changes nothing.
  const failed = screen(); Object.assign(failed, { msgs: held, fetched: new Set([1]), cov: addCoverage([], windowSpan([peer(1)], true)) });
  failed.snapshot(snap);
  let threw = false;
  try { failed.fill(() => { throw new Error('network'); }, 3); } catch { threw = true; }
  t('a failed fill leaves the hole, the door and the ceiling exactly where they were',
    threw && coverageHole(failed.cov) !== null && failed.target() === 1);
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ② TWO HOLES — the second is not dropped, and the read stops below it
// ══════════════════════════════════════════════════════════════════════════════════════════════
// The old screen held ONE door and dropped a second hole found while a fill ran; once the first
// closed it cleared the door and the ceiling with it, and the read jumped the second hole.
{
  const s = screen();
  s.open(server(50).newest());           // 1–50, the whole thread (short page)
  s.snapshot(server(300).newest());      // 201–300: hole 51–200
  s.snapshot(server(600).newest());      // 501–600: hole 301–500
  t('two holes are two stretches above the first — three in all',
    s.cov.length === 3, show(s.cov));
  t('the door is the LOWEST hole', coverageHole(s.cov) !== null && coverageHole(s.cov).afterId === 50);
  t('the ceiling is the top of the lowest stretch', s.target() === 50, String(s.target()));
  s.fill(server(600).older, 3);          // 101–200, 1–100 (first hole closed), 401–500
  const next = coverageHole(s.cov);
  t('🔴 [c1] after the first hole closes the SECOND is the door — it was never dropped',
    next !== null && next.afterId === 300 && next.cursor.id === 401, show(next));
  t('🔴 [c1] and the read stops at 300, below the second hole — not 600',
    s.target() === 300, String(s.target()));
  s.fill(server(600).older, 3);
  t('…until that one closes too', coverageHole(s.cov) === null && s.target() === 600, String(s.target()));
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ③ the spans themselves
// ══════════════════════════════════════════════════════════════════════════════════════════════
t('a short window reaches the thread start (lo = null) — it IS the whole thread',
  (() => { const w = windowSpan(range(1, 3), true); return w !== null && w.lo === null && w.hi.id === 3; })());
t('a full window starts at its own oldest message',
  (() => { const w = windowSpan(range(1, 100), false); return w !== null && w.lo !== null && w.lo.id === 1 && w.hi.id === 100; })());
t('an empty window vouches for nothing', windowSpan([], true) === null);
t('a window holding a message that cannot be placed in time vouches for NOTHING — never a guess',
  windowSpan([peer(1), { id: 2, createdAt: 'not a time', mine: false }], false) === null);
t('an EMPTY older page means nothing older exists: the stretch reaches the start, up to the cursor',
  (() => { const o = olderPageSpan([], { createdAt: at(10), id: 10 }, true); return o !== null && o.lo === null && o.hi.id === 10; })());
t('an older page vouches from its oldest message UP TO the cursor',
  (() => { const o = olderPageSpan(range(1, 100), { createdAt: at(101), id: 101 }, false); return o !== null && o.lo !== null && o.lo.id === 1 && o.hi.id === 101; })());
t('an older page holding a message NOT older than its cursor vouches for nothing — it did not answer the question',
  olderPageSpan([peer(5), peer(12)], { createdAt: at(10), id: 10 }, false) === null);
t('an older page asked with a cursor that cannot be placed vouches for nothing',
  olderPageSpan(range(1, 3), { createdAt: 'nope', id: 4 }, false) === null);

const span = (lo, hi) => ({ lo: lo === null ? null : { createdAt: at(lo), id: lo }, hi: { createdAt: at(hi), id: hi } });
const ids = (cov) => cov.map((s) => [s.lo === null ? null : s.lo.id, s.hi.id]);
t('overlapping stretches merge', show(ids(addCoverage([span(1, 10)], span(5, 20)))) === show([[1, 20]]));
t('🔴 stretches that merely TOUCH stay apart — only a fetch across the boundary may join them',
  show(ids(addCoverage([span(1, 10)], span(11, 20)))) === show([[1, 10], [11, 20]]));
t('a shared endpoint is an overlap (an older page ends AT its cursor)',
  show(ids(addCoverage([span(11, 20)], span(1, 11)))) === show([[1, 20]]));
t('a stretch reaching the start swallows everything it overlaps',
  show(ids(addCoverage([span(5, 10), span(30, 40)], span(null, 35)))) === show([[null, 40]]));
t('the union does not depend on the order fetches landed in',
  show(ids([span(30, 40), span(1, 10), span(8, 31)].reduce((c, s) => addCoverage(c, s), [])))
  === show(ids([span(8, 31), span(30, 40), span(1, 10)].reduce((c, s) => addCoverage(c, s), [])))
  && show(ids([span(30, 40), span(1, 10), span(8, 31)].reduce((c, s) => addCoverage(c, s), []))) === show([[1, 40]]));
t('adding nothing changes nothing', (() => { const c = [span(1, 2)]; return addCoverage(c, null) === c; })());
t('no coverage → no ceiling → nothing may be recorded', coverageCeiling([]) === null);
t('one stretch → no hole', coverageHole([span(null, 9)]) === null);

// ── the ceiling arm of newestPeerMessageId, in the server's order ─────────────────────────────
const T = '2026-09-25T10:00:00.123456Z';
const tie = [4, 5, 6].map((id) => ({ id, createdAt: T, mine: false }));
t('🔴 [c1] the ceiling is compared as the (created_at, id) PAIR — a same-instant sibling above it is excluded',
  newestPeerMessageId(tie, { ceiling: { createdAt: T, id: 5 } }) === 5);
t('a message that cannot be placed against the ceiling is excluded, never let through',
  newestPeerMessageId([{ id: 9, createdAt: 'garbage', mine: false }, { id: 1, createdAt: at(1), mine: false }],
    { ceiling: { createdAt: at(50), id: 50 } }) === 1);
t('control — with no ceiling the same list names its newest (the arm above is doing the work)',
  newestPeerMessageId(tie) === 6);

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
