import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Linking, Modal, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Icon, Row } from '../../../src/components/ui';
import { BigNumRow, ClubCta, ClubMast, ClubTag, DawnCanvas, LiveDot, LoadGate } from '../../../src/components/club-ui';
import {
  addRunEvent, DelegationBoard, DelegationDog, fetchDelegationBoard, fetchRunStartedAt,
  fetchSessionRoster, incidentOpen, saveClubRunTrace, SessionRoster, settleRun, uploadRunPhoto,
} from '../../../src/lib/api';
import { supabase } from '../../../src/lib/supabase';
import { createPosPublisher, distM, GeoPoint, getNaverMap, getTraceSnapshot, LL, resetTrace, seedTrace, smoothTrace, startTracking, TrackHandle, TrackMode } from '../../../src/lib/geo';
import { useNumFont } from '../../../src/lib/fonts';
import { haptic } from '../../../src/lib/haptics';
import { collarColors, CollarKey, lilac, lilacRadius, lilacShadow } from '../../../src/theme';

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

// [2026-08-13] The `note` field is GONE, and its absence is the fix. `dog_condition` carried
// the constant '러너 판단: 컨디션 저하 관찰', which settle-run stored as `runs.condition_note`
// and owner/report.tsx renders under the heading 러너 노트 — the runner's own written account
// of someone's dog. The runner never typed it and was never shown a field. Every owner read the
// same sentence about a different dog.
// `611f014` fixed exactly this on the marketplace surface (runner/run.tsx); the club surface
// was a second copy nobody had grepped, found by the ⑩ class sweep. It matters more than a
// copy bug: G1's anti-gaming control is "the owner can see the runner's account and judge
// whether it is true" (0084:120-122), and under Sean's ruling the owner is now BILLED for a
// condition stop — so this note is the dispute surface too. A constant cannot be evidence.
// Mirrors the marketplace flow: pick the reason, then write what you saw, and the submit is
// gated on it being non-empty (the server requires a note on this reason: settle-run:74).
const END_REASONS = [
  { key: 'dog_condition', label: '아이 컨디션이 걱정돼요', needsNote: true },
  { key: 'owner_request', label: '보호자 요청', needsNote: false },
  { key: 'runner_personal', label: '러너 개인 사정', needsNote: false },
] as const;

export default function ClubRun() {
  const nf = useNumFont();
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [roster, setRoster] = useState<SessionRoster | null>(null);
  // [2026-08-08] boolean이 아니라 판별 결과 — '지도 미탑재 빌드'와 '권한 거부'가 한 불리언으로
  // 뭉개져 엉뚱한 이유를 보여주던 것을 끝낸다. null = 준비 중
  const [trackMode, setTrackMode] = useState<TrackMode | null>(null);
  const [km, setKm] = useState(0);
  const [lastPos, setLastPos] = useState<GeoPoint | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [pathLen, setPathLen] = useState(0);
  const [endTarget, setEndTarget] = useState<DelegationDog | null>(null);
  // two-step end: 'reason' → 'note' (only for the reason the server requires one on)
  const [endStep, setEndStep] = useState<'reason' | 'note'>('reason');
  const [conditionNote, setConditionNote] = useState('');
  const canSubmitNote = conditionNote.trim().length > 0;
  const [busy, setBusy] = useState(false);

  const [saveLag, setSaveLag] = useState(false); // [감사 P1] 트레이스 저장 실패를 침묵시키지 않는다
  const trace = useRef<GeoPoint[]>([]);
  const kmRef = useRef(0);
  const hydrated = useRef(false);
  const handle = useRef<TrackHandle | null>(null);
  const modeRef = useRef<TrackMode | null>(null);
  const publisher = useRef<null | { publish: (p: any) => void; stop: () => void }>(null);
  const startedAtMs = useRef<number | null>(null);
  const maps = getNaverMap();

  // [감사 P0] 재진입 시 km·트레이스가 0부터 시작해 서버 트레이스를 잘라먹고 정산 km이 과소 보고되던 것 —
  // 마운트 시 서버 runs.trace(전 활성 부킹 동일 배열)로 시드하고 같은 게이트로 km을 재계산한다.
  const hydrateFromServer = useCallback(async (bookingId: string) => {
    if (hydrated.current) return;
    hydrated.current = true;
    try {
      const { data } = await supabase.from('runs').select('trace').eq('booking_id', bookingId).maybeSingle();
      const saved: { lat: number; lng: number; t: number }[] = (data as any)?.trace ?? [];
      // [2026-08-08] km 재계산은 seedTrace(=mergeFixes)가 한다 — 라이브와 하이드레이션이
      // 같은 게이트를 쓰지 않으면 두 숫자가 갈라진다. 이미 픽스가 들어온 뒤면 덮지 않는다.
      if (saved.length > 1 && getTraceSnapshot().trace.length === 0) {
        const snap = seedTrace(saved.map((p) => ({ lat: p.lat, lng: p.lng, t: p.t * 1000 })));
        if (snap) {
          trace.current = snap.trace;
          kmRef.current = snap.km;
          setKm(snap.km);
          setPathLen(snap.trace.length);
        }
      }
    } catch { /* 시드 실패 = 새 트레이스로 진행 (저장은 덮어쓰기라 이 경우 이전 기록이 짧아질 수 있음) */ }
  }, []);

  // [honesty 2026-08-11] 로스터(비상 연락처) 실패가 라이브 러닝 중 '로딩 중'으로 영원히
  // 굳던 것 — 안전 데이터는 라우드 페일 + 재시도. 직전 실값은 유지.
  const [rosterErr, setRosterErr] = useState(false);
  // [감사 H1 2026-08-11] 이 화면은 클럽에서 유일하게 LoadGate가 없었다 — board 실패를 조용히 삼키고
  // '불러오는 중...'을 영원히 그렸다. 뒤로도, 재시도도 없이. **달리고 있는 개를 들고 있는 화면**에서
  // 진입 시 네트워크 한 번 튀면 영영 갇힌다. 나머지 5개 딥링크 화면은 전부 LoadGate로 이관됐다.
  const [boardErr, setBoardErr] = useState(false);
  // [기기에서 발견 2026-08-11] LoadGate를 달고 실제로 열어보니 '불러오는 중...'에서 안 넘어갔다.
  // 이유: fetchDelegationBoard는 없는/권한 없는 세션에 **throw가 아니라 null을 resolve**한다
  // (api.ts:2511). 그래서 catch가 영영 안 돌고 board는 null인 채 '로딩'으로 읽혔다.
  // null-resolve를 '아직 로딩 중'과 같은 것으로 취급한 게 버그다 — 셋을 구분한다.
  const [boardLoaded, setBoardLoaded] = useState(false);
  const load = useCallback(() => {
    if (!sid) return;
    setBoardErr(false);
    fetchDelegationBoard(sid)
      .then((b) => { setBoard(b); setBoardLoaded(true); })
      .catch(() => { setBoardErr(true); setBoardLoaded(true); });
    setRosterErr(false);
    fetchSessionRoster(sid).then(setRoster).catch(() => setRosterErr(true));
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  const myRunnerId = board?.runners.find((r) => r.isMe)?.profileId ?? null;
  const active = board && myRunnerId
    ? board.dogs.filter((d) => d.runnerId === myRunnerId && d.bookingStatus === 'active') : [];
  const activeKey = active.map((d) => d.bookingId).filter(Boolean).sort().join(',');

  // 경과 = runs.started_at 실측. [감사 P1] 실패 시 재시도 없던 것 — 틱 안에서 미확보면 재요청
  const fetchingStart = useRef(false);
  const tryFetchStart = useCallback(() => {
    const first = active[0]?.bookingId;
    if (!first || startedAtMs.current != null || fetchingStart.current) return;
    fetchingStart.current = true;
    fetchRunStartedAt(first)
      .then((iso) => { if (iso) startedAtMs.current = new Date(iso).getTime(); })
      .catch(() => {})
      .finally(() => { fetchingStart.current = false; });
  }, [activeKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    tryFetchStart();
    const first = active[0]?.bookingId;
    if (first) hydrateFromServer(first);
  }, [activeKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const t = setInterval(() => {
      if (startedAtMs.current) setElapsed(Math.max(0, Math.round((Date.now() - startedAtMs.current) / 1000)));
      else tryFetchStart();
    }, 1000);
    return () => clearInterval(t);
  }, [tryFetchStart]);

  // GPS 추적 + 멀티 브로드캐스트 — 활성 부킹이 있는 동안만
  useEffect(() => {
    if (!activeKey) return;
    let alive = true;
    publisher.current?.stop();
    publisher.current = createPosPublisher(activeKey.split(','));
    // [2026-08-08] 거리 산수는 geo.ts의 단일 싱크(mergeFixes)로 이동 — 8m/s 정산 게이트도 거기 있다.
    // 백그라운드 배치로 들어오든 포그라운드 한 점씩 들어오든 km은 같아야 한다.
    startTracking((snap) => {
      if (!alive) return;
      trace.current = snap.trace;
      setPathLen(snap.trace.length);
      setLastPos(snap.last);
      kmRef.current = snap.km;
      setKm(snap.km);
      publisher.current?.publish({
        lat: snap.last.lat, lng: snap.last.lng, km: snap.km, paceSec: null, mode: modeRef.current ?? undefined,
      });
    }, { dogName: active.map((d) => d.dogName).join('·') }).then((h) => {
      if (!alive) { h.stop(); return; }
      handle.current = h;
      modeRef.current = h.mode;
      setTrackMode(h.mode);
    }).catch(() => { if (alive) setTrackMode('unavailable'); }); // 영구 '준비 중' 고착 방지
    return () => {
      alive = false;
      handle.current?.stop(); handle.current = null;
      publisher.current?.stop(); publisher.current = null;
    };
  }, [activeKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // 화면을 떠날 때 공용 버퍼를 비운다 — 다음 러닝(1:1 포함)이 이 세션의 점을 물려받으면 안 된다
  useEffect(() => () => { resetTrace(); }, []);

  // §13 — 60초 배치 트레이스 저장 (전체 덮어쓰기, t 초 단위 단조).
  // [감사 P1] 실패를 삼키지 않는다: 무결성 거부(impossible_speed 등)면 문제 구간을 잘라 1회 재시도,
  // 그래도 실패면 saveLag 배너. 언마운트 시 마지막 저장 1회.
  const saveTrace = useCallback(async () => {
    if (!sid || trace.current.length < 2) return;
    const build = (src: GeoPoint[]) => {
      const pts: { lat: number; lng: number; t: number }[] = [];
      let lastT = -1;
      let prev: { lat: number; lng: number; t: number } | null = null;
      for (const p of src) {
        const t = Math.floor(p.t / 1000);
        if (t <= lastT) continue;
        // 서버 등장방형 근사와 같은 8m/s 게이트를 전송 전에 적용 — 배치 전체 거부 예방
        if (prev) {
          const dist = Math.sqrt(((p.lat - prev.lat) * 111000) ** 2 + ((p.lng - prev.lng) * 88800) ** 2);
          if (dist / (t - prev.t) > 8) continue;
        }
        lastT = t;
        prev = { lat: p.lat, lng: p.lng, t };
        pts.push(prev);
      }
      return pts;
    };
    const pts = build(trace.current);
    if (pts.length < 2) return;
    try {
      await saveClubRunTrace(sid, pts);
      setSaveLag(false);
    } catch {
      setSaveLag(true);
    }
  }, [sid]);
  useEffect(() => {
    const t = setInterval(() => { saveTrace(); }, 60_000);
    return () => { clearInterval(t); saveTrace(); }; // 언마운트 시 최대 60초분 유실 방지
  }, [saveTrace]);

  // ---------- 마리별 종료 — 완주 또는 조기 사유, km은 GPS 실측만 ----------
  // [감사 P1] 늦게 인계된 아이가 그룹 누적 km·최초 경과를 받던 것 — 그 아이의 started_at 기준으로 절단.
  // [감사 P1] Math.max(60, elapsed)는 시간을 지어냈다 — 실측 그대로 보낸다 (40초 러닝은 40초다).
  const doSettle = async (d: DelegationDog, endReason: 'completed' | 'dog_condition' | 'owner_request' | 'runner_personal', note?: string) => {
    if (!d.bookingId || busy) return;
    if (trackMode === 'denied') {
      Alert.alert('GPS 없이 정산할 수 없어요', '클럽 정산은 실측 거리로만 가능해요.\n설정에서 위치 권한을 켠 뒤 다시 시도해주세요.');
      return;
    }
    if (trackMode === 'unavailable') {
      Alert.alert('위치 기능이 없는 빌드예요', '이 빌드로는 거리를 잴 수 없어요 — 새 빌드에서 다시 시도해주세요.');
      return;
    }
    if (trackMode == null) {
      Alert.alert('위치 준비 중이에요', '잠시 후 다시 시도해주세요.');
      return;
    }
    // 'foreground'는 막지 않는다: 이미 진행 중인 클럽 러닝의 정산을 막으면 예약이 좌초된다.
    // 대신 화면 상단 스트립이 러닝 내내 '앱을 켜 둔 동안만 기록된다'고 계속 말하고 있다.
    setBusy(true);
    try {
      const iso = await fetchRunStartedAt(d.bookingId);
      if (!iso) {
        Alert.alert('종료 불가', '이 아이의 러닝 시작 기록을 읽지 못했어요 — 잠시 후 다시 시도해주세요.');
        return;
      }
      const startMsDog = new Date(iso).getTime();
      const durationSec = Math.round((Date.now() - startMsDog) / 1000);
      let kmDog = 0;
      const pts = trace.current;
      for (let i = 1; i < pts.length; i++) {
        if (pts[i - 1].t < startMsDog) continue;
        const dd = distM(pts[i - 1], pts[i]);
        const dt = (pts[i].t - pts[i - 1].t) / 1000;
        if (dd > 2 && dd < 120 && dt > 0 && dd / dt <= 8) kmDog += dd / 1000;
      }
      await saveTrace(); // active인 동안 마지막 저장 (completed 후엔 저장 창이 닫힌다)
      await settleRun({
        booking_id: d.bookingId,
        end_reason: endReason,
        actual_km: Number(kmDog.toFixed(2)),
        duration_sec: Math.max(1, durationSec),
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

  // [감사 P1 → 0067 C3] 러닝 중 SOS는 담당견을 대상에 붙여 S1을 연다 (여러 마리면 고른다).
  // 0067이 club_sos를 club_incident_open의 얇은 래퍼로 통합했으므로 어느 문으로 들어와도
  // 팬아웃·지급 보류·보호자 알림이 같이 온다 — 여기서 개를 붙이는 이유는 이제 '보류를 걸기
  // 위해서'가 아니라 **누구 일인지 말하기 위해서**다 (보호자 알림이 아이 이름을 싣는다).
  const fireSos = (d: DelegationDog | null) => {
    incidentOpen(sid, 'S1', '긴급 SOS', {
      dog: d?.dogId ?? null, booking: d?.bookingId ?? null,
      location: lastPos ? { lat: lastPos.lat, lng: lastPos.lng, t: Math.floor(lastPos.t / 1000) } : null,
    })
      .then((id) => { haptic('success'); router.push(`/club/case/${id}`); })
      .catch((e) => Alert.alert('SOS 실패', (e as Error).message));
  };
  const doSosPress = () => {
    // 카피는 이 순간 참인 것만 말한다: 맡고 있는 아이가 없으면 대상견도, 보호자 알림도,
    // 지급 보류도 없다 — 그때 보류를 약속하면 거짓말이 된다.
    Alert.alert('긴급 SOS', active.length > 0
      ? 'S1 케이스가 열려요 — 호스트·러너 전원과 그 아이 보호자에게 즉시 알림이 가고, 그 아이 정산은 해소까지 보류돼요.'
      : 'S1 케이스가 열리고 호스트와 러너 전원에게 즉시 알림이 가요. 지금 맡고 있는 아이가 없어 세션 전체 건으로 접수돼요.', [
      { text: '아직', style: 'cancel' },
      ...(active.length > 1
        ? active.slice(0, 3).map((d) => ({ text: `SOS — ${d.dogName}`, style: 'destructive' as const, onPress: () => fireSos(d) }))
        : [{ text: 'SOS', style: 'destructive' as const, onPress: () => fireSos(active[0] ?? null) }]),
    ]);
  };

  const emergencyOf = (d: DelegationDog): string | null =>
    roster?.dogs.find((x) => x.sdId === d.sdId)?.detail?.emergencyContact ?? null;

  // 러닝 사진 — 함께 뛴 사진이니 활성 마리 전원의 런에 실린다 (보호자 라이브 폴라로이드·영수증 인화의 원천).
  // 보호자에겐 '새 사진 도착' 알림 (addRunEvent photo — 1:1 문법 그대로)
  const doPhoto = async () => {
    if (busy) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch { Alert.alert('개발 빌드 업데이트 필요', '카메라는 새 빌드에 포함돼요'); return; }
    try {
      const camPerm = await ImagePicker.requestCameraPermissionsAsync().catch(() => ({ granted: false }));
      let res: any = null;
      if (camPerm.granted) {
        res = await ImagePicker.launchCameraAsync({ quality: 0.5, base64: true });
      } else {
        const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
        if (!perm.granted) return;
        res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.5, base64: true, selectionLimit: 1 });
      }
      if (!res || res.canceled || !res.assets?.[0]?.base64) return;
      const b64 = res.assets[0].base64 as string;
      setBusy(true);
      // [감사 P2] 중간 실패 후 재시도 시 앞 아이에 중복 append 되던 것 — 실패한 아이만 모아 정직하게 알린다
      const failed: string[] = [];
      for (const d of active) {
        if (!d.bookingId) continue;
        try {
          await uploadRunPhoto(d.bookingId, b64);
          addRunEvent(d.bookingId, 'photo').catch(() => {});
        } catch { failed.push(d.dogName); }
      }
      if (failed.length > 0) {
        Alert.alert('일부 업로드 실패', `${failed.join('·')}의 기록엔 사진이 실리지 않았어요 — 다시 찍으면 성공한 아이에겐 중복돼요`);
      }
      haptic('success');
    } catch (e) {
      Alert.alert('사진 업로드 실패', (e as Error).message);
    } finally { setBusy(false); }
  };

  if (!board) {
    return (
      <LoadGate
        mode={boardErr ? 'error' : boardLoaded ? 'denied' : 'loading'}
        errorLabel="러닝 정보를 불러오지 못했어요"
        deniedLabel="이 세션을 볼 수 없어요 — 없어졌거나 참가자가 아니에요"
        onRetry={load}
        onBack={() => router.back()}
      />
    );
  }
  if (active.length === 0) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 14, color: L.dim, textAlign: 'center' }}>진행 중인 러닝이 없어요{'\n'}세션 화면에서 러닝을 시작해주세요</Text>
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
        {saveLag && (
          <View style={s.lagBanner}>
            <Text style={{ fontSize: 14, color: '#7a5a2a' }}>트레이스 저장이 밀리고 있어요 — 신호가 잡히면 자동 재시도해요</Text>
          </View>
        )}
        {trackMode === 'foreground' && (
          <View style={s.lagBanner}>
            <Text style={{ fontSize: 14, color: '#7a5a2a' }}>앱을 켜 둔 동안만 기록돼요 — 화면이 꺼지면 거리가 멈춰요</Text>
          </View>
        )}

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
              <Text style={{ fontSize: 14, color: L.dim, textAlign: 'center', lineHeight: 18 }}>
                {trackMode === 'denied' ? '위치 권한이 꺼져 있어요 — 트레이스·정산이 불가능해요'
                  : trackMode === 'unavailable' ? '위치 기능이 없는 빌드예요 — 새 빌드에서 기록돼요'
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
                <Text style={{ fontSize: 14, fontWeight: '800', color: '#5d5138' }}>{d.dogName[0]}</Text>
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>{d.dogName} · {d.ownerName} 보호자</Text>
                {em ? (
                  <Pressable onPress={() => Linking.openURL(`tel:${em.replace(/[^0-9+]/g, '')}`).catch(() => {})}>
                    <Text style={{ fontSize: 14, color: L.accent, marginTop: 1, fontWeight: '700' }}>비상 {em} — 탭하면 전화</Text>
                  </Pressable>
                ) : rosterErr && roster == null ? (
                  // safety datum failed during a LIVE run — loud fail + retry, never eternal loading
                  <Pressable onPress={load} hitSlop={8} accessibilityRole="button">
                    <Text style={{ fontSize: 14, color: L.tang, marginTop: 1, fontWeight: '800' }}>비상 연락처를 불러오지 못했어요 — 다시 시도 ›</Text>
                  </Pressable>
                ) : roster == null ? (
                  <Text style={{ fontSize: 14, color: L.dim, marginTop: 1 }}>비상 연락처 로딩 중</Text>
                ) : (
                  <Text style={{ fontSize: 14, color: L.dim, marginTop: 1 }}>비상 연락처 미등록</Text>
                )}
              </View>
              <Pressable onPress={() => setEndTarget(d)} style={s.endBtn}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: L.text }}>종료</Text>
              </Pressable>
            </View>
          );
        })}

        <View style={{ flex: 1 }} />

        {/* ---------- SOS(좌하단 엄지) · 카메라 · 종료 ---------- */}
        <Row style={{ gap: 12, alignItems: 'center', marginBottom: 10 }}>
          <Pressable onPress={doSosPress} style={s.sos}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>SOS</Text>
          </Pressable>
          <Pressable onPress={doPhoto} style={s.camBtn}>
            <Icon name="Camera" glyph="◉" size={20} color={L.head} />
          </Pressable>
          <View style={{ flex: 1 }}>
            {/* [Sean 규칙] 하단 여백이 넓은 화면 — 주 버튼을 키운다 */}
            <ClubCta
              label={active.length === 1 ? `${active[0].dogName} 러닝 종료 →` : '러닝 종료 (마리별) →'}
              onPress={() => setEndTarget(active[0])}
              busy={busy}
              style={{ marginTop: 0, paddingVertical: 18 }}
            />
          </View>
        </Row>
      </View>

      {/* ---------- 종료 시트 — 완주가 기본, 조기 사유는 정직하게 ---------- */}
      <Modal visible={!!endTarget} transparent animationType="slide" onRequestClose={() => { setEndTarget(null); setEndStep('reason'); }}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.45)' }} onPress={() => { setEndTarget(null); setEndStep('reason'); }} />
        <View style={s.sheet}>
          <View style={s.grab} />
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>{endTarget?.dogName} 러닝 종료</Text>
            <Text style={[{ fontSize: 20, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] }, nf]}>
              {km.toFixed(1)}<Text style={{ fontSize: 14, color: L.coral }}>km</Text>
            </Text>
          </Row>
          <Text style={{ fontSize: 14, color: L.dim, marginTop: 4 }}>
            {active.length > 1
              ? `함께 달린 누적 ${km.toFixed(2)}km · ${mmssStr(elapsed)} — 정산은 이 아이의 시작 시점부터 실측으로 계산돼요`
              : `실측 ${km.toFixed(2)}km · ${mmssStr(elapsed)} — 이 기록으로 정산돼요`}
          </Text>
          <ClubCta label="완주로 종료 →" onPress={() => endTarget && doSettle(endTarget, 'completed')} busy={busy} />
          {/* [D13 FLOOR14 2026-08-12] 9.5 → 14. '조기 종료'는 러닝 종료 화면의 한글 섹션 라벨이다. */}
          <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 14, marginBottom: 4, fontWeight: '700', letterSpacing: 0.4 }}>조기 종료</Text>
          {endStep === 'reason'
            ? END_REASONS.map((r) => (
              <Pressable key={r.key} disabled={busy}
                onPress={() => {
                  if (!endTarget) return;
                  // the note step exists only where the note is real evidence — and where the
                  // server refuses without one (settle-run:74)
                  if (r.needsNote) { setConditionNote(''); setEndStep('note'); return; }
                  doSettle(endTarget, r.key);
                }}
                style={s.reasonRow}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: L.text }}>{r.label}</Text>
              </Pressable>
            ))
            : (
              <View style={{ marginTop: 4 }}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: L.text, marginBottom: 6 }}>관찰한 내용</Text>
                <TextInput
                  style={s.noteInput}
                  value={conditionNote}
                  onChangeText={setConditionNote}
                  placeholder="예: 3km 지점부터 헐떡임이 심해지고 걸음을 멈춰서 그늘에서 쉬었어요"
                  placeholderTextColor={L.dim}
                  multiline
                  editable={!busy}
                />
                <Text style={{ fontSize: 13, lineHeight: 18, color: L.dim, marginTop: 6 }}>
                  보호자가 리포트에서 그대로 읽어요 — 보신 것을 적어주세요
                </Text>
                <ClubCta
                  label={canSubmitNote ? '컨디션 종료로 기록 →' : '내용을 적어주세요'}
                  onPress={() => { if (endTarget && canSubmitNote) doSettle(endTarget, 'dog_condition', conditionNote.trim()); }}
                  busy={busy}
                  disabled={!canSubmitNote || busy}
                />
                <Pressable disabled={busy} onPress={() => setEndStep('reason')} style={{ paddingVertical: 10 }}>
                  <Text style={{ fontSize: 13, color: L.dim, textAlign: 'center' }}>← 사유 다시 고르기</Text>
                </Pressable>
              </View>
            )}
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
  lagBanner: {
    backgroundColor: L.amberSoft, borderWidth: 1, borderColor: L.amberEdge,
    borderRadius: lilacRadius.inner, padding: 8, paddingHorizontal: 12, marginTop: 8,
  },
  camBtn: {
    width: 46, height: 46, borderRadius: 23, backgroundColor: L.card,
    borderWidth: 1, borderColor: L.hair, alignItems: 'center', justifyContent: 'center',
    ...lilacShadow, shadowOpacity: 0.1,
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
  // the runner's own account of the dog — the field that had to exist before the note could
  // stop being a constant (2026-08-13)
  noteInput: {
    backgroundColor: L.card, borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.inner,
    paddingVertical: 11, paddingHorizontal: 13, minHeight: 88, textAlignVertical: 'top',
    fontSize: 14, lineHeight: 20, color: L.text,
  },
});
