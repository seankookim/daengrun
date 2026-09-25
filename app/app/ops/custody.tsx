import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row, ScreenHead } from '../../src/components/ui';
import { fetchOpsStrandedCustody, OpsStrandedCustody } from '../../src/lib/api';
import {
  bookingRef, CUSTODY_DESK_CLASS, CUSTODY_EMPTY_KO, CUSTODY_EMPTY_SUB_KO, CUSTODY_FAILED_KO,
  CUSTODY_GONE_KO, CUSTODY_GONE_SUB_KO, CUSTODY_LEAD_KO, CUSTODY_LOADING_KO, CUSTODY_REFUSED_KO,
  CUSTODY_TITLE_KO, custodyAgeLabel, custodyNotifiedNote, custodyShapeLabel, custodyThresholdNote,
  deskAccess, partiesLine,
} from '../../src/lib/ops-custody';
import { useOps } from '../../src/lib/ops-context';
// RAW server text for the log only — `e.message` is the mapped Korean the screen renders
// (api.ts `opsError` → `foldRpcError`; PENDING_DEPLOY_KO until 0224 is pushed).
import { rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 러닝 좌초 — the list behind 「러닝 시작 좌초 — 확인 필요」 and 「러닝 종료 좌초 — 확인 필요」. 0224 §F.
//
// 🔴 **A READ AND ONLY A READ, AND THAT IS 0224 §0c's RULING.** Whether an operator may start or end
//    a run the runner never did is Sean's letter; the only exits the product has are the runner's
//    own start/stop (runner home's ⑫ strip names them), an SOS/incident, or a human in psql. So no
//    row is a button — there is no per-booking ops screen for a custody strand, and a chevron onto
//    nothing would be a dead button. The lead says what is true instead.
// ⚠ Gated on the `return_strand` roster (0224 §F) — the roster the bell pages. The console layout
//   admits on `payout_due`, so an operator can be inside the console and not hold this class; the
//   screen says so rather than drawing a 다시 시도 that can never succeed.
// ⚠ `bid` (from a bell tap) MARKS the row the bell was about. A tapped row may already be gone —
//   the runner started or stopped — and the screen says that instead of an unexplained miss.
// ⚠ Every duration is the server's minute count or an epoch difference; no calendar read.

type Phase = 'loading' | 'error' | 'ready';

export default function OpsStrandedCustodyList() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ bid?: string }>();
  const highlightId = typeof params.bid === 'string' ? params.bid : '';
  const { kinds } = useOps();
  const access = deskAccess(kinds, CUSTODY_DESK_CLASS);

  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<OpsStrandedCustody[]>([]);
  const [err, setErr] = useState<string | null>(null);
  // The epoch instant the list was READ — the age labels are measured against it, so a label never
  // claims a precision the screen did not observe. Re-set on every load.
  const [readAt, setReadAt] = useState(0);

  const load = useCallback(() => {
    setPhase('loading');
    setErr(null);
    fetchOpsStrandedCustody()
      .then((r) => { setRows(r); setReadAt(Date.now()); setPhase('ready'); })
      .catch((e) => {
        console.warn('[ops/custody] load:', rpcRaw(e));
        setErr((e as Error)?.message || CUSTODY_FAILED_KO);
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
        <ScreenHead title={CUSTODY_TITLE_KO} />

        <Text style={s.lead}>{CUSTODY_LEAD_KO}</Text>

        {/* An unread roster answer is not a 'no' — say it is being checked. */}
        {access === 'unknown' && <Text style={s.loading}>권한을 확인하는 중이에요…</Text>}

        {access === 'not_held' && (
          <View style={s.noteCard}>
            <Text style={s.noteText}>{CUSTODY_REFUSED_KO}</Text>
          </View>
        )}

        {access === 'held' && phase === 'loading' && <Text style={s.loading}>{CUSTODY_LOADING_KO}</Text>}

        {access === 'held' && phase === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failText}>{err ?? CUSTODY_FAILED_KO}</Text>
            <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryLabel}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {access === 'held' && highlightMissing && (
          <View style={s.noteCard}>
            <Text style={s.noteText}>{CUSTODY_GONE_KO}</Text>
            <Text style={s.noteSub}>{CUSTODY_GONE_SUB_KO}</Text>
          </View>
        )}

        {access === 'held' && phase === 'ready' && rows.length === 0 && !highlightMissing && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>{CUSTODY_EMPTY_KO}</Text>
            <Text style={s.emptySub}>{CUSTODY_EMPTY_SUB_KO}</Text>
          </View>
        )}

        {access === 'held' && phase === 'ready' && rows.map((r) => {
          const age = custodyAgeLabel(r.shape, r.sinceAt, readAt);
          const marked = r.bookingId === highlightId;
          return (
            <View key={r.bookingId} style={[s.row, marked && s.rowMarked]}>
              <Row style={{ justifyContent: 'flex-start', alignItems: 'baseline', flexWrap: 'wrap' }}>
                <Text style={s.rowTitle}>{r.dogName ?? '이름 없는 강아지'}</Text>
                {age !== null && <Text style={s.rowAge}>{age}</Text>}
                {marked && <Text style={s.marker}>알림</Text>}
              </Row>
              <Text style={s.rowState}>{custodyShapeLabel(r.shape)}</Text>
              <Text style={s.rowHint}>{partiesLine(r.ownerName, r.runnerName)}</Text>
              <Text style={s.rowHint}>{bookingRef(r.bookingId)} · {custodyThresholdNote(r.strandMinutes, r.minutesOverdue)}</Text>
              <Text style={r.notifiedAt === null ? s.rowPending : s.rowHint}>
                {custodyNotifiedNote(r.notifiedAt)}
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
