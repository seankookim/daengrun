import { useCallback, useEffect, useState } from 'react';
import {
  Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperSheet } from '../../src/components/paper-sheet';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import {
  fetchOpsRoster, opsProfileLookup, OpsProfileCandidate, opsRosterSet, OpsRosterWireRow,
} from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import {
  chipLabel, classLabel, CONSOLE_CLASS, dormantNote, groupRoster, OpsRosterPerson, personSummary,
  SELECTABLE_CLASSES, wouldStrandConsole,
} from '../../src/lib/ops-roster';
import { runSeat, seatRefusalText } from '../../src/lib/ops-roster-seat';
// RAW server text for the log. `e.message` is the MAPPED Korean (api.ts `opsError` →
// `foldRpcError`), which is what a screen may render; a `console.warn` printing the folded copy
// has thrown the diagnosis away.
import { rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 운영자 명단 — who receives which operational alert, and who can open this console. 0208.
//
// 🔴 **THIS SCREEN DECIDES WHO CAN READ A RUNNER'S DECRYPTED BANK ACCOUNT.** `ops_me().is_ops` is
//    `payout_due` membership (0198 §0d), and every door behind the console gates on the same
//    class — `ops_bank_account` included. Seating someone on 정산 지급 is therefore the most
//    consequential tap in the product, which is why every toggle is a single server call with the
//    server's own refusal rendered verbatim in Korean, and why nothing here is optimistic: the
//    chip moves when the SERVER says it moved.
//
// 🔴 **마지막 운영자 IS THE SERVER'S RULE.** `wouldStrandConsole` only decides whether the chip
//    explains itself BEFORE the tap. A build that ignored it entirely would still be refused by
//    `ops_roster_set` with `last_operator`, and that Korean sentence is what gets shown.
//
// ⚠ FOUR STATES AND NONE OF THEM IS A BLANK: 'loading' says so in words (loading is not an empty
//   list), 'error' is a loud strip with 다시 시도, an empty roster says it is genuinely empty —
//   and it cannot happen through this screen, because an operator must exist to open it at all.
// ⚠ A class this app has no label for renders as ITSELF (`classLabel`'s fallback). 0084 §E puts
//   no CHECK on `ops_recipients.event_class` and `ops_roster()` returns every row, so hiding an
//   unrecognised one would make the roster lie about who is on call.
// ⚠ No date is rendered here, so there is no device-clock read. `check-device-clock` is the gate.

type Phase = 'loading' | 'error' | 'ready';
type SheetPhase = 'idle' | 'searching' | 'results' | 'error';

export default function OpsRoster() {
  const insets = useSafeAreaInsets();

  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<OpsRosterWireRow[]>([]);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  /** `${profileId}:${eventClass}` of the toggle currently on the wire. One at a time on purpose:
   *  two overlapping writes against a `last_operator` count is the race the server's row lock
   *  exists for, and queueing them here means the operator never sees two chips lie at once. */
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [rowErr, setRowErr] = useState<string | null>(null);

  const [sheetOpen, setSheetOpen] = useState(false);
  const [sheetPhase, setSheetPhase] = useState<SheetPhase>('idle');
  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<OpsProfileCandidate[]>([]);
  const [sheetErr, setSheetErr] = useState<string | null>(null);
  const [picked, setPicked] = useState<OpsProfileCandidate | null>(null);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);

  const load = useCallback(() => {
    setPhase('loading');
    setLoadErr(null);
    fetchOpsRoster()
      .then((r) => { setRows(r); setPhase('ready'); })
      .catch((e) => {
        console.warn('[ops] roster:', rpcRaw(e));
        setLoadErr((e as Error)?.message || '명단을 불러오지 못했어요');
        setPhase('error');
      });
  }, []);
  useEffect(() => load(), [load]);

  const people = groupRoster(rows);

  const toggle = useCallback((profileId: string, eventClass: string, next: boolean) => {
    const key = `${profileId}:${eventClass}`;
    if (busyKey) return;
    setBusyKey(key);
    setRowErr(null);
    haptic('light');
    opsRosterSet({ profileId, eventClass, active: next })
      .then(() => fetchOpsRoster())
      .then((r) => { setRows(r); setBusyKey(null); })
      .catch((e) => {
        console.warn('[ops] roster_set:', rpcRaw(e));
        // ⚠ The server's sentence, not ours. `last_operator` reaches the operator as
        // 「마지막 운영자는 해제할 수 없어요 …」 from `OPS_ERROR_KO`.
        setRowErr((e as Error)?.message || '변경하지 못했어요');
        setBusyKey(null);
      });
  }, [busyKey]);

  const search = useCallback((q: string) => {
    setSheetErr(null);
    if (q.trim().length < 2) { setSheetPhase('idle'); setCandidates([]); return; }
    setSheetPhase('searching');
    opsProfileLookup(q.trim())
      .then((c) => { setCandidates(c); setSheetPhase('results'); })
      .catch((e) => {
        console.warn('[ops] profile_lookup:', rpcRaw(e));
        setSheetErr((e as Error)?.message || '찾지 못했어요');
        setSheetPhase('error');
      });
  }, []);

  const closeSheet = useCallback(() => {
    setSheetOpen(false);
    setSheetPhase('idle');
    setQuery('');
    setCandidates([]);
    setSheetErr(null);
    setPicked(null);
    setChecked(new Set());
  }, []);

  // The sequencing lives in `ops-roster-seat.ts` — sequential, first-refusal-wins, and testable,
  // which it cannot be inside this module. Its header carries the reasoning for both.
  // 🔴 [2026-09-25 · codex c4] `saving` clears in a `finally`. It used to clear only in the
  //    `.catch`, so the SUCCESSFUL path left the busy label on a permanently disabled button —
  //    a dead control that only a remount fixed.
  const seat = useCallback(() => {
    if (!picked || checked.size === 0 || saving) return;
    const profileId = picked.id;
    setSaving(true);
    setSheetErr(null);
    runSeat([...checked], (c) => opsRosterSet({ profileId, eventClass: c, active: true }))
      .then((outcome) => {
        if (outcome.refusal !== null) {
          console.warn('[ops] seat:', rpcRaw(outcome.refusal.error));
          // ⚠ A partial failure keeps the sheet OPEN with the pick and the chips intact: the
          // operator has to read which class was refused and which ones are already seated, and
          // the same button is the retry. Closing here would hide a half-finished write.
          setSheetErr(seatRefusalText(outcome, classLabel));
        } else {
          closeSheet();
        }
        // Whatever landed is the roster's truth either way — a refusal on the third class does
        // not undo the first two, so the list behind the sheet is reloaded on both paths.
        load();
      })
      .finally(() => setSaving(false));
  }, [picked, checked, saving, closeSheet, load]);

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: colors.cream }}
        contentContainerStyle={{
          paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40,
        }}
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5 }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>운영자 명단</Text>
          <View style={{ width: 40 }} />
        </Row>

        <Text style={s.lede}>
          누가 어떤 운영 알림을 받는지 정해요 · 정산 지급 담당만 이 콘솔에 들어올 수 있어요
        </Text>

        {phase === 'loading' && <Text style={s.loading}>명단을 불러오는 중이에요…</Text>}

        {phase === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failText}>{loadErr ?? '불러오지 못했어요'}</Text>
            <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryLabel}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* ⚠ A row-level refusal is shown ABOVE the list and never swallowed. `last_operator` is
            the one an operator meets, and it says what to do next. */}
        {rowErr !== null && (
          <View style={s.failStrip}>
            <Text style={s.failText}>{rowErr}</Text>
          </View>
        )}

        {phase === 'ready' && people.length === 0 && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>명단이 비어 있어요</Text>
            <Text style={s.emptySub}>아래에서 운영자를 추가해주세요</Text>
          </View>
        )}

        {phase === 'ready' && people.map((p) => (
          <PersonCard
            key={p.profileId}
            person={p}
            rows={rows}
            busyKey={busyKey}
            onToggle={toggle}
          />
        ))}

        {phase === 'ready' && (
          <Pressable
            onPress={() => { haptic('light'); setSheetOpen(true); }}
            accessibilityRole="button"
            style={({ pressed }) => [s.primary, pressed && s.primaryPressed]}
          >
            <Text style={s.primaryLabel}>운영자 추가</Text>
          </Pressable>
        )}
      </ScrollView>
      <StatusBarCover color={colors.cream} />

      <PaperSheet visible={sheetOpen} title="운영자 추가" onClose={closeSheet}>
        <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 40 }}>
          <Text style={s.sheetLabel}>이름으로 찾기</Text>
          <TextInput
            value={query}
            onChangeText={(v) => { setQuery(v); search(v); }}
            placeholder="두 글자 이상"
            placeholderTextColor={paper.faint}
            style={s.input}
            autoCorrect={false}
            accessibilityLabel="이름 검색"
          />
          {/* ⚠ Says what the search WILL return, so an operator does not read a short list as
              「that person is not in the product」. */}
          <Text style={s.sheetHint}>이름 앞부분으로 최대 10명까지 찾아요</Text>

          {sheetPhase === 'searching' && <Text style={s.loading}>찾는 중이에요…</Text>}

          {sheetPhase === 'error' && (
            <View style={s.failStrip}>
              <Text style={s.failText}>{sheetErr ?? '찾지 못했어요'}</Text>
              <Pressable onPress={() => search(query)} accessibilityRole="button" style={s.retryBtn}>
                <Text style={s.retryLabel}>다시 시도</Text>
              </Pressable>
            </View>
          )}

          {sheetPhase === 'results' && candidates.length === 0 && (
            <Text style={s.sheetEmpty}>그 이름으로 시작하는 사람이 없어요</Text>
          )}

          {sheetPhase === 'results' && candidates.map((c) => {
            const on = picked?.id === c.id;
            return (
              <Pressable
                key={c.id}
                onPress={() => { haptic('light'); setPicked(on ? null : c); }}
                accessibilityRole="button"
                accessibilityState={{ selected: on }}
                style={({ pressed }) => [s.candidate, on && s.candidateOn, pressed && s.rowPressed]}
              >
                <Text style={[s.candidateName, on && s.candidateNameOn]}>{c.name ?? '이름 없음'}</Text>
                <Text style={[s.candidateRole, on && s.candidateRoleOn]}>
                  {c.role === 'runner' ? '러너' : '보호자'}
                </Text>
              </Pressable>
            );
          })}

          {picked !== null && (
            <>
              <Text style={[s.sheetLabel, { marginTop: 20 }]}>담당 알림 고르기</Text>
              <View style={s.chipWrap}>
                {SELECTABLE_CLASSES.map((c) => {
                  const on = checked.has(c);
                  return (
                    <Pressable
                      key={c}
                      onPress={() => {
                        haptic('light');
                        setChecked((prev) => {
                          const next = new Set(prev);
                          if (next.has(c)) next.delete(c); else next.add(c);
                          return next;
                        });
                      }}
                      accessibilityRole="checkbox"
                      accessibilityState={{ checked: on }}
                      accessibilityLabel={`${classLabel(c)}${dormantNote(c)}`}
                      style={({ pressed }) => [s.chip, on && s.chipOn, pressed && s.rowPressed]}
                    >
                      {/* [ops-notifications-6] a class nothing emits says so — the chip must not
                          promise a page that cannot arrive */}
                      <Text style={[s.chipText, on && s.chipTextOn]}>
                        {on ? '✓ ' : ''}{classLabel(c)}{dormantNote(c)}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
              {checked.has(CONSOLE_CLASS) && (
                <Text style={s.warn}>
                  정산 지급을 켜면 이 운영 콘솔에 들어올 수 있어요 — 러너 정산 계좌를 볼 수 있는 권한이에요
                </Text>
              )}
            </>
          )}

          {sheetErr !== null && sheetPhase !== 'error' && (
            <View style={s.failStrip}>
              <Text style={s.failText}>{sheetErr}</Text>
            </View>
          )}

          {/* ⚠ Disabled is an explicit fill, never an opacity trick, and busy is a LABEL SWAP. */}
          <Pressable
            onPress={seat}
            disabled={picked === null || checked.size === 0 || saving}
            accessibilityRole="button"
            accessibilityState={{ disabled: picked === null || checked.size === 0 || saving }}
            style={({ pressed }) => [
              s.primary,
              (picked === null || checked.size === 0 || saving) && s.primaryDisabled,
              pressed && picked !== null && checked.size > 0 && !saving && s.primaryPressed,
            ]}
          >
            <Text style={[
              s.primaryLabel,
              (picked === null || checked.size === 0 || saving) && s.primaryLabelDisabled,
            ]}>
              {saving ? '추가하는 중이에요…' : '명단에 추가'}
            </Text>
          </Pressable>
        </ScrollView>
      </PaperSheet>
    </>
  );
}

function PersonCard({ person, rows, busyKey, onToggle }: {
  person: OpsRosterPerson;
  rows: readonly OpsRosterWireRow[];
  busyKey: string | null;
  onToggle: (profileId: string, eventClass: string, next: boolean) => void;
}) {
  // Every class the person HAS a row for, plus every class they could be seated at — so a chip
  // exists for each and the tap is always a real server call. A class with no row is OFF.
  const held = new Set(person.classes.map((c) => c.eventClass));
  const all = [...person.classes.map((c) => c.eventClass),
    ...SELECTABLE_CLASSES.filter((c) => !held.has(c))];

  return (
    <View style={s.card}>
      <Text style={s.personName}>
        {person.name ?? `프로필 ${person.profileId.slice(0, 8).toUpperCase()}`}
      </Text>
      <Text style={s.personSub}>{personSummary(person)}</Text>
      <View style={s.chipWrap}>
        {all.map((c) => {
          const row = person.classes.find((r) => r.eventClass === c);
          const on = row?.active === true;
          const key = `${person.profileId}:${c}`;
          const busy = busyKey === key;
          const otherBusy = busyKey !== null && !busy;
          // the pre-tap mirror of 0208 §C's `last_operator` — it explains the chip, it does not
          // enforce anything (the server refuses regardless)
          const stranding = wouldStrandConsole(rows, person.profileId, c, false) && on;
          return (
            <Pressable
              key={c}
              onPress={() => onToggle(person.profileId, c, !on)}
              disabled={busy || otherBusy || stranding}
              accessibilityRole="switch"
              accessibilityState={{ checked: on, disabled: busy || otherBusy || stranding }}
              accessibilityLabel={`${classLabel(c)}${dormantNote(c)} ${on ? '해제' : '설정'}`}
              accessibilityHint={stranding ? '마지막 운영자는 해제할 수 없어요' : undefined}
              style={({ pressed }) => [
                s.chip,
                on && s.chipOn,
                (busy || otherBusy || stranding) && s.chipDisabled,
                pressed && s.rowPressed,
              ]}
            >
              <Text style={[
                s.chipText,
                on && s.chipTextOn,
                (busy || otherBusy || stranding) && s.chipTextDisabled,
              ]}>
                {on && !busy ? '✓ ' : ''}{chipLabel(c, busy)}{busy ? '' : dormantNote(c)}
              </Text>
            </Pressable>
          );
        })}
      </View>
      {wouldStrandConsole(rows, person.profileId, CONSOLE_CLASS, false) && (
        <Text style={s.lastOp}>이 사람이 마지막 운영자예요 — 해제하려면 먼저 다른 사람을 추가해주세요</Text>
      )}
    </View>
  );
}

// 15pt floor (DESIGN.md:145). The kicker exemption is latin-only and this screen has none.
const s = StyleSheet.create({
  backBtn: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.line,
  },
  lede: { fontSize: 15, lineHeight: 22, color: paper.dim, marginTop: 10, marginBottom: 16 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 14 },
  card: {
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 15, paddingVertical: 14, marginBottom: 10,
  },
  personName: { fontSize: 17, fontWeight: '800', color: paper.ink },
  personSub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', marginTop: 10 },
  chip: {
    borderRadius: 999, borderWidth: 1, borderColor: colors.line, backgroundColor: '#fff',
    paddingHorizontal: 12, minHeight: 44, justifyContent: 'center',
    marginRight: 7, marginBottom: 7,
  },
  chipOn: { backgroundColor: paper.wash, borderColor: paper.line },
  chipDisabled: { backgroundColor: paper.disabledFill, borderColor: paper.disabledFill },
  chipText: { fontSize: 15, fontWeight: '700', color: paper.dim },
  chipTextOn: { color: paper.actionInk },
  chipTextDisabled: { color: paper.faint },
  rowPressed: { transform: [{ scale: 0.985 }] },
  lastOp: { fontSize: 15, lineHeight: 21, color: paper.pending, fontWeight: '700', marginTop: 8 },
  emptyCard: {
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 15, paddingVertical: 18,
  },
  emptyText: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginBottom: 12 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // DESIGN.md:203-216 button matrix — primary is the action面 with the 3D lip, radius 0.
  primary: {
    marginTop: 18, minHeight: 56, borderRadius: 0, backgroundColor: paper.action,
    borderBottomWidth: 4, borderBottomColor: paper.actionPressed,
    alignItems: 'center', justifyContent: 'center',
  },
  primaryPressed: { transform: [{ translateY: 3 }], borderBottomWidth: 1 },
  primaryDisabled: { backgroundColor: paper.disabledFill, borderBottomColor: paper.disabledFill },
  primaryLabel: { fontSize: 17, fontWeight: '800', color: '#FFFFFF' },
  primaryLabelDisabled: { color: paper.faint },
  sheetLabel: { fontSize: 16, fontWeight: '800', color: paper.ink, marginBottom: 8 },
  sheetHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 6 },
  sheetEmpty: { fontSize: 15, lineHeight: 22, color: paper.dim, paddingVertical: 14 },
  input: {
    borderWidth: 1, borderColor: colors.line, borderRadius: 12, backgroundColor: '#fff',
    paddingHorizontal: 13, minHeight: 48, fontSize: 16, color: paper.ink,
  },
  candidate: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 14, minHeight: 56, marginTop: 8,
  },
  candidateOn: { backgroundColor: paper.wash, borderColor: paper.line },
  candidateName: { fontSize: 16.5, fontWeight: '800', color: paper.ink },
  candidateNameOn: { color: paper.actionInk },
  candidateRole: { fontSize: 15, color: paper.dim },
  candidateRoleOn: { color: paper.actionInk },
  warn: { fontSize: 15, lineHeight: 21, color: paper.pending, fontWeight: '700', marginTop: 10 },
});
