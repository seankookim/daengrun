import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../../src/components/paper-btn';
import { StatusBarCover } from '../../../src/components/status-bar-cover';
import { Row, ScreenHead } from '../../../src/components/ui';
import {
  fetchOpsStrandedReturns, OpsStrandedReturn, opsResolveReturn,
} from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { kstCal, kstClock, kstMonthDay } from '../../../src/lib/kst';
import {
  memoRefusal, resolveOutcomeLabel, strandAgeLabel, strandNotifiedNote, strandStateLabel,
} from '../../../src/lib/ops-console';
// RAW server text for the log only; `e.message` is the sentence the screen renders — for this
// screen that sentence is the EDGE's own Korean (`resolve_return.ts` mapResolveError), passed
// through untouched by `invokeTransition`.
import { rpcRaw } from '../../../src/lib/rpc-error';
import { colors, paper } from '../../../src/theme';

// 반환 좌초 처리 — one stranded return, its facts, and the ops door out. 0206 §A + 0193 §C-b.
//
// 🔴 **THE ACTION IS THE ALREADY-DEPLOYED `resolve_return` EDGE ACTION.** Nothing about the server
//    changes for this screen to exist: 0193 §C-b built `ops_resolve_return_tx` (seal → settle →
//    one `return_resolutions` journal row) and 0201 §C moved the roster check ahead of the booking
//    read. What was missing was a caller. This is it.
//
// 🔴 **THE MEMO IS REQUIRED BY THE SERVER AND IS AN INTERNAL AUDIT NOTE.** `memo_required` is the
//    RPC's own refusal (0193:446); the local guard below restates it so the operator learns the
//    reason from the button rather than from a round trip, and the server enforces it regardless.
//    ⚠ It NEVER reaches a party's phone — 230 `0199-V5` pins that by value against a sentinel. The
//    parties see the fixed sentence `my_return_resolution` chooses from `rescued_from`. The screen
//    says so above the field, because an operator who believed the owner would read this would
//    write a different sentence.
//
// ⚠ **THERE IS NO `ops_stranded_return(id)` AND THIS SCREEN DOES NOT PRETEND OTHERWISE.** 0206 §A
//   ships one read — the LIST — so this screen reads it and picks its row out. That is honest and
//   it has a consequence worth stating: a booking that is no longer stranded (somebody resolved
//   it, or both parties finally confirmed) is simply NOT IN THE LIST, and the screen says
//   「목록에 없어요」 with a reason rather than an empty form. Adding a per-id read would be a second
//   ops surface for a fact the list already carries.
//
// ⚠ Refusals are the SERVER's sentences, rendered verbatim. `resolve_return.ts` maps every raise
//   to Korean (담당자만 · 메모 · 클럽 · 아직 안 끝남 · 이미 봉인 · 지금은 불가 · 정산 계산 실패 ·
//   종료 기록 불완전) and `invokeTransition` passes Korean through untouched. No second table here:
//   a copy would drift from the words the server actually chose.

type Phase = 'loading' | 'error' | 'missing' | 'ready' | 'done';

export default function OpsStrandedReturnDetail() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ bid?: string }>();
  const bookingId = typeof params.bid === 'string' ? params.bid : '';

  const [phase, setPhase] = useState<Phase>('loading');
  const [row, setRow] = useState<OpsStrandedReturn | null>(null);
  const [memo, setMemo] = useState('');
  const [saving, setSaving] = useState(false);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [formErr, setFormErr] = useState<string | null>(null);
  const [doneMsg, setDoneMsg] = useState<string | null>(null);

  const load = useCallback(() => {
    if (bookingId === '') { setLoadErr('예약을 찾을 수 없어요'); setPhase('error'); return; }
    setPhase('loading');
    setLoadErr(null);
    fetchOpsStrandedReturns()
      .then((rows) => {
        const found = rows.find((r) => r.bookingId === bookingId) ?? null;
        setRow(found);
        setPhase(found === null ? 'missing' : 'ready');
      })
      .catch((e) => {
        console.warn('[ops/returns/bid] load:', rpcRaw(e));
        setLoadErr((e as Error)?.message || '좌초된 반환을 불러오지 못했어요');
        setPhase('error');
      });
  }, [bookingId]);
  useEffect(() => { load(); }, [load]);

  const submit = useCallback(() => {
    if (saving || row === null) return;
    // The server's rule restated locally. It enforces `memo_required` regardless.
    const refusal = memoRefusal(memo);
    if (refusal !== null) { setFormErr(refusal); haptic('light'); return; }

    Alert.alert(
      '반환을 정리할까요?',
      `${row.dogName ?? '이 강아지'}의 반환을 담당자 판정으로 마감하고 정산을 진행해요.\n되돌릴 수 없어요 · 적은 메모는 감사 기록으로 남아요`,
      [
        { text: '취소', style: 'cancel' },
        {
          text: '처리',
          onPress: () => {
            setFormErr(null);
            setDoneMsg(null);
            setSaving(true);
            opsResolveReturn(bookingId, memo.trim())
              .then((res) => {
                // The row must leave the list because the SERVER says it is gone, not because this
                // screen assumed the write did what it asked for (0194's 「draw what the server
                // kept」, same law). So: say what happened, then RE-FETCH.
                setDoneMsg(resolveOutcomeLabel(res));
                setMemo('');
                setPhase('done');
              })
              .catch((e) => {
                console.warn('[ops/returns/bid] resolve:', rpcRaw(e));
                setFormErr((e as Error)?.message || '반환을 정리하지 못했어요');
              })
              .finally(() => setSaving(false));
          },
        },
      ],
    );
  }, [bookingId, memo, row, saving]);

  const age = row === null ? null : strandAgeLabel(row.minutesStranded);
  const ended = row?.runEndedAt == null ? null : kstCal(Date.parse(row.runEndedAt));
  const belled = row?.notifiedAt == null ? null : kstCal(Date.parse(row.notifiedAt));

  return (
    <>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView
          style={{ flex: 1, backgroundColor: colors.cream }}
          contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
          keyboardShouldPersistTaps="handled"
        >
          <ScreenHead title="반환 정리" />

          {phase === 'loading' && <Text style={s.loading}>예약을 불러오는 중이에요…</Text>}

          {phase === 'error' && (
            <View style={s.failStrip}>
              <Text style={s.failText}>{loadErr ?? '불러오지 못했어요'}</Text>
              <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
                <Text style={s.retryLabel}>다시 시도</Text>
              </Pressable>
            </View>
          )}

          {phase === 'missing' && (
            <View style={[s.card, { marginTop: 16, paddingVertical: 18 }]}>
              <Text style={s.emptyText}>목록에 없어요</Text>
              <Text style={s.emptySub}>
                이미 정리됐거나 양측이 반환을 확인해서 좌초 목록에서 빠진 예약이에요.
              </Text>
              <Pressable
                onPress={() => router.replace('/ops/returns')}
                accessibilityRole="button"
                style={({ pressed }) => [s.secondary, pressed && s.secondaryPressed]}
              >
                <Text style={s.secondaryLabel}>좌초 목록으로</Text>
              </Pressable>
            </View>
          )}

          {phase === 'done' && (
            <>
              <View style={s.doneStrip}>
                <Text style={s.doneText}>{doneMsg}</Text>
                <Text style={s.doneSub}>판정 기록이 저장됐어요 · 좌초 목록에서 빠져요</Text>
              </View>
              <PaperBtn label="좌초 목록으로" onPress={() => router.replace('/ops/returns')} style={s.cta} />
            </>
          )}

          {phase === 'ready' && row !== null && (
            <>
              {/* ── 사실 ─────────────────────────────────────────────────────────────── */}
              <View style={[s.card, { marginTop: 16, paddingVertical: 15 }]}>
                <Text style={s.kicker}>이 예약</Text>
                <Text style={s.dogName}>{row.dogName ?? '이름 없는 강아지'}</Text>
                <Text style={s.state}>
                  {strandStateLabel(row.rawStatus, row.runnerStamped, row.ownerStamped)}
                </Text>

                <View style={s.rule} />

                <Fact label="보호자" value={row.ownerName ?? '이름 없음'} />
                <Fact
                  label="보호자 반환 확인"
                  value={row.ownerStamped ? '확인함' : '확인 없음'}
                  tone={row.ownerStamped ? 'ok' : 'warn'}
                />
                <Fact label="러너" value={row.runnerName ?? '이름 없음'} />
                <Fact
                  label="러너 반환 확인"
                  value={row.runnerStamped ? '확인함' : '확인 없음'}
                  tone={row.runnerStamped ? 'ok' : 'warn'}
                />
                <Fact
                  label="러닝 종료"
                  value={ended === null ? '기록 없음' : `${kstMonthDay(ended)} ${kstClock(ended)}`}
                />
                <Fact label="좌초 경과" value={age ?? '알 수 없음'} tone="warn" />
                <Fact
                  label="담당자 알림"
                  value={belled === null ? '아직' : `${kstMonthDay(belled)} ${kstClock(belled)}`}
                />
                {row.notifiedAt === null && (
                  <Text style={s.pendingNote}>{strandNotifiedNote(row.notifiedAt)}</Text>
                )}
              </View>

              {/* ── 메모 ─────────────────────────────────────────────────────────────── */}
              <Text style={s.fieldLabel}>무엇을 확인했나요</Text>
              <Text style={s.fieldHint}>
                보호자·러너와 무엇을 확인했는지 적어주세요. 이 메모는 감사 기록으로만 남고
                보호자와 러너에게는 보이지 않아요.
              </Text>
              <TextInput
                style={[s.input, s.memoInput]}
                value={memo}
                onChangeText={(t) => { setMemo(t); setFormErr(null); }}
                placeholder="예: 보호자와 통화 — 강아지는 집에 있고 러너가 19:40에 인계 완료"
                placeholderTextColor={paper.faint}
                multiline
                editable={!saving}
                accessibilityLabel="판정 메모"
              />

              {formErr !== null && (
                <View style={s.failStrip}><Text style={s.failText}>{formErr}</Text></View>
              )}

              <PaperBtn label="운영 처리" busyLabel="처리 중…" busy={saving} onPress={submit} style={s.cta} />
              <Text style={s.warnNote}>
                반환을 봉인하고 정산까지 진행해요 · 되돌릴 수 없어요
              </Text>
            </>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

function Fact({ label, value, tone }: { label: string; value: string; tone?: 'ok' | 'warn' }) {
  return (
    <Row style={{ justifyContent: 'space-between', alignItems: 'baseline', marginTop: 9 }}>
      <Text style={s.factLabel}>{label}</Text>
      <Text style={[s.factValue, tone === 'warn' && s.factWarn, tone === 'ok' && s.factOk]}>{value}</Text>
    </Row>
  );
}

// 15pt floor (DESIGN.md:145). No Korean below 15 here; the kicker exemption is latin-only.
const s = StyleSheet.create({
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: colors.line },
  kicker: { fontSize: 15, fontWeight: '700', color: paper.dim },
  dogName: { fontSize: 19, fontWeight: '800', color: paper.ink, marginTop: 4 },
  state: { fontSize: 15.5, lineHeight: 22, fontWeight: '700', color: paper.ink, marginTop: 6 },
  rule: { height: 1, backgroundColor: colors.line, marginTop: 14 },
  factLabel: { fontSize: 15, color: paper.dim },
  factValue: { fontSize: 16, fontWeight: '800', color: paper.ink },
  factWarn: { color: paper.critical },
  factOk: { color: paper.ink },
  pendingNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 10 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 16 },
  fieldLabel: { fontSize: 15, fontWeight: '700', color: paper.ink, marginTop: 22, marginBottom: 4 },
  fieldHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginBottom: 8 },
  input: { fontSize: 17, color: paper.ink, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 14, minHeight: 52 },
  memoInput: { minHeight: 110, paddingTop: 13, paddingBottom: 13, textAlignVertical: 'top' },
  warnNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 8 },
  // Layout only — PaperBtn owns the fill (coral primary, DESIGN.md §3b), the lip and the busy swap.
  cta: { marginTop: 20 },
  secondary: {
    marginTop: 14, minHeight: 48, borderRadius: 0, backgroundColor: colors.cream,
    borderWidth: 1, borderColor: paper.ink, alignItems: 'center', justifyContent: 'center',
  },
  secondaryPressed: { backgroundColor: paper.disabledFill, transform: [{ scale: 0.97 }] },
  secondaryLabel: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptyText: { fontSize: 17, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 5 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginTop: 12 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  doneStrip: { backgroundColor: '#EDF4EE', borderRadius: 16, padding: 15, marginTop: 16 },
  doneText: { fontSize: 17, fontWeight: '900', color: paper.ink },
  doneSub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 5 },
});
