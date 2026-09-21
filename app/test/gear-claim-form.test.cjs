// gear-claim-form.ts — tests run against the REAL compiled source (see
// run-gear-claim-form-tests.sh), not a retyped copy, so the rules these cases pin are the rules
// that ship on runner/rewards.tsx.
//
// WHAT THIS FILE IS FOR, since a validator can be pinned pointlessly. The client check is NOT the
// gate — `claim_gear_tx` (0195 §B) validates the same five facts and refuses by name. So the
// properties worth pinning are the two that would actually cost something:
//
//   ① **It must not be STRICTER than the server.** A client that refuses an input the server
//      accepts is a second, undocumented rule — and it is the one a person meets first, so it
//      silently becomes the real rule while nobody has written it down. Every arm below that
//      accepts a "messy" input (hyphens, spaces, a 10-digit 01X number) exists for this.
//   ② **It must point at the TOPMOST problem.** A validator that complains about the postal code
//      while the name is empty reads as random, and a person fixes the wrong field.
//
// ⚠ It is allowed to be LOOSER than the server in one direction and that is deliberate: the
//    server is the authority, and a missed client refusal costs one round trip, while a wrong
//    client refusal costs the claim entirely.
//
// The mutations that redden it: drop any field from the order · accept a 9- or 12-digit phone ·
// require the phone to be digits-only (kills hyphen input) · accept a 4- or 6-digit postal ·
// make address2 required · trim-check `recipient` with `=== ''` instead of `.trim() === ''`.
const {
  gearClaimProblem, gearClaimReady, GEAR_CLAIM_PROBLEM_TEXT, EMPTY_GEAR_CLAIM_FORM,
} = require('./gear-claim-form.build.cjs');

let pass = 0, fail = 0;
const t = (name, fn) => { try { fn(); console.log('PASS ' + name); pass++; } catch (e) { console.log('FAIL ' + name + ' — ' + e.message); fail++; } };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

// A form that is complete in every field. Every case below starts from this and breaks ONE thing,
// so a red arm names the field that broke rather than the accumulation of several.
const OK = {
  recipient: '김러너',
  phone: '010-1234-5678',
  address1: '서울시 서초구 반포대로 1',
  address2: '101동 202호',
  postal: '06578',
};
const withField = (k, v) => ({ ...OK, [k]: v });

t('a complete form is ready — the control that stops every arm below passing for free', () => {
  eq(gearClaimProblem(OK), null);
  eq(gearClaimReady(OK), true);
});

t('the EMPTY form is not ready, and the first complaint is the FIRST field', () => {
  eq(gearClaimProblem(EMPTY_GEAR_CLAIM_FORM), 'recipient');
  eq(gearClaimReady(EMPTY_GEAR_CLAIM_FORM), false);
});

t('②  the problem reported is the TOPMOST one, never a later field', () => {
  // Every field broken at once: the answer must be `recipient` four times over as the earlier
  // fields are filled in, walking down the form the way a person does.
  const allBad = { recipient: '', phone: '1', address1: '', address2: '', postal: 'x' };
  eq(gearClaimProblem(allBad), 'recipient');
  eq(gearClaimProblem({ ...allBad, recipient: '김러너' }), 'phone');
  eq(gearClaimProblem({ ...allBad, recipient: '김러너', phone: '01012345678' }), 'address1');
  eq(gearClaimProblem({ ...allBad, recipient: '김러너', phone: '01012345678', address1: '서울시 1' }), 'postal');
});

t('recipient: whitespace is not a name', () => {
  for (const v of ['', ' ', '   ', '\n', '\t ']) eq(gearClaimProblem(withField('recipient', v)), 'recipient', JSON.stringify(v));
  eq(gearClaimProblem(withField('recipient', ' 김 ')), null, 'a padded real name is a real name');
});

t('①  phone: hyphens and spaces are ACCEPTED — the server strips to digits, so we must not refuse them', () => {
  // 0195 §B ⑥ does `regexp_replace(phone, '[^0-9]', '', 'g')`. Refusing these here would make the
  // client the stricter authority over a field the server deliberately normalises.
  for (const v of ['010-1234-5678', '010 1234 5678', '01012345678', ' 010-1234-5678 ', '010.1234.5678']) {
    eq(gearClaimProblem(withField('phone', v)), null, JSON.stringify(v));
  }
  // 10 digits is a real Korean number (the older 01X blocks), not a typo
  eq(gearClaimProblem(withField('phone', '0111234567')), null, '10-digit 01X');
  eq(gearClaimProblem(withField('phone', '011-123-4567')), null, '10-digit 01X with hyphens');
});

t('phone: fewer than 10 or more than 11 DIGITS is refused, however it is punctuated', () => {
  for (const v of ['', '0', '010', '010123456', '010-123-456', '010123456789', '010-1234-56789', '   ']) {
    eq(gearClaimProblem(withField('phone', v)), 'phone', JSON.stringify(v));
  }
  // ⚠ the arm that separates "counts digits" from "counts characters": this is 11 CHARACTERS of
  // punctuation-heavy text carrying only 7 digits. A length check on the raw string passes it.
  eq(gearClaimProblem(withField('phone', '01-2-3-4-5-6-7')), 'phone', 'punctuation padding to length');
  // ...and its mirror: 11 digits wearing enough punctuation to be 15 characters long
  eq(gearClaimProblem(withField('phone', '010-1234-5678')), null, '11 digits, 13 characters');
});

t('address1 is required; address2 is NOT', () => {
  for (const v of ['', ' ', '   ']) eq(gearClaimProblem(withField('address1', v)), 'address1', JSON.stringify(v));
  // the whole point of the optional field: a person in a detached house has no second line, and
  // making them type one would be a fiction the courier then prints
  for (const v of ['', ' ', '   ', '101동 202호']) eq(gearClaimProblem(withField('address2', v)), null, JSON.stringify(v));
});

t('postal: exactly five digits — four and six are both refused', () => {
  // A four-digit entry is the OLD six-digit format's first half, which is the single most likely
  // wrong thing to type. Accepting it would post a box into a guess.
  for (const v of ['', '1', '0657', '065789', '123456', 'abcde', '065-7', '  ', '0657a']) {
    eq(gearClaimProblem(withField('postal', v)), 'postal', JSON.stringify(v));
  }
  for (const v of ['06578', '00000', '99999', ' 06578 ', '065-78']) {
    eq(gearClaimProblem(withField('postal', v)), null, JSON.stringify(v));
  }
});

t('every field the validator can name has a Korean message, and none is blank or latin', () => {
  // A problem code with no sentence renders as an empty failure strip — a screen that says
  // something went wrong without saying what.
  for (const k of ['recipient', 'phone', 'address1', 'postal']) {
    const msg = GEAR_CLAIM_PROBLEM_TEXT[k];
    if (typeof msg !== 'string' || msg.trim() === '') throw new Error(k + ' has no message');
    if (/[a-zA-Z]/.test(msg)) throw new Error(k + ' message carries latin text: ' + msg);
  }
  // ...and every code the function can actually RETURN has one — the two-sided check, so a fifth
  // code added later cannot ship without its sentence.
  const produced = new Set();
  for (const k of ['recipient', 'phone', 'address1', 'postal']) {
    produced.add(gearClaimProblem(withField(k, k === 'phone' ? '1' : (k === 'postal' ? '1' : ''))));
  }
  for (const code of produced) {
    if (code === null) continue;
    if (!(code in GEAR_CLAIM_PROBLEM_TEXT)) throw new Error('produced code with no message: ' + code);
  }
});

t('EMPTY_GEAR_CLAIM_FORM has every field the form renders, all blank', () => {
  for (const k of ['recipient', 'phone', 'address1', 'address2', 'postal']) {
    if (!(k in EMPTY_GEAR_CLAIM_FORM)) throw new Error('missing field ' + k);
    eq(EMPTY_GEAR_CLAIM_FORM[k], '', k);
  }
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
