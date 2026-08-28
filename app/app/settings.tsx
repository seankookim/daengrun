import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { DeleteAccountSheet } from '../src/components/delete-account-sheet';
import { Row } from '../src/components/ui';
import { fetchMyProfile, fetchMyRunnerBase, MyProfile } from '../src/lib/api';
import { fetchMyPhone, formatPhone, phoneCollectionLive, phoneErrorMessage, setMyPhone } from '../src/lib/api';
import { kstCal, kstMonthDay } from '../src/lib/kst';
import { goBackOrHome } from '../src/lib/nav';
import { session } from '../src/store';
import { colors, paper } from '../src/theme';

// 설정 — 실화면. 가짜 하위메뉴 없음: 실계정 정보 + 실동작만, 나머지는 정직 라벨.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const APP_VERSION = '0.9 (파일럿)';

// 변경 잠금 안내 — 「7일에 한 번」이라는 숫자는 여기서 말하지 않는다. 쿨다운의 길이는 서버의
// _base_change_cooldown() (0123 §4b, Sean 2026-08-25 T1 룰링) 하나에만 있고, 클라가 되뇌면
// 숫자가 두 벌이 된다. 서버가 주는 can_change_at만 쓰고, 잠기지 않았으면 아무 말도 안 한다.
const lockSuffix = (iso: string | null): string => {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t) || t <= Date.now()) return '';
  // 날짜는 KST 로 읽는다 — can_change_at 은 서버 instant 이고, 기기 로컬로 읽으면 KST 자정
  // 근처의 만료가 하루 어긋나 「내일부터」를 「오늘부터」로 말한다. base-pin.tsx 와 같은 문자열.
  return ` · ${kstMonthDay(kstCal(t))}부터 변경 가능`;
};

export default function Settings() {
  const { session: auth, signOut } = useAuth();
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);
  // [0123 · Sean Q6 ruling B] 러너 활동 기준 위치. 네 상태가 **전부 다르게** 그려져야 한다:
  //   'loading'  — 아직 모름 (로딩은 「미설정」이 아니다) → 섹션은 그리고 값 자리에 「확인 중…」
  //   'unset'    — 러너인데 아직 안 정함 → 진짜 문
  //   'set'      — 지정됨
  //   'none'     — 러너 계정이 아님 → **섹션 자체를 안 그린다** (없는 문을 만들지 않는다)
  //   'error'    — 못 읽음 → **섹션 자체를 안 그린다**
  // 🔴 'error'가 'none'과 같은 처리인 것이 픽스 라운드의 MAJOR-4다. 첫 판은 「저장된 위치를
  // 불러오지 못했어요 / —」라는 줄을 그렸고, 그건 한 사람의 일시적 장애에는 정직하지만 **배포
  // 순서에는 재앙**이다: 0123이 아직 안 올라간 서버에 붙은 빌드는 my_runner_base()가 없어서
  // 모든 호출이 실패하고, 그러면 러너가 아닌 **모든 보호자**의 설정 화면에 영구히 깨진 줄이
  // 하나 생긴다 — 자기와 아무 상관도 없는 기능에 대해. 러너 활동은 설정의 부가 섹션이므로
  // 못 읽을 때의 정직한 답은 침묵이다 (요청함의 문은 별개 경로로 살아 있다).
  // 모드(session.role)가 아니라 **서버 진실**로 가른다: 보호자 모드로 들어와도 러너 계정이면
  // 이 문은 찾을 수 있어야 한다 (Sean: "switch this address in settings").
  const [base, setBase] = useState<'loading' | 'none' | 'unset' | 'set' | 'error'>('loading');
  // 잠금 해제 시각 (0123 §4b). 서버가 준 결과값이고, 여기서는 한 줄 덧붙이는 데만 쓴다.
  const [lockedUntil, setLockedUntil] = useState<string | null>(null);

  // ── 연락처 (0133 서버 · 0154 스위치) ──────────────────────────────────────────────────
  // [Sean 2026-08-28, verbatim] 「guest is a member and needs a phone number enter thing.」
  // 강아지 없이 오는 게스트도 멤버이고(그래서 호스트에게 번호가 보이고), **번호를 넣을 자리가
  // 있어야 한다**. 이 섹션이 그 자리다.
  //
  // 🔴 왜 온보딩이 아니라 여기인가. 계약 §3 이 정한 **가입 시점** 수집 지점은 onboard/owner ·
  //   onboard/runner 이고, 그 둘을 건드리는 것이 곧 「전원에게 수집을 켠다」이다 — 그건 변호사
  //   검토(계약 §8)가 게이트이고 그 메일은 아직 안 나갔다. 설정의 자율 입력은 다른 문이다:
  //   사용자가 스스로 찾아와 스스로 넣고, **역할과 무관하게 마이 › 설정으로 닿을 수 있는** 유일한
  //   화면이며(게스트는 보호자 온보딩을 통과할 강아지가 없다), §10 ④ 「Editable, but never blank」가
  //   요구하는 바로 그 화면이다.
  //
  // 🔴 그리고 이 문조차 **서버 플래그** 뒤에 있다. gate 가 open 이 아니면 섹션을 아예 그리지 않고,
  //   그려도 set_my_phone 이 phone_collection_closed 로 거절한다 (0154 §C). 클라만의 게이트는
  //   게이트가 아니다 — 0138 §D 의 문장 그대로: 「a modified client is not bound by either.」
  //
  // 상태가 둘인 이유: 「수집이 열렸는가」와 「내 번호가 무엇인가」는 다른 질문이고, 화면은 네 조합을
  // 전부 다르게 그려야 한다.
  //   gate 'loading' → **아무것도 안 그린다.** 닫혀 있을 땐 섹션이 없어야 하므로, 로딩 중에 그렸다가
  //     치우면 있지도 않은 문이 깜빡인다. 러너 활동 섹션이 로딩 중에도 그리는 것과 반대인데, 그쪽은
  //     결과와 무관하게 문이 남고 여기는 문 자체가 사라질 수 있기 때문이다.
  //   gate 'closed' → 번호가 **이미 있으면** 읽기 전용으로 보여주고(자기 데이터를 볼 권리는 플래그와
  //     무관하다), 없으면 침묵. 없는 문을 만들지 않는다.
  //   ⚠ 읽기 실패도 'closed' 로 접힌다 (phoneCollectionLive 가 실패를 false 로 읽는다). 0154 가 아직
  //     안 올라간 서버에 붙은 빌드에서 모든 사용자의 설정 화면에 영구히 깨진 줄이 생기는 것 —
  //     0123 의 MAJOR-4 가 정확히 그 실수였다 — 을 막는다.
  const [gate, setGate] = useState<'loading' | 'open' | 'closed'>('loading');
  // 번호는 세 상태다. 실패를 null 로 접으면 「번호 없음」과 구별이 안 되고, 그러면 이미 번호가 있는
  // 사람에게 빈 칸을 보여주게 된다 — 빈 값이 아니라 그 사람 데이터에 대한 지어낸 주장이다.
  const [ph, setPh] = useState<{ k: 'loading' } | { k: 'value'; v: string | null } | { k: 'error'; msg: string }>({ k: 'loading' });
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
      // 닫혀 있어도 한 번은 읽는다 — 이미 저장된 번호가 있으면 보여줘야 하고, 그게 있는지는
      // 읽어보기 전에는 모른다. 읽기는 수집이 아니다 (0154 §D 가 플래그에 걸리지 않는 이유).
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

  // 섹션을 그릴지 말지. gate 가 아직 모를 때와, 닫혀 있는데 보여줄 번호도 없을 때는 침묵.
  const showPhoneSection = gate === 'open' || (gate === 'closed' && ph.k === 'value' && ph.v != null);

  useEffect(() => {
    fetchMyProfile().then(setProfile).catch(() => {});
  }, []);

  // 화면에 돌아올 때마다 다시 읽는다 — 핀 화면에서 저장/삭제하고 back으로 오면 이 줄이 낡는다.
  useFocusEffect(
    useCallback(() => {
      let alive = true;
      fetchMyRunnerBase()
        .then((b) => {
          if (!alive) return;
          if (b == null) { setBase('none'); setLockedUntil(null); return; }
          setLockedUntil(b.canChangeAt);
          setBase(b.lat != null && b.lng != null ? 'set' : 'unset');
        })
        .catch((e) => {
          console.warn('[settings] runner base:', (e as Error)?.message ?? e);
          if (alive) setBase('error');
        });
      return () => { alive = false; };
    }, []),
  );

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ paddingHorizontal: 11, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>설정</Text>
        <View style={{ width: 40 }} />
      </Row>

      {/* 계정 (실정보) */}
      <Text style={s.section}>계정</Text>
      <View style={s.card}>
        <InfoRow label="이메일" value={auth?.user.email ?? '—'} />
        <View style={s.div} />
        <InfoRow label="이름" value={profile?.name ?? '—'} />
        <View style={s.div} />
        <InfoRow label="현재 모드" value={session.role === 'runner' ? '러너' : '보호자'} />
      </View>

      {/* 실동작 */}
      <View style={[s.card, { marginTop: 10 }]}>
        <Pressable onPress={() => router.dismissTo('/')} style={s.actionRow}>
          <Text style={s.actionText}>역할 전환 (보호자 ↔ 러너)</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        {/* [charge slice 2026-08-13] 준비 중 카드의 '결제 수단 — PG 연동 후' InfoRow가 여기로 승격.
            실화면이 생겼다: 등록된 카드·청구 내역·실패한 청구의 재시도가 전부 서버 진실이다. */}
        <Pressable onPress={() => router.push('/payments')} style={s.actionRow}>
          <Text style={s.actionText}>결제 관리</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={() => Linking.openURL('mailto:seankookim@uchicago.edu?subject=도그스하이 문의')}
          style={s.actionRow}
        >
          <Text style={s.actionText}>문의하기</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
          style={s.actionRow}
        >
          <Text style={[s.actionText, { color: '#d84a2f' }]}>로그아웃</Text>
        </Pressable>
        <View style={s.div} />
        {/* [O-6 2026-08-20] 계정 삭제는 '준비 중 · 문의로 처리' InfoRow에서 여기로 승격.
            App Store 5.1.1(v)는 인앱 개시를 요구한다 — 문의 메일은 개시가 아니고,
            비활성 카드 안의 회색 라벨은 '찾을 수 있는' 위치도 아니다 (계약 §C.2 1).
            로그아웃과 같은 코랄 잉크: 둘 다 세션을 끝내는 행이고, 무게 차이는 시트가 진다. */}
        <Pressable onPress={() => setDeleteOpen(true)} style={s.actionRow} accessibilityRole="button">
          <Text style={[s.actionText, { color: '#d84a2f' }]}>계정 삭제</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
      </View>

      {/* 러너 활동 — 러너 계정에서만. 「없는 문을 만들지 않는다」: 러너가 아니면 섹션째로 없다.
          [0123 · Sean's Q6 ruling B 2026-08-25, verbatim: 「go with B for distance, and the runner
          should be able to switch this address in settings.」] 이 줄이 그 "settings"다.
          로딩 중에도 섹션을 그리는 이유: 러너에게 이 문이 **깜빡였다 나타나는** 것보다, 있는 줄
          알고 들어와서 상태를 읽는 편이 낫다. 값 자리에는 「확인 중…」이 서고 0도 「미설정」도 아니다. */}
      {(base === 'set' || base === 'unset' || base === 'loading') && (
        <>
          <Text style={s.section}>러너 활동</Text>
          <View style={s.card}>
            <Pressable
              onPress={() => router.push('/runner/base-pin')}
              style={s.actionRow}
              accessibilityRole="button"
              accessibilityLabel="활동 기준 위치 설정"
            >
              <View style={{ flex: 1, paddingRight: 10 }}>
                <Text style={s.actionText}>활동 기준 위치</Text>
                {/* 반올림을 여기서도 말한다 — 러너가 문을 열기 전에 무엇이 저장되는지 안다.
                    이건 사과가 아니라 기능이다: 우리는 러너가 어디 사는지 정확히 알고 싶지 않다. */}
                <Text style={s.actionHint}>
                  {base === 'set'
                    ? `요청 카드에 출발지까지 대략 거리가 표시돼요 · 약 1km 격자로만 저장돼요${lockSuffix(lockedUntil)}`
                    : base === 'unset'
                      ? '지정하면 요청 카드에 출발지까지 대략 거리가 보여요'
                      : '확인 중…'}
                </Text>
              </View>
              <Text style={s.baseValue}>
                {base === 'set' ? '지정됨' : base === 'unset' ? '설정 안 됨' : '확인 중…'}
              </Text>
              <Text style={{ fontSize: 16, color: colors.dim, marginLeft: 6 }}>›</Text>
            </Pressable>
          </View>
        </>
      )}

      {/* ————— 연락처 (0133 서버 · 0154 스위치 · Sean 2026-08-28 게스트 확정) —————
          ⚠ 「인증됨」 같은 말은 절대 쓰지 않는다. §10 ① 「Shape-check is fine for the pilot」은
            비용 절감이 아니라 **정직 의무**를 같이 지운다: 우리는 이 번호를 확인한 적이 없고,
            확인했다고 읽히는 어떤 표시도 거짓이다. 형식만 본다. */}
      {showPhoneSection && (
        <>
          <Text style={s.section}>연락처</Text>
          <View style={s.card}>
            {ph.k === 'loading' ? (
              // 로딩은 「미등록」이 아니다 — 값 자리에 확인 중이 서고, 아무 문도 열리지 않는다.
              <Row style={{ justifyContent: 'space-between', paddingVertical: 14 }}>
                <Text style={s.actionText}>휴대폰 번호</Text>
                <Text style={s.baseValue}>확인 중…</Text>
              </Row>
            ) : ph.k === 'error' ? (
              // 못 읽었다는 사실을 말하고 다시 시도를 준다. 빈 칸을 그리면 「번호 없음」이라는
              // 지어낸 주장이 되고, 그 위에 저장 버튼을 얹으면 있는 번호를 덮어쓰게 만든다.
              <Pressable onPress={loadPhone} style={s.actionRow} accessibilityRole="button" accessibilityLabel="연락처 다시 불러오기">
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.actionText}>휴대폰 번호</Text>
                  <Text style={s.failText}>불러오지 못했어요 — {ph.msg}</Text>
                </View>
                <Text style={s.retryText}>다시 시도 ›</Text>
              </Pressable>
            ) : gate === 'closed' ? (
              // 번호는 있는데 지금은 바꿀 수 없는 상태. 실재하는 상태이므로 실재하는 문장으로
              // 그린다 — 눌리지 않는 행이고, 눌리는 것처럼 보이는 장식도 붙이지 않는다.
              <Row style={{ justifyContent: 'space-between', paddingVertical: 14 }}>
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.actionText}>휴대폰 번호</Text>
                  <Text style={s.actionHint}>지금은 번호를 바꿀 수 없어요</Text>
                </View>
                <Text style={s.baseValue}>{formatPhone(ph.v as string)}</Text>
              </Row>
            ) : editing ? (
              <View style={{ paddingVertical: 14 }}>
                <Text style={s.actionText}>휴대폰 번호</Text>
                <TextInput
                  style={s.phoneField}
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
                    disabled={saving || draft.trim().length === 0}
                    style={[s.saveBtn, (saving || draft.trim().length === 0) && s.saveBtnOff]}
                    accessibilityRole="button"
                    accessibilityLabel="휴대폰 번호 저장"
                    accessibilityState={{ disabled: saving || draft.trim().length === 0, busy: saving }}
                  >
                    {/* 바쁨은 라벨 스왑이 집안 문법이다 (DESIGN.md F2.1) — 알파로 흐리게 만들지 않는다.
                        비활성은 disabledFill + faint 라는 명시 페인트 쌍 (theme.ts:239). 흰 글씨를
                        회색 면 위에 그대로 두면 읽히지 않으므로 잉크도 같이 바뀐다. */}
                    <Text style={[s.saveTxt, (saving || draft.trim().length === 0) && s.saveTxtOff]}>
                      {saving ? '저장 중...' : '저장'}
                    </Text>
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
                  {/* 누가 보는지 정확히 말한다. `_club_phone_visible`(0049) 의 실제 규칙 세 갈래를
                      그대로 옮긴 것이고, 줄이면 거짓이 된다 — 호스트일 때가 가장 넓다. */}
                  <Text style={s.actionHint}>
                    클럽 세션이 열려 있는 동안 호스트에게, 그리고 우리 아이를 맡은 러너에게 보여요 ·
                    내가 호스트일 때는 참여자 모두에게 보여요
                  </Text>
                </View>
                <Text style={s.baseValue}>{ph.v != null ? formatPhone(ph.v) : '등록 안 됨'}</Text>
                <Text style={{ fontSize: 16, color: colors.dim, marginLeft: 6 }}>›</Text>
              </Pressable>
            )}
          </View>
        </>
      )}

      {/* DEV 전용 — 프로덕션 빌드에선 렌더되지 않음 (__DEV__ 게이트, 화면 자체도 이중 게이트) */}
      {__DEV__ && (
        <View style={[s.card, { marginTop: 10, borderColor: '#7B6CDF' }]}>
          <Pressable onPress={() => router.push('/dev/club-lab')} style={s.actionRow}>
            <Text style={[s.actionText, { color: '#4A3DA8' }]}>R2 커스터디 랩 (DEV)</Text>
            <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
          </Pressable>
        </View>
      )}

      {/* 준비 중 — 정직 라벨. 계정 삭제는 실동작이 되어 위 카드로 떠났다 (O-6). */}
      {/* [2026-08-20] The card was painted `opacity: 0.55`, the alpha trick theme.ts:205-207
          bans for disabled surfaces. Measured, that alpha put the label at 2.99:1 and the value
          at 4.06:1 over white — both under the 4.5 floor, i.e. the "준비 중" signal was being
          paid for in legibility. Explicit disabled paint instead: disabledFill面 + dim ink,
          measured 5.13:1. The row is not pressable, so nothing else changes. */}
      <Text style={s.section}>준비 중</Text>
      <View style={[s.card, s.cardPending]}>
        <InfoRow label="알림 설정" value="푸시 도입 후" muted />
      </View>

      <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 18 }}>
        도그스하이 {APP_VERSION} · 반려견 피트니스
      </Text>

      {/* 열려 있을 때만 마운트 — 시트의 상태(거절 문구·꾹 누름 확인)가 다음 열기로 새지 않는다 */}
      {deleteOpen && <DeleteAccountSheet onClose={() => setDeleteOpen(false)} />}
    </ScrollView>
  );
}

// muted = the 준비 중 card's non-interactive row. Ink, not alpha (theme.ts:205-207).
function InfoRow({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
      <Text style={{ fontSize: 15.5, color: muted ? paper.dim : '#3d453d' }}>{label}</Text>
      <Text style={{ fontSize: 15.5, fontWeight: '700', color: muted ? paper.dim : paper.ink }} numberOfLines={1}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  section: { fontSize: 17, fontWeight: '900', color: paper.ink, marginTop: 20, marginBottom: 8 },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: '#DCD6C4' },
  cardPending: { backgroundColor: paper.disabledFill }, // 준비 중 card — explicit fill, no alpha
  div: { height: 1, backgroundColor: '#f0eee3' },
  actionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 14 },
  actionText: { fontSize: 16, fontWeight: '700', color: paper.ink },
  // 15pt 플로어 + paper.dim(5.7:1) — 디테일 텍스트 법 (theme.ts)
  actionHint: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 3 },
  baseValue: { fontSize: 15.5, fontWeight: '700', color: paper.ink },
  // ── 연락처 (0154) ──
  // 온보딩의 입력 문법을 그대로 쓴다 (onboard/owner.tsx 의 .fieldAddr): 잉크 헤어라인 밑줄, 16/700.
  phoneField: {
    marginTop: 8, paddingTop: 10, paddingBottom: 8, minHeight: 44,
    borderBottomWidth: 1.5, borderBottomColor: paper.ink,
    fontSize: 16, fontWeight: '700', color: paper.ink,
  },
  // 15pt 플로어 — 실패 문장은 디테일이 아니라 사람이 읽어야 하는 줄이다.
  failText: { marginTop: 6, fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },
  retryText: { fontSize: 15.5, fontWeight: '800', color: paper.critical },
  // 3D 립 — Sean 의 상시 룰링 (「all primary buttons should have a 3d kinda thing」). paper-btn 과
  // 같은 문법: 잉크 면 + 아래쪽 어두운 테두리가 눌림의 깊이를 만든다.
  saveBtn: {
    minHeight: 44, paddingHorizontal: 22, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.ink, borderRadius: 12, borderBottomWidth: 3, borderBottomColor: '#000',
  },
  // 비활성은 알파가 아니라 명시 페인트다 (theme.ts:205-207 — 알파 트릭은 대비를 깎는다).
  saveBtnOff: { backgroundColor: paper.disabledFill, borderBottomColor: paper.line },
  saveTxt: { fontSize: 16, fontWeight: '800', color: '#fff' },
  saveTxtOff: { color: paper.faint },   // theme.ts:239 의 disabled 쌍 — disabledFill + faint
  cancelBtn: { minHeight: 44, paddingHorizontal: 16, alignItems: 'center', justifyContent: 'center' },
  cancelTxt: { fontSize: 16, fontWeight: '700', color: paper.dim },
});
