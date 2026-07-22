import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { dog, emergencyContacts, safetyChecklist } from '../src/store';
import { colors } from '../src/theme';

// 안심 센터 — safety hub: SOS, live location, verification/insurance,
// emergency contacts, checklist, incident report, medical notes.

const FOREST = '#132117';

export default function Safety() {
  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64, paddingBottom: 24 }}>
        {/* header */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 8 }}>
              <Text style={s.h1}>안심 센터</Text>
              <View style={s.shieldChip}><Text style={{ fontSize: 12, color: FOREST }}>✚</Text></View>
            </Row>
            <Text style={s.sub}>
              {dog.name}와 러너의 안전하고 즐거운 러닝을 위해{'\n'}꼼꼼하게 준비했어요.
            </Text>
          </View>
          <Pressable onPress={() => router.push('/alerts')} style={s.bell}>
            <View style={s.bellDot} />
            <Text style={{ fontSize: 15, color: colors.dim }}>◔</Text>
          </Pressable>
        </Row>

        {/* SOS */}
        <Pressable style={[s.card, { marginTop: 20 }]} onPress={() => Alert.alert('SOS', '보호자와 러너에게 즉시 알림이 전송됩니다 (목업)')}>
          <Row style={{ gap: 14 }}>
            <View style={s.sosCircle}><Text style={{ fontSize: 15, fontWeight: '900', color: colors.tang }}>SOS</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 12, fontWeight: '800', color: colors.tang }}>긴급 상황 시</Text>
              <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST, marginTop: 2 }}>SOS 버튼을 눌러주세요</Text>
              <Text style={s.dim13}>보호자와 러너에게 즉시 알림이 전송됩니다.</Text>
            </View>
            <View style={s.sosGo}><Text style={{ color: '#fff', fontSize: 18, fontWeight: '900' }}>›</Text></View>
          </Row>
        </Pressable>

        {/* live location */}
        <View style={[s.card, { marginTop: 12 }]}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={s.cardTitle}>실시간 위치 공유</Text>
            <View style={s.outlineChip}><Text style={{ fontSize: 11, fontWeight: '700', color: '#5a7a3c' }}>상세보기</Text></View>
          </Row>
          <Row style={{ gap: 14, marginTop: 12 }}>
            <View style={s.iconCircle}><Text style={{ fontSize: 20, color: '#5a7a3c' }}>⌖</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 15, fontWeight: '900', color: '#5a7a3c' }}>공유 중 ●</Text>
              <Text style={s.dim13}>{dog.name}의 위치가 보호자와 러너에게{'\n'}실시간으로 공유되고 있어요.</Text>
            </View>
          </Row>
        </View>

        {/* verification + insurance */}
        <Row style={{ gap: 10, marginTop: 12 }}>
          <MiniCard title="러너 인증" status="인증 완료 ✓" desc={'신원 및 배경 확인이 완료된\n안전한 러너예요.'} glyph="✓" />
          <MiniCard title="보험 가입" status="보장 중 ✓" desc={'러닝 중 발생할 수 있는\n사고를 보장해 드려요.'} glyph="☂" />
        </Row>

        {/* emergency contacts */}
        <View style={[s.card, { marginTop: 12 }]}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={s.cardTitle}>긴급 연락처</Text>
            <Text style={{ fontSize: 11, color: colors.dim }}>총 {emergencyContacts.length}명 등록됨</Text>
          </Row>
          <Row style={{ gap: 8, marginTop: 12 }}>
            {emergencyContacts.map((c) => (
              <View key={c.name} style={s.contact}>
                <Text style={{ fontSize: 12, fontWeight: '800', color: FOREST }}>{c.name}</Text>
                <Text style={{ fontSize: 10, color: colors.dim, marginTop: 1 }}>{c.phone}</Text>
              </View>
            ))}
            <Pressable style={s.contactAdd} onPress={() => Alert.alert('추가', '긴급 연락처 추가 (목업)')}>
              <Text style={{ fontSize: 13, fontWeight: '800', color: '#5a7a3c' }}>+ 추가</Text>
            </Pressable>
          </Row>
        </View>

        {/* checklist */}
        <View style={[s.card, { marginTop: 12 }]}>
          <Text style={s.cardTitle}>산책/러닝 안전 수칙</Text>
          <View style={{ marginTop: 10, gap: 9 }}>
            {safetyChecklist.map((item) => (
              <Row key={item} style={{ gap: 8 }}>
                <View style={s.check}><Text style={{ fontSize: 9, color: '#fff', fontWeight: '900' }}>✓</Text></View>
                <Text style={{ fontSize: 13, color: '#3d453d', flex: 1 }}>{item}</Text>
              </Row>
            ))}
          </View>
        </View>

        {/* report + medical */}
        <Row style={{ gap: 10, marginTop: 12 }}>
          <Pressable style={[s.card, { flex: 1 }]} onPress={() => Alert.alert('신고', '사고/이상 신고 (목업)')}>
            <View style={[s.iconCircle, { backgroundColor: '#fde8e3' }]}><Text style={{ fontSize: 16, color: colors.tang }}>⚠</Text></View>
            <Text style={[s.cardTitle, { marginTop: 10 }]}>사고/이상 신고하기</Text>
            <Text style={s.dim12}>긴급하지 않은 사고나{'\n'}이상을 신고할 수 있어요.</Text>
          </Pressable>
          <Pressable style={[s.card, { flex: 1 }]} onPress={() => Alert.alert('의료 노트', '반려견 의료 노트 (목업)')}>
            <View style={s.iconCircle}><Text style={{ fontSize: 16, color: '#5a7a3c' }}>♥</Text></View>
            <Text style={[s.cardTitle, { marginTop: 10 }]}>반려견 의료 노트</Text>
            <Text style={s.dim12}>기록된 건강 정보와{'\n'}진료 기록을 확인해요.</Text>
          </Pressable>
        </Row>

        {/* help */}
        <View style={[s.card, { marginTop: 12 }]}>
          <Row style={{ gap: 12 }}>
            <View style={s.iconCircle}><Text style={{ fontSize: 16, color: '#5a7a3c' }}>◍</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={s.cardTitle}>도움이 필요하신가요?</Text>
              <Text style={s.dim12}>자주 묻는 질문, 1:1 문의, 고객센터 전화 연결까지</Text>
            </View>
            <View style={s.outlineChip}><Text style={{ fontSize: 11, fontWeight: '700', color: '#5a7a3c' }}>도움말 보기</Text></View>
          </Row>
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function MiniCard({ title, status, desc, glyph }: { title: string; status: string; desc: string; glyph: string }) {
  return (
    <View style={[s.card, { flex: 1 }]}>
      <Text style={s.cardTitle}>{title}</Text>
      <Row style={{ gap: 10, marginTop: 10 }}>
        <View style={s.iconCircle}><Text style={{ fontSize: 15, color: '#5a7a3c' }}>{glyph}</Text></View>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 13, fontWeight: '900', color: '#5a7a3c' }}>{status}</Text>
          <Text style={[s.dim12, { marginTop: 2 }]}>{desc}</Text>
        </View>
      </Row>
    </View>
  );
}

const s = StyleSheet.create({
  h1: { fontSize: 30, fontWeight: '900', color: FOREST },
  shieldChip: { width: 26, height: 26, borderRadius: 13, backgroundColor: '#e7efd8', alignItems: 'center', justifyContent: 'center', marginTop: 6 },
  sub: { fontSize: 13, color: '#5d655d', marginTop: 8, lineHeight: 20 },
  bell: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.line },
  bellDot: { position: 'absolute', top: 9, right: 10, width: 7, height: 7, borderRadius: 4, backgroundColor: colors.voltDeep, zIndex: 2 },
  card: { backgroundColor: '#fff', borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#eceadf' },
  cardTitle: { fontSize: 15, fontWeight: '900', color: FOREST },
  dim13: { fontSize: 12.5, color: '#75806f', marginTop: 3, lineHeight: 18 },
  dim12: { fontSize: 11.5, color: '#75806f', marginTop: 3, lineHeight: 17 },
  sosCircle: { width: 56, height: 56, borderRadius: 28, backgroundColor: '#fde3dd', alignItems: 'center', justifyContent: 'center' },
  sosGo: { width: 46, height: 46, borderRadius: 23, backgroundColor: '#e8492a', alignItems: 'center', justifyContent: 'center', alignSelf: 'center' },
  outlineChip: { borderWidth: 1.2, borderColor: '#a9c47e', borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12 },
  iconCircle: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#e7efd8', alignItems: 'center', justifyContent: 'center' },
  contact: { flex: 1, backgroundColor: '#faf9f3', borderRadius: 14, borderWidth: 1, borderColor: '#eceadf', paddingVertical: 10, paddingHorizontal: 12 },
  contactAdd: { flex: 0.7, borderRadius: 14, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed', alignItems: 'center', justifyContent: 'center' },
  check: { width: 16, height: 16, borderRadius: 8, backgroundColor: '#6aa53c', alignItems: 'center', justifyContent: 'center' },
});
