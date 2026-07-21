import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { Btn, Card, Chip, Row, text } from '../../src/components/ui';
import { AddonKey, dog, draft, fmtWon } from '../../src/store';
import { colors, pricing } from '../../src/theme';

const DISTANCES = [3, 5, 7];
const PACES = ["가볍게 8'+", "보통 7'", "신나게 6'"];

export default function Request() {
  const [km, setKm] = useState(draft.km);
  const [pace, setPace] = useState(draft.pace);
  const [addons, setAddons] = useState<AddonKey[]>(draft.addons);

  const addonSum = addons.reduce((s, k) => s + pricing.addons[k].price, 0);
  const total = pricing.baseFare + km * pricing.perKm + addonSum;

  const toggleAddon = (k: AddonKey) =>
    setAddons((a) => (a.includes(k) ? a.filter((x) => x !== k) : [...a, k]));

  const next = () => {
    Object.assign(draft, { km, pace, addons });
    router.push('/matching');
  };

  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 18 }}>
        <Pressable onPress={() => router.back()}><Text style={{ fontSize: 24 }}>‹</Text></Pressable>
        <Text style={text.h2}>러닝 요청</Text>
        <View style={{ width: 24 }} />
      </Row>

      <Text style={text.label}>누가 달릴까요?</Text>
      <Row style={{ gap: 8, marginTop: 8 }}>
        <Chip label={`${dog.name} · ${dog.breed} · ${dog.weightKg}kg`} selected />
        <Chip label="+ 추가" />
      </Row>

      <Text style={[text.label, { marginTop: 20 }]}>거리</Text>
      <Row style={{ gap: 8, marginTop: 8 }}>
        {DISTANCES.map((d) => (
          <Chip key={d} label={`${d}km`} selected={km === d} onPress={() => setKm(d)} />
        ))}
      </Row>

      <Text style={[text.label, { marginTop: 20 }]}>페이스</Text>
      <Row style={{ gap: 8, marginTop: 8 }}>
        {PACES.map((p) => (
          <Chip key={p} label={p} selected={pace === p} onPress={() => setPace(p)} />
        ))}
      </Row>

      <Text style={[text.label, { marginTop: 20 }]}>언제 달릴까요?</Text>
      <Card style={{ marginTop: 8, paddingVertical: 14 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={{ fontSize: 14, fontWeight: '500' }}>오늘 오후 6:30</Text>
          <Text style={text.dim}>변경 ›</Text>
        </Row>
      </Card>

      <Text style={[text.label, { marginTop: 20 }]}>픽업 장소</Text>
      <Card style={{ marginTop: 8, paddingVertical: 14 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={{ fontSize: 14, fontWeight: '500' }}>서울숲 2번 출입구</Text>
          <Text style={text.dim}>지도 ›</Text>
        </Row>
      </Card>

      <Text style={[text.label, { marginTop: 22 }]}>
        프리미엄 옵션 <Text style={{ fontWeight: '400', color: colors.dim, fontSize: 11 }}>· 원하는 만큼 추가하세요</Text>
      </Text>
      <View style={{ gap: 8, marginTop: 8 }}>
        {(Object.keys(pricing.addons) as AddonKey[]).map((k) => {
          const a = pricing.addons[k];
          const sel = addons.includes(k);
          return (
            <Pressable
              key={k}
              onPress={() => toggleAddon(k)}
              style={{
                flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
                padding: 14, borderRadius: 14, borderWidth: 1.5,
                borderColor: sel ? colors.ink : colors.line,
                backgroundColor: sel ? '#f4f8e6' : '#fff',
              }}
            >
              <Text style={{ fontSize: 13, fontWeight: '700' }}>{a.label}</Text>
              <Text style={{ fontSize: 14, fontWeight: '800', color: colors.voltDeep }}>+{a.price.toLocaleString()}</Text>
            </Pressable>
          );
        })}
      </View>

      <Card style={{ marginTop: 18, backgroundColor: '#faf8f0' }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={text.dim}>기본요금</Text>
          <Text style={text.dim}>{fmtWon(pricing.baseFare)}</Text>
        </Row>
        <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
          <Text style={text.dim}>거리요금 {km}km × {pricing.perKm.toLocaleString()}원</Text>
          <Text style={text.dim}>{fmtWon(km * pricing.perKm)}</Text>
        </Row>
        {addonSum > 0 && (
          <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
            <Text style={text.dim}>프리미엄 옵션</Text>
            <Text style={text.dim}>{fmtWon(addonSum)}</Text>
          </Row>
        )}
        <View style={{ height: 1, backgroundColor: colors.line, marginVertical: 12 }} />
        <Row style={{ justifyContent: 'space-between' }}>
          <Text style={{ fontWeight: '700' }}>예상 결제금액</Text>
          <Text style={{ fontSize: 22, fontWeight: '900' }}>{fmtWon(total)}</Text>
        </Row>
      </Card>

      <Btn label="러너 찾기" style={{ marginTop: 16 }} onPress={next} />
    </ScrollView>
  );
}
