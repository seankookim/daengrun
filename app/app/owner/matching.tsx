import { router } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Pressable, StyleSheet, Text, View } from 'react-native';
import { Avatar, Monogram, Row } from '../../src/components/ui';
import { fetchCertifiedRunners, fetchRunnerProfile, LiveRunner, requestRunner } from '../../src/lib/api';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 선택 — AI 추천 banner + 1순위 dark card + alternatives, per mock.

const FOREST = '#132117';
const FOREST_INNER = '#1d3023';

// 캐러셀 카드 내부 스탯 컬럼 (배경색에 따라 텍스트 색 가변)
function MiniCol({ v, l, main, dim }: { v: string; l: string; main: string; dim: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 14.5, fontWeight: '900', color: main }}>{v}</Text>
      <Text style={{ fontSize: 9.5, color: dim, marginTop: 2 }}>{l}</Text>
    </View>
  );
}

// 스택 카드 팔레트 — 풀와이드 파스텔, 채도 살짝 ↑ (페일 그레이 배경과 분리)
const PALETTE = ['#d9f294', '#bfd8aa', '#ffc9b2', '#f2d992'];

// 러너 풀 카드 — 배경 캐러셀 레이어와 액티브 오버레이가 정확히 같은 컴포넌트를 공유
function RunnerFullCard({ r, m, i, topIsPreferred, nominating, onNominate, onLayout, focused }: {
  r: LiveRunner; m: Match; i: number; topIsPreferred: boolean;
  nominating: string | null; onNominate: (r: LiveRunner) => void;
  onLayout?: (e: any) => void; focused: boolean;
}) {
  const dark = i === 0;
  const bg = dark ? FOREST : PALETTE[(i - 1) % PALETTE.length];
  const tMain = dark ? '#fff' : FOREST;
  const tDim = dark ? '#b8c4ae' : '#5d655d';
  const barTrack = dark ? '#2c4034' : '#ffffff99';
  const barFill = dark ? colors.volt : colors.voltDeep;
  return (
    <View
      onLayout={onLayout}
      style={[
        s.fullCard,
        { backgroundColor: bg },
        focused ? s.cardShadowFocus : s.cardShadowAmbient,
        dark && { borderWidth: 2, borderColor: colors.volt },
      ]}
    >
      <View style={[s.rankTab, !dark && { backgroundColor: FOREST }]}>
        <Text style={{ fontSize: 11, fontWeight: '900', color: dark ? FOREST : '#fff' }}>
          {i === 0 ? (topIsPreferred ? '내가 고른 러너' : '1순위 추천') : `${i + 1}순위 · 적합 ${m.total}%`}
        </Text>
      </View>

      <Pressable onPress={() => router.push(`/runner-profile/${r.profileId}`)}>
        <Row style={{ gap: 12, marginTop: 4 }}>
          <Avatar url={r.avatarUrl} char={r.name[0]} bg="#5a7a3c" size={56} />
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 7 }}>
              <Text style={{ fontSize: 20, fontWeight: '900', color: tMain }}>{r.name}</Text>
              <Text style={{ fontSize: 11, fontWeight: '800', color: dark ? colors.volt : '#5a7a3c', alignSelf: 'center' }}>프로필 ›</Text>
            </Row>
            <Text style={{ fontSize: 11.5, color: tDim, marginTop: 4 }}>
              {r.tier} · {r.district || '근처'} · 러닝 {r.totalRuns}회
            </Text>
          </View>
        </Row>
      </Pressable>

      {/* match bars — 모든 카드에 */}
      <View style={{ gap: 10, marginTop: 14 }}>
        {m.reasons.map((reason) => (
          <View key={reason.label}>
            <Row style={{ justifyContent: 'space-between' }}>
              <Text style={{ fontSize: 11.5, color: tDim }}>{reason.glyph} {reason.label}</Text>
              <Text style={{ fontSize: 12, fontWeight: '900', color: tMain }}>{reason.pct}%</Text>
            </Row>
            <View style={{ height: 6, borderRadius: 99, backgroundColor: barTrack, marginTop: 5, overflow: 'hidden' }}>
              <View style={{ height: 6, borderRadius: 99, backgroundColor: barFill, width: `${reason.pct}%` }} />
            </View>
          </View>
        ))}
      </View>

      {/* stat strip — 모든 카드에 */}
      <Row style={{ marginTop: 14, borderRadius: 14, backgroundColor: dark ? FOREST_INNER : '#ffffff88', paddingVertical: 11, justifyContent: 'space-around' }}>
        <MiniCol v={r.paceLabel} l="평균 페이스" main={tMain} dim={tDim} />
        <MiniCol v={`${r.totalRuns}회`} l="완료 러닝" main={tMain} dim={tDim} />
        <MiniCol v={r.respondRate != null ? `${r.respondRate}%` : '신규'} l="응답률" main={tMain} dim={tDim} />
      </Row>

      <Pressable
        onPress={() => onNominate(r)}
        disabled={nominating !== null}
        style={[s.fullNominate, { backgroundColor: dark ? colors.volt : FOREST }, nominating === r.profileId && { opacity: 0.5 }]}
      >
        <Text style={{ fontSize: 14, fontWeight: '900', color: dark ? FOREST : '#fff' }}>
          {nominating === r.profileId ? '전송 중...' : `${r.name} 러너 지명 요청`}
        </Text>
      </Pressable>
    </View>
  );
}

// 실러너 추천 점수 — 응답률·경험·페이스 적합의 가중합.
// 데이터가 쌓이면 매칭 엔진(견종 경험·후기·거리)으로 교체. 병원 레지던트식 하이브리드 매칭의 v1.
interface Match { total: number; reasons: { glyph: string; label: string; pct: number }[] }
function matchFor(r: LiveRunner, targetPaceSec = 420): Match {
  const respond = r.respondRate ?? 88;
  const exp = Math.min(97, 62 + r.totalRuns * 5);
  const paceFit = Math.max(58, 100 - Math.round(Math.abs(r.paceSec - targetPaceSec) / 4));
  return {
    total: Math.round(respond * 0.35 + exp * 0.3 + paceFit * 0.35),
    reasons: [
      { glyph: '⚡', label: '응답 신뢰도', pct: respond },
      { glyph: '⛨', label: '러닝 경험', pct: exp },
      { glyph: '➤', label: '페이스 적합', pct: paceFit },
    ],
  };
}

export default function Matching() {
  // 목업 러너 참조 은퇴 — 이 화면은 실러너 전용 (2026-07-23)
  const live = !!draft.bookingId;
  const [liveRunners, setLiveRunners] = useState<LiveRunner[]>([]);
  const [nominating, setNominating] = useState<string | null>(null);

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
    const arr = liveRunners.map((r) => ({ r, m: matchFor(r) })).sort((a, b) => b.m.total - a.m.total);
    if (draft.preferredRunnerId) {
      const i = arr.findIndex((x) => x.r.profileId === draft.preferredRunnerId);
      if (i > 0) arr.unshift(arr.splice(i, 1)[0]);
    }
    return arr;
  }, [liveRunners]);
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
  // 실측 카드 높이 기반: STEP = cardH - OVERLAP. 추정치 STEP의 포커스 드리프트를 구조적으로 제거.
  // 스냅 y = i*STEP 에서 카드 i의 top 이 항상 FOCUS_TOP(헤더 하단 고정 좌표)에 온다.
  const [cardH, setCardH] = useState(470);      // onLayout 실측으로 갱신
  const OVERLAP = 32;                            // 이웃 카드의 의도된 겹침 폭 (24–40px)
  const STEP = cardH - OVERLAP;
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

  // 물리 커브 — 두 레이어(배경/오버레이)가 완전히 동일한 scrollY 함수를 공유해 픽셀 단위로 일치
  const physicsFor = (i: number) => {
    const focus = i * STEP;
    const inputRange = [focus - 2 * STEP, focus - STEP, focus, focus + STEP, focus + 2 * STEP];
    return {
      opacity: scrollY.interpolate({ inputRange, outputRange: [0.42, 0.78, 1, 0.78, 0.42], extrapolate: 'clamp' as const }),
      translateY: scrollY.interpolate({ inputRange, outputRange: [-26, -16, 0, 16, 26], extrapolate: 'clamp' as const }),
      scale: scrollY.interpolate({ inputRange, outputRange: [0.82, 0.9, 1.03, 0.9, 0.82], extrapolate: 'clamp' as const }),
      rotateX: scrollY.interpolate({ inputRange, outputRange: ['-11deg', '-7deg', '0deg', '7deg', '11deg'], extrapolate: 'clamp' as const }),
    };
  };

  const measureCard = (e: any) => {
    const h = Math.round(e.nativeEvent.layout.height);
    if (h > 100 && Math.abs(h - cardH) > 2) setCardH(h);
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#E9E7DE' }}>
      {/* 고정 헤더 — 캐러셀과 분리, 포커스 좌표가 흔들리지 않게 */}
      <View style={{ paddingTop: 58, paddingHorizontal: 20 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18, color: FOREST }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>러너 선택</Text>
          <View style={{ width: 40 }} />
        </Row>
        <Text style={{ fontSize: 13, color: '#5d655d', textAlign: 'center', marginBottom: 10 }}>
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
                    style={{
                      position: 'absolute', top: FOCUS_TOP + i * STEP, left: 0, right: 0,
                      zIndex: dist === 0 ? 1000 : dist === 1 ? 100 : dist === 2 ? 10 : 1,
                      elevation: dist === 0 ? 30 : dist === 1 ? 8 : 1,
                      // 액티브 카드: 비주얼은 오버레이가 담당 → 여기선 투명 플레이스홀더.
                      // 터치는 이 투명 카드가 받는다 (단일 터치 레이어 — 이중 처리/스크롤 제스처 충돌 방지,
                      // zIndex 1000이라 스크롤 레이어 최상단 = 터치 좌표는 오버레이 비주얼과 픽셀 일치)
                      opacity: active ? 0 : ph.opacity,
                      transform: [
                        { perspective: 1400 },
                        { translateY: ph.translateY },
                        { scale: ph.scale },
                        { rotateX: ph.rotateX },
                      ],
                    }}
                  >
                    <RunnerFullCard
                      r={r} m={m} i={i} topIsPreferred={topIsPreferred}
                      nominating={nominating} onNominate={nominate}
                      focused={active}
                      onLayout={i === 0 ? measureCard : undefined}
                    />
                  </Animated.View>
                );
              })}

              <View style={[s.trustNote, { position: 'absolute', top: FOCUS_TOP + cardH + (N - 1) * STEP + 14, left: 0, right: 0, zIndex: 0 }]}>
                <Text style={{ fontSize: 12, color: '#5d655d' }}>지명 없이 두면 오픈 매칭으로 모든 러너에게 보여요</Text>
              </View>
            </>
          )}

          {/* 데모 매칭 섹션 은퇴 (2026-07-23) — 목업 김민준 화면이 결제 실패를 숨기는 함정이었음.
              이 화면은 이제 실예약 전용. */}
          {!live && (
            <View style={{ marginTop: 16, marginHorizontal: 20, backgroundColor: '#fff', borderRadius: 16, padding: 24, alignItems: 'center', borderWidth: 1, borderColor: '#dddace' }}>
              <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 20 }}>
                진행 중인 예약이 없어요{'\n'}예약 화면에서 결제하면 러너 선택이 열려요
              </Text>
            </View>
          )}

          {live && liveRunners.length === 0 && (
            <View style={{ marginTop: 16, marginHorizontal: 20, backgroundColor: '#fff', borderRadius: 16, padding: 24, alignItems: 'center', borderWidth: 1, borderColor: '#dddace' }}>
              <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 20 }}>
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
                style={{
                  position: 'absolute', left: 0, right: 0, top: 0, zIndex: 99999, elevation: 50,
                  opacity: ph.opacity,
                  transform: [
                    // 콘텐츠 좌표 → 뷰포트 좌표 변환: base - scrollY
                    { translateY: scrollY.interpolate({ inputRange: [0, 1], outputRange: [base, base - 1] }) },
                    { perspective: 1400 },
                    { translateY: ph.translateY },
                    { scale: ph.scale },
                    { rotateX: ph.rotateX },
                  ],
                }}
              >
                <RunnerFullCard
                  r={r} m={m} i={safeFocus} topIsPreferred={topIsPreferred}
                  nominating={nominating} onNominate={nominate} focused
                />
              </Animated.View>
            </View>
          );
        })()}

        {/* 임시 디버그 — 액티브 인덱스 검증용. 스태킹 확인 후 제거 */}
        {live && top && (
          <View pointerEvents="none" style={{ position: 'absolute', bottom: 12, alignSelf: 'center', zIndex: 100000, backgroundColor: '#132117cc', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 12 }}>
            <Text style={{ color: '#d9f294', fontSize: 11, fontWeight: '800' }}>ACTIVE {safeFocus} — {scored[safeFocus]?.r.name}</Text>
          </View>
        )}
      </View>
    </View>
  );
}

function StripStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={{ fontSize: 10.5, color: '#b8c4ae' }}>{label}</Text>
      <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff', marginTop: 3 }}>{value}</Text>
    </View>
  );
}

function AltStat({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={{ fontSize: 10.5, color: colors.dim }}>{label}</Text>
      <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST, marginTop: 2 }}>{value}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#dddace' },
  aiBanner: { flexDirection: 'row', alignItems: 'center', backgroundColor: FOREST, borderRadius: 18, padding: 16, gap: 10 },
  aiChip: { borderWidth: 1, borderColor: '#3d5245', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 },
  // 스택 카드 시스템 — 풀와이드, 큰 라운드, 겹침 (모던 패스)
  topCard: {
    marginTop: 10, backgroundColor: FOREST, borderRadius: 32, padding: 22, paddingTop: 46, paddingBottom: 52,
    borderWidth: 2, borderColor: colors.volt,
  },
  stackCard: {
    borderRadius: 32, padding: 22, paddingBottom: 54,
    shadowColor: '#000', shadowOpacity: 0.07, shadowRadius: 10, shadowOffset: { width: 0, height: -4 },
  },
  // 통합 캐러셀 풀 카드 — 모든 러너가 1순위급 정보 밀도
  fullCard: {
    borderRadius: 32, padding: 22, paddingTop: 44, paddingBottom: 60,
    borderWidth: 1, borderColor: 'rgba(19,33,23,0.15)', // 모든 카드에 반투명 다크 보더 — 배경 분리
  },
  // 그림자 계층: 포커스 카드는 크고 넓게(뷰어에 가장 가깝다는 신호), 나머지는 은은하게
  cardShadowFocus: {
    shadowColor: '#132117', shadowOpacity: 0.3, shadowRadius: 26, shadowOffset: { width: 0, height: 14 },
  },
  cardShadowAmbient: {
    shadowColor: '#132117', shadowOpacity: 0.1, shadowRadius: 10, shadowOffset: { width: 0, height: 5 },
  },
  fullNominate: { borderRadius: 16, alignItems: 'center', paddingVertical: 14, marginTop: 14 },
  stackNominate: { backgroundColor: FOREST, borderRadius: 99, paddingVertical: 11, paddingHorizontal: 17 },
  rankTab: {
    position: 'absolute', top: -1, left: -1, backgroundColor: colors.volt,
    borderTopLeftRadius: 30, borderBottomRightRadius: 18, paddingVertical: 7, paddingHorizontal: 16,
  },
  limePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  descBox: { backgroundColor: FOREST_INNER, borderRadius: 14, padding: 13, marginTop: 14 },
  barTrack: { height: 7, borderRadius: 99, backgroundColor: '#2c4034', marginTop: 6, overflow: 'hidden' },
  barFill: { height: 7, borderRadius: 99, backgroundColor: colors.volt },
  statStrip: { flexDirection: 'row', backgroundColor: FOREST_INNER, borderRadius: 14, paddingVertical: 12, marginTop: 16 },
  topNominate: { backgroundColor: colors.volt, borderRadius: 14, alignItems: 'center', paddingVertical: 14, marginTop: 16 },
  stripDiv: { width: 1, backgroundColor: '#2c4034', marginVertical: 2 },
  altCard: { backgroundColor: '#fff', borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#eceadf', marginBottom: 10 },
  sagePill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center' },
  tagChip: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10 },
  altDivider: { height: 1, backgroundColor: '#eceadf', marginVertical: 12 },
  altStatDiv: { width: 1, backgroundColor: '#eceadf' },
  trustNote: { alignItems: 'center', paddingTop: 22, paddingBottom: 10, paddingHorizontal: 20 },
});
