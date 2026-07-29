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
// 글로벌 거터 — 화면 좌우 여백은 이 값 하나로 (에지-투-에지 프리미엄)
export const layout = { gutter: 11 } as const; // 2026-07-28 0.9x 축소 (홈·설정 적용, 나머지 화면은 점진 수렴)

// 타이포 스케일 — 규칙: 900은 오직 숫자(display)와 화면 제목(title)에만.
// 본문·라벨이 전부 900이면 위계가 무너진다 (ui-audit). 새 코드는 이 프리셋을 쓸 것.
export const type = {
  display: { fontSize: 48.5, fontWeight: '900', fontVariant: ['tabular-nums'] } as const, // 큰 숫자 전용
  numeric: { fontSize: 25.5, fontWeight: '900', fontVariant: ['tabular-nums'] } as const, // 중간 숫자
  title: { fontSize: 24, fontWeight: '900' } as const,   // 화면 제목
  heading: { fontSize: 16.5, fontWeight: '800' } as const, // 섹션/카드 제목
  body: { fontSize: 15.5, fontWeight: '600' } as const,
  label: { fontSize: 13, fontWeight: '700' } as const,
  caption: { fontSize: 12, fontWeight: '400' } as const,
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

// Pricing (placeholder — validate against competitor research)
export const pricing = {
  baseFare: 9900,
  perKm: 3000,
  commission: 0.2,
  addons: {
    river: { label: '리버뷰 코스', desc: '한강을 따라 더 시원하게', price: 3000 },
    homecare: { label: '홈길 온리', desc: '집까지 안전하게 케어', price: 2000 },
    snack: { label: '간식 타임', desc: '러닝 후 맛있는 보상', price: 2000 },
    snap: { label: '댕댕 스냅', desc: '러닝 사진 · 영상 기록', price: 4000 },
    livecam: { label: '라이브캠', desc: '러닝을 실시간 영상으로', price: 3900 },
  },
} as const;
