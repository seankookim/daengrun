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
  PREF_ROWS, PREF_KEYS, PREFS_NOTE, DEFAULT_PREFS, toPrefs, ALWAYS_ON_TITLES, visiblePrefRows,
} = require('./notification-prefs.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the key set IS a server contract ───────────────────────────────────────────────────────────
// `notification_prefs` (0187 §A + 0210 §A) has exactly these five boolean columns, and
// `set_notification_prefs` takes `p_booking / p_chat / p_community / p_reward / p_ops`. A sixth key
// here is a switch that saves nothing.
const EXPECTED = ['booking', 'chat', 'community', 'reward', 'ops'];
t('the five keys are exactly the server columns',
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

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [0210] THE OPS ROW IS OPERATOR-ONLY, AND THE SAFETY ROW STOPPED CLAIMING IT
// ══════════════════════════════════════════════════════════════════════════════════════════════
// Until 0210 the mapper opened `p_kind in ('safety','system') then 'safety'`, so every ops
// escalation — including 「굿즈 수령 신청 — 확인 필요」, a goods-shipping desk ping — was
// undisableable, and THIS SCREEN explained that with 「개와 사람이 걸린 일이라서예요」. The two
// arms below are the honesty half of the fix: the ops row exists, and the safety row no longer
// says the words that made the old state look justified.
//
// And the visibility arm is the no-dead-buttons half: a `system` push can only reach somebody on
// `ops_recipients` (0084 §E), so for everybody else this would be a switch for a notification they
// can never receive. `ops_me()` (0198 §A) is the server's own answer and UNKNOWN hides the row —
// which is safe in both directions, because a row that is not drawn cannot write its column.
const opsRow = PREF_ROWS.find((r) => r.key === 'ops');
t('there is an ops row and it is operator-only', !!opsRow && opsRow.opsOnly === true,
  JSON.stringify(opsRow));
t('the ops row is a REAL toggle (a key, no alwaysOn) — the point of the slice is that it can be turned off',
  !!opsRow && opsRow.alwaysOn !== true && typeof opsRow.key === 'string');
t('exactly one row is opsOnly (a second one would be an unreviewed operator surface)',
  PREF_ROWS.filter((r) => r.opsOnly === true).length === 1);
t('the always-on row is NOT opsOnly (safety must be visible to everyone)',
  always.length === 1 && always[0].opsOnly !== true);
t('🔴 the safety row no longer claims the ops escalations — that sentence is what made an undisableable goods ping look like a safety matter',
  always.length === 1 && !always[0].desc.includes('운영'), always[0].desc);
t('the ops row names what it actually covers (the four shipped system titles), not a category word',
  !!opsRow && opsRow.desc.includes('지급 대기') && opsRow.desc.includes('굿즈'), opsRow && opsRow.desc);
t('🔴 the ops row says what STAYS — turning it off changes the phone and not the console',
  !!opsRow && opsRow.desc.includes('콘솔'), opsRow && opsRow.desc);

t('visiblePrefRows(true) is every row — an operator sees the ops switch',
  visiblePrefRows(true).length === PREF_ROWS.length
  && visiblePrefRows(true).some((r) => r.key === 'ops'));
t('visiblePrefRows(false) drops the ops row and NOTHING else',
  visiblePrefRows(false).length === PREF_ROWS.length - 1
  && !visiblePrefRows(false).some((r) => r.key === 'ops'),
  JSON.stringify(visiblePrefRows(false).map((r) => r.key)));
for (const unknown of [null, undefined]) {
  t(`visiblePrefRows(${String(unknown)}) hides the ops row — UNKNOWN is not an operator, and a row that is not drawn cannot write its column`,
    !visiblePrefRows(unknown).some((r) => r.key === 'ops'));
}
t('visiblePrefRows never invents a row',
  [true, false, null, undefined].every((v) => visiblePrefRows(v).every((r) => PREF_ROWS.includes(r))));
t('the always-on safety row survives every visibility answer (it is not operator-gated)',
  [true, false, null, undefined].every((v) => visiblePrefRows(v).some((r) => r.alwaysOn === true)));

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
// [0210] The deployment order is client-then-migration, so an ABSENT `ops` key is a pre-0210
// SERVER and not an operator who switched it off. `?? false` here would silence an operator's ops
// pushes for the whole window between the two landings — the same direction the server refuses to
// take, and for the same reason.
t('toPrefs reads an explicit ops:false through',
  toPrefs({ ops: false }).ops === false && toPrefs({ ops: false }).booking === true);
t('🔴 an ABSENT ops key is ON, not OFF — a pre-0210 server must not read as "the operator turned it off"',
  toPrefs({ booking: false }).ops === true && toPrefs({}).ops === true);

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
// 🔴 [0210] THESE TWO ARMS USED TO READ `migSrc` — migration 0189 BY NAME — and that was the same
// staleness the block above fixed for `_noti_urgent_noti_titles`, one function over. 0210 §B
// re-declares `_noti_push_category` (it moves `system` to its own category and the fallthrough to
// `booking`), so 0189's file stopped deciding anything the moment 0210 landed, and a gate pinned
// to it would have kept comparing a superseded declaration: green, confident, and measuring
// nothing. Same rule as before — find every migration that declares the function, take the
// highest-numbered one, and say which one it was.
const mapperDecls = fs.readdirSync(migDir)
  .filter((f) => /^\d{4}_.*\.sql$/.test(f))
  .filter((f) => /create or replace function _noti_push_category/.test(
    stripSql(fs.readFileSync(path.join(migDir, f), 'utf8'))))
  .sort();
t('at least one migration declares the category mapper (absence must fail LOUDLY)',
  mapperDecls.length > 0, JSON.stringify(mapperDecls));
const mapperFile = mapperDecls[mapperDecls.length - 1];
const mapperSrc = mapperFile ? stripSql(fs.readFileSync(path.join(migDir, mapperFile), 'utf8')) : '';
console.log(`  (category mapper read from ${mapperFile}; declared in ${JSON.stringify(mapperDecls)})`);

t(`${mapperFile} consults the urgent family inside _noti_push_category`,
  /when\s+p_title\s*=\s*any\s*\(\s*_noti_urgent_noti_titles\(\)\s*\)\s*then\s*'safety'/.test(mapperSrc));
t('the urgent arm sits ABOVE the chat/booking arms (below them it would never be reached for a booking row)',
  mapperSrc.indexOf('_noti_urgent_noti_titles()') > 0
  && mapperSrc.indexOf('_noti_urgent_noti_titles()') < mapperSrc.indexOf("then 'chat'"));

// ④b [0210] THE FALLTHROUGH IS A DISABLEABLE CATEGORY. `else 'safety'` made a kind nobody has
// thought about yet undisableable — the highest privilege in the system, handed out by default to
// whatever arrives next (`shop` is the member with zero writers, and it is the one that would).
// Read in EXECUTABLE sql, off the latest declaration, because a comment explaining the change
// satisfies any check for the change (the standing comment-quoting law; this migration's own
// header says the words `else 'safety'` three times).
const elseArm = /\belse\s+'([a-z]+)'\s*\n?\s*end/.exec(mapperSrc);
t('the mapper has a parseable fallthrough arm', !!elseArm, String(elseArm && elseArm[0]));
t("🔴 the unknown-kind fallthrough is NOT 'safety' — an uncategorised push must be sent by default AND stoppable by the person receiving it",
  !!elseArm && elseArm[1] !== 'safety', elseArm ? elseArm[1] : 'none');
t("the fallthrough is a real preference column (it must be a key this screen can offer)",
  !!elseArm && PREF_KEYS.includes(elseArm[1]), elseArm ? elseArm[1] : 'none');

// ④c [0210] AND `system` MUST HAVE ITS OWN ARM, mapping to a column this screen renders. Without
// one it falls through to ④b's default and an ops escalation is silenced by the 예약·러닝 switch.
const systemArm = /when\s+p_kind\s*=\s*'system'\s*then\s*'([a-z]+)'/.exec(mapperSrc);
t('the mapper has an explicit `system` arm', !!systemArm, String(systemArm && systemArm[0]));
t('the `system` arm maps to a column PREF_KEYS offers (a category with no column would be silently always-on again)',
  !!systemArm && PREF_KEYS.includes(systemArm[1]), systemArm ? systemArm[1] : 'none');
t('the ops ROW binds the same key the `system` arm answers — a row whose key the server never produces is a switch that saves nothing',
  !!systemArm && !!opsRow && opsRow.key === systemArm[1],
  `row=${opsRow && opsRow.key} sql=${systemArm && systemArm[1]}`);
t('the urgent family is consulted ABOVE the `system` arm (below it, a system row carrying an urgent title would become disableable)',
  !!systemArm && mapperSrc.indexOf('_noti_urgent_noti_titles()') < mapperSrc.indexOf(systemArm[0]));

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
