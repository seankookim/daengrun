import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { AddonKey, dog, draft, fmtWon } from '../../src/store';
import { colors, pricing } from '../../src/theme';

// 러닝 요청 — icon section headers, addon 2×2 grid, sticky pay bar, per mock.

const FOREST = '#132117';
const DISTANCES = [3, 5, 7];
const PACES = ["가볍게 8'+", "보통 7'", "신나게 6'"];
const ADDON_GLYPHS: Record<string, string> = { river: '♒', homecare: '⌂', snack: '≽', snap: '▣' };

export default function Request() {
  const [km, setKm] = useState(draft.km);
  const [pace, setPace] = useState(draft.pace);
  const [addons, setAddons] = useState<AddonKey[]>(draft.addons);

  const addonSum = addons.reduce((s2, k) => s2 + pricing.addons[k].price, 0);
  const total = pricing.baseFare + km * pricing.perKm + addonSum;

  const toggleAddon = (k: AddonKey) =>
    setAddons((a) => (a.includes(k) ? a.filter((x) => x !== k) : [...a, k]));

  const next = () => {
    Object.assign(draft, { km, pace, addons });
    router.push('/owner/matching');
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 130 }}>
        {/* header */}
        <Row style={{ gap: 12 }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 24, fontWeight: '900', color: FOREST }}>러닝 요청</Text>
          </View>
          <View style={s.livePill}>
            <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>● LIVE 러너 12명</Text>
          </View>
        </Row>
        <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 6 }}>
          믿을 수 있는 러너와 우리 아이의 건강한 러닝을 시작해요.
        </Text>

        {/* dog */}
        <SectionHead glyph="◉" title="누가 달릴까요?" />
        <Row style={{ gap: 10 }}>
          <View style={[s.card, { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 }]}>
            <Monogram char={dog.name[0]} bg="#c9a86e" size={40} />
            <Text style={{ flex: 1, fontSize: 14, fontWeight: '700', color: FOREST }}>
              {dog.name} · {dog.breed} · {dog.weightKg}kg
            </Text>
            <Text style={{ fontSize: 12, color: colors.dim }}>▾</Text>
          </View>
          <View style={s.addDog}>
            <Text style={{ fontSize: 18, color: FOREST }}>＋</Text>
            <Text style={{ fontSize: 9, color: colors.dim, marginTop: 2 }}>반려견 추가</Text>
          </View>
        </Row>

        {/* distance */}
        <SectionHead glyph="⌖" title="거리" side="코스 안내" />
        <Row style={{ gap: 10 }}>
          {DISTANCES.map((d) => (
            <Pressable key={d} onPress={() => setKm(d)} style={[s.bigChip, km === d && s.bigChipSel]}>
              {km === d && <View style={s.bolt}><Text style={{ fontSize: 9, color: FOREST }}>⚡</Text></View>}
              <Text style={[s.bigChipText, km === d && { color: '#fff' }]}>{d}km</Text>
            </Pressable>
          ))}
        </Row>

        {/* pace */}
        <SectionHead glyph="⇢" title="페이스" side="페이스 가이드" />
        <Row style={{ gap: 10 }}>
          {PACES.map((pc) => (
            <Pressable key={pc} onPress={() => setPace(pc)} style={[s.bigChip, pace === pc && s.bigChipSel]}>
              <Text style={[s.bigChipText, { fontSize: 14 }, pace === pc && { color: '#fff' }]}>{pc}</Text>
            </Pressable>
          ))}
        </Row>

        {/* when */}
        <SectionHead glyph="◷" title="언제 달릴까요?" />
        <View style={[s.card, s.rowCard]}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: FOREST }}>오늘 오후 6:30</Text>
          <Text style={{ fontSize: 12, color: colors.dim }}>변경 ›</Text>
        </View>

        {/* pickup */}
        <SectionHead glyph="➤" title="픽업 장소" />
        <View style={[s.card, s.rowCard]}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: FOREST }}>서울숲 2번 출입구</Text>
          <Text style={{ fontSize: 12, color: colors.dim }}>지도 ›</Text>
        </View>

        {/* premium addons — 2×2 grid */}
        <SectionHead glyph="✦" title="프리미엄 옵션" sub="· 원하는 만큼 추가해보세요" />
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
          {(Object.keys(pricing.addons) as AddonKey[]).map((k) => {
            const a = pricing.addons[k];
            const sel = addons.includes(k);
            return (
              <Pressable key={k} onPress={() => toggleAddon(k)} style={[s.addon, sel && { borderColor: '#a9c47e' }]}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <View style={s.addonIcon}><Text style={{ fontSize: 14, color: '#5a7a3c' }}>{ADDON_GLYPHS[k]}</Text></View>
                  <View style={[s.checkCircle, sel && { backgroundColor: colors.volt, borderColor: colors.volt }]}>
                    {sel && <Text style={{ fontSize: 10, fontWeight: '900', color: FOREST }}>✓</Text>}
                  </View>
                </Row>
                <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST, marginTop: 10 }}>{a.label}</Text>
                <Text style={{ fontSize: 11, color: '#75806f', marginTop: 2 }}>{a.desc}</Text>
                <Text style={{ fontSize: 13, fontWeight: '900', color: '#5a7a3c', marginTop: 8 }}>+{a.price.toLocaleString()}원</Text>
              </Pressable>
            );
          })}
        </View>

        {/* fee detail */}
        <View style={[s.card, { marginTop: 18 }]}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 10 }}>
            <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>요금 상세</Text>
            <Text style={{ fontSize: 12, color: colors.dim }}>접기 ⌃</Text>
          </Row>
          <FeeRow label="기본요금" value={fmtWon(pricing.baseFare)} />
          <FeeRow label={`거리요금 ${km}km`} value={fmtWon(km * pricing.perKm)} />
          {addonSum > 0 && <FeeRow label={`프리미엄 옵션 ${addons.length}개`} value={`+${fmtWon(addonSum)}`} />}
          <View style={{ height: 1, backgroundColor: '#eceadf', marginVertical: 12 }} />
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: FOREST }}>총 결제 금액</Text>
            <Text style={{ fontSize: 24, fontWeight: '900', color: FOREST }}>{fmtWon(total)}</Text>
          </Row>
        </View>
      </ScrollView>

      {/* sticky pay bar */}
      <View style={s.payBar}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#fff' }}>지금 결제하고 러너 매칭하기</Text>
          <Text style={{ fontSize: 10.5, color: '#b8c4ae', marginTop: 2 }}>안전 결제 · 취소 수수료 없음</Text>
        </View>
        <Pressable onPress={next} style={s.payBtn}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{fmtWon(total)} 결제하기 ›</Text>
        </Pressable>
      </View>
    </View>
  );
}

function SectionHead({ glyph, title, side, sub }: { glyph: string; title: string; side?: string; sub?: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 22, marginBottom: 10 }}>
      <Row style={{ gap: 7 }}>
        <Text style={{ fontSize: 13, color: '#5a7a3c' }}>{glyph}</Text>
        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{title}</Text>
        {sub && <Text style={{ fontSize: 11, color: colors.dim, alignSelf: 'flex-end' }}>{sub}</Text>}
      </Row>
      {side && (
        <View style={s.sideBtn}><Text style={{ fontSize: 11, fontWeight: '700', color: '#3d453d' }}>{side}</Text></View>
      )}
    </Row>
  );
}

function FeeRow({ label, value }: { label: string; value: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
      <Text style={{ fontSize: 13, color: '#75806f' }}>{label}</Text>
      <Text style={{ fontSize: 13, color: '#3d453d', fontWeight: '600' }}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  livePill: { backgroundColor: '#f0f6e2', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12, borderWidth: 1, borderColor: '#dde8c4', alignSelf: 'center' },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 16, borderWidth: 1, borderColor: '#eceadf' },
  rowCard: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 15 },
  addDog: { width: 64, borderRadius: 18, backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf', alignItems: 'center', justifyContent: 'center' },
  bigChip: { flex: 1, backgroundColor: '#fff', borderRadius: 18, paddingVertical: 16, alignItems: 'center', borderWidth: 1, borderColor: '#eceadf' },
  bigChipSel: { backgroundColor: FOREST, borderWidth: 2, borderColor: colors.volt },
  bigChipText: { fontSize: 16, fontWeight: '800', color: '#3d453d' },
  bolt: {
    position: 'absolute', top: -9, alignSelf: 'center', width: 18, height: 18, borderRadius: 9,
    backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center', zIndex: 2,
  },
  sideBtn: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 6, paddingHorizontal: 11, borderWidth: 1, borderColor: '#eceadf' },
  addon: { width: '47.8%', backgroundColor: '#fff', borderRadius: 18, padding: 13, borderWidth: 1.5, borderColor: '#eceadf' },
  addonIcon: { width: 34, height: 34, borderRadius: 10, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  checkCircle: { width: 22, height: 22, borderRadius: 11, borderWidth: 1.5, borderColor: '#dcd9cc', alignItems: 'center', justifyContent: 'center' },
  payBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: FOREST, paddingHorizontal: 20, paddingTop: 14, paddingBottom: 30,
    borderTopLeftRadius: 24, borderTopRightRadius: 24,
  },
  payBtn: { backgroundColor: colors.volt, borderRadius: 16, paddingVertical: 14, paddingHorizontal: 18 },
});
