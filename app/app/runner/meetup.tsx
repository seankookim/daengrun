import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingStatus, runnerEnroute, startRunServer } from '../../src/lib/api';
import { runnerJob, runRequests } from '../../src/store';
import { colors } from '../../src/theme';

// 픽업 이동 & 인계 확인 — the trust-critical handoff moment.
// accept → navigate to pickup → 도착 확인 → BOTH parties confirm → run unlocks.
// Real version: live nav (maps), push to owner, mutual confirmation via backend.

const FOREST = '#132117';
type Stage = 'enroute' | 'arrived' | 'waiting' | 'confirmed';

// 네이버 지도 도보 길찾기 — 출발지 생략 시 현재 위치에서 시작 (nmap URL scheme)
const PICKUP = { lat: 37.5443, lng: 127.0398, name: '서울숲 2번 출입구' };

async function openNaverRoute() {
  const app = `nmap://route/walk?dlat=${PICKUP.lat}&dlng=${PICKUP.lng}&dname=${encodeURIComponent(PICKUP.name)}&appname=com.daengrun.app`;
  const web = `https://map.naver.com/p/directions/-/${PICKUP.lng},${PICKUP.lat},${encodeURIComponent(PICKUP.name)}/-/walk`;
  try {
    const canApp = await Linking.canOpenURL(app);
    await Linking.openURL(canApp ? app : web);
  } catch {
    Linking.openURL(web).catch(() => {});
  }
}

export default function Meetup() {
  const req = runRequests[0];
  const [stage, setStage] = useState<Stage>('enroute');
  const poll = useRef<ReturnType<typeof setInterval> | null>(null);

  // 실예약: 서버에 '이동 중' 보고 → 보호자 화면이 실상태를 본다
  useEffect(() => {
    if (runnerJob.bookingId) runnerEnroute(runnerJob.bookingId).catch(() => { /* 이미 enroute면 무시 */ });
  }, []);

  // waiting: 실예약이면 상대 확인을 서버에서 폴링, 아니면 2초 목업
  useEffect(() => {
    if (stage !== 'waiting') return;
    if (runnerJob.bookingId) {
      const id = runnerJob.bookingId;
      poll.current = setInterval(async () => {
        try {
          const st = await fetchBookingStatus(id);
          if (st === 'picked_up' || st === 'active') setStage('confirmed');
        } catch { /* keep polling */ }
      }, 2500);
      return () => { if (poll.current) clearInterval(poll.current); };
    }
    const t = setTimeout(() => setStage('confirmed'), 2000);
    return () => clearTimeout(t);
  }, [stage]);

  const handoff = async () => {
    if (runnerJob.bookingId) {
      try { await confirmHandoff(runnerJob.bookingId); } catch { /* 폴링이 상태를 따라잡음 */ }
    }
    setStage('waiting');
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#eef2e4' }}>
      {/* map to pickup (placeholder) */}
      <View style={{ height: 300 }}>
        <View style={s.roadA} />
        <View style={s.roadB} />
        {/* runner → pickup path */}
        <View style={s.pathDots}>
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <View key={i} style={[s.pathDot, { left: 40 + i * 44, top: 190 - i * 22 }]} />
          ))}
        </View>
        <View style={s.mePin}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>나</Text></View>
        <View style={s.pickupPin}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>픽업</Text></View>

        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>
              {stage === 'enroute' ? '픽업까지 도보 8분 · 0.8km' : '픽업 장소 도착'}
            </Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 20, paddingBottom: 30 }}>
        {/* pickup info */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{PICKUP.name}</Text>
            <Pressable onPress={openNaverRoute} style={{ backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 }}>
              <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#4a6d1f' }}>네이버 길찾기 ›</Text>
            </Pressable>
          </Row>
          <Text style={{ fontSize: 12, color: '#5d655d', marginTop: 5, lineHeight: 17 }}>
            성동구 뚝섬로 273 · 출입구 옆 벤치에서 만나요{'\n'}보호자 지침: 초코가 낯을 안 가려서 바로 인사해도 괜찮아요
          </Text>
        </View>

        {/* dog + owner */}
        <View style={s.card}>
          <Row style={{ gap: 12 }}>
            <Monogram char={req.dogChar} bg={req.dogColor} size={44} />
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>
                {req.dogName} · {req.breed} {req.weightKg}kg
              </Text>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>{req.when} · {req.km}km · 페이스 {req.pace}</Text>
            </View>
            <Pressable style={s.chatChip} onPress={() => router.push('/chat')}>
              <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>보호자 채팅</Text>
            </Pressable>
          </Row>
        </View>

        {/* handoff steps */}
        <View style={s.card}>
          <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST, marginBottom: 10 }}>인계 확인</Text>
          <Step done label="예약 수락 완료 — 보호자에게 알림 전송됨" />
          <Step done={stage !== 'enroute'} label="픽업 장소 도착" active={stage === 'enroute'} />
          <Step
            done={stage === 'confirmed'}
            active={stage === 'arrived' || stage === 'waiting'}
            label={
              stage === 'waiting' ? '보호자 확인 대기 중...'
              : stage === 'confirmed' ? '양측 인계 확인 완료'
              : '양측 인계 확인 (보호자와 러너 모두 확인해야 시작돼요)'
            }
          />
        </View>

        {/* action */}
        {stage === 'enroute' && (
          <Pressable style={s.primary} onPress={() => setStage('arrived')}>
            <Text style={s.primaryText}>픽업 장소 도착 확인</Text>
            <Text style={s.primarySub}>보호자에게 도착 알림이 전송돼요</Text>
          </Pressable>
        )}
        {stage === 'arrived' && (
          <Pressable style={s.primary} onPress={handoff}>
            <Text style={s.primaryText}>{req.dogName} 인계 받았어요</Text>
            <Text style={s.primarySub}>보호자도 확인하면 러닝을 시작할 수 있어요</Text>
          </Pressable>
        )}
        {stage === 'waiting' && (
          <View style={[s.primary, { backgroundColor: '#e9ebe2' }]}>
            <Text style={[s.primaryText, { color: '#75806f' }]}>보호자 확인 대기 중...</Text>
            <Text style={[s.primarySub, { color: '#9aa393' }]}>보호자 앱에 확인 요청을 보냈어요</Text>
          </View>
        )}
        {stage === 'confirmed' && (
          <Pressable
            style={[s.primary, { backgroundColor: colors.volt }]}
            onPress={async () => {
              if (runnerJob.bookingId) {
                try { await startRunServer(runnerJob.bookingId); } catch { /* run 화면에서 재시도 */ }
              }
              router.replace('/runner/run');
            }}
          >
            <Text style={[s.primaryText, { color: FOREST }]}>러닝 시작하기 ›</Text>
            <Text style={[s.primarySub, { color: '#5d6b4a' }]}>인계 완료 · GPS와 바디캠이 켜져요</Text>
          </Pressable>
        )}

        <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 14, lineHeight: 15 }}>
          양측 확인 없이는 러닝이 시작되지 않아요{'\n'}인계 시점부터 펫보험이 적용됩니다
        </Text>
      </ScrollView>
    </View>
  );
}

function Step({ label, done, active }: { label: string; done?: boolean; active?: boolean }) {
  return (
    <Row style={{ gap: 9, marginTop: 7 }}>
      <View style={[s.stepDot, done && { backgroundColor: '#6aa53c' }, active && !done && { borderColor: '#e2c56b', borderWidth: 2, backgroundColor: '#fff' }]}>
        {done && <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>✓</Text>}
      </View>
      <Text style={{ flex: 1, fontSize: 12.5, color: done ? '#3d5a2b' : active ? '#a97c12' : colors.dim, fontWeight: done || active ? '700' : '400' }}>
        {label}
      </Text>
    </Row>
  );
}

const s = StyleSheet.create({
  roadA: { position: 'absolute', top: 150, left: -20, right: -20, height: 16, backgroundColor: '#ffffffaa', transform: [{ rotate: '-14deg' }] },
  roadB: { position: 'absolute', top: 0, bottom: 0, left: 130, width: 13, backgroundColor: '#ffffff88', transform: [{ rotate: '18deg' }] },
  pathDots: { position: 'absolute', inset: 0 },
  pathDot: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: '#5a7a3c' },
  mePin: { position: 'absolute', left: 28, top: 202, width: 26, height: 26, borderRadius: 13, backgroundColor: FOREST, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#fff' },
  pickupPin: { position: 'absolute', left: 292, top: 62, width: 34, height: 26, borderRadius: 13, backgroundColor: '#e8492a', alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#fff' },
  topBar: { position: 'absolute', top: 56, left: 16, right: 16, justifyContent: 'space-between' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  etaPill: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 16 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginBottom: 10 },
  chatChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12, alignSelf: 'center' },
  stepDot: { width: 18, height: 18, borderRadius: 10, backgroundColor: '#e2e0d4', alignItems: 'center', justifyContent: 'center' },
  primary: { backgroundColor: FOREST, borderRadius: 18, alignItems: 'center', paddingVertical: 16, marginTop: 6 },
  primaryText: { fontSize: 15.5, fontWeight: '900', color: '#fff' },
  primarySub: { fontSize: 10.5, color: '#b8c4ae', marginTop: 3 },
});
