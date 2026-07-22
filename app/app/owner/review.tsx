import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { Btn, Chip, Row, text } from '../../src/components/ui';
import { colors } from '../../src/theme';

const TAGS = ['시간 약속을 잘 지켜요', '우리 아이가 좋아해요', '소통이 빨라요', '사진을 잘 보내줘요'];

export default function Review() {
  const [stars, setStars] = useState(0);
  const [tags, setTags] = useState<string[]>([]);

  const toggle = (tag: string) =>
    setTags((prev) => (prev.includes(tag) ? prev.filter((x) => x !== tag) : [...prev, tag]));

  return (
    <View style={{ flex: 1, justifyContent: 'center', padding: 22 }}>
      <Text style={[text.dim, { textAlign: 'center' }]}>결제 완료</Text>
      <Text style={[text.h1, { textAlign: 'center', marginTop: 6 }]}>오늘 러닝 어땠나요?</Text>

      <Row style={{ justifyContent: 'center', gap: 8, marginTop: 22 }}>
        {[1, 2, 3, 4, 5].map((n) => (
          <Pressable key={n} onPress={() => setStars(n)}>
            <Text style={{ fontSize: 38, color: n <= stars ? colors.tang : '#d8d4c4' }}>★</Text>
          </Pressable>
        ))}
      </Row>

      <Row style={{ flexWrap: 'wrap', gap: 8, justifyContent: 'center', marginTop: 24 }}>
        {TAGS.map((tag) => (
          <Chip key={tag} label={tag} selected={tags.includes(tag)} onPress={() => toggle(tag)} />
        ))}
      </Row>

      <Btn label="완료" style={{ marginTop: 30 }} onPress={() => router.dismissTo('/owner/home')} />
    </View>
  );
}
