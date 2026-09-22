// Chat READ STATE — the unread badge's rules and the 「읽음」 receipt's placement, as pure
// functions. Server side is 0212 (`chat_reads` + `chat_mark_read` / `my_chat_unread` /
// `chat_thread_read_state`).
//
// WHY THESE LIVE HERE AND NOT IN THE SCREENS: `app/test/*.cjs` cannot import a route module, so a
// rule left inside `chat.tsx` or `runner/home.tsx` is untestable by construction — the same reason
// `chat-window.ts` exists. This file is imported by `app/app/chat.tsx`, `app/app/runner/home.tsx`,
// `app/app/owner/schedule.tsx` and `app/src/components/home-hero.tsx`, and it is executed by
// `app/test/chat-read.test.cjs`.
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
 * Which message carries 「읽음」, given the counterpart's `last_read_at`.
 *
 * The rule: the NEWEST message the caller sent whose server timestamp is at or before the
 * counterpart's read position. One label per screen, under the last thing they have seen — the
 * grammar every messenger uses, and the only one that answers the question a sender actually has
 * (「did the 5분 늦어요 land?」) rather than decorating every bubble.
 *
 * 🔴 `null` WHENEVER THE ANSWER IS NOT KNOWN, and that is the honesty rule rather than a
 * convenience: `peerReadAt === null` means the counterpart has never read this thread, and a
 * receipt drawn then would be the app telling a runner their message was seen when the server
 * says nothing of the kind. An unparseable timestamp on either side is the same unknown.
 *
 * ⚠ Both sides are compared as EPOCH MILLISECONDS (`Date.parse`), which is timezone-free —
 * `check-device-clock`'s family of device-local reads is deliberately absent here.
 */
export function readReceiptMessageId(
  msgs: readonly ReceiptMessage[],
  peerReadAt: string | null | undefined,
): number | null {
  if (!peerReadAt) return null;
  const readMs = Date.parse(peerReadAt);
  if (Number.isNaN(readMs)) return null;

  let best: ReceiptMessage | null = null;
  for (const m of msgs) {
    if (!m.mine) continue;
    const t = Date.parse(m.createdAt);
    // A message we cannot place in time cannot be said to have been read.
    if (Number.isNaN(t)) continue;
    if (t > readMs) continue;
    if (best === null || m.id > best.id) best = m;
  }
  return best === null ? null : best.id;
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
 * `open` and `focus` mark unconditionally (while active): the person IS looking at the thread, so
 * recording that is correct even when it moves the position by nothing — and `chat_mark_read` is
 * monotonic, so a redundant call is a no-op by construction rather than by luck.
 *
 * `message` is gated on there being a PEER message newer than the last one this screen marked
 * for. Without that gate the screen would call the RPC on every poll tick of a quiet thread, and
 * with it a conversation costs one call per arriving message.
 */
export function shouldMarkRead(s: {
  reason: MarkReadReason;
  /** The thread is resolved and its history is on screen. */
  ready: boolean;
  /** `AppState.currentState === 'active'`. */
  appActive: boolean;
  /** Highest peer message id on screen, or `null` when the peer has said nothing. */
  newestPeerMessageId: number | null;
  /** Highest peer message id this screen has already marked for, or `null`. */
  lastMarkedPeerMessageId: number | null;
}): boolean {
  if (!s.ready) return false;
  if (!s.appActive) return false;
  if (s.reason !== 'message') return true;
  if (s.newestPeerMessageId === null) return false;
  if (s.lastMarkedPeerMessageId === null) return true;
  return s.newestPeerMessageId > s.lastMarkedPeerMessageId;
}
