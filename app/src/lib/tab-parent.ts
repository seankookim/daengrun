// Which tab does a non-tab dock screen belong to? — the PURE half of `bottomnav.tsx`'s active
// state (HIG row N3, components/tab-bars: 「every screen that shows the dock should show a selected
// tab」). Ruling: announcer, 2026-09-22 — KEEP the dock on these screens and highlight the PARENT.
//
// It knows no RN and no router, so `test/tab-parent.test.cjs` pins it against the REAL compiled
// source AND cross-reads `bottomnav.tsx` as text, so a parent that stops being a tab path fails
// loudly instead of silently un-highlighting the dock again.
//
// THE DEFECT THIS CLOSES: `alerts.tsx:269`, `cards.tsx:250` and `safety.tsx:272` render <BottomNav>
// and appear in neither OWNER_TABS nor RUNNER_TABS, so `active` was false for all five tabs — a
// dock with no indicator anywhere, which tells the person the app has forgotten where they are.
//
// ⚠ THE RULE, and it is measured rather than chosen: the parent is the tab whose screen carries an
// UNCONDITIONAL door to the route. 마이 (`my.tsx`) is the hub that lists all three as menu rows —
// 안심 센터 (`my.tsx:186`), 알림 (`my.tsx:205`), and the owner's 기록 row (`my.tsx:203`) — and those
// rows render for every account in that role. The homes link to the same three as SHORTCUTS (the
// masthead bell, the 안심 센터 draw button, the 기록 section), which is why home is not the parent:
// a shortcut says 「go there」, a hub row says 「it lives here」.
// The one place the two roles genuinely differ is 기록: Sean deleted the runner's 마이 row on
// 2026-08-11 (「러너 페이지의 내 기록 같은 건 마이가 아니라 홈에 있어야 한다」, quoted at
// `runner/home.tsx:1506`), so for a runner the only hub door to /cards is 홈. That is the whole
// reason this function takes a role.

export type TabRole = 'owner' | 'runner';

/**
 * route → the tab path that owns it, per role. `null` on either side would mean 「no parent」 and
 * is deliberately not expressible: a route in this table has a parent in BOTH roles or it does not
 * belong here. A route absent from the table resolves to null (see `parentTabPath`), which is the
 * correct answer for a real tab and for a pushed screen that draws no dock.
 *
 * ⚠ EVERY VALUE MUST BE A PATH IN `OWNER_TABS` / `RUNNER_TABS` (bottomnav.tsx) FOR THAT ROLE.
 * Nothing at runtime notices when it is not — the dock simply goes back to having no selected tab,
 * which is the exact state this file exists to fix and is invisible to every gate. The drift pin in
 * `test/tab-parent.test.cjs` reads both artifacts and is the only thing that can catch it.
 */
export const TAB_PARENTS: Record<string, Record<TabRole, string>> = {
  // 알림함. Both roles reach it from the masthead bell (a shortcut) and from 마이 › 알림 (the row).
  '/alerts': { owner: '/my', runner: '/my' },
  // 안심 센터. 마이 › 안심 센터 is the first row of the hub in both roles; the homes, meetup, live,
  // pay and report screens all link to it as a shortcut.
  '/safety': { owner: '/my', runner: '/my' },
  // 컬렉션 (ANNEX — 도장 + 코스 패치). The role split above lives here and only here.
  '/cards': { owner: '/my', runner: '/runner/home' },
};

/**
 * The tab that should read as selected while `pathname` is on screen, or null when the route is
 * itself a tab (the dock matches it directly) or has no dock at all.
 *
 * 🔴 THIS IS FOR THE DOCK'S HIGHLIGHT ONLY — never for `tabNeighbors`. A left/right swipe on
 * /alerts must go NOWHERE: resolving the parent there would hand the gesture 마이's neighbours, so
 * a swipe on 알림 would land on 수익 or 샵, a screen the person never chose and cannot get back
 * from with the same gesture. `tabNeighbors` keeps its exact-path match, `TabSwipe` sees
 * [null, null] and attaches no PanResponder at all (`tabswipe.tsx`, the `isTab` early return).
 */
export function parentTabPath(pathname: string, role: TabRole): string | null {
  const row = TAB_PARENTS[pathname];
  if (!row) return null;
  return row[role] ?? null;
}
