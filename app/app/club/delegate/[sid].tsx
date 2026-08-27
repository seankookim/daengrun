import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useWindowDimensions } from 'react-native';
import { routeNameOnly } from '../../../src/lib/route-label';
import { ClubMast, ClubTag, DawnCanvas, SealSlide, clubText } from '../../../src/components/club-ui';
import {
  DelegationBoard, DelegationConsent, DogProfile, delegateDog, fetchDelegationBoard, fetchMyDogs,
} from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { haptic } from '../../../src/lib/haptics';
import { goBackOrHome } from '../../../src/lib/nav';
import { lilac } from '../../../src/theme';

// O2 — 위탁 승낙서 (정본: master-lab O2 · ② 코랄 봉인 확정)
// 종이는 종이 문법을 지킨다: 웜 화이트 · 잉크 괘선 · 각(radius 2) — 앱에서 유일하게 각을 유지하는 표면.
// 동의 = 동작: 봉인을 끝까지 끌어야 전송 (버튼 없음 — 실수 탭 구조적 불가). 접근성 대체 = 길게 누르기.
// 서버는 불변 문서 v1로 박제 (본인도 수정 불가 — 재동의만 새 행). 규칙 7: 조항 1문단, 26어.
//
// [클럽 가격 비가시성 · Sean 재정 ④ 2026-08-13] 이 종이가 클럽 요금이 등장하는 **단 한 곳**이다.
// 마켓플레이스 교리(§0-bis PRICE-INVISIBILITY)는 "요청 화면에서 한 번, 그 뒤로는 영원히 없음"이고,
// request.tsx는 그 한 번을 마지막 스텝의 CTA 옆에 둔다. 클럽에서 그 자리는 여기다 — 보호자가
// 처음으로 무언가를 거는 화면이자(승낙서 봉인 = 신청), 청구로 가는 모든 경로의 상류다.
// 여기서 알리면 요금을 못 본 채 청구되는 보호자가 구조적으로 존재할 수 없다.
// 세션 셸(HOLDING 큰 숫자·CTA·'승인 시 가격'·'결제 N원'·결제 시트)의 다섯 표시는 그래서 사라졌다.
// 재정 ④의 '정직한 A': 클럽 기본요금이 1:1보다 높다는 사실도 이 한 번에 같이 말한다.

const L = lilac;
const INK = '#26231b';
const VET_DEFAULT = 200000; // club_config vet_limit_krw 기본값 — 서버가 최종 판정

export default function DelegateConsentScreen() {
  const df = useDisplayFont();
  const { sid, clubName, when } = useLocalSearchParams<{ sid: string; clubName?: string; when?: string }>();
  const { width } = useWindowDimensions();
  const [dogs, setDogs] = useState<DogProfile[]>([]);
  const [dogIdx, setDogIdx] = useState(0);
  const [emergency, setEmergency] = useState('');
  const [pickup, setPickup] = useState('');
  const [vetLimit, setVetLimit] = useState(String(VET_DEFAULT));
  const [photoOk, setPhotoOk] = useState(true);
  const [busy, setBusy] = useState(false);

  // [honesty P1 2026-08-11] A failed dogs fetch used to render "등록된 강아지가
  // 없어요 — 프로필에서 먼저 등록해주세요" on this legal consent document — a
  // network error stated as fact, with a false instruction. Three states now:
  // loading / error+retry / loaded (and loaded-empty keeps the honest-empty copy).
  const [dogsLoaded, setDogsLoaded] = useState(false);
  const [dogsErr, setDogsErr] = useState(false);
  const loadDogs = useCallback(() => {
    setDogsErr(false);
    fetchMyDogs().then((d) => { setDogs(d); setDogsLoaded(true); }).catch(() => setDogsErr(true));
  }, []);
  useEffect(() => { loadDogs(); }, [loadDogs]);
  const dog = dogsLoaded ? dogs[dogIdx] ?? null : null;

  // 요금은 서버 정본(club_delegation_board.session.fare = club_fare(km), 0043:14)에서만 온다 —
  // 클라이언트가 9,900 + 3,000×km를 다시 계산하면 두 개의 가격이 생긴다. 보드는 미참가자에게도
  // session 블록을 준다 (0052 rev2: 집결지·시각·요금은 클럽 공개 정보 수준).
  const [board, setBoard] = useState<DelegationBoard | null>(null);
  const [boardState, setBoardState] = useState<'loading' | 'ready' | 'error'>('loading');
  const loadBoard = useCallback(() => {
    setBoardState((s2) => (s2 === 'ready' ? s2 : 'loading'));
    fetchDelegationBoard(sid)
      .then((b) => { if (b) { setBoard(b); setBoardState('ready'); } else { setBoardState('error'); } })
      .catch((e) => { console.warn('[delegate] board:', (e as Error)?.message ?? e); setBoardState('error'); });
  }, [sid]);
  useEffect(() => { loadBoard(); }, [loadBoard]);
  const fare = board?.session.fare ?? null;

  // 요금을 못 보여준 상태의 봉인 = 값을 모르고 거는 서명이다. 그래서 요금은 봉인의 조건이다
  // (강아지 목록 실패가 이미 같은 규칙으로 봉인을 막는다 — 같은 문법을 요금에도 적용).
  const ready = !!dog && emergency.trim().length >= 9 && fare != null;

  const consent = useMemo((): DelegationConsent => {
    // [감사 P1] '0'이 falsy라 조용히 20만으로 박제되던 것 — 명시적 입력은 그대로, 빈 값만 서버 기본값
    const v = vetLimit.replace(/[^0-9]/g, '');
    return {
      custodyAck: true,
      emergencyContact: emergency.trim(),
      pickupName: pickup.trim() || null,
      vetLimitKrw: v === '' ? null : Number(v),
      photoConsent: photoOk,
    };
  }, [emergency, pickup, vetLimit, photoOk]);

  const submit = async () => {
    if (!dog || busy) return;
    setBusy(true);
    try {
      await delegateDog(sid, dog.id, consent);
      haptic('success');
      Alert.alert('신청이 전송됐어요', `호스트가 확인하면 알려드릴게요 — ${dog.name}의 자리가 심사에 들어갔어요`, [
        { text: '확인', onPress: () => router.back() },
      ]);
    } catch (e) {
      const m = (e as Error).message;
      Alert.alert('신청 실패',
        m.includes('format_closed') ? '이 세션은 위탁을 받지 않아요 — 보호자 동반 전용이에요'
        : m.includes('route_required') ? '이 세션엔 아직 코스가 없어요 — 호스트가 코스를 정하면 위탁 요금이 정해져요'
        : m.includes('session_closed') ? '이미 시작됐거나 닫힌 세션이에요'
        : m.includes('dog_capacity_full') ? '이 세션의 강아지 정원이 다 찼어요'
        : m.includes('no_capacity') ? '위탁 자리가 다 찼어요'
        : m.includes('already') ? '이미 신청한 세션이에요'
        : m.includes('rejected') ? '이 세션에서 거절된 신청이 있어요 — 호스트에게 문의해주세요'
        : m.includes('consent_required') ? '동의 항목이 비어 있어요 — 비상 연락처를 확인해주세요'
        : m);
    } finally { setBusy(false); }
  };

  return (
    <DawnCanvas>
      <ScrollView contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 44 }} keyboardShouldPersistTaps="handled">
        <ClubMast title={`${dog?.name ?? '우리 아이'} 위탁 신청`} sub={(clubName || 'HIGH CLUB') + (when ? ` · ${when}` : '')} onBack={goBackOrHome} />

        {/* ---------- 종이 서식 ---------- */}
        <View style={s.paper}>
          <View pointerEvents="none" style={s.paperInner} />
          <View style={s.pdHead}>
            <Text style={[{ fontSize: 16, color: INK }, df]}>위탁 승낙서</Text>
            <Text style={s.pdHeadMono}>CONSENT · v1 — 不變</Text>
          </View>

          {/* 위탁견 선택 */}
          <View style={s.pdRow}>
            <Text style={s.pdKey}>위탁견</Text>
            <View style={{ flex: 1, flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
              {!dogsLoaded && !dogsErr && <Text style={{ fontSize: 15, color: '#8a8272' }}>강아지 목록 불러오는 중...</Text>}
              {dogsErr && (
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 15, fontWeight: '700', color: L.tang }}>강아지 목록을 불러오지 못했어요</Text>
                  <Pressable onPress={loadDogs} style={s.dogsRetry} accessibilityRole="button">
                    <Text style={{ fontSize: 16, fontWeight: '800', color: INK }}>다시 시도</Text>
                  </Pressable>
                </View>
              )}
              {dogsLoaded && dogs.length === 0 && <Text style={{ fontSize: 15, color: '#8a8272' }}>등록된 강아지가 없어요 — 프로필에서 먼저 등록해주세요</Text>}
              {dogsLoaded && dogs.map((d, i) => (
                <Pressable key={d.id} onPress={() => setDogIdx(i)}
                  style={[s.dogChip, i === dogIdx && { backgroundColor: INK, borderColor: INK }]}>
                  <Text style={{ fontSize: 15, fontWeight: '700', color: i === dogIdx ? '#fff' : INK }}>
                    {d.name}{d.weightKg ? ` · ${d.weightKg}kg` : ''}
                  </Text>
                </Pressable>
              ))}
            </View>
          </View>

          <View style={s.pdRow}>
            <Text style={s.pdKey}>비상 연락처 *</Text>
            <TextInput
              value={emergency} onChangeText={setEmergency} keyboardType="phone-pad"
              placeholder="010-0000-0000" placeholderTextColor="#c9c2b2" style={s.pdInput}
            />
          </View>
          <View style={s.pdRow}>
            <Text style={s.pdKey}>픽업 지정인</Text>
            <TextInput
              value={pickup} onChangeText={setPickup}
              placeholder="본인 (미지정 시)" placeholderTextColor="#c9c2b2" style={s.pdInput}
            />
          </View>
          <View style={s.pdRow}>
            <Text style={s.pdKey}>진료 한도</Text>
            <View style={{ flex: 1, flexDirection: 'row', alignItems: 'baseline', gap: 4 }}>
              <Text style={{ fontSize: 15, fontWeight: '700', color: INK }}>₩</Text>
              <TextInput
                value={vetLimit} onChangeText={setVetLimit} keyboardType="number-pad"
                style={[s.pdInput, { flex: 0, minWidth: 84 }]}
              />
              <Text style={{ fontSize: 15, color: '#8a8272' }}>까지 사전 승인</Text>
            </View>
          </View>
          <Pressable onPress={() => setPhotoOk((v) => !v)} style={s.pdRow}>
            <Text style={s.pdKey}>사진 동의</Text>
            <View style={[s.checkBox, photoOk && { backgroundColor: INK, borderColor: INK }]}>
              {photoOk && <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>✓</Text>}
            </View>
            <Text style={{ fontSize: 15, color: '#8a8272', flex: 1 }}>러닝 사진이 내 책과 클럽에 실릴 수 있어요</Text>
          </Pressable>

          {/* 조항 — 규칙 7: 한 문단 */}
          <View style={s.clause}>
            <Text style={{ fontSize: 15, lineHeight: 18, color: '#4a463c' }}>
              인계부터 <Text style={{ fontWeight: '800', color: INK }}>양측 반환 확인까지</Text> 담당 러너가 {dog?.name ?? '아이'}의 보호 책임자예요.
              긴급 시 위 한도 안에서 바로 진료할 수 있어요.
            </Text>
          </View>

          {/* ---------- 요금 고지 — 앱 전체에서 클럽 요금이 나오는 단 한 곳 (재정 ④) ---------- */}
          <View style={s.fee}>
            <View style={s.feeRow}>
              <Text style={s.pdKey}>위탁 요금</Text>
              {boardState === 'loading' && <Text style={{ fontSize: 15, color: '#8a8272' }}>불러오는 중...</Text>}
              {boardState === 'error' && (
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 15, fontWeight: '700', color: L.tang }}>위탁 요금을 불러오지 못했어요</Text>
                  <Pressable onPress={loadBoard} style={s.dogsRetry} accessibilityRole="button">
                    <Text style={{ fontSize: 16, fontWeight: '800', color: INK }}>다시 시도</Text>
                  </Pressable>
                </View>
              )}
              {/* 코스가 없으면 서버가 route_required로 거절한다 (club_fare는 코스 km에서 나온다) —
                  문 앞에서 그 사실을 그대로 말한다. 없는 숫자를 지어내지 않는다. */}
              {boardState === 'ready' && fare == null && (
                <Text style={{ flex: 1, fontSize: 15, lineHeight: 18, color: '#8a8272' }}>
                  이 세션엔 아직 코스가 없어요 — 코스가 정해지면 요금이 정해져요
                </Text>
              )}
              {boardState === 'ready' && fare != null && (
                <View style={{ flex: 1, alignItems: 'flex-end' }}>
                  <Text style={{ fontSize: 19, lineHeight: 24, fontWeight: '800', color: INK }}>
                    {fare.toLocaleString()}원
                  </Text>
                  {board?.session.routeKm != null && (
                    <Text style={{ fontSize: 15, lineHeight: 18, color: '#8a8272', marginTop: 1 }}>
                      {board.session.routeKm}km{board.session.routeName ? ` · ${routeNameOnly(board.session.routeName)}` : ' 코스'}
                    </Text>
                  )}
                </View>
              )}
            </View>
            {boardState === 'ready' && fare != null && (
              <Text style={s.feeNote}>
                클럽 위탁은 1:1 러닝과 기본요금이 달라요 — 호스트가 자리를 운영하고 집결지가 있어요.
                {'\n'}요금 안내는 여기 한 번이에요 — 청구가 생기면 설정 › 결제 관리에 남아요.
              </Text>
            )}
          </View>

          {/* ② 봉인 스트립 — 코랄 소프트 필 */}
          <SealSlide width={width - 24 - 26 - 8} onSeal={submit} disabled={!ready || busy} />
          {!ready && (
            <Text style={{ fontSize: 15, color: '#a4917f', textAlign: 'center', marginTop: 7 }}>
              {!dogsLoaded
                ? dogsErr ? '강아지 목록을 불러와야 봉인할 수 있어요' : '강아지 목록을 확인하는 중이에요'
                : dogs.length === 0 ? '위탁견이 있어야 봉인할 수 있어요'
                : fare == null
                  ? boardState === 'error' ? '위탁 요금을 불러와야 봉인할 수 있어요'
                    : boardState === 'loading' ? '위탁 요금을 확인하는 중이에요'
                    : '코스가 정해져야 봉인할 수 있어요'
                  : '비상 연락처를 채우면 봉인이 열려요'}
            </Text>
          )}
        </View>

        <View style={{ alignItems: 'center', marginTop: 11, gap: 5 }}>
          <ClubTag label="수정하려면 재동의 — 새 판이 쌓여요" tone="dim" />
          {/* 홀드는 '결제 홀드'가 아니라 '자리 홀드'다 — 확정 시점에 돈은 움직이지 않는다 (§0-bis 사후청구) */}
          <Text style={clubText.dim}>승인 후 20분 안에 자리 확정 · 시작 24시간 전까지 무료 취소</Text>
        </View>
      </ScrollView>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  // 종이 = 앱에서 유일한 각진 표면 (radius 2) — 문서는 문서답게
  paper: {
    backgroundColor: '#fff', borderRadius: 2, padding: 13, marginTop: 12,
    shadowColor: '#1C1837', shadowOpacity: 0.14, shadowRadius: 18, shadowOffset: { width: 0, height: 8 }, elevation: 4,
    borderWidth: 1, borderColor: '#E2DDD0',
  },
  paperInner: { position: 'absolute', left: 4, right: 4, top: 4, bottom: 4, borderWidth: 1, borderColor: '#d9d3c2', borderRadius: 1 },
  pdHead: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline',
    borderBottomWidth: 2.5, borderBottomColor: INK, paddingBottom: 6,
  },
  pdHeadMono: { fontSize: 7.5, letterSpacing: 1.5, color: '#8a8272', fontWeight: '700' },
  pdRow: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    borderBottomWidth: 1, borderBottomColor: '#E4DFD1', paddingVertical: 8,
  },
  // [FLOOR14 sweep 2026-08-11 · FLOOR15 2026-08-27] These are the field labels of a legal consent document
  // (위탁견 · 비상 연락처 · 픽업 지정인 · 진료 한도 · 사진 동의) and they shipped at 8.5pt with
  // tracking 1 — the smallest Korean in the app, on the surface where comprehension matters most.
  // Korean never rides the letterspaced-caps kicker exemption (§3). Width 76 → 96 so the longest
  // label ('비상 연락처 *' ≈ 94px at 14pt) holds one line; the paper's inner width is 352 on a
  // 402pt screen, so the dashed input keeps ~248 — measured, not eyeballed.
  pdKey: { width: 96, fontSize: 15, lineHeight: 18, letterSpacing: 0.2, color: '#8a8272', fontWeight: '700' },
  pdInput: {
    flex: 1, fontSize: 15, fontWeight: '700', color: INK, padding: 0,
    borderBottomWidth: 1.5, borderStyle: 'dashed', borderBottomColor: '#C9C2AE', paddingBottom: 2,
  },
  // retry chip inside the paper document — document grammar (ink border, sanctioned radius 4)
  dogsRetry: {
    alignSelf: 'flex-start', marginTop: 7, minHeight: 36, justifyContent: 'center', paddingHorizontal: 12,
    borderWidth: 1.3, borderColor: INK, borderRadius: 4, backgroundColor: '#FBF9F3',
  },
  dogChip: {
    borderWidth: 1.3, borderColor: '#C9C2AE', borderRadius: 4,
    paddingVertical: 5, paddingHorizontal: 9, backgroundColor: '#FBF9F3',
  },
  checkBox: {
    width: 20, height: 20, borderRadius: 4, borderWidth: 1.5, borderColor: '#C9C2AE',
    alignItems: 'center', justifyContent: 'center',
  },
  clause: {
    backgroundColor: '#F6F3EA', borderLeftWidth: 2.5, borderLeftColor: INK,
    borderRadius: 4, padding: 9, marginTop: 10,
  },
  // 요금 고지 — 조항과 봉인 사이, 종이 문법 그대로 (잉크 괘선 위 한 칸). 봉인 직전에 두는 이유는
  // request.tsx가 총액을 CTA 옆에 두는 것과 같다: 거는 손과 숫자가 같은 시야에 있어야 한다.
  fee: { borderTopWidth: 1.5, borderTopColor: INK, marginTop: 12, paddingTop: 9 },
  feeRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 8 },
  feeNote: { fontSize: 15, lineHeight: 18, color: '#8a8272', marginTop: 7 },
});
