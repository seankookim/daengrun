// 댕런 design tokens — mirrors prototype/index.html
export const colors = {
  ink: '#171a10',
  cream: '#f2efe6',
  volt: '#c8f24e',
  voltDeep: '#9ecf1e',
  tang: '#ff5c38',
  card: '#ffffff',
  line: '#e2ddcf',
  dim: '#8a8877',
} as const;

export const radius = { card: 20, btn: 16, chip: 99 } as const;

// Pricing (placeholder — validate against competitor research)
export const pricing = {
  baseFare: 9900,
  perKm: 3000,
  commission: 0.2,
  addons: {
    river: { label: '리버뷰 코스', price: 3000 },
    dirt: { label: '흙길 온리', price: 2000 },
    snack: { label: '간식 타임', price: 2000 },
    meetup: { label: '댕댕 밋업', price: 4000 },
  },
} as const;
