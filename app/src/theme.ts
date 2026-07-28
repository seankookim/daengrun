// 도그스하이 design tokens — 2026-07-28 리브랜드 리프레시 (rebrand.md)
// 브랜드 = athletic editorial: 숫자는 애슬레틱하게(코랄·900·크게), 순간은 따뜻하게(크림·사진).
// 러너스하이(5음절)의 강아지 버전 — '하이'가 히어로 음절: 하이 포인트 · 오늘의 하이 · 하이 찍다.
export const colors = {
  ink: '#171A17',
  forest: '#0F1D13',     // 딥 포레스트 (구 #132117 — 리프레시로 심화)
  cream: '#F8F6F0',      // 한 톤 웜 (구 #F8F7F3)
  volt: '#C6F542',       // 크림 위 발색 보정 (구 #B9F23A)
  voltDeep: '#7FA818',
  voltBright: '#d4ff66',
  tang: '#FF5C3D',       // 코랄 펀치 업 (구 #FF6347) — 도파민 숫자·라이브 전용
  coralText: '#d84a2f',  // 읽는 코랄 — 경고·조기종료 텍스트 (tang의 텍스트 버전, 의도적 2단)
  card: '#ffffff',
  clay: '#EDE8DA',       // NEW 웜 뉴트럴 — 칩·웰·인풋 바탕 (흰 카드가 크림 위에 뜨지 않게)
  line: '#DCD6C4',       // 헤어라인 3종(#D6D3C4/#DEDACB/#d9d5c6) 단일 수렴
  border: '#DCD6C4',     // line과 동치 — 점진 제거 예정 (line만 남긴다)
  green: '#5a7a3c',      // 기능 그린 — 라벨·강조 (volt의 텍스트 버전, 대비 우선이라 유지)
  dim: '#6D6B5C',
  // dark glow theme (owner home / cards)
  bgDark: '#0C130E',
  cardDark: '#0F1D13',
  lineDark: '#24352a',
  dimDark: '#8fa093',
} as const;

// 디스플레이 서체 — Black Han Sans (src/lib/displayFont.ts의 useDisplayFont로 지연 로드).
// 규칙: 화면당 1회(히어로 카피·브랜드 워드마크)만. 로드 실패 시 시스템 900 폴백.
export const DISPLAY_FONT = 'BlackHanSans_400Regular' as const;

export const radius = { card: 16, btn: 13, chip: 99 } as const;
// 글로벌 거터 — 화면 좌우 여백은 이 값 하나로 (에지-투-에지 프리미엄)
export const layout = { gutter: 12 } as const;

// 타이포 스케일 — 규칙: 900은 오직 숫자(display)와 화면 제목(title)에만.
// 본문·라벨이 전부 900이면 위계가 무너진다 (ui-audit). 새 코드는 이 프리셋을 쓸 것.
export const type = {
  display: { fontSize: 42, fontWeight: '900', fontVariant: ['tabular-nums'] } as const, // 큰 숫자 전용
  numeric: { fontSize: 22, fontWeight: '900', fontVariant: ['tabular-nums'] } as const, // 중간 숫자
  title: { fontSize: 21, fontWeight: '900' } as const,   // 화면 제목
  heading: { fontSize: 14.5, fontWeight: '800' } as const, // 섹션/카드 제목
  body: { fontSize: 13.5, fontWeight: '600' } as const,
  label: { fontSize: 11.5, fontWeight: '700' } as const,
  caption: { fontSize: 10.5, fontWeight: '400' } as const,
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
    chip: '#EDE8DA',
    track: '#DDE8D4',
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
