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
const {
  PREF_ROWS, PREF_KEYS, PREFS_NOTE, DEFAULT_PREFS, toPrefs,
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

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
