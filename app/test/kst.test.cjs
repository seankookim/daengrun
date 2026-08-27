// kst.ts — tests run against the REAL compiled source (see run-kst-tests.sh).
//
// Why it must never be left red: these three functions decide the INSTANT a booking is written
// at. They were device-local until 2026-08-21 (E6), which meant a UTC simulator booked 16:30 KST
// when the owner tapped 07:30, and the server agreed with the wrong time because both sides were
// handed the same shifted instant. The load-bearing property is the last section: on Seoul
// hardware this arithmetic must be a no-op against plain local construction.
const { kstCal, kstInstant, kstKey, kstDateLabel, kstMonthDay, kstClock, kstAmPm, KST_MS } = require('./kst.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

t('KST_MS is +9h', KST_MS === 9 * 3600_000);

// ───────────────────────────────────────────── kstCal reads Seoul parts, not device parts
{
  const c = kstCal(Date.parse('2026-08-21T01:00:00Z')); // 10:00 KST, Friday
  t('kstCal y/m/d', c.y === 2026 && c.m === 7 && c.d === 21, JSON.stringify(c));
  t('kstCal h/min', c.h === 10 && c.min === 0, JSON.stringify(c));
  t('kstCal weekday is Friday(5)', c.wd === 5, String(c.wd));
}
// The case that breaks naive UTC handling: 22:00 UTC is already TOMORROW in Seoul.
{
  const c = kstCal(Date.parse('2026-08-21T22:00:00Z')); // 07:00 KST Aug 22, Saturday
  t('late-UTC evening is next KST day', c.d === 22 && c.h === 7, JSON.stringify(c));
  t('…and next KST weekday', c.wd === 6, String(c.wd));
}
// And the mirror: 00:30 UTC is still the same Seoul day, but early UTC hours before 15:00 UTC
// belong to the same KST date only until 15:00 UTC.
{
  const c = kstCal(Date.parse('2026-08-21T15:00:00Z')); // 00:00 KST Aug 22
  t('15:00 UTC is KST midnight of the next day', c.d === 22 && c.h === 0, JSON.stringify(c));
}

// ───────────────────────────────────────────── kstInstant round-trips
{
  const c = kstCal(Date.parse('2026-08-21T01:00:00Z'));
  const inst = kstInstant(c, 7, 30);
  t('kstInstant builds 07:30 KST', inst.toISOString() === '2026-08-20T22:30:00.000Z', inst.toISOString());
  const back = kstCal(inst.getTime());
  t('round-trip preserves wall clock', back.h === 7 && back.min === 30 && back.d === 21, JSON.stringify(back));
}
// 21:00 is the slot that used to roll into the next KST day on a UTC device.
{
  const c = kstCal(Date.parse('2026-08-21T01:00:00Z'));
  const back = kstCal(kstInstant(c, 21, 0).getTime());
  t('21:00 stays on the same KST day and weekday',
     back.h === 21 && back.d === 21 && back.wd === 5, JSON.stringify(back));
}
// Year boundary — the arithmetic must not depend on month/year locality.
{
  const c = kstCal(Date.parse('2025-12-31T16:00:00Z')); // 01:00 KST Jan 1 2026
  t('year boundary rolls correctly', c.y === 2026 && c.m === 0 && c.d === 1, JSON.stringify(c));
  const back = kstCal(kstInstant(c, 0, 30).getTime());
  t('…and instants build on the rolled date', back.y === 2026 && back.d === 1 && back.h === 0);
}

// ───────────────────────────────────────────── kstKey identity
{
  const a = kstCal(Date.parse('2026-08-21T01:00:00Z'));
  const b = kstCal(Date.parse('2026-08-21T13:00:00Z')); // same KST day
  const c = kstCal(Date.parse('2026-08-21T16:00:00Z')); // next KST day
  t('same KST day → same key', kstKey(a) === kstKey(b), `${kstKey(a)} vs ${kstKey(b)}`);
  t('next KST day → different key', kstKey(a) !== kstKey(c), `${kstKey(a)} vs ${kstKey(c)}`);
}

// ───────────────────────────────────────────── 🔴 labels: the 입장권 DATE cell (club/pass/[sid])
// The regression this section exists for: that cell rendered WD[d.getDay()] and d.getHours(),
// which are DEVICE-local. On a phone outside Asia/Seoul the one artifact a holder physically
// shows a host at the meetup point carried the wrong weekday and a time up to 13h off — measured
// under TZ=America/New_York, where 2026-08-25T22:00:00Z printed 「화 18:00」 for a 「수 07:00」
// session. Expected values below were cross-checked against Intl with timeZone:'Asia/Seoul' so
// they are not the implementation grading its own homework.
// The whole point is that these are LITERAL strings: the runner executes this file under several
// zones, and every one of them must produce the same bytes.
{
  const evening = kstCal(Date.parse('2026-08-26T10:00:00Z')); // 19:00 KST, Wednesday
  t('date label is KST whatever the device zone', kstDateLabel(evening) === '8월 26일 (수)', kstDateLabel(evening));
  t('clock is KST, 24h, zero-padded', kstClock(evening) === '19:00', kstClock(evening));
}
// The instant the old code got wrong in BOTH fields at once: 22:00 UTC is already tomorrow in
// Seoul and still yesterday evening in New York, so a local read moved the weekday as well as
// the hour. If this pair ever goes red the device clock has crept back in.
{
  const morning = kstCal(Date.parse('2026-08-25T22:00:00Z')); // 07:00 KST, Wednesday the 26th
  t('late-UTC evening labels as the next KST day', kstDateLabel(morning) === '8월 26일 (수)', kstDateLabel(morning));
  t('…and carries its KST morning hour', kstClock(morning) === '07:00', kstClock(morning));
}
// Midnight is the padding case — the cell is tabular, so 0시 prints 00:00 and never 0:00.
{
  const midnight = kstCal(Date.parse('2026-08-25T15:00:00Z')); // 00:00 KST, the 26th
  t('KST midnight pads to 00:00', kstClock(midnight) === '00:00', kstClock(midnight));
  t('…and sits on the rolled date', kstDateLabel(midnight) === '8월 26일 (수)', kstDateLabel(midnight));
}
// The widest realistic value the half-width DATE cell has to hold: two-digit month AND day.
// The layout decision (two lines) was sized against this string, so it is pinned here.
{
  const wide = kstCal(Date.parse('2026-12-28T10:00:00Z')); // 19:00 KST, Monday
  t('two-digit month/day is the widest label', kstDateLabel(wide) === '12월 28일 (월)', kstDateLabel(wide));
}

// ───────────────────────────────────────────── kstMonthDay — the bare 「8월 26일」 vocabulary
// Its callers (설정·러너 베이스 핀의 can_change_at, 리포트의 후기 등록일, 커뮤니티 후기 날짜) all
// print a SERVER timestamp with no weekday beside it, so a one-day slip has nothing on screen to
// contradict it. Expected strings cross-checked against Intl timeZone:'Asia/Seoul'.
{
  const evening = kstCal(Date.parse('2026-08-26T10:00:00Z')); // 19:00 KST Wed the 26th
  t('month/day is KST whatever the device zone', kstMonthDay(evening) === '8월 26일', kstMonthDay(evening));
  // 22:00 UTC is already the NEXT day in Seoul and still the previous evening in New York — the
  // single instant where a device-local read is off by a whole calendar day.
  const rolled = kstCal(Date.parse('2026-08-25T22:00:00Z')); // 07:00 KST Wed the 26th
  t('late-UTC evening is the next KST month/day', kstMonthDay(rolled) === '8월 26일', kstMonthDay(rolled));
  // The two date vocabularies are one function apart and must stay that way: the weekday form is
  // literally the bare form plus a suffix, so they cannot report different dates.
  t('kstDateLabel is kstMonthDay plus a weekday',
     kstDateLabel(rolled).startsWith(kstMonthDay(rolled) + ' ('), kstDateLabel(rolled));
}

// ───────────────────────────────────────────── kstAmPm — the 오전/오후 vocabulary (chat bubbles)
// Every chat bubble's timestamp. The 12-hour edges are the whole test: 0시 and 12시 both print 12,
// and 오전/오후 flips at exactly 12:00 KST — a device-local read moves the flip AND the number.
{
  const noon = kstCal(Date.parse('2026-08-26T03:00:00Z'));     // 12:00 KST
  t('KST noon is 오후 12, not 오전 0', kstAmPm(noon) === '오후 12:00', kstAmPm(noon));
  const oneBefore = kstCal(Date.parse('2026-08-26T02:59:00Z')); // 11:59 KST
  t('the minute before noon is still 오전', kstAmPm(oneBefore) === '오전 11:59', kstAmPm(oneBefore));
  const midnight = kstCal(Date.parse('2026-08-26T15:05:00Z')); // 00:05 KST the 27th
  t('KST midnight is 오전 12, and the minute pads', kstAmPm(midnight) === '오전 12:05', kstAmPm(midnight));
  const afternoon = kstCal(Date.parse('2026-08-26T04:30:00Z')); // 13:30 KST
  t('afternoon hour is UNPADDED (api.ts kstParts parity)', kstAmPm(afternoon) === '오후 1:30', kstAmPm(afternoon));
  const morning = kstCal(Date.parse('2026-08-25T22:00:00Z'));  // 07:00 KST the 26th
  t('late-UTC evening is a KST MORNING bubble', kstAmPm(morning) === '오전 7:00', kstAmPm(morning));
}

// ───────────────────────────────────────────── 🔴 the slot round-trip (owner/report 다음 주 같은 시간)
// The property, stated without reference to any bug: a booking written at one of request.tsx's
// nine KST slots, read back +7d later, must still print THAT slot string and must land on a KST
// calendar day the 8-day strip contains. owner/report tests `kstClock(...)` for membership in the
// slot list and finds the strip row by `kstKey`; off-KST both fail SILENTLY — the panel simply
// never renders, which is why no screen can contradict it.
{
  const SLOTS = ['06:30', '07:30', '09:00', '13:00', '15:30', '17:00', '18:30', '19:30', '21:00'];
  const base = kstCal(Date.parse('2026-08-26T01:00:00Z')); // 10:00 KST Wed the 26th
  let held = 0;
  for (const sl of SLOTS) {
    const [h, mi] = sl.split(':').map(Number);
    const plus7 = kstCal(kstInstant(base, h, mi).getTime() + 7 * 86400_000);
    if (kstClock(plus7) === sl) held++;
  }
  t(`every slot survives +7d as the same slot string (${held}/${SLOTS.length})`, held === SLOTS.length);
  // …and the day it lands on is findable in a today..today+7 strip built the way request.tsx
  // builds it. 21:00 is the slot that used to roll off the strip on a device behind KST.
  const late = kstInstant(base, 21, 0).getTime();
  const strip = Array.from({ length: 8 }, (_, i) => kstKey(kstCal(late - 7 * 86400_000 + i * 86400_000)));
  t('run+7d lands on the LAST strip row and nowhere else',
     strip.indexOf(kstKey(kstCal(late))) === 7, JSON.stringify(strip));
}

// ───────────────────────────────────────────── the dark-slot hour (route-chips 안전 카피)
// route-chips' isDarkSlot reads the KST hour of draft.scheduledAtIso and turns the 조명 filter on
// below 07:00 / from 21:00. A device-local hour makes a 19:00 KST booking read 06:00 in New York,
// which switches a SAFETY filter on for a daylight run — and off for a real dawn one.
{
  const cases = [
    ['2026-08-25T21:59:00Z', 6, true],   // 06:59 KST — dark
    ['2026-08-25T22:00:00Z', 7, false],  // 07:00 KST — the open boundary
    ['2026-08-26T11:59:00Z', 20, false], // 20:59 KST — still light
    ['2026-08-26T12:00:00Z', 21, true],  // 21:00 KST — the close boundary
    ['2026-08-26T10:00:00Z', 19, false], // 19:00 KST — the evening run a local read called dawn
  ];
  let ok = 0;
  for (const [iso, hour, dark] of cases) {
    const h = kstCal(Date.parse(iso)).h;
    if (h === hour && (h < 7 || h >= 21) === dark) ok++;
  }
  t(`dark-slot boundaries are KST hours (${ok}/${cases.length})`, ok === cases.length);
}

// ───────────────────────────────────────────── ⚠ the regression that matters for the pilot
// On Seoul hardware this arithmetic must produce EXACTLY what plain local construction produced
// before E6. If this section ever goes red, the fix has started changing behaviour on the phones
// the pilot actually runs on, which E6 promised it would not.
if (process.env.TZ === 'Asia/Seoul') {
  const now = Date.parse('2026-08-21T01:00:00Z');
  let same = 0, checked = 0;
  for (const dayOffset of [0, 1, 3, 7]) {
    for (const [h, mi] of [[6, 30], [7, 30], [13, 0], [21, 0]]) {
      const ms = now + dayOffset * 86400_000;
      const legacy = new Date(new Date(ms).getFullYear(), new Date(ms).getMonth(), new Date(ms).getDate(), h, mi);
      const modern = kstInstant(kstCal(ms), h, mi);
      checked++; if (legacy.getTime() === modern.getTime()) same++;
    }
  }
  t(`Seoul hardware: KST arithmetic is a no-op vs local (${same}/${checked})`, same === checked);
} else {
  console.log('SKIP Seoul no-op check (run under TZ=Asia/Seoul)');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
