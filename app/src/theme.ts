// 댕런 design tokens — mirrors prototype/index.html
export const colors = {
  ink: '#171A17',
  cream: '#F6F2E9',
  volt: '#B9F23A',
  voltDeep: '#82b016',
  voltBright: '#d4ff66',
  tang: '#FF6347',
  card: '#ffffff',
  line: '#DDE8D4',
  dim: '#8a8877',
  // dark glow theme (owner home / cards)
  bgDark: '#0d1410',
  cardDark: '#132117',
  lineDark: '#24352a',
  dimDark: '#8fa093',
} as const;

export const radius = { card: 20, btn: 16, chip: 99 } as const;

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
