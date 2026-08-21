import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaymentRecord, cancelBooking, fetchBookingPayments, fetchInFlightOwnerBookings, fetchMyBookings, pauseRecurringSeries, shareRunToFeed } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { lateness } from '../../src/lib/lateness';
import { BottomNav } from '../../src/components/bottomnav';
import { PaymentRow } from '../../src/components/charge-states';
import { LateNotice } from '../../src/components/late-notice';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { TabSwipe } from '../../src/components/tabswipe';
import { Monogram, Row } from '../../src/components/ui';
import { Booking, BookingStatus, cancelFeeRateFor, cancelPolicy, draft, runners } from '../../src/store';
import { CollarKey, collarColors, colors, paper } from '../../src/theme';

// 내 일정 — agenda view. Tapping a booking opens a management sheet
// (route card + predictions + runner + reschedule/cancel actions).
// A confirmed booking is a contract — never re-routes to runner selection.

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

const STATUS_STYLE: Record<BookingStatus, { label: string; bg: string; fg: string; rail: string }> = {
  confirmed: { label: '예약 확정', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  pending: { label: '러너 응답 대기', bg: '#FDE8D0', fg: '#9D580A', rail: '#F59A43' }, // 앰버×탠저린 50:50 — 카운트다운의 색 (기대감, 코랄 불침범)
  handoff: { label: '인계 완료 · 시작 대기', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  active: { label: '러닝 중 · LIVE', bg: '#eaf7c8', fg: '#4a6d1f', rail: colors.volt },
  completed: { label: '완료', bg: '#E3EEF8', fg: '#4A6E93', rail: '#6E9BC5' }, // 소프트 에너지 블루 — 그레이는 '끝'처럼 죽어 보였다; 완주는 성과다
  cancelled: { label: '취소됨', bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' },
};

// 표시 어휘(6종)가 뭉갠 희귀 서버 상태의 정직한 배지 — no_show·incident_review는 STATUS_MAP 폴백으로
// '러너 응답 대기'가 되어 거짓 배지 + 죽은 버튼을 만들었다 (0056 동반 클라 수리)
const stFor = (b: Booking) =>
  b.rawStatus === 'no_show' ? { label: '불발', bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' }
  : b.rawStatus === 'incident_review' ? { label: '확인 중', bg: '#FDE8D0', fg: '#9D580A', rail: '#F59A43' }
  : STATUS_STYLE[b.status];

const paceMin = (label: string) => (label.includes('8') ? 8 : label.includes('6') ? 6 : 7);

export default function Schedule() {
  const df = useDisplayFont();
  const nf = useNumFont(); // [V4] 시간 = Oswald // 표준 탭 헤더 — 좌측 BHS 30

  const [filterIdx, setFilterIdx] = useState(0);
  const [selected, setSelected] = useState<Booking | null>(null);
  const [sheetMode, setSheetMode] = useState<'detail' | 'cancel'>('detail');
  const [liveBookings, setLiveBookings] = useState<Booking[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  // [honesty 2026-08-11] warn-only catch + [] seed rendered "예정된 러닝이 없어요"
  // in flight and on failure. Three states now: loading / error+retry / loaded.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);

  const load = () => {
    setLoadErr(false);
    // [B9] 홈에서만 고쳤던 합집합을 여기에도. 히어로의 「일정에서 정리하기」가 **도착하는 화면**이
    // 20행 창만 읽으면, 늦었다고 알려준 그 예약이 여기서는 없는 일이 된다 (codex 2026-08-21).
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
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const all = liveBookings; // 데모 예약 제거 — 실예약만
  const visible = all.filter(FILTERS[filterIdx].match);
  const groups = visible.reduce<Record<string, Booking[]>>((acc, b) => {
    (acc[b.dateLabel] = acc[b.dateLabel] ?? []).push(b);
    return acc;
  }, {});

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
            Alert.alert('해지 실패', (e as Error).message ?? '잠시 후 다시 시도해주세요');
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
  const mockRunner = selected && !selected.live ? runners.find((r) => r.id === selected.runnerId) : undefined;
  const runner = selected
    ? mockRunner ?? {
        id: 'live', name: selected.runnerName, char: selected.runnerName[0] ?? '러', color: '#5a7a3c',
        rating: null as number | null, reviews: null as number | null, runs: null as number | null,
        pace: null as string | null, badges: [] as string[], desc: null as string | null, // [정직] 신원인증 배지 은퇴 — 뒷받침 데이터 없음 (wave-1 meetup P1-6과 동일)
        distanceKm: 0,
      }
    : undefined;
  const runMin = selected ? selected.km * paceMin(selected.paceLabel) : 0;
  // [0066] En-route cancel is now legal at a 50% fee (runner compensation) — the preview
  // rate follows the server ladder's tier for this booking's rawStatus. The server still
  // computes the real fee; the success alert shows the returned numbers.
  // [2026-08-13] The tier now comes from cancelFeeRateFor (store.ts), the full four-arm mirror
  // of 0066: the old two-arm version quoted 10% on bookings the server cancels for free.
  const enrouteCancel = selected?.rawStatus === 'runner_enroute';
  const feeRate = selected ? cancelFeeRateFor(selected) : 0;
  const fee = selected ? Math.round(selected.price * feeRate) : 0;
  // ⚠ [철회 2026-08-21] 여기 '면제될 수 있다' 문구를 넣었다가 되돌린다. **오늘은 거짓이기 때문이다.**
  // 0117 §9 의 면제는 아직 배포되지 않았고, 현재 서버는 0066:80 대로 runner_enroute 취소에
  // 조건 없이 50%를 청구한다. 즉 그 시점의 정확한 답은 **50% 그 자체**였고, 내가 넣은 불확실성은
  // 없는 정책을 미리 말한 것이다 — 거짓 주장을 고치는 커밋에서 새 거짓 주장을 하나 만들었다.
  // 게다가 시트는 여전히 정확한 50%와 금액과 '전액 러너 보상' 문장을 함께 보여주고 있었으므로,
  // 한 수수료에 대해 세 가지 다른 말을 하는 화면이 됐다 (codex 지적).
  // 이 변경은 **0117 배포와 같은 창에서** 다시 온다. 그때는 미러가 아니라 quote_cancel_fee 읽기다.

  // 결제 내역 (charge slice §0-bis) — 예약 하나의 payments 행. 정산 전에는 행이 없는 것이
  // 정직한 상태(가격 비가시성)라, 없는 동안에는 섹션 자체가 렌더되지 않는다.
  const [payRows, setPayRows] = useState<PaymentRecord[]>([]);
  const [payErr, setPayErr] = useState(false);
  const loadPayments = useCallback((bid: string) => {
    setPayErr(false);
    fetchBookingPayments(bid)
      .then(setPayRows)
      .catch((e) => { console.warn('[schedule] payments:', e?.message ?? e); setPayErr(true); });
  }, []);
  useEffect(() => {
    if (!selected) { setPayRows([]); setPayErr(false); return; }
    setPayRows([]);
    loadPayments(selected.id);
  }, [selected, loadPayments]);
  // 완료 = 정산이 끝났어야 하는 예약. 그때는 행이 0건이어도 '아직 없다'고 말해야 한다
  // (침묵하면 청구가 없었던 것처럼 읽힌다). 그 전에는 부재가 곧 사실이다.
  const settled = selected?.status === 'completed';
  const showPayments = payRows.length > 0 || settled;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: 56, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <View style={{ paddingHorizontal: 16 }}>
        {/* 표준 탭 헤더 — 탭 루트엔 뒤로가기 없음 (바텀 내비가 탈출구), 좌측 타이틀 + 그레이 서브 */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View>
            {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
            <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>내 일정</Text>
            {/* [2026-08-10 density audit] "실예약" was internal jargon — users only know 예약 */}
            <Text style={{ fontSize: 14.5, color: paper.dim, marginTop: 4 }}>예약 {liveBookings.length}건</Text>
          </View>
          {/* ＋ = 백버튼 문법의 스퀘어 (40×40 · 캔버스 면 · 1px 코랄 · 잉크 글리프) */}
          <Pressable onPress={() => router.push('/owner/request')} style={s.circleBtn}>
            <Text style={{ fontSize: 19.5, color: paper.ink }}>＋</Text>
          </Pressable>
        </Row>

        {/* 주간/월간 데드 토글 은퇴 (ui-audit P1) — 기능이 생길 때 복귀 */}

        {/* filters (functional) */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 12 }} contentContainerStyle={{ gap: 8 }}>
          {FILTERS.map((f, i) => (
            <Pressable
              key={f.label}
              onPress={() => setFilterIdx(i)}
              style={[s.filter, { backgroundColor: filterIdx === i ? f.sel : f.tint, borderColor: filterIdx === i ? f.sel : '#EEE' }]}
            >
              <Text style={{ fontSize: 14, fontWeight: filterIdx === i ? '800' : '700', color: filterIdx === i ? f.selFg : f.tintFg }}>{f.label}</Text>
            </Pressable>
          ))}
        </ScrollView>

        </View>

        {/* agenda — 풀와이드 밴드 (모던 패스: 카드 수프 → 엣지-투-엣지) */}
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>일정 불러오는 중...</Text>
          </View>
        )}
        {/* 라우드-페일 스트립 — 실패는 빈 일정으로 분장하지 않는다 */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>일정을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && visible.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 23 }}>
              {/* [2026-08-10 감사] 슬라이드 예약은 은퇴한 제스처였다 — 죽은 안내 문구 교정.
                  [2026-08-19] 'GO 버튼'도 같은 운명 — 랩 ⑧ v2가 GO 디스크를 은퇴시키고 홈 히어로를
                  두 문(지금 찾기 / 예약하기)으로 바꿨다. 화면에 없는 버튼으로 안내하지 않는다. */}
              {liveBookings.length === 0 ? '예정된 러닝이 없어요\n홈의 지금 찾기 / 예약하기로 러너를 찾아보세요' : '이 조건의 일정이 없어요'}
            </Text>
          </View>
        )}
        {Object.entries(groups).map(([dateLabel, items]) => (
          <View key={dateLabel} style={{ marginTop: 18 }}>
            {/* 날짜 그룹 라벨 — dim 14 (900은 숫자·타이틀 전용 법) */}
            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.dim, paddingHorizontal: 12, marginBottom: 8 }}>{dateLabel}</Text>
            {items.map((b) => {
              const st = stFor(b);
              return (
                <View key={b.id}>
                <Pressable style={s.bookingCard} onPress={() => open(b)}>
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
                          <View style={s.recurPill}><Text style={{ fontSize: 14, fontWeight: '800', color: '#4a6d1f' }}>⟳ 매주</Text></View>
                        )}
                        {LIVE_RAW.includes(b.rawStatus ?? '') && (
                          <View style={s.livePillSm}><Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>● LIVE</Text></View>
                        )}
                      </Row>
                      <View style={[s.statusPill, { backgroundColor: st.bg }]}>
                        <Text style={{ fontSize: 14, fontWeight: '800', color: st.fg }}>{st.label}</Text>
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
                            {b.dogName} · {b.runnerName} 러너 · {b.km}km
                          </Text>
                        </Row>
                        {/* money = Oswald (color/size kept) — lineHeight 19 >= 1.26x (BUG A) */}
                        <Text style={[{ fontSize: 14.5, color: paper.dim, marginTop: 2, lineHeight: 19 }, nf]}>
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
                    {b.status === 'active' && (
                      <Pressable
                        onPress={(e) => { e.stopPropagation(); draft.bookingId = b.id; router.push('/owner/live'); }}
                        style={({ pressed }) => [s.goLiveBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                      >
                        <Text style={{ fontSize: 16, fontWeight: '900', color: '#d84a2f' }}>● 실시간 보기 ›</Text>
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
                    >
                      <Text style={s.shareTxt}>공유 카드</Text>
                    </Pressable>
                    <Pressable
                      onPress={() => {
                        shareRunToFeed(b.id)
                          .then(() => Alert.alert('피드에 올렸어요', '동네 피드에서 확인해보세요'))
                          .catch((err) => Alert.alert('피드 공유', (err as Error).message));
                      }}
                      style={({ pressed }) => [s.shareBtn, pressed && { backgroundColor: paper.wash }, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                    >
                      <Text style={s.shareTxt}>피드 자랑</Text>
                    </Pressable>
                  </View>
                )}
                </View>
              );
            })}
          </View>
        ))}

        <Pressable style={s.emptyCta} onPress={() => router.push('/owner/request')}>
          <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>＋ 새 러닝 예약하기</Text>
        </Pressable>
      </ScrollView>
      {/* 시스템 바 스트립 — 날짜 그룹 라벨과 카드 상단이 시계 뒤로 지나가던 것 (실측 2026-08-19).
          ScrollView '뒤'가 아니라 '위'에 있어야 콘텐츠가 그 아래로 흐른다. */}
      <StatusBarCover />
      </TabSwipe>
      <BottomNav />

      {/* ---------- booking management sheet ---------- */}
      <Modal visible={!!selected} transparent animationType="slide" onRequestClose={close}>
        <Pressable style={s.backdrop} onPress={close} />
        {selected && runner && (
          <View style={s.sheet}>
            <View style={s.handle} />
            <ScrollView showsVerticalScrollIndicator={false} style={{ maxHeight: 560 }}>
              {sheetMode === 'detail' ? (
                <>
                  {/* header */}
                  <Row style={{ justifyContent: 'space-between' }}>
                    <View>
                      <Text style={{ fontSize: 14, color: paper.dim }}>{selected.dateLabel}</Text>
                      {/* Oswald numerals (900 = numbers+titles law) — lineHeight 32 >= 1.2x (BUG A) */}
                      <Text style={[{ fontSize: 25.5, fontWeight: '900', color: paper.ink, marginTop: 2, lineHeight: 32 }, nf]}>
                        {selected.timeLabel} · {selected.dogName}
                      </Text>
                    </View>
                    <View style={[s.statusPill, { backgroundColor: stFor(selected).bg, alignSelf: 'flex-start' }]}>
                      <Text style={{ fontSize: 14, fontWeight: '800', color: stFor(selected).fg }}>
                        {stFor(selected).label}
                      </Text>
                    </View>
                  </Row>

                  {/* [T4] 지각 알림 — 히어로의 「일정에서 정리하기」가 도착하는 자리다. 상태 필은
                      '확정됨'이라고만 말하는데, 그 확정이 16일 전이면 사실의 절반이다.
                      ⚠ actions 를 넘기지 않는다: 이 시트는 이미 자기 출구(취소·러너 변경·다시 예약)를
                      아래에 갖고 있고, 그 취소가 0066 사다리를 정확히 견적한다(cancelFeeRateFor,
                      네 갈래 미러). 여기서 버튼을 또 그리면 두 번째 코랄이거나, 값을 모르는 중복
                      출구가 된다 — 알림은 사실만 말하고 문은 아래 것을 쓴다. */}
                  <LateNotice
                    late={lateness({ scheduledAt: selected.scheduledAt ?? null, rawStatus: selected.rawStatus,
                                     arrivedAt: selected.arrivedAt ?? null, km: selected.km,
                                     startedAt: selected.startedAt ?? null })}
                    side="owner"
                    dogName={selected.dogName}
                    runnerName={selected.runnerName}
                  />

                  {/* route card — 예약 행이 실제로 들고 있는 값만. 목업 특징칩·점검 도장·설명 퇴역 (item 6).
                      '안심 코스 · N.NN 점검' 도장은 실 checked_at이 있을 때만 찍힌다 — 지금 이 행에는 없다. */}
                  <View style={s.sheetCard}>
                    <Row style={{ gap: 5 }}>
                      <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{selected.routeName}</Text>
                      {/* [리뷰 F8] ✓ 인증 도장 은퇴 — 이 행엔 checked_at 실데이터가 없다. 근거 없는 검증 마크 금지 */}
                      <Text style={{ fontSize: 14, color: paper.dim, alignSelf: 'center' }}>{selected.km}km</Text>
                    </Row>
                    {/* 실좌표 없는 코스 지도 슬롯 — 토큰으로 작성 (후속 리페인트 생존) */}
                    <View style={s.sheetMapPending}>
                      <Text style={s.sheetMapPendingTxt}>코스 지도 준비 중</Text>
                    </View>
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
                      <Text style={{ fontSize: 14, color: paper.dim, marginTop: 6, lineHeight: 19 }}>
                        {CHAT_PRE_ACCEPT.includes(selected.rawStatus ?? '')
                          ? '러너가 수락하면 여기에 러너 정보와 채팅이 열려요'
                          : '이 예약은 러너가 정해지기 전에 끝났어요'}
                      </Text>
                    </View>
                  ) : (
                  <View style={s.sheetCard}>
                    <Row style={{ gap: 12 }}>
                      <Monogram char={runner.char} bg={runner.color} size={46} />
                      <View style={{ flex: 1 }}>
                        <Row style={{ gap: 6 }}>
                          <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{runner.name} 러너</Text>
                          {runner.badges.map((b) => (
                            <View key={b} style={s.badgePill}><Text style={{ fontSize: 14, fontWeight: '800', color: '#4a6d1f' }}>{b}</Text></View>
                          ))}
                        </Row>
                        <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3 }}>
                          {runner.rating != null
                            ? `★ ${runner.rating} (${runner.reviews}) · 러닝 ${runner.runs}회 · 평균 ${runner.pace}`
                            : '실러너 · 상세 프로필 준비 중'}
                        </Text>
                      </View>
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
                          <Text style={{ fontSize: 14, fontWeight: '800', color: paper.faint }}>채팅</Text>
                        </View>
                      ) : (
                        <Pressable
                          style={({ pressed }) => [s.chatChip, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                          onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/chat', params: { bid } }); }}
                        >
                          <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>채팅</Text>
                        </Pressable>
                      )}
                    </Row>
                    {CHAT_PRE_ACCEPT.includes(selected.rawStatus ?? '') && (
                      <Text style={{ fontSize: 14, color: paper.dim, marginTop: 8, lineHeight: 19 }}>
                        러너가 수락하면 채팅을 열 수 있어요
                      </Text>
                    )}
                    {runner.desc && (
                      <Text style={{ fontSize: 15, color: paper.text, marginTop: 10, lineHeight: 19.5 }}>{runner.desc}</Text>
                    )}
                  </View>
                  )}

                  {/* 결제 내역 (charge slice) — 청구는 러닝이 끝난 뒤에 생긴다. 행이 있거나 정산이
                      끝난 예약에서만 렌더한다: 정산 전 '결제 내역 없음'은 알림이 아니라 소음이고,
                      §0-bis의 비가시성은 청구가 생긴 뒤에는 반드시 보여주는 것으로만 정직해진다. */}
                  {showPayments && (
                    <View style={s.sheetCard}>
                      <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>결제 내역</Text>
                      {payErr ? (
                        // 실패는 실패로 — 다만 정산된 예약에서만 말한다 (그 전에는 섹션 자체가 없다)
                        <View style={{ marginTop: 8 }}>
                          <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>결제 내역을 불러오지 못했어요</Text>
                          <Pressable onPress={() => loadPayments(selected.id)} style={s.payRetry} accessibilityRole="button">
                            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
                          </Pressable>
                        </View>
                      ) : payRows.length === 0 ? (
                        <Text style={{ fontSize: 14.5, lineHeight: 20, color: paper.dim, marginTop: 6 }}>
                          아직 청구 내역이 없어요 — 정산이 끝나면 여기에 표시돼요
                        </Text>
                      ) : (
                        payRows.map((p) => <PaymentRow key={p.orderId} p={p} showDog={false} />)
                      )}
                    </View>
                  )}

                  {/* actions — 상태별: 진행 중엔 라이브만, 완료엔 기록만, 시작 전에만 변경·취소 */}
                  {selected.status === 'active' ? (
                    <>
                      <Pressable
                        style={({ pressed }) => [s.primaryAction, { backgroundColor: '#ffe9e2', borderWidth: 1, borderColor: '#ffc9b8', transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => { draft.bookingId = selected.id; close(); router.push('/owner/live'); }}
                      >
                        <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#d84a2f' }}>● 실시간 보기</Text>
                        {/* [정직 배치 2.5 · Sean D3=B] 앱 전체에서 바디캠을 '앞으로'라고 말하는 자리는 여기 한 곳뿐 */}
                        <Text style={{ fontSize: 14, color: '#b06a56', marginTop: 2 }}>러닝이 진행 중이에요 — GPS 경로를 실시간으로 지켜보세요</Text>
                        <Text style={{ fontSize: 14, color: '#b06a56', marginTop: 2 }}>바디캠 뷰는 준비 중이에요</Text>
                      </Pressable>
                      <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', marginTop: 12, lineHeight: 18.5 }}>
                        이미 시작된 러닝은 일정 변경·취소가 불가능해요{'\n'}긴급 상황은 안심 센터 SOS를 이용해주세요
                      </Text>
                    </>
                  ) : selected.status === 'handoff' ? (
                    <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 16, lineHeight: 19.5 }}>
                      인계가 완료됐어요 — 러너가 러닝을 시작하면{'\n'}실시간 보기가 열려요 · 변경·취소는 불가능해요
                    </Text>
                  ) : selected.status === 'completed' ? (
                    <>
                      <Pressable
                        style={({ pressed }) => [s.primaryAction, pressed && { backgroundColor: paper.actionPressed }, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid } }); }}
                      >
                        <Text style={s.primaryActionTxt}>러닝 리포트 보기</Text>
                        {/* [2026-08-10 density audit] sub-line cut — it narrated the button above it */}
                      </Pressable>
                      {/* 인증샷 바로가기 — 완료 러닝의 자랑 동선 한 탭 단축 (공유가 곧 마케팅) */}
                      <Pressable
                        style={({ pressed }) => [s.ghostAction, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid, shot: '1' } }); }}
                      >
                        <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>인증샷 만들기</Text>
                      </Pressable>
                      <Pressable
                        style={({ pressed }) => [s.ghostAction, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => {
                          draft.km = selected.km;
                          draft.pace = selected.paceLabel;
                          draft.preferredRunnerId = selected.runnerProfileId ?? null;
                          draft.preferredRunnerName = selected.runnerProfileId ? selected.runnerName : null;
                          draft.scheduledAtIso = null;
                          draft.timeLabel = '시간을 선택해주세요';
                          close();
                          router.push('/owner/request');
                        }}
                      >
                        <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>⟳ 이대로 다시 예약</Text>
                        <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>같은 거리·페이스{selected.runnerProfileId ? ` · ${selected.runnerName} 러너 지명` : ''} — 시간만 골라요</Text>
                      </Pressable>
                    </>
                  ) : selected.status === 'cancelled' ? (
                    // 취소된 일정 — 관리 액션 없음. 변경 요청은 서버가 확정 전용(409)이라 죽은 버튼이 되고,
                    // 취소하기는 재취소가 된다. 상태를 그대로 말하고 끝낸다.
                    <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', paddingVertical: 10 }}>
                      취소된 일정이에요 — 더 진행할 작업이 없어요
                    </Text>
                  ) : (selected.rawStatus === 'no_show' || selected.rawStatus === 'incident_review') ? (
                    // 불발·확인 중 — 서버 전이상 취소도 변경도 불가(refund_pending만 합법) → 액션 없음이 정직.
                    // 이전엔 STATUS_MAP 폴백 'pending'으로 이 시트가 죽은 취소 버튼을 그렸다.
                    <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', paddingVertical: 10 }}>
                      {selected.rawStatus === 'no_show'
                        ? '불발로 처리된 일정이에요 — 더 진행할 작업이 없어요'
                        : '확인이 진행 중인 일정이에요 — 처리되면 알림으로 알려드릴게요'}
                    </Text>
                  ) : (
                    <>
                      {/* 러너가 픽업 이동 중(runner_enroute) — 표시 어휘는 '확정'으로 뭉개지지만 서버는
                          변경은 여전히 거부한다(request_reschedule: confirmed 전용). 취소는 0066부터
                          합법(50% 수수료 = 러너 보상) — 아래 취소 링크가 이 상태에서도 열리고, 확인
                          시트가 50% 티어를 커밋 전에 명시한다. 여기는 변경 마감 사실만 말한다. */}
                      {selected.rawStatus === 'runner_enroute' && (
                        <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', paddingVertical: 10 }}>
                          러너가 픽업으로 이동 중이에요 — 일정 변경은 마감됐어요
                        </Text>
                      )}
                      {/* 일정 변경 요청은 확정 예약에서만 — 서버 규칙(request_reschedule: confirmed 전용 409)과
                          같은 문장. 표시 상태가 아니라 서버 원상태(rawStatus)로 게이트한다 — 표시 어휘는
                          runner_enroute를 '확정'으로 뭉개므로 그걸 믿으면 이동 중 죽은 버튼이 생긴다. */}
                      {selected.rawStatus === 'confirmed' && (
                        <Pressable
                          style={({ pressed }) => [s.primaryAction, pressed && { backgroundColor: paper.actionPressed }, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                          onPress={() => {
                            // 제안 화면 직행 (0016) — 취소·재예약이 아니라 러너 동의 기반 시간 변경
                            const bid = selected.id;
                            close();
                            router.push({ pathname: '/owner/reschedule', params: { bid } });
                          }}
                        >
                          <Text style={s.primaryActionTxt}>일정 변경 요청</Text>
                          <Text style={{ fontSize: 14, color: paper.text, marginTop: 2 }}>{runner.name} 러너의 가능 시간에서 새 시간을 제안해요</Text>
                        </Pressable>
                      )}
                      {/* 러너 변경 = 재지명 (이 예약 그대로). 확정 전에만 — 확정은 계약이고,
                          서버도 matching/runner_pending에서만 request_runner를 받는다.
                          예전엔 /owner/request로 되돌려 두 번째 예약을 만들었고 dog_slot_clash에 걸렸다. */}
                      {(selected.rawStatus === 'matching' || selected.rawStatus === 'runner_pending') && (
                        <Pressable
                          style={({ pressed }) => [s.ghostAction, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                          onPress={() => {
                            draft.bookingId = selected.id;
                            close();
                            router.push({ pathname: '/owner/matching', params: { mode: 'rebook', current: selected.runnerProfileId ?? '', pace: selected.paceLabel ?? '' } });
                          }}
                        >
                          <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>러너 변경</Text>
                          <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>이 예약 그대로 다른 러너에게 다시 요청해요</Text>
                        </Pressable>
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
                        >
                          <Text style={{ fontSize: 14.5, fontWeight: '700', color: paper.ink }}>
                            클럽 세션 화면으로 ›
                          </Text>
                          {/* '취소하기'라고 쓰지 않는다 — 인계 이후(runner_enroute~)의 위탁은
                              클럽 규정상 취소가 아니라 케이스로 다뤄지고, 서버도 그렇게 답한다.
                              여기서 '취소'를 약속하면 다음 화면이 거절할 때 그게 거짓말이 된다. */}
                          <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>
                            위탁 예약은 클럽 세션 화면에서 처리해요 — 취소 규정도 그곳에 있어요
                          </Text>
                        </Pressable>
                      ) : (
                        <Pressable style={s.cancelLink} onPress={() => setSheetMode('cancel')}>
                          <Text style={{ fontSize: 14.5, fontWeight: '700', color: paper.critical }}>
                            {/* 티어는 네 팔 미러가 말한다 — 수수료가 0인 예약에 '(수수료 50%)'를
                                달던 자리(이동 중만 표기하던 이분법)의 교정 */}
                            {fee > 0 ? `일정 취소하기 (수수료 ${Math.round(feeRate * 100)}%)` : '일정 취소하기'}
                          </Text>
                        </Pressable>
                      )}
                    </>
                  )}
                  {/* 반복 해지 (0026) — 구독은 반드시 끌 수 있어야 한다. 상태 무관 노출 */}
                  {selected.seriesId && (
                    <Pressable style={s.cancelLink} onPress={pauseSeries}>
                      <Text style={{ fontSize: 14.5, fontWeight: '700', color: paper.dim }}>⟳ 매주 반복 해지</Text>
                    </Pressable>
                  )}
                </>
              ) : (
                <>
                  {/* cancel confirmation — 크리티컬 문법 (criticalWash/critical) 유지 */}
                  <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>일정을 취소할까요?</Text>
                  <Text style={{ fontSize: 14.5, color: paper.text, marginTop: 6 }}>
                    {selected.dateLabel} {selected.timeLabel} · {runner.name} 러너
                  </Text>

                  {/* [post-pay 2026-08-13] 이 카드는 환불 명세가 아니라 **청구 명세**다.
                      예약 시점에 잡아둔 돈이 없으므로 (§0-bis: 러닝이 끝난 뒤에 청구) 돌려받을
                      금액이라는 개념 자체가 없다 — 취소가 만드는 유일한 돈은 수수료 청구다. */}
                  <View style={s.feeCard}>
                    <FeeLine label="예약 금액" value={`${selected.price.toLocaleString()}원`} />
                    <FeeLine label={`취소 수수료 (${Math.round(feeRate * 100)}%)`} value={`${fee.toLocaleString()}원`} coral />
                    <View style={{ height: 1, backgroundColor: '#EEE', marginVertical: 10 }} />
                    <FeeLine label="청구 금액" value={`${fee.toLocaleString()}원`} bold />
                    {/* [0066] 이동 중 티어는 배분 문장이 다르다 — 50% 전액이 이미 출발한 러너의 보상.
                        일반 티어 카피(10%·50/50 배분·24h 무료)는 그대로 생존. */}
                    <Text style={{ fontSize: 14, color: paper.dim, marginTop: 10, lineHeight: 17 }}>
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
                    <Text style={{ fontSize: 14, color: paper.dim, marginTop: 6, lineHeight: 17 }}>
                      {fee > 0
                        ? '지금까지 결제된 금액이 없어서 환불은 없어요 — 취소 수수료만 청구돼요.'
                        : '지금까지 결제된 금액도, 이번 취소로 청구되는 금액도 없어요.'}
                    </Text>
                  </View>

                  <Pressable
                    style={({ pressed }) => [s.cancelConfirm, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                    onPress={async () => {
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
                        Alert.alert('취소 실패', (e as Error).message);
                      }
                    }}
                  >
                    <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#fff' }}>
                      {fee > 0 ? `수수료 ${fee.toLocaleString()}원 내고 취소하기` : '수수료 없이 취소하기'}
                    </Text>
                  </Pressable>
                  <Pressable style={s.cancelLink} onPress={() => setSheetMode('detail')}>
                    <Text style={{ fontSize: 14.5, fontWeight: '700', color: paper.text }}>돌아가기</Text>
                  </Pressable>
                </>
              )}
            </ScrollView>
          </View>
        )}
      </Modal>
    </View>
  );
}

function Pred({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <View style={{ alignItems: 'center', flex: 1 }}>
      <Text style={{ fontSize: 14, color: paper.dim }}>{label}</Text>
      <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink, marginTop: 3 }}>{value}</Text>
      <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>{sub}</Text>
    </View>
  );
}

function FeeLine({ label, value, coral, bold }: { label: string; value: string; coral?: boolean; bold?: boolean }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 5 }}>
      <Text style={{ fontSize: 14.5, color: bold ? paper.ink : paper.text, fontWeight: bold ? '800' : '400' }}>{label}</Text>
      <Text style={{ fontSize: bold ? 16 : 14, fontWeight: bold ? '900' : '600', color: coral ? paper.critical : paper.ink }}>{value}</Text>
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
      <Text style={{ fontSize: 14, fontWeight: '900', color: '#6E9BC5', marginTop: 1 }}>{date}</Text>
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
  // 새 예약 CTA — 대시드 '추가 슬롯' 어포던스는 남고, 코랄 1px + 잉크 라벨로 이관
  emptyCta: {
    marginTop: 20, marginHorizontal: 12, borderWidth: 1, borderColor: paper.line, borderStyle: 'dashed',
    alignItems: 'center', paddingVertical: 14, backgroundColor: paper.canvas,
  },
  // sheet — 순백·샤프. 카드 수프 → 코랄 1px 풀블리드 섹션 분리 (meetup 섹션 문법)
  backdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: paper.canvas, padding: 16, paddingBottom: 36 },
  handle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#EEE', marginBottom: 14 },
  sheetCard: { marginHorizontal: -16, paddingHorizontal: 16, paddingVertical: 15, borderTopWidth: 1, borderTopColor: paper.line, marginTop: 14 },
  // 취소 수수료 카드 — 크리티컬 문법 (canvas 면 + 1px critical, line과 절대 공유 금지)
  feeCard: { backgroundColor: paper.canvas, padding: 15, borderWidth: 1, borderColor: paper.critical, marginTop: 14 },
  // sheetMap(목업 트레이스)·featChip(목업 특징칩) 퇴역 — item 6. 실좌표가 오면 지도가 돌아온다.
  sheetMapPending: {
    marginTop: 10, height: 110, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
  },
  sheetMapPendingTxt: { fontSize: 14, fontWeight: '700', color: paper.dim },
  vDiv: { width: 1, backgroundColor: '#EEE' },
  // 결제 내역 실패 스트립의 재시도 — schedule의 밑줄 텍스트 문법 (박스 없음, ≥44pt 타깃)
  payRetry: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  badgePill: { backgroundColor: '#e3f0c4', paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }, // 목업 러너 전용 배지 — 확정 틴트 시맨틱 유지, 스퀘어만
  chatChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 8, paddingHorizontal: 13, alignSelf: 'center' }, // meetup chatChip 문법
  // 비활성 칩 — theme.ts:206 매트릭스의 disabled 항 (disabledFill + faint, 불투명도 트릭 금지)
  chatChipOff: { backgroundColor: paper.disabledFill, borderColor: '#EEEEEE' },
  // [Sean 2026-08-11] 볼트 그린 은퇴 — §3b 프라이머리는 잉크 면 + 화이트 17/800이다.
  // 볼트는 버튼 매트릭스에 아예 없는 색이었다 (그린은 이제 '준비됨' 상태 시맨틱에만 남는다).
  // '실시간 보기'만 예외로 자기 색을 유지한다 — 라이브는 상태색이지 버튼 스타일이 아니다.
  primaryAction: { backgroundColor: paper.action, alignItems: 'center', paddingVertical: 16, marginTop: 16 },
  primaryActionTxt: { fontSize: 17, fontWeight: '800', color: '#fff' },
  ghostAction: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#EEE', alignItems: 'center', paddingVertical: 13, marginTop: 8 },
  cancelLink: { alignItems: 'center', paddingVertical: 14, marginTop: 4 },
  cancelConfirm: { backgroundColor: paper.critical, alignItems: 'center', paddingVertical: 15, marginTop: 16 }, // 크리티컬 잉크 — 구 #e8492a는 line과 근친이라 분리 법 위반
});
