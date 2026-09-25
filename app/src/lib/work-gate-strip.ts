// ═══════════ ⑫ The runner work gate's ANSWER → the strip that explains it, on BOTH runner screens ═══════════
//
// Pure: no fetch, no navigation, no React — so `app/test/*.cjs` can ask it every question, which it
// cannot ask `app/runner/home.tsx` or `app/runner/requests.tsx` (a `.tsx` route module is
// unreachable from the test chain; same division as `work-gate-door.ts`, which decides whether a
// 수락 door may OPEN — this module decides what a SHUT gate SAYS and where its exit goes).
//
// ═══ THE DEFECT THIS EXISTS FOR (0224 §0c; Codex s2, 2026-09-25 — both runner strips) ═══
// `runner_work_gate` used to answer `waiting_on ∈ {both, runner, owner}` — three words about the
// RETURN stamps — and both runner strips drew 「반환 봉인 찍기 ›」 → `/runner/return-seal` for ANY
// gated answer that was not `owner`. 0224 §E added two words for a STRANDED custody: `start_run`
// (the handoff finished, the run never started — `picked_up`) and `end_run` (the run started and
// was never stopped — `active`, no `run_ended_at`), exits `runner_start_run` / `runner_end_run`.
// Read through the old strips, a runner holding a dog whose run never started was told a run had
// ended and sent to /runner/return-seal, whose `if (!s.runEndedAt)` frame refuses exactly those
// states (「아직 러닝이 끝나지 않았어요」) and whose `confirm_return_tx` raises `run_not_ended` — a
// door that cannot clear the block, on the runner who most needs the one that can.
// ⚠ THE SAME SENTENCE COVERED A SHIPPED ARM: `incident_review` is gated whether or not the run
//   ended (0092:116), so an incident escalated mid-walk drew the same return-seal exit onto the
//   same refusing frame. Codex named the two new words; the property is 「no exit onto a screen that
//   refuses the state」, and this arm is the third place it was false. It now has no exit — nothing
//   the runner does clears it; the operator's case does.
//
// ═══ THE PROPERTY, stated without reference to any mutation ═══
// (1) A gated answer is READ only when its `waiting_on` is a word this build knows AND its `exit`
//     is the exit the server pairs with that word (runner_work_gate's `case`, 0224:1162-1169,
//     restated in EXIT_FOR). Every other gated answer — an unknown word, an unknown exit, a pair
//     that disagrees, a custody shape whose status contradicts it — falls CLOSED to one neutral
//     face: no exit, no return-seal sentence (the door stays shut; `work-gate-door.ts`).
// (2) An exit is drawn only onto a screen that ACCEPTS the booking's state: return-seal needs a
//     stamped `run_ended_at` on `active`/`incident_review`; the meetup screen's 러닝 시작하기 door
//     needs `picked_up`; the run screen's stop needs `active` with no `run_ended_at`.
//     `app/test/work-gate-strip.test.cjs` enumerates every tuple 0224's gate can return and checks
//     each drawn exit against those screens' own guards (read as source, comments stripped).

/** The five `waiting_on` words `runner_work_gate` returns (0092 §6 + 0224 §E). */
export const WORK_GATE_WAITING_ON = ['both', 'runner', 'owner', 'start_run', 'end_run'] as const;
export type KnownWaitingOn = typeof WORK_GATE_WAITING_ON[number];
/** `'unknown'` = the server answered with a word this build does not know. Never mapped onto a
 *  known word; the strip renders it as the neutral face. */
export type WaitingOnRead = KnownWaitingOn | 'unknown';

/** The five `exit` words, one per `waiting_on` word. */
export const WORK_GATE_EXITS = [
  'both_confirm_return', 'runner_confirm_return', 'owner_confirm_return', 'runner_start_run', 'runner_end_run',
] as const;
export type KnownExit = typeof WORK_GATE_EXITS[number];
export type ExitRead = KnownExit | 'unknown';

/** runner_work_gate's `case g.waiting_on … end` (0224:1162-1169), restated. A gated answer whose
 *  exit is not this one is an answer the two halves of the server disagree about, and it is read
 *  as neither. */
export const EXIT_FOR: Record<KnownWaitingOn, KnownExit> = {
  runner: 'runner_confirm_return',
  owner: 'owner_confirm_return',
  both: 'both_confirm_return',
  start_run: 'runner_start_run',
  end_run: 'runner_end_run',
};

/** The mapper's half (api.ts `fetchRunnerWorkGate`). `null`/`undefined` stays `null` (the server
 *  sends no word for an un-gated runner); anything else that is not a known word is `'unknown'`. */
export function readWaitingOn(v: unknown): WaitingOnRead | null {
  if (v === null || v === undefined) return null;
  return typeof v === 'string' && (WORK_GATE_WAITING_ON as readonly string[]).includes(v)
    ? (v as KnownWaitingOn) : 'unknown';
}
export function readExit(v: unknown): ExitRead | null {
  if (v === null || v === undefined) return null;
  return typeof v === 'string' && (WORK_GATE_EXITS as readonly string[]).includes(v)
    ? (v as KnownExit) : 'unknown';
}

/** The fields of `RunnerWorkGate` (api.ts) this decision reads. */
export interface WorkGateStripFacts {
  gated: boolean;
  bookingId?: string | null;
  rawStatus?: string | null;
  runEndedAt?: string | null;
  waitingOn?: WaitingOnRead | null;
  exit?: ExitRead | null;
}

export type WorkGateRoute = 'return_seal' | 'meetup' | 'run';
export type WorkGateHref =
  | { pathname: '/runner/return-seal'; params: { bid: string } }
  | '/runner/meetup'
  | '/runner/run';

export interface WorkGateExitDoor {
  label: string;
  route: WorkGateRoute;
  /** Where to push. ⚠ `/runner/meetup` and `/runner/run` take NO param and read
   *  `runnerJob.bookingId` (store.ts), so the caller writes `bookingId` into the store first —
   *  exactly what home's `openJob` does before it pushes any of these three. */
  href: WorkGateHref;
  bookingId: string;
  /** What VoiceOver says for the strip when it is a button. */
  a11y: string;
}

export interface WorkGateStrip {
  /** Which reading this is. `unknown` is the fail-closed face. */
  kind: 'return' | 'start_run' | 'end_run' | 'unknown';
  /** The dot on home: `act` = the runner's own move, `wait` = someone else's, `neutral` = this build
   *  cannot say whose. */
  tone: 'act' | 'wait' | 'neutral';
  /** Home's two lines. */
  why: string;
  sub: string;
  /** null = the strip is a SENTENCE, not a button — nothing the runner can do from here. */
  exit: WorkGateExitDoor | null;
  /** The shut accept door's own sentence — home's front ticket draws it, and `work-gate-door.ts`
   *  appends it to every shut 수락 door's accessibilityLabel on 요청. */
  doorBlocked: string;
  /** 요청's two lines (that strip is framed around the accept door rather than around the run). */
  requestsWhy: string;
  requestsSub: string;
}

// ── copy — the return arms are byte-identical to what each screen drew before this module ──
export const REQUESTS_KEEP_KO = '시작 시각 전까지 요청은 남아 있어요';
export const RETURN_EXIT_KO = '반환 봉인 찍기 ›';
export const RETURN_DOOR_BLOCKED_KO = '반환 확인이 끝나면 여기서 수락할 수 있어요';
/** An incident with no stamped run end: no return can be confirmed (`confirm_return_tx` raises
 *  `run_not_ended`) and the run screen draws no start/stop for `incident_review` — the operator's
 *  case is the only thing that moves it. */
export const INCIDENT_OPEN_SUB_KO = '담당자 확인이 끝나야 새 요청을 받을 수 있어요';
export const INCIDENT_DOOR_BLOCKED_KO = '담당자가 확인하는 동안에는 수락할 수 없어요';

// 0224 §C's party sentences say the same facts, so a runner who tapped the push reads the same
// thing on the screen it opens.
export const START_WHY_KO = '인계는 끝났는데 러닝이 아직 시작되지 않았어요';
export const START_SUB_KO = '러닝을 시작해야 새 요청을 받을 수 있어요';
/** The label runner home's own ticket and the meetup screen's CTA already use for this move. */
export const START_EXIT_KO = '러닝 시작하기 ›';
export const START_DOOR_BLOCKED_KO = '러닝을 시작해야 여기서 수락할 수 있어요';

export const END_WHY_KO = '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요';
export const END_SUB_KO = '러닝을 종료해야 새 요청을 받을 수 있어요';
/** The run screen, re-entered on an `active` booking, draws 「기록 이어가기」 and then 「러닝 종료」
 *  (run.tsx `resumable`) — so the label names the screen and the move, not a one-tap stop. */
export const END_EXIT_KO = '러닝 화면에서 종료하기 ›';
export const END_DOOR_BLOCKED_KO = '러닝을 종료해야 여기서 수락할 수 있어요';

// The fail-closed face. It claims only what is known — the gate is SHUT — and names no cause and
// no remedy, because this build could not read the one the server gave.
export const UNKNOWN_WHY_KO = '예약 상태를 확인하는 중이에요';
export const UNKNOWN_SUB_KO = '확인되기 전에는 새 요청을 수락할 수 없어요';
export const UNKNOWN_DOOR_BLOCKED_KO = '예약 상태를 확인하는 중이라 지금은 수락할 수 없어요';

const neutral = (): WorkGateStrip => ({
  kind: 'unknown', tone: 'neutral', why: UNKNOWN_WHY_KO, sub: UNKNOWN_SUB_KO, exit: null,
  doorBlocked: UNKNOWN_DOOR_BLOCKED_KO,
  requestsWhy: UNKNOWN_DOOR_BLOCKED_KO, requestsSub: REQUESTS_KEEP_KO,
});

const door = (route: WorkGateRoute, bookingId: string, label: string, a11y: string): WorkGateExitDoor => ({
  label, route, bookingId, a11y,
  href: route === 'return_seal'
    ? { pathname: '/runner/return-seal', params: { bid: bookingId } }
    : route === 'meetup' ? '/runner/meetup' : '/runner/run',
});

/**
 * The strip for a gate read, or `null` when there is no strip to draw (the runner is not gated).
 * ⚠ `gated === true` only — a non-boolean `gated` is not a gate this module reads; the door module
 *   treats it as an unreadable answer and says so.
 */
export function workGateStrip(g: WorkGateStripFacts | null | undefined): WorkGateStrip | null {
  if (!g || g.gated !== true) return null;
  const w = g.waitingOn ?? null;
  const bid = typeof g.bookingId === 'string' && g.bookingId !== '' ? g.bookingId : null;
  const status = g.rawStatus ?? null;
  const ended = g.runEndedAt != null;
  // Unknown or absent word, or an exit that is not the word's own: fail CLOSED.
  if (w === null || w === 'unknown') return neutral();
  if (g.exit !== EXIT_FOR[w]) return neutral();

  if (w === 'start_run') {
    // 0224 §B: this shape IS status `picked_up`. A start word on any other status is a
    // contradiction, and the meetup screen's start door exists only for `picked_up`.
    if (status !== 'picked_up' || ended) return neutral();
    return {
      kind: 'start_run', tone: 'act', why: START_WHY_KO, sub: START_SUB_KO,
      exit: bid ? door('meetup', bid, START_EXIT_KO, '러닝 시작 화면으로 이동') : null,
      doorBlocked: START_DOOR_BLOCKED_KO,
      requestsWhy: START_DOOR_BLOCKED_KO, requestsSub: `${START_WHY_KO} · ${REQUESTS_KEEP_KO}`,
    };
  }
  if (w === 'end_run') {
    // 0224 §B: this shape IS `active` with no `run_ended_at`. A stamped end means the run is over
    // (its exit would be the RETURN), so the contradiction is read as neither.
    if (status !== 'active' || ended) return neutral();
    return {
      kind: 'end_run', tone: 'act', why: END_WHY_KO, sub: END_SUB_KO,
      exit: bid ? door('run', bid, END_EXIT_KO, '러닝 화면으로 이동해 종료하기') : null,
      doorBlocked: END_DOOR_BLOCKED_KO,
      requestsWhy: END_DOOR_BLOCKED_KO, requestsSub: `${END_WHY_KO} · ${REQUESTS_KEEP_KO}`,
    };
  }

  // ── the three RETURN words ──
  // 0092 §6's arms admit exactly two statuses for them: `active` with a stamped end, and
  // `incident_review` (ended or not). Anything else is not a shape the gate produces.
  if (status !== 'active' && status !== 'incident_review') return neutral();
  if (status === 'active' && !ended) return neutral();
  const incident = status === 'incident_review';
  // [runner-journey-8] 「지난 러닝」 is keyed on `run_ended_at`, not on `rawStatus` alone.
  const why = incident
    ? (ended ? '지난 러닝이 담당자 확인 중이에요' : '진행 중인 러닝을 담당자가 확인하고 있어요')
    : w === 'owner'
      ? '보호자 확인 대기 중이에요'
      : '지난 러닝의 반환 확인이 아직이에요';
  // An open incident whose run never ended: no stamp is possible, so no stamping sentence.
  const sub = incident && !ended
    ? INCIDENT_OPEN_SUB_KO
    : w === 'owner'
      ? '내 봉인은 끝났어요 — 보호자가 찍으면 새 요청을 받을 수 있어요'
      : w === 'runner'
        ? '내 봉인 전 — 찍으면 보호자 확인만 남아요'
        : '둘 다 찍혀야 새 요청을 받아요';
  // The exit exists only where return-seal ACCEPTS the state (a stamped end) and the runner's own
  // stamp is still owed — `owner` means they already stamped, and 「반환 봉인 찍기」 there would be a
  // lie about their own action (0092 §6 splits `waiting_on` for exactly this sentence).
  const exit = w !== 'owner' && ended && bid
    ? door('return_seal', bid, RETURN_EXIT_KO, '반환 봉인 화면으로 이동')
    : null;
  return {
    kind: 'return', tone: w === 'owner' || (incident && !ended) ? 'wait' : 'act', why, sub, exit,
    doorBlocked: incident && !ended ? INCIDENT_DOOR_BLOCKED_KO : RETURN_DOOR_BLOCKED_KO,
    // 요청's strip — its shipped copy, unchanged for every state that had an honest exit.
    requestsWhy: incident ? INCIDENT_DOOR_BLOCKED_KO : RETURN_DOOR_BLOCKED_KO,
    requestsSub: w === 'owner'
      ? `내 봉인은 끝났어요 — 보호자가 찍으면 열려요 · ${REQUESTS_KEEP_KO}`
      : REQUESTS_KEEP_KO,
  };
}
