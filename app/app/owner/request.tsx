import { useDisplayFont } from '../../src/lib/displayFont';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { addDog, Addr, AvailRule, confirmPayment, createBookingHold, createRecurringSeries, DogProfile, ensureDog, fetchAddresses, fetchMyDogs, fetchRoutes, fetchRunnerAvailability, requestRunner } from '../../src/lib/api';
import { HeatTrace } from '../../src/components/runcard';
import { Avatar, Row } from '../../src/components/ui';
import { haptic } from '../../src/lib/haptics';
import { AddonKey, dog, draft, fmtWon, sampleRoutes } from '../../src/store';
import { colors, pricing } from '../../src/theme';

// 러닝 요청 — route carousel (도그스하이 안심 코스), time-slot bottom sheet,
// slot-hold countdown on pay. See docs/calendar.md.

const FOREST = '#0F1D13';
const CERT_BLUE = '#3d8fd4'; // 안심 코스 인증 블루 — certification only
const DISTANCES = [3, 5, 7];
const PACES = ["가볍게 8'+", "보통 7'", "신나게 6'"];
const ADDON_GLYPHS: Record<string, string> = { river: '♒', homecare: '⌂', snack: '≽', snap: '▣', livecam: '▶' };

// 실제 오늘부터 7일 — 컴포넌트 안에서 생성 (모듈 로드 고정은 자정을 넘기면 '오늘'이 어제가 됐다)
const buildDates = () => Array.from({ length: 7 }, (_, i) => {
  const date = new Date(Date.now() + i * 86400_000);
  return {
    date,
    d: String(date.getDate()),
    w: '일월화수목금토'[date.getDay()],
    label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined,
  };
});
let DATES = buildDates(); // toDate 등 모듈 헬퍼 호환용 — 화면 마운트마다 갱신
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
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  // 날짜 스트립 갱신 — 마운트 시점 기준 (자정 넘김 스테일 방지)
  useMemo(() => { DATES = buildDates(); }, []);
  const [km, setKm] = useState(draft.km);
  const [pace, setPace] = useState(draft.pace);
  const [addons, setAddons] = useState<AddonKey[]>(draft.addons);
  const [routeId, setRouteId] = useState(draft.routeId);
  // 시간은 명시 선택 필수 — 라벨과 실예약 시각이 어긋나는 정직성 버그 방지 (ui-audit P0)
  const [timeLabel, setTimeLabel] = useState(draft.scheduledAtIso ? draft.timeLabel : '시간을 선택해주세요');
  const [routes, setRoutes] = useState(sampleRoutes);
  const [routesLive, setRoutesLive] = useState(false);
  const [myDogs, setMyDogs] = useState<DogProfile[]>([]);
  const [pickupAddr, setPickupAddr] = useState<Addr | null>(null);
  const [dogIdx, setDogIdx] = useState(0);

  // 코스가 km을 따른다 (2026-07-28 결정) — 가격·정산의 진실은 km. km 변경 시 최근접 실코스 자동 선택,
  // 수동으로 다른 코스를 고르면 존중하되 불일치를 배지로 정직하게 표기 (find-now와 동일 원칙)
  const pickRouteForKm = (target: number) => {
    if (!routesLive || routes.length === 0) return;
    let best = routes[0];
    routes.forEach((r) => { if (Math.abs(r.km - target) < Math.abs(best.km - target)) best = r; });
    setRouteId(best.id);
  };
  const myDog = myDogs[dogIdx] ?? null;

  // 코스 페이지 '이 코스로 예약하기' 진입 — 코스를 프리셀렉트하고 km 칩을 코스 거리에 맞춘다
  const { routeId: paramRouteId } = useLocalSearchParams<{ routeId?: string }>();
  const paramApplied = useRef(false);
  useEffect(() => {
    if (!paramRouteId || paramApplied.current) return;
    const r = routes.find((x) => x.id === paramRouteId);
    if (!r) return; // 코스 목록 로드 전 — 다음 렌더에서 재시도
    paramApplied.current = true;
    setRouteId(r.id);
    setKm(DISTANCES.reduce((a, b) => (Math.abs(b - r.km) < Math.abs(a - r.km) ? b : a)));
  }, [paramRouteId, routes]);

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
    fetchAddresses().then((l) => setPickupAddr(l.find((a) => a.isDefault) ?? l[0] ?? null)).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const [slotSheet, setSlotSheet] = useState(false);
  const [recurringOn, setRecurringOn] = useState(false); // 매주 반복 (0026)
  const [holdVisible, setHoldVisible] = useState(false);
  const nominatedName = useRef<string | null>(null); // 결제 중 지명 성공 시 러너 이름
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
    // 실소요 = km×8 + 25분 버퍼 (서버 hold와 동일 — 60분 고정은 7km+에서 러너 가용시간을 넘겼다)
    const durMin = km * 8 + 25; // draft.km은 pay() 전까지 lag — 화면 상태값 사용
    return prefRules.some((r) => r.weekday === wd && r.startMin <= min && r.endMin >= min + durMin);
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
    haptic('medium');
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
        address_id: pickupAddr?.id,
        scheduled_at: draft.scheduledAtIso!, // pay()에서 선택 강제됨 — +3h 폴백 은퇴
        km,
        pace_label: pace,
        addons,
      });
      await confirmPayment(res.booking_id); // 결제 성공 시뮬레이션 → matching
      draft.bookingId = res.booking_id;
      // 매주 반복 (0026) — 시리즈 생성 실패가 이번 예약을 막지 않는다 (예약은 이미 성립)
      if (recurringOn) {
        try {
          await createRecurringSeries(res.booking_id);
        } catch (e) {
          console.warn('[pay] series:', (e as Error)?.message);
          Alert.alert('반복 설정 실패', '이번 예약은 완료됐지만 매주 반복 설정에 실패했어요 — 다음 예약 때 다시 켜주세요');
        }
      }
      // 지명 예약: 결제 직후 여기서 바로 지명 전송 — 러너 선택 화면을 아예 거치지 않는다
      // (매칭 화면에 위임하던 방식은 실패 시 조용히 선택 화면에 좌초, 2026-07-23)
      if (draft.preferredRunnerId) {
        try {
          await requestRunner(res.booking_id, draft.preferredRunnerId);
          nominatedName.current = draft.preferredRunnerName ?? '선택한';
          draft.preferredRunnerId = null;
          draft.preferredRunnerName = null;
        } catch (e) {
          console.warn('[pay] nominate:', (e as Error)?.message); // 실패 → 매칭 화면 폴백 (preferred 유지)
        }
      }
      setHoldLive(true);
    } catch (e) {
      // 실패는 실패로 — 데모 폴백 은퇴 (목업 김민준 화면이 실패를 숨기던 함정, 2026-07-23)
      draft.bookingId = null;
      setHoldVisible(false);
      Alert.alert('예약 실패', (e as Error).message ?? '잠시 후 다시 시도해주세요');
    }
  };

  // slot-hold: 서버 홀드가 확보된 경우에만 다음 화면으로 (실패는 pay()가 Alert로 처리)
  useEffect(() => {
    if (!holdVisible) return;
    const tick = setInterval(() => setHoldSec((v) => v - 1), 1000);
    return () => clearInterval(tick);
  }, [holdVisible]);

  useEffect(() => {
    if (!holdVisible || holdLive !== true) return;
    const go = setTimeout(() => {
      setHoldVisible(false);
      if (nominatedName.current) {
        // 지명 완료 — 러너 선택 화면 건너뛰고 내 일정에서 대기
        Alert.alert('지명 요청 전송', `${nominatedName.current} 러너에게 우선 요청을 보냈어요.\n수락하면 알림으로 알려드릴게요.`);
        nominatedName.current = null;
        router.replace('/owner/schedule');
        return;
      }
      router.push('/owner/matching');
    }, 1400);
    return () => clearTimeout(go);
  }, [holdVisible, holdLive]);

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 190 }}>
        {/* header */}
        <Row style={{ gap: 12 }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <View style={{ flex: 1 }}>
            <Text style={[{ fontSize: 27.5, fontWeight: '900', color: FOREST }, df]}>러닝 요청</Text>
          </View>
          <View style={s.livePill}>
            <Text style={{ fontSize: 12.5, fontWeight: '800', color: '#4a6d1f' }}>
              {preferred ? `★ ${draft.preferredRunnerName ?? '지명'} 러너` : '● 안심 결제'}
            </Text>
          </View>
        </Row>
        <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 6 }}>
          고르는 대로 아래 티켓이 완성돼요 🎫
        </Text>

        {/* 누가 · 어디서 — 한 카드 (모던 목업: 티켓형 정보 블록) */}
        <SectionHead glyph="◉" title="누가 · 어디서" />
        <View style={s.card}>
          <Pressable
            onPress={() => router.push('/owner/dog')}
            style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}
          >
            <Avatar url={myDog?.photoUrl} char={(myDog?.name ?? dog.name)[0]} bg="#c9a86e" size={42} />
            <Text style={{ flex: 1, fontSize: 16.5, fontWeight: '800', color: FOREST }}>
              <Text style={{ fontWeight: '900' }}>{myDog?.name ?? dog.name}</Text>
              {'  ·  '}{myDog?.breed ?? dog.breed}{'  ·  '}{myDog?.weightKg ?? dog.weightKg}kg
            </Text>
            <Text style={{ fontSize: 13, fontWeight: '800', color: '#5a7a3c' }}>프로필 ›</Text>
          </Pressable>
          <View style={{ height: 1, backgroundColor: '#DCD6C4', marginVertical: 13 }} />
          <Pressable
            onPress={() => router.push('/owner/addresses')}
            style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}
          >
            <View style={s.addrIcon}><Text style={{ fontSize: 17, color: '#5a7a3c' }}>➤</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }} numberOfLines={1}>
                {pickupAddr ? pickupAddr.label : '픽업 주소를 등록해주세요'}
              </Text>
              <Text style={{ fontSize: 14.5, color: colors.dim, marginTop: 2 }} numberOfLines={1}>
                {pickupAddr ? pickupAddr.addr : '첫 주소가 기본 픽업이 돼요'}
              </Text>
            </View>
            <Text style={{ fontSize: 15, fontWeight: '800', color: colors.dim }}>변경 ›</Text>
          </Pressable>
        </View>
        {/* 다견 선택 + 추가 */}
        <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
          {myDogs.length > 1 && myDogs.map((d, i) => (
            <Pressable key={d.id} onPress={() => setDogIdx(i)} style={[s.dogSelChip, dogIdx === i && { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: dogIdx === i ? '#fff' : '#3d453d' }}>{d.name}</Text>
            </Pressable>
          ))}
          <Pressable
            style={s.dogSelChip}
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
            <Text style={{ fontSize: 14, fontWeight: '800', color: '#3d453d' }}>＋ 반려견 추가</Text>
          </Pressable>
        </Row>

        {/* distance */}
        <SectionHead glyph="⌖" title="거리" />
        <Row style={{ justifyContent: 'space-around', alignItems: 'flex-end', marginTop: 2 }}>
          {DISTANCES.map((d) => {
            const optPrice = pricing.baseFare + d * pricing.perKm;
            const sel = km === d;
            return (
              <Pressable key={d} onPress={() => { setKm(d); pickRouteForKm(d); }} style={{ alignItems: 'center', paddingHorizontal: 8 }}>
                <Text style={{ fontSize: sel ? 46 : 36, fontWeight: '900', color: sel ? colors.tang : '#c9c5b8', lineHeight: sel ? 50 : 42 }}>
                  {d}<Text style={{ fontSize: sel ? 19 : 15 }}>km</Text>
                </Text>
                <View style={{ width: 36, height: 5, borderRadius: 3, backgroundColor: sel ? colors.volt : 'transparent', marginTop: 3 }} />
                <Text style={{ fontSize: 14.5, fontWeight: sel ? '900' : '600', color: sel ? FOREST : '#a09c8e', marginTop: 5 }}>
                  {optPrice.toLocaleString()}원
                </Text>
              </Pressable>
            );
          })}
        </Row>

        {/* pace */}
        <SectionHead glyph="⇢" title="페이스" />
        <Row style={{ gap: 10 }}>
          {PACES.map((pc) => {
            const sel = pace === pc;
            return (
              <Pressable key={pc} onPress={() => setPace(pc)} style={[s.paceChip, sel && s.paceChipSel]}>
                <Row style={{ gap: 2.5, alignItems: 'flex-end', marginBottom: 7 }}>
                  {[7, 10, 13].map((h, bi) => (
                    <View key={bi} style={{
                      width: 4.5, height: h, borderRadius: 2,
                      backgroundColor: sel ? (bi < 2 ? colors.volt : '#3a4a3e') : (bi < 2 ? '#a9c47e' : '#dcd9ca'),
                    }} />
                  ))}
                </Row>
                <Text style={{ fontSize: 15.5, fontWeight: '900', color: sel ? '#fff' : FOREST }}>{pc}</Text>
              </Pressable>
            );
          })}
        </Row>

        {/* ---------- 안심 코스 carousel (live from Supabase, mock fallback) ---------- */}
        <SectionHead
          glyph="✓"
          title="코스 선택"
          sub={routesLive ? '· 실시간 코스 정보' : '· 모든 코스는 도그스하이가 직접 점검해요'}
        />
        {/* 지리 고지 — 코스와 픽업지는 별개라는 걸 예약 전에 정직하게 (좌표 모델링 전 v1) */}
        <Text style={{ fontSize: 12, color: '#82887a', marginBottom: 10 }}>
          픽업 후 코스까지는 러너가 아이와 함께 이동해요
        </Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingRight: 12 }}>
          {routes.map((r) => {
            const sel = routeId === r.id;
            const isBest = r.id === bestRoute.id;
            return (
              <Pressable
                key={r.id}
                onPress={() => setRouteId(r.id)}
                style={[s.routeCard, isBest && { backgroundColor: '#DDF0A6', borderColor: '#c3dd76' }, sel && { borderColor: colors.volt, borderWidth: 2 }]}
              >
                <View style={[s.routeTab, !isBest && { backgroundColor: FOREST }]}>
                  <Text style={{ fontSize: 11.5, fontWeight: '900', color: isBest ? colors.volt : '#fff' }}>
                    {isBest ? '★ 추천 코스' : '안심 코스'}
                  </Text>
                </View>
                <View style={s.fitPillR}>
                  <Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>적합도 {r.fit}%</Text>
                </View>

                <Row style={{ gap: 5, marginTop: 22 }}>
                  <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }} numberOfLines={1}>{r.name}</Text>
                  <View style={s.certBadge}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                </Row>
                <Text style={{ fontSize: 14, color: '#49524a', marginTop: 2 }}>
                  {/* checkedAt이 이미 '7.15 점검' 형태 — '점검' 재접미 금지 (점검 점검 버그) */}
                  {r.area} · {r.km}km · {r.terrain} · {r.checkedAt}
                </Text>
                {r.km !== km && (
                  <View style={s.kmMismatch}>
                    <Text style={{ fontSize: 10.5, fontWeight: '800', color: '#9D580A' }}>
                      선택 거리와 달라요 — 요금·기록은 {km}km 기준
                    </Text>
                  </View>
                )}

                <View style={s.routeMap}>
                  <HeatTrace points={r.trace} width={208} height={92} />
                  {/* 코스 미리보기 — 트레이스·설명·점검일·우리 기록 (탭=선택은 카드가, 미리보기는 이 칩만) */}
                  <Pressable onPress={() => router.push(`/course/${r.id}`)} style={s.previewChip} hitSlop={6}>
                    <Text style={{ fontSize: 11, fontWeight: '900', color: FOREST }}>미리보기 ›</Text>
                  </Pressable>
                </View>

                <Row style={{ gap: 4, marginTop: 9, flexWrap: 'wrap' }}>
                  {r.tags.map((tag) => (
                    <View key={tag} style={[s.routeTag, isBest && { backgroundColor: '#ffffffcc' }]}>
                      <Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>{tag}</Text>
                    </View>
                  ))}
                </Row>
                <Text style={{ fontSize: 14, color: '#49524a', marginTop: 8, lineHeight: 17 }} numberOfLines={2}>{r.desc}</Text>
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
                  <View style={s.addonIcon}><Text style={{ fontSize: 16, color: '#5a7a3c' }}>{ADDON_GLYPHS[k]}</Text></View>
                  <View style={[s.checkCircle, sel && { backgroundColor: colors.volt, borderColor: colors.volt }]}>
                    {sel && <Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>✓</Text>}
                  </View>
                </Row>
                <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST, marginTop: 10 }}>{a.label}</Text>
                <Text style={{ fontSize: 14.5, color: '#75806f', marginTop: 2 }}>{a.desc}</Text>
                <Text style={{ fontSize: 15, fontWeight: '900', color: '#5a7a3c', marginTop: 8 }}>+{a.price.toLocaleString()}원</Text>
              </Pressable>
            );
          })}
        </View>

        {/* 매주 반복 (0026) — 구독형 동의: 가격·주기·해지 자유를 토글 안에 전부 명시 (다크패턴 금지) */}
        <Pressable
          onPress={() => setRecurringOn((v) => !v)}
          style={[s.recurRow, recurringOn && { borderColor: '#a9c47e', backgroundColor: '#fbfdf4' }]}
        >
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>⟳ 매주 반복</Text>
            <Text style={{ fontSize: 14.5, color: '#75806f', marginTop: 3, lineHeight: 18 }}>
              매주 같은 요일·시간에 자동 예약 · 회당 {fmtWon(total)} · 같은 러너 우선 · 일정 탭에서 언제든 해지
            </Text>
          </View>
          <View style={[s.checkCircle, recurringOn && { backgroundColor: colors.volt, borderColor: colors.volt }]}>
            {recurringOn && <Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>✓</Text>}
          </View>
        </Pressable>

        {/* 요금 요약 한 줄 — 총액은 아래 티켓이 보여준다 */}
        <Text style={{ fontSize: 14.5, color: '#a09c8e', textAlign: 'center', marginTop: 20 }}>
          기본 {fmtWon(pricing.baseFare)} · 거리 {fmtWon(km * pricing.perKm)}{addonSum > 0 ? ` · 옵션 ${fmtWon(addonSum)}` : ''} · 취소 수수료 없음
        </Text>
      </ScrollView>

      {/* 티켓 푸터 — 고르는 대로 완성되는 티켓 (절취선 + 노치) */}
      <View style={s.ticket}>
        <Row style={{ gap: 11, alignItems: 'center' }}>
          <Avatar url={myDog?.photoUrl} char={(myDog?.name ?? dog.name)[0]} bg="#c9a86e" size={40} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }} numberOfLines={1}>
              {myDog?.name ?? dog.name} · <Text style={{ color: colors.tang }}>{km}km</Text> · {pace}
            </Text>
            <Text style={{ fontSize: 14.5, color: '#b8c4ae', marginTop: 2 }} numberOfLines={1}>
              {routes.find((r) => r.id === routeId)?.name ?? '코스 선택'}
            </Text>
          </View>
          <Pressable onPress={() => setSlotSheet(true)} style={s.timeChip}>
            <Text style={{ fontSize: 13, fontWeight: '900', color: '#0F1D13' }} numberOfLines={1}>
              {draft.scheduledAtIso ? timeLabel : '시간 선택 ›'}
            </Text>
          </Pressable>
        </Row>

        {/* 절취선 */}
        <View style={{ marginVertical: 13, height: 1 }}>
          <View style={s.tickDash} />
          <View style={[s.notch, { left: -28 }]} />
          <View style={[s.notch, { right: -28 }]} />
        </View>

        <Row style={{ alignItems: 'center' }}>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 14, color: '#8fa093' }}>총 결제 금액</Text>
            <Text style={{ fontSize: 28.5, fontWeight: '900', color: '#fff', marginTop: 1 }}>
              {fmtWon(total)}<Text style={{ fontSize: 15, color: '#b8c4ae' }}> 원</Text>
            </Text>
          </View>
          <Pressable onPress={pay} style={s.payBtn}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>
              {draft.scheduledAtIso ? '결제하기 ›' : '시간부터 ›'}
            </Text>
          </Pressable>
        </Row>
      </View>

      {/* ---------- time-slot bottom sheet ---------- */}
      <Modal visible={slotSheet} transparent animationType="slide" onRequestClose={() => setSlotSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setSlotSheet(false)} />
        <View style={s.sheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 19.5, fontWeight: '900', color: FOREST }}>언제 달릴까요?</Text>
          {preferred && (
            <Text style={{ fontSize: 12.5, color: '#5a7a3c', marginTop: 4, fontWeight: '700' }}>
              ★ {draft.preferredRunnerName ?? '지명'} 러너의 가능 시간만 선택할 수 있어요
            </Text>
          )}

          <Row style={{ gap: 8, marginTop: 12 }}>
            <View style={[s.methodChip, { backgroundColor: FOREST }]}>
              <Text style={{ fontSize: 13, fontWeight: '800', color: '#fff' }}>날짜·시간 선택</Text>
            </View>
            <Pressable style={s.methodChip} onPress={pickEarliest}>
              <Text style={{ fontSize: 13, fontWeight: '700', color: '#3d453d' }}>가장 빠른 시간</Text>
            </Pressable>
            <View style={[s.methodChip, { opacity: 0.45 }]}>
              <Text style={{ fontSize: 13, fontWeight: '700', color: '#3d453d' }}>반복 예약 (준비 중)</Text>
            </View>
          </Row>

          {/* date strip */}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }} contentContainerStyle={{ gap: 8 }}>
            {DATES.map((d, i) => (
              <Pressable key={d.date.toISOString()} onPress={() => setDateIdx(i)} style={[s.dateChip, dateIdx === i && { backgroundColor: FOREST }]}>
                <Text style={{ fontSize: 13, color: dateIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
                <Text style={{ fontSize: 18.5, fontWeight: '900', color: dateIdx === i ? '#fff' : FOREST }}>{d.d}</Text>
                {d.label && <Text style={{ fontSize: 10, fontWeight: '700', color: dateIdx === i ? colors.volt : '#5a7a3c' }}>{d.label}</Text>}
              </Pressable>
            ))}
          </ScrollView>

          {/* slot groups — 지명 러너면 가용시간 밖 비활성, 과거/2시간 내 비활성 */}
          <ScrollView style={{ marginTop: 6, maxHeight: 300 }}>
            {SLOT_GROUPS.map((g) => (
              <View key={g.name} style={{ marginTop: 12 }}>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#49524a' }}>{g.name}</Text>
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
                        <Text style={{ fontSize: 16, fontWeight: '800', color: FOREST }}>{t}</Text>
                        <Text style={{ fontSize: 12.5, color: ok ? '#5a7a3c' : colors.dim, marginTop: 2 }}>
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
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>슬롯을 잡아두고 있어요</Text>
            <Text style={{ fontSize: 34.5, fontWeight: '900', color: '#5a7a3c', marginTop: 10 }}>
              {Math.floor(holdSec / 60)}:{String(holdSec % 60).padStart(2, '0')}
            </Text>
            <Text style={{ fontSize: 15, color: colors.dim, marginTop: 8, textAlign: 'center' }}>
              {timeLabel} 슬롯이 결제 완료까지{'\n'}다른 보호자에게 보이지 않아요
            </Text>
            <Text style={{ fontSize: 13, fontWeight: '800', marginTop: 10, color: holdLive === true ? '#4a6d1f' : colors.dim }}>
              {holdLive === true ? '● 서버 홀드 확보 — 예약이 생성됐어요' : '서버 연결 중...'}
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
        <Text style={{ fontSize: 15, color: '#5a7a3c' }}>{glyph}</Text>
        <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>{title}</Text>
        {sub && <Text style={{ fontSize: 14, color: colors.dim, alignSelf: 'flex-end', flex: 1 }} numberOfLines={1}>{sub}</Text>}
      </Row>
      {side && (
        <View style={s.sideBtn}><Text style={{ fontSize: 12.5, fontWeight: '700', color: '#3d453d' }}>{side}</Text></View>
      )}
    </Row>
  );
}

function FeeRow({ label, value }: { label: string; value: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
      <Text style={{ fontSize: 15, color: '#75806f' }}>{label}</Text>
      <Text style={{ fontSize: 15, color: '#3d453d', fontWeight: '600' }}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  kmMismatch: { backgroundColor: '#FDE8D0', borderRadius: 8, paddingVertical: 4, paddingHorizontal: 8, marginTop: 6, alignSelf: 'flex-start' },
  previewChip: { position: 'absolute', right: 7, bottom: 7, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  livePill: { backgroundColor: '#f0f6e2', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12, borderWidth: 1, borderColor: '#dde8c4', alignSelf: 'center' },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 16, borderWidth: 1, borderColor: '#DCD6C4' },
  rowCard: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 15 },
  addDog: { width: 64, borderRadius: 18, backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', alignItems: 'center', justifyContent: 'center' },
  dogSelChip: { backgroundColor: '#fff', borderRadius: 99, borderWidth: 1.3, borderColor: '#dcd9cc', paddingVertical: 8, paddingHorizontal: 15 },
  bigChip: { flex: 1, backgroundColor: '#fff', borderRadius: 18, paddingVertical: 16, alignItems: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  bigChipSel: { backgroundColor: FOREST, borderWidth: 2, borderColor: colors.volt },
  bigChipText: { fontSize: 18.5, fontWeight: '800', color: '#3d453d' },
  bolt: {
    position: 'absolute', top: -9, alignSelf: 'center', width: 18, height: 18, borderRadius: 9,
    backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center', zIndex: 2,
  },
  sideBtn: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 6, paddingHorizontal: 11, borderWidth: 1, borderColor: '#DCD6C4' },
  // route carousel
  routeCard: { width: 240, backgroundColor: '#fff', borderRadius: 22, padding: 14, paddingTop: 12, borderWidth: 1.5, borderColor: '#DCD6C4', overflow: 'hidden' },
  routeTab: {
    position: 'absolute', top: 0, left: 0, backgroundColor: '#0F1D13',
    borderTopLeftRadius: 20, borderBottomRightRadius: 14, paddingVertical: 6, paddingHorizontal: 12,
  },
  fitPillR: {
    position: 'absolute', top: 9, right: 10, backgroundColor: colors.volt,
    borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9,
  },
  paceChip: {
    flex: 1, backgroundColor: '#fff', borderRadius: 18, paddingVertical: 14,
    alignItems: 'center', borderWidth: 1.5, borderColor: '#DCD6C4',
  },
  paceChipSel: { backgroundColor: FOREST, borderWidth: 2, borderColor: colors.volt },
  addrIcon: {
    width: 34, height: 34, borderRadius: 11, backgroundColor: '#EDE8DA',
    alignItems: 'center', justifyContent: 'center',
  },
  certBadge: {
    width: 15, height: 15, borderRadius: 8, backgroundColor: '#3d8fd4',
    alignItems: 'center', justifyContent: 'center', alignSelf: 'center',
  },
  bestPill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'flex-start' },
  routeMap: { marginTop: 10, borderRadius: 12, backgroundColor: '#0e150f', padding: 0, overflow: 'hidden', paddingVertical: 4, paddingHorizontal: 2 },
  routeTag: { backgroundColor: '#eef4e0', borderRadius: 7, paddingVertical: 3, paddingHorizontal: 6 },
  addon: { width: '47.8%', backgroundColor: '#fff', borderRadius: 18, padding: 13, borderWidth: 1.5, borderColor: '#DCD6C4' },
  recurRow: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: '#fff', borderRadius: 18, padding: 14, borderWidth: 1.5, borderColor: '#DCD6C4', marginTop: 12 },
  addonIcon: { width: 34, height: 34, borderRadius: 10, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  checkCircle: { width: 22, height: 22, borderRadius: 11, borderWidth: 1.5, borderColor: '#dcd9cc', alignItems: 'center', justifyContent: 'center' },
  ticket: {
    // 세미 투명 (86%) — 뒤로 스크롤 콘텐츠가 은은히 비치는 플로팅 티켓 (Sean, 2026-07-28)
    position: 'absolute', left: 10, right: 10, bottom: 26, backgroundColor: '#0F1D13DC',
    borderRadius: 20, padding: 17, overflow: 'hidden',
    shadowColor: '#0F1D13', shadowOpacity: 0.35, shadowRadius: 10, shadowOffset: { width: 0, height: 5 },
  },
  tickDash: { height: 1, borderWidth: 0.7, borderColor: '#3a4a3e', borderStyle: 'dashed', borderRadius: 1 },
  notch: {
    position: 'absolute', top: -8, width: 16, height: 16, borderRadius: 8, backgroundColor: colors.cream,
  },
  timeChip: {
    backgroundColor: '#f2ead8', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13,
    maxWidth: 128,
  },
  payBtn: { backgroundColor: colors.volt, borderRadius: 16, paddingVertical: 14, paddingHorizontal: 12 },
  // slot sheet
  sheetBackdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 16, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#DCD6C4', marginBottom: 14 },
  methodChip: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#DCD6C4' },
  dateChip: { width: 52, borderRadius: 14, backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', alignItems: 'center', paddingVertical: 9, gap: 1 },
  slot: { flex: 1, backgroundColor: '#fff', borderRadius: 13, borderWidth: 1, borderColor: '#DCD6C4', alignItems: 'center', paddingVertical: 11 },
  hotPill: { position: 'absolute', top: -7, right: 6, backgroundColor: '#fde8e3', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 6 },
  // hold modal
  holdBackdrop: { flex: 1, backgroundColor: '#00000066', alignItems: 'center', justifyContent: 'center' },
  holdCard: { width: 270, backgroundColor: '#fff', borderRadius: 22, padding: 18, alignItems: 'center' },
});
