import { Text, View } from 'react-native';
import { CollectCard, TracePoint } from '../store';
import { colors } from '../theme';

// Strava-style run card + heat-map trace. Faster = red, slower = green.

function heatColor(v: number): string {
  // green (#5b8c2a) → amber (#e8b04b) → red-orange (#ff5c38)
  if (v < 0.5) {
    const t = v / 0.5;
    return lerpColor('#5b8c2a', '#e8b04b', t);
  }
  return lerpColor('#e8b04b', '#ff5c38', (v - 0.5) / 0.5);
}

function lerpColor(a: string, b: string, t: number): string {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  const mix = pa.map((x, i) => Math.round(x + (pb[i] - x) * t));
  return `#${mix.map((x) => x.toString(16).padStart(2, '0')).join('')}`;
}

const LINE_W = 4;

export function HeatTrace({ points, width, height }: { points: TracePoint[]; width: number; height: number }) {
  const segments = points.slice(0, -1).map((p, i) => {
    const q = points[i + 1];
    const x1 = p.x * width, y1 = p.y * height;
    const x2 = q.x * width, y2 = q.y * height;
    const dx = x2 - x1, dy = y2 - y1;
    const len = Math.hypot(dx, dy);
    const angle = Math.atan2(dy, dx);
    return {
      key: i,
      left: (x1 + x2) / 2 - len / 2,
      top: (y1 + y2) / 2 - LINE_W / 2,
      len,
      angle,
      color: heatColor((p.v + q.v) / 2),
    };
  });

  return (
    <View style={{ width, height }}>
      {/* continuous heat line: rotated segments + joint dots for smooth corners */}
      {segments.map((s) => (
        <View
          key={s.key}
          style={{
            position: 'absolute', left: s.left, top: s.top,
            width: s.len, height: LINE_W, borderRadius: LINE_W / 2,
            backgroundColor: s.color,
            transform: [{ rotate: `${s.angle}rad` }],
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
        position: 'absolute', left: x - 8, top: y - 8, width: 16, height: 16, borderRadius: 8,
        backgroundColor: colors.cream, alignItems: 'center', justifyContent: 'center',
        borderWidth: 2, borderColor: colors.ink,
      }}
    >
      <Text style={{ fontSize: 8, fontWeight: '900', color: colors.ink }}>{label}</Text>
    </View>
  );
}

const TIER_COLORS: Record<string, string> = { 일반: '#8a8877', 레어: '#c8f24e', 에픽: '#ff5c38' };

export function RunCard({ card, width = 300 }: { card: CollectCard; width?: number }) {
  const traceH = width * 0.52;

  return (
    <View
      style={{
        width,
        backgroundColor: card.locked ? '#22251715' : colors.ink,
        borderRadius: 20,
        padding: 16,
        opacity: card.locked ? 0.55 : 1,
        borderWidth: card.locked ? 1.5 : 0,
        borderColor: colors.line,
      }}
    >
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 11, fontWeight: '900', letterSpacing: 2, color: card.locked ? colors.dim : colors.volt }}>
          댕런
        </Text>
        <View style={{ backgroundColor: card.locked ? colors.line : '#2c3020', borderRadius: 99, paddingVertical: 3, paddingHorizontal: 9 }}>
          <Text style={{ fontSize: 10, fontWeight: '800', color: card.locked ? colors.dim : TIER_COLORS[card.tier] }}>
            {card.locked ? '잠금' : card.tier}
          </Text>
        </View>
      </View>

      <Text style={{ fontSize: 16, fontWeight: '800', color: card.locked ? colors.dim : colors.cream, marginTop: 10 }}>
        {card.title}
      </Text>
      {(card.date || card.series || card.run?.location) && (
        <Text style={{ fontSize: 11, color: '#9a987f', marginTop: 2 }}>
          {card.series ? `${card.series} · ` : ''}
          {card.run?.location ? `${card.run.location} · ` : ''}
          {card.date ?? '달성 조건: 시리즈 코스 완주'}
        </Text>
      )}

      {card.run?.trace ? (
        <View style={{ marginTop: 12, borderRadius: 14, backgroundColor: '#22251a', padding: 10 }}>
          <HeatTrace points={card.run.trace} width={width - 52} height={traceH} />
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: 8, paddingHorizontal: 2 }}>
            <Text style={{ fontSize: 9, color: '#5b8c2a', fontWeight: '700' }}>● 느림</Text>
            <Text style={{ fontSize: 9, color: '#ff5c38', fontWeight: '700' }}>빠름 ●</Text>
          </View>
        </View>
      ) : (
        <View
          style={{
            marginTop: 12, height: traceH * 0.66, borderRadius: 14,
            backgroundColor: card.locked ? colors.line : '#22251a',
            alignItems: 'center', justifyContent: 'center',
          }}
        >
          <Text style={{ fontSize: 44, fontWeight: '900', color: card.locked ? colors.dim : TIER_COLORS[card.tier] }}>
            {card.emblem}
          </Text>
        </View>
      )}

      {card.run && (
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: 12, paddingHorizontal: 4 }}>
          <CardStat value={`${card.run.km}km`} label="거리" />
          <CardStat value={card.run.pace} label="페이스" />
          <CardStat value={card.run.time} label="시간" />
        </View>
      )}
    </View>
  );
}

function CardStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 17, fontWeight: '900', color: colors.cream }}>{value}</Text>
      <Text style={{ fontSize: 10, color: '#9a987f', marginTop: 1 }}>{label}</Text>
    </View>
  );
}
