// Owner Live Activity — the phase → face mapping, as a pure module.
//
// WHY THIS FILE EXISTS, and it is not "extracting a helper".
// `src/activities/OwnerRunActivity.tsx` is a `'widget'` function: it is STRINGIFIED and executed
// inside the widget extension, where module-scope closures do not exist (the CORAL ReferenceError,
// 2026-07-23, recorded in that file's header). So the widget CANNOT import this module — it
// inlines the same table and the same resolution, and `app/test/live-activity-face.test.cjs`
// executes BOTH (this module directly, the widget through an esbuild bundle with SwiftUI stubs)
// and requires them to agree, phase by phase. The two copies are a constraint of the runtime, not
// a duplication anybody chose; the test is what stops them drifting.
//
// THE DEFECT THIS CLOSES (measured on trunk 6d02769). The widget's phase union was
// 'pre'|'running'|'stale'|'done'|'ended' and its pill/title/foot chains all ended in a bare `else`.
// The server has pushed `phase: 'homeward'` since 0083 (`_owner_la_run_end_tg`, and the 귀가 arm of
// `owner_la_sweep_stale` — 0177 carries the current body). Every one of those pushes fell through
// to pill `ENDED` + 「위치 수신 대기 중」 + 「러너가 달리기 시작하면 거리가 표시돼요」: the owner's lock
// screen said the walk home had ENDED and that the run had not started, while their dog was being
// walked back. Two lies in one banner, both from an `else`.
//
// THE LAW THIS ENCODES: an unknown phase is NOT `ended`. A banner that does not know what is
// happening says 「상태 확인 중」 — it never inherits the vocabulary of whichever branch happened to
// be last in the chain. A terminal claim is the most expensive thing this surface can get wrong.

/** Every phase this client has a face for. The server's set is checked against this in the test. */
export type OwnerRunPhase = 'pre' | 'running' | 'stale' | 'homeward' | 'stopping' | 'done' | 'ended';

/**
 * Pill tone. The widget owns the hex values (they must live inside the stringified function);
 * this is the NAME of the tone, which is the part the two copies have to agree on.
 *   live    — something is happening right now (coral)
 *   settled — a fact that is finished and true (sage)
 *   muted   — no live claim available (grey)
 */
export type OwnerRunTone = 'live' | 'settled' | 'muted';

export interface OwnerRunFaceEntry {
  pill: string;
  tone: OwnerRunTone;
  /** Shown when the hero number is not drawn. */
  title: string;
  /** The line under the title. */
  foot: string;
  /** May this phase draw the big distance number at all? */
  numeric: boolean;
}

// ⚠ KEEP BYTE-IDENTICAL to the `OWNER_RUN_FACES` literal inside OwnerRunActivity.tsx's widget
// function. The test executes both and compares; a change here that is not made there reddens.
export const OWNER_RUN_FACES: Record<OwnerRunPhase, OwnerRunFaceEntry> = {
  pre: { pill: 'HANDOFF', tone: 'muted', title: '인계가 확인됐어요', foot: '곧 러닝이 시작돼요', numeric: false },
  running: { pill: 'RUNNING', tone: 'live', title: '위치 수신 대기 중', foot: '러너가 달리기 시작하면 거리가 표시돼요', numeric: true },
  stale: { pill: 'NO SIGNAL', tone: 'muted', title: '위치 수신 대기 중', foot: '러너가 달리기 시작하면 거리가 표시돼요', numeric: true },
  homeward: { pill: '귀가 중', tone: 'settled', title: '집으로 가는 중', foot: '앱에서 자세히 확인하세요', numeric: false },
  stopping: { pill: '마무리 중', tone: 'live', title: '러닝을 마무리하고 있어요', foot: '거리를 정리하고 있어요', numeric: false },
  done: { pill: 'DONE', tone: 'settled', title: '러닝 완료', foot: '리포트 보기 ›', numeric: true },
  ended: { pill: 'ENDED', tone: 'muted', title: '러닝이 종료됐어요', foot: '앱에서 자세히 확인하세요', numeric: true },
};

/** The face for a phase this build has never heard of. Deliberately says nothing terminal. */
export const OWNER_RUN_FACE_UNKNOWN: OwnerRunFaceEntry = {
  pill: '상태 확인 중', tone: 'muted', title: '상태 확인 중', foot: '앱에서 자세히 확인하세요', numeric: false,
};

export const OWNER_RUN_PHASES = Object.keys(OWNER_RUN_FACES) as OwnerRunPhase[];

/** The subset of the payload the face depends on. Every field is a preformatted string — the
 *  widget draws, it does not compute, so nothing here is a number or a clock. */
export interface OwnerRunFaceInput {
  phase: string;
  km: string;
  targetKm: string;
  pace: string;
  elapsed: string;
  statusLine: string;
}

export interface OwnerRunFace {
  /** false = this build has no face for the phase; the neutral one is being used. */
  known: boolean;
  pill: string;
  tone: OwnerRunTone;
  /** true = draw the hero number. Both conditions: the phase allows it AND a number exists. */
  hasNum: boolean;
  title: string;
  foot: string;
  numUnit: string;
  footLeft: string;
  footRight: string;
}

/**
 * Resolve a pushed payload into the strings the banner draws.
 *
 * 귀가 (homeward) is the phase with real logic, and the logic is an honesty rule:
 *   · the TITLE is the server's own `statusLine`, verbatim. On the happy path 0083 sends
 *     「집으로 가는 중」; when the custody heartbeat has gone quiet the sweep sends its own
 *     「N분째 위치 신호가 없어요」. The client NEVER composes that minute count — it has no clock
 *     that can be trusted for it and the server already decided the sentence.
 *   · the FOOT carries the FROZEN km/elapsed the payload brought, and nothing else. 0083's own
 *     comment is the argument: 귀가 has no distance goal and no pace, so a hero-sized number on
 *     the lock screen would read as a live measurement of a walk that is not being measured.
 *     The numbers go in the small line, as a record.
 *   · `stopping` draws no number at all, for the reason 0168 wrote down at its own return shape:
 *     km and durationSec are explicitly NULL there because phase 1 does not know them, and a zero
 *     would be read as a measurement.
 */
export function ownerRunFace(p: OwnerRunFaceInput): OwnerRunFace {
  const table = OWNER_RUN_FACES as Record<string, OwnerRunFaceEntry | undefined>;
  const hit = table[p.phase];
  // `typeof hit.pill === 'string'` and not a bare truthiness check: a phase string of
  // 'constructor' or 'toString' resolves through the prototype to a FUNCTION, and a truthy
  // lookup would then hand the banner an object with no pill. The guard is one comparison.
  const known = !!hit && typeof hit.pill === 'string';
  const e = known ? (hit as OwnerRunFaceEntry) : OWNER_RUN_FACE_UNKNOWN;

  const hasNum = e.numeric && p.km !== '';

  // 귀가's title is the server's sentence; the table's title is only the fallback for a payload
  // that carried none.
  const title = p.phase === 'homeward' && p.statusLine !== '' ? p.statusLine : e.title;

  // 귀가's foot is the frozen record. Each part is included only if the payload actually carried
  // it — no '0.00km', no empty separator (honesty law: bind a real field or omit the element).
  let foot = e.foot;
  if (p.phase === 'homeward') {
    const parts: string[] = [];
    if (p.km !== '') parts.push(p.km + 'km');
    if (p.elapsed !== '') parts.push(p.elapsed);
    if (parts.length > 0) foot = parts.join(' · ');
  }

  // `'/ ' + '' + 'km'` used to render a naked '/ km' whenever targetKm was absent. A goal that
  // does not exist is omitted, not printed as a slash.
  const numUnit = p.phase === 'done' ? 'km 완주' : p.targetKm !== '' ? '/ ' + p.targetKm + 'km' : 'km';

  const footLeft =
    p.phase === 'running' ? (p.pace !== '' ? p.pace + ' · ' + p.elapsed : p.elapsed)
      : p.phase === 'done' ? (p.statusLine !== '' ? p.elapsed + ' · ' + p.statusLine : p.elapsed)
        : '';
  const footRight = p.phase === 'done' ? '리포트 보기 ›' : p.statusLine;

  return { known, pill: e.pill, tone: e.tone, hasNum, title, foot, numUnit, footLeft, footRight };
}
