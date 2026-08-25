import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, Dimensions, Easing, Image, Pressable, ScrollView, Share, StyleSheet, Text, TextStyle, View } from 'react-native';
import { homePath } from '../../src/components/bottomnav';
import { PatchBadge } from '../../src/components/patch';
import { HeatTrace } from '../../src/components/runcard';
import { traceToBox } from '../../src/lib/trace';
import { PaperBtn } from '../../src/components/paper-btn';
import { ProfileGaps } from '../../src/components/profile-gaps';
import { Monogram, Row, Skeleton } from '../../src/components/ui';
import { MediaImage } from '../../src/lib/media';
import { checkSlot, CoursePatch, fetchPatchPop, fetchProfileGaps, fetchRunEarning, fetchRunReportOrNull, fetchRunStandings, fetchStampPop, ProfileGap, RunEarning, RunReport, RunStandings, StampInfo } from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { getNaverMap, smoothTrace } from '../../src/lib/geo';
import { goBackOrHome } from '../../src/lib/nav';
import { supabase } from '../../src/lib/supabase';
import { draft, TracePoint } from '../../src/store';
import { colors, lilac, paper } from '../../src/theme';

// 러닝 리포트 — 러닝 하나의 '프로필 페이지'. 풀블리드 · 공유 가능 · 사진 · 개인 기록 배지.
// 진입: 알림 · 내 일정 완료 카드 · 체력 리포트 최근 러닝. 공유가 곧 마케팅 (자랑 = 전파).

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
// paper.inkPressed 동반 은퇴 — 다크 카드 위의 더 밝은 안쪽 패널은 paper.inkPressed(#333)가 같은 역할을 한다 (신규 색 0개).
// 읽는 바이올렛 (colors.clubInk와 같은 값 — '텍스트용 2단' 문법). 적립 스트립 키커 전용.
// lilac.bg(#F4F2FB) 위 실측 대비: accent #6C5CE7 = 4.38:1 (AA 미달) · #4A3DA8 = 7.50:1 (통과).
// [2026-08-25 pale retirement — re-measured on the new ground, both values SUPERSEDED, not erased]
// lilac.bg is now #FFFFFF, so: accent #6C5CE7 = 4.86:1 (it now clears AA) · #4A3DA8 = 8.32:1.
// READ_VIOLET stays anyway — it is the 'reading' step of the two-step violet grammar, not a
// contrast workaround, and 8.32 on a 14pt kicker is the margin this strip should have.
const READ_VIOLET = '#4A3DA8';
const W = Dimensions.get('window').width;
const TILE = (W - 4) / 3;

const REASON: Record<string, { label: string; color: string; bg: string; note?: string }> = {
  completed: { label: '완주 완료', color: '#3d5a2b', bg: '#e3f0c4' },
  dog_condition: {
    label: '반려견 컨디션으로 조기 종료', color: '#d84a2f', bg: '#fde8e3',
    // Trimmed: "러너 판단으로 안전하게 종료했어요" moved into the 왜 멈췄는지 block, which says it
    // better and says it first. What survives here is the half that block does NOT carry — the
    // owner's next action and the recourse path. One fact, one printing.
    note: '아이 상태를 확인해주시고, 이상이 있으면 안심 센터로 연락주세요.',
  },
  owner_request: { label: '보호자 요청으로 종료', color: '#a97c12', bg: '#fbf0d4' },
  runner_personal: { label: '러너 사정으로 종료', color: '#75806f', bg: '#e9ebe2' },
};

const STATUS_LABEL: Record<string, string> = {
  matching: '러너 매칭 중', runner_pending: '러너 응답 대기', confirmed: '러너 확정 — 러닝 전',
  runner_enroute: '러너 이동 중', picked_up: '인계 완료 — 시작 대기', active: '러닝 진행 중',
};

// 실트레이스 → 박스 좌표: src/lib/trace.ts의 traceToBox로 이전 (0082 K1).
// 여기 있던 normalizeTrace는 축별 min-max라 종횡비를 늘렸다 — 동서로 긴 경로가
// 세로로 부푼 실루엣이 되던 버그. 이제 코스·러닝이 같은 투영을 쓴다.

const fmtDur = (sec: number) => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');
const targetPaceSec = (label: string) => (label.includes('8') ? 480 : label.includes('6') ? 360 : 420);

// ═══════ "다음 주 같은 시간 예약" — resolve it, or do not say it (RULING #11) ═══════
// The coral panel is allowed to NAME a time only if that exact time is something owner/request.tsx
// can actually receive and display. Three checks, each one a mirror of a rule that lives in
// request.tsx, because request.tsx is the screen this panel hands off to:
//
//  ① target = scheduled_at + 7d, and target ≥ now + 2h.
//     request.tsx's mount effect NULLS any draft ISO inside the 2-hour notice floor and silently
//     calls pickEarliest() — so an unchecked prefill becomes "the earliest slot" under a button
//     that said 다음 주 같은 시간. slotAllowed() enforces the same floor on every chip.
//  ② target's calendar day is inside request's date strip (today .. today+7).
//     request.tsx's focus-sync does DATES.findIndex(...); a miss leaves dateIdx at 0, so the strip
//     highlights today while the label names next week — a screen lying about what it will book.
//     Its DATE_STRIP_DAYS is 8 precisely so run+7d is reachable; we re-check rather than assume.
//  ③ HH:MM is one of request's nine slots. The booking was made from one, but a run that was
//     rescheduled off-slot has no chip to land on.
//
// Any check failing → the panel falls back to today's timeless "이대로 다시 예약" copy.
// Everything here is device-local time, exactly as request.tsx computes it (toDate/buildDates use
// the local Date constructor), so the HH:MM we test is the HH:MM the slot sheet prints.
//
// The two constants are a deliberate LOCAL COPY, not an import: request.tsx keeps both module-
// private and this screen only needs to ASK whether a time is offerable. If they ever drift, this
// check gets stricter or looser — never wrong — because a miss shows the no-time copy.
const REQUEST_SLOTS = ['06:30', '07:30', '09:00', '13:00', '15:30', '17:00', '18:30', '19:30', '21:00'];
const REQUEST_STRIP_DAYS = 8; // owner/request.tsx DATE_STRIP_DAYS — today .. today+7
const NOTICE_MS = 2 * 3600_000;
const WD = '일월화수목금토';

function resolveNextWeek(iso: string | null): { iso: string; timeLabel: string; whenLabel: string } | null {
  if (!iso) return null;
  const src = new Date(iso);
  if (Number.isNaN(src.getTime())) return null;
  // +7d as 168h, the same arithmetic buildDates() uses to lay out the strip (KST has no DST)
  const target = new Date(src.getTime() + 7 * 86400_000);
  if (target.getTime() < Date.now() + NOTICE_MS) return null;                       // ①
  const hhmm = `${String(target.getHours()).padStart(2, '0')}:${String(target.getMinutes()).padStart(2, '0')}`;
  if (!REQUEST_SLOTS.includes(hhmm)) return null;                                   // ③
  let idx = -1;                                                                     // ②
  for (let i = 0; i < REQUEST_STRIP_DAYS; i++) {
    if (new Date(Date.now() + i * 86400_000).toDateString() === target.toDateString()) { idx = i; break; }
  }
  if (idx < 0) return null;
  // ④ RECENCY. ② only asks whether run+7d lands SOMEWHERE in the 8-day strip, which a run 1–7
  // days old also satisfies — and then the panel titled 다음 주 같은 시간 prefilled TOMORROW (6d
  // old) or TODAY (7d old). Nothing on the panel contradicted it: the subline carries a weekday
  // only. run+7d is next week ONLY when the run was TODAY, which is exactly idx === last slot.
  if (idx !== REQUEST_STRIP_DAYS - 1) return null;
  // request.tsx pickSlot()'s label format, verbatim: '오늘 19:30' · '내일 19:30' · '8월 26일 19:30'.
  // Matching it is what makes the focus-sync land on the right row instead of showing a stale label.
  const dayLabel = idx === 0 ? '오늘' : idx === 1 ? '내일' : `${target.getMonth() + 1}월 ${target.getDate()}일`;
  return {
    iso: target.toISOString(),
    timeLabel: `${dayLabel} ${hhmm}`,
    whenLabel: `${WD[target.getDay()]} ${hhmm}`, // panel subcopy — the lab's '수 19:30'
  };
}

// 개인 기록 배지 — 내 역사와의 경쟁 (동네 리더보드는 서버 집계 후)
function badges(st: RunStandings | null): string[] {
  if (!st) return [];
  const out: string[] = [`${st.nth}번째 러닝`];
  if (st.total > 1) {
    if (st.kmRank === 1) out.push('★ 역대 최장 거리');
    else if (st.kmRank <= 3) out.push(`거리 TOP ${st.kmRank}`);
    if (st.paceRank === 1) out.push('★ 역대 최고 페이스');
    else if (st.paceRank != null && st.paceRank <= 3) out.push(`페이스 TOP ${st.paceRank}`);
  }
  return out;
}

// ═══════ 내가 남긴 후기 — 세 상태(모름 / 없음 / 있음)를 절대 둘로 접지 않는다 ═══════
// Deliberately a LOCAL read rather than an api.ts export: api.ts is owned by another slice this
// session and a client that imports a function nobody added does not compile. The shape below is
// the one api.ts should eventually carry as `fetchMyReview(bookingId)` — hoist it there when
// review.tsx's 「이미 남긴 후기」 screen (lab C③, not picked) needs the same row, and delete this.
// Same direct-supabase grammar owner/review.tsx (the writer of this very row) already uses.
type MyReview = { rating: number | null; tags: string[]; createdAt: string; visibility: string };

// Returns `undefined` for "could not check" — distinct from `null`, which means "checked, none".
// Every failure path (no session, RLS, transport) returns undefined: unknown is never a yes.
async function readMyReview(bookingId: string): Promise<MyReview | null | undefined> {
  try {
    const { data: u } = await supabase.auth.getUser();
    if (!u.user) return undefined;
    const { data, error } = await supabase
      .from('reviews')
      .select('rating, tags, note, created_at, visibility')
      .eq('booking_id', bookingId)
      .eq('author_id', u.user.id)
      .eq('target_kind', 'runner')
      .maybeSingle();   // 0행 = null · 2행 이상/전송 실패 = throw (fetchRunReportOrNull과 같은 규율)
    if (error) return undefined;
    if (!data) return null;
    return {
      rating: data.rating ?? null,
      tags: Array.isArray(data.tags) ? data.tags : [],
      createdAt: data.created_at,
      visibility: data.visibility,
    };
  } catch {
    return undefined;
  }
}

// created_at → 「8월 19일」. Intl/toLocaleDateString is unreliable on Hermes without ICU, and the
// only thing this line needs is month/day, so it is computed rather than formatted.
const fmtMonthDay = (iso: string): string | null => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : `${d.getMonth() + 1}월 ${d.getDate()}일`;
};

export default function Report() {
  // 디스플레이 서체 — 화면에 **한 번**. [2026-08-19] 그 한 번은 이제 헤더 크롬이 아니라 러닝
  // 타이틀이다 (헤더는 request/review와 같은 평 900 잉크로 내렸다). 종전 주석의 '숫자 금지'는
  // 여기서 완화된다: 랩 14a의 타이틀이 '초코, 5.1km 완주'로 숫자를 문장 안에 품고 있고, Sean이
  // 그 안을 골랐다. 애슬레틱 숫자(Oswald)는 바로 아래 숫자 셋이 전부 가져간다 — 두 서체가
  // 같은 값을 두 번 그리지 않는다.
  const df = useDisplayFont();
  const nf = useNumFont();     // Oswald 숫자 — 적립 합계 (lineHeight 명시 필수, BUG A)
  const { bid, shot } = useLocalSearchParams<{ bid: string; shot?: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [standings, setStandings] = useState<RunStandings | null>(null);
  // TWO STATES, NEVER ONE SENTENCE (2026-08-20).
  //  err      = the read FAILED (network, RLS, 5xx). Retryable → 다시 시도.
  //  notFound = the read SUCCEEDED and there is no such run for me: a foreign booking id, a stale
  //             push ref_id, a deleted booking, or a link with no bid at all. Nothing to retry →
  //             an exit. Merging them is what printed 「JSON object requested, multiple (or no)
  //             rows returned」 at line 289 of the previous revision: `e.message` straight from
  //             PostgREST, in English, on a Korean owner's screen. Merging them the other way is
  //             worse — it would tell an owner on flaky LTE that a run they took cannot be found.
  const [err, setErr] = useState(false);
  const [notFound, setNotFound] = useState(false);
  // Ⓒ② 오늘의 수확 — 패치 승급 + 이 러닝이 방금 넘긴 도장을 오버레이 '하나'로 (닫기도 하나).
  // null = 그릴 게 없다 (fetch 진행 중 포함) — 둘 다 결과가 온 뒤 내용이 있을 때만 세워진다.
  const [haul, setHaul] = useState<{ patch: CoursePatch | null; stamps: StampInfo[] } | null>(null);
  // 리워드 ① — 이 러닝의 하이 포인트 적립. loaded 플래그가 따로 있는 이유: null 은 '적립 없음'
  // (조기 종료·정산 전)이라는 사실이고, 미도착은 '아직 모름'이다. 둘 다 0을 그리지 않는다.
  const [earning, setEarning] = useState<RunEarning | null>(null);
  const [earningLoaded, setEarningLoaded] = useState(false);
  // ★ THE STAR ROW LEARNS WHETHER IT HAS ALREADY BEEN USED (lab B①, Sean 2026-08-24).
  // The old comment here was right that nothing TOLD this screen — and wrong that nothing could.
  // `reviews` has `unique (booking_id, author_id, target_kind)` (0001_init.sql:260) and
  // `reviews author read` (0002_rls.sql:118) grants exactly this row to its author, so one narrow
  // read gives three states that must never be collapsed into two:
  //   known=false            → not answered yet, or the read FAILED → draw NOTHING. A hollow star
  //                            row asserts "you have not reviewed", which is a fact we do not have.
  //   known=true, row null   → no review exists → today's affordance, unchanged.
  //   known=true, row present→ the real rating, the real tags, the real date — and no edit button,
  //                            because the unique index refuses a second one.
  const [myReview, setMyReview] = useState<MyReview | null>(null);
  const [myReviewKnown, setMyReviewKnown] = useState(false);
  // 프로필 빈칸 넛지 (랩 ①) — `null` 은 **모름**이다: 아직 안 읽었거나 읽기가 실패했다.
  // 배열만이 사실이고, 사실일 때만 블록이 그려진다. 실패를 '다 채워졌다'로 그리지 않는다.
  const [profileGaps, setProfileGaps] = useState<ProfileGap[] | null>(null);
  // Extracted into a callback so the failure state's 다시 시도 has something real to call —
  // a retry button wired to nothing is a dead button.
  const load = useCallback(() => {
    // An entry with no bid (a truncated link) has nothing to re-read: same fact as zero rows,
    // same remedy — leave. Never a retry that would run the same early return again.
    if (!bid) { setNotFound(true); return; }
    setErr(false);
    setNotFound(false);
    fetchRunReportOrNull(bid)
      .then((r) => { if (r) setReport(r); else setNotFound(true); })
      .catch((e) => { console.warn('[o-report] run report:', e?.message ?? e); setErr(true); });
    fetchRunStandings(bid).then(setStandings).catch(() => {});
    // 실패 시 loaded 를 세우지 않는다 — 섹션은 조용히 없는 채로 남는다 (거짓 0 금지)
    setEarning(null);
    setEarningLoaded(false);
    fetchRunEarning(bid).then((e) => { setEarning(e); setEarningLoaded(true); }).catch(() => {});
    // 내가 이 러닝에 남긴 후기 — 없으면 null(=사실), 못 읽으면 known을 세우지 않는다(=모름).
    setMyReview(null);
    setMyReviewKnown(false);
    readMyReview(bid).then((r) => { if (r !== undefined) { setMyReview(r); setMyReviewKnown(true); } }).catch(() => {});
  }, [bid]);
  useEffect(() => { load(); }, [load]);
  // 두 팝을 '같은' effect에서 함께 부른다. 게이트는 각자의 모듈 Set이고 각자 내놓을 게 있을 때만
  // 소비하므로, 재방문 때 둘 다 조용해진다 — 한쪽만 소비된 어정쩡한 상태가 생기지 않는다.
  // 코스가 없는 러닝(routeId null)도 완주 도장은 찍힌다 → 패치 팝만 건너뛴다.
  // 실패는 조용한 부재로: 축하가 못 뜨는 편이 화면이 거짓을 말하는 것보다 낫다 (벽에는 남는다).
  useEffect(() => {
    if (!bid || !report || report.run?.endReason !== 'completed') return;
    const routeId = report.routeId;
    Promise.all([
      routeId ? fetchPatchPop(bid, routeId).catch(() => null) : Promise.resolve(null),
      fetchStampPop(bid).catch(() => [] as StampInfo[]),
    ]).then(([patch, stamps]) => {
      if (!patch && stamps.length === 0) return; // 둘 다 비면 오버레이 자체가 마운트되지 않는다
      setHaul({ patch, stamps });
      haptic('success');
    }).catch(() => {});
  }, [bid, report]);

  // ═══ 프로필 빈칸 넛지 — 첫 러닝 리포트에서만 읽는다 (랩 ①, Sean 콘솔 판정 #18) ═══
  // ruling #3 의 조건은 "첫 러닝 **후**"이고, 랩 ①은 그걸 "첫 러닝 리포트의 맨 아래"로 그린다.
  // `standings.nth` 가 그 사실을 이미 들고 있다 — 완주한 러닝을 시각 순으로 센 이 러닝의 번호
  // (api.ts fetchRunStandings). 그래서 새 판정용 읽기를 만들지 않았고, nth 가 1일 때만
  // 빈칸 읽기가 나간다 — 나머지 모든 리포트 진입에서는 요청 자체가 없다.
  // standings 가 못 왔으면(=null) 아무것도 하지 않는다: 첫 러닝인지 **모르는** 상태에서 물을 수 없다.
  useEffect(() => {
    if (standings?.nth !== 1) return;
    fetchProfileGaps().then(setProfileGaps)
      .catch((e) => console.warn('[o-report] gaps:', e?.message ?? e)); // 실패 = null 유지 = 블록 없음
  }, [standings]);

  // 인증샷은 전용 스튜디오(/shot/[bid])로 — 리포트 상단 인라인 카드 은퇴 (2026-07-28)
  const shotAuto = useRef(false);
  useEffect(() => {
    if (shot === '1' && bid && !shotAuto.current) {
      shotAuto.current = true;
      router.push(`/shot/${bid}`);
    }
  }, [shot, bid]);

  const run = report?.run ?? null;
  const reason = run?.endReason ? REASON[run.endReason] : null;
  // ═══════ 멈춘 러닝 — 이 화면의 두 번째 모양 (lab B②, Sean 2026-08-24) ═══════
  // Gated on the SERVER's own end reason, never on display vocabulary. `null` is not a stop:
  // a run row with no end_reason has not ended, and treating unknown as "stopped" would hoist an
  // empty audit block and rename the frame's one saturated element on a live run.
  const stopped = !!run?.endReason && run.endReason !== 'completed';
  // `rating` is nullable in the table (0001_init.sql:255) even though owner/review.tsx never
  // writes a null. Pulled out as its own const so the 1..5 clamp below is a plain number check.
  const myRating = myReview && myReview.rating != null && myReview.rating >= 1 && myReview.rating <= 5
    ? myReview.rating : null;
  const kmPct = run && report ? Math.min(100, Math.round((run.actualKm / report.plannedKm) * 100)) : 0;
  const pacePct = run?.paceSecPerKm && report
    ? Math.min(100, Math.round((targetPaceSec(report.paceLabel) / run.paceSecPerKm) * 100))
    : null;
  const bList = badges(standings);
  // Recomputed on EVERY RENDER — and that is all it is. The 2-hour floor and the date strip are
  // relative to NOW, so a re-render after a boundary drops the offer; but this screen runs no
  // interval, no useFocusEffect and holds no time-varying state, so a report left open simply
  // keeps the value it last rendered with. (The old comment promised the stronger property —
  // "must stop promising a slot it can no longer fill" — that nothing here implements. The
  // backstop is real and lives one screen over: request.tsx's mount effect nulls any draft ISO
  // inside the notice floor and re-picks.)
  const nextWeekCand = report ? resolveNextWeek(report.scheduledAtIso) : null;

  // ═══ The named runner has to be ABLE to take that slot ═══
  // resolveNextWeek only mirrors request.tsx's DISPLAY rules (notice floor, strip, slot grid). It
  // knows nothing about the runner this panel also prefills, and request.tsx never re-validates an
  // externally supplied ISO against that runner's availability — so a runner who narrowed to
  // weekends got a weekday hold and the booking parked in runner_pending for someone who
  // structurally could not accept it. runner-profile/[id].tsx, the only other external writer of
  // scheduledAtIso, calls checkSlot() first; so does this now.
  //   null = not answered yet (or the check failed) — the panel falls back to the timeless copy
  //   rather than promise a time we could not verify. Unknown is not yes.
  const [slotOk, setSlotOk] = useState<boolean | null>(null);
  const candIso = nextWeekCand?.iso ?? null;
  const runnerId = report?.runnerProfileId ?? null;
  const plannedKm = report?.plannedKm ?? null;
  useEffect(() => {
    setSlotOk(null);
    if (!candIso || !runnerId || plannedKm == null) return;
    let alive = true;
    // Same duration the hold will ask for (request.tsx slotAllowed: km × 8 + 25 min buffer) —
    // checking 60 minutes and booking 85 would pass a check the booking then fails.
    const end = new Date(Date.parse(candIso) + (plannedKm * 8 + 25) * 60_000).toISOString();
    checkSlot(runnerId, candIso, end)
      .then((ok) => { if (alive) setSlotOk(ok); })
      .catch(() => { if (alive) setSlotOk(null); }); // failure stays unknown, never a yes
    return () => { alive = false; };
  }, [candIso, runnerId, plannedKm]);

  // What the panel is allowed to say. No runner → the display rules are the whole contract.
  // A stopped run never names a time: B② demotes 재예약 to a quiet row whose copy is the timeless
  // one, and rebook() reads this same value — so the row and the prefill cannot disagree.
  const nextWeek = !stopped && nextWeekCand && (runnerId == null || slotOk === true) ? nextWeekCand : null;

  // 재예약 — same prefill as before, plus the resolved time when (and only when) we have one.
  const rebook = () => {
    if (!report) return;
    draft.km = report.plannedKm;
    draft.pace = report.paceLabel;
    if (report.routeId) draft.routeId = report.routeId;
    draft.preferredRunnerId = report.runnerProfileId;
    draft.preferredRunnerName = report.runnerName;
    if (nextWeek) {
      draft.scheduledAtIso = nextWeek.iso;
      draft.timeLabel = nextWeek.timeLabel;
      // request.tsx's mount effect calls pickEarliest() when this flag is set, which would replace
      // the slot this panel just named. The panel promised a time; clear the flag that overrides it.
      draft.autoEarliest = false;
    } else {
      draft.scheduledAtIso = null;
      draft.timeLabel = '시간을 선택해주세요';
    }
    router.push('/owner/request');
  };

  // 별점 — the stars are the affordance, the review screen is where it is written. `n` is
  // pre-selected there; 0 means "opened without picking one" and review.tsx still refuses submit.
  const openReview = (n: number) => {
    if (!report?.runnerProfileId || !bid) return;
    router.push({
      pathname: '/owner/review',
      params: {
        bid, rid: report.runnerProfileId, rname: report.runnerName ?? '러너',
        ...(n > 0 ? { stars: String(n) } : {}),
      },
    });
  };

  const share = async () => {
    if (!report || !run) return;
    const bLine = bList.filter((b) => b.includes('역대') || b.includes('TOP')).join(' · ');
    try {
      await Share.share({
        message:
          `${report.dogName}의 ${run.actualKm}km 러닝 완주!\n` +
          `${fmtDur(run.durationSec)} · 페이스 ${fmtPace(run.paceSecPerKm)}/km\n` +
          `${report.routeName}${report.runnerName ? ` · ${report.runnerName} 러너와 함께` : ''}` +
          (bLine ? `\n${bLine}` : '') +
          `\n\n반려견 피트니스, 도그스하이`,
      });
    } catch { /* 사용자 취소 */ }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56 }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          {/* Chrome title, not the display moment — plain 900 ink, the grammar request.tsx and
              review.tsx already use. The screen's ONE Black Han Sans is the run title below. */}
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>러닝 리포트</Text>
          {run ? (
            <Pressable onPress={share} style={s.backBtn}><Text style={{ fontSize: 17 }}>↗</Text></Pressable>
          ) : <View style={{ width: 40 }} />}
        </Row>

        {/* Failure: a reversible fact, so it gets a retry rather than a door out. */}
        {err && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: paper.critical }}>기록을 불러오지 못했어요</Text>
            <PaperBtn label="다시 시도" variant="secondary" style={{ alignSelf: 'stretch', marginTop: 14 }} onPress={load} />
          </View>
        )}
        {/* Not found: pressing again returns the same zero rows, so the one action is the exit —
            and it is role-aware (homePath), because this owner screen is reachable by a runner. */}
        {notFound && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>이 러닝을 찾을 수 없어요</Text>
            <PaperBtn label="홈으로" variant="secondary" style={{ alignSelf: 'stretch', marginTop: 14 }}
              onPress={() => router.replace(homePath())} />
          </View>
        )}
        {!err && !notFound && !report && (
          <View style={{ paddingHorizontal: 12, marginTop: 14, gap: 12 }}>
            <Skeleton width="100%" height={210} radius={0} />
            <Skeleton width="100%" height={90} />
            <Skeleton width="70%" height={20} />
          </View>
        )}

        {report && !run && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>
              {STATUS_LABEL[report.status] ?? '진행 상황 확인 중'}
            </Text>
            <Text style={[s.emptyText, { marginTop: 6 }]}>러닝이 끝나면 여기서 기록을 볼 수 있어요</Text>
            <PaperBtn label="내 일정에서 보기 ›" variant="secondary" style={{ alignSelf: 'stretch', marginTop: 14 }}
              onPress={() => router.replace('/owner/schedule')} />
          </View>
        )}

        {report && run && (
          <>
            {/* ══════ ① 러닝 경로 (실트레이스) — §E frame 7 opens on the map ══════
                [2026-08-19 · RULING #11·12·13, lab 14a/14b] The dark full-bleed hero that used to
                sit above this is RETIRED. It carried the same run twice: 50.5pt actualKm here and
                the 목표 달성 bar below, plus a 완주 FINISHER stamp saying what the title now says in
                words. 14a puts the map first and the run's three numbers under a display title;
                keeping both meant two heroes and two printings of one fact. Nothing real was
                dropped — the photo backdrop is the photo grid, 계획 거리 is the 목표 달성 row, and
                the PR badges moved down into the paper-world chip grammar. */}
            {run.trace.length > 1 && (() => {
              const maps = getNaverMap(); // 네이버 지도 (2026-07-29)
              if (maps) {
                const lats = run.trace.map((p) => p.lat);
                const lngs = run.trace.map((p) => p.lng);
                const latDelta = Math.max((Math.max(...lats) - Math.min(...lats)) * 1.4, 0.004);
                const camera = {
                  latitude: (Math.min(...lats) + Math.max(...lats)) / 2,
                  longitude: (Math.min(...lngs) + Math.max(...lngs)) / 2,
                  // 바운즈 → 네이버 줌 근사: zoom = log2(360/latΔ), 10~17 클램프
                  zoom: Math.min(17, Math.max(10, Math.log2(360 / latDelta))),
                };
                return (
                  <View style={{ height: 190, backgroundColor: '#fff' }}>
                    <maps.NaverMapView
                      style={{ flex: 1 }}
                      camera={camera}
                      isShowLocationButton={false}
                      isShowCompass={false}
                      isShowScaleBar={false}
                      isShowZoomControls={false}
                      isScrollGesturesEnabled={false}
                      isZoomGesturesEnabled={false}
                      isTiltGesturesEnabled={false}
                      isRotateGesturesEnabled={false}
                    >
                      <maps.NaverMapPathOverlay
                        coords={smoothTrace(run.trace.map((p) => ({ latitude: p.lat, longitude: p.lng })))}
                        color={colors.voltDeep}
                        width={5}
                        outlineWidth={2}
                        outlineColor="#ffffff"
                      />
                    </maps.NaverMapView>
                  </View>
                );
              }
              return (
                <View style={{ backgroundColor: '#0e150f', alignItems: 'center', paddingVertical: 12 }}>
                  <HeatTrace points={traceToBox(run.trace)} width={W - 60} height={140} />
                  <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 6 }}>실제 GPS 경로 · 지도 배경은 새 빌드에서</Text>
                </View>
              );
            })()}

            {/* ══════ ② 타이틀 + ③ 숫자 셋 (14a) ══════ */}
            <View style={s.head}>
              {/* [시뮬 실측 2026-08-11] 두 자식 모두 폭 예산이 없어, 종료 사유 칩이 코스명 위로
                  올라타 '서울숲 숲길 3km'가 잘렸다. 메타 줄은 남는 폭만 갖고 한 줄로 접고(넘치면
                  ellipsize), 칩은 자기 크기를 지킨다 — 칩이 말하는 건 사유이고, 사유는 잘리면 안 된다. */}
              <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                <Text style={{ fontSize: 14, color: paper.dim, flex: 1, minWidth: 0 }} numberOfLines={1}>
                  {report.when} · {report.routeName}
                </Text>
                {reason && run.endReason !== 'completed' && (
                  <View style={[s.reasonChip, { backgroundColor: reason.bg, flexShrink: 0 }]}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: reason.color }}>{reason.label}</Text>
                  </View>
                )}
              </Row>
              {/* The screen's ONE Black Han Sans. '완주' is a claim, so it is spoken only when the
                  server says the run ended completed — an early-ended run gets the same title
                  without it, and the chip above plus 왜 멈췄는지 below carry the reason. */}
              <Text style={[s.headTitle, df]}>
                {report.dogName}, {run.actualKm}km{run.endReason === 'completed' ? ' 완주' : ''}
              </Text>
              {/* 숫자 셋 — Oswald. [BUG A] 어센더가 잘리므로 lineHeight 명시: 27 × 1.22 = 33 */}
              <Row style={{ gap: 22, marginTop: 12, alignItems: 'flex-start' }}>
                <ReportStat nf={nf} value={String(run.actualKm)} unit="km" label="거리" />
                <ReportStat nf={nf} value={fmtDur(run.durationSec)} label="러닝 시간" />
                <ReportStat nf={nf} value={fmtPace(run.paceSecPerKm)} label="평균 페이스 /km" />
              </Row>
              {/* 개인 기록 배지 — real standings rows. On the white canvas they reuse the 도장 칩
                  grammar (코랄 워시 · 샤프 코너) instead of the retired hero's volt pill: the
                  frame's one saturated element is the 재예약 패널. */}
              {bList.length > 0 && (
                <Row style={{ gap: 6, marginTop: 12, flexWrap: 'wrap' }}>
                  {bList.map((b) => (
                    <View key={b} style={s.stampChip}>
                      <Text style={{ fontSize: 14, fontWeight: '900', color: paper.actionInk }}>{b}</Text>
                    </View>
                  ))}
                </Row>
              )}
            </View>

            {/* ══════ ③b 멈춘 이유는 숫자 바로 아래 (lab B②) ══════
                Under G1 the owner pays for a welfare stop, which makes the owner the auditor of
                the abort — so the audit material is not allowed to be the last block on a very
                long screen. Same block, same fields, moved. */}
            {stopped && (
              run.endReason === 'dog_condition'
                ? <StopReasonSection run={run} reason={reason} plannedKm={report.plannedKm} />
                : <RunnerNoteSection run={run} reason={reason} />
            )}

            {/* ══════ ④ 사진 (14b) — 엣지-투-엣지 ══════ */}
            {run.photos.length > 0 ? (
              <View style={{ backgroundColor: '#fff', flexDirection: 'row', flexWrap: 'wrap', gap: 2 }}>
                {run.photos.map((url) => (
                  /* [0064] 러닝 사진은 프라이빗 media 경로 — 서명 URL로 렌더 */
                  <MediaImage key={url} source={url} style={{ width: TILE, height: TILE, backgroundColor: '#DCD6C4' }} />
                ))}
              </View>
            ) : (
              /* [정직 배치 2.5 · 감사 #31] 유령 타일 3개 은퇴 — 채워질 자리인 척하는 빈 액자였다.
                 바디캠 하이라이트도 파이프라인이 없으므로 약속에서 뺀다. 끝난 러닝의 사실은 과거형 한 줄. */
              <View style={{ backgroundColor: '#fff', paddingHorizontal: 20, paddingTop: 4, paddingBottom: 14 }}>
                <Text style={{ fontSize: 15, fontWeight: '700', color: paper.ink, textAlign: 'center' }}>
                  이번 러닝은 사진이 없어요
                </Text>
                <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 3 }}>
                  러너가 러닝 중 남긴 사진이 있으면 여기에 표시돼요
                </Text>
              </View>
            )}

            {/* ══════ ④b 별점 — 세 상태, 절대 둘이 아니다 (lab B①) ══════
                The row is rendered ONLY once the read has answered. While it is in flight, or if
                it failed, this slot draws NOTHING: a hollow star row says "you have not reviewed
                yet", and "I could not check" is a different fact. Row present → what was actually
                written, with no edit affordance, because `unique (booking_id, author_id,
                target_kind)` refuses a second one. Row absent → today's affordance, unchanged:
                tapping star n opens /owner/review with n pre-selected and the write still happens
                there behind 후기 등록. */}
            {report.status === 'completed' && report.runnerProfileId && myReviewKnown && (
              myReview ? (
                <View style={s.writtenReview}>
                  <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                    {myRating != null ? (
                      <Text style={s.writtenStars} accessibilityLabel={`내가 남긴 별점 ${myRating}점`}>
                        {'★'.repeat(myRating)}
                        <Text style={s.writtenStarsOff}>{'★'.repeat(5 - myRating)}</Text>
                      </Text>
                    ) : (
                      /* rating is nullable in the table; a row without one is a review with no
                         score, not a zero-star review. Say what is there and draw no stars. */
                      <Text style={s.writtenNoRating}>별점 없이 남긴 후기예요</Text>
                    )}
                    {fmtMonthDay(myReview.createdAt) && (
                      <Text style={{ fontSize: 14, color: paper.dim }}>{fmtMonthDay(myReview.createdAt)} 등록</Text>
                    )}
                  </Row>
                  {myReview.tags.length > 0 && (
                    <Row style={{ gap: 6, marginTop: 9, flexWrap: 'wrap' }}>
                      {myReview.tags.map((t) => (
                        <View key={t} style={s.reviewTag}>
                          <Text style={{ fontSize: 14, fontWeight: '800', color: paper.actionInk }}>{t}</Text>
                        </View>
                      ))}
                    </Row>
                  )}
                  {/* 「프로필에 반영됐어요」 is only true for a public review — a platform_only one
                      is deliberately invisible on the runner's page, so it gets its own sentence. */}
                  <Text style={{ fontSize: 14, lineHeight: 20, color: paper.dim, marginTop: 9 }}>
                    후기는 러닝당 한 번만 남길 수 있어요 — {myReview.visibility === 'public'
                      ? `${report.runnerName ?? '러너'} 러너 프로필에 반영됐어요`
                      : '도그스하이 팀에게만 전달됐어요'}
                  </Text>
                </View>
              ) : (
                <View style={s.starsRow}>
                  <Row>
                    {[1, 2, 3, 4, 5].map((n) => (
                      <Pressable
                        key={n}
                        onPress={() => { haptic('light'); openReview(n); }}
                        hitSlop={4}
                        style={s.star}
                        accessibilityRole="button"
                        accessibilityLabel={`별점 ${n}점으로 후기 남기기`}
                      >
                        <Text style={s.starGlyph}>☆</Text>
                      </Pressable>
                    ))}
                  </Row>
                  <Pressable onPress={() => openReview(0)} hitSlop={8} accessibilityRole="button" accessibilityLabel="별점 남기기">
                    <Text style={s.starLabel}>별점 남기기 ›</Text>
                  </Pressable>
                </View>
              )
            )}

            {/* ══════ ⑤ 재예약 넛지 (RULING #11) — the frame's ONE saturated element ══════
                Two shapes, and which one you get is a fact, not a style choice. resolveNextWeek()
                either produced a slot owner/request.tsx can receive and display — in which case
                the panel names it and prefills it — or it did not, in which case the panel says
                the timeless thing and hands off with 시간을 선택해주세요. It never promises a time
                it did not resolve. White on paper.action is measured 4.84:1 at all sizes (theme.ts),
                so the label sits directly on the fill; paper.wash is the tinted subline. */}
            {/* [2026-08-24 · lab B②, Sean's yes] On a STOPPED run the saturated element moves.
                RULING #11 made 재예약 the frame's one climax on the assumption that the run
                happened; G1 changed what this state means — the owner now pays for a welfare stop
                and is therefore its auditor, and the loudest thing on that screen should not be
                "book the same thing again". 안심 센터 (/safety) is a real route, reached the same
                way from owner/pay.tsx:300 and owner/meetup.tsx. 재예약 stays, quietly, one row
                down — no exit is removed, and `nextWeek` is already forced null above so the
                quiet row and the prefill say the same thing. */}
            {stopped ? (
              <>
                <Pressable
                  onPress={() => router.push('/safety')}
                  style={({ pressed }) => [s.rebook, pressed && { backgroundColor: paper.actionPressed }]}
                  accessibilityRole="button"
                  accessibilityLabel="안심 센터 열기"
                >
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={s.rebookTitle}>안심 센터 열기</Text>
                    <Text style={s.rebookSub} numberOfLines={2}>
                      {run.endReason === 'dog_condition'
                        ? '아이 상태가 이상하면 여기서 바로 도와드려요'
                        : '이 러닝에 대해 도움이 필요하면 여기서 문의할 수 있어요'}
                    </Text>
                  </View>
                  <Text style={s.rebookChev}>›</Text>
                </Pressable>
                <Pressable
                  onPress={rebook}
                  style={({ pressed }) => [s.linkRow, pressed && { backgroundColor: paper.wash }]}
                  accessibilityRole="button"
                  accessibilityLabel="이대로 다시 예약"
                >
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={s.linkRowLabel}>이대로 다시 예약</Text>
                    <Text style={s.linkRowSub} numberOfLines={2}>
                      같은 코스·거리{report.runnerName ? ` · ${report.runnerName} 러너 지명` : ''}
                    </Text>
                  </View>
                  <Text style={s.linkRowChev}>›</Text>
                </Pressable>
              </>
            ) : (
              <Pressable
                onPress={rebook}
                style={({ pressed }) => [s.rebook, pressed && { backgroundColor: paper.actionPressed }]}
                accessibilityRole="button"
                accessibilityLabel={nextWeek ? `다음 주 같은 시간 예약 ${nextWeek.whenLabel}` : '이대로 다시 예약'}
              >
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Text style={s.rebookTitle}>{nextWeek ? '다음 주 같은 시간 예약' : '이대로 다시 예약'}</Text>
                  <Text style={s.rebookSub} numberOfLines={2}>
                    {nextWeek
                      ? `${report.runnerName ? `${report.runnerName} 러너 · ` : ''}${report.plannedKm}km · ${nextWeek.whenLabel}`
                      : `같은 코스·거리${report.runnerName ? ` · ${report.runnerName} 러너 지명` : ''} — 시간만 고르면 돼요`}
                  </Text>
                </View>
                <Text style={s.rebookChev}>›</Text>
              </Pressable>
            )}

            {/* ══════ ⑥ 공유 넛지 (RULING #12) — 샷 스튜디오가 넛지의 얼굴 ══════
                /shot/[bid] is the studio that renders the real card (4 skins) and hands it to the
                OS share sheet / Instagram Stories / the photo library. The header ↗ stays as the
                text-only share; this row is the image one. */}
            <Pressable
              onPress={() => bid && router.push(`/shot/${bid}`)}
              style={({ pressed }) => [s.linkRow, pressed && { backgroundColor: paper.wash }]}
              accessibilityRole="button"
            >
              <Text style={s.linkRowLabel}>이 러닝 카드 공유하기</Text>
              <Text style={s.linkRowChev}>›</Text>
            </Pressable>

            {/* ══════ ⑦ 결제 — 한 줄 ══════
                [2026-08-13] This block used to print `bookings.total_price` under the label
                결제 금액 — the FROZEN PLANNED total minted at booking time, not what was
                charged. compute_owner_charge (0084 §A) bills `least(actual, km)` for every
                reason except owner-caused ends, and `runner_personal` drops the base and
                addons entirely, so any early-ended run showed a number the owner was never
                billed, on the one screen they open to check what a run cost. Beneath it sat
                "조기 종료 시 정산 조정은 고객센터를 통해 처리돼요" — naming a support process
                that does not exist anywhere in this app (settle-time adjustment is automatic).
                Two assertions, neither backed; found by the ⑩ class sweep
                (docs/decisions/cancel-fee-runner-share.md).
                The fix is not a corrected number here. §0-bis is explicit that the post-run
                moment is the RECORD CARD — the dog, never the charge — and that money lives in
                exactly two modes, on demand and on exception. So the charge leaves this screen
                and the receipt stays one tap away, which is what the doctrine actually asks
                for. /payments is the on-demand half and reads the real `payments` rows.
                [2026-08-19 §E] The lab's "계좌이체 안내 ›" is NOT buildable honestly: there is no
                bank account anywhere in this codebase (the only 계좌 strings exclude 가상계좌 as a
                Toss method or say a runner has none registered), and an account number is a
                credential value — Sean-only per CLAUDE.md. The row keeps §E's shape and points
                at the screen that has real rows. */}
            <Pressable
              onPress={() => router.push({
                pathname: '/payments',
                params: { returnTo: `/owner/report?bid=${bid ?? ''}`, returnLabel: '러닝 리포트로' },
              })}
              style={({ pressed }) => [s.linkRow, pressed && { backgroundColor: paper.wash }]}
              accessibilityRole="button"
            >
              {/* [2026-08-24 · lab B①] The row absorbs its own note. It used to be a row plus a
                  loose sentence under it — two elements carrying one fact, and the sentence read
                  as a stray caption. Same words, same route, one block. */}
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.linkRowQuiet}>결제</Text>
                <Text style={s.linkRowSub}>실제 청구된 금액과 영수증은 결제 내역에 있어요</Text>
              </View>
              <Text style={[s.linkRowAction, { flexShrink: 0, marginLeft: 10 }]}>내역 ›</Text>
            </Pressable>

            {/* ---------- 하이 포인트 적립 (리워드 ①) — 이 러닝이 벌어들인 것 ----------
                영수증이지 팡파레가 아니다: 애니메이션 없음 (축하는 패치 팝 하나뿐).
                원장 행이 0이면 fetchRunEarning 이 null 을 주고 섹션 자체가 사라진다 —
                조기 종료 러닝은 서버가 한 줄도 안 쓰므로 '적립 0원'이 아니라 '없는 이야기'다.
                endReason 게이트는 서버 게이트(v_is_full)의 클라 거울. */}
            {earningLoaded && earning && run.endReason === 'completed' && (
              <View style={s.earnSection}>
                <Text style={s.earnKicker}>하이 포인트 적립</Text>
                <Row style={{ alignItems: 'baseline', marginTop: 4 }}>
                  <Text style={[s.earnTotal, nf]}>{earning.total > 0 ? '+' : ''}{earning.total.toLocaleString()}</Text>
                  <Text style={s.earnUnit}> 포인트</Text>
                </Row>
                <View style={{ marginTop: 10 }}>
                  {earning.lines.map((l, i) => (
                    <Row key={`${l.reason}-${i}`} style={{ justifyContent: 'space-between', marginTop: i === 0 ? 0 : 5 }}>
                      <Text style={s.earnLabel}>{l.label}</Text>
                      <Text style={s.earnDelta}>{l.delta > 0 ? '+' : ''}{l.delta.toLocaleString()}</Text>
                    </Row>
                  ))}
                </View>
              </View>
            )}

            {/* ---------- 러닝 순간 스탬프 (응가 도장 등) ----------
                [2026-08-25 · Sean Q1, verbatim] "yeah running report (b) 1, but it shuold also include
                the water and poo etc stats as in the current version."
                NOTHING CHANGED HERE, and that is the finding. This block was never inside a state
                gate: `run.events.length > 0` is a PRESENCE check, not a state check, so the care
                counts already render on a STOPPED run (B②) exactly as on a completed one, and they
                are byte-identical to the pre-redesign screen. What dropped them was the LAB, not the
                code — enh-owner-records-lab.html draws 응가 ×1 · 물 ×2 in its 현재 frame (:888) and
                abbreviates them away in BOTH the ① and ② columns. Sean was reading the mock.
                So: do NOT "align" this block to those frames, and never gate it on `stopped`. The
                counts are care evidence, and the run that ended early is the one where an owner most
                needs to see whether the dog drank. Source is runs.events through
                fetchRunReportOrNull (api.ts:4236) — one select for every end reason, so a stop
                loses no rows; the four kinds here are the whole of RunEventKind (api.ts:2165). */}
            {run.events.length > 0 && (
              <View style={[s.section, { flexDirection: 'row', gap: 8, flexWrap: 'wrap' }]}>
                {(
                  [['poop', '응가'], ['snack', '간식'], ['water', '물'], ['photo', '사진']] as const
                ).map(([kind, label]) => {
                  const n = run.events.filter((e) => e.kind === kind).length;
                  if (n === 0) return null;
                  return (
                    <View key={kind} style={s.stampChip}>
                      <Text style={{ fontSize: 14.5, fontWeight: '900', color: paper.actionInk }}>{label} ×{n}</Text>
                    </View>
                  );
                })}
                <Text style={{ fontSize: 14, color: colors.dim, width: '100%', marginTop: 4 }}>
                  러너가 러닝 중 실시간으로 기록한 순간들이에요
                </Text>
              </View>
            )}

            {/* ---------- 목표 달성 / 기록 ----------
                [lab B②] A 68% on a stopped run reads as a grade for the dog, so the percentage is
                withdrawn for that state and replaced by the same two facts stated plainly. Nothing
                is hidden — 예정 and 실제 are both printed; only the ratio is refused. */}
            {stopped ? (
              <View style={s.section}>
                <Text style={s.sectionTitle}>기록</Text>
                <Text style={{ fontSize: 14, lineHeight: 20, color: paper.dim }}>
                  {/* [BUG A] Oswald 숫자는 lineHeight 명시 없이 어센더가 잘린다 — 16 × 1.25 = 20 */}
                  예정 {report.plannedKm}km 중 <Text style={[s.recordNum, nf]}>{run.actualKm}</Text>km에서 종료했어요 — 이 러닝은 목표 달성률을 계산하지 않아요.
                </Text>
              </View>
            ) : (
              <View style={s.section}>
                <Text style={s.sectionTitle}>목표 달성</Text>
                <GoalBar label="거리" pct={kmPct} detail={`${run.actualKm} / ${report.plannedKm}km`} />
                {pacePct != null && (
                  <GoalBar label="페이스" pct={pacePct} detail={`목표 ${fmtPace(targetPaceSec(report.paceLabel))} · 실제 ${fmtPace(run.paceSecPerKm)}`} />
                )}
              </View>
            )}

            {/* ---------- 러너 & 코스 ---------- */}
            <View style={s.section}>
              <Row style={{ gap: 12 }}>
                {/* [2026-08-24 · lab B②] bg was colors.green #5a7a3c — the last local copy of the
                    retired swamp/forest palette on this screen, the same class the file header
                    retired FOREST for. paper.ink, which is what the lab frames draw. */}
                <Monogram char={(report.runnerName ?? '러')[0]} bg={paper.ink} size={44} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>
                    {report.runnerName ?? '러너'} 러너
                  </Text>
                  <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>
                    {report.routeName}{report.routeArea ? ` · ${report.routeArea}` : ''}
                  </Text>
                </View>
                {/* [honesty audit 2026-08-11 · P1 #3] 신원인증 badge retired — it was stamped on
                    every runner unconditionally with no data source (meetup.tsx already retired
                    the same badge for the same reason, P1-6). The runners.identity_verified
                    column exists, but its current values originate from the bootstrap/seed
                    fabrication (see api.ts fetchMyRunnerCert note and the 0061 insert-seal
                    rationale), so binding it would still render a review that never happened.
                    Re-add bound to the real field once the 0062 application funnel is the only
                    writer and existing fabricated rows are cleaned. */}
              </Row>
            </View>

            {/* ---------- 러너 노트 (완주한 러닝의 메모) ----------
                On a STOPPED run this block — and 왜 멈췄는지 with it — is hoisted to directly under
                the numbers (lab B②); here it only serves a completed run that still carries a note. */}
            {!stopped && <RunnerNoteSection run={run} reason={reason} />}

            {/* ══════ 프로필 빈칸 넛지 — 랩 ①, 리포트의 맨 아래 (Sean 콘솔 판정 #18, 2026-08-25) ══════
                그의 말 그대로: **"approve on everything."** (콘솔 아티팩트 aad92054, 04:31:30Z ·
                docs/decisions/2026-08-25-console-rulings.md #18 — 번들 줄 "the profile-nudge lab
                (① recommended) … proceed as picked"). 정본은 docs/labs/profile-nudge-lab.html ①.
                이 자리는 ①이 그린 그 자리다 — 스크롤의 끝. ①의 약점("못 보고 나갈 수 있습니다")도
                그가 읽은 채로 고른 것이고, 강점은 세 줄이 가리키는 화면을 방금 다 봤다는 것이다.
                ⚠ 이 넛지는 **홈의 ② 행을 대체한다** — owner/home.tsx 의 그 자리에 같은 도장이 있다.
                ⚠ 각 줄의 도착지는 실제 라우트다: 사진·백신 → /owner/dog(사진 픽커 + 백신 카탈로그가
                   그 화면에 있다), 현관 상세 → /owner/addresses(기본 주소의 픽업 메모 편집기).
                   죽은 버튼 없음.
                ⚠ 코랄은 위의 재예약 패널이 갖는다 — 이 블록은 잉크다 (화면당 코랄 하나). */}
            {profileGaps && (
              <ProfileGaps
                gaps={profileGaps}
                dogName={report.dogName}
                onOpen={(gap) => router.push(gap === 'doorDetail' ? '/owner/addresses' : '/owner/dog')}
              />
            )}

            {/* [2026-08-19 §E] The screen used to END here, with a 결제 block and three stacked
                CTAs. All four moved UP into the nudge stack (⑤⑥⑦): 이대로 다시 예약 became the
                coral 재예약 panel, 인증샷 만들기 became the 카드 공유 row (same /shot/[bid] route —
                one entry, not two), 후기 남기기 became the ★ row, and 결제 내역 보기 became the
                quiet 결제 row. No exit was removed; the 결제 provenance travelled with its row. */}
          </>
        )}
      </ScrollView>

      {/* ---------- 오늘의 수확 — 패치 승급 + 새 도장 병합 세리머니 (탭 = 닫기) ---------- */}
      {haul && (
        <HaulOverlay
          patch={haul.patch}
          stamps={haul.stamps}
          nf={nf}
          onClose={() => setHaul(null)}
          onCollection={() => { setHaul(null); router.push('/cards'); }}
        />
      )}
    </View>
  );
}

// 승급 어휘 — 문장 안에 들어가므로 느낌표 없이 ('실버 승급 · 서울숲 순환 코스 ×5')
const POP_TITLE: Record<string, string> = { basic: '패치 획득', silver: '실버 승급', gold: '골드 승급', master: '코스 마스터' };

// ═══════ Ⓒ② 오늘의 수확 — 오버레이 하나 · 세계 하나 · 닫기 하나 ═══════
// 배경은 나이트 라일락을 0.94로 덮는다. 예전 rgba(10,16,10,.72)는 새 적립 스트립과 응가 칩이
// 그대로 읽혀 '축하 위에 영수증'이 겹쳐 보였다 (랩이 실측해 잡은 결함) — 포레스트 잔재도 함께 라일락으로.
// 세 가지 정직한 모양으로 degrade한다: 패치만 · 도장만 · 둘 다. 아무것도 없으면 마운트조차 안 된다.
const STAMP_INK = '#B9AEF5';    // 나이트 위 도장 잉크 — 벽의 #4A3DA8은 어두운 배경에서 사라진다
const STAMP_FIRST = '#FF9C82';  // 첫-family 외곽링·도트 (코랄은 링이지 절대 글자가 아니다)
const HAUL_DIM = '#A9A3C8';     // 보조 텍스트 (#1C1837 위 7.09:1 — 실측)
// 한 줄에 놓을 도장 수. 셀 100 + gap 12 → 3칸 324px가 들어가려면 가용폭(W−52) ≥ 324, 즉 W ≥ 376.
// 375dp(가용 323)에서 1px 넘쳐 2+1로 감기던 것을 폭으로 가른다 — 도장 크기는 절대 줄이지 않는다.
const HAUL_CAP = W >= 377 ? 3 : 2;

// 도장 한 개 — 벽과 같은 문법(숫자+한글, 링 수가 사다리, 첫-family만 코랄 링+도트)의 나이트 버전
function StampDisc({ info, nf }: { info: StampInfo; nf: TextStyle | null }) {
  const D = 92;
  const edge = info.coral ? STAMP_FIRST : STAMP_INK;
  return (
    <View style={[s.disc, { width: D, height: D, borderRadius: D / 2, borderColor: edge }]}>
      {info.rings >= 2 && (
        <View style={[s.discRing, { left: 5, right: 5, top: 5, bottom: 5, borderRadius: (D - 10) / 2, borderColor: edge, opacity: 0.85 }]} />
      )}
      {info.rings >= 3 && (
        <View style={[s.discRing, { left: -6, right: -6, top: -6, bottom: -6, borderRadius: (D + 12) / 2, borderColor: STAMP_INK, opacity: 0.55 }]} />
      )}
      {info.coral && <View style={[s.discDot, { left: (D - 5) / 2 - 4 }]} />}
      {/* [BUG A] Oswald 숫자는 lineHeight 명시 없이 어센더가 잘린다 — 27 × 1.2 = 33 */}
      <Text style={[{ fontSize: 27, lineHeight: 33, fontWeight: '600', color: STAMP_INK }, nf]}>{info.num}</Text>
      <Text style={{ fontSize: 15, lineHeight: 19, fontWeight: '800', color: STAMP_INK, marginTop: 1 }}>{info.word}</Text>
    </View>
  );
}

function HaulOverlay({ patch, stamps, nf, onClose, onCollection }: {
  patch: CoursePatch | null; stamps: StampInfo[]; nf: TextStyle | null; onClose: () => void; onCollection: () => void;
}) {
  // 한 줄 상한(폭에 따라 3 또는 2). 넘치면 '외 N개'로 적고 도장을 줄이지 않는다.
  const shown = stamps.slice(0, HAUL_CAP);
  const more = stamps.length - shown.length;
  const kick = useRef(new Animated.Value(0)).current;
  const pa = useRef(new Animated.Value(0)).current;
  // 훅 수는 고정 — 상한이 3칸이라 값 3개를 항상 만든다 (조건부 훅 금지)
  const s0 = useRef(new Animated.Value(0)).current;
  const s1 = useRef(new Animated.Value(0)).current;
  const s2 = useRef(new Animated.Value(0)).current;
  const copy = useRef(new Animated.Value(0)).current;
  const slams = [s0, s1, s2];
  useEffect(() => {
    const steps: Animated.CompositeAnimation[] = [];
    // ① 패치가 먼저 스프링으로 박힌다 (오늘 쓰던 값 그대로 — friction 5 · tension 90)
    if (patch) steps.push(Animated.spring(pa, { toValue: 1, friction: 5, tension: 90, useNativeDriver: true }));
    // ② 도장이 차례로 내려찍힌다 — 영수증 실 스탬프의 커브 그대로, 80ms 간격
    if (shown.length > 0) {
      steps.push(Animated.stagger(80, shown.map((_, i) => Animated.timing(slams[i], {
        toValue: 1, duration: 340, easing: Easing.bezier(0.5, 0, 0.7, 0.35), useNativeDriver: true,
      }))));
    }
    // ③ 카피와 CTA가 마지막에 올라온다
    steps.push(Animated.timing(copy, { toValue: 1, duration: 320, useNativeDriver: true }));
    Animated.parallel([
      Animated.timing(kick, { toValue: 1, duration: 300, useNativeDriver: true }),
      Animated.sequence(steps),
    ]).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Pressable onPress={onClose} style={s.haulBack}>
      <Animated.Text style={[s.haulKicker, { opacity: kick }]}>DOGS HIGH · 오늘의 수확</Animated.Text>

      {patch && (
        <>
          {/* 패치는 자기 색(자수 오브젝트)을 그대로 지킨 채 여권의 나이트 배경 위에 앉는다 */}
          <Animated.View style={{
            alignItems: 'center',
            opacity: pa,
            transform: [
              { scale: pa.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] }) },
              { rotate: pa.interpolate({ inputRange: [0, 1], outputRange: ['-18deg', '-4deg'] }) },
            ],
          }}>
            <PatchBadge km={patch.km} name={patch.name} grade={patch.grade} size={132} />
          </Animated.View>
          <Animated.Text style={[s.haulPatchLine, { opacity: pa }]}>
            {POP_TITLE[patch.grade]} · {patch.name} {patch.count === 1 ? '첫 완주' : `×${patch.count}`}
          </Animated.Text>
        </>
      )}

      {patch && shown.length > 0 && <View style={s.haulPerf} />}

      {shown.length > 0 && (
        <View style={s.haulRow}>
          {shown.map((st, i) => (
            <Animated.View
              key={st.key}
              style={{
                // 셀 100 + gap 12 → 3칸 324 / 2칸 212. 오버레이 가용폭 = W − 좌우 패딩 52
                alignItems: 'center', width: 100,
                opacity: slams[i],
                transform: [
                  { scale: slams[i].interpolate({ inputRange: [0, 1], outputRange: [2.2, 1] }) },
                  // 착지 각도는 그 도장의 고정 기울기(api.ts angle) — 벽과 세리머니가 같은 손도장이어야 한다
                  { rotate: slams[i].interpolate({ inputRange: [0, 1], outputRange: ['-12deg', `${st.angle}deg`] }) },
                ],
              }}
            >
              <StampDisc info={st} nf={nf} />
              <Text style={s.haulCap}>{st.label}</Text>
            </Animated.View>
          ))}
        </View>
      )}

      <Animated.View style={{
        alignItems: 'center',
        opacity: copy,
        transform: [{ translateY: copy.interpolate({ inputRange: [0, 1], outputRange: [8, 0] }) }],
      }}>
        {more > 0 && <Text style={s.haulMore}>외 {more}개</Text>}
        {shown.length > 0 ? (
          <>
            <Text style={s.haulSub}>여권에 새 도장 {stamps.length}개가 찍혔어요</Text>
            {/* '지워지지 않아요'는 거짓이 될 수 있다 — 자랑 글 삭제·코스 비활성은 실제 감소 벡터다 (api.ts 계약 주석) */}
            <Text style={s.haulNote}>기록이 남아 있는 한 도장은 그대로예요</Text>
          </>
        ) : (
          <Text style={s.haulSub}>패치가 컬렉션에 들어갔어요</Text>
        )}
        <Pressable onPress={onCollection} style={s.haulCta}>
          <Text style={s.haulCtaText}>컬렉션 보기 ›</Text>
        </Pressable>
        <Text style={s.haulHint}>탭하면 닫혀요</Text>
      </Animated.View>
    </Pressable>
  );
}

// 숫자 셋 (14a). Oswald via nf — [BUG A] lineHeight must be explicit or the ascenders clip.
// The unit rides inside the value line so '5.1' and 'km' share one baseline, and the label under
// it holds the 14pt detail floor (it is not a letterspaced kicker, so it gets no exemption).
function ReportStat({ nf, value, unit, label }: { nf: TextStyle | null; value: string; unit?: string; label: string }) {
  return (
    <View>
      <Text style={[s.statValue, nf]}>
        {value}{unit ? <Text style={s.statUnit}>{unit}</Text> : null}
      </Text>
      <Text style={s.statLabel}>{label}</Text>
    </View>
  );
}

type RunFacts = NonNullable<RunReport['run']>;
type ReasonPaint = { label: string; color: string; bg: string; note?: string };

// ---------- 왜 멈췄는지 (컨디션 종료 전용) ----------
// G1 (docs/decisions/g1-abort-charge-basis.md) makes a welfare stop a REAL BILL, and both
// adversarial rounds flagged the same consequence: an owner who feels charged for a stopped run
// leans on the next runner to keep going. The agreed mitigation is copy, and this is it. Two jobs,
// and the second one is newer than the first:
//
//  ① Say plainly that stopping was right. Note the claim is about the DECISION, not about the
//     dog — we do not know the dog was unwell, and asserting a diagnosis we cannot see would be
//     the same fabrication this section exists to retire.
//  ② Carry enough for the owner to JUDGE the stop. Under G1 the owner pays, so the owner is now
//     the auditor of an abort — the fraud posture inverted the day the waive ended. That means the
//     runner's own words (real since 611f014) plus where it happened.
//
// [2026-08-24 · lab B②] Extracted from the screen body so the SAME block can be rendered in two
// places: hoisted directly under the numbers on a stopped run (audit material is not allowed
// below the fold), and left where it was on every other run. One block, two positions, zero copies.
function StopReasonSection({ run, reason, plannedKm }: { run: RunFacts; reason: ReasonPaint | null; plannedKm: number }) {
  return (
    <View style={s.section}>
      <Text style={s.sectionTitle}>왜 멈췄는지</Text>
      <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 21 }}>
        아이가 힘들어 보이면 멈추는 게 맞아요.
      </Text>
      <Text style={{ fontSize: 14.5, color: paper.dim, marginTop: 5, lineHeight: 20.5 }}>
        러너는 그렇게 하도록 안내받아요. 끝까지 달리는 것보다 아이 상태가 먼저예요.
      </Text>

      {run.conditionNote ? (
        <View style={{ marginTop: 13, borderLeftWidth: 2, borderLeftColor: paper.line, paddingLeft: 11 }}>
          <Text style={{ fontSize: 14, fontWeight: '800', color: paper.dim, marginBottom: 4 }}>
            러너가 본 것
          </Text>
          <Text style={{ fontSize: 15, color: paper.text, lineHeight: 21.5 }}>{run.conditionNote}</Text>
        </View>
      ) : (
        /* Loading ≠ empty ≠ absent (§7): the note is required at the stop, so a missing one is a
           real gap in the record — say so rather than rendering nothing. */
        <Text style={{ fontSize: 14, color: paper.dim, marginTop: 13, lineHeight: 20 }}>
          러너 메모가 기록되지 않았어요 — 안심 센터로 문의해주세요.
        </Text>
      )}

      <Text style={{ fontSize: 14, color: paper.dim, marginTop: 13, lineHeight: 20 }}>
        {run.actualKm}km 지점 · {fmtDur(run.durationSec)} 지나 종료했어요 (예정 {plannedKm}km)
      </Text>
      {reason?.note && (
        <Text style={{ fontSize: 14, color: reason.color, marginTop: 9, lineHeight: 19.5 }}>
          {reason.note}
        </Text>
      )}
    </View>
  );
}

// ---------- 러너 노트 (그 외 사유) ----------
function RunnerNoteSection({ run, reason }: { run: RunFacts; reason: ReasonPaint | null }) {
  if (!run.conditionNote && !reason?.note) return null;
  return (
    <View style={s.section}>
      <Text style={s.sectionTitle}>러너 노트</Text>
      {run.conditionNote && (
        <Text style={{ fontSize: 14.5, color: paper.text, lineHeight: 20.5 }}>{run.conditionNote}</Text>
      )}
      {reason?.note && (
        <Text style={{ fontSize: 14, color: reason.color, marginTop: run.conditionNote ? 8 : 0, lineHeight: 19.5 }}>
          {reason.note}
        </Text>
      )}
    </View>
  );
}

function GoalBar({ label, pct, detail }: { label: string; pct: number; detail: string }) {
  // 채워지는 모션 — 진행이 '벌어들인 것'처럼 (motion = meaning)
  const w = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(w, { toValue: pct, duration: 700, useNativeDriver: false }).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pct]);
  return (
    <View style={{ marginTop: 10 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Text style={{ fontSize: 14, fontWeight: '700', color: '#3d453d' }}>{label}</Text>
        <Text style={{ fontSize: 15, fontWeight: '900', color: pct >= 100 ? paper.readyDeep : paper.ink }}>{pct}%</Text>
      </Row>
      <View style={s.barTrack}>
        <Animated.View
          style={[
            s.barFill,
            { width: w.interpolate({ inputRange: [0, 100], outputRange: ['0%', '100%'] }) },
            pct >= 100 && { backgroundColor: '#7FA818' },
          ]}
        />
      </View>
      <Text style={{ fontSize: 14, color: colors.dim, marginTop: 4 }}>{detail}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  // §2 종이 크롬: 40×40 **정사각**, 캔버스 면, 1px 코랄 트림 (runner/meetup circleBtn 문법 —
  // 이름만 circle이고 모양은 사각이다). 종전 borderRadius 20 + 베이지 트림은 V4 잔재였다.
  backBtn: { width: 40, height: 40, borderRadius: 0, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  // ---------- ② 타이틀 + ③ 숫자 셋 (14a) — 흰 캔버스, 섹션 리듬은 s.section과 같다 ----------
  head: { backgroundColor: paper.canvas, paddingHorizontal: 12, paddingTop: 14, paddingBottom: 16, borderBottomWidth: 1, borderBottomColor: paper.line },
  headTitle: { fontSize: 27.5, fontWeight: '900', color: paper.ink, marginTop: 6 },
  statValue: { fontSize: 27, lineHeight: 33, fontWeight: '900', color: paper.ink }, // [BUG A] 27 × 1.22
  statUnit: { fontSize: 15, lineHeight: 33, fontWeight: '800', color: paper.dim },
  statLabel: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 1 },
  reasonChip: { borderRadius: 0, paddingVertical: 4, paddingHorizontal: 9 }, // §3b 상태 칩 = radius 0
  // ---------- ④b 별점 행 — 빈 별(☆) + 라벨. 채워진 상태는 이 화면이 알 수 없다 ----------
  starsRow: {
    backgroundColor: paper.canvas, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 12, paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  star: { paddingHorizontal: 4, paddingVertical: 7 }, // 32pt 글리프 + 패딩 ≈ 44pt 타깃
  starGlyph: { fontSize: 32, lineHeight: 38, color: paper.dim },
  starLabel: { fontSize: 15, fontWeight: '800', color: paper.ink },
  // ---------- ④b-written 이미 남긴 후기 — 어포던스가 아니라 기록이다 (누를 것이 없다) ----------
  writtenReview: {
    backgroundColor: paper.canvas, paddingHorizontal: 12, paddingVertical: 12,
    borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  // 채워진 별은 §8의 기록 골드. 빈 별은 뉴트럴 보더 색과 같은 값 — dim(#666)은 '꺼짐'이 아니라
  // '읽는 회색'이라 절반이 눌린 것처럼 보인다.
  writtenStars: { fontSize: 32, lineHeight: 38, letterSpacing: 2, color: colors.gold },
  writtenStarsOff: { color: '#EEEEEE' },
  writtenNoRating: { fontSize: 15, fontWeight: '800', color: paper.ink },
  reviewTag: { backgroundColor: paper.wash, borderRadius: 0, borderWidth: 1, borderColor: paper.line, paddingVertical: 7, paddingHorizontal: 13 },
  // ---------- ⑤ 재예약 넛지 — 이 프레임의 유일한 채도 (흰 라벨 4.84:1, 잉크 플레이트 불필요) ----------
  rebook: { backgroundColor: paper.action, flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 15, paddingVertical: 14 },
  rebookTitle: { fontSize: 19, lineHeight: 25, fontWeight: '900', color: '#fff' },
  rebookSub: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.wash, marginTop: 3 },
  rebookChev: { fontSize: 20, lineHeight: 25, color: paper.wash },
  // ---------- ⑥⑦ 행 문법 — 풀블리드 캔버스 + 코랄 헤어라인 (s.section과 같은 리듬) ----------
  linkRow: {
    backgroundColor: paper.canvas, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 12, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  linkRowLabel: { fontSize: 16, fontWeight: '800', color: paper.ink },
  linkRowSub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 2 },
  linkRowChev: { fontSize: 18, color: paper.actionInk },
  linkRowQuiet: { fontSize: 16, fontWeight: '600', color: paper.dim },
  linkRowAction: { fontSize: 14, fontWeight: '800', color: paper.actionInk },
  // 섹션 분할은 풀블리드 솔리드 코랄 1px — 이 선이 곧 브랜드 (§2 종이 법)
  section: { backgroundColor: paper.canvas, paddingHorizontal: 12, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: paper.line },
  // §3b 섹션 헤더는 앱 전체에서 하나의 문법: 20/800 잉크. 화면마다 크기를 달리 쓰지 않는다.
  sectionTitle: { fontSize: 20, fontWeight: '800', color: paper.ink, marginBottom: 6 },
  // 기록 줄 안의 실주행 km — Oswald. [BUG A] 16 × 1.25 = 20
  recordNum: { fontSize: 16, lineHeight: 20, fontWeight: '900', color: paper.ink },
  barTrack: { height: 8, borderRadius: 99, backgroundColor: '#EEEEEE', marginTop: 6, overflow: 'hidden' }, // 은퇴 팔레트 크림(#f0eee3) → 뉴트럴
  barFill: { height: 8, borderRadius: 99, backgroundColor: colors.volt },
  // 은퇴 팔레트(연두 워시)의 마지막 잔재 + 알약 코너. 코랄 워시 위 샤프 칩으로.
  stampChip: { backgroundColor: paper.wash, borderRadius: 0, paddingVertical: 7, paddingHorizontal: 13 },
  // ---------- 리워드 ① 적립 스트립 — 조용한 라일락 영수증 (섹션 리듬은 s.section과 동일) ----------
  // [2026-08-25 pale retirement] lilac.bg is white now, so this strip no longer reads as a tinted
  // band — it separates by its bottom hairline and its kicker alone. That is the ruling's intent
  // ("white backgrounds"), not an oversight: the token stays bound so the next ground ruling
  // reaches this strip too.
  earnSection: {
    backgroundColor: lilac.bg, paddingHorizontal: 12, paddingVertical: 16,
    borderBottomWidth: 1, borderBottomColor: lilac.hair,
  },
  // 한글 키커 — 라틴 대문자 예외가 아니므로 플로어 14를 그대로 지킨다.
  // 색은 accent(#6C5CE7)가 아니라 READ_VIOLET: lilac.bg 위에서 accent는 4.38:1로 AA를 못 넘는다
  // ([2026-08-25] 흰 그라운드에서 accent는 4.86으로 통과하지만 READ_VIOLET 8.32를 유지 — 위 상수 주석 참조)
  earnKicker: { fontSize: 14, lineHeight: 18, fontWeight: '800', letterSpacing: 1.2, color: READ_VIOLET },
  // [BUG A] Oswald 숫자는 lineHeight 명시 없이는 어센더가 잘린다 — 34 × 1.2 = 41
  earnTotal: { fontSize: 34, lineHeight: 41, fontWeight: '900', color: lilac.head },
  // 단위는 lilac.dim(#7C76A0)이 아니라 text — dim은 lilac.bg 위에서 3.82:1로 AA 미달
  // ([2026-08-25] 흰 그라운드에서도 dim은 4.24로 여전히 미달 — 이 회피는 계속 유효하다. theme.ts의 dim 주석 참조)
  earnUnit: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: lilac.text },
  earnLabel: { fontSize: 14, lineHeight: 19, color: lilac.text },
  earnDelta: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: lilac.head },
  // ---------- Ⓒ② 오늘의 수확 오버레이 — 나이트 라일락 한 겹 (transform/opacity만 애니) ----------
  haulBack: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
    // 나이트 라일락 #1C1837 · 0.94 — 랩이 잡은 결함(0.72는 적립 스트립·응가 칩이 그대로 읽힌다)의 수정치
    backgroundColor: 'rgba(28,24,55,0.94)',
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 26, paddingVertical: 30,
  },
  // 라틴+한글 혼합 키커 — 라틴 대문자 예외가 아니므로 14pt 플로어를 그대로 지킨다
  haulKicker: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 2.4, color: STAMP_INK, marginBottom: 14 },
  haulPatchLine: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: '#fff', marginTop: 12, textAlign: 'center' },
  haulPerf: { alignSelf: 'stretch', marginHorizontal: 8, marginTop: 15, marginBottom: 14, borderTopWidth: 1, borderStyle: 'dashed', borderTopColor: 'rgba(255,255,255,0.3)' },
  // 줄바꿈은 HAUL_CAP이 이미 막았다 (376dp 미만은 2칸) — wrap은 폰트 확대 등 예외 상황의 안전망
  haulRow: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 12 },
  disc: {
    borderWidth: 2.5, backgroundColor: 'rgba(185,174,245,0.10)',
    alignItems: 'center', justifyContent: 'center',
  },
  discRing: { position: 'absolute', borderWidth: 1.5 },
  discDot: { position: 'absolute', top: -4, width: 8, height: 8, borderRadius: 4, backgroundColor: STAMP_FIRST },
  haulCap: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff', marginTop: 8, textAlign: 'center' },
  haulMore: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: HAUL_DIM, marginTop: 10 },
  haulSub: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: HAUL_DIM, marginTop: 14, textAlign: 'center' },
  haulNote: { fontSize: 14, lineHeight: 19, color: HAUL_DIM, marginTop: 3, textAlign: 'center' },
  haulCta: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 11, paddingHorizontal: 22, marginTop: 16 },
  haulCtaText: { fontSize: 15, lineHeight: 20, fontWeight: '900', color: lilac.head },
  haulHint: { fontSize: 14, lineHeight: 18, color: HAUL_DIM, marginTop: 12 },
  emptyBox: { margin: 20, backgroundColor: paper.wash, borderRadius: 0, padding: 26, alignItems: 'center', borderWidth: 1, borderColor: paper.line },
  emptyText: { fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 },
});
