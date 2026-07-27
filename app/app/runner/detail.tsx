import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';
import { Btn, Card, Monogram, Row, text } from '../../src/components/ui';
import { runRequests } from '../../src/store';
import { colors } from '../../src/theme';

export default function RequestDetail() {
  const req = runRequests[0];

  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 14 }}>
        <Pressable onPress={() => router.back()}><Text style={{ fontSize: 24 }}>‹</Text></Pressable>
        <Text style={text.h2}>요청 상세</Text>
        <View style={{ width: 24 }} />
      </Row>

      <Card>
        <Row style={{ gap: 14 }}>
          <Monogram char={req.dogChar} bg={req.dogColor} size={60} />
          <View>
            <Text style={{ fontSize: 17, fontWeight: '700' }}>{req.dogName}</Text>
            <Text style={[text.dim, { marginTop: 3 }]}>
              {req.breed} · 3살 · {req.weightKg}kg · 중성화 O
            </Text>
          </View>
        </Row>
        {req.memo && (
          <>
            <View style={{ height: 1, backgroundColor: colors.line, marginVertical: 12 }} />
            <Text style={[text.label, { marginBottom: 4 }]}>보호자 메모</Text>
            <Text style={text.body}>{req.memo}</Text>
          </>
        )}
      </Card>

      <Card style={{ marginTop: 10 }}>
        {[
          ['일시', req.when],
          ['픽업', `${req.place} 2번 출입구`],
          ['코스', `${req.km}km · 보호자 지정 코스`],
          ['페이스', `보통 ${req.pace}00"`],
        ].map(([k, v]) => (
          <Row key={k} style={{ justifyContent: 'space-between', marginTop: k === '일시' ? 0 : 8 }}>
            <Text style={text.dim}>{k}</Text>
            <Text style={{ fontSize: 13, fontWeight: '700' }}>{v}</Text>
          </Row>
        ))}
      </Card>

      <Card style={{ marginTop: 10, backgroundColor: '#faf8f0' }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={text.dim}>예상 수익 (수수료 20% 제외)</Text>
          <Text style={{ fontSize: 22, fontWeight: '900', color: colors.voltDeep }}>
            {req.payout.toLocaleString()}원
          </Text>
        </Row>
      </Card>

      <Btn
        label="수락하기 (데모)"
        variant="volt"
        style={{ marginTop: 16 }}
        onPress={() => {
          Alert.alert('데모 수락', '이 카드는 데모예요 — 서버에 반영되지 않아요.\n실요청은 요청 탭의 ● LIVE 카드에서 수락하세요');
          router.push('/runner/meetup');
        }}
      />
      <Btn label="거절" variant="ghost" style={{ marginTop: 8 }} onPress={() => router.back()} />
    </ScrollView>
  );
}
