import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  AppState, KeyboardAvoidingView, Linking, Platform, Pressable, ScrollView, StyleSheet, Text,
  TextInput, View,
} from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { updateMyProfile } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { getTrackPermission, requestTrackPermission } from '../../src/lib/geo';
import { supabase } from '../../src/lib/supabase';
import { layout, paper } from '../../src/theme';

// 러너 온보딩 (journey-v3 §B / O3, RULING 2) — 이름 + 홈 베이스 + 위치 권한.
//
// ⚠ 홈 베이스는 좌표가 아니다. The schema has no runner home-base column: `runners.service_radius_km`
// has no centre, and the nearest honest field is `profiles.district` (free text). So the copy says
// only what district actually does today — it SCOPES the course strip to that town (CourseStrip.tsx,
// 2026-08-26; before that it only sorted a whole-city deck, which is the defect Sean caught).
// The mock's "요청이 오는 반경의 중심" is NOT written here: it would be a promise no column keeps.
// A real home-base coordinate is a server slice.
//
// The permission ask is deliberate onboarding work (RULING 2): the reason is stated before the OS
// sheet, because the sheet is one-shot and a refusal is only recoverable through Settings. We ask
// for the grant ONLY — startTracking() would also raise the background task and its
// foreground-service notification, which has no business running before a run exists.

type Perm = 'undetermined' | 'granted' | 'denied' | 'unavailable';

export default function OnboardRunner() {
  const df = useDisplayFont();
  const [name, setName] = useState('');
  const [district, setDistrict] = useState('');
  const [perm, setPerm] = useState<Perm | null>(null); // null = 아직 확인 전
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // Re-read on every foreground: returning from Settings must move the plate, and there is no
  // event for "the user changed a system permission".
  useEffect(() => {
    let alive = true;
    const read = () => { getTrackPermission().then((p) => { if (alive) setPerm(p); }); };
    read();
    const sub = AppState.addEventListener('change', (st) => { if (st === 'active') read(); });
    return () => { alive = false; sub.remove(); };
  }, []);

  const ask = async () => {
    if (asking) return;
    setAsking(true);
    try { setPerm(await requestTrackPermission()); } finally { setAsking(false); }
  };

  const nm = name.trim();
  const dt = district.trim();
  const ready = nm.length > 0 && dt.length > 0;

  const finish = async () => {
    if (busy || !ready) return;
    setBusy(true);
    setErr(null);
    try {
      await updateMyProfile({ name: nm, district: dt });
      // updateMyProfile is a bare UPDATE: with no `profiles` row it matches zero rows and returns
      // NO error — a silent no-op that would render as success. The normal entry always has the
      // row (index.tsx upserts before it routes here), but a direct deep link does not, so read
      // back rather than trust the absence of an error.
      const { data: u } = await supabase.auth.getUser();
      const { data, error: readErr } = await supabase
        .from('profiles').select('district').eq('id', u.user?.id ?? '').maybeSingle();
      if (readErr) throw readErr;
      if ((data?.district ?? '') !== dt) throw new Error('프로필이 아직 없어요 — 시작 화면에서 러너를 다시 골라주세요');
      router.replace('/runner/home');
    } catch (e) {
      setErr((e as Error)?.message ?? '알 수 없는 오류');
    } finally {
      setBusy(false);
    }
  };

  return (
    <KeyboardAvoidingView style={s.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
        {/* Escape hatch. index.tsx pushes (never replaces) into onboarding precisely so this can
            exist: the root stack has no header and no back-swipe, so an owner who mistapped
            러너예요 previously had no in-app way out. Rendered only when there IS somewhere to go
            back to — a deep link straight here must not show a dead control. */}
        {router.canGoBack() && (
          <Pressable onPress={() => router.back()} hitSlop={10} style={s.back}
            accessibilityRole="button" accessibilityLabel="역할 다시 고르기">
            <Text style={s.backTxt}>‹ 역할 다시 고르기</Text>
          </Pressable>
        )}
        {/* The counter is DATA in a kicker slot, so it takes the 14pt detail floor — the
            exemption covers letterspaced Latin kickers (labels), not the step number itself
            (DESIGN.md §3, 14pt floor). */}
        <Text style={s.step} accessibilityLabel="1단계, 총 1단계">1 / 1</Text>
        <Text style={[s.title, df]}>이름과{'\n'}홈 베이스</Text>

        <TextInput
          style={s.fieldName}
          value={name}
          onChangeText={setName}
          placeholder="이름"
          placeholderTextColor={paper.faint}
          maxLength={20}
          returnKeyType="next"
          accessibilityLabel="러너 이름"
        />

        <Text style={s.kicker}>홈 베이스</Text>
        <TextInput
          style={s.fieldSub}
          value={district}
          onChangeText={setDistrict}
          placeholder="주로 뛰는 동네"
          placeholderTextColor={paper.faint}
          maxLength={40}
          returnKeyType="done"
          accessibilityLabel="홈 베이스 동네"
        />
        <Text style={s.hint}>주로 뛰는 동네 · 동네 코스를 먼저 보여드려요</Text>

        {/* 위치 권한 플레이트 — 상태별로 같은 자리에서 문장이 바뀐다 */}
        <View style={s.plate}>
          {perm === 'denied' ? (
            <>
              <Text style={s.plateHead}>러닝 중 위치가 없으면 보호자가 볼 수 없어요</Text>
              <Pressable
                onPress={() => { Linking.openSettings().catch(() => {}); }}
                style={s.plateBtn}
                accessibilityRole="button"
                accessibilityLabel="설정에서 위치 권한 켜기"
              >
                <Text style={s.plateAction}>설정에서 켜기 ›</Text>
              </Pressable>
            </>
          ) : perm === 'granted' ? (
            <>
              <Text style={s.plateHead}>러닝 중 위치를 보호자에게 보여줘요</Text>
              <Text style={s.plateSub}>러닝하는 동안만 · 예약한 보호자에게만</Text>
              <Text style={s.plateDone}>위치 권한 허용됨 ✓</Text>
            </>
          ) : perm === 'unavailable' ? (
            // Module missing ≠ permission refused — say the weaker, true thing.
            <>
              <Text style={s.plateHead}>이 빌드에는 위치 기능이 없어요</Text>
              <Text style={s.plateSub}>새 빌드에서 러닝 위치를 켤 수 있어요</Text>
            </>
          ) : (
            <>
              <Text style={s.plateHead}>러닝 중 위치를 보호자에게 보여줘요</Text>
              <Text style={s.plateSub}>러닝하는 동안만 · 예약한 보호자에게만</Text>
              <Pressable
                onPress={ask}
                disabled={perm == null || asking}
                style={s.plateBtn}
                accessibilityRole="button"
                accessibilityLabel="위치 권한 허용"
                accessibilityState={{ disabled: perm == null || asking }}
              >
                <Text style={[s.plateAction, (perm == null || asking) && { color: paper.faint }]}>
                  {perm == null ? '권한 상태 확인 중…' : asking ? '권한 요청 중…' : '위치 권한 허용 ›'}
                </Text>
              </Pressable>
            </>
          )}
        </View>
      </ScrollView>

      <View style={s.ctaBar}>
        {err != null && (
          <Pressable onPress={finish} style={s.failStrip} accessibilityRole="button" accessibilityLabel="저장 다시 시도">
            <Text style={s.failTxt}>저장하지 못했어요 — {err}</Text>
            <Text style={s.failAction}>다시 시도 ›</Text>
          </Pressable>
        )}
        <PaperBtn label="시작하기 ›" busyLabel="저장 중..." onPress={finish} disabled={!ready} busy={busy} />
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  body: { paddingHorizontal: layout.gutter, paddingTop: 78, paddingBottom: 140 },
  back: { minHeight: 44, justifyContent: 'center', marginBottom: 2 },
  backTxt: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.dim },
  step: { fontSize: 14, lineHeight: 18, letterSpacing: 2, fontWeight: '700', color: paper.dim },
  title: { fontSize: 24, lineHeight: 30, fontWeight: '900', color: paper.ink, marginTop: 12 },
  fieldName: {
    marginTop: 20, paddingTop: 10, paddingBottom: 8, minHeight: 44,
    borderBottomWidth: 1.5, borderBottomColor: paper.ink,
    fontSize: 20, fontWeight: '700', color: paper.ink,
  },
  kicker: { marginTop: 14, fontSize: 14, lineHeight: 18, letterSpacing: 1, fontWeight: '700', color: paper.dim },
  fieldSub: {
    marginTop: 2, paddingTop: 10, paddingBottom: 8, minHeight: 44,
    borderBottomWidth: 1.5, borderBottomColor: paper.ink,
    fontSize: 16, fontWeight: '700', color: paper.ink,
  },
  hint: { marginTop: 8, fontSize: 14, lineHeight: 20, color: paper.dim },
  plate: { marginTop: 20, paddingVertical: 13, paddingHorizontal: 14, backgroundColor: paper.wash },
  plateHead: { fontSize: 14, lineHeight: 20, fontWeight: '800', color: paper.ink },
  plateSub: { marginTop: 3, fontSize: 14, lineHeight: 20, color: paper.dim },
  plateBtn: { marginTop: 5, minHeight: 44, justifyContent: 'center' },
  plateAction: { fontSize: 14, lineHeight: 20, fontWeight: '800', color: paper.ink },
  plateDone: { marginTop: 9, fontSize: 14, lineHeight: 20, fontWeight: '700', color: paper.readyDeep },
  ctaBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    paddingHorizontal: layout.gutter, paddingTop: 10, paddingBottom: 30,
    borderTopWidth: 1, borderTopColor: paper.line,
  },
  failStrip: { backgroundColor: paper.criticalWash, padding: 12, marginBottom: 10 },
  failTxt: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: paper.critical },
  failAction: { marginTop: 4, fontSize: 14, lineHeight: 20, fontWeight: '800', color: paper.critical },
});
