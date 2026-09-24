import {
  GAP_DOOR_LABEL, gapClosedBy, mergeMessageSnapshot, snapshotGap,
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

console.log(`\n${passed} pass / ${failed} fail`);
process.exit(failed === 0 ? 0 : 1);
