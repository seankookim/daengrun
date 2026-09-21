// 굿즈 수령 신청 양식 — pure, importless module (same shape as claim-status.ts / tier.ts).
// It lives here and not in api.ts because of the test: this repo's idiom is "bundle the REAL
// source with esbuild rather than a retyped copy", so the rules the cases pin are the rules that
// ship on runner/rewards.tsx. api.ts imports supabase and cannot be bundled that way.
//
// 🔴 THIS IS NOT THE GATE, AND SAYING SO IS THE POINT. `claim_gear_tx` (0195 §B) validates the
// same five facts server-side and refuses by name — `bad_recipient` / `bad_phone` / `bad_address`
// / `bad_postal`. A client check that a later build loosens, or that an older build never had, is
// not a security property; it is a COURTESY, so that a runner learns a postal code is five digits
// while they are still typing it rather than after a round trip. The server's refusal is still
// rendered when it arrives (rewards.tsx's failure state), because a validator agreeing with the
// server is not evidence the server agreed.
//
// ⚠ Deliberately NOT normalised here: the phone's hyphens. `formatPhone` proves this repo shows
// hyphens and stores digits, and the SERVER strips to digits (0195 §B ⑥) so that 010-1234-5678
// and 01012345678 cannot become two people. The client sends what the person typed and lets the
// one authority decide — two normalisers is how the two spellings drift apart.

export interface GearClaimForm {
  recipient: string;
  phone: string;
  address1: string;
  address2: string;
  postal: string;
}

export type GearClaimField = 'recipient' | 'phone' | 'address1' | 'postal';

/** The first field that is not yet fillable, or null when the form can be sent.
 *  Order matches the screen's field order so the message always points at the topmost problem —
 *  a validator that complains about the last field while the first is empty reads as random. */
export function gearClaimProblem(f: GearClaimForm): GearClaimField | null {
  if (f.recipient.trim() === '') return 'recipient';
  // 10~11 digits: 0133 §A's server CHECK on `profiles.phone` is the same shape, and 010 numbers
  // are 11 while the older 01X blocks are 10. Counting DIGITS (not characters) is what lets a
  // person type hyphens or spaces without being told off for it.
  const digits = f.phone.replace(/[^0-9]/g, '');
  if (digits.length < 10 || digits.length > 11) return 'phone';
  if (f.address1.trim() === '') return 'address1';
  // 우편번호 is exactly five digits nationwide since the 2015 도로명 renumbering. Not "at least"
  // and not "up to": a four-digit entry is the old 6-digit format's first half, which is the
  // single most likely wrong thing to type, and accepting it would post a box into a guess.
  // ⚠ Digits are extracted the same way the SERVER extracts them (0195 §B ⑥) rather than a
  // stricter way. A client that refuses what the server accepts is a second, undocumented rule —
  // and the one a person meets first, so it silently becomes the real one.
  if (!/^[0-9]{5}$/.test(f.postal.replace(/[^0-9]/g, ''))) return 'postal';
  return null;
}

export const gearClaimReady = (f: GearClaimForm): boolean => gearClaimProblem(f) === null;

/** What to say about the first problem. Korean, because a runner reads it. */
export const GEAR_CLAIM_PROBLEM_TEXT: Record<GearClaimField, string> = {
  recipient: '받는 분 이름을 입력해 주세요',
  phone: '연락처를 다시 확인해 주세요 (숫자 10~11자리)',
  address1: '주소를 입력해 주세요',
  postal: '우편번호는 숫자 5자리예요',
};

export const EMPTY_GEAR_CLAIM_FORM: GearClaimForm = {
  recipient: '', phone: '', address1: '', address2: '', postal: '',
};
