import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { Alert, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { HeatTrace } from '../../src/components/runcard';
import { Avatar, Row } from '../../src/components/ui';
import { fetchBookingStatus, fetchMeetupInfo, MeetupInfo, subscribeBooking } from '../../src/lib/api';
import { getNaverMap, LivePos, smoothTrace, subscribePos } from '../../src/lib/geo';
import { dog, draft, lastRunTrace, runners } from '../../src/store';
import { colors } from '../../src/theme';

// 라이브 런 (보호자) — 풀스크린 지도 + 플로팅 아일랜드 카드 (모던 패스, 2026-07-23).
// 실모드: 위치 브로드캐스트 구독 + 실지도, 완료 → 리포트, 종료 → 채팅 조율.
// 데모: 연출 지도 유지 (예약 없을 때만).

const FOREST = '#0F1D13';
const TOTAL_SEC = 2052;

const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

const STOP_REASONS = ['아이 컨디션이 걱정돼요', '급한 일정이 생겼어요', '기타 사유'];

export default function Live() {
  const live = !!draft.bookingId;
  const [t, setT] = useState(0);
  const [stopSheet, setStopSheet] = useState(false);
  const [stopReason, setStopReason] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const runner = runners.find((r) => r.id === draft.runnerId) ?? runners[0];

  // ---------- 실모드 데이터 ----------
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const [pos, setPos] = useState<LivePos | null>(null);
  const path = useRef<{ latitude: number; longitude: number }[]>([]);
  const [pathLen, setPathLen] = useState(0);
  const startAt = useRef<number | null>(null);
  const [liveSec, setLiveSec] = useState(0);
  const maps = live ? getNaverMap() : null; // 네이버 지도 (2026-07-29) — 미탑재 빌드는 대기 화면 폴백

  useEffect(() => {
    if (!live) return;
    const bid = draft.bookingId!;
    fetchMeetupInfo(bid).then(setInfo).catch(() => {});
    const unsubPos = subscribePos(bid, (p) => {
      if (!startAt.current) startAt.current = Date.now();
      path.current.push({ latitude: p.lat, longitude: p.lng });
      setPathLen(path.current.length);
      setPos(p);
    });
    const done = async () => {
      try {
        const st = await fetchBookingStatus(bid);
        if (st === 'completed') router.replace({ pathname: '/owner/report', params: { bid } });
      } catch { /* 폴백이 처리 */ }
    };
    const unsubBk = subscribeBooking(bid, done);
    const poll = setInterval(done, 10000);
    const tick = setInterval(() => { if (startAt.current) setLiveSec(Math.floor((Date.now() - startAt.current) / 1000)); }, 1000);
    return () => { unsubPos(); unsubBk(); clearInterval(poll); clearInterval(tick); };
  }, [live]);

  const confirmStop = () => {
    setStopSheet(false);
    if (live) {
      Alert.alert('러너에게 알렸어요', '안전한 지점에서 정지 후 조율해요 — 채팅으로 이어드릴게요');
      router.push({ pathname: '/chat', params: { bid: draft.bookingId! } });
      return;
    }
    Alert.alert('종료 요청 전송됨', `${runner.name} 러너에게 강제 알림이 전송됐어요 (목업)`);
    router.replace('/owner/pay');
  };

  // 데모 전용 타이머
  useEffect(() => {
    if (live) return;
    timer.current = setInterval(() => setT((prev) => (prev >= 1 ? 1 : Math.min(prev + 0.004, 1))), 80);
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [live]);

  useEffect(() => {
    if (live) return;
    if (t >= 1) {
      const id = setTimeout(() => router.replace('/owner/pay'), 1200);
      return () => clearTimeout(id);
    }
  }, [t, live]);

  const dogName = live ? (info?.dogName ?? '반려견') : dog.name;
  const runnerName = live ? (info?.runnerName ?? '러너') : runner.name;
  const targetKm = live ? (info?.km ?? draft.km) : draft.km;
  const km = live ? (pos?.km ?? 0) : draft.km * t;
  const sec = live ? liveSec : TOTAL_SEC * t;
  const progressT = live ? Math.min(km / Math.max(targetKm, 0.1), 1) : t;
  const dotIdx = Math.min(Math.floor(t * (lastRunTrace.length - 1)), lastRunTrace.length - 1);
  const dot = lastRunTrace[dotIdx];

  return (
    <View style={{ flex: 1, backgroundColor: '#e6ecdc' }}>
      <StatusBar style="dark" />

      {/* ---------- 풀스크린 지도 레이어 ---------- */}
      {live && maps && pos ? (
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
              color={colors.voltDeep}
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
      ) : live ? (
        <View style={[StyleSheet.absoluteFill, { alignItems: 'center', justifyContent: 'center' }]}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>러너 위치 수신 대기 중...</Text>
          <Text style={{ fontSize: 15, color: '#75806f', marginTop: 6, textAlign: 'center', lineHeight: 19.5 }}>
            러너가 달리기 시작하면 실시간 경로가 그려져요{'\n'}{!maps ? '(실지도는 새 개발 빌드에서)' : ''}
          </Text>
        </View>
      ) : (
        <View style={StyleSheet.absoluteFill}>
          {/* 데모 연출 지도 */}
          <View style={s.mapRoadH} />
          <View style={s.mapRoadV} />
          <View style={s.mapWater} />
          <View style={{ position: 'absolute', left: 12, right: 12, top: 130, height: 360 }}>
            <HeatTrace points={lastRunTrace} width={340} height={360} />
            <View style={[s.liveDot, { left: dot.x * 340 - 11, top: dot.y * 360 - 11 }]} />
          </View>
        </View>
      )}

      {/* ---------- 상단 오버레이 ---------- */}
      <Row style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <View style={s.livePill}>
          <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt }}>
            ● LIVE · {dogName}가 달리는 중
          </Text>
        </View>
        <Pressable onPress={() => router.push('/safety')} style={[s.circleBtn, { backgroundColor: '#e8492a' }]}>
          <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>SOS</Text>
        </Pressable>
      </Row>

      {/* ---------- 플로팅 아일랜드 카드 ---------- */}
      <View style={s.island}>
        {/* runner row */}
        <Row style={{ gap: 11, alignItems: 'center' }}>
          <Avatar url={null} char={runnerName[0]} bg="#5a7a3c" size={44} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{runnerName} 러너</Text>
            <Text style={{ fontSize: 15, color: '#75806f', marginTop: 2 }}>
              {live ? (info?.routeName ?? '코스') : '서울숲 코스'} · {targetKm}km
            </Text>
          </View>
          <View style={[s.signalPill, { backgroundColor: (live ? !!pos : true) ? '#eaf7c8' : '#f0efe8' }]}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: (live ? !!pos : true) ? '#3d5a2b' : '#8a8877' }}>
              {live ? (pos ? 'ılı 위치 수신' : '수신 대기') : 'ılı 좋음'}
            </Text>
          </View>
        </Row>

        {/* stats */}
        <Row style={{ marginTop: 14, justifyContent: 'space-between' }}>
          <View>
            <Text style={{ fontSize: 34.5, fontWeight: '900', color: colors.tang }}>
              {km.toFixed(2)}<Text style={{ fontSize: 15, color: '#8a8877' }}> km</Text>
            </Text>
          </View>
          <View style={{ alignItems: 'center' }}>
            <Text style={{ fontSize: 23, fontWeight: '900', color: FOREST }}>{fmt(sec)}</Text>
            <Text style={{ fontSize: 14, color: '#8a8877', marginTop: 1 }}>시간</Text>
          </View>
          <View style={{ alignItems: 'flex-end' }}>
            <Text style={{ fontSize: 23, fontWeight: '900', color: FOREST }}>{paceStr(sec, km)}</Text>
            <Text style={{ fontSize: 14, color: '#8a8877', marginTop: 1 }}>페이스</Text>
          </View>
        </Row>
        {/* thin progress */}
        <View style={s.progressTrack}>
          <View style={[s.progressFill, { width: `${progressT * 100}%` }]} />
        </View>

        {/* actions — 채팅이 주 액션, 종료는 찾을 수 있되 작게 */}
        <Row style={{ gap: 10, marginTop: 14 }}>
          <Pressable
            onPress={() => router.push({ pathname: '/chat', params: live ? { bid: draft.bookingId! } : {} })}
            style={s.chatBtn}
          >
            <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>💬 러너와 채팅</Text>
          </Pressable>
          <Pressable onPress={() => { setStopReason(null); setStopSheet(true); }} style={s.stopCircle}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: '#d84a2f' }}>■</Text>
          </Pressable>
        </Row>
      </View>

      {/* ---------- stop confirmation sheet ---------- */}
      <Modal visible={stopSheet} transparent animationType="slide" onRequestClose={() => setStopSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setStopSheet(false)} />
        <View style={s.stopSheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 20.5, fontWeight: '900', color: FOREST }}>정말 러닝을 종료할까요?</Text>
          <Text style={{ fontSize: 14, color: '#49524a', marginTop: 5, lineHeight: 20.5 }}>
            러너에게 알림이 가고, 안전하게 정지한 뒤{'\n'}{dogName}를 데리고 픽업 장소로 복귀해요.
          </Text>

          <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST, marginTop: 16, marginBottom: 8 }}>종료 사유</Text>
          {STOP_REASONS.map((r) => (
            <Pressable key={r} onPress={() => setStopReason(r)} style={[s.reasonRow, stopReason === r && { borderColor: '#a9c47e', backgroundColor: '#f4f8ea' }]}>
              <View style={[s.radio, stopReason === r && { borderColor: '#5a7a3c' }]}>
                {stopReason === r && <View style={s.radioDot} />}
              </View>
              <Text style={{ fontSize: 15.5, color: '#3d453d', fontWeight: stopReason === r ? '800' : '500' }}>{r}</Text>
            </Pressable>
          ))}

          <View style={s.feeNote}>
            <Text style={{ fontSize: 15, color: '#75806f', lineHeight: 19.5 }}>
              지금까지 달린 {km.toFixed(1)}km 기준으로 정산돼요.{'\n'}
              최소 기본요금 9,900원은 결제되며, 러너에게는 잔여 거리 보장이 적용돼요.
            </Text>
          </View>

          <Pressable
            style={[s.stopConfirm, !stopReason && { opacity: 0.4 }]}
            disabled={!stopReason}
            onPress={confirmStop}
          >
            <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#fff' }}>종료 요청 보내기</Text>
          </Pressable>
          <Pressable style={{ alignItems: 'center', paddingVertical: 13 }} onPress={() => setStopSheet(false)}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: '#49524a' }}>계속 지켜볼게요</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  mapRoadH: { position: 'absolute', top: 200, left: 0, right: 0, height: 14, backgroundColor: '#ffffffaa', transform: [{ rotate: '-8deg' }] },
  mapRoadV: { position: 'absolute', top: 0, bottom: 0, right: 90, width: 12, backgroundColor: '#ffffff88', transform: [{ rotate: '12deg' }] },
  mapWater: { position: 'absolute', bottom: 240, right: 20, width: 120, height: 60, borderRadius: 40, backgroundColor: '#cfe0ea', transform: [{ rotate: '-20deg' }] },
  liveDot: {
    position: 'absolute', width: 22, height: 22, borderRadius: 11,
    backgroundColor: colors.tang, borderWidth: 4, borderColor: '#fff',
    shadowColor: colors.tang, shadowOpacity: 0.8, shadowRadius: 8, shadowOffset: { width: 0, height: 0 },
  },
  topBar: { position: 'absolute', top: 56, left: 10, right: 10, justifyContent: 'space-between' },
  circleBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  livePill: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 16, alignSelf: 'center' },
  // 플로팅 아일랜드 — 지도 위에 떠 있는 정보 카드 (레퍼런스: 배달 트래킹)
  island: {
    position: 'absolute', left: 10, right: 10, bottom: 26,
    backgroundColor: '#fff', borderRadius: 22, padding: 18,
    shadowColor: '#000', shadowOpacity: 0.16, shadowRadius: 11, shadowOffset: { width: 0, height: 4 },
    elevation: 10,
  },
  signalPill: { borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  progressTrack: { height: 5, borderRadius: 99, backgroundColor: '#f0eee3', marginTop: 12, overflow: 'hidden' },
  progressFill: { height: 5, borderRadius: 99, backgroundColor: colors.volt },
  chatBtn: { flex: 1, backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 14 },
  stopCircle: {
    width: 50, height: 50, borderRadius: 25, backgroundColor: '#fff',
    borderWidth: 1.5, borderColor: '#f2d4ca', alignItems: 'center', justifyContent: 'center',
  },
  sheetBackdrop: { flex: 1, backgroundColor: '#00000055' },
  stopSheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 16, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#DCD6C4', marginBottom: 14 },
  reasonRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#fff',
    borderRadius: 14, borderWidth: 1.3, borderColor: '#DCD6C4', padding: 13, marginBottom: 8,
  },
  radio: { width: 18, height: 18, borderRadius: 10, borderWidth: 2, borderColor: '#dcd9cc', alignItems: 'center', justifyContent: 'center' },
  radioDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: '#5a7a3c' },
  feeNote: { backgroundColor: '#f4f2ea', borderRadius: 12, padding: 12, marginTop: 10 },
  stopConfirm: { backgroundColor: '#e8492a', borderRadius: 16, alignItems: 'center', paddingVertical: 15, marginTop: 14 },
});
