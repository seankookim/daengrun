// Chat READ STATE — the unread badge's rules and the 「읽음」 receipt's placement, as pure
// functions. Server side is 0212 (`chat_reads` + `chat_mark_read` / `my_chat_unread` /
// `chat_thread_read_state`).
//
// WHY THESE LIVE HERE AND NOT IN THE SCREENS: `app/test/*.cjs` cannot import a route module, so a
// rule left inside `chat.tsx` or `runner/home.tsx` is untestable by construction — the same reason
// `chat-window.ts` exists. This file is imported by `app/app/chat.tsx`, `app/app/runner/home.tsx`,
// `app/app/owner/schedule.tsx` and `app/src/components/home-hero.tsx`, and it is executed by
// `app/test/chat-read.test.cjs`.
// It imports ONE module — `chat-messages.ts`, for the server's `(created_at, id)` order and its
// microsecond-exact instant comparison — because 「which message is newest」 and 「is this message
// at or before that position」 must be answered in the order the SERVER compares in, not in a
// coarser one the device happens to have (`Date.parse` is millisecond-precise; `created_at` is
// microsecond-precise).
//
// ═══ THE ONE LAW THIS FILE ENFORCES ═══
// A badge is a CLAIM about how many messages are waiting. There are four states and only one of
// them licenses a number:
//   · loading  → nothing is drawn. Loading is not 0 (CLAUDE.md).
//   · error    → nothing is drawn, and the caller logs. A failed read is not 「no messages」.
//   · ready, but this booking is not in the answer → nothing. That read said nothing about it.
//   · ready and present → the server's count, which is a count of ROWS and never an estimate.
// Three of those four render identically — as silence — and that is deliberate: the absence of a
// badge is the app's way of saying 「nothing to act on」, which is true when the count is 0 and
// honest when the count is unknown. What must never happen is a drawn ZERO, which would be the
// screen asserting a number it does not have.

import { compareInstant, compareMessageOrder } from './chat-messages';

/** One row of `my_chat_unread()`. */
export interface ChatUnreadRow {
  threadId: string;
  bookingId: string;
  /** A count of rows, from the server. Never computed on the device. */
  unreadCount: number;
  /** The thread's newest message, any sender. `null` = nothing has ever been said here. */
  lastMessageAt: string | null;
}

export type ChatUnreadState =
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; rows: ChatUnreadRow[] };

/**
 * The MEASURED count for one booking, or `null` when this read says nothing about it.
 *
 * `null` covers three different unknowns on purpose — not loaded, failed, and 「the server did not
 * list this booking」 — because a caller may only do one thing with all three, which is to draw
 * nothing. The distinction that matters to the product is preserved at the other end: a live
 * thread with nothing unread IS listed by `my_chat_unread`, with 0, so a booking that comes back
 * `0` here is a measured zero and one that comes back `null` is genuinely unknown.
 */
export function unreadFor(state: ChatUnreadState, bookingId: string | null | undefined): number | null {
  if (state.status !== 'ready') return null;
  if (!bookingId) return null;
  const row = state.rows.find((r) => r.bookingId === bookingId);
  if (!row) return null;
  return Number.isFinite(row.unreadCount) && row.unreadCount >= 0 ? row.unreadCount : null;
}

/** Above this the badge says 「99+」 rather than a four-digit number the chip cannot hold. */
export const UNREAD_BADGE_CAP = 99;

/**
 * The badge TEXT for one booking, or `null` for 「draw nothing」.
 *
 * 🔴 A zero returns `null`. The badge exists to say 「there is something waiting」; drawing 「0」
 * would be a chip that says there is nothing, which is what an ABSENT chip already says, more
 * quietly and without competing with the thing the screen is actually about.
 *
 * `99+` is not a rounded number — it is a true statement about a count we have, kept short enough
 * to fit the chip. The exact figure is one tap away, on the thread itself.
 */
export function unreadBadge(state: ChatUnreadState, bookingId: string | null | undefined): string | null {
  return formatUnreadBadge(unreadFor(state, bookingId));
}

/** A count → the chip's text, or `null` for 「draw nothing」. One formatter, so the per-booking
 *  badge and the all-threads badge can never disagree about the cap or about zero. */
export function formatUnreadBadge(n: number | null): string | null {
  if (n === null || !Number.isFinite(n) || n <= 0) return null;
  return n > UNREAD_BADGE_CAP ? `${UNREAD_BADGE_CAP}+` : String(n);
}

/** The screen-reader sentence for a badge. `null` when there is no badge to describe. */
export function unreadBadgeLabel(state: ChatUnreadState, bookingId: string | null | undefined): string | null {
  const tx = unreadBadge(state, bookingId);
  return tx === null ? null : `읽지 않은 메시지 ${tx}`;
}

/**
 * Every live thread's unread, summed — for an entry point that opens 「the chat」 rather than one
 * booking's chat (`home-hero`'s button when there is no next booking, `runner/run.tsx`'s bare
 * `/chat`). `null` while unknown, for the same reason as above.
 */
export function totalUnread(state: ChatUnreadState): number | null {
  if (state.status !== 'ready') return null;
  let n = 0;
  for (const r of state.rows) if (Number.isFinite(r.unreadCount) && r.unreadCount > 0) n += r.unreadCount;
  return n;
}

/** The badge TEXT for 「all my live threads」 — the entry point that opens the chat with no booking
 *  in hand. Same formatter and therefore the same zero and cap rules as the per-booking badge. */
export function totalUnreadBadge(state: ChatUnreadState): string | null {
  return formatUnreadBadge(totalUnread(state));
}

// ── the 「읽음」 receipt ────────────────────────────────────────────────────────────────────────

export const READ_RECEIPT_LABEL = '읽음';

export interface ReceiptMessage {
  id: number;
  /** Did the CALLER send it. Only the caller's own messages can carry a receipt. */
  mine: boolean;
  /** The server's `created_at`, verbatim — never a device clock. */
  createdAt: string;
}

/**
 * Which message carries 「읽음」, given the counterpart's read position.
 *
 * The rule: the NEWEST message the caller sent whose server timestamp is at or before the
 * counterpart's `last_read_at`. One label per screen, under the last thing they have seen — the
 * grammar every messenger uses, and the only one that answers the question a sender actually has
 * (「did the 5분 늦어요 land?」) rather than decorating every bubble.
 *
 * [0223] Since `chat_mark_read_to`, the counterpart's `last_read_at` is the `created_at` of the
 * message THEY acknowledged — the newest of the caller's messages their screen rendered — copied
 * verbatim to the microsecond. So the comparison below must be microsecond-exact: two of the
 * caller's messages 400µs apart are one instant to `Date.parse`, and a millisecond-coarse compare
 * would put the receipt on the later one, which their screen never showed.
 *
 * 🔴 `null` WHENEVER THE ANSWER IS NOT KNOWN, and that is the honesty rule rather than a
 * convenience: `peerReadAt === null` means the counterpart has never read this thread, and a
 * receipt drawn then would be the app telling a runner their message was seen when the server
 * says nothing of the kind. An unparseable timestamp on either side is the same unknown.
 *
 * ⚠ Both sides are compared as server INSTANTS (`compareInstant`) — timezone-free, never a
 * device-local getter — and ties between our own messages are broken in the server's
 * `(created_at, id)` order, so array order cannot move the label.
 *
 * ⚠ A FORWARD-DATED message of mine (a pre-0225 client's date) is not receipted until its date,
 *   and that is kept on purpose (0235 §0c named it; the decision is recorded here). When the
 *   counterpart acknowledged it, the server clamped their position to ITS now() — after that the
 *   position is one timestamp, still before my row, and the server's own durable model (their
 *   badge, `my_chat_unread`) counts the row UNREAD until its date. The client cannot recover which
 *   message a clamped position acknowledged: clamping my row to the position would receipt it for
 *   ANY position, including one written before I sent it; clamping it to the device's now leaves it
 *   after every past position, and puts a device clock into a server comparison. Silence on that
 *   row is this function's unknown — the same honesty rule as above — never a claim. Knowing it
 *   needs a server fact (the acknowledged message's id, or the forward-dated rows rewritten — the
 *   latter is 0225 §0e's product decision).
 */
export function readReceiptMessageId(
  msgs: readonly ReceiptMessage[],
  peerReadAt: string | null | undefined,
): number | null {
  if (!peerReadAt) return null;
  let best: ReceiptMessage | null = null;
  for (const m of msgs) {
    if (!m.mine) continue;
    // A message we cannot place in time cannot be said to have been read — and an unparseable
    // read position places nothing (`compareInstant` is null for either side).
    const c = compareInstant(m.createdAt, peerReadAt);
    if (c === null || c > 0) continue;
    if (best === null) { best = m; continue; }
    const vs = compareMessageOrder(m, best);
    if (vs !== null && vs > 0) best = m;
  }
  return best === null ? null : best.id;
}

/** The options both acknowledgement facts are computed under — one set, so they cannot disagree. */
export interface PeerAckOptions {
  ceilingId?: number | null;
  ceiling?: { createdAt: string; id: number } | null;
  fetchedIds?: ReadonlySet<number> | null;
}

/** May this message be acknowledged at all? A peer's, at or below the hole, at or below the top of
 *  verified fetched coverage (placeable against it), and returned by a fetch. The ONE admission
 *  rule behind `newestPeerMessageId` and `admittedPeerCount`. */
function admitsPeer(m: ReceiptMessage, opts: PeerAckOptions): boolean {
  if (m.mine) return false;
  const ceilingId = opts.ceilingId ?? null;
  const ceiling = opts.ceiling ?? null;
  const fetchedIds = opts.fetchedIds ?? null;
  if (ceilingId !== null && m.id > ceilingId) return false;
  if (ceiling !== null) {
    const c = compareMessageOrder(m, ceiling);
    if (c === null || c > 0) return false;
  }
  if (fetchedIds !== null && !fetchedIds.has(m.id)) return false;
  return true;
}

/**
 * The one message a read may be recorded UP TO: the newest PEER message on screen that a
 * SUCCESSFUL FETCH returned, below any open reconnect hole — or `null`, and then nothing is
 * recorded, because a read is a claim about a message and there is none to point at.
 *
 * 「Newest」 is the server's order (`created_at`, then `id`) — the order `fetchMessages` pages in.
 * The server records THIS message's `created_at` (`chat_mark_read_to`, 0223), and `my_chat_unread`
 * / the receipt compare against it, so what the screen acknowledges is what the server counts.
 *
 * 🔴 `fetchedIds` — ONLY MESSAGES A FETCH RETURNED (codex client review, 2026-09-25 · #1). A read
 *    position covers everything before it in time, so acknowledging message N claims every
 *    earlier message was seen. A snapshot from `fetchMessages` is the newest window of ONE server
 *    order, so every message below its newest was in it (or below the screen's hole, see next);
 *    a message that arrived by REALTIME alone carries no such guarantee — the channel drops events
 *    across a reconnect, and the ones it dropped sit below the one it delivered, undrawn. So a
 *    realtime-only message waits for the next successful poll to vouch for it (≤15 s while live).
 *    `null` = no restriction; the screen always passes its set.
 *
 * `ceilingId` is a reconnect hole's `afterId`: while a hole is open the screen has NOT shown what
 * sits in it, so the acknowledgement stops at the newest peer message at or below the hole. A
 * position cannot say 「everything except a hole」, so the honest position is the one below it.
 *
 * 🔴 `ceiling` — THE TOP OF VERIFIED FETCHED COVERAGE (codex client review wave 4 · c1). The screen
 *    passes `coverageCeiling(...)` (chat-messages.ts): the highest message of the lowest stretch
 *    that fetches returned IN FULL. `fetchedIds` alone was not enough — a snapshot anchored on a
 *    REALTIME-only held message hid the hole below it, every id in that snapshot became 「fetched」,
 *    and the read jumped the hole. Compared in the server's `(created_at, id)` order; a message
 *    that cannot be placed against the ceiling is excluded, never let through.
 */
export function newestPeerMessageId(
  msgs: readonly ReceiptMessage[],
  opts: PeerAckOptions = {},
): number | null {
  let best: ReceiptMessage | null = null;
  for (const m of msgs) {
    if (!admitsPeer(m, opts)) continue;
    if (best === null) { best = m; continue; }
    const c = compareMessageOrder(m, best);
    if (c !== null && c > 0) best = m;
  }
  return best === null ? null : best.id;
}

/**
 * How many peer messages the acknowledgement may cover — every one `newestPeerMessageId` would
 * consider, under the SAME options. The screen hands it to `shouldMarkRead` beside the target.
 *
 * 🔴 WHY THE TARGET ALONE IS NOT ENOUGH (0235 §0c · R2 finding 2 — the client half, named there
 *    and built here). A pre-0225 client wrote its own `created_at`, so a thread can hold a peer row
 *    dated in the FUTURE. In the server's `(created_at, id)` order that row is the newest message
 *    until its date passes, so the target names it before AND after a real message arrives — and
 *    'message' re-marked only when the target CHANGED. The real message was drawn and never
 *    acknowledged while the screen stayed up: unread on the server, its 0228 nudge unreleased, every
 *    later push deduped silent, until the next open/focus. The same sentence has a second site with
 *    no forward date at all: an id/time inversion (concurrent inserts) lands a fetched message
 *    BELOW the unchanged target. In both, the fact that changed is 「one more peer message may now be
 *    acknowledged」 — this count.
 *
 * ⚠ WHY NOT RE-ORDER THE TARGET BY `min(created_at, now)` (the other fix 0235 §0c named). A row
 *   clamped to now still sorts at or above every real message (whose `created_at` is before now),
 *   so the target would STILL be the forward-dated row and still not change on an arrival — the
 *   clamp moves nothing here. It would also put a device clock into the server's order, which every
 *   cursor and coverage pin in this module refuses (`compareMessageOrder` is server instants only).
 *
 * ⚠ The count admits exactly what the target may — a message a FETCH returned, at or below the
 *   coverage ceiling (client-review-4's invariant). A realtime-only arrival is not counted, so it
 *   triggers nothing until a poll vouches for it. That matters more here than anywhere: the server
 *   records an acknowledged forward-dated row as ITS now() (0223 §0d ③ clamp), so a re-mark covers
 *   everything committed until the call — a mark triggered by a realtime arrival would cover the
 *   dropped burst below it. Triggered by a fetch, the mark runs on the commit that renders it.
 */
export function admittedPeerCount(
  msgs: readonly ReceiptMessage[],
  opts: PeerAckOptions = {},
): number {
  let n = 0;
  for (const m of msgs) if (admitsPeer(m, opts)) n += 1;
  return n;
}

// ── when to record that the caller has read ───────────────────────────────────────────────────

export type MarkReadReason =
  /** The thread has just been resolved and its history has landed. */
  | 'open'
  /** The screen regained navigation focus, or the app came back to the foreground. */
  | 'focus'
  /** A message arrived while the screen was already up. */
  | 'message';

/**
 * Should the screen call `chat_mark_read` right now?
 *
 * ⚠ `appActive` IS THE HALF THAT MATTERS AND IT IS NOT DECORATION. Expo Router keeps previous
 * screens mounted and their pollers running, so a chat screen left behind a lock screen keeps
 * receiving messages. Marking those read would tell the counterpart 「읽음」 about a message nobody
 * has looked at — the app asserting a human action that did not happen. A phone in a pocket reads
 * nothing.
 *
 * 🔴 `focused` IS THE OTHER HALF, AND IT WAS MISSING (codex client review, 2026-09-25 · c1). The
 * two facts are independent and neither implies the other: `appActive` says the APP is in front,
 * `focused` says THIS SCREEN is the one the person is looking at. Expo Router keeps the chat
 * mounted behind a pushed screen — 예약 상세, 설정, anything — with the app perfectly active and
 * the poller still running, so every message arriving while the owner is somewhere else was
 * marked read and the peer's 「읽음」 receipt said a human had seen it. Nobody had. A false receipt
 * is worse than a missing one: the runner who sent 「5분 늦어요」 stops waiting for an answer.
 * `false` refuses for EVERY reason, 'open' and 'focus' included — a screen that is not in front
 * cannot have been read whatever brought us here.
 *
 * 🔴 `newestPeerMessageId === null` REFUSES FOR EVERY REASON (0223 · codex #1). A read is now
 * recorded UP TO a message — the newest peer message a successful fetch put on screen
 * (`newestPeerMessageId` above) — so with none there is nothing to record, and 「I opened the
 * thread」 is not a message. This is what retires 0212's 「read up to now()」 on 'open' and
 * 'focus': a screen that has rendered nothing of the peer's cannot have read anything of theirs.
 *
 * `open` and `focus` mark whenever there IS something to point at, even when it is the same
 * message this screen already marked — the person IS looking at it, the server's write is
 * monotonic so the repeat is a no-op by construction, and a mark whose network call failed is
 * repaired by the next focus rather than being lost forever.
 *
 * `message` is gated on the newest peer message being a DIFFERENT one from the last this screen
 * marked for. Without that gate the screen would call the RPC on every poll tick of a quiet
 * thread. It is 「different」 and not 「greater」 on purpose: the newest message is chosen in the
 * server's `(created_at, id)` order, in which a larger id can be OLDER (concurrent inserts), so a
 * `>` on ids would refuse to acknowledge a genuinely newer message. The newest of a growing set
 * only changes when a newer one is fetched, so 「different」 is exactly 「a newer one arrived」 —
 * EXCEPT when the newest cannot move: a forward-dated peer row pins it (0235 §0c), and a message
 * fetched below it (an id/time inversion) does not move it either. So 'message' ALSO fires when the
 * admitted count (`admittedPeerCount`) GREW since the last mark. Under an unchanged target the
 * re-mark names the same message: for an ordinary target the server's write is a monotonic no-op
 * that re-runs 0228's release for the new arrival; for a forward-dated one the server clamps to its
 * now(), which is what acknowledges the arrival at all. Both counts must be KNOWN — an absent one
 * is not zero, and a count that did not grow states nothing new.
 */
export function shouldMarkRead(s: {
  reason: MarkReadReason;
  /** The thread is resolved and its history is on screen. */
  ready: boolean;
  /** `AppState.currentState === 'active'`. */
  appActive: boolean;
  /** This screen holds navigation focus — `useFocusEffect`'s own ref, never a guess. */
  focused: boolean;
  /** `newestPeerMessageId(...)` above — the message the read would be recorded up to, or `null`. */
  newestPeerMessageId: number | null;
  /** The peer message id this screen last recorded a read up to, or `null`. */
  lastMarkedPeerMessageId: number | null;
  /** `admittedPeerCount(...)` now, under the target's own options. Absent = unknown. */
  admittedPeerCount?: number | null;
  /** The admitted count when this screen last recorded a read. Absent = unknown. */
  lastMarkedAdmittedPeerCount?: number | null;
}): boolean {
  if (!s.ready) return false;
  if (!s.appActive) return false;
  if (!s.focused) return false;
  if (s.newestPeerMessageId === null) return false;
  if (s.reason !== 'message') return true;
  if (s.lastMarkedPeerMessageId === null) return true;
  if (s.newestPeerMessageId !== s.lastMarkedPeerMessageId) return true;
  const n = s.admittedPeerCount ?? null;
  const last = s.lastMarkedAdmittedPeerCount ?? null;
  return n !== null && last !== null && n > last;
}
