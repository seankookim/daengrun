import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Pressable, RefreshControl, ScrollView, StyleProp, StyleSheet, Text, TextInput, View, ViewStyle } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { TabSwipe } from '../src/components/tabswipe';
import { HeatTrace } from '../src/components/runcard';
import { Avatar, Icon, Row } from '../src/components/ui';
import { MediaImage } from '../src/lib/media';
import {
  addComment, deleteFeedPost, fetchComments, fetchFeed, fetchMyProfile, fetchRecentReviews,
  FeedComment, FeedPost, MyProfile, PublicReview, toggleFeedLike,
} from '../src/lib/api';
import { useClubOverview } from '../src/components/clubcard';
import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { haptic } from '../src/lib/haptics';
import { CollarKey, collarColors, lilac, paper } from '../src/theme';

// 동네 피드 — IG 카드 해부학 개편 (Sean 2026-08-11: "인스타 UI에서 영감 — 쉽게 올리고 스크롤하고
// 반응하고 공유하게"). 인스타에서 가져온 건 비주얼이 아니라 카드의 스캔 리듬:
//   ① 아이덴티티 헤더(아바타·이름·강아지 + 내 포스트면 ⋯ 오버플로) → ② 콘텐츠 블록 엣지-투-엣지
//   (사진 풀블리드 / 기록 조판 / 클럽 리캡) → ③ 액션 행(발자국·댓글, 44pt 타깃, 낙관적 갱신+롤백)
//   → ④ 캡션 → ⑤ 타임스탬프. 포스트 사이 = 풀블리드 코랄 헤어라인 (카드-인-카드 은퇴).
// 미이식 IG 어포던스(백엔드 부재 — 죽은 버튼 금지): 공유/DM · 북마크 · 팔로우 · 스토리 · 캐러셀.
// 직행 포스트: 상단 컴포즈 바 → /compose (실제 전제조건 = 완료된 러닝, shareRunToFeed).
// 삭제는 ⋯ → Alert 확정으로 이동 — '길게 눌러 삭제' 상시 힌트 은퇴.
// 액센트 예산: 코랄 = 포스트 구분선 · 누른 발자국 · 컴포즈 버튼 보더 · 보내기.
// 포일 예산: 홀로 = 클럽 배너 상하 엣지 + 마스트헤드 모노그램만 · 골드 = 기록 소인 화면당 1개.
// 로딩 ≠ 빈 피드 ≠ 에러 — 3상태 분리 (에러는 criticalWash 라우드-페일 스트립 + 재시도).

const W = Dimensions.get('window').width;
const GUTTER = 13;

// 홀로 포일 스톱 (그라디언트 라이브러리 부재 — 세그먼트 View로 근사)
const HOLO = ['#CFC4FF', '#FFD9CB', '#F3E9C6', '#CDEBDD', '#CFE0FF', '#CFC4FF'];
// 코랄 텍스트 법: 흰 글자는 어두워진 종단 스톱(≥ #C6472C)에서만 4.5:1 통과
const CORAL_INK = '#C6472C';

// 기록 소인(골드) — 화면당 1개. SETTLED 필드가 원본에 없으므로 실데이터인 마일스톤 배지에 바인딩.
const isMilestone = (b: string) => b.includes('최고') || b.includes('기록') || b.includes('PB');

const fmtDur = (sec?: number) => (sec ? `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}` : null);
// [V4] 스트라바식 페이스 — km+시간에서 파생 (실데이터만)
const fmtPace = (km?: number, sec?: number) => {
  if (!km || !sec || km <= 0) return null;
  const s = Math.round(sec / km);
  return `${Math.floor(s / 60)}'${String(s % 60).padStart(2, '0')}"`;
};

// 홀로 엣지 — 세그먼트 View 근사 (foil rule: 클럽 배너 상하 + 모노그램 + 리캡 좌측만)
function HoloEdge({ vertical, style }: { vertical?: boolean; style?: StyleProp<ViewStyle> }) {
  return (
    <View style={[{ flexDirection: vertical ? 'column' : 'row', overflow: 'hidden' }, style]}>
      {HOLO.map((c, i) => <View key={i} style={{ flex: 1, backgroundColor: c }} />)}
    </View>
  );
}

// 더블탭 발자국 버스트 — 원샷 오버레이 (IG 하트 문법의 도그스하이 번역)
function PawBurst({ trigger }: { trigger: number }) {
  const scale = useRef(new Animated.Value(0)).current;
  const opacity = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (trigger === 0) return;
    scale.setValue(0.4);
    opacity.setValue(0);
    Animated.parallel([
      Animated.spring(scale, { toValue: 1, useNativeDriver: true, friction: 4 }),
      Animated.sequence([
        Animated.timing(opacity, { toValue: 1, duration: 90, useNativeDriver: true }),
        Animated.delay(420),
        Animated.timing(opacity, { toValue: 0, duration: 260, useNativeDriver: true }),
      ]),
    ]).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trigger]);
  if (trigger === 0) return null;
  return (
    <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { alignItems: 'center', justifyContent: 'center', opacity, transform: [{ scale }] }]}>
      <Icon name="PawPrint" glyph="●" size={84} color={CORAL_INK} />
    </Animated.View>
  );
}

export default function Community() {
  const df = useDisplayFont();
  const nf = useNumFont(); // [V4] 스탯 = Oswald
  const [club] = useClubOverview(); // 하이클럽 스트립 (P-A S1)
  const [posts, setPosts] = useState<FeedPost[]>([]);
  // 탭: 피드(실) | 러너 후기(실 공개 리뷰). 챌린지는 실시스템 생기면 추가 — 가짜 탭 금지.
  const [tab, setTab] = useState<'feed' | 'reviews'>('feed');
  const [reviews, setReviews] = useState<PublicReview[] | null>(null);
  useEffect(() => {
    if (tab === 'reviews' && reviews == null) {
      fetchRecentReviews().then(setReviews).catch(() => setReviews([]));
    }
  }, [tab, reviews]);
  const [loaded, setLoaded] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [feedError, setFeedError] = useState<string | null>(null);
  // 컴포즈 바의 내 아바타 — 실프로필 (없으면 모노그램 폴백)
  const [me, setMe] = useState<MyProfile | null>(null);
  useEffect(() => { fetchMyProfile().then(setMe).catch(() => {}); }, []);

  const load = () => fetchFeed()
    .then((p) => { setPosts(p); setFeedError(null); setLoaded(true); })
    .catch((e) => { setFeedError(e?.message ?? '피드를 불러오지 못했어요'); setLoaded(true); });
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const setLiked = (p: FeedPost, liked: boolean) => {
    if (p.likedByMe === liked) return;
    haptic('light'); // 즉시 촉각 피드백 — 낙관적 카운트 갱신과 동시 (<100ms)
    setPosts((cur) => cur.map((x) => (x.id === p.id
      ? { ...x, likedByMe: liked, likes: p.likes + (liked ? 1 : -1) }
      : x)));
    // 낙관적 반영 — 실패 시 해당 포스트만 원상 롤백 (전체 리로드로 화면을 흔들지 않는다)
    toggleFeedLike(p.id, p.likedByMe).catch(() => {
      setPosts((cur) => cur.map((x) => (x.id === p.id
        ? { ...x, likedByMe: p.likedByMe, likes: p.likes }
        : x)));
    });
  };

  // 더블탭 — IG 문법: 더블탭은 항상 '좋아요' (해제는 액션 버튼으로만)
  const lastTap = useRef<Record<string, number>>({});
  const [bursts, setBursts] = useState<Record<string, number>>({});
  const onPhotoTap = (p: FeedPost) => {
    const now = Date.now();
    if (now - (lastTap.current[p.id] ?? 0) < 300) {
      setBursts((b) => ({ ...b, [p.id]: (b[p.id] ?? 0) + 1 }));
      setLiked(p, true);
      lastTap.current[p.id] = 0;
    } else {
      lastTap.current[p.id] = now;
    }
  };

  // 댓글 — 포스트당 인라인 펼침
  const [openComments, setOpenComments] = useState<string | null>(null);
  const [comments, setComments] = useState<FeedComment[]>([]);
  const [commentInput, setCommentInput] = useState('');
  const [sending, setSending] = useState(false);
  // [honesty 2026-08-11] 댓글 로드 실패가 "첫 댓글을 남겨보세요"로 분장하던 것 —
  // 로딩/실패/실빈 3상태 분리 + 재시도.
  const [commentsLoaded, setCommentsLoaded] = useState(false);
  const [commentsErr, setCommentsErr] = useState(false);

  const loadComments = (postId: string) => {
    setCommentsErr(false);
    setCommentsLoaded(false);
    fetchComments(postId)
      .then((cs) => { setComments(cs); setCommentsLoaded(true); })
      .catch(() => setCommentsErr(true));
  };
  const toggleComments = (p: FeedPost) => {
    if (openComments === p.id) { setOpenComments(null); return; }
    setOpenComments(p.id);
    setComments([]);
    loadComments(p.id);
  };

  const submitComment = async (postId: string) => {
    const body = commentInput.trim();
    if (!body || sending) return;
    setSending(true);
    setCommentInput('');
    try {
      await addComment(postId, body);
      setComments(await fetchComments(postId));
      setPosts((cur) => cur.map((x) => (x.id === postId ? { ...x, commentCount: x.commentCount + 1 } : x)));
    } catch (e) {
      Alert.alert('댓글 실패', (e as Error).message);
      setCommentInput(body);
    } finally {
      setSending(false);
    }
  };

  const remove = (p: FeedPost) => {
    if (!p.mine) return;
    Alert.alert('포스트 삭제', '피드에서 이 러닝을 내릴까요?', [
      { text: '취소', style: 'cancel' },
      { text: '삭제', style: 'destructive', onPress: () => deleteFeedPost(p.id).then(load).catch((e) => Alert.alert('삭제 실패', (e as Error).message)) },
    ]);
  };

  // 골드 소인 — 화면당 1개(scarce). 마일스톤 배지가 있는 첫 포스트에만 찍힘.
  const sealPostId = posts.find((p) => (p.meta.badges ?? []).some(isMilestone))?.id;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>{/* [페이퍼 크롬 2026-08-10] 라일락 캔버스 은퇴 → 백지 */}
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: 56, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={lilac.accent} />}
      >
        {/* ───────── 마스트헤드 ───────── */}
        <View style={{ paddingHorizontal: GUTTER + 2 }}>
          {/* 판권 키커: 모노그램 + 지면명 + 룰 (제 128호·갱신 시각은 날조 데이터 — 미이식) */}
          <Row style={{ alignItems: 'center', gap: 8, marginBottom: 9 }}>
            <View style={s.mono}>
              <HoloEdge style={StyleSheet.absoluteFill} />
              <Text style={[s.monoTxt, nf]}>D</Text>
            </View>
            <Text style={s.kickerLabel}>동네 신문</Text>
            <View style={s.kickerRule} />
          </Row>

          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start', gap: 10 }}>
            <View style={{ flex: 1 }}>
              <Row style={{ gap: 8, alignItems: 'center' }}>
                <Text style={[s.h1, df]}>동네 피드</Text>
                <View style={s.liveBadge}>
                  <View style={s.liveDot} />
                  <Text style={[s.liveTxt, nf]}>LIVE</Text>
                </View>
              </Row>
              <Text style={s.lede}>우리 동네 강아지들의 오늘 러닝. 완료된 러닝이 그대로 지면이 됩니다.</Text>
            </View>
            <Pressable onPress={() => router.push('/leaderboard')} style={s.rankBtn}>
              <Text style={[s.rankTxt, nf]}>랭킹</Text>
            </Pressable>
          </Row>
        </View>

        {/* ───────── 하이클럽 스트립 (P-A S1) — 홀로 엣지 배너, 탭 = 클럽 홈 ───────── */}
        {club && (
          <Pressable onPress={() => router.push(`/club/${club.id}`)} style={s.clubStrip}>
            {club.photoUrl && <Image source={{ uri: club.photoUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />}
            <View style={s.clubScrim} />
            <Row style={{ justifyContent: 'space-between', alignItems: 'flex-end', flex: 1, padding: 10, zIndex: 2 }}>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.clubKick}>HIGH CLUB</Text>
                <Text style={s.clubName} numberOfLines={1}>{club.name}</Text>
              </View>
              <View style={s.clubPill}>
                <Text style={s.clubPillN}>
                  {club.status === 'active'
                    ? club.nextSession
                      ? `${club.nextSession.when.split(' ').slice(-2).join(' ')} · ${Math.max(0, club.nextSession.capacity - club.nextSession.rsvpCount)}자리`
                      : `멤버 ${club.memberCount}`
                    : `관심 ${club.interestCount}명 — 나도 관심 ›`}
                </Text>
                <Text style={s.clubGo}>클럽 홈 ›</Text>
              </View>
            </Row>
            <HoloEdge style={s.holoTop} />
            <HoloEdge style={s.holoBottom} />
          </Pressable>
        )}

        {/* ───────── 섹션 탭 — 피드 | 러너 후기 ───────── */}
        <Row style={{ marginTop: 14, paddingHorizontal: GUTTER + 2, gap: 20, borderBottomWidth: 1, borderBottomColor: paper.line }}>{/* [페이퍼 크롬] 섹션 분리 = 풀블리드 코랄 1px */}
          {([['feed', '피드'], ['reviews', '러너 후기']] as const).map(([k, label]) => {
            const count = k === 'feed' ? posts.length : reviews?.length;
            return (
              <Pressable key={k} onPress={() => setTab(k)} style={{ paddingBottom: 9, borderBottomWidth: 2, borderBottomColor: tab === k ? lilac.head : 'transparent', marginBottom: -1, flexDirection: 'row', alignItems: 'baseline', gap: 5 }}>
                <Text style={{ fontSize: 15, fontWeight: '700', color: tab === k ? lilac.head : lilac.dim }}>{label}</Text>
                {count != null && (
                  <Text style={[s.tabCount, nf, { color: tab === k ? lilac.accent : lilac.dim }]}>{String(count).padStart(2, '0')}</Text>
                )}
              </Pressable>
            );
          })}
        </Row>

        {/* ───────── 러너 후기 탭 — 실 공개 리뷰 ───────── */}
        {tab === 'reviews' && (
          <View style={{ paddingHorizontal: GUTTER, marginTop: 12, gap: 11 }}>
            {reviews == null && <Text style={{ fontSize: 14, color: lilac.dim, textAlign: 'center', marginTop: 30 }}>불러오는 중...</Text>}
            {reviews != null && reviews.length === 0 && (
              <View style={s.revCard}>
                <Text style={{ fontSize: 14.5, color: lilac.dim, textAlign: 'center', lineHeight: 22 }}>
                  아직 공개 후기가 없어요{'\n'}러닝이 끝나면 첫 후기를 남겨보세요
                </Text>
              </View>
            )}
            {(reviews ?? []).map((rv, i) => (
              <View key={i} style={s.revCard}>
                <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head }}>{rv.runnerName} 러너</Text>
                  <Text style={[s.stamp, nf]}>{rv.when}</Text>
                </Row>
                {rv.rating != null && (
                  <Text style={{ fontSize: 14, color: lilac.amber, marginTop: 5, letterSpacing: 2 }}>{'★'.repeat(rv.rating)}{'☆'.repeat(Math.max(0, 5 - rv.rating))}</Text>
                )}
                {!!rv.note && <Text style={{ fontSize: 14, color: lilac.text, marginTop: 6, lineHeight: 21 }}>{rv.note}</Text>}
                {rv.tags.length > 0 && (
                  <Row style={{ gap: 5, marginTop: 8, flexWrap: 'wrap' }}>
                    {rv.tags.map((t) => (
                      <View key={t} style={s.monoTag}><Text style={s.monoTagTxt}>{t}</Text></View>
                    ))}
                  </Row>
                )}
              </View>
            ))}
          </View>
        )}

        {/* ───────── 컴포즈 바 — 피드 직행 포스트 진입 (IG 문법: 아바타 + 플레이스홀더 + 버튼).
            탭하면 /compose — 실제 공유 플로우(완료 러닝 픽커 + 캡션 + shareRunToFeed) ───────── */}
        {tab === 'feed' && (
          <Pressable
            onPress={() => router.push('/compose')}
            style={({ pressed }) => [s.composeBar, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button"
            accessibilityLabel="피드에 자랑하기"
          >
            <Avatar url={me?.avatarUrl} char={(me?.name ?? '나')[0]} bg={lilac.accent} size={34} />
            <Text style={s.composePh} numberOfLines={1}>오늘 러닝 자랑하기...</Text>
            <View style={s.composeGo}><Text style={s.composeGoTxt}>올리기</Text></View>
          </Pressable>
        )}

        {/* ───────── 피드 — 로딩 ≠ 에러 ≠ 빈 피드 (3상태 정직 분리) ───────── */}
        {tab === 'feed' && !loaded && (
          <Text style={{ fontSize: 14, color: lilac.dim, textAlign: 'center', marginTop: 30 }}>피드 불러오는 중...</Text>
        )}
        {tab === 'feed' && loaded && feedError != null && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>피드를 불러오지 못했어요</Text>
            <Text style={{ fontSize: 14, color: paper.critical, marginTop: 3 }} numberOfLines={2}>{feedError}</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {tab === 'feed' && loaded && feedError == null && posts.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: lilac.head, textAlign: 'center' }}>아직 포스트가 없어요</Text>
            <Text style={{ fontSize: 14, color: lilac.dim, textAlign: 'center', marginTop: 6, lineHeight: 22 }}>
              러닝을 완료하고 위의 '올리기'로 자랑해보세요{'\n'}첫 포스트의 주인공이 되어주세요
            </Text>
          </View>
        )}

        {tab === 'feed' && posts.map((p) => (
          <View key={p.id} style={s.post}>
            {/* ── ① 아이덴티티 헤더 (IG 문법) — 아바타 + 이름·강아지 + 내 포스트면 ⋯ 오버플로.
                타임스탬프는 카드 바닥(⑤)으로 — 상시 '길게 눌러 삭제' 힌트는 은퇴, 삭제는 ⋯ → Alert */}
            <Row style={{ gap: 9, paddingHorizontal: GUTTER + 2, paddingTop: 11, paddingBottom: 9, alignItems: 'center' }}>
              <Avatar url={p.authorAvatar} char={p.authorName[0]} bg={lilac.accent} size={34} />
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head }} numberOfLines={1}>{p.authorName}</Text>
                {p.meta.dogName && (
                  <Row style={{ gap: 5, marginTop: 2, alignItems: 'center' }}>
                    {p.meta.collar && collarColors[p.meta.collar as CollarKey] && (
                      <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: collarColors[p.meta.collar as CollarKey] }} />
                    )}
                    <Text style={{ fontSize: 14, color: lilac.text }} numberOfLines={1}>{p.meta.dogName}와 함께</Text>
                  </Row>
                )}
              </View>
              {p.mine && (
                <Pressable
                  onPress={() => remove(p)}
                  style={s.more}
                  hitSlop={8}
                  accessibilityRole="button"
                  accessibilityLabel="내 포스트 관리"
                >
                  <Text style={{ fontSize: 17, fontWeight: '700', color: lilac.dim, letterSpacing: 1, lineHeight: 21 }}>⋯</Text>
                </Pressable>
              )}
            </Row>

            {/* ── 클럽 리캡 자동 포스트 = 밤의 창 (나이트 라일락 #1C1837) */}
            {p.meta.club ? (
              <Pressable onPress={() => p.meta.sessionId && router.push(`/club/session/${p.meta.sessionId}`)}>
                <View style={s.recapCard}>
                  <HoloEdge vertical style={s.recapEdge} />
                  <Text style={s.recapKick}>HIGH CLUB — RECAP</Text>
                  <Text style={{ fontSize: 18, fontWeight: '700', color: '#fff', marginTop: 7, letterSpacing: -0.2 }}>{p.meta.club}</Text>
                  <Row style={{ marginTop: 10, borderTopWidth: 1, borderTopColor: 'rgba(207,196,255,.22)', paddingTop: 9 }}>
                    <View style={s.recapNumCell}><Text style={[s.recapNum, nf]}>{p.meta.teams}</Text><Text style={s.recapK}>TEAMS</Text></View>
                    {(p.meta.dogs ?? 0) > 0 && <View style={[s.recapNumCell, s.recapDiv]}><Text style={[s.recapNum, nf]}>{p.meta.dogs}</Text><Text style={s.recapK}>DOGS</Text></View>}
                    <View style={[s.recapNumCell, s.recapDiv]}><Text style={[s.recapNum, nf]}>✓</Text><Text style={s.recapK}>FINISHED</Text></View>
                  </Row>
                  <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 10 }}>탭해서 세션 리캡 보기 <Text style={{ color: '#CFC4FF', fontWeight: '700' }}>›</Text></Text>
                  <PawBurst trigger={bursts[p.id] ?? 0} />
                </View>
              </Pressable>
            ) : p.photoUrl ? (
              <>
                {/* 사진 = 본문 (콘텐츠 유지) */}
                <Pressable onPress={() => onPhotoTap(p)}>
                  <View style={s.photoWrap}>
                    {/* [0064] 피드 사진 = 공유된 러닝 사진 — 새 포스트는 media 경로라 서명이 필요.
                        [IG 개편] 엣지-투-엣지 풀블리드 — 카드 인셋 은퇴, 사진이 화면 폭 전체 */}
                    <MediaImage source={p.photoUrl} style={{ width: W, height: W, backgroundColor: lilac.inset }} resizeMode="cover" />
                    {(p.meta.badges ?? []).length > 0 && (
                      <View pointerEvents="none" style={s.badgeCol}>
                        {(p.meta.badges ?? []).map((b) => (
                          <View key={b} style={s.badge}><Text style={s.badgeTxt}>{b}</Text></View>
                        ))}
                      </View>
                    )}
                    {/* 기록 소인 — 화면당 1개 */}
                    {sealPostId === p.id && (
                      <View pointerEvents="none" style={s.seal}>
                        <Text style={s.sealB}>기록</Text>
                        <Text style={[s.sealS, nf]}>RECORD</Text>
                      </View>
                    )}
                    <PawBurst trigger={bursts[p.id] ?? 0} />
                  </View>
                </Pressable>
                {/* 하이라인 스탯 표 (스크림 오버레이 → 편집 조판으로 이동) */}
                {(p.meta.km != null || fmtDur(p.meta.durationSec)) && (
                  <Row style={s.statTable}>
                    <View style={s.statCell}>
                      <Text style={s.statK}>KM</Text><Text style={[s.statV, nf]}>{p.meta.km ?? '—'}</Text>
                    </View>
                    {fmtPace(p.meta.km, p.meta.durationSec) && (
                      <View style={[s.statCell, s.statDiv]}>
                        <Text style={s.statK}>PACE</Text><Text style={[s.statV, nf]}>{fmtPace(p.meta.km, p.meta.durationSec)}</Text>
                      </View>
                    )}
                    {fmtDur(p.meta.durationSec) && (
                      <View style={[s.statCell, s.statDiv]}>
                        <Text style={s.statK}>TIME</Text><Text style={[s.statV, nf]}>{fmtDur(p.meta.durationSec)}</Text>
                      </View>
                    )}
                  </Row>
                )}
              </>
            ) : (
              // 사진 없는 포스트 = 기록 조판 블록 (구 볼트 카드 → 라일락 인셋 리페인트)
              <Pressable onPress={() => onPhotoTap(p)}>
                <View style={s.record}>
                  <View style={{ flex: 1 }}>
                    <Text style={[s.recordKm, nf]}>
                      {p.meta.km != null ? p.meta.km : '—'}<Text style={{ fontSize: 14, color: lilac.text, letterSpacing: 0 }}> km</Text>
                    </Text>
                    {fmtPace(p.meta.km, p.meta.durationSec) && (
                      <Text style={[s.recordPace, nf]}>{fmtPace(p.meta.km, p.meta.durationSec)} / KM</Text>
                    )}
                    {p.meta.dogName && (
                      <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head, marginTop: 5 }}>{p.meta.dogName} 완주</Text>
                    )}
                    {fmtDur(p.meta.durationSec) && (
                      <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.text, marginTop: 4 }}><Text style={[{ fontSize: 14, color: lilac.head }, nf]}>{fmtDur(p.meta.durationSec)}</Text></Text>
                    )}
                    <Row style={{ gap: 4, marginTop: 8, flexWrap: 'wrap' }}>
                      {(p.meta.badges ?? []).map((b) => (
                        <View key={b} style={isMilestone(b) ? s.voltTag : s.monoTag}>
                          <Text style={isMilestone(b) ? s.voltTagTxt : s.monoTagTxt}>{b}</Text>
                        </View>
                      ))}
                    </Row>
                  </View>
                  {(p.meta.trace ?? []).length > 1 ? (
                    <View style={s.traceBox}>
                      {/* 칼라 컬러 트레이스 (0033) — 강아지의 색으로 달린 길 */}
                      <HeatTrace
                        points={(p.meta.trace ?? []).map((pt) => ({ ...pt, v: 0.65 }))}
                        width={92} height={104}
                        tint={p.meta.collar ? collarColors[p.meta.collar as CollarKey] : undefined}
                      />
                    </View>
                  ) : (
                    <View style={{ alignSelf: 'center', opacity: 0.4 }}><Icon name="PawPrint" glyph="●" size={38} color={lilac.dim} /></View>
                  )}
                  <PawBurst trigger={bursts[p.id] ?? 0} />
                </View>
              </Pressable>
            )}

            {/* ── ③ 액션 행 — 콘텐츠 직하, 좌측 정렬, 44pt 타깃 · scale 0.96 프레스 ·
                낙관적 카운트 (누른 발자국 = 코랄 단일 신호) */}
            <Row style={{ paddingHorizontal: GUTTER + 2 - 8, alignItems: 'center' }}>
              <Pressable
                onPress={() => setLiked(p, !p.likedByMe)}
                style={({ pressed }) => [s.act, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                accessibilityRole="button"
                accessibilityLabel="발자국"
                accessibilityState={{ selected: p.likedByMe }}
              >
                <Icon name="PawPrint" glyph="●" size={17} color={p.likedByMe ? CORAL_INK : lilac.dim} />
                <Text style={[s.actNum, p.likedByMe && s.actNumOn, nf]}>{p.likes}</Text>
                <Text style={[s.actLabel, p.likedByMe && s.actLabelOn]}>발자국</Text>
              </Pressable>
              <Pressable
                onPress={() => toggleComments(p)}
                style={({ pressed }) => [s.act, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                accessibilityRole="button"
                accessibilityLabel="댓글"
              >
                <Icon name="MessageCircle" glyph="○" size={16} color={lilac.dim} />
                <Text style={[s.actNum, nf]}>{p.commentCount}</Text>
                <Text style={s.actLabel}>댓글</Text>
              </Pressable>
            </Row>

            {/* ── ④ 캡션 (볼드 작성자 + 본문) → ⑤ 타임스탬프 */}
            <View style={{ paddingHorizontal: GUTTER + 2 }}>
              {p.body && (
                <Text style={{ fontSize: 14, color: lilac.text, lineHeight: 21, marginTop: 1 }}>
                  <Text style={{ fontWeight: '700', color: lilac.head }}>{p.authorName}</Text>
                  <Text>  {p.body}</Text>
                </Text>
              )}
              {p.commentCount > 0 && openComments !== p.id && (
                <Pressable onPress={() => toggleComments(p)}>
                  <Text style={{ fontSize: 14, color: lilac.accent, marginTop: 6, textDecorationLine: 'underline' }}>댓글 {p.commentCount}개 모두 보기</Text>
                </Pressable>
              )}
              <Text style={[s.when, nf]}>{p.when}</Text>
            </View>

            {/* ── 독자 편지 (댓글 인라인 펼침) */}
            {openComments === p.id && (
              <View style={s.letters}>
                <Row style={{ alignItems: 'center', gap: 7, marginBottom: 9 }}>
                  <Text style={s.lettersKick}>LETTERS · 댓글 {comments.length}</Text>
                  <View style={s.kickerRule} />
                </Row>
                {comments.map((c) => (
                  <Row key={c.id} style={{ gap: 8, marginBottom: 9, alignItems: 'flex-start' }}>
                    <Avatar url={c.authorAvatar} char={c.authorName[0]} bg={lilac.accentDeep} size={22} />
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 14, lineHeight: 20 }}>
                        <Text style={{ fontWeight: '700', color: lilac.head }}>{c.authorName}</Text>
                        <Text style={{ color: lilac.text }}>  {c.body}</Text>
                      </Text>
                    </View>
                  </Row>
                ))}
                {!commentsLoaded && !commentsErr && (
                  <Text style={{ fontSize: 14, color: lilac.dim, marginBottom: 9 }}>댓글 불러오는 중...</Text>
                )}
                {commentsErr && (
                  <Pressable onPress={() => loadComments(p.id)} hitSlop={8} accessibilityRole="button" style={{ marginBottom: 9 }}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>댓글을 불러오지 못했어요 — 다시 시도 ›</Text>
                  </Pressable>
                )}
                {commentsLoaded && !commentsErr && comments.length === 0 && (
                  <Text style={{ fontSize: 14, color: lilac.dim, marginBottom: 9 }}>첫 댓글을 남겨보세요</Text>
                )}
                <Row style={{ gap: 8, alignItems: 'center' }}>
                  <TextInput
                    value={commentInput}
                    onChangeText={setCommentInput}
                    placeholder="응원 한마디..."
                    placeholderTextColor={lilac.dim}
                    style={s.commentInput}
                    onSubmitEditing={() => submitComment(p.id)}
                    returnKeyType="send"
                  />
                  <Pressable onPress={() => submitComment(p.id)} style={[s.commentSend, sending && { opacity: 0.5 }]}>
                    <Text style={{ fontSize: 16, fontWeight: '700', color: '#fff' }}>↑</Text>
                  </Pressable>
                </Row>
              </View>
            )}
          </View>
        ))}

        {/* ───────── 콜로폰 ───────── */}
        {tab === 'feed' && (
          <View style={s.colophon}>
            <Text style={s.coloBody}>동네 피드는 이웃들이 채웁니다. 완료된 러닝만 실려요 — 광고도, 남의 동네 소식도 없습니다.</Text>
            <Row style={{ alignItems: 'center', gap: 6, marginTop: 8 }}>
              <Text style={s.coloFoot}>오늘 <Text style={[{ color: lilac.text }, nf]}>{posts.length}</Text>건</Text>
              <View style={s.coloDot} />
              <Text style={s.coloFoot}>당겨서 새로고침</Text>
            </Row>
          </View>
        )}
      </ScrollView>
      </TabSwipe>
      <BottomNav />
    </View>
  );
}

// [페이퍼 크롬 2026-08-10] 크롬 페이퍼 이행 — 카드 샤프 1px #EEE · 소프트 섀도 은퇴 · 섹션 룰 = 코랄.
// 생존: 칼라 팔레트·사진 콘텐츠·클럽 나이트 리캡·골드 소인(원형 아티팩트)·코랄 발자국 신호·홀로 예산.
const s = StyleSheet.create({
  // 마스트헤드 — [FIX3] 키커·모노그램 12pt 밴드 승급, 박스 22로 성장 (모노그램 = 홀로 아티팩트, 라운드 유지)
  mono: { width: 22, height: 22, borderRadius: 6, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  monoTxt: { fontSize: 12, fontWeight: '600', color: lilac.head, letterSpacing: 0.5 },
  kickerLabel: { fontSize: 12, fontWeight: '600', letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  kickerRule: { flex: 1, height: 1, backgroundColor: '#EEEEEE' }, // [페이퍼 크롬] 인라인 룰은 뉴트럴
  // [§3c 화면 타이틀 2026-08-11] 38 → 30. 탭 화면 타이틀이 30/38/40 세 값으로 갈라져 있었고
  // (Sean: "tab in screen titles font size difference"), 30이 7개 탭 중 5개가 이미 쓰던 값이다.
  // 크기·굵기·행간은 앱 공통, 색은 화면의 월드를 따른다 (§2). lineHeight 37 = 1.23× (BUG A).
  h1: { fontSize: 30, fontWeight: '900', color: lilac.head, letterSpacing: -0.4, lineHeight: 37 },
  lede: { fontSize: 14, color: lilac.text, marginTop: 8, lineHeight: 20, maxWidth: 265 },
  liveBadge: { flexDirection: 'row', alignItems: 'center', gap: 4, borderWidth: 1, borderColor: '#F6C3B4', borderRadius: 0, backgroundColor: lilac.card, paddingVertical: 4, paddingHorizontal: 8, alignSelf: 'center' }, // [페이퍼 크롬] 샤프 (코랄 틴트 보더 = LIVE 신호 생존)
  liveDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral },
  liveTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1.2, color: lilac.coralDeep },
  rankBtn: { flexDirection: 'column', alignItems: 'center', gap: 2, backgroundColor: lilac.card, borderRadius: 0, paddingVertical: 8, paddingHorizontal: 12, borderWidth: 1, borderColor: '#EEEEEE', alignSelf: 'flex-start', marginTop: 4 }, // [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴
  rankTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.head, textTransform: 'uppercase' },

  // 클럽 스트립 (홀로 엣지) — [FIX3] 높이 72 → 80 · [페이퍼 크롬] 코너만 샤프 (나이트 표면·홀로는 아티팩트)
  clubStrip: { height: 80, borderRadius: 0, overflow: 'hidden', backgroundColor: lilac.head, marginHorizontal: GUTTER, marginTop: 13 },
  clubScrim: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(28,24,55,.40)' },
  clubKick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.5, color: 'rgba(255,255,255,.82)', textTransform: 'uppercase', marginBottom: 4 },
  clubName: { fontSize: 14.5, fontWeight: '700', color: '#fff', letterSpacing: -0.2 },
  clubPill: { backgroundColor: lilac.glassEdge, borderRadius: 0, paddingVertical: 6, paddingHorizontal: 10, alignItems: 'flex-end' }, // 사진 위 판독 플레이트 — 필 유지, 샤프
  clubPillN: { fontSize: 14, fontWeight: '700', color: lilac.head, lineHeight: 18 },
  clubGo: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.accent, marginTop: 3, textTransform: 'uppercase' },
  holoTop: { position: 'absolute', top: 0, left: 0, right: 0, height: 3, zIndex: 3 },
  holoBottom: { position: 'absolute', bottom: 0, left: 0, right: 0, height: 3, zIndex: 3 },

  tabCount: { fontSize: 12, fontWeight: '600', letterSpacing: 1 },

  // 후기 카드 — [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴
  revCard: { backgroundColor: lilac.card, borderRadius: 0, padding: 12, borderWidth: 1, borderColor: '#EEEEEE' },
  monoTag: { borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, backgroundColor: lilac.card, paddingVertical: 4, paddingHorizontal: 8 },
  // [D13 FLOOR14 2026-08-12] 12 → 14. 리뷰 태그는 사용자가 쓴 한글이다. textTransform:uppercase는
  // 한글에 아무 효과가 없으면서 이 스타일이 '라틴 캡스'인 척하게 만들던 잔재라 함께 뗀다.
  monoTagTxt: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.4, color: lilac.text },
  voltTag: { borderWidth: 1, borderColor: '#D9EBAA', borderRadius: 0, backgroundColor: lilac.voltFill, paddingVertical: 4, paddingHorizontal: 8 }, // 볼트 = 시맨틱 (마일스톤)
  voltTagTxt: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.4, color: lilac.voltDeep },

  emptyBox: { marginHorizontal: GUTTER, marginTop: 20, backgroundColor: lilac.inset, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', padding: 26 },

  // 피드 포스트 — [IG 개편] 카드-인-카드 은퇴: 풀블리드 + 포스트 사이 코랄 헤어라인 (스크롤 리듬)
  post: { backgroundColor: paper.canvas, marginTop: 12, borderTopWidth: 1, borderTopColor: paper.line, borderRadius: 0, overflow: 'hidden' },
  // ⋯ 오버플로 (내 포스트만) — 44pt 타깃 (36 + hitSlop 8)
  more: { width: 36, height: 36, alignItems: 'center', justifyContent: 'center' },
  // [D13 FLOOR14 2026-08-12] 12 → 14. {rv.when}은 '8월 3일 (일)' 같은 한글 날짜다.
  stamp: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.4, color: lilac.head },

  // 컴포즈 바 — 아바타 + 플레이스홀더 + 샤프 코랄 보더 버튼 (전체가 /compose 프레스 타깃)
  composeBar: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: GUTTER + 2, paddingVertical: 11, minHeight: 56, backgroundColor: paper.canvas },
  composePh: { flex: 1, fontSize: 14, color: lilac.dim },
  composeGo: { borderWidth: 1, borderColor: paper.line, backgroundColor: paper.canvas, borderRadius: 0, paddingVertical: 9, paddingHorizontal: 13 },
  composeGoTxt: { fontSize: 16, fontWeight: '800', color: paper.ink },

  // 라우드-페일 스트립 — criticalWash 바닥 + critical 잉크 (line과 절대 공유 금지) + 재시도
  failStrip: { marginHorizontal: GUTTER, marginTop: 14, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },

  // 사진 (콘텐츠 불가침 — 크롬 엣지만 뉴트럴)
  photoWrap: { position: 'relative', borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE', backgroundColor: lilac.inset },
  badgeCol: { position: 'absolute', top: 8, right: 8, gap: 4, alignItems: 'flex-end' },
  badge: { backgroundColor: lilac.glassEdge, borderRadius: 0, paddingVertical: 4, paddingHorizontal: 8 },
  badgeTxt: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.4, color: lilac.head },
  // 기록 소인 (골드) — 화면당 1개 · [FIX3] 텍스트 승급분만큼 56 → 68 원형 성장
  seal: { position: 'absolute', right: 10, bottom: 10, width: 68, height: 68, borderRadius: 34, backgroundColor: lilac.goldSoft, borderWidth: 1.4, borderColor: lilac.gold, alignItems: 'center', justifyContent: 'center', transform: [{ rotate: '-8deg' }] },
  sealB: { fontSize: 14, fontWeight: '700', color: lilac.head, lineHeight: 18 },
  sealS: { fontSize: 11.5, fontWeight: '600', letterSpacing: 1, color: lilac.head, textTransform: 'uppercase', marginTop: 2 },

  // 하이라인 스탯 표 — [FIX3] 키 12pt · [BUG A] 값 lineHeight 명시 · [페이퍼 크롬] 카드 내부 룰 = 뉴트럴
  statTable: { marginHorizontal: GUTTER + 2, marginTop: 9, borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE' },
  statCell: { flex: 1, paddingVertical: 9 },
  statDiv: { borderLeftWidth: 1, borderLeftColor: '#EEEEEE', paddingLeft: 11 },
  statK: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.dim, textTransform: 'uppercase', marginBottom: 4 },
  statV: { fontSize: 17, fontWeight: '600', color: lilac.head, fontVariant: ['tabular-nums'], lineHeight: 21 },

  // 기록 조판 블록 (사진 없음) — [BUG A] 큰 Oswald 숫자 lineHeight 46 (≥1.2×38)
  record: { flexDirection: 'row', gap: 10, alignItems: 'stretch', backgroundColor: lilac.inset, borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE', paddingHorizontal: GUTTER + 2, paddingVertical: 12 },
  recordKm: { fontSize: 38, fontWeight: '600', color: lilac.head, letterSpacing: -0.5, lineHeight: 46, fontVariant: ['tabular-nums'] },
  recordPace: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.6, color: lilac.accent, marginTop: 3 },
  traceBox: { alignItems: 'center', justifyContent: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0 },

  // 클럽 리캡 = 밤의 창 (나이트 라일락) — [FIX3] 키커·키 12pt · [BUG A] 숫자 lineHeight 명시
  recapCard: { backgroundColor: '#1C1837', paddingLeft: 16, paddingRight: 14, paddingVertical: 13, borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE', overflow: 'hidden' }, // 밤의 창은 아티팩트 — 크롬 엣지만 뉴트럴
  recapEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3 },
  recapKick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.8, color: '#CFC4FF', textTransform: 'uppercase' },
  recapNumCell: { flex: 1 },
  recapDiv: { borderLeftWidth: 1, borderLeftColor: 'rgba(207,196,255,.18)', paddingLeft: 12 },
  recapNum: { fontSize: 19, fontWeight: '600', color: '#fff', fontVariant: ['tabular-nums'], lineHeight: 23 },
  recapK: { fontSize: 12, fontWeight: '600', letterSpacing: 1.2, color: lilac.dim, textTransform: 'uppercase', marginTop: 4 },

  // 액션 행 — [IG 개편] 칩 보더 은퇴, 좌측 정렬 조용한 타깃 (minHeight 44 · 누른 발자국 = 코랄)
  act: { flexDirection: 'row', alignItems: 'center', gap: 6, minHeight: 44, paddingHorizontal: 8 },
  actLabel: { fontSize: 14, fontWeight: '700', color: lilac.dim },
  actLabelOn: { color: CORAL_INK },
  actNum: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: lilac.head, letterSpacing: 0.4 },
  actNumOn: { color: CORAL_INK },
  when: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.4, color: lilac.dim, marginTop: 7, marginBottom: 11 },

  // 독자 편지 (댓글) — [FIX3] 키커 12pt · 입력 14pt · 보내기 버튼 36
  letters: { borderTopWidth: 1, borderTopColor: '#EEEEEE', backgroundColor: lilac.card, paddingHorizontal: GUTTER + 2, paddingTop: 10, paddingBottom: 11 },
  lettersKick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.5, color: lilac.dim, textTransform: 'uppercase' },
  commentInput: {
    flex: 1, backgroundColor: lilac.inset, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', // [페이퍼 크롬]
    paddingVertical: 9, paddingHorizontal: 12, fontSize: 14, color: lilac.head,
  },
  commentSend: { width: 36, height: 36, borderRadius: 0, backgroundColor: CORAL_INK, alignItems: 'center', justifyContent: 'center' }, // 코랄 = 보내기 단일 신호 생존

  // 콜로폰 — [FIX3] 본문 13 · 풋라인 12 · [페이퍼 크롬] 섹션 룰 = 풀블리드 코랄 (마진 → 내부 패딩)
  colophon: { marginHorizontal: 0, paddingHorizontal: GUTTER + 2, marginTop: 14, paddingTop: 11, borderTopWidth: 1, borderTopColor: paper.line },
  coloBody: { fontSize: 14, color: lilac.dim, lineHeight: 19 },
  coloFoot: { fontSize: 14, lineHeight: 18, color: lilac.dim, letterSpacing: 0.2 },
  coloDot: { width: 3, height: 3, borderRadius: 1.5, backgroundColor: lilac.hair },
});
