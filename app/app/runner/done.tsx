import { router } from 'expo-router';
import { Text, View } from 'react-native';
import { Btn, Card, text } from '../../src/components/ui';
import { runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

const fmt = (sec: number) =>
  `${Math.floor(sec / 60)}분 ${String(Math.floor(sec % 60)).padStart(2, '0')}초`;

export default function RunDone() {
  const req = runRequests[0];

  return (
    <View style={{ flex: 1, justifyContent: 'center', padding: 22 }}>
      <Text style={[text.h1, { textAlign: 'center' }]}>
        {runResult.completed ? '러닝 완료!' : '러닝 종료'}
      </Text>
      <Text style={[text.dim, { textAlign: 'center', marginTop: 8 }]}>
        {req.dogName}를 보호자에게 안전하게 인계해 주세요
      </Text>

      <Card dark style={{ marginTop: 24, alignItems: 'center', padding: 26 }}>
        <Text style={{ fontSize: 12, color: '#8fa0b3', letterSpacing: 2 }}>오늘의 수익</Text>
        <Text style={{ fontSize: 44, fontWeight: '900', color: colors.volt, marginTop: 8 }}>
          +{runResult.payout.toLocaleString()}원
        </Text>
        <Text style={{ fontSize: 12, color: '#8fa0b3', marginTop: 8 }}>
          {runResult.km.toFixed(2)}km · {fmt(runResult.sec)} · {req.dogName}
        </Text>
        {!runResult.completed && (
          <Text style={{ fontSize: 11, color: '#c9a15e', marginTop: 10, textAlign: 'center' }}>
            조기 종료 — 실제 뛴 거리만큼 정산됩니다{'\n'}(개 컨디션 사유는 완주율에 반영되지 않아요)
          </Text>
        )}
      </Card>

      <Text style={[text.dim, { textAlign: 'center', marginTop: 14 }]}>수익은 매주 수요일 정산됩니다</Text>
      <Btn label="홈으로" style={{ marginTop: 20 }} onPress={() => router.dismissTo('/runner/home')} />
    </View>
  );
}
