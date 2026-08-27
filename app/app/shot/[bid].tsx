import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Modal, PanResponder, Pressable, ScrollView, Share, StyleSheet, Switch, Text, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';
import { fetchRunReportOrNull, fetchRunStandings, RunReport, RunStandings } from '../../src/lib/api';
import { homePath } from '../../src/components/bottomnav';
import { traceToBox } from '../../src/lib/trace';
import { kstCal } from '../../src/lib/kst';
import { resolveMediaUrl } from '../../src/lib/media';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { colors, paper } from '../../src/theme';
import { pathFrom, RunShareCard, StoryShareCard } from '../../src/components/run-share-card';
import Constants from 'expo-constants';
import { instagramAvailable, shareToInstagramStories } from '../../modules/instagram-share';
import { Icon } from '../../src/components/ui';

// 인증샷 스튜디오 (2026-07-28 확정 스펙) — 공유가 곧 마케팅.
// 스킨 5: S 스토리(채택·기본) · A 트랜스페어런트 · B 포토 · G 폴라로이드 · I 볼트 블록.
//
// [2026-08-26 · round 6] Two changes, and the second one is a privacy fix that
// was live in production-shaped code:
//   1. S 스토리 — the card Sean picked (「share card i like 3 … pace info
//      background is transparent so it's just text overlaid on photo」). It is
//      first in the rail. Its typography and its measured scrim live in
//      `StoryShareCard`; this file only supplies the photo layer and the data.
//   2. 🔴 THE ROUTE IS NO LONGER EXPORTED BY DEFAULT. Every skin in this studio
//      used to draw the GPS trace unconditionally, so every image this screen
//      has ever produced carried the shape of where a dog lives, with nobody
//      having chosen it. There is now one switch (default OFF) and one gate
//      (`exportPts`), and every skin reads the gate.
// 러너 사진이 있으면 B 포토가 2번 슬롯으로 승격. 완성 = 즉시 캡처 + iOS 공유 시트 (재탭 금지).
// 브랜드 디바이스: 아이콘 칩 · 브랜드 테이프 · 워드마크 락업 — 어느 스킨이 돌아다녀도 도그스하이가 남는다.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const W = Dimensions.get('window').width;
const CARD_W = W - 96;
// ⚠ 0.92 → 0.80 (2026-08-26, review N1). The old factor predates the vertical scroller and its
// comment (「화면 안에 액션 바까지」) was already stale. At 0.92 the card block exceeded the
// scroller's viewport on a 375×667, which put the 경로 switch ~100pt below the fold — and the card
// could not be dragged past: PhotoLayer's PanResponder takes the responder on touch-down and
// blocks the native scroll (RCTScrollView's own comment documents this), so the ONLY draggable
// surface was the 48pt side gutters. The control Sean asked for was effectively unreachable on a
// small phone. 0.80 keeps a 9:16-ish story shape while leaving the switch row peeking on every
// size, so the affordance is visible without a drag at all.
const STORY_H = Math.round(CARD_W * (16 / 9) * 0.80);
const FEED_H = Math.round(CARD_W * 1.25);
const GAP = 14;
const SNAP = CARD_W + GAP;

const KST_WEEKDAY = ['일', '월', '화', '수', '목', '금', '토'];

// ⚠ null = 서버가 재지 못했다. 0으로 접지 않는다 — 이 화면이 만드는 것은 앱을 떠나는 PNG이고,
// run-share-card.tsx의 법이 그대로 적용된다: 「아무도 재지 않은 숫자 자리에 대시도 0도 찍지 않는다」.
const fmtDur = (sec: number | null) => (sec == null ? null : `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`);
// ⚠ 대시가 아니라 null — 위 fmtDur와 같은 이유. 대시는 '쟀는데 0'처럼 읽힌다.
const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : null);

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
      {/* [D13 2026-08-12] Logo-artwork exception (DESIGN.md §3) — these two lines are a **mark**,
          not a sentence (5.8/7.7pt at size 24), so the 14pt detail floor does not apply. Taking the
          exception requires a declaration: they are hidden from assistive tech as decoration, and
          not one character of data ever enters here.
          ⚠ The accessible name comes from `Lockup` (:79), THIS FILE's local brand device that wraps
          this chip — not from any shared component. It renders visible 「도그스하이 DOGS HIGH」 with
          no a11y hiding, so a screen reader reads the brand once from the wrapper while the tiny
          mark inside stays silent. That is what makes hiding these two lines correct rather than a
          gap. [2026-08-20] This line used to say "바깥 BrandLockup" — the claim was right but the
          NAME was not: `BrandLockup` was a different, shared component (src/components/brandmark),
          retired when owner-home dropped its wordmarks. It never lived in this file, so the comment
          pointed at a symbol that now resolves to nothing and read as a live dependency to anyone
          grepping. Naming the local `Lockup` makes it true for the first time. */}
      <Text accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={[{ fontSize: size * 0.24, color: colors.neon, fontWeight: '900', lineHeight: size * 0.28 }, df]}>도그스</Text>
      <Text accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={[{ fontSize: size * 0.32, color: colors.neon, fontWeight: '900', lineHeight: size * 0.36, letterSpacing: 1 }, df]}>하이</Text>
    </View>
  );
}

function BrandTape({ width, rotate, df }: { width: number; rotate: string; df: any }) {
  return (
    <View style={{
      width, height: 26, backgroundColor: colors.neon, transform: [{ rotate }],
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
        도그스하이 <Text style={{ color: light ? colors.neon : colors.clubInk }}>DOGS HIGH</Text>
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
//
// [2026-08-26 · round 6] S 스토리 added and placed FIRST — it is the card Sean
// picked (「share card i like 3」). It requires a photo, like G, so it carries
// G's 사진 고르기 door rather than inventing a photoless fallback: ③ has no
// answer for a run with 0 photos, and I 볼트 블록 (the photoless canon) is still
// in the rail for exactly that run.
type SkinKey = 'S' | 'A' | 'Bp' | 'G' | 'I';
const SKIN_META: Record<SkinKey, { name: string; h: number }> = {
  S: { name: '스토리', h: STORY_H },
  A: { name: '투명 스티커', h: STORY_H },
  Bp: { name: '포토', h: STORY_H },
  G: { name: '폴라로이드', h: FEED_H },
  I: { name: '볼트 블록', h: FEED_H },
};

// ── 캡처 배리어 ────────────────────────────────────────────────────────────
// Two animation frames. React committing a tree is not the same event as the
// platform having drawn it, and `captureRef` reads what is DRAWN. Everything
// that reaches captureRef in this file goes through `captureCard`, which waits
// here first — see the long note there for why a privacy control makes this
// mandatory rather than a nicety.
const nextFrame = () => new Promise<void>((res) => requestAnimationFrame(() => res()));

// 이/가 — chosen from the last syllable's final consonant (jongseong). Hangul syllables are
// contiguous from U+AC00; (code - 0xAC00) % 28 === 0 means no final consonant, which takes 가.
// A non-Hangul tail (a digit, a Latin letter) falls back to 가, which is the safer read aloud.
const josaGa = (w: string): string => {
  const ch = w.trim().slice(-1);
  const c = ch.charCodeAt(0);
  if (c < 0xac00 || c > 0xd7a3) return '가';
  return (c - 0xac00) % 28 === 0 ? '가' : '이';
};

// ── 공유 화면의 초록 은퇴 (Sean 2026-08-26: 「remove this green from the shareable screen and make
//    it blue or something」) ──
// colors.volt(#C6F542) → colors.neon(#9F8FFF). 새 헥스 0개: neon 은 theme.ts 가 이미 「네온 엣지·빕
// 넘버·글로우」로 들고 있는 값이라, 어두운 스튜디오 크롬 위에서 volt 가 하던 역할과 같은 자리다.
// 밝은 바탕용 짝인 voltDeep(#7FA818) 은 clubInk(#4A3DA8) 로 간다 — 「읽는」 버전이라는 같은 문법이고,
// 흰 바탕에서 2.79:1 → 8.32:1 로 오히려 크게 나아진다 (voltDeep 은 원래 본문 대비에 못 미쳤다).
//
// ⚠ 측정하고 바꿨다. 어두운 크롬 위 텍스트 14.42:1 → 6.84:1, 채움 위 잉크 14.87:1 → 7.06:1 —
// 둘 다 여유롭게 통과한다. 하지만 **neon 채움 위 흰 글씨는 2.68:1 로 떨어진다**: volt 는 워낙 밝아
// 아무 색이나 얹혀도 됐지만 neon 은 아니다. 채움 위 잉크는 반드시 어두운 색을 유지한다.
export default function ShotStudio() {
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const df = useDisplayFont();
  const nf = useNumFont();
  const [report, setReport] = useState<RunReport | null>(null);
  const [standings, setStandings] = useState<RunStandings | null>(null);
  // Two states, two sentences (2026-08-20). err = the read failed (retryable) · notFound = there
  // is no such run: someone else's booking id, a stale push ref_id, a link with no bid. Pressing
  // again would return the same zero rows, so that state gets an exit instead of a retry.
  // Both used to be one line of `e.message`, and that line was PostgREST's English PGRST116.
  const [err, setErr] = useState(false);
  const [notFound, setNotFound] = useState(false);
  // 스킨별 독립 사진 (2026-07-29) — B에서 사진을 바꿔도 A의 사진·크롭이 유지된다.
  // transform은 PhotoLayer 인스턴스별이고 resetKey가 스킨별 uri이므로, 자기 사진이 바뀔 때만 리셋.
  const [photos, setPhotos] = useState<Record<'S' | 'A' | 'Bp' | 'G', string | null>>({ S: null, A: null, Bp: null, G: null });
  const [sheetOpen, setSheetOpen] = useState(false);
  const sheetFor = useRef<SkinKey>('Bp'); // 어느 스킨이 사진을 요청했나 (확정 시 그 스킨의 사진 모드 on)
  const [photoOn, setPhotoOn] = useState<{ A: boolean; Bp: boolean }>({ A: false, Bp: true });
  const [busy, setBusy] = useState(false);
  const [active, setActive] = useState(0);
  const activeRef = useRef(0); // onScroll compares against this, not the closure's possibly-stale `active`; state stays for render
  const cardRefs = useRef<Record<SkinKey, View | null>>({ S: null, A: null, Bp: null, G: null, I: null });

  // ── 경로 모양 스위치 ── Sean, round 6: 「route trace should be optionally
  // overlaid on the image to export (add a slide button for that)」.
  //
  // 🔴 DEFAULT OFF, AND THAT IS THE LIVE FIX. Before this commit every skin in
  // this studio drew the GPS trace unconditionally, so every image this screen
  // has ever exported carried the route — the shape of where a dog lives — with
  // nobody having chosen it. A toggle that defaulted ON would be the same
  // disclosure wearing a consent label. Off is the state a person has to reach for.
  //
  // What publishes when it is ON is the output of `traceToBox`: real lat/lng
  // projected into a 0..1 aspect-preserved box. Absolute coordinates do not
  // survive that call, so the card carries a silhouette and not a location.
  const [showTrace, setShowTrace] = useState(false);
  // ── 코스 이름 스위치 (Sean, 2026-08-26: 「Make it a switch, like the route」) ──
  // The 볼트 블록 skin printed `report.routeName` into the exported PNG unconditionally, while the
  // new ③ 스토리 skin passed `routeName: null` — the two shipped cards disagreed about whether a
  // place belongs in a published image. The lab's privacy ledger had ruled out 「any location
  // string」 on the same reasoning that made the route opt-in (a place is a location datum even as
  // five characters of Korean), but a NAMED PUBLIC COURSE is not a home, so it was a real question
  // rather than an oversight. Sean's answer is the third door: the person publishing decides.
  // DEFAULT OFF for the same reason the route is — a control that defaults ON publishes for
  // everyone who never finds it, which is the same disclosure wearing a consent label.
  const [showRoute, setShowRoute] = useState(false);
  // Echo of the last COMMITTED value of showTrace — i.e. what the tree the person
  // is looking at actually contains. `captureCard` takes its intent from HERE and
  // not from a handler closure, because two of the share entry points fire from a
  // 450ms setTimeout whose closure is stale by then.
  const committedTrace = useRef(false);
  useEffect(() => { committedTrace.current = showTrace; }, [showTrace]);
  // Same echo for the course name, and for the same reason: the two auto-share paths fire from a
  // 450ms setTimeout whose closure is stale, so intent must come from a post-commit ref.
  const committedRoute = useRef(false);
  useEffect(() => { committedRoute.current = showRoute; }, [showRoute]);

  // What the failure state's 다시 시도 calls — a retry button wired to nothing is a dead button.
  const load = useCallback(() => {
    if (!bid) { setNotFound(true); return; }
    setErr(false);
    setNotFound(false);
    fetchRunReportOrNull(bid)
      .then((r) => { if (r) setReport(r); else setNotFound(true); })
      .catch((e) => { console.warn('[shot] run report:', e?.message ?? e); setErr(true); });
    fetchRunStandings(bid).then(setStandings).catch(() => {});
  }, [bid]);
  useEffect(() => { load(); }, [load]);

  const run = report?.run ?? null;
  // `[]` is NOT a shape. traceToBox drops non-finite points and returns [] when
  // fewer than two survive, so a run whose trace rows are present but unusable
  // used to arrive here as an empty-but-TRUTHY array — and the inline skins below
  // branch on truthiness and then read `pts[0].x`. Collapsing it to null closes
  // that latent crash and keeps the switch honest: no usable shape, no control.
  const pts = useMemo(() => {
    if (!run || run.trace.length < 2) return null;
    const box = traceToBox(run.trace);
    return box.length > 1 ? box : null;
  }, [run]);
  // 🔴 THE ONE GATE. `pts` = does this run HAVE a shape (drives whether the switch
  // is offered at all). `exportPts` = does this CARD carry it. Every skin below
  // reads exportPts and nothing reads `pts` for drawing, so there is exactly one
  // place where the route can enter the exported image, and it is this line.
  const exportPts = showTrace ? pts : null;
  // ONE gate for the course name, read by every skin — the same shape as exportPts. `report`'s own
  // routeName is never read directly by a card again; if it were, a skin could quietly opt itself
  // back in and the switch would be a lie on that card only.
  const exportRouteName = showRoute ? (report?.routeName ?? null) : null;
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
      setPhotos((p) => ({ S: p.S ?? runPhotos[0], A: p.A ?? runPhotos[0], Bp: p.Bp ?? runPhotos[0], G: p.G ?? runPhotos[0] }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runPhotos.length]);

  const order: SkinKey[] = ['S', 'A', 'Bp', 'G', 'I']; // S 스토리 first — it is the picked card
  const activeKey = order[Math.min(active, order.length - 1)];
  // The same key, read LIVE. `activeKey` above is a render value and is correct for
  // rendering; it is wrong for anything that runs later. `pickFromGallery` and
  // `confirmPhoto` both fire `setTimeout(shareNow, 450)`, and in those 450ms the rail
  // can be swiped — so a capture that trusted the closure would hand the share sheet
  // a different card from the one on screen. Same failure the trace barrier exists to
  // prevent, so it gets the same answer: read the ref, not the closure.
  const liveKey = (): SkinKey => order[Math.min(activeRef.current, order.length - 1)];

  // Per-skin photo state — S and G require a photo, A/B are optional (transparent sticker without one)
  const photoKey = (k: SkinKey): 'S' | 'A' | 'Bp' | 'G' => (k === 'I' ? 'Bp' : k); // I takes no photo — defensive mapping
  const hasPhoto = (k: SkinKey) =>
    (k === 'S' && !!photos.S) || (k === 'G' && !!photos.G)
    || (k === 'A' && photoOn.A && !!photos.A) || (k === 'Bp' && photoOn.Bp && !!photos.Bp);
  const isTransparent = (k: SkinKey) => (k === 'A' || k === 'Bp') && !hasPhoto(k);

  // 🔴 THE CARD CARRIES A DATE, NOT A TIME OF DAY.
  // `report.when` is `${dateLabel} ${timeLabel}` (api.ts) — e.g. 「8월 26일 (토) 오후 7:30」.
  // Printing the whole thing publishes the household's habitual walk hour, and it
  // would sit next to an opt-in route silhouette: together they say where and when.
  // The lab's ③/⑤/⑥ show a date only (「DOGS HIGH · 08.26」), so this recomputes the
  // date half from the real instant instead of trusting a display string.
  const cardDate = useMemo(() => {
    if (!report) return '';
    const ms = report.scheduledAtIso ? Date.parse(report.scheduledAtIso) : NaN;
    if (Number.isFinite(ms)) {
      const c = kstCal(ms);
      return `${c.m + 1}월 ${c.d}일 (${KST_WEEKDAY[c.wd]})`;
    }
    // No instant to compute from. Take the date half of the label rather than
    // invent one — `when` runs 「…일 (요일) 오전/오후 …」, so the weekday bracket
    // is the boundary. If even that does not match, print the label unchanged
    // rather than guess at a substring.
    const m = report.when.match(/^(.*?\))/);
    return m ? m[1] : report.when;
  }, [report]);

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
  //
  // 🔴 EVERY captureRef IN THIS FILE GOES THROUGH HERE. It used to be two call
  // sites (the share/save path and the Instagram path), each with its own
  // options and its own error handling. With a privacy switch in the screen that
  // is no longer just duplication: a second capture entry point is a second
  // chance for the exported bytes to disagree with the preview. One door.
  //
  // The barrier before the shot:
  //   1. read the intent from `committedTrace.current` — the last COMMITTED value
  //      — never from the handler's closure. Two of the entry points here are
  //      `setTimeout(shareNow, 450)` after a photo is picked, and their closure is
  //      450ms stale by the time it runs. The committed ref is what the rendered
  //      tree (and therefore the preview the person is looking at) actually says,
  //      so matching the export to IT is the parity property we want.
  //   2. two animation frames — React having committed is not the platform having
  //      drawn, and captureRef reads what is DRAWN.
  //   3. re-check afterwards. If the switch moved while we waited, the bytes we
  //      are about to read might be from either tree, so we THROW instead of
  //      guessing. A wrong export on a privacy control is worse than a failed one,
  //      and a silent fallback here would publish a route someone just switched off.
  const captureCard = async (opts?: { base64?: boolean }): Promise<string> => {
    const traceAtShot = committedTrace.current;
    const routeAtShot = committedRoute.current;
    await nextFrame();
    await nextFrame();
    if (committedTrace.current !== traceAtShot || committedRoute.current !== routeAtShot) {
      throw new Error('공유 설정이 바뀌었어요 — 카드를 확인하고 다시 공유해 주세요');
    }

    // Loaded lazily and separately from the shot, so a missing native module
    // stays distinguishable from a capture that failed for any other reason.
    let VS: any;
    try {
      VS = require('react-native-view-shot');
    } catch {
      throw new Error('__no-view-shot__');
    }
    const ref = cardRefs.current[liveKey()];
    if (!ref) throw new Error('카드를 캡처하지 못했어요');
    // ⚠ [review N4] `useRenderInContext` is REQUIRED now that the card can be scrolled.
    // view-shot's default path is `drawViewHierarchyInRect:afterScreenUpdates:YES`, which renders
    // the hierarchy AS CURRENTLY VISIBLE ON SCREEN — this repo already records that semantic at
    // club/receipt/[bid].tsx:137 (「captureRef는 '지금 화면에 그려진 것'을 찍는다」). Before the
    // vertical scroller the card was always wholly in the window so it never mattered. Now the
    // action bar is PINNED, so a user can scroll the card half out of view and still tap 공유하기 —
    // and a partial render fails SILENTLY (a total one rejects loudly), i.e. a clipped card in
    // someone's story with no error. renderInContext draws the layer tree instead of the screen.
    const uri = await VS.captureRef(ref, {
      format: 'png', quality: 1, useRenderInContext: true,
      ...(opts?.base64 ? { result: 'base64' } : {}),
    });
    if (!uri) throw new Error('카드를 캡처하지 못했어요');
    return uri;
  };

  // Failures render as failures, and as the RIGHT failure. Every capture error used to
  // collapse into '개발 빌드 업데이트 필요', so a card that simply was not ready read as a
  // missing native module. Two causes, two sentences.
  const reportCaptureFailure = (e: unknown, title: string) => {
    const msg = (e as Error)?.message ?? String(e);
    if (msg === '__no-view-shot__') {
      Alert.alert('개발 빌드 업데이트 필요', '카드 캡처(view-shot)는 새 빌드에 포함돼요');
      return;
    }
    Alert.alert(title, msg);
  };

  const capture = async (): Promise<string | null> => {
    try {
      return await captureCard();
    } catch (e) {
      reportCaptureFailure(e, '카드를 만들지 못했어요');
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
      const b64 = await captureCard({ base64: true });
      const appId = (Constants.expoConfig?.extra as any)?.instagramAppId ?? '';
      await shareToInstagramStories(b64, appId);
      haptic('success');
    } catch (e) {
      // 실패를 삼키지 않는다 — 사용자는 공유가 됐다고 믿고 앱을 나간다.
      reportCaptureFailure(e, '인스타 공유 실패');
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
        Alert.alert('저장 완료', isTransparent(liveKey())
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
        {/* 재지 못한 항목은 칸째로 빠진다 — run-share-card.tsx:301의 규칙과 같은 규칙. */}
        {([
          ...(km != null ? [['DISTANCE', `${km}km`]] : []),
          ...(statLine.pace ? [['PACE', statLine.pace]] : []),
          ...(statLine.time ? [['TIME', statLine.time]] : []),
        ] as [string, string][]).map(([l, v]) => (
          <View key={l}>
            <Text style={[s.hudL, !light && { color: '#3d453d', textShadowRadius: 0 }]}>{l}</Text>
            <Text style={[s.hudV, !light && { color: paper.ink, textShadowRadius: 0 }]}>{v}</Text>
          </View>
        ))}
      </View>
    );

    // ── S 스토리 — the picked card (round 6). Photo full-bleed, no plate.
    // Typography, scrim and every contrast number live in StoryShareCard, so the
    // measured floor has exactly one home. What this file supplies is the photo
    // layer a person manipulates, and one answer: does the route go in.
    if (key === 'S') {
      const photo = hasPhoto('S');
      return (
        <StoryShareCard
          width={CARD_W}
          height={h}
          df={df}
          nf={nf}
          photo={photo
            ? <PhotoLayer uri={photos.S!} w={CARD_W} h={h} resetKey={photos.S!} />
            : (
              // 0 photos is a real and common state, so it gets an empty WELL — a glyph,
              // no sentence. The sentence that tells you what to do about it lives
              // OUTSIDE the capture ref (see the rail below), because this subtree is
              // exactly what savePng writes to the photo library: a directive printed
              // here would ship inside someone's story. Same rule as the two 트레이스
              // notices above, and the same reason the checkerboard is drawn outside.
              <View style={s.storyEmpty}>
                <Icon name="Image" glyph="○" size={30} color="#6d6d69" />
              </View>
            )}
          data={{
            dogName: dog,
            km,
            endReason: run.endReason ?? null,
            durationSec: run.durationSec ?? null,
            paceSecPerKm: run.paceSecPerKm ?? null,
            when: cardDate,
            // Not on THIS card. The lab's privacy ledger puts place strings in the
            // NOT-DRAWN list (a course name is a location datum even as a few characters
            // of Korean), and ③ was drawn without one. Passed explicitly as null rather
            // than omitted so the decision is visible at the call site.
            // ⚠ Scope, stated so this does not read as a rule the file then breaks:
            // skin I below still prints `report.routeName`, unchanged and with no
            // switch. That is a shipped card's content, which is Sean's call and not a
            // mechanical follow-through from this slice — it is flagged for his ruling,
            // not silently changed here.
            routeName: exportRouteName,   // was hardcoded null; now the same switch governs both cards
            trace: exportPts,
          }}
        />
      );
    }

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
          {exportPts ? (
            <Svg pointerEvents="none" width={CARD_W} height={h * 0.62} viewBox={`0 0 ${CARD_W} ${h * 0.62}`} style={{ position: 'absolute', top: h * 0.12 }}>
              <Path d={pathFrom(exportPts, CARD_W, h * 0.62, 40)} stroke="rgba(198,245,66,.35)" strokeWidth={15} strokeLinecap="round" strokeLinejoin="round" fill="none" />
              <Path d={pathFrom(exportPts, CARD_W, h * 0.62, 40)} stroke={colors.neon} strokeWidth={6} strokeLinecap="round" strokeLinejoin="round" fill="none" />
              <Circle cx={40 + exportPts[0].x * (CARD_W - 80)} cy={40 + exportPts[0].y * (h * 0.62 - 80)} r={7} fill="#fff" />
              <Circle cx={40 + exportPts[exportPts.length - 1].x * (CARD_W - 80)} cy={40 + exportPts[exportPts.length - 1].y * (h * 0.62 - 80)} r={7} fill={colors.tang} />
            </Svg>
          ) : (
            /* This line is INSIDE the capture ref, so it ships in the PNG. It may therefore
               state a fact about the run (this one has no GPS) and must never state an
               instruction about the UI. "경로가 있는데 꺼져 있다" is a fact about the CONTROL,
               so it lives outside the card, on the switch row — printing it here would put a
               UI directive into someone's Instagram story. */
            pts ? null : <Text style={[s.noTrace, { top: h * 0.4 }]}>GPS 트레이스가 없는 러닝이에요</Text>
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
            {exportPts ? (
              <Svg pointerEvents="none" width={CARD_W} height={h * 0.7} viewBox={`0 0 ${CARD_W} ${h * 0.7}`} style={{ position: 'absolute', top: h * 0.08 }}>
                <Path d={pathFrom(exportPts, CARD_W, h * 0.7, 16)} stroke="#fff" strokeWidth={7} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                <Circle cx={16 + exportPts[0].x * (CARD_W - 32)} cy={16 + exportPts[0].y * (h * 0.7 - 32)} r={7} fill={colors.neon} />
                <Circle cx={16 + exportPts[exportPts.length - 1].x * (CARD_W - 32)} cy={16 + exportPts[exportPts.length - 1].y * (h * 0.7 - 32)} r={7} fill={colors.tang} />
              </Svg>
            ) : (
              /* This line is INSIDE the capture ref, so it ships in the PNG. It may therefore
               state a fact about the run (this one has no GPS) and must never state an
               instruction about the UI. "경로가 있는데 꺼져 있다" is a fact about the CONTROL,
               so it lives outside the card, on the switch row — printing it here would put a
               UI directive into someone's Instagram story. */
            pts ? null : <Text style={[s.noTrace, { top: h * 0.4 }]}>GPS 트레이스가 없는 러닝이에요</Text>
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
          {exportPts && (
            <Svg pointerEvents="none" width={110} height={120} viewBox="0 0 110 120" style={{ position: 'absolute', top: 66, right: 16 }}>
              <Path d={pathFrom(exportPts, 110, 120, 8)} stroke="#fff" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" fill="none" opacity={0.95} />
              <Circle cx={8 + exportPts[0].x * 94} cy={8 + exportPts[0].y * 104} r={4.5} fill={colors.neon} />
              <Circle cx={8 + exportPts[exportPts.length - 1].x * 94} cy={8 + exportPts[exportPts.length - 1].y * 104} r={4.5} fill={colors.tang} />
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
              {exportPts && (() => {
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
                    <Path d={pathFrom(exportPts, TW, TH, 14)} stroke="rgba(15,29,19,.45)" strokeWidth={9} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                    <Path d={pathFrom(exportPts, TW, TH, 14)} stroke={colors.neon} strokeWidth={4.5} strokeLinecap="round" strokeLinejoin="round" fill="none" />
                    <Circle cx={14 + exportPts[0].x * (TW - 28)} cy={14 + exportPts[0].y * (TH - 28)} r={5.5} fill="#fff" />
                    <Circle cx={14 + exportPts[exportPts.length - 1].x * (TW - 28)} cy={14 + exportPts[exportPts.length - 1].y * (TH - 28)} r={5.5} fill={colors.tang} />
                  </Svg>
                );
              })()}
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 9 }}>
              <IconChip size={28} df={df} />
              <Text numberOfLines={2} style={{ flex: 1, fontSize: 15, fontWeight: '800', color: paper.ink, fontStyle: 'italic' }}>
                {/* ⚠ km이 null이면 「강아지, km 완주!!」가 그대로 PNG에 찍힌다 — 사라지는 것은 숫자뿐,
                    단위와 주장은 남는다. 완주도 거리가 아니라 endReason으로 판정한다 (codex). */}
                {dog}{km != null ? `, ${km}km` : ''}{run.endReason === 'completed' ? ' 완주!!' : ''} <Text style={{ fontSize: 15, color: '#5B594A' }}>{report.when.split(' ')[0]} {report.when.split(' ')[1]} · 도그스하이</Text>
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
          endReason: run.endReason ?? null,
          durationSec: run.durationSec ?? null,
          paceSecPerKm: run.paceSecPerKm ?? null,
          when: report.when,
          routeName: exportRouteName,   // gated — never report.routeName directly (see exportRouteName)
          trace: exportPts,
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
  // S and G both require a photo, so both send the main button to the picker
  // rather than exporting a card with a labelled hole in it.
  const needsPhotoNow = (activeKey === 'G' && !photos.G) || (activeKey === 'S' && !photos.S);
  const mainLabel = busy ? '만드는 중...' : needsPhotoNow ? '사진 고르기 ›' : t ? '투명 PNG 저장' : '공유하기 ›';
  const onMain = needsPhotoNow ? () => openSheet(activeKey) : t ? savePng : shareNow;
  const [ghostLabel, onGhost] =
    activeKey === 'A'
      ? hasPhoto('A') ? ['사진', () => photoMenu('A')] as const : ['사진 위에 올리기', () => openSheet('A')] as const
      : activeKey === 'Bp'
        ? hasPhoto('Bp') ? ['사진', () => photoMenu('Bp')] as const : ['사진 넣기', () => openSheet('Bp')] as const
        : activeKey === 'S' && photos.S
          ? ['사진 변경', () => openSheet('S')] as const
          : activeKey === 'G' && photos.G
            ? ['사진 변경', () => openSheet('G')] as const
            : ['이미지 저장', savePng] as const;

  return (
    <View style={{ flex: 1, backgroundColor: '#0C130E' }}>
      {/* 헤더 */}
      <View style={s.head}>
        {/* ⚠ Guarded, because a bare router.back() is a NO-OP here. This screen is reachable by
            deep link and from a share sheet, both of which can give it a single-entry stack — and
            the root Stack is headerShown:false + gestureEnabled:false, so with a dead ✕ there is
            no way out of the screen at all. The not-found state below already carries its own
            always-walkable door for exactly this reason; the LOADED screen needed the same. Same
            idiom as cards.tsx and owner/live.tsx. */}
        <Pressable
          onPress={() => (router.canGoBack() ? router.back() : router.replace(homePath()))}
          style={s.x} accessibilityRole="button" accessibilityLabel="닫기"
        ><Text style={{ fontSize: 17, color: '#8fa093' }}>✕</Text></Pressable>
        <Text style={[{ fontSize: 19, fontWeight: '900', color: '#fff' }, df]}>인증샷</Text>
        <View style={{ width: 34 }} />
      </View>

      {err && (
        <View style={s.errBox}>
          <Text style={s.errTxt}>기록을 불러오지 못했어요</Text>
          <Pressable onPress={load} style={s.errBtn} accessibilityRole="button">
            <Text style={s.errBtnTxt}>다시 시도</Text>
          </Pressable>
        </View>
      )}
      {notFound && (
        <View style={s.errBox}>
          <Text style={s.errTxt}>이 러닝을 찾을 수 없어요</Text>
          {/* The ✕ is router.back(), which does nothing on a deep-link cold start (no stack to
              pop). This state therefore carries its own always-walkable door, role-aware. */}
          <Pressable onPress={() => router.replace(homePath())} style={s.errBtn} accessibilityRole="button">
            <Text style={s.errBtnTxt}>홈으로</Text>
          </Pressable>
        </View>
      )}
      {!err && !notFound && report && !run && (
        <View style={s.errBox}><Text style={{ fontSize: 15, color: '#8fa093', textAlign: 'center' }}>러닝이 끝나면 인증샷을 만들 수 있어요</Text></View>
      )}

      {report && run && (
        <>
          {/* ⚠ VERTICAL SCROLLER, added 2026-08-26 with the 경로 switch.
              This column is taller than a phone. `STORY_H`'s 0.92 factor was tuned so
              the card plus the action bar just fit, and that budget had no room left
              for a control: adding the switch row pushed 인스타 스토리로 off a 844pt
              screen and the PRIMARY action bar off a 667pt one — and with no scroller
              there was nothing to scroll, so the buttons were simply unreachable.
              (`marginTop:'auto'` on the action row cannot rescue it: once the column
              overflows there is no free space for an auto margin to take.)
              The fix keeps the actions OUTSIDE the scroller so they are always on
              screen, and lets the card + switch scroll under them. `flexShrink` on the
              scroller is what lets it give up height instead of pushing. */}
          <ScrollView
            style={{ flex: 1, flexShrink: 1 }}
            contentContainerStyle={{ flexGrow: 1, justifyContent: 'center' }}
            // review N2: the indicator is the ONLY hint that the switch exists below the card.
            showsVerticalScrollIndicator
          >
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            snapToInterval={SNAP}
            decelerationRate="fast"
            disableIntervalMomentum
            contentContainerStyle={{ paddingHorizontal: (W - CARD_W) / 2, gap: GAP, alignItems: 'center' }}
            onScroll={(e) => {
              const i = Math.min(order.length - 1, Math.max(0, Math.round(e.nativeEvent.contentOffset.x / SNAP)));
              if (i !== activeRef.current) { activeRef.current = i; setActive(i); haptic('light'); }
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
                  {/* Preview-only, and deliberately OUTSIDE the ref above: it tells the
                      person what the empty well needs, and it must never reach the PNG. */}
                  {key === 'S' && !photos.S && (
                    <View pointerEvents="none" style={s.storyHint}>
                      <Text style={s.storyHintTxt}>사진을 고르면 카드가 완성돼요</Text>
                    </View>
                  )}
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

          {/* ── 경로 모양 스위치 (round 6, ⑤/⑥) ──
              Drawn ONLY when this run actually has a shape to offer. A switch on a
              run with no GPS would be a control that changes nothing — a dead
              button with a knob on it.
              It sits under the card and above the actions because that is where
              the decision is real: the card is on screen, and flipping this
              changes what the person is looking at. The finish screen cannot host
              it — nobody has seen the card yet at that moment. */}
          {pts && (
            <View style={s.swRow}>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.swTitle}>경로 모양 넣기</Text>
                {/* The state sentence is the row's OWN body rather than a second line
                    below it (as the lab drew ⑤). One box says the same thing in a
                    column that is already taller than a phone — see the scroller above. */}
                <Text style={s.swBody}>
                  {/* review N3: OFF is where everyone starts and where the choice is made, so it
                      must carry the privacy fact (좌표는 빠지고 모양만), not only the state. The
                      merged one-liner had dropped it from exactly that moment. */}
                  {showTrace
                    ? '켜짐 — 좌표는 빠지고 모양만 들어가요.'
                    : '꺼짐 — 지금은 경로가 안 들어가요 · 켜도 좌표는 빠지고 모양만 들어가요.'}
                </Text>
              </View>
              <Switch
                value={showTrace}
                // Locked while a capture is in flight. Flipping mid-shot is caught by
                // captureCard's re-check and fails closed, but a control that answers
                // an intentional tap with an error is worse than one that waits.
                disabled={busy}
                onValueChange={(v) => { setShowTrace(v); haptic('light'); }}
                accessibilityLabel="카드에 경로 모양 넣기"
                trackColor={{ false: '#2c4034', true: paper.action }}
                thumbColor="#FFFFFF"
                ios_backgroundColor="#2c4034"
              />
            </View>
          )}

          {/* ── 코스 이름 스위치 (Sean 2026-08-26: 「Make it a switch, like the route」) ──
              Same rules as the route switch above, for the same reasons: drawn ONLY when this run
              has a course name to offer (a switch that changes nothing is a dead button with a
              knob on it), default OFF, locked during a capture, and its intent read from a
              post-commit ref so a 450ms auto-share cannot publish a stale answer.
              ⚠ This governs BOTH cards. Before it, 볼트 블록 printed the course name into every
              export and ③ 스토리 hardcoded it to null — two shipped cards disagreeing about
              whether a place belongs in a published image. */}
          {!!report?.routeName && (
            <View style={s.swRow}>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.swTitle}>코스 이름 넣기</Text>
                <Text style={s.swBody}>
                  {showRoute
                    // ⚠ Korean particle: 「이」 is for a consonant-final noun. Course names end
                    // in anything, so the particle is chosen from the last syllable's jongseong —
                    // 「코스」 takes 가, 「길」 takes 이. Hardcoding either is wrong half the time,
                    // and it is the kind of wrong that reads as machine-written.
                    ? `켜짐 — 카드에 「${report.routeName}」${josaGa(report.routeName)} 들어가요.`
                    : '꺼짐 — 어디서 달렸는지는 안 들어가요 · 켜면 코스 이름이 보여요.'}
                </Text>
              </View>
              <Switch
                value={showRoute}
                disabled={busy}
                onValueChange={(v) => { setShowRoute(v); haptic('light'); }}
                accessibilityLabel="카드에 코스 이름 넣기"
                trackColor={{ false: '#2c4034', true: paper.action }}
                thumbColor="#FFFFFF"
                ios_backgroundColor="#2c4034"
              />
            </View>
          )}

          {/* Lab ③/⑤/⑥ carry this line and it was missing. It is a claim, so it has to
              be true, and it is: 공유하기 hands the PNG to the OS sheet, 인스타 스토리로
              opens Instagram's own composer, 이미지 저장 writes to this phone. Nothing
              in this screen posts anything anywhere by itself. */}
          <Text style={s.privLine}>내 기기에서만 저장·전송돼요 — 앱이 대신 올리지 않아요.</Text>
          </ScrollView>

          {/* 액션 바 — outside the scroller, so it is reachable on every screen size. */}
          <View style={s.actRow}>
            <Pressable onPress={onGhost} disabled={busy} style={[s.actGhost, busy && { opacity: 0.5 }]}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: '#b8c4ae' }}>{ghostLabel}</Text>
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
              /* [Sean 2026-08-26 press behaviour] filled primary = a physical key: 4px lip at
                 rest, translateY(3) + 1px pressed. Busy keeps the lip and loses only the travel
                 (PaperBtn's predicate) — the button is mid-send, not dead. */
              style={({ pressed }) => [
                s.igBtn,
                busy && { opacity: 0.6 },
                pressed && !busy
                  ? { backgroundColor: paper.actionPressed, transform: [{ translateY: 3 }], borderBottomWidth: 1, borderBottomColor: paper.actionPressed }
                  : { borderBottomWidth: 4, borderBottomColor: paper.actionPressed },
              ]}
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
          <Text style={{ fontSize: 15, color: colors.dim, marginTop: 3 }}>
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
            /* [D13 FLOOR14 2026-08-12 · FLOOR15 2026-08-27] 13 → 14 → 15. 실패 메시지는 반드시 읽혀야 하는 한 종류다. */
            <Text style={{ fontSize: 15, lineHeight: 19, fontWeight: '700', color: '#b4552d', marginTop: 8 }}>
              사진 {photoSignFails}장을 못 불러왔어요 — 시트를 닫았다 다시 열면 재시도해요
            </Text>
          )}
          <Pressable onPress={pickFromGallery} style={s.galBtn}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: colors.dim }}>내 갤러리에서 선택</Text>
          </Pressable>
          <Pressable onPress={confirmPhoto} disabled={!photos[sheetKey]} style={[s.sheetCta, !photos[sheetKey] && { opacity: 0.4 }]}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: colors.neon }}>이 사진으로 만들기 ›</Text>
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
  errTxt: { fontSize: 15, color: '#8fa093', textAlign: 'center' },
  // Same border as this screen's own dark ghost button (actGhost) — 44pt touch target.
  errBtn: {
    marginTop: 14, minHeight: 44, justifyContent: 'center', alignItems: 'center',
    borderWidth: 1.5, borderColor: '#2c4034', borderRadius: 14, paddingHorizontal: 18,
  },
  errBtnTxt: { fontSize: 15, fontWeight: '800', color: '#e6efe0' },
  checker: { position: 'absolute', top: 0, left: 0, right: 0, borderRadius: 20, backgroundColor: '#3f443f', opacity: 0.6 },
  hudL: { fontSize: 9.5, letterSpacing: 2, color: '#e6efe0', fontWeight: '700', textShadowColor: 'rgba(0,0,0,.55)', textShadowRadius: 6, textShadowOffset: { width: 0, height: 1 } },
  hudV: { fontSize: 20, fontWeight: '900', color: '#fff', marginTop: 3, textShadowColor: 'rgba(0,0,0,.55)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  recordT: { fontSize: 15, fontWeight: '900', color: colors.neon, textAlign: 'center', marginTop: 12, textShadowColor: 'rgba(0,0,0,.5)', textShadowRadius: 6, textShadowOffset: { width: 0, height: 1 } },
  noTrace: { position: 'absolute', left: 0, right: 0, textAlign: 'center', fontSize: 15, color: '#8fa093' },
  dogTitle: { fontSize: 24, fontWeight: '900', color: '#fff', textShadowColor: 'rgba(0,0,0,.45)', textShadowRadius: 10, textShadowOffset: { width: 0, height: 2 } },
  scrimBottom: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 190, backgroundColor: 'rgba(10,16,10,.38)' },
  photoEmpty: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', backgroundColor: '#1d3023' },
  // [D13 FLOOR14 2026-08-12 · FLOOR15 2026-08-27] 10 → 14 → 15. {report.when} · {report.routeName} — 한글 날짜와 한글 코스명이다
  // (인스타 내보내기 카드 상단). 로고 아트워크가 아니라 데이터다.
  dots: { flexDirection: 'row', gap: 5, justifyContent: 'center', marginTop: 12 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#2c4034' },
  dotOn: { backgroundColor: colors.neon, width: 16 },
  skinName: { fontSize: 15, color: '#5f6f5f', textAlign: 'center', marginTop: 7, fontWeight: '700' },
  // S 스토리's 0-photo state. A labelled bind, on this file's canonical dark
  // (paper.ink) so the scrim and its measured contrast still hold above it.
  storyEmpty: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
    alignItems: 'center', justifyContent: 'center', gap: 10, backgroundColor: paper.ink,
  },
  // The hint that belongs to the empty well but must not be captured with it.
  // ⚠ [device-verified 2026-08-26] `top:'58%'` COLLIDED with the display line — on the simulator
  // 「사진을 고르면 카드가 완성돼요」 sat directly on top of 「초코, 오늘 0km」, both unreadable.
  // A code read called it 「slightly crowded, not a defect」; the screen disagreed, which is why the
  // sim pass exists. The hint now hangs off the GLYPH (which is centred in the empty well) with a
  // fixed offset, instead of a percentage of the whole card that drifts into the bottom-pinned type
  // block as the card grows. `bottom` is measured from the type block's top edge, so it can never
  // reach it regardless of card height or dog-name wrap.
  storyHint: { position: 'absolute', left: 0, right: 0, top: '50%', marginTop: 30, alignItems: 'center' },
  storyHintTxt: { fontSize: 15, lineHeight: 21, color: '#b8b8b4', fontWeight: '700' },
  // 경로 스위치 — a control, so it carries a control's marks: ≥56pt row, its own
  // edge, a state word that is never ambiguous. Korean at the 15pt floor.
  swRow: {
    flexDirection: 'row', alignItems: 'center', gap: 14, minHeight: 56,
    marginHorizontal: 18, marginTop: 14, paddingHorizontal: 14, paddingVertical: 12,
    borderWidth: 1.5, borderColor: '#2c4034', borderRadius: 14,
  },
  swTitle: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: '#e6efe0' },
  swBody: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: '#8fa093', marginTop: 3 },
  privLine: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: '#8fa093', marginHorizontal: 18, marginTop: 14 },
  actRow: { flexDirection: 'row', gap: 9, paddingHorizontal: 18, marginTop: 12, marginBottom: 34 },
  actGhost: { flex: 1, borderWidth: 1.5, borderColor: '#2c4034', borderRadius: 14, alignItems: 'center', paddingVertical: 13 },
  actMain: { flex: 1.4, backgroundColor: colors.neon, borderRadius: 14, alignItems: 'center', paddingVertical: 13 },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 16, paddingBottom: 30 },
  grab: { width: 40, height: 4.5, borderRadius: 3, backgroundColor: '#DCD6C4', alignSelf: 'center', marginBottom: 12 },
  wallGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 12 },
  wph: { width: (W - 32 - 12) / 3, aspectRatio: 1, borderRadius: 10, overflow: 'hidden', backgroundColor: '#DCD6C4' },
  wphSel: { borderWidth: 3, borderColor: colors.neon },
  wphTick: { position: 'absolute', top: 5, right: 5, width: 19, height: 19, borderRadius: 10, backgroundColor: colors.neon, alignItems: 'center', justifyContent: 'center' },
  galBtn: { marginTop: 10, borderWidth: 1.5, borderColor: '#b9b39f', borderStyle: 'dashed', borderRadius: 12, alignItems: 'center', paddingVertical: 12 },
  sheetCta: { marginTop: 12, backgroundColor: paper.ink, borderRadius: 14, alignItems: 'center', paddingVertical: 14 },
});
