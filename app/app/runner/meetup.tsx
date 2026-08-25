import { router } from 'expo-router';
import { ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { PickupMap } from '../../src/components/PickupMap';
import { Avatar, Icon, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingAddress, fetchBookingSync, fetchCurrentRunnerJobId, fetchMeetupInfo, MeetupInfo, PickupAddress, runnerArrived, runnerEnroute, startRunServer, subscribeBooking } from '../../src/lib/api';
import { lateness } from '../../src/lib/lateness';
import { LateNotice } from '../../src/components/late-notice';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { clampSuggest } from '../../src/lib/pace';
import { runnerJob } from '../../src/store';
import { layout, paper } from '../../src/theme';

// 픽업 이동 & 인계 확인 — the trust-critical handoff moment.
// accept → navigate to pickup → 도착 확인 → BOTH parties confirm → run unlocks.
// Real version: live nav (maps), push to owner, mutual confirmation via backend.
//
// 보호자 화면과 같은 의식을 반대편에서 본다: 같은 이중 봉인 스텁 · 같은 스텝 레일 · 역할 카피만 다름.
// 봉인 자리는 서버 진실(stage / peerConfirmed)로만 채워진다. 장비 체크는 러너 프리플라이트(로컬).
// 로직 동결: 스테이지 머신·구독/폴링·confirmHandoff·startRunServer·라우팅·게이트 전부 원본 그대로.
//
// [2026-08-06 심 룰 리페인트 · 정직 배치 item 8] 테일러드 라일락 은퇴 → 순백/코랄.
// 법: "dark is the artifact, light is the screen" — 봉인 밴드만 나이트 지면으로 남고(코랄 헤어라인
// 심이 티켓처럼 물린다), 나머지는 전부 순백 크롬. 새벽빛 블룸·이중 프레임·섀도·라운드는 사라지고
// 섹션은 풀블리드 코랄 1px로만 나뉜다. 밀도는 그대로: 스텝 레일·두 봉인 자리·2/2 카운터·
// 프리플라이트 3종 체크는 전부 살아남고 장식만 떠난다 (위탁 표면 법).

const NIGHT = '#1C1837';    // 아티팩트 지면 — 다크 세리머니 월드는 의도적 존속 (theme.ts 순백 법 주석)
const NIGHT_DIM = '#C6BEEB';
const SEAL_INK = '#8a6f2a'; // 소인 잉크
const GOLD = '#B99A4F';     // 봉인 골드 — 밴드 소인·SEALED 룰 전용 (아티팩트 어휘, 크롬 금지)
const GOLD_SOFT = '#F4EBD3';
const GOLD_SHEEN = '#D8C185';
const PERF = 'rgba(255,255,255,0.25)'; // 천공 점선 — 밤 지면 위 흰 선

// 권장 페이스 캡션 — 값이 이미 sec/km라 나눗셈이 없다. run.tsx:68 / live.tsx:43과 같은 M'SS" 문법
// (같은 숫자가 이 화면과 러닝 화면에서 다르게 보이면 그게 거짓말이다 — 포맷터를 문자 그대로 맞춘다).
const suggestStr = (sec: number) => `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"`;

type Stage = 'enroute' | 'arrived' | 'waiting' | 'confirmed';

// [정직 배치 2026-08-06 · item 4 wave-1] 하드코딩 픽업 좌표·주소와 네이버 길찾기 숏컷 은퇴 —
// 파일럿 동네와 무관한 성동구 좌표였고, bookings.address_id를 읽는 코드는 어디에도 없었다.
// [wave 3] 실주소가 도착했다 — booking_pickup_address definer RPC(0060). 길찾기·지도는 여전히 없다:
// 프로덕션 lat/lng가 전부 NULL이라 좌표 슬라이스 전까지 그 버튼은 죽은 버튼이다 (죽은 버튼 금지법).

// 봉인 스탬프 — 빈 자리가 '실제로' 채워지는 순간에만 도장이 내려온다 (클럽 영수증 ② 스탬프 문법).
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

export default function Meetup() {
  const df = useDisplayFont();
  // [훅 배치 동결법 · v4 R3c] Oswald 숫자 훅은 **useDisplayFont 바로 옆**에만 — 아래 상태 뭉치의
  // 순서를 건드리지 않는 유일한 자리다. 쓰는 곳은 '이번 러닝' 블록의 목표 km·권장 페이스뿐.
  const nf = useNumFont();
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const dogName = info?.dogName ?? '반려견';
  const [stage, setStage] = useState<Stage>('enroute');
  const [jobId, setJobId] = useState<string | null>(runnerJob.bookingId ?? null);
  const [peerConfirmed, setPeerConfirmed] = useState(false); // 보호자 측 인계 확인 (서버 진실)
  const [synced, setSynced] = useState(false); // 첫 서버 동기화 도착 (스탬프 하이드레이션 판정용)
  // 인계 전 장비 체크리스트 (0019 연계) — 세 가지 모두 체크해야 인계 버튼이 열린다.
  // 로컬 상태로 충분: 서버 계약은 양측 confirm이고, 이 체크는 러너 자신을 위한 프리플라이트.
  const [check, setCheck] = useState({ leash: false, water: false, treats: false });
  // [훅 배치 동결법] 새 useState는 이 상태 뭉치의 끝에만 — 아래 useRef poll부터 순서가 고정이다.
  // 픽업 주소 삼상태를 한 값으로 묶는다 (로딩 / 결과 · 0행이면 a=null / 실패) — '로딩인데 에러' 같은
  // 불가능한 조합이 생기지 않는다. addrTry는 재시도 트리거일 뿐 값 자체는 읽지 않는다.
  const [pickup, setPickup] = useState<{ s: 'loading' } | { s: 'ok'; a: PickupAddress | null } | { s: 'err' }>({ s: 'loading' });
  const [addrTry, setAddrTry] = useState(0);
  // 도착 = 서버 진실 (bookings.arrived_at, 0060). 리마운트해도 syncNow가 되살리므로 성공 힌트가 살아남는다.
  const [arrived, setArrived] = useState(false);
  const [arriveBusy, setArriveBusy] = useState(false);
  const [arriveFail, setArriveFail] = useState<string | null>(null); // 도착 전송 실패 — 라우드 인라인 한 줄
  // [훅 배치 동결법 · 정직법 2026-08-19] 새 useState는 이 상태 뭉치의 **끝**에만 — 위 법이 지정한
  // 그 자리다. 아래 allChecked·poll부터의 순서는 그대로 밀린다 (모든 렌더에서 같은 위치 = 훅 규칙 준수).
  // 왜 필요했나: fetchMeetupInfo 실패가 console.warn으로 삼켜져 화면이 '예약 정보 불러오는 중...'에
  // 영원히 머물렀다 — 로딩으로 위장한 실패다. pickup 삼상태와 같은 문법으로 로드 상태를 한 값에 묶고
  // (불가능한 조합 차단), try는 재시도 트리거일 뿐 값 자체는 읽지 않는다 (addrTry와 같은 규약).
  const [infoLoad, setInfoLoad] = useState<{ s: 'loading' | 'ready' | 'err'; try: number }>({ s: 'loading', try: 0 });
  const allChecked = check.leash && check.water && check.treats;
  const poll = useRef<ReturnType<typeof setInterval> | null>(null);

  // id 복원 — 인메모리 유실 시 서버에서 현재 작업을 찾는다 (데모 전락 방지, 2026-07-23)
  useEffect(() => {
    if (jobId) return;
    fetchCurrentRunnerJobId()
      .then((id) => {
        if (id) { runnerJob.bookingId = id; setJobId(id); }
        else {
          Alert.alert('진행 중인 작업이 없어요', '요청 탭에서 수락하면 이 화면으로 이어져요');
          router.back();
        }
      })
      .catch((e) => console.warn('[r-meetup] resolve:', e?.message ?? e));
  }, [jobId]);

  // 실컨텍스트 — 강아지·코스 실명/실메모 (runRequests 목업 은퇴, ui-audit P0)
  // [정직법 2026-08-19] 실패를 삼키지 않는다. 이 effect의 **자리와 dep 규약은 그대로**다 —
  // 위 fetchCurrentRunnerJobId 다음, 아래 주소 effect 앞. infoLoad.try가 재시도 dep으로 붙는 것은
  // 바로 아래 addrTry가 쓰는 것과 같은 문법이고, alive 가드도 그 effect에서 그대로 가져왔다
  // (빠른 재시도 두 번이 순서를 바꿔 도착해도 옛 응답이 새 응답을 덮지 못한다).
  useEffect(() => {
    if (!jobId) return;
    let alive = true;
    fetchMeetupInfo(jobId)
      .then((v) => { if (alive) { setInfo(v); setInfoLoad((L) => ({ ...L, s: 'ready' })); } })
      .catch((e) => {
        console.warn('[r-meetup] info:', e?.message ?? e);
        if (alive) setInfoLoad((L) => ({ ...L, s: 'err' }));
      });
    return () => { alive = false; };
  }, [jobId, infoLoad.try]);

  // 픽업 실주소 (0060 definer RPC) — 잡이 정해지면 1회, '다시 시도'면 addrTry가 올라 다시 부른다.
  // [훅 배치 동결법] 새 useEffect는 반드시 이 자리(fetchMeetupInfo 다음)에만 — 하이드레이션
  // 게이트 effect는 언제나 마지막이어야 한다.
  useEffect(() => {
    if (!jobId) return;
    let alive = true;
    setPickup({ s: 'loading' });
    fetchBookingAddress(jobId)
      .then((a) => { if (alive) setPickup({ s: 'ok', a }); })
      .catch((e) => {
        // 실패를 '주소 없음'으로 접으면 러너는 영영 재시도 버튼을 못 본다 — 라우드 페일로 남긴다
        console.warn('[r-meetup] addr:', e?.message ?? e);
        if (alive) setPickup({ s: 'err' });
      });
    return () => { alive = false; };
  }, [jobId, addrTry]);

  const syncNow = useCallback(async () => {
    if (!jobId) return;
    try {
      const s2 = await fetchBookingSync(jobId);
      // 종말 상태 — 취소/만료된 예약의 미트업에 좌초 금지 (감사 ③)
      // ⚠ [F4 2026-08-24] 이건 **거부 목록**이었고, 0117 이 처음 쓰는 두 종점(no_show ·
      // incident_review)이 둘 다 목록에 없었다. 그래서 지각 프로토콜의 **엣지가 아니라 정상 경로**
      // — 러너는 '진행하겠다'고 답했고 보호자는 침묵, 마감이 지나 no_show — 에서 러너가 죽은 예약
      // 위에 선다: 스테이지 머신이 s2.arrivedAt 으로 떨어져 'arrived' 에 주차하고, :587 의
      // 인계 CTA 가 살아 있고, confirmHandoff 는 매번 409 라 보호자 앞에서 무한 재시도가 된다.
      // 허용 목록으로 뒤집는다 — 이 트리가 이미 두 번 쓰는 모양이고(api.ts IN_FLIGHT,
      // lateness.ts CAN_BE_LATE), 새 종점이 또 생겨도 기본값이 '바운스'라 조용히 새지 않는다.
      if (!['confirmed', 'runner_enroute', 'picked_up', 'active'].includes(s2.status)) {
        // incident_review 는 '끝났다'가 아니라 '사람이 봐야 한다'는 뜻이다. 개를 데리고 있을 수도
        // 있는 러너에게 「더 진행할 수 없어요」라고 말하면 안 된다 (D3). 0117:644 가 같은 순간에
        // 보내는 푸시와 **같은 낱말**을 쓴다 — 한 사건에 두 어휘가 생기지 않게.
        Alert.alert(
          '예약 상태가 바뀌었어요',
          s2.status === 'completed' ? '이미 완료된 러닝이에요'
            : s2.status === 'incident_review' ? '확인이 필요해요'
            : '이 예약은 더 진행할 수 없어요',
        );
        router.back();
        return;
      }
      setPeerConfirmed(s2.ownerConfirmed);
      setArrived(!!s2.arrivedAt); // 도착도 서버 진실 — 로컬 낙관값을 서버 값에 정렬시킨다
      setSynced(true); // [P2-12] 봉인 진실이 처음 도착한 지점 — 이 커밋 이후부터가 '라이브'
      if (s2.status === 'picked_up' || s2.status === 'active') setStage('confirmed');
      else if (s2.runnerConfirmed) setStage('waiting');
      // 도착 복원 — 이 분기가 없으면 도착 후 리마운트한 러너가 'enroute'에 좌초한다
      // (장비 체크와 인계 CTA가 전부 'arrived' 뒤에 있다). 위 분기가 이긴 경우는 건드리지 않는다.
      else if (s2.arrivedAt) setStage((cur) => (cur === 'enroute' ? 'arrived' : cur));
      // Inverse of the restore above — server truth can also move BACKWARDS: when the owner
      // swaps runners, runner_accept's resetPatch nulls arrived_at and both handoff confirms.
      // Without this the replaced runner's mounted screen stays on 'arrived'/'waiting' and keeps
      // offering the 인계 CTA for a booking it no longer owns (confirmHandoff would 403).
      // Reaching here means: not picked_up/active, no runner confirm, no arrived_at — the local
      // 'arrived'/'waiting' stages are only ever set after a server ack, so a null arrived_at
      // here is a genuine reset. (A sync that raced the ack self-heals on the next poll/event.)
      else setStage((cur) => (cur === 'arrived' || cur === 'waiting' ? 'enroute' : cur));
    } catch { /* 다음 이벤트/폴백이 처리 */ }
  }, [jobId]);

  // 서버에 '이동 중' 보고 + 실시간 구독 (8초 폴링은 폴백)
  // ⚠ [F3b 열린 문 · 2026-08-24] 아래 runnerEnroute 는 **천장 게이트 밖에 있다.** 이 effect 는
  // 마운트 즉시 돌고 info 는 아직 없으므로 pastCeiling 은 그 시점에 항상 false 다 — 즉 17일 된
  // confirmed 예약도 화면을 여는 것만으로 runner_enroute 로 뒤집히고 보호자에게 「러너 이동 중」
  // 푸시가 나간다 (FM4 의 첫 걸음). 여기서 고치지 않는 이유는 두 가지다:
  //   (1) info 를 기다리려면 deps 에 info 를 넣어야 하고, 그러면 구독과 8초 폴링이 info 변화마다
  //       재설치된다 — meetup 의 스테이지 머신·폴링·confirmHandoff 는 DO-NOT-REFACTOR 동결 대상이다.
  //   (2) 진짜 자물쇠는 서버에 있어야 한다: transition-booking:243 은 **미래** 예약만 막고
  //       confirm_handoff·start_run 은 시계를 보지 않는다. 클라이언트 게이트로는 이 문을 못 닫는다.
  // 그래서 이 슬라이스가 닫은 것은 '탭으로 진행하는 문'이고, '열기만 해도 뒤집히는 문'은 열려 있다.
  // Sean 의 Q4(천장은 규칙인가 권고인가)가 답해지면 서버 거부 한 줄로 같이 닫힌다.
  useEffect(() => {
    if (!jobId) return;
    runnerEnroute(jobId).catch(() => { /* 이미 지난 상태면 무시 */ });
    syncNow();
    const unsub = subscribeBooking(jobId, syncNow);
    poll.current = setInterval(syncNow, 8000);
    return () => { if (poll.current) clearInterval(poll.current); unsub(); };
  }, [jobId, syncNow]);

  // 도착 보고 — 서버가 arrived_at을 찍어야만 스테이지가 오른다 (P1-4 정직법과 같은 규칙).
  // 재탭은 서버가 { unchanged: true }로 200을 주므로 throw가 나지 않는다 = 그것도 성공 경로다.
  // 진짜로 잘못된 상태(출발 전 등)만 던지고, 그때는 스테이지를 그대로 둬 CTA가 남는다.
  const reportArrived = async () => {
    if (!jobId || arriveBusy) return;
    setArriveBusy(true);
    setArriveFail(null);
    try {
      await runnerArrived(jobId);
      haptic('success');
      setArrived(true);
      setStage('arrived');
    } catch (e) {
      const msg = (e as Error)?.message ?? '';
      console.warn('[r-meetup] arrived:', msg || e);
      // 서버가 한국어로 이유를 말해줬으면 그대로 쓴다 — 이동 중이 아닐 때의 409는 '새로고침'이라는
      // 실제 복구 경로를 담고 있어서, 일반 문구로 덮으면 영영 안 되는 재시도만 남는다.
      // 통신 실패의 영문 원문(Failed to send a request…)은 화면에 올리지 않고 일반 문구로 접는다.
      setArriveFail(/[가-힣]/.test(msg) ? msg : '도착 알림을 보내지 못했어요 · 다시 시도해주세요');
    } finally {
      setArriveBusy(false);
    }
  };

  // [정직법 P1-4] 실패는 실패로 — 가짜 소인 금지. 서버가 확인을 받아야만 봉인 자리가 채워진다.
  // 전송 실패 시 'arrived'에 남아 CTA가 다시 뜬다 (재시도 경로 보장). 구: catch를 삼키고 무조건 waiting.
  const handoff = async () => {
    if (!jobId) return;
    haptic('success');
    try {
      await confirmHandoff(jobId, 'runner');
      setStage('waiting');
    } catch {
      Alert.alert('인계 확인이 전송되지 않았어요', '다시 시도해주세요');
    }
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
  const checkDone = (check.leash ? 1 : 0) + (check.water ? 1 : 0) + (check.treats ? 1 : 0);

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

  // 대기 호흡 — 내가 확인하고 보호자를 기다리는 동안에만 (폴링이 실제로 도는 구간)
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

  // [P2-12] 반드시 마지막 effect — 같은 커밋에서 useStamp·celebrate effect가 먼저 실행된 뒤에
  // 게이트가 열린다. 첫 동기화가 이미 봉인 상태였다면 그 커밋은 점프, 그 다음 봉인부터 애니메이션.
  useEffect(() => { if (synced) hydrated.current = true; }, [synced]);

  // 길찾기 (0065) — nmap scheme (whitelisted in app.json LSApplicationQueriesSchemes)
  // with a Naver web-map fallback; only rendered when coordinates exist (dead-button
  // law). Plain function, not a hook — the hook-freeze law leaves hook order untouched.
  // ⚠ `appname` MUST equal the app's real bundle identifier (app.json `ios.bundleIdentifier`,
  // now com.seankookim.dogshigh). Naver's nmap:// scheme uses it to route the user BACK, so a
  // stale value does not fail loudly — it opens Naver Maps and then strands the runner there with
  // no way home, which is the worst shape of failure on a screen someone is using while walking a
  // dog. It read com.seankookim.daengrun until 2026-08-21, left behind by the bundle rename.
  // ⚠ NOT the same string as app.json's `scheme`, which is still "daengrun" and must stay — that
  // one is our own deep-link protocol and every daengrun:// link in the app depends on it.
  const openDirections = async (dlat: number, dlng: number, name: string) => {
    const nmap = `nmap://route/walk?dlat=${dlat}&dlng=${dlng}&dname=${encodeURIComponent(name)}&appname=com.seankookim.dogshigh`;
    const web = `https://map.naver.com/p/directions/-/${dlng},${dlat},${encodeURIComponent(name)}/-/walk`;
    try {
      if (await Linking.canOpenURL(nmap)) { await Linking.openURL(nmap); return; }
      await Linking.openURL(web);
    } catch {
      Alert.alert('링크를 열 수 없어요'); // house pattern — no toast primitive (DS-2)
    }
  };
  const hasCoords = pickup.s === 'ok' && pickup.a != null && pickup.a.lat != null && pickup.a.lng != null;

  // [T5] 지각 판정 — 파생값이므로 훅이 아니다. meetup 의 훅 배치 동결법(:134)과 스테이지 머신은
  // 건드리지 않는다: 이 화면은 자기 단계를 이미 정확히 말하고 있고, 여기서 더하는 건 '얼마나
  // 됐는가'와 '지금 누구를 기다리는가' 뿐이다. 랩의 러너 ⑤가 이 자리다.
  const meetLate = info
    ? lateness({ scheduledAt: info.scheduledAt, rawStatus: info.rawStatus,
                 arrivedAt: info.arrivedAt, km: info.km, startedAt: info.startedAt,
                 // [F7] 커스터디는 status 만으로 판정할 수 없다 (lateness.ts 참조)
                 ownerHandoffAt: info.ownerHandoffAt, runnerHandoffAt: info.runnerHandoffAt })
    : null;

  // [F3b 2026-08-24] 천장(LATENESS_CEILING_MS = 3시간, Sean 2026-08-21)을 실제로 **집행하는**
  // 유일한 자리. 그전까지 resumable 은 자기 자신과 문장 한 갈래 말고는 소비자가 없었다 — 아무도
  // 읽지 않는 필드는 아무도 지키지 않는 규칙이고, 그래서 FM4(탭 두 번으로 16일 된 예약이 되살아남)
  // 가 '처리됨'으로 적힌 채 열려 있었다. 서버는 아직 거부하지 않는다(transition-booking:243 은
  // **미래** 예약만 막고, confirm_handoff·start_run 은 시계를 아예 안 본다), 그러니 이건
  // 클라이언트 판정이다 — 그 사실은 late-copy 의 문장이 '불가능'이라고 말하지 않는 이유이기도 하다.
  //
  // 왜 하필 meetup 인가: 러너의 네 입구(홈 :391 · 캘린더 :63 · 요청 :148 · 푸시 :43)가 전부 이
  // 화면으로 모인다. runner/home 의 티켓 하나에 게이트를 달면 나머지 셋이 샌다.
  // 왜 `=== false` 인가: info 가 아직 안 왔으면 meetLate 는 null 이다. `=== true` 로 쓰면 느린
  // fetch 하나가 **정시에 온 러너**의 문을 닫는다. 모르면 닫지 않는다.
  // ⚠ 인계 후(picked_up·active)는 여기 걸리지 않는다 — 스테이지 머신이 :165 에서 'confirmed' 로
  // 보내므로 아래 세 블록은 구조적으로 인계 전이다. 개를 이미 데려간 러너를 아무 문도 없는 곳에
  // 가두지 않는다는 D3 과 충돌하지 않는 이유다.
  const pastCeiling = meetLate?.resumable === false;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* map plate — real pickup map when coords exist (0065), honest placeholder otherwise.
          Pure JSX swap in the frozen slot; PickupMap is memoized so the 8s poll's re-renders
          never touch the native view (ES-3). Plate keeps its exact 300pt height (DS-7). */}
      {meetLate?.late && info ? (
        <View style={{ paddingHorizontal: layout.gutter }}>
          <LateNotice late={meetLate} side="runner" dogName={info.dogName} runnerName={info.runnerName ?? undefined} />
        </View>
      ) : null}
      <View style={s.mapPlate}>
        {hasCoords ? (
          <>
            <PickupMap lat={pickup.a!.lat!} lng={pickup.a!.lng!} />
            <Pressable
              style={s.naviChip}
              onPress={() => openDirections(pickup.a!.lat!, pickup.a!.lng!, pickup.a!.label)}
              hitSlop={6}
              accessibilityRole="button"
              accessibilityLabel="길찾기"
            >
              <Text style={s.naviChipTxt}>길찾기</Text>
            </Pressable>
          </>
        ) : (
          <>
            <View style={s.roadA} />
            <View style={s.roadB} />
            {/* runner → pickup path */}
            <View style={s.pathDots}>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <View key={i} style={[s.pathDot, { left: 40 + i * 44, top: 190 - i * 22 }]} />
              ))}
            </View>
            <View style={s.mePin}><Text style={s.pinText}>나</Text></View>
            <View style={s.pickupPin}><Text style={s.pinText}>픽업</Text></View>

            {/* [정직 배치 2.5 · 감사 #28 → 0065 ES-4] the dark plate names its real cause:
                loading = transient; err = section strip carries the retry; ok-without-
                coords = the owner hasn't pinned — copy routes recovery through chat
                instead of blaming the app (DF-3). */}
            <View pointerEvents="none" style={s.mapPendingWrap}>
              <View style={s.mapPending}><Text style={s.mapPendingTxt}>
                {pickup.s === 'loading' ? '주소 확인 중...'
                  : pickup.s === 'err' ? '지도를 불러오지 못했어요'
                  : '픽업 위치가 아직 지정되지 않았어요\n보호자와 채팅으로 확인해주세요'}
              </Text></View>
            </View>
          </>
        )}

        <Row style={s.topBar}>
          <Pressable onPress={goBackOrHome} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            {/* 상태 도트 = 시맨틱 (이동·도착 앰버 → 인계 완료 세이지). 강조 예산 면제.
                [v4 R3a/b/c] 도착 상태의 코랄(paper.line)을 앰버로 내렸다: 코랄은 그 프레임의
                유일한 문(CTA)이 가져가고, 이 점은 '주의/사실'만 말한다. 인계가 실제로 끝난
                confirmed에서만 ready — 서버 진실(picked_up/active)에서 파생된 스테이지다. */}
            <View style={[s.etaDot, { backgroundColor: stage === 'confirmed' ? paper.ready : paper.pending }]} />
            {/* [P2-11] GPS 없는 도보 8분·0.8km는 조작이었다 — 스테이지에 묶인 사실만 말한다 */}
            <Text style={s.etaText} numberOfLines={2}>
              {stage === 'enroute' ? '픽업 장소로 이동 중' : stage === 'confirmed' ? '인계 완료' : '픽업 장소 도착'}
            </Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 34 }}>
        {/* pickup info — 주소는 서버가 준 것만 그린다 (로딩 / 실주소 / 미지정 / 실패 네 상태) */}
        <View style={s.section}>
          <Text style={s.cardTitle} numberOfLines={1}>
            {pickup.s === 'ok' && pickup.a ? pickup.a.label : '픽업 장소'}
          </Text>
          {pickup.s === 'err' ? (
            /* 라우드 페일 — 침묵도 '미지정' 위장도 아니다. 재시도가 실제로 RPC를 다시 부른다 */
            <View style={s.addrFailStrip}>
              <Text style={s.addrFailTxt}>주소를 불러오지 못했어요</Text>
              <Pressable onPress={() => setAddrTry((n) => n + 1)} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
                <Text style={s.addrFailRetry}>다시 시도</Text>
              </Pressable>
            </View>
          ) : (
            <>
              <Text style={s.cardBody}>
                {pickup.s === 'loading' ? '주소 확인 중...'
                  : pickup.s === 'ok' && pickup.a ? `${pickup.a.addr}${pickup.a.detail ? ` · ${pickup.a.detail}` : ''}`
                  : '픽업 장소는 보호자와 채팅으로 확인해주세요'}
              </Text>
              {/* [D15c 2026-08-12] 주소·메모 **수동** 새로고침.
                  문제: 이 화면이 열려 있는 동안 보호자가 핀을 찍거나 픽업 메모를 고치면, 러너에게는
                  리마운트 전까지 도착하지 않는다 (주소는 잡이 정해질 때 1회만 부른다).
                  자동으로 하지 않는 이유가 진짜다 — 자동 갱신은 8초 부킹 폴을 건드려야 하고 그 폴은
                  DESIGN.md §9 동결 구역이다. 코덱스가 그 경로의 실패 모드를 열거했다: 주소 RPC 실패가
                  부킹 상태 갱신을 삼키고, 겹친 비동기 호출이 옛 주소로 새 핀을 덮고, 매 폴마다
                  loading이 켜지면 지도가 깜빡이고, 상태 게이트 전이가 '아는 주소'를 '주소 없음'으로
                  뒤집고, effect 순서가 바뀌면 인계 세리머니의 1회-법이 재생된다. 인계 직전 화면에서
                  치를 값이 아니다.
                  그래서 이미 있는 addrTry 하나만 노출한다 — 폴은 손대지 않고, 러너가 필요할 때 누른다. */}
              <Pressable
                onPress={() => setAddrTry((n) => n + 1)}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel="픽업 주소와 메모 다시 확인"
                style={{ minHeight: 44, justifyContent: 'center' }}
              >
                <Text style={s.addrRefresh}>주소·메모 다시 확인 ›</Text>
              </Pressable>
            </>
          )}
          {/* [정직법 · 같은 결함의 이웃] '메모가 없어요'는 예약 정보를 **아는** 상태에서만 참이다.
              로드 전이나 실패 상태에서 이 문장을 그리면 모르는 것을 없다고 단언하게 된다 —
              info가 실제로 도착한 뒤에만 그린다 (실패 사실은 바로 아래 줄이 진다). */}
          {info != null && (
            <Text style={s.cardBody}>
              {info.dogMemo ? `보호자 메모: ${info.dogMemo}` : '보호자 메모가 없어요 — 채팅으로 미리 인사해보세요'}
            </Text>
          )}
        </View>

        {/* dog + owner */}
        <View style={s.section}>
          <Row style={{ gap: 12 }}>
            <Avatar url={info?.dogPhotoUrl} char={dogName[0]} bg={paper.ink} size={44} />
            <View style={{ flex: 1 }}>
              <Text style={s.peerName} numberOfLines={2}>
                {dogName}{info?.dogBreed ? ` · ${info.dogBreed}` : ''}{info?.dogWeightKg != null ? ` ${info.dogWeightKg}kg` : ''}
              </Text>
              {/* [정직법] 실패는 실패로. 이 줄은 실패했을 때도 '불러오는 중...'이라고 말해서
                  영원한 로딩으로 위장했다 — 재시도 경로조차 없었다. 이제 세 상태를 각각 그린다. */}
              {info ? (
                <Text style={s.peerMeta} numberOfLines={2}>{`${info.when} · ${info.km}km · ${info.paceLabel}`}</Text>
              ) : infoLoad.s === 'err' ? (
                <Pressable
                  onPress={() => setInfoLoad((L) => ({ s: 'loading', try: L.try + 1 }))}
                  hitSlop={8}
                  style={{ minHeight: 44, justifyContent: 'center' }}
                  accessibilityRole="button"
                  accessibilityLabel="예약 정보 다시 불러오기"
                >
                  <Text style={s.peerFail} numberOfLines={2}>
                    예약 정보를 불러오지 못했어요 · <Text style={s.peerFailRetry}>다시 시도</Text>
                  </Text>
                </Pressable>
              ) : (
                <Text style={s.peerMeta} numberOfLines={2}>예약 정보 불러오는 중...</Text>
              )}
            </View>
            {/* [0114 · ui2-3, verify-only] 수락 전에는 이 문에 닿을 수 없다 — 확인된 게이트 사슬:
                이 화면의 유일한 진입은 requests.tsx:140(acceptBooking이 resolve한 뒤),
                home.tsx:292 · calendar.tsx:63(둘 다 fetchRunnerJobs, api.ts:1173이
                confirmed/runner_enroute/picked_up/active/completed로만 필터)이고, jobId가 비면
                이 파일 :103-112가 fetchCurrentRunnerJobId(IN_FLIGHT, api.ts:1058-1064)로만
                복원한 뒤 없으면 Alert + back 한다. `: {}` 폴백조차 bare /chat의
                IN_FLIGHT 리졸버로 떨어진다. 게이트 추가 불필요 — 상태 게이트가 이미 상류에 있다. */}
            <Pressable style={s.chatChip} onPress={() => router.push({ pathname: '/chat', params: jobId ? { bid: jobId } : {} })}>
              <Text style={s.chatChipText}>보호자 채팅</Text>
            </Pressable>
          </Row>

          {/* Handling facts, added 2026-08-21. These two live on `dogs` and were ALREADY shown on
              the pre-accept request card, then disappeared the moment the runner accepted — the one
              moment they start to matter, because the dog is now theirs. Rendered only when the
              owner actually recorded something: an empty array is a real answer and gets no line,
              not an empty label. Additive render only; the stage machine, the 8s poll and the
              handoff seals are untouched. */}
          {(info?.dogPrefTags?.length || info?.dogVaccines?.length) ? (
            <Row style={{ gap: 6, flexWrap: 'wrap', marginTop: 9 }}>
              {(info?.dogPrefTags ?? []).map((t) => (
                <View key={`t-${t}`} style={s.dogTag}><Text style={s.dogTagTxt}>{t}</Text></View>
              ))}
              {(info?.dogVaccines ?? []).length > 0 && (
                <Text style={s.dogVax} numberOfLines={2}>백신 · {(info?.dogVaccines ?? []).join(' · ')}</Text>
              )}
            </Row>
          ) : null}
        </View>

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
              caps="RUNNER" name="나" tilt={-7}
              sealed={mineSealed} anim={mineStamp} pulse={null}
              state={mineSealed ? '확인 완료' : '확인 전'}
            />
            <SealSlot
              caps="OWNER" name="보호자" tilt={6}
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
            <Step first done label="예약 수락 완료 — 보호자에게 알림 전송됨" />
            <Step done={stage !== 'enroute'} label="픽업 장소 도착" active={stage === 'enroute'} />
            {/* 양측 확인 상태를 각각 서버 진실로 표시 */}
            <Step
              done={stage === 'waiting' || stage === 'confirmed'}
              active={stage === 'arrived'}
              label={stage === 'waiting' || stage === 'confirmed' ? '내 인계 확인 완료' : '내 인계 확인 (양측 모두 확인해야 시작돼요)'}
            />
            <Step
              last
              done={peerConfirmed || stage === 'confirmed'}
              active={!peerConfirmed && stage === 'waiting'}
              label={peerConfirmed || stage === 'confirmed' ? '보호자 인계 확인 완료' : '보호자 인계 확인 대기'}
            />
          </View>
        </View>

        {/* 인계 전 장비 체크 — 도착 후에만 노출, 전부 체크해야 인계 가능 */}
        {/* 천장을 넘기면 이 블록도 같이 닫는다: 아래 CTA 만 감추면 「세 가지를 확인해야 인계를 받을
            수 있어요」가 아무 데도 닿지 않는 문장으로 남는다 (죽은 버튼 금지법의 같은 얼굴). */}
        {!pastCeiling && stage === 'arrived' && (
          <View style={s.section}>
            <Row style={{ gap: 8 }}>
              <View style={{ flex: 1 }}>
                <Text style={s.kick}>PREFLIGHT</Text>
                <Text style={s.gearTitle}>인계 전 장비 체크</Text>
              </View>
              <View style={[s.countPill, allChecked && s.countPillGo]}>
                <Text style={[s.countText, allChecked && s.countTextGo]}>{checkDone}/3</Text>
              </View>
            </Row>
            <Text style={s.gearSub}>세 가지를 확인해야 {dogName} 인계를 받을 수 있어요</Text>
            <CheckRow icon="Cable" label="러닝 리드줄로 교체했어요" on={check.leash} onPress={() => { haptic('light'); setCheck((c) => ({ ...c, leash: !c.leash })); }} />
            <CheckRow icon="Droplet" label={`${dogName} 급수 준비 완료`} on={check.water} onPress={() => { haptic('light'); setCheck((c) => ({ ...c, water: !c.water })); }} />
            <CheckRow icon="Bone" label="간식 파우치 챙겼어요" on={check.treats} onPress={() => { haptic('light'); setCheck((c) => ({ ...c, treats: !c.treats })); }} />
          </View>
        )}

        {/* action */}
        {!pastCeiling && stage === 'enroute' && (
          <View style={s.actions}>
            {/* [v4 R3a] 세컨더리 → 프라이머리. 옛 근거는 "러너 자기보고라 한 단계 아래"였는데,
                이건 서버 계약 행동이다 — 탭이 arrived_at을 찍고 보호자에게 알림이 정확히 1회 나간다.
                코랄 예산도 깨지 않는다: 스테이지가 배타적이라 enroute 프레임에는 문이 이것 하나뿐이고,
                인계 CTA는 arrived부터 나온다 (화면당 primary 1개 = PaperBtn 호출자의 책임). */}
            <PaperBtn label="픽업 장소 도착 확인 ›" busy={arriveBusy} busyLabel="전송 중..." onPress={reportArrived} />
            {/* [wave 3 · 감사 #29 해소] 도착은 더 이상 로컬 스테이지가 아니다 — bookings.arrived_at이
                정본이고 전송이 실패하면 스테이지는 그대로 남아 재시도 경로가 산다. */}
            {arriveFail
              ? <Text style={s.ctaFail}>{arriveFail}</Text>
              : <Text style={s.ctaHint}>도착을 확인하면 보호자에게 알림이 가요</Text>}
          </View>
        )}
        {!pastCeiling && stage === 'arrived' && (
          <View style={s.actions}>
            {/* 게이트된 CTA — disabled는 명시 fill(disabledFill)로, 불투명도 트릭 금지 */}
            {/* [v4 R3b] 코스 한 줄 — 인계 직전에 '무엇을 뛰기로 했는지'가 CTA 바로 위에 선다.
                routes.name **원문** (routeDisplayName은 만들었다 지운 물건이다, handoff-client §6).
                info가 없으면 줄 자체가 없다 — 모르는 것을 '코스 미지정'으로 단언하지 않는다. */}
            {info && (
              <View style={s.ctaInfo}>
                <InfoRow label="코스">
                  <Text style={s.infoValue} numberOfLines={2}>{info.routeName}</Text>
                </InfoRow>
              </View>
            )}
            {/* 라벨은 코드 원문 그대로 + 화살표만 (RULING 6: 문에는 작은 화살표 + 굵은 글자) */}
            <PaperBtn label={`${dogName} 인계 받았어요 ›`} onPress={handoff} disabled={!allChecked} />
            {/* 도착 성공 힌트는 서버 값(arrived_at) 파생이라 리마운트해도 살아남는다 */}
            <Text style={s.ctaHint}>
              {arrived ? '보호자에게 도착 알림이 갔어요 · ' : ''}
              {allChecked ? '보호자도 확인하면 러닝을 시작할 수 있어요' : '장비 체크를 완료하면 인계할 수 있어요'}
            </Text>
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
            <Text style={s.statusText}>보호자 확인 대기 중...</Text>
            <Text style={s.statusSub}>보호자 앱에 확인 요청을 보냈어요</Text>
          </View>
        )}
        {/* ── 이번 러닝 (v4 R3c) — 인계가 끝난 뒤에만. 네 줄 전부 실필드다:
              목표 = bookings.km + pace_label · 코스 = routes.name **원문**(routeDisplayName은 만들었다
              지운 물건이다, handoff-client §6) · 위치 공유 = run2-<id> private 채널의 사실.
              권장 페이스 = dogs.preferences.paceSuggestSec. clampSuggest는 '확인된 부재'만 기본값으로
              접는 계약이라(pace.ts:32-36) info가 실제로 도착한 뒤에만 부른다 — 실패한 fetch는 info를
              null로 남기고, 그러면 이 블록 자체가 안 그려진다. run.tsx가 러닝 중 쓰는 값과 같은 식이라
              두 화면의 권장 숫자가 갈라지지 않는다. ── */}
        {stage === 'confirmed' && info && (
          <View style={s.section}>
            <Text style={s.cardTitle}>이번 러닝</Text>
            <InfoRow label="목표">
              <Text style={[s.infoNum, nf]}>{info.km}km</Text>
              <Text style={s.infoValue}>· {info.paceLabel}</Text>
            </InfoRow>
            <InfoRow label="권장 페이스">
              <Text style={[s.infoNum, nf]}>{suggestStr(clampSuggest(info.paceSuggestSec))}</Text>
              <Text style={s.infoValue}>안팎</Text>
            </InfoRow>
            <InfoRow label="코스">
              <Text style={s.infoValue} numberOfLines={2}>{info.routeName}</Text>
            </InfoRow>
            <InfoRow label="위치 공유">
              <Text style={s.infoValue} numberOfLines={2}>러닝 중 · 이 예약의 보호자에게만</Text>
            </InfoRow>
          </View>
        )}

        {stage === 'confirmed' && (
          <View style={s.actions}>
            <PaperBtn
              label="러닝 시작하기 ›"
              onPress={async () => {
                if (runnerJob.bookingId) {
                  try { await startRunServer(runnerJob.bookingId); } catch { /* run 화면에서 재시도 */ }
                }
                router.replace('/runner/run');
              }}
            />
            <Text style={s.ctaHint}>인계 완료 · 러닝을 시작하면 GPS 기록이 켜져요</Text>
          </View>
        )}

        {/* [정직 배치 · item 7] 서명된 보험 증권이 없다 — '인계 시점부터 적용' 주장 은퇴, 협의 중 진실로 */}
        <Pressable onPress={() => router.push('/safety')} accessibilityRole="link" accessibilityLabel="안심 센터 열기">
          <Text style={s.foot}>
            양측 확인 없이는 러닝이 시작되지 않아요{'\n'}펫보험 파트너십 협의 중 — 사고 시 안심 센터에서 바로 도와드려요
          </Text>
        </Pressable>
      </ScrollView>
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

// 인계 전 장비 체크 행 — 탭 토글, 완료 시 잉크 틱 (프리플라이트는 잉크, 의식은 골드)
function CheckRow({ icon, label, on, onPress }: { icon: string; label: string; on: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [s.checkRow, on && s.checkRowOn, pressed && { transform: [{ scale: 0.99 }] }]}>
      <Icon name={icon} glyph="●" size={17} color={on ? paper.ink : paper.text} />
      <Text style={[s.checkLabel, on && s.checkLabelOn]}>{label}</Text>
      <View style={[s.checkBox, on && s.checkBoxOn]}>
        {on && <Text style={s.checkTick}>✓</Text>}
      </View>
    </Pressable>
  );
}

// 사실 행 — 라벨 왼쪽 / 값 오른쪽. 값 쪽이 노드를 받는 이유: Oswald는 라틴 전용이라
// 숫자 조각에만 nf를 씌우고 한글 꼬리는 본문 서체로 남겨야 한다 (섞어 씌우면 한글이 폴백으로 튄다).
function InfoRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Row style={s.infoRow}>
      <Text style={s.infoLabel}>{label}</Text>
      <View style={s.infoVal}>{children}</View>
    </Row>
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
  // ── 지도 판 (기능 동일 — 새벽빛 블룸 은퇴, 판이 종이가 된다) ──
  mapPlate: { height: 300, backgroundColor: paper.canvas, overflow: 'hidden', borderBottomWidth: 1, borderBottomColor: paper.line },
  roadA: { position: 'absolute', top: 150, left: -20, right: -20, height: 16, backgroundColor: paper.disabledFill, transform: [{ rotate: '-14deg' }] },
  roadB: { position: 'absolute', top: 0, bottom: 0, left: 130, width: 13, backgroundColor: paper.disabledFill, transform: [{ rotate: '18deg' }] },
  pathDots: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  // [정직 배치 2.5] 경로 점·픽업 핀은 '아는 위치'가 아니라 지면 무늬다 — 주장 강도를 낮춘다
  pathDot: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line, opacity: 0.35 },
  // 핀은 지리 마커라 원형 예외 — 상태색은 남고(위탁 표면 법) 글로우만 떠난다
  mePin: {
    position: 'absolute', left: 28, top: 202, width: 26, height: 26, borderRadius: 13,
    backgroundColor: paper.ink, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: paper.canvas,
  },
  pickupPin: {
    position: 'absolute', left: 292, top: 62, width: 36, height: 26, borderRadius: 13,
    backgroundColor: paper.line, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: paper.canvas,
    opacity: 0.4,
  },
  // 준비 중 오버레이 — request.tsx의 mapPending과 같은 문법(캔버스 면 + 1px 코랄 + dim 14/700)
  mapPendingWrap: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  mapPending: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, maxWidth: 300,
    paddingVertical: 10, paddingHorizontal: 14, alignItems: 'center', justifyContent: 'center',
  },
  mapPendingTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.dim, textAlign: 'center' },
  // 길찾기 overlay chip (DS-2) — circleBtn/chatChip chrome grammar, ≥44pt hit target,
  // anchored inside the plate so it never enters the stage machine's CTA stack
  naviChip: {
    position: 'absolute', right: 12, bottom: 12, backgroundColor: paper.canvas,
    borderWidth: 1, borderColor: paper.line, paddingVertical: 13, paddingHorizontal: 16,
  },
  naviChipTxt: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.ink },
  pinText: { fontSize: 14, lineHeight: 18, fontWeight: '900', color: '#fff' },
  topBar: { position: 'absolute', top: 56, left: 10, right: 10, justifyContent: 'space-between' },
  circleBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  etaPill: {
    flex: 1, marginHorizontal: 8, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    backgroundColor: paper.ink, paddingVertical: 10, paddingHorizontal: 14,
  },
  etaDot: { width: 7, height: 7, borderRadius: 4 },
  etaText: { flexShrink: 1, fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff' },

  // ── 섹션 (풀블리드 — 카드·라운드·섀도·이중 프레임 은퇴, 코랄 1px만이 면을 나눈다) ──
  section: { paddingHorizontal: PAD, paddingVertical: 18, borderBottomWidth: 1, borderBottomColor: paper.line },
  cardTitle: { flexShrink: 1, fontSize: 17, fontWeight: '800', color: paper.ink },
  cardBody: { fontSize: 14, lineHeight: 20, color: paper.text, marginTop: 6 },
  // 주소 로드 실패 = 라우드 페일 (owner/request.tsx dogFailStrip과 같은 문법:
  // criticalWash 면 + 위아래 1px critical + 밑줄 재시도). 새 미학이 아니라 있는 문법의 이식.
  addrFailStrip: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: paper.criticalWash, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: 12, marginTop: 8,
  },
  addrFailTxt: { flex: 1, fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical },
  // [D15c] 새로고침 링크 — 실패가 아니므로 크리티컬 잉크가 아니라 액션 잉크. 14pt 플로어 준수.
  addrRefresh: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.actionInk },
  addrFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  peerName: { fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink },
  peerMeta: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 3 },
  // 예약 정보 로드 실패 — 인계 의식 한복판에 스트립을 놓을 자리가 없어 ctaFail과 같은 처방:
  // 자리는 그대로, 잉크만 critical (강조 예산 면제, line과 값 공유 금지). 문은 ≥44pt.
  peerFail: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical, marginTop: 3 },
  peerFailRetry: { fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  chatChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 9, paddingHorizontal: 11, alignSelf: 'center' },
  chatChipText: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.ink },
  // Handling facts. 14pt holds the detail floor; the wash keeps them quiet next to the memo, which
  // is the sentence that actually changes the next twenty minutes.
  dogTag: { backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line, paddingHorizontal: 8, paddingVertical: 3 },
  dogTagTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.ink },
  dogVax: { fontSize: 14, lineHeight: 18, color: paper.dim, alignSelf: 'center' },

  // ── 이번 러닝 사실 행 (R3c) ──
  infoRow: { justifyContent: 'space-between', gap: 12, marginTop: 10 },
  infoLabel: { fontSize: 14, lineHeight: 19, color: paper.dim },
  infoVal: { flexShrink: 1, flexDirection: 'row', alignItems: 'baseline', gap: 4 },
  infoValue: { fontSize: 14.5, lineHeight: 19, fontWeight: '800', color: paper.ink, textAlign: 'right' },
  // Oswald 숫자 — lineHeight 21 = 1.31× (BUG A: 명시 lineHeight 없으면 어센더가 잘린다)
  infoNum: { fontSize: 16, lineHeight: 21, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const },
  // 행동 존 안의 사실 한 줄 (R3b 코스) — CTA와 붙지 않게 아래로만 띄운다
  ctaInfo: { marginBottom: 12 },

  // ── 의식 헤더 ──
  kick: { fontSize: 12, fontWeight: '700', letterSpacing: 3, color: paper.faint }, // 장식 클래스 (14pt 플로어 면제)
  ttl: { fontSize: 20, fontWeight: '900', color: paper.ink, marginTop: 3 },
  countPill: { alignSelf: 'flex-start', backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 4, paddingHorizontal: 9 },
  countPillOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  countPillGo: { backgroundColor: paper.ink, borderColor: paper.ink },
  countText: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.text },
  countTextOn: { color: '#fff' },
  countTextGo: { color: '#fff' },

  // ── 아티팩트 = 봉인 스텁 (나이트 풀블리드 · 코랄 헤어라인 심 · 가운데 천공) ──
  // 밤 지면 안의 어휘는 그대로 살아남는다: 골드 소인 · SEAL_INK · NIGHT_DIM.
  // [H6] band/slot/slotStage에 overflow 추가 금지 — 립플이 1.85배(133px)로 무대 밖까지 퍼진다.
  band: {
    marginHorizontal: -PAD, marginTop: 16, flexDirection: 'row', alignItems: 'flex-start',
    backgroundColor: NIGHT, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.line,
    paddingVertical: 18, paddingHorizontal: 8,
  },
  perfWrap: { position: 'absolute', left: '50%', marginLeft: -7.5, top: 0, bottom: 0, width: 15 },
  perfLine: { position: 'absolute', top: 0, bottom: 0, left: 6.75, borderLeftWidth: 1.5, borderStyle: 'dashed', borderColor: PERF },
  notch: { position: 'absolute', left: 0, width: 15, height: 15, borderRadius: 7.5, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line },
  slot: { flex: 1, alignItems: 'center', paddingHorizontal: 4 },
  slotStage: { width: 76, height: 76, alignItems: 'center', justifyContent: 'center' },
  slotRipple: { position: 'absolute', width: 72, height: 72, borderRadius: 36, borderWidth: 2, borderColor: GOLD },
  slotBreath: { position: 'absolute', width: 72, height: 72, borderRadius: 36, borderWidth: 2, borderColor: NIGHT_DIM },
  slotEmpty: {
    width: 72, height: 72, borderRadius: 36, borderWidth: 1.5, borderColor: PERF,
    backgroundColor: 'rgba(255,255,255,0.06)', alignItems: 'center', justifyContent: 'center',
  },
  slotSeal: {
    width: 72, height: 72, borderRadius: 36, borderWidth: 2, borderColor: GOLD, backgroundColor: GOLD_SOFT,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: GOLD, shadowOpacity: 0.38, shadowRadius: 9, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  slotMark: { fontSize: 21, lineHeight: 25, fontWeight: '900', color: SEAL_INK },
  // [FLOOR14 예외] 트래킹 라틴 캡스 키커 — 역할 각인. 읽는 정보는 아래 한글 두 줄이 진다.
  slotCaps: { fontSize: 8.5, fontWeight: '800', letterSpacing: 1.6, color: SEAL_INK, marginTop: 1 },
  slotCapsOff: { fontSize: 8.5, fontWeight: '800', letterSpacing: 1.6, color: NIGHT_DIM },
  slotName: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff', marginTop: 10 },
  slotState: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: NIGHT_DIM, marginTop: 2 },
  slotStateOn: { color: GOLD_SHEEN, fontWeight: '800' },
  // SEALED 룰 — 밴드와 한 몸인 의식의 콜로폰이라 골드가 남는다 (크롬에는 골드 금지)
  ribbon: { flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 12, paddingHorizontal: 2 },
  ribbonRule: { flex: 1, height: 1, backgroundColor: GOLD_SHEEN },
  ribbonCaps: { fontSize: 9.5, fontWeight: '800', letterSpacing: 2.6, color: SEAL_INK },

  // ── 스텝 레일 (정직한 순서 — 완료 잉크 / 진행 코랄 링 / 미완 페인트) ──
  steps: { marginTop: 14 },
  stepRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, marginTop: 11 },
  stepCol: { width: 20, alignSelf: 'stretch', alignItems: 'center' },
  rail: { position: 'absolute', left: 9.5, top: 21, bottom: -11, width: 1, backgroundColor: paper.faint },
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

  // ── 프리플라이트 장비 체크 (볼트 은퇴 — 체크 = 잉크 필 + 코랄 워시 행) ──
  gearTitle: { fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink, marginTop: 3 },
  gearSub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 6 },
  checkRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 8,
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 12, paddingHorizontal: 12,
  },
  checkRowOn: { backgroundColor: paper.wash, borderColor: paper.line },
  checkLabel: { flex: 1, fontSize: 14.5, lineHeight: 19, fontWeight: '600', color: paper.text },
  checkLabelOn: { fontWeight: '800', color: paper.ink },
  checkBox: {
    width: 22, height: 22, borderWidth: 1.5, borderColor: paper.faint,
    alignItems: 'center', justifyContent: 'center', backgroundColor: paper.canvas,
  },
  checkBoxOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  checkTick: { fontSize: 12, lineHeight: 15, fontWeight: '900', color: '#fff' },

  // ── 행동 존 (버튼 매트릭스는 PaperBtn이 진다 — 여기는 자리와 힌트만) ──
  actions: { paddingHorizontal: PAD, paddingVertical: 18, borderBottomWidth: 1, borderBottomColor: paper.line },
  ctaHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, textAlign: 'center', marginTop: 10 },
  // 도착 전송 실패 — ctaHint와 같은 자리, 잉크만 critical (행동 존에는 스트립을 놓을 자리가 없다)
  ctaFail: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical, textAlign: 'center', marginTop: 10 },
  status: {
    backgroundColor: paper.canvas, borderBottomWidth: 1, borderBottomColor: paper.line,
    paddingVertical: 18, paddingHorizontal: PAD, alignItems: 'center',
  },
  statusKick: { fontSize: 12, fontWeight: '700', letterSpacing: 3, color: paper.faint },
  statusText: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink, marginTop: 7, textAlign: 'center' },
  statusSub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 4, textAlign: 'center' },
  // 헤일로가 1.9배(15.2px)로 퍼져도 무대(16) 안에 든다 — 안드로이드 클리핑 회피
  pulseStage: { width: 16, height: 16, alignItems: 'center', justifyContent: 'center', overflow: 'visible' },
  pulseHalo: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line },
  pulseCore: { width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line },
  foot: { fontSize: 14, lineHeight: 19, color: paper.dim, textAlign: 'center', marginTop: 16, paddingHorizontal: PAD },
});
