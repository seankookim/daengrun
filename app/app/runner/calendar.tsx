import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Row } from '../../src/components/ui';
import { colors } from '../../src/theme';

// 러너 캘린더 — day timeline (default per docs/calendar.md).
// Blocks: confirmed / travel buffer / available / blocked / pending.

const FOREST = '#132117';
const DATES = [
  { d: '22', w: '수', today: true }, { d: '23', w: '목' }, { d: '24', w: '금' },
  { d: '25', w: '토' }, { d: '26', w: '일' }, { d: '27', w: '월' }, { d: '28', w: '화' },
];

type Block =
  | { kind: 'session'; time: string; title: string; sub: string; pay: string; status: '확정' | '대기' }
  | { kind: 'travel'; time: string; note: string; warn?: boolean }
  | { kind: 'free'; time: string }
  | { kind: 'blocked'; time: string; note: string };

const TIMELINE: Block[] = [
  { kind: 'session', time: '07:00–07:45', title: '몽이 · 3km 러닝', sub: '뚝섬한강공원 · 푸들 6kg', pay: '+15,200원', status: '확정' },
  { kind: 'travel', time: '07:45–08:05', note: '이동 20분 · 뚝섬 → 성수' },
  { kind: 'free', time: '08:05–17:50' },
  { kind: 'session', time: '18:30–19:40', title: '초코 · 5km 러닝', sub: '서울숲 · 웰시코기 11kg', pay: '+19,900원', status: '확정' },
  { kind: 'travel', time: '19:40–19:52', note: '이동 시간이 12분 부족해요', warn: true },
  { kind: 'session', time: '19:50–20:50', title: '두부 · 5km 러닝 (요청)', sub: '한강공원 · 비숑 7kg', pay: '+19,900원', status: '대기' },
  { kind: 'blocked', time: '21:00–22:00', note: '개인 일정 · 러닝크루 훈련' },
];

export default function RunnerCalendar() {
  const [dateIdx, setDateIdx] = useState(0);

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 60, paddingBottom: 30 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>캘린더</Text>
            <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>2026년 7월 · 오늘 2건 확정 · 예상 +35,100원</Text>
          </View>
          <Pressable onPress={() => router.push('/runner/availability')} style={s.availBtn}>
            <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#fff' }}>가용시간 설정</Text>
          </Pressable>
        </Row>

        {/* week strip */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }} contentContainerStyle={{ gap: 8 }}>
          {DATES.map((d, i) => (
            <Pressable key={d.d} onPress={() => setDateIdx(i)} style={[s.dateChip, dateIdx === i && { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 10, color: dateIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
              <Text style={{ fontSize: 16, fontWeight: '900', color: dateIdx === i ? '#fff' : FOREST }}>{d.d}</Text>
              {d.today && <View style={{ width: 4, height: 4, borderRadius: 2, backgroundColor: dateIdx === i ? colors.volt : '#5a7a3c' }} />}
            </Pressable>
          ))}
        </ScrollView>

        {/* timeline */}
        <View style={{ marginTop: 18, gap: 8 }}>
          {TIMELINE.map((b, i) => {
            if (b.kind === 'session') {
              const pending = b.status === '대기';
              return (
                <Pressable key={i} onPress={() => router.push('/runner/detail')} style={[s.session, pending && s.sessionPending]}>
                  <View style={[s.timeRail, pending && { backgroundColor: '#e2c56b' }]} />
                  <View style={{ flex: 1 }}>
                    <Row style={{ justifyContent: 'space-between' }}>
                      <Text style={{ fontSize: 12, fontWeight: '800', color: '#5d655d' }}>{b.time}</Text>
                      <View style={[s.statusPill, pending && { backgroundColor: '#fbf0d4' }]}>
                        <Text style={{ fontSize: 9.5, fontWeight: '800', color: pending ? '#a97c12' : '#3d5a2b' }}>{b.status}</Text>
                      </View>
                    </Row>
                    <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 3 }}>{b.title}</Text>
                    <Row style={{ justifyContent: 'space-between', marginTop: 2 }}>
                      <Text style={{ fontSize: 11.5, color: colors.dim }}>{b.sub}</Text>
                      <Text style={{ fontSize: 13, fontWeight: '900', color: '#5a7a3c' }}>{b.pay}</Text>
                    </Row>
                  </View>
                </Pressable>
              );
            }
            if (b.kind === 'travel') {
              return (
                <View key={i} style={[s.travel, b.warn && s.travelWarn]}>
                  <Text style={{ fontSize: 11, fontWeight: '700', color: b.warn ? '#d84a2f' : '#75806f' }}>
                    {b.warn ? '⚠ ' : '↔ '}{b.time} · {b.note}
                  </Text>
                  {b.warn && (
                    <Text style={{ fontSize: 10.5, fontWeight: '800', color: '#d84a2f' }}>시간 조정 ›</Text>
                  )}
                </View>
              );
            }
            if (b.kind === 'blocked') {
              return (
                <View key={i} style={s.blocked}>
                  <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#8a8a8a' }}>⊘ {b.time} · {b.note}</Text>
                </View>
              );
            }
            return (
              <View key={i} style={s.freeGap}>
                <Text style={{ fontSize: 11, color: '#a9b39f' }}>{b.time} · 가용 시간 — 요청을 받을 수 있어요</Text>
              </View>
            );
          })}
        </View>

        {/* legend */}
        <Row style={{ gap: 14, marginTop: 18, flexWrap: 'wrap' }}>
          <Legend color="#5a7a3c" label="확정" />
          <Legend color="#e2c56b" label="응답 대기" />
          <Legend color="#c9ccc0" label="가용" />
          <Legend color="#8a8a8a" label="차단" />
          <Legend color="#d84a2f" label="이동 경고" />
        </Row>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <Row style={{ gap: 5 }}>
      <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: color }} />
      <Text style={{ fontSize: 10.5, color: colors.dim }}>{label}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  availBtn: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 14, alignSelf: 'flex-start' },
  dateChip: { width: 52, borderRadius: 14, backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf', alignItems: 'center', paddingVertical: 9, gap: 2 },
  session: { flexDirection: 'row', gap: 12, backgroundColor: '#fff', borderRadius: 16, padding: 13, borderWidth: 1, borderColor: '#eceadf' },
  sessionPending: { borderColor: '#e9dcae', backgroundColor: '#fffdf4' },
  timeRail: { width: 4, borderRadius: 2, backgroundColor: '#5a7a3c' },
  statusPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  travel: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 7, paddingHorizontal: 14 },
  travelWarn: { backgroundColor: '#fdeae5', borderRadius: 12, paddingVertical: 10 },
  blocked: { backgroundColor: '#efefec', borderRadius: 12, padding: 12 },
  freeGap: {
    borderRadius: 12, borderWidth: 1.2, borderColor: '#dfe4d4', borderStyle: 'dashed',
    padding: 12, alignItems: 'center',
  },
});
