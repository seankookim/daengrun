import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Avatar, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingSync, fetchCurrentRunnerJobId, fetchMeetupInfo, MeetupInfo, runnerEnroute, startRunServer, subscribeBooking } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { paper } from '../../src/theme';

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

type Stage = 'enroute' | 'arrived' | 'waiting' | 'confirmed';

// [정직 배치 2026-08-06 · item 4 wave-1] 하드코딩 픽업 좌표·주소와 네이버 길찾기 숏컷 은퇴 —
// 파일럿 동네와 무관한 성동구 좌표였고, bookings.address_id를 읽는 코드는 어디에도 없었다.
// 실주소는 wave 3(러너용 definer RPC) 몫. 그때까지의 정직한 상태는 '모름'이지 '지어낸 주소'가 아니다.

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
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const dogName = info?.dogName ?? '반려견';
  const [stage, setStage] = useState<Stage>('enroute');
  const [jobId, setJobId] = useState<string | null>(runnerJob.bookingId ?? null);
  const [peerConfirmed, setPeerConfirmed] = useState(false); // 보호자 측 인계 확인 (서버 진실)
  const [synced, setSynced] = useState(false); // 첫 서버 동기화 도착 (스탬프 하이드레이션 판정용)
  // 인계 전 장비 체크리스트 (0019 연계) — 세 가지 모두 체크해야 인계 버튼이 열린다.
  // 로컬 상태로 충분: 서버 계약은 양측 confirm이고, 이 체크는 러너 자신을 위한 프리플라이트.
  const [check, setCheck] = useState({ leash: false, water: false, treats: false });
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
  useEffect(() => {
    if (!jobId) return;
    fetchMeetupInfo(jobId).then(setInfo).catch((e) => console.warn('[r-meetup] info:', e?.message ?? e));
  }, [jobId]);

  const syncNow = useCallback(async () => {
    if (!jobId) return;
    try {
      const s2 = await fetchBookingSync(jobId);
      // 종말 상태 — 취소/만료된 예약의 미트업에 좌초 금지 (감사 ③)
      if (s2.status === 'completed' || s2.status.startsWith('cancelled') || s2.status === 'expired' || s2.status === 'matching') {
        Alert.alert('예약 상태가 바뀌었어요', s2.status === 'completed' ? '이미 완료된 러닝이에요' : '이 예약은 더 진행할 수 없어요');
        router.back();
        return;
      }
      setPeerConfirmed(s2.ownerConfirmed);
      setSynced(true); // [P2-12] 봉인 진실이 처음 도착한 지점 — 이 커밋 이후부터가 '라이브'
      if (s2.status === 'picked_up' || s2.status === 'active') setStage('confirmed');
      else if (s2.runnerConfirmed) setStage('waiting');
    } catch { /* 다음 이벤트/폴백이 처리 */ }
  }, [jobId]);

  // 서버에 '이동 중' 보고 + 실시간 구독 (8초 폴링은 폴백)
  useEffect(() => {
    if (!jobId) return;
    runnerEnroute(jobId).catch(() => { /* 이미 지난 상태면 무시 */ });
    syncNow();
    const unsub = subscribeBooking(jobId, syncNow);
    poll.current = setInterval(syncNow, 8000);
    return () => { if (poll.current) clearInterval(poll.current); unsub(); };
  }, [jobId, syncNow]);

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

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* map to pickup (placeholder) */}
      <View style={s.mapPlate}>
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

        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            {/* 상태 도트 = 시맨틱 (이동 앰버 → 도착 코랄). 강조 예산 면제, line과 값 공유 금지 */}
            <View style={[s.etaDot, { backgroundColor: stage === 'enroute' ? paper.pending : paper.line }]} />
            {/* [P2-11] GPS 없는 도보 8분·0.8km는 조작이었다 — 스테이지에 묶인 사실만 말한다 */}
            <Text style={s.etaText} numberOfLines={2}>
              {stage === 'enroute' ? '픽업 장소로 이동 중' : '픽업 장소 도착'}
            </Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 34 }}>
        {/* pickup info */}
        <View style={s.section}>
          <Text style={s.cardTitle} numberOfLines={1}>픽업 장소</Text>
          <Text style={s.cardBody}>
            픽업 장소는 보호자와 채팅으로 확인해주세요{'\n'}
            {info?.dogMemo ? `보호자 메모: ${info.dogMemo}` : '보호자 메모가 없어요 — 채팅으로 미리 인사해보세요'}
          </Text>
        </View>

        {/* dog + owner */}
        <View style={s.section}>
          <Row style={{ gap: 12 }}>
            <Avatar url={info?.dogPhotoUrl} char={dogName[0]} bg={paper.ink} size={44} />
            <View style={{ flex: 1 }}>
              <Text style={s.peerName} numberOfLines={2}>
                {dogName}{info?.dogBreed ? ` · ${info.dogBreed}` : ''}{info?.dogWeightKg != null ? ` ${info.dogWeightKg}kg` : ''}
              </Text>
              <Text style={s.peerMeta} numberOfLines={2}>
                {info ? `${info.when} · ${info.km}km · ${info.paceLabel}` : '예약 정보 불러오는 중...'}
              </Text>
            </View>
            <Pressable style={s.chatChip} onPress={() => router.push({ pathname: '/chat', params: jobId ? { bid: jobId } : {} })}>
              <Text style={s.chatChipText}>보호자 채팅</Text>
            </Pressable>
          </Row>
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
        {stage === 'arrived' && (
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
            <CheckRow glyph="🦮" label="러닝 리드줄로 교체했어요" on={check.leash} onPress={() => { haptic('light'); setCheck((c) => ({ ...c, leash: !c.leash })); }} />
            <CheckRow glyph="💧" label={`${dogName} 급수 준비 완료`} on={check.water} onPress={() => { haptic('light'); setCheck((c) => ({ ...c, water: !c.water })); }} />
            <CheckRow glyph="🦴" label="간식 파우치 챙겼어요" on={check.treats} onPress={() => { haptic('light'); setCheck((c) => ({ ...c, treats: !c.treats })); }} />
          </View>
        )}

        {/* action */}
        {stage === 'enroute' && (
          <View style={s.actions}>
            {/* 도착 확인은 화면의 계약 행동이 아니라 러너 자기보고 — 세컨더리로 정직하게 강등 */}
            <PaperBtn label="픽업 장소 도착 확인" variant="secondary" onPress={() => setStage('arrived')} />
            <Text style={s.ctaHint}>보호자에게 도착 알림이 전송돼요</Text>
          </View>
        )}
        {stage === 'arrived' && (
          <View style={s.actions}>
            {/* 게이트된 CTA — disabled는 명시 fill(disabledFill)로, 불투명도 트릭 금지 */}
            <PaperBtn label={`${dogName} 인계 받았어요`} onPress={handoff} disabled={!allChecked} />
            <Text style={s.ctaHint}>
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
            <Text style={s.ctaHint}>인계 완료 · GPS와 바디캠이 켜져요</Text>
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
function CheckRow({ glyph, label, on, onPress }: { glyph: string; label: string; on: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [s.checkRow, on && s.checkRowOn, pressed && { transform: [{ scale: 0.99 }] }]}>
      <Text style={{ fontSize: 18, lineHeight: 22 }}>{glyph}</Text>
      <Text style={[s.checkLabel, on && s.checkLabelOn]}>{label}</Text>
      <View style={[s.checkBox, on && s.checkBoxOn]}>
        {on && <Text style={s.checkTick}>✓</Text>}
      </View>
    </Pressable>
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
  pathDot: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: paper.line },
  // 핀은 지리 마커라 원형 예외 — 상태색은 남고(위탁 표면 법) 글로우만 떠난다
  mePin: {
    position: 'absolute', left: 28, top: 202, width: 26, height: 26, borderRadius: 13,
    backgroundColor: paper.ink, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: paper.canvas,
  },
  pickupPin: {
    position: 'absolute', left: 292, top: 62, width: 36, height: 26, borderRadius: 13,
    backgroundColor: paper.line, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: paper.canvas,
  },
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
  peerName: { fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink },
  peerMeta: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 3 },
  chatChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 9, paddingHorizontal: 11, alignSelf: 'center' },
  chatChipText: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.ink },

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
