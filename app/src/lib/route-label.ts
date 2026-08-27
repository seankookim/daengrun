// 코스 이름과 km — 두 숫자를 **구별해서** 말하기 위한 한 곳.
//
// ═══ 왜 이 파일이 있나 ═══
// Sean, 스크린샷과 함께: 「not sure what these double km measurements are」.
// 카드가 「서울숲 숲길 3km」 위에 「초코 · 5km」를 그렸다. 두 숫자가 라벨 없이 나란히 있었고,
// 서로 다르기까지 했다 — 하나는 코스 길이, 하나는 이 예약의 거리다.
//
// 🔴 ═══ 첫 수정은 틀렸고, 그 이유가 이 파일의 핵심이다 ═══
// 처음엔 이름 끝의 km 토큰을 **떼어냈다**. 장식이라고 봤기 때문이다. 장식이 아니었다.
// codex 리뷰가 `0100_route_name_km_agrees.sql`을 들고 왔고, 그 마이그레이션 헤더가 이미
// 같은 말을 하고 있었다: 「1.6 km, 4.8 km and 5.4 km are three different loops around the same
// hill whose only distinguishing text IS the km token. There, the number is doing IDENTIFICATION
// work, not measurement.」
//
// 프로덕션에서 재측정한 결과, 정확히 그랬다:
//   몽마르뜨 언덕 루프 · 몽마르뜨 언덕 루프 4.79km · 몽마르뜨 언덕 루프 5.4km   ← 3개
//   반포 서래섬 리버 루프 3.31km · 반포 서래섬 리버 루프 3.71km                  ← 2개
// 토큰을 떼면 이 다섯 개가 두 개의 **같은 이름**이 된다. 보호자는 자기가 어느 코스를 골랐는지
// 화면에서 구별할 수 없게 된다 — 원래 결함(헷갈리는 숫자)을 더 나쁜 결함(구별 불가능한 이름)으로
// 바꾼 것이다.
//
// ═══ 그래서 실제 수정 ═══
// **이름은 건드리지 않는다.** Sean의 불만은 「숫자가 둘」이 아니라 「둘인데 뭐가 뭔지 모르겠다」였다.
// 그러니 이름을 훼손하는 대신 **옆의 숫자에 이름표를 붙인다**: 「예약 5km」.
// 두 숫자는 그대로 있고, 각자 무엇인지 말한다.

/** 예약 거리에 붙는 이름표. 코스 이름 안의 km와 눈으로 구별되게 한다. */
export function bookingKmLabel(km: number | null | undefined): string {
  return km == null ? '' : `예약 ${km}km`;
}

/** 이름 끝에 붙은 거리 토큰이 있는지. 옆에 거리를 또 그릴지 결정할 때만 쓴다 — 이름을 바꾸지 않는다. */
const TRAILING_KM = /\s*[·,]?\s*\d+(?:\.\d+)?\s*km\s*$/i;
export function nameCarriesKm(name: string | null | undefined): boolean {
  return TRAILING_KM.test((name ?? '').trim());
}

/**
 * 옆에 km를 그리지 **않을** 때 쓰는 한 줄. 이름이 이미 거리를 달고 있으면 그대로, 아니면 붙인다.
 * (club/[id].tsx의 file-local 버전이 하던 일 — 여기로 옮겼다.)
 */
export function routeLabel(r: { name: string; km: number }): string {
  return TRAILING_KM.test(r.name) ? r.name : `${r.name} ${r.km}km`;
}
