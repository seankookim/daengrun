import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { haptic } from '../../src/lib/haptics';
import { supabase } from '../../src/lib/supabase';
import { colors, paper } from '../../src/theme';

// 보호자 → 러너 후기 — 양방향 신뢰의 나머지 반쪽. reviews(target_kind 'runner').
// 러너 스토어프런트 ★평균·후기 리스트의 원천 (0011 정책으로 전체 공개 읽기).
// 진입: 리포트 '러너 후기 남기기' (bid·rid·rname 파라미터)

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const TAGS = ['시간 약속 철저', '사진 잘 찍어줘요', '소통이 빨라요', '아이를 잘 다뤄요', '페이스 조절 굿', '또 부르고 싶어요'];

export default function OwnerReview() {
  const { bid, rid, rname } = useLocalSearchParams<{ bid: string; rid: string; rname?: string }>();
  const [stars, setStars] = useState(0);
  const [tags, setTags] = useState<string[]>([]);
  const [note, setNote] = useState('');
  const [privateFlag, setPrivateFlag] = useState(false);
  const [busy, setBusy] = useState(false);

  const toggleTag = (t: string) =>
    setTags((prev) => (prev.includes(t) ? prev.filter((x) => x !== t) : [...prev, t]));

  const submit = async () => {
    if (!bid || !rid) { Alert.alert('예약 정보가 없어요'); return; }
    if (stars === 0) { Alert.alert('별점을 선택해주세요'); return; }
    setBusy(true);
    try {
      const { data: user } = await supabase.auth.getUser();
      if (!user.user) throw new Error('not signed in');
      const { error } = await supabase.from('reviews').insert({
        booking_id: bid,
        author_id: user.user.id,
        target_kind: 'runner',
        target_id: rid,
        rating: stars,
        tags,
        note: note.trim() || null,
        visibility: privateFlag ? 'platform_only' : 'public',
      });
      if (error) {
        if (error.code === '23505') { Alert.alert('이미 후기를 남겼어요', '이 러닝의 후기는 한 번만 작성할 수 있어요'); router.back(); return; }
        throw error;
      }
      haptic('success');
      Alert.alert('후기 등록 완료', `${rname ?? '러너'}님의 프로필에 반영됐어요 — 고마워요!`);
      router.back();
    } catch (e) {
      Alert.alert('등록 실패', (e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>러너 후기</Text>
        <View style={{ width: 40 }} />
      </Row>

      <Text style={{ fontSize: 17, fontWeight: '800', color: paper.ink, textAlign: 'center', marginTop: 22 }}>
        {rname ?? '러너'}님과의 러닝, 어땠나요?
      </Text>

      {/* stars */}
      <Row style={{ justifyContent: 'center', gap: 8, marginTop: 16 }}>
        {[1, 2, 3, 4, 5].map((n) => (
          <Pressable key={n} onPress={() => { setStars(n); haptic('light'); }}>
            <Text style={{ fontSize: 43.5, color: n <= stars ? '#f2c14e' : '#dcd9cc' }}>★</Text>
          </Pressable>
        ))}
      </Row>

      {/* tags */}
      <Row style={{ gap: 8, flexWrap: 'wrap', marginTop: 22, justifyContent: 'center' }}>
        {TAGS.map((t) => {
          const on = tags.includes(t);
          return (
            <Pressable key={t} onPress={() => toggleTag(t)} style={[s.tag, on && { backgroundColor: '#eaf7c8', borderColor: '#a9c47e' }]}>
              <Text style={{ fontSize: 14.5, fontWeight: '700', color: on ? '#3d5a2b' : '#49524a' }}>{on ? '✓ ' : ''}{t}</Text>
            </Pressable>
          );
        })}
      </Row>

      {/* note */}
      <TextInput
        value={note}
        onChangeText={setNote}
        placeholder="다른 보호자들에게 도움이 될 이야기를 남겨주세요 (선택)"
        placeholderTextColor="#b0ada0"
        style={s.input}
        multiline
        maxLength={300}
      />

      {/* private flag */}
      <Pressable onPress={() => setPrivateFlag((v) => !v)} style={s.privRow}>
        <View style={[s.check, privateFlag && { backgroundColor: paper.ink, borderColor: paper.ink }]}>
          {privateFlag && <Text style={{ fontSize: 11.5, fontWeight: '900', color: '#fff' }}>✓</Text>}
        </View>
        <Text style={{ flex: 1, fontSize: 14, color: '#49524a', lineHeight: 19.5 }}>
          도그스하이 팀에게만 전달 (프로필에 공개되지 않아요 — 불편했던 점을 솔직하게)
        </Text>
      </Pressable>

      <Pressable onPress={submit} disabled={busy} style={[s.cta, busy && { opacity: 0.5 }]}>
        <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>{busy ? '등록 중...' : '후기 등록'}</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  tag: { backgroundColor: '#fff', borderRadius: 99, borderWidth: 1.3, borderColor: '#DCD6C4', paddingVertical: 9, paddingHorizontal: 14 },
  input: {
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4',
    padding: 14, marginTop: 20, height: 100, textAlignVertical: 'top', fontSize: 15.5, color: paper.ink,
  },
  privRow: { flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 14 },
  check: { width: 20, height: 20, borderRadius: 6, borderWidth: 1.5, borderColor: '#dcd9cc', alignItems: 'center', justifyContent: 'center', backgroundColor: '#fff' },
  cta: { backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 15, marginTop: 22 },
});
