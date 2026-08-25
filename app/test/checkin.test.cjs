// 0117 지각 체크인 핀 — 판정은 src/lib/checkin.ts, 문장은 src/lib/checkin-copy.ts.
// 테스트는 **컴파일된 실소스**에 대고 돈다 (run-checkin-tests.sh), 다시 타이핑한 사본이 아니다.
//
// 이 스위트가 절대 붉어진 채로 남으면 안 되는 이유는 세 가지고, 전부 사람에 관한 것이다:
//  1. 사유 텍스트는 **본인만** 읽는다 (ruling 4B). 최악의 순간에 적힌 문장이 두 개의 불변 테이블에
//     들어가고 계정 삭제보다 오래 남는다 — 한 번 새면 되돌릴 방법이 없다.
//  2. 천장을 넘긴 예약에는 '진행' 문이 없어야 한다 (FM4). 없던 시절 탭 두 번이 16일 된 예약을
//     되살렸다.
//  3. 답하지 않는 것은 과실이 아니다 (D5). 답을 압박하는 문장 하나면 「답은 선택」이 거짓이 된다.
const {
  parseCheckin, affordancesFor, remainMs, checkinTokenFrom, checkinPossible,
  myReasonOf, theirHasReason,
} = require('./checkin.build.cjs');
const {
  checkinCopy, checkinCopyStrings, recordedCopy, recordedCopyStrings, stopReasonsFor,
  reasonTextFor, refusalFor, checkinRefusalFrom, remainLabel, TRIAGE, REASON_STEP, noteStepFor,
} = require('./checkin-copy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const throws = (fn) => { try { fn(); return false; } catch { return true; } };
// 파서가 **터지면 안 되는** 자리를 검사할 때 쓴다. 그냥 부르면 회귀가 스위트를 크래시시켜
// 이름 없는 스택 트레이스로 끝나는데, 무엇이 깨졌는지 말해주는 FAIL 한 줄이 훨씬 낫다.
const val = (fn) => { try { return fn(); } catch (e) { return { threw: String((e && e.message) || e) }; } };

const NOW = '2026-08-25T04:00:00.000Z';
const DEADLINE = '2026-08-25T05:00:00.000Z';

/** §7 이 실제로 내보내는 모양. 오버라이드는 **키 삭제**까지 표현할 수 있어야 한다 (4B 의 핵심이
 *  '키 부재'이므로) — undefined 를 넘기면 지운다. */
const payload = (o = {}) => {
  const base = {
    open: true,
    opened_at: '2026-08-25T03:30:00.000Z',
    deadline_at: DEADLINE,
    owner_answer: null, owner_at: null, owner_has_reason: false,
    runner_answer: null, runner_at: null, runner_has_reason: false,
    resolved_at: null, resolution: null, version: 0,
    past_ceiling: false, custody: 'pre', server_now: NOW,
  };
  const out = { ...base, ...o };
  for (const k of Object.keys(out)) if (out[k] === undefined) delete out[k];
  return out;
};
const noRow = (o = {}) => ({ open: false, past_ceiling: false, custody: 'pre', server_now: NOW, ...o });

// ═══════════════════════════════════════════════════ 1. parseCheckin — 관대한 파싱 금지
t('행 없는 예약은 row=null 로 파싱된다 (시계가 건드린 적 없는 정상 상태)',
  parseCheckin(noRow()).row === null && parseCheckin(noRow()).open === false);
t('행 없는 payload 가 open:true 라고 주장하면 거부한다 — 모순은 그릴 상태가 아니다',
  throws(() => parseCheckin({ ...noRow(), open: true })));
t('정상 행이 파싱된다', parseCheckin(payload()).row.deadlineAt === DEADLINE);

// ⚠ 이 핀 하나가 「성공했는데 터진다」를 막는다: answer_checkin 은 리졸버가 no_show 를 쓴 **뒤에**
// fetch_checkin 을 돌려주므로, 성공한 「진행할 수 없어요」의 응답 custody 는 'out' 이다.
t("custody 'out' 을 받아들인다 — 성공 응답이 실제로 그 값을 들고 온다",
  val(() => parseCheckin(payload({ custody: 'out', open: false, resolved_at: NOW, resolution: 'cannot_proceed' })))
    .custody === 'out');
t('custody 가 세 값 밖이면 거부', throws(() => parseCheckin(payload({ custody: 'unknown' }))));

for (const [k, bad] of [
  ['open', 'yes'], ['past_ceiling', null], ['server_now', 12345],
  ['opened_at', 5], ['deadline_at', null], ['version', '0'],
  ['owner_has_reason', null], ['runner_has_reason', 'false'],
  ['owner_answer', 'maybe'], ['resolution', 7],
]) {
  t(`${k} 의 모양이 다르면 실패다 (기본값으로 둔갑시키지 않는다)`, throws(() => parseCheckin(payload({ [k]: bad }))));
}
// past_ceiling 이 **없으면** 특히 위험하다: `?? false` 였다면 천장을 넘긴 예약에 진행 버튼이 돌아온다.
t('past_ceiling 키가 없으면 실패다 — 없는 값을 false 로 읽으면 FM4 가 되살아난다',
  throws(() => parseCheckin(payload({ past_ceiling: undefined }))));
t('answer 와 서버 소인은 함께 온다 (테이블 제약의 거울) — 한쪽만 오면 거부',
  throws(() => parseCheckin(payload({ owner_answer: 'proceeding', owner_at: null }))));
t('open 은 resolved_at is null 의 거울 — 어긋나면 두 반쪽이 다른 행을 말하는 것이다',
  throws(() => parseCheckin(payload({ open: true, resolved_at: NOW, resolution: 'void' }))));
t('객체가 아니면 거부', throws(() => parseCheckin(null)) && throws(() => parseCheckin([])) && throws(() => parseCheckin('x')));

// ── 4B: 상대방 사유 키는 **부재**다 (null 이 아니다) ─────────────────────────────────────
{
  // 보호자가 읽은 응답: 자기 키만 있다.
  const asOwner = parseCheckin(payload({
    owner_answer: 'cannot_proceed', owner_at: NOW, owner_has_reason: true, owner_reason: '문 앞에 아무도 없었어요',
    runner_answer: 'proceeding', runner_at: NOW, runner_has_reason: true,
  }));
  t('내 사유 키는 값 그대로 실린다', asOwner.row.ownerReason === '문 앞에 아무도 없었어요');
  t("상대 사유 키는 **없다** — null 로 만들어내지 않는다 ('없다'와 '내 것이 아니다'는 다른 사실)",
    !('runnerReason' in asOwner.row));
  t('상대가 사유를 남겼다는 사실은 불리언으로 온다', asOwner.row.runnerHasReason === true);
  t('내 사유가 null 이어도 키는 남는다 (사유 안 남김 ≠ 못 읽음)',
    'ownerReason' in parseCheckin(payload({ owner_answer: 'cannot_proceed', owner_at: NOW, owner_reason: null })).row);
  t('사유 값이 문자열도 null 도 아니면 거부',
    throws(() => parseCheckin(payload({ owner_reason: 42, owner_answer: 'cannot_proceed', owner_at: NOW }))));
  t('myReasonOf 는 상대 쪽을 물으면 null 을 준다 — undefined 가 화면으로 새지 않는다',
    myReasonOf(asOwner.row, 'runner') === null && theirHasReason(asOwner.row, 'owner') === true);
}

// ═══════════════════════════════════════════ 2. affordancesFor — 서버가 거부하기 전에 사라진다
const st = (o = {}) => parseCheckin(payload(o));

t('평상시엔 세 답이 다 있다',
  affordancesFor(st(), 'runner', 'confirmed').join(',') === 'proceeding,other_side_absent,cannot_proceed');

// 🔴 핵심 핀 — §6 checkin_past_ceiling.
t('천장을 넘기면 진행 문이 사라진다 (§6 이 거부하기 전에)',
  !affordancesFor(st({ past_ceiling: true }), 'runner', 'confirmed').includes('proceeding'));
t('천장을 넘겨도 종점 쪽 답은 남는다 — 아무 말도 못 하게 가두지 않는다',
  affordancesFor(st({ past_ceiling: true }), 'runner', 'confirmed').join(',') === 'other_side_absent,cannot_proceed');

t('이미 답했으면 버튼이 없다 (per-side immutable — 두 번째 버튼은 죽은 버튼이다)',
  affordancesFor(st({ runner_answer: 'proceeding', runner_at: NOW }), 'runner', 'confirmed').length === 0);
t('내가 답했어도 상대는 아직 답할 수 있다',
  affordancesFor(st({ runner_answer: 'proceeding', runner_at: NOW }), 'owner', 'confirmed').length === 3);
t('해소된 체크인엔 버튼이 없다',
  affordancesFor(st({ open: false, resolved_at: NOW, resolution: 'void' }), 'runner', 'confirmed').length === 0);
t("custody 'out' 이면 버튼이 없다 — 서버가 not_late_eligible 로 전부 거부한다",
  affordancesFor(st({ custody: 'out' }), 'runner', 'cancelled_owner').length === 0);

// §6 use_cancel_path — 러너 보상을 조용히 0 으로 만드는 문을 미리 닫는다.
t('보호자 · runner_enroute · 인계 전 → 「진행할 수 없어요」가 없다 (use_cancel_path)',
  !affordancesFor(st(), 'owner', 'runner_enroute').includes('cannot_proceed'));
t('같은 상황의 **러너**는 그대로 말할 수 있다 — 자기가 물러서는 것은 남의 돈을 가져가지 않는다',
  affordancesFor(st(), 'runner', 'runner_enroute').includes('cannot_proceed'));
t('보호자라도 confirmed 면 말할 수 있다 (러너가 아직 출발 전 — 보상할 것이 없다)',
  affordancesFor(st(), 'owner', 'confirmed').includes('cannot_proceed'));
t('보호자라도 인계 후면 말할 수 있다 (서버 스코프와 동일 — 취소 문은 그때 거부한다)',
  affordancesFor(st({ custody: 'post' }), 'owner', 'runner_enroute').includes('cannot_proceed'));

t('checkinPossible 은 프로토콜의 네 상태만 참',
  ['confirmed', 'runner_enroute', 'picked_up', 'active'].every((s) => checkinPossible(s))
  && !checkinPossible('no_show') && !checkinPossible('completed') && !checkinPossible(null));

// ═══════════════════════════════════════════════ 3. 시계 — 원점은 서버, 폰은 스톱워치
{
  const row = st().row;
  // 인자: (row, server_now, 그 읽기의 **로컬** 시각, 지금). 달력은 앞의 두 개에서만 나온다.
  const FETCHED = 1_000_000;
  t('남은 시간은 deadline − server_now 에서 시작한다', remainMs(row, NOW, FETCHED, FETCHED) === 3600_000);
  t('폰은 경과만 잰다 (10분 지나면 10분 준다)', remainMs(row, NOW, FETCHED, FETCHED + 600_000) === 3000_000);
  t('음수 경과는 무시된다 — 뒤로 가는 폰 시계가 마감을 늘리지 못한다',
    remainMs(row, NOW, FETCHED, FETCHED - 600_000) === 3600_000);
  // 🔴 폰 시계가 몇 시간 틀려도 마감은 제자리다 — 원점이 서버이기 때문이다 (FM2/FM6).
  t('폰 시계가 6시간 틀려도 남은 시간은 그대로다',
    remainMs(row, NOW, FETCHED + 6 * 3600_000, FETCHED + 6 * 3600_000) === 3600_000);
  t('시각을 못 읽으면 null — 지어낸 카운트다운을 그리지 않는다', remainMs(row, 'not-a-date', FETCHED, FETCHED) === null);
}
t('remainLabel 은 0 을 인쇄하지 않는다', remainLabel(30_000) === '1분 미만' && remainLabel(0) === '마감 시각이 지났어요');
t('remainLabel 문법', remainLabel(45 * 60_000) === '45분' && remainLabel(90 * 60_000) === '1시간 30분' && remainLabel(2 * 3600_000) === '2시간');

// ═══════════════════════════════════════════ 4. 사유 목록 — ③ + ③-A, ③-C 에서 빌린 하나
{
  const runner = stopReasonsFor('runner');
  const owner = stopReasonsFor('owner');
  const keys = (l) => l.map((r) => r.key).join(',');
  const labels = (l) => l.map((r) => r.label);

  t('러너 목록은 런엔드 enum 세 개를 그대로 이어받는다 (③-A: 새 어휘를 만들지 않는다)',
    ['dog_condition', 'owner_request', 'runner_personal'].every((k) => keys(runner).includes(k)));
  t('③-C 에서 빌린 하나가 양쪽에 있다 — 체크인에만 있는 진짜 사유',
    labels(runner).includes('상대방과 연락이 안 돼요') && labels(owner).includes('상대방과 연락이 안 돼요'));
  // 🔴 재작성 핀 — 계획 §8-bis: 「보호자 요청」은 체크인 맥락에서 '연락이 안 됨'과 구별되지 않는다.
  t('「보호자 요청」 원문은 어디에도 남아 있지 않다 (한 줄 재작성이 실제로 일어났다)',
    ![...labels(runner), ...labels(owner)].includes('보호자 요청'));
  t('재작성된 문장은 요청이 **있었다**는 사실을 말한다',
    labels(runner).includes('보호자가 중단을 요청했어요'));
  t('아이 컨디션만 노트를 요구한다 — 탭 수는 사유마다 다르다 (서버가 증거를 요구하는 그 자리)',
    runner.find((r) => r.key === 'dog_condition').needsNote === true
    && runner.find((r) => r.key === 'runner_personal').needsNote === false
    && runner.find((r) => r.key === 'peer_unreachable').needsNote === false);
  t('보호자 목록에 「러너 개인 사정」이 없다 — 남의 사정은 사유가 아니라 다른 답이다',
    !keys(owner).includes('runner_personal'));
  t('보호자의 자기 사정 문장은 1인칭이다', labels(owner).includes('제 사정이 생겼어요'));
  t('직접 입력은 양쪽 목록의 마지막이다',
    runner[runner.length - 1].key === 'other' && owner[owner.length - 1].key === 'other');
}

// reasonTextFor — 실제로 p_reason 에 실려 가는 문자열
t('노트 없는 사유는 라벨 그대로 저장된다 (사람이 고른 말)',
  reasonTextFor('runner', 'runner_personal') === '러너 개인 사정');
t('직접 입력은 사람의 문장이 곧 사유다 — 앞에 우리 말을 붙이지 않는다',
  reasonTextFor('runner', 'other', '문 앞에서 20분 기다렸어요') === '문 앞에서 20분 기다렸어요');
t('컨디션 사유는 라벨과 관찰을 함께 싣는다',
  reasonTextFor('runner', 'dog_condition', '헐떡임이 심해요') === '아이 컨디션이 걱정돼요 · 헐떡임이 심해요');
t('노트가 필요한 사유는 빈 노트로 보내지 않는다 (null → 호출부가 제출을 막는다)',
  reasonTextFor('runner', 'dog_condition', '   ') === null && reasonTextFor('runner', 'other', '') === null);
t('그 쪽 목록에 없는 사유는 null — 보호자에게 러너 사정을 실어 보내지 못한다',
  reasonTextFor('owner', 'runner_personal') === null);

// ═══════════════════════════════════════════════ 5. 문장 — 무엇을 말하고 무엇을 절대 말하지 않는가
const copyOf = (side, rawStatus, o = {}, remaining = 3600_000) => checkinCopy(st(o), side, rawStatus, remaining);

t('행이 없으면 문장도 없다 (이 표면은 답을 받는 표면이다)',
  checkinCopy(parseCheckin(noRow()), 'owner', 'confirmed', null) === null);
t('해소된 체크인엔 문장이 없다',
  copyOf('owner', 'confirmed', { open: false, resolved_at: NOW, resolution: 'void' }) === null);

// 🔴 4B — 상대의 사유 텍스트는 **어떤 문장에도** 없다. 애초에 이 함수에 인자로 들어오지도 않는다.
{
  const LEAK = '초코가 다리를 절어요 · 현관 비밀번호는 0412';
  const s = parseCheckin(payload({
    runner_answer: 'cannot_proceed', runner_at: NOW, runner_has_reason: true,
    owner_answer: null, owner_at: null,
  }));
  // 서버가 절대 보내지 않는 모양이지만, 방어적으로 심어본다: 그래도 새면 안 된다.
  s.row.runnerReason = LEAK;
  const c = checkinCopy(s, 'owner', 'confirmed', 3600_000);
  const blob = checkinCopyStrings(c).join('\n');
  t('보호자 화면 어디에도 러너의 사유 텍스트가 없다 (4B)', !blob.includes(LEAK) && !blob.includes('0412'));
  t('대신 「남겼다」는 사실만 말한다', c.theirsReason && c.theirsReason.includes('사유를 남겼어요'));
  t('그리고 내용은 본인만 본다고 분명히 말한다', c.theirsReason.includes('본인만'));
  const rec = recordedCopy(s, 'runner');
  t('러너 본인은 자기 사유를 되돌려 받는다', rec && rec.reason === LEAK);
  const recOwner = recordedCopy(s, 'owner');
  t('보호자의 확인 블록에는 러너 사유가 없다', recOwner === null);
}

// 내 사유 메아리 + 「안 남겼다」의 정직한 표기
{
  const answered = parseCheckin(payload({
    owner_answer: 'cannot_proceed', owner_at: NOW, owner_has_reason: true, owner_reason: '제 사정이 생겼어요',
  }));
  const c = checkinCopy(answered, 'owner', 'confirmed', 3600_000);
  t('내 답과 내 사유가 그대로 되돌아온다', c.mine.line === '진행할 수 없다고 답했어요' && c.mine.reason === '제 사정이 생겼어요');
  t('답은 바꿀 수 없다는 사실을 말한다', c.mine.immutable.includes('바꿀 수 없'));
  t('답한 뒤에는 버튼이 없다', c.options.length === 0);

  const noReason = parseCheckin(payload({ owner_answer: 'cannot_proceed', owner_at: NOW, owner_reason: null }));
  const c2 = checkinCopy(noReason, 'owner', 'confirmed', 3600_000);
  t('사유를 안 남겼으면 안 남겼다고만 적는다 (불리한 함의 금지)', c2.mine.reason === '사유는 남기지 않았어요');
}

// 거울 문장 — 상대가 지목한 것은 나다
t('상대가 「상대방이 안 나왔다」고 답하면, 그 상대가 나라는 사실을 감추지 않는다',
  copyOf('owner', 'confirmed', { runner_answer: 'other_side_absent', runner_at: NOW }).theirs === '러너는 보호자가 나오지 않았다고 답했어요'
  && copyOf('runner', 'confirmed', { owner_answer: 'other_side_absent', owner_at: NOW }).theirs === '보호자는 러너가 오지 않았다고 답했어요');

// 천장 — 주어는 '답'이지 '예약'이 아니다 (late-copy F3a 가 산 교훈)
{
  const c = copyOf('runner', 'confirmed', { past_ceiling: true });
  t('천장 화면에 진행 버튼이 없다', !c.options.some((o) => o.key === 'proceeding'));
  t('천장 문장은 **답**에 대해 말한다', c.sub.includes('답'));
  const blob = checkinCopyStrings(c).join('\n');
  t('예약 자체가 불가능하다고 단언하지 않는다 — 서버는 러닝 시작을 막지 않는다',
    !/예약은 진행할 수 없|시작할 수 없|진행되지 않았어요/.test(blob), blob);
}

// D5 — 침묵은 과실이 아니고 요금도 아니다. 그리고 압박 문구가 없다.
{
  const combos = [];
  for (const side of ['owner', 'runner']) {
    for (const rawStatus of ['confirmed', 'runner_enroute', 'picked_up', 'active']) {
      for (const custody of ['pre', 'post']) {
        for (const past of [false, true]) {
          const c = copyOf(side, rawStatus, { custody, past_ceiling: past });
          if (c) combos.push([`${side}/${rawStatus}/${custody}/ceiling=${past}`, c]);
        }
      }
    }
  }
  t('모든 조합에서 문장이 나온다 (열린 체크인은 언제나 말할 것이 있다)', combos.length === 32, String(combos.length));
  for (const [name, c] of combos) {
    t(`${name}: 침묵 불변식 스트립이 빠지지 않는다`,
      c.strip.includes('과실로 기록되지 않고') && c.strip.includes('수수료도 청구되지 않아요'));
    const blob = checkinCopyStrings(c).join('\n');
    t(`${name}: 답을 강요하는 말이 없다`, !/필수|반드시|불이익|의무적/.test(blob), blob);
    t(`${name}: 운영팀을 만들어내지 않는다`, !/운영팀|고객센터|상담원/.test(blob));
    t(`${name}: 14pt 아래로 갈 문장이 비어 있지 않다`, blob.trim().length > 0);
  }
}

// 인계 후에는 마감이 무엇을 하는지 약속하지 않는다 (active → superseded: 아무 일도 안 일어난다)
t('인계 전에는 마감 결과를 말한다', copyOf('owner', 'confirmed', { custody: 'pre' }).terminalNote !== null);
t('인계 후에는 마감 결과를 말하지 않는다 — active 는 마감이 아무것도 바꾸지 않는다',
  copyOf('owner', 'picked_up', { custody: 'post' }).terminalNote === null);

// use_cancel_path 안내는 문장이지 두 번째 출구가 아니다
{
  const c = copyOf('owner', 'runner_enroute', { custody: 'pre' });
  t('보호자에게 취소 문을 이름으로 알려준다', c.cancelNote && c.cancelNote.includes('예약 취소'));
  t('그 이유(러너 보상)를 함께 말한다 — 조용한 러너 급여 삭감을 만들지 않는다', c.cancelNote.includes('러너 보상'));
  t('러너 화면에는 그 안내가 없다', copyOf('runner', 'runner_enroute', { custody: 'pre' }).cancelNote === null);
  t('이미 답했으면 안내도 사라진다',
    copyOf('owner', 'runner_enroute', { custody: 'pre', owner_answer: 'proceeding', owner_at: NOW }).cancelNote === null);
}

// 마감 라벨은 남은 시간을 모를 때 그리지 않는다
t('남은 시간을 모르면 카운트다운 줄이 없다', copyOf('runner', 'confirmed', {}, null).sub === null);

// ═══════════════════════════════════════════ 6. ③ 1단계 — 도움과 사유 사이에 게이트가 없다
t('119 문구는 다이얼러가 열린다는 사실만 말한다 (앱은 신고하지 않는다)',
  TRIAGE.callSub.includes('전화 앱') && /신고하지/.test(TRIAGE.callSub));
t('SOS 문구는 sendSOS 가 실제로 하는 것만 말한다 — 알림 하나',
  TRIAGE.sosSub.includes('알림 하나') && !/운영팀|접수|출동/.test(TRIAGE.sosSub));
t('SOS 실패는 실패로 말한다', TRIAGE.sosFailed.includes('보내지 못했어요'));
t('건너뛰기 문구가 「지금은」이라고 말하지 않는다 — 사유는 진술과 함께 불변이다',
  !TRIAGE.skip.includes('지금은') && TRIAGE.skip === '사유 없이 중단 알리기');
t('SOS 를 보낸 뒤의 라벨은 「아니요」가 아니다', TRIAGE.nextAfterSos !== TRIAGE.next && !TRIAGE.nextAfterSos.includes('아니요'));
t('노트 단계 문장은 런엔드와 같은 질문을 쓴다', noteStepFor('dog_condition').head === '무엇을 보고 멈췄나요?');
t('직접 입력 단계는 관찰이 아니라 이유를 묻는다', noteStepFor('other').head === '어떤 이유인가요?');
t('사유 단계 키커는 랩 프레임 그대로', REASON_STEP.kicker === '중단 사유' && REASON_STEP.noteMark === '· 내용 필요');

// ═══════════════════════════════════════════════════ 7. 일곱 거부 토큰 = 일곱 화면 상태
const TOKENS = ['checkin_not_open', 'checkin_resolved', 'answer_immutable', 'checkin_past_ceiling',
  'not_late_eligible', 'reason_not_applicable', 'use_cancel_path'];
for (const tok of TOKENS) {
  const r = refusalFor(tok);
  t(`${tok} 은 제목과 본문을 갖는다 (에러 덤프 금지)`, !!r.title && !!r.body && r.token === tok);
  t(`${tok} 문장에 서버 토큰 문자열이 새지 않는다`, !r.title.includes('_') && !r.body.includes('_'));
}
t('토큰이 그대로 온 실패를 인식한다', checkinRefusalFrom({ message: 'answer_immutable' })?.token === 'answer_immutable');
t('긴 PG 메시지 안에 실려 온 토큰도 인식한다 (=== 매칭이었으면 놓쳤다)',
  checkinRefusalFrom({ message: 'ERROR: checkin_past_ceiling CONTEXT: PL/pgSQL function answer_checkin' })?.token === 'checkin_past_ceiling');
t('모르는 실패는 null — 호출부의 기존 실패 경로가 산다', checkinRefusalFrom({ message: 'network down' }) === null);
t('null/undefined/비문자열에 터지지 않는다',
  checkinRefusalFrom(null) === null && checkinRefusalFrom(undefined) === null && checkinRefusalFrom({ message: 7 }) === null);
t('토큰 추출은 문장 없이도 동작한다 (판정과 문장이 갈려 있다)', checkinTokenFrom({ message: 'use_cancel_path' }) === 'use_cancel_path');
t('천장 거부의 주어는 답이다 — 예약이 진행 불가라고 말하지 않는다',
  refusalFor('checkin_past_ceiling').title.includes('답') && !/예약은 진행할 수 없/.test(refusalFor('checkin_past_ceiling').body));
t('천장 거부는 남아 있는 문을 알려준다 (막다른 길 금지)', refusalFor('checkin_past_ceiling').body.includes('보낼 수 있어요'));
t('use_cancel_path 는 문 이름을 대고 이유를 말한다',
  refusalFor('use_cancel_path').body.includes('러너 보상') && refusalFor('use_cancel_path').title.includes('예약 취소'));
t('checkin_resolved 는 답이 기록되지 않았다고 분명히 말한다 (삼킨 척 금지)',
  refusalFor('checkin_resolved').body.includes('기록되지 않았어요'));

// ═══════════════════════════════════════════════ 8. 답 직후 확인 블록 — 성공이 사라짐처럼 보이지 않게
{
  const resolved = parseCheckin(payload({
    open: false, custody: 'out', resolved_at: NOW, resolution: 'cannot_proceed',
    runner_answer: 'cannot_proceed', runner_at: NOW, runner_has_reason: true, runner_reason: '러너 개인 사정',
  }));
  const rec = recordedCopy(resolved, 'runner');
  t('해소된 뒤에도 내 답을 확인해준다', rec.line === '진행할 수 없다고 답했어요' && rec.reason === '러너 개인 사정');
  t('인계 전 cannot_proceed 의 결과는 불발 + 무수수료 (서버 알림과 같은 사실)',
    recordedCopy(parseCheckin(payload({
      open: false, custody: 'pre', resolved_at: NOW, resolution: 'cannot_proceed',
      runner_answer: 'cannot_proceed', runner_at: NOW,
    })), 'runner').note.includes('불발'));
  t('인계 후 cannot_proceed 는 불발이라 부르지 않는다 (0066:50 이 거부하는 낱말)',
    !recordedCopy(parseCheckin(payload({
      open: false, custody: 'post', resolved_at: NOW, resolution: 'cannot_proceed',
      runner_answer: 'cannot_proceed', runner_at: NOW,
    })), 'runner').note.includes('불발'));
  t('superseded 는 상태를 바꾸지 않았다고 말한다',
    recordedCopy(parseCheckin(payload({
      open: false, custody: 'post', resolved_at: NOW, resolution: 'superseded',
      runner_answer: 'proceeding', runner_at: NOW,
    })), 'runner').note.includes('바꾸지 않았어요'));
  t('아직 해소 전이면 상대를 기다린다고 말한다',
    recordedCopy(parseCheckin(payload({ runner_answer: 'proceeding', runner_at: NOW })), 'runner').note.includes('기다리는 중'));
  t('답하지 않은 쪽에는 확인 블록이 없다', recordedCopy(parseCheckin(payload()), 'owner') === null);
  const blob = recordedCopyStrings(rec).join('\n');
  t('확인 블록에도 압박·거짓 약속이 없다', !/필수|반드시|운영팀|접수/.test(blob));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
