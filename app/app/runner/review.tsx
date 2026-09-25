import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row, ScreenHead } from '../../src/components/ui';
import { fetchRunReportOrNull, RunReport } from '../../src/lib/api';
import { withParticle } from '../../src/lib/particle';
import { resolveReviewBooking, reviewSurface, type ReportRead } from '../../src/lib/review-gate';
import { supabase } from '../../src/lib/supabase';
import { dogReviewTags, runResult } from '../../src/store';
import { colors, layout, paper } from '../../src/theme';

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
//
// [ui-consistency-3, 2026-09-25] (a) is superseded by DESIGN.md §3b 「Chrome header — pushed
// sub-screens」 (2026-09-25): this screen is PUSHED (from runner/done and from the calendar's
// completed ticket), so it wears `ScreenHead` — a working ‹ on every face — instead of a 30/900
// display title with no back key. A runner who opened it from 캘린더 could previously leave only by
// 「다음에 할게요」, which dismissed to HOME; the ‹ now returns them where they came from
// (goBackOrHome, which still lands on home from a cold push). Each face's headline drops to the
// 17/800 body line owner/review.tsx uses, the primaries are PaperBtn (the lip, busy label swap and
// disabled fill are the component's, not a hand-rolled copy), the gutter is layout.gutter, and the
// star/chip grammar matches the owner's mirror: gold stars, selected chip = wash 면 + coral 1px +
// actionInk. What is written and where it goes are untouched.

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
  const insets = useSafeAreaInsets();
  // ═══ WHICH BOOKING IS BEING REVIEWED ═══════════════════════════════════════════════════════
  // 🔴 This screen used to answer that with `runResult.bookingId` and nothing else — run.tsx's
  // in-memory snapshot of whatever run ended last in this process. Two costs, and the second is
  // the dangerous one: a runner who left `runner/done` could NEVER review that run again (the
  // store was the only door), and a STALE store wrote the review onto the WRONG booking, because
  // the insert below uses `booking_id: bookingId` verbatim. Same class 0193 A4 closed for
  // `runner/return-seal` and `runner/done`, left open on this screen.
  //
  // A param now names the run. The store survives only as the fallback for the one route that
  // has no param (a build mid-upgrade), and — see `review-gate.ts` — a store-sourced id is not
  // trusted until the booking has actually been READ.
  //
  // Resolved ONCE at mount, like the id it replaces: the submit's retry path must not change
  // booking underneath a runner who is already typing.
  const { bid } = useLocalSearchParams<{ bid?: string }>();
  const [resolved] = useState(() => resolveReviewBooking(bid, runResult.bookingId));
  const bookingId = resolved.bookingId;
  const [report, setReport] = useState<RunReport | null>(null);
  // THREE ANSWERS, NEVER TWO (api.ts's maybeSingle law): `absent` = zero rows, which for a runner
  // means 「not a booking I can read」; `failed` = a transport/RLS throw, which means 「I do not
  // know」. `fetchRunReportOrNull` is what keeps them apart — the throwing form collapses both.
  const [read, setRead] = useState<ReportRead>('loading');
  const [stars, setStars] = useState(0);
  const [tags, setTags] = useState<string[]>([]);
  const [privateFlag, setPrivateFlag] = useState(false);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const toggleTag = (t: string) =>
    setTags((prev) => (prev.includes(t) ? prev.filter((x) => x !== t) : [...prev, t]));

  // 방금 끝난 러닝의 실컨텍스트 — 강아지 실명 + runs.actual_km (없으면 km 문구 자체를 생략).
  // It is ALSO the verification of a store-sourced id: a booking this runner cannot read comes
  // back as `absent`, and `reviewSurface` refuses to draw a submit button over it.
  const loadReport = useCallback(() => {
    if (!bookingId) return;
    setRead('loading');
    fetchRunReportOrNull(bookingId)
      .then((r) => { setReport(r); setRead(r ? 'ok' : 'absent'); })
      .catch((e) => { setRead('failed'); console.warn('[r-review] report:', e?.message ?? e); });
  }, [bookingId]);
  useEffect(() => { loadReport(); }, [loadReport]);
  const surface = reviewSurface({ source: resolved.source, read });
  // ONE header, drawn by every face below (DESIGN.md §3b) — the default onBack is goBackOrHome.
  const head = (
    <View style={[s.topBar, { paddingTop: insets.top }]}>
      <ScreenHead title="반려견 후기" />
    </View>
  );

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
      Alert.alert('등록 실패', '후기가 저장되지 않았어요 — 다시 시도해주세요');
      return;
    }
    setBusy(false);
    Alert.alert(
      '후기 등록 완료',
      '후기가 서버에 저장됐어요.' + (privateFlag ? '\n비공개 신고는 도그스하이 운영팀만 확인해요.' : ''),
    );
    // ⚠ Clear the store ONLY when it is this booking. With a param the screen can be opened for a
    // run the store knows nothing about (the calendar's second door), and blanking it there would
    // discard another run's in-flight pointer — the same wrong-booking class one step over.
    if (runResult.bookingId === bookingId) runResult.bookingId = null;
    router.dismissTo('/runner/home');
  };

  // 남길 예약이 없으면 폼을 그리지 않는다 — '저장될 것처럼' 보이는 화면이 곧 거짓말이었다.
  // 이제 세 얼굴이다 (review-gate.ts): 불러오는 중 · 예약 없음 · 읽기 실패.
  if (surface === 'loading') {
    return (
      <View style={s.root}>
        {head}
        <View style={s.head}>
          <Text style={s.headline}>러닝 기록을 불러오는 중이에요</Text>
          <Text style={s.helper}>어떤 러닝의 후기인지 확인하고 있어요</Text>
        </View>
        <View style={s.rule} />
        {/* ⚠ 출구 하나는 로딩 얼굴에도 있어야 한다 — the ‹ above is one, and this quiet exit keeps
            its home landing. (종전에는 로딩 중에도 폼이 떠 있어서 '다음에 할게요'가 그 일을 했다.) */}
        <View style={s.actions}>
          <PaperBtn label="다음에 할게요" variant="quiet" onPress={() => router.dismissTo('/runner/home')} />
        </View>
      </View>
    );
  }

  if (surface === 'no-booking') {
    // 두 가지 사실이 있고 둘은 같은 말이 아니다: 아예 예약을 못 받은 진입과, 받은 id가 이 러너가
    // 읽을 수 있는 예약이 아닌 경우(끝났거나 내 예약이 아니거나). 후자를 「러닝을 마치면 다시
    // 열려요」라고 말하면 이미 마친 러너에게 거짓말이 된다.
    const unreadable = resolved.source !== 'none';
    return (
      <View style={s.root}>
        {head}
        <View style={s.head}>
          <Text style={s.headline}>
            {unreadable ? '이 러닝을 찾을 수 없어요' : '후기를 남길 예약을 찾지 못했어요'}
          </Text>
          <Text style={s.helper}>
            {unreadable ? '이미 마무리됐거나 내 예약이 아니에요' : '러닝을 마치면 이 화면이 다시 열려요'}
          </Text>
        </View>
        <View style={s.rule} />
        <View style={s.actions}>
          <PaperBtn label="홈으로 돌아가기" onPress={() => router.dismissTo('/runner/home')} />
        </View>
      </View>
    );
  }

  if (surface === 'read-failed') {
    // 저장소에서 온 예약 id인데 그 예약을 읽지 못했다 — 「이 러닝이 맞다」를 확인해 줄 유일한
    // 읽기가 답하지 않은 상태다. 폼을 그리면 확인되지 않은 예약 위에 제출 버튼을 그리는 것이고,
    // 그게 이 슬라이스가 닫는 결함 그 자체다. 실패는 실패로 말하고 재시도를 준다.
    return (
      <View style={s.root}>
        {head}
        <View style={s.head}>
          <Text style={s.headline}>러닝 기록을 불러오지 못했어요</Text>
          <Text style={s.helper}>어떤 러닝의 후기인지 확인하지 못해서 아직 열 수 없어요 — 기록은 서버에 그대로 있어요</Text>
        </View>
        <View style={s.rule} />
        <View style={s.actions}>
          <PaperBtn label="다시 시도" onPress={loadReport} />
          <PaperBtn label="홈으로 돌아가기" variant="quiet" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
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
  const guardOff = stars === 0;      // 별점 가드 — 명시 fill로 칠하는 유일한 disabled (PaperBtn disabled)

  return (
    <ScrollView style={s.root} contentContainerStyle={{ paddingBottom: 40 }}>
      {head}
      <View style={s.head}>
        <Text style={s.headline}>오늘 러닝 어땠나요?</Text>
        <Text style={s.helper}>러너의 후기가 다음 러너를 지켜요</Text>
      </View>
      <View style={s.rule} />

      {/* dog — 실데이터. 불러오는 중엔 '—' (로딩≠0), 실패해도 km는 지어내지 않는다 */}
      <Row style={s.band}>
        <View style={[s.mono, !dogName && s.monoOff]}>
          <Text style={[s.monoChar, !dogName && s.monoCharOff]}>{dogName ? dogName[0] : '—'}</Text>
        </View>
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Text style={s.dogName}>{dogName ?? '—'}</Text>
          {read === 'failed' ? (
            // Only a PARAM booking reaches the form with a failed read (review-gate.ts) — the
            // caller named this run from a server row, so the form stands and the failure is
            // stated here rather than hidden. A 로딩 branch is not needed: `surface === 'loading'`
            // gates the whole screen above, so the form never renders mid-read.
            <Text style={s.dogErr}>강아지 정보를 불러오지 못했어요</Text>
          ) : actualKm != null && actualKm > 0 ? (
            <Text style={s.dogMeta}>{actualKm.toFixed(2)}km 완주</Text>
          ) : report?.run && actualKm == null ? (
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
            <Pressable
              key={n}
              onPress={() => setStars(n)}
              hitSlop={4}
              accessibilityRole="radio"
              accessibilityState={{ selected: n === stars }}
              accessibilityLabel={`별점 ${n}점`}
            >
              <Text style={[s.star, n <= stars && s.starOn]}>★</Text>
            </Pressable>
          ))}
        </Row>
      </View>
      <View style={s.rule} />

      {/* behavior tags */}
      <View style={s.band}>
        {/* [copy-hierarchy-1] the particle follows the name — 「콩은」, not 「콩는」 (particle.ts) */}
        <Text style={s.label}>{dogName ? `${withParticle(dogName, '는/은')} 어땠나요?` : '강아지는 어땠나요?'}</Text>
        <Row style={{ flexWrap: 'wrap', gap: 8 }}>
          {dogReviewTags.map((t) => (
            <Pressable key={t} onPress={() => toggleTag(t)} style={[s.tag, tags.includes(t) && s.tagSel]}
              accessibilityRole="checkbox" accessibilityState={{ checked: tags.includes(t) }}>
              <Text style={[s.tagText, tags.includes(t) && s.tagTextSel]}>{t}</Text>
            </Pressable>
          ))}
        </Row>
      </View>
      <View style={s.rule} />

      {/* private flag — 다음 러너를 지키는 신고 어포던스라 critical 계열이 정색(正色) */}
      <Pressable onPress={() => setPrivateFlag((v) => !v)} style={[s.band, s.flagBand, privateFlag && s.flagBandOn]}
        accessibilityRole="checkbox" accessibilityState={{ checked: privateFlag }}>
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
          <Text style={s.failText}>후기가 저장되지 않았어요 — 다시 시도해주세요</Text>
        </View>
      )}

      <View style={s.actions}>
        {/* PaperBtn owns the matrix this Pressable hand-copied: the star guard is `disabled`
            (disabledFill + faint, flat — a dead key has no travel), busy is the label swap with the
            rest lip kept, and `submit` re-checks both, so no path double-inserts. */}
        <PaperBtn label="후기 남기기" busyLabel="저장 중…" busy={busy} disabled={guardOff} onPress={submit} />
        {guardOff && <Text style={s.guardHint}>별점을 선택하면 후기를 남길 수 있어요</Text>}
        <PaperBtn label="다음에 할게요" variant="quiet" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  // 풀블리드 — 사이드 마진 0, 섹션은 코랄 헤어라인이 화면 끝까지 그어 나눈다
  root: { flex: 1, backgroundColor: paper.canvas },
  rule: { height: 1, backgroundColor: paper.line, alignSelf: 'stretch' },
  // Chrome header (DESIGN.md §3b) — the same wrapper owner/review.tsx uses, inside the gutter.
  topBar: { paddingHorizontal: layout.gutter, paddingBottom: 12 },
  head: { paddingHorizontal: layout.gutter, paddingTop: 10, paddingBottom: 20 },
  // [ui-consistency-3] the face's headline is a 17/800 body line (owner/review.tsx:100), not a
  // display title — the screen's title is the header's. ⑪(a)'s 30/900 Black Han Sans retired here.
  headline: { fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink },
  helper: { fontSize: 15, lineHeight: 21, fontWeight: '600', color: paper.dim, marginTop: 9 },
  band: { paddingHorizontal: layout.gutter, paddingVertical: 18 },
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
  // §8 기록 골드 — the owner's mirror (owner/review.tsx) fills its stars with the same token.
  starOn: { color: colors.gold },
  tag: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 9, paddingHorizontal: 14 },
  // §3b 선택칩 — wash 면 + coral 1px + actionInk (owner/review.tsx tagOn). An ink fill is STATE
  // grammar on a View, never on a tappable (chrome-header CH-P's rule).
  tagSel: { backgroundColor: paper.wash, borderColor: paper.line },
  tagText: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.text },
  tagTextSel: { color: paper.actionInk },
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
    paddingHorizontal: layout.gutter, paddingVertical: 14,
  },
  failText: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },

  // ── 버튼 — PaperBtn owns the matrix (lip, pressed travel, disabled fill, busy label swap) ──
  actions: { paddingHorizontal: layout.gutter, paddingTop: 20 },
  guardHint: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: paper.dim, textAlign: 'center', marginTop: 10 },
});
