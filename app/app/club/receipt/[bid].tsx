import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Easing, Image, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { MediaImage, resolveMediaUrl } from '../../../src/lib/media';
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
//
// [Sean 2026-08-24 · docs/labs/enh-club-lab.html T] "The t screen (finished receipt) should have
// the shareable card thing nudge and social media share nudge. I like t2 but t1's image carousel
// should be incldued." Three things landed from that, and nothing else moved:
//   T② — the feed door answers BEFORE the tap (F13). runPhotoAllowed is asked at load, not on press.
//   T① — run.photos is an ARRAY and the card printed [0] forever; the rest are a contact strip
//        inside the print. No photos → the card is today's photo-less paper, unchanged.
//   nudges — the two doors shipped silent; each now says what it does before the finger moves.
// The ceremony is untouched (frozen in the lab): the once-law (sealStampFresh), the capture gate,
// 「도장 찍는 중…」. The strip forced ONE addition to that gate — see ④ photosReady.

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

  // ---------- ③ 피드 문의 선-판정 (랩 T② · 결함 F13) ----------
  // 하이 피드 공유는 진짜로 거절될 수 있는 문이다 — 위탁 러닝에 사진 공개 미동의 견이 있으면
  // 0053 §3a가 막는다. 오늘까지 그 거절은 **누른 뒤에** 알림으로 왔다. 같은 RPC를 로드 때 한 번
  // 물어, 거절을 손가락이 움직이기 전의 사실로 바꾼다. 세 값 세 뜻:
  //   null = 아직 모른다 → 오늘과 똑같은 문(누를 때 다시 확인한다)  ·  true = 가능  ·  false = 불가
  // ⚠ 실패는 거절이 아니다. RPC가 없는 구서버도, 네트워크 실패도 allowed로 떨어진다 — 네트워크
  // 오류로 '동의 안 함'을 그리는 건 없는 동의 결정을 지어내는 것이라 늦은 실패보다 나쁘다.
  // 술어는 아래 shareFeed의 것을 **그대로** 쓴다(rejected → true, 그 외 falsy → 거절): 같은 질문에
  // 두 개의 판정식을 두면 문과 그 문의 결과가 언젠가 서로 다른 말을 한다.
  const [feedAllowed, setFeedAllowed] = useState<boolean | null>(null);
  useEffect(() => {
    if (!bid) return;
    let alive = true;
    setFeedAllowed(null);
    runPhotoAllowed(bid).then(
      (ok) => { if (alive) setFeedAllowed(!!ok); },
      () => { if (alive) setFeedAllowed(true); },
    );
    return () => { alive = false; };
  }, [bid]);

  // ---------- ④ 캡처 게이트 확장 — 사진 (랩 T① 비용 항목) ----------
  // captureRef는 '지금 화면에 그려진 것'을 찍는다. 바이트가 아직 안 온 <Image>는 **빈 상자**로
  // 찍히고, 접촉 인화 스트립이 그 문제를 카드 한 장당 최대 6장으로 키웠다. 그래서 도장 게이트
  // 옆에 사진 게이트를 하나 더 둔다: 경로에 서명하고(resolveMediaUrl) RN 이미지 캐시로 당겨온
  // 뒤에야 공유 문이 열린다. 못 가져온 사진도 '해결됨'으로 친다 — MediaImage가 명시적 실패
  // 타일을 그리고, 찍힌 실패 타일은 정직하지만 빈 상자는 아니다.
  // ⚠ 이건 프리페치 기반이라 '캐시에 있다'까지만 보장한다(디코드 완료 콜백이 아니다). 게이트
  // 없음보다 엄격하고, 사용자의 탭은 그 뒤로 여러 프레임 뒤에 온다. 사진 0장이면 기다릴 게 없다.
  const shotKey = (report?.run?.photos ?? []).filter(Boolean).join('|');
  const [photosReady, setPhotosReady] = useState(true);
  useEffect(() => {
    if (!shotKey) { setPhotosReady(true); return; }
    let alive = true;
    setPhotosReady(false);
    Promise.all(
      shotKey.split('|').map((p) => resolveMediaUrl(p).then((u) => Image.prefetch(u)).catch(() => false)),
    ).then(() => { if (alive) setPhotosReady(true); });
    return () => { alive = false; };
  }, [shotKey]);

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
          <Text style={{ fontSize: 15, color: L.dim }}>완료된 러닝만 영수증이 나와요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={goBackOrHome} style={{ alignSelf: 'stretch' }} />
        </View>
      </DawnCanvas>
    );
  }

  const run = report.run;
  // 카드가 그리는 사진 목록. 빈 경로는 여기서 떨어진다 — 인화도 스트립도 '없는 사진'을 위한 빈
  // 칸을 두지 않는다 (빈 칸은 캡처된 PNG에 그대로 박힌다). 장수도 이 목록의 길이로 센다.
  const shots = run.photos.filter(Boolean);
  const bestShot = shots[0] ?? null;
  const pace = run.paceSecPerKm != null ? paceOf(run.paceSecPerKm)
    : run.actualKm > 0.05 ? paceOf(run.durationSec / run.actualKm) : "-'--\"";

  // 카드 캡처 → 시스템 공유 시트 (인증샷 화면 선례 — view-shot 지연 로드, 미탑재 빌드는 정직 안내)
  const shareImage = async () => {
    // ②④ 두 게이트 — 비행 중 트랜스폼도(도장), 아직 안 온 사진도(스트립) PNG에 박히면 안 된다.
    // 버튼 자체도 같은 술어로 비활성이라, 여기 줄은 경합용 이중 잠금이다.
    if (stamping || !photosReady) return;
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
      // [T② 2026-08-24] 선-판정이 생겼어도 이 줄은 남는다 — 로드 시점과 탭 시점 사이에 동의가
      // 바뀔 수 있고, 선-판정이 아직 null(모름)인 채로 누를 수도 있다. 여기서 처음 알게 된
      // 거절은 문에도 반영한다: 같은 사실을 두 번 눌러 배우게 하지 않는다.
      let allowed = true;
      try { allowed = await runPhotoAllowed(bid!); } catch { allowed = true; }
      if (!allowed) {
        setFeedAllowed(false);
        Alert.alert('공유 불가', '이 러닝엔 사진 공개에 동의하지 않은 아이가 있어 피드 공유를 할 수 없어요');
        return;
      }
      await shareRunToFeed(bid!);
      haptic('success');
      Alert.alert('피드에 올라갔어요', '하이 피드에서 오늘의 기록을 볼 수 있어요');
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
              <Text style={{ fontSize: 15, color: L.dim, marginTop: 4 }}>
                {report.runnerName ? `${report.runnerName}와 · ` : ''}{pace} · {durStr(run.durationSec)}
              </Text>
              <View style={{ marginTop: 10 }}>
                <Flap state="SETTLED" />
              </View>
              {/* 수치 룰 행 */}
              <Row style={s.numRow}>
                <View style={s.numCell}>
                  <Text style={[s.numV, nf]}>{run.actualKm.toFixed(1)}<Text style={{ fontSize: 15, color: L.coral }}>km</Text></Text>
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
              {/* 접촉 인화 스트립 (랩 T① — Sean: "t1's image carousel should be incldued").
                  run.photos는 배열인데 카드는 [0] 한 장만 인화해 왔다. 베스트 샷은 그대로 인화로
                  남고, 나머지가 숫자 룰 아래 스트립이 된다 — 썸네일은 글리프이지 디테일 텍스트가
                  아니다(14pt 바닥 비적용). 잘라내지 않는다: 러너 업로더가 6장에서 막으므로
                  (app/runner/done.tsx의 photos.length < 6) 스트립은 최대 5칸이고, slice(1)로 남는
                  걸 전부 그린다 — 있는 사진을 조용히 버리는 슬라이스는 두지 않는다.
                  사진 0·1장이면 이 블록 자체가 없다 (스톡·플레이스홀더 금지, 사진법).
                  캡처 대상 '안'이다 — 공유 PNG가 오늘의 사진 전부를 실어야 인화가 인화다.
                  대신 캡처 게이트가 ④로 넓어졌다. */}
              {shots.length > 1 && (
                <View style={{ alignSelf: 'stretch' }}>
                  <Row style={s.thumbs}>
                    {shots.slice(1).map((p, i) => (
                      /* [0064] 러닝 사진은 media 경로 — 서명 URL로 렌더, 만료는 명시적 실패 타일 */
                      <View key={`${i}-${p}`} style={s.thumb}>
                        <MediaImage source={p} style={s.thumbImg} resizeMode="cover" />
                      </View>
                    ))}
                  </Row>
                  <Text style={s.thumbCount}>
                    오늘 찍은 사진 <Text style={[s.thumbCountNum, nf]}>{shots.length}</Text>장
                  </Text>
                </View>
              )}
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
              {/* 크레딧 라인 — 항상 (사진법 6조). [FLOOR15] 클럽·코스 이름(한글)은 트래킹 라틴 마이크로에서
                  분리해 읽는 크기로 세우고, 'DOGS HIGH'만 각인 세리얼로 남는다 */}
              <Text style={s.creditName}>{clubName || report.routeName || 'HIGH CLUB'}</Text>
              <Text style={s.credit}>DOGS HIGH</Text>
            </View>
          </View>
        </Animated.View>

        {/* ---------- 공유 = 성장 루프 (카드 밖 — 캡처에 안 들어간다). [Sean 규칙] 여백 화면 = 큰 버튼 ----------
            [Sean 2026-08-24] "should have the shareable card thing nudge and social media share nudge."
            문 두 개는 이미 있었지만 아무 말도 하지 않았다 — 넛지는 그 문이 무엇을 하는지 누르기
            전에 말하는 두 줄이다. 지어낸 숫자는 없다: 이 화면이 이미 가진 사실(위 카드, 강아지
            이름)만 말한다. 코랄은 여전히 하나다 — 이미지로 공유. */}
        <View style={s.nudge}>
          <Text style={s.nudgeHead}>오늘의 카드가 나왔어요</Text>
          <Text style={s.nudgeBody}>
            위 영수증을 그대로 이미지로 만들어 저장하거나, 공유 시트에서 메시지·SNS로 바로 보낼 수 있어요.
          </Text>
          <Text style={s.nudgeSub}>내 기기에서만 저장·전송돼요</Text>
        </View>
        <ClubCta
          label={stamping ? '도장 찍는 중…' : !photosReady ? '사진 불러오는 중…' : '이미지로 공유 →'}
          disabled={stamping || !photosReady}
          onPress={shareImage}
          style={{ marginTop: 10, paddingVertical: 18 }}
        />
        {/* 인증샷 스튜디오 — 이 앱의 '공유 카드'가 원래 사는 집(스킨·인스타 스토리 내보내기).
            같은 부킹 id를 받는 실존 라우트라 죽은 문이 아니다 (owner/report·runner/home 선례). */}
        <Pressable
          onPress={() => router.push(`/shot/${bid}`)}
          accessibilityRole="button"
          accessibilityLabel="인증샷 카드로 꾸미기"
        >
          <Text style={s.studioLink}>인증샷 카드로 꾸미기 →</Text>
        </Pressable>

        {/* 하이 피드 문 — T②: 거절을 탭 뒤가 아니라 탭 전에 말한다.
            false(확정 거절)면 문 대신 사실을 그린다. null(아직 모름)·true면 오늘과 같은 문이다. */}
        {feedAllowed === false ? (
          <View style={s.refuse}>
            <Text style={s.refuseHead}>하이 피드 공유는 지금 할 수 없어요</Text>
            {/* 문장은 다른 보호자를 탓하지 않는다 — 동의는 각자의 결정이고, 여기선 사실만 말한다 */}
            <Text style={s.refuseBody}>
              함께 달린 아이 중에 사진 공개에 동의하지 않은 아이가 있어요 — 이 러닝은 피드에 올릴 수 없어요.
            </Text>
            <Text style={s.refuseSub}>이미지로 공유는 그대로 쓸 수 있어요 (내 기기에서만 저장·전송돼요)</Text>
          </View>
        ) : (
          <>
            {/* ⚠ 문장이 범위를 좁히지 않는다. feed_posts의 read 정책은 `using (true)`(0013)라
                '이웃만 본다'는 말은 사실이 아니다 — 공개는 공개라고 쓴다. 두 번째 절은
                shareRunToFeed가 실제로 싣는 것(photos[0])에 붙어 있어, 사진이 없으면 사라진다. */}
            <View style={s.nudge}>
              <Text style={s.nudgeHead}>동네에 자랑하기</Text>
              <Text style={s.nudgeBody}>
                {report.dogName}의 오늘 기록이 하이 피드에 공개돼요{bestShot ? ' — 베스트 샷 한 장이 함께 올라가요' : ''}.
              </Text>
            </View>
            <ClubCta label="하이 피드에 자랑하기" tone="secondary" onPress={shareFeed} busy={busy} style={{ marginTop: 10, paddingVertical: 15 }} />
          </>
        )}
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
  // [FLOOR15] 수치 라벨은 한글 정보다 — 320dp 셀 가용폭 ~89px 에서 '실측 거리'(≈62px)까지 한 줄로 든다
  numL: { fontSize: 15, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginTop: 3 },
  // 접촉 인화 스트립 (T①) — 랩과 같은 치수: 6 간격, 높이 56, 칸은 균등(flex:1).
  thumbs: { alignSelf: 'stretch', gap: 6, marginTop: 10 },
  thumb: { flex: 1, height: 56, backgroundColor: L.inset, borderWidth: 1, borderColor: L.hair, overflow: 'hidden' },
  thumbImg: { width: '100%', height: '100%' },
  // 장수 줄은 한글 정보다 — 14pt 바닥 적용 (썸네일만 글리프로 면제된다)
  thumbCount: { alignSelf: 'stretch', textAlign: 'left', fontSize: 15, lineHeight: 18, color: L.dim, marginTop: 6 },
  // [BUG A] Oswald 는 lineHeight 명시가 없으면 어센더가 잘린다 — 14 × 1.29
  thumbCountNum: { fontSize: 15, lineHeight: 18, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] },
  // 공유 넛지 (Sean 2026-08-24) — 문이 아니라 문 앞의 한 마디라서 인셋 위 잉크다 (버튼 아님).
  nudge: { backgroundColor: L.inset, borderRadius: lilacRadius.inner, padding: 12, marginTop: 16 },
  nudgeHead: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.head },
  nudgeBody: { fontSize: 15, lineHeight: 20, color: L.text, marginTop: 4 },
  nudgeSub: { fontSize: 15, lineHeight: 18, color: L.dim, marginTop: 6 },
  // 피드 거절 (T②) — 경고가 아니라 사실이라 크리티컬 잉크를 안 쓴다. 종이 한 장, 헤어라인 트림.
  refuse: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    padding: 13, marginTop: 16,
  },
  refuseHead: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: L.head },
  refuseBody: { fontSize: 15, lineHeight: 20, color: L.text, marginTop: 6 },
  refuseSub: { fontSize: 15, lineHeight: 18, color: L.dim, marginTop: 6 },
  studioLink: { textAlign: 'center', marginTop: 12, fontSize: 15, fontWeight: '800', color: L.accent },
  // 하이 포인트 줄 — 수치 룰 행 바로 아래의 얇은 회계 줄. 골드는 SETTLED 전용이라 여기 안 쓴다.
  earnLine: { alignSelf: 'stretch', marginTop: 11, paddingTop: 9, borderTopWidth: 1, borderTopColor: L.hair },
  earnLead: { fontSize: 15, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim },
  // [BUG A] Oswald 는 lineHeight 명시가 없으면 어센더가 잘린다 — 18 × 1.22
  earnV: { fontSize: 18, lineHeight: 22, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] },
  earnSub: { fontSize: 15, lineHeight: 18, color: L.dim, marginTop: 3 },
  creditName: { fontSize: 15, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginTop: 14 },
  credit: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2, color: L.dim, marginTop: 2 },
  detailLink: { textAlign: 'center', marginTop: 12, fontSize: 15, fontWeight: '800', color: L.accent },
});
