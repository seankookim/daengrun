// offered-slots.ts — tests run against the REAL compiled source (see run-offered-slots-tests.sh),
// not a retyped copy. Same loader idiom as notification-prefs.test.cjs.
//
// WHAT THIS FILE IS FOR. 0215's server function is pinned by `supabase/tests/246`, which proves the
// LIST is right. This file pins the other half — that the screen turns that list into the same
// candidate set the server would accept — and it is the only place that half can be tested at all,
// because `app/test/*.cjs` cannot import a `.tsx` route module.
//
// 🔴 THE PROPERTY, stated without reference to any mutation: a candidate start the screen draws is
// always one `is_slot_available` would accept, never the other way round — and the LABEL must mean
// 「this time exists only because of a 추가 근무」, not 「this button came out of the extra branch」.
//
// ⚠ **THE FIRST HALF OF THAT SENTENCE USED TO CARRY A SECOND CLAUSE AND IT WAS REMOVED ON
// 2026-09-25 [0221].** It read 「the server's own §1 requires ONE window to contain the slot, so the
// client must not merge adjacent windows」. That was true of 0203's judge; 0219 made §1 the UNION
// of the runner's windows merged where they touch, and from that moment the client's refusal to
// accept a seam was not caution — it was a slot the server accepts that no owner could ever be
// offered (Codex 2026-09-25 server verdict #1). 0221 moves the merge to the SERVER
// (`runner_offered_slots` returns merged spans with their `segments`), and this module accepts a
// span. It still never merges anything itself: two separate rows stay two separate rows, which is
// what keeps the deploy-skew path narrow.
//
// THREE ZONES, for the reason run-kst-tests.sh gives: `kstDayKey` names a KST calendar day, and a
// device-local implementation of it is INVISIBLE on developer hardware in Seoul and wrong on every
// other phone. A Seoul-only green here is worth nothing.
//
// The mutations that redden it: accept only the producing SEGMENT instead of the span · step from
// the span's start instead of each segment's own · label from the row's `source` word instead of
// the merged grid union · drop the dedupe · let a start reach 1440 · build the day key from
// `Date#getMonth()` · make windowsFromRules ignore the weekday.
const {
  kstDayKey, windowsForDay, windowsFromRules, slotStartsForDay, slotChip, EXTRA_CHIP_KO,
} = require('./offered-slots.build.cjs');
const { kstCal, kstInstant } = require('./kst.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const starts = (ss) => ss.map((s) => s.startMin);
const sources = (ss) => ss.map((s) => s.source);

// ── the day key is the server's wire shape, and it is KST ──────────────────────────────────────
// 2026-10-03 08:59 KST is 2026-10-02 23:59 UTC — the exact instant `246 0215-K1` uses on the
// server side, so the two halves are pinned at the same boundary.
const BOUNDARY_MS = Date.UTC(2026, 9, 2, 23, 59);            // 2026-10-02T23:59:00Z
t('the day key is the KST day, not the device day (23:59 UTC → the NEXT KST day)',
  kstDayKey(kstCal(BOUNDARY_MS)) === '2026-10-03', kstDayKey(kstCal(BOUNDARY_MS)));
t('the day key is zero-padded (the server returns 2026-10-03, never 2026-9-3)',
  kstDayKey(kstCal(Date.UTC(2026, 0, 5, 3, 0))) === '2026-01-05',
  kstDayKey(kstCal(Date.UTC(2026, 0, 5, 3, 0))));
t('⚠ the key is NOT kstKey — a 0-based unpadded month would never match a server row',
  kstDayKey(kstCal(BOUNDARY_MS)) !== `${kstCal(BOUNDARY_MS).y}-${kstCal(BOUNDARY_MS).m}-${kstCal(BOUNDARY_MS).d}`);
t('the KST weekday at that boundary is the NEXT day\'s (Sat), not the UTC day\'s (Fri)',
  kstCal(BOUNDARY_MS).wd === 6, String(kstCal(BOUNDARY_MS).wd));
// the round trip a screen actually performs: cal → instant → cal must name the same day
t('a start built with kstInstant round-trips to the same KST day key', (() => {
  const cal = kstCal(BOUNDARY_MS);
  const inst = kstInstant(cal, 9, 0);                        // 09:00 KST on that day
  return kstDayKey(kstCal(inst.getTime())) === kstDayKey(cal);
})());

const D = '2026-10-03';
const OTHER = '2026-10-04';
// ⚠ `grid`/`extra` build a row with NO `segments` — the 0215 four-column shape, which a build
// carrying 0221 can still meet while the db push is one command behind (`rpc-skew.ts`). Every pin
// written with them measures the DEPLOY-SKEW path, and that path must stay exactly as narrow as it
// was before 0221. `span()` below builds the 0221 shape.
const grid = (a, b, day = D) => ({ day, startMin: a, endMin: b, source: 'grid' });
const extra = (a, b, day = D) => ({ day, startMin: a, endMin: b, source: 'extra' });
// One constituent of a merged span, and the span itself — built the way 0221 §A builds them, so a
// fixture here cannot claim a shape the server does not produce.
const sg = (a, b, source) => ({ startMin: a, endMin: b, source });
const span = (segs, day = D) => ({
  day,
  startMin: Math.min(...segs.map((s) => s.startMin)),
  endMin: Math.max(...segs.map((s) => s.endMin)),
  source: segs.every((s) => s.source === 'grid') ? 'grid'
    : segs.every((s) => s.source === 'extra') ? 'extra' : 'mixed',
  segments: segs,
});

// ── windowsForDay is a day filter and nothing else ─────────────────────────────────────────────
t('windowsForDay keeps only that day', (() => {
  const w = [grid(540, 720), grid(540, 720, OTHER), extra(1140, 1260)];
  return windowsForDay(w, D).length === 2 && windowsForDay(w, OTHER).length === 1;
})());

// ── ① the extra window is the reason this slice exists ─────────────────────────────────────────
// A weekday with ZERO grid rows: before 0215 the screen produced nothing here and checkSlot was
// never called, while the server said TRUE (review F2 ④).
t('🔴 a gridless day with an extra window produces candidates (F2 ④)',
  JSON.stringify(starts(slotStartsForDay([extra(300, 480)], D, 65))) === JSON.stringify([300, 360]),
  JSON.stringify(starts(slotStartsForDay([extra(300, 480)], D, 65))));
t('…and every one of them is labelled 추가 근무',
  slotStartsForDay([extra(300, 480)], D, 65).every((s) => s.source === 'extra'));
t('the chip is bound, never guessed',
  slotChip({ startMin: 300, source: 'extra' }) === EXTRA_CHIP_KO
  && slotChip({ startMin: 540, source: 'grid' }) === null);
t('a day with no windows at all produces nothing (a blackout day, or a gridless day)',
  slotStartsForDay([], D, 65).length === 0
  && slotStartsForDay([grid(540, 720, OTHER)], D, 65).length === 0);

// ── ② the grid keeps behaving exactly as it did before 0215 ────────────────────────────────────
// 09:00–12:00 with a 65-minute run, stepping 60 from the window's own start.
t('a grid-only day is unchanged from the pre-0215 loop',
  JSON.stringify(starts(slotStartsForDay([grid(540, 720)], D, 65))) === JSON.stringify([540, 600]),
  JSON.stringify(starts(slotStartsForDay([grid(540, 720)], D, 65))));
t('the run must FIT — a window shorter than the duration offers nothing',
  slotStartsForDay([grid(540, 600)], D, 65).length === 0);
t('the last start is the last one that fits, not the last step',
  JSON.stringify(starts(slotStartsForDay([grid(540, 665)], D, 65))) === JSON.stringify([540, 600]),
  JSON.stringify(starts(slotStartsForDay([grid(540, 665)], D, 65))));

// ── ③ steps come from EACH window's own start ──────────────────────────────────────────────────
t('🔴 a second window steps from ITS start, not from a global grid',
  JSON.stringify(starts(slotStartsForDay([grid(540, 720), extra(1145, 1265)], D, 65)))
    === JSON.stringify([540, 600, 1145]),
  JSON.stringify(starts(slotStartsForDay([grid(540, 720), extra(1145, 1265)], D, 65))));

// ── ④ this module never merges ANYTHING itself — two rows stay two rows ────────────────────────
// 09:00–12:00 and 12:00–14:00 arriving as two SEPARATE rows is the 0215 wire shape, and it is what
// a build meets while the db push is behind. The seam time 11:00 (11:00+65 = 12:05) is not offered
// on that path, which is the narrow direction and the only safe one for a list the server has the
// last word on. Section ⑨ is the same calendar arriving as ONE merged span, where it IS offered.
t('🔴 two separate rows are NOT merged by the client — no candidate crosses the seam',
  JSON.stringify(starts(slotStartsForDay([grid(540, 720), extra(720, 840)], D, 65)))
    === JSON.stringify([540, 600, 720]),
  JSON.stringify(starts(slotStartsForDay([grid(540, 720), extra(720, 840)], D, 65))));
t('…and the control: a genuinely continuous 09:00–14:00 window DOES offer the seam time',
  starts(slotStartsForDay([grid(540, 840)], D, 65)).includes(660),
  JSON.stringify(starts(slotStartsForDay([grid(540, 840)], D, 65)))); // 660 = 11:00

// ── ⑤ dedupe, and the label is by CONTAINMENT not by producing window ──────────────────────────
t('the same start from two windows collapses to one slot (no double button)',
  slotStartsForDay([grid(540, 720), extra(540, 720)], D, 65).length
    === slotStartsForDay([grid(540, 720)], D, 65).length);
t('🔴 a slot a GRID window covers is labelled grid, even when an extra window produced it', (() => {
  // grid 09:00–21:00 steps 540/600/660…; the extra starts at 10:30 so it produces 630, a start the
  // grid never generated — but the grid window CONTAINS it, so it is ordinary work, not 추가 근무.
  const ss = slotStartsForDay([grid(540, 1260), extra(630, 750)], D, 65);
  const at630 = ss.find((s) => s.startMin === 630);
  return at630 && at630.source === 'grid';
})());
t('…and the same fixture still labels the genuinely-outside start as extra', (() => {
  const ss = slotStartsForDay([grid(540, 1260), extra(1280, 1400)], D, 65);
  const at1280 = ss.find((s) => s.startMin === 1280);
  return at1280 && at1280.source === 'extra';
})());
t('a mixed day labels each start by where it actually sits',
  JSON.stringify(sources(slotStartsForDay([grid(540, 720), extra(1140, 1290)], D, 65)))
    === JSON.stringify(['grid', 'grid', 'extra', 'extra']),
  JSON.stringify(sources(slotStartsForDay([grid(540, 720), extra(1140, 1290)], D, 65))));

// ── ⑥ the midnight boundary — a DAY-BOUNDED row still cannot reach past it ─────────────────────
// A row whose own `endMin` is ≤ 1440 (the 0215 shape, and a 0221 span that genuinely ends at
// midnight) can never produce a slot that runs into the next day. Section ⑨ pins the other half:
// a span the server merged ACROSS midnight may, and that is 0219's whole point.
t('🔴 a row bounded at 24:00 never produces a slot that crosses KST midnight',
  slotStartsForDay([grid(0, 1440), extra(1380, 1440)], D, 65)
    .every((s) => s.startMin + 65 <= 1440));
t('a window ending exactly at 24:00 offers its last FITTING start and no more',
  JSON.stringify(starts(slotStartsForDay([grid(1320, 1440)], D, 65))) === JSON.stringify([1320]),
  JSON.stringify(starts(slotStartsForDay([grid(1320, 1440)], D, 65))));

// ── ⑦ the fallback — the pre-0215 behaviour, not a new guess ───────────────────────────────────
const RULES = [{ weekday: 6, startMin: 540, endMin: 720 }, { weekday: 1, startMin: 840, endMin: 960 }];
t('windowsFromRules picks the KST weekday and labels everything grid', (() => {
  const cal = kstCal(BOUNDARY_MS);                      // wd 6 (토)
  const w = windowsFromRules(RULES, cal);
  return w.length === 1 && w[0].startMin === 540 && w[0].source === 'grid' && w[0].day === '2026-10-03';
})());
t('🔴 windowsFromRules on a weekday with no rule is EMPTY — the pre-0215 dead end, kept honest',
  windowsFromRules(RULES, kstCal(Date.UTC(2026, 9, 4, 3, 0))).length === 0);   // 2026-10-04 KST = 일(0)
t('the fallback offers no 추가 근무 chip — it cannot know about one, and must not pretend',
  slotStartsForDay(windowsFromRules(RULES, kstCal(BOUNDARY_MS)), '2026-10-03', 65)
    .every((s) => s.source === 'grid'));

// ── ⑧ degenerate inputs produce nothing rather than looping ────────────────────────────────────
t('a non-positive duration or step yields no candidates (never an infinite loop)',
  slotStartsForDay([grid(540, 720)], D, 0).length === 0
  && slotStartsForDay([grid(540, 720)], D, 65, 0).length === 0
  && slotStartsForDay([grid(540, 720)], D, -5).length === 0);

// ── ⑨ [0221] a MERGED span — the half of Codex #1 that lives on this side of the wire ──────────
// The same calendar as ④, arriving as ONE span with its two segments. `is_slot_available` §1 has
// accepted 11:00–12:05 here since 0219; before 0221 nothing could offer it.
const SEAM = span([sg(540, 720, 'grid'), sg(720, 840, 'extra')]);
t('🔴 a merged span offers the seam start the server already accepts (Codex 2026-09-25 #1)',
  JSON.stringify(starts(slotStartsForDay([SEAM], D, 65))) === JSON.stringify([540, 600, 660, 720]),
  JSON.stringify(starts(slotStartsForDay([SEAM], D, 65))));
t('…and the seam slot really does cross the seam (the fixture is not measuring an easy case)',
  660 < 720 && 660 + 65 > 720);
t('🔴 the seam slot is labelled 추가 근무 — the grid half alone does not contain it', (() => {
  const at660 = slotStartsForDay([SEAM], D, 65).find((s) => s.startMin === 660);
  const at540 = slotStartsForDay([SEAM], D, 65).find((s) => s.startMin === 540);
  return at660 && at660.source === 'extra' && slotChip(at660) === EXTRA_CHIP_KO
      && at540 && at540.source === 'grid' && slotChip(at540) === null;
})());
t('🔴 …but two ADJACENT GRID segments are ordinary work on both sides — NO chip on their seam',
  (() => {
    const both = span([sg(540, 720, 'grid'), sg(720, 840, 'grid')]);
    const at660 = slotStartsForDay([both], D, 65).find((s) => s.startMin === 660);
    return at660 && at660.source === 'grid' && slotChip(at660) === null;
  })());
t('an extra INSIDE an ordinary grid window still gets no chip, merged or not (0215 rule ⑤ kept)',
  (() => {
    const inside = span([sg(540, 1260, 'grid'), sg(630, 750, 'extra')]);
    const at630 = slotStartsForDay([inside], D, 65).find((s) => s.startMin === 630);
    return at630 && at630.source === 'grid';
  })());
t('🔴 steps come from EACH SEGMENT\'s own start — a 12:10 segment keeps its own phase', (() => {
  const offbeat = span([sg(540, 730, 'grid'), sg(730, 840, 'extra')]);
  return JSON.stringify(starts(slotStartsForDay([offbeat], D, 65)))
    === JSON.stringify([540, 600, 660, 720, 730]);
})(), JSON.stringify(starts(slotStartsForDay(
  [span([sg(540, 730, 'grid'), sg(730, 840, 'extra')])], D, 65))));
// Cross-midnight: 22:00–24:00 merged with the next day's 00:00–02:00. The server anchors that span
// on BOTH days; this is the first day's row (endMin 1560 = 02:00 tomorrow).
const NIGHT = span([sg(1320, 1440, 'grid'), sg(1440, 1560, 'grid')]);
t('🔴 a span merged across midnight DOES offer a slot that ends tomorrow (0219 §1, now reachable)',
  JSON.stringify(starts(slotStartsForDay([NIGHT], D, 65))) === JSON.stringify([1320, 1380]),
  JSON.stringify(starts(slotStartsForDay([NIGHT], D, 65))));
t('…and 23:00 really does run past midnight, while NO start ever reaches 24:00',
  1380 + 65 > 1440 && slotStartsForDay([NIGHT], D, 65).every((s) => s.startMin < 1440));
t('the SECOND day of that pair is a row with a NEGATIVE start — its screen is not empty', (() => {
  // 0221 re-anchors the same span on the next day: [-120, 120).
  const nextDay = span([sg(-120, 0, 'grid'), sg(0, 120, 'grid')]);
  const ss = slotStartsForDay([nextDay], D, 65);
  return JSON.stringify(starts(ss)) === JSON.stringify([0]) && ss.every((s) => s.startMin >= 0);
})(), JSON.stringify(starts(slotStartsForDay([span([sg(-120, 0, 'grid'), sg(0, 120, 'grid')])], D, 65))));
// Deploy skew: a row the server sent in 0215's four-column shape has no `segments` at all.
t('🔴 a row with NO segments is read as one unmerged window (the 0215 shape, narrow direction)',
  JSON.stringify(starts(slotStartsForDay([grid(540, 720)], D, 65))) === JSON.stringify([540, 600])
  && slotStartsForDay([grid(540, 720)], D, 65).every((s) => s.source === 'grid')
  && slotStartsForDay([extra(300, 480)], D, 65).every((s) => s.source === 'extra'));
t('…and an empty segments array falls the same way rather than offering nothing',
  JSON.stringify(starts(slotStartsForDay(
    [{ day: D, startMin: 540, endMin: 720, source: 'grid', segments: [] }], D, 65)))
    === JSON.stringify([540, 600]));

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
