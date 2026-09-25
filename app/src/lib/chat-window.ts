// Chat — the message WINDOW and the bubble SHAPE, as pure functions.
//
// TWO DEFECTS THIS CLOSES, both measured on trunk 6d02769 (2026-09-23).
//
// ① THE SCREEN KEPT THE OLDEST 100 MESSAGES. `fetchMessages` read
//    `.order('created_at').limit(100)` — ascending — so past a hundred messages `app/chat.tsx`
//    showed the FIRST hundred and silently dropped everything since. The 「5분 늦어요」 an owner is
//    waiting for is by definition the NEWEST message, and it was the one guaranteed to be missing.
//    Worse than a cap: the screen gave no sign it was capped, so a thread frozen at its hundredth
//    message looked like a thread where nobody had spoken since. A capped read must never pose as
//    a total — so the window is now the NEWEST page plus a real door to the ones before it.
//
// ② `chat_messages.kind` WAS NEVER SELECTED. The column exists in 0001 (`text | photo | location`)
//    and the select listed `id, sender_id, body, media_path, created_at`. `mapMsg` inferred photo
//    from `media_path` alone, so any row that was neither plain text nor a photo rendered as an
//    EMPTY BUBBLE — a message you can see was sent and cannot read. `chatBubble` below gives every
//    kind a shape, and an unknown one says it cannot be shown rather than showing nothing.
//
// WHY THESE LIVE HERE AND NOT IN chat.tsx: `app/test/*.cjs` cannot import a route module, so logic
// left inside the screen is untestable by construction. This file is imported by chat.tsx and
// executed by app/test/chat-window.test.cjs.

import { compareMessageOrder, MessageCursor, parseInstant } from './chat-messages';

/** The window the screen holds, and the size of one older page. */
export const CHAT_PAGE_SIZE = 100;

export interface WindowedMessage {
  id: number;
  /** The server's `created_at`, verbatim. The paging cursor — never a device clock. */
  createdAt: string;
}

/**
 * The cursor for the next older page: the OLDEST message held, as the pair the server pages by.
 *
 * 🔴 [2026-09-25 · codex #2] This returned the `created_at` of the smallest ID, and the older read
 *    used a strict `created_at <` on it. Two holes — the first MEASURED by the reviewer, the second
 *    READ: 101 messages sharing one timestamp made the 101st unreachable forever (the newest 100
 *    load, 「older than T」 returns nothing); and 「smallest id」 is not 「oldest」 — concurrent inserts
 *    need not commit in start order, so a message with a larger id and an older `created_at` was
 *    cursored past. The cursor is now the
 *    `(created_at, id)` pair, the oldest by the SERVER's order (`compareMessageOrder`), and the
 *    read asks for rows strictly below that pair — which can always make progress, because no two
 *    rows share a pair.
 *
 * ⚠ A message whose timestamp cannot be parsed is skipped when choosing: a cursor the server
 *   cannot place in time cannot be sent to it. `mapMsg` only produces one for a row with no
 *   `created_at` string, which a real row never is.
 */
export function olderCursor<T extends WindowedMessage>(held: T[]): MessageCursor | null {
  let oldest: T | null = null;
  for (const m of held) {
    if (oldest === null) {
      if (parseInstant(m.createdAt) !== null) oldest = m;
      continue;
    }
    const c = compareMessageOrder(m, oldest);
    if (c !== null && c < 0) oldest = m;
  }
  return oldest === null ? null : { createdAt: oldest.createdAt, id: oldest.id };
}

/**
 * Put a newest-first server page into display order (oldest → newest).
 *
 * The read is `order('created_at', { ascending: false }).limit(n)` — the NEWEST n — and the screen
 * renders oldest-first, so the page is reversed on arrival. `mergeMessageSnapshot` re-sorts by id
 * anyway; this keeps the array the screen is handed in the order it draws, so a snapshot inspected
 * anywhere in between reads the same way.
 */
export function toDisplayOrder<T>(newestFirstPage: T[]): T[] {
  return newestFirstPage.slice().reverse();
}

/**
 * Was that the last page?
 *
 * A server page shorter than the window means there was nothing else to give. A FULL page always
 * means there may be more — the door stays open and the next tap finds out. Guessing "probably
 * done" on a full page would close a door over messages that exist.
 */
export function pageIsLast(pageLength: number, pageSize: number = CHAT_PAGE_SIZE): boolean {
  return pageLength < pageSize;
}

export type OlderDoorState = 'none' | 'ready' | 'busy';

/**
 * What the 「이전 메시지 더 보기」 door does right now.
 *
 * `busy` is a LABEL SWAP, not a disabled button (chat.tsx's send button settled this grammar on
 * 2026-09-22: busy keeps its fill and reports `accessibilityState.busy`; unavailable is the
 * disabled state). And there is no third 「no more messages」 state: once the history is exhausted
 * the door is GONE. A permanently dead control that still looks like a control is the dead-button
 * class this app forbids.
 */
export function olderDoorState(s: { hasMessages: boolean; exhausted: boolean; busy: boolean }): OlderDoorState {
  if (s.busy) return 'busy';
  if (!s.hasMessages || s.exhausted) return 'none';
  return 'ready';
}

export const OLDER_DOOR_LABEL = '이전 메시지 더 보기';
export const OLDER_DOOR_BUSY_LABEL = '불러오는 중…';

export function olderDoorLabel(state: OlderDoorState): string {
  return state === 'busy' ? OLDER_DOOR_BUSY_LABEL : OLDER_DOOR_LABEL;
}

// ── ② the bubble shape ────────────────────────────────────────────────────────────────────────

export type ChatBubble =
  | { shape: 'photo'; mediaUrl: string }
  | { shape: 'text'; text: string }
  /** A kind this screen cannot draw. `label` says what it is; `text` is whatever body came with
   *  it, which may be ''. Never an empty bubble. */
  | { shape: 'labelled'; label: string; text: string };

/** 0001's `kind` comment names exactly these three. Anything else is a kind this build predates. */
export const CHAT_KIND_LOCATION_LABEL = '위치 메시지';
export const CHAT_KIND_UNSUPPORTED_LABEL = '표시할 수 없는 메시지';
export const CHAT_EMPTY_LABEL = '내용 없는 메시지';

/**
 * Decide what a message renders as.
 *
 * ⚠ `location` gets a LABEL and no coordinates on purpose. `chat_messages` has body / media_path /
 * kind / client_key and NOTHING else — there is no payload column to bind, and the only writer of
 * `kind` in the whole repo is `sendChatPhoto`, which writes 'photo' (grepped 2026-09-23: no
 * migration, edge function or client writes 'location'). Drawing a map pin from a column that does
 * not exist would be the fabricated-field class; naming the message honestly is what is available.
 * The day something writes a location, the payload it adds is what this branch binds.
 *
 * Media wins over `kind` deliberately: `media_path` is a real, resolvable field and photo
 * rendering already keys on it, so a row carrying media draws its media whatever its label says.
 */
export function chatBubble(m: { kind: string; body: string; mediaUrl: string | null }): ChatBubble {
  if (m.mediaUrl !== null && m.mediaUrl !== '') return { shape: 'photo', mediaUrl: m.mediaUrl };

  const kind = m.kind === '' ? 'text' : m.kind;
  if (kind === 'text') {
    // A text row with no body renders nothing at all today — a bubble you can see and cannot read.
    return m.body === '' ? { shape: 'labelled', label: CHAT_EMPTY_LABEL, text: '' } : { shape: 'text', text: m.body };
  }
  if (kind === 'location') return { shape: 'labelled', label: CHAT_KIND_LOCATION_LABEL, text: m.body };
  // Includes 'photo' without media: the row claims a photo and carries no path to one, so it says
  // it cannot be shown rather than drawing a blank square.
  return { shape: 'labelled', label: CHAT_KIND_UNSUPPORTED_LABEL, text: m.body };
}
