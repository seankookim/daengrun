// chat-window.ts — the message WINDOW and the bubble SHAPE.
//
// Runs against the REAL compiled source (run-chat-window-tests.sh bundles src/lib/chat-window.ts
// with esbuild), not a retyped copy, and beside the real `mergeMessageSnapshot` — the paging door
// and the merge are one mechanism and testing them apart would prove nothing about the pair.
//
// THE TWO DEFECTS, both measured on trunk 6d02769 (2026-09-23):
//
// ① `fetchMessages` read `.order('created_at').limit(100)` ASCENDING, so past a hundred messages
//    the screen showed the FIRST hundred and silently dropped everything after. The newest message
//    — the 「5분 늦어요」 someone is actually waiting for — was the one guaranteed missing, and the
//    screen said nothing about being capped, so a long thread looked like a dead one.
// ② `chat_messages.kind` (0001: `text | photo | location`) was never selected. `mapMsg` inferred
//    photo from `media_path` alone, so a `location` row — or any kind a future migration writes —
//    rendered as an EMPTY bubble.
//
// THE MUTATIONS THAT REDDEN THIS FILE: flip the window back to ascending · return the page without
// reversing it · cursor off the NEWEST held message instead of the oldest · call a full page the
// last one · keep the door visible once the history is exhausted · turn busy into a disabled
// button · let an unknown or empty kind fall through to a bare body · [codex #2] cursor by
// smallest ID instead of by (created_at, id) · drop the id tie-breaker from either read · page on
// `created_at <` alone (the boundary-tie pin at ⑧b reproduces the reviewer's measured hole) ·
// [codex #1] record a read on focus BEFORE the refresh, or after a FAILED one · let a
// realtime-only message be acknowledged (⑩).
const {
  CHAT_PAGE_SIZE, olderCursor, toDisplayOrder, pageIsLast, olderDoorState, olderDoorLabel,
  OLDER_DOOR_LABEL, OLDER_DOOR_BUSY_LABEL, chatBubble,
  CHAT_KIND_LOCATION_LABEL, CHAT_KIND_UNSUPPORTED_LABEL, CHAT_EMPTY_LABEL,
} = require('./chat-window.build.cjs');
const {
  mergeMessageSnapshot, snapshotGap, gapClosedBy, GAP_DOOR_LABEL, compareMessageOrder,
  olderThanCursorFilter,
} = require('./chat-messages.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const msg = (id, iso, over) => Object.assign({ id, createdAt: iso, body: 'm' + id, kind: 'text', mediaUrl: null }, over);
/** A real server instant for message n — `olderCursor` refuses a timestamp it cannot place. */
const at = (n) => new Date(Date.UTC(2026, 8, 23, 10, 0, 0) + n * 1000).toISOString();

// ── ① the window is the NEWEST page ───────────────────────────────────────────────────────────
// The server read is `order('created_at', {ascending:false}).limit(n)` — newest first — and the
// screen draws oldest first, so the page is reversed on arrival.
const serverPage = [msg(9, '2026-09-23T10:09:00Z'), msg(8, '2026-09-23T10:08:00Z'), msg(7, '2026-09-23T10:07:00Z')];
t('a newest-first server page is turned into display order',
  JSON.stringify(toDisplayOrder(serverPage).map((m) => m.id)) === JSON.stringify([7, 8, 9]),
  JSON.stringify(toDisplayOrder(serverPage).map((m) => m.id)));
t('reversing does not mutate the array the caller handed in',
  JSON.stringify(serverPage.map((m) => m.id)) === JSON.stringify([9, 8, 7]));
t('the window is 100 — the same number the server LIMITs by', CHAT_PAGE_SIZE === 100);

// ── ② the cursor is the OLDEST held message, as the (created_at, id) PAIR ─────────────────────
// Cursoring off the newest would page the thread that is already on screen, forever. And since
// [0223 · codex #2] the cursor is the PAIR the server orders by: `created_at` alone left a
// same-instant sibling unreachable, and 「smallest id」 is not 「oldest」 — concurrent inserts need
// not commit in start order.
const held = [msg(7, '2026-09-23T10:07:00Z'), msg(8, '2026-09-23T10:08:00Z'), msg(9, '2026-09-23T10:09:00Z')];
t('the cursor is the (created_at, id) of the oldest held message',
  JSON.stringify(olderCursor(held)) === JSON.stringify({ createdAt: '2026-09-23T10:07:00Z', id: 7 }),
  JSON.stringify(olderCursor(held)));
t('the cursor reads the oldest by ORDER, not by array position (an unsorted array cannot fool it)',
  olderCursor([msg(9, '2026-09-23T10:09:00Z'), msg(7, '2026-09-23T10:07:00Z'), msg(8, '2026-09-23T10:08:00Z')]).id === 7);
t('🔴 [#2] an OLDER instant with a LARGER id is the oldest — the server pages by time first, id second',
  olderCursor([msg(7, '2026-09-23T10:07:00.000500Z'), msg(8, '2026-09-23T10:07:00.000400Z')]).id === 8);
t('🔴 [#2] …and that is decided at the MICROSECOND — Date.parse alone would call those two equal',
  Date.parse('2026-09-23T10:07:00.000500Z') === Date.parse('2026-09-23T10:07:00.000400Z'));
t('[#2] equal instants fall back to the smaller id, which is the server\'s tie rule',
  olderCursor([msg(8, '2026-09-23T10:07:00Z'), msg(7, '2026-09-23T10:07:00Z')]).id === 7);
t('a message that cannot be placed in time is never the cursor — the server could not use it',
  olderCursor([msg(3, ''), msg(4, '2026-09-23T10:07:00Z')]).id === 4
  && olderCursor([msg(3, 'not a date')]) === null);
t('no messages means no cursor (and therefore no request)', olderCursor([]) === null);

// ── ③ when the history has run out ────────────────────────────────────────────────────────────
// A short page is the server saying there was nothing else. A FULL page is never evidence of
// being done — closing the door on one would hide messages that exist.
t('a short page is the last page', pageIsLast(37, 100) === true);
t('an empty page is the last page', pageIsLast(0, 100) === true);
t('a FULL page is never the last page', pageIsLast(100, 100) === false);
t('pageIsLast defaults to the real window size', pageIsLast(99) === true && pageIsLast(100) === false);

// ── ④ the door ────────────────────────────────────────────────────────────────────────────────
t('a full first page opens the door',
  olderDoorState({ hasMessages: true, exhausted: false, busy: false }) === 'ready');
t('an exhausted history REMOVES the door — never a dead control left on screen',
  olderDoorState({ hasMessages: true, exhausted: true, busy: false }) === 'none');
t('an empty thread has no door', olderDoorState({ hasMessages: false, exhausted: false, busy: false }) === 'none');
t('busy is a state of its own, not a removal',
  olderDoorState({ hasMessages: true, exhausted: false, busy: true }) === 'busy');
t('busy outranks exhausted — a request in flight is still in flight',
  olderDoorState({ hasMessages: true, exhausted: true, busy: true }) === 'busy');
t('busy is a LABEL SWAP (chat.tsx\'s send-button grammar), and the two labels differ',
  olderDoorLabel('busy') === OLDER_DOOR_BUSY_LABEL
  && olderDoorLabel('ready') === OLDER_DOOR_LABEL
  && OLDER_DOOR_BUSY_LABEL !== OLDER_DOOR_LABEL);
t('the door says what it opens, in the product\'s own words', OLDER_DOOR_LABEL === '이전 메시지 더 보기');

// ── ⑤ the merge is direction-agnostic ─────────────────────────────────────────────────────────
// `mergeMessageSnapshot` is a union keyed by id and sorted by id, so an OLDER page merging below
// the window has to behave exactly like a newer snapshot merging above it. This is the pin that
// makes paging safe: the screen calls the same merge in both directions.
const window100 = [msg(101, at(101)), msg(102, at(102)), msg(103, at(103))];
const olderPage = [msg(98, at(98)), msg(99, at(99)), msg(100, at(100))];
const afterOlder = mergeMessageSnapshot(window100, olderPage);
t('an older page merges BELOW the window, in id order',
  JSON.stringify(afterOlder.map((m) => m.id)) === JSON.stringify([98, 99, 100, 101, 102, 103]),
  JSON.stringify(afterOlder.map((m) => m.id)));
t('an older page that overlaps the window does not duplicate anything',
  JSON.stringify(mergeMessageSnapshot(window100, [msg(100, at(100)), msg(101, at(101))]).map((m) => m.id))
  === JSON.stringify([100, 101, 102, 103]));
t('the message already held wins the overlap (it is at least as fresh as the page)',
  mergeMessageSnapshot([msg(101, at(101), { body: 'held' })], [msg(101, at(101), { body: 'page' })])[0].body === 'held');
// Two pages loaded back to back, then a poll of the newest window on top: nothing may be lost and
// nothing may double.
const twoPages = mergeMessageSnapshot(afterOlder, [msg(95, at(95)), msg(96, at(96)), msg(97, at(97))]);
const thenPolled = mergeMessageSnapshot(twoPages, [msg(103, at(103)), msg(104, at(104))]);
t('two older pages plus a newer poll produce one unbroken, deduped run',
  JSON.stringify(thenPolled.map((m) => m.id)) === JSON.stringify([95, 96, 97, 98, 99, 100, 101, 102, 103, 104]),
  JSON.stringify(thenPolled.map((m) => m.id)));
t('the cursor after paging points at the NEW oldest, so the next tap goes further back',
  olderCursor(thenPolled).id === 95 && olderCursor(thenPolled).createdAt === at(95));

// ── ⑥ every kind gets a shape, and none of them is nothing ────────────────────────────────────
t('a plain text message is a text bubble',
  JSON.stringify(chatBubble({ kind: 'text', body: '지금 출발해요', mediaUrl: null }))
  === JSON.stringify({ shape: 'text', text: '지금 출발해요' }));
t('a photo message draws its media',
  JSON.stringify(chatBubble({ kind: 'photo', body: '', mediaUrl: 'uid/chat/t/k.jpg' }))
  === JSON.stringify({ shape: 'photo', mediaUrl: 'uid/chat/t/k.jpg' }));
t('media wins over the label — a row carrying a path draws it whatever kind says',
  chatBubble({ kind: 'text', body: '', mediaUrl: 'uid/chat/t/k.jpg' }).shape === 'photo');
t('a row with no kind at all reads as text (the column default), not as unknown',
  chatBubble({ kind: '', body: '안녕하세요', mediaUrl: null }).shape === 'text');

// The defect, stated directly. `location` is in 0001's own column comment and NOTHING writes it
// today (grepped 2026-09-23) — so it gets a label, and deliberately not an invented coordinate:
// `chat_messages` has no payload column to bind one from.
const loc = chatBubble({ kind: 'location', body: '', mediaUrl: null });
t('THE DEFECT: a location message is labelled, never an empty bubble',
  loc.shape === 'labelled' && loc.label === CHAT_KIND_LOCATION_LABEL && CHAT_KIND_LOCATION_LABEL === '위치 메시지',
  JSON.stringify(loc));
t('a location message carrying a body shows the body under its label',
  chatBubble({ kind: 'location', body: '반포한강공원 3번 출구', mediaUrl: null }).text === '반포한강공원 3번 출구');
t('a location message never invents coordinates (there is no payload column to bind)',
  chatBubble({ kind: 'location', body: '', mediaUrl: null }).text === '');

const unknown = chatBubble({ kind: 'voice_note_from_a_future_migration', body: '', mediaUrl: null });
t('THE DEFECT: an unknown kind says it cannot be shown, rather than showing nothing',
  unknown.shape === 'labelled' && unknown.label === CHAT_KIND_UNSUPPORTED_LABEL, JSON.stringify(unknown));
t('an unknown kind still shows whatever text it carried',
  chatBubble({ kind: 'voice_note', body: '무슨 말이든', mediaUrl: null }).text === '무슨 말이든');
t('a photo row with NO media path says so instead of drawing a blank square',
  chatBubble({ kind: 'photo', body: '', mediaUrl: null }).label === CHAT_KIND_UNSUPPORTED_LABEL);
t('a text row with an empty body is labelled too — no bubble is ever blank',
  JSON.stringify(chatBubble({ kind: 'text', body: '', mediaUrl: null }))
  === JSON.stringify({ shape: 'labelled', label: CHAT_EMPTY_LABEL, text: '' }));
// The sweeping version of the same claim: no input produces a bubble with nothing to read.
for (const kind of ['text', 'photo', 'location', '', 'zzz_unknown']) {
  for (const body of ['', '본문']) {
    for (const mediaUrl of [null, '', 'uid/chat/t/k.jpg']) {
      const b = chatBubble({ kind, body, mediaUrl });
      const readable = b.shape === 'photo' ? b.mediaUrl !== '' : (b.shape === 'text' ? b.text !== '' : b.label !== '');
      t(`no empty bubble for kind='${kind}' body='${body}' media='${String(mediaUrl)}'`, readable, JSON.stringify(b));
    }
  }
}

// ── ⑦ the two readers in api.ts actually use all of this ──────────────────────────────────────
//
// 🔴 STATE THE SENTENCE THIS SECTION LICENSES, because it is narrower than the ones above.
// Everything before this point EXECUTES the module. These arms read SOURCE, and they prove only
// that `fetchMessages` / `fetchOlderMessages` / `mapMsg` are SHAPED right — not that they run
// right. They exist because the division is structural, exactly as `check-device-clock.mjs`
// records for the KST class: `app/test/*.cjs` cannot import `api.ts` (it pulls in the supabase
// client, expo native modules and the store), so re-planting `.order('created_at')` ascending
// reddens NOTHING above. The window logic is proven; whether the reader calls it is not — and the
// defect WAS in the reader. Neither half is evidence for the other.
//
// Comments are stripped first and every match is scoped to ONE function's body. Both matter:
// api.ts is ~6,000 lines, so an unscoped match would be satisfied by any other function; and this
// slice's own comments QUOTE the ascending read they replaced, so an un-stripped match would be
// measuring the documentation — the class this repo has met three times.
const path = require('path');
const fs = require('fs');

/** Strip JS comments while KEEPING string and template contents (the patterns live inside them). */
function stripJsComments(src) {
  let out = '', i = 0;
  let inLine = false, inBlock = false, quote = null, tmpl = 0;
  while (i < src.length) {
    const c = src[i], d = src[i + 1];
    if (inLine) { if (c === '\n') { inLine = false; out += c; } i++; continue; }
    if (inBlock) { if (c === '*' && d === '/') { inBlock = false; i += 2; } else { if (c === '\n') out += c; i++; } continue; }
    if (quote) {
      if (c === '\\') { out += c + (d ?? ''); i += 2; continue; }
      if (c === quote) quote = null;
      out += c; i++; continue;
    }
    if (tmpl > 0) {
      // Inside a template literal: only the backtick ends it. `${}` bodies are code, but this
      // codebase puts no comments inside one, and treating them as text is the SAFE direction —
      // it can only ever keep more text, never hide a match.
      if (c === '\\') { out += c + (d ?? ''); i += 2; continue; }
      if (c === '`') { tmpl--; out += c; i++; continue; }
      out += c; i++; continue;
    }
    if (c === '/' && d === '/') { inLine = true; i += 2; continue; }
    if (c === '/' && d === '*') { inBlock = true; i += 2; continue; }
    if (c === '`') { tmpl++; out += c; i++; continue; }
    if (c === '"' || c === "'") { quote = c; out += c; i++; continue; }
    out += c; i++;
  }
  return out;
}

/** The body of one function, brace-counted, skipping braces that live inside strings. */
function bodyOf(src, signature) {
  const start = src.indexOf(signature);
  if (start < 0) return null;
  let i = src.indexOf('{', start);
  if (i < 0) return null;
  const from = i;
  let depth = 0, quote = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === '\\') { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(from, i + 1); }
  }
  return null;
}

// The stripper's own control — a pin that reads a comment as code is the failure mode here.
const STRIP_FIXTURE = "// ascending: false in a comment\nconst a = 'ascending: false';\n/* ascending: false */\nconst b = 1;";
const strippedFixture = stripJsComments(STRIP_FIXTURE);
t('the JS comment stripper removes commented code but KEEPS string contents',
  strippedFixture.split('ascending: false').length - 1 === 1
  && strippedFixture.includes("'ascending: false'"),
  JSON.stringify(strippedFixture));
t('the crude (un-stripped) version sees all three — so the stripper is doing work',
  STRIP_FIXTURE.split('ascending: false').length - 1 === 3);

const API = stripJsComments(fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'api.ts'), 'utf8'));
const newest = bodyOf(API, 'export async function fetchMessages(');
const older = bodyOf(API, 'export async function fetchOlderMessages(');
const mapper = bodyOf(API, 'function mapMsg(');
// A body that failed to extract is NULL, and every `includes` on null would throw rather than
// pass — but say it out loud, because an extractor that silently matched nothing would make each
// arm below vacuous (the NULL-collapse class, in JavaScript's dialect).
t('the source extractor found all three function bodies (control — a broken extractor makes every arm below vacuous)',
  typeof newest === 'string' && typeof older === 'string' && typeof mapper === 'string'
  && newest.length > 0 && older.length > 0 && mapper.length > 0,
  `newest=${newest && newest.length} older=${older && older.length} mapper=${mapper && mapper.length}`);
t('the extractor scopes to ONE body — fetchMessages does not contain fetchOlderMessages\' cursor',
  typeof newest === 'string' && !newest.includes('olderThanCursorFilter('));

t('THE DEFECT: fetchMessages reads the NEWEST page, not the oldest',
  typeof newest === 'string' && newest.includes('ascending: false'));
t('fetchMessages no longer carries the bare ascending order that caused it',
  typeof newest === 'string' && !newest.includes(".order('created_at')"));
t('fetchMessages limits by the window this module owns, not a loose literal',
  typeof newest === 'string' && newest.includes('.limit(CHAT_PAGE_SIZE)'));
t('fetchMessages hands the page back in display order',
  typeof newest === 'string' && newest.includes('toDisplayOrder('));
t('🔴 [#2] fetchOlderMessages pages strictly older on the (created_at, id) PAIR — the filter this module pins',
  typeof older === 'string' && older.includes('.or(olderThanCursorFilter(before))')
  && !older.includes(".lt('created_at'"));
t('🔴 [#2] BOTH reads carry the id tie-breaker after the timestamp, so the window is a suffix of one total order',
  typeof newest === 'string' && typeof older === 'string'
  && newest.includes(".order('created_at', { ascending: false })") && newest.includes(".order('id', { ascending: false })")
  && older.includes(".order('created_at', { ascending: false })") && older.includes(".order('id', { ascending: false })")
  && newest.indexOf(".order('created_at'") < newest.indexOf(".order('id'")
  && older.indexOf(".order('created_at'") < older.indexOf(".order('id'"));
t('fetchOlderMessages reads newest-first and reverses, like its sibling',
  typeof older === 'string' && older.includes('ascending: false') && older.includes('toDisplayOrder('));
t('fetchOlderMessages limits by the same window',
  typeof older === 'string' && older.includes('.limit(CHAT_PAGE_SIZE)'));
t('THE DEFECT: the select finally asks for kind',
  /const CHAT_MSG_COLUMNS = '[^']*\bkind\b[^']*'/.test(API), 'columns line not found or missing kind');
t('the select still asks for everything mapMsg reads',
  /const CHAT_MSG_COLUMNS = '[^']*\bmedia_path\b[^']*'/.test(API)
  && /const CHAT_MSG_COLUMNS = '[^']*\bcreated_at\b[^']*'/.test(API)
  && /const CHAT_MSG_COLUMNS = '[^']*\bsender_id\b[^']*'/.test(API));
t('mapMsg binds kind onto every message',
  typeof mapper === 'string' && /\bkind:/.test(mapper));
t('mapMsg carries the server createdAt through — the paging cursor cannot be a display string',
  typeof mapper === 'string' && /\bcreatedAt:/.test(mapper) && mapper.includes('m.created_at'));

// ── ⑧ the reconnect HOLE — the fill loop's three decisions, composed ──────────────────────────
// [2026-09-25 · codex c3] `chat-messages.ts` owns the detector and `chat-messages.test.ts` pins
// it. What belongs HERE is the COMPOSITION, because the fill is made of this file's functions:
// 「did that page reach back?」 (gapClosedBy) · 「was it the last one?」 (pageIsLast) · 「what is the
// next cursor?」 (olderCursor). The three have to terminate together — a loop that cannot stop is
// as bad as a screen that stops silently with the hole still there.
//
// ⚠ HONEST ABOUT WHAT THIS IS: the driver below is a driver over the REAL functions, not the
//   screen. It proves the three decisions compose; that `chat.tsx` actually calls them is the
//   SOURCE pin at ⑨, and NEITHER IS EVIDENCE FOR THE OTHER.
const thread = [];
for (let id = 1; id <= 400; id += 1) thread.push(msg(id, at(id)));
/** The server's order and its strict-less-than on the PAIR — what `olderThanCursorFilter` asks for. */
const byPair = (a, b) => compareMessageOrder(a, b);
const olderThanPair = (m, c) => byPair(m, c) < 0;
/** The server: every message strictly older than the cursor, newest first, capped at one window,
 *  handed back in display order — exactly `fetchOlderMessages`. */
const olderThan = (cursor) => thread.filter((m) => olderThanPair(m, cursor)).sort(byPair).slice(-CHAT_PAGE_SIZE);

const fillDriver = (held, afterId, cursor, server, maxPages) => {
  let list = held, pages = 0, closed = false;
  while (pages < maxPages) {
    const page = server(cursor);
    pages += 1;
    list = mergeMessageSnapshot(list, page);
    if (gapClosedBy(afterId, page)) { closed = true; break; }
    if (pageIsLast(page.length, CHAT_PAGE_SIZE)) { closed = true; break; }
    const next = olderCursor(page);
    if (next === null) { closed = true; break; }
    cursor = next;
  }
  return { list, pages, closed, cursor };
};

// The screen holds the first 50 of a 400-message thread and reconnects to a window of 301..400.
const heldOld = thread.slice(0, 50);
const reconnect = thread.slice(300);
const hole = snapshotGap(heldOld, reconnect);
t('the reconnect leaves a hole, and it is between two real messages',
  hole !== null && hole.afterId === 50 && hole.beforeId === 301, JSON.stringify(hole));
const merged = mergeMessageSnapshot(heldOld, reconnect);

const three = fillDriver(merged, hole.afterId, olderCursor(reconnect), olderThan, 3);
t('🔴 a bounded fill closes a two-page hole and the thread is UNBROKEN afterwards',
  three.closed === true && three.list.length === 400
  && three.list.every((m, i) => i === 0 || m.id === three.list[i - 1].id + 1),
  `closed=${three.closed} len=${three.list.length} pages=${three.pages}`);
t('…and the same snapshot no longer reports a hole against the filled list',
  snapshotGap(three.list, reconnect) === null);

const two = fillDriver(merged, hole.afterId, olderCursor(reconnect), olderThan, 2);
t('🔴 a bound that runs out STOPS — it does not spin, and it does not pretend to be finished',
  two.closed === false && two.pages === 2);
t('…and the cursor it stops on is further back than the one it started from, so the door resumes '
  + 'rather than repeating a page',
  compareMessageOrder(two.cursor, olderCursor(reconnect)) < 0 && two.list.length > merged.length);
t('…and not one held message was dropped on the way',
  heldOld.every((m) => two.list.some((x) => x.id === m.id)));

// The hole that turns out to be empty — messages deleted between the two ends.
const emptyHole = fillDriver(merged, hole.afterId, olderCursor(reconnect), () => [], 3);
t('a hole the server has nothing for closes on the first page — a door that could only ever '
  + 'return nothing is a dead control',
  emptyHole.closed === true && emptyHole.pages === 1);

// ── ⑧b the BOUNDARY TIE — the reviewer's measured hole, reproduced and closed ─────────────────
// 101 messages sharing one instant. The window holds the newest 100. The old predicate
// (`created_at <` the cursor's instant) returns NOTHING for the 101st, which is then unreachable
// forever; the pair predicate returns exactly it. The control is the OLD predicate, run on the
// same fixture, so 「the hole is real」 and 「the fix closes it」 are two observations, not one.
const TIED_AT = '2026-09-23T11:00:00.123456Z';
const tied = [];
for (let id = 1; id <= 101; id += 1) tied.push(msg(id, TIED_AT));
const pairServer = (c) => tied.filter((m) => olderThanPair(m, c)).sort(byPair).slice(-CHAT_PAGE_SIZE);
const timeOnlyServer = (c) => tied.filter((m) => m.createdAt < c.createdAt).slice(-CHAT_PAGE_SIZE);
const tiedWindow = tied.slice(-CHAT_PAGE_SIZE);
const tiedCursor = olderCursor(tiedWindow);
t('control — the OLD predicate returns NOTHING for the 101st message: the defect reproduces on this fixture',
  tiedCursor !== null && timeOnlyServer(tiedCursor).length === 0);
t('🔴 [#2] the pair predicate reaches the 101st message — every message is reachable',
  tiedCursor !== null && pairServer(tiedCursor).length === 1 && pairServer(tiedCursor)[0].id === 1,
  JSON.stringify(tiedCursor));
t('🔴 [#2] …and the filter the server actually receives is that pair, verbatim, timestamp quoted',
  tiedCursor !== null && olderThanCursorFilter(tiedCursor)
    === `created_at.lt."${TIED_AT}",and(created_at.eq."${TIED_AT}",id.lt.2)`,
  tiedCursor && olderThanCursorFilter(tiedCursor));
t('[#2] the same cursor drives the gap fill: a hole whose far side is the tie closes through it',
  (() => {
    const heldBelow = [msg(0, '2026-09-23T10:59:00Z')];
    const hole = snapshotGap(heldBelow, tiedWindow);
    if (hole === null) return false;
    const out = fillDriver(mergeMessageSnapshot(heldBelow, tiedWindow), hole.afterId, tiedCursor,
      (c) => tied.concat(heldBelow).filter((m) => olderThanPair(m, c)).sort(byPair).slice(-CHAT_PAGE_SIZE), 3);
    return out.closed === true && out.list.length === 102;
  })());

t('the mid-thread door does not borrow the other door\'s word …', GAP_DOOR_LABEL !== OLDER_DOOR_LABEL);
t('… but it DOES share the busy one — two words for one state is how a screen starts lying',
  typeof OLDER_DOOR_BUSY_LABEL === 'string' && OLDER_DOOR_BUSY_LABEL === olderDoorLabel('busy'));

// ── ⑨ the screen, as SOURCE ───────────────────────────────────────────────────────────────────
// `app/test/*.cjs` cannot import a route module, so nothing above says the SCREEN does any of
// this — the same division as `check-a11y-roles` beside the test chain, and the same warning:
// neither is evidence for the other. Comments are stripped first (the stripper's own control is
// at the top of this file), because this slice documents both fixes in comments that name the
// very identifiers matched below.
const CHAT = stripJsComments(fs.readFileSync(path.join(__dirname, '..', 'app', 'chat.tsx'), 'utf8'));
t('chat.tsx is readable at all — an unreadable route module must fail LOUDLY, not be skipped',
  CHAT.length > 2000);

const marks = CHAT.split('shouldMarkRead({').length - 1;
const focusArgs = CHAT.split('focused:').length - 1;
t('🔴 [c1] EVERY shouldMarkRead call site passes the navigation-focus fact',
  marks > 0 && marks === focusArgs, `${marks} calls / ${focusArgs} focused:`);
// [0223 · codex #1] ONE, not three. The focus-regained and app-returned callbacks no longer judge
// (or record) anything: they refresh, and the single acknowledgement effect judges on the commit
// that renders the refreshed snapshot — so every path into a read passes through one call site.
t('[c1 → #1] …and there is exactly ONE of them — the acknowledgement effect every path goes through',
  marks === 1, String(marks));
// ⚠ The count above cannot tell `focused: screenFocused.current` from a hard-wired `focused: true`
// — and neither can tsc, which only demands the field. Stated without reference to any mutation:
// a call site that can RUN while the screen is not focused must read the live ref; only the focus
// callback may pass a constant, because its being called IS the fact. So at most one constant.
t('🔴 [c1] at most one call site passes a constant — the rest read the live ref',
  CHAT.split('focused: screenFocused.current').length - 1 >= marks - 1,
  String(CHAT.split('focused: screenFocused.current').length - 1));
t('[c1] the AppState listener keeps its own early return as well — one gate removed must not '
  + 'open the door on its own',
  CHAT.includes('!screenFocused.current'));

const absorbs = CHAT.split('absorbSnapshot(').length - 1;
const reads = CHAT.split('fetchMessages(').length - 1;
t('🔴 [c3] every newest-page read but the first goes through the gap-aware merge',
  absorbs > 0 && absorbs === reads - 1, `${absorbs} absorb / ${reads} fetchMessages`);
// [codex wave 4 · c1] These two pins MOVED with the fix. They used to assert `snapshotGap(` at the
// merge and a `setGapDoor({ afterId: hole.afterId, cursor })` before the fill — the detector that
// anchored on ANY held message, realtime-only ones included, which is the defect c1 measured. The
// properties are unchanged and re-stated against the coverage mechanism: every snapshot's stretch
// joins the fetched coverage at the merge, and the door is derived from coverage BEFORE the fill
// runs. The behaviour (the reviewer's reconnect sequence) is pinned by chat-coverage.test.cjs.
const absorbBody = bodyOf(CHAT, 'const absorbSnapshot = useCallback(');
t('[c3 → c1] the screen reads the hole off FETCHED COVERAGE at the snapshot merge — not off what it holds',
  typeof absorbBody === 'string'
  && absorbBody.includes('noteCoverage(windowSpan(snapshot,')
  && !CHAT.includes('snapshotGap(') && CHAT.includes('coverageHole(coverage.current)'),
  String(absorbBody));
t('🔴 [c3 → c1] the door is DERIVED before the fill is attempted, so a fill cut short by a thread '
  + 'change cannot lose the only record of the hole',
  typeof absorbBody === 'string'
  && absorbBody.indexOf('noteCoverage(') >= 0
  && absorbBody.indexOf('noteCoverage(') < absorbBody.indexOf('runFill(opCtx)')
  && /setGapDoor\(\(cur\) => \{\s*if \(hole === null\) return null;/.test(CHAT));
t('🔴 [c1] the realtime handler touches neither coverage nor the ids a fetch vouched for',
  (() => {
    const i = CHAT.indexOf('unsub = subscribeMessages(');
    const j = CHAT.indexOf('}, (s) => {', i);
    const h = i > 0 && j > i ? CHAT.slice(i, j) : null;
    return h !== null && !h.includes('noteCoverage(') && !h.includes('coverage.current') && !h.includes('noteFetched(');
  })());
t('[c1] every successful older read — the fill AND the older door — joins the coverage',
  (() => {
    const fill = bodyOf(CHAT, 'const fillGap = useCallback(');
    const older = bodyOf(CHAT, 'const loadOlder = async () =>');
    return typeof fill === 'string' && typeof older === 'string'
      && fill.includes('noteCoverage(olderPageSpan(page, hole.cursor,')
      && older.includes('noteCoverage(olderPageSpan(older, cursor,');
  })());
t('[c1] coverage is reset with the thread — in BOTH reset lists (the load effect and retryLoad)',
  (CHAT.match(/coverage\.current = \[\];/g) || []).length === 2);
// [codex wave 4 review · A3] The OPEN path seeds the coverage. Without it the first stretch is
// missing, every later snapshot is the LOWEST stretch, and a poll that jumped past the window
// (open on 51–150, poll returns 400–499) has no hole and a ceiling of 499 — the c1 defect back,
// with 151–399 never fetched. chat-coverage's driver seeds in its own `open`, so only this pin can
// see the line in chat.tsx. Anchored between the first read and the first merge of that read.
t('🔴 [c1] the open path seeds coverage from the FIRST window, before that window is drawn',
  (() => {
    const read = CHAT.indexOf('const history = await fetchMessages(c.threadId);');
    const seed = CHAT.indexOf('coverage.current = addCoverage([], windowSpan(history, pageIsLast(history.length, CHAT_PAGE_SIZE)));');
    const draw = CHAT.indexOf('setMsgs((current) => mergeMessageSnapshot(current, history));');
    return read > 0 && seed > read && draw > seed;
  })());
// [codex wave 4 review · low] The automatic fill is bounded per HOLE, not per poll: absorbSnapshot
// asks `autoFillDecision` (chat-coverage.test.cjs ④ executes it) and starts a fill ONLY on its
// answer. An unconditional `runFill(opCtx)` there re-arms the fill every tick.
t('🔴 [gap] the snapshot starts the automatic fill only on autoFillDecision\'s answer — never unconditionally',
  typeof absorbBody === 'string'
  && /const auto = autoFillDecision\(coverageHole\(coverage\.current\), autoFilledAfter\.current\);\s*autoFilledAfter\.current = auto\.remember;\s*if \(auto\.fill\) runFill\(opCtx\);/.test(absorbBody)
  && (absorbBody.match(/runFill\(/g) || []).length === 1,
  String(absorbBody));
t('[gap] the auto-fill memory is a thread fact — reset in BOTH reset lists',
  (CHAT.match(/autoFilledAfter\.current = null;/g) || []).length === 2);
t('[c3] the mid-thread door carries a role and the shared busy word (busy is a LABEL SWAP)',
  /accessibilityLabel=\{gapBusy \? OLDER_DOOR_BUSY_LABEL : GAP_DOOR_LABEL\}/.test(CHAT)
  && /accessibilityState=\{\{ busy: gapBusy \}\}/.test(CHAT));
t('[c3] a closed hole REMOVES the door rather than leaving a control that fetches nothing',
  CHAT.includes('setGapDoor(null)'));
t('[c3] the fill is bounded by a named constant, not by a loop that decides for itself',
  /const GAP_FILL_MAX_PAGES = \d+;/.test(CHAT) && CHAT.includes('i < GAP_FILL_MAX_PAGES'));

// ── ⑩ [0223 · codex #1] refresh FIRST, acknowledge only what a fetch returned and the screen drew ──
// The defect: the focus and app-return callbacks recorded a read IMMEDIATELY, on the previously
// ready screen, before the poll refetched — so messages that arrived during a suspension became
// 「읽음」 to the peer without ever being drawn, and stayed so when the refresh then failed.
// Source pins, because no test can drive the route module; `chat-read.test.cjs` pins the
// judgment (which message, and when) and neither is evidence for the other.
const focusStart = CHAT.indexOf('useFocusEffect(useCallback(() => {');
const focusEnd = CHAT.indexOf('}, [refreshThenRead]));');
const appStart = CHAT.indexOf("AppState.addEventListener('change'");
const appEnd = CHAT.indexOf('return () => sub.remove();');
const refreshStart = CHAT.indexOf('const refreshThenRead = useCallback(');
const refreshEnd = CHAT.indexOf('}, [absorbSnapshot]);', refreshStart);
const ackStart = CHAT.indexOf('if (!shouldMarkRead({');
const ackEnd = CHAT.indexOf('}, [ctx, state, msgs, gapDoor, ackTick, recordRead]);');
const focusBlock = CHAT.slice(focusStart, focusEnd);
const appBlock = CHAT.slice(appStart, appEnd);
const refreshBody = CHAT.slice(refreshStart, refreshEnd);
const ackBody = CHAT.slice(CHAT.lastIndexOf('useEffect(() => {', ackStart), ackEnd);
t('control — the four blocks were found (an extractor that matched nothing would make every arm below vacuous)',
  focusStart > 0 && focusEnd > focusStart && appStart > 0 && appEnd > appStart
  && refreshStart > 0 && refreshEnd > refreshStart && ackStart > 0 && ackEnd > ackStart && ackBody.length > 0,
  `focus=${focusStart}..${focusEnd} app=${appStart}..${appEnd} refresh=${refreshStart}..${refreshEnd} ack=${ackStart}..${ackEnd}`);
t('🔴 [#1] neither the focus callback nor the app-return listener records a read — both only refresh',
  focusBlock.includes('refreshThenRead(') && !focusBlock.includes('recordRead(') && !focusBlock.includes('markChatRead(')
  && appBlock.includes('refreshThenRead(') && !appBlock.includes('recordRead(') && !appBlock.includes('markChatRead('));
const catchStart = refreshBody.indexOf('catch (e) {');
const catchEnd = refreshBody.indexOf('if (!mounted.current || ctxRef.current !== opCtx) return;');
const catchBlock = refreshBody.slice(catchStart, catchEnd);
t('🔴 [#1] the refresh AWAITS the fetch before it asks for an acknowledgement, and a FAILED fetch returns having asked for nothing',
  catchStart > 0 && catchEnd > catchStart
  && refreshBody.indexOf('await fetchMessages(') >= 0
  && refreshBody.indexOf('await fetchMessages(') < refreshBody.indexOf('focusAckDue.current = true')
  && refreshBody.indexOf('absorbSnapshot(opCtx, next)') < refreshBody.indexOf('focusAckDue.current = true')
  && catchBlock.includes('return;') && catchBlock.includes('setPollErr(true)')
  && !catchBlock.includes('focusAckDue') && !catchBlock.includes('setAckTick') && !catchBlock.includes('recordRead('),
  JSON.stringify(catchBlock));
t('🔴 [#1] the refresh itself records nothing — the record happens in the effect, on the commit that renders it',
  !refreshBody.includes('recordRead(') && !refreshBody.includes('markChatRead(') && !refreshBody.includes('shouldMarkRead('));
t('[#1] exactly one record in the file, inside the acknowledgement effect, and it names a message',
  (CHAT.match(/recordRead\(/g) || []).length === 1 && (CHAT.match(/markChatRead\(/g) || []).length === 1
  && ackBody.includes('recordRead(ctx.threadId, target);'));
// [codex wave 4 · c1] MOVED: the ceiling used to be `gapDoor.afterId`, i.e. only as good as the
// detector that opened the door — and that detector anchored on realtime-only messages. The target
// is now bounded by the top of VERIFIED FETCHED COVERAGE, and with nothing vouched for there is no
// target at all.
t('🔴 [#1 → c1] the target is the newest peer message a FETCH returned, under the top of fetched COVERAGE',
  /newestPeerMessageId\(msgs, \{ ceiling, fetchedIds: fetchedIds\.current \}\)/.test(ackBody)
  && ackBody.includes('const ceiling = coverageCeiling(coverage.current);')
  && /const target = ceiling === null\s*\?\s*null/.test(ackBody)
  && !ackBody.includes('gapDoor.afterId'));
t('🔴 [#1] ids become acknowledgeable only through a fetch: the snapshot merge notes them, the realtime handler does not',
  bodyOf(CHAT, 'const absorbSnapshot = useCallback(') !== null
  && bodyOf(CHAT, 'const absorbSnapshot = useCallback(').includes('noteFetched(snapshot)')
  && (() => {
    const i = CHAT.indexOf('unsub = subscribeMessages(');
    const j = CHAT.indexOf('}, (s) => {', i);
    return i > 0 && j > i && !CHAT.slice(i, j).includes('noteFetched(') && !CHAT.slice(i, j).includes('setAckTick(');
  })());
// [codex wave 4 · c2] REVERSED. This pin asserted the skew-window fallback to 0212's now()-writer
// was ASKED FOR under two conditions; the fallback itself is gone (a delayed skew error let it write
// an unbounded now(), measured by the reviewer), so there is nothing left to ask for. The property
// now is that the screen hands the writer a MESSAGE and nothing else; chat-mark-read.test.cjs
// executes the wrapper and pins that the cursor-less writer is never called.
t('🔴 [c2] the screen asks for no now()-fallback — the record takes the message and nothing else',
  !CHAT.includes('legacyFallback') && !ackBody.includes('newestHeld')
  && /markChatRead\(threadId, upToMessageId\)/.test(CHAT));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
