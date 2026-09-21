// What the booking-hold modal SAYS, decided from the server's own answer.
//
// ═══ THE DEFECT (0179) ═══
// `create-booking-hold` answers a replayed `client_request_id` with `unchanged: true` and the row
// the FIRST attempt made — nothing new was created. `api.ts` has carried that flag since 0179
// (`HoldResult.unchanged`) and `owner/request.tsx` sent the key, read the flag for its
// `landedLive` branch, and then drew the same success as a fresh booking:
//     ● 서버 홀드 확보 — 예약이 생성됐어요
// On a replay that sentence is FALSE at the moment it is printed. A double-tapped 예약하기 — or
// the far more common case, a lost response and a 다시 시도 — showed the owner the first booking
// with no word that it was already theirs, which is the "celebration fires twice" shape: the
// ceremony replays for a thing that happened once.
//
// Nothing here is a new server field. Both lines are chosen from `unchanged`, which the wire has
// carried since 0179.

/** The modal's live line, once the server has answered. `live === null` is 「still asking」. */
export function holdStatusLine(i: { live: boolean | null; replayed: boolean }): string {
  if (i.live !== true) return '서버 연결 중...';
  return i.replayed ? '● 이미 접수된 예약이에요 — 새로 만들지 않았어요' : '● 서버 홀드 확보 — 예약이 생성됐어요';
}

/** The one honest line the owner is told before the confirmation screen opens, and only on a
 *  replay. `null` on a fresh booking — a booking that WAS just made needs no explanation. */
export function holdReplayNotice(replayed: boolean): { title: string; body: string } | null {
  if (!replayed) return null;
  return {
    title: '이미 접수된 예약이에요',
    body: '같은 요청이 두 번 눌렸어요 — 새 예약은 만들어지지 않았어요.',
  };
}
