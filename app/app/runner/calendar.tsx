import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
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

// 2026-08-24 enhancement wave (docs/labs/enh-runner-home-lab.html C①②③ · Sean: "For runner home
// I like all new updates you are showing me"). Three changes, no new server data:
//  · C① 오늘 → 예정 → 지난 러닝. fetchRunnerJobs returns scheduled_at DESC, so this screen opened
//    on the run furthest away and buried today's in the middle of a flat list. Grouping is
//    client-side; the query, openJob and the board are untouched.
//  · C② the board says the next run instead of 「다음 러닝까지 준비 완료」 — a readiness nobody
//    measured, replaced by a fact the same jobs array can prove.
//  · C③ the completed ticket gets the two doors home already ships (/shot/[bid] · /runner/earnings)
//    in place of an Alert that named a destination and refused to go there, and its 정산 완료/정산됨
//    become 정산 예정 — home's week line is the true vocabulary (a ledger row means the run was
//    PRICED; there is no code path that pays a runner yet).

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

// day = "8월 24일 (일) 오후" → 꼬리 토큰(오전/오후)만. 오늘 묶음의 티켓은 날짜를 머리줄이 이미
// 말하므로 시각의 오전/오후만 남긴다. 꼬리가 오전/오후가 아니면(라벨 형식이 바뀐 경우)
// 원문을 그대로 인쇄한다 — 형식 가정이 틀렸을 때 정보를 지우지 않기 위해서다.
const dayTail = (day: string): string => {
  const t = day.split(' ').pop() ?? '';
  return t === '오전' || t === '오후' ? t : day;
};

// KST 고정 오프셋 — 한국은 DST가 없다. 러너 홈의 kstDay·서버 kstParts와 같은 전제이고, 기기 로컬
// 타임존이 아니다 (시뮬레이터가 UTC면 로컬 날짜는 하루 어긋난다).
const KST_MS = 9 * 3_600_000;
const kstDay = (ms: number) => new Date(ms + KST_MS).toISOString().slice(0, 10);

// 상대 시각 — 러너 홈 relWhen의 이식본. 두 클램프까지 그대로 가져온다: 반나절 넘게 늦은 건은
// '지각한 러너'가 아니라 '멈춘 예약'이고(홈이 실기기에서 「400시간 59분 늦음」을 인쇄한 뒤 생긴 법),
// 하루 넘게 남은 건의 카운트다운은 아무도 행동으로 옮기지 않는다 → null(날짜가 일한다).
const LATE_CAP_MIN = 12 * 60;
const AHEAD_CAP_MIN = 24 * 60;
const relWhen = (iso: string | null): string | null => {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const min = Math.round((t - Date.now()) / 60000);
  if (min < -LATE_CAP_MIN) return '지난 예약';
  if (min > AHEAD_CAP_MIN) return null;
  if (min < 0) {
    const l = Math.abs(min);
    return l >= 60 ? `${Math.floor(l / 60)}시간 ${l % 60}분 늦음` : `${l}분 늦음`;
  }
  if (min === 0) return '지금';
  return min >= 60 ? `${Math.floor(min / 60)}시간 ${min % 60}분 뒤` : `${min}분 뒤`;
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

  // [C③ 2026-08-24] 완료 건의 Alert 분기가 사라졌다. 그 다이얼로그의 유일한 내용은 **데려다주지
  // 않는 목적지의 이름**이었고("수익 탭에서 정산 내역을 확인하세요"), 홈은 같은 행에 대해 이미 진짜
  // 문 두 개를 들고 있다. 완료 티켓은 이제 통짜 탭 타깃이 아니라 문 두 개를 갖는다 (아래 참조).
  const openJob = (j: RunnerJob) => {
    runnerJob.bookingId = j.bookingId;
    // active(러닝 중)만 러닝 화면으로 — picked_up(인계 완료)은 미트업의 '러닝 시작하기' 단계로
    router.push(j.rawStatus === 'active' ? '/runner/run' : '/runner/meetup');
  };

  const upcoming = jobs.filter((j) => j.status !== 'completed');
  const expected = upcoming.reduce((sum, j) => sum + j.payout, 0);
  const flapChars = `+${expected.toLocaleString()}`.split('');

  // 시각 정렬 키 — scheduledAt이 없는 행은 정렬의 끝으로 (없는 시각을 0으로 읽으면 1970년이 된다)
  const at = (j: RunnerJob) => {
    const t = j.scheduledAt ? Date.parse(j.scheduledAt) : NaN;
    return Number.isNaN(t) ? Number.POSITIVE_INFINITY : t;
  };

  // [C② 2026-08-24] 보드의 두 번째 줄. 「다음 러닝까지 준비 완료」는 아무도 재지 않은 준비 상태를
  // 단언했다 — 보드는 러너가 준비됐는지 알 방법이 없다. 한 줄 아래에 있는, 이 화면이 **증명할 수
  // 있는** 사실로 바꾼다: 다음 러닝이 언제인가. 값은 이미 불러온 jobs의 min(scheduledAt)이다.
  const nextJob = upcoming.length > 0 ? upcoming.reduce((a, b) => (at(a) <= at(b) ? a : b)) : null;
  const nextRel = nextJob ? relWhen(nextJob.scheduledAt) : null;
  const nextLabel = (() => {
    if (!nextJob) return null;
    const { day, time } = splitWhen(nextJob.when);
    const isToday = nextJob.scheduledAt
      && kstDay(Date.parse(nextJob.scheduledAt)) === kstDay(Date.now());
    return isToday ? `오늘 ${dayTail(day)} ${time}` : nextJob.when;
  })();

  // [C① 2026-08-24] 오늘 → 예정 → 지난. 그룹 키는 KST 일자 문자열('YYYY-MM-DD')이라 사전식 비교가
  // 곧 날짜 비교다. scheduledAt이 없는 행은 **오늘이라고 주장할 수 없으므로** status가 말하는 것만
  // 따른다 (완료 → 지난, 그 외 → 예정). 정렬: 예정은 이른 순, 지난은 최근 순.
  const today = kstDay(Date.now());
  const bucket = (j: RunnerJob): 'today' | 'up' | 'past' => {
    if (!j.scheduledAt) return j.status === 'completed' ? 'past' : 'up';
    const t = Date.parse(j.scheduledAt);
    if (Number.isNaN(t)) return j.status === 'completed' ? 'past' : 'up';
    const d = kstDay(t);
    return d === today ? 'today' : d > today ? 'up' : 'past';
  };
  const todayJobs = jobs.filter((j) => bucket(j) === 'today').sort((a, b) => at(a) - at(b));
  const upJobs = jobs.filter((j) => bucket(j) === 'up').sort((a, b) => at(a) - at(b));
  const pastJobs = jobs.filter((j) => bucket(j) === 'past').sort((a, b) => at(b) - at(a));
  // 오늘 머리줄의 우측 날짜 — 오늘 티켓이 있을 때만 그려지므로 그 티켓의 날짜가 곧 오늘이다.
  const todayDate = todayJobs.length > 0
    ? splitWhen(todayJobs[0].when).day.replace(/\s*(오전|오후)$/, '')
    : '';

  // 한 티켓. 세 묶음이 같은 오브젝트를 쓰므로 렌더는 한 군데다 (복사본 세 개는 다음 사람이
  // 두 개만 고치는 자리다). 오늘 묶음의 티켓만 1.5px 잉크 테두리 — 이 클러스터가 이미 쓰는
  // '지금 내가 들고 있는 것' 문법이고, 날짜는 머리줄이 말하므로 행에는 오전/오후만 남는다.
  const renderTicket = (j: RunnerJob, todayGroup: boolean) => {
    const st = JOB_STATUS[j.status];
    const { day, time } = splitWhen(j.when);
    const done = j.status === 'completed';
    const body = (
      <>
        {/* 본문 */}
        <View style={{ flex: 1, padding: 13, paddingRight: 10 }}>
          <Row style={{ gap: 7, alignItems: 'baseline' }}>
            {/* Oswald ticket time — lineHeight 27 = 1.29× (BUG A) */}
            <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{time}</Text>
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.dim, flex: 1 }} numberOfLines={1}>
              {todayGroup ? dayTail(day) : day}
            </Text>
            {/* §3b status chip — 16/800, tinted fill, no border, on the time's row */}
            <View style={[s.statusChip, { backgroundColor: st.bg }]}>
              <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: st.fg }}>{st.label}</Text>
            </View>
          </Row>
          <Text style={{ fontSize: 16.5, fontWeight: '800', color: paper.ink, marginTop: 4 }}>
            {j.dogName} · {j.km}km 러닝
          </Text>
          {/* [C③] 완료 행의 문장. 종전 '정산 완료'는 정산 사실이 아니라 표시 어휘(STATUS_MAP이
              뭉갠 'completed')에서 파생돼 있었다 — 이 화면에는 정산 여부를 아는 필드가 없다.
              수익 화면이 이미 쓰는 문장으로 맞춘다: 세 화면이 같은 사실을 같은 말로. */}
          <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 2 }}>
            {j.status === 'confirmed' ? '탭하여 픽업 진행 ›'
              : j.status === 'in_progress' ? '탭하여 러닝 화면 ›'
                : '지급 일정은 아직 정해지지 않았어요'}
          </Text>
        </View>
        {/* FINISHER 도장 (완료) — latin stamp glyph class (15pt floor exempt) */}
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
          <Text style={{ fontSize: 15, lineHeight: 18, color: paper.dim, marginTop: 2 }}>
            {done ? '정산 예정' : '실수령'}
          </Text>
        </View>
      </>
    );

    if (!done) {
      return (
        <Pressable
          key={j.bookingId}
          onPress={() => openJob(j)}
          style={({ pressed }) => [s.ticket, todayGroup && s.ticketToday, pressed && { transform: [{ scale: 0.98 }] }]}
        >
          {body}
        </Pressable>
      );
    }
    // [C③] 완료 티켓은 문이 둘이므로 티켓 전체 누르기를 내려놓는다 — 한 번의 누름이 두 가지를
    // 뜻할 수는 없다. 두 문 다 이미 존재하는 라우트이고 홈이 같은 행에서 쓰는 목적지다.
    // 도장은 이 행 안에 있으므로 문 줄을 물지 않는다 (position은 아래 행 래퍼 기준).
    return (
      <View key={j.bookingId} style={[s.ticket, s.ticketDone, todayGroup && s.ticketToday]}>
        <View style={s.ticketRow}>{body}</View>
        <Row style={s.doneDoors}>
          <Pressable
            onPress={() => router.push(`/shot/${j.bookingId}`)}
            style={({ pressed }) => [s.doneDoor, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button"
            accessibilityLabel={`${j.dogName} 인증샷 보기`}
          >
            <Text style={s.doneDoorTxt}>인증샷 ›</Text>
          </Pressable>
          <Pressable
            onPress={() => router.push('/runner/earnings')}
            style={({ pressed }) => [s.doneDoor, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button"
            accessibilityLabel="수익 상세 보기"
          >
            <Text style={s.doneDoorTxt}>수익 상세 ›</Text>
          </Pressable>
        </Row>
      </View>
    );
  };

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
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>가용시간 설정</Text>
          </Pressable>
        </Row>

        {/* ---------- 출발 보드 (C1) — 예상 수익 스플릿-플랩. Dark artifact on paper.ink (the
            board is a ceremony object, not chrome) — volt flap digits = personal money ---------- */}
        <View style={s.board}>
          <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF' }}>나의 출발</Text>
          {/* [C②] 확정 0건은 종전 문장 그대로 (진짜 출구가 있는 문장이라 바꿀 이유가 없다).
              nextLabel은 확정 건이 있으면 항상 있고, nextRel은 하루 밖(또는 시각 없음)이면 null —
              그때는 날짜가 제 일을 하므로 카운트다운을 붙이지 않는다. */}
          <Text style={{ fontSize: 15, lineHeight: 18, color: '#BBBBBB', marginTop: 3 }}>
            확정 {upcoming.length}건
            {upcoming.length > 0 && nextLabel
              ? ` · 다음 러닝 ${nextLabel}${nextRel ? ` · ${nextRel}` : ''}`
              : upcoming.length > 0 ? '' : ' — 요청 탭에서 수락해보세요'}
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
              <Text style={{ fontSize: 15, lineHeight: 18, color: '#BBBBBB', marginTop: 6 }}>확정 건 예상 정산 합계</Text>
            </>
          )}
        </View>

        {/* ---------- 티켓 스택 (C2) ---------- */}
        {!loaded && !loadErr && (
          <View style={s.emptyJobs}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>확정 일정을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && jobs.length === 0 && (
          <View style={s.emptyJobs}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
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

        {/* [C①] 세 묶음. 머리줄은 §3b 그램마 그대로 (풀블리드 코랄 룰 + 20/800) — 앱의 다른 섹션
            머리줄과 같은 말투다. 비어 있는 묶음은 머리줄째 그리지 않는다.
            ⚠ 이 그룹핑은 **20건 창을 고치지 않는다**: fetchRunnerJobs는 여전히 scheduled_at DESC
            limit 20이라, 미래 예약이 스무 건을 넘으면 지난 러닝이 창 밖으로 밀린다. 그래서 지난
            묶음의 캡션이 「최근 20건 안에서」다 — 이 목록이 러너의 전체 기록이라고 주장하지 않는다.
            (홈은 같은 창을 fetchInFlightRunnerJobs로 우회했지만 캘린더에는 대응물이 없고,
             그룹핑이 받지 못한 행을 지어낼 수는 없다.) */}
        {todayJobs.length > 0 && (
          <>
            <Row style={s.dayGroup}>
              <Text style={s.dayGroupH}>오늘</Text>
              <Text style={s.dayGroupS}>{todayDate}</Text>
            </Row>
            <View style={{ marginTop: 10 }}>{todayJobs.map((j) => renderTicket(j, true))}</View>
          </>
        )}
        {upJobs.length > 0 && (
          <>
            <Row style={s.dayGroup}>
              <Text style={s.dayGroupH}>예정</Text>
              <Text style={s.dayGroupS}>{upJobs.length}건</Text>
            </Row>
            <View style={{ marginTop: 10 }}>{upJobs.map((j) => renderTicket(j, false))}</View>
          </>
        )}
        {pastJobs.length > 0 && (
          <>
            <Row style={s.dayGroup}>
              <Text style={s.dayGroupH}>지난 러닝</Text>
              <Text style={s.dayGroupS}>최근 20건 안에서</Text>
            </Row>
            <View style={{ marginTop: 10 }}>{pastJobs.map((j) => renderTicket(j, false))}</View>
          </>
        )}
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
  // [C①] 오늘의 티켓 — 잉크 1.5px. 이 클러스터의 오브젝트 문법("지금 내가 들고 가는 것")과 같다.
  ticketToday: { borderWidth: 1.5, borderColor: paper.ink },
  // [C③] 완료 티켓은 본문 행 + 문 줄의 세로 스택이다 (본문 행 안에서는 여전히 가로).
  ticketDone: { flexDirection: 'column' },
  ticketRow: { flexDirection: 'row', position: 'relative' },
  doneDoors: { gap: 8, paddingHorizontal: 10, paddingBottom: 10 },
  // ≥44pt 타깃 (pv 14 + 20 라인 = 48). 뉴트럴 테두리 — 코랄은 이 화면에서 가용시간 칩 하나다.
  doneDoor: {
    flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 14,
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
  },
  doneDoorTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: paper.ink },
  // [C①] 묶음 머리줄 — §3b 그램마 (거터를 뚫는 풀블리드 코랄 룰 + 타이틀 20/800 + 우측 캡션 14/700)
  dayGroup: {
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter,
    marginTop: 16, paddingTop: 10, alignItems: 'baseline', gap: 8,
    borderTopWidth: 1, borderTopColor: paper.line,
  },
  dayGroupH: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
  dayGroupS: { marginLeft: 'auto', fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim },
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
