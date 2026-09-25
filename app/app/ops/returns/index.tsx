import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../../src/components/status-bar-cover';
import { Row, ScreenHead } from '../../../src/components/ui';
import { fetchOpsStrandedReturns, OpsStrandedReturn } from '../../../src/lib/api';
import { kstCal, kstMonthDay, kstClock } from '../../../src/lib/kst';
import {
  STRAND_EMPTY_UNKNOWN_KO,
  strandAgeLabel, strandDeadlineFrom, strandDeadlineNote, strandNotifiedNote, strandStateLabel,
} from '../../../src/lib/ops-console';
// RAW server text for the log only — `e.message` is the mapped Korean the screen renders
// (api.ts `opsError` → `foldRpcError`). Same import and same reason as `ops/payout/[runner].tsx`.
import { rpcRaw } from '../../../src/lib/rpc-error';
import { colors, paper } from '../../../src/theme';

// 반환 좌초 — the list behind the 「반환 좌초 — 확인 필요」 bell. 0206 §A.
//
// 🔴 **THIS SCREEN IS THE REASON THE BELL STOPPED BEING A SUMMONS TO A PSQL PROMPT.** `resolve_return`
//    (0193 §C-b, hardened by 0201 §C) has been deployed and callable the whole time and had ZERO
//    callers in `app/`; the sweep's arm ⓕ rang, and the only way to act was hand-typed SQL against
//    production — the exact shape 0198 §0 removed one desk over.
//
// ⚠ FOUR STATES, none of them a blank: 'loading' says so in words (loading is not 0 and it is not
//   an empty list), 'error' is a loud strip with 다시 시도, 'empty' says the queue is genuinely
//   empty, and 'rows' draws them.
// ⚠ **THE EMPTY STATE IS NOT ALWAYS GOOD NEWS AND THIS SCREEN SAYS SO.** When
//   `ops_flags.return_strand_minutes` is NULL — the SHIPPED value — the sweep's arm is inert and
//   nothing new is ever belled. An operator reading an empty list as 「nothing is stranded」 would
//   be wrong in exactly the situation where being wrong costs a runner their pay, so
//   `strandDeadlineNote` prints the off-switch sentence whenever the server reports NULL **on a
//   row** — amended 2026-09-25; the unqualified version of that sentence is what produced the
//   defect directly below.
// 🔴 **AND 「THE SERVER REPORTED NULL」 IS NOT 「WE DID NOT ASK」 — codex #3, 2026-09-25.** The
//   threshold rides on ROWS (0206 §A has nowhere else to put it), so an empty successful response
//   carries no threshold at all: an ENABLED deadline with nothing stranded and a switched-OFF arm
//   produce the identical empty payload. This screen used to hand that empty case a `null` and
//   print the off-switch sentence from it — a configuration claim about production that nothing
//   had measured, shown to the one reader who would act on it. The deadline is now a THREE-state
//   (`unknown | off | minutes`, `strandDeadlineFrom`), `unknown` prints no claim at all, and the
//   empty card says in words that the setting cannot be read from an empty list. Reading the flag
//   independently would need a new ops-gated RPC — no shipped one returns it (measured across
//   every migration on trunk) — and that is a server slice, not this one.
// ⚠ Every date goes through `kst.ts` (fixed +9, no Intl — Korea has no DST). `check-device-clock`
//   refuses a device-clock read for a KST fact and this screen has none.

type Phase = 'loading' | 'error' | 'ready';

export default function OpsStrandedReturns() {
  const insets = useSafeAreaInsets();
  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<OpsStrandedReturn[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(() => {
    setPhase('loading');
    setErr(null);
    fetchOpsStrandedReturns()
      .then((r) => { setRows(r); setPhase('ready'); })
      .catch((e) => {
        console.warn('[ops/returns] load:', rpcRaw(e));
        setErr((e as Error)?.message || '좌초된 반환을 불러오지 못했어요');
        setPhase('error');
      });
  }, []);

  // Re-read on every return: resolving one on the detail screen changes exactly this list, and a
  // stale row here is an operator opening a booking somebody already settled.
  useFocusEffect(useCallback(() => { load(); }, [load]));

  // The deadline is a property of the SERVER carried on ROWS, so an empty list is `unknown` and
  // never `off`. `strandDeadlineNote` returns null for `unknown` and the line is omitted.
  const deadline = strandDeadlineFrom(rows);
  const deadlineNote = phase === 'ready' ? strandDeadlineNote(deadline) : null;

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: colors.cream }}
        contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
      >
        <ScreenHead title="반환 좌초" />

        <Text style={s.lead}>
          러닝은 끝났는데 반환 확인이 끝나지 않아 러너가 정산을 받지 못하는 예약이에요.
        </Text>

        {phase === 'loading' && <Text style={s.loading}>좌초된 반환을 불러오는 중이에요…</Text>}

        {phase === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failText}>{err ?? '불러오지 못했어요'}</Text>
            <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryLabel}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {deadlineNote !== null && (
          <Text style={s.deadlineNote}>{deadlineNote}</Text>
        )}

        {phase === 'ready' && rows.length === 0 && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>좌초된 반환이 없어요</Text>
            <Text style={s.emptySub}>
              러닝이 끝나고 반환 확인이 마감 시간을 넘기면 여기에 나와요
            </Text>
            {/* What this list CANNOT tell the operator, said rather than left to an inference —
                the empty payload is identical whether the arm is armed or switched off. */}
            <Text style={s.emptyUnknown}>{STRAND_EMPTY_UNKNOWN_KO}</Text>
          </View>
        )}

        {phase === 'ready' && rows.map((r) => {
          const age = strandAgeLabel(r.minutesStranded);
          const ended = r.runEndedAt === null ? null : kstCal(Date.parse(r.runEndedAt));
          return (
            <Pressable
              key={r.bookingId}
              onPress={() => router.push(`/ops/returns/${r.bookingId}`)}
              accessibilityRole="button"
              accessibilityLabel={`${r.dogName ?? '이름 없는 강아지'} · ${age ?? '경과 시간 미상'}`}
              style={({ pressed }) => [s.row, pressed && s.rowPressed]}
            >
              <View style={{ flex: 1, paddingRight: 10 }}>
                <Row style={{ justifyContent: 'flex-start', alignItems: 'baseline' }}>
                  {/* A dog with no name is said as such — never a blank and never a made-up name. */}
                  <Text style={s.rowTitle}>{r.dogName ?? '이름 없는 강아지'}</Text>
                  {age !== null && <Text style={s.rowAge}>{age}</Text>}
                </Row>
                {/* Gate on rawStatus, print the mapped sentence — the standing STATUS_MAP law. */}
                <Text style={s.rowState}>
                  {strandStateLabel(r.rawStatus, r.runnerStamped, r.ownerStamped)}
                </Text>
                <Text style={s.rowHint}>
                  {r.ownerName ?? '보호자'} · {r.runnerName ?? '러너'}
                  {ended !== null ? ` · ${kstMonthDay(ended)} ${kstClock(ended)} 종료` : ''}
                </Text>
                {/* Not yet belled is a real and different state from belled — said in words. */}
                {r.notifiedAt === null && (
                  <Text style={s.rowPending}>{strandNotifiedNote(r.notifiedAt)}</Text>
                )}
              </View>
              <Text style={s.chev}>›</Text>
            </Pressable>
          );
        })}
      </ScrollView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

// 15pt floor (DESIGN.md:145). No Korean below 15 here; the kicker exemption is latin-only.
const s = StyleSheet.create({
  lead: { fontSize: 15.5, lineHeight: 22, color: paper.dim, marginTop: 14 },
  deadlineNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 10, marginBottom: 12 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 16 },
  row: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 15, paddingVertical: 14, marginBottom: 8, minHeight: 64,
  },
  rowPressed: { transform: [{ scale: 0.985 }] },
  rowTitle: { fontSize: 17, fontWeight: '800', color: paper.ink },
  rowAge: { fontSize: 15, fontWeight: '800', color: paper.critical, marginLeft: 8 },
  rowState: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.ink, marginTop: 4 },
  rowHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  rowPending: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  chev: { fontSize: 16, color: paper.dim, marginLeft: 8 },
  emptyCard: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 15, paddingVertical: 18 },
  emptyText: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  emptyUnknown: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.ink, marginTop: 10 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginTop: 12 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
