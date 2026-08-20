import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { TabSwipe } from '../../src/components/tabswipe';
import { Row } from '../../src/components/ui';
import { fetchRunnerJobs, RunnerJob } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { runnerJob } from '../../src/store';
import { colors, layout, paper } from '../../src/theme';

// 러너 캘린더 — C1(출발 보드) × C2(티켓 스택) 머지 (Sean 확정, 2026-07-29, hi-club-plan §1-B).
// C1에서: 다크 출발 보드 톱 위젯 — 스플릿-플랩 예상 수익 카운터 + 확정 건수 + 상태 오벌.
// C2에서: 작업 행 = 절취선 티켓 (우측 스터브에 실수령/예상 금액), 완료 티켓엔 FINISHER 도장.
// 수익은 전부 실데이터 (fetchRunnerJobs — 완료 건은 ledger 실 net, 그 외 티어 요율 견적).
//
// [paper repaint 2026-08-11] forest/cream/volt chrome scrapped → paper. Kept as artifacts:
// the dark departure board (split-flap counter = race-program object, now on paper.ink),
// ticket perforation stubs + notches (circles are the perforation exception), FINISHER
// stamp (latin stamp glyph class). Retired: 'PAYOUT' latin caption → 실수령 (14pt law),
// completed-ticket 0.82 opacity (status chip + stamp already say it), display font on the
// board title (budget = screen title once). All handlers/routes/data frozen.

const JOB_STATUS: Record<RunnerJob['status'], { label: string; bg: string; fg: string }> = {
  confirmed: { label: '확정', bg: '#E8F3D2', fg: '#3D6B1F' },
  in_progress: { label: '진행 중', bg: '#EAF6C8', fg: '#3D6B1F' },
  completed: { label: '완료', bg: '#E3EEF8', fg: '#4A6E93' },
};

// "7월 29일 (화) 오후 7:00" → { day: '7월 29일 (화) 오후', time: '7:00' } (러너 홈과 동일 분리)
const splitWhen = (when: string): { day: string; time: string } => {
  const i = when.lastIndexOf(' ');
  return i < 0 ? { day: when, time: '' } : { day: when.slice(0, i), time: when.slice(i + 1) };
};

export default function RunnerCalendar() {
  const df = useDisplayFont(); // display font — screen title only (1/screen budget)
  const nf = useNumFont();     // Oswald — flap digits, ticket times, payouts
  const [jobs, setJobs] = useState<RunnerJob[]>([]);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "확정된 작업이
  // 아직 없어요" while loading AND on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);

  const load = () => {
    setLoadErr(false);
    return fetchRunnerJobs()
      .then((j) => { setJobs(j); setLoaded(true); })
      .catch((e) => { console.warn('[calendar] jobs:', e?.message ?? e); setLoadErr(true); });
  };
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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
          <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>캘린더</Text>
          {/* secondary chip — canvas + coral border + ink label (§3b secondary; chip may stay 14) */}
          <Pressable
            onPress={() => router.push('/runner/availability')}
            style={({ pressed }) => [s.availBtn, pressed && { backgroundColor: paper.wash }]}
          >
            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>가용시간 설정</Text>
          </Pressable>
        </Row>

        {/* ---------- 출발 보드 (C1) — 예상 수익 스플릿-플랩. Dark artifact on paper.ink (the
            board is a ceremony object, not chrome) — volt flap digits = personal money ---------- */}
        <View style={s.board}>
          <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF' }}>나의 출발</Text>
          <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB', marginTop: 3 }}>
            확정 {upcoming.length}건{upcoming.length > 0 ? ' · 다음 러닝까지 준비 완료' : ' — 요청 탭에서 수락해보세요'}
          </Text>
          {/* [Sean 2026-08-11 "캘린더 탭 수익 숫자 더 크게"] 플랩 20 → 30pt.
              폭 예산 (320dp 기준, 넘치면 스플릿-플랩 행이 잘린다 — Row에 wrap 없음):
                가용폭 = 320 − 30 거터 − 32 보드 패딩 = 258.
                최악 현실값 '+248,000' = 굵은 셀 6(숫자) + 얇은 셀 2('+' ',').
                30pt Oswald 숫자 글리프 ≈ 0.5em = 15 → 굵은 셀 15 + 패딩 10 = 25 · 6 = 150.
                얇은 셀 ≈ 8 + 8 = 16 · 2 = 32. 갭 4 × 7 = 28. 합계 = 210 < 258 ✓
              그래서 flap의 paddingHorizontal은 8 → 5로 함께 줄인다 (8이면 246 + '원' 열까지
              얹혀 320dp에서 넘쳤다). '원 예상'은 인라인에서 빠져 아래 캡션이 가져간다 —
              30pt 옆의 14pt 인라인 꼬리표는 숫자를 도로 작아 보이게 만들었다. */}
          {upcoming.length > 0 && (
            <>
              <Row style={{ gap: 4, marginTop: 12, alignItems: 'flex-end' }}>
                {flapChars.map((c, i) => (
                  <View key={i} style={[s.flap, (c === ',' || c === '+') && s.flapThin]}>
                    {/* Oswald flap digit — lineHeight 38 = 1.27× (BUG A) */}
                    <Text style={[{ fontSize: 30, lineHeight: 38, fontWeight: '900', color: colors.volt, fontVariant: ['tabular-nums'] as const }, nf]}>{c}</Text>
                  </View>
                ))}
                <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF', paddingBottom: 5, marginLeft: 4 }}>원</Text>
              </Row>
              {/* 추정치라는 사실은 여기서 한 번 — 확정 건들의 예상 정산 합계이지 확정 지급액이 아니다 */}
              <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB', marginTop: 6 }}>확정 건 예상 정산 합계</Text>
            </>
          )}
        </View>

        {/* ---------- 티켓 스택 (C2) ---------- */}
        {!loaded && !loadErr && (
          <View style={s.emptyJobs}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>확정 일정을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && jobs.length === 0 && (
          <View style={s.emptyJobs}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              확정된 작업이 아직 없어요{'\n'}요청 탭에서 새 요청을 수락해보세요
            </Text>
            <Pressable
              onPress={() => router.push('/runner/requests')}
              style={({ pressed }) => [s.emptyBtn, pressed && { backgroundColor: paper.wash }, pressed && { transform: [{ scale: 0.96 }] }]}
            >
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>요청 보러 가기 ›</Text>
            </Pressable>
          </View>
        )}

        <View style={{ marginTop: 16 }}>
          {jobs.map((j) => {
            const st = JOB_STATUS[j.status];
            const { day, time } = splitWhen(j.when);
            const done = j.status === 'completed';
            return (
              <Pressable key={j.bookingId} onPress={() => openJob(j)} style={({ pressed }) => [s.ticket, pressed && { transform: [{ scale: 0.98 }] }]}>
                {/* 본문 */}
                <View style={{ flex: 1, padding: 13, paddingRight: 10 }}>
                  <Row style={{ gap: 7, alignItems: 'baseline' }}>
                    {/* Oswald ticket time — lineHeight 27 = 1.29× (BUG A) */}
                    <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{time}</Text>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: paper.dim, flex: 1 }} numberOfLines={1}>{day}</Text>
                    {/* §3b status chip — 16/800, tinted fill, no border, on the time's row */}
                    <View style={[s.statusChip, { backgroundColor: st.bg }]}>
                      <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: st.fg }}>{st.label}</Text>
                    </View>
                  </Row>
                  <Text style={{ fontSize: 16.5, fontWeight: '800', color: paper.ink, marginTop: 4 }}>
                    {j.dogName} · {j.km}km 러닝
                  </Text>
                  <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>
                    {j.status === 'confirmed' ? '탭하여 픽업 진행 ›' : j.status === 'in_progress' ? '탭하여 러닝 화면 ›' : '정산 완료'}
                  </Text>
                </View>
                {/* FINISHER 도장 (완료) — latin stamp glyph class (14pt floor exempt) */}
                {done && (
                  <View style={s.finStamp}><Text style={{ fontSize: 10, fontWeight: '900', letterSpacing: 2, color: '#6E9BC5' }}>FINISHER</Text></View>
                )}
                {/* 절취선 스터브 — 실수령/예상 (perforation notches keep their circles) */}
                <View style={s.stub}>
                  <View style={[s.notch, { top: -9 }]} />
                  <View style={[s.notch, { bottom: -9 }]} />
                  {/* Oswald payout — lineHeight 20 = 1.29× (BUG A) */}
                  <Text style={[{ fontSize: 15.5, lineHeight: 20, fontWeight: '900', color: done ? '#4A6E93' : '#3D6B1F', fontVariant: ['tabular-nums'] as const }, nf]}>
                    +{j.payout.toLocaleString()}
                  </Text>
                  {/* 'PAYOUT' latin caption retired — Korean data renders ≥14 (§3 kicker law) */}
                  <Text style={{ fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 2 }}>
                    {done ? '정산됨' : '실수령'}
                  </Text>
                </View>
              </Pressable>
            );
          })}
        </View>
      </ScrollView>
      </TabSwipe>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  availBtn: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 10, paddingHorizontal: 14 },
  board: { backgroundColor: paper.ink, padding: 16, marginTop: 14 },
  // paddingHorizontal 8 → 5: 30pt 승격의 폭 예산 (위 주석의 320dp 계산). 세로 패딩은 유지.
  flap: { backgroundColor: '#000000', paddingVertical: 6, paddingHorizontal: 5 },
  flapThin: { paddingHorizontal: 3, backgroundColor: 'transparent' },
  ticket: {
    flexDirection: 'row', backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    marginBottom: 10, overflow: 'hidden', position: 'relative',
  },
  statusChip: { borderRadius: 0, paddingVertical: 3, paddingHorizontal: 9 },
  stub: {
    width: 96, borderLeftWidth: 2, borderLeftColor: '#EEEEEE', borderStyle: 'dashed',
    backgroundColor: '#FAFAFA', alignItems: 'center', justifyContent: 'center', position: 'relative',
  },
  notch: { position: 'absolute', left: -9, width: 16, height: 16, borderRadius: 8, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' },
  // [layout 2026-08-19] top 9 → bottom 9. 도장은 티켓 본문의 우측 상단에 앉아 있었는데, 같은
  // 행의 우측 끝은 상태 칩('완료')의 자리다 — 도장 우변(right:104)이 칩 우변(right:108)보다
  // 4pt 더 오른쪽이라 완료된 모든 행에서 칩 위에 겹쳐 찍혔다 (실측). 본문 하단 우측은
  // '정산 완료' 한 줄만 있고 그 줄은 좌측 65pt 안에서 끝나므로, 아래로 내리면 어떤 행에서도
  // 글자를 물지 않는다. 좌우는 그대로 — 스텁(우측 98pt)과의 간격도 유지된다.
  finStamp: {
    position: 'absolute', right: 104, bottom: 9, borderWidth: 2.5, borderColor: '#6E9BC5',
    paddingVertical: 3, paddingHorizontal: 8, transform: [{ rotate: '-9deg' }], zIndex: 2,
  },
  emptyJobs: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 20, alignItems: 'center', gap: 12, marginTop: 16 },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { marginTop: 16, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  emptyBtn: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 12, paddingHorizontal: 16 },
});
