import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { addAddress, addDog, fetchAddresses, updateMyDog } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { withParticle } from '../../src/lib/particle';
import { supabase } from '../../src/lib/supabase';
import { layout, paper } from '../../src/theme';

// 보호자 온보딩 (journey-v3 §B / O2, RULING 2) — 두 단계: 이름 + 주소 → 지도에 픽업 핀.
//
// [Sean 2026-08-19] "pick up point should be wherever the home owner puts, and the app should
// recommend the nearest path." So the pin is NOT an optional link tucked under the field — it is
// step 2, and the CTA leads into it. That ruling is load-bearing downstream, not decoration:
// `orderByProximity` (route-pick.ts:86) orders the course list AND the request carousel from the
// default address's pinned coordinate (course-map.tsx:129,165 · request.tsx:144), and
// request.tsx:497 already states that "가장 가까운" may only be claimed when that coordinate
// exists. An unpinned address silently degrades course recommendation — which is exactly what
// the 픽업 위치 line tells the owner.
//
// Coordinate doctrine (0065): geocoding NEVER writes lat/lng. The edge function is used here only
// as a *hint* under the address field, and only when it answers positively — `{available:false}`
// (secret absent, NCP down, timeout) draws NOTHING, because "we could not check" must not look
// like "we checked and it is fine". The coordinate comes from address-pin.tsx, untouched here;
// it pre-centres on its own geocode call and ends in `router.back()` (address-pin.tsx:145),
// which is what returns the owner to this screen.
//
// Save shape: ensureSaved() creates the dog and the address row at most once and is re-entrant,
// because every exit (into the map, back out of it, home) runs through it. There is no client
// path to rewrite `addresses.addr` — only `owner_update_address_detail` (0073) exists — so once
// the address row is written the input locks and says where it can be changed later. The dog
// name has updateMyDog and stays editable; each pass flushes an edit.

type Hint =
  | { k: 'none' }
  | { k: 'checking' }
  | { k: 'road'; road: string }
  | { k: 'nomatch' };

// Pin state of the saved row. 'unknown' is a real state, not a spinner-shaped nothing: claiming
// 찍어주세요 before the read lands would flash a lie at an owner who has just pinned.
type Pin = 'unknown' | 'pinned' | 'unpinned' | 'error';

export default function OnboardOwner() {
  const df = useDisplayFont();
  const [dogName, setDogName] = useState('');
  const [addr, setAddr] = useState('');
  const [hint, setHint] = useState<{ for: string; v: Hint }>({ for: '', v: { k: 'none' } });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [pin, setPin] = useState<Pin>('unknown');

  const dogIdRef = useRef<string | null>(null);
  const savedNameRef = useRef<string | null>(null);
  const [addressId, setAddressId] = useState<string | null>(null);
  const hintSeq = useRef(0);

  const dog = dogName.trim();
  const address = addr.trim();
  const ready = dog.length > 0 && address.length > 0;
  const step2 = addressId != null; // the address row exists ⇒ the map step owns the screen
  const locked = step2;

  // ---- geocode hint (debounced) — a hint, never a coordinate write ----
  // The hint carries the address it describes, so a hint for text the owner has since edited is
  // simply not rendered — no stale claim, and no reset-setState inside the effect body.
  useEffect(() => {
    if (locked || address.length < 4 || address.length > 100) return;
    const seq = ++hintSeq.current;
    const t = setTimeout(async () => {
      setHint({ for: address, v: { k: 'checking' } });
      let v: Hint = { k: 'none' };
      try {
        const { data, error } = await supabase.functions.invoke('geocode-address', { body: { query: address } });
        if (!error && data?.available === true) {
          v = typeof data.lat === 'number' && typeof data.lng === 'number'
            ? (typeof data.roadAddress === 'string' && data.roadAddress.length > 0
              ? { k: 'road', road: data.roadAddress }
              : { k: 'none' })   // matched, but nothing extra to tell the user
            : { k: 'nomatch' };  // available:true + lat:null = looked and found nothing
        }
      } catch { /* unavailable — say nothing rather than claim anything */ }
      if (hintSeq.current === seq) setHint({ for: address, v });
    }, 600);
    return () => clearTimeout(t);
  }, [address, locked]);

  // Every return from the map re-reads the row — server truth decides whether step 2 is done.
  // A read failure is its own state: we do not get to guess 'pinned' OR 'unpinned'.
  const checkPin = useCallback((id: string, alive: () => boolean) => {
    fetchAddresses()
      .then((rows) => {
        const r = rows.find((a) => a.id === id);
        if (alive()) setPin(r ? (r.lat != null && r.lng != null ? 'pinned' : 'unpinned') : 'error');
      })
      .catch(() => { if (alive()) setPin('error'); });
  }, []);

  useFocusEffect(useCallback(() => {
    if (!addressId) return;
    let live = true;
    setPin('unknown');
    checkPin(addressId, () => live);
    return () => { live = false; };
  }, [addressId, checkPin]));

  // Creates each row at most once; re-entrant after a trip to the pin picker.
  const ensureSaved = async (): Promise<string> => {
    if (dogIdRef.current == null) {
      dogIdRef.current = await addDog(dog);
      savedNameRef.current = dog;
    } else if (savedNameRef.current !== dog) {
      await updateMyDog(dogIdRef.current, { name: dog });
      savedNameRef.current = dog;
    }
    let aid = addressId;
    if (aid == null) {
      aid = await addAddress({ label: '우리집', addr: address });
      setAddressId(aid);
    }
    return aid;
  };

  // The retry strip repeats whichever exit failed — a save that failed on the way to the map
  // must not silently reroute the owner home.
  const lastAfter = useRef<((addressId: string) => void) | null>(null);
  const run = async (after: (addressId: string) => void) => {
    if (busy || !ready) return;
    lastAfter.current = after;
    setBusy(true);
    setErr(null);
    try {
      after(await ensureSaved());
    } catch (e) {
      setErr((e as Error)?.message ?? '알 수 없는 오류');
    } finally {
      setBusy(false);
    }
  };
  const retry = () => { const a = lastAfter.current; if (a) run(a); };

  const openPin = () => run((id) => router.push({ pathname: '/owner/address-pin', params: { id } }));
  const goHome = () => run(() => router.replace('/owner/home'));

  // One CTA, four phases. `홈으로` appears only once the server says the pin is written.
  const cta = !step2
    ? { label: `${withParticle(dog.length > 0 ? dog : '우리 아이', '와/과')} 시작하기 ›`, onPress: openPin, disabled: !ready }
    : pin === 'unknown' ? { label: '픽업 위치 확인 중...', onPress: () => {}, disabled: true }
      : pin === 'pinned' ? { label: '홈으로 ›', onPress: goHome, disabled: !ready }
        : { label: '지도에서 찍기 ›', onPress: openPin, disabled: !ready };

  // Skipping is allowed but never silent, and it is not a dead end: 마이 › 주소 관리 pins any
  // saved address later — addresses.tsx:82 `openPicker` pushes the same picker, wired to every
  // row at addresses.tsx:146.
  const skippable = step2 && (pin === 'unpinned' || pin === 'error');

  return (
    <KeyboardAvoidingView style={s.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
        {/* latin counter — the one detail-floor exemption on this screen (letterspaced kicker) */}
        <Text style={s.step} accessibilityLabel={step2 ? '2단계, 총 2단계' : '1단계, 총 2단계'}>
          {step2 ? '2 / 2' : '1 / 2'}
        </Text>
        <Text style={[s.title, df]}>우리 아이 이름과{'\n'}보통 출발하는 곳</Text>

        <TextInput
          style={s.fieldName}
          value={dogName}
          onChangeText={setDogName}
          placeholder="이름"
          placeholderTextColor={paper.faint}
          maxLength={20}
          returnKeyType="next"
          accessibilityLabel="반려견 이름"
        />

        <Text style={s.kicker}>시작 주소</Text>
        <TextInput
          style={[s.fieldAddr, locked && s.fieldLocked]}
          value={addr}
          onChangeText={setAddr}
          editable={!locked}
          placeholder="동네와 건물 이름"
          placeholderTextColor={paper.faint}
          maxLength={100}
          returnKeyType="done"
          accessibilityLabel="시작 주소"
        />

        {locked ? (
          <Text style={s.hint}>주소를 저장했어요 · 나중에 마이 › 주소 관리에서 바꿀 수 있어요</Text>
        ) : hint.for !== address ? null : hint.v.k === 'checking' ? (
          <Text style={s.hint}>주소 확인 중…</Text>
        ) : hint.v.k === 'road' ? (
          <Text style={s.hint}>도로명 · {hint.v.road}</Text>
        ) : hint.v.k === 'nomatch' ? (
          <Text style={s.hint}>주소를 찾지 못했어요 — 지도에서 맞춰주세요</Text>
        ) : null}

        {/* 픽업 위치 줄 — 단계 상태를 그대로 말한다 */}
        {!step2 ? (
          <Text style={s.quiet}>러너가 여기서 만나요 · 다음 화면에서 지도에 정확히 찍어요</Text>
        ) : pin === 'unknown' ? (
          <Text style={s.quiet}>픽업 위치를 확인하고 있어요…</Text>
        ) : pin === 'pinned' ? (
          <Pressable
            onPress={openPin}
            disabled={!ready || busy}
            style={s.pinRow}
            accessibilityRole="button"
            accessibilityLabel="픽업 위치 다시 찍기"
            accessibilityState={{ disabled: !ready || busy }}
          >
            <Text style={s.quiet}>
              픽업 위치를 지도에 찍었어요 ✓ ·{' '}
              <Text style={[s.quietLink, (!ready || busy) && { color: paper.faint }]}>다시 찍기 ›</Text>
            </Text>
          </Pressable>
        ) : pin === 'error' ? (
          <Pressable
            onPress={() => { if (addressId) { setPin('unknown'); checkPin(addressId, () => true); } }}
            style={s.pinRow}
            accessibilityRole="button"
            accessibilityLabel="픽업 위치 상태 다시 확인"
          >
            <Text style={s.quiet}>
              픽업 위치를 확인하지 못했어요 · <Text style={s.quietLink}>다시 확인 ›</Text>
            </Text>
          </Pressable>
        ) : (
          <Text style={s.quiet}>픽업 위치를 지도에서 찍어주세요 · 가까운 코스를 추천하려면 필요해요</Text>
        )}
      </ScrollView>

      <View style={s.ctaBar}>
        {err != null && (
          <Pressable onPress={retry} style={s.failStrip} accessibilityRole="button" accessibilityLabel="저장 다시 시도">
            <Text style={s.failTxt}>저장하지 못했어요 — {err}</Text>
            <Text style={s.failAction}>다시 시도 ›</Text>
          </Pressable>
        )}
        <PaperBtn
          label={cta.label}
          busyLabel="저장 중..."
          onPress={cta.onPress}
          disabled={cta.disabled}
          busy={busy}
        />
        {skippable && (
          <Pressable
            onPress={goHome}
            disabled={!ready || busy}
            style={s.later}
            accessibilityRole="button"
            accessibilityLabel="나중에 찍고 홈으로 가기"
            accessibilityState={{ disabled: !ready || busy }}
          >
            <Text style={[s.laterTxt, (!ready || busy) && { color: paper.faint }]}>나중에 · 홈으로</Text>
          </Pressable>
        )}
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  body: { paddingHorizontal: layout.gutter, paddingTop: 78, paddingBottom: 190 },
  step: { fontSize: 12, letterSpacing: 2, fontWeight: '700', color: paper.faint },
  title: { fontSize: 24, lineHeight: 30, fontWeight: '900', color: paper.ink, marginTop: 12 },
  // lab .field — bottom hairline in ink, 20/700 (address 16)
  fieldName: {
    marginTop: 20, paddingTop: 10, paddingBottom: 8, minHeight: 44,
    borderBottomWidth: 1.5, borderBottomColor: paper.ink,
    fontSize: 20, fontWeight: '700', color: paper.ink,
  },
  kicker: { marginTop: 14, fontSize: 14, lineHeight: 18, letterSpacing: 1, fontWeight: '700', color: paper.dim },
  fieldAddr: {
    marginTop: 2, paddingTop: 10, paddingBottom: 8, minHeight: 44,
    borderBottomWidth: 1.5, borderBottomColor: paper.ink,
    fontSize: 16, fontWeight: '700', color: paper.ink,
  },
  fieldLocked: { color: paper.text, borderBottomColor: '#DDDDDD' },
  hint: { marginTop: 8, fontSize: 14, lineHeight: 20, color: paper.dim },
  pinRow: { minHeight: 44, justifyContent: 'center' },
  quiet: { marginTop: 8, fontSize: 14, lineHeight: 22, color: paper.dim },
  quietLink: { color: paper.ink, fontWeight: '800' },
  ctaBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    paddingHorizontal: layout.gutter, paddingTop: 10, paddingBottom: 30,
    borderTopWidth: 1, borderTopColor: paper.line,
  },
  later: { minHeight: 44, alignItems: 'center', justifyContent: 'center', marginTop: 2 },
  laterTxt: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: paper.dim },
  failStrip: { backgroundColor: paper.criticalWash, padding: 12, marginBottom: 10 },
  failTxt: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: paper.critical },
  failAction: { marginTop: 4, fontSize: 14, lineHeight: 20, fontWeight: '800', color: paper.critical },
});
