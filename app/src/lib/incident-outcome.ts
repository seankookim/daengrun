// A resolved incident's FACE — the pure half of `app/app/incident/[bid].tsx`.
//
// WHY IT EXISTS. `fetchOpenIncident` filters `.is('resolved_at', null)`, which is the server's own
// predicate for 「open」 and is correct for the stamp view. The consequence is not: the instant a
// row is resolved, BOTH parties' `/incident/[bid]` found no open incident and fell through to the
// blank report form — a record of a real accident replaced by an empty page, on the screen where
// that substitution costs the most. This module turns the resolved row into a face so the screen
// can say what happened instead of forgetting it.
//
// 🔴 WHAT THE PARTIES CAN ACTUALLY READ, measured before a single sentence was written here —
// because the temptation was to render 0072's settlement vocabulary, and the parties cannot see it.
//
//   · `incidents` is 0001:383 + 0094 §7. Its ONLY resolution column is `resolved_at`; every other
//     column 0094 added is about VERIFICATION (owner/runner stamps, `verified_at`,
//     `verify_forced_by`), which is a different fact and already rendered by the open-case branch.
//     There is no outcome column, no amount column, no reason column. Read from source, not assumed.
//   · Both parties can read the row: `create policy "incidents party" on incidents for select using
//     (reporter_id = auth.uid() or (booking_id is not null and is_booking_party(booking_id)))` —
//     0002_rls.sql:151-153. 0094 §8 dropped the INSERT policy and left this SELECT policy alone;
//     0088/0114 add no narrower one. So the resolved row is readable by both sides, always.
//   · 0072 (`incident_settlement`) writes `ledger_items`, `club_fee_items` and
//     `club_incident_evidence` — the CLUB tables, keyed by a club session, for `club_incidents`,
//     which is a different table from this one. None of it is reachable from here:
//     `ledger self read` (0002:124) is runner-only and the ledger is table-sealed to the client
//     anyway (see api.ts's runner-money block), and `club_fee_items` is club-scoped.
//
// ⚠ SO THERE IS NO MONEY LINE, and that is a fact about the schema rather than a styling choice.
//   No amount for this decision is readable by either party, so this face carries none — an amount
//   rendered here would have to be invented or derived, and both are the thing the honesty laws
//   forbid. If a future slice makes a real amount party-readable, it gets a field here and a pin;
//   until then the absence is the honest state and is written down rather than guarded by a pin
//   that could never fail.
//
// 🔴 WHERE THE DECISION SENTENCE COMES FROM, so that nothing here is invented. 0072 §④ says it in
//   its own words: 환불이 있으면 `refund_pending` … 없으면 그대로 `incident_review`에 남는다 —
//   「부킹을 옮기는 것이 곧 그 선언이고」. The booking status IS the settlement declaration, and it
//   is party-readable (`bookings party read`, 0002:92). The two sentences below are 0072 §⑥'s own
//   notification bodies with the unreadable amount removed. Any OTHER status says nothing about a
//   settlement, so it maps to null and the face simply does not claim a decision — fail closed,
//   never a default sentence, because a wrong decision line on a settled accident is worse than
//   no line at all.
//
// It knows no RN, no router, no supabase — only `kst.ts` — so `test/incident-outcome.test.cjs`
// pins the REAL compiled source (the notification-prefs idiom), and the date it prints cannot
// depend on the device's timezone.

import { kstCal, kstYearMonthDay } from './kst';

/** The party-readable facts about a resolved incident. Every field is a column, not a derivation. */
export interface IncidentOutcomeRow {
  /** `incidents.resolved_at`. Non-null is what makes this row an outcome at all. */
  resolvedAtIso: string | null;
  /** `bookings.status` RAW — never a STATUS_MAP label. 0072 §④ makes this the decision. */
  bookingRawStatus: string | null;
  /** `incidents.verified_at` — both stamps, or an ops adjudication (0094 §11). */
  verifiedAtIso: string | null;
  /** `incidents.verify_forced_by` — 'ops' or null. */
  forcedBy: string | null;
}

export interface IncidentOutcomeFace {
  /** The row is resolved. False means the caller should not render this face at all. */
  resolved: boolean;
  /** 「2026년 9월 23일」 KST, or null when `resolved_at` cannot be parsed. */
  dateLabel: string | null;
  /** 「처리 완료 · 2026년 9월 23일」, degrading to 「처리 완료」 with no date. */
  headline: string;
  /** 0072 §④'s declaration, or null when the booking status does not carry one. */
  decision: string | null;
  /** How the incident was established (0094 §11's two distinct sentences), or null. */
  established: string | null;
}

/** 처리 완료 — the headline stands with or without a parseable date. */
export const RESOLVED_TITLE = '처리 완료';

/** 0072 §④ + §⑥, amount removed because no amount is party-readable (see the header). */
export const DECISION_BY_BOOKING_STATUS: Record<string, string> = {
  refund_pending: '환불이 진행돼요',
  incident_review: '환불 없이 마무리됐어요',
};

/** 0094 §11 deliberately keeps 「ops established it」 and 「both parties confirmed it」 apart —
 *  an ops adjudication fills `verified_at` and leaves BOTH party stamps NULL. Collapsing the two
 *  into one sentence would make the stamp rows above read as a contradiction. */
export const FORCED_BY_OPS = '운영자가 확정했어요';
export const VERIFIED_BOTH = '양쪽 확인 완료';

const NOT_RESOLVED: IncidentOutcomeFace = {
  resolved: false, dateLabel: null, headline: RESOLVED_TITLE, decision: null, established: null,
};

/**
 * Row → face. Pure.
 *
 * ⚠ An UNPARSEABLE `resolved_at` still yields `resolved: true` with a null date. The other
 * direction — treating it as unresolved — puts the blank report form back on a settled accident,
 * which is the exact defect this module exists to remove. It fails towards saying less, never
 * towards forgetting.
 */
export function incidentOutcomeFace(row: IncidentOutcomeRow | null): IncidentOutcomeFace {
  if (!row || !row.resolvedAtIso) return NOT_RESOLVED;
  const ms = Date.parse(row.resolvedAtIso);
  const dateLabel = Number.isFinite(ms) ? kstYearMonthDay(kstCal(ms)) : null;
  return {
    resolved: true,
    dateLabel,
    headline: dateLabel ? `${RESOLVED_TITLE} · ${dateLabel}` : RESOLVED_TITLE,
    decision: row.bookingRawStatus ? (DECISION_BY_BOOKING_STATUS[row.bookingRawStatus] ?? null) : null,
    established: row.forcedBy === 'ops' ? FORCED_BY_OPS : row.verifiedAtIso ? VERIFIED_BOTH : null,
  };
}
