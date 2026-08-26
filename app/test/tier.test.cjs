// runnerTierLabel — tests run against the REAL compiled source (see run-tier-label-tests.sh),
// not a retyped copy, so the mapping these cases pin is the mapping that ships.
//
// Why this pin exists: FIVE call sites mapped `runners.tier` with copied logic that DISAGREED —
// three storefront sites sent every unmatched value to '마스터' (the top credential), a public
// profile sent it to '지원자', and runner/apply leaked the raw English token. The three storefront
// feeds exclude applicants with a NEGATIVE server predicate (tier <> 'applicant'), so two
// negatives compose: add a value to the runner_tier enum and it passes the gate, then renders to
// an owner choosing who takes their dog as a master nobody certified.
//
// THE PROPERTY, stated without reference to any mutation: for every input, the label is either
// the word for that exact enum value, or a word that claims no credential at all. No input may
// produce a credential word it does not name.
const { runnerTierLabel } = require('./tier.build.cjs');

const CREDENTIALS = ['마스터', '베테랑', '인증 러너', '지원자'];
const KNOWN = { certified: '인증 러너', veteran: '베테랑', master: '마스터', applicant: '지원자' };

let pass = 0, fail = 0;
const t = (name, fn) => { try { fn(); console.log('PASS ' + name); pass++; } catch (e) { console.log('FAIL ' + name + ' — ' + e.message); fail++; } };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

for (const [value, word] of Object.entries(KNOWN)) {
  t(value + ' -> ' + word, () => eq(runnerTierLabel(value), word));
}

t('NO input outside the enum ever produces a credential word', () => {
  // ⚠ Half of these deliberately SHARE A PREFIX OR SUBSTRING with a real value. A mapping written
  // with startsWith/includes instead of === passes every "obviously different" outsider and still
  // hands 인증 러너 to anything beginning with c. The property is about the exact value, so the
  // inputs have to be able to tell an exact match from a sloppy one.
  const outsiders = ['elite', 'pro', 'trusted', 'gold', 'MASTER', 'Certified', 'master ', ' veteran',
                     '', null, undefined, 0, 1, true, false, [], {}, '마스터',
                     'c', 'cert', 'certified_plus', 'certifiedx', 'coach', 'club_lead',
                     'v', 'veteran_x', 'vip', 'm', 'master_emeritus', 'mentor',
                     'a', 'applicant2', 'applicant_withdrawn', 'admin'];
  for (const v of outsiders) {
    const out = runnerTierLabel(v);
    for (const c of CREDENTIALS) {
      if (out === c) throw new Error(JSON.stringify(v) + ' claimed the credential ' + c);
    }
  }
});

t('every known value maps to its OWN word, never another value\'s', () => {
  for (const [value, word] of Object.entries(KNOWN)) {
    const out = runnerTierLabel(value);
    for (const [other, otherWord] of Object.entries(KNOWN)) {
      if (other !== value && out === otherWord) throw new Error(value + ' rendered as ' + other + "'s word");
    }
    eq(out, word, value);
  }
});

t('the unknown label is non-empty (callers concatenate it into a subtitle)', () => {
  const out = runnerTierLabel('some_future_tier');
  if (typeof out !== 'string' || out.trim() === '') throw new Error('unknown produced ' + JSON.stringify(out));
});

t('case and whitespace variants do not sneak into a credential', () => {
  for (const v of ['Master', 'MASTER', ' master', 'master\n', 'VETERAN']) {
    const out = runnerTierLabel(v);
    if (CREDENTIALS.includes(out)) throw new Error(JSON.stringify(v) + ' -> ' + out);
  }
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
