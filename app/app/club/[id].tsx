import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Image, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../src/components/ui';
import {
  claimClubHost, ClubOverview, ClubSeries, createClubSession, fetchClubHostStats, fetchClubMyStats,
  fetchClubOverview, fetchClubSeries, pauseClubSeries, registerClubInterest, startClubSeries, uploadClubPhoto,
} from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { haptic } from '../../src/lib/haptics';
import { colors } from '../../src/theme';

// 하이클럽 페이지 — C1 포토 히어로 (Sean 확정, hi-club-lab ③). P-A S1.
// collecting = 관심 수집 상태 (유령 클럽 금지 — 호스트 클레임 전엔 참여 UI 없음).
// active = 다음 세션 카드 + RSVP 진입. 호스트: 사진 업로드 · 세션 개설 시트.
// P-B 자리(주간 합산·패치 월·세션 히스토리)는 구현 전까지 그리지 않는다.

const FOREST = '#0F1D13';

// 세션 개설 프리셋 — 다음 발생 시각 계산 (S1: 프리셋 3종, 커스텀은 P-B)
const nextSlot = (dow: number, hour: number): Date => {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  let add = (dow - d.getDay() + 7) % 7;
  if (add === 0 && d.getTime() < Date.now() + 2 * 3600_000) add = 7;
  d.setDate(d.getDate() + add);
  return d;
};
const SLOT_PRESETS = [
  { label: '토 09:00', get: () => nextSlot(6, 9) },
  { label: '일 09:00', get: () => nextSlot(0, 9) },
  { label: '내일 07:00', get: () => { const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(7, 0, 0, 0); return d; } },
];

export default function ClubPage() {
  const df = useDisplayFont();
  const [club, setClub] = useState<ClubOverview | null>(null);
  const [myStats, setMyStats] = useState<{ attended: number; streak: number } | null>(null);
  const [hostStats, setHostStats] = useState<{ sessions: number; totalTeams: number; returning: number } | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const load = () => fetchClubOverview().then((c) => {
    setClub(c);
    if (c && c.status === 'active') {
      fetchClubMyStats(c.id).then(setMyStats).catch(() => {});
      fetchClubHostStats(c.id).then(setHostStats).catch(() => {});
      fetchClubSeries(c.id).then(setSeries).catch(() => {}); // ⟳ 정기 시리즈 (0035)
    }
  }).catch(() => {});
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setRefreshing(false)); };

  // 호스트: 세션 개설 시트
  const [sheetOpen, setSheetOpen] = useState(false);
  const [slotIdx, setSlotIdx] = useState(0);
  const [meetup, setMeetup] = useState('');
  const [cap, setCap] = useState(9);
  const [busy, setBusy] = useState(false);
  const [weekly, setWeekly] = useState(false); // ⟳ 매주 반복 (0035)
  const [series, setSeries] = useState<ClubSeries[]>([]);

  const createSession = async () => {
    if (!club || busy) return;
    if (!meetup.trim()) { Alert.alert('집결지를 입력해주세요', '예: 잠수교 북단 계단 앞'); return; }
    setBusy(true);
    try {
      const slot = SLOT_PRESETS[slotIdx].get();
      await createClubSession(club.id, slot.toISOString(), meetup.trim(), cap);
      if (weekly) {
        // ⟳ 매주 반복 (0035) — 같은 요일·시각으로 시리즈 등록, 다음 주부턴 크론이 연다
        const hh = String(slot.getHours()).padStart(2, '0');
        const mm = String(slot.getMinutes()).padStart(2, '0');
        await startClubSeries(club.id, slot.getDay(), `${hh}:${mm}`, meetup.trim(), cap).catch(() => {});
      }
      haptic('success');
      setSheetOpen(false);
      setMeetup('');
      load();
      Alert.alert('세션이 열렸어요 🏁', weekly ? '다음 주부터는 매주 자동으로 열려요 ⟳' : '멤버들에게 보이기 시작해요');
    } catch (e) {
      Alert.alert('세션 개설 실패', (e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const changePhoto = async () => {
    if (!club) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch { Alert.alert('개발 빌드 업데이트 필요'); return; }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) return;
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.75, base64: true, allowsEditing: true, aspect: [16, 9] });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      await uploadClubPhoto(club.id, res.assets[0].base64);
      load();
    } catch (e) {
      Alert.alert('사진 업로드 실패', (e as Error).message);
    }
  };

  const interest = () => {
    if (!club) return;
    registerClubInterest(club.id)
      .then(() => { haptic('light'); load(); })
      .catch((e) => Alert.alert('관심 등록', (e as Error).message));
  };

  const ns = club?.nextSession;
  const left = ns ? ns.capacity - ns.rsvpCount : 0;

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}>

        {/* ---------- C1 포토 히어로 ---------- */}
        <View style={s.hero}>
          {club?.photoUrl
            ? <Image source={{ uri: club.photoUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
            : <View style={[StyleSheet.absoluteFill, { backgroundColor: '#26382a' }]} />}
          <View style={s.heroScrim} />
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20, color: '#fff' }}>‹</Text></Pressable>
          {club?.isHost && (
            <Pressable onPress={changePhoto} style={s.photoBtn}>
              <Text style={{ fontSize: 12, fontWeight: '800', color: '#fff' }}>📷 {club.photoUrl ? '사진 변경' : '클럽 사진 올리기'}</Text>
            </Pressable>
          )}
          <View style={s.heroText}>
            <View style={s.officialPill}><Text style={{ fontSize: 10.5, fontWeight: '900', letterSpacing: 1.5, color: FOREST }}>OFFICIAL</Text></View>
            <Text style={[{ fontSize: 26, fontWeight: '900', color: '#fff', marginTop: 7 }, df]}>{club?.name ?? '하이클럽'}</Text>
            <Text style={{ fontSize: 13, color: '#c6d4bd', marginTop: 4 }}>
              {club
                ? club.status === 'active'
                  ? `멤버 ${club.memberCount} · 호스트 ${club.hostName ?? '—'} 러너 · ${club.district}`
                  : `${club.district} · 호스트 모집 중`
                : ''}
            </Text>
          </View>
        </View>

        <View style={{ padding: 15 }}>
          {club?.description && (
            <Text style={{ fontSize: 14.5, color: '#49524a', lineHeight: 21, marginBottom: 4 }}>{club.description}</Text>
          )}

          {/* ---------- collecting: 관심 수집 (유령 클럽 금지의 UI) ---------- */}
          {club?.status === 'collecting' && (
            <View style={s.card}>
              <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>아직 열리기 전이에요</Text>
              <Text style={{ fontSize: 14, color: '#49524a', marginTop: 5, lineHeight: 20.5 }}>
                관심 등록 {club.interestCount}명 · 인증 러너가 호스트를 맡으면 첫 세션이 열려요
              </Text>
              {club.myInterest ? (
                <View style={[s.cta, { backgroundColor: colors.clubTint }]}><Text style={{ fontSize: 14.5, fontWeight: '900', color: colors.clubInk }}>✓ 관심 등록됨 — 열리면 알려드릴게요</Text></View>
              ) : (
                <Pressable onPress={interest} style={s.cta}><Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>나도 관심 있어요</Text></Pressable>
              )}
              <Pressable
                onPress={() => claimClubHost(club.id).then(() => { Alert.alert('호스트가 됐어요 🏁', '첫 세션을 열어보세요'); load(); })
                  .catch((e) => Alert.alert('호스트 클레임', (e as Error).message.includes('not_certified') ? '인증 러너만 호스트가 될 수 있어요' : (e as Error).message))}
                style={[s.cta, s.ctaGhost]}
              >
                <Text style={{ fontSize: 14, fontWeight: '800', color: '#49524a' }}>인증 러너예요 — 호스트 맡기</Text>
              </Pressable>
            </View>
          )}

          {/* ⟳ 정기 시리즈 리듬 (0035) — 멤버에겐 리듬 안내, 호스트에겐 해지 컨트롤 */}
          {club?.status === 'active' && series.length > 0 && (
            <View style={s.seriesRow}>
              <Text style={{ fontSize: 13.5, fontWeight: '800', color: colors.clubInk, flex: 1 }}>
                ⟳ 매주 {['일', '월', '화', '수', '목', '금', '토'][series[0].weekday]} {series[0].time} 정기 세션
                {series[0].meetupPoint ? ` · 📍 ${series[0].meetupPoint}` : ''}
              </Text>
              {series[0].isHost && (
                <Pressable onPress={() => {
                  Alert.alert('정기 세션 해지', '다음 주부터 자동 개설이 멈춰요.\n이미 열린 세션은 그대로예요.', [
                    { text: '유지', style: 'cancel' },
                    { text: '해지', style: 'destructive', onPress: () => pauseClubSeries(series[0].id).then(load).catch((e) => Alert.alert('해지 실패', (e as Error).message)) },
                  ]);
                }}>
                  <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#8a8a8a' }}>해지</Text>
                </Pressable>
              )}
            </View>
          )}

          {/* ---------- active: 다음 세션 ---------- */}
          {club?.status === 'active' && (
            ns ? (
              <Pressable onPress={() => router.push({ pathname: `/club/session/${ns.id}`, params: { clubName: club.name } })} style={s.card}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>다음 세션 · {ns.when}</Text>
                    <Text style={{ fontSize: 13.5, color: '#49524a', marginTop: 4 }}>📍 {ns.meetupPoint}</Text>
                    <Text style={{ fontSize: 13, color: '#75806f', marginTop: 6 }}>
                      {ns.rsvpCount}팀 참여 중{ns.status === 'open' && left > 0 ? ` · ${left}자리 남음` : ' · 마감'}
                    </Text>
                  </View>
                  <View style={[s.joinPill, ns.joined && { backgroundColor: colors.clubTint }]}>
                    <Text style={{ fontSize: 13, fontWeight: '900', color: ns.joined ? colors.clubInk : '#fff' }}>
                      {ns.joined ? '참여 중 ›' : '참여하기 ›'}
                    </Text>
                  </View>
                </Row>
              </Pressable>
            ) : (
              <View style={s.card}>
                <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 22 }}>
                  예정된 세션이 없어요{club.isHost ? '\n아래에서 새 세션을 열어보세요' : '\n호스트가 세션을 열면 여기에 떠요'}
                </Text>
              </View>
            )
          )}

          {/* ---------- P-B: 내 출석 (실데이터 있을 때만) ---------- */}
          {club?.status === 'active' && myStats && myStats.attended > 0 && (
            <View style={[s.card, { flexDirection: 'row', alignItems: 'center', gap: 12 }]}>
              <View style={s.attendStamp}>
                <Text style={{ fontSize: 16, fontWeight: '900', color: colors.clubDeep }}>×{myStats.attended}</Text>
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>내 출석 {myStats.attended}회</Text>
                {myStats.streak >= 2 && (
                  <Text style={{ fontSize: 12.5, color: colors.clubInk, marginTop: 2 }}>🔥 최근 {myStats.streak}세션 연속 출석</Text>
                )}
              </View>
            </View>
          )}

          {/* ---------- P-B: 호스트 신뢰 카드 (완료 세션 있을 때만) ---------- */}
          {club?.status === 'active' && hostStats && hostStats.sessions > 0 && (
            <View style={s.card}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', letterSpacing: 1, color: '#75806f' }}>HOST RECORD · {club.hostName} 러너</Text>
              <Row style={{ marginTop: 9, justifyContent: 'space-between' }}>
                {[['세션', hostStats.sessions], ['총 참여', hostStats.totalTeams + '팀'], ['재방문', hostStats.returning + '명']].map(([l, v]) => (
                  <View key={l as string} style={{ alignItems: 'center', flex: 1 }}>
                    <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>{v}</Text>
                    <Text style={{ fontSize: 12, color: '#75806f', marginTop: 2 }}>{l}</Text>
                  </View>
                ))}
              </Row>
            </View>
          )}

          {/* ---------- 호스트 도구 ---------- */}
          {club?.isHost && (
            <Pressable onPress={() => setSheetOpen(true)} style={[s.cta, { marginTop: 12 }]}>
              <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>＋ 세션 열기</Text>
            </Pressable>
          )}
        </View>
      </ScrollView>

      {/* ---------- 세션 개설 시트 (호스트, S1 프리셋) ---------- */}
      <Modal visible={sheetOpen} transparent animationType="slide" onRequestClose={() => setSheetOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,.5)' }} onPress={() => setSheetOpen(false)} />
        <View style={s.sheet}>
          <Text style={[{ fontSize: 19, fontWeight: '900', color: FOREST }, df]}>세션 열기</Text>
          <Text style={{ fontSize: 13, color: colors.dim, marginTop: 3 }}>시간·집결지·정원 — 열리면 바로 멤버에게 보여요</Text>
          <Row style={{ gap: 8, marginTop: 14 }}>
            {SLOT_PRESETS.map((p, i) => (
              <Pressable key={p.label} onPress={() => setSlotIdx(i)} style={[s.slotChip, slotIdx === i && { backgroundColor: FOREST, borderColor: FOREST }]}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: slotIdx === i ? '#fff' : '#3d453d' }}>{p.label}</Text>
              </Pressable>
            ))}
          </Row>
          <TextInput
            value={meetup} onChangeText={setMeetup}
            placeholder="집결지 — 예: 잠수교 북단 계단 앞" placeholderTextColor="#b0ada0" style={s.input}
          />
          <Row style={{ gap: 10, marginTop: 12, alignItems: 'center' }}>
            <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>정원</Text>
            {[6, 9, 12].map((c) => (
              <Pressable key={c} onPress={() => setCap(c)} style={[s.slotChip, cap === c && { backgroundColor: FOREST, borderColor: FOREST }]}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: cap === c ? '#fff' : '#3d453d' }}>{c}팀</Text>
              </Pressable>
            ))}
          </Row>
          {/* ⟳ 매주 반복 (0035) — 다음 주부턴 크론이 같은 요일·시각으로 자동 개설 */}
          <Pressable onPress={() => setWeekly((w) => !w)} style={s.weeklyRow}>
            <View style={[s.weeklyBox, weekly && { backgroundColor: colors.club, borderColor: colors.club }]}>
              {weekly && <Text style={{ fontSize: 12, fontWeight: '900', color: '#fff' }}>✓</Text>}
            </View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>⟳ 매주 반복</Text>
              <Text style={{ fontSize: 12.5, color: '#75806f', marginTop: 1 }}>같은 요일·시각으로 매주 자동 개설 — 언제든 해지할 수 있어요</Text>
            </View>
          </Pressable>
          <Pressable onPress={createSession} disabled={busy} style={[s.cta, busy && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff' }}>{busy ? '여는 중...' : '세션 열기 🏁'}</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  hero: { height: 230, justifyContent: 'flex-end' },
  heroScrim: { position: 'absolute' as const, top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(10,16,10,.30)' },
  heroText: { padding: 16, paddingBottom: 15 },
  backBtn: { position: 'absolute', top: 56, left: 14, width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(15,29,19,.45)', alignItems: 'center', justifyContent: 'center', zIndex: 2 },
  photoBtn: { position: 'absolute', top: 62, right: 14, backgroundColor: 'rgba(15,29,19,.55)', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12, zIndex: 2 },
  officialPill: { backgroundColor: colors.club, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 9, alignSelf: 'flex-start' },
  card: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4', padding: 15, marginTop: 10 },
  cta: { backgroundColor: colors.club, borderRadius: 14, alignItems: 'center', paddingVertical: 13, marginTop: 12 },
  ctaGhost: { backgroundColor: '#fff', borderWidth: 1.5, borderColor: '#DCD6C4' },
  // ⟳ 정기 시리즈 (0035)
  seriesRow: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: colors.clubTint, borderRadius: 13, paddingVertical: 10, paddingHorizontal: 13, marginBottom: 10 },
  weeklyRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 13 },
  weeklyBox: { width: 22, height: 22, borderRadius: 7, borderWidth: 2, borderColor: '#c9c4b4', alignItems: 'center', justifyContent: 'center' },
  joinPill: { backgroundColor: colors.club, borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, alignSelf: 'center' },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 18, paddingBottom: 34 },
  slotChip: { borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, backgroundColor: '#fff', borderWidth: 1.3, borderColor: '#DCD6C4' },
  attendStamp: { width: 48, height: 48, borderRadius: 24, borderWidth: 2.5, borderColor: colors.clubDeep, alignItems: 'center', justifyContent: 'center', transform: [{ rotate: '-6deg' }] },
  input: { backgroundColor: '#fff', borderRadius: 13, borderWidth: 1, borderColor: '#DCD6C4', paddingVertical: 12, paddingHorizontal: 14, fontSize: 15, color: FOREST, marginTop: 12 },
});
