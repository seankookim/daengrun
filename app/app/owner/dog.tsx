import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { addDog, DangerousBasis, DangerousStatus, DogProfile, fetchMyDogs, updateMyDog, uploadDogPhoto } from '../../src/lib/api';
import { goBackOrHome } from '../../src/lib/nav';
import { clampSuggest } from '../../src/lib/pace';
import { CollarKey, collarColors, collarLabels, layout, paper } from '../../src/theme';

// 반려견 프로필 — 실초코. 사진·정보·성향 메모·선호 태그가 러너에게 전달된다.
// 진입: 예약 화면 강아지 카드 · 마이 메뉴. 저장은 섹션 하단 버튼 1개.

// 선호/성향 태그 카탈로그 — dogs.preferences.tags 로 저장, 러너 요청 카드에 표시
const PREF_CATALOG = [
  '흙길 선호', '이른 아침', '저녁 선호', '자전거 주의', '사람 좋아함',
  '강아지 좋아함', '소심해요', '간식 러버', '물 자주 필요', '천천히 워밍업',
];
const VACCINE_CATALOG = ['종합백신', '광견병', '코로나 장염', '켄넬코프'];

// 권장 최소 페이스 (pace-state-ui-plan §4 / D13) — the adjustable band, 7'00"~9'00", as five
// chips: one tap, the whole band visible, and no inverted-scale trap (a stepper's "+" would
// mean SLOWER). Stored in dogs.preferences.paceSuggestSec, snapshotted into the run at start.
const PACE_OPTIONS = [
  { sec: 420, label: `7'00"`, a11y: '킬로미터당 7분 00초' },
  { sec: 450, label: `7'30"`, a11y: '킬로미터당 7분 30초' },
  { sec: 480, label: `8'00"`, a11y: '킬로미터당 8분 00초' },
  { sec: 510, label: `8'30"`, a11y: '킬로미터당 8분 30초' },
  { sec: 540, label: `9'00"`, a11y: '킬로미터당 9분 00초' },
] as const;

// A radiogroup with nothing selected reads as broken. The five chips are the only writer,
// so this only ever fires on a hand-edited jsonb — snap it onto the band instead of showing
// an empty group. (clampSuggest also coalesces an absent key to the 480 default.)
const nearestPaceOption = (sec: number | null): number => {
  const v = clampSuggest(sec);
  return PACE_OPTIONS.reduce<number>(
    (best, o) => (Math.abs(o.sec - v) < Math.abs(best - v) ? o.sec : best),
    PACE_OPTIONS[0].sec,
  );
};

export default function DogProfileScreen() {
  const { dogId } = useLocalSearchParams<{ dogId?: string }>();
  const [dogs, setDogs] = useState<DogProfile[]>([]);
  const [dog, setDog] = useState<DogProfile | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const [name, setName] = useState('');
  const [breed, setBreed] = useState('');
  const [birth, setBirth] = useState('');
  const [weight, setWeight] = useState('');
  const [neutered, setNeutered] = useState<boolean | null>(null);
  const [memo, setMemo] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [vaccines, setVaccines] = useState<string[]>([]);
  const [collar, setCollar] = useState<CollarKey | null>(null); // 칼라 컬러 (0033)
  const [paceSuggest, setPaceSuggest] = useState<number>(nearestPaceOption(null)); // 권장 최소 페이스 sec/km
  // [0119] 맹견 신고. `undeclared` 는 결함이 아니라 '아직 묻지 않았다'는 정상 상태다.
  const [danger, setDanger] = useState<DangerousStatus>('undeclared');
  const [basis, setBasis] = useState<DangerousBasis | null>(null);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const selectDog = (d: DogProfile) => {
    setDog(d);
    setName(d.name);
    setBreed(d.breed ?? '');
    setBirth(d.birthDate ?? '');
    setWeight(d.weightKg != null ? String(d.weightKg) : '');
    setNeutered(d.neutered);
    setDanger(d.dangerousStatus);
    setBasis(d.dangerousBasis);
    setMemo(d.memo ?? '');
    setTags(d.prefTags);
    setVaccines(d.vaccines);
    setCollar((d.collar as CollarKey) ?? null);
    setPaceSuggest(nearestPaceOption(d.paceSuggestSec));
  };

  // [honesty 2026-08-11] a failed fetch used to setLoaded(true) and render the
  // "아직 반려견이 없어요" empty state — a network error stated as fact. Error renders now.
  const load = (preferId?: string) => {
    setLoadErr(false);
    return fetchMyDogs()
      .then((list) => {
        setDogs(list);
        const target = list.find((x) => x.id === (preferId ?? dogId)) ?? list[0];
        if (target) selectDog(target);
        setLoaded(true);
      })
      .catch((e) => { console.warn('[dog] load:', e?.message ?? e); setLoadErr(true); });
  };

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, []);

  // 다견 가구 — 새 아이 추가 후 바로 편집
  const onAddDog = () => {
    Alert.prompt?.('반려견 추가', '이름을 입력해주세요', async (n) => {
      if (!n?.trim()) return;
      try {
        const id = await addDog(n.trim());
        await load(id);
      } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
    }) ?? Alert.alert('반려견 추가', 'iOS에서 지원돼요');
  };

  const pickPhoto = async () => {
    if (!dog) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'], allowsEditing: true, aspect: [1, 1], quality: 0.7, base64: true,
      });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploading(true);
      const url = await uploadDogPhoto(dog.id, res.assets[0].base64);
      setDog((d) => (d ? { ...d, photoUrl: url } : d));
    } catch (e) {
      Alert.alert('업로드 실패', (e as Error).message);
    } finally {
      setUploading(false);
    }
  };

  const toggleTag = (t: string) =>
    setTags((cur) => (cur.includes(t) ? cur.filter((x) => x !== t) : [...cur, t]));

  const save = async () => {
    if (!dog) return;
    if (!name.trim()) { Alert.alert('이름을 입력해주세요'); return; }
    const w = weight.trim() ? Number(weight) : null;
    // ⚠ [0119 F2] THESE GUARDS ONLY JUDGE WHAT THE OWNER ACTUALLY TYPED, and that is a fix, not a
    // loosening. `dogs.weight_kg` is `numeric(4,1)` with NO check constraint, so 95.0 is a perfectly
    // legal stored value while this screen refuses anything over 90 — the client has always been
    // stricter than the database. That was harmless while saving was optional. It stops being
    // harmless the moment the declaration below becomes MANDATORY: an owner whose dog has sat at
    // 95kg since before this rule existed could not save 「맹견 아님」 without first falsifying or
    // deleting a valid weight, and until they save it their bookings are refused. That is an outage
    // aimed exactly at the legacy population the no-backfill decision was written to protect.
    // So: a value the owner did not touch is not theirs to re-litigate. A value they DID type is
    // still checked, which is what these guards were for.
    const weightUntouched = w === dog.weightKg || (w == null && dog.weightKg == null);
    const birthUntouched = (birth.trim() || null) === (dog.birthDate ?? null);
    if (!weightUntouched && weight.trim() && (Number.isNaN(w) || w! <= 0 || w! > 90)) { Alert.alert('몸무게를 확인해주세요', 'kg 숫자로 입력해요 (예: 6.5)'); return; }
    if (!birthUntouched && birth.trim() && !/^\d{4}-\d{2}-\d{2}$/.test(birth.trim())) { Alert.alert('생일 형식', 'YYYY-MM-DD 형식으로 입력해주세요 (예: 2021-03-15)'); return; }
    // ⚠ [0119] 신고는 선택 항목이 아니다. 답이 없으면 서버가 예약 자체를 거절하므로(그리고 기존
    // 반려견에 대한 백필은 일부러 하지 않았다), 답 없이 저장하면 '저장은 됐는데 예약이 안 되는'
    // 상태로 내보내는 것이 된다. 여기서 막고 이유를 말하는 편이 정직하다.
    if (danger === 'undeclared') {
      Alert.alert('맹견 여부를 알려주세요', '동물보호법상 맹견은 러너에게 맡길 수 없어요. 답하지 않으면 예약을 만들 수 없어서 먼저 여쭤봐요.');
      return;
    }
    // 짝이 맞지 않는 신고는 DB CHECK 가 거절한다 — 400 을 받아 '저장 실패'로 보여주기 전에 막는다.
    if (danger === 'declared_dangerous' && !basis) {
      Alert.alert('어떤 경우인지 알려주세요', '법정 견종인지, 기질평가로 지정받았는지 골라주세요.');
      return;
    }
    setSaving(true);
    try {
      await updateMyDog(dog.id, {
        name: name.trim(),
        breed: breed.trim() || undefined,
        birth_date: birth.trim() || null,
        weight_kg: w,
        neutered: neutered ?? undefined,
        memo: memo.trim() || undefined,
        prefTags: tags,
        vaccines,
        collar,
        paceSuggestSec: paceSuggest,
        // 짝으로만 보낸다 (api.ts 의 union 이 그 외의 조합을 타입에서 막는다).
        dangerous: danger === 'declared_dangerous'
          ? { status: 'declared_dangerous', basis: basis! }
          : { status: 'declared_none' },
      });
      // ⚠ [0119 F4] ADOPT THE WRITE WE JUST MADE. `dog` is the screen's record of SERVER truth and
      // the §F latch reads it (`dog?.dangerousStatus === 'declared_dangerous'`), so leaving it stale
      // means: declare 맹견, save successfully, and the 「맹견이 아니에요」 chip stays enabled and the
      // irreversible-warning stays hidden — until a remount. The owner then taps a control this
      // screen was designed to disable and gets a server refusal instead. Same disabled-control-
      // with-a-reason rule as everywhere else, applied one state later.
      // Only fields this save actually wrote are adopted; nothing here invents a server value.
      setDog((cur) => (cur ? {
        ...cur,
        name: name.trim(),
        birthDate: birth.trim() || null,
        weightKg: w,
        dangerousStatus: danger,
        dangerousBasis: danger === 'declared_dangerous' ? basis : null,
      } : cur));
      Alert.alert('저장 완료', '러너에게 전달되는 프로필이 업데이트됐어요');
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 130 }}>
        {/* [Sean 2026-08-11] 리밴프 — 라임 히어로 밴드 + 크림 캔버스 은퇴 (구 팔레트).
            페이퍼 크롬: 흰 캔버스 · 40×40 스퀘어 백 버튼 · 풀블리드 코랄 헤어라인.
            칼라 컬러 링도 제거: 아바타는 사각인데 링만 radius 22라 뒤에서 삐져나와 겹쳐 보였다.
            링은 컬러 프리뷰였을 뿐이고, 아래 칼라 피커 자체가 이미 그 색을 보여준다 (정보 손실 0). */}
        <View style={s.topBar}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={s.topTitle}>반려견 프로필</Text>
        </View>
        <View style={{ paddingHorizontal: layout.gutter, paddingTop: 16 }}>
          <Pressable onPress={pickPhoto} disabled={uploading} style={{ alignSelf: 'flex-start' }}>
            <Avatar url={dog?.photoUrl} char={(name || '멍')[0]} bg={paper.ink} size={88} />
            <View style={s.camBadge}><Text style={{ fontSize: 14, color: '#fff' }}>{uploading ? '…' : '✎'}</Text></View>
          </Pressable>
          <Text style={{ fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 8 }}>사진을 탭해서 변경 — 러너가 픽업 때 알아봐요</Text>
        </View>

        {!loaded && !loadErr && <Text style={{ padding: 16, fontSize: 14, color: paper.dim }}>불러오는 중...</Text>}
        {/* loud-fail strip — failure is never dressed as the empty state */}
        {!loaded && loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>반려견 정보를 불러오지 못했어요</Text>
            <Pressable onPress={() => load()} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !dog && (
          <Text style={{ padding: 16, fontSize: 14, lineHeight: 19, color: paper.dim }}>
            {/* ⚠ Auto-creation was deliberately retired: request.tsx says "여기서 아이를 만드는
                일은 영원히 없다" and bounces an owner with no dog straight back to this screen.
                The old copy promised the opposite, so a new owner could read it, skip
                registration, tap 러너 찾기, and land right back here — a loop with a polite lie
                in the middle. */}
            아직 등록된 아이가 없어요 — 예약하려면 먼저 아이를 등록해주세요
          </Text>
        )}

        {dog && (
          <View style={{ paddingHorizontal: layout.gutter, marginTop: 18 }}>
            {/* 다견 스위처 */}
            <Row style={{ gap: 8, flexWrap: 'wrap' }}>
              {dogs.map((d) => (
                <Pressable key={d.id} onPress={() => selectDog(d)} style={[s.dogChip, dog.id === d.id && { backgroundColor: paper.ink, borderColor: paper.ink }]}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: dog.id === d.id ? '#fff' : paper.ink }}>{d.name}</Text>
                </Pressable>
              ))}
              <Pressable onPress={onAddDog} style={[s.dogChip, { borderStyle: 'dashed' }]}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>＋ 추가</Text>
              </Pressable>
            </Row>

            {/* 칼라 컬러 (P1, 0033) — 내 아이의 색: 아바타 링·일정 카드 도트가 이 색으로 */}
            <Text style={s.label}>칼라 컬러 — 내 아이의 색</Text>
            <Row style={{ gap: 9, flexWrap: 'wrap' }}>
              {(Object.keys(collarColors) as CollarKey[]).map((k) => (
                <Pressable
                  key={k}
                  onPress={() => setCollar((cur) => (cur === k ? null : k))}
                  style={[s.collarDot, { backgroundColor: collarColors[k] }, collar === k && s.collarDotOn]}
                >
                  {collar === k && <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>✓</Text>}
                </Pressable>
              ))}
            </Row>
            <Text style={{ fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 8 }}>
              {collar ? `${collarLabels[collar]} — ${name || '아이'}의 시그니처 컬러예요` : '고르면 일정·카드에서 이 색으로 보여요 (선택)'}
            </Text>

            {/* 기본 정보 */}
            <Text style={s.label}>이름</Text>
            <TextInput value={name} onChangeText={setName} style={s.input} maxLength={12} placeholder="초코" placeholderTextColor="#b0ada0" />
            <Row style={{ gap: 10 }}>
              <View style={{ flex: 1 }}>
                <Text style={s.label}>견종</Text>
                <TextInput value={breed} onChangeText={setBreed} style={s.input} maxLength={20} placeholder="웰시코기" placeholderTextColor="#b0ada0" />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={s.label}>몸무게 (kg)</Text>
                <TextInput value={weight} onChangeText={setWeight} style={s.input} keyboardType="decimal-pad" maxLength={5} placeholder="6.5" placeholderTextColor="#b0ada0" />
              </View>
            </Row>
            <Row style={{ gap: 10 }}>
              <View style={{ flex: 1 }}>
                <Text style={s.label}>생일 (YYYY-MM-DD)</Text>
                <TextInput value={birth} onChangeText={setBirth} style={s.input} maxLength={10} placeholder="2021-03-15" placeholderTextColor="#b0ada0" />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={s.label}>중성화</Text>
                <Row style={{ gap: 8 }}>
                  {([[true, '했어요'], [false, '안 했어요']] as const).map(([v, label]) => (
                    <Pressable key={label} onPress={() => setNeutered(v)} style={[s.neuterChip, neutered === v && { backgroundColor: paper.ink, borderColor: paper.ink }]}>
                      <Text style={{ fontSize: 14, fontWeight: '800', color: neutered === v ? '#fff' : paper.ink }}>{label}</Text>
                    </Pressable>
                  ))}
                </Row>
              </View>
            </Row>

            {/* ═══ 맹견 신고 (0119) ═══════════════════════════════════════════════════════
                자기 섹션을 갖는 이유: 이건 취향이 아니라 법적 게이트다. 답이 없으면 서버가
                예약 INSERT 와 인계 방향 전이를 전부 거절한다.
                ⚠ 이 화면은 판정하지 않는다 — 보호자의 진술을 받을 뿐이다 (특허 설계 게이트:
                학습 모델도, 점수도, 견종 추론도 없다. 이진 질문 하나).
                ⚠ `undeclared` 는 막다른 길이 아니라 '아직 안 물어봤다'이고, 그래서 문구는
                거절이 아니라 요청이다. */}
            <View style={s.secRule} />
            <Text style={s.secH}>맹견 여부</Text>
            <Text style={s.dangerIntro}>
              동물보호법상 맹견은 러너에게 맡길 수 없어요. 한 번만 여쭤봐요.
            </Text>
            <View style={s.dangerRow} accessibilityRole="radiogroup" accessibilityLabel="맹견 여부">
              {([['declared_none', '맹견이 아니에요'], ['declared_dangerous', '맹견이에요']] as const).map(([v, label]) => {
                const on = danger === v;
                // 신고는 한 방향으로 잠긴다 (0119 §F): 맹견으로 신고한 뒤에는 화면에서 되돌릴 수
                // 없다. 서버가 거절할 버튼을 그려두면 그게 죽은 버튼이므로, 아예 비활성으로 두고
                // 아래에서 사유를 말한다.
                const locked = dog?.dangerousStatus === 'declared_dangerous' && v === 'declared_none';
                return (
                  <Pressable
                    key={v}
                    onPress={() => { if (locked) return; setDanger(v); if (v === 'declared_none') setBasis(null); }}
                    disabled={locked}
                    style={[s.neuterChip, on && { backgroundColor: paper.ink, borderColor: paper.ink }, locked && s.chipLocked]}
                    accessibilityRole="radio"
                    accessibilityState={{ selected: on, disabled: locked }}
                    accessibilityLabel={label}
                  >
                    <Text style={{ fontSize: 14, fontWeight: '800', color: on ? '#fff' : locked ? paper.faint : paper.ink }}>{label}</Text>
                  </Pressable>
                );
              })}
            </View>
            {danger === 'declared_dangerous' && (
              <>
                <Text style={s.label}>어떤 경우인가요</Text>
                <View style={s.dangerRow} accessibilityRole="radiogroup" accessibilityLabel="맹견 지정 근거">
                  {([['listed_breed', '법정 견종'], ['designated', '기질평가 지정']] as const).map(([v, label]) => {
                    const on = basis === v;
                    return (
                      <Pressable
                        key={v}
                        onPress={() => setBasis(v)}
                        style={[s.neuterChip, on && { backgroundColor: paper.ink, borderColor: paper.ink }]}
                        accessibilityRole="radio"
                        accessibilityState={{ selected: on }}
                        accessibilityLabel={label}
                      >
                        <Text style={{ fontSize: 14, fontWeight: '800', color: on ? '#fff' : paper.ink }}>{label}</Text>
                      </Pressable>
                    );
                  })}
                </View>
              </>
            )}
            {/* 결과를 숨기지 않는다. 다만 '허가증을 내면 된다'는 암시는 절대 하지 않는다 —
                입마개·맹견사육허가·책임보험을 확인할 수단이 이 제품에 없고, 확인자 없는 조건은
                양식일 뿐이다 (0119 REGISTRY 의 판단, Sean 미결). 대신 실제로 열려 있는 문 하나만
                말한다: 클럽 동반 참여는 막히지 않는다. */}
            {danger === 'declared_dangerous' && (
              <Text style={s.dangerNote}>
                맹견은 러너에게 맡기는 예약을 만들 수 없어요. 보호자님이 함께 가는 클럽 동반 참여는 그대로 이용할 수 있어요.
              </Text>
            )}
            {dog?.dangerousStatus === 'declared_dangerous' && (
              <Text style={s.dangerNote}>
                맹견 신고는 화면에서 되돌릴 수 없어요. 잘못 고르셨다면 고객센터로 알려주세요.
              </Text>
            )}

            {/* 권장 최소 페이스 (pace-state-ui-plan §4) — 러닝 중 페이스 신호의 기준.
                §3b 섹션 헤더 문법(풀블리드 코랄 룰 + 20/800 잉크)으로 자기 섹션을 갖는다:
                이름·견종 사이에 묻히면 안 되는 '행동 컨트롤'이다. 저장은 기존 버튼 하나. */}
            <View style={s.secRule} />
            <Text style={s.secH}>권장 최소 페이스</Text>
            <View style={s.paceRow} accessibilityRole="radiogroup" accessibilityLabel="권장 최소 페이스">
              {PACE_OPTIONS.map((o) => {
                const on = paceSuggest === o.sec;
                return (
                  <Pressable
                    key={o.sec}
                    onPress={() => setPaceSuggest(o.sec)}
                    style={[s.paceChip, on && s.paceChipOn]}
                    accessibilityRole="radio"
                    accessibilityState={{ selected: on }}
                    accessibilityLabel={o.a11y}
                  >
                    <Text style={{ fontSize: 16, fontWeight: '800', color: on ? '#fff' : paper.ink }}>{o.label}</Text>
                  </Pressable>
                );
              })}
            </View>
            {/* 헬퍼는 색이 아니라 '행동'을 설명한다 — 화면의 색 규칙은 여기서 가르치지 않는다 */}
            <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 10 }}>
              이 값보다 느려지면 러너에게 안내해요
            </Text>

            {/* 성향 메모 */}
            <Text style={s.label}>러너에게 전달되는 성향 메모</Text>
            <TextInput
              value={memo}
              onChangeText={setMemo}
              style={[s.input, { height: 88, textAlignVertical: 'top', paddingTop: 12 }]}
              multiline
              maxLength={200}
              placeholder="예: 자전거를 보면 짖어요. 낯은 안 가려서 바로 인사해도 괜찮아요"
              placeholderTextColor="#b0ada0"
            />

            {/* 예방접종 */}
            <Text style={s.label}>예방접종 (완료한 항목 선택)</Text>
            <Row style={{ gap: 8, flexWrap: 'wrap' }}>
              {VACCINE_CATALOG.map((v) => {
                const on = vaccines.includes(v);
                return (
                  <Pressable
                    key={v}
                    onPress={() => setVaccines((cur) => (on ? cur.filter((x) => x !== v) : [...cur, v]))}
                    style={[s.tagChip, on && s.tagChipOn]}
                  >
                    <Text style={{ fontSize: 14, fontWeight: '800', color: on ? paper.ink : paper.text }}>{on ? '✓ ' : ''}{v}</Text>
                  </Pressable>
                );
              })}
            </Row>

            {/* 선호 태그 */}
            <Text style={s.label}>선호 러닝 조건 · 성향 태그</Text>
            <Row style={{ gap: 8, flexWrap: 'wrap' }}>
              {PREF_CATALOG.map((t) => {
                const on = tags.includes(t);
                return (
                  <Pressable key={t} onPress={() => toggleTag(t)} style={[s.tagChip, on && s.tagChipOn]}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: on ? paper.ink : paper.text }}>{on ? '✓ ' : ''}{t}</Text>
                  </Pressable>
                );
              })}
            </Row>
            <Text style={{ fontSize: 14, color: paper.dim, marginTop: 12, lineHeight: 19 }}>
              태그와 메모는 러너의 요청 카드에 그대로 표시돼요{'\n'}주간 목표 거리는 체력 리포트에서 조정해요
            </Text>
          </View>
        )}
      </ScrollView>

      {dog && (
        <View style={s.saveBar}>
          {/* §3b 프라이머리: 잉크 면 · 화이트 17/800 · radius 0. busy = 라벨 스왑 (opacity 0.5 트릭 폐기, F2.1). */}
          <Pressable onPress={save} disabled={saving} style={({ pressed }) => [s.saveBtn, pressed && { backgroundColor: paper.actionPressed }]}>
            <Text style={{ fontSize: 17, fontWeight: '800', color: '#fff' }}>{saving ? '저장 중...' : '저장하기'}</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  // 페이퍼 크롬 상단 — 풀블리드 코랄 헤어라인 + 40×40 스퀘어 백 (runner/meetup circleBtn 문법)
  topBar: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingTop: 56, paddingBottom: 12, paddingHorizontal: layout.gutter,
    borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  topTitle: { fontSize: 20, fontWeight: '800', color: paper.ink },
  backBtn: {
    width: 40, height: 40, borderWidth: 1, borderColor: paper.line,
    backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
  },
  // loud-fail strip — criticalWash bg + critical ink + retry (community.tsx grammar)
  failStrip: { marginHorizontal: layout.gutter, marginTop: 14, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  camBadge: {
    position: 'absolute', right: -1, bottom: -1, width: 24, height: 24,
    backgroundColor: paper.ink, alignItems: 'center', justifyContent: 'center',
    borderWidth: 2, borderColor: paper.canvas,
  },
  label: { fontSize: 14, fontWeight: '800', color: paper.ink, marginTop: 18, marginBottom: 7 },
  // 입력 = 뉴트럴 카드 (radius 0 · 1px #EEE). 강조는 코랄 선과 CTA 하나에만 (§8 예산).
  input: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 12, paddingHorizontal: 13, fontSize: 16, color: paper.ink,
  },
  neuterChip: { flex: 1, backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', alignItems: 'center', paddingVertical: 13 },
  dogChip: { backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', paddingVertical: 10, paddingHorizontal: 15 },
  // 칼라 스와치 — 사각(샤프 코너 법). 선택 = 잉크 링 + 체크. 페인트 칩처럼 읽힌다.
  collarDot: { width: 38, height: 38, borderRadius: 0, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#EEEEEE' },
  collarDotOn: { borderWidth: 2.5, borderColor: paper.ink },
  tagChip: { backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', paddingVertical: 10, paddingHorizontal: 13 },
  tagChipOn: { backgroundColor: paper.wash, borderColor: paper.line },
  // §3b 섹션 헤더 — 풀블리드 코랄 1px 룰 + 20/800 잉크 타이틀. 이 화면은 gutter 패딩 안이라
  // 룰만 음수 마진으로 화면 끝까지 빼낸다 (사이드 마진 금지 법).
  secRule: { height: 1, backgroundColor: paper.line, marginHorizontal: -layout.gutter, marginTop: 26 },
  secH: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink, marginTop: 14, marginBottom: 11 },
  // 페이스 밴드 칩 — 5개가 한 줄, 44pt 터치, 갭 10. 선택 = 잉크 면 + 흰 16/800 (선택칩은
  // 액션이 아니라 상태라서 잉크가 남는다, §3b 버튼 매트릭스).
  paceRow: { flexDirection: 'row', gap: 10 },
  paceChip: {
    flex: 1, minHeight: 44, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
  },
  paceChipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  // [0119] 신고 섹션. 14pt 바닥 준수 — 법적 고지를 장식 클래스로 내리지 않는다.
  dangerRow: { flexDirection: 'row', gap: 8 },
  dangerIntro: { fontSize: 14, lineHeight: 19, color: paper.dim, marginBottom: 11 },
  dangerNote: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 10 },
  // 잠긴 칩은 명시 fill — 불투명도 트릭 금지 (DESIGN.md, disabledFill 이 그 법의 물화).
  chipLocked: { backgroundColor: paper.disabledFill, borderColor: paper.disabledFill },
  saveBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    paddingHorizontal: layout.gutter, paddingTop: 10, paddingBottom: 30, borderTopWidth: 1, borderTopColor: paper.line,
  },
  saveBtn: { backgroundColor: paper.action, borderRadius: 0, alignItems: 'center', paddingVertical: 16 },
});
