import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Badge, Card, Monogram, Row, StatBlock, text } from '../../src/components/ui';
import { runnerStats, runRequests } from '../../src/store';
import { colors } from '../../src/theme';

export default function RunnerHome() {
  const [available, setAvailable] = useState(true);

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={text.dim}>러너 모드</Text>
            <Text style={[text.h1, { marginTop: 2 }]}>김민준 님</Text>
          </View>
          <Pressable
            onPress={() => setAvailable((v) => !v)}
            style={{
              width: 56, height: 32, borderRadius: 99, padding: 3,
              backgroundColor: available ? colors.voltDeep : '#d8d4c4',
              alignItems: available ? 'flex-end' : 'flex-start',
            }}
          >
            <View style={{ width: 26, height: 26, borderRadius: 13, backgroundColor: '#fff' }} />
          </Pressable>
        </Row>

        <Card dark style={{ marginTop: 18 }}>
          <Row style={{ justifyContent: 'space-around' }}>
            <StatBlock value={runnerStats.weekEarnings.toLocaleString()} label="이번 주 수익(원)" />
            <StatBlock value={String(runnerStats.weekRuns)} label="완료 러닝" />
            <StatBlock value={String(runnerStats.weekKm)} label="km" />
          </Row>
        </Card>

        <Row style={{ justifyContent: 'space-between', marginTop: 24, marginBottom: 10 }}>
          <Text style={text.h2}>새 러닝 요청</Text>
          <Badge label={`${runRequests.length}건`} tone="red" />
        </Row>

        {runRequests.map((req, i) => (
          <Pressable key={req.id} onPress={() => router.push('/runner/detail')} disabled={i > 0}>
            <Card style={[{ marginBottom: 8 }, i === 0 ? { borderWidth: 2, borderColor: colors.ink } : { opacity: 0.7 }]}>
              <Row style={{ gap: 12 }}>
                <Monogram char={req.dogChar} bg={req.dogColor} size={48} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 15, fontWeight: '700' }}>
                    {req.dogName} · {req.breed} {req.weightKg}kg
                  </Text>
                  <Text style={[text.dim, { marginTop: 3 }]}>
                    {req.when} · {req.place} · {req.km}km · 페이스 {req.pace}
                  </Text>
                </View>
              </Row>
              <View style={{ height: 1, backgroundColor: colors.line, marginVertical: 12 }} />
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={text.dim}>픽업까지 {req.pickupKm}km</Text>
                <Text style={{ fontSize: 18, fontWeight: '900', color: colors.voltDeep }}>
                  +{req.payout.toLocaleString()}원
                </Text>
              </Row>
            </Card>
          </Pressable>
        ))}
      </ScrollView>
      <BottomNav role="runner" />
    </View>
  );
}
