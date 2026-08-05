import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import Svg, { Defs, LinearGradient as SvgLinear, RadialGradient, Rect, Stop } from 'react-native-svg';
import { Monogram, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingSync, fetchCurrentOwnerBookingId, fetchMeetupInfo, MeetupInfo, subscribeBooking } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { haptic } from '../../src/lib/haptics';
import { draft } from '../../src/store';
import { lilac, lilacRadius, lilacShadow } from '../../src/theme';

// 보호자 인계 화면 — 실신원만 (김민준·초코 목업 은퇴, ui-audit P0).
// 모든 이름·상태는 서버에서. 가짜 ETA 문구 없음.
//
// [2026-08-05 라일락 리페인트 + 의식 격상] 포레스트/스웜프 전량 은퇴 → 테일러드 라일락.
// 모티프 = 이중 봉인(二重封印): 양측 확인이 각각 하나의 도장 자리를 채운다. 자리는 서버 진실
// (stage / peerConfirmed)로만 채워진다 — 가짜 진행 없음. 둘 다 채워지면 골드 SEALED 룰이 내려온다.
// 로직 동결: 스테이지 머신·구독/폴링·confirmHandoff·라우팅·게이트 전부 원본 그대로.

const L = lilac;
const NIGHT = '#1C1837';    // 나이트 라일락 다크 인셋 (owner/home·clubcard와 동일 토큰 — 포레스트 은퇴)
const NIGHT_DIM = '#C6BEEB';
const SEAL_INK = '#8a6f2a'; // 소인 잉크 — 클럽 영수증 골드 실과 같은 잉크
const STUB = '#FBFAFE';     // 스텁 지면 (보딩패스 그래머)
const PERF = '#D8D2EE';     // 천공 점선

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

// 새벽빛 지도 하늘 — 코랄·바이올렛 블룸 (DawnCanvas와 같은 법, 지도 판 위에만)
function MapSky() {
  return (
    <Svg width="100%" height="100%" style={StyleSheet.absoluteFill} pointerEvents="none">
      <Defs>
        <RadialGradient id="om-sky-c" cx="86%" cy="4%" rx="74%" ry="72%">
          <Stop offset="0" stopColor="#F0765A" stopOpacity="0.17" />
          <Stop offset="1" stopColor="#F0765A" stopOpacity="0" />
        </RadialGradient>
        <RadialGradient id="om-sky-v" cx="2%" cy="92%" rx="70%" ry="64%">
          <Stop offset="0" stopColor="#6C5CE7" stopOpacity="0.15" />
          <Stop offset="1" stopColor="#6C5CE7" stopOpacity="0" />
        </RadialGradient>
      </Defs>
      <Rect x="0" y="0" width="100%" height="100%" fill="url(#om-sky-c)" />
      <Rect x="0" y="0" width="100%" height="100%" fill="url(#om-sky-v)" />
    </Svg>
  );
}

// 지평선 페이드 — 지도 판이 종이(카드 지면)로 내려앉는다
function MapHorizon() {
  return (
    <Svg width="100%" height={64} style={s.mapFade} pointerEvents="none">
      <Defs>
        <SvgLinear id="om-fade" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#F4F2FB" stopOpacity="0" />
          <Stop offset="1" stopColor="#F4F2FB" stopOpacity="0.96" />
        </SvgLinear>
      </Defs>
      <Rect x="0" y="0" width="100%" height="64" fill="url(#om-fade)" />
    </Svg>
  );
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
      .catch((e) => console.warn('[o-meetup] resolve:', e?.message ?? e));
  }, [bookingId]);

  // 실컨텍스트 로드 — 러너·강아지·코스 실명
  useEffect(() => {
    if (!bookingId) return;
    fetchMeetupInfo(bookingId).then(setInfo).catch((e) => console.warn('[o-meetup] info:', e?.message ?? e));
  }, [bookingId]);

  // 모든 단계가 서버 진실을 따른다 — 가짜 도착 없음
  const refresh = useCallback(async () => {
    if (!bookingId) return;
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

  // [P2-12] 반드시 마지막 effect — 같은 커밋에서 useStamp·celebrate effect가 먼저 실행된 뒤에
  // 게이트가 열린다. 첫 동기화가 이미 봉인 상태였다면 그 커밋은 점프, 그 다음 봉인부터 애니메이션.
  useEffect(() => { if (synced) hydrated.current = true; }, [synced]);

  return (
    <View style={{ flex: 1, backgroundColor: L.bg }}>
      {/* map: runner approaching pickup */}
      <View style={s.mapPlate}>
        <MapSky />
        <View style={s.roadA} />
        <View style={s.roadB} />
        {[0, 1, 2, 3, 4].map((i) => (
          <View key={i} style={[s.pathDot, { right: 60 + i * 42, top: 80 + i * 26, opacity: stage === 'enroute' ? 1 : 0.3 }]} />
        ))}
        <View style={[s.runnerPin, stage !== 'enroute' && { right: 260, top: 196 }]}>
          <Text style={s.pinText}>{runnerName[0]}</Text>
        </View>
        <View style={s.pickupPin}><Text style={s.pinText}>픽업</Text></View>
        <MapHorizon />

        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5, color: L.head }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            <View style={[s.etaDot, { backgroundColor: stage === 'enroute' ? L.amber : L.coral }]} />
            <Text style={s.etaText} numberOfLines={2}>
              {stage === 'enroute' ? `${runnerName} 러너 매칭됨 — 출발 대기` : `${runnerName} 러너 이동 중`}
            </Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 12, paddingBottom: 34 }}>
        {/* runner card — 낯선 사람이 내 개를 데려간다: 신원이 먼저다 */}
        <View style={s.card}>
          <View pointerEvents="none" style={s.dbl} />
          <Row style={{ gap: 12 }}>
            <Monogram char={runnerName[0]} bg={L.accent} size={46} />
            <View style={{ flex: 1 }}>
              <Row style={{ gap: 6 }}>
                {/* [320dp] 이름 컬럼 ~144px — 긴 이름은 잘리지 않고 두 줄로 접힌다 (신뢰 화면에서 말줄임 금지) */}
                <Text style={s.peerName} numberOfLines={2}>{runnerName} 러너</Text>
                <View style={s.badgePill}><Text style={s.badgeText}>신원인증</Text></View>
              </Row>
              <Text style={s.peerMeta} numberOfLines={2}>
                {info ? `${info.when} · ${info.routeName} ${info.km}km` : '예약 정보 불러오는 중...'}
              </Text>
            </View>
            <Pressable style={s.chatChip} onPress={() => router.push({ pathname: '/chat', params: bookingId ? { bid: bookingId } : {} })}>
              <Text style={s.chatChipText}>채팅</Text>
            </Pressable>
          </Row>
        </View>

        {/* handoff ceremony — 이중 봉인 + 정직한 순서 */}
        <View style={s.card}>
          <View pointerEvents="none" style={s.dbl} />
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
            <Step done={stage !== 'enroute'} active={stage === 'enroute'} label={stage === 'enroute' ? '러너 이동 중 — 실시간 위치가 위 지도에 보여요' : '러너 픽업 장소 도착'} />
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
              <View style={s.pulseStage}><View style={[s.pulseCore, { backgroundColor: L.amber }]} /></View>
              <Text style={s.statusKick}>EN ROUTE</Text>
            </Row>
            <Text style={s.statusText}>러너 도착을 기다리는 중...</Text>
            <Text style={s.statusSub}>도착하면 알림을 보내드려요</Text>
          </View>
        )}
        {stage === 'arrived' && (
          <Pressable style={({ pressed }) => [s.cta, pressed && { transform: [{ scale: 0.985 }] }]} onPress={handoff}>
            <Text style={s.ctaText}>{dogName}를 인계했어요</Text>
            <Text style={s.ctaSub}>러너도 확인하면 러닝이 시작돼요</Text>
          </Pressable>
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

        <Text style={s.foot}>
          인계 시점부터 펫보험이 적용됩니다{'\n'}러너가 10분 내 도착하지 않으면 자동으로 고객센터가 연결돼요
        </Text>
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

const s = StyleSheet.create({
  // ── 지도 판 (기능 동일 — 표면만 라일락) ──
  mapPlate: { height: 290, backgroundColor: L.inset, overflow: 'hidden' },
  roadA: { position: 'absolute', top: 140, left: -20, right: -20, height: 16, backgroundColor: 'rgba(255,255,255,0.92)', transform: [{ rotate: '10deg' }] },
  roadB: { position: 'absolute', top: 0, bottom: 0, left: 200, width: 13, backgroundColor: 'rgba(255,255,255,0.7)', transform: [{ rotate: '-14deg' }] },
  pathDot: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: L.accent },
  runnerPin: {
    position: 'absolute', right: 34, top: 56, width: 26, height: 26, borderRadius: 13,
    backgroundColor: L.coral, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#fff',
    shadowColor: L.coral, shadowOpacity: 0.5, shadowRadius: 8, shadowOffset: { width: 0, height: 2 }, elevation: 3,
  },
  pickupPin: {
    position: 'absolute', left: 60, top: 200, width: 36, height: 26, borderRadius: 13,
    backgroundColor: NIGHT, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#fff',
  },
  pinText: { fontSize: 14, lineHeight: 18, fontWeight: '900', color: '#fff' },
  mapFade: { position: 'absolute', left: 0, right: 0, bottom: 0 },
  topBar: { position: 'absolute', top: 56, left: 10, right: 10, justifyContent: 'space-between' },
  circleBtn: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: L.card, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: L.hair, ...lilacShadow, shadowOpacity: 0.1,
  },
  etaPill: {
    flex: 1, marginHorizontal: 8, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    backgroundColor: NIGHT, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 14,
    shadowColor: NIGHT, shadowOpacity: 0.28, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 4,
  },
  etaDot: { width: 7, height: 7, borderRadius: 4 },
  etaText: { flexShrink: 1, fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff' },

  // ── 카드 (헤어라인 법 · 히어로 이중 프레임) ──
  card: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 13, marginBottom: 10, ...lilacShadow,
  },
  dbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: L.hair2, borderRadius: lilacRadius.inner },
  peerName: { flexShrink: 1, fontSize: 17, lineHeight: 23, fontWeight: '800', color: L.head },
  badgePill: { backgroundColor: '#F4F1FE', borderWidth: 1, borderColor: '#DCD6F8', borderRadius: lilacRadius.tag, paddingVertical: 2, paddingHorizontal: 7 },
  badgeText: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: L.accent },
  peerMeta: { fontSize: 14, lineHeight: 19, color: L.dim, marginTop: 3 },
  chatChip: { backgroundColor: L.inset, borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.tag, paddingVertical: 9, paddingHorizontal: 12, alignSelf: 'center' },
  chatChipText: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: L.accent },

  // ── 의식 헤더 ──
  kick: { fontSize: 10.5, fontWeight: '800', letterSpacing: 2.4, color: L.accent },
  ttl: { fontSize: 20, fontWeight: '900', color: L.head, marginTop: 3 },
  countPill: { alignSelf: 'flex-start', backgroundColor: L.inset, borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9 },
  countPillOn: { backgroundColor: L.goldSoft, borderColor: L.goldSheen },
  countText: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: L.dim },
  countTextOn: { color: SEAL_INK },

  // ── 봉인 스텁 (풀블리드 밴드 · 가운데 천공) ──
  band: {
    marginHorizontal: -9, marginTop: 13, flexDirection: 'row', alignItems: 'flex-start',
    backgroundColor: STUB, borderTopWidth: 1, borderBottomWidth: 1, borderColor: L.hair,
    paddingVertical: 16, paddingHorizontal: 8,
  },
  perfWrap: { position: 'absolute', left: '50%', marginLeft: -7.5, top: 0, bottom: 0, width: 15 },
  perfLine: { position: 'absolute', top: 0, bottom: 0, left: 6.75, borderLeftWidth: 1.5, borderStyle: 'dashed', borderColor: PERF },
  notch: { position: 'absolute', left: 0, width: 15, height: 15, borderRadius: 7.5, backgroundColor: L.bg, borderWidth: 1, borderColor: L.hair },
  slot: { flex: 1, alignItems: 'center', paddingHorizontal: 4 },
  slotStage: { width: 76, height: 76, alignItems: 'center', justifyContent: 'center' },
  slotRipple: { position: 'absolute', width: 72, height: 72, borderRadius: 36, borderWidth: 2, borderColor: L.gold },
  slotBreath: { position: 'absolute', width: 72, height: 72, borderRadius: 36, borderWidth: 2, borderColor: L.accent },
  slotEmpty: {
    width: 72, height: 72, borderRadius: 36, borderWidth: 1.5, borderColor: PERF,
    backgroundColor: L.inset, alignItems: 'center', justifyContent: 'center',
  },
  slotSeal: {
    width: 72, height: 72, borderRadius: 36, borderWidth: 2, borderColor: L.gold, backgroundColor: L.goldSoft,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: L.gold, shadowOpacity: 0.38, shadowRadius: 9, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  slotMark: { fontSize: 21, lineHeight: 25, fontWeight: '900', color: SEAL_INK },
  // [FLOOR14 예외] 트래킹 라틴 캡스 키커 — 역할 각인. 읽는 정보는 아래 한글 두 줄이 진다.
  slotCaps: { fontSize: 8.5, fontWeight: '800', letterSpacing: 1.6, color: SEAL_INK, marginTop: 1 },
  slotCapsOff: { fontSize: 8.5, fontWeight: '800', letterSpacing: 1.6, color: L.dim },
  slotName: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: L.head, marginTop: 10 },
  slotState: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: L.dim, marginTop: 2 },
  slotStateOn: { color: L.voltDeep, fontWeight: '800' },
  ribbon: { flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 12, paddingHorizontal: 2 },
  ribbonRule: { flex: 1, height: 1, backgroundColor: L.goldSheen },
  ribbonCaps: { fontSize: 9.5, fontWeight: '800', letterSpacing: 2.6, color: SEAL_INK },

  // ── 스텝 레일 (정직한 순서) ──
  steps: { marginTop: 14 },
  stepRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, marginTop: 11 },
  stepCol: { width: 20, alignSelf: 'stretch', alignItems: 'center' },
  rail: { position: 'absolute', left: 9, top: 21, bottom: -11, width: 2, backgroundColor: L.hair },
  railOn: { backgroundColor: L.accent },
  stepDot: {
    width: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center',
    backgroundColor: L.inset, borderWidth: 1, borderColor: L.hair,
  },
  stepDotDone: { backgroundColor: L.accent, borderColor: L.accent },
  stepDotActive: { backgroundColor: L.card, borderWidth: 2, borderColor: L.amber },
  stepCore: { width: 7, height: 7, borderRadius: 4, backgroundColor: L.amber },
  stepTick: { fontSize: 11, lineHeight: 14, fontWeight: '900', color: '#fff' },
  stepLabel: { flex: 1, fontSize: 14.5, lineHeight: 20, fontWeight: '500', color: L.dim },
  stepLabelDone: { color: L.head, fontWeight: '700' },
  stepLabelActive: { color: L.amber, fontWeight: '700' },

  // ── 행동 존 (여백 화면 = 큰 버튼) ──
  cta: {
    backgroundColor: L.coral, borderRadius: lilacRadius.btn, alignItems: 'center',
    paddingVertical: 20, paddingHorizontal: 14, marginTop: 4,
    shadowColor: L.coral, shadowOpacity: 0.4, shadowRadius: 16, shadowOffset: { width: 0, height: 8 }, elevation: 5,
  },
  ctaText: { fontSize: 19, lineHeight: 25, fontWeight: '900', color: '#fff', textAlign: 'center' },
  ctaSub: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: 'rgba(255,255,255,0.88)', marginTop: 4, textAlign: 'center' },
  status: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    paddingVertical: 18, paddingHorizontal: 14, marginTop: 4, alignItems: 'center',
    ...lilacShadow, shadowOpacity: 0.06,
  },
  statusKick: { fontSize: 10, fontWeight: '800', letterSpacing: 2.2, color: L.dim },
  statusText: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: L.head, marginTop: 7, textAlign: 'center' },
  statusSub: { fontSize: 14, lineHeight: 19, color: L.dim, marginTop: 4, textAlign: 'center' },
  // 헤일로가 1.9배(15.2px)로 퍼져도 무대(16) 안에 든다 — 안드로이드 클리핑 회피
  pulseStage: { width: 16, height: 16, alignItems: 'center', justifyContent: 'center', overflow: 'visible' },
  pulseHalo: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: L.coral },
  pulseCore: { width: 8, height: 8, borderRadius: 4, backgroundColor: L.coral },
  night: {
    backgroundColor: NIGHT, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)',
    paddingVertical: 20, paddingHorizontal: 16, marginTop: 4, alignItems: 'center',
    shadowColor: NIGHT, shadowOpacity: 0.32, shadowRadius: 24, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  nightKick: { fontSize: 10, fontWeight: '800', letterSpacing: 2.6, color: L.goldSheen },
  nightText: { fontSize: 18, lineHeight: 24, fontWeight: '900', color: '#fff', marginTop: 7, textAlign: 'center' },
  nightSub: { fontSize: 14, lineHeight: 19, color: NIGHT_DIM, marginTop: 5, textAlign: 'center' },
  foot: { fontSize: 14, lineHeight: 19, color: L.dim, textAlign: 'center', marginTop: 16 },
});
