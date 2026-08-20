import { router, useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Image, Pressable, Share, StyleSheet, Text, TextInput, View, ViewStyle } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import {
  claimClubHost, ClubOverview, ClubSearchHit, DemandBoard, fetchClubDemandBoard, fetchClubOverview,
  registerClubInterest, requestDistrictClub, searchClubs,
} from '../lib/api';
import { useDisplayFont } from '../lib/displayFont';
import { lilac, lilacShadow, paper } from '../theme';
import { Icon, Row } from './ui';

// 하이클럽 홈 모듈 v5 — 나이트 스텁 × 시트맵 (2026-08-05 Sean 확정: glowup-go-lab Ⓐ② 전반 + Ⓐ④ 시트맵).
// 흰 틴트-헤더 카드 폐기 → 종이 피드 위의 다크 아일랜드로 교체 (가치 반전 = 가장 강한 강조):
//   나이트-라일락(#1C1837) 카드 · 찢어진 점선 스텁 열(D-day 큰 숫자 · RSVP 도트 · HOST) ·
//   홀로 모노그램 + 3px 홀로 상단 엣지(포일 예산 정확히 2) · 좌석 = capacity 핍 그리드(rsvpCount 채움).
// 로직 동결: 훅·페치·핸들러·라우트 타깃(/club/${id} — 문 하나)·상태 분기·HOST 진실 전부 보존. JSX/StyleSheet만 변경.
// 타입 플로어: 나이트 위 디테일 14.5~15 · 1차 값 16+ · 레터스페이스 대문자 킥커만 예외. 디스플레이 숫자는 lineHeight ≥1.2×.

const READ_VIOLET = '#4A3DA8'; // 읽는 바이올렛 (흰 배경 위 라벨·텍스트, 2단 문법)
const VIOLET_TINT = '#F4F1FE'; // 칩·하이라이트 행 배경
const VIOLET_TINT_EDGE = '#DCD6F8'; // 바이올렛 틴트 헤어라인
const NIGHT = '#1C1837'; // 나이트-라일락 다크 인셋 (포레스트 은퇴)
const NIGHT_EDGE = '#3A3266'; // 나이트 카드 보더 (lab .a2)
const NIGHT_TXT = '#D8CFF7'; // 나이트 위 본문 딤 — 대비 11.5:1
const NIGHT_KK = '#CFC5F6'; // 나이트 위 킥커 — 대비 10.5:1
const NIGHT_HAIR = 'rgba(255,255,255,0.24)'; // 스텁 찢김선 (점선 divider — tktStub 선례)
const SEAT_ON = '#F0765A'; // 채워진 좌석 = 코랄 (lilac.coral)
const CORAL_READ = '#FFC3B1'; // 나이트 위 읽는 코랄 — 대비 11.1:1

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

// 홀로 모노그램 필 (클럽 정체성 스퀘어 — 포일 예산). 대각 홀로 그라디언트로 스퀘어를 채운다.
function HoloSquare({ id }: { id: string }) {
  return (
    <Svg style={StyleSheet.absoluteFill} width="100%" height="100%" viewBox="0 0 30 30" preserveAspectRatio="none">
      <Defs>
        <LinearGradient id={id} x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#CFC5F6" />
          <Stop offset="0.22" stopColor="#FFDCD1" />
          <Stop offset="0.45" stopColor="#F3E9C6" />
          <Stop offset="0.62" stopColor="#EAF6C8" />
          <Stop offset="0.8" stopColor="#CDEAF3" />
          <Stop offset="1" stopColor="#CFC5F6" />
        </LinearGradient>
      </Defs>
      <Rect x="0" y="0" width="30" height="30" fill={`url(#${id})`} />
    </Svg>
  );
}

// [3차 피드백] 헤더 Svg 그라디언트가 기기에서 잘린 어두운 밴드로 렌더 → 플랫 틴트로 교체 (clubTop bg).

// [정직 2026-08-19] 구현은 `.then(setClub).catch(() => {})` 였다 — 조용한 catch. 리페치가 실패하면
// 모듈이 아무 말 없이 사라졌고(실측: 콜드 런치엔 보이고 리포커스 뒤 사라짐), 그건 CLAUDE.md의
// "실패를 실패로 보여준다 · silent catch → happy UI 금지"를 정면으로 어긴다.
// 이제 세 상태를 구분한다: 로딩(club null, failed false) · 실패(failed true) · 실데이터.
// 직전 실값은 유지한다 — 리페치 한 번 실패했다고 화면에 있던 진짜 클럽을 지우는 건 과잉이다.
// 그래서 실패 행은 '보여줄 데이터가 하나도 없을 때만' 뜬다 (club === null && failed).
export function useClubOverview(): [ClubOverview | null, () => void, boolean] {
  const [club, setClub] = useState<ClubOverview | null>(null);
  const [failed, setFailed] = useState(false);
  const load = useCallback(() => {
    setFailed(false);
    fetchClubOverview()
      .then((c) => { setClub(c); setFailed(false); })
      .catch((e) => { console.warn('[club] overview:', (e as Error)?.message ?? e); setFailed(true); });
  }, []);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  return [club, load, failed];
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
      .then((id) => closeAnd(() => { Alert.alert(`${d} 하이클럽 관심 등록`, '이웃과 호스트가 모이면 열려요'); router.push(`/club/${id}`); }))
      .catch((e) => Alert.alert('클럽 요청', (e as Error).message.includes('bad_district') ? '동네 이름을 2~12자로 입력해주세요' : (e as Error).message));
  };

  return (
    <View style={{ zIndex: 20 }}>
      <View style={s.searchWrap}>
        <Text style={{ fontSize: 19, color: lilac.dim }}>⌕</Text>
        <TextInput
          value={q} onChangeText={onChange}
          placeholder="동네 하이클럽 검색 — 예: 반포동"
          placeholderTextColor={lilac.dim} style={s.searchInput}
        />
        {q.length > 0 && (
          <Pressable onPress={() => { setQ(''); setHits(null); }} hitSlop={8}>
            <Text style={{ fontSize: 16, color: lilac.dim }}>✕</Text>
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
                  : <Icon name="Users" glyph="●" size={18} color={lilac.dim} />}
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>{h.name}</Text>
                <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 2 }}>
                  {h.status === 'active' ? `멤버 ${h.memberCount} · 활동 중` : `관심 ${h.interestCount}명 · 모집 중`}
                </Text>
              </View>
              <View style={[s.dropTag, h.status !== 'active' && { backgroundColor: lilac.inset }]}>
                {/* [§3b 상태칩] 16/800 */}
                <Text style={{ fontSize: 16, fontWeight: '800', letterSpacing: 0.6, color: h.status === 'active' ? READ_VIOLET : lilac.dim }}>
                  {h.status === 'active' ? 'OPEN' : '모집 중'}
                </Text>
              </View>
            </Pressable>
          ))}
          {hits.length === 0 && q.trim().length >= 2 && (
            <Pressable onPress={requestDistrict} style={s.dropRow}>
              <View style={[s.dropThumb, { backgroundColor: VIOLET_TINT }]}><Text style={{ fontSize: 20, color: lilac.accent }}>＋</Text></View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>'{q.trim()}' 하이클럽 요청하기</Text>
                <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 2 }}>아직 없어요 — 관심을 모아 열어요</Text>
              </View>
            </Pressable>
          )}
          {hits.length === 0 && q.trim().length < 2 && (
            <View style={s.dropRow}><Text style={{ fontSize: 14, color: lilac.dim }}>동네 이름을 2자 이상 입력해주세요</Text></View>
          )}
        </View>
      )}
    </View>
  );
}

// ---------- 하이클럽 카드 (상태 인지형 · Ⓐ② 나이트 스텁 × Ⓐ④ 시트맵) ----------
// 종이 피드 위 단 하나의 다크 아일랜드. 왼쪽 = 찢어진 점선 스텁(큰 D-day · RSVP 도트 · HOST),
// 오른쪽 = 홀로 모노그램/킥커/클럽명 → 요일·시각 → 집결지·호스트 → 시트맵 → 클럽 홈 고스트 CTA.
// 좌석은 문장이 아니라 그림이다: capacity만큼 핍을 그리고 rsvpCount만큼 채운다 (고정 8 금지).
function ClubBanner({ club, role, reload }: { club: ClubOverview; role: 'owner' | 'runner'; reload: () => void }) {
  const df = useDisplayFont();
  const ns = club.nextSession;
  const joined = !!ns?.joined;
  const left = ns ? Math.max(0, ns.capacity - ns.rsvpCount) : 0;
  const active = club.status === 'active';

  // [홈 = 루트, Sean 3차 확정] 카드 탭 = 항상 클럽 홈 — 문 하나. 세션·참여·호스트 클레임은 전부
  // 클럽 홈(티켓·콘솔 행·collecting 카드)이 가진다. 카드 자체는 공개 세션 정보를 즉시 보여준다.
  // (2차 리라이트에서 세션 직행 분기가 되살아났던 회귀를 다시 제거. 러너 클레임 경로는 DemandTicket 유지.)
  const onPress = () => router.push(`/club/${club.id}`);
  void role; void reload; // 시그니처 유지 (클레임·역할 분기는 홈으로 이관)

  // 모노그램 = 클럽명 첫 글자 (기본 정체성). 다음 세션 요일/시각은 기존 ns.when(kstParts) 파싱.
  const initial = (club.name ?? '').trim().charAt(0) || '·';
  const wmatch = ns ? ns.when.match(/\(([^)]+)\)\s*(.*)$/) : null;
  const dayLabel = wmatch ? wmatch[1] : '';
  const timeLabel = wmatch ? wmatch[2] : (ns ? ns.when : '');

  // 스텁 숫자 — 기존 3분기(active+세션 / collecting / active-무세션) 그대로, 자리만 헤더 태그 → 스텁.
  const stubValue = active && ns
    ? dday(ns.scheduledAt)
    : String(club.status === 'collecting' ? club.interestCount : club.memberCount);
  const stubKicker = active && ns ? 'NEXT' : club.status === 'collecting' ? 'WAITING' : 'MEMBERS';
  const stubWide = stubValue.length >= 5; // 'D-DAY'·5자리 수 — 한 단계 축소해서 84dp 스텁 폭 안에 눕힌다

  // 시트맵 — 정직: 정원이 12면 12개를 그린다. 상한 24는 렌더 가드(프리셋 6·9·12, 명세 범위 4~16).
  const seatN = ns ? Math.max(0, Math.min(ns.capacity, 24)) : 0;
  const seatFilled = ns ? Math.max(0, Math.min(ns.rsvpCount, seatN)) : 0;
  const seatSmall = seatN > 10; // 320dp에서도 두 줄 안에 들어오게 (랩 + 축소)

  return (
    <Pressable onPress={onPress} style={s.clubCard}>
      {/* 포일 예산 ①/② — 3px 홀로 상단 엣지 */}
      <HoloEdge id="club-holo-edge" style={s.clubEdge} />

      <View style={s.clubRow}>
        {/* 찢어진 스텁 열 — 점선 divider · 큰 D-day/관심/멤버 · RSVP 도트(joined) · HOST 진실 */}
        <View style={s.clubStub}>
          {club.isHost && <View style={s.stubHost}><Text style={s.stubHostText}>HOST</Text></View>}
          <Text style={[stubWide ? s.stubNumSm : s.stubNum, df]} numberOfLines={1}>{stubValue}</Text>
          <Text style={s.stubK}>{stubKicker}</Text>
          {active && ns && joined && (
            <View style={s.stubRsvp}>
              <View style={s.stubRsvpDot} />
              <Text style={s.stubRsvpText}>RSVP ✓</Text>
            </View>
          )}
        </View>

        {/* 본문 열 */}
        <View style={s.clubMain}>
          <View style={s.clubIdRow}>
            {/* 포일 예산 ②/② — 홀로 모노그램 (디스플레이 서체는 스텁 숫자가 가져갔다 → 900 폴백) */}
            <View style={s.clubMono}>
              <HoloSquare id="club-holo" />
              <Text style={s.clubMonoText}>{initial}</Text>
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={s.clubKk} numberOfLines={1}>HIGH CLUB — {club.district}</Text>
              <Text style={s.clubName} numberOfLines={1}>{club.name}</Text>
            </View>
          </View>

          {active && ns ? (
            <>
              <View style={s.clubWhen}>
                {dayLabel !== '' && <Text style={s.clubWhenD}>{dayLabel}</Text>}
                <Text style={s.clubWhenT}>{timeLabel}</Text>
              </View>
              <Text style={s.clubSub} numberOfLines={1}>
                {ns.meetupPoint}{club.hostName ? ` · 호스트 ${club.hostName}` : ''}
              </Text>
              {/* 시트맵 — capacity 핍 / rsvpCount 채움 (Ⓐ④). 남은 자리는 세는 게 아니라 보인다. */}
              <View style={s.clubSeats}>
                <View style={s.seatGrid}>
                  {Array.from({ length: seatN }).map((_, i) => (
                    <View key={i} style={[seatSmall ? s.seatPipSm : s.seatPip, i < seatFilled && s.seatPipOn]} />
                  ))}
                </View>
                <Text style={s.seatLb} numberOfLines={1}>
                  {ns.status === 'open' ? (left > 0 ? `${left}자리` : '마감 임박') : '마감'}
                </Text>
              </View>
            </>
          ) : (
            <Text style={s.clubLine} numberOfLines={2}>
              {club.status === 'collecting'
                ? `호스트를 기다려요 · 멤버 ${club.memberCount}명`
                : club.isHost ? '탭해서 세션을 열어보세요' : '다음 세션 준비 중'}
            </Text>
          )}

          {/* CTA 하나 — 문은 클럽 홈뿐 (Sean 3차: 두 버튼의 차이가 불명확 → 홈이 모든 갈래를 가진다) */}
          <Pressable onPress={onPress} style={({ pressed }) => [s.clubGhost, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
            <Text style={s.clubGhostText}>클럽 홈 ›</Text>
          </Pressable>
        </View>
      </View>

      {/* 이너 이중-프레임 헤어라인 (히어로 카드 법 — 나이트 위에선 흰 9%) */}
      <View style={s.clubDbl} pointerEvents="none" />
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
        .then(() => { Alert.alert('호스트가 됐어요', '클럽 페이지에서 첫 세션을 열어보세요'); reload(); })
        .catch((e) => Alert.alert('호스트 클레임', (e as Error).message.includes('not_certified') ? '인증 러너만 호스트가 될 수 있어요' : (e as Error).message)),
    },
  ]);
  return (
    <View style={s.tkt}>
      <HoloEdge id="tkt-holo" style={s.tktHolo} />
      <View style={s.tktStub}>
        <Text style={{ fontSize: 28, fontWeight: '900', color: '#fff', lineHeight: 32 }}>{mine.interestCount}</Text>
        <Text style={{ fontSize: 10, fontWeight: '800', letterSpacing: 1.6, color: 'rgba(255,255,255,.86)', marginTop: 3 }}>WAITING</Text>
      </View>
      <View style={{ flex: 1, padding: 15 }}>
        <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>{mine.district}에서 {mine.interestCount}팀이 기다려요</Text>
        <Text style={{ fontSize: 14, color: lilac.text, marginTop: 5, lineHeight: 19 }}>인증 러너가 호스트를 맡으면 클럽이 열려요.</Text>
        <Pressable onPress={claim} style={({ pressed }) => [s.tktCta, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
          {/* [§3b] 버튼 라벨 플로어 16/800 · scale 0.96 프레스 */}
          <Text style={{ fontSize: 16, fontWeight: '800', color: '#fff' }}>호스트 되기</Text>
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
      <View style={s.stripN}><Text style={{ fontSize: 14, fontWeight: '800', color: READ_VIOLET }}>{mine.interestCount}팀</Text></View>
      <Text style={{ flex: 1, fontSize: 14, color: '#D8CFF7', lineHeight: 19 }}>
        <Text style={{ fontWeight: '800', color: '#fff' }}>{mine.district}</Text>이 호스트를 기다려요 — 첫 세션을 여는 러너가 클럽의 얼굴
      </Text>
      <Text style={{ fontSize: 18, fontWeight: '800', color: '#fff' }}>›</Text>
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
      <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>{n}/{cap}</Text>
      <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 1 }}>모이는 중</Text>
    </View>
  );
}

function OwnerDemand({ board, reload }: { board: DemandBoard; reload: () => void }) {
  const mine = board.mine;
  const collecting = mine?.status === 'collecting';
  const invite = () => {
    Share.share({
      message: `${board.district} 하이클럽이 열리는 중이에요. ${mine ? mine.interestCount : 0}팀이 모였어요 — 도그스하이에서 이웃 강아지들과 함께 달려요!`,
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
            <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>{mine.district} 하이클럽, 열리는 중</Text>
            <Text style={{ fontSize: 14, color: lilac.text, marginTop: 5, lineHeight: 19 }}>
              {mine.threshold}팀이 모이면 호스트 모집 시작 — 이웃을 초대할수록 빨리 열려요.
            </Text>
            <Pressable onPress={invite} style={({ pressed }) => [s.inviteCta, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
              {/* [§3b] 버튼 라벨 플로어 16/800 · scale 0.96 프레스 */}
              <Text style={{ fontSize: 16, fontWeight: '800', color: '#fff' }}>이웃 초대하기</Text>
            </Pressable>
          </View>
        </View>
      )}
      {league.length > 0 && (
        <View style={[s.league, !collecting && { borderTopWidth: 1 }]}>
          <Text style={{ fontSize: 14, fontWeight: '800', letterSpacing: 1, color: READ_VIOLET, marginBottom: 8 }}>동네 리그 — 이번 달</Text>
          {league.map((l, i) => (
            <Pressable key={l.clubId} onPress={() => router.push(`/club/${l.clubId}`)} style={[s.lrow, l.mine && s.lrowMe]}>
              <Text style={{ fontSize: 14, fontWeight: '900', width: 18, color: l.status === 'active' ? READ_VIOLET : lilac.dim }}>
                {l.status === 'active' ? String(i + 1) : '—'}
              </Text>
              <Text style={{ flex: 1, fontSize: 14, fontWeight: '700', color: lilac.head }} numberOfLines={1}>
                {l.name}{l.mine ? ' (우리 동네)' : ''}
              </Text>
              <Text style={{ fontSize: 14, fontWeight: '700', color: l.status === 'active' ? READ_VIOLET : lilac.dim }}>
                {l.status === 'active' ? `세션 ${l.sessionsMonth}회 · ${l.teamsMonth}팀` : `${l.interestCount}팀 대기 중`}
              </Text>
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}

// ---------- compact 행 (보호자 홈 전용, 2026-08-19 랩 ⑧) ----------
// 나이트 스텁 카드는 홈의 두 번째 다크 아일랜드였다 (⑧ 법: 다크 섬은 화면에 하나, active 상태의
// 라이브 위젯뿐). 홈에서는 같은 진실을 **라이트 modh 행 하나**로 말한다 — 새 데이터 0개:
// 아래 분기는 ClubBanner의 분기를 그대로 옮긴 것이고, 목적지도 같은 문(`/club/{id}`) 하나다.
function ClubCompactRow({ club }: { club: ClubOverview }) {
  const ns = club.nextSession;
  const active = club.status === 'active';
  // 타이틀 — 실제 클럽명이 이미 '하이클럽'을 포함하면(예: '반포동 하이클럽') 접두를 붙이지 않는다:
  // '하이클럽 · 반포동 하이클럽'은 같은 말을 두 번 하는 것이다.
  const title = club.name.includes('하이클럽') ? club.name : `하이클럽 · ${club.name}`;
  // 서브 — ClubBanner의 스텁/라인 분기와 같은 필드만 읽는다 (지어내는 값 0개).
  const bits: string[] = [];
  if (club.isHost) bits.push('호스트');
  if (active && ns) {
    bits.push(ns.when);                                    // kstParts 파생 — '8월 22일 (토) 07:30'
    if (ns.joined) bits.push('참여 ✓');
    const left = Math.max(0, ns.capacity - ns.rsvpCount);
    bits.push(ns.status === 'open' ? (left > 0 ? `${left}자리 남음` : '마감 임박') : '마감');
  } else if (club.status === 'collecting') {
    bits.push(`관심 ${club.interestCount}팀 · 호스트를 기다려요`);
  } else {
    bits.push(`멤버 ${club.memberCount}명`);
    bits.push(club.isHost ? '탭해서 세션을 열어보세요' : '다음 세션 준비 중');
  }
  // [2026-08-20 Sean] 각인 클럽 위젯 — 랩 `home-state-lab.html`의 ③(포일 엣지 + 모노그램 +
  // 원장 발치)이 이겼다. 이긴 이유는 예쁨이 아니라 **비대칭**이다: 모노그램이 왼쪽, 화살표가
  // 오른쪽이라 '들어가는 행'으로 읽히고, 가운데 정렬 명패(①)처럼 '보는 판'으로 읽히지 않는다.
  // 나이트 판(④)은 더 강한 물건이지만 홈에 두 번째 다크 아일랜드를 다시 들여오므로 탈락했다.
  // 발치의 원장 줄은 소속의 증거(설립·멤버 수)이고 전부 실필드다 — 지어낸 값 0개.
  const mono = club.name.trim().charAt(0) || '클';
  return (
    <Pressable
      onPress={() => router.push(`/club/${club.id}`)}
      style={({ pressed }) => [s.cEngrave, pressed && { opacity: 0.94 }]}
      accessibilityRole="button" accessibilityLabel={`${title} 클럽 홈`}
    >
      <View style={s.cFoil} />
      <View style={s.cEngraveBody}>
        <View style={s.cMono}><Text style={s.cMonoT}>{mono}</Text></View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={s.cEngraveT} numberOfLines={1}>{title}</Text>
          <Text style={s.cEngraveSub} numberOfLines={1}>{bits.join(' · ')}</Text>
        </View>
        <Text style={s.cEngraveAct}>›</Text>
      </View>
      <View style={s.cLedger}>
        <Text style={s.cLedgerT}>반포 · 하이클럽</Text>
        <Text style={s.cLedgerT}>{`멤버 ${club.memberCount}`}</Text>
      </View>
    </Pressable>
  );
}

// ---------- 홈 모듈 (양쪽 공용) ----------
// compact = 보호자 홈의 라이트 행 문법. 러너 홈(RunnerClubCard)은 이 플래그를 넘기지 않으므로
// 나이트 스텁 카드 + 검색창을 그대로 쓴다 — 이 변경의 사정거리는 보호자 홈 하나다.
export function ClubModule({ role, compact }: { role: 'owner' | 'runner'; compact?: boolean }) {
  const [club, reload, clubFailed] = useClubOverview();
  const [board, reloadBoard] = useDemandBoard();
  const reloadAll = () => { reload(); reloadBoard(); };
  // 🔴 검색은 접되 지우지 않는다. `searchClubs`의 진입점은 앱 전체에서 이 ClubSearchBar 하나뿐이고
  // (`/club/[id]`에도, 어떤 클럽 인덱스 라우트에도 검색이 없다 — grep으로 확인), 홈에서 그냥
  // 삭제하면 클럽 탐색이 앱에서 사라진다. 그래서 조용한 행 뒤로 접는다: 기본 화면엔 상자가
  // 없고(⑧의 '상자 0개'), 탭하면 그 자리에서 열린다. 갈 곳 없는 링크를 두는 것보다 정직하다.
  const [findOpen, setFindOpen] = useState(false);
  if (compact) {
    return (
      <View>
        {/* 세 상태: 실데이터 → 행 · 실패(보여줄 값 0) → 라우드 페일 + 재시도 · 로딩 → 침묵 */}
        {club ? (
          <ClubCompactRow club={club} />
        ) : clubFailed ? (
          <View style={s.cFail}>
            <Text style={s.cFailTxt}>클럽 정보를 불러오지 못했어요</Text>
            <Pressable onPress={reload} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
              <Text style={s.cFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
        ) : null}
        <Pressable
          onPress={() => setFindOpen((v) => !v)}
          style={({ pressed }) => [s.cRow, pressed && { backgroundColor: paper.wash }]}
          accessibilityRole="button" accessibilityLabel="동네 클럽 찾기"
        >
          <Text style={[s.cRowT, { flex: 1 }]}>동네 클럽 찾기</Text>
          <Text style={s.cRowAct}>{findOpen ? '닫기' : '›'}</Text>
        </Pressable>
        {findOpen && <View style={{ paddingHorizontal: 15, paddingTop: 10 }}><ClubSearchBar /></View>}
        {board && role === 'owner' && <OwnerDemand board={board} reload={reloadAll} />}
      </View>
    );
  }
  return (
    <View style={{ marginTop: 14 }}>
      {/* [2026-08-19 랩 ⑧] 모듈 헤더 = modh 문법 — 15/800 잉크 타이틀 한 줄. 코랄 1px 상단 룰은
          은퇴(홈의 덩어리 경계는 여백 + 킥커 하나가 만든다). 'HIGH CLUB' 라틴 키커 칩과
          '동네에서 함께 달려요' 서브타이틀은 §3b에서 이미 은퇴. */}
      <Row style={{ marginBottom: 8, alignItems: 'baseline' }}>
        <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink }}>하이클럽</Text>
      </Row>
      <ClubSearchBar />
      {/* 같은 세 상태 — 실데이터 → 배너 · 실패(보여줄 값 0) → 라우드 페일 + 재시도 · 로딩 → 침묵.
          이 arm은 `{club && ...}` 하나여서 실패와 로딩이 똑같이 '아무것도 없음'으로 보였고,
          clubFailed는 여기서 읽히지 않는 값이었다 (review). 러너 홈이 이 arm을 쓴다. */}
      {club ? (
        <ClubBanner club={club} role={role} reload={reloadAll} />
      ) : clubFailed ? (
        <View style={s.cFail}>
          <Text style={s.cFailTxt}>클럽 정보를 불러오지 못했어요</Text>
          <Pressable onPress={reload} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
            <Text style={s.cFailRetry}>다시 시도</Text>
          </Pressable>
        </View>
      ) : null}
      {board && role === 'runner' && <DemandTicket board={board} reload={reloadAll} />}
      {board && role === 'owner' && <OwnerDemand board={board} reload={reloadAll} />}
    </View>
  );
}

// 하위 호환 (기존 삽입 지점)
export function ClubHomeCard({ compact }: { compact?: boolean } = {}) { return <ClubModule role="owner" compact={compact} />; }
export function RunnerClubCard() { return <ClubModule role="runner" />; }

const s = StyleSheet.create({
  // ── compact 행 (보호자 홈) — owner/home.tsx의 s.row와 같은 문법이다.
  // 두 파일에 사는 이유: 홈의 행 스타일은 홈의 것이고, 여기 것은 이 모듈이 어디에 꽂히든
  // 자기 모양을 갖기 위한 것이다. 값이 갈라지면 홈이 정본이다 (거터 15 = layout.gutter).
  cRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 44,
    paddingVertical: 13, paddingHorizontal: 15,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  // 각인 클럽 위젯 — 골드 워시 + 2px 포일 상단 엣지 + 모노그램 + 원장 발치.
  cEngrave: { marginHorizontal: 15, marginTop: 4, marginBottom: 4,
    backgroundColor: '#F4EBD3', borderWidth: 1, borderColor: '#E7DAB6' },
  cFoil: { height: 2, backgroundColor: '#C9AE6A' },
  cEngraveBody: { flexDirection: 'row', alignItems: 'center', gap: 13, paddingHorizontal: 15, paddingVertical: 14 },
  cMono: { width: 42, height: 42, borderWidth: 1.5, borderColor: '#D8C185',
    alignItems: 'center', justifyContent: 'center' },
  cMonoT: { fontSize: 19, fontWeight: '900', color: '#5F4E1C' },
  // 각인 문자 — 위 흰 하이라이트 + 아래 어두운 획으로 종이에 눌린 것처럼. 첫 랩에서 크림 위
  // 크림으로 해 이름이 사라졌던 값(#EFE3C2)은 쓰지 않는다: 읽히지 않는 각인은 각인이 아니다.
  cEngraveT: { fontSize: 20, lineHeight: 26, fontWeight: '900', color: '#5F4E1C',
    textShadowColor: 'rgba(255,255,255,0.95)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 0 },
  // 3.8:1이던 값(#8A7434)을 재서 교체 — 골드 워시 위 서브라인은 눈으로 고르면 항상 미달한다.
  cEngraveSub: { fontSize: 14.5, lineHeight: 20, fontWeight: '600', color: '#6B5720', marginTop: 2 },
  cEngraveAct: { fontSize: 21, color: '#5F4E1C' },
  cLedger: { flexDirection: 'row', justifyContent: 'space-between',
    borderTopWidth: 1, borderTopColor: '#E4D5AE', paddingHorizontal: 15, paddingVertical: 7 },
  cLedgerT: { fontSize: 11, letterSpacing: 1.4, fontWeight: '700', color: '#7C682E' },
  cRowT: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.ink },
  cRowSub: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 1 },
  cRowAct: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.dim },
  // 라우드 페일 — owner/home.tsx의 s.fitFail과 같은 문법 (14/700 critical 잉크 · 텍스트 재시도)
  cFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: 15,
  },
  cFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  cFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // [§3b] 카드·필드 코너 샤프 (radius 0 everywhere) — 클럽 예외는 마진뿐
  searchWrap: { flexDirection: 'row', alignItems: 'center', gap: 9, backgroundColor: lilac.card, borderRadius: 0, borderWidth: 1, borderColor: lilac.hair, paddingHorizontal: 15, paddingVertical: 2, ...lilacShadow, shadowOpacity: 0.06 },
  searchInput: { flex: 1, fontSize: 16, color: lilac.head, paddingVertical: 13 },
  drop: { position: 'absolute', top: 60, left: 0, right: 0, backgroundColor: lilac.card, borderRadius: 0, borderWidth: 1, borderColor: lilac.hair, paddingVertical: 5, ...lilacShadow, shadowOpacity: 0.14, shadowRadius: 18, zIndex: 30 },
  dropRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12, paddingHorizontal: 14 },
  dropThumb: { width: 44, height: 44, borderRadius: 0, backgroundColor: lilac.inset, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  // [§3b 상태칩 문법] 틴트 면 · 무보더 · 샤프 (OPEN/모집 중 상태 태그)
  dropTag: { backgroundColor: VIOLET_TINT, borderRadius: 0, paddingVertical: 4, paddingHorizontal: 9 },

  // ── 하이클럽 나이트 스텁 카드 (Ⓐ② 다크 아일랜드 × Ⓐ④ 시트맵) ──
  // [§3b item 9] 샤프 코너 — 클럽 예외는 '마진'이었지 코너가 아니다 (radius 0, 마진은 셸이 유지)
  clubCard: {
    position: 'relative', backgroundColor: NIGHT, borderWidth: 1, borderColor: NIGHT_EDGE,
    borderRadius: 0, overflow: 'hidden', marginTop: 12,
    shadowColor: '#0B0720', shadowOpacity: 0.42, shadowRadius: 20, shadowOffset: { width: 0, height: 11 }, elevation: 6,
  },
  clubEdge: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },
  clubDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: 'rgba(255,255,255,0.09)', borderRadius: 0 },
  clubRow: { flexDirection: 'row', alignItems: 'stretch' },
  // 스텁 열 — 찢김선(점선)은 tktStub 선례와 동일 문법(단면 borderWidth + borderStyle dashed)
  clubStub: {
    width: 84, paddingVertical: 14, paddingHorizontal: 6, alignItems: 'center', justifyContent: 'center',
    borderRightWidth: 2, borderRightColor: NIGHT_HAIR, borderStyle: 'dashed',
  },
  stubHost: { backgroundColor: '#fff', borderRadius: 0, paddingHorizontal: 7, paddingVertical: 3, marginBottom: 9 }, // [§3b] 샤프
  stubHostText: { fontSize: 10.5, fontWeight: '800', letterSpacing: 1, color: NIGHT },
  // 디스플레이 서체(Black Han Sans) 1회 — 카드에서 가장 값진 자리인 D-day 숫자에만. lineHeight ≥1.2×
  stubNum: { fontSize: 26, lineHeight: 33, fontWeight: '900', color: '#fff', includeFontPadding: false, letterSpacing: -0.3 },
  stubNumSm: { fontSize: 21, lineHeight: 27, fontWeight: '900', color: '#fff', includeFontPadding: false, letterSpacing: -0.3 },
  stubK: { fontSize: 11, lineHeight: 14, fontWeight: '700', letterSpacing: 1.6, color: 'rgba(255,255,255,0.62)', marginTop: 3 },
  stubRsvp: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 8 },
  stubRsvpDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: SEAT_ON },
  stubRsvpText: { fontSize: 11, lineHeight: 14, fontWeight: '700', letterSpacing: 0.9, color: CORAL_READ },
  // 본문 열
  clubMain: { flex: 1, minWidth: 0, paddingHorizontal: 12, paddingTop: 11, paddingBottom: 11 },
  clubIdRow: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  clubMono: { width: 32, height: 32, borderRadius: 0, overflow: 'hidden', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.65)' }, // [§3b] 샤프
  clubMonoText: { fontSize: 17, lineHeight: 22, fontWeight: '900', color: lilac.head, includeFontPadding: false },
  clubKk: { fontSize: 11.5, fontWeight: '700', letterSpacing: 1.3, color: NIGHT_KK, textTransform: 'uppercase', marginBottom: 2 },
  clubName: { fontSize: 18, lineHeight: 23, fontWeight: '900', color: '#fff', letterSpacing: -0.2 },
  clubWhen: { flexDirection: 'row', alignItems: 'baseline', gap: 7, marginTop: 9 },
  clubWhenD: { fontSize: 15.5, lineHeight: 20, fontWeight: '800', color: NIGHT_KK },
  clubWhenT: { fontSize: 21, lineHeight: 26, fontWeight: '800', color: '#fff', letterSpacing: -0.2, fontVariant: ['tabular-nums'] },
  clubSub: { fontSize: 14.5, lineHeight: 20, color: NIGHT_TXT, marginTop: 3 },
  clubLine: { fontSize: 15, lineHeight: 21, color: NIGHT_TXT, marginTop: 9 },
  // 시트맵 — 핍은 랩되고(capacity 4~16+), 큰 정원은 한 단계 축소된다
  clubSeats: { flexDirection: 'row', alignItems: 'center', marginTop: 10 },
  seatGrid: { flex: 1, flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 4 },
  seatPip: { width: 11, height: 11, borderRadius: 3, borderWidth: 1, borderColor: 'rgba(255,255,255,0.38)' },
  seatPipSm: { width: 9, height: 9, borderRadius: 2.5, borderWidth: 1, borderColor: 'rgba(255,255,255,0.38)' },
  seatPipOn: { backgroundColor: SEAT_ON, borderColor: SEAT_ON },
  seatLb: { fontSize: 14.5, lineHeight: 19, fontWeight: '800', color: CORAL_READ, marginLeft: 7 },
  // 고스트 CTA — 나이트 위에선 바이올렛 솔리드가 카드와 싸운다 (lab .a2 .ghost)
  // [§3b] 샤프 · 라벨 16/800 (버튼 라벨 플로어)
  clubGhost: {
    marginTop: 10, borderWidth: 1, borderColor: 'rgba(255,255,255,0.3)', borderRadius: 0,
    backgroundColor: 'rgba(255,255,255,0.06)', paddingVertical: 9, alignItems: 'center', justifyContent: 'center',
  },
  clubGhostText: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: '#fff' },

  // ── 클럽 월드 공통 (바이올렛 라일락) ──
  // [§3b] hcChip('HIGH CLUB' 키커 칩) 은퇴 — 섹션 헤더 단일 문법. 카드·버튼·태그 코너 전부 샤프.
  // R1-A 대기 티켓 (대형 CTA · 라일락)
  tkt: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2, borderRadius: 0, overflow: 'hidden', marginTop: 12, ...lilacShadow },
  tktHolo: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },
  tktStub: { width: 104, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center', borderRightWidth: 2, borderRightColor: 'rgba(255,255,255,.42)', borderStyle: 'dashed' },
  tktCta: { backgroundColor: lilac.accent, borderRadius: 0, alignItems: 'center', paddingVertical: 15, marginTop: 12, shadowColor: lilac.accent, shadowOpacity: 0.32, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 3 },
  // R1-C 스트립 (요청 탭 · 나이트-라일락 아일랜드)
  strip: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: NIGHT, borderRadius: 0, paddingVertical: 15, paddingHorizontal: 16 },
  stripN: { backgroundColor: '#fff', borderRadius: 0, paddingVertical: 6, paddingHorizontal: 12 },
  // D-A 진행 링 + 동네 리그
  demand: { marginTop: 12 },
  prog: { flexDirection: 'row', gap: 16, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderTopLeftRadius: 0, borderTopRightRadius: 0, padding: 16, ...lilacShadow },
  inviteCta: { backgroundColor: lilac.accent, borderRadius: 0, alignSelf: 'flex-start', paddingVertical: 10, paddingHorizontal: 16, marginTop: 10, shadowColor: lilac.accent, shadowOpacity: 0.3, shadowRadius: 8, shadowOffset: { width: 0, height: 3 }, elevation: 2 },
  league: { backgroundColor: lilac.card, borderWidth: 1, borderTopWidth: 0, borderColor: lilac.hair, borderBottomLeftRadius: 0, borderBottomRightRadius: 0, paddingVertical: 13, paddingHorizontal: 14 },
  lrow: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingVertical: 9, paddingHorizontal: 10, borderRadius: 0 },
  lrowMe: { backgroundColor: VIOLET_TINT, borderWidth: 1, borderColor: VIOLET_TINT_EDGE },
});
