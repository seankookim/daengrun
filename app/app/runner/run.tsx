import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { payoutFor, runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

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
  const req = runRequests[0];
  const [running, setRunning] = useState(false);
  const [sec, setSec] = useState(0);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  const km = Math.min(sec / 409, req.km + 0.02); // ~6'49" pace, demo-accelerated
  const remaining = Math.max(req.km - km, 0);
  const progress = Math.min(km / req.km, 1);

  useEffect(() => {
    if (running) {
      timer.current = setInterval(() => setSec((s) => s + 8), 100); // accelerated demo time
    }
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [running]);

  const finish = (completed: boolean) => {
    Object.assign(runResult, { km, sec, payout: payoutFor(km), completed });
    router.replace('/runner/done');
  };

  useEffect(() => {
    if (km >= req.km) {
      setRunning(false);
      Object.assign(runResult, { km, sec, payout: payoutFor(km), completed: true });
      router.replace('/runner/done');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [km >= req.km]);

  return (
    <View style={s.root}>
      {/* 코스 맵 placeholder */}
      <View style={s.mapArea}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 16 }}>
          <View style={s.statusBadge}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: colors.volt }}>
              {running ? `● ${req.dogName}와 러닝 중` : `${req.dogName}와 러닝 준비`}
            </Text>
          </View>
          <View style={s.camStatus}>
            <View style={[s.recDot, !running && { backgroundColor: '#8a8877' }]} />
            <Text style={s.camText}>{running ? 'REC · 보호자 시청 중' : '카메라 대기'} · 배터리 82%</Text>
          </View>
        </Row>

        <View style={s.trackWrap}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 8 }}>
            <Text style={{ fontSize: 12, color: colors.dim }}>{req.place} 코스 · {req.km}km</Text>
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
          onPress={() => Alert.alert('채팅', `${req.dogName} 보호자님과의 채팅 (목업)`)}
        >
          <Monogram char={req.dogChar} bg={req.dogColor} size={36} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: colors.cream }}>{req.dogName} 보호자님</Text>
            <Text style={{ fontSize: 11, color: '#8fa0b3' }} numberOfLines={1}>
              "자전거도로만 피해주시면 돼요!"
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
          <Text style={{ fontSize: 12, color: '#8fa0b3' }}>
            현재 예상 수익 <Text style={{ color: colors.volt, fontWeight: '800' }}>{payoutFor(km).toLocaleString()}원</Text> · 완주 시 {payoutFor(req.km + 0.02).toLocaleString()}원
          </Text>
        </Row>

        <View style={{ flexDirection: 'row', gap: 10 }}>
          <Pressable
            style={[s.btn, { backgroundColor: '#212b38' }]}
            onPress={() => Alert.alert('전송 완료', '사진이 보호자에게 전송되었습니다 (목업)')}
          >
            <Text style={{ fontSize: 16, fontWeight: '800', color: colors.cream }}>사진 전송</Text>
          </Pressable>
          <Pressable
            style={[s.btn, { backgroundColor: colors.volt }]}
            onPress={() => (running ? finish(false) : setRunning(true))}
          >
            <Text style={{ fontSize: 16, fontWeight: '800', color: colors.ink }}>
              {running ? '러닝 종료' : '러닝 시작'}
            </Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}

function MiniStat({ value, label, big }: { value: string; label: string; big?: boolean }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: big ? 44 : 28, fontWeight: '900', color: big ? colors.volt : colors.cream }}>
        {value}
      </Text>
      <Text style={{ fontSize: 11, color: '#8fa0b3', marginTop: 2 }}>{label}</Text>
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
    backgroundColor: '#212b38', borderRadius: 16, padding: 12,
  },
  btn: { flex: 1, borderRadius: 16, padding: 16, alignItems: 'center' },
});
