import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { PickupMap } from '../../src/components/PickupMap';
import { Monogram, Row } from '../../src/components/ui';
import { cancelBooking, confirmHandoff, fetchBookingSync, fetchCurrentOwnerBookingId, fetchMeetupInfo, fetchOwnerPickupCoords, MeetupInfo, OwnerPickup, subscribeBooking } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { startOwnerActivity } from '../../src/lib/ownerActivity';
import { haptic } from '../../src/lib/haptics';
import { cancelPolicy, draft } from '../../src/store';
import { layout, paper } from '../../src/theme';

// 보호자 인계 화면 — 실신원만 (김민준·초코 목업 은퇴, ui-audit P0).
// 모든 이름·상태는 서버에서. 가짜 ETA 문구 없음.
//
// 모티프 = 이중 봉인(二重封印): 양측 확인이 각각 하나의 도장 자리를 채운다. 자리는 서버 진실
// (stage / peerConfirmed)로만 채워진다 — 가짜 진행 없음. 둘 다 채워지면 골드 SEALED 룰이 내려온다.
// 로직 동결: 스테이지 머신·구독/폴링·confirmHandoff·라우팅·게이트 전부 원본 그대로.
//
// [2026-08-06 심 룰 리페인트 · 정직 배치 item 8] 테일러드 라일락 은퇴 → 순백/코랄.
// 법: "dark is the artifact, light is the screen" — 봉인 밴드와 인계 완료 카드만 나이트 지면으로
// 남고(코랄 헤어라인 심이 티켓처럼 물린다), 나머지 화면은 전부 순백 크롬. 새벽빛 블룸·이중 프레임·
// 섀도·라운드는 사라지고 섹션은 풀블리드 코랄 1px로만 나뉜다. 밀도는 그대로(위탁 표면 법):
// 스텝 레일·두 봉인 자리·2/2 카운터는 전부 살아남고 장식만 떠난다.

const NIGHT = '#1C1837';    // 아티팩트 지면 — 다크 세리머니 월드는 의도적 존속 (theme.ts 순백 법 주석)
const NIGHT_DIM = '#C6BEEB';
const SEAL_INK = '#8a6f2a'; // 소인 잉크 — 클럽 영수증 골드 실과 같은 잉크
const GOLD = '#B99A4F';     // 봉인 골드 — 밴드 소인·SEALED 룰 전용 (아티팩트 어휘, 크롬 금지)
const GOLD_SOFT = '#F4EBD3';
const GOLD_SHEEN = '#D8C185';
const PERF = 'rgba(255,255,255,0.25)'; // 천공 점선 — 밤 지면 위 흰 선

type Stage = 'enroute' | 'arrived' | 'waiting' | 'confirmed';

// 봉인 스탬프 — 빈 자리가 '실제로' 채워지는 순간에만 도장이 내려온다 (클럽 영수증 ② 스탬프 문법).
// 정지값 = opacity 1 · scale 1 · rotate tilt. sealed는 서버 진실에서만 온다 → 연출이 앞서 나가지 않는다.
// [P2-12 once-law] 첫 동기화가 '이미 봉인된' 상태로 도착하면 = 재진입이다 → 도장을 다시 찍지 않고
// 정지값으로 점프한다. 하이드레이션 이후(사용자가 보는 앞에서 일어난 실제 봉인)만 애니메이션.
function useStamp(sealed: boolean, hydrated: { current: boolean }) {
  const v = useRef(new Animated.Value(sealed ? 1 : 0)).current;
  const was = useRef(sealed);
  useEffect(() => {
    if (sealed === was.current) return;
    was.current = sealed;
    if (!sealed) { v.setValue(0); return; }
    if (!hydrated.current) { v.setValue(1); return; } // 재진입 — 정지값 (파문 없음)
    v.setValue(0);
    const a = Animated.timing(v, {
      toValue: 1, duration: 340, easing: Easing.bezier(0.5, 0, 0.7, 0.35), useNativeDriver: true,
    });
    a.start();
    return () => a.stop();
  }, [sealed, v, hydrated]);
  return v;
}

export default function OwnerMeetup() {
  const df = useDisplayFont();
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const [stage, setStage] = useState<Stage>('enroute');
  const runnerName = info?.runnerName ?? '러너';
  const dogName = info?.dogName ?? '반려견';

  const poll = useRef<ReturnType<typeof setInterval> | null>(null);
  const [bookingId, setBookingId] = useState<string | null>(draft.bookingId ?? null);
  const [peerConfirmed, setPeerConfirmed] = useState(false); // 러너 측 인계 확인 (서버 진실)
  const [synced, setSynced] = useState(false); // 첫 서버 동기화 도착 (스탬프 하이드레이션 판정용)
  // [훅 배치 동결법] 새 useState는 이 뭉치의 끝에만 — 아래 effect 순서는 고정이고 하이드레이션
  // 게이트 effect가 항상 마지막이어야 한다. 러너 도착 = 서버 진실(bookings.arrived_at, 0060).
  const [arrivedAt, setArrivedAt] = useState<string | null>(null);
  // 0065: pickup coords for the map plate (owner-RLS read, no new server surface).
  // Appended at the end of the bundle per the freeze law above.
  const [pin, setPin] = useState<{ s: 'loading' | 'ok' | 'err'; c: OwnerPickup | null }>({ s: 'loading', c: null });
  const [pinTry, setPinTry] = useState(0);
  // [2026-08-11 owner cancel · 0066] Cancel affordance for both pre-departure ('enroute' =
  // server confirmed: free >=24h out, else 10%) and en-route ('arrived' = server
  // runner_enroute: 50%, runner compensation — 0066 widened the transition map). picked_up
  // stays closed server-side (incident, not cancellation), and this screen stops offering
  // cancel once the owner starts the handoff ceremony (stage 'waiting'). Appended at the
  // END of the bundle per the hook-placement freeze above.
  const [cancelling, setCancelling] = useState(false);
  // [2026-08-19 11b′ restyle] Owner-side 챙겼나요 checklist. LOCAL ONLY and NON-GATING — it is the
  // owner's own "did I grab it" list, never a claim about the runner's equipment and never a gate on
  // the handoff CTA (the runner's preflight gates its own CTA; ours must not invent a second one).
  // Appended at the END of the bundle per the hook-placement freeze above, together with the
  // safe-area insets the new in-flow header and the CTA dock need.
  const [gear, setGear] = useState({ leash: false, water: false, treats: false });
  const insets = useSafeAreaInsets();
  // Mutes refresh()'s terminal-state handler while our own cancel exit runs — realtime can
  // observe cancelled_owner before cancelBooking() resolves, and without this both paths
  // would Alert + router.back() (double pop).
  const closingRef = useRef(false);

  // id 복원 — 리로드로 draft가 비어도 서버가 진실을 안다 (데모 전락 사고 방지, 2026-07-23)
  useEffect(() => {
    if (bookingId) return;
    fetchCurrentOwnerBookingId()
      .then((id) => {
        if (id) { draft.bookingId = id; setBookingId(id); }
        else {
          Alert.alert('진행 중인 예약이 없어요', '러너가 확정된 예약이 있을 때 이 화면이 열려요');
          router.back();
        }
      })
      .catch((e) => {
        // [리뷰 F1] fetchCurrentOwnerBookingId가 이제 네트워크 실패 시 throw — 삼키면 버튼 죽은 유령
        // 인계 화면이 된다. 정직하게 알리고 재시도/복귀를 준다 (스테이지 머신은 건드리지 않는다).
        console.warn('[o-meetup] resolve:', e?.message ?? e);
        Alert.alert('상태를 확인하지 못했어요', '네트워크를 확인하고 다시 시도해주세요', [
          { text: '다시 시도', onPress: () => { draft.bookingId = null; setBookingId(null); } },
          { text: '돌아가기', style: 'cancel', onPress: () => router.back() },
        ]);
      });
  }, [bookingId]);

  // 실컨텍스트 로드 — 러너·강아지·코스 실명
  useEffect(() => {
    if (!bookingId) return;
    fetchMeetupInfo(bookingId).then(setInfo).catch((e) => console.warn('[o-meetup] info:', e?.message ?? e));
  }, [bookingId]);

  // 0065: pickup coords for the plate. New effect sits HERE (after fetchMeetupInfo,
  // before the frozen sync machinery) per the hook-placement freeze. Error is its own
  // state — the plate shows an inline retry, never a silent placeholder (DS-3).
  useEffect(() => {
    if (!bookingId) return;
    let alive = true;
    setPin({ s: 'loading', c: null });
    fetchOwnerPickupCoords(bookingId)
      .then((c) => { if (alive) setPin({ s: 'ok', c }); })
      .catch((e) => {
        console.warn('[o-meetup] pin:', e?.message ?? e);
        if (alive) setPin({ s: 'err', c: null });
      });
    return () => { alive = false; };
  }, [bookingId, pinTry]);

  // 모든 단계가 서버 진실을 따른다 — 가짜 도착 없음
  const refresh = useCallback(async () => {
    if (!bookingId) return;
    if (closingRef.current) return; // cancel exit in flight — it owns the alert + navigation
    try {
      const sync = await fetchBookingSync(bookingId);
      // 종말 상태 — 화면에 좌초하지 않고 정직하게 이탈 (감사 ③)
      if (sync.status === 'completed') {
        router.replace({ pathname: '/owner/report', params: { bid: bookingId } });
        return;
      }
      if (sync.status === 'matching' || sync.status.startsWith('cancelled') || sync.status === 'expired') {
        Alert.alert('예약 상태가 바뀌었어요', sync.status === 'matching' ? '러너가 응답을 취소했어요 — 다른 러너를 찾고 있어요' : '이 예약은 종료됐어요');
        router.back();
        return;
      }
      setPeerConfirmed(sync.runnerConfirmed);
      setArrivedAt(sync.arrivedAt); // 러너 도착 — 표시 조건일 뿐, 스테이지 머신은 건드리지 않는다
      setSynced(true); // [P2-12] 봉인 진실이 처음 도착한 지점 — 이 커밋 이후부터가 '라이브'
      if (sync.status === 'active') {
        router.replace('/owner/live'); // 러너가 start_run을 눌렀을 때만 라이브 진입
      } else if (sync.status === 'picked_up') {
        setStage('confirmed'); // 인계 완료 — 시작 대기 (라이브 아님)
      } else if (sync.ownerConfirmed) {
        setStage('waiting'); // 이미 확인함 — 재진입해도 버튼 재노출 없이 러너 대기
      } else if (sync.status === 'runner_enroute') {
        setStage((cur) => (cur === 'waiting' ? cur : 'arrived')); // 러너 이동 중 → 인계 버튼 활성
      } else {
        setStage((cur) => (cur === 'waiting' ? cur : 'enroute')); // 아직 수락/출발 전
      }
    } catch { /* 다음 이벤트/폴백이 처리 */ }
  }, [bookingId]);

  useEffect(() => {
    if (!bookingId) return;
    refresh();
    // Realtime이 주채널, 8초 폴링은 폴백
    const unsub = subscribeBooking(bookingId, refresh);
    poll.current = setInterval(refresh, 8000);
    return () => { if (poll.current) clearInterval(poll.current); unsub(); };
  }, [bookingId, refresh]);

  // [정직법 P1-4] 실패는 실패로 — 가짜 소인 금지. 서버가 확인을 받아야만 봉인 자리가 채워진다.
  // 전송 실패 시 'arrived'에 남아 CTA가 다시 뜬다 (재시도 경로 보장). 구: catch를 삼키고 무조건 waiting.
  const handoff = async () => {
    if (!bookingId) return;
    haptic('success');
    try {
      await confirmHandoff(bookingId, 'owner');
      setStage('waiting');
    } catch {
      Alert.alert('인계 확인이 전송되지 않았어요', '다시 시도해주세요');
    }
  };

  // [2026-08-11 owner cancel] Design (a): state the policy in words BEFORE committing —
  // the fee is computed server-side (0066 marketplace_cancel_fee: unmatched/>=24h free,
  // confirmed <24h 10%, runner_enroute 50% as runner compensation) and MeetupInfo carries no
  // price, so no client number is guessed. The success alert then shows the server's returned
  // cancel_fee/refund (schedule.tsx cancel vocabulary, verbatim). At stage 'arrived' the
  // server status is runner_enroute — the confirm copy must say 50% plainly, and why.
  const cancel = () => {
    if (!bookingId || cancelling) return;
    const enroute = stage === 'arrived'; // server runner_enroute — 50% tier (0066)
    Alert.alert(
      '일정을 취소할까요?',
      // [post-pay 2026-08-13] '차감'은 잡아둔 돈이 있을 때만 참인 말이다 — 러닝 전에는
      // 결제된 금액이 없으므로 수수료는 차감이 아니라 **청구**다 (§0-bis).
      `${info ? `${info.when} · ` : ''}${runnerName} 러너\n\n${enroute
        ? `러너가 이미 픽업으로 출발했어요.\n지금 취소하면 예약 금액의 ${cancelPolicy.enrouteFeeRate * 100}%가 취소 수수료로 청구되고, 시간을 내어 출발한 러너의 보상으로 쓰여요.`
        : `시작 24시간 전까지는 수수료가 없어요.\n이후에는 예약 금액의 ${cancelPolicy.feeRate * 100}%가 취소 수수료로 청구돼요.`}`,
      [
        { text: '돌아가기', style: 'cancel' },
        {
          text: '취소하기', style: 'destructive',
          onPress: async () => {
            setCancelling(true);
            try {
              const r = await cancelBooking(bookingId);
              closingRef.current = true; // this exit owns navigation — see refresh() guard
              // Alert-then-back mirrors the terminal-state handler in refresh() above.
              Alert.alert(
                '취소 완료',
                r.cancel_fee > 0
                  ? `취소 수수료 ${r.cancel_fee.toLocaleString()}원이 청구돼요\n설정 › 결제 관리에서 결제 내역을 볼 수 있어요`
                  : '청구되는 금액은 없어요',
              );
              router.back();
            } catch (e) {
              // Loud fail — the booking is still live, the button stays for retry.
              Alert.alert('취소 실패', (e as Error).message ?? '잠시 후 다시 시도해주세요');
            } finally {
              setCancelling(false);
            }
          },
        },
      ],
    );
  };

  // ── 이중 봉인 = 서버 진실의 파생값 (아래 Step의 done 식과 문자 그대로 동일) ──
  const mineSealed = stage === 'waiting' || stage === 'confirmed';
  const peerSealed = peerConfirmed || stage === 'confirmed';
  const bothSealed = mineSealed && peerSealed;
  const sealCount = (mineSealed ? 1 : 0) + (peerSealed ? 1 : 0);
  // [P2-12] 하이드레이션 게이트 — 첫 동기화 '커밋이 지난 뒤'에만 true가 된다.
  // (ref를 sync 함수 안에서 바로 세우면 배치된 리렌더보다 먼저 참이 돼 게이트가 무력화된다.)
  const hydrated = useRef(false);
  const mineStamp = useStamp(mineSealed, hydrated);
  const peerStamp = useStamp(peerSealed, hydrated);

  // 양측 봉인 완료 — 골드 룰이 내려온다 (장식 전용, 정보는 아래 스텝 한글이 진다)
  const celebrate = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!bothSealed) { celebrate.setValue(0); return; }
    if (!hydrated.current) { celebrate.setValue(1); return; } // 재진입 — 정지값 (스탬프와 같은 once-law)
    const a = Animated.timing(celebrate, {
      toValue: 1, duration: 460, delay: 180, easing: Easing.out(Easing.back(1.5)), useNativeDriver: true,
    });
    a.start();
    return () => a.stop();
  }, [bothSealed, celebrate]);

  // 대기 호흡 — 내가 확인하고 상대를 기다리는 동안에만 (폴링이 실제로 도는 구간)
  const pulse = useRef(new Animated.Value(0)).current;
  const isWaiting = stage === 'waiting';
  useEffect(() => {
    if (!isWaiting) { pulse.setValue(0); return; }
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(pulse, { toValue: 1, duration: 1100, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      Animated.timing(pulse, { toValue: 0, duration: 1100, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [isWaiting, pulse]);

  // [0063] owner Live Activity — starts at the sealed handoff (server truth: status picked_up),
  // the lab's '인계 완료' card. No 0.00 is drawn (km: '' — the number does not exist yet). From
  // here the lock screen is driven by the APNs pipeline, not this screen; startOwnerActivity also
  // registers the per-activity push token. Re-render repeats are absorbed by the controller
  // (adopt-existing, update-in-place).
  useEffect(() => {
    if (stage !== 'confirmed' || !bookingId || !info) return;
    startOwnerActivity(bookingId, {
      phase: 'pre', dogName: info.dogName, runnerName: info.runnerName ?? '러너',
      km: '', targetKm: String(info.km), pace: '', elapsed: '', statusLine: '',
    });
  }, [stage, bookingId, info]);

  // [P2-12] 반드시 마지막 effect — 같은 커밋에서 useStamp·celebrate effect가 먼저 실행된 뒤에
  // 게이트가 열린다. 첫 동기화가 이미 봉인 상태였다면 그 커밋은 점프, 그 다음 봉인부터 애니메이션.
  useEffect(() => { if (synced) hydrated.current = true; }, [synced]);

  // Dock geometry — the arrived CTA left the flow, so the scroll has to reserve its height
  // (dock padTop 12 + hint 19 + gap 8 + PaperBtn 54 + safe-area pad). Plain arithmetic, no hook.
  const dockPadBottom = insets.bottom + 12;
  const dockH = 12 + 19 + 8 + 54 + dockPadBottom;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* [11b′] Real in-flow header — the old absolute topBar floated over the map plate, which
          cost the plate its top 90pt and put the only 채팅 entry inside the runner card. Now the
          screen names itself (인계) and 채팅 sits where every other screen puts it. paddingTop is
          the safe area, injected from JSX (a fixed value here would win over the inset). */}
      <View style={[s.header, { paddingTop: insets.top }]}>
        <Pressable onPress={() => router.back()} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={s.headerTtl} numberOfLines={1}>인계</Text>
        {/* [0114 · ui2-3, verify-only] 수락 전에는 이 문에 닿을 수 없다 — 확인된 게이트 사슬:
            진입은 home-hero.tsx:68(goState 'handoff'|'confirmed')과 push.ts:61(직전에
            fetchCurrentOwnerBookingId로 IN_FLIGHT 확인)뿐이고, bookingId가 비면 이 파일
            :102-110이 fetchCurrentOwnerBookingId(IN_FLIGHT = confirmed/runner_enroute/
            picked_up/active, api.ts:1036·1049-1056)로만 복원한 뒤 없으면 Alert + back 한다.
            `: {}` 폴백도 bare /chat의 같은 IN_FLIGHT 리졸버로 떨어진다. 게이트 추가 불필요 —
            수락 전 죽은 채팅 문은 owner/schedule.tsx의 예약 시트 칩 하나뿐이었다 (ui2-1). */}
        <Pressable
          onPress={() => router.push({ pathname: '/chat', params: bookingId ? { bid: bookingId } : {} })}
          hitSlop={10} accessibilityRole="button" accessibilityLabel="채팅 열기"
        >
          <Text style={s.headerLink}>채팅 ›</Text>
        </Pressable>
      </View>

      {/* [11b′] 상태 줄 — the expression is unchanged (it was the ink pill's text); only the
          surface moved to the coral wash strip the lab draws. 상태 도트 = 시맨틱, 강조 예산 면제:
          앰버 = 아직 내 차례가 아님 · 코랄 = 내 차례. 도착은 스테이지가 아니라 arrivedAt이
          결정한다 (머신 매핑은 동결) — 코랄은 arrivedAt이 참일 때만 켜진다. */}
      <View style={s.alert}>
        <View style={[s.alertDot, { backgroundColor: arrivedAt ? paper.action : paper.pending }]} />
        <Text style={s.alertText} numberOfLines={2}>
          {arrivedAt ? `${runnerName} 러너 도착`
            : stage === 'enroute' ? `${runnerName} 러너 매칭됨 — 출발 대기`
            : `${runnerName} 러너 이동 중`}
        </Text>
      </View>

      {/* map plate — real pickup map when the address has a pin (0065); otherwise the
          honest dark state now carries its own fix path (P4: the owner CAN fix it).
          Pure JSX swap in the frozen slot; PickupMap memoized (ES-3), height 290 → 190
          (11b′ density: the plate states where, the block under it says it in words). */}
      <View style={s.mapPlate}>
        {pin.s === 'ok' && pin.c?.lat != null && pin.c.lng != null ? (
          <PickupMap lat={pin.c.lat} lng={pin.c.lng} />
        ) : (
          <>
            <View style={s.roadA} />
            <View style={s.roadB} />
            {[0, 1, 2, 3, 4].map((i) => (
              // [정직 배치 2.5] 경로 점은 '아는 경로'가 아니라 지면 무늬 — 주장 강도를 낮춘다
              <View key={i} style={[s.pathDot, { right: 60 + i * 42, top: 80 + i * 26, opacity: stage === 'enroute' ? 0.35 : 0.2 }]} />
            ))}
            <View style={[s.runnerPin, stage !== 'enroute' && { right: 260, top: 128 }]}>
              <Text style={s.pinText}>{runnerName[0]}</Text>
            </View>
            <View style={s.pickupPin}><Text style={s.pinText}>픽업</Text></View>

            {/* [정직 배치 2.5 · 감사 #28 → 0065 DS-3/DF-8] box-none so the plate stays
                inert except the pending box itself, which now holds the fix path:
                no-pin → 위치 지정하기 link (picker for the assigned address, or the
                address list when the booking has none); fetch error → inline retry. */}
            <View pointerEvents="box-none" style={s.mapPendingWrap}>
              <View style={s.mapPending}>
                {pin.s === 'err' ? (
                  <Pressable onPress={() => setPinTry((n) => n + 1)} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
                    <Text style={s.mapPendingTxt}>정보를 불러오지 못했어요</Text>
                    <Text style={s.mapPendingLink}>다시 시도</Text>
                  </Pressable>
                ) : pin.s === 'ok' ? (
                  <Pressable
                    onPress={() => pin.c
                      ? router.push({ pathname: '/owner/address-pin', params: { id: pin.c.addressId } })
                      : router.push('/owner/addresses')}
                    hitSlop={8} accessibilityRole="button" accessibilityLabel="위치 지정하기"
                  >
                    <Text style={s.mapPendingTxt}>픽업 위치가 아직 지정되지 않았어요</Text>
                    <Text style={s.mapPendingLink}>위치 지정하기 ›</Text>
                  </Pressable>
                ) : (
                  <Text style={s.mapPendingTxt}>주소 확인 중...</Text>
                )}
              </View>
            </View>
          </>
        )}
      </View>

      {/* contentContainerStyle stays a CONSTANT — the dock clearance rides a spacer View instead,
          so the 8s poll's re-render never hands the content container a fresh style object
          (react-doctor rn-scrollview-dynamic-padding; this screen re-renders on every tick). */}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={s.scrollPad}>
        {/* [11b′ 만남 장소] The block the lab asks for, built out of fields this screen ALREADY
            fetches and threw away: fetchOwnerPickupCoords returns { label, addr, detail } and only
            `detail` was ever drawn. label = the place the owner named, addr = its address line.
            No new fetch, no new server surface, nothing invented.
            [D15 2026-08-12 · Sean "special note … always visible in intermediary"] — the memo strip
            is absorbed here, keeping its whole contract: 지도판 바로 아래, 주소가 있는 **모든
            상태**에서, 메모가 없으면 '추가' 초대, 있으면 문장 + 수정 문. 이 문장(addresses.detail)은
            배정된 러너가 인계 화면에서 읽는 줄인데(runner/meetup.tsx:332) 정작 그걸 쓴 보호자는
            볼 방법이 없었다 — 그 이유가 여전히 이 블록을 여기에 묶어 둔다.
            로딩·에러 상태에서는 아무 주장도 하지 않는다 — 위 지도판이 이미 그 상태를 말한다. */}
        {pin.s === 'ok' && pin.c && (
          <Pressable
            onPress={() => router.push('/owner/addresses')}
            style={s.place}
            accessibilityRole="button"
            accessibilityLabel={pin.c.detail ? '픽업 메모 수정' : '픽업 메모 추가'}
          >
            <Text style={s.noteK}>만남 장소</Text>
            {!!pin.c.label && <Text style={s.placeTtl} numberOfLines={2}>{pin.c.label}</Text>}
            {!!pin.c.addr && <Text style={s.placeAddr} numberOfLines={2}>{pin.c.addr}</Text>}
            {pin.c.detail
              ? <Text style={s.placeNote}>{pin.c.detail}</Text>
              : <Text style={s.noteEmpty}>아직 없어요 — 만날 지점을 한 줄로 남겨보세요</Text>}
            <Text style={s.noteGo}>{pin.c.detail ? '메모 수정 ›' : '메모 추가 ›'}</Text>
          </Pressable>
        )}

        {/* runner card — 낯선 사람이 내 개를 데려간다: 신원이 먼저다 */}
        {/* [정직 배치 item 8] '신원인증' 배지 은퇴 — 뒷받침하는 데이터 소스가 어디에도 없다 (P1-6) */}
        <View style={s.section}>
          <Row style={{ gap: 12 }}>
            <Monogram char={runnerName[0]} bg={paper.ink} size={46} />
            <View style={{ flex: 1 }}>
              {/* [320dp] 긴 이름은 잘리지 않고 두 줄로 접힌다 (신뢰 화면에서 말줄임 금지) */}
              <Text style={s.peerName} numberOfLines={2}>{runnerName} 러너</Text>
              <Text style={s.peerMeta} numberOfLines={2}>
                {info ? `${info.when} · ${info.routeName} ${info.km}km` : '예약 정보 불러오는 중...'}
              </Text>
            </View>
          </Row>
        </View>

        {/* [11b′ 챙겼나요] 보호자 자신을 위한 체크리스트 — 로컬 상태뿐이고 아무것도 게이트하지 않는다.
            러너 쪽 프리플라이트(runner/meetup.tsx:442)와 같은 로컬 문법이지만, 카피는 철저히
            '내가 챙길 것'이다: 이 칩은 러너의 장비에 대한 주장이 아니다 (그런 주장을 뒷받침하는
            서버 진실이 없다). 도착 단계에서만 뜬다 — 그때만 할 일이 되기 때문. */}
        {stage === 'arrived' && (
          <View style={s.section}>
            <Text style={s.noteK}>챙겼나요</Text>
            <Row style={{ gap: 6, marginTop: 8 }}>
              {([['leash', '목줄'], ['water', '물'], ['treats', '간식']] as const).map(([k, ko]) => (
                <Pressable
                  key={k}
                  onPress={() => { haptic('light'); setGear((g) => ({ ...g, [k]: !g[k] })); }}
                  style={[s.gearChip, gear[k] && s.gearChipOn]}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: gear[k] }}
                  accessibilityLabel={ko}
                >
                  <Text style={[s.gearChipTxt, gear[k] && s.gearChipTxtOn]}>{ko}{gear[k] ? ' ✓' : ''}</Text>
                </Pressable>
              ))}
            </Row>
            <Text style={s.gearSub}>내가 챙길 것들이에요 — 체크하지 않아도 인계할 수 있어요</Text>
          </View>
        )}

        {/* handoff ceremony — 이중 봉인 + 정직한 순서 */}
        <View style={s.section}>
          <Row style={{ gap: 8 }}>
            <View style={{ flex: 1 }}>
              <Text style={s.kick}>HANDOFF</Text>
              <Text style={[s.ttl, df]}>인계 확인</Text>
            </View>
            <View style={[s.countPill, bothSealed && s.countPillOn]}>
              <Text style={[s.countText, bothSealed && s.countTextOn]}>확인 {sealCount}/2</Text>
            </View>
          </Row>

          {/* 봉인 스텁 — 두 개의 도장 자리, 가운데 천공. 자리는 서버 진실로만 채워진다 */}
          <View style={s.band}>
            <SealSlot
              caps="OWNER" name="나" tilt={-7}
              sealed={mineSealed} anim={mineStamp} pulse={null}
              state={mineSealed ? '확인 완료' : '확인 전'}
            />
            <SealSlot
              caps="RUNNER" name="러너" tilt={6}
              sealed={peerSealed} anim={peerStamp} pulse={isWaiting ? pulse : null}
              state={peerSealed ? '확인 완료' : '확인 대기'}
            />
            <View pointerEvents="none" style={s.perfWrap}>
              <View style={s.perfLine} />
              <View style={[s.notch, { top: -8 }]} />
              <View style={[s.notch, { bottom: -8 }]} />
            </View>
          </View>

          {bothSealed && (
            <Animated.View
              style={[s.ribbon, {
                opacity: celebrate.interpolate({ inputRange: [0, 1], outputRange: [0, 1], extrapolate: 'clamp' }),
                transform: [{ scale: celebrate.interpolate({ inputRange: [0, 1], outputRange: [0.9, 1] }) }],
              }]}
            >
              <View style={s.ribbonRule} />
              <Text style={s.ribbonCaps}>SEALED</Text>
              <View style={s.ribbonRule} />
            </Animated.View>
          )}

          <View style={s.steps}>
            <Step first done label="러너 수락 완료" />
            {/* [정직 배치 2.5 · 감사 #30] 스테이지 이름이 실제 의미와 뒤집혀 있다(동결된 매핑):
                'enroute' = 러너 수락 후 출발 전, 'arrived' = 러너가 실제로 이동 중.
                머신은 건드리지 않고 라벨만 위 pill(:210)의 어휘에 맞춘다. */}
            {/* 도착 라벨은 '지금 그 단계일 때'만 — 인계 이후(waiting·confirmed)엔 이동 라벨이 남는다 */}
            <Step
              done={stage !== 'enroute'} active={stage === 'enroute'}
              label={stage === 'enroute' ? '러너 출발 대기'
                : arrivedAt && stage === 'arrived' ? '러너 픽업 장소 도착'
                : '러너가 픽업 장소로 이동'}
            />
            {/* 양측 확인 상태를 각각 서버 진실로 표시 — 누가 누굴 기다리는지 추측 금지 */}
            <Step
              done={stage === 'waiting' || stage === 'confirmed'}
              active={stage === 'arrived'}
              label={
                stage === 'waiting' || stage === 'confirmed' ? '내 인계 확인 완료'
                : `${dogName} 인계 확인 (양측 모두 확인해야 시작돼요)`
              }
            />
            <Step
              last
              done={peerConfirmed || stage === 'confirmed'}
              active={!peerConfirmed && stage === 'waiting'}
              label={peerConfirmed || stage === 'confirmed' ? '러너 인계 확인 완료' : '러너 인계 확인 대기'}
            />
          </View>
        </View>

        {/* action */}
        {stage === 'enroute' && (
          <View style={s.status}>
            <Row style={{ gap: 4 }}>
              <View style={s.pulseStage}><View style={[s.pulseCore, { backgroundColor: paper.pending }]} /></View>
              <Text style={s.statusKick}>WAITING</Text>
            </Row>
            <Text style={s.statusText}>러너의 출발을 기다리는 중...</Text>
            {/* [wave 3] 도착이 서버 진실이 됐다 (bookings.arrived_at + '러너 도착' 알림) — 옛 주석의
                '도착 상태는 서버에 없다'와 '도착은 채팅으로' 카피는 이제 거짓이라 은퇴한다.
                이 카드는 출발 전에만 뜨므로 arrivedAt 분기는 사실상 안 닿지만, 상태가 앞서 도착해도
                화면이 거짓말하지 않도록 조건을 남겨둔다. */}
            <Text style={s.statusSub}>러너가 출발하면 알림을 보내드려요 · 도착하면 다시 알려드려요</Text>
            {/* [2026-08-11 owner cancel] Secondary destructive affordance — paper destructive
                grammar (canvas + 1px critical border + critical ink, criticalWash pressed) via
                PaperBtn. Pre-departure tier: free >=24h out, else 10%. (0066: the en-route
                stage below now carries its own cancel at the 50% tier.) */}
            <PaperBtn
              label="예약 취소" busyLabel="취소 처리 중..." variant="destructive"
              onPress={cancel} busy={cancelling} style={{ alignSelf: 'stretch', marginTop: 14 }}
            />
          </View>
        )}
        {stage === 'arrived' && (
          <View style={s.actions}>
            {/* [11b′] 계약 행동(인계 확인)은 아래 고정 도크로 내려갔다 — 이 존에는 취소만 남는다.
                화면당 코랄 면 CTA는 여전히 하나(도크의 그것)이고, 취소는 destructive 문법이다. */}
            {/* [2026-08-11 owner cancel · 0066] The old "취소 마감" closure line retired — the
                server now accepts runner_enroute → cancelled_owner at a 50% fee (runner
                compensation), so the honest surface is a real destructive action whose
                confirm dialog states that tier before committing (cancel() above). The
                hint keeps the number visible before the tap, same 50% framing as
                schedule.tsx's management sheet. */}
            <PaperBtn
              label="예약 취소" busyLabel="취소 처리 중..." variant="destructive"
              onPress={cancel} busy={cancelling} style={{ alignSelf: 'stretch', marginTop: 0 }}
            />
            {/* [2026-08-19 정직 교정] '차감' → '청구'. 러닝 전에는 잡아둔 돈이 없으므로 차감할 것이
                없다 — cancel()의 확인 다이얼로그는 이미 '청구'라고 말한다(:210). 한 화면에서 같은
                수수료를 두 단어로 부르던 모순만 제거했다. 숫자(50%)는 그대로. */}
            <Text style={[s.ctaHint, { marginTop: 8 }]}>이동 중 취소는 결제 금액의 50%가 수수료로 청구돼요 — 출발한 러너의 보상으로 쓰여요</Text>
          </View>
        )}
        {stage === 'waiting' && (
          <View style={s.status}>
            <Row style={{ gap: 4 }}>
              <View style={s.pulseStage}>
                <Animated.View
                  pointerEvents="none"
                  style={[s.pulseHalo, {
                    opacity: pulse.interpolate({ inputRange: [0, 1], outputRange: [0.34, 0.06] }),
                    transform: [{ scale: pulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.9] }) }],
                  }]}
                />
                <View style={s.pulseCore} />
              </View>
              <Text style={s.statusKick}>WAITING</Text>
            </Row>
            <Text style={s.statusText}>러너 확인 대기 중...</Text>
          </View>
        )}
        {stage === 'confirmed' && (
          <View style={s.night}>
            <Text style={s.nightKick}>SEALED</Text>
            <Text style={s.nightText}>인계 완료! 러너가 곧 러닝을 시작해요</Text>
            <Text style={s.nightSub}>시작되면 자동으로 라이브 화면으로 전환돼요</Text>
          </View>
        )}

        {/* [정직 배치 · item 7 + P1-22] 서명된 보험 증권도, 10분 자동 에스컬레이션 타이머·채널도 없다.
            둘 다 은퇴하고 협의 중 진실 한 문장만 남긴다 (탭 → 안심 센터). */}
        <Pressable onPress={() => router.push('/safety')} accessibilityRole="link" accessibilityLabel="안심 센터 열기">
          <Text style={s.foot}>펫보험 파트너십 협의 중 — 사고 시 안심 센터에서 바로 도와드려요</Text>
        </Pressable>

        {/* 도크가 가리는 만큼의 자리 — 마지막 줄(안심 센터)이 고정 CTA 뒤로 숨지 않는다 */}
        {stage === 'arrived' && <View style={{ height: dockH }} />}
      </ScrollView>

      {/* [11b′ · request.tsx:1352 도크 문법] 인계 CTA는 이제 바닥에 고정된다 — 도착한 러너가 문
          앞에 서 있는 동안 스크롤 위치와 무관하게 계약 행동이 손 닿는 곳에 있어야 한다.
          면은 불투명 캔버스(반투명이면 '떠 있는 CTA'가 아니라 반쯤 가린 콘텐츠로 읽힌다),
          위 가장자리는 코랄 헤어라인 1px, 세이프에어리어는 도크 안쪽 패딩으로 존중한다.
          onPress·handoff·실패 경로는 전부 그대로 — 컨테이너만 바뀌었다. */}
      {stage === 'arrived' && (
        <View style={[s.ctaDock, { paddingBottom: dockPadBottom }]}>
          <Text style={s.dockHint}>러너도 확인하면 러닝이 시작돼요</Text>
          {/* 화면당 코랄 면 CTA 1개 — 이 화면의 계약 행동은 인계 확인 하나뿐.
              라벨의 동사는 RULING 8(현재 UI를 그대로 가져온다)에 따라 유지, 작은 화살표는 RULING 6. */}
          <PaperBtn label={`${dogName}를 인계했어요 ›`} onPress={handoff} style={{ marginTop: 8 }} />
        </View>
      )}
    </View>
  );
}

// ---------- 봉인 자리 — 비어 있으면 점선 링, 채워지면 골드 소인 ----------
function SealSlot({ caps, name, state, sealed, tilt, anim, pulse }: {
  caps: string; name: string; state: string; sealed: boolean; tilt: number;
  anim: Animated.Value; pulse: Animated.Value | null;
}) {
  return (
    <View style={s.slot}>
      <View style={s.slotStage}>
        {!sealed && !!pulse && (
          <Animated.View
            pointerEvents="none"
            style={[s.slotBreath, {
              opacity: pulse.interpolate({ inputRange: [0, 1], outputRange: [0.12, 0.5] }),
              transform: [{ scale: pulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.16] }) }],
            }]}
          />
        )}
        {sealed ? (
          <>
            {/* 착지 파문 — 정지값 0 (재진입·대기 중엔 파문 없음) */}
            <Animated.View
              pointerEvents="none"
              style={[s.slotRipple, {
                opacity: anim.interpolate({ inputRange: [0, 0.0001, 1], outputRange: [0, 0.75, 0] }),
                transform: [{ scale: anim.interpolate({ inputRange: [0, 1], outputRange: [1, 1.85] }) }],
              }]}
            />
            <Animated.View
              style={[s.slotSeal, {
                opacity: anim.interpolate({ inputRange: [0, 0.55, 1], outputRange: [0, 1, 1], extrapolate: 'clamp' }),
                transform: [
                  { scale: anim.interpolate({ inputRange: [0, 1], outputRange: [2.4, 1] }) },
                  { rotate: anim.interpolate({ inputRange: [0, 1], outputRange: [`${tilt - 7}deg`, `${tilt}deg`] }) },
                ],
              }]}
            >
              <Text style={s.slotMark}>✓</Text>
              <Text style={s.slotCaps}>{caps}</Text>
            </Animated.View>
          </>
        ) : (
          <View style={s.slotEmpty}><Text style={s.slotCapsOff}>{caps}</Text></View>
        )}
      </View>
      <Text style={s.slotName} numberOfLines={1}>{name}</Text>
      <Text style={[s.slotState, sealed && s.slotStateOn]} numberOfLines={1}>{state}</Text>
    </View>
  );
}

function Step({ label, done, active, first, last }: { label: string; done?: boolean; active?: boolean; first?: boolean; last?: boolean }) {
  return (
    <View style={[s.stepRow, first && { marginTop: 0 }]}>
      <View style={s.stepCol}>
        {!last && <View style={[s.rail, done && s.railOn]} />}
        <View style={[s.stepDot, active && !done && s.stepDotActive, done && s.stepDotDone]}>
          {done ? <Text style={s.stepTick}>✓</Text> : active ? <View style={s.stepCore} /> : null}
        </View>
      </View>
      <Text style={[s.stepLabel, active && !done && s.stepLabelActive, done && s.stepLabelDone]}>
        {label}
      </Text>
    </View>
  );
}

// 섹션 좌우 여백 — 밴드 marginHorizontal −26의 짝 (H7 산술: 구 컨테이너 12 + 보더 1 + 카드 패딩 13).
// 이 값 덕분에 밴드가 정확히 화면 끝에서 끝까지 물린다.
const PAD = 26;

const s = StyleSheet.create({
  scrollPad: { paddingBottom: 34 },
  // ── 지도 판 (기능 동일 — 새벽빛 블룸 은퇴, 판이 종이가 된다) ──
  // [11b′] 290 → 190. 판은 '어디인지'를 그리기만 하고, 말은 바로 아래 만남 장소 블록이 한다.
  // 무늬(도로·점·핀)의 좌표는 290 높이에 맞춰져 있었으므로 스타일 쪽 좌표를 190 안으로 당겼다.
  mapPlate: { height: 190, backgroundColor: paper.canvas, overflow: 'hidden', borderBottomWidth: 1, borderBottomColor: paper.line },
  roadA: { position: 'absolute', top: 92, left: -20, right: -20, height: 16, backgroundColor: paper.disabledFill, transform: [{ rotate: '10deg' }] },
  roadB: { position: 'absolute', top: 0, bottom: 0, left: 200, width: 13, backgroundColor: paper.disabledFill, transform: [{ rotate: '-14deg' }] },
  pathDot: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line },
  // 준비 중 오버레이 — request.tsx의 mapPending과 같은 문법(캔버스 면 + 1px 코랄 + dim 14/700)
  mapPendingWrap: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  mapPending: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 10, paddingHorizontal: 14, alignItems: 'center', justifyContent: 'center',
  },
  mapPendingTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.dim, textAlign: 'center' },
  // fix-path line inside the pending box (DS-3) — coral, invitation not error
  mapPendingLink: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.line, textAlign: 'center', marginTop: 5 },
  // 핀은 지리 마커라 원형 예외 — 상태색은 남고(위탁 표면 법) 글로우만 떠난다
  runnerPin: {
    position: 'absolute', right: 34, top: 34, width: 26, height: 26, borderRadius: 13,
    backgroundColor: paper.ink, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: paper.canvas,
  },
  // ── 만남 장소 (구 noteStrip을 흡수 — 이제 제목·주소·메모가 한 블록) ──
  place: { paddingHorizontal: PAD, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: paper.line },
  noteK: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.dim },
  placeTtl: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink, marginTop: 4 },
  placeAddr: { fontSize: 14, lineHeight: 19, color: paper.text, marginTop: 2 },
  // 러너가 인계 화면에서 읽는 바로 그 줄(addresses.detail) — 조용하지만 dim(AA) 하한 위
  placeNote: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 5 },
  noteEmpty: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 5 },
  noteGo: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.actionInk, marginTop: 7, textAlign: 'right' },
  pickupPin: {
    position: 'absolute', left: 60, top: 128, width: 36, height: 26, borderRadius: 13,
    backgroundColor: paper.line, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: paper.canvas,
    opacity: 0.4, // [정직 배치 2.5] 실좌표가 아니다 — 지면 무늬로 강등
  },
  pinText: { fontSize: 14, lineHeight: 18, fontWeight: '900', color: '#fff' },

  // ── 헤더 (인플로우 — 구 absolute topBar 은퇴, request.tsx의 §C .top 문법) ──
  header: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: paper.canvas, paddingHorizontal: layout.gutter, paddingBottom: 10,
  },
  circleBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  headerTtl: { flex: 1, fontSize: 20, lineHeight: 26, fontWeight: '800', color: paper.ink },
  headerLink: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.ink },

  // ── 상태 줄 (코랄 워시 스트립 — 랩 11b′의 .alert) ──
  alert: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: paper.wash, paddingVertical: 12, paddingHorizontal: layout.gutter,
  },
  alertDot: { width: 8, height: 8, borderRadius: 4 },
  alertText: { flex: 1, fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.ink },

  // ── 섹션 (풀블리드 — 카드·라운드·섀도·이중 프레임 은퇴, 코랄 1px만이 면을 나눈다) ──
  section: { paddingHorizontal: PAD, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: paper.line },
  peerName: { flexShrink: 1, fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink },
  peerMeta: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 3 },

  // ── 챙겼나요 칩 (러너 프리플라이트의 checkRow 문법을 칩으로 — 캔버스/1px, on은 워시 면) ──
  gearChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 9, paddingHorizontal: 14 },
  gearChipOn: { backgroundColor: paper.wash },
  gearChipTxt: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: paper.text },
  gearChipTxtOn: { fontWeight: '800', color: paper.actionInk },
  gearSub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 8 },

  // ── 의식 헤더 ──
  kick: { fontSize: 12, fontWeight: '700', letterSpacing: 3, color: paper.faint }, // 장식 클래스 (14pt 플로어 면제)
  ttl: { fontSize: 20, fontWeight: '900', color: paper.ink, marginTop: 3 },
  countPill: { alignSelf: 'flex-start', backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 4, paddingHorizontal: 9 },
  countPillOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  countText: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.text },
  countTextOn: { color: '#fff' },

  // ── 아티팩트 = 봉인 스텁 (나이트 풀블리드 · 코랄 헤어라인 심 · 가운데 천공) ──
  // 밤 지면 안의 어휘는 그대로 살아남는다: 골드 소인 · SEAL_INK · NIGHT_DIM.
  // [H6] band/slot/slotStage에 overflow 추가 금지 — 립플이 1.85배(133px)로 무대 밖까지 퍼진다.
  // [11b′ I2] 위 H6 산술은 지름 72 기준이었다 — 64로 줄인 뒤에도 파문은 1.85배(118px)로 무대(68)
  // 밖까지 퍼지므로 금지는 그대로 유효하다.
  // [11b′ I2] 세리머니 여백을 조였다: 밴드 패딩 18→14, 봉인 지름 72→64(네 개 전부 함께 —
  // ripple/breath/empty/seal이 같은 값이어야 파문이 소인과 동심으로 남는다), 무대 76→68.
  band: {
    marginHorizontal: -PAD, marginTop: 14, flexDirection: 'row', alignItems: 'flex-start',
    backgroundColor: NIGHT, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.line,
    paddingVertical: 14, paddingHorizontal: 8,
  },
  perfWrap: { position: 'absolute', left: '50%', marginLeft: -7.5, top: 0, bottom: 0, width: 15 },
  perfLine: { position: 'absolute', top: 0, bottom: 0, left: 6.75, borderLeftWidth: 1.5, borderStyle: 'dashed', borderColor: PERF },
  notch: { position: 'absolute', left: 0, width: 15, height: 15, borderRadius: 7.5, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line },
  slot: { flex: 1, alignItems: 'center', paddingHorizontal: 4 },
  slotStage: { width: 68, height: 68, alignItems: 'center', justifyContent: 'center' },
  slotRipple: { position: 'absolute', width: 64, height: 64, borderRadius: 32, borderWidth: 2, borderColor: GOLD },
  slotBreath: { position: 'absolute', width: 64, height: 64, borderRadius: 32, borderWidth: 2, borderColor: NIGHT_DIM },
  slotEmpty: {
    width: 64, height: 64, borderRadius: 32, borderWidth: 1.5, borderColor: PERF,
    backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center', justifyContent: 'center',
  },
  slotSeal: {
    width: 64, height: 64, borderRadius: 32, borderWidth: 2, borderColor: GOLD, backgroundColor: GOLD_SOFT,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: GOLD, shadowOpacity: 0.38, shadowRadius: 9, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  slotMark: { fontSize: 21, lineHeight: 25, fontWeight: '900', color: SEAL_INK },
  // [FLOOR14 예외] 트래킹 라틴 캡스 키커 — 역할 각인. 읽는 정보는 아래 한글 두 줄이 진다.
  slotCaps: { fontSize: 8.5, fontWeight: '800', letterSpacing: 1.6, color: SEAL_INK, marginTop: 1 },
  slotCapsOff: { fontSize: 8.5, fontWeight: '800', letterSpacing: 1.6, color: NIGHT_DIM },
  slotName: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff', marginTop: 8 },
  slotState: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: NIGHT_DIM, marginTop: 2 },
  slotStateOn: { color: GOLD_SHEEN, fontWeight: '800' },
  // SEALED 룰 — 밴드와 한 몸인 의식의 콜로폰이라 골드가 남는다 (크롬에는 골드 금지)
  ribbon: { flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 12, paddingHorizontal: 2 },
  ribbonRule: { flex: 1, height: 1, backgroundColor: GOLD_SHEEN },
  ribbonCaps: { fontSize: 9.5, fontWeight: '800', letterSpacing: 2.6, color: SEAL_INK },

  // ── 스텝 레일 (정직한 순서 — 완료 잉크 / 진행 코랄 링 / 미완 페인트) ──
  // [11b′ I2] steps 14→12, 행 간격 11→9 — rail의 bottom은 행 간격의 음수여야 다음 점까지 이어진다.
  steps: { marginTop: 12 },
  stepRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, marginTop: 9 },
  stepCol: { width: 20, alignSelf: 'stretch', alignItems: 'center' },
  rail: { position: 'absolute', left: 9.5, top: 21, bottom: -9, width: 1, backgroundColor: paper.faint },
  railOn: { backgroundColor: paper.ink },
  stepDot: {
    width: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.faint,
  },
  stepDotDone: { backgroundColor: paper.ink, borderColor: paper.ink },
  stepDotActive: { backgroundColor: paper.canvas, borderWidth: 2, borderColor: paper.line },
  stepCore: { width: 7, height: 7, borderRadius: 4, backgroundColor: paper.line },
  stepTick: { fontSize: 11, lineHeight: 14, fontWeight: '900', color: '#fff' },
  // 미완 라벨도 읽히는 정보라 dim(AA) — faint는 캡스 키커 전용
  stepLabel: { flex: 1, fontSize: 14.5, lineHeight: 20, fontWeight: '500', color: paper.dim },
  stepLabelDone: { color: paper.ink, fontWeight: '700' },
  stepLabelActive: { color: paper.text, fontWeight: '700' },

  // ── 행동 존 (버튼 매트릭스는 PaperBtn이 진다 — 여기는 자리와 힌트만) ──
  actions: { paddingHorizontal: PAD, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: paper.line },
  ctaHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, textAlign: 'center', marginTop: 10 },
  // ── 고정 CTA 도크 (request.tsx:1352 문법) — bottom:0까지 불투명 캔버스 + 코랄 헤어라인 1px.
  //    paddingBottom은 JSX가 세이프에어리어로 주입한다 (여기 고정값을 두면 그 값이 이긴다) ──
  ctaDock: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderTopColor: paper.line,
    paddingTop: 12, paddingHorizontal: layout.gutter,
  },
  dockHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, textAlign: 'center' },
  status: {
    backgroundColor: paper.canvas, borderBottomWidth: 1, borderBottomColor: paper.line,
    paddingVertical: 16, paddingHorizontal: PAD, alignItems: 'center',
  },
  statusKick: { fontSize: 12, fontWeight: '700', letterSpacing: 3, color: paper.faint },
  statusText: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink, marginTop: 7, textAlign: 'center' },
  statusSub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 4, textAlign: 'center' },
  // 헤일로가 1.9배(15.2px)로 퍼져도 무대(16) 안에 든다 — 안드로이드 클리핑 회피
  pulseStage: { width: 16, height: 16, alignItems: 'center', justifyContent: 'center', overflow: 'visible' },
  pulseHalo: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line },
  pulseCore: { width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line },
  // 인계 완료 카드 = 의식의 끝에 남는 두 번째 아티팩트 (심 룰 (c)) — 위 심은 앞 섹션의 코랄 1px
  night: {
    backgroundColor: NIGHT, borderBottomWidth: 1, borderBottomColor: paper.line,
    paddingVertical: 20, paddingHorizontal: PAD, alignItems: 'center',
  },
  nightKick: { fontSize: 10, fontWeight: '800', letterSpacing: 2.6, color: GOLD_SHEEN },
  nightText: { fontSize: 18, lineHeight: 24, fontWeight: '900', color: '#fff', marginTop: 7, textAlign: 'center' },
  nightSub: { fontSize: 14, lineHeight: 19, color: NIGHT_DIM, marginTop: 5, textAlign: 'center' },
  foot: { fontSize: 14, lineHeight: 19, color: paper.dim, textAlign: 'center', marginTop: 16, paddingHorizontal: PAD },
});
