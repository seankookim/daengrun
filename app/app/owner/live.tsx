import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { dog, draft, runners } from '../../src/store';
import { colors } from '../../src/theme';

// Simulated live run. Real version: expo-location on runner device →
// Supabase realtime → map (react-native-maps) + bodycam stream.

const TOTAL_SEC = 2052; // 34:12
const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

export default function Live() {
  const [t, setT] = useState(0); // 0..1 progress
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const runner = runners.find((r) => r.id === draft.runnerId) ?? runners[0];

  useEffect(() => {
    timer.current = setInterval(() => {
      setT((prev) => {
        if (prev >= 1) return 1;
        return Math.min(prev + 0.004, 1);
      });
    }, 80);
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

  return (
    <View style={s.root}>
      {/* 지도 자리 — react-native-maps 붙이기 전 placeholder */}
      <View style={s.mapArea}>
        <Row style={s.topRow}>
          <Pressable onPress={() => router.back()} style={s.backBtn}>
            <Text style={{ fontSize: 20 }}>‹</Text>
          </Pressable>
          <View style={s.liveBadge}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: colors.volt }}>
              {t >= 1 ? '러닝 완료!' : `● LIVE · ${dog.name}가 달리는 중`}
            </Text>
          </View>
        </Row>

        {/* 바디캠 PIP placeholder */}
        <View style={s.bodycam}>
          <View style={s.recRow}>
            <View style={s.recDot} />
            <Text style={s.recText}>REC</Text>
          </View>
          <Text style={s.camLabel}>러너 바디캠</Text>
        </View>

        {/* 진행률 트랙 */}
        <View style={s.trackWrap}>
          <Text style={{ fontSize: 12, color: colors.dim, marginBottom: 8 }}>서울숲 코스 · {draft.km}km</Text>
          <View style={s.track}>
            <View style={[s.trackFill, { width: `${t * 100}%` }]} />
            <View style={[s.trackDot, { left: `${Math.max(t * 100 - 2, 0)}%` }]} />
          </View>
        </View>
      </View>

      <View style={s.liveBar}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Row style={{ gap: 10 }}>
            <Monogram char={runner.char} bg={runner.color} size={40} />
            <View>
              <Text style={{ fontSize: 14, fontWeight: '700', color: colors.cream }}>{runner.name} 러너</Text>
              <Text style={{ fontSize: 11, color: '#9a987f' }}>{dog.name}와 러닝 중</Text>
            </View>
          </Row>
          <Pressable style={s.chatBtn}>
            <Text style={{ fontSize: 12, color: colors.volt }}>채팅</Text>
          </Pressable>
        </Row>
        <View style={{ height: 1, backgroundColor: '#33371f', marginVertical: 14 }} />
        <Row style={{ justifyContent: 'space-around' }}>
          <Stat value={km.toFixed(1)} label="킬로미터" />
          <Stat value={fmt(sec)} label="시간" />
          <Stat value={paceStr(sec, km)} label="페이스" />
        </Row>
      </View>
    </View>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 26, fontWeight: '900', color: colors.volt }}>{value}</Text>
      <Text style={{ fontSize: 10, color: '#9a987f', marginTop: 2 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#e7e9dc' },
  mapArea: { flex: 1, paddingTop: 56 },
  topRow: { justifyContent: 'space-between', paddingHorizontal: 16 },
  backBtn: { backgroundColor: '#fff', borderRadius: 12, paddingVertical: 6, paddingHorizontal: 12 },
  liveBadge: { backgroundColor: colors.ink, borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14 },
  bodycam: {
    position: 'absolute', top: 112, right: 16, width: 118, height: 158,
    borderRadius: 16, borderWidth: 3, borderColor: colors.ink,
    backgroundColor: '#6b7a52', padding: 8, justifyContent: 'space-between',
  },
  recRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  recDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#ff3b30' },
  recText: { fontSize: 9, fontWeight: '700', color: '#fff', letterSpacing: 1 },
  camLabel: { fontSize: 9, color: '#fff' },
  trackWrap: { position: 'absolute', left: 20, right: 20, bottom: 24 },
  track: { height: 10, borderRadius: 99, backgroundColor: '#d5d8c6', overflow: 'visible' },
  trackFill: { height: 10, borderRadius: 99, backgroundColor: colors.tang },
  trackDot: {
    position: 'absolute', top: -4, width: 18, height: 18, borderRadius: 9,
    backgroundColor: colors.tang, borderWidth: 3, borderColor: '#fff',
  },
  liveBar: { backgroundColor: colors.ink, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 20, paddingBottom: 34 },
  chatBtn: { borderWidth: 1, borderColor: '#3a3e2c', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 14 },
});
