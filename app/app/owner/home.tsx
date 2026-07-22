import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useRef } from 'react';
import { Animated, Dimensions, Pressable, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Ring } from '../../src/components/ring';
import { RunCard } from '../../src/components/runcard';
import { Monogram } from '../../src/components/ui';
import { dog, myCards, runners } from '../../src/store';
import { colors } from '../../src/theme';
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
  const pct = dog.weekKm / dog.weeklyGoalKm;
  const remaining = Math.max(dog.weeklyGoalKm - dog.weekKm, 0);
  const goalHit = pct >= 1;
  const latestCard = myCards.find((c) => c.run);
  const scrollY = useRef(new Animated.Value(0)).current;

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

        <Pressable onPress={() => router.push('/owner/dog')}>
          <Animated.View style={[s.hero, { height: heroH, backgroundColor: p.card, borderColor: p.line }]}>
            <View style={[s.weekChip, { backgroundColor: p.chip }]}>
              <Text style={{ fontSize: 11, fontWeight: '700', color: p.textSoft }}>이번 주 ▾</Text>
            </View>

            {/* compact info block (left side, fades in) */}
            <Animated.View style={[s.info, { opacity: infoOpacity, transform: [{ translateX: infoX }] }]}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: p.textSoft }}>{dog.name}의 주간 목표</Text>
              <Text style={{ marginTop: 2 }}>
                <Text style={{ fontSize: 32, fontWeight: '900', color: mode === 'dark' ? colors.volt : colors.voltDeep }}>
                  {dog.weekKm}
                </Text>
                <Text style={{ fontSize: 13, color: p.dim }}> / {dog.weeklyGoalKm} km</Text>
              </Text>
              <Text style={{ fontSize: 11, color: p.textSoft, marginTop: 3 }}>
                {goalHit ? '이번 주 목표 달성!' : `목표까지 ${remaining.toFixed(1)}km 남았어요!`}
              </Text>
              <View style={[s.miniBar, { backgroundColor: p.track }]}>
                <View style={[s.miniBarFill, { width: `${Math.min(pct, 1) * 100}%` }]} />
              </View>
              <Text style={{ fontSize: 10, fontWeight: '800', color: mode === 'dark' ? colors.volt : colors.voltDeep, marginTop: 4 }}>
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
              <Ring pct={pct} size={RING_BIG} trackColor={p.track}>
                <View style={{ alignItems: 'center' }}>
                  <Text style={{ fontSize: 13, color: p.dim }}>이번 주</Text>
                  <Text style={{ fontSize: 46, fontWeight: '900', color: p.textStrong, lineHeight: 50 }}>
                    {dog.weekKm}
                    <Text style={{ fontSize: 16, color: p.dim }}> km</Text>
                  </Text>
                  <Text style={{ fontSize: 13, color: mode === 'dark' ? colors.volt : colors.voltDeep, marginTop: 2 }}>
                    / {dog.weeklyGoalKm}km
                  </Text>
                  <View style={[s.goalChip, { backgroundColor: p.chip }]}>
                    <Text style={{ fontSize: 10, fontWeight: '800', color: p.textSoft }}>주간 목표</Text>
                  </View>
                </View>
              </Ring>
            </Animated.View>

            {/* big-state goal message */}
            <Animated.Text style={[s.bigMsg, { opacity: bigMsgOpacity, color: p.textSoft }]}>
              {goalHit ? `이번 주 목표 달성! ${dog.name} 최고예요` : `목표까지 ${remaining.toFixed(1)}km 남았어요!`}
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
          <StatChip top={`연속 ${dog.streakDays}일`} bottom="연속 기록" accent={colors.tang} />
          <StatChip top="3회 완료" bottom="이번 주" accent={mode === 'dark' ? colors.volt : colors.voltDeep} />
          <StatChip top={`평균 7'20"`} bottom="평균 페이스" accent="#9fc3e8" />
        </View>

        {/* ---------- CTA ---------- */}
        <Pressable onPress={() => router.push('/owner/request')} style={({ pressed }) => [s.cta, pressed && { transform: [{ scale: 0.98 }] }]}>
          <Text style={{ fontSize: 18, fontWeight: '900', color: colors.ink, letterSpacing: 0.5 }}>러닝 요청하기</Text>
          <Text style={{ fontSize: 18, fontWeight: '900', color: colors.ink }}>›</Text>
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
  cta: {
    marginTop: 14, backgroundColor: colors.volt, borderRadius: 22, paddingVertical: 19, paddingHorizontal: 24,
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    shadowColor: colors.volt, shadowOpacity: 0.45, shadowRadius: 18, shadowOffset: { width: 0, height: 6 },
    elevation: 8,
  },
  sectionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 26, marginBottom: 12 },
  sectionTitle: { fontSize: 17, fontWeight: '800' },
  runnerCard: { flexDirection: 'row', alignItems: 'center', borderRadius: 18, borderWidth: 1, padding: 14, marginBottom: 8 },
  runnerBadge: { borderWidth: 1, borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7 },
});
