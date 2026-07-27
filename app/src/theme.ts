// 댕런 design tokens — mirrors prototype/index.html
// 브랜드 = athletic editorial: 숫자는 애슬레틱하게(코랄·900·크게), 순간은 따뜻하게(크림·사진).
export const colors = {
  ink: '#171A17',
  forest: '#132117',     // 다크 카드/히어로 (파일 로컬 FOREST 상수를 이걸로 수렴)
  cream: '#F8F7F3',   // 클린 오프화이트 — 파스텔 헤이즈 제거 (2026-07-27 샤프닝)
  volt: '#B9F23A',
  voltDeep: '#82b016',
  voltBright: '#d4ff66',
  tang: '#FF6347',       // 밝은 코랄 — 도파민 숫자·라이브 전용
  coralText: '#d84a2f',  // 읽는 코랄 — 경고·조기종료 텍스트 (tang의 텍스트 버전, 의도적 2단)
  card: '#ffffff',
  line: '#D6D3C4',
  border: '#DEDACB',  // 헤어라인 강화 — 서피스 정의는 소프트함이 아니라 스트로크로     // 흰 카드 테두리 (산재한 리터럴 수렴용)
  green: '#5a7a3c',      // 기능 그린 — 라벨·강조 (volt의 텍스트 버전)
  dim: '#6E6C5E',      // 텍스트 대비 강화
  // dark glow theme (owner home / cards)
  bgDark: '#0d1410',
  cardDark: '#132117',
  lineDark: '#24352a',
  dimDark: '#8fa093',
} as const;

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
    chip: '#eef4e4',
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
