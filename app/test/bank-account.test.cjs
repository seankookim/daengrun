// bank-account.ts — tests run against the REAL compiled source (see run-bank-account-tests.sh),
// not a retyped copy.
//
// What this file is FOR. `app/src/lib/bank-account.ts` is a MIRROR of
// `supabase/migrations/0194_bank_account_registration.sql`: the same bank list, the same three
// validations, the same refusal vocabulary, the same mask. A mirror that drifts is worse than no
// mirror, because the client then refuses what the server accepts (or, far worse, accepts what the
// server refuses and shows a raw error). The SQL suite `225_bank_account_registration_suite.sql`
// pins the server side; NOTHING pins the join except this file, because `app/test/*.cjs` cannot
// import a `.tsx` route and the harness cannot read TypeScript.
//
// So the arms that matter are the DRIFT arms, and they are bidirectional: each one reads the
// migration file itself and compares it to the compiled module. The mutations that redden them:
// add/remove/reorder a bank in either copy · change a digit bound in either copy · change the
// account-shape regex in either copy · add a `raise exception '<token>'` to the migration without
// copy here (or copy here for a token the server cannot raise) · change the mask prefix in either
// copy · strip `normalizeAccountDigits` down to a bare non-digit replace · empty BANK_NOTE · make
// the note claim a verification the product does not have.
const fs = require('fs');
const path = require('path');
const {
  BANKS, bankLabel, BANK_ERROR_KO, BANK_NOTE, MASK_PREFIX, ACCOUNT_UNREADABLE_KO,
  ACCOUNT_MIN_DIGITS, ACCOUNT_MAX_DIGITS, HOLDER_MAX,
  normalizeAccountDigits, maskAccount, validateBankAccount,
} = require('./bank-account.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const migDir = path.join(__dirname, '..', '..', 'supabase', 'migrations');
const migName = fs.readdirSync(migDir).find((f) => /^0194_.*\.sql$/.test(f));
t('the migration this module mirrors is on disk', !!migName, String(migName));
const migRaw = migName ? fs.readFileSync(path.join(migDir, migName), 'utf8') : '';
// ⚠ TWO different reads of the same file, on purpose.
//   · The bank list is parsed from the RAW text, because its BANK-LIST-BEGIN/END markers are
//     themselves `--` comments and a stripped read would delete them.
//   · The refusal tokens are harvested from the STRIPPED text, because `prosrc` is source plus our
//     own prose and a token named in a comment explaining a guard would otherwise count as the
//     guard (the standing comment-matching law). The raw>stripped arm below proves the strip does
//     something rather than being decorative.
const migStripped = migRaw.replace(/--[^\n]*/g, '');
t('stripping comments from the migration removes something (the strip is load-bearing)',
  migRaw.length > migStripped.length, `${migRaw.length} vs ${migStripped.length}`);

// ── DRIFT ①: the bank list is the same list, in the same order ────────────────────────────────
const between = migRaw.split('BANK-LIST-BEGIN')[1]?.split('BANK-LIST-END')[0] ?? '';
t('the migration carries a BANK-LIST-BEGIN/END block', between.length > 0, String(between.length));
const sqlBanks = [...between.matchAll(/\('(\d{3})',\s*'([^']+)',\s*\d+\)/g)]
  .map((m) => ({ code: m[1], label: m[2] }));
t('the SQL seed block parses to a non-empty list', sqlBanks.length > 0, String(sqlBanks.length));
t('BANKS and bank_codes are the SAME list in the SAME order (drift, both directions)',
  JSON.stringify(sqlBanks) === JSON.stringify(BANKS.map((b) => ({ code: b.code, label: b.label }))),
  `sql=${sqlBanks.length} ts=${BANKS.length}`);
t('every bank code is a distinct three-digit 금융결제원 code',
  BANKS.every((b) => /^\d{3}$/.test(b.code))
  && new Set(BANKS.map((b) => b.code)).size === BANKS.length);
t('every bank has a non-empty label, all distinct',
  BANKS.every((b) => typeof b.label === 'string' && b.label.trim() !== '')
  && new Set(BANKS.map((b) => b.label)).size === BANKS.length);
t('bankLabel resolves a code and is honest about one it does not know',
  bankLabel('090') === '카카오뱅크' && bankLabel('999') === null
  && bankLabel(null) === null && bankLabel('') === null,
  String(bankLabel('090')));

// ── DRIFT ②: the refusal vocabulary is exactly what the migration can raise ────────────────────
const sqlTokens = [...migStripped.matchAll(/raise exception '([a-z_]+)'/g)].map((m) => m[1]);
const sqlSet = [...new Set(sqlTokens)].sort();
const koSet = Object.keys(BANK_ERROR_KO).sort();
t('the migration raises at least one named refusal (the harvester works)',
  sqlSet.length > 0, JSON.stringify(sqlSet));
t('BANK_ERROR_KO covers EXACTLY the tokens 0194 raises — no missing copy, no copy for a token that cannot happen',
  JSON.stringify(sqlSet) === JSON.stringify(koSet),
  `sql=${JSON.stringify(sqlSet)} ts=${JSON.stringify(koSet)}`);
t('every refusal has non-empty Korean copy',
  koSet.every((k) => typeof BANK_ERROR_KO[k] === 'string' && BANK_ERROR_KO[k].trim() !== ''));
t('payout_owed says WHY rather than naming an action that does not exist',
  BANK_ERROR_KO.payout_owed.includes('지급') && BANK_ERROR_KO.payout_owed.includes('삭제'),
  BANK_ERROR_KO.payout_owed);
// 🔴 `account_unreadable` MUST NOT be in the refusal map. 0194 §F④ stopped raising it — a raise
// would roll back its own journal row — so it names a STATE the client renders (a NULL mask), not
// something the server sends. Both arms, because either alone is satisfiable by the wrong file:
// the copy has to exist, and it has to exist OUTSIDE the map the equality arm above compares.
t('the unreadable-row copy exists and is NOT a refusal token',
  typeof ACCOUNT_UNREADABLE_KO === 'string' && ACCOUNT_UNREADABLE_KO.trim() !== ''
  && !('account_unreadable' in BANK_ERROR_KO),
  String(ACCOUNT_UNREADABLE_KO));
t('and the migration genuinely stopped raising it (if it raises again, the map must carry it again)',
  !/raise exception 'account_unreadable'/.test(migStripped));

// 🔴 the honesty arm: nothing on this surface may claim a verification the product does not have.
// `verified_at` is NULL in every row and 0194 never writes it.
const allCopy = Object.values(BANK_ERROR_KO).join(' ') + ' ' + BANK_NOTE + ' ' + ACCOUNT_UNREADABLE_KO;
t('no copy on this surface claims the account is verified/authenticated',
  !/인증|검증|확인됐|확인되었|확인 완료/.test(allCopy), allCopy.slice(0, 120));
t('BANK_NOTE says what is done (암호화) AND what is not (예금주 확인 없음)',
  BANK_NOTE.trim() !== '' && BANK_NOTE.includes('암호화') && BANK_NOTE.includes('아직 없어요'),
  BANK_NOTE);

// ── DRIFT ③: the bounds and the shape rule are the server's ───────────────────────────────────
t('the digit bounds are the migration\'s bounds (both directions)',
  migStripped.includes(`length(v_digits) < ${ACCOUNT_MIN_DIGITS}`)
  && migStripped.includes(`length(v_digits) > ${ACCOUNT_MAX_DIGITS}`),
  `${ACCOUNT_MIN_DIGITS}..${ACCOUNT_MAX_DIGITS}`);
t('the holder cap is the migration\'s cap',
  migStripped.includes(`length(v_holder) > ${HOLDER_MAX}`), String(HOLDER_MAX));
t('the account-shape regex is byte-identical to the migration\'s',
  migStripped.includes("'^[0-9]([0-9 -]*[0-9])?$'"),
  'the SQL regex changed without this file');
// 🔴 BOTH SIDES TRIM, OR A PASTED NUMBER PASSES HERE AND IS REFUSED THERE. `normalizeAccountDigits`
// trims; this asserts the server does too. Of the two ways a mirror can drift, accepting what the
// server refuses is the one that leaves the person with an error they cannot resolve.
t('the server trims before testing the shape, the way this module does',
  migStripped.includes('btrim(p_account)'),
  'set_my_bank_account does not btrim — a pasted number would pass locally and be refused remotely');
t('the mask prefix is the migration\'s prefix',
  migStripped.includes(`'${MASK_PREFIX}'`), MASK_PREFIX);

// ── normalizeAccountDigits ────────────────────────────────────────────────────────────────────
t('plain digits pass through', normalizeAccountDigits('1234567890') === '1234567890');
t('hyphens are separators, not data', normalizeAccountDigits('110-123-456789') === '110123456789');
t('spaces are separators too', normalizeAccountDigits('100 200 300400') === '100200300400');
t('surrounding whitespace is trimmed first', normalizeAccountDigits('  1234567890  ') === '1234567890');
// 🔴 THE ARM THAT MATTERS: a strip-first implementation returns '1234567890' here and would store
// a destination nobody typed. The shape must be checked BEFORE the separators come out.
t('digits buried in text are NOT an account number',
  normalizeAccountDigits('계좌 1234567890 입니다') === null,
  String(normalizeAccountDigits('계좌 1234567890 입니다')));
t('letters mixed in are rejected', normalizeAccountDigits('110-abc-456789') === null);
t('separators only are rejected', normalizeAccountDigits('----------') === null);
t('a leading or trailing separator is rejected',
  normalizeAccountDigits('-1234567890') === null && normalizeAccountDigits('1234567890-') === null);
t('empty, null and non-strings are rejected',
  normalizeAccountDigits('') === null && normalizeAccountDigits(null) === null
  && normalizeAccountDigits(undefined) === null && normalizeAccountDigits(1234567890) === null);
t('a single digit normalises (length is validate\'s job, not normalise\'s)',
  normalizeAccountDigits('7') === '7');

// ── maskAccount ───────────────────────────────────────────────────────────────────────────────
t('the mask is the prefix plus the LAST four digits',
  maskAccount('3333011234567') === MASK_PREFIX + '4567', String(maskAccount('3333011234567')));
t('the mask never leaks more than four digits',
  ['1234567890', '1234567890123456', '110123456789']
    .every((d) => (maskAccount(d).match(/\d/g) || []).length === 4));
t('the mask strips separators before slicing', maskAccount('110-123-456789') === MASK_PREFIX + '6789');
t('too short to mask is null, not a partial leak',
  maskAccount('123') === null && maskAccount('') === null && maskAccount(null) === null);

// ── validateBankAccount ───────────────────────────────────────────────────────────────────────
const ok = { bank: '090', account: '3333-01-1234567', holder: '김러너' };
t('a well-formed registration is not refused locally', validateBankAccount(ok) === null,
  String(validateBankAccount(ok)));
t('an unknown bank code is bad_bank',
  validateBankAccount({ ...ok, bank: '999' }) === 'bad_bank');
t('a LABEL where a code belongs is bad_bank (the client sends codes)',
  validateBankAccount({ ...ok, bank: '카카오뱅크' }) === 'bad_bank');
t('a missing bank is bad_bank',
  validateBankAccount({ ...ok, bank: null }) === 'bad_bank'
  && validateBankAccount({ account: ok.account, holder: ok.holder }) === 'bad_bank');
t('9 digits and 17 digits are bad_account',
  validateBankAccount({ ...ok, account: '123456789' }) === 'bad_account'
  && validateBankAccount({ ...ok, account: '12345678901234567' }) === 'bad_account');
// the control: the bounds are INCLUSIVE at both ends, so 「refuse everything」 fails here
t('10 and 16 digits are accepted (the bounds are inclusive — the control for every arm above)',
  validateBankAccount({ ...ok, account: '1234567890' }) === null
  && validateBankAccount({ ...ok, account: '1234567890123456' }) === null);
t('an unparseable account is bad_account',
  validateBankAccount({ ...ok, account: '계좌 1234567890 입니다' }) === 'bad_account'
  && validateBankAccount({ ...ok, account: '' }) === 'bad_account'
  && validateBankAccount({ ...ok, account: null }) === 'bad_account');
t('an empty or whitespace holder is bad_holder',
  validateBankAccount({ ...ok, holder: '' }) === 'bad_holder'
  && validateBankAccount({ ...ok, holder: '   ' }) === 'bad_holder'
  && validateBankAccount({ ...ok, holder: null }) === 'bad_holder');
t('an over-long holder is bad_holder, and one at the cap is not',
  validateBankAccount({ ...ok, holder: '가'.repeat(HOLDER_MAX + 1) }) === 'bad_holder'
  && validateBankAccount({ ...ok, holder: '가'.repeat(HOLDER_MAX) }) === null);
// 🔴 the ORDER arm: the server gates bank → account → holder, so a call that is wrong in all three
// must report the FIRST one. A client that reports a different token than the server would send a
// person to fix the wrong field.
t('when several things are wrong the token is the FIRST the server would raise',
  validateBankAccount({ bank: 'NOPE', account: 'xx', holder: '' }) === 'bad_bank'
  && validateBankAccount({ bank: '090', account: 'xx', holder: '' }) === 'bad_account',
  String(validateBankAccount({ bank: 'NOPE', account: 'xx', holder: '' })));
t('every token validateBankAccount can return has copy',
  ['bad_bank', 'bad_account', 'bad_holder'].every((k) => typeof BANK_ERROR_KO[k] === 'string'));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
