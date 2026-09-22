// 예외 일정 (휴가 · 다구간) — the pure half of the 0203 slice.
//
// Everything here is arithmetic and copy composition: no network, no React, no device clock. That
// is what lets `test/availability-exceptions.test.cjs` bundle the REAL source with esbuild and run
// it in three zones, the same idiom as `notification-prefs` / `handoff-escalation` / `kst`.
//
// ═══ WHY A MODULE AND NOT A FEW HELPERS IN THE SCREEN ═══
// Two of the three things below are CONTRACTS with `0203_availability_exceptions.sql`, not screen
// details, and a contract that lives only inside a .tsx is a contract no test can reach:
//   · the refusal vocabulary — the server raises `bad_kind` / `bad_range` / `range_too_long` /
//     `bad_window` / `note_too_long` / `too_many` / `not_runner` / `not_authenticated` /
//     `not_found`, and every one of them needs a Korean sentence. A token that reaches a person is
//     a database word in a Korean product (the `rpc-error.ts` class).
//   · the LIMITS — 90 days, one day per 추가 근무, `start_min < end_min`, 40-char note, 20 live
//     rows. The client re-checks them so a person is told before a round trip, and the SERVER
//     stays the authority: these numbers are a mirror, never the rule. If they drift apart the
//     server refuses and the screen shows its sentence — annoying, never wrong.
//   · 🔴 `extraIsShadowed` is a real product fact and not decoration: `is_slot_available` §2
//     evaluates the blackout arm INDEPENDENTLY of §1, so a 추가 근무 inside a 휴가 window never
//     opens a slot. Without this line the screen would list a row that does nothing, which is the
//     dead-element half of the honesty law.
//
// ⚠ NO `Date.now()`, NO `new Date()` ANYWHERE IN THIS FILE. Every function that needs 「today」
// takes it as a `YYYY-MM-DD` argument, and the one caller derives that from `kstCal(Date.now())`
// at the edge. That is what makes a three-zone run meaningful: a device-clock read inside here
// would be invisible in Seoul and wrong everywhere else.

import { KST_MS, KstCal, kstCal, kstDateLabel } from './kst';

export type ExceptionKind = 'blackout' | 'extra';

/** A row as the server stores it. `startsOn`/`endsOn` are INCLUSIVE KST dates, `YYYY-MM-DD`. */
export interface AvailException {
  id: string;
  kind: ExceptionKind;
  startsOn: string;
  endsOn: string;
  /** minutes from KST midnight — `extra` only; a blackout is whole days and carries null. */
  startMin: number | null;
  endMin: number | null;
  note: string | null;
}

/** What the sheet is about to send. Same shape minus the id the server assigns. */
export type ExceptionDraft = Omit<AvailException, 'id'>;

// ── the limits, mirrored from 0203 §C ─────────────────────────────────────────────────────────
/** inclusive span cap. 0203 checks `ends_on - starts_on <= 89`, i.e. 90 calendar days. */
export const MAX_RANGE_DAYS = 90;
export const MAX_NOTE_CHARS = 40;
export const MAX_LIVE_EXCEPTIONS = 20;
/** the grid's own floor/ceiling, so a 추가 근무 cannot be written outside a plausible day. */
export const DAY_MIN = 0;
export const DAY_MAX = 1440;

export type ExceptionRefusal =
  | 'not_authenticated' | 'not_runner' | 'bad_kind' | 'bad_range'
  | 'range_too_long' | 'bad_window' | 'note_too_long' | 'too_many' | 'not_found';

/** The server's tokens, each with the one sentence a person may read. Every sentence says what to
 *  DO where there is something to do — a refusal that only names the rule leaves the person
 *  holding a form they cannot fix. */
export const EXCEPTION_REFUSAL_KO: Record<ExceptionRefusal, string> = {
  not_authenticated: '로그인이 풀렸어요 — 다시 로그인한 뒤 시도해주세요',
  not_runner: '러너 등록을 마치면 예외 일정을 쓸 수 있어요',
  bad_kind: '휴가와 추가 근무 중 하나를 골라주세요',
  bad_range: '끝나는 날이 시작하는 날보다 빠를 수 없어요',
  range_too_long: `한 번에 ${MAX_RANGE_DAYS}일까지 정할 수 있어요 — 기간을 나눠 등록해주세요`,
  bad_window: '추가 근무는 하루 안에서 시작 시간이 끝나는 시간보다 빨라야 해요',
  note_too_long: `메모는 ${MAX_NOTE_CHARS}자까지 쓸 수 있어요`,
  too_many: `예외 일정은 ${MAX_LIVE_EXCEPTIONS}개까지 둘 수 있어요 — 지난 일정을 지우고 다시 시도해주세요`,
  not_found: '이미 지워진 일정이에요 — 목록을 새로고침할게요',
};

// ── YYYY-MM-DD arithmetic, with no clock anywhere ─────────────────────────────────────────────

const YMD_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** `YYYY-MM-DD` → a KST calendar piece at 00:00, or null when the string is not a real date.
 *  Built on `kstCal` rather than beside it, so the weekday here and the weekday on every other
 *  screen come from ONE arithmetic (kst.ts's whole reason for existing). */
export const calOfYmd = (ymd: string): KstCal | null => {
  const m = YMD_RE.exec(ymd ?? '');
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]) - 1;
  const d = Number(m[3]);
  if (mo < 0 || mo > 11 || d < 1 || d > 31) return null;
  const c = kstCal(Date.UTC(y, mo, d) - KST_MS);
  // round-trip guard: Date.UTC rolls 2026-02-31 into March rather than refusing it
  if (c.y !== y || c.m !== mo || c.d !== d) return null;
  return c;
};

/** A KST calendar piece → `YYYY-MM-DD`. The one place the server's date format is produced. */
export const ymdOfCal = (c: KstCal): string =>
  `${c.y}-${String(c.m + 1).padStart(2, '0')}-${String(c.d).padStart(2, '0')}`;

/** KST calendar-day serial. Two of these subtract to a day count; null for a bad date. */
export const dayIndexOfYmd = (ymd: string): number | null => {
  const c = calOfYmd(ymd);
  return c == null ? null : Math.floor(Date.UTC(c.y, c.m, c.d) / 86_400_000);
};

/** `YYYY-MM-DD` shifted by n calendar days (Korea has no DST, so a day is exactly 86400000ms). */
export const addDaysYmd = (ymd: string, n: number): string | null => {
  const c = calOfYmd(ymd);
  if (c == null) return null;
  return ymdOfCal(kstCal(Date.UTC(c.y, c.m, c.d) + n * 86_400_000 - KST_MS));
};

/** 「09:30」 — minutes from midnight as a 24h wall clock. The screen's grid uses this too, so the
 *  two halves of one page cannot print a time two different ways. */
export const hhmm = (min: number): string =>
  `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;

// ── validation — the server's rules, re-stated so a person hears them before a round trip ──────

export type ValidationResult = { ok: true } | { ok: false; reason: ExceptionRefusal; ko: string };

const refuse = (reason: ExceptionRefusal): ValidationResult =>
  ({ ok: false, reason, ko: EXCEPTION_REFUSAL_KO[reason] });

/**
 * ⚠ The ORDER matches 0203 §C exactly. That is deliberate: a draft that breaks two rules must be
 * told about the same one by both halves, or the sheet says 「fix the window」, the person fixes it,
 * and the server then says 「too long」 — two round trips to learn two things the first screen knew.
 */
export const validateDraft = (d: ExceptionDraft): ValidationResult => {
  if (d.kind !== 'blackout' && d.kind !== 'extra') return refuse('bad_kind');

  const a = dayIndexOfYmd(d.startsOn);
  const b = dayIndexOfYmd(d.endsOn);
  if (a == null || b == null || b < a) return refuse('bad_range');
  if (b - a > MAX_RANGE_DAYS - 1) return refuse('range_too_long');

  if (d.kind === 'extra') {
    if (a !== b) return refuse('bad_window');
    if (d.startMin == null || d.endMin == null) return refuse('bad_window');
    if (!Number.isFinite(d.startMin) || !Number.isFinite(d.endMin)) return refuse('bad_window');
    if (d.startMin < DAY_MIN || d.endMin > DAY_MAX) return refuse('bad_window');
    if (d.startMin >= d.endMin) return refuse('bad_window');
  } else if (d.startMin != null || d.endMin != null) {
    // A 휴가 carrying a window is refused rather than silently stripped: dropping it would save a
    // value the person typed and never show it again, which is the 「저장 안 된 값을 저장된 것처럼」
    // failure the booking-rules block on this same screen already argues against.
    return refuse('bad_window');
  }

  const note = (d.note ?? '').trim();
  if (note.length > MAX_NOTE_CHARS) return refuse('note_too_long');

  return { ok: true };
};

/** Rows that can still change an answer — 0203's cap counts exactly these (`ends_on >= today`). */
export const liveExceptions = (list: readonly AvailException[], todayYmd: string): AvailException[] => {
  const today = dayIndexOfYmd(todayYmd);
  if (today == null) return [...list];
  return list.filter((e) => {
    const end = dayIndexOfYmd(e.endsOn);
    return end == null || end >= today;
  });
};

/** True when the runner is already at the cap and the 추가 버튼 must say so instead of 409-ing. */
export const atExceptionCap = (list: readonly AvailException[], todayYmd: string): boolean =>
  liveExceptions(list, todayYmd).length >= MAX_LIVE_EXCEPTIONS;

// ── overlap, and the one place it means something ─────────────────────────────────────────────

/** Inclusive date-range intersection, in calendar days. Bad dates never overlap anything. */
export const rangesOverlap = (aS: string, aE: string, bS: string, bE: string): boolean => {
  const a1 = dayIndexOfYmd(aS); const a2 = dayIndexOfYmd(aE);
  const b1 = dayIndexOfYmd(bS); const b2 = dayIndexOfYmd(bE);
  if (a1 == null || a2 == null || b1 == null || b2 == null) return false;
  return a1 <= b2 && b1 <= a2;
};

/**
 * 🔴 Does a blackout swallow this 추가 근무?
 *
 * `is_slot_available` (0203 §D) runs its blackout gate INDEPENDENTLY of the weekly-grid/extra
 * gate, so a 휴가 covering the date wins and the `extra` row opens nothing. The screen says so on
 * the row rather than listing an element with no effect.
 *
 * Returns false for anything that is not an `extra` — a blackout overlapping another blackout is
 * a union and means nothing to anybody.
 *
 * ⚠ THERE IS NO `o.id !== ex.id` SELF-EXCLUSION HERE, AND ITS ABSENCE IS DELIBERATE. The first
 * draft carried one; a mutation that deleted it reddened NOTHING in any zone, and the reason is
 * that the conjunct is UNREACHABLE: `ex` is an `extra` by the guard on the line above, and the
 * `some` only considers rows whose kind is `blackout`, so `o` can never BE `ex`. A conjunct that
 * cannot fire reads as protection and is not — the same shape as a pin whose green licenses
 * nothing, one level down. The two kind checks are the whole rule, and the test pins each of them
 * with a mutation that genuinely reddens.
 */
export const extraIsShadowed = (ex: AvailException, all: readonly AvailException[]): boolean => {
  if (ex.kind !== 'extra') return false;
  return all.some((o) => o.kind === 'blackout'
    && rangesOverlap(ex.startsOn, ex.endsOn, o.startsOn, o.endsOn));
};

// ── copy composition ──────────────────────────────────────────────────────────────────────────

/** 「휴가」 / 「추가 근무」 — the chip word. */
export const kindLabel = (kind: ExceptionKind): string => (kind === 'blackout' ? '휴가' : '추가 근무');

/**
 * The row's date line.
 *   blackout, one day   → 「10월 5일 (월)」
 *   blackout, a range   → 「10월 5일 (월) ~ 10월 9일 (금) · 5일」
 *   extra               → 「10월 5일 (월) · 05:00–06:20」
 * An unparseable date returns '' so the caller omits the element rather than printing 「NaN월」.
 */
export const exceptionDateLabel = (ex: AvailException): string => {
  const s = calOfYmd(ex.startsOn);
  const e = calOfYmd(ex.endsOn);
  if (s == null || e == null) return '';
  if (ex.kind === 'extra') {
    if (ex.startMin == null || ex.endMin == null) return kstDateLabel(s);
    return `${kstDateLabel(s)} · ${hhmm(ex.startMin)}–${hhmm(ex.endMin)}`;
  }
  const a = dayIndexOfYmd(ex.startsOn);
  const b = dayIndexOfYmd(ex.endsOn);
  if (a == null || b == null || a === b) return kstDateLabel(s);
  return `${kstDateLabel(s)} ~ ${kstDateLabel(e)} · ${b - a + 1}일`;
};

/** What a person is told the row DOES. One sentence per kind, and the shadowed case is its own
 *  sentence because 「적용돼요」 would be false there. */
export const exceptionEffectLabel = (ex: AvailException, all: readonly AvailException[]): string => {
  if (ex.kind === 'blackout') return '이 기간에는 예약을 받지 않아요';
  if (extraIsShadowed(ex, all)) return '휴가 기간과 겹쳐서 적용되지 않아요';
  return '이 시간에도 예약을 받아요';
};

/** Newest-first is wrong for a calendar: a runner reads their own schedule forwards. */
export const sortExceptions = (list: readonly AvailException[]): AvailException[] =>
  [...list].sort((x, y) => {
    if (x.startsOn !== y.startsOn) return x.startsOn < y.startsOn ? -1 : 1;
    const xs = x.startMin ?? -1;
    const ys = y.startMin ?? -1;
    if (xs !== ys) return xs - ys;
    return x.id < y.id ? -1 : x.id > y.id ? 1 : 0;
  });

/** The confirm sentence before a delete. Named here so the test can pin that it identifies the
 *  row — an 「정말 지울까요?」 with no date is a destructive tap on an unnamed thing. */
export const deleteConfirmMessage = (ex: AvailException): string => {
  const d = exceptionDateLabel(ex);
  return d === '' ? `${kindLabel(ex.kind)} 일정을 지울까요?` : `${kindLabel(ex.kind)} · ${d}`;
};
