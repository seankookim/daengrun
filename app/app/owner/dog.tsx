import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { Badge, Card, Chip, Monogram, Row, StatBlock, text } from '../../src/components/ui';
import { dog } from '../../src/store';
import { colors } from '../../src/theme';

const PREFS = ['흙길 선호', "페이스 7' 내외", '저녁 시간대', '서울숲 코스'];
const PHOTOS: [string, string][] = [['#cfe3b8', '#9ab87a'], ['#e8d5b0', '#c9a86e'], ['#b8ccd8', '#7fa3b8']];

export default function DogProfile() {
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
      <View style={{ height: 210, backgroundColor: colors.volt }}>
        <Pressable
          onPress={() => router.back()}
          style={{ position: 'absolute', top: 56, left: 16, backgroundColor: '#fff', borderRadius: 12, paddingVertical: 6, paddingHorizontal: 12 }}
        >
          <Text style={{ fontSize: 20 }}>‹</Text>
        </Pressable>
        <View style={{ position: 'absolute', bottom: 14, right: 18 }}>
          <Badge label={`연속 ${dog.streakDays}일 러닝`} tone="red" />
        </View>
        <View style={{ position: 'absolute', bottom: -36, left: 22, borderWidth: 4, borderColor: colors.cream, borderRadius: 32 }}>
          <Monogram char={dog.name[0]} bg={colors.ink} size={88} />
        </View>
      </View>

      <View style={{ padding: 22, paddingTop: 48 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={text.h1}>{dog.name}</Text>
            <Text style={[text.dim, { marginTop: 2 }]}>
              {dog.breed} · {dog.age}살 · 수컷(중성화) · {dog.weightKg}kg
            </Text>
          </View>
          <Chip label="수정" />
        </Row>

        <Row style={{ gap: 6, marginTop: 12, flexWrap: 'wrap' }}>
          <Badge label="종합백신 완료" />
          <Badge label="광견병 접종" />
          <Badge label="펫보험 가입" />
        </Row>

        <Card dark style={{ marginTop: 16 }}>
          <Row style={{ justifyContent: 'space-around' }}>
            <StatBlock value="86.2" label="누적 km" />
            <StatBlock value="21" label="총 러닝" />
            <StatBlock value="7'18&quot;" label="평균 페이스" />
          </Row>
        </Card>

        <Text style={[text.label, { marginTop: 18, marginBottom: 8 }]}>러너에게 전달되는 성향 메모</Text>
        <Card>
          <Text style={text.body}>{dog.memo}</Text>
        </Card>

        <Text style={[text.label, { marginTop: 18, marginBottom: 8 }]}>선호 러닝 조건</Text>
        <Row style={{ gap: 6, flexWrap: 'wrap' }}>
          {PREFS.map((p) => <Chip key={p} label={p} selected />)}
        </Row>

        <Text style={[text.label, { marginTop: 18, marginBottom: 8 }]}>최근 러닝 사진</Text>
        <Row style={{ gap: 8 }}>
          {PHOTOS.map(([c], i) => (
            <View key={i} style={{ flex: 1, height: 80, borderRadius: 14, backgroundColor: c }} />
          ))}
        </Row>
      </View>
    </ScrollView>
  );
}
