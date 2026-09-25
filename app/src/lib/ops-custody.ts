// ═══════════ The two 0224 console desks — 러닝 좌초 (custody) and 정산 미완료 (sealed) ═══════════
//
// Pure: no fetch, no navigation, no React, no clock of its own (the one epoch read is a `nowMs`
// ARGUMENT) — so `app/test/ops-custody.test.cjs` can pin every sentence against the REAL compiled
// source, which it cannot do for `app/ops/custody.tsx` / `app/ops/sealed.tsx` (route modules are
// unreachable from the test chain; `ops-console.ts` is the same division for the 0206 desks).
//
// 🔴 BOTH DESKS ARE READ-ONLY, AND THAT IS 0224 §0c's RULING RATHER THAN A GAP. Whether an operator
//    may start or end a run the runner never did is Sean's letter; settling a sealed row needs the
//    pricing re-drive 0083 §0f names, which is not built (`ops_resolve_return_tx` refuses it by name,
//    `already_sealed`). So no row is a button: there is no per-booking ops screen these rows could
//    open, and a chevron onto nothing would be a dead button. The lead says what IS true instead.
//
// ⚠ Every duration here is a NUMBER OF MINUTES the server computed, or an epoch difference — never
//   a calendar or weekday read, so `check-device-clock` has nothing to see and KST is not involved.

import { strandAgeLabel } from './ops-console';

/** The roster each 0224 read gates on (0224 §F: 「the people who were TOLD are the people who may
 *  look」). The console draws a desk only when `ops_me().kinds` carries its class. */
export const CUSTODY_DESK_CLASS = 'return_strand';
export const SEALED_DESK_CLASS = 'payout_due';

/** `null` kinds = NOT READ YET, which is not a 「no」 (ops-context.tsx). */
export type DeskAccess = 'unknown' | 'held' | 'not_held';
export function deskAccess(kinds: readonly string[] | null, cls: string): DeskAccess {
  if (kinds === null) return 'unknown';
  return kinds.includes(cls) ? 'held' : 'not_held';
}

// ── 러닝 좌초 (ops_stranded_custody) ─────────────────────────────────────────────────────────────

export const CUSTODY_TITLE_KO = '러닝 좌초';
export const CUSTODY_LEAD_KO =
  '러너가 개를 데리고 있는데 러닝이 시작되지 않았거나, 시작된 러닝이 종료되지 않은 채 멈춘 예약이에요. '
  + '이 화면은 보기 전용이에요 — 운영자가 러닝을 대신 시작하거나 종료하는 방법은 아직 정해지지 않았어요.';
export const CUSTODY_LOADING_KO = '멈춘 러닝을 불러오는 중이에요…';
export const CUSTODY_FAILED_KO = '멈춘 러닝을 불러오지 못했어요';
export const CUSTODY_EMPTY_KO = '멈춘 러닝이 없어요';
/** ⚠ THE EMPTY LIST CLAIMS LESS THAN IT LOOKS. With both thresholds NULL — the SHIPPED value — the
 *  list shows only rows a bell already rang for, and the threshold rides on ROWS only, so an empty
 *  response cannot say whether the sweep is on (the codex #3 lesson from the 반환 좌초 desk). */
export const CUSTODY_EMPTY_SUB_KO =
  '이 목록만으로는 좌초 기준이 켜져 있는지 알 수 없어요 — 기준이 꺼져 있으면 알림이 이미 간 건만 나와요';
export const CUSTODY_REFUSED_KO = '이 목록은 반환 좌초 담당자만 볼 수 있어요';
export const CUSTODY_GONE_KO = '알림이 가리킨 예약은 이미 목록에서 빠졌어요';
export const CUSTODY_GONE_SUB_KO = '러너가 러닝을 시작했거나 종료했을 수 있어요 — 다시 멈추면 목록에 돌아와요';

/** Which run move is missing, as a sentence. `shape` is the server's own word (0224 §B); a word
 *  this build does not know is SAID, never mapped onto a known one. */
export function custodyShapeLabel(shape: string): string {
  if (shape === 'start_run') return '인계는 끝났는데 러닝이 시작되지 않았어요';
  if (shape === 'end_run') return '예정 시간이 지났는데 러닝이 종료되지 않았어요';
  return '어느 단계에서 멈췄는지 이 앱 버전에서는 읽을 수 없어요';
}

/** How long the custody has sat still, from where 0224 §B starts its clock: the handoff for
 *  `start_run`, the run's NOMINAL end for `end_run`. `null` when there is no clock to read or the
 *  shape is unknown — absent, never 0분. A negative difference (clock skew; `end_run`'s nominal end
 *  still ahead) is not 「0분째」 either: it is not yet a wait, so nothing is printed. */
export function custodyAgeLabel(shape: string, sinceAt: string | null, nowMs: number): string | null {
  if (sinceAt === null || !Number.isFinite(nowMs)) return null;
  const at = Date.parse(sinceAt);
  if (!Number.isFinite(at)) return null;
  const min = Math.floor((nowMs - at) / 60000);
  if (min < 0) return null;
  const dur = strandAgeLabel(min);
  if (dur === null) return null;
  if (shape === 'start_run') return `인계 후 ${dur}`;
  if (shape === 'end_run') return `예정 종료 후 ${dur}`;
  return null;
}

/** The threshold line — what the SERVER said on this row. `strandMinutes === null` is the server
 *  reporting the shipped off-switch, observed on a row (so it may be said); the row is here
 *  because a bell already rang. */
export function custodyThresholdNote(strandMinutes: number | null, minutesOverdue: number | null): string {
  if (strandMinutes === null || !Number.isFinite(strandMinutes)) {
    return '좌초 기준이 꺼져 있어요 — 알림이 이미 간 건이라 목록에 남아 있어요';
  }
  const base = `좌초 기준 ${Math.max(0, Math.floor(strandMinutes))}분`;
  if (minutesOverdue === null || !Number.isFinite(minutesOverdue)) return base;
  if (minutesOverdue < 0) return `${base} · 아직 기준 전이에요`;
  const over = strandAgeLabel(minutesOverdue);
  return over === null ? base : `${base} · 기준을 넘긴 지 ${over}`;
}

/** Has the roster been paged about this row yet? The operator reading this IS on the roster, so a
 *  null means the next sweep tick has not run yet (0224 §C pass 2 retries every tick). */
export function custodyNotifiedNote(notifiedAt: string | null): string {
  return notifiedAt === null
    ? '담당자 알림은 아직이에요 — 다음 점검에서 발송돼요'
    : '담당자 알림이 발송된 건이에요';
}

// ── 정산 미완료 (ops_sealed_unsettled) ──────────────────────────────────────────────────────────

export const SEALED_TITLE_KO = '정산 미완료';
export const SEALED_LEAD_KO =
  '양측이 반환을 확인했는데 정산이 마무리되지 않은 예약이에요 — 러너에게 지급될 돈이 걸려 있어요. '
  + '이 화면은 보기 전용이에요 — 멈춘 정산을 다시 돌리는 기능은 아직 없어요.';
export const SEALED_LOADING_KO = '정산 미완료를 불러오는 중이에요…';
export const SEALED_FAILED_KO = '정산 미완료를 불러오지 못했어요';
export const SEALED_EMPTY_KO = '정산이 멈춘 예약이 없어요';
/** 0224 §F admits arm ⓐ's candidate predicate with NO age, so — unlike the custody list — an
 *  empty list here IS the fact: nothing is sealed and unsettled right now. */
export const SEALED_EMPTY_SUB_KO = '양측 반환 확인 후 정산이 끝나지 않은 예약이 생기면 바로 여기에 나와요';
export const SEALED_REFUSED_KO = '이 목록은 정산 담당자만 볼 수 있어요';
export const SEALED_GONE_KO = '알림이 가리킨 예약은 이미 목록에서 빠졌어요';
export const SEALED_GONE_SUB_KO = '정산이 마무리됐거나 예약 상태가 바뀐 거예요';

/** How long since the return was sealed — the server's minute count, absent when it sent none. */
export function sealedAgeLabel(minutesSealed: number | null): string | null {
  if (minutesSealed === null || !Number.isFinite(minutesSealed) || minutesSealed < 0) return null;
  const dur = strandAgeLabel(minutesSealed);
  return dur === null ? null : `봉인 후 ${dur}`;
}

/** The sealed bell rings once, after SEAL_ALARM_AFTER (0224 §D ①) — so a young row has no bell
 *  yet and that is ordinary, not a failure. No number is printed: the delay is the sweep's
 *  constant, and a copy of it here would be a second place for it to drift. */
export function sealedNotifiedNote(notifiedAt: string | null): string {
  return notifiedAt === null
    ? '담당자 알림은 아직이에요 — 봉인 후 일정 시간이 지나면 발송돼요'
    : '담당자 알림이 발송된 건이에요';
}

// ── shared ───────────────────────────────────────────────────────────────────────────────────────

/** The booking, named so an operator can find it: the first eight characters of its uuid,
 *  uppercased (ops/index.tsx's `shortId` for runners). */
export function bookingRef(bookingId: string): string {
  return `예약 ${bookingId.slice(0, 8).toUpperCase()}`;
}

/** Both parties by display name, falling back to the ROLE word — never a blank, never invented. */
export function partiesLine(ownerName: string | null, runnerName: string | null): string {
  return `보호자 ${ownerName ?? '이름 없음'} · 러너 ${runnerName ?? '이름 없음'}`;
}
