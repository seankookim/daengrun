import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { fetchRunnerJobs, RunnerJob } from '../../src/lib/api';
import { runnerJob } from '../../src/store';
import { colors } from '../../src/theme';

const JOB_STATUS = {
  confirmed: { label: '확정', bg: '#e3f0c4', fg: '#3d5a2b' },
  in_progress: { label: '진행 중', bg: '#eaf7c8', fg: '#4a6d1f' },
  completed: { label: '완료', bg: '#e9ebe2', fg: '#75806f' },
} as const;

// 러너 캘린더 — day timeline (default per docs/calendar.md).
// Blocks: confirmed / travel buffer / available / blocked / pending.

const FOREST = '#132117';
const DATES = [
  { d: '22', w: '수', today: true }, { d: '23', w: '목' }, { d: '24', w: '금' },
  { d: '25', w: '토' }, { d: '26', w: '일' }, { d: '27', w: '월' }, { d: '28', w: '화' },
];

// (데모 타임라인 제거 — 실작업만 표시. 시간대 타임라인 뷰·이동 버퍼 경고는 실좌표 붙는 세션에서 실데이터로 복귀)

export default function RunnerCalendar() {
  const [dateIdx, setDateIdx] = useState(0);
  const [jobs, setJobs] = useState<RunnerJob[]>([]);

  useFocusEffect(useCallback(() => {
    fetchRunnerJobs().then(setJobs).catch(() => {});
  }, []));

  const openJob = (j: RunnerJob) => {
    if (j.status === 'completed') {
      Alert.alert('완료된 러닝', `${j.dogName} · ${j.km}km · +${j.payout.toLocaleString()}원\n수익 탭에서 정산 내역을 확인하세요`);
      return;
    }
    runnerJob.bookingId = j.bookingId;
    // active(러닝 중)만 러닝 화면으로 — picked_up(인계 완료)은 미트업의 '러닝 시작하기' 단계로
    router.push(j.rawStatus === 'active' ? '/runner/run' : '/runner/meetup');
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 60, paddingBottom: 30 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>캘린더</Text>
            <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>
              2026년 7월 · 확정 {jobs.filter((j) => j.status !== 'completed').length}건 · 예상 +
              {jobs.filter((j) => j.status !== 'completed').reduce((sum, j) => sum + j.payout, 0).toLocaleString()}원
            </Text>
          </View>
          <Pressable onPress={() => router.push('/runner/availability')} style={s.availBtn}>
            <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#fff' }}>가용시간 설정</Text>
          </Pressable>
        </Row>

        {/* week strip */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }} contentContainerStyle={{ gap: 8 }}>
          {DATES.map((d, i) => (
            <Pressable key={d.d} onPress={() => setDateIdx(i)} style={[s.dateChip, dateIdx === i && { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 10, color: dateIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
              <Text style={{ fontSize: 16, fontWeight: '900', color: dateIdx === i ? '#fff' : FOREST }}>{d.d}</Text>
              {d.today && <View style={{ width: 4, height: 4, borderRadius: 2, backgroundColor: dateIdx === i ? colors.volt : '#5a7a3c' }} />}
            </Pressable>
          ))}
        </ScrollView>

        {/* ---------- 내 작업 (실예약) ---------- */}
        <View style={{ marginTop: 18 }}>
          <Row style={{ gap: 6, marginBottom: 8 }}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>내 작업</Text>
            <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7 }}>
              <Text style={{ fontSize: 8.5, fontWeight: '900', color: '#fff' }}>● LIVE</Text>
            </View>
          </Row>
          {jobs.length === 0 && (
            <View style={s.emptyJobs}>
              <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 }}>
                확정된 작업이 아직 없어요{'\n'}요청 탭에서 새 요청을 수락해보세요
              </Text>
              <Pressable onPress={() => router.push('/runner/requests')} style={s.emptyBtn}>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: FOREST }}>요청 보러 가기 ›</Text>
              </Pressable>
            </View>
          )}
          {jobs.map((j) => {
              const st = JOB_STATUS[j.status];
              return (
                <Pressable key={j.bookingId} onPress={() => openJob(j)} style={[s.session, { marginBottom: 8 }]}>
                  <View style={[s.timeRail, j.status === 'completed' && { backgroundColor: '#c9ccc0' }]} />
                  <View style={{ flex: 1 }}>
                    <Row style={{ justifyContent: 'space-between' }}>
                      <Text style={{ fontSize: 12, fontWeight: '800', color: '#5d655d' }}>{j.when}</Text>
                      <View style={[s.statusPill, { backgroundColor: st.bg }]}>
                        <Text style={{ fontSize: 9.5, fontWeight: '800', color: st.fg }}>{st.label}</Text>
                      </View>
                    </Row>
                    <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 3 }}>
                      {j.dogName} · {j.km}km 러닝
                    </Text>
                    <Row style={{ justifyContent: 'space-between', marginTop: 2 }}>
                      <Text style={{ fontSize: 11.5, color: colors.dim }}>
                        {j.status === 'confirmed' ? '탭하여 픽업 진행 ›' : j.status === 'in_progress' ? '탭하여 러닝 화면 ›' : '정산 완료'}
                      </Text>
                      <Text style={{ fontSize: 13, fontWeight: '900', color: '#5a7a3c' }}>+{j.payout.toLocaleString()}원</Text>
                    </Row>
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
  availBtn: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 14, alignSelf: 'flex-start' },
  dateChip: { width: 52, borderRadius: 14, backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf', alignItems: 'center', paddingVertical: 9, gap: 2 },
  session: { flexDirection: 'row', gap: 12, backgroundColor: '#fff', borderRadius: 16, padding: 13, borderWidth: 1, borderColor: '#eceadf' },
  timeRail: { width: 4, borderRadius: 2, backgroundColor: '#5a7a3c' },
  statusPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  emptyJobs: {
    backgroundColor: '#f4f2ea', borderRadius: 16, padding: 20, alignItems: 'center', gap: 10,
  },
  emptyBtn: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 9, paddingHorizontal: 16 },
});
