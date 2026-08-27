import { router } from 'expo-router';
import { session } from '../store';
import { fetchCurrentOwnerBookingId, INCIDENT_NOTI_TITLE } from './api';
import { supabase } from './supabase';

// APNs 푸시 등록 (Expo Push 경유, 0024) — 홈 진입 시 1회 호출 (양 역할).
// expo-notifications 미탑재(구 빌드) / 권한 거부 / projectId 미설정은 전부 조용한 스킵 —
// 푸시는 부가 채널, 실패가 앱을 막지 않는다.

let _registered = false;
let _armed = false;
const _handledTaps = new Set<string>();

// 라이브 미트업 제목 — 서버↔클라이언트 계약 쌍이다. 이 두 문자열은 transition-booking의
// enroute 케이스(:186 '러너 이동 중')와 arrived 케이스('러너 도착')가 보내는 제목 그대로이고,
// 한쪽을 바꾸면 반드시 다른 쪽도 같이 바꿔야 한다.
// 완전 일치만 쓴다 — includes로 부분 일치를 잡으면 '새 사진 도착'·'위탁 배정 도착'·
// '위탁 신청 도착'이 '도착'에 걸려 리포트 대신 인계 화면으로 잘못 새어 나간다.
const LIVE_TITLES = ['러너 도착', '러너 이동 중'];
// 보호자 → 러너 중단 요청 (api.ts RUN_STOP_TITLE와 같은 문자열 — 한쪽을 바꾸면 둘 다 바꾼다).
// 러너의 기본 booking 도착지는 캘린더인데, 진행 중인 러닝을 멈춰달라는 요청이 캘린더에 떨어지면
// 그건 도달이 아니다. 이 제목만 러닝 화면으로 보낸다.
const RUN_STOP_TITLE = '러닝 중단 요청';

// [0090 ⑬] 채팅 알림의 제목이자 라우팅 키. RUN_STOP_TITLE과 같은 종류의 문자열 계약이고,
// 같은 위험(한쪽만 바뀌면 조용히 어긋난다)을 가진다 — 그래서 이 리터럴은 0090 마이그레이션을
// 테스트 시점에 읽어 양방향으로 대조한다(_test/chat_notify_contract_test.ts).
// 채팅은 양쪽 역할 모두 채팅 화면으로 간다: 메시지가 도착한 곳이 곧 목적지다.
const CHAT_TITLE = '새 메시지';

// ── Runner destinations, by EXACT title ────────────────────────────────────────────────
// Replaces `title.includes('요청') ? requests : calendar`, which sent the runner to the wrong
// screen at the one moment that matters most: the owner taps 인계하기, the server sends
// 「인계 확인 요청」, and `.includes('요청')` dropped the runner on the OPEN-REQUEST INBOX — a list
// that contains nothing about this booking — while the only screen with the 인계 받았어요 button
// sat two taps away with no hint. The bug was invisible because the other 요청 titles
// (일정 변경 요청 · 변경 요청 철회 · 지명 러닝 요청) happen to belong in that inbox.
// Same discipline as LIVE_TITLES above: exact match, and a title that is not listed falls to the
// calendar, which is the honest "here is your schedule" default rather than a guess.
// ⚠ Server contract — these strings are the titles `transition-booking` actually sends. Changing
// one side without the other silently misroutes; grep the notify() calls before editing.
const RUNNER_ROUTES: Record<string, string> = {
  '인계 확인 요청': '/runner/meetup',   // the handoff CTA lives here
  '인계 완료': '/runner/run',           // both sides sealed — the run is what happens next
  '러닝 시작': '/runner/run',
  '지명 러닝 요청': '/runner/requests',
  '일정 변경 요청': '/runner/requests',
  '변경 요청 철회': '/runner/requests',
};

// Owner titles that mean "the meetup is happening NOW". Same self-restore caveat as LIVE_TITLES:
// /owner/meetup takes no bid, so these only route there when the notification IS the current
// booking; otherwise they fall to the bid-scoped report.
const OWNER_MEETUP_TITLES = [...LIVE_TITLES, '인계 확인 요청', '인계 완료'];

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

// The destination set for a ref_id that is a BOOKING. Split out so a safety row whose ref turns
// out to be a booking (0117:793) reuses this exact logic rather than a parallel copy that drifts.
function routeForBookingRef(refId: string, title: string): void {
  try {
    // [0090 ⑬] 역할과 무관하게 채팅으로 — 러너든 보호자든 온 메시지는 같은 스레드에 있다.
    if (title === CHAT_TITLE) { router.push({ pathname: '/chat', params: { bid: refId } }); return; }
    // [0094 ⑪] 사고 신고 — 채팅과 같은 이유로 역할 분기가 없다: 확인 도장은 양쪽이 각자 찍어야
    // 하고(verified_at 은 둘 다여야 채워진다), 그 화면은 예약 id 하나로 열린다. 상수는 api.ts 에서
    // import 한다 — RUN_STOP_TITLE 처럼 사본을 두면 한쪽만 바뀌어 조용히 어긋나는 부류다.
    // 템플릿 리터럴 — `/club/session/${refId}` 와 같은 형태다 (이 리포에서 동적 세그먼트가
    // 실제로 그렇게 푸시되고 있는 유일한 증명된 형태).
    if (title === INCIDENT_NOTI_TITLE) { router.push(`/incident/${refId}`); return; }
    if (session.role === 'runner') {
      // [적대 리뷰 2026-08-11] 처음엔 /runner/run으로 보냈는데, 콜드 스타트에서 그 화면은 refId를
      // 버리고 running=false로 마운트한다 — 이미 진행 중인 러닝을 두고 '러닝 시작' 버튼을 내미는
      // 화면이 뜬다. 게다가 **중단 사유는 채팅에 있다**. 채팅은 bid로 스코프되므로 정확한 예약의
      // 정확한 내용으로 착지한다 — 러너가 알아야 할 것이 실제로 있는 곳.
      if (title === RUN_STOP_TITLE) { router.push({ pathname: '/chat', params: { bid: refId } }); return; }
      router.push(RUNNER_ROUTES[title] ?? '/runner/calendar');
    } else if (OWNER_MEETUP_TITLES.includes(title)) {
      // /owner/meetup takes no bid — it self-restores to whatever booking is CURRENTLY in
      // flight. Fine for a live push tapped in the moment; wrong for the historical inbox
      // (alerts.tsx shares this router): a months-old "러너 이동 중" row would open today's
      // unrelated booking, or dead-end on "진행 중인 예약이 없어요". Route to the meetup screen
      // only when this notification IS the current booking; otherwise keep the report route.
      // Async by necessity — deep links are best-effort, so the fetch failing folds to report
      // (still bid-scoped and honest) rather than to a screen that guesses.
      fetchCurrentOwnerBookingId()
        .then((cur) => {
          try {
            if (cur && cur === refId) router.push('/owner/meetup');
            else router.push({ pathname: '/owner/report', params: { bid: refId } });
          } catch { /* navigation not ready — deep link is best-effort */ }
        })
        .catch(() => {
          try { router.push({ pathname: '/owner/report', params: { bid: refId } }); } catch { /* */ }
        });
    } else {
      router.push({ pathname: '/owner/report', params: { bid: refId } });
    }
  } catch {
    // 내비게이션 미준비 등 — 딥링크는 부가 기능, 실패해도 앱은 살아있다
  }
}

// 알림 탭 도착지 — alerts.tsx 인박스와 단일 소스 (kind/ref_id는 0024 data 페이로드).
// 역할별: 러너는 요청/캘린더, 보호자는 라이브 미트업(도착·이동 중) 또는 리포트.
export function routeForNotification(kind: string | null | undefined, refId: string | null | undefined, title: string): void {
  if (kind === 'community') { try { router.push('/community'); } catch { /* */ } return; } // 클럽 리캡 등
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
  // The runner's whole booking set qualifies: RUNNER_ROUTES and the calendar default take no id at
  // all, and its two id-consuming titles (새 메시지 · 러닝 중단 요청) are both booking-scoped.
  // [0094 ⑪] 사고 접수 알림도 이 빠른 경로에 든다 — 그 행의 유일한 writer 가 api.ts 의
  // openBookingIncident 이고, `ref_id` 에 예약 id 를 넣는다. 아는 것을 프로브로 되묻지 않는다.
  if (kind === 'booking' && (title === CHAT_TITLE || title === INCIDENT_NOTI_TITLE
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
    const { status } = await Notifications.requestPermissionsAsync();
    if (status !== 'granted') return;
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
