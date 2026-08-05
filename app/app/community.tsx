import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Pressable, RefreshControl, ScrollView, StyleProp, StyleSheet, Text, TextInput, View, ViewStyle } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { HeatTrace } from '../src/components/runcard';
import { Avatar, Row } from '../src/components/ui';
import {
  addComment, deleteFeedPost, fetchComments, fetchFeed, fetchRecentReviews,
  FeedComment, FeedPost, PublicReview, toggleFeedLike,
} from '../src/lib/api';
import { useClubOverview } from '../src/components/clubcard';
import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { haptic } from '../src/lib/haptics';
import { CollarKey, collarColors, lilac, lilacRadius, lilacShadow } from '../src/theme';

// 동네 피드 — "동네 신문 (LOCAL PAPER)" 리페인트 (라일락 정본, delegation-premium-refresh2).
// 편집 문법: 마스트헤드(판권 라인 + Black Han Sans 워드마크 1회) → 홀로 엣지 클럽 배너 →
// 기사 카드(바이라인 행 · 사진=본문 · 하이라인 스탯 표 · 조용한 액션 행) → 독자 편지(댓글).
// 액센트 예산: 바이올렛 = 구조/룰/링크 · 코랄 = 단일 신호(LIVE 도트 · 누른 발자국 · 보내기).
// 포일 예산: 홀로 = 클럽 배너 상하 엣지 + 마스트헤드 모노그램만 · 골드 = 기록 소인 화면당 1개.
// 로직 동결: 모든 핸들러/라우팅/데이터 흐름은 원본 그대로, 프레젠테이션만 재도색.
// FIX3: 디테일 텍스트 플로어 — ≤10.5pt 전부 12–15 밴드로 승급(최저 11.5), 본문 11–13 → 13–15.
//       히어로/헤딩 크기 불변 · 큰 Oswald 숫자는 lineHeight ≥ 1.2×로 상단 클리핑 방지 (BUG A).

const W = Dimensions.get('window').width;
const GUTTER = 13;
const CARDW = W - GUTTER * 2;

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
      <Text style={{ fontSize: 84, textShadowColor: 'rgba(0,0,0,.35)', textShadowRadius: 14, textShadowOffset: { width: 0, height: 3 } }}>🐾</Text>
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

  const load = () => fetchFeed()
    .then((p) => { setPosts(p); setLoaded(true); })
    .catch((e) => { console.warn('[feed]:', e?.message ?? e); setLoaded(true); });
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const setLiked = (p: FeedPost, liked: boolean) => {
    if (p.likedByMe === liked) return;
    haptic('light');
    setPosts((cur) => cur.map((x) => (x.id === p.id
      ? { ...x, likedByMe: liked, likes: p.likes + (liked ? 1 : -1) }
      : x)));
    toggleFeedLike(p.id, p.likedByMe).catch(() => load()); // 낙관적 반영 — 실패 시 리로드로 정합
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

  const toggleComments = (p: FeedPost) => {
    if (openComments === p.id) { setOpenComments(null); return; }
    setOpenComments(p.id);
    setComments([]);
    fetchComments(p.id).then(setComments).catch(() => {});
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
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
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
              <Text style={{ fontSize: 15 }}>🏆</Text>
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
        <Row style={{ marginTop: 14, paddingHorizontal: GUTTER + 2, gap: 20, borderBottomWidth: 1, borderBottomColor: lilac.hair }}>
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

        {/* ───────── 피드 ───────── */}
        {tab === 'feed' && loaded && posts.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: lilac.head, textAlign: 'center' }}>아직 포스트가 없어요</Text>
            <Text style={{ fontSize: 14, color: lilac.dim, textAlign: 'center', marginTop: 6, lineHeight: 22 }}>
              러닝을 완료하고 리포트에서 '동네 피드에 자랑하기'를 눌러보세요{'\n'}첫 포스트의 주인공이 되어주세요 🐕
            </Text>
          </View>
        )}

        {tab === 'feed' && posts.map((p, i) => (
          <View key={p.id} style={s.post}>
            {/* ── 바이라인 행 */}
            <Pressable onLongPress={() => remove(p)}>
              <Row style={{ gap: 9, paddingHorizontal: 11, paddingTop: 10, paddingBottom: 9, alignItems: 'flex-start' }}>
                <Avatar url={p.authorAvatar} char={p.authorName[0]} bg={lilac.accent} size={32} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head }}>{p.authorName}</Text>
                  {p.meta.dogName && (
                    <Row style={{ gap: 5, marginTop: 2, alignItems: 'center' }}>
                      {p.meta.collar && collarColors[p.meta.collar as CollarKey] && (
                        <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: collarColors[p.meta.collar as CollarKey] }} />
                      )}
                      <Text style={{ fontSize: 14, color: lilac.text }}>{p.meta.dogName}와 함께</Text>
                    </Row>
                  )}
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={[s.stamp, nf]}>{p.when}</Text>
                  {p.mine && <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 3 }}>길게 눌러 삭제</Text>}
                </View>
                <Text style={[s.idx, nf]}>{String(i + 1).padStart(2, '0')}</Text>
              </Row>
            </Pressable>

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
                    <View style={[s.recapNumCell, s.recapDiv]}><Text style={[s.recapNum, nf]}>🏁</Text><Text style={s.recapK}>FINISHED</Text></View>
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
                    <Image source={{ uri: p.photoUrl }} style={{ width: CARDW, height: CARDW * 1.1, backgroundColor: lilac.inset }} resizeMode="cover" />
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
                      <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.text, marginTop: 4 }}>⏱ <Text style={[{ fontSize: 14, color: lilac.head }, nf]}>{fmtDur(p.meta.durationSec)}</Text></Text>
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
                    <Text style={{ fontSize: 38, alignSelf: 'center', opacity: 0.4 }}>🐾</Text>
                  )}
                  <PawBurst trigger={bursts[p.id] ?? 0} />
                </View>
              </Pressable>
            )}

            {/* ── 조용한 액션 행 (누른 발자국 = 코랄 단일 신호) */}
            <Row style={{ paddingHorizontal: 11, paddingTop: 9, gap: 6 }}>
              <Pressable onPress={() => setLiked(p, !p.likedByMe)} style={[s.act, p.likedByMe && s.actOn]} hitSlop={6}>
                <Text style={{ fontSize: 14, opacity: p.likedByMe ? 1 : 0.5 }}>🐾</Text>
                <Text style={[s.actLabel, p.likedByMe && s.actLabelOn]}>발자국</Text>
                <Text style={[s.actNum, p.likedByMe && s.actLabelOn, nf]}>{p.likes}</Text>
              </Pressable>
              <Pressable onPress={() => toggleComments(p)} style={s.act} hitSlop={6}>
                <Text style={{ fontSize: 14, opacity: 0.5 }}>💬</Text>
                <Text style={s.actLabel}>댓글</Text>
                <Text style={[s.actNum, nf]}>{p.commentCount}</Text>
              </Pressable>
            </Row>

            {/* ── 캡션 본문 (볼드 작성자 + 본문) */}
            <View style={{ paddingHorizontal: 11, paddingTop: 8 }}>
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
                {comments.length === 0 && (
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
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  // 마스트헤드 — [FIX3] 키커·모노그램 12pt 밴드 승급, 박스 22로 성장
  mono: { width: 22, height: 22, borderRadius: 6, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  monoTxt: { fontSize: 12, fontWeight: '600', color: lilac.head, letterSpacing: 0.5 },
  kickerLabel: { fontSize: 12, fontWeight: '600', letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  kickerRule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  h1: { fontSize: 38, fontWeight: '900', color: lilac.head, letterSpacing: -0.4, lineHeight: 46 }, // [BUG A] lineHeight ≥1.2× — 상단 클리핑 방지 (크기 불변)
  lede: { fontSize: 14, color: lilac.text, marginTop: 8, lineHeight: 20, maxWidth: 265 },
  liveBadge: { flexDirection: 'row', alignItems: 'center', gap: 4, borderWidth: 1, borderColor: '#F6C3B4', borderRadius: lilacRadius.tag, backgroundColor: lilac.card, paddingVertical: 4, paddingHorizontal: 8, alignSelf: 'center' },
  liveDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral },
  liveTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1.2, color: lilac.coralDeep },
  rankBtn: { flexDirection: 'column', alignItems: 'center', gap: 2, backgroundColor: lilac.card, borderRadius: lilacRadius.card, paddingVertical: 8, paddingHorizontal: 12, borderWidth: 1, borderColor: lilac.hair, alignSelf: 'flex-start', marginTop: 4, ...lilacShadow },
  rankTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.head, textTransform: 'uppercase' },

  // 클럽 스트립 (홀로 엣지) — [FIX3] 텍스트 승급분만큼 높이 72 → 80
  clubStrip: { height: 80, borderRadius: 6, overflow: 'hidden', backgroundColor: lilac.head, marginHorizontal: GUTTER, marginTop: 13 },
  clubScrim: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(28,24,55,.40)' },
  clubKick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.5, color: 'rgba(255,255,255,.82)', textTransform: 'uppercase', marginBottom: 4 },
  clubName: { fontSize: 14.5, fontWeight: '700', color: '#fff', letterSpacing: -0.2 },
  clubPill: { backgroundColor: lilac.glassEdge, borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 10, alignItems: 'flex-end' },
  clubPillN: { fontSize: 14, fontWeight: '700', color: lilac.head, lineHeight: 18 },
  clubGo: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.accent, marginTop: 3, textTransform: 'uppercase' },
  holoTop: { position: 'absolute', top: 0, left: 0, right: 0, height: 3, zIndex: 3 },
  holoBottom: { position: 'absolute', bottom: 0, left: 0, right: 0, height: 3, zIndex: 3 },

  tabCount: { fontSize: 12, fontWeight: '600', letterSpacing: 1 },

  // 후기 카드
  revCard: { backgroundColor: lilac.card, borderRadius: lilacRadius.card, padding: 12, borderWidth: 1, borderColor: lilac.hair, ...lilacShadow },
  monoTag: { borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.tag, backgroundColor: lilac.card, paddingVertical: 4, paddingHorizontal: 8 },
  monoTagTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.text, textTransform: 'uppercase' },
  voltTag: { borderWidth: 1, borderColor: '#D9EBAA', borderRadius: lilacRadius.tag, backgroundColor: lilac.voltFill, paddingVertical: 4, paddingHorizontal: 8 },
  voltTagTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.voltDeep, textTransform: 'uppercase' },

  emptyBox: { marginHorizontal: GUTTER, marginTop: 20, backgroundColor: lilac.inset, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: lilac.hair, padding: 26 },

  // 기사 카드 — [FIX3] 스탬프·인덱스 12pt 승급
  post: { backgroundColor: lilac.card, marginHorizontal: GUTTER, marginTop: 11, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card, overflow: 'hidden', ...lilacShadow },
  stamp: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.head, textTransform: 'uppercase' },
  idx: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.head, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.doc, paddingVertical: 3, paddingHorizontal: 5, marginLeft: 2, alignSelf: 'flex-start' },

  // 사진
  photoWrap: { position: 'relative', borderTopWidth: 1, borderBottomWidth: 1, borderColor: lilac.hair2, backgroundColor: lilac.inset },
  badgeCol: { position: 'absolute', top: 8, right: 8, gap: 4, alignItems: 'flex-end' },
  badge: { backgroundColor: lilac.glassEdge, borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 8 },
  badgeTxt: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.head, textTransform: 'uppercase' },
  // 기록 소인 (골드) — 화면당 1개 · [FIX3] 텍스트 승급분만큼 56 → 68 원형 성장
  seal: { position: 'absolute', right: 10, bottom: 10, width: 68, height: 68, borderRadius: 34, backgroundColor: lilac.goldSoft, borderWidth: 1.4, borderColor: lilac.gold, alignItems: 'center', justifyContent: 'center', transform: [{ rotate: '-8deg' }] },
  sealB: { fontSize: 14, fontWeight: '700', color: lilac.head, lineHeight: 18 },
  sealS: { fontSize: 11.5, fontWeight: '600', letterSpacing: 1, color: lilac.head, textTransform: 'uppercase', marginTop: 2 },

  // 하이라인 스탯 표 — [FIX3] 키 12pt · [BUG A] 값 lineHeight 명시
  statTable: { marginHorizontal: 11, marginTop: 9, borderTopWidth: 1, borderBottomWidth: 1, borderColor: lilac.hair },
  statCell: { flex: 1, paddingVertical: 9 },
  statDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2, paddingLeft: 11 },
  statK: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.dim, textTransform: 'uppercase', marginBottom: 4 },
  statV: { fontSize: 17, fontWeight: '600', color: lilac.head, fontVariant: ['tabular-nums'], lineHeight: 21 },

  // 기록 조판 블록 (사진 없음) — [BUG A] 큰 Oswald 숫자 lineHeight 46 (≥1.2×38)
  record: { flexDirection: 'row', gap: 10, alignItems: 'stretch', backgroundColor: lilac.inset, borderTopWidth: 1, borderBottomWidth: 1, borderColor: lilac.hair2, paddingHorizontal: 11, paddingVertical: 12 },
  recordKm: { fontSize: 38, fontWeight: '600', color: lilac.head, letterSpacing: -0.5, lineHeight: 46, fontVariant: ['tabular-nums'] },
  recordPace: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.6, color: lilac.accent, marginTop: 3 },
  traceBox: { alignItems: 'center', justifyContent: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.inner },

  // 클럽 리캡 = 밤의 창 (나이트 라일락) — [FIX3] 키커·키 12pt · [BUG A] 숫자 lineHeight 명시
  recapCard: { backgroundColor: '#1C1837', paddingLeft: 16, paddingRight: 14, paddingVertical: 13, borderTopWidth: 1, borderBottomWidth: 1, borderColor: lilac.hair2, overflow: 'hidden' },
  recapEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3 },
  recapKick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.8, color: '#CFC4FF', textTransform: 'uppercase' },
  recapNumCell: { flex: 1 },
  recapDiv: { borderLeftWidth: 1, borderLeftColor: 'rgba(207,196,255,.18)', paddingLeft: 12 },
  recapNum: { fontSize: 19, fontWeight: '600', color: '#fff', fontVariant: ['tabular-nums'], lineHeight: 23 },
  recapK: { fontSize: 12, fontWeight: '600', letterSpacing: 1.2, color: lilac.dim, textTransform: 'uppercase', marginTop: 4 },

  // 조용한 액션 행 — [FIX3] 라벨·숫자 승급, 칩 패딩 성장
  act: { flexDirection: 'row', alignItems: 'center', gap: 5, borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.card, borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 10 },
  actOn: { borderColor: '#F6C3B4', backgroundColor: '#FFF7F4', borderLeftWidth: 2.5, borderLeftColor: lilac.coral },
  actLabel: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.dim, textTransform: 'uppercase' },
  actLabelOn: { color: lilac.head },
  actNum: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.head, letterSpacing: 0.4 },
  when: { fontSize: 12, fontWeight: '600', letterSpacing: 1, color: lilac.dim, textTransform: 'uppercase', marginTop: 7, marginBottom: 11 },

  // 독자 편지 (댓글) — [FIX3] 키커 12pt · 입력 14pt · 보내기 버튼 36
  letters: { borderTopWidth: 1, borderTopColor: lilac.hair, backgroundColor: lilac.card, paddingHorizontal: 11, paddingTop: 10, paddingBottom: 11 },
  lettersKick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.5, color: lilac.dim, textTransform: 'uppercase' },
  commentInput: {
    flex: 1, backgroundColor: lilac.inset, borderRadius: lilacRadius.inner, borderWidth: 1, borderColor: lilac.hair,
    paddingVertical: 9, paddingHorizontal: 12, fontSize: 14, color: lilac.head,
  },
  commentSend: { width: 36, height: 36, borderRadius: lilacRadius.btn, backgroundColor: CORAL_INK, alignItems: 'center', justifyContent: 'center' },

  // 콜로폰 — [FIX3] 본문 13 · 풋라인 12
  colophon: { marginHorizontal: GUTTER + 2, marginTop: 14, paddingTop: 11, borderTopWidth: 1, borderTopColor: lilac.hair },
  coloBody: { fontSize: 14, color: lilac.dim, lineHeight: 19 },
  coloFoot: { fontSize: 14, lineHeight: 18, color: lilac.dim, letterSpacing: 0.2 },
  coloDot: { width: 3, height: 3, borderRadius: 1.5, backgroundColor: lilac.hair },
});
