import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Monogram, Row } from '../../src/components/ui';
import { Booking, bookings, BookingStatus } from '../../src/store';
import { colors } from '../../src/theme';

// 내 일정 — agenda view (default per docs/calendar.md). 주간/월간 later.

const FOREST = '#132117';
const VIEWS = ['일정', '주간', '월간'];
const FILTERS = ['전체', '예약 확정', '응답 대기', '완료', '반복'];

const STATUS_STYLE: Record<BookingStatus, { label: string; bg: string; fg: string }> = {
  confirmed: { label: '예약 확정', bg: '#e3f0c4', fg: '#3d5a2b' },
  pending: { label: '러너 응답 대기', bg: '#fbf0d4', fg: '#a97c12' },
  active: { label: '러닝 중 · LIVE', bg: '#eaf7c8', fg: '#4a6d1f' },
  completed: { label: '완료', bg: '#e9ebe2', fg: '#75806f' },
  cancelled: { label: '취소됨', bg: '#ececec', fg: '#8a8a8a' },
};

export default function Schedule() {
  const [view, setView] = useState('일정');
  const [filter, setFilter] = useState('전체');

  const groups = bookings.reduce<Record<string, Booking[]>>((acc, b) => {
    (acc[b.dateLabel] = acc[b.dateLabel] ?? []).push(b);
    return acc;
  }, {});

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 30 }}>
        {/* header */}
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={{ alignItems: 'center' }}>
            <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>내 일정</Text>
            <Text style={{ fontSize: 11, color: colors.dim, marginTop: 1 }}>2026년 7월</Text>
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

        {/* filters */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 12 }} contentContainerStyle={{ gap: 8 }}>
          {FILTERS.map((f) => (
            <Pressable key={f} onPress={() => setFilter(f)} style={[s.filter, filter === f && { backgroundColor: FOREST, borderColor: FOREST }]}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: filter === f ? '#fff' : '#3d453d' }}>{f}</Text>
            </Pressable>
          ))}
        </ScrollView>

        {/* agenda */}
        {Object.entries(groups).map(([dateLabel, items]) => (
          <View key={dateLabel} style={{ marginTop: 18 }}>
            <Text style={{ fontSize: 13, fontWeight: '900', color: '#5d655d' }}>{dateLabel}</Text>
            {items.map((b) => {
              const st = STATUS_STYLE[b.status];
              return (
                <Pressable key={b.id} style={s.bookingCard} onPress={() => router.push('/owner/matching')}>
                  <Row style={{ gap: 12 }}>
                    <Monogram char={b.dogName[0]} bg="#c9a86e" size={44} />
                    <View style={{ flex: 1 }}>
                      <Row style={{ gap: 6 }}>
                        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{b.timeLabel}</Text>
                        {b.recurring && (
                          <View style={s.recurPill}><Text style={{ fontSize: 8.5, fontWeight: '800', color: '#4a6d1f' }}>⟳ 매주</Text></View>
                        )}
                      </Row>
                      <Text style={{ fontSize: 12, color: '#5d655d', marginTop: 3 }}>
                        {b.dogName} · {b.runnerName} 러너 ✓ · {b.routeName}
                      </Text>
                      <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>
                        {b.km}km · {b.price.toLocaleString()}원
                      </Text>
                    </View>
                    <View style={{ alignItems: 'flex-end', gap: 8 }}>
                      <View style={[s.statusPill, { backgroundColor: st.bg }]}>
                        <Text style={{ fontSize: 9.5, fontWeight: '800', color: st.fg }}>{st.label}</Text>
                      </View>
                      <Row style={{ gap: 10 }}>
                        <Text style={{ fontSize: 11, fontWeight: '700', color: '#5a7a3c' }}>채팅</Text>
                        <Text style={{ fontSize: 13, color: colors.dim }}>›</Text>
                      </Row>
                    </View>
                  </Row>
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
    </View>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  viewToggle: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 99, padding: 4, marginTop: 16, borderWidth: 1, borderColor: '#eceadf' },
  viewTab: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 99 },
  comingSoon: { backgroundColor: '#f4f2ea', borderRadius: 12, padding: 10, marginTop: 10 },
  filter: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14, borderWidth: 1, borderColor: '#eceadf' },
  bookingCard: { backgroundColor: '#fff', borderRadius: 18, padding: 14, borderWidth: 1, borderColor: '#eceadf', marginTop: 8 },
  recurPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  statusPill: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  emptyCta: {
    marginTop: 20, borderRadius: 16, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed',
    alignItems: 'center', paddingVertical: 14,
  },
});
