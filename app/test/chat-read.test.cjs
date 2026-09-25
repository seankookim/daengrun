// chat-read.ts pins — the unread badge's four states, the 「읽음」 receipt's placement, and when a
// screen may record that its owner has read.
//
// The module is bundled from the REAL source (the run-notification-prefs idiom), not retyped.
//
// WHAT THESE PIN, and why each is worth a case rather than being obvious:
//   · A badge is a CLAIM. Three of the four input states are unknowns and must render as silence;
//     only 「ready AND this booking is in the answer」 licenses a number. The cases that matter are
//     the ones where a naive implementation draws 0: loading, error, and a booking the read did
//     not list.
//   · The receipt is the one place this app could tell a runner their message was seen when the
//     server says nothing of the kind. Every 「unknown」 input returns null.
//   · `shouldMarkRead`'s `appActive` arm: a chat screen left behind a lock screen keeps polling,
//     and marking those messages read would assert a human action that did not happen.
//   · `shouldMarkRead`'s `focused` arm (2026-09-25 · codex c1): the SAME lie by a different route,
//     and the one the app was actually telling. Expo Router keeps the chat mounted behind a
//     pushed screen with the app perfectly ACTIVE, so `appActive` was true, the poller was
//     running, and every message arriving while the owner was on another screen was marked read.
//
//   · [0223 · codex #1] a read is recorded UP TO A MESSAGE — the newest PEER message a
//     successful fetch put on screen, below any open hole — and the server writes that message's
//     `created_at`. `shouldMarkRead` refuses for EVERY reason when there is no such message:
//     「I opened the thread」 is not a message, and 「read up to now()」 was the claim that let
//     unseen messages become 「읽음」. The receipt compares that position to the microsecond,
//     because it is now a message's exact `created_at` rather than a clock reading.
//
// The mutations that redden it: draw 0 as a badge · treat `loading` as `ready` with no rows ·
// return the caller's own newest message regardless of the read time · use `<` instead of `<=` on
// the receipt boundary · drop the `appActive` arm · drop the `focused` arm · drop the peer-id
// gate on 'message' · [0223] let 'open'/'focus' record with NO peer message on screen (the old
// 「up to now」) · gate 'message' on `>` of ids (an inverted pair is then never acknowledged) ·
// compare the receipt with millisecond `Date.parse` · pick the newest peer message by id rather
// than by (created_at, id) · read through an open gap · acknowledge a message no fetch returned.
const {
  unreadFor, unreadBadge, unreadBadgeLabel, totalUnread, totalUnreadBadge, formatUnreadBadge,
  UNREAD_BADGE_CAP, readReceiptMessageId, READ_RECEIPT_LABEL, shouldMarkRead, newestPeerMessageId,
} = require('./chat-read.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const row = (bookingId, unreadCount, lastMessageAt = '2026-09-23T10:00:00Z') => ({
  threadId: 'th-' + bookingId, bookingId, unreadCount, lastMessageAt,
});
const ready = (...rows) => ({ status: 'ready', rows });
const LOADING = { status: 'loading' };
const ERROR = { status: 'error' };

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ① the badge's four states — three of them are silence
// ══════════════════════════════════════════════════════════════════════════════════════════════
t('loading draws nothing — loading is not 0',
  unreadBadge(LOADING, 'b1') === null && unreadFor(LOADING, 'b1') === null);
t('a failed read draws nothing — a failure is not 「no messages」',
  unreadBadge(ERROR, 'b1') === null && unreadFor(ERROR, 'b1') === null);
t('a booking the read did not list is UNKNOWN, not zero',
  unreadFor(ready(row('b2', 3)), 'b1') === null && unreadBadge(ready(row('b2', 3)), 'b1') === null);
t('a listed booking with 0 is a MEASURED zero (unreadFor says 0, not null)',
  unreadFor(ready(row('b1', 0)), 'b1') === 0);
t('…and a measured zero still draws no badge — an absent chip already says 「nothing waiting」',
  unreadBadge(ready(row('b1', 0)), 'b1') === null);
t('a real count draws the number', unreadBadge(ready(row('b1', 3)), 'b1') === '3');
t('a missing bookingId draws nothing (the bare /chat entry has no booking)',
  unreadBadge(ready(row('b1', 3)), null) === null && unreadBadge(ready(row('b1', 3)), undefined) === null);

// 🔴 The distinction the whole server shape exists for: 「listed with 0」 and 「not listed」 render
// identically AND ARE DIFFERENT FACTS. If these two agreed at the `unreadFor` level too, the
// client could never tell a cleared thread from one the read never covered.
t('🔴 「listed with 0」 and 「absent」 are distinguishable upstream of the badge',
  unreadFor(ready(row('b1', 0)), 'b1') === 0 && unreadFor(ready(row('b2', 0)), 'b1') === null);

t('the cap is a true statement, not a rounded number',
  unreadBadge(ready(row('b1', UNREAD_BADGE_CAP)), 'b1') === String(UNREAD_BADGE_CAP)
  && unreadBadge(ready(row('b1', UNREAD_BADGE_CAP + 1)), 'b1') === UNREAD_BADGE_CAP + '+');

// a server that ever returned nonsense must not become a rendered claim
t('a negative or non-finite count is UNKNOWN, never drawn',
  unreadFor(ready(row('b1', -1)), 'b1') === null
  && unreadFor(ready(row('b1', NaN)), 'b1') === null
  && unreadBadge(ready(row('b1', -1)), 'b1') === null);

t('the a11y label describes the badge and is null when there is none',
  unreadBadgeLabel(ready(row('b1', 3)), 'b1') === '읽지 않은 메시지 3'
  && unreadBadgeLabel(ready(row('b1', 0)), 'b1') === null
  && unreadBadgeLabel(LOADING, 'b1') === null);

t('the total is null while unknown and a sum when known',
  totalUnread(LOADING) === null && totalUnread(ERROR) === null
  && totalUnread(ready(row('b1', 3), row('b2', 0), row('b3', 4))) === 7
  && totalUnread(ready()) === 0);

// 🔴 ONE formatter behind both badges, so the per-booking chip and the all-threads chip can never
// disagree about zero or about the cap — two formatters is how a 0 appears on exactly one screen.
t('the all-threads badge obeys the same zero and cap rules',
  totalUnreadBadge(LOADING) === null
  && totalUnreadBadge(ERROR) === null
  && totalUnreadBadge(ready()) === null
  && totalUnreadBadge(ready(row('b1', 0), row('b2', 0))) === null
  && totalUnreadBadge(ready(row('b1', 3), row('b2', 4))) === '7'
  && totalUnreadBadge(ready(row('b1', 200))) === UNREAD_BADGE_CAP + '+');
t('the formatter refuses zero, negatives and non-numbers',
  formatUnreadBadge(0) === null && formatUnreadBadge(-3) === null
  && formatUnreadBadge(null) === null && formatUnreadBadge(NaN) === null
  && formatUnreadBadge(1) === '1');

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ② the 「읽음」 receipt — every unknown is silence
// ══════════════════════════════════════════════════════════════════════════════════════════════
const msgs = [
  { id: 1, mine: true,  createdAt: '2026-09-23T10:00:00.000Z' },
  { id: 2, mine: false, createdAt: '2026-09-23T10:01:00.000Z' },
  { id: 3, mine: true,  createdAt: '2026-09-23T10:02:00.000Z' },
  { id: 4, mine: true,  createdAt: '2026-09-23T10:05:00.000Z' },
  { id: 5, mine: false, createdAt: '2026-09-23T10:06:00.000Z' },
];

t("🔴 never read = NO receipt (the app must not say 「읽음」 on the server's silence)",
  readReceiptMessageId(msgs, null) === null && readReceiptMessageId(msgs, undefined) === null
  && readReceiptMessageId(msgs, '') === null);
t('an unparseable read time is the same unknown',
  readReceiptMessageId(msgs, 'not a date') === null);
t('the receipt sits on the NEWEST of my messages at or before the read time',
  readReceiptMessageId(msgs, '2026-09-23T10:03:00.000Z') === 3);
t('a later read time moves it forward',
  readReceiptMessageId(msgs, '2026-09-23T10:05:30.000Z') === 4);
t('🔴 「at or before」 includes the exact boundary — a message read on the same instant IS read',
  readReceiptMessageId(msgs, '2026-09-23T10:02:00.000Z') === 3);
t('a read time older than every one of my messages gives no receipt',
  readReceiptMessageId(msgs, '2026-09-23T09:00:00.000Z') === null);
t("🔴 the counterpart's OWN messages never carry my receipt",
  readReceiptMessageId(msgs, '2026-09-23T10:01:30.000Z') === 1);
t('a thread where I have said nothing has no receipt however long ago they read',
  readReceiptMessageId([{ id: 9, mine: false, createdAt: '2026-09-23T10:00:00.000Z' }],
    '2026-09-23T23:00:00.000Z') === null);
t('a message with an unplaceable timestamp is skipped rather than assumed read',
  readReceiptMessageId(
    [{ id: 1, mine: true, createdAt: '2026-09-23T10:00:00.000Z' },
     { id: 2, mine: true, createdAt: '' }],
    '2026-09-23T23:00:00.000Z') === 1);
t('an empty thread is silence', readReceiptMessageId([], '2026-09-23T10:00:00.000Z') === null);
t("the label is the product's word", READ_RECEIPT_LABEL === '읽음');

// order of the input array must not decide the answer — the screen prepends older pages
t('the answer does not depend on array order',
  readReceiptMessageId(msgs.slice().reverse(), '2026-09-23T10:03:00.000Z') === 3);

// ── [0223] the position is now a MESSAGE's exact created_at — so microseconds decide ─────────────
// The counterpart's `last_read_at` is the `created_at` of the caller's message their screen
// acknowledged, verbatim. Two of the caller's messages a fraction of a millisecond apart are ONE
// instant to `Date.parse`; a millisecond compare would hang the receipt on the later one, which the
// counterpart's screen never showed.
t('🔴 [0223] microseconds count: a position 1µs before my message does not cover it — and Date.parse alone would say it did',
  readReceiptMessageId([{ id: 20, mine: true, createdAt: '2026-09-23T10:10:00.000124Z' }], '2026-09-23T10:10:00.000123Z') === null
  && Date.parse('2026-09-23T10:10:00.000124Z') === Date.parse('2026-09-23T10:10:00.000123Z'));
t('🔴 [0223] …so of two of my messages 400µs apart, the position on the EARLIER one puts the receipt there, not on the later',
  readReceiptMessageId([
    { id: 21, mine: true, createdAt: '2026-09-23T10:10:00.000100Z' },
    { id: 22, mine: true, createdAt: '2026-09-23T10:10:00.000500Z' },
  ], '2026-09-23T10:10:00.000100Z') === 21);
t('[0223] the server\'s offset spelling and Z are the same instant',
  readReceiptMessageId([{ id: 23, mine: true, createdAt: '2026-09-23T10:10:00.000100+00:00' }], '2026-09-23T19:10:00.000100+09:00') === 23);
t('[0223] an inverted pair (smaller id, LATER instant) is not read by a position on the earlier instant — the order is time, not id',
  readReceiptMessageId([
    { id: 30, mine: true, createdAt: '2026-09-23T10:10:00.000200Z' },
    { id: 31, mine: true, createdAt: '2026-09-23T10:10:00.000100Z' },
  ], '2026-09-23T10:10:00.000100Z') === 31);
const sameInstant = [
  { id: 41, mine: true, createdAt: '2026-09-23T10:10:00.000100Z' },
  { id: 40, mine: true, createdAt: '2026-09-23T10:10:00.000100Z' },
];
t('[0223] two of my messages on the exact same instant: the receipt sits on the later one in server order (id breaks the tie) — in BOTH array orders',
  readReceiptMessageId(sameInstant, '2026-09-23T10:10:00.000100Z') === 41
  && readReceiptMessageId(sameInstant.slice().reverse(), '2026-09-23T10:10:00.000100Z') === 41);

// ── [0223] the ONE message a read may be recorded up to ─────────────────────────────────────────
const peers = [
  { id: 1, mine: true,  createdAt: '2026-09-23T10:00:00Z' },
  { id: 2, mine: false, createdAt: '2026-09-23T10:01:00Z' },
  { id: 3, mine: false, createdAt: '2026-09-23T10:02:00.000500Z' },
  { id: 4, mine: false, createdAt: '2026-09-23T10:02:00.000400Z' }, // larger id, OLDER instant
  { id: 5, mine: true,  createdAt: '2026-09-23T10:05:00Z' },
];
t('🔴 [0223] the target is the newest PEER message in server order — never my own, and not the largest id',
  newestPeerMessageId(peers) === 3);
t('🔴 [0223] the gap ceiling stops the target at or below the hole — a hole is not read through',
  newestPeerMessageId(peers, { ceilingId: 2 }) === 2
  && newestPeerMessageId(peers, { ceilingId: 1 }) === null
  && newestPeerMessageId(peers, { ceilingId: 3 }) === 3);
// A message that arrived by REALTIME alone has not been vouched for by a fetch: the channel drops
// events across a reconnect, and a dropped message sits BELOW the delivered one, undrawn.
// Acknowledging the delivered one would claim the dropped one was read.
const withRealtime = peers.concat([{ id: 6, mine: false, createdAt: '2026-09-23T10:07:00Z' }]);
const fetched = new Set([1, 2, 3, 4, 5]);
t('🔴 [0223] a peer message no fetch returned is never the target — the newest FETCHED peer message is',
  newestPeerMessageId(withRealtime, { fetchedIds: fetched }) === 3
  && newestPeerMessageId(withRealtime) === 6);
t('[0223] …and once a fetch vouches for it, it is',
  newestPeerMessageId(withRealtime, { fetchedIds: new Set([1, 2, 3, 4, 5, 6]) }) === 6);
t('[0223] an empty fetched set records nothing, whatever is on screen',
  newestPeerMessageId(withRealtime, { fetchedIds: new Set() }) === null);
t('[0223] the ceiling and the fetched set compose — both must admit the message',
  newestPeerMessageId(withRealtime, { ceilingId: 2, fetchedIds: new Set([1, 2, 3, 4, 5, 6]) }) === 2
  && newestPeerMessageId(withRealtime, { ceilingId: 6, fetchedIds: new Set([2]) }) === 2);
t('[0223] no peer message on screen = nothing to record',
  newestPeerMessageId([{ id: 9, mine: true, createdAt: '2026-09-23T10:00:00Z' }]) === null && newestPeerMessageId([]) === null);
t('[0223] array order does not matter', newestPeerMessageId(peers.slice().reverse()) === 3);
const peerTie = [
  { id: 51, mine: false, createdAt: '2026-09-23T10:10:00.000100Z' },
  { id: 50, mine: false, createdAt: '2026-09-23T10:10:00.000100Z' },
];
t('[0223] two peer messages on the exact same instant: the target is the later in server order (id breaks the tie) — in BOTH array orders',
  newestPeerMessageId(peerTie) === 51 && newestPeerMessageId(peerTie.slice().reverse()) === 51);

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ③ when a screen may record a read
// ══════════════════════════════════════════════════════════════════════════════════════════════
const mk = (o) => Object.assign(
  { reason: 'message', ready: true, appActive: true, focused: true, newestPeerMessageId: 5, lastMarkedPeerMessageId: null }, o);

t('nothing is recorded before the thread is ready',
  shouldMarkRead(mk({ ready: false })) === false
  && shouldMarkRead(mk({ reason: 'open', ready: false })) === false
  && shouldMarkRead(mk({ reason: 'focus', ready: false })) === false);
t('🔴 a backgrounded screen records NOTHING — a phone in a pocket reads nothing',
  shouldMarkRead(mk({ appActive: false })) === false
  && shouldMarkRead(mk({ reason: 'open', appActive: false })) === false
  && shouldMarkRead(mk({ reason: 'focus', appActive: false })) === false);
// [0223 · codex #1] These two pins REVERSED, and deliberately. 'open'/'focus' used to record with
// `newestPeerMessageId: null` — which was 「read up to now()」, the claim that let messages the
// screen never drew become 「읽음」. A read position now NAMES a peer message, so with none on
// screen there is nothing to record, whatever the reason.
t('🔴 [0223] with NO peer message on screen nothing is recorded, for EVERY reason — a read is a claim about a message',
  shouldMarkRead(mk({ reason: 'open', newestPeerMessageId: null })) === false
  && shouldMarkRead(mk({ reason: 'focus', newestPeerMessageId: null })) === false
  && shouldMarkRead(mk({ reason: 'message', newestPeerMessageId: null, lastMarkedPeerMessageId: null })) === false);
t('open and focus record whenever there IS something to point at — even the message already marked '
  + '(the server write is monotonic, and a mark whose call failed is repaired by the next focus)',
  shouldMarkRead(mk({ reason: 'open', newestPeerMessageId: 5, lastMarkedPeerMessageId: 5 })) === true
  && shouldMarkRead(mk({ reason: 'focus', newestPeerMessageId: 5, lastMarkedPeerMessageId: 5 })) === true
  && shouldMarkRead(mk({ reason: 'focus', newestPeerMessageId: 3, lastMarkedPeerMessageId: 5 })) === true);
t('an arriving message records only when the newest peer message is a DIFFERENT one from the last marked',
  shouldMarkRead(mk({ newestPeerMessageId: 5, lastMarkedPeerMessageId: null })) === true
  && shouldMarkRead(mk({ newestPeerMessageId: 6, lastMarkedPeerMessageId: 5 })) === true
  && shouldMarkRead(mk({ newestPeerMessageId: 5, lastMarkedPeerMessageId: 5 })) === false);
t('🔴 [0223] 「different」, not 「greater」: the newest in server order can carry a SMALLER id (concurrent inserts) and is still newer',
  shouldMarkRead(mk({ newestPeerMessageId: 4, lastMarkedPeerMessageId: 5 })) === true);
t('a quiet thread does not call the RPC on every poll tick',
  shouldMarkRead(mk({ newestPeerMessageId: null, lastMarkedPeerMessageId: null })) === false);

// ── [2026-09-25 · codex c1] the screen is MOUNTED but nobody is looking at it ─────────────────
// 🔴 The defect this closes was reachable every single day and left no trace: Expo Router keeps
// the chat mounted behind a pushed screen, the app stays 'active', the poller keeps running — so
// a message arriving while the owner is on 예약 상세 was marked read, and the runner who sent
// 「5분 늦어요」 saw 「읽음」 about a message nobody had seen. `appActive` cannot catch this: it is
// TRUE the whole time. The two facts are independent and the screen must pass both.
t('🔴 an UNFOCUSED screen records nothing on an arriving message, however active the app is',
  shouldMarkRead(mk({ focused: false, appActive: true })) === false);
t('🔴 …and it refuses for EVERY reason, not just the arriving-message one',
  shouldMarkRead(mk({ focused: false, reason: 'open' })) === false
  && shouldMarkRead(mk({ focused: false, reason: 'focus' })) === false
  && shouldMarkRead(mk({ focused: false, reason: 'message', lastMarkedPeerMessageId: null })) === false);
t('the two facts are INDEPENDENT — neither one alone licenses a receipt',
  shouldMarkRead(mk({ focused: true, appActive: false })) === false
  && shouldMarkRead(mk({ focused: false, appActive: false })) === false
  && shouldMarkRead(mk({ focused: true, appActive: true })) === true);
// The other half of c1, and the half that makes the refusal above safe to ship: nothing is LOST
// while the screen sits unfocused. The 'focus' arm returns true BEFORE the 「different from the
// last marked」 gate, so the pile that arrived while nobody was looking is marked on the way back.
// [0223] It carries the newest peer message the REFRESH put on screen (chat.tsx: `refreshThenRead`
// fetches, the acknowledgement effect records on the commit that renders it) — never null, which
// used to mean 「up to now()」 and is now refused (the pin above).
t('🔴 a message that arrived while UNFOCUSED is marked on the next focus, not dropped',
  shouldMarkRead(mk({ reason: 'message', focused: false, newestPeerMessageId: 7 })) === false
  && shouldMarkRead(mk({ reason: 'focus', focused: true, newestPeerMessageId: 7,
    lastMarkedPeerMessageId: null })) === true);
t('…and it is still marked when this screen had already marked an OLDER message',
  shouldMarkRead(mk({ reason: 'focus', focused: true, newestPeerMessageId: 7,
    lastMarkedPeerMessageId: 3 })) === true);

console.log('');
console.log(pass + ' pass / ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
