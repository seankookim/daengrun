import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { Badge, Card, Monogram, Row, text } from '../../src/components/ui';
import { draft, fmtWon, priceForRunner, runners } from '../../src/store';
import { colors } from '../../src/theme';

export default function Matching() {
  const pick = (id: string) => {
    draft.runnerId = id;
    router.push('/live'); // 실제로는 수락 대기 → live. 목업에서는 바로 이동.
  };

  const recommended = runners.find((r) => r.match)!;
  const others = runners.filter((r) => !r.match);

  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 14 }}>
        <Pressable onPress={() => router.back()}><Text style={{ fontSize: 24 }}>‹</Text></Pressable>
        <Text style={text.h2}>러너 선택</Text>
        <View style={{ width: 24 }} />
      </Row>

      <Text style={[text.dim, { marginBottom: 14 }]}>
        보호자님과 러너의 선호도를 양방향으로 분석했어요
      </Text>

      <Pressable onPress={() => pick(recommended.id)}>
        <Card style={{ borderWidth: 2, borderColor: colors.ink }}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 12 }}>
            <View style={{ backgroundColor: colors.ink, borderRadius: 99, paddingVertical: 5, paddingHorizontal: 12 }}>
              <Text style={{ fontSize: 11, fontWeight: '700', color: colors.volt }}>
                댕런 추천 · {recommended.match!.total}% 매치
              </Text>
            </View>
            <Text style={text.dim}>왜 추천했나요?</Text>
          </Row>
          <Row style={{ gap: 14 }}>
            <Monogram char={recommended.char} bg={recommended.color} size={56} />
            <View style={{ flex: 1 }}>
              <Row style={{ gap: 6 }}>
                <Text style={{ fontSize: 16, fontWeight: '700' }}>{recommended.name}</Text>
                {recommended.badges.map((b) => <Badge key={b} label={b} />)}
              </Row>
              <Text style={[text.dim, { marginTop: 3 }]}>
                ★ {recommended.rating} ({recommended.reviews}) · 러닝 {recommended.runs}회
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={{ fontSize: 18, fontWeight: '900' }}>{fmtWon(priceForRunner(recommended))}</Text>
              <Text style={text.dim}>{recommended.distanceKm}km 거리</Text>
            </View>
          </Row>
          <View style={{ height: 1, backgroundColor: colors.line, marginVertical: 12 }} />
          <View style={{ gap: 10 }}>
            {recommended.match!.reasons.map((reason) => (
              <View key={reason.label}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Text style={[text.dim, { flex: 1 }]}>{reason.label}</Text>
                  <Text style={{ fontSize: 12, fontWeight: '700' }}>{reason.pct}%</Text>
                </Row>
                <View style={{ height: 6, borderRadius: 99, backgroundColor: colors.line, marginTop: 5, overflow: 'hidden' }}>
                  <View style={{ height: 6, borderRadius: 99, width: `${reason.pct}%`, backgroundColor: colors.voltDeep }} />
                </View>
              </View>
            ))}
          </View>
        </Card>
      </Pressable>

      <Text style={[text.dim, { marginTop: 16, marginBottom: 8 }]}>다른 러너도 볼 수 있어요</Text>

      {others.map((r) => (
        <Pressable key={r.id} onPress={() => pick(r.id)}>
          <Card style={{ marginBottom: 8 }}>
            <Row style={{ gap: 14 }}>
              <Monogram char={r.char} bg={r.color} size={56} />
              <View style={{ flex: 1 }}>
                <Row style={{ gap: 6 }}>
                  <Text style={{ fontSize: 16, fontWeight: '700' }}>{r.name}</Text>
                  {r.badges.map((b) => <Badge key={b} label={b} tone={b === '훈련사' ? 'red' : 'green'} />)}
                </Row>
                <Text style={[text.dim, { marginTop: 3 }]}>
                  ★ {r.rating} ({r.reviews}) · 러닝 {r.runs}회
                </Text>
              </View>
              <View style={{ alignItems: 'flex-end' }}>
                <Text style={{ fontSize: 18, fontWeight: '900' }}>{fmtWon(priceForRunner(r))}</Text>
                <Text style={text.dim}>{r.distanceKm}km 거리</Text>
              </View>
            </Row>
          </Card>
        </Pressable>
      ))}
    </ScrollView>
  );
}
