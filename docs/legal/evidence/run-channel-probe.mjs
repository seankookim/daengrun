// EVIDENCE, NOT A TEST. Read the header before reusing this.
//
// This is the probe that produced the measurement behind the P0 in
// docs/legal/readiness-review-2026-08-19.md §2ⓒ: the `run-<bookingId>` live-GPS channel is a
// PUBLIC Supabase broadcast channel. Two clients holding only the app's public anon key, never
// logged in, with no booking relationship, exchanged a position payload.
//
// Measured 2026-08-19 against the LINKED PRODUCTION PROJECT. Output:
//
//   stranger subscribe status: SUBSCRIBED
//   publisher subscribe status: SUBSCRIBED
//   publish result: ok
//   STRANGER RECEIVED: {"lat":37.5109,"lng":126.9959,"km":1.2,"paceSec":330}
//
// ─────────────────────────────────────────────────────────────────────────────
// TURNING THIS INTO THE REGRESSION TEST — four things it does NOT do
// ─────────────────────────────────────────────────────────────────────────────
//
// ① IT HAS NO POSITIVE ARM, AND WITHOUT ONE IT IS A FALSE-GREEN GENERATOR.
//    After the fix, "the stranger received nothing" is satisfied just as well by a broken
//    publisher, a renamed topic, a typo'd event name, or a channel nobody joined. A test that
//    only asserts the negative passes forever once the feature is dead. The regression test
//    needs BOTH arms in the same run, against the same topic:
//      negative — an unrelated client must NOT receive (and should be REJECTED at subscribe)
//      positive — the booking's actual owner MUST still receive
//    The positive arm is the harder one to build and the one that actually protects the owner's
//    live map. It needs real signed-in JWTs for a real booking's owner and assigned runner, plus
//    `supabase.realtime.setAuth(token)` — private channels authorize off the realtime socket's
//    token, not the PostgREST one, and forgetting setAuth fails BOTH arms and looks like a pass.
//
// ② IT CANNOT DISTINGUISH "REJECTED" FROM "SLOW". The subscribe promise below resolves on a
//    timeout to 'NO_STATUS'. For a pass/fail test, assert the stranger's terminal status is
//    CHANNEL_ERROR (authorization refused) — do not accept a timeout as proof of blocking. A
//    flaky network would then read as a passing security test.
//
// ③ IT MUST NOT RUN AGAINST PRODUCTION IN CI. This probe published a fabricated position to a
//    production realtime topic. That was deliberate and contained — the topic is a made-up UUID
//    that belongs to no booking, so no owner's map saw it — but the same script pointed at a real
//    booking id is a live injection into a real owner's map. Point the test at a local
//    `supabase start` or a dedicated project, and keep the production run as a one-off,
//    human-invoked check.
//
// ④ THE TOPIC IS MADE UP. Real coverage uses the real shape from a real booking row, because the
//    thing being protected is the mapping from booking party → topic, and a synthetic UUID never
//    exercises it.
//
// The mutation check that makes this pin real, in this repo's idiom: with the fix applied, revert
// `private: true` alone and the negative arm must go RED. If it stays green, the test is watching
// something other than the channel.
//
// ─────────────────────────────────────────────────────────────────────────────
// Run: node docs/legal/evidence/run-channel-probe.mjs
// Requires app/.env and app/node_modules (run from the repo root of a worktree with both).

import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';

const ROOT = process.env.DAENGRUN_APP_DIR ?? path.resolve('app');
const require_ = createRequire(path.join(ROOT, 'package.json'));
const { createClient } = require_('@supabase/supabase-js');

const env = Object.fromEntries(
  fs.readFileSync(path.join(ROOT, '.env'), 'utf8')
    .split('\n').filter((l) => l.includes('='))
    .map((l) => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }),
);
const URL = env.EXPO_PUBLIC_SUPABASE_URL;
const KEY = env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
if (!URL || !KEY) { console.error('MISSING ENV — need EXPO_PUBLIC_SUPABASE_{URL,ANON_KEY}'); process.exit(1); }

// A topic that belongs to no booking. See ③/④ above before changing this to a real id.
const topic = 'run-00000000-0000-4000-8000-probe0000001';

const settle = (ch) => new Promise((r) => {
  ch.subscribe((s) => { if (s === 'SUBSCRIBED' || s === 'CHANNEL_ERROR' || s === 'TIMED_OUT') r(s); });
  setTimeout(() => r('NO_STATUS'), 8000);   // ② — a test must not treat this as "blocked"
});

const pub = createClient(URL, KEY);   // stands in for the runner's device
const sub = createClient(URL, KEY);   // the stranger: separate client, anon, no relationship

let got = null;
const subCh = sub.channel(topic).on('broadcast', { event: 'pos' }, ({ payload }) => { got = payload; });
console.log('stranger subscribe status:', await settle(subCh));

const pubCh = pub.channel(topic);
const pubStatus = await settle(pubCh);
console.log('publisher subscribe status:', pubStatus);

if (pubStatus === 'SUBSCRIBED') {
  console.log('publish result:', await pubCh.send({
    type: 'broadcast', event: 'pos',
    payload: { lat: 37.5109, lng: 126.9959, km: 1.2, paceSec: 330 },
  }));
}

await new Promise((r) => setTimeout(r, 3000));
console.log('STRANGER RECEIVED:', JSON.stringify(got));
console.log(got
  ? '=> PUBLIC CHANNEL: an unrelated anon client received the live position payload'
  : '=> stranger received nothing (see ① — this alone is NOT proof the channel is private)');
process.exit(0);
