import { ReactNode } from 'react';
import { Text, View } from 'react-native';
import { useNumFont } from '../lib/fonts';
import { lilac } from '../theme';

// ④ 링 드레인 — 마감의 색 (정본: docs/labs/choreography-lab.html ④)
// 실마감 전용 부품: 서버가 준 만료 시각이 있는 자리에만 그린다 (상시 애니 금지 — 링이 돌면 진짜 시간이 준 것).
// 애니메이션 값이 없다 — 부모가 이미 돌리는 1초 틱이 곧 프레임이다(1fps). 점은 View, SVG·Reanimated 불요.
// 색 램프: 바이올렛 → 코랄 → 딥코랄 (랩의 drainColor 키프레임을 '남은 비율'로 옮긴 것).

const L = lilac;

// 색 보간 — owner/home.tsx lerpHex와 같은 문법 (부품은 화면에서 끌어오지 않는다: 복사가 의존보다 싸다)
function lerpHex(a: string, b: string, t: number): string {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `#${pa.map((x, i) => Math.round(x + (pb[i] - x) * t).toString(16).padStart(2, '0')).join('')}`;
}

// 랩 키프레임(경과 0~55% 바이올렛 · 78% 코랄 · 100% 딥코랄)을 남은 비율 f로 환산
function drainColor(f: number): string {
  if (f >= 0.45) return L.accent;
  if (f >= 0.22) return lerpHex(L.coral, L.accent, (f - 0.22) / 0.23);
  return lerpHex(L.coralDeep, L.coral, f / 0.22);
}

const mmss = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

export function DrainRing({
  leftMs, totalMs, size = 78, dots = 24, showTime, children,
}: {
  leftMs: number;       // 남은 시간 = 서버 만료 시각 − now (음수면 만료)
  totalMs: number;      // 창 전체 길이 (제안 5분 · 결제 홀드 20분 …)
  size?: number;
  dots?: number;
  showTime?: boolean;   // 기본 = 숫자가 들어갈 만큼 큰 링에서만. mm:ss는 60분 미만 창 전용이다
  children?: ReactNode; // 링 안 한 줄 더 (14pt 바닥선을 지킬 것)
}) {
  const nf = useNumFont();
  const done = leftMs <= 0;
  const f = done || totalMs <= 0 ? 0 : Math.min(Math.max(leftMs / totalMs, 0), 1);
  const lit = f > 0 ? Math.max(1, Math.round(f * dots)) : 0; // 살아 있는 창은 최소 1점 — 0점은 만료의 낱말이다
  const color = drainColor(f);
  const track = done ? L.coralSoft : L.hair; // 만료 = 딥코랄 숫자 위의 다 빠진 코랄 링
  const dotSize = Math.max(2.4, size / 11);
  const withTime = showTime ?? size >= 48;
  const r = size / 2 - dotSize;
  const c = size / 2;

  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      {Array.from({ length: dots }).map((_, i) => {
        const angle = -Math.PI / 2 + (i / dots) * Math.PI * 2; // 12시 시작 · 시계 방향 (남은 만큼 앞에서부터 점등)
        return (
          <View
            key={i}
            style={{
              position: 'absolute',
              left: c + r * Math.cos(angle) - dotSize / 2,
              top: c + r * Math.sin(angle) - dotSize / 2,
              width: dotSize,
              height: dotSize,
              borderRadius: dotSize / 2,
              backgroundColor: i < lit ? color : track,
            }}
          />
        );
      })}
      {withTime && (
        <Text style={[{ fontSize: 22, lineHeight: 27, fontWeight: '600', color: done ? L.coralDeep : L.head, fontVariant: ['tabular-nums'] }, nf]}>
          {mmss(leftMs)}
        </Text>
      )}
      {children}
    </View>
  );
}
