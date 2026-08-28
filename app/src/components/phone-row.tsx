import { useCallback, useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { fetchMyPhone, formatPhone, phoneCollectionLive, phoneErrorMessage, setMyPhone } from '../lib/api';
import { colors, paper } from '../theme';
import { Row } from './ui';

// ═══ 연락처 섹션 (0133 서버 · 0154 스위치) ═══
//
// [Sean 2026-08-28, verbatim] 「guest is a member and needs a phone number enter thing.」
// 강아지 없이 클럽 산책에 오는 사람도 **멤버**이고(그래서 호스트에게 번호가 보이고), **번호를 넣을
// 자리가 있어야 한다**. 이 컴포넌트가 그 자리다.
//
// 🔴 왜 온보딩이 아니라 설정인가 — 범위 판단이고, 편의가 아니다. 계약 §3 이 정한 **가입 시점**
//   수집 지점은 `app/app/onboard/owner.tsx` · `onboard/runner.tsx` 이고, **그 둘을 건드리는 것이 곧
//   「전원에게 수집을 켠다」**이다. 그건 변호사 검토(계약 §8, `docs/legal/counsel-email.md` — 아직
//   발송 전)가 게이트다. 설정의 자율 입력은 다른 문이다: 사용자가 스스로 찾아와 스스로 넣는 자리이고,
//   **역할과 무관하게 마이 › 설정으로 닿을 수 있는** 유일한 화면이며(게스트에게는 보호자 온보딩을
//   통과할 강아지가 없다), §10 ④ 「Editable, but never blank」가 요구하는 바로 그 화면이다.
//
// 🔴 그리고 이 문조차 **서버 플래그** 뒤에 있다. gate 가 open 이 아니면 섹션을 아예 그리지 않고,
//   그려도 `set_my_phone` 이 `phone_collection_closed` 로 거절한다 (0154 §C). 클라만의 게이트는
//   게이트가 아니다 — 0138 §D 의 문장 그대로: 「a modified client is not bound by either.」
//
// ⚠ 왜 화면 안이 아니라 **독립 컴포넌트**인가. 첫 판은 `settings.tsx` 안에 직접 넣었고, react-doctor
//   가 `no-giant-component` 로 그 화면을 새로 잡았다 — **측정했다: 이 슬라이스 전 27건, 후 28건이고
//   추가된 하나가 settings.tsx 였다.** 「다들 그렇다」로 넘기지 않고 뺐다. 부수 효과가 하나 더 있고
//   그게 더 중요하다: 이 문이 언젠가 클럽 세션 화면에도 필요해지면 그 화면은 이걸 **그대로 마운트**
//   하면 된다 — 게이트·상태 기계·실패 처리·문구를 두 벌로 만들지 않는다.
//
// ⚠ 「인증됨」 같은 말은 절대 쓰지 않는다. §10 ① 「Shape-check is fine for the pilot」 은 비용 절감이
//   아니라 **정직 의무**를 같이 지운다: 우리는 이 번호를 확인한 적이 없고, 확인했다고 읽히는 어떤
//   표시도 거짓이다. 형식만 본다.

type Gate = 'loading' | 'open' | 'closed';
// 번호는 세 상태다. 실패를 null 로 접으면 「번호 없음」과 구별이 안 되고, 그러면 이미 번호가 있는
// 사람에게 빈 칸을 보여주게 된다 — 빈 값이 아니라 그 사람 데이터에 대한 지어낸 주장이다.
type Ph = { k: 'loading' } | { k: 'value'; v: string | null } | { k: 'error'; msg: string };

export function PhoneRow() {
  // 상태가 둘인 이유: 「수집이 열렸는가」와 「내 번호가 무엇인가」는 다른 질문이고, 화면은 그 조합을
  // 전부 다르게 그려야 한다.
  //   gate 'loading' → **아무것도 안 그린다.** 닫혀 있을 땐 섹션이 없어야 하므로, 로딩 중에 그렸다가
  //     치우면 있지도 않은 문이 깜빡인다. (설정 화면의 러너 활동 섹션은 반대로 로딩 중에도 그리는데,
  //     그쪽은 결과와 무관하게 문이 남고 여기는 문 자체가 사라질 수 있기 때문이다.)
  //   gate 'closed' → 번호가 **이미 있으면** 읽기 전용으로 보여주고(자기 데이터를 볼 권리는 플래그와
  //     무관하다 — 0154 §D 가 플래그에 걸리지 않는 이유), 없으면 침묵. 없는 문을 만들지 않는다.
  //   ⚠ 읽기 실패도 'closed' 로 접힌다 (`phoneCollectionLive` 가 실패를 false 로 읽는다). 0154 가 아직
  //     안 올라간 서버에 붙은 빌드에서 **모든** 사용자의 설정 화면에 영구히 깨진 줄이 생기는 것 —
  //     settings.tsx 의 러너 기준 위치가 겪었던 MAJOR-4 가 정확히 그 실수였다 — 을 막는다.
  const [gate, setGate] = useState<Gate>('loading');
  const [ph, setPh] = useState<Ph>({ k: 'loading' });
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [saveErr, setSaveErr] = useState<string | null>(null);

  const loadPhone = useCallback(() => {
    setPh({ k: 'loading' });
    fetchMyPhone()
      .then((v) => setPh({ k: 'value', v }))
      .catch((e) => setPh({ k: 'error', msg: phoneErrorMessage(e) }));
  }, []);

  useEffect(() => {
    let alive = true;
    phoneCollectionLive().then((open) => {
      if (!alive) return;
      setGate(open ? 'open' : 'closed');
      // 닫혀 있어도 한 번은 읽는다 — 이미 저장된 번호가 있으면 보여줘야 하고, 그게 있는지는 읽어보기
      // 전에는 모른다. 읽기는 수집이 아니다.
      loadPhone();
    });
    return () => { alive = false; };
  }, [loadPhone]);

  const savePhone = async () => {
    if (saving) return;
    setSaving(true);
    setSaveErr(null);
    try {
      await setMyPhone(draft);
      setEditing(false);
      setDraft('');
      loadPhone();                       // 서버가 정규화한 값을 다시 읽는다 — 화면이 지어내지 않는다
    } catch (e) {
      setSaveErr(phoneErrorMessage(e));  // 실패는 실패로 (조용한 catch → happy UI 금지)
    } finally {
      setSaving(false);
    }
  };

  // 섹션을 그릴지 말지. gate 를 아직 모를 때와, 닫혀 있는데 보여줄 번호도 없을 때는 침묵.
  const show = gate === 'open' || (gate === 'closed' && ph.k === 'value' && ph.v != null);
  if (!show) return null;

  const saveOff = saving || draft.trim().length === 0;

  return (
    <>
      <Text style={s.section}>연락처</Text>
      <View style={s.card}>
        {ph.k === 'loading' ? (
          // 로딩은 「미등록」이 아니다 — 값 자리에 확인 중이 서고, 아무 문도 열리지 않는다.
          <Row style={{ justifyContent: 'space-between', paddingVertical: 14 }}>
            <Text style={s.actionText}>휴대폰 번호</Text>
            <Text style={s.value}>확인 중…</Text>
          </Row>
        ) : ph.k === 'error' ? (
          // 못 읽었다는 사실을 말하고 다시 시도를 준다. 빈 칸을 그리면 「번호 없음」이라는 지어낸
          // 주장이 되고, 그 위에 저장 버튼을 얹으면 있는 번호를 덮어쓰게 만든다.
          <Pressable onPress={loadPhone} style={s.actionRow} accessibilityRole="button" accessibilityLabel="연락처 다시 불러오기">
            <View style={{ flex: 1, paddingRight: 10 }}>
              <Text style={s.actionText}>휴대폰 번호</Text>
              <Text style={s.failText}>불러오지 못했어요 — {ph.msg}</Text>
            </View>
            <Text style={s.retryText}>다시 시도 ›</Text>
          </Pressable>
        ) : gate === 'closed' ? (
          // 번호는 있는데 지금은 바꿀 수 없는 상태. 실재하는 상태이므로 실재하는 문장으로 그린다 —
          // 눌리지 않는 행이고, 눌리는 것처럼 보이는 장식(꺾쇠·립)도 붙이지 않는다.
          <Row style={{ justifyContent: 'space-between', paddingVertical: 14 }}>
            <View style={{ flex: 1, paddingRight: 10 }}>
              <Text style={s.actionText}>휴대폰 번호</Text>
              <Text style={s.hint}>지금은 번호를 바꿀 수 없어요</Text>
            </View>
            <Text style={s.value}>{formatPhone(ph.v as string)}</Text>
          </Row>
        ) : editing ? (
          <View style={{ paddingVertical: 14 }}>
            <Text style={s.actionText}>휴대폰 번호</Text>
            <TextInput
              style={s.field}
              value={draft}
              onChangeText={setDraft}
              placeholder="010-0000-0000"
              placeholderTextColor={paper.faint}
              keyboardType="phone-pad"
              maxLength={20}
              autoFocus
              accessibilityLabel="휴대폰 번호 입력"
            />
            {saveErr != null && <Text style={s.failText}>{saveErr}</Text>}
            <Row style={{ gap: 8, marginTop: 12 }}>
              <Pressable
                onPress={savePhone}
                disabled={saveOff}
                style={[s.saveBtn, saveOff && s.saveBtnOff]}
                accessibilityRole="button"
                accessibilityLabel="휴대폰 번호 저장"
                accessibilityState={{ disabled: saveOff, busy: saving }}
              >
                {/* 바쁨은 라벨 스왑이 집안 문법이다 (DESIGN.md F2.1) — 알파로 흐리게 만들지 않는다.
                    비활성은 disabledFill + faint 라는 명시 페인트 쌍 (theme.ts:239). 흰 글씨를 회색
                    면 위에 그대로 두면 읽히지 않으므로 잉크도 같이 바뀐다. */}
                <Text style={[s.saveTxt, saveOff && s.saveTxtOff]}>{saving ? '저장 중...' : '저장'}</Text>
              </Pressable>
              <Pressable
                onPress={() => { setEditing(false); setDraft(''); setSaveErr(null); }}
                disabled={saving}
                style={s.cancelBtn}
                accessibilityRole="button"
                accessibilityLabel="입력 취소"
              >
                <Text style={s.cancelTxt}>취소</Text>
              </Pressable>
            </Row>
          </View>
        ) : (
          <Pressable
            onPress={() => { setDraft(ph.v != null ? formatPhone(ph.v) : ''); setSaveErr(null); setEditing(true); }}
            style={s.actionRow}
            accessibilityRole="button"
            accessibilityLabel={ph.v != null ? '휴대폰 번호 변경' : '휴대폰 번호 등록'}
          >
            <View style={{ flex: 1, paddingRight: 10 }}>
              <Text style={s.actionText}>휴대폰 번호</Text>
              {/* 누가 보는지 정확히 말한다. `_club_phone_visible`(0049:167-192) 의 실제 규칙 세 갈래를
                  그대로 옮긴 것이고, 줄이면 거짓이 된다 — 내가 호스트일 때가 가장 넓다. */}
              <Text style={s.hint}>
                클럽 세션이 열려 있는 동안 호스트에게, 그리고 우리 아이를 맡은 러너에게 보여요 ·
                내가 호스트일 때는 참여자 모두에게 보여요
              </Text>
            </View>
            <Text style={s.value}>{ph.v != null ? formatPhone(ph.v) : '등록 안 됨'}</Text>
            <Text style={{ fontSize: 16, color: colors.dim, marginLeft: 6 }}>›</Text>
          </Pressable>
        )}
      </View>
    </>
  );
}

// settings.tsx 의 섹션/카드 문법을 그대로 쓴다 — 이 컴포넌트는 그 화면 안에 앉으므로 둘이 어긋나면
// 한 화면에 두 가지 카드가 생긴다.
const s = StyleSheet.create({
  section: { fontSize: 17, fontWeight: '900', color: paper.ink, marginTop: 20, marginBottom: 8 },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: '#DCD6C4' },
  actionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 14 },
  actionText: { fontSize: 16, fontWeight: '700', color: paper.ink },
  // 15pt 플로어 + paper.dim (5.7:1) — 디테일 텍스트 법 (theme.ts)
  hint: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 3 },
  value: { fontSize: 15.5, fontWeight: '700', color: paper.ink },
  // 온보딩의 입력 문법 (onboard/owner.tsx 의 .fieldAddr): 잉크 헤어라인 밑줄, 16/700.
  field: {
    marginTop: 8, paddingTop: 10, paddingBottom: 8, minHeight: 44,
    borderBottomWidth: 1.5, borderBottomColor: paper.ink,
    fontSize: 16, fontWeight: '700', color: paper.ink,
  },
  // 15pt 플로어 — 실패 문장은 디테일이 아니라 사람이 반드시 읽어야 하는 줄이다.
  failText: { marginTop: 6, fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },
  retryText: { fontSize: 15.5, fontWeight: '800', color: paper.critical },
  // 3D 립 — Sean 의 상시 룰링 (「all primary buttons should have a 3d kinda thing」). paper-btn 과 같은
  // 문법: 잉크 면 + 아래쪽 어두운 테두리가 눌림의 깊이를 만든다.
  saveBtn: {
    minHeight: 44, paddingHorizontal: 22, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.ink, borderRadius: 12, borderBottomWidth: 3, borderBottomColor: '#000',
  },
  // 비활성은 알파가 아니라 명시 페인트다 (theme.ts:205-207 — 알파 트릭은 대비를 깎는다).
  saveBtnOff: { backgroundColor: paper.disabledFill, borderBottomColor: paper.line },
  saveTxt: { fontSize: 16, fontWeight: '800', color: '#fff' },
  saveTxtOff: { color: paper.faint },
  cancelBtn: { minHeight: 44, paddingHorizontal: 16, alignItems: 'center', justifyContent: 'center' },
  cancelTxt: { fontSize: 16, fontWeight: '700', color: paper.dim },
});
