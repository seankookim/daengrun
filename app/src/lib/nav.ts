import { router } from 'expo-router';
import { homePath } from '../components/bottomnav';

// Leaving a screen must always land somewhere.
//
// WHY THIS EXISTS (measured 2026-08-20). `router.back()` is a NO-OP on an empty stack, and this app
// produces single-entry stacks routinely: every route is reachable as `daengrun://<path>`, pushes
// deep-link straight to a screen (`src/lib/push.ts`), and the two Live Activities open
// `daengrun://runner/run` and `daengrun://owner/live` from the lock screen. The root Stack is
// `headerShown: false` + `gestureEnabled: false` (`app/_layout.tsx`), so there is no system back
// affordance and no back-swipe either — when a screen's own ‹ or ✕ no-ops, the user is TRAPPED with
// no way out but force-quitting. That was observed on `owner/live`: resolve finds no live booking,
// alerts, calls `back()`, nothing happens, and the owner is left on a blank screen with a dead ‹.
//
// Only one of the app's ~50 back call sites had ever guarded for this (`cards.tsx`). This makes that
// idiom the shared one so a new screen inherits it instead of rediscovering the trap.
//
// The fallback is `homePath()`, which is ROLE-AWARE — a runner must not be dropped on the owner
// home. ⚠ Known limitation, inherited not introduced: `session.role` is module state written by the
// role-select screen, so a cold deep link that skips it defaults to owner (see the hydration note in
// `src/auth-context.tsx`). Best available answer, and better than a hardcoded path.
export function goBackOrHome(): void {
  goBackOr(homePath());
}

/** Where `router.replace` can go — taken from the router itself so it tracks expo-router's own type. */
export type NavTarget = Parameters<typeof router.replace>[0];

// The same idiom with a screen-specific landing. Use it where the right place to be after a SUCCESS
// is known and is not the role home — after a review the booking's report, after a reschedule
// request the schedule, after a course pick the request form that reads it. `goBackOrHome` is this
// with the role home as the fallback.
// ⚠ With history, it still goes BACK (never pushes the fallback): the screen underneath is usually
// the fallback itself, and a push/replace there would leave two copies of it on the stack.
// `test/nav-back.test.cjs` refuses an unguarded `router.back()` ANYWHERE, this file included — the
// call below passes only because it sits under `canGoBack()`; un-guard it and that test reddens.
export function goBackOr(fallback: NavTarget): void {
  if (router.canGoBack()) router.back();
  else router.replace(fallback);
}
