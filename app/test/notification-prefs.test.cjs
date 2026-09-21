// notification-prefs.ts — tests run against the REAL compiled source (see
// run-notification-prefs-tests.sh), not a retyped copy.
//
// What this file is FOR, since a table of constants can be pinned pointlessly: the screen's copy
// is a CLAIM about what the server does, and the server does something narrower than 「turn off
// notifications」. A preference silences the DEVICE PUSH; the `notifications` row is written either
// way and `alerts.tsx` keeps showing it (0187 §C). So the arms that matter are the two honesty
// arms — no description may promise the record disappears, and the note that says so must survive
// a copy edit — plus the key set, which is a server CONTRACT (`notification_prefs`'s columns and
// `set_notification_prefs`'s `p_<key>` arguments).
//
// The mutations that redden it: delete a category row · add a `safety` KEY (it must stay
// column-less and always-on) · drop `alwaysOn`/`reason` from the safety row · rewrite a
// description to say 알림이 오지 않아요 / 알림함 … 사라 · empty PREFS_NOTE · make `toPrefs`
// default a missing value to false.
const fs = require('fs');
const path = require('path');
const {
  PREF_ROWS, PREF_KEYS, PREFS_NOTE, DEFAULT_PREFS, toPrefs, ALWAYS_ON_TITLES,
} = require('./notification-prefs.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the key set IS a server contract ───────────────────────────────────────────────────────────
// `notification_prefs` (0187 §A) has exactly these four boolean columns, and
// `set_notification_prefs` takes `p_booking / p_chat / p_community / p_reward`. A fifth key here
// is a switch that saves nothing.
const EXPECTED = ['booking', 'chat', 'community', 'reward'];
t('the four keys are exactly the server columns',
  JSON.stringify(PREF_KEYS) === JSON.stringify(EXPECTED), JSON.stringify(PREF_KEYS));
t('the defaults are all ON (opt-out, never opt-in — a person who never opened this screen keeps getting everything)',
  EXPECTED.every((k) => DEFAULT_PREFS[k] === true), JSON.stringify(DEFAULT_PREFS));

const toggleable = PREF_ROWS.filter((r) => r.key !== null);
const always = PREF_ROWS.filter((r) => r.key === null);
t('every toggleable row maps to a real key, once',
  toggleable.length === EXPECTED.length
  && JSON.stringify(toggleable.map((r) => r.key)) === JSON.stringify(EXPECTED),
  JSON.stringify(toggleable.map((r) => r.key)));
t('every key has a row (no column the person cannot reach)',
  EXPECTED.every((k) => PREF_ROWS.some((r) => r.key === k)));

// ── safety is always-on and has NO key ─────────────────────────────────────────────────────────
// `notify_push` returns before it reads notification_prefs for kind safety/system, so there is no
// column to bind. A row with a key here would be a switch whose save the server ignores.
t('exactly one always-on row', always.length === 1);
t('the always-on row is safety-shaped: no key, alwaysOn true, and a REASON (not a silent disabled switch)',
  always.length === 1 && always[0].key === null && always[0].alwaysOn === true
  && typeof always[0].reason === 'string' && always[0].reason.length > 0,
  JSON.stringify(always[0]));
t('no toggleable row claims to be always-on',
  toggleable.every((r) => r.alwaysOn !== true));
t('"safety" never becomes a key (it is not a column, in either direction)',
  !PREF_KEYS.includes('safety') && !PREF_ROWS.some((r) => r.key === 'safety'));

// ── the honesty arms ───────────────────────────────────────────────────────────────────────────
// The note is the one sentence that keeps this screen true, and no description may contradict it.
t('PREFS_NOTE says the push stops and the inbox does not',
  typeof PREFS_NOTE === 'string' && PREFS_NOTE.includes('알림함') && PREFS_NOTE.includes('쌓'),
  PREFS_NOTE);
const LIES = ['알림이 사라', '알림함에서 사라', '기록이 사라', '알림이 오지 않아요'];
for (const r of PREF_ROWS) {
  t(`「${r.label}」 does not promise the record disappears`,
    LIES.every((bad) => !r.desc.includes(bad)), r.desc);
}

// ── every row is renderable ────────────────────────────────────────────────────────────────────
for (const r of PREF_ROWS) {
  t(`「${r.label}」 has a label and a description`,
    typeof r.label === 'string' && r.label.length > 0
    && typeof r.desc === 'string' && r.desc.length > 0);
}
t('labels are unique (they are the React key and the accessibility label)',
  new Set(PREF_ROWS.map((r) => r.label)).size === PREF_ROWS.length);

// ── toPrefs: only an explicit false is OFF — the same rule the server's notify_push uses ───────
t('toPrefs(null) = all on', JSON.stringify(toPrefs(null)) === JSON.stringify(DEFAULT_PREFS));
t('toPrefs(undefined) = all on', JSON.stringify(toPrefs(undefined)) === JSON.stringify(DEFAULT_PREFS));
t('toPrefs({}) = all on (a missing column is never read as OFF)',
  JSON.stringify(toPrefs({})) === JSON.stringify(DEFAULT_PREFS));
t('toPrefs passes an explicit false through',
  toPrefs({ booking: false }).booking === false && toPrefs({ booking: false }).chat === true);
t('toPrefs treats null as unset, not as off (a NULL column must not silence anything)',
  toPrefs({ chat: null }).chat === true);
t('toPrefs ignores extra server columns',
  JSON.stringify(toPrefs({ updated_at: '2026-09-21', profile_id: 'x' })) === JSON.stringify(DEFAULT_PREFS));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [0189] THE DRIFT GATE — three artifacts, read as TEXT, compared in BOTH directions
// ══════════════════════════════════════════════════════════════════════════════════════════════
// Codex REJECT/2 #1: 0114:273-281 admits only `kind = 'booking'` from a booking party, so SOS, a
// filed accident and a run-stop request all reach the server as ordinary booking notifications.
// The ONLY thing that keeps them from being silenced by the 예약·러닝 switch is their TITLE, matched
// exactly against `_noti_urgent_noti_titles()` in migration 0189.
//
// So three copies of each string exist and must never disagree:
//   ① the WRITER in api.ts          (SOS_TITLE · INCIDENT_NOTI_TITLE · RUN_STOP_TITLE)
//   ② this module's ALWAYS_ON_TITLES (what the client believes is always-on)
//   ③ the SQL array in 0189          (what actually decides, on the server)
// A rename that reaches ① but not ③ does not throw, does not fail a type check and does not log:
// the push just stops arriving, for the most urgent message this product sends. Nobody files a bug
// about a push they never saw. That is why this is a gate.
//
// ⚠ COMMENTS ARE STRIPPED FROM BOTH FILES BEFORE MATCHING. Both of them document this very
// mechanism, so an un-stripped read would be satisfied by the prose explaining the guard rather
// than by the guard — the standing comment-quoting law, and the reason it is mechanical here
// instead of a note asking the next reader to be careful.
const stripTs = (src) => src
  .replace(/\/\*[\s\S]*?\*\//g, ' ')      // block comments (the JSDoc above each constant)
  .split('\n').filter((l) => !/^\s*(\/\/|\*)/.test(l)).join('\n');
const stripSql = (src) => src.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

const constOf = (src, name) => {
  const m = src.match(new RegExp(`export const ${name}\\s*=\\s*'([^']*)'`));
  return m ? m[1] : null;
};
const apiSrc = stripTs(fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'api.ts'), 'utf8'));
const routeSrc = stripTs(fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'notification-route.ts'), 'utf8'));
const migDir = path.join(__dirname, '..', '..', 'supabase', 'migrations');
const migName = fs.readdirSync(migDir).find((f) => /^0189_.*\.sql$/.test(f));
t('migration 0189 is on disk (a missing file must fail LOUDLY, never read as "nothing to compare")',
  typeof migName === 'string', String(migName));
const migSrc = migName ? stripSql(fs.readFileSync(path.join(migDir, migName), 'utf8')) : '';

// 🔴 [0193] THE ARRAY IS READ FROM THE **LATEST** MIGRATION THAT DECLARES IT, NEVER FROM 0189 BY
// NAME. 0193 §E re-declares `_noti_urgent_noti_titles()` to add the ONE server-written member
// (0188 arm ⓑ-①'s 「귀가 확인이 필요해요」, which 0187 filed as a disableable booking row — codex
// B5). A gate pinned to 0189's filename would have kept comparing a file that no longer decides
// anything: green, confident, and measuring a superseded declaration. So: find every migration
// that declares the function, take the highest-numbered one, and say which one it was.
const urgentDecls = fs.readdirSync(migDir)
  .filter((f) => /^\d{4}_.*\.sql$/.test(f))
  .filter((f) => /create or replace function _noti_urgent_noti_titles/.test(
    stripSql(fs.readFileSync(path.join(migDir, f), 'utf8'))))
  .sort();
t('at least one migration declares the urgent-title array (absence must fail LOUDLY)',
  urgentDecls.length > 0, JSON.stringify(urgentDecls));
const urgentFile = urgentDecls[urgentDecls.length - 1];
const urgentSrc = urgentFile ? stripSql(fs.readFileSync(path.join(migDir, urgentFile), 'utf8')) : '';
const urgentRaw = urgentFile ? fs.readFileSync(path.join(migDir, urgentFile), 'utf8') : '';
console.log(`  (urgent-title array read from ${urgentFile}; declared in ${JSON.stringify(urgentDecls)})`);

// The server-written member's client-side constant. It is NOT in ALWAYS_ON_TITLES and must not be:
// that array is 「what a CLIENT writer sends」, and nothing in the app writes this title. Its client
// copy lives in notification-route.ts, which routes it — so a rename that reaches routing and not
// the always-on family is caught here, in the direction that would silence the push.
const SERVER_URGENT = constOf(routeSrc, 'RETURN_ESCALATION_TITLE');

// ① the writers' constants, read out of api.ts by name (constOf is declared above)
const WRITERS = {
  SOS_TITLE: 'api.ts:sendSOS',
  INCIDENT_NOTI_TITLE: 'api.ts:openBookingIncident',
  RUN_STOP_TITLE: 'api.ts:notifyRunStop',
};
const fromApi = [];
for (const [name, where] of Object.entries(WRITERS)) {
  const v = constOf(apiSrc, name);
  t(`${name} is an exported string constant in api.ts (${where})`, typeof v === 'string' && v.length > 0, String(v));
  if (v) fromApi.push(v);
}

// the writers must USE the constant — an inline literal is what renames silently, and `sendSOS`
// wrote a bare 'SOS' until 0189
for (const name of Object.keys(WRITERS)) {
  t(`the writer passes ${name} rather than an inline literal`,
    new RegExp(`title:\\s*${name}\\b`).test(apiSrc));
}

// ② ①  ⇄  ALWAYS_ON_TITLES
t('ALWAYS_ON_TITLES holds exactly the three writer constants, and nothing else',
  JSON.stringify([...ALWAYS_ON_TITLES].sort()) === JSON.stringify([...fromApi].sort()),
  `client=${JSON.stringify(ALWAYS_ON_TITLES)} api=${JSON.stringify(fromApi)}`);

// ③ ②  ⇄  the SQL array in 0189 — both directions, so neither a rename nor an addition can hide
const sqlArray = (() => {
  const m = urgentSrc.match(/_noti_urgent_noti_titles\(\)[\s\S]*?select\s+array\[([^\]]*)\]/);
  if (!m) return null;
  return m[1].split(',').map((x) => x.trim().replace(/^'/, '').replace(/'$/, '')).filter(Boolean);
})();
t(`${urgentFile} declares the urgent-title array and it is parseable`, Array.isArray(sqlArray), String(sqlArray));
t('notification-route.ts declares the server-written escalation title', typeof SERVER_URGENT === 'string' && SERVER_URGENT.length > 0, String(SERVER_URGENT));
// [0193] the family is now CLIENT writers + exactly one SERVER writer. Both directions still hold,
// and the count is still pinned — widening it to get a green is how this guard dies.
const URGENT_FAMILY = SERVER_URGENT ? [...ALWAYS_ON_TITLES, SERVER_URGENT] : [...ALWAYS_ON_TITLES];
if (Array.isArray(sqlArray)) {
  t('every client-written title is in the SQL array (a rename on the client that did not reach the server would SILENTLY make an SOS disableable)',
    ALWAYS_ON_TITLES.every((x) => sqlArray.includes(x)),
    `sql=${JSON.stringify(sqlArray)}`);
  t('the SERVER-written escalation title is in the SQL array (0188 ⓑ-①; without it 예약 알림 off silences 「the dog is unaccounted for」 — codex B5)',
    !!SERVER_URGENT && sqlArray.includes(SERVER_URGENT),
    `sql=${JSON.stringify(sqlArray)} server=${SERVER_URGENT}`);
  t('every SQL title is accounted for on the client (the other direction: an entry nothing writes is a title nobody can rename safely)',
    sqlArray.every((x) => URGENT_FAMILY.includes(x)),
    `sql=${JSON.stringify(sqlArray)} expected=${JSON.stringify(URGENT_FAMILY)}`);
  t('the SQL array holds exactly the expected family and nothing more',
    sqlArray.length === URGENT_FAMILY.length, `${sqlArray.length} vs ${URGENT_FAMILY.length}`);
  t('the server-written title is NOT in ALWAYS_ON_TITLES (that array is what a CLIENT writer sends; nothing in the app writes this one)',
    !!SERVER_URGENT && !ALWAYS_ON_TITLES.includes(SERVER_URGENT));
}

// ④ the mapper must consult the array ABOVE the disableable arms, in EXECUTABLE sql
t('0189 consults the urgent family inside _noti_push_category',
  /when\s+p_title\s*=\s*any\s*\(\s*_noti_urgent_noti_titles\(\)\s*\)\s*then\s*'safety'/.test(migSrc));
t('the urgent arm sits ABOVE the chat/booking arms (below them it would never be reached for a booking row)',
  migSrc.indexOf('_noti_urgent_noti_titles()') > 0
  && migSrc.indexOf('_noti_urgent_noti_titles()') < migSrc.indexOf("then 'chat'"));

// ⑤ RUN_STOP_TITLE exists TWICE on the client (api.ts and notification-route.ts, whose own comment
//    says "change one, change both"). That comment is not a mechanism; this is.
t('notification-route.ts RUN_STOP_TITLE matches api.ts RUN_STOP_TITLE',
  constOf(routeSrc, 'RUN_STOP_TITLE') === constOf(apiSrc, 'RUN_STOP_TITLE'),
  `route=${constOf(routeSrc, 'RUN_STOP_TITLE')} api=${constOf(apiSrc, 'RUN_STOP_TITLE')}`);

// ⑥ the crude check beside the careful one (the standing rule for a new detector): the three
//    strings must be present in the raw, UNSTRIPPED migration too. If the stripped read finds them
//    and the raw read does not, the stripper is eating source; if the raw finds them and the
//    stripped does not, they live only in a comment — which is exactly the false green this
//    file's stripping exists to prevent.
for (const title of URGENT_FAMILY) {
  t(`「${title}」 is present in ${urgentFile} both raw and comment-stripped (a title that survives only in prose is not a rule)`,
    urgentRaw.includes(title) && urgentSrc.includes(title));
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
