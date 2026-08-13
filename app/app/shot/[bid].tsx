import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Modal, PanResponder, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';
import { fetchRunReport, fetchRunStandings, RunReport, RunStandings } from '../../src/lib/api';
import { traceToBox } from '../../src/lib/trace';
import { resolveMediaUrl } from '../../src/lib/media';
import { useDisplayFont } from '../../src/lib/displayFont';
import { haptic } from '../../src/lib/haptics';
import { colors, paper } from '../../src/theme';
import { pathFrom, RunShareCard } from '../../src/components/run-share-card';
import Constants from 'expo-constants';
import { instagramAvailable, shareToInstagramStories } from '../../modules/instagram-share';
import { Icon } from '../../src/components/ui';

// 인증샷 스튜디오 (2026-07-28 확정 스펙) — 공유가 곧 마케팅.
// 스킨 5: A 트랜스페어런트(기본) · B 투명 대형 · B 포토 · G 폴라로이드 · I 볼트 블록.
// 러너 사진이 있으면 B 포토가 2번 슬롯으로 승격. 완성 = 즉시 캡처 + iOS 공유 시트 (재탭 금지).
// 브랜드 디바이스: 아이콘 칩 · 브랜드 테이프 · 워드마크 락업 — 어느 스킨이 돌아다녀도 도그스하이가 남는다.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const W = Dimensions.get('window').width;
const CARD_W = W - 96;
const STORY_H = Math.round(CARD_W * (16 / 9) * 0.92); // 9:16 근사 — 화면 안에 액션 바까지
const FEED_H = Math.round(CARD_W * 1.25);
const GAP = 14;
const SNAP = CARD_W + GAP;

const fmtDur = (sec: number) => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');

// 실 GPS → 박스 좌표: src/lib/trace.ts의 traceToBox 정본 (0082 K1).
// 여기 있던 사본은 축별 min-max라 종횡비를 늘렸다 — 서울에서 경도 1도는 위도 1도의 0.79배
// 거리이므로, 동서로 긴 한강 경로가 공유 카드 위에서 세로로 부푼 모양이 됐다. 공유 카드는
// 이 제품에서 가장 공개적인 표면이라 실루엣이 사실인 게 특히 중요하다.
// (traceToBox는 v(진행도)도 실어 주지만 여기 SVG 경로는 x/y만 쓴다 — 남는 필드는 무해.)

// [2026-08-12] pathFrom는 run-share-card.tsx가 export하는 것을 쓴다 — 같은 산식이 두 벌이 되면
// 공유 카드와 스튜디오 스킨의 궤적이 조용히 어긋난다. 정본 하나.

// ── 브랜드 디바이스 ──────────────────────────────────────────
function IconChip({ size, df }: { size: number; df: any }) {
  return (
    <View style={{
      width: size, height: size, borderRadius: size * 0.22, backgroundColor: paper.ink,
      alignItems: 'center', justifyContent: 'center',
      shadowColor: '#000', shadowOpacity: 0.3, shadowRadius: 4, shadowOffset: { width: 0, height: 2 },
    }}>
      {/* [D13 2026-08-12] 로고 아트워크 예외 (DESIGN.md §3) — 이 두 줄은 문장이 아니라 **마크**다
          (size 24에서 5.8/7.7pt). 예외를 타려면 선언이 필요하다: 보조기술에는 장식으로 감춘다.
          바깥 BrandLockup이 읽을 이름을 갖는다. 데이터는 한 글자도 여기 들어오지 않는다. */}
      <Text accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={[{ fontSize: size * 0.24, color: colors.volt, fontWeight: '900', lineHeight: size * 0.28 }, df]}>도그스</Text>
      <Text accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={[{ fontSize: size * 0.32, color: colors.volt, fontWeight: '900', lineHeight: size * 0.36, letterSpacing: 1 }, df]}>하이</Text>
    </View>
  );
}

function BrandTape({ width, rotate, df }: { width: number; rotate: string; df: any }) {
  return (
    <View style={{
      width, height: 26, backgroundColor: colors.volt, transform: [{ rotate }],
      flexDirection: 'row', alignItems: 'center', overflow: 'hidden',
      shadowColor: '#000', shadowOpacity: 0.25, shadowRadius: 5, shadowOffset: { width: 0, height: 2 },
    }}>
      {/* [D13 2026-08-12] 반복 브랜드 테이프 = 워드마크 아트워크 (DESIGN.md §3 로고 예외).
          코덱스는 "반복은 한글을 글리프로 만들지 않는다"며 14pt를 요구했고 그 지적은 옳다 —
          그래서 '반복하니까 괜찮다'가 아니라 '이건 워드마크다'로 예외를 세우고 선언한다.
          데이터는 없고(브랜드 이름뿐), 스크린리더에는 장식으로 감춘다. */}
      <Text accessibilityElementsHidden importantForAccessibility="no-hide-descendants" numberOfLines={1} style={[{ fontSize: 13, color: paper.ink, fontWeight: '900', letterSpacing: 2, paddingLeft: 6 }, df]}>
        도그스하이 · DOGS HIGH · 도그스하이 · DOGS HIGH · 도그스하이 · DOGS HIGH
      </Text>
    </View>
  );
}

function Lockup({ df, small, light = true }: { df: any; small?: boolean; light?: boolean }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: small ? 6 : 8 }}>
      <IconChip size={small ? 24 : 32} df={df} />
      <Text style={[{
        fontSize: small ? 12.5 : 15.5, color: light ? '#fff' : paper.ink, fontWeight: '900', letterSpacing: 2,
        ...(light ? { textShadowColor: 'rgba(0,0,0,.5)', textShadowRadius: 6, textShadowOffset: { width: 0, height: 1 } } : {}),
      }, df]}>
        도그스하이 <Text style={{ color: light ? colors.volt : colors.voltDeep }}>DOGS HIGH</Text>
      </Text>
    </View>
  );
}

// ── 사진 레이어 — 핀치 줌 · 드래그 팬 · 더블탭 리셋 (스탯·로고 레이어는 고정) ──
function PhotoLayer({ uri, w, h, resetKey }: { uri: string; w: number; h: number; resetKey: string }) {
  const scale = useRef(new Animated.Value(1)).current;
  const pan = useRef(new Animated.ValueXY()).current;
  const st = useRef({ baseScale: 1, baseX: 0, baseY: 0, startDist: 0, lastTap: 0 }).current;

  // 새 사진 = transform 리셋 (이전 사진의 크롭 유령 방지)
  useEffect(() => {
    st.baseScale = 1; st.baseX = 0; st.baseY = 0;
    scale.setValue(1); pan.setValue({ x: 0, y: 0 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resetKey]);

  const responder = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 2 || Math.abs(g.dy) > 2,
    onPanResponderGrant: (e) => {
      const now = Date.now();
      if (now - st.lastTap < 280 && e.nativeEvent.touches.length === 1) {
        st.baseScale = 1; st.baseX = 0; st.baseY = 0;
        Animated.parallel([
          Animated.spring(scale, { toValue: 1, useNativeDriver: true, friction: 7 }),
          Animated.spring(pan, { toValue: { x: 0, y: 0 }, useNativeDriver: true, friction: 7 }),
        ]).start();
      }
      st.lastTap = now;
      st.startDist = 0;
    },
    onPanResponderMove: (e, g) => {
      const t = e.nativeEvent.touches;
      if (t.length >= 2) {
        const d = Math.hypot(t[0].pageX - t[1].pageX, t[0].pageY - t[1].pageY);
        if (st.startDist === 0) st.startDist = d;
        else scale.setValue(Math.min(3.5, Math.max(1, st.baseScale * (d / st.startDist))));
      } else {
        pan.setValue({ x: st.baseX + g.dx, y: st.baseY + g.dy });
      }
    },
    onPanResponderRelease: (_e, g) => {
      st.baseX += g.dx; st.baseY += g.dy;
      scale.stopAnimation((v: number) => { st.baseScale = Math.min(3.5, Math.max(1, v)); });
      st.startDist = 0;
    },
  })).current;

  return (
    <Animated.View
      {...responder.panHandlers}
      style={{ position: 'absolute', top: 0, left: 0, width: w, height: h, transform: [{ translateX: pan.x }, { translateY: pan.y }, { scale }] }}
    >
      <Image source={{ uri }} style={{ width: w, height: h }} resizeMode="cover" />
    </Animated.View>
  );
}

// ── 스킨 정의 — A·B·G·I 4종. A·B는 사진 온/오프 이중 모드:
// 사진 없으면 투명 스티커(체커보드 프리뷰), 사진 올리면 그 위에 오버레이 (Sean 2026-07-28 정정).
// B의 사진 없는 모드 = '투명 배경 + 대형 트레이스' (B 변형 아이디어가 B의 상태로 복원).
type SkinKey = 'A' | 'Bp' | 'G' | 'I';
const SKIN_META: Record<SkinKey, { name: string; h: number }> = {
  A: { name: '투명 스티커', h: STORY_H },
  Bp: { name: '포토', h: STORY_H },
  G: { name: '폴라로이드', h: FEED_H },
  I: { name: '볼트 블록', h: FEED_H },
};

export default function ShotStudio() {
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const df = useDisplayFont();
  const [report, setReport] = useState<RunReport | null>(null);
  const [standings, setStandings] = useState<RunStandings | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // 스킨별 독립 사진 (2026-07-29) — B에서 사진을 바꿔도 A의 사진·크롭이 유지된다.
  // transform은 PhotoLayer 인스턴스별이고 resetKey가 스킨별 uri이므로, 자기 사진이 바뀔 때만 리셋.
  const [photos, setPhotos] = useState<Record<'A' | 'Bp' | 'G', string | null>>({ A: null, Bp: null, G: null });
  const [sheetOpen, setSheetOpen] = useState(false);
  const sheetFor = useRef<SkinKey>('Bp'); // 어느 스킨이 사진을 요청했나 (확정 시 그 스킨의 사진 모드 on)
  const [photoOn, setPhotoOn] = useState<{ A: boolean; Bp: boolean }>({ A: false, Bp: true });
  const [busy, setBusy] = useState(false);
  const [active, setActive] = useState(0);
  const cardRefs = useRef<Record<SkinKey, View | null>>({ A: null, Bp: null, G: null, I: null });

  useEffect(() => {
    if (!bid) { setErr('러닝 정보가 없어요'); return; }
    fetchRunReport(bid).then(setReport).catch((e) => setErr(e?.message ?? '불러오기 실패'));
    fetchRunStandings(bid).then(setStandings).catch(() => {});
  }, [bid]);

  const run = report?.run ?? null;
  const pts = useMemo(() => (run && run.trace.length > 1 ? traceToBox(run.trace) : null), [run]);
  // [0064] runs.photos는 프라이빗 media 경로일 수 있다 — PhotoLayer/캡처가 실 URI를 요구하므로
  // 여기서 한 번 서명 URL로 풀어 상태에 담는다. 실패 장수는 시트에 정직하게 고지 (침묵 강등 금지).
  const [runPhotos, setRunPhotos] = useState<string[]>([]);
  const [photoSignFails, setPhotoSignFails] = useState(0);
  useEffect(() => {
    const paths = run?.photos ?? [];
    if (paths.length === 0) { setRunPhotos([]); setPhotoSignFails(0); return; }
    let live = true;
    Promise.all(paths.map((p) => resolveMediaUrl(p).catch(() => null))).then((rs) => {
      if (!live) return;
      setRunPhotos(rs.filter((x): x is string => !!x));
      setPhotoSignFails(rs.filter((x) => x === null).length);
    });
    return () => { live = false; };
    // sheetOpen 재오픈 = 실패분 재시도 (서명 캐시가 있어 성공분은 공짜)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [run, sheetOpen]);

  // 러너 사진이 있으면 자동 기본 사진 (스킨별, 이미 고른 스킨은 유지)
  useEffect(() => {
    if (runPhotos.length > 0) {
      setPhotos((p) => ({ A: p.A ?? runPhotos[0], Bp: p.Bp ?? runPhotos[0], G: p.G ?? runPhotos[0] }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runPhotos.length]);

  const order: SkinKey[] = ['A', 'Bp', 'G', 'I']; // A 투명 기본 · B 포토 2번 고정
  const activeKey = order[Math.min(active, order.length - 1)];

  // 스킨별 사진 상태 — G는 사진 필수, A/B는 선택(없으면 투명 스티커)
  const photoKey = (k: SkinKey): 'A' | 'Bp' | 'G' => (k === 'I' ? 'Bp' : k); // I는 사진 없음 — 방어용 매핑
  const hasPhoto = (k: SkinKey) =>
    (k === 'G' && !!photos.G) || (k === 'A' && photoOn.A && !!photos.A) || (k === 'Bp' && photoOn.Bp && !!photos.Bp);
  const isTransparent = (k: SkinKey) => (k === 'A' || k === 'Bp') && !hasPhoto(k);

  const recordLine = useMemo(() => {
    if (!standings) return null;
    const out: string[] = [];
    if (standings.total > 1) {
      if (standings.kmRank === 1) out.push('역대 최장');
      if (standings.paceRank === 1) out.push('최고 페이스');
    }
    return out.length > 0 ? out.join(' · ') : null;
  }, [standings]);

  // ── 캡처 → 공유/저장 — 완성 = 곧 공유 시트 (재탭 금지) ──
  const capture = async (): Promise<string | null> => {
    try {
      const VS = require('react-native-view-shot');
      const ref = cardRefs.current[activeKey];
      if (!ref) return null;
      return await VS.captureRef(ref, { format: 'png', quality: 1 });
    } catch {
      Alert.alert('개발 빌드 업데이트 필요', '카드 캡처(view-shot)는 새 빌드에 포함돼요');
      return null;
    }
  };

  // 인스타 설치 여부는 **렌더 시점에 한 번** 묻는다 (네이티브 왕복). 없으면 버튼을 아예 안 그린다 —
  // 설치 안 된 앱으로 가는 버튼은 죽은 버튼이다 (§7 정직법).
  const igOk = useMemo(() => instagramAvailable(), []);

  // 인스타 스토리 1탭 — 캡처한 PNG를 배경 스티커로 넘긴다.
  // base64가 필요하다: 페이스트보드에 들어가는 건 파일 경로가 아니라 **바이트**다.
  const shareToInstagram = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const VS = require('react-native-view-shot');
      const ref = cardRefs.current[activeKey];
      if (!ref) throw new Error('카드를 캡처하지 못했어요');
      const b64 = await VS.captureRef(ref, { format: 'png', quality: 1, result: 'base64' });
      const appId = (Constants.expoConfig?.extra as any)?.instagramAppId ?? '';
      await shareToInstagramStories(b64, appId);
      haptic('success');
    } catch (e) {
      // 실패를 삼키지 않는다 — 사용자는 공유가 됐다고 믿고 앱을 나간다.
      Alert.alert('인스타 공유 실패', (e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const shareNow = async () => {
    if (busy) return;
    setBusy(true);
    haptic('success');
    const uri = await capture();
    if (uri) { try { await Share.share({ url: uri }); } catch { /* 취소 */ } }
    setBusy(false);
  };

  const savePng = async () => {
    if (busy) return;
    setBusy(true);
    const uri = await capture();
    if (uri) {
      try {
        const ML = require('expo-media-library');
        const perm = await ML.requestPermissionsAsync();
        if (!perm.granted) throw new Error('no-perm');
        await ML.saveToLibraryAsync(uri);
        haptic('success');
        Alert.alert('저장 완료', isTransparent(activeKey)
          ? '투명 PNG가 사진첩에 저장됐어요 — 인스타 스토리에서 스티커처럼 올려보세요'
          : '이미지가 사진첩에 저장됐어요');
      } catch {
        // 미디어 라이브러리 미탑재/거부 → 공유 시트의 '이미지 저장'으로 폴백
        try { await Share.share({ url: uri }); } catch { /* 취소 */ }
      }
    }
    setBusy(false);
  };

  const pickFromGallery = async () => {
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '갤러리 선택은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.9 });
      if (res.canceled || !res.assets?.[0]?.uri) return;
      const k = sheetFor.current;
      setPhotos((p) => ({ ...p, [photoKey(k)]: res.assets[0].uri })); // 요청한 스킨에만 (독립 사진)
      if (k === 'A' || k === 'Bp') setPhotoOn((p) => ({ ...p, [k]: true }));
      setSheetOpen(false);
      setTimeout(shareNow, 450); // 갤러리 선택도 확정과 동일 — 완성 즉시 공유
    } catch (e) {
      Alert.alert('사진 선택 실패', (e as Error).message);
    }
  };

  // 사진 시트에서 확정 → 요청한 스킨의 사진 모드 on → 렌더 안정 후 자동 공유 (완성 즉시 공유 시트)
  const confirmPhoto = () => {
    const k = sheetFor.current;
    if (k === 'A' || k === 'Bp') setPhotoOn((p) => ({ ...p, [k]: true }));
    setSheetOpen(false);
    setTimeout(shareNow, 450);
  };

  // ── 스킨 렌더 ──
  const renderSkin = (key: SkinKey) => {
    if (!report || !run) return null;
    const h = SKIN_META[key].h;
    const dog = report.dogName;
    const km = run.actualKm;
    const statLine = { time: fmtDur(run.durationSec), pace: fmtPace(run.paceSecPerKm) };

    const stats = (light = true) => (
      <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
        {[['DISTANCE', `${km}km`], ['PACE', statLine.pace], ['TIME', statLine.time]].map(([l, v]) => (
          <View key={l}>
            <Text style={[s.hudL, !light && { color: '#3d453d', textShadowRadius: 0 }]}>{l}</Text>
            <Text style={[s.hudV, !light && { color: paper.ink, textShadowRadius: 0 }]}>{v}</Text>
          </View>
        ))}
      </View>
    );

    if (key === 'A') {
      const photo = hasPhoto('A');
      return (
        <View style={{ width: CARD_W, height: h }}>
          {/* 사진 위에 올리기 모드 — 투명 스티커가 사진을 배경으로 얻는다 */}
          {photo && <PhotoLayer uri={photos.A!} w={CARD_W} h={h} resetKey={photos.A!} />}
          {photo && <View pointerEvents="none" style={s.scrimBottom} />}
          {/* 브랜드 테이프 — 투명으로 저장돼도 봉인은 남는다 */}
          <View pointerEvents="none" style={{ position: 'absolute', top: 18, left: -14, right: -14 }}>
            <BrandTape width={CARD_W + 28} rotate="-2deg" df={df} />
          </View>
          {pts ? (
            <Svg pointerEvents="none" width={CARD_W} height={h * 0.62} viewBox={`0 0 ${CARD_W} ${h * 0.62}`} style={{ position: 'absolute', top: h * 0.12 }}>
              <Path d={pathFrom(pts, CARD_W, h * 0.62, 40)} stroke="rgba(198,245,66,.35)" strokeWidth={15} strokeLinecap="round" strokeLinejoin="round" fill="none" />
              <Path d={pathFrom(pts, CARD_W, h * 0.62, 40)} stroke={colors.volt} strokeWidth={6} strokeLinecap="round" strokeLinejoin="round" fill="none" />
              <Circle cx={40 + pts[0].x * (CARD_W - 80)} cy={40 + pts[0].y * (h * 0.62 - 80)} r={7} fill="#fff" />
              <Circle cx={40 + pts[pts.length - 1].x * (CARD_W - 80)} cy={40 + pts[pts.length - 1].y * (h * 0.62 - 80)} r={7} fill={colors.tang} />
            </Svg>
          ) : (
            <Text style={[s.noTrace, { top: h * 0.4 }]}>GPS 트레이스가 없는 러닝이에요</Text>
          )}
          <View pointerEvents="none" style={{ position: 'absolute', bottom: 22, left: 18, right: 18 }}>
            <View style={{ alignItems: 'center', marginBottom: 14 }}><Lockup df={df} /></View>
            {stats()}
            {recordLine && <Text style={s.recordT}>{recordLine}</Text>}
          </View>
        </View>
      );
    }

    if (key === 'Bp') {
      const photo = hasPhoto('Bp');
      // 사진 없는 B = 투명 배경 + 대형 화이트 트레이스 (Sean의 B 변형 아이디어 — B의 상태로 복원)
      if (!photo) {
        return (
          <View style={{ width: CARD_W, height: h }}>
            <View pointerEvents="none" style={{ position: 'absolute', top: 14, right: 14 }}><IconChip size={40} df={df} /></View>
            {pts ? (
              <Svg pointerEvents="none" width={CARD_W} height={h * 0.7} viewBox={`0 0 ${CARD_W} ${h * 0.7}`} style={{ position: 'absolute', top: h * 0.08 }}>
                <Path d={pathFrom(pts, CARD_W, h * 0.7, 16)} stroke="#fff" strokeWidth={7} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                <Circle cx={16 + pts[0].x * (CARD_W - 32)} cy={16 + pts[0].y * (h * 0.7 - 32)} r={7} fill={colors.volt} />
                <Circle cx={16 + pts[pts.length - 1].x * (CARD_W - 32)} cy={16 + pts[pts.length - 1].y * (h * 0.7 - 32)} r={7} fill={colors.tang} />
              </Svg>
            ) : (
              <Text style={[s.noTrace, { top: h * 0.4 }]}>GPS 트레이스가 없는 러닝이에요</Text>
            )}
            <View pointerEvents="none" style={{ position: 'absolute', bottom: 22, left: 18, right: 18 }}>
              <Text style={[s.dogTitle, df]}>{dog}의 러닝</Text>
              <View style={{ marginTop: 12, marginBottom: 12 }}>{stats()}</View>
              <Lockup df={df} small />
            </View>
          </View>
        );
      }
      return (
        <View style={{ width: CARD_W, height: h, borderRadius: 20, overflow: 'hidden', backgroundColor: paper.ink }}>
          <PhotoLayer uri={photos.Bp!} w={CARD_W} h={h} resetKey={photos.Bp!} />
          <View pointerEvents="none" style={s.scrimBottom} />
          <View pointerEvents="none" style={{ position: 'absolute', top: 14, right: 14 }}><IconChip size={40} df={df} /></View>
          {pts && (
            <Svg pointerEvents="none" width={110} height={120} viewBox="0 0 110 120" style={{ position: 'absolute', top: 66, right: 16 }}>
              <Path d={pathFrom(pts, 110, 120, 8)} stroke="#fff" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" fill="none" opacity={0.95} />
              <Circle cx={8 + pts[0].x * 94} cy={8 + pts[0].y * 104} r={4.5} fill={colors.volt} />
              <Circle cx={8 + pts[pts.length - 1].x * 94} cy={8 + pts[pts.length - 1].y * 104} r={4.5} fill={colors.tang} />
            </Svg>
          )}
          <View pointerEvents="none" style={{ position: 'absolute', bottom: 20, left: 18, right: 18 }}>
            <Text style={[s.dogTitle, df]}>{dog}의 러닝</Text>
            <View style={{ marginTop: 12, marginBottom: 12 }}>{stats()}</View>
            <Lockup df={df} small />
          </View>
        </View>
      );
    }

    if (key === 'G') {
      const PH = h - 96;
      return (
        <View style={{ width: CARD_W, height: h, backgroundColor: '#e9e4d6', alignItems: 'center', justifyContent: 'center' }}>
          <View style={{ width: CARD_W - 64, backgroundColor: '#fff', padding: 10, paddingBottom: 0, transform: [{ rotate: '-2.5deg' }], shadowColor: paper.ink, shadowOpacity: 0.28, shadowRadius: 12, shadowOffset: { width: 0, height: 8 } }}>
            <View style={{ height: PH - 62, overflow: 'hidden', backgroundColor: '#c9ccc0' }}>
              {photos.G
                ? <PhotoLayer uri={photos.G} w={CARD_W - 84} h={PH - 62} resetKey={photos.G} />
                : <View style={[s.photoEmpty, { backgroundColor: '#3b4d35' }]}><Icon name="Image" glyph="○" size={24} color="#8fa093" /></View>}
              {/* 트레이스 = 폴라로이드의 주인공 (Sean 2026-07-29: 크게·중앙·선명한 네온).
                  다크 헤일로 언더스트로크가 어떤 사진 위에서도 볼트를 세운다 */}
              {pts && (() => {
                const PW = CARD_W - 84;
                const PHH = PH - 62;
                const TW = Math.round(PW * 0.74);
                const TH = Math.round(PHH * 0.6);
                return (
                  <Svg
                    pointerEvents="none"
                    width={TW}
                    height={TH}
                    viewBox={`0 0 ${TW} ${TH}`}
                    style={{ position: 'absolute', left: (PW - TW) / 2, top: (PHH - TH) / 2 }}
                  >
                    <Path d={pathFrom(pts, TW, TH, 14)} stroke="rgba(15,29,19,.45)" strokeWidth={9} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                    <Path d={pathFrom(pts, TW, TH, 14)} stroke={colors.volt} strokeWidth={4.5} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                    <Circle cx={14 + pts[0].x * (TW - 28)} cy={14 + pts[0].y * (TH - 28)} r={5.5} fill="#fff" />
                    <Circle cx={14 + pts[pts.length - 1].x * (TW - 28)} cy={14 + pts[pts.length - 1].y * (TH - 28)} r={5.5} fill={colors.tang} />
                  </Svg>
                );
              })()}
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 9 }}>
              <IconChip size={28} df={df} />
              <Text numberOfLines={2} style={{ flex: 1, fontSize: 14.5, fontWeight: '800', color: paper.ink, fontStyle: 'italic' }}>
                {dog}, {km}km 완주!! <Text style={{ fontSize: 14, color: '#5B594A' }}>{report.when.split(' ')[0]} {report.when.split(' ')[1]} · 도그스하이</Text>
              </Text>
            </View>
            <View style={{ position: 'absolute', top: -12, left: '50%', marginLeft: -62 }}>
              <BrandTape width={124} rotate="3deg" df={df} />
            </View>
          </View>
        </View>
      );
    }

    // I — 볼트 블록. [2026-08-12] 인라인 조판이 `RunShareCard`로 이사했다 (코덱스 §C 지적:
    // 컴포저 미리보기와 인스타 export가 같은 카드를 각자 다시 그리려 하고 있었다).
    // 이 스킨은 **사진을 요구하지 않는 유일한 스킨**이라 공유 아티팩트의 정본이 됐다 —
    // 완주 사진은 선택이고, 사진을 요구하면 사진 없는 러너는 공유 자체를 못 한다.
    // 나머지 3종(A 투명·Bp 포토·G 폴라로이드)은 여기 인라인으로 남는다: 사진 레이어·크롭 제스처와
    // 얽혀 있어 순수 컴포넌트로 뽑으면 그 상호작용까지 끌고 가야 한다. 공유되는 한 장만 정본화한다.
    return (
      <RunShareCard
        width={CARD_W}
        height={h}
        df={df}
        data={{
          dogName: dog,
          km,
          durationSec: run.durationSec ?? null,
          paceSecPerKm: run.paceSecPerKm ?? null,
          when: report.when,
          routeName: report.routeName ?? null,
          trace: pts,
          recordLine,
        }}
      />
    );
  };

  // ── 액션 바 — 스킨별 분기 ──
  const openSheet = (k: SkinKey) => { sheetFor.current = k; setSheetOpen(true); };
  // 사진이 붙은 A/B: 고스트 버튼이 [사진 변경 / 투명으로] 메뉴
  const photoMenu = (k: 'A' | 'Bp') => Alert.alert('사진', undefined, [
    { text: '사진 변경', onPress: () => openSheet(k) },
    { text: '투명 배경으로', onPress: () => setPhotoOn((p) => ({ ...p, [k]: false })) },
    { text: '취소', style: 'cancel' },
  ]);

  const t = isTransparent(activeKey);
  const sheetKey = photoKey(sheetFor.current); // 시트가 어느 스킨의 사진을 고르는 중인가
  const needsPhotoNow = activeKey === 'G' && !photos.G;
  const mainLabel = busy ? '만드는 중...' : needsPhotoNow ? '사진 고르기 ›' : t ? '투명 PNG 저장' : '공유하기 ›';
  const onMain = needsPhotoNow ? () => openSheet('G') : t ? savePng : shareNow;
  const [ghostLabel, onGhost] =
    activeKey === 'A'
      ? hasPhoto('A') ? ['사진', () => photoMenu('A')] as const : ['사진 위에 올리기', () => openSheet('A')] as const
      : activeKey === 'Bp'
        ? hasPhoto('Bp') ? ['사진', () => photoMenu('Bp')] as const : ['사진 넣기', () => openSheet('Bp')] as const
        : activeKey === 'G' && photos.G
          ? ['사진 변경', () => openSheet('G')] as const
          : ['이미지 저장', savePng] as const;

  return (
    <View style={{ flex: 1, backgroundColor: '#0C130E' }}>
      {/* 헤더 */}
      <View style={s.head}>
        <Pressable onPress={() => router.back()} style={s.x}><Text style={{ fontSize: 17, color: '#8fa093' }}>✕</Text></Pressable>
        <Text style={[{ fontSize: 19, fontWeight: '900', color: '#fff' }, df]}>인증샷</Text>
        <View style={{ width: 34 }} />
      </View>

      {err && <View style={s.errBox}><Text style={{ fontSize: 14.5, color: '#8fa093', textAlign: 'center' }}>{err}</Text></View>}
      {!err && report && !run && (
        <View style={s.errBox}><Text style={{ fontSize: 14.5, color: '#8fa093', textAlign: 'center' }}>러닝이 끝나면 인증샷을 만들 수 있어요</Text></View>
      )}

      {report && run && (
        <>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            snapToInterval={SNAP}
            decelerationRate="fast"
            disableIntervalMomentum
            contentContainerStyle={{ paddingHorizontal: (W - CARD_W) / 2, gap: GAP, alignItems: 'center' }}
            onScroll={(e) => {
              const i = Math.min(order.length - 1, Math.max(0, Math.round(e.nativeEvent.contentOffset.x / SNAP)));
              if (i !== active) { setActive(i); haptic('light'); }
            }}
            scrollEventThrottle={32}
            style={{ flexGrow: 0, marginTop: 8 }}
          >
            {order.map((key) => {
              const kMeta = SKIN_META[key];
              const kt = isTransparent(key);
              return (
                <View key={key} style={{ width: CARD_W, height: STORY_H, justifyContent: 'center' }}>
                  {/* 투명 모드: 체커보드는 캡처 밖 (프리뷰 전용) */}
                  {kt && <View style={[s.checker, { height: kMeta.h }]} pointerEvents="none" />}
                  <View
                    ref={(r) => { cardRefs.current[key] = r; }}
                    collapsable={false}
                    style={{ width: CARD_W, height: kMeta.h, borderRadius: kt ? 0 : 20, overflow: kt ? 'visible' : 'hidden' }}
                  >
                    {renderSkin(key)}
                  </View>
                </View>
              );
            })}
          </ScrollView>

          {/* 도트 + 스킨명 */}
          <View style={s.dots}>
            {order.map((k, i) => (
              <View key={k} style={[s.dot, i === active && s.dotOn]} />
            ))}
          </View>
          <Text style={s.skinName}>
            {SKIN_META[activeKey].name}
            {hasPhoto(activeKey) ? ' · 핀치로 크기 · 드래그로 위치 · 더블탭 원위치' : t ? ' · 저장 후 인스타 스토리 스티커로' : ''}
          </Text>

          {/* 액션 바 */}
          <View style={s.actRow}>
            <Pressable onPress={onGhost} disabled={busy} style={[s.actGhost, busy && { opacity: 0.5 }]}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: '#b8c4ae' }}>{ghostLabel}</Text>
            </Pressable>
            <Pressable onPress={onMain} disabled={busy} style={[s.actMain, busy && { opacity: 0.6 }]}>
              <Text style={{ fontSize: 15, fontWeight: '900', color: paper.ink }}>{mainLabel}</Text>
            </Pressable>
          </View>

          {/* 인스타 스토리 1탭 — **설치돼 있을 때만 그린다**.
              시스템 공유 시트(위 '공유하기')는 탭 두 번이고 늘 있다. 이 버튼은 한 번이고,
              인스타가 없으면 갈 곳이 없으므로 아예 존재하지 않는다 (죽은 버튼 금지법).
              igOk가 false인 경우는 둘 다 포함한다: 앱 미설치 · 이 빌드에 네이티브 모듈 없음. */}
          {igOk && (
            <Pressable
              onPress={shareToInstagram}
              disabled={busy}
              style={[s.igBtn, busy && { opacity: 0.6 }]}
              accessibilityRole="button"
              accessibilityLabel="인스타그램 스토리로 공유"
            >
              <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>인스타 스토리로 ›</Text>
            </Pressable>
          )}
        </>
      )}

      {/* ── 사진 시트 — 러너 사진 월 + 갤러리 폴백 ── */}
      <Modal visible={sheetOpen} transparent animationType="slide" onRequestClose={() => setSheetOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,.5)' }} onPress={() => setSheetOpen(false)} />
        <View style={s.sheet}>
          <View style={s.grab} />
          <Text style={[{ fontSize: 19, fontWeight: '900', color: paper.ink }, df]}>사진 고르기</Text>
          <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>
            {runPhotos.length > 0 ? '이 러닝에서 러너가 담아온 순간들이에요' : '이 러닝엔 러너 사진이 없어요 — 갤러리에서 골라주세요'}
          </Text>
          {runPhotos.length > 0 && (
            <View style={s.wallGrid}>
              {runPhotos.slice(0, 9).map((url) => (
                <Pressable key={url} onPress={() => setPhotos((p) => ({ ...p, [sheetKey]: url }))} style={[s.wph, photos[sheetKey] === url && s.wphSel]}>
                  <Image source={{ uri: url }} style={{ width: '100%', height: '100%' }} />
                  {photos[sheetKey] === url && <View style={s.wphTick}><Text style={{ fontSize: 11, fontWeight: '900', color: paper.ink }}>✓</Text></View>}
                </Pressable>
              ))}
            </View>
          )}
          {photoSignFails > 0 && (
            /* [0064] 서명 실패 = 명시적 실패 상태 — 조용히 장수를 줄이지 않는다 */
            /* [D13 FLOOR14 2026-08-12] 13 → 14. 실패 메시지는 반드시 읽혀야 하는 한 종류다. */
            <Text style={{ fontSize: 14, lineHeight: 19, fontWeight: '700', color: '#b4552d', marginTop: 8 }}>
              사진 {photoSignFails}장을 못 불러왔어요 — 시트를 닫았다 다시 열면 재시도해요
            </Text>
          )}
          <Pressable onPress={pickFromGallery} style={s.galBtn}>
            <Text style={{ fontSize: 14, fontWeight: '800', color: colors.dim }}>내 갤러리에서 선택</Text>
          </Pressable>
          <Pressable onPress={confirmPhoto} disabled={!photos[sheetKey]} style={[s.sheetCta, !photos[sheetKey] && { opacity: 0.4 }]}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: colors.volt }}>이 사진으로 만들기 ›</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  // 인스타 버튼 — 인스타의 그라디언트를 흉내내지 않는다 (남의 브랜드 색을 우리 화면에 칠하지 않는다).
  // 우리 코랄 액션 면 + 흰 라벨 (4.84:1). 폭은 액션 바와 같게, 아래에 한 줄로 앉는다.
  igBtn: {
    marginTop: 10, marginHorizontal: 18, paddingVertical: 15, alignItems: 'center',
    backgroundColor: paper.action, borderRadius: 0,
  },
  // [2026-08-12] iTiny/iGiant/iRow 삭제 — 볼트 블록 조판이 RunShareCard로 이사하며 사용처 0이 됐다.
  head: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingTop: 58, paddingHorizontal: 16, paddingBottom: 6 },
  x: { width: 34, height: 34, borderRadius: 17, backgroundColor: '#1d3023', alignItems: 'center', justifyContent: 'center' },
  errBox: { margin: 20, backgroundColor: '#121b14', borderRadius: 16, padding: 24 },
  checker: { position: 'absolute', top: 0, left: 0, right: 0, borderRadius: 20, backgroundColor: '#3f443f', opacity: 0.6 },
  hudL: { fontSize: 9.5, letterSpacing: 2, color: '#e6efe0', fontWeight: '700', textShadowColor: 'rgba(0,0,0,.55)', textShadowRadius: 6, textShadowOffset: { width: 0, height: 1 } },
  hudV: { fontSize: 20, fontWeight: '900', color: '#fff', marginTop: 3, textShadowColor: 'rgba(0,0,0,.55)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  recordT: { fontSize: 14, fontWeight: '900', color: colors.volt, textAlign: 'center', marginTop: 12, textShadowColor: 'rgba(0,0,0,.5)', textShadowRadius: 6, textShadowOffset: { width: 0, height: 1 } },
  noTrace: { position: 'absolute', left: 0, right: 0, textAlign: 'center', fontSize: 14, color: '#8fa093' },
  dogTitle: { fontSize: 24, fontWeight: '900', color: '#fff', textShadowColor: 'rgba(0,0,0,.45)', textShadowRadius: 10, textShadowOffset: { width: 0, height: 2 } },
  scrimBottom: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 190, backgroundColor: 'rgba(10,16,10,.38)' },
  photoEmpty: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', backgroundColor: '#1d3023' },
  // [D13 FLOOR14 2026-08-12] 10 → 14. {report.when} · {report.routeName} — 한글 날짜와 한글 코스명이다
  // (인스타 내보내기 카드 상단). 로고 아트워크가 아니라 데이터다.
  dots: { flexDirection: 'row', gap: 5, justifyContent: 'center', marginTop: 12 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#2c4034' },
  dotOn: { backgroundColor: colors.volt, width: 16 },
  skinName: { fontSize: 14, color: '#5f6f5f', textAlign: 'center', marginTop: 7, fontWeight: '700' },
  actRow: { flexDirection: 'row', gap: 9, paddingHorizontal: 18, marginTop: 'auto', marginBottom: 34 },
  actGhost: { flex: 1, borderWidth: 1.5, borderColor: '#2c4034', borderRadius: 14, alignItems: 'center', paddingVertical: 13 },
  actMain: { flex: 1.4, backgroundColor: colors.volt, borderRadius: 14, alignItems: 'center', paddingVertical: 13 },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 16, paddingBottom: 30 },
  grab: { width: 40, height: 4.5, borderRadius: 3, backgroundColor: '#DCD6C4', alignSelf: 'center', marginBottom: 12 },
  wallGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 12 },
  wph: { width: (W - 32 - 12) / 3, aspectRatio: 1, borderRadius: 10, overflow: 'hidden', backgroundColor: '#DCD6C4' },
  wphSel: { borderWidth: 3, borderColor: colors.volt },
  wphTick: { position: 'absolute', top: 5, right: 5, width: 19, height: 19, borderRadius: 10, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
  galBtn: { marginTop: 10, borderWidth: 1.5, borderColor: '#b9b39f', borderStyle: 'dashed', borderRadius: 12, alignItems: 'center', paddingVertical: 12 },
  sheetCta: { marginTop: 12, backgroundColor: paper.ink, borderRadius: 14, alignItems: 'center', paddingVertical: 14 },
});
