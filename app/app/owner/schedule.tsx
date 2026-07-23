import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { fetchMyBookings } from '../../src/lib/api';
import { BottomNav } from '../../src/components/bottomnav';
import { HeatTrace } from '../../src/components/runcard';
import { Monogram, Row } from '../../src/components/ui';
import { Booking, BookingStatus, cancelPolicy, draft, runners, sampleRoutes } from '../../src/store';
import { colors } from '../../src/theme';

// 내 일정 — agenda view. Tapping a booking opens a management sheet
// (route card + predictions + runner + reschedule/cancel actions).
// A confirmed booking is a contract — never re-routes to runner selection.

const FOREST = '#132117';
const VIEWS = ['일정', '주간', '월간'];
const FILTERS: { label: string; match: (b: Booking) => boolean }[] = [
  { label: '전체', match: () => true },
  { label: '예약 확정', match: (b) => b.status === 'confirmed' },
  { label: '응답 대기', match: (b) => b.status === 'pending' },
  { label: '완료', match: (b) => b.status === 'completed' },
  { label: '반복', match: (b) => !!b.recurring },
];

const STATUS_STYLE: Record<BookingStatus, { label: string; bg: string; fg: string; rail: string }> = {
  confirmed: { label: '예약 확정', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  pending: { label: '러너 응답 대기', bg: '#fbf0d4', fg: '#a97c12', rail: '#e2c56b' },
  handoff: { label: '인계 완료 · 시작 대기', bg: '#e3f0c4', fg: '#3d5a2b', rail: '#5a7a3c' },
  active: { label: '러닝 중 · LIVE', bg: '#eaf7c8', fg: '#4a6d1f', rail: colors.volt },
  completed: { label: '완료', bg: '#e9ebe2', fg: '#75806f', rail: '#c9ccc0' },
  cancelled: { label: '취소됨', bg: '#ececec', fg: '#8a8a8a', rail: '#c9c9c9' },
};

const paceMin = (label: string) => (label.includes('8') ? 8 : label.includes('6') ? 6 : 7);

export default function Schedule() {
  const [view, setView] = useState('일정');
  const [filterIdx, setFilterIdx] = useState(0);
  const [selected, setSelected] = useState<Booking | null>(null);
  const [sheetMode, setSheetMode] = useState<'detail' | 'cancel'>('detail');
  const [liveBookings, setLiveBookings] = useState<Booking[]>([]);

  useFocusEffect(useCallback(() => {
    fetchMyBookings().then(setLiveBookings).catch((e) => console.warn('[schedule] bookings:', e?.message ?? e));
  }, []));

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
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 30 }}>
        {/* header */}
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={{ alignItems: 'center' }}>
            <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>내 일정</Text>
            <Text style={{ fontSize: 11, color: colors.dim, marginTop: 1 }}>실예약 {liveBookings.length}건</Text>
          </View>
          <Pressable onPress={() => router.push('/owner/request')} style={[s.circleBtn, { backgroundColor: FOREST }]}>
            <Text style={{ fontSize: 17, color: colors.volt }}>＋</Text>
          </Pressable>
        </Row>

        {/* view toggle */}
        <View style={s.viewToggle}>
          {VIEWS.map((v) => (
            <Pressable key={v} onPress={() => setView(v)} style={[s.viewTab, view === v && { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: view === v ? '#fff' : '#5d655d' }}>{v}</Text>
            </Pressable>
          ))}
        </View>
        {view !== '일정' && (
          <View style={s.comingSoon}>
            <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center' }}>{view} 뷰는 준비 중이에요 — 일정 뷰를 이용해주세요</Text>
          </View>
        )}

        {/* filters (functional) */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 12 }} contentContainerStyle={{ gap: 8 }}>
          {FILTERS.map((f, i) => (
            <Pressable key={f.label} onPress={() => setFilterIdx(i)} style={[s.filter, filterIdx === i && { backgroundColor: FOREST, borderColor: FOREST }]}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: filterIdx === i ? '#fff' : '#3d453d' }}>{f.label}</Text>
            </Pressable>
          ))}
        </ScrollView>

        {/* agenda */}
        {visible.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 20 }}>
              {liveBookings.length === 0 ? '예정된 러닝이 없어요\n홈에서 슬라이드로 예약해보세요' : '이 조건의 일정이 없어요'}
            </Text>
          </View>
        )}
        {Object.entries(groups).map(([dateLabel, items]) => (
          <View key={dateLabel} style={{ marginTop: 18 }}>
            <Text style={{ fontSize: 13, fontWeight: '900', color: '#5d655d' }}>{dateLabel}</Text>
            {items.map((b) => {
              const st = STATUS_STYLE[b.status];
              const rt = sampleRoutes.find((r) => r.id === b.routeId);
              return (
                <Pressable key={b.id} style={s.bookingCard} onPress={() => open(b)}>
                  <View style={[s.rail, { backgroundColor: st.rail }]} />
                  <View style={{ flex: 1, padding: 14 }}>
                    <Row style={{ justifyContent: 'space-between' }}>
                      <Row style={{ gap: 6 }}>
                        <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>{b.timeLabel}</Text>
                        {b.recurring && (
                          <View style={s.recurPill}><Text style={{ fontSize: 8.5, fontWeight: '800', color: '#4a6d1f' }}>⟳ 매주</Text></View>
                        )}
                        {b.live && (
                          <View style={s.livePillSm}><Text style={{ fontSize: 8.5, fontWeight: '900', color: '#fff' }}>● LIVE</Text></View>
                        )}
                      </Row>
                      <View style={[s.statusPill, { backgroundColor: st.bg }]}>
                        <Text style={{ fontSize: 9.5, fontWeight: '800', color: st.fg }}>{st.label}</Text>
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
                          <Text style={{ fontSize: 13, fontWeight: '800', color: FOREST }}>{b.routeName}</Text>
                          <View style={s.certDot}><Text style={{ fontSize: 7, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                        </Row>
                        <Text style={{ fontSize: 11.5, color: '#5d655d', marginTop: 3 }}>
                          {b.dogName} · {b.runnerName} 러너 · {b.km}km
                        </Text>
                        <Text style={{ fontSize: 11, color: colors.dim, marginTop: 2 }}>
                          {b.price.toLocaleString()}원 · {b.paceLabel}
                        </Text>
                      </View>
                      <Text style={{ fontSize: 14, color: colors.dim, alignSelf: 'center' }}>›</Text>
                    </Row>
                    {b.status === 'active' && (
                      <Pressable
                        onPress={(e) => { e.stopPropagation(); draft.bookingId = b.id; router.push('/owner/live'); }}
                        style={s.goLiveBtn}
                      >
                        <Text style={{ fontSize: 13, fontWeight: '900', color: '#d84a2f' }}>● 실시간 보기 ›</Text>
                      </Pressable>
                    )}
                  </View>
                </Pressable>
              );
            })}
          </View>
        ))}

        <Pressable style={s.emptyCta} onPress={() => router.push('/owner/request')}>
          <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#5a7a3c' }}>＋ 새 러닝 예약하기</Text>
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
                      <Text style={{ fontSize: 12, color: colors.dim }}>{selected.dateLabel}</Text>
                      <Text style={{ fontSize: 22, fontWeight: '900', color: FOREST, marginTop: 2 }}>
                        {selected.timeLabel} · {selected.dogName}
                      </Text>
                    </View>
                    <View style={[s.statusPill, { backgroundColor: STATUS_STYLE[selected.status].bg, alignSelf: 'flex-start' }]}>
                      <Text style={{ fontSize: 10, fontWeight: '800', color: STATUS_STYLE[selected.status].fg }}>
                        {STATUS_STYLE[selected.status].label}
                      </Text>
                    </View>
                  </Row>

                  {/* route card */}
                  <View style={s.sheetCard}>
                    <Row style={{ gap: 5 }}>
                      <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{route.name}</Text>
                      <View style={s.certDot}><Text style={{ fontSize: 7, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                      <Text style={{ fontSize: 10.5, color: colors.dim, alignSelf: 'center' }}>안심 코스 · {route.checkedAt}</Text>
                    </Row>
                    <View style={s.sheetMap}>
                      <HeatTrace points={route.trace} width={278} height={110} />
                    </View>
                    <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
                      {route.features.map((f) => (
                        <View key={f.label} style={s.featChip}>
                          <Text style={{ fontSize: 10, color: '#5a7a3c' }}>{f.g}</Text>
                          <Text style={{ fontSize: 10.5, fontWeight: '700', color: '#3d5a2b' }}>{f.label}</Text>
                        </View>
                      ))}
                    </Row>
                    <Text style={{ fontSize: 11.5, color: '#75806f', marginTop: 9, lineHeight: 17 }}>{route.desc}</Text>
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
                          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{runner.name} 러너</Text>
                          {runner.badges.map((b) => (
                            <View key={b} style={s.badgePill}><Text style={{ fontSize: 8.5, fontWeight: '800', color: '#4a6d1f' }}>{b}</Text></View>
                          ))}
                        </Row>
                        <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 3 }}>
                          {runner.rating != null
                            ? `★ ${runner.rating} (${runner.reviews}) · 러닝 ${runner.runs}회 · 평균 ${runner.pace}`
                            : '실러너 · 상세 프로필 준비 중'}
                        </Text>
                      </View>
                      <Pressable style={s.chatChip} onPress={() => { close(); router.push('/chat'); }}>
                        <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>채팅</Text>
                      </Pressable>
                    </Row>
                    {runner.desc && (
                      <Text style={{ fontSize: 11.5, color: '#75806f', marginTop: 10, lineHeight: 17 }}>{runner.desc}</Text>
                    )}
                  </View>

                  {/* actions — 상태별: 진행 중엔 라이브만, 완료엔 기록만, 시작 전에만 변경·취소 */}
                  {selected.status === 'active' ? (
                    <>
                      <Pressable
                        style={[s.primaryAction, { backgroundColor: '#ffe9e2', borderWidth: 1.2, borderColor: '#ffc9b8' }]}
                        onPress={() => { draft.bookingId = selected.id; close(); router.push('/owner/live'); }}
                      >
                        <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#d84a2f' }}>● 실시간 보기</Text>
                        <Text style={{ fontSize: 10.5, color: '#b06a56', marginTop: 2 }}>러닝이 진행 중이에요 — GPS·바디캠으로 지켜보세요</Text>
                      </Pressable>
                      <Text style={{ fontSize: 11, color: colors.dim, textAlign: 'center', marginTop: 12, lineHeight: 16 }}>
                        이미 시작된 러닝은 일정 변경·취소가 불가능해요{'\n'}긴급 상황은 안심 센터 SOS를 이용해주세요
                      </Text>
                    </>
                  ) : selected.status === 'handoff' ? (
                    <Text style={{ fontSize: 11.5, color: colors.dim, textAlign: 'center', marginTop: 16, lineHeight: 17 }}>
                      인계가 완료됐어요 — 러너가 러닝을 시작하면{'\n'}실시간 보기가 열려요 · 변경·취소는 불가능해요
                    </Text>
                  ) : selected.status === 'completed' ? (
                    <Pressable style={s.ghostAction} onPress={() => { close(); router.push('/cards'); }}>
                      <Text style={{ fontSize: 13.5, fontWeight: '800', color: '#3d453d' }}>러닝 기록 보기</Text>
                      <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 2 }}>완료된 러닝의 카드와 기록을 확인해요</Text>
                    </Pressable>
                  ) : (
                    <>
                      <Pressable
                        style={s.primaryAction}
                        onPress={() => {
                          close();
                          Alert.alert('같은 러너로 일정 변경', `${runner.name} 러너의 가능한 슬롯만 표시된 예약 화면으로 이동해요 (목업)`);
                          router.push('/owner/request');
                        }}
                      >
                        <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>같은 러너로 일정 변경</Text>
                        <Text style={{ fontSize: 10.5, color: '#5d6b4a', marginTop: 2 }}>{runner.name} 러너의 열린 슬롯에서 다시 선택해요</Text>
                      </Pressable>
                      <Pressable
                        style={s.ghostAction}
                        onPress={() => { close(); router.push('/owner/request'); }}
                      >
                        <Text style={{ fontSize: 13.5, fontWeight: '800', color: '#3d453d' }}>러너 변경</Text>
                        <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 2 }}>처음부터 일반 예약 과정으로 돌아가요</Text>
                      </Pressable>
                      <Pressable style={s.cancelLink} onPress={() => setSheetMode('cancel')}>
                        <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#d84a2f' }}>일정 취소하기</Text>
                      </Pressable>
                    </>
                  )}
                </>
              ) : (
                <>
                  {/* cancel confirmation */}
                  <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>일정을 취소할까요?</Text>
                  <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 6 }}>
                    {selected.dateLabel} {selected.timeLabel} · {runner.name} 러너
                  </Text>

                  <View style={[s.sheetCard, { borderColor: '#f2d4ca' }]}>
                    <FeeLine label="결제 금액" value={`${selected.price.toLocaleString()}원`} />
                    <FeeLine label={`취소 수수료 (${cancelPolicy.feeRate * 100}%)`} value={`−${fee.toLocaleString()}원`} coral />
                    <View style={{ height: 1, backgroundColor: '#f0eee3', marginVertical: 10 }} />
                    <FeeLine label="환불 금액" value={`${(selected.price - fee).toLocaleString()}원`} bold />
                    <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 10, lineHeight: 15 }}>
                      취소 수수료는 시간을 비워둔 러너에게 {Math.round(cancelPolicy.runnerShare * 100)}%, 댕런에 {Math.round((1 - cancelPolicy.runnerShare) * 100)}% 배분돼요.{'\n'}시작 24시간 전까지는 수수료가 없어요.
                    </Text>
                  </View>

                  <Pressable
                    style={s.cancelConfirm}
                    onPress={() => { close(); Alert.alert('취소 완료', `환불 ${(selected.price - fee).toLocaleString()}원이 3일 내 처리돼요 (목업)`); }}
                  >
                    <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#fff' }}>취소하고 {(selected.price - fee).toLocaleString()}원 환불받기</Text>
                  </Pressable>
                  <Pressable style={s.cancelLink} onPress={() => setSheetMode('detail')}>
                    <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#5d655d' }}>돌아가기</Text>
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
      <Text style={{ fontSize: 10.5, color: colors.dim }}>{label}</Text>
      <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 3 }}>{value}</Text>
      <Text style={{ fontSize: 9.5, color: colors.dim, marginTop: 2 }}>{sub}</Text>
    </View>
  );
}

function FeeLine({ label, value, coral, bold }: { label: string; value: string; coral?: boolean; bold?: boolean }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 5 }}>
      <Text style={{ fontSize: 12.5, color: bold ? FOREST : '#75806f', fontWeight: bold ? '800' : '400' }}>{label}</Text>
      <Text style={{ fontSize: bold ? 16 : 12.5, fontWeight: bold ? '900' : '600', color: coral ? '#d84a2f' : FOREST }}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  viewToggle: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 99, padding: 4, marginTop: 16, borderWidth: 1, borderColor: '#eceadf' },
  viewTab: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 99 },
  comingSoon: { backgroundColor: '#f4f2ea', borderRadius: 12, padding: 10, marginTop: 10 },
  filter: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14, borderWidth: 1, borderColor: '#eceadf' },
  emptyBox: { marginTop: 24, padding: 24, backgroundColor: '#f4f2ea', borderRadius: 16 },
  bookingCard: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 18, borderWidth: 1, borderColor: '#eceadf', marginTop: 8, overflow: 'hidden' },
  rail: { width: 5 },
  recurPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  livePillSm: { backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  statusPill: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  goLiveBtn: {
    marginTop: 11, backgroundColor: '#ffe9e2', borderRadius: 12, alignItems: 'center',
    paddingVertical: 12, borderWidth: 1.2, borderColor: '#ffc9b8',
  },
  thumbMap: { width: 68, height: 52, borderRadius: 10, backgroundColor: '#0e150f', padding: 2, overflow: 'hidden' },
  certDot: { width: 13, height: 13, borderRadius: 7, backgroundColor: '#3d8fd4', alignItems: 'center', justifyContent: 'center', alignSelf: 'center' },
  emptyCta: {
    marginTop: 20, borderRadius: 16, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed',
    alignItems: 'center', paddingVertical: 14,
  },
  // sheet
  backdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 22, paddingBottom: 36 },
  handle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#d8d5c8', marginBottom: 14 },
  sheetCard: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 12 },
  sheetMap: { marginTop: 10, borderRadius: 14, backgroundColor: '#0e150f', paddingVertical: 6, paddingHorizontal: 4, overflow: 'hidden', alignItems: 'center' },
  featChip: { flexDirection: 'row', gap: 4, alignItems: 'center', backgroundColor: '#eef4e0', borderRadius: 9, paddingVertical: 4, paddingHorizontal: 8 },
  vDiv: { width: 1, backgroundColor: '#f0eee3' },
  badgePill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  chatChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 13, alignSelf: 'center' },
  primaryAction: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14, marginTop: 16 },
  ghostAction: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf', borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 8 },
  cancelLink: { alignItems: 'center', paddingVertical: 14, marginTop: 4 },
  cancelConfirm: { backgroundColor: '#e8492a', borderRadius: 16, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
});
