import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Modal, Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { homePath } from '../../src/components/bottomnav';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Avatar, Row } from '../../src/components/ui';
import { ensureThread, fetchBookingStatus, fetchCurrentOwnerBookingId, fetchMeetupInfo, fetchOwnerPickupCoords, fetchRouteById, fetchRunMeta, MeetupInfo, notifyRunStop, OwnerPickup, sendChatMessage, subscribeBooking } from '../../src/lib/api';
import { useNumFont } from '../../src/lib/fonts';
import { getNaverMap, LiveLinkState, LivePos, smoothTrace, subscribePos } from '../../src/lib/geo';
import { endOwnerActivity, OwnerLAProps, startOwnerActivity, updateOwnerActivity } from '../../src/lib/ownerActivity';
import { clampSuggest, PACE_WINDOW_MS, PaceState, paceState, windowPaceSec } from '../../src/lib/pace';
import { haversineM, nearestOnTrace, rotateLoopAtEntry, snapToRoute } from '../../src/lib/route-geom';
import { draft, RouteInfo } from '../../src/store';
import { colors, lilac, paper } from '../../src/theme';

// 라이브 런 (보호자) — 풀스크린 실지도 + 하단 아일랜드. 실예약 전용 화면이다.
// [정직 배치 2026-08-06 · item 2] 데모 모드 전면 퇴역: 빈 draft(앱 새로 열기·딥링크·백스택 재진입)가
// 화면을 통째로 목업 러닝으로 뒤집던 경로를 삭제했다 — 20초 가짜 타이머, 목업 러너, 연출 지도,
// 그리고 t≥1에서 100% 목업 영수증(/owner/pay)으로 자동 이동까지. 가짜 러닝은 이제 존재하지 않는다.
// 예약 id가 비면 서버가 진실을 안다 (fetchCurrentOwnerBookingId — owner/meetup과 동일 관용구).
// 크롬만 순백/코랄로 전환 — 지도가 곧 화면이라 밀도는 그대로다 (양육권 표면: 상태 가독성이 법).

// 라이브 캠 스트림 인터페이스 스텁 (office-hours 승인 설계) — 타입만, 전송 코드 없음
export type StreamState = 'connecting' | 'live' | 'degraded' | 'lost';
export interface LiveStreamSession { state: StreamState; startedAt: number | null; }

const STREAM_COPY: Record<StreamState, string> = {
  connecting: '영상 연결 중...',
  live: '영상 수신 중',
  degraded: '영상 품질 낮음',
  lost: '영상 연결이 끊겼어요',
};

// 예약 해석 상태 — 로딩 ≠ 없음 ≠ 실패. 셋을 절대 한 화면으로 뭉개지 않는다.
type Resolve = 'resolving' | 'ready' | 'empty' | 'error';

const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};
// The 권장 caption's value is already sec/km, so it needs no division — same M'SS" grammar.
const suggestStr = (sec: number) => `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"`;
const PACE_CHIP_LABEL: Record<'good' | 'slow', string> = { good: '페이스 양호', slow: '권장보다 느려요' };
const PACE_CHIP_A11Y: Record<'good' | 'slow', string> = {
  good: '페이스 상태: 양호',
  slow: '페이스 상태: 권장보다 느림',
};

const STOP_REASONS = ['아이 컨디션이 걱정돼요', '급한 일정이 생겼어요', '기타 사유'];

// ---------- [2026-08-20] when a run ends through a door that is not `completed` ----------
// The statuses on which a run is live or about to be — api.ts's IN_FLIGHT set. Anything else means
// the run this screen is drawing has ENDED, and `done()` below only ever tested for 'completed'.
// `active → incident_review` is legal (0066_enroute_cancel.sql:54), so on an incident this screen
// never left: the 1s tick kept advancing the elapsed clock forever off runs.started_at, and the strip
// said 「위치가 N분째 갱신되지 않았어요 · 채팅으로 확인」 — a network-trouble sentence during a
// safety event.
const LIVE_STATUS = new Set(['confirmed', 'runner_enroute', 'picked_up', 'active']);
// The two held statuses reachable from a live run (`active → incident_review`, then
// 0072_incident_settlement.sql:179 `incident_review → refund_pending`). Both keep the owner HERE:
// /safety takes no booking context, and teleporting away from the last-known-position map — the
// most important artifact they have during a hold — reads as the app malfunctioning at the moment
// trust is decided. The pill words are the ones this app already uses for these rawStatuses
// (owner/schedule.tsx:57 '확인 중', owner/pay.tsx:44 '환불 중'), not new vocabulary.
const HELD_COPY: Record<string, { pill: string; strip: string }> = {
  incident_review: {
    pill: '확인 중',
    strip: '확인이 진행 중이에요 — 위치는 마지막으로 받은 지점이에요. 처리되면 알림으로 알려드릴게요.',
  },
  refund_pending: {
    pill: '환불 중',
    strip: '환불이 진행 중이에요 — 위치는 마지막으로 받은 지점이에요. 처리되면 알림으로 알려드릴게요.',
  },
};

// ---------- 계획 경로 · 접근 구간 상수 (재정 #14/#15 · RULING 9) ----------
// 입구 마커 에셋 — 러너 화면과 **같은 파일**이다. 두 화면이 같은 점을 다른 글리프로 그리면
// 그건 같은 점으로 읽히지 않는다.
const ROUTE_ANCHOR = require('../../assets/route-anchor.png');
// 입구 도착 판정 반경(m) · 닫힌 루프 임계값(m) — 둘 다 runner/run.tsx와 같은 수를 쓴다.
// 한 화면만 다른 '도착'/'닫힘' 정의를 갖는 순간 두 지도가 같은 러닝을 다르게 그린다.
// 표시 전용: 거리·페이스·정산에는 닿지 않는다.
const ENTRY_REACHED_M = 40;
const LOOP_CLOSURE_M = 50;
// 계획 구도가 피해야 할 화면 덮개(pt). 상단 = 상단 바(top 56 + 40) + 그 아래 대기 스트립.
// 하단은 아일랜드의 **실측** 높이를 쓴다 (이 상수는 그것을 재기 전의 하한이 아니라, 상단 쪽 값).
const MAP_TOP_COVER_PT = 170;
const MAP_PAD_PT = 24;
// 딱 맞게 담으면 선이 화면 가장자리에 닿는다 — 요구 해상도를 15% 여유 있게 잡아 한 걸음 물린다.
const MAP_FIT_PAD = 1.15;
// 시뮬레이터 보정(2026-08-19, 코디네이터 실측). 표준 메르카토르 식(256pt 타일 가정)이 낸 줌으로
// 그렸더니 루프의 일부만 보였다 — 네이버 SDK의 zoom은 그 식이 예측하는 것보다 **한 단계 정도
// 더 당겨서** 그린다. 식을 손대는 대신 보정값을 한 개만 둔다: 여전히 잘려 보이면 이 값을
// 올리고(더 넓게), 너무 멀어 보이면 내린다. ⚠ 내가 직접 시뮬레이터에서 잰 값이 아니라
// 실측 보고를 반영한 상수다 — 다음 시뮬레이터 패스에서 확인 대상.
const MAP_ZOOM_TRIM = 1;

// 스트림 슬롯 — 라이브 캠이 붙을 자리. 세션이 null이면 아무것도 그리지 않는다
// (없는 기능의 어포던스 금지). 자리만 아일랜드 레이아웃에 예약해 둔 것 — 나중에 붙어도 재배치 없음.
function StreamSlot({ session }: { session: LiveStreamSession | null }) {
  if (!session) return null;
  return (
    <View style={s.streamSlot}>
      <Text style={s.streamTxt}>{STREAM_COPY[session.state]}</Text>
    </View>
  );
}

export default function Live() {
  const nf = useNumFont(); // 숫자 = Oswald — 이 화면의 단 하나의 타입 점프(km)
  // 회전·분할 대응 — Dimensions.get은 구독이 없어 stale (fitness.tsx:74와 같은 이유)
  const { width: winW, height: winH } = useWindowDimensions();
  const [bookingId, setBookingId] = useState<string | null>(draft.bookingId ?? null);
  const [resolve, setResolve] = useState<Resolve>(draft.bookingId ? 'ready' : 'resolving');
  const [stopSheet, setStopSheet] = useState(false);
  const [stopReason, setStopReason] = useState<string | null>(null);
  const [stopBusy, setStopBusy] = useState(false);
  // 라이브 캠 세션 — 오늘은 항상 null (전송 계층이 없다). 타입만 먼저 못 박아 둔다.
  const [streamSession] = useState<LiveStreamSession | null>(null);

  // ---------- 실모드 데이터 ----------
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const [pos, setPos] = useState<LivePos | null>(null);
  const path = useRef<{ latitude: number; longitude: number }[]>([]);
  const [pathLen, setPathLen] = useState(0);
  const startAt = useRef<number | null>(null);
  const [liveSec, setLiveSec] = useState(0);
  // [2026-08-08] 신선도 시계 — 멈춘 점을 살아있는 점처럼 보여주던 것이 보호자 쪽 거짓말이었다.
  // 러너가 백그라운드로 계속 기록하는 지금, '갱신 없음'은 '러닝 종료'가 아니라 신호 문제일 수 있다.
  const lastFixAt = useRef<number | null>(null);
  const [staleSec, setStaleSec] = useState(0);
  // 위치 채널의 상태. '아직 안 옴'과 '받을 수 없음'은 지도에서 똑같이 생겼으므로
  // (둘 다 빈 지도다) 화면이 구별해서 말해야 한다 — 그러지 않으면 거절이 정지한
  // 개처럼 읽힌다. (P0-1)
  const [link, setLink] = useState<LiveLinkState>('connecting');
  // The booking status once it leaves LIVE_STATUS — null while the run is live. Held, not exited:
  // the map keeps the last received fix rendered (real data), the numbers keep their last values,
  // and only the claims that stopped being true are taken away. The ref is what the 1s tick reads:
  // the tick's closure is built once per bookingId and would never see the state.
  const [held, setHeld] = useState<string | null>(null);
  const heldRef = useRef(false);
  const maps = getNaverMap(); // 네이버 지도 (2026-07-29) — 미탑재 빌드는 대기 화면 폴백

  // ---------- 계획 경로 + 접근 구간 (재정 #14 · RULING 9) ----------
  // 보호자가 보는 지도는 러너가 보는 지도와 **같은 그림**이어야 한다: 계획된 랩(라일락) 위에
  // 지금까지 실제로 달린 선(voltDeep), 그리고 아직 입구에 닿기 전이라면 픽업→입구 직선.
  // 세 선은 색·굵기·z가 전부 달라서 절대 한 가지로 읽히지 않는다 (CLAUDE.md 색 역할 법).
  const [routeGeo, setRouteGeo] = useState<RouteInfo | null>(null);
  const [routeState, setRouteState] = useState<'idle' | 'loading' | 'ready' | 'error'>('idle');
  // fetchMeetupInfo 실패 — routeState가 'idle'에 머무는 두 이유(예약에 코스가 없다 / 예약
  // 컨텍스트를 못 읽었다)를 가르는 값이다. 둘을 뭉치면 '코스 없음'이라는 거짓말이 된다.
  const [infoErr, setInfoErr] = useState(false);
  const [pickup, setPickup] = useState<{ s: 'loading' } | { s: 'ok'; a: OwnerPickup | null } | { s: 'err' }>({ s: 'loading' });
  // 두 fetch를 한 버튼으로 되돌리는 재시도 카운터 — 화면에 보이는 '다시 시도'가 실제로 무엇을
  // 다시 부르는지가 이 값이다 (죽은 버튼 금지).
  const [geoTry, setGeoTry] = useState(0);
  // 입구 도착 — 한 번 켜지면 다시 꺼지지 않는다. 픽스가 오기 전에는 false다 (모름 ≠ 도착).
  const [atEntry, setAtEntry] = useState(false);
  // 아일랜드 실측 높이 — 범례를 그 위에 정확히 얹기 위한 값. 추정 높이를 쓰면 아일랜드가
  // 커지는 상태(신선도 스트립·페이스 줄)에서 범례가 그 밑으로 들어간다.
  const [islandH, setIslandH] = useState(0);

  // ---------- pace-state (pace-state-ui-plan §1) ----------
  // ⚠ Elapsed precondition. `startAt.current` above clocks from the FIRST FIX AFTER MOUNT, so an
  // owner opening this screen at km 2.3 used to be shown a count starting at 0 — and a pace
  // derived from it (0'52", a lying verdict). Elapsed now comes from `runs.started_at` ONLY;
  // the first-fix clock survives as the 1s heartbeat and as the pre-run absence marker, and
  // while started_at is unknown the 시간/페이스 stats render the existing '—' placeholder
  // rather than a fabricated count. No number here is ever recomputed from mount time again.
  const runStartedAt = useRef<number | null>(null);
  const [elapsedSec, setElapsedSec] = useState<number | null>(null);
  // The run-start SNAPSHOT of the owner's suggestion (frozen: a mid-run pref edit cannot move
  // the goalpost). null = not known from the run row — pre-run, or pre-0079 schema.
  const [runSuggestSec, setRunSuggestSec] = useState<number | null>(null);
  // LivePos carries no timestamp (geo.ts), so local ARRIVAL stamps are the honest window
  // source (plan §5) — cumulative km as broadcast, paired with when it reached this screen.
  const pacePairs = useRef<{ t: number; km: number }[]>([]);
  const prevPace = useRef<PaceState>(''); // the hysteresis LATCH — survives staleness
  const [pace, setPace] = useState<PaceState>('');

  // id 복원 — 리로드로 draft가 비어도 서버가 진실을 안다. 실패(네트워크)는 '진행 중 없음'과 다르다:
  // 조용히 back 하지 않고 재시도 문을 연다.
  // Leaving this screen must always land somewhere. A cold entry (Live Activity deep link, or a
  // push tapped after the run already ended) gives this route a single-entry stack, and the root
  // Stack is headerShown:false + gestureEnabled:false — so a bare router.back() is a NO-OP and the
  // owner is left staring at an empty screen with a back arrow that does nothing. Only one of the
  // app's many back sites guarded for this (cards.tsx); this is that idiom.
  const goBack = useCallback(() => {
    if (router.canGoBack()) router.back();
    else router.replace(homePath());
  }, []);

  const resolveBooking = useCallback(() => {
    setResolve('resolving');
    fetchCurrentOwnerBookingId()
      .then((id) => {
        if (id) { draft.bookingId = id; setBookingId(id); setResolve('ready'); return; }
        setResolve('empty');
        Alert.alert('진행 중인 러닝이 없어요', '러닝이 시작되면 이 화면이 열려요');
        goBack();
      })
      .catch((e) => { console.warn('[live] resolve:', e?.message ?? e); setResolve('error'); });
  }, [goBack]);

  useEffect(() => {
    if (bookingId) return;
    resolveBooking();
  }, [bookingId, resolveBooking]);

  // 예약 컨텍스트 (코스 id · 코스 이름 · 아이 · 권장 페이스). 자기 effect를 갖는 이유 둘:
  // ① 실패를 조용한 catch로 삼키던 것을 상태로 올린다 — 이 fetch가 실패하면 routeId를 못 얻고
  //    routeState는 'idle'에 머물러 계획선·입구·마커가 통째로 빠지는데, 화면은 아무 말도 하지
  //    않았다 (geoNote에 idle 분기가 없었다). ② geoTry를 받아 화면의 '다시 시도'가 이것도
  //    되부른다 — 구독을 세우는 아래 effect에 섞어 두면 재시도가 구독을 통째로 다시 만든다.
  useEffect(() => {
    if (!bookingId) return;
    const bid = bookingId;
    let alive = true;
    setInfoErr(false);
    fetchMeetupInfo(bid)
      .then((i) => { if (alive) { setInfo(i); setInfoErr(false); } })
      .catch((e) => {
        console.warn('[live] meetup info:', e?.message ?? e);
        if (alive) setInfoErr(true);
      });
    return () => { alive = false; };
  }, [bookingId, geoTry]);

  useEffect(() => {
    if (!bookingId) return;
    const bid = bookingId;
    const unsubPos = subscribePos(bid, (p) => {
      const now = Date.now();
      if (!startAt.current) startAt.current = now;
      lastFixAt.current = now;
      setStaleSec(0);
      path.current.push({ latitude: p.lat, longitude: p.lng });
      setPathLen(path.current.length);
      setPos(p);
      // Rolling-window feed. Kept to twice the window so the buffer cannot grow with the run.
      pacePairs.current.push({ t: now, km: p.km });
      if (pacePairs.current.length > 120) {
        pacePairs.current = pacePairs.current.filter((q) => q.t >= now - PACE_WINDOW_MS * 2);
      }
    }, setLink);
    const done = async () => {
      try {
        const st = await fetchBookingStatus(bid);
        if (st === 'completed') {
          // [0063] local end fallback — the completion push (settled numbers) also ends the LA
          // server-side; whichever lands first wins, the other is a no-op. Uses the last drawn
          // props so the banner never shows numbers this screen did not.
          if (laPropsRef.current) {
            endOwnerActivity({ ...laPropsRef.current, phase: 'done', targetKm: '', pace: '', statusLine: '' });
          }
          router.replace({ pathname: '/owner/report', params: { bid } });
          return;
        }
        // [2026-08-20] The other way a run ends. No navigation: this screen IS the artifact during
        // a hold. `held` only ever gates claims — the map, the trace and the last numbers stay.
        heldRef.current = !LIVE_STATUS.has(st);
        setHeld(heldRef.current ? st : null); // reversible by the same 10s poll that set it
      } catch { /* 폴백이 처리 */ }
    };
    const unsubBk = subscribeBooking(bid, done);
    const poll = setInterval(done, 10000);
    const tick = setInterval(() => {
      // Heartbeat only — the first-fix clock no longer feeds a displayed number (§1 precondition).
      if (startAt.current) setLiveSec(Math.floor((Date.now() - startAt.current) / 1000));
      // Elapsed is "how long the run has been going", measured off runs.started_at — a sentence that
      // only holds while the run is going. Once the booking leaves LIVE_STATUS the count would
      // climb forever off a run that already ended, so the tick stops WRITING it and the last
      // value stays on screen: clearing it would fabricate absence, and the run really did run
      // that long. (staleSec keeps ticking — the location channel's state is still a real fact.)
      if (runStartedAt.current && !heldRef.current) setElapsedSec(Math.max(0, Math.floor((Date.now() - runStartedAt.current) / 1000)));
      if (lastFixAt.current) setStaleSec(Math.floor((Date.now() - lastFixAt.current) / 1000));
    }, 1000);
    return () => { unsubPos(); unsubBk(); clearInterval(poll); clearInterval(tick); };
  }, [bookingId]);

  // runs.started_at + the frozen pace suggestion, in one round trip. The run may not have begun
  // when this screen opens (a booking is "진행 중" from confirmed onward), so this retries until
  // the row exists — and stops the moment it does. Failure stays silent-but-honest: no
  // started_at means the stats keep their '—', never a count invented on the client.
  useEffect(() => {
    if (!bookingId) return;
    const bid = bookingId;
    let alive = true;
    const pull = () => {
      fetchRunMeta(bid)
        .then((m) => {
          if (!alive) return;
          if (m.paceSuggestSec != null) setRunSuggestSec(m.paceSuggestSec);
          const ms = m.startedAt ? new Date(m.startedAt).getTime() : NaN;
          if (Number.isFinite(ms)) {
            runStartedAt.current = ms;
            setElapsedSec(Math.max(0, Math.floor((Date.now() - ms) / 1000)));
          }
        })
        .catch(() => { /* the retry below owns recovery */ });
    };
    pull();
    const id = setInterval(() => {
      if (runStartedAt.current != null) { clearInterval(id); return; }
      pull();
    }, 10000);
    return () => { alive = false; clearInterval(id); };
  }, [bookingId]);

  // ---------- 코스 트레이스 ----------
  // fetchMeetupInfo는 route_id와 코스 **이름**만 싣고 트레이스는 싣지 않는다 (api.ts의
  // fetchMeetupInfo 참조 — 줄 번호로 쓰지 않는다: 종전의 `:1767-1769`는 이미 다른 함수를
  // 가리키고 있었다). 선은 여기서 따로 온다. fetchRouteById는 라이프사이클 무관으로 읽으므로
  // 정지된 코스로 예약한 러닝도 계획선을 잃지 않는다. 실패해도 위치·기록·정산에는 닿지 않는다.
  useEffect(() => {
    const rid = info?.routeId;
    if (!rid) return;
    let alive = true;
    setRouteState('loading');
    fetchRouteById(rid)
      .then((r) => { if (alive) { setRouteGeo(r); setRouteState('ready'); } })
      .catch((e) => { if (alive) { console.warn('[live] route:', e?.message ?? e); setRouteState('error'); } });
    return () => { alive = false; };
  }, [info?.routeId, geoTry]);

  // ---------- 픽업 핀 ----------
  // 삼상 계약 (api.ts의 fetchOwnerPickupCoords — 심볼로 인용한다, 종전의 `:2686-2689`는 이미
  // 어긋나 있었다): null = 예약에 주소가 없다 · 행은 있는데 lat이 NULL = 주소는 있으나 핀이
  // 없다 · throw = 못 불러왔다. 세 번째를 첫 번째로 접으면 '핀이 없어요'라는 거짓말이 되므로
  // 실패는 실패로 남긴다.
  useEffect(() => {
    if (!bookingId) return;
    const bid = bookingId;
    let alive = true;
    setPickup({ s: 'loading' });
    fetchOwnerPickupCoords(bid)
      .then((a) => { if (alive) setPickup({ s: 'ok', a }); })
      .catch((e) => {
        console.warn('[live] pickup:', e?.message ?? e);
        if (alive) setPickup({ s: 'err' });
      });
    return () => { alive = false; };
  }, [bookingId, geoTry]);

  // ---------- 지오메트리 (runner/run.tsx:376-398의 거울) ----------
  // ⚠ entryIdx는 **화면 로컬**이다. 목록의 trace_thumb(≤50점)와 여기 trace(≤200점)는 다른
  // 배열이라 인덱스가 서로를 가리키지 못한다 (route-geom.ts:24-28). 그래서 다른 화면이 계산한
  // 값을 받지 않고 **전체 트레이스 위에서** 다시 계산한다.
  const pickupLL = useMemo(() => {
    const a = pickup.s === 'ok' ? pickup.a : null;
    return a && a.lat != null && a.lng != null ? { lat: a.lat, lng: a.lng } : null;
  }, [pickup]);
  const traceLL = useMemo(() => routeGeo?.trace ?? [], [routeGeo]);
  const routeCoords = useMemo(
    () => traceLL.map((p) => ({ latitude: p.lat, longitude: p.lng })),
    [traceLL],
  );
  /** 입구 = 픽업에서 코스 **선 위**로 내린 수선의 발 (정점 최근접도, trace[0]도 아니다). */
  const entry = useMemo(() => (pickupLL ? nearestOnTrace(pickupLL, traceLL) : null), [pickupLL, traceLL]);
  const entryCoord = useMemo(
    () => (entry ? { latitude: entry.point.lat, longitude: entry.point.lng } : null),
    [entry],
  );
  // 회전은 **닫힌 루프에만**. rotateLoopAtEntry가 열린 경로면 입력과 같은 참조를 돌려주므로
  // 그 항등 비교가 곧 '이 코스는 닫혔는가'의 답이다 (route-geom.ts:176-180).
  const lapLL = useMemo(
    () => (entry ? rotateLoopAtEntry(traceLL, entry, LOOP_CLOSURE_M) : traceLL),
    [entry, traceLL],
  );
  const rotated = entry != null && lapLL !== traceLL;
  const lapCoords = useMemo(
    () => (rotated ? lapLL.map((p) => ({ latitude: p.lat, longitude: p.lng })) : routeCoords),
    [rotated, lapLL, routeCoords],
  );

  // 입구 도착 — 러너 화면(runner/run.tsx)의 술어를 **포함하되 더 넓다**. 같다고 적으면 안 된다:
  // 첫 줄(entry 점 ≤ ENTRY_REACHED_M)이 러너 쪽과 같은 테스트이고, 둘째 줄(트레이스 위 스냅)은
  // 이 화면에만 있는 추가 조건이다.
  // 왜 넓혀 두는가: 보호자는 보통 러닝 **중간에** 이 화면을 연다 — 첫 픽스가 이미 랩 위 어딘가,
  // 입구에서 한참 떨어진 곳이다. 코스 선 위(≤ 40 m, snapToRoute의 허용치)에 있는 픽스는 접근이
  // 끝났다는 뜻이므로 접근선을 그리지 않는다.
  // ⚠ 대가는 알고 받아들인 것이다: 코스 선에서 40 m 안쪽에 픽업이 있는 강변 예약이라면 첫 픽스에
  //   바로 atEntry가 걸려, 러너는 아직 입구로 안내받는 중인데 보호자 화면엔 '입구까지'가 없다.
  //   러너 화면이 안내의 정본이고 이 화면은 관전이라 그쪽으로 기울여 둔다.
  useEffect(() => {
    if (atEntry || !entry || !pos) return;
    const fix = { lat: pos.lat, lng: pos.lng };
    if (haversineM(fix, entry.point) <= ENTRY_REACHED_M) { setAtEntry(true); return; }
    if (traceLL.length > 1 && snapToRoute(traceLL, fix, { offRouteM: ENTRY_REACHED_M }).onRoute) setAtEntry(true);
  }, [atEntry, entry, pos, traceLL]);

  /** 접근선이 그려지는 동안인가. 카메라가 담아야 할 것이 무엇인지도 이 술어가 정한다. */
  const showApproach = !atEntry && pickupLL != null && entryCoord != null;

  /**
   * 계획 구도 — 첫 픽스 전에 지도가 가질 수 있는 유일한 정직한 카메라.
   *
   * 담아야 할 것은 랩만이 아니다. **접근선을 그리는 동안에는 픽업과 입구도 화면 안에 있어야
   * 한다**: 반포 픽업 + 서울숲 코스처럼 둘이 km 단위로 떨어진 예약에서 랩만 담으면 접근선과
   * 입구 마커가 화면 밖으로 나가고, 그러면 범례가 **화면에 없는 선**을 가리키게 된다 —
   * 그리지 않은 선의 스와치를 금지한 것과 같은 거짓말이다. (sim 확인 2026-08-19)
   *
   * ⚠ report.tsx:236-243의 `log2(360/latΔ)` 근사는 이 화면에서 쓸 수 없다. 그 식은 (a) 위도
   * 스팬만 보고 경도를 무시하고 (b) 뷰포트를 256px로 가정한다. report의 지도는 190pt 높이의
   * 작은 띠라 그 가정으로 충분했지만, 이 화면은 풀스크린이고 세로가 길다 — 같은 식이 한 단계
   * 이상 당겨진 줌을 내서 루프의 일부만 보였다.
   *
   * 그래서 각도가 아니라 **미터로 재고 실제 포인트 크기에 맞춘다**: 웹 메르카토르에서 줌 z의
   * 해상도는 156543.03 * cos(lat) / 2^z (m/px)이므로, 가로·세로가 각각 요구하는 m/px 중
   * **큰 쪽**이 두 축을 모두 담는 답이다.
   *
   * 카메라는 화면 중앙을 잡는데 상단 크롬과 하단 아일랜드가 지도를 덮으므로, 세로 가용폭은
   * "중앙을 기준으로 양쪽 모두 가려지지 않는 띠" = height − 2 × (덮개 중 큰 쪽)로 잡는다.
   * 중심을 위로 밀어 보정하는 대신 보수적으로 담는 쪽을 택했다 — 조금 넓게 보이는 것은
   * 사실이지만, 아일랜드 뒤에 숨은 선은 없는 선처럼 읽힌다.
   */
  const planCam = useMemo(() => {
    if (lapCoords.length < 2) return null; // 그릴 계획선이 없으면 계획 구도도 없다
    const pts: { lat: number; lng: number }[] = lapCoords.map((c) => ({ lat: c.latitude, lng: c.longitude }));
    if (showApproach && pickupLL) pts.push(pickupLL);
    if (showApproach && entryCoord) pts.push({ lat: entryCoord.latitude, lng: entryCoord.longitude });

    let n = -90, s2 = 90, e = -180, w = 180;
    for (const p of pts) {
      n = Math.max(n, p.lat); s2 = Math.min(s2, p.lat);
      e = Math.max(e, p.lng); w = Math.min(w, p.lng);
    }
    const midLat = (n + s2) / 2, midLng = (e + w) / 2;
    const spanXm = haversineM({ lat: midLat, lng: w }, { lat: midLat, lng: e });
    const spanYm = haversineM({ lat: s2, lng: midLng }, { lat: n, lng: midLng });

    // 아일랜드를 아직 재지 못했으면 보수적으로 예약한다 — 측정 뒤 구도는 좁아지지 않고
    // 넓어지기만 하는 방향이라, 처음 한 프레임이 선을 숨기는 일이 없다.
    const cover = Math.max(MAP_TOP_COVER_PT, islandH > 0 ? islandH : 300);
    const usableW = Math.max(120, winW - 2 * MAP_PAD_PT);
    const usableH = Math.max(120, winH - 2 * cover);
    // 한 점뿐(스팬 0)일 때 줌이 발산하지 않도록 바닥 해상도를 둔다.
    const mpp = Math.max((spanXm / usableW) * MAP_FIT_PAD, (spanYm / usableH) * MAP_FIT_PAD, 0.3);
    const zoom = Math.log2((156543.03392 * Math.cos((midLat * Math.PI) / 180)) / mpp) - MAP_ZOOM_TRIM;
    return { latitude: midLat, longitude: midLng, zoom: Math.min(17, Math.max(9, zoom)) };
  }, [lapCoords, showApproach, pickupLL, entryCoord, islandH, winW, winH]);

  // [honesty audit 2026-08-11 · P1 #3] Before this fix confirmStop made no server call: it closed
  // the sheet, claimed "러너에게 알렸어요", and discarded the chosen reason. No owner-side server
  // transition exists for an active run (transition-booking: cancel_owner covers pre-run states
  // only; settle-run is 403 for anyone but the assigned runner). The only real delivery channel
  // is chat — so the chosen reason is now sent as an actual chat message (recorded in the thread)
  // and the sheet closes only on success. The settlement copy below (remaining-50% guarantee +
  // min fare) is the real settle-run policy applied when the runner ends with 'owner_request'.
  const confirmStop = async () => {
    if (!bookingId || !stopReason || stopBusy) return;
    setStopBusy(true);
    try {
      const threadId = await ensureThread(bookingId);
      await sendChatMessage(
        threadId,
        `[러닝 종료 요청] 사유: ${stopReason}\n안전한 지점에서 정지한 뒤 픽업 장소로 복귀 부탁드려요.`,
      );
      // [2026-08-11] 채팅만으로는 **도달하지 않는다** — messages는 notifications 행을 만들지 않고,
      // 0024의 푸시 브리지는 notifications INSERT에만 걸린다. 그래서 러너가 채팅을 열기 전까지
      // 중단 요청이 보이지 않았다. 이제 알림도 함께 넣는다 (기록은 채팅, 도달은 알림).
      // 알림 실패가 이미 전송된 채팅을 되돌릴 수는 없으므로 여기서 던지지 않는다 — 다만
      // 뒤따르는 카피가 '푸시가 갔다'고 주장하지 않도록 성공 여부를 들고 간다.
      // `sent`는 '알림 행을 넣었다'는 뜻이지 '러너 폰에 떴다'가 아니다 — 0024 트리거가 푸시 오류를
      // 삼키므로 앱은 배달을 알 수 없다. 그래서 성공 경로는 배달을 주장하지 않는다.
      let sent = false;
      try { sent = await notifyRunStop(bookingId, stopReason); } catch { sent = false; }
      setStopSheet(false);
      if (!sent) {
        Alert.alert('요청은 채팅으로 전달됐어요',
          '알림은 보내지 못했어요 — 러너가 채팅을 열어야 볼 수 있어요. 급하면 직접 연락해주세요.');
      }
      // 어느 쪽이든 채팅 스레드로 — 보낸 요청이 눈에 보이는 곳이다 (주장이 아니라 증거).
      router.push({ pathname: '/chat', params: { bid: bookingId } });
    } catch (e) {
      // Failure renders as failure — sheet stays open, retry possible
      Alert.alert('요청을 보내지 못했어요', (e as Error)?.message ?? '네트워크를 확인하고 다시 시도해주세요');
    } finally {
      setStopBusy(false);
    }
  };

  const dogName = info?.dogName ?? '반려견';
  const runnerName = info?.runnerName ?? '러너';
  const targetKm = info?.km ?? null; // 목표 거리는 실예약에서만 — draft 목업 5km 폴백 퇴역
  // 첫 GPS 픽스 전에는 거리·시간·페이스를 모른다 — 0을 주장하지 않는다 (로딩 ≠ 0)
  const hasFix = pos != null;
  // The hold's words, or null. Keyed on `held` and not on a boolean so a status we have no honest
  // sentence for (no_show / cancelled_* — only reachable on a cold entry that opened this screen
  // before the run began) does not borrow the incident copy. Those still stop the elapsed clock
  // via heldRef; they just do not get a strip.
  const heldCopy = held ? HELD_COPY[held] ?? null : null;
  // 90초 넘게 갱신이 없으면 지도의 점은 더 이상 '지금'이 아니다 — 그렇다고 말한다.
  const stale = hasFix && staleSec >= 90;
  const staleMin = Math.max(1, Math.floor(staleSec / 60));
  const km = pos?.km ?? 0;
  // 경과는 runs.started_at에서만 온다 — 모르면 모른다고 말한다 (숫자를 지어내지 않는다).
  const hasElapsed = elapsedSec != null;
  const sec = elapsedSec ?? 0;
  const progressT = hasFix && targetKm != null ? Math.min(km / Math.max(targetKm, 0.1), 1) : 0;

  // ---------- 지도 게이트 (RULING 9) ----------
  // 예전에는 `maps && pos`였다 — 픽스가 오기 전에는 지도가 통째로 없었다. 계획 경로와 픽업은
  // 첫 픽스보다 **먼저** 알 수 있는 사실이라, 그것만으로도 지도를 띄운다. 다만 두 경우는
  // 예외다: 권한 없음(denied)과 연결 실패(error)에서는 지도를 띄우지 않는다 — '권한이 없어요'
  // 밑에 깔린 계획선은 개가 지금 저기 있다는 말로 읽힌다.
  const planOnly = pos == null && planCam != null && link !== 'denied' && link !== 'error';
  // 픽스가 있으면 오늘과 똑같이 러너를 따라가고, 없으면 계획 전체(랩 + 접근선)를 담는다.
  const camera = useMemo(
    () => (pos ? { latitude: pos.lat, longitude: pos.lng, zoom: 15 } : planCam),
    [pos, planCam],
  );

  // 범례 — **지금 실제로 그려지고 있는 선만** 적는다. 그리지 않은 선의 스와치는 그 자체로
  // 거짓말이다 (계획선이 없는데 '계획 경로'라고 적으면 화면에 없는 것을 찾게 만든다).
  const legend: { c: string; t: string }[] = [];
  if (lapCoords.length > 1) legend.push({ c: lilac.accent, t: '계획 경로' });
  if (showApproach) legend.push({ c: paper.ink, t: '입구까지' });
  if (pathLen > 1) legend.push({ c: colors.voltDeep, t: '지금까지' });

  // 계획선·접근선이 빠졌을 때의 정직 고지. 어느 것도 위치·기록·정산을 막지 않는다 (자문이다).
  // 실패(재시도 가능)와 부재(재시도해도 같은 답)는 다른 사실이므로 버튼도 다르게 붙는다.
  const geoNote = ((): { text: string; retry: boolean } | null => {
    // routeState === 'idle'은 '아직 아무것도 시도하지 않았다'는 뜻이고, 그 자리에 머무는 경우가
    // 셋이다: 예약 컨텍스트를 못 읽었다(infoErr) · 읽는 중이다(info == null) · 읽었는데 이
    // 예약에 코스가 없다(routeId == null). 첫째와 셋째는 서로 다른 사실이라 다르게 말한다.
    // 둘째(로딩)는 아무 말도 하지 않는다 — 모르는 것에 문장을 얹지 않는다.
    if (routeState === 'idle' && infoErr) {
      return { text: '예약 정보를 불러오지 못했어요 — 계획 경로와 입구 안내선이 빠져요', retry: true };
    }
    if (routeState === 'idle' && info != null && info.routeId == null) {
      return { text: '이 러닝에는 코스가 지정되지 않았어요 — 실시간 경로만 그려져요', retry: false };
    }
    if (routeState === 'error') return { text: '계획 경로를 불러오지 못했어요 — 러닝 기록에는 영향 없어요', retry: true };
    if (pickup.s === 'err') return { text: '픽업 위치를 불러오지 못했어요 — 입구까지의 안내선만 빠져요', retry: true };
    if (routeState === 'ready' && !routeGeo) return { text: '배정된 코스 정보를 찾을 수 없어요 — 러닝 기록에는 영향 없어요', retry: false };
    if (routeState === 'ready' && routeGeo && routeCoords.length < 2) {
      return { text: '이 코스는 아직 실측 전이에요 — 계획 경로 없이 실시간 경로만 그려져요', retry: false };
    }
    return null;
  })();

  // The suggestion the caption prints. Priority: the run-start snapshot (frozen truth) → the
  // dog's current pref from a SUCCESSFUL MeetupInfo fetch (pre-run, and pre-0079 the only
  // source there is; its null means the owner never set one = confirmed absent = default 480).
  // Both unknown (info never loaded / fetch failed) → null: no caption, no chip. §6's
  // fetch-fail row — defaulting to 480 against an owner who set 9'00" claims what we lack.
  const suggestSec = runSuggestSec != null ? clampSuggest(runSuggestSec)
    : info != null ? clampSuggest(info.paceSuggestSec)
    : null;

  // §1 machine, recomputed on the 1s tick. Stale returns '' inside paceState (stale ≠ slow),
  // and the latch keeps its memory across it so recovery restores the prior state.
  useEffect(() => {
    if (suggestSec == null) { setPace(''); return; }
    const next = paceState(prevPace.current, {
      windowSec: windowPaceSec(pacePairs.current, Date.now()),
      suggestSec,
      km,
      elapsedSec: sec,
      stale,
    });
    if (next !== '') prevPace.current = next;
    setPace(next);
  }, [suggestSec, km, sec, stale]);

  // ---------- [0063] owner Live Activity — this screen's lock-screen mirror ----------
  // While the app is awake this screen refreshes the LA locally from the same broadcast that draws
  // the map (5s throttle — runner LA convention). The moment the app sleeps, the 0063 APNs
  // pipeline takes over from runs.trace — same truth, different transport. Same honesty rules as
  // this screen: no fix → no number, stale ≥90s → the number greys out and says how long.
  const laPropsRef = useRef<OwnerLAProps | null>(null);
  const laLast = useRef(0);
  const laProps: OwnerLAProps = {
    // 'ended' is the phase the widget was built for and nothing ever set: "a run aborted into
    // incident_review — a live-looking banner surviving an aborted run would be a lie"
    // (src/activities/OwnerRunActivity.tsx:9-10, which draws 러닝이 종료됐어요 · 앱에서 자세히
    // 확인하세요). Same fact as the pill above, on the lock screen.
    phase: heldCopy ? 'ended' : !hasFix ? 'running' : stale ? 'stale' : 'running',
    dogName,
    runnerName,
    km: hasFix ? km.toFixed(2) : '',
    targetKm: targetKm != null ? String(targetKm) : '',
    pace: hasFix && hasElapsed && !stale ? paceStr(sec, km) : '',
    elapsed: hasFix && hasElapsed && !stale ? fmt(sec) : '',
    statusLine: !hasFix ? '' : stale ? `${staleMin}분째 위치가 갱신되지 않았어요` : '방금 업데이트',
    // Local-update nicety only — the server (0079) computes the state that rides real pushes.
    paceState: pace,
  };
  // Mirror the drawn props into the ref after every commit (no deps) — refs are not written
  // during render. Declared before the two LA effects below, so effect order guarantees they
  // read this render's props; the `done` handler above reads it asynchronously and null-checks.
  useEffect(() => {
    laPropsRef.current = laProps;
  });
  // Adopt-or-start (re-entry safe) + per-activity push token registration — needs real identities,
  // so it waits for info. This screen only opens for a live booking, so the state gate holds.
  useEffect(() => {
    if (!bookingId || !info) return;
    startOwnerActivity(bookingId, laPropsRef.current!);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bookingId, info]);
  // Local refresh — every position/clock/staleness change, throttled to 5s.
  useEffect(() => {
    if (!bookingId || !info) return;
    const now = Date.now();
    if (now - laLast.current < 5000) return;
    laLast.current = now;
    updateOwnerActivity(laPropsRef.current!);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pos, liveSec, staleSec]);

  // ---------- 해석 중 · 없음 · 실패 — 지도도 숫자도 없는 중립 대기면 ----------
  if (resolve !== 'ready') {
    return (
      <View style={s.root}>
        <StatusBar style="dark" />
        <Row style={s.topBar}>
          <Pressable onPress={goBack} style={s.squareBtn}><Text style={s.backGlyph}>‹</Text></Pressable>
        </Row>
        <View style={s.waitWrap}>
          {resolve === 'error' ? (
            <View style={s.failStrip}>
              <Text style={s.failTxt}>상태를 확인하지 못했어요</Text>
              <Pressable onPress={resolveBooking} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
                <Text style={s.failRetry}>다시 시도</Text>
              </Pressable>
            </View>
          ) : resolve === 'resolving' ? (
            <Text style={s.waitTitle}>예약 확인 중...</Text>
          ) : null}
        </View>
      </View>
    );
  }

  return (
    <View style={s.root}>
      <StatusBar style="dark" />

      {/* ---------- 풀스크린 지도 레이어 — 지도가 곧 화면이다 ---------- */}
      {maps && camera && (pos != null || planOnly) ? (
        <maps.NaverMapView
          style={StyleSheet.absoluteFill}
          camera={camera}
          isShowLocationButton={false}
          isShowCompass={false}
          isShowScaleBar={false}
          isShowZoomControls={false}
        >
          {/* 계획된 랩 — '인쇄된 코스도'. 흰 케이싱, 실측선 **아래**(z0). 닫힌 루프면 입구에서
              시작하도록 회전된 좌표를 그린다 — 회전은 그리는 순서를 바꿀 뿐 이 선이 무엇인지를
              바꾸지 않는다. */}
          {lapCoords.length > 1 && (
            <maps.NaverMapPathOverlay
              coords={lapCoords}
              width={3}
              color={lilac.accent}
              outlineWidth={1}
              outlineColor="#FFFFFF"
              zIndex={0}
            />
          )}
          {/* 접근 구간 — 픽업에서 입구까지. **직선**이다: 우리에게 도로 라우팅이 없고 문구도
              그렇게 말한다. 입구에 닿으면 할 일을 다 했으므로 사라진다. */}
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
          {/* 스무딩은 렌더 전용 — 픽스 게이트는 소스(러너 run.tsx)에서 이미 적용됨.
              [RULING 9 · 2026-08-19] 색을 paper.line(코랄 브랜드 헤어라인)에서 colors.voltDeep으로
              고친다. 라이브 = voltDeep, 계획 = lilac.accent가 법이고 run.tsx·report.tsx는 이미
              그 값을 쓰고 있었다 — 이 화면 하나만 실측선을 섹션 구분선·LIVE 도트·진행 바와 같은
              토큰으로 그리고 있었다. */}
          {pathLen > 1 && (
            <maps.NaverMapPathOverlay
              coords={smoothTrace(path.current)}
              color={colors.voltDeep}
              width={6}
              outlineWidth={2}
              outlineColor="#ffffff"
              zIndex={1}
            />
          )}
          {/* 입구 — 러너가 인도되는 대상. 도착하면 사라진다 (러너 화면과 같은 글리프·같은 캡션). */}
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
          {pos && (
            <maps.NaverMapMarkerOverlay
              latitude={pos.lat}
              longitude={pos.lng}
              anchor={{ x: 0.5, y: 1 }}
              caption={{ text: `${dogName} · ${runnerName} 러너` }}
              zIndex={3}
            />
          )}
        </maps.NaverMapView>
      ) : (
        <View style={[StyleSheet.absoluteFill, { alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 }]}>
          {/* 빈 지도는 세 가지 서로 다른 사실을 똑같이 그린다: 아직 안 왔다 / 받을 권한이 없다 /
              연결에 실패했다. 앞의 것만 말하면 나머지 둘은 '가만히 있는 개'로 읽힌다. */}
          {link === 'denied' ? (
            <>
              <Text style={s.waitTitle}>위치 공유 권한이 없어요</Text>
              <Text style={s.waitBody}>
                이 러닝의 실시간 위치는 예약한 보호자와 배정된 러너만 볼 수 있어요.{'\n'}
                러닝이 끝났거나 러너가 변경되면 연결이 끊겨요.
              </Text>
            </>
          ) : link === 'error' ? (
            <>
              <Text style={s.waitTitle}>실시간 위치에 연결하지 못했어요</Text>
              <Text style={s.waitBody}>
                네트워크를 확인해주세요 — 러닝과 기록은 그대로 진행돼요.{'\n'}
                화면을 나갔다 들어오면 다시 연결을 시도해요.
              </Text>
            </>
          ) : (
            <>
              <Text style={s.waitTitle}>러너 위치 수신 대기 중...</Text>
              <Text style={s.waitBody}>
                러너가 달리기 시작하면 실시간 경로가 그려져요{'\n'}{!maps ? '(실지도는 새 개발 빌드에서)' : ''}
              </Text>
            </>
          )}
        </View>
      )}

      {/* ---------- 지도 위 대기 스트립 ----------
          계획선이 먼저 떠 있어도 '내 개의 점이 아직 없다'는 사실은 따로 말한다. 지도를 대체하지
          않고 지도 위에 조용히 얹힌다 — 대체하면 계획선을 볼 수 없고, 말하지 않으면 계획선이
          지금 위치처럼 읽힌다. (denied/error는 위에서 이미 지도를 가져갔다) */}
      {maps && camera && planOnly && (
        <View style={s.mapNote}>
          <Text style={s.mapNoteTitle}>러너 위치 수신 대기 중...</Text>
          <Text style={s.mapNoteBody}>지금은 계획된 코스만 보여요 — 러너가 달리기 시작하면 실시간 경로가 그려져요</Text>
        </View>
      )}

      {/* ---------- 범례 — 그려진 선만 ----------
          아일랜드 실측 높이 위에 얹는다 (islandH가 0인 첫 프레임에는 그리지 않는다 — 아일랜드
          밑으로 한 번 깜빡이는 것을 막는다). */}
      {maps && camera && (pos != null || planOnly) && legend.length > 0 && islandH > 0 && (
        <View style={[s.legend, { bottom: islandH + 10 }]}>
          {legend.map((l) => (
            <Row key={l.t} style={{ gap: 4, alignItems: 'center' }}>
              <Text style={[s.legendSwatch, { color: l.c }]}>━</Text>
              <Text style={s.legendTxt}>{l.t}</Text>
            </Row>
          ))}
        </View>
      )}

      {/* 시스템 바 스트립 — 지도가 시계·노치 뒤로 번지던 것. 지도·대기 스트립 **위**,
          상단 오버레이 **아래**: 뒤로/LIVE/SOS 는 안전 영역 바로 아래에서 시작하므로 가려지지 않는다. */}
      <StatusBarCover />

      {/* ---------- 상단 오버레이 ---------- */}
      <Row style={s.topBar}>
        <Pressable onPress={goBack} style={s.squareBtn}><Text style={s.backGlyph}>‹</Text></Pressable>
        {/* LIVE는 근거가 있을 때만 — 위치 픽스 전에는 '달리는 중'이라고 말하지 않는다.
            (진행 중 예약에는 confirmed·인계 대기도 포함된다 — 아직 러닝이 아니다)
            [2026-08-20] Fix freshness alone is not enough evidence. A run stopped by an incident
            can keep receiving fixes, and 「LIVE · {dog}가 달리는 중」 is then a claim the server
            contradicts. The booking status is the older fact, so it is tested first. */}
        <View style={s.livePill}>
          <Text style={s.livePillTxt}>
            <Text style={{ color: hasFix && !stale && !heldCopy ? paper.line : paper.faint }}>●</Text>
            {heldCopy ? ` ${dogName} · ${heldCopy.pill}`
              : !hasFix ? ` ${dogName} · 위치 수신 대기` : stale ? ` ${dogName} · 위치 갱신 없음` : ` LIVE · ${dogName}가 달리는 중`}
          </Text>
        </View>
        {/* SOS = 긴급 어포던스 — 라우드 페일 토큰이 정확히 이 자리를 위한 색이다 */}
        <Pressable onPress={() => router.push('/safety')} style={s.sosBtn}>
          <Text style={s.sosTxt}>SOS</Text>
        </Pressable>
      </Row>

      {/* ---------- 하단 아일랜드 카드 (풀블리드 · 샤프 · 1px 코랄 프레임) ---------- */}
      <View style={s.island} onLayout={(e) => setIslandH(e.nativeEvent.layout.height)}>
        {/* runner row */}
        <Row style={{ gap: 11, alignItems: 'center' }}>
          <Avatar url={null} char={runnerName[0]} bg={paper.ink} size={44} />
          <View style={{ flex: 1 }}>
            <Text style={s.runnerName}>{runnerName} 러너</Text>
            <Text style={s.runnerMeta}>
              {info?.routeName ?? '코스'}{targetKm != null ? ` · ${targetKm}km` : ''}
            </Text>
          </View>
          {/* 신호 상태는 두 상태가 명시적으로 달라야 한다 (양육권 법) — 면색·잉크·도트 전부 구분.
              '수신 중'과 '멈춘 지 오래'도 서로 다른 상태다 (프리즈를 라이브로 그리지 않는다) */}
          <View style={[s.signalPill, hasFix && !stale ? s.signalOn : s.signalOff]}>
            <Text style={hasFix && !stale ? s.signalTxtOn : s.signalTxtOff}>
              <Text style={{ color: hasFix && !stale ? paper.line : paper.faint }}>●</Text> {!hasFix ? '수신 대기' : stale ? '갱신 없음' : '위치 수신'}
            </Text>
          </View>
        </Row>

        {/* [2026-08-20 hold] This strip REPLACES the staleness strip below, never stacks with it:
            during an incident 「위치가 N분째 갱신되지 않았어요 · 채팅으로 확인」 puts a
            network-trouble sentence on a safety event, which was this screen's worst lie. The map
            keeps the last fix it received — real data is not erased; the sentence is what says that
            point is not 'now'. Ground is criticalWash on purpose: failStrip (canvas) is this file's
            token for "it just failed, retry", and this is a hold waiting on someone else's
            decision. Same values as owner/meetup.tsx's hold strip — one incident, one voice. */}
        {heldCopy && (
          <View style={s.holdStrip}>
            <Text style={s.holdTxt}>{heldCopy.strip}</Text>
            {/* push, never replace — the owner has to be able to come back to the last-known
                position map, the most important artifact they have during a hold */}
            <Row style={{ gap: 10, marginTop: 10 }}>
              <Pressable
                onPress={() => router.push({ pathname: '/chat', params: { bid: bookingId! } })}
                style={s.holdBtn}
                accessibilityRole="button"
                accessibilityLabel="러너와 채팅"
              >
                <Text style={s.holdBtnTxt}>러너와 채팅</Text>
              </Pressable>
              <Pressable
                onPress={() => router.push('/safety')}
                style={s.holdBtnInk}
                accessibilityRole="button"
                accessibilityLabel="안전 센터 열기"
              >
                <Text style={s.holdBtnInkTxt}>안전 센터 열기</Text>
              </Pressable>
            </Row>
          </View>
        )}
        {/* 신선도 — 멈춘 점을 라이브라고 말하지 않는다 */}
        {stale && !heldCopy && (
          <View style={[s.failStrip, { marginTop: 12 }]}>
            <Text style={s.failTxt}>위치가 {staleMin}분째 갱신되지 않았어요</Text>
            <Pressable onPress={() => router.push({ pathname: '/chat', params: { bid: bookingId! } })} hitSlop={8} accessibilityRole="button" accessibilityLabel="러너와 채팅으로 확인">
              <Text style={s.failRetry}>채팅으로 확인</Text>
            </Pressable>
          </View>
        )}
        {/* 러너 빌드가 포그라운드 전용일 때만 (mode 없는 구 빌드에선 아무것도 추측하지 않는다) */}
        {pos?.mode === 'foreground' && (
          <Text style={s.modeNote}>러너 앱이 화면에 떠 있는 동안만 위치가 전송돼요 — 잠시 끊길 수 있어요</Text>
        )}
        {/* 계획선/접근선이 빠진 이유. 조용한 고지지 실패 스트립이 아니다 — 러닝 자체는 멀쩡하다.
            '다시 시도'는 실제로 세 fetch를 다시 부른다 (geoTry: 예약 컨텍스트 · 코스 · 픽업). */}
        {geoNote && (
          <Row style={{ marginTop: 10, gap: 8, alignItems: 'center' }}>
            <Text style={[s.modeNote, { marginTop: 0, flex: 1 }]}>{geoNote.text}</Text>
            {geoNote.retry && (
              <Pressable
                onPress={() => setGeoTry((t) => t + 1)}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel="코스·픽업 정보 다시 불러오기"
              >
                <Text style={s.geoRetry}>다시 시도</Text>
              </Pressable>
            )}
          </Row>
        )}

        {/* 라이브 캠 슬롯 — 오늘은 null이라 아무것도 그려지지 않는다 */}
        <StreamSlot session={streamSession} />

        {/* stats — 픽스 전에는 전부 '—' (0km·00:00을 실측처럼 보여주지 않는다) */}
        <Row style={{ marginTop: 14, justifyContent: 'space-between', alignItems: 'flex-end' }}>
          <View>
            <Text style={[s.kmNum, nf]}>
              {hasFix ? km.toFixed(2) : '—'}<Text style={s.kmUnit}> km</Text>
            </Text>
          </View>
          <View style={{ alignItems: 'center' }}>
            {/* 시간은 runs.started_at을 알 때만 — 마운트 기준 카운트는 이 화면에서 퇴역했다 */}
            <Text style={[s.statNum, nf]}>{hasFix && hasElapsed ? fmt(sec) : '—'}</Text>
            <Text style={s.statLabel}>시간</Text>
          </View>
          <View style={{ alignItems: 'flex-end' }}>
            {/* 신호가 끊기면 마지막 페이스는 더 이상 '지금'이 아니다 — 숫자를 비운다 ('없음'≠'느림').
                설명은 위의 신선도 스트립이 진다. */}
            <Text style={[s.statNum, nf]}>{hasFix && hasElapsed && !stale ? paceStr(sec, km) : '—'}</Text>
            <Text style={s.statLabel}>페이스</Text>
          </View>
        </Row>
        {/* thin progress — 각진 코랄 필 (목표 거리를 알 때만 찬다) */}
        <View style={s.progressTrack}>
          <View style={[s.progressFill, { width: `${progressT * 100}%` }]} />
        </View>

        {/* 페이스 상태 (plan §3a Ⓐ②) — 기준이 판정을 앞선다: 권장 캡션은 아는 순간부터 혼자 서 있고,
            칩은 상태가 생길 때만 끼어든다 (애니메이션 없는 이산 삽입 · 모프 법). 신선도 스트립이
            뜨면 칩은 같은 줄에서 빠지고 캡션만 남는다 — 두 번의 리플로를 쌓지 않는다. */}
        {(suggestSec != null || pace !== '') && (
          <Row style={s.paceRow}>
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
        )}

        {/* actions — 채팅이 이 화면의 유일한 잉크 CTA, 종료는 destructive.
            [2026-08-20 hold] The whole row leaves during a hold and the strip above carries the
            actions. The stop request promises, about a run that has already ended, 「러너가 확인하면
            안전하게 정지한 뒤 픽업 장소로 복귀해요」 and 「요금은 예약하신 그대로 청구돼요」 — but an
            incident is not settled down that path (0072_incident_settlement.sql §B settles the case
            separately, and it can refund), so both sentences become promises we cannot keep. Chat
            survives inside the strip, so the same button is never drawn twice. */}
        {!heldCopy && (
          <Row style={{ gap: 10, marginTop: 14 }}>
            <Pressable
              onPress={() => router.push({ pathname: '/chat', params: { bid: bookingId! } })}
              style={({ pressed }) => [s.chatBtn, pressed && s.chatBtnPressed]}
              accessibilityRole="button"
              accessibilityLabel="러너와 채팅"
            >
              <Text style={s.chatBtnTxt}>러너와 채팅</Text>
            </Pressable>
            <Pressable
              onPress={() => { setStopReason(null); setStopSheet(true); }}
              style={({ pressed }) => [s.stopBtn, pressed && s.stopBtnPressed]}
              accessibilityRole="button"
              accessibilityLabel="러닝 종료 요청"
            >
              <Text style={s.stopGlyph}>■</Text>
            </Pressable>
          </Row>
        )}
      </View>

      {/* ---------- stop confirmation sheet ---------- */}
      <Modal visible={stopSheet} transparent animationType="slide" onRequestClose={() => setStopSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setStopSheet(false)} />
        <View style={s.stopSheet}>
          <View style={s.sheetHandle} />
          <Text style={s.sheetTitle}>정말 러닝을 종료할까요?</Text>
          {/* 정직 카피 — 실제로 일어나는 것만: 채팅(기록) + 알림(도달) → 러너가 확인 → 정지·복귀.
              2026-08-11까지는 채팅뿐이었고 그건 러너가 채팅을 열어야만 보였다. 이제 알림도 간다. */}
          <Text style={s.sheetBody}>
            종료 요청과 사유를 러너에게 알림으로 보내고 채팅에도 남겨요.{'\n'}러너가 확인하면 안전하게 정지한 뒤 {dogName}를 데리고 픽업 장소로 복귀해요.
          </Text>

          <Text style={s.sheetLabel}>종료 사유</Text>
          {STOP_REASONS.map((r) => (
            <Pressable key={r} onPress={() => setStopReason(r)} style={[s.reasonRow, stopReason === r && s.reasonRowSel]}>
              <View style={[s.radio, stopReason === r && { borderColor: paper.ink }]}>
                {stopReason === r && <View style={s.radioDot} />}
              </View>
              <Text style={[s.reasonTxt, stopReason === r && { fontWeight: '800', color: paper.ink }]}>{r}</Text>
            </Pressable>
          ))}

          {/* [2026-08-13] This note said three things and all three were false for the case
              it appears in — the owner asking to stop. Found by the ⑩ class sweep.
              ① "지금까지 달린 거리 기준으로 정산돼요" — the OPPOSITE of the rule. An
                 owner-caused end bills the PLANNED distance (`0084 §A`: `v_basis := b.km`,
                 rule `owner_caused_planned`), which is D2's anti-cut-short decision: stopping
                 early must not be a way to pay less. The fare works out to exactly
                 base_fare + distance_fare + addon_fare — the quote, unchanged.
              ② "최소 기본요금 9,900원" — 9,900 is `runnerCompBase`, the RUNNER's floor
                 (ctx.ts warns the two pots are different). The owner's base is 7,900, and
                 `compute_owner_charge` never reads `min_fare` at all. There is no owner-side
                 minimum; quoting one invented a floor under a bill that is actually fixed.
              ③ "러너에게는 잔여 거리 보장이 적용돼요" — true only when the run is settled as
                 `owner_request`/`owner_forced`, and this screen cannot pin that: the request
                 goes out as a chat message and a notification, and the runner then chooses the
                 reason freely. It is also the runner's money on the owner's screen.
              So: say the one thing that is true and load-bearing for the decision being made —
              stopping does not reduce the fare — and stop speaking for the runner's ledger. No
              new number appears: it is the price they already consented to at request (§0-bis
              shows the price exactly once). */}
          <View style={s.feeNote}>
            <Text style={s.feeTxt}>
              보호자 요청으로 종료되면 요금은 예약하신 그대로 청구돼요 — 남은 거리만큼 줄어들지 않아요.
            </Text>
          </View>

          {/* destructive-filled — 사유 없으면 명시 disabledFill (불투명도 트릭 퇴역).
              While sending: label swap + lock (no opacity paint) */}
          <Pressable
            style={[s.stopConfirm, !stopReason && s.stopConfirmOff]}
            disabled={!stopReason || stopBusy}
            onPress={confirmStop}
          >
            <Text style={[s.stopConfirmTxt, !stopReason && { color: paper.faint }]}>
              {stopBusy ? '전송 중...' : '종료 요청 보내기'}
            </Text>
          </Pressable>
          <Pressable style={{ alignItems: 'center', paddingVertical: 13 }} onPress={() => setStopSheet(false)}>
            <Text style={s.keepWatchTxt}>계속 지켜볼게요</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  // ---------- 상단 크롬 ----------
  topBar: { position: 'absolute', top: 56, left: 10, right: 10, justifyContent: 'space-between', zIndex: 2 },
  squareBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas,
    borderWidth: 1, borderColor: paper.line, alignItems: 'center', justifyContent: 'center',
  },
  backGlyph: { fontSize: 20.5, color: paper.ink },
  livePill: { backgroundColor: paper.ink, paddingVertical: 11, paddingHorizontal: 16, alignSelf: 'center' },
  livePillTxt: { fontSize: 14, fontWeight: '900', color: '#ffffff' },
  sosBtn: { width: 40, height: 40, backgroundColor: paper.critical, alignItems: 'center', justifyContent: 'center' },
  sosTxt: { fontSize: 14, fontWeight: '900', color: '#ffffff' },
  // ---------- 대기·실패면 ----------
  waitWrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 },
  waitTitle: { fontSize: 16, fontWeight: '900', color: paper.ink },
  waitBody: { fontSize: 15, color: paper.dim, marginTop: 6, textAlign: 'center', lineHeight: 19.5 },
  // 라우드 페일(F1.2) — 풀블리드 크리티컬 헤어라인 위아래 + 14pt/700 크리티컬 잉크
  failStrip: {
    alignSelf: 'stretch', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 12, paddingHorizontal: 16,
  },
  failTxt: { fontSize: 14, fontWeight: '700', color: paper.critical, flex: 1 },
  failRetry: { fontSize: 14, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // ---------- hold strip (확인 중 · 환불 중) ----------
  // Same critical vocabulary as failStrip, different ground: failStrip (canvas) is "it just failed,
  // retry", this is "it is being handled, wait". Ink is critical (#B3261E on #FBEAE7 = 8.9:1
  // measured). Identical values to owner/meetup.tsx's hold strip — one incident, one voice.
  holdStrip: {
    alignSelf: 'stretch', backgroundColor: paper.criticalWash,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 12, paddingHorizontal: 16, marginTop: 12,
  },
  holdTxt: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical },
  // Never two buttons of the same colour: 안전 센터 is the emphasized door (ink plate + white
  // label), 채팅 is the critical-hairline plate. Both land at 42pt so neither outranks by size.
  holdBtn: {
    flex: 1, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.critical,
    alignItems: 'center', paddingVertical: 10,
  },
  holdBtnTxt: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.critical },
  holdBtnInk: { flex: 1, backgroundColor: paper.ink, alignItems: 'center', paddingVertical: 11 },
  holdBtnInkTxt: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: '#ffffff' },
  // ---------- 아일랜드 (풀블리드 · 샤프 · 코랄 프레임) ----------
  island: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderColor: paper.line,
    padding: 18, paddingBottom: 30,
  },
  runnerName: { fontSize: 17, fontWeight: '900', color: paper.ink },
  runnerMeta: { fontSize: 15, color: paper.dim, marginTop: 2 },
  // 신호 칩 — 수신(잉크 온 워시 + 코랄 도트) / 대기(딤 온 캔버스 + 페인트 도트)
  signalPill: { paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center', borderWidth: 1 },
  signalOn: { backgroundColor: paper.wash, borderColor: paper.line },
  signalOff: { backgroundColor: paper.canvas, borderColor: paper.faint },
  signalTxtOn: { fontSize: 14, fontWeight: '800', color: paper.ink },
  signalTxtOff: { fontSize: 14, fontWeight: '800', color: paper.dim },
  modeNote: { fontSize: 14, color: paper.dim, marginTop: 10, lineHeight: 19 },
  // 잉크 밑줄 — 코랄 강조 예산을 쓰지 않는 어포던스 (실패 스트립의 크리티컬 링크와 역할이 다르다)
  geoRetry: { fontSize: 14, fontWeight: '800', color: paper.ink, textDecorationLine: 'underline' },
  // ---------- 지도 위 오버레이 (샤프 코너 · 흰 플레이트) ----------
  // 상단 바(top 56, 높이 40)를 지나 앉는다. 지도를 가리지 않도록 좌우 여백은 상단 바와 같다.
  mapNote: {
    position: 'absolute', top: 106, left: 10, right: 10,
    backgroundColor: 'rgba(255,255,255,0.92)', paddingVertical: 9, paddingHorizontal: 12,
  },
  mapNoteTitle: { fontSize: 14.5, fontWeight: '900', color: paper.ink },
  mapNoteBody: { fontSize: 14, color: paper.dim, marginTop: 2, lineHeight: 19 },
  // 범례 — 디테일 텍스트 플로어 14pt (랩의 12.5pt는 이 프로젝트에서 통과하지 않는다)
  legend: {
    position: 'absolute', left: 10, flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: 'rgba(255,255,255,0.92)', paddingVertical: 5, paddingHorizontal: 8,
  },
  legendSwatch: { fontSize: 14, fontWeight: '800', lineHeight: 18 },
  legendTxt: { fontSize: 14, color: paper.text, lineHeight: 18 },
  // 라이브 캠 슬롯 — null이면 렌더되지 않는다 (자리만 예약)
  streamSlot: { marginTop: 12, borderWidth: 1, borderColor: paper.line, paddingVertical: 8, paddingHorizontal: 12 },
  streamTxt: { fontSize: 14, fontWeight: '700', color: paper.text },
  kmNum: { fontSize: 34.5, lineHeight: 42, fontWeight: '900', color: paper.ink },
  kmUnit: { fontSize: 15, fontWeight: '700', color: paper.dim },
  statNum: { fontSize: 23, lineHeight: 28, fontWeight: '900', color: paper.ink },
  statLabel: { fontSize: 14, color: paper.dim, marginTop: 1 },
  progressTrack: { height: 5, backgroundColor: paper.disabledFill, marginTop: 12, overflow: 'hidden' },
  progressFill: { height: 5, backgroundColor: paper.line },
  // 페이스 상태 줄 — 칩(§3b: 16/800 · radius 0 · 틴트 면 · 보더 없음) 왼쪽, 권장 캡션 오른쪽.
  // 상태 칩이지 CTA가 아니다 — 코랄 라인+CTA 예산을 쓰지 않는다. 숫자는 어느 쪽도 물들이지 않는다.
  paceRow: { marginTop: 12 },
  paceChip: { paddingVertical: 6, paddingHorizontal: 10 },
  paceChipGood: { backgroundColor: paper.paceGoodWash },
  paceChipSlow: { backgroundColor: paper.paceSlowWash },
  paceChipTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800' },
  paceChipInkGood: { color: paper.paceGoodInk },
  paceChipInkSlow: { color: paper.paceSlowInk },
  paceTarget: { marginLeft: 'auto', fontSize: 14, lineHeight: 18, color: paper.dim },
  // 버튼 매트릭스 — secondary(wash 면 + 코랄 헤어라인 + actionInk 라벨) + destructive(캔버스 면
  // + 크리티컬 잉크·보더). [액션] 채팅은 이동이지 커밋이 아니다 -> 세컨더리. 이 화면은 코랄
  // **필**이 0개인 게 맞다: 예산은 상한이지 할당량이 아니고, 강조는 livePill(잉크=상태)이 진다.
  //
  // ⚠ 면은 세컨더리로 바뀌었는데 라벨과 pressed 면색이 프라이머리의 것으로 남아 있었다:
  //   #FFFFFF on paper.wash(#FFF6F4) = 실측 1.05:1 — 이 화면의 유일한 CTA가 사실상 보이지 않았다.
  //   PaperBtn의 secondary와 같은 값으로 맞춘다 (actionInk on wash = 5.99:1, pressed #FBE7E1).
  chatBtn: { flex: 1, backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line, alignItems: 'center', paddingVertical: 14 },
  chatBtnPressed: { backgroundColor: '#FBE7E1' }, // PaperBtn secondary pressed 면색과 동일 (토큰 미보유)
  chatBtnTxt: { fontSize: 16.5, fontWeight: '900', color: paper.actionInk },
  stopBtn: {
    width: 50, height: 50, backgroundColor: paper.canvas,
    borderWidth: 1, borderColor: paper.critical, alignItems: 'center', justifyContent: 'center',
  },
  stopBtnPressed: { backgroundColor: paper.criticalWash },
  stopGlyph: { fontSize: 14, fontWeight: '900', color: paper.critical },
  // ---------- 종료 시트 ----------
  sheetBackdrop: { flex: 1, backgroundColor: '#00000055' },
  stopSheet: { backgroundColor: paper.canvas, borderTopWidth: 1, borderColor: paper.line, padding: 16, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 3, backgroundColor: paper.line, marginBottom: 14 },
  sheetTitle: { fontSize: 20.5, fontWeight: '900', color: paper.ink },
  sheetBody: { fontSize: 14, color: paper.text, marginTop: 5, lineHeight: 20.5 },
  sheetLabel: { fontSize: 14.5, fontWeight: '800', color: paper.ink, marginTop: 16, marginBottom: 8 },
  reasonRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: paper.canvas,
    borderWidth: 1, borderColor: paper.line, padding: 13, marginBottom: 8,
  },
  reasonRowSel: { backgroundColor: paper.wash },
  reasonTxt: { fontSize: 15.5, color: paper.text, fontWeight: '500' },
  radio: { width: 18, height: 18, borderWidth: 2, borderColor: paper.faint, alignItems: 'center', justifyContent: 'center' },
  radioDot: { width: 8, height: 8, backgroundColor: paper.ink },
  feeNote: { backgroundColor: paper.wash, padding: 12, marginTop: 10 },
  feeTxt: { fontSize: 15, color: paper.text, lineHeight: 19.5 },
  // 승인된 유일한 라우드 필 — pressed 면색은 매트릭스가 '채워진 destructive'에 대해 정의하지 않았다.
  // 새 헥스를 지어내지 않고 default/disabled 둘만 명시한다 (disabled = 명시 fill, 불투명도 금지).
  stopConfirm: { backgroundColor: paper.critical, alignItems: 'center', paddingVertical: 15, marginTop: 14 },
  stopConfirmOff: { backgroundColor: paper.disabledFill },
  stopConfirmTxt: { fontSize: 16.5, fontWeight: '900', color: '#ffffff' },
  keepWatchTxt: { fontSize: 15, fontWeight: '700', color: paper.dim },
});
