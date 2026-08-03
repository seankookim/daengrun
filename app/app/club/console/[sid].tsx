import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { AckStack } from '../../../src/components/club-acks';
import { BigNumRow, ClubCta, ClubMast, ClubTag, DawnCanvas, LilacCard, clubText } from '../../../src/components/club-ui';
import {
  approveDelegation, assignmentRevoke, ClubIncident, custodyOverride, DelegationBoard, DelegationDog, DelegationRunner,
  fetchDelegationBoard, fetchSessionIncidents, finishClubSession, incidentAssign, incidentResolve,
  proposalRevoke, proposeDog, reviewDelegation,
} from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { collarColors, CollarKey, lilac, lilacRadius } from '../../../src/theme';

// 호스트 콘솔 — H1a(심사·결제) + H1b(배정·종료 게이트) (정본: master-lab H1a/H1b)
// 승인만 채도 있는 행동 (볼트 필). 결제 열은 라벨뿐 — 호스트는 돈을 만지지 않는다.
// 만석 러너 칩은 탭조차 안 된다. 종료 게이트는 서버 사유를 낱말 그대로 — 죽은 버튼 미스터리 금지.

const L = lilac;

const CHARGE_LABEL: Record<string, string> = {
  paid: '결제 완료', pending_payment: '결제 대기', refunded: '환불', refund_pending: '환불 진행',
};

const mmss = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

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
      <View style={s.secN}><Text style={{ fontSize: 11, fontWeight: '700', color: '#fff' }}>{n}</Text></View>
      <Text style={{ fontSize: 13, fontWeight: '800', color: L.head }}>{title}</Text>
      {!!sub && <Text style={{ fontSize: 9.5, color: L.dim, marginLeft: 'auto' }}>{sub}</Text>}
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

  const load = useCallback(() => {
    if (!sid) return;
    fetchDelegationBoard(sid).then(setBoard).catch(() => {});
    // [감사 P2] 실패 시 []로 덮으면 종료 차단 배너가 사라져 죽은 버튼 미스터리 — 이전 값 유지
    fetchSessionIncidents(sid).then(setIncidents).catch(() => {});
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setTimeout(() => setRefreshing(false), 400)); };

  const dogs = board?.dogs ?? [];
  const hasProposal = dogs.some((d) => d.assignmentState === 'proposed');
  useEffect(() => {
    if (!hasProposal) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [hasProposal]);

  if (!board) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 13, color: L.dim }}>불러오는 중...</Text>
        </View>
      </DawnCanvas>
    );
  }
  if (!board.session.isHost) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 13, color: L.dim }}>호스트만 볼 수 있는 화면이에요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={() => router.back()} style={{ alignSelf: 'stretch' }} />
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
      ok ? `${d.dogName}을(를) 승인할까요? 보호자에게 결제 요청이 발송돼요 (20분 홀드).`
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
      ok ? `${d.dogName}의 변경 사항을 확인하고 재승인할까요?` : `${d.dogName}을(를) 거절할까요? 결제분은 전액 환불돼요.`,
      [
        { text: '아직', style: 'cancel' },
        {
          text: ok ? '재승인' : '거절 (전액 환불)', style: ok ? 'default' : 'destructive',
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
  const openCases = incidents.filter((i) => i.state !== 'resolved');
  const unownedCases = openCases.filter((i) => !i.caseOwner);
  const blockers: string[] = [
    ...(unreturned.length > 0 ? [`${unreturned.map((d) => d.dogName).join('·')} 반환 미완`] : []),
    ...(unownedCases.length > 0 ? [`케이스 오너 미지정 ${unownedCases.length}건`] : []),
  ];
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
          <ClubMast title="세션 결과" sub={`${sess.when}${clubName ? ` · ${clubName}` : ''}`} onBack={() => router.back()}
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
                    <Text style={{ fontSize: 11, fontWeight: '800', color: L.accent }}>열기 →</Text>
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
        <ClubMast title="호스트 콘솔" sub={`${sess.when}${clubName ? ` · ${clubName}` : ''}`} onBack={() => router.back()} />
        <AckStack />

        {/* 성립 미터 */}
        <BigNumRow items={[
          { v: `${sess.reservedCount}/${sess.delegatedCapacity}`, label: '위탁' },
          { v: String(via?.paidDogs ?? 0), label: '결제' },
          { v: String(via?.presentRunners ?? board.runners.length), label: '러너' },
          { v: via?.viable ? 'OK' : '미달', label: '성립' },
        ]} />

        {/* ---------- 1 심사 ---------- */}
        <SecHead n="1" title="심사" sub="승인 = 결제 요청 발송" />
        {/* 동적 정원: 확약 러너 캡 합 = 위탁 정원 — 0이면 승인이 설 자리가 없다, 미리 말한다 */}
        {sess.delegatedCapacity === 0 && (
          <View style={s.capWarn}>
            <Text style={{ fontSize: 10.5, color: '#7a5a2a', lineHeight: 16 }}>
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
              <Pressable onPress={() => doReview(d, false)} style={[s.abtn, s.abtnWarn]}><Text style={[s.abtnTxt, { color: L.amber }]}>거절 (전액 환불)</Text></Pressable>
            </Row>
          </View>
        ))}

        {/* ---------- 2 결제 현황 (읽기 전용) ---------- */}
        <SecHead n="2" title="결제 현황" sub="읽기 전용" />
        {dogs.filter((d) => d.approval === 'approved' && d.chargeState).length === 0 && (
          <Text style={s.emptyLine}>승인된 위탁이 아직 없어요</Text>
        )}
        {dogs.filter((d) => d.approval === 'approved' && d.chargeState).map((d) => (
          <View key={d.sdId} style={s.drow}>
            <Row style={{ gap: 10, alignItems: 'center' }}>
              <DogDot name={d.dogName} collar={d.collar} size={30} />
              <View style={{ flex: 1 }}>
                <Text style={s.dogName}>{d.dogName}</Text>
                <Text style={s.dogSub}>{d.ownerName}</Text>
              </View>
              <ClubTag label={CHARGE_LABEL[d.chargeState!] ?? d.chargeState!} tone={d.chargeState === 'paid' ? 'volt' : 'amber'} />
            </Row>
          </View>
        ))}

        {/* ---------- 3 배정 제안 ---------- */}
        <SecHead n="3" title="배정 제안" sub="러너 수락으로 확정" />
        {/* 배정 창 = 집결 2시간 전 ~ 6시간 후 (checkinOpen과 동일 창) — 닫혀 있으면 미리 말한다 */}
        {!sess.checkinOpen && paid.length > 0 && (
          <View style={s.capWarn}>
            <Text style={{ fontSize: 10.5, color: '#7a5a2a', lineHeight: 16 }}>
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
              {board.runners.map((r) => {
                const full = r.assigned >= r.cap;
                return (
                  <Pressable key={r.profileId} onPress={full ? undefined : () => doPropose(d, r)}
                    style={[s.abtn, s.runnerChip, full && { opacity: 0.45 }]}>
                    <Text style={[s.abtnTxt, { color: L.accent }]}>{r.name}{r.isMe ? '(나)' : ''} {r.assigned}/{r.cap}{full ? ' 만석' : ''}</Text>
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
                    <Text style={{ fontSize: 11, fontWeight: '800', color: L.accent }}>열기 →</Text>
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
            <Text style={{ fontSize: 12, fontWeight: '800', color: L.tang }}>종료 차단 {blockers.length}건</Text>
            <Text style={{ fontSize: 10.5, color: L.text, marginTop: 6, lineHeight: 17 }}>{blockers.join(' · ')}</Text>
          </LilacCard>
        )}
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
        <Text style={[clubText.dim, { textAlign: 'center', marginTop: 10 }]}>결제는 서버가 관리해요 — 호스트는 돈을 만지지 않아요</Text>
      </ScrollView>
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
  dogName: { fontSize: 13.5, fontWeight: '800', color: L.head },
  dogSub: { fontSize: 9.5, color: L.text, marginTop: 1 },
  emptyLine: { fontSize: 11, color: L.dim, marginTop: 10, textAlign: 'center' },
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
  abtnTxt: { fontSize: 11, fontWeight: '800', color: L.voltDeep },
  runnerChip: { backgroundColor: L.hair2, flexGrow: 0 },
});
