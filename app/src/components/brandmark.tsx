// 도그스하이 brandmark — the running-dog mark (Sean-supplied logo, 2026-08-10).
//
// Vector traced from the source artwork: an elongated leaping hound, ink silhouette,
// with one coral speed-streak trailing the hind leg. The streak is the ONLY colored
// element and it carries the brand coral — no second accent, no gradient (style freeze).
//
// Sizing: pass `height`; width follows the 1.66:1 aspect of the source art. Used at
// 40 in the owner-home masthead lockup; the mark stays legible down to ~22.
import Svg, { Path } from 'react-native-svg';
import { Text, View } from 'react-native';
import { useDisplayFont } from '../lib/displayFont';
import { paper } from '../theme';

const ASPECT = 1600 / 960; // source art viewBox

export function BrandMark({ height = 40, ink = '#111111', streak = '#E8552F' }: {
  height?: number; ink?: string; streak?: string;
}) {
  return (
    <Svg width={height * ASPECT} height={height} viewBox="0 0 1600 960">
      {/* head · neck · back · tail — one continuous silhouette */}
      <Path
        d="M105 300 C 190 262, 245 240, 268 228 L 350 190 L 412 96 L 420 218
           C 470 268, 545 312, 620 340 C 760 392, 900 402, 1010 392
           C 1150 380, 1300 420, 1420 470 C 1480 495, 1530 518, 1575 540
           C 1500 500, 1400 452, 1300 420 C 1180 382, 1070 372, 960 380
           C 840 388, 730 398, 640 424 C 560 447, 500 452, 452 440
           C 330 410, 210 355, 105 300 Z"
        fill={ink}
      />
      {/* fore leg — tapered blade sweeping forward-down */}
      <Path
        d="M578 452 C 470 470, 300 555, 108 660 C 262 602, 432 542, 592 508
           C 610 490, 600 468, 578 452 Z"
        fill={ink}
      />
      {/* hind leg (near) — the long trailing blade */}
      <Path
        d="M690 520 C 806 604, 1004 752, 1232 900 C 1128 730, 998 600, 862 518
           C 812 494, 738 496, 690 520 Z"
        fill={ink}
      />
      {/* hind leg (far) — extends to the rear right */}
      <Path
        d="M1004 466 C 1152 518, 1352 640, 1522 730 C 1400 598, 1232 496, 1082 452
           C 1050 446, 1022 452, 1004 466 Z"
        fill={ink}
      />
      {/* coral speed streak — the mark's single accent */}
      <Path
        d="M1078 486 C 1200 518, 1382 620, 1522 722 C 1402 590, 1252 504, 1122 476
           C 1104 474, 1088 478, 1078 486 Z"
        fill={streak}
      />
      {/* eye — negative space in the ink */}
      <Path d="M243 214 C 268 206, 292 208, 306 218 C 286 228, 260 228, 243 214 Z" fill="#FFFFFF" />
    </Svg>
  );
}

// Full lockup: mark on the left, wordmark stacked on the right (Sean 2026-08-10).
export function BrandLockup({ height = 40 }: { height?: number }) {
  const df = useDisplayFont();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
      <BrandMark height={height} />
      <View style={{ marginLeft: 10 }}>
        <Text style={[{ fontSize: height * 0.66, lineHeight: height * 0.82, color: paper.ink }, df]}>
          도그스하이
        </Text>
        <Text style={{ fontSize: 11.5, fontWeight: '700', letterSpacing: 2.4, color: paper.dim, marginTop: -1 }}>
          DOGS HIGH
        </Text>
      </View>
    </View>
  );
}
