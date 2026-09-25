// runner-home-pick.ts — tests run against the REAL compiled source (see run-runner-home-pick-tests.sh),
// under THREE zones (UTC · America/New_York · Asia/Seoul), because two of these decisions are KST
// calendar/clock questions and a Seoul-only run cannot see a device-clock read at all.
//
// WHAT THIS FILE IS FOR (fix/runner-home-truth, sweep 2 on trunk b4c273f):
//   runner-journey-1  home's 진행 중 fallback was the FURTHEST confirmed booking (fetchRunnerJobs is
//                     scheduled_at DESC and nothing re-sorted), and 오늘의 루트 held the three
//                     furthest rows under a heading that is a date claim.
//   runner-journey-2  every picked_up / active / 귀가 ticket read 「N분 늦음」 in critical red; the
//                     returning subline said 「러닝 기록이 쌓이는 중이에요」; 「출발할 시간이에요」
//                     printed for runs days away; a stamped return stayed the coral 「your move」.
//   runner-journey-3  the ⑫ strip drew a second door to the same screen as the ticket's CTA.
//   runner-journey-7  요청's 수락 pushed the meetup screen (whose mount fires runnerEnroute → a false
//                     「출발했어요」 to the owner) and home promised 「오늘의 루트에 올라가요」 for any date.
//   less-is-more-2    내 기록 had two doors to /cards and called the collection 「상세 기록 보기」.
//   copy-hierarchy-1  dog-name particles hard-coded (콩를 · 반려견가).
//
// The mutations that redden it (the brief's battery, plus the device-clock one):
//   · sortJobsAsc returns the input order          → RHP-C1 (tomorrow before Friday), RHP-S1
//   · isLateDatum returns true for `active`         → RHP-L1
//   · pickUpcoming loses its today gate            → RHP-U1 in every zone
//   · isTodayKst reads the DEVICE day              → RHP-U1 / RHP-T1 under UTC + New_York, NOT Seoul
//   · requests' commitAccept pushes /runner/meetup → RHP-SRC1
const {
  sortJobsAsc, isTodayKst, pickCurrent, pickUpcoming, pickPast, stageSubline, isLateDatum,
  returnWaitLine, gateStripExit, acceptedLine, LATE_CAP_MIN, DEPART_NEAR_MIN,
} = require('./runner-home-pick.build.cjs');
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const J = (x) => JSON.stringify(x);
const ids = (xs) => xs.map((j) => j.bookingId).join(',');
const job = (bookingId, rawStatus, scheduledAt) => ({ bookingId, rawStatus, scheduledAt });

console.log(`zone: ${process.env.TZ ?? '(unset)'}`);

// 2026-09-25 08:00 KST = 2026-09-24T23:00:00Z (a Friday in KST). Chosen so that a phone in New York
// (2026-09-24 19:00 EDT) and a UTC simulator (2026-09-24 23:00) are both still on the PREVIOUS
// calendar day — a device-clock read disagrees with KST here, and only here can a pin see it.
const NOW = Date.parse('2026-09-24T23:00:00Z');
const TOMORROW_0900 = '2026-09-26T00:00:00Z';   // 2026-09-26 09:00 KST
const NEXT_FRI_0900 = '2026-10-02T00:00:00Z';   // 2026-10-02 09:00 KST (next Friday)

// ── ① ordering ──────────────────────────────────────────────────────────────────────────────
{
  const rows = [
    job('c', 'confirmed', NEXT_FRI_0900), job('n', 'confirmed', null),
    job('a', 'confirmed', TOMORROW_0900), job('b', 'confirmed', TOMORROW_0900),
  ];
  const before = ids(rows);
  const out = sortJobsAsc(rows);
  t('RHP-S1 sortJobsAsc: ascending by time, ties by bookingId, an unreadable time LAST', ids(out) === 'a,b,c,n', ids(out));
  t('RHP-S1b sortJobsAsc returns a NEW array (never sorts React state in place)', out !== rows && ids(rows) === before);
}

// ── ② pickCurrent ───────────────────────────────────────────────────────────────────────────
{
  // fetchRunnerJobs order: scheduled_at DESC. The furthest booking arrives FIRST — the defect.
  const desc = [job('fri', 'confirmed', NEXT_FRI_0900), job('tmr', 'confirmed', TOMORROW_0900)];
  t('🔴 RHP-C1 confirmed tomorrow 09:00 and next Friday (DESC input) → the 진행 중 ticket is TOMORROW\'s',
    pickCurrent(desc, NOW)?.bookingId === 'tmr', J(pickCurrent(desc, NOW)));
  t('RHP-C1b the same answer whatever order the read arrived in',
    pickCurrent([...desc].reverse(), NOW)?.bookingId === 'tmr');

  const withLive = [job('fri', 'confirmed', NEXT_FRI_0900), job('tmr', 'confirmed', TOMORROW_0900),
    job('live', 'runner_enroute', '2026-09-26T05:00:00Z')];
  t('RHP-C2 an in-flight booking outranks every confirmed one, even an earlier one',
    pickCurrent(withLive, NOW)?.bookingId === 'live');
  for (const st of ['runner_enroute', 'picked_up', 'active', 'incident_review']) {
    t(`RHP-C2b ${st} is in flight`, pickCurrent([job('x', 'confirmed', TOMORROW_0900), job('y', st, NEXT_FRI_0900)], NOW)?.bookingId === 'y');
  }
  // The in-flight arm is trunk's, unchanged: `find` over the DESC read = the LATEST in-flight row.
  const twoLive = [job('stale', 'runner_enroute', '2026-08-04T01:00:00Z'), job('today', 'active', '2026-09-24T22:00:00Z')];
  t('RHP-C3 several in flight → the latest-scheduled one (the row trunk\'s DESC find returned)',
    pickCurrent(twoLive, NOW)?.bookingId === 'today' && pickCurrent([...twoLive].reverse(), NOW)?.bookingId === 'today');

  const late3h = job('late', 'confirmed', '2026-09-24T20:00:00Z'); // 05:00 KST — 3h ago, inside the cap
  t('RHP-C4 a confirmed booking 3h late (inside LATE_CAP_MIN) still outranks tomorrow — the runner IS late',
    pickCurrent([job('tmr', 'confirmed', TOMORROW_0900), late3h], NOW)?.bookingId === 'late');
  const stranded = job('old', 'confirmed', '2026-09-23T00:00:00Z'); // two days ago — stranded
  t('RHP-C5 a STRANDED confirmed booking (past LATE_CAP_MIN) does not outrank the next one',
    pickCurrent([stranded, job('tmr', 'confirmed', TOMORROW_0900)], NOW)?.bookingId === 'tmr');
  t('RHP-C5b the cap edge: exactly LATE_CAP_MIN late still counts, one minute more is stranded',
    pickCurrent([job('edge', 'confirmed', new Date(NOW - LATE_CAP_MIN * 60_000).toISOString()), job('tmr', 'confirmed', TOMORROW_0900)], NOW)?.bookingId === 'edge'
    && pickCurrent([job('over', 'confirmed', new Date(NOW - (LATE_CAP_MIN + 1) * 60_000).toISOString()), job('tmr', 'confirmed', TOMORROW_0900)], NOW)?.bookingId === 'tmr');
  t('RHP-C5c only stranded ones → the MOST RECENT stranded booking (never dropped)',
    pickCurrent([stranded, job('older', 'confirmed', '2026-09-20T00:00:00Z')], NOW)?.bookingId === 'old');
  t('RHP-C6 a confirmed booking with no readable time is still shown when it is the only one',
    pickCurrent([job('n', 'confirmed', null)], NOW)?.bookingId === 'n');
  t('RHP-C6b completed only / nothing → null (no ticket)',
    pickCurrent([job('d', 'completed', TOMORROW_0900)], NOW) === null && pickCurrent([], NOW) === null);
}

// ── ③ isTodayKst + pickUpcoming — THE ZONE-SENSITIVE HALF ───────────────────────────────────
{
  const at2359 = Date.parse('2026-09-25T14:59:00Z'); // 2026-09-25 23:59 KST
  t('RHP-T1 KST midnight is the edge: 00:00 KST today is today, 00:00 KST tomorrow is not',
    isTodayKst('2026-09-24T15:00:00Z', at2359) === true && isTodayKst('2026-09-25T15:00:00Z', at2359) === false);
  t('RHP-T1b 08:00 KST now vs 20:00 KST the same day — today in KST whatever the device zone says',
    isTodayKst('2026-09-25T11:00:00Z', NOW) === true);
  t('RHP-T1c 22:00 KST YESTERDAY is not today — even where the device calendar says it is',
    isTodayKst('2026-09-24T13:00:00Z', NOW) === false);
  t('RHP-T1d null / garbage time is never today', isTodayKst(null, NOW) === false && isTodayKst('nope', NOW) === false);

  // DESC, as fetchRunnerJobs delivers it.
  const rows = [
    job('C', 'confirmed', NEXT_FRI_0900),          // next Friday
    job('B', 'confirmed', TOMORROW_0900),          // tomorrow 09:00 KST
    job('A', 'confirmed', '2026-09-25T11:00:00Z'), // today 20:00 KST (NY: 9/25 07:00 — the NEXT device day)
    job('A2', 'confirmed', '2026-09-25T03:00:00Z'),// today 12:00 KST (NY: 9/24 23:00 — the device's today)
    job('X', 'active', '2026-09-24T22:00:00Z'),    // today 07:00 KST — in flight, the ticket
    job('E', 'completed', '2026-09-24T21:00:00Z'), // today 06:00 KST — done, never a route stop
    job('D', 'confirmed', '2026-09-24T13:00:00Z'), // YESTERDAY 22:00 KST (NY + UTC: the device's today)
  ];
  const cur = pickCurrent(rows, NOW);
  t('RHP-U0 fixture: the in-flight row is the ticket', cur?.bookingId === 'X', J(cur));
  const up = pickUpcoming(rows, cur, NOW);
  t('🔴 RHP-U1 오늘의 루트 holds only TODAY-KST confirmed rows, ascending, minus the ticket',
    ids(up) === 'A2,A', ids(up));
  t('RHP-U2 no tomorrow, no next Friday, no yesterday, no completed row, no in-flight row',
    !up.some((j) => ['B', 'C', 'D', 'E', 'X'].includes(j.bookingId)));
  // No count cap — the 「오늘 N건」 row counts all of them, and a route of three-of-five contradicts it.
  const five = [0, 1, 2, 3, 4].map((i) => job(`t${i}`, 'confirmed', new Date(Date.parse('2026-09-25T01:00:00Z') + i * 3_600_000).toISOString()));
  t('RHP-U3 five today → five stops (no three-row cap)', pickUpcoming(five, null, NOW).length === 5);
  t('RHP-U4 the ticket\'s own booking is never repeated as a stop',
    ids(pickUpcoming(five, five[2], NOW)) === 't0,t1,t3,t4');
}

// ── ④ pickPast ──────────────────────────────────────────────────────────────────────────────
{
  const asc = ['2026-09-01', '2026-09-05', '2026-09-10', '2026-09-20'].map((d, i) => job(`p${i}`, 'completed', `${d}T01:00:00Z`));
  t('RHP-P1 최근 완료: newest first, at most three — from ascending input', ids(pickPast(asc)) === 'p3,p2,p1', ids(pickPast(asc)));
  t('RHP-P1b …and from descending input', ids(pickPast([...asc].reverse())) === 'p3,p2,p1');
  t('RHP-P2 only completed rows', pickPast([job('c', 'confirmed', TOMORROW_0900), ...asc]).every((j) => j.rawStatus === 'completed'));
  t('RHP-P3 an unreadable time sorts after every timed row', ids(pickPast([job('n', 'completed', null), ...asc], 5)) === 'p3,p2,p1,p0,n');
}

// ── ⑤ isLateDatum ───────────────────────────────────────────────────────────────────────────
{
  t('🔴 RHP-L1 active (running OR returning) never speaks in lateness', isLateDatum('active', null) === false);
  t('RHP-L1b picked_up · incident_review · completed never speak in lateness',
    isLateDatum('picked_up', null) === false && isLateDatum('incident_review', null) === false && isLateDatum('completed', null) === false);
  t('🔴 RHP-L2 confirmed with no arrival → the datum may say late (a past time reads 「N분 늦음」)',
    isLateDatum('confirmed', null) === true && isLateDatum('confirmed', undefined) === true);
  t('RHP-L2b runner_enroute with no arrival → may say late', isLateDatum('runner_enroute', null) === true);
  t('RHP-L3 an ARRIVED runner is not late — they are at the door', isLateDatum('runner_enroute', '2026-09-24T23:05:00Z') === false
    && isLateDatum('confirmed', '2026-09-24T23:05:00Z') === false);
}

// ── ⑥ stageSubline ──────────────────────────────────────────────────────────────────────────
{
  const ret = stageSubline('returning', '콩', null, NOW);
  t('🔴 RHP-SUB1 returning has its OWN line — not 「러닝 기록이 쌓이는 중」', !ret.includes('러닝 기록이 쌓이는 중'), ret);
  t('RHP-SUB1b returning names the move with the right particle: 콩을 / 초코를 / 반려견을',
    ret === '콩을 보호자에게 돌려주세요'
    && stageSubline('returning', '초코', null, NOW) === '초코를 보호자에게 돌려주세요'
    && stageSubline('returning', '반려견', null, NOW) === '반려견을 보호자에게 돌려주세요', ret);
  t('RHP-SUB2 runner_enroute particle (copy-hierarchy-1): 콩을 / 초코를',
    stageSubline('runner_enroute', '콩', null, NOW) === '콩을 넘겨받을 시간이에요'
    && stageSubline('runner_enroute', '초코', null, NOW) === '초코를 넘겨받을 시간이에요');
  // confirmed: 「출발할 시간」 only inside the near window.
  const in30 = new Date(NOW + 30 * 60_000).toISOString();
  const late30 = new Date(NOW - 30 * 60_000).toISOString();
  t('RHP-SUB3 confirmed, 30 min out → 출발할 시간이에요', stageSubline('confirmed', '콩', in30, NOW) === '콩에게 출발할 시간이에요');
  t('RHP-SUB3b confirmed, 30 min LATE → still 출발할 시간이에요', stageSubline('confirmed', '콩', late30, NOW) === '콩에게 출발할 시간이에요');
  t('RHP-SUB3c the near edge is DEPART_NEAR_MIN', stageSubline('confirmed', '콩', new Date(NOW + DEPART_NEAR_MIN * 60_000).toISOString(), NOW).includes('출발할')
    && !stageSubline('confirmed', '콩', new Date(NOW + (DEPART_NEAR_MIN + 1) * 60_000).toISOString(), NOW).includes('출발할'));
  const far = stageSubline('confirmed', '콩', TOMORROW_0900, NOW);
  t('🔴 RHP-SUB4 confirmed, tomorrow → the KST pickup clock, never 「출발할 시간」 (device-local would print 20:00 in New York)',
    far === '09:00 픽업이에요', far);
  t('RHP-SUB4b a STRANDED confirmed booking (2 days ago) gets the clock, not an instruction to leave',
    stageSubline('confirmed', '콩', '2026-09-23T00:00:00Z', NOW) === '09:00 픽업이에요');
  t('RHP-SUB5 confirmed with no readable time → the neutral line, never a guessed clock',
    stageSubline('confirmed', '콩', null, NOW) === '이어서 진행해요');
  t('RHP-SUB6 the unchanged stages keep their sentences',
    stageSubline('picked_up', '콩', null, NOW) === '보호자와 인계를 마쳤어요 — 시작해요'
    && stageSubline('active', '콩', null, NOW) === '러닝 기록이 쌓이는 중이에요'
    && stageSubline('incident_review', '콩', null, NOW) === '담당자가 확인하는 동안 기다려주세요'
    && stageSubline('???', '콩', null, NOW) === '이어서 진행해요');
}

// ── ⑦ returnWaitLine (return-seal frame b, KST) ─────────────────────────────────────────────
{
  const w = returnWaitLine('2026-09-25T10:05:00Z'); // 19:05 KST · 06:05 EDT · 10:05 UTC
  t('🔴 RHP-W1 the runner\'s stamp → 「보호자 확인 대기 · 19:05 확인 보냄」 in KST on every device', w === '보호자 확인 대기 · 19:05 확인 보냄', w);
  t('RHP-W2 no stamp / unreadable stamp → null (the move is still the runner\'s)',
    returnWaitLine(null) === null && returnWaitLine(undefined) === null && returnWaitLine('garbage') === null);
}

// ── ⑧ gateStripExit ─────────────────────────────────────────────────────────────────────────
{
  const exit = { label: '러닝 시작하기 ›', route: 'meetup', href: '/runner/meetup', bookingId: 'b1', a11y: 'x' };
  t('🔴 RHP-G1 the gated booking IS the ticket\'s → the strip draws no second door', gateStripExit(exit, 'b1', 'b1') === null);
  t('RHP-G2 a different booking keeps its exit', gateStripExit(exit, 'b1', 'b2') === exit);
  t('RHP-G3 no ticket / unknown ids keep the exit (only a real match removes it)',
    gateStripExit(exit, 'b1', null) === exit && gateStripExit(exit, null, null) === exit
    && gateStripExit(exit, '', '') === exit && gateStripExit(exit, undefined, undefined) === exit);
  t('RHP-G4 no exit stays no exit', gateStripExit(null, 'b1', 'b2') === null);
}

// ── ⑨ acceptedLine ──────────────────────────────────────────────────────────────────────────
{
  const l = acceptedLine('9월 26일 (토) 오전 9:00');
  t('RHP-A1 both 수락 doors: 「{when} · 러너 홈의 진행 중에서 이어가요」', l === '9월 26일 (토) 오전 9:00 · 러너 홈의 진행 중에서 이어가요', l);
  t('RHP-A2 …and never promise 오늘의 루트 (a today-only section) for any date', !l.includes('오늘의 루트'));
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// SOURCE — what no node test can execute: the two route modules. Comments stripped (quote-aware),
// and the stripper is control-tested on the real file before any pin trusts it.
// ══════════════════════════════════════════════════════════════════════════════════════════════
function stripComments(src) {
  let out = '';
  let i = 0;
  let quote = null;
  while (i < src.length) {
    const c = src[i];
    const nx = src[i + 1];
    if (quote) {
      if (c === '\\') { out += '  '; i += 2; continue; }
      if (c === quote) quote = null;
      out += c; i += 1; continue;
    }
    if (c === '\'' || c === '"' || c === '`') { quote = c; out += c; i += 1; continue; }
    if (c === '/' && nx === '/') { while (i < src.length && src[i] !== '\n') { out += ' '; i += 1; } continue; }
    if (c === '/' && nx === '*') {
      i += 2; out += '  ';
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) { out += src[i] === '\n' ? '\n' : ' '; i += 1; }
      out += '  '; i += 2; continue;
    }
    out += c; i += 1;
  }
  return out;
}
const read = (rel) => {
  const raw = fs.readFileSync(path.join(__dirname, '..', rel), 'utf8');
  if (raw.length < 500) throw new Error(`NO-SOURCE(${rel}) — read back ${raw.length} bytes`);
  return { raw, code: stripComments(raw) };
};
const home = read('app/runner/home.tsx');
const reqs = read('app/runner/requests.tsx');
const slice = (code, from, to) => {
  const a = code.indexOf(from);
  if (a < 0) return null;
  const b = code.indexOf(to, a + from.length);
  return b < 0 ? null : code.slice(a, b);
};

t('CONTROL ⓐ the stripper removes prose — `stageSub(rawStatus` survives in home.tsx only inside the comment recording its removal',
  home.raw.includes('stageSub(rawStatus') && !home.code.includes('stageSub(rawStatus'));
t('CONTROL ⓑ the stripper keeps executable text — `const door = workGateDoor(gateRead);` survives',
  home.code.includes('const door = workGateDoor(gateRead);'));

{
  const body = slice(reqs.code, 'const commitAccept = async', '\n  };\n');
  t('RHP-SRC1 NO-SOURCE guard: requests.tsx commitAccept found', body !== null && body.length > 80, String(body && body.length));
  t('🔴 RHP-SRC1b requests\' commitAccept does not push /runner/meetup (whose mount fires runnerEnroute)',
    body !== null && !body.includes('/runner/meetup') && !/router\.(push|replace|navigate)\(/.test(body), body ?? '');
  t('RHP-SRC1c …does not write the store for a screen it no longer opens, says acceptedLine and reloads',
    body !== null && !body.includes('runnerJob.bookingId') && body.includes("Alert.alert('수락 완료', acceptedLine(req.when));")
    && /acceptedLine\(req\.when\)\);\s*load\(\);/.test(body), body ?? '');
}
{
  const body = slice(home.code, 'const acceptFront = () => {', 'const declineFront');
  t('RHP-SRC2 home\'s 수락 says the same sentence and never 「오늘의 루트에 올라가요」',
    body !== null && body.includes("Alert.alert('수락 완료', acceptedLine(rq.when));") && !home.code.includes('오늘의 루트에 올라가요'), body ?? '');
}
t('🔴 RHP-SRC3 home picks through the module — no `find` over the DESC read',
  home.code.includes('const current = pickCurrent(jobs, nowMs);')
  && home.code.includes('const upcoming = pickUpcoming(jobs, current, nowMs);')
  && home.code.includes('const past = pickPast(jobs, 3);')
  && !/jobs\.find\(\(j\) => j\.rawStatus === 'confirmed'\)/.test(home.code)
  && !/jobs\.filter\(\(j\) => j\.status === 'completed'\)\.slice/.test(home.code));
{
  const tk = slice(home.code, 'const relStage = isLateDatum(', 'styles.objClock');
  t('RHP-SRC4 NO-SOURCE guard: the 진행 중 datum block found', tk !== null && tk.length > 200, String(tk && tk.length));
  const crit = [];
  if (tk) { let i = -1; while ((i = tk.indexOf('paper.critical', i + 1)) >= 0) crit.push(tk.slice(Math.max(0, i - 30), i)); }
  t('🔴 RHP-SRC4b every paper.critical on the datum and stage word is gated by datumLate (= isLateDatum ∧ late)',
    crit.length === 2 && crit.every((pre) => pre.endsWith('datumLate ? ') || pre.endsWith('datumLate ? { color: ')), J(crit));
  t('RHP-SRC4c datumLate derives from isLateDatum, and the relative form is computed only on that gate',
    home.code.includes('const relStage = isLateDatum(current.rawStatus, current.arrivedAt ?? null);')
    && home.code.includes('const rel = relStage ? relWhen(current.scheduledAt) : null;')
    && home.code.includes('const datumLate = relStage && rel?.late === true;'));
  t('RHP-SRC4d no ungated `rel?.late ? … paper.critical` anywhere in home', !/rel\?\.late \? (\{ color: )?paper\.critical/.test(home.code));
}
t('RHP-SRC5 the CTA subline is stageSubline(stageFor) and a stamped return swaps to the ink key',
  home.code.includes('stageSubline(stage, current.dogName, current.scheduledAt, nowMs)')
  && home.code.includes("const returnWait = stage === 'returning' ? returnWaitLine(current.runnerReturnAt) : null;")
  && /returnWait\s*\?\s*\[styles\.jobCtaWait,/.test(home.code));
t('RHP-SRC6 the ⑫ strip\'s exit goes through gateStripExit against the ticket\'s booking',
  home.code.includes('const x = gateStripExit(g.exit, gateBookingId, current?.bookingId);')
  && !home.code.includes('const x = g.exit;'));
t('RHP-SRC7 내 기록: one door named for where it goes',
  home.code.includes('<SectionHead title="내 기록" />') && home.code.includes('컬렉션 보기 ›') && !home.code.includes('상세 기록 보기'));
t('RHP-SRC8 no executable → on home (link chevrons are ›); no hard-coded dog particle left',
  !home.code.includes('→') && !home.code.includes('{current.dogName}와') && !/\$\{dogName\}를/.test(home.code));
t('RHP-SRC9 the payout strip goes through payoutHomeStrip (the no-account line suppresses the 7-day one)',
  home.code.includes('payoutHomeStrip(ledgerState, nowMs)') && !home.code.includes('payoutStuckLine('));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
