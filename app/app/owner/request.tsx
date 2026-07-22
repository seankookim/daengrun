import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { HeatTrace } from '../../src/components/runcard';
import { Monogram, Row } from '../../src/components/ui';
import { AddonKey, dog, draft, fmtWon, sampleRoutes } from '../../src/store';
import { colors, pricing } from '../../src/theme';

// 러닝 요청 — route carousel (댕런 안심 코스), time-slot bottom sheet,
// slot-hold countdown on pay. See docs/calendar.md.

const FOREST = '#132117';
const CERT_BLUE = '#3d8fd4'; // 안심 코스 인증 블루 — certification only
const DISTANCES = [3, 5, 7];
const PACES = ["가볍게 8'+", "보통 7'", "신나게 6'"];
const ADDON_GLYPHS: Record<string, string> = { river: '♒', homecare: '⌂', snack: '≽', snap: '▣' };

const DATES = [
  { d: '22', w: '수', label: '오늘' }, { d: '23', w: '목', label: '내일' }, { d: '24', w: '금' },
  { d: '25', w: '토' }, { d: '26', w: '일' }, { d: '27', w: '월' }, { d: '28', w: '화' },
];
const SLOT_GROUPS = [
  { name: '오전', slots: [{ t: '06:30', n: 5 }, { t: '07:30', n: 8 }, { t: '09:00', n: 3 }] },
  { name: '오후', slots: [{ t: '13:00', n: 2 }, { t: '15:30', n: 0 }, { t: '17:00', n: 6 }] },
  { name: '저녁', slots: [{ t: '18:30', n: 8, hot: true }, { t: '19:30', n: 4 }, { t: '21:00', n: 2, sale: true }] },
];

export default function Request() {
  const [km, setKm] = useState(draft.km);
  const [pace, setPace] = useState(draft.pace);
  const [addons, setAddons] = useState<AddonKey[]>(draft.addons);
  const [routeId, setRouteId] = useState(draft.routeId);
  const [timeLabel, setTimeLabel] = useState(draft.timeLabel);
  const [slotSheet, setSlotSheet] = useState(false);
  const [holdVisible, setHoldVisible] = useState(false);
  const [holdSec, setHoldSec] = useState(300);
  const [dateIdx, setDateIdx] = useState(0);

  const addonSum = addons.reduce((s2, k) => s2 + pricing.addons[k].price, 0);
  const total = pricing.baseFare + km * pricing.perKm + addonSum;
  const bestRoute = sampleRoutes.reduce((a, b) => (a.fit > b.fit ? a : b));

  const toggleAddon = (k: AddonKey) =>
    setAddons((a) => (a.includes(k) ? a.filter((x) => x !== k) : [...a, k]));

  const pickSlot = (t: string) => {
    const day = DATES[dateIdx].label ?? `7월 ${DATES[dateIdx].d}일`;
    setTimeLabel(`${day} ${t}`);
    setSlotSheet(false);
  };

  const pay = () => {
    Object.assign(draft, { km, pace, addons, routeId, timeLabel });
    setHoldSec(300);
    setHoldVisible(true);
  };

  // slot-hold: brief countdown demo, then continue to matching
  useEffect(() => {
    if (!holdVisible) return;
    const tick = setInterval(() => setHoldSec((v) => v - 1), 1000);
    const go = setTimeout(() => {
      setHoldVisible(false);
      router.push('/owner/matching');
    }, 2200);
    return () => { clearInterval(tick); clearTimeout(go); };
  }, [holdVisible]);

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
        <SectionHead glyph="⌖" title="거리" />
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

        {/* when — opens slot sheet */}
        <SectionHead glyph="◷" title="언제 달릴까요?" />
        <Pressable style={[s.card, s.rowCard]} onPress={() => setSlotSheet(true)}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: FOREST }}>{timeLabel}</Text>
          <Text style={{ fontSize: 12, color: colors.dim }}>변경 ›</Text>
        </Pressable>

        {/* pickup */}
        <SectionHead glyph="➤" title="픽업 장소" />
        <View style={[s.card, s.rowCard]}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: FOREST }}>서울숲 2번 출입구</Text>
          <Text style={{ fontSize: 12, color: colors.dim }}>지도 ›</Text>
        </View>

        {/* ---------- 안심 코스 carousel ---------- */}
        <SectionHead glyph="✓" title="코스 선택" sub="· 모든 코스는 댕런이 직접 점검해요" />
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingRight: 22 }}>
          {sampleRoutes.map((r) => {
            const sel = routeId === r.id;
            const isBest = r.id === bestRoute.id;
            return (
              <Pressable key={r.id} onPress={() => setRouteId(r.id)} style={[s.routeCard, sel && { borderColor: colors.volt, borderWidth: 2 }]}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Row style={{ gap: 5, flex: 1 }}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }} numberOfLines={1}>{r.name}</Text>
                    <View style={s.certBadge}><Text style={{ fontSize: 8, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                  </Row>
                  {isBest && <View style={s.bestPill}><Text style={{ fontSize: 9, fontWeight: '900', color: FOREST }}>추천</Text></View>}
                </Row>
                <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 2 }}>
                  {r.area} · {r.km}km · {r.terrain} · 안심 코스 {r.checkedAt}
                </Text>

                <View style={s.routeMap}>
                  <HeatTrace points={r.trace} width={196} height={86} />
                </View>

                <Row style={{ gap: 4, marginTop: 8, flexWrap: 'wrap' }}>
                  {r.tags.map((tag) => (
                    <View key={tag} style={s.routeTag}><Text style={{ fontSize: 9, fontWeight: '700', color: '#4a6d1f' }}>{tag}</Text></View>
                  ))}
                </Row>
                <Row style={{ justifyContent: 'space-between', marginTop: 8 }}>
                  <Text style={{ fontSize: 10.5, color: '#75806f', flex: 1 }} numberOfLines={2}>{r.desc}</Text>
                </Row>
                <Text style={{ fontSize: 11, fontWeight: '900', color: '#5a7a3c', marginTop: 6 }}>
                  {dog.name} 적합도 {r.fit}%
                </Text>
              </Pressable>
            );
          })}
        </ScrollView>

        {/* premium addons */}
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
        <Pressable onPress={pay} style={s.payBtn}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{fmtWon(total)} 결제하기 ›</Text>
        </Pressable>
      </View>

      {/* ---------- time-slot bottom sheet ---------- */}
      <Modal visible={slotSheet} transparent animationType="slide" onRequestClose={() => setSlotSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setSlotSheet(false)} />
        <View style={s.sheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>언제 달릴까요?</Text>

          <Row style={{ gap: 8, marginTop: 12 }}>
            <View style={[s.methodChip, { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#fff' }}>날짜·시간 선택</Text>
            </View>
            <Pressable style={s.methodChip} onPress={() => pickSlot('18:30')}>
              <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#3d453d' }}>가장 빠른 시간</Text>
            </Pressable>
            <View style={[s.methodChip, { opacity: 0.45 }]}>
              <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#3d453d' }}>반복 예약 (준비 중)</Text>
            </View>
          </Row>

          {/* date strip */}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }} contentContainerStyle={{ gap: 8 }}>
            {DATES.map((d, i) => (
              <Pressable key={d.d} onPress={() => setDateIdx(i)} style={[s.dateChip, dateIdx === i && { backgroundColor: FOREST }]}>
                <Text style={{ fontSize: 10, color: dateIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', color: dateIdx === i ? '#fff' : FOREST }}>{d.d}</Text>
                {d.label && <Text style={{ fontSize: 8.5, fontWeight: '700', color: dateIdx === i ? colors.volt : '#5a7a3c' }}>{d.label}</Text>}
              </Pressable>
            ))}
          </ScrollView>

          {/* slot groups */}
          <ScrollView style={{ marginTop: 6, maxHeight: 300 }}>
            {SLOT_GROUPS.map((g) => (
              <View key={g.name} style={{ marginTop: 12 }}>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#5d655d' }}>{g.name}</Text>
                <Row style={{ gap: 8, marginTop: 8 }}>
                  {g.slots.map((slot) => {
                    const disabled = slot.n === 0;
                    return (
                      <Pressable
                        key={slot.t}
                        disabled={disabled}
                        onPress={() => pickSlot(slot.t)}
                        style={[s.slot, disabled && { opacity: 0.35 }]}
                      >
                        <Text style={{ fontSize: 14, fontWeight: '800', color: FOREST }}>{slot.t}</Text>
                        <Text style={{ fontSize: 9.5, color: disabled ? colors.dim : '#5a7a3c', marginTop: 2 }}>
                          {disabled ? '마감' : `러너 ${slot.n}명`}
                        </Text>
                        {slot.hot && <View style={s.hotPill}><Text style={{ fontSize: 8, fontWeight: '900', color: '#d84a2f' }}>인기</Text></View>}
                        {slot.sale && <View style={[s.hotPill, { backgroundColor: '#e3f0c4' }]}><Text style={{ fontSize: 8, fontWeight: '900', color: '#4a6d1f' }}>-2,000</Text></View>}
                      </Pressable>
                    );
                  })}
                </Row>
              </View>
            ))}
          </ScrollView>
        </View>
      </Modal>

      {/* ---------- slot-hold countdown ---------- */}
      <Modal visible={holdVisible} transparent animationType="fade">
        <View style={s.holdBackdrop}>
          <View style={s.holdCard}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>슬롯을 잡아두고 있어요</Text>
            <Text style={{ fontSize: 30, fontWeight: '900', color: '#5a7a3c', marginTop: 10 }}>
              {Math.floor(holdSec / 60)}:{String(holdSec % 60).padStart(2, '0')}
            </Text>
            <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 8, textAlign: 'center' }}>
              {timeLabel} 슬롯이 결제 완료까지{'\n'}다른 보호자에게 보이지 않아요
            </Text>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function SectionHead({ glyph, title, side, sub }: { glyph: string; title: string; side?: string; sub?: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 22, marginBottom: 10 }}>
      <Row style={{ gap: 7, flex: 1 }}>
        <Text style={{ fontSize: 13, color: '#5a7a3c' }}>{glyph}</Text>
        <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{title}</Text>
        {sub && <Text style={{ fontSize: 10.5, color: colors.dim, alignSelf: 'flex-end', flex: 1 }} numberOfLines={1}>{sub}</Text>}
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
  // route carousel
  routeCard: { width: 224, backgroundColor: '#fff', borderRadius: 18, padding: 13, borderWidth: 1.5, borderColor: '#eceadf' },
  certBadge: {
    width: 15, height: 15, borderRadius: 8, backgroundColor: '#3d8fd4',
    alignItems: 'center', justifyContent: 'center', alignSelf: 'center',
  },
  bestPill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'flex-start' },
  routeMap: { marginTop: 10, borderRadius: 12, backgroundColor: '#0e150f', padding: 0, overflow: 'hidden', paddingVertical: 4, paddingHorizontal: 2 },
  routeTag: { backgroundColor: '#eef4e0', borderRadius: 7, paddingVertical: 3, paddingHorizontal: 6 },
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
  // slot sheet
  sheetBackdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 22, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#d8d5c8', marginBottom: 14 },
  methodChip: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#eceadf' },
  dateChip: { width: 52, borderRadius: 14, backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf', alignItems: 'center', paddingVertical: 9, gap: 1 },
  slot: { flex: 1, backgroundColor: '#fff', borderRadius: 13, borderWidth: 1, borderColor: '#eceadf', alignItems: 'center', paddingVertical: 11 },
  hotPill: { position: 'absolute', top: -7, right: 6, backgroundColor: '#fde8e3', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 6 },
  // hold modal
  holdBackdrop: { flex: 1, backgroundColor: '#00000066', alignItems: 'center', justifyContent: 'center' },
  holdCard: { width: 270, backgroundColor: '#fff', borderRadius: 22, padding: 24, alignItems: 'center' },
});
