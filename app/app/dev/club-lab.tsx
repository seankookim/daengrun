// ═══ DEV 전용: R2 위탁 커스터디 랩 ═══
// 슬라이스당 얇은 디버그 UI 독트린 (club-run-logic.md §16) — 프로덕션 UI 아님.
// 원칙: ① __DEV__ 빌드에서만 렌더 ② 실 인증 계정 + 실 RPC만 (서비스롤 키 절대 없음 —
// 게이트는 서버의 _club_require_v2 허용목록) ③ 낙관적 전이 금지 — RPC 에러와 DB 결과
// 상태를 그대로 보여준다 ④ 축은 각각 독립 표시 (서비스·돈·배정·커스터디·인시던트·정산).
import { useCallback, useState } from 'react';
import {
  ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { Redirect } from 'expo-router';
import { colors } from '../../src/theme';
import {
  ClubIncident, CustodyEvent, DelegationBoard, DelegationDog,
  confirmReturn, custodyOverride, debugReleasePayouts, fetchCustodyEvents,
  fetchDelegationBoard, fetchSessionIncidents, finishClubSession,
  incidentAssign, incidentResolve, transferAccept, transferCancel, transferInitiate,
} from '../../src/lib/api';

const C = colors;

export default function ClubLabScreen() {
  if (!__DEV__) return <Redirect href="/" />;
  return <ClubLab />;
}

function ClubLab() {
  const [sessionId, setSessionId] = useState('');
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [incidents, setIncidents] = useState<ClubIncident[]>([]);
  const [events, setEvents] = useState<Record<string, CustodyEvent[]>>({});
  const [extTarget, setExtTarget] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);

  const load = useCallback(async (sid: string) => {
    if (!sid.trim()) return;
    setBusy(true);
    try {
      const b = await fetchDelegationBoard(sid.trim());
      setBoard(b);
      const inc = await fetchSessionIncidents(sid.trim()).catch(() => []);
      setIncidents(inc);
      setLastError(null);
    } catch (e: any) {
      setLastError(String(e?.message ?? e));
      Alert.alert('보드 로드 실패', String(e?.message ?? e));
    } finally {
      setBusy(false);
    }
  }, []);

  // 모든 액션의 공통 규약: 실행 → 실패는 실패로 Alert → 성공/실패 무관하게 서버 재조회.
  // 화면이 스스로 상태를 지어내지 않는다 — DB가 말한 것만 보여준다.
  const act = useCallback(async (label: string, fn: () => Promise<unknown>) => {
    setBusy(true);
    try {
      const r = await fn();
      setLastError(null);
      if (r !== undefined && r !== null && typeof r !== 'object') Alert.alert(label, String(r));
    } catch (e: any) {
      setLastError(`${label}: ${String(e?.message ?? e)}`);
      Alert.alert(`${label} 실패`, String(e?.message ?? e));
    } finally {
      if (board) await load(board.session.id);
      setBusy(false);
    }
  }, [board, load]);

  const artifact = () => (note.trim() ? { note: note.trim() } : null);

  const loadEvents = async (sdId: string) => {
    try {
      const ev = await fetchCustodyEvents(sdId);
      setEvents((m) => ({ ...m, [sdId]: ev }));
    } catch (e: any) {
      Alert.alert('이벤트 조회 실패', String(e?.message ?? e));
    }
  };

  return (
    <ScrollView style={s.stage} contentContainerStyle={{ padding: 14, paddingTop: 64, paddingBottom: 60 }}>
      <Text style={s.h1}>R2 커스터디 랩</Text>
      <Text style={s.sub}>DEV 전용 · 실 RPC · 허용목록 게이트 — 상태는 전부 서버가 말한 것</Text>

      <View style={s.row}>
        <TextInput
          style={s.input} value={sessionId} onChangeText={setSessionId}
          placeholder="club_session id" placeholderTextColor={C.nightDim}
          autoCapitalize="none" autoCorrect={false}
        />
        <LabBtn label="로드" onPress={() => load(sessionId)} />
      </View>

      {busy && <ActivityIndicator color={C.neon} style={{ marginVertical: 8 }} />}
      {lastError && <Text style={s.err}>⚠ {lastError}</Text>}

      {board && (
        <>
          <View style={s.card}>
            <Text style={s.cardTitle}>세션 · {board.session.status}</Text>
            <AxisRow k="정원" v={`${board.session.reservedCount ?? '?'} / ${board.session.delegatedCapacity}`} />
            <AxisRow k="인시던트" v={`열림 ${board.session.openIncidents ?? 0} · 미배정 ${board.session.unassignedIncidents ?? 0}`}
              warn={(board.session.unassignedIncidents ?? 0) > 0} />
            <View style={s.btnRow}>
              <LabBtn label="새로고침" onPress={() => load(board.session.id)} />
              <LabBtn label="릴리스 실행" onPress={() => act('릴리스', () => debugReleasePayouts())} />
              <LabBtn label="세션 종료" danger onPress={() => act('세션 종료', () => finishClubSession(board.session.id))} />
            </View>
          </View>

          {incidents.length > 0 && (
            <View style={s.card}>
              <Text style={s.cardTitle}>인시던트 {incidents.length}</Text>
              {incidents.map((i) => (
                <View key={i.id} style={s.incident}>
                  <Text style={s.mono}>{i.severity} · {i.state} · 오너 {i.caseOwner ? '있음' : '미배정'}</Text>
                  <Text style={s.body}>{i.summary}</Text>
                  <View style={s.btnRow}>
                    {!i.caseOwner && <LabBtn label="케이스 인수" onPress={() => act('케이스 인수', () => incidentAssign(i.id))} />}
                    {i.state !== 'resolved' && (
                      <LabBtn label="해소" onPress={() => act('인시던트 해소', () => incidentResolve(i.id, note.trim() || null))} />
                    )}
                  </View>
                </View>
              ))}
            </View>
          )}

          <View style={s.row}>
            <TextInput
              style={s.input} value={extTarget} onChangeText={setExtTarget}
              placeholder="외부 대상 (병원명 등)" placeholderTextColor={C.nightDim}
            />
          </View>
          <View style={s.row}>
            <TextInput
              style={s.input} value={note} onChangeText={setNote}
              placeholder="사유/증빙 노트 (비우면 증빙 없음 — 거부 경로 시험용)" placeholderTextColor={C.nightDim}
            />
          </View>

          {board.dogs.map((d) => (
            <DogCard
              key={d.sdId} d={d} runners={board.runners} events={events[d.sdId]}
              onAct={act} onEvents={() => loadEvents(d.sdId)}
              extTarget={extTarget} artifact={artifact} note={note}
            />
          ))}
        </>
      )}
    </ScrollView>
  );
}

function DogCard({ d, runners, events, onAct, onEvents, extTarget, artifact, note }: {
  d: DelegationDog; runners: DelegationBoard['runners']; events?: CustodyEvent[];
  onAct: (label: string, fn: () => Promise<unknown>) => void; onEvents: () => void;
  extTarget: string; artifact: () => Record<string, unknown> | null; note: string;
}) {
  const sev = d.ui?.severity;
  const custodian = d.custodianType === 'runner'
    ? `러너${d.custodianProfileId === d.runnerId && d.runnerName ? ` (${d.runnerName})` : ''}`
    : d.custodianType === 'owner' ? '보호자'
    : d.custodianType ? `${d.custodianType} (${d.custodianExternal ?? '?'})` : '?';
  return (
    <View style={[s.card, sev === 'critical' && { borderColor: C.tang }, sev === 'warn' && { borderColor: C.gold }]}>
      <View style={s.dogHead}>
        <Text style={s.flap}>{d.flap}</Text>
        <Text style={s.cardTitle}>{d.dogName}</Text>
        <Text style={s.stage2}>{d.ui?.primaryStage ?? '—'}</Text>
      </View>
      {(d.ui?.secondaryBadges?.length ?? 0) > 0 && (
        <Text style={s.badges}>{d.ui!.secondaryBadges.join(' · ')}</Text>
      )}
      {/* 축 독립 표시 — 한 줄 요약으로 뭉개지 않는다 */}
      <AxisRow k="SERVICE" v={`${d.serviceState ?? '—'} / ${d.completionOutcome ?? '—'} / ${d.terminationType ?? '—'}`} />
      <AxisRow k="CHARGE" v={`${d.chargeState ?? '—'} · hold ${d.holdStatus ?? '—'} · refund ${d.refundState ?? '—'}`} />
      <AxisRow k="ASSIGN" v={`${d.runnerName ?? '미배정'} · booking ${d.bookingStatus ?? '—'}`} />
      <AxisRow k="CUSTODY" v={`${custodian} · ${d.custodyPhase ?? '—'} · 반환확인 O${d.ownerReturnConfirmed ? '✓' : '✗'} R${d.runnerReturnConfirmed ? '✓' : '✗'}`}
        warn={d.custodyPhase === 'return_pending' || d.custodyPhase === 'transfer_pending'} />
      <AxisRow k="PAYOUT" v={`${d.payoutState ?? '—'} · hold ${d.payoutHold ?? '—'}${d.payoutHoldReason ? ` (${d.payoutHoldReason})` : ''}`} />
      {d.pendingTransfer && (
        <AxisRow k="TRANSFER" v={`→ ${d.pendingTransfer.toType} ${d.pendingTransfer.toExternal ?? d.pendingTransfer.toProfile ?? ''} 대기 중`} warn />
      )}
      {(d.ui?.requiredActors?.length ?? 0) > 0 && (
        <AxisRow k="ACTORS" v={`${d.ui!.requiredActors.join(', ')} → ${d.ui!.primaryIssue ?? ''}`} />
      )}

      <View style={s.btnRow}>
        <LabBtn label="반환 확인" onPress={() => onAct('반환 확인', () => confirmReturn(d.sdId))} />
        <LabBtn label="이양 취소" onPress={() => onAct('이양 취소', () => transferCancel(d.sdId))} />
        <LabBtn label="이양 수락" onPress={() => onAct('이양 수락', () => transferAccept(d.sdId, artifact()))} />
        <LabBtn label="→클리닉" danger onPress={() => onAct('클리닉 이양',
          () => transferInitiate(d.sdId, 'clinic', { toExternal: extTarget.trim() || undefined, reason: note.trim() || undefined }))} />
      </View>
      <View style={s.btnRow}>
        {runners.filter((r) => !r.isMe).map((r) => (
          <LabBtn key={r.profileId} label={`→${r.name}`} onPress={() => onAct(`${r.name}에게 이양`,
            () => transferInitiate(d.sdId, 'runner', { toProfile: r.profileId, reason: note.trim() || undefined }))} />
        ))}
      </View>
      <View style={s.btnRow}>
        <LabBtn label="대리기록 O(assisted)" onPress={() => onAct('대리 기록', () => custodyOverride(d.sdId, 'owner', 'assisted', artifact()))} />
        <LabBtn label="대리기록 R(witness)" onPress={() => onAct('대리 기록', () => custodyOverride(d.sdId, 'runner', 'witness', artifact()))} />
        <LabBtn label="이벤트" onPress={onEvents} />
      </View>

      {events && (
        <View style={s.events}>
          {events.length === 0 && <Text style={s.mono}>이벤트 없음</Text>}
          {events.map((e) => (
            <Text key={e.seq} style={s.mono}>
              #{e.seq} {e.eventType} · {e.fromType ?? '∅'}→{e.toType}{e.toExternal ? `(${e.toExternal})` : ''} · {e.confirmationKind}
              {e.incidentId ? ' · 인시던트 연결' : ''}{e.reason ? ` · ${e.reason}` : ''}
            </Text>
          ))}
        </View>
      )}
    </View>
  );
}

function AxisRow({ k, v, warn }: { k: string; v: string; warn?: boolean }) {
  return (
    <View style={s.axisRow}>
      <Text style={s.axisKey}>{k}</Text>
      <Text style={[s.axisVal, warn && { color: C.gold }]}>{v}</Text>
    </View>
  );
}

function LabBtn({ label, onPress, danger }: { label: string; onPress: () => void; danger?: boolean }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [s.btn, danger && s.btnDanger, pressed && { opacity: 0.6 }]}>
      <Text style={[s.btnText, danger && { color: C.tang }]}>{label}</Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  stage: { flex: 1, backgroundColor: C.nightBg },
  h1: { color: '#fff', fontSize: 24, fontWeight: '800' },
  sub: { color: C.nightDim, fontSize: 12, marginTop: 2, marginBottom: 12 },
  row: { flexDirection: 'row', gap: 8, marginBottom: 8, alignItems: 'center' },
  input: {
    flex: 1, borderWidth: 1, borderColor: C.nightEdge, color: '#fff', backgroundColor: C.nightCard,
    paddingHorizontal: 10, paddingVertical: 8, borderRadius: 4, fontSize: 13,
  },
  err: { color: C.tang, fontSize: 12, marginBottom: 8 },
  card: {
    backgroundColor: C.nightCard, borderWidth: 1, borderColor: C.nightEdge,
    borderRadius: 6, padding: 12, marginBottom: 10,
  },
  cardTitle: { color: '#fff', fontSize: 15, fontWeight: '800' },
  dogHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 6 },
  flap: {
    color: C.neon, fontSize: 12, fontWeight: '800', letterSpacing: 1.5,
    borderWidth: 1, borderColor: C.nightEdge, paddingHorizontal: 6, paddingVertical: 2, borderRadius: 3,
    overflow: 'hidden',
  },
  stage2: { color: C.nightDim, fontSize: 12, marginLeft: 'auto' },
  badges: { color: C.gold, fontSize: 11.5, marginBottom: 4 },
  axisRow: { flexDirection: 'row', gap: 8, paddingVertical: 2.5, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: C.nightEdge },
  axisKey: { color: C.neon, fontSize: 11, fontWeight: '700', width: 70, letterSpacing: 0.5 },
  axisVal: { color: '#E8E5F5', fontSize: 12, flex: 1 },
  btnRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 8 },
  btn: {
    borderWidth: 1, borderColor: C.neon, borderRadius: 4,
    paddingHorizontal: 10, paddingVertical: 6, backgroundColor: 'transparent',
  },
  btnDanger: { borderColor: C.tang },
  btnText: { color: C.neon, fontSize: 12, fontWeight: '700' },
  incident: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: C.nightEdge, paddingTop: 6, marginTop: 6 },
  events: { marginTop: 8, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: C.nightEdge, paddingTop: 6, gap: 2 },
  mono: { color: C.nightDim, fontSize: 11.5 },
  body: { color: '#E8E5F5', fontSize: 12.5, marginTop: 2 },
});
