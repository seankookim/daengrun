import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { applyStatus } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 인증 센터 — the supply funnel. Defines runners-table schema:
// application fields, KYC artifacts, education progress, trial evaluation, tier.

const FOREST = '#0F1D13';

const TIERS = [
  { name: '인증 러너', req: '지원 절차 완료', perk: '기본 요청 수신' },
  { name: '베테랑', req: '러닝 250회 · ★4.8+', perk: '수수료 18% · 프리미엄 요청 우선' },
  { name: '마스터', req: '러닝 1,000회 · ★4.9+ · 무사고', perk: '수수료 15% · 시범 러닝 평가관 · 전용 배지' },
];

export default function Apply() {
  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 22, fontWeight: '900', color: FOREST }}>러너 인증 센터</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginBottom: 16 }}>
        검증된 러너만 아이들을 만나요 — 비포펫의 체크리스트가 아니라 커리어예요
      </Text>

      {/* current tier */}
      <View style={s.tierCard}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={{ fontSize: 14.5, color: '#b8c4ae', letterSpacing: 1.5 }}>현재 등급</Text>
            <Text style={{ fontSize: 27.5, fontWeight: '900', color: colors.volt, marginTop: 3 }}>{applyStatus.tier}</Text>
          </View>
          <View style={{ alignItems: 'flex-end' }}>
            <Text style={{ fontSize: 14.5, color: '#b8c4ae' }}>다음 등급: {applyStatus.nextTier}</Text>
            <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff', marginTop: 3 }}>러닝 {applyStatus.runsToNext}회 남음</Text>
          </View>
        </Row>
        <View style={s.tierBar}>
          <View style={[s.tierFill, { width: '86%' }]} />
        </View>
      </View>

      {/* application steps */}
      <Text style={s.section}>지원 절차</Text>
      <View style={s.card}>
        {applyStatus.steps.map((st, i) => (
          <View key={st.key}>
            {i > 0 && <View style={s.stepLine} />}
            <Pressable
              style={{ flexDirection: 'row', gap: 12, paddingVertical: 4 }}
              onPress={() => Alert.alert(st.label, st.done ? '완료된 단계예요' : `${st.desc} (목업)`)}
            >
              <View style={[s.stepDot, st.done && { backgroundColor: '#6aa53c' }, st.active && s.stepActive]}>
                {st.done ? <Text style={{ fontSize: 11.5, fontWeight: '900', color: '#fff' }}>✓</Text>
                  : <Text style={{ fontSize: 14, fontWeight: '900', color: st.active ? '#a97c12' : '#b3b3ab' }}>{i + 1}</Text>}
              </View>
              <View style={{ flex: 1 }}>
                <Row style={{ gap: 6 }}>
                  <Text style={{ fontSize: 16.5, fontWeight: '800', color: st.done || st.active ? FOREST : '#9a9a90' }}>{st.label}</Text>
                  {st.active && <View style={s.nowPill}><Text style={{ fontSize: 14, fontWeight: '900', color: '#a97c12' }}>진행 중</Text></View>}
                </Row>
                <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>{st.desc}</Text>
              </View>
              {st.active && <Text style={{ fontSize: 15, color: '#5a7a3c', alignSelf: 'center' }}>›</Text>}
            </Pressable>
          </View>
        ))}
      </View>

      <Pressable style={s.continueBtn} onPress={() => Alert.alert('안전 교육', '모듈 5/6: 여름철 열사병 신호 (목업)')}>
        <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>교육 이어하기 — 모듈 5/6</Text>
      </Pressable>

      {/* tier ladder */}
      <Text style={s.section}>등급 사다리</Text>
      {TIERS.map((t) => (
        <View key={t.name} style={[s.card, { marginBottom: 8 }, t.name === applyStatus.tier && { borderColor: '#a9c47e', borderWidth: 1.6 }]}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>{t.name}</Text>
            {t.name === applyStatus.tier && (
              <View style={s.nowPill}><Text style={{ fontSize: 14, fontWeight: '900', color: '#4a6d1f' }}>현재</Text></View>
            )}
          </Row>
          <Text style={{ fontSize: 15, color: colors.dim, marginTop: 4 }}>조건: {t.req}</Text>
          <Text style={{ fontSize: 14, fontWeight: '700', color: '#5a7a3c', marginTop: 2 }}>혜택: {t.perk}</Text>
        </View>
      ))}

      <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 10, lineHeight: 17 }}>
        신원 서류는 암호화 보관되며 인증 완료 후 원본은 파기돼요{'\n'}허위 제출 시 영구 활동 정지
      </Text>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  tierCard: { backgroundColor: FOREST, borderRadius: 20, padding: 18 },
  tierBar: { height: 7, borderRadius: 99, backgroundColor: '#2c4034', marginTop: 14, overflow: 'hidden' },
  tierFill: { height: 7, borderRadius: 99, backgroundColor: colors.volt },
  section: { fontSize: 17, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 10 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#DCD6C4' },
  stepLine: { width: 2, height: 14, backgroundColor: '#DCD6C4', marginLeft: 10, marginVertical: 2 },
  stepDot: { width: 22, height: 22, borderRadius: 11, backgroundColor: '#DCD6C4', alignItems: 'center', justifyContent: 'center' },
  stepActive: { backgroundColor: '#fbf0d4', borderWidth: 1.6, borderColor: '#e2c56b' },
  nowPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  continueBtn: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14, marginTop: 12 },
});
