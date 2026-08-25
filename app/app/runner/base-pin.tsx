import { router } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { fetchMyRunnerBase, isBaseCooldownError, setRunnerBase } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { BANPO, getNaverMap } from '../../src/lib/geo';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { paper } from '../../src/theme';

// 러너 활동 기준 위치 — Sean's Q6 ruling B (2026-08-25): 「go with B for distance, and the runner
// should be able to switch this address in settings.」 이 화면이 그 "switch"다.
//
// owner/address-pin.tsx의 지도 피커를 **각색**한 것이고 그 화면을 재구성하지는 않았다. 둘은 같은
// 제스처(지도를 움직여 중심을 확정)를 공유하지만 서로 다른 화면이다:
//   · 보호자의 핀은 픽업 지점 — 6dp 그대로 저장되고, 배정된 러너가 24시간 창 안에서 읽는다.
//   · 러너의 기준점은 **거리 계산의 원점일 뿐** — 서버가 0.01°(~1.1km) 격자로 반올림해 저장하고,
//     누구에게도 좌표로 나가지 않는다. 나가는 건 「~1km」 같은 밴드 문자열 하나다.
// 그래서 여기엔 주소 배너도, 픽업 메모도, 스팟 칩도 없다 (러너의 집은 우리가 아는 주소가 아니다).
// 대신 여기에만 있는 것: 반올림을 **말하는** 문장과, 지울 수 있는 문.
//
// ⚠ 반올림을 숨기지 않는 이유. 저장 뒤 이 화면을 다시 열면 카메라는 러너가 찍은 지점이 아니라
// **격자 꼭짓점**에 선다 — 최대 ~550m 어긋난다. 말하지 않으면 그건 버그로 보이고, 말하면 그건
// 기능이다: 우리는 러너가 어디 사는지 정확히 알고 싶지 않다.
const HINT_ROUND = '대략적인 위치만 저장돼요 — 약 1km 격자로 반올림해서 기록하고, 정확한 주소는 저장하지 않아요';

// 잠금 문구. 「7일에 한 번」이라는 **숫자를 클라가 말하지 않는다** — 그 숫자는 서버의
// _base_change_cooldown() 하나에만 있고(0123 §4b, Sean 2026-08-25 T1 룰링), 여기서 되뇌면
// Sean이 숫자를 옮기는 날 이 화면이 거짓말을 한다. 서버가 주는 건 언제 열리는지(can_change_at)
// 하나이고, 화면은 그 날짜만 말한다.
const lockLine = (iso: string) => {
  const d = new Date(iso);
  return `${d.getMonth() + 1}월 ${d.getDate()}일부터 다시 지정할 수 있어요`;
};

// Korea-plausible bounds — 서버 CHECK(runners_base_shape / 0065의 같은 값)의 미러.
// 클라가 먼저 검사하는 이유는 실패가 23514가 아니라 한국어 문장이 되게 하려는 것뿐이다.
const inBounds = (lat: number, lng: number) =>
  lat >= 33 && lat <= 39 && lng >= 124 && lng <= 132;

export default function RunnerBasePin() {
  const df = useDisplayFont();
  const insets = useSafeAreaInsets();
  // resolving = 서버에 물어보는 중. 로딩은 0이 아니고 「미설정」도 아니다 — 셋은 다른 상태다.
  const [resolving, setResolving] = useState(true);
  const [saved, setSaved] = useState<{ lat: number; lng: number } | null>(null);
  const [notRunner, setNotRunner] = useState(false);
  const [readErr, setReadErr] = useState(false);
  const [busy, setBusy] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [err, setErr] = useState<null | 'bounds' | 'save' | 'clear' | 'cooldown'>(null);
  // 다시 바꿀 수 있는 시각. 서버가 준 결과값이지 클라가 계산한 값이 아니다 (api.ts RunnerBase).
  const [lockedUntil, setLockedUntil] = useState<string | null>(null);

  // 카메라 진실은 ref에 산다 — 확정 시점에 읽는 것이 지도를 다시 그리면 안 된다 (address-pin의 교리)
  const mapRef = useRef<any>(null);
  const centerRef = useRef<{ lat: number; lng: number }>({ ...BANPO });
  const pannedRef = useRef(false);
  const recenteredRef = useRef(false);

  // ⚠ address-pin은 `useRef(getNaverMap()).current`를 쓰지만 여기서는 useMemo다. 같은 값이고
  // (getNaverMap은 require 캐시 조회라 순수하다) react-hooks/refs 경고 4건이 없다. 저쪽을
  // 고치지 않는 이유는 이 슬라이스가 그 화면의 흐름을 건드리지 않기로 했기 때문 — 새 파일만
  // 깨끗한 형태로 태어난다.
  const maps = useMemo(() => getNaverMap(), []);

  // 중심 우선순위: 저장된 기준점 → BANPO 상수. **그게 전부다.**
  // 🔴 여기엔 GPS가 없고, 없는 것이 이 화면의 요점이다. 첫 판에는 owner/address-pin의 사슬을
  // 그대로 베껴 `getOneShotPosition()`이 중간에 있었다 — 권한이 이미 있으면 프롬프트 없이
  // 조용히 읽는 호출이다. 그건 이 슬라이스가 존재할 수 있었던 이유 자체와 정면으로 부딪힌다:
  // 0123이 빌드 가능한 건 **기기를 읽지 않기 때문**이고(ruling B), 마이그레이션 헤더도
  // requests.tsx:97-99도 privacy-policy.md:88도 전부 「러닝 중이 아닐 때는 위치를 수집하지
  // 않습니다」라고 적혀 있다. 정책 문장은 Sean의 것이라 고칠 수 없으니 **코드가 문장 쪽으로
  // 움직인다**. 러너는 지도를 움직여 자기 동네를 찍는다 — 그게 ruling B의 「TYPES a place」다.
  // ⚠ owner/address-pin은 그대로 둔다 (기존 동작, 이 슬라이스 범위 밖).
  useEffect(() => {
    let alive = true;
    (async () => {
      let best: { lat: number; lng: number } | null = null;
      let zoom = 13;                 // 격자 단위가 ~1.1km라 동네가 다 보이는 줌이 맞다
      try {
        const base = await fetchMyRunnerBase();
        if (!alive) return;
        if (base == null) {
          setNotRunner(true);
        } else {
          setLockedUntil(base.canChangeAt);
          if (base.lat != null && base.lng != null) {
            setSaved({ lat: base.lat, lng: base.lng });
            best = { lat: base.lat, lng: base.lng };
            zoom = 14;
          }
        }
      } catch (e) {
        // 실패를 실패로 — 「미설정」으로 그리면 러너가 이미 저장한 위치를 잃은 것처럼 보인다
        console.warn('[runner-base] read:', (e as Error)?.message ?? e);
        if (alive) setReadErr(true);
      }
      if (!alive) return;
      setResolving(false);
      // 저장된 기준점이 있을 때만 카메라가 움직인다. 없으면 지도는 마운트한 자리(BANPO)에
      // 그대로 선다 — 「우리가 아는 위치」인 척하는 애니메이션은 하지 않는다.
      if (best && !pannedRef.current && !recenteredRef.current) {
        recenteredRef.current = true;
        centerRef.current = best;
        mapRef.current?.animateCameraTo({ latitude: best.lat, longitude: best.lng, zoom, duration: 600 });
      }
    })();
    return () => { alive = false; };
  }, []);

  // 잠겼는가. 클라의 계산은 이 비교 하나뿐이다 — 쿨다운의 길이는 서버만 안다.
  const locked = lockedUntil != null && new Date(lockedUntil).getTime() > Date.now();

  const onCameraChanged = (p: { latitude: number; longitude: number; reason: string }) => {
    centerRef.current = { lat: p.latitude, lng: p.longitude };
    if (p.reason === 'Gesture') pannedRef.current = true;
  };
  const onCameraIdle = (p: { latitude: number; longitude: number }) => {
    centerRef.current = { lat: p.latitude, lng: p.longitude };
  };

  const confirm = async () => {
    if (busy || clearing) return;
    const c = centerRef.current;
    if (!inBounds(c.lat, c.lng)) { setErr('bounds'); return; }
    setErr(null);
    setBusy(true);
    try {
      await setRunnerBase(c.lat, c.lng);
      haptic('success');
      router.back();
    } catch (e) {
      console.warn('[runner-base] save:', (e as Error)?.message ?? e);
      if (isBaseCooldownError(e)) {
        // 쿨다운은 **재시도로 낫지 않는 실패**다. 그래서 재시도 스트립이 아니라 잠금 상태로
        // 넘어가고, 잠금이 언제 풀리는지는 다시 묻는다 — 우리가 추측하지 않는다.
        setErr('cooldown');
        try {
          const fresh = await fetchMyRunnerBase();
          if (fresh) setLockedUntil(fresh.canChangeAt);
        } catch { /* 잠금 시각을 모르면 날짜 없이 「지금은 바꿀 수 없어요」만 남는다 */ }
      } else {
        setErr('save');   // 화면에 남는다 — 스트립이 재시도 경로다
      }
    } finally {
      setBusy(false);
    }
  };

  const clear = async () => {
    if (busy || clearing) return;
    setErr(null);
    setClearing(true);
    try {
      await setRunnerBase(null, null);
      haptic('success');
      router.back();
    } catch (e) {
      console.warn('[runner-base] clear:', (e as Error)?.message ?? e);
      setErr('clear');
    } finally {
      setClearing(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <Row style={s.header}>
        <Pressable onPress={goBackOrHome} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
      </Row>
      <Text style={[s.title, df]}>어디에서 출발하세요?</Text>

      <View style={s.banner}>
        <Text style={s.bannerLead}>요청 카드에 출발지까지의 대략 거리가 표시돼요</Text>
        <Text style={s.bannerHint}>{HINT_ROUND}</Text>
        {resolving ? (
          <Text style={s.bannerHint}>저장된 위치 확인 중…</Text>
        ) : readErr ? (
          /* 읽기 실패는 실패로 말한다 — 「미설정」과 섞이면 러너가 이미 정한 값을 잃은 줄 안다 */
          <Text style={s.bannerFail}>저장된 위치를 불러오지 못했어요 — 지금 지정하면 덮어써요</Text>
        ) : notRunner ? (
          <Text style={s.bannerFail}>러너로 등록된 계정에서만 지정할 수 있어요</Text>
        ) : saved ? (
          <Text style={s.bannerHint}>이미 지정돼 있어요 — 지도가 선 곳은 반올림된 위치예요</Text>
        ) : (
          <Text style={s.bannerHint}>아직 지정하지 않았어요</Text>
        )}
      </View>

      <View style={{ flex: 1 }}>
        {maps ? (
          <>
            <maps.NaverMapView
              ref={mapRef}
              style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
              initialCamera={{ latitude: BANPO.lat, longitude: BANPO.lng, zoom: 13 }}
              onCameraChanged={onCameraChanged}
              onCameraIdle={onCameraIdle}
              isShowLocationButton={false}
              isShowCompass={false}
              isShowScaleBar={false}
              isShowZoomControls={false}
            />
            <View pointerEvents="none" style={s.pinWrap}>
              <View style={s.pinGlyph}>
                <View style={s.pinHead} />
                <View style={s.pinBar} />
              </View>
            </View>
          </>
        ) : (
          /* SDK 없음 — 하우스 플레이스홀더. 확정 버튼도 숨는다 (죽은 버튼 금지법) */
          <View style={s.mapFallbackWrap}>
            <View style={s.mapFallback}>
              <Text style={s.mapFallbackTxt}>지도를 불러올 수 없어요</Text>
            </View>
          </View>
        )}
      </View>

      {err === 'bounds' && (
        <View style={s.failStrip}><Text style={s.failTxt}>서비스 지역을 벗어났어요</Text></View>
      )}
      {/* 쿨다운 — 누를 수 없는 줄이다. 「다시 시도」가 없는 이유가 이 화면의 유일한 예외이고,
          이유는 하나뿐이다: 이 실패는 다시 눌러도 **절대** 성공하지 않는다.
          `!locked`인 이유: 거절 직후 잠금 시각을 다시 읽는 데 성공하면 아래 확정 바가 날짜까지
          말하는 잠금 판으로 바뀐다 — 그때 이 줄까지 뜨면 같은 말을 두 번 하는 화면이 된다.
          이 줄이 혼자 서는 경우는 거절은 받았는데 **언제 열리는지 못 읽은** 때 하나뿐이고,
          그때는 날짜를 지어내지 않고 날짜 없이 말한다. */}
      {err === 'cooldown' && !locked && (
        <View style={s.failStrip}>
          <Text style={s.failTxt}>지금은 바꿀 수 없어요</Text>
        </View>
      )}
      {err === 'save' && (
        <Pressable onPress={confirm} style={s.failStrip} accessibilityRole="button" accessibilityLabel="다시 시도">
          <Text style={s.failTxt}>저장하지 못했어요 · 다시 시도</Text>
        </Pressable>
      )}
      {err === 'clear' && (
        <Pressable onPress={clear} style={s.failStrip} accessibilityRole="button" accessibilityLabel="다시 시도">
          <Text style={s.failTxt}>삭제하지 못했어요 · 다시 시도</Text>
        </Pressable>
      )}

      {/* 삭제 문 — 저장된 값이 **실제로 있을 때만** 그린다. 없는 상태에서 그리면 죽은 버튼이다. */}
      {saved && (
        <Pressable
          onPress={clear}
          style={s.clearStrip}
          accessibilityRole="button"
          accessibilityLabel="기준 위치 삭제"
        >
          <Text style={s.clearTxt}>
            {clearing ? '삭제 중...' : '기준 위치 삭제 › '}
            {/* 잠겨 있을 때 삭제는 함정이 될 수 있다: 지우는 건 언제나 되지만 다시 지정하는 건
                잠금이 풀린 뒤다 (서버가 해제로 시계를 되돌리지 않는다 — 그게 우회를 막는 이유).
                그래서 잠긴 동안에는 그 사실을 여기서 먼저 말한다. */}
            {clearing ? '' : (
              <Text style={s.clearHint}>
                {locked ? '거리 표시가 사라지고, 다시 지정은 잠금이 풀린 뒤예요' : '거리 표시가 사라져요'}
              </Text>
            )}
          </Text>
        </Pressable>
      )}

      {/* 확정 바 — 세 조건. 지도가 있고(SDK 폴백에선 :184의 관용구대로 숨는다), 러너 계정이고
          (아니면 서버가 not_a_runner로 거절할 것이 확정이다 — 배너가 이미 그렇게 말했다),
          잠겨 있지 않다. 셋 다 죽은 버튼 금지법의 같은 문장이다: 보이는 행위에는 모든 상태에서
          진짜 경로가 있다. 잠긴 자리에는 버튼 대신 **언제 열리는지**가 선다 (빈칸이 아니다). */}
      {maps && !notRunner && (
        <View style={[s.confirmBar, { paddingBottom: Math.max(insets.bottom, 12) + 12 }]}>
          {locked ? (
            <View style={s.lockBar}>
              <Text style={s.lockLead}>지금은 기준 위치를 바꿀 수 없어요</Text>
              <Text style={s.lockHint}>{lockLine(lockedUntil as string)}</Text>
            </View>
          ) : (
            <PaperBtn label="이 위치로 지정" busyLabel="저장 중..." busy={busy} onPress={confirm} />
          )}
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
  bannerLead: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.ink },
  bannerHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 4 },
  bannerFail: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical, marginTop: 4 },

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

  failStrip: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.criticalWash, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: 12,
  },
  failTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical },

  // 삭제 스트립 — address-pin의 메모 스트립과 같은 문법(≥44pt, 뉴트럴 구분선)
  clearStrip: {
    borderTopWidth: 1, borderTopColor: '#EEEEEE', backgroundColor: paper.canvas,
    paddingHorizontal: PAD, minHeight: 48, justifyContent: 'center',
  },
  clearTxt: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.actionInk },
  clearHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim },

  confirmBar: { paddingHorizontal: PAD, paddingTop: 10, backgroundColor: paper.canvas },

  // 잠금 판 — 버튼 자리를 비우지 않고 **사실**로 채운다. 누를 수 없으므로 Pressable이 아니고
  // accessibilityRole도 button이 아니다 (스크린리더에게도 죽은 버튼을 만들지 않는다).
  lockBar: {
    minHeight: 52, justifyContent: 'center', paddingHorizontal: 14, paddingVertical: 10,
    borderWidth: 1, borderColor: paper.line, backgroundColor: paper.canvas,
  },
  lockLead: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink },
  lockHint: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 2 },
});
