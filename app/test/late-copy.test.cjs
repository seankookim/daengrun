// late-copy.ts — tests run against the REAL compiled source (see run-late-copy-tests.sh),
// not a retyped copy.
//
// Why it must never be left red: this mapping is the language boundary at custody handoff.
// Before handoff, a booking may use no-show vocabulary; after handoff, the database refuses
// picked_up -> no_show because the dog is already with the runner. A screen must never describe
// a post-custody incident with a word the database rejects, or promise compensation that the
// stage-1 resolver cannot provide.
const { copyFor } = require('./late-copy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const MIN = 60_000;
const L = (overrides = {}) => ({
  late: true,
  sinceMs: 90 * MIN,
  custody: 'pre',
  waitingOn: 'runner',
  resumable: true,
  started: false,
  waitMs: 5 * MIN,
  ...overrides,
});
const eq = (actual, expected) => JSON.stringify(actual) === JSON.stringify(expected);
const strings = (copy) => Object.values(copy).filter((value) => typeof value === 'string');

// ───────────────────────────────────────────── exact copy for every meaningful branch
// These are observable return values, not a retyped implementation. They pin the component's
// existing words, line breaks, tones, interpolation, and optional strips across the extraction.
const exactCases = [
  {
    name: 'post-custody owner: collected but not started',
    late: L({ custody: 'post', started: false }), side: 'owner', names: { dog: '별이' },
    expected: { kick: '직접 확인해 주세요', head: '별이와의 러닝이\n아직 시작되지 않았어요', tone: 'warn',
      strip: '자동으로 정리되지 않아요 — 러너에게 연락해 주세요.' },
  },
  {
    name: 'post-custody runner: collected but not started',
    late: L({ custody: 'post', started: false }), side: 'runner', names: {},
    expected: { kick: '1시간 30분 지남', head: '아직 러닝을\n시작하지 않았어요', tone: 'warn' },
  },
  {
    name: 'post-custody owner: dog is out and overdue',
    late: L({ custody: 'post', started: true }), side: 'owner', names: {},
    expected: { kick: '직접 확인해 주세요', head: '반려견가 아직\n돌아오지 않았어요', tone: 'critical',
      strip: '자동으로 확인되지 않아요 — 러너에게 연락하거나 긴급 도움을 요청하세요.' },
  },
  {
    name: 'post-custody runner: run is overdue',
    late: L({ custody: 'post', started: true }), side: 'runner', names: {},
    expected: { kick: '예상보다 1시간 30분 초과', head: '러닝이\n길어지고 있어요', tone: 'warn',
      strip: '보호자 화면에도 같은 사실이 보여요. 문제가 있으면 직접 알려주세요.' },
  },
  {
    name: 'pre-custody owner: runner waits at the door',
    late: L({ waitingOn: 'owner' }), side: 'owner', names: { runner: '민수' },
    expected: { kick: '지금 기다리는 중', head: '민수님이\n문 앞에서 기다려요', tone: 'critical',
      strip: '지금 취소하면 취소 수수료가 붙어요 — 일정에서 조건을 확인하세요.' },
  },
  {
    name: 'pre-custody runner: owner has not come out',
    late: L({ waitingOn: 'owner' }), side: 'runner', names: {},
    expected: { kick: '5분째 대기 중', head: '보호자가 아직\n나오지 않았어요', tone: 'warn',
      strip: '떠나기 전에 한 번 더 알려주세요.' },
  },
  {
    name: 'pre-custody owner: runner has not arrived',
    late: L({ waitingOn: 'runner' }), side: 'owner', names: {},
    expected: { kick: '예약 시각이 지났어요', head: '러너가 아직\n도착하지 않았어요', tone: 'warn' },
  },
  {
    name: 'pre-custody runner: dog is waiting',
    late: L({ waitingOn: 'runner' }), side: 'runner', names: { dog: '별이' },
    expected: { kick: '1시간 30분 늦음', head: '별이가\n기다리고 있어요', tone: 'critical' },
  },
];
for (const c of exactCases) {
  const actual = copyFor(c.late, c.side, c.names);
  t(c.name, eq(actual, c.expected), JSON.stringify(actual));
}

// ───────────────────────────────────────────── the handoff vocabulary law (0066:50)
// Enumerate the FULL required post-custody space. waitingOn is normally runner after handoff,
// but copy must stay lawful even if an upstream embed hands it the other value.
for (const side of ['owner', 'runner']) {
  for (const started of [true, false]) {
    for (const waitingOn of ['runner', 'owner']) {
      const copy = copyFor(L({ custody: 'post', started, waitingOn }), side, {});
      const hasForbiddenWord = strings(copy).some((value) => value.includes('불발'));
      t(`post custody never says 불발: side=${side}, started=${started}, waitingOn=${waitingOn}`,
        hasForbiddenWord === false, JSON.stringify(copy));
    }
  }
}

// ───────────────────────────────────────────── picked_up and active are different facts
{
  const collected = copyFor(L({ custody: 'post', started: false }), 'owner', { dog: '별이' });
  const overdue = copyFor(L({ custody: 'post', started: true }), 'owner', { dog: '별이' });
  t('post-custody owner distinguishes collected/not-started from dog-out/overdue',
    collected.head === '별이와의 러닝이\n아직 시작되지 않았어요'
      && overdue.head === '별이가 아직\n돌아오지 않았어요'
      && collected.head !== overdue.head,
    JSON.stringify({ collected, overdue }));
}

// ───────────────────────────────────────────── actual door wait is not schedule lateness
{
  const copy = copyFor(L({ custody: 'pre', waitingOn: 'owner', sinceMs: 90 * MIN, waitMs: 5 * MIN }),
    'runner', {});
  t('runner-side wait duration uses waitMs, not sinceMs',
    copy.kick === '5분째 대기 중' && !copy.kick.includes('1시간 30분'), JSON.stringify(copy));
}

// ───────────────────────────────────────────── stage 1 never promises compensation
// Exercise the full structural input space, including combinations lateness.ts does not normally
// emit. That keeps a future branch from smuggling a promise into a previously unreachable strip.
for (const custody of ['pre', 'post']) {
  for (const side of ['owner', 'runner']) {
    for (const started of [true, false]) {
      for (const waitingOn of ['runner', 'owner']) {
        const copy = copyFor(L({ custody, started, waitingOn }), side, {});
        t(`strip never promises 보상: custody=${custody}, side=${side}, started=${started}, waitingOn=${waitingOn}`,
          !(copy.strip ?? '').includes('보상'), JSON.stringify(copy));
      }
    }
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
