import { ReactNode } from 'react';
import { View } from 'react-native';
import { colors } from '../theme';

// Dot-ring progress — pure RN, no SVG dependency.
// N dots around a circle; the first pct*N light up in the active color.

export function Ring({
  size = 190,
  dots = 40,
  dotSize = 9,
  pct,
  activeColor = colors.volt,
  trackColor = '#33371f',
  children,
}: {
  size?: number;
  dots?: number;
  dotSize?: number;
  pct: number; // 0..1
  activeColor?: string;
  trackColor?: string;
  children?: ReactNode;
}) {
  const p = Math.min(Math.max(pct, 0), 1);
  const lit = Math.round(p * dots);
  const r = size / 2 - dotSize;
  const c = size / 2;

  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      {Array.from({ length: dots }).map((_, i) => {
        const angle = -Math.PI / 2 + (i / dots) * Math.PI * 2; // start at 12 o'clock
        const x = c + r * Math.cos(angle) - dotSize / 2;
        const y = c + r * Math.sin(angle) - dotSize / 2;
        const active = i < lit;
        return (
          <View
            key={i}
            style={{
              position: 'absolute',
              left: x,
              top: y,
              width: dotSize,
              height: dotSize,
              borderRadius: dotSize / 2,
              backgroundColor: active ? activeColor : trackColor,
            }}
          />
        );
      })}
      {children}
    </View>
  );
}
