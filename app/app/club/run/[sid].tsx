import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Linking, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { BigNumRow, ClubCta, ClubMast, ClubTag, DawnCanvas, LiveDot } from '../../../src/components/club-ui';
import {
  clubSos, DelegationBoard, DelegationDog, fetchDelegationBoard, fetchRunStartedAt, fetchSessionRoster,
  saveClubRunTrace, SessionRoster, settleRun,
} from '../../../src/lib/api';
import { acceptFix, createPosPublisher, distM, GeoPoint, getNaverMap, LL, smoothTrace, startTracking } from '../../../src/lib/geo';
import { useNumFont } from '../../../src/lib/fonts';
import { haptic } from '../../../src/lib/haptics';
import { collarColors, CollarKey, lilac, lilacRadius } from '../../../src/theme';

// 클럽 러닝 (러너) — 정본: master-lab R4 (라일락 라이브 — 야외 역광 가독성은 다크가 아니라 대비 규율로)
// §13 준수: 트레이스 = 60초 배치 club_save_run_trace (t 단조·초 단위 — 서버가 불가능 속도 거부),
// km = GPS 실측만 (픽스 게이트 통과분 — 지터로 km 부풀리면 정산 부정직), 데모 폴백 없음.
// 여러 마리 = 부킹 여러 개: 보호자 라이브 채널 전부에 브로드캐스트, 종료는 마리별 (완주/조기 사유).
// SOS = 좌하단 엄지 자리, S1 + 위치 증거.

const L = lilac;

const collarOf = (c: string | null): string => (c && collarColors[c as CollarKey]) || L.coral;

const mmssStr = (sec: number): string =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number): string => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

const END_REASONS = [
  { key: 'dog_condition', label: '아이 컨디션이 걱정돼요', note: '러너 판단: 컨디션 저하 관찰' },
  { key: 'owner_request', label: '보호자 요청', note: undefined },
  { key: 'runner_personal', label: '러너 개인 사정', note: undefined },
] as const;

export default function ClubRun() {
  const nf = useNumFont();
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [roster, setRoster] = useState<SessionRoster | null>(null);
  const [gpsOn, setGpsOn] = useState<boolean | null>(null); // null = 준비 중
  const [km, setKm] = useState(0);
  const [lastPos, setLastPos] = useState<GeoPoint | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [pathLen, setPathLen] = useState(0);
  const [endTarget, setEndTarget] = useState<DelegationDog | null>(null);
  const [busy, setBusy] = useState(false);

  const trace = useRef<GeoPoint[]>([]);
  const kmRef = useRef(0);
  const stopTrack = useRef<null | (() => void)>(null);
  const publisher = useRef<null | { publish: (p: any) => void; stop: () => void }>(null);
  const startedAtMs = useRef<number | null>(null);
  const maps = getNaverMap();

  const load = useCallback(() => {
    if (!sid) return;
    fetchDelegationBoard(sid).then(setBoard).catch(() => {});
    fetchSessionRoster(sid).then(setRoster).catch(() => {});
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  const myRunnerId = board?.runners.find((r) => r.isMe)?.profileId ?? null;
  const active = board && myRunnerId
    ? board.dogs.filter((d) => d.runnerId === myRunnerId && d.bookingStatus === 'active') : [];
  const activeKey = active.map((d) => d.bookingId).filter(Boolean).sort().join(',');

  // 경과 = runs.started_at 실측 (화면 진입 시점이 아니라 러닝 시작 시점부터)
  useEffect(() => {
    const first = active[0]?.bookingId;
    if (!first || startedAtMs.current != null) return;
    fetchRunStartedAt(first).then((iso) => {
      if (iso) startedAtMs.current = new Date(iso).getTime();
    }).catch(() => {});
  }, [activeKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const t = setInterval(() => {
      if (startedAtMs.current) setElapsed(Math.max(0, Math.round((Date.now() - startedAtMs.current) / 1000)));
    }, 1000);
    return () => clearInterval(t);
  }, []);

  // GPS 추적 + 멀티 브로드캐스트 — 활성 부킹이 있는 동안만
  useEffect(() => {
    if (!activeKey) return;
    let alive = true;
    publisher.current?.stop();
    publisher.current = createPosPublisher(activeKey.split(','));
    startTracking((p) => {
      if (!alive) return;
      const prev = trace.current[trace.current.length - 1] ?? null;
      if (!acceptFix(prev, p)) return; // 나쁜 픽스는 그리지도, 세지도 않는다
      trace.current.push(p);
      setPathLen(trace.current.length);
      setLastPos(p);
      if (prev) {
        const d = distM(prev, p);
        if (d > 2 && d < 120) {
          kmRef.current += d / 1000;
          setKm(kmRef.current);
        }
      }
      publisher.current?.publish({ lat: p.lat, lng: p.lng, km: kmRef.current, paceSec: null });
    }).then((stop) => {
      if (!alive) { stop?.(); return; }
      stopTrack.current = stop;
      setGpsOn(stop != null);
    });
    return () => {
      alive = false;
      stopTrack.current?.(); stopTrack.current = null;
      publisher.current?.stop(); publisher.current = null;
    };
  }, [activeKey]);

  // §13 — 60초 배치 트레이스 저장 (전체 트레이스 덮어쓰기 방식, t는 초 단위 단조)
  const saveTrace = useCallback(async () => {
    if (!sid || trace.current.length < 2) return;
    const pts: { lat: number; lng: number; t: number }[] = [];
    let lastT = -1;
    for (const p of trace.current) {
      const t = Math.floor(p.t / 1000);
      if (t <= lastT) continue; // 같은 초 중복 = 서버 trace_out_of_order 방지
      lastT = t;
      pts.push({ lat: p.lat, lng: p.lng, t });
    }
    if (pts.length > 1) await saveClubRunTrace(sid, pts).catch(() => {});
  }, [sid]);
  useEffect(() => {
    const t = setInterval(() => { saveTrace(); }, 60_000);
    return () => clearInterval(t);
  }, [saveTrace]);

  // ---------- 마리별 종료 — 완주 또는 조기 사유, km은 GPS 실측만 ----------
  const doSettle = async (d: DelegationDog, endReason: 'completed' | 'dog_condition' | 'owner_request' | 'runner_personal', note?: string) => {
    if (!d.bookingId || busy) return;
    if (!gpsOn) {
      Alert.alert('GPS 없이 정산할 수 없어요', '클럽 정산은 실측 거리로만 가능해요.\n설정에서 위치 권한을 켠 뒤 다시 시도해주세요.');
      return;
    }
    setBusy(true);
    try {
      await saveTrace(); // active인 동안 마지막 저장 (completed 후엔 저장 창이 닫힌다)
      await settleRun({
        booking_id: d.bookingId,
        end_reason: endReason,
        actual_km: Number(kmRef.current.toFixed(2)),
        duration_sec: Math.max(60, elapsed),
        condition_note: note,
      });
      haptic('success');
      setEndTarget(null);
      const remaining = active.filter((x) => x.sdId !== d.sdId).length;
      load();
      if (remaining === 0) {
        Alert.alert('러닝 종료', '모든 아이의 러닝이 끝났어요 — 집결지에서 반환을 확인해주세요.', [
          { text: '확인', onPress: () => router.back() },
        ]);
      }
    } catch (e) {
      Alert.alert('정산 실패', `${(e as Error).message}\n\n아무것도 반영되지 않았어요 — 다시 시도하면 이어서 정산돼요.`);
    } finally { setBusy(false); }
  };

  const doSosPress = () => {
    Alert.alert('긴급 SOS', 'S1 케이스가 열리고 호스트와 러너 전원에게 즉시 알림이 가요.', [
      { text: '아직', style: 'cancel' },
      {
        text: 'SOS', style: 'destructive',
        onPress: () => clubSos(sid, lastPos ? { lat: lastPos.lat, lng: lastPos.lng, t: Math.floor(lastPos.t / 1000) } : null)
          .then((id) => { haptic('success'); router.push(`/club/case/${id}`); })
          .catch((e) => Alert.alert('SOS 실패', (e as Error).message)),
      },
    ]);
  };

  const emergencyOf = (d: DelegationDog): string | null =>
    roster?.dogs.find((x) => x.sdId === d.sdId)?.detail?.emergencyContact ?? null;

  if (!board) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 13, color: L.dim }}>불러오는 중...</Text>
        </View>
      </DawnCanvas>
    );
  }
  if (active.length === 0) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 13, color: L.dim, textAlign: 'center' }}>진행 중인 러닝이 없어요{'\n'}세션 화면에서 러닝을 시작해주세요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={() => router.back()} style={{ alignSelf: 'stretch' }} />
        </View>
      </DawnCanvas>
    );
  }

  const path: LL[] = trace.current.map((p) => ({ latitude: p.lat, longitude: p.lng }));

  return (
    <DawnCanvas>
      <View style={{ flex: 1, padding: 12, paddingTop: 56 }}>
        <ClubMast
          title="러닝 중"
          sub={`${active.map((d) => d.dogName).join(' · ')}${clubName ? ` — ${clubName}` : ''}`}
          onBack={() => router.back()}
          right={<LiveDot />}
        />

        {/* ---------- 지도 (실지도 or 정직한 대기 패널) ---------- */}
        <View style={s.mapCard}>
          {maps && lastPos ? (
            <maps.NaverMapView
              style={StyleSheet.absoluteFill}
              camera={{ latitude: lastPos.lat, longitude: lastPos.lng, zoom: 15 }}
              isShowLocationButton={false}
              isShowCompass={false}
              isShowScaleBar={false}
              isShowZoomControls={false}
            >
              {pathLen > 1 && (
                <maps.NaverMapPathOverlay
                  coords={smoothTrace(path)}
                  color={L.accent}
                  width={6}
                  outlineWidth={2}
                  outlineColor="#ffffff"
                />
              )}
              <maps.NaverMapMarkerOverlay latitude={lastPos.lat} longitude={lastPos.lng} anchor={{ x: 0.5, y: 1 }} />
            </maps.NaverMapView>
          ) : (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 8 }}>
              <LiveDot />
              <Text style={{ fontSize: 11, color: L.dim, textAlign: 'center', lineHeight: 16 }}>
                {gpsOn === false ? '위치 권한이 꺼져 있어요 — 트레이스·정산이 불가능해요'
                  : !maps ? '지도 미탑재 빌드 — 위치는 기록되고 있어요'
                  : 'GPS 신호를 기다리는 중...'}
              </Text>
            </View>
          )}
        </View>

        {/* ---------- 레저 숫자 ---------- */}
        <BigNumRow items={[
          { v: km.toFixed(1), unit: 'km', label: '거리 (실측)' },
          { v: paceStr(elapsed, km), label: '페이스' },
          { v: mmssStr(elapsed), label: '경과' },
        ]} />

        {/* ---------- 담당 행 — 비상 = 탭하면 전화 · 종료는 마리별 ---------- */}
        {active.map((d) => {
          const em = emergencyOf(d);
          return (
            <View key={d.sdId} style={s.dogRow}>
              <View style={[s.dogDot, { borderColor: collarOf(d.collar) }]}>
                <Text style={{ fontSize: 12, fontWeight: '800', color: '#5d5138' }}>{d.dogName[0]}</Text>
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 13, fontWeight: '800', color: L.head }}>{d.dogName} · {d.ownerName} 보호자</Text>
                {em ? (
                  <Pressable onPress={() => Linking.openURL(`tel:${em.replace(/[^0-9+]/g, '')}`).catch(() => {})}>
                    <Text style={{ fontSize: 10, color: L.accent, marginTop: 1, fontWeight: '700' }}>비상 {em} — 탭하면 전화</Text>
                  </Pressable>
                ) : (
                  <Text style={{ fontSize: 10, color: L.dim, marginTop: 1 }}>비상 연락처 로딩 중</Text>
                )}
              </View>
              <Pressable onPress={() => setEndTarget(d)} style={s.endBtn}>
                <Text style={{ fontSize: 10.5, fontWeight: '800', color: L.text }}>종료</Text>
              </Pressable>
            </View>
          );
        })}

        <View style={{ flex: 1 }} />

        {/* ---------- SOS — 좌하단 엄지 자리 ---------- */}
        <Row style={{ gap: 12, alignItems: 'center', marginBottom: 10 }}>
          <Pressable onPress={doSosPress} style={s.sos}>
            <Text style={{ fontSize: 13, fontWeight: '900', color: '#fff' }}>SOS</Text>
          </Pressable>
          <View style={{ flex: 1 }}>
            <ClubCta
              label={active.length === 1 ? `${active[0].dogName} 러닝 종료 →` : '러닝 종료 (마리별) →'}
              onPress={() => setEndTarget(active[0])}
              busy={busy}
              style={{ marginTop: 0 }}
            />
          </View>
        </Row>
      </View>

      {/* ---------- 종료 시트 — 완주가 기본, 조기 사유는 정직하게 ---------- */}
      <Modal visible={!!endTarget} transparent animationType="slide" onRequestClose={() => setEndTarget(null)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.45)' }} onPress={() => setEndTarget(null)} />
        <View style={s.sheet}>
          <View style={s.grab} />
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>{endTarget?.dogName} 러닝 종료</Text>
            <Text style={[{ fontSize: 20, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] }, nf]}>
              {km.toFixed(1)}<Text style={{ fontSize: 13, color: L.coral }}>km</Text>
            </Text>
          </Row>
          <Text style={{ fontSize: 10.5, color: L.dim, marginTop: 4 }}>실측 {km.toFixed(2)}km · {mmssStr(elapsed)} — 이 기록으로 정산돼요</Text>
          <ClubCta label="완주로 종료 →" onPress={() => endTarget && doSettle(endTarget, 'completed')} busy={busy} />
          <Text style={{ fontSize: 9.5, color: L.dim, marginTop: 14, marginBottom: 4, fontWeight: '700', letterSpacing: 1 }}>조기 종료</Text>
          {END_REASONS.map((r) => (
            <Pressable key={r.key} disabled={busy}
              onPress={() => endTarget && doSettle(endTarget, r.key, r.note)}
              style={s.reasonRow}>
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: L.text }}>{r.label}</Text>
            </Pressable>
          ))}
        </View>
      </Modal>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  mapCard: {
    height: 240, borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 10,
    backgroundColor: '#E9E5F8', borderWidth: 1, borderColor: L.hair,
  },
  dogRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 10, paddingHorizontal: 12, marginTop: 8,
  },
  dogDot: {
    width: 30, height: 30, borderRadius: 15, backgroundColor: '#C9B89A',
    borderWidth: 2, alignItems: 'center', justifyContent: 'center',
  },
  endBtn: {
    backgroundColor: L.inset, borderRadius: lilacRadius.tag, paddingVertical: 7, paddingHorizontal: 12,
  },
  sos: {
    width: 58, height: 58, borderRadius: 29, backgroundColor: L.tang,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: L.tang, shadowOpacity: 0.45, shadowRadius: 14, shadowOffset: { width: 0, height: 8 }, elevation: 5,
  },
  sheet: {
    backgroundColor: L.bg, borderTopLeftRadius: lilacRadius.screen, borderTopRightRadius: lilacRadius.screen,
    padding: 16, paddingBottom: 34,
  },
  grab: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: L.hair, marginBottom: 12 },
  reasonRow: {
    backgroundColor: L.card, borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.inner,
    paddingVertical: 11, paddingHorizontal: 13, marginTop: 7,
  },
});
