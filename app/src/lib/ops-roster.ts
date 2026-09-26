// ops-roster.ts — the grouping and the labels the 운영자 명단 screen needs before it touches the
// wire. `app/test/ops-roster.test.cjs` pins it against the REAL compiled source (esbuild), not a
// retyped copy, the same idiom as `ops-payout.ts` and `notification-prefs.ts`.
//
// 🔴 **NOTHING HERE IS AN ENFORCEMENT POINT.** `ops_roster_set` (0208 §C) takes the console gate
//   before it looks at an argument, validates the class against its OWN allowlist, and refuses
//   `last_operator` from its own count of locked rows. Everything in this file is there so the
//   screen can say the right thing WITHOUT a round trip; if the client and the server ever
//   disagree, the server is right and its refusal is what gets rendered. In particular
//   `wouldStrandConsole` below is a MIRROR, not a rule: it exists so a disabled chip can explain
//   itself, and the code path that ignores it still ends at the server's `last_operator`.
//
// ⚠ NOTHING HERE READS THE DEVICE CLOCK — no date work at all. `check-device-clock` is the gate;
//   the screen's dates go through `kst.ts`.

/** The class every shipped ops door gates on, and therefore the one that decides whether a person
 *  can open the console at all (0198 §0d). It is the only class `last_operator` protects. */
export const CONSOLE_CLASS = 'payout_due';

/** One flat row exactly as `ops_roster()` (0208 §B) hands it over. Structural on purpose, so the
 *  pins can build one without importing the screen or the wire. */
export interface OpsRosterRow {
  profileId: string;
  /** NULL when the profile row is gone — `ops_roster` uses a left join so such a row is SHOWN
   *  rather than silently dropped. The screen renders the id in that case. */
  name: string | null;
  role: string | null;
  eventClass: string;
  active: boolean;
  createdAt: string | null;
}

/** One person and every class they are (or were) subscribed to. */
export interface OpsRosterPerson {
  profileId: string;
  name: string | null;
  role: string | null;
  /** Every row this person has, in the order `CLASS_ORDER` puts them, unknown classes last. */
  classes: OpsRosterRow[];
  /** Active rows only — what `ops_recipients_for` would return for this person. */
  activeClasses: string[];
}

/** The screen's chip order and Korean labels.
 *
 * ⚠ **THIS IS DISPLAY VOCABULARY AND THE RAW CLASS IS THE FACT.** Every toggle sends
 *   `eventClass`, never a label, and an unknown class renders as ITSELF rather than being hidden
 *   or renamed — `ops_roster()` returns every row including one written by psql with a string
 *   this table does not know, because a roster that hid rows it did not recognise would be a
 *   roster that lies about who is on call (0208 §0c). `classLabel` therefore falls back to the
 *   raw string, which is the honest rendering of 「we do not have a name for this」.
 *
 * ⚠ The KEY SET is a server contract: `ops_roster_set` refuses anything outside 0208 §C's
 *   `c_classes`, so a key here that the server does not know is a chip whose tap is refused, and
 *   a class the server knows and this table omits is a desk nobody can be seated at from the
 *   product. `ops-roster.test.cjs` pins the set in both directions. */
export const CLASS_LABELS: Readonly<Record<string, string>> = {
  payout_due: '정산 지급',
  return_strand: '귀가 좌초',
  handoff_unanswered: '인계 무응답',
  // [0234 §C] open_incident_tx's ops bell — every newly reported incident, title by severity
  incident_opened: '사고 접수',
  // [0237 §C] the recurring generator's failure ring — a series whose failure episode reached its
  // third failed tick (`_recurring_failure_escalate`, one ring per episode)
  recurring_generation_failed: '반복 예약 생성 실패',
  billing_key_revocation_abandoned: '결제수단 해지 실패',
  club_fee_mint_failed: '클럽 수수료 발행 실패',
  payment_manual_cancel: '결제 수동 취소',
  charge_ladder_exhausted: '청구 재시도 소진',
  charge_dispatch_stale: '청구 결과 미확인',
  settled_without_payment: '정산됐는데 결제 없음',
  enroute_comp_failed: '이동 중 보상 실패',
  late_comp_failed: '지각 보상 실패',
  incident_waive_pending: '사고 면제 미판정',
  payment_marker_lost: '결제 실패 기록 유실',
};

/** The order the chips are drawn in — the console desk first, then the two ceremony desks, then
 *  the money desks. Anything not listed sorts after, alphabetically by its raw name. */
export const CLASS_ORDER: readonly string[] = Object.keys(CLASS_LABELS);

/** Every class the screen offers in the 운영자 추가 sheet. Same set, named separately because the
 *  two questions are different: this one is 「what may a new person be seated at」. */
export const SELECTABLE_CLASSES: readonly string[] = CLASS_ORDER;

/** Classes the server ACCEPTS and nothing EMITS — a chip an operator can turn on and never be paged
 *  by. [gap sweep 2026-09-25 · ops-notifications-6]
 *
 *  Measured on trunk `943eb7c`, comment-stripped: the edge's `notifyOps(db, "<class>")` callers are
 *  late_comp_failed + enroute_comp_failed (transition-booking/cancel_owner.ts) and
 *  payment_marker_lost + payment_manual_cancel (confirm-payment/handler.ts); the migrations'
 *  `ops_recipients_for('<class>')` literals and `c_ops_class constant text := '<class>'` routing
 *  constants cover payout_due · return_strand · handoff_unanswered ·
 *  billing_key_revocation_abandoned · club_fee_mint_failed. These four appear in neither.
 *
 *  ⚠ They stay SELECTABLE (0208 §0c: a class the server knows and this table omits is a desk nobody
 *    can be seated at from the product — and seating someone ahead of an emitter is legitimate).
 *    The screen LABELS them instead of hiding them, so the chip stops promising a page.
 *  ⚠ `ops-roster.test.cjs` scans the emitters every run and fails in BOTH directions: an emitter
 *    landing for a class listed here reddens it (delete the entry), and a class NOT listed here
 *    with no emitter reddens it too (add it). The set can only say what the source says.
 *  ⚠ The charge ladder's `charge_ladder_exhausted` ping is the money-path slice that turns charging
 *    on (`charge.ts`'s last rung tells only the owner today) — not this file's to add. */
export const DORMANT_CLASSES: ReadonlySet<string> = new Set([
  'charge_ladder_exhausted',
  'charge_dispatch_stale',
  'settled_without_payment',
  'incident_waive_pending',
]);

/** The suffix a dormant class's chip carries — '' for every class something emits. */
export function dormantNote(eventClass: string): string {
  return DORMANT_CLASSES.has(eventClass) ? ' · 아직 발신 없음' : '';
}

/** The Korean label, or the raw class when we do not have one (see CLASS_LABELS' header). */
export function classLabel(eventClass: string): string {
  return CLASS_LABELS[eventClass] ?? eventClass;
}

function classRank(eventClass: string): number {
  const i = CLASS_ORDER.indexOf(eventClass);
  return i === -1 ? CLASS_ORDER.length : i;
}

/** Group the flat rows by person.
 *
 *  ⚠ People are ordered by NAME, and a row whose profile is gone (name null) sorts last under its
 *  id — the same order `ops_roster()` returns, restated here because the screen must not depend on
 *  the wire preserving it through a JSON round trip.
 *  ⚠ A person with only INACTIVE rows is still a person. 0084 keeps the row precisely so that
 *  「who used to be on call」 survives, and dropping them here would mean re-typing a uuid to put a
 *  former operator back. */
export function groupRoster(rows: readonly OpsRosterRow[]): OpsRosterPerson[] {
  const byId = new Map<string, OpsRosterPerson>();
  for (const r of rows) {
    let p = byId.get(r.profileId);
    if (!p) {
      p = { profileId: r.profileId, name: r.name, role: r.role, classes: [], activeClasses: [] };
      byId.set(r.profileId, p);
    }
    // the first non-null name wins — a left join can hand back a null beside a real one only if
    // the profile vanished mid-read, and a name we have beats a name we do not
    if (p.name === null && r.name !== null) p.name = r.name;
    if (p.role === null && r.role !== null) p.role = r.role;
    p.classes.push(r);
    if (r.active) p.activeClasses.push(r.eventClass);
  }
  const out = [...byId.values()];
  for (const p of out) {
    p.classes.sort((a, b) => classRank(a.eventClass) - classRank(b.eventClass)
      || a.eventClass.localeCompare(b.eventClass));
    p.activeClasses.sort((a, b) => classRank(a) - classRank(b) || a.localeCompare(b));
  }
  out.sort((a, b) => {
    if ((a.name === null) !== (b.name === null)) return a.name === null ? 1 : -1;
    const byName = (a.name ?? '').localeCompare(b.name ?? '');
    return byName !== 0 ? byName : a.profileId.localeCompare(b.profileId);
  });
  return out;
}

/** How many people hold an ACTIVE `payout_due` row — i.e. how many humans can open the console. */
export function activeConsoleOperators(rows: readonly OpsRosterRow[]): string[] {
  const ids = new Set<string>();
  for (const r of rows) if (r.active && r.eventClass === CONSOLE_CLASS) ids.add(r.profileId);
  return [...ids];
}

/**
 * Would turning this row OFF leave nobody able to open the console?
 *
 * 🔴 A MIRROR OF 0208 §C's `last_operator`, NOT a second implementation of it — the server counts
 *    LOCKED rows inside the same transaction as the write, which is the only count that can be
 *    relied on when two terminals are open. This one answers 「should the chip explain itself
 *    before the tap」, and its wrong answer costs a round trip, never a locked-out console.
 *
 * ⚠ It is `payout_due`-only, exactly like the server's: emptying `return_strand` is a state 0084
 *   §E documents as honest (zero recipients, the caller falls back), not a lockout.
 * ⚠ It returns false for a row that is ALREADY off — turning off what is already off changes
 *   nothing and the server does not refuse it either.
 */
export function wouldStrandConsole(
  rows: readonly OpsRosterRow[], profileId: string, eventClass: string, next: boolean,
): boolean {
  if (next !== false || eventClass !== CONSOLE_CLASS) return false;
  const isOnNow = rows.some(
    (r) => r.profileId === profileId && r.eventClass === CONSOLE_CLASS && r.active,
  );
  if (!isOnNow) return false;
  return activeConsoleOperators(rows).filter((id) => id !== profileId).length === 0;
}

/** The label a class chip carries while its toggle is in flight.
 *  ⚠ A LABEL SWAP and not a spinner over the old text: the chip must never read as though the old
 *  state were still true while a write is on the wire. */
export function chipLabel(eventClass: string, busy: boolean): string {
  return busy ? `${classLabel(eventClass)} 저장 중…` : classLabel(eventClass);
}

/** What a person's row says under their name. Never a count we do not have. */
export function personSummary(p: OpsRosterPerson): string {
  if (p.activeClasses.length === 0) return '담당 없음 · 이력만 남아 있어요';
  return p.activeClasses.map(classLabel).join(' · ');
}
