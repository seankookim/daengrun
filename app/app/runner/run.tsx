import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { addRunEvent, fetchCurrentRunnerJobId, fetchMeetupInfo, MeetupInfo, notifyKmMilestone, RunEventKind, saveRunTrace, settleRun, startRunServer, uploadRunPhoto } from '../../src/lib/api';
import { distM, GeoPoint, publishPos, startTracking, stopPublishing } from '../../src/lib/geo';
import { haptic } from '../../src/lib/haptics';
import { endRunActivity, RunLAProps, startRunActivity, updateRunActivity } from '../../src/lib/runActivity';
import { EndReason, payoutFor, runnerJob, runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

const REASON_MAP = { dog: 'dog_condition', owner: 'owner_request', runner: 'runner_personal' } as const;

// Runner-side live run: route progress map (placeholder), camera status,
// pinned customer chat. Real version: expo-location + react-native-maps + camera stream.

const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

export default function ActiveRun() {
  const req = runRequests[0]; // 시각 폴백 전용 — 실값은 info가 우선
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const dogName = info?.dogName ?? req.dogName;
  // 🔴 목표 거리 실화 — mock 5km가 진행/자동완주 임계로 쓰이던 버그 수정 (fake-inventory)
  const targetKm = info?.km ?? req.km;
  const [running, setRunning] = useState(false);
  const [sec, setSec] = useState(0);
  const [endSheet, setEndSheet] = useState(false);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const settled = useRef(false); // 중복 정산 방지 (자동완주 + 수동종료 레이스)
  const [evCounts, setEvCounts] = useState<Record<string, number>>({});

  // 러닝 이벤트 원탭 — 기록 + 보호자 즉시 알림 (응가 도장 = 케어 증거이자 건강 데이터)
  const fireEvent = (kind: Exclude<RunEventKind, 'photo'>) => {
    if (!runnerJob.bookingId) { Alert.alert('실예약에서만 기록돼요'); return; }
    haptic('light');
    setEvCounts((c) => ({ ...c, [kind]: (c[kind] ?? 0) + 1 }));
    addRunEvent(runnerJob.bookingId, kind).catch((e) => console.warn('[run] event:', e?.message ?? e));
  };

  const firePhoto = async () => {
    if (!runnerJob.bookingId) { Alert.alert('실예약에서만 기록돼요'); return; }
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) return;
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      await uploadRunPhoto(runnerJob.bookingId, res.assets[0].base64);
      await addRunEvent(runnerJob.bookingId, 'photo');
      setEvCounts((c) => ({ ...c, photo: (c.photo ?? 0) + 1 }));
    } catch (e) {
      Alert.alert('전송 실패', (e as Error).message);
    }
  };

  // id 복원 — 리로드로 유실돼도 서버의 active 예약으로 정산이 연결되게
  useEffect(() => {
    (async () => {
      if (!runnerJob.bookingId) {
        try {
          const id = await fetchCurrentRunnerJobId();
          if (id) runnerJob.bookingId = id;
        } catch (e) { console.warn('[run] resolve:', (e as Error)?.message); }
      }
      if (runnerJob.bookingId) {
        fetchMeetupInfo(runnerJob.bookingId).then(setInfo).catch((e) => console.warn('[run] info:', e?.message ?? e));
      }
    })();
  }, []);

  // ---------- 실GPS 거리 (핵심 실화) ----------
  // gps=true: 실좌표 누적 거리 · 실시간 초 · 위치 브로드캐스트 · km 마일스톤 알림
  // gps=false(모듈 없음/권한 거부/구 빌드): 가속 데모 타이머 폴백 — 화면에 '데모 거리' 표기
  const [gps, setGps] = useState(false);
  const [gpsKm, setGpsKm] = useState(0);
  const trace = useRef<GeoPoint[]>([]);
  const lastMilestone = useRef(0);
  const stopTrack = useRef<null | (() => void)>(null);

  useEffect(() => {
    if (!running) {
      if (stopTrack.current) { stopTrack.current(); stopTrack.current = null; }
      return;
    }
    let alive = true;
    startTracking((p) => {
      if (!alive) return;
      const prev = trace.current[trace.current.length - 1];
      trace.current.push(p);
      if (prev) {
        const d = distM(prev, p);
        if (d > 2 && d < 120) { // GPS 노이즈/텔레포트 필터
          setGpsKm((cur) => {
            const next = cur + d / 1000;
            // km 마일스톤 — 실거리에서만 실알림
            const crossed = Math.floor(next);
            if (crossed > lastMilestone.current && runnerJob.bookingId) {
              lastMilestone.current = crossed;
              notifyKmMilestone(runnerJob.bookingId, crossed).catch(() => {});
              haptic('success');
            }
            return next;
          });
        }
      }
      if (runnerJob.bookingId) {
        publishPos(runnerJob.bookingId, { lat: p.lat, lng: p.lng, km: gpsKmRef.current, paceSec: null });
      }
    }).then((stop) => {
      if (!alive) { stop?.(); return; }
      if (stop) { stopTrack.current = stop; setGps(true); }
    });
    return () => { alive = false; if (stopTrack.current) { stopTrack.current(); stopTrack.current = null; } };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  // publishPos 클로저용 최신 km
  const gpsKmRef = useRef(0);
  useEffect(() => { gpsKmRef.current = gpsKm; }, [gpsKm]);

  const demoKm = Math.min(sec / 409, targetKm + 0.02); // 데모 폴백: ~6'49" 가속
  const km = gps ? gpsKm : demoKm;
  const remaining = Math.max(targetKm - km, 0);
  const progress = Math.min(km / targetKm, 1);

  // ---------- 라이브 액티비티 (다이내믹 아일랜드 + 잠금화면) ----------
  const laProps = (): RunLAProps => ({
    dogName,
    km: km.toFixed(2),
    targetKm: String(targetKm),
    pace: paceStr(sec, km),
    elapsed: fmt(sec),
    eventLine: [
      evCounts.poop ? `💩${evCounts.poop}` : '',
      evCounts.snack ? `🍖${evCounts.snack}` : '',
      evCounts.water ? `💧${evCounts.water}` : '',
      evCounts.photo ? `📷${evCounts.photo}` : '',
    ].filter(Boolean).join(' · '),
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

  useEffect(() => {
    if (!running || !laStarted.current) return;
    const now = Date.now();
    if (now - laLastUpdate.current < 5000) return; // 5초 스로틀
    laLastUpdate.current = now;
    updateRunActivity(laProps());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sec]);

  useEffect(() => {
    if (running) {
      timer.current = setInterval(() => setSec((s) => s + (gps ? 1 : 8)), gps ? 1000 : 100); // GPS면 실시간
    }
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [running, gps]);

  // per-reason payout (docs/product-notes: all pay actual km — never incentivize pushing a hurt dog)
  const payoutByReason = (reason: EndReason): number => {
    const actual = payoutFor(km);
    if (reason === 'owner') return actual + Math.round((payoutFor(targetKm) - actual) * 0.5); // + 잔여 50% 보장
    return actual; // dog / runner: actual km
  };

  // 실예약이면 서버 정산 (사유별 금액·드랍은 settle-run이 계산), 아니면 로컬 계산
  const settle = async (reason: EndReason, completed: boolean) => {
    if (settled.current) return;
    settled.current = true;
    const bid = runnerJob.bookingId;
    // 추적 종료 + 브로드캐스트 + 라이브 액티비티 정리
    if (stopTrack.current) { stopTrack.current(); stopTrack.current = null; }
    stopPublishing();
    endRunActivity(laProps());
    const localPayout = completed ? payoutFor(km) : payoutByReason(reason);
    Object.assign(runResult, { km, sec, payout: localPayout, completed, reason, bookingId: bid });

    if (bid) {
      try {
        const res = await settleRun({
          booking_id: bid,
          end_reason: completed ? 'completed' : REASON_MAP[reason as keyof typeof REASON_MAP],
          actual_km: Number(km.toFixed(2)),
          duration_sec: sec,
          condition_note: reason === 'dog' ? '러너 판단: 컨디션 저하 관찰' : undefined,
        });
        runResult.payout = res.net; // 서버가 계산한 실지급액
        runnerJob.bookingId = null;
        // 실트레이스 저장 — 리포트 지도·기록의 원천
        if (trace.current.length > 1) saveRunTrace(bid, trace.current).catch((e) => console.warn('[run] trace:', e?.message ?? e));
        if (res.drop) Alert.alert('드랍 도착!', res.drop === 'pick' ? '픽 드랍 — 리워드 센터에서 선택하세요' : '보급 상자가 도착했어요');
      } catch (e) {
        Alert.alert('정산 지연', `서버 정산 실패 — 로컬 추정치 표시\n${(e as Error).message}`);
      }
    }
    router.replace('/runner/done');
  };

  const endWith = (reason: EndReason) => {
    setEndSheet(false);
    if (reason === 'dog') {
      Alert.alert('컨디션 종료', '보호자에게 알림 전송됨 · 상태 사진과 메모를 남겨주세요\n근처 동물병원: 성수동물병원 650m');
    }
    settle(reason, false);
  };

  const finish = (_completed: boolean) => {
    settle(null, true);
  };

  // 자동 완주도 반드시 서버 정산을 거친다 — 예전엔 여기서 정산 없이 done으로 직행해
  // 예약이 영원히 active로 남았음 (보호자 위젯 ● LIVE 좀비의 원인, 2026-07-23)
  useEffect(() => {
    if (km >= targetKm) {
      setRunning(false);
      settle(null, true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [km >= targetKm]);

  return (
    <View style={s.root}>
      {/* 코스 맵 placeholder */}
      <View style={s.mapArea}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 16 }}>
          <View style={s.statusBadge}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: colors.volt }}>
              {running ? `● ${dogName}와 러닝 중${gps ? ' · GPS' : ' · 데모 거리'}` : `${dogName}와 러닝 준비`}
            </Text>
          </View>
          <View style={s.camStatus}>
            <View style={[s.recDot, !running && { backgroundColor: '#8a8877' }]} />
            <Text style={s.camText}>{running ? 'REC · 보호자 시청 중' : '카메라 대기'} · 배터리 82%</Text>
          </View>
        </Row>

        <View style={s.trackWrap}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 8 }}>
            <Text style={{ fontSize: 12, color: colors.dim }}>{info?.routeName ?? req.place} 코스 · {targetKm}km</Text>
            <Text style={{ fontSize: 12, fontWeight: '800', color: colors.ink }}>
              남은 거리 {remaining.toFixed(1)}km
            </Text>
          </Row>
          <View style={s.track}>
            <View style={[s.trackFill, { width: `${progress * 100}%` }]} />
            <View style={[s.trackDot, { left: `${Math.max(progress * 100 - 2, 0)}%` }]} />
          </View>
        </View>
      </View>

      {/* 스탯 + 컨트롤 */}
      <View style={s.panel}>
        {/* 고정된 고객 채팅 */}
        <Pressable
          style={s.chatPin}
          onPress={() => router.push('/chat')}
        >
          <Monogram char={req.dogChar} bg={req.dogColor} size={36} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: colors.cream }}>{dogName} 보호자님</Text>
            <Text style={{ fontSize: 11, color: '#8fa093' }} numberOfLines={1}>
              {info?.dogMemo ?? '채팅으로 이동'}
            </Text>
          </View>
          <Text style={{ fontSize: 12, color: colors.volt }}>채팅 ›</Text>
        </Pressable>

        <Row style={{ justifyContent: 'space-around', marginVertical: 22 }}>
          <MiniStat value={km.toFixed(2)} label="km" big />
          <MiniStat value={fmt(sec)} label="시간" />
          <MiniStat value={paceStr(sec, km)} label="페이스" />
        </Row>

        <Row style={{ justifyContent: 'center', marginBottom: 14 }}>
          <Text style={{ fontSize: 12, color: '#8fa093' }}>
            현재 예상 수익 <Text style={{ color: colors.volt, fontWeight: '800' }}>{payoutFor(km).toLocaleString()}원</Text> · 완주 시 {payoutFor(targetKm + 0.02).toLocaleString()}원
          </Text>
        </Row>

        {/* 러닝 이벤트 스트립 — 원탭이 보호자 알림으로 (응가 도장 포함) */}
        {running && (
          <View style={{ flexDirection: 'row', gap: 8, marginBottom: 14 }}>
            {([['poop', '💩', '응가'], ['snack', '🍖', '간식'], ['water', '💧', '물']] as const).map(([k, g, label]) => (
              <Pressable key={k} onPress={() => fireEvent(k)} style={s.eventBtn}>
                <Text style={{ fontSize: 16 }}>{g}</Text>
                <Text style={{ fontSize: 10, fontWeight: '800', color: colors.cream, marginTop: 2 }}>
                  {label}{evCounts[k] ? ` ${evCounts[k]}` : ''}
                </Text>
              </Pressable>
            ))}
            <Pressable onPress={firePhoto} style={s.eventBtn}>
              <Text style={{ fontSize: 16 }}>📷</Text>
              <Text style={{ fontSize: 10, fontWeight: '800', color: colors.cream, marginTop: 2 }}>
                사진{evCounts.photo ? ` ${evCounts.photo}` : ''}
              </Text>
            </Pressable>
          </View>
        )}

        <View style={{ flexDirection: 'row', gap: 10, alignItems: 'center' }}>
          {running && (
            <Pressable style={s.moreBtn} onPress={() => setEndSheet(true)}>
              <Text style={{ fontSize: 14, color: '#8fa093', fontWeight: '900' }}>❙❙</Text>
            </Pressable>
          )}
          <Pressable
            style={[s.btn, { backgroundColor: colors.volt }]}
            onPress={() => {
              if (running) { setEndSheet(true); return; }
              // 캘린더에서 picked_up 상태로 재진입한 경우에도 start_run이 호출되도록
              if (runnerJob.bookingId) startRunServer(runnerJob.bookingId).catch(() => { /* 이미 active면 무시 */ });
              setRunning(true);
            }}
          >
            <Text style={{ fontSize: 16, fontWeight: '800', color: colors.ink }}>
              {running ? '러닝 종료' : '러닝 시작'}
            </Text>
          </Pressable>
        </View>
      </View>

      {/* ---------- end-run options sheet ---------- */}
      <Modal visible={endSheet} transparent animationType="slide" onRequestClose={() => setEndSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setEndSheet(false)} />
        <View style={s.sheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 17, fontWeight: '900', color: colors.cream }}>어떤 이유로 종료하나요?</Text>
          <Text style={{ fontSize: 11.5, color: '#8fa093', marginTop: 4 }}>
            지금까지 {km.toFixed(2)}km · 이유에 따라 정산이 달라져요
          </Text>

          <EndOption
            title="강아지 컨디션"
            desc="지친 기색·이상 징후 등. 사진과 메모를 남겨요"
            pay={`${payoutByReason('dog').toLocaleString()}원 · 완주율 무영향`}
            accent="#B9F23A"
            onPress={() => endWith('dog')}
          />
          <EndOption
            title="보호자 요청"
            desc="보호자가 조기 종료를 요청했어요"
            pay={`${payoutByReason('owner').toLocaleString()}원 · 잔여 거리 50% 보장 포함`}
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

          <Pressable style={s.sheetCancel} onPress={() => setEndSheet(false)}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: '#8fa093' }}>계속 달릴게요</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

function EndOption({ title, desc, pay, accent, onPress }: { title: string; desc: string; pay: string; accent: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={s.endOption}>
      <View style={[s.endRail, { backgroundColor: accent }]} />
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 14.5, fontWeight: '900', color: colors.cream }}>{title}</Text>
        <Text style={{ fontSize: 11, color: '#8fa093', marginTop: 2 }}>{desc}</Text>
        <Text style={{ fontSize: 11.5, fontWeight: '800', color: accent, marginTop: 5 }}>{pay}</Text>
      </View>
      <Text style={{ fontSize: 15, color: '#8fa093' }}>›</Text>
    </Pressable>
  );
}

function MiniStat({ value, label, big }: { value: string; label: string; big?: boolean }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: big ? 44 : 28, fontWeight: '900', color: big ? colors.volt : colors.cream }}>
        {value}
      </Text>
      <Text style={{ fontSize: 11, color: '#8fa093', marginTop: 2 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#e7e9dc' },
  mapArea: { flex: 1, paddingTop: 56 },
  statusBadge: { backgroundColor: colors.ink, borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14 },
  camStatus: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#fff', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12 },
  recDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#ff3b30' },
  camText: { fontSize: 10, fontWeight: '700', color: colors.ink },
  trackWrap: { position: 'absolute', left: 20, right: 20, bottom: 24 },
  track: { height: 10, borderRadius: 99, backgroundColor: '#d5d8c6' },
  trackFill: { height: 10, borderRadius: 99, backgroundColor: colors.tang },
  trackDot: {
    position: 'absolute', top: -4, width: 18, height: 18, borderRadius: 9,
    backgroundColor: colors.tang, borderWidth: 3, borderColor: '#fff',
  },
  panel: { backgroundColor: colors.ink, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 20, paddingBottom: 34 },
  chatPin: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#1c2b21', borderRadius: 16, padding: 12,
  },
  btn: { flex: 1, borderRadius: 16, padding: 16, alignItems: 'center' },
  moreBtn: { width: 44, height: 52, borderRadius: 16, backgroundColor: '#1c2b21', alignItems: 'center', justifyContent: 'center' },
  eventBtn: { flex: 1, backgroundColor: '#1c2b21', borderRadius: 14, alignItems: 'center', paddingVertical: 9, borderWidth: 1, borderColor: '#2c4034' },
  sheetBackdrop: { flex: 1, backgroundColor: '#00000066' },
  sheet: { backgroundColor: '#10160f', borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 22, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#2c3a2c', marginBottom: 14 },
  endOption: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#1a231a', borderRadius: 16, padding: 14, marginTop: 10,
  },
  endRail: { width: 4, height: 44, borderRadius: 2 },
  sheetCancel: { alignItems: 'center', paddingVertical: 14, marginTop: 6 },
});
