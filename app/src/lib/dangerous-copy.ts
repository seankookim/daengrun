// ═══════════ 맹견 거절 문장 (0119 dog custody gate) ═══════════
// 서버(0119 §C)가 돌려주는 세 토큰을 화면 문장으로 바꾼다. 판정은 서버, 문장은 여기, 렌더링은
// 호출부 — lateness/late-copy 와 같은 배치다.
//
// ⚠ 왜 src/lib 인가: 문장이 곧 법이다. 이 문장들은 사람이 자기 반려견을 맡길 수 없다는 말을
// 전하고, 그 말이 틀리면(예: 있지도 않은 허가 절차를 암시하면) 그건 화면이 지어낸 약속이 된다.
// 컴포넌트 안에 두면 .cjs 스위트가 번들할 수 없어 영원히 테스트 밖에 남는다.
//
// ⚠ 이 파일이 절대 하지 않는 것: 조건부 허용을 암시하는 것. 입마개·맹견사육허가·책임보험은
// 전부 **확인할 수단이 이 제품에 없다** — 문서 업로드도, 검토자도, '맹견을 다뤄봤다'는 러너
// 등급도 없다. 확인자 없는 조건은 양식일 뿐이고, 양식은 「서류를 내면 된다」고 읽힌다.
// 「조건부 허용」 룰링(Sean 미결, 0119 REGISTRY)이 내려오면 이 파일과 검증자가 같은 슬라이스로
// 함께 바뀐다. 그때까지 화면은 0119 가 실제로 구현한 것만 말한다: 거절, 그리고 실제로 열려 있는
// 문 하나(보호자 동반 클럽 참여).

export type DangerousToken =
  | 'dog_dangerous_undeclared'
  | 'dog_dangerous_custody_refused'
  | 'dog_dangerous_breed_conflict';

export type DangerousRefusal = {
  token: DangerousToken;
  title: string;
  body: string;
  /** 사용자가 실제로 할 수 있는 행동이 있으면 그 라벨. 없으면 null — 가짜 문을 만들지 않는다. */
  action: { label: string; route: '/owner/dog' } | null;
};

const TOKENS: DangerousToken[] = [
  'dog_dangerous_undeclared',
  'dog_dangerous_custody_refused',
  'dog_dangerous_breed_conflict',
];

/**
 * 에러 메시지에서 맹견 거절 토큰을 찾는다. 못 찾으면 null — 호출부는 그때 기존 실패 경로를 쓴다.
 *
 * ⚠ `===` 가 아니라 `includes` 인 이유: 토큰이 두 경로로 도착한다. create-booking-hold 는 409 의
 * 메시지를 **토큰 그대로** 담아 주지만(handler.ts, 0119 edge), 인계 방향 전이는 트리거의 raise 가
 * PostgREST 를 거쳐 오므로 토큰이 더 긴 문장 **안에** 실려 온다. 한쪽에만 맞춘 매칭은 다른 쪽에서
 * 조용히 일반 실패로 떨어지고, 그건 「예약 실패」라는 막다른 길이 된다.
 */
export function dangerousRefusalFrom(err: unknown, side: DangerousSide = 'owner'): DangerousRefusal | null {
  const msg = (err as { message?: unknown } | null)?.message;
  if (typeof msg !== 'string') return null;
  const token = TOKENS.find((t) => msg.includes(t));
  return token ? refusalFor(token, side) : null;
}

/** 누가 읽는가. 0119 F1 이후 이 토큰들은 배정·수락·이동·인계에서도 뜨므로 러너도 읽는다. */
export type DangerousSide = 'owner' | 'runner';

export function refusalFor(token: DangerousToken, side: DangerousSide = 'owner'): DangerousRefusal {
  // ⚠ 러너에게 보호자용 문장을 보여주면 그건 할 수 없는 일을 시키는 것이다. 러너는 남의 반려견
  // 프로필을 고칠 수 없고 신고를 대신할 수도 없다 — 그래서 행동 버튼은 **없고**(가짜 문 금지),
  // 문장은 '무엇이 막혔고 누가 풀 수 있는지'만 말한다. 세 토큰이 러너에게는 한 가지 사실로
  // 수렴한다: 이 예약은 지금 받을 수 없고, 푸는 쪽은 보호자다.
  if (side === 'runner') {
    return {
      token,
      title: '이 예약은 지금 받을 수 없어요',
      // ⚠ 이 문장은 **두 자리**에서 쓰인다: 요청 수락(0119 F1 의 배정/수락 팔)과 인계 확인 탭
      // (같은 트리거가 인계 도장 쓰기도 막는다 — 늦게 신고된 맹견이 인계를 완주하면 안 되므로
      // 그 탭이 마지막 관문이다). 첫 판은 「이 요청은 목록에서 사라집니다」였는데, 그건 수락
      // 화면에서만 참이다 — 문 앞에 서서 인계 확인을 누른 러너에게는 목록 이야기가 거짓말이다.
      // 그래서 두 자리 모두에서 참인 것만 말한다: 이 예약은 진행되지 않고, 푸는 쪽은 보호자다.
      // ⚠ 「보호자가 신고하면 다시 진행할 수 있어요」였다 — 그건 약속이고, 지킬 수 없는 약속이다.
      // 보호자가 「맹견이에요」라고 답하면 이 예약은 영영 진행되지 않는다. 미신고는 '아직 모른다'는
      // 뜻이지 '곧 풀린다'는 뜻이 아니므로, 문장은 답이 **결정한다**고만 말한다.
      body: token === 'dog_dangerous_custody_refused'
        ? '동물보호법상 맹견은 러너에게 맡길 수 없어요. 이 예약은 진행되지 않아요.'
        : '반려견의 맹견 여부 확인이 끝나지 않았어요. 보호자의 답에 따라 이 예약을 진행할 수 있는지 정해져요.',
      action: null,
    };
  }
  switch (token) {
    // 아직 묻지 않았다. 거절문이 아니라 **요청문**이다 — 사용자는 한 번 답하면 끝난다.
    case 'dog_dangerous_undeclared':
      return {
        token,
        title: '맹견 여부를 알려주세요',
        // ⚠ 첫 판은 「한 번만 답해주시면 바로 예약할 수 있어요」였고, 그건 러너 쪽과 똑같은
        // 과잉 약속이다 — 맹견이라고 답하면 예약은 열리지 않는다. 조건을 문장 안에 넣는다.
        body: '동물보호법상 맹견은 러너에게 맡길 수 없어요. 반려견 프로필에서 한 번만 답해주세요 — 맹견이 아니라면 바로 예약할 수 있어요.',
        action: { label: '프로필에서 답하기', route: '/owner/dog' },
      };
    // 보호자가 맹견이라고 신고했다. 되돌릴 문이 없으므로 행동 버튼도 없다 — 대신 실제로 열려
    // 있는 문을 문장으로 말한다. 여기에 '허가증' 류의 단어가 들어가면 그게 거짓 약속이다.
    case 'dog_dangerous_custody_refused':
      return {
        token,
        title: '맹견은 러너에게 맡길 수 없어요',
        body: '동물보호법상 맹견은 다른 사람에게 맡기는 산책을 제공할 수 없어요. 보호자님이 함께 가는 클럽 동반 참여는 그대로 이용할 수 있어요.',
        action: null,
      };
    // 신고와 견종이 서로 다른 말을 한다. 사람이 고칠 수 있는 일이고, 어디서 고치는지도 안다.
    case 'dog_dangerous_breed_conflict':
      return {
        token,
        title: '견종과 신고 내용이 달라요',
        body: '등록된 견종은 맹견으로 분류되는데 맹견이 아니라고 신고돼 있어요. 반려견 프로필에서 견종이나 맹견 여부를 확인해주세요 — 어느 쪽이 맞는지에 따라 예약 가능 여부가 정해져요.',
        action: { label: '프로필 확인하기', route: '/owner/dog' },
      };
  }
}
