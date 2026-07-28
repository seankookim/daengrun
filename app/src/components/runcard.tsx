import { Text, View } from 'react-native';
import { CollectCard, TracePoint } from '../store';
import { colors } from '../theme';
import { useTheme } from '../theme-context';

// Strava-style run card on a dark map backdrop.
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

export function HeatTrace({ points, width, height }: { points: TracePoint[]; width: number; height: number }) {
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
      color: heatColor((p.v + q.v) / 2),
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
      <Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>{label}</Text>
    </View>
  );
}

const TIER_COLORS: Record<string, string> = { 일반: '#8fa093', 레어: '#C6F542', 에픽: '#FF5C3D' };

export function RunCard({ card, width = 340 }: { card: CollectCard; width?: number }) {
  const { mode, p } = useTheme();
  const traceH = width * 0.5;
  const inner = width - 34;
  const tierColor = (tier: string) =>
    mode === 'light' && tier === '레어' ? colors.voltDeep : TIER_COLORS[tier];

  return (
    <View
      style={{
        width,
        backgroundColor: p.card,
        borderRadius: 18,
        padding: 16,
        borderWidth: 1,
        borderColor: p.line,
        opacity: card.locked ? 0.55 : 1,
        shadowColor: card.locked ? 'transparent' : colors.volt,
        shadowOpacity: 0.12,
        shadowRadius: 9,
        shadowOffset: { width: 0, height: 4 },
      }}
    >
      {/* header */}
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
        <View style={{ width: 36, height: 36, borderRadius: 12, backgroundColor: p.chip, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: mode === 'dark' ? colors.volt : colors.voltDeep }}>런</Text>
        </View>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 18.5, fontWeight: '800', color: card.locked ? p.dim : p.textStrong }}>
            {card.title}
          </Text>
          <Text style={{ fontSize: 12.5, color: p.dim, marginTop: 1 }}>
            {card.series ? `${card.series} · ` : ''}
            {card.run?.location ? `${card.run.location} · ` : ''}
            {card.date ?? '달성 조건: 시리즈 코스 완주'}
          </Text>
        </View>
        <View
          style={{
            borderWidth: 1, borderColor: card.locked ? p.line : tierColor(card.tier),
            borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10,
          }}
        >
          <Text style={{ fontSize: 11.5, fontWeight: '800', color: card.locked ? p.dim : tierColor(card.tier) }}>
            {card.locked ? '잠금' : card.run ? '도그스하이' : card.tier}
          </Text>
        </View>
      </View>

      {/* trace / emblem */}
      {card.run?.trace ? (
        <View style={{ marginTop: 14, borderRadius: 16, backgroundColor: '#0a120d', padding: 12, overflow: 'hidden' }}>
          <HeatTrace points={card.run.trace} width={inner - 24} height={traceH} />
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: 10 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#1b2f21', borderRadius: 10, paddingVertical: 6, paddingHorizontal: 10 }}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', color: colors.volt }}>컨디션 좋음</Text>
              <Text style={{ fontSize: 11.5, color: colors.dimDark }}>평소보다 +12% 활동량</Text>
            </View>
            <View style={{ backgroundColor: '#1b2330', borderRadius: 10, paddingVertical: 6, paddingHorizontal: 10 }}>
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#9fc3e8' }}>24°</Text>
            </View>
          </View>
        </View>
      ) : (
        <View
          style={{
            marginTop: 14, height: traceH * 0.62, borderRadius: 16,
            backgroundColor: '#0a120d', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <Text
            style={{
              fontSize: 53, fontWeight: '900',
              color: card.locked ? '#2c3222' : TIER_COLORS[card.tier],
              ...(card.locked ? {} : { textShadowColor: TIER_COLORS[card.tier], textShadowRadius: 18, textShadowOffset: { width: 0, height: 0 } }),
            }}
          >
            {card.emblem}
          </Text>
          <Text style={{ fontSize: 11.5, color: colors.dimDark, marginTop: 6, letterSpacing: 2 }}>
            {card.locked ? 'LOCKED' : card.tier.toUpperCase?.() ?? card.tier}
          </Text>
        </View>
      )}

      {/* stats */}
      {card.run && (
        <View style={{ flexDirection: 'row', marginTop: 14 }}>
          <CardStat value={card.run.km} unit="거리 (km)" color={p.textStrong} dim={p.dim} />
          <Divider color={p.line} />
          <CardStat value={card.run.pace} unit="평균 페이스" color={p.textStrong} dim={p.dim} />
          <Divider color={p.line} />
          <CardStat value={card.run.time} unit="시간" color={p.textStrong} dim={p.dim} />
        </View>
      )}
    </View>
  );
}

function Divider({ color }: { color: string }) {
  return <View style={{ width: 1, backgroundColor: color, marginVertical: 4 }} />;
}

function CardStat({ value, unit, color, dim }: { value: string; unit: string; color: string; dim: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={{ fontSize: 23, fontWeight: '900', color }}>{value}</Text>
      <Text style={{ fontSize: 11.5, color: dim, marginTop: 2 }}>{unit}</Text>
    </View>
  );
}
