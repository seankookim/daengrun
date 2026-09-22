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
// button · let an unknown or empty kind fall through to a bare body.
const {
  CHAT_PAGE_SIZE, olderCursor, toDisplayOrder, pageIsLast, olderDoorState, olderDoorLabel,
  OLDER_DOOR_LABEL, OLDER_DOOR_BUSY_LABEL, chatBubble,
  CHAT_KIND_LOCATION_LABEL, CHAT_KIND_UNSUPPORTED_LABEL, CHAT_EMPTY_LABEL,
} = require('./chat-window.build.cjs');
const { mergeMessageSnapshot } = require('./chat-messages.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const msg = (id, iso, over) => Object.assign({ id, createdAt: iso, body: 'm' + id, kind: 'text', mediaUrl: null }, over);

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

// ── ② the cursor is the OLDEST held message ───────────────────────────────────────────────────
// Cursoring off the newest would page the thread that is already on screen, forever.
const held = [msg(7, '2026-09-23T10:07:00Z'), msg(8, '2026-09-23T10:08:00Z'), msg(9, '2026-09-23T10:09:00Z')];
t('the cursor is the created_at of the oldest held message',
  olderCursor(held) === '2026-09-23T10:07:00Z', String(olderCursor(held)));
t('the cursor reads the oldest by ID, not by array position (an unsorted array cannot fool it)',
  olderCursor([msg(9, 'C'), msg(7, 'A'), msg(8, 'B')]) === 'A');
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
const window100 = [msg(101, 'w1'), msg(102, 'w2'), msg(103, 'w3')];
const olderPage = [msg(98, 'o1'), msg(99, 'o2'), msg(100, 'o3')];
const afterOlder = mergeMessageSnapshot(window100, olderPage);
t('an older page merges BELOW the window, in id order',
  JSON.stringify(afterOlder.map((m) => m.id)) === JSON.stringify([98, 99, 100, 101, 102, 103]),
  JSON.stringify(afterOlder.map((m) => m.id)));
t('an older page that overlaps the window does not duplicate anything',
  JSON.stringify(mergeMessageSnapshot(window100, [msg(100, 'o3'), msg(101, 'w1')]).map((m) => m.id))
  === JSON.stringify([100, 101, 102, 103]));
t('the message already held wins the overlap (it is at least as fresh as the page)',
  mergeMessageSnapshot([msg(101, 'w1', { body: 'held' })], [msg(101, 'w1', { body: 'page' })])[0].body === 'held');
// Two pages loaded back to back, then a poll of the newest window on top: nothing may be lost and
// nothing may double.
const twoPages = mergeMessageSnapshot(afterOlder, [msg(95, 'p1'), msg(96, 'p2'), msg(97, 'p3')]);
const thenPolled = mergeMessageSnapshot(twoPages, [msg(103, 'w3'), msg(104, 'w4')]);
t('two older pages plus a newer poll produce one unbroken, deduped run',
  JSON.stringify(thenPolled.map((m) => m.id)) === JSON.stringify([95, 96, 97, 98, 99, 100, 101, 102, 103, 104]),
  JSON.stringify(thenPolled.map((m) => m.id)));
t('the cursor after paging points at the NEW oldest, so the next tap goes further back',
  olderCursor(thenPolled) === 'p1');

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
  typeof newest === 'string' && !newest.includes(".lt('created_at'"));

t('THE DEFECT: fetchMessages reads the NEWEST page, not the oldest',
  typeof newest === 'string' && newest.includes('ascending: false'));
t('fetchMessages no longer carries the bare ascending order that caused it',
  typeof newest === 'string' && !newest.includes(".order('created_at')"));
t('fetchMessages limits by the window this module owns, not a loose literal',
  typeof newest === 'string' && newest.includes('.limit(CHAT_PAGE_SIZE)'));
t('fetchMessages hands the page back in display order',
  typeof newest === 'string' && newest.includes('toDisplayOrder('));
t('fetchOlderMessages pages strictly older, on the server\'s created_at',
  typeof older === 'string' && older.includes(".lt('created_at', beforeCreatedAt)"));
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

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
