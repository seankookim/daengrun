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
//
// The mutations that redden it: draw 0 as a badge · treat `loading` as `ready` with no rows ·
// return the caller's own newest message regardless of the read time · use `<` instead of `<=` on
// the receipt boundary · drop the `appActive` arm · drop the peer-id gate on 'message'.
const {
  unreadFor, unreadBadge, unreadBadgeLabel, totalUnread, totalUnreadBadge, formatUnreadBadge,
  UNREAD_BADGE_CAP, readReceiptMessageId, READ_RECEIPT_LABEL, shouldMarkRead,
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

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ③ when a screen may record a read
// ══════════════════════════════════════════════════════════════════════════════════════════════
const mk = (o) => Object.assign(
  { reason: 'message', ready: true, appActive: true, newestPeerMessageId: 5, lastMarkedPeerMessageId: null }, o);

t('nothing is recorded before the thread is ready',
  shouldMarkRead(mk({ ready: false })) === false
  && shouldMarkRead(mk({ reason: 'open', ready: false })) === false
  && shouldMarkRead(mk({ reason: 'focus', ready: false })) === false);
t('🔴 a backgrounded screen records NOTHING — a phone in a pocket reads nothing',
  shouldMarkRead(mk({ appActive: false })) === false
  && shouldMarkRead(mk({ reason: 'open', appActive: false })) === false
  && shouldMarkRead(mk({ reason: 'focus', appActive: false })) === false);
t('open and focus record unconditionally while active (mark_read is monotonic, so a redundant call is a no-op)',
  shouldMarkRead(mk({ reason: 'open', newestPeerMessageId: null })) === true
  && shouldMarkRead(mk({ reason: 'focus', newestPeerMessageId: null })) === true
  && shouldMarkRead(mk({ reason: 'focus', newestPeerMessageId: 5, lastMarkedPeerMessageId: 5 })) === true);
t('an arriving message records only when it is NEWER than what this screen already marked',
  shouldMarkRead(mk({ newestPeerMessageId: 5, lastMarkedPeerMessageId: null })) === true
  && shouldMarkRead(mk({ newestPeerMessageId: 6, lastMarkedPeerMessageId: 5 })) === true
  && shouldMarkRead(mk({ newestPeerMessageId: 5, lastMarkedPeerMessageId: 5 })) === false
  && shouldMarkRead(mk({ newestPeerMessageId: 4, lastMarkedPeerMessageId: 5 })) === false);
t('a quiet thread does not call the RPC on every poll tick',
  shouldMarkRead(mk({ newestPeerMessageId: null, lastMarkedPeerMessageId: null })) === false);

console.log('');
console.log(pass + ' pass / ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
