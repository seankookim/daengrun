// claimStatusLabel — tests run against the REAL compiled source (see run-claim-status-tests.sh),
// not a retyped copy, so the mapping these cases pin is the mapping that ships on the rewards
// centre and the shop.
//
// Why this pin exists: TWO call sites mapped `gear_claims.status` with copied ternaries that
// covered DIFFERENT amounts of the same closed enum. runner/rewards.tsx matched one value and
// sent locked/claimed/shipped to the raw English token; shop.tsx matched two and leaked the
// other two the same way. `claim_status` is a pg enum of exactly four
// (0001_init.sql:21 — locked, claimable, claimed, shipped), so "the domain is closed" is a fact
// about the server, not an assumption about the client.
//
// THE PROPERTY, stated without reference to any mutation: for every input, the label is either
// the word for that exact enum value, or a neutral word that claims no fulfilment state at all.
// No input may produce a fulfilment word it does not name, and no input may be echoed back as
// its own raw token.
const { claimStatusLabel, claimCarrierLine } = require('./claim-status.build.cjs');

// [0195] THREE OF THE FOUR WORDS MOVED, and the reason is in claim-status.ts's own header: the
// fulfilment door shipped, so 「배송 연동 준비 중」 became false and 「수령 완료」 started claiming
// possession of a box that has not moved. The PROPERTIES below are unchanged — that is the point
// of writing them without reference to the copy. Only this table and OVERSTATING are edited.
const KNOWN = {
  locked: '잠김',
  claimable: '수령 가능',
  claimed: '배송 준비 중',
  shipped: '배송 중',
};
const STATE_WORDS = Object.values(KNOWN);
// The two that overstate hardest: they assert that ops has begun or completed a dispatch, which
// only a server row can establish. An unknown value reaching either is the failure this helper
// exists to stop.
const OVERSTATING = ['배송 준비 중', '배송 중'];

let pass = 0, fail = 0;
const t = (name, fn) => { try { fn(); console.log('PASS ' + name); pass++; } catch (e) { console.log('FAIL ' + name + ' — ' + e.message); fail++; } };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

for (const [value, word] of Object.entries(KNOWN)) {
  t(value + ' -> ' + word, () => eq(claimStatusLabel(value), word));
}

// ⚠ Half of these deliberately SHARE A PREFIX OR SUBSTRING with a real enum value. A mapping
// written with startsWith/includes instead of === passes every "obviously different" outsider
// and still hands 발송 완료 to anything beginning with 'ship'. The property is about the EXACT
// value, so the inputs have to be able to tell an exact match from a sloppy one.
const OUTSIDERS = [
  'pending', 'cancelled', 'refunded', 'returned', 'delivered', 'expired', 'void',
  'Locked', 'SHIPPED', 'Claimed', 'shipped ', ' claimable', 'claimed\n',
  '', null, undefined, 0, 1, true, false, [], {},
  // the four current words AND the three 0195 retired — a mapping that echoes a display word
  // back is as broken as one that echoes the enum token
  '잠김', '수령 가능', '배송 준비 중', '배송 중', '수령 완료', '발송 완료', '수령 가능 · 배송 연동 준비 중',
  // prefix/substring neighbours of each of the four values
  'lock', 'locke', 'locked_out', 'lockedx', 'l',
  'claim', 'claima', 'claimable_soon', 'claimablex', 'c',
  'claimed_x', 'claimed2', 'unclaimed', 'reclaimed',
  'ship', 'shipp', 'shipping', 'shippedx', 'shipped_partial', 's', 'unshipped',
];

// ⚠ Never let one input abort the sweep. A mapping written as `s?.startsWith('lock')` THROWS on
// the first non-string input (0, true, []) — and if that ends the loop, the case goes red for a
// TypeError while the prefix outsiders it exists to check are never reached. It was caught, but
// for the wrong reason, and a pin that reports the wrong reason cannot tell you which conjunct is
// doing the work. So: a throw is recorded as its own violation and the sweep continues.
const sweep = (judge) => {
  const bad = [];
  for (const v of OUTSIDERS) {
    let out;
    try {
      out = claimStatusLabel(v);
    } catch (e) {
      bad.push(JSON.stringify(v) + ' threw ' + e.message);
      continue;
    }
    const why = judge(out);
    if (why) bad.push(JSON.stringify(v) + ' ' + why);
  }
  if (bad.length) throw new Error(bad.length + ' violation(s): ' + bad.join(' | '));
};

t('NO input outside the enum ever produces a state word', () => {
  sweep((out) => (STATE_WORDS.includes(out) ? 'claimed the state ' + out : null));
});

t('NO input outside the enum ever asserts a fulfilment step', () => {
  // The same conjunct as above narrowed to the two overstating words, so this case still fails
  // on its own if the neutral fallback is ever pointed at 수령 완료 / 발송 완료.
  sweep((out) => (OVERSTATING.includes(out) ? 'asserted fulfilment: ' + out : null));
});

t('every enum value maps to its OWN word, never another value\'s', () => {
  for (const [value, word] of Object.entries(KNOWN)) {
    const out = claimStatusLabel(value);
    for (const [other, otherWord] of Object.entries(KNOWN)) {
      if (other !== value && out === otherWord) throw new Error(value + ' rendered as ' + other + "'s word");
    }
    eq(out, word, value);
  }
});

t('no raw English token is ever echoed to the screen', () => {
  // The original defect verbatim: `… : g.status`. Every enum value and every latin-token
  // outsider must come back as something OTHER than itself.
  const tokens = [...Object.keys(KNOWN), ...OUTSIDERS.filter((v) => typeof v === 'string' && /^[a-zA-Z_ \n]*$/.test(v) && v !== '')];
  for (const v of tokens) {
    const out = claimStatusLabel(v);
    if (out === v) throw new Error(JSON.stringify(v) + ' was echoed back as its own token');
    if (/[a-zA-Z]/.test(out)) throw new Error(JSON.stringify(v) + ' produced latin text: ' + JSON.stringify(out));
  }
});

t('null, undefined and empty produce the neutral word, not a state and not blank', () => {
  for (const v of [null, undefined, '']) {
    const out = claimStatusLabel(v);
    if (typeof out !== 'string' || out.trim() === '') throw new Error(JSON.stringify(v) + ' produced ' + JSON.stringify(out));
    if (STATE_WORDS.includes(out)) throw new Error(JSON.stringify(v) + ' claimed the state ' + out);
  }
  // All three agree — the callers concatenate nothing here, but a chip with three different
  // "we don't know" words is drift starting over.
  eq(claimStatusLabel(null), claimStatusLabel(undefined), 'null vs undefined');
  eq(claimStatusLabel(''), claimStatusLabel(null), 'empty vs null');
});

t('case and whitespace variants do not sneak into a state word', () => {
  for (const v of ['Shipped', 'SHIPPED', ' shipped', 'shipped\n', 'CLAIMED', 'Locked', 'claimable ']) {
    const out = claimStatusLabel(v);
    if (STATE_WORDS.includes(out)) throw new Error(JSON.stringify(v) + ' -> ' + out);
  }
});

// ── [0195] the properties the copy change is allowed to move, and the ones it is not ──────────

t('NO label ever asserts an ARRIVAL — the enum has no `delivered` value', () => {
  // The original file's strongest argument, and it survives the copy change verbatim: nothing
  // records that a box was received, so no word may say it was. ⚠ `배송 완료` is the exact string
  // to refuse; `배송 중` and `배송 준비 중` are transit and preparation, which ARE recorded.
  for (const v of [...Object.keys(KNOWN), ...OUTSIDERS.filter((x) => typeof x === 'string')]) {
    const out = claimStatusLabel(v);
    for (const banned of ['배송 완료', '도착', '수령 완료']) {
      if (out.includes(banned)) throw new Error(JSON.stringify(v) + ' -> ' + out + ' asserts arrival via ' + banned);
    }
  }
});

t('the claimable word makes NO claim about shipping — there is a door beside it now', () => {
  // The retired clause 「· 배송 연동 준비 중」 was honest while the chip was a dead label. Next to
  // a working 수령 신청 button it is the mirror of the original defect: copy describing a state
  // the product has left. A runner who has not claimed yet is told nothing about dispatch.
  const out = claimStatusLabel('claimable');
  for (const banned of ['배송', '연동', '준비']) {
    if (out.includes(banned)) throw new Error('claimable label still talks about shipping: ' + out);
  }
});

t('claimed and shipped are DIFFERENT words — the two ops steps must be distinguishable', () => {
  // `ops_gear_claims_pending()` is exactly the `claimed` population and `ops_mark_gear_shipped`
  // moves a row out of it. If the screen rendered one word for both, a runner could not tell
  // "we have your address" from "your box is moving", which is the whole value of the ops write.
  if (claimStatusLabel('claimed') === claimStatusLabel('shipped')) throw new Error('claimed and shipped share a word');
});

// ── claimCarrierLine — an absent shipment draws nothing ───────────────────────────────────────
// THE PROPERTY: a carrier line is rendered only when the server holds BOTH halves. A half-filled
// pair is not a partial truth worth printing — a carrier with no number cannot be looked up, and
// a number with no carrier cannot be looked up either.
t('both halves required — any missing or blank half yields null', () => {
  const halves = [null, undefined, '', '   ', '\n'];
  for (const c of halves) {
    if (claimCarrierLine(c, 'TRK-1') !== null) throw new Error('carrier ' + JSON.stringify(c) + ' rendered');
    if (claimCarrierLine('CJ대한통운', c) !== null) throw new Error('tracking ' + JSON.stringify(c) + ' rendered');
    for (const c2 of halves) {
      if (claimCarrierLine(c, c2) !== null) throw new Error('both missing rendered');
    }
  }
});

t('a complete pair renders both halves, trimmed, with nothing invented', () => {
  eq(claimCarrierLine('CJ대한통운', 'TRK-0195-B'), 'CJ대한통운 TRK-0195-B');
  eq(claimCarrierLine('  롯데택배 ', ' 1234567890 '), '롯데택배 1234567890');
  // the control: a real pair must NOT be null, or the arm above passes by rendering nothing ever
  if (claimCarrierLine('한진택배', 'X') === null) throw new Error('a complete pair was suppressed');
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
