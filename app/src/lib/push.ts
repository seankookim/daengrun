import { router } from 'expo-router';
import { session } from '../store';
import { fetchCurrentOwnerBookingId, INCIDENT_NOTI_TITLE } from './api';
import {
  CHAT_TITLE, destinationForBookingRef, destinationForCommunityRef, needsClubProbe,
  needsCommunityClubProbe, needsCurrentBookingProbe, OWNER_MEETUP_TITLES, refMayBeClubSession,
} from './notification-route';
import { supabase } from './supabase';

// APNs 푸시 등록 (Expo Push 경유, 0024) — 홈 진입 시 1회 호출 (양 역할).
// expo-notifications 미탑재(구 빌드) / 권한 거부 / projectId 미설정은 전부 조용한 스킵 —
// 푸시는 부가 채널, 실패가 앱을 막지 않는다.

let _registered = false;
let _armed = false;
const _handledTaps = new Set<string>();

// The title tables (LIVE_TITLES · RUN_STOP_TITLE · CHAT_TITLE · HANDOFF_TITLES · RUNNER_ROUTES ·
// OWNER_MEETUP_TITLES) and the destination decision for a booking ref live in
// `notification-route.ts` — pure, so `test/notification-route.test.cjs` pins the table against the
// real compiled source. This file keeps what needs the world: the router, the store, the probes.

// ── Where a ref_id actually points ─────────────────────────────────────────────────────────────
// `notifications` has exactly ONE pointer column and it is an UNTYPED uuid — the whole table is
// (id, profile_id, kind, title, body, ref_id, read_at, created_at), measured against production
// 2026-08-27. So `kind` classifies the MESSAGE, never the target, and production carries
// counterexamples in BOTH directions:
//   kind='booking' 「위탁 승인 — 결제 대기」 → club_sessions.id (0084:642 writes sd.session_id) · 7 rows
//   kind='safety'  「확인이 필요해요」       → bookings.id      (0117:793 writes p_booking)     · 2 rows
// Every other safety writer emits a session id (0045:294/0058:200 외부 커스터디 이양 ·
// 0049:433/0068:107 반환 지연 경보 · 0049:457/0068:131 미확인 크리티컬 알림 · 0049:138 채팅 신고 접수 ·
// 0050/0067/0070 인시던트 발생), which is exactly why a per-kind or per-title rule reads as correct
// and is wrong on the minority — both defects this function used to have were that guess.
// So we ask the ID itself. `club_sessions` is world-readable (RLS policy `sessions public read`,
// `using (true)` — measured), so this is a primary-key lookup any signed-in role may make.
// ⚠ COST, paid deliberately: one extra round trip BEFORE navigating, on the taps that need it
// (every safety row, and the owner's non-meetup booking rows). Both candidate destinations fetch
// on mount anyway, so the tap was never instant. The durable fix is a `ref_kind` column written
// beside ref_id — that is server-side and outside this file; until it exists the client cannot
// know statically, and guessing is what produced these two dead taps.
async function refIsClubSession(refId: string): Promise<boolean> {
  const { data, error } = await supabase.from('club_sessions').select('id').eq('id', refId).maybeSingle();
  if (error) throw error;
  return !!data;
}

// A booking ref's club membership. `bookings` is readable by its parties ("bookings party read",
// 0002:92) and the tapping user IS a party — the notification was addressed to them. Asked ONLY
// for the handoff family (needsClubProbe): every other booking title lands on the same screen in
// both worlds. `undefined` = not known — the caller then takes the 1:1 routes, the pre-slice
// behaviour, which fails LOUDLY for a club party (a screen with no CTA) rather than stalling.
async function bookingClubSessionId(refId: string): Promise<string | null | undefined> {
  try {
    const { data, error } = await supabase.from('bookings').select('club_session_id').eq('id', refId).maybeSingle();
    if (error) return undefined;
    const sid = (data as { club_session_id?: string | null } | null)?.club_session_id;
    return sid ?? null;
  } catch {
    return undefined;
  }
}

// The destination set for a ref_id that is a BOOKING. Split out so a safety row whose ref turns
// out to be a booking (0117:793) reuses this exact logic rather than a parallel copy that drifts.
// The decision itself is `destinationForBookingRef` (notification-route.ts, pure, pinned); this
// function only gathers the facts it needs — at most one probe each, only on the taps that need
// them — and pushes. Async by necessity — deep links are best-effort, so a probe failing folds
// to the honest fallback inside the pure table rather than to a screen that guesses.
function routeForBookingRef(refId: string, title: string): void {
  const role = session.role;
  const club = needsClubProbe(title) ? bookingClubSessionId(refId) : Promise.resolve<string | null | undefined>(null);
  const current = needsCurrentBookingProbe(role, title)
    ? fetchCurrentOwnerBookingId().then((cur) => !!cur && cur === refId).catch((): boolean | null => null)
    : Promise.resolve<boolean | null>(null);
  Promise.all([club, current])
    .then(([clubSessionId, isCurrentOwnerBooking]) => {
      const dest = destinationForBookingRef(
        { refId, title, role, clubSessionId, isCurrentOwnerBooking },
        { incident: INCIDENT_NOTI_TITLE },
      );
      try { router.push(dest as Parameters<typeof router.push>[0]); } catch { /* navigation not ready — best-effort */ }
    })
    .catch(() => { /* unreachable: both probes fold their own failures; a deep link never throws */ });
}

// 알림 탭 도착지 — alerts.tsx 인박스와 단일 소스 (kind/ref_id는 0024 data 페이로드).
// 역할별: 러너는 요청/캘린더, 보호자는 라이브 미트업(도착·이동 중) 또는 리포트.
export function routeForNotification(kind: string | null | undefined, refId: string | null | undefined, title: string): void {
  // [routing sweep ③] `community` asks the id, like every other kind with a ref. This line used to
  // be an unconditional `/community`, and every community writer in the migrations passes a club
  // SESSION id — so 0047's 「배정 불발 자동 환불」 and 0070's 「미진행 위탁 자동 환불」 (whose body
  // says 「세션 종료를 눌러주세요」) landed a host on the feed, which has no such control. The recap
  // family keeps the feed: its body says 「피드에서 확인하세요」, and `needsCommunityClubProbe`
  // exempts it so it stays instant and pays for no probe. See notification-route.ts §③.
  if (kind === 'community') {
    if (!needsCommunityClubProbe(refId, title)) {
      try { router.push('/community'); } catch { /* navigation not ready — best-effort */ }
      return;
    }
    refIsClubSession(refId as string)
      .then((isSession) => destinationForCommunityRef({ refId, title, isClubSession: isSession }))
      .catch(() => destinationForCommunityRef({ refId, title, isClubSession: null }))
      .then((dest) => { try { router.push(dest as Parameters<typeof router.push>[0]); } catch { /* navigation not ready */ } });
    return;
  }
  if (kind === 'reward') { // 기록·마일스톤 (0034) — ref_id = booking → 리포트로
    try { router.push(refId ? { pathname: '/owner/report', params: { bid: refId } } : '/cards'); } catch { /* */ }
    return;
  }
  // `safety` joins `booking` here. It used to fall off the end of this function and route NOWHERE,
  // so 「외부 커스터디 이양 … 즉시 확인하세요」 — the most urgent thing this product can say — was a
  // tap that did nothing, in the inbox AND on the OS push. `shop` and `system` are still not
  // listed: they are in the noti_kind enum (0001:23) and NOTHING writes them (zero writers across
  // every migration, zero rows in production). hasNotificationRoute() below keeps them from being
  // drawn as buttons, which is the honest handling of a kind with no destination to bind.
  if ((kind !== 'booking' && kind !== 'safety') || !refId) return;

  // Fast path — titles whose writer is KNOWN to emit a booking id skip the probe and stay instant.
  // ⚠ [0193] THIS SENTENCE USED TO READ 「RUNNER_ROUTES and the calendar default take no id at
  // all」, and that stopped being true when the return family started carrying `params: { bid }`
  // (codex A4). The fast path is UNCHANGED and is if anything better justified: the question it
  // answers is 「is this row's `ref_id` a BOOKING id」, and every writer in the runner's booking set
  // emits one — so the destinations that now consume it are handed the right id, and the ones that
  // ignore it are unaffected. Corrected rather than deleted: a header that quietly stops claiming
  // something is how the next session inherits the belief.
  // The club probe is NOT skipped here — `routeForBookingRef` decides that per title
  // (`needsClubProbe`), which is what sends a club 「반환 확인 요청」 to its session screen.
  // [0094 ⑪] 사고 접수 알림도 이 빠른 경로에 든다 — 그 행의 유일한 writer 가 api.ts 의
  // openBookingIncident 이고, `ref_id` 에 예약 id 를 넣는다. 아는 것을 프로브로 되묻지 않는다.
  // 🔴 [routing sweep ②] `!refMayBeClubSession(title)` IS THE FAST PATH'S MISSING PRECONDITION.
  // The paragraph above says the fast path answers 「is this row's ref_id a BOOKING id」 and that
  // every writer in the runner's booking set emits one. The second half was false: 0068's
  // `club_assignment_recovery` sends the runner 「체크인 지연」 — 「지금 체크인하세요」 — with a
  // `club_sessions.id`, and six more club writers address a runner the same way (the list is
  // `CLUB_SESSION_REF_TITLES`, enumerated from the migrations). For those titles the skip was
  // resolving a session id as a booking id: the probe never ran, `/club/session/[sid]` was
  // unreachable for a runner by construction, and the tap fell to `/runner/calendar`.
  // The titles on that list now fall through to the probe below, which asks the id itself — so a
  // session ref reaches the session screen and a booking ref still takes the 1:1 route. The skip
  // is unchanged for every other title, including the two named ones and the meetup family.
  if (kind === 'booking' && !refMayBeClubSession(title)
      && (title === CHAT_TITLE || title === INCIDENT_NOTI_TITLE
      || session.role === 'runner' || OWNER_MEETUP_TITLES.includes(title))) {
    routeForBookingRef(refId, title);
    return;
  }
  // Everything left is genuinely ambiguous — the owner's non-meetup booking rows (where 0084:642's
  // session id lands) and every safety row. A failed probe folds to the booking route rather than
  // stalling: both destinations fail LOUDLY on a wrong id (report → 「이 러닝을 찾을 수 없어요」,
  // session → its own error state), so an error-path guess is visible and recoverable, never silent.
  refIsClubSession(refId)
    .then((isSession) => {
      if (!isSession) { routeForBookingRef(refId, title); return; }
      try { router.push(`/club/session/${refId}`); } catch { /* navigation not ready — best-effort */ }
    })
    .catch(() => routeForBookingRef(refId, title));
}

// alerts.tsx draws every row and must not draw a control that cannot act (house law: no dead
// buttons). This is the SYNCHRONOUS twin of routeForNotification's early returns above, and the
// two must be edited in the same breath — if they disagree the inbox either grows a dead tap or
// hides a live destination. It answers only "is there a destination at all"; WHICH destination can
// need the probe, and that answer is never needed to decide whether a row is a button.
export function hasNotificationRoute(kind: string | null | undefined, refId: string | null | undefined): boolean {
  if (kind === 'community') return true;              // /community — no ref needed
  if (kind === 'reward') return true;                 // 리포트(ref 있음) 또는 /cards(없음)
  if (kind === 'booking' || kind === 'safety') return !!refId;
  return false;                                       // shop · system · 미지의 kind — 바인딩할 목적지 없음
}

function handleTap(Notifications: any, response: any): void {
  const req = response?.notification?.request;
  if (!req) return;
  const id: string = req.identifier ?? '';
  if (id && _handledTaps.has(id)) return; // 리스너와 콜드스타트 이중 배달 가드
  if (id) _handledTaps.add(id);
  const content = req.content ?? {};
  const data = content.data ?? {};
  routeForNotification(data.kind, data.ref_id, content.title ?? '');
}

// 딥링크 무장: 탭 리스너 + 콜드스타트(종료 상태에서 알림 탭으로 실행된 경우).
// 홈 마운트 시점(registerPushToken 경유)에 호출되므로 내비게이션은 이미 준비됨.
function armDeepLinks(Notifications: any): void {
  if (_armed) return;
  _armed = true;
  try {
    Notifications.addNotificationResponseReceivedListener((r: any) => handleTap(Notifications, r));
    Notifications.getLastNotificationResponseAsync?.().then((r: any) => { if (r) handleTap(Notifications, r); });
  } catch (e) {
    console.warn('[push] deep link:', (e as Error)?.message);
  }
}

// ── Permission, split out of registration (HIG row S1, 2026-09-22) ─────────────────────────────
// 🔴 `registerPushToken` NO LONGER ASKS. That is structural, not a convention to remember: the
// only code path in this app that can reach the system alert is `requestPushPermission` below, and
// its only caller is `notification-primer.tsx`'s 계속 button. Previously this function asked on
// mount from both homes — which for a signed-in user IS launch — so the single question iOS grants
// was spent before the person had been told what arrives. Removing the ask from here means a
// future session cannot reintroduce the unprimed prompt by editing a call site; it would have to
// call the request function by name, which is documented as the primer's.

/** The current permission, or null when it cannot be read (old build, throwing module). */
export async function readPushPermission(): Promise<{ status?: string; canAskAgain?: boolean } | null> {
  let Notifications: any;
  try { Notifications = require('expo-notifications'); } catch { return null; } // 구 빌드
  try {
    const cur = await Notifications.getPermissionsAsync();
    if (!cur) return null;
    return { status: cur.status, canAskAgain: cur.canAskAgain };
  } catch (e) {
    console.warn('[push] permission read:', (e as Error)?.message);
    return null;
  }
}

/**
 * Fire the system alert. THE PRIMER'S BUTTON IS THE ONLY CALLER — see the block above.
 * Returns the resulting status, or null when it could not be asked at all.
 */
export async function requestPushPermission(): Promise<string | null> {
  let Notifications: any;
  try { Notifications = require('expo-notifications'); } catch { return null; }
  try {
    return (await Notifications.requestPermissionsAsync())?.status ?? null;
  } catch (e) {
    console.warn('[push] permission request:', (e as Error)?.message);
    return null;
  }
}

export async function registerPushToken(): Promise<void> {
  let Notifications: any;
  let Constants: any;
  try {
    Notifications = require('expo-notifications');
    Constants = require('expo-constants').default;
  } catch {
    return; // 구 빌드 — 새 빌드에 포함
  }
  armDeepLinks(Notifications); // 토큰 등록 여부와 무관하게 1회 무장 (탭 배달은 OS가 이미 함)
  if (_registered) return;
  try {
    // 포그라운드에서도 배너 표시 (요청 수락 대기 중 앱을 보고 있어도 알림이 보이게)
    Notifications.setNotificationHandler({
      handleNotification: async () => ({
        shouldShowAlert: true, shouldShowBanner: true, shouldShowList: true,
        shouldPlaySound: true, shouldSetBadge: false,
      }),
    });
    // Read only. Not granted ⇒ there is no token to get, so return — WITHOUT prompting. Calling
    // this on an `undetermined` account is a no-op by design: the primer asks first, then calls
    // back in here. (Deep links are armed above regardless, which is why that line sits before
    // this return: taps are delivered by the OS and do not depend on our token.)
    const current = await Notifications.getPermissionsAsync();
    if (current?.status !== 'granted') return;
    const projectId = Constants?.expoConfig?.extra?.eas?.projectId ?? Constants?.easConfig?.projectId;
    if (!projectId) {
      console.warn('[push] EAS projectId 없음 — `eas init` 후 토큰 발급 가능');
      return;
    }
    const tokenRes = await Notifications.getExpoPushTokenAsync({ projectId });
    const token: string | undefined = tokenRes?.data;
    if (!token) return;
    const { data: user } = await supabase.auth.getUser();
    if (!user.user) return;
    const { error } = await supabase.from('push_tokens').upsert(
      { profile_id: user.user.id, token, updated_at: new Date().toISOString() },
      { onConflict: 'profile_id' },
    );
    if (!error) _registered = true;
    else console.warn('[push] token save:', error.message);
  } catch (e) {
    console.warn('[push] register:', (e as Error)?.message);
  }
}

// Local (device-only) notification — no server, no push token. Used by the run screen when
// background tracking crosses a line the runner has to act on (target reached, settlement
// ceiling approaching) while the app is not on screen. Silent no-op on an old build: this is
// a nudge, and a missing nudge must never break a run.
export async function notifyLocal(title: string, body: string): Promise<void> {
  let Notifications: any;
  try { Notifications = require('expo-notifications'); } catch { return; }
  try {
    await Notifications.scheduleNotificationAsync({ content: { title, body, sound: true }, trigger: null });
  } catch (e) {
    console.warn('[push] local:', (e as Error)?.message);
  }
}
