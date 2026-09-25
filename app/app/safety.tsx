import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomNav } from '../src/components/bottomnav';
import { PaperBtn } from '../src/components/paper-btn';
import { Icon, Row, ScreenHead } from '../src/components/ui';
import {
  addEmergencyContact, deleteEmergencyContact, EmContact, fetchEmergencyContacts,
  fetchReportableRun, ReportableRun, sendSOS,
} from '../src/lib/api';
import { haptic } from '../src/lib/haptics';
import { session } from '../src/store';
import { layout, paper } from '../src/theme';

// 안심 센터 — 실동작: SOS(진행 중 예약 상대에게 즉시 알림), 긴급 연락처 CRUD, 전화 걸기,
// 사고 신고(/incident/[bid] — 0094 ⑪ 의 클라이언트 절반). 의료노트는 반려견 프로필이 대체한다.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.

export default function Safety() {
  const insets = useSafeAreaInsets();
  const [adding, setAdding] = useState(false);
  const [cName, setCName] = useState('');
  const [cPhone, setCPhone] = useState('');
  // busy = label swap on 저장 (PaperBtn), and a second tap during the write is refused rather than
  // sending a duplicate contact.
  const [saving, setSaving] = useState(false);

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

  // 사고 신고 카드가 어디로 갈지 — 서버가 정한다 (0114 §3 의 접수 가능 집합).
  // ⚠ 네 상태를 넷으로 둔다. 「불러오는 중」이 「없어요」로 접히면, 접수할 수 있는 러닝을 가진
  // 사람이 안 된다는 말을 듣는다 — 이 파일이 긴급 연락처에서 이미 한 번 배운 치환이다.
  const [run, setRun] = useState<ReportableRun | null>(null);
  const [runState, setRunState] = useState<'loading' | 'found' | 'none' | 'error'>('loading');
  const loadRun = () => {
    setRunState('loading');
    return fetchReportableRun()
      .then((r) => { setRun(r); setRunState(r ? 'found' : 'none'); })
      .catch((e) => { console.warn('[safety] run:', e?.message ?? e); setRunState('error'); });
  };
  useFocusEffect(useCallback(() => { load(); loadRun(); }, []));

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
    if (saving) return;
    if (!cName.trim() || !cPhone.trim()) { Alert.alert('이름과 전화번호를 입력해주세요'); return; }
    setSaving(true);
    try {
      await addEmergencyContact(cName.trim(), cPhone.trim());
      setCName(''); setCPhone(''); setAdding(false);
      load();
    } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
    finally { setSaving(false); }
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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top, paddingBottom: 24 }}>
        {/* Chrome header (DESIGN.md §3b). The 30/900 display title, its subtitle and the green
            shield chip retired together: a pushed sub-screen wears the shared 23/900 header, the
            subtitle restated the title (§7a-bis), and the chip was decoration painted in the
            personal-signal colour (DESIGN.md §5). */}
        <ScreenHead title="안심 센터" />

        {/* ---------- SOS (실동작) ---------- */}
        <Pressable
          style={({ pressed }) => [s.sosCard, pressed ? s.sosDown : s.sosLip]}
          onPress={sos}
          accessibilityRole="button"
        >
          <Icon name="Siren" glyph="✚" size={28} color="#fff" />
          <View style={{ flex: 1, marginLeft: 14 }}>
            <Text style={{ fontSize: 18.5, fontWeight: '900', color: '#fff' }}>SOS 긴급 알림</Text>
            {/* ⚠ White, not a tinted salmon. `#ffd9cf` on this ground measured 2.97:1 — below the
                4.5 floor — and the sentence carrying it is 「위급 시엔 112·119가 항상 우선이에요」,
                the single most important line on the screen. White on the tokenized ground
                (paper.action) measures 4.84:1, the value theme.ts:182 already records. */}
            <Text style={{ fontSize: 15, color: '#fff', marginTop: 3, lineHeight: 18.5 }}>
              진행 중인 러닝의 상대방에게 즉시 알림{'\n'}위급 시엔 112·119가 항상 우선이에요
            </Text>
          </View>
        </Pressable>
        {/* Secondary keys (PaperBtn). The label says 전화 because the phone icon that carried
            that meaning does not ride on a PaperBtn. */}
        <Row style={{ gap: 10, marginTop: 10 }}>
          <PaperBtn label="112 전화" variant="secondary" onPress={() => Linking.openURL('tel:112')} style={{ flex: 1 }} />
          <PaperBtn label="119 전화" variant="secondary" onPress={() => Linking.openURL('tel:119')} style={{ flex: 1 }} />
        </Row>

        {/* ---------- 긴급 연락처 (실CRUD) ---------- */}
        <View style={s.rule} />
        <Text style={s.section}>긴급 연락처</Text>
        {/* Failure, loading and genuine-empty are three different sentences. Only the last one
            may claim the roster is empty. */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>연락처를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={s.retryTxt}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {!loadErr && contacts === null && (
          <Text style={s.quiet}>불러오는 중…</Text>
        )}
        {contacts?.length === 0 && !adding && (
          <Text style={s.quiet}>아직 없어요 — 위급 시 연락할 가족·지인을 등록해두세요</Text>
        )}
        {(contacts ?? []).map((c, i) => (
          <View key={c.id}>
            {i > 0 && <View style={s.div} />}
            <Row style={{ paddingVertical: 10 }}>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>{c.name}</Text>
                <Text style={{ fontSize: 15, color: paper.dim, marginTop: 2 }}>{c.phone}</Text>
              </View>
              {/* Every row says 전화 and 삭제, so the label carries the name — otherwise
                  VoiceOver reads the same two words for every contact. */}
              <Pressable
                onPress={() => Linking.openURL(`tel:${c.phone}`)}
                style={({ pressed }) => [s.miniBtn, pressed && s.miniDown]}
                accessibilityRole="button"
                accessibilityLabel={`${c.name}에게 전화`}
              >
                <Text style={[s.miniTxt, { color: paper.actionInk }]}>전화</Text>
              </Pressable>
              <Pressable
                onPress={() => removeContact(c)}
                style={({ pressed }) => [s.miniBtn, { marginLeft: 6 }, pressed && s.miniDown]}
                accessibilityRole="button"
                accessibilityLabel={`${c.name} 삭제`}
              >
                <Text style={[s.miniTxt, { color: paper.critical }]}>삭제</Text>
              </Pressable>
            </Row>
          </View>
        ))}
        {adding ? (
          <View style={{ marginTop: 8, gap: 8 }}>
            <TextInput value={cName} onChangeText={setCName} placeholder="이름 (예: 엄마)" placeholderTextColor={paper.dim} style={s.input} maxLength={12} textContentType="name" autoComplete="name" autoCorrect={false} editable={!saving} />
            <TextInput value={cPhone} onChangeText={setCPhone} placeholder="전화번호" placeholderTextColor={paper.dim} style={s.input} keyboardType="phone-pad" maxLength={15} textContentType="telephoneNumber" autoComplete="tel" editable={!saving} />
            <Row style={{ gap: 8, alignItems: 'flex-start' }}>
              <PaperBtn label="저장" busyLabel="저장 중…" busy={saving} onPress={saveContact} style={{ flex: 1.4 }} />
              <PaperBtn label="취소" variant="quiet" disabled={saving} onPress={() => setAdding(false)} style={{ flex: 1 }} />
            </Row>
          </View>
        ) : (
          <PaperBtn label="＋ 연락처 추가" variant="secondary" onPress={() => setAdding(true)} style={{ marginTop: 8 }} />
        )}

        {/* ---------- 보험·안전 안내 (정보성) ---------- */}
        <View style={s.rule} />
        <Text style={s.section}>안전 체계</Text>
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

        {/* ---------- 사고 신고 (0094 ⑪ — 서버는 진작 있었고 화면이 없었다) ---------- */}
        <View style={s.rule} />
        <Row style={{ gap: 10, marginTop: 14, alignItems: 'stretch' }}>
          {/* 접수할 러닝이 없거나 아직 모르는 동안에는 **버튼이 아니다** — 목적지가 없는 문을
              그리지 않는다. 실패는 다시 눌러볼 값이 있으므로 그때만 눌린다. */}
          {runState === 'found' && run ? (
            <Pressable
              style={s.tile}
              onPress={() => router.push(`/incident/${run.bookingId}`)}
              accessibilityRole="button"
            >
              <Text style={s.tileTitle}>사고 신고</Text>
              <Text style={{ fontSize: 15, color: paper.text, marginTop: 3 }}>
                {run.dogName ? `${run.dogName} · ` : ''}{run.dateLabel} ›
              </Text>
            </Pressable>
          ) : runState === 'error' ? (
            <Pressable style={s.tile} onPress={loadRun} accessibilityRole="button">
              <Text style={s.tileTitle}>사고 신고</Text>
              <Text style={{ fontSize: 15, color: paper.critical, fontWeight: '700', marginTop: 3 }}>
                불러오지 못했어요 · 다시 시도
              </Text>
            </Pressable>
          ) : (
            <View style={s.tile}>
              <Text style={s.tileTitle}>사고 신고</Text>
              <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3 }}>
                {runState === 'loading' ? '불러오는 중…' : '접수할 수 있는 러닝이 없어요'}
              </Text>
            </View>
          )}
          {/* ⚠ Owner-only destination. This screen is a quick link from BOTH homes, and
              `/owner/dog` has no role guard of its own — so a runner could land on the owner's dog
              screen and create a real `dogs` row from its empty state. The row is still rendered
              for a runner (the information is true for them too: medical notes live on the owner's
              dog profile), it simply stops being a door into an owner-only write surface. */}
          {session.role === 'runner' ? (
            <View style={s.tile}>
              <Text style={s.tileTitle}>의료·성향 메모</Text>
              <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3 }}>보호자가 등록한 내용을 러닝 화면에서 볼 수 있어요</Text>
            </View>
          ) : (
            <Pressable style={s.tile} onPress={() => router.push('/owner/dog')} accessibilityRole="button">
              <Text style={s.tileTitle}>의료·성향 메모</Text>
              <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3 }}>반려견 프로필에서 관리 ›</Text>
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
        <Text style={{ fontSize: 15, color: paper.dim, marginTop: 2, lineHeight: 18.5 }}>{desc}</Text>
      </View>
    </Row>
  );
}

// Paper grammar (DESIGN.md §2 chrome migration · §3b): radius 0 everywhere, sections divided by a
// full-bleed coral rule rather than boxed in cards, neutral #EEE for rows and tiles.
const s = StyleSheet.create({
  // Ground is the TOKEN, not an ad-hoc coral. `#e8492a` was untokenized and too light: white
  // clears only 3.88:1 on it, so nothing this card could print would have passed AA. paper.action
  // carries white at 4.84:1 (measured; theme.ts:182 states the same number).
  sosCard: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: paper.action,
    padding: 18, marginTop: 18,
  },
  // [Sean 2026-08-26 press behaviour] the screen's only filled primary, and the only control here
  // that commits anything. 4px lip at rest, translateY(3) + 1px pressed — the edge gives up
  // exactly what the transform takes, so the bottom of the card never moves. Hand-rolled rather
  // than PaperBtn: this is an icon + two lines of copy, not a label.
  sosLip: { borderBottomWidth: 4, borderBottomColor: paper.actionPressed },
  sosDown: {
    backgroundColor: paper.actionPressed, transform: [{ translateY: 3 }],
    borderBottomWidth: 1, borderBottomColor: paper.actionPressed,
  },
  // full-bleed: the rule escapes the scroll gutter so it runs edge to edge (DESIGN.md §2)
  rule: { height: 1, backgroundColor: paper.line, marginHorizontal: -layout.gutter, marginTop: 24 },
  section: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink, marginTop: 14, marginBottom: 6 }, // → theme.secTitle
  div: { height: 1, backgroundColor: '#EEEEEE' },
  quiet: { fontSize: 15, lineHeight: 21, color: paper.dim, paddingVertical: 6 },
  // quiet-button grammar (paper-btn.tsx): canvas + #EEE, wash when pressed, 44pt target
  miniBtn: {
    minHeight: 44, paddingHorizontal: 14, alignItems: 'center', justifyContent: 'center',
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
  },
  miniDown: { backgroundColor: paper.wash },
  miniTxt: { fontSize: 15, fontWeight: '800' },
  input: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 11, paddingHorizontal: 12, fontSize: 15.5, color: paper.ink,
  },
  // a tile is the interaction itself (DESIGN.md §4: a card must BE the interaction to exist)
  tile: { flex: 1, padding: 14, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' },
  tileTitle: { fontSize: 16, fontWeight: '800', color: paper.ink },
  // loud-fail strip — criticalWash ground, critical ink, underlined retry ≥44pt (house grammar)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 4 },
  failTxt: { fontSize: 15, fontWeight: '700', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
