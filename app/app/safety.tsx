import { useDisplayFont } from '../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { addEmergencyContact, deleteEmergencyContact, EmContact, fetchEmergencyContacts, sendSOS } from '../src/lib/api';
import { haptic } from '../src/lib/haptics';
import { session } from '../src/store';
import { colors } from '../src/theme';

// 안심 센터 — 실동작: SOS(진행 중 예약 상대에게 즉시 알림), 긴급 연락처 CRUD, 전화 걸기.
// 신고·의료노트는 각각 향후 세션(incidents 플로우 / 반려견 프로필 메모가 대체).

const FOREST = '#0F1D13';

export default function Safety() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [contacts, setContacts] = useState<EmContact[]>([]);
  const [adding, setAdding] = useState(false);
  const [cName, setCName] = useState('');
  const [cPhone, setCPhone] = useState('');

  const load = () => fetchEmergencyContacts().then(setContacts).catch((e) => console.warn('[safety]:', e?.message ?? e));
  useFocusEffect(useCallback(() => { load(); }, []));

  const sos = () => {
    Alert.alert('🚨 SOS', '진행 중인 러닝의 상대방에게 긴급 알림을 보낼까요?', [
      { text: '취소', style: 'cancel' },
      {
        text: 'SOS 전송', style: 'destructive',
        onPress: async () => {
          haptic('success');
          try {
            const bid = await sendSOS(session.role === 'runner' ? 'runner' : 'owner');
            if (bid) Alert.alert('전송 완료', '상대방에게 긴급 알림이 전송됐어요.\n위급 상황이면 즉시 112/119에 연락하세요.');
            else Alert.alert('진행 중인 러닝이 없어요', '위급 상황이면 즉시 112/119에 연락하세요.');
          } catch (e) {
            Alert.alert('전송 실패', `${(e as Error).message}\n위급 상황이면 즉시 112/119에 연락하세요.`);
          }
        },
      },
    ]);
  };

  const saveContact = async () => {
    if (!cName.trim() || !cPhone.trim()) { Alert.alert('이름과 전화번호를 입력해주세요'); return; }
    try {
      await addEmergencyContact(cName.trim(), cPhone.trim());
      setCName(''); setCPhone(''); setAdding(false);
      load();
    } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
  };

  const removeContact = (c: EmContact) => {
    Alert.alert('연락처 삭제', `${c.name}을(를) 긴급 연락처에서 삭제할까요?`, [
      { text: '취소', style: 'cancel' },
      { text: '삭제', style: 'destructive', onPress: () => deleteEmergencyContact(c.id).then(load).catch(() => {}) },
    ]);
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 64, paddingBottom: 24 }}>
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Pressable onPress={() => router.back()} style={[s.bell, { marginRight: 12 }]}>
            <Text style={{ fontSize: 20.5, color: FOREST }}>‹</Text>
          </Pressable>
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 8 }}>
              <Text style={[s.h1, df]}>안심 센터</Text>
              <View style={s.shieldChip}><Text style={{ fontSize: 14, color: FOREST }}>✚</Text></View>
            </Row>
            <Text style={s.sub}>안전하고 즐거운 러닝을 위한 실비상 체계</Text>
          </View>
        </Row>

        {/* ---------- SOS (실동작) ---------- */}
        <Pressable style={s.sosCard} onPress={sos}>
          <Text style={{ fontSize: 30 }}>🚨</Text>
          <View style={{ flex: 1, marginLeft: 14 }}>
            <Text style={{ fontSize: 18.5, fontWeight: '900', color: '#fff' }}>SOS 긴급 알림</Text>
            <Text style={{ fontSize: 14, color: '#ffd9cf', marginTop: 3, lineHeight: 18.5 }}>
              진행 중인 러닝의 상대방에게 즉시 알림{'\n'}위급 시엔 112·119가 항상 우선이에요
            </Text>
          </View>
        </Pressable>
        <Row style={{ gap: 10, marginTop: 10 }}>
          <Pressable style={s.callBtn} onPress={() => Linking.openURL('tel:112')}>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#d84a2f' }}>📞 112</Text>
          </Pressable>
          <Pressable style={s.callBtn} onPress={() => Linking.openURL('tel:119')}>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#d84a2f' }}>📞 119</Text>
          </Pressable>
        </Row>

        {/* ---------- 긴급 연락처 (실CRUD) ---------- */}
        <Text style={s.section}>긴급 연락처</Text>
        <View style={s.card}>
          {contacts.length === 0 && !adding && (
            <Text style={{ fontSize: 14.5, color: colors.dim, paddingVertical: 6 }}>
              아직 없어요 — 위급 시 연락할 가족·지인을 등록해두세요
            </Text>
          )}
          {contacts.map((c, i) => (
            <View key={c.id}>
              {i > 0 && <View style={s.div} />}
              <Row style={{ paddingVertical: 10, alignItems: 'center' }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 16, fontWeight: '800', color: FOREST }}>{c.name}</Text>
                  <Text style={{ fontSize: 14, color: colors.dim, marginTop: 2 }}>{c.phone}</Text>
                </View>
                <Pressable onPress={() => Linking.openURL(`tel:${c.phone}`)} style={s.miniBtn}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#3d5a2b' }}>전화</Text>
                </Pressable>
                <Pressable onPress={() => removeContact(c)} style={[s.miniBtn, { marginLeft: 6 }]}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#d84a2f' }}>삭제</Text>
                </Pressable>
              </Row>
            </View>
          ))}
          {adding ? (
            <View style={{ marginTop: 8, gap: 8 }}>
              <TextInput value={cName} onChangeText={setCName} placeholder="이름 (예: 엄마)" placeholderTextColor="#b0ada0" style={s.input} maxLength={12} />
              <TextInput value={cPhone} onChangeText={setCPhone} placeholder="전화번호" placeholderTextColor="#b0ada0" style={s.input} keyboardType="phone-pad" maxLength={15} />
              <Row style={{ gap: 8 }}>
                <Pressable onPress={saveContact} style={[s.saveBtn, { flex: 1.4 }]}>
                  <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>저장</Text>
                </Pressable>
                <Pressable onPress={() => setAdding(false)} style={[s.miniBtn, { flex: 1, alignItems: 'center', paddingVertical: 11 }]}>
                  <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#49524a' }}>취소</Text>
                </Pressable>
              </Row>
            </View>
          ) : (
            <Pressable onPress={() => setAdding(true)} style={s.addRow}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#5a7a3c' }}>＋ 연락처 추가</Text>
            </Pressable>
          )}
        </View>

        {/* ---------- 보험·안전 안내 (정보성) ---------- */}
        <Text style={s.section}>안전 체계</Text>
        <View style={s.card}>
          <InfoRow glyph="🛡" title="펫보험" desc="인계 확인 시점부터 러닝 종료까지 적용 (파일럿 보험 파트너 협의 중)" />
          <View style={s.div} />
          <InfoRow glyph="📍" title="실시간 위치" desc="러닝 중 보호자 라이브 지도에 러너 경로가 실시간 표시돼요" />
          <View style={s.div} />
          <InfoRow glyph="✓" title="러너 신원" desc="모든 러너는 신원 확인을 거쳐요 (본인인증 고도화 예정)" />
        </View>

        {/* ---------- 준비 중 (정직 라벨) ---------- */}
        <Row style={{ gap: 10, marginTop: 14 }}>
          <View style={[s.card, { flex: 1, opacity: 0.55, marginTop: 0 }]}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: FOREST }}>사고 신고</Text>
            <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>인시던트 플로우 준비 중</Text>
          </View>
          <Pressable style={[s.card, { flex: 1, marginTop: 0 }]} onPress={() => router.push('/owner/dog')}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: FOREST }}>의료·성향 메모</Text>
            <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>반려견 프로필에서 관리 ›</Text>
          </Pressable>
        </Row>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function InfoRow({ glyph, title, desc }: { glyph: string; title: string; desc: string }) {
  return (
    <Row style={{ paddingVertical: 10, gap: 10 }}>
      <Text style={{ fontSize: 18.5 }}>{glyph}</Text>
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 15.5, fontWeight: '800', color: FOREST }}>{title}</Text>
        <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2, lineHeight: 18.5 }}>{desc}</Text>
      </View>
    </Row>
  );
}

const s = StyleSheet.create({
  h1: { fontSize: 30, fontWeight: '900', color: FOREST },
  sub: { fontSize: 14, color: colors.dim, marginTop: 4 },
  bell: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  shieldChip: { width: 24, height: 24, borderRadius: 12, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center', alignSelf: 'center' },
  sosCard: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#e8492a',
    borderRadius: 20, padding: 18, marginTop: 18,
  },
  callBtn: { flex: 1, backgroundColor: '#fff', borderRadius: 14, alignItems: 'center', paddingVertical: 12, borderWidth: 1.3, borderColor: '#f2d4ca' },
  section: { fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 8 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  miniBtn: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 },
  addRow: { marginTop: 6, borderRadius: 12, borderWidth: 1.3, borderColor: '#cfd8c2', borderStyle: 'dashed', alignItems: 'center', paddingVertical: 11 },
  input: { backgroundColor: '#faf9f3', borderRadius: 12, borderWidth: 1, borderColor: '#DCD6C4', paddingVertical: 10, paddingHorizontal: 12, fontSize: 15.5, color: FOREST },
  saveBtn: { backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11 },
});
