// Push-preference categories — the PURE half of `app/notification-settings.tsx`.
//
// It knows no RN, no router, no supabase, so `test/notification-prefs.test.cjs` pins this table
// against the REAL compiled source (the `notification-route.ts` idiom) rather than a retyped copy.
//
// ⚠ THE FOUR KEYS ARE SERVER COLUMN NAMES. `notification_prefs` (0187 §A) has exactly
// `booking · chat · community · reward`, and `set_notification_prefs` takes `p_<key>` for each.
// A key added here without its column is a switch that saves nothing; a column added there
// without a row here is a preference nobody can reach.
//
// ⚠ `safety` IS NOT A COLUMN AND MUST NOT BECOME ONE. 0187 §C files `kind in ('safety','system')`
// — SOS, S1/S2 인시던트, 외부 커스터디 이양, 반환 지연 경보, ops escalations — as always-on, and
// `notify_push` returns before it even reads the preferences table for those. The row below is
// rendered with a disabled switch and a reason, never as a control that does nothing.
//
// ⚠ AND `marketing` IS ABSENT ON PURPOSE. Nothing in the product sends a campaign notification
// (measured across every migration, 2026-09-21: zero writers), and a toggle for a push nobody
// sends is a dead button. It arrives with its first writer, in the same slice.

/** The four columns `notification_prefs` actually has. */
export type PrefKey = 'booking' | 'chat' | 'community' | 'reward';

export interface NotiPrefs {
  booking: boolean;
  chat: boolean;
  community: boolean;
  reward: boolean;
}

export interface PrefRow {
  /** null ⇒ the always-on safety row: no column, no toggle. */
  key: PrefKey | null;
  label: string;
  desc: string;
  /** true ⇒ rendered as a disabled switch with `reason` shown instead of a promise. */
  alwaysOn?: boolean;
  reason?: string;
}

export const DEFAULT_PREFS: NotiPrefs = { booking: true, chat: true, community: true, reward: true };

export const PREF_KEYS: PrefKey[] = ['booking', 'chat', 'community', 'reward'];

// The descriptions name WHAT ARRIVES, never what the person "will miss" — and none of them may
// claim the record disappears, because it does not (see PREFS_NOTE). `notification-prefs.test.cjs`
// asserts that in both directions.
export const PREF_ROWS: PrefRow[] = [
  {
    key: 'booking',
    label: '예약·러닝',
    desc: '요청 수락과 거절, 인계 확인 요청, 러닝 시작과 종료, 결제 안내',
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
    key: null,
    label: '안전·긴급',
    desc: 'SOS, 사고 접수와 처리, 반환 지연 경보, 운영팀 확인 요청',
    alwaysOn: true,
    reason: '안전 알림은 끌 수 없어요 — 개와 사람이 걸린 일이라서예요',
  },
];

/** The one sentence that keeps this screen honest: a preference silences the DEVICE push only. */
export const PREFS_NOTE = '끄면 휴대폰 알림만 오지 않아요 · 알림함에는 그대로 쌓입니다';

/** Server row (or the defaults) → the strict shape the screen renders. Unknown/missing ⇒ true,
 *  the same direction the server takes: a preference nobody set never silences anything. */
export function toPrefs(row: Partial<Record<PrefKey, unknown>> | null | undefined): NotiPrefs {
  const one = (k: PrefKey): boolean => (row?.[k] === false ? false : true);
  return { booking: one('booking'), chat: one('chat'), community: one('community'), reward: one('reward') };
}
