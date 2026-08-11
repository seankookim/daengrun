import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { DemandStrip } from '../../src/components/clubcard';
import { Avatar, Row } from '../../src/components/ui';
import { acceptBooking, acceptReschedule, declineReschedule, fetchRescheduleRequests, fetchRunnerInbox, OpenRequest, RescheduleRequest } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { layout, paper } from '../../src/theme';

// 요청 인박스 — deadlines, match score, conflict warnings (docs/calendar.md).
//
// [paper repaint 2026-08-11] forest/cream/volt chrome scrapped → paper. Cards go neutral
// #EEE sharp; the STATUS moves onto §3b chips (지명=amber tint, LIVE=green tint) on the
// datum's own row — the colored 2px card borders retired with the chrome. Accept doors
// use the home ticket's coral-door grammar (CORAL_INK fill, white 17/800) — the assigned
// state color for the accept action; busy = label swap, opacity tricks retired. Miller:
// each card keeps time → dog → payout → tags → memo → course → door, one chunk per row.
// Behavior frozen: accept/acceptReschedule/declineReschedule, focus reload, all routes.

const CORAL_INK = '#C6472C';      // accept-door fill (white label holds ≥4.5:1)
const CORAL_INK_DEEP = '#B23E25';
const MONEY_GREEN = '#3D6B1F';    // reading green — payout/km emphasis
const AMBER_BG = '#FDE8D0';       // pending/directed tint world (paper.pending family)
const AMBER_INK = '#9D580A';

// "7월 31일 (목) 15:30" → ["7월 31일 (목)", "15:30"] — 시간을 1급 정보로 분리
const splitWhen = (w: string): [string, string] => {
  const i = w.lastIndexOf(' ');
  return i < 0 ? [w, ''] : [w.slice(0, i), w.slice(i + 1)];
};

export default function Requests() {
  const df = useDisplayFont(); // display font — screen title (1/screen budget)
  const nf = useNumFont();     // Oswald — request times, payouts
  const [live, setLive] = useState<OpenRequest[]>([]);
  const [accepting, setAccepting] = useState<string | null>(null);
  // 일정 변경 요청 (0016) — 확정 예약의 새 시간 제안, 수락해야만 시간이 바뀐다
  const [resched, setResched] = useState<RescheduleRequest[]>([]);
  const [reschedBusy, setReschedBusy] = useState<string | null>(null);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "새 요청 0건 /
  // 지금은 열린 요청이 없어요" while loading AND on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);

  const load = () => {
    setLoadErr(false);
    return Promise.all([
      fetchRunnerInbox().then(setLive),
      fetchRescheduleRequests().then(setResched),
    ]).then(() => setLoaded(true))
      .catch((e) => { console.warn('[requests] inbox:', e?.message ?? e); setLoadErr(true); });
  };
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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={[{ fontSize: 30, fontWeight: '900', color: paper.ink }, df]}>요청</Text>
            <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3 }}>
              {/* count only after a real load — never "0건" in flight or on failure */}
              {!loaded
                ? loadErr ? '요청을 불러오지 못했어요' : '요청 확인 중...'
                : `새 요청 ${live.length}건${resched.length > 0 ? ` · 변경 요청 ${resched.length}건` : ''}`}
            </Text>
          </View>
          <Pressable style={({ pressed }) => [s.refreshChip, pressed && { backgroundColor: paper.wash }]} onPress={load}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>↻ 새로고침</Text>
          </Pressable>
        </Row>

        {/* ---------- 하이클럽 호스트 수요 스트립 (R1-C, 0032) — 호스트 = 또 하나의 동네 일감.
            대기 팀이 있을 때만 나타난다 (유령 클럽 금지) ---------- */}
        <View style={{ marginTop: 12 }}>
          <DemandStrip />
        </View>

        {/* ---------- 일정 변경 요청 (0016) — 기존→새 시간, 수락/거절 ---------- */}
        {resched.map((rq) => (
          <View key={`rs-${rq.bookingId}`} style={s.reqCard}>
            {/* §3b status chip — amber pending, beside its subject */}
            <View style={[s.chip, { backgroundColor: AMBER_BG, alignSelf: 'flex-start' }]}>
              <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: AMBER_INK }}>일정 변경 요청</Text>
            </View>
            <Text style={{ fontSize: 17, fontWeight: '800', color: paper.ink, marginTop: 10 }}>
              {rq.dogName} · {rq.km}km
            </Text>
            <Row style={{ gap: 8, marginTop: 8, alignItems: 'center' }}>
              <View style={s.timeBox}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: paper.dim }}>기존</Text>
                <Text style={{ fontSize: 14, fontWeight: '700', color: paper.dim, textDecorationLine: 'line-through', marginTop: 1 }}>
                  {rq.curDate}
                </Text>
                <Text style={{ fontSize: 17, fontWeight: '800', color: paper.dim, textDecorationLine: 'line-through' }}>
                  {rq.curTime}
                </Text>
              </View>
              <Text style={{ fontSize: 17, fontWeight: '900', color: AMBER_INK }}>→</Text>
              <View style={[s.timeBox, { backgroundColor: AMBER_BG }]}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: AMBER_INK }}>제안</Text>
                <Text style={{ fontSize: 14, fontWeight: '800', color: AMBER_INK, marginTop: 1 }}>{rq.newDate}</Text>
                <Text style={{ fontSize: 17, fontWeight: '900', color: AMBER_INK }}>{rq.newTime}</Text>
              </View>
            </Row>
            <Row style={{ gap: 8, marginTop: 12 }}>
              {/* busy = label swap on the acting door; both disabled while one is in flight */}
              <Pressable
                style={({ pressed }) => [s.secondaryDoor, pressed && { backgroundColor: paper.wash, transform: [{ scale: 0.96 }] }]}
                disabled={reschedBusy !== null}
                onPress={async () => {
                  setReschedBusy(rq.bookingId);
                  try { await declineReschedule(rq.bookingId); haptic('light'); load(); }
                  catch (e) { Alert.alert('처리 실패', (e as Error).message); }
                  finally { setReschedBusy(null); }
                }}
              >
                <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>거절 (기존 유지)</Text>
              </Pressable>
              <Pressable
                style={({ pressed }) => [s.acceptDoor, pressed && { backgroundColor: CORAL_INK_DEEP, transform: [{ scale: 0.96 }] }]}
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
                <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF' }}>
                  {reschedBusy === rq.bookingId ? '처리 중...' : '새 시간 수락'}
                </Text>
              </Pressable>
            </Row>
          </View>
        ))}

        {/* ---------- 실시간 요청 (Supabase) ---------- */}
        {live.map((req) => (
          <View key={req.bookingId} style={s.reqCard}>
            <Row style={{ justifyContent: 'space-between' }}>
              {/* §3b status chip — the request's nature, 16/800 tinted, no border */}
              <View style={[s.chip, { backgroundColor: req.directed ? AMBER_BG : '#E8F3D2' }]}>
                <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: req.directed ? AMBER_INK : MONEY_GREEN }}>
                  {req.directed ? '★ 지명 요청' : '● LIVE 요청'}
                </Text>
              </View>
              <Row style={{ gap: 5 }}>
                {req.repeatPrior != null && req.repeatPrior > 0 && (
                  <View style={[s.metaChip, { backgroundColor: AMBER_BG }]}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: AMBER_INK }}>⟳ {req.repeatPrior + 1}번째 함께</Text>
                  </View>
                )}
                <View style={[s.metaChip, { backgroundColor: '#E8F3D2' }]}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: MONEY_GREEN }}>{req.directed ? '나를 지명함' : '매칭 대기'}</Text>
                </View>
              </Row>
            </Row>
            {/* 언제 뛰는가 — 요청의 1급 정보 (회색 각주 은퇴, 정보 위계 수정 2026-07-28) */}
            {(() => { const [wd, wt] = splitWhen(req.when); return (
              <Row style={s.whenBar}>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: paper.text }}>{wd}</Text>
                {/* Oswald request time — lineHeight 27 = 1.29× (BUG A) */}
                <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{wt}</Text>
              </Row>
            ); })()}
            <Row style={{ gap: 12, marginTop: 12 }}>
              <Avatar url={req.photoUrl} char={req.dogName[0]} bg={paper.ink} size={48} />
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 18, fontWeight: '800', color: paper.ink }}>
                  {req.dogName} · {req.breed} {req.weightKg}kg
                </Text>
                <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3 }}>
                  <Text style={{ fontWeight: '800', color: MONEY_GREEN }}>{req.km}km</Text> · {req.paceLabel}
                </Text>
              </View>
              <View style={{ alignItems: 'flex-end', alignSelf: 'center' }}>
                {/* Oswald payout — lineHeight 24 = 1.3× (BUG A) */}
                <Text style={[{ fontSize: 18.5, lineHeight: 24, fontWeight: '900', color: MONEY_GREEN, fontVariant: ['tabular-nums'] as const }, nf]}>
                  +{req.payout.toLocaleString()}
                </Text>
                <Text style={{ fontSize: 14, color: paper.dim, marginTop: 1 }}>수수료 33% 제외</Text>
              </View>
            </Row>
            {(req.prefTags.length > 0 || req.vaccines.length > 0) && (
              <Row style={{ gap: 5, marginTop: 9, flexWrap: 'wrap' }}>
                {req.vaccines.length > 0 && (
                  <View style={[s.metaChip, { backgroundColor: '#E3EFF9' }]}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: '#2D6DA8' }}>백신 {req.vaccines.length}종</Text>
                  </View>
                )}
                {req.prefTags.map((t) => (
                  <View key={t} style={[s.metaChip, { backgroundColor: '#F5F5F5' }]}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: paper.text }}>{t}</Text>
                  </View>
                ))}
              </Row>
            )}
            {req.memo && (
              <View style={s.memo}>
                <Text style={{ fontSize: 14.5, color: paper.text, lineHeight: 20 }} numberOfLines={2}>메모: {req.memo}</Text>
              </View>
            )}
            {/* 코스 미리보기 — 수락 전에 코스를 알고 결정한다 (트레이스·지형·점검일) */}
            {req.routeId && req.routeName && (
              <Pressable
                onPress={() => router.push(`/course/${req.routeId}`)}
                style={({ pressed }) => [s.courseLink, pressed && { backgroundColor: paper.wash }]}
              >
                <Text style={{ fontSize: 14, fontWeight: '800', color: paper.text }}>{req.routeName}</Text>
                <Text style={{ fontSize: 14, fontWeight: '800', color: CORAL_INK }}>코스 미리보기 ›</Text>
              </Pressable>
            )}
            <Pressable
              style={({ pressed }) => [s.acceptDoor, { marginTop: 12 }, pressed && { backgroundColor: CORAL_INK_DEEP, transform: [{ scale: 0.96 }] }]}
              disabled={accepting !== null}
              onPress={() => accept(req)}
            >
              <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF' }}>
                {accepting === req.bookingId ? '수락 중...' : '수락하기'}
              </Text>
            </Pressable>
          </View>
        ))}

        {!loaded && !loadErr && (
          <View style={s.empty}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>요청 인박스를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && live.length === 0 && resched.length === 0 && (
          <View style={s.empty}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              지금은 열린 요청이 없어요{'\n'}새 요청이 오면 여기에 표시돼요
            </Text>
          </View>
        )}

        <View style={s.note}>
          <Text style={{ fontSize: 14, lineHeight: 20, color: paper.dim, textAlign: 'center' }}>
            수락하면 캘린더에 확정 일정으로 추가돼요{'\n'}응답 기한이 지나면 요청은 자동 만료됩니다
          </Text>
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  refreshChip: { backgroundColor: paper.canvas, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: paper.line, alignSelf: 'flex-start' },
  reqCard: { backgroundColor: paper.canvas, padding: 15, borderWidth: 1, borderColor: '#EEEEEE', marginTop: 14 },
  chip: { borderRadius: 0, paddingVertical: 4, paddingHorizontal: 9 },
  metaChip: { borderRadius: 0, paddingVertical: 3, paddingHorizontal: 8 },
  memo: { backgroundColor: '#F7F7F7', padding: 9, marginTop: 8 },
  courseLink: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 9, paddingHorizontal: 11, marginTop: 8,
  },
  whenBar: {
    justifyContent: 'space-between', alignItems: 'center', backgroundColor: '#F7F7F7',
    paddingVertical: 8, paddingHorizontal: 13, marginTop: 10,
  },
  timeBox: { flex: 1, backgroundColor: '#F7F7F7', paddingVertical: 7, paddingHorizontal: 10 },
  // accept door — coral-door grammar (home ticket): CORAL_INK fill, white 17/800, sharp
  acceptDoor: {
    flex: 1.4, backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP,
    alignItems: 'center', paddingVertical: 15,
  },
  // secondary door — canvas + coral line border, ink 16/800 (§3b secondary)
  secondaryDoor: {
    flex: 1, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    alignItems: 'center', paddingVertical: 15,
  },
  empty: { marginTop: 24, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 18, alignItems: 'center' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { marginTop: 24, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  note: { marginTop: 18, padding: 10 },
});
