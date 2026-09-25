import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Dimensions, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { bookingKmLabel } from '../../src/lib/route-label';
import { alertFail } from '../../src/lib/alert-fail';
import { bookingStateLabel } from '../../src/lib/booking-state-copy';
import { traceToBox } from '../../src/lib/trace';
import { HeatTrace } from '../../src/components/runcard';
import { PaperBtn } from '../../src/components/paper-btn';
import { BookingPaymentState, PaymentRecord, cancelBooking, fetchBookingPaymentState, fetchBookingPayments, fetchChatUnread, fetchInFlightOwnerBookings, fetchMyBookings, fetchRouteById, pauseRecurringSeries, shareRunToFeed } from '../../src/lib/api';
import { unreadBadge, unreadBadgeLabel, type ChatUnreadState } from '../../src/lib/chat-read';
import { PAYMENT_STATES_THAT_SPEAK, paymentFace, latestOnly, type LatestOnly } from '../../src/lib/payment-state';
import { CancelQuote, quoteCancelFee } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { kstCal } from '../../src/lib/kst';
import { lateness, LATENESS_CEILING_MS } from '../../src/lib/lateness';
import { deepLinkStep, nowBandLine, RETURN_PHASE_LABEL, returnOwed, returnSentence } from '../../src/lib/home-hero-route';
import { BottomNav } from '../../src/components/bottomnav';
import { PaperSheet } from '../../src/components/paper-sheet';
import { PaymentRow } from '../../src/components/charge-states';
import { CheckinAnswer } from '../../src/components/checkin-answer';
import { LateNotice } from '../../src/components/late-notice';
import { RecurringCta } from '../../src/components/recurring-cta';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { TabSwipe } from '../../src/components/tabswipe';
import { Monogram, Row } from '../../src/components/ui';
import { Booking, BookingStatus, cancelPolicy, draft, RouteInfo } from '../../src/store';
import { CollarKey, collarColors, colors, paper } from '../../src/theme';

// 시트 코스 카드의 실좌표 실루엣 폭 — HeatTrace 는 명시 width/height 를 요구한다 (auto layout 불가).
// 시트 좌우 패딩 16 + 카드 안쪽 여백을 뺀 값.
const SHEET_MAP_W = Dimensions.get('window').width - 64;
const SHEET_MAP_H = 110;

// 내 일정 — agenda view. Tapping a booking opens a management sheet
// (route card + predictions + runner + reschedule/cancel actions).
// A confirmed booking is a contract — never re-routes to runner selection.

// [DESIGN.md §7a-bis · Sean 2026-08-26] Ink is the default; the grey ramp marks only what a
// customer may skip. State notes (why this booking can no longer be changed, where a club
// cancellation lives), honest gaps and the two cancel-fee disclosures moved up to ink; counts,
// units, timestamps, group labels, stat labels and glyphs stayed where they were. The judgment
// is per site — this screen is not a find-and-replace target.

// [paper chrome 2026-08-10] 포레스트/크림 레거시 크롬 은퇴 → 페이퍼 잉크 램프.
// 상태 컬러(레일·배지·칩)는 시맨틱 시스템 — 그대로 생존 (DESIGN.md 이관 문법).
// 필터 칩 = 카드 좌측 레일과 같은 상태 컬러 스키마 — 칩이 곧 범례가 된다.
// tint = 비선택(연한 상태색), sel = 선택(레일 원색). 상태가 아닌 칩(전체/반복)은 잉크 중립.
const FILTERS: { label: string; match: (b: Booking) => boolean; tint: string; tintFg: string; sel: string; selFg: string }[] = [
  { label: '전체', match: () => true, tint: '#fff', tintFg: paper.text, sel: paper.ink, selFg: '#fff' },
  { label: '예약 확정', match: (b) => b.status === 'confirmed', tint: '#e3f0c4', tintFg: '#3d5a2b', sel: '#5a7a3c', selFg: '#fff' },
  { label: '응답 대기', match: (b) => b.status === 'pending' && b.rawStatus !== 'no_show' && b.rawStatus !== 'incident_review', tint: '#FDE8D0', tintFg: '#9D580A', sel: '#F59A43', selFg: '#fff' }, // 불발·확인중은 stFor 배지와 모순되지 않게 제외 (전체 칩에는 남는다)
  { label: '완료', match: (b) => b.status === 'completed', tint: '#E3EEF8', tintFg: '#4A6E93', sel: '#6E9BC5', selFg: '#fff' },
  { label: '반복', match: (b) => !!b.recurring, tint: '#fff', tintFg: paper.text, sel: paper.ink, selFg: '#fff' },
];

// 채팅이 아직 열리지 않는 서버 상태 — 0114가 chat_threads INSERT를 accepted 상태로 좁혔다
// (is_booking_party_active; docs/contracts/party-membership-status-filter-contract.md §C.1/§E.5).
// ⚠ rawStatus로만 판단한다: STATUS_MAP은 payment_hold·matching·runner_pending을 전부 'pending'
// 하나로 뭉개므로(api.ts:690-706) 표시 어휘로 게이트하면 확정 예약까지 같이 잠긴다.
const CHAT_PRE_ACCEPT = ['draft', 'quoted', 'payment_hold', 'matching', 'runner_pending'];

// '● LIVE' 필이 참인 서버 상태 — 러너가 이 예약을 위해 **지금 밖에 있는** 구간.
// [honesty 2026-08-19] 이 필은 `b.live`로 렌더됐는데, 그 필드는 "실서버 예약"(데모 아님)이라는
// 뜻이다 (:77·:122). 데모 예약이 은퇴한 지금 그 값은 모든 행에서 true라 취소됨·완료 행에도
// 초록 LIVE 필이 붙었다 — 표시 어휘가 아니라 rawStatus로 배지를 게이트하라는 법의 정확한 위반.
// runner_enroute·picked_up 는 STATUS_MAP이 '확정'·'인계'로 뭉개므로 이 필이 실제로 정보를 더한다.
const LIVE_RAW = ['runner_enroute', 'picked_up', 'active'];

// The 실시간 보기 door sits INSIDE a card that is itself one accessibility element, so VoiceOver
// cannot focus it on its own — double-tapping the card opens the sheet, and the live map (the dog
// is out with a stranger right now) had no way in. The card therefore carries the door as a custom
// action (VoiceOver rotor → 「실시간 보기」), dispatched to the same code the nested button runs.
const LIVE_A11Y_ACTIONS = [{ name: 'live', label: '실시간 보기' }];
function openLive(bookingId: string) {
  draft.bookingId = bookingId;
  router.push('/owner/live');
}

const STATUS_STYLE: Record<BookingStatus, { label: string; bg: string; fg: string; rail: string }> = {
  confirmed: { label: '예약 확정', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  pending: { label: '러너 응답 대기', bg: '#FDE8D0', fg: '#9D580A', rail: '#F59A43' }, // 앰버×탠저린 50:50 — 카운트다운의 색 (기대감, 코랄 불침범)
  handoff: { label: '인계 완료 · 시작 대기', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  active: { label: '러닝 중 · LIVE', bg: '#eaf7c8', fg: '#4a6d1f', rail: colors.volt },
  completed: { label: '완료', bg: '#E3EEF8', fg: '#4A6E93', rail: '#6E9BC5' }, // 소프트 에너지 블루 — 그레이는 '끝'처럼 죽어 보였다; 완주는 성과다
  cancelled: { label: '취소됨', bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' },
};

// 표시 어휘(6종)가 뭉갠 희귀 서버 상태의 정직한 **색** — no_show·incident_review는 STATUS_MAP 폴백으로
// 'pending' 이 되어 확정 예약과 같은 앰버 레일을 달았다 (0056 동반 클라 수리).
// 🔴 [정직 2026-08-27] `expired` 는 STATUS_MAP 에서 'cancelled' 로 뭉개진다 — 아무도 취소하지
//    않았다. 시작 시간까지 러너를 못 찾은 것이고, 그건 플랫폼의 실패다. 알림 화면은 같은 예약을
//    이미 「매칭 만료」라고 부른다. 두 화면이 같은 사건에 다른 낱말을 쓰면 보호자는 자기가
//    취소했는지 아닌지를 화면마다 다르게 배운다.
//    ⚠ STATUS_MAP 의 뭉개기 자체는 그대로 둔다 — 그건 표시 어휘 6종을 유지하려는 의도된
//      납작화이고, rawStatus 우회로가 「뭉갠 것 중 실제로 다른 사실」을 되살리는 자리다.
// 🔴 [contract-gaps-7 2026-09-25] 낱말은 더 이상 이 파일 것이 아니다. 같은 서버 상태에 대해
//    owner/report.tsx 가 다른 표를 들고 있었고(`confirmed` 를 이 파일은 「예약 확정」, 그쪽은
//    「러너 확정 — 러닝 전」), 어느 쪽도 정본이 아니었다. 이제 낱말은 src/lib/booking-state-copy.ts
//    한 곳에서 오고 이 함수는 **색만** 고른다. 표가 모르는 상태에서는 표시 어휘의 낱말로 떨어진다.
const stFor = (b: Booking): { label: string; bg: string; fg: string; rail: string } => {
  const base = STATUS_STYLE[b.status];
  const skin = b.rawStatus === 'no_show' ? { bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' }
    : b.rawStatus === 'incident_review' ? { bg: '#FDE8D0', fg: '#9D580A', rail: '#F59A43' }
    : b.rawStatus === 'expired' ? { bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' }
    : { bg: base.bg, fg: base.fg, rail: base.rail };
  // [fix/owner-inflight-truth · owner-journey-2] The word table is keyed by raw status and cannot
  // see `run_ended_at`, so for an `active` booking whose run has ENDED it says 「러닝 중 · LIVE」 —
  // directly above the sheet's 「러닝이 끝났어요」. The return phase takes its own caption here (the
  // table's `null`-is-the-caller's-call doctrine, applied to a phase the key cannot express).
  if (b.rawStatus === 'active' && returnOwed(b)) return { label: RETURN_PHASE_LABEL, ...skin };
  return { label: bookingStateLabel(b.rawStatus) ?? base.label, ...skin };
};

const paceMin = (label: string) => (label.includes('8') ? 8 : label.includes('6') ? 6 : 7);

// ══════════ 다가오는 순서 (B① · Sean 2026-08-24: "I like 1 and 2, with the relevance sort") ══════════
//
// 이 화면은 **가장 먼 미래**로 열렸다. fetchMyBookings 가 scheduled_at DESC 로 오고, 여기서는 도착
// 순서대로 그룹을 쌓았기 때문이다. 홈은 자기 랭킹에서 같은 결함을 이미 고쳤다
// (home.tsx 「[FIX] 동순위 타이브레이크」) — 일정 목록만 그 수리를 못 받았다.
//
// ✅ [2026-08-26] 이 경고는 해소됐다. fetchMyBookings 의 `.limit(20)` 이 제거되면서 (Sean 콘솔 #17:
// 「Fix the list」 + 「keep everything」) 이 정렬은 이제 **무조건** 참이다 — 도착한 20행이라는 단서가
// 사라졌기 때문이다. 원문을 지우지 않고 남긴 이유: 이 결함은 한 번 「고쳤다」고 커밋된 뒤에도 살아
// 있었다 (b85ce82 가 러너 목록에서 캡을 지우고 보호자 목록을 고쳤다고 적었다). 무엇이 잘못이었는지
// 읽을 수 있어야 같은 오독이 반복되지 않는다.
//
// ⚠ kstDayDiff 는 home.tsx 에도 같은 것이 있다. 한 벌이 살 자리는 src/lib/kst.ts 이고 (lateness()·
// route-pick 과 같은 이유 — 화면 안에 있으면 .cjs 스위트가 닿지 못한다), 그 파일은 이 슬라이스의
// 클레임 밖이라 아직 옮기지 못했다. 두 벌이 사는 동안 규칙은 하나다: 한쪽을 고치면 둘 다 고친다.
// 복제된 것은 '날짜 칸 빼기'뿐이고, 산술 자체는 앱 공용 kstCal 을 그대로 쓴다.
function kstDayDiff(iso: string, now = Date.now()): number | null {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const box = (ms: number) => { const c = kstCal(ms); return Date.UTC(c.y, c.m, c.d); };
  return Math.floor((box(t) - box(now)) / 86400_000);
}

// [fix/owner-inflight-truth] The second copy of `elapsedLabel` that lived here is gone: its one
// caller was the 지금 band, whose sentence now comes from `nowBandLine` (src/lib/home-hero-route.ts),
// which holds the one copy the hero also uses.

// '지난 일정'의 경계 = 6시간 유예. 홈의 랭킹 타이브레이크와 **같은 값**이다 (home.tsx: past()).
// 왜 '지금'이 아니라 6시간인가: 예정 시각을 막 지난 확정 건은 지난 일정이 아니라 **늦은 일정**이고,
// 히어로의 「일정에서 정리하기」가 도착하는 자리가 바로 그 행이다. 그 행을 아래로 내리면 codex 가
// 고친 막다른 골목이 다른 문으로 되돌아온다.
const PAST_GRACE_MS = 6 * 3_600_000;

type Anchor = { head: string | null; date: string; d: string | null };
type Grp = { key: string; anchor: Anchor; items: Booking[] };

// 그룹 라벨의 상대 앵커. 지난 건에는 D-라벨을 주지 않는다 — 음수 카운트다운은 아무도 요구하지 않은
// 사실이고, '지난 일정' 구분선이 이미 그 말을 한다.
function anchorOf(b: Booking, now: number): Anchor {
  const n = b.scheduledAt ? kstDayDiff(b.scheduledAt, now) : null;
  if (n === null || n < 0) return { head: null, date: b.dateLabel, d: null };
  return { head: n === 0 ? '오늘' : n === 1 ? '내일' : null, date: b.dateLabel, d: n >= 1 ? `D-${n}` : null };
}

// 미래는 가까운 순, 지난 것은 최근 순. 숨기지 않는다 — 지난 카드는 소인도 공유 행도 그대로 유지된다
// (§7b: 정리는 숨김이 아니다).
// 시계를 함수 안에 두는 이유는 lateness() 와 같다 — 렌더 중 Date.now() 는 react-hooks/purity 가 잡는다.
function agenda(rows: Booking[], now: number = Date.now()): { future: Grp[]; past: Grp[] } {
  const at = (b: Booking) => (b.scheduledAt ? Date.parse(b.scheduledAt) : Number.MAX_SAFE_INTEGER);
  const done = (b: Booking) => b.status === 'completed' || b.status === 'cancelled';
  const isPast = (b: Booking) => done(b) || (!!b.scheduledAt && at(b) < now - PAST_GRACE_MS);
  const group = (list: Booking[]): Grp[] => {
    const out: Grp[] = [];
    const seen = new Map<string, Grp>();
    for (const b of list) {
      let g = seen.get(b.dateLabel);
      if (!g) { g = { key: b.dateLabel, anchor: anchorOf(b, now), items: [] }; seen.set(b.dateLabel, g); out.push(g); }
      g.items.push(b);
    }
    return out;
  };
  return {
    future: group(rows.filter((b) => !isPast(b)).sort((a, b) => at(a) - at(b))),
    past: group(rows.filter(isPast).sort((a, b) => at(b) - at(a))),
  };
}

export default function Schedule() {
  const insets = useSafeAreaInsets();
  const df = useDisplayFont();
  const nf = useNumFont(); // [V4] 시간 = Oswald // 표준 탭 헤더 — 좌측 BHS 30

  const [filterIdx, setFilterIdx] = useState(0);
  const [selected, setSelected] = useState<Booking | null>(null);
  const [sheetMode, setSheetMode] = useState<'detail' | 'cancel'>('detail');
  // [0117 §9b mirror — Sean 2026-08-25 "ship the cancel fee mirror thing"] The fee is READ,
  // not computed: the client's four-arm ladder could not see the §9 waiver's fault half
  // (booking_faults is sealed), so the same booking could show 50% here and charge 0 there.
  // One quote per selected booking; both render sites (the detail link and the confirm sheet)
  // read this one answer. 'loading' is not 0 — no number renders until the server answers, and
  // a failed quote BLOCKS the cancel commit: a price we could not show is a price we may not
  // promise ("the price shown IS the price charged", 0117 §9c's own law, applied client-side).
  const [cancelQuote, setCancelQuote] = useState<
    { s: 'idle' | 'loading' | 'err' } | ({ s: 'ok' } & CancelQuote)
  >({ s: 'idle' });
  const [quoteTry, setQuoteTry] = useState(0);
  // primitives, so the effect's deps are exactly what it reads (exhaustive-deps, honestly —
  // depending on the `selected` OBJECT would re-quote on every identity churn of the row)
  const selectedId = selected?.id ?? null;
  const selectedClubId = selected?.clubSessionId ?? null;
  useEffect(() => {
    // club rows never quote: the marketplace ladder is not theirs (club_out_of_scope) and the
    // sheet routes them to the club screen instead of drawing a cancel door at all.
    if (!selectedId || selectedClubId) { setCancelQuote({ s: 'idle' }); return; }
    let alive = true;
    setCancelQuote({ s: 'loading' });
    quoteCancelFee(selectedId)
      .then((q) => { if (alive) setCancelQuote({ s: 'ok', ...q }); })
      .catch((e) => {
        console.warn('[schedule] cancel quote:', (e as Error)?.message ?? e);
        if (alive) setCancelQuote({ s: 'err' });
      });
    return () => { alive = false; };
  }, [selectedId, selectedClubId, quoteTry]);
  // ── 시트 코스 카드의 실좌표 (owner-journey-7) ──────────────────────────────────────────────
  // 여기엔 110pt 짜리 영구 플레이스홀더가 있었다. 같은 routeId 로 owner/request.tsx 는 이미 실선을
  // 그린다(fetchRouteById → HeatTrace) — 즉 화면이 「없다」고 말한 것은 앱이 못 하는 일이 아니라
  // 이 화면이 읽지 않은 값이었다. 예약 행은 좌표를 싣고 오지 않으므로(목업 썸네일 은퇴, :500 참조)
  // 시트가 열릴 때 그 한 행만 읽는다.
  // ⚠ 네 가지 사실을 네 가지로 그린다: 코스 없음(아무것도 아님) · 읽는 중 · 실패(다시 시도) ·
  //   도착. 도착했는데 지오메트리가 없으면 **아무것도 그리지 않는다** — 지어낸 모양 금지가 이
  //   파일의 기존 법이고(:500), 「준비 중」은 우리가 못 만든 것을 곧 만들 것처럼 말하는 문장이다.
  const [routeInfo, setRouteInfo] = useState<RouteInfo | null>(null);
  const [routeState, setRouteState] = useState<'none' | 'loading' | 'ready' | 'err'>('none');
  const [routeTry, setRouteTry] = useState(0);
  const selectedRouteId = selected?.routeId ?? null;
  useEffect(() => {
    setRouteInfo(null);
    if (!selectedRouteId) { setRouteState('none'); return; }
    let alive = true;
    setRouteState('loading');
    fetchRouteById(selectedRouteId)
      .then((r) => { if (alive) { setRouteInfo(r); setRouteState('ready'); } })
      .catch((e) => {
        console.warn('[schedule] route:', (e as Error)?.message ?? e);
        if (alive) setRouteState('err');
      });
    return () => { alive = false; };
  }, [selectedRouteId, routeTry]);
  const [liveBookings, setLiveBookings] = useState<Booking[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  // [honesty 2026-08-11] warn-only catch + [] seed rendered "예정된 러닝이 없어요"
  // in flight and on failure. Three states now: loading / error+retry / loaded.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);

  const load = () => {
    setLoadErr(false);
    // [B9] 홈에서만 고쳤던 합집합을 여기에도. 히어로의 「일정에서 정리하기」가 **도착하는 화면**이
    // (#17 이후 20행 창은 없다. 이 belt는 상태 필터 쪽 위험만 남아 그대로 둔다 — codex 2026-08-21.)
    return Promise.all([fetchMyBookings(), fetchInFlightOwnerBookings()])
      .then(([bs, inFlight]) => {
        const seen = new Set(bs.map((b) => b.id));
        const liveById = new Map(inFlight.map((b) => [b.id, b]));
        return inFlight.length
          ? [...bs.map((b) => liveById.get(b.id) ?? b), ...inFlight.filter((b) => !seen.has(b.id))]
          : bs;
      })
      .then((b) => { setLiveBookings(b); setLoaded(true); })
      .catch((e) => { console.warn('[schedule] bookings:', e?.message ?? e); setLoadErr(true); });
  };
  // [0212] 채팅 미확인 — 관리 시트의 채팅 칩에 붙는 배지. 별도 상태·별도 실패: 목록 로드가
  // 실패해도 배지는 그 얘기를 하지 않고, 배지 로드가 실패하면 **배지가 없을 뿐** 0이 아니다.
  const [chatUnread, setChatUnread] = useState<ChatUnreadState>({ status: 'loading' });
  const loadChatUnread = useCallback(() => {
    fetchChatUnread()
      .then((rows) => setChatUnread({ status: 'ready', rows }))
      .catch((e) => { console.warn('[schedule] chat unread:', e?.message ?? e); setChatUnread({ status: 'error' }); });
  }, []);
  useFocusEffect(useCallback(() => { load(); loadChatUnread(); }, [loadChatUnread]));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const all = liveBookings; // 데모 예약 제거 — 실예약만
  // [B② 2026-08-24 Sean] 진행 중인 예약은 목록의 한 항목이 아니다. 러너가 **지금 아이를 데리고
  // 밖에 있는** 건이 DESC 목록에서 미래 예약 세 개 밑에 앉아 있었다. 게이트는 이 파일이 이미
  // 정의해 둔 rawStatus 집합(LIVE_RAW) 그대로 — 새 상태도, 새 어휘도 없다.
  // 목록에서 빼는 것이 숨기는 것이 아니다: 밴드는 **필터 칩과 무관하게 항상** 그려지고, 밴드 행을
  // 탭하면 같은 관리 시트가 열린다 (이동 중 취소 = 0066 의 50% 티어가 그 시트에 있다).
  // ⚠ [sim walk 2026-08-25] THE BAND'S CLAIM IS "지금", AND rawStatus ALONE CANNOT CARRY IT.
  // Measured on the fixture: a runner_enroute row 20 days old rendered under 「지금 ● LIVE」 as
  // 「14일째 문 앞이에요」 — true per the columns, absurd as liveness. Past the 3-hour ceiling the
  // late-protocol's own vocabulary says a booking is 끝난 일, not 지금 (lateness.ts:55-59), so the
  // band inherits that line instead of inventing one: enroute/picked_up rows past
  // scheduled_at + ceiling fall back to the plain list (still reachable, still cancellable —
  // dropping from the BAND is not hiding). `active` stays unconditionally: the server says a run
  // is in progress, and a run that started late is genuinely live past any schedule arithmetic.
  const bandCeiling = (b: Booking) => {
    if (b.rawStatus === 'active') return true;
    const t = b.scheduledAt ? Date.parse(b.scheduledAt) : NaN;
    return !Number.isNaN(t) && Date.now() < t + LATENESS_CEILING_MS;
  };
  const liveNow = all.filter((b) => LIVE_RAW.includes(b.rawStatus ?? '') && bandCeiling(b));
  const liveIds = new Set(liveNow.map((b) => b.id));
  const notLive = all.filter((b) => !liveIds.has(b.id));
  const visible = notLive.filter(FILTERS[filterIdx].match);
  const { future, past } = agenda(visible);
  // 헤더 카운트는 **칩과 무관하게** 계정을 말한다 — 필터를 걸면 줄어드는 숫자는 '전체'가 아니다.
  // ✅ #17 이후 두 숫자는 전체 수다 (위 B① 주석). 화면은 같은 수를 「예약 N건」으로
  // 말하고 있었으므로 새 주장이 늘지는 않는다 — 늘어난 건 '다가오는' 이라는 구분 하나다.
  const upcomingCount = agenda(notLive).future.reduce((n, g) => n + g.items.length, 0);

  const open = (b: Booking) => {
    // ⚠ The sheet OPENS for a still-matching booking (2026-08-20). It used to short-circuit into a
    // one-button alert, and because `b.live` is hardcoded true for every row (api.ts) the guard
    // caught EVERY `matching` booking — so the sheet's own 러너 변경 arm, which explicitly handles
    // `rawStatus === 'matching'`, was unreachable code. The user-visible consequence was a dead
    // end: with an `active` booking ranked ahead of it, home's hero never surfaced the searching
    // booking either, leaving NO path anywhere in the app to cancel or re-nominate it. The sheet's
    // rawStatus arms already know what to render for this state; the guard predated them.
    setSheetMode('detail');
    setSelected(b);
  };
  const close = () => setSelected(null);

  // A door that starts a NEW booking clears the last nomination first — home-hero.tsx's rule
  // (review P1-3): a failed or abandoned nomination must not ride along into this booking. The ＋
  // pushed `/owner/request` bare and skipped it; the empty state's button and the ＋ share this.
  const startNewBooking = () => {
    draft.preferredRunnerId = null;
    draft.preferredRunnerName = null;
    draft.autoEarliest = false;
    router.push('/owner/request');
  };

  // ── [fix/owner-inflight-truth · owner-journey-5] `?bid=` — open THAT booking's sheet, once ──
  // Every door into this screen used to land on the list: the late hero (「일정에서 정리하기 · 취소
  // 조건을 확인하고 닫아요」), the check-in push, five pre-run pushes, home's rail rows and radar's
  // exits. They now carry the booking, and the rule for consuming it is `deepLinkStep`
  // (src/lib/home-hero-route.ts, pinned): after the first SUCCESSFUL load only, exactly once, and
  // an id not in the list opens nothing. The param is then dropped so a re-render or coming back
  // cannot reopen a sheet the owner closed. The ref is written inside the effect, never in render.
  const { bid: bidParam } = useLocalSearchParams<{ bid?: string }>();
  const deepHandled = useRef<string | null>(null);
  useEffect(() => {
    const step = deepLinkStep({ loaded, bid: bidParam, handled: deepHandled.current, rows: liveBookings });
    deepHandled.current = step.handled;
    if (step.open) { setSheetMode('detail'); setSelected(step.open); }
    if (step.clear) router.setParams({ bid: undefined });
  }, [loaded, bidParam, liveBookings]);

  // 반복 해지 (0026) — 시리즈만 멈추고, 이미 생성된 예약은 그대로 (개별 취소는 기존 플로우)
  const pauseSeries = () => {
    const sid = selected?.seriesId;
    if (!sid) return;
    Alert.alert('매주 반복 해지', '다음 주부터 자동 예약이 멈춰요.\n이미 잡힌 일정은 그대로 유지돼요.', [
      { text: '유지', style: 'cancel' },
      {
        text: '해지', style: 'destructive',
        onPress: async () => {
          try {
            await pauseRecurringSeries(sid);
            close();
            load();
            Alert.alert('해지 완료', '매주 반복이 해지됐어요');
          } catch (e) {
            alertFail('해지 실패', e, null, { fold: { empty: '잠시 후 다시 시도해주세요' } });
          }
        },
      },
    ]);
  };

  // [정직 배치 2026-08-06 · item 6] 목업 코스 조회(sampleRoutes.find) 퇴역 — 실예약의 route_id를
  // 목업 코스에 맞춰 '식수대 2곳 · 7.18 점검 · 초코의 슬개골 메모'로 채우던 자리다. 시트의 코스
  // 카드는 이제 예약 행이 실제로 들고 있는 값(routeName·km)만 말한다. 실 코스 상세(특징·점검일·
  // 트레이스)는 route_id로 실코스 행을 읽는 헬퍼가 생길 때 복귀한다 (스펙 wave-2).
  // live 예약은 실러너 이름으로 뷰 구성 — 목업 프로필 조회 금지
  // ⚠ [2026-09-15] The `!selected.live ? runners.find(…)` lookup that stood here is GONE. It fell
  // back to store.ts's fixture roster, whose rows carry `rating: 4.9`, `reviews: 127`, `runs: 214`
  // and badges 「신원인증·펫보험」 — and this sheet renders exactly those fields (line ~742). It was
  // unreachable rather than broken: `all = liveBookings` and every row api.ts builds sets
  // `live: true` (api.ts:5255). But `Booking.live` is OPTIONAL (store.ts:185), so one booking
  // constructed without it and an owner reads a stranger's invented 4.9★ on their own 일정 —
  // the fabricated-data law with no gate standing between it and the screen. The fixture roster
  // is no longer imported here, so the path cannot come back by accident.
  const runner = selected
    ? {
        id: 'live', name: selected.runnerName, char: selected.runnerName[0] ?? '러', color: '#5a7a3c',
        // [2026-09-23] `rating`/`reviews`/`runs`/`pace` are GONE with the line that read them.
        // They were hard-coded `null`, so the sheet's 「★ …」 branch was unreachable and the card
        // always fell to 「실러너 · 상세 프로필 준비 중」 — a sentence about a page that shipped
        // weeks ago. The identity block is now a button to `/runner-profile/[id]`, which reads
        // those same numbers from the server; four `null`s nobody can render belong there, not
        // here. (`desc` stays: it is still read below, same null-today shape.)
        badges: [] as string[], desc: null as string | null, // [정직] 신원인증 배지 은퇴 — 뒷받침 데이터 없음 (wave-1 meetup P1-6과 동일)
        distanceKm: 0,
      }
    : undefined;
  const runMin = selected ? selected.km * paceMin(selected.paceLabel) : 0;

  // ── ⟳ 이대로 다시 예약 — 한 벌 (owner-journey-6) ────────────────────────────────────────────
  // 이 프리필은 완료 시트에만 있었고, 취소·만료·불발 시트는 「더 진행할 작업이 없어요」에서 끝났다.
  // 그 문장은 **이 예약**에 대해서는 참이지만, 보호자가 그 자리에서 하고 싶은 일(같은 조건으로
  // 다시 잡기)은 이 예약에 대한 동작이 아니라 새 예약이라 그 사실과 충돌하지 않는다. 리포트 화면은
  // 멈춘 러닝에도 이미 같은 문을 준다 — 일정 시트만 못 받았다.
  // ⚠ 한 벌로 뽑은 이유: 두 벌이 되는 순간 한쪽에만 프리필 수리가 붙고 두 문이 다른 예약을 만든다.
  const rebook = () => {
    if (!selected) return;
    draft.km = selected.km;
    draft.pace = selected.paceLabel;
    draft.preferredRunnerId = selected.runnerProfileId ?? null;
    draft.preferredRunnerName = selected.runnerProfileId ? selected.runnerName : null;
    draft.scheduledAtIso = null;
    draft.timeLabel = '시간을 선택해주세요';
    close();
    router.push('/owner/request');
  };
  // ⚠ 러너가 정해지기 전에 끝난 예약(만료·매칭 중 취소)은 지명할 사람이 없다 — 그때는 지명 절이
  //   통째로 빠진다. `runnerProfileId` 가 그 유일한 근거이고, 프리필과 이 문장이 같은 값을 읽는다.
  // [fix/owner-inflight-truth · ui-consistency-10] The three `ghostAction` doors on this sheet were a
  // FOURTH secondary-button style ('#fff' face, '#EEE' border, ink label) beside PaperBtn's matrix.
  // They are PaperBtn secondary now; a door's sub-line moves OUT of the face and sits under it, the
  // 일정 변경 요청 idiom further down this file (a two-line face is not a matrix button).
  const rebookRow = selected ? (
    <>
      {/* No ⟳ in the label: PaperBtn speaks its label as the accessibility label, and the old
          face's explicit label was the words alone. ⟳ means 매주 반복 everywhere else on this sheet. */}
      <PaperBtn label="이대로 다시 예약" variant="secondary" style={{ marginTop: 8 }} onPress={rebook} />
      <Text style={s.btnSub}>
        같은 거리·페이스{selected.runnerProfileId ? ` · ${selected.runnerName} 러너 지명` : ''} — 시간만 골라요
      </Text>
    </>
  ) : null;

  // [2026-08-25] cancelFeeRateFor is RETIRED — the number now comes from quote_cancel_fee
  // (see cancelQuote above). The tier sentence keys on the QUOTED status when the quote is in
  // (the server's answer includes the fault-waiver arm the client cannot see) and falls back
  // to rawStatus only for display continuity while loading — never for the number itself.
  const enrouteCancel = (cancelQuote.s === 'ok' ? cancelQuote.status : selected?.rawStatus) === 'runner_enroute';
  const quotedFee = cancelQuote.s === 'ok' ? cancelQuote.fee : null;
  // [2026-08-25] 아래 철회 기록의 전제가 이 파일과 함께 닫힌다: 이 브랜치는 0117 과 함께
  // 배포되므로 '면제 정책은 배포되지 않았다'가 더는 참이 아니고, 면제를 볼 수 있는 유일한 눈
  // (quote_cancel_fee)이 이제 이 화면의 숫자다. 기록 자체는 판단의 근거였으므로 지우지 않는다.
  // ⚠ [철회 2026-08-21] 여기 '면제될 수 있다' 문구를 넣었다가 되돌린다. **오늘은 거짓이기 때문이다.**
  // 0117 §9 의 면제는 아직 배포되지 않았고, 현재 서버는 0066:80 대로 runner_enroute 취소에
  // 조건 없이 50%를 청구한다. 즉 그 시점의 정확한 답은 **50% 그 자체**였고, 내가 넣은 불확실성은
  // 없는 정책을 미리 말한 것이다 — 거짓 주장을 고치는 커밋에서 새 거짓 주장을 하나 만들었다.
  // 게다가 시트는 여전히 정확한 50%와 금액과 '전액 러너 보상' 문장을 함께 보여주고 있었으므로,
  // 한 수수료에 대해 세 가지 다른 말을 하는 화면이 됐다 (codex 지적).
  // 이 변경은 **0117 배포와 같은 창에서** 다시 온다. 그때는 미러가 아니라 quote_cancel_fee 읽기다.

  // 결제 내역 (charge slice §0-bis) — 예약 하나의 payments 행. 이 목록은 **영수증 행**만 담당한다.
  const [payRows, setPayRows] = useState<PaymentRecord[]>([]);
  const [payErr, setPayErr] = useState(false);
  // 🔴 [0220] 늦게 도착한 응답은 **남의 예약 돈 이야기**다. 시트를 다른 예약으로 바꿔도
  //    앞선 예약의 promise 는 멈추지 않는다 — 아래 useEffect 의 초기화는 상태를 비울 뿐
  //    뒤늦은 resolve 를 막지 못한다. 요청마다 토큰을 받고, 최신 토큰일 때만 반영한다.
  //    `catch`/`finally` 도 똑같이 막는다: 늦은 실패가 실패 줄을 켜거나 로딩을 끄는 것도
  //    같은 버그의 다른 얼굴이다. 두 읽기는 각자 가드를 갖는다 — 재시도가 한쪽만 다시
  //    부를 때 공유 카운터라면 다른 쪽의 진행 중 요청을 무효로 만든다.
  //    ⚠ 보관은 `useState`의 **게으른 초기화**다. 셋 다 재보기 전에 측정한 결과다:
  //      `if (!ref.current) ref.current = …` 는 렌더 중 ref 변이로 에러 2건
  //      (react-doctor/no-ref-current-in-render), `useRef(latestOnly())` 는 매 렌더 초기화로
  //      경고 2건(rerender-lazy-ref-init), `useState(latestOnly)` 는 둘 다 0건이다 — 리액트가
  //      초기화 함수를 한 번만 부르고, 세터는 쓰지 않으므로 리렌더도 일으키지 않는다.
  const [payRowsGuard] = useState<LatestOnly>(latestOnly);
  const [payStateGuard] = useState<LatestOnly>(latestOnly);

  const loadPayments = useCallback((bid: string) => {
    const token = payRowsGuard.begin();
    setPayErr(false);
    fetchBookingPayments(bid)
      .then((rows) => { if (payRowsGuard.isCurrent(token)) setPayRows(rows); })
      .catch((e) => {
        console.warn('[schedule] payments:', e?.message ?? e);
        if (payRowsGuard.isCurrent(token)) setPayErr(true);
      });
  }, [payRowsGuard]);

  // 🔴 [0207] 결제 **상태**는 서버가 말한다 — 행 수가 아니다.
  //    여기 있던 판정은 `payRows.length === 0`이면 「아직 청구 내역이 없어요 — 정산이 끝나면
  //    여기에 표시돼요」였다. 정산 중인 예약에는 참이고, 0173의 여덟째 팔이 보고하는 모집단
  //    (정산은 끝났는데 가격을 못 매겼거나 민트가 터져서 다섯 분마다 도는 스윕이 한 시간 동안
  //    아무것도 못 만든 건)에는 **거짓**이다 — 그 문장은 「청구가 없었다」로 읽힌다. 부재의 뜻이
  //    둘이었고, 서버는 내내 그 차이를 알고 있었다.
  // ⚠ 실패해도 **이미 보여 준 상태를 지우지 않는다**: 재시도가 실패했다고 화면에 있던 참인 문장이
  //   사라지면, 사라진 자리가 다시 「아무 일도 없었다」로 읽힌다.
  const [payState, setPayState] = useState<BookingPaymentState | null>(null);
  const [payStateLoading, setPayStateLoading] = useState(false);
  const [payStateErr, setPayStateErr] = useState(false);
  const loadPayState = useCallback((bid: string) => {
    const token = payStateGuard.begin();
    setPayStateErr(false);
    setPayStateLoading(true);
    fetchBookingPaymentState(bid)
      .then((v) => { if (payStateGuard.isCurrent(token)) { setPayState(v); setPayStateErr(false); } })
      .catch((e) => {
        console.warn('[schedule] payment state:', e?.message ?? e);
        if (payStateGuard.isCurrent(token)) setPayStateErr(true);
      })
      .finally(() => { if (payStateGuard.isCurrent(token)) setPayStateLoading(false); });
  }, [payStateGuard]);

  useEffect(() => {
    if (!selected) {
      // ⚠ [0220] 시트를 닫을 때도 **토큰을 올린다**. 상태만 비우면 진행 중이던 읽기의 토큰은
      //   여전히 '최신'이라, 닫은 뒤 도착한 응답이 비운 자리를 다시 채운다.
      payRowsGuard.begin();
      payStateGuard.begin();
      setPayRows([]); setPayErr(false);
      setPayState(null); setPayStateErr(false); setPayStateLoading(false);
      return;
    }
    setPayRows([]);
    setPayState(null);            // 다른 예약의 상태가 한 프레임이라도 남으면 남의 돈 이야기다
    loadPayments(selected.id);    // 각 로더가 새 토큰을 받는다 — 이전 예약의 응답은 버려진다
    loadPayState(selected.id);
  }, [selected, loadPayments, loadPayState, payRowsGuard, payStateGuard]);

  const payFace = paymentFace(payState);
  // ⚠ 완료(display status)는 더 이상 **유일한** 트리거가 아니다 — 0116:47-52가 이름으로 거절하는
  //   앵커라서다: 정산된 예약은 incident_review/refund_pending으로 합법적으로 옮겨 가고, 그때
  //   display status로 판정하면 이 슬라이스가 드러내려는 바로 그 부류가 숨는다.
  const settled = selected?.status === 'completed';
  const stateSpeaks = !!payState && PAYMENT_STATES_THAT_SPEAK.includes(payState.state);
  const payBusy = payStateLoading && !payFace;
  const payFailed = payStateErr || payErr;
  // ⚠ 매 갈래가 **본문을 보장한다** — 제목만 있는 빈 카드는 「여기 뭔가 있었다」고 말하면서
  //   아무것도 말하지 않는다. 완료 예약은 서버가 조용한 상태(awaiting_settlement)여도 참인
  //   문장이 있으므로 그때는 연다; 아직 뛰지도 않은 예약은 열지 않는다(정산 전 '내역 없음'은 소음).
  const showPayments = payRows.length > 0
    || stateSpeaks
    || (!!settled && (!!payFace || payBusy || payFailed));

  // 그룹 하나 = 날짜 라벨 + 그 날의 카드들. 미래 그룹은 상대 앵커(오늘 · 내일 · D-n)를 달고,
  // 지난 그룹은 날짜만 단다. 키에 접두사를 붙이는 이유: 유예 안의 늦은 건은 라벨이 날짜뿐이라
  // 지난 그룹과 같은 문자열이 될 수 있다.
  const renderGroup = (g: Grp, side: 'f' | 'p') => (
    <View key={`${side}-${g.key}`} style={{ marginTop: 18 }}>
      {/* 날짜 그룹 라벨 — dim 14 (900은 숫자·타이틀 전용 법). 앵커만 잉크, D-라벨만 Oswald. */}
      <Text style={s.grp}>
        {g.anchor.head ? <Text style={s.grpHead}>{g.anchor.head} · </Text> : null}
        {g.anchor.date}
        {g.anchor.d ? <Text style={[s.grpD, nf]}> {g.anchor.d}</Text> : null}
      </Text>
      {g.items.map((b) => {
        const st = stFor(b);
        return (
          <View key={b.id}>
          <Pressable style={s.bookingCard} onPress={() => open(b)} accessibilityRole="button"
            accessibilityActions={b.status === 'active' && !returnOwed(b) ? LIVE_A11Y_ACTIONS : undefined}
            onAccessibilityAction={(e) => { if (e.nativeEvent.actionName === 'live') openLive(b.id); }}>
            <View style={[s.rail, { backgroundColor: st.rail }]} />
            {/* 절취선 (티켓 모티프 마지막 조각) — 확정 = 계약 = 티켓. 상태 레일이 스텁,
                레일 경계에 펀치 노치 + 퍼포레이션 도트 (overflow hidden이 노치를 반원으로 클립) */}
            {b.status === 'confirmed' && (
              <View pointerEvents="none" style={s.perfWrap}>
                <View style={[s.perfNotch, { marginTop: -5 }]} />
                <View style={{ flex: 1, justifyContent: 'space-evenly', alignItems: 'center' }}>
                  {Array.from({ length: 8 }).map((_, i) => (
                    <View key={i} style={s.perfDot} />
                  ))}
                </View>
                <View style={[s.perfNotch, { marginBottom: -5 }]} />
              </View>
            )}
            <View style={{ flex: 1, padding: 14 }}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Row style={{ gap: 6 }}>
                  {/* 18 -> 20, lineHeight 25 >= 1.2x (BUG A) */}
                  <Text style={[{ fontSize: 20, fontWeight: '900', color: paper.ink, lineHeight: 25 }, nf]}>{b.timeLabel}</Text>
                  {b.recurring && (
                    <View style={s.recurPill}><Text style={{ fontSize: 15, fontWeight: '800', color: '#4a6d1f' }}>⟳ 매주</Text></View>
                  )}
                  {/* ⚠ [2026-09-15] 이 필은 `LIVE_RAW.includes(rawStatus)` 만 보고 `bandCeiling` 을
                      보지 않았다. 그런데 이 파일이 :224-231 에 적어 둔 측정이 바로 그것이다 —
                      「THE BAND'S CLAIM IS "지금", AND rawStatus ALONE CANNOT CARRY IT」, 20일 묵은
                      runner_enroute 행. 천장을 넘긴 그 행들은 밴드에서 빠져 notLive → agenda 의
                      **past** 버킷으로 내려가는데(6시간 유예, :140), 거기서 이 카드가 「지난 일정」
                      구분선 아래에 초록 ● LIVE 를 찍었다 — 그것도 STATUS_MAP 이 runner_enroute 를
                      뭉갠 「예약 확정」 배지 바로 옆에. 밴드가 쓰는 판정을 같은 주장에 그대로 쓴다:
                      한 파일이 같은 문장을 두 자리에서 다르게 판정하지 않는다. */}
                  {LIVE_RAW.includes(b.rawStatus ?? '') && bandCeiling(b) && (
                    <View style={s.livePillSm}><Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>● LIVE</Text></View>
                  )}
                </Row>
                <View style={[s.statusPill, { backgroundColor: st.bg }]}>
                  <Text style={{ fontSize: 15, fontWeight: '800', color: st.fg }}>{st.label}</Text>
                </View>
              </Row>
              <Row style={{ gap: 12, marginTop: 10 }}>
                {/* 목업 트레이스 썸네일 퇴역 (item 6) — 예약 행에는 코스 좌표가 없다.
                    지어낸 모양 대신 아무것도 그리지 않는다 (실좌표는 코스 상세가 담당) */}
                <View style={{ flex: 1 }}>
                  <Row style={{ gap: 4 }}>
                    <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>{b.routeName}</Text>
                    {/* ⚠ NO ✓ HERE. This row has no `checked_at` behind it — the dot was
                        drawn unconditionally, so a booking with no route rendered
                        「코스 미지정 ✓」: a verification mark on the absence of a course.
                        The management sheet in this same file retired the same badge for
                        exactly this reason ("근거 없는 검증 마크 금지"). If this row ever
                        needs the mark back, it needs the column first. */}
                  </Row>
                  {/* 칼라 컬러 도트 (P1, 0033) — 다견 가구가 한 눈에 '누구 러닝인지' */}
                  <Row style={{ gap: 6, marginTop: 3, alignItems: 'center' }}>
                    {b.dogCollar && collarColors[b.dogCollar as CollarKey] && (
                      <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: collarColors[b.dogCollar as CollarKey], borderWidth: 1.5, borderColor: '#fff' }} />
                    )}
                    <Text style={{ fontSize: 15, color: paper.text, flexShrink: 1 }} numberOfLines={1}>
                      {/* 🔴 [정직 2026-08-27] `b.runnerName` 은 이름 슬롯이지만 아직 매칭 전이면
                          api.ts:4506 이 거기에 **상태 토큰** '매칭 중' 을 넣는다 — 그래서 화면에
                          「매칭 중 러너」가 떴고, 이건 '매칭 중'이라는 이름의 러너로 읽힌다.
                          owner/home:561 은 이미 `b.matched ?` 로 막고 있었다; 이 파일만 안 막았다.
                          같은 가드를 그대로 가져온다 — 새 문장을 쓰지 않는 이유는, 두 화면이 같은
                          상태를 다른 낱말로 말하면 그게 다음 정직 결함이 되기 때문이다. */}
                      {/* The booking distance carries a label: the route name above can end in its
                          own km token (0100), and the two numbers are different facts. */}
                      {b.dogName} · {b.matched ? `${b.runnerName} 러너` : '러너 찾는 중'} · {bookingKmLabel(b.km)}
                    </Text>
                  </Row>
                  {/* money = Oswald (color/size kept) — lineHeight 19 >= 1.26x (BUG A) */}
                  <Text style={[{ fontSize: 15, color: paper.dim, marginTop: 2, lineHeight: 19 }, nf]}>
                    {b.price.toLocaleString()}원 · {b.paceLabel}
                  </Text>
                </View>
                {/* 완료 = T3 원형 소인 (Sean 확정 — 완주 날짜 내장, 인플로우 우측 컬럼이라 겹침 원천 차단) ·
                    그 외 = 셰브런. 공유 버튼들은 카드 아래 행 (Sean 2026-07-29) */}
                {b.status === 'completed' ? (
                  <FinisherSeal dateLabel={b.dateLabel} />
                ) : (
                  <Text style={{ fontSize: 16, color: paper.dim, alignSelf: 'center' }}>›</Text>
                )}
              </Row>
              {/* [owner-journey-2] Not for a run that has ENDED (`returnOwed`): a live map of a
                  finished run is a door to nothing. (Every `active` row sits in the 지금 band today,
                  so this card arm is a belt — it must not disagree with the band if that changes.) */}
              {b.status === 'active' && !returnOwed(b) && (
                <Pressable
                  onPress={(e) => { e.stopPropagation(); openLive(b.id); }}
                  style={({ pressed }) => [s.goLiveBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                  accessibilityRole="button"
                >
                  <Text style={s.liveInk}>● 실시간 보기 ›</Text>
                </Pressable>
              )}
            </View>
          </Pressable>
          {/* 공유 진입을 일정 카드에 직결 (Sean 2026-07-29) — 카드 아래 부착 행이라 도장을 가리지 않는다 */}
          {b.status === 'completed' && (
            <View style={s.shareRow}>
              <Pressable
                onPress={() => router.push(`/shot/${b.id}`)}
                style={({ pressed }) => [s.shareBtn, pressed && { backgroundColor: paper.wash }, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                accessibilityRole="button"
              >
                <Text style={s.shareTxt}>공유 카드</Text>
              </Pressable>
              <Pressable
                onPress={() => {
                  shareRunToFeed(b.id)
                    .then(() => Alert.alert('피드에 올렸어요', '하이 피드에서 확인해보세요'))
                    .catch((err) => alertFail('피드 공유 실패', err));
                }}
                style={({ pressed }) => [s.shareBtn, pressed && { backgroundColor: paper.wash }, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                accessibilityRole="button"
              >
                <Text style={s.shareTxt}>피드 자랑</Text>
              </Pressable>
            </View>
          )}
          </View>
        );
      })}
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: insets.top, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <View style={{ paddingHorizontal: 16 }}>
        {/* 표준 탭 헤더 — 탭 루트엔 뒤로가기 없음 (바텀 내비가 탈출구), 좌측 타이틀 + 그레이 서브 */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View>
            {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
            <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>내 일정</Text>
            {/* [2026-08-10 density audit] "실예약" was internal jargon — users only know 예약
                [B① 2026-08-24] 「예약 N건」 하나였던 자리 — 목록이 다가오는 순으로 열리는 화면에서
                가장 쓸모 있는 수는 '앞으로 몇 건인가'다. Oswald 숫자는 명시 lineHeight (BUG A). */}
            {/* ⚠ [2026-09-15 로딩은 0이 아니다] 이 두 수는 게이트 없이 그려지고 있었다. `liveBookings`
                는 []로 시작하고 `loaded`/`loadErr`는 아래 목록(:571·:577)에서만 읽히므로, 첫 페인트와
                실패 후에 「다가오는 0건 · 전체 0건」이 나왔다 — 읽지도 못한 계정에 대해 측정된 사실인
                척하는 수이고, 실패 때는 바로 아래 「일정을 불러오지 못했어요」 스트립과 한 화면에서
                서로를 반박했다. 이 파일이 이미 아는 규칙이다 (:983 「확인 중엔 숫자 대신 상태를
                말하고(로딩은 0이 아니다)」) — 같은 규칙을 이 줄에도 적용한다. */}
            <Text style={[{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 4 }, nf]}>
              {loadErr ? '일정을 불러오지 못했어요'
                : !loaded ? '불러오는 중…'
                  : `다가오는 ${upcomingCount}건 · 전체 ${liveBookings.length}건`}
            </Text>
          </View>
          {/* ＋ = 백버튼 문법의 스퀘어 (40×40 · 캔버스 면 · 1px 코랄 · 잉크 글리프)
              [fix/owner-inflight-truth · less-is-more-1] Drawn exactly like the back key, so it is
              NOT the empty state's only door any more — see the labelled button under 「예정된
              러닝이 없어요」. Both go through `startNewBooking`. */}
          <Pressable onPress={startNewBooking} style={s.circleBtn}
            accessibilityRole="button" accessibilityLabel="러닝 예약하기">
            <Text style={{ fontSize: 19.5, color: paper.ink }}>＋</Text>
          </Pressable>
        </Row>
        </View>

        {/* ══════════════════ 지금 (B② · Sean 2026-08-24) ══════════════════
            게이트가 참일 때만 존재한다: 빈 밴드도, 플레이스홀더도 없다. 두 아이가 나가 있으면
            같은 밴드 안에 두 행이 쌓인다 (밴드가 두 개가 되지 않는다).
            ⚠ 문장은 rawStatus 마다 하나씩이고 **추측하지 않는다**. 특히 runner_enroute 는 arrived_at
            유무로 갈린다 — 「도착했어요」와 「이동 중이에요」는 보호자에게 완전히 다른 사실이다.
            ⚠ 여기에 인계 CTA 는 없다. 도착에서 무엇이 켜지는가(A/B)는 Sean 의 재정 대기이고
            (docs/decisions/handoff-cta-gating.md), 밴드는 그 재정을 앞질러 결정하지 않는다 — 사실만
            말하고, 행 전체가 관리 시트로 가는 문이다.
            색은 이 파일의 기존 라이브 어휘 그대로(#ffe9e2 면 · #ffc9b8 선 = "라이브는
            상태색이지 버튼 스타일이 아니다") + 볼트 레일. 목록에는 여전히 코랄 표면이 0개다.
            [fix/owner-inflight-truth · ui-consistency-7] The label INK is paper.actionInk now (s.liveInk):
            the old coral text measured 3.64:1 on the #ffe9e2 face, below AA for a 16/900 label (not
            large text); actionInk is 5.72:1 in the same coral family. Face and border are unchanged.
            [owner-journey-2] The row's sentence and its live door come from `nowBandLine`
            (src/lib/home-hero-route.ts, pinned): an `active` row whose run has ENDED says the return
            sentence the hero says — no elapsed clock, no 실시간 보기, no VoiceOver live action. */}
        {liveNow.length > 0 && (
          <View style={s.nowBand}>
            <Row style={{ gap: 6 }}>
              <Text style={s.nowKick}>지금</Text>
              <View style={s.livePillSm}><Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>● LIVE</Text></View>
            </Row>
            {liveNow.map((b, i) => {
              // 경과·대기는 실소인에서만 온다. 없으면(또는 1분 미만이면) 절이 통째로 빠진다 (nowBandLine).
              const band = nowBandLine(b);
              const line = band.line;
              const sub = band.sub ?? `${b.routeName} · ${bookingKmLabel(b.km)}`;
              return (
                <Pressable
                  key={b.id}
                  onPress={() => open(b)}
                  style={({ pressed }) => [i > 0 && s.nowRowDiv, pressed && { backgroundColor: paper.wash }]}
                  accessibilityRole="button"
                  accessibilityLabel={line}
                  accessibilityActions={band.liveDoor ? LIVE_A11Y_ACTIONS : undefined}
                  onAccessibilityAction={(e) => { if (band.liveDoor && e.nativeEvent.actionName === 'live') openLive(b.id); }}
                >
                  <Text style={s.nowT}>{line}</Text>
                  <Text style={s.nowS}>{sub}</Text>
                  {/* 실시간 지도는 러닝이 실제로 시작된 뒤에만 존재한다 — picked_up 은 아직 출발 전이라
                      버튼이 없고, 그 사실을 위 서브라인이 말한다 (없는 화면으로 보내는 버튼 금지). */}
                  {band.liveDoor && (
                    <Pressable
                      onPress={(e) => { e.stopPropagation(); openLive(b.id); }}
                      style={({ pressed }) => [s.goLiveBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                      accessibilityRole="button" accessibilityLabel="실시간 보기"
                    >
                      <Text style={s.liveInk}>● 실시간 보기 ›</Text>
                    </Pressable>
                  )}
                </Pressable>
              );
            })}
          </View>
        )}

        <View style={{ paddingHorizontal: 16 }}>
        {/* 주간/월간 데드 토글 은퇴 (ui-audit P1) — 기능이 생길 때 복귀 */}

        {/* filters (functional) */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }} contentContainerStyle={{ gap: 8 }}>
          {FILTERS.map((f, i) => (
            <Pressable
              key={f.label}
              onPress={() => setFilterIdx(i)}
              accessibilityRole="radio"
              accessibilityState={{ selected: filterIdx === i }}
              style={[s.filter, { backgroundColor: filterIdx === i ? f.sel : f.tint, borderColor: filterIdx === i ? f.sel : '#EEE' }]}
            >
              <Text style={{ fontSize: 15, fontWeight: filterIdx === i ? '800' : '700', color: filterIdx === i ? f.selFg : f.tintFg }}>{f.label}</Text>
            </Pressable>
          ))}
        </ScrollView>

        </View>

        {/* agenda — 풀와이드 밴드 (모던 패스: 카드 수프 → 엣지-투-엣지) */}
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center' }}>일정 불러오는 중…</Text>
          </View>
        )}
        {/* 라우드-페일 스트립 — 실패는 빈 일정으로 분장하지 않는다 */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>일정을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && visible.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', lineHeight: 23 }}>
              {/* [2026-08-10 감사] 슬라이드 예약은 은퇴한 제스처였다 — 죽은 안내 문구 교정.
                  [2026-08-19] 'GO 버튼'도 같은 운명 — 랩 ⑧ v2가 GO 디스크를 은퇴시키고 홈 히어로를
                  두 문(지금 찾기 / 예약하기)으로 바꿨다. 화면에 없는 버튼으로 안내하지 않는다. */}
              {/* [B② 2026-08-24] 세 번째 갈래가 필요해졌다: 진행 중인 러닝 하나만 있는 계정은 그
                  행이 위 밴드로 올라가 목록이 비는데, 그때 「이 조건의 일정이 없어요」는 '전체' 칩을
                  스스로 반박한다 (화면에 러닝이 보이는데 없다고 말한다). */}
              {/* [onboarding-first-run-12 2026-09-25] 두 번째 줄은 보호자를 홈으로 돌려보냈는데,
                  이 화면의 헤더에 같은 문(＋)이 이미 있다 — 다른 화면으로 가라는 안내와 바로
                  여기 있는 문이 한 화면에서 서로를 반박했다. 사실 하나만 남기고, 방향은 ＋ 가 쥔다. */}
              {liveBookings.length === 0
                ? '예정된 러닝이 없어요'
                : filterIdx === 0 && liveNow.length > 0
                  ? '지금 진행 중인 러닝 외에는 일정이 없어요'
                  : '이 조건의 일정이 없어요'}
            </Text>
            {/* [fix/owner-inflight-truth · less-is-more-1] The TRUE empty (no bookings at all) gets
                one labelled way forward. Its only door was the header ＋ — a glyph drawn exactly
                like the back key (DESIGN.md chrome header). A filtered or band-only empty stays
                text: there, the owner has bookings and the chips/band are the way forward. This is
                not the retired footer CTA (less-is-more-18): that one drew unconditionally, under
                every list; this exists only when there is nothing else on the screen to do. */}
            {liveBookings.length === 0 && (
              <PaperBtn label="러닝 예약하기" style={{ marginTop: 14 }} onPress={startNewBooking} />
            )}
          </View>
        )}
        {/* [B①] 다가오는 순서 → 지난 일정 구분선 → 지난 것들. 카드 본체는 한 벌이다
            (renderGroup) — 두 벌로 갈라 두면 한쪽에만 수리가 붙는 날 조용히 어긋난다. */}
        {future.map((g) => renderGroup(g, 'f'))}
        {past.length > 0 && (
          <View style={s.divPast}>
            <Text style={s.divPastTx}>지난 일정</Text>
            <View style={s.divPastLine} />
          </View>
        )}
        {past.map((g) => renderGroup(g, 'p'))}
        {/* [less-is-more-18 2026-09-25] 목록 끝의 대시드 CTA 는 은퇴했다. 스타일 이름은
            「추가 슬롯」 어포던스였지만 실제로는 **무조건** 그려져, 헤더의 ＋ 와 같은 화면에서 같은
            곳(/owner/request)으로 가는 두 번째 문이 됐다 — 그리고 빈 상태에서는 「홈으로 가세요」
            안내 바로 아래에 앉아 그 안내를 반박했다. 문은 헤더의 ＋ 하나로 족하다. */}
      </ScrollView>
      {/* 시스템 바 스트립 — 날짜 그룹 라벨과 카드 상단이 시계 뒤로 지나가던 것 (실측 2026-08-19).
          ScrollView '뒤'가 아니라 '위'에 있어야 콘텐츠가 그 아래로 흐른다. */}
      <StatusBarCover />
      </TabSwipe>
      <BottomNav />

      {/* ---------- booking management sheet [HIG N8] ----------
          hand-rolled transparent slide modal + tap-only backdrop + fake grabber → PaperSheet
          (presentationStyle="pageSheet"): swipe-down dismiss, and the dismiss control on the
          LEADING edge instead of only a backdrop tap VoiceOver could not name.
          ⚠ No 완료 on the trailing edge and that is the honest reading of this sheet, not an
          omission: detail mode is a hub with several exits (취소 · 러너 변경 · 다시 예약) and
          cancel mode's commit is the destructive button below, whose label carries the server's
          fee quote. Neither is a Done. The header title names the mode so the two are not one
          screen that silently changed under you; every handler below is untouched — the leading
          닫기 and the swipe both call the same `close` that `onRequestClose` already called. */}
      <PaperSheet visible={!!selected} title={sheetMode === 'detail' ? '예약 상세' : '일정 취소'} onClose={close}>
        {selected && runner && (
          <View style={s.sheet}>
            <ScrollView showsVerticalScrollIndicator={false} style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 12, paddingBottom: 36 }}>
              {sheetMode === 'detail' ? (
                <>
                  {/* header */}
                  <Row style={{ justifyContent: 'space-between' }}>
                    <View>
                      <Text style={{ fontSize: 15, color: paper.ink }}>{selected.dateLabel}</Text>
                      {/* Oswald numerals (900 = numbers+titles law) — lineHeight 32 >= 1.2x (BUG A) */}
                      <Text style={[{ fontSize: 25.5, fontWeight: '900', color: paper.ink, marginTop: 2, lineHeight: 32 }, nf]}>
                        {selected.timeLabel} · {selected.dogName}
                      </Text>
                    </View>
                    <View style={[s.statusPill, { backgroundColor: stFor(selected).bg, alignSelf: 'flex-start' }]}>
                      <Text style={{ fontSize: 15, fontWeight: '800', color: stFor(selected).fg }}>
                        {stFor(selected).label}
                      </Text>
                    </View>
                  </Row>

                  {/* [T4] 지각 알림 — 히어로의 「일정에서 정리하기」가 도착하는 자리다. 상태 필은
                      '확정됨'이라고만 말하는데, 그 확정이 16일 전이면 사실의 절반이다.
                      ⚠ actions 를 넘기지 않는다: 이 시트는 이미 자기 출구(취소·러너 변경·다시 예약)를
                      아래에 갖고 있고, 그 취소가 서버 견적(quote_cancel_fee)을 그대로 보여준다(2026-08-25 미러 은퇴,
                      네 갈래 미러). 여기서 버튼을 또 그리면 두 번째 코랄이거나, 값을 모르는 중복
                      출구가 된다 — 알림은 사실만 말하고 문은 아래 것을 쓴다. */}
                  <LateNotice
                    late={lateness({ scheduledAt: selected.scheduledAt ?? null, rawStatus: selected.rawStatus,
                                     arrivedAt: selected.arrivedAt ?? null, km: selected.km,
                                     startedAt: selected.startedAt ?? null,
                                     // [F7] 커스터디는 status 만으로 판정할 수 없다 (lateness.ts 참조)
                                     ownerHandoffAt: selected.ownerHandoffAt ?? null,
                                     runnerHandoffAt: selected.runnerHandoffAt ?? null })}
                    side="owner"
                    dogName={selected.dogName}
                    runnerName={selected.runnerName}
                  />

                  {/* [0117 stage 2] 체크인 답 표면 — 계획 §13/§15 T4 가 가리키는 그 자리, 지각
                      알림 **바로 아래**다. LateNotice 는 사실을 말하고(자기 파일 9줄: "이 컴포넌트는
                      답을 받지 않는다"), 이 컴포넌트가 답을 받는다.
                      · 서버가 체크인을 열지 않았으면 아무것도 그리지 않는다 — 시계는 아직
                        ops_flags.late_protocol_live_since 로 꺼져 있고, 그동안 이 자리는 빈 자리다.
                      · 코랄을 쓰지 않는다: 이 시트의 강조 예산은 아래 취소·러너 변경 문이 갖는다.
                      · onAnswered → load(): 답이 예약 상태를 바꿨을 수 있으니 목록을 다시 읽는다.
                        cancelBooking 성공 후 이 화면이 이미 하는 것과 같은 처리다. */}
                  <CheckinAnswer
                    key={selected.id}
                    bookingId={selected.id}
                    side="owner"
                    rawStatus={selected.rawStatus}
                    onAnswered={load}
                  />

                  {/* route card — 예약 행이 실제로 들고 있는 값만. 목업 특징칩·점검 도장·설명 퇴역 (item 6).
                      '안심 코스 · N.NN 점검' 도장은 실 checked_at이 있을 때만 찍힌다 — 지금 이 행에는 없다. */}
                  <View style={s.sheetCard}>
                    <Row style={{ gap: 5 }}>
                      <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{selected.routeName}</Text>
                      {/* [리뷰 F8] ✓ 인증 도장 은퇴 — 이 행엔 checked_at 실데이터가 없다. 근거 없는 검증 마크 금지 */}
                      {/* Labelled for the same reason as the list card: the name beside it can already
                          end in the ROUTE's km (0100), while this number is the BOOKING's.
                          15 is trunk's post-sweep size, not this commit's original 14. */}
                      <Text style={{ fontSize: 15, color: paper.dim, alignSelf: 'center' }}>{bookingKmLabel(selected.km)}</Text>
                    </Row>
                    {/* 코스 실루엣 — 네 가지 사실을 네 가지로 (owner-journey-7, 위 effect 참조).
                        코스가 없으면 아무것도 그리지 않는다: 이름 줄이 이미 「코스 미지정」이라고
                        말했고, 같은 말을 두 번 하지 않는다. */}
                    {routeState === 'loading' && (
                      <View style={s.sheetMapBox} accessibilityLabel="코스 경로를 불러오는 중">
                        <Text style={s.sheetMapTxt}>불러오는 중…</Text>
                      </View>
                    )}
                    {routeState === 'err' && (
                      <View style={[s.sheetMapBox, { borderColor: paper.critical }]}>
                        <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>
                          코스 경로를 불러오지 못했어요
                        </Text>
                        {/* payRetry 는 왼쪽 정렬이 기본이다 (결제 스트립은 좌측 정렬 블록) —
                            가운데 정렬된 이 박스에서는 자기 정렬만 덮어쓴다. 44pt 타깃은 그대로. */}
                        <Pressable onPress={() => setRouteTry((n) => n + 1)} style={[s.payRetry, { alignSelf: 'center' }]} accessibilityRole="button">
                          <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>
                            다시 시도
                          </Text>
                        </Pressable>
                      </View>
                    )}
                    {/* 다크 플레이트 유지 — HeatTrace 는 어두운 면 위에서 그리도록 만들어졌다
                        (request.tsx·report.tsx 와 같은 문법). 점이 하나뿐인 행은 선이 아니다. */}
                    {routeState === 'ready' && routeInfo && routeInfo.trace.length > 1 && (
                      <View style={s.sheetMapPlate}>
                        <HeatTrace points={traceToBox(routeInfo.trace)} width={SHEET_MAP_W} height={SHEET_MAP_H} />
                      </View>
                    )}
                  </View>

                  {/* predictions */}
                  <View style={s.sheetCard}>
                    <Row style={{ justifyContent: 'space-around' }}>
                      {/* ⚠ The total is COMPUTED, not a constant. It used to read a literal
                          "~65분" beside a real per-booking `runMin`, so a 10 km booking rendered
                          「예상 러닝 약 80분 / 픽업·인계 포함 ~65분」 — a total smaller than its own
                          part. Same km*8+25 outing formula the request screen uses. */}
                      <Pred label="예상 러닝" value={`약 ${runMin}분`} sub={`픽업·인계 포함 약 ${Math.round(selected.km * 8 + 25)}분`} />
                      <View style={s.vDiv} />
                      <Pred label="예상 페이스" value={selected.paceLabel} sub={`${selected.km}km`} />
                      <View style={s.vDiv} />
                      <Pred label="예상 결제" value={`${selected.price.toLocaleString()}원`} sub="완주 기준" />
                    </Row>
                  </View>

                  {/* runner — before acceptance there IS no runner: a card with a "러" monogram
                      and "러너를 찾고 있어요 러너" is a person who does not exist. Pre-accept the
                      card becomes one quiet fact line (review 2026-08-19).
                      ⚠ The gate is `!selected.matched` — i.e. the booking has no `runner_id` —
                      NOT a list of pre-accept statuses (2026-08-20). The status list missed every
                      booking that ended WITHOUT ever matching: a cancelled or expired row still
                      rendered the person-shaped card, monogram 「매」 and all, reading its name off
                      api.ts's 「매칭 중 러너」 placeholder. That was unreachable while the sheet
                      refused to open for unmatched bookings; opening it (see `open()` above) made
                      it reachable, so the gate moves to the fact that actually decides it. */}
                  {!selected.matched ? (
                    <View style={s.sheetCard}>
                      <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>
                        {selected.rawStatus === 'runner_pending' ? '지명한 러너의 응답을 기다리는 중'
                          : CHAT_PRE_ACCEPT.includes(selected.rawStatus ?? '') ? '러너를 찾는 중'
                            : '러너가 정해지지 않았어요'}
                      </Text>
                      <Text style={{ fontSize: 15, color: paper.dim, marginTop: 6, lineHeight: 19 }}>
                        {CHAT_PRE_ACCEPT.includes(selected.rawStatus ?? '')
                          ? '러너가 수락하면 여기에 러너 정보와 채팅이 열려요'
                          : '이 예약은 러너가 정해지기 전에 끝났어요'}
                      </Text>
                    </View>
                  ) : (
                  <View style={s.sheetCard}>
                    <Row style={{ gap: 12 }}>
                      {/* [2026-09-23] 「실러너 · 상세 프로필 준비 중」 was a lie about our own product:
                          `/runner-profile/[id]` has been live for weeks and owner home, 매칭 and
                          레이더 all link to it. This card was the one place that told the owner the
                          page did not exist yet — on the booking they had already paid for.
                          ⚠ The monogram + identity block is now ONE button to that page. The chat
                          chip stays a SIBLING, never a child: a Pressable inside a Pressable gives
                          one tap two owners.
                          ⚠ `selected.runnerId` (api.ts `mapMyBooking`) is the real profile uuid and
                          the route takes a PROFILE id (`runners.profile_id` is that table's PK,
                          0001:58) — the same value `owner/home.tsx:789` pushes. It is `''` before
                          matching, which cannot be reached here: this whole branch is gated on
                          `selected.matched`, and api.ts sets `matched: !!r.runner_id` (:6268). The
                          `runnerId ?` guard below is the belt for a row that ever arrives with the
                          two out of step — no button rather than a dead one. */}
                      {selected.runnerId ? (
                        <Pressable
                          onPress={() => { const rid = selected.runnerId; close(); router.push(`/runner-profile/${rid}`); }}
                          accessibilityRole="button"
                          accessibilityLabel={`${runner.name} 러너 프로필 보기`}
                          style={({ pressed }) => [{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, opacity: pressed ? 0.6 : 1 }]}
                        >
                          <Monogram char={runner.char} bg={runner.color} size={46} />
                          <View style={{ flex: 1 }}>
                            <Row style={{ gap: 6 }}>
                              <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{runner.name} 러너</Text>
                              {runner.badges.map((b) => (
                                <View key={b} style={s.badgePill}><Text style={{ fontSize: 15, fontWeight: '800', color: '#4a6d1f' }}>{b}</Text></View>
                              ))}
                            </Row>
                            {/* Ink, not the grey ramp — this file's own header carries the law
                                (DESIGN.md §7a-bis): the ramp marks what a customer may SKIP, and
                                the label of a button is never that. The retired sentence was dim
                                because it was an apology; this one is an action. */}
                            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.ink, marginTop: 3 }}>프로필 보기</Text>
                          </View>
                        </Pressable>
                      ) : (
                        <>
                          <Monogram char={runner.char} bg={runner.color} size={46} />
                          <View style={{ flex: 1 }}>
                            <Row style={{ gap: 6 }}>
                              <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{runner.name} 러너</Text>
                              {runner.badges.map((b) => (
                                <View key={b} style={s.badgePill}><Text style={{ fontSize: 15, fontWeight: '800', color: '#4a6d1f' }}>{b}</Text></View>
                              ))}
                            </Row>
                          </View>
                        </>
                      )}
                      {/* [0114 · ui2-1] 이 카드는 **무조건** 그려지고 runner.name은 미매칭 예약에서
                          "러너를 찾고 있어요"로 떨어지므로, 수락 전에도 이 칩이 떠 있었다. 0114 이후
                          서버는 그 예약의 chat_threads INSERT를 거부한다 — 탭한 뒤 실패하는 문이다.
                          숨기지 않고 **비활성 + 이유**로 그린다: 채팅이 언젠가 열린다는 사실 자체가
                          보호자에게 필요한 정보이고, 사라진 칩은 그 말을 못 한다. */}
                      {CHAT_PRE_ACCEPT.includes(selected.rawStatus ?? '') ? (
                        <View
                          style={[s.chatChip, s.chatChipOff]}
                          accessible
                          accessibilityLabel="채팅 — 러너가 수락하면 열려요"
                          accessibilityState={{ disabled: true }}
                        >
                          <Text style={{ fontSize: 15, fontWeight: '800', color: paper.faint }}>채팅</Text>
                        </View>
                      ) : (
                        <Pressable
                          style={({ pressed }) => [s.chatChip, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                          onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/chat', params: { bid } }); }}
                          accessibilityRole="button"
                          accessibilityLabel={unreadBadgeLabel(chatUnread, selected.id)
                            ? `채팅 — ${unreadBadgeLabel(chatUnread, selected.id)}`
                            : '채팅'}
                        >
                          {/* [0212] 배지는 서버가 센 행 수다. 모르면(로딩·실패·이 예약이 답에 없음)
                              칩은 예전 그대로 — 0을 그리면 갖고 있지 않은 수를 주장하는 것이다. */}
                          <Row style={{ gap: 6, alignItems: 'center' }}>
                            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>채팅</Text>
                            {unreadBadge(chatUnread, selected.id) ? (
                              <Text style={s.chatChipBadge}>{unreadBadge(chatUnread, selected.id)}</Text>
                            ) : null}
                          </Row>
                        </Pressable>
                      )}
                    </Row>
                    {CHAT_PRE_ACCEPT.includes(selected.rawStatus ?? '') && (
                      <Text style={{ fontSize: 15, color: paper.ink, marginTop: 8, lineHeight: 19 }}>
                        러너가 수락하면 채팅을 열 수 있어요
                      </Text>
                    )}
                    {runner.desc && (
                      <Text style={{ fontSize: 15, color: paper.text, marginTop: 10, lineHeight: 19.5 }}>{runner.desc}</Text>
                    )}
                  </View>
                  )}

                  {/* 결제 내역 (charge slice) — 청구는 러닝이 끝난 뒤에 생긴다. 섹션은 영수증 행이
                      있거나, 예약이 완료됐거나, **서버가 할 말이 있을 때** 렌더한다. 정산 전
                      '결제 내역 없음'은 알림이 아니라 소음이라 awaiting_settlement는 스스로
                      말하지 않는다 (PAYMENT_STATES_THAT_SPEAK). */}
                  {showPayments && (
                    <View style={s.sheetCard}>
                      <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>결제 내역</Text>

                      {/* 🔴 [0207] 한 줄의 진실 — 서버가 말한 상태. 행 수로 추론하지 않는다.
                          로딩은 0이 아니다: 값이 없을 때는 골격을 그리고, 값이 한 번 그려진 뒤에는
                          재시도가 실패해도 지우지 않는다. */}
                      {payFace ? (
                        <View style={{ marginTop: 8 }}>
                          <Text style={{ fontSize: 16, fontWeight: '800', lineHeight: 21,
                                         color: payFace.tone === 'alert' ? paper.critical : paper.ink }}>
                            {payFace.text}
                          </Text>
                          {payFace.sub && (
                            <Text style={{ fontSize: 15, lineHeight: 20, color: paper.text, marginTop: 3 }}>
                              {payFace.sub}
                            </Text>
                          )}
                          {/* 죽은 버튼 금지 — 이 문은 진짜로 열리고 그 끝에 진짜 재청구가 있다.
                              재청구 동작 자체는 /payments 하나가 갖는다 (owner/pay.tsx가 같은
                              이유로 같은 결정을 했다: 한 돈 동작이 두 화면에 살면 갈라진다). */}
                          {payFace.canRetry && (
                            <Pressable onPress={() => { close(); router.push('/payments'); }}
                                       style={s.payRetry} accessibilityRole="button">
                              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>
                                결제 관리에서 다시 시도
                              </Text>
                            </Pressable>
                          )}
                        </View>
                      ) : payStateLoading ? (
                        <View style={{ marginTop: 10 }} accessibilityLabel="결제 상태를 불러오는 중">
                          <View style={s.paySkelWide} />
                          <View style={s.paySkelNarrow} />
                        </View>
                      ) : null}

                      {/* 실패는 실패로. ⚠ payFace가 이미 있으면 그 아래에 붙는다 — 참인 문장을
                          실패 줄로 갈아 끼우면 사라진 자리가 다시 '아무 일도 없었다'로 읽힌다. */}
                      {(payStateErr || payErr) && (
                        <View style={{ marginTop: 10 }}>
                          <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>
                            {payFace ? '결제 정보를 새로 불러오지 못했어요' : '결제 내역을 불러오지 못했어요'}
                          </Text>
                          <Pressable
                            onPress={() => { loadPayments(selected.id); loadPayState(selected.id); }}
                            style={s.payRetry} accessibilityRole="button">
                            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
                          </Pressable>
                        </View>
                      )}

                      {/* 예약 상세 → 결제 내역 → 영수증 상세 (pay-rebuild-lab Ⓒ 온디맨드의
                          두 진입로 중 하나). 시트를 닫고 넘어간다 — 다른 액션 행들과 같은 문법. */}
                      {payRows.map((p) => (
                        <PaymentRow
                          key={p.orderId}
                          p={p}
                          showDog={false}
                          onPress={() => { const bid = p.bookingId; close(); router.push({ pathname: '/owner/pay', params: { bid } }); }}
                        />
                      ))}
                    </View>
                  )}

                  {/* actions — 상태별: 진행 중엔 라이브만, 완료엔 기록만, 시작 전에만 변경·취소 */}
                  {/* [fix/owner-inflight-truth · owner-journey-2] The RETURN phase comes before the
                      live arm. `active` + `run_ended_at` is a run that has ENDED: 「러닝이 진행 중이에요」
                      and a live map were false, and the one thing owed — the owner's return stamp,
                      which lives on the bid-scoped report (⑫, 0188) — had no door here. The sentence
                      is the hero's (`returnSentence`); the no-cancel note stays, because the server
                      refuses a cancel in this phase exactly as it does mid-run. */}
                  {selected.status === 'active' && returnOwed(selected) ? (
                    <>
                      <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', paddingVertical: 10, lineHeight: 20 }}>
                        러닝이 끝났어요 — {returnSentence(`${selected.runnerName} 러너`, selected.dogName)}
                      </Text>
                      <PaperBtn
                        label="반환 확인하기"
                        style={{ marginTop: 6 }}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid } }); }}
                      />
                      <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', marginTop: 12, lineHeight: 18.5 }}>
                        이미 시작된 러닝은 일정 변경·취소가 불가능해요{'\n'}긴급 상황은 안심 센터 SOS를 이용해주세요
                      </Text>
                    </>
                  ) : selected.status === 'active' ? (
                    <>
                      <Pressable
                        style={({ pressed }) => [s.primaryAction, { backgroundColor: '#ffe9e2', borderWidth: 1, borderColor: '#ffc9b8', transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => { draft.bookingId = selected.id; close(); router.push('/owner/live'); }}
                        accessibilityRole="button"
                        accessibilityLabel="실시간 보기"
                      >
                        {/* [ui-consistency-7] actionInk on the #ffe9e2 face — the old ink and sub ink
                            measured 3.64:1 and 3.57:1; actionInk is 5.72:1. The face is Sean's
                            2026-08-26 live-state keep and is untouched. */}
                        <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.actionInk }}>● 실시간 보기</Text>
                        {/* [정직 배치 2.5 · Sean D3=B] 앱 전체에서 바디캠을 '앞으로'라고 말하는 자리는 여기 한 곳뿐 */}
                        <Text style={{ fontSize: 15, color: paper.actionInk, marginTop: 2 }}>러닝이 진행 중이에요 — GPS 경로를 실시간으로 지켜보세요</Text>
                        <Text style={{ fontSize: 15, color: paper.actionInk, marginTop: 2 }}>바디캠 뷰는 준비 중이에요</Text>
                      </Pressable>
                      <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', marginTop: 12, lineHeight: 18.5 }}>
                        이미 시작된 러닝은 일정 변경·취소가 불가능해요{'\n'}긴급 상황은 안심 센터 SOS를 이용해주세요
                      </Text>
                    </>
                  ) : selected.status === 'handoff' ? (
                    <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', marginTop: 16, lineHeight: 19.5 }}>
                      인계가 완료됐어요 — 러너가 러닝을 시작하면{'\n'}실시간 보기가 열려요 · 변경·취소는 불가능해요
                    </Text>
                  ) : selected.status === 'completed' ? (
                    <>
                      {/* [ui-consistency-2] 손으로 만 코랄 립 → 버튼 매트릭스. 이 시트의 로컬 립
                          스타일은 PaperBtn primary 와 **같은 산식**(면 paper.action, 쉼 4px ·
                          눌림 translateY(3)+1px, 17/800 흰 라벨)을 한 벌 더 들고 있었을 뿐이다 —
                          한 값에 주인이 둘이면 한쪽만 고쳐지는 날이 온다. 그 스타일들은 은퇴했다.
                          [2026-08-10 density audit] 서브라인은 그때 잘렸다. */}
                      <PaperBtn
                        label="러닝 리포트 보기"
                        style={{ marginTop: 16 }}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid } }); }}
                      />
                      {/* 인증샷 바로가기 — 완료 러닝의 자랑 동선 한 탭 단축 (공유가 곧 마케팅)
                          [ui-consistency-10] quiet, not secondary: an optional flourish beside the
                          report primary, and the rebook row under it already wears secondary. */}
                      <PaperBtn
                        label="인증샷 만들기"
                        variant="quiet"
                        style={{ marginTop: 8 }}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid, shot: '1' } }); }}
                      />
                      {rebookRow}
                    </>
                  ) : selected.status === 'cancelled' ? (
                    // 취소·만료·환불 진행 — 이 예약에 대한 관리 액션은 없다. 변경 요청은 서버가 확정
                    // 전용(409)이라 죽은 버튼이 되고, 취소하기는 재취소가 된다.
                    // ⚠ [owner-journey-6] 문장은 남기되 막다른 골목은 아니다: 다시 예약은 **이 예약에
                    //   대한 동작이 아니라 새 예약**이므로 위 문장과 모순되지 않는다. 표시 어휘가
                    //   뭉갠 네 상태(cancelled_owner · cancelled_runner · expired · refund_pending)가
                    //   모두 이 갈래로 오고, 그중 만료는 우리가 러너를 못 찾은 건이라 이 문이 가장
                    //   필요한 자리다 — 배지는 이미 「매칭 만료」라고 말하고 있다.
                    <>
                      <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', paddingVertical: 10 }}>
                        {selected.rawStatus === 'expired'
                          ? '시작 시간까지 러너를 찾지 못했어요 — 이 예약은 더 진행되지 않아요'
                          : '취소된 일정이에요 — 이 예약으로 더 진행할 작업은 없어요'}
                      </Text>
                      {rebookRow}
                    </>
                  ) : (selected.rawStatus === 'no_show' || selected.rawStatus === 'incident_review') ? (
                    // 불발·확인 중 — 서버 전이상 취소도 변경도 불가(refund_pending만 합법) → 이 예약에
                    // 대한 액션 없음이 정직. 이전엔 STATUS_MAP 폴백 'pending'으로 죽은 취소 버튼을 그렸다.
                    // ⚠ 다시 예약 문은 **불발에만** 붙는다. 확인 중은 아직 끝나지 않은 사건이고,
                    //   그 위에 「다시 예약」을 얹으면 판정 전에 사건이 끝났다고 말하는 것이 된다.
                    <>
                      <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', paddingVertical: 10 }}>
                        {selected.rawStatus === 'no_show'
                          ? '불발로 처리된 일정이에요 — 이 예약으로 더 진행할 작업은 없어요'
                          : '확인이 진행 중인 일정이에요 — 처리되면 알림으로 알려드릴게요'}
                      </Text>
                      {/* [fix/owner-inflight-truth · owner-journey-1] A review whose run ENDED
                          (`run_ended_at`) is 0226's unstamped return: nobody confirmed it, and the
                          owner's stamp is still accepted (`confirm_return_tx` takes incident_review,
                          0096 §2; the report's ⑫ allow-list draws it). This was reachable only from
                          the push. The case sentence above stays true — a person is looking — and
                          the owner's own half is one tap away. */}
                      {returnOwed(selected) && (
                        <PaperBtn
                          label="반환 확인하기"
                          style={{ marginTop: 6 }}
                          onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid } }); }}
                        />
                      )}
                      {selected.rawStatus === 'no_show' ? rebookRow : null}
                    </>
                  ) : (
                    <>
                      {/* 러너가 픽업 이동 중(runner_enroute) — 표시 어휘는 '확정'으로 뭉개지지만 서버는
                          변경은 여전히 거부한다(request_reschedule: confirmed 전용). 취소는 0066부터
                          합법(50% 수수료 = 러너 보상) — 아래 취소 링크가 이 상태에서도 열리고, 확인
                          시트가 50% 티어를 커밋 전에 명시한다. 여기는 변경 마감 사실만 말한다. */}
                      {selected.rawStatus === 'runner_enroute' && (
                        <Text style={{ fontSize: 15, color: paper.ink, textAlign: 'center', paddingVertical: 10 }}>
                          러너가 픽업으로 이동 중이에요 — 일정 변경은 마감됐어요
                        </Text>
                      )}
                      {/* 일정 변경 요청은 확정 예약에서만 — 서버 규칙(request_reschedule: confirmed 전용 409)과
                          같은 문장. 표시 상태가 아니라 서버 원상태(rawStatus)로 게이트한다 — 표시 어휘는
                          runner_enroute를 '확정'으로 뭉개므로 그걸 믿으면 이동 중 죽은 버튼이 생긴다. */}
                      {selected.rawStatus === 'confirmed' && (
                        <>
                          {/* [ui-consistency-2] 손으로 만 코랄 립 → 버튼 매트릭스 (위 리포트 버튼과 같은 이유).
                              ⚠ 서브라인은 면 **밖으로** 나왔다. 코랄 면 위의 paper.text 는 실측 1.88:1 로
                                AA 근처에도 가지 못했다 — 같은 파일의 다른 코랄 서브라인들이 밝은
                                paper.wash 를 쓰는 이유가 그것이고, 이 줄만 어두운 본문색이었다.
                                캔버스 위로 내리면 문장은 그대로 남고 읽히기까지 한다. */}
                          <PaperBtn
                            label="일정 변경 요청"
                            style={{ marginTop: 16 }}
                            onPress={() => {
                              // 제안 화면 직행 (0016) — 취소·재예약이 아니라 러너 동의 기반 시간 변경
                              const bid = selected.id;
                              close();
                              router.push({ pathname: '/owner/reschedule', params: { bid } });
                            }}
                          />
                          <Text style={{ fontSize: 15, color: paper.text, textAlign: 'center', marginTop: 8, lineHeight: 20 }}>
                            {runner.name} 러너의 가능 시간에서 새 시간을 제안해요
                          </Text>
                        </>
                      )}
                      {/* 러너 변경 = 재지명 (이 예약 그대로). 확정 전에만 — 확정은 계약이고,
                          서버도 matching/runner_pending에서만 request_runner를 받는다.
                          예전엔 /owner/request로 되돌려 두 번째 예약을 만들었고 dog_slot_clash에 걸렸다. */}
                      {(selected.rawStatus === 'matching' || selected.rawStatus === 'runner_pending') && (
                        <>
                          <PaperBtn
                            label="러너 변경"
                            variant="secondary"
                            style={{ marginTop: 8 }}
                            onPress={() => {
                              draft.bookingId = selected.id;
                              close();
                              router.push({ pathname: '/owner/matching', params: { mode: 'rebook', current: selected.runnerProfileId ?? '', pace: selected.paceLabel ?? '' } });
                            }}
                          />
                          <Text style={s.btnSub}>이 예약 그대로 다른 러너에게 다시 요청해요</Text>
                        </>
                      )}
                      {/* [0066] 이동 중 취소가 서버 전이로 열렸다(runner_enroute → cancelled_owner,
                          50% 수수료 = 러너 보상) — 숨김 게이트 은퇴. 링크 라벨이 티어를 예고하고,
                          확인 시트(fee/feeRate)가 정확한 % 와 배분을 커밋 전에 다시 명시한다. */}
                      {/* 클럽 위탁 예약은 이 사다리(0066)의 대상이 아니다 — 클럽은 자체 수수료
                          규정(club_config)과 자체 출구(session_cancel_delegation: 호스트 알림·
                          배정 회수·club_fee_items 기록)를 갖는다. 서버 cancel_owner도 거부하므로
                          여기서 취소 버튼을 그리면 죽은 버튼이 된다 — 대신 그 출구로 보낸다. */}
                      {selected.clubSessionId ? (
                        <Pressable
                          style={s.cancelLink}
                          onPress={() => { setSelected(null); router.push(`/club/session/${selected.clubSessionId}`); }}
                          accessibilityRole="button"
                        >
                          <Text style={{ fontSize: 16, fontWeight: '700', color: paper.ink }}>
                            클럽 세션 화면으로 ›
                          </Text>
                          {/* '취소하기'라고 쓰지 않는다 — 인계 이후(runner_enroute~)의 위탁은
                              클럽 규정상 취소가 아니라 케이스로 다뤄지고, 서버도 그렇게 답한다.
                              여기서 '취소'를 약속하면 다음 화면이 거절할 때 그게 거짓말이 된다. */}
                          <Text style={{ fontSize: 15, color: paper.ink, marginTop: 2 }}>
                            위탁 예약은 클럽 세션 화면에서 처리해요 — 취소 규정도 그곳에 있어요
                          </Text>
                        </Pressable>
                      ) : (
                        <Pressable style={s.cancelLink} onPress={() => setSheetMode('cancel')} accessibilityRole="button">
                          <Text style={{ fontSize: 16, fontWeight: '700', color: paper.critical }}>
                            {/* 티어는 네 팔 미러가 말한다 — 수수료가 0인 예약에 '(수수료 50%)'를
                                달던 자리(이동 중만 표기하던 이분법)의 교정 */}
                            {/* 견적이 오기 전에는 숫자를 예고하지 않는다 — 0 도 % 도 아닌 '없음' */}
                            {quotedFee != null && quotedFee > 0 ? `일정 취소하기 (수수료 ${quotedFee.toLocaleString()}원)` : '일정 취소하기'}
                          </Text>
                        </Pressable>
                      )}
                    </>
                  )}
                  {/* ⟳ 매주 반복 — 상태 · 만들기 · 다시 시작 (0026 · 0077 · 0111)
                      THE DOOR WAS ONE-WAY UNTIL NOW. `0111:193` grants the client exactly one
                      column on `recurring_series` — `update (paused)` — and the only client writer
                      of it wrote `true` (해지). `false` was a capability the server had shipped and
                      nothing in the app could reach, so an owner who stopped their weekly run had
                      to rebuild the series from a new booking. `RecurringCta` draws whichever of
                      the three states is true: no series → 매주 반복으로 바꾸기 · running → the
                      state line the cron will act on · paused → the line plus 반복 다시 시작.
                      `onChanged` re-reads this screen's list so the ⟳ 매주 pill on the row agrees
                      with the sheet. */}
                  <RecurringCta
                    bookingId={selected.id}
                    seriesId={selected.seriesId ?? null}
                    onChanged={load}
                  />
                  {/* 반복 해지 (0026) — 구독은 반드시 끌 수 있어야 한다. 상태 무관 노출 */}
                  {selected.seriesId && (
                    <Pressable style={s.cancelLink} onPress={pauseSeries} accessibilityRole="button">
                      <Text style={{ fontSize: 15, fontWeight: '700', color: paper.ink }}>⟳ 매주 반복 해지</Text>
                    </Pressable>
                  )}
                </>
              ) : (
                <>
                  {/* cancel confirmation — 크리티컬 문법 (criticalWash/critical) 유지 */}
                  <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>일정을 취소할까요?</Text>
                  <Text style={{ fontSize: 15, color: paper.text, marginTop: 6 }}>
                    {selected.dateLabel} {selected.timeLabel} · {runner.name} 러너
                  </Text>

                  {/* [post-pay 2026-08-13] 이 카드는 환불 명세가 아니라 **청구 명세**다.
                      예약 시점에 잡아둔 돈이 없으므로 (§0-bis: 러닝이 끝난 뒤에 청구) 돌려받을
                      금액이라는 개념 자체가 없다 — 취소가 만드는 유일한 돈은 수수료 청구다. */}
                  <View style={s.feeCard}>
                    <FeeLine label="예약 금액" value={`${selected.price.toLocaleString()}원`} />
                    {/* 서버의 절대액 그대로 — % 는 클라이언트 산수라 은퇴했다. 확인 중엔 숫자 대신
                        상태를 말하고(로딩은 0이 아니다), 실패는 아래 스트립이 크게 말한다. */}
                    <FeeLine
                      label="취소 수수료"
                      value={cancelQuote.s === 'ok' ? `${cancelQuote.fee.toLocaleString()}원` : cancelQuote.s === 'err' ? '확인 실패' : '확인 중…'}
                      coral
                    />
                    <View style={{ height: 1, backgroundColor: '#EEE', marginVertical: 10 }} />
                    <FeeLine
                      label="청구 금액"
                      value={cancelQuote.s === 'ok' ? `${cancelQuote.fee.toLocaleString()}원` : '—'}
                      bold
                    />
                    {cancelQuote.s === 'err' && (
                      <Pressable onPress={() => setQuoteTry((t) => t + 1)} style={{ marginTop: 10 }} accessibilityRole="button">
                        <Text style={{ fontSize: 15, fontWeight: '800', color: paper.critical }}>
                          수수료를 확인하지 못했어요 — 다시 시도 ›
                        </Text>
                      </Pressable>
                    )}
                    {/* [0066] 이동 중 티어는 배분 문장이 다르다 — 50% 전액이 이미 출발한 러너의 보상.
                        일반 티어 카피(10%·50/50 배분·24h 무료)는 그대로 생존. */}
                    <Text style={{ fontSize: 15, color: paper.ink, marginTop: 10, lineHeight: 20 }}>
                      {enrouteCancel
                        ? '러너가 이미 픽업으로 출발했어요 — 이동 중 취소 수수료는 전액 시간을 내어 출발한 러너의 보상으로 배분돼요.'
                        : `취소 수수료는 시간을 비워둔 러너에게 ${Math.round(cancelPolicy.runnerShare * 100)}%, 도그스하이에 ${Math.round((1 - cancelPolicy.runnerShare) * 100)}% 배분돼요.\n시작 24시간 전까지는 수수료가 없어요.`}
                    </Text>
                    {/* TODO(widget slice, R3 P3-8): both sentences assume no captured payment —
                        true today, and MORE true after O-5: the conclusion survives but the
                        mechanism named here does not. `payment_ok` is deleted (it never wrote a
                        payments row anyway); today nothing before the run writes one at all —
                        TOSS_ENABLED=false and money is only taken at settle. FALSE for a
                        widget-prepaid booking the day that
                        slice ships. The server already branches on payments.status='confirmed'
                        (cancel_owner.ts isPrepaid); this sheet must branch the same way
                        (fetchBookingPayments) before widget payments go live. */}
                    <Text style={{ fontSize: 15, color: paper.ink, marginTop: 6, lineHeight: 20 }}>
                      {quotedFee == null
                        ? '지금까지 결제된 금액이 없어서 환불은 없어요.'
                        : quotedFee > 0
                          ? '지금까지 결제된 금액이 없어서 환불은 없어요 — 취소 수수료만 청구돼요.'
                          : '지금까지 결제된 금액도, 이번 취소로 청구되는 금액도 없어요.'}
                    </Text>
                  </View>

                  <Pressable
                    style={({ pressed }) => [
                      s.cancelConfirm,
                      cancelQuote.s !== 'ok' && { backgroundColor: paper.disabledFill },
                      { transform: [{ scale: pressed && cancelQuote.s === 'ok' ? 0.96 : 1 }] },
                    ]}
                    disabled={cancelQuote.s !== 'ok'}
                    accessibilityRole="button"
                    accessibilityState={{ disabled: cancelQuote.s !== 'ok' }}
                    onPress={async () => {
                      // 보여주지 못한 가격은 약속하지 못한다 — 견적 없이는 커밋 없음 (§9c의 법)
                      if (cancelQuote.s !== 'ok') return;
                      // 실취소 — 서버 cancel_owner가 수수료 계산 + 상태 전이 (목업 알럿 은퇴, fake-inventory)
                      const bid = selected.id;
                      close();
                      try {
                        const r = await cancelBooking(bid);
                        // [post-pay 2026-08-13] 서버가 돌려주는 사실은 수수료 하나뿐이다 (refund 은퇴).
                        // 잡아둔 돈이 없으니 환불 약속을 할 자리도 없다 — 청구 여부만 말한다.
                        Alert.alert(
                          '취소 완료',
                          r.cancel_fee > 0
                            ? `취소 수수료 ${r.cancel_fee.toLocaleString()}원이 청구돼요\n설정 › 결제 관리에서 결제 내역을 볼 수 있어요`
                            : '청구되는 금액은 없어요',
                        );
                        load();
                      } catch (e) {
                        alertFail('취소 실패', e);
                      }
                    }}
                  >
                    <Text style={{ fontSize: 16.5, fontWeight: '900', color: cancelQuote.s === 'ok' ? '#fff' : paper.dim }}>
                      {cancelQuote.s === 'ok'
                        ? (cancelQuote.fee > 0 ? `수수료 ${cancelQuote.fee.toLocaleString()}원 내고 취소하기` : '수수료 없이 취소하기')
                        : cancelQuote.s === 'err' ? '수수료를 확인한 뒤 취소할 수 있어요' : '수수료 확인 중…'}
                    </Text>
                  </Pressable>
                  <Pressable style={s.cancelLink} onPress={() => setSheetMode('detail')} accessibilityRole="button">
                    <Text style={{ fontSize: 16, fontWeight: '700', color: paper.text }}>돌아가기</Text>
                  </Pressable>
                </>
              )}
            </ScrollView>
          </View>
        )}
      </PaperSheet>
    </View>
  );
}

function Pred({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <View style={{ alignItems: 'center', flex: 1 }}>
      <Text style={{ fontSize: 15, color: paper.dim }}>{label}</Text>
      <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink, marginTop: 3 }}>{value}</Text>
      <Text style={{ fontSize: 15, color: paper.dim, marginTop: 2 }}>{sub}</Text>
    </View>
  );
}

function FeeLine({ label, value, coral, bold }: { label: string; value: string; coral?: boolean; bold?: boolean }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 5 }}>
      <Text style={{ fontSize: 15, color: bold ? paper.ink : paper.text, fontWeight: bold ? '800' : '400' }}>{label}</Text>
      <Text style={{ fontSize: bold ? 16 : 15,   /* [floor] was 14 — below the 15pt detail floor, inside the
        cancel-FEE card. Found by the dim-text agent and out of its brief; fixed here because a
        money line a customer cannot read is the worst place to keep a floor violation. */ fontWeight: bold ? '900' : '600', color: coral ? paper.critical : paper.ink }}>{value}</Text>
    </Row>
  );
}

// T3 원형 소인 (schedule-stamp-lab 확정) — 우체국 소인 문법: FINISHER + 완주 날짜 + DOGS HIGH.
// 인플로우 우측 컬럼 소자 (앱솔루트 아님 → 텍스트·필과 절대 안 겹침). 점선 이너 링 + 보더를
// 무는 화이트 스펙클 4점 = 가벼운 워너웃 (카드 배경이 흰색이라 뷰 4개로 충분, 의존성 0)
function FinisherSeal({ dateLabel }: { dateLabel: string }) {
  const m = dateLabel.match(/(\d+)월\s*(\d+)일/);
  const date = m ? `${m[1].padStart(2, '0')}.${m[2].padStart(2, '0')}` : 'DONE';
  return (
    <View style={s.seal}>
      <View style={s.sealRing} />
      <Text style={{ fontSize: 9.5, fontWeight: '900', letterSpacing: 1.5, color: '#6E9BC5' }}>FINISHER</Text>
      <Text style={{ fontSize: 15, fontWeight: '900', color: '#6E9BC5', marginTop: 1 }}>{date}</Text>
      <Text style={{ fontSize: 6.5, fontWeight: '700', letterSpacing: 1, color: 'rgba(110,155,197,.85)', marginTop: 1 }}>DOGS HIGH</Text>
      {/* 워너웃 스펙클 — 보더 위를 무는 잉크 벗겨짐 */}
      <View style={[s.sealNick, { top: 6, left: 14, width: 4, height: 2.5 }]} />
      <View style={[s.sealNick, { top: 30, right: -1, width: 3, height: 4 }]} />
      <View style={[s.sealNick, { bottom: 8, left: 8, width: 3, height: 3 }]} />
      <View style={[s.sealNick, { bottom: 2, right: 22, width: 4.5, height: 2.5 }]} />
    </View>
  );
}

const s = StyleSheet.create({
  // ＋ 버튼 — 백버튼 문법 (40×40 스퀘어 · 캔버스 · 1px 코랄) — 레거시 이름 유지
  circleBtn: { width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  // viewToggle/viewTab/comingSoon 스타일 퇴역 — 주간/월간 데드 토글과 함께 (ui-audit P1, JSX엔 이미 없음)
  filter: { backgroundColor: '#fff', paddingVertical: 8, paddingHorizontal: 14, borderWidth: 1, borderColor: '#EEE' },
  emptyBox: { marginTop: 24, marginHorizontal: 12, padding: 18, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEE' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { marginTop: 24, marginHorizontal: 12, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  // ── 날짜 그룹 라벨 (B① · 2026-08-24) ──────────────────────────────────────
  // 구조는 그대로(dim 14/800, 거터 12), 앞에 상대 앵커, 뒤에 D-라벨이 붙는다.
  // ⚠ 중첩 Text 의 lineHeight 는 부모에 값이 없으면 iOS 에서 무시된다 — 부모에 먼저 둔다 (BUG A).
  grp: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.dim, paddingHorizontal: 12, marginBottom: 8 },
  grpHead: { color: paper.ink },
  grpD: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.dim },
  // 지난 일정 경계 — 선 하나와 라벨 하나. 아래 것을 접지도 지우지도 않는다 (§7b).
  divPast: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 26, marginBottom: 4, paddingHorizontal: 12 },
  divPastTx: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.dim, letterSpacing: 0.5 },
  divPastLine: { flex: 1, height: 1, backgroundColor: '#EEE' },
  // ── 지금 밴드 (B② · 2026-08-24) ──────────────────────────────────────────
  // 카드가 아니라 띠다: 흰 면 + 뉴트럴 1px + 왼쪽 볼트 레일 3px. 레일이 8px 이었을 때는 카드의
  // 상태 레일과 같은 무게라 '목록의 한 항목'처럼 읽혔다 (사이드탭 실측, 2026-08-24).
  nowBand: {
    marginTop: 14, marginHorizontal: 12, backgroundColor: '#fff',
    borderWidth: 1, borderColor: '#EEE', borderLeftWidth: 3, borderLeftColor: colors.volt,
    paddingVertical: 13, paddingHorizontal: 14,
  },
  nowKick: { fontSize: 15, lineHeight: 18, fontWeight: '800', letterSpacing: 0.6, color: '#4a6d1f' },
  nowT: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink, marginTop: 4 },
  nowS: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 3 },
  nowRowDiv: { marginTop: 11, paddingTop: 11, borderTopWidth: 1, borderTopColor: '#EEE' },
  bookingCard: { flexDirection: 'row', backgroundColor: '#fff', borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEE', marginTop: -1, overflow: 'hidden' },
  rail: { width: 8 }, // 상태 컬러 레일 1.6배 (5→8) — 시맨틱, 페이퍼 이관에서 생존
  // 확정 카드 절취선 — 레일 경계 x=8 중심 (노치 지름 10, 도트 2.5)
  // 크림 은퇴: 노치 = 캔버스 면 + #EEE 보더, 도트 = #EEE (순백 위에서 천공이 살아남는 값)
  perfWrap: { position: 'absolute', left: 3, top: 0, bottom: 0, width: 10, alignItems: 'center' },
  perfNotch: { width: 10, height: 10, borderRadius: 5, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEE' },
  perfDot: { width: 2.5, height: 2.5, borderRadius: 1.25, backgroundColor: '#EEE' },
  recurPill: { backgroundColor: '#e3f0c4', paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  livePillSm: { backgroundColor: '#5a7a3c', paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  statusPill: { paddingVertical: 4, paddingHorizontal: 9 },
  goLiveBtn: {
    marginTop: 11, backgroundColor: '#ffe9e2', alignItems: 'center',
    paddingVertical: 12, borderWidth: 1, borderColor: '#ffc9b8',
  },
  // thumbMap(목업 트레이스 썸네일) 퇴역 — item 6
  // 완료 카드 공유 행 — 카드 하단에 부착된 풀와이드 밴드 (도장을 가리지 않는 위치, Sean 2026-07-29)
  shareRow: { flexDirection: 'row', gap: 8, backgroundColor: paper.canvas, borderBottomWidth: 1, borderColor: '#EEE', marginTop: -1, paddingVertical: 9, paddingHorizontal: 14 },
  // [Sean 2026-08-11] 볼트 그린 은퇴. 이 둘은 완료 카드에 붙는 **동급 보조 액션 한 쌍**이지
  // 화면의 유일한 CTA가 아니다 (§8 강조 예산 = 코랄 선 + CTA 1). 그래서 §3b 보조 버튼 문법으로:
  // 캔버스 면 · 1px 코랄 · 잉크 16/800 · 누르면 wash. 홈의 '일정 변경 / 러너와 채팅' 쌍과 같은 옷이라
  // 앱 전체에서 '나란한 보조 액션 두 개'가 한 가지로만 읽힌다.
  // 라벨도 함께 교정: 14/900 → 16/800 (무게 법: 900은 숫자와 화면 제목만).
  shareBtn: {
    flex: 1, alignItems: 'center', backgroundColor: paper.wash,
    borderWidth: 1, borderColor: paper.line, paddingVertical: 11,
  },
  shareTxt: { fontSize: 16, fontWeight: '800', color: paper.actionInk },
  // T3 원형 소인 — 콘텐츠가 여유 있게 들어가는 84 지름 (랩의 64는 작았음, Sean 피드백)
  // marginTop 6 = 회전 여유. 소인은 인플로우라 겹칠 수 없지만, 8° 회전은 레이아웃 박스 밖으로
  // 위아래 ~5.4pt를 더 그린다 — 그 여유 없이는 84 원의 어깨가 바로 위 상태 필의 4.6pt 아래에서
  // 끝났다 (실측 2026-08-19). 6pt를 더해 어떤 필 라벨 길이에서도 어깨가 필을 물지 않게 한다.
  seal: { width: 84, height: 84, borderRadius: 42, borderWidth: 2.5, borderColor: '#6E9BC5', alignItems: 'center', justifyContent: 'center', alignSelf: 'center', marginTop: 6, transform: [{ rotate: '8deg' }], opacity: 0.88 },
  sealRing: { position: 'absolute', top: 5, left: 5, right: 5, bottom: 5, borderRadius: 37, borderWidth: 1, borderStyle: 'dashed', borderColor: 'rgba(110,155,197,.55)' },
  sealNick: { position: 'absolute', backgroundColor: '#fff', borderRadius: 3 },
  // sheet — 순백·샤프. 카드 수프 → 코랄 1px 풀블리드 섹션 분리 (meetup 섹션 문법)
  // [HIG N8] 배경 딤과 드래그는 이제 pageSheet 가 시스템으로 그린다 — 손으로 그린 두 스타일
  // (딤 면 · 44×5 바)은 은퇴했다. 그 바는 이 시트가 할 수 없는 드래그를 약속하고 있었다.
  sheet: { flex: 1, backgroundColor: paper.canvas, paddingHorizontal: 16 },
  sheetCard: { marginHorizontal: -16, paddingHorizontal: 16, paddingVertical: 15, borderTopWidth: 1, borderTopColor: paper.line, marginTop: 14 },
  // 취소 수수료 카드 — 크리티컬 문법 (canvas 면 + 1px critical, line과 절대 공유 금지)
  feeCard: { backgroundColor: paper.canvas, padding: 15, borderWidth: 1, borderColor: paper.critical, marginTop: 14 },
  // 코스 실루엣 — 읽는 중·실패는 캔버스 박스, 도착한 실좌표는 다크 플레이트 (HeatTrace 는 어두운
  // 면 위에서 그리도록 만들어졌다). 목업 트레이스·featChip 퇴역은 그대로 (item 6).
  sheetMapBox: {
    marginTop: 10, minHeight: SHEET_MAP_H, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 12,
  },
  sheetMapTxt: { fontSize: 15, fontWeight: '700', color: paper.dim },
  sheetMapPlate: { marginTop: 10, backgroundColor: '#0e150f', alignItems: 'center', paddingVertical: 12 },
  vDiv: { width: 1, backgroundColor: '#EEE' },
  // 결제 내역 실패 스트립의 재시도 — schedule의 밑줄 텍스트 문법 (박스 없음, ≥44pt 타깃)
  payRetry: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  // [0207] 결제 상태 로딩 골격 — 「로딩은 0이 아니다」. 두 줄인 이유: 한 줄짜리 골격은 그 자리에
  // 값이 하나만 온다고 약속하는데, 이 줄은 헤드라인 + 보조 문장 두 줄이다.
  paySkelWide: { height: 15, borderRadius: 3, backgroundColor: paper.disabledFill, width: '62%' },
  paySkelNarrow: { height: 13, borderRadius: 3, backgroundColor: paper.disabledFill, width: '44%', marginTop: 7 },
  badgePill: { backgroundColor: '#e3f0c4', paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }, // 목업 러너 전용 배지 — 확정 틴트 시맨틱 유지, 스퀘어만
  chatChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 8, paddingHorizontal: 13, alignSelf: 'center' }, // meetup chatChip 문법
  // 비활성 칩 — theme.ts:206 매트릭스의 disabled 항 (disabledFill + faint, 불투명도 트릭 금지)
  chatChipOff: { backgroundColor: paper.disabledFill, borderColor: '#EEEEEE' },
  // [0212] 미확인 배지 — 잉크 면 위 종이 글자. 수치이므로 색이 아니라 대비로 말한다.
  chatChipBadge: { minWidth: 22, textAlign: 'center', overflow: 'hidden', borderRadius: 10,
    paddingHorizontal: 6, paddingVertical: 1, backgroundColor: paper.ink, color: '#FFFFFF',
    fontSize: 15, lineHeight: 19, fontWeight: '800' },
  // [Sean 2026-08-11] 볼트 그린 은퇴 — §3b 프라이머리는 잉크 면 + 화이트 17/800이다.
  // 볼트는 버튼 매트릭스에 아예 없는 색이었다 (그린은 이제 '준비됨' 상태 시맨틱에만 남는다).
  // '실시간 보기'만 예외로 자기 색을 유지한다 — 라이브는 상태색이지 버튼 스타일이 아니다.
  // [ui-consistency-2 2026-09-25] 이 이름은 이제 **하나의 호출자**만 갖는다: 창백한 #ffe9e2 면의
  // '실시간 보기'. 코랄 면 두 벌(쉼 4px 립 · 눌림 translateY(3)+1px · 17/800 흰 라벨)은 버튼
  // 매트릭스(PaperBtn primary)와 같은 산식이라 매트릭스로 접었고, 그 로컬 립 스타일은 은퇴했다.
  // 라이브 면만 남는 이유는 Sean 2026-08-26 의 기록 그대로다 — 라이브는 상태색이지 버튼
  // 스타일이 아니고, 창백한 워시 아래 코랄 립은 다른 버튼이 된다.
  primaryAction: { backgroundColor: paper.action, alignItems: 'center', paddingVertical: 16, marginTop: 16 },
  // [ui-consistency-10] `ghostAction` (a fourth secondary style: '#fff' face · '#EEE' border · ink
  // label) is retired — its three doors are PaperBtn now. A door's sub-line sits under the button.
  btnSub: { fontSize: 15, lineHeight: 20, color: paper.dim, textAlign: 'center', marginTop: 6 },
  // [ui-consistency-7] The live label ink on the #ffe9e2 face — paper.actionInk (5.72:1), not the
  // retired coral text (3.64:1). 16/900 is below the large-text threshold, so AA needs 4.5.
  liveInk: { fontSize: 16, fontWeight: '900', color: paper.actionInk },
  cancelLink: { alignItems: 'center', paddingVertical: 14, marginTop: 4 },
  cancelConfirm: { backgroundColor: paper.critical, alignItems: 'center', paddingVertical: 15, marginTop: 16 }, // 크리티컬 잉크 — 구 #e8492a는 line과 근친이라 분리 법 위반
});
