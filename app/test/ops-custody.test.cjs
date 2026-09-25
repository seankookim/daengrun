// ops-custody.ts — the two 0224 console desks (러닝 좌초 · 정산 미완료). Tests run against the REAL
// compiled source (see run-ops-custody-tests.sh), never a retyped copy.
//
// 🔴 THE PROPERTIES, stated without reference to any mutation:
//   D1  each desk is drawn, fetched and read only for an operator on the roster ITS read gates on
//       (0224 §F: custody → `return_strand`, sealed → `payout_due`) — read out of 0224, not retyped;
//   D2  every face says what it is — loading in words, a failure with 다시 시도, an empty list that
//       claims no more than it knows, rows naming the booking, both parties and how long — and no row
//       is a button, because no ops door exists behind either list (0224 §0c);
//   D3  a bell tap's `bid` is READ and marks its row;
//   D4  both wrappers fold through `foldRpcError` with the name of the function they call, so the
//       PGRST202 window before 0224 is pushed renders the version-mismatch sentence, not PostgREST's
//       English, and both names are on PENDING_DEPLOY.
const fs = require('node:fs');
const path = require('node:path');
const C = require('./ops-custody.build.cjs');
const R = require('./rpc-error.ops-custody.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const J = (x) => JSON.stringify(x);
const NOW = Date.parse('2026-09-25T12:00:00Z');
const ago = (min) => new Date(NOW - min * 60000).toISOString();

// ── ① desk access: an unread answer is not a 'no' ───────────────────────────────────────────────
t('D1 · kinds not read yet → unknown (never 「not held」)', C.deskAccess(null, 'return_strand') === 'unknown');
t('D1 · the class held → held; another class only → not_held; [] → not_held (a measured none)',
  C.deskAccess(['return_strand'], 'return_strand') === 'held'
  && C.deskAccess(['payout_due'], 'return_strand') === 'not_held'
  && C.deskAccess([], 'payout_due') === 'not_held');

// ── ② the custody desk's sentences ──────────────────────────────────────────────────────────────
t('D2 · start_run and end_run each get their own sentence',
  C.custodyShapeLabel('start_run') === '인계는 끝났는데 러닝이 시작되지 않았어요'
  && C.custodyShapeLabel('end_run') === '예정 시간이 지났는데 러닝이 종료되지 않았어요');
t('D2 · a shape this build cannot read is SAID, never mapped onto start or end',
  !/시작되지|종료되지/.test(C.custodyShapeLabel('club_run')) && C.custodyShapeLabel('').length > 0);
t('D2 · how long — from the handoff for a start strand, from the nominal end for an end strand',
  C.custodyAgeLabel('start_run', ago(45), NOW) === '인계 후 45분째'
  && C.custodyAgeLabel('end_run', ago(125), NOW) === '예정 종료 후 2시간 5분째'
  && C.custodyAgeLabel('start_run', ago(180), NOW) === '인계 후 3시간째',
  J([C.custodyAgeLabel('start_run', ago(45), NOW), C.custodyAgeLabel('end_run', ago(125), NOW)]));
t('D2 · no clock, an unparseable clock, a future clock or an unknown shape → NO age (absent, never 0분)',
  C.custodyAgeLabel('start_run', null, NOW) === null && C.custodyAgeLabel('start_run', 'not-a-date', NOW) === null
  && C.custodyAgeLabel('end_run', ago(-10), NOW) === null && C.custodyAgeLabel('club_run', ago(30), NOW) === null
  && C.custodyAgeLabel('start_run', ago(30), NaN) === null);
t('D2 · the threshold line reports the SERVER\'s off-switch only when a row carried it',
  /꺼져 있어요/.test(C.custodyThresholdNote(null, null)));
t('D2 · …and a live threshold with how far past it the row is',
  C.custodyThresholdNote(30, null) === '좌초 기준 30분'
  && C.custodyThresholdNote(30, 15) === '좌초 기준 30분 · 기준을 넘긴 지 15분째'
  && C.custodyThresholdNote(30, -5) === '좌초 기준 30분 · 아직 기준 전이에요',
  J([C.custodyThresholdNote(30, 15), C.custodyThresholdNote(30, -5)]));
t('D2 · the bell note says PENDING in words (the operator reading it is on the roster)',
  /아직/.test(C.custodyNotifiedNote(null)) && /발송된/.test(C.custodyNotifiedNote('2026-09-25T10:00:00Z')));
t('D2 · 🔴 the empty custody list claims LESS than it looks — it cannot tell whether the sweep is on',
  /알 수 없어요/.test(C.CUSTODY_EMPTY_SUB_KO));

// ── ③ the sealed desk's sentences ───────────────────────────────────────────────────────────────
t('D2 · minutes sealed → 「봉인 후 N」; absent or negative → nothing',
  C.sealedAgeLabel(425) === '봉인 후 7시간 5분째' && C.sealedAgeLabel(null) === null && C.sealedAgeLabel(-1) === null,
  C.sealedAgeLabel(425));
t('D2 · the sealed bell note prints no number (the delay is the sweep\'s constant, not the client\'s)',
  !/\d/.test(C.sealedNotifiedNote(null)) && /발송된/.test(C.sealedNotifiedNote('2026-09-25T10:00:00Z')));

// ── ④ shared ─────────────────────────────────────────────────────────────────────────────────────
t('D2 · rows name the booking (short id) and both parties, falling back to a word — never a blank',
  C.bookingRef('a1b2c3d4-0000-0000-0000-000000000000') === '예약 A1B2C3D4'
  && C.partiesLine('민지', null) === '보호자 민지 · 러너 이름 없음' && C.partiesLine(null, '도윤') === '보호자 이름 없음 · 러너 도윤');
{
  const all = Object.entries(C).filter(([k, v]) => /_KO$/.test(k) && typeof v === 'string');
  t('every exported Korean sentence is ≥ 1 char, uses … not ..., and none is an English token',
    all.length === 18 && all.every(([, v]) => v.length > 0 && !v.includes('...') && /[가-힣]/.test(v)), String(all.length));
  t('every loading line ends with …, every other sentence ends in 요',
    all.every(([k, v]) => (/LOADING/.test(k) ? /…$/.test(v) : /TITLE/.test(k) || /요\.?$/.test(v))),
    J(all.filter(([k, v]) => !(/LOADING/.test(k) ? /…$/.test(v) : /TITLE/.test(k) || /요\.?$/.test(v)))));
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑤ D1 — the rosters, read out of 0224's own reads (comments stripped, latest declaration)
// ══════════════════════════════════════════════════════════════════════════════════════════════
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
  console.log(hit ? `  (${fn} read from ${hit.file})` : `  NO-SOURCE(${fn})`);
  return hit ? hit.body : '';
};
const custodyFn = latestFn('ops_stranded_custody');
const sealedFn = latestFn('ops_sealed_unsettled');
const classOf = (body) => (body.match(/c_ops_class\s+constant text := '([a-z_]+)'/) || [])[1] || null;
t('D1 · both reads are declared (absence fails LOUDLY)', custodyFn.length > 200 && sealedFn.length > 200);
t('D1 · 🔴 the custody desk\'s class IS the roster ops_stranded_custody gates on',
  classOf(custodyFn) === C.CUSTODY_DESK_CLASS && C.CUSTODY_DESK_CLASS === 'return_strand', classOf(custodyFn));
t('D1 · 🔴 the sealed desk\'s class IS the roster ops_sealed_unsettled gates on',
  classOf(sealedFn) === C.SEALED_DESK_CLASS && C.SEALED_DESK_CLASS === 'payout_due', classOf(sealedFn));
t('D1 · …and both reads raise not_ops for anyone off that roster BEFORE any read (so the client gate agrees)',
  [custodyFn, sealedFn].every((b) => /ops_recipients_for\(c_ops_class\)[\s\S]{0,200}is not true[\s\S]{0,40}raise exception 'not_ops'/.test(b)
    && b.indexOf("raise exception 'not_ops'") < b.indexOf('return query')));

// ── the columns the wrappers map are the columns the reads return (a renamed column is a blank row) ──
const api = fs.readFileSync(path.join(__dirname, '..', 'src/lib/api.ts'), 'utf8')
  .split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
const fnBody = (name) => {
  const at = api.indexOf(`export async function ${name}(`);
  return at >= 0 ? api.slice(at, api.indexOf('\n}\n', at)) : '';
};
const wCustody = fnBody('fetchOpsStrandedCustody');
const wSealed = fnBody('fetchOpsSealedUnsettled');
const retCols = (body) => {
  const m = body.match(/returns table \(([\s\S]*?)\)\s*language/);
  return m ? m[1].split(',').map((c) => c.trim().split(/\s+/)[0]).filter(Boolean) : [];
};
t('D4 · api.ts declares both wrappers (absence fails LOUDLY)', wCustody.length > 100 && wSealed.length > 100);
for (const [name, body, w] of [['ops_stranded_custody', custodyFn, wCustody], ['ops_sealed_unsettled', sealedFn, wSealed]]) {
  const cols = retCols(body);
  t(`${name} · every returned column is read by its wrapper (r.<col>), and it reads nothing the read does not return`,
    cols.length >= 9 && cols.every((c) => w.includes(`r.${c}`))
    && [...w.matchAll(/\br\.([a-z_]+)/g)].every((m) => cols.includes(m[1])), J(cols));
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑥ D4 — the two wrappers FOLD, with their own function's name, and are on PENDING_DEPLOY
// ══════════════════════════════════════════════════════════════════════════════════════════════
for (const [fn, w] of [['ops_stranded_custody', wCustody], ['ops_sealed_unsettled', wSealed]]) {
  t(`D4 · 🔴 ${fn}: the wrapper calls exactly that RPC and throws opsError(error, '${fn}') — the SAME name`,
    w.includes(`supabase.rpc('${fn}')`) && w.includes(`if (error) throw opsError(error, '${fn}');`), w.slice(0, 200));
  const skew = R.foldRpcError({ code: 'PGRST202', message: `Could not find the function public.${fn} without parameters in the schema cache` },
    { fn, tokens: { not_ops: 'OPS' }, empty: 'EMPTY' });
  t(`D4 · 🔴 ${fn}: before 0224 is pushed, the PGRST202 folds to the version-mismatch sentence (it is on PENDING_DEPLOY)`,
    skew.message === R.PENDING_DEPLOY_KO, skew.message);
  const refused = R.foldRpcError({ message: 'not_ops' }, { fn, tokens: { not_ops: '운영자 권한이 없어요' } });
  t(`D4 · ${fn}: a named refusal maps through the caller's table`, refused.message === '운영자 권한이 없어요');
  const english = R.foldRpcError({ message: 'permission denied for function ' + fn }, { fn, tokens: { not_ops: 'x' } });
  t(`D4 · ${fn}: raw English never reaches the screen (folds, and keeps the diagnosis on raw)`,
    english.message === R.RPC_FOLD_KO && R.rpcRaw(english).includes('permission denied'));
}
t('D4 · opsError is foldRpcError with the ops token table (the path both wrappers take)',
  /function opsError\(e: unknown, fn\?: string\): Error \{\s*return foldRpcError\(e, \{ fn, tokens: OPS_ERROR_KO,/.test(api));
t('D4 · a DIFFERENT function\'s PGRST202 is not borrowed as skew (the allowlist is by name)',
  R.foldRpcError({ code: 'PGRST202', message: 'Could not find the function public.ops_stranded_custody_v2 without parameters' },
    { fn: 'ops_stranded_custody_v2' }).message !== R.PENDING_DEPLOY_KO);

// ══════════════════════════════════════════════════════════════════════════════════════════════
// ⑦ the screens — faces, the bid read, the roster gate, and NO row doors (source, comments stripped)
// ══════════════════════════════════════════════════════════════════════════════════════════════
const stripTsx = (x) => x.replace(/\/\*[\s\S]*?\*\//g, '').split('\n').map((l) => l.replace(/^\s*\/\/.*$/, '')).join('\n');
const readTsx = (rel) => {
  const raw = fs.readFileSync(path.join(__dirname, '..', rel), 'utf8');
  if (raw.length < 500) throw new Error(`NO-SOURCE(${rel})`);
  return { raw, code: stripTsx(raw) };
};
const scr = { custody: readTsx('app/ops/custody.tsx'), sealed: readTsx('app/ops/sealed.tsx') };
t('CONTROL · the stripper removes prose (both screens\' headers say 「READ」 only in comments) and keeps code',
  scr.custody.raw.includes('A READ AND ONLY A READ') && !scr.custody.code.includes('A READ AND ONLY A READ')
  && scr.custody.code.includes('fetchOpsStrandedCustody()'));
for (const [k, pre, fetchName, cls] of [
  ['custody', 'CUSTODY', 'fetchOpsStrandedCustody', 'CUSTODY_DESK_CLASS'],
  ['sealed', 'SEALED', 'fetchOpsSealedUnsettled', 'SEALED_DESK_CLASS'],
]) {
  const c = scr[k].code;
  t(`D1 · /ops/${k} gates on its own class through deskAccess, and fetches only when held`,
    c.includes(`const access = deskAccess(kinds, ${cls});`) && c.includes("if (access === 'held') load();"));
  t(`D1 · /ops/${k} says 「not your desk」 in words for a non-holder (no 다시 시도 that can never succeed)`,
    new RegExp(`access === 'not_held' && \\(\\s*<View[\\s\\S]{0,200}\\{${pre}_REFUSED_KO\\}`).test(c));
  t(`D2 · /ops/${k} has all four faces: loading in words · failure + 다시 시도 (load) · empty · rows`,
    c.includes(`{${pre}_LOADING_KO}`) && /phase === 'error'[\s\S]{0,300}onPress=\{load\}[\s\S]{0,200}다시 시도/.test(c)
    && c.includes(`{${pre}_EMPTY_KO}`) && c.includes(`{${pre}_EMPTY_SUB_KO}`) && c.includes('rows.map((r) =>'));
  t(`D2 · /ops/${k} rows name the booking, both parties and how long`,
    c.includes('bookingRef(r.bookingId)') && c.includes('partiesLine(r.ownerName, r.runnerName)')
    && (c.includes('custodyAgeLabel(r.shape, r.sinceAt, readAt)') || c.includes('sealedAgeLabel(r.minutesSealed)')));
  // The back key is ScreenHead's (DESIGN.md §3b chrome header, ui/chrome-consistency-2) — so the
  // screen's own tappables are exactly its failure strips' 다시 시도.
  // [0233 §F] /ops/custody now carries TWO lists (러닝 좌초 + 러닝 전 사고 검토) that load and fail
  // independently, so it has TWO 다시 시도 — and still NO row door. The property this pin owns is
  // unchanged (every Pressable is a retry); only the count of lists moved. `0233-P1` below pins the
  // second strip's retry target.
  const retries = k === 'custody' ? 2 : 1;
  t(`D2 · 🔴 /ops/${k} draws NO row door — its only own Pressables are 다시 시도 (${retries}, with a role); the header is ScreenHead`,
    (c.match(/<Pressable\b/g) || []).length === retries && (c.match(/accessibilityRole="button"/g) || []).length === retries
    && (c.match(/<Text style=\{s\.retryLabel\}>다시 시도<\/Text>/g) || []).length === retries
    && c.includes(`<ScreenHead title={${pre}_TITLE_KO} />`) && !c.includes('accessibilityLabel="뒤로"'));
  t(`D3 · /ops/${k} reads the bell's bid and marks its row, and says so when the row is gone`,
    c.includes('useLocalSearchParams<{ bid?: string }>()') && c.includes("const highlightId = typeof params.bid === 'string' ? params.bid : '';")
    && c.includes('const marked = r.bookingId === highlightId;') && c.includes('marked && s.rowMarked')
    && /!rows\.some\(\(r\) => r\.bookingId === highlightId\)/.test(c) && c.includes(`{${pre}_GONE_KO}`));
  t(`D4 · /ops/${k} logs rpcRaw and renders the folded message`,
    new RegExp(`${fetchName}\\(\\)[\\s\\S]{0,200}rpcRaw\\(e\\)[\\s\\S]{0,120}\\(e as Error\\)\\?\\.message \\|\\| ${pre}_FAILED_KO`).test(c));
}

// ── [0233 §F] /ops/custody's pre-run section: its own faces, its own retry, the bid, no remedy ─────
{
  const c = scr.custody.code;
  t('0233-P1 · the pre-run list is fetched only when the desk is held, and has all four faces with its OWN retry',
    c.includes("if (access === 'held') loadPre();") && c.includes('{PRERUN_LOADING_KO}')
    && /prePhase === 'error'[\s\S]{0,300}onPress=\{loadPre\}[\s\S]{0,200}다시 시도/.test(c)
    && c.includes('{PRERUN_EMPTY_KO}') && c.includes('pre.map((c) =>'));
  t('0233-P1 · a bid marks a PRE-RUN row too, and 「gone」 waits for BOTH lists',
    c.includes('const preMarked = c.bookingId === highlightId;') && c.includes('preMarked && s.rowMarked')
    && /phase === 'ready' && prePhase === 'ready'[\s\S]{0,200}!pre\.some\(\(c\) => c\.bookingId === highlightId\)/.test(c));
  // 🔴 NO REMEDY: no pre-run row names a door (L2/L3 are Sean's). Checked on the RAW source of the
  //    section's copy so a remedy word anywhere in its sentences reddens.
  const sec = scr.custody.raw.slice(scr.custody.raw.indexOf('const PRERUN_TITLE_KO'), scr.custody.raw.indexOf('const s = StyleSheet.create'));
  t('0233-P1 · 🔴 the pre-run copy names no remedy (no confirm/resolve/close door, no 해주세요)',
    sec.length > 200 && !/confirm_return|resolve|해주세요|처리하세요|눌러/.test(sec), sec.slice(0, 80));
  // 🔴 `runner_gated` answers for THIS row only (0233 §F), so the sentence must be about this booking:
  //    「러너는 새 요청을 받을 수 있어요」 is false for a runner held by ANOTHER booking (review of 8682181).
  const gatedDecl = (name) => (c.match(new RegExp(`const ${name} = '([^']*)';`)) || [])[1];
  t('0233-P2 · 🔴 the gated line speaks for THIS booking, never for the runner as a whole',
    c.includes('{c.runnerGated ? PRERUN_GATED_KO : PRERUN_NOT_GATED_KO}')
    && /^이 예약/.test(gatedDecl('PRERUN_GATED_KO') || '') && /^이 예약/.test(gatedDecl('PRERUN_NOT_GATED_KO') || '')
    && !c.includes('러너는 새 요청을 받을 수 있어요') && !c.includes('러너는 새 요청을 받을 수 없는 상태예요'),
    `${gatedDecl('PRERUN_GATED_KO')} / ${gatedDecl('PRERUN_NOT_GATED_KO')}`);
}

// ── ops/index.tsx: the entry rows appear only for the relevant class ─────────────────────────────
{
  const idx = stripTsx(fs.readFileSync(path.join(__dirname, '..', 'app/ops/index.tsx'), 'utf8'));
  t('D1 · 🔴 the console computes each desk from ITS class', idx.includes("const hasCustodyDesk = deskAccess(kinds, CUSTODY_DESK_CLASS) === 'held';")
    && idx.includes("const hasSealedDesk = deskAccess(kinds, SEALED_DESK_CLASS) === 'held';"));
  t('D1 · 🔴 each section is drawn only when its desk is held', /\{hasCustodyDesk && \(\s*<>/.test(idx) && /\{hasSealedDesk && \(\s*<>/.test(idx));
  t('D1 · …and fetched only when held (focus and pull-to-refresh)',
    (idx.match(/if \(hasCustodyDesk\) loadCustody\(\);/g) || []).length === 2
    && (idx.match(/if \(hasSealedDesk\) loadSealed\(\);/g) || []).length === 2);
  t('D2 · each section prints its count only once READ, and has loading / FailStrip / empty faces',
    idx.includes("count={custodyPhase === 'ready' ? custody.length : null}") && idx.includes("count={sealedPhase === 'ready' ? sealed.length : null}")
    && idx.includes('<FailStrip message={custodyErr} onRetry={loadCustody} />') && idx.includes('<FailStrip message={sealedErr} onRetry={loadSealed} />')
    && idx.includes('{CUSTODY_EMPTY_KO}') && idx.includes('{SEALED_EMPTY_KO}'));
  // [0234 §D] the open-incidents desk: its own class, fetched only when held, four faces, no door
  t('0234-P1 · 🔴 the open-incidents desk is computed from incident_opened, drawn and fetched only when held',
    idx.includes("const hasIncidentDesk = deskAccess(kinds, INCIDENT_DESK_CLASS) === 'held';")
    && idx.includes("const INCIDENT_DESK_CLASS = 'incident_opened';")
    && /\{hasIncidentDesk && \(\s*<>/.test(idx)
    && (idx.match(/if \(hasIncidentDesk\) loadIncidents\(\);/g) || []).length === 2);
  t('0234-P1 · loading in words, FailStrip with 다시 시도 → loadIncidents, an empty face, count only once read',
    idx.includes('{INCIDENTS_LOADING_KO}') && idx.includes('<FailStrip message={incErr} onRetry={loadIncidents} />')
    && idx.includes('열린 사고가 없어요') && idx.includes("count={incPhase === 'ready' ? incidents.length : null}"));
  // [0234 review finding 4] a bell tap into this screen must always have a visible effect: the
  // marked card is scrolled into view, and a mark this screen does not draw is SAID (closed since, or
  // the desk no longer held) — never a silent no-op, and never claimed before the answer is read.
  t('0234-P2 · 🔴 a bell pointed at an incident this screen does not draw says so — only once the list was read or the desk is known not held',
    idx.includes("(incidentDeskHeld === 'held' && incPhase === 'ready' && !incidents.some((i) => i.incidentId === incidentMark))")
    && idx.includes("|| incidentDeskHeld === 'not_held');")
    && idx.includes("const incidentNotListed = incidentMark !== '' && (")
    && /\{incidentNotListed && \(\s*<View[\s\S]{0,400}\{INCIDENT_NOT_LISTED_KO\}/.test(idx)
    && idx.includes("{incidentDeskHeld === 'held' ? INCIDENT_NOT_LISTED_SUB_KO : INCIDENT_DESK_NOT_HELD_SUB_KO}"));
  t('0234-P2 · 🔴 a marked incident is brought into view — the tap scrolls to the card (or the note), a push pays on layout',
    idx.includes('ref={scrollRef}') && idx.includes('scrollRef.current?.scrollTo({ y: Math.max(0, y - 16), animated: true });')
    && idx.includes('if (bringIntoView(listed ? iid : INCIDENT_NOT_LISTED_KEY)) pendingScroll.current = \'\';')
    && idx.includes('if (pendingScroll.current === i.incidentId && bringIntoView(i.incidentId)) pendingScroll.current = \'\';')
    && idx.includes("useEffect(() => { if (paramIid !== '') pendingScroll.current = paramIid; }, [paramIid]);"));
  t('0234-P1 · 🔴 an incident card is NOT a door (a plain View; no push to a per-incident screen)',
    // (the card's props now span lines — it gained an onLayout for 0234-P2 — so `\s+`, same property)
    /incidents\.map\(\(i\) => \{[\s\S]{0,200}<View\s+key=\{i\.incidentId\}/.test(idx) && !/router\.push\(`\/ops\/incident/.test(idx));
  t('D2 · each section\'s door opens its list and is drawn only when there are rows',
    /custody\.length > 0 && \(\s*<Pressable\s+onPress=\{\(\) => router\.push\('\/ops\/custody'\)\}/.test(idx)
    && /sealed\.length > 0 && \(\s*<Pressable\s+onPress=\{\(\) => router\.push\('\/ops\/sealed'\)\}/.test(idx));
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
