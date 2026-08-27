// ═══ DEV 전용: R2 위탁 커스터디 랩 — 전 루프 콘솔 ═══
// 슬라이스당 얇은 디버그 UI 독트린 (club-run-logic.md §16) — 프로덕션 UI 아님.
// 원칙: ① __DEV__ 빌드에서만 렌더 ② 실 인증 계정 + 실 RPC만 (서비스롤 키 절대 없음 —
// 게이트는 서버의 _club_require_v2 허용목록) ③ 낙관적 전이 금지 — RPC 에러와 DB 결과
// 상태를 그대로 보여준다 ④ 축은 각각 독립 표시 ⑤ 세션 생성→위탁→승인→결제→배정→인계→
// 주행→정산→반환→릴리스→종료 전 구간이 이 한 화면에서 돌아간다 (솔로 테스트 완결).
import { useCallback, useState } from 'react';
import {
  ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { Redirect } from 'expo-router';
import { colors } from '../../src/theme';
import { supabase } from '../../src/lib/supabase';
import {
  ClubIncident, CustodyEvent, DelegationBoard, DelegationDog, DogProfile,
  approveDelegation, assignDelegation, checkinClubSession, commitAsHandler,
  confirmHandoff, confirmReturn, createClubSession, custodyOverride,
  debugReleasePayouts, delegateDog, fetchCustodyEvents, fetchDelegationBoard,
  fetchMyDogs, fetchSessionIncidents, finishClubSession, incidentAssign,
  incidentResolve, payDelegation, settleRun, startDelegatedRuns,
  transferAccept, transferCancel, transferInitiate,
} from '../../src/lib/api';

const C = colors;

export default function ClubLabScreen() {
  if (!__DEV__) return <Redirect href="/" />;
  return <ClubLab />;
}

interface RecentSession { id: string; scheduled_at: string; status: string }

function ClubLab() {
  const [sessionId, setSessionId] = useState('');
  const [recent, setRecent] = useState<RecentSession[]>([]);
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [incidents, setIncidents] = useState<ClubIncident[]>([]);
  const [myDogs, setMyDogs] = useState<DogProfile[]>([]);
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
      setIncidents(await fetchSessionIncidents(sid.trim()).catch(() => []));
      setMyDogs(await fetchMyDogs().catch(() => []));
      setLastError(null);
    } catch (e: any) {
      setLastError(String(e?.message ?? e));
      Alert.alert('보드 로드 실패', String(e?.message ?? e));
    } finally {
      setBusy(false);
    }
  }, []);

  // 모든 액션의 공통 규약: 실행 → 실패는 실패로 Alert → 성공/실패 무관하게 서버 재조회.
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

  const loadRecent = async () => {
    const { data, error } = await supabase.from('club_sessions')
      .select('id, scheduled_at, status').order('scheduled_at', { ascending: false }).limit(6);
    if (error) { Alert.alert('세션 목록 실패', error.message); return; }
    setRecent((data ?? []) as RecentSession[]);
  };

  // 테스트 세션: 내가 호스트인 클럽 + 첫 루트로 +90분 mixed 세션 생성
  const createLabSession = async () => {
    setBusy(true);
    try {
      const { data: u } = await supabase.auth.getUser();
      const { data: club } = await supabase.from('clubs').select('id, name')
        .eq('host_profile_id', u.user?.id ?? '').limit(1).maybeSingle();
      if (!club) { Alert.alert('클럽 없음', '내가 호스트인 클럽이 없어요 — 클럽 화면에서 먼저 개설'); return; }
      const { data: route } = await supabase.from('routes').select('id, name, km').limit(1).maybeSingle();
      if (!route) { Alert.alert('루트 없음', '루트가 없어요 — 위탁 세션은 루트 필수'); return; }
      const iso = new Date(Date.now() + 90 * 60 * 1000).toISOString();
      const sid = await createClubSession(club.id, iso, '랩 집결지', 8, route.id, 'mixed');
      setSessionId(sid);
      await load(sid);
    } catch (e: any) {
      Alert.alert('세션 생성 실패', String(e?.message ?? e));
    } finally {
      setBusy(false);
    }
  };

  const loadEvents = async (sdId: string) => {
    try {
      const ev = await fetchCustodyEvents(sdId);
      setEvents((m) => ({ ...m, [sdId]: ev }));
    } catch (e: any) {
      Alert.alert('이벤트 조회 실패', String(e?.message ?? e));
    }
  };

  const km = board?.session.routeKm ?? 3;
  return (
    <ScrollView style={s.stage} contentContainerStyle={{ padding: 14, paddingTop: 64, paddingBottom: 60 }}>
      <Text style={s.h1}>R2 커스터디 랩</Text>
      <Text style={s.sub}>DEV 전용 · 실 RPC · 허용목록 게이트 — 상태는 전부 서버가 말한 것</Text>

      <View style={s.btnRow}>
        <LabBtn label="테스트 세션 생성 (+90분)" onPress={createLabSession} />
        <LabBtn label="최근 세션" onPress={loadRecent} />
      </View>
      {recent.length > 0 && (
        <View style={s.btnRow}>
          {recent.map((r) => (
            <LabBtn key={r.id} label={`${r.status} · ${r.scheduled_at.slice(5, 16)}`}
              onPress={() => { setSessionId(r.id); load(r.id); }} />
          ))}
        </View>
      )}
      <View style={s.row}>
        <TextInput
          style={s.input} value={sessionId} onChangeText={setSessionId}
          placeholder="club_session id (직접 붙여넣기도 가능)" placeholderTextColor={C.nightDim}
          autoCapitalize="none" autoCorrect={false}
        />
        <LabBtn label="로드" onPress={() => load(sessionId)} />
      </View>

      {busy && <ActivityIndicator color={C.neon} style={{ marginVertical: 8 }} />}
      {lastError && <Text style={s.err}>⚠ {lastError}</Text>}

      {board && (
        <>
          <View style={s.card}>
            <Text style={s.cardTitle}>세션 · {board.session.status}{board.session.isHost ? ' · 호스트' : ''}</Text>
            <Text style={s.mono} selectable>{board.session.id}</Text>
            <AxisRow k="정원" v={`${board.session.reservedCount ?? '?'} / ${board.session.delegatedCapacity} (커밋 러너 캡 합)`} />
            <AxisRow k="인시던트" v={`열림 ${board.session.openIncidents ?? 0} · 미배정 ${board.session.unassignedIncidents ?? 0}`}
              warn={(board.session.unassignedIncidents ?? 0) > 0} />
            <AxisRow k="나" v={`커밋 ${board.me.committed ? '✓' : '✗'} · 체크인 ${board.me.checkedIn ? '✓' : '✗'} · 러너캡 ${board.me.runnerCap}`} />
            <View style={s.btnRow}>
              <LabBtn label="러너 커밋" onPress={() => act('커밋', () => commitAsHandler(board.session.id))} />
              <LabBtn label="체크인" onPress={() => act('체크인', () => checkinClubSession(board.session.id))} />
              <LabBtn label="내 주행 시작" onPress={() => act('주행 시작', () => startDelegatedRuns(board.session.id))} />
              <LabBtn label="새로고침" onPress={() => load(board.session.id)} />
            </View>
            <View style={s.btnRow}>
              <LabBtn label="릴리스 실행" onPress={() => act('릴리스', () => debugReleasePayouts())} />
              <LabBtn label="세션 종료" danger onPress={() => act('세션 종료', () => finishClubSession(board.session.id))} />
            </View>
            {myDogs.length > 0 && (
              <View style={s.btnRow}>
                {myDogs.map((d: any) => (
                  <LabBtn key={d.id} label={`위탁 신청: ${d.name}`}
                    onPress={() => act(`${d.name} 위탁 신청`, () => delegateDog(board.session.id, d.id,
                      { custodyAck: true, emergencyContact: '010-0000-0000', pickupName: 'DEV', vetLimitKrw: 150000 }))} />
                ))}
              </View>
            )}
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
              key={d.sdId} d={d} board={board} events={events[d.sdId]} km={km}
              onAct={act} onEvents={() => loadEvents(d.sdId)}
              extTarget={extTarget} artifact={artifact} note={note}
            />
          ))}
          {board.dogs.length === 0 && (
            <Text style={s.body}>위탁견 없음 — 위 '위탁 신청' 칩으로 시작</Text>
          )}
        </>
      )}
    </ScrollView>
  );
}

function DogCard({ d, board, events, km, onAct, onEvents, extTarget, artifact, note }: {
  d: DelegationDog; board: DelegationBoard; events?: CustodyEvent[]; km: number;
  onAct: (label: string, fn: () => Promise<unknown>) => void; onEvents: () => void;
  extTarget: string; artifact: () => Record<string, unknown> | null; note: string;
}) {
  const sev = d.ui?.severity;
  const isHost = board.session.isHost;
  const custodian = d.custodianType === 'runner'
    ? `러너${d.runnerName ? ` (${d.runnerName})` : ''}`
    : d.custodianType === 'owner' ? '보호자'
    : d.custodianType ? `${d.custodianType} (${d.custodianExternal ?? '?'})` : '?';
  const inRunnerCustody = d.custodianType === 'runner'
    && (d.custodyPhase === 'with_custodian' || d.custodyPhase === 'return_pending');
  return (
    <View style={[s.card, sev === 'critical' && { borderColor: C.tang }, sev === 'warn' && { borderColor: C.gold }]}>
      <View style={s.dogHead}>
        <Text style={s.flap}>{d.flap}</Text>
        <Text style={s.cardTitle}>{d.dogName}</Text>
        <Text style={s.stage2}>{d.ui?.primaryStage ?? '—'}</Text>
      </View>
      <Text style={s.mono} selectable>sd {d.sdId}</Text>
      {d.bookingId && <Text style={s.mono} selectable>bk {d.bookingId}</Text>}
      {(d.ui?.secondaryBadges?.length ?? 0) > 0 && (
        <Text style={s.badges}>{d.ui!.secondaryBadges.join(' · ')}</Text>
      )}
      <AxisRow k="SERVICE" v={`${d.serviceState ?? '—'} / ${d.completionOutcome ?? '—'} / ${d.terminationType ?? '—'}`} />
      <AxisRow k="CHARGE" v={`${d.chargeState ?? '—'} · hold ${d.holdStatus ?? '—'} · refund ${d.refundState ?? '—'}`} />
      <AxisRow k="ASSIGN" v={`${d.runnerName ?? '미배정'} · booking ${d.bookingStatus ?? '—'} · 인계 O${d.ownerConfirmed ? '✓' : '✗'} R${d.runnerConfirmed ? '✓' : '✗'}`} />
      <AxisRow k="CUSTODY" v={`${custodian} · ${d.custodyPhase ?? '—'} · 반환 O${d.ownerReturnConfirmed ? '✓' : '✗'} R${d.runnerReturnConfirmed ? '✓' : '✗'}`}
        warn={d.custodyPhase === 'return_pending' || d.custodyPhase === 'transfer_pending'} />
      <AxisRow k="PAYOUT" v={`${d.payoutState ?? '—'} · hold ${d.payoutHold ?? '—'}${d.payoutHoldReason ? ` (${d.payoutHoldReason})` : ''}`} />
      {d.pendingTransfer && (
        <AxisRow k="TRANSFER" v={`→ ${d.pendingTransfer.toType} ${d.pendingTransfer.toExternal ?? d.pendingTransfer.toProfile ?? ''} 대기 중`} warn />
      )}
      {(d.ui?.requiredActors?.length ?? 0) > 0 && (
        <AxisRow k="ACTORS" v={`${d.ui!.requiredActors.join(', ')} → ${d.ui!.primaryIssue ?? ''}`} />
      )}

      {/* 수명주기 컨트롤 — 단계 조건부지만 에러는 그대로 노출 (서버가 판정자) */}
      {isHost && d.approval === 'pending' && (
        <View style={s.btnRow}>
          <LabBtn label="승인 (20분 홀드)" onPress={() => onAct('승인', () => approveDelegation(d.sdId, true))} />
          <LabBtn label="거절" danger onPress={() => onAct('거절', () => approveDelegation(d.sdId, false))} />
        </View>
      )}
      {d.isMine && d.approval === 'approved' && !d.bookingId && (
        <View style={s.btnRow}>
          <LabBtn label="결제 (멱등키 자동)" onPress={() => onAct('결제', () => payDelegation(d.sdId, `pay-${d.sdId}`))} />
        </View>
      )}
      {isHost && d.bookingStatus === 'matching' && (
        <View style={s.btnRow}>
          {board.runners.map((r) => (
            <LabBtn key={r.profileId} label={`배정: ${r.name}`}
              onPress={() => onAct(`${r.name} 배정`, () => assignDelegation(d.sdId, r.profileId))} />
          ))}
        </View>
      )}
      {d.bookingId && d.bookingStatus === 'confirmed' && (
        <View style={s.btnRow}>
          <LabBtn label="인계 확인 O" onPress={() => onAct('인계(보호자)', () => confirmHandoff(d.bookingId!, 'owner'))} />
          <LabBtn label="인계 확인 R" onPress={() => onAct('인계(러너)', () => confirmHandoff(d.bookingId!, 'runner'))} />
        </View>
      )}
      {d.bookingId && d.bookingStatus === 'active' && (
        <View style={s.btnRow}>
          <LabBtn label={`정산 (완주 ${km}km)`} onPress={() => onAct('정산', () => settleRun({
            booking_id: d.bookingId!, end_reason: 'completed', actual_km: km, duration_sec: 1800,
          }))} />
        </View>
      )}
      {d.custodyPhase === 'return_pending' && (
        <View style={s.btnRow}>
          <LabBtn label="반환 확인 O" onPress={() => onAct('반환(보호자)', () => confirmReturn(d.sdId, 'owner'))} />
          <LabBtn label="반환 확인 R" onPress={() => onAct('반환(러너)', () => confirmReturn(d.sdId, 'runner'))} />
        </View>
      )}
      {inRunnerCustody && (
        <View style={s.btnRow}>
          {board.runners.filter((r) => r.profileId !== d.runnerId).map((r) => (
            <LabBtn key={r.profileId} label={`이양→${r.name}`} onPress={() => onAct(`${r.name}에게 이양`,
              () => transferInitiate(d.sdId, 'runner', { toProfile: r.profileId, reason: note.trim() || undefined }))} />
          ))}
          <LabBtn label="이양→클리닉" danger onPress={() => onAct('클리닉 이양',
            () => transferInitiate(d.sdId, 'clinic', { toExternal: extTarget.trim() || undefined, reason: note.trim() || undefined }))} />
        </View>
      )}
      {d.custodyPhase === 'transfer_pending' && (
        <View style={s.btnRow}>
          <LabBtn label="이양 수락 (증빙=노트)" onPress={() => onAct('이양 수락', () => transferAccept(d.sdId, artifact()))} />
          <LabBtn label="이양 취소" onPress={() => onAct('이양 취소', () => transferCancel(d.sdId))} />
        </View>
      )}
      {d.custodyPhase === 'return_pending' && (
        <View style={s.btnRow}>
          <LabBtn label="대리기록 O(assisted)" onPress={() => onAct('대리 기록', () => custodyOverride(d.sdId, 'owner', 'assisted', artifact()))} />
          <LabBtn label="대리기록 R(witness)" onPress={() => onAct('대리 기록', () => custodyOverride(d.sdId, 'runner', 'witness', artifact()))} />
        </View>
      )}
      <View style={s.btnRow}>
        <LabBtn label="이벤트" onPress={onEvents} />
      </View>

      {events && (
        <View style={s.events}>
          {events.length === 0 && <Text style={s.body}>이벤트 없음</Text>}
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
  sub: { color: C.nightDim, fontSize: 15, marginTop: 2, marginBottom: 12 },
  row: { flexDirection: 'row', gap: 8, marginBottom: 8, alignItems: 'center' },
  input: {
    flex: 1, borderWidth: 1, borderColor: C.nightEdge, color: '#fff', backgroundColor: C.nightCard,
    paddingHorizontal: 10, paddingVertical: 8, borderRadius: 4, fontSize: 15,
  },
  err: { color: C.tang, fontSize: 15, marginBottom: 8 },
  card: {
    backgroundColor: C.nightCard, borderWidth: 1, borderColor: C.nightEdge,
    borderRadius: 6, padding: 12, marginBottom: 10,
  },
  cardTitle: { color: '#fff', fontSize: 15, fontWeight: '800' },
  dogHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 4 },
  flap: {
    color: C.neon, fontSize: 12, fontWeight: '800', letterSpacing: 1.5,
    borderWidth: 1, borderColor: C.nightEdge, paddingHorizontal: 6, paddingVertical: 2, borderRadius: 3,
    overflow: 'hidden',
  },
  stage2: { color: C.nightDim, fontSize: 15, marginLeft: 'auto' },
  badges: { color: C.gold, fontSize: 15, marginVertical: 3 },
  axisRow: { flexDirection: 'row', gap: 8, paddingVertical: 2.5, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: C.nightEdge },
  axisKey: { color: C.neon, fontSize: 15, fontWeight: '700', width: 70, letterSpacing: 0.5 },
  axisVal: { color: '#E8E5F5', fontSize: 15, flex: 1 },
  btnRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 8 },
  btn: {
    borderWidth: 1, borderColor: C.neon, borderRadius: 4,
    paddingHorizontal: 10, paddingVertical: 6, backgroundColor: 'transparent',
  },
  btnDanger: { borderColor: C.tang },
  btnText: { color: C.neon, fontSize: 15, fontWeight: '700' },
  incident: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: C.nightEdge, paddingTop: 6, marginTop: 6 },
  events: { marginTop: 8, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: C.nightEdge, paddingTop: 6, gap: 2 },
  mono: { color: C.nightDim, fontSize: 11 },
  body: { color: '#E8E5F5', fontSize: 15, marginTop: 2 },
});
