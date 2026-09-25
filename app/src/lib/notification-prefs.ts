// Push-preference categories — the PURE half of `app/notification-settings.tsx`.
//
// It knows no RN, no router, no supabase, so `test/notification-prefs.test.cjs` pins this table
// against the REAL compiled source (the `notification-route.ts` idiom) rather than a retyped copy.
//
// ⚠ THE FIVE KEYS ARE SERVER COLUMN NAMES. `notification_prefs` (0187 §A + 0210 §A) has exactly
// `booking · chat · community · reward · ops`, and `set_notification_prefs` takes `p_<key>` for
// each. A key added here without its column is a switch that saves nothing; a column added there
// without a row here is a preference nobody can reach.
//
// ⚠ `safety` IS NOT A COLUMN AND MUST NOT BECOME ONE. 0187 §C files `kind = 'safety'` and the
// `_noti_urgent_noti_titles()` family — SOS, S1/S2 인시던트, 외부 커스터디 이양, 반환 지연 경보,
// 귀가 확인 — as always-on, and `notify_push` returns before it even reads the preferences table
// for those. The safety row below is rendered with a disabled switch and a reason, never as a
// control that does nothing.
//
// 🔴 [0210] `ops` IS THE ROW THAT MADE THE SAFETY ROW HONEST AGAIN. Until 0210 the mapper opened
// `p_kind in ('safety','system') then 'safety'`, so every ops escalation — 지급 대기 · 인계 확인
// 멈춤 · 반환 좌초 · **굿즈 수령 신청** — was undisableable, and the safety row's reason line
// 「개와 사람이 걸린 일이라서예요」 was the sentence this screen used to explain that to an
// operator. It is true of an SOS and it is not true of a goods-shipping desk ping. 0210 §B moved
// `system` to its own category and the safety row's description no longer claims it.
//
// 🔴 AND THE OPS ROW IS OPERATOR-ONLY, which is why `PREF_ROWS` is not what the screen renders.
// A `system` push can only reach somebody on `ops_recipients` (0084 §E), so for everybody else
// this would be a switch for a notification they can never receive — a dead control wearing a
// switch's costume (the no-dead-buttons law). `visiblePrefRows(isOps)` is the list to render, and
// `isOps` comes from `ops_me()` (0198 §A) — the server's own answer, computed through the same
// roster window the console doors gate on, never a guess from the client.
//
// ⚠ AND `marketing` IS ABSENT ON PURPOSE. Nothing in the product sends a campaign notification
// (measured across every migration, 2026-09-21: zero writers), and a toggle for a push nobody
// sends is a dead button. It arrives with its first writer, in the same slice.

/** The five columns `notification_prefs` actually has. */
export type PrefKey = 'booking' | 'chat' | 'community' | 'reward' | 'ops';

export interface NotiPrefs {
  booking: boolean;
  chat: boolean;
  community: boolean;
  reward: boolean;
  /** [0210 §A] the ops roster's own escalations (`kind = 'system'`). Present for every caller —
   *  the server returns it to everybody — but only rendered for an operator. */
  ops: boolean;
}

export interface PrefRow {
  /** null ⇒ the always-on safety row: no column, no toggle. */
  key: PrefKey | null;
  label: string;
  desc: string;
  /** true ⇒ rendered as a disabled switch with `reason` shown instead of a promise. */
  alwaysOn?: boolean;
  reason?: string;
  /** [0210] true ⇒ shown ONLY to a caller `ops_me()` reports as an operator. The column exists for
   *  everyone server-side; what is operator-only is the ability to ever RECEIVE the push, and a
   *  switch for a notification you cannot receive is a dead control. */
  opsOnly?: boolean;
}

export const DEFAULT_PREFS: NotiPrefs = {
  booking: true, chat: true, community: true, reward: true, ops: true,
};

export const PREF_KEYS: PrefKey[] = ['booking', 'chat', 'community', 'reward', 'ops'];

// The descriptions name WHAT ARRIVES, never what the person "will miss" — and none of them may
// claim the record disappears, because it does not (see PREFS_NOTE). `notification-prefs.test.cjs`
// asserts that in both directions.
export const PREF_ROWS: PrefRow[] = [
  {
    key: 'booking',
    label: '예약·러닝',
    // [ops-notifications-4] The club 위탁 pushes that reach a PARTY — the runner's 배정 제안 and
    // the owner's 자리 확정 — are written kind='booking' (0047/0048, 0081 §B), so THIS switch
    // silences them; the sentence used to name only 1:1 events. The community row's 위탁 stays:
    // the host-side 위탁 events really are kind='community'.
    desc: '요청 수락과 거절, 인계 확인 요청, 러닝 시작과 종료, 결제 안내, 클럽 위탁 배정 제안과 자리 확정',
  },
  {
    key: 'chat',
    label: '채팅',
    desc: '상대방이 메시지를 보냈을 때 (내용은 알림에 담기지 않아요)',
  },
  {
    key: 'community',
    label: '커뮤니티·클럽',
    desc: '클럽 세션 소식, 위탁 진행 상황, 피드 알림',
  },
  {
    key: 'reward',
    label: '기록·하이',
    desc: '최고 페이스 경신, 누적 거리 달성, 완주 횟수 같은 기록 알림',
  },
  {
    // [0210] 운영 알림 — the `system` kind. Operator-only: see `visiblePrefRows`. It says what
    // stays, because turning this off changes the phone and nothing else.
    // [fix/alert-fold-copy 2026-09-25 · ops-notifications-10] The description used to name FOUR
    // titles while the switch silenced every title in `_noti_ops_titles()` — eleven at 0214,
    // FOURTEEN since 0224 (the two custody-strand bells and 정산 미완료). An operator reading it
    // would switch it off believing card-revocation and payment-cancel failures still rang. It now
    // names a FAMILY for every title the server files as `ops`, and
    // `notification-prefs.test.cjs` re-reads the latest `_noti_ops_titles()` declaration and fails
    // on any title whose family this sentence does not name — so the next system writer cannot
    // make it a partial list again without reddening a pin.
    key: 'ops',
    label: '운영 알림',
    desc: '지급 대기·정산 미완료, 인계·반환·러닝 좌초, 굿즈 수령 신청, 결제·카드·취소 수수료·보상 처리 실패 같은 운영 확인 요청 — 운영 콘솔은 그대로예요',
    opsOnly: true,
  },
  {
    key: null,
    label: '안전·긴급',
    // [0210] 「운영팀 확인 요청」 left this line with `system`. What remains is what is genuinely
    // undisableable: kind=safety plus the four `_noti_urgent_noti_titles()` members.
    desc: 'SOS, 사고 접수와 처리, 반환 지연 경보, 귀가 확인 요청',
    alwaysOn: true,
    reason: '안전 알림은 끌 수 없어요 — 개와 사람이 걸린 일이라서예요',
  },
];

/** What the screen renders. The ops row is dropped for a non-operator, because a `system` push
 *  can only reach somebody on `ops_recipients` — a switch for a notification you can never
 *  receive is a dead control, not a courtesy.
 *  ⚠ `isOps` is `ops_me().is_ops` (0198 §A). `null`/`undefined` means NOT KNOWN — the probe failed
 *  or has not answered — and the row is HIDDEN, which is the safe direction in both senses: a
 *  non-operator never sees a switch they cannot use, and an operator whose probe failed keeps
 *  getting the pushes (the column is untouched by a row that is not drawn). */
export function visiblePrefRows(isOps: boolean | null | undefined): PrefRow[] {
  return PREF_ROWS.filter((r) => r.opsOnly !== true || isOps === true);
}

// ── [0189] THE URGENT TITLE FAMILY ────────────────────────────────────────────────────────────
// These three are NOT preferences and never appear on the settings screen. They are here because
// this is the module the drift pin can bundle, and the pin's whole job is to notice when one of
// them is renamed.
//
// 🔴 WHY A TITLE AND NOT A `kind`: 0114's INSERT policy (0114:273-281) admits only
// `kind = 'booking'` from a booking party, so the three urgent things a CLIENT can send — SOS, a
// filed accident, a run-stop request — arrive at the server indistinguishable from 응가 도장.
// 0187 filed every non-chat booking row as disableable, which meant `booking = false` silenced an
// SOS; 0189 §A fixes that with a title family, and `_noti_urgent_noti_titles()` in that migration
// is the AUTHORITY. This array is the client-side mirror, and
// `test/notification-prefs.test.cjs` reads BOTH artifacts as text (comments stripped) and asserts
// they agree in both directions.
//
// ⚠ A rename that reached only one side fails SILENTLY and in the worst direction: the push simply
// stops arriving, and nobody files a bug about a push they never saw. That asymmetry is the entire
// reason this is a gate rather than a comment.
export const ALWAYS_ON_TITLES: string[] = ['SOS', '사고 신고 접수', '러닝 중단 요청'];

/** The one sentence that keeps this screen honest: a preference silences the DEVICE push only. */
export const PREFS_NOTE = '끄면 휴대폰 알림만 오지 않아요 · 알림함에는 그대로 쌓여요';

/** Server row (or the defaults) → the strict shape the screen renders. Unknown/missing ⇒ true,
 *  the same direction the server takes: a preference nobody set never silences anything. */
export function toPrefs(row: Partial<Record<PrefKey, unknown>> | null | undefined): NotiPrefs {
  const one = (k: PrefKey): boolean => (row?.[k] === false ? false : true);
  return {
    booking: one('booking'), chat: one('chat'), community: one('community'),
    reward: one('reward'),
    // [0210] An ABSENT `ops` key is a pre-0210 SERVER, not an operator who switched it off — and
    // the same rule answers both: only an explicit false is off. A `?? false` here would silence
    // an operator's ops pushes for the whole window between the client shipping and the migration
    // landing, which is the deployment order this slice actually has.
    ops: one('ops'),
  };
}
