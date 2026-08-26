import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { getTrackPermission, requestTrackPermission } from '../lib/geo';
import { paper } from '../theme';

// 첫 실행 위치 프라이머 — lab ①「한 줄」, Sean 확정 2026-08-26.
//
// WHY THIS EXISTS AT ALL: iOS asks exactly once. A reflexive refusal at the bare OS prompt, before
// the person knows what the app is for, is unrecoverable in-app — and location is what the entire
// running product rests on. This screen spends a cheap in-app moment so the OS's single question
// is only asked of someone who has been told why.
//
// 🔴 NO 「나중에」 BUTTON — Sean, verbatim: 「go with 1, no 나중에」. One action, deliberately.
// The cost was named and accepted: without a defer path, a refusal at the OS prompt cannot be
// re-asked in-app. It is bounded because the recovery path already ships — the run screens refuse
// to start without permission and three screens deep-link to Settings, so a refusal strands
// nobody; it only stops them running until they turn it on. For a running app that is honest.
//
// ⚠ COPY CEILING, and it is not stylistic: never promise tracking with the phone pocketed beyond
// what the build delivers, and never state or imply more than `NSLocationWhenInUseUsageDescription`
// already claims. The Always escalation is requested at RUN START (see `geo.ts`), never here —
// this screen's single ask is When-In-Use.
//
// ⚠ The owner and runner sentences differ because the TRUE reason differs. An owner IS the
// 보호자, so telling them we show their location "to the 보호자" would be false. Owners need this
// since Sean ruled 동반 (self-run) dogs get GPS and that the host runs with the pack.

export type PrimerRole = 'owner' | 'runner';

export function LocationPrimer({ role, onDone }: { role: PrimerRole; onDone: () => void }) {
  const [asking, setAsking] = useState(false);

  const ask = async () => {
    if (asking) return;
    setAsking(true);
    try {
      await requestTrackPermission();
    } finally {
      // Either answer moves on. The screen's job was the explanation, not the gate — and a
      // refusal must not trap anyone here, because there is no second button to escape with.
      setAsking(false);
      onDone();
    }
  };

  return (
    <View style={s.wrap}>
      <View style={s.body}>
        <Text style={s.kicker}>위치 사용</Text>
        <Text style={s.head}>러닝을 기록하려면{'\n'}위치가 필요해요</Text>
        <Text style={s.lede}>
          {role === 'runner'
            ? '달린 거리를 재고, 보호자에게 실시간 지도를 보여줘요.'
            : '함께 뛴 거리를 재고, 다녀온 코스를 기록으로 남겨요.'}
        </Text>
      </View>

      <View style={s.rule} />
      <Text style={s.limit}>러닝 중에만 사용하고, 끝나면 멈춰요.</Text>

      <Pressable
        onPress={ask}
        disabled={asking}
        style={[s.cta, asking && s.ctaBusy]}
        accessibilityRole="button"
        accessibilityState={{ disabled: asking }}
        accessibilityLabel="위치 사용 허용"
      >
        {/* busy = label swap, never an opacity trick (DESIGN.md button matrix) */}
        <Text style={[s.ctaTxt, asking && s.ctaTxtBusy]}>{asking ? '확인 중...' : '위치 사용 허용'}</Text>
      </Pressable>
    </View>
  );
}

// `undetermined` is the ONLY state worth a primer: granted has nothing to ask, and denied cannot
// be re-asked in-app so the screen would be a dead end. `unavailable` means the module is missing,
// which is not a refusal and must not be drawn as one.
export async function shouldShowPrimer(): Promise<boolean> {
  try {
    return (await getTrackPermission()) === 'undetermined';
  } catch {
    return false;
  }
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: paper.canvas },
  body: { paddingHorizontal: 20, paddingTop: 28 },
  kicker: { fontSize: 12, fontWeight: '800', letterSpacing: 1.9, color: paper.faint },
  head: { fontSize: 26, lineHeight: 34, fontWeight: '900', color: paper.ink, marginTop: 10 },
  lede: { fontSize: 16, lineHeight: 24, color: paper.text, marginTop: 12 },
  // solid coral hairline — 이 선이 곧 브랜드 (DESIGN.md §4)
  rule: { height: 1, backgroundColor: paper.line, marginTop: 'auto' },
  limit: { fontSize: 15, lineHeight: 22, color: paper.dim, paddingHorizontal: 20, paddingVertical: 16 },
  // paper.action (#C6472C), NOT paper.coral — coral is the retired lilac world's CTA. action is
  // the paper world's primary fill and carries a measured 4.84:1 against a white label.
  cta: { backgroundColor: paper.action, paddingVertical: 16, marginHorizontal: 20, marginBottom: 24 },
  ctaBusy: { backgroundColor: paper.disabledFill },
  ctaTxt: { textAlign: 'center', color: '#FFFFFF', fontSize: 16.5, fontWeight: '800' },
  ctaTxtBusy: { color: paper.faint },
});
