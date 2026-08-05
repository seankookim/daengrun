import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { addAddress, Addr, deleteAddress, fetchAddresses, setDefaultAddress } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 주소 관리 — 실CRUD. 기본 픽업 주소가 예약 화면에 표시되고 예약에 연결된다.
// 지도 핀·좌표·공동현관 코드는 지도 세션에서 (좌표가 있어야 길찾기 실화).

const FOREST = '#0F1D13';

export default function Addresses() {
  const [list, setList] = useState<Addr[]>([]);
  const [adding, setAdding] = useState(false);
  const [label, setLabel] = useState('');
  const [addr, setAddr] = useState('');
  const [detail, setDetail] = useState('');

  const load = () => fetchAddresses().then(setList).catch((e) => console.warn('[addr]:', e?.message ?? e));
  useFocusEffect(useCallback(() => { load(); }, []));

  const save = async () => {
    if (!label.trim() || !addr.trim()) { Alert.alert('라벨과 주소를 입력해주세요'); return; }
    try {
      await addAddress({ label: label.trim(), addr: addr.trim(), detail: detail.trim() || undefined });
      setLabel(''); setAddr(''); setDetail(''); setAdding(false);
      load();
    } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
  };

  const remove = (a: Addr) => {
    Alert.alert('주소 삭제', `'${a.label}'을(를) 삭제할까요?`, [
      { text: '취소', style: 'cancel' },
      { text: '삭제', style: 'destructive', onPress: () => deleteAddress(a.id).then(load).catch(() => {}) },
    ]);
  };

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: FOREST }}>주소 관리</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 6 }}>
        기본 주소가 예약의 픽업 장소로 쓰여요 · 탭해서 기본 지정
      </Text>

      <View style={{ marginTop: 16, gap: 10 }}>
        {list.length === 0 && !adding && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: colors.dim, textAlign: 'center', lineHeight: 22 }}>
              등록된 주소가 없어요{'\n'}첫 주소를 추가하면 자동으로 기본 픽업이 돼요
            </Text>
          </View>
        )}
        {list.map((a) => (
          <Pressable
            key={a.id}
            onPress={() => { if (!a.isDefault) setDefaultAddress(a.id).then(load).catch(() => {}); }}
            onLongPress={() => remove(a)}
            style={[s.card, a.isDefault && { borderColor: '#a9c47e', borderWidth: 1.6 }]}
          >
            <Row style={{ justifyContent: 'space-between' }}>
              <Row style={{ gap: 7 }}>
                <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>{a.label}</Text>
                {a.isDefault && (
                  <View style={s.defaultPill}><Text style={{ fontSize: 14, fontWeight: '900', color: '#3d5a2b' }}>기본 픽업</Text></View>
                )}
              </Row>
              <Text style={{ fontSize: 14, color: colors.dim }}>길게 눌러 삭제</Text>
            </Row>
            <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 5 }}>{a.addr}</Text>
            {a.detail && <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>{a.detail}</Text>}
          </Pressable>
        ))}

        {adding ? (
          <View style={s.card}>
            <TextInput value={label} onChangeText={setLabel} placeholder="라벨 (예: 우리집, 서울숲 입구)" placeholderTextColor="#b0ada0" style={s.input} maxLength={16} />
            <TextInput value={addr} onChangeText={setAddr} placeholder="주소" placeholderTextColor="#b0ada0" style={[s.input, { marginTop: 8 }]} maxLength={60} />
            <TextInput value={detail} onChangeText={setDetail} placeholder="상세 (동·호, 만날 지점 메모 — 선택)" placeholderTextColor="#b0ada0" style={[s.input, { marginTop: 8 }]} maxLength={60} />
            <Row style={{ gap: 8, marginTop: 10 }}>
              <Pressable onPress={save} style={[s.saveBtn, { flex: 1.4 }]}>
                <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>저장</Text>
              </Pressable>
              <Pressable onPress={() => setAdding(false)} style={s.cancelBtn}>
                <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#49524a' }}>취소</Text>
              </Pressable>
            </Row>
          </View>
        ) : (
          <Pressable style={s.addBtn} onPress={() => setAdding(true)}>
            <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#5a7a3c' }}>＋ 주소 추가</Text>
          </Pressable>
        )}
      </View>

      <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 16, lineHeight: 17 }}>
        지도 핀 선택·공동현관 코드(암호화)는 지도 세션에서 추가돼요{'\n'}코드는 러닝 시간에만 러너에게 보여요
      </Text>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  emptyBox: { backgroundColor: '#f4f2ea', borderRadius: 16, padding: 16 },
  card: { backgroundColor: '#fff', borderRadius: 16, padding: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  defaultPill: { backgroundColor: '#eaf7c8', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center' },
  input: { backgroundColor: '#faf9f3', borderRadius: 12, borderWidth: 1, borderColor: '#DCD6C4', paddingVertical: 11, paddingHorizontal: 12, fontSize: 15.5, color: FOREST },
  saveBtn: { backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 12 },
  cancelBtn: { flex: 1, backgroundColor: '#f4f2ea', borderRadius: 12, alignItems: 'center', paddingVertical: 12 },
  addBtn: { borderRadius: 16, borderWidth: 1.4, borderColor: '#cfd8c2', borderStyle: 'dashed', alignItems: 'center', paddingVertical: 14 },
});
