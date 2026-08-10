import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { addAddress, Addr, deleteAddress, fetchAddresses, setDefaultAddress } from '../../src/lib/api';
import { paper } from '../../src/theme';

// Address management — real CRUD. The default pickup address shows on the request
// screen and gets attached to bookings.
// [0065 coordinates slice, DS-1] cream/rounded/volt legacy retired → paper repaint.
// Behavior unchanged: 3 inputs (same maxLengths), first-address auto default,
// tap row = set default, long-press = delete, useFocusEffect reload.
// [DS-5] each row carries a pin-state strip ("위치 지정됨/필요 ›") into the picker —
// works in both states (edit path DF-7). [DS-9] a successful add routes straight
// into the picker for the new row: the pin is the second half of saving.

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
      const newId = await addAddress({ label: label.trim(), addr: addr.trim(), detail: detail.trim() || undefined });
      setLabel(''); setAddr(''); setDetail(''); setAdding(false);
      load();
      // [DS-9] straight into the picker — back from it lands on the list with the row visible
      router.push({ pathname: '/owner/address-pin', params: { id: newId } });
    } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
  };

  const remove = (a: Addr) => {
    Alert.alert('주소 삭제', `'${a.label}'을(를) 삭제할까요?`, [
      { text: '취소', style: 'cancel' },
      { text: '삭제', style: 'destructive', onPress: () => deleteAddress(a.id).then(load).catch(() => {}) },
    ]);
  };

  const openPicker = (a: Addr) =>
    router.push({ pathname: '/owner/address-pin', params: { id: a.id } });

  return (
    <ScrollView style={{ flex: 1, backgroundColor: paper.canvas }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>주소 관리</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 14.5, lineHeight: 20, color: paper.dim, textAlign: 'center', marginTop: 6 }}>
        기본 주소가 예약의 픽업 장소로 쓰여요 · 탭해서 기본 지정
      </Text>

      <View style={{ marginTop: 16, gap: 10 }}>
        {list.length === 0 && !adding && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              등록된 주소가 없어요{'\n'}첫 주소를 추가하면 자동으로 기본 픽업이 돼요
            </Text>
          </View>
        )}
        {list.map((a) => (
          <Pressable
            key={a.id}
            onPress={() => { if (!a.isDefault) setDefaultAddress(a.id).then(load).catch(() => {}); }}
            onLongPress={() => remove(a)}
            style={s.card}
          >
            <Row style={{ justifyContent: 'space-between' }}>
              <Row style={{ gap: 7 }}>
                <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>{a.label}</Text>
                {a.isDefault && (
                  <View style={s.defaultTag}><Text style={{ fontSize: 14, fontWeight: '800', color: paper.line }}>기본 픽업</Text></View>
                )}
              </Row>
              <Text style={{ fontSize: 14, color: paper.dim }}>길게 눌러 삭제</Text>
            </Row>
            <Text style={{ fontSize: 14.5, color: paper.text, marginTop: 5 }}>{a.addr}</Text>
            {a.detail && <Text style={{ fontSize: 14.5, color: paper.dim, marginTop: 2 }}>{a.detail}</Text>}
            {/* [DS-5] pin-state strip — own pressable (suppresses the outer set-default press),
                ≥44pt, works in BOTH states: missing = coral invitation (not an error, no
                criticalWash), set = dim edit path (pre-centers on the existing pin). */}
            <Pressable
              onPress={() => openPicker(a)}
              hitSlop={6}
              style={s.pinStrip}
              accessibilityRole="button"
              accessibilityLabel={a.lat != null ? '위치 지정됨 — 핀 수정' : '위치 지정 필요'}
            >
              {a.lat != null ? (
                <Text style={s.pinSetTxt}>위치 지정됨 ›</Text>
              ) : (
                <Text style={s.pinNeedTxt}>위치 지정 필요 ›</Text>
              )}
            </Pressable>
          </Pressable>
        ))}

        {adding ? (
          <View style={[s.card, { paddingBottom: 14 }]}>
            <TextInput value={label} onChangeText={setLabel} placeholder="라벨 (예: 우리집, 서울숲 입구)" placeholderTextColor={paper.faint} style={s.input} maxLength={16} />
            <TextInput value={addr} onChangeText={setAddr} placeholder="주소" placeholderTextColor={paper.faint} style={[s.input, { marginTop: 8 }]} maxLength={60} />
            <TextInput value={detail} onChangeText={setDetail} placeholder="상세 (동·호, 만날 지점 메모 — 선택)" placeholderTextColor={paper.faint} style={[s.input, { marginTop: 8 }]} maxLength={60} />
            <Row style={{ gap: 8, marginTop: 12 }}>
              <PaperBtn label="저장" onPress={save} style={{ flex: 1.4 }} />
              <PaperBtn label="취소" variant="secondary" onPress={() => setAdding(false)} style={{ flex: 1 }} />
            </Row>
          </View>
        ) : (
          <Pressable style={s.addBtn} onPress={() => setAdding(true)} accessibilityRole="button" accessibilityLabel="주소 추가">
            <Text style={{ fontSize: 14.5, fontWeight: '800', color: paper.ink }}>＋ 주소 추가</Text>
          </Pressable>
        )}
      </View>

      <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 16, lineHeight: 19 }}>
        지도 핀으로 지정한 위치가 픽업 안내에 쓰여요{'\n'}공동현관 코드(암호화)는 다음 세션에서 추가돼요
      </Text>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  emptyBox: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, padding: 16 },
  card: { backgroundColor: paper.canvas, padding: 14, paddingBottom: 0, borderWidth: 1, borderColor: paper.line },
  defaultTag: {
    backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center',
  },
  // pin-state strip — full-width third line, its own press target (≥44pt)
  pinStrip: {
    marginTop: 10, marginHorizontal: -14, minHeight: 44,
    borderTopWidth: 1, borderTopColor: paper.line,
    paddingHorizontal: 14, justifyContent: 'center',
  },
  pinSetTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.dim },
  pinNeedTxt: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.line },
  input: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 11, paddingHorizontal: 12, fontSize: 15.5, color: paper.ink,
  },
  addBtn: {
    borderWidth: 1, borderColor: paper.line, alignItems: 'center', paddingVertical: 14,
    backgroundColor: paper.canvas,
  },
});
