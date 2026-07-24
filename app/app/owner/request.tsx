import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { addDog, AvailRule, confirmPayment, createBookingHold, DogProfile, ensureDog, fetchMyDogs, fetchRoutes, fetchRunnerAvailability } from '../../src/lib/api';
import { HeatTrace } from '../../src/components/runcard';
import { Avatar, Row } from '../../src/components/ui';
import { AddonKey, dog, draft, fmtWon, sampleRoutes } from '../../src/store';
import { colors, pricing } from '../../src/theme';

// 러닝 요청 — route carousel (댕런 안심 코스), time-slot bottom sheet,
// slot-hold countdown on pay. See docs/calendar.md.

const FOREST = '#132117';
const CERT_BLUE = '#3d8fd4'; // 안심 코스 인증 블루 — certification only
const DISTANCES = [3, 5, 7];
const PACES = ["가볍게 8'+", "보통 7'", "신나게 6'"];
const ADDON_GLYPHS: Record<string, string> = { river: '♒', homecare: '⌂', snack: '≽', snap: '▣', livecam: '▶' };

// 실제 오늘부터 7일 — 하드코딩 날짜 금지
const DATES = Array.from({ length: 7 }, (_, i) => {
  const date = new Date(Date.now() + i * 86400_000);
  return {
    date,
    d: String(date.getDate()),
    w: '일월화수목금토'[date.getDay()],
    label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined,
  };
});
const SLOT_GROUPS = [
  { name: '오전', times: ['06:30', '07:30', '09:00'] },
  { name: '오후', times: ['13:00', '15:30', '17:00'] },
  { name: '저녁', times: ['18:30', '19:30', '21:00'] },
];

const toDate = (dateIdx: number, t: string): Date => {
  const base = DATES[dateIdx].date;
  const [h, m] = t.split(':').map(Number);
  return new Date(base.getFullYear(), base.getMonth(), base.getDate(), h, m);
};

export default function Request() {
  const [km, setKm] = useState(draft.km);
  const [pace, setPace] = useState(draft.pace);
  const [addons, setAddons] = useState<AddonKey[]>(draft.addons);
  const [routeId, setRouteId] = useState(draft.routeId);
  // 시간은 명시 선택 필수 — 라벨과 실예약 시각이 어긋나는 정직성 버그 방지 (ui-audit P0)
  const [timeLabel, setTimeLabel] = useState(draft.scheduledAtIso ? draft.timeLabel : '시간을 선택해주세요');
  const [routes, setRoutes] = useState(sampleRoutes);
  const [routesLive, setRoutesLive] = useState(false);
  const [myDogs, setMyDogs] = useState<DogProfile[]>([]);
  const [dogIdx, setDogIdx] = useState(0);
  const myDog = myDogs[dogIdx] ?? null;

  // 첫 실화(實化) 지점: 안심 코스는 서버에서 온다. 실패 시 목업 유지.
  useEffect(() => {
    fetchRoutes()
      .then((r) => {
        if (r.length > 0) {
          setRoutes(r);
          setRoutesLive(true);
          if (!r.some((x) => x.id === draft.routeId)) setRouteId(r[0].id);
        }
      })
      .catch(() => {});
    fetchMyDogs().then(setMyDogs).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const [slotSheet, setSlotSheet] = useState(false);
  const [holdVisible, setHoldVisible] = useState(false);
  const [holdSec, setHoldSec] = useState(300);
  const [holdLive, setHoldLive] = useState<null | boolean>(null); // null=진행, true=서버 홀드, false=목업 폴백
  const [dateIdx, setDateIdx] = useState(0);

  // 지명 러너 컨텍스트 — 그 러너의 가용시간 밖 슬롯은 비활성
  const preferred = draft.preferredRunnerId;
  const [prefRules, setPrefRules] = useState<AvailRule[] | null>(null);
  useEffect(() => {
    if (!preferred) { setPrefRules(null); return; }
    fetchRunnerAvailability(preferred).then(setPrefRules).catch(() => setPrefRules(null));
  }, [preferred]);

  const slotAllowed = (di: number, t: string): boolean => {
    const start = toDate(di, t);
    if (start.getTime() < Date.now() + 2 * 3600_000) return false; // 최소 2시간 통보
    if (!prefRules) return true; // 오픈 매칭 — 서버 홀드가 최종 검증
    const wd = start.getDay();
    const min = start.getHours() * 60 + start.getMinutes();
    return prefRules.some((r) => r.weekday === wd && r.startMin <= min && r.endMin >= min + 60);
  };

  const addonSum = addons.reduce((s2, k) => s2 + pricing.addons[k].price, 0);
  const total = pricing.baseFare + km * pricing.perKm + addonSum;
  const bestRoute = routes.reduce((a, b) => (a.fit > b.fit ? a : b));

  const toggleAddon = (k: AddonKey) =>
    setAddons((a) => (a.includes(k) ? a.filter((x) => x !== k) : [...a, k]));

  const pickSlot = (t: string, di = dateIdx) => {
    const when = toDate(di, t);
    draft.scheduledAtIso = when.toISOString(); // 실제 예약 시각 — +3h 하드코드 은퇴
    const day = DATES[di].label ?? `${when.getMonth() + 1}월 ${when.getDate()}일`;
    setTimeLabel(`${day} ${t}`);
    setSlotSheet(false);
  };

  // 가장 빠른 가능 슬롯
  const pickEarliest = () => {
    for (let di = 0; di < DATES.length; di++) {
      for (const g of SLOT_GROUPS) {
        for (const t of g.times) {
          if (slotAllowed(di, t)) { setDateIdx(di); pickSlot(t, di); return; }
        }
      }
    }
  };

  const pay = async () => {
    if (!draft.scheduledAtIso) {
      setSlotSheet(true); // 시간 미선택 → 결제 대신 슬롯 시트
      return;
    }
    Object.assign(draft, { km, pace, addons, routeId, timeLabel });
    setHoldSec(300);
    setHoldLive(null);
    setHoldVisible(true);

    // 실화: 서버에 원자적 홀드 + 예약 생성 (draft→quoted→payment_hold→matching)
    try {
      const dogId = myDog?.id ?? await ensureDog(); // 선택한 아이로 예약 (다견 가구)
      const res = await createBookingHold({
        dog_id: dogId,
        route_id: routesLive ? routeId : undefined, // 목업 코스 id는 uuid가 아님
        scheduled_at: draft.scheduledAtIso!, // pay()에서 선택 강제됨 — +3h 폴백 은퇴
        km,
        pace_label: pace,
        addons,
      });
      await confirmPayment(res.booking_id); // 결제 성공 시뮬레이션 → matching
      draft.bookingId = res.booking_id;
      setHoldLive(true);
    } catch {
      draft.bookingId = null;
      setHoldLive(false); // 서버 실패 → 목업 흐름 유지
    }
  };

  // slot-hold: brief countdown, then continue to matching
  useEffect(() => {
    if (!holdVisible) return;
    const tick = setInterval(() => setHoldSec((v) => v - 1), 1000);
    const go = setTimeout(() => {
      setHoldVisible(false);
      router.push('/owner/matching');
    }, 2600);
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
            <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>
              {preferred ? `★ ${draft.preferredRunnerName ?? '지명'} 러너` : '● 안심 결제'}
            </Text>
          </View>
        </Row>
        <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 6 }}>
          믿을 수 있는 러너와 우리 아이의 건강한 러닝을 시작해요.
        </Text>

        {/* dog */}
        <SectionHead glyph="◉" title="누가 달릴까요?" />
        <Row style={{ gap: 10 }}>
          <Pressable
            onPress={() => router.push('/owner/dog')}
            style={[s.card, { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 }]}
          >
            <Avatar url={myDog?.photoUrl} char={(myDog?.name ?? dog.name)[0]} bg="#c9a86e" size={40} />
            <Text style={{ flex: 1, fontSize: 14, fontWeight: '700', color: FOREST }}>
              {myDog?.name ?? dog.name} · {myDog?.breed ?? dog.breed} · {myDog?.weightKg ?? dog.weightKg}kg
            </Text>
            <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#5a7a3c' }}>프로필 ›</Text>
          </Pressable>
          <Pressable
            style={s.addDog}
            onPress={() => {
              Alert.prompt?.('반려견 추가', '이름을 입력해주세요', async (n) => {
                if (!n?.trim()) return;
                try {
                  const id = await addDog(n.trim());
                  const list = await fetchMyDogs();
                  setMyDogs(list);
                  setDogIdx(Math.max(list.findIndex((d) => d.id === id), 0));
                  router.push({ pathname: '/owner/dog', params: { dogId: id } });
                } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
              }) ?? Alert.alert('반려견 추가', 'iOS에서 지원돼요');
            }}
          >
            <Text style={{ fontSize: 18, color: FOREST }}>＋</Text>
            <Text style={{ fontSize: 9, color: colors.dim, marginTop: 2 }}>반려견 추가</Text>
          </Pressable>
        </Row>
        {/* 다견 선택 */}
        {myDogs.length > 1 && (
          <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
            {myDogs.map((d, i) => (
              <Pressable key={d.id} onPress={() => setDogIdx(i)} style={[s.dogSelChip, dogIdx === i && { backgroundColor: FOREST }]}>
                <Text style={{ fontSize: 12, fontWeight: '800', color: dogIdx === i ? '#fff' : '#3d453d' }}>{d.name}</Text>
              </Pressable>
            ))}
          </Row>
        )}

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
        <SectionHead glyph="⇢" title="페이스" />
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
        <Pressable style={[s.card, s.rowCard]} onPress={() => router.push('/owner/addresses')}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: FOREST }}>서울숲 2번 출입구</Text>
          <Text style={{ fontSize: 12, color: colors.dim }}>주소 관리 ›</Text>
        </Pressable>

        {/* ---------- 안심 코스 carousel (live from Supabase, mock fallback) ---------- */}
        <SectionHead
          glyph="✓"
          title="코스 선택"
          sub={routesLive ? '· 실시간 코스 정보' : '· 모든 코스는 댕런이 직접 점검해요'}
        />
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingRight: 22 }}>
          {routes.map((r) => {
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
          {preferred && (
            <Text style={{ fontSize: 11, color: '#5a7a3c', marginTop: 4, fontWeight: '700' }}>
              ★ {draft.preferredRunnerName ?? '지명'} 러너의 가능 시간만 선택할 수 있어요
            </Text>
          )}

          <Row style={{ gap: 8, marginTop: 12 }}>
            <View style={[s.methodChip, { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 11.5, fontWeight: '800', color: '#fff' }}>날짜·시간 선택</Text>
            </View>
            <Pressable style={s.methodChip} onPress={pickEarliest}>
              <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#3d453d' }}>가장 빠른 시간</Text>
            </Pressable>
            <View style={[s.methodChip, { opacity: 0.45 }]}>
              <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#3d453d' }}>반복 예약 (준비 중)</Text>
            </View>
          </Row>

          {/* date strip */}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }} contentContainerStyle={{ gap: 8 }}>
            {DATES.map((d, i) => (
              <Pressable key={d.date.toISOString()} onPress={() => setDateIdx(i)} style={[s.dateChip, dateIdx === i && { backgroundColor: FOREST }]}>
                <Text style={{ fontSize: 10, color: dateIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', color: dateIdx === i ? '#fff' : FOREST }}>{d.d}</Text>
                {d.label && <Text style={{ fontSize: 8.5, fontWeight: '700', color: dateIdx === i ? colors.volt : '#5a7a3c' }}>{d.label}</Text>}
              </Pressable>
            ))}
          </ScrollView>

          {/* slot groups — 지명 러너면 가용시간 밖 비활성, 과거/2시간 내 비활성 */}
          <ScrollView style={{ marginTop: 6, maxHeight: 300 }}>
            {SLOT_GROUPS.map((g) => (
              <View key={g.name} style={{ marginTop: 12 }}>
                <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#5d655d' }}>{g.name}</Text>
                <Row style={{ gap: 8, marginTop: 8 }}>
                  {g.times.map((t) => {
                    const ok = slotAllowed(dateIdx, t);
                    return (
                      <Pressable
                        key={t}
                        disabled={!ok}
                        onPress={() => pickSlot(t)}
                        style={[s.slot, !ok && { opacity: 0.35 }]}
                      >
                        <Text style={{ fontSize: 14, fontWeight: '800', color: FOREST }}>{t}</Text>
                        <Text style={{ fontSize: 9.5, color: ok ? '#5a7a3c' : colors.dim, marginTop: 2 }}>
                          {ok ? '가능' : prefRules ? '러너 불가' : '마감'}
                        </Text>
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
            <Text style={{ fontSize: 10, fontWeight: '800', marginTop: 10, color: holdLive === true ? '#4a6d1f' : holdLive === false ? '#a97c12' : colors.dim }}>
              {holdLive === true ? '● 서버 홀드 확보 — 예약이 생성됐어요' : holdLive === false ? '오프라인 데모 모드' : '서버 연결 중...'}
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
  dogSelChip: { backgroundColor: '#fff', borderRadius: 99, borderWidth: 1.3, borderColor: '#dcd9cc', paddingVertical: 8, paddingHorizontal: 15 },
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
