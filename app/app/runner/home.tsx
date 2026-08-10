import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { CourseStrip } from '../../src/components/CourseStrip';
import { RunnerClubCard } from '../../src/components/clubcard';
import { Icon, Row } from '../../src/components/ui';
import {
  acceptBooking, AvailRule, CoursePatch, declineBooking, fetchBookingAddress, fetchCoursePatches, fetchLedgerMonth, fetchLedgerTotal, fetchMyAvailability, fetchMyName, fetchMyRunnerStatus, fetchRunnerInbox, fetchRunnerJobs,
  fetchRunnerWeekStats, fetchUnreadCount, MyRunnerStatus, OpenRequest, PickupAddress, RunnerJob, RunnerWeekStats, saveMyAvailability, setRunnerOnline,
} from '../../src/lib/api';
import { PatchBadge } from '../../src/components/patch';
import { registerPushToken } from '../../src/lib/push';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { colors, layout, lilac, paper } from '../../src/theme';

// 러너 홈 — 테일러드 라일락 리페인트 (빕 퍼스트 × 정산 장부 × 클럽 엔진).
// 컬러 월드 결정: DAWN DUAL — 코랄이 정체성·CTA(빕 토글·수락 문·라이브), 바이올렛이 구조·클럽.
// 로직은 동결: 모든 훅·데이터 페치·핸들러·라우터 타깃·조건 가드 보존, JSX/StyleSheet만 재도색.
// 2026-08-03 스케일 교정 라운드 (Sean 디바이스): 타입/스페이싱을 runner-FINAL.html 목업 px에 1:1 정합
// (그랜마폰 ~1.75x 과대 제거). 빕 대형숫자 고정폭 열·₩+금액 baseline+gap 오버랩 픽스는 유지, 사이즈만 목업으로.
// 2026-08-03 정밀 픽스 라운드 (FIX3): BUG A — 모든 대형 Oswald 숫자에 lineHeight ≥1.2×fontSize,
// includeFontPadding:false 제거 (0의 상단 잘림 "UU"/"₩U" 픽스). 히어로/빅넘버 크기는 동결.
// 2026-08-10 type/density wave: FIX3's private "11.5pt floor" is RETIRED — the governing law is the
// 14pt detail-text floor (DESIGN.md §3). Only latin letterspaced caps kickers, serial/MRZ strings and
// barcode/glyph-only marks stay below it; Korean data never rides a kicker style.

const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const DAY_NAME = '일월화수목금토';
const hh = (m: number) => String(Math.floor(m / 60)).padStart(2, '0');

// 코랄-텍스트 법: 흰 텍스트는 오직 어두운 터미널 스톱(≥ #C6472C, 백지 4.84:1) 위에.
// 밝은 --coral(#F0765A)은 fill/edge/dot·글로우 섀도로만 생존, 절대 그 위에 흰 소자 텍스트 금지.
const CORAL_INK = '#C6472C';
const CORAL_INK_DEEP = '#B23E25';

const TIER_LABEL: Record<string, string> = { certified: '인증 러너', veteran: '베테랑', master: '마스터' };

// 세션 동안 거절한 요청 id — 오픈 풀로 되돌아와도 내 큐에 재등장하지 않게 (모듈 레벨: 리마운트 생존)
const declinedIds = new Set<string>();

// 진행 단계 메타 — 서버 상태 → 러너가 지금 뭘 해야 하는지 (라벨·액션 동결, 색만 라일락으로 재매핑)
const STAGE: Record<string, { label: string; action: string; color: string }> = {
  confirmed: { label: '픽업 대기', action: '픽업 이동 시작 ›', color: lilac.amber },
  runner_enroute: { label: '픽업 이동 중', action: '인계 화면으로 ›', color: lilac.amber },
  picked_up: { label: '인계 완료 · 시작 대기', action: '러닝 시작하기 ›', color: lilac.voltDeep }, // 확인/성공 볼트만 기능적
  active: { label: '러닝 중 · LIVE', action: '러닝 화면으로 ›', color: CORAL_INK },
};

// [정직 배치 2026-08-06 · item 4 wave-1] 픽업 지도 숏컷 은퇴 — 목업 좌표로 길을 안내하던 버튼이었다.
// 실주소는 wave 3(러너용 definer RPC)에서 오고, 그 전까진 버튼 자리 자체가 없다 (죽은 버튼 금지법).

// 파동 링 — 긴급/도착 신호. 링 두 개가 900ms 간격으로 퍼져나간다 (네이티브 드라이버)
function PulseRings({ color = colors.tang, size = 30 }: { color?: string; size?: number }) {
  const a1 = useRef(new Animated.Value(0)).current;
  const a2 = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const mk = (v: Animated.Value, delay: number) => Animated.loop(Animated.sequence([
      Animated.delay(delay),
      Animated.timing(v, { toValue: 1, duration: 1800, easing: Easing.out(Easing.quad), useNativeDriver: true }),
    ]));
    const l1 = mk(a1, 0);
    const l2 = mk(a2, 900);
    l1.start(); l2.start();
    return () => { l1.stop(); l2.stop(); };
  }, [a1, a2]);
  const ring = (v: Animated.Value) => (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', width: size, height: size, borderRadius: size / 2,
        borderWidth: 1.5, borderColor: color,
        opacity: v.interpolate({ inputRange: [0, 0.15, 1], outputRange: [0, 0.85, 0] }),
        transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [0.45, 1.6] }) }],
      }}
    />
  );
  return <>{ring(a1)}{ring(a2)}</>;
}

// 홀로 상단 엣지 — 3px 포일 트림 (빕·장부·티켓·스텁). 포일 예산: 모노그램 + 카드 엣지만.
const HOLO = ['#CFC4FF', '#FFD9CB', '#F3E9C6', '#EAF6C8', '#CFE0FF'];
function HoloEdge() {
  // [페이퍼 크롬 2026-08-10] radius 프롭 은퇴 — 모든 카드가 샤프라 라운드 홀로 엣지 변형이 사라졌다
  return (
    <View style={styles.holo}>
      {HOLO.map((c, i) => <View key={i} style={{ flex: 1, backgroundColor: c }} />)}
    </View>
  );
}

// 바코드 푸터 — 러너 빕/티켓 스톱마크 (목업 barcode height 14)
const BAR_W = [2, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1, 2, 1, 1, 3, 1, 2, 2, 1, 3, 1, 2, 1, 1, 2, 3, 1, 2, 1];
function Barcode({ width = 120 }: { width?: number }) {
  return (
    <View style={{ height: 14, width, flexDirection: 'row', alignItems: 'stretch', overflow: 'hidden', opacity: 0.82 }}>
      {BAR_W.map((w, i) => (
        <View key={i} style={{ width: w, marginRight: i % 3 === 0 ? 2.5 : 1.5, backgroundColor: i % 2 ? 'transparent' : lilac.head }} />
      ))}
    </View>
  );
}

// 섹션 룰 — 에디토리얼 순차 넘버 (01→06)
function SectionRule({ no, title, link, onPress }: { no: string; title: string; link?: string; onPress?: () => void }) {
  // [페이퍼 크롬] 섹션 분리 = 풀블리드 솔리드 코랄 1px — 거터를 음수 마진으로 뚫어 화면 끝까지 (paper.line 법)
  return (
    <Row style={[styles.secWrap, { alignItems: 'center', gap: 8, marginTop: 14 }]}>
      <Text style={styles.srNo}>{no}</Text>
      <Text style={styles.srTitle}>{title}</Text>
      <View style={styles.rule} />
      {link ? <Pressable onPress={onPress}><Text style={styles.srLink}>{link}</Text></Pressable> : null}
    </Row>
  );
}

// 캡션 헤더 — 넘버 없는 섹션 (진행중·클럽)
function CapHead({ title, link, onPress }: { title: string; link?: string; onPress?: () => void }) {
  return (
    <Row style={[styles.secWrap, { alignItems: 'center', gap: 8, marginTop: 14 }]}>
      <Text style={styles.srTitle}>{title}</Text>
      <View style={styles.rule} />
      {link ? <Pressable onPress={onPress}><Text style={styles.srLink}>{link}</Text></Pressable> : null}
    </Row>
  );
}

// 장부 점선 리더 행 — 좌 라벨 · 점선 리더 · 우 값
function LedgerRow({ label, sub, value, unit, nf, total }: {
  label: string; sub: string; value: string; unit: string; nf: TextStyle | null; total?: boolean;
}) {
  return (
    <Row style={[styles.lr, total && { borderBottomWidth: 0 }]}>
      <View style={{ width: 86 }}>
        <Text style={styles.lrLabel}>{label}</Text>
        <Text style={styles.lrSub}>{sub}</Text>
      </View>
      <View style={styles.lead} />
      <Text style={styles.lrVal}>
        <Text style={[styles.lrValNum, nf, total && { fontSize: 15 }]}>{value}</Text>{unit}
      </Text>
    </Row>
  );
}

export default function RunnerHome() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면당 1회 (빕 네임)
  const nf = useNumFont();     // 숫자 서체 — Oswald tabular
  const [inbox, setInbox] = useState<OpenRequest[]>([]);
  const [name, setName] = useState<string | null>(null);
  const [stats, setStats] = useState<RunnerWeekStats>({ net: 0, runs: 0, km: 0 });
  // 장부 넓은 창 — 이번 달(KST 월 1일~) · 누적(정산 예정 총액). 로드 전엔 null → '—' (0원 위장 금지)
  const [monthNet, setMonthNet] = useState<number | null>(null);
  const [totalNet, setTotalNet] = useState<number | null>(null);
  const [unread, setUnread] = useState(0); // 미읽음 알림 실카운트 — 벨 도트의 유일한 근거
  const [jobs, setJobs] = useState<RunnerJob[]>([]);
  const [patchMap, setPatchMap] = useState<Record<string, CoursePatch>>({}); // 완료 카드 미니 패치
  // [honesty repair 2026-08-08 / plan §6.1-2, §6.3] The seed used to be tier: 'certified' — the same
  // lie fetchMyRunnerStatus told one layer down, and it painted 인증 러너 on the bib of an applicant
  // before any fetch resolved. null = not known yet / no runners row; a separate loaded flag keeps
  // "not arrived" distinct from "known to be nothing" (loading is not empty).
  const [rs, setRs] = useState<MyRunnerStatus>({ totalRuns: 0, totalKm: 0, online: false, tier: null });
  const [rsLoaded, setRsLoaded] = useState(false);
  const [rsErr, setRsErr] = useState(false);
  const [avail, setAvail] = useState<AvailRule[] | null>(null);
  const [busyReq, setBusyReq] = useState(false); // 티켓 문 실동작 중 (수락/거절)
  // 진행 중 카드의 픽업 주소 한 줄 (0060 definer RPC). 서버가 행을 준 경우에만 채워진다 —
  // 0행(주소 미지정·24h 창 밖)과 에러는 둘 다 null로 접고 카드에 아무 줄도 그리지 않는다.
  const [jobAddr, setJobAddr] = useState<PickupAddress | null>(null);

  // [Sean] 거절한 요청은 다시 안 본다 — 서버 정본은 0056 booking_declines(뷰 제외). 이 Set은 거절 POST와
  // 다음 fetch 사이 깜빡임을 막는 낙관 레이어 + 로그 기록 실패(엣지 fn fail-open)의 폴백.
  // ⚠ 오픈 레그만 거른다 — 지명 레그(directed)까지 거르면 '거절 후 보호자가 다시 콕 집은' 정당한
  // 재지명이 영영 안 보여 만료까지 썩는다 (0056이 일부러 살려둔 경로 — 적대 리뷰 P1).
  const filterDeclined = (list: OpenRequest[]) => list.filter((r) => r.directed || !declinedIds.has(r.bookingId));

  // [실동작] 홈 티켓의 수락/거절 — 라벨만 있고 요청함으로 도망가던 문을 진짜 문으로.
  const reloadQueue = () => {
    fetchRunnerInbox().then((l) => setInbox(filterDeclined(l))).catch((e) => console.warn('[rhome] inbox:', e?.message ?? e));
    fetchRunnerJobs().then(setJobs).catch((e) => console.warn('[rhome] jobs:', e?.message ?? e));
  };
  const acceptFront = () => {
    const rq = inbox[0];
    if (!rq || busyReq) return;
    Alert.alert('요청 수락', `${rq.dogName} · ${rq.when}\n${rq.payout.toLocaleString()}원 실수령 — 수락할까요?`, [
      { text: '아직', style: 'cancel' },
      {
        text: '수락', style: 'default',
        onPress: async () => {
          setBusyReq(true);
          try {
            await acceptBooking(rq.bookingId);
            haptic('success');
            Alert.alert('수락 완료 🏁', '보호자에게 알림이 갔어요 — 오늘의 루트에 올라갑니다');
            reloadQueue();
          } catch (e) {
            Alert.alert('수락 실패', (e as Error).message);
          } finally { setBusyReq(false); }
        },
      },
    ]);
  };
  const declineFront = () => {
    const rq = inbox[0];
    if (!rq || busyReq) return;
    // 오픈 브로드캐스트엔 '거절' 개념이 없다 (안 받으면 그만) — 상세만 안내. 지명만 실거절.
    if (!rq.directed) { router.push('/runner/requests'); return; }
    Alert.alert('지명 거절', '이 요청을 다른 러너에게 넘길까요?\n보호자에게는 재탐색 알림이 가요.', [
      { text: '유지', style: 'cancel' },
      {
        text: '거절', style: 'destructive',
        onPress: async () => {
          setBusyReq(true);
          try {
            await declineBooking(rq.bookingId);
            declinedIds.add(rq.bookingId);
            haptic('light');
            reloadQueue();
          } catch (e) {
            Alert.alert('거절 실패', (e as Error).message);
          } finally { setBusyReq(false); }
        },
      },
    ]);
  };

  useFocusEffect(useCallback(() => {
    fetchMyAvailability().then(setAvail).catch((e) => console.warn('[rhome] avail:', e?.message ?? e));
    fetchRunnerInbox().then((l) => setInbox(filterDeclined(l))).catch((e) => console.warn('[rhome] inbox:', e?.message ?? e));
    fetchMyName().then(setName).catch(() => {});
    fetchRunnerWeekStats().then(setStats).catch((e) => console.warn('[rhome] stats:', e?.message ?? e));
    fetchLedgerMonth().then(setMonthNet).catch((e) => console.warn('[rhome] month:', e?.message ?? e));
    fetchLedgerTotal().then(setTotalNet).catch((e) => console.warn('[rhome] total:', e?.message ?? e));
    fetchUnreadCount().then(setUnread).catch((e) => console.warn('[rhome] unread:', e?.message ?? e));
    fetchRunnerJobs().then(setJobs).catch((e) => console.warn('[rhome] jobs:', e?.message ?? e));
    fetchCoursePatches()
      .then(({ earned }) => setPatchMap(Object.fromEntries(earned.map((pt) => [pt.routeId, pt]))))
      .catch(() => {});
    registerPushToken(); // APNs (0024) — 러너는 푸시가 곧 수입 (요청 도착 알림)
    fetchMyRunnerStatus()
      .then((v) => { setRs(v); setRsErr(false); })
      .catch((e) => { console.warn('[rhome] status:', e?.message ?? e); setRsErr(true); })
      .finally(() => setRsLoaded(true));
  }, []));

  // 온라인 토글 — 실저장 (오프라인이면 추천·동네 러너 셸프에서 빠짐). 빕 위 스위치가 이 상태를 쓴다.
  const toggleOnline = () => {
    const next = !rs.online;
    setRs((v) => ({ ...v, online: next }));
    setRunnerOnline(next).catch((e) => {
      setRs((v) => ({ ...v, online: !next }));
      console.warn('[rhome] online:', e?.message ?? e);
    });
  };

  // 요일 탭 = 즉시 열기/닫기 (저장 버튼 없음 — 충동적 슬롯 오픈은 홈에서 바로)
  const toggleDay = (wd: number) => {
    if (!avail) return;
    const has = avail.some((r) => r.weekday === wd);
    const prev = avail;
    const next = has
      ? avail.filter((r) => r.weekday !== wd)
      : [...avail, { weekday: wd, startMin: 360, endMin: 1320 }];
    setAvail(next);
    saveMyAvailability(next).catch((e) => {
      setAvail(prev);
      console.warn('[rhome] avail save:', e?.message ?? e);
    });
  };

  const current = jobs.find((j) => ['runner_enroute', 'picked_up', 'active'].includes(j.rawStatus))
    ?? jobs.find((j) => j.rawStatus === 'confirmed');
  const upcoming = jobs.filter((j) => j.status === 'confirmed' && j.bookingId !== current?.bookingId).slice(0, 3);
  const past = jobs.filter((j) => j.status === 'completed').slice(0, 3);

  // 진행 중 잡의 픽업 주소 — 키는 RunnerJob.bookingId (이 타입에 id 필드는 없다). 20행 잡 목록 전체를
  // 훑지 않고 지금 진행 중인 한 건만 부른다. 실패는 여기서 조용하다: 홈 카드는 지나가는 요약이고,
  // 라우드한 실패 표면(재시도 스트립)은 미트업 화면의 픽업 카드가 진다 — 두 곳에서 소리치지 않는다.
  useEffect(() => {
    const bid = current?.bookingId;
    if (!bid) { setJobAddr(null); return; }
    let alive = true;
    fetchBookingAddress(bid)
      .then((a) => { if (alive) setJobAddr(a); })
      .catch((e) => { console.warn('[rhome] addr:', e?.message ?? e); if (alive) setJobAddr(null); });
    return () => { alive = false; };
  }, [current?.bookingId]);

  const openJob = (j: RunnerJob) => {
    runnerJob.bookingId = j.bookingId;
    router.push(j.rawStatus === 'active' ? '/runner/run' : '/runner/meetup');
  };

  // 드랍 트레일 — 실카운트 (runners.total_runs, settle-run이 증가시키는 값)
  const cycle5 = rs.totalRuns % 5;
  const remaining5 = 5 - cycle5;
  const cycle10 = rs.totalRuns % 10;

  // While tier is null (not loaded, signed out, or no runners row) render a neutral 러너 — never
  // 인증 러너, which asserts a certification that has not happened. 'applicant' also falls through
  // to 러너 because TIER_LABEL deliberately has no applicant entry (plan §6.3).
  const tierLabel = (rs.tier && TIER_LABEL[rs.tier]) || '러너';
  // An applicant (and anyone without a runners row) cannot receive a request at all — the inbox and
  // the tier ladder both say so instead of pretending it is a quiet day / a rung away.
  const preCert = rsLoaded && !rsErr && (rs.tier === null || rs.tier === 'applicant');
  const avg = stats.runs > 0 ? Math.round(stats.net / stats.runs) : 0;
  // 오늘 라벨 — 기기 시계가 아니라 KST 고정(UTC+9, DST 없음). j.when은 서버 api의 kstParts 산출물이라
  // 기기가 UTC(에뮬레이터)·해외면 라벨이 하루 어긋나 오늘 잡이 통째로 안 잡혔다.
  const _t = new Date(Date.now() + 9 * 3_600_000);
  const todayLabel = `${_t.getUTCMonth() + 1}월 ${_t.getUTCDate()}일`;
  const todayJobs = jobs.filter((j) => j.when.startsWith(todayLabel) && ['confirmed', 'runner_enroute', 'picked_up', 'active', 'completed'].includes(j.rawStatus));
  const todaySum = todayJobs.reduce((a, j) => a + (j.payout ?? 0), 0);
  const todayN = todayJobs.length;

  // when 문자열 파싱 — 마지막 토큰 = 시간, 앞 = 요일/날짜 (소스 다음예약 파싱과 동일)
  const parseWhen = (w: string) => {
    const i = w.lastIndexOf(' ');
    return i < 0 ? { wd: '', wt: w } : { wd: w.slice(0, i), wt: w.slice(i + 1) };
  };

  // 오늘의 루트 — 진행 중 + 다음 예약을 정차역 타임라인으로 (모든 job 데이터·openJob 보존)
  const routeStops: { job: RunnerJob; kind: 'on' | 'next' }[] = [
    ...(current ? [{ job: current, kind: 'on' as const }] : []),
    ...upcoming.map((j) => ({ job: j, kind: 'next' as const })),
  ];

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>{/* [페이퍼 크롬] 라일락 캔버스 은퇴 → 백지 */}
      {/* ————— 상단 크롬 — 플레인 화이트 + 코랄 헤어라인 (글래스 은퇴) · 알림 벨 보존 (/alerts) ————— */}
      <View style={styles.top}>
        <Row style={{ alignItems: 'center', gap: 6 }}>
          <View style={styles.brandmark}><Text style={styles.brandmarkGlyph}>다</Text></View>
          <Text style={styles.crumb}>RUNNER</Text>
        </Row>
        <Pressable onPress={() => router.push('/alerts')} style={styles.bell} accessibilityLabel="알림">
          {/* 도트는 실 미읽음 수가 있을 때만 — 무조건 점은 가짜 알림 신호다 */}
          {unread > 0 && <View style={styles.bellDot} />}
          <Icon name="Bell" glyph="◔" size={16} color={lilac.head} />
        </Pressable>
      </View>

      {/* [2026-08-10] screen gutter 14 → layout.gutter (15) — vertical paddings unchanged */}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 12, paddingBottom: 28 }}>

        {/* ————— 마스트헤드 · ① HERO 레이스 빕 (온라인 토글이 빕 위에) ————— */}
        <Row style={styles.kicker}>
          <Text style={styles.kickerTxt}>DAENGRUN RUNNER</Text>
          <View style={styles.rule} />
          {/* [2026-08-10] tierLabel is Korean data, not kicker decoration — 14pt (DESIGN.md §3);
              the latin kicker on the left keeps its 12pt letterspaced-caps exemption */}
          <Text style={styles.kickerTxtKo}>{tierLabel}</Text>
        </Row>

        <View style={styles.bib}>
          <HoloEdge />
          <View style={styles.bibInner} pointerEvents="none" />
          <View style={[styles.pin, { top: 11, left: 11 }]} />
          <View style={[styles.pin, { top: 11, right: 11 }]} />
          <View style={[styles.pin, { bottom: 52, left: 11 }]} />
          <View style={[styles.pin, { bottom: 52, right: 11 }]} />

          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start', paddingHorizontal: 26, paddingTop: 14, gap: 10 }}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.bibOrg}>DAENGRUN · {tierLabel}</Text>
              <Text style={[styles.bibName, df]} numberOfLines={1}>
                {name ?? '러너'}<Text style={styles.bibNameEm}> 러너</Text>
              </Text>
            </View>
            {/* 온라인 토글 — 러너의 유일한 스위치, 빕 위에 산다. 같은 rs.online/toggleOnline 상태 */}
            <Pressable onPress={toggleOnline} style={{ alignItems: 'flex-end', gap: 5 }} accessibilityRole="switch" accessibilityState={{ checked: rs.online }}>
              <View style={[styles.swTrack, rs.online ? styles.swTrackOn : styles.swTrackOff]}>
                <View style={styles.swKnob} />
              </View>
              <Text style={[styles.swLabel, { color: rs.online ? CORAL_INK : lilac.dim }]}>
                {rs.online ? '온라인' : '오프라인'}
              </Text>
            </Pressable>
          </Row>

          {/* 빕 바디 — 대형숫자 열은 고정폭(bibNoCol)으로 경계, gap 12 + 좌측보더로 사이드 스탯과 완전 분리 (오버랩 FIX #1) */}
          <Row style={{ alignItems: 'flex-end', gap: 12, paddingHorizontal: 26, paddingTop: 6 }}>
            <View style={styles.bibNoCol}>
              <Text style={[styles.bibNo, nf]} numberOfLines={1}>{String(stats.runs).padStart(2, '0')}</Text>
              <Text style={styles.bibNoCap}>이번 주 완료 러닝</Text>
            </View>
            <View style={styles.bibSide}>
              <Row style={styles.bsRow}>
                <Text style={styles.bsK}>TOTAL</Text>
                <Text style={styles.bsV}><Text style={[styles.bsVNum, nf]}>{rs.totalRuns}</Text>회</Text>
              </Row>
              <Row style={[styles.bsRow, styles.bsRowTop]}>
                <Text style={styles.bsK}>TIER</Text>
                <Text style={styles.bsV}>{tierLabel}</Text>
              </Row>
              <Row style={[styles.bsRow, styles.bsRowTop]}>
                <Text style={styles.bsK}>DISTANCE</Text>
                <Text style={styles.bsV}><Text style={[styles.bsVNum, nf]}>{rs.totalKm}</Text>km</Text>
              </Row>
            </View>
          </Row>

          <Row style={styles.bibFoot}>
            <Barcode width={118} />
            <Text style={styles.bibFootTxt}>DAENGRUN · RUNNER</Text>
          </Row>
        </View>

        {/* ————— ② EARNINGS: 정산 장부 — 빕 바로 아래, 실 정산 필드 바인딩 · 점선 리더 ————— */}
        <View style={[styles.card, { marginTop: 12, padding: 5 }]}>
          <View style={styles.ledgerIn}>
            <HoloEdge />
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 4 }}>
              <Row style={{ alignItems: 'center', gap: 6 }}>
                <View style={styles.lGlyph}><Text style={{ color: '#fff', fontSize: 9, fontWeight: '700' }}>₩</Text></View>
                <Text style={styles.lBrand}>EARNINGS LEDGER</Text>
              </Row>
              <View style={styles.monoTagV}><Text style={styles.monoTagVTxt}>THIS WEEK</Text></View>
            </Row>

            {/* 정산 히어로 — ₩와 금액은 baseline 정렬 + gap 4로 절대 겹치지 않음 (오버랩 FIX #2) */}
            <Row style={{ alignItems: 'baseline', gap: 4, marginTop: 11 }}>
              <Text style={[styles.won, nf]}>₩</Text>
              <Text style={[styles.lBig, nf]} numberOfLines={1}>{stats.net.toLocaleString()}</Text>
            </Row>
            {/* [2026-08-10 filler cull] 'THIS WEEK' tag + ₩ hero already say week/earnings — only the fee basis earns the caption */}
            <Text style={styles.lCap}>수수료 차감 후 기준</Text>
            {/* 넓은 창 — 이번 달(KST 월 1일~ 원장 합) · 누적(my_ledger_total RPC). 실값만, 로드 전엔 '—' */}
            <Row style={styles.lWin}>
              <Text style={styles.lWinK}>이번 달</Text>
              <Text style={styles.lWinV}>₩<Text style={[styles.lWinNum, nf]}>{monthNet === null ? '—' : monthNet.toLocaleString()}</Text></Text>
              <Text style={styles.lWinSep}>·</Text>
              <Text style={styles.lWinK}>누적</Text>
              <Text style={styles.lWinV}>₩<Text style={[styles.lWinNum, nf]}>{totalNet === null ? '—' : totalNet.toLocaleString()}</Text></Text>
            </Row>
            {/* [Sean] 오늘의 가시 수익 = 러너의 인센티브 — 오늘 확정·진행·완료 잡의 실수령 합 (실필드만) */}
            {/* 라벨 '·예정': 완료 건만 원장 실수령이고 확정~진행 건은 티어 수수료 견적(api fetchRunnerJobs)이다 —
                섞인 합을 '확보'라 부르면 아직 안 들어온 돈을 확정으로 위장한다. 계산·필터는 그대로. */}
            {todayN > 0 && (
              <Text style={styles.lToday}>
                오늘 확보·예정 <Text style={[styles.lTodayNum, nf]}>+{todaySum.toLocaleString()}</Text>원 · 확정 {todayN}건
              </Text>
            )}

            <View style={{ marginTop: 11, borderTopWidth: 1, borderTopColor: '#EEEEEE' }}>
              <LedgerRow label="완료 러닝" sub="THIS WEEK" value={String(stats.runs)} unit="회" nf={nf} />
              <LedgerRow label="총 거리" sub="DISTANCE" value={String(stats.km)} unit="km" nf={nf} />
              <LedgerRow label="회당 평균" sub="AVG / RUN" value={avg.toLocaleString()} unit="원" nf={nf} total />
            </View>

            <Row style={styles.lFoot}>
              {/* [2026-08-10 filler cull] the 수익 상세 link right next to this already names the destination */}
              <Text style={styles.lFootTxt}>매주 정산</Text>
              <Pressable onPress={() => router.push('/runner/earnings')}>
                <Text style={styles.lFootLink}>수익 상세 ›</Text>
              </Pressable>
            </Row>
          </View>
        </View>

        {/* ————— ③ CLUB ENGINE — 히어로 인접 승격 (빕·장부 다음, 운영 피드보다 위). 클럽+호스트 로직은 컴포넌트가 보유 ————— */}
        <CapHead title="하이클럽" />
        <View style={{ marginTop: 10 }}>
          <RunnerClubCard />
        </View>

        {/* ————— 진행 중 작업 (관제탑의 심장) — 코랄 좌측 엣지 ————— */}
        {current && (
          <>
            <CapHead title="진행 중" />
            <Pressable onPress={() => openJob(current)} style={styles.now}>
              <View style={styles.nowEdge} />
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <Row style={{ alignItems: 'center', gap: 6 }}>
                  <View style={{ width: 14, height: 14, alignItems: 'center', justifyContent: 'center' }}>
                    <PulseRings color={lilac.coral} size={14} />
                    <View style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: lilac.coral }} />
                  </View>
                  <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: STAGE[current.rawStatus]?.color ?? CORAL_INK }}>
                    {STAGE[current.rawStatus]?.label ?? current.rawStatus}
                  </Text>
                </Row>
                <Text style={styles.nowWhen}>{current.when}</Text>
              </Row>
              <Text style={styles.nowTitle}>{current.dogName} · {current.km}km 러닝</Text>
              <Text style={styles.nowSub}>
                예상 수익 <Text style={{ fontWeight: '700', color: lilac.text }}>+{current.payout.toLocaleString()}원</Text>
              </Text>
              {/* 주소는 서버가 준 행이 있을 때만 — 없으면 줄 자체가 없다 (죽은 줄·거짓 줄 금지) */}
              {jobAddr && (
                <Text style={styles.nowSub} numberOfLines={1}>{jobAddr.label} · {jobAddr.addr}</Text>
              )}
              <Row style={{ gap: 7, marginTop: 11 }}>
                <View style={[styles.btnCoral, { flex: 1.5 }]}>
                  <Text style={styles.btnCoralTxt}>{STAGE[current.rawStatus]?.action ?? '이어서 진행 ›'}</Text>
                </View>
              </Row>
            </Pressable>
          </>
        )}

        {/* ————— ①(01) QUEUE: 오늘 맨 앞 = 보딩패스 티켓 · 나머지 = 스텁 행. 수락/거절 = 소스 요청함 핸들러 ————— */}
        <SectionRule no="01" title="요청 대기열" link={`요청함 · ${inbox.length}건 ›`} onPress={() => router.push('/runner/requests')} />

        {inbox.length > 0 ? (
          <>
            {/* 오늘 맨 앞 예약 = 보딩패스 티켓 전문 (inbox[0]) */}
            <View style={styles.ticket}>
              <View style={styles.tMain}>
                <HoloEdge />
                <Row style={{ justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 13, paddingTop: 12, gap: 8 }}>
                  <Row style={{ alignItems: 'center', gap: 6 }}>
                    <View style={styles.tGlyph}><Text style={{ color: '#fff', fontSize: 9 }}>✈</Text></View>
                    <Text style={styles.tBrand}>TODAY · FRONT REQUEST</Text>
                  </Row>
                  {inbox[0].directed && (
                    <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>
                  )}
                </Row>
                <View style={{ paddingHorizontal: 13, paddingTop: 9, paddingBottom: 12 }}>
                  <Row style={{ alignItems: 'baseline', gap: 7 }}>
                    <Text style={[styles.tBig, nf]}>{inbox[0].when}</Text>
                  </Row>
                  <Row style={{ alignItems: 'center', gap: 6, marginTop: 8 }}>
                    <View style={{ width: 10, height: 12, borderRadius: 5, backgroundColor: lilac.coral }} />
                    <Text style={styles.tWhere}>{inbox[0].dogName}</Text>
                    <Text style={styles.tWhereSub}>· 지명 요청 픽업</Text>
                  </Row>
                  <Row style={{ marginTop: 10, borderTopWidth: 1, borderTopColor: '#EEEEEE', paddingTop: 9 }}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.factK}>COURSE</Text>
                      <Text style={styles.factV}><Text style={[styles.factVNum, nf]}>{inbox[0].km}</Text><Text style={styles.factVUnit}> km</Text></Text>
                    </View>
                    <View style={styles.factDiv}>
                      {/* [2026-08-10] '정산' is a Korean info label, not a latin kicker — 14pt override */}
                      <Text style={[styles.factK, styles.factKKo]}>정산</Text>
                      <Text style={styles.factV}><Text style={[styles.factVNum, nf]}>{inbox[0].payout.toLocaleString()}</Text><Text style={styles.factVUnit}> 원</Text></Text>
                    </View>
                  </Row>
                </View>
              </View>

              {/* 퍼포레이션 + 사이드 노치 */}
              <View style={styles.perfWrap}>
                <View style={styles.perf} />
                <View style={[styles.perfNotch, { left: -8 }]} />
                <View style={[styles.perfNotch, { right: -8 }]} />
              </View>

              <View style={styles.tStub}>
                <Row style={{ gap: 8 }}>
                  {/* [실동작] 문이 곧 행동 — 수락은 여기서 끝난다. 상세(사진·메모)가 필요하면 콰이엇 문(오픈 요청) */}
                  <Pressable onPress={acceptFront} disabled={busyReq} style={[styles.door, styles.doorCoral, busyReq && { opacity: 0.55 }]}>
                    <Text style={[styles.doorName, { color: '#fff' }]}>{busyReq ? '전송 중...' : '수락'}</Text>
                    {/* [2026-08-10 filler cull] ' · 바로 확정돼요' dropped — the confirm Alert states the consequence */}
                    <Text style={[styles.doorSub, { color: '#fff' }]}>
                      <Text style={[styles.doorSubNum, nf]}>{inbox[0].payout.toLocaleString()}</Text>원
                    </Text>
                  </Pressable>
                  <Pressable onPress={declineFront} disabled={busyReq} style={[styles.door, styles.doorQuiet, busyReq && { opacity: 0.55 }]}>
                    <Text style={[styles.doorName, { color: lilac.head }]}>{inbox[0].directed ? '거절' : '자세히'}</Text>
                    <Text style={[styles.doorSub, { color: lilac.dim }]}>
                      {inbox[0].directed ? '다른 러너에게 넘겨요' : '메모 · 사진 · 성향 보기 →'}
                    </Text>
                  </Pressable>
                </Row>
                <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 10 }}>
                  <Barcode width={120} />
                  <Text style={styles.bibFootTxt}>REQ · FRONT</Text>
                </Row>
              </View>
            </View>

            {/* 나머지 요청 = 스텁 행 (퍼포 스텁 · 장부 행) */}
            <View style={{ gap: 9, marginTop: 9 }}>
              {inbox.slice(1).map((rq, i) => (
                <View key={i} style={styles.stub}>
                  <HoloEdge />
                  <View style={{ flex: 1, minWidth: 0, paddingHorizontal: 11, paddingTop: 12, paddingBottom: 10 }}>
                    <Row style={{ alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                      <Text style={styles.stubNm}>{rq.dogName}</Text>
                      <Text style={[styles.stubKm, nf]}>{rq.km}<Text style={styles.stubKmUnit}>KM</Text></Text>
                      {rq.directed && <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>}
                    </Row>
                    <Row style={{ alignItems: 'center', gap: 5, marginTop: 5 }}>
                      <Text style={styles.stubWhen}>{rq.when}</Text>
                    </Row>
                  </View>
                  <View style={styles.stubAct}>
                    <View style={[styles.stubNotch, { top: -6 }]} />
                    <View style={[styles.stubNotch, { bottom: -6 }]} />
                    <View style={{ alignItems: 'center' }}>
                      <Text style={[styles.stubFare, nf]}>{rq.payout.toLocaleString()}</Text>
                      <Text style={styles.stubFareCap}>KRW 실수령</Text>
                    </View>
                    <Pressable onPress={() => router.push('/runner/requests')} style={styles.accept}>
                      <Text style={styles.acceptTxt}>수락</Text>
                    </Pressable>
                  </View>
                </View>
              ))}

              {/* [2026-08-10 filler cull] queue-mechanics narration removed — the real empty state
                  (emptyInbox below) already explains quiet days; this row is just the door to 요청함 */}
              <Pressable onPress={() => router.push('/runner/requests')} style={styles.stubMore}>
                <Text style={styles.stubMoreLink}>모두 보기 ›</Text>
              </Pressable>
            </View>
          </>
        ) : (
          <View style={styles.emptyInbox}>
            {/* [honesty repair 2026-08-08 / plan §6.3, §7.3] This box used to tell an applicant
                "지금은 새 요청이 없어요 — 오는 대로 여기에 떠요". For an applicant a request can never
                arrive: only tier <> 'applicant' runners are reachable. The failure was the empty state
                with no explanation and no exit, not the emptiness. Now: loading says loading, a failed
                load says it failed, and a pre-certification runner gets the reason plus a real route. */}
            {!rsLoaded ? (
              <Text style={styles.emptyInboxTxt}>내 러너 상태를 불러오는 중이에요…</Text>
            ) : rsErr ? (
              <Text style={styles.emptyInboxTxt}>내 러너 상태를 불러오지 못했어요</Text>
            ) : preCert ? (
              <Pressable
                onPress={() => router.push('/runner/apply')}
                accessibilityRole="button"
                accessibilityLabel="인증 센터로 이동해 러너 지원하기"
              >
                <Text style={styles.emptyInboxTxt}>인증 전에는 요청이 오지 않아요</Text>
                <Text style={styles.emptyInboxLink}>인증 센터에서 지원할 수 있어요 ›</Text>
              </Pressable>
            ) : (
              <Text style={styles.emptyInboxTxt}>
                {rs.online ? '지금은 새 요청이 없어요 — 오는 대로 여기에 떠요' : '오프라인 상태 — 켜야 요청을 받아요'}
              </Text>
            )}
          </View>
        )}

        {/* ————— ②(02) 오늘의 루트 — 정차역 타임라인 (진행 중 + 다음 예약) ————— */}
        {routeStops.length > 0 && (
          <>
            <SectionRule no="02" title="오늘의 루트" link="캘린더 ›" onPress={() => router.push('/runner/calendar')} />
            <View style={styles.card}>
              <View style={{ marginTop: 2 }}>
                {routeStops.map((st, i) => {
                  const { wd, wt } = parseWhen(st.job.when);
                  const on = st.kind === 'on';
                  return (
                    <Pressable
                      key={st.job.bookingId}
                      onPress={() => openJob(st.job)}
                      style={[styles.stop, i > 0 && { borderTopWidth: 1, borderTopColor: '#EEEEEE' }]}
                    >
                      <View style={[styles.stopPt, on && styles.stopPtOn]}>
                        {on && <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral }} />}
                      </View>
                      {/* [2026-08-10] time col 52 → 60: stopTm went 14 → 16pt Oswald — 'HH:MM' ≈ 5 glyphs
                          × ~9px + tracking ≈ 48px, 60 leaves device-font-scale headroom (52 fit 14pt ≈ 42px) */}
                      <View style={{ width: 60 }}>
                        <Text style={[styles.stopTm, nf]}>{wt}</Text>
                        <Text style={styles.stopTmSub}>{on ? '지금' : wd || '예정'}</Text>
                      </View>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Text style={styles.stopInfoB}>{st.job.dogName} · {st.job.km}km</Text>
                        <Text style={styles.stopInfoS}>{on ? '픽업 대기' : '지명 요청 · 예정'}</Text>
                      </View>
                      <Text style={[styles.stopPay, nf]}>+{st.job.payout.toLocaleString()}</Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </>
        )}

        {/* ————— ③(03) 리워드 — 티어 사다리 + 보급 드랍 트레일 (실카운트) ————— */}
        <SectionRule no="03" title="리워드" link="리워드 센터 ›" onPress={() => router.push('/runner/rewards')} />
        <Pressable onPress={() => router.push('/runner/rewards')} style={styles.card}>
          {(() => {
            // [honesty repair 2026-08-08 / plan §6.3, §7.3] The ladder is progress toward the rung
            // ABOVE 인증 러너. Drawing "베테랑까지 30회" for someone who has not reached 인증 러너 yet
            // measures them against a rung two steps away and implies the first one is already theirs.
            // Loading and a failed load are stated as themselves — neither is a tier.
            if (!rsLoaded) {
              return <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.dim }}>등급을 불러오는 중이에요…</Text>;
            }
            if (rsErr) {
              return <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.dim }}>등급을 불러오지 못했어요</Text>;
            }
            if (preCert) {
              return <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head }}>인증 러너가 되면 등급이 시작돼요</Text>;
            }
            // v1 승급 기준: 베테랑 30회, 마스터 100회 — 심사 도입 전 잠정.
            // 수수료는 일괄 33%(0059) — 티어 연동 요율 없음. 요율 인하 약속 금지(정산은 33%를 뗀다).
            const t = rs.tier === 'veteran'
              ? { next: '마스터', at: 100 }
              : rs.tier === 'master'
                ? null
                : { next: '베테랑', at: 30 };
            if (!t) {
              return <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head }}>🏅 마스터 러너</Text>;
            }
            const left = Math.max(t.at - rs.totalRuns, 0);
            const pct = Math.min(rs.totalRuns / t.at, 1);
            return (
              <>
                <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head }}>
                    {t.next}까지 러닝 <Text style={[{ fontSize: 14, color: CORAL_INK }, nf]}>{left}</Text>회
                  </Text>
                  <Text style={[styles.fee, nf]}>수수료 일괄 <Text style={{ color: lilac.voltDeep }}>33%</Text></Text>
                </Row>
                <Row style={{ alignItems: 'center', marginTop: 11, gap: 0 }}>
                  {[0, 1, 2, 3, 4].map((i) => {
                    const segFill = Math.max(0, Math.min(1, pct * 5 - i));
                    return (
                      <View key={i} style={[styles.rung, i === 0 && styles.rungL, i === 4 && styles.rungR]}>
                        {segFill > 0 && <View style={[styles.rungFill, { width: `${segFill * 100}%` }, i === 0 && styles.rungL, i === 4 && segFill >= 1 && styles.rungR]} />}
                      </View>
                    );
                  })}
                </Row>
                {/* [2026-08-10 filler cull] '승급 혜택은 준비 중이에요' clause dropped — announcing an
                    unbuilt benefit is filler; the honest disclaimer stays */}
                <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 8 }}>
                  승급 기준은 파일럿 중 조정될 수 있어요
                </Text>
              </>
            );
          })()}

          <View style={{ height: 1, backgroundColor: '#EEEEEE', marginTop: 11, marginBottom: 10 }} />

          {/* 보급 드랍 트레일 — 지그재그 체크포인트 (i<cycle5 지남=accent, i===cycle5 다음=accent 링, 끝=보급 상자) */}
          <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head }}>
              <Text style={{ color: lilac.gold }}>▣ </Text>보급 드랍 트레일
            </Text>
            <Text style={styles.trailCnt}>누적 {rs.totalRuns}회 ›</Text>
          </Row>
          <Row style={{ alignItems: 'center', height: 52, marginTop: 6 }}>
            {[0, 1, 2, 3, 4].map((i) => (
              <Row key={i} style={{ flex: 1, alignItems: 'center' }}>
                <View style={{
                  transform: [{ translateY: i % 2 === 0 ? 11 : -11 }, { rotate: '45deg' }],
                  width: 17, height: 17, borderRadius: 4,
                  backgroundColor: i < cycle5 ? lilac.accent : lilac.card,
                  borderWidth: 1.5,
                  borderColor: i < cycle5 ? lilac.accentDeep : i === cycle5 ? lilac.accent : lilac.hair,
                  shadowColor: lilac.accent, shadowOpacity: i < cycle5 ? 0.3 : 0,
                  shadowRadius: 5, shadowOffset: { width: 0, height: 2 },
                }} />
                <View style={{
                  flex: 1, height: 2, borderRadius: 2, marginHorizontal: 2,
                  backgroundColor: i < cycle5 ? '#C9BEF7' : lilac.hair,
                  transform: [{ rotate: i % 2 === 0 ? '-13deg' : '13deg' }],
                }} />
              </Row>
            ))}
            <View style={{ transform: [{ translateY: 11 }], width: 28, height: 28, alignItems: 'center', justifyContent: 'center' }}>
              {cycle5 === 0 && rs.totalRuns > 0 && <PulseRings color={lilac.accent} size={28} />}
              <View style={{
                width: 28, height: 28, borderRadius: 7, backgroundColor: lilac.amberSoft,
                alignItems: 'center', justifyContent: 'center',
                borderWidth: 1.5, borderColor: cycle5 === 0 && rs.totalRuns > 0 ? lilac.accent : lilac.amberEdge,
              }}>
                <Text style={{ fontSize: 12, color: lilac.amber }}>▣</Text>
              </View>
            </View>
          </Row>
          <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head, marginTop: 4 }}>
            {rs.totalRuns === 0
              ? '첫 러닝을 완료하면 트레일이 시작돼요'
              : cycle5 === 0
                ? '보급 드랍 도착! 리워드 센터에서 열어보세요'
                : `${remaining5}번 더 달리면 보급 드랍!`}
          </Text>
          <Row style={{ alignItems: 'center', gap: 7, marginTop: 9, paddingTop: 9, borderTopWidth: 1, borderTopColor: '#EEEEEE' }}>
            <Text style={styles.flagLb}>픽 드랍</Text>
            <View style={styles.flagTrack}>
              <View style={[styles.flagFill, { width: `${(cycle10 / 10) * 100}%` }]} />
            </View>
            <Text style={[styles.flagCnt, nf]}>{cycle10}/10</Text>
          </Row>
        </Pressable>

        {/* ————— ④(04) 러닝 가능 시간 — 요일 탭 (온라인 토글은 빕 위) ————— */}
        <SectionRule no="04" title="러닝 가능 시간" link="시간 조정 ›" onPress={() => router.push('/runner/availability')} />
        <View style={styles.card}>
          {!avail ? (
            <Text style={{ fontSize: 14, color: lilac.dim }}>불러오는 중...</Text>
          ) : (
            <>
              <Row style={{ gap: 4 }}>
                {DAY_ORDER.map((wd) => {
                  const rule = avail.find((r) => r.weekday === wd);
                  const on = !!rule;
                  return (
                    <Pressable key={wd} onPress={() => toggleDay(wd)} style={[styles.day, on && styles.dayOn]}>
                      <Text style={[styles.dayD, { color: on ? lilac.head : lilac.dim }]}>{DAY_NAME[wd]}</Text>
                      <Text style={[styles.dayH, { color: on ? lilac.accent : lilac.dim }]}>
                        {rule ? `${hh(rule.startMin)}–${hh(rule.endMin)}` : '쉼'}
                      </Text>
                    </Pressable>
                  );
                })}
              </Row>
              {/* [2026-08-10 filler cull] tap-narration clause dropped — the chips demonstrate the tap */}
              <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 9 }}>
                기본 06–22시 · 보호자 예약 화면에 즉시 반영
              </Text>
            </>
          )}
        </View>

        {/* ————— ⑤(05) 최근 완료 — 패치 + 인증샷 ————— */}
        {past.length > 0 && (
          <>
            <SectionRule no="05" title="최근 완료" link="수익 상세 ›" onPress={() => router.push('/runner/earnings')} />
            <View style={[styles.card, { padding: 0, overflow: 'hidden' }]}>
              {past.map((j, i) => (
                <Row key={j.bookingId} style={[styles.drow, i > 0 && { borderTopWidth: 1, borderTopColor: '#EEEEEE' }]}>
                  <View style={{ alignSelf: 'center' }}>
                    {j.routeId && patchMap[j.routeId] ? (
                      <Pressable onPress={() => router.push('/cards')}>
                        <PatchBadge km={patchMap[j.routeId].km} grade={patchMap[j.routeId].grade} size={34} />
                      </Pressable>
                    ) : (
                      <View style={styles.patchFallback}><Text style={[styles.patchFallbackTxt, nf]}>{j.km}K</Text></View>
                    )}
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.drowB}>{j.dogName} · {j.km}km · 완료</Text>
                    <Text style={styles.drowS}>{j.when} · <Text style={{ color: lilac.voltDeep, fontWeight: '700' }}>✓ 정산 완료</Text></Text>
                  </View>
                  <View style={{ alignItems: 'flex-end', gap: 5 }}>
                    <Text style={[styles.drowPay, nf]}>+{j.payout.toLocaleString()}</Text>
                    <Pressable onPress={() => router.push(`/shot/${j.bookingId}`)} style={styles.shot}>
                      <Text style={styles.shotTxt}>📸 인증샷</Text>
                    </Pressable>
                  </View>
                </Row>
              ))}
            </View>
          </>
        )}

        {/* ————— ⑥(06) 동네 코스 ————— */}
        <View style={{ marginTop: 8 }}>
          <CourseStrip title="동네 코스" />
        </View>

        {/* ————— 퀵 링크 ————— */}
        <Row style={{ flexWrap: 'wrap', gap: 6, marginTop: 14 }}>
          <Pressable onPress={() => router.push('/leaderboard')} style={styles.qlink}>
            <Text style={styles.qlinkB}>🏆 랭킹</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/community')} style={styles.qlink}>
            <Text style={styles.qlinkB}>커뮤니티</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/safety')} style={styles.qlink}>
            <Text style={styles.qlinkB}>안심 센터</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/cards')} style={styles.qlink}>
            <Text style={styles.qlinkB}>마이 카드</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
        </Row>

        {/* ————— 푸터 ————— */}
        <Row style={styles.foot}>
          <Text style={styles.footTxt}>누적 <Text style={{ color: lilac.text }}>{rs.totalRuns}</Text>회</Text>
          <View style={styles.footDot} />
          <Text style={styles.footTxt}>{tierLabel}</Text>
          <View style={styles.footDot} />
          <Text style={styles.footTxt}>{rs.online ? '온라인' : '오프라인'}</Text>
        </Row>
      </ScrollView>

      <BottomNav />
    </View>
  );
}

const styles = StyleSheet.create({
  // 상단 크롬 — [페이퍼 크롬] 글래스 은퇴: 플레인 화이트 + 코랄 헤어라인 바텀 엣지 (마스트헤드 법)
  top: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingTop: 48, paddingBottom: 9, paddingHorizontal: 12,
    backgroundColor: paper.canvas, borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  brandmark: {
    width: 20, height: 20, borderRadius: 6, backgroundColor: HOLO[0], alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: 'rgba(34,30,61,0.16)',
  },
  brandmarkGlyph: { fontSize: 10, color: lilac.head, lineHeight: 12 }, // 글리프 전용 브랜드마크('다') — 20px 칩 안 조형이라 플로어 면제
  crumb: { fontSize: 12, lineHeight: 15, letterSpacing: 2, color: lilac.dim, fontWeight: '600' },
  bell: {
    width: 26, height: 26, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', // [페이퍼 크롬] 샤프·뉴트럴
    backgroundColor: lilac.card, alignItems: 'center', justifyContent: 'center',
  },
  // 미읽음 도트 — 보호자 홈과 동일 어휘(코랄 6px 글로우), 26px 벨에 맞춘 인셋
  bellDot: {
    position: 'absolute', top: 4, right: 4, width: 6, height: 6, borderRadius: 3,
    backgroundColor: lilac.coral, zIndex: 2,
    shadowColor: lilac.coral, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },

  // 공통 카드 + 룰 — [페이퍼 크롬] 샤프 코너 · 뉴트럴 #EEE 1px · 소프트 섀도 은퇴
  card: {
    backgroundColor: lilac.card, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 12, paddingHorizontal: 13, marginTop: 10,
  },
  rule: { flex: 1, height: 1, backgroundColor: '#EEEEEE' }, // 인라인 룰은 뉴트럴 — 코랄은 풀블리드 섹션 룰(secWrap)이 전담
  // [페이퍼 크롬] 섹션 헤더 래퍼 — 거터를 음수 마진으로 뚫은 풀블리드 코랄 1px 상단 룰
  secWrap: { marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter, borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10 },
  holo: { flexDirection: 'row', height: 3, position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },

  // 마스트헤드 — 키커: FIX3 디테일 밴드 12–15 (구 8px 목업값 → 12, 자간은 ≤2로 타이트닝)
  kicker: { alignItems: 'center', gap: 8, marginBottom: 10, marginTop: 2 },
  kickerTxt: { fontSize: 12, lineHeight: 15, letterSpacing: 2, color: lilac.dim, fontWeight: '600' },
  // [2026-08-10] Korean data slot in the masthead kicker row — 14pt floor, tracking eased to 1.2
  // (letterSpacing 2 is a latin-caps device; Korean glyphs read gappy at 2)
  kickerTxtKo: { fontSize: 14, lineHeight: 18, letterSpacing: 1.2, color: lilac.dim, fontWeight: '600' },

  srNo: { fontSize: 12, lineHeight: 15, letterSpacing: 1.2, color: lilac.accent, fontWeight: '700' },
  srTitle: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head },
  srLink: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '500' },

  // ① 빕 — [페이퍼 크롬] 카드 크롬만 샤프·뉴트럴 (홀로·바코드·핀·모노그램 아티팩트는 생존)
  bib: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0,
    overflow: 'hidden', paddingBottom: 0,
  },
  bibInner: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0 },
  pin: {
    position: 'absolute', width: 7, height: 7, borderRadius: 3.5, backgroundColor: lilac.inset,
    borderWidth: 1, borderColor: lilac.hair, zIndex: 2,
  },
  // [2026-08-10] carries {tierLabel} (Korean data) → 12 → 14 with tracking eased 1.6 → 1.
  // Width check (header row, not the bibNoCol cage): 'DAENGRUN · 인증 러너' ≈ 8×9 (latin 14pt)
  // + 20 (· + spaces) + 5×14 (Korean) + 12×1 (ls) ≈ 174px < left column ≈ 240px at 320dp
  // (320 − 26×2 side pads − ~64 toggle column) — fits on one line.
  bibOrg: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: lilac.dim, fontWeight: '600', marginBottom: 6 },
  bibName: { fontSize: 31, color: lilac.head, lineHeight: 37 }, // 사이즈 동결 · lineHeight 1.2×로 상단 잘림 방지
  bibNameEm: { fontSize: 14, color: lilac.dim, fontWeight: '600' },
  swTrack: { width: 44, height: 25, borderRadius: 99, padding: 3, flexDirection: 'row' },
  swTrackOn: {
    backgroundColor: lilac.coral, justifyContent: 'flex-end',
    shadowColor: lilac.coral, shadowOpacity: 0.32, shadowRadius: 9, shadowOffset: { width: 0, height: 3 },
  },
  swTrackOff: { backgroundColor: lilac.inset, justifyContent: 'flex-start', borderWidth: 1, borderColor: lilac.hair },
  swKnob: { width: 19, height: 19, borderRadius: 9.5, backgroundColor: '#fff', shadowColor: '#1C1837', shadowOpacity: 0.3, shadowRadius: 2, shadowOffset: { width: 0, height: 1 } },
  // [2026-08-10] 14 → 15 with tracking 1.2 → 1: '오프라인' width stays ≈ 63px (4×15 + 3×1 vs 4×14 + 3×1.2),
  // so the toggle column footprint next to the bib name is unchanged — the switch layout still fits.
  swLabel: { fontSize: 15, lineHeight: 19, letterSpacing: 1, fontWeight: '700' },
  // 대형숫자 열 — 고정폭 116으로 경계 (2자리 "07" ~76px + 캡션 14pt 한 줄이 안에 완전히 들어감
  // · gap 12 + 좌측보더로 사이드 스탯과 절대 충돌 안함)
  // [FLOOR14 2026-08-05] 100 → 116. bibNoCap '이번 주 완료 러닝' = 한글 7자 + 공백 2 ≈ 7×14 + 8 = 106px (구 12pt 91px).
  // 남는 폭은 bibSide(flex:1)에서 16px 빠지지만 최장 행 'DISTANCE'(12pt·ls1.3 ≈ 70) + 값(14pt ≈ 50) + gap 6 = 126 < 잔여 폭.
  bibNoCol: { width: 116, flexShrink: 0 },
  // BUG A: lineHeight 92 = 1.24×74 — Oswald 어센더 확보, includeFontPadding 제거 → "0" 상단 온전한 타원
  bibNo: { fontSize: 74, color: lilac.head, lineHeight: 92, letterSpacing: -1.5 },
  bibNoCap: { marginTop: 4, fontSize: 14, fontWeight: '600', color: lilac.text, lineHeight: 18 },
  bibSide: { flex: 1, minWidth: 0, borderLeftWidth: 1, borderLeftColor: '#EEEEEE', paddingLeft: 11, paddingBottom: 3 },
  bsRow: { justifyContent: 'space-between', alignItems: 'baseline', gap: 6, paddingVertical: 5 },
  bsRowTop: { borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  bsK: { fontSize: 12, lineHeight: 15, letterSpacing: 1.3, color: lilac.dim, fontWeight: '600' },
  bsV: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  bsVNum: { fontSize: 14, color: lilac.head },
  bibFoot: {
    marginTop: 13, borderTopWidth: 1.5, borderTopColor: '#DCD7F0', borderStyle: 'dashed',
    justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 9, backgroundColor: lilac.card,
  },
  bibFootTxt: { fontSize: 12, lineHeight: 15, letterSpacing: 1.5, color: lilac.dim, fontWeight: '500' },

  // ② 장부 — 목업 .l-in padding 11 12 10 · [페이퍼 크롬] 샤프·뉴트럴 (점선 리더는 장부 아티팩트로 생존)
  ledgerIn: { borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, paddingHorizontal: 12, paddingTop: 11, paddingBottom: 10, overflow: 'hidden' },
  lGlyph: { width: 16, height: 16, borderRadius: 5, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  lBrand: { fontSize: 12, lineHeight: 15, letterSpacing: 1.5, color: lilac.head, fontWeight: '700' },
  monoTagV: { borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE', borderRadius: 0, paddingHorizontal: 6, paddingVertical: 2 }, // [페이퍼 크롬] 칩 샤프 (바이올렛 틴트 필은 액센트로 생존)
  monoTagVTxt: { fontSize: 12, lineHeight: 15, letterSpacing: 1, color: lilac.accent, fontWeight: '600' },
  monoTagStar: { borderWidth: 1, borderColor: lilac.amberEdge, backgroundColor: lilac.amberSoft, borderRadius: 0, paddingHorizontal: 6, paddingVertical: 2 }, // [페이퍼 크롬] 샤프 (앰버 = 시맨틱)
  monoTagStarTxt: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: lilac.amber, fontWeight: '700' },
  // ₩와 금액은 baseline 정렬 · won은 flexShrink 0로 자기 폭 확보, 금액은 numberOfLines 1 (오버랩 FIX #2)
  // BUG A: 둘 다 lineHeight ≥1.2×fontSize, includeFontPadding 제거 → "₩0"의 0이 온전한 타원으로
  won: { fontSize: 20, color: CORAL_INK, lineHeight: 25, flexShrink: 0 },
  lBig: { fontSize: 46, color: lilac.head, lineHeight: 58, letterSpacing: 0.2, flexShrink: 1 },
  lToday: { fontSize: 14, fontWeight: '700', color: '#3D6B1F', marginTop: 7 },
  lTodayNum: { fontSize: 16, fontWeight: '700' },
  // 월·누적 행 — 히어로 아래 조용한 보조 창. Oswald 숫자는 lineHeight ≥1.2× (BUG A 법)
  // [2026-08-10] lWinNum 14 → 16/20 (1.25×). Width check at 320dp: ledger content ≈ 320 − 30 gutter
  // − 10 card pad(5×2) − 24 ledgerIn pad − 4 borders ≈ 252px; '이번 달 ₩9,999,999 · 누적 ₩9,999,999'
  // ≈ 2×(46 + 10 + 9×8.8) + 18 ≈ 250px — worst case wraps onto a second line via flexWrap (by design),
  // typical 6-digit sums stay on one. This row is NOT the LedgerRow 86px label cage below (unchanged).
  lWin: { alignItems: 'baseline', gap: 5, marginTop: 8, flexWrap: 'wrap' },
  lWinK: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '600' },
  lWinV: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head },
  lWinNum: { fontSize: 16, lineHeight: 20, color: lilac.head },
  lWinSep: { fontSize: 12, lineHeight: 16, color: lilac.dim }, // 글리프 전용(·) 구분자 — 플로어 면제
  lCap: { marginTop: 6, fontSize: 14, color: lilac.dim, lineHeight: 18 },
  lr: { alignItems: 'baseline', gap: 7, paddingTop: 7, paddingBottom: 6, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  lrLabel: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  lrSub: { fontSize: 11.5, lineHeight: 14, letterSpacing: 1.1, color: lilac.dim, fontWeight: '500', marginTop: 2 },
  lead: { flex: 1, borderBottomWidth: 1, borderStyle: 'dotted', borderBottomColor: '#D5CFEC', transform: [{ translateY: -3 }] },
  lrVal: { fontSize: 14, lineHeight: 18, fontWeight: '500', color: lilac.text },
  lrValNum: { fontSize: 14, color: lilac.head },
  lFoot: { justifyContent: 'space-between', alignItems: 'center', gap: 8, marginTop: 9, paddingTop: 8, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  lFootTxt: { fontSize: 14, lineHeight: 18, color: lilac.dim, flex: 1 },
  lFootLink: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.accent },

  // 진행 중 — 목업 .now padding 11 12 12 14 · [페이퍼 크롬] 샤프·뉴트럴 (코랄 좌측 엣지 = DAWN DUAL 액센트 생존)
  now: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0,
    overflow: 'hidden', paddingTop: 11, paddingRight: 12, paddingBottom: 12, paddingLeft: 14, marginTop: 10,
  },
  nowEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: lilac.coral },
  nowWhen: { fontSize: 14, lineHeight: 18, letterSpacing: 1.2, color: lilac.dim, fontWeight: '500' },
  nowTitle: { marginTop: 8, fontSize: 16, lineHeight: 21, fontWeight: '700', color: lilac.head },
  nowSub: { marginTop: 3, fontSize: 14, lineHeight: 18, color: lilac.dim },
  btnCoral: {
    borderRadius: 0, alignItems: 'center', justifyContent: 'center', paddingVertical: 13, backgroundColor: CORAL_INK, // [페이퍼 크롬] 샤프 · 코랄 글로우 섀도 은퇴 (CTA 필은 시맨틱 생존)
    borderWidth: 1, borderColor: CORAL_INK_DEEP,
  },
  btnCoralTxt: { fontSize: 16, lineHeight: 20, fontWeight: '700', color: '#fff' }, // [2026-08-10] 14 → 16 (primary button floor)

  // ① 티켓 — [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴 (퍼포레이션·바코드·홀로 아티팩트 생존)
  ticket: { marginTop: 9 },
  tMain: { backgroundColor: lilac.card, borderTopLeftRadius: 0, borderTopRightRadius: 0, borderWidth: 1, borderBottomWidth: 0, borderColor: '#EEEEEE', overflow: 'hidden' },
  tGlyph: { width: 16, height: 16, borderRadius: 0, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  tBrand: { fontSize: 12, lineHeight: 15, letterSpacing: 1.5, color: lilac.head, fontWeight: '700' },
  // BUG A: 티켓 시각 31pt → lineHeight 39 (1.26×), includeFontPadding 제거 — "0" 상단 온전
  tBig: { fontSize: 31, color: lilac.head, lineHeight: 39 },
  tWhere: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  tWhereSub: { fontSize: 14, lineHeight: 18, color: lilac.dim },
  factK: { fontSize: 12, lineHeight: 15, letterSpacing: 1.2, color: lilac.dim, fontWeight: '600', marginBottom: 3 },
  // [2026-08-10] Korean override for factK — 14pt floor, tracking eased for hangul
  factKKo: { fontSize: 14, lineHeight: 18, letterSpacing: 0.5 },
  factV: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  factVNum: { fontSize: 14, color: lilac.head },
  factVUnit: { fontSize: 14, fontWeight: '500', color: lilac.text },
  factDiv: { flex: 1, borderLeftWidth: 1, borderLeftColor: '#EEEEEE', paddingLeft: 10 },
  perfWrap: { backgroundColor: lilac.card, borderLeftWidth: 1, borderRightWidth: 1, borderColor: '#EEEEEE', position: 'relative' },
  perf: { borderTopWidth: 1.5, borderTopColor: '#DCD7F0', borderStyle: 'dashed' },
  perfNotch: { position: 'absolute', top: -8, width: 16, height: 16, borderRadius: 8, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' }, // 노치 = 캔버스 구멍 (원형은 퍼포 아티팩트 예외)
  tStub: { backgroundColor: lilac.card, borderBottomLeftRadius: 0, borderBottomRightRadius: 0, borderWidth: 1, borderTopWidth: 0, borderColor: '#EEEEEE', paddingHorizontal: 13, paddingTop: 11, paddingBottom: 12 },
  door: { flex: 1, borderRadius: 0, paddingVertical: 12, paddingHorizontal: 11, overflow: 'hidden' }, // [페이퍼 크롬] 샤프
  doorCoral: { backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP }, // 코랄 글로우 섀도 은퇴
  doorQuiet: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE' },
  doorName: { fontSize: 16, lineHeight: 20, fontWeight: '800' }, // [2026-08-10] 14.5 → 16 — the money action wears the primary-button floor
  doorSub: { marginTop: 4, fontSize: 14, lineHeight: 18 },
  doorSubNum: { fontSize: 14, lineHeight: 18 },

  // 스텁 행 — 목업 .s-act width 92 → 96 (FIX3: 11.5pt 캡션 한 줄 여유 확보, 구조는 동일)
  stub: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, overflow: 'hidden' }, // [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴
  stubNm: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head },
  stubKm: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  stubKmUnit: { fontSize: 14, color: CORAL_INK, fontWeight: '600' },
  stubWhen: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '500' },
  // [FLOOR14 2026-08-05] 96 → 112. 스텁 캡션 'KRW 실수령'이 11.5 → 14pt 가 되며 한 줄 폭 ≈ 4×8(KRW+공백) + 3×14 = 74px,
  // 여기에 paddingHorizontal 8×2 = 16 을 더하면 90px 필요 → 96은 여유 6px 뿐이라 기기 폰트 스케일에서 랩됐다. 112 = 90 + 22 여유.
  stubAct: { width: 112, borderLeftWidth: 1.4, borderStyle: 'dashed', borderLeftColor: '#DCD7F0', paddingVertical: 11, paddingHorizontal: 8, alignItems: 'center', justifyContent: 'center', gap: 7 },
  stubNotch: { position: 'absolute', left: -6, width: 12, height: 12, borderRadius: 6, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', zIndex: 3 },
  // BUG A: 스텁 요금 17pt → lineHeight 22 (1.29×), includeFontPadding 제거
  stubFare: { fontSize: 17, lineHeight: 22, color: lilac.head },
  stubFareCap: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: lilac.dim, fontWeight: '500', marginTop: 2 },
  accept: { width: '100%', borderRadius: 0, paddingVertical: 9, alignItems: 'center', backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP }, // [페이퍼 크롬] 샤프
  acceptTxt: { fontSize: 16, lineHeight: 20, fontWeight: '700', color: '#fff' }, // [2026-08-10] 14 → 16 (primary button floor); '수락' 2 glyphs ≈ 32px, well inside the 112 stubAct cage
  // [2026-08-10] narration text culled → the link centers alone (stubMoreTxt style retired with it)
  stubMore: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 8, borderWidth: 1, borderStyle: 'dashed', borderColor: '#EEEEEE', borderRadius: 0, paddingVertical: 9, paddingHorizontal: 11, backgroundColor: paper.canvas }, // [페이퍼 크롬] 글래스 은퇴
  stubMoreLink: { fontSize: 14, fontWeight: '700', color: lilac.accent },
  emptyInbox: { marginTop: 9, backgroundColor: lilac.inset, borderRadius: 0, padding: 16, borderWidth: 1, borderColor: '#EEEEEE' }, // [페이퍼 크롬] 샤프 (인셋 필 생존)
  emptyInboxTxt: { fontSize: 14, lineHeight: 18, color: lilac.dim, textAlign: 'center' },
  emptyInboxLink: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: lilac.accent, textAlign: 'center', marginTop: 5 },

  // ② 루트 — 목업 .stop padding 7 0 8, gap 11
  stop: { flexDirection: 'row', alignItems: 'flex-start', gap: 11, paddingTop: 7, paddingBottom: 8 },
  stopPt: { width: 14, height: 14, borderRadius: 7, marginTop: 2, backgroundColor: lilac.card, borderWidth: 1.5, borderColor: '#DCD6F8', alignItems: 'center', justifyContent: 'center' },
  stopPtOn: { borderColor: lilac.coral },
  stopTm: { fontSize: 16, lineHeight: 20, fontWeight: '600', color: lilac.head }, // [2026-08-10] 14 → 16 Oswald · lineHeight 20 = 1.25× (BUG A); time col widened 52 → 60 in JSX
  stopTmSub: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '500', marginTop: 2 },
  stopInfoB: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  stopInfoS: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 2 },
  // [2026-08-10] 14 → 16 Oswald · lineHeight 20 = 1.25× (BUG A). Row check at 320dp: card content
  // 320 − 30 gutter − 26 card pad − 2 border = 262 → minus pt 14, gaps 3×11, time 60, pay '+99,000'
  // ≈ 60 leaves ≈ 95px for the info column (flex, minWidth 0 — long dog names ellipsize, no overlap).
  stopPay: { fontSize: 16, lineHeight: 20, fontWeight: '600', color: lilac.head, marginTop: 1 },

  // ③ 리워드
  fee: { fontSize: 14, lineHeight: 18, letterSpacing: 0.5, color: lilac.head, fontWeight: '600' },
  rung: { flex: 1, height: 6, backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE', overflow: 'hidden' },
  rungL: { borderTopLeftRadius: 99, borderBottomLeftRadius: 99 },
  rungR: { borderTopRightRadius: 99, borderBottomRightRadius: 99 },
  rungFill: { height: '100%', backgroundColor: lilac.accent },
  trailCnt: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: lilac.accent, fontWeight: '500' },
  flagLb: { fontSize: 14, lineHeight: 18, letterSpacing: 1.2, color: lilac.dim, fontWeight: '600' },
  flagTrack: { flex: 1, height: 5, borderRadius: 99, backgroundColor: lilac.inset, overflow: 'hidden', borderWidth: 1, borderColor: '#EEEEEE' },
  flagFill: { height: '100%', borderRadius: 99, backgroundColor: lilac.accent },
  flagCnt: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },

  // ④ 가능 시간 — 목업 .day padding 8 0 7 · [페이퍼 크롬] 샤프·뉴트럴 (dayOn 바이올렛 틴트는 액센트 생존)
  day: { flex: 1, borderRadius: 0, paddingVertical: 8, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE' },
  dayOn: { backgroundColor: '#F4F1FE', borderColor: '#DCD6F8' },
  dayD: { fontSize: 14, fontWeight: '700', lineHeight: 18 },
  dayH: { fontSize: 14, lineHeight: 18, letterSpacing: 0.4, fontWeight: '500', marginTop: 4 },

  // ⑤ 최근 완료 — 목업 .drow padding 10 11, patch 34
  drow: { alignItems: 'center', gap: 10, paddingHorizontal: 11, paddingVertical: 10 },
  patchFallback: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#1C1837', alignItems: 'center', justifyContent: 'center' },
  patchFallbackTxt: { fontSize: 14, lineHeight: 18, color: '#CFC4FF', fontWeight: '600' },
  drowB: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  drowS: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 3 },
  drowPay: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.text },
  shot: { borderWidth: 1, borderColor: '#EEEEEE', backgroundColor: lilac.card, borderRadius: 0, paddingVertical: 4, paddingHorizontal: 6 }, // [페이퍼 크롬]
  shotTxt: { fontSize: 14, fontWeight: '600', color: lilac.head },

  // 퀵 링크 + 푸터 — 목업 .qlink padding 10 11
  qlink: { flexBasis: '48%', flexGrow: 1, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 6, backgroundColor: paper.canvas, borderWidth: 1, borderStyle: 'dashed', borderColor: '#EEEEEE', borderRadius: 0, paddingVertical: 10, paddingHorizontal: 11 }, // [페이퍼 크롬] 글래스 은퇴
  qlinkB: { fontSize: 14, fontWeight: '600', color: lilac.head },
  qlinkChev: { fontSize: 12, color: lilac.dim }, // 글리프 전용(›) 셰브런 — 플로어 면제
  foot: { alignItems: 'center', gap: 6, paddingTop: 10, marginTop: 12, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  footTxt: { fontSize: 14, lineHeight: 18, letterSpacing: 0.2, color: lilac.dim },
  footDot: { width: 2, height: 2, borderRadius: 1, backgroundColor: lilac.hair },
});
