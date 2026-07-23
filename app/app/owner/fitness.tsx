import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ring } from '../../src/components/ring';
import { Row } from '../../src/components/ui';
import { fetchFitness, Fitness, updateDogGoal } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 체력 리포트 — 모프 링의 도착지. 브랜드의 심장: 반려견 피트니스.
// 주간 링 · 8주 추이 · 체력 나이 · 주간 목표 편집(실저장 → 홈 링 즉시 반영) · 최근 러닝 → 리포트.

const FOREST = '#132117';
const FOREST_INNER = '#1d3023';

const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');

export default function FitnessHub() {
  const [fit, setFit] = useState<Fitness | null>(null);
  const [savingGoal, setSavingGoal] = useState(false);

  const load = () => fetchFitness().then(setFit).catch((e) => console.warn('[fitness]:', e?.message ?? e));
  useFocusEffect(useCallback(() => { load(); }, []));

  const bumpGoal = async (delta: number) => {
    if (!fit?.dogId || savingGoal) return;
    const next = Math.min(50, Math.max(3, Math.round(fit.goalKm + delta)));
    if (next === fit.goalKm) return;
    setSavingGoal(true);
    const prev = fit.goalKm;
    setFit({ ...fit, goalKm: next }); // 낙관적 반영
    try {
      await updateDogGoal(fit.dogId, next);
    } catch (e) {
      setFit((f) => (f ? { ...f, goalKm: prev } : f));
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSavingGoal(false);
    }
  };

  const pct = fit ? Math.min(fit.weekKm / fit.goalKm, 1) : 0;
  const maxWeek = fit ? Math.max(...fit.weeks.map((w) => w.km), fit.goalKm * 0.6, 1) : 1;

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>체력 리포트</Text>
          <View style={{ width: 40 }} />
        </Row>

        {/* ---------- weekly ring hero ---------- */}
        <View style={s.hero}>
          <Text style={{ fontSize: 12, color: '#b8c4ae' }}>{fit?.dogName ?? '반려견'}의 이번 주</Text>
          <View style={{ alignItems: 'center', marginTop: 10 }}>
            <Ring pct={pct} size={190} trackColor="#233827">
              <View style={{ alignItems: 'center' }}>
                <Text style={{ fontSize: 40, fontWeight: '900', color: colors.tang, lineHeight: 44 }}>
                  {fit?.weekKm ?? 0}
                  <Text style={{ fontSize: 15, color: '#b8c4ae' }}> km</Text>
                </Text>
                <Text style={{ fontSize: 12.5, color: colors.volt, marginTop: 2 }}>/ {fit?.goalKm ?? '—'}km 목표</Text>
                <Text style={{ fontSize: 11, color: '#b8c4ae', marginTop: 4 }}>{Math.round(pct * 100)}% 달성</Text>
              </View>
            </Ring>
          </View>
          <Row style={{ marginTop: 14, backgroundColor: FOREST_INNER, borderRadius: 14, paddingVertical: 12, justifyContent: 'space-around' }}>
            <HeroStat value={`${fit?.weekRuns ?? 0}회`} label="이번 주 러닝" />
            <View style={s.heroDiv} />
            <HeroStat value={fmtPace(fit?.avgPaceSec ?? null)} label="평균 페이스" />
            <View style={s.heroDiv} />
            <HeroStat value={`${fit?.streakDays ?? 0}일`} label="연속 기록" />
          </Row>
        </View>

        {/* ---------- 체력 나이 ---------- */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={s.cardTitle}>체력 나이</Text>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>
                꾸준한 러닝이 체력 나이를 젊게 유지해요
              </Text>
            </View>
            <Text style={{ fontSize: 28, fontWeight: '900', color: colors.tang }}>
              {fit?.fitnessAge != null ? `${fit.fitnessAge}살` : '측정 전'}
            </Text>
          </Row>
          {fit?.fitnessAge == null && (
            <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 8 }}>
              러닝이 쌓이면 수의학 공식 기반으로 산출돼요 (준비 중)
            </Text>
          )}
        </View>

        {/* ---------- 주간 목표 편집 ---------- */}
        <View style={s.card}>
          <Text style={s.cardTitle}>주간 목표</Text>
          <Row style={{ justifyContent: 'space-between', marginTop: 8 }}>
            <Pressable onPress={() => bumpGoal(-1)} style={s.goalBtn}><Text style={s.goalBtnText}>−</Text></Pressable>
            <View style={{ alignItems: 'center' }}>
              <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>{fit?.goalKm ?? '—'}km</Text>
              <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 2 }}>홈 화면 링에 바로 반영돼요</Text>
            </View>
            <Pressable onPress={() => bumpGoal(1)} style={s.goalBtn}><Text style={s.goalBtnText}>＋</Text></Pressable>
          </Row>
        </View>

        {/* ---------- 8주 추이 ---------- */}
        <View style={s.card}>
          <Text style={s.cardTitle}>최근 8주</Text>
          <Row style={{ alignItems: 'flex-end', gap: 6, height: 110, marginTop: 10 }}>
            {(fit?.weeks ?? []).map((w, i) => {
              const h = Math.max((w.km / maxWeek) * 92, w.km > 0 ? 8 : 3);
              const isNow = i === 7;
              return (
                <View key={w.label} style={{ flex: 1, alignItems: 'center' }}>
                  <Text style={{ fontSize: 8.5, color: colors.dim, marginBottom: 3 }}>{w.km > 0 ? w.km : ''}</Text>
                  <View style={{ width: '68%', height: h, borderRadius: 6, backgroundColor: isNow ? colors.volt : '#dde8d4' }} />
                  <Text style={{ fontSize: 8, color: isNow ? '#4a6d1f' : colors.dim, marginTop: 4, fontWeight: isNow ? '800' : '400' }}>
                    {isNow ? '이번주' : `${7 - i}주`}
                  </Text>
                </View>
              );
            })}
          </Row>
        </View>

        {/* ---------- 최근 러닝 → 리포트 ---------- */}
        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 8 }}>최근 러닝</Text>
        {(fit?.recent ?? []).length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 }}>
              아직 완료된 러닝이 없어요{'\n'}첫 러닝을 예약하면 여기부터 채워져요
            </Text>
          </View>
        )}
        {(fit?.recent ?? []).map((r) => (
          <Pressable
            key={r.bookingId}
            onPress={() => router.push({ pathname: '/owner/report', params: { bid: r.bookingId } })}
            style={s.runRow}
          >
            <View style={s.runRail} />
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 13.5, fontWeight: '800', color: FOREST }}>{r.when}</Text>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>
                {r.km}km · {Math.floor(r.durationSec / 60)}분 · 리포트 보기 ›
              </Text>
            </View>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#5a7a3c' }}>{r.km}km</Text>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

function HeroStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>{value}</Text>
      <Text style={{ fontSize: 10, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  hero: { backgroundColor: FOREST, borderRadius: 22, padding: 18, marginTop: 18 },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 12 },
  cardTitle: { fontSize: 13.5, fontWeight: '900', color: FOREST },
  goalBtn: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  goalBtnText: { fontSize: 20, fontWeight: '900', color: '#4a6d1f' },
  emptyBox: { backgroundColor: '#f4f2ea', borderRadius: 16, padding: 22, alignItems: 'center' },
  runRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: '#fff',
    borderRadius: 16, padding: 13, borderWidth: 1, borderColor: '#eceadf', marginBottom: 8,
  },
  runRail: { width: 4, height: 34, borderRadius: 2, backgroundColor: '#5a7a3c' },
});
