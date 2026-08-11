import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { cancelBooking, fetchMyBookings, pauseRecurringSeries, shareRunToFeed } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { BottomNav } from '../../src/components/bottomnav';
import { Monogram, Row } from '../../src/components/ui';
import { Booking, BookingStatus, cancelPolicy, draft, runners } from '../../src/store';
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
    return fetchMyBookings()
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
    // 실예약이 러너 확정 전이면 관리 시트 대신 상태 안내 — 단, '매칭 중' 상태일 때만.
    // matched(runner_id) 없는 취소·만료 예약까지 "러너를 찾고 있어요"라고 하면 죽은 예약에 대한 거짓말이 된다.
    if (b.live && !b.matched && b.status === 'pending') {
      Alert.alert('매칭 중', '러너를 찾고 있어요.\n러너가 확정되면 여기서 일정 변경·취소를 관리할 수 있어요.');
      return;
    }
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
  const enrouteCancel = selected?.rawStatus === 'runner_enroute';
  const feeRate = enrouteCancel ? cancelPolicy.enrouteFeeRate : cancelPolicy.feeRate;
  const fee = selected ? Math.round(selected.price * feeRate) : 0;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: 56, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <View style={{ paddingHorizontal: 16 }}>
        {/* 표준 탭 헤더 — 탭 루트엔 뒤로가기 없음 (바텀 내비가 탈출구), 좌측 타이틀 + 그레이 서브 */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View>
            <Text style={[{ fontSize: 30, fontWeight: '900', color: paper.ink }, df]}>내 일정</Text>
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
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && visible.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 23 }}>
              {/* [2026-08-10 감사] 슬라이드 예약은 은퇴한 제스처였다(owner/home.tsx:1222) — 죽은 안내 문구 교정 */}
              {liveBookings.length === 0 ? '예정된 러닝이 없어요\n홈의 GO 버튼으로 러너를 찾아보세요' : '이 조건의 일정이 없어요'}
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
                        {b.live && (
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
                          <View style={s.certDot}><Text style={{ fontSize: 8, fontWeight: '900', color: '#fff' }}>✓</Text></View>
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
                      style={({ pressed }) => [s.shareBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                    >
                      <Text style={{ fontSize: 14, fontWeight: '900', color: paper.ink }}>공유 카드</Text>
                    </Pressable>
                    <Pressable
                      onPress={() => {
                        shareRunToFeed(b.id)
                          .then(() => Alert.alert('피드에 올렸어요', '동네 피드에서 확인해보세요'))
                          .catch((err) => Alert.alert('피드 공유', (err as Error).message));
                      }}
                      style={({ pressed }) => [s.shareBtn, { backgroundColor: '#e7efd8', transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                    >
                      <Text style={{ fontSize: 14, fontWeight: '900', color: '#3d5a2b' }}>피드 자랑</Text>
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
                      <Pred label="예상 러닝" value={`약 ${runMin}분`} sub="픽업·인계 포함 ~65분" />
                      <View style={s.vDiv} />
                      <Pred label="예상 페이스" value={selected.paceLabel} sub={`${selected.km}km`} />
                      <View style={s.vDiv} />
                      <Pred label="예상 결제" value={`${selected.price.toLocaleString()}원`} sub="완주 기준" />
                    </Row>
                  </View>

                  {/* runner */}
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
                      <Pressable
                        style={({ pressed }) => [s.chatChip, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/chat', params: { bid } }); }}
                      >
                        <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>채팅</Text>
                      </Pressable>
                    </Row>
                    {runner.desc && (
                      <Text style={{ fontSize: 15, color: paper.text, marginTop: 10, lineHeight: 19.5 }}>{runner.desc}</Text>
                    )}
                  </View>

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
                        style={({ pressed }) => [s.primaryAction, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid } }); }}
                      >
                        <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>러닝 리포트 보기</Text>
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
                          style={({ pressed }) => [s.primaryAction, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                          onPress={() => {
                            // 제안 화면 직행 (0016) — 취소·재예약이 아니라 러너 동의 기반 시간 변경
                            const bid = selected.id;
                            close();
                            router.push({ pathname: '/owner/reschedule', params: { bid } });
                          }}
                        >
                          <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>일정 변경 요청</Text>
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
                      <Pressable style={s.cancelLink} onPress={() => setSheetMode('cancel')}>
                        <Text style={{ fontSize: 14.5, fontWeight: '700', color: paper.critical }}>
                          {enrouteCancel ? '일정 취소하기 (수수료 50%)' : '일정 취소하기'}
                        </Text>
                      </Pressable>
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

                  <View style={s.feeCard}>
                    <FeeLine label="결제 금액" value={`${selected.price.toLocaleString()}원`} />
                    <FeeLine label={`취소 수수료 (${feeRate * 100}%)`} value={`−${fee.toLocaleString()}원`} coral />
                    <View style={{ height: 1, backgroundColor: '#EEE', marginVertical: 10 }} />
                    <FeeLine label="환불 금액" value={`${(selected.price - fee).toLocaleString()}원`} bold />
                    {/* [0066] 이동 중 티어는 배분 문장이 다르다 — 50% 전액이 이미 출발한 러너의 보상.
                        일반 티어 카피(10%·50/50 배분·24h 무료)는 그대로 생존. */}
                    <Text style={{ fontSize: 14, color: paper.dim, marginTop: 10, lineHeight: 17 }}>
                      {enrouteCancel
                        ? '러너가 이미 픽업으로 출발했어요 — 이동 중 취소 수수료는 전액 시간을 내어 출발한 러너의 보상으로 배분돼요.'
                        : `취소 수수료는 시간을 비워둔 러너에게 ${Math.round(cancelPolicy.runnerShare * 100)}%, 도그스하이에 ${Math.round((1 - cancelPolicy.runnerShare) * 100)}% 배분돼요.\n시작 24시간 전까지는 수수료가 없어요.`}
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
                        Alert.alert(
                          '취소 완료',
                          `환불 ${r.refund.toLocaleString()}원${r.cancel_fee > 0 ? ` (수수료 ${r.cancel_fee.toLocaleString()}원 차감)` : ' (수수료 없음)'}\n결제 실연동 후엔 3일 내 환불 처리돼요`,
                        );
                        load();
                      } catch (e) {
                        Alert.alert('취소 실패', (e as Error).message);
                      }
                    }}
                  >
                    <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#fff' }}>취소하고 {(selected.price - fee).toLocaleString()}원 환불받기</Text>
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
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 40, justifyContent: 'center', paddingHorizontal: 14, borderWidth: 1, borderColor: paper.ink, backgroundColor: paper.canvas },
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
  certDot: { width: 13, height: 13, borderRadius: 7, backgroundColor: '#3d8fd4', alignItems: 'center', justifyContent: 'center', alignSelf: 'center' },
  // 완료 카드 공유 행 — 카드 하단에 부착된 풀와이드 밴드 (도장을 가리지 않는 위치, Sean 2026-07-29)
  shareRow: { flexDirection: 'row', gap: 8, backgroundColor: paper.canvas, borderBottomWidth: 1, borderColor: '#EEE', marginTop: -1, paddingVertical: 9, paddingHorizontal: 14 },
  // 볼트 = 퍼스널(내 러닝 자랑) 시맨틱 — 면은 남고 섀도만 은퇴 (라운드와 함께)
  shareBtn: { flex: 1, alignItems: 'center', backgroundColor: colors.volt, paddingVertical: 9 },
  // T3 원형 소인 — 콘텐츠가 여유 있게 들어가는 84 지름 (랩의 64는 작았음, Sean 피드백)
  seal: { width: 84, height: 84, borderRadius: 42, borderWidth: 2.5, borderColor: '#6E9BC5', alignItems: 'center', justifyContent: 'center', alignSelf: 'center', transform: [{ rotate: '8deg' }], opacity: 0.88 },
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
  badgePill: { backgroundColor: '#e3f0c4', paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }, // 목업 러너 전용 배지 — 확정 틴트 시맨틱 유지, 스퀘어만
  chatChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 8, paddingHorizontal: 13, alignSelf: 'center' }, // meetup chatChip 문법
  primaryAction: { backgroundColor: colors.volt, alignItems: 'center', paddingVertical: 14, marginTop: 16 }, // 볼트 = 퍼스널(예약 액션) 시맨틱 유지
  ghostAction: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#EEE', alignItems: 'center', paddingVertical: 13, marginTop: 8 },
  cancelLink: { alignItems: 'center', paddingVertical: 14, marginTop: 4 },
  cancelConfirm: { backgroundColor: paper.critical, alignItems: 'center', paddingVertical: 15, marginTop: 16 }, // 크리티컬 잉크 — 구 #e8492a는 line과 근친이라 분리 법 위반
});
