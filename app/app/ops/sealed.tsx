import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row, ScreenHead } from '../../src/components/ui';
import { fetchOpsSealedUnsettled, OpsSealedUnsettled } from '../../src/lib/api';
import { kstCal, kstClock, kstMonthDay } from '../../src/lib/kst';
import {
  bookingRef, deskAccess, partiesLine, SEALED_DESK_CLASS, SEALED_EMPTY_KO, SEALED_EMPTY_SUB_KO,
  SEALED_FAILED_KO, SEALED_GONE_KO, SEALED_GONE_SUB_KO, SEALED_LEAD_KO, SEALED_LOADING_KO,
  SEALED_REFUSED_KO, SEALED_TITLE_KO, sealedAgeLabel, sealedNotifiedNote,
} from '../../src/lib/ops-custody';
import { useOps } from '../../src/lib/ops-context';
// RAW server text for the log only — `e.message` is the mapped Korean the screen renders
// (api.ts `opsError` → `foldRpcError`; PENDING_DEPLOY_KO until 0224 is pushed).
import { rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 정산 미완료 — the list behind 「정산 미완료 — 확인 필요」. 0224 §F.
//
// 🔴 **A READ AND ONLY A READ.** Both parties confirmed the return (`settlement_ready_at` set), the
//    booking is still `active`, and the settlement never happened — the runner is owed money. The
//    fix is the pricing RE-DRIVE 0083 §0f names, which is not built, and `ops_resolve_return_tx`
//    refuses a sealed row by name (`already_sealed`). So no row is a button: there is no ops door
//    that could settle it, and the lead says so rather than drawing a control that would guess.
//    The parties were told 「담당자가 확인하고 있어요」 (0201 arm ⓐ); this list is what makes that
//    sentence have a person behind it.
// ⚠ Gated on the `payout_due` roster (0224 §F — the roster the bell pages).
// ⚠ `bid` (from a bell tap) MARKS the row; a tapped row may already be gone (settled since).
// ⚠ Instants go through `kst.ts` (fixed +9, no Intl — Korea has no DST).

type Phase = 'loading' | 'error' | 'ready';

export default function OpsSealedUnsettledList() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ bid?: string }>();
  const highlightId = typeof params.bid === 'string' ? params.bid : '';
  const { kinds } = useOps();
  const access = deskAccess(kinds, SEALED_DESK_CLASS);

  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<OpsSealedUnsettled[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(() => {
    setPhase('loading');
    setErr(null);
    fetchOpsSealedUnsettled()
      .then((r) => { setRows(r); setPhase('ready'); })
      .catch((e) => {
        console.warn('[ops/sealed] load:', rpcRaw(e));
        setErr((e as Error)?.message || SEALED_FAILED_KO);
        setPhase('error');
      });
  }, []);
  useFocusEffect(useCallback(() => { if (access === 'held') load(); }, [access, load]));

  const highlightMissing =
    phase === 'ready' && highlightId !== '' && !rows.some((r) => r.bookingId === highlightId);

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: colors.cream }}
        contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
      >
        {/* DESIGN.md §3b chrome header — a pushed desk wears ScreenHead, never an inline copy of it. */}
        <ScreenHead title={SEALED_TITLE_KO} />

        <Text style={s.lead}>{SEALED_LEAD_KO}</Text>

        {access === 'unknown' && <Text style={s.loading}>권한을 확인하는 중이에요…</Text>}

        {access === 'not_held' && (
          <View style={s.noteCard}>
            <Text style={s.noteText}>{SEALED_REFUSED_KO}</Text>
          </View>
        )}

        {access === 'held' && phase === 'loading' && <Text style={s.loading}>{SEALED_LOADING_KO}</Text>}

        {access === 'held' && phase === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failText}>{err ?? SEALED_FAILED_KO}</Text>
            <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryLabel}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {access === 'held' && highlightMissing && (
          <View style={s.noteCard}>
            <Text style={s.noteText}>{SEALED_GONE_KO}</Text>
            <Text style={s.noteSub}>{SEALED_GONE_SUB_KO}</Text>
          </View>
        )}

        {access === 'held' && phase === 'ready' && rows.length === 0 && !highlightMissing && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>{SEALED_EMPTY_KO}</Text>
            <Text style={s.emptySub}>{SEALED_EMPTY_SUB_KO}</Text>
          </View>
        )}

        {access === 'held' && phase === 'ready' && rows.map((r) => {
          const age = sealedAgeLabel(r.minutesSealed);
          const endMs = r.runEndedAt === null ? NaN : Date.parse(r.runEndedAt);
          const end = Number.isNaN(endMs) ? null : kstCal(endMs);
          const marked = r.bookingId === highlightId;
          return (
            <View key={r.bookingId} style={[s.row, marked && s.rowMarked]}>
              <Row style={{ justifyContent: 'flex-start', alignItems: 'baseline', flexWrap: 'wrap' }}>
                <Text style={s.rowTitle}>{r.dogName ?? '이름 없는 강아지'}</Text>
                {age !== null && <Text style={s.rowAge}>{age}</Text>}
                {marked && <Text style={s.marker}>알림</Text>}
              </Row>
              <Text style={s.rowState}>양측 반환 확인 완료 · 정산 미완료</Text>
              <Text style={s.rowHint}>{partiesLine(r.ownerName, r.runnerName)}</Text>
              <Text style={s.rowHint}>
                {bookingRef(r.bookingId)}
                {end !== null ? ` · ${kstMonthDay(end)} ${kstClock(end)} 러닝 종료` : ''}
              </Text>
              <Text style={r.notifiedAt === null ? s.rowPending : s.rowHint}>
                {sealedNotifiedNote(r.notifiedAt)}
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
