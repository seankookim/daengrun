import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Badge, Card, Chip, Monogram, Row, text } from '../../src/components/ui';
import { posts, streakRanking } from '../../src/store';
import { colors } from '../../src/theme';

export default function Community() {
  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 14 }}>
          <Pressable onPress={() => router.replace('/owner/home')}><Text style={{ fontSize: 24 }}>‹</Text></Pressable>
          <Text style={text.h2}>커뮤니티</Text>
          <Text style={{ fontSize: 18 }}>＋</Text>
        </Row>

        <Card dark style={{ paddingVertical: 14 }}>
          <Text style={{ fontSize: 11, letterSpacing: 2, color: '#9a987f' }}>이번 주 스트릭 랭킹</Text>
          <Row style={{ justifyContent: 'space-between', marginTop: 10 }}>
            {streakRanking.map((r, i) => (
              <Text key={r.name} style={{ fontSize: 12, color: colors.cream }}>
                {i + 1}. {r.name} <Text style={{ color: colors.volt, fontWeight: '800' }}>{r.days}일</Text>
              </Text>
            ))}
          </Row>
        </Card>

        {posts.map((p) => (
          <Card key={p.id} style={{ marginTop: 12 }}>
            <Row style={{ gap: 10 }}>
              <Monogram char={p.char} bg={p.color} size={38} />
              <View style={{ flex: 1 }}>
                <Row style={{ gap: 6 }}>
                  <Text style={{ fontSize: 13, fontWeight: '700' }}>{p.author}</Text>
                  <Badge label={p.roleBadge} tone={p.roleBadge.includes('보호자') ? 'red' : 'green'} />
                </Row>
                <Text style={{ fontSize: 11, color: colors.dim }}>{p.when}</Text>
              </View>
              {p.streak != null && <Badge label={`${p.streak}일 연속`} tone="red" />}
            </Row>

            {p.run && (
              <View style={{ marginTop: 12, borderRadius: 14, backgroundColor: '#e7e9dc', padding: 14 }}>
                <View style={{ height: 4, borderRadius: 99, backgroundColor: colors.tang, width: '85%' }} />
                <Row style={{ gap: 14, marginTop: 10 }}>
                  <Text style={{ fontSize: 15, fontWeight: '900' }}>{p.run.km}</Text>
                  <Text style={{ fontSize: 15, fontWeight: '900' }}>{p.run.pace}</Text>
                  <Text style={{ fontSize: 15, fontWeight: '900' }}>{p.run.time}</Text>
                </Row>
              </View>
            )}

            {p.photo && (
              <View style={{ marginTop: 12, borderRadius: 14, height: 150, backgroundColor: p.photo[0], justifyContent: 'flex-end', padding: 12 }}>
                <Text style={{ fontSize: 12, color: '#fff', fontWeight: '600' }}>{p.body}</Text>
              </View>
            )}

            {!p.photo && <Text style={[text.body, { marginTop: 10 }]}>{p.body}</Text>}

            {p.product && (
              <Card style={{ marginTop: 10, backgroundColor: '#faf8f0', paddingVertical: 10 }}>
                <Row style={{ gap: 10 }}>
                  <View style={{ width: 36, height: 36, borderRadius: 10, backgroundColor: p.product.colors[0] }} />
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontSize: 12, fontWeight: '500' }}>{p.product.name}</Text>
                    <Text style={{ fontSize: 11, color: colors.dim }}>댕런 샵 · {p.product.price.toLocaleString()}원</Text>
                  </View>
                  <Chip label="보기" onPress={() => router.replace('/owner/shop')} />
                </Row>
              </Card>
            )}

            <Row style={{ gap: 16, marginTop: 12 }}>
              <Text style={text.dim}>♥ {p.likes}</Text>
              <Text style={text.dim}>댓글 {p.comments}</Text>
              <Text style={text.dim}>공유</Text>
            </Row>
          </Card>
        ))}
      </ScrollView>
      <BottomNav role="owner" />
    </View>
  );
}
