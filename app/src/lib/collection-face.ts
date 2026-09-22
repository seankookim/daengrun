// collection-face — which face a collection section on `/cards` wears, as a pure function.
//
// ═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════════════════════════
// Measured on the simulator, 2026-09-22, signed out: `/cards` rendered the 도장 failure strip
// (with 다시 시도) and **no 코스 패치 section at all** — no header, no failure, no empty state,
// nothing. The section simply was not on the screen.
//
// 🔴 THE ROOT CAUSE IS NOT RLS AND IS NOT AN ERROR. `fetchCoursePatches` (api.ts) opens with
//
//     const { data: user } = await supabase.auth.getUser();
//     if (!user.user) return { earned: [], locked: [] };
//
// — a SUCCESSFUL read of zero rows, deliberately, so that signed-out callers do not throw. Its
// sibling `fetchStampStats` instead `throw`s '로그인이 필요해요', which is why one section showed
// its failure face and the other vanished. The patches section was gated on
// `patches && patchTotal > 0`, and a successful-but-empty read satisfies the first clause and
// fails the second, so every branch on the screen was false at once.
//
// **A section that renders nothing is indistinguishable from a section that does not exist**, and
// an empty collection is exactly what a new user has — so the one state the screen most needed to
// speak about was the one state it was silent in. That is the silent-catch→happy-UI law with the
// catch replaced by a count.
//
// ═══ WHY IT IS A FUNCTION AND NOT A FIXED CONDITION ══════════════════════════════════════════
// The bug was not a wrong boolean; it was an INCOMPLETE ENUMERATION written as a chain of `&&`s
// in JSX, where 「no branch matched」 has no name and produces no output. Naming the faces makes
// the missing one a value the screen has to handle, and makes the property testable at all:
// `app/test/collection-face.test.cjs` walks the whole input space and asserts that `suppressed`
// — the only face that draws nothing — is returned if and only if the caller says BOTH reads on
// the screen failed and one shared box is already speaking for them.
//
// ⚠ Deliberately knows nothing about 도장 or 패치. It takes the four facts a section actually has
// and returns one of five words; the copy, the ordering and the markup stay in `cards.tsx`.

/** The five things a collection section can be. Exactly one is drawn per section, per render. */
export type CollectionFace =
  /** the read has not come back yet — a skeleton line, never a 0 and never an empty state */
  | 'loading'
  /** the read threw — say so, with a retry that re-runs THIS read alone */
  | 'failed'
  /** the read SUCCEEDED and there is nothing in it yet — the face this file was written for */
  | 'empty'
  /** the read succeeded and there is something to draw */
  | 'list'
  /** both reads on the screen failed and one shared box owns the message — draw nothing HERE */
  | 'suppressed';

export interface CollectionFaceInput {
  /** the read returned (its state is non-null). A successful empty read is `true`. */
  loaded: boolean;
  /** how many items the read returned. Only consulted when `loaded`. */
  count: number;
  /** the read threw. */
  failed: boolean;
  /** every read on this screen failed, so the screen's single shared failure box speaks instead. */
  bothFailed: boolean;
}

export function collectionFace(x: CollectionFaceInput): CollectionFace {
  // ① The shared box first, because it is the one case where drawing nothing here is correct —
  //    the message is on the screen, one level up. Nothing else may return this value.
  if (x.bothFailed) return 'suppressed';
  // ② Data that has arrived outranks a failure flag: a retry that fails keeps whatever had
  //    already loaded (cards.tsx sets state on success only), and a screen that hid real data
  //    behind a stale error would be lying in the other direction.
  if (x.loaded) return x.count > 0 ? 'list' : 'empty';
  // ③ Nothing has arrived. Which of the two silent states it is, is the whole point of ③/④.
  if (x.failed) return 'failed';
  // ④ Not loaded, not failed — still in flight. Loading is not 0 and it is not 「비어 있어요」.
  return 'loading';
}
