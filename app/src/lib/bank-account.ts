// 정산 계좌 — the pure half: the bank list, the three validations, and the mask.
//
// Everything here is a MIRROR of `supabase/migrations/0194_bank_account_registration.sql`, and
// the two copies are drift-pinned in BOTH directions by `app/test/bank-account.test.cjs`, which
// parses the migration's own seed block and its refusal tokens and compares them to this file.
// That is 0189's shape for `_noti_urgent_noti_titles`, and it is why the picker can render
// instantly with no RPC and no loading state without the two lists diverging.
//
// 🔴 THIS IS NOT THE ENFORCEMENT POINT AND MUST NEVER BE READ AS ONE. The server validates
// everything again in `set_my_bank_account` and refuses by name; what this file buys is that a
// runner sees 「계좌번호를 다시 확인해주세요」 while typing instead of after a round trip. If the two
// ever disagree, the SERVER is right and the test above is what tells us.
//
// ⚠ `bank` is a 금융결제원 CODE, never a label. A label is what the person reads; a code is what
// survives a rename (대구은행 → iM뱅크 in 2024), and `bank_accounts.bank` stores the code.

export type Bank = { readonly code: string; readonly label: string };

/** The banks a 정산 계좌 can sit at. Mirrors `bank_codes` (0194 §B), in the same order. */
export const BANKS: readonly Bank[] = [
  { code: '004', label: 'KB국민은행' },
  { code: '088', label: '신한은행' },
  { code: '020', label: '우리은행' },
  { code: '081', label: '하나은행' },
  { code: '011', label: 'NH농협은행' },
  { code: '003', label: 'IBK기업은행' },
  { code: '090', label: '카카오뱅크' },
  { code: '092', label: '토스뱅크' },
  { code: '089', label: '케이뱅크' },
  { code: '007', label: '수협은행' },
  { code: '023', label: 'SC제일은행' },
  { code: '027', label: '한국씨티은행' },
  { code: '031', label: 'iM뱅크' },
  { code: '032', label: '부산은행' },
  { code: '039', label: '경남은행' },
  { code: '034', label: '광주은행' },
  { code: '037', label: '전북은행' },
  { code: '035', label: '제주은행' },
  { code: '002', label: 'KDB산업은행' },
  { code: '045', label: '새마을금고' },
  { code: '048', label: '신협' },
  { code: '071', label: '우체국' },
];

export function bankLabel(code: string | null | undefined): string | null {
  if (!code) return null;
  return BANKS.find((b) => b.code === code)?.label ?? null;
}

/** The account-number bounds, mirroring 0194 §F②. Both ends INCLUSIVE. */
export const ACCOUNT_MIN_DIGITS = 10;
export const ACCOUNT_MAX_DIGITS = 16;
export const HOLDER_MAX = 60;

/**
 * The digits of an account number, or null when the input is not an account number at all.
 *
 * ⚠ THE SHAPE IS CHECKED BEFORE THE STRIP, NOT AFTER — the same order as the server, and the
 * reason is the one arm of the SQL suite that matters most here. Stripping every non-digit first
 * would turn 「계좌 1234567890 입니다」 into a perfectly valid-looking `1234567890` and store a
 * destination the runner never typed. Digits, with `-` or spaces BETWEEN them, and nothing else.
 *
 * ⚠ The leading `.trim()` is matched by `btrim(p_account)` in `set_my_bank_account` (0194 §F②).
 * It was not, for one draft: this side trimmed and the server did not, so a pasted 「 1234567890 」
 * passed here and was refused there — the person told 「숫자 10~16자리예요」 while looking at a
 * field holding exactly ten digits. Of the two directions a mirror can drift, accepting what the
 * server refuses is the one that produces an unresolvable error, and the pair is now pinned on
 * both sides (here, and suite 225's B6).
 */
export function normalizeAccountDigits(input: string | null | undefined): string | null {
  if (typeof input !== 'string') return null;
  const raw = input.trim();
  if (!/^[0-9]([0-9 -]*[0-9])?$/.test(raw)) return null;
  return raw.replace(/[^0-9]/g, '');
}

/** `••••` + the last four digits — the same string the server composes in `my_bank_account()`. */
export const MASK_PREFIX = '••••';
export function maskAccount(digits: string | null | undefined): string | null {
  if (typeof digits !== 'string') return null;
  const d = digits.replace(/[^0-9]/g, '');
  if (d.length < 4) return null;
  return MASK_PREFIX + d.slice(-4);
}

export type BankAccountRefusal =
  | 'not_signed_in'
  | 'not_runner'
  | 'bad_bank'
  | 'bad_account'
  | 'bad_holder'
  | 'payout_owed'
  // ⚠ ops-surface tokens. No screen in this app raises them — `ops_bank_account` is a PostgREST
  // call an operator makes. They are here because the drift pin in `bank-account.test.cjs` asserts
  // this vocabulary is EXACTLY what 0194 can raise, and an exemption list is the thing that rots.
  | 'not_ops'
  | 'no_runner';

/**
 * The same three checks `set_my_bank_account` runs, in the same order, returning the same token.
 * `null` means 「the server will not refuse this for a reason we can see from here」.
 */
export function validateBankAccount(input: {
  bank?: string | null;
  account?: string | null;
  holder?: string | null;
}): BankAccountRefusal | null {
  if (!input.bank || !BANKS.some((b) => b.code === input.bank)) return 'bad_bank';
  const digits = normalizeAccountDigits(input.account);
  if (digits === null) return 'bad_account';
  if (digits.length < ACCOUNT_MIN_DIGITS || digits.length > ACCOUNT_MAX_DIGITS) return 'bad_account';
  const holder = (input.holder ?? '').trim();
  if (holder === '' || holder.length > HOLDER_MAX) return 'bad_holder';
  return null;
}

/**
 * Korean copy for every refusal the server can raise on this surface.
 *
 * ⚠ Each one names something the person can DO — 0115 §B.1's rule that a refusal must point at
 * something the user can themselves resolve. `payout_owed` is the exception that proves it: there
 * is nothing they can do except wait, so the sentence says why rather than pretending otherwise.
 */
export const BANK_ERROR_KO: Readonly<Record<BankAccountRefusal, string>> = {
  not_signed_in: '세션이 만료된 것 같아요 — 다시 로그인해주세요',
  not_runner: '러너 계정에서만 정산 계좌를 등록할 수 있어요',
  bad_bank: '은행을 다시 선택해주세요',
  bad_account: '계좌번호를 다시 확인해주세요 — 숫자 10~16자리예요',
  bad_holder: '예금주 이름을 입력해주세요',
  payout_owed: '지급 대기 중인 정산이 있어 계좌를 삭제할 수 없어요',
  not_ops: '이 계좌를 볼 수 있는 권한이 없어요',
  no_runner: '러너를 지정해주세요',
};

/**
 * Not a refusal — a STATE. `my_bank_account()` returns a NULL mask when the stored row cannot be
 * decrypted, and 0194 §F④ deliberately does NOT raise on that path (a raise would roll back its
 * own journal row). So this copy lives outside `BANK_ERROR_KO`, which the drift test pins by
 * EQUALITY against the tokens the migration can actually raise.
 */
export const ACCOUNT_UNREADABLE_KO = '저장된 계좌를 읽지 못했어요 — 다시 등록해주세요';

/** The note the screen carries under its title. Says what the product does NOT do, on purpose. */
export const BANK_NOTE =
  '입력한 계좌는 암호화해서 보관하고, 정산할 때만 사용해요 · 예금주 확인 절차는 아직 없어요';
