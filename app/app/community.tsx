import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Monogram, Row } from '../src/components/ui';
import { posts, streakRanking } from '../src/store';
import { colors } from '../src/theme';

// 커뮤니티 — streak medals, filter chips, rich post cards, FAB, per mock.

const FOREST = '#132117';
const FILTERS = ['전체', '러너', '보호자', '질문', '팁 & 후기'];
const MEDALS = ['①', '②', '③'];

export default function Community() {
  const [filter, setFilter] = useState('전체');

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 60, paddingBottom: 30 }}>
        {/* header */}
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Row style={{ gap: 6 }}>
              <Text style={{ fontSize: 26, fontWeight: '900', color: FOREST }}>커뮤니티</Text>
              <Text style={{ fontSize: 14, color: '#5a7a3c', alignSelf: 'center' }}>❋</Text>
            </Row>
            <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 4 }}>함께 달리고, 함께 성장해요</Text>
          </View>
          <Pressable style={s.writeBtn}>
            <Text style={{ fontSize: 13, fontWeight: '800', color: '#fff' }}>＋ 글쓰기</Text>
          </Pressable>
        </Row>

        {/* streak ranking */}
        <View style={s.ranking}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 12 }}>
            <Row style={{ gap: 6 }}>
              <Text style={{ fontSize: 12, color: colors.tang }}>▲</Text>
              <Text style={{ fontSize: 13, fontWeight: '900', color: '#fff' }}>이번 주 스트릭 랭킹</Text>
            </Row>
            <Text style={{ fontSize: 11, color: '#b8c4ae' }}>더보기 ›</Text>
          </Row>
          <Row style={{ justifyContent: 'space-between' }}>
            {streakRanking.map((r, i) => (
              <Row key={r.name} style={{ gap: 7 }}>
                <Text style={{ fontSize: 16, color: i === 0 ? '#f2c94c' : i === 1 ? '#c8ccd0' : '#c99a6b' }}>{MEDALS[i]}</Text>
                <Monogram char={r.name[0]} bg={['#c9a86e', '#e8b04b', '#9b8bb4'][i]} size={34} />
                <View>
                  <Text style={{ fontSize: 12, fontWeight: '700', color: '#fff' }}>{r.name}</Text>
                  <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>{r.days}일</Text>
                </View>
              </Row>
            ))}
          </Row>
        </View>

        {/* filters */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginVertical: 16 }} contentContainerStyle={{ gap: 8 }}>
          {FILTERS.map((f) => (
            <Pressable key={f} onPress={() => setFilter(f)} style={[s.filter, filter === f && { backgroundColor: FOREST, borderColor: FOREST }]}>
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: filter === f ? '#fff' : '#3d453d' }}>{f}</Text>
            </Pressable>
          ))}
        </ScrollView>

        {/* posts */}
        {posts.map((post) => (
          <View key={post.id} style={s.post}>
            <Row style={{ gap: 10 }}>
              <Monogram char={post.char} bg={post.color} size={44} />
              <View style={{ flex: 1 }}>
                <Row style={{ gap: 6 }}>
                  <View style={[s.rolePill, post.roleBadge.includes('보호자') && { backgroundColor: '#fde8e3' }]}>
                    <Text style={{ fontSize: 9.5, fontWeight: '800', color: post.roleBadge.includes('보호자') ? '#d84a2f' : '#4a6d1f' }}>
                      {post.roleBadge}
                    </Text>
                  </View>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>{post.author}</Text>
                </Row>
                <Text style={{ fontSize: 11, color: colors.dim, marginTop: 3 }}>⌖ {post.when}</Text>
              </View>
              {post.streak != null && (
                <View style={s.streakPill}>
                  <Text style={{ fontSize: 10.5, fontWeight: '800', color: '#d84a2f' }}>▲ {post.streak}일 연속</Text>
                </View>
              )}
            </Row>

            {post.run && (
              <View style={s.runPill}>
                <Text style={s.runStat}>⌖ {post.run.km}</Text>
                <Text style={s.runStat}>◷ {post.run.time}</Text>
                <Text style={s.runStat}>⇢ {post.run.pace}</Text>
              </View>
            )}

            <Row style={{ gap: 12, marginTop: 10, alignItems: 'flex-start' }}>
              <Text style={{ flex: 1, fontSize: 13.5, color: '#3d453d', lineHeight: 21 }}>{post.body}</Text>
              {(post.photo || post.run) && (
                <View style={[s.photo, { backgroundColor: post.photo ? post.photo[0] : '#c9b68a' }]}>
                  {post.photo && (
                    <View style={s.playBtn}><Text style={{ fontSize: 11, color: '#fff' }}>▶</Text></View>
                  )}
                </View>
              )}
            </Row>

            {post.photo && (
              <Row style={{ gap: 6, marginTop: 10 }}>
                {['#바디캠', '#성수동', '#컨디션굿'].map((tag) => (
                  <View key={tag} style={s.hashtag}><Text style={{ fontSize: 10.5, fontWeight: '700', color: '#5a7a3c' }}>{tag}</Text></View>
                ))}
              </Row>
            )}

            {post.product && (
              <View style={s.productRow}>
                <View style={{ width: 34, height: 34, borderRadius: 9, backgroundColor: post.product.colors[0] }} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 12, fontWeight: '600', color: FOREST }}>{post.product.name}</Text>
                  <Text style={{ fontSize: 10.5, color: colors.dim }}>댕런 샵 · {post.product.price.toLocaleString()}원</Text>
                </View>
                <Pressable onPress={() => router.replace('/shop')} style={s.viewBtn}>
                  <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d453d' }}>보기</Text>
                </Pressable>
              </View>
            )}

            <Row style={{ gap: 18, marginTop: 12 }}>
              <Text style={{ fontSize: 12.5, color: '#d84a2f', fontWeight: '700' }}>♥ {post.likes}</Text>
              <Text style={s.action}>◒ {post.comments}</Text>
              <Text style={s.action}>↥ 공유</Text>
              <View style={{ flex: 1 }} />
              <Text style={s.action}>⊐</Text>
            </Row>
          </View>
        ))}
      </ScrollView>

      {/* FAB */}
      <Pressable style={s.fab}>
        <Text style={{ fontSize: 18, color: colors.volt }}>❋</Text>
      </Pressable>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  writeBtn: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 16, alignSelf: 'flex-start' },
  ranking: { backgroundColor: FOREST, borderRadius: 20, padding: 16, marginTop: 16 },
  filter: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 16, borderWidth: 1, borderColor: '#eceadf' },
  post: { backgroundColor: '#fff', borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#eceadf', marginBottom: 12 },
  rolePill: { backgroundColor: '#e3f0c4', borderRadius: 8, paddingVertical: 3, paddingHorizontal: 7, alignSelf: 'center' },
  streakPill: { backgroundColor: '#fde8e3', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'flex-start' },
  runPill: { flexDirection: 'row', gap: 14, backgroundColor: '#eef4e0', borderRadius: 12, paddingVertical: 9, paddingHorizontal: 13, marginTop: 12, alignSelf: 'flex-start' },
  runStat: { fontSize: 12.5, fontWeight: '900', color: '#3d5a2b' },
  photo: { width: 96, height: 96, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
  playBtn: { width: 30, height: 30, borderRadius: 15, backgroundColor: '#00000066', alignItems: 'center', justifyContent: 'center' },
  hashtag: { backgroundColor: '#eef4e0', borderRadius: 8, paddingVertical: 4, paddingHorizontal: 8 },
  productRow: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#faf9f3', borderRadius: 12, padding: 10, marginTop: 10 },
  viewBtn: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12, borderWidth: 1, borderColor: '#eceadf' },
  action: { fontSize: 12.5, color: '#75806f', fontWeight: '600' },
  fab: {
    position: 'absolute', right: 20, bottom: 100, width: 54, height: 54, borderRadius: 27,
    backgroundColor: FOREST, alignItems: 'center', justifyContent: 'center',
    shadowColor: FOREST, shadowOpacity: 0.4, shadowRadius: 12, shadowOffset: { width: 0, height: 6 }, elevation: 8,
  },
});
