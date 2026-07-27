import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import {
  cancelBooking, fetchAvailableRunners, fetchBookingBrief, LiveRunner, subscribeBooking,
} from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 지금 러너 찾기 → 오픈 브로드캐스트 대기 화면 (라이트 + 코랄 웨이브).
// 결과는 이 화면에 뜬다: 수락한 러너가 매치 카드로 나타나고 일정으로 이동.
// 정직 원칙: 가짜 진행률/가짜 지도 점 없음 — 실가용 러너 목록, 경과 시간, 실상태만.

const FOREST = '#132117';
const CORAL = colors.tang; // #FF6347 — 워터 리플

const fmtElapsed = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;

// 코랄 물결 — 잔잔한 리플이 퍼져나간다 (소나가 아니라 산책로 물웅덩이 느낌)
function Ripple({ delay }: { delay: number }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(v, { toValue: 1, duration: 3200, delay, easing: Easing.out(Easing.cubic), useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [v, delay]);
  return (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', width: 130, height: 130, borderRadius: 65,
        borderWidth: 2, borderColor: CORAL,
        opacity: v.interpolate({ inputRange: [0, 0.6, 1], outputRange: [0.4, 0.14, 0] }),
        transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 2.5] }) }],
      }}
    />
  );
}

export default function Radar() {
  const bookingId = draft.bookingId;
  const [elapsed, setElapsed] = useState(0);
  const [avail, setAvail] = useState<LiveRunner[] | null>(null);
  const [matchedName, setMatchedName] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const matchedRef = useRef(false);

  // 강아지 둥실둥실 — 기다림이 덜 지루하게
  const bob = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(bob, { toValue: 1, duration: 1300, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      Animated.timing(bob, { toValue: 0, duration: 1300, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [bob]);

  // 부킹 없이 진입하면 홈으로 (딥링크/백스택 잔재 방어)
  useEffect(() => {
    if (!bookingId) router.replace('/owner/home');
  }, [bookingId]);

  useEffect(() => {
    const t = setInterval(() => setElapsed((e) => e + 1), 1000);
    return () => clearInterval(t);
  }, []);

  // 가용 러너 = 요청을 실제로 받을 수 있는 사람들 (러닝 중 제외, 0015 뷰) — 30초마다 갱신
  useEffect(() => {
    const load = () => fetchAvailableRunners().then(setAvail).catch(() => {});
    load();
    const t = setInterval(load, 30_000);
    return () => clearInterval(t);
  }, []);

  // 수락 감지 — realtime 구독 + 10초 폴링 (벨트+서스펜더)
  useEffect(() => {
    if (!bookingId) return;
    const check = async () => {
      if (matchedRef.current) return;
      try {
        const b = await fetchBookingBrief(bookingId);
        if (['confirmed', 'runner_enroute', 'picked_up', 'active'].includes(b.status)) {
          matchedRef.current = true;
          haptic('success');
          setMatchedName(b.runnerName ?? '러너');
          setTimeout(() => router.replace('/owner/schedule'), 1800);
        } else if (b.status.startsWith('cancelled')) {
          matchedRef.current = true;
          router.replace('/owner/home');
        }
      } catch {} // 일시 네트워크 오류 — 다음 틱에 재시도
    };
    check();
    const unsub = subscribeBooking(bookingId, check);
    const poll = setInterval(check, 10_000);
    return () => { unsub(); clearInterval(poll); };
  }, [bookingId]);

  const cancel = () => {
    if (!bookingId) return;
    Alert.alert('요청 취소', '러너 찾기를 취소할까요?', [
      { text: '계속 찾기', style: 'cancel' },
      {
        text: '취소하기', style: 'destructive',
        onPress: async () => {
          setCancelling(true);
          try {
            const r = await cancelBooking(bookingId);
            draft.bookingId = null;
            Alert.alert('취소 완료', r.cancel_fee > 0
              ? `취소 수수료 ${r.cancel_fee.toLocaleString()}원 · 환불 ${r.refund.toLocaleString()}원`
              : `전액 ${r.refund.toLocaleString()}원 환불돼요`);
            router.replace('/owner/home');
          } catch (e) {
            Alert.alert('취소 실패', (e as Error).message);
          } finally {
            setCancelling(false);
          }
        },
      },
    ]);
  };

  const stale = elapsed >= 600; // 10분 무응답 — 정직하게 대안 제시

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <View style={{ paddingTop: 64, paddingHorizontal: 12 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.replace('/owner/home')} style={s.backBtn}>
            <Text style={{ fontSize: 18, color: FOREST }}>‹</Text>
          </Pressable>
          <View style={s.livePill}>
            <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: CORAL }} />
            <Text style={{ fontSize: 11, fontWeight: '900', color: CORAL }}>주변 러너에게 요청 중</Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView contentContainerStyle={{ paddingHorizontal: 12, paddingBottom: 150 }}>
        {/* ---------- 리플 코어 ---------- */}
        <View style={{ alignItems: 'center', justifyContent: 'center', marginTop: 44, height: 210 }}>
          {!matchedName && (
            <>
              <Ripple delay={0} />
              <Ripple delay={1050} />
              <Ripple delay={2100} />
            </>
          )}
          <Animated.View
            style={[
              s.core,
              matchedName != null && { borderColor: colors.voltDeep, borderWidth: 2.5 },
              { transform: [{ translateY: bob.interpolate({ inputRange: [0, 1], outputRange: [0, -6] }) }] },
            ]}
          >
            <Text style={{ fontSize: 42 }}>{matchedName ? '🎉' : '🐕'}</Text>
          </Animated.View>
        </View>

        {matchedName ? (
          <View style={{ alignItems: 'center', marginTop: 18 }}>
            <Text style={{ fontSize: 22, fontWeight: '900', color: colors.voltDeep }}>{matchedName} 러너가 수락했어요!</Text>
            <Text style={{ fontSize: 13, color: '#5d655d', marginTop: 8 }}>일정 화면으로 이동할게요</Text>
          </View>
        ) : (
          <>
            <View style={{ alignItems: 'center', marginTop: 14 }}>
              <Text style={{ fontSize: 22, fontWeight: '900', color: FOREST }}>러너를 찾고 있어요</Text>
              <Text style={{ fontSize: 13.5, color: '#5d655d', marginTop: 7 }}>
                경과 {fmtElapsed(elapsed)} · 수락한 러너가 이 화면에 바로 나타나요
              </Text>
            </View>

            {/* ---------- 요청을 받은 러너들 — 실가용 (러닝 중 제외) ---------- */}
            <View style={{ marginTop: 26 }}>
              <Row style={{ justifyContent: 'space-between', marginBottom: 10 }}>
                <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>요청을 받은 러너</Text>
                <Text style={{ fontSize: 11.5, color: '#5d655d' }}>
                  {avail == null ? '확인 중…' : `${avail.length}명 가능`}
                </Text>
              </Row>
              {avail != null && avail.length === 0 && (
                <View style={s.emptyBox}>
                  <Text style={{ fontSize: 12.5, color: '#5d655d', textAlign: 'center', lineHeight: 19 }}>
                    지금 바로 가능한 러너가 없어요{'\n'}요청은 살아있어요 — 러너가 온라인되면 바로 보여요
                  </Text>
                </View>
              )}
              {(avail ?? []).map((r) => (
                <Pressable key={r.profileId} onPress={() => router.push(`/runner-profile/${r.profileId}`)} style={s.runnerRow}>
                  <Avatar url={r.avatarUrl} char={r.name[0]} bg="#5a7a3c" size={42} />
                  <View style={{ flex: 1, marginLeft: 11 }}>
                    <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>{r.name}</Text>
                    <Text style={{ fontSize: 11, color: '#5d655d', marginTop: 2 }}>
                      {r.tier} · {r.district || '근처'} · 러닝 {r.totalRuns}회
                    </Text>
                  </View>
                  <View style={s.pacePill}>
                    <Text style={{ fontSize: 11, fontWeight: '900', color: '#3f5a26' }}>{r.paceLabel}</Text>
                  </View>
                </Pressable>
              ))}
            </View>

            {stale && (
              <View style={s.staleBox}>
                <Text style={{ fontSize: 12.5, color: '#a97c12', textAlign: 'center', lineHeight: 19 }}>
                  아직 응답이 없어요 — 마음에 드는 러너를 직접 지명하면{'\n'}응답 확률이 올라가요
                </Text>
              </View>
            )}
          </>
        )}
      </ScrollView>

      {!matchedName && (
        <View style={s.footer}>
          <Pressable onPress={() => router.push('/owner/matching')} style={s.pickBtn}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>직접 고를래요 — 러너 카드 보기</Text>
          </Pressable>
          <Pressable onPress={cancel} disabled={cancelling} style={s.cancelBtn}>
            <Text style={{ fontSize: 13, fontWeight: '800', color: '#8a917f' }}>
              {cancelling ? '취소 중...' : '요청 취소'}
            </Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#d9d5c6',
  },
  livePill: {
    flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#fdece7',
    borderRadius: 99, paddingVertical: 7, paddingHorizontal: 14, borderWidth: 1, borderColor: '#f8cfc2',
  },
  core: {
    width: 130, height: 130, borderRadius: 65, backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: '#f8cfc2',
    shadowColor: CORAL, shadowOpacity: 0.2, shadowRadius: 10, shadowOffset: { width: 0, height: 4 },
  },
  runnerRow: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff', borderRadius: 16,
    padding: 12, marginBottom: 8, borderWidth: 1, borderColor: '#dedacb',
  },
  pacePill: { backgroundColor: '#eaf7c8', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10 },
  emptyBox: {
    backgroundColor: '#fff', borderRadius: 16, padding: 18, borderWidth: 1, borderColor: '#dedacb',
  },
  staleBox: {
    marginTop: 16, backgroundColor: '#fbf0d4', borderRadius: 14, padding: 14,
    borderWidth: 1, borderColor: '#ecd9a0',
  },
  footer: {
    position: 'absolute', left: 12, right: 12, bottom: 42, gap: 8,
  },
  pickBtn: {
    backgroundColor: FOREST, borderRadius: 16, alignItems: 'center', paddingVertical: 16,
    shadowColor: FOREST, shadowOpacity: 0.25, shadowRadius: 7, shadowOffset: { width: 0, height: 6 },
  },
  cancelBtn: { alignItems: 'center', paddingVertical: 9 },
});
