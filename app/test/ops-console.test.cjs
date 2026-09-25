// ops-console.ts — tests run against the REAL compiled source (see run-ops-console-tests.sh), not
// a retyped copy.
//
// Why these sentences need pinning at all: `app/test/*.cjs` cannot import a `.tsx` route module, so
// re-planting a wrong sentence into `ops/returns/index.tsx` or `ops/handoffs.tsx` reddens NOTHING.
// Pulling the composition out into a pure module is what makes it testable; the same source-vs-
// runtime division as `check-device-clock` beside the 33 KST pins — and the same warning: these
// pins prove the SENTENCES, they say nothing about whether a screen calls them.
//
// 🔴 The propositions, each stated without reference to any mutation:
//   · A NULL never renders as a zero or a dash. Every absent value here is absent for a reason the
//     operator has to know, and each function says the reason in words.
//   · The strand deadline has THREE states and the client can only ever observe two of them.
//     `off` — a null the SERVER returned on a row — says the ALARM IS OFF, which is the shipped
//     state of `ops_flags.return_strand_minutes` (0193 §A) and the one case where an empty list
//     is not good news. `unknown` — an empty response, which carries no threshold at all because
//     0206 §A has nowhere but a row to put one — says NOTHING about the setting, because an
//     enabled deadline with nothing stranded produces exactly the same payload.
//     ⚠ **PINS CHANGED 2026-09-25 AND THIS IS WHY** (codex #3): they previously asserted
//     `strandDeadlineNote(null)` → the off-switch sentence, and the screen fed the EMPTY case
//     that same null — so the console printed a configuration claim about production that
//     nothing had measured. The behaviour those pins described was the defect. `deadline ·
//     unknown` below owns the new property; `deadline · off` still owns the old one, now reachable
//     only from a server-returned null.
//   · `handoffAlertNote` distinguishes 0183's PENDING (parties told, roster empty, arm ⓔ retrying)
//     from 「told everybody」. Drawn as a blank, PENDING reads as a failed escalation.
//   · `strandStateLabel` gates on the RAW server word and never prints it.
const {
  strandAgeLabel, strandStateLabel, strandDeadlineFrom, strandDeadlineNote, strandNotifiedNote,
  STRAND_EMPTY_UNKNOWN_KO,
  handoffWaitingLabel, handoffAlertNote, memoRefusal, MEMO_REQUIRED_KO, resolveOutcomeLabel,
} = require('./ops-console.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const hasKorean = (s) => /[가-힣]/.test(s);

// ── strandAgeLabel: a duration, and null when there is no number ─────────────────────────────
t('age · null in ⇒ null out (a minute count we do not have is ABSENT, not 0분째)',
  strandAgeLabel(null) === null);
t('age · a non-finite number is also absent, never NaN분째',
  strandAgeLabel(NaN) === null && strandAgeLabel(Infinity) === null);
t('age · under an hour keeps the minute form (a fresh strand must not read 0시간)',
  strandAgeLabel(0) === '0분째' && strandAgeLabel(1) === '1분째' && strandAgeLabel(59) === '59분째',
  `${strandAgeLabel(0)} / ${strandAgeLabel(59)}`);
t('age · a whole hour drops the minutes', strandAgeLabel(60) === '1시간째' && strandAgeLabel(180) === '3시간째',
  `${strandAgeLabel(60)} / ${strandAgeLabel(180)}`);
t('age · hours and minutes together', strandAgeLabel(200) === '3시간 20분째', strandAgeLabel(200));
t('age · a negative is floored at zero rather than printing a minus',
  strandAgeLabel(-5) === '0분째', String(strandAgeLabel(-5)));

// ── strandStateLabel: gate on the raw word, print the mapped sentence ────────────────────────
{
  const all = [
    strandStateLabel('active', true, false),
    strandStateLabel('active', false, true),
    strandStateLabel('active', false, false),
    strandStateLabel('active', true, true),
    strandStateLabel('incident_review', false, false),
    strandStateLabel('incident_review', true, true),
  ];
  t('state · every branch is Korean prose and never the raw server word (STATUS_MAP law)',
    all.every((x) => hasKorean(x) && !x.includes('active') && !x.includes('incident_review')),
    JSON.stringify(all));
  t('state · every branch is a DIFFERENT sentence (a table that collapses two states is a table that hides one)',
    new Set(all).size === all.length, JSON.stringify(all));
  t('state · one-sided says WHICH side is missing, by name',
    strandStateLabel('active', true, false).includes('보호자')
    && strandStateLabel('active', false, true).includes('러너'));
  t('state · 🔴 incident_review with BOTH stamps still says 담당자 확인 대기 — 0096 lets late stamps land there WITHOUT sealing, so two ticks must not read as 「all is well」',
    strandStateLabel('incident_review', true, true).includes('담당자 확인 대기'),
    strandStateLabel('incident_review', true, true));
  t('state · incident_review is distinguished from an ordinary active row even with identical stamps',
    strandStateLabel('incident_review', false, false) !== strandStateLabel('active', false, false));
}

// ── the strand deadline: three states, and only two of them are observable ───────────────────
{
  const off = strandDeadlineFrom([{ strandMinutes: null }]);
  const live = strandDeadlineFrom([{ strandMinutes: 180 }]);
  const unknown = strandDeadlineFrom([]);

  t('deadline · 🔴 an EMPTY list is `unknown` — 0206 §A carries the threshold on ROWS, so an empty response measured nothing about the setting',
    unknown.state === 'unknown', JSON.stringify(unknown));
  t('deadline · 🔴 and `unknown` prints NO sentence at all — the console must not make a configuration claim it never measured (codex #3)',
    strandDeadlineNote(unknown) === null, String(strandDeadlineNote(unknown)));
  t('deadline · 🔴 `unknown` is a DIFFERENT state from `off`, not a synonym — an enabled deadline with nothing stranded and a switched-off arm produce the identical empty payload',
    unknown.state !== off.state && strandDeadlineNote(unknown) !== strandDeadlineNote(off));

  t('deadline · 🔴 a NULL the SERVER returned on a row still says the alarm is OFF — the shipped value of ops_flags.return_strand_minutes, and the one case where an empty list is NOT good news',
    off.state === 'off' && strandDeadlineNote(off).includes('꺼져 있어요'), String(strandDeadlineNote(off)));
  t('deadline · OFF also says what IS still shown, so the list is not read as complete',
    strandDeadlineNote(off).includes('이미 알림이 간'), String(strandDeadlineNote(off)));
  t('deadline · a number is stated as the rule it is',
    live.state === 'minutes' && strandDeadlineNote(live) === '러닝 종료 후 180분이 지나면 좌초로 봅니다',
    String(strandDeadlineNote(live)));
  t('deadline · a non-finite value on a row takes the OFF branch rather than printing NaN분',
    strandDeadlineFrom([{ strandMinutes: NaN }]).state === 'off');
  t('deadline · a negative minute count is floored rather than printed as a minus',
    strandDeadlineNote(strandDeadlineFrom([{ strandMinutes: -5 }])) === '러닝 종료 후 0분이 지나면 좌초로 봅니다',
    String(strandDeadlineNote(strandDeadlineFrom([{ strandMinutes: -5 }]))));
  t('deadline · the deadline is read off the FIRST row and rows do not disagree about it — one server fact, not a per-row one',
    strandDeadlineNote(strandDeadlineFrom([{ strandMinutes: 180 }, { strandMinutes: 180 }]))
      === strandDeadlineNote(live));

  t('deadline · the empty card SAYS what it cannot know, in Korean, instead of leaving it to an inference',
    hasKorean(STRAND_EMPTY_UNKNOWN_KO) && STRAND_EMPTY_UNKNOWN_KO.includes('알 수 없어요'),
    STRAND_EMPTY_UNKNOWN_KO);
  t('deadline · and that sentence is not the OFF sentence wearing another hat',
    STRAND_EMPTY_UNKNOWN_KO !== strandDeadlineNote(off) && !STRAND_EMPTY_UNKNOWN_KO.includes('꺼져 있어요'));
}
{
  // ⚠ A SECOND, DIFFERENT PROPOSITION, and it is weaker on purpose: everything above proves the
  //   DECISION FUNCTION, and says nothing about whether the screen calls it — `app/test/*.cjs`
  //   cannot import a `.tsx`. This arm reads the route module AS TEXT (the idiom `tab-parent`
  //   and the memo pin below already use) with comment lines stripped first, because a comment
  //   describing the fix would otherwise satisfy a grep for the fix (the standing comment-quoting
  //   law: documenting it and doing it must not look identical). It proves only that the call is
  //   written; it does not prove what renders. Only a device does that.
  const fs = require('fs');
  const path = require('path');
  const code = fs.readFileSync(path.resolve(__dirname, '../app/ops/returns/index.tsx'), 'utf8')
    .split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
  t('screen · the returns console composes its deadline through strandDeadlineFrom(rows) — executable lines only',
    /strandDeadlineFrom\(rows\)/.test(code), 'no strandDeadlineFrom(rows) call outside comments');
  t('screen · 🔴 and it never takes the threshold off row 0 by hand, which is the shape that flattened unknown into off',
    !/rows\[0\]\s*\.\s*strandMinutes/.test(code), 'a hand-rolled rows[0].strandMinutes is back');
  t('screen · the empty card carries the 「cannot know」 sentence',
    /STRAND_EMPTY_UNKNOWN_KO/.test(code), 'empty card does not print STRAND_EMPTY_UNKNOWN_KO');
}

// ── strandNotifiedNote: belled vs not-yet-belled are different facts ─────────────────────────
t('notified · not yet belled says so AND says it is coming (the row is in the list because it is past the deadline)',
  strandNotifiedNote(null).includes('아직') && strandNotifiedNote(null).includes('다음 점검'),
  strandNotifiedNote(null));
t('notified · belled is a different sentence',
  strandNotifiedNote('2026-09-22T10:00:00Z') !== strandNotifiedNote(null));

// ── handoffWaitingLabel: who stamped, who we wait on, and no invented names ──────────────────
t('handoff · owner stamped ⇒ we are waiting on the runner, both named',
  handoffWaitingLabel(true, false, '김보호', '박러너') === '김보호 확인 완료 — 박러너 확인을 기다리는 중',
  handoffWaitingLabel(true, false, '김보호', '박러너'));
t('handoff · runner stamped ⇒ the mirror sentence',
  handoffWaitingLabel(false, true, '김보호', '박러너') === '박러너 확인 완료 — 김보호 확인을 기다리는 중',
  handoffWaitingLabel(false, true, '김보호', '박러너'));
t('handoff · a nameless profile falls back to its ROLE word — never a blank and never an invented name',
  handoffWaitingLabel(true, false, null, null) === '보호자 확인 완료 — 러너 확인을 기다리는 중',
  handoffWaitingLabel(true, false, null, null));
t('handoff · the two unreachable states (0206 §B is an XOR) still say something actionable rather than rendering blank',
  hasKorean(handoffWaitingLabel(true, true, null, null))
  && hasKorean(handoffWaitingLabel(false, false, null, null))
  && handoffWaitingLabel(true, true, null, null).includes('새로고침')
  && handoffWaitingLabel(false, false, null, null).includes('새로고침'));

// ── handoffAlertNote: 0183's PENDING is a state, not a missing value ─────────────────────────
t('alert · 🔴 escalated with NO ops alert is 0183 PENDING — 「the roster was empty, arm ⓔ retries」, NOT 「we do not know」',
  handoffAlertNote('2026-09-22T10:00:00Z', null).includes('명부가 비어')
  && handoffAlertNote('2026-09-22T10:00:00Z', null).includes('다시 시도'),
  handoffAlertNote('2026-09-22T10:00:00Z', null));
t('alert · both delivered is a different sentence',
  handoffAlertNote('2026-09-22T10:00:00Z', '2026-09-22T10:00:05Z') !== handoffAlertNote('2026-09-22T10:00:00Z', null));
t('alert · never escalated is a third, distinct sentence',
  new Set([
    handoffAlertNote(null, null),
    handoffAlertNote('2026-09-22T10:00:00Z', null),
    handoffAlertNote('2026-09-22T10:00:00Z', '2026-09-22T10:00:05Z'),
  ]).size === 3);

// ── memoRefusal: the local restatement of the server's memo_required ─────────────────────────
t('memo · empty and whitespace-only are refused with the SERVER\'s own sentence',
  memoRefusal('') === MEMO_REQUIRED_KO && memoRefusal('   ') === MEMO_REQUIRED_KO
  && memoRefusal('\n\t ') === MEMO_REQUIRED_KO);
t('memo · a real memo passes', memoRefusal('보호자와 통화함') === null);
{
  // The copy is the EDGE's, byte for byte — read out of resolve_return.ts (comments stripped, per
  // the comment-matching law). A local restatement that worded it differently would be a second
  // product surface for one rule, chosen by whether the round trip happened.
  const fs = require('fs');
  const path = require('path');
  const src = fs.readFileSync(
    path.resolve(__dirname, '../../supabase/functions/transition-booking/resolve_return.ts'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  const m = src.match(/HttpError\(400, "(무엇을 확인했는지[^"]*)"\)/);
  t('the edge declares the memo_required sentence', !!m, 'no memo sentence in resolve_return.ts');
  t('🔴 the client\'s MEMO_REQUIRED_KO is the EDGE\'s sentence verbatim — one rule, one wording, whether or not the round trip happens',
    !!m && m[1] === MEMO_REQUIRED_KO, m ? `edge: ${m[1]} client: ${MEMO_REQUIRED_KO}` : '');
}

// ── resolveOutcomeLabel: three genuinely different outcomes ──────────────────────────────────
{
  const fresh = resolveOutcomeLabel({ resolved: true, settled: true, unchanged: false });
  const noSettle = resolveOutcomeLabel({ resolved: true, settled: false, unchanged: false });
  const again = resolveOutcomeLabel({ resolved: false, settled: true, unchanged: true });
  const nothing = resolveOutcomeLabel({ resolved: false, settled: false, unchanged: false });
  t('outcome · the four shapes are four distinct sentences', new Set([fresh, noSettle, again, nothing]).size === 4,
    JSON.stringify([fresh, noSettle, again, nothing]));
  t('outcome · `unchanged` wins over `settled` — a re-call on an already-resolved booking must not claim it just did the work',
    again.includes('이미') && !again.includes('마쳤어요'), again);
  t('outcome · resolved-without-settlement says the settlement is OUTSTANDING rather than implying success',
    noSettle.includes('정산은 아직'), noSettle);
  t('outcome · a server answer of nothing-happened is reported as such, never as success',
    nothing.includes('아무것도 바꾸지 않았어요'), nothing);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
