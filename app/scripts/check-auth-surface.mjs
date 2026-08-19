#!/usr/bin/env node
// Auth-surface drift check — the full auth config, vs a version-controlled snapshot.
// Run: node scripts/check-auth-surface.mjs   (from app/)
//
// WHY THIS EXISTS. Auth configuration is the one class of production config this repo cannot
// otherwise see: `supabase/config.toml` is 215 bytes with no [auth] section, so providers,
// redirect URLs, token lifetimes and rate limits live only in the dashboard. No migration,
// harness pin, hook or gate can observe them. On 2026-08-15 ui removed the email door from the
// client and the server went on accepting email signups — a door removed from the client is not
// a door shut, and nothing in the repo could have noticed.
//
// CREDENTIAL. Reads the Supabase CLI's own access token from the macOS KEYCHAIN (or
// SUPABASE_ACCESS_TOKEN). Sanctioned by CLAUDE.md: a machine-configured credential may be USED;
// its value is never typed, printed, logged or written to a file. It goes from the keychain into
// an Authorization header and nowhere else.
//   ⚠ v1 of this script claimed this read was impossible "with no credential on this machine".
//   That was FALSE and it is the mistake worth remembering: I checked for a FILE
//   (~/.supabase/access-token), found none, and recorded a tooling limit as a fact about the
//   world. The macOS CLI stores it in the keychain. Absence of evidence, in the one place I
//   happened to look.
//
// READ ONLY, and the write path stays dangerous. This performs a GET. Never "fix" auth drift
// with `supabase config push`: it pushes the LOCAL config.toml, which declares nothing, so it
// would send CLI defaults for every setting the file omits — including switching off the Kakao
// provider that must stay on. Drift is fixed in the dashboard, deliberately, by a person.
//
// WHY AN ALLOWLIST AND NOT A DENYLIST. The live config is 242 fields and several hold real
// secrets — `external_kakao_secret` is populated right now. A regex denylist is the same defect
// as grepping policies for `auth.uid()`: it matches names, not meaning. Measured: a
// secret|password|token denylist does NOT match `smtp_pass`. So the snapshot is built from an
// explicit allowlist of security-relevant, provably non-secret fields, and adding a field is a
// deliberate edit here rather than an accident of pattern matching.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const snapPath = join(root, 'supabase', 'auth-surface.expected.json');
const PROJECT = 'zjabnywjpvpgmtajygqy';

const inAllowlist = (k) =>
  (k.startsWith('external_') && k.endsWith('_enabled')) ||
  k.startsWith('rate_limit_') ||
  (k.startsWith('hook_') && (k.endsWith('_enabled') || k.endsWith('_uri'))) ||
  [ 'disable_signup', 'site_url', 'uri_allow_list', 'jwt_exp', 'password_min_length',
    'password_required_characters', 'password_hibp_enabled', 'refresh_token_rotation_enabled',
    'security_refresh_token_reuse_interval', 'mailer_autoconfirm', 'mailer_otp_exp',
    'security_captcha_enabled', 'security_captcha_provider', 'sms_provider',
    'security_manual_linking_enabled', 'sessions_timebox', 'sessions_inactivity_timeout',
  ].includes(k);

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN;
  try {
    return execFileSync('security', ['find-generic-password', '-s', 'Supabase CLI', '-w'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { return null; }
}

// A guard that cannot run must say so and FAIL, never pass quietly. 2026-08-15: five worktrees
// had core.hooksPath pointing at a deleted directory and git ran no hooks without a word.
const tok = token();
if (!tok) {
  console.error('❌ cannot check the auth surface: no Supabase access token.');
  console.error('   Expected the CLI keychain entry ("Supabase CLI") or SUPABASE_ACCESS_TOKEN.');
  console.error('   Refusing to pass unverified — a guard that skips silently is');
  console.error('   indistinguishable from one that passed.');
  process.exit(1);
}
if (!existsSync(snapPath)) { console.error(`❌ no snapshot at ${snapPath}`); process.exit(1); }

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}/config/auth`,
  { headers: { Authorization: `Bearer ${tok}` } });
if (!res.ok) { console.error(`❌ management API returned ${res.status}`); process.exit(1); }
const full = await res.json();

const live = Object.fromEntries(Object.entries(full).filter(([k]) => inAllowlist(k)).sort());
const expected = JSON.parse(readFileSync(snapPath, 'utf8'));

const diffs = [];
for (const k of Object.keys(expected).filter((k) => !k.startsWith('_'))) {
  const a = JSON.stringify(expected[k]), b = JSON.stringify(live[k]);
  if (a !== b) diffs.push(`${k}: expected ${a}, live ${b}`);
}
for (const k of Object.keys(live)) {
  if (!(k in expected)) diffs.push(`${k}: NEW field, live ${JSON.stringify(live[k])} — not in snapshot`);
}

if (diffs.length) {
  console.error('❌ AUTH SURFACE DRIFT — who can sign in, or how, has changed:\n');
  for (const d of diffs) console.error(`   ${d}`);
  console.error('\n   If intended, update supabase/auth-surface.expected.json in a commit naming');
  console.error('   WHO changed it and WHY. The dashboard leaves no other trace anywhere.');
  process.exit(1);
}
console.log(`✅ auth surface matches the snapshot (${Object.keys(live).length} fields pinned)`);
