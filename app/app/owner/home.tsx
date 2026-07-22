import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Ring } from '../../src/components/ring';
import { RunCard } from '../../src/components/runcard';
import { Badge, Btn, Card, Monogram, Row, text } from '../../src/components/ui';
import { dog, myCards, runners } from '../../src/store';
import { colors } from '../../src/theme';

// Owner home = the dopamine hub. Leads with the dog's fitness, not chores.

export default function OwnerHome() {
  const pct = dog.weekKm / dog.weeklyGoalKm;
  const remaining = Math.max(dog.weeklyGoalKm - dog.weekKm, 0);
  const goalHit = pct >= 1;
  const latestCard = myCards.find((c) => c.run);

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={text.dim}>성수동 · 맑음 24°</Text>
            <Text style={[text.h1, { marginTop: 2 }]}>{dog.name} 보호자님</Text>
          </View>
          <Monogram char={dog.name[0]} bg={colors.volt} size={46} />
        </Row>

        {/* ---------- 주간 러닝 링 (dopamine hero) ---------- */}
        <Pressable onPress={() => router.push('/owner/dog')}>
          <Card dark style={{ marginTop: 18, alignItems: 'center', paddingVertical: 24 }}>
            <Ring pct={pct} size={200}>
              <View style={{ alignItems: 'center' }}>
                <Text style={{ fontSize: 44, fontWeight: '900', color: colors.volt, lineHeight: 48 }}>
                  {dog.weekKm}
                </Text>
                <Text style={{ fontSize: 12, color: '#9a987f' }}>/ {dog.weeklyGoalKm}km 이번 주</Text>
              </View>
            </Ring>

            <Text style={{ fontSize: 14, fontWeight: '700', color: colors.cream, marginTop: 16 }}>
              {goalHit
                ? `이번 주 목표 달성! ${dog.name} 최고예요`
                : `목표까지 ${remaining.toFixed(1)}km — 거의 다 왔어요`}
            </Text>

            <Row style={{ gap: 8, marginTop: 12 }}>
              <Badge label={`연속 ${dog.streakDays}일`} tone="red" />
              <Badge label="3회 완료" tone="ink" />
              <Badge label={`평균 7'20"`} tone="ink" />
            </Row>
          </Card>
        </Pressable>

        <Btn label="러닝 요청하기" variant="volt" style={{ marginTop: 14 }} onPress={() => router.push('/owner/request')} />

        {/* ---------- 최신 러닝 카드 ---------- */}
        <Row style={{ justifyContent: 'space-between', marginTop: 24, marginBottom: 10 }}>
          <Text style={text.h2}>{dog.name}의 최신 카드</Text>
          <Pressable onPress={() => router.push('/cards')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>마이 카드 ›</Text>
          </Pressable>
        </Row>
        {latestCard && (
          <Pressable onPress={() => router.push('/cards')} style={{ alignItems: 'center' }}>
            <RunCard card={latestCard} width={340} />
          </Pressable>
        )}

        {/* ---------- 인기 러너 ---------- */}
        <Row style={{ justifyContent: 'space-between', marginTop: 24, marginBottom: 10 }}>
          <Text style={text.h2}>내 주변 인기 러너</Text>
          <Text style={text.dim}>전체보기</Text>
        </Row>

        {runners.slice(0, 2).map((r) => (
          <Pressable key={r.id} onPress={() => router.push('/owner/matching')}>
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
      <BottomNav />
    </View>
  );
}
