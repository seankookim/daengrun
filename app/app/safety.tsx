import { useDisplayFont } from '../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Icon, Row } from '../src/components/ui';
import { addEmergencyContact, deleteEmergencyContact, EmContact, fetchEmergencyContacts, sendSOS } from '../src/lib/api';
import { haptic } from '../src/lib/haptics';
import { session } from '../src/store';
import { colors, paper } from '../src/theme';

// 안심 센터 — 실동작: SOS(진행 중 예약 상대에게 즉시 알림), 긴급 연락처 CRUD, 전화 걸기.
// 신고·의료노트는 각각 향후 세션(incidents 플로우 / 반려견 프로필 메모가 대체).

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.

export default function Safety() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [adding, setAdding] = useState(false);
  const [cName, setCName] = useState('');
  const [cPhone, setCPhone] = useState('');

  // ⚠ Three states, not two. A failed READ used to fall into the same render as "you have no
  // contacts" — so an owner opening this screen mid-incident on a flaky connection was told their
  // emergency roster was empty. On a safety surface that is the worst possible substitution, and
  // this file already learned the lesson once on the DELETE path (see the comment there); the read
  // never got the same treatment. `null` = not loaded yet / failed, and it renders as itself.
  const [contacts, setContacts] = useState<EmContact[] | null>(null);
  const [loadErr, setLoadErr] = useState(false);
  const load = () => {
    setLoadErr(false);
    return fetchEmergencyContacts()
      .then(setContacts)
      .catch((e) => { console.warn('[safety]:', e?.message ?? e); setLoadErr(true); });
  };
  useFocusEffect(useCallback(() => { load(); }, []));

  const sos = () => {
    Alert.alert('SOS', '진행 중인 러닝의 상대방에게 긴급 알림을 보낼까요?', [
      { text: '취소', style: 'cancel' },
      {
        text: 'SOS 전송', style: 'destructive',
        onPress: async () => {
          haptic('success');
          try {
            const bid = await sendSOS(session.role === 'runner' ? 'runner' : 'owner');
            if (bid) Alert.alert('전송 완료', '상대방에게 긴급 알림이 전송됐어요.\n위급 상황이면 즉시 112/119에 연락하세요.');
            else Alert.alert('진행 중인 러닝이 없어요', '위급 상황이면 즉시 112/119에 연락하세요.');
          } catch (e) {
            Alert.alert('전송 실패', `${(e as Error).message}\n위급 상황이면 즉시 112/119에 연락하세요.`);
          }
        },
      },
    ]);
  };

  const saveContact = async () => {
    if (!cName.trim() || !cPhone.trim()) { Alert.alert('이름과 전화번호를 입력해주세요'); return; }
    try {
      await addEmergencyContact(cName.trim(), cPhone.trim());
      setCName(''); setCPhone(''); setAdding(false);
      load();
    } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
  };

  const removeContact = (c: EmContact) => {
    Alert.alert('연락처 삭제', `${c.name}을(를) 긴급 연락처에서 삭제할까요?`, [
      { text: '취소', style: 'cancel' },
      {
        text: '삭제', style: 'destructive',
        // [honesty 2026-08-11] a confirmed destructive delete of an EMERGENCY contact
        // used to fail silently — the user believed the safety roster changed. It says so now.
        onPress: () => deleteEmergencyContact(c.id).then(load).catch((e) => Alert.alert('삭제 실패', (e as Error).message)),
      },
    ]);
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 64, paddingBottom: 24 }}>
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Pressable onPress={() => router.back()} style={[s.bell, { marginRight: 12 }]}>
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 8 }}>
              <Text style={[s.h1, df]}>안심 센터</Text>
              <View style={s.shieldChip}><Text style={{ fontSize: 14, color: paper.ink }}>✚</Text></View>
            </Row>
            <Text style={s.sub}>안전하고 즐거운 러닝을 위한 실비상 체계</Text>
          </View>
        </Row>

        {/* ---------- SOS (실동작) ---------- */}
        <Pressable style={s.sosCard} onPress={sos}>
          <Icon name="Siren" glyph="✚" size={28} color="#fff" />
          <View style={{ flex: 1, marginLeft: 14 }}>
            <Text style={{ fontSize: 18.5, fontWeight: '900', color: '#fff' }}>SOS 긴급 알림</Text>
            {/* ⚠ White, not a tinted salmon. `#ffd9cf` on this ground measured 2.97:1 — below the
                4.5 floor — and the sentence carrying it is 「위급 시엔 112·119가 항상 우선이에요」,
                the single most important line on the screen. White on the tokenized ground
                (paper.action) measures 4.84:1, the value theme.ts:182 already records. */}
            <Text style={{ fontSize: 14, color: '#fff', marginTop: 3, lineHeight: 18.5 }}>
              진행 중인 러닝의 상대방에게 즉시 알림{'\n'}위급 시엔 112·119가 항상 우선이에요
            </Text>
          </View>
        </Pressable>
        <Row style={{ gap: 10, marginTop: 10 }}>
          <Pressable style={s.callBtn} onPress={() => Linking.openURL('tel:112')}>
            <Icon name="Phone" glyph="●" size={14} color="#d84a2f" />
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#d84a2f' }}>112</Text>
          </Pressable>
          <Pressable style={s.callBtn} onPress={() => Linking.openURL('tel:119')}>
            <Icon name="Phone" glyph="●" size={14} color="#d84a2f" />
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#d84a2f' }}>119</Text>
          </Pressable>
        </Row>

        {/* ---------- 긴급 연락처 (실CRUD) ---------- */}
        <Text style={s.section}>긴급 연락처</Text>
        <View style={s.card}>
          {/* Failure, loading and genuine-empty are three different sentences. Only the last one
              may claim the roster is empty. */}
          {loadErr && (
            <Row style={{ paddingVertical: 6, alignItems: 'center' }}>
              <Text style={{ flex: 1, fontSize: 14.5, color: paper.critical, fontWeight: '700' }}>
                연락처를 불러오지 못했어요
              </Text>
              <Pressable onPress={load} style={s.miniBtn} accessibilityRole="button">
                <Text style={{ fontSize: 14, fontWeight: '800', color: paper.actionInk }}>다시 시도</Text>
              </Pressable>
            </Row>
          )}
          {!loadErr && contacts === null && (
            <Text style={{ fontSize: 14.5, color: colors.dim, paddingVertical: 6 }}>불러오는 중...</Text>
          )}
          {contacts?.length === 0 && !adding && (
            <Text style={{ fontSize: 14.5, color: colors.dim, paddingVertical: 6 }}>
              아직 없어요 — 위급 시 연락할 가족·지인을 등록해두세요
            </Text>
          )}
          {(contacts ?? []).map((c, i) => (
            <View key={c.id}>
              {i > 0 && <View style={s.div} />}
              <Row style={{ paddingVertical: 10, alignItems: 'center' }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>{c.name}</Text>
                  <Text style={{ fontSize: 14, color: colors.dim, marginTop: 2 }}>{c.phone}</Text>
                </View>
                <Pressable onPress={() => Linking.openURL(`tel:${c.phone}`)} style={s.miniBtn}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#3d5a2b' }}>전화</Text>
                </Pressable>
                <Pressable onPress={() => removeContact(c)} style={[s.miniBtn, { marginLeft: 6 }]}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#d84a2f' }}>삭제</Text>
                </Pressable>
              </Row>
            </View>
          ))}
          {adding ? (
            <View style={{ marginTop: 8, gap: 8 }}>
              <TextInput value={cName} onChangeText={setCName} placeholder="이름 (예: 엄마)" placeholderTextColor="#b0ada0" style={s.input} maxLength={12} />
              <TextInput value={cPhone} onChangeText={setCPhone} placeholder="전화번호" placeholderTextColor="#b0ada0" style={s.input} keyboardType="phone-pad" maxLength={15} />
              <Row style={{ gap: 8 }}>
                <Pressable onPress={saveContact} style={[s.saveBtn, { flex: 1.4 }]}>
                  <Text style={{ fontSize: 14.5, fontWeight: '900', color: paper.ink }}>저장</Text>
                </Pressable>
                <Pressable onPress={() => setAdding(false)} style={[s.miniBtn, { flex: 1, alignItems: 'center', paddingVertical: 11 }]}>
                  <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#49524a' }}>취소</Text>
                </Pressable>
              </Row>
            </View>
          ) : (
            <Pressable onPress={() => setAdding(true)} style={s.addRow}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#5a7a3c' }}>＋ 연락처 추가</Text>
            </Pressable>
          )}
        </View>

        {/* ---------- 보험·안전 안내 (정보성) ---------- */}
        <Text style={s.section}>안전 체계</Text>
        <View style={s.card}>
          {/* [정직 배치 2.5] 서명된 증권이 없다 — 적용 시점·범위 주장 은퇴, 협의 중이라는 사실만 남긴다 */}
          <InfoRow icon="Shield" glyph="✚" title="펫보험" desc="파일럿 보험 파트너와 협의 중이에요" />
          <View style={s.div} />
          <InfoRow icon="MapPin" glyph="●" title="실시간 위치" desc="러닝 중 보호자 라이브 지도에 러너 경로가 실시간 표시돼요" />
          <View style={s.div} />
          {/* [honesty repair 2026-08-08 / plan §7.1-7.2] The previous copy ("모든 러너는 신원 확인을
              거쳐요 (본인인증 고도화 예정)") was the strongest false claim in the app: identity_verified
              is hardcoded false at creation and no automated check exists. "고도화 예정" made it worse
              by implying a basic check already runs. This copy states the manual process that actually
              happens during the pilot — an operator meets the runner on video and checks the ID — and
              promises no upgrade date. It is true only while approval flows through runner_app_approve
              (the sole tier writer) and no seeded/grandfathered certified runners exist in prod. */}
          <InfoRow
            glyph="✓"
            title="러너 신원"
            desc="파일럿 기간에는 운영자가 화상 통화로 러너를 직접 만나 신분증을 확인하고 한 명씩 승인해요 — 자동 본인인증(PASS)은 아직 도입 전이에요"
          />
        </View>

        {/* ---------- 준비 중 (정직 라벨) ---------- */}
        <Row style={{ gap: 10, marginTop: 14 }}>
          <View style={[s.card, { flex: 1, opacity: 0.55, marginTop: 0 }]}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>사고 신고</Text>
            <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>인시던트 플로우 준비 중</Text>
          </View>
          {/* ⚠ Owner-only destination. This screen is a quick link from BOTH homes, and
              `/owner/dog` has no role guard of its own — so a runner could land on the owner's dog
              screen and create a real `dogs` row from its empty state. The row is still rendered
              for a runner (the information is true for them too: medical notes live on the owner's
              dog profile), it simply stops being a door into an owner-only write surface. */}
          {session.role === 'runner' ? (
            <View style={[s.card, { flex: 1, marginTop: 0 }]}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>의료·성향 메모</Text>
              <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>보호자가 등록한 내용을 러닝 화면에서 볼 수 있어요</Text>
            </View>
          ) : (
            <Pressable style={[s.card, { flex: 1, marginTop: 0 }]} onPress={() => router.push('/owner/dog')}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>의료·성향 메모</Text>
              <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>반려견 프로필에서 관리 ›</Text>
            </Pressable>
          )}
        </Row>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

function InfoRow({ icon, glyph, title, desc }: { icon?: string; glyph: string; title: string; desc: string }) {
  return (
    <Row style={{ paddingVertical: 10, gap: 10 }}>
      {icon ? <Icon name={icon} glyph={glyph} size={18} color={paper.ink} /> : <Text style={{ fontSize: 18.5, color: paper.ink }}>{glyph}</Text>}
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>{title}</Text>
        <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2, lineHeight: 18.5 }}>{desc}</Text>
      </View>
    </Row>
  );
}

const s = StyleSheet.create({
  // [§3c 화면 타이틀 2026-08-11] lineHeight 37 = 1.23× 명시 (BUG A). 크기는 이미 규격값이었다.
  h1: { fontSize: 30, fontWeight: '900', color: paper.ink, lineHeight: 37 },
  sub: { fontSize: 14, color: colors.dim, marginTop: 4 },
  bell: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  shieldChip: { width: 24, height: 24, borderRadius: 12, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center', alignSelf: 'center' },
  // Ground is the TOKEN, not an ad-hoc coral. `#e8492a` was untokenized and too light: white
  // clears only 3.88:1 on it, so nothing this card could print would have passed AA. paper.action
  // carries white at 4.84:1 (measured; theme.ts:182 states the same number).
  sosCard: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: paper.action,
    borderRadius: 20, padding: 18, marginTop: 18,
  },
  callBtn: { flex: 1, backgroundColor: '#fff', borderRadius: 14, flexDirection: 'row', gap: 6, justifyContent: 'center', alignItems: 'center', paddingVertical: 12, borderWidth: 1.3, borderColor: '#f2d4ca' },
  section: { fontSize: 17, fontWeight: '900', color: paper.ink, marginTop: 20, marginBottom: 8 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 14, borderWidth: 1, borderColor: '#DCD6C4' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  miniBtn: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 },
  addRow: { marginTop: 6, borderRadius: 12, borderWidth: 1.3, borderColor: '#cfd8c2', borderStyle: 'dashed', alignItems: 'center', paddingVertical: 11 },
  input: { backgroundColor: '#faf9f3', borderRadius: 12, borderWidth: 1, borderColor: '#DCD6C4', paddingVertical: 10, paddingHorizontal: 12, fontSize: 15.5, color: paper.ink },
  saveBtn: { backgroundColor: colors.volt, borderRadius: 12, alignItems: 'center', paddingVertical: 11 },
});
