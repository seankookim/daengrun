import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { runRequests } from '../../src/store';
import { colors } from '../../src/theme';

// Runner-side active run. Real version: expo-location tracking + camera stream upload.

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

  useEffect(() => {
    if (running) {
      timer.current = setInterval(() => setSec((s) => s + 8), 100); // accelerated demo time
    }
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [running]);

  useEffect(() => {
    if (km >= req.km) {
      setRunning(false);
      router.replace('/runner/done');
    }
  }, [km, req.km]);

  const toggle = () => {
    if (running) {
      router.replace('/runner/done');
    } else {
      setRunning(true);
    }
  };

  return (
    <View style={s.root}>
      <View style={s.topRow}>
        <View style={s.statusBadge}>
          <Text style={{ fontSize: 12, fontWeight: '700', color: colors.volt }}>
            {running ? `● ${req.dogName}와 러닝 중` : `${req.dogName}와 러닝 준비`}
          </Text>
        </View>
        <Text style={{ fontSize: 12, color: '#9a987f' }}>{req.place} 코스 {req.km}km</Text>
      </View>

      <View style={s.center}>
        <Text style={s.distLabel}>DISTANCE</Text>
        <Text style={s.dist}>{km.toFixed(2)}</Text>
        <Text style={{ fontSize: 14, color: '#9a987f', marginTop: 4 }}>km</Text>
        <View style={s.statsRow}>
          <MiniStat value={fmt(sec)} label="시간" />
          <MiniStat value={paceStr(sec, km)} label="페이스" />
          <MiniStat value="132" label="BPM" />
        </View>
      </View>

      <View style={{ flexDirection: 'row', gap: 10 }}>
        <Pressable
          style={[s.btn, { backgroundColor: '#2c3020' }]}
          onPress={() => Alert.alert('전송 완료', '사진이 보호자에게 전송되었습니다 (목업)')}
        >
          <Text style={{ fontSize: 17, fontWeight: '800', color: colors.cream }}>사진 전송</Text>
        </Pressable>
        <Pressable style={[s.btn, { backgroundColor: colors.volt }]} onPress={toggle}>
          <Text style={{ fontSize: 17, fontWeight: '800', color: colors.ink }}>
            {running ? '러닝 종료' : '러닝 시작'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

function MiniStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 28, fontWeight: '900', color: colors.cream }}>{value}</Text>
      <Text style={{ fontSize: 11, color: '#9a987f', marginTop: 2 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.ink, paddingTop: 64, paddingHorizontal: 24, paddingBottom: 30 },
  topRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  statusBadge: { backgroundColor: '#2c3020', borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  distLabel: { fontSize: 12, color: '#9a987f', letterSpacing: 3 },
  dist: { fontSize: 84, fontWeight: '900', color: colors.volt, lineHeight: 92 },
  statsRow: { flexDirection: 'row', gap: 40, marginTop: 30 },
  btn: { flex: 1, borderRadius: 16, padding: 17, alignItems: 'center' },
});
