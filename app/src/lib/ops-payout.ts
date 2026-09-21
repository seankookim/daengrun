// ops-payout.ts — the arithmetic the ops console's payout screen does before it touches the wire.
//
// WHY THIS IS A MODULE AND NOT THIRTY LINES INSIDE `app/ops/payout/[runner].tsx`: the number this
// computes is sent to the server as `p_amount_won`, and `ops_record_manual_payout` (0186 §C)
// compares it for **EQUALITY** against the net of the rows it locks. So this file is the only
// place in the client where an off-by-one is an operator staring at 「금액이 맞지 않아요」 with no
// idea which row moved. `app/test/ops-payout.test.cjs` pins it against the REAL compiled source.
//
// 🔴 **THIS IS NOT THE ENFORCEMENT POINT AND MUST NEVER BE READ AS ONE.** 0186 §C recomputes the
//   net from the LOCKED rows and refuses any disagreement. What this file buys is that the number
//   on the screen is the number that gets sent — nothing more. If the two ever disagree, the
//   SERVER is right and `amount_mismatch` is the correct outcome, not a bug to paper over: the
//   case where they differ is precisely the case where the operator's screen has gone stale
//   (another terminal paid a row between the read and the tap), and refusing is the answer.
//
// ⚠ **A NEGATIVE ROW IS A REAL ROW.** `ops_runner_payout_detail` (0198 §B) deliberately carries
//   individual rows whose net is ≤ 0, because 0186 §B's `having sum > 0` is a PER-RUNNER clause
//   and the aggregate an operator is looking at already includes them. So nothing here filters by
//   sign, and `sum` is a plain sum: dropping a negative row would make the screen's total exceed
//   the server's and turn a correct batch into a refusal.
//
// ⚠ NOTHING HERE READS THE DEVICE CLOCK. This module does no date work at all; the console's dates
//   go through `kst.ts` in the screen (fixed +9, no Intl — Korea has no DST). `check-device-clock`
//   is the gate.

/** One tickable row, exactly as `ops_runner_payout_detail()` hands it over. Structural on purpose
 *  so the pins can build one without importing the screen or the wire. */
export interface OpsPayoutRow {
  /** `ledger_items.id` — what goes into `p_ledger_item_ids`. */
  id: string;
  /** The row's own net in won. May be ZERO or NEGATIVE; see the header. */
  netWon: number;
}

/** Sum of the CHECKED rows, in won.
 *
 *  ⚠ A checked id that is not in `rows` contributes NOTHING and is not an error here — the screen
 *  cannot tick a row it did not render, and a stale id surviving a refresh is a real shape. It is
 *  `selectedIds()` that keeps the two in step, and the server that refuses the rest. */
export function checkedTotalWon(rows: readonly OpsPayoutRow[], checked: ReadonlySet<string>): number {
  let total = 0;
  for (const r of rows) if (checked.has(r.id)) total += r.netWon;
  return total;
}

/** The ids to send, in the order the rows were rendered.
 *
 *  ⚠ **INTERSECTED WITH `rows`, NEVER TAKEN FROM THE SET.** After a re-fetch the paid rows are
 *  gone from `rows` while their ids may still sit in the checked set; sending one would be
 *  `not_runner_item` or `already_paid` from a screen that looks correct. Deriving the ids from
 *  what is DRAWN keeps the batch equal to what the operator can see, which is also what makes the
 *  total and the ids describe the same set — 0186 §C compares them against each other. */
export function selectedIds(rows: readonly OpsPayoutRow[], checked: ReadonlySet<string>): string[] {
  return rows.filter((r) => checked.has(r.id)).map((r) => r.id);
}

/** Why a batch cannot be submitted, or null when it can.
 *
 *  These mirror 0186 §C's own refusals (`no_items`, `bad_amount`) so the operator learns the
 *  reason from the button instead of from a round trip — the server still enforces every one of
 *  them and is the authority. */
export type BatchRefusal = 'no_items' | 'bad_amount';

/** ⚠ **THE ZERO/NEGATIVE GUARD IS THE SERVER'S RULE, NOT A UI PREFERENCE.** `ops_record_manual_payout`
 *  raises `bad_amount` on `p_amount_won <= 0` — 「a zero or negative transfer is not a payout」 —
 *  so a selection of rows that nets to zero is a batch the server will never accept. Saying so on
 *  the button is the difference between a dead-looking screen and a refusal with a reason. */
export function batchRefusal(rows: readonly OpsPayoutRow[], checked: ReadonlySet<string>): BatchRefusal | null {
  const ids = selectedIds(rows, checked);
  if (ids.length === 0) return 'no_items';
  if (checkedTotalWon(rows, checked) <= 0) return 'bad_amount';
  return null;
}

/** The Korean for each local refusal. The same strings the server's tokens map to in `api.ts`, so
 *  an operator reads one sentence whichever side refused. */
export const BATCH_REFUSAL_KO: Record<BatchRefusal, string> = {
  no_items: '지급할 행을 하나 이상 선택해주세요',
  bad_amount: '선택한 행의 합계가 0원 이하예요 — 이체할 금액이 있어야 기록할 수 있어요',
};

/**
 * 원 with thousands separators, e.g. `-1,200원`.
 *
 * ⚠ **HAND-ROLLED, AND `toLocaleString` IS DELIBERATELY NOT USED.** It is ambiguous between
 *   `Date` and `Number` and this repo's `check-device-clock` gate does not match it for exactly
 *   that reason (CLAUDE.md records the measurement: 60 call sites, zero passing a date option).
 *   A money formatter that reaches for it invites the next reader to reach for it on a date.
 * ⚠ The SIGN is rendered, never dropped. A negative row is a real row (see the header), and a
 *   screen that printed `800원` for `-800` would be showing an operator the opposite of the truth
 *   on a money surface.
 * ⚠ A non-finite input renders as `—`, never as `NaN원`: a number we do not have is absent, not
 *   zero. Loading is not 0 — the screen that has not read yet prints its own loading line rather
 *   than calling this with a placeholder.
 */
export function wonLabel(n: number): string {
  if (!Number.isFinite(n)) return '—';
  const neg = n < 0;
  const digits = String(Math.abs(Math.trunc(n)));
  let out = '';
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ',';
    out += digits[i];
  }
  return `${neg ? '-' : ''}${out}원`;
}

/** 「3건 · 24,000원」 — the one line the primary button and the header both print, so the count and
 *  the sum can never disagree between them. */
export function batchSummary(rows: readonly OpsPayoutRow[], checked: ReadonlySet<string>): string {
  const n = selectedIds(rows, checked).length;
  return `${n}건 · ${wonLabel(checkedTotalWon(rows, checked))}`;
}
