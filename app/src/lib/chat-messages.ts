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
