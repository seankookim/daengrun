import { useDisplayFont } from '../../src/lib/displayFont';
import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, AppState, KeyboardAvoidingView, Linking, Modal, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Avatar, Icon, Row } from '../../src/components/ui';
import { traceKind } from '../../src/components/course-detail';
import { addRunEvent, ensureThread, fetchBookingAddress, fetchCurrentRunnerJobId, fetchMeetupInfo, fetchRouteById, fetchRunMeta, fetchRunStartedAt, fetchRunTrace, MeetupInfo, notifyKmMilestone, PickupAddress, RunEventKind, saveRunTrace, sendChatMessage, sendChatPhoto, settleRun, startRunServer, uploadRunPhoto } from '../../src/lib/api';
import { GeoPoint, getNaverMap, getTraceSnapshot, getTrackPermission, mergeFixes, publishPos, resetTrace, seedTrace, smoothTrace, startTracking, stopPublishing, TrackHandle, TrackMode, TrackSnapshot } from '../../src/lib/geo';
import { haversineM, nearestOnTrace, rotateLoopAtEntry } from '../../src/lib/route-geom';
import { haptic } from '../../src/lib/haptics';
import { notifyLocal } from '../../src/lib/push';
import { clampSuggest, PACE_WINDOW_MS, PaceState, paceState, windowPaceSec } from '../../src/lib/pace';
import { endRunActivity, RunLAProps, startRunActivity, updateRunActivity } from '../../src/lib/runActivity';
import { useNumFont } from '../../src/lib/fonts';
import { EndReason, payoutFor, RouteInfo, runnerJob, runResult } from '../../src/store';
import { colors, lilac, paper } from '../../src/theme';

const REASON_MAP = { dog: 'dog_condition', owner: 'owner_request', runner: 'runner_personal' } as const;

// ---------- K7 코스 지도 상수/타입 ----------
// 대시 패턴 에셋. `patternImage`는 선 두께에 맞춰 축소되므로 24×8 잉크 사각형이 두께 4pt에서
// 12×4 눈금이 되고, patternInterval이 그 사이 간격을 준다. 선 본체를 흰색으로 두면 눈금 사이가
// 그대로 흰 케이싱이 되어 "인쇄된 코스도" 읽기가 성립한다. (색은 paper.ink #111111 — 신규 색 0개.)
// 앵커 = 회전 사각형(다이아몬드). 기본 네이버 핀은 '검색 결과'를 뜻해서 만남 장소로 읽히지 않는다.
const ROUTE_ANCHOR = require('../../assets/route-anchor.png');
// 입구 도착 판정 반경(m). route-geom의 off-route 기본값과 같은 수다 — 지배적 오차는 GPS 지터가
// 아니라 코너 컷(한 세그먼트가 굽이를 가로지름)이라, 더 좁히면 곡선마다 오판이 난다
// (route-geom.ts:20-22). 이 값은 **표시**에만 쓰이고 거리·정산에는 닿지 않는다.
const ENTRY_REACHED_M = 40;
// '닫힌 루프' 임계값(m). api.ts의 CLOSURE_MAX_M(디스커버리 게이트)과 같은 수를 쓴다 — 한 화면만
// 다른 '닫힘' 정의를 갖게 하지 않는다. route-geom의 기본값(25)보다 느슨하므로 명시적으로 넘긴다.
const LOOP_CLOSURE_M = 50;

type CamMode = 'approach' | 'fit' | 'follow' | 'free';
type LatLng = { latitude: number; longitude: number };
/** getNaverMap()이 동적 require라 컴포넌트가 any다 — ref로 쓰는 표면만 여기 좁게 적는다. */
interface NaverMapHandle {
  animateCameraTo: (p: LatLng & { zoom?: number; duration?: number }) => void;
  animateCameraWithTwoCoords: (p: { coord1: LatLng; coord2: LatLng; duration?: number }) => void;
  cancelAnimation: () => void;
  setLocationTrackingMode: (m: 'None' | 'NoFollow' | 'Follow' | 'Face') => void;
}

// Runner-side live run: real GPS distance (background-capable since 2026-08-08), event
// stamps, photo snaps, pinned owner chat.
//
// Tracking law (Sean, 2026-08-08): a run may not start unless distance can be recorded
// continuously — screen locked, phone pocketed. Anything short of TrackMode 'background'
// blocks the start and says why, because a truncated trace is a short payout and the runner
// only finds out at settlement. There is no demo-distance path any more.
//
// [paper repaint 2026-08-11] The LIVE run is a Peak (§7b) — calmer, not smaller. Light
// chrome (map area, status plates, progress) goes paper; the control panel and end-run
// sheets stay DARK as the run-world artifact, de-greened from forest to neutral ink with
// a coral hairline seam. Kept: every GPS/permission honest state and loud-fail strip,
// the Korean event stamp chips (fresh de-emoji pass), volt = personal run semantics,
// coral progress fill (LIVE = watch). Retired: rounded chrome, opacity press/busy paints
// (labels already swap), display font on the sheet button (budget = main CTA once).
// Logic frozen: tracking singleton, settle retry loop, overrun ceiling, Live Activity.

const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};
// 권장 caption — the value is already sec/km, so no division. Same M'SS" grammar as paceStr.
const suggestStr = (sec: number) => `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"`;
const PACE_CHIP_LABEL: Record<'good' | 'slow', string> = { good: '페이스 양호', slow: '권장보다 느려요' };
const PACE_CHIP_A11Y: Record<'good' | 'slow', string> = {
  good: '페이스 상태: 양호',
  slow: '페이스 상태: 권장보다 느림',
};

// Rolling-window pairs for the pace state (plan §1/§5). The app's single trace buffer is the
// source, and the window's DISTANCE is measured by mergeFixes — the same billable rule that
// pays the runner. A second implementation here would be a second, drifting truth. Two pairs
// describe the window: its first accepted point (0) and its last (km accumulated inside it).
const paceWindowPairs = (nowMs: number): { t: number; km: number }[] => {
  const { trace } = getTraceSnapshot();
  if (trace.length < 2) return [];
  const cutoff = nowMs - PACE_WINDOW_MS;
  const win = trace.filter((p) => p.t >= cutoff);
  if (win.length < 2) return [];
  const { addedKm } = mergeFixes([], win);
  return [{ t: win[0].t, km: 0 }, { t: win[win.length - 1].t, km: addedKm }];
};

export default function ActiveRun() {
  const df = useDisplayFont(); // 디스플레이 서체 — 러닝 시작/종료 CTA
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  // Booking context is the ONLY source of dog name and target distance — the runRequests
  // mock fallback is retired (fake-inventory 2026-08-11). loading != error != no booking:
  // on error the strip below says so and offers retry.
  const [infoStatus, setInfoStatus] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle');
  const dogName = info?.dogName ?? null;
  // null target = unknown. A guessed threshold must never move money: with targetKm null the
  // auto-settle and overrun ceiling are OFF and the run can only end via the manual end sheet.
  const targetKm = info?.km ?? null;
  const [running, setRunning] = useState(false);
  const [sec, setSec] = useState(0);
  const [endSheet, setEndSheet] = useState(false);
  const settled = useRef(false); // 중복 정산 방지 (자동완주 + 수동종료 레이스)
  // Foreground/background truth. Money is never settled from the background (§5.4), and the
  // buffer is re-read on every return to the foreground rather than trusted incrementally.
  const [appActive, setAppActive] = useState(AppState.currentState === 'active');
  useEffect(() => {
    const sub = AppState.addEventListener('change', (st) => setAppActive(st === 'active'));
    return () => sub.remove();
  }, []);

  // 레이아웃 A/B — 'panel'(하단 고정 패널) vs 'island'(지도 위 플로팅 카드). ⧉ 토글, 선택 유지.
  const [layout, setLayout] = useState<'panel' | 'island'>('panel');
  useEffect(() => {
    try {
      const AS = require('@react-native-async-storage/async-storage').default;
      AS.getItem('@runLayout').then((v: string | null) => { if (v === 'island') setLayout('island'); }).catch(() => {});
    } catch { /* no-op */ }
  }, []);
  const toggleLayout = () => {
    const next = layout === 'panel' ? 'island' : 'panel';
    setLayout(next);
    try {
      const AS = require('@react-native-async-storage/async-storage').default;
      AS.setItem('@runLayout', next).catch(() => {});
    } catch { /* no-op */ }
  };
  const [evCounts, setEvCounts] = useState<Record<string, number>>({});

  // 러닝 이벤트 원탭 — 기록 + 보호자 즉시 알림 (응가 도장 = 케어 증거이자 건강 데이터)
  const fireEvent = (kind: Exclude<RunEventKind, 'photo'>) => {
    if (!runnerJob.bookingId) { Alert.alert('실예약에서만 기록돼요'); return; }
    haptic('light');
    setEvCounts((c) => ({ ...c, [kind]: (c[kind] ?? 0) + 1 }));
    addRunEvent(runnerJob.bookingId, kind).catch((e) => console.warn('[run] event:', e?.message ?? e));
  };

  // 러닝 스냅 — 카메라 우선 (현장의 순간), 촬영 즉시 보호자 채팅으로 사진+재미 메시지 직송.
  // 앨범은 카메라 거부/취소 시 폴백. base64 인코딩 동안 '전송 중' 표시 (멈춘 것처럼 보이던 문제).
  const [snapBusy, setSnapBusy] = useState(false);

  const funLine = (): string => {
    const k = km.toFixed(2);
    const t = fmt(sec);
    // Name the dog only when the real booking told us the name — no invented names.
    const lines = dogName
      ? [
          `${dogName}, ${k}km 지점에서 한 컷! ${t} · 오늘도 체력 적금 +1`,
          `${k}km 통과 중인 ${dogName} — 꼬리 텐션 최상입니다 (${t})`,
          `지금 ${dogName} 표정 보세요! ${k}km 달리고 이 컨디션 · 체력 나이 -0.01살 적립 중`,
          `${dogName} 현장 소식: ${k}km · ${t} · 산소 가득 마시는 중`,
        ]
      : [
          `${k}km 지점에서 한 컷! ${t} · 오늘도 체력 적금 +1`,
          `${k}km 통과 중 — 꼬리 텐션 최상입니다 (${t})`,
          `현장 소식: ${k}km · ${t} · 산소 가득 마시는 중`,
        ];
    return lines[Math.floor(Math.random() * lines.length)];
  };

  const firePhoto = async () => {
    if (!runnerJob.bookingId) { Alert.alert('실예약에서만 기록돼요'); return; }
    const bid = runnerJob.bookingId;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      let res: any = null;
      const camPerm = await ImagePicker.requestCameraPermissionsAsync().catch(() => ({ granted: false }));
      if (camPerm.granted) {
        res = await ImagePicker.launchCameraAsync({ quality: 0.5, base64: true });
      }
      if (!res || res.canceled) {
        // 카메라 불가/취소 → 앨범 폴백
        const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
        if (!perm.granted) return;
        res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.5, base64: true, selectionLimit: 1 });
      }
      if (res.canceled || !res.assets?.[0]?.base64) return;
      const b64 = res.assets[0].base64;
      setSnapBusy(true);
      haptic('light');
      await uploadRunPhoto(bid, b64);
      await addRunEvent(bid, 'photo'); // 알림: '새 사진 도착'
      // 보호자 채팅으로 직송 — 사진 + 위치/거리/재미 한 줄
      const threadId = await ensureThread(bid);
      await sendChatPhoto(threadId, b64);
      await sendChatMessage(threadId, funLine());
      setEvCounts((c) => ({ ...c, photo: (c.photo ?? 0) + 1 }));
      haptic('success');
    } catch (e) {
      Alert.alert('전송 실패', (e as Error).message);
    } finally {
      setSnapBusy(false);
    }
  };

  // ---------- 실GPS 거리 (핵심 실화) ----------
  // 거리는 geo.ts의 단일 버퍼가 소유한다 — 포그라운드 워처와 백그라운드 태스크가 같은 싱크로 들어오고,
  // km 누적은 mergeFixes 한 곳에서만 일어난다. 이 화면은 스냅샷을 그릴 뿐 산수를 하지 않는다.
  const [gps, setGps] = useState(false);            // 백그라운드 추적 가동 중
  const [gpsKm, setGpsKm] = useState(0);
  const [lastPos, setLastPos] = useState<GeoPoint | null>(null);
  const [trackMode, setTrackMode] = useState<TrackMode | null>(null); // null = 아직 시도 전
  const [rationale, setRationale] = useState(false); // OS 시트 전 1회 설명 (한 번뿐인 프롬프트라)
  const [starting, setStarting] = useState(false);
  const [saveLag, setSaveLag] = useState(false);     // 트레이스 저장 실패를 침묵시키지 않는다
  const [ceilingHit, setCeilingHit] = useState(false); // 정산 밴드 상한 근접 → 기록 정지
  const maps = getNaverMap(); // 네이버 지도 (2026-07-29) — 미탑재 빌드는 대기 배경 폴백
  const trace = useRef<GeoPoint[]>([]);
  const lastMilestone = useRef(0);
  const handle = useRef<TrackHandle | null>(null);
  const startedAtMs = useRef<number | null>(null);
  const modeRef = useRef<TrackMode | null>(null);
  const overrunNotified = useRef(false);

  const km = gpsKm;
  const remaining = targetKm != null ? Math.max(targetKm - km, 0) : null;
  const progress = targetKm != null ? Math.min(km / targetKm, 1) : 0;
  // settle-run 400 밴드(plannedKm*2+2)의 코앞. 넘기면 재시도 루프로도 못 푸는 400이라 예약이 좌초된다.
  // Unknown target → no client ceiling (the server band still guards settlement).
  const ceilingKm = targetKm != null ? targetKm * 2 + 2 - 0.5 : null;

  // Booking context load — retryable, and its failure is announced (blockStrip below).
  const loadInfo = useCallback((bid: string) => {
    setInfoStatus('loading');
    fetchMeetupInfo(bid)
      .then((i) => { setInfo(i); setInfoStatus('ready'); })
      .catch((e) => { console.warn('[run] info:', e?.message ?? e); setInfoStatus('error'); });
  }, []);

  const refreshStartedAt = useCallback(() => {
    const bid = runnerJob.bookingId;
    if (!bid) return;
    fetchRunStartedAt(bid)
      .then((iso) => { if (iso) startedAtMs.current = new Date(iso).getTime(); })
      .catch(() => { /* 다음 복귀에 다시 시도 */ });
  }, []);

  // id 복원 — 리로드로 유실돼도 서버의 active 예약으로 정산이 연결되게.
  // + 트레이스 시드 (2026-08-08): 재진입 시 km이 0부터 다시 시작해 서버 트레이스를 덮어쓰던 구멍.
  useEffect(() => {
    // 공용 버퍼는 앱 전역 싱글턴이다 — 이전 러닝(클럽 포함)의 점을 물려받지 않게 먼저 비운다
    resetTrace();
    (async () => {
      if (!runnerJob.bookingId) {
        try {
          const id = await fetchCurrentRunnerJobId();
          if (id) runnerJob.bookingId = id;
        } catch (e) { console.warn('[run] resolve:', (e as Error)?.message); }
      }
      const bid = runnerJob.bookingId;
      if (!bid) return;
      loadInfo(bid);
      refreshStartedAt();
      try {
        const saved = await fetchRunTrace(bid);
        if (saved.length > 1) {
          // 서버는 t를 초로 저장한다 (club_save_run_trace와 동일 규약) — 밀리초로 되돌린다.
          const snap = seedTrace(saved.map((p) => ({ lat: p.lat, lng: p.lng, t: p.t > 1e11 ? p.t : p.t * 1000 })));
          if (snap) {
            trace.current = snap.trace;
            setGpsKm(snap.km);
            setLastPos(snap.last);
            lastMilestone.current = Math.floor(snap.km);
          }
        }
      } catch (e) { console.warn('[run] hydrate:', (e as Error)?.message); }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 단일 싱크의 구독자 — 여기서 하는 일은 그리기·브로드캐스트·마일스톤뿐 (거리 산수 없음)
  const onTrack = useCallback((snap: TrackSnapshot) => {
    // Runner-side stale clock (plan §1): the sink only calls back when something survived the
    // gates, so this stamp is exactly "last ACCEPTED fix" — nothing else in here changes.
    lastAcceptedAt.current = Date.now();
    trace.current = snap.trace;
    setLastPos(snap.last);
    setGpsKm(snap.km);
    const crossed = Math.floor(snap.km);
    if (crossed > lastMilestone.current && runnerJob.bookingId) {
      lastMilestone.current = crossed;
      notifyKmMilestone(runnerJob.bookingId, crossed).catch(() => {});
      haptic('success');
    }
    if (runnerJob.bookingId) {
      publishPos(runnerJob.bookingId, {
        lat: snap.last.lat, lng: snap.last.lng, km: snap.km, paceSec: null,
        mode: modeRef.current ?? undefined,
      });
    }
  }, []);

  // ═══════════════ K7 · 코스 지도 카메라 계약 ═══════════════
  // 스파이크: docs/design/k7-map-primitives-spike.md (측정본).
  //
  // 컨트롤드 `camera` 프롭 **은퇴**. 매 GPS 픽스마다 카메라를 다시 밀어 넣으면 러너의 손가락과
  // 화면이 싸운다 — 팬을 하는 순간 다음 픽스가 되감는다. 라이브러리 문서도 같은 말을 한다:
  // "initialCamera는 camera를 사용하지 않을 때만 사용해야합니다." 그래서 초기 카메라 1회 +
  // ref 명령형 이동이고, 세 모드가 전부 네이티브 호출이다.
  //
  // ⚠ 오프루트 감지·진행 투영은 **여기 없다** (T5, 실제 이탈 사고 관측이 트리거).
  // 이 지도는 코스를 보여줄 뿐 길을 안내하지 않는다 — 개를 다루는 손으로 화면을 보게 만드는
  // 것이 이 제품이 피하려는 바로 그것이다.
  //
  // ⚠ 앵커는 `routes.anchor_lat/lng`를 읽지 않는다. 0078이 그 컬럼을 "근사값 — 소비 금지"로
  // 못박았고, 0082의 승격이 첫 검증 런의 트레이스 시작점으로 그 값을 확정한다. 그러니 실측된
  // 트레이스의 **첫 점**이 곧 확정된 앵커이고, 트레이스가 없으면 앵커도 없다 —
  // 없는 좌표를 그리지 않는 것이 이 화면의 유일한 정직한 선택지다.
  const [routeGeo, setRouteGeo] = useState<RouteInfo | null>(null);
  const [routeState, setRouteState] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle');
  useEffect(() => {
    const rid = info?.routeId;
    if (!rid) return;
    let alive = true;
    setRouteState('loading');
    // fetchRouteById는 라이프사이클 무관으로 읽는다 — 정지된 코스를 예약해 둔 러너가
    // 브리핑에서 '찾을 수 없음'을 만나지 않게 (K2). 실패해도 GPS·정산은 건드리지 않는다.
    fetchRouteById(rid)
      .then((r) => { if (alive) { setRouteGeo(r); setRouteState('ready'); } })
      .catch((e) => { if (alive) { console.warn('[run] route:', e?.message ?? e); setRouteState('error'); } });
    return () => { alive = false; };
  }, [info?.routeId]);

  const routeCoords = useMemo(
    () => (routeGeo?.trace ?? []).map((p) => ({ latitude: p.lat, longitude: p.lng })),
    [routeGeo],
  );
  /** 루프 전체를 담는 두 모서리 — animateCameraWithTwoCoords가 정확히 이 두 점을 받는다. */
  const routeBox = useMemo(() => {
    if (routeCoords.length < 2) return null;
    let n = -90, s = 90, e = -180, w = 180;
    routeCoords.forEach((c: LatLng) => {
      n = Math.max(n, c.latitude); s = Math.min(s, c.latitude);
      e = Math.max(e, c.longitude); w = Math.min(w, c.longitude);
    });
    return { nw: { latitude: n, longitude: w }, se: { latitude: s, longitude: e } };
  }, [routeCoords]);
  const anchor = routeCoords.length > 0 ? routeCoords[0] : null;

  // ═══════════════ 픽업 → 입구 → 랩 (Sean 재정 #14, 2026-08-19) ═══════════════
  // "픽업 지점은 보호자가 찍은 곳이고, 앱은 거기서 코스 **위**의 가장 가까운 점(= 입구)까지 러너를
  //  인도한다. 랩은 그 입구에서 시작한다."
  //
  // ⚠ 이 슬라이스는 돈을 1mm도 움직이지 않는다. `actual_km`은 오늘과 똑같이 추적 버퍼 전체를
  // 뜻하고, 자동완주·오버런 천장·정산은 손대지 않았다. 접근 구간이 예약 km에 포함되는지는
  // Sean에게 따로 올라간 결정이다 — 지도가 먼저 정직해지는 것이 그 결정을 막지 않는다.
  //
  // ⚠ entryIdx는 **화면 로컬**이다. 목록 화면의 trace_thumb(≤50점)와 이 화면의 trace(≤200점)는
  // 다른 배열이라 인덱스가 서로를 가리키지 못한다 (route-geom.ts:24-28). 그래서 다른 화면이 계산한
  // 인덱스를 믿지 않고 여기서 다시 계산한다.
  const [pickup, setPickup] = useState<{ s: 'loading' } | { s: 'ok'; a: PickupAddress | null } | { s: 'err' }>({ s: 'loading' });
  const [pickupTry, setPickupTry] = useState(0);
  useEffect(() => {
    // infoStatus === 'ready'가 곧 "runnerJob.bookingId가 해소됐다"의 신호다 — loadInfo는 bid 없이는
    // 불리지 않는다. bookingId 자체는 모듈 값이라 의존성에 걸 수 없다.
    if (infoStatus !== 'ready') return;
    const bid = runnerJob.bookingId;
    if (!bid) return;
    let alive = true;
    setPickup({ s: 'loading' });
    fetchBookingAddress(bid)
      .then((a) => { if (alive) setPickup({ s: 'ok', a }); })
      .catch((e) => {
        // 실패를 '주소 없음'으로 접으면 러너는 재시도 버튼을 영영 못 본다 (meetup.tsx:109-121과 같은 규율)
        console.warn('[run] pickup:', e?.message ?? e);
        if (alive) setPickup({ s: 'err' });
      });
    return () => { alive = false; };
  }, [infoStatus, pickupTry]);

  /** 보호자가 찍은 핀. 행은 있는데 lat/lng가 NULL인 것은 '못 불러왔다'가 아니라 '핀이 없다'이다. */
  const pickupLL = useMemo(() => {
    const a = pickup.s === 'ok' ? pickup.a : null;
    return a && a.lat != null && a.lng != null ? { lat: a.lat, lng: a.lng } : null;
  }, [pickup]);
  const traceLL = useMemo(() => routeGeo?.trace ?? [], [routeGeo]);
  /** 입구 = 픽업에서 코스 **선 위**로 내린 수선의 발 (정점 최근접이 아니라 세그먼트 투영). */
  const entry = useMemo(() => (pickupLL ? nearestOnTrace(pickupLL, traceLL) : null), [pickupLL, traceLL]);
  const entryCoord = useMemo(
    () => (entry ? { latitude: entry.point.lat, longitude: entry.point.lng } : null),
    [entry],
  );
  // 루프 회전은 **닫힌 루프에만**. rotateLoopAtEntry는 열린 경로면 입력과 같은 참조를 돌려주므로
  // 그 항등 비교가 곧 '이 코스는 닫혔는가'의 답이다 (route-geom.ts:176-180) — closureM을 한 번 더
  // 돌리지 않고 같은 판정을 쓴다.
  const lapLL = useMemo(
    () => (entry ? rotateLoopAtEntry(traceLL, entry, LOOP_CLOSURE_M) : traceLL),
    [entry, traceLL],
  );
  const rotated = entry != null && lapLL !== traceLL;
  const lapCoords = useMemo(
    () => (rotated ? lapLL.map((p) => ({ latitude: p.lat, longitude: p.lng })) : routeCoords),
    [rotated, lapLL, routeCoords],
  );

  // 입구 도착 — 한 번 켜지면 다시 꺼지지 않는다. **새 구독자를 만들지 않는다**: onTrack이 이미
  // 세팅하는 lastPos(마지막으로 게이트를 통과한 픽스)를 읽을 뿐이다. 추적 싱글턴은 동결이다.
  const [atEntry, setAtEntry] = useState(false);
  useEffect(() => {
    if (atEntry || !entry || !lastPos) return;
    if (haversineM({ lat: lastPos.lat, lng: lastPos.lng }, entry.point) <= ENTRY_REACHED_M) {
      setAtEntry(true);
      haptic('success');
    }
  }, [atEntry, entry, lastPos]);

  /** 입구까지 남은 **직선** 거리(m). 픽스가 아직 없으면 픽업→입구 거리로 답한다 — 둘 다 실좌표
   *  두 점 사이의 실측이고, 어느 쪽도 도로 경로 길이가 아니다 (문구가 그렇게 말한다). */
  const entryDistM = useMemo(() => {
    if (!entry) return null;
    return lastPos ? haversineM({ lat: lastPos.lat, lng: lastPos.lng }, entry.point) : entry.distM;
  }, [entry, lastPos]);

  const mapRef = useRef<NaverMapHandle | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const [camMode, setCamMode] = useState<CamMode>('approach'); // 렌더용 (내 위치로 버튼)
  const camModeRef = useRef<CamMode>('approach');              // 로직용 (타임아웃 클로저가 낡지 않게)
  const fitDone = useRef(false);
  const setMode = useCallback((m: CamMode) => { camModeRef.current = m; setCamMode(m); }, []);

  // 초기 카메라는 **한 번만** 결정된다 (프롭이 아니라 씨앗이다).
  const initialCam = useRef<{ latitude: number; longitude: number; zoom: number } | null>(null);
  if (!initialCam.current) {
    if (lastPos) initialCam.current = { latitude: lastPos.lat, longitude: lastPos.lng, zoom: 16 };
    else if (anchor) initialCam.current = { ...anchor, zoom: 15 };
  }

  const follow = useCallback(() => {
    if (camModeRef.current === 'free') return; // 손가락이 먼저다 — 팬을 되감지 않는다
    setMode('follow');
    mapRef.current?.setLocationTrackingMode('Follow');
  }, [setMode]);

  // 접근 — 러너와 앵커가 한 화면에. 정확히 두 좌표라 두-좌표 fit이 이 일 자체다.
  // 의존성이 `lastPos`가 아니라 `hasPos`(불리언)인 것은 **의도**다: 첫 픽스가 들어온
  // 순간 한 번 다시 맞추고, 그 뒤 픽스마다 재적용하지 않는다 — 그게 곧 컨트롤드 카메라다.
  //
  // 재정 #14: 접근 구도가 맞춰야 할 상대는 이제 **입구**다 (없으면 오늘처럼 트레이스 첫 점).
  // camTarget은 코스가 뜰 때와 픽업이 뜰 때 최대 두 번 바뀔 뿐이라, 의존성에 넣어도 "픽스마다
  // 카메라를 다시 민다"는 은퇴한 패턴으로 돌아가지 않는다 — 이 계약은 그대로다.
  const hasPos = lastPos != null;
  const camTarget = entryCoord ?? anchor;
  useEffect(() => {
    if (!mapReady || running || camModeRef.current === 'free') return;
    setMode('approach');
    if (lastPos && camTarget) {
      mapRef.current?.animateCameraWithTwoCoords({
        coord1: { latitude: lastPos.lat, longitude: lastPos.lng }, coord2: camTarget, duration: 700,
      });
    } else if (routeBox) {
      mapRef.current?.animateCameraWithTwoCoords({ coord1: routeBox.nw, coord2: routeBox.se, duration: 700 });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapReady, running, routeBox, hasPos, camTarget]);

  // 러닝 시작 = 루프 전체를 **한 번** 맞춰 보여주고, 그다음 카메라를 러너에게 돌려준다.
  useEffect(() => {
    if (!mapReady || !running || fitDone.current) return;
    fitDone.current = true;
    if (!routeBox) { follow(); return; }
    setMode('fit');
    mapRef.current?.animateCameraWithTwoCoords({ coord1: routeBox.nw, coord2: routeBox.se, duration: 900 });
    const t = setTimeout(follow, 2400); // follow()가 free를 존중하므로 중간에 팬해도 안전하다
    return () => clearTimeout(t);
  }, [mapReady, running, routeBox, follow, setMode]);

  const recenter = () => {
    haptic('light');
    // ⚠ 러닝 전에는 위치 추적 모드를 **켜지 않는다**. SDK의 Follow는 자기 위치 소스를 붙이고,
    // 그건 OS 권한 시트를 띄운다 — 이 앱에서 그 시트는 단 한 번뿐이고, beginRun의 rationale이
    // 그 앞에 서 있어야 한다(거부되면 설정에서만 되돌릴 수 있다). 그래서 여기선 접근 구도로만 되돌린다.
    if (!running) {
      setMode('approach');
      if (lastPos && camTarget) {
        mapRef.current?.animateCameraWithTwoCoords({
          coord1: { latitude: lastPos.lat, longitude: lastPos.lng }, coord2: camTarget, duration: 500,
        });
      } else if (routeBox) {
        mapRef.current?.animateCameraWithTwoCoords({ coord1: routeBox.nw, coord2: routeBox.se, duration: 500 });
      } else if (lastPos) {
        mapRef.current?.animateCameraTo({ latitude: lastPos.lat, longitude: lastPos.lng, zoom: 16, duration: 500 });
      }
      return;
    }
    setMode('follow');
    mapRef.current?.setLocationTrackingMode('Follow');
  };

  // 코스 오버레이에 대한 정직 고지 — 어느 것도 GPS·정산을 막지 않는다 (자문일 뿐).
  const routeNote = ((): { text: string; warn: boolean } | null => {
    if (routeGeo?.status === 'suspended') return { text: '이 코스는 점검을 위해 일시 중단됐어요', warn: true };
    if (routeState === 'error') return { text: '코스 선을 불러오지 못했어요 — 기록에는 영향 없어요', warn: false };
    // 행이 없는 것과 선이 없는 것은 다른 사실이다 — 같은 문장으로 덮지 않는다
    if (routeState === 'ready' && !routeGeo) return { text: '배정된 코스 정보를 찾을 수 없어요 — 기록에는 영향 없어요', warn: false };
    if (routeState === 'ready' && routeCoords.length < 2) {
      // 트레이스가 없으면 앵커도 없다 — '앵커만 표시돼요'라고 말하면 그게 거짓이 된다.
      return { text: '이 코스는 아직 실측 전이에요 — 코스 선 없이 내 기록만 그려져요', warn: false };
    }
    // 선은 그려지지만 아직 아무도 개와 함께 달려보지 않은 경우. 러너에게 이걸 말하지 않으면
    // 선을 실측 코스로 믿고 따라가게 된다 — 그건 우리가 만든 오해다 (0082 source='algo').
    // ⚠ '점선'이라 부르지 않는다: 대시는 f0ceed4에서 은퇴했고, 러너에게 화면에 없는 것을
    // 찾으라고 말하는 순간 안내가 아니라 혼란이 된다.
    if (routeGeo && traceKind(routeGeo) === 'planned') {
      return { text: '이 선은 예정 경로예요 — 아직 실측 전이라 현장과 다를 수 있어요', warn: false };
    }
    return null;
  })();

  // ── 픽업 → 입구 안내 (재정 #14). 조용하게·정직하게: ETA 없음, 도로 안내 주장 없음, 새 버튼 없음.
  //    이 스트립은 어떤 상태에서도 GPS·기록·정산을 막지 않는다 (자문이다).
  const guide = ((): { text: string; note?: string; action?: string; onAction?: () => void; warn?: boolean } | null => {
    if (pickup.s === 'loading') return null; // 로딩은 아무 말도 하지 않는다 — 곧 답이 온다
    if (pickup.s === 'err') {
      // 통신 실패를 '핀 없음'으로 위장하지 않는다 — 실패는 실패로, 재시도와 함께
      return { text: '픽업 위치를 불러오지 못했어요', action: '다시 시도', onAction: () => setPickupTry((t) => t + 1), warn: true };
    }
    if (!pickupLL) {
      // 핀이 없으면 입구를 계산할 방법이 **없다**. trace[0]을 '입구'라고 부르는 순간 그건
      // 정확해 보이면서 틀린 문장이 된다 — 코스 시작점이라고 그대로 말한다.
      // 코스 선조차 없으면 routeNote가 이미 그 사실을 말하므로 여기선 침묵한다.
      // 러닝을 시작하면 시작점 마커는 사라지므로(오늘 그대로) '안내해요'는 그때 거짓이 된다 —
      // 그 뒤로는 사실만 남긴다.
      if (routeCoords.length <= 1) return null;
      return running
        ? { text: '픽업 위치가 없어 입구를 계산할 수 없어요' }
        : { text: '픽업 위치가 없어 입구를 계산할 수 없어요 — 코스 시작점으로 안내해요' };
    }
    if (!entry || entryDistM == null) return null; // 핀은 있으나 트레이스가 없다 → routeNote의 몫
    // 회전하지 않았다 = 트레이스의 첫 점과 끝 점이 만나지 않는다 = 시작이 정해진 열린 코스다.
    // 트레이스에서 그대로 읽히는 사실일 때만 말한다.
    const openNote = rotated ? undefined : '시작점이 정해진 코스예요';
    if (atEntry) {
      const rkm = routeGeo?.km;
      return {
        text: rkm != null ? `입구 도착 — 여기서 랩 시작 · 코스 ${rkm}km` : '입구 도착 — 여기서 랩 시작',
        note: openNote,
      };
    }
    return {
      text: `입구까지 직선 ${Math.round(entryDistM)}m`,
      // 실도로 경로가 아니라는 사실을 한 번, 작게. docs/routes/strava/route-guidance.mjs는 라이브
      // GPS 스트림에 대해 한 번도 돌아본 적이 없다 — '길 안내'라고 부르면 우리가 만든 오해가 된다.
      note: ['직선 거리예요 · 길 안내는 실도로 검증 전', openNote].filter(Boolean).join(' · '),
    };
  })();

  // 언마운트 정리 — 추적 태스크는 화면이 사라져도 OS에 남는다
  useEffect(() => () => { handle.current?.stop(); handle.current = null; }, []);

  // 포그라운드 복귀 정합 — 백그라운드 km을 포그라운드 누계에 '더하지' 않는다. 병합 버퍼가 유일 진실이다.
  useEffect(() => {
    if (!appActive || !running) return;
    const snap = getTraceSnapshot();
    trace.current = snap.trace;
    setGpsKm(snap.km);
    if (snap.trace.length > 0) setLastPos(snap.trace[snap.trace.length - 1]);
    refreshStartedAt(); // 경과는 로컬 카운터가 아니라 runs.started_at 기준으로 되맞춘다
  }, [appActive, running, refreshStartedAt]);

  // ---------- 라이브 액티비티 (다이내믹 아일랜드 + 잠금화면) ----------
  const laProps = (): RunLAProps => ({
    dogName: dogName ?? '반려견',
    km: km.toFixed(2),
    targetKm: targetKm != null ? String(targetKm) : '—',
    pace: paceStr(sec, km),
    elapsed: fmt(sec),
    eventLine: [
      evCounts.poop ? `응가 ${evCounts.poop}` : '',
      evCounts.snack ? `간식 ${evCounts.snack}` : '',
      evCounts.water ? `물 ${evCounts.water}` : '',
      evCounts.photo ? `사진 ${evCounts.photo}` : '',
    ].filter(Boolean).join(' · '),
    // '' = no claim (gate/stale/unknown) — the banner then renders no pill at all.
    paceState: pace,
  });
  const laStarted = useRef(false);
  const laLastUpdate = useRef(0);

  useEffect(() => {
    if (running && !laStarted.current) {
      laStarted.current = true;
      startRunActivity(laProps());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  // [2026-08-08] gpsKm를 의존성에 추가 — 잠금화면/다이내믹 아일랜드가 '실제로 라이브'가 되는 지점이다.
  // 예전엔 sec(=setInterval)에만 걸려 있었고, 백그라운드에서 타이머가 스로틀되면 배너가 얼어붙었다.
  // 백그라운드 픽스는 JS를 확실히 깨우므로(태스크 핸들러 → ingestFixes → 이 구독), km 변화가
  // 업데이트를 끈다. ActivityKit update()는 앱이 실행 중이기만 하면 백그라운드에서도 유효하다.
  useEffect(() => {
    if (!running || !laStarted.current) return;
    const now = Date.now();
    if (now - laLastUpdate.current < 5000) return; // 5초 스로틀
    laLastUpdate.current = now;
    updateRunActivity(laProps());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sec, gpsKm]);

  // 경과 — runs.started_at이 있으면 벽시계 기준 (백그라운드에서 타이머가 스로틀돼도 시간이 새지 않는다).
  // 데모 80배속 이중 속도 타이머는 데모 경로와 함께 퇴역 (2026-08-08).
  useEffect(() => {
    if (!running) return;
    const id = setInterval(() => {
      if (startedAtMs.current) setSec(Math.max(0, Math.round((Date.now() - startedAtMs.current) / 1000)));
      else setSec((s) => s + 1);
    }, 1000);
    return () => clearInterval(id);
  }, [running]);

  // ---------- 트레이스 저장 (러닝 중에) ----------
  // 2026-08-08 수정: 예전엔 settleRun 성공 '뒤'에 저장해서 _guard_run_cols가
  // run_frozen_after_settlement로 전부 거부했고, 그 에러는 console.warn으로 삼켜졌다 —
  // 1:1 트레이스는 사실상 한 번도 저장된 적이 없다. 부킹이 살아있는 동안 저장한다.
  const buildTracePts = (src: GeoPoint[]): { lat: number; lng: number; t: number }[] => {
    const pts: { lat: number; lng: number; t: number }[] = [];
    let lastT = -1;
    let prev: { lat: number; lng: number; t: number } | null = null;
    for (const p of src) {
      const t = Math.floor(p.t / 1000); // 서버 규약: 초 단위 단조
      if (t <= lastT) continue;
      if (prev) {
        const dist = Math.sqrt(((p.lat - prev.lat) * 111000) ** 2 + ((p.lng - prev.lng) * 88800) ** 2);
        if (dist / (t - prev.t) > 8) continue; // 서버 게이트와 같은 8m/s — 배치 전체 거부 예방
      }
      lastT = t;
      prev = { lat: p.lat, lng: p.lng, t };
      pts.push(prev);
    }
    return pts;
  };

  const saveTrace = useCallback(async () => {
    const bid = runnerJob.bookingId;
    if (!bid || trace.current.length < 2) return;
    const pts = buildTracePts(trace.current);
    if (pts.length < 2) return;
    try {
      await saveRunTrace(bid, pts);
      setSaveLag(false);
    } catch {
      setSaveLag(true); // 침묵하지 않는다 — 신호가 잡히면 다음 주기에 자동 재시도
    }
  }, []);

  useEffect(() => {
    if (!running) return;
    const id = setInterval(() => { saveTrace(); }, 60_000);
    return () => { clearInterval(id); saveTrace(); }; // 언마운트 시 최대 60초분 유실 방지
  }, [running, saveTrace]);

  // ---------- 오버런 봉쇄 (백그라운드 추적이 만든 새 실패 모드) ----------
  // 종료를 잊은 러너가 집까지 계속 기록하면 settle-run의 km > plannedKm*2+2 밴드에 걸려 400이 나고,
  // 재시도 루프로도 못 풀어 예약이 active로 좌초된다 (● LIVE 좀비의 재발).
  useEffect(() => {
    if (!running || !gps) return;
    if (targetKm != null && km >= targetKm && !overrunNotified.current && !appActive) {
      overrunNotified.current = true;
      notifyLocal('목표 거리에 도달했어요', '앱을 열어 러닝을 종료해주세요');
    }
    if (ceilingKm != null && km >= ceilingKm && !ceilingHit) {
      setCeilingHit(true);
      handle.current?.stop(); // 기록만 멈춘다 — 지금까지의 트레이스는 그대로 남는다
      handle.current = null;
      notifyLocal('정산 가능한 최대 거리에 근접했어요', '지금 러닝을 종료해주세요');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [km, running, gps, appActive]);

  // per-reason payout (docs/product-notes: all pay actual km — never incentivize pushing a hurt dog)
  const payoutByReason = (reason: EndReason): number => {
    const actual = payoutFor(km);
    // The remaining-50% guarantee is only *estimated* when the real target is known —
    // the server computes the actual amount either way (settleRun res.net).
    if (reason === 'owner' && targetKm != null) return actual + Math.round((payoutFor(targetKm) - actual) * 0.5);
    return actual; // dog / runner: actual km
  };

  // 실예약이면 서버 정산 (사유별 금액·드랍은 settle-run이 계산), 아니면 로컬 계산
  const settle = async (reason: EndReason, completed: boolean) => {
    if (settled.current) return;
    settled.current = true;
    const bid = runnerJob.bookingId;
    // 추적 종료 + 브로드캐스트 + 라이브 액티비티 정리
    await handle.current?.stop();
    handle.current = null;
    stopPublishing();
    // 종말 프레임은 판정을 들고 죽지 않는다 (plan §6 — no posthumous verdict; 러너 LA엔
    // phase가 없어 이 인자 하드셋이 보호자 쪽 SQL 하드셋의 미러다).
    endRunActivity({ ...laProps(), paceState: '' });
    const localPayout = completed ? payoutFor(km) : payoutByReason(reason);
    // dogName rides along from the real booking context (null when it never loaded —
    // the done screen then re-reads the booking or uses generic wording, never a fake name).
    // settled=false until the server says otherwise — the estimate never masquerades as income
    Object.assign(runResult, { km, sec, payout: localPayout, settled: false, completed, reason, bookingId: bid, dogName });

    if (bid && !gps) {
      // 정직 가드 — 실측되지 않은 거리로는 실예약을 정산하지 않는다.
      // (데모 거리 경로는 2026-08-08 퇴역했지만, 가드는 남긴다 — 정산은 실측만이라는 법 자체다.)
      settled.current = false;
      Alert.alert(
        'GPS 없이 정산할 수 없어요',
        '실예약 정산은 실측 거리로만 가능해요.\n설정에서 위치 권한을 켠 뒤 다시 시작해주세요.',
      );
      return;
    }
    if (bid) {
      // 트레이스는 정산 '전에' 저장한다 — settle_run_tx가 부킹을 completed로 만드는 순간
      // _guard_run_cols가 클라이언트 쓰기를 전부 거부한다 (저장 창이 닫힌다).
      await saveTrace();
      // 정산 재시도 루프 (2026-07-29) — 실패 시 예약이 active로 남아 좌초되던 문제.
      // 서버 트랜잭션은 전체 롤백이라 재시도 안전. 네트워크 블립('Failed to send a request')도 여기서 회복.
      const trySettle = async (): Promise<boolean> => {
        try {
          const res = await settleRun({
            booking_id: bid,
            end_reason: completed ? 'completed' : REASON_MAP[reason as keyof typeof REASON_MAP],
            actual_km: Number(km.toFixed(2)),
            duration_sec: sec,
            // The runner's OWN sentence, typed in the end sheet's 기록 step — never a canned
            // fallback. The old constant ('러너 판단: 컨디션 저하 관찰') shipped the same
            // fabricated observation to every owner's report card and propped up the
            // dog_condition charge waiver with a value no human ever wrote. If it is empty the
            // server's 400 must surface (settle retry alert) — an invented sentence is worse
            // than a visible failure.
            condition_note: reason === 'dog' ? conditionNote.trim() : undefined,
          });
          runResult.payout = res.net; // 서버가 계산한 실지급액
          runResult.settled = true;  // 이제서야 '수익'이라고 부를 수 있다
          runnerJob.bookingId = null;
          if (res.drop) Alert.alert('드랍 도착!', res.drop === 'pick' ? '픽 드랍 — 리워드 센터에서 선택하세요' : '보급 상자가 도착했어요');
          return true;
        } catch (e) {
          return new Promise((resolve) => {
            Alert.alert(
              '정산 실패',
              // [적대 리뷰 2026-08-11] 예전 카피는 '아무것도 반영되지 않았어요'라고 단정했다. 서버
              // 트랜잭션은 전체 롤백이지만, **응답이 유실된 경우**(네트워크 끊김·앱 종료)는 서버에서
              // 이미 커밋됐는데 클라만 실패로 본다 — 그때 이 문장은 거짓이고, 재시도는 '이미 정산'으로
              // 거절된다. 아는 것만 말한다: 대개는 반영되지 않았고, 재시도가 안전하며, 확인 경로가 있다.
              `${(e as Error).message}\n\n대부분의 경우 아무것도 반영되지 않았어요 — 재시도는 안전해요.\n재시도가 '이미 정산됐다'고 하면 정산은 끝난 거예요. 수익 화면에서 확인해주세요.`,
              [
                { text: '나중에 (추정치 표시)', style: 'cancel', onPress: () => resolve(false) },
                { text: '다시 시도', onPress: () => resolve(trySettle()) },
              ],
            );
          });
        }
      };
      await trySettle();
    }
    router.replace('/runner/done');
  };

  // The end sheet owns the whole decision (§7b — one surface). 이유 선택은 그대로 즉시 정산으로
  // 가고, 컨디션만 같은 시트 안에서 기록 스텝으로 넘어간다 (모달 위에 모달을 쌓지 않는다).
  const openEndSheet = () => { setEndStep('reason'); setEndSheet(true); };
  const closeEndSheet = () => {
    if (endBusy) return; // 정산 중에는 시트를 걷지 않는다
    setEndSheet(false);
    setEndStep('reason'); // 다음에 열 땐 언제나 이유 목록부터 (초안 텍스트는 러너의 것이라 남긴다)
  };

  const endWith = (reason: EndReason) => {
    if (reason === 'dog') {
      // 컨디션 종료는 보호자가 읽을 문장이 있어야 성립한다 — 여기서 정산하지 않고 기록 스텝으로.
      // (The fabricated "nearby vet" line was already retired; the fabricated condition_note
      // and the "상태 사진과 메모를 남겨주세요" alert — a promise with no field — go here.)
      setEndStep('note');
      return;
    }
    setEndSheet(false);
    settle(reason, false);
  };

  // 기록 스텝의 확정 — 시트를 먼저 걷고 정산한다. 정산 실패 알림(서버 400 포함)은 모달 위가
  // 아니라 화면 위에 떠야 보인다. 슬라이드 아웃이 도는 동안 라벨은 '기록 중...'으로 바뀐다.
  const submitConditionEnd = async () => {
    if (!canSubmitNote || endBusy) return;
    setEndBusy(true);
    setEndSheet(false);
    try {
      await settle('dog', false);
    } finally {
      setEndBusy(false);
    }
  };

  const finish = (_completed: boolean) => {
    settle(null, true);
  };

  // 자동 완주도 반드시 서버 정산을 거친다 — 예전엔 여기서 정산 없이 done으로 직행해
  // 예약이 영원히 active로 남았음 (보호자 위젯 ● LIVE 좀비의 원인, 2026-07-23)
  // [2026-08-08] appActive 게이트: 백그라운드에서 사람 없이 돈이 확정되면 안 된다.
  // 백그라운드에서 목표를 넘겼다면 복귀 시점(appActive 전환)에 이 효과가 다시 돌아 정산한다.
  // A guessed threshold must never move money: with targetKm unknown (null) this stays off
  // and the run ends only through the manual end sheet — the strip below says so.
  const reachedTarget = targetKm != null && km >= targetKm;
  useEffect(() => {
    if (!running || !appActive) return;
    if (reachedTarget) {
      setRunning(false);
      settle(null, true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reachedTarget, appActive, running]);

  // ---------- pace-state (pace-state-ui-plan §1 · UI slot — appended last, nothing reordered) ----------
  // Nothing below touches tracking, settlement, the overrun ceiling or the LA lifecycle: it reads
  // the same buffer the panel already draws and produces one string for one chip.
  const lastAcceptedAt = useRef<number | null>(null); // stamped in onTrack — accepted fixes only
  const [runSuggestSec, setRunSuggestSec] = useState<number | null>(null);
  const prevPace = useRef<PaceState>(''); // the hysteresis LATCH — survives staleness
  const [pace, setPace] = useState<PaceState>('');
  const [paceStale, setPaceStale] = useState(false);

  // The run-start SNAPSHOT of the owner's suggestion — frozen, so a mid-run pref edit cannot
  // move the goalpost under a runner. Pre-0079 the column does not exist and fetchRunMeta's
  // fallback returns null; the caption then rides the dog's current pref from the booking
  // context, and stays ABSENT if that never loaded (§6: a failed fetch is not a known 480).
  useEffect(() => {
    if (!running || runSuggestSec != null) return;
    const bid = runnerJob.bookingId;
    if (!bid) return;
    let alive = true;
    let tries = 0;
    const pull = () => {
      tries += 1;
      fetchRunMeta(bid)
        .then((m) => { if (alive && m.paceSuggestSec != null) setRunSuggestSec(m.paceSuggestSec); })
        .catch(() => { /* bounded retry below; the caption simply stays on the booking value */ });
    };
    pull();
    // The runs row is created by startRunServer, which may still be in flight — a few bounded
    // retries, not a permanent poll (pre-0079 the answer is null forever).
    const id = setInterval(() => {
      if (!alive || tries >= 5) { clearInterval(id); return; }
      pull();
    }, 15000);
    return () => { alive = false; clearInterval(id); };
  }, [running, runSuggestSec]);

  const suggestSec = runSuggestSec != null ? clampSuggest(runSuggestSec)
    : infoStatus === 'ready' && info != null ? clampSuggest(info.paceSuggestSec)
    : null;

  // The §1 machine on the existing 1s tick (sec) and every km change. `stale` is defined here
  // for the runner side: ≥90s since the last accepted fix while running — it drops the claim
  // AND blanks the 페이스 datum, because "no signal" and "too slow" must never look alike.
  useEffect(() => {
    if (!running) { setPace(''); setPaceStale(false); return; }
    const now = Date.now();
    const st = lastAcceptedAt.current != null && now - lastAcceptedAt.current >= 90_000;
    setPaceStale(st);
    if (suggestSec == null) { setPace(''); return; }
    const next = paceState(prevPace.current, {
      windowSec: windowPaceSec(paceWindowPairs(now), now),
      suggestSec,
      km,
      elapsedSec: sec,
      stale: st,
    });
    if (next !== '') prevPace.current = next;
    setPace(next);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, sec, gpsKm, suggestSec]);

  // ---------- 컨디션 종료 기록 (run-end-flow-plan §4a-bis · UI 스텝 — 맨 뒤에 붙인다) ----------
  // Nothing here touches tracking, the settle retry loop, the overrun ceiling or the Live
  // Activity: it is one extra step in front of settle() and one real string in its payload.
  // The field is required by the schema (0001:244 '컨디션 종료 시 필수') and by the server
  // (settle-run/handler.ts:53-54), and it is the ONLY thing the owner ever gets as the
  // runner's account of why their dog stopped (owner/report.tsx:380-388).
  const [endStep, setEndStep] = useState<'reason' | 'note'>('reason');
  const [conditionNote, setConditionNote] = useState('');
  const [endBusy, setEndBusy] = useState(false);
  const canSubmitNote = conditionNote.trim().length > 0;

  // ---------- 러닝 시작 — 연속 기록이 안 되면 시작하지 않는다 (Sean 2026-08-08) ----------
  const startRun = async () => {
    setRationale(false);
    const h = await startTracking(onTrack, { dogName: dogName ?? undefined });
    setTrackMode(h.mode);
    modeRef.current = h.mode;
    if (h.mode !== 'background') {
      // 하드 블록 — 화면이 꺼지면 멈추는 기록으로 러닝을 시작시키면, 러너는 정산 시점에야
      // 거리가 짧다는 걸 알게 된다. 시작하지 않고 이유와 해결 경로를 말한다.
      await h.stop();
      setGps(false);
      haptic('light');
      return;
    }
    handle.current = h;
    setGps(true);
    setSec(0);
    const bid = runnerJob.bookingId;
    if (bid) {
      // 캘린더에서 picked_up 상태로 재진입한 경우에도 start_run이 호출되도록
      startRunServer(bid).catch(() => { /* 이미 active면 무시 */ }).then(() => refreshStartedAt());
    }
    setRunning(true);
  };

  const beginRun = async () => {
    if (starting) return;
    setStarting(true);
    try {
      const perm = await getTrackPermission();
      // OS 시트는 단 한 번뿐 — 거부되면 설정에서만 되돌릴 수 있으니, 왜 필요한지 먼저 말한다
      if (perm === 'undetermined') { setRationale(true); return; }
      await startRun();
    } finally {
      setStarting(false);
    }
  };

  // 추적 불가 사유별 정직 카피 — '모듈 없는 빌드'와 '권한 거부'는 같은 문장이 아니다
  const blockStrip = (): { text: string; action?: string; onAction?: () => void } | null => {
    if (ceilingHit) return { text: '정산 가능한 최대 거리에 근접했어요 — 지금 종료해주세요' };
    if (trackMode == null || trackMode === 'background') {
      // Booking context failed → target distance unknown → auto-complete is OFF. Say so
      // honestly instead of settling on a guessed threshold, and offer retry.
      if (infoStatus === 'error') {
        return {
          text: '예약 정보를 불러오지 못했어요 — 자동 완주 없이 종료 버튼으로 정산돼요',
          action: '다시 시도',
          onAction: () => { if (runnerJob.bookingId) loadInfo(runnerJob.bookingId); },
        };
      }
      return null;
    }
    if (trackMode === 'denied') {
      return {
        text: '위치 권한이 꺼져 있어요 — 거리를 잴 수도, 정산할 수도 없어요',
        action: '설정 열기',
        onAction: () => { Linking.openSettings().catch(() => {}); },
      };
    }
    if (trackMode === 'foreground') {
      return { text: '앱을 켜 둔 동안만 기록돼요 — 화면이 꺼지면 거리가 멈춰요 · 새 빌드에서 러닝을 시작할 수 있어요' };
    }
    return { text: '위치 기능이 없는 빌드예요 — 새 빌드에서 기록돼요' };
  };
  const strip = blockStrip();

  return (
    <View style={s.root}>
      {/* 코스 맵 — 실지도 (GPS 픽스 수신 시), 아니면 대기 배경 */}
      <View style={s.mapArea}>
        {maps && initialCam.current && (
          <maps.NaverMapView
            ref={mapRef}
            style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
            // 컨트롤드 camera 프롭 은퇴 (K7) — 씨앗 1회, 이후는 전부 ref 명령형
            initialCamera={initialCam.current}
            // 러너의 점은 **우리 마커 하나**다. SDK 자체 위치 오버레이까지 뜨면 같은 사람이
            // 두 번 찍히고, 게다가 그건 우리 게이트가 거른 픽스까지 따라간다.
            locationOverlay={{ isVisible: false }}
            isShowLocationButton={false}
            isShowCompass={false}
            isShowScaleBar={false}
            isShowZoomControls={false}
            isTiltGesturesEnabled={false}
            isRotateGesturesEnabled={false}
            onInitialized={() => setMapReady(true)}
            // 팬 오버라이드는 상태 기계가 아니라 술어 하나다 — 우리가 움직인 건 Developer,
            // 팔로우가 움직인 건 Location, 손가락만 Gesture다.
            onCameraChanged={(e: { reason?: string }) => {
              if (e?.reason !== 'Gesture' || camModeRef.current === 'free') return;
              setMode('free');
              mapRef.current?.setLocationTrackingMode('NoFollow');
            }}
          >
            {/* 예정 코스(랩) — '인쇄된 코스도'. 흰 케이싱, 실측 트레이스 **아래**.
                재정 #14: 닫힌 루프면 입구에서 시작하도록 회전된 좌표를 그린다. 색·굵기·zIndex는
                그대로다 — 회전은 그리는 순서를 바꿀 뿐 이 선이 무엇인지를 바꾸지 않는다. */}
            {routeCoords.length > 1 && (
              <maps.NaverMapPathOverlay
                coords={lapCoords}
                width={3}
                color={lilac.accent}
                outlineWidth={1}
                outlineColor="#FFFFFF"
                zIndex={0}
              />
            )}
            {/* 접근 구간 — 픽업에서 입구까지. **직선**이다: 우리에게 도로 라우팅이 없고, 안내 문구도
                그렇게 말한다. 랩(라일락)과도 실측 트레이스(볼트)와도 다른 잉크·굵기라 세 선이 절대
                한 가지로 읽히지 않는다. 입구에 닿으면 할 일을 다 했으므로 사라진다. */}
            {!atEntry && pickupLL && entryCoord && (
              <maps.NaverMapPathOverlay
                coords={[{ latitude: pickupLL.lat, longitude: pickupLL.lng }, entryCoord]}
                width={4}
                color={paper.ink}
                outlineWidth={1}
                outlineColor="#FFFFFF"
                zIndex={0}
              />
            )}
            {trace.current.length > 1 && (
              <maps.NaverMapPathOverlay
                coords={smoothTrace(trace.current.map((p) => ({ latitude: p.lat, longitude: p.lng })))}
                color="#7FA818"
                width={6}
                outlineWidth={2}
                outlineColor="#ffffff"
                zIndex={1}
              />
            )}
            {/* 입구 — 픽업에서 코스 위로 내린 가장 가까운 점. 러너가 인도되는 **대상**이므로
                러닝을 시작한 뒤에도 남는다: 예전 앵커 마커는 running이 되는 순간 사라졌는데,
                그러면 지금 향해 가고 있는 바로 그 점이 화면에서 없어진다. 도착하면 사라진다. */}
            {entryCoord && !atEntry && (
              <maps.NaverMapMarkerOverlay
                latitude={entryCoord.latitude}
                longitude={entryCoord.longitude}
                anchor={{ x: 0.5, y: 0.5 }}
                width={26}
                height={26}
                image={ROUTE_ANCHOR}
                caption={{ text: '입구', textSize: 12, color: paper.ink, haloColor: '#FFFFFF' }}
                zIndex={2}
              />
            )}
            {/* 입구를 계산할 수 없을 때(핀 없음·트레이스 없음)는 오늘 그대로 — 트레이스 첫 점을
                러닝 전에만 보여주고, 그것을 '입구'라고 부르지 않는다. 그건 선이 시작된 자리일 뿐이다. */}
            {!entryCoord && !running && anchor && (
              <maps.NaverMapMarkerOverlay
                latitude={anchor.latitude}
                longitude={anchor.longitude}
                anchor={{ x: 0.5, y: 0.5 }}
                width={26}
                height={26}
                image={ROUTE_ANCHOR}
                zIndex={2}
              />
            )}
            {/* 내 위치 — showsUserLocation 대체 (러너 자신의 최신 **채택된** 픽스) */}
            {lastPos && (
              <maps.NaverMapMarkerOverlay latitude={lastPos.lat} longitude={lastPos.lng} anchor={{ x: 0.5, y: 1 }} zIndex={3} />
            )}
          </maps.NaverMapView>
        )}
        {/* 내 위치로 — 팬으로 팔로우가 풀렸을 때만. 44×44 (a11y 계약) */}
        {maps && initialCam.current && camMode === 'free' && (
          <Pressable onPress={recenter} style={s.recenterBtn} accessibilityRole="button" accessibilityLabel="내 위치로">
            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>내 위치로</Text>
          </Pressable>
        )}
        {/* 지도가 코스를 먼저 띄우고 있어도, 내 점이 아직 없다는 사실은 따로 말한다 */}
        {maps && !lastPos && running && (
          <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' }}>
            {/* sits on the white map canvas, not the dark panel — dim ink for the ≥4.5:1 floor */}
            <Text style={{ fontSize: 14.5, color: paper.dim }}>GPS 신호 잡는 중... (실외에서 몇 초 걸려요)</Text>
          </View>
        )}
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 16 }}>
          <View style={s.statusBadge}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: colors.volt }}>
              {running
                ? dogName ? `● ${dogName}와 러닝 중 · GPS` : '● 러닝 중 · GPS'
                : dogName ? `${dogName}와 러닝 준비` : '러닝 준비'}
            </Text>
            {running && gps && !ceilingHit && (
              <Text style={{ fontSize: 14, color: '#BBBBBB', marginTop: 2 }}>화면이 꺼져도 거리가 기록돼요</Text>
            )}
          </View>
          <Row style={{ gap: 8 }}>
            <View style={s.camStatus}>
              <View style={[s.recDot, !(running && gps) && { backgroundColor: '#BBBBBB' }]} />
              <Text style={s.camText}>
                {running && gps ? '보호자에게 위치 공유 중' : running ? '위치 공유 대기' : '시작 전'}
              </Text>
            </View>
            <Pressable onPress={toggleLayout} style={s.layoutBtn}>
              <Text style={{ fontSize: 15, color: '#fff' }}>⧉</Text>
            </Pressable>
          </Row>
        </Row>

        {/* Course + progress render only from the real booking (mock course retired).
            loading != absent: while the context loads we say so; unknown target = no bar. */}
        <View style={[s.trackWrap, layout === 'island' && { display: 'none' }]}>
          {targetKm != null && remaining != null ? (
            <>
              <Row style={{ justifyContent: 'space-between', marginBottom: 8 }}>
                <Text style={{ fontSize: 14, color: paper.dim }}>{info?.routeName} 코스 · {targetKm}km</Text>
                <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>
                  남은 거리 {remaining.toFixed(1)}km
                </Text>
              </Row>
              <View style={s.track}>
                <View style={[s.trackFill, { width: `${progress * 100}%` }]} />
                <View style={[s.trackDot, { left: `${Math.max(progress * 100 - 2, 0)}%` }]} />
              </View>
            </>
          ) : infoStatus === 'loading' ? (
            <Text style={{ fontSize: 14, color: paper.dim }}>코스 정보 불러오는 중...</Text>
          ) : null}
        </View>
      </View>

      {/* 스탯 + 컨트롤 — panel: 하단 고정 / island: 지도 위 플로팅 */}
      <View style={[s.panel, layout === 'island' && s.panelIsland]}>
        {/* island 모드: 코스·남은 거리·진행바가 카드 안으로 들어온다 (숨기지 않는다) */}
        {layout === 'island' && targetKm != null && remaining != null && (
          <View style={{ marginBottom: 12 }}>
            <Row style={{ justifyContent: 'space-between', marginBottom: 7 }}>
              <Text style={{ fontSize: 15, color: '#BBBBBB' }} numberOfLines={1}>
                {info?.routeName} 코스 · {targetKm}km
              </Text>
              <Text style={{ fontSize: 14, fontWeight: '800', color: '#FFFFFF' }}>
                남은 거리 {remaining.toFixed(1)}km
              </Text>
            </Row>
            <View style={{ height: 5, backgroundColor: '#333333', overflow: 'hidden' }}>
              <View style={{ height: 5, backgroundColor: colors.volt, width: `${progress * 100}%` }} />
            </View>
          </View>
        )}
        {layout === 'island' && targetKm == null && infoStatus === 'loading' && (
          <Text style={{ fontSize: 14, color: '#BBBBBB', marginBottom: 12 }}>코스 정보 불러오는 중...</Text>
        )}
        {/* 추적 상태 라우드 페일 — 실패는 실패로 보인다 (침묵 강등 금지).
            팔레트는 이 화면의 다크 패널에 맞춰 코랄, 문법은 paper 라우드 페일 그대로 */}
        {strip && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>{strip.text}</Text>
            {strip.action && (
              <Pressable onPress={strip.onAction} hitSlop={8} accessibilityRole="button" accessibilityLabel={strip.action}>
                <Text style={s.failAction}>{strip.action}</Text>
              </Pressable>
            )}
          </View>
        )}
        {saveLag && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>기록 저장이 밀리고 있어요 — 신호가 잡히면 자동 재시도해요</Text>
          </View>
        )}
        {/* 픽업 → 입구 안내 (재정 #14). 같은 스트립 문법: 통신 실패만 코랄, 나머지는 중립 헤어라인 */}
        {guide && (
          <View style={[s.failStrip, !guide.warn && s.noteStrip]}>
            <View style={{ flex: 1 }}>
              <Text style={[s.guideTxt, guide.warn && { color: colors.tang }]}>{guide.text}</Text>
              {guide.note && <Text style={s.guideNote}>{guide.note}</Text>}
            </View>
            {guide.action && (
              <Pressable onPress={guide.onAction} hitSlop={8} accessibilityRole="button" accessibilityLabel={guide.action}>
                <Text style={s.failAction}>{guide.action}</Text>
              </Pressable>
            )}
          </View>
        )}
        {/* 코스 오버레이 고지 — 자문이지 차단이 아니다. 코스 선이 없어도 러닝·기록·정산은 그대로 간다 */}
        {routeNote && (
          <View style={[s.failStrip, !routeNote.warn && s.noteStrip]}>
            <Text style={[s.failTxt, !routeNote.warn && { color: '#BBBBBB' }]}>{routeNote.text}</Text>
          </View>
        )}

        {/* 고정된 고객 채팅 */}
        <Pressable
          style={s.chatPin}
          onPress={() => router.push('/chat')}
        >
          {/* Real dog identity — booking photo when it exists, monogram of the real name
              otherwise (mock char/color retired). Neutral tile on the dark panel. */}
          <Avatar url={info?.dogPhotoUrl} char={(dogName ?? '반려견')[0]} bg="#3A3A3A" size={36} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: '#FFFFFF' }}>{dogName ? `${dogName} 보호자님` : '보호자님'}</Text>
            <Text style={{ fontSize: 14.5, color: '#BBBBBB' }} numberOfLines={1}>
              {info?.dogMemo ?? '채팅으로 이동'}
            </Text>
          </View>
          <Text style={{ fontSize: 14, color: colors.volt }}>채팅 ›</Text>
        </Pressable>

        <Row style={{ justifyContent: 'space-around', marginVertical: 22 }}>
          <MiniStat value={km.toFixed(2)} label="km" big />
          <MiniStat value={fmt(sec)} label="시간" />
          {/* 90초 넘게 새 픽스가 없으면 마지막 페이스는 더 이상 '지금'이 아니다 — 숫자를 비운다 */}
          <MiniStat value={paceStale ? '—' : paceStr(sec, km)} label="페이스" />
        </Row>

        {/* 페이스 상태 (plan §3b Ⓑ①) — 스탯 줄과 수익 줄 사이 한 줄. panel·island 두 레이아웃이
            이 슬롯 하나를 공유한다. 워시 칩이 자기 배경을 들고 다녀서 다크 패널 위에서도 대비는
            칩 안에서 완결된다. 기준(권장 캡션)이 판정(칩)을 앞선다 — 캡션은 아는 순간부터. */}
        {(suggestSec != null || pace !== '') && (
          <View style={{ marginBottom: 14 }}>
            <Row>
              {pace !== '' && (
                <View
                  style={[s.paceChip, pace === 'good' ? s.paceChipGood : s.paceChipSlow]}
                  accessibilityLabel={PACE_CHIP_A11Y[pace]}
                >
                  <Text style={[s.paceChipTxt, pace === 'good' ? s.paceChipInkGood : s.paceChipInkSlow]}>
                    {PACE_CHIP_LABEL[pace]}
                  </Text>
                </View>
              )}
              {suggestSec != null && <Text style={s.paceTarget}>권장 {suggestStr(suggestSec)}</Text>}
            </Row>
            {/* 케어 스톱은 정당하다 — 신호가 러너를 물·응가에서 밀어내면 안 된다. 필요한 상태에서만 */}
            {pace === 'slow' && (
              <Text style={s.paceCare}>물·응가 스톱도 평균에 들어가요 — 괜찮아요</Text>
            )}
          </View>
        )}

        <Row style={{ justifyContent: 'center', marginBottom: 14 }}>
          <Text style={{ fontSize: 14, color: '#BBBBBB' }}>
            현재 예상 수익 <Text style={{ color: colors.volt, fontWeight: '800' }}>{payoutFor(km).toLocaleString()}원</Text>
            {targetKm != null ? ` · 완주 시 ${payoutFor(targetKm + 0.02).toLocaleString()}원` : ''}
          </Text>
        </Row>

        {/* 러닝 이벤트 스트립 — 원탭이 보호자 알림으로 (응가 도장 포함).
            리프레시: 다크 타일 → 파스텔 스탬프 필 (다크 위에서 팝, 도장 문화의 색) */}
        {running && (
          <View style={{ flexDirection: 'row', gap: 7, marginBottom: 14 }}>
            {([['poop', '응가', '#FFCDB6'], ['snack', '간식', '#F2DA96'], ['water', '물', '#C3D9AE']] as const).map(([k, label, bg]) => (
              <Pressable key={k} onPress={() => fireEvent(k)} style={[s.eventBtn, { backgroundColor: bg }]}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: '#111111' }}>
                  {label}{evCounts[k] ? ` ${evCounts[k]}` : ''}
                </Text>
              </Pressable>
            ))}
            {/* busy = label swap ('전송 중') — opacity paint retired */}
            <Pressable onPress={firePhoto} disabled={snapBusy} style={[s.eventBtn, { backgroundColor: '#DDF0A6' }]}>
              <Icon name="Camera" glyph="◉" size={15} color={'#111111'} />
              <Text style={{ fontSize: 14, fontWeight: '800', color: '#111111' }}>
                {snapBusy ? '전송 중' : `스냅${evCounts.photo ? ` ${evCounts.photo}` : ''}`}
              </Text>
            </Pressable>
          </View>
        )}

        <View style={{ flexDirection: 'row', gap: 10, alignItems: 'center' }}>
          {running && (
            <Pressable style={s.moreBtn} onPress={openEndSheet}>
              <Text style={{ fontSize: 16, color: '#BBBBBB', fontWeight: '900' }}>❙❙</Text>
            </Pressable>
          )}
          <Pressable
            // busy = label swap below ('위치 확인 중...') — the opacity paint retired (§2 button law)
            style={({ pressed }) => [s.btn, { backgroundColor: pressed && !starting ? colors.voltDeep : colors.volt }]}
            disabled={starting}
            onPress={() => {
              if (running) { openEndSheet(); return; }
              beginRun();
            }}
          >
            <Text style={[{ fontSize: 19.5, fontWeight: '800', color: colors.ink }, df]}>
              {running ? '러닝 종료' : starting ? '위치 확인 중...' : '러닝 시작'}
            </Text>
          </Pressable>
        </View>
      </View>

      {/* ---------- 위치 사전 설명 (OS 시트 직전, 최초 1회) ----------
          시스템 프롬프트는 한 번뿐이고, 거절하면 설정에서만 되돌릴 수 있다 — 먼저 이유를 말한다 */}
      <Modal visible={rationale} transparent animationType="slide" onRequestClose={() => setRationale(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => { setRationale(false); setTrackMode('denied'); }} />
        <View style={s.sheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 19.5, fontWeight: '900', color: '#FFFFFF' }}>러닝 거리는 위치로 재요</Text>
          <Text style={{ fontSize: 15, color: '#BBBBBB', marginTop: 8, lineHeight: 21 }}>
            주머니에 넣거나 화면이 꺼져도 거리와 경로가 계속 기록돼요. 이 거리가 보호자에게 보이는 기록이자 정산 기준이에요.{'\n'}
            러닝을 종료하면 기록도 함께 멈춰요.
          </Text>
          <Pressable style={[s.btn, { backgroundColor: colors.volt, marginTop: 18 }]} onPress={() => { startRun(); }}>
            {/* display font retired here — 1/screen budget is spent on the main CTA */}
            <Text style={{ fontSize: 17, fontWeight: '800', color: colors.ink }}>위치 허용하기</Text>
          </Pressable>
          <Pressable style={s.sheetCancel} onPress={() => { setRationale(false); setTrackMode('denied'); }}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: '#BBBBBB' }}>나중에</Text>
          </Pressable>
        </View>
      </Modal>

      {/* ---------- end-run sheet — 한 시트, 두 스텝 (이유 → 컨디션이면 기록) ---------- */}
      <Modal visible={endSheet} transparent animationType="slide" onRequestClose={closeEndSheet}>
        <Pressable style={s.sheetBackdrop} onPress={closeEndSheet} />
        {endStep === 'reason' ? (
          <View style={s.sheet}>
            <View style={s.sheetHandle} />
            <Text style={{ fontSize: 19.5, fontWeight: '900', color: '#FFFFFF' }}>어떤 이유로 종료하나요?</Text>
            <Text style={{ fontSize: 15, color: '#BBBBBB', marginTop: 4 }}>
              지금까지 {km.toFixed(2)}km · 이유에 따라 정산이 달라져요
            </Text>

            <EndOption
              title="강아지 컨디션"
              // 사진 약속은 내렸다 — 이 스텝이 받는 것은 메모다. 없는 것을 약속하지 않는다.
              desc="지친 기색·이상 징후 등. 종료 전에 메모를 남겨요"
              pay={`${payoutByReason('dog').toLocaleString()}원 · 완주율 무영향`}
              accent="#C6F542"
              onPress={() => endWith('dog')}
            />
            <EndOption
              title="보호자 요청"
              desc="보호자가 조기 종료를 요청했어요"
              pay={targetKm != null
                ? `${payoutByReason('owner').toLocaleString()}원 · 잔여 거리 50% 보장 포함`
                : `${payoutByReason('owner').toLocaleString()}원 + 잔여 거리 50% 보장 · 정산 시 확정`}
              accent="#9fc3e8"
              onPress={() => endWith('owner')}
            />
            <EndOption
              title="러너 개인 사유"
              desc="부상·일정 등 러너 사정으로 종료해요"
              pay={`${payoutByReason('runner').toLocaleString()}원 · 완주율에 반영`}
              accent="#e2c56b"
              onPress={() => endWith('runner')}
            />

            <Pressable style={s.sheetCancel} onPress={closeEndSheet}>
              <Text style={{ fontSize: 15, fontWeight: '700', color: '#BBBBBB' }}>계속 달릴게요</Text>
            </Pressable>
          </View>
        ) : (
          // 키보드가 입력칸을 덮으면 러너는 자기가 쓴 문장을 못 본다 — 시트를 밀어 올린다
          <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
            <View style={s.sheet}>
              <View style={s.sheetHandle} />
              <Text style={{ fontSize: 19.5, fontWeight: '900', color: '#FFFFFF' }}>무엇을 보고 멈췄나요?</Text>
              <Text style={{ fontSize: 15, color: '#BBBBBB', marginTop: 6, lineHeight: 21 }}>
                여기 적은 내용이 보호자의 기록 카드에 그대로 실려요. 본 것만 적어주세요 — 판단은 보호자와 수의사가 해요.
              </Text>

              {/* 플레이스홀더는 라벨이 아니다 — 보이는 라벨을 따로 세운다 */}
              <Text style={s.noteLabel}>관찰한 내용</Text>
              <TextInput
                style={s.noteInput}
                value={conditionNote}
                onChangeText={setConditionNote}
                multiline
                textAlignVertical="top"
                editable={!endBusy}
                placeholder="예: 3km 지점부터 헐떡임이 심해지고 걸음을 멈춰서 그늘에서 쉬었어요"
                placeholderTextColor={paper.dim}
                accessibilityLabel="관찰한 내용"
                autoFocus
              />
              <Text style={s.noteHint}>지금까지 {km.toFixed(2)}km · 컨디션 종료는 완주율에 반영되지 않아요</Text>

              <Pressable
                // busy = 라벨 스왑, disabled = 명시 fill (§3b 버튼 매트릭스 — 불투명도 트릭 없음)
                style={({ pressed }) => [
                  s.btn,
                  { marginTop: 18 },
                  !canSubmitNote
                    ? { backgroundColor: paper.disabledFill }
                    : { backgroundColor: pressed && !endBusy ? colors.voltDeep : colors.volt },
                ]}
                disabled={!canSubmitNote || endBusy}
                onPress={submitConditionEnd}
                accessibilityRole="button"
                accessibilityState={{ disabled: !canSubmitNote || endBusy }}
              >
                <Text style={{ fontSize: 17, fontWeight: '800', color: canSubmitNote ? colors.ink : paper.faint }}>
                  {endBusy ? '기록 중...' : '종료하고 기록 남기기'}
                </Text>
              </Pressable>
              <Pressable style={s.sheetCancel} onPress={() => setEndStep('reason')} disabled={endBusy}>
                <Text style={{ fontSize: 15, fontWeight: '700', color: '#BBBBBB' }}>이유 다시 고르기</Text>
              </Pressable>
            </View>
          </KeyboardAvoidingView>
        )}
      </Modal>
    </View>
  );
}

function EndOption({ title, desc, pay, accent, onPress }: { title: string; desc: string; pay: string; accent: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={s.endOption}>
      <View style={[s.endRail, { backgroundColor: accent }]} />
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#FFFFFF' }}>{title}</Text>
        <Text style={{ fontSize: 14.5, color: '#BBBBBB', marginTop: 2 }}>{desc}</Text>
        <Text style={{ fontSize: 14, fontWeight: '800', color: accent, marginTop: 5 }}>{pay}</Text>
      </View>
      <Text style={{ fontSize: 17, color: '#BBBBBB' }}>›</Text>
    </Pressable>
  );
}

function MiniStat({ value, label, big }: { value: string; label: string; big?: boolean }) {
  const nf = useNumFont(); // Oswald live stats — lineHeight 55/35 = 1.25× (BUG A)
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={[{ fontSize: big ? 44 : 28, lineHeight: big ? 55 : 35, fontWeight: '900', color: big ? colors.volt : '#FFFFFF', fontVariant: ['tabular-nums'] as const }, nf]}>
        {value}
      </Text>
      <Text style={{ fontSize: 14.5, color: '#BBBBBB', marginTop: 2 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  // paper chrome — white map-world canvas; the sage placeholder ground retired
  root: { flex: 1, backgroundColor: paper.canvas },
  mapArea: { flex: 1, paddingTop: 56 },
  // small white/volt text sits on an ink plate (§3 plate law) — sharp
  statusBadge: { backgroundColor: paper.ink, borderRadius: 0, paddingVertical: 8, paddingHorizontal: 14 },
  camStatus: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, paddingVertical: 8, paddingHorizontal: 12 },
  recDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#ff3b30' },
  camText: { fontSize: 14, fontWeight: '700', color: paper.ink },
  trackWrap: { position: 'absolute', left: 20, right: 20, bottom: 24 },
  // coral fill = LIVE (watch) semantic; bar sharp, position dot keeps its circle (marker exception)
  track: { height: 10, backgroundColor: '#EEEEEE' },
  trackFill: { height: 10, backgroundColor: colors.tang },
  trackDot: {
    position: 'absolute', top: -4, width: 18, height: 18, borderRadius: 9,
    backgroundColor: colors.tang, borderWidth: 3, borderColor: '#fff',
  },
  // dark run-panel artifact — sharp, seamed to the paper world by a coral hairline
  panel: { backgroundColor: paper.ink, borderTopWidth: 1, borderTopColor: paper.line, padding: 20, paddingBottom: 34 },
  panelIsland: {
    position: 'absolute', left: 12, right: 12, bottom: 22,
    paddingBottom: 20, borderWidth: 1, borderColor: paper.line,
    // island genuinely floats over the map — the one sanctioned shadow on this screen
    shadowColor: '#000', shadowOpacity: 0.25, shadowRadius: 22, shadowOffset: { width: 0, height: 5 },
    elevation: 12,
  },
  layoutBtn: {
    width: 32, height: 32, borderRadius: 0, backgroundColor: paper.ink,
    alignItems: 'center', justifyContent: 'center', alignSelf: 'center',
  },
  chatPin: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#222222', borderRadius: 0, padding: 12,
  },
  // Loud fail (F1.2 grammar): full-bleed strip, 1px hairline top and bottom, 14pt/700 ink,
  // underlined action. Palette is coral because this screen is still on the dark tokens —
  // porting the grammar, not the paper palette.
  failStrip: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10,
    marginHorizontal: -20, paddingHorizontal: 20, paddingVertical: 12, marginBottom: 12,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: colors.coralText,
  },
  failTxt: { flex: 1, fontSize: 14, fontWeight: '700', color: colors.tang },
  failAction: { fontSize: 14, fontWeight: '800', color: colors.tang, textDecorationLine: 'underline' },
  // 같은 스트립 문법의 **자문** 변형 — 코랄은 라우드 페일에만 쓴다 (색 역할 분리 법).
  // 코스 선이 없는 것은 실패가 아니라 사실이므로 중립 헤어라인으로 말한다.
  noteStrip: { borderColor: '#3A3A3A' },
  // 픽업→입구 안내 — 자문 스트립과 같은 문법, 두 줄(사실 / 그 사실의 한계). 디테일 플로어 14pt.
  guideTxt: { fontSize: 14.5, lineHeight: 20, fontWeight: '700', color: '#FFFFFF' },
  guideNote: { fontSize: 14, lineHeight: 19, color: '#BBBBBB', marginTop: 4 },
  // 내 위치로 — 팬 오버라이드를 되돌리는 유일한 컨트롤 (44pt 터치 타깃)
  recenterBtn: {
    // 진행바(trackWrap, bottom 24)를 피해 그 위에 앉는다
    position: 'absolute', right: 20, bottom: 84, minHeight: 44, justifyContent: 'center',
    paddingHorizontal: 14, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    shadowColor: '#000', shadowOpacity: 0.14, shadowRadius: 10, shadowOffset: { width: 0, height: 3 }, elevation: 4,
  },
  btn: { flex: 1, borderRadius: 0, padding: 16, alignItems: 'center' },
  // 페이스 칩 (§3b) — 16/800 · radius 0 · 틴트 면 · 보더 없음. 페이퍼 월드와 같은 문법이고,
  // 워시가 자기 배경을 들고 오므로 다크 패널 위에서도 잉크 대비가 유지된다. 숫자 리컬러는 없다.
  paceChip: { paddingVertical: 6, paddingHorizontal: 10 },
  paceChipGood: { backgroundColor: paper.paceGoodWash },
  paceChipSlow: { backgroundColor: paper.paceSlowWash },
  paceChipTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800' },
  paceChipInkGood: { color: paper.paceGoodInk },
  paceChipInkSlow: { color: paper.paceSlowInk },
  paceTarget: { marginLeft: 'auto', fontSize: 14, lineHeight: 18, color: '#BBBBBB' },
  paceCare: { marginTop: 7, fontSize: 14, lineHeight: 18, color: '#BBBBBB' },
  moreBtn: { width: 44, height: 52, borderRadius: 0, backgroundColor: '#222222', alignItems: 'center', justifyContent: 'center' },
  // event stamp chips — pastel stamp fills survive (stamp-culture semantics), corners sharp
  eventBtn: { flex: 1, flexDirection: 'row', gap: 5, borderRadius: 0, alignItems: 'center', justifyContent: 'center', paddingVertical: 12 },
  sheetBackdrop: { flex: 1, backgroundColor: '#00000066' },
  // end-run sheets stay in the dark run world — sharp, coral hairline seam at the top edge
  sheet: { backgroundColor: '#141414', borderTopWidth: 1, borderTopColor: paper.line, padding: 16, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#3A3A3A', marginBottom: 14 },
  endOption: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#222222', borderRadius: 0, padding: 14, marginTop: 10,
  },
  endRail: { width: 4, height: 44 },
  // 컨디션 종료 기록 스텝 — 다크 시트 안의 종이 필드. 보호자가 읽게 될 문장을 쓰는 자리라
  // 캔버스 면 + 코랄 헤어라인 1px로 시트에서 떼어 놓는다 (모서리는 여기도 샤프).
  noteLabel: { fontSize: 15, fontWeight: '800', color: '#FFFFFF', marginTop: 18, marginBottom: 7 },
  noteInput: {
    minHeight: 108, borderRadius: 0, borderWidth: 1, borderColor: paper.line,
    backgroundColor: paper.canvas, color: paper.ink,
    fontSize: 15.5, lineHeight: 21, padding: 12,
  },
  noteHint: { fontSize: 14, lineHeight: 19, color: '#BBBBBB', marginTop: 8 },
  sheetCancel: { alignItems: 'center', paddingVertical: 14, marginTop: 6 },
});
