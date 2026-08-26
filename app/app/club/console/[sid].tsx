import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { AckStack } from '../../../src/components/club-acks';
import { BigNumRow, ClubCta, ClubMast, ClubTag, DawnCanvas, LilacCard, LoadGate, clubText } from '../../../src/components/club-ui';
import { DrainRing } from '../../../src/components/drainring';
import {
  approveDelegation, assignmentRevoke, cancelClubSession, ClubIncident, custodyOverride, DelegationBoard, DelegationDog,
  DelegationRunner, fetchDelegationBoard, fetchSessionIncidents, finishClubSession, hostForceResolve, incidentAssign,
  incidentResolve, proposalRevoke, proposeDog, reviewDelegation,
} from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { goBackOrHome } from '../../../src/lib/nav';
import { collarColors, CollarKey, lilac, lilacRadius } from '../../../src/theme';

// 호스트 콘솔 — H1a(심사·결제) + H1b(배정·종료 게이트) (정본: master-lab H1a/H1b)
// 승인만 채도 있는 행동 (볼트 필). 결제 열은 라벨뿐 — 호스트는 돈을 만지지 않는다.
// 만석 러너 칩은 탭조차 안 된다. 종료 게이트는 서버 사유를 낱말 그대로 — 죽은 버튼 미스터리 금지.

const L = lilac;

// [정직 2026-08-26] CHARGE_LABEL was deleted here, not extended. It mapped
// paid|pending_payment|refunded|refund_pending, but `session_dogs.charge_state`'s domain is
// exactly **none|hold|paid** and CLOSED (`session_dogs_charge_state_check`, measured in
// production) — so three of its four keys had never matched anything, and none/hold fell through
// `?? d.chargeState` to render the raw English tokens 'none' and 'hold' as chips in a Korean UI.
// ⚠ The dead keys were the actual hazard: four entries made the map LOOK complete, so a reader
// checking coverage concluded it was covered. They also preserved a stale money model nobody had
// re-examined — reading `pending_payment` as "what the author meant for hold" would have imported
// it. The three charge words now live in the render below, one branch each. Do not re-add a map
// from an old screenshot; the domain is closed and named above.
const mmss = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

const PROPOSAL_MS = 5 * 60_000; // ④ 링 드레인 — 0047/0048 propose: proposal_expires_at = now() + 5 minutes

const collarOf = (c: string | null): string => (c && collarColors[c as CollarKey]) || L.coral;

function DogDot({ name, collar, size = 34 }: { name: string; collar: string | null; size?: number }) {
  return (
    <View style={{
      width: size, height: size, borderRadius: size / 2, backgroundColor: '#C9B89A',
      borderWidth: 2, borderColor: collarOf(collar), alignItems: 'center', justifyContent: 'center',
    }}>
      <Text style={{ fontSize: size * 0.4, fontWeight: '800', color: '#5d5138' }}>{name[0]}</Text>
    </View>
  );
}

function SecHead({ n, title, sub }: { n: string; title: string; sub?: string }) {
  return (
    <View style={s.sechead}>
      <View style={s.secN}><Text style={{ fontSize: 14, fontWeight: '700', color: '#fff' }}>{n}</Text></View>
      <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>{title}</Text>
      {!!sub && <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginLeft: 'auto' }}>{sub}</Text>}
    </View>
  );
}

export default function HostConsole() {
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [incidents, setIncidents] = useState<ClubIncident[]>([]);
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [now, setNow] = useState(Date.now());
  // [클럽 감사 C4] 강제 종결 사유 입력 — Alert.prompt는 iOS 전용(안드로이드에선 무반응 죽은
  // 버튼)이라 session/[sid].tsx가 세운 공용 시트 문법을 그대로 쓴다.
  const [forceTarget, setForceTarget] = useState<DelegationDog | null>(null);
  const [forceDraft, setForceDraft] = useState('');

  // [honesty 2026-08-11] 보드 실패가 영원한 '불러오는 중...' 골목이던 것 — LoadGate 3상태.
  // 직전 실값은 유지 (리프레시 실패가 화면을 비우지 않는다).
  const [boardErr, setBoardErr] = useState(false);
  const load = useCallback(() => {
    if (!sid) return;
    setBoardErr(false);
    // ⚠ [codex re-review P1] `now` is re-stamped as the board LANDS, not only by the 1s interval.
    // Without it a board that gains a hold via refresh renders its first frame against a MOUNT-ERA
    // `now`: on a screen open ten minutes with no proposal, a 20-minute window flashes as ~30:00
    // until the first tick corrects it. An inflated clock for one second is still a fabricated
    // number. Stamped HERE rather than inside the interval effect on purpose — a synchronous
    // setState in an effect trips the cascading-render rule, and this is the same instant anyway.
    fetchDelegationBoard(sid).then((b) => { setNow(Date.now()); setBoard(b); }).catch(() => setBoardErr(true));
    // [감사 P2] 실패 시 []로 덮으면 종료 차단 배너가 사라져 죽은 버튼 미스터리 — 이전 값 유지
    fetchSessionIncidents(sid).then(setIncidents).catch(() => {});
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setTimeout(() => setRefreshing(false), 400)); };

  const dogs = board?.dogs ?? [];
  const hasProposal = dogs.some((d) => d.assignmentState === 'proposed');
  // [codex P1 2026-08-26] `hasHold` is load-bearing, not tidiness. §2's hold chip renders a live
  // mm:ss off `now`, and this interval used to run ONLY while a proposal existed — so a session
  // with a hold and no proposal froze `now` at mount and displayed a countdown that never
  // decremented. A frozen clock is a fabricated live number (honesty law: loading is not 0, and a
  // number that isn't counting is worse than no number, because it reads as counting).
  // ⚠ [codex re-review P2] This asks for a hold that is still LIVE, not merely a row whose
  // chargeState reads 'hold'. Keyed on the token alone the interval never stops: the chip vanishes
  // at zero but the timer keeps re-rendering the whole screen at 1 Hz until refresh or unmount.
  // Deriving it from `now` is safe and does not thrash — the boolean changes value exactly once
  // (true → false at expiry), so the effect re-runs on that edge and cleans up, not every tick.
  const hasLiveHold = dogs.some((d) =>
    d.chargeState === 'hold' && d.holdExpiresAt != null && new Date(d.holdExpiresAt).getTime() > now);
  useEffect(() => {
    if (!hasProposal && !hasLiveHold) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [hasProposal, hasLiveHold]);

  if (!board) {
    return (
      <LoadGate
        mode={boardErr ? 'error' : 'loading'}
        errorLabel="호스트 콘솔을 불러오지 못했어요"
        onRetry={load}
        onBack={goBackOrHome}
      />
    );
  }
  if (!board.session.isHost) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 14, color: L.dim }}>호스트만 볼 수 있는 화면이에요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={goBackOrHome} style={{ alignSelf: 'stretch' }} />
        </View>
      </DawnCanvas>
    );
  }

  const sess = board.session;
  const via = sess.viability;
  const isDone = sess.status === 'done';
  const run = (fn: () => Promise<unknown>, fail: string, map?: (m: string) => string | null) => {
    if (busy) return;
    setBusy(true);
    fn().then(() => { haptic('success'); load(); })
      .catch((e) => {
        const m = (e as Error).message;
        Alert.alert(fail, (map && map(m)) || m);
      })
      .finally(() => setBusy(false));
  };

  // ---------- 심사 ----------
  const pending = dogs.filter((d) => d.approval === 'pending');
  const review = dogs.filter((d) => d.approval === 'approved' && d.reviewNeeded === true);
  const doApprove = (d: DelegationDog, ok: boolean) => {
    Alert.alert(ok ? '승인' : '거절',
      // ⚠ [정직 2026-08-26] This said 「보호자에게 결제 요청이 발송돼요」 — an event that DOES NOT
      // HAPPEN. Verified against the deployed RPC, not the migration file: `session_approve_dog`
      // has `mints_intent = false, sets_hold = true` — it sets approval + a 20-minute hold and
      // nothing else. The RPC even carries the ruling in its own body (0084 §F ④): 「요금 없음,
      // '결제' 없음 … 이 단계에서 움직이는 돈은 없다」, because charging is after the run. So the
      // host was told the app had asked the owner for money, and it had not. The line now states
      // what the RPC actually does.
      ok ? `${d.dogName}을(를) 승인할까요? 20분 동안 자리가 잡혀요.`
        : `${d.dogName}을(를) 거절할까요?`,
      [
        { text: '아직', style: 'cancel' },
        {
          text: ok ? '승인' : '거절', style: ok ? 'default' : 'destructive',
          onPress: () => run(() => approveDelegation(d.sdId, ok), ok ? '승인 실패' : '거절 실패', (m) =>
            // 정원 = 확약 러너 캡 합에서 동적 파생 (0037) — 러너가 없으면 0
            m.includes('no_capacity')
              ? `위탁 정원이 다 찼어요 (${sess.reservedCount}/${sess.delegatedCapacity})${sess.delegatedCapacity === 0 ? ' — 정원은 러너 확약이 만들어요. 세션 화면에서 러너로 확약부터 해주세요' : ''}`
              : m.includes('not_pending') ? '심사 상태가 바뀌었어요 — 새로고침해 주세요' : null),
        },
      ]);
  };
  // [감사 P0] 재검토 행은 approved라 session_approve_dog가 항상 not_pending으로 거절한다 — 정본은 session_review_dog
  const doReview = (d: DelegationDog, ok: boolean) => {
    Alert.alert(ok ? '변경 확인 — 재승인' : '재검토 거절',
      // ⚠ [정직 2026-08-26] 「전액 환불」 was UNCONDITIONAL here, and it is the same false claim
      // mirrored: on the ordinary path nothing has been charged, so it promised to return money
      // that never moved. Payment happens after the run, so an approved dog is at charge_state
      // 'hold' or 'none' for its whole pre-run life and only 'paid' has anything to refund.
      // Now conditional on the server's own field. ⚠ Contrast session-cancel below (:284/:292):
      // that 「전액 환불」 is CORRECT and is the model — it prints the real count the server
      // returns (「N건이 환불 처리로 넘어갔어요」) instead of asserting an outcome. Do not
      // "harmonise" the two; they differ because one of them knows.
      ok ? `${d.dogName}의 변경 사항을 확인하고 재승인할까요?`
        : d.chargeState === 'paid' && d.refundState === 'none'
          ? `${d.dogName}을(를) 거절할까요? 결제분은 전액 환불돼요.`
          : d.chargeState === 'hold'
            ? `${d.dogName}을(를) 거절할까요? 잡아둔 자리가 풀려요.`
            : `${d.dogName}을(를) 거절할까요?`,
      [
        { text: '아직', style: 'cancel' },
        {
          text: ok ? '재승인' : d.chargeState === 'paid' && d.refundState === 'none' ? '거절 (전액 환불)' : '거절',
          style: ok ? 'default' : 'destructive',
          onPress: () => run(() => reviewDelegation(d.sdId, ok), ok ? '재승인 실패' : '거절 실패', (m) =>
            m.includes('no_review') ? '재검토 대상이 아니에요 — 새로고침해 주세요' : null),
        },
      ]);
  };

  // ---------- 배정 ----------
  const paid = dogs.filter((d) => d.chargeState === 'paid' && d.serviceState === 'confirmed');
  // [감사 P2] 재검토 중인 개는 배정 불가 (서버 review_pending) — 심사 섹션이 담당, 여기선 제외
  const unassigned = paid.filter((d) => d.reviewNeeded !== true
    && (!d.assignmentState || ['unassigned', 'declined', 'replacement_needed'].includes(d.assignmentState)));
  const proposed = paid.filter((d) => d.assignmentState === 'proposed');
  const accepted = paid.filter((d) => d.assignmentState === 'accepted');
  const doPropose = (d: DelegationDog, r: DelegationRunner) => {
    Alert.alert('배정 제안', r.isMe
      ? `${d.dogName}을(를) 내가 맡을까요? 자기 제안은 바로 확정돼요.`
      : `${d.dogName} → ${r.name} (오늘 담당 ${r.assigned}/${r.cap})\n제안은 5분 안에 수락돼야 해요.`, [
      { text: '아직', style: 'cancel' },
      {
        text: r.isMe ? '내가 맡기' : '제안 보내기',
        onPress: () => run(() => proposeDog(d.sdId, r.profileId), '제안 실패', (m) =>
          m.includes('assign_window') ? '배정 창이 아직이에요 — 집결 2시간 전부터 열려요 (담당은 집결지에서 정해져요)'
          : m.includes('runner_not_checked_in') ? `${r.name}${r.isMe ? '(나)' : ''}가 아직 체크인 전이에요 — 집결지 체크인 후 제안할 수 있어요`
          : m.includes('runner_not_committed') ? `${r.name}의 러너 확약이 풀려 있어요`
          : m.includes('proposal_active') ? '이미 진행 중인 제안이 있어요 — 취소 후 다시 제안하세요'
          : m.includes('review_pending') ? '재검토가 끝나야 배정할 수 있어요 — 심사 섹션을 확인하세요'
          : m.includes('not_approved') ? '승인·결제 상태가 바뀌었어요 — 새로고침해 주세요'
          : m.includes('session_closed') ? '이미 닫힌 세션이에요'
          : m.includes('runner_cap_full') || m.includes('cap') ? `${r.name}의 오늘 담당이 가득 찼어요 (수락분+제안+동반견 합산)`
          : null),
      },
    ]);
  };
  const doRevoke = (d: DelegationDog) => {
    Alert.alert('배정 철회', `${d.dogName}의 배정을 철회할까요? 자리는 유지되고 재배정이 필요해져요.`, [
      { text: '유지', style: 'cancel' },
      {
        text: '철회', style: 'destructive',
        onPress: () => run(() => assignmentRevoke(d.sdId), '철회 실패', (m) =>
          m.includes('already_handed_off') ? '이미 인계가 시작돼 철회할 수 없어요'
          : m.includes('not_assigned') ? '배정 상태가 바뀌었어요 — 새로고침해 주세요' : null),
      },
    ]);
  };

  // ---------- 종료 게이트 — 서버 술어(_club_dogs_unresolved, 0045)와 동일하게만 센다 ----------
  // [감사 P0] custody_phase 기본값은 'with_custodian'(미인계 개 전부) — 이걸 세면 신청 1건만 있어도
  // 세션 종료가 영구 비활성화됐다. 서버 기준: 명시적 진행 국면 3종 + 러너/호스트 보관 중 & 부킹 진행.
  const unreturned = dogs.filter((d) =>
    ['outbound_pending', 'transfer_pending', 'return_pending'].includes(d.custodyPhase ?? '')
    || (['runner', 'host'].includes(d.custodianType ?? '')
        && d.custodyPhase !== 'resolved'
        && ['picked_up', 'active', 'completed'].includes(d.bookingStatus ?? '')));
  // [클럽 감사 C4] 러닝이 끝나지 않아 종료가 막힌 개 — 반환 미완과는 **다른 차단이고 다른 탈출구**다.
  // 러너가 인계만 받고 시작/종료를 누르지 않으면(폰 사망) 여기 남는다: 행도 버튼도 없이 세션과
  // 정산이 영구 정지했고, 차단 배너는 시작조차 안 한 러닝을 '반환 미완'이라 불렀다.
  // [적대 리뷰 2026-08-11] 자기 개(호스트가 그 개의 보호자)는 서버가 self_override로 거부한다 —
  // 그 행에도 버튼을 그리면 **눌러도 항상 실패하는 죽은 버튼**이다 (정직 법: 죽은 버튼 금지).
  // 호스트가 그 개의 러너인 경우는 다르다: 자기 러닝을 '안 끝났다'고 신고하는 건 자기고발이고
  // 서버가 허용한다 (0070 §F) — 소규모 클럽의 가장 흔한 모양이라 여기서 빠지면 C4가 안 고쳐진다.
  const runStuck = dogs.filter((d) =>
    ['runner', 'host'].includes(d.custodianType ?? '')
    && d.custodyPhase !== 'resolved'
    && ['picked_up', 'active'].includes(d.bookingStatus ?? '')
    && !d.isMine);   // isMine = 서버가 판정한 '내가 이 아이의 보호자' (클라가 재구성하지 않는다)
  // 반환 대기(한쪽 이상 미확인)로 종료가 막힌 개 — 호스트 대리 확인 대상
  const returnStuck = dogs.filter((d) => d.custodyPhase === 'return_pending' && (!d.ownerReturnConfirmed || !d.runnerReturnConfirmed));
  const doOverride = (d: DelegationDog, side: 'owner' | 'runner') => {
    Alert.alert('대리 반환 확인', `증인 자격으로 ${d.dogName}의 ${side === 'owner' ? '보호자' : '러너'} 측 반환을 대신 확인할까요? 기록에 남아요.`, [
      { text: '아직', style: 'cancel' },
      {
        text: '대리 확인',
        onPress: () => run(() => custodyOverride(d.sdId, side, 'witness', { at: new Date().toISOString(), by: 'host' }), '대리 확인 실패', (m) =>
          m.includes('self_override') ? '당사자는 자기 대리를 할 수 없어요' : m.includes('not_host') ? '호스트만 대리 확인할 수 있어요' : null),
      },
    ]);
  };
  // [클럽 감사 C4] 강제 종결 = 케이스를 여는 행동이지 반환 기록이 아니다. 서버는 개가 어디
  // 있는지 모른다고 말하고(커스터디언은 러너 유지), 진실은 열리는 S2 케이스가 나른다.
  // 호스트가 걸어나갈 수는 없다 — club_finish_session이 케이스 인수 전까진 여전히 거부한다.
  const doForceResolve = (d: DelegationDog, reason: string) => {
    const at = new Date().toISOString();
    run(
      () => hostForceResolve(d.sdId, reason, { kind: 'host_log', note: reason, at, by: 'host' })
        .then((id) => { setForceTarget(null); router.push(`/club/case/${id}`); }),
      '강제 종결 실패',
      (m) => m.includes('not_stuck') ? '이 아이는 러닝 중이 아니에요 — 반환 확인 흐름을 쓰세요'
        : m.includes('self_override') ? '이 아이의 보호자는 강제 종결할 수 없어요 — 백업 호스트나 운영에 요청하세요'
        : m.includes('not_host') ? '호스트만 강제 종결할 수 있어요'
        : m.includes('artifact_required') || m.includes('reason_required') ? '무슨 일이 있었는지 적어주세요' : null,
    );
  };
  const openCases = incidents.filter((i) => i.state !== 'resolved');
  const unownedCases = openCases.filter((i) => !i.caseOwner);
  // 차단 사유는 실제 사유대로 말한다: 러닝이 끝나지 않은 것과 반환이 끝나지 않은 것은 다른 일이다
  const returnBlocked = unreturned.filter((d) => !runStuck.some((x) => x.sdId === d.sdId));
  const blockers: string[] = [
    ...(runStuck.length > 0 ? [`${runStuck.map((d) => d.dogName).join('·')} 러닝 미종료`] : []),
    ...(returnBlocked.length > 0 ? [`${returnBlocked.map((d) => d.dogName).join('·')} 반환 미완`] : []),
    ...(unownedCases.length > 0 ? [`케이스 오너 미지정 ${unownedCases.length}건`] : []),
  ];
  // [감사 H4 2026-08-11] `cancelClubSession`은 0038부터 서버에 있는데 비-dev 호출부가 0이었다.
  // 그러면서 club-acks는 '세션 취소 — 전액 환불'을 크리티컬 ack로 등록해 둔다 — 클라이언트가
  // **받을 수는 있지만 절대 보낼 수 없는** 취소였다. 호스트가 세션을 못 여는 게 아니라 못 닫는다.
  // 서버 계약 그대로 노출한다: 호스트만 · open/full일 때만 · 인계된 아이가 있으면 서버가 거절 ·
  // 반환값은 실제 환불 건수라 결과를 주장하지 않고 **인쇄**할 수 있다.
  const doCancelSession = () => {
    Alert.alert('세션 취소',
      '이 세션을 취소할까요?\n참여자 전원에게 알림이 가고, 결제된 위탁은 전액 환불돼요. 되돌릴 수 없어요.',
      [
        { text: '아직', style: 'cancel' },
        {
          text: '세션 취소', style: 'destructive',
          onPress: () => run(
            () => cancelClubSession(sess.id).then((n) => {
              Alert.alert('세션이 취소됐어요',
                typeof n === 'number' && n > 0 ? `${n}건이 환불 처리로 넘어갔어요` : '환불 대상 예약은 없었어요');
            }),
            '취소 실패',
            (m) => m.includes('session_in_flight') ? '이미 인계된 아이가 있어요 — 밖에 나가 있는 러닝은 취소가 아니라 케이스로 다뤄요'
              : m.includes('not_host_or_closed') ? '호스트만, 그리고 진행 전 세션만 취소할 수 있어요' : null,
          ),
        },
      ]);
  };
  const doFinish = () => {
    Alert.alert('세션 종료', '세션을 마무리할까요?', [
      { text: '아직', style: 'cancel' },
      {
        text: '종료',
        onPress: () => run(() => finishClubSession(sess.id), '종료 차단', (m) =>
          m.includes('dogs_not_returned') ? '반환이 끝나지 않은 아이가 있어요 (dogs_not_returned)'
          : m.includes('incident_unassigned') ? '오너 미지정 케이스가 있어요 (incident_unassigned)'
          : null),
      },
    ]);
  };

  // ---------- 결과 화면 (done) — 콘솔의 기계는 세션과 함께 끝난다. 읽기 전용 요약 + 남은 케이스만 ----------
  if (isDone) {
    const settled = dogs.filter((d) => d.flap === 'SETTLED').length;
    const held = dogs.filter((d) => d.payoutHold === 'held').length;
    return (
      <DawnCanvas>
        <ScrollView
          contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 40 }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        >
          <ClubMast title="세션 결과" sub={`${sess.when}${clubName ? ` · ${clubName}` : ''}`} onBack={goBackOrHome}
            right={<ClubTag label="DONE" tone="dim" />} />
          <AckStack />
          <BigNumRow items={[
            { v: String(dogs.filter((d) => d.approval === 'approved').length), label: '위탁' },
            { v: String(settled), label: '완료' },
            { v: String(held), label: '정산 보류' },
            { v: String(openCases.length), label: '케이스' },
          ]} />
          {openCases.length > 0 && (
            <>
              <SecHead n="!" title="남은 케이스" sub="해소돼야 보류가 풀려요" />
              {openCases.map((i) => (
                <Pressable key={i.id} onPress={() => router.push(`/club/case/${i.id}`)} style={s.drow}>
                  <Row style={{ gap: 8, alignItems: 'center' }}>
                    <ClubTag label={i.severity.toUpperCase()} tone={i.severity.toLowerCase() === 's1' ? 'coral' : 'amber'} />
                    <Text style={[s.dogName, { flex: 1 }]} numberOfLines={1}>{i.summary}</Text>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: L.accent }}>열기 →</Text>
                  </Row>
                </Pressable>
              ))}
            </>
          )}
          <Text style={[clubText.dim, { textAlign: 'center', marginTop: 14 }]}>
            세션이 끝났어요 — 반환·케이스 해소가 끝난 정산은 자동으로 풀려요
          </Text>
        </ScrollView>
      </DawnCanvas>
    );
  }

  return (
    <DawnCanvas>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <ClubMast title="호스트 콘솔" sub={`${sess.when}${clubName ? ` · ${clubName}` : ''}`} onBack={goBackOrHome} />
        <AckStack />

        {/* 성립 미터 */}
        <BigNumRow items={[
          { v: `${sess.reservedCount}/${sess.delegatedCapacity}`, label: '위탁' },
          { v: String(via?.paidDogs ?? 0), label: '결제' },
          { v: String(via?.presentRunners ?? board.runners.length), label: '러너' },
          { v: via?.viable ? 'OK' : '미달', label: '성립' },
        ]} />

        {/* ---------- 1 심사 ---------- */}
        <SecHead n="1" title="심사" sub="승인 = 20분 자리 홀드" />
        {/* 동적 정원: 확약 러너 캡 합 = 위탁 정원 — 0이면 승인이 설 자리가 없다, 미리 말한다 */}
        {sess.delegatedCapacity === 0 && (
          <View style={s.capWarn}>
            <Text style={{ fontSize: 14, color: '#7a5a2a', lineHeight: 18 }}>
              <Text style={{ fontWeight: '800', color: L.amber }}>위탁 정원 0</Text> — 정원은 러너 확약이 만들어요. 세션 화면에서 러너 확약부터 하면 승인이 열려요.
            </Text>
          </View>
        )}
        {pending.length === 0 && review.length === 0 && (
          <Text style={s.emptyLine}>대기 중인 신청이 없어요</Text>
        )}
        {pending.map((d) => (
          <View key={d.sdId} style={[s.drow, { borderWidth: 1.5, borderColor: L.hair }]}>
            <Row style={{ gap: 10, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName}</Text>
                <Text style={s.dogSub}>{d.ownerName} 보호자</Text>
              </View>
            </Row>
            <Row style={{ gap: 8, marginTop: 10 }}>
              <Pressable onPress={() => doApprove(d, true)} style={s.abtn}><Text style={s.abtnTxt}>승인</Text></Pressable>
              <Pressable onPress={() => doApprove(d, false)} style={[s.abtn, s.abtnGhost]}><Text style={[s.abtnTxt, { color: L.dim }]}>거절</Text></Pressable>
            </Row>
          </View>
        ))}
        {review.map((d) => (
          <View key={d.sdId} style={s.drow}>
            <Row style={{ gap: 10, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName}</Text>
                <Text style={s.dogSub}>프로필 변경 — 재검토 필요</Text>
              </View>
              <ClubTag label="재검토" tone="amber" />
            </Row>
            <Row style={{ gap: 8, marginTop: 10 }}>
              <Pressable onPress={() => doReview(d, true)} style={s.abtn}><Text style={s.abtnTxt}>변경 확인 — 재승인</Text></Pressable>
              <Pressable onPress={() => doReview(d, false)} style={[s.abtn, s.abtnWarn]}><Text style={[s.abtnTxt, { color: L.amber }]}>{d.chargeState === 'paid' && d.refundState === 'none' ? '거절 (전액 환불)' : '거절'}</Text></Pressable>
            </Row>
          </View>
        ))}

        {/* ---------- 2 결제 현황 (읽기 전용) ---------- */}
        <SecHead n="2" title="결제 현황" sub="읽기 전용" />
        {dogs.filter((d) => d.approval === 'approved' && d.chargeState).length === 0 && (
          <Text style={s.emptyLine}>승인된 위탁이 아직 없어요</Text>
        )}
        {dogs.filter((d) => d.approval === 'approved' && d.chargeState).map((d) => {
          // `hold` is a SEAT hold, not a payment hold: the server sets it exactly when
          // `hold_status='active' and hold_expires_at > now()` (0048:763) — nothing about money.
          // Payment happens AFTER the run (Sean), so during this window nothing is pending except
          // the seat. That is why the word is 자리-shaped, matching 자리 확정, and why the dead map's
          // 「결제 대기」 was not adopted: it would assert a payment that is not owed yet — the same
          // error the 2026-08-11 note refused for `paid`, pointed the other way.
          const holdLeft = d.holdExpiresAt ? new Date(d.holdExpiresAt).getTime() - now : null;
          // [same guard as the proposal row] Never render an elapsed hold as '00:00 남음'.
          // ⚠ [codex P1 2026-08-26] And once elapsed we do not fall back to a bare 「자리 잡는 중」
          // either — that asserts a LIVE hold, and an elapsed one is exactly the case where the
          // payload's claim has expired under us (the server recomputes charge_state to 'none' the
          // moment `hold_expires_at` passes, 0048:763). So the chip DISAPPEARS at zero, landing on
          // the same nothing that 'none' shows — which is where the next fetch puts it anyway.
          const ticking = holdLeft != null && holdLeft > 0;
          return (
            <View key={d.sdId} style={s.drow}>
              <Row style={{ gap: 10, alignItems: 'center' }}>
                <DogDot name={d.dogName} collar={d.collar} size={30} />
                <View style={{ flex: 1 }}>
                  <Text style={s.dogName}>{d.dogName}</Text>
                  <Text style={s.dogSub}>{d.ownerName}</Text>
                </View>
                {d.chargeState === 'paid' ? (
                  <ClubTag label="자리 확정" tone="volt" />
                ) : d.chargeState === 'hold' && ticking ? (
                  <ClubTag label={`자리 잡는 중 · ${mmss(holdLeft!)}`} tone="amber" />
                ) : null /* 'none', or a 'hold' whose window has already elapsed. The payload does
                            not say WHY there is no live hold, so no word: a chip here would be
                            invented state (honesty law). */}
              </Row>
            </View>
          );
        })}

        {/* ---------- 3 배정 제안 ---------- */}
        <SecHead n="3" title="배정 제안" sub="러너 수락으로 확정" />
        {/* 배정 창 = 집결 2시간 전 ~ 6시간 후 (checkinOpen과 동일 창) — 닫혀 있으면 미리 말한다 */}
        {!sess.checkinOpen && paid.length > 0 && (
          <View style={s.capWarn}>
            <Text style={{ fontSize: 14, color: '#7a5a2a', lineHeight: 18 }}>
              <Text style={{ fontWeight: '800', color: L.amber }}>배정 창 닫힘</Text> — 집결 2시간 전에 열려요. 담당은 집결지에서 정해져요.
            </Text>
          </View>
        )}
        {paid.length === 0 && <Text style={s.emptyLine}>결제 완료된 위탁이 아직 없어요</Text>}
        {unassigned.map((d) => (
          <View key={d.sdId} style={s.drow}>
            <Row style={{ gap: 10, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName}</Text>
                <Text style={s.dogSub}>
                  {d.assignmentState === 'declined' ? '거절됨 — 다른 러너에게 제안하세요'
                    : d.assignmentState === 'replacement_needed' ? '재배정 필요 — 자리는 유지돼요'
                    : '배정 대기'}
                </Text>
              </View>
              {d.assignmentState === 'declined' && <ClubTag label="재확인" tone="coral" />}
            </Row>
            <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
              {/* [감사 H2 2026-08-11] 칩은 만석만 막고 있었다. 서버는 세 가지로 거절한다:
                  만석(_club_runner_load, 0048:478) · **체크인 전**(0048:465) · **배정 창 밖**(0048:454).
                  뒤의 둘은 클라가 이미 데이터를 들고 있으면서(board.runners[].checkedIn · sess.checkinOpen)
                  쓰지 않아, 눌리지만 실패하는 버튼 = 죽은 버튼(정직 법)이었다. 이유를 칩에 적는다 —
                  실패한 뒤 Alert로 알려주는 것은 이유를 말하는 게 아니라 변명하는 것이다. */}
              {board.runners.map((r) => {
                const full = r.assigned >= r.cap;
                const windowShut = !sess.checkinOpen;
                const notIn = !r.checkedIn;
                const blocked = full || windowShut || notIn;
                const why = full ? ' 만석' : windowShut ? ' 배정 창 닫힘' : notIn ? ' 체크인 전' : '';
                return (
                  <Pressable key={r.profileId} onPress={blocked ? undefined : () => doPropose(d, r)}
                    accessibilityState={{ disabled: blocked }}
                    style={[s.abtn, s.runnerChip, blocked && s.runnerChipOff]}>
                    <Text style={[s.abtnTxt, { color: blocked ? L.dim : L.accent }]}>
                      {r.name}{r.isMe ? '(나)' : ''} {r.assigned}/{r.cap}{why}
                    </Text>
                  </Pressable>
                );
              })}
              {board.runners.length === 0 && <Text style={s.dogSub}>확약 러너가 아직 없어요</Text>}
            </Row>
          </View>
        ))}
        {proposed.map((d) => {
          const left = d.proposalExpiresAt ? new Date(d.proposalExpiresAt).getTime() - now : null;
          const expired = left != null && left <= 0; // [감사 P2] 만료를 '00:00 남음'으로 오독시키지 않는다
          return (
            <View key={d.sdId} style={s.drow}>
              <Row style={{ gap: 10, alignItems: 'center' }}>
                <DogDot name={d.dogName} collar={d.collar} />
                <View style={{ flex: 1 }}>
                  <Text style={s.dogName}>{d.dogName}</Text>
                  <Text style={s.dogSub}>
                    {expired ? `${d.proposedRunnerName ?? '러너'} 제안 소멸 — 다시 제안하세요`
                      : `제안 → ${d.proposedRunnerName ?? '러너'}${left != null ? ` · ${mmss(left)} 남음` : ''}`}
                  </Text>
                </View>
                {/* ④ 링 드레인 (인라인 소형) — 만료 전에만. 숫자는 위 줄이 이미 말한다 */}
                {!expired && left != null && <DrainRing leftMs={left} totalMs={PROPOSAL_MS} size={28} dots={12} />}
                <ClubTag label={expired ? '소멸' : '수락 대기'} tone={expired ? 'dim' : 'amber'} />
              </Row>
              <Row style={{ gap: 8, marginTop: 10 }}>
                <Pressable onPress={() => run(() => proposalRevoke(d.sdId), '제안 취소 실패')} style={[s.abtn, s.abtnGhost]}>
                  <Text style={[s.abtnTxt, { color: L.dim }]}>{expired ? '정리하고 재제안' : '제안 취소'}</Text>
                </Pressable>
              </Row>
            </View>
          );
        })}
        {accepted.map((d) => (
          <View key={d.sdId} style={s.drow}>
            <Row style={{ gap: 10, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName}</Text>
                <Text style={s.dogSub}>담당 {d.runnerName} · 확정</Text>
              </View>
              <ClubTag label="확정" tone="volt" />
            </Row>
            {!d.ownerConfirmed && !d.runnerConfirmed && (
              <Row style={{ gap: 8, marginTop: 10 }}>
                <Pressable onPress={() => doRevoke(d)} style={[s.abtn, s.abtnGhost]}>
                  <Text style={[s.abtnTxt, { color: L.dim }]}>배정 철회</Text>
                </Pressable>
              </Row>
            )}
          </View>
        ))}

        {/* ---------- 4 케이스 ---------- */}
        {openCases.length > 0 && (
          <>
            <SecHead n="4" title="케이스" sub={`진행 중 ${openCases.length}건`} />
            {openCases.map((i) => (
              <View key={i.id} style={s.drow}>
                <Pressable onPress={() => router.push(`/club/case/${i.id}`)}>
                  <Row style={{ gap: 8, alignItems: 'center' }}>
                    <ClubTag label={i.severity.toUpperCase()} tone={i.severity.toLowerCase() === 's1' ? 'coral' : i.severity.toLowerCase() === 's2' ? 'amber' : 'dim'} />
                    <Text style={[s.dogName, { flex: 1 }]} numberOfLines={1}>{i.summary}</Text>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: L.accent }}>열기 →</Text>
                  </Row>
                </Pressable>
                <Row style={{ gap: 8, marginTop: 10 }}>
                  {!i.caseOwner ? (
                    <Pressable onPress={() => run(() => incidentAssign(i.id), '오너 지정 실패')} style={s.abtn}>
                      <Text style={s.abtnTxt}>내가 맡기</Text>
                    </Pressable>
                  ) : (
                    <Pressable
                      onPress={() => Alert.alert('케이스 해소', '해소하면 이 케이스의 정산 보류가 풀려요.', [
                        { text: '아직', style: 'cancel' },
                        { text: '해소', onPress: () => run(() => incidentResolve(i.id), '해소 실패') },
                      ])}
                      style={[s.abtn, s.abtnGhost]}>
                      <Text style={[s.abtnTxt, { color: L.dim }]}>해소 처리</Text>
                    </Pressable>
                  )}
                </Row>
              </View>
            ))}
          </>
        )}

        {/* ---------- 5 진행 · 종료 ---------- */}
        {/* 러닝 시작은 러너 액션이다 (club_start_delegated_runs = 내 픽업 부킹만) — 세션 셸 R3에 있다 */}
        <SecHead n="5" title="세션 진행" />
        {blockers.length > 0 && (
          <LilacCard crit>
            <Text style={{ fontSize: 14, fontWeight: '800', color: L.tang }}>종료 차단 {blockers.length}건</Text>
            <Text style={{ fontSize: 14, color: L.text, marginTop: 6, lineHeight: 18 }}>{blockers.join(' · ')}</Text>
          </LilacCard>
        )}
        {/* [클럽 감사 C4] 러닝이 끝나지 않은 개 — 인계까지 갔는데 러너가 시작/종료를 누르지 않으면
            (폰 사망·연락 두절) 세션도 정산도 영원히 멈췄다. 행도 버튼도 없었고, 차단 배너는
            시작조차 안 한 러닝을 '반환 미완'이라 불렀다. 여기가 그 유일한 출구다. */}
        {runStuck.map((d) => (
          <View key={d.sdId} style={s.drow}>
            <Row style={{ gap: 8, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} size={28} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName} 러닝 미종료</Text>
                <Text style={s.dogSub}>
                  {d.bookingStatus === 'picked_up' ? '인계됨 — 러닝이 시작되지 않았어요' : '러닝 중 — 종료 기록이 없어요'}
                </Text>
              </View>
            </Row>
            <Pressable onPress={() => { setForceDraft(''); setForceTarget(d); }} style={[s.abtn, s.abtnWarn, { marginTop: 9 }]}>
              <Text style={[s.abtnTxt, { color: L.tang }]}>강제 종결 — 케이스 열기</Text>
            </Pressable>
          </View>
        ))}
        {/* [감사 P1] 반환 한쪽 미확인 = 서버 종료 게이트인데 UI에 탈출구가 없어 세션이 영구 미종료였다.
            서버가 준 수단(session_custody_override) 노출 — 호스트가 증인 자격으로 대리 반환 확인. 당사자 호스트는 자기대리 금지(서버 판정). */}
        {returnStuck.map((d) => (
          <View key={d.sdId} style={s.drow}>
            <Row style={{ gap: 8, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} size={28} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName} 반환 미완</Text>
                <Text style={s.dogSub}>
                  {!d.ownerReturnConfirmed && !d.runnerReturnConfirmed ? '양측 미확인'
                    : !d.ownerReturnConfirmed ? '보호자 확인 대기' : '러너 확인 대기'}
                </Text>
              </View>
            </Row>
            <Row style={{ gap: 8, marginTop: 9 }}>
              {!d.ownerReturnConfirmed && (
                <Pressable onPress={() => doOverride(d, 'owner')} style={[s.abtn, s.abtnWarn]}>
                  <Text style={[s.abtnTxt, { color: L.amber }]}>보호자 대리 확인 (증인)</Text>
                </Pressable>
              )}
              {!d.runnerReturnConfirmed && (
                <Pressable onPress={() => doOverride(d, 'runner')} style={[s.abtn, s.abtnWarn]}>
                  <Text style={[s.abtnTxt, { color: L.amber }]}>러너 대리 확인 (증인)</Text>
                </Pressable>
              )}
            </Row>
          </View>
        ))}
        <ClubCta
          label={blockers.length > 0 ? '세션 종료 — 차단 해소 후' : '세션 종료'}
          tone={blockers.length > 0 ? 'disabled' : 'coral'}
          onPress={blockers.length > 0 ? undefined : doFinish}
          busy={busy}
        />
        {/* 취소는 종료와 다른 일이다 — 종료는 '끝났다', 취소는 '열지 않는다'.
            [적대 리뷰 2026-08-11] 처음엔 `!isDone`만 봤는데, 그러면 **취소된 뒤에도**(cancelled ≠ done)
            그리고 **이미 인계된 개가 있을 때도** 버튼이 남았다 — 둘 다 서버가 반드시 거절하는 상태다.
            서버 조건(0038:235,238)을 그대로 클라에도 적는다: open/full일 때만, 그리고 나간 개가 없을 때만.
            주석이 '진행 전에만'이라고 말하면 코드도 그래야 한다. */}
        {['open', 'full'].includes(sess.status) && runStuck.length === 0 && (
          <ClubCta label="세션 취소 — 전액 환불" tone="destructive" onPress={doCancelSession} busy={busy} />
        )}
        <Text style={[clubText.dim, { textAlign: 'center', marginTop: 10 }]}>결제는 서버가 관리해요 — 호스트는 돈을 만지지 않아요</Text>
      </ScrollView>

      {/* 강제 종결 사유 시트 — 적은 내용이 그대로 케이스 증빙(document)이 된다. 빈 채로는 못 넘긴다. */}
      <Modal visible={!!forceTarget} transparent animationType="slide" onRequestClose={() => setForceTarget(null)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.45)' }} onPress={() => setForceTarget(null)} />
        <View style={s.sheet}>
          <View style={s.grab} />
          <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>{forceTarget?.dogName} 강제 종결</Text>
          <Text style={{ fontSize: 14, color: L.text, marginTop: 5, lineHeight: 19 }}>
            {/* [적대 리뷰 2026-08-11] 종전 카피는 '정산은 보류돼요'였다 — 보류는 '곧 풀린다'는 뜻인데,
                incident_review는 전이 맵의 종단이라(0001:206) 케이스를 해소해도 정산이 스스로
                풀리지 않는다. 앱이 못 지키는 약속을 지우고 실제로 참인 것만 말한다. */}
            반환으로 기록하지 않아요 — 아이가 어디 있는지 앱은 모릅니다. S2 케이스가 열리고,
            이 예약의 정산은 케이스가 끝난 뒤 운영 처리로만 마무리돼요 (앱이 자동으로 풀지 않아요).
            적은 내용은 케이스 증빙으로 남고, 담당 러너와 보호자에게 알림이 갑니다.
          </Text>
          <TextInput
            value={forceDraft} onChangeText={setForceDraft} multiline autoFocus
            placeholder="예: 06:50 집결지 확인, 담당 러너 연락 두절"
            placeholderTextColor={L.dim}
            style={s.inputField}
          />
          <ClubCta
            label="강제 종결하고 케이스 열기"
            tone="destructive"
            busy={busy}
            onPress={() => {
              const t = forceDraft.trim();
              if (!t) { Alert.alert('무슨 일이 있었는지 적어주세요'); return; }
              if (forceTarget) doForceResolve(forceTarget, t);
            }}
          />
          <ClubCta label="아직" tone="quiet" onPress={() => setForceTarget(null)} />
        </View>
      </Modal>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  sechead: {
    flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 16, paddingBottom: 6,
    borderBottomWidth: 1, borderBottomColor: L.hair2,
  },
  secN: { backgroundColor: L.accent, borderRadius: 6, paddingVertical: 1, paddingHorizontal: 8 },
  drow: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 11, marginTop: 8,
  },
  dogName: { fontSize: 14, fontWeight: '800', color: L.head },
  // 제안 카운트다운(mmss)·확약 러너 부재 안내가 사는 줄 — 정보 텍스트 바닥선 14
  dogSub: { fontSize: 14, lineHeight: 18, color: L.text, marginTop: 1 },
  emptyLine: { fontSize: 14, color: L.dim, marginTop: 10, textAlign: 'center' },
  capWarn: {
    backgroundColor: L.amberSoft, borderWidth: 1, borderColor: L.amberEdge,
    borderRadius: lilacRadius.inner, padding: 10, paddingHorizontal: 12, marginTop: 8,
  },
  abtn: {
    flexGrow: 1, alignItems: 'center', paddingVertical: 9, paddingHorizontal: 10,
    borderRadius: lilacRadius.btn, backgroundColor: L.voltFill,
  },
  abtnGhost: { backgroundColor: L.inset },
  abtnWarn: { backgroundColor: L.amberSoft },
  abtnTxt: { fontSize: 14, fontWeight: '800', color: L.voltDeep },
  runnerChipOff: { backgroundColor: L.inset, borderColor: L.hair },
  runnerChip: { backgroundColor: L.hair2, flexGrow: 0 },
  // 강제 종결 시트 — session/[sid].tsx의 공용 시트 문법 이식 (같은 부품, 같은 느낌)
  sheet: {
    backgroundColor: L.bg, borderTopLeftRadius: lilacRadius.screen, borderTopRightRadius: lilacRadius.screen,
    padding: 16, paddingBottom: 34,
  },
  grab: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: L.hair, marginBottom: 12 },
  inputField: {
    backgroundColor: '#fff', borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.btn,
    paddingVertical: 10, paddingHorizontal: 12, fontSize: 14, color: L.head,
    marginTop: 12, minHeight: 72, textAlignVertical: 'top',
  },
});
