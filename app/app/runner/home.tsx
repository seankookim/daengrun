import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Avatar } from '../../src/components/ui';
import { BrandMark } from '../../src/components/brandmark';
import { TabSwipe } from '../../src/components/tabswipe';
import { CourseStrip } from '../../src/components/CourseStrip';
import { RunnerClubCard } from '../../src/components/clubcard';
import { Icon, Row } from '../../src/components/ui';
import {
  acceptBooking, AvailRule, CoursePatch, declineBooking, fetchBookingAddress, fetchCoursePatches, fetchMyAvailability, fetchMyName, fetchMyRunnerStatus, fetchInFlightRunnerJobs, fetchRunnerInbox, fetchRunnerJobs,
  fetchRunnerWeekStats, fetchUnreadCount, MyRunnerStatus, OpenRequest, PickupAddress, RunnerJob, RunnerWeekStats, saveMyAvailability, setRunnerOnline,
} from '../../src/lib/api';
import { PatchBadge } from '../../src/components/patch';
import { registerPushToken } from '../../src/lib/push';
import { haptic } from '../../src/lib/haptics';
import { lateness } from '../../src/lib/lateness';
import { CheckinAnswer } from '../../src/components/checkin-answer';
import { LateNotice } from '../../src/components/late-notice';
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
// detail-text floor (DESIGN.md §3). Only latin letterspaced caps kickers, serial/MRZ strings and
// barcode/glyph-only marks stay below it; Korean data never rides a kicker style.
// 2026-08-25 (Sean, on the owner home: "very small font text sizes; not acceptable and are illegible"):
// the WORKING Korean floor is **15**, not 14 (DESIGN.md §2 amendment). 14 survives only as the absolute
// minimum for the exempt classes above. Every Korean site on this screen that sat at 14 moved to 15 with
// lineHeight 20 (1.33×); the two glyph-only marks (12pt ▣ · qlinkChev ›) stayed where they are.
// 2026-08-11 Ⓑ① MONEY FIRST (declutter-lab, Sean pick "b1 + keep the rewards layout"):
// 장부(₩ 히어로)가 화면의 리드 모듈, 레이스 빕은 한 줄 스트랩(이름·티어·온라인 토글)으로 접혔다.
// 중복 인쇄 0: tierLabel 1회(스트랩), 주간 러닝/거리/평균 1회(장부), 온라인 1회(스트랩) — 푸터·마스트헤드
// 키커 은퇴. §3b 그램마: 섹션 헤더 = 코랄 풀블리드 룰 + 타이틀 20/800 (라틴 키커·서브타이틀·01~06 넘버 전부 은퇴).
// 리워드 카드는 Sean 지시로 현행 레이아웃 동결 (3중 진행계 포함 — 랩의 통합안 미적용).
//
// 2026-08-19 journey v4 (R1a/R1b, docs/labs/journey-v4-runner.html) — money is ONE line:
//  · The ₩50 pt ledger hero is RETIRED (with it: 이번 달 / 누적 / 오늘 확보·예정 / the three ledger
//    rows). What replaces it is a single factual week row bound to the same fetchRunnerWeekStats —
//    "이번 주 N회 · Nkm · 정산 예정 N원", every `stats === null ? '—'` guard preserved.
//    ⚠ fetchLedgerMonth now has NO caller anywhere in the client (earnings.tsx keeps 누적 only).
//  · The online toggle leaves the bib strap and becomes one big INK switch on canvas. On = ink,
//    never coral: being online is a STATE, not an action, and a coral switch reads as "turn me on".
//    The strap keeps identity only (name in the display font — the screen's one display budget).
//  · 진행 중 and the front request are both TICKET OBJECTS (1.5 px ink border + perforation).
//    The 진행 중 card's coral action BAR is retired → an ink action line; the screen's single coral
//    is the 수락 door. While a run is `active` the STAGE map already paints 러닝 중 · LIVE coral, so
//    the 수락 door drops to an ink-outline ghost for that state — one coral, always the moment's own.
//  · Section links go coral → ink (six coral chevrons was six climaxes).
//  · Omitted deliberately: the lab's "홈 베이스 반경 3km" (no home-base coordinate column, and
//    MyRunnerStatus carries no radius) and its "지명 요청도 오프라인이면 오지 않아요" (measured false —
//    fetchRunnerInbox's directed leg has no online filter, api.ts:826-830).

// 2026-08-24 runner-home enhancement wave (docs/labs/enh-runner-home-lab.html · Sean, verbatim:
// "For runner home I like all new updates you are showing me"). Shape ① is settled and nothing
// below adds, removes or reorders a module — every change lives inside 온라인 토글 / 이번 주 /
// 요청 대기열 / the empty state.
//  · A④ the switch says what it actually does. `online` is read by exactly three surfaces and the
//    open pool is none of them (measured: 0056's marketplace_open_requests has no online predicate,
//    its gate is is_active_runner(); 0054 runners_available_for and fetchCertifiedRunners are the
//    ones that read r.online = true). The old offline sub-line 「새 요청이 멈춰 있어요」 was the
//    biggest false claim on this screen.
//  · A③ 오늘 — one row above 이번 주, from jobs already in memory + the isTodayKst() below.
//  · A② the front request gets its face (OpenRequest.photoUrl was fetched and never drawn) and the
//    expiry sentence 0080 actually enforces.
//    ✔ [2026-08-25] The held half landed. `OpenRequest.scheduledAt` (raw ISO) reached both mappers
//    on 2026-08-24, so the request ticket now promotes the countdown and demotes the clock exactly
//    like the 진행 중 ticket above it, and the stub rows carry the same relative time. The countdown
//    is derived from the RAW field and never from the typeset `when` — that re-parse is the thing
//    RunnerJob.scheduledAt exists to prevent, and it would have given this screen two clocks.
//    The deadline is not a policy number: expire_unmatched_bookings (0080 ⓐ) deletes a matching /
//    runner_pending booking when `scheduled_at < now()`, so the run's own start time IS the deadline.
//  · A① the quiet day explains itself — 온라인 · 러닝 가능 시간 as two summary rows (the second a
//    real door to the editor) + the sentence that kills the wrong inference.
const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const DAY_NAME = '일월화수목금토';
const hh = (m: number) => String(Math.floor(m / 60)).padStart(2, '0');
const hhmm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

// [A① 2026-08-24] 가용시간 한 줄 요약 — 빈 상태의 두 번째 요약 행. requests.tsx:65가 이미 쓰는
// 함수를 그대로 가져온다 (통합하지 않는 이유: 네 줄짜리 표시 포맷터를 api.ts로 올리면 데이터 층에
// 표시 어휘가 생긴다). 이 함수가 **지어내지 않는** 두 가지가 요점이다 — 요일마다 시간이 다르면
// 시간을 만들지 않고 「요일마다 다름」이라 말하고, 빈 규칙 집합은 「아직 설정 안 했어요」가 아니라
// 「설정된 요일이 없어요」다 (모든 요일을 끈 러너는 그 빈 집합을 **의도적으로** 저장한다 —
// availability.tsx:92-95). 로딩·실패는 호출부가 가른다: avail이 null이면 행 자체를 그리지 않는다.
const availSummary = (rules: AvailRule[]): string => {
  if (rules.length === 0) return '설정된 요일이 없어요';
  const same = rules.every((r) => r.startMin === rules[0].startMin && r.endMin === rules[0].endMin);
  return same
    ? `주 ${rules.length}일 · ${hhmm(rules[0].startMin)}–${hhmm(rules[0].endMin)}`
    : `주 ${rules.length}일 · 요일마다 다름`;
};

// 코랄-텍스트 법: 흰 텍스트는 오직 어두운 터미널 스톱(≥ #C6472C, 백지 4.84:1) 위에.
// 밝은 --coral(#F0765A)은 fill/edge/dot·글로우 섀도로만 생존, 절대 그 위에 흰 소자 텍스트 금지.
// [액션 롤아웃 2026-08-11] 이 화면이 들고 있던 로컬 코랄 상수 두 개는 은퇴한다.
// CORAL_INK은 paper.action과 **같은 값**이었고 (#C6472C), CORAL_INK_DEEP(#B23E25)은
// actionPressed(#A83315)와 분리도 1.1로 눈에 구분되지 않는 중복 헥스였다. 한 화면이 자기
// 팔레트를 들고 있으면 시스템이 두 개가 된다 — 토큰 하나로 접는다.
const CORAL_INK = paper.action;
const CORAL_INK_DEEP = paper.actionPressed;

const TIER_LABEL: Record<string, string> = { certified: '인증 러너', veteran: '베테랑', master: '마스터' };

// 이 시각이 **오늘(KST)** 인가. 한국은 DST가 없어 고정 오프셋 산술로 충분하다 (서버 kstParts·
// owner/home의 kstDayDiff와 같은 전제). 기기 로컬 타임존이 아니라 Asia/Seoul 고정 — 시뮬레이터가
// UTC이거나 사용자가 해외면 로컬 날짜는 하루 어긋난다.
const KST_MS = 9 * 3_600_000;
const kstDay = (ms: number) => new Date(ms + KST_MS).toISOString().slice(0, 10);
const isTodayKst = (iso: string | null) => {
  if (!iso) return false;
  const t = Date.parse(iso);
  return !Number.isNaN(t) && kstDay(t) === kstDay(Date.now());
};

// 세션 동안 거절한 요청 id — 오픈 풀로 되돌아와도 내 큐에 재등장하지 않게 (모듈 레벨: 리마운트 생존)
const declinedIds = new Set<string>();

// 진행 단계 메타 — 서버 상태 → 러너가 지금 뭘 해야 하는지 (라벨·액션 동결, 색만 라일락으로 재매핑)
// ── A · TIME PRESSURE ─────────────────────────────────────────────────────────────────────
// The ticket printed a clock ("5:00"), which cannot answer the only question a runner in transit
// actually has: am I late? The relative form can, and it is the value that changes what they do
// next — so it takes the big slot and the clock demotes to the quiet line beneath.
// `late` is a MEASURED delay, not manufactured urgency, so it is allowed to spend critical ink
// (the 지어낸 긴급함 = 학습된 무시 law forbids inventing pressure, not reporting it).
// Returns null when there is no timestamp — the caller then keeps the plain clock rather than
// guessing, because "no scheduled_at" is not "on time".
// The coral button's second line. Says what the stage means for the runner right now rather than
// repeating the label above it — an empty subline would be decoration, so every stage has one.
function stageSub(rawStatus: string, dogName: string): string {
  switch (rawStatus) {
    case 'confirmed': return `${dogName}에게 출발할 시간이에요`;
    case 'runner_enroute': return `${dogName}를 넘겨받을 시간이에요`;
    case 'picked_up': return '보호자와 인계를 마쳤어요 — 시작해요';
    case 'active': return '러닝 기록이 쌓이는 중이에요';
    default: return '이어서 진행해요';
  }
}

const LATE_CAP_MIN = 12 * 60;   // beyond half a day late, it is a stranded booking, not a late runner
const AHEAD_CAP_MIN = 24 * 60;  // beyond a day out, "N시간 뒤" is not a thing anyone acts on

function relWhen(iso: string | null): { text: string; late: boolean } | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const min = Math.round((t - Date.now()) / 60000);
  // ⚠ BOTH ENDS ARE CLAMPED, and the reason was only visible on a device. Sean's stale Aug-4
  // fixture rendered 「400시간 59분 늦음」 in critical red across the whole ticket — at that scale the
  // relative form stops being information and becomes a number nobody can act on, shouting. Past a
  // half-day the fact is not "the runner is late", it is "this booking is stranded", so say that
  // instead; past a day ahead the countdown is not actionable either and the date does the work.
  if (min < -LATE_CAP_MIN) return { text: '지난 예약', late: true };
  if (min > AHEAD_CAP_MIN) return null;   // keep the clock + date — a countdown adds nothing here
  if (min < 0) {
    const l = Math.abs(min);
    return { text: l >= 60 ? `${Math.floor(l / 60)}시간 ${l % 60}분 늦음` : `${l}분 늦음`, late: true };
  }
  if (min === 0) return { text: '지금', late: false };
  return { text: min >= 60 ? `${Math.floor(min / 60)}시간 ${min % 60}분 뒤` : `${min}분 뒤`, late: false };
}

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

export default function RunnerHome() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면당 1회 (빕 네임)
  const nf = useNumFont();     // 숫자 서체 — Oswald tabular
  const [inbox, setInbox] = useState<OpenRequest[]>([]);
  // [honesty 2026-08-11] inbox fetch failure used to render the online empty copy
  // ("지금은 새 요청이 없어요") — a quiet day fabricated from a network error.
  const [inboxLoaded, setInboxLoaded] = useState(false);
  const [inboxErr, setInboxErr] = useState(false);
  const [name, setName] = useState<string | null>(null);
  // [honesty 2026-08-11] weekly stats used to seed {net: 0} → the money hero printed
  // ₩0 in flight and on failure. null = not known yet → '—' (0원 위장 금지).
  const [stats, setStats] = useState<RunnerWeekStats | null>(null);
  const [unread, setUnread] = useState(0); // 미읽음 알림 실카운트 — 벨 도트의 유일한 근거
  const [jobs, setJobs] = useState<RunnerJob[]>([]);
  // [B9 · codex 2026-08-21] fetchRunnerJobs 도 scheduled_at DESC + limit 20 이다 — 보호자 홈에서
  // 고친 것과 **같은 결함이 러너 홈에 남아 있었다**. 진행 중인 일은 지금(= 그 20건보다 과거)이라
  // 미래 일정이 20건을 넘으면 창 밖으로 밀려나고, 개를 데리고 있는데 '진행 중'이 사라진다.
  // 캡 없는 진행 중 읽기를 합쳐 그 행이 **목록에 있게**만 한다 — current 의 선택 규칙은 그대로다.
  const loadJobs = useCallback(() => {
    Promise.all([fetchRunnerJobs(), fetchInFlightRunnerJobs()])
      .then(([js, inFlight]) => {
        const seen = new Set(js.map((j) => j.bookingId));
        const liveById = new Map(inFlight.map((j) => [j.bookingId, j]));
        setJobs(inFlight.length
          ? [...js.map((j) => liveById.get(j.bookingId) ?? j), ...inFlight.filter((j) => !seen.has(j.bookingId))]
          : js);
      })
      .catch((e) => console.warn('[rhome] jobs:', e?.message ?? e));
  }, []);
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
  // [Ⓑ② 2026-08-12] 가용시간 접기 — 순수 표시 상태. 기본은 접힘(요약이 기본값이라 접기가 의미를 갖는다).
  // avail 데이터·toggleDay·3개 술어와 아무 관계 없다.
  const [availOpen, setAvailOpen] = useState(false);
  const availDays = avail?.length ?? 0;
  // [E7 2026-08-12] 기록면이 이 화면으로 오면서 rs 로드가 **재시도 가능한 문**을 갖게 됐다 —
  // 실패 스트립의 '다시 시도'가 부를 대상. 포커스 이펙트도 이걸 쓴다 (한 곳에서만 로드).
  const reloadStatus = useCallback(() => {
    fetchMyRunnerStatus()
      .then((v) => { setRs(v); setRsErr(false); })
      .catch((e) => { console.warn('[rhome] status:', e?.message ?? e); setRsErr(true); })
      .finally(() => setRsLoaded(true));
  }, []);

  // [Sean] 거절한 요청은 다시 안 본다 — 서버 정본은 0056 booking_declines(뷰 제외). 이 Set은 거절 POST와
  // 다음 fetch 사이 깜빡임을 막는 낙관 레이어 + 로그 기록 실패(엣지 fn fail-open)의 폴백.
  // ⚠ 오픈 레그만 거른다 — 지명 레그(directed)까지 거르면 '거절 후 보호자가 다시 콕 집은' 정당한
  // 재지명이 영영 안 보여 만료까지 썩는다 (0056이 일부러 살려둔 경로 — 적대 리뷰 P1).
  const filterDeclined = (list: OpenRequest[]) => list.filter((r) => r.directed || !declinedIds.has(r.bookingId));

  // [실동작] 홈 티켓의 수락/거절 — 라벨만 있고 요청함으로 도망가던 문을 진짜 문으로.
  const reloadQueue = () => {
    loadInbox();
    loadJobs();
  };
  const acceptFront = () => {
    const rq = inbox[0];
    if (!rq || busyReq) return;
    // [honesty 2026-08-19] '실수령'은 확정 금액을 뜻하는데 이 값은 추정치다 (서버가 실거리·수수료율로
    // 확정 — api.ts:427). requests.tsx:76이 이미 교정한 문장을 같은 행동의 두 번째 문에도 맞춘다.
    Alert.alert('요청 수락', `${rq.dogName} · ${rq.when}\n예상 ${rq.payout.toLocaleString()}원 (실거리로 확정) — 수락할까요?`, [
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

  const loadInbox = useCallback(() => {
    setInboxErr(false);
    fetchRunnerInbox()
      .then((l) => { setInbox(filterDeclined(l)); setInboxLoaded(true); })
      .catch((e) => { console.warn('[rhome] inbox:', e?.message ?? e); setInboxErr(true); });
  }, []);

  // [honesty 2026-08-20 · runner journey T3] This fetch was a silent catch, so a failed load
  // printed 「불러오는 중...」 forever: loading and failure were the same sentence and there was
  // no way back — the runner watches a spinner-shaped lie until they leave the screen.
  // Three-stated on the model the editor screen already carries (availability.tsx:49-60 load +
  // :126-141 loading / loud-fail-with-retry), so both surfaces of the same data fail alike.
  // ⚠ `avail` stays null on failure ON PURPOSE. It is not just the loading flag: toggleDay
  // writes the WHOLE rule set back and saveMyAvailability is delete-all-then-insert
  // (api.ts:1650-1657), so seeding an empty week from a failed read would let one chip tap
  // erase every slot the runner actually has (the same trap availability.tsx:45-48 names).
  const [availErr, setAvailErr] = useState(false);
  const loadAvail = useCallback(() => {
    setAvailErr(false);
    fetchMyAvailability()
      .then(setAvail)
      .catch((e) => { console.warn('[rhome] avail:', e?.message ?? e); setAvailErr(true); });
  }, []);

  useFocusEffect(useCallback(() => {
    loadAvail();
    loadInbox();
    fetchMyName().then(setName).catch(() => {});
    fetchRunnerWeekStats().then(setStats).catch((e) => console.warn('[rhome] stats:', e?.message ?? e));
    fetchUnreadCount().then(setUnread).catch((e) => console.warn('[rhome] unread:', e?.message ?? e));
    loadJobs();
    fetchCoursePatches()
      .then(({ earned }) => setPatchMap(Object.fromEntries(earned.map((pt) => [pt.routeId, pt]))))
      .catch(() => {});
    registerPushToken(); // APNs (0024) — 러너는 푸시가 곧 수입 (요청 도착 알림)
    reloadStatus();
  }, [loadAvail, loadInbox, loadJobs, reloadStatus]));

  // 온라인 토글 — 실저장 (오프라인이면 추천·동네 러너 셸프에서 빠짐). 빕 위 스위치가 이 상태를 쓴다.
  // [honesty 2026-08-19 · runner review #7] 저장이 실패하면 낙관 플립을 되돌리는 것까지는 옳았지만,
  // 되돌림이 console.warn 하나뿐이라 스위치가 **이유 없이 제자리로 튕겼다**. v4가 이 컨트롤을
  // 56×32 자기 행으로 승격하면서 그 침묵이 더 눈에 띈다 — 되돌림은 유지하고, 왜 되돌렸는지 말한다.
  const toggleOnline = () => {
    const next = !rs.online;
    setRs((v) => ({ ...v, online: next }));
    setRunnerOnline(next).catch((e) => {
      setRs((v) => ({ ...v, online: !next }));
      console.warn('[rhome] online:', e?.message ?? e);
      Alert.alert('온라인 상태를 바꾸지 못했어요', '다시 시도해주세요');
    });
  };

  // 요일 탭 = 즉시 열기/닫기 (저장 버튼 없음 — 충동적 슬롯 오픈은 홈에서 바로)
  // [honesty 2026-08-20 · runner journey T2] Same defect the function above was fixed for, one
  // control over: the optimistic flip was reverted on a failed save with nothing but a
  // console.warn, so the 토 chip lit up and then bounced back「이유 없이 제자리로」. A runner reads
  // that as a broken app and stops opening slots — supply we lose without ever hearing why.
  // The revert is right and stays; what was missing is saying that the SERVER refused it.
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
      Alert.alert('가용시간을 저장하지 못했어요', '다시 시도해주세요');
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
  // [v4] 회당 평균·오늘 확보 합·이번 달/누적은 히어로와 함께 은퇴했다 (돈은 한 줄). 파생값도 같이 간다 —
  // 계산만 남아 아무도 읽지 않는 상태가 다음 세션에게는 "여기 있었는데 왜 안 그리지?"가 된다.
  // 화면의 유일한 코랄 소유권: LIVE(active) 러닝이 있으면 그 카드가 가져가고, 수락 문은 고스트로 내려간다.
  // ⚠ WIDENED from `active` only. The rule was "the LIVE run owns coral, the 수락 door otherwise",
  // which left every pre-run stage (confirmed · runner_enroute · picked_up) with no coral owner at
  // all — and when the inbox was also empty, no coral on the screen whatsoever. Any in-flight job
  // now owns it, because a dog already committed outranks a request nobody has accepted.
  const liveOwnsCoral = current != null;

  // [A② 2026-08-25] 맨 앞 요청의 카운트다운. 진행 중 티켓과 **같은 함수**를 쓴다 (relWhen) —
  // 화면 하나에 상대시각 포맷터가 둘이면 두 티켓이 같은 사실을 다르게 말한다.
  // ⚠ 한 번만 계산해서 두 줄(큰 슬롯 · 강등된 시계)이 나눠 쓴다. 두 번 부르면 Date.now()를 두 번
  //   읽어 같은 렌더 안에서 분이 어긋날 수 있다.
  // ⚠ `late`면 카운트다운을 그리지 않는다 (아래 티켓은 시계를 그대로 유지한다). 시작 시각이 지난
  //   요청은 '늦은' 것이 아니라 **만료 대상**이고(0080 ⓐ), relWhen의 지각 어휘(「N분 늦음」·
  //   「지난 예약」)는 러너를 탓하는 말이다 — 아무도 늦지 않았다. 크론이 아직 안 돌았을 뿐이라
  //   부재로 둔다: 없는 사실을 지어내는 것보다 안 말하는 쪽이 이 파일의 법이다.
  const frontRel = inbox.length > 0 ? relWhen(inbox[0].scheduledAt) : null;
  const frontAhead = frontRel && !frontRel.late ? frontRel : null;

  // when 문자열 파싱 — 마지막 토큰 = 시간, 앞 = 요일/날짜 (소스 다음예약 파싱과 동일)
  const parseWhen = (w: string) => {
    const i = w.lastIndexOf(' ');
    return i < 0 ? { wd: '', wt: w } : { wd: w.slice(0, i), wt: w.slice(i + 1) };
  };

  // [A③ 2026-08-24] 오늘 — 이번 주 위의 한 줄. 이번 주는 "이번 주가 어땠나"에 답하고, 아침 6시에
  // 앱을 여는 러너의 질문은 다른 것이다: **오늘 얼마나 남았나**. 두 값 다 이미 메모리에 있다
  // (jobs + 이 파일이 이미 정의한 isTodayKst — 오늘의 루트가 쓰는 그 함수).
  // ⚠ 이 줄은 오늘의 루트와 **같은 사실을 두 번** 쓴다 (요약 ↔ 상세). 랩이 그 사실을 숨기지 않고
  // 이름 붙여 올렸고 Sean이 전부 채택했으므로 둘 다 남긴다 — 요약은 개수와 다음 시각, 상세는
  // 정차역마다 개·거리·금액. 로딩/실패에는 jobs가 빈 배열이라 행 자체가 그려지지 않는다 ('0건' 없음).
  const todayJobs = jobs
    .flatMap((j) => (j.status !== 'completed' && isTodayKst(j.scheduledAt)
      ? [{ job: j, t: Date.parse(j.scheduledAt as string) }] : []))
    .sort((a, b) => a.t - b.t);
  // 다음 = 오늘 것 중 **아직 오지 않은** 가장 이른 것. 랩의 바인딩은 "그중 가장 이른 것"이지만,
  // 오늘 오전 7:30에 잡혀 아직 안 끝난 예약을 저녁 8시에 「다음 오전 7:30」이라 부르면 '다음'이라는
  // 말이 거짓이 된다 (그 상황은 실제로 존재한다 — 홈이 '지난 예약'을 클램프하는 이유와 같은 사실).
  // 지나간 건뿐이면 건수만 인쇄한다: 개수는 여전히 참이고, 없는 '다음'을 만들지 않는다.
  // `when` = `${dateLabel} ${timeLabel}`이고 timeLabel은 '오후 7:30'이라, parseWhen의 wd 꼬리가
  // 오전/오후이고 wt가 시각이다 (api.ts kstParts:728-729).
  const nextTodayJob = todayJobs.find((x) => x.t >= Date.now()) ?? null;
  const nextToday = nextTodayJob ? parseWhen(nextTodayJob.job.when) : null;
  const nextTodayMer = nextToday ? (nextToday.wd.split(' ').pop() ?? '') : '';

  // 오늘의 루트 — 진행 중 + 다음 예약을 정차역 타임라인으로 (모든 job 데이터·openJob 보존)
  // ⚠ [sim walk 2026-08-25] the header says 오늘의 루트, and the fixture put an Aug-4 enroute row
  // under it three weeks later — `current` is "the runner's live job" with no day predicate, so a
  // rotted in-flight booking leaked into a section whose name is a date claim. Gate it on the
  // section's own word (isTodayKst — the same helper every other 오늘 fact here uses). A stale
  // live job LOSES NOTHING: the 진행 중 ticket above still owns it unconditionally.
  const routeStops: { job: RunnerJob; kind: 'on' | 'next' }[] = [
    ...(current && isTodayKst(current.scheduledAt) ? [{ job: current, kind: 'on' as const }] : []),
    ...upcoming.map((j) => ({ job: j, kind: 'next' as const })),
  ];

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>{/* [페이퍼 크롬] 라일락 캔버스 은퇴 → 백지 */}
      {/* [2026-08-12] 탭 스와이프 — 상단 크롬(브랜드 마크+벨)까지 함께 민다. 도크만 제자리. */}
      <TabSwipe>
      {/* ————— 상단 크롬 — 플레인 화이트 + 코랄 헤어라인 · 브랜드 마크 + 알림 벨 —————
           [정체성 2026-08-11 · Sean 재정] 보호자 홈은 **패스포트**(브랜드 마스트헤드), 러너 홈은
           **빕**(아래 스트랩). 이 규칙으로 오늘 아침 '다' 글리프 칩 + 'RUNNER' 키커를 뺐는데 —
           그 둘이 지운 말은 "너는 러너다"였고, 그건 빕이 이미 하는 말이라 옳은 삭제였다.
           브랜드 마크가 하는 말은 "도그스하이"다. 다른 주장이므로 중복 인쇄가 아니다.
           그래서 **마크만** 온다(워드마크 없음): 브랜드 정체성은
           크롬이 한 번, 러너 정체성은 빕이 한 번. 한 화면 한 번 법은 그대로 산다. */}
      {/* [2026-08-20 Sean] 보호자 홈과 같은 로고를 러너에도 — 마크 + 한글 워드마크, 가운데 정렬.
          벨은 absolute로 빠져야 로고가 남은 폭이 아니라 화면의 실제 가운데에 앉는다.
          ⚠ 디스플레이 서체(df)가 이 화면에서 두 번째로 쓰인다: 여기 워드마크와 빕 스트랩의
          러너 이름(styles.strapName, :1100의 주석이 '화면당 1회 예산'이라고 못박아 둔 그 한 번).
          DESIGN.md §3 예산은 화면당 1회이므로 이건 초과다 — 로고 예외(§3 :112)는 14pt 하한에
          관한 것이지 이 예산에 관한 것이 아니다. Sean의 "같은 로고를 러너에도"가 명시적 지시라
          그대로 넣되, 둘 중 무엇이 df를 양보할지는 그의 판단으로 남긴다. 조용히 고르지 않는다. */}
      <View style={styles.top}>
        {/* 좌측 스페이서 = 벨 폭. 벨을 absolute로 빼면 행에서 빠져 높이가 콘텐츠(24pt 마크)로
            주저앉고, 로고가 다이내믹 아일랜드 위로 올라탄다 — 시뮬레이터에서 실제로 그렇게 됐다.
            대칭 스페이서는 벨을 흐름에 남겨 40pt 행 높이를 지키면서 로고를 화면 정중앙에 놓는다. */}
        <View style={styles.topSpacer} />
        <View style={styles.topLogo}>
          <BrandMark height={24} />
          <Text style={[styles.wordmark, df]}>도그스하이</Text>
        </View>
        <Pressable onPress={() => router.push('/alerts')} style={styles.bell} accessibilityLabel="알림">
          {/* 도트는 실 미읽음 수가 있을 때만 — 무조건 점은 가짜 알림 신호다 */}
          {unread > 0 && <View style={styles.bellDot} />}
          <Icon name="Bell" glyph="◔" size={20} color={paper.ink} />
        </Pressable>
      </View>

      {/* [2026-08-10] screen gutter 14 → layout.gutter (15) — vertical paddings unchanged */}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 12, paddingBottom: 28 }}>

        {/* ————— ① BIB STRAP — 레이스 빕이 한 줄 스트랩으로 접혔다 (Ⓑ①). 빕의 대형 주간 숫자·
             TOTAL/TIER/DISTANCE 스탯 블록·핀·이너 프레임은 은퇴 — 티어는 여기 한 번만.
             [v4] 온라인 토글도 여기서 나갔다 (아래 자기 행) — 스트랩에 남는 것은 **정체성뿐**:
             이름(디스플레이 서체, 화면당 1회) + 티어. 케이지가 넉넉해져 긴 이름의 ellipsize 여유가 늘었다
             (구 산식은 토글 열 ≈119px를 빼고 텍스트 몫 145였다; 이제 콘텐츠 264 전부가 텍스트 몫). */}
        <Row style={styles.strap}>
          <Text style={{ flex: 1, minWidth: 0 }} numberOfLines={1}>
            <Text style={[styles.strapName, df]}>{name ?? '러너'}</Text>
            <Text style={styles.strapNameEm}> 러너</Text>
            <Text style={styles.strapTier}>  {tierLabel}</Text>
          </Text>
        </Row>

        {/* ————— ② 온라인 토글 — [v4 R1a/R1b] 빕 스트랩 안의 44×25 스위치에서 캔버스 위 56×32 잉크
             스위치로 나왔다. 두 가지가 바뀐다.
             ① 색: ON이 코랄이었다. 온라인은 **상태**지 행동이 아니고, 상태에 클라이맥스 색을 칠하면
                화면이 "켜라"고 재촉한다 — 그리고 그 코랄은 바로 아래 수락 문과 예산을 두고 싸웠다.
                ON = 잉크, OFF = 인셋. (랩의 법 그대로: "토글 ON = 잉크".)
             ② 자리: 잉크 스트랩 위에서는 잉크 스위치가 보이지 않는다. 스트랩은 정체성만 지고
                (이름 = 화면당 1회 디스플레이 서체), 스위치는 자기 행을 갖는다 — 한 개의 명확한 컨트롤.
             상태·핸들러(rs.online/toggleOnline)는 그대로다. 서브 문구는 오프라인일 때 **무엇이 멈추고
             무엇이 안 멈추는지**를 말한다: 확정된 러닝은 오프라인과 무관하게 남는다. 랩이 여기 얹은
             "홈 베이스 반경 3km"는 뺐다 — 홈 베이스 좌표 컬럼이 없고 MyRunnerStatus에 반경도 없다.
             🔴 [honesty 2026-08-19 · runner review P1] 세 번째 상태. `rs`의 시드는 {online:false}이고
             reloadStatus의 catch는 그 시드를 지우지 않는다 — 즉 로딩 중과 실패 후에 이 행이 17pt
             '오프라인' + "새 요청이 멈춰 있어요"를 **네트워크 오류에서 지어내** 인쇄하고 있었다.
             fetchMyRunnerStatus가 굳이 throw하는 이유가 그것이고("실패한 읽기가 '오프라인, 0회'로
             해석되면 안 된다"), 이 파일의 다른 다섯 자리는 이미 rsLoaded/rsErr로 게이트한다.
             모르는 동안에는 라벨도 서브 문장도 주장하지 않고, 스위치 자체를 그리지 않는다 —
             비활성 스위치는 여전히 '지금 상태는 OFF'라고 말하기 때문이다. */}
        {!rsLoaded || rsErr ? (
          <View style={styles.tog}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={[styles.togLbl, { color: rsErr ? paper.critical : lilac.dim }]}>
                {rsErr ? '상태를 불러오지 못했어요' : '상태 확인 중'}
              </Text>
            </View>
            {rsErr && (
              <Pressable onPress={reloadStatus} hitSlop={8} style={styles.togRetry} accessibilityRole="button" accessibilityLabel="온라인 상태 다시 불러오기">
                <Text style={styles.togRetryTxt}>다시 시도</Text>
              </Pressable>
            )}
          </View>
        ) : (
          <Pressable
            onPress={toggleOnline}
            accessibilityRole="switch"
            accessibilityState={{ checked: rs.online }}
            accessibilityLabel={rs.online ? '온라인 — 끄기' : '오프라인 — 켜기'}
            style={styles.tog}
          >
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={[styles.togLbl, { color: rs.online ? lilac.head : lilac.dim }]}>
                {rs.online ? '온라인' : '오프라인'}
              </Text>
              {/* [A④ 2026-08-24] 두 문장이 바뀐다. 데이터·핸들러·낙관 되돌림·세 번째 상태는 한 글자도
                  건드리지 않는다 — 이 토글이 **실제로 하는 일**만 말하게 한다.
                  꺼짐이 하던 약속: 「새 요청이 멈춰 있어요」. 오픈 풀은 online을 읽지 않는다 —
                  0056 marketplace_open_requests의 술어는 status='matching' · runner_id is null ·
                  club_session_id is null · is_active_runner()가 전부이고, 그 안에 online은 없다.
                  online을 실제로 읽는 곳은 셋: fetchCertifiedRunners(보호자 러너 목록) ·
                  0054 runners_available_for(`r.online = true`, 지명 화면) · 0015/0003 지금-가능 표면.
                  즉 **인증된 러너가 오프라인이어도 열린 요청은 그대로 온다**. 이 파일 머리(:55-56)가
                  이미 이웃한 실측("지명 요청도 오프라인이면 오지 않아요 — measured false")을 적어
                  뒀는데 토글만 교정을 못 받았다. */}
              <Text style={styles.togSub}>
                {rs.online
                  ? '보호자의 러너 목록과 추천에 보여요'
                  : '보호자의 러너 목록·추천에서 빠져요 · 열린 요청과 확정된 러닝은 그대로'}
              </Text>
            </View>
            <View style={[styles.swTrack, rs.online ? styles.swTrackOn : styles.swTrackOff]}>
              <View style={styles.swKnob} />
            </View>
          </Pressable>
        )}

        {/* [A③] 오늘 — 같은 행 문법, 같은 Oswald 숫자, 이번 주 바로 위. 없으면 없는 대로
            (건수 0을 인쇄하지 않는다 — 오늘 일이 없는 것과 아직 못 불러온 것은 다른 사실이다). */}
        {todayJobs.length > 0 && (
          <Row style={styles.week}>
            <Text style={styles.weekK}>오늘</Text>
            <Text style={styles.weekV}>
              <Text style={[styles.weekNum, nf]}>{todayJobs.length}</Text>건
              {nextToday ? (
                <>
                  {` · 다음${nextTodayMer ? ` ${nextTodayMer}` : ''} `}
                  <Text style={[styles.weekNum, nf]}>{nextToday.wt}</Text>
                </>
              ) : null}
            </Text>
          </Row>
        )}

        {/* ————— ③ 이번 주 — [v4] 장부 히어로가 한 줄이 됐다. 같은 fetchRunnerWeekStats, 같은 세 값,
             같은 '—' 가드. 히어로가 하던 말("내가 얼마 벌었나")은 이 줄이 그대로 하고, 히어로가 하던
             **주장**("이 화면의 주인공은 돈이다")만 사라진다 — 러너 홈의 주인공은 지금 할 일이다.
             '정산 예정'인 이유: fetchRunnerWeekStats는 ledger_items를 직접 읽으므로 금액 자체는 **실값**
             (base+distance+addon+tip+remaining_guarantee − platform_fee, api.ts:2299)이다. 예정인 것은
             금액이 아니라 **지급**이다 — 러너에게 돈을 실제로 보내는 코드 경로가 아직 없다 (수익 화면의
             '지급 일정 미정'과 같은 사실). 그래서 '확보'도 '실수령 완료'도 아니고 '정산 예정'이다. ————— */}
        <Row style={styles.week}>
          <Text style={styles.weekK}>이번 주</Text>
          <Text style={styles.weekV}>
            {/* Two different unknowns share the same '—': the whole fetch failed (stats null), or
                it succeeded and only the runs lookup failed (runs/km null while net is real). The
                second used to render a fabricated 0km beside a real count — see RunnerWeekStats. */}
            <Text style={[styles.weekNum, nf]}>{stats?.runs == null ? '—' : String(stats.runs)}</Text>회 ·{' '}
            <Text style={[styles.weekNum, nf]}>{stats?.km == null ? '—' : String(stats.km)}</Text>km · 정산 예정{' '}
            <Text style={[styles.weekNum, nf]}>{stats === null ? '—' : stats.net.toLocaleString()}</Text>원
          </Text>
        </Row>


        {/* ————— 진행 중 — [v4 R1a] 카드에서 **티켓 오브젝트**로. 랩의 법: 러너가 실제로 들고
             가는 것(오늘의 확정 러닝, 수락/거절할 요청)만 박스를 받는다. 그래서 이 카드와 아래 요청
             티켓이 같은 문법(잉크 1.5px + 퍼포레이션)을 쓰고, 나머지 섹션은 줄로 산다.
             🔴 코랄 면(nowBar) 은퇴 — 화면의 코랄 하나는 수락 문이 가져간다. 액션은 잉크 한 줄이고,
             카드 전체가 여전히 하나의 탭 타깃이라 "가리키는 자리 = 눌리는 자리"는 유지된다.
             파동 링/코랄 좌측 엣지도 함께 내렸다: 상태는 STAGE 라벨이 말로 하고 있었고, 링은 같은
             사실을 색으로 한 번 더 말하는 장식이었다 (LIVE일 때만 STAGE가 코랄 라벨을 든다).
             '예상 수익' 줄도 뺐다 — 돈은 이 화면에서 한 줄(이번 주)이고, 이 잡의 금액은 바로 아래
             '오늘의 루트'가 정차역마다 인쇄한다 (한 사실은 한 화면에 한 번). ————— */}
        {current && (() => {
          const { wd, wt } = parseWhen(current.when);
          const st = STAGE[current.rawStatus];
          const rel = relWhen(current.scheduledAt);
          return (
            <>
              <SectionHead title="진행 중" />
              {/* [T5] 지각 알림. 러너 쪽 ④/⑥. actions 없음 — 이 티켓 자체가 이미 문이고,
                  코랄은 liveOwnsCoral 이 소유한다(① 확정 설계). 사실 한 덩어리만 얹는다. */}
              <LateNotice
                late={lateness({ scheduledAt: current.scheduledAt, rawStatus: current.rawStatus,
                                 arrivedAt: current.arrivedAt ?? null, km: current.km,
                                 startedAt: current.startedAt ?? null,
                                 // [F7] 커스터디는 status 만으로 판정할 수 없다 (lateness.ts 참조)
                                 ownerHandoffAt: current.ownerHandoffAt ?? null,
                                 runnerHandoffAt: current.runnerHandoffAt ?? null })}
                side="runner"
                dogName={current.dogName}
              />
              {/* [0117 stage 2] 체크인 답 표면 — 계획 §13/§15 T5 의 러너 쪽 자리. 지각 알림이 사실을
                  말한 바로 아래에서 답을 받는다.
                  · 러너의 네 입구는 meetup 으로 모이지만 meetup 은 동결 화면이라(스테이지 머신·폴링·
                    confirmHandoff) 답 표면이 거기 붙지 못한다 — 홈이 러너 쪽 유일한 마운트다.
                  · 코랄 0: 이 화면의 코랄은 수락 문(liveOwnsCoral)이 갖는다.
                  · 서버가 체크인을 열지 않았으면 아무것도 그리지 않는다. */}
              <CheckinAnswer
                key={current.bookingId}
                bookingId={current.bookingId}
                side="runner"
                rawStatus={current.rawStatus}
                onAnswered={loadJobs}
              />
              <Pressable onPress={() => openJob(current)} style={({ pressed }) => [styles.ticket, pressed && styles.pressed96]}>
                <View style={styles.tMain}>
                  <View style={{ paddingHorizontal: 13, paddingTop: 12, paddingBottom: 12 }}>
                    <Row style={{ justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
                      {/* A — the actionable datum leads. `rel` is null only when there is no
                          scheduled_at, and then the clock keeps the slot rather than guessing. */}
                      <Text style={[styles.tBig, nf, rel?.late ? { color: paper.critical } : null]}>
                        {rel ? rel.text : wt}
                      </Text>
                      <Text style={[styles.objStage, { color: rel?.late ? paper.critical : st?.color ?? CORAL_INK }]}>
                        {st?.label ?? current.rawStatus}
                      </Text>
                    </Row>
                    {/* The clock demotes but does not disappear — a runner still needs the actual
                        appointment to say it out loud to an owner. */}
                    <Text style={styles.objClock}>{rel ? `${wt}${wd ? ` · ${wd}` : ''}` : wd}</Text>

                    {/* B — the face. Avatar falls back to a monogram when photo_url is null, so the
                        row never becomes an empty frame. */}
                    <Row style={{ gap: 10, marginTop: 9, alignItems: 'center' }}>
                      <Avatar url={current.dogPhotoUrl} char={current.dogName[0] ?? '견'} bg={lilac.head} size={42} />
                      <View style={{ flex: 1 }}>
                        <Text style={[styles.objMain, { marginTop: 0 }]}>
                          <Text style={{ fontWeight: '800' }}>{current.dogName}</Text> · <Text style={[styles.objNum, nf]}>{current.km}</Text>km
                        </Text>
                        {/* D — door-level address. The road name is what a map needs; 동·호수 is what
                            the RUNNER needs, and it used to be dropped entirely by a single
                            numberOfLines={1} line that also spent its width on the label. */}
                        {jobAddr && (
                          <>
                            <Text style={styles.objAddr} numberOfLines={1}>{jobAddr.addr}</Text>
                            {jobAddr.detail ? <Text style={styles.objDetail} numberOfLines={1}>{jobAddr.detail}</Text> : null}
                          </>
                        )}
                      </View>
                    </Row>

                    {/* C — what this job pays. Already in RunnerJob and never rendered: the runner
                        could see earnings for finished runs but not for the one they are walking to.
                        Quiet green, never coral — the decision is already made, so this is
                        confirmation and must not compete with the action for weight. */}
                    <Row style={{ justifyContent: 'space-between', alignItems: 'baseline', marginTop: 9 }}>
                      <Text style={[styles.objPay, nf]}>+{current.payout.toLocaleString()}원</Text>
                      <Text style={styles.objQuiet}>완주 기준</Text>
                    </Row>
                  </View>
                </View>

                <View style={styles.perfWrap}>
                  <View style={styles.perf} />
                  <View style={[styles.perfNotch, { left: -8, borderLeftColor: 'transparent' }]} />
                  <View style={[styles.perfNotch, { right: -8, borderRightColor: 'transparent' }]} />
                </View>

                {/* The stub keeps the ticket's shape but no longer carries the action — the coral
                    button below says the same sentence, and one screen must not say it twice. */}
                <View style={styles.tStub}>
                  <Text style={styles.objStubTxt}>{current.dogName}와 함께</Text>
                </View>
              </Pressable>

              {/* ① — THE COLOUR RULE, FLIPPED. The screen's single coral used to belong to the
                  수락 door, which means an EMPTY inbox rendered no coral at all: in that state the
                  runner's real next action (인계 화면으로) was a grey stub link at the bottom of a
                  card, while the heaviest thing on screen was a black identity bar that does
                  nothing. A job already in flight — a dog already committed — outranks a request
                  nobody has accepted. So it takes the coral, and the 수락 door drops to a ghost
                  (see `liveOwnsCoral`, extended below to every in-flight stage rather than `active`
                  alone). Label is STAGE[rawStatus].action, so it stays the stage's own next step. */}
              <Pressable
                onPress={() => openJob(current)}
                style={({ pressed }) => [styles.jobCta, pressed && styles.pressed96]}
                accessibilityRole="button"
                accessibilityLabel={st?.action ?? '이어서 진행'}
              >
                <Text style={styles.jobCtaT}>{st?.action ?? '이어서 진행 ›'}</Text>
                <Text style={styles.jobCtaS}>{stageSub(current.rawStatus, current.dogName)}</Text>
              </Pressable>

              {/* Chat sits directly beneath, INK OUTLINE not coral (Sean: "should have a chat option
                  right underneath"). Two corals in one frame is exactly how the half-second glance
                  breaks — chat earns a full row, not equal weight with the thing the dog is
                  waiting on. */}
              <Pressable
                onPress={() => router.push({ pathname: '/chat', params: { bid: current.bookingId } })}
                style={({ pressed }) => [styles.jobChat, pressed && styles.pressed96]}
                accessibilityRole="button"
                accessibilityLabel="보호자와 채팅"
              >
                <Text style={styles.jobChatT}>채팅</Text>
                <Text style={styles.jobChatS}>늦으면 미리 알려주세요</Text>
              </Pressable>
            </>
          );
        })()}

        {/* ————— QUEUE: 오늘 맨 앞 = 보딩패스 티켓 · 나머지 = 스텁 행. 수락/거절 = 소스 요청함 핸들러 ————— */}
        {/* [honesty 2026-08-19 · runner review #4] 'N건'은 로드가 성공한 뒤에만. 종전엔 로딩 중과
            인박스 실패 후에 '요청함 · 0건 ›'을 인쇄했는데, 같은 프레임 아래 박스는 '요청을 불러오지
            못했어요'라고 말하고 있었다 (한 화면이 스스로와 모순). 문 자체는 그대로 살아 있다. */}
        <SectionHead
          title="요청 대기열"
          link={inboxLoaded && !inboxErr ? `요청함 · ${inbox.length}건 ›` : '요청함 ›'}
          onPress={() => router.push('/runner/requests')}
        />

        {inbox.length > 0 ? (
          <>
            {/* 맨 앞 요청 = 티켓 오브젝트 (inbox[0]) — 진행 중 카드와 같은 문법.
                [v4 R1a] 세 가지가 바뀐다.
                🔴 ① '지명 요청 픽업'은 **오픈 풀 요청 위에서도** 인쇄되고 있었다 (조건 없는 문자열) —
                   아무도 지명하지 않은 요청을 "당신을 지명했다"고 말하던 줄이다. ★ 태그가 이미
                   directed일 때만 뜨므로 같은 사실이 두 번 필요하지도 않았다. 실필드로 갈아끼운다:
                   견종·체중·페이스는 OpenRequest에 실제로 있는 값이다 (api.ts:740-758).
                ② 조용한 줄에 '실거리로 확정' — 문에 찍힌 금액은 추정치다 (requests.tsx:76과 같은 문장).
                   ⟳ N번째는 repeatPrior(완료 동반 러닝 수)+1, 있을 때만.
                ③ 코랄 도트 은퇴 · 시각 31 → 24pt: 화면 위쪽 진행 중 티켓이 31pt 데이텀을 갖고,
                   요청은 그 다음 오브젝트다 (같은 크기면 위계가 없다).
                금액은 여전히 수락 문이 **한 번만** 인쇄한다. */}
            <View style={styles.ticket}>
              <View style={styles.tMain}>
                <View style={{ paddingHorizontal: 13, paddingTop: 12, paddingBottom: 12 }}>
                  <Row style={{ justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                    {/* [A② 2026-08-25] 행동을 바꾸는 값이 큰 슬롯을 갖는다. 진행 중 티켓의 질문이
                        「나 늦었나」라 relWhen이 시계를 밀어낸 것과 같은 이유로, 요청의 질문은
                        「얼마나 남았나」다 — 그리고 서버가 그 질문에 정확히 답한다 (0080 ⓐ).
                        남은 시간을 모를 때(시각 없음·하루 넘게 남음·이미 지남)는 **시계가 자리를
                        지킨다**: 추측하지 않고, 있던 사실을 지우지도 않는다. */}
                    <Text style={[styles.tMid, nf]} numberOfLines={1}>
                      {frontAhead ? frontAhead.text : inbox[0].when}
                    </Text>
                    {/* [§3b status chip] 16/800 · 보더 없는 틴트 필 · 데이텀(시각)과 같은 행 */}
                    {inbox[0].directed && (
                      <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>
                    )}
                  </Row>
                  {/* [A② 2026-08-24] 마감. 서버의 만료 규칙은 정책 숫자가 아니라 **이 러닝의 시작
                      시각 그 자체**다: expire_unmatched_bookings(0080 ⓐ, 0017/0037/0060 계승)가
                      `status in ('matching','runner_pending') and scheduled_at < now()`인 예약을
                      expired로 넘긴다. 요청함 화면의 푸터가 이미 약속하던 문장이고, 여기서는
                      새 컬럼도 새 쿼리도 없이 참이다.
                      [2026-08-25] 카운트다운이 위로 올라가면 시계는 여기로 내려온다 — 사라지지는
                      않는다. 러너는 보호자에게 시각을 **말로** 해야 하고, 「5시간 뒤」로는 못 한다
                      (진행 중 티켓이 같은 이유로 시계를 남기는 것과 같은 결정). */}
                  <Text style={styles.objClock}>
                    {frontAhead ? `${inbox[0].when} · ` : ''}시작 시각이 지나면 자동 만료돼요
                  </Text>
                  {/* [A② 2026-08-24] 얼굴. `photoUrl`은 요청마다 이미 실려 오고(api.ts OpenRequest)
                      요청함 화면은 그리는데, 홈 티켓만 개 이름을 부르면서 보여주지 않았다.
                      Avatar는 photo_url이 null이면 모노그램으로 떨어지므로 빈 액자가 되지 않는다.
                      42가 아니라 40인 것은 랩의 선택 그대로다 — 진행 중 티켓의 개(내가 이미 데리고
                      가는 개)가 아직 아무도 수락하지 않은 요청보다 한 단 위다. */}
                  <Row style={{ gap: 10, marginTop: 9, alignItems: 'center' }}>
                    <Avatar url={inbox[0].photoUrl} char={inbox[0].dogName[0] ?? '견'} bg={lilac.head} size={40} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Text style={[styles.objMain, { marginTop: 0 }]}>
                        <Text style={{ fontWeight: '800' }}>{inbox[0].dogName}</Text>
                        {inbox[0].breed ? ` · ${inbox[0].breed}` : ''}
                        {inbox[0].weightKg > 0 ? ` ${inbox[0].weightKg}kg` : ''}
                        {' · '}<Text style={[styles.objNum, nf]}>{inbox[0].km}</Text>km
                        {/* [0114 residual · party-membership-status-filter-contract §C.6] 지명(directed =
                            status 'runner_pending', api.ts fetchRunnerInbox의 directed 레그) 카드에는
                            `bookings.pace_label`을 인쇄하지 않는다 — 수락 전 러너에게 닿는 보호자 작성
                            자유 텍스트의 무검증 통과 경로다. 오픈 풀(matching) 카드는 그대로.
                            견종·체중·이름은 남는다: 러너가 실제로 결정에 쓰는 정보다. */}
                        {!inbox[0].directed && inbox[0].paceLabel ? ` · ${inbox[0].paceLabel}` : ''}
                      </Text>
                      {/* [0122 · Sean Q6 2026-08-25, verbatim: 「…also include the 동.」] 출발 동이
                          조용한 줄의 맨 앞에 선다 — 이 줄에서 유일하게 **어디로 가야 하는가**를
                          말하는 값이고, 나머지(정산 어휘·단골·코스명)는 전부 그 다음 질문이다.
                          값이 없으면 토큰이 통째로 빠진다: 자리표시자 없음 (api.ts pickupDong).
                          [0123 · Sean Q6 ruling B 2026-08-25] 거리 밴드가 동 바로 뒤에 붙는다 —
                          requests.tsx의 카드와 **같은 라벨**을 쓴다(「기준 위치에서」): 위 줄의
                          {km}은 러닝 거리이고 이건 출발지까지의 거리라, 라벨 없이는 한 줄에 뜻이
                          다른 km가 둘이 된다. 「내 위치」가 아닌 이유는 이게 기기에서 읽은 값이
                          아니라 러너가 설정에서 저장한 ~1km 격자 기준점이기 때문이다.
                          여기엔 「설정하러 가기」 문을 두지 않는다 — 홈의 티켓은 한 장짜리 요약이고
                          그 문은 요청함 화면에 한 번만 있다 (문이 두 개면 둘 다 약해진다). */}
                      <Text style={styles.objQuiet}>
                        {inbox[0].pickupDong ? `${inbox[0].pickupDong} 출발 · ` : ''}
                        {inbox[0].distanceBand ? `기준 위치에서 ${inbox[0].distanceBand} · ` : ''}
                        실거리로 확정
                        {inbox[0].repeatPrior != null && inbox[0].repeatPrior > 0 ? ` · ⟳ ${inbox[0].repeatPrior + 1}번째 함께` : ''}
                        {inbox[0].routeName ? ` · ${inbox[0].routeName}` : ''}
                      </Text>
                    </View>
                  </Row>
                </View>
              </View>

              {/* 퍼포레이션 + 사이드 노치 */}
              <View style={styles.perfWrap}>
                <View style={styles.perf} />
                <View style={[styles.perfNotch, { left: -8, borderLeftColor: 'transparent' }]} />
                <View style={[styles.perfNotch, { right: -8, borderRightColor: 'transparent' }]} />
              </View>

              <View style={styles.tStub}>
                <Row style={{ gap: 8 }}>
                  {/* [실동작] 문이 곧 행동 — 수락은 여기서 끝난다. 상세(사진·메모)가 필요하면 콰이엇 문(오픈 요청)
                      [§3b] busy = 라벨 스왑만 (opacity 트릭 은퇴) · pressed = scale 0.96 · 수락 라벨 17/800
                      [v4] liveOwnsCoral: 러닝이 LIVE인 동안 '지금 내 차례'는 러닝 화면이지 새 요청이 아니다 —
                      그때만 이 문이 잉크 아웃라인 고스트로 내려간다 (화면당 코랄 1개 법). 동작은 동일. */}
                  <Pressable onPress={acceptFront} disabled={busyReq} style={({ pressed }) => [styles.door, liveOwnsCoral ? styles.doorGhost : styles.doorCoral, pressed && styles.pressed96]}>
                    <Text style={[styles.doorName, { color: liveOwnsCoral ? lilac.head : '#fff', fontSize: 17 }]}>{busyReq ? '전송 중...' : '수락 ›'}</Text>
                    {/* [2026-08-10 filler cull] ' · 바로 확정돼요' dropped — the confirm Alert states the consequence */}
                    <Text style={[styles.doorSub, { color: liveOwnsCoral ? lilac.dim : '#fff' }]}>
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
              {inbox.slice(1).map((rq, i) => {
                // [A② 2026-08-25] 스텁도 같은 마감을 안다 — 앞 티켓만 남은 시간을 알고 나머지가
                // 시각만 말하면, 러너는 어느 요청이 먼저 사라지는지 보려고 요청함까지 가야 한다.
                // 앞 티켓과 **같은 함수·같은 클램프**이고, 지각 어휘는 여기서도 그리지 않는다.
                const rel = relWhen(rq.scheduledAt);
                const ahead = rel && !rel.late ? rel : null;
                return (
                <View key={i} style={styles.stub}>
                  <View style={{ flex: 1, minWidth: 0, paddingHorizontal: 11, paddingTop: 12, paddingBottom: 10 }}>
                    <Row style={{ alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                      <Text style={styles.stubNm}>{rq.dogName}</Text>
                      <Text style={[styles.stubKm, nf]}>{rq.km}<Text style={styles.stubKmUnit}>KM</Text></Text>
                      {rq.directed && <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>}
                    </Row>
                    <Row style={{ alignItems: 'center', gap: 5, marginTop: 5, flexWrap: 'wrap' }}>
                      <Text style={styles.stubWhen}>{rq.when}</Text>
                      {ahead && <Text style={styles.stubRel}>· {ahead.text}</Text>}
                    </Row>
                  </View>
                  <View style={styles.stubAct}>
                    <View style={[styles.stubNotch, { top: -6 }]} />
                    <View style={[styles.stubNotch, { bottom: -6 }]} />
                    <View style={{ alignItems: 'center' }}>
                      <Text style={[styles.stubFare, nf]}>{rq.payout.toLocaleString()}</Text>
                      {/* [honesty 2026-08-19] '실수령'은 확정 금액을 뜻한다 — 이 값은 추정치다
                          (서버가 실거리·수수료율로 확정). 앞 티켓의 조용한 줄과 같은 어휘로 맞춘다. */}
                      <Text style={styles.stubFareCap}>예상</Text>
                    </View>
                    <Pressable onPress={() => router.push('/runner/requests')} style={({ pressed }) => [styles.stubView, pressed && styles.pressed96]}>
                      <Text style={styles.stubViewTxt}>보기 ›</Text>
                    </Pressable>
                  </View>
                </View>
                );
              })}
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
            ) : inboxErr ? (
              // [honesty 2026-08-11] a failed inbox fetch is not a quiet day — say so, offer retry
              <Pressable onPress={loadInbox} accessibilityRole="button" accessibilityLabel="요청 인박스 다시 불러오기">
                <Text style={styles.emptyInboxTxt}>요청을 불러오지 못했어요</Text>
                <Text style={styles.emptyInboxLink}>다시 시도 ›</Text>
              </Pressable>
            ) : !inboxLoaded ? (
              <Text style={styles.emptyInboxTxt}>요청을 확인하는 중이에요…</Text>
            ) : (
              // [A① 2026-08-24] 조용한 날이 스스로를 설명한다. 종전 한 줄은 두 갈래였는데 오프라인
              // 갈래(「오프라인 상태 — 켜야 요청을 받아요」)가 A④와 **같은 거짓말**이었다: 오픈 풀은
              // online을 읽지 않으므로 켠다고 열린 요청이 오는 게 아니다. 이 화면은 왜 조용한지에
              // 답할 두 값을 이미 들고 있다 (rs · avail, 포커스마다 다시 읽는다).
              // ⚠ 로드되지 않은 행은 그리지 않는다: avail이 null(로딩·실패)이면 러닝 가능 시간 행이
              // 통째로 빠진다 — 모르는 값을 '설정 없음'으로 위장하지 않는다. 이 갈래 자체가 이미
              // rsLoaded && !rsErr && !preCert && inboxLoaded && !inboxErr 안이므로 온라인 행은 실값이다.
              <>
                <Text style={styles.emptyInboxHead}>지금은 새 요청이 없어요</Text>
                <View style={styles.emptySum}>
                  <Row style={styles.sumRow}>
                    <Text style={styles.sumLbl}>온라인</Text>
                    <Text style={styles.sumVal}>{rs.online ? '켜짐' : '꺼짐'}</Text>
                  </Row>
                  {avail && (
                    <Row style={[styles.sumRow, styles.sumRowDiv]}>
                      <Text style={styles.sumLbl}>러닝 가능 시간</Text>
                      <Text style={styles.sumVal} numberOfLines={1}>{availSummary(avail)}</Text>
                      <Pressable
                        onPress={() => router.push('/runner/availability')}
                        hitSlop={8}
                        style={styles.sumAct}
                        accessibilityRole="button"
                        accessibilityLabel="러닝 가능 시간 조정"
                      >
                        <Text style={styles.sumActTxt}>시간 조정 ›</Text>
                      </Pressable>
                    </Row>
                  )}
                </View>
                {/* 실측된 문장이지 주장이 아니다 — 오픈 풀 = marketplace_open_requests(online 술어 없음),
                    지명 목록 = runners_available_for/fetchCertifiedRunners(`r.online = true`). */}
                <Text style={styles.emptyInboxNote}>
                  열린 요청은 온라인과 무관하게 도착해요 — 지명은 온라인일 때만 새로 들어와요
                </Text>
              </>
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
                  // [honesty 2026-08-19 · runner review #2/#3] 두 줄이 실필드로 바뀐다.
                  // ① '지금'은 kind === 'on'에서 하드코딩돼 있었는데, `current`는 진행 중 잡이 없으면
                  //    **다음 confirmed 잡**으로 폴백한다 — 사흘 뒤 예약에 '지금'이 찍혔다.
                  //    실제로 시작된 단계(rawStatus ≠ confirmed)일 때만 '지금'이다.
                  // ② 아래 줄은 모든 정차역에 '지명 요청 · 예정'을, 진행 중 정차역엔 '픽업 대기'를
                  //    하드코딩했다. RunnerJob에는 `directed` 필드가 아예 없어(api.ts:1154-1163)
                  //    지명 주장을 뒷받침할 값이 없고, '픽업 대기'는 러닝 중(active)에도 그대로
                  //    찍혀 같은 화면의 'STAGE[rawStatus] = 러닝 중 · LIVE'와 정면으로 부딪혔다.
                  //    진행 중 정차역은 STAGE 라벨(서버 상태 파생)을 쓰고, 예정 정차역은
                  //    아무 줄도 그리지 않는다 (실필드를 붙이거나 요소를 생략한다 — 지어내지 않는다).
                  // ③ [2026-08-19] '지금'은 시작된 단계**이면서 오늘 것**일 때만이다. 8월 4일에
                  //    시작돼 끝나지 않은 잡(rawStatus='active')이 8월 19일 홈에서 '지금'으로
                  //    찍혔다 (실측). 진행 중이라는 사실은 바로 옆 stageLabel('러닝 중 · LIVE')이
                  //    이미 말하므로, 이 칸은 **언제**를 말한다 — 오늘이 아니면 그 날짜를.
                  const started = on && st.job.rawStatus !== 'confirmed' && isTodayKst(st.job.scheduledAt);
                  const stageLabel = on ? STAGE[st.job.rawStatus]?.label ?? null : null;
                  return (
                    <Pressable
                      key={st.job.bookingId}
                      onPress={() => openJob(st.job)}
                      style={[styles.stop, i > 0 && { borderTopWidth: 1, borderTopColor: '#EEEEEE' }]}
                    >
                      {/* [v4] '지금' 표식은 잉크 — 코랄은 화면당 하나이고 그 하나는 수락 문이다.
                          이 점이 말하려던 사실은 바로 옆 'stopTmSub'가 이미 '지금'이라고 글자로 말한다. */}
                      <View style={[styles.stopPt, on && styles.stopPtOn]}>
                        {on && <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.head }} />}
                      </View>
                      {/* [2026-08-10] time col 52 → 60: stopTm went 14 → 16pt Oswald — 'HH:MM' ≈ 5 glyphs
                          × ~9px + tracking ≈ 48px, 60 leaves device-font-scale headroom (52 fit 14pt ≈ 42px) */}
                      <View style={{ width: 60 }}>
                        <Text style={[styles.stopTm, nf]}>{wt}</Text>
                        <Text style={styles.stopTmSub}>{started ? '지금' : wd || '예정'}</Text>
                      </View>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Text style={styles.stopInfoB}>{st.job.dogName} · {st.job.km}km</Text>
                        {stageLabel ? <Text style={styles.stopInfoS}>{stageLabel}</Text> : null}
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
             클럽+호스트 로직은 컴포넌트가 보유.
             [중복 타이틀 수리 2026-08-11 · Sean "러너 쪽에 하이클럽 타이틀이 중복"] 여기 있던
             <SectionHead title="하이클럽" />를 삭제한다. ClubModule(clubcard.tsx:401-419)이 이미
             자기 §3b 섹션 헤더를 그린다 — 코랄 1px 룰 + '하이클럽' 20/800 잉크로, 이 SectionHead와
             **글자·크기·굵기·색이 전부 같다**. 화면에는 같은 제목이 10px 간격으로 두 번 찍혀 있었다.
             보호자 홈은 처음부터 <ClubHomeCard /> 하나만 넣어 옳았다(owner/home.tsx:1181) — 러너 홈만
             모듈이 헤더를 갖기 전의 래퍼를 들고 있었다. 헤더의 주인은 모듈이다. ————— */}
        <RunnerClubCard />

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
              return <Text style={{ fontSize: 15, lineHeight: 20, color: lilac.dim }}>등급을 불러오는 중이에요…</Text>;
            }
            if (rsErr) {
              return <Text style={{ fontSize: 15, lineHeight: 20, color: lilac.dim }}>등급을 불러오지 못했어요</Text>;
            }
            if (preCert) {
              return <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head }}>인증 러너가 되면 등급이 시작돼요</Text>;
            }
            // v1 승급 기준: 베테랑 30회, 마스터 100회 — 심사 도입 전 잠정.
            // 수수료는 일괄 33%(0059) — 티어 연동 요율 없음. 요율 인하 약속 금지(정산은 33%를 뗀다).
            const t = rs.tier === 'veteran'
              ? { next: '마스터', at: 100 }
              : rs.tier === 'master'
                ? null
                : { next: '베테랑', at: 30 };
            if (!t) {
              return <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head }}>★ 마스터 러너</Text>;
            }
            const left = Math.max(t.at - rs.totalRuns, 0);
            const pct = Math.min(rs.totalRuns / t.at, 1);
            return (
              <>
                <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head }}>
                    {t.next}까지 러닝 <Text style={[{ fontSize: 15, color: lilac.head }, nf]}>{left}</Text>회
                  </Text>
                  {/* [2026-08-24 Sean] "don't show them the 수수료… keep the margin a secret."
                      The word itself goes, not just the rate: 「수수료 제외」 names the deduction and
                      hands back the arithmetic by subtraction. 「실수령 기준」 states the same basis
                      with no reference to what was taken. (The earlier note here said the 수익
                      screen's breakdown row speaks the fee amount — that row is now gone too, same
                      ruling, so this caption was the last place the word survived on a runner
                      surface besides apply.tsx, fixed in the same commit.) */}
                  <Text style={styles.fee}>실수령 기준</Text>
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
                <Text style={{ fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 8 }}>
                  승급 기준은 파일럿 중 조정될 수 있어요
                </Text>
              </>
            );
          })()}

          {/* [honesty 2026-08-19 · runner review #6] 트레일 전체가 rsLoaded/rsErr 게이트 밖에 있었다:
              rs의 시드는 totalRuns 0이고 실패해도 지워지지 않으므로, 로드 실패한 러너에게
              '누적 0회' + 빈 체크포인트 다섯 개 + "첫 러닝을 완료하면 트레일이 시작돼요"가
              찍혔다 — 100회 뛴 러너에게 0회라고 말하는 화면. 위 사다리는 이미 로딩/실패를
              자기 문장으로 말하므로, 아래는 모르는 동안 아무것도 그리지 않는다 (구분선 포함). */}
          {rsLoaded && !rsErr && (<>
          <View style={{ height: 1, backgroundColor: '#EEEEEE', marginTop: 11, marginBottom: 10 }} />

          {/* 보급 드랍 트레일 — 지그재그 체크포인트 (i<cycle5 지남=accent, i===cycle5 다음=accent 링, 끝=보급 상자) */}
          <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head }}>
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
          <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head, marginTop: 4 }}>
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
          </>)}
        </Pressable>

        {/* ————— 러닝 가능 시간 — 요일 탭 (온라인 토글은 스트랩 위) ————— */}
        <SectionHead title="러닝 가능 시간" link="시간 조정 ›" onPress={() => router.push('/runner/availability')} />
        {/* [Ⓑ② 2026-08-12 · Sean 랩 픽] 접기 — 7칸 스트립.
            ⚠ 표시만 바뀐다. avail · toggleDay · DAY_ORDER/DAY_NAME/hh · 가용성의 3개 술어는
            전부 그대로다 (DO-NOT-REFACTOR, DESIGN.md §9).
            접힘 = 어느 요일에 뛰는가(7칸) · 펼침 = 몇 시에 뛰는가(기존 칩, 여기서만 토글).
            스트립과 칩은 **동시에 뜨지 않는다** — 둘 다 요일 글자를 인쇄하므로 겹치면 같은 사실이
            한 화면에 두 번이다.
            🔴 랩에서 이 안에 걸어둔 유일한 반대가 타입 플로어였는데(12pt 요일 글자, 한글은 라틴
            키커 예외를 못 탄다 — §3), 실측해보니 걸 필요가 없었다: 320dp에서 카드 콘텐츠 폭은
            320 − 30 거터 − 26 카드 패딩 = 264, 갭 3×6 = 18을 빼면 칸당 ≈ 35px. 15pt 한글 한 글자는
            ≈ 15px이라 여유가 두 배다. 그래서 **15pt로 짓는다** — 플로어를 지키고 칸도 안 키운다.
            (2026-08-25: 작업 플로어가 15로 올라가며 14 → 15. 칸당 여유 35 − 15 = 20px로 그대로다.) */}
        <View style={styles.card}>
          {/* [honesty 2026-08-20 · T3] 로딩과 실패가 같은 문장이었다 (둘 다 '불러오는 중...').
              실패는 자기 문장 + 실제로 다시 부르는 문을 갖는다 — 이 카드의 토글은 저장 버튼 없이
              바로 서버에 쓰기 때문에, 무엇이 저장돼 있는지 모르는 채로는 칩을 아예 그리지 않는다.
              문법은 이 화면의 recFail/togRetry 그대로 (크리티컬 잉크 + 밑줄, ≥44pt 타깃).
              ⚠ 실패 행은 **가진 데이터가 없을 때만**이다 (availability.tsx:131의 `!loaded && loadErr`와
              같은 술어). 이 화면은 포커스마다 다시 부르므로, 한 번 성공해 실값이 있는 상태에서
              새로고침이 실패했다고 러너에게서 그 실값을 뺏으면 안 된다 — 마지막 서버 진실은
              여전히 진실이고, 그 위에서의 토글도 실데이터 위의 쓰기다. */}
          {!avail && availErr ? (
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', gap: 9 }}>
              <Text style={{ flex: 1, fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical }}>
                러닝 가능 시간을 불러오지 못했어요
              </Text>
              <Pressable onPress={loadAvail} hitSlop={8} style={styles.togRetry} accessibilityRole="button" accessibilityLabel="러닝 가능 시간 다시 불러오기">
                <Text style={styles.togRetryTxt}>다시 시도</Text>
              </Pressable>
            </Row>
          ) : !avail ? (
            <Text style={{ fontSize: 15, color: lilac.dim }}>불러오는 중...</Text>
          ) : (
            <>
              <Pressable
                onPress={() => setAvailOpen((v) => !v)}
                accessibilityRole="button"
                accessibilityState={{ expanded: availOpen }}
                accessibilityLabel={`러닝 가능 시간 주 ${availDays}일 — ${availOpen ? '접기' : '펼치기'}`}
                style={{ flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 44 }}
              >
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head }}>
                    주 {availDays}일 가능
                  </Text>
                  {/* 접힘 상태의 정보량이 이 안의 값 — 며칠인지가 아니라 **어느 요일**인지 보인다.
                      요약 스트립이라 토글하지 않는다 (토글은 펼친 칩의 일). */}
                  {!availOpen && (
                    <Row style={{ gap: 3, marginTop: 7 }}>
                      {DAY_ORDER.map((wd) => {
                        const on = !!avail.find((r) => r.weekday === wd);
                        return (
                          <View key={wd} style={[styles.sq, on && styles.sqOn]}>
                            <Text style={[styles.sqTxt, { color: on ? '#FFFFFF' : lilac.dim }]}>{DAY_NAME[wd]}</Text>
                          </View>
                        );
                      })}
                    </Row>
                  )}
                </View>
                {/* 셰브론 — 펼침이면 ⌄, 접힘이면 › (산증 글리프만) */}
                <Text style={{ fontSize: 19, lineHeight: 24, color: lilac.dim }}>{availOpen ? '⌄' : '›'}</Text>
              </Pressable>

              {availOpen && (
                <View style={{ marginTop: 11, paddingTop: 11, borderTopWidth: 1, borderTopColor: '#EEEEEE' }}>
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
                  <Text style={{ fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 9 }}>
                    기본 06–22시 · 보호자 예약 화면에 즉시 반영
                  </Text>
                </View>
              )}
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
                    {/* [honesty 2026-08-19 · runner review #1] '✓ 정산 완료'는 정산 사실이 아니라
                        **표시 어휘**에서 파생돼 있었다: j.status는 STATUS_MAP이 뭉갠 'completed'이고
                        (api.ts:1203), 정산 여부를 아는 필드는 이 화면에 없다 — done.tsx가 쓰는
                        runResult.settled가 그 구분이 존재한다는 증거다. 러닝이 끝난 것은 참이고
                        돈이 정산된 것은 이 데이터로 알 수 없으므로 '완료'만 말한다.
                        위 줄의 중복 '완료'도 함께 접었다 (한 사실은 한 화면에 한 번). */}
                    <Text style={styles.drowB}>{j.dogName} · {j.km}km</Text>
                    <Text style={styles.drowS}>{j.when} · <Text style={{ color: lilac.voltDeep, fontWeight: '700' }}>✓ 완료</Text></Text>
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
              accessibilityLabel="하이 피드에 자랑하기"
            >
              <Text style={styles.feedShareTxt}>완주 기록을 하이 피드에 자랑하기 ›</Text>
            </Pressable>
          </>
        )}

        {/* ————— 내 기록 — [Sean 2026-08-11] "러너 페이지의 내 기록 같은 건 마이가 아니라 홈에 있어야
             한다. 그리고 이걸 왜 보고 있지? 그래서 뭐?"
             세 가지가 겹쳐 있었다. ① 기록 문은 이미 홈에 있었다 — 다만 아래 퀵링크의 '마이 카드 ›'
             칩이라 아무 말도 하지 않았다. ② 마이(my.tsx)에도 '내 러닝 기록' 행이 따로 있어 문이 둘.
             ③ 🔴 두 문 다 목적지를 잘못 부르고 있었다: /cards는 **컬렉션(ANNEX — 도장 + 코스 패치)**
             이지 러닝 기록부가 아니다. 한 화면을 세 이름으로 부르던 것이 "그래서 뭐?"의 실체다.
             수리: 마이의 러너 행 삭제(문 하나) · 퀵링크 칩 삭제 · 여기 실수치를 든 섹션 하나.
             수치는 rs.totalKm — settle_run_tx가 실주행마다 올리는 runners.total_km이고, 이 화면
             어디에도 인쇄되지 않은 유일한 러너 실적이다 (누적 '회수'는 리워드 트레일이 이미 말한다 —
             한 사실은 한 화면에 한 번). 로딩·실패는 0이 아니라 '—' (로딩≠0 법). ————— */}
        {/* [E7 승인 2026-08-12 · Sean] 여권의 **기록면**이 마이에서 여기로 왔다. 어제는 이 자리에
            임시 라이트 카드를 뒀었는데(아티팩트를 임의로 뜯을 수 없어서), 승인이 났으니 진짜 물건을
            옮긴다 — 나이트 라일락 면 · 홀로 엣지 · 상세 기록 보기 문까지 같은 오브젝트다.
            🔴 옮기면서 **죽은 칸 하나를 버렸다**: 러너의 '평균 페이스'는 영원히 '—'였다.
            my.tsx:59가 `fetchMyRunnerStatus()`를 `any`로 캐스팅한 뒤 `r.paceLabel`을 읽는데
            MyRunnerStatus에 그런 필드가 없다 (`{totalRuns, totalKm, online, tier}`) — 즉 값이 온 적이
            없는 칸이다 (시뮬레이터에서도 '—'로 확인). 없는 필드를 홈까지 데려가지 않는다.
            '총 횟수'도 뺐다 — 리워드 트레일이 같은 화면에서 '누적 N회'로 이미 인쇄한다.
            남는 실적은 총 거리 하나, 그리고 그게 이 면의 큰 숫자가 된다.
            목적지는 /cards(컬렉션) — 마이에서는 /runner/home이었는데, 홈에 사는 카드가 홈으로
            가리키면 순환이다. */}
        <SectionHead title="내 기록" link="컬렉션 ›" onPress={() => router.push('/cards')} />
        <Pressable
          onPress={() => router.push('/cards')}
          style={({ pressed }) => [styles.record, pressed && styles.pressed96]}
          accessibilityRole="button"
          accessibilityLabel="컬렉션 열기"
        >
          <View style={styles.recordInner}>
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff' }}>나의 러닝 기록</Text>
              <Row style={{ alignItems: 'center', gap: 5 }}>
                <View style={styles.coralDot} />
                <Text style={[styles.recordKick, nf]}>RECORD / 기록면</Text>
              </Row>
            </Row>
            {/* 로딩·실패는 0이 아니라 '—' (단위도 함께 접어 대시에 매달리지 않게) */}
            <Text style={[styles.recN, nf]}>
              {rsLoaded && !rsErr ? rs.totalKm.toFixed(1) : '—'}
              <Text style={styles.recU}>{rsLoaded && !rsErr ? ' km' : ''}</Text>
            </Text>
            <Text style={styles.recL}>총 거리</Text>
            <View style={styles.recGoWrap}>
              <Text style={styles.recGo}>상세 기록 보기 ›</Text>
            </View>
          </View>
        </Pressable>
        {/* 기록 로드 실패 — '—'가 로딩인지 실패인지 여기서 갈린다 (라우드 페일 + 재시도).
            다크 면 '밖'에 붙여 크리티컬 잉크의 대비를 지킨다 (my.tsx recFail 선례 그대로). */}
        {rsErr && (
          <Row style={styles.recFail}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>러닝 기록을 불러오지 못했어요</Text>
            <Pressable onPress={reloadStatus} hitSlop={8} accessibilityRole="button" accessibilityLabel="러닝 기록 다시 불러오기">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </Row>
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
          {/* [2026-08-11] '마이 카드 ›' 칩 은퇴 — 위 '내 기록' 섹션이 같은 목적지(/cards)로 가는
              문이면서 실수치까지 말한다. 이름 없는 칩과 말하는 섹션이 둘 다 있을 이유가 없다. */}
        </Row>

        {/* [Ⓑ① 2026-08-11] 푸터 은퇴 — 누적·티어·온라인 전부 재인쇄였다 (티어·온라인 = 스트랩,
            누적 = 리워드 트레일 '누적 N회'). 각 사실은 화면에 한 번만. */}
      </ScrollView>
      </TabSwipe>

      <BottomNav />
    </View>
  );
}

const styles = StyleSheet.create({
  // 상단 크롬 — [페이퍼 크롬] 글래스 은퇴: 플레인 화이트 + 코랄 헤어라인 바텀 엣지 (마스트헤드 법)
  top: {
    // [2026-08-11] justifyContent 'flex-end' 은퇴 — 좌측에 브랜드 마크가 왔고 간격은 flex 스페이서가 잡는다.
    // paddingHorizontal 12 → layout.gutter(15): 벨의 우측 엣지가 스크롤 콘텐츠 우측 엣지와 3px
    // 어긋나 있었다. 크롬과 본문은 같은 거터를 쓴다.
    // [2026-08-20] 가운데 로고 — 좌 스페이서(40) · 로고(flex 1, 가운데) · 벨(40)의 대칭 3열.
    // 거터는 그대로 두 끝에 남고, 양쪽 40이 같으므로 로고는 화면 정중앙에 온다.
    flexDirection: 'row', alignItems: 'center',
    paddingTop: 48, paddingBottom: 9, paddingHorizontal: layout.gutter,
    backgroundColor: paper.canvas, borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  topSpacer: { width: 40 },
  topLogo: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7 },
  // 17pt — 14pt 하한 위이므로 §3 로고 예외를 타지 않는다. 보조기술에도 숨기지 않는다.
  wordmark: { fontSize: 17, lineHeight: 22, color: paper.ink, letterSpacing: 0.2 },
  // [§3b 아이콘 컨트롤 2026-08-11] '아이콘 온리 컨트롤 = 40×40 정사각 · 캔버스 · 코랄 1px'은
  // 바인딩 스펙인데 이 벨만 26×26 + 뉴트럴 #EEE 보더로 남아 있었다 (스펙 제정 이전의 잔재).
  // 44pt 타깃 법(§7b Fitts)에도 26은 미달 — 규격으로 되돌린다. 글리프도 16 → 20.
  bell: {
    width: 40, height: 40, borderRadius: 0, borderWidth: 1, borderColor: paper.line,
    backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
  },
  // 미읽음 도트 — 보호자 홈과 동일 어휘(코랄 6px 글로우), 40px 벨에 맞춘 인셋
  bellDot: {
    position: 'absolute', top: 6, right: 6, width: 6, height: 6, borderRadius: 3,
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

  // [§3b 2026-08-11] 섹션 헤더 — 앱 전체 단일 그램마: 타이틀 20/800 잉크 · 우측 링크 16/800
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: lilac.head },
  // [v4] 섹션 링크가 코랄이었다 — 한 화면에 코랄 셰브런이 여섯 개(요청함·캘린더·리워드 센터·
  // 시간 조정·수익 상세·컬렉션)면 클라이맥스가 여섯 개고, 그건 클라이맥스가 없다는 뜻이다.
  // 랩의 R1a도 이 링크들을 굵은 잉크 + 셰브런으로 그린다. 코랄은 수락 문 하나가 가져간다.
  secLink: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: lilac.head },
  // [§3b] 승인된 촉감 패턴 — 컴포지터 전용 scale 프레스 (버튼 4킨드 공통)
  pressed96: { transform: [{ scale: 0.96 }] },

  // ① 빕 스트랩 — [Ⓑ①] 빕이 한 줄로: 이름(df)·티어·온라인 토글. 케이지 산식은 JSX 주석에.
  // [정체성 2026-08-11] 빕은 아티팩트다 — "dark is the artifact, light is the screen" (§1).
  // 흰 카드로 앉아 있을 때는 다른 카드와 구별되지 않았다. 잉크로 뒤집으면 이 줄이 러너의
  // 레이스 빕으로 읽히고, 화면의 정체성 인쇄가 정확히 한 번이 된다.
  strap: {
    marginTop: 12, backgroundColor: paper.ink, borderRadius: 0,
    alignItems: 'center', gap: 10, paddingVertical: 12, paddingHorizontal: 12,
  },
  strapName: { fontSize: 17, lineHeight: 22, color: '#FFFFFF' }, // 디스플레이 서체(df) 지참 — 화면당 1회 예산
  // 잉크 위 실측: #999 = 6.57:1 (AA 통과). lilac.dim(#7C76A0)은 잉크 위에서 3.4:1로 미달한다.
  strapNameEm: { fontSize: 15, lineHeight: 20, color: paper.faint, fontWeight: '600' },
  strapTier: { fontSize: 15, lineHeight: 20, color: paper.faint, fontWeight: '700' },

  // ② 온라인 토글 행 — [v4] 캔버스 위 자기 행. 44pt 타깃 법: 56×32 스위치 + 15/20 서브줄로 행 높이 ≈ 64.
  tog: {
    flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 60,
    paddingTop: 14, paddingBottom: 12,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  togLbl: { fontSize: 17, lineHeight: 22, fontWeight: '800' }, // 색은 상태에 따라 인라인 (잉크/딤/크리티컬)
  togSub: { fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 2 },
  // 상태 로드 실패의 재시도 — 아래 recFail과 같은 문법 (크리티컬 잉크 + 밑줄, ≥44pt 타깃)
  togRetry: { minHeight: 44, justifyContent: 'center', flexShrink: 0 },
  togRetryTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // 스위치 — 랩 치수 56×32. ON = 잉크(상태), OFF = 인셋. 코랄 없음: 코랄은 '누를 곳'이지 '켜진 상태'가 아니다.
  swTrack: { width: 56, height: 32, borderRadius: 16, padding: 3, flexDirection: 'row', borderWidth: 1, flexShrink: 0 },
  swTrackOn: { backgroundColor: lilac.head, borderColor: lilac.head, justifyContent: 'flex-end' },
  swTrackOff: { backgroundColor: lilac.inset, borderColor: lilac.hair, justifyContent: 'flex-start' },
  // 노브는 항상 흰색 + 헤어라인 — OFF의 인셋 트랙 위에서도 노브 경계가 보인다 (불투명도 트릭 금지)
  swKnob: {
    width: 24, height: 24, borderRadius: 12, backgroundColor: '#FFFFFF',
    borderWidth: 1, borderColor: lilac.hair,
    shadowColor: '#1C1837', shadowOpacity: 0.22, shadowRadius: 2, shadowOffset: { width: 0, height: 1 },
  },

  // ③ 이번 주 한 줄 — [v4] 머니 히어로(₩50pt·점선 리더 3행·월/누적 창·오늘 합)를 대체한다.
  // 숫자만 Oswald, lineHeight 19 = 1.27× (BUG A 법). 320dp에서 값이 두 줄로 접히면 접힌다 —
  // flex:1 + textAlign right라 오른쪽 정렬을 유지한 채로 흐른다.
  week: { alignItems: 'baseline', gap: 8, paddingTop: 11, paddingBottom: 11, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  weekK: { fontSize: 15, lineHeight: 20, color: lilac.dim, fontWeight: '600', flexShrink: 0 },
  weekV: { flex: 1, textAlign: 'right', fontSize: 15, lineHeight: 20, color: lilac.head, fontWeight: '600' },
  weekNum: { fontSize: 15, lineHeight: 19, color: lilac.head },

  // [§3b status chip] 16/800 · 보더 없는 틴트 필 · 샤프 (앰버 = 시맨틱 지명 신호)
  monoTagStar: { backgroundColor: lilac.amberSoft, borderRadius: 0, paddingHorizontal: 7, paddingVertical: 2 },
  monoTagStarTxt: { fontSize: 16, lineHeight: 20, letterSpacing: 0.5, color: lilac.amber, fontWeight: '800' },

  // ④ 티켓 오브젝트 — [v4] 진행 중 카드와 맨 앞 요청이 **같은** 문법을 쓴다. 랩의 법: 러너가 실제로
  // 들고 가는 것만 박스를 받는다. 그래서 보더가 뉴트럴 #EEE 1px에서 **잉크 1.5px**로 올라간다 —
  // 은퇴한 장부 히어로가 들고 있던 '강조 하나'의 예산을 이 두 오브젝트가 물려받는다 (§7b Von Restorff:
  // 강조는 화면당 하나의 **종류**이고, 여기서는 '오브젝트다'라는 한 종류가 두 번 나타난다).
  ticket: { marginTop: 9 },
  tMain: { backgroundColor: lilac.card, borderRadius: 0, borderWidth: 1.5, borderBottomWidth: 0, borderColor: lilac.head, overflow: 'hidden' },
  // BUG A: 티켓 시각 31pt → lineHeight 39 (1.26×), includeFontPadding 제거 — "0" 상단 온전
  tBig: { fontSize: 31, color: lilac.head, lineHeight: 39 },
  // [v4] 요청 티켓의 시각 — 진행 중(31)보다 한 단 아래 (같은 크기면 위계가 없다). lineHeight 30 = 1.25×
  tMid: { fontSize: 24, color: lilac.head, lineHeight: 30, flexShrink: 1 },
  perfWrap: { backgroundColor: lilac.card, borderLeftWidth: 1.5, borderRightWidth: 1.5, borderColor: lilac.head, position: 'relative' },
  perf: { borderTopWidth: 1.5, borderTopColor: '#DCD7F0', borderStyle: 'dashed' },
  // 노치 = 캔버스 구멍 (원형은 퍼포 아티팩트 예외). [v4] 보더가 잉크 1.5px로 올라가면서 바깥쪽 호를
  // 투명으로 끊는다 (랩 .perf:before/after의 border-*-color:transparent) — 안 그러면 티켓 옆에
  // 온전한 원 두 개가 붙어 '구멍'이 아니라 '단추'로 읽힌다.
  perfNotch: { position: 'absolute', top: -8, width: 16, height: 16, borderRadius: 8, backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: lilac.head },
  tStub: { backgroundColor: lilac.card, borderRadius: 0, borderWidth: 1.5, borderTopWidth: 0, borderColor: lilac.head, paddingHorizontal: 13, paddingTop: 11, paddingBottom: 12 },

  // 오브젝트 본문 — 두 티켓이 공유하는 줄들
  objStage: { fontSize: 15, lineHeight: 20, fontWeight: '800', flexShrink: 0 }, // 색 = STAGE[rawStatus].color (인라인)
  objMain: { marginTop: 8, fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.head },
  // A — the demoted clock. 15pt keeps the detail floor (raised from 14 on 2026-08-25); it is a
  // supporting fact, not a datum.
  objClock: { marginTop: 3, fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.dim },
  // D — road name quiet, 동·호수 loud. The bold half is the half that finds the door.
  objAddr: { marginTop: 3, fontSize: 15, lineHeight: 20, color: lilac.dim },
  objDetail: { marginTop: 1, fontSize: 15, lineHeight: 19, fontWeight: '800', color: lilac.head },
  // C — confirmation, not a call to action. Green reads as money without spending the coral budget.
  objPay: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: '#2F7D4F' },
  objStubTxt: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.dim },
  // ① the coral action. 4px depth edge = the same drawn-button grammar the owner home uses, so a
  // dual-role user meets one language. Solid coral: title white is 4.84:1 on paper.action (the
  // ground's ceiling), sub is paper.wash at 4.55:1 — both measured, both above the 4.5 floor.
  jobCta: { marginTop: 10, backgroundColor: paper.action, paddingHorizontal: 14, paddingVertical: 13,
    borderBottomWidth: 4, borderBottomColor: '#A63A20' },
  jobCtaT: { fontSize: 18, lineHeight: 23, fontWeight: '800', color: '#FFFFFF' },
  jobCtaS: { marginTop: 2, fontSize: 15, lineHeight: 20, color: paper.wash },
  // chat — ink outline, deliberately not a second coral (see the JSX note).
  jobChat: { marginTop: 8, backgroundColor: lilac.card, borderWidth: 1.5, borderColor: lilac.head,
    paddingHorizontal: 14, paddingVertical: 11 },
  jobChatT: { fontSize: 17, lineHeight: 22, fontWeight: '800', color: lilac.head },
  jobChatS: { marginTop: 1, fontSize: 15, lineHeight: 20, color: lilac.dim },
  objNum: { fontSize: 15, lineHeight: 20, color: lilac.head }, // Oswald 숫자 — lineHeight 1.33× (BUG A)
  objQuiet: { marginTop: 3, fontSize: 15, lineHeight: 20, color: lilac.dim },
  // 스텁의 액션 줄 — 코랄 면(nowBar) 은퇴 후의 자리. 카드 전체가 탭 타깃이라 이 줄은 라벨이지 버튼이 아니다.
  objActTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: lilac.head, textAlign: 'right' },

  door: { flex: 1, borderRadius: 0, paddingVertical: 15, paddingHorizontal: 11, overflow: 'hidden' }, // [§3b] 샤프 · pv 12 → 15 (버튼 공통 플로어)
  doorCoral: { backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP }, // 코랄 글로우 섀도 은퇴
  // [v4] LIVE 러닝이 코랄을 쥐고 있을 때의 수락 문 — 잉크 아웃라인 고스트 (랩 .doorB). 여전히 프라이머리
  // 치수(pv 15 · 라벨 17/800)라 '내려간 것은 색이지 문이 아니다'가 읽힌다.
  doorGhost: { backgroundColor: lilac.card, borderWidth: 1.5, borderColor: lilac.head },
  doorQuiet: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE' },
  doorName: { fontSize: 16, lineHeight: 22, fontWeight: '800' }, // 수락 문은 인라인 17로 승격 (프라이머리급) · 거절/자세히 16/800
  doorSub: { marginTop: 4, fontSize: 15, lineHeight: 20 },
  doorSubNum: { fontSize: 15, lineHeight: 20 },

  // 스텁 행 — 목업 .s-act width 92 → 96 (FIX3: 11.5pt 캡션 한 줄 여유 확보, 구조는 동일)
  stub: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, overflow: 'hidden' }, // [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴
  stubNm: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: lilac.head },
  stubKm: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.head },
  stubKmUnit: { fontSize: 15, color: lilac.dim, fontWeight: '600' }, // [v4] 코랄 단위 은퇴 — 단위는 강조가 아니다
  stubWhen: { fontSize: 15, lineHeight: 20, color: lilac.dim, fontWeight: '500' },
  // [A② 2026-08-25] 스텁의 마감 — 같은 줄, 같은 크기(15pt 바닥), 잉크로 한 단 올린다.
  // 시각은 참고값이고 남은 시간이 행동을 바꾸는 값이라 이쪽이 무게를 갖는다. 앰버·크리티컬은
  // 쓰지 않는다: 서버에 임박 문턱이 아예 없어서(오직 scheduled_at < now()) 색으로 급함을
  // 주장하면 그건 측정이 아니라 지어낸 긴급함이다.
  stubRel: { fontSize: 15, lineHeight: 20, color: lilac.head, fontWeight: '800' },
  // [Ⓑ① re-derive] 112 케이지 유지. 캡션이 'KRW 실수령' → '실수령'(한글 3자 ≈ 3×15 + ls = 47px)으로 줄어
  // 최장 소자는 이제 요금 숫자('999,999' 7글리프 × ~8.5 ≈ 60px)와 '보기 ›' 라벨(2×16 + 12 ≈ 44px) —
  // 60 + 패딩 16 = 76 < 112 (기기 폰트 스케일 여유 36px).
  stubAct: { width: 112, borderLeftWidth: 1.4, borderStyle: 'dashed', borderLeftColor: '#DCD7F0', paddingVertical: 11, paddingHorizontal: 8, alignItems: 'center', justifyContent: 'center', gap: 7 },
  stubNotch: { position: 'absolute', left: -6, width: 12, height: 12, borderRadius: 6, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', zIndex: 3 },
  // BUG A: 스텁 요금 17pt → lineHeight 22 (1.29×), includeFontPadding 제거
  stubFare: { fontSize: 17, lineHeight: 22, color: lilac.head },
  stubFareCap: { fontSize: 15, lineHeight: 20, letterSpacing: 0.5, color: lilac.dim, fontWeight: '500', marginTop: 2 }, // [§3b] 한글 캡션 — 라틴 자간 1 → 0.5
  // [§3b] 세컨더리 킨드 — 캔버스 필 + 코랄 라인 보더 + 잉크 16/800 (구 코랄 필 '수락'은 요청함으로 가는
  // 문이었다 — 라벨과 킨드를 정직하게)
  stubView: { width: '100%', borderRadius: 0, paddingVertical: 15, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: paper.line },
  stubViewTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', color: lilac.head },
  emptyInbox: { marginTop: 9, backgroundColor: lilac.inset, borderRadius: 0, padding: 16, borderWidth: 1, borderColor: '#EEEEEE' }, // [페이퍼 크롬] 샤프 (인셋 필 생존)
  emptyInboxTxt: { fontSize: 15, lineHeight: 20, color: lilac.dim, textAlign: 'center' },
  emptyInboxLink: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.actionInk, textAlign: 'center', marginTop: 5 },
  // [A① 2026-08-24] 조용한 날의 두 줄 요약. 랩의 .sumrow 문법 그대로: 라벨 고정 열 · 값 우측 정렬 ·
  // 문은 행 끝. 이 상태의 코랄 수는 **0개**이고 그건 합법이다 (requests.tsx R2c 선례) — 누를 것이
  // 없는 화면에 클라이맥스를 만들면 그 코랄이 가리키는 행동이 없다.
  emptyInboxHead: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: lilac.head, textAlign: 'center' },
  emptySum: { marginTop: 11, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  // min-height 52 + 15/20 두 소자 = 랩 치수(2026-08-25 플로어 상향분 반영). 문(시간 조정)은
  // 자기 44pt 타깃을 따로 진다.
  sumRow: { alignItems: 'center', gap: 10, minHeight: 52, paddingVertical: 12 },
  sumRowDiv: { borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  sumLbl: { width: 96, flexShrink: 0, fontSize: 15, lineHeight: 20, color: lilac.dim },
  sumVal: { flex: 1, minWidth: 0, textAlign: 'right', fontSize: 15, lineHeight: 20, fontWeight: '800', color: lilac.head },
  sumAct: { minHeight: 44, justifyContent: 'center', flexShrink: 0 },
  sumActTxt: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: lilac.head },
  // 닫는 문장은 좌측 정렬 — 두 줄로 접히는 문장을 가운데 정렬하면 읽는 눈이 매 줄 시작점을 다시 찾는다.
  emptyInboxNote: { marginTop: 11, fontSize: 15, lineHeight: 21, color: lilac.dim },

  // ② 루트 — 목업 .stop padding 7 0 8, gap 11
  stop: { flexDirection: 'row', alignItems: 'flex-start', gap: 11, paddingTop: 7, paddingBottom: 8 },
  stopPt: { width: 14, height: 14, borderRadius: 7, marginTop: 2, backgroundColor: lilac.card, borderWidth: 1.5, borderColor: '#DCD6F8', alignItems: 'center', justifyContent: 'center' },
  stopPtOn: { borderColor: lilac.head }, // [v4] 링도 잉크 — 안쪽 점과 같은 이유 (코랄은 수락 문 하나)
  stopTm: { fontSize: 16, lineHeight: 20, fontWeight: '600', color: lilac.head }, // [2026-08-10] 14 → 16 Oswald · lineHeight 20 = 1.25× (BUG A); time col widened 52 → 60 in JSX
  stopTmSub: { fontSize: 15, lineHeight: 20, color: lilac.dim, fontWeight: '500', marginTop: 2 },
  stopInfoB: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.head },
  stopInfoS: { fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 2 },
  // [2026-08-10] 14 → 16 Oswald · lineHeight 20 = 1.25× (BUG A). Row check at 320dp: card content
  // 320 − 30 gutter − 26 card pad − 2 border = 262 → minus pt 14, gaps 3×11, time 60, pay '+99,000'
  // ≈ 60 leaves ≈ 95px for the info column (flex, minWidth 0 — long dog names ellipsize, no overlap).
  stopPay: { fontSize: 16, lineHeight: 20, fontWeight: '600', color: lilac.head, marginTop: 1 },

  // ③ 리워드
  fee: { fontSize: 15, lineHeight: 20, letterSpacing: 0.5, color: lilac.head, fontWeight: '600' },
  rung: { flex: 1, height: 6, backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE', overflow: 'hidden' },
  rungL: { borderTopLeftRadius: 99, borderBottomLeftRadius: 99 },
  rungR: { borderTopRightRadius: 99, borderBottomRightRadius: 99 },
  rungFill: { height: '100%', backgroundColor: lilac.accent },
  trailCnt: { fontSize: 15, lineHeight: 20, letterSpacing: 1, color: lilac.accent, fontWeight: '500' },
  flagLb: { fontSize: 15, lineHeight: 20, letterSpacing: 1.2, color: lilac.dim, fontWeight: '600' },
  flagTrack: { flex: 1, height: 5, borderRadius: 99, backgroundColor: lilac.inset, overflow: 'hidden', borderWidth: 1, borderColor: '#EEEEEE' },
  flagFill: { height: '100%', borderRadius: 99, backgroundColor: lilac.accent },
  flagCnt: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.head },

  // ④ 가능 시간 — 목업 .day padding 8 0 7 · [페이퍼 크롬] 샤프·뉴트럴 (dayOn 바이올렛 틴트는 액센트 생존)
  // [E7 2026-08-12] 기록면 — my.tsx에서 그대로 옮겨온 아티팩트 (§1 "다크는 아티팩트"). 값은
  // my.tsx의 s.record / s.recordInner / s.recN … 과 동일하다. 라디우스만 라일락 스케일 대신
  // 0 — 이 화면은 페이퍼 크롬이고 §3b는 클럽 카드까지 포함해 모든 코너를 샤프로 못박았다.
  record: {
    backgroundColor: '#1C1837', borderRadius: 0, overflow: 'hidden', marginTop: 10,
    shadowColor: '#120E2C', shadowOpacity: 0.34, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  recordInner: { margin: 9, borderWidth: 1, borderColor: 'rgba(255,255,255,0.13)', borderRadius: 0, padding: 13 },
  recordKick: { fontSize: 15, lineHeight: 20, letterSpacing: 1, color: 'rgba(255,255,255,0.5)', textTransform: 'uppercase' },
  coralDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral },
  // 큰 숫자 — 세 칸이 한 칸이 되면서 23 → 34로 승격 (BUG A: lineHeight 43 = 1.26×)
  recN: { fontSize: 34, lineHeight: 43, fontWeight: '800', color: '#fff' },
  recU: { fontSize: 15, fontWeight: '500', color: 'rgba(255,255,255,0.55)' },
  recL: { fontSize: 15, lineHeight: 20, color: 'rgba(255,255,255,0.62)', marginTop: 2 },
  recGoWrap: { marginTop: 12, paddingTop: 10, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.13)', alignItems: 'flex-end' },
  recGo: { fontSize: 15, fontWeight: '700', color: '#fff' },
  recFail: {
    alignItems: 'center', justifyContent: 'space-between', gap: 9,
    marginHorizontal: -layout.gutter, marginTop: 8, paddingVertical: 11, paddingHorizontal: layout.gutter,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
  },

  // [Ⓑ②] 접힘 상태의 7칸 스트립. 320dp 실측: 콘텐츠 264 − 갭 3×6 = 246 / 7 ≈ 35px/칸.
  // 15pt 한글 한 글자 ≈ 15px이라 여유가 두 배 — 랩이 걸어둔 타입 플로어 반대는 실측으로 해소됐다.
  // 높이 26은 요약 표식의 크기다 (탭 타깃은 이 스트립이 아니라 감싸는 44pt 행이 진다).
  // [2026-08-25] 15/20 으로 올라가도 20 < 26 이라 칸 높이는 그대로다.
  sq: {
    flex: 1, height: 26, borderRadius: 0, alignItems: 'center', justifyContent: 'center',
    // [2026-08-25 pale retirement] hardcoded #E6E2F4 (lilac.hair's OLD value) → the token, which
    // now carries the neutral #EEEEEE. The literal was a copy of the token and drifted out of the
    // sweep's reach; binding it back is what keeps the next ruling from missing this cell.
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
  },
  sqOn: { backgroundColor: lilac.accent, borderColor: lilac.accent },
  sqTxt: { fontSize: 15, lineHeight: 20, fontWeight: '800' },

  day: { flex: 1, borderRadius: 0, paddingVertical: 8, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE' },
  dayOn: { backgroundColor: '#F4F1FE', borderColor: '#DCD6F8' },
  dayD: { fontSize: 15, fontWeight: '700', lineHeight: 20 },
  dayH: { fontSize: 15, lineHeight: 20, letterSpacing: 0.4, fontWeight: '500', marginTop: 4 },

  // ⑤ 최근 완료 — 목업 .drow padding 10 11, patch 34
  drow: { alignItems: 'center', gap: 10, paddingHorizontal: 11, paddingVertical: 10 },
  patchFallback: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#1C1837', alignItems: 'center', justifyContent: 'center' },
  patchFallbackTxt: { fontSize: 15, lineHeight: 20, color: '#CFC4FF', fontWeight: '600' },
  drowB: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.head },
  drowS: { fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 3 },
  drowPay: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.text },
  shot: { borderWidth: 1, borderColor: '#EEEEEE', backgroundColor: lilac.card, borderRadius: 0, paddingVertical: 4, paddingHorizontal: 6 }, // [페이퍼 크롬]
  shotTxt: { fontSize: 15, fontWeight: '600', color: lilac.head },

  // 퀵 링크 — 목업 .qlink padding 10 11 (푸터 스타일은 Ⓑ① 재인쇄 은퇴와 함께 삭제)
  qlink: { flexBasis: '48%', flexGrow: 1, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 6, backgroundColor: paper.canvas, borderWidth: 1, borderStyle: 'dashed', borderColor: '#EEEEEE', borderRadius: 0, paddingVertical: 10, paddingHorizontal: 11 }, // [페이퍼 크롬] 글래스 은퇴
  qlinkB: { fontSize: 15, fontWeight: '600', color: lilac.head },
  qlinkChev: { fontSize: 12, color: lilac.dim }, // 글리프 전용(›) 셰브런 — 플로어 면제
});
