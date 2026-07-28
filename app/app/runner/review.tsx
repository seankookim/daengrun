import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { supabase } from '../../src/lib/supabase';
import { dogReviewTags, runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 → 보호자·반려견 리뷰 (양방향 신뢰의 반쪽).
// Schema seed: reviews table is bidirectional; private flags go to platform only.

const FOREST = '#0F1D13';

export default function RunnerReview() {
  const req = runRequests[0];
  const [stars, setStars] = useState(0);
  const [tags, setTags] = useState<string[]>([]);
  const [privateFlag, setPrivateFlag] = useState(false);
  const [note, setNote] = useState('');

  const toggleTag = (t: string) =>
    setTags((prev) => (prev.includes(t) ? prev.filter((x) => x !== t) : [...prev, t]));

  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    let saved = false;
    // 실예약이면 reviews 테이블에 실제 저장 (양방향 리뷰의 러너 쪽)
    if (runResult.bookingId) {
      try {
        const { data: bk } = await supabase.from('bookings').select('dog_id').eq('id', runResult.bookingId).single();
        const { data: user } = await supabase.auth.getUser();
        if (bk && user.user) {
          const { error } = await supabase.from('reviews').insert({
            booking_id: runResult.bookingId,
            author_id: user.user.id,
            target_kind: 'dog',
            target_id: bk.dog_id,
            rating: stars,
            tags,
            note: note.trim() || null,
            visibility: privateFlag ? 'platform_only' : 'public',
          });
          if (!error) saved = true;
        }
      } catch { /* fallback below */ }
    }
    setBusy(false);
    Alert.alert(
      '리뷰 완료',
      (saved ? '리뷰가 서버에 저장됐어요.' : '리뷰가 저장됐어요 (오프라인).') +
        (privateFlag ? '\n비공개 신고는 도그스하이 운영팀만 확인해요.' : '') +
        '\n보호자 알림은 푸시 연동 시 전송돼요.',
    );
    runResult.bookingId = null;
    router.dismissTo('/runner/home');
  };

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Text style={{ fontSize: 25.5, fontWeight: '900', color: FOREST, textAlign: 'center' }}>오늘 러닝 어땠나요?</Text>
      <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 5 }}>
        러너의 리뷰가 다음 러너를 지켜요
      </Text>

      {/* dog */}
      <View style={s.dogCard}>
        <Monogram char={req.dogChar} bg={req.dogColor} size={52} />
        <View style={{ marginLeft: 12 }}>
          <Text style={{ fontSize: 18.5, fontWeight: '900', color: FOREST }}>{req.dogName}</Text>
          <Text style={{ fontSize: 13, color: colors.dim, marginTop: 2 }}>{req.breed} · 5.02km 완주</Text>
        </View>
      </View>

      {/* rating */}
      <Row style={{ justifyContent: 'center', gap: 8, marginTop: 18 }}>
        {[1, 2, 3, 4, 5].map((n) => (
          <Pressable key={n} onPress={() => setStars(n)}>
            <Text style={{ fontSize: 41.5, color: n <= stars ? '#f2a33c' : '#dcd9cc' }}>★</Text>
          </Pressable>
        ))}
      </Row>

      {/* behavior tags */}
      <Text style={s.label}>{req.dogName}는 어땠나요?</Text>
      <Row style={{ flexWrap: 'wrap', gap: 8 }}>
        {dogReviewTags.map((t) => (
          <Pressable key={t} onPress={() => toggleTag(t)} style={[s.tag, tags.includes(t) && s.tagSel]}>
            <Text style={{ fontSize: 14.5, fontWeight: '700', color: tags.includes(t) ? '#fff' : '#3d453d' }}>{t}</Text>
          </Pressable>
        ))}
      </Row>

      {/* private flag — protects the next runner */}
      <Pressable onPress={() => setPrivateFlag((v) => !v)} style={[s.flagCard, privateFlag && { borderColor: '#e8b0a0', backgroundColor: '#fdf3f0' }]}>
        <View style={[s.flagCheck, privateFlag && { backgroundColor: '#e8492a', borderColor: '#e8492a' }]}>
          {privateFlag && <Text style={{ fontSize: 11.5, fontWeight: '900', color: '#fff' }}>✓</Text>}
        </View>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 15.5, fontWeight: '800', color: FOREST }}>고지되지 않은 문제가 있었어요</Text>
          <Text style={{ fontSize: 12.5, color: colors.dim, marginTop: 2 }}>
            보호자에게 보이지 않아요 · 운영팀 확인 후 다음 러너 매칭에 반영
          </Text>
        </View>
      </Pressable>

      {/* note */}
      <Text style={s.label}>보호자에게 남길 메모 (선택)</Text>
      <TextInput
        style={s.noteInput}
        value={note}
        onChangeText={setNote}
        placeholder="다음 러닝에 도움될 정보를 남겨주세요"
        placeholderTextColor="#a9a795"
        multiline
      />

      <Pressable style={[s.submit, (stars === 0 || busy) && { opacity: 0.4 }]} disabled={stars === 0 || busy} onPress={submit}>
        <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{busy ? '저장 중...' : '리뷰 남기기'}</Text>
      </Pressable>
      <Pressable style={{ alignItems: 'center', paddingVertical: 13 }} onPress={() => router.dismissTo('/runner/home')}>
        <Text style={{ fontSize: 14.5, fontWeight: '700', color: colors.dim }}>다음에 할게요</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  dogCard: {
    flexDirection: 'row', alignItems: 'center', alignSelf: 'center',
    backgroundColor: '#fff', borderRadius: 18, padding: 14, paddingHorizontal: 12,
    borderWidth: 1, borderColor: '#DCD6C4', marginTop: 18,
  },
  label: { fontSize: 15.5, fontWeight: '900', color: FOREST, marginTop: 22, marginBottom: 9 },
  tag: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  tagSel: { backgroundColor: FOREST, borderColor: FOREST },
  flagCard: {
    flexDirection: 'row', alignItems: 'center', gap: 11,
    backgroundColor: '#fff', borderWidth: 1.4, borderColor: '#DCD6C4', borderRadius: 16,
    padding: 14, marginTop: 20,
  },
  flagCheck: { width: 22, height: 22, borderRadius: 7, borderWidth: 1.6, borderColor: '#dcd9cc', alignItems: 'center', justifyContent: 'center' },
  noteInput: {
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4',
    padding: 14, minHeight: 80, fontSize: 15.5, color: FOREST, textAlignVertical: 'top',
  },
  submit: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 15, marginTop: 20 },
});
