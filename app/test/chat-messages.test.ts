import { mergeMessageSnapshot } from '../src/lib/chat-messages';

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

console.log(`\n${passed} pass / ${failed} fail`);
process.exit(failed === 0 ? 0 : 1);
