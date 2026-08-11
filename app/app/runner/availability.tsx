import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { AvailRule, fetchMyAvailability, saveMyAvailability } from '../../src/lib/api';
import { useNumFont } from '../../src/lib/fonts';
import { layout, paper } from '../../src/theme';

// 가용시간 설정 — 실편집기. runner_availability_rules 실저장.
// 반영 지점: 러너 공개 프로필 슬롯 그리드 · 보호자 예약 슬롯 시트 · 서버 is_slot_available.
// v1: 요일당 1구간, 30분 단위. 다구간·예외일정·예약규칙은 v2.
//
// [paper repaint 2026-08-11] cream/forest/volt legacy scrapped → paper chrome.
// Behavior frozen: load/mutate/bump/applyToAll/save, 30-min clamps, dirty gate, sticky
// save bar. §3b applied: day toggle = explicit ink/canvas chip (no tint pill), stepper
// values Oswald with lineHeight 25 (BUG A), save = PaperBtn (busy label swap, no opacity),
// 예약 규칙 placeholder rows lose the 0.55 opacity trick — muted state is explicit dim ink.

const CORAL_INK = '#C6472C'; // reading coral — text links (paper.line fails the 4.5:1 text floor)
const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const DAY_NAME = '일월화수목금토';

interface DayState { enabled: boolean; startMin: number; endMin: number }
const DEFAULT_DAY: DayState = { enabled: false, startMin: 360, endMin: 1320 };

const fmtMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

export default function Availability() {
  const nf = useNumFont(); // Oswald — stepper time values
  const [days, setDays] = useState<DayState[]>(Array.from({ length: 7 }, () => ({ ...DEFAULT_DAY })));
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);

  // [honesty P1 2026-08-11] A failed load used to setLoaded(true) and render the
  // default all-쉬는날 grid as if it were the runner's saved rules — one 저장하기
  // tap then overwrote the real server rules with an empty set. Failure now
  // renders as failure, and the save bar only mounts after a real load succeeded.
  const load = useCallback(() => {
    setLoadErr(false);
    fetchMyAvailability()
      .then((rules) => {
        const next = Array.from({ length: 7 }, () => ({ ...DEFAULT_DAY }));
        rules.forEach((r) => { next[r.weekday] = { enabled: true, startMin: r.startMin, endMin: r.endMin }; });
        setDays(next);
        setLoaded(true);
      })
      .catch((e) => { console.warn('[avail] load:', e?.message ?? e); setLoadErr(true); });
  }, []);
  useEffect(() => { load(); }, [load]);

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
    if (!loaded) return; // hard guard — never write from a grid the server didn't seed
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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 56, paddingBottom: 120 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 22, fontWeight: '900', color: paper.ink }}>가용시간 설정</Text>
          <View style={{ width: 40 }} />
        </Row>
        <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, textAlign: 'center', marginBottom: 16 }}>
          설정한 시간에만 요청을 받아요 · 주 {activeCount}일 러닝
        </Text>

        {!loaded && !loadErr && (
          <View style={s.card}><Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', paddingVertical: 10 }}>불러오는 중...</Text></View>
        )}

        {/* loud-fail strip — criticalWash bg + critical ink (never shares paper.line) + retry */}
        {!loaded && loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>저장된 가용시간을 불러오지 못했어요</Text>
            <Text style={{ fontSize: 14, lineHeight: 19, color: paper.critical, marginTop: 3 }}>
              불러오기 전에는 편집과 저장을 열지 않아요 — 기존 설정을 지우지 않기 위해서예요
            </Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>다시 시도</Text>
            </Pressable>
          </View>
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
                        <Text style={{ width: 24, fontSize: 17, fontWeight: '900', color: d.enabled ? paper.ink : '#BBBBBB' }}>
                          {DAY_NAME[wd]}
                        </Text>
                        {/* day toggle — explicit state colors (§3b, no tint-pill legacy):
                            on = ink fill + white label · off = canvas + neutral border + dim */}
                        <Pressable
                          onPress={() => mutate(wd, { enabled: !d.enabled })}
                          style={({ pressed }) => [s.toggleChip, d.enabled ? s.toggleChipOn : s.toggleChipOff, pressed && { transform: [{ scale: 0.96 }] }]}
                          accessibilityRole="switch"
                          accessibilityState={{ checked: d.enabled }}
                        >
                          <Text style={{ fontSize: 14.5, fontWeight: '800', color: d.enabled ? '#FFFFFF' : paper.dim }}>
                            {d.enabled ? '가능' : '쉬는 날'}
                          </Text>
                        </Pressable>
                      </Row>
                      {d.enabled && (
                        <Pressable onPress={() => applyToAll(wd)} hitSlop={8}>
                          <Text style={{ fontSize: 14, fontWeight: '800', color: CORAL_INK }}>전체 적용</Text>
                        </Pressable>
                      )}
                    </Row>
                    {d.enabled && (
                      <Row style={{ gap: 8, marginTop: 10, justifyContent: 'center' }}>
                        <Stepper value={fmtMin(d.startMin)} nf={nf} onMinus={() => bump(wd, 'startMin', -30)} onPlus={() => bump(wd, 'startMin', 30)} />
                        <Text style={{ fontSize: 16, color: paper.dim, alignSelf: 'center' }}>—</Text>
                        <Stepper value={fmtMin(d.endMin)} nf={nf} onMinus={() => bump(wd, 'endMin', -30)} onPlus={() => bump(wd, 'endMin', 30)} />
                      </Row>
                    )}
                  </View>
                </View>
              );
            })}
          </View>
        )}

        <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 14, lineHeight: 19 }}>
          30분 단위 · 요일당 1구간 (다구간·휴가 등 예외 일정은 준비 중){'\n'}
          변경 사항은 내 공개 프로필과 보호자 예약 화면에 즉시 반영돼요
        </Text>

        {/* 예약 규칙 — server wiring pending, so the section says so in its title and the rows
            render in explicit muted ink (the 0.55-opacity paint retired with the paper repaint) */}
        <Row style={s.secWrap}>
          <Text style={s.secTitle}>예약 규칙 (준비 중)</Text>
        </Row>
        <View style={s.card}>
          {[['최소 통보 시간', '2시간 전'], ['하루 최대 세션', '4건'], ['세션 후 휴식', '30분']].map(([label, value], i) => (
            <View key={label}>
              {i > 0 && <View style={s.div} />}
              <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
                <Text style={{ fontSize: 14.5, color: paper.dim }}>{label}</Text>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: paper.dim }}>{value}</Text>
              </Row>
            </View>
          ))}
        </View>
      </ScrollView>

      {/* sticky save — PaperBtn matrix: busy = label swap, saved = explicit disabledFill.
          Mounts ONLY after a real load: saving an unseeded grid would wipe server rules. */}
      {loaded && (
        <View style={s.saveBar}>
          <PaperBtn
            label={dirty ? '저장하기' : '저장됨 ✓'}
            busyLabel="저장 중..."
            busy={saving}
            disabled={!dirty}
            onPress={save}
          />
        </View>
      )}
    </View>
  );
}

function Stepper({ value, nf, onMinus, onPlus }: { value: string; nf: TextStyle | null; onMinus: () => void; onPlus: () => void }) {
  return (
    <Row style={s.stepper}>
      <Pressable onPress={onMinus} style={s.stepBtn} accessibilityRole="button" accessibilityLabel="30분 빼기">
        <Text style={s.stepBtnText}>−</Text>
      </Pressable>
      <View style={{ paddingHorizontal: 12, justifyContent: 'center' }}>
        {/* Oswald time value — lineHeight 25 = 1.28× (BUG A) */}
        <Text style={[{ fontSize: 19.5, lineHeight: 25, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{value}</Text>
      </View>
      <Pressable onPress={onPlus} style={s.stepBtn} accessibilityRole="button" accessibilityLabel="30분 더하기">
        <Text style={s.stepBtnText}>＋</Text>
      </Pressable>
    </Row>
  );
}

const s = StyleSheet.create({
  // paper back button grammar — 40×40 square, canvas, 1px coral
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  card: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', paddingHorizontal: 14, paddingVertical: 6 },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 40, justifyContent: 'center', paddingHorizontal: 14, borderWidth: 1, borderColor: paper.ink, backgroundColor: paper.canvas },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  toggleChip: { paddingVertical: 8, paddingHorizontal: 15, borderRadius: 0 },
  toggleChipOn: { backgroundColor: paper.ink },
  toggleChipOff: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' },
  stepper: { gap: 0, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' },
  stepBtn: { width: 46, height: 46, alignItems: 'center', justifyContent: 'center' },
  stepBtnText: { fontSize: 22, fontWeight: '800', color: paper.ink },
  // §3b section header — full-bleed coral rule (negative gutter margins) + 20/800 ink title
  secWrap: {
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter,
    borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10, marginTop: 22, marginBottom: 10,
  },
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
  saveBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    paddingHorizontal: layout.gutter, paddingTop: 10, paddingBottom: 30,
    borderTopWidth: 1, borderTopColor: paper.line,
  },
});
