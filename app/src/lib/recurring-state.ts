// 반복 러닝 (recurring_series) — what a series row MEANS on screen, as a pure function.
//
// Why this is its own module and not three copies inside three screens: `owner/report.tsx`,
// `owner/schedule.tsx` and `owner/home.tsx` all now offer the same loop (make this booking weekly ·
// see what the weekly booking actually is · restart it when it is stopped), and a sentence that
// says 「매주 수요일 19:30」 is a CLAIM about what the hourly cron will do. The claim has to be
// checkable, so the arithmetic lives here where `test/recurring-state.test.cjs` can reach it and
// the screens only render what comes back.
//
// ══ WHAT THE SERVER ACTUALLY DOES, MEASURED — every line below is bound to one of these ══
//
//  ① `generate_recurring_bookings()` (latest definition `0180_cron_dog_lock_and_tick_split.sql:82`)
//     reads exactly ONE weekday per series: `v_dow := (s.rule->'weekdays'->>0)::int` (0180:109).
//     `rule.weekdays` is an ARRAY and `create_recurring_series` writes a one-element array
//     (`0077:53`), but nothing enforces that. So this module renders the FIRST weekday only —
//     printing a second one would promise a run the cron will never create.
//  ② A series whose `rule` has no `weekdays[0]` or no `time` is skipped entirely (`0180:111`,
//     `continue`). That is a dead series, and it is said as one — never as 「매주」 with a blank.
//  ③ The cron's window is 72 hours (`0180:120`), so a row for next week does not exist yet. The
//     copy for 「no upcoming booking」 states that rule instead of implying something is wrong.
//  ④ `paused` gates the whole sweep (`0180:107`, `where not paused`). ⚠ MEASURED AND LOAD-BEARING:
//     **NOTHING ON THE SERVER EVER SETS `paused = true`.** The money gate at `0180:174-181` writes
//     a notification titled 「반복 예약 일시 중지」 and `continue`s — it does not touch the column
//     (grep `set paused` across every migration: zero hits; the only writer of the column is the
//     client's own `pauseRecurringSeries`, and `0111:193` grants the client exactly that one
//     column). So a paused series was paused BY ITS OWNER, and this module must not attribute it
//     to a payment problem. The notification's title says 일시 중지 and the state does not — the
//     copy here follows the STATE.
//  ⑤ The money gate itself is separately visible and is bound: the cron blocks on
//     `owner_has_unsettled_charge(s.owner_id)` (`0180:169`), and `my_unsettled_charge()`
//     (`0080:541`) is `owner_has_unsettled_charge(auth.uid())` — the same predicate for one's own
//     series. That is a real, readable reason for 「the series is on and nothing is appearing」,
//     and it is the reason the 「반복 예약 일시 중지」 notification now routes to /payments.
//     `null` means NOT ASKED or the read failed: unknown is never rendered as a problem.
//
// ⚠ Every instant that reaches a label goes through `kst.ts` (fixed +9, no Intl). `nowMs` is a
//    PARAMETER rather than a `Date.now()` inside, so the suite can pin a moment; the suite runs
//    under three zones and the labels are literal, so a device-clock leak reddens it.

import { kstCal, kstClock, kstMonthDay } from './kst';

/** 0=일 … 6=토, the `extract(dow …)` convention `create_recurring_series` writes (`0077:53`). */
export const WEEKDAY_KO = ['일', '월', '화', '수', '목', '금', '토'];

export interface SeriesFacts {
  /** `recurring_series.paused`. */
  paused: boolean;
  /** `rule.weekdays[0]` — the only one the cron reads (①). null = absent/unparseable. */
  weekday: number | null;
  /** `rule.time`, 'HH:MM' as the cron reads it (`0180:110`). null = absent. */
  time: string | null;
  /** The earliest non-terminal booking in this series, ISO. null = none exists yet. */
  nextBookingAt: string | null;
  /** `my_unsettled_charge()` — the cron's own debt gate (⑤). null = not asked / read failed. */
  unsettledCharge: boolean | null;
}

export interface SeriesView {
  /** The one line that states what the series IS. Never empty. */
  line: string;
  /** A second line, only when there is something true to add. null = say nothing. */
  note: string | null;
  /** Does the 반복 다시 시작 control belong on screen? */
  canResume: boolean;
  /** Is this series structurally dead (② — the cron skips it every sweep)? */
  broken: boolean;
}

// ── copy ───────────────────────────────────────────────────────────────────────────────────────
export const CREATE_LABEL = '매주 반복으로 바꾸기';
export const CREATE_SUB = '같은 요일·시간에 자동으로 예약돼요';
export const CREATE_BUSY = '반복으로 바꾸는 중…';
export const RESUME_LABEL = '반복 다시 시작';
export const RESUME_BUSY = '다시 시작하는 중…';
/** ③ — the 72h window, stated rather than implied. */
export const PENDING_NEXT = '다음 예약은 3일 전에 자동으로 잡혀요';
/** ④ — the owner's own pause. No payment cause is claimed, because the column has no other writer. */
export const PAUSED_NOTE = '반복이 멈춰 있어요 — 다시 시작하면 다음 주부터 자동으로 잡혀요';
/** ⑤ — the cron's debt gate, in the owner's words, pointing at the screen that fixes it. */
export const DEBT_NOTE = '결제 문제로 자동 예약이 멈춰 있어요 — 결제 관리에서 해결해주세요';
/** ② — a rule the cron cannot read. Said as broken, never as 「매주」 with a hole in it.
 *  ⚠ It NAMES THE SCREEN that has the 해지 control. This block renders on three screens and only
 *  the schedule sheet carries 매주 반복 해지, so a bare 「해지하고 다시 만들어주세요」 would be an
 *  instruction with no control in reach on two of them — the dead-button law in sentence form. */
export const BROKEN_LINE = '반복 일정을 읽지 못했어요 — 내 일정에서 해지하고 다시 만들어주세요';

/** The refusals `create_recurring_series` can raise, token → Korean (`0077:39`, `0077:42`,
 *  `0077:44`). `not_found` and `forbidden` are the same sentence to a person — they differ only in
 *  whether the row exists — but they are listed apart so a changed server token fails to match
 *  instead of silently folding to the generic line. */
export const CREATE_SERIES_TOKENS: Record<string, string> = {
  not_signed_in: '세션이 만료된 것 같아요 — 다시 로그인해주세요',
  not_found: '이 예약을 찾을 수 없어요',
  forbidden: '이 예약의 반복을 만들 수 없어요',
};

const hhmm = (t: string): boolean => /^([01]\d|2[0-3]):[0-5]\d$/.test(t);

/** 「9월 30일 19:30」 — the booking's OWN KST instant, so a rescheduled row states its real time
 *  rather than inheriting the rule's. */
const whenLabel = (iso: string): string | null => {
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) return null;
  const c = kstCal(ms);
  return `${kstMonthDay(c)} ${kstClock(c)}`;
};

/**
 * What to draw for a series the owner owns. `nowMs` decides only one thing: whether
 * `nextBookingAt` is still in the future — a read a few seconds stale must not print a past
 * instant under the words 다음 예약.
 */
export function describeSeries(f: SeriesFacts, nowMs: number): SeriesView {
  // ② the cron skips this row every sweep. Nothing else on this view can be true, so nothing else
  //    is said — including 다시 시작, which would restart a series that still creates nothing.
  if (f.weekday == null || f.weekday < 0 || f.weekday > 6 || !f.time || !hhmm(f.time)) {
    return { line: BROKEN_LINE, note: null, canResume: false, broken: true };
  }

  const base = `매주 ${WEEKDAY_KO[f.weekday]}요일 ${f.time}`;
  const nextMs = f.nextBookingAt ? Date.parse(f.nextBookingAt) : NaN;
  const next = !Number.isNaN(nextMs) && nextMs > nowMs && f.nextBookingAt
    ? whenLabel(f.nextBookingAt)
    : null;

  // A paused series creates nothing — but a booking the cron already made BEFORE the pause is not
  // cancelled by pausing (the 해지 confirmation says so in as many words), so it is still named.
  // When there is none, the 다음 예약 clause is omitted rather than filled with 「없음」: the note
  // below already says why there is nothing coming.
  if (f.paused) {
    return {
      line: next ? `${base} · 다음 예약 ${next}` : base,
      note: PAUSED_NOTE,
      canResume: true,
      broken: false,
    };
  }

  return {
    line: `${base} · ${next ? `다음 예약 ${next}` : PENDING_NEXT}`,
    // ⑤ only `true` speaks. `null` (not asked / failed) and `false` both say nothing — an unknown
    //   is never rendered as a problem, and a 「문제 없음」 line would be noise on a healthy series.
    note: f.unsettledCharge === true ? DEBT_NOTE : null,
    canResume: false,
    broken: false,
  };
}

/** `rule` as it arrives from PostgREST (jsonb). Parsing lives here so the screen never reaches
 *  into an untyped blob, and so ① — 「the first weekday only」 — has exactly one implementation. */
export function ruleWeekdayAndTime(rule: unknown): { weekday: number | null; time: string | null } {
  const r = (rule ?? {}) as { weekdays?: unknown; time?: unknown };
  const list = Array.isArray(r.weekdays) ? r.weekdays : [];
  const raw = list.length > 0 ? Number(list[0]) : NaN;
  const weekday = Number.isInteger(raw) && raw >= 0 && raw <= 6 ? raw : null;
  const time = typeof r.time === 'string' && hhmm(r.time) ? r.time : null;
  return { weekday, time };
}
