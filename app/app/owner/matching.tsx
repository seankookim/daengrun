import { router } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { draft, fmtWon, priceForRunner, runners } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 선택 — AI 추천 banner + 1순위 dark card + alternatives, per mock.

const FOREST = '#132117';
const FOREST_INNER = '#1d3023';

export default function Matching() {
  const recommended = runners.find((r) => r.match)!;
  const others = runners.filter((r) => !r.match);

  const pick = (id: string) => {
    draft.runnerId = id;
    router.push('/owner/live'); // 실제로는 수락 대기 → live. 목업에서는 바로 이동.
  };

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>러너 선택</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 13, color: '#5d655d', textAlign: 'center', marginBottom: 16 }}>
        보호자님과 러너의 선호도를 종합 분석했어요
      </Text>

      {/* AI banner */}
      <View style={s.aiBanner}>
        <View style={{ flex: 1 }}>
          <Row style={{ gap: 6 }}>
            <Text style={{ fontSize: 13, color: colors.volt }}>✿</Text>
            <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt }}>AI 추천 · 매칭 확신도 {recommended.match!.total}%</Text>
          </Row>
          <Text style={{ fontSize: 12, color: '#b8c4ae', marginTop: 3 }}>반려견 초코와 가장 잘 맞는 러너예요</Text>
        </View>
        <View style={s.aiChip}><Text style={{ fontSize: 11, fontWeight: '700', color: '#e8efe0' }}>추천 기준 ▾</Text></View>
      </View>

      {/* 1순위 card */}
      <Pressable onPress={() => pick(recommended.id)}>
        <View style={s.topCard}>
          <View style={s.rankTab}><Text style={{ fontSize: 11, fontWeight: '900', color: FOREST }}>1순위 추천</Text></View>

          <Row style={{ gap: 12, marginTop: 18 }}>
            <Monogram char={recommended.char} bg={recommended.color} size={58} />
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 17, fontWeight: '900', color: '#fff' }}>{recommended.name} 러너</Text>
              <Row style={{ gap: 5, marginTop: 5 }}>
                {recommended.badges.map((b) => (
                  <View key={b} style={s.limePill}><Text style={{ fontSize: 9.5, fontWeight: '800', color: FOREST }}>✓ {b}</Text></View>
                ))}
              </Row>
              <Text style={{ fontSize: 12, color: '#b8c4ae', marginTop: 5 }}>
                ★ {recommended.rating} ({recommended.reviews}) · 러닝 {recommended.runs}회
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={{ fontSize: 20, fontWeight: '900', color: '#fff' }}>{fmtWon(priceForRunner(recommended))}</Text>
              <Text style={{ fontSize: 11, color: '#b8c4ae', marginTop: 2 }}>{recommended.distanceKm}km 거리</Text>
            </View>
          </Row>

          {/* AI summary */}
          <View style={s.descBox}>
            <Text style={{ fontSize: 12.5, color: '#dfe7d8', lineHeight: 19 }}>{recommended.desc}</Text>
          </View>

          {/* match bars */}
          <View style={{ gap: 13, marginTop: 16 }}>
            {recommended.match!.reasons.map((reason) => (
              <View key={reason.label}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Row style={{ gap: 7, flex: 1 }}>
                    <Text style={{ fontSize: 12, color: colors.volt }}>{reason.glyph}</Text>
                    <Text style={{ fontSize: 12, color: '#dfe7d8', flex: 1 }}>{reason.label}</Text>
                  </Row>
                  <Text style={{ fontSize: 13, fontWeight: '900', color: '#fff' }}>{reason.pct}%</Text>
                </Row>
                <View style={s.barTrack}>
                  <View style={[s.barFill, { width: `${reason.pct}%` }]} />
                </View>
              </View>
            ))}
          </View>

          {/* stat strip */}
          <View style={s.statStrip}>
            <StripStat label="평균 훈련 시간" value={`${recommended.pace} / km`} />
            <View style={s.stripDiv} />
            <StripStat label="최근 후기" value={`★ ${recommended.rating} (${recommended.reviews})`} />
            <View style={s.stripDiv} />
            <StripStat label="응답률" value={`${recommended.respondRate}%`} />
          </View>
        </View>
      </Pressable>

      <Text style={{ fontSize: 13, fontWeight: '700', color: '#5d655d', marginTop: 20, marginBottom: 10 }}>
        다른 러너도 살펴보세요
      </Text>

      {others.map((r) => (
        <Pressable key={r.id} onPress={() => pick(r.id)}>
          <View style={s.altCard}>
            <Row style={{ gap: 12 }}>
              <Monogram char={r.char} bg={r.color} size={52} />
              <View style={{ flex: 1 }}>
                <Row style={{ gap: 6 }}>
                  <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{r.name} 러너</Text>
                  {r.badges.map((b) => (
                    <View key={b} style={[s.sagePill, b === '훈련사' && { backgroundColor: '#fde8e3' }]}>
                      <Text style={{ fontSize: 9.5, fontWeight: '800', color: b === '훈련사' ? '#d84a2f' : '#4a6d1f' }}>{b}</Text>
                    </View>
                  ))}
                </Row>
                <Text style={{ fontSize: 12, color: colors.dim, marginTop: 4 }}>
                  ★ {r.rating} ({r.reviews}) · 러닝 {r.runs}회
                </Text>
              </View>
              <View style={{ alignItems: 'flex-end' }}>
                <Text style={{ fontSize: 18, fontWeight: '900', color: FOREST }}>{fmtWon(priceForRunner(r))}</Text>
                <Text style={{ fontSize: 11, color: colors.dim, marginTop: 2 }}>{r.distanceKm}km 거리</Text>
              </View>
            </Row>
            {r.tags && (
              <Row style={{ gap: 6, marginTop: 10 }}>
                <View style={s.tagChip}>
                  <Text style={{ fontSize: 10.5, fontWeight: '700', color: '#3d453d' }}>◈ {r.tags.join(' · ')}</Text>
                </View>
              </Row>
            )}
            <View style={s.altDivider} />
            <Row>
              <AltStat label="평균 페이스" value={`${r.pace} / km`} />
              <View style={s.altStatDiv} />
              <AltStat label="웰시코기 경험" value={`${r.breedExp}회`} />
              <View style={s.altStatDiv} />
              <AltStat label="신호 준수율" value={`${r.compliance}%`} />
            </Row>
          </View>
        </Pressable>
      ))}

      {/* trust footer */}
      <View style={s.trustNote}>
        <Text style={{ fontSize: 12, color: '#5d655d' }}>✓ 모든 러너는 신원 확인 및 펫보험에 가입되어 있어요.</Text>
        <Text style={{ fontSize: 14, color: colors.dim }}>›</Text>
      </View>
    </ScrollView>
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
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  aiBanner: { flexDirection: 'row', alignItems: 'center', backgroundColor: FOREST, borderRadius: 18, padding: 16, gap: 10 },
  aiChip: { borderWidth: 1, borderColor: '#3d5245', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 },
  topCard: {
    marginTop: 12, backgroundColor: FOREST, borderRadius: 22, padding: 16,
    borderWidth: 2, borderColor: colors.volt,
  },
  rankTab: {
    position: 'absolute', top: -1, left: -1, backgroundColor: colors.volt,
    borderTopLeftRadius: 20, borderBottomRightRadius: 16, paddingVertical: 6, paddingHorizontal: 14,
  },
  limePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  descBox: { backgroundColor: FOREST_INNER, borderRadius: 14, padding: 13, marginTop: 14 },
  barTrack: { height: 7, borderRadius: 99, backgroundColor: '#2c4034', marginTop: 6, overflow: 'hidden' },
  barFill: { height: 7, borderRadius: 99, backgroundColor: colors.volt },
  statStrip: { flexDirection: 'row', backgroundColor: FOREST_INNER, borderRadius: 14, paddingVertical: 12, marginTop: 16 },
  stripDiv: { width: 1, backgroundColor: '#2c4034', marginVertical: 2 },
  altCard: { backgroundColor: '#fff', borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#eceadf', marginBottom: 10 },
  sagePill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'center' },
  tagChip: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 10 },
  altDivider: { height: 1, backgroundColor: '#eceadf', marginVertical: 12 },
  altStatDiv: { width: 1, backgroundColor: '#eceadf' },
  trustNote: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    backgroundColor: '#f4f2ea', borderRadius: 14, paddingVertical: 12, paddingHorizontal: 14, marginTop: 8,
  },
});
