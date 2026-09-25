// work-gate-strip.ts — tests run against the REAL compiled source (see run-work-gate-strip-tests.sh),
// never a retyped copy.
//
// WHAT THIS FILE IS FOR (0224 §0c · Codex s2, 2026-09-25). 0224 taught `runner_work_gate` two new
// `waiting_on` words — `start_run` / `end_run`, a dog in custody whose run never started or never
// stopped — and both runner strips drew 「반환 봉인 찍기 ›」 → /runner/return-seal for anything that
// was not `owner`. return-seal refuses both states. The mapping now lives in `workGateStrip()`.
//
// 🔴 THE PROPERTIES, stated without reference to any mutation:
//   P1  every `waiting_on` word the server can return maps to ITS OWN sentence and exit;
//   P2  a word, exit or shape this build cannot read falls CLOSED — neutral sentence, no exit, and
//       never the return-seal sentence;
//   P3  (the compatibility pin Codex asked for) for EVERY tuple 0224's gate can return, the strip's
//       exit — when it draws one — lands on a screen whose own guard ACCEPTS that state, and every
//       tuple where the runner has a move of their own gets an exit;
//   P4  both runner screens draw the strip through this module, and runner home reads the 수락 door
//       through `workGateDoor()` — the parity 요청 already had (Codex c2).
//
// THE MUTATIONS THAT REDDEN IT: revert any arm to the return-seal exit · drop the exit-agreement
// check · let an unknown word through as a known one · draw the return exit on an incident whose run
// never ended · a screen strip that hard-codes /runner/return-seal again · home going back to
// `gate` + `gateKnown`.
const fs = require('node:fs');
const path = require('node:path');
const S = require('./work-gate-strip.build.cjs');
const { runnerJobDestination } = require('./runner-job-route.wgs.build.cjs');
const {
  workGateStrip, readWaitingOn, readExit, EXIT_FOR, WORK_GATE_WAITING_ON, WORK_GATE_EXITS,
  RETURN_EXIT_KO, START_EXIT_KO, END_EXIT_KO, START_WHY_KO, END_WHY_KO, START_SUB_KO, END_SUB_KO,
  START_DOOR_BLOCKED_KO, END_DOOR_BLOCKED_KO, RETURN_DOOR_BLOCKED_KO, UNKNOWN_WHY_KO, UNKNOWN_SUB_KO,
  UNKNOWN_DOOR_BLOCKED_KO, INCIDENT_OPEN_SUB_KO, INCIDENT_DOOR_BLOCKED_KO, REQUESTS_KEEP_KO,
} = S;

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const J = (x) => JSON.stringify(x);
const BID = 'b0000000-0000-0000-0000-00000000000a';
const ENDED = '2026-09-25T09:00:00Z';
const gate = (w, over = {}) => ({
  gated: true, bookingId: BID, rawStatus: 'active', runEndedAt: ENDED,
  waitingOn: w, exit: w === null || w === 'unknown' ? null : EXIT_FOR[w], ...over,
});
const everyLine = (st) => [st.why, st.sub, st.doorBlocked, st.requestsWhy, st.requestsSub, st.exit ? st.exit.label : ''];

// ── ① the mapper's half: known words pass, everything else is 'unknown', absence stays null ──────
t('P1 · readWaitingOn passes each of the five server words through unchanged',
  WORK_GATE_WAITING_ON.every((w) => readWaitingOn(w) === w) && WORK_GATE_WAITING_ON.length === 5);
t('P1 · readExit passes each of the five server exits through unchanged',
  WORK_GATE_EXITS.every((x) => readExit(x) === x) && WORK_GATE_EXITS.length === 5);
t('P2 · an unknown word, a wrong case, a number or an object reads as \'unknown\' — never as a known word',
  ['club_run', 'START_RUN', 'Owner', '', 7, {}, true].every((v) => readWaitingOn(v) === 'unknown')
  && ['runner_club', 'RUNNER_START_RUN', '', 0, []].every((v) => readExit(v) === 'unknown'));
t('the un-gated answer carries no word — null and undefined stay null (not \'unknown\')',
  readWaitingOn(null) === null && readWaitingOn(undefined) === null && readExit(null) === null && readExit(undefined) === null);
t('EXIT_FOR pairs each word with its own exit, one-to-one',
  new Set(Object.values(EXIT_FOR)).size === 5 && WORK_GATE_WAITING_ON.every((w) => WORK_GATE_EXITS.includes(EXIT_FOR[w])));

// ── ② P1 — every word, its own sentence and exit ────────────────────────────────────────────────
{
  const st = workGateStrip(gate('start_run', { rawStatus: 'picked_up', runEndedAt: null }));
  t('P1 · 🔴 start_run → its OWN reading: 「러닝 시작하기 ›」 onto the meetup screen, never the return seal',
    !!st && st.kind === 'start_run' && st.exit && st.exit.route === 'meetup' && st.exit.href === '/runner/meetup'
    && st.exit.label === START_EXIT_KO && st.exit.bookingId === BID, J(st));
  t('P1 · start_run → the why/sub/door sentences name the START, on both screens',
    !!st && st.why === START_WHY_KO && st.sub === START_SUB_KO && st.doorBlocked === START_DOOR_BLOCKED_KO
    && st.requestsWhy === START_DOOR_BLOCKED_KO && st.requestsSub === `${START_WHY_KO} · ${REQUESTS_KEEP_KO}`, J(st));
}
{
  const st = workGateStrip(gate('end_run', { rawStatus: 'active', runEndedAt: null }));
  t('P1 · 🔴 end_run → its OWN reading: the run screen (where the stop is), never the return seal',
    !!st && st.kind === 'end_run' && st.exit && st.exit.route === 'run' && st.exit.href === '/runner/run'
    && st.exit.label === END_EXIT_KO, J(st));
  t('P1 · end_run → the why/sub/door sentences name the END, on both screens',
    !!st && st.why === END_WHY_KO && st.sub === END_SUB_KO && st.doorBlocked === END_DOOR_BLOCKED_KO
    && st.requestsWhy === END_DOOR_BLOCKED_KO, J(st));
}
for (const w of ['runner', 'both']) {
  const st = workGateStrip(gate(w));
  t(`P1 · ${w} (run ended, return unsealed) → 「반환 봉인 찍기 ›」 onto the seal screen with the bid`,
    !!st && st.kind === 'return' && st.exit && st.exit.route === 'return_seal' && st.exit.label === RETURN_EXIT_KO
    && st.exit.href.pathname === '/runner/return-seal' && st.exit.href.params.bid === BID
    && st.why === '지난 러닝의 반환 확인이 아직이에요' && st.doorBlocked === RETURN_DOOR_BLOCKED_KO, J(st));
}
t('P1 · runner → 「내 봉인 전」; both → 「둘 다 찍혀야」 (home\'s shipped sub lines, unchanged)',
  workGateStrip(gate('runner')).sub === '내 봉인 전 — 찍으면 보호자 확인만 남아요'
  && workGateStrip(gate('both')).sub === '둘 다 찍혀야 새 요청을 받아요');
{
  const st = workGateStrip(gate('owner'));
  t('P1 · owner → NO exit (the runner already stamped — 「반환 봉인 찍기」 would be a lie about their own action), lilac wait',
    !!st && st.kind === 'return' && st.exit === null && st.tone === 'wait' && st.why === '보호자 확인 대기 중이에요'
    && st.requestsSub === `내 봉인은 끝났어요 — 보호자가 찍으면 열려요 · ${REQUESTS_KEEP_KO}`, J(st));
}
{
  const st = workGateStrip(gate('runner', { rawStatus: 'incident_review' }));
  t('P1 · incident_review with a STAMPED end → the seal screen (confirm_return_tx accepts incident_review)',
    !!st && st.exit && st.exit.route === 'return_seal' && st.why === '지난 러닝이 담당자 확인 중이에요'
    && st.requestsWhy === INCIDENT_DOOR_BLOCKED_KO, J(st));
}
{
  const st = workGateStrip(gate('both', { rawStatus: 'incident_review', runEndedAt: null }));
  t('P1 · 🔴 incident_review with NO run end → NO exit and no stamping sentence (return-seal and confirm_return_tx both refuse it)',
    !!st && st.exit === null && st.why === '진행 중인 러닝을 담당자가 확인하고 있어요'
    && st.sub === INCIDENT_OPEN_SUB_KO && st.doorBlocked === INCIDENT_DOOR_BLOCKED_KO && st.tone === 'wait', J(st));
}
t('a gate with no booking id draws no exit (there is nothing to open) but keeps its reading',
  workGateStrip(gate('start_run', { rawStatus: 'picked_up', runEndedAt: null, bookingId: null })).exit === null
  && workGateStrip(gate('start_run', { rawStatus: 'picked_up', runEndedAt: null, bookingId: null })).kind === 'start_run'
  && workGateStrip(gate('runner', { bookingId: '' })).exit === null);
t('not gated → no strip at all', workGateStrip({ gated: false }) === null && workGateStrip(null) === null
  && workGateStrip(undefined) === null && workGateStrip({ gated: 'true', waitingOn: 'runner' }) === null);

// ── ③ P2 — fail CLOSED ───────────────────────────────────────────────────────────────────────────
const isNeutral = (st) => !!st && st.kind === 'unknown' && st.exit === null && st.why === UNKNOWN_WHY_KO
  && st.sub === UNKNOWN_SUB_KO && st.doorBlocked === UNKNOWN_DOOR_BLOCKED_KO && st.tone === 'neutral';
const closedCases = [
  ['an unknown word', gate('unknown', { exit: 'unknown' })],
  // Facts with the exit OMITTED (the type allows it): the exit check cannot catch an unknown word
  // here — EXIT_FOR has no entry, so both sides are undefined — only the word guard does.
  ['an unknown word whose exit is absent', gate('unknown', { exit: undefined })],
  ['a gated answer with NO word', gate(null, { exit: null })],
  ['a known word with an unknown exit', gate('runner', { exit: 'unknown' })],
  ['start_run paired with a RETURN exit', gate('start_run', { rawStatus: 'picked_up', runEndedAt: null, exit: 'runner_confirm_return' })],
  ['runner paired with the START exit', gate('runner', { exit: 'runner_start_run' })],
  ['end_run with no exit at all', gate('end_run', { rawStatus: 'active', runEndedAt: null, exit: null })],
  ['start_run on an ACTIVE booking (0224 §B: start is picked_up)', gate('start_run', { rawStatus: 'active', runEndedAt: null })],
  ['end_run whose run END is stamped (that is a return, not an end strand)', gate('end_run', { rawStatus: 'active' })],
  ['end_run on picked_up', gate('end_run', { rawStatus: 'picked_up', runEndedAt: null })],
  ['a return word on a status the gate never admits', gate('runner', { rawStatus: 'completed' })],
  ['a return word on ACTIVE with no run end (the gate\'s arm needs a stamped end)', gate('both', { runEndedAt: null })],
];
for (const [name, g] of closedCases) {
  t(`P2 · 🔴 ${name} → the neutral face, no exit`, isNeutral(workGateStrip(g)), J(workGateStrip(g)));
}
t('P2 · the neutral face never says 반환 or 봉인 on either screen, and its door sentence is 요-final',
  closedCases.every(([, g]) => everyLine(workGateStrip(g)).every((l) => !/반환|봉인/.test(l)))
  && /요$/.test(UNKNOWN_DOOR_BLOCKED_KO) && /요$/.test(UNKNOWN_WHY_KO));
t('P2 · the MAPPER path: a raw payload with a future word reaches the neutral face (readWaitingOn → workGateStrip)',
  isNeutral(workGateStrip({ gated: true, bookingId: BID, rawStatus: 'active', runEndedAt: null,
    waitingOn: readWaitingOn('club_run'), exit: readExit('runner_club_run') })));
t('no line on any reading uses "..." (the house uses …)',
  [...WORK_GATE_WAITING_ON.map((w) => gate(w, w === 'start_run' ? { rawStatus: 'picked_up', runEndedAt: null }
    : w === 'end_run' ? { runEndedAt: null } : {})), ...closedCases.map(([, g]) => g)]
    .every((g) => everyLine(workGateStrip(g)).every((l) => !l.includes('...'))));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ④ P3 — THE COMPATIBILITY PIN: every tuple 0224's gate can return → an exit whose screen accepts it
// ══════════════════════════════════════════════════════════════════════════════════════════════
// The tuple space is read out of the SERVER (the latest declaration of each function, comments
// stripped), and each screen's acceptance is read out of THAT SCREEN's own guard — so a server that
// grows a word, or a screen that moves its guard, reddens here instead of shipping a dead exit.
const REPO = path.resolve(__dirname, '../..');
const MIG = path.join(REPO, 'supabase/migrations');
const stripSql = (x) => x.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const migFiles = fs.readdirSync(MIG).filter((f) => /^\d{4}_.*\.sql$/.test(f)).sort();
const DECL = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\(/gi;
const latestFn = (fn) => {
  let hit = null;
  for (const f of migFiles) {
    const src = stripSql(fs.readFileSync(path.join(MIG, f), 'utf8'));
    const marks = [];
    let m;
    DECL.lastIndex = 0;
    while ((m = DECL.exec(src))) marks.push({ name: m[1], at: m.index });
    marks.forEach((mk, i) => {
      if (mk.name !== fn) return;
      const next = i + 1 < marks.length ? marks[i + 1].at : src.length;
      const close = src.indexOf('$$;', mk.at);
      hit = { file: f, body: src.slice(mk.at, close > mk.at && close < next ? close + 3 : next) };
    });
  }
  if (!hit) console.log(`  NO-SOURCE(${fn})`);
  else console.log(`  (${fn} read from ${hit.file})`);
  return hit ? hit.body : '';
};
const ws = (x) => x.replace(/\s+/g, ' ');
const rwg = ws(latestFn('runner_work_gate'));
const blk = ws(latestFn('_runner_work_gate_blocking'));
const cst = ws(latestFn('_custody_strand'));
t('P3 · the three gate functions are declared (absence must fail LOUDLY, not read as 「nothing to check」)',
  rwg.length > 200 && blk.length > 200 && cst.length > 200, `${rwg.length}/${blk.length}/${cst.length}`);

// The exit case, read from runner_work_gate: every `when 'W' then 'X'` plus the `else`.
const serverPairs = {};
for (const m of rwg.matchAll(/when '([a-z_]+)'\s+then '([a-z_]+)'/g)) serverPairs[m[1]] = m[2];
const elseExit = (rwg.match(/'exit', case g\.waiting_on[\s\S]*?else '([a-z_]+)'/) || [])[1];
// `both` is the word the blocking helper names for zero stamps; the server reaches its exit via `else`.
if (elseExit) serverPairs.both = elseExit;
t('P3 · runner_work_gate\'s exit case is EXACTLY EXIT_FOR (five words, five exits, same pairs)',
  J(Object.keys(serverPairs).sort()) === J([...WORK_GATE_WAITING_ON].sort())
  && WORK_GATE_WAITING_ON.every((w) => serverPairs[w] === EXIT_FOR[w]), J(serverPairs));
t('P3 · the blocking helper names the three return words (both · runner · owner) and falls to the custody shape FIRST',
  /coalesce\(x\.shape,/.test(blk) && /then 'both'/.test(blk) && /then 'runner'/.test(blk) && /else 'owner'/.test(blk));
t('P3 · the gate admits exactly three arms: active + a stamped end · incident_review · a stranded custody shape',
  blk.includes("(b.run_ended_at is not null and b.status::text = 'active')")
  && blk.includes("or b.status::text = 'incident_review'") && blk.includes('or x.shape is not null'));
t('P3 · 0224 §B: start_run IS picked_up, end_run IS active with no run end',
  cst.includes("when b.status::text = 'picked_up' then 'start_run'")
  && cst.includes("when b.status::text = 'active' and b.run_ended_at is null then 'end_run'"));

// Each screen's acceptance, from its OWN guard (comments stripped — quote-aware, control-tested below).
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
    if (c === '/' && nx === '/') {
      while (i < src.length && src[i] !== '\n') { out += ' '; i += 1; }
      continue;
    }
    if (c === '/' && nx === '*') {
      i += 2;
      out += '  ';
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i += 1;
      }
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
const seal = read('app/runner/return-seal.tsx').code;
const meet = read('app/runner/meetup.tsx').code;
const run = read('app/runner/run.tsx').code;
const guards = {
  // return-seal: the no-run-end frame refuses a run that has not stopped; the stamp is live only on
  // active / incident_review (confirm_return_tx's own allow-list).
  return_seal: seal.includes('if (!s.runEndedAt) {')
    && seal.includes("const canStamp = s.rawStatus === 'active' || s.rawStatus === 'incident_review';"),
  // meetup: picked_up puts the stage machine on 'confirmed', whose one CTA is 러닝 시작하기 → the run.
  meetup: meet.includes("if (s2.status === 'picked_up' || s2.status === 'active') setStage('confirmed');")
    && /stage === 'confirmed' && \([\s\S]{0,400}label="러닝 시작하기 ›"[\s\S]{0,120}router\.replace\('\/runner\/run'\)/.test(meet),
  // run: a stamped end bounces to the seal screen; incident_review draws no start/stop; otherwise the
  // CTA resumes (기록 이어가기) and then stops (러닝 종료 → the end sheet), and start is awaited.
  run: run.includes('.then((r) => !!r?.runEndedAt)')
    && run.includes("router.replace({ pathname: '/runner/return-seal', params: { bid } });")
    && run.includes('{!(incidentBid && !running) && (')
    && run.includes('if (running) { openEndSheet(); return; }')
    && run.includes("resumable ? '기록 이어가기'") && run.includes('await startRunServer(bid);'),
};
t('P3 · the three exit screens still carry the guards this pin models (a moved guard reddens HERE)',
  guards.return_seal && guards.meetup && guards.run, J(guards));
const ACCEPTS = {
  return_seal: (g) => (g.rawStatus === 'active' || g.rawStatus === 'incident_review') && g.runEndedAt != null,
  meetup: (g) => g.rawStatus === 'picked_up',
  run: (g) => (g.rawStatus === 'active' || g.rawStatus === 'picked_up') && g.runEndedAt == null,
};

// The tuple space the gate can return, built from the three arms read above.
const tuples = [];
for (const [runnerStamp, ownerStamp] of [[false, false], [false, true], [true, false]]) {
  const w = !runnerStamp && !ownerStamp ? 'both' : !runnerStamp ? 'runner' : 'owner';
  tuples.push({ arm: 'A active+ended', g: gate(w, { rawStatus: 'active', runEndedAt: ENDED }), own: w !== 'owner' });
  tuples.push({ arm: 'B incident+ended', g: gate(w, { rawStatus: 'incident_review', runEndedAt: ENDED }), own: w !== 'owner' });
  // Stamps need a run end (confirm_return_tx raises run_not_ended), so only `both` is reachable here —
  // the other two are kept anyway: the strip must be SAFE on them, not merely on the reachable one.
  tuples.push({ arm: 'B incident+open', g: gate(w, { rawStatus: 'incident_review', runEndedAt: null }), own: false });
}
tuples.push({ arm: 'C start strand', g: gate('start_run', { rawStatus: 'picked_up', runEndedAt: null }), own: true });
tuples.push({ arm: 'C end strand', g: gate('end_run', { rawStatus: 'active', runEndedAt: null }), own: true });
t('P3 · the tuple space covers every word the server can return', WORK_GATE_WAITING_ON.every((w) => tuples.some((x) => x.g.waitingOn === w)));

for (const { arm, g, own } of tuples) {
  const st = workGateStrip(g);
  const label = `${arm} · ${g.waitingOn}`;
  t(`P3 · ${label} is READ (a real server shape never falls to the neutral face)`, !!st && st.kind !== 'unknown', J(st));
  if (!st) continue;
  t(`P3 · 🔴 ${label} → ${st.exit ? st.exit.route : 'no exit'} — a drawn exit lands on a screen whose guard ACCEPTS this state`,
    st.exit === null || ACCEPTS[st.exit.route](g), J({ g, exit: st.exit }));
  t(`P3 · ${label} — ${own ? 'the runner has a move of their own, so there IS an exit' : 'nothing the runner does clears it, so there is NO exit'}`,
    own ? st.exit !== null : st.exit === null, J(st.exit));
  if (st.exit) {
    // …and the exit is the same destination the in-flight ticket would take for that booking
    // (runner-job-route.ts, the contract runner/home.tsx and runner/calendar.tsx are held to).
    const d = runnerJobDestination({ bookingId: BID, rawStatus: g.rawStatus, runEndedAt: g.runEndedAt });
    t(`P3 · ${label} — the strip exit is the ticket's own destination for this state`, J(d) === J(st.exit.href), `${J(d)} vs ${J(st.exit.href)}`);
    t(`P3 · ${label} — only the seal exit may say 반환`, st.exit.route === 'return_seal' || !/반환|봉인/.test(st.exit.label + st.why + st.sub));
  }
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑤ P4 — both screens draw it through this module; home reads the door through work-gate-door
// ══════════════════════════════════════════════════════════════════════════════════════════════
const home = read('app/runner/home.tsx');
const reqs = read('app/runner/requests.tsx');
// Control the stripper on the REAL file before trusting it: `gateKnown` survives only in the
// comment that records its removal, and a real call survives stripping.
t('CONTROL ⓐ the stripper removes prose — `gateKnown` is in home.tsx only inside the comment recording its removal',
  home.raw.includes('gateKnown') && !home.code.includes('gateKnown'));
t('CONTROL ⓑ the stripper keeps executable text — `workGateDoor(gateRead)` survives in home.tsx',
  home.code.includes('const door = workGateDoor(gateRead);'));
t('P4 · 🔴 home imports the door decision from work-gate-door (parity with 요청)',
  /import \{ workGateDoor, type WorkGateRead \} from '\.\.\/\.\.\/src\/lib\/work-gate-door';/.test(home.code));
t('P4 · home records a FAILED gate read as a failure, never folded into 「not gated」',
  /fetchRunnerWorkGate\(\)[\s\S]{0,160}\.catch\([^\n]*setGateRead\('error'\)/.test(home.code));
{
  const head = home.code.indexOf('const acceptFront = () => {');
  const alert = home.code.indexOf("Alert.alert('요청 수락'", head);
  t('P4 · 🔴 home\'s acceptFront refuses the confirm Alert unless the gate is KNOWN open',
    head >= 0 && alert > head && home.code.slice(head, alert).includes('if (!door.acceptOpen) return;'), `${head}/${alert}`);
}
t('P4 · home draws the LIVE 수락 door only on door.acceptOpen — a gated or unknown door is a sentence',
  /\{door\.notice === 'gated' \? \([\s\S]{0,2500}\) : !door\.acceptOpen \? \([\s\S]{0,2500}\{door\.doorReason\}[\s\S]{0,400}\) : \(\s*<Pressable\s+onPress=\{acceptFront\}/.test(home.code));
t('P4 · home\'s failed read is drawn with a 다시 시도 that re-runs the gate read',
  /door\.notice === 'failed'[\s\S]{0,900}onPress=\{loadGate\}[\s\S]{0,300}\{door\.retry\}/.test(home.code));
t('P4 · home\'s strip is the module\'s reading, and its exit writes the store then pushes the module\'s href',
  home.code.includes('workGateStrip(gateRead)') && /runnerJob\.bookingId = x\.bookingId;\s*router\.push\(x\.href\);/.test(home.code)
  && home.code.includes('onPress={() => goGateExit(x)}'));
t('P4 · 🔴 requests draws the same reading (workGateStrip) and pushes its href — no hard-coded seal exit left',
  reqs.code.includes('const gateStrip = workGateStrip(gate);')
  && /runnerJob\.bookingId = x\.bookingId;\s*router\.push\(x\.href\);/.test(reqs.code));
for (const [name, f] of [['home', home], ['requests', reqs]]) {
  t(`P4 · 🔴 ${name}: no executable 「반환 봉인 찍기」 literal and no strip push of /runner/return-seal — the module owns both`,
    !f.code.includes('반환 봉인 찍기') && !/gate\.waitingOn === 'owner'/.test(f.code));
}
t('P4 · home keeps no `gate` + `gateKnown` pair in executable code', !/\bgateKnown\b/.test(home.code) && !/setGateKnown/.test(home.code));

// ── ⑥ the api.ts mapper reads the words through this module (source, line comments stripped) ──
{
  const api = fs.readFileSync(path.join(__dirname, '..', 'src/lib/api.ts'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  const at = api.indexOf('export async function fetchRunnerWorkGate');
  const body = at >= 0 ? api.slice(at, api.indexOf('\n}\n', at)) : '';
  t('api.ts still declares fetchRunnerWorkGate (absence fails LOUDLY)', body.length > 100);
  t('P2 · 🔴 the mapper reads both words through readWaitingOn / readExit — a raw passthrough would let an unknown word masquerade',
    body.includes('waitingOn: readWaitingOn(g.waiting_on),') && body.includes('exit: readExit(g.exit),'), body.slice(-300));
  t('the RunnerWorkGate type carries the read types, not the three-word literal union',
    /waitingOn: WaitingOnRead \| null;/.test(api) && /exit: ExitRead \| null;/.test(api)
    && !/waitingOn: 'both' \| 'runner' \| 'owner' \| null;/.test(api));
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
