// Korean particle agreement — the CTA reads "초코와 시작하기" but "민준과 시작하기".
// `pair` is written OPEN-SYLLABLE-FORM / FINAL-CONSONANT-FORM, the order 와/과 and 로/으로 are
// conventionally written in. ⚠ 은/는 · 이/가 · 을/를 are conventionally written the other way
// round, so those must be passed reversed ('는/은'). A non-Hangul tail (latin, digit, emoji)
// takes the open form — the reading is unknown and that is what Korean writers default to.
export function withParticle(word: string, pair: string): string {
  const [open, closed] = pair.split('/');
  const code = word.trim().slice(-1).charCodeAt(0); // '' → NaN → open
  const isSyllable = code >= 0xac00 && code <= 0xd7a3;
  return word + (isSyllable && (code - 0xac00) % 28 !== 0 ? closed : open);
}
