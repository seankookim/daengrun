import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { Badge, Btn, Card, Monogram, Row, StatBlock, text } from '../../src/components/ui';
import { dog, runners } from '../../src/store';
import { colors } from '../../src/theme';

export default function OwnerHome() {
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <View>
          <Text style={text.dim}>성수동 · 맑음 24°</Text>
          <Text style={[text.h1, { marginTop: 2 }]}>{dog.name} 보호자님</Text>
        </View>
        <Monogram char={dog.name[0]} bg={colors.volt} size={46} />
      </Row>

      <Card dark style={{ marginTop: 18 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={{ fontSize: 12, color: '#9a987f' }}>이번 주 {dog.name}의 러닝</Text>
            <Text style={{ fontSize: 32, fontWeight: '900', color: colors.volt, marginTop: 4 }}>
              {dog.weekKm} <Text style={{ fontSize: 16 }}>km</Text>
            </Text>
          </View>
          <Text style={{ fontSize: 12, color: '#9a987f', textAlign: 'right', lineHeight: 20 }}>
            3회 완료{'\n'}평균 페이스 7'20"
          </Text>
        </Row>
        <View style={{ height: 1, backgroundColor: '#33371f', marginVertical: 12 }} />
        <Row style={{ justifyContent: 'space-between' }}>
          <Badge label={`연속 ${dog.streakDays}일 러닝 중`} tone="red" />
          <Text style={{ fontSize: 11, color: '#9a987f' }}>{dog.name} 프로필 ›</Text>
        </Row>
      </Card>

      <Btn label="러닝 요청하기" variant="volt" style={{ marginTop: 14 }} onPress={() => router.push('/request')} />

      <Row style={{ justifyContent: 'space-between', marginTop: 24, marginBottom: 10 }}>
        <Text style={text.h2}>내 주변 인기 러너</Text>
        <Text style={text.dim}>전체보기</Text>
      </Row>

      {runners.slice(0, 2).map((r) => (
        <Pressable key={r.id} onPress={() => router.push('/matching')}>
          <Card style={{ marginBottom: 8 }}>
            <Row style={{ gap: 14 }}>
              <Monogram char={r.char} bg={r.color} />
              <View style={{ flex: 1 }}>
                <Row style={{ gap: 6 }}>
                  <Text style={{ fontSize: 15, fontWeight: '700' }}>{r.name}</Text>
                  {r.badges.map((b) => <Badge key={b} label={b} tone={b === '훈련사' ? 'red' : 'green'} />)}
                </Row>
                <Text style={[text.dim, { marginTop: 3 }]}>
                  ★ {r.rating} · 러닝 {r.runs}회 · 성수동 {r.distanceKm}km
                </Text>
              </View>
              <Text style={{ color: colors.dim, fontSize: 18 }}>›</Text>
            </Row>
          </Card>
        </Pressable>
      ))}
    </ScrollView>
  );
}
