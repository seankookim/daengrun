// ═══ pay-chip-label — the phase chip on /owner/pay may not call a real booking a mock ═══
//
// Slice cloud/p8-nav-back-mock-chip (2026-09-28). `CHIP.mock_pending` in app/owner/pay.tsx is the
// kicker a customer reads while their booking sits at `payment_hold` (src/lib/payphase.ts maps
// payment_hold → 'mock_pending'). That booking is REAL and so is its slot hold — but it is NOT a
// money hold: nothing is charged at hold creation and no PG authorization exists
// (create-booking-hold/handler.ts:40-50; the widget confirm path createPaymentIntent → TossSheet →
// confirmToss has no caller in the app). The label read 「MOCK · 준비 중」 — a false word about a
// real booking (honesty law: no fake labels). Nothing in the product is simulated; the money paths
// that do call Toss (billing-key issue, the settle charge — docs/payments.md, 2026-09-26
// correction) all run elsewhere, never at hold creation. The enum VALUE keeps its historical name
// (pay-lab and the payphase suite spell it); this pins the LABEL.
//
// ── WHY BABEL AND NOT GREP ──────────────────────────────────────────────────────────────────
// The old label is quoted in prose — this header, and the file's own comments explaining the
// relabel. A grep for `MOCK` is satisfied by documentation of the fix (the standing
// comment-quoting law). Parsing puts comments outside the tree: the value read here is the STRING
// LITERAL assigned to the key, and nothing else. PC-C1/C2 are the controls that prove a quoted old
// label reddens nothing, and PC-R1/R2 prove a real one still does.
//
// ⚠ NAMED LIMITS, prose not pins:
//   · This reads SOURCE. It proves what the table SAYS for the phase; it does not prove the chip
//     renders, nor what a `payment_hold` row IS on the server (create-booking-hold owns that; the
//     payphase suite owns the mapping), and only a device shows the chip.
//   · Only the object literal initialising `const CHIP` is read. A screen that builds the label
//     some other way (a function, a second table) is outside what this reads.
'use strict';
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

// A lab can point this at a copied tree (mutation battery): PAY_ROOT=/lab/app node test/…
const ROOT = process.env.PAY_ROOT || path.join(__dirname, '..');
const REL = 'app/owner/pay.tsx';

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const HANGUL = /[가-힣]/;
// The file's kicker grammar: LATIN CAPS · 한국어 (cf. 'CHARGE · 결제 대기', 'REVIEW · 확인 중').
const KICKER = /^[A-Z]+(?: [A-Z]+)* · \S.*$/;

/**
 * Read `const CHIP = { key: 'literal', … }` and the `chip` style's fontSize from one source text.
 * Returns { chip: Map<key, string|null> | null, chipFontSize: number | null, parseError }.
 * Only STRING LITERAL values are recorded — a template or a call is reported as `null` so a
 * table that stops being plain literals fails PC-T1 loudly rather than passing by omission.
 */
function scan(src) {
  let ast;
  try {
    ast = parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
  } catch (e) {
    return { chip: null, chipFontSize: null, parseError: String(e.message).split('\n')[0] };
  }
  let chip = null;
  let chipFontSize = null;
  const keyName = (p) => (p.key.type === 'Identifier' ? p.key.name : p.key.type === 'StringLiteral' ? p.key.value : null);
  const walk = (node) => {
    if (!node || typeof node !== 'object' || typeof node.type !== 'string') return;
    if (node.type === 'VariableDeclarator' && node.id.type === 'Identifier' && node.id.name === 'CHIP'
      && node.init && node.init.type === 'ObjectExpression') {
      chip = new Map();
      for (const p of node.init.properties) {
        if (p.type !== 'ObjectProperty') continue;
        const k = keyName(p);
        if (k == null) continue;
        chip.set(k, p.value.type === 'StringLiteral' ? p.value.value : null);
      }
    }
    // s.chip = { fontSize: <n>, … } — the style the chip Text uses. Any object property named
    // `chip` whose value carries a numeric `fontSize` is read; the file has exactly one.
    if (node.type === 'ObjectProperty' && keyName(node) === 'chip' && node.value.type === 'ObjectExpression') {
      for (const p of node.value.properties) {
        if (p.type === 'ObjectProperty' && keyName(p) === 'fontSize' && p.value.type === 'NumericLiteral') chipFontSize = p.value.value;
      }
    }
    for (const k of Object.keys(node)) {
      if (k === 'loc' || k === 'leadingComments' || k === 'trailingComments' || k === 'innerComments' || k === 'extra') continue;
      const v = node[k];
      if (Array.isArray(v)) { for (const c of v) walk(c); } else if (v && typeof v.type === 'string') walk(v);
    }
  };
  walk(ast.program);
  return { chip, chipFontSize, parseError: null };
}

const mockish = (label) => typeof label === 'string' && /mock/i.test(label);

// ── PC-R · the detector sees a real one ─────────────────────────────────────────────────────
{
  const r = scan(`const CHIP: Record<string, string> = { loading: 'LOADING', mock_pending: 'MOCK · 준비 중' };`);
  t('PC-R1 a mock_pending label spelling MOCK is seen', r.chip !== null && mockish(r.chip.get('mock_pending')));
  const r2 = scan(`const CHIP = { mock_pending: 'Mock hold' };`);
  t('PC-R2 the match is case-insensitive', mockish(r2.chip.get('mock_pending')));
  const r3 = scan(`const CHIP = { mock_pending: \`MOCK · \${x}\` };`);
  t('PC-R3 a non-literal value is reported as null, never as clean', r3.chip.has('mock_pending') && r3.chip.get('mock_pending') === null);
  const r4 = scan(`const s = StyleSheet.create({ chip: { fontSize: 11.5, lineHeight: 18 } });`);
  t('PC-R4 the chip style fontSize is read', r4.chipFontSize === 11.5);
}

// ── PC-C · controls: prose is not a label ───────────────────────────────────────────────────
{
  const c1 = scan(`// the chip used to read 'MOCK · 준비 중' — a false claim\nconst CHIP = { mock_pending: 'HOLD · 접수 전' };`);
  t('PC-C1 a // comment quoting the old label reddens nothing', c1.chip !== null && !mockish(c1.chip.get('mock_pending')));
  const c2 = scan(`/* MOCK · 준비 중 */\nconst CHIP = { mock_pending: 'HOLD · 접수 전' }; const DOC = 'MOCK · 준비 중';`);
  t('PC-C2 a block comment and an UNRELATED string spelling MOCK redden nothing', !mockish(c2.chip.get('mock_pending')));
  const c3 = scan(`const NOT_CHIP = { mock_pending: 'MOCK · 준비 중' };`);
  t('PC-C3 a table that is not CHIP is not read (chip stays null)', c3.chip === null);
  t('PC-P1 an unparseable file reports a parse error rather than 「nothing found」', scan(`const CHIP = { mock_pending: `).parseError !== null);
}

// ── PC-T · the live file ────────────────────────────────────────────────────────────────────
{
  const file = path.join(ROOT, REL);
  const r = scan(fs.readFileSync(file, 'utf8'));
  t('PC-T0 the file was read: CHIP found with mock_pending and at least ten phases',
    r.parseError === null && r.chip !== null && r.chip.has('mock_pending') && r.chip.size >= 10,
    r.parseError ?? `chip=${r.chip ? r.chip.size : 'null'}`);
  const label = r.chip?.get('mock_pending') ?? null;
  t('PC-T1 CHIP.mock_pending is a string literal that does not say MOCK (a real booking is not a mock)',
    typeof label === 'string' && !mockish(label), `label=${JSON.stringify(label)}`);
  const offenders = [...(r.chip ?? new Map()).entries()].filter(([, v]) => mockish(v)).map(([k]) => k);
  t('PC-T2 no chip in the table claims MOCK (no phase is a simulation)',
    offenders.length === 0, offenders.join(', '));
  t('PC-T3 the label keeps the file\'s kicker grammar — LATIN CAPS · 한국어',
    typeof label === 'string' && KICKER.test(label) && HANGUL.test(label.split(' · ')[1] ?? ''), `label=${JSON.stringify(label)}`);
  // The label carries Hangul, so the 15pt detail floor applies (DESIGN.md §3 — Korean text never
  // rides the Latin kicker exemption). Pinned here because the chip is the payment screen's status.
  t('PC-T4 the chip style stays at the 15pt floor (its label carries Hangul)',
    r.chipFontSize !== null && r.chipFontSize >= 15, `fontSize=${r.chipFontSize}`);
}

console.log(`\npay-chip-label: ${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
