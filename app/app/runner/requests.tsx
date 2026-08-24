import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { TabSwipe } from '../../src/components/tabswipe';
import { DemandStrip } from '../../src/components/clubcard';
import { Avatar, Row } from '../../src/components/ui';
import { acceptBooking, acceptReschedule, AvailRule, declineReschedule, fetchMyAvailability, fetchMyRunnerStatus, fetchRescheduleRequests, fetchRunnerInbox, OpenRequest, RescheduleRequest } from '../../src/lib/api';
import { dangerousRefusalFrom } from '../../src/lib/dangerous-copy';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { layout, lilac, paper } from '../../src/theme';

// 요청 인박스 — deadlines, match score, conflict warnings (docs/calendar.md).
//
// [paper repaint 2026-08-11] forest/cream/volt chrome scrapped → paper. Cards go neutral
// #EEE sharp; the STATUS moves onto §3b chips (지명=amber tint, LIVE=green tint) on the
// datum's own row — the colored 2px card borders retired with the chrome. Accept doors
// use the home ticket's coral-door grammar (CORAL_INK fill, white 17/800) — the assigned
// state color for the accept action; busy = label swap, opacity tricks retired. Miller:
// each card keeps time → dog → payout → tags → memo → course → door, one chunk per row.
// Behavior frozen: accept/acceptReschedule/declineReschedule, focus reload, all routes.
//
// [journey v4 · R2a/R2b/R2c 2026-08-19] The lab's object grammar lands: a request is a thing
// the runner accepts, so it gets a 1.5px ink box (owner/request.tsx's RULING-5 nudge grammar),
// and everything that used to be a grey fill inside it (when-bar, memo plate, course box) goes
// back to type + a hairline. Three substantive changes beyond the dress:
//   1. ONE coral per frame. Every card's accept door used to be #C6472C — five requests meant
//      five climaxes and none. The single topmost ACTIONABLE door owns the coral now
//      (변경 요청 → 지명 → nothing); every other door is the ink-outline ghost. 근처(오픈) accepts
//      are never coral: "지명 먼저" is said in colour as well as in order (lab §B).
//   2. Money is one line, in place, in the dog's own row — the 18.5pt green payout column is
//      retired with the rest of the v4 money heroes (home hero, done receipt, earnings ticket).
//      The rate stops being printed: "수수료 제외" as words. 33% is a real column
//      (runners.commission_rate) — this is the lab's design choice, not a correction.
//   3. The empty state gains two REAL summary rows (온라인 from fetchMyRunnerStatus, 러닝 가능
//      시간 from fetchMyAvailability). A row that has not loaded renders nothing; a row that
//      failed says so quietly with a retry — never a default dressed up as an answer.
// NOT built from the lab: the "자세히 →" door (no open-request detail screen exists — a door to
// nowhere), the "홈 베이스에서 1.2km" line (OpenRequest has no pickup/distance field), and the
// "근처 요청 · 온라인일 때만" kicker — measured false: the open pool's gate is is_active_runner()
// (tier <> 'applicant', 0004:4-10), which never reads runners.online.

const CORAL_INK = '#C6472C';      // accept-door fill (white label holds ≥4.5:1)
const CORAL_INK_DEEP = '#B23E25';
const AMBER_BG = '#FDE8D0';       // pending/directed tint world (paper.pending family)
const AMBER_INK = '#9D580A';
const GREY_CHIP = '#F5F5F5';      // neutral chip fill (성향 태그 · 매칭 대기)

// "7월 31일 (목) 15:30" → ["7월 31일 (목)", "15:30"] — 시간을 1급 정보로 분리
const splitWhen = (w: string): [string, string] => {
  const i = w.lastIndexOf(' ');
  return i < 0 ? [w, ''] : [w.slice(0, i), w.slice(i + 1)];
};

const hhmm = (min: number) => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;

// 가용시간 한 줄 요약 — 규칙 행이 정본이다. 요일마다 시간이 다르면 시간을 지어내지 않고 그렇다고 말한다.
// [honesty 2026-08-19 · runner review P2] 빈 규칙 집합은 "설정한 적 없음"이 아니다:
// availability.tsx:85-89가 저장 전에 enabled만 남기므로, 모든 요일을 '쉬는 날'로 돌린 러너는
// **의도적으로** 빈 집합을 저장한다. 그 러너에게 '아직 설정 안 했어요'라고 말한 뒤 시간 조정 →을
// 열어주면 자기 설정이 그대로 있고, 둘 중 무엇을 믿어야 할지 알 수 없게 된다. 이 함수가 구분할 수
// 있는 사실은 '지금 켜진 요일이 없다' 하나뿐이므로 그것만 말한다 (로딩·실패는 호출부가 가른다).
const availSummary = (rules: AvailRule[]): string => {
  if (rules.length === 0) return '설정된 요일이 없어요';
  const same = rules.every((r) => r.startMin === rules[0].startMin && r.endMin === rules[0].endMin);
  return same
    ? `주 ${rules.length}일 · ${hhmm(rules[0].startMin)}–${hhmm(rules[0].endMin)}`
    : `주 ${rules.length}일 · 요일마다 다름`;
};

export default function Requests() {
  const df = useDisplayFont(); // display font — screen title (1/screen budget)
  const nf = useNumFont();     // Oswald — request times, payouts
  const [live, setLive] = useState<OpenRequest[]>([]);
  const [accepting, setAccepting] = useState<string | null>(null);
  // 일정 변경 요청 (0016) — 확정 예약의 새 시간 제안, 수락해야만 시간이 바뀐다
  const [resched, setResched] = useState<RescheduleRequest[]>([]);
  const [reschedBusy, setReschedBusy] = useState<string | null>(null);
  // 어느 **문**이 지금 동작 중인가 — bookingId만으로는 한 카드의 두 문(거절/수락)을 가를 수 없고,
  // 그러면 '동작 중이 아닌 문'을 정확히 비활성으로 그릴 수 없다 (아래 doorRow 참조).
  const [reschedAct, setReschedAct] = useState<'accept' | 'decline' | null>(null);
  // [적대 리뷰] busy는 확인 콜백 안에서야 켜진다 — 그 전 구간에 연타가 확인창을 쌓을 수 있었다.
  // 서버 CAS가 이중 커밋은 막지만, 중복 내비게이션과 '성공 뒤 실패' UI는 막지 못한다.
  const [asking, setAsking] = useState(false);
  const [reschedAsking, setReschedAsking] = useState(false);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "새 요청 0건 /
  // 지금은 열린 요청이 없어요" while loading AND on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  // [R2c] 빈 상태의 두 요약 행 — 인박스와 독립적으로 살고 죽는다. null = 아직 안 들어옴(그리지 않음).
  const [online, setOnline] = useState<boolean | null>(null);
  const [onlineErr, setOnlineErr] = useState(false);
  const [avail, setAvail] = useState<AvailRule[] | null>(null);
  const [availErr, setAvailErr] = useState(false);

  // 요약 두 줄도 매 로드마다 다시 읽는다 — '시간 조정 ›'으로 나갔다 돌아온 러너에게 옛 요약을 보여주지
  // 않으려면 포커스 리로드가 이 둘도 함께 끌어와야 한다 (빈 상태에서만 그려지지만, 빈 상태야말로 그
  // 출구가 있는 곳이다). 인박스와 **독립적으로** 실패한다 — 한쪽의 네트워크 오류가 다른 쪽을 지우지 않게.
  // ⚠ 별도 함수로 빼지 않는다: `load`가 컴포넌트 스코프의 다른 함수를 부르는 순간
  // exhaustive-deps가 `load`를 unstable로 보고 useFocusEffect에 새 에러를 만든다 (린트 베이스라인 6개 유지).
  const load = () => {
    setLoadErr(false);
    setOnlineErr(false);
    setAvailErr(false);
    // 실패하면 **값을 버린다**: 옛 값 옆에 실패 줄을 같이 그리면 둘 다 못 믿는 화면이 되고,
    // 옛 값만 조용히 남기면 그건 오래된 사실을 지금 사실로 파는 것이다. 하나의 행 = 하나의 상태.
    fetchMyRunnerStatus()
      .then((st) => setOnline(st.online))
      .catch((e) => { console.warn('[requests] status:', e?.message ?? e); setOnline(null); setOnlineErr(true); });
    fetchMyAvailability()
      .then(setAvail)
      .catch((e) => { console.warn('[requests] availability:', e?.message ?? e); setAvail(null); setAvailErr(true); });
    return Promise.all([
      fetchRunnerInbox().then(setLive),
      fetchRescheduleRequests().then(setResched),
    ]).then(() => setLoaded(true))
      .catch((e) => { console.warn('[requests] inbox:', e?.message ?? e); setLoadErr(true); });
  };
  // 화면에 돌아올 때마다 갱신 — 수락/완료된 요청 카드가 남지 않게
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // [2026-08-11] 여기는 한 번의 탭이 곧 커밋이었다. 수락은 **현실 세계의 약속**이다 — 그 시간에
  // 남의 개를 데리러 가겠다는 것이고, 동시에 다른 일에 쓸 수 있는 자리를 없앤다. 잘못 눌린 수락은
  // 보호자를 길에 세우거나 노쇼가 된다. 러너 홈의 티켓(home.tsx:182)은 이미 개·시각·실수령을
  // 보여주고 확인을 받는데, 정작 요청이 잔뜩 쌓이는 이 화면만 즉시 커밋이었다. 같은 계약으로 맞춘다.
  const accept = (req: OpenRequest) => {
    if (accepting || asking) return;
    setAsking(true);
    Alert.alert('요청 수락',
      // '실수령'은 확정 금액을 뜻한다 — 이 값은 api.ts:427의 **추정치**다 (실거리·수수료율로 서버가 확정).
      `${req.dogName} · ${req.when}\n예상 ${req.payout.toLocaleString()}원 (실거리로 확정) — 수락할까요?\n수락하면 이 시간에 갈 사람은 나예요.`,
      [
        { text: '아직', style: 'cancel', onPress: () => setAsking(false) },
        { text: '수락', style: 'default', onPress: () => { setAsking(false); void commitAccept(req); } },
      ]);
  };
  const commitAccept = async (req: OpenRequest) => {
    setAccepting(req.bookingId);
    try {
      await acceptBooking(req.bookingId);
      haptic('success');
      runnerJob.bookingId = req.bookingId;
      Alert.alert('수락 완료', '보호자에게 수락 알림이 전송되었어요');
      router.push('/runner/meetup');
    } catch (e) {
      // [0119] 맹견 게이트는 배정·수락에서도 뜬다 (F1). 러너에게는 고칠 수 있는 일이 없으므로
      // 문 없는 사실 하나만 말한다 — 「수락 실패 · dog_dangerous_undeclared」로 내보내면
      // 러너는 자기가 뭘 잘못했는지 찾다가 재시도만 반복한다.
      const refusal = dangerousRefusalFrom(e, 'runner');
      if (refusal) { Alert.alert(refusal.title, refusal.body); load(); return; }
      Alert.alert('수락 실패', (e as Error).message);
      load();
    } finally {
      setAccepting(null);
    }
  };

  // 지명 먼저 — fetchRunnerInbox가 이미 directed를 앞에 붙여 오지만, 코랄 예산을 계산하려면
  // 두 레그를 이름으로 갈라놔야 한다 (섞인 배열의 '첫 항목'은 예산의 근거가 못 된다).
  const directed = live.filter((r) => r.directed);
  const nearby = live.filter((r) => !r.directed);
  // 화면당 코랄 하나 (DESIGN §5) — **지금 눌러야 할 문 하나**가 가진다.
  // 변경 요청 > 지명 요청 > 없음. 변경 요청이 이기는 이유: 그건 새 일이 아니라 **이미 확정된 약속의
  // 시간**이 흔들리는 중이라 답을 미룰수록 비싸다 (lab R2b). 근처(오픈) 요청의 수락은 절대 코랄이
  // 아니다 — 지명이 없을 때도 그렇다. 코랄 0인 화면은 합법이다 (lab R2c).
  const coralResched = resched.length > 0 ? resched[0].bookingId : null;
  const coralDirected = coralResched === null && directed.length > 0 ? directed[0].bookingId : null;

  const renderRequest = (req: OpenRequest) => {
    const [wd, wt] = splitWhen(req.when);
    const coral = req.bookingId === coralDirected;
    // 다른 문이 동작 중이라 이 문은 눌러도 아무 일이 없다 — 그렇게 **보이게** 그린다
    // (theme.ts:206 매트릭스: disabled = disabledFill + faint, 불투명도 트릭 금지).
    const inert = accepting !== null && accepting !== req.bookingId;
    // [0114 residual · docs/contracts/party-membership-status-filter-contract.md §C.6]
    // `directed`는 곧 서버 상태 'runner_pending'이다 (api.ts fetchRunnerInbox의 지명 레그는
    // .eq('status','runner_pending')로만 읽는다). 수락 **전**의 지명 카드에는 보호자가 작성한
    // 자유 텍스트를 렌더하지 않는다: dogs.memo, dogs.preferences.tags[], bookings.pace_label은
    // 전부 무검증 통과 값이고, 0114가 채팅·리뷰·알림을 닫은 뒤에도 지명 하나로 낯선 러너에게
    // 닿는 잔여 경로다. 이름·견종·체중·백신은 남는다 — 러너가 수락 여부를 판단하는 정보이고,
    // 케어 지시(메모)는 수락한 러너의 잡 화면에서 볼 것이다. 오픈 풀(matching) 카드는 그대로.
    const preAccept = !!req.directed;
    return (
      <View key={req.bookingId} style={s.reqCard}>
        <View style={s.cardBody}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
            {/* §3b status chip — the request's nature, 16/800 tinted, no border.
                오픈 요청은 라일락(매칭 대기 = 기다림의 색). 예전 초록 '● LIVE 요청'은 은퇴 —
                초록은 이 팔레트에서 '준비됨'이고, 아직 아무도 배정되지 않은 요청은 준비된 게 아니다. */}
            <View style={[s.chip, { backgroundColor: req.directed ? AMBER_BG : GREY_CHIP }]}>
              <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: req.directed ? AMBER_INK : lilac.accent }}>
                {req.directed ? '★ 지명 요청' : '● 요청 · 매칭 대기'}
              </Text>
            </View>
            {req.repeatPrior != null && req.repeatPrior > 0 && (
              <View style={[s.metaChip, { backgroundColor: AMBER_BG }]}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: AMBER_INK }}>⟳ {req.repeatPrior + 1}번째 함께</Text>
              </View>
            )}
          </Row>
          {/* 언제 뛰는가 — 요청의 1급 정보 (회색 각주 은퇴, 정보 위계 수정 2026-07-28).
              [v4] 회색 바 은퇴 — 잉크 상자 안에서 회색 면은 소음이다. 활자가 위계를 진다. */}
          <Row style={s.whenRow}>
            <Text style={{ fontSize: 14.5, fontWeight: '800', color: paper.text }}>{wd}</Text>
            {/* Oswald request time — lineHeight 27 = 1.29× (BUG A) */}
            <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{wt}</Text>
          </Row>
          <Row style={{ gap: 12, marginTop: 10 }}>
            <Avatar url={req.photoUrl} char={req.dogName[0]} bg={paper.ink} size={48} />
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 18, fontWeight: '800', color: paper.ink }}>
                {req.dogName} · {req.breed} {req.weightKg}kg
              </Text>
              {/* 돈은 한 줄 — 개의 줄 안에서, 사실로. Oswald 숫자 lineHeight 19 = 1.27× (BUG A).
                  '예상'은 장식이 아니라 계약이다: 이 값은 견적이고 실거리·수수료율로 서버가 확정한다.
                  요율(33%)은 인쇄하지 않는다 — 실컬럼이지만 러너의 결정에 들어가는 수는 실수령이다. */}
              <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3, lineHeight: 19 }}>
                <Text style={{ fontWeight: '800', color: paper.ink }}>{req.km}km</Text>
                {preAccept ? '' : ` · ${req.paceLabel}`} · 예상{' '}
                <Text style={[{ fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 19, fontVariant: ['tabular-nums'] as const }, nf]}>
                  {req.payout.toLocaleString()}
                </Text>
                원 · 수수료 제외
              </Text>
            </View>
          </Row>
          {(req.vaccines.length > 0 || (!preAccept && req.prefTags.length > 0)) && (
            <Row style={{ gap: 5, marginTop: 9, flexWrap: 'wrap' }}>
              {req.vaccines.length > 0 && (
                <View style={[s.metaChip, { backgroundColor: '#E3EFF9' }]}>
                  <Text style={{ fontSize: 14, fontWeight: '700', color: '#2D6DA8' }}>백신 {req.vaccines.length}종</Text>
                </View>
              )}
              {!preAccept && req.prefTags.map((t) => (
                <View key={t} style={[s.metaChip, { backgroundColor: GREY_CHIP }]}>
                  <Text style={{ fontSize: 14, fontWeight: '700', color: paper.text }}>{t}</Text>
                </View>
              ))}
            </Row>
          )}
          {req.memo && !preAccept && (
            <View style={s.memo}>
              <Text style={{ fontSize: 14.5, color: paper.text, lineHeight: 20 }} numberOfLines={2}>메모: {req.memo}</Text>
            </View>
          )}
          {/* 코스 미리보기 — 수락 전에 코스를 알고 결정한다 (트레이스·지형·점검일).
              라벨은 잉크: 이 화면의 코랄은 문 하나가 가진다. 코스 이름은 원문 그대로 (§6 정본). */}
          {req.routeId && req.routeName && (
            <Pressable
              onPress={() => router.push(`/course/${req.routeId}`)}
              style={({ pressed }) => [s.courseRow, pressed && { backgroundColor: paper.wash }]}
            >
              <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink, flex: 1 }} numberOfLines={1}>{req.routeName}</Text>
              <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink, marginLeft: 10 }}>코스 미리보기 ›</Text>
            </Pressable>
          )}
        </View>
        <View style={s.doorRow}>
          <Pressable
            style={({ pressed }) => [
              coral ? s.doorPrimary : s.doorGhost,
              inert && s.doorOff,
              !inert && pressed && (coral ? { backgroundColor: CORAL_INK_DEEP } : { backgroundColor: paper.wash }),
              !inert && pressed && { transform: [{ scale: 0.97 }] },
            ]}
            disabled={accepting !== null}
            accessibilityState={{ disabled: accepting !== null }}
            onPress={() => accept(req)}
          >
            <Text style={{ fontSize: 17, fontWeight: '800', color: inert ? paper.faint : coral ? '#FFFFFF' : paper.ink }}>
              {accepting === req.bookingId ? '수락 중...' : '수락하기 ›'}
            </Text>
          </Pressable>
        </View>
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
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
            <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>요청</Text>
            <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3 }}>
              {/* count only after a real load — never "0건" in flight or on failure */}
              {!loaded
                ? loadErr ? '요청을 불러오지 못했어요' : '요청 확인 중...'
                : `새 요청 ${live.length}건${resched.length > 0 ? ` · 변경 요청 ${resched.length}건` : ''}`}
            </Text>
          </View>
          <Pressable style={({ pressed }) => [s.refreshChip, pressed && { backgroundColor: paper.wash }]} onPress={load}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>↻ 새로고침</Text>
          </Pressable>
        </Row>

        {/* ---------- 하이클럽 호스트 수요 스트립 (R1-C, 0032) — 호스트 = 또 하나의 동네 일감.
            대기 팀이 있을 때만 나타난다 (유령 클럽 금지) ---------- */}
        <View style={{ marginTop: 12 }}>
          <DemandStrip />
        </View>

        {/* ---------- 일정 변경 요청 (0016) — 기존→새 시간, 수락/거절 ---------- */}
        {resched.map((rq) => {
          const coral = rq.bookingId === coralResched;
          // 동작 중인 문은 정확히 하나다 (그 카드 × 그 액션). 나머지는 전부 눌러도 아무 일이
          // 없으므로 disabled 필로 내려간다 — 다섯 장이 떠 있을 때 한 장을 누르면 나머지 여덟
          // 개의 문이 온전한 무게로 남아 "눌리는 문"을 사칭하던 상태를 없앤다.
          const busyHere = reschedBusy === rq.bookingId;
          const declineOff = reschedBusy !== null && !(busyHere && reschedAct === 'decline');
          const acceptOff = reschedBusy !== null && !(busyHere && reschedAct === 'accept');
          return (
            <View key={`rs-${rq.bookingId}`} style={s.reqCard}>
              <View style={s.cardBody}>
                {/* §3b status chip — amber pending, beside its subject */}
                <View style={[s.chip, { backgroundColor: AMBER_BG, alignSelf: 'flex-start' }]}>
                  <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: AMBER_INK }}>일정 변경 요청</Text>
                </View>
                <Text style={{ fontSize: 17, fontWeight: '800', color: paper.ink, marginTop: 10 }}>
                  {rq.dogName} · {rq.km}km
                </Text>
                <Row style={{ gap: 8, marginTop: 8, alignItems: 'center' }}>
                  <View style={s.timeBox}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: paper.dim }}>기존</Text>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: paper.dim, textDecorationLine: 'line-through', marginTop: 1 }}>
                      {rq.curDate}
                    </Text>
                    <Text style={{ fontSize: 17, fontWeight: '800', color: paper.dim, textDecorationLine: 'line-through' }}>
                      {rq.curTime}
                    </Text>
                  </View>
                  <Text style={{ fontSize: 17, fontWeight: '900', color: AMBER_INK }}>→</Text>
                  <View style={[s.timeBox, { backgroundColor: AMBER_BG }]}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: AMBER_INK }}>제안</Text>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: AMBER_INK, marginTop: 1 }}>{rq.newDate}</Text>
                    <Text style={{ fontSize: 17, fontWeight: '900', color: AMBER_INK }}>{rq.newTime}</Text>
                  </View>
                </Row>
              </View>
              <View style={s.doorRow}>
                {/* busy = label swap on the acting door; both disabled while one is in flight.
                    거절(기존 유지)은 고스트지만 약한 문이 아니다 — 내 캘린더를 지키는 쪽이
                    눈에 안 띄면 그건 넛지가 아니라 함정이다. 둘 다 같은 크기·같은 테두리. */}
                <Pressable
                  style={({ pressed }) => [
                    s.doorGhost,
                    declineOff && s.doorOff,
                    !declineOff && pressed && { backgroundColor: paper.wash, transform: [{ scale: 0.97 }] },
                  ]}
                  disabled={reschedBusy !== null}
                  accessibilityState={{ disabled: reschedBusy !== null }}
                  onPress={async () => {
                    setReschedBusy(rq.bookingId);
                    setReschedAct('decline');
                    try { await declineReschedule(rq.bookingId); haptic('light'); load(); }
                    catch (e) { Alert.alert('처리 실패', (e as Error).message); }
                    finally { setReschedBusy(null); setReschedAct(null); }
                  }}
                >
                  <Text style={{ fontSize: 17, fontWeight: '800', color: declineOff ? paper.faint : paper.ink }}>
                    {busyHere && reschedAct === 'decline' ? '처리 중...' : '거절 (기존 유지)'}
                  </Text>
                </Pressable>
                <Pressable
                  style={({ pressed }) => [
                    coral ? s.doorPrimary : s.doorGhost,
                    acceptOff && s.doorOff,
                    !acceptOff && pressed && (coral ? { backgroundColor: CORAL_INK_DEEP } : { backgroundColor: paper.wash }),
                    !acceptOff && pressed && { transform: [{ scale: 0.97 }] },
                  ]}
                  disabled={reschedBusy !== null}
                  accessibilityState={{ disabled: reschedBusy !== null }}
                  /* 같은 법: 이건 **이미 확정된 약속의 시간을 바꾸는** 커밋이다. 한 번의 탭으로
                     내 캘린더가 조용히 옮겨가면 안 된다 — 옛 시간과 새 시간을 다시 보여주고 묻는다. */
                  onPress={() => {
                    if (reschedBusy || reschedAsking) return;   // 확인창이 겹쳐 쌓이는 것도 막는다
                    setReschedAsking(true);
                    Alert.alert('새 시간 수락',
                      `${rq.dogName} · ${rq.km}km\n${rq.curDate} ${rq.curTime} → ${rq.newDate} ${rq.newTime}\n이 시간으로 바꿀까요?`,
                      [
                        { text: '아직', style: 'cancel', onPress: () => setReschedAsking(false) },
                        { text: '수락', style: 'default', onPress: async () => {
                          setReschedAsking(false);
                          setReschedBusy(rq.bookingId);
                          setReschedAct('accept');
                          try {
                            await acceptReschedule(rq.bookingId);
                            haptic('success');
                            Alert.alert('변경 수락', '일정이 새 시간으로 변경됐어요 — 캘린더에 반영됩니다');
                            load();
                          } catch (e) { Alert.alert('수락 실패', (e as Error).message); load(); }
                          finally { setReschedBusy(null); setReschedAct(null); }
                        } },
                      ]);
                  }}
                >
                  <Text style={{ fontSize: 17, fontWeight: '800', color: acceptOff ? paper.faint : coral ? '#FFFFFF' : paper.ink }}>
                    {busyHere && reschedAct === 'accept' ? '처리 중...' : '새 시간 수락 ›'}
                  </Text>
                </Pressable>
              </View>
            </View>
          );
        })}

        {/* ---------- 실시간 요청 (Supabase) — 지명 먼저, 근처는 그 아래 ---------- */}
        {directed.map(renderRequest)}
        {nearby.map(renderRequest)}

        {!loaded && !loadErr && (
          <View style={s.stateBlock}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>요청 인박스를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && live.length === 0 && resched.length === 0 && (
          <>
            <View style={s.stateBlock}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink, textAlign: 'center' }}>지금은 열린 요청이 없어요</Text>
              <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', marginTop: 4 }}>새 요청이 오면 여기에 표시돼요</Text>
            </View>
            {/* ---------- 조용한 날의 두 줄 — 왜 조용한지 러너가 스스로 볼 수 있게.
                둘 다 실필드다: runners.online · runner_availability_rules.
                아직 안 들어온 행은 **그리지 않는다** (기본값을 답으로 위장하지 않는다). ---------- */}
            <View style={s.sumGroup}>
              {online !== null && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>온라인</Text>
                  <Text style={s.sumValue}>{online ? '켜짐' : '꺼짐'}</Text>
                </Row>
              )}
              {onlineErr && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>온라인</Text>
                  <Text style={s.sumState}>상태를 불러오지 못했어요</Text>
                  <Pressable onPress={load} style={s.sumRetry} accessibilityRole="button">
                    <Text style={s.sumAction}>다시 시도</Text>
                  </Pressable>
                </Row>
              )}
              {avail !== null && (
                <Pressable
                  onPress={() => router.push('/runner/availability')}
                  style={({ pressed }) => [s.sumRow, pressed && { backgroundColor: paper.wash }]}
                >
                  <Text style={s.sumLabel}>러닝 가능 시간</Text>
                  <Text style={s.sumValue}>{availSummary(avail)}</Text>
                  <Text style={s.sumAction}>시간 조정 ›</Text>
                </Pressable>
              )}
              {availErr && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>러닝 가능 시간</Text>
                  <Text style={s.sumState}>불러오지 못했어요</Text>
                  <Pressable onPress={load} style={s.sumRetry} accessibilityRole="button">
                    <Text style={s.sumAction}>다시 시도</Text>
                  </Pressable>
                </Row>
              )}
            </View>
          </>
        )}

        <View style={s.note}>
          <Text style={{ fontSize: 14, lineHeight: 20, color: paper.dim, textAlign: 'center' }}>
            수락하면 캘린더에 확정 일정으로 추가돼요{'\n'}응답 기한이 지나면 요청은 자동 만료됩니다
          </Text>
        </View>
      </ScrollView>
      </TabSwipe>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  refreshChip: { backgroundColor: paper.canvas, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: paper.line, alignSelf: 'flex-start' },
  // [v4] 요청 = 러너가 수락하는 **오브젝트**라 잉크 1.5px 상자를 받는다
  // (owner/request.tsx:1341 코스 넛지와 같은 문법). 안쪽 회색 면들은 전부 은퇴 — 상자 안의
  // 상자는 위계를 만들지 못하고 소음만 만든다.
  reqCard: { backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: paper.ink, marginTop: 14 },
  cardBody: { padding: 14, paddingBottom: 12 },
  chip: { borderRadius: 0, paddingVertical: 4, paddingHorizontal: 9 },
  metaChip: { borderRadius: 0, paddingVertical: 3, paddingHorizontal: 8 },
  // 메모 — 회색 면 대신 왼쪽 규칙선 (보호자의 목소리를 인용문처럼)
  memo: { borderLeftWidth: 2, borderLeftColor: '#EEEEEE', paddingLeft: 9, marginTop: 9 },
  whenRow: { justifyContent: 'space-between', alignItems: 'baseline', marginTop: 10 },
  courseRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderTopWidth: 1, borderTopColor: '#EEEEEE',
    marginTop: 12, paddingTop: 12, minHeight: 44,
  },
  timeBox: { flex: 1, backgroundColor: '#F7F7F7', paddingVertical: 7, paddingHorizontal: 10 },
  doorRow: { flexDirection: 'row', gap: 8, paddingHorizontal: 12, paddingBottom: 12 },
  // 코랄 문 — 화면당 하나. CORAL_INK fill, 흰 라벨 17/800 (4.84:1), 샤프.
  doorPrimary: {
    flex: 1, backgroundColor: CORAL_INK, borderWidth: 1.5, borderColor: CORAL_INK,
    alignItems: 'center', justifyContent: 'center', paddingVertical: 14, minHeight: 48,
  },
  // 고스트 문 — 캔버스 + 잉크 1.5px 윤곽 + 잉크 라벨. 코랄 예산 밖의 모든 문이 이것이다.
  // (theme.ts:205의 세컨더리 매트릭스는 wash+코랄 라인이지만, 그 문법을 여러 문에 쓰면
  //  화면에 코랄이 대여섯 개가 된다 — v4 랩의 doorB(잉크 윤곽)를 따른다.)
  doorGhost: {
    flex: 1, backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: paper.ink,
    alignItems: 'center', justifyContent: 'center', paddingVertical: 14, minHeight: 48,
  },
  // 비활성 문 — theme.ts:206 매트릭스의 disabled 항 (disabledFill + faint 라벨, 알파 금지).
  // 코랄 문에도 그대로 얹힌다: 동작 중이 아닌 문은 그 프레임의 코랄 예산도 쓰지 않는다.
  doorOff: { backgroundColor: paper.disabledFill, borderColor: '#EEEEEE' },
  // 로딩·빈 상태 — 상자 없이 활자만 (빈 인박스에 테두리를 그리면 없는 내용에 무게가 생긴다)
  stateBlock: { marginTop: 40, paddingHorizontal: 10, alignItems: 'center' },
  // ── R2c 요약 행 — owner/request.tsx의 prefRow 문법 (딤 라벨 왼쪽 · 굵은 값 오른쪽 · 잉크 액션) ──
  sumGroup: { marginTop: 40, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  sumRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
    minHeight: 52,   // 44pt 터치 타깃 이상
  },
  sumLabel: { fontSize: 14, color: paper.dim, width: 110 },
  sumValue: { fontSize: 15, fontWeight: '800', color: paper.ink, flex: 1, textAlign: 'right' },
  // 값이 아니라 **상태**를 말하는 자리 — 굵은 잉크로 그리면 답으로 읽힌다
  sumState: { fontSize: 14, color: paper.dim, flex: 1, textAlign: 'right' },
  sumAction: { fontSize: 14, fontWeight: '800', color: paper.ink, marginLeft: 10 },
  sumRetry: { minHeight: 44, justifyContent: 'center' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { marginTop: 24, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  note: { marginTop: 18, padding: 10 },
});
