import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { Alert, Dimensions, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { HeatTrace } from '../../src/components/runcard';
import { Monogram, Row } from '../../src/components/ui';
import { dog, draft, lastRunTrace, runners } from '../../src/store';
import { colors } from '../../src/theme';

// 라이브 런 (보호자 뷰) — light map + heat route + POI, bodycam PIP,
// dark stat panel w/ BPM/KCAL/SPM, coral 종료. Simulated progress.
// Real version: expo-location → Supabase realtime → react-native-maps + stream.

const { width: SCREEN_W } = Dimensions.get('window');
const FOREST = '#132117';
const TOTAL_SEC = 2052; // 34:12

const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

const POIS = [
  { label: '생태숲', x: 0.28, y: 0.38 },
  { label: '습지원', x: 0.22, y: 0.68 },
  { label: '가족마당', x: 0.72, y: 0.85 },
];

const STOP_REASONS = ['아이 컨디션이 걱정돼요', '급한 일정이 생겼어요', '기타 사유'];

export default function Live() {
  const [t, setT] = useState(0);
  const [stopSheet, setStopSheet] = useState(false);
  const [stopReason, setStopReason] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const runner = runners.find((r) => r.id === draft.runnerId) ?? runners[0];

  const confirmStop = () => {
    setStopSheet(false);
    Alert.alert(
      '종료 요청 전송됨',
      `${runner.name} 러너에게 강제 알림이 전송됐어요.\n러너가 안전하게 정지한 뒤 ${dog.name}를 데리고 복귀합니다 (목업)`,
    );
    router.replace('/owner/pay');
  };

  useEffect(() => {
    timer.current = setInterval(() => setT((prev) => (prev >= 1 ? 1 : Math.min(prev + 0.004, 1))), 80);
    return () => { if (timer.current) clearInterval(timer.current); };
  }, []);

  useEffect(() => {
    if (t >= 1) {
      const id = setTimeout(() => router.replace('/owner/pay'), 1200);
      return () => clearTimeout(id);
    }
  }, [t]);

  const km = draft.km * t;
  const sec = TOTAL_SEC * t;
  const mapW = SCREEN_W;
  const mapH = 420;
  const dotIdx = Math.min(Math.floor(t * (lastRunTrace.length - 1)), lastRunTrace.length - 1);
  const dot = lastRunTrace[dotIdx];

  return (
    <View style={{ flex: 1, backgroundColor: '#eef2e4' }}>
      <StatusBar style="dark" />

      {/* ---------- map ---------- */}
      <View style={{ height: mapH + 90, overflow: 'hidden' }}>
        {/* map texture */}
        <View style={s.mapRoadH} />
        <View style={s.mapRoadV} />
        <View style={s.mapWater} />

        {/* heat route */}
        <View style={{ position: 'absolute', left: 24, right: 24, top: 100, height: mapH - 60 }}>
          <HeatTrace points={lastRunTrace} width={mapW - 48} height={mapH - 60} />
          {/* live position dot */}
          <View
            style={[s.liveDot, {
              left: dot.x * (mapW - 48) - 11,
              top: dot.y * (mapH - 60) - 11,
            }]}
          />
        </View>

        {/* POIs */}
        {POIS.map((poi) => (
          <View key={poi.label} style={{ position: 'absolute', left: poi.x * mapW, top: 100 + poi.y * (mapH - 60), flexDirection: 'row', alignItems: 'center', gap: 4 }}>
            <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: '#6aa53c' }} />
            <Text style={{ fontSize: 11, fontWeight: '700', color: '#7a8a6d' }}>{poi.label}</Text>
          </View>
        ))}

        {/* top bar */}
        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={s.livePill}>
            <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>
              ● LIVE · {t >= 1 ? '러닝 완료!' : `${dog.name}가 달리는 중`}
            </Text>
          </View>
          <Pressable style={s.circleBtn}><Text style={{ fontSize: 14 }}>▣</Text></Pressable>
        </Row>

        {/* course chip */}
        <View style={s.courseChip}>
          <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#fff' }}>서울숲 코스</Text>
          <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>{draft.km}km</Text>
        </View>

        {/* bodycam PIP */}
        <View style={s.bodycam}>
          <View style={s.camVisual}>
            <View style={{ position: 'absolute', bottom: 0, left: 10, right: 10, height: 54, borderTopLeftRadius: 26, borderTopRightRadius: 26, backgroundColor: '#a97e4f' }} />
            <View style={{ position: 'absolute', bottom: 30, alignSelf: 'center', width: 34, height: 9, borderRadius: 4, backgroundColor: '#2c2c2c' }} />
          </View>
          <Row style={{ position: 'absolute', top: 8, left: 8, gap: 4 }}>
            <View style={s.recDot} />
            <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff', letterSpacing: 1 }}>REC</Text>
          </Row>
          <Row style={{ position: 'absolute', bottom: 8, left: 8, right: 8, justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 9.5, color: '#fff' }}>러너 바디캠</Text>
            <Text style={{ fontSize: 10, color: '#fff' }}>⇲</Text>
          </Row>
        </View>

        {/* locate btn */}
        <View style={[s.circleBtn, { position: 'absolute', left: 20, bottom: 18 }]}>
          <Text style={{ fontSize: 14, color: FOREST }}>➤</Text>
        </View>

        {/* SOS — 안심 센터 (safety matters most mid-run) */}
        <Pressable onPress={() => router.push('/safety')} style={s.sosBtn}>
          <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>SOS</Text>
        </Pressable>

        {/* 종료 — deliberately small; owners shouldn't need it, but it must be findable */}
        <Pressable
          onPress={() => { setStopReason(null); setStopSheet(true); }}
          style={s.stopBtn}
        >
          <Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>■</Text>
          <Text style={{ fontSize: 7.5, fontWeight: '800', color: '#ffffffcc', marginTop: 1 }}>종료</Text>
        </Pressable>
      </View>

      {/* ---------- progress strip ---------- */}
      <View style={s.progressStrip}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 7 }}>
          <Text style={{ fontSize: 12, fontWeight: '700', color: '#3d453d' }}>서울숲 코스 · {draft.km}km</Text>
          <Text style={{ fontSize: 12, fontWeight: '900', color: FOREST }}>{Math.round(t * 100)}%</Text>
        </Row>
        <View style={s.progressTrack}>
          <View style={[s.progressFill, { width: `${t * 100}%` }]} />
          <View style={[s.progressDot, { left: `${Math.max(t * 100 - 3, 0)}%` }]} />
        </View>
      </View>

      {/* ---------- dark panel ---------- */}
      <View style={s.panel}>
        <Row style={{ gap: 11 }}>
          <Monogram char={runner.char} bg={runner.color} size={44} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>{runner.name} 러너</Text>
            <Text style={{ fontSize: 11.5, color: '#b8c4ae', marginTop: 2 }}>{dog.name}와 러닝 중</Text>
          </View>
          <View style={s.signalPill}><Text style={{ fontSize: 11, fontWeight: '800', color: colors.volt }}>ılı 좋음</Text></View>
          <View style={s.gearBtn}><Text style={{ fontSize: 13, color: '#b8c4ae' }}>⚙</Text></View>
        </Row>

        {/* big stats */}
        <Row style={{ marginTop: 18 }}>
          <BigStat glyph="⌖" value={km.toFixed(1)} unit="km" label="거리" />
          <View style={s.panelDiv} />
          <BigStat glyph="◷" value={fmt(sec)} label="시간" />
          <View style={s.panelDiv} />
          <BigStat glyph="⇢" value={paceStr(sec, km)} label="페이스" />
        </Row>

        {/* secondary stats */}
        <View style={s.secondary}>
          <Text style={s.secStat}><Text style={{ color: colors.tang }}>♥</Text> {Math.round(128 + t * 18)} <Text style={s.secUnit}>BPM</Text></Text>
          <Text style={s.secStat}><Text style={{ color: '#f2a33c' }}>▲</Text> {Math.round(t * 164)} <Text style={s.secUnit}>KCAL</Text></Text>
          <Text style={s.secStat}><Text style={{ color: '#9fc3e8' }}>➶</Text> {Math.round(160 + t * 10)} <Text style={s.secUnit}>SPM</Text></Text>
        </View>

        {/* controls — chat is the owner's primary mid-run action, not stopping */}
        <Row style={{ gap: 12, marginTop: 16 }}>
          <Pressable
            style={s.smallCtrl}
            onPress={() => Alert.alert('사진 요청', `${runner.name} 러너에게 사진 요청을 보냈어요 (목업)`)}
          >
            <Text style={{ fontSize: 13, color: '#b8c4ae' }}>▣</Text>
            <Text style={s.ctrlLabel}>사진</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/chat')} style={s.chatBtn}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>러너와 채팅</Text>
          </Pressable>
          <Pressable
            style={s.smallCtrl}
            onPress={() => Alert.alert('휴식 요청', `${runner.name} 러너에게 잠시 휴식을 요청했어요 (목업)`)}
          >
            <Text style={{ fontSize: 13, color: '#b8c4ae' }}>‖</Text>
            <Text style={s.ctrlLabel}>휴식</Text>
          </Pressable>
        </Row>
      </View>

      {/* ---------- stop confirmation sheet ---------- */}
      <Modal visible={stopSheet} transparent animationType="slide" onRequestClose={() => setStopSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setStopSheet(false)} />
        <View style={s.stopSheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 18, fontWeight: '900', color: FOREST }}>정말 러닝을 종료할까요?</Text>
          <Text style={{ fontSize: 12, color: '#5d655d', marginTop: 5, lineHeight: 18 }}>
            러너에게 강제 알림이 가고, 안전하게 정지한 뒤{'\n'}{dog.name}를 데리고 픽업 장소로 복귀해요.
          </Text>

          <Text style={{ fontSize: 12.5, fontWeight: '800', color: FOREST, marginTop: 16, marginBottom: 8 }}>종료 사유</Text>
          {STOP_REASONS.map((r) => (
            <Pressable key={r} onPress={() => setStopReason(r)} style={[s.reasonRow, stopReason === r && { borderColor: '#a9c47e', backgroundColor: '#f4f8ea' }]}>
              <View style={[s.radio, stopReason === r && { borderColor: '#5a7a3c' }]}>
                {stopReason === r && <View style={s.radioDot} />}
              </View>
              <Text style={{ fontSize: 13.5, color: '#3d453d', fontWeight: stopReason === r ? '800' : '500' }}>{r}</Text>
            </Pressable>
          ))}

          <View style={s.feeNote}>
            <Text style={{ fontSize: 11.5, color: '#75806f', lineHeight: 17 }}>
              지금까지 달린 {km.toFixed(1)}km 기준으로 정산돼요.{'\n'}
              최소 기본요금 {'9,900'}원은 결제되며, 러너에게는 잔여 거리 보장이 적용돼요.
            </Text>
          </View>

          <Pressable
            style={[s.stopConfirm, !stopReason && { opacity: 0.4 }]}
            disabled={!stopReason}
            onPress={confirmStop}
          >
            <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#fff' }}>종료 요청 보내기</Text>
          </Pressable>
          <Pressable style={{ alignItems: 'center', paddingVertical: 13 }} onPress={() => setStopSheet(false)}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: '#5d655d' }}>계속 지켜볼게요</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

function BigStat({ glyph, value, unit, label }: { glyph: string; value: string; unit?: string; label: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={{ fontSize: 13, color: '#7a8a6d' }}>{glyph}</Text>
      <Text style={{ fontSize: 27, fontWeight: '900', color: colors.volt, marginTop: 3 }}>
        {value}{unit && <Text style={{ fontSize: 13, color: '#b8c4ae' }}> {unit}</Text>}
      </Text>
      <Text style={{ fontSize: 11, color: '#b8c4ae', marginTop: 2 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  mapRoadH: { position: 'absolute', top: 200, left: 0, right: 0, height: 14, backgroundColor: '#ffffffaa', transform: [{ rotate: '-8deg' }] },
  mapRoadV: { position: 'absolute', top: 0, bottom: 0, right: 90, width: 12, backgroundColor: '#ffffff88', transform: [{ rotate: '12deg' }] },
  mapWater: { position: 'absolute', bottom: 40, right: 20, width: 120, height: 60, borderRadius: 40, backgroundColor: '#cfe0ea', transform: [{ rotate: '-20deg' }] },
  topBar: { position: 'absolute', top: 56, left: 16, right: 16, justifyContent: 'space-between' },
  circleBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  livePill: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 16 },
  courseChip: { position: 'absolute', top: 116, left: 20, backgroundColor: FOREST, borderRadius: 12, paddingVertical: 8, paddingHorizontal: 12 },
  bodycam: {
    position: 'absolute', top: 116, right: 16, width: 128, height: 178, borderRadius: 18,
    borderWidth: 3, borderColor: FOREST, overflow: 'hidden', backgroundColor: '#5d6b47',
  },
  camVisual: { flex: 1, backgroundColor: '#7d8f63' },
  recDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#ff3b30', alignSelf: 'center' },
  liveDot: {
    position: 'absolute', width: 22, height: 22, borderRadius: 11,
    backgroundColor: colors.tang, borderWidth: 4, borderColor: '#fff',
    shadowColor: colors.tang, shadowOpacity: 0.8, shadowRadius: 8, shadowOffset: { width: 0, height: 0 },
  },
  sosBtn: {
    position: 'absolute', right: 20, bottom: 18, width: 46, height: 46, borderRadius: 23,
    backgroundColor: '#e8492a', alignItems: 'center', justifyContent: 'center',
    shadowColor: '#e8492a', shadowOpacity: 0.5, shadowRadius: 10, shadowOffset: { width: 0, height: 3 }, elevation: 6,
  },
  progressStrip: { backgroundColor: '#f6f4ec', paddingHorizontal: 22, paddingVertical: 14 },
  progressTrack: { height: 8, borderRadius: 99, backgroundColor: '#e2dfd2' },
  progressFill: { height: 8, borderRadius: 99, backgroundColor: colors.tang },
  progressDot: { position: 'absolute', top: -5, width: 18, height: 18, borderRadius: 9, backgroundColor: colors.tang, borderWidth: 3, borderColor: '#fff' },
  panel: { flex: 1, backgroundColor: FOREST, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 20, paddingBottom: 30 },
  signalPill: { backgroundColor: '#1d3023', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12, alignSelf: 'center' },
  gearBtn: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#1d3023', alignItems: 'center', justifyContent: 'center' },
  panelDiv: { width: 1, backgroundColor: '#2c4034', marginVertical: 6 },
  secondary: { flexDirection: 'row', justifyContent: 'space-around', backgroundColor: '#1d3023', borderRadius: 14, paddingVertical: 11, marginTop: 16 },
  secStat: { fontSize: 14, fontWeight: '900', color: '#fff' },
  secUnit: { fontSize: 10, color: '#b8c4ae', fontWeight: '600' },
  smallCtrl: { width: 56, height: 52, borderRadius: 18, backgroundColor: '#1d3023', alignItems: 'center', justifyContent: 'center' },
  ctrlLabel: { fontSize: 8, color: '#7a8a6d', marginTop: 2, fontWeight: '700' },
  sheetBackdrop: { flex: 1, backgroundColor: '#00000055' },
  stopSheet: { backgroundColor: '#F6F2E9', borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 22, paddingBottom: 36 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#d8d5c8', marginBottom: 14 },
  reasonRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#fff', borderWidth: 1.4, borderColor: '#eceadf', borderRadius: 14,
    paddingVertical: 12, paddingHorizontal: 14, marginTop: 7,
  },
  radio: { width: 18, height: 18, borderRadius: 9, borderWidth: 2, borderColor: '#d8d5c8', alignItems: 'center', justifyContent: 'center' },
  radioDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: '#5a7a3c' },
  feeNote: { backgroundColor: '#f4f2ea', borderRadius: 12, padding: 12, marginTop: 14 },
  stopConfirm: { backgroundColor: '#e8492a', borderRadius: 16, alignItems: 'center', paddingVertical: 15, marginTop: 14 },
  chatBtn: { flex: 1, backgroundColor: '#1d3023', borderWidth: 1, borderColor: '#2c4034', borderRadius: 99, alignItems: 'center', justifyContent: 'center', paddingVertical: 15 },
  stopBtn: {
    position: 'absolute', right: 20, bottom: 74, width: 40, height: 40, borderRadius: 20,
    backgroundColor: '#00000088', alignItems: 'center', justifyContent: 'center',
  },
});
