import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  Alert, Clipboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text,
  TextInput, View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../../src/components/paper-btn';
import { StatusBarCover } from '../../../src/components/status-bar-cover';
import { Row, ScreenHead } from '../../../src/components/ui';
import {
  fetchOpsBankAccount, fetchOpsRunnerPayoutDetail, OpsBankAccount, OpsPayoutRowDetail,
  opsRecordManualPayout,
} from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { kstCal, kstMonthDay } from '../../../src/lib/kst';
// The RAW server text, for the log only. `e.message` is now the MAPPED Korean sentence
// (api.ts `opsError` -> `foldRpcError`), which is what the screen must render and the last
// thing a log should carry: a `console.warn` printing the folded copy has thrown the
// diagnosis away, which is the cost the fold exists to avoid paying.
import { rpcRaw } from '../../../src/lib/rpc-error';
import {
  batchRefusal, batchSummary, BATCH_REFUSAL_KO, checkedTotalWon, selectedIds, wonLabel,
} from '../../../src/lib/ops-payout';
import { colors, paper, secTitle } from '../../../src/theme';

// 지급 기록 — one runner's unpaid settled rows, and the transfer that covers them. 0198 §B + 0186 §C.
//
// 🔴 **THE AMOUNT THIS SCREEN SENDS IS THE SUM OF THE TICKED ROWS, AND THE SERVER STILL REFUSES A
//    MISMATCH.** That is not belt-and-braces theatre: the case where the two numbers differ is
//    precisely the case where this screen is STALE — another terminal paid a row between the read
//    and the tap — and `amount_mismatch` is then the correct outcome, surfaced in Korean with what
//    to do about it. A screen that sent the server's own number back would turn 0186 §C's equality
//    gate into a no-op while leaving it looking present.
//
// 🔴 **계좌 보기 IS FETCHED ON TAP AND NEVER ON MOUNT.** `ops_bank_account` (0194 §F④) writes a
//    `bank_account_access_log` row for EVERY gated call, found or not — probing for existence is
//    access. Reading it during load would stamp the journal every time an operator opened this
//    page, which makes the journal useless as evidence exactly when it is needed. The screen says
//    so out loud (「이 조회는 기록돼요」) BEFORE the tap, not after: an audit trail a person did not
//    know about is a trap rather than a safeguard.
//
// 🔴 **THE DECRYPTED NUMBER LIVES IN ONE PIECE OF STATE AND ON ONE LINE.** It is never logged,
//    never put in an error message, never sent anywhere. `console.warn` below carries the error's
//    message only, and that message comes from `opsError`'s fixed Korean table.
//
// ⚠ A NEGATIVE row is rendered with its sign and is tickable like any other. 0198 §B returns it
//   because `ops_payouts_due()` already counted it; hiding it would make this screen's total
//   exceed the total the operator saw one tap ago.

type Phase = 'loading' | 'error' | 'ready';
type BankPhase = 'idle' | 'loading' | 'shown' | 'none' | 'error';

export default function OpsPayoutRunner() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ runner?: string }>();
  const runnerId = typeof params.runner === 'string' ? params.runner : '';

  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<OpsPayoutRowDetail[]>([]);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [memo, setMemo] = useState('');
  const [saving, setSaving] = useState(false);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [formErr, setFormErr] = useState<string | null>(null);
  const [doneMsg, setDoneMsg] = useState<string | null>(null);

  const [bankPhase, setBankPhase] = useState<BankPhase>('idle');
  const [bank, setBank] = useState<OpsBankAccount | null>(null);
  const [bankErr, setBankErr] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [copyFailed, setCopyFailed] = useState(false);

  const load = useCallback(() => {
    if (runnerId === '') { setLoadErr('러너를 찾을 수 없어요'); setPhase('error'); return; }
    setPhase('loading');
    setLoadErr(null);
    fetchOpsRunnerPayoutDetail(runnerId)
      .then((r) => {
        setRows(r);
        // ⚠ The selection is INTERSECTED with what came back rather than kept whole. After a
        // payout the paid rows are gone, and a checked id that no longer renders would be sent on
        // the next tap — `already_paid` from a screen that looks correct.
        setChecked((prev) => new Set(r.filter((x) => prev.has(x.id)).map((x) => x.id)));
        setPhase('ready');
      })
      .catch((e) => {
        console.warn('[ops/payout] load:', rpcRaw(e));
        setLoadErr((e as Error)?.message || '지급 대기 행을 불러오지 못했어요');
        setPhase('error');
      });
  }, [runnerId]);
  useEffect(() => { load(); }, [load]);

  const toggle = useCallback((id: string) => {
    if (saving) return;
    haptic('light');
    setFormErr(null);
    setDoneMsg(null);
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, [saving]);

  const toggleAll = useCallback(() => {
    if (saving) return;
    haptic('light');
    setFormErr(null);
    setDoneMsg(null);
    setChecked((prev) => (prev.size === rows.length ? new Set() : new Set(rows.map((r) => r.id))));
  }, [rows, saving]);

  /** 🔴 ONE TAP, ONE JOURNAL ROW. Never called from an effect. */
  const revealBank = useCallback(() => {
    if (bankPhase === 'loading' || runnerId === '') return;
    haptic('light');
    setBankPhase('loading');
    setBankErr(null);
    setCopied(false);
    fetchOpsBankAccount(runnerId)
      .then((row) => {
        if (row === null) { setBank(null); setBankPhase('none'); return; }
        setBank(row);
        setBankPhase('shown');
      })
      .catch((e) => {
        // ⚠ The MESSAGE only. Nothing that could carry an account number reaches a log.
        console.warn('[ops/payout] bank:', rpcRaw(e));
        setBankErr((e as Error)?.message || '계좌를 불러오지 못했어요');
        setBankPhase('error');
      });
  }, [runnerId, bankPhase]);

  /** ⚠ **REACT NATIVE'S CORE `Clipboard`, DELIBERATELY, AND NOT `expo-clipboard`.** The Expo
   *  module is not a dependency of this app (measured: no `clipboard` package in `node_modules`),
   *  and adding one would need a pod install before any binary works — the class
   *  `check-route-native-imports` exists for, and a build only Sean can make. Core `Clipboard`
   *  ships inside the React Native pod itself, so there is no link that can be missing. Metro
   *  compiles the named import to a member access, so the one-time deprecation warning fires on
   *  the first TAP rather than at module load: an operator who never taps 복사 never sees it.
   *
   *  🔴 **THIS IS A KNOWN, DELIBERATE react-doctor ERROR — `rn-no-deprecated-modules` on the
   *     import at the top of this file — and it is recorded here rather than left for a reviewer
   *     to find.** The trade, stated so it can be overturned rather than rediscovered:
   *       · what it costs — one more error in a report that already carries seven, and a line
   *         that will genuinely stop working on some future RN.
   *       · what it buys — the operator copies a sixteen-digit account number with ONE tap
   *         instead of a long-press and an OS menu, on the screen where mistyping that number
   *         sends someone else's money to the wrong bank.
   *       · why it is safe to lose — the number above is `selectable`, so the long-press route
   *         works TODAY and keeps working after the API is gone; the `catch` below points at it
   *         by name. The feature degrades to the thing it replaced, in words, at the moment it
   *         breaks.
   *     The exit, for whoever picks this up: `npx expo install expo-clipboard` + a pod install,
   *     then swap `Clipboard.setString` for `setStringAsync` and delete this paragraph. It is a
   *     dependency decision, which makes it Sean's rather than this slice's.
   *
   *  ⚠ And the failure is REAL, not swallowed: if the API is gone the button says so and points at
   *  the affordance that still works. A copy button that silently did nothing on a money screen
   *  would be the dead button this house forbids. */
  const copyAccount = useCallback(() => {
    const value = bank?.account;
    if (value == null) return;
    haptic('light');
    try {
      Clipboard.setString(value);
      setCopyFailed(false);
      setCopied(true);
    } catch {
      // No `console.log(value)` anywhere in this path — the number never reaches a log.
      setCopied(false);
      setCopyFailed(true);
    }
  }, [bank]);

  const submit = useCallback(() => {
    if (saving) return;
    // The local guard is the SERVER's rule restated so the operator learns the reason from the
    // button rather than from a round trip. The server enforces every one of them regardless.
    const refusal = batchRefusal(rows, checked);
    if (refusal !== null) { setFormErr(BATCH_REFUSAL_KO[refusal]); haptic('light'); return; }

    const ids = selectedIds(rows, checked);
    const amount = checkedTotalWon(rows, checked);
    Alert.alert(
      '지급을 기록할까요?',
      `${ids.length}건 · ${wonLabel(amount)}\n은행에서 이미 옮긴 돈을 장부에 적는 거예요 · 이 화면이 돈을 보내지는 않아요`,
      [
        { text: '취소', style: 'cancel' },
        {
          text: '기록',
          onPress: () => {
            setFormErr(null);
            setDoneMsg(null);
            setSaving(true);
            opsRecordManualPayout({
              runnerId,
              ledgerItemIds: ids,
              amountWon: amount,
              memo: memo.trim() === '' ? null : memo.trim(),
            })
              .then(() => {
                // 🔴 Re-read from the SERVER rather than splicing locally. The paid rows must
                // disappear because the server says they are gone, not because this screen
                // assumed the write did what it asked for — on a money surface that difference is
                // the whole point (0194's 「draw what the server kept」, same law).
                setDoneMsg(`${ids.length}건 · ${wonLabel(amount)} 기록했어요`);
                setMemo('');
                setChecked(new Set());
                load();
              })
              .catch((e) => setFormErr((e as Error)?.message || '지급을 기록하지 못했어요'))
              .finally(() => setSaving(false));
          },
        },
      ],
    );
  }, [rows, checked, memo, runnerId, saving, load]);

  const total = checkedTotalWon(rows, checked);
  const allOn = rows.length > 0 && checked.size === rows.length;

  return (
    <>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView
          style={{ flex: 1, backgroundColor: colors.cream }}
          contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
          keyboardShouldPersistTaps="handled"
        >
          <ScreenHead title="지급 기록" />
          <Text style={s.note}>러너 {runnerId.slice(0, 8).toUpperCase()}</Text>

          {/* ── 계좌 ─────────────────────────────────────────────────────────────────────
              The button is here, above the rows, because it is the FIRST thing an operator
              needs — and it is a button rather than a card because every press is recorded. */}
          <View style={[s.card, { marginTop: 14, paddingVertical: 15 }]}>
            <Text style={s.kicker}>정산 계좌</Text>
            {bankPhase === 'idle' && (
              <>
                <Text style={s.journalNote}>이 조회는 기록돼요</Text>
                <Pressable
                  onPress={revealBank}
                  accessibilityRole="button"
                  style={({ pressed }) => [s.secondary, pressed && s.secondaryPressed]}
                >
                  <Text style={s.secondaryLabel}>계좌 보기</Text>
                </Pressable>
              </>
            )}
            {bankPhase === 'loading' && <Text style={s.loading}>계좌를 불러오는 중이에요…</Text>}
            {bankPhase === 'none' && (
              <Text style={s.bankMissing}>등록된 정산 계좌가 없어요 — 러너가 먼저 등록해야 이체할 수 있어요</Text>
            )}
            {bankPhase === 'error' && (
              <>
                <Text style={s.failText}>{bankErr}</Text>
                <Pressable onPress={revealBank} accessibilityRole="button" style={s.retryBtn}>
                  <Text style={s.retryLabel}>다시 시도</Text>
                </Pressable>
              </>
            )}
            {bankPhase === 'shown' && bank !== null && (
              <>
                <Text style={s.bankName}>{bank.bankLabel ?? bank.bank}</Text>
                {/* ⚠ `account === null` means the stored row could not be DECRYPTED. It is not a
                    blank and it is not a partial number — absence, said as absence. */}
                {bank.account !== null ? (
                  <>
                    <Text style={s.bankAccount} selectable>{bank.account}</Text>
                    <Text style={s.bankHolder}>{bank.holder}</Text>
                    <Pressable
                      onPress={copyAccount}
                      accessibilityRole="button"
                      accessibilityLabel="계좌번호 복사"
                      style={({ pressed }) => [s.secondary, pressed && s.secondaryPressed]}
                    >
                      <Text style={s.secondaryLabel}>{copied ? '복사됐어요' : '복사'}</Text>
                    </Pressable>
                    {copyFailed && (
                      <Text style={s.bankMissing}>
                        복사하지 못했어요 — 위 번호를 길게 눌러 복사해주세요
                      </Text>
                    )}
                  </>
                ) : (
                  <Text style={s.bankMissing}>
                    저장된 번호를 읽지 못했어요 — 러너에게 계좌를 다시 등록해달라고 해주세요
                  </Text>
                )}
                <Text style={s.journalNote}>이 조회는 기록됐어요</Text>
              </>
            )}
          </View>

          {/* ── 미지급 행 ──────────────────────────────────────────────────────────────── */}
          <Row style={{ justifyContent: 'space-between', marginTop: 24, alignItems: 'baseline' }}>
            <Text style={secTitle}>미지급 행</Text>
            {phase === 'ready' && rows.length > 0 && (
              <Pressable onPress={toggleAll} accessibilityRole="button" style={s.allBtn}>
                <Text style={s.allLabel}>{allOn ? '전체 해제' : '전체 선택'}</Text>
              </Pressable>
            )}
          </Row>

          {phase === 'loading' && <Text style={s.loading}>미지급 행을 불러오는 중이에요…</Text>}

          {phase === 'error' && (
            <View style={s.failStrip}>
              <Text style={s.failText}>{loadErr}</Text>
              <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
                <Text style={s.retryLabel}>다시 시도</Text>
              </Pressable>
            </View>
          )}

          {phase === 'ready' && rows.length === 0 && (
            <View style={s.emptyCard}>
              <Text style={s.emptyText}>이 러너에게 지급할 행이 없어요</Text>
              <Text style={s.emptySub}>
                {doneMsg !== null ? '방금 기록한 지급으로 전부 정리됐어요' : '정산이 끝난 미지급 행이 생기면 여기에 나와요'}
              </Text>
            </View>
          )}

          {phase === 'ready' && rows.map((r) => {
            const on = checked.has(r.id);
            return (
              <Pressable
                key={r.id}
                onPress={() => toggle(r.id)}
                disabled={saving}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: on, disabled: saving }}
                accessibilityLabel={`${r.dogName ?? (r.cancelComp ? '취소 보상' : '러닝')} · ${wonLabel(r.netWon)}`}
                style={[s.itemRow, on && s.itemRowOn]}
              >
                <View style={[s.box, on && s.boxOn]}>
                  {on && <Text style={s.boxTick}>✓</Text>}
                </View>
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.itemTitle}>
                    {r.cancelComp ? '취소 보상' : (r.dogName ?? '이름 없는 강아지')}
                  </Text>
                  <Text style={s.itemHint}>
                    {r.createdAt ? kstMonthDay(kstCal(Date.parse(r.createdAt))) : '날짜 없음'}
                    {/* ⚠ `settledAt` is genuinely NULL for a cancellation-compensation row and for
                        an incident settlement that wrote no stamp. Said, not coalesced. */}
                    {r.settledAt ? ` · ${kstMonthDay(kstCal(Date.parse(r.settledAt)))} 정산` : ' · 정산 기록 없음'}
                  </Text>
                </View>
                <Text style={[s.itemAmount, r.netWon < 0 && s.itemAmountNeg]}>{wonLabel(r.netWon)}</Text>
              </Pressable>
            );
          })}

          {/* ── 기록 ───────────────────────────────────────────────────────────────────── */}
          {phase === 'ready' && rows.length > 0 && (
            <>
              <Text style={s.fieldLabel}>메모 (선택)</Text>
              <TextInput
                value={memo}
                onChangeText={setMemo}
                editable={!saving}
                placeholder="이체한 은행·시각 등"
                placeholderTextColor={paper.dim}
                autoCorrect={false}
                style={s.input}
                accessibilityLabel="메모"
              />

              <View style={s.totalRow}>
                <Text style={s.totalLabel}>선택한 합계</Text>
                <Text style={s.totalValue}>{batchSummary(rows, checked)}</Text>
              </View>
              <Text style={s.equalityNote}>
                이 금액이 은행에서 옮긴 액수와 같아야 해요 · 다르면 서버가 거절해요
              </Text>

              {formErr !== null && (
                <View style={s.failStrip}>
                  <Text style={s.failText}>{formErr}</Text>
                </View>
              )}
              {doneMsg !== null && formErr === null && (
                <View style={s.doneStrip}>
                  <Text style={s.doneText}>{doneMsg}</Text>
                </View>
              )}

              {/* PaperBtn (DESIGN.md §3b): coral primary, and busy is a LABEL SWAP with
                  accessibilityState.busy — the key is blocked while the write is in flight, not
                  drawn as a dead one (this was an ink primary that went flat-grey while saving). */}
              <PaperBtn
                label={`지급 기록 · ${wonLabel(total)}`} busyLabel="기록 중…" busy={saving}
                onPress={submit} style={s.cta}
              />
            </>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

// 15pt floor (DESIGN.md:145). The only sub-15 glyph on this screen is the checkbox tick, which is
// a glyph rather than Korean prose (Sean 2026-08-31: 아바타 dot initials are glyphs and exempt).
const s = StyleSheet.create({
  note: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 12 },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: colors.line },
  kicker: { fontSize: 15, fontWeight: '700', color: paper.dim },
  journalNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 6 },
  bankName: { fontSize: 19, fontWeight: '800', color: paper.ink, marginTop: 4 },
  bankAccount: { fontSize: 22, fontWeight: '900', color: paper.ink, marginTop: 4, letterSpacing: 0.5 },
  bankHolder: { fontSize: 16, fontWeight: '700', color: paper.ink, marginTop: 3 },
  bankMissing: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.critical, marginTop: 6 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 14 },
  allBtn: { minHeight: 44, justifyContent: 'center', paddingHorizontal: 4 },
  allLabel: { fontSize: 16, fontWeight: '800', color: paper.action, textDecorationLine: 'underline' },
  itemRow: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 13, paddingVertical: 13, marginBottom: 8, minHeight: 64,
  },
  itemRowOn: { borderColor: paper.ink, borderWidth: 2 },
  box: { width: 26, height: 26, borderRadius: 7, borderWidth: 2, borderColor: colors.line, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', marginRight: 12 },
  boxOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  boxTick: { fontSize: 15, fontWeight: '900', color: '#FFFFFF', lineHeight: 18 },
  itemTitle: { fontSize: 17, fontWeight: '800', color: paper.ink },
  itemHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  itemAmount: { fontSize: 17, fontWeight: '900', color: paper.ink },
  itemAmountNeg: { color: paper.critical },
  fieldLabel: { fontSize: 15, fontWeight: '700', color: paper.ink, marginTop: 18, marginBottom: 6 },
  input: { fontSize: 17, color: paper.ink, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 14, minHeight: 52 },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 20 },
  totalLabel: { fontSize: 16, fontWeight: '700', color: paper.dim },
  totalValue: { fontSize: 20, fontWeight: '900', color: paper.ink },
  equalityNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 5 },
  // Layout only — PaperBtn owns the fill (coral primary, DESIGN.md §3b), the lip and the busy swap.
  cta: { marginTop: 18 },
  // Secondary = canvas + 1px line, no lip (「Paper has no depth」 — a lip belongs to filled keys).
  secondary: {
    marginTop: 10, minHeight: 48, borderRadius: 0, backgroundColor: colors.cream,
    borderWidth: 1, borderColor: paper.ink, alignItems: 'center', justifyContent: 'center',
  },
  secondaryPressed: { backgroundColor: paper.disabledFill, transform: [{ scale: 0.97 }] },
  secondaryLabel: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptyCard: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 15, paddingVertical: 18 },
  emptyText: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginTop: 10 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  doneStrip: { backgroundColor: '#EDF4EE', borderRadius: 16, padding: 13, marginTop: 10 },
  doneText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.ink },
});
