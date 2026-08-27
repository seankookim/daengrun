import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { supabase } from '../../src/lib/supabase';
import { colors, paper } from '../../src/theme';

// 보호자 → 러너 후기 — 양방향 신뢰의 나머지 반쪽. reviews(target_kind 'runner').
// 러너 스토어프런트 ★평균·후기 리스트의 원천 (0011 정책으로 전체 공개 읽기).
// 진입: 리포트 '러너 후기 남기기' (bid·rid·rname 파라미터)

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
//
// ═══ [2026-08-24 · Sean "The runner review (C) I like 1"] 종이로 이관 (lab C①) ═══
// This screen was the least-migrated in the records cluster: NINE hexes that appear nowhere in
// theme.ts — #DCD6C4 ×3 (retired beige hairline), #eaf7c8 / #a9c47e / #3d5a2b (retired swamp
// chip), #dcd9cc, #f2c14e (star gold), #b0ada0 (placeholder) — plus colors.volt as the CTA
// surface, pill corners in a sharp-corner world, and an `opacity: 0.5` busy state that F2.1
// explicitly bans while the code was ALREADY doing the label swap that replaces it.
// Nothing here changes what is written or where it goes: same params in, same insert out. The
// screen simply stops being drawn from a retired palette.
//   · chrome  §2 — 40×40 square back, full-bleed solid coral hairline, white canvas
//   · chips   §3b — radius 0, #EEE border; selected = wash 면 + coral 보더 + actionInk (dog.tsx)
//   · CTA     §3b — paper.action 면, white 17/800, radius 0; busy = 라벨 스왑, 알파 금지
//   · stars        colors.gold (#D9A93C, §8 기록 골드) on #EEE, each a real 44pt target
const TAGS = ['시간 약속 철저', '사진 잘 찍어줘요', '소통이 빨라요', '아이를 잘 다뤄요', '페이스 조절 굿', '또 부르고 싶어요'];

export default function OwnerReview() {
  const { bid, rid, rname, stars: starsParam } = useLocalSearchParams<{ bid: string; rid: string; rname?: string; stars?: string }>();
  // The report's star row is an AFFORDANCE, not a submission — it carries the star the owner
  // tapped over here and pre-selects it. Nothing is written until 후기 등록. The param is a URL
  // string, so anything outside 1..5 falls back to 0 and submit() keeps refusing.
  const [stars, setStars] = useState(() => {
    const n = Number(starsParam);
    return Number.isInteger(n) && n >= 1 && n <= 5 ? n : 0;
  });
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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
        {/* §2 종이 크롬 — 헤더는 거터 밖에 서서 코랄 헤어라인이 화면 끝까지 간다 (사이드 마진 금지) */}
        <Row style={s.topBar}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>러너 후기</Text>
          <View style={{ width: 40 }} />
        </Row>

        <View style={{ paddingHorizontal: 15 }}>
          <Text style={{ fontSize: 17, fontWeight: '800', color: paper.ink, textAlign: 'center', marginTop: 22 }}>
            {rname ?? '러너'}님과의 러닝, 어땠나요?
          </Text>

          {/* stars — §8 기록 골드. 글리프 자체가 Pressable 이었던 것을 패딩으로 감싸 44pt 타깃을
              만든다 (report.tsx s.star 과 같은 수치). 빈 별은 #EEE: dim(#666)은 '꺼짐'이 아니라
              '읽는 회색'이라 절반이 이미 눌린 것처럼 보인다. */}
          <Row style={{ justifyContent: 'center', gap: 8, marginTop: 16 }}>
            {[1, 2, 3, 4, 5].map((n) => (
              <Pressable
                key={n}
                onPress={() => { setStars(n); haptic('light'); }}
                style={s.star}
                accessibilityRole="radio"
                accessibilityState={{ selected: n === stars }}
                accessibilityLabel={`별점 ${n}점`}
              >
                <Text style={[s.starGlyph, { color: n <= stars ? colors.gold : '#EEEEEE' }]}>★</Text>
              </Pressable>
            ))}
          </Row>

          {/* tags — §3b 선택칩: 샤프 코너 · 선택은 코랄 워시 면 + 코랄 보더 + actionInk */}
          <Row style={{ gap: 8, flexWrap: 'wrap', marginTop: 22, justifyContent: 'center' }}>
            {TAGS.map((t) => {
              const on = tags.includes(t);
              return (
                <Pressable
                  key={t}
                  onPress={() => toggleTag(t)}
                  style={[s.tag, on && s.tagOn]}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: on }}
                >
                  <Text style={{ fontSize: 15, fontWeight: '800', color: on ? paper.actionInk : paper.text }}>{on ? '✓ ' : ''}{t}</Text>
                </Pressable>
              );
            })}
          </Row>

          {/* note */}
          <TextInput
            value={note}
            onChangeText={setNote}
            placeholder="다른 보호자들에게 도움이 될 이야기를 남겨주세요 (선택)"
            placeholderTextColor={paper.faint}
            style={s.input}
            multiline
            maxLength={300}
          />

          {/* private flag */}
          <Pressable
            onPress={() => setPrivateFlag((v) => !v)}
            style={s.privRow}
            accessibilityRole="checkbox"
            accessibilityState={{ checked: privateFlag }}
          >
            <View style={[s.check, privateFlag && { backgroundColor: paper.ink, borderColor: paper.ink }]}>
              {privateFlag && <Text style={{ fontSize: 11.5, fontWeight: '900', color: '#fff' }}>✓</Text>}
            </View>
            <Text style={{ flex: 1, fontSize: 15, color: paper.text, lineHeight: 19.5 }}>
              도그스하이 팀에게만 전달 (프로필에 공개되지 않아요 — 불편했던 점을 솔직하게)
            </Text>
          </Pressable>

          {/* §3b 프라이머리 — action 면 · 흰 17/800 · radius 0. busy = 라벨 스왑 (opacity 0.5 폐기, F2.1) */}
          <Pressable
            onPress={submit}
            disabled={busy}
            style={({ pressed }) => [s.cta, pressed && { backgroundColor: paper.actionPressed }]}
            accessibilityRole="button"
          >
            <Text style={{ fontSize: 17, fontWeight: '800', color: '#fff' }}>{busy ? '등록 중...' : '후기 등록'}</Text>
          </Pressable>
          {/* 이 줄은 체크박스가 실제로 무엇을 바꾸는지 말한다 — visibility 는 두 값이므로 문장도 둘. */}
          <Text style={s.ctaNote}>
            {privateFlag
              ? '도그스하이 팀에게만 전달돼요 — 러너 프로필에는 보이지 않아요'
              : `등록하면 ${rname ?? '러너'} 러너의 프로필에 바로 보여요`}
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  // 페이퍼 크롬 상단 — 풀블리드 코랄 헤어라인 + 40×40 스퀘어 백 (report/dog 와 같은 문법)
  topBar: {
    justifyContent: 'space-between', paddingTop: 56, paddingBottom: 12, paddingHorizontal: 15,
    borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 0, backgroundColor: paper.canvas,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line,
  },
  star: { paddingHorizontal: 4, paddingVertical: 2 }, // 43.5pt 글리프(lineHeight 52) + 패딩 → 44pt 초과
  starGlyph: { fontSize: 43.5, lineHeight: 52 },
  tag: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 10, paddingHorizontal: 13,
  },
  tagOn: { backgroundColor: paper.wash, borderColor: paper.line },
  input: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    padding: 13, marginTop: 20, height: 100, textAlignVertical: 'top', fontSize: 16, color: paper.ink,
  },
  privRow: { flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 14 },
  check: {
    width: 20, height: 20, borderRadius: 0, borderWidth: 1.5, borderColor: '#EEEEEE',
    alignItems: 'center', justifyContent: 'center', backgroundColor: paper.canvas,
  },
  cta: { backgroundColor: paper.action, borderRadius: 0, alignItems: 'center', paddingVertical: 16, marginTop: 22 },
  ctaNote: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 10, textAlign: 'center' },
});
