import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { colors } from '../../src/theme';

// 가용시간 설정 — weekly recurring availability + booking rules (docs/calendar.md).

const FOREST = '#132117';

const WEEK: { day: string; ranges: string[] }[] = [
  { day: '월', ranges: ['18:00–22:00'] },
  { day: '화', ranges: [] },
  { day: '수', ranges: ['06:00–09:00', '18:00–22:00'] },
  { day: '목', ranges: ['18:00–22:00'] },
  { day: '금', ranges: ['18:00–21:00'] },
  { day: '토', ranges: ['08:00–18:00'] },
  { day: '일', ranges: ['08:00–12:00'] },
];

const RULES = [
  { label: '최소 통보 시간', value: '2시간 전' },
  { label: '하루 최대 세션', value: '4건' },
  { label: '세션 후 휴식', value: '30분' },
  { label: '최대 픽업 거리', value: '3km' },
  { label: '그룹 러닝 정원', value: '2마리' },
];

export default function Availability() {
  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>가용시간 설정</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginBottom: 16 }}>
        설정한 시간에만 예약 요청을 받아요
      </Text>

      {/* weekly editor */}
      <View style={s.card}>
        {WEEK.map((w, i) => (
          <View key={w.day}>
            {i > 0 && <View style={s.div} />}
            <Row style={{ paddingVertical: 11 }}>
              <Text style={{ width: 30, fontSize: 14, fontWeight: '900', color: w.ranges.length ? FOREST : '#b3b3ab' }}>
                {w.day}
              </Text>
              <Row style={{ flex: 1, gap: 6, flexWrap: 'wrap' }}>
                {w.ranges.length === 0 ? (
                  <Text style={{ fontSize: 12.5, color: '#b3b3ab' }}>쉬는 날</Text>
                ) : (
                  w.ranges.map((r) => (
                    <View key={r} style={s.rangeChip}>
                      <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#3d5a2b' }}>{r}</Text>
                    </View>
                  ))
                )}
              </Row>
              <Pressable onPress={() => Alert.alert('시간대', `${w.day}요일 시간대 편집 (목업)`)}>
                <Text style={{ fontSize: 13, color: '#5a7a3c', fontWeight: '800' }}>＋</Text>
              </Pressable>
            </Row>
          </View>
        ))}
      </View>

      <Pressable style={s.copyBtn} onPress={() => Alert.alert('복사', '다른 요일로 복사 (목업)')}>
        <Text style={{ fontSize: 12, fontWeight: '700', color: '#3d453d' }}>⧉ 다른 요일로 복사</Text>
      </Pressable>

      {/* rules */}
      <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 22, marginBottom: 10 }}>예약 규칙</Text>
      <View style={s.card}>
        {RULES.map((r, i) => (
          <View key={r.label}>
            {i > 0 && <View style={s.div} />}
            <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
              <Text style={{ fontSize: 13.5, color: '#3d453d' }}>{r.label}</Text>
              <Row style={{ gap: 6 }}>
                <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>{r.value}</Text>
                <Text style={{ fontSize: 13, color: colors.dim }}>›</Text>
              </Row>
            </Row>
          </View>
        ))}
      </View>

      {/* exceptions */}
      <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 22, marginBottom: 10 }}>예외 일정</Text>
      <View style={s.card}>
        <Row style={{ justifyContent: 'space-between', paddingVertical: 6 }}>
          <View>
            <Text style={{ fontSize: 13.5, fontWeight: '800', color: FOREST }}>8월 1일–3일 · 휴가</Text>
            <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>기간 중 새 요청을 받지 않아요</Text>
          </View>
          <Text style={{ fontSize: 12, color: '#d84a2f', fontWeight: '700' }}>삭제</Text>
        </Row>
      </View>
      <Pressable style={s.addException} onPress={() => Alert.alert('예외 추가', '휴가/개인 일정/임시 휴무 (목업)')}>
        <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#5a7a3c' }}>＋ 예외 일정 추가</Text>
      </Pressable>

      <View style={s.preview}>
        <Text style={{ fontSize: 11.5, color: colors.dim, textAlign: 'center' }}>
          보호자에게는 이 설정이 반영된 예약 가능 슬롯만 보여요
        </Text>
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  card: { backgroundColor: '#fff', borderRadius: 18, paddingHorizontal: 16, paddingVertical: 6, borderWidth: 1, borderColor: '#eceadf' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  rangeChip: { backgroundColor: '#e3f0c4', borderRadius: 9, paddingVertical: 5, paddingHorizontal: 9 },
  copyBtn: { alignSelf: 'center', marginTop: 12, backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 16, borderWidth: 1, borderColor: '#eceadf' },
  addException: {
    marginTop: 10, borderRadius: 14, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed',
    alignItems: 'center', paddingVertical: 13,
  },
  preview: { marginTop: 18, padding: 8 },
});
