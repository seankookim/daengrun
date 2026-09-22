// edge-errors.ts — tests run against the REAL compiled source (see run-edge-errors-tests.sh),
// not a retyped copy, and against the REAL handler source for the drift arms.
//
// What this file is FOR. A `Record<string,string>` of Korean sentences can be pinned pointlessly
// (「the map has 14 keys」 proves nothing). The property that matters is a DRIFT property:
//
//   every English token `create-booking-hold/handler.ts` can put on the wire is mapped here.
//
// So the expected token set is not typed into this file — it is READ OUT OF THE HANDLER SOURCE,
// comment-stripped, every run. A new `throw new HttpError(400, "some_new_token")` there reddens
// this file the moment it lands, before anyone can ship it into a Korean Alert.
//
// ⚠ COMMENT-STRIPPED, and that is load-bearing (CLAUDE.md's standing law): this handler documents
// its own tokens in prose — `:88` literally contains the words `runner_id` and `:97`'s reasoning
// quotes the field. A matcher that reads comments measures the documentation, and the better the
// documentation the more surely it passes.
//
// ⚠ THE EXTRACTOR IS THE DANGEROUS PART — a stripper that over-blanks returns ZERO tokens and
// every mapping arm then passes VACUOUSLY: a gate with a false negative, which is worse than no
// gate. So the census arms come FIRST and are not optional: the extractor must find a known floor
// of literals AND must find Korean ones too (proving the Hangul filter is what excludes them, not
// a stripper that ate the file).
//
// The mutations that redden it: add an English `new HttpError` to create-booking-hold without a
// map entry · delete any key from BOOKING_HOLD_TOKENS / PAY_TOKENS / DROP_TOKENS · map a token
// to an English sentence · drop the Hangul passthrough · drop `raw` from the fold · give a token
// a Korean sentence that blames the owner for `bad_body` · trim the trailing space off
// `'unknown addon '`.
const fs = require('fs');
const path = require('path');
const {
  BOOKING_HOLD_TOKENS, PAY_TOKENS, DROP_TOKENS,
  APP_BUG_KO, SESSION_EXPIRED_KO,
  bookingHoldError, payError, dropError,
} = require('./edge-errors.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const hasHangul = (s) => /[가-힣]/.test(s);

// ── the extractor ──────────────────────────────────────────────────────────────────────────────
// A character walk rather than a regex, because a regex comment-stripper cannot tell `//` inside a
// string from a comment, and this handler builds URLs and log lines. Strings/templates are kept
// (they hold the tokens); comments are replaced by spaces so line/column shape survives.
function stripComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') { out += ' '; i++; }
      continue;
    }
    if (c === '/' && d === '*') {
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) { out += src[i] === '\n' ? '\n' : ' '; i++; }
      out += '  '; i += 2;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      const q = c; out += c; i++;
      while (i < n) {
        if (src[i] === '\\') { out += src[i] + (src[i + 1] ?? ''); i += 2; continue; }
        out += src[i];
        if (src[i] === q) { i++; break; }
        i++;
      }
      continue;
    }
    out += c; i++;
  }
  return out;
}

/** Every `new HttpError(<status>, <literal>)` message in a handler, as the server would send it.
 *  A template literal reduces to its STATIC PREFIX (`unknown addon ${k}` → `unknown addon `) —
 *  which is exactly the substring `matchToken` needs, trailing space included. A second argument
 *  that is not a literal (`txErr.message`, `mapped.message`, a Korean const by name) yields
 *  nothing: it cannot be read from source, and the arms below say so by name where it matters. */
function httpErrorLiterals(file) {
  const raw = fs.readFileSync(file, 'utf8');   // throws loudly if the path ever moves — a missing
  const src = stripComments(raw);              // file must never read as 「zero tokens」
  const out = [];
  const re = /new HttpError\(\s*\d+\s*,\s*(["'`])([\s\S]*?)\1/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const body = m[2];
    const cut = body.indexOf('${');
    out.push(cut === -1 ? body : body.slice(0, cut));
  }
  return out;
}

// ⚠ `EDGE_FN_DIR` exists so a mutation can be planted into a COPY of the handlers instead of into
// the live files — the same escape hatch `check-definer-acl.mjs` carries as `MIGRATIONS_DIR`, and
// for the same measured reason (CLAUDE.md: editing a live file to test a hypothetical is a
// read-modify-write with a multi-second window another agent can land inside). It is never set by
// `npm test`.
const FN = process.env.EDGE_FN_DIR || path.join(__dirname, '..', '..', 'supabase', 'functions');
const HOLD = path.join(FN, 'create-booking-hold', 'handler.ts');
const INTENT = path.join(FN, 'create-payment-intent', 'handler.ts');
const CONFIRM = path.join(FN, 'confirm-payment', 'handler.ts');
const DROP = path.join(FN, 'open-drop', 'handler.ts');

// ── ① the census: the extractor works at all ───────────────────────────────────────────────────
// These arms exist so that no arm below can pass by finding nothing. Run them first and look at
// them (the control-first law) — a battery whose control is silent measures nothing.
const holdAll = httpErrorLiterals(HOLD);
const holdEn = [...new Set(holdAll.filter((s) => !hasHangul(s)))].sort();
const holdKo = holdAll.filter(hasHangul);

t('the extractor finds create-booking-hold at all (≥18 HttpError literals)',
  holdAll.length >= 18, 'found ' + holdAll.length);
t('the extractor finds KOREAN literals too — so the Hangul filter is what excludes them, not a stripper that ate the file',
  holdKo.length >= 5, 'found ' + holdKo.length);
t('the comment-stripper is not blanking code: the handler source still contains its guarded parse',
  stripComments(fs.readFileSync(HOLD, 'utf8')).includes('"bad_body"'));
t('the comment-stripper DOES blank comments: the prose word 「idempotency」 survives raw and dies stripped',
  fs.readFileSync(HOLD, 'utf8').includes('idempotency')
  && !stripComments(fs.readFileSync(HOLD, 'utf8')).includes('idempotency'));

// ── ② THE DRIFT PIN ────────────────────────────────────────────────────────────────────────────
// The one arm this file exists for. Not 「the map has the twelve I typed」 — 「the map covers what
// the handler can say」, recomputed from the handler every run.
const unmapped = holdEn.filter((tok) => !(tok in BOOKING_HOLD_TOKENS));
t('every English HttpError literal in create-booking-hold is mapped to Korean',
  unmapped.length === 0, 'unmapped: ' + JSON.stringify(unmapped));

// The census of the twelve, written down so a SHRINKING extractor (or a deleted throw) is visible
// rather than silently satisfying the arm above. A new token is meant to redden this line — that
// is the prompt to write its Korean, not a reason to relax the arm.
const TWELVE = [
  'bad client_request_id',
  'bad scheduled_at',
  'bad_body',
  'candidate_ack_required',
  'forbidden',
  'km out of range',
  'missing fields',
  'runner_id_not_accepted_here',
  'unauthorized',
  'unknown addon ',
  'unknown route',
  'unknown selection_origin ',
].sort();
t('the handler still says exactly the twelve English tokens this map was written against',
  JSON.stringify(holdEn) === JSON.stringify(TWELVE), JSON.stringify(holdEn));

// `:408` re-throws `txErr.message`, so these two reach the wire while being INVISIBLE to any
// source extractor — the transaction's underscore-shaped twins. Pinned by name for that reason.
t('the two transaction pass-through tokens (:408, unreadable from source) are mapped by hand',
  'missing_fields' in BOOKING_HOLD_TOKENS && 'km_out_of_range' in BOOKING_HOLD_TOKENS);
t('the handler really does pass those two through (the switch cases still exist)',
  (() => {
    const s = stripComments(fs.readFileSync(HOLD, 'utf8'));
    return s.includes('case "missing_fields"') && s.includes('case "km_out_of_range"')
      && s.includes('new HttpError(400, txErr.message)');
  })());

// Same sweep, the other two doors.
const payEn = [...new Set([...httpErrorLiterals(INTENT), ...httpErrorLiterals(CONFIRM)].filter((s) => !hasHangul(s)))].sort();
t('the pay-path extractor finds something (≥5 English tokens across the two handlers)',
  payEn.length >= 5, 'found ' + JSON.stringify(payEn));
t('every English HttpError literal on the pay path is mapped',
  payEn.every((tok) => tok in PAY_TOKENS), JSON.stringify(payEn.filter((k) => !(k in PAY_TOKENS))));

const dropEn = [...new Set(httpErrorLiterals(DROP).filter((s) => !hasHangul(s)))].sort();
t('open-drop\'s envelope is the whole English surface and it is mapped',
  dropEn.length === 2 && dropEn.every((tok) => tok in DROP_TOKENS), JSON.stringify(dropEn));
t('open-drop maps `unauthorized` too — it comes from ctx.ts\'s caller(), not from this handler',
  DROP_TOKENS.unauthorized === SESSION_EXPIRED_KO);

// ── ③ the collision arm: a token must not hijack a Korean sentence ─────────────────────────────
// `matchToken` runs BEFORE the Hangul passthrough, so a token that occurs inside one of the
// handlers' own Korean sentences would replace copy the server deliberately wrote.
const allKo = [
  ...holdKo,
  ...httpErrorLiterals(INTENT).filter(hasHangul),
  ...httpErrorLiterals(CONFIRM).filter(hasHangul),
];
const collisions = [];
for (const ko of allKo) {
  for (const tok of [...Object.keys(BOOKING_HOLD_TOKENS), ...Object.keys(PAY_TOKENS)]) {
    if (ko.includes(tok)) collisions.push(tok + ' ⊂ ' + ko);
  }
}
t('no token is a substring of a handler\'s own Korean sentence (matching runs before the passthrough)',
  collisions.length === 0, JSON.stringify(collisions));

// ── ④ every mapped sentence is Korean, and none of them blames the owner for our bug ───────────
const everyMap = { BOOKING_HOLD_TOKENS, PAY_TOKENS, DROP_TOKENS };
for (const [name, map] of Object.entries(everyMap)) {
  t(name + ': every value is Hangul (an English token replaced by an English sentence is the same defect)',
    Object.values(map).every(hasHangul),
    JSON.stringify(Object.entries(map).filter(([, v]) => !hasHangul(v))));
  t(name + ': no key is empty and no value is empty',
    Object.entries(map).every(([k, v]) => k.length > 0 && v.length > 0));
}
t('the app-bug sentence names the APP, never the person (bad_body / missing fields are ours)',
  APP_BUG_KO.includes('앱') && !/입력|확인해주세요$/.test(APP_BUG_KO)
  && BOOKING_HOLD_TOKENS.bad_body === APP_BUG_KO
  && BOOKING_HOLD_TOKENS['missing fields'] === APP_BUG_KO
  && PAY_TOKENS.bad_body === APP_BUG_KO
  && DROP_TOKENS.bad_body === APP_BUG_KO,
  APP_BUG_KO);
t('an expired session gets the re-login door, on all three doors',
  BOOKING_HOLD_TOKENS.unauthorized === SESSION_EXPIRED_KO
  && PAY_TOKENS.unauthorized === SESSION_EXPIRED_KO
  && PAY_TOKENS['no caller token'] === SESSION_EXPIRED_KO
  && DROP_TOKENS.unauthorized === SESSION_EXPIRED_KO
  && SESSION_EXPIRED_KO.includes('로그인'));
t('the template-prefix keys keep their trailing space (they are matched as substrings of `unknown addon livecam`)',
  BOOKING_HOLD_TOKENS['unknown addon '] !== undefined
  && BOOKING_HOLD_TOKENS['unknown selection_origin '] !== undefined);

// ── ⑤ the three behaviours, through the REAL folders ───────────────────────────────────────────
for (const [name, map, fold] of [
  ['bookingHoldError', BOOKING_HOLD_TOKENS, bookingHoldError],
  ['payError', PAY_TOKENS, payError],
  ['dropError', DROP_TOKENS, dropError],
]) {
  const bad = [];
  for (const [tok, ko] of Object.entries(map)) {
    // A template-prefix token arrives with a suffix, exactly as the server builds it.
    const wire = tok.endsWith(' ') ? tok + 'livecam' : tok;
    const out = fold(new Error(wire));
    if (out.message !== ko) bad.push(tok + ' → ' + out.message);
    if (out.raw !== wire) bad.push(tok + ' lost raw: ' + out.raw);
  }
  t(name + ': every mapped token renders its Korean AND keeps the token on `raw`',
    bad.length === 0, JSON.stringify(bad));

  // The fold: something English nobody enumerated.
  const unknown = fold(new Error('PGRST301 JWT expired at row 4'));
  t(name + ': an unknown English message folds to Korean',
    hasHangul(unknown.message), unknown.message);
  t(name + ': the fold PRESERVES the original on `raw` (a log that prints the Korean has thrown the diagnosis away)',
    unknown.raw === 'PGRST301 JWT expired at row 4', String(unknown.raw));
  t(name + ': the fold keeps the original on `cause` too',
    unknown.cause instanceof Error && unknown.cause.message === 'PGRST301 JWT expired at row 4');

  // A Hangul message is the server's own copy — it must arrive untouched, identity included.
  const ko = new Error('이 코스는 지금 예약할 수 없어요 — 점검을 위해 잠시 중단됐어요. 다른 코스를 골라주세요');
  t(name + ': a Hangul message passes through unchanged, same object',
    fold(ko) === ko);
  const ko2 = fold(new Error('card_required — 결제 카드를 먼저 등록해주세요. 카드를 등록하면 바로 예약할 수 있어요'));
  t(name + ': a mixed token+Korean sentence keeps its Korean (no token hijacks it)',
    ko2.message.includes('결제 카드를 먼저 등록해주세요'), ko2.message);
}

// The substring order that matters the day someone adds a token containing another.
t('bookingHoldError matches the longest token first (unknown addon / unknown selection_origin do not cross)',
  bookingHoldError(new Error('unknown selection_origin quick_book')).message === APP_BUG_KO
  && bookingHoldError(new Error('unknown route')).message === BOOKING_HOLD_TOKENS['unknown route']);

// An error with nothing to say is not an English error — there is no diagnosis to preserve.
t('an empty error still gets Korean, never an empty Alert',
  hasHangul(bookingHoldError(new Error('')).message)
  && hasHangul(bookingHoldError({ code: 'PGRST301' }).message)
  && hasHangul(bookingHoldError(null).message)
  && hasHangul(payError(null).message)
  && hasHangul(dropError(null).message));

// ── ⑥ the `empty` asymmetry, which is a copy decision and not a default ────────────────────────
// `owner/request.tsx` reads `(e as Error).message ?? '…'` and `??` does NOT fire on '' — so a
// message-less error drew an Alert with an empty body until this sentence existed.
t('bookingHoldError names what failed when the error says nothing',
  bookingHoldError(null).message === '예약을 만들지 못했어요 — 잠시 후 다시 시도해주세요',
  bookingHoldError(null).message);
t('dropError keeps the EXACT sentence runner/rewards.tsx used before the fold moved into the wrapper',
  dropError(null).message === '드랍을 열지 못했어요', dropError(null).message);
// 🔴 The one that must never be "improved". `confirmToss` runs after Toss may have captured, so a
// message-less error cannot be called a failed payment. A domain `empty` here would be a claim
// the client has no way to check — see edge-errors.ts's note on payError.
t('payError refuses to claim the payment failed when it does not know — it stays on the generic fold',
  payError(null).message === payError(new Error('some unmapped english')).message
  && !payError(null).message.includes('결제'),
  payError(null).message);

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
