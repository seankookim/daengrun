import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { claimClubHost, ClubOverview, fetchClubOverview } from '../lib/api';
import { colors } from '../theme';
import { Row } from './ui';

// 하이클럽 홈 모듈 (P-A S1, hi-club-lab H1/H2/R1) — 상태 인지형.
// 정직 규칙: 실세션이 있어야만 그린다 (홈은 실물만 — collecting 수요 수집은 커뮤니티 스트립 담당).

const FOREST = '#0F1D13';

export function useClubOverview(): [ClubOverview | null, () => void] {
  const [club, setClub] = useState<ClubOverview | null>(null);
  const load = useCallback(() => { fetchClubOverview().then(setClub).catch(() => {}); }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  return [club, load];
}

const dday = (iso: string): string => {
  const d = Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000);
  return d <= 0 ? 'D-DAY' : `D-${d}`;
};

// 보호자·러너 공용 발견/커밋 카드 — H1(탐색) ↔ H2(RSVP 후 다크 커밋)
export function ClubHomeCard() {
  const [club] = useClubOverview();
  const ns = club?.nextSession;
  if (!club || club.status !== 'active' || !ns) return null; // 실세션 없으면 안 그림

  if (ns.joined) {
    return (
      <Pressable onPress={() => router.push({ pathname: `/club/session/${ns.id}`, params: { clubName: club.name } })} style={s.commit}>
        <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
          <Text style={{ fontSize: 19, fontWeight: '900', color: '#fff' }}>하이클럽 {dday(ns.scheduledAt)}</Text>
          <View style={s.voltPill}><Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>RSVP 완료</Text></View>
        </Row>
        <Text style={{ fontSize: 13.5, color: '#b8c4ae', marginTop: 5 }} numberOfLines={1}>
          {ns.when} · 📍 {ns.meetupPoint} · {ns.rsvpCount}팀
        </Text>
      </Pressable>
    );
  }
  const left = ns.capacity - ns.rsvpCount;
  return (
    <Pressable onPress={() => router.push({ pathname: `/club/session/${ns.id}`, params: { clubName: club.name } })} style={s.discover}>
      <Row style={{ justifyContent: 'space-between' }}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>🏃 {club.name}</Text>
          <Text style={{ fontSize: 13.5, color: '#49524a', marginTop: 3 }} numberOfLines={1}>{ns.when} · {ns.meetupPoint}</Text>
        </View>
        {left > 0 && ns.status === 'open' && (
          <View style={[s.voltPill, { alignSelf: 'center' }]}><Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>{left}자리</Text></View>
        )}
      </Row>
      <Row style={{ gap: 8, marginTop: 8, alignItems: 'center' }}>
        <Text style={{ fontSize: 12.5, color: '#75806f' }}>{ns.rsvpCount}팀 참여 중</Text>
        <Text style={{ marginLeft: 'auto', fontSize: 13.5, fontWeight: '900', color: colors.voltDeep }}>참여하기 ›</Text>
      </Row>
    </Pressable>
  );
}

// 러너 홈 전용 — collecting이면 호스트 클레임 CTA, 호스트면 내 클럽 현황
export function RunnerClubCard() {
  const [club, reload] = useClubOverview();
  const [busy, setBusy] = useState(false);
  if (!club) return null;

  if (club.status === 'collecting') {
    return (
      <View style={s.discover}>
        <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>🏃 {club.name} — 호스트 모집</Text>
        <Text style={{ fontSize: 13.5, color: '#49524a', marginTop: 3, lineHeight: 19 }}>
          관심 등록 {club.interestCount}명이 기다려요. 인증 러너가 호스트를 맡으면 클럽이 열려요.
        </Text>
        <Pressable
          disabled={busy}
          onPress={() => {
            setBusy(true);
            claimClubHost(club.id)
              .then(() => { Alert.alert('호스트가 됐어요 🏁', '클럽 페이지에서 첫 세션을 열어보세요'); reload(); })
              .catch((e) => Alert.alert('호스트 클레임', (e as Error).message.includes('not_certified') ? '인증 러너만 호스트가 될 수 있어요' : (e as Error).message))
              .finally(() => setBusy(false));
          }}
          style={[s.claimBtn, busy && { opacity: 0.5 }]}
        >
          <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>호스트 되기 ›</Text>
        </Pressable>
      </View>
    );
  }
  if (club.isHost) {
    const ns = club.nextSession;
    return (
      <Pressable onPress={() => router.push(`/club/${club.id}`)} style={s.discover}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>🏁 내 하이클럽</Text>
          <View style={s.hostPill}><Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>HOST</Text></View>
        </Row>
        <Text style={{ fontSize: 13.5, color: '#49524a', marginTop: 4 }} numberOfLines={1}>
          {ns ? `다음 세션 ${ns.when} · 신청 ${ns.rsvpCount}/${ns.capacity}` : '예정 세션 없음 — 탭해서 세션을 열어보세요'}
        </Text>
      </Pressable>
    );
  }
  return <ClubHomeCard />;
}

const s = StyleSheet.create({
  discover: { backgroundColor: '#fbfdf2', borderRadius: 18, borderWidth: 1.5, borderColor: '#cede96', padding: 14, marginTop: 12 },
  commit: { backgroundColor: FOREST, borderRadius: 18, padding: 15, marginTop: 12 },
  voltPill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  hostPill: { backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 9, alignSelf: 'center' },
  claimBtn: { backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11, marginTop: 10 },
});
