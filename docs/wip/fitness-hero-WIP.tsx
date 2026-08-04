import { router, useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Animated, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { fetchFitness, fetchRecentMoments, Fitness, Moment, updateDogGoal } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { lilac, lilacRadius } from '../../src/theme';

// 체력 리포트 — 모프 링의 도착지. 브랜드의 심장: 반려견 피트니스.
// [2026-08-04 W4] 히어로 = 랩 ①(시네 스트립) 골격 × ③(파노라마 릴) 사진법.
//   필름 밴드(풀블리드) = 스프로킷 · 풀블리드 한 컷 + 스크림 · 썸네일 레일 · 엣지코드,
//   데이터 밴드 = 이번 주 km 와 체력 나이가 나란히 선 공동 주역(Sean: 나이를 더 세게).
//   스크롤하면 두 정적 레이어가 크로스페이드 — 확장 히어로가 빠지고 다크 필름 리본만 남는다
//   (owner-home 검증 패턴: Animated.event + opacity/translateY, useNativeDriver. 높이 애니메이션 없음).
// [은퇴] 포레스트/크림 서피스 · 볼트/탱 신호색 · 주간 링 위젯 — 테일러드 라일락으로 재도장.

const FILM = lilac.head;        // 필름 베이스 — 헤드 잉크(#221E3D)를 그대로 필름으로
const FILM_INK = '#C9C2E8';     // 엣지코드 잉크 (필름 위 라일락 실버)
const FILM_TITLE = '#F2EFFA';   // 리본 타이틀 · 카운터
const FILM_NUM = '#FFD9CD';     // 리본 숫자 — 코랄 틴트
const BAR_PAST = '#9787DC';     // 8주 바 과거 (validate_palette ALL PASS)
const BAR_NOW = lilac.coralDeep; // 8주 바 이번 주
const MORPH_RANGE = 120;        // 스크롤 0→120px 가 모프 진행도 0→1
const GUTTER = 16;              // 화면 좌우 여백 — 필름 밴드는 이 값만큼 음수 마진으로 풀블리드
const PANO_H = 200;             // 파노라마 한 컷 높이
const BAR_MAX = 66;             // 88px 바 영역에서 값 라벨(≈22px)을 뺀 최대 바 높이
const DAYS = ['월', '화', '수', '목', '금', '토', '일'] as const;
// 스프로킷 = 작은 배경색 점 줄 (그라디언트/이미지 없이 View만 — 프레임당 비용 0)
const SPROCKETS = Array.from({ length: 18 }, (_, i) => i);
const MINI_SPROCKETS = Array.from({ length: 12 }, (_, i) => i);

const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');

export default function FitnessHub() {
  const df = useDisplayFont(); // 디스플레이 서체 — 이 화면의 유일한 Black Han Sans (상태당 1회)
  const nf = useNumFont();     // 숫자 = Oswald (모든 사용처에 명시 lineHeight)
  const [fit, setFit] = useState<Fitness | null>(null);
  const [moments, setMoments] = useState<Moment[]>([]);
  const [selIdx, setSelIdx] = useState(0);
  const [savingGoal, setSavingGoal] = useState(false);

  // 실패해도 직전 상태를 지우지 않는다 (정직 원칙: 빈 화면 ≠ 데이터 없음)
  const load = () => {
    Promise.all([fetchFitness(), fetchRecentMoments(12)])
      .then(([f, ms]) => { setFit(f); setMoments(ms); })
      .catch((e) => console.warn('[fitness]:', e?.message ?? e));
  };
  useFocusEffect(useCallback(() => { load(); }, []));

  const bumpGoal = async (delta: number) => {
    if (!fit?.dogId || savingGoal) return;
    const next = Math.min(50, Math.max(3, Math.round(fit.goalKm + delta)));
    if (next === fit.goalKm) return;
    setSavingGoal(true);
    const prev = fit.goalKm;
    setFit({ ...fit, goalKm: next }); // 낙관적 반영
    try {
      await updateDogGoal(fit.dogId, next);
    } catch (e) {
      setFit((f) => (f ? { ...f, goalKm: prev } : f));
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSavingGoal(false);
    }
  };

  // 선택 컷 — 사진이 줄어도 인덱스가 배열 밖으로 나가지 않게 파생 단계에서 클램프
  const idx = moments.length > 0 ? Math.min(selIdx, moments.length - 1) : 0;
  const sel: Moment | null = moments[idx] ?? null;

  const goalKm = fit?.goalKm ?? 0;
  const pct = fit && goalKm > 0 ? Math.min(fit.weekKm / goalKm, 1) : 0;
  const pctLabel = Math.round(pct * 100);
  const weeks = fit?.weeks ?? [];
  const maxWeek = weeks.length > 0 ? Math.max(...weeks.map((w) => w.km), goalKm * 0.6, 1) : 1;
  // 값 라벨은 이번 주 + 최고 주에만 (dataviz: 라벨은 선택적, 모든 바에 붙이면 축이 죽는다)
  const peakIdx = weeks.reduce((best, w, i) => (w.km > weeks[best].km ? i : best), 0);
  const runDays = fit?.runDays ?? [];
  const ageLabel = fit?.fitnessAge != null ? `${fit.fitnessAge}살` : null;

  // ── 모프 — 두 정적 레이어 크로스페이드 (owner-home 패턴 그대로: transform/opacity만, 레이아웃 애니메이션 없음)
  const scrollY = useRef(new Animated.Value(0)).current;
  const expOpacity = scrollY.interpolate({ inputRange: [0, MORPH_RANGE], outputRange: [1, 0], extrapolate: 'clamp' });
  const expSlide = scrollY.interpolate({ inputRange: [0, MORPH_RANGE], outputRange: [0, -12], extrapolate: 'clamp' });
  const cmpOpacity = scrollY.interpolate({ inputRange: [0, MORPH_RANGE], outputRange: [0, 1], extrapolate: 'clamp' });
  const cmpSlide = scrollY.interpolate({ inputRange: [0, MORPH_RANGE], outputRange: [-10, 0], extrapolate: 'clamp' });

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: GUTTER, paddingTop: 56, paddingBottom: 44 }}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
      >
        {/* ---------- 헤더 — 백 칩 · 마스트헤드 ---------- */}
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.backChip} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 19, fontWeight: '700', color: lilac.head, marginTop: -2 }}>‹</Text>
          </Pressable>
          <View style={{ alignItems: 'center' }}>
            <Text style={[s.mastTitle, df]}>체력 리포트</Text>
            <Text style={s.mastSub}>{fit?.dogName ?? '반려견'} · 이번 주</Text>
          </View>
          <View style={{ width: 38 }} />
        </Row>

        {/* ---------- 확장 히어로 (모프 출발 레이어) ---------- */}
        <Animated.View style={{ opacity: expOpacity, transform: [{ translateY: expSlide }] }}>
          {sel ? (
            <View style={s.filmBand}>
              <SprocketRow />
              {/* 파노라마 — 한 컷을 풀블리드로. 숫자는 사진 위 스크림에 얹는다 */}
              <View style={{ height: PANO_H }}>
                <Image source={{ uri: sel.url }} style={{ width: '100%', height: '100%' }} resizeMode="cover" />
                {/* 스크림 — expo-linear-gradient 미도입 프로젝트라 반투명 뷰를 겹쳐 램프를 만든다 */}
                <View pointerEvents="none" style={[s.scrim, { height: 96, backgroundColor: 'rgba(16,12,36,0.32)' }]} />
                <View pointerEvents="none" style={[s.scrim, { height: 62, backgroundColor: 'rgba(16,12,36,0.40)' }]} />
                <View pointerEvents="none" style={[s.scrim, { height: 34, backgroundColor: 'rgba(16,12,36,0.50)' }]} />
                <View style={s.counter}>
                  <Text style={[s.counterText, nf]}>{idx + 1} / {moments.length}</Text>
                </View>
                <View style={s.panoOverlay}>
                  <Row style={{ alignItems: 'baseline' }}>
                    <Text style={[s.panoKm, nf]}>{sel.km}</Text>
                    <Text style={[s.panoKmUnit, nf]}> km</Text>
                  </Row>
                  <Text style={s.panoWhen}>{sel.when}</Text>
                </View>
              </View>
              <SprocketRow />
              {/* 썸네일 레일 — 탭하면 파노라마가 그 컷으로 갈아끼워진다 */}
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.railContent}>
                {moments.map((m, i) => (
                  <Pressable
                    key={`${m.bookingId}-${i}`}
                    onPress={() => setSelIdx(i)}
                    style={[s.thumb, i === idx ? { borderColor: lilac.coral } : { borderColor: 'transparent', opacity: 0.55 }]}
                    accessibilityRole="button"
                    accessibilityLabel={`${m.when} ${m.km}km 사진 보기`}
                  >
                    <Image source={{ uri: m.url }} style={{ flex: 1 }} resizeMode="cover" />
                  </Pressable>
                ))}
              </ScrollView>
              {/* 엣지코드 — ① 시네 스트립의 필름 여백 각인 */}
              <Text style={[s.edgeCode, nf]}>{sel.km} KM · {sel.when}</Text>
            </View>
          ) : (
            /* 사진 0장 = 정직한 빈 프레임. 스톡/플레이스홀더 이미지 금지 */
            <View style={s.emptyFilm}>
              {fit?.dogPhotoUrl ? <Image source={{ uri: fit.dogPhotoUrl }} style={s.emptyDog} /> : null}
              <Text style={s.emptyCopy}>
                아직 러닝 사진이 없어요{'\n'}완주하면 러너가 남긴 순간이 여기 걸려요
              </Text>
            </View>
          )}

          {/* 데이터 밴드 — 이번 주 km 와 체력 나이가 나란히 선 공동 주역 */}
          <Row style={{ alignItems: 'flex-start', gap: 12, marginTop: 15 }}>
            <View style={{ flex: 1 }}>
              <Text style={s.bandLabel}>이번 주</Text>
              <Row style={{ alignItems: 'baseline' }}>
                <Text style={[s.bandBigWeek, nf]}>{fit ? fit.weekKm : '—'}</Text>
                <Text style={[s.bandUnit, nf]}> km</Text>
              </Row>
              <Text style={s.bandCap}>
                {fit ? `/ ${fit.goalKm}km 목표 · ${pctLabel}%` : '/ —km 목표 · —%'}
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={s.bandLabel}>체력 나이</Text>
              {fit == null ? (
                <Text style={[s.bandBigAge, nf]}>—</Text>
              ) : ageLabel ? (
                <Text style={[s.bandBigAge, nf]}>{ageLabel}</Text>
              ) : (
                <Text style={s.bandAgeGate}>측정 전</Text>
              )}
            </View>
          </Row>

          <View style={s.rail}>
            <View style={[s.railFill, { width: `${pctLabel}%` }]} />
          </View>

          {/* 요일 펀치 — 필름에 뚫린 구멍처럼 (runDays[7]) */}
          <Row style={{ gap: 9, marginTop: 13 }}>
            {DAYS.map((d, i) => {
              const on = runDays[i] === true;
              return (
                <View key={d} style={{ alignItems: 'center' }}>
                  <View style={[s.punch, on && { backgroundColor: FILM, borderColor: lilac.coralDeep }]}>
                    {on ? <View style={s.punchInner} /> : null}
                  </View>
                  <Text style={[s.punchLabel, on && s.punchLabelOn]}>{d}</Text>
                </View>
              );
            })}
          </Row>

          {/* 러닝 요약 — 랩 ①의 데이터 밴드 우측 열(횟수·페이스·연속)을 한 줄로. 로딩 중엔 0이 아니라 '—' */}
          <Text style={s.statLine}>
            {fit
              ? `${fit.weekRuns}회 러닝 · 평균 ${fmtPace(fit.avgPaceSec)} · 연속 ${fit.streakDays}일`
              : '—회 러닝 · 평균 — · 연속 —일'}
          </Text>
        </Animated.View>

        {/* ---------- 체력 나이 — 히어로가 헤드라인, 이 카드가 설명 ---------- */}
        <View style={s.card}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start', gap: 10 }}>
            <View style={{ flex: 1 }}>
              <Text style={s.cardTitle}>체력 나이</Text>
              <Text style={s.cardSub}>꾸준한 러닝이 체력 나이를 젊게 유지해요</Text>
            </View>
            {fit == null ? (
              <Text style={[s.ageVal, nf]}>—</Text>
            ) : ageLabel ? (
              <Text style={[s.ageVal, nf]}>{ageLabel}</Text>
            ) : (
              <Text style={s.ageValGate}>측정 전</Text>
            )}
          </Row>
          {fit == null ? null : fit.fitnessAge == null ? (
            <Text style={s.ageGate}>
              {fit.fitnessGate?.reason === 'runs'
                ? `최근 4주에 ${(fit.fitnessGate as any).left}번 더 완주하면 측정돼요 — 활동 데이터가 있어야 나이가 아니라 '체력'을 잴 수 있어요`
                : '반려견 프로필에 생일을 등록하면 측정이 시작돼요'}
            </Text>
          ) : (
            <Text style={s.ageGate}>
              베타 산식: 실제 나이 − 최근 4주 활동량·연속 기록 보정 (수의 검증 산식으로 교체 예정)
            </Text>
          )}
        </View>

        {/* ---------- 주간 목표 편집 (실저장 → 홈 링 즉시 반영) ---------- */}
        <View style={s.card}>
          <Text style={s.cardTitle}>주간 목표</Text>
          <Row style={{ justifyContent: 'space-between', marginTop: 12 }}>
            <Pressable onPress={() => bumpGoal(-1)} style={s.goalBtn} accessibilityRole="button" accessibilityLabel="주간 목표 1km 줄이기">
              <Text style={s.goalGlyph}>−</Text>
            </Pressable>
            <View style={{ alignItems: 'center' }}>
              <Text style={[s.goalVal, nf]}>{fit ? `${fit.goalKm}km` : '—'}</Text>
              <Text style={s.goalHint} numberOfLines={1}>홈 화면 링에 바로 반영돼요</Text>
            </View>
            <Pressable onPress={() => bumpGoal(1)} style={s.goalBtn} accessibilityRole="button" accessibilityLabel="주간 목표 1km 늘리기">
              <Text style={s.goalGlyph}>＋</Text>
            </Pressable>
          </Row>
        </View>

        {/* ---------- 8주 추이 ---------- */}
        <View style={s.card}>
          <Text style={s.cardTitle}>최근 8주</Text>
          <Row style={s.bars}>
            {weeks.map((w, i) => {
              const isNow = i === 7;
              const h = Math.max(Math.round((w.km / maxWeek) * BAR_MAX), w.km > 0 ? 6 : 2);
              return (
                <View key={w.label} style={s.barCol}>
                  {w.km > 0 && (isNow || i === peakIdx) ? <Text style={[s.barVal, nf]}>{w.km}</Text> : null}
                  <View style={[s.bar, { height: h, backgroundColor: isNow ? BAR_NOW : BAR_PAST }]} />
                </View>
              );
            })}
          </Row>
          <Row style={{ gap: 2, marginTop: 6 }}>
            {weeks.map((w, i) => (
              <Text key={w.label} style={[s.barX, i === 7 && s.barXNow]}>
                {i === 7 ? '이번주' : i === 0 ? '7주' : i === 2 ? '5주' : i === 4 ? '3주' : ''}
              </Text>
            ))}
          </Row>
        </View>

        {/* ---------- 최근 러닝 → 리포트 ---------- */}
        <Text style={s.sect}>최근 러닝</Text>
        {fit && fit.recent.length === 0 ? (
          <View style={s.emptyRuns}>
            <Text style={s.emptyCopy}>
              아직 완료된 러닝이 없어요{'\n'}첫 러닝을 예약하면 여기부터 채워져요
            </Text>
          </View>
        ) : null}
        {(fit?.recent ?? []).map((r) => (
          <Pressable
            key={r.bookingId}
            onPress={() => router.push({ pathname: '/owner/report', params: { bid: r.bookingId } })}
            style={s.runRow}
          >
            <View style={{ flex: 1 }}>
              <Text style={s.runWhen}>{r.when}</Text>
              <Text style={s.runMeta}>
                {r.km}km · {Math.floor(r.durationSec / 60)}분 · 리포트 보기 ›
              </Text>
            </View>
            <Text style={[s.runKm, nf]}>{r.km}km</Text>
          </Pressable>
        ))}
      </Animated.ScrollView>

      {/* ---------- 컴팩트 레이어 (모프 도착 레이어) — 다크 필름 리본.
          pointerEvents none: 투명할 때 아래 백 칩·카드 탭을 삼키지 않는다 ---------- */}
      <Animated.View
        pointerEvents="none"
        style={[s.ribbon, { opacity: cmpOpacity, transform: [{ translateY: cmpSlide }] }]}
      >
        <Row style={{ gap: 10 }}>
          <Text style={[s.ribbonTitle, df]}>체력 리포트</Text>
          <View style={s.miniSprocket}>
            {MINI_SPROCKETS.map((i) => <View key={i} style={s.miniDot} />)}
          </View>
          <Text style={[s.ribbonNum, nf]}>
            {fit ? fit.weekKm : '—'} KM · {fit == null ? '—' : ageLabel ?? '측정 전'}
          </Text>
        </Row>
      </Animated.View>
    </View>
  );
}

// 스프로킷 한 줄 — 필름 위아래 구멍. 이미지/그라디언트 없이 View만 (재합성 비용 0)
function SprocketRow() {
  return (
    <View style={s.sprocketRow}>
      {SPROCKETS.map((i) => <View key={i} style={s.sprocketDot} />)}
    </View>
  );
}

const s = StyleSheet.create({
  // ── 헤더 ──
  backChip: {
    width: 38, height: 38, borderRadius: 19, backgroundColor: lilac.card,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  mastTitle: { fontSize: 23, lineHeight: 30, fontWeight: '900', color: lilac.head, letterSpacing: 0.2 },
  mastSub: { fontSize: 12.5, lineHeight: 17, color: lilac.dim, marginTop: 1 },

  // ── 필름 밴드 (풀블리드) ──
  filmBand: { backgroundColor: FILM, marginHorizontal: -GUTTER, marginTop: 14 },
  sprocketRow: { height: 11, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 6 },
  sprocketDot: { width: 8, height: 5, borderRadius: 2.5, backgroundColor: lilac.bg },
  scrim: { position: 'absolute', left: 0, right: 0, bottom: 0 },
  counter: {
    position: 'absolute', right: 12, top: 10,
    backgroundColor: 'rgba(16,12,36,0.68)', borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9,
  },
  counterText: { fontSize: 13, lineHeight: 17, color: FILM_TITLE, letterSpacing: 1.2 },
  panoOverlay: { position: 'absolute', left: GUTTER, bottom: 10 },
  panoKm: { fontSize: 32, lineHeight: 40, color: '#fff' },
  panoKmUnit: { fontSize: 14, lineHeight: 19, color: 'rgba(255,255,255,0.85)' },
  panoWhen: { fontSize: 12.5, lineHeight: 18, color: 'rgba(255,255,255,0.88)' },
  railContent: { gap: 5, paddingHorizontal: 14, paddingTop: 7, paddingBottom: 4 },
  thumb: { width: 42, height: 31, borderRadius: 3, borderWidth: 2, overflow: 'hidden', backgroundColor: '#171332' },
  edgeCode: { fontSize: 12, lineHeight: 15, color: FILM_INK, letterSpacing: 0.8, paddingHorizontal: GUTTER, paddingBottom: 10 },

  // ── 빈 상태 (사진 0장) ──
  emptyFilm: {
    marginTop: 14, backgroundColor: lilac.card, borderRadius: lilacRadius.card,
    borderWidth: 1.6, borderStyle: 'dashed', borderColor: lilac.hair,
    paddingVertical: 20, paddingHorizontal: 16, alignItems: 'center',
  },
  emptyDog: { width: 40, height: 40, borderRadius: 20, marginBottom: 9, backgroundColor: lilac.inset },
  emptyCopy: { fontSize: 13.5, lineHeight: 22, color: lilac.dim, textAlign: 'center' },

  // ── 데이터 밴드 ──
  bandLabel: { fontSize: 12.5, lineHeight: 17, fontWeight: '600', color: lilac.dim },
  bandBigWeek: { fontSize: 40, lineHeight: 50, color: lilac.head },
  bandBigAge: { fontSize: 40, lineHeight: 50, color: lilac.coralDeep },
  bandUnit: { fontSize: 16, lineHeight: 21, color: lilac.dim },
  // 미측정은 가짜 숫자를 쓰지 않는다 — 서체도 Oswald가 아니다. lineHeight 50 = 좌측 숫자와 밑선 정렬
  bandAgeGate: { fontSize: 18, lineHeight: 50, fontWeight: '700', color: lilac.dim },
  bandCap: { fontSize: 12.5, lineHeight: 18, color: lilac.dim },
  rail: { height: 5, borderRadius: 3, backgroundColor: lilac.inset, marginTop: 11, overflow: 'hidden' },
  railFill: { height: '100%', borderRadius: 3, backgroundColor: lilac.coralDeep },

  // ── 요일 펀치 ──
  punch: {
    width: 19, height: 19, borderRadius: 10, borderWidth: 1.6,
    borderColor: lilac.hair, backgroundColor: lilac.card,
  },
  punchInner: { position: 'absolute', left: 0, top: 0, right: 0, bottom: 0, borderRadius: 8, borderWidth: 2.5, borderColor: lilac.coralSoft },
  punchLabel: { fontSize: 12, lineHeight: 16, color: lilac.dim, marginTop: 4 },
  punchLabelOn: { color: lilac.head, fontWeight: '700' },
  statLine: { fontSize: 12.5, lineHeight: 18, color: lilac.dim, marginTop: 12 },

  // ── 카드 ──
  card: {
    backgroundColor: lilac.card, borderRadius: lilacRadius.card, padding: 16,
    borderWidth: 1, borderColor: lilac.hair, marginTop: 12,
  },
  cardTitle: { fontSize: 15.5, lineHeight: 21, fontWeight: '700', color: lilac.head },
  cardSub: { fontSize: 13.5, lineHeight: 20, color: lilac.dim, marginTop: 3 },
  ageVal: { fontSize: 34, lineHeight: 43, color: lilac.coralDeep },
  ageValGate: { fontSize: 20, lineHeight: 27, fontWeight: '700', color: lilac.dim },
  ageGate: { fontSize: 13.5, lineHeight: 21, color: lilac.dim, marginTop: 9 },

  // ── 주간 목표 ──
  goalBtn: {
    width: 64, paddingVertical: 17, borderRadius: lilacRadius.btn,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, alignItems: 'center',
  },
  goalGlyph: { fontSize: 22, lineHeight: 27, fontWeight: '700', color: lilac.accent },
  goalVal: { fontSize: 29, lineHeight: 36, color: lilac.head },
  goalHint: { fontSize: 12, lineHeight: 16, color: lilac.dim, marginTop: 3 },

  // ── 8주 추이 ──
  bars: {
    alignItems: 'flex-end', gap: 2, height: 88, marginTop: 16,
    paddingBottom: 2, borderBottomWidth: 1, borderBottomColor: lilac.hair,
  },
  barCol: { flex: 1, height: '100%', alignItems: 'center', justifyContent: 'flex-end' },
  barVal: { fontSize: 12, lineHeight: 15, color: lilac.head, marginBottom: 3 },
  bar: { width: '62%', borderTopLeftRadius: 4, borderTopRightRadius: 4 },
  barX: { flex: 1, textAlign: 'center', fontSize: 12, lineHeight: 16, color: lilac.dim },
  barXNow: { color: lilac.coralDeep, fontWeight: '700' },

  // ── 최근 러닝 ──
  sect: { fontSize: 16, lineHeight: 22, fontWeight: '800', color: lilac.head, marginTop: 22, marginBottom: 8 },
  emptyRuns: {
    backgroundColor: lilac.inset, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: lilac.hair,
    paddingVertical: 18, paddingHorizontal: 16, alignItems: 'center',
  },
  runRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: lilac.card,
    borderRadius: lilacRadius.card, paddingVertical: 14, paddingHorizontal: 14,
    borderWidth: 1, borderColor: lilac.hair, marginBottom: 8,
  },
  runWhen: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: lilac.head },
  runMeta: { fontSize: 13.5, lineHeight: 19, color: lilac.dim, marginTop: 2 },
  runKm: { fontSize: 18, lineHeight: 23, color: lilac.coralDeep },

  // ── 컴팩트 리본 ──
  ribbon: {
    position: 'absolute', left: 0, right: 0, top: 0, zIndex: 30, backgroundColor: FILM,
    borderBottomLeftRadius: 10, borderBottomRightRadius: 10,
    paddingTop: 46, paddingBottom: 10, paddingHorizontal: GUTTER,
  },
  ribbonTitle: { fontSize: 15, lineHeight: 21, color: FILM_TITLE },
  miniSprocket: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  miniDot: { width: 5, height: 3, borderRadius: 2, backgroundColor: 'rgba(244,242,251,0.8)' },
  ribbonNum: { fontSize: 15, lineHeight: 19, color: FILM_NUM, letterSpacing: 0.4 },
});
