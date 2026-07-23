import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Monogram, Row } from '../../src/components/ui';
import { acceptBooking, fetchRunnerInbox, OpenRequest } from '../../src/lib/api';
import { runnerJob } from '../../src/store';
import { colors } from '../../src/theme';

// 요청 인박스 — deadlines, match score, conflict warnings (docs/calendar.md).

const FOREST = '#132117';

export default function Requests() {
  const [live, setLive] = useState<OpenRequest[]>([]);
  const [accepting, setAccepting] = useState<string | null>(null);

  const load = () => fetchRunnerInbox().then(setLive).catch((e) => console.warn('[requests] inbox:', e?.message ?? e));
  // 화면에 돌아올 때마다 갱신 — 수락/완료된 요청 카드가 남지 않게
  useFocusEffect(useCallback(() => { load(); }, []));

  const accept = async (req: OpenRequest) => {
    setAccepting(req.bookingId);
    try {
      await acceptBooking(req.bookingId);
      runnerJob.bookingId = req.bookingId;
      Alert.alert('수락 완료', '보호자에게 수락 알림이 전송되었어요');
      router.push('/runner/meetup');
    } catch (e) {
      Alert.alert('수락 실패', (e as Error).message);
      load();
    } finally {
      setAccepting(null);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 60, paddingBottom: 30 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>요청</Text>
            <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>
              새 요청 {live.length}건
            </Text>
          </View>
          <Pressable style={s.autoPill} onPress={load}>
            <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d453d' }}>↻ 새로고침</Text>
          </Pressable>
        </Row>

        {/* ---------- 실시간 요청 (Supabase) ---------- */}
        {live.map((req) => (
          <View key={req.bookingId} style={[s.reqCard, req.directed ? { borderColor: '#e2c56b', borderWidth: 2 } : { borderColor: '#5a7a3c', borderWidth: 1.8 }]}>
            <Row style={{ justifyContent: 'space-between' }}>
              <View style={[s.deadline, { backgroundColor: req.directed ? '#fbf0d4' : '#e3f0c4' }]}>
                <Text style={{ fontSize: 10, fontWeight: '900', color: req.directed ? '#a97c12' : '#3d5a2b' }}>
                  {req.directed ? '★ 지명 요청' : '● LIVE 요청'}
                </Text>
              </View>
              <View style={s.matchPill}>
                <Text style={{ fontSize: 10, fontWeight: '900', color: '#4a6d1f' }}>{req.directed ? '나를 지명함' : '매칭 대기'}</Text>
              </View>
            </Row>
            <Row style={{ gap: 12, marginTop: 12 }}>
              <Monogram char={req.dogName[0]} bg="#c9a86e" size={48} />
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>
                  {req.dogName} · {req.breed} {req.weightKg}kg
                </Text>
                <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>
                  {req.when} · {req.km}km · {req.paceLabel}
                </Text>
              </View>
              <View style={{ alignItems: 'flex-end', alignSelf: 'center' }}>
                <Text style={{ fontSize: 16, fontWeight: '900', color: '#5a7a3c' }}>
                  +{req.payout.toLocaleString()}
                </Text>
                <Text style={{ fontSize: 9, color: colors.dim, marginTop: 1 }}>수수료 20% 제외</Text>
              </View>
            </Row>
            {req.memo && (
              <View style={s.memo}>
                <Text style={{ fontSize: 11.5, color: '#5d655d', lineHeight: 17 }} numberOfLines={2}>메모: {req.memo}</Text>
              </View>
            )}
            <Pressable
              style={[s.accept, { marginTop: 12 }, accepting === req.bookingId && { opacity: 0.5 }]}
              disabled={accepting !== null}
              onPress={() => accept(req)}
            >
              <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>
                {accepting === req.bookingId ? '수락 중...' : '수락하기'}
              </Text>
            </Pressable>
          </View>
        ))}

        {live.length === 0 && (
          <View style={{ marginTop: 24, backgroundColor: '#f4f2ea', borderRadius: 16, padding: 24, alignItems: 'center' }}>
            <Text style={{ fontSize: 13, color: '#8a8877', textAlign: 'center', lineHeight: 20 }}>
              지금은 열린 요청이 없어요{'\n'}새 요청이 오면 여기에 표시돼요
            </Text>
          </View>
        )}

        <View style={s.note}>
          <Text style={{ fontSize: 11.5, color: colors.dim, textAlign: 'center' }}>
            수락하면 캘린더에 확정 일정으로 추가돼요{'\n'}응답 기한이 지나면 요청은 자동 만료됩니다
          </Text>
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  autoPill: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#eceadf', alignSelf: 'flex-start' },
  reqCard: { backgroundColor: '#fff', borderRadius: 20, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 14 },
  deadline: { backgroundColor: '#fbf0d4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  matchPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  conflict: { backgroundColor: '#fdeae5', borderRadius: 10, padding: 9, marginTop: 10 },
  memo: { backgroundColor: '#faf9f3', borderRadius: 10, padding: 9, marginTop: 8 },
  accept: { flex: 1.4, backgroundColor: colors.volt, borderRadius: 13, alignItems: 'center', paddingVertical: 12 },
  secondary: { flex: 1, backgroundColor: '#f4f2ea', borderRadius: 13, alignItems: 'center', paddingVertical: 12 },
  note: { marginTop: 18, padding: 10 },
});
