import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingSync, fetchCurrentRunnerJobId, fetchMeetupInfo, MeetupInfo, runnerEnroute, startRunServer, subscribeBooking } from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { colors } from '../../src/theme';

// 픽업 이동 & 인계 확인 — the trust-critical handoff moment.
// accept → navigate to pickup → 도착 확인 → BOTH parties confirm → run unlocks.
// Real version: live nav (maps), push to owner, mutual confirmation via backend.

const FOREST = '#0F1D13';
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
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const dogName = info?.dogName ?? '반려견';
  const [stage, setStage] = useState<Stage>('enroute');
  const [jobId, setJobId] = useState<string | null>(runnerJob.bookingId ?? null);
  const [peerConfirmed, setPeerConfirmed] = useState(false); // 보호자 측 인계 확인 (서버 진실)
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

  const handoff = async () => {
    if (!jobId) return;
    haptic('success');
    try { await confirmHandoff(jobId, 'runner'); } catch { /* 폴링이 상태를 따라잡음 */ }
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
        <View style={s.mePin}><Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>나</Text></View>
        <View style={s.pickupPin}><Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>픽업</Text></View>

        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt }}>
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
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{PICKUP.name}</Text>
            <Pressable onPress={openNaverRoute} style={{ backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 }}>
              <Text style={{ fontSize: 13, fontWeight: '800', color: '#4a6d1f' }}>네이버 길찾기 ›</Text>
            </Pressable>
          </Row>
          <Text style={{ fontSize: 14, color: '#49524a', marginTop: 5, lineHeight: 19.5 }}>
            성동구 뚝섬로 273 · 출입구 옆 벤치에서 만나요 (실주소는 곧){'\n'}
            {info?.dogMemo ? `보호자 메모: ${info.dogMemo}` : '보호자 메모가 없어요 — 채팅으로 미리 인사해보세요'}
          </Text>
        </View>

        {/* dog + owner */}
        <View style={s.card}>
          <Row style={{ gap: 12 }}>
            <Avatar url={info?.dogPhotoUrl} char={dogName[0]} bg="#c9a86e" size={44} />
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>
                {dogName}{info?.dogBreed ? ` · ${info.dogBreed}` : ''}{info?.dogWeightKg != null ? ` ${info.dogWeightKg}kg` : ''}
              </Text>
              <Text style={{ fontSize: 13, color: colors.dim, marginTop: 2 }}>
                {info ? `${info.when} · ${info.km}km · ${info.paceLabel}` : '예약 정보 불러오는 중...'}
              </Text>
            </View>
            <Pressable style={s.chatChip} onPress={() => router.push({ pathname: '/chat', params: jobId ? { bid: jobId } : {} })}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#4a6d1f' }}>보호자 채팅</Text>
            </Pressable>
          </Row>
        </View>

        {/* handoff steps */}
        <View style={s.card}>
          <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST, marginBottom: 10 }}>인계 확인</Text>
          <Step done label="예약 수락 완료 — 보호자에게 알림 전송됨" />
          <Step done={stage !== 'enroute'} label="픽업 장소 도착" active={stage === 'enroute'} />
          {/* 양측 확인 상태를 각각 서버 진실로 표시 */}
          <Step
            done={stage === 'waiting' || stage === 'confirmed'}
            active={stage === 'arrived'}
            label={stage === 'waiting' || stage === 'confirmed' ? '내 인계 확인 완료' : '내 인계 확인 (양측 모두 확인해야 시작돼요)'}
          />
          <Step
            done={peerConfirmed || stage === 'confirmed'}
            active={!peerConfirmed && stage === 'waiting'}
            label={peerConfirmed || stage === 'confirmed' ? '보호자 인계 확인 완료' : '보호자 인계 확인 대기'}
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
            <Text style={s.primaryText}>{dogName} 인계 받았어요</Text>
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

        <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginTop: 14, lineHeight: 17 }}>
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
        {done && <Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>✓</Text>}
      </View>
      <Text style={{ flex: 1, fontSize: 14.5, color: done ? '#3d5a2b' : active ? '#a97c12' : colors.dim, fontWeight: done || active ? '700' : '400' }}>
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
  topBar: { position: 'absolute', top: 56, left: 10, right: 10, justifyContent: 'space-between' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  etaPill: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 16 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#DCD6C4', marginBottom: 10 },
  chatChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12, alignSelf: 'center' },
  stepDot: { width: 18, height: 18, borderRadius: 10, backgroundColor: '#DCD6C4', alignItems: 'center', justifyContent: 'center' },
  primary: { backgroundColor: FOREST, borderRadius: 18, alignItems: 'center', paddingVertical: 16, marginTop: 6 },
  primaryText: { fontSize: 18, fontWeight: '900', color: '#fff' },
  primarySub: { fontSize: 12, color: '#b8c4ae', marginTop: 3 },
});
