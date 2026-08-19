#!/usr/bin/env node
// Auth-surface drift check — the sign-in doors, vs a version-controlled snapshot.
// Run: node scripts/check-auth-surface.mjs   (from app/)
//
// WHY THIS EXISTS. Auth configuration is the ONE class of production config this repo cannot
// see: `supabase/config.toml` is 215 bytes with no [auth] section, so providers, disable_signup
// and token lifetimes live only in the dashboard. No migration, harness pin, hook or gate has
// ever been able to observe them. On 2026-08-15 ui removed the email door from the client and
// the server went on accepting email signups — a door removed from the client is not a door
// shut, and nothing in the repo could have noticed.
//
// WHAT IT CANNOT DO, stated because the gap is the reason this is a CHECK and not a config file:
// /auth/v1/settings is a PUBLIC SUBSET. It returns providers, disable_signup, autoconfirm,
// sms_provider, saml and passkeys — and NOT redirect URLs, JWT expiry, SMTP, rate limits or
// password policy. So this pins the doors, not the whole of auth. Declaring [auth] in
// config.toml would cover the rest, but `supabase config push` pushes the LOCAL file and ours
// declares nothing, so it would send CLI defaults for every setting it omits — including the
// Kakao provider. Writing that file needs a read of the remote config that this credential
// cannot perform. Do not "finish" this by guessing the missing half.
//
// It fails on ANY difference, including a GOOD one. That is deliberate: an unacknowledged change
// to who can sign in is exactly the event worth stopping on, and updating the snapshot is a
// one-line commit that records who changed the door and when.
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const snapPath = join(root, 'supabase', 'auth-surface.expected.json');

function env(name) {
  if (process.env[name]) return process.env[name];
  const envFile = join(root, 'app', '.env');
  if (!existsSync(envFile)) return null;
  const line = readFileSync(envFile, 'utf8').split('\n').find((l) => l.startsWith(`${name}=`));
  return line ? line.slice(name.length + 1).trim().replace(/^["']|["']$/g, '') : null;
}

const url = env('EXPO_PUBLIC_SUPABASE_URL');
const key = env('EXPO_PUBLIC_SUPABASE_ANON_KEY');   // PUBLIC key — ships in every build

// A guard that cannot run must say so and fail, never pass quietly. 2026-08-15: five worktrees
// had core.hooksPath pointing at a deleted directory and git ran no hooks without a word.
if (!url || !key) {
  console.error('❌ cannot check the auth surface: EXPO_PUBLIC_SUPABASE_URL / _ANON_KEY not found');
  console.error('   (env vars, or app/.env). Refusing to pass unverified — a guard that skips');
  console.error('   silently is indistinguishable from one that passed.');
  process.exit(1);
}
if (!existsSync(snapPath)) {
  console.error(`❌ no snapshot at ${snapPath}`);
  process.exit(1);
}

const expected = JSON.parse(readFileSync(snapPath, 'utf8'));
const res = await fetch(`${url}/auth/v1/settings`, { headers: { apikey: key } });
if (!res.ok) {
  console.error(`❌ /auth/v1/settings returned ${res.status}`);
  process.exit(1);
}
const live = await res.json();

const diffs = [];
const walk = (exp, got, path) => {
  for (const k of Object.keys(exp)) {
    if (k.startsWith('_')) continue;                       // _comment keys are notes, not state
    const p = path ? `${path}.${k}` : k;
    if (exp[k] && typeof exp[k] === 'object') walk(exp[k], got?.[k] ?? {}, p);
    else if (exp[k] !== got?.[k]) diffs.push(`${p}: expected ${JSON.stringify(exp[k])}, live ${JSON.stringify(got?.[k])}`);
  }
};
walk(expected, live, '');

if (diffs.length) {
  console.error('❌ AUTH SURFACE DRIFT — who can sign in has changed:\n');
  for (const d of diffs) console.error(`   ${d}`);
  console.error('\n   If the change was intended, update supabase/auth-surface.expected.json in a');
  console.error('   commit that says WHO changed it and WHY. The dashboard leaves no other trace.');
  process.exit(1);
}
console.log(`✅ auth surface matches the snapshot (${Object.keys(expected.external ?? {}).length} providers pinned)`);
