// ═══════════ 0215 — 후보 슬롯을 만드는 한 벌 (offered windows → slot starts) ═══════════
//
// WHY THIS IS A PURE MODULE AND NOT TWO COPIES IN TWO SCREENS. Before 0215 the candidate loop was
// written out TWICE — `runner-profile/[id].tsx:174` and `owner/reschedule.tsx:131` — and the two
// had already drifted once: `runner-profile` verified every candidate against 60 minutes while
// `reschedule` had been corrected to the real duration (codex, 2026-08-21, the comment is still in
// that file). A rule copied into two screens gets fixed in one of them. And a `.tsx` route module
// is unreachable from `app/test/*.cjs`, so the duplicated version could not be tested at all.
//
// WHAT CHANGED IN 0215. Both screens used to enumerate candidates from `runner_availability_rules`
// ALONE and only then verify each one with `checkSlot`. That is why a 추가 근무 (`extra`) window
// could never be offered: `is_slot_available` said TRUE for it and no screen ever asked, because
// the weekday had no grid row to enumerate from. The server-side reader is
// `runner_offered_slots(p_runner, p_from, p_to)` (migration 0215); this module turns its windows
// into the start times a screen draws.
//
// 🔴 THE LAYERING, because it decides what may be changed here. The server's list is the CALENDAR
// layer only — weekly grid ∪ `extra` − `blackout` days. Bookings, holds and the daily cap stay
// with the per-slot `checkSlot`, which both screens still run on every candidate and which is
// still the FINAL gate. So this module may narrow what is offered; it must never widen it.

import type { KstCal } from './kst';

export type OfferedSource = 'grid' | 'extra';

/** One open window on one KST day, exactly as `runner_offered_slots` returns it. */
export interface OfferedWindow {
  /** KST calendar date, `YYYY-MM-DD` — the server's own `day` column, used verbatim as a key. */
  day: string;
  /** minutes from KST midnight, inclusive lower bound */
  startMin: number;
  /** minutes from KST midnight, exclusive upper bound (≤ 1440) */
  endMin: number;
  source: OfferedSource;
}

/** One candidate start time on one day. */
export interface OfferedSlot {
  startMin: number;
  /** 'extra' ONLY when no weekly-grid window covers this slot — see `slotStartsForDay`. */
  source: OfferedSource;
}

export interface AvailRuleLike { weekday: number; startMin: number; endMin: number }

const pad2 = (n: number): string => (n < 10 ? '0' + n : String(n));

/**
 * The server's day vocabulary, built from a KST calendar piece.
 *
 * ⚠ This is NOT `kstKey()` and must not be replaced by it: `kstKey` is a device-independent
 * EQUALITY key (`2026-9-3`, month 0-based, unpadded) while this is the WIRE shape of
 * `runner_offered_slots.day` (`2026-10-03`). They are different strings for the same day and
 * swapping one for the other makes every window silently fail to match.
 *
 * ⚠ It takes a `KstCal` rather than a `Date` on purpose. `d.getFullYear()/getMonth()/getDate()`
 * are DEVICE-LOCAL: on a phone that is not Asia/Seoul they name the wrong calendar day for exactly
 * the evening slots this product sells. `kstCal()` has already done the +9 arithmetic.
 */
export const kstDayKey = (c: KstCal): string => `${c.y}-${pad2(c.m + 1)}-${pad2(c.d)}`;

/** The windows the server returned for one KST day. */
export const windowsForDay = (windows: OfferedWindow[], dayKey: string): OfferedWindow[] =>
  windows.filter((w) => w.day === dayKey);

/**
 * THE FALLBACK, and the only thing it is for: this build is ahead of migration 0215, so
 * `runner_offered_slots` does not exist yet and `fetchOfferedSlots` returned `null`. Then the
 * weekly grid is the whole calendar — which is exactly what both screens did before 0215, so the
 * fallback is the OLD behaviour rather than a new guess: 추가 근무 windows are not offered and a
 * 휴가 is still honoured, because `checkSlot` refuses each candidate one by one.
 *
 * ⚠ It is NOT a general-purpose grid expander. Once 0215 is deployed the list comes from the
 * server, and a screen that keeps computing its own would be a second definition of availability.
 */
export const windowsFromRules = (rules: AvailRuleLike[], cal: KstCal): OfferedWindow[] => {
  const day = kstDayKey(cal);
  return rules
    .filter((r) => r.weekday === cal.wd)
    .map((r) => ({ day, startMin: r.startMin, endMin: r.endMin, source: 'grid' as const }));
};

/**
 * Candidate start times for one day, from that day's windows.
 *
 * THE THREE RULES, and each one is load-bearing:
 *
 *  ① **A slot must fit ENTIRELY inside ONE window** — never across two adjacent ones. That looks
 *     like a missed opportunity (a 09:00–12:00 grid window beside a 12:00–14:00 추가 근무 does not
 *     offer 11:30) and it is deliberate: `is_slot_available` §1 also requires ONE row to contain
 *     the slot, so merging the windows first would make this list offer times the server refuses —
 *     the one direction that must never happen, because it puts a 가능 label on a booking that
 *     will be rejected.
 *  ② **Starts are stepped from EACH window's own start**, which is what both screens did before
 *     0215 (`for (let m = r.startMin; m + durMin <= r.endMin; m += 60)`). Keeping it means a
 *     runner with no exceptions sees exactly the grid they saw yesterday.
 *  ③ **The same start minute from two windows collapses to ONE slot** — otherwise a 추가 근무 that
 *     overlaps the grid would draw the same button twice.
 *
 * THE LABEL: `source` is `'extra'` only when NO grid window CONTAINS the whole slot. So the chip
 * means 「this time exists only because the runner opened it for this one day」 — which is what
 * `runner/availability.tsx` promises them — rather than 「this button came out of the extra
 * branch」, which would put a 추가 근무 chip on an ordinary hour that an extra happened to overlap.
 */
export const slotStartsForDay = (
  windows: OfferedWindow[],
  dayKey: string,
  durMin: number,
  stepMin = 60,
): OfferedSlot[] => {
  if (!(durMin > 0) || !(stepMin > 0)) return [];
  const today = windowsForDay(windows, dayKey);
  const starts = new Set<number>();
  for (const w of today) {
    for (let m = w.startMin; m + durMin <= w.endMin; m += stepMin) starts.add(m);
  }
  const grid = today.filter((w) => w.source === 'grid');
  return [...starts]
    .sort((a, b) => a - b)
    .map((m) => ({
      startMin: m,
      source: grid.some((w) => w.startMin <= m && m + durMin <= w.endMin)
        ? ('grid' as const)
        : ('extra' as const),
    }));
};

/** 추가 근무 칩. `null` = 평소 근무라 칩을 달지 않는다 (없는 배지를 그리지 않는다). */
export const EXTRA_CHIP_KO = '추가 근무';
export const slotChip = (s: OfferedSlot): string | null =>
  s.source === 'extra' ? EXTRA_CHIP_KO : null;
