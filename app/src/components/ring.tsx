import { ReactNode } from 'react';
import { View } from 'react-native';
import { colors } from '../theme';

// Glowing dot-ring progress — pure RN, no SVG dependency.
// Lit dots shade deep→bright volt along the arc; a larger glowing head dot marks progress.

function lerpColor(a: string, b: string, t: number): string {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `#${pa.map((x, i) => Math.round(x + (pb[i] - x) * t).toString(16).padStart(2, '0')).join('')}`;
}

export function Ring({
  size = 220,
  dots = 48,
  dotSize = 10,
  pct,
  trackColor = '#2a3118',
  children,
}: {
  size?: number;
  dots?: number;
  dotSize?: number;
  pct: number; // 0..1
  trackColor?: string;
  children?: ReactNode;
}) {
  const p = Math.min(Math.max(pct, 0), 1);
  const lit = Math.round(p * dots);
  const r = size / 2 - dotSize;
  const c = size / 2;
  const headSize = dotSize * 1.9;

  const pos = (i: number) => {
    const angle = -Math.PI / 2 + (i / dots) * Math.PI * 2; // 12 o'clock start
    return { x: c + r * Math.cos(angle), y: c + r * Math.sin(angle) };
  };

  const head = pos(Math.max(lit - 1, 0));

  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      {Array.from({ length: dots }).map((_, i) => {
        const { x, y } = pos(i);
        const active = i < lit;
        const color = active ? lerpColor(colors.voltDeep, colors.voltBright, i / dots) : trackColor;
        return (
          <View
            key={i}
            style={{
              position: 'absolute',
              left: x - dotSize / 2,
              top: y - dotSize / 2,
              width: dotSize,
              height: dotSize,
              borderRadius: dotSize / 2,
              backgroundColor: color,
              ...(active && {
                shadowColor: colors.volt,
                shadowOpacity: 0.9,
                shadowRadius: 6,
                shadowOffset: { width: 0, height: 0 },
              }),
            }}
          />
        );
      })}
      {/* glowing head dot */}
      {lit > 0 && (
        <View
          style={{
            position: 'absolute',
            left: head.x - headSize / 2,
            top: head.y - headSize / 2,
            width: headSize,
            height: headSize,
            borderRadius: headSize / 2,
            backgroundColor: colors.voltBright,
            borderWidth: 3,
            borderColor: '#ffffff55',
            shadowColor: colors.volt,
            shadowOpacity: 1,
            shadowRadius: 12,
            shadowOffset: { width: 0, height: 0 },
            elevation: 8,
          }}
        />
      )}
      {children}
    </View>
  );
}
