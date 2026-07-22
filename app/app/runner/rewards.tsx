import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { rewardStatus, runnerGearLadder } from '../../src/store';
import { colors } from '../../src/theme';

// 리워드 센터 — two-beat retention loop:
// 5회마다 보급 드랍 (variable, floor guaranteed) · 10회마다 픽 드랍 (choose 1 of 3).
// Schema seed: drops, boosts, gear_claims, miles_ledger. Choice data reveals runner motivation.

const FOREST = '#132117';

const PICK_OPTIONS = [
  { key: 'boost', title: '매칭 부스트 24h', desc: '요청 노출 최상단 · 예상 +1~2건', glyph: '⚡' },
  { key: 'miles', title: '5,000 댕마일', desc: '샵에서 현금처럼 사용', glyph: '◈' },
  { key: 'gear', title: '기어 교환권', desc: '반다나·삭스·밴드 중 선택', glyph: '▣' },
];

export default function Rewards() {
  const [pick, setPick] = useState<string | null>(null);

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 19, fontWeight: '900', color: FOREST }}>리워드 센터</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginBottom: 16 }}>
        달릴수록 열리는 것들 · 보유 {rewardStatus.daengMiles.toLocaleString()} 댕마일
      </Text>

      {/* drop progress */}
      <View style={s.progressCard}>
        <DropRow label="보급 드랍" sub="5회마다 · 댕마일 + 카드/기어 확률" left={rewardStatus.toMini} total={5} />
        <View style={{ height: 1, backgroundColor: '#2c4034', marginVertical: 13 }} />
        <DropRow label="픽 드랍" sub="10회마다 · 셋 중 하나 선택" left={rewardStatus.toPick} total={10} accent />
      </View>

      {/* pick drop preview / chooser */}
      <Text style={s.section}>픽 드랍 — 220회 도달 시 선택</Text>
      <View style={{ gap: 8 }}>
        {PICK_OPTIONS.map((o) => (
          <Pressable
            key={o.key}
            onPress={() => setPick(o.key)}
            style={[s.pickCard, pick === o.key && { borderColor: colors.volt, borderWidth: 2, backgroundColor: '#f7faee' }]}
          >
            <View style={s.pickIcon}><Text style={{ fontSize: 15, color: '#5a7a3c' }}>{o.glyph}</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>{o.title}</Text>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>{o.desc}</Text>
            </View>
            <View style={[s.radio, pick === o.key && { borderColor: '#5a7a3c' }]}>
              {pick === o.key && <View style={s.radioDot} />}
            </View>
          </Pressable>
        ))}
      </View>
      <Pressable
        style={[s.claimBtn, { opacity: 0.45 }]}
        onPress={() => Alert.alert('픽 드랍', `${rewardStatus.toPick}회 더 달리면 선택할 수 있어요`)}
      >
        <Text style={{ fontSize: 13.5, fontWeight: '900', color: FOREST }}>아직 {rewardStatus.toPick}회 남았어요</Text>
      </Pressable>

      {/* gear ladder */}
      <Text style={s.section}>기어 사다리 — 러닝 어패럴</Text>
      <View style={s.card}>
        {runnerGearLadder.map((g, i) => (
          <View key={g.at}>
            {i > 0 && <View style={{ height: 1, backgroundColor: '#f0eee3' }} />}
            <Row style={{ paddingVertical: 11, gap: 12 }}>
              <View style={[s.gearDot, g.got && { backgroundColor: '#6aa53c' }]}>
                {g.got && <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>✓</Text>}
              </View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 13.5, fontWeight: '800', color: g.got ? FOREST : '#9a9a90' }}>{g.item}</Text>
                <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 1 }}>누적 러닝 {g.at}회</Text>
              </View>
              {g.got ? (
                <Text style={{ fontSize: 10.5, fontWeight: '700', color: '#5a7a3c' }}>수령 완료</Text>
              ) : (
                <Text style={{ fontSize: 10.5, color: colors.dim }}>{g.at - rewardStatus.totalRuns}회 남음</Text>
              )}
            </Row>
          </View>
        ))}
      </View>

      <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 14, lineHeight: 15 }}>
        기어를 입고 달리는 순간, 당신이 댕런의 얼굴이에요{'\n'}드랍 확률과 구성은 공지로 투명하게 공개돼요
      </Text>
    </ScrollView>
  );
}

function DropRow({ label, sub, left, total, accent }: { label: string; sub: string; left: number; total: number; accent?: boolean }) {
  const pct = ((total - left) / total) * 100;
  return (
    <View>
      <Row style={{ justifyContent: 'space-between' }}>
        <Text style={{ fontSize: 14, fontWeight: '900', color: accent ? colors.volt : '#fff' }}>{label}</Text>
        <Text style={{ fontSize: 12, fontWeight: '800', color: '#b8c4ae' }}>{left}회 남음</Text>
      </Row>
      <Text style={{ fontSize: 10.5, color: '#8fa093', marginTop: 2 }}>{sub}</Text>
      <View style={s.dropBar}>
        <View style={[s.dropFill, { width: `${pct}%` }]} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  progressCard: { backgroundColor: FOREST, borderRadius: 20, padding: 18 },
  dropBar: { height: 6, borderRadius: 99, backgroundColor: '#2c4034', marginTop: 8, overflow: 'hidden' },
  dropFill: { height: 6, borderRadius: 99, backgroundColor: colors.volt },
  section: { fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 10 },
  pickCard: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#fff', borderRadius: 16, padding: 14, borderWidth: 1.4, borderColor: '#eceadf',
  },
  pickIcon: { width: 38, height: 38, borderRadius: 12, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  radio: { width: 18, height: 18, borderRadius: 9, borderWidth: 2, borderColor: '#d8d5c8', alignItems: 'center', justifyContent: 'center' },
  radioDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: '#5a7a3c' },
  claimBtn: { backgroundColor: colors.volt, borderRadius: 14, alignItems: 'center', paddingVertical: 13, marginTop: 10 },
  card: { backgroundColor: '#fff', borderRadius: 18, paddingHorizontal: 15, paddingVertical: 4, borderWidth: 1, borderColor: '#eceadf' },
  gearDot: { width: 20, height: 20, borderRadius: 10, backgroundColor: '#e2e0d4', alignItems: 'center', justifyContent: 'center' },
});
