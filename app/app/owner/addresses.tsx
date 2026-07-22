import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { addresses } from '../../src/store';
import { colors } from '../../src/theme';

// 주소 관리 — saved pickup/dropoff points.
// Schema seed: addresses table w/ encrypted gate_code, exposed to runner only during session.

const FOREST = '#132117';

export default function Addresses() {
  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>주소 관리</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginBottom: 16 }}>
        픽업·인계 장소를 저장해두면 예약이 빨라져요
      </Text>

      {addresses.map((a) => (
        <Pressable
          key={a.id}
          style={[s.card, a.isDefault && { borderColor: '#a9c47e', borderWidth: 1.6 }]}
          onPress={() => Alert.alert(a.label, '이 주소를 기본 픽업으로 선택 (목업)')}
        >
          <Row style={{ justifyContent: 'space-between' }}>
            <Row style={{ gap: 7 }}>
              <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{a.label}</Text>
              {a.isDefault && (
                <View style={s.defaultPill}><Text style={{ fontSize: 8.5, fontWeight: '900', color: '#4a6d1f' }}>기본 픽업</Text></View>
              )}
            </Row>
            <Pressable onPress={() => Alert.alert('편집', '주소 편집 (목업)')}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: '#5a7a3c' }}>편집</Text>
            </Pressable>
          </Row>
          <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 5 }}>{a.addr}</Text>
          {a.detail && <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 3 }}>메모: {a.detail}</Text>}

          {a.gateCode && (
            <View style={s.gateRow}>
              <Text style={{ fontSize: 11.5, fontWeight: '800', color: FOREST }}>공동현관 ●●●●●</Text>
              <Text style={{ fontSize: 10, color: colors.dim, flex: 1, textAlign: 'right' }}>
                암호화 저장 · 러닝 시간에만 러너에게 노출
              </Text>
            </View>
          )}
        </Pressable>
      ))}

      <Pressable style={s.addBtn} onPress={() => Alert.alert('새 주소', '지도에서 핀 선택 → 라벨·메모·공동현관 입력 (목업)')}>
        <Text style={{ fontSize: 13, fontWeight: '800', color: '#5a7a3c' }}>＋ 새 주소 추가</Text>
      </Pressable>

      <View style={s.privacyNote}>
        <Text style={{ fontSize: 11, color: colors.dim, lineHeight: 16, textAlign: 'center' }}>
          공동현관 비밀번호는 종단 암호화로 저장되고, 배정된 러너에게{'\n'}
          러닝 시작 30분 전부터 종료 시까지만 표시돼요.{'\n'}
          열람 기록은 안심 센터에서 확인할 수 있어요.
        </Text>
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginBottom: 10 },
  defaultPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center' },
  gateRow: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: '#f4f2ea', borderRadius: 10, padding: 10, marginTop: 9,
  },
  addBtn: {
    borderRadius: 16, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed',
    alignItems: 'center', paddingVertical: 15, marginTop: 4,
  },
  privacyNote: { marginTop: 18, padding: 8 },
});
