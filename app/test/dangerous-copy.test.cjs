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

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
