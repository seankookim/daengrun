// 코스 이름과 km — 한 사실을 두 번 쓰지 않기 위한 한 곳.
//
// ═══ 왜 이 파일이 있나 ═══
// Sean, 스크린샷과 함께: 「not sure what these double km measurements are」.
// 실측: production 코스 이름의 상당수가 자기 길이를 이름 안에 달고 있다 —
// '서울숲 숲길 3km', '송파 새내근린공원·온조마루근린공원 루프 1.52km'. 그리고 화면 13곳이
// 그 이름 **옆에** 또 km를 그린다. 그래서 「서울숲 숲길 3km · 5km」가 나오고, 두 숫자는
// 심지어 서로 다르다 (이름의 3km는 코스 길이, 옆의 5km는 이 예약의 거리다).
//
// ⚠ 두 숫자가 다른 것 자체는 버그가 아니다 — 다른 사실이니까. 버그는 **라벨 없이 나란히**
//   놓아 같은 것의 두 값처럼 읽히게 만든 것이다. 이름 안의 km는 장식이고(코스 길이가 정말
//   필요하면 라벨 붙은 필드여야 한다), 옆의 km는 이 러닝의 실제 값이다. 그래서 이름에서
//   장식을 떼고 진짜 값 하나만 남긴다.
//
// ⚠ 이 헬퍼가 **공유 모듈**인 이유: 같은 함수가 club/[id].tsx 안에 file-local 로 살아 있었고
//   호출부가 하나였다. 그래서 나머지 12곳이 그대로 남았다 — Sean 이 이미 한 번 찾아낸 결함이
//   고쳐진 곳 옆에서 계속 살아 있었던 것이다. 한 곳에 두고 export 한다.

/** 이름 끝에 붙은 거리 토큰. 끝에서만 잡는다 — '3km 코스 왕복' 같은 이름의 중간 km는 이름의
 *  일부일 수 있고, 그걸 지우면 이름을 훼손한다. 소수점과 공백 변형을 모두 받는다. */
const TRAILING_KM = /\s*[·,]?\s*\d+(?:\.\d+)?\s*km\s*$/i;

/**
 * 옆에 km 를 따로 그릴 때 쓰는 이름. 이름 끝의 거리 토큰을 떼어낸다.
 * 떼고 나면 빈 문자열이 되는 병적인 경우(이름이 '5km' 뿐)에는 원래 이름을 돌려준다 —
 * 이름 없는 코스를 만들지 않는다.
 */
export function routeNameOnly(name: string | null | undefined): string {
  const n = (name ?? '').trim();
  if (!n) return '';
  const stripped = n.replace(TRAILING_KM, '').trim();
  return stripped.length > 0 ? stripped : n;
}

/**
 * 옆에 km 를 그리지 **않을** 때 쓰는 한 줄. 이름이 이미 거리를 달고 있으면 그대로,
 * 아니면 km 를 붙인다. (club/[id].tsx 의 file-local 버전이 하던 일 — 여기로 옮겼다.)
 */
export function routeLabel(r: { name: string; km: number }): string {
  return TRAILING_KM.test(r.name) ? r.name : `${r.name} ${r.km}km`;
}
