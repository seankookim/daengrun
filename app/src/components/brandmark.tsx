// 도그스하이 brandmark — the running-dog mark (Sean-supplied asset, app/assets/logo.png).
//
// The source art is an elongated leaping hound in ink with a single coral speed streak.
// It ships as the PNG Sean provided (1619×971, aspect 1.667) rather than a hand-trace —
// the asset is the truth. `resizeMode="contain"` keeps the aspect at any height.
//
// Sizing: pass `height`; width follows the source aspect. Used at 40 in the owner-home
// masthead lockup; legible down to ~22.
import { Image, Text, View } from 'react-native';
import { useDisplayFont } from '../lib/displayFont';
import { paper } from '../theme';

const ASPECT = 1619 / 971; // source asset

export function BrandMark({ height = 40 }: { height?: number }) {
  return (
    <Image
      source={require('../../assets/logo.png')}
      style={{ width: height * ASPECT, height }}
      resizeMode="contain"
      accessibilityRole="image"
      accessibilityLabel="도그스하이"
    />
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
