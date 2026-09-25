import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row, ScreenHead } from '../../src/components/ui';
import {
  fetchOpsPrerunCases, fetchOpsStrandedCustody, OpsPrerunCase, OpsStrandedCustody,
} from '../../src/lib/api';
import { kstCal, kstClock, kstMonthDay } from '../../src/lib/kst';
import {
  bookingRef, CUSTODY_DESK_CLASS, CUSTODY_EMPTY_KO, CUSTODY_EMPTY_SUB_KO, CUSTODY_FAILED_KO,
  CUSTODY_GONE_KO, CUSTODY_LEAD_KO, CUSTODY_LOADING_KO, CUSTODY_REFUSED_KO,
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
//
// [0233 §F] + a SECOND SECTION, 「러닝 전 사고 검토」 — every marketplace booking in `incident_review`
//   whose run never ended (`ops_prerun_cases()`), the rows behind 「러닝 전 사고 검토 — 확인 필요」.
//   Same roster (`return_strand`, the one the bell rings), same READ-ONLY rule, and it NAMES NO
//   REMEDY: no door resolves a pre-run incident review (gap sweep 2 §P5 — letters L2/L3 are Sean's),
//   so the row says what happened and whether the runner is still held, and nothing about what to do.
//   Its own four faces and its own 다시 시도 — the two lists load and fail independently.
//   ⚠ A bell's `bid` may name a row in EITHER list, so 「the row is gone」 is claimed only once BOTH
//   lists have been read and neither carries it.

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

  // [0233 §F] the pre-run incident list — its own phase, so one failing list never blanks the other
  const [prePhase, setPrePhase] = useState<Phase>('loading');
  const [pre, setPre] = useState<OpsPrerunCase[]>([]);
  const [preErr, setPreErr] = useState<string | null>(null);

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
  const loadPre = useCallback(() => {
    setPrePhase('loading');
    setPreErr(null);
    fetchOpsPrerunCases()
      .then((r) => { setPre(r); setPrePhase('ready'); })
      .catch((e) => {
        console.warn('[ops/custody] prerun:', rpcRaw(e));
        setPreErr((e as Error)?.message || PRERUN_FAILED_KO);
        setPrePhase('error');
      });
  }, []);
  useFocusEffect(useCallback(() => { if (access === 'held') load(); }, [access, load]));
  useFocusEffect(useCallback(() => { if (access === 'held') loadPre(); }, [access, loadPre]));

  // A bid may name a row in EITHER list — 「gone」 only once both were read and neither has it.
  const highlightMissing =
    phase === 'ready' && prePhase === 'ready' && highlightId !== ''
    && !rows.some((r) => r.bookingId === highlightId)
    && !pre.some((c) => c.bookingId === highlightId);

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
            <Text style={s.noteSub}>{GONE_SUB_KO}</Text>
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

        {/* ── 러닝 전 사고 검토 [0233 §F] ─────────────────────────────────────────────────
            READ-ONLY and names NO remedy (L2/L3). Four faces; its own 다시 시도. */}
        {access === 'held' && (
          <>
            <Text style={s.secTitle}>{PRERUN_TITLE_KO}</Text>
            <Text style={s.lead}>{PRERUN_LEAD_KO}</Text>

            {prePhase === 'loading' && <Text style={s.loading}>{PRERUN_LOADING_KO}</Text>}

            {prePhase === 'error' && (
              <View style={s.failStrip}>
                <Text style={s.failText}>{preErr ?? PRERUN_FAILED_KO}</Text>
                <Pressable onPress={loadPre} accessibilityRole="button" style={s.retryBtn}>
                  <Text style={s.retryLabel}>다시 시도</Text>
                </Pressable>
              </View>
            )}

            {prePhase === 'ready' && pre.length === 0 && (
              <View style={s.emptyCard}>
                <Text style={s.emptyText}>{PRERUN_EMPTY_KO}</Text>
                <Text style={s.emptySub}>{PRERUN_EMPTY_SUB_KO}</Text>
              </View>
            )}

            {prePhase === 'ready' && pre.map((c) => {
              const preMarked = c.bookingId === highlightId;
              return (
                <View key={c.bookingId} style={[s.row, preMarked && s.rowMarked]}>
                  <Row style={{ justifyContent: 'flex-start', alignItems: 'baseline', flexWrap: 'wrap' }}>
                    <Text style={s.rowTitle}>{c.dogName ?? '이름 없는 강아지'}</Text>
                    {preMarked && <Text style={s.marker}>알림</Text>}
                  </Row>
                  <Text style={s.rowState}>{prerunEvidenceLine(c)}</Text>
                  {/* ⚠ About THIS booking only: `runner_gated` is 0233 §A's arm evaluated on this row,
                      not runner_work_gate's global answer — a runner held by ANOTHER booking would
                      make 「받을 수 있어요」 false (executing review of 8682181, finding 3). */}
                  <Text style={c.runnerGated ? s.rowPending : s.rowHint}>
                    {c.runnerGated ? PRERUN_GATED_KO : PRERUN_NOT_GATED_KO}
                  </Text>
                  <Text style={s.rowHint}>{partiesLine(c.ownerName, c.runnerName)}</Text>
                  <Text style={s.rowHint}>
                    {bookingRef(c.bookingId)}{prerunScheduledLabel(c.scheduledAt)}
                  </Text>
                  <Text style={c.notifiedAt === null ? s.rowPending : s.rowHint}>
                    {custodyNotifiedNote(c.notifiedAt)}
                  </Text>
                </View>
              );
            })}
          </>
        )}
      </ScrollView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

// [0233 §F] the pre-run section's copy. Inline rather than in `ops-custody.ts` because only this
// screen draws it; every sentence says what the SERVER reported and none of them names a remedy.
const PRERUN_TITLE_KO = '러닝 전 사고 검토';
/** The 「gone」 note's second line, widened from CUSTODY_GONE_SUB_KO: the bid may have come from the
 *  pre-run bell, where 「the runner started or stopped」 is not the only way a row leaves. */
const GONE_SUB_KO = '러닝이 시작되거나 종료됐거나, 예약 상태가 바뀌었을 수 있어요 — 다시 멈추면 목록에 돌아와요';
const PRERUN_LEAD_KO =
  '러닝이 시작되기 전에 사고 검토로 넘어간 예약이에요. 이 화면은 보기 전용이에요 — '
  + '이 상태를 마무리하는 방법은 아직 정해지지 않았어요.';
/** Scoped to the booking on purpose — the server answers for THIS row, not for the runner. */
const PRERUN_GATED_KO = '이 예약 때문에 러너가 새 요청을 받을 수 없어요';
const PRERUN_NOT_GATED_KO = '이 예약은 러너의 새 요청을 막지 않아요';
const PRERUN_LOADING_KO = '러닝 전 사고 검토를 불러오는 중이에요…';
const PRERUN_FAILED_KO = '러닝 전 사고 검토를 불러오지 못했어요';
const PRERUN_EMPTY_KO = '러닝 전 사고 검토 중인 예약이 없어요';
/** ⚠ 0233 §F lists EVERY such row, belled or not, with no threshold — so an empty list IS the fact. */
const PRERUN_EMPTY_SUB_KO = '러닝 전에 사고 검토로 넘어간 예약이 생기면 바로 여기에 나와요';

/** What the row carries as evidence — the stamps the server returned, never a guess at the cause. */
function prerunEvidenceLine(c: OpsPrerunCase): string {
  const owner = c.ownerHandoffAt !== null;
  const runner = c.runnerHandoffAt !== null;
  if (owner && runner) return '양쪽 인계 확인 뒤, 러닝이 시작되기 전에 멈췄어요';
  if (owner) return '보호자만 인계를 확인한 채 멈췄어요';
  if (runner) return '러너만 인계를 확인한 채 멈췄어요';
  if (c.arrivedAt !== null) return '러너 도착만 기록되고 인계는 없었어요';
  return '인계와 도착 기록이 없어요';
}

/** 「 · 예정 9월 26일 19:00」 in KST (kst.ts — never the device clock), or '' when absent. */
function prerunScheduledLabel(scheduledAt: string | null): string {
  if (scheduledAt === null) return '';
  const ms = Date.parse(scheduledAt);
  if (!Number.isFinite(ms)) return '';
  const c = kstCal(ms);
  return ` · 예정 ${kstMonthDay(c)} ${kstClock(c)}`;
}

// 15pt floor (DESIGN.md:145). No Korean below 15 here; the kicker exemption is latin-only.
const s = StyleSheet.create({
  secTitle: { fontSize: 20, fontWeight: '900', color: paper.ink, marginTop: 26 },
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
