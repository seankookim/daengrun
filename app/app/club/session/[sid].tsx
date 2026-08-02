import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Avatar, Row } from '../../../src/components/ui';
import { AckStack } from '../../../src/components/club-acks';
import {
  BigNumRow, ClubCta, ClubMast, ClubTag, DawnCanvas, Flap, LilacCard, clubText,
} from '../../../src/components/club-ui';
import {
  cancelClubRsvp, cancelDelegation, checkinClubSession, ClubChatMsg, clubChatDelete, clubChatReport,
  ClubSessionDetail, commitAsHandler, confirmHandoff, confirmReturn, DelegationBoard, DelegationDog,
  fetchChatWritable, fetchClubChat, fetchClubSession, fetchDelegationBoard, fetchMyDogs, fetchSessionRoster,
  clubSos, fetchRunStartedAt, fetchShellAccess, incidentOpen, ownerObjection, payDelegation, respondProposal,
  rsvpClubSession, sendClubChat, SessionRoster, settleRun, ShellAccess, startDelegatedRuns, subscribeClubChat,
  withdrawAsHandler,
} from '../../../src/lib/api'; // finishClubSession은 호스트 콘솔로 이사
import { draft as liveDraft } from '../../../src/store'; // 라이브 화면 진입 키 (챗 draft 상태와 이름 충돌 주의)
import { useNumFont } from '../../../src/lib/fonts';
import { haptic } from '../../../src/lib/haptics';
import { collarColors, CollarKey, lilac, lilacRadius } from '../../../src/theme';

// 세션 셸 v2 — 테일러드 라일락 (빌드 2a, 정본: master-lab O3~O8 + flow-lab O4·O5)
// 셸 = 마스트 + 개요/참가자/채팅 탭. 접근은 club_my_shell_access 단일 판정 (신청은 문이 아니다).
// 개요 탭 = "몽이의 위탁" 상태 카드 하나가 상태 머신 (O3/O4/O6/O7 = 같은 카드의 다른 상태) —
// 상태 문구는 ui.primaryStage를 낱말 그대로 렌더 (클라이언트는 상태 텍스트를 지어내지 않는다).
// 이 빌드의 행동: 신청 취소(O3) · 결제 시트(O4→O5) · 이의 1회(O7) · 함께 뛰기 RSVP/체크인.
// 인계/반환 확인(O8/O10)·호스트 콘솔은 빌드 3 — 카드는 상태를 정직하게 보여주되 버튼을 만들지 않는다.

const L = lilac;

// 플랩별 한 줄 힌트 (규칙 7: 최대 1힌트) — 상태명이 아니라 "다음에 무슨 일이 일어나는지"만
const STAGE_HINT: Record<string, string> = {
  PENDING: '호스트가 확인 중이에요 — 보통 몇 시간 안에 답이 와요',
  CLEARED: '담당 러너는 집결지에서 정해져요 — 정해지면 바로 알려드려요',
};

const ROLE_LINE: Record<string, string> = {
  host: '호스트', handling_runner: '담당 러너', runner_attending: '러너', owner_attending: '동반 참가',
};

const CHARGE_LABEL: Record<string, string> = {
  paid: '결제 완료', pending_payment: '결제 대기', refunded: '환불', refund_pending: '환불 진행',
};

const WAIVER =
  '동반 참가 안내\n\n· 내 강아지의 안전과 행동은 세션 내내 보호자 본인이 책임져요\n· 리드줄 착용은 필수예요\n· 다른 참가자·강아지에게 공격성이 보이면 호스트 안내에 따라 거리를 둬요\n· 사진 촬영이 있을 수 있어요 (공개는 동의한 사진만)';

const mmss = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

const collarOf = (c: string | null): string =>
  (c && collarColors[c as CollarKey]) || L.coral;

// ---------- 강아지 아바타 — 칼라색 링 (사진 백엔드 전까지 이니셜) ----------
function DogDot({ name, collar, size = 36 }: { name: string; collar: string | null; size?: number }) {
  return (
    <View style={{
      width: size, height: size, borderRadius: size / 2, backgroundColor: '#C9B89A',
      borderWidth: 2, borderColor: collarOf(collar), alignItems: 'center', justifyContent: 'center',
    }}>
      <Text style={{ fontSize: size * 0.4, fontWeight: '800', color: '#5d5138' }}>{name[0]}</Text>
    </View>
  );
}

export default function ClubSessionShell() {
  const nf = useNumFont();
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [sess, setSess] = useState<ClubSessionDetail | null>(null);
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [access, setAccess] = useState<ShellAccess>('none');
  const [roster, setRoster] = useState<SessionRoster | null>(null);
  const [tab, setTab] = useState<'개요' | '참가자' | '채팅'>('개요');
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  // O5 결제 시트
  const [payTarget, setPayTarget] = useState<DelegationDog | null>(null);
  const [methodOk, setMethodOk] = useState(false);
  // HOLDING 카운트다운 틱
  const [now, setNow] = useState(Date.now());
  // ④ 채팅 — 그룹 스트림 + 호스트 창구 드로어
  const [chat, setChat] = useState<{ uid: string | null; msgs: ClubChatMsg[] } | null>(null);
  const [writable, setWritable] = useState(true);
  const [draft, setDraft] = useState('');
  const [hostThread, setHostThread] = useState<string | null>(null); // 열린 1:1 상대 (호스트: 신청자 id · 참가자: 'me')
  const [threadDraft, setThreadDraft] = useState('');

  const load = useCallback(() => {
    if (!sid) return;
    fetchClubSession(sid).then(setSess).catch(() => {});
    fetchDelegationBoard(sid).then(setBoard).catch(() => setBoard(null));
    fetchShellAccess(sid).then(setAccess).catch(() => setAccess('none'));
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  // 로스터 — host/full은 바로 (러너의 비상 연락처가 여기 있다), limited는 참가자 탭에서만
  useEffect(() => {
    if (!sid || access === 'none') return;
    if (access === 'host' || access === 'full' || tab === '참가자') {
      fetchSessionRoster(sid).then(setRoster).catch(() => setRoster(null));
    }
  }, [tab, access, sid]);

  // ④ 채팅 로드 + 리얼타임 — 탭이 열려 있는 동안만 구독
  useEffect(() => {
    if (tab !== '채팅' || access === 'none' || !sid) return;
    const reload = () => fetchClubChat(sid).then(setChat).catch(() => {});
    reload();
    fetchChatWritable(sid).then(setWritable).catch(() => {});
    return subscribeClubChat(sid, reload);
  }, [tab, access, sid]);

  const myDogs = board?.dogs.filter((d) => d.isMine) ?? [];
  // 러너 축 — proposedRunner*는 호스트·피제안자에게만 오므로 isMe 러너와 대조하면 곧 '나에게 온 제안'
  const myRunnerId = board?.runners.find((r) => r.isMe)?.profileId ?? null;
  const myProposals = board && myRunnerId
    ? board.dogs.filter((d) => d.assignmentState === 'proposed' && d.proposedRunnerId === myRunnerId) : [];
  const RUNNER_ACTIVE = ['confirmed', 'picked_up', 'active', 'completed'];
  const myCharges = board && myRunnerId
    ? board.dogs.filter((d) => d.runnerId === myRunnerId && RUNNER_ACTIVE.includes(d.bookingStatus ?? '')) : [];
  const ticking = myDogs.some((d) => d.flap === 'HOLDING') || myProposals.length > 0;
  useEffect(() => {
    if (!ticking) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [ticking]);

  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setTimeout(() => setRefreshing(false), 400)); };

  if (!sess) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 13, color: L.dim }}>불러오는 중...</Text>
        </View>
      </DawnCanvas>
    );
  }

  const startMs = new Date(sess.scheduledAt).getTime();
  const inCheckinWindow = Date.now() >= startMs - 2 * 3600_000 && Date.now() <= startMs + 6 * 3600_000;
  const isDone = sess.status === 'done';
  const isOpenish = sess.status === 'open' || sess.status === 'full';
  const checkedCount = sess.people.filter((p) => p.attendance === 'checked_in').length;
  const fare = board?.session.fare ?? null;

  // ---------- 함께 뛰기 (동반 참가) 액션 ----------
  const doRsvp = () => {
    Alert.alert('참여 전 확인', WAIVER, [
      { text: '취소', style: 'cancel' },
      {
        text: '동의하고 참여',
        onPress: async () => {
          setBusy(true);
          try {
            const dogs = await fetchMyDogs().catch(() => []);
            await rsvpClubSession(sess.id, dogs[0]?.id ?? null);
            haptic('success');
            load();
          } catch (e) {
            const m = (e as Error).message;
            Alert.alert('참여 실패', m.includes('session_full') ? '정원이 찼어요' : m.includes('already_joined') ? '이미 참여 중이에요' : m);
          } finally { setBusy(false); }
        },
      },
    ]);
  };
  const doCancelRsvp = () => {
    Alert.alert('참여 취소', '이번 세션 참여를 취소할까요?', [
      { text: '유지', style: 'cancel' },
      { text: '취소하기', style: 'destructive', onPress: () => cancelClubRsvp(sess.id).then(load).catch((e) => Alert.alert('취소 실패', (e as Error).message)) },
    ]);
  };
  const doCheckin = async () => {
    setBusy(true);
    try { await checkinClubSession(sess.id); haptic('success'); load(); }
    catch (e) {
      Alert.alert('체크인 실패', (e as Error).message.includes('checkin_window') ? '체크인은 시작 2시간 전부터 가능해요' : (e as Error).message);
    } finally { setBusy(false); }
  };
  // ---------- 위탁 액션 ----------
  const doWithdraw = (d: DelegationDog) => {
    Alert.alert('신청 취소', `${d.dogName}의 위탁 신청을 거둘까요? 승인 전 취소는 무료예요.`, [
      { text: '유지', style: 'cancel' },
      { text: '신청 취소', style: 'destructive', onPress: () => cancelDelegation(d.sdId).then(() => { haptic('light'); load(); }).catch((e) => Alert.alert('취소 실패', (e as Error).message)) },
    ]);
  };
  const doCancelPaid = (d: DelegationDog) => {
    Alert.alert('취소 규정', '시작 24시간 전까지 무료 · 이후 10% · 배정 수락 후 20%\n수수료는 서버가 시점 기준으로 판정해요.', [
      { text: '닫기', style: 'cancel' },
      {
        text: '취소하기', style: 'destructive',
        onPress: () => cancelDelegation(d.sdId).then(() => { haptic('light'); load(); }).catch((e) => {
          const m = (e as Error).message;
          Alert.alert('취소 실패', m.includes('incident') ? '진행 중인 케이스가 있어 지금은 취소할 수 없어요' : m);
        }),
      },
    ]);
  };
  // 이의 = preference (T-20까지 · 1회 · 사유 필수). 재배정(자리 유지) 또는 전액 환불 이탈.
  const submitObjection = (d: DelegationDog, reason: string, wantRefund: boolean) =>
    ownerObjection(d.sdId, 'preference', reason, wantRefund).then(() => { haptic('light'); load(); })
      .catch((e) => {
        const m = (e as Error).message;
        Alert.alert('접수 실패',
          m.includes('objection_window_closed') ? '시작 20분 전까지만 낼 수 있어요'
          : m.includes('objection_already_used') ? '이의는 한 번만 낼 수 있어요'
          : m.includes('already_handed_off') ? '인계 후에는 이의 대신 호스트에게 알려주세요'
          : m);
      });
  const doObjection = (d: DelegationDog) => {
    Alert.prompt?.(
      '배정 이의 (1회)',
      '우려 사유를 적어주세요 — 시작 20분 전까지 낼 수 있어요.',
      [
        { text: '닫기', style: 'cancel' },
        {
          text: '재배정 요청',
          onPress: (reason?: string) => reason?.trim() ? submitObjection(d, reason.trim(), false) : Alert.alert('사유가 필요해요'),
        },
        {
          text: '전액 환불로 취소', style: 'destructive',
          onPress: (reason?: string) => reason?.trim() ? submitObjection(d, reason.trim(), true) : Alert.alert('사유가 필요해요'),
        },
      ],
    );
  };
  const doHandoff = (d: DelegationDog) => {
    if (!d.bookingId) return;
    Alert.alert('인계 확인', `확인하면 ${d.dogName}의 책임자가 ${d.runnerName ?? '담당 러너'}(으)로 바뀌어요.`, [
      { text: '아직', style: 'cancel' },
      {
        text: '맡겼어요',
        onPress: () => confirmHandoff(d.bookingId!, 'owner').then(() => { haptic('success'); load(); })
          .catch((e) => Alert.alert('인계 확인 실패', (e as Error).message)),
      },
    ]);
  };
  const doReturnConfirm = (d: DelegationDog) => {
    confirmReturn(d.sdId, 'owner').then(() => { haptic('success'); load(); })
      .catch((e) => Alert.alert('반환 확인 실패', (e as Error).message));
  };

  // ---------- 러너 액션 (R2/R3) ----------
  const doAcceptProposal = (d: DelegationDog) => {
    Alert.alert('배정 수락', `수락하면 인계부터 반환까지 ${d.dogName}의 책임자는 나예요.`, [
      { text: '아직', style: 'cancel' },
      {
        text: '이 아이, 내가 맡을게요',
        onPress: () => respondProposal(d.sdId, true).then(() => { haptic('success'); load(); })
          .catch((e) => {
            const m = (e as Error).message;
            // 서버가 재검증한다 — 낡은 수락은 정직한 한 문장으로
            Alert.alert('수락 실패',
              m.includes('expired') ? '제안이 소멸했어요 — 호스트가 다시 제안할 수 있어요'
              : m.includes('full') || m.includes('cap') ? '오늘 담당이 가득 찼어요'
              : m);
          }),
      },
    ]);
  };
  const doDeclineProposal = (d: DelegationDog) => {
    Alert.prompt?.('우려 제기 · 거절', '사유를 남기면 호스트가 재배정에 참고해요 (선택)', [
      { text: '닫기', style: 'cancel' },
      {
        text: '거절', style: 'destructive',
        onPress: (reason?: string) => respondProposal(d.sdId, false, reason?.trim() || undefined)
          .then(() => { haptic('light'); load(); })
          .catch((e) => Alert.alert('거절 실패', (e as Error).message)),
      },
    ]);
  };
  const doRunnerHandoff = (d: DelegationDog) => {
    if (!d.bookingId) return;
    confirmHandoff(d.bookingId, 'runner').then(() => { haptic('success'); load(); })
      .catch((e) => Alert.alert('인계 확인 실패', (e as Error).message));
  };
  const doRunnerReturn = (d: DelegationDog) => {
    confirmReturn(d.sdId, 'runner').then(() => { haptic('success'); load(); })
      .catch((e) => Alert.alert('반환 확인 실패', (e as Error).message));
  };
  // 러닝 종료 (완주) = settle-run 엣지 함수 — 세그먼트는 completed 전이에 자동 마감, 커스터디는 반환 대기로.
  // km = 코스 계약 거리(라벨 명시), 경과 = runs.started_at 실측. GPS 실거리는 클럽 런 화면(R4)에서.
  const doEndRun = async (d: DelegationDog) => {
    if (!d.bookingId || busy) return;
    const startedAt = await fetchRunStartedAt(d.bookingId).catch(() => null);
    const durationSec = startedAt ? Math.max(60, Math.round((Date.now() - new Date(startedAt).getTime()) / 1000)) : null;
    const km = board?.session.routeKm ?? null;
    if (km == null || durationSec == null) {
      Alert.alert('종료 불가', km == null ? '코스 정보가 없어요' : '러닝 시작 기록을 찾지 못했어요');
      return;
    }
    Alert.alert('러닝 종료 — 완주',
      `${d.dogName} · 코스 ${km}km · 경과 ${mmss(durationSec * 1000)}\n정산이 기록되고 반환 확인으로 넘어가요.`, [
      { text: '아직', style: 'cancel' },
      {
        text: '완주로 종료',
        onPress: () => {
          setBusy(true);
          settleRun({ booking_id: d.bookingId!, end_reason: 'completed', actual_km: km, duration_sec: durationSec })
            .then(() => { haptic('success'); load(); })
            .catch((e) => Alert.alert('종료 실패', (e as Error).message))
            .finally(() => setBusy(false));
        },
      },
    ]);
  };
  // 러닝 시작 = 러너 액션 (서버: 내 픽업 부킹만) — 트랙이 열리고 보호자 화면이 '러닝 중'으로
  const doStartRuns = () => {
    Alert.alert('러닝 시작', '인계받은 아이들의 러닝 트랙이 시작돼요.', [
      { text: '아직', style: 'cancel' },
      {
        text: '시작',
        onPress: () => startDelegatedRuns(sess.id).then(() => { haptic('success'); load(); })
          .catch((e) => Alert.alert('시작 실패', (e as Error).message.includes('nothing_to_start') ? '인계 확인이 끝난 아이가 아직 없어요' : (e as Error).message)),
      },
    ]);
  };
  const doCommit = () => {
    commitAsHandler(sess.id).then(() => { haptic('success'); load(); })
      .catch((e) => {
        const m = (e as Error).message;
        Alert.alert('확약 실패', m.includes('not_certified') ? '인증 러너만 확약할 수 있어요' : m);
      });
  };
  const doWithdrawHandler = () => {
    Alert.alert('확약 철회', '이번 세션 러너 확약을 거둘까요?', [
      { text: '유지', style: 'cancel' },
      {
        text: '철회', style: 'destructive',
        onPress: () => withdrawAsHandler(sess.id).then(() => { haptic('light'); load(); })
          .catch((e) => Alert.alert('철회 실패', (e as Error).message)),
      },
    ]);
  };

  // ---------- R6 — 문제 신고 · SOS (케이스 문은 참가자 전원) ----------
  const doIncident = () => {
    Alert.alert('문제 신고', '무슨 일인가요?', [
      { text: '닫기', style: 'cancel' },
      {
        text: '케이스 접수',
        onPress: () => Alert.prompt?.('케이스 접수', '상황을 한 줄로 적어주세요 — 내 위탁견이 있으면 그 아이의 정산이 보류돼요', [
          { text: '닫기', style: 'cancel' },
          {
            text: '접수',
            onPress: (summary?: string) => {
              if (!summary?.trim()) { Alert.alert('내용이 필요해요'); return; }
              incidentOpen(sess.id, 'S2', summary.trim(), { dog: myDogs[0]?.dogId ?? null })
                .then((id) => { haptic('success'); load(); router.push(`/club/case/${id}`); })
                .catch((e) => Alert.alert('접수 실패', (e as Error).message));
            },
          },
        ]),
      },
      {
        text: '긴급 SOS', style: 'destructive',
        onPress: () => Alert.alert('긴급 SOS', 'S1 케이스가 열리고 호스트와 러너 전원에게 즉시 알림이 가요.', [
          { text: '아직', style: 'cancel' },
          {
            text: 'SOS', style: 'destructive',
            onPress: () => clubSos(sess.id)
              .then((id) => { haptic('success'); router.push(`/club/case/${id}`); })
              .catch((e) => Alert.alert('SOS 실패', (e as Error).message)),
          },
        ]),
      },
    ]);
  };

  // ---------- ④ 채팅 액션 ----------
  const chatReload = () => fetchClubChat(sess.id).then(setChat).catch(() => {});
  const doSend = (body: string, opts: { audience?: 'group' | 'host_channel'; recipient?: string | null } = {}) => {
    const t = body.trim();
    if (!t || busy) return;
    setBusy(true);
    sendClubChat(sess.id, t, opts)
      .then(() => { setDraft(''); setThreadDraft(''); chatReload(); })
      .catch((e) => {
        const m = (e as Error).message;
        Alert.alert('전송 실패', m.includes('rate_limited') ? '잠깐 숨을 고르세요 — 분당 20건이에요' : m);
      })
      .finally(() => setBusy(false));
  };
  const msgActions = (m: ClubChatMsg) => {
    if (m.deleted || m.kind === 'system') return;
    if (m.mine) {
      Alert.alert('내 메시지', undefined, [
        { text: '닫기', style: 'cancel' },
        {
          text: '삭제 (5분 내)', style: 'destructive',
          onPress: () => clubChatDelete(m.id).then(chatReload)
            .catch((e) => Alert.alert('삭제 실패', (e as Error).message.includes('too_late') ? '5분이 지나 삭제할 수 없어요' : (e as Error).message)),
        },
      ]);
    } else {
      Alert.prompt?.('메시지 신고', '사유를 남겨주세요 (선택) — 호스트에게 전달돼요', [
        { text: '닫기', style: 'cancel' },
        {
          text: '신고', style: 'destructive',
          onPress: (reason?: string) => clubChatReport(m.id, reason?.trim() || null)
            .then(() => { haptic('light'); chatReload(); })
            .catch((e) => Alert.alert('신고 실패', (e as Error).message)),
        },
      ]);
    }
  };

  // ④ 파생 — 그룹 스트림 · 호스트 창구 스레드 (스레드 키 = counterpartId)
  const isHostView = access === 'host';
  const groupMsgs = chat?.msgs.filter((m) => m.audience === 'group') ?? [];
  const hostMsgs = chat?.msgs.filter((m) => m.audience === 'host_channel') ?? [];
  const inquiryIds = isHostView ? [...new Set(hostMsgs.map((m) => m.counterpartId).filter(Boolean))] as string[] : [];
  const threadMsgs = hostThread == null ? [] : isHostView ? hostMsgs.filter((m) => m.counterpartId === hostThread) : hostMsgs;
  const nameOf = (pid: string) => hostMsgs.find((m) => m.senderId === pid)?.senderName
    ?? roster?.people.find((p) => p.profileId === pid)?.name ?? '참가자';

  // ④ 말풍선 — 시스템은 가운데 흐리게, 남은 왼쪽, 나는 오른쪽 바이올렛
  const renderMsg = (m: ClubChatMsg) => m.kind === 'system' ? (
    <Text key={m.id} style={s.sysMsg}>{m.body} · {m.when}</Text>
  ) : (
    <Pressable key={m.id} onLongPress={() => msgActions(m)} style={[s.msgRow, m.mine && { alignItems: 'flex-end' }]}>
      {!m.mine && <Text style={s.msgWho}>{m.senderName}</Text>}
      <View style={[s.bb, m.mine && s.bbMine]}>
        <Text style={[s.bbTxt, m.mine && { color: '#fff' }, m.deleted && { fontStyle: 'italic', color: L.dim }]}>
          {m.deleted ? '삭제된 메시지' : m.body}
        </Text>
      </View>
    </Pressable>
  );
  const doPay = async () => {
    const d = payTarget;
    if (!d || busy) return;
    setBusy(true);
    try {
      await payDelegation(d.sdId, `pay-${d.sdId}`); // 멱등키 = sdId 고정 — 재탭·재시도 안전
      haptic('success');
      setPayTarget(null);
      setMethodOk(false);
      load();
      Alert.alert('결제 완료', `${d.dogName}의 자리가 확정됐어요 — 담당 러너가 정해지면 알려드려요`);
    } catch (e) {
      const m = (e as Error).message;
      Alert.alert('결제 실패',
        m.includes('no_capacity') ? '마지막 자리가 먼저 찼어요 — 결제되지 않았어요'
        : m.includes('hold_expired') ? '결제 시간이 지났어요 — 호스트 승인부터 다시 필요해요'
        : m);
    } finally { setBusy(false); }
  };

  // ---------- 위탁 상태 카드 (O3/O4/O6/O7 = 한 카드의 상태들) ----------
  const renderDogCard = (d: DelegationDog) => {
    const stage = d.ui?.primaryStage ?? d.flap; // 서버 프로젝션이 제1언어, 플랩은 풍미
    const crit = d.ui?.severity === 'critical';
    const holdLeft = d.holdExpiresAt ? new Date(d.holdExpiresAt).getTime() - now : null;
    const assigned = d.assignmentState === 'accepted' && !!d.runnerName;
    const hint = STAGE_HINT[d.flap];
    return (
      <View key={d.sdId}>
        <LilacCard hero={!crit} crit={crit}>
          <Text style={clubText.vk}>{d.dogName}의 위탁</Text>
          <Row style={{ alignItems: 'center', gap: 10, marginTop: 8 }}>
            <DogDot name={d.dogName} collar={d.collar} />
            <Text style={[clubText.stateStrong, { flex: 1 }, crit && { color: L.tang }]}>{stage}</Text>
            <Flap state={d.flap} />
          </Row>
          {d.ui?.secondaryBadges && d.ui.secondaryBadges.length > 0 && (
            <Row style={{ gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              {d.ui.secondaryBadges.map((b) => <ClubTag key={b} label={b} tone="dim" />)}
            </Row>
          )}
          {d.ui?.primaryIssue ? (
            <Text style={{ fontSize: 10.5, color: L.tang, marginTop: 8 }}>{d.ui.primaryIssue}</Text>
          ) : hint && !assigned ? (
            <Text style={{ fontSize: 10.5, color: L.dim, marginTop: 8 }}>{hint}</Text>
          ) : null}
        </LilacCard>

        {/* O4 — 승인 → 결제 (앰버 데드라인 + 결제 CTA) */}
        {d.flap === 'HOLDING' && (
          <>
            {holdLeft != null && (
              <View style={s.deadline}>
                <Text style={[{ fontSize: 22, fontWeight: '600', color: L.amber, fontVariant: ['tabular-nums'] }, nf]}>
                  {mmss(holdLeft)}
                </Text>
                <Text style={{ fontSize: 11, color: '#7a5a2a', lineHeight: 16, flex: 1 }}>
                  {holdLeft > 0 ? '안에 결제하면 자리 확정' : '홀드가 끝났어요 — 승인부터 다시 필요할 수 있어요'}
                </Text>
              </View>
            )}
            {fare != null && (
              <BigNumRow items={[
                { v: fare.toLocaleString(), label: '원' },
                ...(board?.session.routeKm ? [{ v: String(board.session.routeKm), unit: 'km', label: board.session.routeName ?? '코스' }] : []),
                { v: String(board?.session.viability?.presentRunners ?? board?.runners.length ?? 0), unit: '명', label: '확약 러너' },
              ]} />
            )}
            <ClubCta label={`${fare != null ? fare.toLocaleString() + '원 ' : ''}결제하기 →`} onPress={() => { setMethodOk(false); setPayTarget(d); }} />
            <Pressable onPress={() => { setMethodOk(false); setPayTarget(d); }}>
              <Text style={s.detailLink}>취소 규정 · 배정 방식 →</Text>
            </Pressable>
          </>
        )}

        {/* O3 — 신청 대기: 무료 취소 (콰이엇) */}
        {d.flap === 'PENDING' && (
          <>
            {fare != null && (
              <BigNumRow items={[
                { v: fare.toLocaleString(), label: '승인 시 가격' },
                ...(board?.session.routeKm ? [{ v: String(board.session.routeKm), unit: 'km', label: board.session.routeName ?? '코스' }] : []),
              ]} />
            )}
            <ClubCta label="신청 취소 (무료)" tone="quiet" onPress={() => doWithdraw(d)} />
          </>
        )}

        {/* O6/O7 — 결제 완료: 배정 대기 or 러너 공개 */}
        {d.flap === 'CLEARED' && (
          <>
            {assigned && (
              <LilacCard>
                <Row style={{ gap: 11, alignItems: 'center' }}>
                  <Avatar url={null} char={d.runnerName![0]} bg="#8f88b8" size={44} />
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>{d.runnerName}</Text>
                    <Text style={{ fontSize: 10, color: L.dim, marginTop: 2 }}>담당 러너 — 수락으로 확정</Text>
                  </View>
                  <ClubTag label="확정" tone="volt" />
                </Row>
                <View style={s.custodyNote}>
                  <Text style={{ fontSize: 10.5, color: L.text }}>인계 확인부터 반환 확인까지 {d.dogName}의 책임자예요</Text>
                </View>
              </LilacCard>
            )}
            {!assigned && fare != null && (
              <View style={s.paidRow}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 12, fontWeight: '800', color: L.head }}>결제 {fare.toLocaleString()}원</Text>
                  <Text style={{ fontSize: 9.5, color: L.dim, marginTop: 1 }}>{sess.when}{board?.session.routeName ? ` · ${board.session.routeName}` : ''}</Text>
                </View>
                <ClubTag label="완료" tone="volt" />
              </View>
            )}
            {/* O8 — 인계 확인 (반환의 거울): 체크인 창이 열려야 인계가 시작된다 */}
            {assigned && board?.session.checkinOpen ? (
              <>
                <View style={s.retcol}>
                  <View style={[s.retside, !!d.runnerConfirmed && s.retsideDone]}>
                    <Text style={s.retMono}>RUNNER {d.runnerName}</Text>
                    <Text style={[s.retWord, !!d.runnerConfirmed && { color: L.voltDeep }]}>{d.runnerConfirmed ? '받았어요 ✓' : '확인 대기'}</Text>
                  </View>
                  <View style={[s.retside, !!d.ownerConfirmed && s.retsideDone]}>
                    <Text style={s.retMono}>OWNER 나</Text>
                    <Text style={[s.retWord, !!d.ownerConfirmed && { color: L.voltDeep }]}>{d.ownerConfirmed ? '맡겼어요 ✓' : '맡겼어요 →'}</Text>
                  </View>
                </View>
                {!d.ownerConfirmed
                  ? <ClubCta label={`${d.runnerName}에게 맡겼어요 — 인계 확인 →`} onPress={() => doHandoff(d)} busy={busy} />
                  : !d.runnerConfirmed && (
                    <Text style={{ fontSize: 10.5, color: L.dim, textAlign: 'center', marginTop: 10 }}>
                      {d.runnerName}의 확인을 기다려요 — 양쪽이 확인하면 책임자가 바뀌어요
                    </Text>
                  )}
              </>
            ) : assigned ? (
              <ClubCta label="집결지에서 인계가 시작돼요" tone="disabled" />
            ) : null}
            <Pressable onPress={() => doCancelPaid(d)}>
              <Text style={s.detailLink}>취소 규정 →</Text>
            </Pressable>
            {assigned && d.objectionUsed === false && (
              <Pressable onPress={() => doObjection(d)}>
                <Text style={[s.detailLink, { color: L.dim, marginTop: 6 }]}>이 배정에 우려가 있어요 (1회)</Text>
              </Pressable>
            )}
          </>
        )}

        {/* O10 — 반환 확인 (인계의 거울): 역할이 뒤집히고 낱말 하나가 바뀐다 */}
        {d.custodyPhase === 'return_pending' && (
          <>
            <View style={s.retcol}>
              <View style={[s.retside, d.runnerReturnConfirmed && s.retsideDone]}>
                <Text style={s.retMono}>RUNNER {d.runnerName ?? ''}</Text>
                <Text style={[s.retWord, d.runnerReturnConfirmed && { color: L.voltDeep }]}>{d.runnerReturnConfirmed ? '반환했어요 ✓' : '반환 대기'}</Text>
              </View>
              <View style={[s.retside, d.ownerReturnConfirmed && s.retsideDone]}>
                <Text style={s.retMono}>OWNER 나</Text>
                <Text style={[s.retWord, d.ownerReturnConfirmed && { color: L.voltDeep }]}>{d.ownerReturnConfirmed ? '인계받았어요 ✓' : '인계받았어요 →'}</Text>
              </View>
            </View>
            {!d.ownerReturnConfirmed
              ? <ClubCta label="인계받았어요 — 반환 확인 →" onPress={() => doReturnConfirm(d)} busy={busy} />
              : !d.runnerReturnConfirmed && (
                <Text style={{ fontSize: 10.5, color: L.dim, textAlign: 'center', marginTop: 10 }}>
                  양쪽이 확인하면 반환이 끝나고 정산 시계가 돌기 시작해요
                </Text>
              )}
          </>
        )}
        {/* O9 — 러닝 중: 실시간 지켜보기 (기존 라이브 화면 재사용 — 보기 전용 문) */}
        {d.bookingStatus === 'active' && d.bookingId && (
          <ClubCta label={`${d.dogName} 실시간 지켜보기 →`}
            onPress={() => { liveDraft.bookingId = d.bookingId!; router.push('/owner/live'); }} />
        )}
        {/* O11(임시 문) — 완료: 기존 리포트 재사용. 골드 실 영수증 인화는 후속 빌드 */}
        {d.flap === 'SETTLED' && d.bookingId && (
          <ClubCta label="오늘의 기록 보기 →" tone="quiet"
            onPress={() => router.push({ pathname: '/owner/report', params: { bid: d.bookingId! } })} />
        )}
        {/* BOARDED/OUTSIDE/REFUND/REFUSED — 상태는 카드가 정직하게 말한다.
            영수증 인화·클럽 전용 러너 런 화면은 후속 빌드. 죽은 버튼은 그리지 않는다. */}
      </View>
    );
  };

  // ---------- 참가자 탭 ----------
  const renderRoster = () => {
    if (access === 'none' || !roster) {
      // 폴백 = 공개 명단 (전화·상세 없음 — 셸 접근이 없으면 사적 정보도 없다)
      return (
        <>
          <View style={s.sechead}><Text style={s.secheadTitle}>사람 {sess.people.length}</Text></View>
          {sess.people.map((p, i) => (
            <View key={i} style={s.drow}>
              <Row style={{ gap: 10, alignItems: 'center' }}>
                <Avatar url={p.avatarUrl} char={p.name[0]} bg="#8f88b8" size={32} />
                <View style={{ flex: 1 }}>
                  <Text style={s.personName}>{p.name}{p.dogName ? ` + ${p.dogName}` : ''}{p.isMe ? ' (나)' : ''}</Text>
                  <Text style={s.personSub}>{ROLE_LINE[p.role] ?? '참가'}{p.attendance === 'checked_in' ? ' · 체크인' : ''}</Text>
                </View>
              </Row>
            </View>
          ))}
        </>
      );
    }
    return (
      <>
        <View style={s.sechead}><Text style={s.secheadTitle}>사람 {roster.people.length}</Text></View>
        {roster.people.map((p) => (
          <View key={p.profileId} style={s.drow}>
            <Row style={{ gap: 10, alignItems: 'center' }}>
              <Avatar url={p.avatarUrl} char={p.name[0]} bg="#8f88b8" size={32} />
              <View style={{ flex: 1 }}>
                <Text style={s.personName}>{p.name}{p.isMe ? ' (나)' : ''}</Text>
                <Text style={s.personSub}>
                  {p.isHost ? '호스트' : ROLE_LINE[p.role ?? ''] ?? '위탁 보호자'}
                  {p.isBackup ? ' · 백업 호스트' : ''}
                  {p.attendance === 'checked_in' ? ' · 체크인' : ''}
                </Text>
              </View>
              {p.isHost ? <ClubTag label="HOST" tone="lilac" />
                : p.phone ? (
                  <View style={s.phoneChip}><Text style={s.phoneChipTxt}>{p.phone}</Text></View>
                ) : !p.isMe ? (
                  <View style={[s.phoneChip, { backgroundColor: L.inset }]}><Text style={[s.phoneChipTxt, { color: L.dim }]}>호스트 경유</Text></View>
                ) : null}
            </Row>
          </View>
        ))}
        {roster.dogs.length > 0 && (
          <>
            <View style={s.sechead}><Text style={s.secheadTitle}>견 {roster.dogs.length}</Text></View>
            {roster.dogs.map((d) => (
              <View key={d.sdId} style={s.drow}>
                <Row style={{ gap: 10, alignItems: 'center' }}>
                  <DogDot name={d.dogName} collar={d.collar} size={30} />
                  <View style={{ flex: 1 }}>
                    <Text style={s.personName}>{d.dogName}{d.isMine ? ' (내 아이)' : ''}</Text>
                    <Text style={s.personSub}>
                      {d.detail
                        ? [
                            d.detail.emergencyContact ? `비상 ${d.detail.emergencyContact}` : null,
                            d.detail.pickupName ? `픽업 ${d.detail.pickupName}` : null,
                            d.detail.vetLimitKrw ? `한도 ${Math.round(d.detail.vetLimitKrw / 10000)}만` : null,
                          ].filter(Boolean).join(' · ') || (d.ownerName ?? '')
                        : `${d.ownerName ?? ''} 보호자`}
                    </Text>
                  </View>
                  {d.chargeLabel && <ClubTag label={CHARGE_LABEL[d.chargeLabel] ?? d.chargeLabel} tone={d.chargeLabel === 'paid' ? 'volt' : 'dim'} />}
                </Row>
              </View>
            ))}
          </>
        )}
        <Text style={s.phoneNotice}>번호가 보이면 열람이 기록돼요</Text>
      </>
    );
  };

  const tabCounts: Record<string, number | null> = { 개요: null, 참가자: sess.people.length, 채팅: null };

  return (
    <DawnCanvas>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        keyboardShouldPersistTaps="handled"
      >
        <ClubMast
          title={`${sess.when} 세션`}
          sub={clubName || 'HIGH CLUB'}
          onBack={() => router.back()}
          right={isDone ? <ClubTag label="DONE" tone="dim" /> : sess.status === 'cancelled' ? <ClubTag label="취소됨" tone="coral" /> : undefined}
        />
        {/* ⑤ 크리티컬 ack — 글래스 크롬 아래, 확인 전까지 따라온다 */}
        <AckStack />

        {/* ---------- 셸 탭 ---------- */}
        <View style={s.shell}>
          {(['개요', '참가자', '채팅'] as const).map((t) => (
            <Pressable key={t} onPress={() => setTab(t)} style={s.shellTab}>
              <Text style={[s.shellTxt, tab === t && { color: L.head }]}>
                {t}{tabCounts[t] != null ? <Text style={{ fontSize: 8, color: L.voltDeep }}>  {tabCounts[t]}</Text> : null}
              </Text>
              {tab === t && <View style={s.shellOn} />}
            </Pressable>
          ))}
        </View>

        {tab === '개요' && (
          <>
            {/* 집결 팩트 */}
            <LilacCard>
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <View style={{ flex: 1 }}>
                  <Text style={clubText.vkDim}>MEET</Text>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: L.head, marginTop: 3 }}>📍 {sess.meetupPoint}</Text>
                  <Text style={{ fontSize: 10.5, color: L.dim, marginTop: 3 }}>
                    호스트 {sess.hostName ?? '—'} · {sess.people.length}팀 / {sess.capacity}
                  </Text>
                </View>
              </Row>
            </LilacCard>

            {/* done 리캡 */}
            {isDone && (
              <LilacCard style={{ alignItems: 'center', paddingVertical: 20 }}>
                <Text style={{ fontSize: 28 }}>🏁</Text>
                <Text style={{ fontSize: 17, fontWeight: '800', color: L.head, marginTop: 6 }}>오늘의 하이클럽</Text>
                <Text style={{ fontSize: 12.5, color: L.text, marginTop: 4 }}>
                  {checkedCount}팀{sess.dogCount > 0 ? ` · ${sess.dogCount}마리` : ''}가 함께 달렸어요
                </Text>
                {sess.nextSessionId && (
                  <ClubCta label="다음 세션 참여하기 →" tone="violet" style={{ alignSelf: 'stretch' }}
                    onPress={() => router.replace({ pathname: `/club/session/${sess.nextSessionId}`, params: { clubName } })} />
                )}
              </LilacCard>
            )}

            {/* ---------- R2 — 나에게 온 배정 제안 (5분 시효, 가장 위) ---------- */}
            {myProposals.map((d) => {
              const left = d.proposalExpiresAt ? new Date(d.proposalExpiresAt).getTime() - now : null;
              return (
                <View key={d.sdId}>
                  {left != null && (
                    <View style={s.deadline}>
                      <Text style={[{ fontSize: 22, fontWeight: '600', color: L.amber, fontVariant: ['tabular-nums'] }, nf]}>{mmss(left)}</Text>
                      <Text style={{ fontSize: 11, color: '#7a5a2a', lineHeight: 16, flex: 1 }}>안에 결정하지 않으면{'\n'}제안이 소멸해요</Text>
                    </View>
                  )}
                  <LilacCard hero>
                    <Text style={clubText.vk}>배정 제안 — 호스트</Text>
                    <Row style={{ gap: 11, alignItems: 'center', marginTop: 8 }}>
                      <DogDot name={d.dogName} collar={d.collar} size={46} />
                      <View style={{ flex: 1 }}>
                        <Text style={{ fontSize: 16, fontWeight: '800', color: L.head }}>{d.dogName}</Text>
                        <Text style={{ fontSize: 10.5, color: L.dim, marginTop: 2 }}>{d.ownerName} 보호자</Text>
                      </View>
                    </Row>
                    <View style={s.custodyNote}>
                      <Text style={{ fontSize: 10.5, color: L.text }}>수락하면 인계부터 반환까지 {d.dogName}의 책임자는 나</Text>
                    </View>
                  </LilacCard>
                  <ClubCta label="이 아이, 내가 맡을게요 →" onPress={() => doAcceptProposal(d)} busy={busy} />
                  <Pressable onPress={() => doDeclineProposal(d)}>
                    <Text style={[s.detailLink, { color: L.dim }]}>우려 제기 · 거절</Text>
                  </Pressable>
                </View>
              );
            })}

            {/* ---------- R3 — 오늘 내 담당 ---------- */}
            {myCharges.length > 0 && (
              <>
                {myCharges.map((d) => {
                  const det = roster?.dogs.find((x) => x.sdId === d.sdId)?.detail ?? null;
                  const needHandoff = !d.runnerConfirmed && board?.session.checkinOpen && d.bookingStatus === 'confirmed';
                  const running = d.bookingStatus === 'active';
                  const needReturn = d.custodyPhase === 'return_pending' && !d.runnerReturnConfirmed;
                  return (
                    <View key={d.sdId} style={s.paidRow}>
                      <DogDot name={d.dogName} collar={d.collar} size={30} />
                      <View style={{ flex: 1 }}>
                        <Text style={{ fontSize: 13.5, fontWeight: '800', color: L.head }}>{d.dogName}</Text>
                        <Text style={{ fontSize: 9.5, color: L.text, marginTop: 1 }}>
                          {[
                            det?.emergencyContact ? `비상 ${det.emergencyContact}` : null,
                            det?.vetLimitKrw ? `한도 ${Math.round(det.vetLimitKrw / 10000)}만` : null,
                          ].filter(Boolean).join(' · ') || `${d.ownerName} 보호자`}
                        </Text>
                        {needHandoff && (
                          <ClubCta label={`${d.dogName} 인계 확인 →`} onPress={() => doRunnerHandoff(d)} busy={busy}
                            style={{ marginTop: 9, paddingVertical: 11 }} />
                        )}
                        {running && (
                          <ClubCta label={`${d.dogName} 러닝 종료 — 완주 →`} onPress={() => doEndRun(d)} busy={busy}
                            style={{ marginTop: 9, paddingVertical: 11 }} />
                        )}
                        {needReturn && (
                          <ClubCta label={`${d.dogName} 반환했어요 →`} onPress={() => doRunnerReturn(d)} busy={busy}
                            style={{ marginTop: 9, paddingVertical: 11 }} />
                        )}
                      </View>
                      {!needHandoff && !running && !needReturn && d.ui?.primaryStage && (
                        <ClubTag label={d.ui.primaryStage} tone={d.ui.severity === 'critical' ? 'coral' : d.ui.severity === 'warn' ? 'amber' : 'volt'} />
                      )}
                    </View>
                  );
                })}
                {board && (
                  <View style={s.paidRow}>
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 12, fontWeight: '800', color: L.head }}>오늘 담당 {myCharges.length}/{board.me.runnerCap}</Text>
                      {myCharges.length >= board.me.runnerCap && (
                        <Text style={{ fontSize: 9.5, color: L.dim, marginTop: 1 }}>가득 찼어요 — 새 제안이 오지 않아요</Text>
                      )}
                    </View>
                    <Flap word={`${myCharges.length}/${board.me.runnerCap}`} />
                  </View>
                )}
                {/* 러닝 시작 — 인계(픽업) 확정된 아이가 있을 때만 (러너 액션) */}
                {myCharges.some((d) => d.bookingStatus === 'picked_up') && (
                  <ClubCta label="러닝 시작 →" tone="violet" onPress={doStartRuns} busy={busy} />
                )}
              </>
            )}

            {/* ---------- 러너 확약 — 인증 러너(cap>0)에게만 문을 그린다 ---------- */}
            {isOpenish && board && !board.me.committed && board.me.runnerCap > 0 && (
              <ClubCta label={`이번 세션 러너로 확약하기 (담당 ${board.me.runnerCap}마리까지)`} tone="violet"
                onPress={doCommit} busy={busy} />
            )}
            {isOpenish && board?.me.committed && myCharges.length === 0 && myProposals.length === 0 && (
              <Pressable onPress={doWithdrawHandler}>
                <Text style={[s.detailLink, { color: L.dim }]}>러너 확약 철회</Text>
              </Pressable>
            )}

            {/* ---------- 내 위탁 카드(들) — 상태 머신 ---------- */}
            {myDogs.map(renderDogCard)}

            {/* ---------- 함께 뛰기 (동반 참가) ---------- */}
            {isOpenish && !sess.joined && (
              <ClubCta
                label={sess.status === 'full' ? '정원이 찼어요' : '함께 뛰기 — 동의하고 참여'}
                onPress={doRsvp}
                disabled={busy || sess.status === 'full'}
                tone={myDogs.length > 0 ? 'quiet' : 'coral'}
              />
            )}
            {isOpenish && sess.joined && sess.myAttendance === 'rsvp' && (
              inCheckinWindow
                ? <ClubCta label="✓ 집결지 도착 체크인" onPress={doCheckin} busy={busy} />
                : <ClubCta label="참여 중 — 취소하려면 탭" tone="quiet" onPress={doCancelRsvp} />
            )}
            {isOpenish && sess.myAttendance === 'checked_in' && (
              <View style={s.checkedCard}>
                <Text style={{ fontSize: 13.5, fontWeight: '800', color: L.accent }}>체크인 완료 — 좋은 러닝 되세요 🐾</Text>
              </View>
            )}

            {/* 입장권 (기존 pass 화면 — 재도색은 후속) */}
            {sess.joined && !isDone && (
              <Pressable onPress={() => router.push({ pathname: `/club/pass/${sess.id}`, params: { clubName: clubName ?? '' } })}>
                <Text style={s.detailLink}>🎟 내 입장권 — 집결지에서 보여주세요</Text>
              </Pressable>
            )}

            {/* 호스트 콘솔 문 — 심사·배정·종료는 콘솔에서 */}
            {sess.isHost && !isDone && (
              <ClubCta label="호스트 콘솔 →" tone="violet"
                onPress={() => router.push({ pathname: `/club/console/${sess.id}`, params: { clubName: clubName ?? '' } })}
                style={{ marginTop: 16 }} />
            )}

            {/* R6 케이스 문 — 조용하지만 항상 있다 (열린 인시던트는 정산을 세운다) */}
            {access !== 'none' && !isDone && (
              <Pressable onPress={doIncident}>
                <Text style={[s.detailLink, { color: L.dim, marginTop: 16 }]}>문제가 생겼나요 — 신고 · SOS</Text>
              </Pressable>
            )}
          </>
        )}

        {tab === '참가자' && renderRoster()}

        {/* ---------- ④ 채팅 — 그룹이 홈, 호스트 창구는 고정 드로어 ---------- */}
        {tab === '채팅' && access === 'none' && (
          <View style={{ alignItems: 'center', paddingVertical: 48 }}>
            <Text style={{ fontSize: 12.5, color: L.dim }}>세션 참가자만 볼 수 있어요</Text>
          </View>
        )}
        {tab === '채팅' && access === 'limited' && (
          // limited(결제 전 신청자) = 호스트 창구만, 전체 화면
          <>
            <LilacCard frame>
              <Row style={{ alignItems: 'center', gap: 7 }}>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: L.head, flex: 1 }}>호스트 창구</Text>
                <View style={s.liveDotSm} />
              </Row>
              <View style={{ marginTop: 6 }}>
                {hostMsgs.length === 0 && <Text style={s.sysMsg}>궁금한 게 있으면 호스트에게 바로 물어보세요</Text>}
                {hostMsgs.map(renderMsg)}
              </View>
            </LilacCard>
            {writable ? (
              <Row style={s.inputbar}>
                <TextInput value={draft} onChangeText={setDraft} placeholder="호스트에게 문의..." placeholderTextColor={L.dim}
                  style={s.inputField} multiline />
                <Pressable onPress={() => doSend(draft, { audience: 'host_channel' })} style={s.sendBtn}>
                  <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>전송</Text>
                </Pressable>
              </Row>
            ) : (
              <Text style={s.closedLine}>채팅이 닫혔어요</Text>
            )}
            <Text style={[clubText.dim, { textAlign: 'center', marginTop: 9 }]}>결제하면 그룹 채팅이 열려요</Text>
          </>
        )}
        {tab === '채팅' && (access === 'full' || access === 'host') && (
          <>
            {/* 고정 드로어 — 호스트: 열린 문의 · 참가자: 내 1:1 문 */}
            {isHostView ? (
              inquiryIds.length > 0 && (
                <LilacCard frame>
                  <Row style={{ alignItems: 'center', gap: 7 }}>
                    <Text style={{ fontSize: 12.5, fontWeight: '800', color: L.head, flex: 1 }}>호스트 창구 — 문의 {inquiryIds.length}건</Text>
                    <View style={s.liveDotSm} />
                  </Row>
                  {inquiryIds.map((pid) => {
                    const last = [...hostMsgs].reverse().find((m) => m.counterpartId === pid);
                    return (
                      <Pressable key={pid} onPress={() => setHostThread(pid)} style={{ marginTop: 6 }}>
                        <Text style={{ fontSize: 10.5, color: L.text }} numberOfLines={1}>
                          {nameOf(pid)}: “{last?.deleted ? '삭제된 메시지' : last?.body ?? ''}” <Text style={{ color: L.accent, fontWeight: '800' }}>→ 탭해서 1:1</Text>
                        </Text>
                      </Pressable>
                    );
                  })}
                </LilacCard>
              )
            ) : (
              <Pressable onPress={() => setHostThread('me')}>
                <LilacCard frame>
                  <Row style={{ alignItems: 'center', gap: 7 }}>
                    <Text style={{ fontSize: 12.5, fontWeight: '800', color: L.head, flex: 1 }}>호스트 창구</Text>
                    {hostMsgs.length > 0 && <View style={s.liveDotSm} />}
                  </Row>
                  <Text style={{ fontSize: 10.5, color: L.text, marginTop: 5 }} numberOfLines={1}>
                    {hostMsgs.length > 0
                      ? `${hostMsgs[hostMsgs.length - 1].mine ? '나' : hostMsgs[hostMsgs.length - 1].senderName}: “${hostMsgs[hostMsgs.length - 1].deleted ? '삭제된 메시지' : hostMsgs[hostMsgs.length - 1].body}”`
                      : '호스트에게 1:1로 문의하기'} <Text style={{ color: L.accent, fontWeight: '800' }}>→</Text>
                  </Text>
                </LilacCard>
              </Pressable>
            )}

            {/* 그룹 스트림 */}
            <View style={{ marginTop: 8 }}>
              {groupMsgs.length === 0 && chat != null && (
                <Text style={s.sysMsg}>아직 메시지가 없어요 — 첫 인사를 남겨보세요</Text>
              )}
              {groupMsgs.map(renderMsg)}
            </View>
            {writable ? (
              <Row style={s.inputbar}>
                <TextInput value={draft} onChangeText={setDraft} placeholder="메시지..." placeholderTextColor={L.dim}
                  style={s.inputField} multiline />
                <Pressable onPress={() => doSend(draft)} style={s.sendBtn}>
                  <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>전송</Text>
                </Pressable>
              </Row>
            ) : (
              <Text style={s.closedLine}>채팅이 닫혔어요 — 세션 뒤 24시간까지, 열린 케이스가 있으면 그동안은 계속 열려요</Text>
            )}
          </>
        )}
      </ScrollView>

      {/* ---------- O5 — 결제 시트 (법적 문장의 자리) ---------- */}
      <Modal visible={!!payTarget} transparent animationType="slide" onRequestClose={() => setPayTarget(null)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.45)' }} onPress={() => setPayTarget(null)} />
        <View style={s.sheet}>
          <View style={s.grab} />
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>{payTarget?.dogName} 위탁 결제</Text>
            {fare != null && (
              <Text style={[{ fontSize: 22, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] }, nf]}>
                {fare.toLocaleString()}
              </Text>
            )}
          </Row>
          {/* 규칙 7이 카드에서 옮겨온 두 문장 — 법적으로 묶이는 순간에만 등장 */}
          <Pressable onPress={() => setMethodOk((v) => !v)} style={s.legal}>
            <View style={[s.chk, methodOk && { backgroundColor: L.coral }]}>
              {methodOk && <Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>✓</Text>}
            </View>
            <Text style={s.legalTxt}>
              담당 러너는 <Text style={{ fontWeight: '800', color: L.head }}>집결지에서 호스트가 제안하고 러너가 수락</Text>하면 정해져요 — 이 방식에 동의해요
            </Text>
          </Pressable>
          <View style={[s.legal, { marginTop: 7 }]}>
            <View style={[s.chk, { backgroundColor: L.dim }]}>
              <Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>✓</Text>
            </View>
            <Text style={s.legalTxt}>
              시작 <Text style={{ fontWeight: '800', color: L.head }}>24시간 전까지 무료 취소</Text> · 이후 10% · 배정 수락 후 20%
            </Text>
          </View>
          <ClubCta label="동의하고 결제 →" onPress={doPay} disabled={!methodOk} busy={busy} />
        </View>
      </Modal>

      {/* ---------- ④ 호스트 창구 1:1 시트 (드로어가 길어지면 시트로 확장) ---------- */}
      <Modal visible={hostThread != null} transparent animationType="slide" onRequestClose={() => setHostThread(null)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.45)' }} onPress={() => setHostThread(null)} />
        <View style={[s.sheet, { maxHeight: '75%' }]}>
          <View style={s.grab} />
          <Text style={{ fontSize: 14.5, fontWeight: '800', color: L.head }}>
            호스트 창구{isHostView && hostThread ? ` — ${nameOf(hostThread)}` : ''}
          </Text>
          <ScrollView style={{ marginTop: 8 }} keyboardShouldPersistTaps="handled">
            {threadMsgs.length === 0 && <Text style={s.sysMsg}>아직 대화가 없어요</Text>}
            {threadMsgs.map(renderMsg)}
          </ScrollView>
          {writable ? (
            <Row style={s.inputbar}>
              <TextInput value={threadDraft} onChangeText={setThreadDraft} placeholder="메시지..." placeholderTextColor={L.dim}
                style={s.inputField} multiline />
              <Pressable
                onPress={() => doSend(threadDraft, { audience: 'host_channel', recipient: isHostView && hostThread !== 'me' ? hostThread : undefined })}
                style={s.sendBtn}>
                <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>전송</Text>
              </Pressable>
            </Row>
          ) : (
            <Text style={s.closedLine}>채팅이 닫혔어요</Text>
          )}
        </View>
      </Modal>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  shell: { flexDirection: 'row', borderBottomWidth: 1, borderBottomColor: L.hair2, marginTop: 8 },
  shellTab: { flex: 1, alignItems: 'center', paddingVertical: 9 },
  shellTxt: { fontSize: 11.5, fontWeight: '800', color: L.dim },
  shellOn: { position: 'absolute', left: '28%', right: '28%', bottom: -1, height: 2.5, backgroundColor: L.accent, borderRadius: 2 },
  deadline: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: L.amberSoft, borderRadius: lilacRadius.inner, padding: 11, paddingHorizontal: 13, marginTop: 10,
  },
  detailLink: { textAlign: 'center', marginTop: 11, fontSize: 11, fontWeight: '800', color: L.accent },
  custodyNote: { backgroundColor: L.inset, borderRadius: lilacRadius.inner, padding: 9, paddingHorizontal: 10, marginTop: 10 },
  paidRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 11, marginTop: 8,
  },
  checkedCard: {
    backgroundColor: L.hair2, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 13, marginTop: 12,
  },
  // 양측 확인 (O8 인계 ↔ O10 반환 — 같은 부품, 역할만 거울)
  retcol: { flexDirection: 'row', gap: 9, marginTop: 11 },
  retside: { flex: 1, borderRadius: lilacRadius.inner, paddingVertical: 11, paddingHorizontal: 8, alignItems: 'center', backgroundColor: L.inset },
  retsideDone: { backgroundColor: L.voltFill },
  retMono: { fontSize: 7.5, fontWeight: '700', letterSpacing: 1.5, color: L.dim },
  retWord: { fontSize: 12, fontWeight: '800', color: L.head, marginTop: 4 },
  sechead: {
    flexDirection: 'row', alignItems: 'center', marginTop: 14, paddingBottom: 6,
    borderBottomWidth: 1, borderBottomColor: L.hair2,
  },
  secheadTitle: { fontSize: 12.5, fontWeight: '800', color: L.head },
  drow: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 11, marginTop: 8,
  },
  personName: { fontSize: 13.5, fontWeight: '800', color: L.head },
  personSub: { fontSize: 9.5, color: L.text, marginTop: 1 },
  phoneChip: { backgroundColor: L.voltFill, borderRadius: lilacRadius.tag, paddingVertical: 5, paddingHorizontal: 9 },
  phoneChipTxt: { fontSize: 9.5, fontWeight: '700', color: L.voltDeep, fontVariant: ['tabular-nums'] },
  phoneNotice: { fontSize: 9.5, color: L.dim, marginTop: 10, textAlign: 'center' },
  sheet: {
    backgroundColor: L.bg, borderTopLeftRadius: lilacRadius.screen, borderTopRightRadius: lilacRadius.screen,
    padding: 16, paddingBottom: 34,
  },
  grab: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: L.hair, marginBottom: 12 },
  legal: {
    flexDirection: 'row', gap: 9, alignItems: 'flex-start',
    backgroundColor: L.card, borderRadius: lilacRadius.inner, borderWidth: 1, borderColor: L.hair,
    padding: 11, marginTop: 12,
  },
  chk: {
    width: 18, height: 18, borderRadius: 5, borderWidth: 1.5, borderColor: L.hair,
    backgroundColor: L.inset, alignItems: 'center', justifyContent: 'center', marginTop: 1,
  },
  legalTxt: { flex: 1, fontSize: 11, color: L.text, lineHeight: 16.5 },
  // ④ 채팅 — 말풍선 문법 (시스템 가운데 · 남 왼쪽 · 나 오른쪽 바이올렛)
  sysMsg: { fontSize: 9.5, color: L.dim, textAlign: 'center', marginTop: 10 },
  msgRow: { marginTop: 9, alignItems: 'flex-start' },
  msgWho: { fontSize: 8.5, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginBottom: 3, marginLeft: 2 },
  bb: {
    maxWidth: '82%', backgroundColor: L.card, borderWidth: 1, borderColor: L.hair,
    borderRadius: 10, borderTopLeftRadius: 3, paddingVertical: 8, paddingHorizontal: 11,
  },
  bbMine: {
    backgroundColor: L.accent, borderColor: L.accent,
    borderTopLeftRadius: 10, borderTopRightRadius: 3,
  },
  bbTxt: { fontSize: 11.5, lineHeight: 16.5, color: L.text },
  inputbar: {
    gap: 8, marginTop: 12, alignItems: 'flex-end',
    backgroundColor: L.glass, borderWidth: 1, borderColor: L.glassEdge,
    borderRadius: 10, padding: 7,
  },
  inputField: {
    flex: 1, backgroundColor: '#fff', borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.btn,
    paddingVertical: 8, paddingHorizontal: 12, fontSize: 12, color: L.head, maxHeight: 90,
  },
  sendBtn: {
    backgroundColor: L.accent, borderRadius: lilacRadius.btn, paddingVertical: 10, paddingHorizontal: 13,
  },
  closedLine: { fontSize: 10, color: L.dim, textAlign: 'center', marginTop: 12, lineHeight: 15 },
  liveDotSm: {
    width: 8, height: 8, borderRadius: 4, backgroundColor: L.coral,
    shadowColor: L.coral, shadowOpacity: 0.4, shadowRadius: 4, elevation: 2,
  },
});
