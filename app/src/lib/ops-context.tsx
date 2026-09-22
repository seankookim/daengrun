import { createContext, ReactNode, useContext } from 'react';
import { OpsMe } from './api';

// ops-context — ONE answer to `ops_me()` for the whole `/ops` stack.
//
// WHY THIS EXISTS, measured on trunk 0776c11: `ops/_layout.tsx` calls `opsMe()` to decide whether
// to draw the console at all, and `ops/index.tsx` called it AGAIN inside a `useFocusEffect` to
// decide which desks to draw. So opening the console cost two round trips to the same RPC, and
// every return from a desk screen (pay a runner, post a box, resolve a strand) cost another — an
// N+1 on a question whose answer is roster membership, which nothing inside this console can
// change. The layout has already asked; this is how the answer reaches the screens.
//
// 🔴 **THIS IS NOT A SECURITY BOUNDARY AND MUST NEVER BE READ AS ONE**, exactly as `_layout`'s own
//    header says. Every door behind the gate carries its own `ops_recipients_for(...)` check ahead
//    of every read, and a build that deleted this file would leak NOTHING. What the context buys
//    is that the app does not draw a console for someone who cannot use one, and does not draw a
//    DESK whose door would answer `not_ops` — 「no dead buttons」, never 「no access」.
//
// ⚠ **`kinds: null` MEANS UNREAD AND MUST KEEP MEANING UNREAD.** 0206 gates the 반환 좌초 and
//   인계 멈춤 sections on `kinds.includes(...)`, and an unread answer is not a 'no': drawing those
//   sections on an unknown would be a button that opens onto a refusal, and claiming they are
//   empty would be a number nobody measured. The default value below is `{ isOps: false,
//   kinds: null }` for that reason — a component rendered outside the provider (which cannot
//   happen inside `/ops`, but a stack is a stack) reads UNKNOWN rather than a confident false.
export interface OpsCtx {
  /** `ops_me().is_ops` — 「can you use this console」, decided server-side (0198 §A). */
  isOps: boolean;
  /** The caller's own active ops classes, or **null when the answer has not been read**. Never an
   *  empty array for 「we do not know」: `[]` is a measured 「you hold none」. */
  kinds: string[] | null;
  /** Re-ask the server and update this context. Used by the console's pull-to-refresh, which is
   *  the ONE refresh path — `_layout` asks on mount, this re-asks on demand, and no screen calls
   *  `opsMe()` on its own any more. Resolves when the re-ask settles, so a RefreshControl can
   *  await it; a FAILED refresh keeps the last known answer rather than tearing down a working
   *  console, because a network blip is not a removal from the roster. */
  refresh: () => Promise<void>;
}

const OpsContext = createContext<OpsCtx>({
  isOps: false,
  kinds: null,
  refresh: async () => {},
});

export function OpsProvider({ value, children }: { value: OpsCtx; children: ReactNode }) {
  return <OpsContext.Provider value={value}>{children}</OpsContext.Provider>;
}

/** The console's own answer about the caller. Inside `/ops` this is always the layout's value —
 *  the gate has already passed, so `isOps` is true and `kinds` is whatever the server said. */
export function useOps(): OpsCtx {
  return useContext(OpsContext);
}
