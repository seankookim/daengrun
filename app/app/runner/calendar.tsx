import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomNav } from '../../src/components/bottomnav';
import { TabSwipe } from '../../src/components/tabswipe';
import { Row } from '../../src/components/ui';
import { fetchMyReviewedBookingIds, fetchMyRunnerStatus, fetchRunnerJobs, RunnerJob } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { reviewDoor, type ReviewedRead } from '../../src/lib/review-gate';
import { runnerJobCaption, runnerJobDestination } from '../../src/lib/runner-job-route';
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
  const insets = useSafeAreaInsets();
  const df = useDisplayFont(); // display font — screen title only (1/screen budget)
  const nf = useNumFont();     // Oswald — flap digits, ticket times, payouts
  const [jobs, setJobs] = useState<RunnerJob[]>([]);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "확정된 작업이
  // 아직 없어요" while loading AND on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);

  // ═══ THE SECOND DOOR TO THE REVIEW ════════════════════════════════════════════════════════
  // `runner/done` is reachable once per run in practice, so 「리뷰 남기기」 has been a
  // use-it-or-lose-it door: a runner who backed out of that screen could never review the run
  // again. The completed ticket is the second door, and it is drawn from the `reviews` table
  // rather than from anything local — a door onto a duplicate insert is a dead button with extra
  // steps. THREE STATES (review-gate.ts): `err` and `loading` both HIDE the door, because neither
  // licenses the sentence 「you have not reviewed this run」. Pull-to-refresh is the retry.
  const [reviewed, setReviewed] = useState<Set<string>>(new Set());
  const [reviewedRead, setReviewedRead] = useState<ReviewedRead>('loading');

  const loadReviewed = (list: RunnerJob[]) => {
    const done = list.filter((j) => j.rawStatus === 'completed').map((j) => j.bookingId);
    if (done.length === 0) { setReviewed(new Set()); setReviewedRead('ready'); return; }
    setReviewedRead('loading');
    return fetchMyReviewedBookingIds(done)
      .then((ids) => { setReviewed(ids); setReviewedRead('ready'); })
      .catch((e) => { console.warn('[calendar] reviews:', e?.message ?? e); setReviewedRead('err'); });
  };

  // [onboarding-first-run-8] The empty state below told EVERY zero-job runner 「요청 탭에서 새 요청을
  // 수락해보세요」 — and for an applicant the 요청 tab then says 「인증 전에는 요청이 오지 않아요」 and
  // sends them to /runner/apply. A two-hop misdirection on the one tab that could point straight at
  // the next step. Same tri-state as runner/home.tsx's `preCert`: the applicant sentence is drawn
  // only when the tier READ SUCCEEDED and says pre-certification; unknown or failed keeps today's
  // copy, because a guessed tier would tell a certified runner to go and apply.
  const [tier, setTier] = useState<{ s: 'loading' } | { s: 'ok'; tier: string | null } | { s: 'err' }>({ s: 'loading' });
  const loadTier = () => {
    fetchMyRunnerStatus()
      .then((v) => setTier({ s: 'ok', tier: v.tier }))
      .catch((e) => { console.warn('[calendar] status:', e?.message ?? e); setTier({ s: 'err' }); });
  };
  const preCert = tier.s === 'ok' && (tier.tier === null || tier.tier === 'applicant');

  const load = () => {
    setLoadErr(false);
    loadTier();
    return fetchRunnerJobs()
      .then((j) => { setJobs(j); setLoaded(true); return loadReviewed(j); })
      .catch((e) => { console.warn('[calendar] jobs:', e?.message ?? e); setLoadErr(true); });
  };
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // [C③ 2026-08-24] 완료 건의 Alert 분기가 사라졌다. 그 다이얼로그의 유일한 내용은 **데려다주지
  // 않는 목적지의 이름**이었고("수익 탭에서 정산 내역을 확인하세요"), 홈은 같은 행에 대해 이미 진짜
  // 문 두 개를 들고 있다. 완료 티켓은 이제 통짜 탭 타깃이 아니라 문 두 개를 갖는다 (아래 참조).
  // [runner-journey-2] The destination is the job's PHASE, not its status word. `active` alone sent
  // a run-ended (귀가) job to the live run screen; runner-job-route.ts reads `run_ended_at` too, and
  // routes `incident_review` by the same fact (runner-journey-8). The caption below comes from the
  // same function, so the ticket cannot promise one screen and open another.
  const openJob = (j: RunnerJob) => {
    runnerJob.bookingId = j.bookingId;
    router.push(runnerJobDestination(j));
  };

  // [runner-journey-8] `incident_review` rows now arrive (api.ts) and draw a ticket below, but they
  // are not part of the board's 「확정 N건 · 예상 정산 합계 · 다음 러닝」: the booking is held for a
  // person to decide, its payout is not a forecast anyone can make, and a held run from yesterday
  // would otherwise be announced as the 「다음 러닝」 with a 「지난 예약」 countdown.
  const upcoming = jobs.filter((j) => j.status !== 'completed' && j.rawStatus !== 'incident_review');
  // …and while one is held, the work gate (0092:116) refuses new work, so 「요청 탭에서 수락해보세요」
  // would point at a door that is shut. The held ticket itself is the thing to open.
  const held = jobs.some((j) => j.rawStatus === 'incident_review');
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
            {done ? '지급 일정은 아직 정해지지 않았어요' : runnerJobCaption(j)}
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
          {/* ⚠ [2026-09-15] 완료 전 티켓의 캡션이 「실수령」이었다. 그 자리의 `j.payout` 은
              `expectedByBooking` = 서버의 expected_net 이고 (api.ts:1513-1514), 그건 **계획 km 위의
              견적**이지 받은 돈이 아니다. 러너 홈이 같은 값에서 이 단어를 이미 은퇴시켰다
              (home.tsx:954-956 — 「'실수령'은 확정 금액을 뜻한다 — 이 값은 추정치다」 → 「예상」).
              이 파일 자신도 위 출발 보드에서 같은 수들의 합을 「확정 건 예상 정산 합계」라고 부른다 —
              합은 예상이고 각 항은 실수령이라고 적고 있었다. 같은 어휘로 맞춘다. */}
          <Text style={{ fontSize: 15, lineHeight: 18, color: paper.dim, marginTop: 2 }}>
            {done ? '정산 예정' : '예상'}
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
          accessibilityRole="button"
        >
          {body}
        </Pressable>
      );
    }
    // [C③] 완료 티켓은 문이 둘이므로 티켓 전체 누르기를 내려놓는다 — 한 번의 누름이 두 가지를
    // 뜻할 수는 없다. 두 문 다 이미 존재하는 라우트이고 홈이 같은 행에서 쓰는 목적지다.
    // 도장은 이 행 안에 있으므로 문 줄을 물지 않는다 (position은 아래 행 래퍼 기준).
    // ⚠ 세 번째 문(리뷰)은 **조건부**다. `rawStatus === 'completed'`(정산됨)이고, `reviews`에서
    // 아직 내 리뷰가 없다고 **확인된** 경우에만 그린다 — 이미 쓴 러너에게 중복 insert로 가는
    // 문을 보여 주지 않고, 읽지 못한 상태를 '안 썼다'로 읽지도 않는다 (review-gate.ts).
    const door = reviewDoor({ rawStatus: j.rawStatus, read: reviewedRead, reviewed: reviewed.has(j.bookingId) });
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
        {/* 리뷰 문은 제 줄을 갖는다 — 셋째 `flex: 1` 칸에 넣으면 320dp에서 「리뷰 남기기 ›」가
            84pt 칸에 들어가지 않아 두 줄로 접힌다 (16/800 한글 5자 ≈ 93pt). 위 두 문은 참조고
            이건 행동이라 같은 무게가 아니기도 하다. */}
        {door.show && (
          <Pressable
            onPress={() => router.push({ pathname: '/runner/review', params: { bid: j.bookingId } })}
            style={({ pressed }) => [s.reviewDoor, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button"
            accessibilityLabel={`${j.dogName} 후기 남기기`}
          >
            <Text style={s.doneDoorTxt}>{j.dogName} 후기 남기기 ›</Text>
          </Pressable>
        )}
      </View>
    );
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top + 4, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
          <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>캘린더</Text>
          {/* secondary chip — canvas + coral border + ink label (§3b secondary; chip may stay 14) */}
          <Pressable
            onPress={() => router.push('/runner/availability')}
            style={({ pressed }) => [s.availBtn, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button"
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
          {/* ⚠ [2026-09-15 로딩은 0이 아니다] 이 줄에는 게이트가 없었다 — `jobs` 는 [] 로 시작하고
              `loaded`/`loadErr` 는 아래 티켓 스택에서만 읽히므로, 읽는 중에도 실패한 뒤에도 보드가
              「확정 0건 — 요청 탭에서 수락해보세요」라고 단언했다. 확정 러닝이 다섯 건 있는 러너에게
              한 말이고, 실패 때는 바로 아래 자기 화면의 「확정 일정을 불러오지 못했어요」 스트립과
              한 화면에서 서로를 반박했다. 러너 홈이 같은 결함으로 이미 고쳐진 자리다
              (home.tsx:802-807 — 「요청함 · 0건 ›」 을 inboxLoaded && !inboxErr 뒤로). */}
          <Text style={{ fontSize: 15, lineHeight: 18, color: '#BBBBBB', marginTop: 3 }}>
            {loadErr ? '확정 일정을 불러오지 못했어요'
              : !loaded ? '불러오는 중…'
                : `확정 ${upcoming.length}건${upcoming.length > 0 && nextLabel
                  ? ` · 다음 러닝 ${nextLabel}${nextRel ? ` · ${nextRel}` : ''}`
                  : upcoming.length > 0 || preCert || held ? '' : ' — 요청 탭에서 수락해보세요'}`}
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
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>불러오는 중…</Text>
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
              {preCert
                ? '인증이 끝나면 확정된 러닝이 여기에 떠요'
                : <>확정된 작업이 아직 없어요{'\n'}요청 탭에서 새 요청을 수락해보세요</>}
            </Text>
            <Pressable
              onPress={() => router.push(preCert ? '/runner/apply' : '/runner/requests')}
              style={({ pressed }) => [s.emptyBtn, pressed && { backgroundColor: paper.wash }, pressed && { transform: [{ scale: 0.96 }] }]}
              accessibilityRole="button"
            >
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>{preCert ? '인증 센터 ›' : '요청 보러 가기 ›'}</Text>
            </Pressable>
          </View>
        )}

        {/* [C①] 세 묶음. 머리줄은 §3b 그램마 그대로 (풀블리드 코랄 룰 + 20/800) — 앱의 다른 섹션
            머리줄과 같은 말투다. 비어 있는 묶음은 머리줄째 그리지 않는다.
            ⚠ [2026-09-15 정정] 이 자리에는 「fetchRunnerJobs는 여전히 scheduled_at DESC limit 20」
            이라는 문단이 있었고, 지난 묶음의 캡션은 그래서 「최근 20건 안에서」였다. **그 창은 더
            이상 없다**: api.ts:1477-1486 이 그 `.limit(20)` 을 「that stood here is GONE」 이라고
            적는다 (Sean 「keep everything」 · 콘솔 #17). 사용자는 존재하지 않는 창에 대한 면책
            문장을 읽고 있었고, 다음 세션은 삭제된 줄을 설명하는 주석을 읽게 돼 있었다 — 제거된
            코드를 인용하는 주석이 정확히 그 grep 을 속인다는 이 저장소의 법 그대로다.
            캡션은 이제 예정 묶음과 같은 말을 한다: 자기가 실제로 들고 있는 건수.
            ⚠ 남아 있는 진짜 천장은 다른 것이다 — PostgREST 의 서버 기본 상한(보통 1000). api.ts 의
            같은 주석이 그건 오늘의 문제가 아니라고 적어두었고, 그날의 해법은 페이지네이션이지
            되살린 창이 아니다. */}
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
              <Text style={s.dayGroupS}>{pastJobs.length}건</Text>
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
  // 리뷰 문 — 같은 뉴트럴 문법, 제 줄 전폭. 문 줄의 paddingBottom 안쪽에 들어가므로 위 여백만 준다.
  reviewDoor: {
    marginHorizontal: 10, marginBottom: 10, marginTop: -2,
    alignItems: 'center', justifyContent: 'center', paddingVertical: 14,
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
  },
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
