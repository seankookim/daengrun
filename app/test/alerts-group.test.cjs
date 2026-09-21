// alerts-group.ts — tests run against the REAL compiled source (see run-alerts-group-tests.sh),
// not a retyped copy. Same idiom as notification-prefs / notification-route.
//
// WHAT THIS FILE IS FOR. The inbox drew one card per `notifications` row, and
// `transition-booking`'s confirm_handoff arm plus 0183's `sweep_run_end_recovery` arm ⓒ write
// 「인계 확인 요청」 every time the same handoff is asked again — so a re-asked handoff read as
// three or four identical unanswered demands. 0183 gave that question an identity
// (`notifications.handoff_cycle_id`), and this module is the decision that uses it.
//
// The mutations that redden it, named because a pin nobody can break is prose: group NULL cycles
// together · keep the FIRST row instead of the newest · count `older.length` instead of
// `older.length + 1` · read `unread` off the head alone · return insertion order instead of
// newest-first · let an unparseable timestamp win 「newest」 · drop `handoff_cycle_id` from
// api.ts's select · stop calling the function from alerts.tsx.
const fs = require('fs');
const path = require('path');
const { groupByHandoffCycle, resendBadge } = require('./alerts-group.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const CYCLE_A = 'aaaaaaaa-0000-0000-0000-000000000001';
const CYCLE_B = 'bbbbbbbb-0000-0000-0000-000000000002';
// newest → oldest, the order `fetchNotifications` returns
const iso = (min) => new Date(Date.UTC(2026, 8, 22, 10, min, 0)).toISOString();
const row = (id, min, cycle, unread = false) => ({ id, createdAt: iso(min), unread, handoffCycleId: cycle ?? null });
const ids = (gs) => gs.map((g) => g.newest.id);

// ── rows without a cycle stay separate — the pre-slice rendering, exactly ──────────────────────
{
  const rows = [row('n3', 30, null), row('n2', 20, null), row('n1', 10, null)];
  const g = groupByHandoffCycle(rows);
  t('three cycle-less rows → three groups of one (NULL is never a group key: it is on EVERY non-ask notification)',
    g.length === 3 && g.every((x) => x.count === 1 && x.older.length === 0), JSON.stringify(g.map((x) => x.count)));
  t('cycle-less rows keep their newest-first order', JSON.stringify(ids(g)) === JSON.stringify(['n3', 'n2', 'n1']), JSON.stringify(ids(g)));
}

// ── rows with the same cycle collapse to the NEWEST ───────────────────────────────────────────
{
  const rows = [row('a3', 30, CYCLE_A), row('a2', 20, CYCLE_A), row('a1', 10, CYCLE_A)];
  const g = groupByHandoffCycle(rows);
  t('three asks of one cycle → ONE group', g.length === 1, JSON.stringify(ids(g)));
  t('the head is the NEWEST ask, not the first seen', g[0].newest.id === 'a3', g[0].newest.id);
  t('the count is the whole cycle (3), not the collapsed remainder (2)', g[0].count === 3, String(g[0].count));
  t('the older re-sends are kept, newest first (nothing is discarded — they are still real rows)',
    JSON.stringify(g[0].older.map((r) => r.id)) === JSON.stringify(['a2', 'a1']), JSON.stringify(g[0].older.map((r) => r.id)));
}

// ── the head is chosen by TIMESTAMP, not by the caller's ordering ─────────────────────────────
// ⚠ This is the arm that separates 「the function knows which is newest」 from 「the server happened
// to sort for it」. Fed oldest-first, a first-seen implementation returns a3's predecessor.
{
  const g = groupByHandoffCycle([row('a1', 10, CYCLE_A), row('a2', 20, CYCLE_A), row('a3', 30, CYCLE_A)]);
  t('fed OLDEST-first, the head is still the newest ask (the order is computed, not inherited)',
    g.length === 1 && g[0].newest.id === 'a3' && g[0].count === 3, JSON.stringify(g.map((x) => [x.newest.id, x.count])));
}

// ── two cycles never merge, and a cycle never swallows a neighbour ────────────────────────────
{
  const rows = [row('b2', 50, CYCLE_B), row('a2', 40, CYCLE_A), row('x', 35, null), row('b1', 30, CYCLE_B), row('a1', 20, CYCLE_A)];
  const g = groupByHandoffCycle(rows);
  t('two cycles + one cycle-less row → three groups', g.length === 3, JSON.stringify(ids(g)));
  t('each cycle keeps its OWN rows (a different id is a different question, never the same card)',
    g[0].newest.id === 'b2' && g[0].count === 2 && g[1].newest.id === 'a2' && g[1].count === 2 && g[2].newest.id === 'x' && g[2].count === 1,
    JSON.stringify(g.map((x) => [x.newest.id, x.count])));
  t('groups come back ordered by their own newest',
    JSON.stringify(ids(g)) === JSON.stringify(['b2', 'a2', 'x']), JSON.stringify(ids(g)));
}

// ── unread is the OR over the cycle — the badge stands for all of them ─────────────────────────
{
  const readHeadUnreadTail = groupByHandoffCycle([row('a2', 20, CYCLE_A, false), row('a1', 10, CYCLE_A, true)]);
  t('a READ newest over an UNREAD re-send is an unread cycle (the question is still unanswered)',
    readHeadUnreadTail[0].unread === true);
  const allRead = groupByHandoffCycle([row('a2', 20, CYCLE_A, false), row('a1', 10, CYCLE_A, false)]);
  t('an all-read cycle is read (the OR does not manufacture an unread badge)', allRead[0].unread === false);
  const lone = groupByHandoffCycle([row('n1', 10, null, true)]);
  t('a cycle-less row carries its own unread, unchanged', lone[0].unread === true);
}

// ── a timestamp that cannot be read never wins 「the newest」 ───────────────────────────────────
{
  const bad = { id: 'bad', createdAt: 'not-a-date', unread: false, handoffCycleId: CYCLE_A };
  const g = groupByHandoffCycle([bad, row('a1', 10, CYCLE_A)]);
  t('an unparseable createdAt sorts LAST rather than being called the newest',
    g.length === 1 && g[0].newest.id === 'a1' && g[0].count === 2, JSON.stringify([g[0].newest.id, g[0].count]));
}

// ── degenerate inputs ─────────────────────────────────────────────────────────────────────────
t('an empty inbox groups to nothing (never one empty group)', groupByHandoffCycle([]).length === 0);
t('a single ask is a group of one — the badge never appears for an un-re-asked handoff',
  groupByHandoffCycle([row('a1', 10, CYCLE_A)])[0].count === 1);

// ── the badge copy ────────────────────────────────────────────────────────────────────────────
t('the resend badge names the real count', resendBadge(3) === '×3 재요청', resendBadge(3));
t('the badge is derived, never a fixed string', resendBadge(2) === '×2 재요청' && resendBadge(7) === '×7 재요청');

// ══════════════════════════════════════════════════════════════════════════════════════════
// SOURCE PINS — a pure function that is right and unused is indistinguishable from one that is
// wrong, and both leave this file green. `app/test/*.cjs` cannot import a `.tsx` route module
// (the same structural gap `check-device-clock.mjs` exists for), so these read the source with
// comment lines stripped — a comment quoting a call must not satisfy a check for the call.
// ══════════════════════════════════════════════════════════════════════════════════════════
{
  const strip = (p) => fs.readFileSync(p, 'utf8').split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');

  // ① the column is actually SELECTED. Without it every `handoffCycleId` is null, every cycle is
  // a group of one, and every behavioural pin above stays green over a feature that does nothing.
  const api = strip(path.resolve(__dirname, '../src/lib/api.ts'));
  const sel = api.match(/from\('notifications'\)\s*\n?\s*\.select\('([^']+)'\)/);
  t("api.ts still reads the notifications inbox with a literal select", !!sel, 'no .select() found after .from(\'notifications\')');
  t("the inbox select carries handoff_cycle_id (without it the grouping is dead and silent)",
    !!sel && sel[1].includes('handoff_cycle_id'), sel ? sel[1] : '');
  t('LiveNoti surfaces handoffCycleId and createdAt (the grouping needs the raw timestamp — when/dateLabel are KST display labels and cannot be compared)',
    /handoffCycleId: string \| null/.test(api) && /createdAt: string/.test(api));

  // ② the screen actually CALLS it.
  const screen = strip(path.resolve(__dirname, '../app/alerts.tsx'));
  t('alerts.tsx calls groupByHandoffCycle', /groupByHandoffCycle\(/.test(screen));
  t('alerts.tsx renders the badge from resendBadge, never a hand-written string', /resendBadge\(/.test(screen));
  t('the badge is gated on a real count > 1 (a lone ask must not wear 「×1 재요청」)',
    /count > 1/.test(screen), 'no count > 1 gate in alerts.tsx');
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// 0183 IS THE CONTRACT — read the migration, not a memory of it
// ══════════════════════════════════════════════════════════════════════════════════════════
{
  const sqlPath = path.resolve(__dirname, '../../supabase/migrations/0183_handoff_cycle_identity.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  t('0183 still adds notifications.handoff_cycle_id (the column this whole module reads)',
    /alter table notifications\s+add column if not exists handoff_cycle_id/.test(sql));
  t("0183's sweep still writes the column on the re-sent ask (a cycle with one row can never group)",
    /insert into notifications \(profile_id, kind, title, body, ref_id, handoff_cycle_id\)/.test(sql));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
