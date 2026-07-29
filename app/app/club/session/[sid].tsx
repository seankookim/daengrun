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
  host_runner: { label: 'HOST · 페이스 리드', bg: '#e3f0c4', fg: '#3d5a2b' },
  handling_runner: { label: '위탁 담당', bg: '#e3f0c4', fg: '#3d5a2b' },
  runner_attending: { label: '러너 참여', bg: '#e3f0c4', fg: '#3d5a2b' },
  owner_attending: { label: '보호자 동반', bg: '#EDE8DA', fg: '#5B594A' },
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
      <View style={{ flex: 1, backgroundColor: colors.cream, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: 14.5, color: colors.dim }}>불러오는 중...</Text>
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
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 15, paddingTop: 58, paddingBottom: 36 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}>

        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20, color: FOREST }}>‹</Text></Pressable>

        {/* ---------- 집결 티켓 (S-A) ---------- */}
        <View style={s.head}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={[{ fontSize: 21, fontWeight: '900', color: '#fff', flex: 1 }, df]} numberOfLines={1}>
              {clubName ?? '하이클럽'} 세션
            </Text>
            <View style={s.voltPill}>
              <Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>
                {isDone ? 'DONE' : sess.status === 'cancelled' ? '취소됨' : dday(sess.scheduledAt)}
              </Text>
            </View>
          </Row>
          <Text style={{ fontSize: 13.5, color: '#8fa093', marginTop: 4 }}>{sess.when} · 호스트 {sess.hostName ?? '—'} 러너</Text>
          <View style={s.meetupBox}>
            <Text style={{ fontSize: 11.5, color: '#8fa093' }}>집결지</Text>
            <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff', marginTop: 2 }}>📍 {sess.meetupPoint}</Text>
          </View>
        </View>

        {/* ---------- done: 세션 리캡 (P-B — 실집계 + 리캡 내 다음 RSVP) ---------- */}
        {isDone && (
          <View style={[s.card, { alignItems: 'center', paddingVertical: 20 }]}>
            <Text style={{ fontSize: 30 }}>🏁</Text>
            <Text style={[{ fontSize: 19, fontWeight: '900', color: FOREST, marginTop: 6 }, df]}>오늘의 하이클럽</Text>
            <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 4 }}>
              {checkedCount}팀{sess.dogCount > 0 ? ` · ${sess.dogCount}마리` : ''}가 함께 달렸어요
            </Text>
            <Text style={{ fontSize: 12.5, color: '#9a978a', marginTop: 3 }}>리캡이 동네 피드에 올라갔어요</Text>
            {sess.nextSessionId && (
              <Pressable
                onPress={() => router.replace({ pathname: `/club/session/${sess.nextSessionId}`, params: { clubName } })}
                style={[s.cta, { alignSelf: 'stretch' }]}
              >
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>다음 세션 참여하기 ›</Text>
              </Pressable>
            )}
          </View>
        )}

        {/* ---------- 참가자 — 책임 라벨 = 불변식의 UI ---------- */}
        <View style={s.card}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>
            참가자 {sess.people.length}팀 <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#9a978a' }}>· 정원 {sess.capacity}</Text>
          </Text>
          {sess.people.map((p, i) => {
            const rl = ROLE_LABEL[p.role] ?? ROLE_LABEL.owner_attending;
            return (
              <Row key={i} style={{ marginTop: 11, alignItems: 'center', gap: 10 }}>
                <Avatar url={p.avatarUrl} char={p.name[0]} bg="#5a7a3c" size={32} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>
                    {p.name}{p.dogName ? ` + ${p.dogName}` : ''}
                  </Text>
                </View>
                {p.attendance === 'checked_in' ? (
                  <View style={s.checkedStamp}><Text style={{ fontSize: 9.5, fontWeight: '900', letterSpacing: 1, color: colors.voltDeep }}>CHECKED</Text></View>
                ) : (
                  <View style={[s.roleTag, { backgroundColor: rl.bg }]}>
                    <Text style={{ fontSize: 10.5, fontWeight: '800', color: rl.fg }}>{rl.label}</Text>
                  </View>
                )}
              </Row>
            );
          })}
        </View>

        {/* ---------- CTA 상태 머신 ---------- */}
        {isOpenish && !sess.joined && (
          <Pressable onPress={doRsvp} disabled={busy || sess.status === 'full'} style={[s.cta, (busy || sess.status === 'full') && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>
              {sess.status === 'full' ? '정원이 찼어요' : '참여하기 (동의문 확인 →)'}
            </Text>
          </Pressable>
        )}
        {isOpenish && sess.joined && sess.myAttendance === 'rsvp' && (
          inCheckinWindow ? (
            <Pressable onPress={doCheckin} disabled={busy} style={[s.cta, busy && { opacity: 0.5 }]}>
              <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>✓ 집결지 도착 체크인</Text>
            </Pressable>
          ) : (
            <Pressable onPress={doCancel} style={[s.cta, s.ctaGhost]}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#49524a' }}>참여 중 — 취소하려면 탭</Text>
            </Pressable>
          )
        )}
        {isOpenish && sess.myAttendance === 'checked_in' && (
          <View style={[s.cta, { backgroundColor: '#e7efd8' }]}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#3d5a2b' }}>체크인 완료 — 좋은 러닝 되세요 🐾</Text>
          </View>
        )}
        {isOpenish && iAmHost && (
          <Pressable onPress={doFinish} style={[s.cta, s.ctaGhost]}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: '#49524a' }}>세션 종료하기 (호스트)</Text>
          </Pressable>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { position: 'absolute', top: 56, left: 14, width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', alignItems: 'center', justifyContent: 'center', zIndex: 2 },
  head: { backgroundColor: FOREST, borderRadius: 20, padding: 16, marginTop: 44 },
  voltPill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  meetupBox: { backgroundColor: '#1b2d20', borderRadius: 12, padding: 11, marginTop: 11 },
  card: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4', padding: 15, marginTop: 11 },
  roleTag: { borderRadius: 8, paddingVertical: 3, paddingHorizontal: 8 },
  checkedStamp: { borderWidth: 2, borderColor: colors.voltDeep, borderRadius: 8, paddingVertical: 3, paddingHorizontal: 8, transform: [{ rotate: '-6deg' }] },
  cta: { backgroundColor: colors.volt, borderRadius: 14, alignItems: 'center', paddingVertical: 14, marginTop: 12 },
  ctaGhost: { backgroundColor: '#fff', borderWidth: 1.5, borderColor: '#DCD6C4' },
});
