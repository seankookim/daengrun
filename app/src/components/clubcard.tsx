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

// 하이클럽 홈 모듈 v4 — 격상 라일락 에디토리얼 카드 (2026-08-03 Sean 2차 디바이스 피드백, PROBLEM 2).
// 다크 풀블리드 포토 배너 + 러버 여권 직인 폐기 → owner-FINAL `.club` 모듈로 구조 교체:
//   흰색 격상 카드(border #DCD6F8·soft violet shadow) · 바이올렛 틴트 헤더(홀로 모노그램·Oswald 킥커·모노 태그)
//   · 다음 세션 요일/시각 + 밋업 서브 · 헤어라인 2셀 메타 · CTA 2개(바이올렛 메인 + 콰이엇 인셋).
// 로직 동결: 훅·페치·핸들러·라우트 타깃(/club/${id}·세션·claim)·게이트·가드 전부 보존. JSX/StyleSheet만 변경.
// 타입 스케일: FIX2 ~1.25× (1.75× 오버슛 철회) — 값·라벨 1줄, 트렁케이션·오버랩 없음.

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
                  : <Text style={{ fontSize: 20 }}>🏃</Text>}
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>{h.name}</Text>
                <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 2 }}>
                  {h.status === 'active' ? `멤버 ${h.memberCount} · 활동 중` : `관심 ${h.interestCount}명 · 모집 중`}
                </Text>
              </View>
              <View style={[s.dropTag, h.status !== 'active' && { backgroundColor: lilac.inset }]}>
                <Text style={{ fontSize: 14, fontWeight: '800', letterSpacing: 0.6, color: h.status === 'active' ? READ_VIOLET : lilac.dim }}>
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

// ---------- 하이클럽 카드 (상태 인지형 · 격상 라일락 에디토리얼 셸) ----------
// owner-FINAL `.club` 모듈 구조: 흰 격상 카드 + 바이올렛 틴트 헤더(홀로 모노그램·킥커·모노 태그) +
// 다음 세션 요일/시각 + 밋업 서브 + 헤어라인 2셀 메타 + CTA 2개. 다크 포토·러버 직인 없음.
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

  // 헤더 모노 태그 — 기존 자리/D-day 상태 로직 유지
  const tagText = active && ns
    ? (joined
      ? `${dday(ns.scheduledAt)} · RSVP ✓`
      : ns.status === 'open' && left > 0
        ? `${left}자리`
        : dday(ns.scheduledAt))
    : club.status === 'collecting'
      ? '모집 중'
      : `멤버 ${club.memberCount}`;

  return (
    <Pressable onPress={onPress} style={s.clubCard}>
      {/* 헤더 행 — 플랫 바이올렛 틴트 + 홀로 모노그램 + 킥커/클럽명 + 모노 태그 */}
      <View style={s.clubTop}>
        <View style={s.clubMono}>
          <HoloSquare id="club-holo" />
          <Text style={[s.clubMonoText, df]}>{initial}</Text>
        </View>
        <View style={{ flex: 1 }}>
          <Text style={s.clubKk} numberOfLines={1}>HIGH CLUB — {club.district}</Text>
          <Text style={s.clubName} numberOfLines={1}>{club.name}</Text>
        </View>
        {club.isHost && (
          <View style={s.hostTag}><Text style={s.hostTagText}>HOST</Text></View>
        )}
        <View style={s.monoTag}><Text style={s.monoTagText} numberOfLines={1}>{tagText}</Text></View>
      </View>

      {/* 바디 — 다음 세션 요일/시각 + 밋업 서브 · 헤어라인 2셀 메타 · CTA 2개 */}
      <View style={s.clubBody}>
        {active && ns ? (
          <View style={s.clubWhen}>
            {dayLabel !== '' && <Text style={[s.clubWhenD, df]}>{dayLabel}</Text>}
            <Text style={s.clubWhenT}>{timeLabel}</Text>
            <Text style={s.clubWhenSub} numberOfLines={1}>
              {ns.meetupPoint}{club.hostName ? ` · 호스트 ${club.hostName}` : ''}
            </Text>
          </View>
        ) : (
          <Text style={s.clubBodyLine} numberOfLines={2}>
            {club.status === 'collecting'
              ? `관심 ${club.interestCount}명 · 호스트를 기다려요`
              : `멤버 ${club.memberCount} · ${club.isHost ? '탭해서 세션을 열어보세요' : '다음 세션 준비 중'}`}
          </Text>
        )}

        {/* 헤어라인 2셀 메타 (기존 필드·dday 헬퍼 바인딩) */}
        <View style={s.clubMeta}>
          {active && ns ? (
            <>
              <View style={s.clubCell}>
                <Text style={s.clubK}>MEMBERS</Text>
                <Text style={s.clubV}>멤버 <Text style={s.clubNum}>{club.memberCount}</Text>명</Text>
              </View>
              <View style={[s.clubCell, s.clubCellDiv]}>
                <Text style={s.clubK}>NEXT</Text>
                <Text style={s.clubV}><Text style={s.clubNum}>{dday(ns.scheduledAt)}</Text></Text>
              </View>
            </>
          ) : club.status === 'collecting' ? (
            <>
              <View style={s.clubCell}>
                <Text style={s.clubK}>INTEREST</Text>
                <Text style={s.clubV}>관심 <Text style={s.clubNum}>{club.interestCount}</Text>명</Text>
              </View>
              <View style={[s.clubCell, s.clubCellDiv]}>
                <Text style={s.clubK}>MEMBERS</Text>
                <Text style={s.clubV}>멤버 <Text style={s.clubNum}>{club.memberCount}</Text>명</Text>
              </View>
            </>
          ) : (
            <>
              <View style={s.clubCell}>
                <Text style={s.clubK}>MEMBERS</Text>
                <Text style={s.clubV}>멤버 <Text style={s.clubNum}>{club.memberCount}</Text>명</Text>
              </View>
              <View style={[s.clubCell, s.clubCellDiv]}>
                <Text style={s.clubK}>HOST</Text>
                <Text style={s.clubV} numberOfLines={1}>{club.hostName ?? '준비 중'}</Text>
              </View>
            </>
          )}
        </View>

        {/* CTA 하나 — 문은 클럽 홈뿐 (Sean 3차: 두 버튼의 차이가 불명확 → 홈이 모든 갈래를 가진다) */}
        <View style={s.clubCta}>
          <Pressable onPress={onPress} style={s.ctaMain}>
            <Text style={s.ctaMainText}>클럽 홈 ›</Text>
          </Pressable>
        </View>
      </View>

      {/* 이너 이중-프레임 헤어라인 (히어로 카드 법) */}
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
        .then(() => { Alert.alert('호스트가 됐어요 🏁', '클럽 페이지에서 첫 세션을 열어보세요'); reload(); })
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
        <Pressable onPress={claim} style={s.tktCta}>
          <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff' }}>🏁 호스트 되기</Text>
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
            <Text style={{ fontSize: 15, fontWeight: '800', color: lilac.head }}>{mine.district} 하이클럽, 열리는 중</Text>
            <Text style={{ fontSize: 14, color: lilac.text, marginTop: 5, lineHeight: 19 }}>
              {mine.threshold}팀이 모이면 호스트 모집 시작 — 이웃을 초대할수록 빨리 열려요.
            </Text>
            <Pressable onPress={invite} style={s.inviteCta}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: '#fff' }}>🐾 이웃 초대하기</Text>
            </Pressable>
          </View>
        </View>
      )}
      {league.length > 0 && (
        <View style={[s.league, !collecting && { borderTopWidth: 1, borderTopLeftRadius: lilacRadius.card, borderTopRightRadius: lilacRadius.card }]}>
          <Text style={{ fontSize: 14, fontWeight: '800', letterSpacing: 1, color: READ_VIOLET, marginBottom: 8 }}>동네 리그 — 이번 달</Text>
          {league.map((l, i) => (
            <Pressable key={l.clubId} onPress={() => router.push(`/club/${l.clubId}`)} style={[s.lrow, l.mine && s.lrowMe]}>
              <Text style={{ fontSize: 14 }}>{l.status === 'active' ? (i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : '🏃') : '⏳'}</Text>
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

// ---------- 홈 모듈 (양쪽 공용) ----------
export function ClubModule({ role }: { role: 'owner' | 'runner' }) {
  const [club, reload] = useClubOverview();
  const [board, reloadBoard] = useDemandBoard();
  const reloadAll = () => { reload(); reloadBoard(); };
  return (
    <View style={{ marginTop: 14 }}>
      <Row style={{ gap: 8, marginBottom: 11, alignItems: 'center' }}>
        <Text style={{ fontSize: 16.5, fontWeight: '800', color: lilac.head }}>하이클럽</Text>
        <View style={s.hcChip}><Text style={{ fontSize: 11, fontWeight: '800', letterSpacing: 1, color: READ_VIOLET }}>HIGH CLUB</Text></View>
        <Text style={{ fontSize: 14, color: lilac.dim }}>동네에서 함께 달려요</Text>
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
  searchInput: { flex: 1, fontSize: 16, color: lilac.head, paddingVertical: 13 },
  drop: { position: 'absolute', top: 60, left: 0, right: 0, backgroundColor: lilac.card, borderRadius: 14, borderWidth: 1, borderColor: lilac.hair, paddingVertical: 5, ...lilacShadow, shadowOpacity: 0.14, shadowRadius: 18, zIndex: 30 },
  dropRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12, paddingHorizontal: 14 },
  dropThumb: { width: 44, height: 44, borderRadius: 11, backgroundColor: lilac.inset, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  dropTag: { backgroundColor: VIOLET_TINT, borderWidth: 1, borderColor: VIOLET_TINT_EDGE, borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9 },

  // ── 하이클럽 격상 카드 (흰 카드 · 바이올렛 틴트 헤더 · 홀로 모노그램 · CTA 2개) ──
  clubCard: {
    position: 'relative', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#DCD6F8',
    borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 12,
    shadowColor: '#6C5CE7', shadowOpacity: 0.14, shadowRadius: 15, shadowOffset: { width: 0, height: 8 }, elevation: 4,
  },
  clubDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner },
  // 헤더 행 — 틴트 그라디언트 + 하단 헤어라인
  clubTop: { position: 'relative', flexDirection: 'row', alignItems: 'center', gap: 9, paddingHorizontal: 12, paddingVertical: 11, backgroundColor: VIOLET_TINT, borderBottomWidth: 1, borderBottomColor: '#E0D9FA' },
  clubMono: { width: 32, height: 32, borderRadius: 6, overflow: 'hidden', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.7)' },
  clubMonoText: { fontSize: 17, color: lilac.head, includeFontPadding: false },
  clubKk: { fontSize: 12, fontWeight: '700', letterSpacing: 1.3, color: lilac.accent, textTransform: 'uppercase', marginBottom: 2 },
  clubName: { fontSize: 17, fontWeight: '800', color: lilac.head, letterSpacing: -0.2 },
  hostTag: { borderWidth: 1, borderColor: VIOLET_TINT_EDGE, backgroundColor: lilac.accent, borderRadius: lilacRadius.tag, paddingHorizontal: 6, paddingVertical: 3 },
  hostTagText: { fontSize: 10, fontWeight: '800', letterSpacing: 1, color: '#fff' },
  monoTag: { borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: lilac.card, borderRadius: lilacRadius.tag, paddingHorizontal: 7, paddingVertical: 3 },
  monoTagText: { fontSize: 11, fontWeight: '700', letterSpacing: 0.8, color: READ_VIOLET, textTransform: 'uppercase' },
  // 바디
  clubBody: { position: 'relative', paddingHorizontal: 12, paddingTop: 11, paddingBottom: 12 },
  clubWhen: { flexDirection: 'row', alignItems: 'baseline', gap: 7 },
  clubWhenD: { fontSize: 18, color: lilac.accent, includeFontPadding: false },
  clubWhenT: { fontSize: 18, fontWeight: '700', color: lilac.head, fontVariant: ['tabular-nums'] },
  clubWhenSub: { flex: 1, fontSize: 14, color: lilac.dim },
  clubBodyLine: { fontSize: 14, color: lilac.text, lineHeight: 20 },
  clubMeta: { flexDirection: 'row', marginTop: 10, borderTopWidth: 1, borderTopColor: lilac.hair2, paddingTop: 9 },
  clubCell: { flex: 1 },
  clubCellDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2, paddingLeft: 10 },
  clubK: { fontSize: 11.5, fontWeight: '600', letterSpacing: 1, color: lilac.dim, textTransform: 'uppercase', marginBottom: 3 },
  clubV: { fontSize: 14, fontWeight: '700', color: lilac.head },
  clubNum: { fontSize: 15.5, fontWeight: '800', color: lilac.head, fontVariant: ['tabular-nums'] },
  clubCta: { flexDirection: 'row', gap: 8, marginTop: 11 },
  ctaMain: { flex: 1, backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, paddingVertical: 12, alignItems: 'center', justifyContent: 'center', shadowColor: lilac.accent, shadowOpacity: 0.3, shadowRadius: 13, shadowOffset: { width: 0, height: 5 }, elevation: 3 },
  ctaMainText: { fontSize: 14.5, fontWeight: '800', color: '#fff' },
  ctaQuiet: { flex: 1, borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset, borderRadius: lilacRadius.btn, paddingVertical: 12, alignItems: 'center', justifyContent: 'center' },
  ctaQuietText: { fontSize: 14.5, fontWeight: '700', color: lilac.head },

  // ── 클럽 월드 공통 (바이올렛 라일락) ──
  hcChip: { backgroundColor: VIOLET_TINT, borderWidth: 1, borderColor: VIOLET_TINT_EDGE, borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9 },
  // R1-A 대기 티켓 (대형 CTA · 라일락)
  tkt: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 12, ...lilacShadow },
  tktHolo: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },
  tktStub: { width: 104, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center', borderRightWidth: 2, borderRightColor: 'rgba(255,255,255,.42)', borderStyle: 'dashed' },
  tktCta: { backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 15, marginTop: 12, shadowColor: lilac.accent, shadowOpacity: 0.32, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 3 },
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
