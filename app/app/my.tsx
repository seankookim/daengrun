import { useDisplayFont } from '../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { BottomNav } from '../src/components/bottomnav';
import { Avatar, Row } from '../src/components/ui';
import { fetchFitness, fetchMyRunnerStatus } from '../src/lib/api';
import { fetchMyProfile, fetchMyRunnerBio, MyProfile, updateMyProfile, updateRunnerBio, uploadAvatar } from '../src/lib/api';
import { dog, session } from '../src/store';
import { colors } from '../src/theme';

// 마이 — 실프로필 (사진·이름·동네). 김민준은 은퇴했다.

const FOREST = '#0F1D13';

export default function My() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const isRunner = session.role === 'runner';
  // 나의 러닝 기록 — 실데이터 (보호자: fitness 집계 / 러너: 누적 스탯)
  const [rec, setRec] = useState<{ km: number; runs: number; pace: string } | null>(null);
  useEffect(() => {
    if (isRunner) {
      fetchMyRunnerStatus().then((r: any) => setRec({ km: r.totalKm ?? 0, runs: r.totalRuns ?? 0, pace: r.paceLabel ?? '—' })).catch(() => {});
    } else {
      fetchFitness().then((f: any) => setRec({
        km: f.totalKm ?? f.weekKm ?? 0, runs: f.totalRuns ?? f.weekRuns ?? 0,
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
    { glyph: '✚', label: '안심 센터', desc: 'SOS · 긴급 연락처 · 보험', path: '/safety' as const },
    isRunner
      ? { glyph: '✓', label: '러너 인증 센터', desc: '지원 절차 · 등급 사다리 · 교육', path: '/runner/apply' as const }
      : { glyph: '⌂', label: '주소 관리', desc: '픽업 장소 · 공동현관 정보', path: '/owner/addresses' as const },
    ...(!isRunner ? [{ glyph: '◉', label: '반려견 프로필', desc: '사진 · 성향 · 러너에게 전달되는 정보', path: '/owner/dog' as const }] : []),
    { glyph: '▦', label: '예약 관리', desc: '다가오는 일정과 지난 예약', path: isRunner ? null : ('/owner/schedule' as const) },
    { glyph: '⌗', label: isRunner ? '내 러닝 기록' : `${dog.name}의 기록`, desc: '마이 카드 · 러닝 히스토리', path: '/cards' as const },
    { glyph: '◔', label: '알림', desc: '알림 확인 및 설정', path: '/alerts' as const },
    { glyph: '⚙', label: '설정', desc: '계정 · 로그아웃 · 문의', path: '/settings' as const },
  ];

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 64, paddingBottom: 24 }}>
        <Text style={[s.h1, df]}>마이</Text>

        {/* profile header — 실데이터 */}
        <View style={s.profile}>
          <Pressable onPress={pickPhoto} disabled={uploading}>
            <Avatar url={profile?.avatarUrl} char={(profile?.name ?? '나')[0]} bg={isRunner ? '#FF5C3D' : colors.volt} size={56} />
            <View style={s.camBadge}><Text style={{ fontSize: 10.5, color: '#fff' }}>{uploading ? '…' : '✎'}</Text></View>
          </Pressable>
          <View style={{ flex: 1, marginLeft: 14 }}>
            <Text style={{ fontSize: 19.5, fontWeight: '900', color: FOREST }}>
              {profile?.name ?? '...'} {isRunner ? '러너' : '보호자님'}
            </Text>
            <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>
              {profile?.district ? `${profile.district} · ` : ''}{isRunner ? '신원인증 · 펫보험 가입' : `${dog.name} · ${dog.breed}`}
            </Text>
          </View>
          <Pressable
            style={s.editBtn}
            onPress={() => {
              // 프로필 편집 단일화 — 러너는 스토어프런트에서, 보호자는 여기 시트에서 (혼선 제거)
              if (isRunner) {
                if (profile) router.push(`/runner-profile/${profile.id}`);
              } else {
                openEdit();
              }
            }}
          >
            <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#3d453d' }}>{isRunner ? '프로필 편집 ›' : '프로필 설정'}</Text>
          </Pressable>
        </View>
        <Text style={{ fontSize: 14, color: colors.dim, marginTop: 6, marginLeft: 4 }}>
          사진을 탭하면 프로필 사진을 바꿀 수 있어요
        </Text>

        {/* 나의 러닝 기록 — 다크 앵커 카드 (실데이터, 모던 목업) */}
        <Pressable
          onPress={() => router.push(isRunner ? '/runner/home' : '/owner/fitness')}
          style={{ backgroundColor: FOREST, borderRadius: 18, padding: 16, marginTop: 12 }}
        >
          <Text style={{ fontSize: 15, fontWeight: '800', color: '#b8c4ae' }}>나의 러닝 기록</Text>
          <View style={{ flexDirection: 'row', marginTop: 12 }}>
            {[
              { v: (rec?.km ?? 0).toFixed(1), u: ' km', l: '총 거리' },
              { v: `${rec?.runs ?? 0}`, u: ' 회', l: '총 횟수' },
              { v: rec?.pace ?? '—', u: '', l: '평균 페이스' },
            ].map((c) => (
              <View key={c.l} style={{ flex: 1 }}>
                <Text style={{ fontSize: 22, fontWeight: '900', color: '#fff' }}>
                  {c.v}<Text style={{ fontSize: 14.5, color: '#8fa093' }}>{c.u}</Text>
                </Text>
                <Text style={{ fontSize: 13, color: '#8fa093', marginTop: 3 }}>{c.l}</Text>
              </View>
            ))}
          </View>
          <Text style={{ fontSize: 12.5, fontWeight: '800', color: colors.volt, textAlign: 'right', marginTop: 10 }}>상세 기록 보기 ›</Text>
        </Pressable>

        {/* menu */}
        <View style={{ gap: 10, marginTop: 12 }}>
          {MENU.map((m) => (
            <Pressable
              key={m.label}
              style={s.menuRow}
              onPress={() => {
                if (m.path) router.push(m.path);
                else Alert.alert(m.label, '준비 중이에요');
              }}
            >
              <View style={s.menuIcon}><Text style={{ fontSize: 17, color: '#5a7a3c' }}>{m.glyph}</Text></View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 16.5, fontWeight: '800', color: FOREST }}>{m.label}</Text>
                <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>{m.desc}</Text>
              </View>
              <Text style={{ fontSize: 18.5, color: colors.dim }}>›</Text>
            </Pressable>
          ))}
        </View>

        <Pressable style={s.roleSwitch} onPress={() => router.dismissTo('/')}>
          <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#49524a' }}>역할 전환 (보호자 ↔ 러너)</Text>
        </Pressable>
        <Pressable
          style={s.roleSwitch}
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
        >
          <Text style={{ fontSize: 14.5, fontWeight: '700', color: '#d84a2f' }}>
            로그아웃{auth?.user.email ? ` (${auth.user.email})` : ''}
          </Text>
        </Pressable>
      </ScrollView>
      <BottomNav />

      {/* ---------- 프로필 편집 시트 ---------- */}
      <Modal visible={editing} transparent animationType="slide" onRequestClose={() => setEditing(false)}>
        <Pressable style={s.backdrop} onPress={() => setEditing(false)} />
        <View style={s.sheet}>
          <View style={s.handle} />
          <Text style={{ fontSize: 22, fontWeight: '900', color: FOREST }}>프로필 설정</Text>

          <Text style={s.fieldLabel}>이름</Text>
          <TextInput
            value={name}
            onChangeText={setName}
            placeholder="이름 또는 닉네임"
            placeholderTextColor="#b0ada0"
            style={s.input}
            maxLength={20}
          />
          <Text style={s.fieldLabel}>활동 동네</Text>
          <TextInput
            value={district}
            onChangeText={setDistrict}
            placeholder="예: 반포동"
            placeholderTextColor="#b0ada0"
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
                placeholderTextColor="#b0ada0"
                style={[s.input, { height: 96, textAlignVertical: 'top', paddingTop: 12 }]}
                multiline
                maxLength={300}
              />
            </>
          )}
          <Text style={{ fontSize: 14, color: colors.dim, marginTop: 8, lineHeight: 17 }}>
            이름과 동네는 매칭 화면에서 상대방에게 보여요{'\n'}프로필 사진은 마이 화면에서 사진을 탭해 변경해요
          </Text>

          <Pressable onPress={save} disabled={saving} style={[s.saveBtn, saving && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{saving ? '저장 중...' : '저장'}</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  h1: { fontSize: 30, fontWeight: '900', color: FOREST }, // 표준 탭 헤더 사이즈
  profile: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff',
    borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#DCD6C4', marginTop: 16,
  },
  camBadge: {
    position: 'absolute', right: -3, bottom: -3, width: 18, height: 18, borderRadius: 9,
    backgroundColor: '#5a7a3c', alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: '#fff',
  },
  editBtn: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 11 },
  menuRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#DCD6C4',
  },
  menuIcon: { width: 40, height: 40, borderRadius: 12, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  roleSwitch: { alignItems: 'center', marginTop: 20, padding: 12 },
  backdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 16, paddingBottom: 40 },
  handle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#DCD6C4', marginBottom: 14 },
  fieldLabel: { fontSize: 14, fontWeight: '800', color: '#3d453d', marginTop: 14, marginBottom: 6 },
  input: {
    backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4',
    paddingVertical: 12, paddingHorizontal: 14, fontSize: 16.5, color: FOREST,
  },
  saveBtn: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14, marginTop: 18 },
});
