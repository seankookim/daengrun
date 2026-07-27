import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import {
  cancelBooking, fetchBookingBrief, fetchCertifiedRunners, LiveRunner, subscribeBooking,
} from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 지금 러너 찾기 → 오픈 브로드캐스트 대기 화면 (레이더).
// 온라인 러너 전원에게 뿌려진 요청을 누가 수락하면 실시간으로 잡아채 확정 화면으로.
// 정직 원칙: 가짜 진행률 없음 — 경과 시간, 실제 온라인 러너, 실제 상태만.

const FOREST = '#132117';

const fmtElapsed = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;

function PulseRing({ delay }: { delay: number }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(v, { toValue: 1, duration: 2400, delay, easing: Easing.out(Easing.quad), useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [v, delay]);
  return (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', width: 120, height: 120, borderRadius: 60,
        borderWidth: 1.5, borderColor: colors.volt,
        opacity: v.interpolate({ inputRange: [0, 0.7, 1], outputRange: [0.5, 0.15, 0] }),
        transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 2.6] }) }],
      }}
    />
  );
}

export default function Radar() {
  const bookingId = draft.bookingId;
  const [elapsed, setElapsed] = useState(0);
  const [online, setOnline] = useState<LiveRunner[]>([]);
  const [matchedName, setMatchedName] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const matchedRef = useRef(false);

  // 부킹 없이 진입하면 홈으로 (딥링크/백스택 잔재 방어)
  useEffect(() => {
    if (!bookingId) router.replace('/owner/home');
  }, [bookingId]);

  useEffect(() => {
    const t = setInterval(() => setElapsed((e) => e + 1), 1000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    fetchCertifiedRunners().then(setOnline).catch(() => {});
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
          setTimeout(() => router.replace('/owner/schedule'), 1600);
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
    <View style={{ flex: 1, backgroundColor: FOREST, paddingTop: 64, paddingHorizontal: 24 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.replace('/owner/home')} style={s.backBtn}>
          <Text style={{ fontSize: 18, color: '#f3f1e7' }}>‹</Text>
        </Pressable>
        <View style={s.livePill}>
          <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: colors.volt }} />
          <Text style={{ fontSize: 11, fontWeight: '900', color: colors.volt }}>오픈 매칭</Text>
        </View>
        <View style={{ width: 40 }} />
      </Row>

      {/* ---------- 레이더 코어 ---------- */}
      <View style={{ alignItems: 'center', justifyContent: 'center', marginTop: 70, height: 240 }}>
        {!matchedName && (
          <>
            <PulseRing delay={0} />
            <PulseRing delay={800} />
            <PulseRing delay={1600} />
          </>
        )}
        <View style={[s.core, matchedName != null && { borderColor: colors.volt, borderWidth: 2 }]}>
          <Text style={{ fontSize: 40 }}>{matchedName ? '✓' : '🐕'}</Text>
        </View>
      </View>

      {matchedName ? (
        <View style={{ alignItems: 'center', marginTop: 28 }}>
          <Text style={{ fontSize: 22, fontWeight: '900', color: colors.volt }}>{matchedName} 러너가 수락했어요!</Text>
          <Text style={{ fontSize: 13, color: '#8fa093', marginTop: 8 }}>일정 화면으로 이동할게요</Text>
        </View>
      ) : (
        <View style={{ alignItems: 'center', marginTop: 28 }}>
          <Text style={{ fontSize: 22, fontWeight: '900', color: '#fff' }}>러너를 찾고 있어요</Text>
          <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 8 }}>
            경과 {fmtElapsed(elapsed)} · 보통 몇 분 안에 응답이 와요
          </Text>

          {/* 실제 온라인 러너 — 지금 이 요청을 볼 수 있는 사람들 */}
          {online.length > 0 && (
            <View style={{ alignItems: 'center', marginTop: 26 }}>
              <Row style={{ gap: -8 }}>
                {online.slice(0, 5).map((r) => (
                  <View key={r.profileId} style={s.avatarRim}>
                    <Avatar url={r.avatarUrl} char={r.name[0]} bg="#5a7a3c" size={40} />
                  </View>
                ))}
              </Row>
              <Text style={{ fontSize: 12, color: '#b8c4ae', marginTop: 10 }}>
                지금 온라인 러너 {online.length}명이 요청을 받았어요
              </Text>
            </View>
          )}

          {stale && (
            <View style={s.staleBox}>
              <Text style={{ fontSize: 12.5, color: '#e8c87a', textAlign: 'center', lineHeight: 19 }}>
                아직 응답이 없어요 — 마음에 드는 러너를 직접 지명하면{'\n'}응답 확률이 올라가요
              </Text>
            </View>
          )}
        </View>
      )}

      {!matchedName && (
        <View style={{ position: 'absolute', left: 24, right: 24, bottom: 46, gap: 10 }}>
          <Pressable onPress={() => router.push('/owner/matching')} style={s.pickBtn}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>직접 고를래요 — 러너 카드 보기</Text>
          </Pressable>
          <Pressable onPress={cancel} disabled={cancelling} style={s.cancelBtn}>
            <Text style={{ fontSize: 13, fontWeight: '800', color: '#8fa093' }}>
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
    width: 40, height: 40, borderRadius: 20, backgroundColor: '#26332a',
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#3a4a3e',
  },
  livePill: {
    flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#1d3023',
    borderRadius: 99, paddingVertical: 7, paddingHorizontal: 14, borderWidth: 1, borderColor: '#2c4034',
  },
  core: {
    width: 120, height: 120, borderRadius: 60, backgroundColor: '#1d3023',
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#2c4034',
  },
  avatarRim: { borderWidth: 2, borderColor: FOREST, borderRadius: 22 },
  staleBox: {
    marginTop: 22, backgroundColor: '#241f12', borderRadius: 14, padding: 14,
    borderWidth: 1, borderColor: '#4a3d1e', marginHorizontal: 6,
  },
  pickBtn: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 16 },
  cancelBtn: { alignItems: 'center', paddingVertical: 10 },
});
