import {
  GAP_DOOR_LABEL, compareInstant, compareMessageOrder, gapClosedBy, mergeMessageSnapshot,
  olderThanCursorFilter, parseInstant, snapshotGap,
} from '../src/lib/chat-messages';

interface Message { id: number; source: string }

let passed = 0;
let failed = 0;

function equal(label: string, actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    passed++;
    console.log(`PASS ${label}`);
    return;
  }
  failed++;
  console.log(`FAIL ${label}\n  got:  ${JSON.stringify(actual)}\n  want: ${JSON.stringify(expected)}`);
}

equal(
  'a stale snapshot cannot delete a message received live while it was loading',
  mergeMessageSnapshot<Message>(
    [{ id: 4, source: 'live' }],
    [{ id: 1, source: 'snapshot' }, { id: 2, source: 'snapshot' }, { id: 3, source: 'snapshot' }],
  ),
  [
    { id: 1, source: 'snapshot' },
    { id: 2, source: 'snapshot' },
    { id: 3, source: 'snapshot' },
    { id: 4, source: 'live' },
  ],
);

equal(
  'the current live item wins when a stale snapshot contains the same ID',
  mergeMessageSnapshot<Message>(
    [{ id: 2, source: 'live' }],
    [{ id: 2, source: 'stale snapshot' }],
  ),
  [{ id: 2, source: 'live' }],
);

equal(
  'duplicate precedence is deterministic within each input',
  mergeMessageSnapshot<Message>(
    [{ id: 2, source: 'older current duplicate' }, { id: 2, source: 'later current duplicate' }],
    [{ id: 2, source: 'later snapshot duplicate' }, { id: 2, source: 'last snapshot duplicate' }],
  ),
  [{ id: 2, source: 'later current duplicate' }],
);

equal(
  'interleaved inputs are returned in ascending ID order',
  mergeMessageSnapshot<Message>(
    [{ id: 6, source: 'live' }, { id: 2, source: 'live' }],
    [{ id: 5, source: 'snapshot' }, { id: 1, source: 'snapshot' }, { id: 4, source: 'snapshot' }],
  ).map((message) => message.id),
  [1, 2, 4, 5, 6],
);

// ══════════════════════════════════════════════════════════════════════════════════════════════
// the reconnect HOLE (2026-09-25 · codex c3)
// ══════════════════════════════════════════════════════════════════════════════════════════════
// 🔴 THE MEASUREMENT FIRST, because the defect is invisible in the merge's own output: the union
// is CORRECT and it is also the thing that hides the hole. A screen holding 1..50 that is handed
// a snapshot of 200..299 gets a 150-message list whose bubbles sit against each other exactly as
// they would in a conversation that never stopped. Nothing in the array says 51..199 are missing,
// and 「이전 메시지 더 보기」 pages backward from the OLDEST held message — below the hole — so no
// door on the screen could ever fill it.

const run = (from: number, to: number, source: string): Message[] => {
  const out: Message[] = [];
  for (let id = from; id <= to; id += 1) out.push({ id, source });
  return out;
};

const stranded = mergeMessageSnapshot<Message>(run(1, 50, 'held'), run(200, 299, 'snapshot'));
equal('THE DEFECT: the merge is a union, so the hole is invisible in its own output',
  [stranded.length, stranded[49].id, stranded[50].id], [150, 50, 200]);
equal('…and nothing between them survived to be drawn',
  stranded.filter((m) => m.id > 50 && m.id < 200).length, 0);
equal('🔴 the hole is REPORTED, between two real messages the screen can point at',
  snapshotGap<Message>(run(1, 50, 'held'), run(200, 299, 'snapshot')), { afterId: 50, beforeId: 200 });

// The ordinary poll, tick after tick: the window has not moved past what the screen holds.
equal('an overlapping snapshot has NO gap — this is every normal poll',
  snapshotGap<Message>(run(1, 100, 'held'), run(60, 120, 'snapshot')), null);
equal('a snapshot identical to the held window has no gap',
  snapshotGap<Message>(run(1, 100, 'held'), run(1, 100, 'snapshot')), null);
equal('the FIRST load has no gap — an empty screen strands nothing below',
  snapshotGap<Message>([], run(200, 299, 'snapshot')), null);
equal('an empty snapshot says nothing about anything',
  snapshotGap<Message>(run(1, 50, 'held'), []), null);
equal('a snapshot entirely OLDER than everything held is not a hole — an older page merging below',
  snapshotGap<Message>(run(200, 299, 'held'), run(1, 50, 'snapshot')), null);

// 🔴 WHY THE DETECTOR IS MEMBERSHIP AND NOT ID ARITHMETIC, pinned in both directions.
// `chat_messages.id` is a TABLE-wide identity shared with every other thread, so ids inside one
// thread are not consecutive and 「snapshot.min − held.max」 is neither a count nor a contiguity
// test. These two cases are where the subtraction gets it wrong, and they are not exotic:
equal('🔴 ids that jump do NOT make a hole, as long as the snapshot starts inside our history',
  snapshotGap<Message>(
    [{ id: 10, source: 'held' }, { id: 4000, source: 'held' }],
    [{ id: 4000, source: 'snap' }, { id: 9100, source: 'snap' }],
  ), null);
equal('🔴 one live message can raise the highest held id ABOVE the whole snapshot — the hole is '
  + 'still there and a max-based detector is blind to it',
  snapshotGap<Message>(
    [...run(1, 50, 'held'), { id: 901, source: 'realtime' }],
    run(800, 901, 'snapshot'),
  ), { afterId: 50, beforeId: 800 });

// Closing it. The page is fetched strictly older than the snapshot's oldest, newest first.
equal('a page that reaches back to a held message CLOSES the hole',
  gapClosedBy<Message>(50, run(45, 144, 'older')), true);
equal('a page that stops short of it does NOT — the door stays and the cursor moves',
  gapClosedBy<Message>(50, run(100, 199, 'older')), false);
equal('the boundary message itself closes it', gapClosedBy<Message>(50, [{ id: 50, source: 'o' }]), true);
equal('an EMPTY page closes it — the server has nothing in the hole, so a door would be dead',
  gapClosedBy<Message>(50, []), true);

equal('the door says what it opens, in the product\'s own words',
  GAP_DOOR_LABEL, '빠진 메시지 불러오기');

// Filling it must never cost a held message, and must never double one.
const filled = mergeMessageSnapshot<Message>(stranded, run(45, 205, 'fill'));
equal('a filled hole is one unbroken run, oldest first, with nothing lost or duplicated',
  [filled.length, filled[0].id, filled[filled.length - 1].id,
    filled.every((m, i) => i === 0 || m.id === filled[i - 1].id + 1)],
  [299, 1, 299, true]);
equal('the messages already held won their own ids through the fill',
  filled[49].source, 'held');
equal('…and the refilled hole is gone', snapshotGap<Message>(filled, run(200, 299, 'snapshot')), null);

// ── [0223 · codex #2] the (created_at, id) order — compared the way the SERVER compares it ──────
// `Date.parse` is millisecond-coarse and `created_at` is microsecond-precise; a cursor built on
// Date.parse would misorder two messages 100µs apart and, on a page boundary, never move. These
// pin that every digit the server sent survives, that the order is time-then-id, and that the
// filter string the server receives is the row-order strict-less-than.
const T0 = Date.UTC(2026, 8, 23, 10, 0, 0);
equal('parseInstant keeps a 6-digit fraction: ms into Date.parse, the rest as sub-ms nanoseconds',
  parseInstant('2026-09-23T10:00:00.123456+00:00'), [T0 + 123, 456000]);
equal('parseInstant: Z and +00:00 spell the same instant',
  parseInstant('2026-09-23T10:00:00.123456Z'), [T0 + 123, 456000]);
equal('parseInstant: no fraction is [ms, 0]', parseInstant('2026-09-23T10:00:00Z'), [T0, 0]);
equal('parseInstant: a 1-digit fraction is tenths, not a raw digit', parseInstant('2026-09-23T10:00:00.5Z'), [T0 + 500, 0]);
equal('parseInstant: a 3-digit fraction has no sub-ms part', parseInstant('2026-09-23T10:00:00.250Z'), [T0 + 250, 0]);
equal('parseInstant: a +09:00 offset is placed on the timeline', parseInstant('2026-09-23T19:00:00.000001+09:00'), [T0, 1000]);
equal('parseInstant: unparseable is null, never a guess', [parseInstant('not a date'), parseInstant(''), parseInstant('2026-13-45T99:00:00Z')], [null, null, null]);

equal('🔴 compareInstant orders by the microsecond Date.parse cannot see',
  [compareInstant('2026-09-23T10:00:00.000400Z', '2026-09-23T10:00:00.000500Z'),
    compareInstant('2026-09-23T10:00:00.000500Z', '2026-09-23T10:00:00.000400Z'),
    Date.parse('2026-09-23T10:00:00.000400Z') === Date.parse('2026-09-23T10:00:00.000500Z')],
  [-1, 1, true]);
equal('compareInstant: equal instants in two spellings are 0',
  compareInstant('2026-09-23T10:00:00.123456+00:00', '2026-09-23T10:00:00.123456Z'), 0);
equal('compareInstant: whole seconds still order', compareInstant('2026-09-23T10:00:01Z', '2026-09-23T10:00:00.999999Z'), 1);
equal('compareInstant: null when either side cannot be placed',
  [compareInstant('x', '2026-09-23T10:00:00Z'), compareInstant('2026-09-23T10:00:00Z', '')], [null, null]);

equal('compareMessageOrder: time first — a larger id with an older instant is OLDER',
  compareMessageOrder({ createdAt: '2026-09-23T10:00:00.000500Z', id: 1 }, { createdAt: '2026-09-23T10:00:00.000400Z', id: 2 }), 1);
equal('compareMessageOrder: id breaks an exact tie',
  [compareMessageOrder({ createdAt: '2026-09-23T10:00:00Z', id: 1 }, { createdAt: '2026-09-23T10:00:00Z', id: 2 }),
    compareMessageOrder({ createdAt: '2026-09-23T10:00:00Z', id: 2 }, { createdAt: '2026-09-23T10:00:00Z', id: 2 })],
  [-1, 0]);
equal('compareMessageOrder: null when a side cannot be placed — no silent fall-back to id order',
  compareMessageOrder({ createdAt: '', id: 1 }, { createdAt: '2026-09-23T10:00:00Z', id: 2 }), null);

equal('olderThanCursorFilter is the row-order strict less-than, timestamp double-quoted, id bare',
  olderThanCursorFilter({ createdAt: '2026-09-23T10:00:00.123456+00:00', id: 42 }),
  'created_at.lt."2026-09-23T10:00:00.123456+00:00",and(created_at.eq."2026-09-23T10:00:00.123456+00:00",id.lt.42)');

console.log(`\n${passed} pass / ${failed} fail`);
process.exit(failed === 0 ? 0 : 1);
