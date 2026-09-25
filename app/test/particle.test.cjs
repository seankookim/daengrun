// particle.ts pins — the particle after a dog's name agrees with the name.
//
// ═══ WHY THIS EXISTS (copy-hierarchy-1, 2026-09-25 second gap sweep) ═══
// Particles were hard-coded after interpolated names across the owner screens: `${name}가 달려요`,
// `{runner}가 {name}를 돌려주고`, `${name}와 달릴 시간을`. A name ending in a final consonant read
// 「콩가 달려요 · 콩를 돌려주고」, and the '반려견' fallback — which ends in one — read 「반려견가」.
// `withParticle` (src/lib/particle.ts) already existed and had exactly one caller.
//
// ═══ THE PAIR ORDER IS THE WHOLE TRAP ═══
// particle.ts takes the pair OPEN-SYLLABLE-FORM first: '가/이', '를/을', '와/과', '는/은'. 와/과 is
// conventionally written that way round and the other three are not, so a caller that writes the
// conventional '이/가' gets EXACTLY the inverted particle for every name. The cases below fix a
// consonant-final name AND an open-syllable name for each pair, so an inversion — in the helper or
// in the pair a caller passes — reddens on both 콩 and 초코, never on one alone.
const { withParticle } = require('./particle.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const eq = (got, want, label) => t(`${label}: ${want}`, got === want, `got ${got}`);

// ── a final consonant (받침) — 콩 · 반려견 ──────────────────────────────────────────────────────
eq(withParticle('콩', '가/이'), '콩이', '콩 + 가/이');
eq(withParticle('콩', '를/을'), '콩을', '콩 + 를/을');
eq(withParticle('콩', '와/과'), '콩과', '콩 + 와/과');
eq(withParticle('콩', '는/은'), '콩은', '콩 + 는/은');
// The fallback name the screens print when a booking has no dog name. It ends in 견 (받침 ㄴ),
// which is exactly why the hard-coded 가 printed 「반려견가」.
eq(withParticle('반려견', '가/이'), '반려견이', '반려견 (the fallback) + 가/이');
eq(withParticle('반려견', '를/을'), '반려견을', '반려견 + 를/을');

// ── an open syllable — 초코 · 러너 ──────────────────────────────────────────────────────────────
eq(withParticle('초코', '가/이'), '초코가', '초코 + 가/이');
eq(withParticle('초코', '를/을'), '초코를', '초코 + 를/을');
eq(withParticle('초코', '와/과'), '초코와', '초코 + 와/과');
eq(withParticle('초코', '는/은'), '초코는', '초코 + 는/은');
// The runner label every hero sentence builds (`${runnerName} 러너`) ends in 너 — open.
eq(withParticle('민준 러너', '가/이'), '민준 러너가', 'a runner label + 가/이');
// 「우리 아이」 is home-hero's name fallback; 이 is open (no 받침), so 가.
eq(withParticle('우리 아이', '가/이'), '우리 아이가', 'home-hero fallback + 가/이');

// ── what is NOT Hangul takes the open form (the reading is unknown; Korean writers default there) ──
eq(withParticle('Coco', '가/이'), 'Coco가', 'a latin name');
eq(withParticle('R2', '를/을'), 'R2를', 'a trailing digit');
eq(withParticle('', '가/이'), '가', 'an empty name (never a crash, never NaN)');

// ── the inversion guard, stated directly ─────────────────────────────────────────────────────────
// The conventional spelling of the pair is the WRONG argument. This case exists so nobody can
// "fix" a call site to '이/가' without a red: with the helper's contract, '이/가' yields the
// open-syllable slot's text for a consonant-final name.
t('CONTROL · passing the conventional \'이/가\' INVERTS the result (the pair order is load-bearing)',
  withParticle('콩', '이/가') === '콩가' && withParticle('초코', '이/가') === '초코이',
  `${withParticle('콩', '이/가')} / ${withParticle('초코', '이/가')}`);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
