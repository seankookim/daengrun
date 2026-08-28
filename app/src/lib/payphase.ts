// 결제 페이즈 머신 — 서버 진실(bookings.status)에서 결제 표면의 화면 페이즈를 파생하는 단 하나의 자리.
// owner/pay.tsx와 미래 PG 클라이언트(설계 phase ④)가 같은 머신을 import 한다 — 3차 리빌드 방지
// (웨이브 2 리뷰 H4/H5). 화면은 이 파일이 말한 것만 말한다: 상태를 지어내지 않는다.
//
// [C5 수정 확정] 리포트의 draft|quoted→'error(라우드)'는 타입 불능이었다 — M1이 error를 페이즈에서
// 제거했기 때문. 확정 해석: 도달 불가 상태 = '부재'(not_found, 재시도 문 없음). 리포트보다 이 줄이 이긴다.
// [어휘 분기 명문화 · H5] api.ts STATUS_MAP(fetchMyBookings 부근)은 '예약 목록 배지' 어휘(pending/confirmed/cancelled…)라
// refund_pending을 'cancelled'로 접는다 — 목록에서는 취소의 후속 단계로 보이는 게 정직하기 때문이다.
// 여기서는 접지 않는다: 결제 표면에서 '환불 진행 중'과 '취소됨'은 사용자가 지금 기다려야 하는지가
// 갈리는 서로 다른 사실이다. 두 매핑은 목적이 달라 일부러 갈라져 있다 — 통합하지 말 것.

// bookings.status enum 전체 16종 (supabase/migrations/0001_init.sql:9-14).
// 리터럴 유니언인 이유: 아래 Record가 누락을 tsc 에러로 만든다
// (웨이브 2 리뷰 C5 — 8종 미매핑 + no_show/incident_review가 '결제 완료'로 위장하던 사고).
export type BookingStatus =
  | 'draft' | 'quoted' | 'payment_hold' | 'matching' | 'runner_pending'
  | 'confirmed' | 'runner_enroute' | 'picked_up' | 'active' | 'completed'
  | 'cancelled_owner' | 'cancelled_runner' | 'expired' | 'no_show'
  | 'incident_review' | 'refund_pending';

// 9페이즈 확정 (웨이브 2 리뷰 M1 — 'partial' 삭제: 정산은 원자적이라 서버가 그 상태를 만들 수 없다).
// 통신 실패('error')는 여기 없다 — 그건 예약의 상태가 아니라 우리 쪽 실패다. 화면이 한 칸 더 갖는다.
export type PayPhase =
  | 'loading'        // 청구 fetch 중 — 숫자는 전부 '—', CTA 없음
  | 'not_found'      // 0행·없는 bid·남의 예약 — 재시도 없는 정직한 부재 (H3/M5)
  // [O-5 §E.5.1] '실전이(confirmPayment)'는 삭제됐다 — payment_hold에 남은 예약을 앞으로 미는
  // 클라이언트 호출이 더 이상 없다. 이 페이즈는 이제 '아직 접수되지 않음'을 말할 뿐이다.
  | 'mock_pending'   // PG 목업 · 접수 전 — 화면이 할 수 있는 일은 사실을 말하고 나가는 것뿐
  | 'authorizing'    // 미래 PG: 승인 요청 진행 중 — 취소 어포던스 없는 화면
  | 'authorized'     // 결제 홀드를 지난 예약 — 여기서는 종점, 다음 화면으로 보낸다
  | 'disputed'       // no_show·incident_review — '완료'로 위장하지 않는다 (C5)
  | 'failed'         // 전이 실패 / PG 거절 — 라우드 페일 + 재시도
  | 'cancelled'      // cancelled_* · expired — 종점
  | 'refund_pending' // 환불 진행 중 — 종점이지만 대기 중
  // ── [codex 2026-08-28, findings 11+12] four phases that a booking status CANNOT produce alone.
  // Each of them exists because the sentence above it was being said about a fact nobody had read;
  // see the COLLECTION block at the foot of this file for what they are derived from.
  | 'not_charged'      // 환불/정산이 끝났지만 청구된 돈이 없다 — 환불이 아니라 무청구다 (#11)
  | 'paid'             // 정산 + 수금 모두 끝났다 — 실결제가 일어난 예약 (플래그 이후)
  | 'collect_pending'  // 정산은 끝났고 청구가 아직 처리되지 않았다 (#12)
  | 'collect_failed'   // 정산은 끝났고 청구가 실패했다 — 사람이 움직여야 하는 칸 (#12)
  | 'charge_unknown';  // 결제 상태를 읽지 못했다 — '청구 없음'으로 위장하지 않는다

// PG 시도 레코드 — 오늘 서버에 존재하지 않는다 (derivePayPhase의 attempt는 항상 undefined).
// PG 슬라이스가 붙을 때 이 인자만 채우면 authorizing/failed가 살아난다: 머신 재작성 없음 (H4).
// 승인 '성공'은 여기 없다 — 그건 서버 status가 말한다 (클라이언트가 결제 완료를 선언하지 않는다).
export type PayAttemptState = 'in_flight' | 'declined';
export interface PayAttempt { state: PayAttemptState; reason?: string | null }

// 상태 → 페이즈 (16종 전수). 새 enum 값이 생기면 tsc가 이 자리에서 막는다.
export const STATUS_PHASE: Record<BookingStatus, PayPhase> = {
  // draft·quoted: 이 라우트로 도달할 수 없다 — 홀드 생성(create-booking-hold)이 그 두 상태를
  // 한 요청 안에서 지나쳐 간다. 도달했다면 결제 표면이 말할 수 있는 사실이 없다는 뜻이라
  // '부재'로 떨어뜨린다 (재시도 문을 열지 않는다 — 없는 결제를 기다리게 하지 않는 쪽이 정직하다).
  draft: 'not_found',
  quoted: 'not_found',
  payment_hold: 'mock_pending',
  // 아래 7종은 이미 결제 홀드를 지난 예약이다 — 결제 표면의 할 일은 '다음 화면으로'뿐.
  // [M7] 클럽 예약은 payment_hold를 거치지 않고 곧장 이 구간으로 들어온다 → authorized로 렌더된다 (정상).
  matching: 'authorized',
  runner_pending: 'authorized',
  confirmed: 'authorized',
  runner_enroute: 'authorized',
  picked_up: 'authorized',
  active: 'authorized',
  completed: 'authorized',
  cancelled_owner: 'cancelled',
  cancelled_runner: 'cancelled',
  expired: 'cancelled',
  // 노쇼·사고 검토는 '결제 완료'가 아니다 — 사람이 확인 중인 예약이다 (C5).
  no_show: 'disputed',
  incident_review: 'disputed',
  refund_pending: 'refund_pending',
};

export function derivePayPhase(
  p: { status: BookingStatus; attempt?: PayAttempt | null; collection?: Collection | null },
): PayPhase {
  const base: PayPhase | undefined = STATUS_PHASE[p.status];
  // 서버가 enum을 늘리면 런타임 문자열은 tsc가 못 잡는다 — 모르는 상태를 '결제 완료'로 위장하지 않고
  // 부재로 떨어뜨린다 (모르면 모른다고 말한다).
  if (!base) return 'not_found';
  // ── [codex #11/#12] The two statuses whose sentence needs a second fact. This runs BEFORE the
  // attempt branch because neither of them is `mock_pending`, so the two never interact.
  if (collectionMatters(p.status)) {
    // No collection supplied at all is not the same as "nothing was collected" — a caller that
    // forgot to read the rows must not be handed 「청구되지 않았어요」. Same fail-closed direction
    // as an unrecognised payments status.
    const c = p.collection ?? COLLECTION_UNKNOWN;
    if (c.captured === null || c.outstanding === 'unknown') return 'charge_unknown';
    if (p.status === 'refund_pending') {
      // The migration's own predicate, in the migration's own words: a refund is only 「진행 중」
      // when there is something to refund. Otherwise this is a no-charge case (0152 §notify).
      return c.captured ? 'refund_pending' : 'not_charged';
    }
    // `completed` — the ledger committed. Collection is a separate, later, non-unwinding fact.
    if (c.captured) return 'paid';
    if (c.outstanding === 'failed') return 'collect_failed';
    if (c.outstanding === 'pending') return 'collect_pending';
    // Rows exist but none of them is a charge: the whole booking priced to 0원 (`waived`).
    if (c.minted) return 'not_charged';
    // Nothing was ever minted — the card-less pilot, and every run before `payments_live_since`.
    return base;
  }
  if (!p.attempt) return base;              // 오늘의 유일한 경로 — attempt는 아직 서버에 없다
  if (base !== 'mock_pending') return base; // 홀드를 지난 예약은 시도 레코드보다 서버 상태가 최신이다
  return p.attempt.state === 'declined' ? 'failed' : 'authorizing';
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// COLLECTION — the second fact this surface needs, and the reason it now needs one
// ═══════════════════════════════════════════════════════════════════════════════════════════
// [codex 2026-08-28 findings 11+12 · docs/reviews/2026-08-28-codex-runend-money.md]
//
// `bookings.status` alone does NOT mean what this screen was reading out of it.
//
//  · `refund_pending` is written by `club_incident_settle` (0152:209-211) whenever the quote's
//    refund is > 0, and by `_club_refund_bookings`, and NEITHER checks whether money was ever
//    captured. The migration knows this perfectly well — six lines later it asks
//        exists (select 1 from payments p where p.booking_id = … and p.status = 'confirmed')
//    and sends the owner 「이번 건은 청구되지 않아요」 instead of 「…원이 환불돼요」 (0152:221-228,
//    verified against the DEPLOYED `prosrc`, not the file). The NOTIFICATION got the predicate;
//    this screen never did, so it said 「환불이 진행 중이에요」 for a charge that never happened.
//    MEASURED on production 2026-08-28: 2 bookings sit in `refund_pending` and BOTH have zero
//    payments rows.
//  · `completed` says the ledger committed. It says nothing about collection, which happens
//    AFTER it and cannot unwind it (settle-run's ordering law, handler.ts:14-18). A settled run
//    whose card was declined is `completed` and read identically to one that was paid.
//
// The vocabulary below is derived from the CHECK constraints on `payments`, read off PRODUCTION
// rather than off a migration file:
//     payments_status_vocab     status ∈ (pending, confirmed, canceled, partial_canceled, failed, waived)
//     payments_settled_has_key  status ∈ (pending, failed, waived) OR payment_key IS NOT NULL
// The second one is what makes `captured` a fact rather than a guess: a row outside those three
// words cannot exist without a payment_key, and a payment_key means money moved.
//
// ⚠ `status` is TEXT with a CHECK, not an enum — it can widen without a client deploy (the
// widened-meaning law, CLAUDE.md §④). Every unrecognised word therefore lands in `unknown`, and
// `unknown` renders as 「we could not tell you」, never as 「nothing was charged」. Failing open
// here is precisely how an invented sentence reaches an owner.

/** Rows whose existence proves money moved — `payments_settled_has_key` forbids them without a key. */
const CAPTURED_STATUSES = ['confirmed', 'canceled', 'partial_canceled'];
/** Rows the same CHECK allows to exist with NO payment_key — nothing has moved through any of them. */
const UNCAPTURED_STATUSES = ['pending', 'failed', 'waived'];

export interface Collection {
  /** true = money moved · false = it provably did not · null = we cannot tell (never rendered as false). */
  captured: boolean | null;
  /** A minted charge on this booking that has not been collected. 'failed' outranks 'pending'. */
  outstanding: 'none' | 'pending' | 'failed' | 'unknown';
  /** At least one payments row exists. FALSE is the whole card-less pilot: nothing was ever minted. */
  minted: boolean;
}

/** The answer when the read itself failed. Not a state of the booking — a state of our knowledge. */
export const COLLECTION_UNKNOWN: Collection = { captured: null, outstanding: 'unknown', minted: false };

/**
 * Fold this booking's `payments` rows into the facts the screen may state. `null`/`undefined` (the
 * read threw) and a row carrying a word we do not know both land on UNKNOWN.
 */
export function summarizeCollection(rows: readonly { status: string }[] | null | undefined): Collection {
  if (!rows) return COLLECTION_UNKNOWN;
  let captured = false;
  let unknownWord = false;
  let pending = false;
  let failed = false;
  for (const r of rows) {
    const st = String(r?.status ?? '');
    if (CAPTURED_STATUSES.includes(st)) { captured = true; continue; }
    // A word we do not recognise could be either kind, so it poisons BOTH answers rather than
    // being quietly skipped — a dropped row is exactly how 「nothing was charged」 gets invented.
    if (!UNCAPTURED_STATUSES.includes(st)) { unknownWord = true; continue; }
    if (st === 'failed') failed = true;
    else if (st === 'pending') pending = true;
  }
  if (unknownWord) return { captured: null, outstanding: 'unknown', minted: rows.length > 0 };
  return {
    captured,
    outstanding: failed ? 'failed' : pending ? 'pending' : 'none',
    minted: rows.length > 0,
  };
}

/** The two statuses whose sentence is a lie without the collection fact. Everything else is status-only. */
export function collectionMatters(status: BookingStatus): boolean {
  return status === 'refund_pending' || status === 'completed';
}
