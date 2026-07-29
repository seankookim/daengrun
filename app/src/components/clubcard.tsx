import { router, useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Image, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import {
  claimClubHost, ClubOverview, ClubSearchHit, fetchClubOverview, requestDistrictClub, searchClubs,
} from '../lib/api';
import { useDisplayFont } from '../lib/displayFont';
import { colors } from '../theme';
import { Row } from './ui';

// 하이클럽 홈 모듈 v2 (Sean 2026-07-29: 양쪽 홈에서 훨씬 prominent + 동네 클럽 검색).
// 구성: 검색 바(드롭다운) + 풀블리드 포토 배너 (상태 인지형). 배너는 실존 클럽만 그린다.

const FOREST = '#0F1D13';

const dday = (iso: string): string => {
  const d = Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000);
  return d <= 0 ? 'D-DAY' : `D-${d}`;
};

export function useClubOverview(): [ClubOverview | null, () => void] {
  const [club, setClub] = useState<ClubOverview | null>(null);
  const load = useCallback(() => { fetchClubOverview().then(setClub).catch(() => {}); }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  return [club, load];
}

// ---------- 동네 클럽 검색 바 + 드롭다운 ----------
function ClubSearchBar() {
  const [q, setQ] = useState('');
  const [hits, setHits] = useState<ClubSearchHit[] | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const onChange = (t: string) => {
    setQ(t);
    if (timer.current) clearTimeout(timer.current);
    const query = t.trim();
    if (query.length < 1) { setHits(null); return; }
    timer.current = setTimeout(() => {
      searchClubs(query).then(setHits).catch(() => setHits([]));
    }, 280);
  };
  const closeAnd = (fn: () => void) => { setQ(''); setHits(null); fn(); };

  const requestDistrict = () => {
    const d = q.trim();
    requestDistrictClub(d)
      .then((id) => closeAnd(() => { Alert.alert(`${d} 하이클럽 관심 등록 🐾`, '이웃과 호스트가 모이면 열려요'); router.push(`/club/${id}`); }))
      .catch((e) => Alert.alert('클럽 요청', (e as Error).message.includes('bad_district') ? '동네 이름을 2~12자로 입력해주세요' : (e as Error).message));
  };

  return (
    <View style={{ zIndex: 20 }}>
      <View style={s.searchWrap}>
        <Text style={{ fontSize: 15, color: '#9a978a' }}>⌕</Text>
        <TextInput
          value={q} onChangeText={onChange}
          placeholder="동네 하이클럽 검색 — 예: 반포동"
          placeholderTextColor="#9a978a" style={s.searchInput}
        />
        {q.length > 0 && (
          <Pressable onPress={() => { setQ(''); setHits(null); }} hitSlop={8}>
            <Text style={{ fontSize: 13, color: '#9a978a' }}>✕</Text>
          </Pressable>
        )}
      </View>
      {/* 드롭다운 */}
      {hits != null && (
        <View style={s.drop}>
          {hits.map((h) => (
            <Pressable key={h.id} onPress={() => closeAnd(() => router.push(`/club/${h.id}`))} style={s.dropRow}>
              <View style={s.dropThumb}>
                {h.photoUrl
                  ? <Image source={{ uri: h.photoUrl }} style={{ width: '100%', height: '100%' }} />
                  : <Text style={{ fontSize: 15 }}>🏃</Text>}
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{h.name}</Text>
                <Text style={{ fontSize: 12.5, color: '#75806f', marginTop: 1 }}>
                  {h.status === 'active' ? `멤버 ${h.memberCount} · 활동 중` : `관심 ${h.interestCount}명 · 모집 중`}
                </Text>
              </View>
              <View style={[s.dropPill, h.status !== 'active' && { backgroundColor: '#EDE8DA' }]}>
                <Text style={{ fontSize: 10.5, fontWeight: '900', color: h.status === 'active' ? FOREST : '#5B594A' }}>
                  {h.status === 'active' ? 'OPEN' : '모집 중'}
                </Text>
              </View>
            </Pressable>
          ))}
          {hits.length === 0 && q.trim().length >= 2 && (
            <Pressable onPress={requestDistrict} style={s.dropRow}>
              <View style={[s.dropThumb, { backgroundColor: '#e7efd8' }]}><Text style={{ fontSize: 15 }}>＋</Text></View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>'{q.trim()}' 하이클럽 요청하기</Text>
                <Text style={{ fontSize: 12.5, color: '#75806f', marginTop: 1 }}>아직 없어요 — 관심을 모아 열어요</Text>
              </View>
            </Pressable>
          )}
          {hits.length === 0 && q.trim().length < 2 && (
            <View style={s.dropRow}><Text style={{ fontSize: 13.5, color: '#9a978a' }}>동네 이름을 2자 이상 입력해주세요</Text></View>
          )}
        </View>
      )}
    </View>
  );
}

// 볼트→탱 그라디언트 아웃라인 (Sean 확정 E3 변형) — SVG 스트로크, 신규 네이티브 의존성 0
function GradientOutline({ w, h }: { w: number; h: number }) {
  if (w === 0) return null;
  return (
    <Svg pointerEvents="none" width={w} height={h} style={StyleSheet.absoluteFill}>
      <Defs>
        <LinearGradient id="clubEdge" x1="0" y1="0" x2="1" y2="0.35">
          <Stop offset="0" stopColor={colors.volt} />
          <Stop offset="0.45" stopColor="#7FA818" />
          <Stop offset="1" stopColor={colors.tang} />
        </LinearGradient>
      </Defs>
      <Rect x={1.25} y={1.25} width={w - 2.5} height={h - 2.5} rx={20} stroke="url(#clubEdge)" strokeWidth={2.5} fill="none" />
    </Svg>
  );
}

// ---------- 프로미넌트 포토 배너 (상태 인지형 · V2 여권 직인 — Sean 확정) ----------
function ClubBanner({ club, role, reload }: { club: ClubOverview; role: 'owner' | 'runner'; reload: () => void }) {
  const df = useDisplayFont();
  const [size, setSize] = useState({ w: 0, h: 0 });
  const ns = club.nextSession;
  const joined = !!ns?.joined;
  const left = ns ? Math.max(0, ns.capacity - ns.rsvpCount) : 0;

  const claim = () => claimClubHost(club.id)
    .then(() => { Alert.alert('호스트가 됐어요 🏁', '클럽 페이지에서 첫 세션을 열어보세요'); reload(); })
    .catch((e) => Alert.alert('호스트 클레임', (e as Error).message.includes('not_certified') ? '인증 러너만 호스트가 될 수 있어요' : (e as Error).message));

  const onPress = () => {
    if (club.status === 'active' && ns) {
      router.push({ pathname: `/club/session/${ns.id}`, params: { clubName: club.name } });
    } else {
      router.push(`/club/${club.id}`);
    }
  };

  return (
    <Pressable onPress={onPress} style={s.banner} onLayout={(e) => setSize({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}>
      {club.photoUrl
        ? <Image source={{ uri: club.photoUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
        : <View style={[StyleSheet.absoluteFill, { backgroundColor: '#26382a' }]} />}
      <View style={s.bannerScrim} />

      {/* 우상단 상태 필 (자리/D-day) */}
      {club.status === 'active' && ns && (joined || (ns.status === 'open' && left > 0)) && (
        <View style={s.ddayPill}>
          <Text style={{ fontSize: 12, fontWeight: '900', color: FOREST }}>
            {joined ? `${dday(ns.scheduledAt)} · RSVP ✓` : `${left}자리`}
          </Text>
        </View>
      )}

      <View style={{ flex: 1, padding: 14, paddingTop: 16 }}>
        {/* 클럽명 — 상단으로, 더 크게 (Sean 2026-07-29) */}
        <Text style={[{ fontSize: 26, fontWeight: '900', color: '#fff', paddingRight: 92 }, df]} numberOfLines={1}>{club.name}</Text>
        <Text style={{ fontSize: 13, color: '#d8e2d0', marginTop: 4, paddingRight: 92 }} numberOfLines={1}>
          {club.status === 'collecting'
            ? `관심 ${club.interestCount}명 · 호스트를 기다려요`
            : ns
              ? joined
                ? `${ns.when} · 📍 ${ns.meetupPoint}`
                : `다음 세션 ${ns.when} · ${ns.rsvpCount}팀 참여 중`
              : `멤버 ${club.memberCount} · ${club.isHost ? '탭해서 세션을 열어보세요' : '다음 세션 준비 중'}`}
        </Text>
        {/* 액션 행 — 하단 고정 */}
        <Row style={{ gap: 8, marginTop: 'auto' }}>
          {club.status === 'collecting' && role === 'runner' ? (
            <Pressable onPress={claim} style={s.bannerCta}>
              <Text style={{ fontSize: 13, fontWeight: '900', color: FOREST }}>호스트 되기 ›</Text>
            </Pressable>
          ) : club.status === 'active' && ns && !joined ? (
            <View style={s.bannerCta}><Text style={{ fontSize: 13, fontWeight: '900', color: FOREST }}>참여하기 ›</Text></View>
          ) : club.status === 'active' && joined ? (
            <View style={[s.bannerCta, { backgroundColor: 'rgba(255,255,255,.92)' }]}><Text style={{ fontSize: 13, fontWeight: '900', color: FOREST }}>세션 보기 ›</Text></View>
          ) : (
            <View style={[s.bannerCta, { backgroundColor: 'rgba(255,255,255,.25)' }]}><Text style={{ fontSize: 13, fontWeight: '900', color: '#fff' }}>클럽 보기 ›</Text></View>
          )}
          {club.isHost && <View style={s.hostPill}><Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>HOST</Text></View>}
        </Row>
      </View>

      {/* V2 여권 직인 — 클라우트 + 개방성 한 도장에 (Sean 확정) */}
      <View style={s.stamp} pointerEvents="none">
        <Text style={s.stampMain}>HIGH-VERIFIED</Text>
        <Text style={s.stampSub}>FREE TO JOIN · ANYTIME</Text>
      </View>

      <GradientOutline w={size.w} h={size.h} />
    </Pressable>
  );
}

// ---------- 홈 모듈 (양쪽 공용) ----------
export function ClubModule({ role }: { role: 'owner' | 'runner' }) {
  const [club, reload] = useClubOverview();
  return (
    <View style={{ marginTop: 14 }}>
      <Row style={{ gap: 6, marginBottom: 9, alignItems: 'baseline' }}>
        <Text style={{ fontSize: 18, fontWeight: '900', color: FOREST }}>하이클럽</Text>
        <Text style={{ fontSize: 12.5, color: '#75806f' }}>동네에서 함께 달려요</Text>
      </Row>
      <ClubSearchBar />
      {club && <ClubBanner club={club} role={role} reload={reload} />}
    </View>
  );
}

// 하위 호환 (기존 삽입 지점)
export function ClubHomeCard() { return <ClubModule role="owner" />; }
export function RunnerClubCard() { return <ClubModule role="runner" />; }

const s = StyleSheet.create({
  searchWrap: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4', paddingHorizontal: 13, paddingVertical: 2 },
  searchInput: { flex: 1, fontSize: 14.5, color: FOREST, paddingVertical: 11 },
  drop: { position: 'absolute', top: 50, left: 0, right: 0, backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4', paddingVertical: 4, shadowColor: '#000', shadowOpacity: 0.14, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 8, zIndex: 30 },
  dropRow: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingVertical: 10, paddingHorizontal: 13 },
  dropThumb: { width: 38, height: 38, borderRadius: 12, backgroundColor: '#EDE8DA', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  dropPill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  banner: { height: 152, borderRadius: 21, overflow: 'hidden', marginTop: 10, backgroundColor: '#26382a' },
  bannerScrim: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(10,16,10,.36)' },
  ddayPill: { position: 'absolute', top: 13, right: 13, zIndex: 2, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  stamp: { position: 'absolute', right: 12, bottom: 12, borderWidth: 2.5, borderColor: colors.volt, borderRadius: 9, paddingVertical: 5, paddingHorizontal: 10, backgroundColor: 'rgba(15,29,19,.35)', transform: [{ rotate: '-7deg' }], alignItems: 'center' },
  stampMain: { fontSize: 12, fontWeight: '900', letterSpacing: 2, color: colors.volt },
  stampSub: { fontSize: 7.5, fontWeight: '700', letterSpacing: 1.6, color: 'rgba(198,245,66,.8)', marginTop: 2, borderTopWidth: 1, borderTopColor: 'rgba(198,245,66,.4)', paddingTop: 2 },
  bannerCta: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 7, paddingHorizontal: 13 },
  hostPill: { backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 9, alignSelf: 'center' },
});
