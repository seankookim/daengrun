import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Image, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { MediaImage } from '../../../src/lib/media';
import { ClubCta, ClubMast, DawnCanvas, Flap, LoadGate } from '../../../src/components/club-ui';
import { fetchRunEarning, fetchRunReport, RunEarning, runPhotoAllowed, RunReport, sealStampFresh, shareRunToFeed } from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { useNumFont } from '../../../src/lib/fonts';
import { haptic } from '../../../src/lib/haptics';
import { goBackOrHome } from '../../../src/lib/nav';
import { lilac, lilacRadius, lilacShadow } from '../../../src/theme';

// O11 — 완료 영수증 (정본: flow-lab O11 + 결정 로그 "영수증 = 사진 인화")
// 포일 예산: 골드 = SETTLED 전용 (여기가 골드가 사는 유일한 집).
// 사진법: 베스트 샷이 있으면 인화(골드 실이 사진에 반쯤 걸친다), 없으면 사진 없는 종이 —
// 스톡/플레이스홀더 이미지는 없다 (사진은 콘텐츠, 월페이퍼 금지). 공유 카드 = 성장 루프.

const L = lilac;

// 티켓 폭(320dp)에 드는 적립 사유 축약 — 표시 전용이고, 그리는 행은 전부 실원장 행이다.
// 모르는 reason 은 api.ts MILE_REASON 정식 라벨로 폴백한다 (없는 사유를 지어내지 않는다).
const EARN_SHORT: Record<string, string> = {
  run_complete: '완주', poop_bonus: '응가', patch_gold: '골드 패치', patch_master: '코스 마스터',
};

const durStr = (sec: number): string =>
  `${Math.floor(sec / 60)}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceOf = (secPerKm: number): string =>
  `${Math.floor(secPerKm / 60)}'${String(Math.round(secPerKm % 60)).padStart(2, '0')}"`;

export default function ClubReceipt() {
  const df = useDisplayFont();
  const nf = useNumFont();
  const { bid, clubName } = useLocalSearchParams<{ bid: string; clubName?: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [busy, setBusy] = useState(false);
  const cardRef = useRef<View>(null);
  // 리워드 ① — 이 러닝의 하이 포인트 적립. loaded 는 '도착했다'는 사실이고 null 은 '적립 행이 없다'는
  // 사실이다 (조기 종료 러닝엔 서버가 한 줄도 안 쓴다). 둘 다 0을 그리지 않는다.
  const [earning, setEarning] = useState<RunEarning | null>(null);
  const [earningLoaded, setEarningLoaded] = useState(false);

  // [honesty 2026-08-11] 리포트 실패가 영원한 '불러오는 중...'(백·재시도 없음)이던 것 — LoadGate.
  const [reportErr, setReportErr] = useState(false);
  const load = useCallback(() => {
    if (!bid) return;
    setReportErr(false);
    fetchRunReport(bid).then(setReport).catch(() => setReportErr(true));
  }, [bid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  useEffect(() => {
    if (!bid) return;
    // 정산 원장은 불변이라 포커스마다 다시 읽지 않는다. 실패하면 loaded 를 세우지 않는다 —
    // 카드 안엔 스켈레톤·스피너를 두지 않는 게 법이라(공유 캡처), 이 줄은 그냥 없는 채로 남는다.
    setEarning(null);
    setEarningLoaded(false);
    fetchRunEarning(bid).then((e) => { setEarning(e); setEarningLoaded(true); }).catch(() => {});
  }, [bid]);

  // ---------- ② 실 스탬프 (정본: docs/labs/choreography-lab.html ②) ----------
  // 이 예약의 첫 진입에서만 도장이 내려온다. 재진입(포커스 재로드 포함)은 전부 정지값 — opacity 1 · scale 1 · -8deg.
  // [리뷰 P1] 1회 토큰을 첫 렌더(= 항상 로딩 분기)에서 태우면, 로딩 중 뒤로 나간 사용자는 그 예약의
  // 도장을 앱 세션 내내 영영 못 본다. 토큰은 '카드가 실제로 그려지는 순간'에만 태운다.
  const stamp = useRef(new Animated.Value(1)).current;  // 0 = 공중, 1 = 종이에 찍힘 (정지값)
  const ripple = useRef(new Animated.Value(0)).current; // 착지 파문 (0 = 없음, 1 = 다 퍼짐)
  const dip = useRef(new Animated.Value(0)).current;    // 종이 눌림 (캡처 대상 밖 래퍼에만)
  const [stamping, setStamping] = useState(false);      // 캡처 게이트 — 도장이 나는 동안 공유 잠금
  const [fresh, setFresh] = useState(false);
  const consumedRef = useRef(false);
  useEffect(() => {
    if (report?.run && !consumedRef.current && bid) {
      consumedRef.current = true; // 이 마운트에서 판정은 1회 (포커스 재로드가 토큰을 또 묻지 않게)
      // 판정과 같은 틱에 실을 공중으로 올린다 — 정지 상태가 한 프레임 스쳤다 사라지는 걸 최소화
      if (sealStampFresh(bid)) { stamp.setValue(0); setFresh(true); }
    }
  }, [report?.run, bid, stamp]);
  const stampable = fresh && !!report?.run; // 카드가 실제로 그려진 뒤에 찍는다
  useEffect(() => {
    if (!stampable) return;
    let alive = true; // 도장 중 이탈해도 언마운트 뒤 상태를 건드리지 않는다 (fonts.ts와 같은 문법)
    stamp.setValue(0);
    ripple.setValue(0);
    setStamping(true);
    const seq = Animated.sequence([
      Animated.delay(350), // 카드가 먼저 보이고 → 도장이 내려온다
      Animated.parallel([
        Animated.timing(stamp, { toValue: 1, duration: 340, easing: Easing.bezier(0.5, 0, 0.7, 0.35), useNativeDriver: true }),
        // 착지(≈310ms) 순간: 종이가 눌리고(200ms) 파문이 퍼진다(550ms)
        Animated.sequence([
          Animated.delay(310),
          Animated.timing(dip, { toValue: 1, duration: 70, easing: Easing.out(Easing.quad), useNativeDriver: true }),
          Animated.timing(dip, { toValue: 0, duration: 130, easing: Easing.out(Easing.quad), useNativeDriver: true }),
        ]),
        Animated.sequence([
          Animated.delay(310),
          Animated.timing(ripple, { toValue: 1, duration: 550, easing: Easing.out(Easing.quad), useNativeDriver: true }),
        ]),
      ]),
    ]);
    seq.start(() => { if (alive) setStamping(false); });
    return () => { alive = false; seq.stop(); };
  }, [stampable, stamp, ripple, dip]);

  // goBackOrHome, not back(): a receipt is a push-notification / share-sheet destination, so these
  // two dead ends are exactly where the stack is a single entry — and LoadGate's own contract is
  // that 돌아가기 is always walkable. See src/lib/nav.ts.
  if (!report) {
    return (
      <LoadGate
        mode={reportErr ? 'error' : 'loading'}
        errorLabel="영수증을 불러오지 못했어요"
        onRetry={load}
        onBack={goBackOrHome}
      />
    );
  }
  if (!report.run) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 14, color: L.dim }}>완료된 러닝만 영수증이 나와요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={goBackOrHome} style={{ alignSelf: 'stretch' }} />
        </View>
      </DawnCanvas>
    );
  }

  const run = report.run;
  const bestShot = run.photos[0] ?? null;
  const pace = run.paceSecPerKm != null ? paceOf(run.paceSecPerKm)
    : run.actualKm > 0.05 ? paceOf(run.durationSec / run.actualKm) : "-'--\"";

  // 카드 캡처 → 시스템 공유 시트 (인증샷 화면 선례 — view-shot 지연 로드, 미탑재 빌드는 정직 안내)
  const shareImage = async () => {
    if (stamping) return; // ② 도장이 나는 동안엔 캡처 금지 — 비행 중 트랜스폼이 PNG에 박힌다 (버튼도 비활성)
    try {
      const VS = require('react-native-view-shot');
      const uri = await VS.captureRef(cardRef, { format: 'png', quality: 1 });
      await Share.share({ url: uri }).catch(() => {});
    } catch {
      Alert.alert('개발 빌드 업데이트 필요', '카드 캡처(view-shot)는 새 빌드에 포함돼요');
    }
  };
  const shareFeed = async () => {
    if (busy) return;
    setBusy(true);
    try {
      // [0053 §3a/감사 11a] 미동의 견 사진 공개 차단 — 위탁 부킹이면 최신 photo_consent 게이트를 먼저 확인.
      // graceful: RPC가 없는(푸시 전) 서버면 에러가 나므로 오늘처럼 그대로 진행 (없는 함수로 막지 않는다).
      let allowed = true;
      try { allowed = await runPhotoAllowed(bid!); } catch { allowed = true; }
      if (!allowed) {
        Alert.alert('공유 불가', '이 러닝엔 사진 공개에 동의하지 않은 아이가 있어 피드 공유를 할 수 없어요');
        return;
      }
      await shareRunToFeed(bid!);
      haptic('success');
      Alert.alert('피드에 올라갔어요', '동네 피드에서 오늘의 기록을 볼 수 있어요');
    } catch (e) {
      Alert.alert('공유 실패', (e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <DawnCanvas>
      <ScrollView contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 40 }}>
        <ClubMast title="완료" sub={`${report.when}${clubName ? ` · ${clubName}` : ''}`} onBack={goBackOrHome} />

        {/* ---------- 영수증 카드 (캡처 대상) ---------- */}
        {/* ② 종이 눌림은 캡처 대상 '밖' 래퍼에만 — 찍힌 PNG에 비행 중 트랜스폼이 섞이면 안 된다 */}
        <Animated.View style={{ transform: [{ translateY: dip.interpolate({ inputRange: [0, 1], outputRange: [0, 2] }) }] }}>
          <View ref={cardRef} collapsable={false} style={s.card}>
            <View pointerEvents="none" style={s.innerFrame} />
            {/* 베스트 샷 인화 — 있으면 사진이 카드의 상단을 산다, 골드 실이 반쯤 걸친다 */}
            {bestShot && (
              <View style={s.photoWrap}>
                {/* [0064] 러닝 사진은 media 경로 — 서명 URL로 렌더 */}
                <MediaImage source={bestShot} style={s.photo} resizeMode="cover" />
              </View>
            )}
            <View style={{ alignItems: 'center', marginTop: bestShot ? -26 : 16 }}>
              <View style={s.sealStage}>
                {/* 착지 파문 — 실과 같은 62 원, 골드 테두리만 남기고 퍼지며 사라진다 */}
                <Animated.View pointerEvents="none" style={[s.sealRipple, {
                  // 0 = 아직 안 찍힘 → 투명 (내려오는 동안·재진입 시 파문은 없다. 랩의 fill-mode:none과 같은 뜻).
                  // 착지 순간 0.7에서 출발해 1.9배로 퍼지며 사라진다.
                  opacity: ripple.interpolate({ inputRange: [0, 0.0001, 1], outputRange: [0, 0.7, 0] }),
                  transform: [{ scale: ripple.interpolate({ inputRange: [0, 1], outputRange: [1, 1.9] }) }],
                }]} />
                <Animated.View style={[s.goldSeal, {
                  opacity: stamp.interpolate({ inputRange: [0, 0.55, 1], outputRange: [0, 1, 1], extrapolate: 'clamp' }),
                  transform: [
                    { scale: stamp.interpolate({ inputRange: [0, 1], outputRange: [2.6, 1] }) },
                    { rotate: stamp.interpolate({ inputRange: [0, 1], outputRange: ['-14deg', '-8deg'] }) },
                  ],
                }]}>
                  <Text style={s.goldSealTxt}>SETTLED</Text>
                </Animated.View>
              </View>
            </View>
            <View style={{ alignItems: 'center', paddingBottom: 18, paddingHorizontal: 14 }}>
              <Text style={[{ fontSize: 19, color: L.head, marginTop: 10 }, df]}>
                {report.dogName}, 오늘 <Text style={{ color: L.coral }}>{run.actualKm.toFixed(1)}km</Text>
              </Text>
              <Text style={{ fontSize: 14, color: L.dim, marginTop: 4 }}>
                {report.runnerName ? `${report.runnerName}와 · ` : ''}{pace} · {durStr(run.durationSec)}
              </Text>
              <View style={{ marginTop: 10 }}>
                <Flap state="SETTLED" />
              </View>
              {/* 수치 룰 행 */}
              <Row style={s.numRow}>
                <View style={s.numCell}>
                  <Text style={[s.numV, nf]}>{run.actualKm.toFixed(1)}<Text style={{ fontSize: 14, color: L.coral }}>km</Text></Text>
                  <Text style={s.numL}>실측 거리</Text>
                </View>
                <View style={s.numCell}>
                  <Text style={[s.numV, nf]}>{pace}</Text>
                  <Text style={s.numL}>페이스</Text>
                </View>
                <View style={[s.numCell, { borderRightWidth: 0 }]}>
                  <Text style={[s.numV, nf]}>{durStr(run.durationSec)}</Text>
                  <Text style={s.numL}>시간</Text>
                </View>
              </Row>
              {/* 하이 포인트 적립 (리워드 ①) — 원장 행이 있을 때만 그린다. 조기 종료·정산 전이면
                  fetchRunEarning 이 null 이라 이 줄 자체가 없다. 카드 안이라 스켈레톤·스피너 금지:
                  적립이 도착하기 전에 공유하면 PNG 에도 이 줄이 없는 게 정직하다 (공유 게이트는 그대로). */}
              {earningLoaded && earning && (
                <View style={s.earnLine}>
                  <Row style={{ justifyContent: 'space-between' }}>
                    <Text style={s.earnLead}>하이 포인트</Text>
                    <Text style={[s.earnV, nf]}>{earning.total > 0 ? '+' : ''}{earning.total.toLocaleString()}</Text>
                  </Row>
                  <Text style={s.earnSub} numberOfLines={2}>
                    {earning.lines
                      .map((l) => `${EARN_SHORT[l.reason] ?? l.label} ${l.delta > 0 ? '+' : ''}${l.delta.toLocaleString()}`)
                      .join(' · ')}
                  </Text>
                </View>
              )}
              {/* 크레딧 라인 — 항상 (사진법 6조). [FLOOR14] 클럽·코스 이름(한글)은 트래킹 라틴 마이크로에서
                  분리해 읽는 크기로 세우고, 'DOGS HIGH'만 각인 세리얼로 남는다 */}
              <Text style={s.creditName}>{clubName || report.routeName || 'HIGH CLUB'}</Text>
              <Text style={s.credit}>DOGS HIGH</Text>
            </View>
          </View>
        </Animated.View>

        {/* ---------- 공유 = 성장 루프 (카드 밖 — 캡처에 안 들어간다). [Sean 규칙] 여백 화면 = 큰 버튼 ---------- */}
        <ClubCta label={stamping ? '도장 찍는 중…' : '이미지로 공유 →'} disabled={stamping} onPress={shareImage}
          style={{ marginTop: 14, paddingVertical: 18 }} />
        <ClubCta label="동네 피드에 자랑하기" tone="secondary" onPress={shareFeed} busy={busy} style={{ paddingVertical: 15 }} />
        <Pressable onPress={() => router.push({ pathname: '/owner/report', params: { bid: bid! } })}>
          <Text style={s.detailLink}>상세 리포트 (지도·이벤트) →</Text>
        </Pressable>
      </ScrollView>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  card: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    marginTop: 12, overflow: 'hidden', ...lilacShadow,
  },
  innerFrame: {
    position: 'absolute', left: 5, right: 5, top: 5, bottom: 5, zIndex: 2,
    borderWidth: 1, borderColor: L.goldSheen, borderRadius: 4, opacity: 0.55,
  },
  photoWrap: { height: 190, backgroundColor: L.inset },
  photo: { width: '100%', height: '100%' },
  // 실 무대 — 실과 파문이 같은 62 원을 공유한다 (레이아웃은 그대로: 62 사각 한 칸)
  sealStage: { width: 62, height: 62, alignItems: 'center', justifyContent: 'center', zIndex: 3 },
  sealRipple: { position: 'absolute', width: 62, height: 62, borderRadius: 31, borderWidth: 2, borderColor: L.gold },
  goldSeal: {
    width: 62, height: 62, borderRadius: 31, backgroundColor: L.goldSoft,
    borderWidth: 2, borderColor: L.gold, alignItems: 'center', justifyContent: 'center',
    zIndex: 3,
    // 회전·스케일은 ② 스탬프 보간이 소유한다 (정지값 = opacity 1 · scale 1 · rotate -8deg)
    shadowColor: L.gold, shadowOpacity: 0.35, shadowRadius: 8, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  goldSealTxt: { fontSize: 9, fontWeight: '800', letterSpacing: 1.5, color: '#8a6f2a' },
  numRow: {
    alignSelf: 'stretch', backgroundColor: L.inset, borderRadius: lilacRadius.inner,
    borderWidth: 1, borderColor: L.hair, marginTop: 14, overflow: 'hidden',
  },
  numCell: { flex: 1, paddingVertical: 9, alignItems: 'center', borderRightWidth: 1, borderRightColor: L.hair },
  numV: { fontSize: 18, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] },
  // [FLOOR14] 수치 라벨은 한글 정보다 — 320dp 셀 가용폭 ~89px 에서 '실측 거리'(≈62px)까지 한 줄로 든다
  numL: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginTop: 3 },
  // 하이 포인트 줄 — 수치 룰 행 바로 아래의 얇은 회계 줄. 골드는 SETTLED 전용이라 여기 안 쓴다.
  earnLine: { alignSelf: 'stretch', marginTop: 11, paddingTop: 9, borderTopWidth: 1, borderTopColor: L.hair },
  earnLead: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim },
  // [BUG A] Oswald 는 lineHeight 명시가 없으면 어센더가 잘린다 — 18 × 1.22
  earnV: { fontSize: 18, lineHeight: 22, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] },
  earnSub: { fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 3 },
  creditName: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginTop: 14 },
  credit: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2, color: L.dim, marginTop: 2 },
  detailLink: { textAlign: 'center', marginTop: 12, fontSize: 14, fontWeight: '800', color: L.accent },
});
