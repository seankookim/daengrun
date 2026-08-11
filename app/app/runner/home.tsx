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
// 2026-08-11 Ⓑ① MONEY FIRST (declutter-lab, Sean pick "b1 + keep the rewards layout"):
// 장부(₩ 히어로)가 화면의 리드 모듈, 레이스 빕은 한 줄 스트랩(이름·티어·온라인 토글)으로 접혔다.
// 중복 인쇄 0: tierLabel 1회(스트랩), 주간 러닝/거리/평균 1회(장부), 온라인 1회(스트랩) — 푸터·마스트헤드
// 키커 은퇴. §3b 그램마: 섹션 헤더 = 코랄 풀블리드 룰 + 타이틀 20/800 (라틴 키커·서브타이틀·01~06 넘버 전부 은퇴).
// 리워드 카드는 Sean 지시로 현행 레이아웃 동결 (3중 진행계 포함 — 랩의 통합안 미적용).

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

// 섹션 헤더 — §3b 단일 그램마 (2026-08-11): 풀블리드 코랄 룰 위 · 타이틀 20/800 잉크 · 우측 링크 16/800.
// 라틴 키커·서브타이틀·01~06 순번 칩은 은퇴 — 대기열/루트/리워드는 순서 있는 시퀀스가 아니었다 (넘버 = 장식).
function SectionHead({ title, link, onPress }: { title: string; link?: string; onPress?: () => void }) {
  return (
    <Row style={[styles.secWrap, { alignItems: 'baseline', gap: 8, marginTop: 14 }]}>
      <Text style={styles.secTitle}>{title}</Text>
      <View style={{ flex: 1 }} />
      {link ? (
        <Pressable onPress={onPress} hitSlop={{ top: 10, bottom: 10, left: 6, right: 6 }}>
          <Text style={styles.secLink}>{link}</Text>
        </Pressable>
      ) : null}
    </Row>
  );
}

// 장부 점선 리더 행 — 좌 라벨 · 점선 리더 · 우 값. [§3b] 라틴 서브키커(THIS WEEK/DISTANCE/AVG/RUN) 은퇴 —
// 주간 컨텍스트는 히어로 캡션이 한 번만 말한다.
function LedgerRow({ label, value, unit, nf, total }: {
  label: string; value: string; unit: string; nf: TextStyle | null; total?: boolean;
}) {
  return (
    <Row style={[styles.lr, total && { borderBottomWidth: 0 }]}>
      {/* 라벨 열 72 — 최장 라벨 '완료 러닝' = 한글 4자 + 공백 ≈ 4×14.5 + 7 = 65px < 72 (서브키커가 빠져
          구 86 케이지의 존재 이유가 사라짐 — 리더 점선이 14px 더 벌어 숨쉰다) */}
      <View style={{ width: 72 }}>
        <Text style={styles.lrLabel}>{label}</Text>
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
            Alert.alert('수락 완료', '보호자에게 알림이 갔어요 — 오늘의 루트에 올라갑니다');
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

        {/* ————— ① BIB STRAP — 레이스 빕이 한 줄 스트랩으로 접혔다 (Ⓑ①). 정체성(이름·티어)과
             온라인 토글만 남는다. 빕의 대형 주간 숫자·TOTAL/TIER/DISTANCE 스탯 블록·핀·이너 프레임은 은퇴 —
             주간 스탯은 장부가 한 번만 인쇄하고 티어는 여기 한 번만. 홀로 엣지·바코드는 스트랩 높이(≈45px)에서
             아티팩트로 안 읽혀 은퇴 (홀로 예산 '표면당 티켓 엣지 1'은 머니 히어로가 가져간다).
             원라인 케이지: 320dp → 콘텐츠 264 (320 − 30 거터 − 24 패딩 − 2 보더). 토글 열 ≈ 44 트랙 +
             58 라벨('오프라인' 4×14+ls) + gap 17 ≈ 119 → 텍스트 몫 145. '민준 러너 인증 러너' ≈
             3×17(df) + 7×14 + 여백 ≈ 143 — 꼭 맞고, 긴 이름은 numberOfLines 1이 ellipsize. */}
        <Row style={styles.strap}>
          <Text style={{ flex: 1, minWidth: 0 }} numberOfLines={1}>
            <Text style={[styles.strapName, df]}>{name ?? '러너'}</Text>
            <Text style={styles.strapNameEm}> 러너</Text>
            <Text style={styles.strapTier}>  {tierLabel}</Text>
          </Text>
          {/* 온라인 토글 — 러너의 유일한 스위치, 스트랩 우측에 산다. 같은 rs.online/toggleOnline 상태 */}
          <Pressable onPress={toggleOnline} accessibilityRole="switch" accessibilityState={{ checked: rs.online }}>
            <Row style={{ alignItems: 'center', gap: 7 }}>
              <Text style={[styles.swLabel, { color: rs.online ? CORAL_INK : lilac.dim }]}>
                {rs.online ? '온라인' : '오프라인'}
              </Text>
              <View style={[styles.swTrack, rs.online ? styles.swTrackOn : styles.swTrackOff]}>
                <View style={styles.swKnob} />
              </View>
            </Row>
          </Pressable>
        </Row>

        {/* ————— ② MONEY HERO — 정산 장부가 화면의 리드 모듈 (Ⓑ① "내가 얼마 벌었나 = 0스크롤").
             실 정산 필드 바인딩 · 점선 리더 · 잉크 1.5px 보더 = 히어로 강조 ————— */}
        <View style={styles.ledger}>
          <HoloEdge />
          {/* 정산 히어로 — ₩와 금액은 baseline 정렬 + gap 4로 절대 겹치지 않음 (오버랩 FIX #2)
              [Ⓑ①] 46 → 50 승격 — 빕의 74pt가 은퇴해 ₩가 화면의 유일한 대형 숫자다. 폭: 최악 현실 주간
              '9,999,999' = 9글리프 × ~25(0.5em) = 225 + ₩(22pt ≈ 24) + gap 4 ≈ 253 < 261 콘텐츠
              (320 − 30 거터 − 24 패딩 − 3 보더). lineHeight 62 = 1.24× (BUG A). */}
          <Row style={{ alignItems: 'baseline', gap: 4, marginTop: 6 }}>
            <Text style={[styles.won, nf]}>₩</Text>
            <Text style={[styles.lBig, nf]} numberOfLines={1}>{stats.net.toLocaleString()}</Text>
          </Row>
          {/* [§3b] 'THIS WEEK' 라틴 태그 은퇴 — 주간 컨텍스트는 캡션이 한국어로 한 번 말한다 */}
          <Text style={styles.lCap}>이번 주 실수령 · 수수료 차감 후 기준</Text>
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

          {/* 주간 스탯 — 화면 유일 인쇄 (빕 재인쇄 은퇴) */}
          <View style={{ marginTop: 11, borderTopWidth: 1, borderTopColor: '#EEEEEE' }}>
            <LedgerRow label="완료 러닝" value={String(stats.runs)} unit="회" nf={nf} />
            <LedgerRow label="총 거리" value={String(stats.km)} unit="km" nf={nf} />
            <LedgerRow label="회당 평균" value={avg.toLocaleString()} unit="원" nf={nf} total />
          </View>

          <Row style={styles.lFoot}>
            {/* [2026-08-10 filler cull] the 수익 상세 link right next to this already names the destination */}
            <Text style={styles.lFootTxt}>매주 정산</Text>
            <Pressable onPress={() => router.push('/runner/earnings')}>
              <Text style={styles.lFootLink}>수익 상세 ›</Text>
            </Pressable>
          </Row>
        </View>

        {/* ————— 진행 중 작업 (관제탑의 심장) — 코랄 좌측 엣지 ————— */}
        {current && (
          <>
            <SectionHead title="진행 중" />
            <Pressable onPress={() => openJob(current)} style={({ pressed }) => [styles.now, pressed && styles.pressed96]}>
              <View style={styles.nowEdge} />
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <Row style={{ alignItems: 'center', gap: 6 }}>
                  <View style={{ width: 14, height: 14, alignItems: 'center', justifyContent: 'center' }}>
                    <PulseRings color={lilac.coral} size={14} />
                    <View style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: lilac.coral }} />
                  </View>
                  {/* [§3b status chip] 16/800, 자기 데이텀(current.when)과 같은 베이스라인 행 */}
                  <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: STAGE[current.rawStatus]?.color ?? CORAL_INK }}>
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

        {/* ————— QUEUE: 오늘 맨 앞 = 보딩패스 티켓 · 나머지 = 스텁 행. 수락/거절 = 소스 요청함 핸들러 ————— */}
        <SectionHead title="요청 대기열" link={`요청함 · ${inbox.length}건 ›`} onPress={() => router.push('/runner/requests')} />

        {inbox.length > 0 ? (
          <>
            {/* 오늘 맨 앞 예약 = 보딩패스 티켓 전문 (inbox[0]).
                [§3b] 'TODAY · FRONT REQUEST' 헤더·'COURSE/정산' 팩트 행·바코드 푸터 은퇴 — 시각이 첫 소자,
                km는 메타 한 줄에 흡수, 정산액은 수락 문이 한 번만 인쇄한다 (Ⓑ① 목업 그대로) */}
            <View style={styles.ticket}>
              <View style={styles.tMain}>
                <View style={{ paddingHorizontal: 13, paddingTop: 12, paddingBottom: 12 }}>
                  <Row style={{ justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                    <Text style={[styles.tBig, nf]}>{inbox[0].when}</Text>
                    {/* [§3b status chip] 16/800 · 보더 없는 틴트 필 · 데이텀(시각)과 같은 행 */}
                    {inbox[0].directed && (
                      <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>
                    )}
                  </Row>
                  <Row style={{ alignItems: 'center', gap: 6, marginTop: 8 }}>
                    <View style={{ width: 10, height: 12, borderRadius: 5, backgroundColor: lilac.coral }} />
                    <Text style={styles.tWhere}>{inbox[0].dogName}</Text>
                    <Text style={styles.tWhereSub}>· <Text style={[styles.tWhereSubNum, nf]}>{inbox[0].km}</Text>km · 지명 요청 픽업</Text>
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
                  {/* [실동작] 문이 곧 행동 — 수락은 여기서 끝난다. 상세(사진·메모)가 필요하면 콰이엇 문(오픈 요청)
                      [§3b] busy = 라벨 스왑만 (opacity 트릭 은퇴) · pressed = scale 0.96 · 수락 라벨 17/800 */}
                  <Pressable onPress={acceptFront} disabled={busyReq} style={({ pressed }) => [styles.door, styles.doorCoral, pressed && styles.pressed96]}>
                    <Text style={[styles.doorName, { color: '#fff', fontSize: 17 }]}>{busyReq ? '전송 중...' : '수락'}</Text>
                    {/* [2026-08-10 filler cull] ' · 바로 확정돼요' dropped — the confirm Alert states the consequence */}
                    <Text style={[styles.doorSub, { color: '#fff' }]}>
                      <Text style={[styles.doorSubNum, nf]}>{inbox[0].payout.toLocaleString()}</Text>원
                    </Text>
                  </Pressable>
                  <Pressable onPress={declineFront} disabled={busyReq} style={({ pressed }) => [styles.door, styles.doorQuiet, pressed && styles.pressed96]}>
                    <Text style={[styles.doorName, { color: lilac.head }]}>{inbox[0].directed ? '거절' : '자세히'}</Text>
                    <Text style={[styles.doorSub, { color: lilac.dim }]}>
                      {inbox[0].directed ? '다른 러너에게 넘겨요' : '메모 · 사진 · 성향 보기 →'}
                    </Text>
                  </Pressable>
                </Row>
              </View>
            </View>

            {/* 나머지 요청 = 스텁 행 (퍼포 스텁 · 장부 행). [Ⓑ①/§3b] 홀로 엣지 은퇴(예산 = 히어로 1),
                'KRW 실수령' 라틴 캡션 → '실수령', 문 라벨 '수락' → '보기 ›' 세컨더리 — 이 버튼은 수락이 아니라
                요청함으로 가는 문이었다 (라벨이 행동을 위장하던 것을 정직하게). '모두 보기' 행 삭제 —
                섹션 헤더의 '요청함 · N건 ›'이 같은 문이다 (중복 문 0). */}
            <View style={{ gap: 9, marginTop: 9 }}>
              {inbox.slice(1).map((rq, i) => (
                <View key={i} style={styles.stub}>
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
                      <Text style={styles.stubFareCap}>실수령</Text>
                    </View>
                    <Pressable onPress={() => router.push('/runner/requests')} style={({ pressed }) => [styles.stubView, pressed && styles.pressed96]}>
                      <Text style={styles.stubViewTxt}>보기 ›</Text>
                    </Pressable>
                  </View>
                </View>
              ))}
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

        {/* ————— 오늘의 루트 — 정차역 타임라인 (진행 중 + 다음 예약) ————— */}
        {routeStops.length > 0 && (
          <>
            <SectionHead title="오늘의 루트" link="캘린더 ›" onPress={() => router.push('/runner/calendar')} />
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

        {/* ————— CLUB ENGINE — 운영 코어(장부·대기열·루트) 아래로 이동 (Ⓑ① 머니 퍼스트 순서).
             클럽+호스트 로직은 컴포넌트가 보유 ————— */}
        <SectionHead title="하이클럽" />
        <View style={{ marginTop: 10 }}>
          <RunnerClubCard />
        </View>

        {/* ————— 리워드 — 티어 사다리 + 보급 드랍 트레일 (실카운트).
             [Ⓑ① 예외, Sean 2026-08-11] 카드 레이아웃은 현행 동결 — 랩의 3중 진행계 통합안 미적용 ————— */}
        <SectionHead title="리워드" link="리워드 센터 ›" onPress={() => router.push('/runner/rewards')} />
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
              return <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head }}>★ 마스터 러너</Text>;
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

        {/* ————— 러닝 가능 시간 — 요일 탭 (온라인 토글은 스트랩 위) ————— */}
        <SectionHead title="러닝 가능 시간" link="시간 조정 ›" onPress={() => router.push('/runner/availability')} />
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

        {/* ————— 최근 완료 — 패치 + 인증샷 ————— */}
        {past.length > 0 && (
          <>
            <SectionHead title="최근 완료" link="수익 상세 ›" onPress={() => router.push('/runner/earnings')} />
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
                      <Text style={styles.shotTxt}>인증샷</Text>
                    </Pressable>
                  </View>
                </Row>
              ))}
            </View>
            {/* 피드 직행 — 완료 러닝이 있는 러너만 본다 (compose.tsx가 중복 공유·전제조건을 정직하게 말한다) */}
            <Pressable
              onPress={() => router.push('/compose')}
              style={({ pressed }) => [styles.feedShare, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
              accessibilityRole="button"
              accessibilityLabel="동네 피드에 자랑하기"
            >
              <Text style={styles.feedShareTxt}>완주 기록을 동네 피드에 자랑하기 ›</Text>
            </Pressable>
          </>
        )}

        {/* ————— 동네 코스 — 헤더는 컴포넌트가 §3b 그램마로 그린다 (bleed = 패딩 컨테이너에서 풀블리드 룰) ————— */}
        <View style={{ marginTop: 8 }}>
          <CourseStrip title="동네 코스" bleed={layout.gutter} />
        </View>

        {/* ————— 퀵 링크 ————— */}
        <Row style={{ flexWrap: 'wrap', gap: 6, marginTop: 14 }}>
          <Pressable onPress={() => router.push('/leaderboard')} style={styles.qlink}>
            <Text style={styles.qlinkB}>랭킹</Text><Text style={styles.qlinkChev}>›</Text>
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

        {/* [Ⓑ① 2026-08-11] 푸터 은퇴 — 누적·티어·온라인 전부 재인쇄였다 (티어·온라인 = 스트랩,
            누적 = 리워드 트레일 '누적 N회'). 각 사실은 화면에 한 번만. */}
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
  // 피드 직행 버튼 — 최근 완료 카드 직하 · [§3b] 세컨더리 킨드: 캔버스 필 + 코랄 라인 보더 + 잉크 16/800
  feedShare: {
    marginTop: 8, minHeight: 50, alignItems: 'center', justifyContent: 'center', paddingVertical: 15,
    borderWidth: 1, borderColor: paper.line, backgroundColor: lilac.card, borderRadius: 0,
  },
  feedShareTxt: { fontSize: 16, fontWeight: '800', color: lilac.head },
  // [페이퍼 크롬] 섹션 헤더 래퍼 — 거터를 음수 마진으로 뚫은 풀블리드 코랄 1px 상단 룰
  secWrap: { marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter, borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10 },
  holo: { flexDirection: 'row', height: 3, position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },

  // [§3b 2026-08-11] 섹션 헤더 — 앱 전체 단일 그램마: 타이틀 20/800 잉크 · 우측 링크 16/800
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: lilac.head },
  secLink: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: CORAL_INK },
  // [§3b] 승인된 촉감 패턴 — 컴포지터 전용 scale 프레스 (버튼 4킨드 공통)
  pressed96: { transform: [{ scale: 0.96 }] },

  // ① 빕 스트랩 — [Ⓑ①] 빕이 한 줄로: 이름(df)·티어·온라인 토글. 케이지 산식은 JSX 주석에.
  strap: {
    marginTop: 12, backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0,
    alignItems: 'center', gap: 10, paddingVertical: 10, paddingHorizontal: 12,
  },
  strapName: { fontSize: 17, lineHeight: 22, color: lilac.head }, // 디스플레이 서체(df) 지참 — 화면당 1회 예산
  strapNameEm: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '600' },
  strapTier: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '700' },
  swTrack: { width: 44, height: 25, borderRadius: 99, padding: 3, flexDirection: 'row' },
  swTrackOn: {
    backgroundColor: lilac.coral, justifyContent: 'flex-end',
    shadowColor: lilac.coral, shadowOpacity: 0.32, shadowRadius: 9, shadowOffset: { width: 0, height: 3 },
  },
  swTrackOff: { backgroundColor: lilac.inset, justifyContent: 'flex-start', borderWidth: 1, borderColor: lilac.hair },
  swKnob: { width: 19, height: 19, borderRadius: 9.5, backgroundColor: '#fff', shadowColor: '#1C1837', shadowOpacity: 0.3, shadowRadius: 2, shadowOffset: { width: 0, height: 1 } },
  // [2026-08-10] 14 → 15 with tracking 1.2 → 1: '오프라인' width stays ≈ 63px (4×15 + 3×1 vs 4×14 + 3×1.2),
  // so the toggle column footprint next to the strap name is unchanged — the switch layout still fits.
  swLabel: { fontSize: 15, lineHeight: 19, letterSpacing: 1, fontWeight: '700' },

  // ② 머니 히어로 장부 — [Ⓑ①] 잉크 1.5px 보더 = 히어로 강조 (구 이중 프레임 card+ledgerIn 은퇴 → 단일 박스)
  ledger: {
    marginTop: 12, backgroundColor: lilac.card, borderWidth: 1.5, borderColor: lilac.head, borderRadius: 0,
    paddingHorizontal: 12, paddingTop: 11, paddingBottom: 10, overflow: 'hidden',
  },
  // [§3b status chip] 16/800 · 보더 없는 틴트 필 · 샤프 (앰버 = 시맨틱 지명 신호)
  monoTagStar: { backgroundColor: lilac.amberSoft, borderRadius: 0, paddingHorizontal: 7, paddingVertical: 2 },
  monoTagStarTxt: { fontSize: 16, lineHeight: 20, letterSpacing: 0.5, color: lilac.amber, fontWeight: '800' },
  // ₩와 금액은 baseline 정렬 · won은 flexShrink 0로 자기 폭 확보, 금액은 numberOfLines 1 (오버랩 FIX #2)
  // BUG A: 둘 다 lineHeight ≥1.2×fontSize, includeFontPadding 제거 → "₩0"의 0이 온전한 타원으로
  // [Ⓑ①] 46/58 → 50/62 승격 (폭 산식은 JSX 주석), won 20/25 → 22/28 비례
  won: { fontSize: 22, color: CORAL_INK, lineHeight: 28, flexShrink: 0 },
  lBig: { fontSize: 50, color: lilac.head, lineHeight: 62, letterSpacing: 0.2, flexShrink: 1 },
  lToday: { fontSize: 14, fontWeight: '700', color: '#3D6B1F', marginTop: 7 },
  lTodayNum: { fontSize: 16, fontWeight: '700' },
  // 월·누적 행 — 히어로 아래 조용한 보조 창. Oswald 숫자는 lineHeight ≥1.2× (BUG A 법)
  // [Ⓑ① re-derive] ledger content = 320 − 30 gutter − 24 pad − 3 borders(1.5×2) ≈ 263px (구 이중
  // 프레임 252 산식 폐기); '이번 달 ₩9,999,999 · 누적 ₩9,999,999' ≈ 2×(46 + 10 + 9×8.8) + 18 ≈ 250px
  // — worst case still one line, deeper sums wrap via flexWrap (by design). NOT the LedgerRow 72px
  // label cage below.
  lWin: { alignItems: 'baseline', gap: 5, marginTop: 8, flexWrap: 'wrap' },
  lWinK: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '600' },
  lWinV: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head },
  lWinNum: { fontSize: 16, lineHeight: 20, color: lilac.head },
  lWinSep: { fontSize: 12, lineHeight: 16, color: lilac.dim }, // 글리프 전용(·) 구분자 — 플로어 면제
  lCap: { marginTop: 6, fontSize: 14, color: lilac.dim, lineHeight: 18 },
  lr: { alignItems: 'baseline', gap: 7, paddingTop: 7, paddingBottom: 6, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  lrLabel: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
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
    borderRadius: 0, alignItems: 'center', justifyContent: 'center', paddingVertical: 15, backgroundColor: CORAL_INK, // [§3b] pv 13 → 15 (버튼 공통 플로어) · 샤프 · 코랄 필 = 시맨틱 CTA 생존
    borderWidth: 1, borderColor: CORAL_INK_DEEP,
  },
  btnCoralTxt: { fontSize: 17, lineHeight: 22, fontWeight: '800', color: '#fff' }, // [§3b] 16/700 → 17/800 (프라이머리급 라벨)

  // ① 티켓 — [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴 (퍼포레이션 아티팩트 생존 · [Ⓑ①] 홀로/바코드는 예산 은퇴)
  ticket: { marginTop: 9 },
  tMain: { backgroundColor: lilac.card, borderTopLeftRadius: 0, borderTopRightRadius: 0, borderWidth: 1, borderBottomWidth: 0, borderColor: '#EEEEEE', overflow: 'hidden' },
  // BUG A: 티켓 시각 31pt → lineHeight 39 (1.26×), includeFontPadding 제거 — "0" 상단 온전
  tBig: { fontSize: 31, color: lilac.head, lineHeight: 39 },
  tWhere: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  tWhereSub: { fontSize: 14, lineHeight: 18, color: lilac.dim },
  tWhereSubNum: { fontSize: 14, lineHeight: 18, color: lilac.head }, // km 숫자 = Oswald (메타 줄에 흡수된 구 COURSE 팩트)
  perfWrap: { backgroundColor: lilac.card, borderLeftWidth: 1, borderRightWidth: 1, borderColor: '#EEEEEE', position: 'relative' },
  perf: { borderTopWidth: 1.5, borderTopColor: '#DCD7F0', borderStyle: 'dashed' },
  perfNotch: { position: 'absolute', top: -8, width: 16, height: 16, borderRadius: 8, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' }, // 노치 = 캔버스 구멍 (원형은 퍼포 아티팩트 예외)
  tStub: { backgroundColor: lilac.card, borderBottomLeftRadius: 0, borderBottomRightRadius: 0, borderWidth: 1, borderTopWidth: 0, borderColor: '#EEEEEE', paddingHorizontal: 13, paddingTop: 11, paddingBottom: 12 },
  door: { flex: 1, borderRadius: 0, paddingVertical: 15, paddingHorizontal: 11, overflow: 'hidden' }, // [§3b] 샤프 · pv 12 → 15 (버튼 공통 플로어)
  doorCoral: { backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP }, // 코랄 글로우 섀도 은퇴
  doorQuiet: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE' },
  doorName: { fontSize: 16, lineHeight: 22, fontWeight: '800' }, // 수락 문은 인라인 17로 승격 (프라이머리급) · 거절/자세히 16/800
  doorSub: { marginTop: 4, fontSize: 14, lineHeight: 18 },
  doorSubNum: { fontSize: 14, lineHeight: 18 },

  // 스텁 행 — 목업 .s-act width 92 → 96 (FIX3: 11.5pt 캡션 한 줄 여유 확보, 구조는 동일)
  stub: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, overflow: 'hidden' }, // [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴
  stubNm: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: lilac.head },
  stubKm: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head },
  stubKmUnit: { fontSize: 14, color: CORAL_INK, fontWeight: '600' },
  stubWhen: { fontSize: 14, lineHeight: 18, color: lilac.dim, fontWeight: '500' },
  // [Ⓑ① re-derive] 112 케이지 유지. 캡션이 'KRW 실수령' → '실수령'(한글 3자 ≈ 3×14 + ls = 45px)으로 줄어
  // 최장 소자는 이제 요금 숫자('999,999' 7글리프 × ~8.5 ≈ 60px)와 '보기 ›' 라벨(2×16 + 12 ≈ 44px) —
  // 60 + 패딩 16 = 76 < 112 (기기 폰트 스케일 여유 36px).
  stubAct: { width: 112, borderLeftWidth: 1.4, borderStyle: 'dashed', borderLeftColor: '#DCD7F0', paddingVertical: 11, paddingHorizontal: 8, alignItems: 'center', justifyContent: 'center', gap: 7 },
  stubNotch: { position: 'absolute', left: -6, width: 12, height: 12, borderRadius: 6, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', zIndex: 3 },
  // BUG A: 스텁 요금 17pt → lineHeight 22 (1.29×), includeFontPadding 제거
  stubFare: { fontSize: 17, lineHeight: 22, color: lilac.head },
  stubFareCap: { fontSize: 14, lineHeight: 18, letterSpacing: 0.5, color: lilac.dim, fontWeight: '500', marginTop: 2 }, // [§3b] 한글 캡션 — 라틴 자간 1 → 0.5
  // [§3b] 세컨더리 킨드 — 캔버스 필 + 코랄 라인 보더 + 잉크 16/800 (구 코랄 필 '수락'은 요청함으로 가는
  // 문이었다 — 라벨과 킨드를 정직하게)
  stubView: { width: '100%', borderRadius: 0, paddingVertical: 15, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: paper.line },
  stubViewTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: lilac.head },
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

  // 퀵 링크 — 목업 .qlink padding 10 11 (푸터 스타일은 Ⓑ① 재인쇄 은퇴와 함께 삭제)
  qlink: { flexBasis: '48%', flexGrow: 1, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 6, backgroundColor: paper.canvas, borderWidth: 1, borderStyle: 'dashed', borderColor: '#EEEEEE', borderRadius: 0, paddingVertical: 10, paddingHorizontal: 11 }, // [페이퍼 크롬] 글래스 은퇴
  qlinkB: { fontSize: 14, fontWeight: '600', color: lilac.head },
  qlinkChev: { fontSize: 12, color: lilac.dim }, // 글리프 전용(›) 셰브런 — 플로어 면제
});
