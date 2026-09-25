export interface IdentifiedMessage { id: number }

/**
 * Merge a server snapshot into the messages already held by the screen.
 *
 * The current item wins an ID collision because it may have arrived from Realtime
 * after the snapshot request began. Later duplicates within either input win, and
 * the result is always ordered by the server-assigned numeric ID.
 */
export function mergeMessageSnapshot<T extends IdentifiedMessage>(current: T[], snapshot: T[]): T[] {
  const byId = new Map<number, T>();
  for (const message of snapshot) byId.set(message.id, message);
  for (const message of current) byId.set(message.id, message);

  const merged = [...byId.values()].sort((a, b) => a.id - b.id);
  return merged.length === current.length && merged.every((message, index) => message === current[index])
    ? current
    : merged;
}

// ── the reconnect HOLE ────────────────────────────────────────────────────────────────────────
//
// 🔴 THE DEFECT THIS CLOSES (codex client review, 2026-09-25 · c3). `mergeMessageSnapshot` is a
//    union keyed by id, and `fetchMessages` returns the NEWEST `CHAT_PAGE_SIZE` messages. Both are
//    correct on their own and wrong together: if more than one page arrived while the screen was
//    away, the snapshot does not reach back to anything held, so the merged list is
//    [old history] + [newest page] with an INVISIBLE hole between them. Nothing said so — the
//    bubbles sat against each other as if the conversation had run continuously — and no door
//    filled it, because 「이전 메시지 더 보기」 pages backward from the OLDEST held message, which
//    is below the hole. A screen silently dropping the middle of a conversation is the same class
//    as the capped read this window replaced.
//
// ⚠ WHY THE DETECTOR IS NOT ID ARITHMETIC, and this is the one thing a later session must not
//   "simplify". `chat_messages.id` is `generated always as identity` on the TABLE, shared with
//   every other thread, so ids inside one thread are NOT consecutive: 「the snapshot's lowest id
//   minus the highest held id」 is neither a count of missing messages nor a test of contiguity,
//   and a subtraction-based gap flags a hole on every ordinary poll where the window has slid by
//   one message. The exact question — the only one the client can answer without a second server
//   read — is MEMBERSHIP: is the snapshot's OLDEST message one the screen already holds? If it
//   is, the snapshot is anchored to our history and everything between its ends is inside it. If
//   it is not, and the screen holds something older, the region between those two messages is
//   covered by neither input and the screen must say so.

/** Where the hole is: between two REAL messages, both of which the screen can point at. */
export interface MessageGap {
  /** The newest held message OLDER than the snapshot — the hole opens below this bubble. */
  afterId: number;
  /** The snapshot's oldest message — the hole closes above this bubble. */
  beforeId: number;
}

/**
 * The hole a snapshot leaves between itself and the history already on screen, or `null`.
 *
 * `null` for an empty snapshot, for an empty screen (nothing is stranded below), and for every
 * snapshot that OVERLAPS the held history — which is the ordinary case, poll after poll, because
 * a window that has not moved past the screen's newest message contains it.
 */
export function snapshotGap<T extends IdentifiedMessage>(
  held: readonly T[],
  snapshot: readonly T[],
): MessageGap | null {
  if (held.length === 0 || snapshot.length === 0) return null;

  let beforeId = snapshot[0].id;
  for (const m of snapshot) if (m.id < beforeId) beforeId = m.id;

  let afterId: number | null = null;
  for (const m of held) {
    // The snapshot starts inside our own history: the two ranges touch, nothing can be missing.
    if (m.id === beforeId) return null;
    if (m.id < beforeId && (afterId === null || m.id > afterId)) afterId = m.id;
  }
  // Every held message is newer than the snapshot's oldest — nothing of ours is stranded below it.
  return afterId === null ? null : { afterId, beforeId };
}

/**
 * Did this older page reach back into what the screen already holds?
 *
 * `fetchOlderMessages` asks for every row strictly older than its cursor, newest first, capped at
 * one window — so a page containing any id at or below `afterId` has spanned the whole region
 * between that message and the cursor, and the hole is filled rather than merely smaller.
 *
 * ⚠ An EMPTY page also closes it, and that is a statement about the server rather than a
 *   convenience: nothing came back for 「older than this」, so there is nothing in the hole to
 *   fetch. Treating it as still-open would leave a door whose tap can only ever return nothing,
 *   which is the dead-control class this app forbids.
 */
export function gapClosedBy<T extends IdentifiedMessage>(afterId: number, page: readonly T[]): boolean {
  if (page.length === 0) return true;
  for (const m of page) if (m.id <= afterId) return true;
  return false;
}

/**
 * The mid-thread door's word.
 *
 * It lives here rather than beside 「이전 메시지 더 보기」 in `chat-window.ts` because the hole is
 * this module's fact — `snapshotGap` is the only thing that can find one. The BUSY word is
 * deliberately not redefined: both doors import `OLDER_DOOR_BUSY_LABEL`, so the screen cannot
 * grow two vocabularies for one state.
 */
export const GAP_DOOR_LABEL = '빠진 메시지 불러오기';

// ── the (created_at, id) ORDER — one comparator for every cursor ──────────────────────────────
//
// 🔴 THE DEFECT THIS CLOSES (codex client review, 2026-09-25 · #2). Both message reads paged on
//    `created_at` ALONE with a strict predicate, and `olderCursor` picked the smallest ID while the
//    query ordered by timestamp. Two consequences (the first MEASURED by the reviewer): 101 messages
//    sharing one timestamp → the newest 100 load and the older page returns ZERO, so one message
//    is unreachable forever; and a message whose id is larger but whose `created_at` is older
//    (concurrent transactions need not commit in start order) was cursored past. Both reads now
//    order by `(created_at, id)` and every paging cursor — the initial window, the older page and
//    the gap fill — is that pair, compared the way the server compares it. The READ position
//    (0223) stays a timestamp, but it is compared with the same microsecond-exact `compareInstant`.
//
// ⚠ WHY NOT `Date.parse`: it is MILLISECOND-precise and `created_at` is MICROSECOND-precise, so
//   two messages 400µs apart compare EQUAL and the id then decides — which is the server's tie
//   rule only when the timestamps are actually equal. A cursor built on that would ask the server
//   for 「older than (T, id)」 with a T the server considers later than a held message, re-fetching
//   it every page, or on a boundary, never moving. `parseInstant` keeps every digit the server
//   sent, so the client's order IS the server's order.

/** An instant as the server orders it: epoch milliseconds plus the sub-millisecond digits. */
export type Instant = readonly [ms: number, subMsNanos: number];

const FRACTION = /\.(\d+)(?=Z|[+-]\d\d(?::?\d\d)?$|$)/;

/**
 * Parse a server timestamp EXACTLY, or `null` when it is not one.
 *
 * The fractional second is split: the first three digits ride into `Date.parse` (which every
 * engine accepts), the rest are kept as nanoseconds below the millisecond. A string with no
 * fraction is `[ms, 0]`. Anything `Date.parse` rejects is `null` — a cursor that cannot be placed
 * in time cannot be sent to the server as one.
 */
export function parseInstant(iso: string): Instant | null {
  if (typeof iso !== 'string' || iso === '') return null;
  const m = FRACTION.exec(iso);
  let sub = 0;
  let base = iso;
  if (m) {
    const padded = (m[1] + '000000000').slice(0, 9);
    sub = Number(padded.slice(3));
    base = iso.slice(0, m.index) + '.' + padded.slice(0, 3) + iso.slice(m.index + m[0].length);
  }
  const ms = Date.parse(base);
  if (Number.isNaN(ms)) return null;
  return [ms, sub];
}

/** `-1 | 0 | 1` in the server's order, or `null` when either side cannot be placed in time. */
export function compareInstant(a: string, b: string): -1 | 0 | 1 | null {
  const pa = parseInstant(a);
  const pb = parseInstant(b);
  if (pa === null || pb === null) return null;
  if (pa[0] !== pb[0]) return pa[0] < pb[0] ? -1 : 1;
  if (pa[1] !== pb[1]) return pa[1] < pb[1] ? -1 : 1;
  return 0;
}

/** The pair every cursor is made of — the server's own `created_at`, verbatim, and the row id. */
export interface MessageCursor {
  createdAt: string;
  id: number;
}

/**
 * The server's ORDER on two messages: `created_at` first, `id` as the tie-breaker — exactly the
 * `order by created_at, id` the reads use. `null` when either timestamp cannot be placed, so a
 * caller never silently falls back to id-only order for a message it cannot date.
 */
export function compareMessageOrder(a: MessageCursor, b: MessageCursor): -1 | 0 | 1 | null {
  const c = compareInstant(a.createdAt, b.createdAt);
  if (c === null) return null;
  if (c !== 0) return c;
  if (a.id === b.id) return 0;
  return a.id < b.id ? -1 : 1;
}

/**
 * The PostgREST `or=` body for 「strictly older than this (created_at, id)」 — the row-order
 * strict-less-than spelled out: `created_at < T OR (created_at = T AND id < I)`.
 *
 * Lives here, beside the comparator, so `app/test/chat-window.test.cjs` can pin the exact string
 * the server receives; `api.ts` (which cannot be bundled by the tests) only forwards it to `.or()`.
 *
 * ⚠ The timestamp is DOUBLE-QUOTED: inside a PostgREST logical filter `.`, `:` and `,` are
 *   reserved, and a timestamp contains the first two. The id is a bare integer.
 */
export function olderThanCursorFilter(before: MessageCursor): string {
  const at = `"${before.createdAt}"`;
  return `created_at.lt.${at},and(created_at.eq.${at},id.lt.${before.id})`;
}

// ── FETCHED COVERAGE — what a successful read VOUCHED FOR, kept apart from what realtime delivered ──
//
// 🔴 THE DEFECT THIS CLOSES (codex client review wave 4, 2026-09-25 · c1 — MEASURED by the reviewer
//    on the compiled helpers). `snapshotGap` above anchors a snapshot on ANY held message. A held
//    message that arrived by REALTIME alone is not an anchor: the channel drops events across a
//    reconnect, and the ones it dropped sit BELOW the one it delivered. The reviewer's sequence —
//    the screen holds fetched message 1 and realtime-only 102, then a poll returns 102–201 — makes
//    `snapshotGap` answer `null` (102 is held), so there was no hole, no door and no ceiling, and
//    the read was acknowledged up to 201 across 2–101, which no fetch had returned and no screen
//    had drawn. `chat.tsx` no longer asks `snapshotGap`; the pins keep it as the CONTROL that
//    reproduces the reviewer's measurement on the same fixture.
//
// The fix is a second fact, tracked apart from what the screen holds: the stretches of the thread
// a successful FETCH returned IN FULL. A newest-window snapshot vouches for everything between its
// oldest and newest message (one server order, one LIMIT); an older page vouches for everything
// between its oldest message and the cursor it was asked for. Realtime vouches for nothing. Then:
//   · a hole is the space between the LOWEST vouched stretch and the next one (`coverageHole`);
//   · a read may be recorded only inside the lowest stretch (`coverageCeiling`) — everything below
//     that stretch's top was returned by a fetch, so the position cannot cover an undrawn message.
// A hole is no longer 「observable at one merge or never」: it is a standing property of the
// coverage, so a second hole found while a fill is running is not dropped, and the door is always
// the lowest open hole.
//
// ⚠ Order is the SERVER's `(created_at, id)` — `compareMessageOrder`, the comparator every cursor
//   already uses — never id arithmetic (ids are table-wide, see the gap section above). A page
//   holding a message that cannot be placed in time vouches for NOTHING (`null` span): coverage
//   never grows on a guess, and the cost of refusing is only that the acknowledgement waits.
//
// ⚠ Two stretches merge only when they OVERLAP (one's lowest message at or below the other's
//   highest). Stretches that merely touch — nothing between them — stay apart until a fetch
//   crosses the boundary, because only the server can say nothing lies between two messages. The
//   cost is at most one extra older-page read per hole; the alternative is a guess.

/** One stretch of the thread, in the server's order, that successful fetches returned IN FULL.
 *  `lo === null` = the stretch reaches the thread's FIRST message (the server said nothing is older). */
export interface CoverageSpan {
  lo: MessageCursor | null;
  hi: MessageCursor;
}

/** Disjoint vouched stretches, lowest first. */
export type Coverage = readonly CoverageSpan[];

interface PlacedMessage { id: number; createdAt: string }

/** Oldest and newest of a page in the server's order — `null` if ANY message cannot be placed. */
function pageBounds(page: readonly PlacedMessage[]): { oldest: MessageCursor; newest: MessageCursor } | null {
  let oldest: MessageCursor | null = null;
  let newest: MessageCursor | null = null;
  for (const m of page) {
    if (parseInstant(m.createdAt) === null) return null;
    const c: MessageCursor = { createdAt: m.createdAt, id: m.id };
    if (oldest === null || compareMessageOrder(c, oldest) === -1) oldest = c;
    if (newest === null || compareMessageOrder(c, newest) === 1) newest = c;
  }
  return oldest === null || newest === null ? null : { oldest, newest };
}

/**
 * What a NEWEST-WINDOW read (`fetchMessages`) vouches for: its oldest message through its newest.
 * `reachesStart` = the page was shorter than the window (`pageIsLast`), so it IS the whole thread
 * and the stretch reaches the first message. `null` for an empty page (nothing to vouch for) or a
 * page with a message that cannot be placed in time.
 */
export function windowSpan(page: readonly PlacedMessage[], reachesStart: boolean): CoverageSpan | null {
  const b = pageBounds(page);
  if (b === null) return null;
  return { lo: reachesStart ? null : b.oldest, hi: b.newest };
}

/**
 * What an OLDER-PAGE read (`fetchOlderMessages(cursor)`) vouches for: every message strictly older
 * than `cursor`, down to the page's oldest — plus the cursor message itself, which the caller took
 * from a message it holds. `reachesStart` (a short page) or an EMPTY page means the server has
 * nothing older, so the stretch reaches the first message.
 *
 * `null` — vouch for nothing — when the cursor cannot be placed, when a message cannot be placed,
 * or when the page holds a message that is NOT strictly older than the cursor: that page does not
 * answer the question that was asked, and coverage built on it would be a guess.
 */
export function olderPageSpan(
  page: readonly PlacedMessage[],
  cursor: MessageCursor,
  reachesStart: boolean,
): CoverageSpan | null {
  if (parseInstant(cursor.createdAt) === null) return null;
  const hi: MessageCursor = { createdAt: cursor.createdAt, id: cursor.id };
  if (page.length === 0) return { lo: null, hi };
  const b = pageBounds(page);
  if (b === null) return null;
  if (compareMessageOrder(b.newest, cursor) !== -1) return null;
  return { lo: reachesStart ? null : b.oldest, hi };
}

/** `a` at or below `b` in the server's order, with `null` as the thread's start. */
function loAtOrBelow(a: MessageCursor | null, b: MessageCursor): boolean {
  if (a === null) return true;
  const c = compareMessageOrder(a, b);
  return c !== null && c <= 0;
}

/** The union of `cov` and `span`, as disjoint stretches lowest first. `null` adds nothing. */
export function addCoverage(cov: Coverage, span: CoverageSpan | null): Coverage {
  if (span === null) return cov;
  const all = [...cov, span].sort((x, y) => {
    if (x.lo === null || y.lo === null) return x.lo === y.lo ? 0 : x.lo === null ? -1 : 1;
    return compareMessageOrder(x.lo, y.lo) ?? 0;
  });
  const out: CoverageSpan[] = [];
  for (const s of all) {
    const top = out[out.length - 1];
    // Overlap: this stretch starts at or below the current top stretch's highest message.
    if (top !== undefined && loAtOrBelow(s.lo, top.hi)) {
      const higher = compareMessageOrder(s.hi, top.hi) === 1 ? s.hi : top.hi;
      out[out.length - 1] = { lo: top.lo, hi: higher };
    } else {
      out.push({ lo: s.lo, hi: s.hi });
    }
  }
  return out;
}

/**
 * The highest message a read may be recorded UP TO: the top of the LOWEST vouched stretch.
 * Everything at or below it (down to the stretch's start) was returned by a fetch; above it lies
 * either nothing or a hole. `null` = nothing has been vouched for, and then nothing may be recorded.
 */
export function coverageCeiling(cov: Coverage): MessageCursor | null {
  return cov.length === 0 ? null : cov[0].hi;
}

/**
 * The LOWEST open hole, or `null`. `afterId` is the message the door is drawn under (the top of the
 * lowest stretch); `cursor` is where the fill reads backward from (the bottom of the next one).
 */
export function coverageHole(cov: Coverage): { afterId: number; cursor: MessageCursor } | null {
  if (cov.length < 2) return null;
  const upper = cov[1].lo;
  // Unreachable after `addCoverage` (a stretch reaching the start merges with everything below it),
  // but a door with no cursor would be a control that cannot fetch — refuse it rather than draw it.
  if (upper === null) return null;
  return { afterId: cov[0].hi.id, cursor: upper };
}

/**
 * Should THIS snapshot start the automatic fill? Its budget is per HOLE, not per poll.
 *
 * [codex wave 4 review · low] Asking 「is a hole open?」 on every snapshot turned the bounded fill
 * into an unbounded one spread over poll ticks: a thread that moved on by 5 000 messages was
 * backfilled with no tap — 50 pages across 17 ticks, measured on these helpers — and the door
 * flipped to its busy word on every tick. The design is 「fill a little on our own, then hand the
 * rest to a door the reader taps」, so the screen fills automatically once for each LOWEST hole it
 * meets (identified by `afterId`, the message the door is drawn under — it does not move while a
 * fill reads down from above) and leaves a standing hole to the door. A new lowest hole — the old
 * one closed, or none was open — earns one more automatic fill.
 *
 * `remember` is what the caller keeps for the next snapshot: the hole's `afterId`, or `null` once
 * no hole is open (so a later hole at any position is new).
 */
export function autoFillDecision(
  hole: { afterId: number } | null,
  lastAutoFilledAfterId: number | null,
): { fill: boolean; remember: number | null } {
  if (hole === null) return { fill: false, remember: null };
  return { fill: hole.afterId !== lastAutoFilledAfterId, remember: hole.afterId };
}
