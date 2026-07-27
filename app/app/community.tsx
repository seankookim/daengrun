import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Dimensions, Image, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Avatar, Row } from '../src/components/ui';
import { addComment, deleteFeedPost, FeedComment, FeedPost, fetchComments, fetchFeed, toggleFeedLike } from '../src/lib/api';
import { haptic } from '../src/lib/haptics';
import { colors } from '../src/theme';

// 동네 피드 — 완료 러닝 자랑 (옵트인: 리포트에서 공유한 것만). 미니 인스타의 v1.
// 좋아요 실동작 · 본인 포스트 길게 눌러 삭제 · 랭킹 진입. 목업 스트릭랭킹·필터·글쓰기 은퇴.

const FOREST = '#132117';
const W = Dimensions.get('window').width;

const fmtDur = (sec?: number) => (sec ? `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}` : null);

export default function Community() {
  const [posts, setPosts] = useState<FeedPost[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const load = () => fetchFeed()
    .then((p) => { setPosts(p); setLoaded(true); })
    .catch((e) => { console.warn('[feed]:', e?.message ?? e); setLoaded(true); });
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const like = (p: FeedPost) => {
    haptic('light');
    // 낙관적 반영 — 실패 시 리로드로 정합
    setPosts((cur) => cur.map((x) => (x.id === p.id
      ? { ...x, likedByMe: !p.likedByMe, likes: p.likes + (p.likedByMe ? -1 : 1) }
      : x)));
    toggleFeedLike(p.id, p.likedByMe).catch(() => load());
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
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 22 }}>
          <View>
            <Row style={{ gap: 6 }}>
              <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>동네 피드</Text>
              <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }}>
                <Text style={{ fontSize: 8.5, fontWeight: '900', color: '#fff' }}>● LIVE</Text>
              </View>
            </Row>
            <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 4 }}>우리 동네 강아지들의 오늘 러닝</Text>
          </View>
          <Pressable onPress={() => router.push('/leaderboard')} style={s.rankBtn}>
            <Text style={{ fontSize: 12, fontWeight: '900', color: colors.tang }}>🏆 랭킹</Text>
          </Pressable>
        </Row>

        {/* feed */}
        {loaded && posts.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST, textAlign: 'center' }}>아직 포스트가 없어요</Text>
            <Text style={{ fontSize: 12.5, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 19 }}>
              러닝을 완료하고 리포트에서 '동네 피드에 자랑하기'를 눌러보세요{'\n'}첫 포스트의 주인공이 되어주세요 🐕
            </Text>
          </View>
        )}

        {posts.map((p) => (
          <Pressable key={p.id} onLongPress={() => remove(p)} style={s.post}>
            {/* author */}
            <Row style={{ gap: 10, paddingHorizontal: 16, paddingVertical: 12 }}>
              <Avatar url={p.authorAvatar} char={p.authorName[0]} bg="#5a7a3c" size={38} />
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 13.5, fontWeight: '800', color: FOREST }}>{p.authorName}</Text>
                <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 1 }}>{p.when}{p.mine ? ' · 내 포스트 (길게 눌러 삭제)' : ''}</Text>
              </View>
            </Row>

            {/* photo — 엣지-투-엣지 (사진이 디자인이다) */}
            {p.photoUrl && (
              <Image source={{ uri: p.photoUrl }} style={{ width: W, height: W * 0.75, backgroundColor: '#e2e0d4' }} resizeMode="cover" />
            )}

            {/* run stats strip */}
            <Row style={{ gap: 10, paddingHorizontal: 16, paddingTop: 11, flexWrap: 'wrap' }}>
              {p.meta.dogName && (
                <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>🐕 {p.meta.dogName}</Text>
              )}
              {p.meta.km != null && (
                <Text style={{ fontSize: 13.5, fontWeight: '900', color: colors.tang }}>{p.meta.km}km</Text>
              )}
              {fmtDur(p.meta.durationSec) && (
                <Text style={{ fontSize: 12.5, color: colors.dim, alignSelf: 'center' }}>⏱ {fmtDur(p.meta.durationSec)}</Text>
              )}
              {(p.meta.badges ?? []).map((b) => (
                <View key={b} style={s.badge}><Text style={{ fontSize: 10, fontWeight: '900', color: '#3d5a2b' }}>{b}</Text></View>
              ))}
            </Row>

            {p.body && (
              <Text style={{ fontSize: 13, color: '#3d453d', lineHeight: 19, paddingHorizontal: 16, paddingTop: 7 }}>{p.body}</Text>
            )}

            {/* like + comment row */}
            <Row style={{ paddingHorizontal: 16, paddingVertical: 11, gap: 8 }}>
              <Pressable onPress={() => like(p)} style={s.likeBtn}>
                <Text style={{ fontSize: 15 }}>{p.likedByMe ? '❤️' : '🤍'}</Text>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: p.likedByMe ? colors.tang : '#5d655d' }}>
                  {p.likes > 0 ? p.likes : '응원하기'}
                </Text>
              </Pressable>
              <Pressable onPress={() => toggleComments(p)} style={s.likeBtn}>
                <Text style={{ fontSize: 14 }}>💬</Text>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#5d655d' }}>
                  {p.commentCount > 0 ? p.commentCount : '댓글'}
                </Text>
              </Pressable>
            </Row>

            {/* comments (inline expand) */}
            {openComments === p.id && (
              <View style={s.commentsWrap}>
                {comments.map((c) => (
                  <Row key={c.id} style={{ gap: 8, marginBottom: 9 }}>
                    <Avatar url={c.authorAvatar} char={c.authorName[0]} bg="#c9a86e" size={26} />
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 12 }}>
                        <Text style={{ fontWeight: '800', color: FOREST }}>{c.authorName}</Text>
                        <Text style={{ color: '#3d453d' }}>  {c.body}</Text>
                      </Text>
                    </View>
                  </Row>
                ))}
                {comments.length === 0 && (
                  <Text style={{ fontSize: 11.5, color: colors.dim, marginBottom: 8 }}>첫 댓글을 남겨보세요</Text>
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
                    <Text style={{ fontSize: 13, fontWeight: '900', color: FOREST }}>↑</Text>
                  </Pressable>
                </Row>
              </View>
            )}
          </Pressable>
        ))}
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  rankBtn: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#eceadf', alignSelf: 'flex-start' },
  emptyBox: { margin: 22, marginTop: 26, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26 },
  post: { backgroundColor: '#fff', marginTop: 14, borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#eceadf' },
  badge: { backgroundColor: '#eaf7c8', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center' },
  likeBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#faf9f3', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14 },
  commentsWrap: { paddingHorizontal: 16, paddingBottom: 14, borderTopWidth: 1, borderTopColor: '#f0eee3', paddingTop: 11 },
  commentInput: {
    flex: 1, backgroundColor: '#faf9f3', borderRadius: 99, borderWidth: 1, borderColor: '#eceadf',
    paddingVertical: 9, paddingHorizontal: 14, fontSize: 13, color: FOREST,
  },
  commentSend: { width: 36, height: 36, borderRadius: 18, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
