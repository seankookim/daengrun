import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../../src/components/ui';
import {
  cancelClubRsvp, checkinClubSession, ClubSessionDetail, fetchClubSession,
  fetchMyDogs, finishClubSession, rsvpClubSession,
} from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { haptic } from '../../../src/lib/haptics';
import { colors } from '../../../src/theme';

// 세션 상세 — S-A(집결 티켓) → S-B(당일 체크인) → done(리캡 플레이스홀더). P-A S1.
// 참가자 행마다 책임 라벨 = 혼합 이벤트 불변식의 UI (P-C는 '위탁 · 담당 ○○' 라벨만 추가).

const FOREST = '#0F1D13';

const ROLE_LABEL: Record<string, { label: string; bg: string; fg: string }> = {
  host_runner: { label: 'HOST · PACE LEAD', bg: '#241C4E', fg: '#9F8FFF' },
  handling_runner: { label: 'HANDLER', bg: '#241C4E', fg: '#9F8FFF' },
  runner_attending: { label: 'RUNNER', bg: '#1D1839', fg: '#8F86C2' },
  owner_attending: { label: 'OWNER', bg: '#1D1839', fg: '#8F86C2' },
};

const dday = (iso: string): string => {
  const d = Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000);
  return d <= 0 ? 'D-DAY' : `D-${d}`;
};

const WAIVER =
  '동반 참가 안내\n\n· 내 강아지의 안전과 행동은 세션 내내 보호자 본인이 책임져요\n· 리드줄 착용은 필수예요\n· 다른 참가자·강아지에게 공격성이 보이면 호스트 안내에 따라 거리를 둬요\n· 사진 촬영이 있을 수 있어요 (공개는 동의한 사진만)';

export default function ClubSession() {
  const df = useDisplayFont();
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [sess, setSess] = useState<ClubSessionDetail | null>(null);
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(() => {
    if (sid) fetchClubSession(sid).then(setSess).catch(() => {});
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setRefreshing(false)); };

  if (!sess) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.nightBg, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: 14.5, color: colors.nightDim }}>불러오는 중...</Text>
      </View>
    );
  }

  const startMs = new Date(sess.scheduledAt).getTime();
  const inCheckinWindow = Date.now() >= startMs - 2 * 3600_000 && Date.now() <= startMs + 6 * 3600_000;
  const isDone = sess.status === 'done';
  const isOpenish = sess.status === 'open' || sess.status === 'full';
  const checkedCount = sess.people.filter((p) => p.attendance === 'checked_in').length;
  const iAmHost = sess.isHost;

  const doRsvp = async () => {
    Alert.alert('참여 전 확인', WAIVER, [
      { text: '취소', style: 'cancel' },
      {
        text: '동의하고 참여',
        onPress: async () => {
          setBusy(true);
          try {
            const dogs = await fetchMyDogs().catch(() => []);
            await rsvpClubSession(sess.id, dogs[0]?.id ?? null);
            haptic('success');
            load();
          } catch (e) {
            const m = (e as Error).message;
            Alert.alert('참여 실패', m.includes('session_full') ? '정원이 찼어요' : m.includes('already_joined') ? '이미 참여 중이에요' : m);
          } finally { setBusy(false); }
        },
      },
    ]);
  };

  const doCancel = () => {
    Alert.alert('참여 취소', '이번 세션 참여를 취소할까요?', [
      { text: '유지', style: 'cancel' },
      { text: '취소하기', style: 'destructive', onPress: () => cancelClubRsvp(sess.id).then(load).catch((e) => Alert.alert('취소 실패', (e as Error).message)) },
    ]);
  };

  const doCheckin = async () => {
    setBusy(true);
    try {
      await checkinClubSession(sess.id);
      haptic('success');
      load();
    } catch (e) {
      Alert.alert('체크인 실패', (e as Error).message.includes('checkin_window') ? '체크인은 시작 2시간 전부터 가능해요' : (e as Error).message);
    } finally { setBusy(false); }
  };

  const doFinish = () => {
    Alert.alert('세션 종료', `${checkedCount}팀 체크인 상태로 세션을 마무리할까요?`, [
      { text: '아직', style: 'cancel' },
      { text: '종료', onPress: () => finishClubSession(sess.id).then(load).catch((e) => Alert.alert('종료 실패', (e as Error).message)) },
    ]);
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.nightBg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 15, paddingTop: 58, paddingBottom: 36 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}>

        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20, color: FOREST }}>‹</Text></Pressable>

        {/* ---------- 집결 티켓 (S-A) — D1×D2: 나이트 스텁 + 프로그램 킥커 ---------- */}
        <View style={s.head}>
          <View style={s.neonEdge} />
          <Text style={s.kicker}>HIGH CLUB — SESSION</Text>
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={[{ fontSize: 21, fontWeight: '900', color: '#fff', flex: 1 }, df]} numberOfLines={1}>
              {clubName ?? '하이클럽'} 세션
            </Text>
            <View style={s.voltPill}>
              <Text style={{ fontSize: 11.5, fontWeight: '900', color: '#fff' }}>
                {isDone ? 'DONE' : sess.status === 'cancelled' ? '취소됨' : dday(sess.scheduledAt)}
              </Text>
            </View>
          </Row>
          <Text style={{ fontSize: 13.5, color: colors.nightDim, marginTop: 4 }}>{sess.when} · 호스트 {sess.hostName ?? '—'} 러너</Text>
          <View style={s.meetupBox}>
            <Text style={{ fontSize: 10.5, letterSpacing: 2, fontWeight: '700', color: colors.nightDim }}>MEET</Text>
            <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff', marginTop: 2 }}>📍 {sess.meetupPoint}</Text>
          </View>
          {/* 바코드 스트립 — 티켓의 물성 */}
          <Row style={{ gap: 2, marginTop: 12, alignItems: 'flex-end', height: 20, opacity: 0.7 }}>
            {Array.from({ length: 26 }).map((_, i) => (
              <View key={i} style={{ width: i % 3 === 0 ? 3.5 : 2, height: i % 4 === 0 ? '62%' : '100%', backgroundColor: colors.nightDim }} />
            ))}
          </Row>
        </View>

        {/* ---------- done: 세션 리캡 (P-B — 실집계 + 리캡 내 다음 RSVP) ---------- */}
        {isDone && (
          <View style={[s.card, { alignItems: 'center', paddingVertical: 20 }]}>
            <Text style={{ fontSize: 30 }}>🏁</Text>
            <Text style={[{ fontSize: 19, fontWeight: '900', color: '#fff', marginTop: 6 }, df]}>오늘의 하이클럽</Text>
            <Text style={{ fontSize: 14.5, color: '#B9B1E8', marginTop: 4 }}>
              {checkedCount}팀{sess.dogCount > 0 ? ` · ${sess.dogCount}마리` : ''}가 함께 달렸어요
            </Text>
            <Text style={{ fontSize: 12.5, color: colors.nightDim, marginTop: 3 }}>리캡이 동네 피드에 올라갔어요</Text>
            {sess.nextSessionId && (
              <Pressable
                onPress={() => router.replace({ pathname: `/club/session/${sess.nextSessionId}`, params: { clubName } })}
                style={[s.cta, { alignSelf: 'stretch' }]}
              >
                <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>다음 세션 참여하기 ›</Text>
              </Pressable>
            )}
          </View>
        )}

        {/* ---------- 참가자 — 책임 라벨 = 불변식의 UI ---------- */}
        <View style={s.card}>
          <Text style={s.entryHead}>ENTRY LIST — {sess.people.length} TEAMS <Text style={{ color: colors.nightDim }}>/ {sess.capacity}</Text></Text>
          {sess.people.map((p, i) => {
            const rl = ROLE_LABEL[p.role] ?? ROLE_LABEL.owner_attending;
            return (
              <Row key={i} style={{ marginTop: 4, alignItems: 'center', gap: 10, paddingVertical: 7, borderBottomWidth: 1, borderBottomColor: '#221C42', ...(p.isMe ? { backgroundColor: '#1B1536', marginHorizontal: -8, paddingHorizontal: 8 } : {}) }}>
                <Text style={s.bib}>{String(i + 1).padStart(3, '0')}</Text>
                <Avatar url={p.avatarUrl} char={p.name[0]} bg="#5a7a3c" size={30} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#EDE9FF' }}>
                    {p.name}{p.dogName ? ` + ${p.dogName}` : ''}{p.isMe ? ' (나)' : ''}
                  </Text>
                </View>
                {p.attendance === 'checked_in' ? (
                  <View style={s.checkedStamp}><Text style={{ fontSize: 9.5, fontWeight: '900', letterSpacing: 1.5, color: colors.volt }}>CHECKED</Text></View>
                ) : (
                  <View style={[s.roleTag, { backgroundColor: rl.bg }]}>
                    <Text style={{ fontSize: 9, fontWeight: '800', letterSpacing: 1.2, color: rl.fg }}>{rl.label}</Text>
                  </View>
                )}
              </Row>
            );
          })}
        </View>

        {/* 🎟 입장권 (D2) — 집결지에서 호스트에게 보여주는 화면 */}
        {sess.joined && !isDone && (
          <Pressable onPress={() => router.push({ pathname: `/club/pass/${sess.id}`, params: { clubName: clubName ?? '' } })} style={s.passBtn}>
            <Text style={{ fontSize: 14.5, fontWeight: '900', color: colors.neon, letterSpacing: 1 }}>🎟 내 입장권 — 집결지에서 보여주세요</Text>
          </Pressable>
        )}

        {/* ---------- CTA 상태 머신 ---------- */}
        {isOpenish && !sess.joined && (
          <Pressable onPress={doRsvp} disabled={busy || sess.status === 'full'} style={[s.cta, (busy || sess.status === 'full') && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff' }}>
              {sess.status === 'full' ? '정원이 찼어요' : '참여하기 (동의문 확인 →)'}
            </Text>
          </Pressable>
        )}
        {isOpenish && sess.joined && sess.myAttendance === 'rsvp' && (
          inCheckinWindow ? (
            <Pressable onPress={doCheckin} disabled={busy} style={[s.cta, busy && { opacity: 0.5 }]}>
              <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff' }}>✓ 집결지 도착 체크인</Text>
            </Pressable>
          ) : (
            <Pressable onPress={doCancel} style={[s.cta, s.ctaGhost]}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#B9B1E8' }}>참여 중 — 취소하려면 탭</Text>
            </Pressable>
          )
        )}
        {isOpenish && sess.myAttendance === 'checked_in' && (
          <View style={[s.cta, { backgroundColor: '#241C4E', borderColor: '#3A3168' }]}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#C9C0FF' }}>체크인 완료 — 좋은 러닝 되세요 🐾</Text>
          </View>
        )}
        {isOpenish && iAmHost && (
          <Pressable onPress={doFinish} style={[s.cta, s.ctaGhost]}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: '#B9B1E8' }}>세션 종료하기 (호스트)</Text>
          </Pressable>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  // D1×D2 나이트 스텁 — 샤프 코너 (라운드 6 이하), 룰 라인·모노 킥커·네온 엣지
  backBtn: { position: 'absolute', top: 56, left: 14, width: 40, height: 40, borderRadius: 6, backgroundColor: colors.nightCard, borderWidth: 1, borderColor: colors.nightEdge, alignItems: 'center', justifyContent: 'center', zIndex: 2 },
  head: { backgroundColor: colors.nightCard, borderRadius: 6, borderWidth: 1, borderColor: colors.nightEdge, padding: 16, paddingLeft: 19, marginTop: 44, overflow: 'hidden' },
  neonEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: colors.neon },
  kicker: { fontSize: 9.5, fontWeight: '700', letterSpacing: 3, color: colors.neon, marginBottom: 6 },
  voltPill: { backgroundColor: colors.club, borderRadius: 4, paddingVertical: 4, paddingHorizontal: 10 },
  meetupBox: { backgroundColor: '#1B1536', borderRadius: 4, padding: 11, marginTop: 11, borderWidth: 1, borderColor: colors.nightEdge },
  card: { backgroundColor: colors.nightCard, borderRadius: 6, borderWidth: 1, borderColor: colors.nightEdge, padding: 15, marginTop: 11 },
  entryHead: { fontSize: 11, fontWeight: '800', letterSpacing: 2, color: colors.neon, marginBottom: 6 },
  bib: { fontSize: 12, fontWeight: '700', color: colors.neon, width: 30, fontVariant: ['tabular-nums'] },
  roleTag: { borderRadius: 4, paddingVertical: 3, paddingHorizontal: 8 },
  checkedStamp: { borderWidth: 1.5, borderColor: colors.volt, borderRadius: 4, paddingVertical: 3, paddingHorizontal: 8, transform: [{ rotate: '-6deg' }] },
  cta: { backgroundColor: colors.club, borderRadius: 6, borderWidth: 1.2, borderColor: colors.neon, alignItems: 'center', paddingVertical: 14, marginTop: 12, shadowColor: colors.neon, shadowOpacity: 0.45, shadowRadius: 12, shadowOffset: { width: 0, height: 0 } },
  ctaGhost: { backgroundColor: 'transparent', borderWidth: 1.5, borderColor: '#3A3168', shadowOpacity: 0 },
  passBtn: { borderWidth: 1.2, borderColor: colors.neon, borderRadius: 6, alignItems: 'center', paddingVertical: 13, marginTop: 11, backgroundColor: '#161130' },
});
