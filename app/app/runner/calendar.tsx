import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { fetchRunnerJobs, RunnerJob } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { runnerJob } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 캘린더 — C1(출발 보드) × C2(티켓 스택) 머지 (Sean 확정, 2026-07-29, hi-club-plan §1-B).
// C1에서: 다크 출발 보드 톱 위젯 — 스플릿-플랩 예상 수익 카운터 + 확정 건수 + 상태 오벌.
// C2에서: 작업 행 = 절취선 티켓 (우측 스터브에 실수령/예상 금액), 완료 티켓엔 FINISHER 도장.
// 수익은 전부 실데이터 (fetchRunnerJobs — 완료 건은 ledger 실 net, 그 외 티어 요율 견적).

const FOREST = '#0F1D13';

const JOB_STATUS: Record<RunnerJob['status'], { label: string; bg: string; fg: string }> = {
  confirmed: { label: '확정', bg: '#e3f0c4', fg: '#3d5a2b' },
  in_progress: { label: '진행 중', bg: '#eaf7c8', fg: '#4a6d1f' },
  completed: { label: '완료', bg: '#E3EEF8', fg: '#4A6E93' },
};

// "7월 29일 (화) 오후 7:00" → { day: '7월 29일 (화) 오후', time: '7:00' } (러너 홈과 동일 분리)
const splitWhen = (when: string): { day: string; time: string } => {
  const i = when.lastIndexOf(' ');
  return i < 0 ? { day: when, time: '' } : { day: when.slice(0, i), time: when.slice(i + 1) };
};

export default function RunnerCalendar() {
  const df = useDisplayFont();
  const [jobs, setJobs] = useState<RunnerJob[]>([]);

  const load = () => fetchRunnerJobs().then(setJobs).catch((e) => console.warn('[calendar] jobs:', e?.message ?? e));
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const openJob = (j: RunnerJob) => {
    if (j.status === 'completed') {
      Alert.alert('완료된 러닝', `${j.dogName} · ${j.km}km · +${j.payout.toLocaleString()}원\n수익 탭에서 정산 내역을 확인하세요`);
      return;
    }
    runnerJob.bookingId = j.bookingId;
    // active(러닝 중)만 러닝 화면으로 — picked_up(인계 완료)은 미트업의 '러닝 시작하기' 단계로
    router.push(j.rawStatus === 'active' ? '/runner/run' : '/runner/meetup');
  };

  const upcoming = jobs.filter((j) => j.status !== 'completed');
  const expected = upcoming.reduce((sum, j) => sum + j.payout, 0);
  const flapChars = `+${expected.toLocaleString()}`.split('');

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Text style={[{ fontSize: 30, fontWeight: '900', color: FOREST }, df]}>캘린더</Text>
          <Pressable onPress={() => router.push('/runner/availability')} style={s.availBtn}>
            <Text style={{ fontSize: 13, fontWeight: '800', color: '#fff' }}>가용시간 설정</Text>
          </Pressable>
        </Row>

        {/* ---------- 출발 보드 (C1) — 예상 수익 스플릿-플랩 ---------- */}
        <View style={s.board}>
          <Text style={[{ fontSize: 19, fontWeight: '900', color: '#fff' }, df]}>나의 출발</Text>
          <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 3 }}>
            확정 {upcoming.length}건{upcoming.length > 0 ? ' · 다음 러닝까지 준비 완료' : ' — 요청 탭에서 수락해보세요'}
          </Text>
          {upcoming.length > 0 && (
            <Row style={{ gap: 4, marginTop: 12, alignItems: 'flex-end' }}>
              {flapChars.map((c, i) => (
                <View key={i} style={[s.flap, (c === ',' || c === '+') && s.flapThin]}>
                  <Text style={{ fontSize: 20, fontWeight: '900', color: colors.volt, fontVariant: ['tabular-nums'] }}>{c}</Text>
                </View>
              ))}
              <Text style={{ fontSize: 13, color: '#8fa093', paddingBottom: 5, marginLeft: 3 }}>원 예상</Text>
            </Row>
          )}
        </View>

        {/* ---------- 티켓 스택 (C2) ---------- */}
        {jobs.length === 0 && (
          <View style={s.emptyJobs}>
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 22 }}>
              확정된 작업이 아직 없어요{'\n'}요청 탭에서 새 요청을 수락해보세요
            </Text>
            <Pressable onPress={() => router.push('/runner/requests')} style={s.emptyBtn}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>요청 보러 가기 ›</Text>
            </Pressable>
          </View>
        )}

        <View style={{ marginTop: 16 }}>
          {jobs.map((j) => {
            const st = JOB_STATUS[j.status];
            const { day, time } = splitWhen(j.when);
            const done = j.status === 'completed';
            return (
              <Pressable key={j.bookingId} onPress={() => openJob(j)} style={[s.ticket, done && { opacity: 0.82 }]}>
                {/* 본문 */}
                <View style={{ flex: 1, padding: 13, paddingRight: 10 }}>
                  <Row style={{ gap: 7, alignItems: 'baseline' }}>
                    <Text style={{ fontSize: 21, fontWeight: '900', color: FOREST, fontVariant: ['tabular-nums'] }}>{time}</Text>
                    <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#75806f', flex: 1 }} numberOfLines={1}>{day}</Text>
                    <View style={[s.oval, { backgroundColor: st.bg }]}>
                      <Text style={{ fontSize: 11, fontWeight: '800', color: st.fg }}>{st.label}</Text>
                    </View>
                  </Row>
                  <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST, marginTop: 4 }}>
                    {j.dogName} · {j.km}km 러닝
                  </Text>
                  <Text style={{ fontSize: 13.5, color: colors.dim, marginTop: 2 }}>
                    {j.status === 'confirmed' ? '탭하여 픽업 진행 ›' : j.status === 'in_progress' ? '탭하여 러닝 화면 ›' : '정산 완료'}
                  </Text>
                </View>
                {/* FINISHER 도장 (완료) */}
                {done && (
                  <View style={s.finStamp}><Text style={{ fontSize: 10, fontWeight: '900', letterSpacing: 2, color: '#6E9BC5' }}>FINISHER</Text></View>
                )}
                {/* 절취선 스터브 — 실수령/예상 */}
                <View style={s.stub}>
                  <View style={[s.notch, { top: -9 }]} />
                  <View style={[s.notch, { bottom: -9 }]} />
                  <Text style={{ fontSize: 15.5, fontWeight: '900', color: done ? '#4A6E93' : '#5a7a3c', fontVariant: ['tabular-nums'] }}>
                    +{j.payout.toLocaleString()}
                  </Text>
                  <Text style={{ fontSize: 9.5, fontWeight: '800', letterSpacing: 1.5, color: '#9a978a', marginTop: 2 }}>
                    {done ? '정산됨' : 'PAYOUT'}
                  </Text>
                </View>
              </Pressable>
            );
          })}
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  availBtn: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 14 },
  board: { backgroundColor: FOREST, borderRadius: 20, padding: 16, marginTop: 14 },
  flap: { backgroundColor: '#0a140d', borderRadius: 7, paddingVertical: 6, paddingHorizontal: 8 },
  flapThin: { paddingHorizontal: 4, backgroundColor: 'transparent' },
  ticket: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4', marginBottom: 10, overflow: 'hidden', position: 'relative' },
  oval: { borderRadius: 99, paddingVertical: 3, paddingHorizontal: 9 },
  stub: { width: 92, borderLeftWidth: 2, borderLeftColor: '#DCD6C4', borderStyle: 'dashed', backgroundColor: '#fbfaf5', alignItems: 'center', justifyContent: 'center', position: 'relative' },
  notch: { position: 'absolute', left: -9, width: 16, height: 16, borderRadius: 8, backgroundColor: colors.cream, borderWidth: 1, borderColor: '#DCD6C4' },
  finStamp: { position: 'absolute', right: 100, top: 9, borderWidth: 2.5, borderColor: '#6E9BC5', borderRadius: 8, paddingVertical: 3, paddingHorizontal: 8, transform: [{ rotate: '-9deg' }], opacity: 0.85, zIndex: 2 },
  emptyJobs: { backgroundColor: '#f4f2ea', borderRadius: 16, padding: 20, alignItems: 'center', gap: 10, marginTop: 16 },
  emptyBtn: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 9, paddingHorizontal: 16 },
});
