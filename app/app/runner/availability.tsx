import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { AvailRule, fetchMyAvailability, saveMyAvailability } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 가용시간 설정 — 실편집기. runner_availability_rules 실저장.
// 반영 지점: 러너 공개 프로필 슬롯 그리드 · 보호자 예약 슬롯 시트 · 서버 is_slot_available.
// v1: 요일당 1구간, 30분 단위. 다구간·예외일정·예약규칙은 v2.

const FOREST = '#132117';
const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const DAY_NAME = '일월화수목금토';

interface DayState { enabled: boolean; startMin: number; endMin: number }
const DEFAULT_DAY: DayState = { enabled: false, startMin: 360, endMin: 1320 };

const fmtMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

export default function Availability() {
  const [days, setDays] = useState<DayState[]>(Array.from({ length: 7 }, () => ({ ...DEFAULT_DAY })));
  const [loaded, setLoaded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    fetchMyAvailability()
      .then((rules) => {
        const next = Array.from({ length: 7 }, () => ({ ...DEFAULT_DAY }));
        rules.forEach((r) => { next[r.weekday] = { enabled: true, startMin: r.startMin, endMin: r.endMin }; });
        setDays(next);
        setLoaded(true);
      })
      .catch((e) => { console.warn('[avail] load:', e?.message ?? e); setLoaded(true); });
  }, []);

  const mutate = (wd: number, patch: Partial<DayState>) => {
    setDays((ds) => ds.map((d, i) => (i === wd ? { ...d, ...patch } : d)));
    setDirty(true);
  };

  const bump = (wd: number, field: 'startMin' | 'endMin', delta: number) => {
    const d = days[wd];
    if (field === 'startMin') {
      mutate(wd, { startMin: Math.min(Math.max(d.startMin + delta, 300), d.endMin - 60) });
    } else {
      mutate(wd, { endMin: Math.min(Math.max(d.endMin + delta, d.startMin + 60), 1440) });
    }
  };

  const applyToAll = (srcWd: number) => {
    const src = days[srcWd];
    setDays((ds) => ds.map((d) => (d.enabled ? { ...d, startMin: src.startMin, endMin: src.endMin } : d)));
    setDirty(true);
  };

  const save = async () => {
    setSaving(true);
    try {
      const rules: AvailRule[] = days
        .map((d, wd) => ({ weekday: wd, startMin: d.startMin, endMin: d.endMin, enabled: d.enabled }))
        .filter((d) => d.enabled)
        .map(({ weekday, startMin, endMin }) => ({ weekday, startMin, endMin }));
      await saveMyAvailability(rules);
      setDirty(false);
      Alert.alert('저장 완료', '보호자 예약 화면과 내 공개 프로필에 바로 반영됐어요');
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  const activeCount = days.filter((d) => d.enabled).length;

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 120 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>가용시간 설정</Text>
          <View style={{ width: 40 }} />
        </Row>
        <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginBottom: 16 }}>
          설정한 시간에만 요청을 받아요 · 주 {activeCount}일 러닝
        </Text>

        {!loaded && (
          <View style={s.card}><Text style={{ fontSize: 12.5, color: colors.dim, textAlign: 'center', paddingVertical: 10 }}>불러오는 중...</Text></View>
        )}

        {loaded && (
          <View style={s.card}>
            {DAY_ORDER.map((wd, i) => {
              const d = days[wd];
              return (
                <View key={wd}>
                  {i > 0 && <View style={s.div} />}
                  <View style={{ paddingVertical: 11 }}>
                    <Row style={{ justifyContent: 'space-between' }}>
                      <Row style={{ gap: 10 }}>
                        <Text style={{ width: 24, fontSize: 15, fontWeight: '900', color: d.enabled ? FOREST : '#b3b3ab' }}>
                          {DAY_NAME[wd]}
                        </Text>
                        <Pressable
                          onPress={() => mutate(wd, { enabled: !d.enabled })}
                          style={[s.togglePill, d.enabled && { backgroundColor: '#e3f0c4' }]}
                        >
                          <Text style={{ fontSize: 11, fontWeight: '800', color: d.enabled ? '#3d5a2b' : '#8a8877' }}>
                            {d.enabled ? '가능' : '쉬는 날'}
                          </Text>
                        </Pressable>
                      </Row>
                      {d.enabled && (
                        <Pressable onPress={() => applyToAll(wd)}>
                          <Text style={{ fontSize: 10.5, fontWeight: '700', color: '#5a7a3c' }}>⧉ 전체 적용</Text>
                        </Pressable>
                      )}
                    </Row>
                    {d.enabled && (
                      <Row style={{ gap: 8, marginTop: 10, justifyContent: 'center' }}>
                        <Stepper value={fmtMin(d.startMin)} onMinus={() => bump(wd, 'startMin', -30)} onPlus={() => bump(wd, 'startMin', 30)} />
                        <Text style={{ fontSize: 14, color: colors.dim, alignSelf: 'center' }}>—</Text>
                        <Stepper value={fmtMin(d.endMin)} onMinus={() => bump(wd, 'endMin', -30)} onPlus={() => bump(wd, 'endMin', 30)} />
                      </Row>
                    )}
                  </View>
                </View>
              );
            })}
          </View>
        )}

        <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 14, lineHeight: 15 }}>
          30분 단위 · 요일당 1구간 (다구간·휴가 등 예외 일정은 준비 중){'\n'}
          변경 사항은 내 공개 프로필과 보호자 예약 화면에 즉시 반영돼요
        </Text>

        {/* 예약 규칙 — 서버 반영 전이므로 준비 중 표기 */}
        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 22, marginBottom: 10 }}>예약 규칙 (준비 중)</Text>
        <View style={[s.card, { opacity: 0.55 }]}>
          {[['최소 통보 시간', '2시간 전'], ['하루 최대 세션', '4건'], ['세션 후 휴식', '30분']].map(([label, value], i) => (
            <View key={label}>
              {i > 0 && <View style={s.div} />}
              <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
                <Text style={{ fontSize: 13.5, color: '#3d453d' }}>{label}</Text>
                <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>{value}</Text>
              </Row>
            </View>
          ))}
        </View>
      </ScrollView>

      {/* sticky save */}
      <View style={s.saveBar}>
        <Pressable onPress={save} disabled={saving || !dirty} style={[s.saveBtn, (!dirty || saving) && { opacity: 0.45 }]}>
          <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>
            {saving ? '저장 중...' : dirty ? '저장하기' : '저장됨 ✓'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

function Stepper({ value, onMinus, onPlus }: { value: string; onMinus: () => void; onPlus: () => void }) {
  return (
    <Row style={{ gap: 0, backgroundColor: '#f4f2ea', borderRadius: 12, overflow: 'hidden' }}>
      <Pressable onPress={onMinus} style={s.stepBtn}><Text style={s.stepBtnText}>−</Text></Pressable>
      <View style={{ paddingHorizontal: 12, justifyContent: 'center' }}>
        <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{value}</Text>
      </View>
      <Pressable onPress={onPlus} style={s.stepBtn}><Text style={s.stepBtnText}>＋</Text></Pressable>
    </Row>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#dedacb' },
  card: { backgroundColor: '#fff', borderRadius: 18, paddingHorizontal: 16, paddingVertical: 6, borderWidth: 1, borderColor: '#dedacb' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  togglePill: { backgroundColor: '#f0efe8', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 15 },
  stepBtn: { width: 46, height: 46, alignItems: 'center', justifyContent: 'center' },
  stepBtnText: { fontSize: 20, fontWeight: '900', color: '#5a7a3c' },
  saveBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: colors.cream,
    paddingHorizontal: 12, paddingTop: 10, paddingBottom: 30, borderTopWidth: 1, borderTopColor: '#dedacb',
  },
  saveBtn: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 15 },
});
