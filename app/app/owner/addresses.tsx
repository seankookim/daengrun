import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { addAddress, Addr, deleteAddress, fetchAddresses, setDefaultAddress, updateAddressDetail } from '../../src/lib/api';
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
  // [honesty 2026-08-11] loading ≠ 0 ≠ empty: a failed load used to render
  // "등록된 주소가 없어요" (and the list showed the same in flight). Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const [adding, setAdding] = useState(false);
  const [label, setLabel] = useState('');
  const [addr, setAddr] = useState('');
  const [detail, setDetail] = useState('');
  // [D15 2026-08-12 · Sean "special note … editable for owner in preference"] 픽업 메모 인라인 편집.
  // 지금까지 addresses.detail은 **생성 시 1회 쓰기**였다 — api.ts에 update가 아예 없어서,
  // '1층 로비에서 인계'를 '경비실에 맡겨주세요'로 바꾸려면 주소를 지우고 다시 만들어야 했고
  // 그 과정에서 핀과 기본-픽업 플래그가 함께 날아갔다. 그게 이 상태 두 줄이 고치는 것이다.
  const [noteId, setNoteId] = useState<string | null>(null);  // 편집 중인 주소 (null = 없음)
  const [noteVal, setNoteVal] = useState('');
  const [noteBusy, setNoteBusy] = useState(false);

  const load = () => {
    setLoadErr(false);
    return fetchAddresses()
      .then((l) => { setList(l); setLoaded(true); })
      .catch((e) => { console.warn('[addr]:', e?.message ?? e); setLoadErr(true); });
  };
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

  const openNote = (a: Addr) => { setNoteId(a.id); setNoteVal(a.detail ?? ''); };
  const saveNote = async () => {
    if (!noteId || noteBusy) return;
    setNoteBusy(true);
    try {
      // 원문 그대로 보낸다 — 트림·빈문자열→NULL·60자 상한은 서버(0073)가 단일 소유자다.
      await updateAddressDetail(noteId, noteVal);
      setNoteId(null); setNoteVal('');
      await load();
    } catch (e) {
      // 조용한 실패 금지 — 보호자는 러너가 읽을 문장을 바꿨다고 믿는다.
      Alert.alert('메모 저장 실패', (e as Error).message);
    } finally { setNoteBusy(false); }
  };

  const remove = (a: Addr) => {
    Alert.alert('주소 삭제', `'${a.label}'을(를) 삭제할까요?`, [
      { text: '취소', style: 'cancel' },
      {
        text: '삭제', style: 'destructive',
        // [honesty 2026-08-11] a confirmed destructive delete used to fail silently —
        // the row just stayed. Failure now says so.
        onPress: () => deleteAddress(a.id).then(load).catch((e) => Alert.alert('삭제 실패', (e as Error).message)),
      },
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
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>주소를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && list.length === 0 && !adding && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              등록된 주소가 없어요{'\n'}첫 주소를 추가하면 자동으로 기본 픽업이 돼요
            </Text>
          </View>
        )}
        {list.map((a) => (
          <Pressable
            key={a.id}
            onPress={() => {
              // silent failure here left the old default active while the user believed it changed
              if (!a.isDefault) setDefaultAddress(a.id).then(load).catch((e) => Alert.alert('기본 픽업 변경 실패', (e as Error).message));
            }}
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
              {/* [2026-08-10 density audit] per-row "길게 눌러 삭제" cut — one list-level
                  footer line below the cards keeps the invisible gesture discoverable */}
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
            {/* [D15] 픽업 메모 스트립 — pinStrip과 같은 문법(자체 Pressable, ≥44pt, 두 상태 모두 동작).
                이 문장은 장식이 아니다: 배정된 러너가 인계 화면에서 읽는 바로 그 줄이다. */}
            {noteId === a.id ? (
              <View style={s.noteEdit}>
                <TextInput
                  value={noteVal}
                  onChangeText={setNoteVal}
                  placeholder="예: 공동현관 #1204 · 경비실에 맡겨주세요"
                  placeholderTextColor={paper.faint}
                  style={s.input}
                  maxLength={60}
                  autoFocus
                  multiline={false}
                  returnKeyType="done"
                  onSubmitEditing={saveNote}
                />
                {/* 60자는 서버 상한과 같은 수 — 여기 maxLength는 막는 장치가 아니라 미리 알려주는 장치다 */}
                <Text style={s.noteCount}>{noteVal.length}/60 · 러너가 이 문장을 봐요</Text>
                <Row style={{ gap: 8, marginTop: 10 }}>
                  <PaperBtn label="저장" busyLabel="저장 중..." busy={noteBusy} onPress={saveNote} style={{ flex: 1.4 }} />
                  <PaperBtn label="취소" variant="secondary" onPress={() => setNoteId(null)} style={{ flex: 1 }} />
                </Row>
              </View>
            ) : (
              <Pressable
                onPress={() => openNote(a)}
                hitSlop={6}
                style={s.pinStrip}
                accessibilityRole="button"
                accessibilityLabel={a.detail ? '픽업 메모 수정' : '픽업 메모 추가'}
              >
                {a.detail
                  ? <Text style={s.pinSetTxt} numberOfLines={1}>메모 · {a.detail} ›</Text>
                  : <Text style={s.pinNeedTxt}>픽업 메모 추가 ›</Text>}
              </Pressable>
            )}
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
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>＋ 주소 추가</Text>
          </Pressable>
        )}
      </View>

      {/* list-level delete hint — the long-press gesture has no visual affordance, so one
          quiet line replaces the retired per-row hint (only when there are rows to press) */}
      {list.length > 0 && (
        <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 12 }}>
          주소를 길게 누르면 삭제돼요
        </Text>
      )}
      {/* [2026-08-10 density audit] roadmap clause ("공동현관 코드...다음 세션") cut — screens state
          facts, not the backlog. The pin-fact line stays: it explains what the pin strip does. */}
      <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 16 }}>
        지도 핀으로 지정한 위치가 픽업 안내에 쓰여요
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
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
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
  noteEdit: { marginTop: 10, marginHorizontal: -14, borderTopWidth: 1, borderTopColor: paper.line, paddingHorizontal: 14, paddingTop: 12 },
  noteCount: { fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 6 },
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
