// ═══════════ 0215 → 0221 — 후보 슬롯을 만드는 한 벌 (offered spans → slot starts) ═══════════
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
// `runner_offered_slots(p_runner, p_from, p_to)`; this module turns its windows into the start
// times a screen draws.
//
// 🔴 WHAT CHANGED IN 0221, AND IT REVERSES A RULE THIS FILE USED TO ARGUE FOR. 0219 made
// `is_slot_available` §1 the UNION of a runner's windows, merged where they touch — so a
// 09:00–12:00 weekly rule beside a 12:00–14:00 추가 근무 accepts 11:00–12:05. This module still
// required the whole duration inside ONE window, and `runner_offered_slots` still returned the two
// windows separately, so **an owner could never be offered a slot the server would accept**
// (Codex, 2026-09-25 server verdict #1). 0221 makes the server emit the MERGED spans, and this
// module now accepts a span. The comment that used to sit at rule ① — 「merging the windows first
// would make this list offer times the server refuses」 — was true against 0203's judge and became
// false the moment 0219 landed; it is recorded here rather than quietly deleted, because
// documenting a fix and failing to make one look identical to every later grep.
//
// 🔴 THE LAYERING, because it decides what may be changed here. The server's list is the CALENDAR
// layer only — weekly grid ∪ `extra` − `blackout` days, merged. Bookings, holds and the daily cap
// stay with the per-slot `checkSlot`, which both screens still run on every candidate and which is
// still the FINAL gate. So this module may narrow what is offered; it must never widen it.

import type { KstCal } from './kst';

/** One window's provenance — unchanged meaning since 0215. */
export type OfferedSource = 'grid' | 'extra';
/** A merged span's SUMMARY: `mixed` when its constituents are not all of one kind [0221]. */
export type OfferedSpanSource = OfferedSource | 'mixed';

/** One constituent window of a span, in the span row's own day-relative minutes [0221]. */
export interface OfferedSegment {
  startMin: number;
  endMin: number;
  source: OfferedSource;
}

/** One open SPAN on one KST day, exactly as `runner_offered_slots` returns it. */
export interface OfferedWindow {
  /** KST calendar date, `YYYY-MM-DD` — the server's own `day` column, used verbatim as a key. */
  day: string;
  /**
   * Minutes from this day's KST midnight, inclusive lower bound.
   * ⚠ **MAY BE NEGATIVE** [0221]: a span that started the previous day is re-anchored here so the
   * second day of a cross-midnight pair is not an empty screen.
   */
  startMin: number;
  /** Minutes from this day's KST midnight, exclusive upper bound. ⚠ **MAY EXCEED 1440** [0221]. */
  endMin: number;
  /** A summary of `segments`; the 추가 근무 chip is NOT computed from it — see `slotStartsForDay`. */
  source: OfferedSpanSource;
  /**
   * Every constituent of the span, ascending, covering `[startMin, endMin)` exactly [0221].
   * ⚠ May be absent/empty when the deployed function still has 0215's four-column shape — see
   * `segmentsOf`. It is never merged away: the chip needs to know WHERE the grid part is.
   */
  segments?: OfferedSegment[];
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

/** The spans the server returned for one KST day. */
export const windowsForDay = (windows: OfferedWindow[], dayKey: string): OfferedWindow[] =>
  windows.filter((w) => w.day === dayKey);

/**
 * 🔴 THE DEPLOY-SKEW SEAM, and it is the reason `segments` is optional rather than required.
 * A build carrying 0221 can meet a server that has only 0215's FOUR-column function (the push is
 * one command behind, `rpc-skew.ts`). That row is a single UNMERGED window, so reading it as a
 * span whose only segment is itself reproduces the pre-0221 behaviour exactly: nothing merges,
 * nothing widens, and the 추가 근무 chip keeps its old answer. That is the NARROW direction, which
 * is the only safe one for a list the server has the last word on.
 *
 * ⚠ `source: 'mixed'` cannot occur on that path and is mapped to `'extra'` here for the chip's
 * purposes only — a span whose kinds are mixed is not wholly ordinary work, and the grid-union
 * test below is what actually decides the label, so this fallback never reaches a real decision.
 */
export const segmentsOf = (w: OfferedWindow): OfferedSegment[] =>
  w.segments && w.segments.length > 0
    ? w.segments
    : [{ startMin: w.startMin, endMin: w.endMin, source: w.source === 'grid' ? 'grid' : 'extra' }];

/** Merge `[start, end)` intervals that overlap or touch. Same predicate as 0221's SQL. */
const mergeIntervals = (xs: { startMin: number; endMin: number }[]): { s: number; e: number }[] => {
  const sorted = [...xs].sort((a, b) => a.startMin - b.startMin || a.endMin - b.endMin);
  const out: { s: number; e: number }[] = [];
  for (const x of sorted) {
    const last = out[out.length - 1];
    if (last && x.startMin <= last.e) { if (x.endMin > last.e) last.e = x.endMin; }
    else out.push({ s: x.startMin, e: x.endMin });
  }
  return out;
};

/**
 * THE FALLBACK, and the only thing it is for: this build is ahead of migration 0215, so
 * `runner_offered_slots` does not exist yet and `fetchOfferedSlots` returned `null`. Then the
 * weekly grid is the whole calendar — which is exactly what both screens did before 0215, so the
 * fallback is the OLD behaviour rather than a new guess: 추가 근무 windows are not offered and a
 * 휴가 is still honoured, because `checkSlot` refuses each candidate one by one.
 *
 * ⚠ It does NOT merge adjacent rules, deliberately [0221]. The fallback's contract is 「what the
 * screen did before 0215」, and narrowing is always safe: a seam the server would accept is simply
 * not offered until the push lands. Widening here would be the one direction that paints 가능 on a
 * booking the server rejects, and this path has no server to check itself against.
 *
 * ⚠ It is NOT a general-purpose grid expander. Once the function is deployed the list comes from
 * the server, and a screen that keeps computing its own would be a second definition of
 * availability.
 */
export const windowsFromRules = (rules: AvailRuleLike[], cal: KstCal): OfferedWindow[] => {
  const day = kstDayKey(cal);
  return rules
    .filter((r) => r.weekday === cal.wd)
    .map((r) => ({
      day,
      startMin: r.startMin,
      endMin: r.endMin,
      source: 'grid' as const,
      segments: [{ startMin: r.startMin, endMin: r.endMin, source: 'grid' as const }],
    }));
};

/**
 * Candidate start times for one day, from that day's spans.
 *
 * THE FOUR RULES, and each one is load-bearing:
 *
 *  ① **A slot must fit entirely inside ONE SPAN** — which, since 0221, is the merged union of the
 *     windows the runner opened. `is_slot_available` §1 (0219) asks exactly this, so the two agree
 *     by construction rather than by coincidence. Before 0221 this rule said 「inside ONE WINDOW」
 *     and that was the defect Codex #1 named: the server accepted 11:00–12:05 across a
 *     09:00–12:00 / 12:00–14:00 seam and no screen could offer it.
 *  ② **Starts are stepped from EACH SEGMENT's own start**, not from the span's start alone. Both
 *     screens did this before 0215 (`for (let m = r.startMin; …; m += 60)`) and dropping it would
 *     silently RETIRE offers: a 추가 근무 beginning at 12:10 beside a grid window ending at 12:10
 *     contributes the 12:10 start only through its own phase. A start is still kept only when the
 *     whole duration fits in the SPAN, so this widens the grid of starts, never the acceptance.
 *  ③ **A start always lies on the day being drawn** — `0 <= m < 1440`. A span may run past
 *     midnight and the slot may END on the next day (that is the point of 0219), but the button
 *     belongs to one day and `kstInstant(cal, h, m)` has no hour 24.
 *  ④ **The same start minute collapses to ONE slot** — otherwise a 추가 근무 overlapping the grid
 *     would draw the same button twice.
 *
 * THE LABEL, unchanged in meaning since 0215 and now computed from `segments`: `source` is
 * `'extra'` only when no GRID interval CONTAINS the whole slot, where the grid intervals are the
 * MERGED union of every grid segment on that day. So the chip means 「this time exists only because
 * the runner opened it for this one day」 — which is what `runner/availability.tsx` promises them —
 * rather than 「this button came out of the extra branch」, which would put a 추가 근무 chip on an
 * ordinary hour that an extra happened to overlap. Merging the grid segments first is what keeps
 * that answer right across a seam: two ADJACENT grid windows are ordinary work on both sides, and
 * a slot crossing their boundary must not sprout a badge.
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
    const lo = Math.max(0, w.startMin);
    for (const sg of segmentsOf(w)) {
      // ② phase comes from the segment; ③ the first candidate is the first one on this day.
      let m = sg.startMin;
      if (m < lo) m += Math.ceil((lo - m) / stepMin) * stepMin;
      for (; m + durMin <= w.endMin && m < 1440; m += stepMin) starts.add(m);
    }
  }
  // THE LABEL: the merged union of every grid segment drawn on this day.
  const gridUnion = mergeIntervals(
    today.flatMap((w) => segmentsOf(w).filter((s) => s.source === 'grid')),
  );
  return [...starts]
    .sort((a, b) => a - b)
    .map((m) => ({
      startMin: m,
      source: gridUnion.some((iv) => iv.s <= m && m + durMin <= iv.e)
        ? ('grid' as const)
        : ('extra' as const),
    }));
};

/** 추가 근무 칩. `null` = 평소 근무라 칩을 달지 않는다 (없는 배지를 그리지 않는다). */
export const EXTRA_CHIP_KO = '추가 근무';
export const slotChip = (s: OfferedSlot): string | null =>
  s.source === 'extra' ? EXTRA_CHIP_KO : null;
