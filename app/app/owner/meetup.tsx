import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingSync, fetchCurrentOwnerBookingId, fetchMeetupInfo, MeetupInfo, subscribeBooking } from '../../src/lib/api';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 보호자 인계 화면 — 실신원만 (김민준·초코 목업 은퇴, ui-audit P0).
// 모든 이름·상태는 서버에서. 가짜 ETA 문구 없음.

const FOREST = '#132117';
type Stage = 'enroute' | 'arrived' | 'waiting' | 'confirmed';

export default function OwnerMeetup() {
  const [info, setInfo] = useState<MeetupInfo | null>(null);
  const [stage, setStage] = useState<Stage>('enroute');
  const runnerName = info?.runnerName ?? '러너';
  const dogName = info?.dogName ?? '반려견';

  const poll = useRef<ReturnType<typeof setInterval> | null>(null);
  const [bookingId, setBookingId] = useState<string | null>(draft.bookingId ?? null);
  const [peerConfirmed, setPeerConfirmed] = useState(false); // 러너 측 인계 확인 (서버 진실)

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
      setPeerConfirmed(sync.runnerConfirmed);
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

  const handoff = async () => {
    if (!bookingId) return;
    try { await confirmHandoff(bookingId, 'owner'); } catch { /* 폴링이 따라잡음 */ }
    setStage('waiting');
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#eef2e4' }}>
      {/* map: runner approaching pickup */}
      <View style={{ height: 290 }}>
        <View style={s.roadA} />
        <View style={s.roadB} />
        {[0, 1, 2, 3, 4].map((i) => (
          <View key={i} style={[s.pathDot, { right: 60 + i * 42, top: 80 + i * 26, opacity: stage === 'enroute' ? 1 : 0.3 }]} />
        ))}
        <View style={[s.runnerPin, stage !== 'enroute' && { right: 260, top: 196 }]}>
          <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>{runnerName[0]}</Text>
        </View>
        <View style={s.pickupPin}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>픽업</Text></View>

        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>
              {stage === 'enroute' ? `${runnerName} 러너 매칭됨 — 출발 대기` : `${runnerName} 러너 이동 중`}
            </Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 20, paddingBottom: 30 }}>
        {/* runner card */}
        <View style={s.card}>
          <Row style={{ gap: 12 }}>
            <Monogram char={runnerName[0]} bg="#5a7a3c" size={46} />
            <View style={{ flex: 1 }}>
              <Row style={{ gap: 6 }}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{runnerName} 러너</Text>
                <View style={s.badgePill}><Text style={{ fontSize: 8.5, fontWeight: '800', color: '#4a6d1f' }}>신원인증</Text></View>
              </Row>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 3 }}>
                {info ? `${info.when} · ${info.routeName} ${info.km}km` : '예약 정보 불러오는 중...'}
              </Text>
            </View>
            <Pressable style={s.chatChip} onPress={() => router.push({ pathname: '/chat', params: bookingId ? { bid: bookingId } : {} })}>
              <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>채팅</Text>
            </Pressable>
          </Row>
        </View>

        {/* handoff steps */}
        <View style={s.card}>
          <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST, marginBottom: 10 }}>인계 확인</Text>
          <Step done label="러너 수락 완료" />
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
            done={peerConfirmed || stage === 'confirmed'}
            active={!peerConfirmed && stage === 'waiting'}
            label={peerConfirmed || stage === 'confirmed' ? '러너 인계 확인 완료' : '러너 인계 확인 대기'}
          />
        </View>

        {/* action */}
        {stage === 'enroute' && (
          <View style={[s.primary, { backgroundColor: '#e9ebe2' }]}>
            <Text style={[s.primaryText, { color: '#75806f' }]}>러너 도착을 기다리는 중...</Text>
            <Text style={[s.primarySub, { color: '#9aa393' }]}>도착하면 알림을 보내드려요</Text>
          </View>
        )}
        {stage === 'arrived' && (
          <Pressable style={[s.primary, { backgroundColor: colors.volt }]} onPress={handoff}>
            <Text style={[s.primaryText, { color: FOREST }]}>{dogName}를 인계했어요</Text>
            <Text style={[s.primarySub, { color: '#5d6b4a' }]}>러너도 확인하면 러닝이 시작돼요</Text>
          </Pressable>
        )}
        {stage === 'waiting' && (
          <View style={[s.primary, { backgroundColor: '#e9ebe2' }]}>
            <Text style={[s.primaryText, { color: '#75806f' }]}>러너 확인 대기 중...</Text>
          </View>
        )}
        {stage === 'confirmed' && (
          <View style={s.primary}>
            <Text style={s.primaryText}>인계 완료! 러너가 곧 러닝을 시작해요</Text>
            <Text style={s.primarySub}>시작되면 자동으로 라이브 화면으로 전환돼요</Text>
          </View>
        )}

        <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 14, lineHeight: 15 }}>
          인계 시점부터 펫보험이 적용됩니다{'\n'}러너가 10분 내 도착하지 않으면 자동으로 고객센터가 연결돼요
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
  roadA: { position: 'absolute', top: 140, left: -20, right: -20, height: 16, backgroundColor: '#ffffffaa', transform: [{ rotate: '10deg' }] },
  roadB: { position: 'absolute', top: 0, bottom: 0, left: 200, width: 13, backgroundColor: '#ffffff88', transform: [{ rotate: '-14deg' }] },
  pathDot: { position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: '#5a7a3c' },
  runnerPin: { position: 'absolute', right: 34, top: 56, width: 26, height: 26, borderRadius: 13, backgroundColor: '#FF6347', alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#fff' },
  pickupPin: { position: 'absolute', left: 60, top: 200, width: 34, height: 26, borderRadius: 13, backgroundColor: FOREST, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: '#fff' },
  topBar: { position: 'absolute', top: 56, left: 16, right: 16, justifyContent: 'space-between' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  etaPill: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 16 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginBottom: 10 },
  badgePill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  chatChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12, alignSelf: 'center' },
  stepDot: { width: 18, height: 18, borderRadius: 10, backgroundColor: '#e2e0d4', alignItems: 'center', justifyContent: 'center' },
  primary: { backgroundColor: FOREST, borderRadius: 18, alignItems: 'center', paddingVertical: 16, marginTop: 6 },
  primaryText: { fontSize: 15.5, fontWeight: '900', color: '#fff' },
  primarySub: { fontSize: 10.5, color: '#b8c4ae', marginTop: 3 },
});
