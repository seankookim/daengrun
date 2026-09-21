import { useCallback, useEffect, useState } from 'react';
import {
  Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import { deleteMyBankAccount, fetchMyBankAccount, MyBankAccount, setMyBankAccount } from '../../src/lib/api';
import {
  ACCOUNT_UNREADABLE_KO, BANKS, BANK_ERROR_KO, BANK_NOTE, validateBankAccount,
} from '../../src/lib/bank-account';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { colors, paper } from '../../src/theme';

// 정산 계좌 — 0194. `earnings.tsx:158` 이 「계좌 등록은 오픈뱅킹 연동과 함께 제공돼요」라고 적어 둔
// 자리가 실화면이 된다. 그 문장은 사실이었다: `bank_accounts` 는 0001 부터 있었지만 행을 만들 방법이
// 없었고, 그래서 0186 의 운영자는 이체할 곳을 찾을 수 없었다.
//
// 🔴 이 화면은 번호를 **절대 다시 보여주지 않는다.** 서버가 돌려주는 것은 마지막 4자리뿐이고
//   (`account_masked`), 암호문 열은 클라가 SELECT 할 수조차 없다(0194 §C). 그래서 「변경」은 항상
//   새로 입력하는 것이지 기존 값을 불러와 고치는 것이 아니다 — 입력칸을 저장된 값으로 채우는 순간
//   그건 우리가 갖고 있지 않은 정보를 가진 척하는 화면이 된다.
//
// 🔴 예금주 확인(1원 인증)은 **없다.** `verified_at` 은 언제나 NULL 이고 서버는 그 칸에 아무것도
//   쓰지 않는다. 그래서 이 화면에는 「확인됨」 배지가 없고, 대신 안내문이 없다는 사실을 말한다
//   (BANK_NOTE). 없는 검증을 그린 배지는 돈이 걸린 화면에서 가장 비싼 거짓말이다.
//
// 상태는 넷이 전부 다르게 그려진다:
//   'loading' — 아직 모름 → 문장 한 줄 (폼을 빈 채로 미리 그리지 않는다)
//   'error'   — 못 읽음 → 라우드-페일 스트립 + 「다시 시도」, 폼은 아예 없다
//   'ready + 계좌 있음' — 마스크 카드 + 변경 폼 + 삭제
//   'ready + 계좌 없음' — 등록 폼만
type Phase = 'loading' | 'error' | 'ready';

export default function BankAccountScreen() {
  const insets = useSafeAreaInsets();
  const [phase, setPhase] = useState<Phase>('loading');
  const [current, setCurrent] = useState<MyBankAccount | null>(null);
  const [bank, setBank] = useState<string | null>(null);
  const [account, setAccount] = useState('');
  const [holder, setHolder] = useState('');
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [formErr, setFormErr] = useState<string | null>(null);

  const load = useCallback(() => {
    setPhase('loading');
    setFormErr(null);
    fetchMyBankAccount()
      .then((row) => {
        setCurrent(row);
        // ⚠ 은행만 미리 고른다. 번호와 이름은 비운 채로 둔다 — 서버가 준 적 없는 값이라
        // 채울 수 있는 정직한 값 자체가 없다.
        setBank(row?.bank ?? null);
        setAccount('');
        setHolder('');
        setPhase('ready');
      })
      .catch((e) => {
        console.warn('[bank-account] load:', (e as Error)?.message ?? e);
        setPhase('error');
      });
  }, []);
  useEffect(() => { load(); }, [load]);

  const save = useCallback(() => {
    if (saving || deleting) return;
    // 로컬 검증은 **서버의 사본**이다(같은 순서·같은 토큰). 집행은 서버가 한다 —
    // 여기서 걸러지는 건 왕복 한 번이지 규칙이 아니다.
    const refusal = validateBankAccount({ bank, account, holder });
    if (refusal !== null) { setFormErr(BANK_ERROR_KO[refusal]); haptic('light'); return; }
    setFormErr(null);
    setSaving(true);
    haptic('light');
    setMyBankAccount({ bank: bank as string, account, holder })
      .then((row) => {
        // 서버가 **보관한** 행으로 덮어쓴다. 보낸 값을 그대로 그리면 화면이 서버가 가진 값이
        // 아니라 우리가 보낸 값을 보여주게 된다 — 돈 목적지에서는 그 차이가 전부다.
        setCurrent(row);
        setAccount('');
        setHolder('');
      })
      .catch((e) => setFormErr((e as Error)?.message || '정산 계좌를 저장하지 못했어요'))
      .finally(() => setSaving(false));
  }, [bank, account, holder, saving, deleting]);

  const confirmDelete = useCallback(() => {
    if (saving || deleting) return;
    Alert.alert(
      '정산 계좌를 삭제할까요?',
      '삭제하면 정산받을 곳이 없어져요 · 다시 등록할 수 있어요',
      [
        { text: '취소', style: 'cancel' },
        {
          text: '삭제',
          style: 'destructive',
          onPress: () => {
            setFormErr(null);
            setDeleting(true);
            deleteMyBankAccount()
              .then(() => { setCurrent(null); setBank(null); })
              .catch((e) => setFormErr((e as Error)?.message || '계좌를 삭제하지 못했어요'))
              .finally(() => setDeleting(false));
          },
        },
      ],
    );
  }, [saving, deleting]);

  const busy = saving || deleting;

  return (
    <>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView
          style={{ flex: 1, backgroundColor: colors.cream }}
          contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
          keyboardShouldPersistTaps="handled"
        >
          <Row style={{ justifyContent: 'space-between' }}>
            <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
              <Text style={{ fontSize: 20.5 }}>‹</Text>
            </Pressable>
            <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>정산 계좌</Text>
            <View style={{ width: 40 }} />
          </Row>

          <Text style={s.note}>{BANK_NOTE}</Text>

          {phase === 'loading' && (
            <View style={[s.card, { marginTop: 10 }]}>
              <Text style={s.loading}>계좌 정보를 불러오는 중이에요…</Text>
            </View>
          )}

          {phase === 'error' && (
            <View style={s.failStrip}>
              <Text style={s.failText}>정산 계좌를 불러오지 못했어요</Text>
              <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
                <Text style={s.retryLabel}>다시 시도</Text>
              </Pressable>
            </View>
          )}

          {phase === 'ready' && (
            <>
              {current !== null && (
                <View style={[s.card, { marginTop: 10, paddingVertical: 15 }]}>
                  <Text style={s.kicker}>등록된 계좌</Text>
                  <Text style={s.currentBank}>{current.bankLabel ?? current.bank}</Text>
                  {/* 마스크는 서버가 만든다. null 이면 그 행을 복호화하지 못한다는 뜻이고,
                      그건 조용히 넘길 일이 아니라 다시 등록해야 한다는 뜻이다. */}
                  {current.accountMasked !== null ? (
                    <Text style={s.currentAccount}>{current.accountMasked} · {current.holder}</Text>
                  ) : (
                    <Text style={s.currentBroken}>{ACCOUNT_UNREADABLE_KO}</Text>
                  )}
                </View>
              )}

              {formErr !== null && (
                <View style={s.failStrip}>
                  <Text style={s.failText}>{formErr}</Text>
                </View>
              )}

              <Text style={s.secTitle}>{current === null ? '계좌 등록' : '계좌 변경'}</Text>
              {current !== null && (
                <Text style={s.subNote}>
                  보안을 위해 저장된 번호는 다시 보여드리지 않아요 · 전체를 새로 입력해주세요
                </Text>
              )}

              <Text style={s.fieldLabel}>은행</Text>
              <View style={s.bankWrap}>
                {BANKS.map((b) => {
                  const on = b.code === bank;
                  return (
                    <Pressable
                      key={b.code}
                      onPress={() => { if (!busy) { setBank(b.code); haptic('light'); } }}
                      disabled={busy}
                      accessibilityRole="button"
                      accessibilityState={{ selected: on, disabled: busy }}
                      accessibilityLabel={b.label}
                      style={[s.bankChip, on && s.bankChipOn, busy && !on && s.chipDisabled]}
                    >
                      <Text style={[s.bankChipLabel, on && s.bankChipLabelOn]}>{b.label}</Text>
                    </Pressable>
                  );
                })}
              </View>

              <Text style={s.fieldLabel}>계좌번호</Text>
              <TextInput
                value={account}
                onChangeText={setAccount}
                editable={!busy}
                keyboardType="number-pad"
                placeholder="- 없이 숫자만 입력해도 돼요"
                placeholderTextColor={paper.dim}
                // ⚠ 자동완성·자동저장 전부 끈다. 계좌번호는 OS 키체인에 흘려보낼 값이 아니다.
                autoComplete="off"
                textContentType="none"
                autoCorrect={false}
                importantForAutofill="no"
                style={s.input}
                accessibilityLabel="계좌번호"
              />

              <Text style={s.fieldLabel}>예금주</Text>
              <TextInput
                value={holder}
                onChangeText={setHolder}
                editable={!busy}
                placeholder="통장에 적힌 이름 그대로"
                placeholderTextColor={paper.dim}
                textContentType="name"
                autoCorrect={false}
                style={s.input}
                accessibilityLabel="예금주"
              />

              {/* ⚠ 「Disabled stays flat」 (DESIGN.md:218) — a dead key has no travel, so the lip
                  and the press transform are both dropped while busy rather than dimmed. */}
              <Pressable
                onPress={save}
                disabled={busy}
                accessibilityRole="button"
                accessibilityState={{ disabled: busy, busy: saving }}
                style={({ pressed }) => [
                  s.primary,
                  busy ? s.flatDisabled : (pressed && s.primaryPressed),
                ]}
              >
                <Text style={[s.primaryLabel, busy && s.flatDisabledLabel]}>{saving ? '저장 중…' : '계좌 저장'}</Text>
              </Pressable>

              {current !== null && (
                <Pressable
                  onPress={confirmDelete}
                  disabled={busy}
                  accessibilityRole="button"
                  accessibilityState={{ disabled: busy, busy: deleting }}
                  style={({ pressed }) => [s.destructive, !busy && pressed && s.destructivePressed]}
                >
                  <Text style={s.destructiveLabel}>{deleting ? '삭제 중…' : '계좌 삭제'}</Text>
                </Pressable>
              )}
            </>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

// 15pt 플로어 (DESIGN.md:145) — 한국어는 kicker 면제를 타지 않으므로 여기 어떤 한글도 15 밑으로
// 내려가지 않는다. 라틴 대문자 키커만 면제이고 이 화면에는 그런 것이 없다.
const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.line },
  note: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 14, marginBottom: 2 },
  subNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: colors.line },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 16 },
  kicker: { fontSize: 15, fontWeight: '700', color: paper.dim },
  currentBank: { fontSize: 19, fontWeight: '800', color: paper.ink, marginTop: 4 },
  currentAccount: { fontSize: 16, lineHeight: 22, fontWeight: '700', color: paper.ink, marginTop: 3 },
  currentBroken: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.critical, marginTop: 3 },
  secTitle: { fontSize: 20, fontWeight: '800', color: paper.ink, marginTop: 22 },
  fieldLabel: { fontSize: 15, fontWeight: '700', color: paper.ink, marginTop: 16, marginBottom: 6 },
  bankWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  bankChip: { paddingHorizontal: 13, minHeight: 44, justifyContent: 'center', borderRadius: 12, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.line },
  bankChipOn: { backgroundColor: paper.action, borderColor: paper.action },
  bankChipLabel: { fontSize: 15, fontWeight: '700', color: paper.ink },
  bankChipLabelOn: { color: '#FFFFFF' },
  // the same explicit-token rule as the buttons, not an alpha (theme.ts:204)
  chipDisabled: { backgroundColor: paper.disabledFill, borderColor: paper.disabledFill },
  input: { fontSize: 17, color: paper.ink, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 14, minHeight: 52 },
  // DESIGN.md:203-206 button matrix, followed to the row rather than invented. The first draft
  // used a coral fill with radius 16 for Primary and `criticalWash` as the RESTING ground for
  // Destructive — which made 계좌 삭제 the same face as the failure strip below it (same wash, same
  // radius, same critical ink), so an ACTION and a FAILURE shared one grammar on a money screen.
  //   Primary     = paper.ink fill, no border, white 17/800, radius 0
  //   Destructive = canvas, 1px critical, critical 16/800, radius 0 (criticalWash is PRESSED only)
  // ⚠ The 3D lip (`borderBottomWidth: 4`, DESIGN.md:211-216) belongs to FILLED buttons, so Primary
  //   carries it and Destructive does not — 「Paper has no depth」 is that section's own sentence,
  //   and a lip plus a border would be two depth languages on one control.
  primary: {
    marginTop: 24, minHeight: 56, borderRadius: 0, backgroundColor: paper.ink,
    borderBottomWidth: 4, borderBottomColor: paper.inkPressed,
    alignItems: 'center', justifyContent: 'center',
  },
  primaryPressed: { transform: [{ translateY: 3 }], borderBottomWidth: 1 },
  primaryLabel: { fontSize: 17, fontWeight: '800', color: '#FFFFFF' },
  destructive: {
    marginTop: 12, minHeight: 52, borderRadius: 0, backgroundColor: colors.cream,
    borderWidth: 1, borderColor: paper.critical, alignItems: 'center', justifyContent: 'center',
  },
  destructivePressed: { backgroundColor: paper.criticalWash, transform: [{ scale: 0.96 }] },
  destructiveLabel: { fontSize: 16, fontWeight: '800', color: paper.critical },
  // DESIGN.md:218 — a disabled key has no travel, so the lip goes flat. And the colour is the
  // EXPLICIT disabled pair (`disabledFill` + `faint`), never an alpha: `theme.ts:204` calls that
  // token 「불투명도 트릭 금지 법의 물화」 — the no-opacity law made into a value. My first draft
  // wrote `opacity: 0.6` here, in a comment that forbade opacity tricks.
  flatDisabled: { borderBottomWidth: 1, backgroundColor: paper.disabledFill },
  flatDisabledLabel: { color: paper.faint },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginTop: 10 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
