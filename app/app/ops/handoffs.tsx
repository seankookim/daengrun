import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import { fetchOpsStalledHandoffs, OpsStalledHandoff } from '../../src/lib/api';
import { kstCal, kstClock, kstMonthDay } from '../../src/lib/kst';
import { goBackOrHome } from '../../src/lib/nav';
import { handoffAlertNote, handoffWaitingLabel, strandAgeLabel } from '../../src/lib/ops-console';
// RAW server text for the log only — `e.message` is the mapped Korean the screen renders.
import { rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 인계 확인 멈춤 — the list behind the 「인계 확인 멈춤 — 확인 필요」 bell. 0206 §B.
//
// 🔴 **THIS SCREEN IS A READ AND ONLY A READ, AND THAT IS A RULING RATHER THAN A GAP.** 0183 arm
//    ⓓ's own header: 「NO status move — what a stuck pickup handoff should BECOME is a product
//    decision (Sean's), not a clock's」. An 「운영 처리」 button here would be that same decision
//    taken by whoever wrote this screen. So there is no action, and the screen says what an
//    operator CAN do instead of drawing a control that would guess.
//    ⚠ The 0185 tools that already exist stay the tools. Nothing was removed to make this list.
//
// ⚠ **THE PENDING STATE IS THE REASON THIS LIST IS WORTH HAVING.** `handoff_escalated_at` set with
//   `handoff_ops_alerted_at` NULL is not missing information — it is 0183's durable PENDING: the
//   two parties were told while the ops roster was EMPTY, and arm ⓔ retries every tick. Drawn as a
//   blank it reads as 「the escalation failed」. `handoffAlertNote` says it in words.
//
// ⚠ `bid` (from a 「인계 확인 멈춤」 notification tap) MARKS the row the bell was about. The param is
//   read and has a visible effect — a param nothing reads is the defect 0193 codex A4 found in the
//   other direction, so it earns its place or it would not be passed.
// ⚠ Every date goes through `kst.ts` (fixed +9, no Intl — Korea has no DST).

type Phase = 'loading' | 'error' | 'ready';

export default function OpsStalledHandoffs() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ bid?: string }>();
  const highlightId = typeof params.bid === 'string' ? params.bid : '';

  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<OpsStalledHandoff[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(() => {
    setPhase('loading');
    setErr(null);
    fetchOpsStalledHandoffs()
      .then((r) => { setRows(r); setPhase('ready'); })
      .catch((e) => {
        console.warn('[ops/handoffs] load:', rpcRaw(e));
        setErr((e as Error)?.message || '멈춘 인계를 불러오지 못했어요');
        setPhase('error');
      });
  }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  // The tapped row may already be gone — the counterparty confirmed between the push and the tap.
  // That is an ordinary outcome and it is said, not hidden behind an unexplained highlight miss.
  const highlightMissing =
    phase === 'ready' && highlightId !== '' && !rows.some((r) => r.bookingId === highlightId);

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: colors.cream }}
        contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5 }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>인계 멈춤</Text>
          <View style={{ width: 40 }} />
        </Row>

        <Text style={s.lead}>
          한쪽만 인계를 확인한 채 멈춰 있는 예약이에요. 이 화면은 보기 전용이에요 — 멈춘 인계를
          어떻게 처리할지는 아직 정해진 규칙이 없어서, 양측에 직접 연락해 확인해주세요.
        </Text>

        {phase === 'loading' && <Text style={s.loading}>멈춘 인계를 불러오는 중이에요…</Text>}

        {phase === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failText}>{err ?? '불러오지 못했어요'}</Text>
            <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryLabel}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {highlightMissing && (
          <View style={s.noteCard}>
            <Text style={s.noteText}>알림이 가리킨 예약은 이미 목록에서 빠졌어요</Text>
            <Text style={s.noteSub}>상대방이 인계를 확인했거나 예약이 종료된 거예요</Text>
          </View>
        )}

        {phase === 'ready' && rows.length === 0 && !highlightMissing && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>멈춘 인계가 없어요</Text>
            <Text style={s.emptySub}>한쪽만 확인한 인계가 30분을 넘기면 여기에 나와요</Text>
          </View>
        )}

        {phase === 'ready' && rows.map((r) => {
          const age = strandAgeLabel(r.minutesStalled);
          const sched = r.scheduledAt === null ? null : kstCal(Date.parse(r.scheduledAt));
          const esc = r.escalatedAt === null ? null : kstCal(Date.parse(r.escalatedAt));
          const marked = r.bookingId === highlightId;
          return (
            <View key={r.bookingId} style={[s.row, marked && s.rowMarked]}>
              <Row style={{ justifyContent: 'flex-start', alignItems: 'baseline' }}>
                <Text style={s.rowTitle}>{r.dogName ?? '이름 없는 강아지'}</Text>
                {age !== null && <Text style={s.rowAge}>{age}</Text>}
                {marked && <Text style={s.marker}>알림</Text>}
              </Row>
              <Text style={s.rowState}>
                {handoffWaitingLabel(r.ownerStamped, r.runnerStamped, r.ownerName, r.runnerName)}
              </Text>
              <Text style={s.rowHint}>
                {sched !== null ? `${kstMonthDay(sched)} ${kstClock(sched)} 예정` : '예정 시각 없음'}
                {esc !== null ? ` · ${kstMonthDay(esc)} ${kstClock(esc)} 승격` : ''}
              </Text>
              {/* 0183's PENDING state, said in words rather than drawn as a blank. */}
              <Text style={r.opsAlertedAt === null ? s.rowPending : s.rowHint}>
                {handoffAlertNote(r.escalatedAt, r.opsAlertedAt)}
              </Text>
            </View>
          );
        })}
      </ScrollView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

// 15pt floor (DESIGN.md:145). No Korean below 15 here; the kicker exemption is latin-only.
const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.line },
  lead: { fontSize: 15.5, lineHeight: 22, color: paper.dim, marginTop: 14, marginBottom: 14 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 16 },
  row: {
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 15, paddingVertical: 14, marginBottom: 8,
  },
  rowMarked: { borderColor: paper.ink, borderWidth: 2 },
  rowTitle: { fontSize: 17, fontWeight: '800', color: paper.ink },
  rowAge: { fontSize: 15, fontWeight: '800', color: paper.critical, marginLeft: 8 },
  marker: { fontSize: 15, fontWeight: '800', color: paper.ink, marginLeft: 8 },
  rowState: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.ink, marginTop: 4 },
  rowHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  rowPending: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.critical, marginTop: 3 },
  noteCard: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 15, paddingVertical: 15, marginBottom: 12 },
  noteText: { fontSize: 16, fontWeight: '800', color: paper.ink },
  noteSub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  emptyCard: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 15, paddingVertical: 18 },
  emptyText: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginTop: 12 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
