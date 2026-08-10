// PickupMap — static pickup-pin map for the meetup plates (0065 coordinates slice).
//
// ES-3 contract: both meetup screens re-render their whole tree on an 8s poll, so
// this component is memoized on primitive props and owns ALL of its state — the
// screens' hook-freeze law forbids new hooks in their bodies, and a re-created
// native map view on every poll tick would jank a frozen screen.
//
// DS-7 contract: the plate's placeholder look stays mounted OVER the map until the
// SDK reports ready (onInitialized), then cross-fades out (200ms, native driver).
// onInitialized is first-use API in this repo, so a 1.5s timeout force-reveals —
// the cover must never permanently hide a live map. Static camera, every gesture
// disabled (report.tsx idiom): this plate states "here is the pickup", nothing
// live — the marker caption grounds it ("픽업"), no motion claims (DS-3).
import { memo, useEffect, useRef, useState } from 'react';
import { Animated, StyleSheet, Text, View } from 'react-native';
import { getNaverMap } from '../lib/geo';
import { paper } from '../theme';

export const PickupMap = memo(function PickupMap({ lat, lng, caption = '픽업' }: {
  lat: number; lng: number; caption?: string;
}) {
  const maps = getNaverMap();
  const [covered, setCovered] = useState(true);
  const fade = useRef(new Animated.Value(1)).current;
  const revealed = useRef(false);

  const reveal = () => {
    if (revealed.current) return;
    revealed.current = true;
    Animated.timing(fade, { toValue: 0, duration: 200, useNativeDriver: true })
      .start(() => setCovered(false));
  };

  useEffect(() => {
    const tm = setTimeout(reveal, 1500); // force-reveal fallback (ES-3)
    return () => clearTimeout(tm);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!maps) {
    // SDK unavailable — honest placeholder, same grammar as the plates' pending box
    return (
      <View style={[StyleSheet.absoluteFill, st.center]}>
        <View style={st.pendingBox}><Text style={st.pendingTxt}>지도를 불러올 수 없어요</Text></View>
      </View>
    );
  }

  return (
    <View style={StyleSheet.absoluteFill}>
      <maps.NaverMapView
        style={{ flex: 1 }}
        camera={{ latitude: lat, longitude: lng, zoom: 15.5 }}
        isShowLocationButton={false}
        isShowCompass={false}
        isShowScaleBar={false}
        isShowZoomControls={false}
        isScrollGesturesEnabled={false}
        isZoomGesturesEnabled={false}
        isTiltGesturesEnabled={false}
        isRotateGesturesEnabled={false}
        onInitialized={reveal}
      >
        <maps.NaverMapMarkerOverlay
          latitude={lat}
          longitude={lng}
          anchor={{ x: 0.5, y: 1 }}
          caption={{ text: caption }}
        />
      </maps.NaverMapView>
      {covered && (
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, st.center, { opacity: fade, backgroundColor: paper.canvas }]}>
          <View style={st.pendingBox}><Text style={st.pendingTxt}>지도 여는 중...</Text></View>
        </Animated.View>
      )}
    </View>
  );
});

const st = StyleSheet.create({
  center: { alignItems: 'center', justifyContent: 'center' },
  pendingBox: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 10, paddingHorizontal: 14, alignItems: 'center', justifyContent: 'center',
  },
  pendingTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.dim },
});
