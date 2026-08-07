// Runner certification ops — the operator surface for the application funnel (0062).
// Modelled on scripts/seed-runners.mjs: root .env, service-role key, plain fetch against PostgREST.
//
//   node scripts/runner-ops.mjs list
//   node scripts/runner-ops.mjs show    <application_id>
//   node scripts/runner-ops.mjs review  <application_id> <operator>
//   node scripts/runner-ops.mjs approve <application_id> <operator> "<note>"
//   node scripts/runner-ops.mjs reject  <application_id> <operator> "<reason>" [--hard]
//
// Why a script and not an edge function or an in-app admin screen: there is exactly one operator
// and he holds the service key (plan D4). The moment a second operator exists this needs a real
// identity, and `decided_by` is the seam — today it is a self-declared string and this script says so.
//
// The three mutating commands go through the revoked RPCs ONLY. There is no raw update statement
// anywhere in this file, so the script cannot do anything the state machine would not do: it
// cannot approve twice, cannot skip a state, cannot reject without a reason, cannot raise a tier
// by hand. Deliberate — the RPCs are the audited surface and this is just a keyboard on top of them.
//
// `list` and `show` read the table directly (the service role bypasses RLS, which is the only way
// to read it at all — runner_applications has zero policies).

import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

function loadEnv(path) {
  try {
    return Object.fromEntries(
      readFileSync(path, 'utf8').split('\n')
        .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
        .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
    );
  } catch { return {}; }
}
const env = { ...loadEnv(join(ROOT, 'app/.env')), ...loadEnv(join(ROOT, '.env')), ...process.env };
const URL_ = env.EXPO_PUBLIC_SUPABASE_URL;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;

const H = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' };

const HELP = `runner-ops — runner certification funnel (0062)

  list                                            queue: submitted + under_review, oldest first
  show    <id>                                    full row incl. contact details and payload
  review  <id> <operator>                         submitted -> under_review
  approve <id> <operator> "<note>"                -> approved; raises runners.tier to certified
  reject  <id> <operator> "<reason>" [--hard]     -> rejected; reason is shown to the applicant verbatim

Flag form is accepted too (plan §4): --by <operator> --note "..." --reason "..."
  --hard    permanent bar; the applicant can never re-apply
  --yes     skip the confirmation prompt (required when stdin is not a terminal)
  --help    this text

The operator handle and the approve note are REQUIRED. The note is where "I actually did the video
call and saw the ID" is recorded — it is the thing that makes the 러너 신원 copy on safety.tsx true
(plan §7.1 condition 4). It is not a nicety and there is no default.

Reads SUPABASE_SERVICE_ROLE_KEY and EXPO_PUBLIC_SUPABASE_URL from the root .env.
Every mutation goes through the ops RPCs, which are revoked from public/anon/authenticated.`;

const argv = process.argv.slice(2);
if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
  console.log(HELP);
  process.exit(argv.length === 0 ? 1 : 0);
}

// ---------- arg parsing: positional first, named flags as the plan §4 alternative ----------
function flag(name) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] ?? null : null;
}
const HARD = argv.includes('--hard');
const YES = argv.includes('--yes');
// Everything that is not a flag or a flag's value. Keeps `approve <id> <op> "<note>" --hard` and
// `approve <id> --by sean --note "..."` both working without a dependency.
const VALUED_FLAGS = ['by', 'note', 'reason'];
const positional = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith('--')) {
    if (VALUED_FLAGS.includes(a.slice(2))) i++; // skip its value
    continue;
  }
  positional.push(a);
}
const cmd = positional[0];

function die(msg) { console.error(`✗ ${msg}`); process.exit(1); }
if (!URL_ || !SERVICE) die('SUPABASE_SERVICE_ROLE_KEY and EXPO_PUBLIC_SUPABASE_URL must be in the root .env');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function requireId(v) {
  if (!v) die('application id required — run `list` to find it');
  if (!UUID_RE.test(v)) die(`not an application id: ${v}`);
  return v;
}
function requireText(v, what) {
  const s = (v ?? '').trim();
  if (!s) die(`${what} required — see --help`);
  return s;
}

// ---------- transport ----------
async function rest(path) {
  const res = await fetch(`${URL_}/rest/v1/${path}`, { headers: H });
  const body = await res.text();
  if (!res.ok) die(`${res.status} ${body}`); // server message verbatim — never paraphrased
  try { return JSON.parse(body); } catch { return null; }
}

// A failed RPC prints exactly what the server said. The tokens (not_found, not_approvable,
// ops_only, operator_required, …) are the contract; translating them here would hide which gate
// actually refused.
async function rpc(fn, args) {
  const res = await fetch(`${URL_}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: H, body: JSON.stringify(args),
  });
  const body = await res.text();
  if (!res.ok) die(`${fn} failed — ${res.status} ${body}`);
  try { return JSON.parse(body); } catch { return body; }
}

function confirm(lines) {
  console.log('');
  for (const l of lines) console.log(l);
  console.log('');
  if (YES) { console.log('(--yes) proceeding'); return Promise.resolve(); }
  if (!process.stdin.isTTY) {
    die('stdin is not a terminal — re-run with --yes if this is really what you want');
  }
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('proceed? [y/N] ', (a) => {
      rl.close();
      if (a.trim().toLowerCase() !== 'y') { console.log('aborted — nothing was sent'); process.exit(0); }
      resolve();
    });
  });
}

const short = (v) => (v ? String(v).slice(0, 8) : '—');
const when = (v) => (v ? String(v).slice(0, 16).replace('T', ' ') : '—');

// ---------- commands ----------
const SELECT_LIST = 'id,profile_id,attempt_no,state,district,contact_kakao,contact_phone,contact_window,created_at,reviewed_at';

if (cmd === 'list') {
  const rows = await rest(
    `runner_applications?state=in.(submitted,under_review)&select=${SELECT_LIST}&order=created_at.asc`,
  );
  if (!rows || rows.length === 0) {
    console.log('queue empty — no submitted or under_review applications');
    process.exit(0);
  }
  console.log(`${rows.length} waiting (oldest first)\n`);
  for (const r of rows) {
    const contact = [r.contact_kakao && `kakao ${r.contact_kakao}`, r.contact_phone].filter(Boolean).join(' · ') || '—';
    console.log(`  ${r.id}`);
    console.log(`    ${r.state.padEnd(12)} attempt ${r.attempt_no}  ${r.district}  profile ${short(r.profile_id)}…`);
    console.log(`    submitted ${when(r.created_at)}${r.reviewed_at ? `  reviewed ${when(r.reviewed_at)}` : ''}`);
    console.log(`    contact: ${contact}${r.contact_window ? `  (${r.contact_window})` : ''}`);
    console.log('');
  }
  console.log('next: review <id> <operator>, then approve/reject after the video call');
  process.exit(0);
}

if (cmd === 'show') {
  const id = requireId(positional[1]);
  const rows = await rest(`runner_applications?id=eq.${id}&select=*`);
  if (!rows || rows.length === 0) die(`no application ${id}`);
  const r = rows[0];
  for (const [k, v] of Object.entries(r)) {
    console.log(`  ${k.padEnd(21)} ${Array.isArray(v) ? JSON.stringify(v) : v ?? '—'}`);
  }
  process.exit(0);
}

if (cmd === 'review') {
  const id = requireId(positional[1]);
  const operator = requireText(positional[2] ?? flag('by'), 'operator handle');
  await rpc('runner_app_review', { p_application: id, p_operator: operator });
  console.log(`✓ ${id} → under_review (by ${operator})`);
  console.log('  the applicant now sees 검토 중 — contact them in their stated window');
  process.exit(0);
}

if (cmd === 'approve') {
  const id = requireId(positional[1]);
  const operator = requireText(positional[2] ?? flag('by'), 'operator handle');
  const note = requireText(positional[3] ?? flag('note'), 'note (what you actually verified on the call)');
  await confirm([
    'APPROVE',
    `  application  ${id}`,
    `  operator     ${operator}`,
    `  note         ${note}`,
    '',
    '  This raises runners.tier to certified and sets identity_verified = true.',
    '  The runner becomes bookable by real owners and can take custody of a dog.',
    '  It does NOT flip `online` — tell them to turn it on in 러너 홈 or they stay invisible.',
    '  Only approve if you did the video call and saw the ID on camera.',
  ]);
  const profile = await rpc('runner_app_approve', { p_application: id, p_operator: operator, p_note: note });
  console.log(`✓ ${id} → approved  (profile ${String(profile).replace(/"/g, '')})`);
  console.log('  reminder: ask them to open 러너 홈 and check 온라인 is on (approval does not set it)');
  process.exit(0);
}

if (cmd === 'reject') {
  const id = requireId(positional[1]);
  const operator = requireText(positional[2] ?? flag('by'), 'operator handle');
  const reason = requireText(positional[3] ?? flag('reason'), 'reason (the applicant reads this verbatim)');
  await confirm([
    HARD ? 'REJECT — HARD BAR' : 'REJECT',
    `  application  ${id}`,
    `  operator     ${operator}`,
    `  reason       ${reason}`,
    '',
    '  The reason above is shown to the applicant word for word. Write it to them, not about them.',
    HARD
      ? '  --hard: permanent. This account can never apply again, and there is no un-bar command.'
      : '  Soft reject: they may re-apply, up to 3 attempts total.',
  ]);
  await rpc('runner_app_reject', {
    p_application: id, p_operator: operator, p_reason: reason, p_hard_bar: HARD,
  });
  console.log(`✓ ${id} → rejected${HARD ? ' (hard bar)' : ''} (by ${operator})`);
  process.exit(0);
}

die(`unknown command: ${cmd}\n\n${HELP}`);
