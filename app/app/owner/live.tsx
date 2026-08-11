import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { ensureThread, fetchBookingStatus, fetchCurrentOwnerBookingId, fetchMeetupInfo, MeetupInfo, sendChatMessage, subscribeBooking } from '../../src/lib/api';
import { useNumFont } from '../../src/lib/fonts';
import { getNaverMap, LivePos, smoothTrace, subscribePos } from '../../src/lib/geo';
import { endOwnerActivity, OwnerLAProps, startOwnerActivity, updateOwnerActivity } from '../../src/lib/ownerActivity';
import { draft } from '../../src/store';
import { paper } from '../../src/theme';

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

const STOP_REASONS = ['아이 컨디션이 걱정돼요', '급한 일정이 생겼어요', '기타 사유'];

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
  const maps = getNaverMap(); // 네이버 지도 (2026-07-29) — 미탑재 빌드는 대기 화면 폴백

  // id 복원 — 리로드로 draft가 비어도 서버가 진실을 안다. 실패(네트워크)는 '진행 중 없음'과 다르다:
  // 조용히 back 하지 않고 재시도 문을 연다.
  const resolveBooking = useCallback(() => {
    setResolve('resolving');
    fetchCurrentOwnerBookingId()
      .then((id) => {
        if (id) { draft.bookingId = id; setBookingId(id); setResolve('ready'); return; }
        setResolve('empty');
        Alert.alert('진행 중인 러닝이 없어요', '러닝이 시작되면 이 화면이 열려요');
        router.back();
      })
      .catch((e) => { console.warn('[live] resolve:', e?.message ?? e); setResolve('error'); });
  }, []);

  useEffect(() => {
    if (bookingId) return;
    resolveBooking();
  }, [bookingId, resolveBooking]);

  useEffect(() => {
    if (!bookingId) return;
    const bid = bookingId;
    fetchMeetupInfo(bid).then(setInfo).catch(() => {});
    const unsubPos = subscribePos(bid, (p) => {
      if (!startAt.current) startAt.current = Date.now();
      lastFixAt.current = Date.now();
      setStaleSec(0);
      path.current.push({ latitude: p.lat, longitude: p.lng });
      setPathLen(path.current.length);
      setPos(p);
    });
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
        }
      } catch { /* 폴백이 처리 */ }
    };
    const unsubBk = subscribeBooking(bid, done);
    const poll = setInterval(done, 10000);
    const tick = setInterval(() => {
      if (startAt.current) setLiveSec(Math.floor((Date.now() - startAt.current) / 1000));
      if (lastFixAt.current) setStaleSec(Math.floor((Date.now() - lastFixAt.current) / 1000));
    }, 1000);
    return () => { unsubPos(); unsubBk(); clearInterval(poll); clearInterval(tick); };
  }, [bookingId]);

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
      setStopSheet(false);
      // No overclaim: what actually happened is a chat send, not a push — land the owner in the
      // thread where the sent request is visible (proof, not assertion).
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
  // 90초 넘게 갱신이 없으면 지도의 점은 더 이상 '지금'이 아니다 — 그렇다고 말한다.
  const stale = hasFix && staleSec >= 90;
  const staleMin = Math.max(1, Math.floor(staleSec / 60));
  const km = pos?.km ?? 0;
  const sec = liveSec;
  const progressT = hasFix && targetKm != null ? Math.min(km / Math.max(targetKm, 0.1), 1) : 0;

  // ---------- [0063] owner Live Activity — this screen's lock-screen mirror ----------
  // While the app is awake this screen refreshes the LA locally from the same broadcast that draws
  // the map (5s throttle — runner LA convention). The moment the app sleeps, the 0063 APNs
  // pipeline takes over from runs.trace — same truth, different transport. Same honesty rules as
  // this screen: no fix → no number, stale ≥90s → the number greys out and says how long.
  const laPropsRef = useRef<OwnerLAProps | null>(null);
  const laLast = useRef(0);
  laPropsRef.current = {
    phase: !hasFix ? 'running' : stale ? 'stale' : 'running',
    dogName,
    runnerName,
    km: hasFix ? km.toFixed(2) : '',
    targetKm: targetKm != null ? String(targetKm) : '',
    pace: hasFix && !stale ? paceStr(sec, km) : '',
    elapsed: hasFix && !stale ? fmt(sec) : '',
    statusLine: !hasFix ? '' : stale ? `${staleMin}분째 위치가 갱신되지 않았어요` : '방금 업데이트',
  };
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
          <Pressable onPress={() => router.back()} style={s.squareBtn}><Text style={s.backGlyph}>‹</Text></Pressable>
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
      {maps && pos ? (
        <maps.NaverMapView
          style={StyleSheet.absoluteFill}
          camera={{ latitude: pos.lat, longitude: pos.lng, zoom: 15 }}
          isShowLocationButton={false}
          isShowCompass={false}
          isShowScaleBar={false}
          isShowZoomControls={false}
        >
          {/* 스무딩은 렌더 전용 — 픽스 게이트는 소스(러너 run.tsx)에서 이미 적용됨 */}
          {pathLen > 1 && (
            <maps.NaverMapPathOverlay
              coords={smoothTrace(path.current)}
              color={paper.line}
              width={6}
              outlineWidth={2}
              outlineColor="#ffffff"
            />
          )}
          <maps.NaverMapMarkerOverlay
            latitude={pos.lat}
            longitude={pos.lng}
            anchor={{ x: 0.5, y: 1 }}
            caption={{ text: `${dogName} · ${runnerName} 러너` }}
          />
        </maps.NaverMapView>
      ) : (
        <View style={[StyleSheet.absoluteFill, { alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 }]}>
          <Text style={s.waitTitle}>러너 위치 수신 대기 중...</Text>
          <Text style={s.waitBody}>
            러너가 달리기 시작하면 실시간 경로가 그려져요{'\n'}{!maps ? '(실지도는 새 개발 빌드에서)' : ''}
          </Text>
        </View>
      )}

      {/* ---------- 상단 오버레이 ---------- */}
      <Row style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.squareBtn}><Text style={s.backGlyph}>‹</Text></Pressable>
        {/* LIVE는 근거가 있을 때만 — 위치 픽스 전에는 '달리는 중'이라고 말하지 않는다.
            (진행 중 예약에는 confirmed·인계 대기도 포함된다 — 아직 러닝이 아니다) */}
        <View style={s.livePill}>
          <Text style={s.livePillTxt}>
            <Text style={{ color: hasFix && !stale ? paper.line : paper.faint }}>●</Text>
            {!hasFix ? ` ${dogName} · 위치 수신 대기` : stale ? ` ${dogName} · 위치 갱신 없음` : ` LIVE · ${dogName}가 달리는 중`}
          </Text>
        </View>
        {/* SOS = 긴급 어포던스 — 라우드 페일 토큰이 정확히 이 자리를 위한 색이다 */}
        <Pressable onPress={() => router.push('/safety')} style={s.sosBtn}>
          <Text style={s.sosTxt}>SOS</Text>
        </Pressable>
      </Row>

      {/* ---------- 하단 아일랜드 카드 (풀블리드 · 샤프 · 1px 코랄 프레임) ---------- */}
      <View style={s.island}>
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

        {/* 신선도 — 멈춘 점을 라이브라고 말하지 않는다 */}
        {stale && (
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
            <Text style={[s.statNum, nf]}>{hasFix ? fmt(sec) : '—'}</Text>
            <Text style={s.statLabel}>시간</Text>
          </View>
          <View style={{ alignItems: 'flex-end' }}>
            <Text style={[s.statNum, nf]}>{hasFix ? paceStr(sec, km) : '—'}</Text>
            <Text style={s.statLabel}>페이스</Text>
          </View>
        </Row>
        {/* thin progress — 각진 코랄 필 (목표 거리를 알 때만 찬다) */}
        <View style={s.progressTrack}>
          <View style={[s.progressFill, { width: `${progressT * 100}%` }]} />
        </View>

        {/* actions — 채팅이 이 화면의 유일한 잉크 CTA, 종료는 destructive */}
        <Row style={{ gap: 10, marginTop: 14 }}>
          <Pressable
            onPress={() => router.push({ pathname: '/chat', params: { bid: bookingId! } })}
            style={({ pressed }) => [s.chatBtn, pressed && s.chatBtnPressed]}
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
      </View>

      {/* ---------- stop confirmation sheet ---------- */}
      <Modal visible={stopSheet} transparent animationType="slide" onRequestClose={() => setStopSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setStopSheet(false)} />
        <View style={s.stopSheet}>
          <View style={s.sheetHandle} />
          <Text style={s.sheetTitle}>정말 러닝을 종료할까요?</Text>
          {/* Honest copy — only what actually happens: chat send (not a push) → runner sees it → stop & return */}
          <Text style={s.sheetBody}>
            종료 요청과 사유가 채팅으로 러너에게 전송돼요.{'\n'}러너가 확인하면 안전하게 정지한 뒤 {dogName}를 데리고 픽업 장소로 복귀해요.
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

          <View style={s.feeNote}>
            <Text style={s.feeTxt}>
              {hasFix ? `러너가 종료하면 지금까지 달린 ${km.toFixed(1)}km 기준으로 정산돼요.` : '러너가 종료하면 지금까지 달린 거리 기준으로 정산돼요.'}{'\n'}
              최소 기본요금 9,900원은 결제되며, 러너에게는 잔여 거리 보장이 적용돼요.
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
  // 라이브 캠 슬롯 — null이면 렌더되지 않는다 (자리만 예약)
  streamSlot: { marginTop: 12, borderWidth: 1, borderColor: paper.line, paddingVertical: 8, paddingHorizontal: 12 },
  streamTxt: { fontSize: 14, fontWeight: '700', color: paper.text },
  kmNum: { fontSize: 34.5, lineHeight: 42, fontWeight: '900', color: paper.ink },
  kmUnit: { fontSize: 15, fontWeight: '700', color: paper.dim },
  statNum: { fontSize: 23, lineHeight: 28, fontWeight: '900', color: paper.ink },
  statLabel: { fontSize: 14, color: paper.dim, marginTop: 1 },
  progressTrack: { height: 5, backgroundColor: paper.disabledFill, marginTop: 12, overflow: 'hidden' },
  progressFill: { height: 5, backgroundColor: paper.line },
  // 버튼 매트릭스 — primary(잉크 면) 하나 + destructive(캔버스 면 + 크리티컬 잉크·보더)
  // [액션] 채팅은 이동이지 커밋이 아니다 -> 세컨더리. 이 화면은 코랄 필이 0개인 게 맞다:
  // 예산은 상한이지 할당량이 아니고, 강조는 livePill(잉크=상태)이 지고 있다.
  chatBtn: { flex: 1, backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line, alignItems: 'center', paddingVertical: 14 },
  chatBtnPressed: { backgroundColor: '#333333' }, // F2.1 매트릭스가 지정한 primary pressed 면색 (토큰 미보유)
  chatBtnTxt: { fontSize: 16.5, fontWeight: '900', color: '#ffffff' },
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
