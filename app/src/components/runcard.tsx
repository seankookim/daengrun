import { Text, View } from 'react-native';
import { TracePoint } from '../store';
import { colors } from '../theme';

// 히트 트레이스 — 실좌표 기반 러닝 궤적 렌더 (report.tsx가 사용).
// [정직 수리 2026-08-05] RunCard/CardStat/TIER_COLORS 퇴역 — 목업 카드 6장(myCards)의 유일한 소비자였고
// 조작 데이터('컨디션 좋음'·'+12% 활동량'·'24°')를 실화면에 그렸다. HeatTrace만 생존.
// Heat line: faster = red-orange, slower = green. Glowing segments.

function heatColor(v: number): string {
  if (v < 0.5) return lerpColor('#5b8c2a', '#e8b04b', v / 0.5);
  return lerpColor('#e8b04b', '#FF5C3D', (v - 0.5) / 0.5);
}

function lerpColor(a: string, b: string, t: number): string {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `#${pa.map((x, i) => Math.round(x + (pb[i] - x) * t).toString(16).padStart(2, '0')).join('')}`;
}

const LINE_W = 5;

// tint (0033): 강아지 칼라 컬러가 있으면 히트 그라디언트 대신 그 색으로 — 퍼스널 트레이스
export function HeatTrace({ points, width, height, tint }: { points: TracePoint[]; width: number; height: number; tint?: string }) {
  const segments = points.slice(0, -1).map((p, i) => {
    const q = points[i + 1];
    const x1 = p.x * width, y1 = p.y * height;
    const x2 = q.x * width, y2 = q.y * height;
    const len = Math.hypot(x2 - x1, y2 - y1);
    return {
      key: i,
      left: (x1 + x2) / 2 - len / 2,
      top: (y1 + y2) / 2 - LINE_W / 2,
      len,
      angle: Math.atan2(y2 - y1, x2 - x1),
      color: tint ?? heatColor((p.v + q.v) / 2),
    };
  });

  return (
    <View style={{ width, height }}>
      {/* faint map grid */}
      {[0.22, 0.5, 0.78].map((t) => (
        <View key={`h${t}`} style={{ position: 'absolute', left: 0, right: 0, top: t * height, height: 1, backgroundColor: '#ffffff08' }} />
      ))}
      {[0.18, 0.42, 0.66, 0.9].map((t) => (
        <View key={`v${t}`} style={{ position: 'absolute', top: 0, bottom: 0, left: t * width, width: 1, backgroundColor: '#ffffff08' }} />
      ))}
      {/* park blob */}
      <View style={{ position: 'absolute', left: width * 0.3, top: height * 0.3, width: width * 0.34, height: height * 0.36, borderRadius: 18, backgroundColor: '#14261f' }} />

      {/* glowing heat line */}
      {segments.map((s) => (
        <View
          key={s.key}
          style={{
            position: 'absolute', left: s.left, top: s.top,
            width: s.len, height: LINE_W, borderRadius: LINE_W / 2,
            backgroundColor: s.color,
            transform: [{ rotate: `${s.angle}rad` }],
            shadowColor: s.color, shadowOpacity: 0.9, shadowRadius: 5, shadowOffset: { width: 0, height: 0 },
          }}
        />
      ))}
      {points.map((p, i) => (
        <View
          key={`j${i}`}
          style={{
            position: 'absolute',
            left: p.x * width - LINE_W / 2,
            top: p.y * height - LINE_W / 2,
            width: LINE_W, height: LINE_W, borderRadius: LINE_W / 2,
            backgroundColor: heatColor(p.v),
          }}
        />
      ))}
      <Marker x={points[0].x * width} y={points[0].y * height} label="S" />
      <Marker x={points[points.length - 1].x * width} y={points[points.length - 1].y * height} label="F" />
    </View>
  );
}

function Marker({ x, y, label }: { x: number; y: number; label: string }) {
  return (
    <View
      style={{
        position: 'absolute', left: x - 10, top: y - 10, width: 20, height: 20, borderRadius: 10,
        backgroundColor: colors.bgDark, alignItems: 'center', justifyContent: 'center',
        borderWidth: 2, borderColor: '#ffffffcc',
      }}
    >
      {/* 'S'/'F' 한 글자 = 트레이스 위 아이콘 티어 마커. 20px 핀(테두리 2 → 내부 16px)에 갇힌 조형이라 14pt 플로어 면제 */}
      <Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>{label}</Text>
    </View>
  );
}
