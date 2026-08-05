import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import { useAuth } from '../src/auth-context';
import { BottomNav } from '../src/components/bottomnav';
import { Avatar, Row } from '../src/components/ui';
import { fetchFitness, fetchMyRunnerStatus } from '../src/lib/api';
import { fetchMyProfile, fetchMyRunnerBio, MyProfile, updateMyProfile, updateRunnerBio, uploadAvatar } from '../src/lib/api';
import { dog, session } from '../src/store';
import { colors, lilac, lilacRadius, lilacShadow } from '../src/theme';

// 마이 — 여권(PASSPORT) 리페인트. 신분면(이중 프레임·MRZ)·기록면(나이트 라일락)·서류행.
// 로직 동결: 실프로필(사진·이름·동네)·MENU 라우팅·편집 시트·아바타 업로드는 원본 그대로.
// 코랄은 텍스트로 쓰지 않는다 — 필/엣지/도트(홀로 엣지·씰·틱)로만. 배지 = coralSoft + head 잉크.

// 홀로 엣지 (여권 각인 · 티켓 엣지 문법) — 코랄이 텍스트가 아닌 엣지로만 등장
const HOLO = ['#CFC5F6', '#FFDCD1', '#F3E9C6', '#EAF6C8', '#CDEAF3', '#CFC5F6'];
function HoloEdge({ height = 3, opacity = 1 }: { height?: number; opacity?: number }) {
  return (
    <Svg width="100%" height={height} style={{ position: 'absolute', top: 0, left: 0, right: 0, opacity }} pointerEvents="none">
      <Defs>
        <LinearGradient id="holo" x1="0" y1="0" x2="1" y2="0">
          {HOLO.map((c, i) => (
            <Stop key={i} offset={`${i / (HOLO.length - 1)}`} stopColor={c} />
          ))}
        </LinearGradient>
      </Defs>
      <Rect x="0" y="0" width="100%" height={height} fill="url(#holo)" />
    </Svg>
  );
}

export default function My() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀 (화면당 1회)
  const nf = useNumFont();     // [V4] Oswald — 숫자·마이크로캡 라벨
  const isRunner = session.role === 'runner';
  // 나의 러닝 기록 — 실데이터 (러너: 서버 누적 스탯 / 보호자: 이번 주 집계)
  // [정직 수리 2026-08-05] Fitness에는 totalKm/totalRuns가 존재한 적 없다 — f:any가 가리던 채로
  // 주간 수치가 '총 거리/총 횟수'로 표기되던 P1. 보호자는 주간 수치를 주간 라벨로 말한다.
  // 실누적은 리워드 ② 구현에서 실카운트 쿼리와 함께 온다.
  const [rec, setRec] = useState<{ km: number; runs: number; pace: string } | null>(null);
  useEffect(() => {
    if (isRunner) {
      fetchMyRunnerStatus().then((r: any) => setRec({ km: r.totalKm ?? 0, runs: r.totalRuns ?? 0, pace: r.paceLabel ?? '—' })).catch(() => {});
    } else {
      fetchFitness().then((f) => setRec({
        km: f.weekKm ?? 0, runs: f.weekRuns ?? 0,
        pace: f.avgPaceSec ? `${Math.floor(f.avgPaceSec / 60)}'${String(f.avgPaceSec % 60).padStart(2, '0')}"` : '—',
      })).catch(() => {});
    }
  }, [isRunner]);
  const { session: auth, signOut } = useAuth();
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState('');
  const [district, setDistrict] = useState('');
  const [bio, setBio] = useState('');
  const [savedBio, setSavedBio] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);

  useFocusEffect(useCallback(() => {
    fetchMyProfile().then(setProfile).catch((e) => console.warn('[my] profile:', e?.message ?? e));
    if (isRunner) fetchMyRunnerBio().then(setSavedBio).catch(() => {});
  }, [isRunner]));

  const openEdit = () => {
    setName(profile?.name ?? '');
    setDistrict(profile?.district ?? '');
    setBio(savedBio ?? '');
    setEditing(true);
  };

  const pickPhoto = async () => {
    // 지연 로드 — 네이티브 모듈이 없는 빌드(구 dev build/Expo Go)에서 앱 전체가 죽지 않게.
    // 상단 import는 라우터의 라우트 스캔 단계에서 앱을 통째로 크래시시킨다 (2026-07-23).
    let ImagePicker: any;
    try {
      ImagePicker = require('expo-image-picker');
    } catch {
      Alert.alert('개발 빌드 업데이트 필요', '프로필 사진 기능은 새 빌드에 포함돼요\n터미널에서: npx expo run:ios');
      return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'], allowsEditing: true, aspect: [1, 1], quality: 0.6, base64: true,
      });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploading(true);
      const url = await uploadAvatar(res.assets[0].base64);
      setProfile((p) => (p ? { ...p, avatarUrl: url } : p));
    } catch (e) {
      Alert.alert('업로드 실패', (e as Error).message);
    } finally {
      setUploading(false);
    }
  };

  const save = async () => {
    setSaving(true);
    try {
      await updateMyProfile({ name: name.trim() || undefined, district: district.trim() || undefined });
      if (isRunner) {
        await updateRunnerBio(bio.trim());
        setSavedBio(bio.trim());
      }
      setProfile((p) => (p ? { ...p, name: name.trim() || p.name, district: district.trim() || p.district } : p));
      setEditing(false);
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  const MENU = [
    { glyph: '✚', label: '안심 센터', desc: 'SOS · 긴급 연락처 · 보험', path: '/safety' as const, ink: colors.tang, tint: '#FCE7E1' },
    isRunner
      ? { glyph: '✓', label: '러너 인증 센터', desc: '지원 절차 · 등급 사다리 · 교육', path: '/runner/apply' as const, ink: colors.voltDeep, tint: '#EDF5D8' }
      : { glyph: '⌂', label: '주소 관리', desc: '픽업 장소 · 공동현관 정보', path: '/owner/addresses' as const, ink: colors.voltDeep, tint: '#EDF5D8' },
    ...(!isRunner ? [{ glyph: '◉', label: '반려견 프로필', desc: '사진 · 성향 · 러너에게 전달되는 정보', path: '/owner/dog' as const, ink: colors.terra, tint: colors.terraTint }] : []),
    { glyph: '▦', label: '예약 관리', desc: '다가오는 일정과 지난 예약', path: isRunner ? null : ('/owner/schedule' as const), ink: '#4A6E93', tint: '#E3EEF8' },
    { glyph: '⌗', label: isRunner ? '내 러닝 기록' : `${dog.name}의 기록`, desc: '마이 카드 · 러닝 히스토리', path: '/cards' as const, ink: colors.goldDeep, tint: colors.goldTint },
    { glyph: '◔', label: '알림', desc: '알림 확인 및 설정', path: '/alerts' as const, ink: colors.clubInk, tint: colors.clubTint },
    { glyph: '⚙', label: '설정', desc: '계정 · 로그아웃 · 문의', path: '/settings' as const, ink: '#586055', tint: '#EFF1EC' },
  ];

  // 신분면 필드 값 (원본 subtitle과 동일 바인딩 — 활동 동네 · 반려견/인증)
  const districtLine = `${profile?.district ? `${profile.district} · ` : ''}${isRunner ? '신원인증 · 펫보험 가입' : `${dog.name} · ${dog.breed}`}`;
  const passportType = isRunner ? 'RUNNER' : 'OWNER';
  const docNo = profile?.id ? profile.id.replace(/-/g, '').slice(0, 8).toUpperCase() : null;

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 64, paddingBottom: 24 }}>

        {/* ————— 마스트헤드 (에디토리얼 키커 + Black Han Sans 타이틀) ————— */}
        <Row style={s.kicker}>
          <Text style={[s.kickerTxt, nf]}>DOGS HIGH · MEMBER</Text>
          <View style={s.rule} />
          <Text style={[s.kickerTxt, nf]}>KOR</Text>
        </Row>
        <Row style={{ alignItems: 'flex-start', gap: 10 }}>
          <Text style={[s.h1, df]}>마이</Text>
          <View style={s.official}><Text style={[s.officialTxt, nf]}>PASSPORT</Text></View>
        </Row>
        <Text style={s.subNote}>이 화면은 내 여권이에요 — 신분면 · 기록면 · 서류가 한 권에 있어요</Text>

        {/* ————— ① 신분면 — 이중 프레임 + MRZ ————— */}
        <View style={s.idcard}>
          <HoloEdge height={3} />
          <View style={s.idInner}>
            <Row style={s.idStrap}>
              <Text style={[s.microK, nf]}>IDENTITY / 신분면</Text>
              <View style={s.roleTag}><Text style={[s.roleTagTxt, nf]}>{isRunner ? '러너' : '보호자'}</Text></View>
            </Row>

            <Row style={{ alignItems: 'flex-start', gap: 12 }}>
              {/* 사진 창 — 탭하면 프로필 사진 변경 (uploadAvatar) */}
              <Pressable onPress={pickPhoto} disabled={uploading} style={s.photoWin}>
                <Avatar url={profile?.avatarUrl} char={(profile?.name ?? '나')[0]} bg={lilac.accent} size={56} />
                <View style={s.cam}><Text style={{ fontSize: 14, color: '#fff' }}>{uploading ? '…' : '✎'}</Text></View>
              </Pressable>

              <View style={{ flex: 1, minWidth: 0 }}>
                <View style={s.fld}>
                  <Text style={[s.fldK, nf]}>NAME / 이름</Text>
                  <Text style={s.fldV}>
                    {profile?.name ?? '...'} <Text style={s.fldVSmall}>{isRunner ? '러너' : '보호자님'}</Text>
                  </Text>
                </View>
                <View style={s.fld}>
                  <Text style={[s.fldK, nf]}>DISTRICT / 활동 동네</Text>
                  <Text style={s.fldV2}>{districtLine}</Text>
                </View>
                <Pressable
                  style={s.idEdit}
                  onPress={() => {
                    // 프로필 편집 단일화 — 러너는 스토어프런트에서, 보호자는 여기 시트에서 (혼선 제거)
                    if (isRunner) {
                      if (profile) router.push(`/runner-profile/${profile.id}`);
                    } else {
                      openEdit();
                    }
                  }}
                >
                  <Text style={s.idEditTxt}>{isRunner ? '프로필 편집' : '프로필 설정'}</Text>
                  <Text style={[s.idEditEm, nf]}>EDIT ›</Text>
                </Pressable>
              </View>
            </Row>

            {/* 신분면 그리드 — Type(역할 실데이터) · No.(프로필 id 파생) */}
            <Row style={s.idGrid}>
              <View style={s.idCell}>
                <Text style={[s.gridK, nf]}>TYPE</Text>
                <Text style={[s.gridV, nf]}>P · {passportType}</Text>
              </View>
              {docNo && (
                <View style={[s.idCell, s.idCellDiv]}>
                  <Text style={[s.gridK, nf]}>NO.</Text>
                  <Text style={[s.gridV, nf]}>DH-{docNo}</Text>
                </View>
              )}
            </Row>
          </View>

          {/* MRZ 스트립 — 순수 장식 (aria-safe, 실데이터 없음) */}
          <View
            style={s.mrz}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
            pointerEvents="none"
          >
            <Text style={[s.mrzTxt, nf]} numberOfLines={1}>P&lt;KOR&lt;DOGSHIGH&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;</Text>
            <Text style={[s.mrzTxt, nf]} numberOfLines={1}>{passportType}&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;</Text>
          </View>
        </View>
        <Row style={s.photoHint}>
          <View style={s.photoHintDot}><Text style={{ fontSize: 9, color: lilac.head }}>✎</Text></View>
          <Text style={{ fontSize: 14, color: lilac.dim, flex: 1 }}>사진을 탭하면 프로필 사진을 바꿀 수 있어요</Text>
        </Row>

        {/* ————— ② 기록면 — 나이트 라일락 앵커 (실데이터) ————— */}
        <Pressable
          onPress={() => router.push(isRunner ? '/runner/home' : '/owner/fitness')}
          style={s.record}
        >
          <HoloEdge height={2} opacity={0.85} />
          <View style={s.recordInner}>
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff' }}>나의 러닝 기록</Text>
              <Row style={{ alignItems: 'center', gap: 5 }}>
                <View style={s.coralDot} />
                <Text style={[s.recordKick, nf]}>RECORD / 기록면</Text>
              </Row>
            </Row>
            <Row>
              {[
                { v: (rec?.km ?? 0).toFixed(1), u: ' km', l: isRunner ? '총 거리' : '이번 주 거리', div: false },
                { v: `${rec?.runs ?? 0}`, u: ' 회', l: isRunner ? '총 횟수' : '이번 주 횟수', div: true },
                { v: rec?.pace ?? '—', u: '', l: isRunner ? '평균 페이스' : '주간 페이스', div: true },
              ].map((c) => (
                <View key={c.l} style={[{ flex: 1 }, c.div && s.recDiv]}>
                  <Text style={[s.recN, nf]}>
                    {c.v}<Text style={s.recU}>{c.u}</Text>
                  </Text>
                  <Text style={s.recL}>{c.l}</Text>
                </View>
              ))}
            </Row>
            <View style={s.recGoWrap}>
              <Text style={s.recGo}>상세 기록 보기 ›</Text>
            </View>
          </View>
        </Pressable>

        {/* ————— ④ 서류행 — 헤어라인 문서 목록 (MENU 동결) ————— */}
        <Row style={s.sec}>
          <Text style={[s.secNo, nf]}>§</Text>
          <Text style={[s.secT, nf]}>DOCUMENTS</Text>
          <Text style={s.secKo}>서류</Text>
          <View style={s.rule} />
        </Row>
        <View style={s.doc}>
          {MENU.map((m, i) => (
            <Pressable
              key={m.label}
              style={[s.drow, i > 0 && s.drowDiv]}
              onPress={() => {
                if (m.path) router.push(m.path);
                else Alert.alert(m.label, '준비 중이에요');
              }}
            >
              {/* 도메인 잉크 — 좌측 액센트 틱 + 틴트 아이콘 칩 */}
              <View style={[s.drowTick, { backgroundColor: (m as any).ink }]} />
              <View style={[s.drowIcon, { backgroundColor: (m as any).tint }]}>
                <Text style={{ fontSize: 14, color: (m as any).ink }}>{m.glyph}</Text>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.drowTitle}>{m.label}</Text>
                <Text style={s.drowDesc}>{m.desc}</Text>
              </View>
              <Text style={{ fontSize: 16, color: lilac.dim }}>›</Text>
            </Pressable>
          ))}
        </View>

        {/* ————— ⑤ 큰 버튼 (여백엔 큰 버튼 — Sean 룰) ————— */}
        <Pressable style={s.btnRole} onPress={() => router.dismissTo('/')}>
          <View>
            <Text style={s.btnRoleTitle}>역할 전환</Text>
            <Text style={[s.btnRoleSub, nf]}>OWNER ↔ RUNNER</Text>
          </View>
          <View style={s.btnRoleSw}><Text style={[s.btnRoleSwTxt, nf]}>보호자 ↔ 러너</Text></View>
        </Pressable>

        <Pressable
          style={s.signout}
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
        >
          <View style={s.signoutTick} />
          <View style={{ flex: 1 }}>
            <Text style={s.signoutTitle}>로그아웃</Text>
            {auth?.user.email ? <Text style={s.signoutSub}>{auth.user.email}</Text> : null}
          </View>
          <Text style={{ fontSize: 15, color: lilac.dim }}>›</Text>
        </Pressable>

        {/* ————— ⑥ 콜로폰 (브랜드 워드마크 — 정적 브랜딩) ————— */}
        <View style={s.colophon}>
          <Text style={[s.colophonTxt, nf]}>도그스하이 · DOGS HIGH</Text>
        </View>
      </ScrollView>
      <BottomNav />

      {/* ---------- 프로필 편집 시트 ---------- */}
      <Modal visible={editing} transparent animationType="slide" onRequestClose={() => setEditing(false)}>
        <Pressable style={s.backdrop} onPress={() => setEditing(false)} />
        <View style={s.sheet}>
          <View style={s.handle} />
          <Text style={{ fontSize: 22, fontWeight: '900', color: lilac.head }}>프로필 설정</Text>

          <Text style={s.fieldLabel}>이름</Text>
          <TextInput
            value={name}
            onChangeText={setName}
            placeholder="이름 또는 닉네임"
            placeholderTextColor="#A9A3C4"
            style={s.input}
            maxLength={20}
          />
          <Text style={s.fieldLabel}>활동 동네</Text>
          <TextInput
            value={district}
            onChangeText={setDistrict}
            placeholder="예: 반포동"
            placeholderTextColor="#A9A3C4"
            style={s.input}
            maxLength={20}
          />
          {isRunner && (
            <>
              <Text style={s.fieldLabel}>자기소개 (스토어프런트)</Text>
              <TextInput
                value={bio}
                onChangeText={setBio}
                placeholder="보호자에게 보여줄 소개를 적어보세요 — 러닝 경력, 반려견 경험, 나의 강점"
                placeholderTextColor="#A9A3C4"
                style={[s.input, { height: 96, textAlignVertical: 'top', paddingTop: 12 }]}
                multiline
                maxLength={300}
              />
            </>
          )}
          <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 8, lineHeight: 17 }}>
            이름과 동네는 매칭 화면에서 상대방에게 보여요{'\n'}프로필 사진은 마이 화면에서 사진을 탭해 변경해요
          </Text>

          <Pressable onPress={save} disabled={saving} style={[s.saveBtn, saving && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 16, fontWeight: '800', color: '#fff' }}>{saving ? '저장 중...' : '저장'}</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  // 마스트헤드
  kicker: { alignItems: 'center', gap: 8, marginTop: 6, marginBottom: 8 },
  kickerTxt: { fontSize: 12, letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  rule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  h1: { fontSize: 40, fontWeight: '900', color: lilac.head, lineHeight: 48 },
  official: {
    marginTop: 6, borderWidth: 1, borderColor: lilac.head, borderRadius: 2,
    paddingVertical: 5, paddingHorizontal: 8, backgroundColor: lilac.card,
  },
  officialTxt: { fontSize: 11.5, letterSpacing: 1.8, color: lilac.head, fontWeight: '600' },
  subNote: { fontSize: 14, lineHeight: 21, color: lilac.text, marginTop: 9, marginBottom: 14 },

  // ① 신분면
  idcard: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, overflow: 'hidden', ...lilacShadow,
  },
  idInner: { margin: 9, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner, padding: 12, paddingBottom: 0 },
  idStrap: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 11 },
  microK: { fontSize: 12, letterSpacing: 1.6, color: lilac.dim, textTransform: 'uppercase' },
  roleTag: { borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE', borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9 },
  roleTagTxt: { fontSize: 12, letterSpacing: 1, color: lilac.accent, fontWeight: '600' },
  photoWin: {
    width: 62, height: 74, borderRadius: lilacRadius.inner, borderWidth: 1, borderColor: lilac.hair,
    backgroundColor: lilac.inset, alignItems: 'center', justifyContent: 'center',
  },
  cam: {
    position: 'absolute', right: -6, bottom: 2, width: 22, height: 22, borderRadius: 11,
    backgroundColor: '#C6472C', borderWidth: 1.5, borderColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
  },
  fld: { marginBottom: 8 },
  fldK: { fontSize: 11.5, letterSpacing: 1.2, color: lilac.dim, textTransform: 'uppercase', marginBottom: 4 },
  fldV: { fontSize: 15, fontWeight: '800', color: lilac.head },
  fldVSmall: { fontSize: 14, fontWeight: '600', color: lilac.text },
  fldV2: { fontSize: 14, fontWeight: '600', color: lilac.text, lineHeight: 18 },
  idEdit: {
    marginTop: 2, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset,
    borderRadius: lilacRadius.btn, paddingVertical: 10, paddingHorizontal: 11,
  },
  idEditTxt: { fontSize: 14, fontWeight: '700', color: lilac.head },
  idEditEm: { fontSize: 11.5, letterSpacing: 1.4, color: lilac.accent, textTransform: 'uppercase' },
  idGrid: { marginTop: 10, marginHorizontal: -12, borderTopWidth: 1, borderTopColor: lilac.hair2 },
  idCell: { flex: 1, paddingTop: 9, paddingBottom: 10, paddingLeft: 12 },
  idCellDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2 },
  gridK: { fontSize: 11.5, letterSpacing: 1.2, color: lilac.dim, textTransform: 'uppercase', marginBottom: 3 },
  gridV: { fontSize: 13, letterSpacing: 0.6, color: lilac.head, fontWeight: '600' },
  mrz: { backgroundColor: lilac.inset, borderTopWidth: 1, borderTopColor: lilac.hair2, paddingVertical: 7, paddingHorizontal: 10, gap: 2 },
  mrzTxt: { fontSize: 9, letterSpacing: 0.8, color: '#6E67A0' },
  photoHint: { alignItems: 'center', gap: 6, paddingHorizontal: 3, marginTop: 8 },
  photoHintDot: { width: 16, height: 16, borderRadius: 4, backgroundColor: lilac.coralSoft, alignItems: 'center', justifyContent: 'center' },

  // ② 기록면
  record: {
    backgroundColor: '#1C1837', borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 14,
    shadowColor: '#120E2C', shadowOpacity: 0.34, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  recordInner: { margin: 9, borderWidth: 1, borderColor: 'rgba(255,255,255,0.13)', borderRadius: lilacRadius.inner, padding: 13 },
  coralDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral },
  recordKick: { fontSize: 12, letterSpacing: 1.8, color: 'rgba(255,255,255,0.5)', textTransform: 'uppercase' },
  recDiv: { borderLeftWidth: 1, borderLeftColor: 'rgba(255,255,255,0.13)', paddingLeft: 11 },
  recN: { fontSize: 23, lineHeight: 28, fontWeight: '800', color: '#fff' },
  recU: { fontSize: 14, fontWeight: '500', color: 'rgba(255,255,255,0.55)' },
  recL: { fontSize: 14, color: 'rgba(255,255,255,0.62)', marginTop: 4 },
  recGoWrap: { marginTop: 12, paddingTop: 10, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.13)', alignItems: 'flex-end' },
  recGo: { fontSize: 14, fontWeight: '700', color: '#fff' },

  // 섹션 라벨
  sec: { alignItems: 'center', gap: 8, marginTop: 18, marginBottom: 9, marginHorizontal: 2 },
  secNo: { fontSize: 12, color: lilac.accent, fontWeight: '600' }, // 글리프 전용(§) — 12pt 플로어 면제
  secT: { fontSize: 12, letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  secKo: { fontSize: 14, fontWeight: '700', color: lilac.text },

  // ④ 서류행
  doc: { backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card, overflow: 'hidden', ...lilacShadow },
  drow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 13, paddingRight: 12, backgroundColor: lilac.card },
  drowDiv: { borderTopWidth: 1, borderTopColor: lilac.hair2 },
  drowTick: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3 },
  drowIcon: { width: 27, height: 27, borderRadius: lilacRadius.inner, alignItems: 'center', justifyContent: 'center', marginLeft: 11, marginRight: 10 },
  drowTitle: { fontSize: 14, fontWeight: '700', color: lilac.head },
  drowDesc: { fontSize: 14, color: lilac.dim, marginTop: 2, lineHeight: 18 },

  // ⑤ 큰 버튼
  btnRole: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: lilac.head, borderRadius: lilacRadius.btn, paddingVertical: 16, paddingHorizontal: 15, marginTop: 20,
    shadowColor: '#221E3D', shadowOpacity: 0.28, shadowRadius: 18, shadowOffset: { width: 0, height: 8 }, elevation: 5,
  },
  btnRoleTitle: { fontSize: 15, fontWeight: '800', color: '#fff' },
  btnRoleSub: { fontSize: 12, letterSpacing: 1.8, color: 'rgba(255,255,255,0.7)', textTransform: 'uppercase', marginTop: 3 },
  btnRoleSw: { borderWidth: 1, borderColor: 'rgba(255,255,255,0.35)', borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 10 },
  btnRoleSwTxt: { fontSize: 12, letterSpacing: 1, color: '#fff', fontWeight: '600' },

  signout: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: lilac.card,
    borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.btn, paddingVertical: 13, paddingHorizontal: 12, marginTop: 12,
  },
  signoutTick: { width: 3, height: 30, borderRadius: 2, backgroundColor: lilac.coralDeep },
  signoutTitle: { fontSize: 14, fontWeight: '700', color: lilac.head },
  signoutSub: { fontSize: 14, color: lilac.dim, marginTop: 2 },

  // ⑥ 콜로폰
  colophon: { marginTop: 18, paddingTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair, alignItems: 'center' },
  colophonTxt: { fontSize: 12, letterSpacing: 1.8, color: lilac.dim, textTransform: 'uppercase' },

  // 편집 시트
  backdrop: { flex: 1, backgroundColor: 'rgba(28,24,55,0.34)' },
  sheet: { backgroundColor: lilac.card, borderTopLeftRadius: lilacRadius.card, borderTopRightRadius: lilacRadius.card, padding: 16, paddingBottom: 40 },
  handle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: lilac.hair, marginBottom: 14 },
  fieldLabel: { fontSize: 14, fontWeight: '700', color: lilac.head, marginTop: 14, marginBottom: 6 },
  input: {
    backgroundColor: lilac.inset, borderRadius: lilacRadius.inner, borderWidth: 1, borderColor: lilac.hair,
    paddingVertical: 12, paddingHorizontal: 14, fontSize: 16, color: lilac.head,
  },
  saveBtn: { backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 15, marginTop: 18 },
});
