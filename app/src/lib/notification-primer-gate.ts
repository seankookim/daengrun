// Should the notification primer be shown, or the token simply registered? — the PURE half of
// `src/components/notification-primer.tsx` (HIG row S1 / O3).
//
// It knows no RN, no expo-notifications and no storage, so `test/notification-primer-gate.test.cjs`
// pins this decision against the REAL compiled source (the `notification-prefs.ts` idiom) rather
// than a retyped copy. The component supplies the two facts; this function owns the rule.
//
// 🔴 WHY THE RULE IS WORTH ISOLATING: iOS asks exactly once. `requestPermissionsAsync` on a
// `denied` account does not re-prompt — it returns `denied` silently — so an unprimed ask at first
// home entry spends the single question of a person who has not yet been told what arrives. The
// primer exists to spend that question knowingly, and this function is the only place that decides
// whether it gets spent at all.

/** What the caller must do, given the permission it read and the dismissed flag it stored. */
export type PrimerAction =
  /** Draw the primer. The system alert fires on ITS button, never on mount. */
  | 'primer'
  /** Already granted — no question to ask. Register the token. */
  | 'register'
  /** Nothing to draw and nothing to ask: permanently denied, already dismissed, or unknown. */
  | 'skip';

/** The shape `Notifications.getPermissionsAsync()` returns, narrowed to the two fields that decide. */
export interface PushPermissionRead {
  /** 'granted' · 'denied' · 'undetermined' — anything else is treated as unknown. */
  status?: string | null;
  /** false ⇒ iOS will never show the alert again; the primer would be a dead end. */
  canAskAgain?: boolean | null;
}

/**
 * The decision. `perm` is null when the permission could not be read at all (an old build with no
 * expo-notifications, or a throwing module) — that is NOT a refusal and must not be drawn as one,
 * so it folds to 'skip' exactly the way `registerPushToken` folds to a silent return.
 *
 * ⚠ ORDER IS LOAD-BEARING. `granted` wins over `dismissed`: a person who dismissed the primer and
 * later turned notifications on in Settings must still get their token registered, or every push
 * this product sends lands nowhere and nobody ever files a bug about a push they never saw.
 */
export function primerAction(
  perm: PushPermissionRead | null | undefined,
  dismissed: boolean,
): PrimerAction {
  if (!perm || typeof perm.status !== 'string' || perm.status.length === 0) return 'skip';
  if (perm.status === 'granted') return 'register';
  // The same conjunct `push.ts` reads before it would ever prompt. `canAskAgain === false` is the
  // only value that closes the door — `undefined` from a platform that does not report it must not
  // be read as a refusal.
  if (perm.canAskAgain === false) return 'skip';
  // Once per install. The flag is set by BOTH primer buttons, so a person who answered the system
  // alert and a person who tapped 나중에 are alike afterwards: neither is asked again in-app.
  if (dismissed) return 'skip';
  return 'primer';
}
