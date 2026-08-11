import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Image, Modal, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import Svg, { Defs, LinearGradient as SvgLinear, Rect, Stop } from 'react-native-svg';
import { Icon, Row } from '../../src/components/ui';
import {
  claimClubHost, ClubOverview, ClubSeries, createClubSession, DelegationBoard, fetchClubHostStats, fetchClubMyStats,
  fetchClubOverview, fetchClubSeries, fetchDelegationBoard, fetchRoutes, pauseClubSeries, registerClubInterest, startClubSeries, uploadClubPhoto,
} from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { AckStack } from '../../src/components/club-acks';
import { ClubCta, ClubTag, Ticket } from '../../src/components/club-ui';
import { lilac, lilacRadius, lilacShadow, paper } from '../../src/theme';

// 하이클럽 홈 — 변형 D (Sean 확정: 3 티켓-퍼스트 골격 × 2 에디토리얼 마스트헤드, home-repaint lab).
// 구조: 초박 내비 → 홀로 엣지 사진 스트립(3) → 거대 활자 마스트헤드(2) → ack → 보딩패스 티켓 + 두 문(3)
//       → 시리즈 리듬(+호스트 해지) → 출석·호스트 신뢰 타일 → 호스트 세션 열기 → 콜로폰.
// opus 심사 반영: 코랄 문 서브라인 = 흰 88%(대비) · cream-tint 태그 금지 · 새 폰트 미도입(Oswald 재사용).
// collecting = 관심 수집 (유령 클럽 금지 — 호스트 클레임 전엔 참여 UI 없음).

const L = lilac;

// 세션 개설 프리셋 — 다음 발생 시각 계산 (S1: 프리셋 3종, 커스텀은 P-B)
const nextSlot = (dow: number, hour: number): Date => {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  let add = (dow - d.getDay() + 7) % 7;
  if (add === 0 && d.getTime() < Date.now() + 2 * 3600_000) add = 7;
  d.setDate(d.getDate() + add);
  return d;
};
const SLOT_PRESETS = [
  { label: '토 09:00', get: () => nextSlot(6, 9) },
  { label: '일 09:00', get: () => nextSlot(0, 9) },
  { label: '내일 07:00', get: () => { const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(7, 0, 0, 0); return d; } },
];

// [감사 P2 선례] 티켓 시각 파트 — 기기 로컬이 아니라 Asia/Seoul 고정 (Intl 실패 시 로컬 폴백)
const DAYS_KO = ['일', '월', '화', '수', '목', '금', '토'];
const DAYS_EN = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const ticketParts = (iso: string) => {
  const d = new Date(iso);
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Seoul', month: 'numeric', day: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: false, weekday: 'short',
    }).formatToParts(d);
    const g = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
    const wk = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(g('weekday'));
    const i = wk >= 0 ? wk : d.getDay();
    const hh = g('hour') === '24' ? '00' : g('hour');
    return { day: DAYS_KO[i], hhmm: `${hh}:${g('minute')}`, code: `${Number(g('month'))}.${Number(g('day'))} ${DAYS_EN[i]}` };
  } catch {
    return {
      day: DAYS_KO[d.getDay()],
      hhmm: `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`,
      code: `${d.getMonth() + 1}.${d.getDate()} ${DAYS_EN[d.getDay()]}`,
    };
  }
};
const kstYmd = (d: Date): string => {
  try { return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(d); }
  catch { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; }
};
const ddayLabel = (iso: string): string => {
  const n = Math.round((Date.parse(kstYmd(new Date(iso))) - Date.parse(kstYmd(new Date()))) / 86400_000);
  return n <= 0 ? '오늘' : `D-${n}`;
};

// 홀로 엣지 스트립 (포일 예산: 모노그램 + 티켓/스트립 엣지만)
const HOLO_STOPS = [['0', '#CFC4FF'], ['0.22', '#FFD9CB'], ['0.45', '#F3E9C6'], ['0.65', '#CDEBDD'], ['1', '#CFE0FF']] as const;
function HoloEdge({ id, top }: { id: string; top?: boolean }) {
  return (
    <Svg width="100%" height={3} style={[{ position: 'absolute', left: 0, right: 0, zIndex: 3 }, top ? { top: 0 } : { bottom: 0 }]}>
      <Defs>
        <SvgLinear id={id} x1="0" y1="0" x2="1" y2="0">
          {HOLO_STOPS.map(([o, c]) => <Stop key={o} offset={o} stopColor={c} />)}
        </SvgLinear>
      </Defs>
      <Rect x="0" y="0" width="100%" height="3" fill={`url(#${id})`} />
    </Svg>
  );
}

export default function ClubPage() {
  const df = useDisplayFont();
  const nf = useNumFont();
  const [club, setClub] = useState<ClubOverview | null>(null);
  const [myStats, setMyStats] = useState<{ attended: number; streak: number } | null>(null);
  const [hostStats, setHostStats] = useState<{ sessions: number; totalTeams: number; returning: number } | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  // [홈 = 루트] 내 진행 스레드 감지 — 보드 한 번으로 세 역할 전부 (dogs.isMine=보호자 위탁 · me.committed=러너 · isHost)
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  // [honesty 2026-08-11] overview 로드 실패가 무지 셸(빈 마스트헤드)로 침묵하던 것 —
  // 실패는 스트립으로 말하고 재시도 문을 연다. 서브 집계(myStats 등)는 장식이라 soft 유지.
  const [clubErr, setClubErr] = useState(false);
  // [감사 H3 2026-08-11] fetchClubOverview는 '로딩 중'과 '이 동네에 클럽이 없다'를 **똑같이 null**로
  // 돌려준다. 그래서 마스트헤드가 두 경우 모두 하이클럽 / DISTRICT — / HOST 모집 중을 그렸다 —
  // 없는 클럽의 이름과 '모집 중'이라는 진행 상태를 지어낸 것이다 (정직 법: 로딩 ≠ 빈 값 ≠ 실패).
  // 한 번이라도 응답을 받았는지를 따로 들고, 세 상태를 다르게 그린다.
  const [clubLoaded, setClubLoaded] = useState(false);
  const load = () => {
    setClubErr(false);
    return fetchClubOverview().then((c) => {
      setClub(c);
      setClubLoaded(true);
      if (c && c.status === 'active') {
        fetchClubMyStats(c.id).then(setMyStats).catch(() => {});
        fetchClubHostStats(c.id).then(setHostStats).catch(() => {});
        fetchClubSeries(c.id).then(setSeries).catch(() => {}); // ⟳ 정기 시리즈 (0035)
        if (c.nextSession) fetchDelegationBoard(c.nextSession.id).then(setBoard).catch(() => setBoard(null));
        else setBoard(null);
      }
    }).catch(() => setClubErr(true));
  };
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setRefreshing(false)); };

  // 호스트: 세션 개설 시트
  const [sheetOpen, setSheetOpen] = useState(false);
  const [slotIdx, setSlotIdx] = useState(0);
  const [meetup, setMeetup] = useState('');
  const [cap, setCap] = useState(9);
  const [busy, setBusy] = useState(false);
  const [weekly, setWeekly] = useState(false); // ⟳ 매주 반복 (0035)
  const [series, setSeries] = useState<ClubSeries[]>([]);
  // 코스 — mixed 세션은 코스 필수 (위탁 요금 = club_fare(km), 서버 route_required 게이트)
  const [routes, setRoutes] = useState<{ id: string; name: string; km: number }[]>([]);
  const [routeIdx, setRouteIdx] = useState(0);
  // [honesty 2026-08-11] routes 실패가 시트 안 영원한 '불러오는 중...'으로 굳어
  // 세션 개설을 말없이 막던 것 — 실패 상태 + 재시도로 교정.
  const [routesErr, setRoutesErr] = useState(false);
  const loadRoutes = () => {
    setRoutesErr(false);
    fetchRoutes().then((rs) => setRoutes(rs.map((r) => ({ id: r.id, name: r.name, km: r.km })))).catch(() => setRoutesErr(true));
  };
  const openSheet = () => {
    setSheetOpen(true);
    if (routes.length === 0) loadRoutes();
  };

  const createSession = async () => {
    if (!club || busy) return;
    if (!meetup.trim()) { Alert.alert('집결지를 입력해주세요', '예: 잠수교 북단 계단 앞'); return; }
    const route = routes[routeIdx];
    if (!route) { Alert.alert('코스를 선택해주세요', '위탁을 받으려면 코스(요금 기준)가 필요해요'); return; }
    setBusy(true);
    try {
      const slot = SLOT_PRESETS[slotIdx].get();
      // 클럽 불변식 = 혼합 이벤트 (모든 개에 명시적 책임자 1인) — 위탁 문이 열리려면 mixed + 코스 필수
      await createClubSession(club.id, slot.toISOString(), meetup.trim(), cap, route.id, 'mixed');
      // [감사 P1] 시리즈에 코스·포맷 미전파 → 자동 생성 세션이 전부 owner_only·무코스가 되던 것 + 실패 삼킴
      let seriesOk = true;
      if (weekly) {
        const hh = String(slot.getHours()).padStart(2, '0');
        const mm = String(slot.getMinutes()).padStart(2, '0');
        await startClubSeries(club.id, slot.getDay(), `${hh}:${mm}`, meetup.trim(), cap, route.id, 'mixed')
          .catch(() => { seriesOk = false; });
      }
      haptic('success');
      setSheetOpen(false);
      setMeetup('');
      load();
      Alert.alert('세션이 열렸어요',
        weekly
          ? seriesOk ? '다음 주부터는 매주 자동으로 열려요 ⟳' : '세션은 열렸지만 매주 반복 등록엔 실패했어요 — 다시 시도해주세요'
          : '멤버들에게 보이기 시작해요');
    } catch (e) {
      Alert.alert('세션 개설 실패', (e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const changePhoto = async () => {
    if (!club) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch { Alert.alert('개발 빌드 업데이트 필요'); return; }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) return;
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.75, base64: true, allowsEditing: true, aspect: [16, 9] });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      await uploadClubPhoto(club.id, res.assets[0].base64);
      load();
    } catch (e) {
      Alert.alert('사진 업로드 실패', (e as Error).message);
    }
  };

  const interest = () => {
    if (!club) return;
    registerClubInterest(club.id)
      .then(() => { haptic('light'); load(); })
      .catch((e) => Alert.alert('관심 등록', (e as Error).message));
  };

  const ns = club?.nextSession;
  const left = ns ? ns.capacity - ns.rsvpCount : 0;
  const tp = ns ? ticketParts(ns.scheduledAt) : null;
  // 내 스레드 — 문은 내 상태를 알고 그려진다 (보호자: 위탁 진행 · 러너: 커밋 · 호스트: 콘솔)
  const myDogs = board?.dogs.filter((d) => d.isMine && d.approval !== 'rejected' && d.approval !== 'withdrawn') ?? [];
  const iRun = !!board?.me.committed;
  // 티켓 팩트 행 — 있는 사실만 그린다 (0051 미도착 구 서버면 코스 팩트 생략)
  const facts: { k: string; v: string; unit?: string; num?: boolean }[] = [];
  if (ns?.routeKm != null) facts.push({ k: 'COURSE', v: String(ns.routeKm), unit: 'km', num: true });
  if (club?.hostName) facts.push({ k: 'HOST', v: club.hostName });
  if (club && club.status === 'active') facts.push({ k: 'CREW', v: String(club.memberCount), unit: '멤버', num: true });

  // [리밴프] 라일락 캔버스 → 페이퍼 흰 캔버스 (§2: 틴티드 캔버스 없음). 이 화면은 킷의
  // DawnCanvas를 쓰지 않고 자기 배경을 칠하므로 여기서 따로 바꾼다. 새벽빛 블룸도 함께 은퇴 —
  // 블룸은 라일락 캔버스 위에서만 성립하고, 흰 종이 위에서는 얼룩으로 읽힌다.
  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <Svg width="100%" height={0} style={StyleSheet.absoluteFill} pointerEvents="none">
        <Defs>
          <SvgLinear id="homeDawn" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor="#6C5CE7" stopOpacity="0.07" />
            <Stop offset="1" stopColor="#6C5CE7" stopOpacity="0" />
          </SvgLinear>
        </Defs>
        <Rect x="0" y="0" width="100%" height="240" fill="url(#homeDawn)" />
      </Svg>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 44 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}>

        {/* ---------- ① 초박형 내비 — 클럽명은 아래 마스트헤드가 가진다 ---------- */}
        <Row style={s.nav}>
          <Pressable onPress={() => router.back()} hitSlop={8} style={s.navBtn}>
            <Text style={{ fontSize: 17, color: L.head, marginTop: -2 }}>‹</Text>
          </Pressable>
          <Text style={s.crumb}>CLUB{club ? ` · ${club.district}` : ''}</Text>
          <View style={{ width: 30 }} />
        </Row>

        {/* 라우드-페일 스트립 — 실패는 빈 셸로 침묵하지 않는다 (재시도 동반) */}
        {clubErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>클럽 정보를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.failRetry} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: L.head }}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* ---------- ② 사진 = 홀로 엣지 배너 스트립 (변형 3) ---------- */}
        <View style={s.strip}>
          {club?.photoUrl
            ? <Image source={{ uri: club.photoUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
            : (
              <Svg width="100%" height="100%" style={StyleSheet.absoluteFill}>
                <Defs>
                  <SvgLinear id="stripFall" x1="0" y1="0" x2="1" y2="1">
                    <Stop offset="0" stopColor="#8A7BF0" /><Stop offset="0.6" stopColor="#6C5CE7" /><Stop offset="1" stopColor="#5A4BC7" />
                  </SvgLinear>
                </Defs>
                <Rect x="0" y="0" width="100%" height="100%" fill="url(#stripFall)" />
              </Svg>
            )}
          <HoloEdge id="holoTop" top />
          <HoloEdge id="holoBot" />
          {club?.isHost && (
            <Pressable onPress={changePhoto} style={s.photoBtn}>
              <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: '#fff' }}>{/* CLUB15 */}{club.photoUrl ? '사진 변경' : '클럽 사진 올리기'}</Text>
            </Pressable>
          )}
        </View>

        {/* ---------- ②-b 에디토리얼 마스트헤드 (변형 2) ---------- */}
        <View style={s.mast}>
          <Row style={{ alignItems: 'center', gap: 8 }}>
            <Text style={s.kicker}>RUNNING CLUB</Text>
            <View style={s.kickerRule} />
            <Text style={s.kicker}>DOGS HIGH</Text>
          </Row>
          <Row style={{ alignItems: 'flex-start', gap: 10, marginTop: 9 }}>
            <Text style={[s.mastTitle, df]}>
              {club ? club.name : clubErr ? '불러오지 못했어요' : clubLoaded ? '아직 클럽이 없어요' : '불러오는 중...'}
            </Text>
            {/* OFFICIAL은 실재하는 클럽의 표식이다 — 없는 클럽에 붙이면 그 자체가 거짓 주장이다 */}
            {!!club && (
              <View style={s.officialTab}>
                <Text style={s.officialTxt}>OFFICIAL</Text>
              </View>
            )}
          </Row>
          {!!club?.description && <Text style={s.mastDesc}>{club.description}</Text>}
          {!club && clubLoaded && !clubErr && (
            <Text style={s.mastDesc}>이 동네엔 아직 하이클럽이 없어요 — 관심을 등록하면 열릴 때 알려드려요</Text>
          )}
          <Row style={s.metaRow}>
            <View style={s.metaCell}>
              <Text style={s.metaK}>DISTRICT</Text>
              <Text style={s.metaV} numberOfLines={1}>{club?.district ?? '—'}</Text>
            </View>
            <View style={[s.metaCell, s.metaCellDiv]}>
              <Text style={s.metaK}>{club?.status === 'collecting' ? 'INTEREST' : 'MEMBERS'}</Text>
              <Text style={s.metaV}>
                {/* CLUB15 */}<Text style={[{ fontSize: 16, lineHeight: 20 }, nf]}>{club ? (club.status === 'collecting' ? club.interestCount : club.memberCount) : '—'}</Text>명
              </Text>
            </View>
            <View style={[s.metaCell, s.metaCellDiv]}>
              <Text style={s.metaK}>HOST</Text>
              {/* '모집 중'은 진행 중인 활동을 주장한다 — 클럽 자체가 없을 때는 참이 아니다 */}
              <Text style={s.metaV} numberOfLines={1}>{club?.hostName ?? '—'}</Text>
            </View>
          </Row>
        </View>

        <View style={{ paddingHorizontal: 12 }}>
          {/* ⑤ 크리티컬 ack — 클럽 표면 어디서든 확인 전까지 따라온다 */}
          <AckStack />

          {/* ---------- collecting: 관심 수집 (유령 클럽 금지의 UI) ---------- */}
          {club?.status === 'collecting' && (
            <View style={s.card}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: L.head }}>아직 열리기 전이에요</Text>
              <Text style={{ fontSize: 15, color: L.text, marginTop: 5, lineHeight: 21 }}>{/* CLUB15 */}
                관심 등록 {club.interestCount}명 · 인증 러너가 호스트를 맡으면 첫 세션이 열려요
              </Text>
              {club.myInterest ? (
                <View style={[s.quietState]}><Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.accent }}>{/* CLUB15 */}✓ 관심 등록됨 — 열리면 알려드릴게요</Text></View>
              ) : (
                <ClubCta label="나도 관심 있어요" onPress={interest} style={{ paddingVertical: 15 }} />
              )}
              <Pressable
                onPress={() => claimClubHost(club.id).then(() => { Alert.alert('호스트가 됐어요', '첫 세션을 열어보세요'); load(); })
                  .catch((e) => Alert.alert('호스트 클레임', (e as Error).message.includes('not_certified') ? '인증 러너만 호스트가 될 수 있어요' : (e as Error).message))}
                style={s.ghostBtn}
              >
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.text }}>{/* CLUB15 */}인증 러너예요 — 호스트 맡기</Text>
              </Pressable>
            </View>
          )}

          {/* ---------- ③ 히어로: 다음 세션 보딩패스 (변형 3 그대로) ----------
              천공 위 = 사실(팩트), 스텁 = 내 결정. 두 개의 문, 명확히 비대등:
              위탁(코랄·프라이머리) vs 직접 함께 뛰기(콰이엇). 문은 열리는 조건을 알고 그려진다 (0051). */}
          {club?.status === 'active' && (
            ns && tp ? (
              <>
              <Ticket
                notchColor={L.bg}
                top={
                  <>
                    <Row style={{ alignItems: 'center', justifyContent: 'space-between' }}>
                      <Row style={{ alignItems: 'center', gap: 6 }}>
                        <View style={s.brandGlyph}><Text style={{ fontSize: 8, color: '#fff' }}>➤</Text></View>
                        <Text style={s.brandTxt}>NEXT SESSION · BOARDING</Text>
                      </Row>
                      <Row style={{ gap: 5 }}>
                        <ClubTag label={ddayLabel(ns.scheduledAt)} tone="lilac" />
                        <ClubTag label={ns.status === 'open' ? (left > 0 ? `${left}자리` : '마감 임박') : '마감'} tone={ns.status === 'open' && left > 0 ? 'volt' : 'amber'} />
                      </Row>
                    </Row>
                    <Row style={{ alignItems: 'baseline', gap: 8, marginTop: 11 }}>
                      <Text style={[{ fontSize: 19, lineHeight: 24, color: L.accent }, df]}>{tp.day}</Text>
                      <Text style={[{ fontSize: 33, lineHeight: 40, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] }, nf]}>{tp.hhmm}</Text>
                      <Text style={s.dateCode}>{tp.code}</Text>
                    </Row>
                    {/* [CLUB15 가드] 15로 올리면 320~375dp에서 한 줄을 넘긴다 → 행을 랩 허용 + 집결지 shrink */}
                    <Row style={{ alignItems: 'center', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
                      <Icon name="MapPin" glyph="●" size={12} color={L.coral} />
                      <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: L.head, flexShrink: 1 }} numberOfLines={1}>{/* CLUB15 */}{ns.meetupPoint}</Text>
                      <Text style={{ fontSize: 15, lineHeight: 20, color: L.dim }}>{/* CLUB15 */}· {ns.rsvpCount}팀 참여 중 / 정원 {ns.capacity}</Text>
                    </Row>
                    {facts.length >= 2 && (
                      <Row style={s.factsRow}>
                        {facts.map((f, i) => (
                          <View key={f.k} style={[s.factCell, i > 0 && s.factCellDiv]}>
                            <Text style={s.factK}>{f.k}</Text>
                            <Text style={[{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: L.head }, f.num ? nf : undefined]}>
                              {/* CLUB15 */}{f.v}{f.unit ? <Text style={{ fontSize: 12, fontWeight: '500', color: L.text }}> {f.unit}</Text> : null}{/* CLUB15 단위 접미사 예외 */}
                            </Text>
                          </View>
                        ))}
                      </Row>
                    )}
                  </>
                }
                stub={
                  <>
                    {/* [director] 문 2짝 stretch 정렬 + 서브라인 2줄 허용 — 요금·조건 잘림(P2-10 트레이드) 대신 두 문 높이 동기 */}
                    <Row style={{ gap: 8, alignItems: 'stretch' }}>
                      {/* 코랄 문 — 위탁 진행 중이면 파는 문이 아니라 내 스레드의 문이 된다 */}
                      {myDogs.length > 0 ? (
                        <Pressable
                          onPress={() => router.push({ pathname: `/club/session/${ns.id}`, params: { clubName: club.name } })}
                          style={({ pressed }) => [s.door, s.doorCoral, pressed && { transform: [{ scale: 0.98 }] }]}
                        >
                          <Svg style={StyleSheet.absoluteFill}>
                            <Defs>
                              <SvgLinear id="doorG" x1="0" y1="0" x2="1" y2="1">
                                <Stop offset="0" stopColor="#F5825F" /><Stop offset="0.55" stopColor="#F0765A" /><Stop offset="1" stopColor="#E5654A" />
                              </SvgLinear>
                            </Defs>
                            <Rect x="0" y="0" width="100%" height="100%" fill="url(#doorG)" />
                          </Svg>
                          <Text style={[{ fontSize: 16, lineHeight: 21, color: '#fff' }, df]}>{/* CLUB15 */}내 위탁</Text>
                          <Text style={s.doorSubCoral} numberOfLines={2}>
                            {myDogs[0].dogName}{myDogs.length > 1 ? ` 외 ${myDogs.length - 1}` : ''}
                            {myDogs[0].ui?.primaryStage ? ` · ${myDogs[0].ui.primaryStage}` : ''} →
                          </Text>
                        </Pressable>
                      ) : ns.format !== 'owner_only' && (
                        <Pressable
                          onPress={() => router.push({ pathname: `/club/delegate/${ns.id}`, params: { clubName: club.name, when: ns.when } })}
                          style={({ pressed }) => [s.door, s.doorCoral, pressed && { transform: [{ scale: 0.98 }] }]}
                        >
                          <Svg style={StyleSheet.absoluteFill}>
                            <Defs>
                              <SvgLinear id="doorG2" x1="0" y1="0" x2="1" y2="1">
                                <Stop offset="0" stopColor="#F5825F" /><Stop offset="0.55" stopColor="#F0765A" /><Stop offset="1" stopColor="#E5654A" />
                              </SvgLinear>
                            </Defs>
                            <Rect x="0" y="0" width="100%" height="100%" fill="url(#doorG2)" />
                          </Svg>
                          <Text style={[{ fontSize: 16, lineHeight: 21, color: '#fff' }, df]}>{/* CLUB15 */}위탁하기</Text>
                          {/* [opus a11y] 서브라인 = 흰 88% (coralSoft 2.3:1 금지) */}
                          <Text style={s.doorSubCoral} numberOfLines={2}>
                            {ns.fare != null
                              ? <>{/* CLUB15 */}<Text style={[{ fontSize: 15, lineHeight: 20, color: '#fff' }, nf]}>{ns.fare.toLocaleString()}</Text>원{ns.routeKm ? ` · ${ns.routeKm}km 완주 위탁` : ' · 완주 위탁'}</>
                              : '오늘의 러닝을 맡겨요'}
                          </Text>
                        </Pressable>
                      )}
                      <Pressable
                        onPress={() => router.push({ pathname: `/club/session/${ns.id}`, params: { clubName: club.name } })}
                        style={({ pressed }) => [
                          s.door, ns.format === 'owner_only' && myDogs.length === 0 ? s.doorCoralSolid : s.doorQuiet,
                          pressed && { transform: [{ scale: 0.98 }] },
                        ]}
                      >
                        <Text style={[{ fontSize: 16, lineHeight: 21, color: ns.format === 'owner_only' && myDogs.length === 0 ? '#fff' : L.head }, df]}>
                          {/* CLUB15 */}{ns.joined || iRun ? '참여 중' : '함께 뛰기'}
                        </Text>
                        <Text style={ns.format === 'owner_only' && myDogs.length === 0 ? s.doorSubCoral : s.doorSubQuiet} numberOfLines={2}>
                          {iRun && !ns.joined ? '러너로 뛰어요 · 세션 보기 →'
                            : ns.joined ? '세션 보기 →'
                            : <><Text style={{ fontWeight: '700', color: ns.format === 'owner_only' ? '#fff' : L.accent }}>무료</Text> · 같이 새벽을 달려요</>}
                        </Text>
                      </Pressable>
                    </Row>
                    <Row style={{ alignItems: 'center', justifyContent: 'space-between', marginTop: 11 }}>
                      <Row style={{ gap: 2, height: 13, alignItems: 'stretch' }}>
                        {Array.from({ length: 26 }).map((_, i) => (
                          <View key={i} style={{ width: (ns.id.charCodeAt(i % ns.id.length) % 3) + 1, backgroundColor: L.head, opacity: 0.8 }} />
                        ))}
                      </Row>
                      <Text style={s.codeTxt}>HIGH CLUB · {tp.code.replace(/[^0-9]/g, '')}</Text>
                    </Row>
                  </>
                }
              />
              {/* 호스트 콘솔 진입 — 홈 = 루트: 운영은 콘솔에서, 문은 여기서 하나로 */}
              {club.isHost && (
                <Pressable
                  onPress={() => router.push({ pathname: `/club/console/${ns.id}`, params: { clubName: club.name } })}
                  style={({ pressed }) => [s.consoleRow, pressed && { opacity: 0.85 }]}
                >
                  <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.accent }}>{/* CLUB15 */}호스트 콘솔</Text>
                  <Text style={{ flex: 1, fontSize: 15, lineHeight: 20, color: L.dim }} numberOfLines={1}>{/* CLUB15 */}승인 · 배정 · 세션 운영</Text>
                  <Text style={{ fontSize: 13, fontWeight: '800', color: L.accent }}>→</Text>
                </Pressable>
              )}
              </>
            ) : (
              <View style={s.card}>
                <Text style={{ fontSize: 15, color: L.dim, textAlign: 'center', lineHeight: 21 }}>
                  {/* CLUB15 */}예정된 세션이 없어요{club.isHost ? '\n아래에서 새 세션을 열어보세요' : '\n호스트가 세션을 열면 여기에 떠요'}
                </Text>
              </View>
            )
          )}

          {/* ---------- ④ ⟳ 정기 시리즈 리듬 — 멤버에겐 리듬 안내, 호스트에겐 해지 ---------- */}
          {club?.status === 'active' && series.length > 0 && (
            <View style={s.rhythm}>
              <View style={s.rhythmGlyph}><Text style={{ fontSize: 14, color: L.accent }}>⟳</Text></View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '700', color: L.head }}>
                  {/* CLUB15 */}매주 {DAYS_KO[series[0].weekday]}요일 <Text style={[{ fontSize: 15, lineHeight: 20, color: L.accent }, nf]}>{series[0].time}</Text>
                </Text>
                <Text style={{ fontSize: 15, lineHeight: 20, color: L.dim, marginTop: 1.5 }} numberOfLines={1}>{/* CLUB15 */}
                  {series[0].meetupPoint ? `${series[0].meetupPoint} 집결 · ` : ''}같은 리듬으로 계속돼요
                </Text>
              </View>
              {series[0].isHost && (
                <Pressable hitSlop={6} onPress={() => {
                  Alert.alert('정기 세션 해지', '다음 주부터 자동 개설이 멈춰요.\n이미 열린 세션은 그대로예요.', [
                    { text: '유지', style: 'cancel' },
                    { text: '해지', style: 'destructive', onPress: () => pauseClubSeries(series[0].id).then(load).catch((e) => Alert.alert('해지 실패', (e as Error).message)) },
                  ]);
                }}>
                  <Text style={s.stopLink}>호스트 해지</Text>
                </Pressable>
              )}
            </View>
          )}

          {/* ---------- ⑥ 출석 스탬프 + 호스트 신뢰 타일 (실데이터 있을 때만) ---------- */}
          {club?.status === 'active' && ((myStats && myStats.attended > 0) || (hostStats && hostStats.sessions > 0)) && (
            <Row style={{ gap: 10, marginTop: 10, alignItems: 'stretch' }}>
              {myStats && myStats.attended > 0 && (
                <View style={s.tile}>
                  <Row style={{ alignItems: 'center', justifyContent: 'space-between', marginBottom: 7 }}>
                    <Text style={s.tileK}>내 출석</Text>
                    {myStats.streak >= 2 && (
                      <View style={s.streakTag}><Text style={{ fontSize: 8.5, fontWeight: '800', letterSpacing: 1, color: L.amber }}>연속 {myStats.streak}</Text></View>
                    )}
                  </Row>
                  <Text style={[{ fontSize: 23, lineHeight: 28, fontWeight: '600', color: L.head }, nf]}>
                    <Text style={{ fontSize: 14, color: L.dim }}>×</Text>{myStats.attended}
                  </Text>
                  <Row style={{ gap: 3, marginTop: 8 }}>
                    {Array.from({ length: Math.min(myStats.attended, 7) }).map((_, i) => (
                      <View key={i} style={s.stampOn}><Text style={{ fontSize: 6.5, color: '#fff', fontWeight: '800' }}>✓</Text></View>
                    ))}
                    <View style={s.stampNext} />
                  </Row>
                </View>
              )}
              {hostStats && hostStats.sessions > 0 && (
                <View style={s.tile}>
                  <Text style={[s.tileK, { marginBottom: 7 }]}>호스트 신뢰</Text>
                  {/* [sweep 2026-08-11] `Row` is alignItems:'center', so this hand-rolled stat row
                      VERTICALLY CENTERED its three cells: '총 참여 팀' wraps to two lines, making
                      that cell taller, which pushed its number above the other two and left the
                      divider hairlines ragged (three numbers at three heights — visible on device).
                      'stretch' makes every cell the tallest cell's height: numbers top-align on one
                      line and the dividers run full height. */}
                  <Row style={{ alignItems: 'stretch' }}>
                    {[[hostStats.sessions, '세션'], [hostStats.totalTeams, '총 참여 팀'], [hostStats.returning, '재방문']].map(([v, l], i) => (
                      <View key={l as string} style={[{ flex: 1, minWidth: 0 }, i > 0 && { borderLeftWidth: 1, borderLeftColor: L.hair2, paddingLeft: 8 }]}>
                        <Text style={[{ fontSize: 16, lineHeight: 20, fontWeight: '600', color: L.head }, nf]}>{v}</Text>
                        <Text style={{ fontSize: 14, lineHeight: 19, color: L.dim, marginTop: 3 }}>{/* CLUB15 */}{l}</Text>
                      </View>
                    ))}
                  </Row>
                  {!!club.hostName && (
                    <Row style={s.hostLine}>
                      <View style={s.hostDot}><Text style={{ fontSize: 7, fontWeight: '700', color: '#fff' }}>{club.hostName.slice(0, 1)}</Text></View>
                      {/* numberOfLines 1 → 2: '· N세션째 같은 자리'가 말줄임으로 잘려 문장이 사라졌다.
                          호스트 신뢰의 유일한 서술문이라 줄여 없앨 대상이 아니다. */}
                      <Text style={{ flex: 1, fontSize: 14, lineHeight: 19, fontWeight: '600', color: L.text }} numberOfLines={2}>
                        {club.hostName} <Text style={{ color: L.dim }}>· {hostStats.sessions}세션째 같은 자리</Text>
                      </Text>
                    </Row>
                  )}
                </View>
              )}
            </Row>
          )}

          {/* ---------- 호스트 도구: 세션 열기 ---------- */}
          {/* [Sean 2026-08-11] 가로 배치라 설명문이 '…열 수 있 / 어요'로 낱말 중간에서 끊기고
              CTA는 눌린 폭으로 쪼그라들었다. 세로로 쌓으면 문장은 한 줄, 버튼은 풀폭이 된다
              (§3b 프라이머리는 어차피 풀블리드에 가깝게 놓인다). */}
          {club?.isHost && (
            <View style={s.hostTool}>
              <Text style={{ fontSize: 14, color: paper.dim, lineHeight: 19 }}>호스트 전용 · 다음 회차를 미리 열 수 있어요</Text>
              <Pressable onPress={openSheet} style={({ pressed }) => [s.hostBtn, pressed && { backgroundColor: paper.actionPressed }]}>
                <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '800', color: '#fff' }}>＋ 세션 열기</Text>
              </Pressable>
            </View>
          )}

          {/* ---------- 콜로폰 ---------- */}
          <Row style={s.colophon}>
            <Text style={s.colophonTxt}>{club?.district ?? ''}</Text>
            <Text style={s.colophonTxt}>DOGS HIGH · HIGH CLUB</Text>
          </Row>
        </View>
      </ScrollView>

      {/* ---------- 세션 개설 시트 (호스트, S1 프리셋 — 라일락 재도장) ---------- */}
      <Modal visible={sheetOpen} transparent animationType="slide" onRequestClose={() => setSheetOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(28,24,55,.5)' }} onPress={() => setSheetOpen(false)} />
        <View style={s.sheet}>
          <Text style={[{ fontSize: 19, lineHeight: 24, color: L.head }, df]}>세션 열기</Text>
          <Text style={{ fontSize: 15, lineHeight: 20, color: L.dim, marginTop: 3 }}>{/* CLUB15 */}시간·집결지·정원 — 열리면 바로 멤버에게 보여요</Text>
          {/* [CLUB15 가드] 칩 라벨 15 → 320dp에서 3칩이 한 줄을 넘긴다 → 코스 행과 같은 랩 규칙 적용 */}
          <Row style={{ gap: 8, marginTop: 14, flexWrap: 'wrap' }}>
            {SLOT_PRESETS.map((p, i) => (
              <Pressable key={p.label} onPress={() => setSlotIdx(i)} style={[s.chip, slotIdx === i && s.chipOn]}>
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: slotIdx === i ? '#fff' : L.text }}>{/* CLUB15 */}{p.label}</Text>
              </Pressable>
            ))}
          </Row>
          <TextInput
            value={meetup} onChangeText={setMeetup}
            placeholder="집결지 — 예: 잠수교 북단 계단 앞" placeholderTextColor={L.dim} style={s.input}
          />
          {/* 코스 — mixed 필수 (요금 기준) */}
          <Row style={{ gap: 8, marginTop: 12, flexWrap: 'wrap', alignItems: 'center' }}>
            <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.head }}>{/* CLUB15 */}코스</Text>
            {routes.length === 0 && !routesErr && <Text style={{ fontSize: 15, lineHeight: 20, color: L.dim }}>{/* CLUB15 */}불러오는 중...</Text>}
            {routes.length === 0 && routesErr && (
              <Pressable onPress={loadRoutes} hitSlop={8} accessibilityRole="button">
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.critical }}>{/* CLUB15 */}코스를 불러오지 못했어요 — 다시 시도 ›</Text>
              </Pressable>
            )}
            {routes.map((r, i) => (
              <Pressable key={r.id} onPress={() => setRouteIdx(i)} style={[s.chip, routeIdx === i && s.chipOn]}>
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: routeIdx === i ? '#fff' : L.text }}>{/* CLUB15 */}{r.name} {r.km}km</Text>
              </Pressable>
            ))}
          </Row>
          <Row style={{ gap: 10, marginTop: 12, alignItems: 'center', flexWrap: 'wrap' }}>
            <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.head }}>{/* CLUB15 */}정원</Text>
            {[6, 9, 12].map((c) => (
              <Pressable key={c} onPress={() => setCap(c)} style={[s.chip, cap === c && s.chipOn]}>
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: cap === c ? '#fff' : L.text }}>{/* CLUB15 */}{c}팀</Text>
              </Pressable>
            ))}
          </Row>
          {/* ⟳ 매주 반복 (0035) — 다음 주부턴 크론이 같은 요일·시각으로 자동 개설 */}
          <Pressable onPress={() => setWeekly((w) => !w)} style={s.weeklyRow}>
            <View style={[s.weeklyBox, weekly && { backgroundColor: L.accent, borderColor: L.accent }]}>
              {weekly && <Text style={{ fontSize: 12, fontWeight: '900', color: '#fff' }}>✓</Text>}
            </View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.head }}>{/* CLUB15 */}⟳ 매주 반복</Text>
              <Text style={{ fontSize: 15, lineHeight: 20, color: L.dim, marginTop: 1 }}>{/* CLUB15 */}같은 요일·시각으로 매주 자동 개설 — 언제든 해지할 수 있어요</Text>
            </View>
          </Pressable>
          {/* [Sean 규칙] 여백 화면 = 큰 버튼 */}
          <ClubCta label={busy ? '여는 중...' : '세션 열기'} onPress={createSession} busy={busy} style={{ paddingVertical: 17 }} />
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  // ① 내비
  nav: { alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 54, paddingBottom: 9 },
  navBtn: {
    width: 30, height: 30, borderRadius: 7, borderWidth: 1, borderColor: L.hair, backgroundColor: L.card,
    alignItems: 'center', justifyContent: 'center', ...lilacShadow, shadowOpacity: 0.06,
  },
  crumb: { fontSize: 9, fontWeight: '700', letterSpacing: 3, color: L.dim },
  // 라우드-페일 스트립 — criticalWash 바닥 + critical 잉크 + 재시도 (community.tsx 문법)
  failStrip: { marginTop: 10, backgroundColor: paper.criticalWash, borderRadius: lilacRadius.card, padding: 13 },
  failRetry: { alignSelf: 'flex-start', marginTop: 10, minHeight: 40, justifyContent: 'center', paddingHorizontal: 14, borderWidth: 1, borderColor: L.head, borderRadius: lilacRadius.btn, backgroundColor: '#fff' },
  // ② 사진 스트립
  strip: { height: 86, overflow: 'hidden', backgroundColor: L.inset },
  photoBtn: {
    position: 'absolute', right: 10, bottom: 9, zIndex: 4,
    backgroundColor: 'rgba(24,18,44,.42)', borderWidth: 1, borderColor: 'rgba(255,255,255,.5)',
    borderRadius: 6, paddingVertical: 5, paddingHorizontal: 9,
  },
  // ②-b 마스트헤드
  mast: { paddingHorizontal: 14, paddingTop: 15 },
  kicker: { fontSize: 8, fontWeight: '700', letterSpacing: 3, color: L.dim },
  kickerRule: { flex: 1, height: 1, backgroundColor: L.hair },
  mastTitle: { flex: 1, fontSize: 40, lineHeight: 44, color: L.head, letterSpacing: -0.5 },
  officialTab: {
    width: 21, height: 74, borderWidth: 1, borderColor: L.head, borderRadius: 2,
    backgroundColor: L.card, alignItems: 'center', justifyContent: 'center', marginTop: 4,
  },
  officialTxt: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2.2, color: L.head, width: 74, textAlign: 'center', transform: [{ rotate: '90deg' }] },
  mastDesc: { fontSize: 15, lineHeight: 20, color: L.text, marginTop: 9, maxWidth: 300 }, // CLUB15
  metaRow: { marginTop: 13, borderTopWidth: 1, borderTopColor: L.hair, borderBottomWidth: 1, borderBottomColor: L.hair },
  metaCell: { flex: 1, paddingVertical: 9 },
  metaCellDiv: { borderLeftWidth: 1, borderLeftColor: L.hair2, paddingLeft: 12 },
  metaK: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2, color: L.dim, marginBottom: 3 },
  metaV: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: L.head }, // CLUB15
  // 카드 공통
  card: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 14, marginTop: 10, ...lilacShadow,
  },
  quietState: {
    backgroundColor: L.inset, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 13, marginTop: 12,
  },
  ghostBtn: {
    backgroundColor: L.card, borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.btn,
    alignItems: 'center', paddingVertical: 11, marginTop: 8,
  },
  // ③ 티켓 상단
  brandGlyph: { width: 15, height: 15, borderRadius: 4, backgroundColor: L.accent, alignItems: 'center', justifyContent: 'center' },
  brandTxt: { fontSize: 8.5, fontWeight: '700', letterSpacing: 2, color: L.head },
  dateCode: { fontSize: 9.5, fontWeight: '700', letterSpacing: 1.5, color: L.dim },
  factsRow: { marginTop: 11, borderTopWidth: 1, borderTopColor: L.hair2, paddingTop: 10 },
  factCell: { flex: 1, minWidth: 0 },
  factCellDiv: { borderLeftWidth: 1, borderLeftColor: L.hair2, paddingLeft: 11 },
  factK: { fontSize: 7.5, fontWeight: '700', letterSpacing: 1.8, color: L.dim, marginBottom: 3 },
  // 두 문 — [Sean 규칙] 여백 화면 = 큰 버튼
  door: { flex: 1, borderRadius: lilacRadius.btn, paddingVertical: 13, paddingHorizontal: 12, overflow: 'hidden' },
  doorCoral: {
    backgroundColor: L.coral, // 그라디언트 아래 베이스 — iOS 섀도 렌더 조건 (불투명 bg 필요)
    shadowColor: L.coral, shadowOpacity: 0.34, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 4,
  },
  doorCoralSolid: {
    backgroundColor: L.coral,
    shadowColor: L.coral, shadowOpacity: 0.34, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 4,
  },
  doorQuiet: { backgroundColor: L.inset, borderWidth: 1, borderColor: L.hair },
  doorSubCoral: { fontSize: 14, lineHeight: 19, color: 'rgba(255,255,255,.88)', marginTop: 4 }, // CLUB15
  doorSubQuiet: { fontSize: 14, lineHeight: 19, color: L.dim, marginTop: 4 }, // CLUB15
  codeTxt: { fontSize: 8.5, fontWeight: '700', letterSpacing: 2, color: L.dim },
  // ④ 리듬
  rhythm: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: L.card,
    borderWidth: 1, borderColor: L.hair2, borderRadius: lilacRadius.card,
    paddingVertical: 10, paddingHorizontal: 12, marginTop: 10, ...lilacShadow, shadowOpacity: 0.06,
  },
  rhythmGlyph: {
    width: 28, height: 28, borderRadius: 6, backgroundColor: L.inset,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: L.hair,
  },
  stopLink: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: L.dim, textDecorationLine: 'underline' }, // CLUB15
  consoleRow: {
    flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 8,
    backgroundColor: L.card, borderWidth: 1, borderColor: L.hair2, borderLeftWidth: 3, borderLeftColor: L.accent,
    borderRadius: lilacRadius.card, paddingVertical: 11, paddingHorizontal: 12,
    ...lilacShadow, shadowOpacity: 0.06,
  },
  // ⑥ 타일
  tile: {
    flex: 1, minWidth: 0, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    borderRadius: 0, padding: 12,
  },
  // [FLOOR14] '내 출석' · '호스트 신뢰'는 한글 라벨인데 8pt + 트래킹 1.8로 렌더됐다 —
  // 라틴 레터스페이스 키커 문법을 한글에 입힌 정확한 위반 (§3). 14로 올리고 트래킹을 걷는다.
  tileK: { fontSize: 14, lineHeight: 18, fontWeight: '800', letterSpacing: 0.2, color: paper.dim },
  streakTag: { borderWidth: 1, borderColor: L.hair, borderRadius: 5, backgroundColor: L.card, paddingVertical: 2, paddingHorizontal: 5 },
  stampOn: { width: 11, height: 11, borderRadius: 2, backgroundColor: L.accent, alignItems: 'center', justifyContent: 'center', opacity: 0.92 },
  stampNext: { width: 11, height: 11, borderRadius: 2, borderWidth: 1.2, borderColor: L.hair },
  hostLine: { alignItems: 'center', gap: 5, marginTop: 8, paddingTop: 7, borderTopWidth: 1, borderTopColor: L.hair2 },
  hostDot: {
    width: 14, height: 14, borderRadius: 7, backgroundColor: L.accent,
    alignItems: 'center', justifyContent: 'center',
  },
  // 호스트 도구
  hostTool: {
    gap: 10, marginTop: 12,
    borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0,
    paddingVertical: 13, paddingHorizontal: 13, backgroundColor: paper.canvas,
  },
  hostBtn: {
    backgroundColor: paper.action, borderRadius: 0, paddingVertical: 16, alignItems: 'center',
  },
  // 콜로폰
  colophon: { justifyContent: 'space-between', marginTop: 18, paddingTop: 11, borderTopWidth: 1, borderTopColor: L.hair },
  colophonTxt: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2.2, color: L.dim },
  // 시트
  sheet: { backgroundColor: paper.canvas, borderTopLeftRadius: 0, borderTopRightRadius: 0, padding: 18, paddingBottom: 34, borderTopWidth: 1, borderTopColor: paper.line },
  chip: {
    borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14,
    backgroundColor: L.card, borderWidth: 1.3, borderColor: L.hair,
  },
  chipOn: { backgroundColor: L.accent, borderColor: L.accent },
  input: {
    backgroundColor: L.card, borderRadius: lilacRadius.btn, borderWidth: 1, borderColor: L.hair,
    paddingVertical: 12, paddingHorizontal: 14, fontSize: 16, color: L.head, marginTop: 12, // CLUB15
  },
  weeklyRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 13 },
  weeklyBox: { width: 22, height: 22, borderRadius: 7, borderWidth: 2, borderColor: L.hair, alignItems: 'center', justifyContent: 'center', backgroundColor: L.card },
});
