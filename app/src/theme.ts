// 도그스하이 design tokens — 2026-07-28 리브랜드 리프레시 (rebrand.md)
// 브랜드 = athletic editorial: 숫자는 애슬레틱하게(코랄·900·크게), 순간은 따뜻하게(크림·사진).
// 러너스하이(5음절)의 강아지 버전 — '하이'가 히어로 음절: 하이 포인트 · 오늘의 하이 · 하이 찍다.
export const colors = {
  ink: '#171A17',
  forest: '#0F1D13',     // 딥 포레스트 (구 #132117 — 리프레시로 심화)
  cream: '#FFFFFF',      // [V4] 페이퍼 — 베이지 박멸 (구 #F8F6F0). 이름은 호환 유지, 값은 종이
  volt: '#C6F542',       // 크림 위 발색 보정 (구 #B9F23A)
  voltDeep: '#7FA818',
  voltBright: '#d4ff66',
  tang: '#FF5C3D',       // 코랄 펀치 업 (구 #FF6347) — 도파민 숫자·라이브 전용
  coralText: '#d84a2f',  // 읽는 코랄 — 경고·조기종료 텍스트 (tang의 텍스트 버전, 의도적 2단)
  // ── live-run surface role token (runner/run.tsx only) ──
  // Sean 2026-08-24, verbatim: "Runner run's b screen I can't see the map; not much space for
  // it, but this is important as the runner needs to see where to go at all times. I like 6 and
  // it's #ff5c3e as well."
  // ROLE, not hue: the live run's own accent — the progress fill the runner watches while the
  // record is running, and the single remaining door in the ceiling frame (lab ⑥). Named for the
  // surface it belongs to so a future pass cannot re-use it as a general coral.
  // ⚠ It sits 1/255 from `tang` (#FF5C3D) and is NOT a duplicate by accident — Sean named this
  //   exact value for this surface. Do not "dedupe" it into tang without his word.
  // Measured white label on this fill: 3.06:1 → large bold labels only (19.5/800, the end CTA).
  //   Small white text still needs an ink plate (§3 plate law).
  runLive: '#FF5C3E',
  card: '#ffffff',
  clay: '#EFF1EC',       // [V4] 쿨 그레이 웰 (구 베이지 #EDE8DA)
  line: '#D8DAD2',       // [V4] 쿨 헤어라인 (구 베이지 #DCD6C4) — 굵은 구조는 ink 2.5px 룰
  border: '#D8DAD2',     // line과 동치
  green: '#5a7a3c',      // 기능 그린 — 라벨·강조 (volt의 텍스트 버전, 대비 우선이라 유지)
  dim: '#586055',        // [V4] 쿨 딤 (구 웜 #5B594A)
  // 하이클럽 컬러 월드 (2026-07-29 Sean 확정 C1 바이올렛) — 클럽 vs 개인 분리:
  // 개인(예약·러닝·인증샷)=볼트 그린, 클럽=바이올렛. 다른 신호색(탱·앰버·블루)과 불충돌.
  club: '#7B6CDF',       // 프라이머리 — CTA·스텁·링
  clubDeep: '#5A4BC7',   // 그라디언트 딥 엔드·프레스드
  clubInk: '#4A3DA8',    // 읽는 바이올렛 — 라벨·텍스트 (coralText와 같은 2단 문법)
  clubTint: '#EFECFF',   // 틴트 — 칩·하이라이트 행 배경
  clubNight: '#3A2F86',  // 다크 스트립 그라디언트 스타트
  // D1×D2 하이브리드 (Sean 확정 — 클럽 = 나이트 스텁 × 레이스 프로그램, 샤프 코너)
  nightBg: '#0D0A1E',    // 클럽 화면 스테이지
  nightCard: '#14102B',  // 티켓 카드
  nightEdge: '#2A2350',  // 카드 보더·룰 라인
  nightDim: '#8F86C2',   // 보조 텍스트
  neon: '#9F8FFF',       // 네온 엣지·빕 넘버·글로우
  // 기록 골드 (P3) — PB·마일스톤 전용. 희소 운용이 생명: 일상은 볼트, 사건만 골드
  gold: '#D9A93C',
  goldDeep: '#B8860B',   // 읽는 골드 — 텍스트·소인 잉크
  goldTint: '#FBF3DD',
  // 샵 테라코타 (P5) — 리테일 온도 분리: 샵은 서비스가 아니라 부티크
  terra: '#C96F4A',
  terraDeep: '#A85536',
  terraInk: '#6B3A24',    // 읽는 테라 — 제목·가격
  terraTint: '#FBEEE7',
  terraCraft: '#F8F0E7',  // 크래프트 종이 배경 — 샵 화면 전용 bg
  // dark glow theme (owner home / cards)
  bgDark: '#0C130E',
  cardDark: '#0F1D13',
  lineDark: '#24352a',
  dimDark: '#8fa093',
} as const;

// ═══ 클럽 위탁 = 테일러드 라일락 (2026-08-01 디자인 페이즈 완결 — delegation-premium-refresh2 정본) ═══
// 공식: 크리스프 코너 + 소프트 라이트. 나이트 월드(nightBg 등)는 위탁 표면에서 은퇴 — 점진 교체.
// 포일 예산: 홀로=모노그램+티켓 엣지만 · 골드=SETTLED 전용 · 사진법: 콘텐츠 5슬롯, 월페이퍼 금지.
export const lilac = {
  // ⚠ PALE MEMBERS RETIRED — Sean 2026-08-25, twice in one round: "i like the accent color, not
  // the pale color; product wide and mock wide" (scope) and "white backgrounds" (the replacement
  // ground, ratified round 4). DESIGN.md §2's pale-lilac amendment is the spec. The four pale
  // members below become the paper world's neutrals; NO new hex enters the palette — every
  // replacement is a value the system already ships (#FFFFFF = paper.canvas · #F2F2F2 =
  // paper.disabledFill's value, the only neutral FILL the paper world owns · #EEEEEE = the paper
  // chrome grammar's neutral card line, DESIGN.md §2 "cards separate with neutral #EEE 1px").
  // Old values kept here on purpose — supersede, don't erase.
  bg: '#FFFFFF',        // [2026-08-25 pale retirement] 구 #F4F2FB — 캔버스는 순백. 새벽빛 워시(dawn*)는 화면별 오버레이로 남는다
  card: '#FFFFFF',
  inset: '#F2F2F2',     // [2026-08-25 pale retirement] 구 #EFECF9 — 필드·웰은 뉴트럴 (paper.disabledFill과 같은 값, 역할 토큰은 별개)
  hair: '#EEEEEE',      // [2026-08-25 pale retirement] 구 #E6E2F4 — 헤어라인 법 유지, 색만 뉴트럴 (페이퍼 크롬의 #EEE)
  hair2: '#F2F2F2',     // [2026-08-25 pale retirement] 구 #EDEAF8 — 이중 프레임 안쪽 선 (hair보다 한 단 옅게 유지)
  head: '#221E3D',      // 제목 잉크
  text: '#4B4668',
  // ⚠ MEASURED on the new white ground (WCAG 2.x relative luminance, 2026-08-25 sweep):
  // #7C76A0 on #FFFFFF = 4.24:1 — the ground change IMPROVED it (3.82 on the old #F4F2FB) but it
  // still sits under the 4.5 body floor. It is a pre-existing failure the sweep did not create and
  // could not clear without changing an ink Sean listed as a KEEP; report.tsx:1212 already routes
  // around it (units use `text`, not `dim`). The only sanctioned fix is paper.dim #666666 (5.74 on
  // white) — flagged for Sean rather than taken, because it repaints every lilac caption at once.
  dim: '#7C76A0',      // [Sean] 디테일 회색 한 단계 진하게 — 가독 (구 #928DAD)
  accent: '#6C5CE7',    // 바이올렛 — 마스트 룰·셸 인디케이터·섹션 넘버·링크 (예산제)
  accentDeep: '#7867EC',
  coral: '#F0765A',     // CTA·봉인·라이브 도트
  coralDeep: '#E45F41',
  coralSoft: '#FFDCD1',
  amber: '#C77414', amberSoft: '#FBEED9', amberEdge: '#F2DFC2',
  voltDeep: '#5E7F0E', voltFill: '#EAF6C8',
  tang: '#E8552F',      // 크리티컬 잉크
  gold: '#B99A4F', goldSoft: '#F4EBD3', goldSheen: '#D8C185',
  glass: 'rgba(255,255,255,0.62)',      // 글래스 크롬 (마스트헤드·셸·도크)
  glassEdge: 'rgba(255,255,255,0.85)',
  dawnCoral: 'rgba(240,118,90,0.11)',   // 새벽빛 블룸
  dawnViolet: 'rgba(108,92,231,0.09)',
} as const;
// 크리스프 라디우스 스케일 — phone 14 · card 8 · inner 6 · btn 8 · tag 5 · 문서 2 · 원형만 예외
export const lilacRadius = { screen: 14, card: 8, inner: 6, btn: 8, tag: 5, doc: 2 } as const;
// 소프트 레이어드 섀도 (하드 블랙 오프셋 은퇴)
export const lilacShadow = {
  shadowColor: '#1C1837', shadowOpacity: 0.09, shadowRadius: 14,
  shadowOffset: { width: 0, height: 6 }, elevation: 3,
} as const;

// 강아지 칼라 컬러 팔레트 (P1, 0033) — 키는 DB(dogs.collar), 값은 여기가 단일 소스.
// 규칙: 시스템 신호색(볼트·탱·앰버·블루·바이올렛)과 '같은 값'은 피한다 — 칼라는 퍼스널, 신호는 시스템.
export const collarColors = {
  tangerine: '#FF8A5C', sky: '#5BB8D4', rose: '#E58BA9', violet: '#9B8CE8',
  gold: '#E0B457', teal: '#3EC6A8', moss: '#8AA84E', berry: '#C25E7F',
} as const;
export type CollarKey = keyof typeof collarColors;
export const collarLabels: Record<CollarKey, string> = {
  tangerine: '탠저린', sky: '스카이', rose: '로즈', violet: '바이올렛',
  gold: '골드', teal: '틸', moss: '모스', berry: '베리',
};

// 디스플레이 서체 — Black Han Sans (src/lib/displayFont.ts의 useDisplayFont로 지연 로드).
// 규칙: 화면당 1회(히어로 카피·브랜드 워드마크)만. 로드 실패 시 시스템 900 폴백.
export const DISPLAY_FONT = 'BlackHanSans_400Regular' as const;
// [V4] 숫자 서체 — Oswald (애슬레틱 컨덴스드, 레이스 빕의 서체). src/lib/fonts.ts의 useNumFont로 지연 로드
export const NUM_FONT = 'Oswald_600SemiBold' as const;
// [V4] 본문 서체 — IBM Plex Sans KR (시스템 폰트 은퇴). useBodyFont/useBodyBold로 지연 로드
export const BODY_FONT = 'IBMPlexSansKR_400Regular' as const;
export const BODY_FONT_BOLD = 'IBMPlexSansKR_700Bold' as const;

export const radius = { card: 6, btn: 6, chip: 4 } as const; // [V4] 샤프 — 소프트 코너 은퇴
// Global gutter — one value for screen side padding. [2026-08-10 폴리시 패스, Sean]
// 15 supersedes the 2026-07-28 "0.9x" 11: the audit found ZERO screens actually
// imported this token (real gutters ran 11/13/14/16), so 15 is the first enforced
// value, wired into the seven audited screens. login's spacious 28 stays local.
export const layout = { gutter: 15 } as const;

// 타이포 스케일 — 규칙: 900은 오직 숫자(display)와 화면 제목(title)에만.
// 본문·라벨이 전부 900이면 위계가 무너진다 (ui-audit). 새 코드는 이 프리셋을 쓸 것.
// [2026-08-10] label/caption raised to the 14pt detail floor (DESIGN.md §3 — they
// predated the 2026-08-06 floor law), body 15.5→16, button labels ≥16 (PaperBtn).
export const type = {
  display: { fontSize: 48.5, fontWeight: '900', fontVariant: ['tabular-nums'] } as const, // 큰 숫자 전용
  numeric: { fontSize: 25.5, fontWeight: '900', fontVariant: ['tabular-nums'] } as const, // 중간 숫자
  title: { fontSize: 24, fontWeight: '900' } as const,   // 화면 제목
  heading: { fontSize: 16.5, fontWeight: '800' } as const, // 섹션/카드 제목
  body: { fontSize: 16, fontWeight: '600' } as const,
  // ⚠ 15, not 14, and the two were 14 until 2026-08-27. The Korean detail floor was raised to
  // 15 on 2026-08-25 (DESIGN.md:145) and these presets were missed by that sweep — they had ZERO
  // importers, so no shipped screen was under the floor THROUGH them and nothing went red. That
  // is exactly what made them worth fixing: theme.ts tells new code to reach for these presets,
  // so the trap was not a screen that renders too small today, it was the first screen that
  // obeys the instruction tomorrow. A dead export is the cheapest possible thing to correct and
  // the most expensive thing to discover later.
  label: { fontSize: 15, fontWeight: '700' } as const,
  caption: { fontSize: 15, fontWeight: '400' } as const,
} as const;

// Surface palettes for themed screens (home, cards). Toggled by ThemeProvider.
export type ThemeMode = 'dark' | 'light';

export const surfaces = {
  dark: {
    bg: colors.bgDark,
    card: colors.cardDark,
    line: colors.lineDark,
    chip: '#1e2c22',
    track: '#233827',
    dim: colors.dimDark,
    textStrong: '#ffffff',
    textSoft: colors.cream,
    nav: true,
  },
  light: {
    bg: colors.cream,
    card: '#ffffff',
    line: colors.line,
    chip: '#EFF1EC',
    track: '#E2E6DE',
    dim: colors.dim,
    textStrong: colors.ink,
    textSoft: '#3d453d',
    nav: false,
  },
} as const;

// ═══ 순백/코랄 — 전역 라이트 캔버스 (2026-08-06 Sean 확정, 디자인 샷건 pick ①) ═══
// 법: 캔버스 #FFFFFF · 잉크 램프 대비 하한(캔버스 기준) head ≥12:1 / text ≥7:1 / dim ≥4.5:1 ·
//   faint는 장식 클래스(레터스페이스 캡스 키커) 전용 · 헤어라인 = 솔리드 코랄 1px, 불투명도 금지,
//   풀블리드(라인이 화면 끝까지, 사이드 마진 금지) · 샤프 코너 · 강조 예산 = 코랄 라인 + CTA 1개 ·
//   버튼 상태는 불투명도 트릭 금지, 명시 색으로. 스타일 프리즈: 유료견 50마리까지 신규 미학 금지.
// 다크 세리머니 월드(패스포트·클럽·씰)는 의도적 유지 — "dark is the artifact, light is the screen".
export const paper = {
  canvas: '#FFFFFF',
  canvasSoft: '#FBFAF7',  // 소프트 화이트 — 홈 계열 바디 캔버스 (Sean 2026-08-06 "soft white"; 순백과 한 끗)
  ink: '#111111',      // head
  text: '#333333',     // 본문 (12.6:1)
  dim: '#666666',      // 디테일 (5.7:1 — 15pt 플로어와 함께 AA)
  faint: '#999999',    // 장식 클래스 전용 (sub-4.5 허용 유일 지점)
  line: '#E8552F',     // 솔리드 코랄 헤어라인 — 이 선이 곧 브랜드
  wash: '#FFF6F4',     // 코랄 95% 화이트 워시 (pressed 상태 등)
  // ── 정직 배치 선행 토큰 (F1.2 라우드-페일 · F2.1 버튼 매트릭스) ──
  critical: '#B3261E',      // 라우드-페일 잉크 — 강조 예산 면제, line과 절대 공유 금지 (색 역할 분리 법). ≥14pt/700
  criticalWash: '#FBEAE7',  // critical의 95% 워시 (인라인 실패 스트립 bg · destructive pressed)
  disabledFill: '#F2F2F2',  // disabled 버튼 명시 fill — 불투명도 트릭 금지 법의 물화
  inkPressed: '#333333',    // primary pressed fill — text와 값은 같아도 역할 토큰 분리 (F5 #10, 웨이브 2 리뷰 M3)
  pending: '#C77414',       // 시맨틱 대기 상태(앰버) — 라일락 L.amber의 순백 세계 승계 (웨이브 2 리뷰 L3)
  // ── 액션 시스템 (Sean 2026-08-11: "검정은 제일 지루하다. 버튼은 동기를 일으켜야 한다") ──
  // 잉크 프라이머리 은퇴. §5의 코랄 법을 '면'으로 확장한다 — 검정은 누구 차례인지 말하지 않는 색이었다.
  //
  // [디자인 보이스 교정] 첫 안은 #C7401F라는 **새 헥스**를 만들었다. 팔레트에 이미
  // #C6472C(= home.tsx MONEY_DEEP · GO_SKIN.deep · community CORAL_INK)가 있고, 둘의 분리도는
  // 1.04 — 눈으로 구분 불가다. 새 색을 만드는 것은 스타일 프리즈 위반이므로 **기존 값을 승격**한다.
  // 실측 흰 라벨: #C6472C = 4.84 (전 크기 AA 통과). 보너스로 프라이머리 버튼과 GO 디스크의
  // 눌린 코랄이 **같은 토큰**이 되어 두 개의 비슷한 색이 아니라 하나의 시스템으로 읽힌다.
  action: '#C6472C',        // 프라이머리/클라이맥스 면 — 흰 라벨 4.84:1. 신규 색 0개.
  actionPressed: '#A83315', // press 면 (불투명 — 알파 금지). 흰 라벨 6.67:1
  actionInk: '#A83315',     // 세컨더리 라벨 잉크 — wash 위 5.99:1
  // [교정] actionWash 신설 취소 — 기존 paper.wash(#FFF6F4)가 그 역할이다. 세컨더리 면 = wash.
  //
  // ── 준비됨(그린) — 상태 전용, 절대 누르는 면이 아니다 ──
  // [교정] DESIGN.md §3b는 아직 #12A05C를 적고 있는데, 그 값은 같은 문단의 ≥3.5 게이트를
  // 3.38로 하회한다. 실제 출하값은 owner/home.tsx의 화면 지역 const(GO_SAGE)였다 — 법전이
  // 존재하지 않는 색을 지정하고 있었다. 토큰으로 승격한다.
  ready: '#119B58',         // 확정·준비됨 (흰 라벨 3.59 — 큰 활자 전용, 누르는 면 금지)
  readyDeep: '#0E7F49',     // 그 위의 텍스트/딥 (5.06:1)
  // ── pace-state role tokens (pace-state-ui-plan §3) — live pace chip only ──
  // ROLE names over EXISTING hues, not new colors: good inherits ready/readyDeep
  // (#119B58's 95% white wash + readyDeep ink — the GO_TINT precedent), slow inherits
  // lilac.amberSoft's wash with a deeper amber ink. `pending` (#C77414) is NOT usable
  // as the slow ink: measured 3.09:1 on that wash, so the ink goes darker in the same hue.
  // Style-freeze compliant: four new names, zero new hues.
  // Measured contrast (WCAG 2.x relative luminance): paceGoodInk on paceGoodWash = 4.50:1,
  // paceSlowInk on paceSlowWash = 4.78:1 — both ≥4.5. Re-measure if any value moves.
  paceGoodWash: '#E7F5EE',
  paceGoodInk: '#0E7F49',
  paceSlowWash: '#FBEED9',
  paceSlowInk: '#9D580A',
  // 버튼 매트릭스 법(F2.1 개정): primary action面/actionPressed · secondary wash面+line 보더+actionInk ·
  // quiet canvas面+#EEE (드물게) · destructive canvas面+critical · disabled = disabledFill+faint (알파 금지) ·
  // busy = 라벨 스왑. **잉크는 상태(선택칩·완료 스텝·라이브 필·다크 아티팩트)로 남는다 — 액션이 아니다.**
} as const;

// Pricing — ⚠ 두 기본요금은 서로 다른 돈 (Sean 2026-08-12 D2 디커플링; 서버 정본 _shared/ctx.ts):
//   ownerBaseFare 7,900 = 보호자 가격 · runnerCompBase 9,900 = 러너 정산 기준 (피치의 바닥).
//   하나를 다른 하나에 맞추는 수정은 사고다.
export const pricing = {
  ownerBaseFare: 7900,
  // [0121] runnerCompBase and commission are GONE from the bundle: together they were the
  // runner-side gross formula and the margin. perKm stays — it prices the OWNER's distance
  // fare on four owner screens; the server's runner-side twin lives in 0101 only.
  perKm: 3000,
  addons: {
    river: { label: '리버뷰 코스', desc: '한강을 따라 더 시원하게', price: 3000 },
    homecare: { label: '홈길 온리', desc: '집까지 안전하게 케어', price: 2000 },
    snack: { label: '간식 타임', desc: '러닝 후 맛있는 보상', price: 2000 },
    snap: { label: '댕댕 스냅', desc: '러닝 사진 기록', price: 4000 }, // [정직 배치 2.5] 영상 기록 경로 없음 — 사진만 약속
    livecam: { label: '라이브캠', desc: '러닝을 실시간 영상으로', price: 3900 },
  },
} as const;
