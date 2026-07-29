import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { cancelBooking, CoursePatch, fetchCoursePatches, fetchMyBookings, pauseRecurringSeries, shareRunToFeed } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { BottomNav } from '../../src/components/bottomnav';
import { PatchBadge } from '../../src/components/patch';
import { HeatTrace } from '../../src/components/runcard';
import { Monogram, Row } from '../../src/components/ui';
import { Booking, BookingStatus, cancelPolicy, draft, runners, sampleRoutes } from '../../src/store';
import { colors } from '../../src/theme';

// 내 일정 — agenda view. Tapping a booking opens a management sheet
// (route card + predictions + runner + reschedule/cancel actions).
// A confirmed booking is a contract — never re-routes to runner selection.

const FOREST = '#0F1D13';
// 필터 칩 = 카드 좌측 레일과 같은 상태 컬러 스키마 — 칩이 곧 범례가 된다.
// tint = 비선택(연한 상태색), sel = 선택(레일 원색). 상태가 아닌 칩(전체/반복)은 forest 중립.
const FILTERS: { label: string; match: (b: Booking) => boolean; tint: string; tintFg: string; sel: string; selFg: string }[] = [
  { label: '전체', match: () => true, tint: '#fff', tintFg: '#3d453d', sel: '#0F1D13', selFg: '#fff' },
  { label: '예약 확정', match: (b) => b.status === 'confirmed', tint: '#e3f0c4', tintFg: '#3d5a2b', sel: '#5a7a3c', selFg: '#fff' },
  { label: '응답 대기', match: (b) => b.status === 'pending', tint: '#FDE8D0', tintFg: '#9D580A', sel: '#F59A43', selFg: '#fff' },
  { label: '완료', match: (b) => b.status === 'completed', tint: '#E3EEF8', tintFg: '#4A6E93', sel: '#6E9BC5', selFg: '#fff' },
  { label: '반복', match: (b) => !!b.recurring, tint: '#fff', tintFg: '#3d453d', sel: '#0F1D13', selFg: '#fff' },
];

const STATUS_STYLE: Record<BookingStatus, { label: string; bg: string; fg: string; rail: string }> = {
  confirmed: { label: '예약 확정', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  pending: { label: '러너 응답 대기', bg: '#FDE8D0', fg: '#9D580A', rail: '#F59A43' }, // 앰버×탠저린 50:50 — 카운트다운의 색 (기대감, 코랄 불침범)
  handoff: { label: '인계 완료 · 시작 대기', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  active: { label: '러닝 중 · LIVE', bg: '#eaf7c8', fg: '#4a6d1f', rail: colors.volt },
  completed: { label: '완료', bg: '#E3EEF8', fg: '#4A6E93', rail: '#6E9BC5' }, // 소프트 에너지 블루 — 그레이는 '끝'처럼 죽어 보였다; 완주는 성과다
  cancelled: { label: '취소됨', bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' },
};

const paceMin = (label: string) => (label.includes('8') ? 8 : label.includes('6') ? 6 : 7);

export default function Schedule() {
  const df = useDisplayFont(); // 표준 탭 헤더 — 좌측 BHS 30

  const [filterIdx, setFilterIdx] = useState(0);
  const [selected, setSelected] = useState<Booking | null>(null);
  const [sheetMode, setSheetMode] = useState<'detail' | 'cancel'>('detail');
  const [liveBookings, setLiveBookings] = useState<Booking[]>([]);
  // 완료 카드 미니 패치 — routeId → 내 패치 (파생 데이터, 1회 조회)
  const [patchMap, setPatchMap] = useState<Record<string, CoursePatch>>({});
  const [refreshing, setRefreshing] = useState(false);

  const load = () => fetchMyBookings().then(setLiveBookings).catch((e) => console.warn('[schedule] bookings:', e?.message ?? e));
  useFocusEffect(useCallback(() => {
    load();
    fetchCoursePatches()
      .then(({ earned }) => setPatchMap(Object.fromEntries(earned.map((pt) => [pt.routeId, pt]))))
      .catch(() => {});
  }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const all = liveBookings; // 데모 예약 제거 — 실예약만
  const visible = all.filter(FILTERS[filterIdx].match);
  const groups = visible.reduce<Record<string, Booking[]>>((acc, b) => {
    (acc[b.dateLabel] = acc[b.dateLabel] ?? []).push(b);
    return acc;
  }, {});

  const open = (b: Booking) => {
    // 실예약이 러너 확정 전이면 관리 시트 대신 상태 안내
    if (b.live && !b.matched) {
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

  const route = selected ? sampleRoutes.find((r) => r.id === selected.routeId) : undefined;
  // live 예약은 실러너 이름으로 뷰 구성 — 목업 프로필 조회 금지
  const mockRunner = selected && !selected.live ? runners.find((r) => r.id === selected.runnerId) : undefined;
  const runner = selected
    ? mockRunner ?? {
        id: 'live', name: selected.runnerName, char: selected.runnerName[0] ?? '러', color: '#5a7a3c',
        rating: null as number | null, reviews: null as number | null, runs: null as number | null,
        pace: null as string | null, badges: ['신원인증'], desc: null as string | null,
        distanceKm: 0,
      }
    : undefined;
  const runMin = selected ? selected.km * paceMin(selected.paceLabel) : 0;
  const fee = selected ? Math.round(selected.price * cancelPolicy.feeRate) : 0;

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: 56, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <View style={{ paddingHorizontal: 16 }}>
        {/* 표준 탭 헤더 — 탭 루트엔 뒤로가기 없음 (바텀 내비가 탈출구), 좌측 타이틀 + 그레이 서브 */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View>
            <Text style={[{ fontSize: 30, fontWeight: '900', color: FOREST }, df]}>내 일정</Text>
            <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 4 }}>실예약 {liveBookings.length}건</Text>
          </View>
          <Pressable onPress={() => router.push('/owner/request')} style={[s.circleBtn, { backgroundColor: FOREST }]}>
            <Text style={{ fontSize: 19.5, color: colors.volt }}>＋</Text>
          </Pressable>
        </Row>

        {/* 주간/월간 데드 토글 은퇴 (ui-audit P1) — 기능이 생길 때 복귀 */}

        {/* filters (functional) */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 12 }} contentContainerStyle={{ gap: 8 }}>
          {FILTERS.map((f, i) => (
            <Pressable
              key={f.label}
              onPress={() => setFilterIdx(i)}
              style={[s.filter, { backgroundColor: filterIdx === i ? f.sel : f.tint, borderColor: filterIdx === i ? f.sel : '#DCD6C4' }]}
            >
              <Text style={{ fontSize: 14, fontWeight: filterIdx === i ? '800' : '700', color: filterIdx === i ? f.selFg : f.tintFg }}>{f.label}</Text>
            </Pressable>
          ))}
        </ScrollView>

        </View>

        {/* agenda — 풀와이드 밴드 (모던 패스: 카드 수프 → 엣지-투-엣지) */}
        {visible.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 23 }}>
              {liveBookings.length === 0 ? '예정된 러닝이 없어요\n홈에서 슬라이드로 예약해보세요' : '이 조건의 일정이 없어요'}
            </Text>
          </View>
        )}
        {Object.entries(groups).map(([dateLabel, items]) => (
          <View key={dateLabel} style={{ marginTop: 18 }}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#49524a', paddingHorizontal: 12, marginBottom: 8 }}>{dateLabel}</Text>
            {items.map((b) => {
              const st = STATUS_STYLE[b.status];
              const rt = sampleRoutes.find((r) => r.id === b.routeId);
              return (
                <Pressable key={b.id} style={s.bookingCard} onPress={() => open(b)}>
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
                        <Text style={{ fontSize: 18, fontWeight: '900', color: FOREST }}>{b.timeLabel}</Text>
                        {b.recurring && (
                          <View style={s.recurPill}><Text style={{ fontSize: 10, fontWeight: '800', color: '#4a6d1f' }}>⟳ 매주</Text></View>
                        )}
                        {b.live && (
                          <View style={s.livePillSm}><Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>● LIVE</Text></View>
                        )}
                      </Row>
                      <View style={[s.statusPill, { backgroundColor: st.bg }]}>
                        <Text style={{ fontSize: 11, fontWeight: '800', color: st.fg }}>{st.label}</Text>
                      </View>
                    </Row>
                    <Row style={{ gap: 12, marginTop: 10 }}>
                      {rt && (
                        <View style={s.thumbMap}>
                          <HeatTrace points={rt.trace} width={64} height={48} />
                        </View>
                      )}
                      <View style={{ flex: 1 }}>
                        <Row style={{ gap: 4 }}>
                          <Text style={{ fontSize: 15, fontWeight: '800', color: FOREST }}>{b.routeName}</Text>
                          <View style={s.certDot}><Text style={{ fontSize: 8, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                        </Row>
                        <Text style={{ fontSize: 13, color: '#49524a', marginTop: 3 }}>
                          {b.dogName} · {b.runnerName} 러너 · {b.km}km
                        </Text>
                        <Text style={{ fontSize: 12.5, color: colors.dim, marginTop: 2 }}>
                          {b.price.toLocaleString()}원 · {b.paceLabel}
                        </Text>
                      </View>
                      {/* 완료 = 패치 + 인증샷 원탭 (2026-07-28 목업 확정) · 그 외 = 셰브런 */}
                      {b.status === 'completed' ? (
                        // 공유 진입을 일정 카드에 직결 (Sean 2026-07-29 — 리포트 안에 묻혀 있던 문제)
                        <View style={{ alignItems: 'center', gap: 6, alignSelf: 'center' }}>
                          {patchMap[b.routeId] && (
                            <Pressable onPress={(e) => { e.stopPropagation(); router.push('/cards'); }}>
                              <PatchBadge km={patchMap[b.routeId].km} grade={patchMap[b.routeId].grade} size={34} />
                            </Pressable>
                          )}
                          <Pressable
                            onPress={(e) => { e.stopPropagation(); router.push(`/shot/${b.id}`); }}
                            style={s.shotChip}
                          >
                            <Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>📸 공유 카드</Text>
                          </Pressable>
                          <Pressable
                            onPress={(e) => {
                              e.stopPropagation();
                              shareRunToFeed(b.id)
                                .then(() => Alert.alert('피드에 올렸어요 🐾', '동네 피드에서 확인해보세요'))
                                .catch((err) => Alert.alert('피드 공유', (err as Error).message));
                            }}
                            style={[s.shotChip, { backgroundColor: '#e7efd8' }]}
                          >
                            <Text style={{ fontSize: 11.5, fontWeight: '900', color: '#3d5a2b' }}>🐕 피드 자랑</Text>
                          </Pressable>
                        </View>
                      ) : (
                        <Text style={{ fontSize: 16, color: colors.dim, alignSelf: 'center' }}>›</Text>
                      )}
                    </Row>
                    {b.status === 'active' && (
                      <Pressable
                        onPress={(e) => { e.stopPropagation(); draft.bookingId = b.id; router.push('/owner/live'); }}
                        style={s.goLiveBtn}
                      >
                        <Text style={{ fontSize: 15, fontWeight: '900', color: '#d84a2f' }}>● 실시간 보기 ›</Text>
                      </Pressable>
                    )}
                  </View>
                </Pressable>
              );
            })}
          </View>
        ))}

        <Pressable style={s.emptyCta} onPress={() => router.push('/owner/request')}>
          <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#5a7a3c' }}>＋ 새 러닝 예약하기</Text>
        </Pressable>
      </ScrollView>
      <BottomNav />

      {/* ---------- booking management sheet ---------- */}
      <Modal visible={!!selected} transparent animationType="slide" onRequestClose={close}>
        <Pressable style={s.backdrop} onPress={close} />
        {selected && route && runner && (
          <View style={s.sheet}>
            <View style={s.handle} />
            <ScrollView showsVerticalScrollIndicator={false} style={{ maxHeight: 560 }}>
              {sheetMode === 'detail' ? (
                <>
                  {/* header */}
                  <Row style={{ justifyContent: 'space-between' }}>
                    <View>
                      <Text style={{ fontSize: 14, color: colors.dim }}>{selected.dateLabel}</Text>
                      <Text style={{ fontSize: 25.5, fontWeight: '900', color: FOREST, marginTop: 2 }}>
                        {selected.timeLabel} · {selected.dogName}
                      </Text>
                    </View>
                    <View style={[s.statusPill, { backgroundColor: STATUS_STYLE[selected.status].bg, alignSelf: 'flex-start' }]}>
                      <Text style={{ fontSize: 11.5, fontWeight: '800', color: STATUS_STYLE[selected.status].fg }}>
                        {STATUS_STYLE[selected.status].label}
                      </Text>
                    </View>
                  </Row>

                  {/* route card */}
                  <View style={s.sheetCard}>
                    <Row style={{ gap: 5 }}>
                      <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{route.name}</Text>
                      <View style={s.certDot}><Text style={{ fontSize: 8, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                      <Text style={{ fontSize: 12, color: colors.dim, alignSelf: 'center' }}>안심 코스 · {route.checkedAt}</Text>
                    </Row>
                    <View style={s.sheetMap}>
                      <HeatTrace points={route.trace} width={278} height={110} />
                    </View>
                    <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
                      {route.features.map((f) => (
                        <View key={f.label} style={s.featChip}>
                          <Text style={{ fontSize: 11.5, color: '#5a7a3c' }}>{f.g}</Text>
                          <Text style={{ fontSize: 12, fontWeight: '700', color: '#3d5a2b' }}>{f.label}</Text>
                        </View>
                      ))}
                    </Row>
                    <Text style={{ fontSize: 13, color: '#75806f', marginTop: 9, lineHeight: 19.5 }}>{route.desc}</Text>
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
                          <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{runner.name} 러너</Text>
                          {runner.badges.map((b) => (
                            <View key={b} style={s.badgePill}><Text style={{ fontSize: 10, fontWeight: '800', color: '#4a6d1f' }}>{b}</Text></View>
                          ))}
                        </Row>
                        <Text style={{ fontSize: 13, color: colors.dim, marginTop: 3 }}>
                          {runner.rating != null
                            ? `★ ${runner.rating} (${runner.reviews}) · 러닝 ${runner.runs}회 · 평균 ${runner.pace}`
                            : '실러너 · 상세 프로필 준비 중'}
                        </Text>
                      </View>
                      <Pressable style={s.chatChip} onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/chat', params: { bid } }); }}>
                        <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#4a6d1f' }}>채팅</Text>
                      </Pressable>
                    </Row>
                    {runner.desc && (
                      <Text style={{ fontSize: 13, color: '#75806f', marginTop: 10, lineHeight: 19.5 }}>{runner.desc}</Text>
                    )}
                  </View>

                  {/* actions — 상태별: 진행 중엔 라이브만, 완료엔 기록만, 시작 전에만 변경·취소 */}
                  {selected.status === 'active' ? (
                    <>
                      <Pressable
                        style={[s.primaryAction, { backgroundColor: '#ffe9e2', borderWidth: 1.2, borderColor: '#ffc9b8' }]}
                        onPress={() => { draft.bookingId = selected.id; close(); router.push('/owner/live'); }}
                      >
                        <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#d84a2f' }}>● 실시간 보기</Text>
                        <Text style={{ fontSize: 12, color: '#b06a56', marginTop: 2 }}>러닝이 진행 중이에요 — GPS·바디캠으로 지켜보세요</Text>
                      </Pressable>
                      <Text style={{ fontSize: 12.5, color: colors.dim, textAlign: 'center', marginTop: 12, lineHeight: 18.5 }}>
                        이미 시작된 러닝은 일정 변경·취소가 불가능해요{'\n'}긴급 상황은 안심 센터 SOS를 이용해주세요
                      </Text>
                    </>
                  ) : selected.status === 'handoff' ? (
                    <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', marginTop: 16, lineHeight: 19.5 }}>
                      인계가 완료됐어요 — 러너가 러닝을 시작하면{'\n'}실시간 보기가 열려요 · 변경·취소는 불가능해요
                    </Text>
                  ) : selected.status === 'completed' ? (
                    <>
                      <Pressable
                        style={s.primaryAction}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid } }); }}
                      >
                        <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>러닝 리포트 보기</Text>
                        <Text style={{ fontSize: 12, color: '#5d6b4a', marginTop: 2 }}>실거리·시간·페이스·종료 사유를 확인해요</Text>
                      </Pressable>
                      {/* 인증샷 바로가기 — 완료 러닝의 자랑 동선 한 탭 단축 (공유가 곧 마케팅) */}
                      <Pressable
                        style={s.ghostAction}
                        onPress={() => { const bid = selected.id; close(); router.push({ pathname: '/owner/report', params: { bid, shot: '1' } }); }}
                      >
                        <Text style={{ fontSize: 15, fontWeight: '800', color: '#3d5a2b' }}>📸 인증샷 만들기</Text>
                      </Pressable>
                      <Pressable
                        style={s.ghostAction}
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
                        <Text style={{ fontSize: 15.5, fontWeight: '800', color: '#3d5a2b' }}>⟳ 이대로 다시 예약</Text>
                        <Text style={{ fontSize: 12, color: colors.dim, marginTop: 2 }}>같은 거리·페이스{selected.runnerProfileId ? ` · ${selected.runnerName} 러너 지명` : ''} — 시간만 골라요</Text>
                      </Pressable>
                    </>
                  ) : (
                    <>
                      <Pressable
                        style={s.primaryAction}
                        onPress={() => {
                          // 제안 화면 직행 (0016) — 취소·재예약이 아니라 러너 동의 기반 시간 변경
                          const bid = selected.id;
                          close();
                          router.push({ pathname: '/owner/reschedule', params: { bid } });
                        }}
                      >
                        <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>일정 변경 요청</Text>
                        <Text style={{ fontSize: 12, color: '#5d6b4a', marginTop: 2 }}>{runner.name} 러너의 가능 시간에서 새 시간을 제안해요</Text>
                      </Pressable>
                      <Pressable
                        style={s.ghostAction}
                        onPress={() => { close(); router.push('/owner/request'); }}
                      >
                        <Text style={{ fontSize: 15.5, fontWeight: '800', color: '#3d453d' }}>러너 변경</Text>
                        <Text style={{ fontSize: 12, color: colors.dim, marginTop: 2 }}>처음부터 일반 예약 과정으로 돌아가요</Text>
                      </Pressable>
                      <Pressable style={s.cancelLink} onPress={() => setSheetMode('cancel')}>
                        <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#d84a2f' }}>일정 취소하기</Text>
                      </Pressable>
                    </>
                  )}
                  {/* 반복 해지 (0026) — 구독은 반드시 끌 수 있어야 한다. 상태 무관 노출 */}
                  {selected.seriesId && (
                    <Pressable style={s.cancelLink} onPress={pauseSeries}>
                      <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#8a8a8a' }}>⟳ 매주 반복 해지</Text>
                    </Pressable>
                  )}
                </>
              ) : (
                <>
                  {/* cancel confirmation */}
                  <Text style={{ fontSize: 23, fontWeight: '900', color: FOREST }}>일정을 취소할까요?</Text>
                  <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 6 }}>
                    {selected.dateLabel} {selected.timeLabel} · {runner.name} 러너
                  </Text>

                  <View style={[s.sheetCard, { borderColor: '#f2d4ca' }]}>
                    <FeeLine label="결제 금액" value={`${selected.price.toLocaleString()}원`} />
                    <FeeLine label={`취소 수수료 (${cancelPolicy.feeRate * 100}%)`} value={`−${fee.toLocaleString()}원`} coral />
                    <View style={{ height: 1, backgroundColor: '#f0eee3', marginVertical: 10 }} />
                    <FeeLine label="환불 금액" value={`${(selected.price - fee).toLocaleString()}원`} bold />
                    <Text style={{ fontSize: 12, color: colors.dim, marginTop: 10, lineHeight: 17 }}>
                      취소 수수료는 시간을 비워둔 러너에게 {Math.round(cancelPolicy.runnerShare * 100)}%, 도그스하이에 {Math.round((1 - cancelPolicy.runnerShare) * 100)}% 배분돼요.{'\n'}시작 24시간 전까지는 수수료가 없어요.
                    </Text>
                  </View>

                  <Pressable
                    style={s.cancelConfirm}
                    onPress={async () => {
                      // 🔴 실취소 — 서버 cancel_owner가 수수료 계산 + 상태 전이 (목업 알럿 은퇴, fake-inventory)
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
                    <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#49524a' }}>돌아가기</Text>
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
      <Text style={{ fontSize: 12, color: colors.dim }}>{label}</Text>
      <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 3 }}>{value}</Text>
      <Text style={{ fontSize: 11, color: colors.dim, marginTop: 2 }}>{sub}</Text>
    </View>
  );
}

function FeeLine({ label, value, coral, bold }: { label: string; value: string; coral?: boolean; bold?: boolean }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 5 }}>
      <Text style={{ fontSize: 14.5, color: bold ? FOREST : '#75806f', fontWeight: bold ? '800' : '400' }}>{label}</Text>
      <Text style={{ fontSize: bold ? 16 : 12.5, fontWeight: bold ? '900' : '600', color: coral ? '#d84a2f' : FOREST }}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  viewToggle: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 99, padding: 4, marginTop: 16, borderWidth: 1, borderColor: '#DCD6C4' },
  viewTab: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 99 },
  comingSoon: { backgroundColor: '#f4f2ea', borderRadius: 12, padding: 10, marginTop: 10 },
  filter: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  emptyBox: { marginTop: 24, marginHorizontal: 12, padding: 18, backgroundColor: '#f4f2ea', borderRadius: 16 },
  bookingCard: { flexDirection: 'row', backgroundColor: '#fff', borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#DCD6C4', marginTop: -1, overflow: 'hidden' },
  rail: { width: 8 }, // 상태 컬러 레일 1.6배 (5→8)
  // 확정 카드 절취선 — 레일 경계 x=8 중심 (노치 지름 10, 도트 2.5)
  perfWrap: { position: 'absolute', left: 3, top: 0, bottom: 0, width: 10, alignItems: 'center' },
  perfNotch: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.cream, borderWidth: 1, borderColor: '#DCD6C4' },
  perfDot: { width: 2.5, height: 2.5, borderRadius: 1.25, backgroundColor: colors.cream },
  recurPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  livePillSm: { backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  statusPill: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  goLiveBtn: {
    marginTop: 11, backgroundColor: '#ffe9e2', borderRadius: 12, alignItems: 'center',
    paddingVertical: 12, borderWidth: 1.2, borderColor: '#ffc9b8',
  },
  thumbMap: { width: 68, height: 52, borderRadius: 10, backgroundColor: '#0e150f', padding: 2, overflow: 'hidden' },
  certDot: { width: 13, height: 13, borderRadius: 7, backgroundColor: '#3d8fd4', alignItems: 'center', justifyContent: 'center', alignSelf: 'center' },
  shotChip: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10, shadowColor: '#7FA818', shadowOpacity: 0.35, shadowRadius: 4, shadowOffset: { width: 0, height: 2 } },
  emptyCta: {
    marginTop: 20, marginHorizontal: 12, borderRadius: 16, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed',
    alignItems: 'center', paddingVertical: 14,
  },
  // sheet
  backdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 16, paddingBottom: 36 },
  handle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#DCD6C4', marginBottom: 14 },
  sheetCard: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#DCD6C4', marginTop: 12 },
  sheetMap: { marginTop: 10, borderRadius: 14, backgroundColor: '#0e150f', paddingVertical: 6, paddingHorizontal: 4, overflow: 'hidden', alignItems: 'center' },
  featChip: { flexDirection: 'row', gap: 4, alignItems: 'center', backgroundColor: '#eef4e0', borderRadius: 9, paddingVertical: 4, paddingHorizontal: 8 },
  vDiv: { width: 1, backgroundColor: '#f0eee3' },
  badgePill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  chatChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 13, alignSelf: 'center' },
  primaryAction: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14, marginTop: 16 },
  ghostAction: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 8 },
  cancelLink: { alignItems: 'center', paddingVertical: 14, marginTop: 4 },
  cancelConfirm: { backgroundColor: '#e8492a', borderRadius: 16, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
});
