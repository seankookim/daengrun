// EVIDENCE. Post-0103 re-measurement: does the server-side fix close the channel?
//
// 0103 added realtime.messages RLS (trust's half). This probe asks the question that RLS alone
// cannot answer: `realtime.messages` policies are only consulted for channels joined AS PRIVATE.
// Privacy is the joining client's choice. So the test is a 2x2 — {current topic, a hypothetical
// renamed topic} x {private: true, private: false}.
//
// Measured 2026-08-19 against the linked production project, after 0103 was deployed:
//
//   existing namespace             private=true  -> CHANNEL_ERROR     ← 0103 works
//   existing namespace             private=false -> SUBSCRIBED        ← and is bypassable
//   hypothetical bumped namespace  private=true  -> CHANNEL_ERROR
//   hypothetical bumped namespace  private=false -> SUBSCRIBED        ← rename cannot help
//
// Two conclusions, both load-bearing:
//
//   ① 0103 is CORRECT and does its job. An attacker simply does not ask for the mode it governs.
//   ② A TOPIC RENAME IS NOT A CONTROL. Note that neither topic below belongs to any booking and
//      one is a namespace that does not exist — public joins succeed on ARBITRARY topic names.
//      Renaming helps only against a stale subscriber on the old topic. The new name ships in the
//      client bundle, which is public by construction.
//
// Closure requires project-level enforcement that refuses public channels outright, so that
// `private: false` stops being an available answer. That is project config, not a migration, and
// it must be flipped together with the client half or the live map breaks for every real user.
//
// UNRESOLVED, deliberately not guessed at: `chat-*` and `bk-*` are `postgres_changes` — a
// different mechanism from broadcast, but they ride the same channel transport. Whether
// disabling public channels project-wide also breaks them is UNTESTED. Test on a non-production
// project before flipping. If they break, they need their own private-mode + policies.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE CLOSURE GATE — agreed 2026-08-19. Re-running THIS FILE is half of it.
// ─────────────────────────────────────────────────────────────────────────────
//
// After `private_only` is flipped, closure requires BOTH instruments in ONE run, on a real build
// before the flip and on production after:
//
//   negative (this file): stranger refused — CHANNEL_ERROR on all four cells.
//   positive (ui's test): the booking's real owner, signed in, private:true + setAuth() →
//                         SUBSCRIBED and receives. Same for a real chat thread and a real
//                         booking-status subscription, since those families convert together.
//
// FAIL EITHER AND IT IS NOT CLOSED. This file alone CANNOT prove closure, and it is important to
// say so at the top of the file that will be re-run: all four cells go CHANNEL_ERROR just as
// readily against a broken policy, a killed transport, or a client that never connects. A
// stranger-only instrument cannot tell "shut" from "dead".
//
// That is the general rule this exposure produced three times — negative-only on the first test,
// private-only after 0103, stranger-only on this gate: **every instrument that can only observe
// failure will report success when the system is dead.** (Fleet roster §7.)
//
// Run: DAENGRUN_APP_DIR=/path/to/app node docs/legal/evidence/run-channel-private-matrix.mjs

import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';

const ROOT = process.env.DAENGRUN_APP_DIR ?? path.resolve('app');
const { createClient } = createRequire(path.join(ROOT, 'package.json'))('@supabase/supabase-js');

const env = Object.fromEntries(
  fs.readFileSync(path.join(ROOT, '.env'), 'utf8')
    .split('\n').filter((l) => l.includes('='))
    .map((l) => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }),
);
const U = env.EXPO_PUBLIC_SUPABASE_URL;
const K = env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
if (!U || !K) { console.error('MISSING ENV'); process.exit(1); }

// Neither topic belongs to a booking. That is the point — see ② above.
const TOPICS = [
  ['existing namespace', 'run-00000000-0000-4000-8000-probe0000001'],
  ['hypothetical bumped namespace', 'runp-v2-00000000-0000-4000-8000-probe0000001'],
];

const settle = (ch) => new Promise((r) => {
  ch.subscribe((s) => { if (['SUBSCRIBED', 'CHANNEL_ERROR', 'TIMED_OUT', 'CLOSED'].includes(s)) r(s); });
  setTimeout(() => r('NO_STATUS'), 8000);
});

for (const [label, topic] of TOPICS) {
  for (const priv of [true, false]) {
    const c = createClient(U, K);
    const ch = c.channel(topic, { config: { private: priv } });
    console.log(`${label.padEnd(30)} private=${String(priv).padEnd(5)} -> ${await settle(ch)}`);
    await c.removeChannel(ch);
  }
}
process.exit(0);
