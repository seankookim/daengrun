import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { confirmHandoff, fetchBookingSync } from '../../src/lib/api';
import { dog, draft, nextBooking, runners } from '../../src/store';
import { colors } from '../../src/theme';

// 보호자 인계 화면 — the owner-side mirror of runner/meetup.
// Runner en route → arrived → owner confirms handoff → both confirmed → live.

const FOREST = '#132117';
type Stage = 'enroute' | 'arrived' | 'waiting' | 'confirmed';

export default function OwnerMeetup() {
  const runner = runners.find((r) => r.id === nextBooking.runnerId) ?? runners[0];
  const [stage, setStage] = useState<Stage>('enroute');

  const poll = useRef<ReturnType<typeof setInterval> | null>(null);
  const live = !!draft.bookingId;

  // 실예약: 모든 단계가 서버 진실을 따른다 — 가짜 도착 없음
  useEffect(() => {
    if (!live) return;
    const bid = draft.bookingId!;
    poll.current = setInterval(async () => {
      try {
        const sync = await fetchBookingSync(bid);
        if (sync.status === 'picked_up' || sync.status === 'active') {
          setStage('confirmed');
        } else if (sync.status === 'runner_enroute') {
          setStage((cur) => (cur === 'waiting' ? cur : 'arrived')); // 러너 이동 중 → 인계 버튼 활성
        } else {
          setStage((cur) => (cur === 'waiting' ? cur : 'enroute')); // 아직 수락/출발 전
        }
      } catch { /* keep polling */ }
    }, 2500);
    return () => { if (poll.current) clearInterval(poll.current); };
  }, [live]);

  // 데모 경로만 타이머 사용
  useEffect(() => {
    if (live) {
      if (stage === 'confirmed') {
        const id = setTimeout(() => router.replace('/owner/live'), 1200);
        return () => clearTimeout(id);
      }
      return;
    }
    if (stage === 'enroute') {
      const id = setTimeout(() => setStage('arrived'), 2500);
      return () => clearTimeout(id);
    }
    if (stage === 'waiting') {
      const id = setTimeout(() => setStage('confirmed'), 1500);
      return () => clearTimeout(id);
    }
    if (stage === 'confirmed') {
      const id = setTimeout(() => router.replace('/owner/live'), 1200);
      return () => clearTimeout(id);
    }
  }, [stage, live]);

  const handoff = async () => {
    if (draft.bookingId) {
      try { await confirmHandoff(draft.bookingId); } catch { /* 폴링이 따라잡음 */ }
    }
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
          <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>{runner.char}</Text>
        </View>
        <View style={s.pickupPin}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>픽업</Text></View>

        <Row style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={s.etaPill}>
            <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>
              {stage === 'enroute' ? `${runner.name} 러너 도착까지 약 6분` : `${runner.name} 러너 도착!`}
            </Text>
          </View>
          <View style={{ width: 40 }} />
        </Row>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 20, paddingBottom: 30 }}>
        {/* runner card */}
        <View style={s.card}>
          <Row style={{ gap: 12 }}>
            <Monogram char={runner.char} bg={runner.color} size={46} />
            <View style={{ flex: 1 }}>
              <Row style={{ gap: 6 }}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{runner.name} 러너</Text>
                {runner.badges.map((b) => (
                  <View key={b} style={s.badgePill}><Text style={{ fontSize: 8.5, fontWeight: '800', color: '#4a6d1f' }}>{b}</Text></View>
                ))}
              </Row>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 3 }}>
                ★ {runner.rating} · {nextBooking.timeLabel} · {nextBooking.routeName}
              </Text>
            </View>
            <Pressable style={s.chatChip} onPress={() => router.push('/chat')}>
              <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>채팅</Text>
            </Pressable>
          </Row>
        </View>

        {/* handoff steps */}
        <View style={s.card}>
          <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST, marginBottom: 10 }}>인계 확인</Text>
          <Step done label="러너 수락 완료" />
          <Step done={stage !== 'enroute'} active={stage === 'enroute'} label={stage === 'enroute' ? '러너 이동 중 — 실시간 위치가 위 지도에 보여요' : '러너 픽업 장소 도착'} />
          <Step
            done={stage === 'confirmed'}
            active={stage === 'arrived' || stage === 'waiting'}
            label={
              stage === 'waiting' ? '러너 확인 대기 중...'
              : stage === 'confirmed' ? '양측 인계 확인 완료 — 러닝이 시작돼요'
              : `${dog.name} 인계 확인 (양측 모두 확인해야 시작돼요)`
            }
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
            <Text style={[s.primaryText, { color: FOREST }]}>{dog.name}를 인계했어요</Text>
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
            <Text style={s.primaryText}>인계 완료! 라이브 화면으로 이동해요</Text>
            <Text style={s.primarySub}>GPS · 바디캠이 켜졌어요</Text>
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
