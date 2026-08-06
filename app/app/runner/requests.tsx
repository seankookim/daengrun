import { useDisplayFont } from '../../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { DemandStrip } from '../../src/components/clubcard';
import { Avatar, Row } from '../../src/components/ui';
import { acceptBooking, acceptReschedule, declineReschedule, fetchRescheduleRequests, fetchRunnerInbox, OpenRequest, RescheduleRequest } from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { colors } from '../../src/theme';

// 요청 인박스 — deadlines, match score, conflict warnings (docs/calendar.md).

const FOREST = '#0F1D13';

// "7월 31일 (목) 15:30" → ["7월 31일 (목)", "15:30"] — 시간을 1급 정보로 분리
const splitWhen = (w: string): [string, string] => {
  const i = w.lastIndexOf(' ');
  return i < 0 ? [w, ''] : [w.slice(0, i), w.slice(i + 1)];
};

export default function Requests() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [live, setLive] = useState<OpenRequest[]>([]);
  const [accepting, setAccepting] = useState<string | null>(null);
  // 일정 변경 요청 (0016) — 확정 예약의 새 시간 제안, 수락해야만 시간이 바뀐다
  const [resched, setResched] = useState<RescheduleRequest[]>([]);
  const [reschedBusy, setReschedBusy] = useState<string | null>(null);

  const load = () => Promise.all([
    fetchRunnerInbox().then(setLive),
    fetchRescheduleRequests().then(setResched),
  ]).catch((e) => console.warn('[requests] inbox:', e?.message ?? e));
  // 화면에 돌아올 때마다 갱신 — 수락/완료된 요청 카드가 남지 않게
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const accept = async (req: OpenRequest) => {
    setAccepting(req.bookingId);
    try {
      await acceptBooking(req.bookingId);
      haptic('success');
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
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={[{ fontSize: 30, fontWeight: '900', color: FOREST }, df]}>요청</Text>
            <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>
              새 요청 {live.length}건{resched.length > 0 ? ` · 변경 요청 ${resched.length}건` : ''}
            </Text>
          </View>
          <Pressable style={s.autoPill} onPress={load}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: '#3d453d' }}>↻ 새로고침</Text>
          </Pressable>
        </Row>

        {/* ---------- 하이클럽 호스트 수요 스트립 (R1-C, 0032) — 호스트 = 또 하나의 동네 일감.
            대기 팀이 있을 때만 나타난다 (유령 클럽 금지) ---------- */}
        <View style={{ marginTop: 12 }}>
          <DemandStrip />
        </View>

        {/* ---------- 일정 변경 요청 (0016) — 기존→새 시간, 수락/거절 ---------- */}
        {resched.map((rq) => (
          <View key={`rs-${rq.bookingId}`} style={[s.reqCard, { borderColor: '#F59A43', borderWidth: 2 }]}>
            <View style={[s.deadline, { backgroundColor: '#FDE8D0', alignSelf: 'flex-start' }]}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: '#9D580A' }}>⏱ 일정 변경 요청</Text>
            </View>
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 10 }}>
              {rq.dogName} · {rq.km}km
            </Text>
            <Row style={{ gap: 8, marginTop: 8, alignItems: 'center' }}>
              <View style={s.timeBox}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: colors.dim }}>기존</Text>
                <Text style={{ fontSize: 14, fontWeight: '700', color: '#82887a', textDecorationLine: 'line-through', marginTop: 1 }}>
                  {rq.curDate}
                </Text>
                <Text style={{ fontSize: 17, fontWeight: '800', color: '#82887a', textDecorationLine: 'line-through' }}>
                  {rq.curTime}
                </Text>
              </View>
              <Text style={{ fontSize: 17, fontWeight: '900', color: '#F59A43' }}>→</Text>
              <View style={[s.timeBox, { backgroundColor: '#FDE8D0' }]}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: '#9D580A' }}>제안</Text>
                <Text style={{ fontSize: 14, fontWeight: '800', color: '#9D580A', marginTop: 1 }}>{rq.newDate}</Text>
                <Text style={{ fontSize: 17, fontWeight: '900', color: '#9D580A' }}>{rq.newTime}</Text>
              </View>
            </Row>
            <Row style={{ gap: 8, marginTop: 12 }}>
              <Pressable
                style={[s.secondary, reschedBusy === rq.bookingId && { opacity: 0.5 }]}
                disabled={reschedBusy !== null}
                onPress={async () => {
                  setReschedBusy(rq.bookingId);
                  try { await declineReschedule(rq.bookingId); haptic('light'); load(); }
                  catch (e) { Alert.alert('처리 실패', (e as Error).message); }
                  finally { setReschedBusy(null); }
                }}
              >
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#3d453d' }}>거절 (기존 유지)</Text>
              </Pressable>
              <Pressable
                style={[s.accept, reschedBusy === rq.bookingId && { opacity: 0.5 }]}
                disabled={reschedBusy !== null}
                onPress={async () => {
                  setReschedBusy(rq.bookingId);
                  try {
                    await acceptReschedule(rq.bookingId);
                    haptic('success');
                    Alert.alert('변경 수락', '일정이 새 시간으로 변경됐어요 — 캘린더에 반영됩니다');
                    load();
                  } catch (e) { Alert.alert('수락 실패', (e as Error).message); load(); }
                  finally { setReschedBusy(null); }
                }}
              >
                <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>새 시간 수락</Text>
              </Pressable>
            </Row>
          </View>
        ))}

        {/* ---------- 실시간 요청 (Supabase) ---------- */}
        {live.map((req) => (
          <View key={req.bookingId} style={[s.reqCard, req.directed ? { borderColor: '#e2c56b', borderWidth: 2 } : { borderColor: '#5a7a3c', borderWidth: 1.8 }]}>
            <Row style={{ justifyContent: 'space-between' }}>
              <View style={[s.deadline, { backgroundColor: req.directed ? '#fbf0d4' : '#e3f0c4' }]}>
                <Text style={{ fontSize: 14, fontWeight: '900', color: req.directed ? '#a97c12' : '#3d5a2b' }}>
                  {req.directed ? '★ 지명 요청' : '● LIVE 요청'}
                </Text>
              </View>
              <Row style={{ gap: 5 }}>
                {req.repeatPrior != null && req.repeatPrior > 0 && (
                  <View style={[s.matchPill, { backgroundColor: '#fbf0d4' }]}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: '#a97c12' }}>⟳ {req.repeatPrior + 1}번째 함께</Text>
                  </View>
                )}
                <View style={s.matchPill}>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: '#4a6d1f' }}>{req.directed ? '나를 지명함' : '매칭 대기'}</Text>
                </View>
              </Row>
            </Row>
            {/* 언제 뛰는가 — 요청의 1급 정보 (회색 각주 은퇴, 정보 위계 수정 2026-07-28) */}
            {(() => { const [wd, wt] = splitWhen(req.when); return (
              <Row style={s.whenBar}>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#3d5a2b' }}>{wd}</Text>
                <Text style={{ fontSize: 21, fontWeight: '900', color: FOREST }}>{wt}</Text>
              </Row>
            ); })()}
            <Row style={{ gap: 12, marginTop: 12 }}>
              <Avatar url={req.photoUrl} char={req.dogName[0]} bg="#c9a86e" size={48} />
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 18, fontWeight: '900', color: FOREST }}>
                  {req.dogName} · {req.breed} {req.weightKg}kg
                </Text>
                <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>
                  <Text style={{ fontWeight: '900', color: '#3d5a2b' }}>{req.km}km</Text> · {req.paceLabel}
                </Text>
              </View>
              <View style={{ alignItems: 'flex-end', alignSelf: 'center' }}>
                <Text style={{ fontSize: 18.5, fontWeight: '900', color: '#5a7a3c' }}>
                  +{req.payout.toLocaleString()}
                </Text>
                <Text style={{ fontSize: 14, color: colors.dim, marginTop: 1 }}>수수료 33% 제외</Text>
              </View>
            </Row>
            {(req.prefTags.length > 0 || req.vaccines.length > 0) && (
              <Row style={{ gap: 5, marginTop: 9, flexWrap: 'wrap' }}>
                {req.vaccines.length > 0 && (
                  <View style={{ backgroundColor: '#e3eff9', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 }}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: '#2d6da8' }}>💉 백신 {req.vaccines.length}종</Text>
                  </View>
                )}
                {req.prefTags.map((t) => (
                  <View key={t} style={{ backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 }}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: '#3d5a2b' }}>{t}</Text>
                  </View>
                ))}
              </Row>
            )}
            {req.memo && (
              <View style={s.memo}>
                <Text style={{ fontSize: 15, color: '#49524a', lineHeight: 19.5 }} numberOfLines={2}>메모: {req.memo}</Text>
              </View>
            )}
            {/* 코스 미리보기 — 수락 전에 코스를 알고 결정한다 (트레이스·지형·점검일) */}
            {req.routeId && req.routeName && (
              <Pressable onPress={() => router.push(`/course/${req.routeId}`)} style={s.courseLink}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: '#3d5a2b' }}>⛳ {req.routeName}</Text>
                <Text style={{ fontSize: 14, fontWeight: '900', color: '#5a7a3c' }}>코스 미리보기 ›</Text>
              </Pressable>
            )}
            <Pressable
              style={[s.accept, { marginTop: 12 }, accepting === req.bookingId && { opacity: 0.5 }]}
              disabled={accepting !== null}
              onPress={() => accept(req)}
            >
              <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>
                {accepting === req.bookingId ? '수락 중...' : '수락하기'}
              </Text>
            </Pressable>
          </View>
        ))}

        {live.length === 0 && resched.length === 0 && (
          <View style={{ marginTop: 24, backgroundColor: '#f4f2ea', borderRadius: 16, padding: 18, alignItems: 'center' }}>
            <Text style={{ fontSize: 15, color: '#8a8877', textAlign: 'center', lineHeight: 23 }}>
              지금은 열린 요청이 없어요{'\n'}새 요청이 오면 여기에 표시돼요
            </Text>
          </View>
        )}

        <View style={s.note}>
          <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center' }}>
            수락하면 캘린더에 확정 일정으로 추가돼요{'\n'}응답 기한이 지나면 요청은 자동 만료됩니다
          </Text>
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  autoPill: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#DCD6C4', alignSelf: 'flex-start' },
  reqCard: { backgroundColor: '#fff', borderRadius: 20, padding: 15, borderWidth: 1, borderColor: '#DCD6C4', marginTop: 14 },
  deadline: { backgroundColor: '#fbf0d4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  matchPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  conflict: { backgroundColor: '#fdeae5', borderRadius: 10, padding: 9, marginTop: 10 },
  memo: { backgroundColor: '#faf9f3', borderRadius: 10, padding: 9, marginTop: 8 },
  courseLink: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: '#eef4e0', borderRadius: 10, paddingVertical: 9, paddingHorizontal: 11, marginTop: 8 },
  whenBar: { justifyContent: 'space-between', alignItems: 'center', backgroundColor: '#f2f8e2', borderRadius: 12, paddingVertical: 8, paddingHorizontal: 13, marginTop: 10 },
  timeBox: { flex: 1, backgroundColor: '#f4f2ea', borderRadius: 10, paddingVertical: 7, paddingHorizontal: 10 },
  accept: { flex: 1.4, backgroundColor: colors.volt, borderRadius: 13, alignItems: 'center', paddingVertical: 12 },
  secondary: { flex: 1, backgroundColor: '#f4f2ea', borderRadius: 13, alignItems: 'center', paddingVertical: 12 },
  note: { marginTop: 18, padding: 10 },
});
