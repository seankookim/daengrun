import { router } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Pressable, StyleSheet, Text, View } from 'react-native';
import { Avatar, Monogram, Row } from '../../src/components/ui';
import { fetchCertifiedRunners, fetchGearFor, fetchRunnerProfile, GEAR_META, GearItem, LiveRunner, requestRunner } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 선택 — AI 추천 banner + 1순위 dark card + alternatives, per mock.

const FOREST = '#0F1D13';
const FOREST_INNER = '#1d3023';

// 캐러셀 카드 내부 스탯 컬럼 (배경색에 따라 텍스트 색 가변)
function MiniCol({ v, l, g, main, dim }: { v: string; l: string; g?: string; main: string; dim: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      {g ? <Text style={{ fontSize: 12.5, color: dim, marginBottom: 3 }}>{g}</Text> : null}
      <Text style={{ fontSize: 16.5, fontWeight: '900', color: main }}>{v}</Text>
      <Text style={{ fontSize: 11, color: dim, marginTop: 2 }}>{l}</Text>
    </View>
  );
}

// 스택 카드 팔레트 — 풀와이드 파스텔, 채도 살짝 ↑ (페일 그레이 배경과 분리)
const PALETTE = ['#DDF0A6', '#C3D9AE', '#FFCDB6', '#F2DA96'];

// 러너 풀 카드 — 배경 캐러셀 레이어와 액티브 오버레이가 정확히 같은 컴포넌트를 공유
function RunnerFullCard({ r, m, i, topIsPreferred, nominating, onNominate, onLayout, focused, gear }: {
  r: LiveRunner; m: Match; i: number; topIsPreferred: boolean;
  nominating: string | null; onNominate: (r: LiveRunner) => void;
  onLayout?: (e: any) => void; focused: boolean; gear?: GearItem[];
}) {
  // 다크 트리트먼트는 1순위 카드 고정 — 포커스 연동 색 전환은 급작스러워 제거 (2026-07-27)
  const df = useDisplayFont();
  const dark = i === 0;
  const bg = dark ? FOREST : PALETTE[(i - 1 + PALETTE.length) % PALETTE.length];
  const tMain = dark ? '#fff' : FOREST;
  const tDim = dark ? '#b8c4ae' : '#49524a';
  const barTrack = dark ? '#2c4034' : '#ffffff99';
  const barFill = dark ? colors.volt : colors.voltDeep;
  return (
    <View
      onLayout={onLayout}
      style={[
        s.fullCard,
        { backgroundColor: bg },
        // 라임 아우터 글로우 (드롭 섀도우는 래퍼가 담당 — 뷰당 그림자 1개 제한)
        dark && { borderWidth: 1.5, borderColor: colors.volt, shadowColor: colors.volt, shadowOpacity: 0.3, shadowRadius: 9, shadowOffset: { width: 0, height: 0 } },
      ]}
    >
      {/* 포커스 카드 장식 — 상단 미광(수직 그라데이션 근사) + 우측 컨투어 라인 */}
      {dark && (
        <View pointerEvents="none" style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, borderRadius: 22, overflow: 'hidden' }}>
          <View style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '45%', backgroundColor: 'rgba(255,255,255,0.03)' }} />
          <View style={s.contour1} />
          <View style={s.contour2} />
          <View style={s.contour3} />
        </View>
      )}

      <View style={[s.rankTab, !dark && { backgroundColor: FOREST }]}>
        <Text style={{ fontSize: 12.5, fontWeight: '900', color: dark ? FOREST : '#fff' }}>
          {i === 0 ? (topIsPreferred ? '★ 내가 고른 러너' : '★ 추천 1순위') : `${i + 1}순위 · 적합 ${m.total}%`}
        </Text>
      </View>
      {dark && (
        <View style={s.fitPill}><Text style={{ fontSize: 12.5, fontWeight: '900', color: FOREST }}>적합도 {m.total}%</Text></View>
      )}

      <Pressable onPress={() => router.push(`/runner-profile/${r.profileId}`)}>
        <Row style={{ gap: 12, marginTop: 4 }}>
          <View style={{ width: 56, height: 56 }}>
            <Avatar url={r.avatarUrl} char={r.name[0]} bg="#5a7a3c" size={56} />
            {dark && <View style={s.checkBadge}><Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>✓</Text></View>}
          </View>
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 7 }}>
              <Text style={{ fontSize: 23, fontWeight: '900', color: tMain }}>{r.name}</Text>
              <Text style={{ fontSize: 12.5, fontWeight: '800', color: dark ? colors.volt : '#5a7a3c', alignSelf: 'center' }}>프로필 ›</Text>
            </Row>
            <Text style={{ fontSize: 13, color: tDim, marginTop: 4 }}>
              {r.tier} · {r.district || '근처'} · 러닝 {r.totalRuns}회
            </Text>
          </View>
        </Row>
      </Pressable>

      {/* match bars — 모든 카드에 */}
      <View style={{ gap: 8, marginTop: 12 }}>
        {m.reasons.map((reason) => (
          <View key={reason.label}>
            <Row style={{ justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 13, color: tDim }}>{reason.glyph} {reason.label}</Text>
              <Text style={{ fontSize: 14, fontWeight: '900', color: tMain }}>{reason.pct}%</Text>
            </Row>
            <View style={{ height: 6, borderRadius: 99, backgroundColor: barTrack, marginTop: 5, overflow: 'hidden' }}>
              <View style={{ height: 6, borderRadius: 99, backgroundColor: barFill, width: `${reason.pct}%` }} />
            </View>
          </View>
        ))}
      </View>

      {/* stat strip — 모든 카드에 */}
      <Row style={{ marginTop: 12, borderRadius: 14, backgroundColor: dark ? FOREST_INNER : '#ffffff88', paddingVertical: 10, justifyContent: 'space-around' }}>
        <MiniCol v={r.paceLabel} l="평균 페이스" g="◷" main={tMain} dim={tDim} />
        <MiniCol v={`${r.totalRuns}회`} l="완료 러닝" g="⚑" main={tMain} dim={tDim} />
        <MiniCol v={r.respondRate != null ? `${r.respondRate}%` : '신규'} l="응답률" g="✦" main={tMain} dim={tDim} />
      </Row>

      {/* 인증 장비 칩 (0019) — 사진으로 인증된 슬롯만. 없으면 그리지 않는다 */}
      {gear && gear.some((g) => g.verified) && (
        <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
          {gear.filter((g) => g.verified).map((g) => (
            <View key={g.id} style={[s.gearChip, dark && { backgroundColor: FOREST_INNER }]}>
              <Text style={{ fontSize: 11.5, fontWeight: '800', color: dark ? colors.volt : '#3d5a2b' }}>
                {GEAR_META[g.kind].glyph} {GEAR_META[g.kind].name} ✓
              </Text>
            </View>
          ))}
        </Row>
      )}

      <Pressable
        onPress={() => onNominate(r)}
        disabled={nominating !== null}
        style={[s.fullNominate, { backgroundColor: dark ? colors.volt : FOREST }, nominating === r.profileId && { opacity: 0.5 }]}
      >
        <Row style={{ gap: 8 }}>
          <Text style={[{ fontSize: 16, fontWeight: '900', color: dark ? FOREST : '#fff' }, df]}>
            {nominating === r.profileId ? '전송 중...' : `${r.name} 러너 지명 요청`}
          </Text>
          <Text style={{ fontSize: 17, fontWeight: '900', color: dark ? FOREST : '#fff' }}>›</Text>
        </Row>
      </Pressable>
    </View>
  );
}

// 실러너 추천 점수 — 응답률·경험·페이스 적합의 가중합.
// 데이터가 쌓이면 매칭 엔진(견종 경험·후기·거리)으로 교체. 병원 레지던트식 하이브리드 매칭의 v1.
interface Match { total: number; reasons: { glyph: string; label: string; pct: number }[] }
// gearVerified: 인증 장비 부스트 — 슬롯당 +1, 최대 +2 (가드레일: 핵심 점수 불변, 장비는 승부축이 아니다)
function matchFor(r: LiveRunner, gearVerified = 0, targetPaceSec = 420): Match {
  const respond = r.respondRate ?? 88;
  const exp = Math.min(97, 62 + r.totalRuns * 5);
  const paceFit = Math.max(58, 100 - Math.round(Math.abs(r.paceSec - targetPaceSec) / 4));
  return {
    total: Math.min(99, Math.round(respond * 0.35 + exp * 0.3 + paceFit * 0.35) + Math.min(2, gearVerified)),
    reasons: [
      { glyph: '⚡', label: '응답 신뢰도', pct: respond },
      { glyph: '⛨', label: '러닝 경험', pct: exp },
      { glyph: '➤', label: '페이스 적합', pct: paceFit },
    ],
  };
}

export default function Matching() {
  const df = useDisplayFont(); // 디스플레이 서체 — 헤더 타이틀
  // 목업 러너 참조 은퇴 — 이 화면은 실러너 전용 (2026-07-23)
  const live = !!draft.bookingId;
  const [liveRunners, setLiveRunners] = useState<LiveRunner[]>([]);
  const [nominating, setNominating] = useState<string | null>(null);
  // 러너별 장비 로드아웃 (0019) — 배치 조회, 실패해도 카드는 뜬다
  const [gearMap, setGearMap] = useState<Record<string, GearItem[]>>({});

  useEffect(() => {
    const ids = liveRunners.map((r) => r.profileId);
    if (ids.length === 0) return;
    fetchGearFor(ids).then(setGearMap).catch((e) => console.warn('[matching] gear:', e?.message ?? e));
  }, [liveRunners]);

  useEffect(() => {
    if (live) fetchCertifiedRunners().then(setLiveRunners).catch((e) => console.warn('[matching] runners:', e?.message ?? e));
  }, [live]);

  // 선호 러너가 오프라인이라 목록에 없어도 반드시 보이게 주입 (지명은 오프라인이어도 가능)
  useEffect(() => {
    const pref = draft.preferredRunnerId;
    if (!live || !pref || liveRunners.some((r) => r.profileId === pref)) return;
    fetchRunnerProfile(pref)
      .then((p) => {
        setLiveRunners((cur) => (cur.some((r) => r.profileId === pref) ? cur : [{
          profileId: p.profileId, name: p.name, district: p.district, tier: p.tier,
          totalRuns: p.totalRuns, paceLabel: p.paceLabel, paceSec: 420,
          respondRate: p.respondRate, avatarUrl: p.avatarUrl, bio: p.bio,
        }, ...cur]));
      })
      .catch((e) => console.warn('[matching] pref inject:', e?.message ?? e));
  }, [live, liveRunners]);

  // 프로필→슬롯→결제로 온 경우: 이미 러너를 골랐으므로 지명을 자동 전송 (CTA 약속 이행)
  const autoRef = useRef(false);
  useEffect(() => {
    const pref = draft.preferredRunnerId;
    if (!live || !pref || !draft.bookingId || autoRef.current) return;
    autoRef.current = true;
    requestRunner(draft.bookingId, pref)
      .then(() => {
        const name = draft.preferredRunnerName ?? '선택한';
        draft.preferredRunnerId = null;
        draft.preferredRunnerName = null;
        Alert.alert('지명 요청 전송', `${name} 러너에게 우선 요청을 보냈어요.\n수락하면 알림으로 알려드릴게요.`);
        router.replace('/owner/schedule');
      })
      .catch((e) => {
        autoRef.current = false; // 실패 → 수동 지명 리스트로 폴백
        console.warn('[matching] auto-nominate:', e?.message ?? e);
      });
  }, [live]);

  // 점수순 정렬 — 1위는 추천 카드, 나머지는 대안 리스트.
  // 프로필에서 '이 러너와 예약하기'로 왔으면 그 러너가 최상단.
  const scored = useMemo(() => {
    const arr = liveRunners
      .map((r) => ({ r, m: matchFor(r, (gearMap[r.profileId] ?? []).filter((g) => g.verified).length) }))
      .sort((a, b) => b.m.total - a.m.total);
    if (draft.preferredRunnerId) {
      const i = arr.findIndex((x) => x.r.profileId === draft.preferredRunnerId);
      if (i > 0) arr.unshift(arr.splice(i, 1)[0]);
    }
    return arr;
  }, [liveRunners, gearMap]);
  const top = scored[0];
  const rest = scored.slice(1);
  const topIsPreferred = !!top && top.r.profileId === draft.preferredRunnerId;

  const nominate = async (r: LiveRunner) => {
    if (!draft.bookingId) return;
    setNominating(r.profileId);
    try {
      await requestRunner(draft.bookingId, r.profileId);
      draft.preferredRunnerId = null; // 지명 완료 — 선호 러너 상태 소거
      Alert.alert('지명 요청 전송', `${r.name} 러너에게 요청을 보냈어요.\n수락하면 알림으로 알려드릴게요.`);
      router.replace('/owner/schedule');
    } catch (e) {
      Alert.alert('요청 실패', (e as Error).message);
    } finally {
      setNominating(null);
    }
  };

  // ── 캐러셀 지오메트리 ─────────────────────────────────────────
  // 애플 월렛식 덱: STEP은 카드당 스크롤 트래블(고정), 이웃 카드는 translateY 클램프로
  // 액티브 곁에 붙는다 — 이전 카드는 상단 ~140px 피크, 다음 카드는 액티브 하단 아래 피크.
  const [cardH, setCardH] = useState(470);      // onLayout 실측으로 갱신
  const STEP = 260;                              // 카드 1장당 스크롤 거리
  const FOCUS_TOP = 16;                          // 스크롤러 상단(=헤더 하단)에서 포커스 카드 top까지
  const SCREEN_H = Dimensions.get('window').height;
  const TAIL = Math.max(140, SCREEN_H - cardH - 160); // 마지막 카드 스냅용 꼬리
  const N = scored.length;
  // 카드가 절대좌표(top = FOCUS_TOP + i*STEP)라 콘텐츠 높이를 명시
  const contentH = N > 0 ? FOCUS_TOP + cardH + (N - 1) * STEP + TAIL : undefined;

  const scrollY = useRef(new Animated.Value(0)).current;
  const [focusIdx, setFocusIdx] = useState(0);
  const focusRef = useRef(0);
  const safeFocus = Math.min(Math.max(0, focusIdx), Math.max(0, N - 1));
  const onFocusChange = (idx: number) => {
    focusRef.current = idx;
    setFocusIdx(idx);
    try { require('expo-haptics').impactAsync(require('expo-haptics').ImpactFeedbackStyle.Light); } catch {}
  };

  // 물리 커브 — 두 레이어(배경/오버레이)가 완전히 동일한 scrollY 함수를 공유해 픽셀 단위로 일치.
  // 입력축 = 카드의 부호 있는 포커스 거리. 비선형(포커스 근처 라운드) 벌지 + 엣지 기준 회전 + 덱 클램프.
  const physicsFor = (i: number) => {
    const f = i * STEP;
    const in5 = [f - 2 * STEP, f - STEP, f, f + STEP, f + 2 * STEP];
    // 포커스 ±S/2에 중간점 — 스케일이 선형이 아니라 스프링처럼 둥글게 부풀도록
    const in7 = [f - 2 * STEP, f - STEP, f - STEP / 2, f, f + STEP / 2, f + STEP, f + 2 * STEP];
    const H2 = cardH / 2;
    // 덱 클램프 translateY:
    // 위(이전) 카드는 기존대로 상단 ~140px 피크.
    // 아래(다음) 카드들은 액티브 '밑으로 턱' — 상반신은 액티브(오버레이가 항상 위) 뒤에 숨고,
    // 바닥 엣지만 56px 계단으로 노출: 액티브 아래로 +1 바닥, 그 아래 +2 바닥 (Sean 안).
    // 반투명 이중노출 없이 전부 불투명 — 겹침은 z가 아니라 '아래 카드 바닥이 더 낮다'로 표현.
    // effective bottom = top + T + cardH·(1+s)/2  (센터 스케일 보정)
    const T_m1 = Math.round(0.05 * cardH + 56 - STEP);      // 다음 — 바닥이 액티브 바닥 +56px
    const T_m2 = Math.round(0.10 * cardH + 112 - 2 * STEP); // 두 칸 아래 — 바닥 +112px
    const T_p1 = Math.round(STEP - 140 - 0.05 * cardH);     // 이전 — 상단 140px 피크
    // 두 칸 위: 이전 카드 뒤로 완전히 숨김 (레퍼런스도 위는 1장만 피크)
    const T_p2 = Math.round(2 * STEP - 150 - 0.9 * cardH);
    return {
      // 아래 덱은 불투명(엣지 스택), 위 피크만 기존 반투명 유지
      opacity: scrollY.interpolate({ inputRange: in5, outputRange: [1, 1, 1, 0.72, 0.5], extrapolate: 'clamp' as const }),
      translateY: scrollY.interpolate({ inputRange: in5, outputRange: [T_m2, T_m1, 0, T_p1, T_p2], extrapolate: 'clamp' as const }),
      // 포커스 스케일 1.04 → 1.0: 풀와이드 카드라 1 초과분이 화면 밖으로 잘려 나가던 문제
      // (우상단 모서리 클리핑). 벌지감은 이웃을 0.96으로 낮춰 상대값으로 보존.
      scale: scrollY.interpolate({ inputRange: in7, outputRange: [0.8, 0.9, 0.96, 1.0, 0.96, 0.9, 0.8], extrapolate: 'clamp' as const }),
      scaleX: scrollY.interpolate({ inputRange: in5, outputRange: [0.94, 0.965, 1, 0.965, 0.94], extrapolate: 'clamp' as const }),
      // 아래 덱은 평평하게(바닥 엣지에 회전은 어지럽다), 위 피크만 힌지 폴드 유지
      rotateX: scrollY.interpolate({ inputRange: in5, outputRange: ['0deg', '0deg', '0deg', '10deg', '15deg'], extrapolate: 'clamp' as const }),
      // transform-origin 에뮬레이션: 액티브에 가까운 엣지가 힌지 —
      // 위 카드는 하단 엣지(+H2), 아래 카드는 상단 엣지(-H2). translate → rotate → 역translate.
      oShift: scrollY.interpolate({ inputRange: in5, outputRange: [-H2, -H2, 0, H2, H2], extrapolate: 'clamp' as const }),
      oShiftBack: scrollY.interpolate({ inputRange: in5, outputRange: [H2, H2, 0, -H2, -H2], extrapolate: 'clamp' as const }),
    };
  };

  const measureCard = (e: any) => {
    const h = Math.round(e.nativeEvent.layout.height);
    if (h > 100 && Math.abs(h - cardH) > 2) setCardH(h);
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#E9E7DE' }}>
      {/* 고정 헤더 — 캐러셀과 분리, 포커스 좌표가 흔들리지 않게 */}
      <View style={{ paddingTop: 58, paddingHorizontal: 12, zIndex: 50, backgroundColor: '#E9E7DE' }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5, color: FOREST }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 23, fontWeight: '900', color: FOREST }, df]}>러너 선택</Text>
          <View style={{ width: 40 }} />
        </Row>
        <Text style={{ fontSize: 15, color: '#49524a', textAlign: 'center', marginBottom: 10 }}>
          {live ? '러너를 지명하거나, 오픈 매칭으로 기다릴 수 있어요\n보통 몇 분 안에 응답이 와요' : '보호자님과 러너의 선호도를 종합 분석했어요'}
        </Text>
      </View>

      {/* ── 2층 컴포지터: [배경 캐러셀 레이어(ScrollView)] + [액티브 카드 오버레이(형제, 항상 위)] ──
          ScrollView 내부의 어떤 카드도 오버레이 위에 그릴 수 없다 — 네이티브 계층 자체가 분리됨 */}
      <View style={{ flex: 1, overflow: 'visible' }}>
        <Animated.ScrollView
          style={{ flex: 1, overflow: 'visible' }}
          removeClippedSubviews={false}
          contentContainerStyle={{ height: live && top ? contentH : undefined, overflow: 'visible' }}
          snapToInterval={STEP}
          disableIntervalMomentum
          decelerationRate="fast"
          onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], {
            useNativeDriver: true,
            // activeIndex = 고정 포커스 좌표에 top이 가장 가까운 카드 (렌더 순서/랭크와 무관)
            listener: (e: any) => {
              const n = scored.length || 1;
              const idx = Math.min(n - 1, Math.max(0, Math.round(e.nativeEvent.contentOffset.y / STEP)));
              if (idx !== focusRef.current) onFocusChange(idx);
            },
          })}
          scrollEventThrottle={16}
        >
          {live && top && (
            <>
              {scored.map(({ r, m }, i) => {
                const dist = Math.abs(i - safeFocus);
                const active = dist === 0;
                const ph = physicsFor(i);
                return (
                  <Animated.View
                    key={r.profileId}
                    style={[active ? null : s.cardShadowAmbient, {
                      position: 'absolute', top: FOCUS_TOP + i * STEP, left: 0, right: 0,
                      // 가까울수록 위 — 아래 덱은 '밑으로 턱'이라 가까운 카드가 먼 카드의 상반신을 가린다
                      zIndex: dist === 0 ? 1000 : dist === 1 ? 100 : dist === 2 ? 10 : 1,
                      elevation: dist === 0 ? 30 : dist === 1 ? 8 : 1,
                      // 액티브 카드: 비주얼은 오버레이가 담당 → 여기선 투명 플레이스홀더.
                      // 터치는 이 투명 카드가 받는다 (단일 터치 레이어 — 이중 처리/스크롤 제스처 충돌 방지,
                      // zIndex 1000이라 스크롤 레이어 최상단 = 터치 좌표는 오버레이 비주얼과 픽셀 일치)
                      opacity: active ? 0 : ph.opacity,
                      transform: [
                        { perspective: 1100 },
                        { translateY: ph.translateY },
                        { translateY: ph.oShift },
                        { rotateX: ph.rotateX },
                        { translateY: ph.oShiftBack },
                        { scale: ph.scale },
                        { scaleX: ph.scaleX },
                      ],
                    }]}
                  >
                    <RunnerFullCard
                      r={r} m={m} i={i} topIsPreferred={topIsPreferred}
                      nominating={nominating} onNominate={nominate}
                      focused={active} gear={gearMap[r.profileId]}
                      onLayout={i === 0 ? measureCard : undefined}
                    />
                  </Animated.View>
                );
              })}

              <View style={[s.trustNote, { position: 'absolute', top: FOCUS_TOP + cardH + (N - 1) * STEP + 14, left: 0, right: 0, zIndex: 0 }]}>
                <Text style={{ fontSize: 14, color: '#49524a' }}>지명 없이 두면 오픈 매칭으로 모든 러너에게 보여요</Text>
              </View>
            </>
          )}

          {/* 데모 매칭 섹션 은퇴 (2026-07-23) — 목업 김민준 화면이 결제 실패를 숨기는 함정이었음.
              이 화면은 이제 실예약 전용. */}
          {!live && (
            <View style={{ marginTop: 16, marginHorizontal: 12, backgroundColor: '#fff', borderRadius: 16, padding: 18, alignItems: 'center', borderWidth: 1, borderColor: '#dddace' }}>
              <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 23 }}>
                진행 중인 예약이 없어요{'\n'}예약 화면에서 결제하면 러너 선택이 열려요
              </Text>
            </View>
          )}

          {live && liveRunners.length === 0 && (
            <View style={{ marginTop: 16, marginHorizontal: 12, backgroundColor: '#fff', borderRadius: 16, padding: 18, alignItems: 'center', borderWidth: 1, borderColor: '#dddace' }}>
              <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 23 }}>
                지금 온라인인 러너가 없어요{'\n'}오픈 매칭으로 등록되어 러너들이 응답할 수 있어요
              </Text>
            </View>
          )}
        </Animated.ScrollView>

        {/* ── 액티브 카드 오버레이 — ScrollView 밖 최종 형제. 스크롤과 픽셀 단위 동기(base - scrollY),
            동일 물리 커브라 레이어 전환 순간에도 이어 붙은 듯 연속. pointerEvents none = 비주얼 전용. */}
        {live && top && scored[safeFocus] && (() => {
          const { r, m } = scored[safeFocus];
          const ph = physicsFor(safeFocus);
          const base = FOCUS_TOP + safeFocus * STEP;
          return (
            <View pointerEvents="none" style={[StyleSheet.absoluteFill, { zIndex: 99999, elevation: 50, overflow: 'visible' }]}>
              <Animated.View
                style={[s.cardShadowFocus, {
                  position: 'absolute', left: 0, right: 0, top: 0, zIndex: 99999, elevation: 50,
                  opacity: ph.opacity,
                  transform: [
                    // 콘텐츠 좌표 → 뷰포트 좌표 변환: base - scrollY
                    { translateY: scrollY.interpolate({ inputRange: [0, 1], outputRange: [base, base - 1] }) },
                    { perspective: 1100 },
                    { translateY: ph.translateY },
                    { translateY: ph.oShift },
                    { rotateX: ph.rotateX },
                    { translateY: ph.oShiftBack },
                    { scale: ph.scale },
                    { scaleX: ph.scaleX },
                  ],
                }]}
              >
                <RunnerFullCard
                  r={r} m={m} i={safeFocus} topIsPreferred={topIsPreferred}
                  nominating={nominating} onNominate={nominate} focused
                  gear={gearMap[r.profileId]}
                />
              </Animated.View>
            </View>
          );
        })()}

      </View>
    </View>
  );
}

function StripStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={{ fontSize: 12, color: '#b8c4ae' }}>{label}</Text>
      <Text style={{ fontSize: 17, fontWeight: '900', color: '#fff', marginTop: 3 }}>{value}</Text>
    </View>
  );
}

function AltStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={{ fontSize: 12, color: colors.dim }}>{label}</Text>
      <Text style={{ fontSize: 15.5, fontWeight: '900', color: FOREST, marginTop: 2 }}>{value}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#dddace' },
  aiBanner: { flexDirection: 'row', alignItems: 'center', backgroundColor: FOREST, borderRadius: 18, padding: 16, gap: 10 },
  aiChip: { borderWidth: 1, borderColor: '#3d5245', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 },
  // 스택 카드 시스템 — 풀와이드, 큰 라운드, 겹침 (모던 패스)
  topCard: {
    marginTop: 10, backgroundColor: FOREST, borderRadius: 18, padding: 16, paddingTop: 46, paddingBottom: 52,
    borderWidth: 2, borderColor: colors.volt,
  },
  stackCard: {
    borderRadius: 18, padding: 16, paddingBottom: 54,
    shadowColor: '#000', shadowOpacity: 0.07, shadowRadius: 10, shadowOffset: { width: 0, height: -4 },
  },
  // 통합 캐러셀 풀 카드 — 모든 러너가 1순위급 정보 밀도
  fullCard: {
    borderRadius: 18, padding: 16, paddingTop: 38, paddingBottom: 30,
    borderWidth: 1, borderColor: 'rgba(15,29,19,0.15)', // 모든 카드에 반투명 다크 보더 — 배경 분리
  },
  // 그림자 계층 (래퍼에 적용 — 카드 뷰의 그림자 슬롯은 포커스 라임 글로우가 사용)
  cardShadowFocus: {
    shadowColor: '#0F1D13', shadowOpacity: 0.28, shadowRadius: 8, shadowOffset: { width: 0, height: 4 },
  },
  cardShadowAmbient: {
    shadowColor: '#0F1D13', shadowOpacity: 0.08, shadowRadius: 8, shadowOffset: { width: 0, height: 4 },
  },
  // 포커스 카드 장식 — 우측 컨투어 아크 (레퍼런스의 웨이브 라인)
  contour1: { position: 'absolute', right: -100, top: -30, width: 280, height: 280, borderRadius: 140, borderWidth: 1, borderColor: 'rgba(221,240,166,0.10)' },
  contour2: { position: 'absolute', right: -70, top: 10, width: 210, height: 210, borderRadius: 105, borderWidth: 1, borderColor: 'rgba(221,240,166,0.08)' },
  contour3: { position: 'absolute', right: -130, top: -80, width: 360, height: 360, borderRadius: 180, borderWidth: 1, borderColor: 'rgba(221,240,166,0.06)' },
  fitPill: { position: 'absolute', top: 14, right: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12, zIndex: 2 },
  gearChip: { backgroundColor: '#ffffff99', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  checkBadge: {
    position: 'absolute', bottom: -3, right: -3, width: 20, height: 20, borderRadius: 10,
    backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: FOREST,
  },
  fullNominate: { borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 12 },
  stackNominate: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 17 },
  rankTab: {
    // top/left 0 + 카드와 같은 반경 18 — 태그 모서리가 카드 라운드 밖으로 삐져나오던 정렬 수정 (Sean, 2026-07-28)
    position: 'absolute', top: 0, left: 0, backgroundColor: colors.volt,
    borderTopLeftRadius: 18, borderBottomRightRadius: 18, paddingVertical: 7, paddingHorizontal: 16,
  },
  limePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  descBox: { backgroundColor: FOREST_INNER, borderRadius: 14, padding: 13, marginTop: 14 },
  barTrack: { height: 7, borderRadius: 99, backgroundColor: '#2c4034', marginTop: 6, overflow: 'hidden' },
  barFill: { height: 7, borderRadius: 99, backgroundColor: colors.volt },
  statStrip: { flexDirection: 'row', backgroundColor: FOREST_INNER, borderRadius: 14, paddingVertical: 12, marginTop: 16 },
  topNominate: { backgroundColor: colors.volt, borderRadius: 14, alignItems: 'center', paddingVertical: 14, marginTop: 16 },
  stripDiv: { width: 1, backgroundColor: '#2c4034', marginVertical: 2 },
  altCard: { backgroundColor: '#fff', borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#DCD6C4', marginBottom: 10 },
  sagePill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center' },
  tagChip: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10 },
  altDivider: { height: 1, backgroundColor: '#DCD6C4', marginVertical: 12 },
  altStatDiv: { width: 1, backgroundColor: '#DCD6C4' },
  trustNote: { alignItems: 'center', paddingTop: 22, paddingBottom: 10, paddingHorizontal: 12 },
});
