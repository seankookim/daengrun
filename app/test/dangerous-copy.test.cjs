// 0119 맹견 게이트 문장 핀. 판정은 서버, 문장은 src/lib/dangerous-copy.ts — 여기서 그 문장이
// 무엇을 말하고 무엇을 절대 말하지 않는지를 고정한다.
const { dangerousRefusalFrom, refusalFor } = require('./dangerous-copy.build.cjs');

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('PASS ' + m); } else { fail++; console.log('FAIL ' + m); } };
const TOKENS = ['dog_dangerous_undeclared', 'dog_dangerous_custody_refused', 'dog_dangerous_breed_conflict'];

// ── 매칭: 두 도착 경로를 다 받는다 ──────────────────────────────────────────────
// create-booking-hold 는 토큰을 그대로 던지고(409), 인계 방향 전이는 더 긴 문장 안에 실어 온다.
ok(dangerousRefusalFrom({ message: 'dog_dangerous_undeclared' })?.token === 'dog_dangerous_undeclared',
  '토큰 그대로 온 409 를 인식한다 (create-booking-hold 경로)');
ok(dangerousRefusalFrom({ message: 'new row violates ... dog_dangerous_custody_refused ... CONTEXT: PL/pgSQL' })?.token === 'dog_dangerous_custody_refused',
  '긴 PG 메시지 안에 실려 온 토큰을 인식한다 (전이 경로) — === 매칭이었으면 놓쳤다');
ok(dangerousRefusalFrom({ message: 'boom' }) === null, '관계없는 실패는 null — 호출부의 기존 실패 경로가 산다');
ok(dangerousRefusalFrom(null) === null && dangerousRefusalFrom(undefined) === null, 'null/undefined 에 터지지 않는다');
ok(dangerousRefusalFrom({}) === null && dangerousRefusalFrom({ message: 7 }) === null, 'message 가 없거나 문자열이 아니면 null');

// ── 세 토큰 전부 문장을 갖는다 ────────────────────────────────────────────────
for (const t of TOKENS) {
  const r = refusalFor(t);
  ok(!!r.title && !!r.body, t + ' 는 제목과 본문을 갖는다 (빈 알럿 금지)');
  ok(r.token === t, t + ' 는 자기 토큰을 되돌려준다');
}

// ── 🔴 절대 하지 않는 말: 조건부 허용의 암시 ────────────────────────────────────
// 입마개·맹견사육허가·책임보험은 확인할 수단이 이 제품에 없다. 확인자 없는 조건을 문장으로 말하면
// 사용자는 「서류를 내면 된다」고 읽고, 그건 우리가 지킬 수 없는 약속이다.
const BANNED = ['허가', '입마개', '보험', '증명서', '서류', '신청서'];
for (const side of ['owner', 'runner']) {
  for (const t of TOKENS) {
    const blob = JSON.stringify(refusalFor(t, side));
    const hit = BANNED.filter((w) => blob.includes(w));
    ok(hit.length === 0, `${side}/${t} 에 조건부 허용 암시어 없음${hit.length ? ' — ' + hit.join(',') : ''}`);
  }
}

// ── 미신고는 거절이 아니라 요청이다 ───────────────────────────────────────────
const und = refusalFor('dog_dangerous_undeclared');
ok(und.action && und.action.route === '/owner/dog', '미신고에는 답하러 가는 문이 있다 (막다른 길 금지)');
ok(!/할 수 없|불가/.test(und.title), '미신고 제목은 불가능을 단언하지 않는다 — 아직 묻지 않았을 뿐이다');

// ── 맹견 신고는 되돌릴 문이 없으므로 가짜 버튼도 없다 ─────────────────────────
const ref = refusalFor('dog_dangerous_custody_refused');
ok(ref.action === null, '맹견 확정 거절에는 행동 버튼이 없다 (죽은 버튼 금지)');
ok(ref.body.includes('클럽'), '대신 실제로 열려 있는 문(클럽 동반 참여)을 말한다');

// ── 러너에게는 보호자용 지시를 주지 않는다 ───────────────────────────────────
for (const t of TOKENS) {
  const r = refusalFor(t, 'runner');
  ok(r.action === null, `러너 ${t} 에는 행동 버튼이 없다 — 남의 반려견 프로필을 고칠 수 없다`);
  // ⚠ 이 핀은 처음에 '프로필에서 답' 문자열 자체를 금지했다가, 옳은 문장을 붉게 만들어서
  // 고쳤다. 「보호자가 프로필에서 답하면 다시 요청이 올 수 있어요」는 러너에게 내리는 지시가
  // 아니라 **무슨 일이 일어나는지에 대한 설명**이고, 러너에게 그건 알 가치가 있는 사실이다.
  // 잡아야 하는 건 읽는 사람에게 시키는 명령형이다 — 러너는 그 일을 할 수 없다.
  // (문자열 금지가 아니라 명령형 금지: 핀이 겨냥해야 하는 명제는 후자였다.)
  ok(!/프로필에서 (답해|확인해)|프로필을 확인해/.test(r.body), `러너 ${t} 에 읽는 사람을 향한 명령형이 없다`);
}

// ── 러너 문장은 **두 자리**에서 참이어야 한다 ────────────────────────────────
// 같은 문장이 요청 수락(F1 배정/수락 팔)과 인계 확인 탭(같은 트리거가 인계 도장을 막는다)에서
// 쓰인다. 첫 판은 「이 요청은 목록에서 사라집니다」였는데 그건 수락 화면에서만 참이고, 문 앞에서
// 인계 확인을 누른 러너에게는 거짓이다. 한 자리에서만 참인 문장은 다른 자리에서 거짓말이 된다.
for (const t of TOKENS) {
  const b = refusalFor(t, 'runner').body;
  ok(!/목록|리스트/.test(b), `러너 ${t} 는 목록에 무슨 일이 생기는지 단언하지 않는다 (인계 자리에선 거짓)`);
  ok(!/다시 시도|재시도/.test(b), `러너 ${t} 는 재시도를 권하지 않는다 — 같은 답이 영원히 돌아온다`);
}

// ── 미신고는 '곧 풀린다'고 약속하지 않는다 ─────────────────────────────────────
// 미신고 = '아직 모른다'이지 '곧 열린다'가 아니다. 보호자가 「맹견이에요」라고 답하면 이 예약은
// 영영 진행되지 않으므로, 답이 **결정한다**고만 말해야 한다.
// ⚠ 앞선 핀(재시도 권유 금지)은 이 명제를 잡지 못했다 — 「한 번 더 눌러주세요」도 통과했다.
// 그래서 여기서는 문자열 금지가 아니라 **조건 표지의 존재**를 요구한다: 진행/예약을 언급하는
// 문장은 반드시 조건을 함께 말해야 한다. (문자열 금지는 옳은 문장을 붉게 만든 전력이 있다.)
for (const side of ['owner', 'runner']) {
  for (const t of ['dog_dangerous_undeclared', 'dog_dangerous_breed_conflict']) {
    const b = refusalFor(t, side).body;
    const mentions = /진행|예약/.test(b);
    // 조건은 **답의 내용**에 걸려야 한다. 답하는 행위에 거는 것은 조건처럼 보이는 약속이다:
    // 「신고하면 다시 진행할 수 있어요」는 문법상 조건문이지만, 맹견이라고 신고해도 진행된다는
    // 뜻으로 읽힌다 — 그리고 그건 거짓이다. (첫 판의 이 핀은 정확히 그 문장을 통과시켰고,
    // 변이 A 가 그걸 드러냈다. 명제가 '조건문일 것'이 아니라 '내용 조건일 것'이었다.)
    const contentConditional = /아니라면|아닌 경우|답에 따라|어느 쪽|있는지|여부가/.test(b);
    const actConditional = /(신고|답)(해|하)?(면|시면)[^.]*(진행|예약)/.test(b);
    ok(!mentions || (contentConditional && !actConditional),
      `${side}/${t} 는 답의 **내용**에 조건을 건다 (답하는 행위가 아니라)`);
  }
}

// 정책 문장 자체를 리터럴로 박는다 — 이 두 문장은 '무엇이 결정되는가'를 말하는 문장이고,
// 동등해 보이는 다른 표현으로 조용히 바뀌면 약속으로 되돌아간다.
ok(refusalFor('dog_dangerous_undeclared', 'runner').body
   === '반려견의 맹견 여부 확인이 끝나지 않았어요. 보호자의 답에 따라 이 예약을 진행할 수 있는지 정해져요.',
   '러너 미신고 정책 문장 리터럴');
ok(refusalFor('dog_dangerous_undeclared', 'owner').body
   === '동물보호법상 맹견은 러너에게 맡길 수 없어요. 반려견 프로필에서 한 번만 답해주세요 — 맹견이 아니라면 바로 예약할 수 있어요.',
   '보호자 미신고 정책 문장 리터럴');

// ── 평범한 전이 거절을 맹견으로 오인하지 않는다 ───────────────────────────────
// transition-booking 의 set() 은 모든 트리거 거절을 같은 409 로 던진다. 그 통로를 공유하는
// 이상, 관계없는 거절이 맹견 문구를 뒤집어쓰면 사용자는 있지도 않은 문제를 고치러 간다.
for (const m of [
  'invalid booking transition: no_show -> picked_up',
  'cancel_after_handoff',
  'cancel_fee_requote',
]) {
  ok(dangerousRefusalFrom({ message: m }) === null, `평범한 전이 거절은 맹견으로 오인되지 않는다 (${m.slice(0, 28)})`);
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
