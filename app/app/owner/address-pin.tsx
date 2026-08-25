import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { Addr, fetchAddresses, setAddressPin, updateAddressDetail } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { BANPO, getNaverMap, getOneShotPosition } from '../../src/lib/geo';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { supabase } from '../../src/lib/supabase';
import { paper } from '../../src/theme';

// Pickup pin picker (0065 coordinates slice, DS-4) — pin is truth: coordinates are
// written only from a user-confirmed pin; geocoding is a pre-center hint, never
// silently saved.
//
// [2026-08-24 · Sean: "Maybe the map picker should have a comment addition box." — 🔵 BUILT]
// His "maybe" was a judgment call with one hard condition: bind or omit. It binds. The column
// already exists (`addresses.detail`, 0001:122), it already has exactly one narrow writer
// (`owner_update_address_detail`, 0073 — trims, empty→NULL, caps at 60), and the sentence
// already has a reader: the assigned runner sees it on the handoff screen
// (`booking_pickup_address` → runner/meetup.tsx). So this box is not a new field, it is the
// same field asked for at the moment the owner is already answering "where exactly".
// A pin says WHERE; the memo says the part a coordinate cannot carry ("공동현관 #1204").
// The 60-char maxLength here is the server's number, mirrored to warn early — the server
// remains the single owner of the rule (0073 §normalise).
// Center priority chain (AD-7): existing pin (edit mode) → geocode-address edge fn
// → one-shot GPS (never prompts) → BANPO fallback. The map mounts IMMEDIATELY at
// the best-available-so-far center; at most ONE animated recenter if a better
// center arrives before the user pans; after the first pan the user's camera wins.

// 반포한강공원 fallback — the pilot neighborhood's center of gravity.
// ⚠ MOVED to `src/lib/geo.ts` (2026-08-25) and imported at the top of this file. It used to be
// DECLARED here and `runner/base-pin.tsx` imported it from this screen, which meant opening a
// runner picker evaluated an owner screen module. Nothing else imported it, so this is an import
// line changing address — no behaviour in this file moves.

// E9 curated Banpo spot chips — each chip only MOVES the camera; the user still
// confirms the pin, so slight offsets self-correct (plan §E9, AD-14).
const SPOTS: { label: string; lat: number; lng: number }[] = [
  { label: '잠수교 남단 입구', lat: 37.5158, lng: 126.9958 },
  { label: '세빛섬 앞', lat: 37.5122, lng: 126.9961 },
  { label: '서래섬 동측 입구', lat: 37.5111, lng: 126.9895 },
  { label: '반포한강공원 4주차장', lat: 37.5089, lng: 127.0012 },
  { label: '몽마르뜨공원 입구', lat: 37.5041, lng: 126.9989 },
  { label: '반포천 산책로', lat: 37.5049, lng: 127.0114 },
  { label: '고속터미널 8-1번 출구', lat: 37.5057, lng: 127.0043 },
  { label: '반포본동 주민센터', lat: 37.5083, lng: 126.9880 },
];

// Korea-plausible bounds — mirrors the server CHECK addresses_latlng_shape.
// The client validates first so the failure is a Korean sentence, not a 23514.
const inBounds = (lat: number, lng: number) =>
  lat >= 33 && lat <= 39 && lng >= 124 && lng <= 132;

// Geocode pre-center hint (ES-10): ANY invoke error, undeployed function, or a
// response that isn't {available:true, lat:number, lng:number} means "unavailable"
// — silent fallback down the chain, never parse error bodies, never surface it.
async function tryGeocode(query: string): Promise<{ lat: number; lng: number } | null> {
  try {
    const { data, error } = await supabase.functions.invoke('geocode-address', { body: { query } });
    if (error) return null;
    if (!data || data.available !== true) return null;
    if (typeof data.lat !== 'number' || typeof data.lng !== 'number') return null;
    return { lat: data.lat, lng: data.lng };
  } catch { return null; }
}

export default function AddressPin() {
  const df = useDisplayFont();
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();
  const [row, setRow] = useState<Addr | null>(null);
  const [resolving, setResolving] = useState(true);
  const [bottomed, setBottomed] = useState(false); // chain ended at the BANPO fallback
  const [selSpot, setSelSpot] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<null | 'bounds' | 'save'>(null);
  // 픽업 메모 — addresses.tsx의 메모 스트립과 같은 문법·같은 쓰기 경로 (updateAddressDetail)
  const [noteOpen, setNoteOpen] = useState(false);
  const [noteVal, setNoteVal] = useState('');
  const [noteBusy, setNoteBusy] = useState(false);

  // Camera truth lives in refs — reading it on confirm must not re-render the map.
  const mapRef = useRef<any>(null);
  const centerRef = useRef<{ lat: number; lng: number }>({ ...BANPO });
  const pannedRef = useRef(false);     // first Gesture locks out any auto-recenter (AD-7)
  const recenteredRef = useRef(false); // the chain gets exactly one animated recenter
  const selRef = useRef<number | null>(null);

  const maps = useRef(getNaverMap()).current;

  // Center priority chain — runs once per address id. The map is already mounted
  // at BANPO; a better center animates in only if the user hasn't panned yet.
  useEffect(() => {
    let alive = true;
    (async () => {
      let best: { lat: number; lng: number } | null = null;
      let fell = false;
      let zoom = 15;
      try {
        const rows = await fetchAddresses();
        const r = rows.find((a) => a.id === id) ?? null;
        if (alive && r) setRow(r);
        if (r && r.lat != null && r.lng != null) {
          best = { lat: r.lat, lng: r.lng }; // edit mode — skip geocode/GPS entirely
          zoom = 16;
        } else if (r) {
          best = await tryGeocode(r.addr);
          if (best) zoom = 16;
          if (!best) best = await getOneShotPosition();
          if (!best) { best = { ...BANPO }; fell = true; }
        } else {
          best = { ...BANPO }; fell = true;
        }
      } catch {
        best = { ...BANPO }; fell = true;
      }
      if (!alive) return;
      setResolving(false);
      setBottomed(fell);
      const better = best.lat !== BANPO.lat || best.lng !== BANPO.lng;
      if (better && !pannedRef.current && !recenteredRef.current) {
        recenteredRef.current = true;
        centerRef.current = best;
        mapRef.current?.animateCameraTo({ latitude: best.lat, longitude: best.lng, zoom, duration: 600 });
      }
    })();
    return () => { alive = false; };
  }, [id]);

  const onCameraChanged = (p: { latitude: number; longitude: number; reason: string }) => {
    centerRef.current = { lat: p.latitude, lng: p.longitude };
    if (p.reason === 'Gesture') {
      pannedRef.current = true; // user intent — the chain may never recenter again
      if (selRef.current !== null) { selRef.current = null; setSelSpot(null); }
    }
  };
  const onCameraIdle = (p: { latitude: number; longitude: number }) => {
    centerRef.current = { lat: p.latitude, lng: p.longitude };
  };

  const jumpToSpot = (i: number) => {
    const s = SPOTS[i];
    selRef.current = i;
    setSelSpot(i);
    pannedRef.current = true; // choosing a spot is user intent — chain must not override
    centerRef.current = { lat: s.lat, lng: s.lng };
    setErr(null);
    mapRef.current?.animateCameraTo({ latitude: s.lat, longitude: s.lng, zoom: 16, duration: 500 });
  };

  const openNote = () => { setNoteVal(row?.detail ?? ''); setNoteOpen(true); };
  // 저장 뒤에는 **서버가 가진 값**을 다시 읽어 그린다 — 트림·빈문자열→NULL은 0073이 단일
  // 소유자이고, 클라가 그 규칙을 흉내 내 그리면 두 개의 규칙이 생긴다. 재조회가 실패했을
  // 때만 문서화된 정규화를 그대로 반영한 낙관값을 쓴다 (저장 자체는 이미 성공한 상태).
  const saveNote = async () => {
    if (!id || noteBusy) return;
    setNoteBusy(true);
    try {
      await updateAddressDetail(id, noteVal);
      const rows = await fetchAddresses().catch(() => null);
      const fresh = rows?.find((a) => a.id === id) ?? null;
      if (fresh) setRow(fresh);
      else setRow((prev) => (prev ? { ...prev, detail: noteVal.trim() || null } : prev));
      setNoteOpen(false);
      haptic('success');
    } catch (e) {
      // 조용한 실패 금지 — 보호자는 러너가 읽을 문장을 바꿨다고 믿는다 (addresses.tsx와 같은 문장)
      Alert.alert('메모 저장 실패', (e as Error).message);
    } finally { setNoteBusy(false); }
  };

  const confirm = async () => {
    if (busy || !id) return;
    const c = centerRef.current;
    if (!inBounds(c.lat, c.lng)) { setErr('bounds'); return; }
    setErr(null);
    setBusy(true);
    try {
      await setAddressPin(id, c.lat, c.lng);
      haptic('success');
      router.back();
    } catch (e) {
      console.warn('[addr-pin] save:', (e as Error)?.message ?? e);
      setErr('save'); // stay on screen — the strip is the retry path
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* header — paddingTop 56 idiom + circleBtn back */}
      <Row style={s.header}>
        <Pressable onPress={goBackOrHome} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
      </Row>
      {/* the screen's one display-font slot */}
      <Text style={[s.title, df]}>어디서 만날까요?</Text>

      {/* address banner — what am I pinning */}
      <View style={s.banner}>
        <Text style={s.bannerAddr} numberOfLines={2}>
          {row ? `${row.label} · ${row.addr}` : resolving ? '주소 확인 중...' : '주소를 불러오지 못했어요'}
        </Text>
        {resolving ? (
          <Text style={s.bannerStatus}>주소 위치 찾는 중…</Text>
        ) : bottomed ? (
          /* [honesty 2026-08-20] `bottomed` means the whole chain missed: geocode said
             unavailable AND one-shot GPS returned nothing, so the camera is sitting on the
             BANPO constant (:23) — a place the user never gave us. The banner said only
             "지도를 움직여…", so a fallback centre was indistinguishable from a located address,
             and on this screen the pin IS the saved truth (header note, :14-16): a confirmed
             pin can be kilometres from the address printed one line above. Name the default;
             the instruction line stays because it is still what the user has to do. */
          <>
            <Text style={s.bannerStatus}>주소 위치를 찾지 못했어요 — 반포한강공원을 기본 위치로 보여주고 있어요</Text>
            <Text style={s.bannerStatus}>지도를 움직여 픽업 위치에 핀을 맞춰주세요</Text>
          </>
        ) : null}
      </View>

      {/* full-bleed map + fixed center crosshair */}
      <View style={{ flex: 1 }}>
        {maps ? (
          <>
            <maps.NaverMapView
              ref={mapRef}
              style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
              initialCamera={{ latitude: BANPO.lat, longitude: BANPO.lng, zoom: 15 }}
              onCameraChanged={onCameraChanged}
              onCameraIdle={onCameraIdle}
              isShowLocationButton={false}
              isShowCompass={false}
              isShowScaleBar={false}
              isShowZoomControls={false}
            />
            {/* fixed center crosshair — sharp system glyph (square head + 2px bar),
                overlaid View so it never pans with the map; the bar tip = camera center */}
            <View pointerEvents="none" style={s.pinWrap}>
              <View style={s.pinGlyph}>
                <View style={s.pinHead} />
                <View style={s.pinBar} />
              </View>
            </View>
          </>
        ) : (
          /* SDK unavailable — house placeholder idiom; confirm hidden (dead-button law) */
          <View style={s.mapFallbackWrap}>
            <View style={s.mapFallback}>
              <Text style={s.mapFallbackTxt}>지도를 불러올 수 없어요</Text>
            </View>
          </View>
        )}
      </View>

      {maps && (
        <>
          {/* E9 spot chips — each tap only moves the camera; the pin is still confirmed by the user */}
          <View style={s.chipStrip}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow}>
              {SPOTS.map((sp, i) => (
                <Pressable
                  key={sp.label}
                  onPress={() => jumpToSpot(i)}
                  style={[s.chip, selSpot === i && s.chipOn]}
                  accessibilityRole="button"
                  accessibilityLabel={sp.label}
                >
                  <Text style={[s.chipTxt, selSpot === i && s.chipTxtOn]}>{sp.label}</Text>
                </Pressable>
              ))}
            </ScrollView>
          </View>

          {/* failures shown as failures — bounds is a sentence, save failure is a retry strip */}
          {err === 'bounds' && (
            <View style={s.failStrip}>
              <Text style={s.failTxt}>서비스 지역을 벗어났어요</Text>
            </View>
          )}
          {err === 'save' && (
            <Pressable onPress={confirm} style={s.failStrip} accessibilityRole="button" accessibilityLabel="다시 시도">
              <Text style={s.failTxt}>저장하지 못했어요 · 다시 시도</Text>
            </Pressable>
          )}
        </>
      )}

      {/* 픽업 메모 — 지도가 없어도 쓸 수 있다(핀과 독립된 사실이다). 구분선은 뉴트럴:
          이 화면의 코랄 가로선은 배너 아래와 칩 스트립 위 둘로 유지한다 */}
      {row && (noteOpen ? (
        <View style={s.noteEdit}>
          <TextInput
            value={noteVal}
            onChangeText={setNoteVal}
            placeholder="예: 공동현관 #1204 · 경비실에 맡겨주세요"
            placeholderTextColor={paper.faint}
            style={s.noteInput}
            maxLength={60}
            autoFocus
            multiline={false}
            returnKeyType="done"
            onSubmitEditing={saveNote}
          />
          <Text style={s.noteCount}>{noteVal.length}/60 · 러너가 이 문장을 봐요</Text>
          <Row style={{ gap: 8, marginTop: 10 }}>
            {/* 이 화면의 코랄 프라이머리는 '이 위치로 지정' 하나다 — 메모 저장은 세컨더리 */}
            <PaperBtn label="메모 저장" busyLabel="저장 중..." busy={noteBusy} variant="secondary" onPress={saveNote} style={{ flex: 1.4 }} />
            <PaperBtn label="취소" variant="quiet" onPress={() => setNoteOpen(false)} style={{ flex: 1 }} />
          </Row>
        </View>
      ) : (
        <Pressable
          onPress={openNote}
          style={s.noteStrip}
          accessibilityRole="button"
          accessibilityLabel={row.detail ? '픽업 메모 수정' : '픽업 메모 추가'}
        >
          {row.detail
            ? <Text style={s.noteSetTxt} numberOfLines={1}>메모 · {row.detail} ›</Text>
            : <Text style={s.noteNeedTxt}>픽업 메모 추가 › <Text style={s.noteHint}>동·호수, 만날 지점 — 러너가 읽어요</Text></Text>}
        </Pressable>
      ))}

      {maps && (
        /* confirm bar — coral, full width; busy = label swap, never disabled paint.
           [2026-08-24] `style={{backgroundColor: paper.line}}` 삭제 — paper-btn.tsx:70-73이
           호출자 style을 매트릭스 **앞**으로 옮긴 뒤로 이 프롭은 아무것도 하지 않는 죽은 값이었다
           (버튼은 이미 paper.action으로 그려지고 있었다). 그 리뷰 노트가 이름을 댄 화면이 여기다. */
        <View style={[s.confirmBar, { paddingBottom: Math.max(insets.bottom, 12) + 12 }]}>
          <PaperBtn
            label="이 위치로 지정"
            busyLabel="저장 중..."
            busy={busy}
            onPress={confirm}
          />
        </View>
      )}
    </View>
  );
}

const PAD = 16;

const s = StyleSheet.create({
  header: { paddingTop: 56, paddingHorizontal: PAD },
  circleBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  title: { fontSize: 24, fontWeight: '900', color: paper.ink, paddingHorizontal: PAD, marginTop: 12 },
  banner: {
    paddingHorizontal: PAD, paddingTop: 8, paddingBottom: 12,
    borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  bannerAddr: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.ink },
  bannerStatus: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 4 },

  // crosshair pin — the glyph column is 30pt tall; translate up by half so the
  // bar's bottom tip sits exactly on the camera center.
  pinWrap: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  pinGlyph: { alignItems: 'center', transform: [{ translateY: -15 }] },
  pinHead: { width: 12, height: 12, backgroundColor: paper.line, borderWidth: 1, borderColor: paper.canvas },
  pinBar: { width: 2, height: 18, backgroundColor: paper.line },

  mapFallbackWrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: PAD },
  mapFallback: {
    alignSelf: 'stretch', height: 92, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
  },
  mapFallbackTxt: { fontSize: 14, fontWeight: '700', color: paper.dim },

  chipStrip: { borderTopWidth: 1, borderTopColor: paper.line, backgroundColor: paper.canvas },
  chipRow: { paddingHorizontal: PAD, paddingVertical: 10, gap: 8 },
  chip: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.faint,
    paddingVertical: 10, paddingHorizontal: 12, justifyContent: 'center',
  },
  chipOn: { borderColor: paper.line },
  chipTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.text },
  chipTxtOn: { color: paper.line, fontWeight: '800' },

  // save-failure / bounds strip — addrFailStrip grammar (runner/meetup.tsx)
  failStrip: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.criticalWash, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: 12,
  },
  failTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical },

  confirmBar: { paddingHorizontal: PAD, paddingTop: 10, backgroundColor: paper.canvas },

  // 픽업 메모 — addresses.tsx 카드 스트립과 같은 문법(≥44pt, 뉴트럴 구분선, 두 상태 모두 동작)
  noteStrip: {
    borderTopWidth: 1, borderTopColor: '#EEEEEE', backgroundColor: paper.canvas,
    paddingHorizontal: PAD, minHeight: 48, justifyContent: 'center',
  },
  noteSetTxt: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.dim },
  // 읽는 코랄(6.67:1) — paper.line은 3.64:1이라 14pt 라벨에 쓰지 않는다 (A① 실측)
  noteNeedTxt: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.actionInk },
  noteHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim },
  noteEdit: {
    borderTopWidth: 1, borderTopColor: '#EEEEEE', backgroundColor: paper.canvas,
    paddingHorizontal: PAD, paddingTop: 12, paddingBottom: 4,
  },
  noteInput: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 11, paddingHorizontal: 12, fontSize: 15.5, color: paper.ink,
  },
  noteCount: { fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 6 },
});
