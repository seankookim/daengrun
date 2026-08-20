import { StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { paper } from '../theme';

// Opaque strip over the system status bar.
//
// Screens in this app scroll their own content from y=0 (paddingTop reserves the space but the
// ScrollView still paints under it), so date headers, map labels and card edges pass behind the
// clock and the Dynamic Island. owner/home solved that inline on 2026-08-19 with an absolute
// canvas strip; this is that same strip, extracted, because the defect was systemic (measured on
// schedule · earnings · availability · apply · community · my · alerts · course detail · course map).
//
// Two placement rules — both are about paint order, RN has no z-index arbitration beyond siblings:
//   · scroll screens: mount AFTER the ScrollView so the strip paints on top of the content.
//   · map screens:    mount AFTER the map but BEFORE the floating top chrome, so the strip covers
//                     the map and the chrome still covers the strip (a header card that starts
//                     above insets.top must not disappear behind it).
//
// `color` exists because the strip must be the screen's OWN canvas — a white strip on the lilac
// alerts board would read as a second surface, which is a different lie from the one we are fixing.
// pointerEvents="none": the clock's row must never swallow a tap.
export function StatusBarCover({ color = paper.canvas }: { color?: string }) {
  const insets = useSafeAreaInsets();
  if (insets.top <= 0) return null;
  return <View pointerEvents="none" style={[s.cover, { height: insets.top, backgroundColor: color }]} />;
}

const s = StyleSheet.create({
  // Height is injected from insets.top — never a constant (it differs per device).
  cover: { position: 'absolute', top: 0, left: 0, right: 0 },
});
