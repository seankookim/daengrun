// The alerts inbox's handoff-cycle grouping — PURE, so `test/alerts-group.test.cjs` pins it
// against the real compiled source (the `notification-prefs` / `notification-route` idiom).
//
// WHAT IT IS FOR. `transition-booking`'s confirm_handoff arm writes 「인계 확인 요청」 every time a
// party taps 인계하기, and 0183's `sweep_run_end_recovery` arm ⓒ re-sends the same ask when a
// handoff has stayed one-sided. All of those rows are the SAME question asked again, and the
// inbox drew each one as its own card — a re-asked handoff read as three or four identical
// unanswered demands stacked on top of each other, which is both noise and a lie about how many
// things need doing.
//
// 0183 gave that question an IDENTITY: `notifications.handoff_cycle_id`, minted on the booking by
// the `_handoff_cycle` trigger and stamped onto the ask by the edge (index.ts:406) and by the
// sweep (0183:383). `_notification_cycle_guard` refuses an ask whose id is not the booking's
// current cycle, so two rows sharing a non-null id are the same cycle's ask — never two different
// asks, and never a different message: the column is the ask's alone, and the edge's own control
// pin asserts that no other arm writes it (`_test/transition_booking_actions_test.ts:505`).
//
// ⚠ A NULL CYCLE IS NOT A GROUP KEY. Every notification that is not a handoff ask carries NULL,
// and so do asks that predate 0183. Grouping those together would collapse unrelated messages
// into one card under a 「×n 재요청」 badge — a fabricated count over rows that share nothing.
// NULL rows therefore each become a group of one, which is the pre-slice rendering exactly.
//
// ⚠ THE ORDER IS COMPUTED, NOT INHERITED. `fetchNotifications` returns newest-first today, and a
// function that called its first-seen row 「the newest」 would be asserting a property of its
// caller rather than of its input. `newest` is chosen by `createdAt`, and the groups come back
// ordered by their own newest, so the claim the badge makes is one this file can back.

/** The fields the grouping needs. `LiveNoti` satisfies it; the test uses the minimum. */
export interface CycleRow {
  id: string;
  /** The raw `notifications.created_at` (ISO 8601). Compared with `Date.parse` — epoch-safe, and
   *  never a device-clock read: no calendar field of it is ever looked at here. */
  createdAt: string;
  unread: boolean;
  /** `notifications.handoff_cycle_id` — non-null only on 「인계 확인 요청」 rows (0183). */
  handoffCycleId: string | null;
}

export interface CycleGroup<T> {
  /** The row the inbox draws and the tap opens — the most recent ask of this cycle. */
  newest: T;
  /** The earlier re-sends, newest first. Empty for every ordinary row. */
  older: T[];
  /** `older.length + 1`. 1 for an ordinary row; 3 for an ask sent twice more. */
  count: number;
  /** True when ANY row in the cycle is unread — the badge stands for all of them. */
  unread: boolean;
}

/** The badge an inbox row wears when a cycle holds more than one ask. Korean: it is UI copy. */
export function resendBadge(count: number): string {
  return `×${count} 재요청`;
}

/** An unparseable or absent timestamp sorts LAST rather than throwing or winning — a row that
 *  cannot say when it arrived must never be picked as 「the newest」. */
function at(row: CycleRow): number {
  const t = Date.parse(row.createdAt);
  return Number.isNaN(t) ? -Infinity : t;
}

/**
 * Collapse the handoff-ask re-sends, leaving every other row untouched.
 *
 * Rows with a NULL `handoffCycleId` each come back as their own group of one. Rows sharing a
 * non-null id come back as ONE group whose `newest` is the most recent of them. Groups are
 * ordered by their own `newest`, most recent first; ties keep the input's order, so a stable
 * server ordering stays stable here.
 */
export function groupByHandoffCycle<T extends CycleRow>(rows: readonly T[]): CycleGroup<T>[] {
  const groups: { g: CycleGroup<T>; seen: number }[] = [];
  const byCycle = new Map<string, { g: CycleGroup<T>; seen: number }>();

  rows.forEach((row, i) => {
    const cid = row.handoffCycleId;
    if (!cid) {
      groups.push({ g: { newest: row, older: [], count: 1, unread: row.unread }, seen: i });
      return;
    }
    const held = byCycle.get(cid);
    if (!held) {
      const entry = { g: { newest: row, older: [] as T[], count: 1, unread: row.unread }, seen: i };
      byCycle.set(cid, entry);
      groups.push(entry);
      return;
    }
    const { g } = held;
    g.count += 1;
    g.unread = g.unread || row.unread;
    // whichever of the two is more recent becomes the head; the other joins the collapsed list
    if (at(row) > at(g.newest)) { g.older.push(g.newest); g.newest = row; }
    else { g.older.push(row); }
  });

  for (const { g } of groups) g.older.sort((a, b) => at(b) - at(a));
  return groups
    .slice()
    .sort((a, b) => (at(b.g.newest) - at(a.g.newest)) || (a.seen - b.seen))
    .map(({ g }) => g);
}
