import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { homePath } from '../src/components/bottomnav';
import { PaperBtn } from '../src/components/paper-btn';
import { paper } from '../src/theme';

// Unmatched-route screen (2026-08-20). Without this file expo-router renders its OWN built-in
// screen: English dev chrome ("This screen doesn't exist.") plus a link that echoes the path the
// user tried. Every route in this app is reachable by URL — push payloads (`ref_id`), a shared
// link, a renamed screen — so an unmatched path is a real user destination, not a dev artifact.
//
// Three deliberate absences:
//  · No attempted path on screen. Echoing it IS the dev chrome, in a Korean wrapper — nobody
//    reading 도그스하이 can act on `/owner/reprot?bid=…`.
//  · No 다시 시도. Nothing was read, so nothing can be re-read; the only true action is leaving.
//  · No display font. This screen carries no display moment and the budget is one per screen.
//
// The exit is ROLE-AWARE. `/owner/home` hardcoded would strand a runner on a screen with an
// owner's tab bar — homePath() is the same source the dock and the swipe order already read.
export default function NotFound() {
  return (
    <View style={s.wrap}>
      <View style={s.rule} />
      <Text style={s.title}>이 화면을 찾을 수 없어요</Text>
      <Text style={s.body}>주소가 바뀌었거나 없는 페이지예요</Text>
      <PaperBtn label="홈으로" style={{ alignSelf: 'stretch', marginTop: 20 }} onPress={() => router.replace(homePath())} />
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: paper.canvas, justifyContent: 'center', paddingHorizontal: 24 },
  // §3b section law, applied to a standalone screen: one coral rule above the sentence rather
  // than a full-bleed section head — there is only one section here.
  rule: { height: 1, backgroundColor: paper.line, marginBottom: 18 },
  title: { fontSize: 23, fontWeight: '900', color: paper.ink },
  body: { fontSize: 15, lineHeight: 22, color: paper.dim, marginTop: 8 },
});
