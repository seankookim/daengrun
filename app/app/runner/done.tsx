import { router } from 'expo-router';
import { Text, View } from 'react-native';
import { Btn, Card, text } from '../../src/components/ui';
import { runRequests } from '../../src/store';
import { colors } from '../../src/theme';

export default function RunDone() {
  const req = runRequests[0];

  return (
    <View style={{ flex: 1, justifyContent: 'center', padding: 22 }}>
      <Text style={[text.h1, { textAlign: 'center' }]}>러닝 완료!</Text>
      <Text style={[text.dim, { textAlign: 'center', marginTop: 8 }]}>
        {req.dogName}를 보호자에게 안전하게 인계해 주세요
      </Text>

      <Card dark style={{ marginTop: 24, alignItems: 'center', padding: 26 }}>
        <Text style={{ fontSize: 12, color: '#9a987f', letterSpacing: 2 }}>오늘의 수익</Text>
        <Text style={{ fontSize: 44, fontWeight: '900', color: colors.volt, marginTop: 8 }}>
          +{req.payout.toLocaleString()}원
        </Text>
        <Text style={{ fontSize: 12, color: '#9a987f', marginTop: 8 }}>
          {req.km}.02km · 34분 12초 · {req.dogName}
        </Text>
      </Card>

      <Text style={[text.dim, { textAlign: 'center', marginTop: 14 }]}>수익은 매주 수요일 정산됩니다</Text>
      <Btn label="홈으로" style={{ marginTop: 20 }} onPress={() => router.dismissTo('/runner/home')} />
    </View>
  );
}
