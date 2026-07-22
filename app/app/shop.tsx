import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { products } from '../src/store';
import { colors } from '../src/theme';

// 댕런 샵 — member banner, category chips, pastel product cards, per mock.

const FOREST = '#132117';
const CATS = ['전체', '간식', '용품', '의류', '영양제'];

export default function Shop() {
  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 16 }}>
          <Pressable onPress={() => router.replace(homePath())} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>댕런 샵</Text>
          <Pressable style={s.circleBtn} onPress={() => Alert.alert('장바구니', '장바구니 (목업)')}>
            <Text style={{ fontSize: 15, color: FOREST }}>◱</Text>
          </Pressable>
        </Row>

        {/* member banner */}
        <View style={s.banner}>
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 6 }}>
              <Text style={{ fontSize: 11, color: colors.volt }}>♛</Text>
              <Text style={{ fontSize: 11, fontWeight: '800', letterSpacing: 2, color: colors.volt }}>MEMBER</Text>
            </Row>
            <Text style={{ fontSize: 18, fontWeight: '900', color: '#fff', marginTop: 6 }}>
              멤버는 전 상품 <Text style={{ color: colors.volt }}>10%</Text> 할인
            </Text>
            <Text style={{ fontSize: 12, color: '#b8c4ae', marginTop: 6 }}>이번 달 러닝 12.4km — 4,900P 적립됨</Text>
          </View>
          <View style={s.bannerGo}><Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>→</Text></View>
        </View>

        {/* categories */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginVertical: 16 }} contentContainerStyle={{ gap: 8 }}>
          {CATS.map((c, i) => (
            <View key={c} style={[s.cat, i === 0 && { backgroundColor: FOREST, borderColor: FOREST }]}>
              <Text style={{ fontSize: 13, fontWeight: '700', color: i === 0 ? '#fff' : '#3d453d' }}>{c}</Text>
            </View>
          ))}
        </ScrollView>

        {/* product grid */}
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
          {products.map((p) => (
            <Pressable key={p.id} style={[s.prod, { backgroundColor: p.colors[0] }]} onPress={() => Alert.alert(p.name, '상품 상세 (목업)')}>
              <Text style={{ fontSize: 11, fontWeight: '900', color: p.fg }}>{p.tag}</Text>
              <Text style={s.prodName} numberOfLines={2}>{p.name}</Text>
              <Text style={{ fontSize: 10.5, color: '#00000066', marginTop: 3 }}>{p.collab}</Text>
              {/* product visual placeholder */}
              <View style={s.prodVisual}>
                <Text style={{ fontSize: 30, fontWeight: '900', color: `${p.fg}33` }}>{p.tag}</Text>
              </View>
              <Row style={{ justifyContent: 'space-between', marginTop: 'auto' }}>
                <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{p.price.toLocaleString()}원</Text>
                <Pressable style={s.addBtn} onPress={() => Alert.alert('담기', `${p.name} 담김 (목업)`)}>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt }}>+</Text>
                </Pressable>
              </Row>
            </Pressable>
          ))}
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  banner: { flexDirection: 'row', alignItems: 'center', backgroundColor: FOREST, borderRadius: 20, padding: 18 },
  bannerGo: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
  cat: { borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18, backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf' },
  prod: { width: '47.5%', borderRadius: 20, padding: 14, minHeight: 210 },
  prodName: { fontSize: 14.5, fontWeight: '900', color: FOREST, marginTop: 6, lineHeight: 20 },
  prodVisual: { flex: 1, alignItems: 'center', justifyContent: 'center', marginVertical: 8 },
  addBtn: { width: 30, height: 30, borderRadius: 15, backgroundColor: FOREST, alignItems: 'center', justifyContent: 'center' },
});
