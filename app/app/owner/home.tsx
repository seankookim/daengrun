import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Modal, PanResponder, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Ring } from '../../src/components/ring';
import { RunCard } from '../../src/components/runcard';
import { Avatar, Monogram } from '../../src/components/ui';
import { fetchCertifiedRunners, fetchFitness, fetchMyBookings, Fitness, LiveRunner } from '../../src/lib/api';
import { Booking, demoImminent, dog, draft, myCards, nextBooking, ownerGearLadder, runners } from '../../src/store';
import { colors, surfaces } from '../../src/theme';
import { useTheme } from '../../src/theme-context';

// Owner home — themed (dark/light toggle in header) with a sticky collapsing hero:
// on load the ring is big and centered; scrolling shrinks the hero card into a
// compact pinned rectangle (ring right, goal data left) that stays at the top.

const { width: SCREEN_W } = Dimensions.get('window');
const CARD_W = SCREEN_W - 44;
const RING_BIG = 216;
const PAD_TOP = 56;
const HEADER_H = 62;
const HERO_BIG = 296;
const HERO_SMALL = 148;
const SCROLL_RANGE = 150;

export default function OwnerHome() {
  const { mode, toggle, p } = useTheme();
  // 링 실데이터 — 완료 러닝 집계 (로드 전엔 0, 가짜 숫자 없음)
  const [fit, setFit] = useState<Fitness | null>(null);
  const weekKm = fit?.weekKm ?? 0;
  const goalKm = fit?.goalKm ?? dog.weeklyGoalKm;
  const fitnessAge = fit?.fitnessAge ?? null;
  const pct = goalKm > 0 ? weekKm / goalKm : 0;
  const goalHit = pct >= 1;
  const latestCard = myCards.find((c) => c.run);
  const scrollY = useRef(new Animated.Value(0)).current;

  // 실예약 next booking — 위젯이 진짜 다음 일정을 보여준다 (없으면 목업)
  const [liveNext, setLiveNext] = useState<Booking | null>(null);
  useFocusEffect(useCallback(() => {
    fetchMyBookings()
      .then((bs) => setLiveNext(bs.find((b) => ['pending', 'confirmed', 'handoff', 'active'].includes(b.status)) ?? null))
      .catch((e) => console.warn('[home] bookings:', e?.message ?? e));
    fetchFitness().then(setFit).catch((e) => console.warn('[home] fitness:', e?.message ?? e));
    fetchCertifiedRunners().then(setLocalRunners).catch((e) => console.warn('[home] runners:', e?.message ?? e));
  }, []));

  // 우리 동네 러너 — 온라인 러너 셸프 (탐색형 매칭의 시작점)
  const [localRunners, setLocalRunners] = useState<LiveRunner[]>([]);

  // reward pulse — dopamine beacon for unclaimed rewards
  const [ladderOpen, setLadderOpen] = useState(false);
  const claimable = ownerGearLadder.find((g) => g.claimable);
  const nextLocked = ownerGearLadder.find((g) => !g.got && !g.claimable);
  const pulse = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!claimable) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 1, duration: 900, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0, duration: 900, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [claimable, pulse]);
  const pulseScale = pulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.12] });
  const pulseOpacity = pulse.interpolate({ inputRange: [0, 1], outputRange: [0.35, 0.9] });

  // height animation → JS driver everywhere
  const t = scrollY.interpolate({ inputRange: [0, SCROLL_RANGE], outputRange: [0, 1], extrapolate: 'clamp' });
  const heroH = t.interpolate({ inputRange: [0, 1], outputRange: [HERO_BIG, HERO_SMALL] });
  const headerH = t.interpolate({ inputRange: [0, 0.6], outputRange: [HEADER_H, 0], extrapolate: 'clamp' });
  const headerOpacity = t.interpolate({ inputRange: [0, 0.45], outputRange: [1, 0], extrapolate: 'clamp' });
  const ringScale = t.interpolate({ inputRange: [0, 1], outputRange: [1, 0.5] });
  const ringX = t.interpolate({ inputRange: [0, 1], outputRange: [0, CARD_W / 2 - RING_BIG * 0.25 - 30] });
  const ringY = t.interpolate({ inputRange: [0, 1], outputRange: [0, -58] });
  const infoOpacity = t.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0, 0, 1] });
  const infoX = t.interpolate({ inputRange: [0, 1], outputRange: [-20, 0] });
  const bigMsgOpacity = t.interpolate({ inputRange: [0, 0.35], outputRange: [1, 0], extrapolate: 'clamp' });

  // hero uses the OPPOSITE theme's surfaces — contrast is the point
  const hp = surfaces[mode === 'dark' ? 'light' : 'dark'];
  const heroAccent = mode === 'dark' ? colors.voltDeep : colors.volt;

  return (
    <View style={{ flex: 1, backgroundColor: p.bg }}>
      <StatusBar style={mode === 'dark' ? 'light' : 'dark'} />

      {/* ---------- pinned overlay: greeting + collapsing hero ---------- */}
      <View style={[s.overlay, { backgroundColor: p.bg }]}>
        <Animated.View style={{ height: headerH, opacity: headerOpacity, overflow: 'hidden' }}>
          <View style={s.headerRow}>
            <Monogram char={dog.name[0]} bg={colors.volt} size={46} />
            <View style={{ flex: 1, marginLeft: 12 }}>
              <Text style={{ fontSize: 17, fontWeight: '800', color: p.textStrong }}>
                안녕하세요, {dog.name} 보호자님
              </Text>
              <Text style={{ fontSize: 12, color: p.dim, marginTop: 2 }}>
                {dog.name}와 함께 건강한 하루 보내세요!
              </Text>
            </View>
            {/* theme toggle + notifications */}
            <Pressable onPress={toggle} style={[s.themeBtn, { borderColor: p.line }]}>
              <Text style={{ fontSize: 16, color: mode === 'dark' ? colors.volt : colors.ink }}>
                {mode === 'dark' ? '☀' : '☾'}
              </Text>
            </Pressable>
            <Pressable onPress={() => router.push('/alerts')} style={[s.themeBtn, { borderColor: p.line, marginLeft: 8 }]}>
              <View style={s.bellDot} />
              <Text style={{ fontSize: 15, color: p.dim }}>◔</Text>
            </Pressable>
          </View>
        </Animated.View>

        <Pressable onPress={() => router.push('/owner/fitness')}>
          <Animated.View style={[s.hero, { height: heroH, backgroundColor: hp.card, borderColor: hp.line }]}>
            <View style={[s.weekChip, { backgroundColor: hp.chip }]}>
              <Text style={{ fontSize: 11, fontWeight: '700', color: hp.textSoft }}>이번 주 ▾</Text>
            </View>

            {/* compact info block (left side, fades in) */}
            <Animated.View style={[s.info, { opacity: infoOpacity, transform: [{ translateX: infoX }] }]}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: hp.textSoft }}>{dog.name}의 주간 목표</Text>
              <Text style={{ marginTop: 2 }}>
                <Text style={{ fontSize: 32, fontWeight: '900', color: colors.tang }}>
                  {weekKm}
                </Text>
                <Text style={{ fontSize: 13, color: hp.dim }}> / {goalKm} km</Text>
              </Text>
              <Text style={{ fontSize: 11, color: hp.textSoft, marginTop: 3 }}>
                {fitnessAge != null ? `체력 나이 ${fitnessAge}살 · 실제보다 젊어요` : '체력 나이 측정 준비 중'}
              </Text>
              <View style={[s.miniBar, { backgroundColor: hp.track }]}>
                <View style={[s.miniBarFill, { width: `${Math.min(pct, 1) * 100}%` }]} />
              </View>
              <Text style={{ fontSize: 10, fontWeight: '800', color: heroAccent, marginTop: 4 }}>
                {Math.round(pct * 100)}% 달성
              </Text>
            </Animated.View>

            {/* the ring */}
            <Animated.View
              style={{
                alignSelf: 'center',
                marginTop: 6,
                transform: [{ translateX: ringX }, { translateY: ringY }, { scale: ringScale }],
              }}
            >
              <Ring pct={pct} size={RING_BIG} trackColor={hp.track}>
                <View style={{ alignItems: 'center' }}>
                  <Text style={{ fontSize: 13, color: hp.dim }}>이번 주</Text>
                  <Text style={{ fontSize: 46, fontWeight: '900', color: colors.tang, lineHeight: 50 }}>
                    {weekKm}
                    <Text style={{ fontSize: 16, color: hp.dim }}> km</Text>
                  </Text>
                  <Text style={{ fontSize: 13, color: heroAccent, marginTop: 2 }}>
                    / {goalKm}km
                  </Text>
                  {/* 체력 나이 — our concept, front and center */}
                  <View style={[s.goalChip, { backgroundColor: hp.chip, flexDirection: 'row', gap: 4, alignItems: 'center' }]}>
                    <Text style={{ fontSize: 10, fontWeight: '800', color: hp.textSoft }}>체력 나이</Text>
                    <Text style={{ fontSize: 12, fontWeight: '900', color: heroAccent }}>
                      {fitnessAge != null ? `${fitnessAge}살` : '측정 전'}
                    </Text>
                    {fitnessAge != null && (
                      <Text style={{ fontSize: 9, fontWeight: '800', color: colors.tang }}>▼{Math.max(dog.age - fitnessAge, 0).toFixed(1)}</Text>
                    )}
                  </View>
                </View>
              </Ring>
            </Animated.View>

            {/* big-state goal message */}
            <Animated.Text style={[s.bigMsg, { opacity: bigMsgOpacity, color: hp.textSoft }]}>
              {goalHit
                ? `이번 주 목표 달성! ${dog.name} 최고예요`
                : weekKm > 0
                  ? `목표까지 ${Math.max(Math.round((goalKm - weekKm) * 10) / 10, 0)}km — 좋은 페이스예요`
                  : '이번 주 첫 러닝을 예약해보세요'}
            </Animated.Text>
          </Animated.View>
        </Pressable>
      </View>

      {/* ---------- scroll content (starts below expanded hero) ---------- */}
      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{
          paddingHorizontal: 22,
          paddingTop: PAD_TOP + HEADER_H + HERO_BIG + 14,
          paddingBottom: 30,
        }}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: false })}
        scrollEventThrottle={16}
      >
        {/* ---------- stat chips ---------- */}
        <View style={{ flexDirection: 'row', gap: 8 }}>
          <StatChip top={`연속 ${fit?.streakDays ?? 0}일`} bottom="연속 기록" accent={colors.tang} />
          <StatChip top={`${fit?.weekRuns ?? 0}회 완료`} bottom="이번 주" accent={mode === 'dark' ? colors.volt : colors.voltDeep} />
          <StatChip
            top={fit?.avgPaceSec ? `평균 ${Math.floor(fit.avgPaceSec / 60)}'${String(fit.avgPaceSec % 60).padStart(2, '0')}"` : '페이스 —'}
            bottom="평균 페이스"
            accent="#9fc3e8"
          />
        </View>

        {/* ---------- slide-to-book ---------- */}
        <SlideToBook onComplete={() => router.push('/owner/request')} />

        {/* ---------- reward beacon (dopamine: unclaimed collab gear) ---------- */}
        {claimable && (
          <Pressable onPress={() => setLadderOpen(true)} style={[s.rewardCard, { backgroundColor: mode === 'dark' ? '#1e2c22' : '#fff' }]}>
            {/* pulsing halo */}
            <View style={s.giftWrap}>
              <Animated.View style={[s.giftHalo, { opacity: pulseOpacity, transform: [{ scale: pulseScale }] }]} />
              <View style={s.giftBox}><Text style={{ fontSize: 16, color: colors.ink }}>▣</Text></View>
              <View style={s.giftBadge}><Text style={{ fontSize: 8, fontWeight: '900', color: '#fff' }}>1</Text></View>
            </View>
            <View style={{ flex: 1, marginLeft: 13 }}>
              <Text style={{ fontSize: 11, fontWeight: '900', color: colors.tang, letterSpacing: 0.5 }}>수령 대기 리워드</Text>
              <Text style={{ fontSize: 14.5, fontWeight: '900', color: p.textStrong, marginTop: 2 }} numberOfLines={1}>
                {claimable.item}
              </Text>
              <Text style={{ fontSize: 10.5, color: p.dim, marginTop: 2 }}>
                {claimable.at}km 달성! · 다음: {nextLocked ? `${nextLocked.item.split(' ').pop()}까지 ${(nextLocked.at - 86.2).toFixed(0)}km` : '완료'}
              </Text>
            </View>
            <Pressable
              onPress={(e) => { e.stopPropagation(); Alert.alert('수령 신청', '배송지로 콜라보 굿즈를 보내드려요 (목업)'); }}
              style={s.claimBtn}
            >
              <Text style={{ fontSize: 12, fontWeight: '900', color: colors.ink }}>수령하기</Text>
            </Pressable>
          </Pressable>
        )}

        {/* ---------- upcoming schedule widget (docs/calendar.md: 4-state component; mock shows 예정 state) ---------- */}
        {/* whole card taps through to 내 일정 — buttons stop propagation */}
        <Pressable onPress={() => router.push('/owner/schedule')} style={[s.scheduleCard, { backgroundColor: p.card }]}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <View style={s.liveDotSm} />
              <Text style={{ fontSize: 12.5, fontWeight: '900', color: p.textStrong }}>다가오는 일정</Text>
            </View>
            <View style={s.allScheduleChip}>
              <Text style={{ fontSize: 11.5, fontWeight: '900', color: colors.ink }}>전체 일정 ›</Text>
            </View>
          </View>
          {liveNext ? (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 12 }}>
              <Monogram char={liveNext.dogName[0]} bg="#FF6347" size={46} />
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 17, fontWeight: '900', color: p.textStrong }}>
                  {liveNext.dateLabel.split(' ')[0]} {liveNext.timeLabel} · {liveNext.dogName}
                </Text>
                <Text style={{ fontSize: 11.5, color: p.dim, marginTop: 3 }}>
                  {liveNext.routeName} · {liveNext.status === 'pending' ? '러너 응답 대기' : liveNext.status === 'active' ? '러닝 진행 중' : liveNext.status === 'handoff' ? '인계 완료 — 곧 시작돼요' : '러너 확정 ✓'}
                </Text>
              </View>
              <View style={[s.countdownPill, { backgroundColor: liveNext.status === 'pending' ? '#fbf0d4' : '#fde8e3' }]}>
                <Text style={{ fontSize: 10.5, fontWeight: '900', color: liveNext.status === 'pending' ? '#a97c12' : '#d84a2f' }}>
                  {liveNext.status === 'pending' ? '매칭 중' : liveNext.status === 'active' ? '● LIVE' : liveNext.status === 'handoff' ? '시작 대기' : '확정됨'}
                </Text>
              </View>
            </View>
          ) : (
            <View style={{ marginTop: 12, alignItems: 'center', paddingVertical: 6 }}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: p.textStrong }}>예정된 러닝이 없어요</Text>
              <Text style={{ fontSize: 11.5, color: p.dim, marginTop: 4 }}>아래 슬라이더로 첫 러닝을 예약해보세요</Text>
            </View>
          )}
          {/* 30분 전부터/러너 확정 시: 확인·시작 액션이 위젯에 올라온다 */}
          {liveNext?.status === 'active' ? (
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
              <Pressable
                style={s.meetBtn}
                onPress={(e) => { e.stopPropagation(); if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); }}
              >
                <Text style={{ fontSize: 12.5, fontWeight: '900', color: colors.ink }}>실시간 보기 ›</Text>
              </Pressable>
            </View>
          ) : liveNext?.status === 'handoff' ? (
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
              <Pressable
                style={[s.widgetBtn, { borderColor: p.line, flex: 1 }]}
                onPress={(e) => {
                  e.stopPropagation();
                  if (liveNext) draft.bookingId = liveNext.id;
                  router.push('/owner/meetup'); // 시작되면 미트업이 라이브로 자동 전환
                }}
              >
                <Text style={{ fontSize: 11.5, fontWeight: '700', color: p.textSoft }}>인계 완료 · 러닝 시작 대기 중 ›</Text>
              </Pressable>
            </View>
          ) : liveNext?.status === 'confirmed' ? (
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
              <Pressable
                style={s.meetBtn}
                onPress={(e) => {
                  e.stopPropagation();
                  if (liveNext) draft.bookingId = liveNext.id; // 재시작 후에도 실예약으로 인계 재개
                  router.push('/owner/meetup');
                }}
              >
                <Text style={{ fontSize: 12.5, fontWeight: '900', color: colors.ink }}>러너 만나기 · 인계 확인 ›</Text>
              </Pressable>
              <Pressable
                style={[s.widgetBtn, { borderColor: p.line, flex: 0.6 }]}
                onPress={(e) => { e.stopPropagation(); router.push('/chat'); }}
              >
                <Text style={{ fontSize: 11.5, fontWeight: '700', color: p.textSoft }}>채팅</Text>
              </Pressable>
            </View>
          ) : (
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
              <Pressable
                style={[s.widgetBtn, { borderColor: p.line }]}
                onPress={(e) => { e.stopPropagation(); router.push('/owner/schedule'); }}
              >
                <Text style={{ fontSize: 11.5, fontWeight: '700', color: p.textSoft }}>일정 변경</Text>
              </Pressable>
              <Pressable
                style={[s.widgetBtn, { borderColor: p.line }]}
                onPress={(e) => { e.stopPropagation(); router.push('/chat'); }}
              >
                <Text style={{ fontSize: 11.5, fontWeight: '700', color: p.textSoft }}>러너와 채팅</Text>
              </Pressable>
            </View>
          )}
        </Pressable>

        {/* ---------- 우리 동네 러너 (탐색형 매칭) ---------- */}
        {localRunners.length > 0 && (
          <View style={{ marginTop: 14 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 9 }}>
              <Text style={[s.sectionTitle, { color: p.textStrong }]}>우리 동네 러너</Text>
              <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7 }}>
                <Text style={{ fontSize: 8.5, fontWeight: '900', color: '#fff' }}>● {localRunners.length}명 온라인</Text>
              </View>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10 }}>
              {localRunners.map((r) => (
                <Pressable
                  key={r.profileId}
                  onPress={() => router.push(`/runner-profile/${r.profileId}`)}
                  style={{
                    width: 150, backgroundColor: p.card, borderRadius: 18, padding: 13,
                    borderWidth: 1, borderColor: p.line, alignItems: 'center',
                  }}
                >
                  <Avatar url={r.avatarUrl} char={r.name[0]} bg="#5a7a3c" size={54} />
                  <Text style={{ fontSize: 13.5, fontWeight: '900', color: p.textStrong, marginTop: 8 }} numberOfLines={1}>
                    {r.name}
                  </Text>
                  <Text style={{ fontSize: 10.5, color: p.dim, marginTop: 2 }} numberOfLines={1}>
                    {r.district || '근처'} · {r.tier}
                  </Text>
                  <Text style={{ fontSize: 10.5, color: p.dim, marginTop: 1 }}>
                    러닝 {r.totalRuns}회 · {r.paceLabel}
                  </Text>
                  <View style={{ backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 11, marginTop: 8 }}>
                    <Text style={{ fontSize: 10.5, fontWeight: '800', color: '#4a6d1f' }}>프로필 보기 ›</Text>
                  </View>
                </Pressable>
              ))}
            </ScrollView>
          </View>
        )}

        {/* ---------- safety quick card ---------- */}
        <Pressable onPress={() => router.push('/safety')} style={[s.safetyStrip, { backgroundColor: p.card }]}>
          <View style={s.safetyIcon}><Text style={{ fontSize: 13, color: '#5a7a3c' }}>✚</Text></View>
          <Text style={{ flex: 1, fontSize: 12.5, fontWeight: '700', color: p.textStrong }}>
            안심 센터 <Text style={{ fontWeight: '400', color: p.dim }}>· SOS · 실시간 위치 · 보험</Text>
          </Text>
          <Text style={{ fontSize: 14, color: p.dim }}>›</Text>
        </Pressable>

        {/* ---------- latest card ---------- */}
        <View style={s.sectionRow}>
          <Text style={[s.sectionTitle, { color: p.textStrong }]}>최근 활동</Text>
          <Pressable onPress={() => router.push('/cards')}>
            <Text style={{ fontSize: 12, color: p.dim, fontWeight: '700' }}>모두 보기 ›</Text>
          </Pressable>
        </View>
        {latestCard && (
          <Pressable onPress={() => router.push('/cards')} style={{ alignItems: 'center' }}>
            <RunCard card={latestCard} width={CARD_W} />
          </Pressable>
        )}

        {/* ---------- runners ---------- */}
        <View style={s.sectionRow}>
          <Text style={[s.sectionTitle, { color: p.textStrong }]}>내 주변 인기 러너</Text>
          <Text style={{ fontSize: 12, color: p.dim }}>전체보기</Text>
        </View>
        {runners.slice(0, 2).map((r) => (
          <Pressable key={r.id} onPress={() => router.push('/owner/matching')}>
            <View style={[s.runnerCard, { backgroundColor: p.card, borderColor: p.line }]}>
              <Monogram char={r.char} bg={r.color} />
              <View style={{ flex: 1, marginLeft: 12 }}>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                  <Text style={{ fontSize: 15, fontWeight: '700', color: p.textStrong }}>{r.name}</Text>
                  {r.badges.map((b) => (
                    <View key={b} style={[s.runnerBadge, { borderColor: p.line }]}>
                      <Text style={{ fontSize: 9, fontWeight: '800', color: b === '훈련사' ? colors.tang : mode === 'dark' ? colors.volt : colors.voltDeep }}>
                        {b}
                      </Text>
                    </View>
                  ))}
                </View>
                <Text style={{ fontSize: 12, color: p.dim, marginTop: 3 }}>
                  ★ {r.rating} · 러닝 {r.runs}회 · 성수동 {r.distanceKm}km
                </Text>
              </View>
              <Text style={{ color: p.dim, fontSize: 18 }}>›</Text>
            </View>
          </Pressable>
        ))}
      </Animated.ScrollView>
      <BottomNav dark={mode === 'dark'} />

      {/* ---------- milestone ladder sheet ---------- */}
      <Modal visible={ladderOpen} transparent animationType="slide" onRequestClose={() => setLadderOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: '#00000055' }} onPress={() => setLadderOpen(false)} />
        <View style={s.ladderSheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 18, fontWeight: '900', color: '#132117' }}>마일스톤 리워드</Text>
          <Text style={{ fontSize: 12, color: colors.dim, marginTop: 4, marginBottom: 12 }}>
            {dog.name}의 누적 86.2km — 달릴수록 콜라보 굿즈가 열려요
          </Text>
          {ownerGearLadder.map((g, i) => (
            <View key={g.at}>
              {i > 0 && <View style={{ height: 1, backgroundColor: '#f0eee3' }} />}
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 }}>
                <View style={{
                  width: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center',
                  backgroundColor: g.got ? '#6aa53c' : g.claimable ? colors.volt : '#eceadf',
                }}>
                  {g.got && <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>✓</Text>}
                  {g.claimable && <Text style={{ fontSize: 9, fontWeight: '900', color: '#132117' }}>!</Text>}
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 13.5, fontWeight: '800', color: g.got || g.claimable ? '#132117' : '#9a9a90' }}>{g.item}</Text>
                  <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 1 }}>누적 {g.at}km</Text>
                </View>
                {g.claimable ? (
                  <Pressable
                    onPress={() => Alert.alert('수령 신청', '배송지로 콜라보 굿즈를 보내드려요 (목업)')}
                    style={{ backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 }}
                  >
                    <Text style={{ fontSize: 11, fontWeight: '900', color: '#132117' }}>수령하기</Text>
                  </Pressable>
                ) : g.got ? (
                  <Text style={{ fontSize: 10.5, fontWeight: '700', color: '#5a7a3c' }}>수령 완료</Text>
                ) : (
                  <Text style={{ fontSize: 10.5, color: colors.dim }}>{(g.at - 86.2).toFixed(0)}km 남음</Text>
                )}
              </View>
            </View>
          ))}
        </View>
      </Modal>
    </View>
  );

  function StatChip({ top, bottom, accent }: { top: string; bottom: string; accent: string }) {
    return (
      <View style={[s.statChip, { backgroundColor: p.card, borderColor: p.line }]}>
        <View style={[s.statDot, { backgroundColor: accent, shadowColor: accent }]} />
        <Text style={{ fontSize: 13, fontWeight: '800', color: p.textStrong, marginTop: 6 }}>{top}</Text>
        <Text style={{ fontSize: 10, color: p.dim, marginTop: 2 }}>{bottom}</Text>
      </View>
    );
  }
}

// Slide-to-book — commitment gesture beats a tap; also just more fun.
function SlideToBook({ onComplete }: { onComplete: () => void }) {
  const KNOB = 56;
  const MAX = CARD_W - KNOB - 12;
  const x = useRef(new Animated.Value(0)).current;
  const pan = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 4,
      onPanResponderMove: (_e, g) => x.setValue(Math.min(Math.max(g.dx, 0), MAX)),
      onPanResponderRelease: (_e, g) => {
        if (g.dx > MAX * 0.7) {
          Animated.timing(x, { toValue: MAX, duration: 120, useNativeDriver: false }).start(() => {
            onComplete();
            setTimeout(() => x.setValue(0), 500);
          });
        } else {
          Animated.spring(x, { toValue: 0, useNativeDriver: false }).start();
        }
      },
    }),
  ).current;
  const labelOpacity = x.interpolate({ inputRange: [0, MAX * 0.6], outputRange: [1, 0], extrapolate: 'clamp' });

  return (
    <View style={s.slideTrack}>
      <Animated.Text style={[s.slideLabel, { opacity: labelOpacity }]}>밀어서 러닝 요청 ›››</Animated.Text>
      <Animated.View {...pan.panHandlers} style={[s.slideKnob, { transform: [{ translateX: x }] }]}>
        <Text style={{ fontSize: 20, fontWeight: '900', color: colors.volt }}>❯</Text>
      </Animated.View>
    </View>
  );
}

const s = StyleSheet.create({
  overlay: {
    position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20,
    paddingTop: PAD_TOP, paddingHorizontal: 22, paddingBottom: 10,
  },
  headerRow: { flexDirection: 'row', alignItems: 'center', height: HEADER_H - 12, marginBottom: 12 },
  themeBtn: {
    width: 40, height: 40, borderRadius: 20, borderWidth: 1,
    alignItems: 'center', justifyContent: 'center',
  },
  bellDot: {
    position: 'absolute', top: 8, right: 9, width: 7, height: 7, borderRadius: 4,
    backgroundColor: colors.volt, zIndex: 2,
    shadowColor: colors.volt, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },
  hero: {
    borderRadius: 28, padding: 18, overflow: 'hidden', borderWidth: 1,
    shadowColor: colors.volt, shadowOpacity: 0.1, shadowRadius: 24, shadowOffset: { width: 0, height: 6 },
  },
  weekChip: {
    position: 'absolute', top: 14, left: 16, zIndex: 4,
    borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12,
  },
  info: { position: 'absolute', left: 18, top: 40, width: CARD_W * 0.5, zIndex: 3 },
  miniBar: { height: 4, borderRadius: 99, marginTop: 6, overflow: 'hidden' },
  miniBarFill: { height: 4, borderRadius: 99, backgroundColor: colors.volt },
  goalChip: { marginTop: 8, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  bigMsg: { textAlign: 'center', marginTop: 8, fontSize: 13, fontWeight: '700' },
  statChip: { flex: 1, borderRadius: 18, borderWidth: 1, paddingVertical: 12, paddingHorizontal: 12 },
  statDot: { width: 8, height: 8, borderRadius: 4, shadowOpacity: 0.9, shadowRadius: 5, shadowOffset: { width: 0, height: 0 } },
  rewardCard: {
    flexDirection: 'row', alignItems: 'center', borderRadius: 20, padding: 15, marginTop: 12,
    borderWidth: 1.6, borderColor: colors.tang + '66',
    shadowColor: colors.tang, shadowOpacity: 0.3, shadowRadius: 14, shadowOffset: { width: 0, height: 3 },
    elevation: 4,
  },
  giftWrap: { width: 46, height: 46, alignItems: 'center', justifyContent: 'center' },
  giftHalo: {
    position: 'absolute', width: 46, height: 46, borderRadius: 23,
    backgroundColor: colors.volt,
  },
  giftBox: { width: 38, height: 38, borderRadius: 13, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
  giftBadge: {
    position: 'absolute', top: 0, right: 0, width: 15, height: 15, borderRadius: 8,
    backgroundColor: colors.tang, alignItems: 'center', justifyContent: 'center', zIndex: 2,
  },
  claimBtn: { backgroundColor: colors.volt, borderRadius: 12, paddingVertical: 10, paddingHorizontal: 13 },
  ladderSheet: { backgroundColor: '#F6F2E9', borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 22, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#d8d5c8', marginBottom: 14 },
  slideTrack: {
    marginTop: 14, height: 68, borderRadius: 24, backgroundColor: colors.volt, justifyContent: 'center',
    shadowColor: colors.volt, shadowOpacity: 0.5, shadowRadius: 20, shadowOffset: { width: 0, height: 6 },
    elevation: 8,
  },
  slideLabel: { alignSelf: 'center', fontSize: 17, fontWeight: '900', color: colors.ink, letterSpacing: 0.5 },
  slideKnob: {
    position: 'absolute', left: 6, width: 56, height: 56, borderRadius: 20,
    backgroundColor: '#132117', alignItems: 'center', justifyContent: 'center',
    shadowColor: '#000', shadowOpacity: 0.25, shadowRadius: 6, shadowOffset: { width: 2, height: 2 },
  },
  scheduleCard: {
    borderRadius: 22, padding: 17, marginTop: 12,
    borderWidth: 1.4, borderColor: '#b9f23a55', // lime accent — the widget earns its emphasis
    shadowColor: colors.volt, shadowOpacity: 0.2, shadowRadius: 12, shadowOffset: { width: 0, height: 3 },
    elevation: 3,
  },
  liveDotSm: {
    width: 7, height: 7, borderRadius: 4, backgroundColor: colors.volt,
    shadowColor: colors.volt, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },
  allScheduleChip: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12 },
  meetBtn: {
    flex: 1, backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11,
    shadowColor: colors.volt, shadowOpacity: 0.4, shadowRadius: 8, shadowOffset: { width: 0, height: 2 },
  },
  countdownPill: { borderRadius: 99, paddingVertical: 6, paddingHorizontal: 10 },
  widgetBtn: { flex: 1, borderWidth: 1, borderRadius: 12, alignItems: 'center', paddingVertical: 9 },
  safetyStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 10, borderRadius: 16,
    paddingVertical: 12, paddingHorizontal: 14, marginTop: 12,
    borderWidth: 1.2, borderColor: '#ff634745', // faint coral outline
    shadowColor: colors.tang, shadowOpacity: 0.22, shadowRadius: 10, shadowOffset: { width: 0, height: 2 },
    elevation: 3,
  },
  safetyIcon: { width: 28, height: 28, borderRadius: 9, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  sectionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 26, marginBottom: 12 },
  sectionTitle: { fontSize: 17, fontWeight: '800' },
  runnerCard: { flexDirection: 'row', alignItems: 'center', borderRadius: 18, borderWidth: 1, padding: 14, marginBottom: 8 },
  runnerBadge: { borderWidth: 1, borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7 },
});
