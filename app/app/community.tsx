import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { HeatTrace } from '../src/components/runcard';
import { Avatar, Row } from '../src/components/ui';
import {
  addComment, deleteFeedPost, fetchComments, fetchFeed, fetchRecentReviews,
  FeedComment, FeedPost, PublicReview, toggleFeedLike,
} from '../src/lib/api';
import { useDisplayFont } from '../src/lib/displayFont';
import { haptic } from '../src/lib/haptics';
import { colors } from '../src/theme';

// 동네 피드 — 인스타 풀와이드 개편 (Sean 확정, hi-club-plan §1-C, 2026-07-29).
// IG 문법: 작성자 → 엣지-투-엣지 사진(더블탭 🐾 + 스트라바식 스탯 오버레이) → 액션 행 →
// 발자국 수 → 캡션(볼드 작성자+본문) → 댓글. 좋아요 언어 = 발자국(🐾).
// 피드의 미래 베이스라인 = 세션 리캡 자동 유입 (P-B에서 합류) — 수동 포스트는 보충.
// 화면당 애니메이션 상한 준수: 원샷 발자국 버스트 1개만.

const FOREST = '#0F1D13';
const W = Dimensions.get('window').width;

const fmtDur = (sec?: number) => (sec ? `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}` : null);

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

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* header */}
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 16 }}>
          <View>
            <Row style={{ gap: 6 }}>
              <Text style={[{ fontSize: 30, fontWeight: '900', color: FOREST }, df]}>동네 피드</Text>
              <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }}>
                <Text style={{ fontSize: 10, fontWeight: '900', color: '#fff' }}>● LIVE</Text>
              </View>
            </Row>
            <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 4 }}>우리 동네 강아지들의 오늘 러닝</Text>
          </View>
          <Pressable onPress={() => router.push('/leaderboard')} style={s.rankBtn}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: colors.tang }}>🏆 랭킹</Text>
          </Pressable>
        </Row>

        {/* 탭바 — 피드 | 러너 후기 (밑줄 인디케이터) */}
        <Row style={{ marginTop: 14, paddingHorizontal: 16, gap: 20, borderBottomWidth: 1, borderBottomColor: '#DCD6C4' }}>
          {([['feed', '피드'], ['reviews', '러너 후기']] as const).map(([k, label]) => (
            <Pressable key={k} onPress={() => setTab(k)} style={{ paddingBottom: 9, borderBottomWidth: 2.5, borderBottomColor: tab === k ? FOREST : 'transparent', marginBottom: -1 }}>
              <Text style={{ fontSize: 16, fontWeight: '900', color: tab === k ? FOREST : '#9a978a' }}>{label}</Text>
            </Pressable>
          ))}
        </Row>

        {/* ---------- 러너 후기 탭 — 실 공개 리뷰 ---------- */}
        {tab === 'reviews' && (
          <View style={{ paddingHorizontal: 12, marginTop: 14, gap: 9 }}>
            {reviews == null && <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 30 }}>불러오는 중...</Text>}
            {reviews != null && reviews.length === 0 && (
              <View style={s.revCard}>
                <Text style={{ fontSize: 14.5, color: colors.dim, textAlign: 'center', lineHeight: 22 }}>
                  아직 공개 후기가 없어요{'\n'}러닝이 끝나면 첫 후기를 남겨보세요
                </Text>
              </View>
            )}
            {(reviews ?? []).map((rv, i) => (
              <View key={i} style={s.revCard}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST }}>{rv.runnerName} 러너</Text>
                  <Text style={{ fontSize: 14.5, color: colors.dim }}>{rv.when}</Text>
                </Row>
                {rv.rating != null && (
                  <Text style={{ fontSize: 14, color: '#e8a13c', marginTop: 4 }}>{'★'.repeat(rv.rating)}{'☆'.repeat(Math.max(0, 5 - rv.rating))}</Text>
                )}
                {!!rv.note && <Text style={{ fontSize: 14.5, color: '#3d453d', marginTop: 6, lineHeight: 20.5 }}>{rv.note}</Text>}
                {rv.tags.length > 0 && (
                  <Row style={{ gap: 5, marginTop: 8, flexWrap: 'wrap' }}>
                    {rv.tags.map((t) => (
                      <View key={t} style={{ backgroundColor: '#EDE8DA', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 }}>
                        <Text style={{ fontSize: 11, fontWeight: '700', color: '#4a6d1f' }}>{t}</Text>
                      </View>
                    ))}
                  </Row>
                )}
              </View>
            ))}
          </View>
        )}

        {/* feed */}
        {tab === 'feed' && loaded && posts.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST, textAlign: 'center' }}>아직 포스트가 없어요</Text>
            <Text style={{ fontSize: 14.5, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 22 }}>
              러닝을 완료하고 리포트에서 '동네 피드에 자랑하기'를 눌러보세요{'\n'}첫 포스트의 주인공이 되어주세요 🐕
            </Text>
          </View>
        )}

        {tab === 'feed' && posts.map((p) => (
          <View key={p.id} style={s.post}>
            {/* ── 작성자 (IG 헤더) */}
            <Pressable onLongPress={() => remove(p)}>
              <Row style={{ gap: 10, paddingHorizontal: 16, paddingVertical: 11 }}>
                <Avatar url={p.authorAvatar} char={p.authorName[0]} bg="#5a7a3c" size={38} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 15.5, fontWeight: '800', color: FOREST }}>{p.authorName}</Text>
                  {p.meta.dogName && <Text style={{ fontSize: 13, color: colors.dim, marginTop: 1 }}>{p.meta.dogName}와 함께</Text>}
                </View>
                {p.mine && <Text style={{ fontSize: 12, color: '#9a978a', alignSelf: 'center' }}>길게 눌러 삭제</Text>}
              </Row>
            </Pressable>

            {/* ── 사진 — 엣지-투-엣지 4:5 + 더블탭 🐾 + 스트라바식 스탯 오버레이 */}
            {p.photoUrl ? (
              <Pressable onPress={() => onPhotoTap(p)}>
                <Image source={{ uri: p.photoUrl }} style={{ width: W, height: W * 1.1, backgroundColor: '#DCD6C4' }} resizeMode="cover" />
                {/* 스탯 오버레이 — 사진 위 좌하단 (스크림으로 가독) */}
                {(p.meta.km != null || fmtDur(p.meta.durationSec)) && (
                  <View pointerEvents="none" style={s.statScrim}>
                    {p.meta.km != null && (
                      <Text style={s.statKm}>{p.meta.km}<Text style={{ fontSize: 15 }}> km</Text></Text>
                    )}
                    {fmtDur(p.meta.durationSec) && (
                      <Text style={s.statSub}>⏱ {fmtDur(p.meta.durationSec)}</Text>
                    )}
                  </View>
                )}
                {(p.meta.badges ?? []).length > 0 && (
                  <View pointerEvents="none" style={s.badgeCol}>
                    {(p.meta.badges ?? []).map((b) => (
                      <View key={b} style={s.badge}><Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>{b}</Text></View>
                    ))}
                  </View>
                )}
                <PawBurst trigger={bursts[p.id] ?? 0} />
              </Pressable>
            ) : (
              // 사진 없는 포스트 = 볼트 런 카드 (밋밋한 텍스트 스트립 은퇴 — Sean 2026-07-29).
              // 인증샷 볼트 블록의 피드 미니어처: 큰 km + 트레이스 + 배지. 더블탭 🐾 동일 지원.
              <Pressable onPress={() => onPhotoTap(p)}>
                <View style={s.runCard}>
                  <View style={{ flex: 1 }}>
                    <Text style={s.runCardKm}>
                      {p.meta.km != null ? p.meta.km : '—'}<Text style={{ fontSize: 16, letterSpacing: 0 }}> km</Text>
                    </Text>
                    {p.meta.dogName && (
                      <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 2 }}>{p.meta.dogName} 완주</Text>
                    )}
                    {fmtDur(p.meta.durationSec) && (
                      <Text style={{ fontSize: 13.5, fontWeight: '700', color: '#3d5a2b', marginTop: 4 }}>⏱ {fmtDur(p.meta.durationSec)}</Text>
                    )}
                    <Row style={{ gap: 5, marginTop: 8, flexWrap: 'wrap' }}>
                      {(p.meta.badges ?? []).map((b) => (
                        <View key={b} style={s.runCardBadge}><Text style={{ fontSize: 11, fontWeight: '900', color: colors.volt }}>{b}</Text></View>
                      ))}
                    </Row>
                  </View>
                  {(p.meta.trace ?? []).length > 1 ? (
                    <View style={{ justifyContent: 'center' }}>
                      <HeatTrace points={(p.meta.trace ?? []).map((pt) => ({ ...pt, v: 0.65 }))} width={110} height={116} />
                    </View>
                  ) : (
                    <Text style={{ fontSize: 40, alignSelf: 'center', opacity: 0.5 }}>🐾</Text>
                  )}
                  <PawBurst trigger={bursts[p.id] ?? 0} />
                </View>
              </Pressable>
            )}

            {/* ── 액션 행 (IG) */}
            <Row style={{ paddingHorizontal: 14, paddingTop: 9, gap: 4 }}>
              <Pressable onPress={() => setLiked(p, !p.likedByMe)} style={s.actBtn} hitSlop={6}>
                <Text style={{ fontSize: 22, opacity: p.likedByMe ? 1 : 0.45 }}>🐾</Text>
              </Pressable>
              <Pressable onPress={() => toggleComments(p)} style={s.actBtn} hitSlop={6}>
                <Text style={{ fontSize: 20, opacity: 0.7 }}>💬</Text>
              </Pressable>
            </Row>

            {/* ── 발자국 수 + 캡션 (IG 문법: 볼드 작성자 + 본문 이어쓰기) */}
            <View style={{ paddingHorizontal: 16, paddingTop: 5 }}>
              {p.likes > 0 && (
                <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>발자국 {p.likes}개</Text>
              )}
              {p.body && (
                <Text style={{ fontSize: 15, color: '#3d453d', lineHeight: 22, marginTop: 3 }}>
                  <Text style={{ fontWeight: '800', color: FOREST }}>{p.authorName}</Text>
                  <Text>  {p.body}</Text>
                </Text>
              )}
              {p.commentCount > 0 && openComments !== p.id && (
                <Pressable onPress={() => toggleComments(p)}>
                  <Text style={{ fontSize: 14, color: '#9a978a', marginTop: 4 }}>댓글 {p.commentCount}개 모두 보기</Text>
                </Pressable>
              )}
              <Text style={{ fontSize: 12, color: '#9a978a', marginTop: 4, marginBottom: 11 }}>{p.when}</Text>
            </View>

            {/* ── 댓글 (인라인 펼침) */}
            {openComments === p.id && (
              <View style={s.commentsWrap}>
                {comments.map((c) => (
                  <Row key={c.id} style={{ gap: 8, marginBottom: 9 }}>
                    <Avatar url={c.authorAvatar} char={c.authorName[0]} bg="#c9a86e" size={26} />
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 14 }}>
                        <Text style={{ fontWeight: '800', color: FOREST }}>{c.authorName}</Text>
                        <Text style={{ color: '#3d453d' }}>  {c.body}</Text>
                      </Text>
                    </View>
                  </Row>
                ))}
                {comments.length === 0 && (
                  <Text style={{ fontSize: 15, color: colors.dim, marginBottom: 8 }}>첫 댓글을 남겨보세요</Text>
                )}
                <Row style={{ gap: 8 }}>
                  <TextInput
                    value={commentInput}
                    onChangeText={setCommentInput}
                    placeholder="응원 한마디..."
                    placeholderTextColor="#b0ada0"
                    style={s.commentInput}
                    onSubmitEditing={() => submitComment(p.id)}
                    returnKeyType="send"
                  />
                  <Pressable onPress={() => submitComment(p.id)} style={[s.commentSend, sending && { opacity: 0.5 }]}>
                    <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>↑</Text>
                  </Pressable>
                </Row>
              </View>
            )}
          </View>
        ))}
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  revCard: { backgroundColor: '#fff', borderRadius: 14, padding: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  rankBtn: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#DCD6C4', alignSelf: 'flex-start' },
  emptyBox: { margin: 22, marginTop: 26, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26 },
  post: { backgroundColor: '#fff', marginTop: 14, borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#DCD6C4' },
  statScrim: { position: 'absolute', left: 0, right: 0, bottom: 0, paddingHorizontal: 16, paddingBottom: 12, paddingTop: 34, backgroundColor: 'rgba(10,16,10,.30)' },
  statKm: { fontSize: 30, fontWeight: '900', color: '#fff', textShadowColor: 'rgba(0,0,0,.5)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  statSub: { fontSize: 13.5, fontWeight: '700', color: '#e6efe0', marginTop: 1, textShadowColor: 'rgba(0,0,0,.5)', textShadowRadius: 6, textShadowOffset: { width: 0, height: 1 } },
  badgeCol: { position: 'absolute', top: 12, right: 12, gap: 6, alignItems: 'flex-end' },
  badge: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10, alignSelf: 'center' },
  actBtn: { paddingVertical: 4, paddingHorizontal: 6 },
  runCard: { flexDirection: 'row', gap: 12, backgroundColor: colors.volt, marginHorizontal: 0, paddingHorizontal: 18, paddingVertical: 16, overflow: 'hidden' },
  runCardKm: { fontSize: 44, fontWeight: '900', color: FOREST, letterSpacing: -2, lineHeight: 48 },
  runCardBadge: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  commentsWrap: { paddingHorizontal: 16, paddingBottom: 14, borderTopWidth: 1, borderTopColor: '#f0eee3', paddingTop: 11 },
  commentInput: {
    flex: 1, backgroundColor: '#faf9f3', borderRadius: 99, borderWidth: 1, borderColor: '#DCD6C4',
    paddingVertical: 9, paddingHorizontal: 14, fontSize: 15, color: FOREST,
  },
  commentSend: { width: 36, height: 36, borderRadius: 18, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
