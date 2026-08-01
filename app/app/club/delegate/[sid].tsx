import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View, useWindowDimensions } from 'react-native';
import { ClubMast, ClubTag, DawnCanvas, SealSlide, clubText } from '../../../src/components/club-ui';
import { DelegationConsent, DogProfile, delegateDog, fetchMyDogs } from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { haptic } from '../../../src/lib/haptics';
import { lilac } from '../../../src/theme';

// O2 — 위탁 승낙서 (정본: master-lab O2 · ② 코랄 봉인 확정)
// 종이는 종이 문법을 지킨다: 웜 화이트 · 잉크 괘선 · 각(radius 2) — 앱에서 유일하게 각을 유지하는 표면.
// 동의 = 동작: 봉인을 끝까지 끌어야 전송 (버튼 없음 — 실수 탭 구조적 불가). 접근성 대체 = 길게 누르기.
// 서버는 불변 문서 v1로 박제 (본인도 수정 불가 — 재동의만 새 행). 규칙 7: 조항 1문단, 26어.

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

  useEffect(() => { fetchMyDogs().then(setDogs).catch(() => {}); }, []);
  const dog = dogs[dogIdx] ?? null;
  const ready = !!dog && emergency.trim().length >= 9;

  const consent = useMemo((): DelegationConsent => ({
    custodyAck: true,
    emergencyContact: emergency.trim(),
    pickupName: pickup.trim() || null,
    vetLimitKrw: Number(vetLimit.replace(/[^0-9]/g, '')) || VET_DEFAULT,
    photoConsent: photoOk,
  }), [emergency, pickup, vetLimit, photoOk]);

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
        : m.includes('no_capacity') ? '위탁 자리가 다 찼어요'
        : m.includes('already') ? '이미 신청한 세션이에요'
        : m.includes('consent_required') ? '동의 항목이 비어 있어요 — 비상 연락처를 확인해주세요'
        : m);
    } finally { setBusy(false); }
  };

  return (
    <DawnCanvas>
      <ScrollView contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 44 }} keyboardShouldPersistTaps="handled">
        <ClubMast title={`${dog?.name ?? '우리 아이'} 위탁 신청`} sub={(clubName || 'HIGH CLUB') + (when ? ` · ${when}` : '')} onBack={() => router.back()} />

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
              {dogs.length === 0 && <Text style={{ fontSize: 11.5, color: '#8a8272' }}>등록된 강아지가 없어요 — 프로필에서 먼저 등록해주세요</Text>}
              {dogs.map((d, i) => (
                <Pressable key={d.id} onPress={() => setDogIdx(i)}
                  style={[s.dogChip, i === dogIdx && { backgroundColor: INK, borderColor: INK }]}>
                  <Text style={{ fontSize: 12, fontWeight: '700', color: i === dogIdx ? '#fff' : INK }}>
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
              <Text style={{ fontSize: 12, fontWeight: '700', color: INK }}>₩</Text>
              <TextInput
                value={vetLimit} onChangeText={setVetLimit} keyboardType="number-pad"
                style={[s.pdInput, { flex: 0, minWidth: 84 }]}
              />
              <Text style={{ fontSize: 10.5, color: '#8a8272' }}>까지 사전 승인</Text>
            </View>
          </View>
          <Pressable onPress={() => setPhotoOk((v) => !v)} style={s.pdRow}>
            <Text style={s.pdKey}>사진 동의</Text>
            <View style={[s.checkBox, photoOk && { backgroundColor: INK, borderColor: INK }]}>
              {photoOk && <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>✓</Text>}
            </View>
            <Text style={{ fontSize: 10.5, color: '#8a8272', flex: 1 }}>러닝 사진이 내 책과 클럽에 실릴 수 있어요</Text>
          </Pressable>

          {/* 조항 — 규칙 7: 한 문단 */}
          <View style={s.clause}>
            <Text style={{ fontSize: 10.5, lineHeight: 17, color: '#4a463c' }}>
              인계부터 <Text style={{ fontWeight: '800', color: INK }}>양측 반환 확인까지</Text> 담당 러너가 {dog?.name ?? '아이'}의 보호 책임자예요.
              긴급 시 위 한도 안에서 바로 진료할 수 있어요.
            </Text>
          </View>

          {/* ② 봉인 스트립 — 코랄 소프트 필 */}
          <SealSlide width={width - 24 - 26 - 8} onSeal={submit} disabled={!ready || busy} />
          {!ready && (
            <Text style={{ fontSize: 10, color: '#a4917f', textAlign: 'center', marginTop: 7 }}>
              {dogs.length === 0 ? '위탁견이 있어야 봉인할 수 있어요' : '비상 연락처를 채우면 봉인이 열려요'}
            </Text>
          )}
        </View>

        <View style={{ alignItems: 'center', marginTop: 11, gap: 5 }}>
          <ClubTag label="수정하려면 재동의 — 새 판이 쌓여요" tone="dim" />
          <Text style={clubText.dim}>승인 후 20분 결제 홀드 · 시작 24시간 전까지 무료 취소</Text>
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
  pdKey: { width: 76, fontSize: 8.5, letterSpacing: 1, color: '#8a8272', fontWeight: '700' },
  pdInput: {
    flex: 1, fontSize: 12.5, fontWeight: '700', color: INK, padding: 0,
    borderBottomWidth: 1.5, borderStyle: 'dashed', borderBottomColor: '#C9C2AE', paddingBottom: 2,
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
});
