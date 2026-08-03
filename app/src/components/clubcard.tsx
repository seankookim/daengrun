import { router, useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Image, Pressable, Share, StyleSheet, Text, TextInput, View, ViewStyle } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import {
  claimClubHost, ClubOverview, ClubSearchHit, DemandBoard, fetchClubDemandBoard, fetchClubOverview,
  registerClubInterest, requestDistrictClub, searchClubs,
} from '../lib/api';
import { useDisplayFont } from '../lib/displayFont';
import { lilac, lilacRadius, lilacShadow } from '../theme';
import { Row } from './ui';

// 하이클럽 홈 모듈 v3 — 테일러드 라일락 리페인트 (2026-08-03 Sean 디바이스 피드백).
// 로직 동결: 훅·페치·핸들러·라우트·게이트·가드 전부 보존. JSX/StyleSheet/토큰만 라일락으로.
// 월드: 클럽 = 바이올렛 액센트(#6C5CE7) · 카드 흰색 · 캔버스 #F4F2FB · 헤어라인 #E6E2F4 · 코랄은 fill/edge/dot만.

const READ_VIOLET = '#4A3DA8'; // 읽는 바이올렛 (흰 배경 위 라벨·텍스트, 2단 문법)
const VIOLET_TINT = '#F4F1FE'; // 칩·하이라이트 행 배경
const VIOLET_TINT_EDGE = '#DCD6F8'; // 바이올렛 틴트 헤어라인
const NIGHT = '#1C1837'; // 나이트-라일락 다크 인셋 (포레스트 은퇴)

const dday = (iso: string): string => {
  const d = Math.ceil((new Date(iso).getTime() - Date.now()) / 86400000);
  return d <= 0 ? 'D-DAY' : `D-${d}`;
};

// 홀로 포일 엣지 (포일 예산 — 모노그램·티켓 엣지 전용). 각 인스턴스 고유 id로 그라디언트 충돌 방지.
function HoloEdge({ id, style }: { id: string; style?: ViewStyle }) {
  return (
    <Svg height={3} width="100%" viewBox="0 0 100 3" preserveAspectRatio="none" style={style}>
      <Defs>
        <LinearGradient id={id} x1="0" y1="0" x2="1" y2="0">
          <Stop offset="0" stopColor="#CFC5F6" />
          <Stop offset="0.22" stopColor="#FFDCD1" />
          <Stop offset="0.45" stopColor="#F3E9C6" />
          <Stop offset="0.62" stopColor="#EAF6C8" />
          <Stop offset="0.8" stopColor="#CDEAF3" />
          <Stop offset="1" stopColor="#CFC5F6" />
        </LinearGradient>
      </Defs>
      <Rect x="0" y="0" width="100" height="3" fill={`url(#${id})`} />
    </Svg>
  );
}

// 사진 없을 때 라일락 새벽 폴백 (포레스트 필 은퇴 — 바이올렛→코랄 그라디언트)
function BannerFallback() {
  return (
    <Svg style={StyleSheet.absoluteFill} width="100%" height="100%" viewBox="0 0 340 190" preserveAspectRatio="xMidYMid slice">
      <Defs>
        <LinearGradient id="bfsky" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#6C5CE7" />
          <Stop offset="0.5" stopColor="#A98FD8" />
          <Stop offset="0.82" stopColor="#F0987C" />
          <Stop offset="1" stopColor="#F8C4A6" />
        </LinearGradient>
      </Defs>
      <Rect x="0" y="0" width="340" height="190" fill="url(#bfsky)" />
      <Circle cx={262} cy={72} r={30} fill="#FFE3C8" opacity={0.26} />
      <Circle cx={262} cy={72} r={18} fill="#FFE3C8" opacity={0.9} />
    </Svg>
  );
}

export function useClubOverview(): [ClubOverview | null, () => void] {
  const [club, setClub] = useState<ClubOverview | null>(null);
  const load = useCallback(() => { fetchClubOverview().then(setClub).catch(() => {}); }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  return [club, load];
}

// 수요 보드 (0032) — 러너 티켓·스트립 + 보호자 진행 링·동네 리그의 단일 소스
export function useDemandBoard(): [DemandBoard | null, () => void] {
  const [board, setBoard] = useState<DemandBoard | null>(null);
  const load = useCallback(() => { fetchClubDemandBoard().then(setBoard).catch(() => {}); }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  return [board, load];
}

// ---------- 동네 클럽 검색 바 + 드롭다운 (라일락 필드 + 헤어라인 드롭) ----------
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
        <Text style={{ fontSize: 21, color: lilac.dim }}>⌕</Text>
        <TextInput
          value={q} onChangeText={onChange}
          placeholder="동네 하이클럽 검색 — 예: 반포동"
          placeholderTextColor={lilac.dim} style={s.searchInput}
        />
        {q.length > 0 && (
          <Pressable onPress={() => { setQ(''); setHits(null); }} hitSlop={8}>
            <Text style={{ fontSize: 18, color: lilac.dim }}>✕</Text>
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
                  : <Text style={{ fontSize: 22 }}>🏃</Text>}
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 17, fontWeight: '900', color: lilac.head }}>{h.name}</Text>
                <Text style={{ fontSize: 13.5, color: lilac.dim, marginTop: 2 }}>
                  {h.status === 'active' ? `멤버 ${h.memberCount} · 활동 중` : `관심 ${h.interestCount}명 · 모집 중`}
                </Text>
              </View>
              <View style={[s.dropTag, h.status !== 'active' && { backgroundColor: lilac.inset }]}>
                <Text style={{ fontSize: 12, fontWeight: '900', letterSpacing: 0.6, color: h.status === 'active' ? READ_VIOLET : lilac.dim }}>
                  {h.status === 'active' ? 'OPEN' : '모집 중'}
                </Text>
              </View>
            </Pressable>
          ))}
          {hits.length === 0 && q.trim().length >= 2 && (
            <Pressable onPress={requestDistrict} style={s.dropRow}>
              <View style={[s.dropThumb, { backgroundColor: VIOLET_TINT }]}><Text style={{ fontSize: 22, color: lilac.accent }}>＋</Text></View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 17, fontWeight: '900', color: lilac.head }}>'{q.trim()}' 하이클럽 요청하기</Text>
                <Text style={{ fontSize: 13.5, color: lilac.dim, marginTop: 2 }}>아직 없어요 — 관심을 모아 열어요</Text>
              </View>
            </Pressable>
          )}
          {hits.length === 0 && q.trim().length < 2 && (
            <View style={s.dropRow}><Text style={{ fontSize: 15, color: lilac.dim }}>동네 이름을 2자 이상 입력해주세요</Text></View>
          )}
        </View>
      )}
    </View>
  );
}

// ---------- 프로미넌트 포토 배너 (상태 인지형 · 라일락 에디토리얼 — 홀로 엣지 + 바이올렛 직인) ----------
function ClubBanner({ club, role, reload }: { club: ClubOverview; role: 'owner' | 'runner'; reload: () => void }) {
  const df = useDisplayFont();
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
    <Pressable onPress={onPress} style={s.banner}>
      {club.photoUrl
        ? <Image source={{ uri: club.photoUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
        : <BannerFallback />}
      <View style={s.bannerScrim} />
      {/* 홀로 포일 상단 엣지 (포일 예산) + 바이올렛 좌측 트림 */}
      <HoloEdge id="banner-holo" style={s.bannerHolo} />
      <View style={s.bannerEdge} />

      {/* 우상단 상태 태그 (자리/D-day) — 글래스 화이트 + 읽는 바이올렛, 코랄 라이브 도트 */}
      {club.status === 'active' && ns && (joined || (ns.status === 'open' && left > 0)) && (
        <View style={s.ddayPill}>
          <View style={s.liveDot} />
          <Text style={{ fontSize: 14, fontWeight: '900', color: READ_VIOLET }}>
            {joined ? `${dday(ns.scheduledAt)} · RSVP ✓` : `${left}자리`}
          </Text>
        </View>
      )}

      <View style={{ flex: 1, padding: 16, paddingTop: 15, paddingLeft: 18 }}>
        {/* 모노 킥커 + 클럽명 (라일락 마스트헤드 문법) */}
        <Text style={s.bannerKicker}>HIGH CLUB — {club.district}</Text>
        <Text style={[{ fontSize: 33, fontWeight: '900', color: '#fff', paddingRight: 98, marginTop: 3 }, df]} numberOfLines={1}>{club.name}</Text>
        <Text style={{ fontSize: 15.5, color: 'rgba(255,255,255,.86)', marginTop: 6, paddingRight: 98 }} numberOfLines={1}>
          {club.status === 'collecting'
            ? `관심 ${club.interestCount}명 · 호스트를 기다려요`
            : ns
              ? joined
                ? `${ns.when} · 📍 ${ns.meetupPoint}`
                : `다음 세션 ${ns.when} · ${ns.rsvpCount}팀 참여 중`
              : `멤버 ${club.memberCount} · ${club.isHost ? '탭해서 세션을 열어보세요' : '다음 세션 준비 중'}`}
        </Text>
        {/* 액션 행 — 하단 고정 (클럽 월드 = 바이올렛) */}
        <Row style={{ gap: 8, marginTop: 'auto' }}>
          {club.status === 'collecting' && role === 'runner' ? (
            <Pressable onPress={claim} style={s.bannerCta}>
              <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff' }}>호스트 되기 ›</Text>
            </Pressable>
          ) : club.status === 'active' && ns && !joined ? (
            <View style={s.bannerCta}><Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff' }}>참여하기 ›</Text></View>
          ) : club.status === 'active' && joined ? (
            <View style={[s.bannerCta, { backgroundColor: 'rgba(255,255,255,.94)' }]}><Text style={{ fontSize: 15.5, fontWeight: '900', color: READ_VIOLET }}>세션 보기 ›</Text></View>
          ) : (
            <View style={[s.bannerCta, { backgroundColor: 'rgba(255,255,255,.24)' }]}><Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff' }}>클럽 보기 ›</Text></View>
          )}
          {club.isHost && <View style={s.hostPill}><Text style={{ fontSize: 12, fontWeight: '900', color: '#fff' }}>HOST</Text></View>}
        </Row>
      </View>

      {/* 바이올렛 검증 직인 — 클라우트 + 개방성 (여권 직인 → 라일락 실). 워너웃: 보더를 무는 다크 닉 4점 */}
      <View style={s.stamp} pointerEvents="none">
        <Text style={s.stampMain}>HIGH-VERIFIED</Text>
        <Text style={s.stampSub}>FREE TO JOIN · ANYTIME</Text>
        <View style={[s.stampNick, { top: -2, left: 22, width: 7, height: 4 }]} />
        <View style={[s.stampNick, { top: 14, right: -2, width: 4, height: 6 }]} />
        <View style={[s.stampNick, { bottom: -2, left: 52, width: 6, height: 4 }]} />
        <View style={[s.stampNick, { bottom: 12, left: -2, width: 4, height: 5 }]} />
      </View>
    </Pressable>
  );
}

// ---------- R1-A 대기 티켓 (러너 홈 — 대형 CTA · 라일락 티켓) ----------
function DemandTicket({ board, reload }: { board: DemandBoard; reload: () => void }) {
  const mine = board.mine;
  if (!mine || mine.status !== 'collecting' || mine.isHost) return null;
  const claim = () => Alert.alert('호스트 되기', `${mine.district} 하이클럽의 첫 호스트가 될까요?\n세션을 열면 클럽이 시작돼요.`, [
    { text: '다음에', style: 'cancel' },
    {
      text: '호스트 되기', style: 'default',
      onPress: () => claimClubHost(mine.clubId)
        .then(() => { Alert.alert('호스트가 됐어요 🏁', '클럽 페이지에서 첫 세션을 열어보세요'); reload(); })
        .catch((e) => Alert.alert('호스트 클레임', (e as Error).message.includes('not_certified') ? '인증 러너만 호스트가 될 수 있어요' : (e as Error).message)),
    },
  ]);
  return (
    <View style={s.tkt}>
      <HoloEdge id="tkt-holo" style={s.tktHolo} />
      <View style={s.tktStub}>
        <Text style={{ fontSize: 38, fontWeight: '900', color: '#fff', lineHeight: 42 }}>{mine.interestCount}</Text>
        <Text style={{ fontSize: 11, fontWeight: '800', letterSpacing: 1.8, color: 'rgba(255,255,255,.86)', marginTop: 3 }}>WAITING</Text>
      </View>
      <View style={{ flex: 1, padding: 15 }}>
        <Text style={{ fontSize: 18, fontWeight: '900', color: lilac.head }}>{mine.district}에서 {mine.interestCount}팀이 기다려요</Text>
        <Text style={{ fontSize: 15, color: lilac.text, marginTop: 5, lineHeight: 22 }}>인증 러너가 호스트를 맡으면 클럽이 열려요.</Text>
        <Pressable onPress={claim} style={s.tktCta}>
          <Text style={{ fontSize: 18, fontWeight: '900', color: '#fff' }}>🏁 호스트 되기</Text>
        </Pressable>
      </View>
    </View>
  );
}

// ---------- R1-C 스트립 (러너 요청 탭 상단 — 나이트-라일락 다크 아일랜드) ----------
export function DemandStrip() {
  const [board] = useDemandBoard();
  const mine = board?.mine;
  if (!mine || mine.status !== 'collecting' || mine.isHost || mine.interestCount === 0) return null;
  return (
    <Pressable onPress={() => router.push(`/club/${mine.clubId}`)} style={s.strip}>
      <View style={s.stripN}><Text style={{ fontSize: 17, fontWeight: '900', color: READ_VIOLET }}>{mine.interestCount}팀</Text></View>
      <Text style={{ flex: 1, fontSize: 15, color: '#D8CFF7', lineHeight: 21 }}>
        <Text style={{ fontWeight: '900', color: '#fff' }}>{mine.district}</Text>이 호스트를 기다려요 — 첫 세션을 여는 러너가 클럽의 얼굴
      </Text>
      <Text style={{ fontSize: 20, fontWeight: '900', color: '#fff' }}>›</Text>
    </Pressable>
  );
}

// ---------- D-A 진행 링 + 동네 리그 (보호자 홈 — 바이올렛 링 · 라일락 카드) ----------
function ProgressRing({ n, cap }: { n: number; cap: number }) {
  const R = 38; const C = 2 * Math.PI * R;
  const frac = Math.min(1, n / cap);
  return (
    <View style={{ width: 96, height: 96, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={96} height={96} style={{ position: 'absolute', transform: [{ rotate: '-90deg' }] }}>
        <Circle cx={48} cy={48} r={R} stroke={lilac.hair} strokeWidth={9} fill="none" />
        <Circle cx={48} cy={48} r={R} stroke={lilac.accent} strokeWidth={9} fill="none" strokeLinecap="round"
          strokeDasharray={[C * frac, C]} />
      </Svg>
      <Text style={{ fontSize: 18, fontWeight: '900', color: lilac.head }}>{n}/{cap}</Text>
      <Text style={{ fontSize: 11, color: lilac.dim, marginTop: 1 }}>모이는 중</Text>
    </View>
  );
}

function OwnerDemand({ board, reload }: { board: DemandBoard; reload: () => void }) {
  const mine = board.mine;
  const collecting = mine?.status === 'collecting';
  const invite = () => {
    Share.share({
      message: `${board.district} 하이클럽이 열리는 중이에요 🐾 ${mine ? mine.interestCount : 0}팀이 모였어요 — 도그스하이에서 이웃 강아지들과 함께 달려요!`,
    }).catch(() => {});
    if (mine && !mine.myInterest) {
      // 초대하는 사람 = 기다리는 사람 — 내 관심도 조용히 등록 (멱등, 실패 무해)
      registerClubInterest(mine.clubId).then(reload).catch(() => {});
    }
  };
  const league = board.league.filter((l) => l.status === 'active' || l.mine).slice(0, 4);
  if (!collecting && league.length < 2) return null; // 보여줄 이야기가 없으면 침묵
  return (
    <View style={s.demand}>
      {collecting && mine && (
        <View style={s.prog}>
          <ProgressRing n={mine.interestCount} cap={mine.threshold} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 18, fontWeight: '900', color: lilac.head }}>{mine.district} 하이클럽, 열리는 중</Text>
            <Text style={{ fontSize: 15, color: lilac.text, marginTop: 5, lineHeight: 22 }}>
              {mine.threshold}팀이 모이면 호스트 모집 시작 — 이웃을 초대할수록 빨리 열려요.
            </Text>
            <Pressable onPress={invite} style={s.inviteCta}>
              <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>🐾 이웃 초대하기</Text>
            </Pressable>
          </View>
        </View>
      )}
      {league.length > 0 && (
        <View style={[s.league, !collecting && { borderTopWidth: 1, borderTopLeftRadius: lilacRadius.card, borderTopRightRadius: lilacRadius.card }]}>
          <Text style={{ fontSize: 14.5, fontWeight: '900', letterSpacing: 1, color: READ_VIOLET, marginBottom: 8 }}>동네 리그 — 이번 달</Text>
          {league.map((l, i) => (
            <Pressable key={l.clubId} onPress={() => router.push(`/club/${l.clubId}`)} style={[s.lrow, l.mine && s.lrowMe]}>
              <Text style={{ fontSize: 16 }}>{l.status === 'active' ? (i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : '🏃') : '⏳'}</Text>
              <Text style={{ flex: 1, fontSize: 16, fontWeight: '800', color: lilac.head }} numberOfLines={1}>
                {l.name}{l.mine ? ' (우리 동네)' : ''}
              </Text>
              <Text style={{ fontSize: 14, fontWeight: '800', color: l.status === 'active' ? READ_VIOLET : lilac.dim }}>
                {l.status === 'active' ? `세션 ${l.sessionsMonth}회 · ${l.teamsMonth}팀` : `${l.interestCount}팀 대기 중`}
              </Text>
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}

// ---------- 홈 모듈 (양쪽 공용) ----------
export function ClubModule({ role }: { role: 'owner' | 'runner' }) {
  const [club, reload] = useClubOverview();
  const [board, reloadBoard] = useDemandBoard();
  const reloadAll = () => { reload(); reloadBoard(); };
  return (
    <View style={{ marginTop: 14 }}>
      <Row style={{ gap: 8, marginBottom: 11, alignItems: 'center' }}>
        <Text style={{ fontSize: 22, fontWeight: '900', color: lilac.head }}>하이클럽</Text>
        <View style={s.hcChip}><Text style={{ fontSize: 12, fontWeight: '900', letterSpacing: 1.2, color: READ_VIOLET }}>HIGH CLUB</Text></View>
        <Text style={{ fontSize: 14.5, color: lilac.dim }}>동네에서 함께 달려요</Text>
      </Row>
      <ClubSearchBar />
      {club && <ClubBanner club={club} role={role} reload={reloadAll} />}
      {board && role === 'runner' && <DemandTicket board={board} reload={reloadAll} />}
      {board && role === 'owner' && <OwnerDemand board={board} reload={reloadAll} />}
    </View>
  );
}

// 하위 호환 (기존 삽입 지점)
export function ClubHomeCard() { return <ClubModule role="owner" />; }
export function RunnerClubCard() { return <ClubModule role="runner" />; }

const s = StyleSheet.create({
  searchWrap: { flexDirection: 'row', alignItems: 'center', gap: 9, backgroundColor: lilac.card, borderRadius: 12, borderWidth: 1, borderColor: lilac.hair, paddingHorizontal: 15, paddingVertical: 2, ...lilacShadow, shadowOpacity: 0.06 },
  searchInput: { flex: 1, fontSize: 17, color: lilac.head, paddingVertical: 15 },
  drop: { position: 'absolute', top: 64, left: 0, right: 0, backgroundColor: lilac.card, borderRadius: 14, borderWidth: 1, borderColor: lilac.hair, paddingVertical: 5, ...lilacShadow, shadowOpacity: 0.14, shadowRadius: 18, zIndex: 30 },
  dropRow: { flexDirection: 'row', alignItems: 'center', gap: 13, paddingVertical: 13, paddingHorizontal: 15 },
  dropThumb: { width: 48, height: 48, borderRadius: 12, backgroundColor: lilac.inset, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  dropTag: { backgroundColor: VIOLET_TINT, borderWidth: 1, borderColor: VIOLET_TINT_EDGE, borderRadius: lilacRadius.tag, paddingVertical: 5, paddingHorizontal: 10 },
  // ── 라일락 포토 배너 (홀로 엣지 · 나이트-라일락 스크림 · 바이올렛 CTA/직인) ──
  banner: { height: 190, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: lilac.hair, overflow: 'hidden', marginTop: 12, backgroundColor: lilac.card, ...lilacShadow },
  bannerScrim: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(28,24,55,.5)' },
  bannerHolo: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },
  bannerEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: lilac.accent, zIndex: 2 },
  bannerKicker: { fontSize: 12, fontWeight: '700', letterSpacing: 2.4, color: '#D8CFF7', textTransform: 'uppercase' },
  ddayPill: { position: 'absolute', top: 14, right: 14, zIndex: 4, flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: 'rgba(255,255,255,.92)', borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 11 },
  liveDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral },
  // 바이올렛 검증 직인 — 워너웃 + 다크 인셋 잉크
  stamp: { position: 'absolute', right: 24, bottom: 46, borderWidth: 3, borderColor: lilac.accent, borderRadius: 12, paddingVertical: 7, paddingHorizontal: 15, backgroundColor: 'rgba(28,24,55,.42)', transform: [{ rotate: '-7deg' }], alignItems: 'center', opacity: 0.94 },
  stampMain: { fontSize: 17, fontWeight: '900', letterSpacing: 2.4, color: '#D8CFF7' },
  stampSub: { fontSize: 11, fontWeight: '700', letterSpacing: 1.6, color: 'rgba(216,207,247,.86)', marginTop: 3, borderTopWidth: 1, borderTopColor: 'rgba(216,207,247,.42)', paddingTop: 3 },
  stampNick: { position: 'absolute', backgroundColor: 'rgba(28,24,55,.78)', borderRadius: 3 },
  bannerCta: { backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, paddingVertical: 11, paddingHorizontal: 16, shadowColor: lilac.accent, shadowOpacity: 0.36, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 3 },
  hostPill: { backgroundColor: lilac.accentDeep, borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 10, alignSelf: 'center' },
  // ── 클럽 월드 공통 (바이올렛 라일락) ──
  hcChip: { backgroundColor: VIOLET_TINT, borderWidth: 1, borderColor: VIOLET_TINT_EDGE, borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9 },
  // R1-A 대기 티켓 (대형 CTA · 라일락)
  tkt: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 12, ...lilacShadow },
  tktHolo: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },
  tktStub: { width: 104, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center', borderRightWidth: 2, borderRightColor: 'rgba(255,255,255,.42)', borderStyle: 'dashed' },
  tktCta: { backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 16, marginTop: 12, shadowColor: lilac.accent, shadowOpacity: 0.32, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 3 },
  // R1-C 스트립 (요청 탭 · 나이트-라일락 아일랜드)
  strip: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: NIGHT, borderRadius: lilacRadius.card, paddingVertical: 15, paddingHorizontal: 16 },
  stripN: { backgroundColor: '#fff', borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 12 },
  // D-A 진행 링 + 동네 리그
  demand: { marginTop: 12 },
  prog: { flexDirection: 'row', gap: 16, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderTopLeftRadius: lilacRadius.card, borderTopRightRadius: lilacRadius.card, padding: 16, ...lilacShadow },
  inviteCta: { backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, alignSelf: 'flex-start', paddingVertical: 10, paddingHorizontal: 16, marginTop: 10, shadowColor: lilac.accent, shadowOpacity: 0.3, shadowRadius: 8, shadowOffset: { width: 0, height: 3 }, elevation: 2 },
  league: { backgroundColor: lilac.card, borderWidth: 1, borderTopWidth: 0, borderColor: lilac.hair, borderBottomLeftRadius: lilacRadius.card, borderBottomRightRadius: lilacRadius.card, paddingVertical: 13, paddingHorizontal: 14 },
  lrow: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingVertical: 9, paddingHorizontal: 10, borderRadius: lilacRadius.inner },
  lrowMe: { backgroundColor: VIOLET_TINT, borderWidth: 1, borderColor: VIOLET_TINT_EDGE },
});
