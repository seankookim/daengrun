import { ReactNode, useId } from 'react';
import { Text, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Rect, Stop } from 'react-native-svg';
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
  /** ⚠ 실측 거리. `number`였다가 nullable이 됐다 — 바로 아래 두 필드가 이미 지키고 있던 법에서
   *  이 필드 하나만 빠져 있었다. 서버가 재지 못한 러닝(incident 종료 등)은 `actual_km`이 NULL이고,
   *  예전 타입에서는 그게 `0`으로 내려와 **내보내는 PNG에** 「0km 완주」가 찍혔다. 이 카드는 앱을
   *  떠나므로(아래 :368 주석) 작은 부정확이 곧 발행된 부정확이다. */
  km: number | null;
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
      {/* 날짜 · 코스 — 한글 데이터라 15pt 플로어를 지킨다 (§3, 로고 예외 아님) */}
      <Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '900', letterSpacing: 0.6, color: paper.ink }}>
        {data.when}{data.routeName ? ` · ${data.routeName}` : ''}
      </Text>

      {/* 거리 = 화면의 유일한 대형 숫자. lineHeight는 1.05× (BUG A는 Oswald 법이지만 큰 숫자는 항상 명시) */}
      {data.km != null && (
        <Text style={[{ fontSize: width * 0.30, lineHeight: width * 0.32, fontWeight: '900', color: paper.ink, marginTop: 2 }, df]}>
          {data.km}<Text style={{ fontSize: width * 0.10, letterSpacing: -1 }}>KM</Text>
        </Text>
      )}
      {/* 거리를 재지 못했으면 「완주」도 주장하지 않는다 — 완주는 거리에 대한 주장이다. */}
      <Text style={[{ fontSize: width * 0.10, fontWeight: '900', color: paper.ink, marginTop: 2 }, df]}>
        {data.dogName}{data.km != null ? ' 완주' : ''}
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
              <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>{l}</Text>
              <Text style={{ fontSize: 15, fontWeight: '900', color: paper.ink }}>{v}</Text>
            </View>
          ))}
      </View>
    </View>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ③ 스토리 — the SHARE CARD SEAN PICKED (round 6, 2026-08-25).
//   「share card i like 3 but make it so that the pace info background is
//    transparent so it's just text overlaid on photo」
// Spec: docs/labs/share-card-lab.html — ROUND 6 header block, frames ③ ⑤ ⑥.
//
// 9:16, the photo runs to all four edges, and the stat block sits DIRECTLY on
// the photo: no plate, no box, no visible edge. The r5 build had an ink plate
// (#26231b, ~14:1) and he amended it away.
//
// WHY THE PLATE EXISTED IS STILL ANSWERED, NOT DROPPED. White type cannot be
// contrast-checked against an unknown photo, and DESIGN.md's floors are *vs the
// canvas*. So what replaces the plate is a DETERMINISTIC SCRIM burned into the
// captured PNG — a fixed-height `ScrimRamp` above the type and a FLAT floor fill
// behind it (`SCRIM_FLOOR_FILL`), so the alpha under every glyph is a literal
// constant and the worst case is arithmetic instead of a guess.
//
// ⚠ ONE LAB DETAIL DID NOT SURVIVE THE MEASUREMENT and is corrected here.
// The lab's `.overlay .odisp .u` still carried --coralSoft (#FFDCD1) on the km
// number — a leftover from the plate build, where it sat on #26231b and was
// fine. On the scrim's worst-case ground it measures **4.45:1 and FAILS**
// (re-derived from these constants, unrounded: L(#FFDCD1)=0.77037, L(worst-case
// composite rgb(103.7,102.5,100.6))=0.13458 → 4.45. The same run reproduces the
// lab's whole table — #D8D6D0 3.91, floor 0.60 → label 4.40, floor 0.55 → white
// 4.43 — so the disagreement is real, not a different method.) The display line
// is therefore #FFFFFF end to end (5.69:1). This is the exact class of thing the
// lab itself flagged when #D8D6D0 had to become #EDEAE3 — a "just delete the
// box" change silently breaks inks that the box used to carry. No new colour
// was invented to keep the accent; the accent was dropped.
//
// NOT ON THIS CARD, on purpose (lab's privacy ledger): no course/place name, no
// other dog, no runner name, no money, and no TIME OF DAY. `data.routeName` is
// deliberately unread here — a course name is a location datum even as a few
// characters of Korean. `data.when` is expected to be a DATE: the studio strips
// the clock time out of `RunReport.when` before handing it over, because an
// habitual walk hour beside an opt-in route silhouette says where AND when.

/** #0B0906 — the scrim base. Not a theme colour: it is the black the floor
 *  arithmetic below was measured against, and changing it invalidates the table. */
const SCRIM_BASE = '#0B0906';
/** The floor alpha. 0.62 is the LIGHTEST value that clears both inks against a
 *  pure-white photo. Re-derived from these exact constants: 0.60 → label ink
 *  4.40:1 (fail) · 0.55 → white type 4.43:1 (fail) · 0.45 → white type 3.18:1
 *  (fail) · 0.62 → white 5.69:1, label 4.74:1 (both pass). Do not soften it. */
const SCRIM_FLOOR = 0.62;
/** The floor as a paint value. This is a FLAT FILL, not a gradient stop — see
 *  `StoryShareCard`: the type band's background IS this colour, so the alpha
 *  under every glyph is a literal constant rather than a sampled point on a ramp. */
const SCRIM_FLOOR_FILL = `rgba(11,9,6,${SCRIM_FLOOR})`;
/** Label ink. #D8D6D0 (the r5 value) measures 3.91:1 on this floor and FAILS. */
const SCRIM_LABEL_INK = '#EDEAE3';

/** An exported card must not reflow with the reader's OS text size — it is an
 *  artifact, not UI, and the card box is fixed and clips. Applied to every Text
 *  on the card so the PNG is the same picture on every phone. */
const FIXED_TYPE = { allowFontScaling: false } as const;

/**
 * The scrim's RAMP — the fade from transparent down to the floor alpha.
 *
 * ⚠ It draws ONLY the ramp, and the ramp only ever sits ABOVE the type. The flat
 * floor under the text is not drawn here at all: it is the text block's own
 * background (`SCRIM_FLOOR_FILL`).
 *
 * That split is deliberate and it is the whole correctness argument. An earlier
 * cut drew one gradient sized to an onLayout-MEASURED band height, and that has a
 * failure mode: on the first frame — before layout reports — the fallback height
 * has to be guessed, and any guess that comes out short puts real glyphs over the
 * ramp instead of the floor. (Measured: the guessed 32%-of-card fallback was 154pt
 * against a real band of 172pt with the route off, 296pt with it on. It was short
 * both times.) Splitting the two removes the guess and the measurement together —
 * the floor is coextensive with the type BY CONSTRUCTION, at every frame, for any
 * dog-name length, any wrap, any accessibility text size, route on or off.
 *
 * Worst case is therefore a fixed arithmetic value, not a hope: a pure-white photo
 * composites to rgb(104,102,101) under the floor, where #FFFFFF = 5.69:1 and
 * #EDEAE3 = 4.74:1. Both clear 4.5. (The lab measured 5.65 / 4.70 by compositing
 * the real CSS gradient on a canvas and reading the pixel back; the difference is
 * its rounding of the composite to integers.)
 *
 * The ramp's interior stops mirror the lab's CSS exactly, as fractions of the ramp
 * measured from its top: 0 → 0, .25 → .16, .5625 → .40, 1 → .62.
 */
function ScrimRamp({ width, height }: { width: number; height: number }) {
  // react-native-svg resolves gradient ids in a document-wide namespace and this
  // studio mounts five cards at once, so a shared id would paint from whichever
  // mounted last. useId is unique per instance; the strip is required because
  // React's ids carry punctuation (`:r0:` / `«r0»`) that `url(#…)` cannot hold.
  const id = `dhScrim${useId().replace(/[^a-zA-Z0-9]/g, '')}`;
  const h = Math.max(1, height);

  return (
    <Svg pointerEvents="none" width={width} height={h}>
      <Defs>
        <LinearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <Stop offset={0} stopColor={SCRIM_BASE} stopOpacity={0} />
          <Stop offset={0.25} stopColor={SCRIM_BASE} stopOpacity={0.16} />
          <Stop offset={0.5625} stopColor={SCRIM_BASE} stopOpacity={0.4} />
          <Stop offset={1} stopColor={SCRIM_BASE} stopOpacity={SCRIM_FLOOR} />
        </LinearGradient>
      </Defs>
      <Rect x={0} y={0} width={width} height={h} fill={`url(#${id})`} />
    </Svg>
  );
}

/**
 * The route SILHOUETTE, drawn only when the composer's switch is ON.
 *
 * What publishes: the output of `traceToBox` (src/lib/trace.ts) — real lat/lng
 * projected into a 0..1 aspect-preserved box. **Absolute coordinates do not
 * survive that call.** No basemap, no scale bar, no north arrow, no place name.
 * The line carries its own dark halo underneath for the same reason the type
 * gets a scrim: a white line on a white photo is as invisible as white text.
 */
function TraceSilhouette({ pts, size }: { pts: { x: number; y: number }[]; size: number }) {
  const PAD = 10;
  const d = pathFrom(pts, size, size, PAD);
  const at = (p: { x: number; y: number }) => ({
    cx: PAD + p.x * (size - PAD * 2),
    cy: PAD + p.y * (size - PAD * 2),
  });
  const a = at(pts[0]);
  const b = at(pts[pts.length - 1]);
  return (
    <Svg pointerEvents="none" width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      <Path d={d} stroke="rgba(11,9,6,0.55)" strokeWidth={7} strokeLinecap="round" strokeLinejoin="round" fill="none" />
      <Path d={d} stroke="#FFFFFF" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" fill="none" />
      {/* 출발 = filled · 도착 = ring. Same two marks the lab drew. */}
      <Circle cx={a.cx} cy={a.cy} r={5.5} fill="rgba(11,9,6,0.55)" />
      <Circle cx={a.cx} cy={a.cy} r={3.6} fill="#FFFFFF" />
      <Circle cx={b.cx} cy={b.cy} r={5.8} fill="none" stroke="rgba(11,9,6,0.55)" strokeWidth={4} />
      <Circle cx={b.cx} cy={b.cy} r={5.8} fill="none" stroke="#FFFFFF" strokeWidth={2} />
    </Svg>
  );
}

/**
 * ③ 스토리 — 9:16 poster, photo full-bleed, type straight on the photo.
 *
 * `photo` is a SLOT rather than a uri: the studio owns the pinch/pan photo layer
 * (PhotoLayer) and its gesture state, and dragging that in here would make this
 * component interactive. Everything that decides what the exported PNG SAYS
 * lives here; the thing the person manipulates stays in the studio.
 *
 * `data.trace` is the export gate itself: the studio passes `null` whenever the
 * composer's 경로 switch is off. There is no second path to a drawn route — if
 * this prop is null, no route pixel exists in the tree, so none can be captured.
 */
export function StoryShareCard({
  data, width, height, df, nf, photo,
}: {
  data: RunCardData;
  width: number;
  height: number;
  /** useDisplayFont() — loading stays the caller's job (this component takes no async). */
  df: any;
  /** useNumFont() — Oswald. Every numeral below carries an explicit lineHeight ≥1.2× (BUG A). */
  nf: any;
  /** Full-bleed photo layer, or a labelled empty state. Never stock imagery. */
  photo: ReactNode;
}) {
  // No state, no measurement. See `ScrimRamp` for why: the flat floor is the type
  // block's own background, so it is coextensive with the type by construction —
  // there is nothing to measure and no first-frame guess to get wrong.
  const ramp = Math.round(height * 0.152); // lab: 105.6px of a 693px card

  const time = fmtDur(data.durationSec);
  const pace = fmtPace(data.paceSecPerKm);
  // Value + label pairs. A null value drops its whole column — the card never
  // prints a dash, a zero or an em-dash in place of a number nobody measured.
  const trio: [string, string][] = [
    // km도 이제 이 규칙을 따른다 — 위 주석의 「A null value drops its whole column」이 원래
    // 이 필드만 예외였다.
    ...(data.km != null ? ([[`${data.km}`, '거리 km']] as [string, string][]) : []),
    ...(pace ? ([[pace, '페이스']] as [string, string][]) : []),
    ...(time ? ([[time, '시간']] as [string, string][]) : []),
  ];

  return (
    <View style={{ width, height, overflow: 'hidden', backgroundColor: paper.ink }}>
      {photo}

      {/* One column pinned to the bottom edge, three boxes, top to bottom:
            [ 경로 모양 — over bare photo, carrying its own halo   ]
            [ ramp     — fixed height, the fade down to the floor  ]
            [ floor fill — the type block's background, every glyph ]
          Because the last box IS the text block, the constant floor cannot be
          shorter than the text it carries. Nothing here measures anything.

          ⚠ The trace deliberately sits ABOVE the floor rather than on it. Two
          reasons, and the second is the load-bearing one:
            · it does not need the floor — the silhouette carries a dark halo
              under its white stroke, which is the lab's own stated mechanism for
              making it legible on a light photo and a dark one alike;
            · folding it into the floor would push the darkened band from about
              HALF the card to about THREE QUARTERS (computed from these exact
              paddings and line heights: 249 of a 500pt card with the route off,
              271 with it on, against 375 if the artwork were folded in). The
              whole point of his amendment was 「just text overlaid on photo」 —
              less box, not more. A floor that grew to swallow the artwork would
              answer the contrast question by undoing the request. The lab's own
              ⑥ puts the silhouette over the ramp for the same reason (its scrim
              is 330 of a 693px card = 48%). */}
      <View
        pointerEvents="none"
        style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}
      >
        {/* 경로 모양 — present only when the composer's switch put it there. */}
        {data.trace && data.trace.length > 1 && (
          <View style={{ alignSelf: 'flex-end', paddingHorizontal: 18, marginBottom: 8 }}>
            <TraceSilhouette pts={data.trace} size={96} />
          </View>
        )}

        <ScrimRamp width={width} height={ramp} />
        <View style={{ backgroundColor: SCRIM_FLOOR_FILL, paddingHorizontal: 18, paddingBottom: 18 }}>
          {/* The silhouette's caption. It lives DOWN HERE, inside the floor, and not
              under the artwork where it was drawn — the artwork is legible on its own
              halo, but a 10pt line is not, and over bare photo its contrast would be
              a text-shadow guess rather than a number. On the floor it is 4.74:1.
              (Latin serial — the letterspaced-kicker exemption to the 15pt floor.) */}
          {data.trace && data.trace.length > 1 && (
            <Text {...FIXED_TYPE} style={{ fontSize: 10, letterSpacing: 1.8, fontWeight: '700', color: SCRIM_LABEL_INK, textAlign: 'right', paddingTop: 10 }}>
              START · END
            </Text>
          )}

          {/* Display line — the card's ONE Black Han Sans line (≤1 per surface).
              #FFFFFF end to end: see the coralSoft note in this file's header.
              ⚠ 「오늘」 WAS HARDCODED HERE and it was a lie on most cards — the studio opens on
                any completed run, so a two-week-old run published a card reading 「초코, 오늘
                0km」 directly above its own footer date 「8월 11일 (화)」. Caught on the simulator
                (2026-08-26), not in review: the contradiction is only obvious when you see both
                lines at once. This component is PURE by construction — props only, no clock, no
                fetch (the view-shot capture requires it) — so it cannot ask what day it is, and
                a component that cannot know must not assert. The date is already on the card,
                so the temporal claim is dropped rather than plumbed: one fewer prop and no state
                in which it can be wrong. This card LEAVES THE APP, which is what makes a small
                inaccuracy a published one. */}
          <Text {...FIXED_TYPE} style={[{ fontSize: 24, lineHeight: 30, fontWeight: '900', color: '#FFFFFF', letterSpacing: -0.2 }, df]}>
            {data.dogName}{data.km != null ? `, ${data.km}km` : ''}
          </Text>

          <View style={{ flexDirection: 'row', marginTop: 14, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.34)' }}>
            {trio.map(([v, l], i) => (
              <View
                key={l}
                style={{
                  flex: 1, paddingTop: 12, paddingHorizontal: i === 0 ? 0 : 12,
                  ...(i === 0 ? {} : { borderLeftWidth: 1, borderLeftColor: 'rgba(255,255,255,0.34)' }),
                }}
              >
                <Text {...FIXED_TYPE} style={[{ fontSize: 24, lineHeight: 30, color: '#FFFFFF', fontWeight: '900' }, nf]}>{v}</Text>
                {/* Korean, so it sits at the 15pt floor — and at #EDEAE3, not #D8D6D0. */}
                <Text {...FIXED_TYPE} style={{ fontSize: 15, lineHeight: 21, fontWeight: '700', color: SCRIM_LABEL_INK }}>{l}</Text>
              </View>
            ))}
          </View>

          <View style={{ flexDirection: 'row', alignItems: 'baseline', marginTop: 14, paddingTop: 12 }}>
            {/* The date the run happened, and — only when the composer's switch put it there —
                the course name beside it. ⚠ [device-verified 2026-08-26] This card previously
                did NOT render `routeName` at all, while the studio's new 코스 이름 switch told the
                person 「카드에 「…」이 들어가요」. The switch was promising something this skin could
                not keep, on the one screen whose whole subject is what does and does not get
                published. Found by flipping the switch on the simulator; a code read had passed it.
                Same gate as the trace: the studio hands `null` unless the switch is ON. */}
            <Text {...FIXED_TYPE} style={{ flexShrink: 1, fontSize: 15, lineHeight: 21, fontWeight: '800', color: '#FFFFFF' }} numberOfLines={1}>
              {data.when}{data.routeName ? ` · ${data.routeName}` : ''}
            </Text>
            {/* Wordmark — logo artwork (DESIGN.md §3): a mark, no data, Latin serial.
                flexShrink 0: a long date truncates, the brand mark never does. */}
            <Text
              {...FIXED_TYPE}
              accessibilityElementsHidden
              importantForAccessibility="no-hide-descendants"
              style={{ flexShrink: 0, marginLeft: 'auto', paddingLeft: 10, fontSize: 10, letterSpacing: 1.8, fontWeight: '700', color: SCRIM_LABEL_INK }}
            >
              DOGS HIGH
            </Text>
          </View>
        </View>
      </View>
    </View>
  );
}
