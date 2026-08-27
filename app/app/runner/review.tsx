import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { fetchRunReport, RunReport } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { supabase } from '../../src/lib/supabase';
import { dogReviewTags, runResult } from '../../src/store';
import { paper } from '../../src/theme';

// 러너 → 보호자·반려견 리뷰 (양방향 신뢰의 반쪽).
// Schema seed: reviews table is bidirectional; private flags go to platform only.
//
// [정직 배치 2026-08-06 · item 3] 오프라인 큐가 없는데 '저장됐어요 (오프라인)'라고 말하던 거짓말 은퇴.
// 저장 성공은 서버 진실(!error)일 때만 선언한다 — 실패하면 화면에 남아 인라인 라우드-페일 + 재시도.
// 강아지 카드는 목업 초코(runRequests[0]) + 하드코딩 거리 → fetchRunReport 실데이터(runs.actual_km).
// 표면은 순백/코랄: 결정 화면이라 밀도는 내리고, 섹션은 풀블리드 코랄 헤어라인으로만 나눈다.
//
// [⑪ 2026-08-24 · Sean "For D, I like 11."] 두 가지가 바뀐다.
//  (a) 라틴 키커 REVIEW를 은퇴시키고(§3b가 앱 전체에서 은퇴시킨 그 장식) 제목을 §3b 화면 제목
//      규격 30/900 · lineHeight 37 · Black Han Sans로 올린다. 디스플레이 서체 예산(화면당 1회)은
//      이 화면에서 아무도 쓰지 않고 있었다 — 제목이 가져간다. 두 분기(폼/예약 없음)는 서로
//      배타적이라 화면당 1회는 그대로다.
//  (b) 별점이 낱말을 단다 (STAR_WORD).

// ⑪(b) 별점의 낱말 — 1~5와 **1:1로만** 대응한다. 애매한 말('그냥 그랬어요')은 두 숫자에 걸쳐서
// 러너가 고른 값을 흐린다. 이 별점은 다음 매칭에 실리는 값이라 그 무게를 낱말이 말한다.
// ⚠ 표시 전용이다: 서버로 가는 값은 여전히 reviews.rating(1-5) 하나뿐이고 낱말은 저장하지
// 않는다 — 두 번째 진실을 만들지 않는다.
const STAR_WORD: Record<number, string> = {
  1: '많이 힘들었어요',
  2: '아쉬웠어요',
  3: '무난했어요',
  4: '좋았어요',
  5: '아주 좋았어요',
};

export default function RunnerReview() {
  const df = useDisplayFont(); // 디스플레이 서체 — 이 화면의 유일한 사용처는 제목이다 (§3b)
  // 마운트 시점의 예약 id를 고정 — 제출 실패 시에도 이 값은 살아 있어야 재시도가 된다
  const [bookingId] = useState<string | null>(runResult.bookingId);
  const [report, setReport] = useState<RunReport | null>(null);
  const [reportErr, setReportErr] = useState(false);
  const [stars, setStars] = useState(0);
  const [tags, setTags] = useState<string[]>([]);
  const [privateFlag, setPrivateFlag] = useState(false);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const toggleTag = (t: string) =>
    setTags((prev) => (prev.includes(t) ? prev.filter((x) => x !== t) : [...prev, t]));

  // 방금 끝난 러닝의 실컨텍스트 — 강아지 실명 + runs.actual_km (없으면 km 문구 자체를 생략)
  useEffect(() => {
    if (!bookingId) return;
    fetchRunReport(bookingId)
      .then(setReport)
      .catch((e) => { setReportErr(true); console.warn('[r-review] report:', e?.message ?? e); });
  }, [bookingId]);

  const submit = async () => {
    if (!bookingId || stars === 0 || busy) return;
    setBusy(true);
    setFailed(false);
    try {
      const { data: bk, error: bkErr } = await supabase.from('bookings').select('dog_id').eq('id', bookingId).single();
      if (bkErr) throw bkErr;
      const { data: user } = await supabase.auth.getUser();
      if (!bk || !user.user) throw new Error('로그인 정보를 확인하지 못했어요');
      const { error } = await supabase.from('reviews').insert({
        booking_id: bookingId,
        author_id: user.user.id,
        target_kind: 'dog',
        target_id: bk.dog_id,
        rating: stars,          // 1-5 클라이언트 가드 (별점 0이면 여기까지 못 온다)
        tags,
        note: note.trim() || null,
        visibility: privateFlag ? 'platform_only' : 'public',
      });
      if (error) throw error;
    } catch (e) {
      // 실패는 실패로 — 화면 유지 · 입력 보존 · bookingId 보존 (재시도 경로). 네비게이션 없음.
      console.warn('[r-review] submit:', (e as Error)?.message ?? e);
      setBusy(false);
      setFailed(true);
      Alert.alert('등록 실패', '리뷰가 저장되지 않았어요 — 다시 시도해주세요');
      return;
    }
    setBusy(false);
    Alert.alert(
      '리뷰 완료',
      '리뷰가 서버에 저장됐어요.' + (privateFlag ? '\n비공개 신고는 도그스하이 운영팀만 확인해요.' : ''),
    );
    runResult.bookingId = null;
    router.dismissTo('/runner/home');
  };

  // 남길 예약이 없으면 폼을 그리지 않는다 — '저장될 것처럼' 보이는 화면이 곧 거짓말이었다
  if (!bookingId) {
    return (
      <View style={s.root}>
        <View style={s.head}>
          <Text style={[s.title, df]}>리뷰를 남길 예약을 찾지 못했어요</Text>
          <Text style={s.helper}>러닝을 마치면 이 화면이 다시 열려요</Text>
        </View>
        <View style={s.rule} />
        <View style={s.actions}>
          <Pressable
            style={({ pressed }) => [s.cta, pressed ? s.ctaPressed : s.ctaLip]}
            onPress={() => router.dismissTo('/runner/home')}
          >
            <Text style={s.ctaText}>홈으로 돌아가기</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  const dogName = report?.dogName ?? null;
  // ⚠ [2026-08-27] `?? 0` 이었다. 화면에는 아무것도 안 나왔으므로 (아래 `actualKm > 0` 가드가
  // 삼켰다) 무해해 보였지만, 그 식은 「모른다」와 「0km를 쟀다」를 같은 값으로 만든다 — 다음 사람이
  // 가드를 한 줄 손대면 그대로 0km가 인쇄된다. 더 나쁜 건 그 가드가 서로 다른 두 상태를 한 침묵으로
  // 덮었다는 것이다: 러닝 기록이 아예 없는 예약과, 서버가 거리를 재지 않은 러닝(actual_km IS NULL,
  // incident 경로)이 똑같이 빈 자리로 보였다. 이제 세 상태가 각자 말한다.
  const actualKm = report?.run?.actualKm ?? null;
  const guardOff = stars === 0;      // 별점 가드 — 명시 fill로 칠하는 유일한 disabled
  const blocked = guardOff || busy;  // 입력 차단. busy는 disabled로 칠하지 않는다 (버튼 매트릭스 법)

  return (
    <ScrollView style={s.root} contentContainerStyle={{ paddingBottom: 40 }}>
      <View style={s.head}>
        <Text style={[s.title, df]}>오늘 러닝 어땠나요?</Text>
        <Text style={s.helper}>러너의 리뷰가 다음 러너를 지켜요</Text>
      </View>
      <View style={s.rule} />

      {/* dog — 실데이터. 불러오는 중엔 '—' (로딩≠0), 실패해도 km는 지어내지 않는다 */}
      <Row style={s.band}>
        <View style={[s.mono, !dogName && s.monoOff]}>
          <Text style={[s.monoChar, !dogName && s.monoCharOff]}>{dogName ? dogName[0] : '—'}</Text>
        </View>
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Text style={s.dogName}>{dogName ?? '—'}</Text>
          {reportErr ? (
            <Text style={s.dogErr}>강아지 정보를 불러오지 못했어요</Text>
          ) : !report ? (
            <Text style={s.dogMeta}>러닝 기록 불러오는 중...</Text>
          ) : actualKm != null && actualKm > 0 ? (
            <Text style={s.dogMeta}>{actualKm.toFixed(2)}km 완주</Text>
          ) : report.run && actualKm == null ? (
            // 러닝은 있는데 거리를 모른다 — owner/report.tsx·club/receipt과 같은 낱말.
            // 0km도 '—'도 아니다: 둘 다 잰 값처럼 읽힌다.
            <Text style={s.dogMeta}>거리 기록 없음</Text>
          ) : null}
        </View>
      </Row>
      <View style={s.rule} />

      {/* rating — 이 화면의 강조는 결정 입력 그 자체 (코랄).
          ⑪(b): 고른 순간 낱말이 같은 줄 오른쪽에 선다. 0이면 낱말이 없고, 아래 CTA의
          '별점을 선택하면...' 힌트가 그 자리를 지킨다 (상태가 스스로 말한다). */}
      <View style={s.band}>
        <Row style={s.labelRow}>
          <Text style={[s.label, s.labelFlush]}>별점</Text>
          {stars > 0 && <Text style={s.starWord}>{STAR_WORD[stars]}</Text>}
        </Row>
        <Row style={{ gap: 10 }}>
          {[1, 2, 3, 4, 5].map((n) => (
            <Pressable key={n} onPress={() => setStars(n)} hitSlop={4}>
              <Text style={[s.star, n <= stars && s.starOn]}>★</Text>
            </Pressable>
          ))}
        </Row>
      </View>
      <View style={s.rule} />

      {/* behavior tags */}
      <View style={s.band}>
        <Text style={s.label}>{dogName ? `${dogName}는 어땠나요?` : '강아지는 어땠나요?'}</Text>
        <Row style={{ flexWrap: 'wrap', gap: 8 }}>
          {dogReviewTags.map((t) => (
            <Pressable key={t} onPress={() => toggleTag(t)} style={[s.tag, tags.includes(t) && s.tagSel]}>
              <Text style={[s.tagText, tags.includes(t) && s.tagTextSel]}>{t}</Text>
            </Pressable>
          ))}
        </Row>
      </View>
      <View style={s.rule} />

      {/* private flag — 다음 러너를 지키는 신고 어포던스라 critical 계열이 정색(正色) */}
      <Pressable onPress={() => setPrivateFlag((v) => !v)} style={[s.band, s.flagBand, privateFlag && s.flagBandOn]}>
        <View style={[s.flagCheck, privateFlag && s.flagCheckOn]}>
          {privateFlag && <Text style={s.flagTick}>✓</Text>}
        </View>
        <View style={{ flex: 1 }}>
          <Text style={s.flagTitle}>고지되지 않은 문제가 있었어요</Text>
          <Text style={s.flagSub}>보호자에게 보이지 않아요 · 운영팀 확인 후 다음 러너 매칭에 반영</Text>
        </View>
      </Pressable>
      <View style={s.rule} />

      {/* note */}
      <View style={s.band}>
        <Text style={s.label}>보호자에게 남길 메모 (선택)</Text>
        <TextInput
          style={s.noteInput}
          value={note}
          onChangeText={setNote}
          placeholder="다음 러닝에 도움될 정보를 남겨주세요"
          placeholderTextColor={paper.faint}
          multiline
        />
      </View>
      <View style={s.rule} />

      {/* 라우드-페일 — 전송이 실패한 사실은 화면에 남는다 (알럿을 닫아도 사라지지 않음) */}
      {failed && (
        <View style={s.failStrip}>
          <Text style={s.failText}>리뷰가 저장되지 않았어요 — 다시 시도해주세요</Text>
        </View>
      )}

      <View style={s.actions}>
        <Pressable
          style={({ pressed }) => [s.cta, guardOff && s.ctaOff, !guardOff && (pressed && !busy ? s.ctaPressed : s.ctaLip)]}
          disabled={blocked}
          onPress={submit}
        >
          <Text style={[s.ctaText, guardOff && s.ctaTextOff]}>{busy ? '저장 중...' : '리뷰 남기기'}</Text>
        </Pressable>
        {guardOff && <Text style={s.ctaHint}>별점을 선택하면 리뷰를 남길 수 있어요</Text>}
        <Pressable style={s.quiet} onPress={() => router.dismissTo('/runner/home')}>
          <Text style={s.quietText}>다음에 할게요</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  // 풀블리드 — 사이드 마진 0, 섹션은 코랄 헤어라인이 화면 끝까지 그어 나눈다
  root: { flex: 1, backgroundColor: paper.canvas },
  rule: { height: 1, backgroundColor: paper.line, alignSelf: 'stretch' },
  head: { paddingHorizontal: 18, paddingTop: 60, paddingBottom: 20 },
  // ⑪(a) §3b 화면 제목 규격: 30/900 · lineHeight 37 (1.23×) · Black Han Sans.
  // 라틴 키커 REVIEW는 은퇴 — §3b가 앱 전체에서 내린 장식이다. [BUG A]는 Black Han Sans에도
  // 적용되므로 lineHeight는 명시값이다.
  title: { fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink },
  helper: { fontSize: 15, lineHeight: 21, fontWeight: '600', color: paper.dim, marginTop: 9 },
  band: { paddingHorizontal: 18, paddingVertical: 18 },
  // ⑪(b) 라벨과 낱말이 같은 베이스라인 위에 (§3b 상태 칩과 같은 규율: 판정은 자기 데이터 옆에 산다)
  labelRow: { justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 },
  labelFlush: { marginBottom: 0 },
  starWord: { fontSize: 15.5, lineHeight: 21, fontWeight: '800', color: paper.ink },

  // ── 강아지 (실데이터) ──
  mono: { width: 52, height: 52, backgroundColor: paper.ink, alignItems: 'center', justifyContent: 'center' },
  monoOff: { backgroundColor: paper.disabledFill },
  monoChar: { fontSize: 22, fontWeight: '800', color: '#fff' }, // 잉크 fill 위 흰 글자 (hex 감사 KEEP)
  monoCharOff: { color: paper.faint },
  dogName: { fontSize: 18.5, lineHeight: 24, fontWeight: '800', color: paper.ink },
  dogMeta: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: paper.dim, marginTop: 3 },
  dogErr: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.critical, marginTop: 3 },

  // ── 라벨·입력 ──
  label: { fontSize: 15.5, lineHeight: 21, fontWeight: '700', color: paper.text, marginBottom: 12 },
  star: { fontSize: 40, lineHeight: 48, color: paper.faint },
  starOn: { color: paper.line },
  tag: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 9, paddingHorizontal: 14 },
  tagSel: { backgroundColor: paper.ink, borderColor: paper.ink },
  tagText: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.text },
  tagTextSel: { color: '#fff' },
  noteInput: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    padding: 13, minHeight: 84, fontSize: 15.5, lineHeight: 21, color: paper.ink, textAlignVertical: 'top',
  },

  // ── 비공개 신고 ──
  flagBand: { flexDirection: 'row', alignItems: 'center', gap: 11 },
  flagBandOn: { backgroundColor: paper.criticalWash },
  flagCheck: { width: 22, height: 22, borderWidth: 1.5, borderColor: paper.faint, alignItems: 'center', justifyContent: 'center' },
  flagCheckOn: { backgroundColor: paper.critical, borderColor: paper.critical },
  flagTick: { fontSize: 15, lineHeight: 18, fontWeight: '800', color: '#fff' },
  flagTitle: { fontSize: 15.5, lineHeight: 21, fontWeight: '800', color: paper.ink },
  flagSub: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: paper.dim, marginTop: 3 },

  // ── 라우드-페일 스트립 (F1.2) ──
  failStrip: {
    backgroundColor: paper.criticalWash, borderBottomWidth: 1, borderBottomColor: paper.critical,
    paddingHorizontal: 18, paddingVertical: 14,
  },
  failText: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },

  // ── 버튼 매트릭스 (불투명도 트릭 금지 — disabled는 명시 fill) ──
  actions: { paddingHorizontal: 18, paddingTop: 20 },
  // [액션] 후기 전송 = 커밋 -> 프라이머리 코랄. mono/tagSel은 잉크(아티팩트/상태)로 남는다.
  cta: { backgroundColor: paper.action, alignItems: 'center', paddingVertical: 17 },
  // [Sean 2026-08-26 press behaviour] filled primary = a physical key: 4px lip at rest,
  // translateY(3) + 1px pressed, so the bottom edge stays put. Same predicate as PaperBtn:
  // guard-off is DISABLED so it goes flat (a dead key has no travel), while busy keeps the
  // rest lip and only loses the travel — the button is still a key, it is just mid-send.
  ctaLip: { borderBottomWidth: 4, borderBottomColor: paper.actionPressed },
  // ⚠ pressed was paper.text (#333) — the ink-primary matrix this button left behind when its
  // face became paper.action. A coral face that darkens to grey is the wrong key, and the lip's
  // colour IS the pressed fill, so the two had to agree before the lip could be drawn at all.
  ctaPressed: {
    backgroundColor: paper.actionPressed, transform: [{ translateY: 3 }],
    borderBottomWidth: 1, borderBottomColor: paper.actionPressed,
  },
  ctaOff: { backgroundColor: paper.disabledFill },
  ctaText: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: '#fff' },
  ctaTextOff: { color: paper.faint },
  ctaHint: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: paper.dim, textAlign: 'center', marginTop: 10 },
  quiet: { alignItems: 'center', paddingVertical: 15, marginTop: 4 },
  quietText: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.dim },
});
