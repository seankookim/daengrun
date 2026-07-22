import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { Card, Chip, Row, text } from '../src/components/ui';
import { products } from '../src/store';
import { colors } from '../src/theme';

const CATS = ['전체', '간식', '용품', '의류', '영양제'];

export default function Shop() {
  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 14 }}>
          <Pressable onPress={() => router.replace(homePath())}><Text style={{ fontSize: 24 }}>‹</Text></Pressable>
          <Text style={text.h2}>댕런 샵</Text>
          <View style={{ width: 24 }} />
        </Row>

        <Card dark style={{ paddingVertical: 14 }}>
          <Row style={{ justifyContent: 'space-between' }}>
            <View>
              <Text style={{ fontSize: 12, color: colors.cream, lineHeight: 19 }}>
                멤버는 전 상품 <Text style={{ color: colors.volt, fontWeight: '800' }}>10% 할인</Text>
              </Text>
              <Text style={{ fontSize: 11, color: '#8fa0b3', marginTop: 2 }}>이번 달 러닝 12.4km — 4,900P 적립됨</Text>
            </View>
            <View style={{ backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10, alignSelf: 'center' }}>
              <Text style={{ fontSize: 11, fontWeight: '800', color: colors.ink }}>MEMBER</Text>
            </View>
          </Row>
        </Card>

        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginVertical: 14 }} contentContainerStyle={{ gap: 8 }}>
          {CATS.map((c, i) => <Chip key={c} label={c} selected={i === 0} />)}
        </ScrollView>

        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
          {products.map((p) => (
            <Card key={p.id} style={{ width: '47%', padding: 0, overflow: 'hidden' }}>
              <View style={{ height: 100, backgroundColor: p.colors[0], alignItems: 'center', justifyContent: 'center' }}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: p.fg, letterSpacing: 1 }}>{p.tag}</Text>
              </View>
              <View style={{ padding: 12 }}>
                <Text style={{ fontSize: 10, color: colors.dim }}>{p.collab}</Text>
                <Text style={{ fontSize: 12, fontWeight: '500', marginTop: 2 }} numberOfLines={2}>{p.name}</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', marginTop: 5 }}>{p.price.toLocaleString()}원</Text>
              </View>
            </Card>
          ))}
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}
