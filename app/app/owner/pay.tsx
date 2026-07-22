import { router } from 'expo-router';
import { ScrollView, Text, View } from 'react-native';
import { Badge, Btn, Card, Row, text } from '../../src/components/ui';
import { draft, draftTotal, fmtWon } from '../../src/store';
import { colors, pricing } from '../../src/theme';

export default function Pay() {
  const actualKm = draft.km + 0.02; // mock: 실제 뛴 거리
  const addonSum = draft.addons.reduce((s, k) => s + pricing.addons[k].price, 0);

  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64, paddingBottom: 40 }}>
      <Text style={[text.h2, { textAlign: 'center', marginBottom: 16 }]}>러닝 완료</Text>

      <Card dark style={{ alignItems: 'center', padding: 26 }}>
        <Text style={{ fontSize: 12, color: '#9a987f', letterSpacing: 2 }}>TODAY'S RUN</Text>
        <Text style={{ fontSize: 48, fontWeight: '900', color: colors.volt, marginVertical: 8 }}>
          {actualKm.toFixed(2)} km
        </Text>
        <Text style={{ fontSize: 13, color: '#9a987f' }}>34분 12초 · 평균 페이스 6'49"</Text>
        <Row style={{ gap: 8, marginTop: 16 }}>
          <Badge label="배변 2회" tone="ink" />
          <Badge label="물 급여 완료" tone="ink" />
          <Badge label="사진 4장" tone="ink" />
        </Row>
      </Card>

      <Card style={{ marginTop: 14 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={text.dim}>기본요금</Text>
          <Text style={text.dim}>{fmtWon(pricing.baseFare)}</Text>
        </Row>
        <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
          <Text style={text.dim}>거리요금 {actualKm.toFixed(2)}km × {pricing.perKm.toLocaleString()}원</Text>
          <Text style={text.dim}>{fmtWon(Math.round(actualKm * pricing.perKm))}</Text>
        </Row>
        {addonSum > 0 && (
          <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
            <Text style={text.dim}>프리미엄 옵션</Text>
            <Text style={text.dim}>{fmtWon(addonSum)}</Text>
          </Row>
        )}
        <View style={{ height: 1, backgroundColor: colors.line, marginVertical: 12 }} />
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={{ fontWeight: '700' }}>결제금액</Text>
          <Text style={{ fontSize: 22, fontWeight: '900' }}>
            {fmtWon(pricing.baseFare + Math.round(actualKm * pricing.perKm) + addonSum)}
          </Text>
        </Row>
        <Text style={[text.dim, { marginTop: 8, fontSize: 11 }]}>카카오페이 ···· 3841</Text>
      </Card>

      <Btn label="결제하고 리뷰 남기기" variant="volt" style={{ marginTop: 16 }} onPress={() => router.push('/owner/review')} />
    </ScrollView>
  );
}
