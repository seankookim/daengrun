// 위치/지도 유틸 — 실거리·트레이스·실시간 위치 브로드캐스트.
// Native modules are lazy-required everywhere in this file: an old build that lacks
// expo-location / expo-task-manager degrades to a stated mode instead of crashing.
import { supabase } from './supabase';

export interface GeoPoint { lat: number; lng: number; t: number; acc?: number }

// 하버사인 (m)
export function distM(a: GeoPoint, b: GeoPoint): number {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const la = (a.lat * Math.PI) / 180;
  const lb = (b.lat * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(la) * Math.cos(lb) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// ---------- 트레이스 품질 (2026-07-29 — 스트라바풍 스무딩) ----------
// 원칙: 나쁜 픽스는 그리지도, 거리에 세지도 않는다 (지터가 km를 부풀리면 정산 부정직).

// 픽스 게이트 — 정확도 나쁨(>25m) 또는 순간이동(>10m/s, 전력 질주 개도 ~9m/s)이면 버림
export function acceptFix(prev: GeoPoint | null, p: GeoPoint): boolean {
  if (p.acc != null && p.acc > 25) return false;
  if (prev) {
    const dt = (p.t - prev.t) / 1000;
    if (dt <= 0) return false;
    if (distM(prev, p) / dt > 10) return false;
  }
  return true;
}

// ---------- Background-capable tracking (2026-08-08) ----------
// One sink, two sources. The expo-task-manager background task and the foreground
// watchPositionAsync fallback both call ingestFixes, which owns the only trace buffer and
// is the only place where a fix becomes distance. km is money (settle-run pays km * 3000),
// so there must be exactly one accumulator and it must not care how the OS batched delivery.

// Task name — also used by bgTrack.ts, which registers the handler at module scope.
// It lives here (not in bgTrack.ts) so geo.ts never has to import bgTrack: bgTrack → geo is
// the only direction, and a cycle would break the lazy-require degradation story.
export const BG_TASK = 'daengrun-run-location';

export type TrackMode =
  | 'background'    // location task running — survives screen lock and a pocketed phone
  | 'foreground'    // watchPositionAsync only — dies on screen lock (old build, no background mode)
  | 'denied'        // the runner refused the location permission
  | 'unavailable';  // expo-location missing/unusable (old build)

export interface TrackSnapshot {
  trace: GeoPoint[];   // the whole merged buffer (single source of truth)
  km: number;          // billable distance accumulated over that buffer
  last: GeoPoint;      // newest accepted fix
  addedKm: number;     // delta contributed by this delivery
}

export interface TrackHandle {
  mode: TrackMode;
  stop: () => Promise<void>;
}

export interface TrackOptions {
  dogName?: string;    // Android foreground-service notification body
  bookingId?: string;  // reserved for future task-side attribution — not required today
}

// Billable speed gate — 8 m/s, matching the server's trace gate (club_save_run_trace, 0053).
// Tighter than acceptFix's 10 m/s on purpose: a segment the server would call impossible must
// never be paid for. Points above it stay in the trace (they happened) but earn nothing.
const BILLABLE_MPS = 8;
// The server stores t in whole seconds, so two fixes inside the same second collapse there
// anyway. Collapsing client-side keeps client km and the stored trace consistent.
const DEDUP_MS = 1000;

// Pure, dependency-free, and therefore testable — see app/test/geo.test.cjs.
// Rules, in order: sort by t · drop non-monotonic · drop sub-second · acceptFix gate ·
// accumulate km only over segments the server would also accept.
export function mergeFixes(
  existing: GeoPoint[],
  incoming: GeoPoint[],
): { trace: GeoPoint[]; addedKm: number } {
  const trace = existing.slice();
  if (incoming.length === 0) return { trace, addedKm: 0 };
  const sorted = incoming.slice().sort((a, b) => a.t - b.t);
  let prev: GeoPoint | null = trace[trace.length - 1] ?? null;
  let addedKm = 0;
  for (const p of sorted) {
    if (prev) {
      if (p.t <= prev.t) continue;            // monotonic — mirrors the server's trace_out_of_order law
      if (p.t - prev.t < DEDUP_MS) continue;  // same-second dedup
    }
    if (!acceptFix(prev, p)) continue;        // accuracy + 10 m/s teleport gate
    if (prev) {
      const d = distM(prev, p);
      const dt = (p.t - prev.t) / 1000;
      if (d > 2 && d < 120 && dt > 0 && d / dt <= BILLABLE_MPS) addedKm += d / 1000;
    }
    trace.push(p);
    prev = p;
  }
  return { trace, addedKm };
}

// ---------- the single live buffer ----------
let liveTrace: GeoPoint[] = [];
let liveKm = 0;
let liveSub: ((s: TrackSnapshot) => void) | null = null;

// The sink. Called with one fix from the foreground watcher, or with a whole batch from the
// background task. Batching must not change km — that is pinned in the test suite.
export function ingestFixes(points: GeoPoint[]): void {
  if (!points || points.length === 0) return;
  const { trace, addedKm } = mergeFixes(liveTrace, points);
  if (trace.length === liveTrace.length) return; // nothing survived the gates
  liveTrace = trace;
  liveKm += addedKm;
  const last = liveTrace[liveTrace.length - 1];
  if (liveSub) liveSub({ trace: liveTrace, km: liveKm, last, addedKm });
}

// Seed from the server trace on mount (reload/kill recovery). km is recomputed through the
// same gate rather than trusted, so a hydrated run and a live run measure identically.
export function seedTrace(points: GeoPoint[]): TrackSnapshot | null {
  liveTrace = [];
  liveKm = 0;
  const { trace, addedKm } = mergeFixes([], points);
  liveTrace = trace;
  liveKm = addedKm;
  if (liveTrace.length === 0) return null;
  return { trace: liveTrace, km: liveKm, last: liveTrace[liveTrace.length - 1], addedKm };
}

export function resetTrace(): void {
  liveTrace = [];
  liveKm = 0;
}

export function getTraceSnapshot(): { trace: GeoPoint[]; km: number } {
  return { trace: liveTrace, km: liveKm };
}

function toGeoPoint(loc: any): GeoPoint {
  // Use the OS timestamp, never Date.now(): a background batch arrives all at once, and
  // stamping it with arrival time would collapse the whole batch into one second.
  const t = typeof loc?.timestamp === 'number' && loc.timestamp > 0 ? loc.timestamp : Date.now();
  return {
    lat: loc.coords.latitude,
    lng: loc.coords.longitude,
    t,
    acc: loc.coords.accuracy ?? undefined,
  };
}

// Permission state without asking — lets the run screen show its own rationale before the
// one-shot OS sheet (a declined system prompt is only recoverable through Settings).
export async function getTrackPermission(): Promise<'undetermined' | 'granted' | 'denied' | 'unavailable'> {
  let Location: any;
  try { Location = require('expo-location'); } catch { return 'unavailable'; }
  try {
    const perm = await Location.getForegroundPermissionsAsync();
    if (perm?.granted) return 'granted';
    if (perm?.canAskAgain === false) return 'denied';
    return perm?.status === 'undetermined' ? 'undetermined' : 'denied';
  } catch { return 'unavailable'; }
}

// One-shot current position for the address-pin picker's default center (0065 slice).
// Deliberately NEVER prompts: it checks the existing grant via getTrackPermission and
// returns null on anything but 'granted' — the picker must not escalate a permission
// sheet for a map that has a perfectly good 반포 fallback. null means "use the next
// center in the chain", never an error state.
export async function getOneShotPosition(): Promise<{ lat: number; lng: number } | null> {
  const perm = await getTrackPermission();
  if (perm !== 'granted') return null;
  let Location: any;
  try { Location = require('expo-location'); } catch { return null; }
  try {
    const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy?.Balanced ?? 3 });
    if (typeof loc?.coords?.latitude !== 'number' || typeof loc?.coords?.longitude !== 'number') return null;
    return { lat: loc.coords.latitude, lng: loc.coords.longitude };
  } catch { return null; }
}

// Start tracking. Never returns null again — the caller is told which mode it got so it can
// be honest about *why* tracking is degraded (module missing ≠ permission denied).
// Resolution order: expo-location missing → unavailable · permission refused → denied ·
// task registered and startLocationUpdatesAsync accepted → background · otherwise foreground.
export async function startTracking(
  onUpdate: (s: TrackSnapshot) => void,
  opts: TrackOptions = {},
): Promise<TrackHandle> {
  // Even the no-op stop clears the subscriber: a failed start must not leave the previous
  // screen's callback wired to the sink.
  const noop = async () => { liveSub = null; };
  let Location: any;
  try { Location = require('expo-location'); } catch { return { mode: 'unavailable', stop: noop }; }

  try {
    const perm = await Location.requestForegroundPermissionsAsync();
    if (!perm?.granted) return { mode: 'denied', stop: noop };
  } catch {
    // The module is present but the permission call itself failed — we cannot claim the
    // runner denied anything, so report the honest weaker claim.
    return { mode: 'unavailable', stop: noop };
  }

  liveSub = onUpdate;

  // ---- preferred path: background location task ----
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const TaskManager = require('expo-task-manager');
    if (TaskManager.isTaskDefined(BG_TASK)) {
      if (await Location.hasStartedLocationUpdatesAsync(BG_TASK)) {
        await Location.stopLocationUpdatesAsync(BG_TASK); // stale task from a killed run
      }
      await Location.startLocationUpdatesAsync(BG_TASK, {
        accuracy: Location.Accuracy.BestForNavigation,
        distanceInterval: 5,
        timeInterval: 2000,
        // CRITICAL, not tuning: iOS auto-pause decides on its own that the user stopped
        // moving and silently stops delivering — a truncated trace is a short payout.
        pausesUpdatesAutomatically: false,
        // expo-location re-exports the enum as ActivityType (LocationActivityType is the
        // internal name) — read both, fall back to the literal so an API rename cannot
        // silently drop us to the default activity type. Fitness = 3.
        activityType: Location.ActivityType?.Fitness ?? Location.LocationActivityType?.Fitness ?? 3,
        showsBackgroundLocationIndicator: true,
        foregroundService: {
          notificationTitle: '도그스하이 · 러닝 기록 중',
          notificationBody: opts.dogName
            ? `${opts.dogName}와 러닝 중 — 거리와 경로를 기록하고 있어요`
            : '거리와 경로를 기록하고 있어요',
          notificationColor: '#6C5CE7',
          // App killed ⇒ tracking stops. We do not support kill-continuation, and a service
          // that outlives the app would be a silent liar.
          killServiceOnDestroy: true,
        },
      });
      return {
        mode: 'background',
        stop: async () => {
          liveSub = null;
          try {
            if (await Location.hasStartedLocationUpdatesAsync(BG_TASK)) {
              await Location.stopLocationUpdatesAsync(BG_TASK);
            }
          } catch { /* already stopped */ }
        },
      };
    }
  } catch {
    // No expo-task-manager, or no UIBackgroundModes / FOREGROUND_SERVICE_LOCATION in this
    // binary (LocationUpdatesUnavailable / ForegroundServicePermissionsException).
    // Fall through — and say so, rather than pretending the screen lock is safe.
  }

  // ---- fallback: foreground-only watcher (old build) ----
  try {
    const sub = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.BestForNavigation, distanceInterval: 5, timeInterval: 2000 },
      (loc: any) => ingestFixes([toGeoPoint(loc)]),
    );
    return {
      mode: 'foreground',
      stop: async () => { liveSub = null; try { sub.remove(); } catch { /* no-op */ } },
    };
  } catch {
    liveSub = null;
    return { mode: 'unavailable', stop: noop };
  }
}

export interface LL { latitude: number; longitude: number }

// Catmull-Rom 스플라인 — 수락된 픽스 사이를 보간해 각진 폴리라인을 곡선으로.
// 렌더 전용 (거리 계산은 원본 픽스 기준 — 보간점으로 거리를 재면 그것도 부정직).
export function smoothTrace(pts: LL[], steps = 6): LL[] {
  const n = pts.length;
  if (n < 3) return pts.slice();
  const out: LL[] = [pts[0]];
  for (let i = 0; i < n - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[Math.min(n - 1, i + 2)];
    for (let s2 = 1; s2 <= steps; s2++) {
      const t = s2 / steps;
      const t2 = t * t;
      const t3 = t2 * t;
      out.push({
        latitude: 0.5 * (2 * p1.latitude + (-p0.latitude + p2.latitude) * t
          + (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2
          + (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3),
        longitude: 0.5 * (2 * p1.longitude + (-p0.longitude + p2.longitude) * t
          + (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2
          + (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3),
      });
    }
  }
  return out;
}

// 지연 로드 네이버 지도 (2026-07-29 — react-native-maps 은퇴) — 없으면 null (호출측이 대기 화면 폴백).
// 한국 지도 충실도(공원 내부·하천변 산책로)가 애플/구글보다 월등 — 코스가 사는 곳이 정확히 거기다.
// 클라이언트 ID는 app.json 플러그인 설정 (시크릿은 앱에 넣지 않는다 — 서버 REST 전용).
export function getNaverMap(): null | { NaverMapView: any; NaverMapPolylineOverlay: any; NaverMapPathOverlay: any; NaverMapMarkerOverlay: any } {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const M = require('@mj-studio/react-native-naver-map');
    if (!M?.NaverMapView) return null;
    return {
      NaverMapView: M.NaverMapView,
      NaverMapPolylineOverlay: M.NaverMapPolylineOverlay,
      NaverMapPathOverlay: M.NaverMapPathOverlay, // 케이싱(outline) 지원 — 스트라바풍 라인
      NaverMapMarkerOverlay: M.NaverMapMarkerOverlay,
    };
  } catch { return null; }
}

// ---------- 실시간 위치 브로드캐스트 (DB 기록 없음 — 채널만) ----------
// mode is optional on the wire: an old runner build sends none, and an old owner build
// ignores it. The owner screen renders nothing extra when it is absent — never a guess.
export interface LivePos { lat: number; lng: number; km: number; paceSec: number | null; mode?: TrackMode }

// Broadcast throttle. Every accepted fix used to become a message (~1,800/hour on an hour-long
// run) while the Live Activity next to it was already throttled to 5 s. The owner's map gains
// nothing from sub-3-second updates; the runner's battery and the Realtime quota lose.
const PUB_MIN_MS = 3000;

// ═══ 실시간 위치 채널은 PRIVATE 이다 (P0-1, 0103) ═══
// 예전엔 `supabase.channel(`run-${bookingId}`)` — **공개 브로드캐스트**였다. 부킹 id만 알면
// 아무나 구독해서 산책 중인 개의 실시간 위치를 따라볼 수 있었고, 같은 채널로 **가짜 좌표를
// 보호자 지도에 밀어 넣을** 수도 있었다(legal 실측: 로그인조차 하지 않은 두 익명 클라이언트가
// 서로 주고받는 데 성공). 토픽 이름은 비밀이 아니고 비밀로 취급해서도 안 된다 — 권한은
// 서버(realtime.messages RLS, trust 소유)가 판정하고, 클라이언트는 **private으로 요청**한다.
//
// ⚠ private 채널은 PostgREST 토큰이 아니라 **realtime 소켓의 토큰**으로 인가된다. setAuth를
// 빼먹으면 구독도 발행도 조용히 실패하고, 화면에는 '아직 안 옴'과 구별되지 않는다.
export const REALTIME_PRIVATE = { config: { private: true } } as const;

// 토픽 네임스페이스는 **서버 정책과 글자 단위로 맞아야 한다** (0104: `^run2-`). 한 곳에만 둔다 —
// 세 호출부에 문자열이 흩어져 있으면 다음 범프 때 하나가 남고, 그 증상은 '조용히 빈 지도'다.
//
// ⚠ 왜 `run2-`인가 (이유가 한 번 바뀌었다): 0104의 원래 근거는 "구버전(public 채널) 바이너리가
// 0103을 우회할지도 모른다"였다. 그 질문은 이후 실측으로 **답이 났다 — 우회는 없다**(public
// 구독자는 private 발행을 받지 못한다). 그래서 원래 근거는 사라졌고, 남은 근거는 더 약하지만
// 여전히 참이다: 격리가 **우리가 통제하지 않는 realtime 동작**(한 버전에서 한 번 측정한 것)에
// 기대는 대신 **다른 토픽이라는 구조**에 기대게 된다. 그 동작이 언젠가 회귀해도 `run-`에 있는
// 구버전은 `run2-` 트래픽에 닿지 못한다.
const RUN_TOPIC = (bookingId: string) => `run2-${bookingId}`;

/** 구독/발행 직전에 realtime 소켓을 현재 세션으로 무장시킨다. 인자 없는 setAuth()는
 *  supabase-js가 현재 세션 토큰을 집어 쓴다(2.109). 실패는 삼키지 않고 subscribe 상태로 드러난다. */
export async function armRealtime(): Promise<void> {
  try { await supabase.realtime.setAuth(); } catch { /* subscribe 상태가 실패를 말한다 */ }
}

// JWT는 1시간이면 만료된다. 한 시간 넘는 러닝은 실제로 존재하므로, 갱신 때마다 소켓을 다시
// 무장시키지 않으면 **달리는 도중에** 위치 공유가 끊긴다 — 그리고 그건 '신호 없음'처럼 보인다.
let authHooked = false;
export function hookTokenRefresh(): void {
  if (authHooked) return;
  authHooked = true;
  supabase.auth.onAuthStateChange((event) => {
    if (event === 'TOKEN_REFRESHED' || event === 'SIGNED_IN') void supabase.realtime.setAuth();
  });
}

/** 보호자 라이브 지도가 말해야 하는 링크 상태. 'denied'는 서버가 명시적으로 거절했을 때만 —
 *  네트워크 문제를 '권한 없음'이라고 부르는 것도 지어낸 주장이다. */
export type LiveLinkState = 'connecting' | 'live' | 'denied' | 'error';

function deniedLike(err: unknown): boolean {
  const m = String((err as Error)?.message ?? err ?? '').toLowerCase();
  return m.includes('unauthorized') || m.includes('forbidden') || m.includes('policy')
    || m.includes('permission') || m.includes('not authorized');
}

let pubCh: ReturnType<typeof supabase.channel> | null = null;
let pubId: string | null = null;
let pubJoined = false;
let pubLastAt = 0;

export function publishPos(bookingId: string, pos: LivePos): void {
  if (!pubCh || pubId !== bookingId) {
    if (pubCh) supabase.removeChannel(pubCh);
    pubJoined = false;
    pubLastAt = 0;
    pubCh = supabase.channel(RUN_TOPIC(bookingId), REALTIME_PRIVATE);
    pubId = bookingId;
    hookTokenRefresh();
    // 무장 → 구독 순서를 지킨다. 그 사이 픽스는 아래 `!pubJoined` 가드가 흘려보내고,
    // 2초 뒤 다음 픽스가 어차피 온다. **공개 채널로 떨어지는 폴백은 없다.**
    const ch = pubCh;
    void armRealtime().then(() => {
      if (pubCh !== ch) return;   // 그 사이 부킹이 바뀌었다
      ch.subscribe((status) => { pubJoined = status === 'SUBSCRIBED'; });
    });
  }
  // 채널 조인 전 전송은 스킵 (REST 폴백 경고 방지 — 2초마다 다음 픽스가 어차피 온다)
  if (!pubJoined) return;
  const now = Date.now();
  if (now - pubLastAt < PUB_MIN_MS) return;
  pubLastAt = now;
  pubCh.send({ type: 'broadcast', event: 'pos', payload: pos }).catch(() => {});
}

export function stopPublishing(): void {
  if (pubCh) supabase.removeChannel(pubCh);
  pubCh = null;
  pubId = null;
  pubLastAt = 0;
}

// 러너 위치 구독 — 해제 함수 반환
export function subscribePos(
  bookingId: string,
  onPos: (p: LivePos) => void,
  onState?: (s: LiveLinkState) => void,
): () => void {
  const ch = supabase
    .channel(RUN_TOPIC(bookingId), REALTIME_PRIVATE)
    .on('broadcast', { event: 'pos' }, ({ payload }) => onPos(payload as LivePos));
  let dropped = false;
  hookTokenRefresh();
  onState?.('connecting');
  void armRealtime().then(() => {
    if (dropped) return;
    ch.subscribe((status, err) => {
      if (status === 'SUBSCRIBED') onState?.('live');
      // 거절과 장애를 합치지 않는다: 화면이 둘에 대해 다른 말을 해야 하기 때문이다.
      else if (status === 'CHANNEL_ERROR') onState?.(deniedLike(err) ? 'denied' : 'error');
      else if (status === 'TIMED_OUT') onState?.('error');
    });
  });
  return () => { dropped = true; supabase.removeChannel(ch); };
}

// ---------- 클럽 러닝 멀티 브로드캐스트 (2026-08-02) ----------
// 클럽 위탁 러닝은 개 여러 마리 = 부킹 여러 개 = 보호자 라이브 채널 여러 개.
// 싱글톤 publishPos(1:1 전용)를 건드리지 않고, 수명은 호출측(클럽 런 화면)이 관리한다.
export function createPosPublisher(bookingIds: string[]): { publish: (pos: LivePos) => void; stop: () => void } {
  hookTokenRefresh();
  const chs = bookingIds.map((id) => {
    // 같은 결함의 세 번째 자리 — 클럽 러닝은 러너 하나가 보호자 채널 N개로 방송한다.
    const c = { joined: false, ch: supabase.channel(RUN_TOPIC(id), REALTIME_PRIVATE) };
    void armRealtime().then(() => {
      c.ch.subscribe((status: string) => { c.joined = status === 'SUBSCRIBED'; });
    });
    return c;
  });
  let lastAt = 0;
  return {
    publish: (pos) => {
      const now = Date.now();
      if (now - lastAt < PUB_MIN_MS) return; // same 3s throttle as the 1:1 publisher
      lastAt = now;
      for (const c of chs) {
        if (c.joined) c.ch.send({ type: 'broadcast', event: 'pos', payload: pos }).catch(() => {});
      }
    },
    stop: () => { for (const c of chs) supabase.removeChannel(c.ch); },
  };
}
