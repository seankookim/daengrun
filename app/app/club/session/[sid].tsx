import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Image, Linking, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Avatar, Icon, Row } from '../../../src/components/ui';
import { AckStack } from '../../../src/components/club-acks';
import {
  BigNumRow, ClubCta, ClubMast, ClubTag, DawnCanvas, Flap, LilacCard, LoadGate, clubText,
} from '../../../src/components/club-ui';
import { DrainRing } from '../../../src/components/drainring';
import {
  cancelClubRsvp, cancelDelegation, checkinClubSession, ClubChatMsg, clubChatDelete, clubChatReport,
  ClubSessionDetail, commitAsHandler, confirmHandoff, confirmReturn, DelegationBoard, DelegationDog,
  fetchChatWritable, fetchClubChat, fetchClubSession, fetchDelegationBoard, fetchMyDogs, fetchSessionRoster,
  clubSos, fetchShellAccess, incidentOpen, ownerObjection, payDelegation, respondProposal,
  rsvpClubSession, sendClubChat, sendClubChatPhoto, SessionRoster, ShellAccess, startDelegatedRuns,
  subscribeClubChat, withdrawAsHandler,
} from '../../../src/lib/api'; // finishClubSession=콘솔 · settleRun/fetchRunStartedAt=클럽 런 화면
import { draft as liveDraft } from '../../../src/store'; // 라이브 화면 진입 키 (챗 draft 상태와 이름 충돌 주의)
import { getTrackPermission, resetTrace, startTracking } from '../../../src/lib/geo';
import { MediaImage } from '../../../src/lib/media';
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
  // [정직 2026-08-11] '결제 완료'는 청구가 일어났다는 주장이다. 모의 결제 시대엔 거짓 —
  // 리포에 PG 연동이 없고 서버도 '모의 시대: 청구 없음'이라 적는다 (0057:250).
  paid: '자리 확정', pending_payment: '결제 대기', refunded: '환불', refund_pending: '환불 진행',
};

const WAIVER =
  '동반 참가 안내\n\n· 내 강아지의 안전과 행동은 세션 내내 보호자 본인이 책임져요\n· 리드줄 착용은 필수예요\n· 다른 참가자·강아지에게 공격성이 보이면 호스트 안내에 따라 거리를 둬요\n· 사진 촬영이 있을 수 있어요 (공개는 동의한 사진만)';

// ④ 링 드레인 창 길이 — 전부 서버 정본이다 (지어낸 창은 그리지 않는다)
const PROPOSAL_MS = 5 * 60_000;    // 0047/0048 propose: proposal_expires_at = now() + 5 minutes
const HOLD_MS = 20 * 60_000;       // 0043 approve: hold_expires_at = now() + 20 minutes
const CHECKIN_MS = 8 * 3600_000;   // 0030 session_checkin 창 = 시작 −2h ~ +6h (총 8시간)

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
  // [감사 P0] Alert.prompt는 iOS 전용 — 안드로이드에서 무반응 죽은 버튼. 공용 텍스트 시트로 대체.
  const [askText, setAskText] = useState<null | {
    title: string; message: string;
    actions: { label: string; destructive?: boolean; onSubmit: (text: string) => void }[];
    requireText: boolean;
  }>(null);
  const [askDraft, setAskDraft] = useState('');
  const openPrompt = (
    title: string, message: string,
    actions: { label: string; destructive?: boolean; onSubmit: (text: string) => void }[],
    requireText = true,
  ) => { setAskDraft(''); setAskText({ title, message, actions, requireText }); };
  // ④ 채팅 — 그룹 스트림 + 호스트 창구 드로어
  const [chat, setChat] = useState<{ uid: string | null; msgs: ClubChatMsg[] } | null>(null);
  const [writable, setWritable] = useState(true);
  const [draft, setDraft] = useState('');
  const [hostThread, setHostThread] = useState<string | null>(null); // 열린 1:1 상대 (호스트: 신청자 id · 참가자: 'me')
  const [threadDraft, setThreadDraft] = useState('');

  // [honesty P1 2026-08-11] 세션 실패가 앱 대표 딥링크에서 영원한 '불러오는 중...'(백 없음)
  // 이던 것 — LoadGate 3상태 + 돌아가기 상시. 직전 실값은 유지.
  const [sessErr, setSessErr] = useState(false);
  const load = useCallback(() => {
    if (!sid) return;
    setSessErr(false);
    fetchClubSession(sid).then(setSess).catch(() => setSessErr(true));
    // [감사 P1] 일시적 네트워크 오류가 board=null·access='none'으로 리셋해 카드·버튼이 전멸하던 것 —
    // 실패 시 이전 상태 유지 (access='none'은 서버가 실제로 준 값일 때만)
    fetchDelegationBoard(sid).then(setBoard).catch(() => {});
    fetchShellAccess(sid).then(setAccess).catch(() => {});
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  // 로스터 — [감사 P2] 서버가 규칙 B 대상 전원의 '열람 로그'를 남기므로, 실제로 번호가 쓰이는
  // 시점에만 부른다: 참가자 탭 진입, 또는 러너(비상 연락처 필요). limited는 사람 명단을 그리지 않는다.
  useEffect(() => {
    if (!sid || access === 'none' || access === 'limited') return;
    const needForRunner = board?.me.committed === true;
    if (tab === '참가자' || needForRunner) {
      fetchSessionRoster(sid).then(setRoster).catch(() => {});
    }
  }, [tab, access, sid, board?.me.committed]);

  // ④ 채팅 로드 + 리얼타임 — 탭이 열려 있는 동안만 구독.
  // [감사 P2] INSERT마다 전체 재조회라 응답 역순 도착 시 옛 스냅샷이 최신을 덮던 것 — seq 가드로 최신만 반영.
  const chatSeq = useRef(0);
  const applyChat = useCallback((run: () => Promise<{ uid: string | null; msgs: ClubChatMsg[] }>) => {
    const my = ++chatSeq.current;
    run().then((c) => { if (my === chatSeq.current) setChat(c); }).catch(() => {});
  }, []);
  useEffect(() => {
    if (tab !== '채팅' || access === 'none' || !sid) return;
    const reload = () => applyChat(() => fetchClubChat(sid));
    reload();
    fetchChatWritable(sid).then(setWritable).catch(() => {});
    return subscribeClubChat(sid, reload);
  }, [tab, access, sid, applyChat]);

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
  // [감사 P2] 체크인 창 판정이 렌더 시점에 얼어 버튼이 제때 안 나타나던 것 — 참여 중이면 30초 저빈도 틱
  const joinedWaiting = sess?.joined === true && sess?.myAttendance === 'rsvp';
  useEffect(() => {
    if (!joinedWaiting || ticking) return;
    const t = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(t);
  }, [joinedWaiting, ticking]);

  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setTimeout(() => setRefreshing(false), 400)); };

  if (!sess) {
    return (
      <LoadGate
        mode={sessErr ? 'error' : 'loading'}
        errorLabel="세션을 불러오지 못했어요"
        onRetry={load}
        onBack={() => router.back()}
      />
    );
  }

  const startMs = new Date(sess.scheduledAt).getTime();
  const inCheckinWindow = Date.now() >= startMs - 2 * 3600_000 && Date.now() <= startMs + 6 * 3600_000;
  // ④ 체크인 창의 '닫히는 쪽' — 서버 규칙(0030)이 준 실시각. 위 30초 저빈도 틱이 곧 이 링의 프레임이다.
  const checkinLeftMs = startMs + 6 * 3600_000 - now;
  const isDone = sess.status === 'done';
  const isOpenish = sess.status === 'open' || sess.status === 'full';
  const checkedCount = sess.people.filter((p) => p.attendance === 'checked_in').length;
  // [0052 §2] people는 당사자에게만 채워진다 — 인원수는 서버 peopleCount가 정본.
  // (db push 전 원격에선 undefined → 예전대로 명단 길이)
  const peopleCount = sess.peopleCount ?? sess.people.length;
  const fare = board?.session.fare ?? null;

  // ---------- 함께 뛰기 (동반 참가) 액션 ----------
  const rsvpWith = async (dogId: string | null) => {
    setBusy(true);
    try {
      await rsvpClubSession(sess.id, dogId);
      haptic('success');
      load();
    } catch (e) {
      const m = (e as Error).message;
      Alert.alert('참여 실패',
        m.includes('session_full') ? '정원이 찼어요'
        : m.includes('already_joined') ? '이미 참여 중이에요'
        : m.includes('dog_capacity_full') ? '이 세션의 강아지 정원이 다 찼어요'
        : m.includes('already_registered') ? '이 아이는 이미 위탁으로 등록돼 있어요' : m);
    } finally { setBusy(false); }
  };
  const doRsvp = () => {
    Alert.alert('참여 전 확인', WAIVER, [
      { text: '취소', style: 'cancel' },
      {
        text: '동의하고 참여',
        onPress: async () => {
          const dogs = await fetchMyDogs().catch(() => []);
          // [감사 P2] 다견인데 무조건 dogs[0]으로 RSVP되던 것 — 2마리 이상이면 고른다
          if (dogs.length > 1) {
            Alert.alert('어느 아이와 뛰나요?', undefined, [
              { text: '닫기', style: 'cancel' },
              ...dogs.slice(0, 3).map((d) => ({ text: d.name, onPress: () => rsvpWith(d.id) })),
            ]);
          } else {
            rsvpWith(dogs[0]?.id ?? null);
          }
        },
      },
    ]);
  };
  const doCancelRsvp = () => {
    // [감사 P1] session_cancel_rsvp는 이 세션의 내 session_dogs를 custody 구분 없이 지운다 —
    // 진행 중 위탁이 있으면 참여 취소로 위탁(동의서·결제 기록 포함)이 함께 사라진다. 문에서 막는다.
    // [리뷰 P2] flap='REFUSED'는 refundState가 approval보다 먼저라 환불 중 종료건을 놓친다 —
    // 서버 가드(0052 §3)와 동일하게 serviceState='ended' 기준 (종료건은 서버가 취소를 허용한다)
    const activeDeleg = myDogs.filter((d) => d.serviceState !== 'ended');
    if (activeDeleg.length > 0) {
      Alert.alert('위탁이 진행 중이에요',
        `${activeDeleg.map((d) => d.dogName).join('·')}의 위탁이 이 세션에 걸려 있어요.\n참여 취소는 위탁 기록까지 지워요 — 위탁 취소를 먼저 해주세요.`);
      return;
    }
    Alert.alert('참여 취소', '이번 세션 참여를 취소할까요?', [
      { text: '유지', style: 'cancel' },
      {
        text: '취소하기', style: 'destructive',
        onPress: () => cancelClubRsvp(sess.id).then(load).catch((e) => {
          const m = (e as Error).message;
          // [0052 §3] 서버도 활성 위탁이면 거부한다 (delegation_active) — 문 앞 가드가 새도 정직하게 말한다
          Alert.alert('취소 실패',
            m.includes('delegation_active') ? '위탁이 걸려 있어요 — 위탁 취소를 먼저 해주세요'
            : m.includes('host_cannot_leave') ? '호스트는 참여를 취소할 수 없어요'
            : m.includes('not_joined') ? '참여 중이 아니에요'
            : m);
        }),
      },
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
      {
        text: '신청 취소', style: 'destructive',
        onPress: () => cancelDelegation(d.sdId).then(() => { haptic('light'); load(); }).catch((e) => {
          const m = (e as Error).message;
          Alert.alert('취소 실패', m.includes('incident') ? '진행 중인 케이스가 있어 지금은 취소할 수 없어요' : m.includes('already_ended') ? '이미 종료된 신청이에요' : m);
        }),
      },
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
  // 이의 — [감사 P1] preference(T-20까지·1회)와 safety(인계 전까지 무제한)를 분리. 안전 문은 닫히지 않는다.
  const submitObjection = (d: DelegationDog, kind: 'preference' | 'safety', reason: string, wantRefund: boolean) =>
    ownerObjection(d.sdId, kind, reason, wantRefund).then(() => { haptic('light'); load(); })
      .catch((e) => {
        const m = (e as Error).message;
        Alert.alert('접수 실패',
          m.includes('objection_window_closed') ? '시작 20분 전까지만 낼 수 있어요'
          : m.includes('objection_already_used') ? '이의는 한 번만 낼 수 있어요'
          : m.includes('already_handed_off') ? '인계 후에는 이의 대신 문제 신고를 이용해주세요'
          : m);
      });
  const doObjection = (d: DelegationDog, kind: 'preference' | 'safety') => {
    openPrompt(
      kind === 'safety' ? '안전 우려 제기' : '배정 이의 (1회)',
      kind === 'safety'
        ? '안전 우려는 인계 전까지 언제든 낼 수 있어요 — 사유를 적어주세요.'
        : '우려 사유를 적어주세요 — 시작 20분 전까지, 한 번만 낼 수 있어요.',
      [
        { label: '재배정 요청', onSubmit: (t) => submitObjection(d, kind, t, false) },
        { label: '전액 환불로 취소', destructive: true, onSubmit: (t) => submitObjection(d, kind, t, true) },
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
    openPrompt('우려 제기 · 거절', '사유를 남기면 호스트가 재배정에 참고해요 (선택)', [
      {
        label: '거절', destructive: true,
        onSubmit: (reason) => respondProposal(d.sdId, false, reason || undefined)
          .then(() => { haptic('light'); load(); })
          .catch((e) => {
            const m = (e as Error).message;
            Alert.alert('거절 실패', m.includes('expired') || m.includes('not_pending') ? '제안이 이미 소멸했어요' : m);
          }),
      },
    ], false);
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
  // 러닝 시작 = 러너 액션 (서버: 내 픽업 부킹만) — 시작 즉시 러닝 화면으로 (GPS·트레이스·종료는 거기서)
  // Background-GPS start gate — the SAME hard block as the 1:1 run screen (runner/run.tsx
  // startRun, Sean 2026-08-08: a run may not start without continuous tracking). Club runs used
  // to start ungated because the start lives here, not on the run screen. The probe learns the
  // real TrackMode the run screen would get; anything short of 'background' blocks the start
  // BEFORE startDelegatedRuns marks anything server-side. Copy below is the 1:1 screen's
  // discriminated-mode vocabulary verbatim (blockStrip + rationale sheet) — no second vocabulary.
  // Re-entry to an in-progress run does NOT pass through here (the '러닝 화면' CTA routes straight
  // to /club/run), so this gate cannot strand a session that already started.
  const gateThenStart = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const h = await startTracking(() => {}, { dogName: myCharges.map((d) => d.dogName).join('·') });
      await h.stop();
      // The probe may have pushed fixes into the shared trace buffer; a dirty buffer would make
      // the run screen skip its server-trace hydration (its P0: truncated trace = short payout).
      resetTrace();
      if (h.mode !== 'background') {
        if (h.mode === 'denied') {
          Alert.alert('러닝을 시작할 수 없어요', '위치 권한이 꺼져 있어요 — 거리를 잴 수도, 정산할 수도 없어요', [
            { text: '닫기', style: 'cancel' },
            { text: '설정 열기', onPress: () => { Linking.openSettings().catch(() => {}); } },
          ]);
        } else if (h.mode === 'foreground') {
          Alert.alert('러닝을 시작할 수 없어요', '앱을 켜 둔 동안만 기록돼요 — 화면이 꺼지면 거리가 멈춰요 · 새 빌드에서 러닝을 시작할 수 있어요');
        } else {
          Alert.alert('러닝을 시작할 수 없어요', '위치 기능이 없는 빌드예요 — 새 빌드에서 기록돼요');
        }
        return;
      }
      await startDelegatedRuns(sess.id);
      haptic('success'); load();
      router.push({ pathname: `/club/run/${sess.id}`, params: { clubName: clubName ?? '' } });
    } catch (e) {
      Alert.alert('시작 실패', (e as Error).message.includes('nothing_to_start') ? '인계 확인이 끝난 아이가 아직 없어요' : (e as Error).message);
    } finally { setBusy(false); }
  };
  const doStartRuns = () => {
    Alert.alert('러닝 시작', '인계받은 아이들의 러닝 트랙이 시작돼요.', [
      { text: '아직', style: 'cancel' },
      {
        text: '시작',
        onPress: async () => {
          // The OS location sheet is one-shot — say why first (1:1 rationale copy verbatim).
          const perm = await getTrackPermission().catch(() => 'unavailable' as const);
          if (perm === 'undetermined') {
            Alert.alert(
              '러닝 거리는 위치로 재요',
              '주머니에 넣거나 화면이 꺼져도 거리와 경로가 계속 기록돼요. 이 거리가 보호자에게 보이는 기록이자 정산 기준이에요.\n러닝을 종료하면 기록도 함께 멈춰요.',
              [
                { text: '나중에', style: 'cancel' },
                { text: '위치 허용하기', onPress: () => { gateThenStart(); } },
              ],
            );
            return;
          }
          gateThenStart();
        },
      },
    ]);
  };
  const doCommit = () => {
    commitAsHandler(sess.id).then(() => { haptic('success'); load(); })
      .catch((e) => {
        const m = (e as Error).message;
        Alert.alert('확약 실패',
          m.includes('not_certified') ? '인증 러너만 확약할 수 있어요'
          : m.includes('format_closed') ? '이 세션은 위탁을 받지 않아요 — 보호자 동반 전용이에요'
          : m.includes('session_full') ? '세션 정원이 찼어요' : m);
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
  // [감사 P1] 대상견 자동 myDogs[0]은 다견 보호자의 엉뚱한 아이에게 보류를 걸었다 — 2마리 이상이면 고른다
  const openCase = (dogId: string | null, dogName: string | null) => {
    openPrompt('케이스 접수',
      dogName ? `${dogName} 대상 케이스 — 이 아이의 정산이 해소까지 보류돼요. 상황을 한 줄로 적어주세요.`
        : '상황을 한 줄로 적어주세요.',
      [{
        label: '접수',
        onSubmit: (summary) => incidentOpen(sess.id, 'S2', summary, { dog: dogId })
          .then((id) => { haptic('success'); load(); router.push(`/club/case/${id}`); })
          .catch((e) => Alert.alert('접수 실패', (e as Error).message)),
      }]);
  };
  const doIncident = () => {
    Alert.alert('문제 신고', '무슨 일인가요?', [
      { text: '닫기', style: 'cancel' },
      {
        text: '케이스 접수',
        onPress: () => {
          const candidates = myDogs.filter((d) => d.flap !== 'REFUSED');
          if (candidates.length > 1) {
            Alert.alert('어느 아이 일인가요?', undefined, [
              { text: '닫기', style: 'cancel' },
              ...candidates.slice(0, 3).map((d) => ({ text: d.dogName, onPress: () => openCase(d.dogId, d.dogName) })),
              { text: '세션 전체', onPress: () => openCase(null, null) },
            ]);
          } else {
            openCase(candidates[0]?.dogId ?? null, candidates[0]?.dogName ?? null);
          }
        },
      },
      {
        text: '긴급 SOS', style: 'destructive',
        // [C3 / 0067] 세션 SOS는 대상견을 붙이지 않는다 — 풀린 개·싸움·사람이 쓰러진 상황엔
        // 대상견이 없고, 아무 아이나 붙이면 무관한 러너의 정산에 보류가 떨어진다. 그래서 카피는
        // 지급 보류를 약속하지 않고, 아이 건이면 '케이스 접수'로 지정하라고 길을 준다.
        onPress: () => Alert.alert('긴급 SOS', 'S1 케이스가 열리고 호스트와 러너 전원에게 즉시 알림이 가요. 특정 아이 일이면 위 케이스 접수로 아이를 지정하세요 — 그래야 그 아이 정산도 함께 보류돼요.', [
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
  const chatReload = () => applyChat(() => fetchClubChat(sess.id)); // [감사 P2] seq 가드 공유
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
  // 사진 메시지 — 카메라 우선, 미허용 시 갤러리 (러닝 사진 문법 그대로)
  const doSendPhoto = async (opts: { audience?: 'group' | 'host_channel'; recipient?: string | null } = {}) => {
    if (busy) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch { Alert.alert('개발 빌드 업데이트 필요', '카메라는 새 빌드에 포함돼요'); return; }
    try {
      const camPerm = await ImagePicker.requestCameraPermissionsAsync().catch(() => ({ granted: false }));
      let res: any = null;
      if (camPerm.granted) {
        res = await ImagePicker.launchCameraAsync({ quality: 0.5, base64: true });
      } else {
        const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
        if (!perm.granted) return;
        res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.5, base64: true, selectionLimit: 1 });
      }
      if (!res || res.canceled || !res.assets?.[0]?.base64) return;
      setBusy(true);
      await sendClubChatPhoto(sess.id, res.assets[0].base64 as string, opts);
      haptic('light');
      chatReload();
    } catch (e) {
      const m = (e as Error).message;
      Alert.alert('사진 전송 실패', m.includes('rate_limited') ? '잠깐 숨을 고르세요 — 분당 20건이에요' : m);
    } finally { setBusy(false); }
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
      openPrompt('메시지 신고', '사유를 남겨주세요 (선택) — 호스트에게 전달돼요', [
        {
          label: '신고', destructive: true,
          onSubmit: (reason) => clubChatReport(m.id, reason || null)
            .then(() => { haptic('light'); Alert.alert('신고 접수', '호스트가 확인할 거예요'); chatReload(); })
            .catch((e) => Alert.alert('신고 실패', (e as Error).message)),
        },
      ], false);
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

  // ④ 말풍선 — 시스템은 가운데 흐리게, 남은 왼쪽, 나는 오른쪽 바이올렛. 사진은 사진답게 (콘텐츠)
  const renderMsg = (m: ClubChatMsg) => m.kind === 'system' ? (
    <Text key={m.id} style={s.sysMsg}>{m.body} · {m.when}</Text>
  ) : (
    <Pressable key={m.id} onLongPress={() => msgActions(m)} style={[s.msgRow, m.mine && { alignItems: 'flex-end' }]}>
      {!m.mine && <Text style={s.msgWho}>{m.senderName}</Text>}
      {m.kind === 'photo' && !m.deleted && m.mediaPath ? (
        /* [0064] media_path is a private-bucket path, not a URL — MediaImage signs it and
           renders expiry as an explicit failure. A raw <Image> here would render broken. */
        <MediaImage source={m.mediaPath} style={s.bbPhoto} resizeMode="cover" />
      ) : (
        <View style={[s.bb, m.mine && s.bbMine]}>
          <Text style={[s.bbTxt, m.mine && { color: '#fff' }, m.deleted && { fontStyle: 'italic', color: L.dim }]}>
            {m.deleted ? '삭제된 메시지' : m.body}
          </Text>
        </View>
      )}
    </Pressable>
  );
  const doPay = async () => {
    const d = payTarget;
    if (!d || busy) return;
    setBusy(true);
    try {
      // [0053 §1/감사 9] 배정 방식 동의(methodOk)를 서버에 박제 — CTA는 이미 !methodOk면 비활성이나 서버가 최종 게이트.
      await payDelegation(d.sdId, `pay-${d.sdId}`, methodOk); // 멱등키 = sdId 고정 — 재탭·재시도 안전
      haptic('success');
      setPayTarget(null);
      setMethodOk(false);
      load();
      // '결제 완료'는 돈이 움직였다는 주장이다. 움직이지 않았다.
      Alert.alert('자리 확정', `${d.dogName}의 자리가 확정됐어요 — 담당 러너가 정해지면 알려드려요`);
    } catch (e) {
      const m = (e as Error).message;
      // [감사 P1] hold_expired는 서버가 던지지 않는 죽은 매핑이었고, 실제 코드들이 원문 노출됐다
      Alert.alert('결제 실패',
        m.includes('no_capacity') ? '마지막 자리가 먼저 찼어요 — 결제되지 않았어요'
        : m.includes('dog_slot_clash') ? '같은 시간대에 이 아이의 다른 러닝 예약이 있어요'
        : m.includes('method_consent_required') ? '배정 방식에 동의해야 결제할 수 있어요' // [0053 §1] 서버 백스톱 (CTA는 이미 게이트)
        : m.includes('not_payable') ? '승인 상태가 바뀌었어요 — 새로고침해 주세요'
        : m.includes('session_closed') ? '이미 시작됐거나 닫힌 세션이에요'
        : m.includes('route_required') ? '세션 코스가 아직 없어요 — 호스트에게 문의해주세요'
        // [0081] 클럽도 마켓플레이스·반복 예약과 같은 두 게이트를 지난다. 두 문장 모두 돈 문제를
        // 숨기지 않는다 — 잠금은 조용하면 안 되고(§0-bis 예외 모드), 해결 경로를 이름으로 준다.
        // ⚠ 이 두 코드 문자열은 SQL과의 계약이다 (0081 §A의 raise exception). SQL 쪽 이름은
        // 117_club_money_suite K1/K4가 리터럴로 박아두었지만 **이쪽은 핀이 없다** — 한쪽만
        // 바꾸면 하네스는 초록인 채 보호자가 영문 코드를 보게 된다. 바꾸려면 양쪽을 같이.
        : m.includes('unsettled_charge') ? '지난 러닝의 결제가 아직 처리되지 않아 새 예약이 잠겼어요 — 설정 › 결제 관리에서 해결하면 다시 신청할 수 있어요'
        : m.includes('billing_key_required') ? '결제 수단이 등록되어 있지 않아요 — 설정 › 결제 관리에서 카드를 연결한 뒤 다시 시도해주세요'
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
    // [0052 §1] '케이스 확인'이 갈 곳 없는 문구였다 — 서버가 준 openIncidentId가 있으면 케이스로 가는 문을 연다.
    // id가 없으면(구 서버·해소된 케이스) 링크를 만들지 않는다 — 죽은 버튼 금지.
    const caseId = d.openIncidentId ?? null;
    const caseLink = caseId && (d.ui?.primaryIssue === '케이스 확인' || !d.ui?.primaryIssue) ? (
      <Pressable onPress={() => router.push(`/club/case/${caseId}`)}>
        <Text style={{ fontSize: 14, fontWeight: '800', color: L.accent, marginTop: 8 }}>케이스 확인 →</Text>
      </Pressable>
    ) : null;
    return (
      <View key={d.sdId}>
        <LilacCard hero={!crit} crit={crit}>
          <Text style={clubText.vkTitle}>{d.dogName}의 위탁</Text>
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
          {caseLink ?? (d.ui?.primaryIssue ? (
            <Text style={{ fontSize: 14, color: L.tang, marginTop: 8 }}>{d.ui.primaryIssue}</Text>
          ) : hint && !assigned ? (
            <Text style={{ fontSize: 14, color: L.dim, marginTop: 8 }}>{hint}</Text>
          ) : null)}
        </LilacCard>

        {/* O4 — 승인 → 결제 (앰버 데드라인 + 결제 CTA) */}
        {d.flap === 'HOLDING' && (
          <>
            {holdLeft != null && (
              <View style={s.deadline}>
                {/* ④ 링 드레인 — 20분 홀드가 실제로 빠져나간다 (숫자·색 모두 서버 만료 시각 바인딩) */}
                <DrainRing leftMs={holdLeft} totalMs={HOLD_MS} />
                <Text style={s.deadlineCopy}>
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
            {/* [감사 P2] 홀드 중에도 무료 취소는 서버가 허용한다 — 문을 그린다 (자리가 즉시 풀린다) */}
            <Pressable onPress={() => doWithdraw(d)}>
              <Text style={[s.detailLink, { color: L.dim, marginTop: 6 }]}>신청 취소 (무료)</Text>
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
            <ClubCta label="신청 취소 (무료)" tone="destructive" onPress={() => doWithdraw(d)} />
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
                    <Text style={{ fontSize: 14, color: L.dim, marginTop: 2 }}>담당 러너 — 수락으로 확정</Text>
                  </View>
                  <ClubTag label="확정" tone="volt" />
                </Row>
                <View style={s.custodyNote}>
                  <Text style={{ fontSize: 14, color: L.text }}>인계 확인부터 반환 확인까지 {d.dogName}의 책임자예요</Text>
                </View>
              </LilacCard>
            )}
            {!assigned && fare != null && (
              <View style={s.paidRow}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>결제 {fare.toLocaleString()}원</Text>
                  <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 1 }}>{sess.when}{board?.session.routeName ? ` · ${board.session.routeName}` : ''}</Text>
                </View>
                <ClubTag label="완료" tone="volt" />
              </View>
            )}
            {/* O8 — 인계 확인 (반환의 거울): 체크인 창이 열려야 인계가 시작된다 */}
            {assigned && board?.session.checkinOpen ? (
              <>
                <View style={s.retcol}>
                  <View style={[s.retside, !!d.runnerConfirmed && s.retsideDone]}>
                    <Text style={s.retMono}>RUNNER</Text>
                    <Text style={s.retWho}>{d.runnerName}</Text>
                    <Text style={[s.retWord, !!d.runnerConfirmed && { color: L.voltDeep }]}>{d.runnerConfirmed ? '받았어요 ✓' : '확인 대기'}</Text>
                  </View>
                  <View style={[s.retside, !!d.ownerConfirmed && s.retsideDone]}>
                    <Text style={s.retMono}>OWNER</Text>
                    <Text style={s.retWho}>나</Text>
                    <Text style={[s.retWord, !!d.ownerConfirmed && { color: L.voltDeep }]}>{d.ownerConfirmed ? '맡겼어요 ✓' : '맡겼어요 →'}</Text>
                  </View>
                </View>
                {!d.ownerConfirmed
                  ? <ClubCta label={`${d.runnerName}에게 맡겼어요 — 인계 확인 →`} onPress={() => doHandoff(d)} busy={busy} />
                  : !d.runnerConfirmed && (
                    <Text style={{ fontSize: 14, color: L.dim, textAlign: 'center', marginTop: 10 }}>
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
            {/* [감사 P1·P2] 이의 문 재정비: preference는 T-20·1회·인계 전, safety는 인계 전까지 항상 */}
            {assigned && !d.ownerConfirmed && !d.runnerConfirmed && (
              <Row style={{ justifyContent: 'center', gap: 18, marginTop: 6 }}>
                {d.objectionUsed === false && startMs - Date.now() > 20 * 60_000 && (
                  <Pressable onPress={() => doObjection(d, 'preference')}>
                    <Text style={[s.detailLink, { color: L.dim, marginTop: 0 }]}>배정 이의 (1회)</Text>
                  </Pressable>
                )}
                <Pressable onPress={() => doObjection(d, 'safety')}>
                  <Text style={[s.detailLink, { color: L.dim, marginTop: 0 }]}>안전 우려</Text>
                </Pressable>
              </Row>
            )}
          </>
        )}

        {/* O10 — 반환 확인 (인계의 거울): 역할이 뒤집히고 낱말 하나가 바뀐다 */}
        {d.custodyPhase === 'return_pending' && (
          <>
            <View style={s.retcol}>
              <View style={[s.retside, d.runnerReturnConfirmed && s.retsideDone]}>
                <Text style={s.retMono}>RUNNER</Text>
                <Text style={s.retWho}>{d.runnerName ?? ''}</Text>
                <Text style={[s.retWord, d.runnerReturnConfirmed && { color: L.voltDeep }]}>{d.runnerReturnConfirmed ? '반환했어요 ✓' : '반환 대기'}</Text>
              </View>
              <View style={[s.retside, d.ownerReturnConfirmed && s.retsideDone]}>
                <Text style={s.retMono}>OWNER</Text>
                <Text style={s.retWho}>나</Text>
                <Text style={[s.retWord, d.ownerReturnConfirmed && { color: L.voltDeep }]}>{d.ownerReturnConfirmed ? '인계받았어요 ✓' : '인계받았어요 →'}</Text>
              </View>
            </View>
            {!d.ownerReturnConfirmed
              ? <ClubCta label="인계받았어요 — 반환 확인 →" onPress={() => doReturnConfirm(d)} busy={busy} />
              : !d.runnerReturnConfirmed && (
                <Text style={{ fontSize: 14, color: L.dim, textAlign: 'center', marginTop: 10 }}>
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
        {/* O11 — 완료: 골드 실 영수증 (상세 리포트는 영수증 안의 문) */}
        {d.flap === 'SETTLED' && d.bookingId && (
          <ClubCta label="오늘의 영수증 →" tone="secondary"
            onPress={() => router.push({ pathname: `/club/receipt/${d.bookingId}`, params: { clubName: clubName ?? '' } })} />
        )}
        {/* BOARDED/OUTSIDE/REFUND/REFUSED — 상태는 카드가 정직하게 말한다 (위 카드의 서버 primaryStage가 마지막 말).
            영수증 인화·클럽 전용 러너 런 화면은 후속 빌드. 죽은 버튼은 그리지 않는다. */}
        {/* [0053 §4] REFUSED 정직한 마지막 말 + 재신청 문. 서버(0048 session_delegate_dog)는 host_rejected
            신청의 같은 세션 재신청만 막고(rejected 예외) 철회(withdrawn)는 허용한다 — 그래서 문은 '철회'에만,
            그것도 세션이 아직 열려 있고 시작 전이며 위탁 포맷일 때만 연다(그 외엔 서버가 던져 죽은 버튼이 됨).
            거절(rejected)엔 문을 그리지 않는다 — 위 카드 문구가 정직한 마지막 말이다. */}
        {d.flap === 'REFUSED' && d.approval === 'withdrawn' && isOpenish && startMs > Date.now()
          && (board?.session.format === 'mixed' || board?.session.format === 'delegated_only') && (
          <ClubCta label="다시 신청하기 →" tone="secondary"
            onPress={() => router.push({ pathname: `/club/delegate/${sess.id}`, params: { clubName: clubName ?? '', when: sess.when } })} />
        )}
      </View>
    );
  };

  // ---------- 참가자 탭 ----------
  const renderRoster = () => {
    // [감사 P1] 거절·철회된 신청자도 limited로 남는다 — 사람 명단은 host/full에게만.
    // none/limited 폴백은 인원수까지만 (실명·강아지 이름을 클라이언트가 그리지 않는다).
    if (access === 'none' || access === 'limited' || !roster) {
      return (
        <View style={{ alignItems: 'center', paddingVertical: 40 }}>
          <Text style={{ fontSize: 14, color: L.text }}>참가 {peopleCount}팀 · 정원 {sess.capacity}</Text>
          <Text style={{ fontSize: 14, color: L.dim, marginTop: 6 }}>
            {access === 'limited' ? '결제하면 참가자 명단이 열려요' : access === 'none' ? '세션 참가자만 볼 수 있어요' : '명단을 불러오는 중...'}
          </Text>
        </View>
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
              {/* [감사 P1] HOST 태그가 전화 칩 자리를 먹어 규칙 B가 열어준 호스트 번호가 안 보이던 것 — 함께 그린다 */}
              {p.isHost && <ClubTag label="HOST" tone="lilac" />}
              {p.phone ? (
                <Pressable onPress={() => Linking.openURL(`tel:${p.phone!.replace(/[^0-9+]/g, '')}`).catch(() => {})}>
                  <View style={s.phoneChip}><Text style={s.phoneChipTxt}>{p.phone}</Text></View>
                </Pressable>
              ) : !p.isMe && !p.isHost ? (
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

  const tabCounts: Record<string, number | null> = { 개요: null, 참가자: peopleCount, 채팅: null };

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

        {/* ---------- 셸 탭 — 세션이 끝나면 기계는 사라진다 (결과만 남는 화면) ---------- */}
        {!isDone && (
          <View style={s.shell}>
            {(['개요', '참가자', '채팅'] as const).map((t) => (
              <Pressable key={t} onPress={() => setTab(t)} style={s.shellTab}>
                <Text style={[s.shellTxt, tab === t && { color: L.head }]}>
                  {t}{tabCounts[t] != null ? <Text style={{ fontSize: 14, color: L.voltDeep }}>  {tabCounts[t]}</Text> : null}
                </Text>
                {tab === t && <View style={s.shellOn} />}
              </Pressable>
            ))}
          </View>
        )}

        {/* ---------- 결과 화면 (done) — 세 당사자 모두 여기만 본다 ---------- */}
        {isDone && tab === '개요' && (
          <>
            <LilacCard style={{ alignItems: 'center', paddingVertical: 22 }}>
              <Text style={{ fontSize: 17, fontWeight: '800', color: L.head }}>오늘의 하이클럽</Text>
              <Text style={{ fontSize: 14, color: L.text, marginTop: 4 }}>
                {checkedCount}팀{sess.dogCount > 0 ? ` · ${sess.dogCount}마리` : ''}가 함께 달렸어요
              </Text>
            </LilacCard>

            {/* 내 위탁 결과 — 상태 낱말 그대로 + 기록 문. [감사 P1] 배지·심각도·이슈를 버리지 않는다
                (환불 처리 중·정산 보류·외부 보호 같은 의무가 결과 화면에서 증발하면 안 된다) */}
            {myDogs.map((d) => (
              <View key={d.sdId}>
                <LilacCard hero={d.ui?.severity !== 'critical'} crit={d.ui?.severity === 'critical'}>
                  <Text style={clubText.vkTitle}>{d.dogName}의 위탁</Text>
                  <Row style={{ alignItems: 'center', gap: 10, marginTop: 8 }}>
                    <DogDot name={d.dogName} collar={d.collar} />
                    <Text style={[clubText.stateStrong, { flex: 1 }, d.ui?.severity === 'critical' && { color: L.tang }]}>
                      {d.ui?.primaryStage ?? d.flap}
                    </Text>
                    <Flap state={d.flap} />
                  </Row>
                  {d.ui?.secondaryBadges && d.ui.secondaryBadges.length > 0 && (
                    <Row style={{ gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
                      {d.ui.secondaryBadges.map((b) => <ClubTag key={b} label={b} tone={b.includes('환불') || b.includes('인시던트') ? 'coral' : 'dim'} />)}
                    </Row>
                  )}
                  {d.ui?.primaryIssue && (
                    <Text style={{ fontSize: 14, color: L.tang, marginTop: 8 }}>{d.ui.primaryIssue}</Text>
                  )}
                </LilacCard>
                {d.flap === 'SETTLED' && d.bookingId && (
                  <ClubCta label="오늘의 영수증 →" style={{ paddingVertical: 17 }}
                    onPress={() => router.push({ pathname: `/club/receipt/${d.bookingId}`, params: { clubName: clubName ?? '' } })} />
                )}
              </View>
            ))}

            {/* 러너 결과 */}
            {myCharges.length > 0 && (
              <View style={s.paidRow}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>오늘 {myCharges.length}마리와 달렸어요</Text>
                  <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 2 }}>정산은 반환·케이스 해소 후 자동으로 풀려요</Text>
                </View>
                <Flap word="DONE" />
              </View>
            )}

            {/* [Sean 규칙] 여백 많은 화면의 버튼은 크게 — 결과 화면은 한 손 엄지 존 */}
            {sess.nextSessionId && (
              <ClubCta label="다음 세션 참여하기 →" tone="secondary" style={{ paddingVertical: 18 }}
                onPress={() => router.replace({ pathname: `/club/session/${sess.nextSessionId}`, params: { clubName } })} />
            )}

            {/* 조용한 뒷문 — 채팅은 세션 뒤 24시간(스펙), 신고는 정산 시비의 통로라 남긴다. 호스트는 요약도 */}
            {access !== 'none' && (
              <Row style={{ justifyContent: 'center', gap: 22, marginTop: 18 }}>
                <Pressable onPress={() => setTab('채팅')}><Text style={[s.detailLink, { color: L.dim, marginTop: 0 }]}>채팅</Text></Pressable>
                <Pressable onPress={doIncident}><Text style={[s.detailLink, { color: L.dim, marginTop: 0 }]}>문제 신고</Text></Pressable>
                {sess.isHost && (
                  <Pressable onPress={() => router.push({ pathname: `/club/console/${sess.id}`, params: { clubName: clubName ?? '' } })}>
                    <Text style={[s.detailLink, { color: L.dim, marginTop: 0 }]}>호스트 요약</Text>
                  </Pressable>
                )}
              </Row>
            )}
          </>
        )}
        {isDone && tab === '채팅' && (
          <Pressable onPress={() => setTab('개요')}>
            <Text style={[s.detailLink, { marginTop: 12 }]}>‹ 결과로 돌아가기</Text>
          </Pressable>
        )}

        {tab === '개요' && !isDone && (
          <>
            {/* 집결 팩트 */}
            <LilacCard>
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <View style={{ flex: 1 }}>
                  <Text style={clubText.vkDim}>MEET</Text>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: L.head, marginTop: 3 }}>{sess.meetupPoint}</Text>
                  <Text style={{ fontSize: 14, color: L.dim, marginTop: 3 }}>
                    호스트 {sess.hostName ?? '—'} · {peopleCount}팀 / {sess.capacity}
                  </Text>
                </View>
              </Row>
            </LilacCard>

            {/* ---------- R2 — 나에게 온 배정 제안 (5분 시효, 가장 위) ---------- */}
            {myProposals.map((d) => {
              const left = d.proposalExpiresAt ? new Date(d.proposalExpiresAt).getTime() - now : null;
              // [리뷰] 만료를 '00:00 남음'으로 오독시키지 않는다 (콘솔 expired와 같은 판정) —
              // 소멸한 제안은 서버가 proposal_expired를 던진다: 수락 문을 열어두면 죽은 버튼이다.
              const expired = left != null && left <= 0;
              return (
                <View key={d.sdId}>
                  {left != null && (
                    <View style={s.deadline}>
                      {/* ④ 링 드레인 — 5분 시효 (proposal_expires_at) */}
                      <DrainRing leftMs={left} totalMs={PROPOSAL_MS} />
                      <Text style={s.deadlineCopy}>
                        {expired ? '제안이 소멸했어요 — 호스트가 다시 제안해야 해요' : '안에 결정하지 않으면 제안이 소멸해요'}
                      </Text>
                    </View>
                  )}
                  <LilacCard hero>
                    <Text style={clubText.vkTitle}>배정 제안 — 호스트</Text>
                    <Row style={{ gap: 11, alignItems: 'center', marginTop: 8 }}>
                      <DogDot name={d.dogName} collar={d.collar} size={46} />
                      <View style={{ flex: 1 }}>
                        <Text style={{ fontSize: 16, fontWeight: '800', color: L.head }}>{d.dogName}</Text>
                        <Text style={{ fontSize: 14, color: L.dim, marginTop: 2 }}>{d.ownerName} 보호자</Text>
                      </View>
                    </Row>
                    <View style={s.custodyNote}>
                      <Text style={{ fontSize: 14, color: L.text }}>수락하면 인계부터 반환까지 {d.dogName}의 책임자는 나</Text>
                    </View>
                  </LilacCard>
                  <ClubCta label="이 아이, 내가 맡을게요 →" onPress={() => doAcceptProposal(d)} busy={busy} disabled={expired} />
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
                        <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>{d.dogName}</Text>
                        <Text style={{ fontSize: 14, lineHeight: 18, color: L.text, marginTop: 1 }}>
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
                          <ClubCta label="러닝 화면 (트래킹 · 종료) →" tone="secondary"
                            onPress={() => router.push({ pathname: `/club/run/${sess.id}`, params: { clubName: clubName ?? '' } })}
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
                      <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>오늘 담당 {myCharges.length}/{board.me.runnerCap}</Text>
                      {myCharges.length >= board.me.runnerCap && (
                        <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 1 }}>가득 찼어요 — 새 제안이 오지 않아요</Text>
                      )}
                    </View>
                    <Flap word={`${myCharges.length}/${board.me.runnerCap}`} />
                  </View>
                )}
                {/* 러닝 시작 — 인계(픽업) 확정된 아이가 있을 때만 (러너 액션) */}
                {myCharges.some((d) => d.bookingStatus === 'picked_up') && (
                  <ClubCta label="러닝 시작 →" onPress={doStartRuns} busy={busy} />
                )}
              </>
            )}

            {/* ---------- 러너 확약 — 인증 러너(cap>0) + 위탁 세션에만 문을 그린다 ([감사 P1] owner_only 죽은 버튼) ---------- */}
            {isOpenish && board && board.session.format !== 'owner_only' && !board.me.committed && board.me.runnerCap > 0 && (
              <ClubCta label={`이번 세션 러너로 확약하기 (담당 ${board.me.runnerCap}마리까지)`}
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
                tone={myDogs.length > 0 ? 'secondary' : 'coral'}
              />
            )}
            {isOpenish && sess.joined && sess.myAttendance === 'rsvp' && (
              inCheckinWindow
                ? (
                  <>
                    <ClubCta label="✓ 집결지 도착 체크인" onPress={doCheckin} busy={busy} />
                    {/* ④ 체크인 창 드레인 — 창 자체는 8시간이라 숫자는 안 쓴다(mm:ss는 60분 미만 전용), 링만 */}
                    <Row style={{ alignItems: 'center', gap: 9, marginTop: 9, paddingHorizontal: 2 }}>
                      <DrainRing leftMs={checkinLeftMs} totalMs={CHECKIN_MS} size={26} dots={12} />
                      <Text style={{ fontSize: 14, color: L.dim, lineHeight: 20, flex: 1 }}>체크인 창은 시작 6시간 뒤 닫혀요</Text>
                    </Row>
                  </>
                )
                : <ClubCta label="참여 중 — 취소하려면 탭" tone="destructive" onPress={doCancelRsvp} />
            )}
            {isOpenish && sess.myAttendance === 'checked_in' && (
              <View style={s.checkedCard}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: L.accent }}>체크인 완료 — 좋은 러닝 되세요</Text>
              </View>
            )}

            {/* 입장권 (기존 pass 화면 — 재도색은 후속) */}
            {sess.joined && !isDone && (
              <Pressable onPress={() => router.push({ pathname: `/club/pass/${sess.id}`, params: { clubName: clubName ?? '' } })}>
                <Text style={s.detailLink}>내 입장권 — 집결지에서 보여주세요</Text>
              </Pressable>
            )}

            {/* 호스트 콘솔 문 — 심사·배정·종료는 콘솔에서 */}
            {sess.isHost && !isDone && (
              <ClubCta label="호스트 콘솔 →" tone="secondary"
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
            <Text style={{ fontSize: 14, color: L.dim }}>세션 참가자만 볼 수 있어요</Text>
          </View>
        )}
        {tab === '채팅' && access === 'limited' && (
          // limited(결제 전 신청자) = 호스트 창구만, 전체 화면
          <>
            <LilacCard frame>
              <Row style={{ alignItems: 'center', gap: 7 }}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: L.head, flex: 1 }}>호스트 창구</Text>
                <View style={s.liveDotSm} />
              </Row>
              <View style={{ marginTop: 6 }}>
                {hostMsgs.length === 0 && <Text style={s.sysMsg}>궁금한 게 있으면 호스트에게 바로 물어보세요</Text>}
                {hostMsgs.map(renderMsg)}
              </View>
            </LilacCard>
            {writable ? (
              <Row style={s.inputbar}>
                <Pressable onPress={() => doSendPhoto({ audience: 'host_channel' })} style={s.camChip}><Icon name="Camera" glyph="◉" size={17} color={L.head} /></Pressable>
                <TextInput value={draft} onChangeText={setDraft} placeholder="호스트에게 문의..." placeholderTextColor={L.dim}
                  style={s.inputField} multiline />
                <Pressable onPress={() => doSend(draft, { audience: 'host_channel' })} style={s.sendBtn}>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>전송</Text>
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
                    <Text style={{ fontSize: 14, fontWeight: '800', color: L.head, flex: 1 }}>호스트 창구 — 문의 {inquiryIds.length}건</Text>
                    <View style={s.liveDotSm} />
                  </Row>
                  {inquiryIds.map((pid) => {
                    const last = [...hostMsgs].reverse().find((m) => m.counterpartId === pid);
                    return (
                      <Pressable key={pid} onPress={() => setHostThread(pid)} style={{ marginTop: 6 }}>
                        <Text style={{ fontSize: 14, color: L.text }} numberOfLines={1}>
                          {nameOf(pid)}: “{last?.deleted ? '삭제된 메시지' : last?.kind === 'photo' ? '사진' : last?.body ?? ''}” <Text style={{ color: L.accent, fontWeight: '800' }}>→ 탭해서 1:1</Text>
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
                    <Text style={{ fontSize: 14, fontWeight: '800', color: L.head, flex: 1 }}>호스트 창구</Text>
                    {hostMsgs.length > 0 && <View style={s.liveDotSm} />}
                  </Row>
                  <Text style={{ fontSize: 14, color: L.text, marginTop: 5 }} numberOfLines={1}>
                    {hostMsgs.length > 0
                      ? `${hostMsgs[hostMsgs.length - 1].mine ? '나' : hostMsgs[hostMsgs.length - 1].senderName}: “${hostMsgs[hostMsgs.length - 1].deleted ? '삭제된 메시지' : hostMsgs[hostMsgs.length - 1].kind === 'photo' ? '사진' : hostMsgs[hostMsgs.length - 1].body}”`
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
                <Pressable onPress={() => doSendPhoto()} style={s.camChip}><Icon name="Camera" glyph="◉" size={17} color={L.head} /></Pressable>
                <TextInput value={draft} onChangeText={setDraft} placeholder="메시지..." placeholderTextColor={L.dim}
                  style={s.inputField} multiline />
                <Pressable onPress={() => doSend(draft)} style={s.sendBtn}>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>전송</Text>
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
              {'\n'}<Text style={{ color: L.dim }}>실결제 연동 후 적용돼요 — 파일럿 기간에는 청구되지 않아요</Text>
            </Text>
          </View>
          {/* [정직 2026-08-11] 1:1 결제 화면(owner/pay.tsx:284)은 '실결제가 발생하지 않는다'를 세 번
              고지하는데 클럽 시트는 한 번도 하지 않았다 — 같은 앱, 같은 사용자, 두 개의 진실.
              게다가 거짓말하는 쪽에 취소 수수료표가 붙어 있었다. 리포지토리 어디에도 PG 연동이 없고
              (toss/portone/iamport/stripe 전무), 서버조차 스스로 '모의 시대: 청구 없음'이라고 적는다
              (0057:250). 1:1과 같은 플레이트를 여기에도 세운다. */}
          <View style={s.payPlate}>
            <Text style={s.payPlateTxt}>
              결제 수단 연동 준비 중 — 파일럿 기간에는 자리 확정 시 실결제가 발생하지 않아요
            </Text>
          </View>
          <ClubCta label="동의하고 자리 확정 →" onPress={doPay} disabled={!methodOk} busy={busy} />
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
              <Pressable
                onPress={() => doSendPhoto({ audience: 'host_channel', recipient: isHostView && hostThread !== 'me' ? hostThread : undefined })}
                style={s.camChip}><Icon name="Camera" glyph="◉" size={17} color={L.head} /></Pressable>
              <TextInput value={threadDraft} onChangeText={setThreadDraft} placeholder="메시지..." placeholderTextColor={L.dim}
                style={s.inputField} multiline />
              <Pressable
                onPress={() => doSend(threadDraft, { audience: 'host_channel', recipient: isHostView && hostThread !== 'me' ? hostThread : undefined })}
                style={s.sendBtn}>
                <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>전송</Text>
              </Pressable>
            </Row>
          ) : (
            <Text style={s.closedLine}>채팅이 닫혔어요</Text>
          )}
        </View>
      </Modal>

      {/* ---------- 공용 사유 입력 시트 (Alert.prompt 대체 — iOS 전용 API의 안드로이드 죽은 버튼 해소) ---------- */}
      <Modal visible={!!askText} transparent animationType="slide" onRequestClose={() => setAskText(null)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.45)' }} onPress={() => setAskText(null)} />
        <View style={s.sheet}>
          <View style={s.grab} />
          <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>{askText?.title}</Text>
          <Text style={{ fontSize: 14, color: L.text, marginTop: 5, lineHeight: 18 }}>{askText?.message}</Text>
          <TextInput
            value={askDraft} onChangeText={setAskDraft} multiline autoFocus
            placeholder="내용..." placeholderTextColor={L.dim}
            style={[s.inputField, { marginTop: 12, minHeight: 64, flex: 0 }]}
          />
          {askText?.actions.map((a) => (
            <ClubCta
              key={a.label}
              label={a.label}
              tone={a.destructive ? 'destructive' : 'coral'}
              onPress={() => {
                const t = askDraft.trim();
                if (askText.requireText && !t) { Alert.alert('내용이 필요해요'); return; }
                setAskText(null);
                a.onSubmit(t);
              }}
            />
          ))}
        </View>
      </Modal>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  // 정직 고지 플레이트 — owner/pay.tsx의 plate 문법을 클럽 시트로 이식
  payPlate: { backgroundColor: L.inset, borderLeftWidth: 3, borderLeftColor: L.amber, padding: 11, marginTop: 10 },
  payPlateTxt: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: L.text },
  shell: { flexDirection: 'row', borderBottomWidth: 1, borderBottomColor: L.hair2, marginTop: 8 },
  shellTab: { flex: 1, alignItems: 'center', paddingVertical: 9 },
  shellTxt: { fontSize: 14, fontWeight: '800', color: L.dim },
  shellOn: { position: 'absolute', left: '28%', right: '28%', bottom: -1, height: 2.5, backgroundColor: L.accent, borderRadius: 2 },
  deadline: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: L.amberSoft, borderRadius: lilacRadius.inner, padding: 11, paddingHorizontal: 13, marginTop: 10,
  },
  // ④ 링 옆 경고 한 줄 — 앰버 잉크 유지, 14pt 바닥선 (숫자는 링이 말한다)
  deadlineCopy: { fontSize: 14, color: '#7a5a2a', lineHeight: 20, flex: 1 },
  detailLink: { textAlign: 'center', marginTop: 11, fontSize: 14, fontWeight: '800', color: L.accent },
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
  // 트래킹 라틴 마이크로는 라벨(RUNNER/OWNER)만 입는다 — 사람 이름은 읽는 크기의 형제로 분리 (7.5pt 한글 금지)
  retMono: { fontSize: 7.5, fontWeight: '700', letterSpacing: 1.5, color: L.dim },
  retWho: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: L.text, marginTop: 2 },
  retWord: { fontSize: 14, fontWeight: '800', color: L.head, marginTop: 4 },
  sechead: {
    flexDirection: 'row', alignItems: 'center', marginTop: 14, paddingBottom: 6,
    borderBottomWidth: 1, borderBottomColor: L.hair2,
  },
  secheadTitle: { fontSize: 14, fontWeight: '800', color: L.head },
  drow: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 11, marginTop: 8,
  },
  personName: { fontSize: 14, fontWeight: '800', color: L.head },
  personSub: { fontSize: 14, lineHeight: 18, color: L.text, marginTop: 1 },
  phoneChip: { backgroundColor: L.voltFill, borderRadius: lilacRadius.tag, paddingVertical: 5, paddingHorizontal: 9 },
  // 전화 칩 = tel: 탭 타깃이다 — 번호가 읽히지 않으면 문이 아니다 (바닥선 14)
  phoneChipTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: L.voltDeep, fontVariant: ['tabular-nums'] },
  phoneNotice: { fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 10, textAlign: 'center' },
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
  legalTxt: { flex: 1, fontSize: 14, color: L.text, lineHeight: 18 },
  // ④ 채팅 — 말풍선 문법 (시스템 가운데 · 남 왼쪽 · 나 오른쪽 바이올렛)
  sysMsg: { fontSize: 14, lineHeight: 18, color: L.dim, textAlign: 'center', marginTop: 10 },
  msgRow: { marginTop: 9, alignItems: 'flex-start' },
  msgWho: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginBottom: 3, marginLeft: 2 },
  bb: {
    maxWidth: '82%', backgroundColor: L.card, borderWidth: 1, borderColor: L.hair,
    borderRadius: 10, borderTopLeftRadius: 3, paddingVertical: 8, paddingHorizontal: 11,
  },
  bbMine: {
    backgroundColor: L.accent, borderColor: L.accent,
    borderTopLeftRadius: 10, borderTopRightRadius: 3,
  },
  bbTxt: { fontSize: 14, lineHeight: 18, color: L.text },
  inputbar: {
    gap: 8, marginTop: 12, alignItems: 'flex-end',
    backgroundColor: L.glass, borderWidth: 1, borderColor: L.glassEdge,
    borderRadius: 10, padding: 7,
  },
  inputField: {
    flex: 1, backgroundColor: '#fff', borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.btn,
    paddingVertical: 8, paddingHorizontal: 12, fontSize: 14, color: L.head, maxHeight: 90,
  },
  sendBtn: {
    backgroundColor: L.accent, borderRadius: lilacRadius.btn, paddingVertical: 10, paddingHorizontal: 13,
  },
  camChip: {
    width: 38, height: 38, borderRadius: lilacRadius.btn, backgroundColor: '#fff',
    borderWidth: 1, borderColor: L.hair, alignItems: 'center', justifyContent: 'center',
  },
  bbPhoto: { width: 190, height: 142, borderRadius: 10, backgroundColor: L.inset },
  closedLine: { fontSize: 14, color: L.dim, textAlign: 'center', marginTop: 12, lineHeight: 18 },
  liveDotSm: {
    width: 8, height: 8, borderRadius: 4, backgroundColor: L.coral,
    shadowColor: L.coral, shadowOpacity: 0.4, shadowRadius: 4, elevation: 2,
  },
});
