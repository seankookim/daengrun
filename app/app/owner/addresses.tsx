import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { addAddress, Addr, deleteAddress, fetchAddresses, setDefaultAddress, updateAddressDetail } from '../../src/lib/api';
import { goBackOrHome } from '../../src/lib/nav';
import { supabase } from '../../src/lib/supabase';
import { paper } from '../../src/theme';

// Address management — real CRUD. The default pickup address shows on the request
// screen and gets attached to bookings.
// [0065 coordinates slice, DS-1] cream/rounded/volt legacy retired → paper repaint.
// Behavior unchanged: 3 inputs (same maxLengths), first-address auto default,
// useFocusEffect reload.
// [DS-5] each row carries a pin-state strip ("위치 지정됨/필요 ›") into the picker —
// works in both states (edit path DF-7). [DS-9] a successful add routes straight
// into the picker for the new row: the pin is the second half of saving.
//
// [2026-08-24 · Sean "Sure to all of the address management screen things" — lab A①A②A③]
//   A① 코랄 텍스트를 읽는 코랄로. 「위치 지정 필요 ›」·「픽업 메모 추가 ›」는 이 화면에서 가장
//     행동처럼 생긴 라벨인데 paper.line(#E8552F)으로 그려져 있었다 — 흰 바탕에서 **3.64:1**,
//     14pt 디테일이 넘어야 하는 4.5 하한 아래다. theme.ts에 이미 그 색조의 '읽는 버전'이 있다:
//     actionInk #A83315, **6.67:1**. 카드 테두리와 기본-픽업 태그의 **면**은 paper.line 그대로다
//     — 그 토큰은 엣지·면의 것이고, 이것이 정확히 2단 문법(display 색 / ink 색)이 존재하는 이유다.
//   A② 주소를 저장 전에 확인한다. geocode-address 엣지 함수는 이미 있고 이미 roadAddress를
//     돌려준다 — 폼의 「확인」이 그걸 부르고, **찾은 것을 보여줄 뿐 사용자가 쓴 글자를 절대
//     고쳐 쓰지 않는다.** 세 갈래는 문서화된 세 응답과 1:1이다: hit(roadAddress) · miss(lat null)
//     · unavailable(available:false). 어느 갈래도 저장을 막지 않는다 — 확인은 도움이지 관문이 아니다.
//   A③ 보이지 않는 제스처를 보이는 행으로. 카드 하나가 세 개의 제스처를 지고 있었고(탭=기본
//     지정, 길게=삭제, 안쪽 스트립 두 개), 그 중 둘이 안 보였으며 **파괴적인 쪽이 가장 안 보였다**
//     — 목록 아래 회색 한 줄이 유일한 안내였다. 이제 기본 지정은 칩, 삭제는 카드 안의 행이다.
//     바깥 Pressable은 은퇴한다 (삭제 확인 Alert와 실패 Alert는 그대로).
// 카드 안의 가로선은 뉴트럴 #EEEEEE다 — 코랄 풀블리드 룰은 **섹션**의 문법이고 카드 한 장이
// 코랄 가로선 3~4개를 쌓으면 화면이 줄무늬가 된다 (Sean 2026-08-24: "too many horizontal red
// lines"). 카드 테두리 코랄 1개만 남는다.

// A② 주소 확인 — 서버가 돌려주는 세 가지 사실 그대로. 'checking'은 상태지 결과가 아니다.
type VerifyState =
  | null
  | 'checking'
  | { kind: 'hit'; roadAddress: string | null }
  | { kind: 'miss' }
  | { kind: 'unavailable' };

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
  const [verify, setVerify] = useState<VerifyState>(null);
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
      setLabel(''); setAddr(''); setDetail(''); setAdding(false); setVerify(null);
      load();
      // [DS-9] straight into the picker — back from it lands on the list with the row visible
      router.push({ pathname: '/owner/address-pin', params: { id: newId } });
    } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
  };

  // [A②] 확인 = 지도가 이 주소를 아는지 묻는 것. 결과는 보여주기만 한다 — 입력값을 덮어쓰지
  // 않고, 저장을 막지도 않는다. 엣지 함수는 오류 본문을 절대 노출하지 않는 계약이라(ES-10)
  // 클라도 error/비정상 응답을 전부 '확인 불가' 한 갈래로 접는다.
  const runVerify = async () => {
    const query = addr.trim();
    if (!query) return;
    setVerify('checking');
    try {
      const { data, error } = await supabase.functions.invoke('geocode-address', { body: { query } });
      if (error || !data || data.available !== true) { setVerify({ kind: 'unavailable' }); return; }
      if (typeof data.lat !== 'number' || typeof data.lng !== 'number') { setVerify({ kind: 'miss' }); return; }
      setVerify({ kind: 'hit', roadAddress: typeof data.roadAddress === 'string' ? data.roadAddress : null });
    } catch { setVerify({ kind: 'unavailable' }); }
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

  // silent failure here left the old default active while the user believed it changed
  const makeDefault = (a: Addr) =>
    setDefaultAddress(a.id).then(load).catch((e) => Alert.alert('기본 픽업 변경 실패', (e as Error).message));

  const openPicker = (a: Addr) =>
    router.push({ pathname: '/owner/address-pin', params: { id: a.id } });

  return (
    <ScrollView style={{ flex: 1, backgroundColor: paper.canvas }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>주소 관리</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 14.5, lineHeight: 20, color: paper.dim, textAlign: 'center', marginTop: 6 }}>
        기본 주소가 예약의 픽업 장소로 쓰여요
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
          // [A③] 카드는 다시 카드다 — 바깥 Pressable(탭=기본 지정, 길게=삭제) 은퇴.
          // 이 카드 안의 모든 동작은 눈에 보이는 자기 행을 가진다.
          <View key={a.id} style={s.card}>
            <Row style={{ justifyContent: 'space-between', gap: 8 }}>
              <Row style={{ gap: 7, flexShrink: 1 }}>
                <Text numberOfLines={1} style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>{a.label}</Text>
                {a.isDefault && (
                  // 면·엣지는 paper.line 그대로, 글자만 읽는 코랄로 (A① 2단 문법)
                  <View style={s.defaultTag}><Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.actionInk }}>기본 픽업</Text></View>
                )}
              </Row>
              {!a.isDefault && (
                <Pressable
                  onPress={() => makeDefault(a)}
                  hitSlop={6}
                  style={s.setDefaultChip}
                  accessibilityRole="button"
                  accessibilityLabel={`${a.label}을 기본 픽업으로 지정`}
                >
                  <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.actionInk }}>기본으로 지정</Text>
                </Pressable>
              )}
            </Row>
            <Text style={{ fontSize: 14.5, lineHeight: 20, color: paper.text, marginTop: 5 }}>{a.addr}</Text>
            {/* [DS-5] pin-state strip — own pressable, ≥44pt, works in BOTH states: missing =
                coral invitation (not an error, no criticalWash), set = dim edit path
                (pre-centers on the existing pin). */}
            <Pressable
              onPress={() => openPicker(a)}
              hitSlop={6}
              style={s.rowStrip}
              accessibilityRole="button"
              accessibilityLabel={a.lat != null ? '위치 지정됨 — 핀 수정' : '위치 지정 필요'}
            >
              {a.lat != null ? (
                <Text style={s.stripSetTxt}>위치 지정됨 ›</Text>
              ) : (
                <Text style={s.stripNeedTxt}>위치 지정 필요 ›</Text>
              )}
            </Pressable>
            {/* [D15] 픽업 메모 스트립 — 핀 스트립과 같은 문법(자체 Pressable, ≥44pt, 두 상태 모두 동작).
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
                <Row style={{ gap: 8, marginTop: 10, marginBottom: 12 }}>
                  <PaperBtn label="저장" busyLabel="저장 중..." busy={noteBusy} onPress={saveNote} style={{ flex: 1.4 }} />
                  <PaperBtn label="취소" variant="secondary" onPress={() => setNoteId(null)} style={{ flex: 1 }} />
                </Row>
              </View>
            ) : (
              <Pressable
                onPress={() => openNote(a)}
                hitSlop={6}
                style={s.rowStrip}
                accessibilityRole="button"
                accessibilityLabel={a.detail ? '픽업 메모 수정' : '픽업 메모 추가'}
              >
                {a.detail
                  ? <Text style={s.stripSetTxt} numberOfLines={1}>메모 · {a.detail} ›</Text>
                  : <Text style={s.stripNeedTxt}>픽업 메모 추가 ›</Text>}
              </Pressable>
            )}
            {/* [A③] 삭제는 더 이상 보이지 않는 제스처가 아니다 — 확인 Alert는 그대로 */}
            <Pressable
              onPress={() => remove(a)}
              style={s.rowStrip}
              accessibilityRole="button"
              accessibilityLabel={`${a.label} 주소 삭제`}
            >
              <Text style={s.stripDeleteTxt}>주소 삭제</Text>
            </Pressable>
          </View>
        ))}

        {adding ? (
          <View style={[s.card, { paddingBottom: 14 }]}>
            <TextInput value={label} onChangeText={setLabel} placeholder="라벨 (예: 우리집, 서울숲 입구)" placeholderTextColor={paper.faint} style={s.input} maxLength={16} />
            {/* [A②] 주소 + 확인. 확인은 저장의 전제가 아니다 — 세 갈래 모두 저장은 열려 있다 */}
            <Row style={{ gap: 8, marginTop: 8, alignItems: 'stretch' }}>
              <TextInput
                value={addr}
                onChangeText={(t) => { setAddr(t); setVerify(null); }}
                placeholder="주소"
                placeholderTextColor={paper.faint}
                style={[s.input, { flex: 1 }]}
                maxLength={60}
              />
              <Pressable
                onPress={runVerify}
                disabled={!addr.trim() || verify === 'checking'}
                style={s.verifyBtn}
                accessibilityRole="button"
                accessibilityLabel="주소 확인"
                accessibilityState={{ disabled: !addr.trim() || verify === 'checking' }}
              >
                <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: addr.trim() ? paper.actionInk : paper.faint }}>
                  {verify === 'checking' ? '확인 중...' : '확인'}
                </Text>
              </Pressable>
            </Row>
            {verify === 'checking' && (
              <Text style={s.verifyQuiet}>주소를 확인하는 중이에요…</Text>
            )}
            {verify && verify !== 'checking' && verify.kind === 'hit' && (
              <View style={s.verifyHit}>
                <Text style={{ fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.paceGoodInk }}>이 주소를 찾았어요</Text>
                <Text style={{ fontSize: 14, lineHeight: 19, color: paper.paceGoodInk, marginTop: 2 }}>
                  {/* roadAddress가 없으면 지어내지 않는다 — 찾았다는 사실만 말한다 */}
                  {verify.roadAddress ? `${verify.roadAddress} · ` : ''}저장하면 지도에서 핀을 맞출 수 있어요
                </Text>
              </View>
            )}
            {verify && verify !== 'checking' && verify.kind === 'miss' && (
              <View style={s.verifyMiss}>
                <Text style={{ fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.actionInk }}>이 주소는 지도에서 찾지 못했어요</Text>
                <Text style={{ fontSize: 14, lineHeight: 19, color: paper.text, marginTop: 2 }}>
                  그래도 저장할 수 있어요 — 저장 뒤 지도에서 픽업 위치를 직접 맞추면 돼요
                </Text>
              </View>
            )}
            {verify && verify !== 'checking' && verify.kind === 'unavailable' && (
              <Text style={s.verifyQuiet}>지금은 주소 확인을 할 수 없어요 — 저장 뒤 지도에서 맞춰주세요</Text>
            )}
            <TextInput value={detail} onChangeText={setDetail} placeholder="상세 (동·호, 만날 지점 메모 — 선택)" placeholderTextColor={paper.faint} style={[s.input, { marginTop: 8 }]} maxLength={60} />
            <Row style={{ gap: 8, marginTop: 12 }}>
              <PaperBtn label="저장" onPress={save} style={{ flex: 1.4 }} />
              <PaperBtn label="취소" variant="secondary" onPress={() => { setAdding(false); setVerify(null); }} style={{ flex: 1 }} />
            </Row>
          </View>
        ) : (
          <Pressable style={s.addBtn} onPress={() => setAdding(true)} accessibilityRole="button" accessibilityLabel="주소 추가">
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>＋ 주소 추가</Text>
          </Pressable>
        )}
      </View>

      {/* [2026-08-10 density audit] roadmap clause ("공동현관 코드...다음 세션") cut — screens state
          facts, not the backlog. The pin-fact line stays: it explains what the pin strip does.
          [A③ 2026-08-24] 「주소를 길게 누르면 삭제돼요」 삭제 — 그 제스처가 사라졌다. 없는 동작을
          안내하는 줄은 그 자체로 거짓말이다. */}
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
  setDefaultChip: {
    borderWidth: 1, borderColor: paper.line, paddingVertical: 7, paddingHorizontal: 10,
    minHeight: 44, justifyContent: 'center',
  },
  // 카드 안의 행 — 풀블리드 구분선은 **뉴트럴**이다 (코랄 가로선 캡, Sean 2026-08-24).
  // 자체 press 타깃 ≥44pt.
  rowStrip: {
    marginTop: 10, marginHorizontal: -14, minHeight: 44,
    borderTopWidth: 1, borderTopColor: '#EEEEEE',
    paddingHorizontal: 14, justifyContent: 'center',
  },
  stripSetTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.dim },
  // [A①] 3.64:1 → 6.67:1. 같은 색조의 '읽는 버전'이 이미 토큰으로 있었다
  stripNeedTxt: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.actionInk },
  stripDeleteTxt: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical },
  noteEdit: { marginTop: 10, marginHorizontal: -14, borderTopWidth: 1, borderTopColor: '#EEEEEE', paddingHorizontal: 14, paddingTop: 12 },
  noteCount: { fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 6 },
  input: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 11, paddingHorizontal: 12, fontSize: 15.5, color: paper.ink,
  },
  verifyBtn: {
    borderWidth: 1, borderColor: paper.line, paddingHorizontal: 14,
    alignItems: 'center', justifyContent: 'center', minHeight: 44,
  },
  verifyQuiet: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 8 },
  // 찾음 = paceGoodWash/paceGoodInk (실측 4.50:1) · 못 찾음 = coral wash + actionInk (실패가
  // 아니라 안내다 — criticalWash는 쓰지 않는다)
  verifyHit: { backgroundColor: paper.paceGoodWash, paddingVertical: 10, paddingHorizontal: 12, marginTop: 8 },
  verifyMiss: { backgroundColor: paper.wash, paddingVertical: 10, paddingHorizontal: 12, marginTop: 8 },
  addBtn: {
    borderWidth: 1, borderColor: paper.line, alignItems: 'center', paddingVertical: 14,
    backgroundColor: paper.canvas,
  },
});
