import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { addDog, DogProfile, fetchMyDogs, updateMyDog, uploadDogPhoto } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 반려견 프로필 — 실초코. 사진·정보·성향 메모·선호 태그가 러너에게 전달된다.
// 진입: 예약 화면 강아지 카드 · 마이 메뉴. 저장은 섹션 하단 버튼 1개.

const FOREST = '#0F1D13';

// 선호/성향 태그 카탈로그 — dogs.preferences.tags 로 저장, 러너 요청 카드에 표시
const PREF_CATALOG = [
  '흙길 선호', '이른 아침', '저녁 선호', '자전거 주의', '사람 좋아함',
  '강아지 좋아함', '소심해요', '간식 러버', '물 자주 필요', '천천히 워밍업',
];
const VACCINE_CATALOG = ['종합백신', '광견병', '코로나 장염', '켄넬코프'];

export default function DogProfileScreen() {
  const { dogId } = useLocalSearchParams<{ dogId?: string }>();
  const [dogs, setDogs] = useState<DogProfile[]>([]);
  const [dog, setDog] = useState<DogProfile | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [name, setName] = useState('');
  const [breed, setBreed] = useState('');
  const [birth, setBirth] = useState('');
  const [weight, setWeight] = useState('');
  const [neutered, setNeutered] = useState<boolean | null>(null);
  const [memo, setMemo] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [vaccines, setVaccines] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const selectDog = (d: DogProfile) => {
    setDog(d);
    setName(d.name);
    setBreed(d.breed ?? '');
    setBirth(d.birthDate ?? '');
    setWeight(d.weightKg != null ? String(d.weightKg) : '');
    setNeutered(d.neutered);
    setMemo(d.memo ?? '');
    setTags(d.prefTags);
    setVaccines(d.vaccines);
  };

  const load = (preferId?: string) => fetchMyDogs()
    .then((list) => {
      setDogs(list);
      const target = list.find((x) => x.id === (preferId ?? dogId)) ?? list[0];
      if (target) selectDog(target);
      setLoaded(true);
    })
    .catch((e) => { console.warn('[dog] load:', e?.message ?? e); setLoaded(true); });

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
    if (weight.trim() && (Number.isNaN(w) || w! <= 0 || w! > 90)) { Alert.alert('몸무게를 확인해주세요', 'kg 숫자로 입력해요 (예: 6.5)'); return; }
    if (birth.trim() && !/^\d{4}-\d{2}-\d{2}$/.test(birth.trim())) { Alert.alert('생일 형식', 'YYYY-MM-DD 형식으로 입력해주세요 (예: 2021-03-15)'); return; }
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
      });
      Alert.alert('저장 완료', '러너에게 전달되는 프로필이 업데이트됐어요');
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 120 }}>
        {/* hero band + photo */}
        <View style={{ height: 150, backgroundColor: colors.volt }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        </View>
        <View style={{ paddingHorizontal: 12, marginTop: -44 }}>
          <Pressable onPress={pickPhoto} disabled={uploading} style={{ alignSelf: 'flex-start' }}>
            <View style={{ borderWidth: 4, borderColor: colors.cream, borderRadius: 22 }}>
              <Avatar url={dog?.photoUrl} char={(name || '멍')[0]} bg={FOREST} size={88} />
            </View>
            <View style={s.camBadge}><Text style={{ fontSize: 11.5, color: '#fff' }}>{uploading ? '…' : '✎'}</Text></View>
          </Pressable>
          <Text style={{ fontSize: 14.5, color: colors.dim, marginTop: 6 }}>사진을 탭해서 변경 — 러너가 픽업 때 알아봐요</Text>
        </View>

        {!loaded && <Text style={{ padding: 16, fontSize: 14.5, color: colors.dim }}>불러오는 중...</Text>}
        {loaded && !dog && (
          <Text style={{ padding: 16, fontSize: 14.5, color: colors.dim }}>
            아직 반려견이 없어요 — 첫 예약 때 자동으로 만들어져요
          </Text>
        )}

        {dog && (
          <View style={{ paddingHorizontal: 12, marginTop: 14 }}>
            {/* 다견 스위처 */}
            <Row style={{ gap: 8, flexWrap: 'wrap' }}>
              {dogs.map((d) => (
                <Pressable key={d.id} onPress={() => selectDog(d)} style={[s.dogChip, dog.id === d.id && { backgroundColor: FOREST }]}>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: dog.id === d.id ? '#fff' : '#3d453d' }}>{d.name}</Text>
                </Pressable>
              ))}
              <Pressable onPress={onAddDog} style={[s.dogChip, { borderStyle: 'dashed' }]}>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#5a7a3c' }}>＋ 추가</Text>
              </Pressable>
            </Row>

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
                    <Pressable key={label} onPress={() => setNeutered(v)} style={[s.neuterChip, neutered === v && { backgroundColor: FOREST }]}>
                      <Text style={{ fontSize: 14.5, fontWeight: '700', color: neutered === v ? '#fff' : '#3d453d' }}>{label}</Text>
                    </Pressable>
                  ))}
                </Row>
              </View>
            </Row>

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
                    style={[s.tagChip, on && { backgroundColor: '#e3eff9', borderColor: '#9fc3e8' }]}
                  >
                    <Text style={{ fontSize: 14.5, fontWeight: '700', color: on ? '#2d6da8' : '#49524a' }}>{on ? '💉 ' : ''}{v}</Text>
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
                  <Pressable key={t} onPress={() => toggleTag(t)} style={[s.tagChip, on && { backgroundColor: '#eaf7c8', borderColor: '#a9c47e' }]}>
                    <Text style={{ fontSize: 14.5, fontWeight: '700', color: on ? '#3d5a2b' : '#49524a' }}>{on ? '✓ ' : ''}{t}</Text>
                  </Pressable>
                );
              })}
            </Row>
            <Text style={{ fontSize: 14, color: colors.dim, marginTop: 8, lineHeight: 17 }}>
              태그와 메모는 러너의 요청 카드에 그대로 표시돼요{'\n'}주간 목표 거리는 체력 리포트에서 조정해요
            </Text>
          </View>
        )}
      </ScrollView>

      {dog && (
        <View style={s.saveBar}>
          <Pressable onPress={save} disabled={saving} style={[s.saveBtn, saving && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>{saving ? '저장 중...' : '저장하기'}</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { position: 'absolute', top: 56, left: 16, width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  camBadge: {
    position: 'absolute', right: -2, bottom: -2, width: 22, height: 22, borderRadius: 11,
    backgroundColor: '#5a7a3c', alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: colors.cream,
  },
  label: { fontSize: 14, fontWeight: '800', color: '#3d453d', marginTop: 16, marginBottom: 6 },
  input: {
    backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4',
    paddingVertical: 12, paddingHorizontal: 14, fontSize: 16.5, color: FOREST,
  },
  neuterChip: { flex: 1, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4', alignItems: 'center', paddingVertical: 13 },
  dogChip: { backgroundColor: '#fff', borderRadius: 99, borderWidth: 1.3, borderColor: '#dcd9cc', paddingVertical: 9, paddingHorizontal: 16 },
  tagChip: { backgroundColor: '#fff', borderRadius: 99, borderWidth: 1.3, borderColor: '#DCD6C4', paddingVertical: 9, paddingHorizontal: 14 },
  saveBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: colors.cream,
    paddingHorizontal: 12, paddingTop: 10, paddingBottom: 30, borderTopWidth: 1, borderTopColor: '#DCD6C4',
  },
  saveBtn: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 15 },
});
