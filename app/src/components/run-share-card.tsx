import { Text, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';
import { colors, paper } from '../theme';

// RunShareCard — 공유용 러닝 포스터 한 장. **단일 정본**.
//
// 왜 뽑았나 (코덱스 §C 리뷰의 최대 지적):
//   `shot/[bid].tsx`에는 이미 스킨 4종짜리 카드 스튜디오가 있는데, 컴포저 미리보기와 인스타 export가
//   각자 비슷한 카드를 또 그리려 하고 있었다. 같은 물건이 세 벌이 되면 셋이 조금씩 어긋난다.
//   그래서 **공유 아티팩트**는 이 컴포넌트 하나로 모은다: 샷 스튜디오 · 컴포저 미리보기 · 인스타 export.
//
// ⚠ 피드 카드는 여기 포함되지 않는다. 코덱스는 피드까지 한 컴포넌트로 묶으라고 했지만, 그건
//   과통합이다: 피드 카드는 **가로로 흐르는 포스트 행**이고 이건 **9:16 포스터**다. 같은 데이터를
//   쓰지만 다른 물건이라, 하나로 묶으면 둘 다 어색해진다. 공유되는 것만 여기 산다.
//
// 왜 볼트 블록(구 'I' 스킨)이 정본인가: **사진을 요구하지 않는다.** 완주 사진은 선택이라 상당수의
//   러닝에 사진이 없고, 사진을 요구하는 스킨을 export 기본값으로 삼으면 그 러너들은 공유 자체를
//   못 한다. 사진 없는 카드가 모두에게 동작하는 유일한 형태다.
//
// 이 컴포넌트는 **순수**하다: props만 읽고, 데이터를 가져오지 않고, 상태가 없다.
//   react-native-view-shot이 캡처하려면 그래야 한다 (캡처 시점에 비동기가 남아 있으면 빈 프레임이 찍힌다).

export interface RunCardData {
  dogName: string;
  km: number;
  /** 실측 — 없으면 그 줄을 그리지 않는다 (0을 그리지 않는다) */
  durationSec: number | null;
  paceSecPerKm: number | null;
  when: string;
  routeName: string | null;
  /** 0..1로 정규화된 실 GPS 궤적. null이면 트레이스를 그리지 않는다 — 가짜 선을 그리지 않는다. */
  trace: { x: number; y: number }[] | null;
  /** '역대 최장 거리' 같은 실제 기록 줄. 없으면 줄 자체가 없다. */
  recordLine?: string | null;
}

export const fmtDur = (sec: number | null): string | null =>
  sec == null ? null : `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
export const fmtPace = (secPerKm: number | null): string | null =>
  secPerKm == null ? null : `${Math.floor(secPerKm / 60)}'${String(Math.round(secPerKm % 60)).padStart(2, '0')}"`;

// 정규화된 점들을 SVG path로. shot/[bid].tsx의 pathFrom과 같은 산식 — 그 파일이 이걸 import한다.
export function pathFrom(pts: { x: number; y: number }[], w: number, h: number, pad = 10): string {
  const sx = (v: number) => pad + v * (w - pad * 2);
  const sy = (v: number) => pad + v * (h - pad * 2);
  return pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${sx(p.x).toFixed(1)},${sy(p.y).toFixed(1)}`).join(' ');
}

/**
 * 공유 카드 한 장. width/height는 호출부가 정한다 —
 * 인스타 스토리는 9:16, 피드 공유는 4:5, 미리보기는 축소판. 조판은 비율에 따라 스스로 맞춘다.
 */
export function RunShareCard({
  data, width, height, df,
}: {
  data: RunCardData;
  width: number;
  height: number;
  /** useDisplayFont()의 결과. 폰트 로딩은 호출부의 일 — 이 컴포넌트는 순수하게 유지한다. */
  df: any;
}) {
  const time = fmtDur(data.durationSec);
  const pace = fmtPace(data.paceSecPerKm);
  const traceSize = Math.min(width, height) * 0.42;

  return (
    <View style={{ width, height, backgroundColor: colors.volt, padding: width * 0.06, overflow: 'hidden' }}>
      {/* 날짜 · 코스 — 한글 데이터라 14pt 플로어를 지킨다 (§3, 로고 예외 아님) */}
      <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '900', letterSpacing: 0.6, color: paper.ink }}>
        {data.when}{data.routeName ? ` · ${data.routeName}` : ''}
      </Text>

      {/* 거리 = 화면의 유일한 대형 숫자. lineHeight는 1.05× (BUG A는 Oswald 법이지만 큰 숫자는 항상 명시) */}
      <Text style={[{ fontSize: width * 0.30, lineHeight: width * 0.32, fontWeight: '900', color: paper.ink, marginTop: 2 }, df]}>
        {data.km}<Text style={{ fontSize: width * 0.10, letterSpacing: -1 }}>KM</Text>
      </Text>
      <Text style={[{ fontSize: width * 0.10, fontWeight: '900', color: paper.ink, marginTop: 2 }, df]}>
        {data.dogName} 완주
      </Text>

      {/* GPS 트레이스 — 숫자 위를 의도적으로 가로지른다 (Sean 2026-07-29: 겹침을 전경화).
          흰 케이싱 + 탱 라인이라 숫자와 한 색으로 뭉개지지 않고 스티커처럼 앞에 선다.
          trace가 null이면 통째로 그리지 않는다 — 없는 길을 그리지 않는다. */}
      {data.trace && data.trace.length > 1 && (
        <Svg
          pointerEvents="none"
          width={traceSize} height={traceSize} viewBox={`0 0 ${traceSize} ${traceSize}`}
          style={{ position: 'absolute', right: width * 0.08, top: height * 0.16 }}
        >
          <Path d={pathFrom(data.trace, traceSize, traceSize, 12)} stroke="#fff" strokeWidth={8} strokeLinecap="round" strokeLinejoin="round" fill="none" />
          <Path d={pathFrom(data.trace, traceSize, traceSize, 12)} stroke={colors.tang} strokeWidth={4} strokeLinecap="round" strokeLinejoin="round" fill="none" />
          <Circle cx={12 + data.trace[0].x * (traceSize - 24)} cy={12 + data.trace[0].y * (traceSize - 24)} r={5.5} fill="#fff" />
          <Circle
            cx={12 + data.trace[data.trace.length - 1].x * (traceSize - 24)}
            cy={12 + data.trace[data.trace.length - 1].y * (traceSize - 24)}
            r={5.5} fill={paper.ink}
          />
        </Svg>
      )}

      {/* 세로 워드마크 — 로고 아트워크 (DESIGN.md §3 로고 예외: 마크이고, 장식으로 선언되고, 데이터가 없다) */}
      <View
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
        style={{ position: 'absolute', right: width * 0.03, top: height * 0.02 }}
      >
        {['도', '그', '스', '하', '이'].map((c) => (
          <Text key={c} style={[{ fontSize: width * 0.085, color: paper.ink, fontWeight: '900', lineHeight: width * 0.093, textAlign: 'center' }, df]}>{c}</Text>
        ))}
      </View>

      {/* 사실 표 — 값이 있는 줄만 그린다 */}
      <View style={{ position: 'absolute', bottom: height * 0.06, left: width * 0.06, right: width * 0.06, borderTopWidth: 2.5, borderTopColor: paper.ink }}>
        {([
          ['TIME', time],
          ['PACE', pace ? `${pace} /KM` : null],
          ...(data.recordLine ? [['RECORD', data.recordLine] as [string, string]] : []),
        ] as [string, string | null][])
          .filter(([, v]) => v != null)
          .map(([l, v]) => (
            <View key={l} style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 5, borderBottomWidth: 1, borderBottomColor: 'rgba(17,17,17,0.18)' }}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>{l}</Text>
              <Text style={{ fontSize: 14, fontWeight: '900', color: paper.ink }}>{v}</Text>
            </View>
          ))}
      </View>
    </View>
  );
}
