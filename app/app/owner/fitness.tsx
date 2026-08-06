import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Image, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { Row } from '../../src/components/ui';
import { fetchFitness, fetchRecentMoments, Fitness, Moment, updateDogGoal } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { lilac, lilacRadius, paper } from '../../src/theme';

// 체력 리포트 — 모프 링의 도착지. 브랜드의 심장: 반려견 피트니스.
// [2026-08-04 W4] 히어로 = 랩 ①(시네 스트립) 골격 × ③(파노라마 릴) 사진법.
//   필름 밴드(풀블리드) = 스프로킷 · 풀블리드 한 컷 + 스크림 · 썸네일 레일 · 엣지코드,
//   데이터 밴드 = 이번 주 km 와 체력 나이가 나란히 선 공동 주역(Sean: 나이를 더 세게).
// [은퇴] 포레스트/크림 서피스 · 볼트/탱 신호색 · 주간 링 위젯 — 테일러드 라일락으로 재도장.

const FILM = lilac.head;        // 필름 베이스 — 헤드 잉크(#221E3D)를 그대로 필름으로
const FILM_INK = '#C9C2E8';     // 엣지코드 잉크 (필름 위 라일락 실버)
const FILM_TITLE = '#F2EFFA';   // 리본 타이틀 · 카운터
const FILM_NUM = '#FFD9CD';     // 리본 숫자 — 코랄 틴트
const BAR_PAST = '#9787DC';     // 8주 바 과거 (validate_palette ALL PASS)
const BAR_NOW = lilac.coralDeep; // 8주 바 이번 주
const GUTTER = 16;              // 화면 좌우 여백 — 필름 밴드는 이 값만큼 음수 마진으로 풀블리드
// 바 영역 91 − paddingBottom 2 = 89 가용 · 값 라벨(lineHeight 18 + marginBottom 3) = 21 → 89 − 21 = 68.
// 66은 거기서 2px 더 보수적으로 잡은 값 (반올림·테두리 여유). 라벨이 잘리지 않는 쪽으로 남긴다.
// [FLOOR14] barVal 12/15 → 14/18 로 라벨이 3px 커져 s.bars height 를 88 → 91 로 키웠다 (바 자체 크기는 동결)
const BAR_MAX = 66;
const DAYS = ['월', '화', '수', '목', '금', '토', '일'] as const;
// 스프로킷 = 작은 배경색 점 줄 (그라디언트/이미지 없이 View만 — 프레임당 비용 0)
const SPROCKETS = Array.from({ length: 18 }, (_, i) => i);
const MINI_SPROCKETS = Array.from({ length: 12 }, (_, i) => i);

// ══ 핀 고정 히어로 기하 ══
// 히어로는 스크롤 콘텐츠가 아니라 상단 절대 오버레이다. 콘텐츠는 paddingTop = HERO_BIG + HERO_GAP 에서 시작하고,
// 히어로는 콘텐츠가 올라오는 속도와 '정확히 같은 속도'로 위로 미끄러진다 → 빈 공간 0, 겹침 0.
// 그래서 HERO_BIG 은 반드시 상태와 무관한 상수여야 한다 (사진 유/무/로딩이 높이를 바꾸면 collapse 거리가 흔들려 스크롤이 튄다).
// 아래 하위 높이는 전부 고정값이거나 명시 lineHeight — 기기 폰트 메트릭에 흔들리지 않는다.
// [FLOOR14 2026-08-05] 디테일 최소 활자 12–13.5 → 14pt 플로어. 히어로 안에서 높이를 바꾸는 건
// mastSub(17→18) · bandLabel(17→18) · punchLabel(16→18) 셋뿐이고, 아래 상수에 정확히 그만큼 더했다.
// edgeCode(필름 보이스) · counterText(시리얼)는 면제라 EDGE_H/FILM_H 불변. statLine은 lineHeight 18을 이미 갖고 있어 STAT_H 불변.
const PAD_TOP = 56;             // 상태바
const HEAD_H = 49;              // 백 칩(38) vs 마스트헤드(30 + 1 + 18 = 49) 중 큰 쪽 — mastSub lineHeight 17→18
const SPROCKET_H = 11;
const PANO_H = 200;
const THUMB_RAIL_H = 42;        // paddingTop 7 + 썸네일 31 + paddingBottom 4
const EDGE_H = 25;              // lineHeight 15 + paddingBottom 10 (edgeCode = 필름 엣지 보이스, 12pt 면제 → 불변)
const FILM_H = SPROCKET_H + PANO_H + SPROCKET_H + THUMB_RAIL_H + EDGE_H; // 11+200+11+42+25 = 289
const FILM_GAP = 14;
const BAND_H = 86;              // 라벨 18 + 숫자 50 + 캡션 18 — bandLabel lineHeight 17→18 (bandCap은 이미 18)
const BAND_GAP = 15;
const PROG_H = 16;              // marginTop 11 + 레일 5
const PUNCH_H = 54;             // marginTop 13 + 펀치 19 + 라벨(marginTop 4 + lineHeight 18) — punchLabel 16→18
const STAT_H = 30;              // marginTop 12 + lineHeight 18 (statLine 12.5→14, lineHeight 18 유지 = 1.29×)
const HERO_PAD_BOTTOM = 10;     // 산술 오차 흡수용 여유
// 합 검증: 56 + 49 + 14 + 289 + 15 + 86 + 16 + 54 + 30 + 10 = 619 (구 615, 승급분 +4 = HEAD +1, BAND +1, PUNCH +2)
const HERO_BIG =
  PAD_TOP + HEAD_H + FILM_GAP + FILM_H + BAND_GAP + BAND_H + PROG_H + PUNCH_H + STAT_H + HERO_PAD_BOTTOM; // 619
const RIBBON_H = 46 + 21 + 10;  // paddingTop + 콘텐츠(lineHeight 21) + paddingBottom = 77 — 리본 활자는 전부 ≥14라 불변
const COLLAPSE = HERO_BIG - RIBBON_H; // 619 - 77 = 542 — 히어로가 리본만 남기고 접히는 거리
const HERO_GAP = 12;            // 히어로 바닥 ↔ 첫 카드
// 페이드는 기하가 아니라 폴리시다. 접힘 '끝 구간'에서만 태워야 중간에 빈 캔버스가 생기지 않는다
// (COLLAPSE 가 페이드 길이보다 짧으면 자동으로 0부터 시작 = 원안과 동일 곡선).
const FADE_START = Math.max(0, COLLAPSE - 140);
const RIBBON_START = Math.max(0, COLLAPSE - 80);
// 리본 실버튼 전환 히스테리시스 — 경계에서 깜빡이지 않게 켜짐/꺼짐 임계를 벌린다
const PIN_ON = COLLAPSE - 40;
const PIN_OFF = COLLAPSE - 120;

const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');

export default function FitnessHub() {
  const df = useDisplayFont(); // 디스플레이 서체 — 이 화면의 유일한 Black Han Sans (상태당 1회)
  const nf = useNumFont();     // 숫자 = Oswald (모든 사용처에 명시 lineHeight)
  const { width: winW, height: winH } = useWindowDimensions(); // 회전·분할 대응 — Dimensions.get은 구독이 없어 stale (리뷰 P2)
  const [fit, setFit] = useState<Fitness | null>(null);
  const [moments, setMoments] = useState<Moment[] | null>(null); // null = 로딩, [] = 사진 없음(정직한 빈 상태)
  const [selIdx, setSelIdx] = useState(0);
  const [savingGoal, setSavingGoal] = useState(false);

  // 두 페치는 서로를 인질로 잡지 않는다 — 하나가 실패해도 나머지는 그려지고, 실패한 쪽은 직전 상태를 유지한다
  // (moments 를 []로 덮으면 '사진이 없어요'라는 거짓말이 된다).
  const [momentsErr, setMomentsErr] = useState(false); // 첫 로드 실패 시 무한 '불러오는 중' 방지 — 정직한 오류 프레임 + 재시도
  const loadMoments = () => {
    setMomentsErr(false);
    fetchRecentMoments(12)
      .then((ms) => { setMoments(ms); setMomentsErr(false); })
      .catch((e) => { console.warn('[fitness] moments:', e?.message ?? e); setMomentsErr(true); }); // 직전 상태 유지 — []로 덮으면 거짓말
  };
  // [정직 배치 2026-08-06 · item 5] 체력 실패는 실패로. 로딩('—')과 구별되는 라우드 페일 + 재시도.
  const [fitErr, setFitErr] = useState(false);
  const loadFit = () => {
    setFitErr(false);
    fetchFitness()
      .then((f) => { setFit(f); setFitErr(false); })
      .catch((e) => { console.warn('[fitness]:', e?.message ?? e); setFitErr(true); }); // 직전 실값 유지
  };
  const load = () => {
    loadFit();
    loadMoments();
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
  // 레일 수용량: 히어로가 absolute 오버레이가 되면서 가로 ScrollView가 페이지 스크롤러의 '형제'가 됐고,
  // RN의 중첩 스크롤 양보는 조상→자손만 작동한다 — 가로 레일이 세로 드래그를 삼키는 42px 데드존 (리뷰 P2).
  // 그래서 레일은 화면에 들어가는 만큼만 평면 Row로 건다. 카운터도 같은 부분집합 기준 (정직).
  // 파노라마 스와이프 페이저로 전량 탐색은 후속 (핸드오프).
  const railN = Math.max(3, Math.floor((winW - GUTTER * 2 - 28 + 5) / (42 + 5)));
  const shots = (moments ?? []).slice(0, railN);
  const idx = shots.length > 0 ? Math.min(selIdx, shots.length - 1) : 0;
  const sel: Moment | null = shots[idx] ?? null;

  const goalKm = fit?.goalKm ?? 0;
  const pct = fit && goalKm > 0 ? Math.min(fit.weekKm / goalKm, 1) : 0;
  const pctLabel = Math.round(pct * 100);
  const weeks = fit?.weeks ?? [];
  const maxWeek = weeks.length > 0 ? Math.max(...weeks.map((w) => w.km), goalKm * 0.6, 1) : 1;
  // 값 라벨은 이번 주 + 최고 주에만 (dataviz: 라벨은 선택적, 모든 바에 붙이면 축이 죽는다)
  const peakIdx = weeks.reduce((best, w, i) => (w.km > weeks[best].km ? i : best), 0);
  const runDays = fit?.runDays ?? [];
  const ageLabel = fit?.fitnessAge != null ? `${fit.fitnessAge}살` : null;

  // ── 모프 — 전부 transform/opacity (네이티브 드라이버). 높이·레이아웃 애니메이션 없음
  const scrollRef = useRef<any>(null); // Animated.ScrollView 의 forwarded ref 타입이 RN 버전마다 달라 느슨하게
  const scrollY = useRef(new Animated.Value(0)).current;
  const heroSlide = scrollY.interpolate({ inputRange: [0, COLLAPSE], outputRange: [0, -COLLAPSE], extrapolate: 'clamp' });
  const expOpacity = scrollY.interpolate({ inputRange: [FADE_START, COLLAPSE], outputRange: [1, 0], extrapolate: 'clamp' });
  const cmpOpacity = scrollY.interpolate({ inputRange: [RIBBON_START, COLLAPSE], outputRange: [0, 1], extrapolate: 'clamp' });
  const cmpSlide = scrollY.interpolate({ inputRange: [RIBBON_START, COLLAPSE], outputRange: [-10, 0], extrapolate: 'clamp' });

  // 리본이 '실제로 눌리는' 구간만 터치를 받는다 — pointerEvents:none 리본은 아래 콘텐츠로 탭이 새는 함정
  const [pinned, setPinned] = useState(false);
  const pinnedRef = useRef(false);
  useEffect(() => {
    const id = scrollY.addListener(({ value }: { value: number }) => {
      if (!pinnedRef.current && value > PIN_ON) { pinnedRef.current = true; setPinned(true); }
      else if (pinnedRef.current && value < PIN_OFF) { pinnedRef.current = false; setPinned(false); }
    });
    return () => scrollY.removeListener(id);
  }, [scrollY]);

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      {/* ---------- 스크롤 콘텐츠 — 히어로 높이만큼 아래에서 시작 ---------- */}
      <Animated.ScrollView
        ref={scrollRef}
        style={{ flex: 1 }}
        // minHeight = 화면 + COLLAPSE: 콘텐츠가 적어도(러닝 0회) 리본까지 접힘이 항상 도달 가능해야
        // 모프가 '중간에 걸린' 채 끝나지 않는다 (구현 리뷰 리스크 — 감독 수용)
        contentContainerStyle={{ paddingHorizontal: GUTTER, paddingTop: HERO_BIG + HERO_GAP, paddingBottom: 44, minHeight: winH + COLLAPSE }}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
      >
        {/* ---------- 체력 로드 실패 스트립 (item 5) — 히어로는 고정 높이 핀 오버레이(모프 배관 불가침)라
             스크롤 콘텐츠 최상단, 히어로 바로 아래에 붙인다. 히어로의 '—'가 로딩인지 실패인지 여기서 갈린다 ---------- */}
        {fitErr && (
          <View style={s.fitFail}>
            <Text style={s.fitFailTxt}>체력 기록을 불러오지 못했어요</Text>
            <Pressable onPress={loadFit} hitSlop={8} accessibilityRole="button" accessibilityLabel="체력 기록 다시 불러오기">
              <Text style={s.fitFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
        )}

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
              // [FLOOR14] 라벨 칸은 8분할이라 30~39px뿐 — 14pt '이번주'(3음절 ≈42px)는 두 줄로 접힌다.
              // '이번'(≈28px)이면 최소폭 기기(320dp, 칸 30.3px)에서도 한 줄. numberOfLines로 못을 박는다.
              <Text key={w.label} style={[s.barX, i === 7 && s.barXNow]} numberOfLines={1}>
                {i === 7 ? '이번' : i === 0 ? '7주' : i === 2 ? '5주' : i === 4 ? '3주' : ''}
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

      {/* ---------- 핀 고정 히어로 (확장 레이어) — 콘텐츠가 올라오는 속도와 같은 속도로 미끄러진다.
          box-none + 비인터랙티브 서브트리 pointerEvents:none → 히어로 위를 드래그해도 아래 스크롤이 먹는다.
          실제로 터치를 받는 건 백 칩과 썸네일 레일 둘뿐. ---------- */}
      <Animated.View pointerEvents="box-none" style={[s.heroWrap, { transform: [{ translateY: heroSlide }] }]}>
        <Animated.View pointerEvents="box-none" style={{ opacity: expOpacity }}>
          {/* 헤더 — 백 칩 · 마스트헤드 */}
          <View pointerEvents="box-none" style={s.headRow}>
            <Pressable onPress={() => router.back()} style={s.backChip} accessibilityRole="button" accessibilityLabel="뒤로">
              <Text style={{ fontSize: 19, fontWeight: '700', color: lilac.head, marginTop: -2 }}>‹</Text>
            </Pressable>
            <View pointerEvents="none" style={{ alignItems: 'center' }}>
              <Text style={[s.mastTitle, df]}>체력 리포트</Text>
              <Text style={s.mastSub}>{fit?.dogName ?? '반려견'} · 이번 주</Text>
            </View>
            <View pointerEvents="none" style={{ width: 38 }} />
          </View>

          {moments == null && momentsErr ? (
            /* 첫 로드 실패 — 실패는 실패로. 무한 '불러오는 중'과 구별되는 오류 프레임 + 재시도 문 */
            <View pointerEvents="box-none" style={s.filmBand}>
              <SprocketRow />
              <View pointerEvents="box-none" style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 10 }}>
                <Text style={s.filmNote}>순간을 불러오지 못했어요</Text>
                <Pressable onPress={loadMoments} style={s.filmRetry} accessibilityRole="button" accessibilityLabel="사진 다시 불러오기">
                  <Text style={s.filmRetryTxt}>다시 시도</Text>
                </Pressable>
              </View>
              <SprocketRow />
            </View>
          ) : moments == null ? (
            /* 로딩 — 빈 상태 카피를 쓰지 않는다. 사진이 없는 건지 아직 모른다 */
            <View pointerEvents="none" style={s.filmBand}>
              <SprocketRow />
              <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
                <Text style={s.filmNote}>순간을 불러오는 중…</Text>
              </View>
              <SprocketRow />
            </View>
          ) : sel == null ? (
            /* 사진 0장 = 정직한 빈 프레임. 스톡/플레이스홀더 이미지 금지 */
            <View pointerEvents="none" style={s.emptySlot}>
              <View style={s.emptyFilm}>
                {fit?.dogPhotoUrl ? <Image source={{ uri: fit.dogPhotoUrl }} style={s.emptyDog} /> : null}
                <Text style={s.emptyCopy}>
                  아직 러닝 사진이 없어요{'\n'}완주하면 러너가 남긴 순간이 여기 걸려요
                </Text>
              </View>
            </View>
          ) : (
            <View pointerEvents="box-none" style={s.filmBand}>
              <SprocketRow />
              {/* 파노라마 — 한 컷을 풀블리드로. 숫자는 사진 위 스크림에 얹는다 */}
              <View pointerEvents="none" style={{ height: PANO_H }}>
                <Image source={{ uri: sel.url }} style={{ width: '100%', height: '100%' }} resizeMode="cover" />
                {/* 스크림 — expo-linear-gradient 미도입 프로젝트라 반투명 뷰를 겹쳐 램프를 만든다 */}
                <View style={[s.scrim, { height: 96, backgroundColor: 'rgba(16,12,36,0.32)' }]} />
                <View style={[s.scrim, { height: 62, backgroundColor: 'rgba(16,12,36,0.40)' }]} />
                <View style={[s.scrim, { height: 34, backgroundColor: 'rgba(16,12,36,0.50)' }]} />
                <View style={s.counter}>
                  <Text style={[s.counterText, nf]}>{idx + 1} / {shots.length}</Text>
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
              <View style={s.railRow}>
                {shots.map((m, i) => (
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
              </View>
              {/* 엣지코드 — ① 시네 스트립의 필름 여백 각인 */}
              <View pointerEvents="none">
                <Text style={[s.edgeCode, nf]}>{sel.km} KM · {sel.when}</Text>
              </View>
            </View>
          )}

          {/* 데이터 밴드 · 진행 레일 · 요일 펀치 · 러닝 요약 — 전부 읽기 전용이라 한 겹으로 터치를 비운다 */}
          <View pointerEvents="none">
            <Row style={{ alignItems: 'flex-start', gap: 12, marginTop: BAND_GAP }}>
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
              {/* 로딩 중엔 0% 막대를 그리지 않는다 — 옆 텍스트는 '—'인데 막대만 '0'을 주장하는 모순 방지 */}
              {fit != null && <View style={[s.railFill, { width: `${pctLabel}%` }]} />}
            </View>

            {/* 요일 펀치 — 필름에 뚫린 구멍처럼 (runDays[7]) */}
            <Row style={{ gap: 9, marginTop: 13 }}>
              {DAYS.map((d, i) => {
                const on = fit != null && runDays[i] === true; // 로딩 중 '전부 안 뜀' 주장 방지 — fit 전엔 중립 링만
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
          </View>
        </Animated.View>
      </Animated.View>

      {/* ---------- 컴팩트 리본 (모프 도착 레이어) — 접힌 동안엔 '펼치기' 실버튼.
          투명할 땐 pointerEvents:none 이라 아래 히어로/콘텐츠를 가리지 않고,
          불투명할 땐 auto 라 탭이 리본에서 멈춘다 (숨은 버튼으로 새지 않는다) ---------- */}
      <Animated.View
        pointerEvents={pinned ? 'auto' : 'none'}
        style={[s.ribbon, { opacity: cmpOpacity, transform: [{ translateY: cmpSlide }] }]}
      >
        <Pressable
          onPress={() => scrollRef.current?.scrollTo({ y: 0, animated: true })}
          style={s.ribbonPress}
          accessibilityRole="button"
          accessibilityLabel="체력 리포트 요약 펼치기"
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
        </Pressable>
      </Animated.View>
    </View>
  );
}

// 스프로킷 한 줄 — 필름 위아래 구멍. 이미지/그라디언트 없이 View만 (재합성 비용 0)
function SprocketRow() {
  return (
    <View pointerEvents="none" style={s.sprocketRow}>
      {SPROCKETS.map((i) => <View key={i} style={s.sprocketDot} />)}
    </View>
  );
}

const s = StyleSheet.create({
  // 체력 로드 실패 스트립 — 라우드 페일 문법(F1.2): 위아래 1px critical 헤어라인 · 14pt/700 critical
  // 잉크 · 캔버스 바닥 · 재시도는 텍스트 버튼. GUTTER 밖까지 나가는 풀블리드는 음수 마진으로.
  fitFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    marginHorizontal: -GUTTER, paddingVertical: 11, paddingHorizontal: GUTTER,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
  },
  fitFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  fitFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // ── 핀 고정 히어로 ──
  heroWrap: {
    position: 'absolute', left: 0, right: 0, top: 0, height: HERO_BIG, zIndex: 20,
    backgroundColor: lilac.bg, paddingTop: PAD_TOP, paddingHorizontal: GUTTER,
    overflow: 'hidden', // fontScale 확대 시 고정 높이를 넘친 히어로가 아래 카드를 덮는 것 방지 (owner-home:513 선례)
  },
  headRow: { height: HEAD_H, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  backChip: {
    width: 38, height: 38, borderRadius: 19, backgroundColor: lilac.card,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  mastTitle: { fontSize: 23, lineHeight: 30, fontWeight: '900', color: lilac.head, letterSpacing: 0.2 },
  mastSub: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 1 },

  // ── 필름 밴드 (풀블리드) — 파노라마/로딩/빈 상태 모두 정확히 같은 높이 ──
  filmBand: { backgroundColor: FILM, marginHorizontal: -GUTTER, marginTop: FILM_GAP, height: FILM_H },
  filmNote: { fontSize: 14, lineHeight: 20, color: FILM_INK },
  filmRetry: { paddingVertical: 10, paddingHorizontal: 24, borderRadius: 8, backgroundColor: 'rgba(244,242,251,0.12)', borderWidth: 1, borderColor: 'rgba(201,194,232,0.4)' },
  filmRetryTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: '#F2EFFA' },
  emptySlot: { marginTop: FILM_GAP, height: FILM_H, justifyContent: 'center' },
  sprocketRow: { height: SPROCKET_H, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 6 },
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
  panoWhen: { fontSize: 14, lineHeight: 18, color: 'rgba(255,255,255,0.88)' },
  railRow: { flexDirection: 'row', gap: 5, paddingHorizontal: 14, paddingTop: 7, paddingBottom: 4 },
  thumb: { width: 42, height: 31, borderRadius: 3, borderWidth: 2, overflow: 'hidden', backgroundColor: '#171332' },
  edgeCode: { fontSize: 12, lineHeight: 15, color: FILM_INK, letterSpacing: 0.8, paddingHorizontal: GUTTER, paddingBottom: 10 },
  emptyFilm: {
    backgroundColor: lilac.card, borderRadius: lilacRadius.card,
    borderWidth: 1.6, borderStyle: 'dashed', borderColor: lilac.hair,
    paddingVertical: 20, paddingHorizontal: 16, alignItems: 'center',
  },
  emptyDog: { width: 40, height: 40, borderRadius: 20, marginBottom: 9, backgroundColor: lilac.inset },
  emptyCopy: { fontSize: 14, lineHeight: 22, color: lilac.dim, textAlign: 'center' },

  // ── 데이터 밴드 ──
  bandLabel: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.dim },
  bandBigWeek: { fontSize: 40, lineHeight: 50, color: lilac.head },
  bandBigAge: { fontSize: 40, lineHeight: 50, color: lilac.coralDeep },
  bandUnit: { fontSize: 16, lineHeight: 21, color: lilac.dim },
  // 미측정은 가짜 숫자를 쓰지 않는다 — 서체도 Oswald가 아니다. lineHeight 50 = 좌측 숫자와 밑선 정렬
  bandAgeGate: { fontSize: 18, lineHeight: 50, fontWeight: '700', color: lilac.dim },
  bandCap: { fontSize: 14, lineHeight: 18, color: lilac.dim },
  rail: { height: 5, borderRadius: 3, backgroundColor: lilac.inset, marginTop: 11, overflow: 'hidden' },
  railFill: { height: '100%', borderRadius: 3, backgroundColor: lilac.coralDeep },

  // ── 요일 펀치 · 러닝 요약 ──
  punch: {
    width: 19, height: 19, borderRadius: 10, borderWidth: 1.6,
    borderColor: lilac.hair, backgroundColor: lilac.card,
  },
  punchInner: { position: 'absolute', left: 0, top: 0, right: 0, bottom: 0, borderRadius: 8, borderWidth: 2.5, borderColor: lilac.coralSoft },
  punchLabel: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 4 },
  punchLabelOn: { color: lilac.head, fontWeight: '700' },
  statLine: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 12 },

  // ── 카드 ──
  card: {
    backgroundColor: lilac.card, borderRadius: lilacRadius.card, padding: 16,
    borderWidth: 1, borderColor: lilac.hair, marginTop: 12,
  },
  cardTitle: { fontSize: 15.5, lineHeight: 21, fontWeight: '700', color: lilac.head },
  cardSub: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 3 },
  ageVal: { fontSize: 34, lineHeight: 43, color: lilac.coralDeep },
  ageValGate: { fontSize: 20, lineHeight: 27, fontWeight: '700', color: lilac.dim },
  ageGate: { fontSize: 14, lineHeight: 21, color: lilac.dim, marginTop: 9 },

  // ── 주간 목표 ──
  goalBtn: {
    width: 64, paddingVertical: 17, borderRadius: lilacRadius.btn,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, alignItems: 'center',
  },
  goalGlyph: { fontSize: 22, lineHeight: 27, fontWeight: '700', color: lilac.accent },
  goalVal: { fontSize: 29, lineHeight: 36, color: lilac.head },
  goalHint: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 3 },

  // ── 8주 추이 ──
  bars: {
    alignItems: 'flex-end', gap: 2, height: 91, marginTop: 16, // [FLOOR14] 88 → 91: barVal 라벨 18+3 (구 15+3)
    paddingBottom: 2, borderBottomWidth: 1, borderBottomColor: lilac.hair,
  },
  barCol: { flex: 1, height: '100%', alignItems: 'center', justifyContent: 'flex-end' },
  barVal: { fontSize: 14, lineHeight: 18, color: lilac.head, marginBottom: 3 },
  bar: { width: '62%', borderTopLeftRadius: 4, borderTopRightRadius: 4 },
  barX: { flex: 1, textAlign: 'center', fontSize: 14, lineHeight: 18, color: lilac.dim },
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
  runMeta: { fontSize: 14, lineHeight: 19, color: lilac.dim, marginTop: 2 },
  runKm: { fontSize: 18, lineHeight: 23, color: lilac.coralDeep },

  // ── 컴팩트 리본 ──
  ribbon: {
    position: 'absolute', left: 0, right: 0, top: 0, height: RIBBON_H, zIndex: 40, backgroundColor: FILM,
    borderBottomLeftRadius: 10, borderBottomRightRadius: 10, overflow: 'hidden',
  },
  ribbonPress: { flex: 1, paddingTop: 46, paddingBottom: 10, paddingHorizontal: GUTTER },
  ribbonTitle: { fontSize: 15, lineHeight: 21, color: FILM_TITLE },
  miniSprocket: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  miniDot: { width: 5, height: 3, borderRadius: 2, backgroundColor: 'rgba(244,242,251,0.8)' },
  ribbonNum: { fontSize: 15, lineHeight: 19, color: FILM_NUM, letterSpacing: 0.4 },
});
