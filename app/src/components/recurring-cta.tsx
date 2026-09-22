// 매주 반복 — the one block that turns a booking into a weekly series, and shows what the weekly
// series actually IS once it exists.
//
// WHY A COMPONENT AND NOT THREE COPIES. The loop the PMF gate measures (M1 rebooking 60%) is
// server-complete and has been since 0026: `create_recurring_series` makes the series, the hourly
// `generate_recurring_bookings` cron fills it. Measured on trunk before this slice, the ONLY place
// a client could reach that RPC was a collapsed fold on the FIRST booking
// (`owner/request.tsx:~646`) — the one moment an owner has no idea yet whether they want this
// weekly. The intent forms LATER: on the report right after a good run, in the schedule sheet, on
// home's rebook row. Three screens, one sentence, one refusal table; a copy that drifted between
// them would be three different promises about the same cron.
//
// WHAT IT NEVER DOES:
//  · claim a series was created. `create_recurring_series` is IDEMPOTENT (`0077:45` returns the
//    existing `series_id` untouched), so 「만들었어요」 after a second tap would be a lie. The
//    component READS the series back and renders its state line — the same line it would render on
//    a cold mount — so the screen says what IS rather than what it did.
//  · show a button when the booking is already in a series. The state line replaces it.
//  · guess. Every sentence is `describeSeries`'s output over a row that was read back; a failed
//    read is a failure strip with a retry, never a silent absence (`recurring-state.ts` holds the
//    reasoning about which facts license which sentence).
//
// Busy = label swap (the button matrix law), refusals in Korean through `foldRpcError`.

import { useCallback, useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import {
  SeriesRow, createRecurringSeries, fetchSeries, fetchSeriesForBooking, resumeRecurringSeries,
} from '../lib/api';
import { haptic } from '../lib/haptics';
import { rpcRaw } from '../lib/rpc-error';
import {
  CREATE_BUSY, CREATE_LABEL, CREATE_SUB, RESUME_BUSY, RESUME_LABEL, describeSeries,
} from '../lib/recurring-state';
import { paper } from '../theme';

type Load = 'loading' | 'ready' | 'failed';

export function RecurringCta({
  bookingId, seriesId, onChanged,
}: {
  bookingId: string;
  /** The caller's own `series_id` when it already has one (the schedule sheet does). Saves the
   *  bookings lookup; the series row is still read from the server either way. */
  seriesId?: string | null;
  /** Fired after a create or a resume LANDED, so the host screen can re-read its own list. */
  onChanged?: () => void;
}) {
  const [series, setSeries] = useState<SeriesRow | null>(null);
  const [load, setLoad] = useState<Load>('loading');
  const [busy, setBusy] = useState<'create' | 'resume' | null>(null);
  // The refusal the server gave, in Korean, kept until the next attempt. A failed write must stay
  // on screen: an Alert the user dismisses leaves a button that looks untouched.
  const [refusal, setRefusal] = useState<string | null>(null);

  const read = useCallback(() => {
    setLoad('loading');
    const p = seriesId ? fetchSeries(seriesId) : fetchSeriesForBooking(bookingId);
    return p
      .then((row) => { setSeries(row); setLoad('ready'); })
      .catch((e) => { console.warn('[recurring] read:', rpcRaw(e)); setLoad('failed'); });
  }, [bookingId, seriesId]);

  useEffect(() => { read(); }, [read]);

  const create = () => {
    if (busy) return;
    haptic('light');
    setBusy('create');
    setRefusal(null);
    createRecurringSeries(bookingId)
      // The returned id is read BACK rather than trusted as 「created」 — see the header.
      .then((sid) => fetchSeries(sid))
      .then((row) => { setSeries(row); setLoad('ready'); onChanged?.(); })
      .catch((e) => setRefusal((e as Error).message ?? '매주 반복으로 바꾸지 못했어요'))
      .finally(() => setBusy(null));
  };

  const resume = () => {
    if (busy || !series) return;
    haptic('light');
    setBusy('resume');
    setRefusal(null);
    resumeRecurringSeries(series.id)
      .then(() => read())
      .then(() => onChanged?.())
      .catch((e) => setRefusal((e as Error).message ?? '반복을 다시 시작하지 못했어요'))
      .finally(() => setBusy(null));
  };

  // Loading is not an empty space and it is not a button: the two answers this block can give
  // (「바꾸기」 vs a state line) are opposite claims, so it says neither until it knows.
  if (load === 'loading') {
    return <Text style={s.quiet}>반복 예약 확인 중…</Text>;
  }
  if (load === 'failed') {
    return (
      <View style={s.fail}>
        <Text style={s.failText}>반복 예약 정보를 불러오지 못했어요</Text>
        <Pressable onPress={read} accessibilityRole="button" accessibilityLabel="반복 예약 다시 확인하기">
          <Text style={s.failRetry}>다시 시도</Text>
        </Pressable>
      </View>
    );
  }

  if (!series) {
    return (
      <View>
        <Pressable
          onPress={create}
          disabled={busy !== null}
          style={({ pressed }) => [s.row, pressed && !busy && { backgroundColor: paper.wash }]}
          accessibilityRole="button"
          accessibilityLabel={CREATE_LABEL}
          accessibilityState={{ busy: busy === 'create', disabled: busy !== null }}
        >
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={s.rowLabel}>{busy === 'create' ? CREATE_BUSY : CREATE_LABEL}</Text>
            <Text style={s.rowSub}>{CREATE_SUB}</Text>
          </View>
          {busy !== 'create' && <Text style={s.chev}>›</Text>}
        </Pressable>
        {refusal && <Text style={s.refusal}>{refusal}</Text>}
      </View>
    );
  }

  const view = describeSeries(series, Date.now());
  return (
    <View style={s.state}>
      <Text style={s.stateLine}>{view.broken ? view.line : `⟳ ${view.line}`}</Text>
      {view.note && <Text style={s.stateNote}>{view.note}</Text>}
      {view.canResume && (
        <Pressable
          onPress={resume}
          disabled={busy !== null}
          style={({ pressed }) => [s.resume, pressed && !busy && { backgroundColor: paper.wash }]}
          accessibilityRole="button"
          accessibilityLabel={RESUME_LABEL}
          accessibilityState={{ busy: busy === 'resume', disabled: busy !== null }}
        >
          <Text style={s.resumeLabel}>{busy === 'resume' ? RESUME_BUSY : RESUME_LABEL}</Text>
        </Pressable>
      )}
      {refusal && <Text style={s.refusal}>{refusal}</Text>}
    </View>
  );
}

const s = StyleSheet.create({
  quiet: { fontSize: 15, color: paper.dim, paddingVertical: 12 },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#EEEEEE',
  },
  rowLabel: { fontSize: 16, fontWeight: '800', color: paper.ink },
  rowSub: { fontSize: 15, color: paper.dim, marginTop: 2 },
  chev: { fontSize: 20, fontWeight: '800', color: paper.faint },
  state: { paddingVertical: 14, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  stateLine: { fontSize: 16, fontWeight: '800', color: paper.ink },
  stateNote: { fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 4 },
  resume: { marginTop: 10, alignSelf: 'flex-start', paddingVertical: 8, paddingHorizontal: 14, backgroundColor: paper.wash },
  resumeLabel: { fontSize: 16, fontWeight: '800', color: paper.actionInk },
  refusal: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical, marginTop: 8 },
  fail: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12, flexWrap: 'wrap' },
  failText: { flex: 1, minWidth: 180, fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },
  failRetry: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
