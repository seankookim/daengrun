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
//   · drop the `ceiling` arm from `newestPeerMessageId` · [⑤ forward-dated] drop the admitted-count
//   arm of `shouldMarkRead`'s 'message' reason · let a realtime-only arrival join the count.
const {
  mergeMessageSnapshot, snapshotGap, windowSpan, olderPageSpan, addCoverage, coverageCeiling,
  coverageHole, compareMessageOrder, autoFillDecision,
} = require('./chat-coverage.messages.build.cjs');
const readMod = require('./chat-coverage.read.build.cjs');
const { newestPeerMessageId, shouldMarkRead } = readMod;
// Written first and measured against the base, where this export did not exist: a FAIL row there,
// never a crash that hides every other row.
const admittedPeerCount = (...a) =>
  (typeof readMod.admittedPeerCount === 'function' ? readMod.admittedPeerCount(...a) : NaN);
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

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ④ THE AUTOMATIC FILL IS BOUNDED PER HOLE, NOT PER POLL (codex wave 4 review · low)
// ══════════════════════════════════════════════════════════════════════════════════════════════
// The reviewer's probe, on these helpers: a thread that moved on by 5 000 messages closed with no
// tap after 17 poll ticks and 50 pages fetched automatically, because every snapshot asked only
// 「is a hole open?」. `tick` below is chat.tsx's absorbSnapshot: merge, cover, then ask the rule.
// The MUTATION this section exists for: `fill: hole !== null` (the per-poll rule) reddens ④b/④c.
{
  const MAX = 3; // chat.tsx GAP_FILL_MAX_PAGES — chat-window.test.cjs pins the constant itself
  const run = (rule) => {
    const s = screen();
    const srv = server(5100);
    s.open(server(100).newest());                 // 1–100, a full window: older pages exist
    let remembered = null;
    let autoPages = 0;
    for (let tick = 0; tick < 17; tick += 1) {
      s.snapshot(srv.newest());                   // 5001–5100 every tick: the thread is quiet now
      const d = rule(coverageHole(s.cov), remembered);
      remembered = d.remember;
      if (d.fill) autoPages += s.fill(srv.older, MAX);
    }
    return { s, autoPages, remembered };
  };
  const fixed = run(autoFillDecision);
  const perPoll = run((hole) => ({ fill: hole !== null, remember: null }));
  t('④a control — the per-poll rule reproduces the review: the whole backfill runs with no tap',
    coverageHole(perPoll.s.cov) === null && perPoll.autoPages === 50, `pages=${perPoll.autoPages}`);
  t('🔴 ④b the automatic fill spends ONE budget on the hole — then stops',
    fixed.autoPages === MAX, `pages=${fixed.autoPages}`);
  const door = coverageHole(fixed.s.cov);
  t('🔴 ④c …and the hole is still open for the DOOR, with the read held below it',
    door !== null && door.afterId === 100 && fixed.s.target() === 100, `${show(door)} target=${fixed.s.target()}`);
  t('④d a NEW lowest hole earns one more automatic fill; no hole forgets the last one',
    autoFillDecision({ afterId: 7 }, 3).fill === true
    && autoFillDecision({ afterId: 7 }, 7).fill === false
    && autoFillDecision({ afterId: 7 }, 7).remember === 7
    && autoFillDecision(null, 7).fill === false && autoFillDecision(null, 7).remember === null);
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑤ A FORWARD-DATED PEER ROW — the screen re-marks on a fetched arrival (0235 §0c, client half)
// ══════════════════════════════════════════════════════════════════════════════════════════════
// A pre-0225 client dated a message in the future. In the server's `(created_at, id)` order it
// stays the newest, so every newest-window snapshot ends at it and the acknowledgement target is
// it — before and after a real message lands. `ack` below is chat.tsx's acknowledgement effect:
// target and admitted count under the coverage ceiling, `shouldMarkRead`, then remember both.
{
  const FWD = '2099-01-01T00:00:00.000000Z';
  const fwdRow = { id: 6, createdAt: FWD, mine: false, body: 'forward-dated' };
  const fwdServer = (lastReal) => {
    const all = range(1, 5).concat([fwdRow], range(7, lastReal)).sort((x, y) => compareMessageOrder(x, y));
    return { newest: () => all.slice(-CHAT_PAGE_SIZE) };
  };
  const acker = (s) => {
    const a = { marked: [], lastTarget: null, lastCount: null, opened: false };
    a.ack = () => {
      const ceiling = coverageCeiling(s.cov);
      const opts = { ceiling, fetchedIds: s.fetched };
      const target = ceiling === null ? null : newestPeerMessageId(s.msgs, opts);
      const count = ceiling === null ? 0 : admittedPeerCount(s.msgs, opts);
      const ok = shouldMarkRead({
        reason: a.opened ? 'message' : 'open', ready: true, appActive: true, focused: true,
        newestPeerMessageId: target, lastMarkedPeerMessageId: a.lastTarget,
        admittedPeerCount: count, lastMarkedAdmittedPeerCount: a.lastCount,
      });
      if (!ok || target === null) return null;
      a.opened = true; a.lastTarget = target; a.lastCount = count; a.marked.push(target);
      return target;
    };
    return a;
  };

  const s = screen();
  s.open(fwdServer(0).newest());            // 1–5 + the forward row, the whole thread (short page)
  const a = acker(s);
  t('⑤ fixture — the forward-dated row sits on top of the window, and opening acknowledges it',
    s.msgs.length === 6 && coverageCeiling(s.cov).id === 6 && a.ack() === 6, show(a.marked));

  s.realtime(peer(7));                       // a real message, delivered by realtime only
  t('🔴 ⑤ a realtime-only arrival is NOT acknowledged — no fetch vouched for it (client-review-4 holds)',
    a.ack() === null && admittedPeerCount(s.msgs, { ceiling: coverageCeiling(s.cov), fetchedIds: s.fetched }) === 6);

  s.snapshot(fwdServer(7).newest());         // the poll returns it
  t('⑤ control — the poll does not move the target: it is still the forward-dated row',
    s.target() === 6, String(s.target()));
  const again = a.ack();
  t('🔴 ⑤ …and the screen re-marks anyway: the fetched arrival is acknowledged while the screen is up',
    again === 6 && a.marked.length === 2, show(a.marked));
  t('⑤ a quiet poll after that calls nothing', (s.snapshot(fwdServer(7).newest()), a.ack() === null), show(a.marked));
  s.snapshot(fwdServer(9).newest());         // two more land together
  t('⑤ the next fetched arrival re-marks once more', a.ack() === 6 && a.marked.length === 3, show(a.marked));
  t('⑤ every mark named a message a fetch returned, at or under the coverage ceiling',
    a.marked.every((id) => s.fetched.has(id)
      && compareMessageOrder(s.msgs.find((m) => m.id === id), coverageCeiling(s.cov)) <= 0));

  // CONTROL — an ordinary thread moves its target on every arrival, so the count arm is not what
  // acknowledges there; it adds no call to a quiet thread either.
  const n = screen();
  n.open(server(5).newest());
  const na = acker(n);
  na.ack();
  n.snapshot(server(6).newest());
  const moved = na.ack();
  n.snapshot(server(6).newest());
  t('⑤ control — an ordinary thread: the arrival moves the target, a quiet poll calls nothing',
    moved === 6 && na.ack() === null && show(na.marked) === show([5, 6]), show(na.marked));
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑥ SOURCE — chat.tsx hands the count to the judgment and remembers it at the mark
// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑤ proves the helpers compose; it cannot prove the route calls them that way (no test can import
// a route module). These read the acknowledgement effect's SOURCE, comments stripped (this slice's
// own comments name every identifier matched below). Neither half is evidence for the other.
{
  const fs = require('fs');
  const path = require('path');
  /** Strip JS comments, keeping string and template contents (chat-window.test.cjs's stripper). */
  const strip = (src) => {
    let out = '', i = 0, inLine = false, inBlock = false, quote = null, tmpl = 0;
    while (i < src.length) {
      const c = src[i], d = src[i + 1];
      if (inLine) { if (c === '\n') { inLine = false; out += c; } i++; continue; }
      if (inBlock) { if (c === '*' && d === '/') { inBlock = false; i += 2; } else { if (c === '\n') out += c; i++; } continue; }
      if (quote) { if (c === '\\') { out += c + (d ?? ''); i += 2; continue; } if (c === quote) quote = null; out += c; i++; continue; }
      if (tmpl > 0) { if (c === '\\') { out += c + (d ?? ''); i += 2; continue; } if (c === '`') tmpl--; out += c; i++; continue; }
      if (c === '/' && d === '/') { inLine = true; i += 2; continue; }
      if (c === '/' && d === '*') { inBlock = true; i += 2; continue; }
      if (c === '`') { tmpl++; out += c; i++; continue; }
      if (c === '"' || c === "'") { quote = c; out += c; i++; continue; }
      out += c; i++;
    }
    return out;
  };
  const FIX = "// admittedPeerCount: admitted,\nconst x = 'admittedPeerCount: admitted,';\n/* admittedPeerCount: admitted, */";
  t('⑥ control — the stripper drops commented code and keeps strings (a comment must not satisfy a pin)',
    strip(FIX).split('admittedPeerCount: admitted,').length - 1 === 1 && FIX.split('admittedPeerCount: admitted,').length - 1 === 3);
  const CHAT = strip(fs.readFileSync(path.join(__dirname, '..', 'app', 'chat.tsx'), 'utf8'));
  const callAt = CHAT.indexOf('if (!shouldMarkRead({');
  const effEnd = CHAT.indexOf('}, [ctx, state, msgs, gapDoor, ackTick, recordRead]);');
  const eff = callAt > 0 && effEnd > callAt ? CHAT.slice(CHAT.lastIndexOf('useEffect(() => {', callAt), effEnd) : '';
  const call = eff.slice(eff.indexOf('if (!shouldMarkRead({'), eff.indexOf('})) return;'));
  t('⑥ control — the acknowledgement effect and its one judgment call were found',
    eff.length > 0 && call.length > 0 && CHAT.split('shouldMarkRead({').length - 1 === 1, `${callAt}..${effEnd}`);
  t('🔴 ⑥ the count is computed under the TARGET\'s own options — the ceiling and the fetched set',
    /admittedPeerCount\(msgs, \{ ceiling, fetchedIds: fetchedIds\.current \}\)/.test(eff)
    && /newestPeerMessageId\(msgs, \{ ceiling, fetchedIds: fetchedIds\.current \}\)/.test(eff));
  t('🔴 ⑥ the judgment receives both counts',
    call.includes('admittedPeerCount: admitted,') && call.includes('lastMarkedAdmittedPeerCount: lastMarkedAdmitted.current,'),
    JSON.stringify(call));
  const tail = eff.slice(eff.indexOf('})) return;'));
  t('🔴 ⑥ the count is remembered at the mark, beside the target, before the record',
    tail.indexOf('lastMarkedAdmitted.current = admitted;') > tail.indexOf('if (target === null) return;')
    && tail.indexOf('if (target === null) return;') > 0
    && tail.indexOf('lastMarkedAdmitted.current = admitted;') < tail.indexOf('recordRead(ctx.threadId, target);'));
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
