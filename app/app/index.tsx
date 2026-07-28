import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { Btn } from '../src/components/ui';
import { ensureRunner } from '../src/lib/api';
import { supabase } from '../src/lib/supabase';
import { session } from '../src/store';
import { colors } from '../src/theme';

type Role = 'owner' | 'runner' | null;

export default function RoleSelect() {
  const { session: auth, loading } = useAuth();
  const [role, setRole] = useState<Role>(null);
  const [busy, setBusy] = useState(false);

  // route guard: 로그인 없으면 로그인 화면으로
  useEffect(() => {
    if (!loading && !auth) router.replace('/login');
  }, [loading, auth]);

  const start = async () => {
    if (!role || !auth) return;
    setBusy(true);
    // 프로필 실화: profiles 행 upsert (RLS self-insert)
    const { error } = await supabase.from('profiles').upsert({
      id: auth.user.id,
      role,
      name: auth.user.email?.split('@')[0] ?? '사용자',
    });
    if (error) {
      setBusy(false);
      Alert.alert('프로필 저장 실패', error.message);
      return;
    }
    // 러너 선택 시 runners 행 + 기본 가용시간 확보 (루프 테스트용 즉시 인증)
    if (role === 'runner') {
      try { await ensureRunner(); } catch (e) { console.warn('ensureRunner:', e); }
    }
    setBusy(false);
    session.role = role;
    router.push(role === 'owner' ? '/owner/home' : '/runner/home');
  };

  return (
    <View style={s.root}>
      <View style={s.hero}>
        <Text style={s.big}>
          우리 개는{'\n'}
          <Text style={{ color: colors.cream }}>오늘도</Text>
          {'\n'}달린다
        </Text>
        <Text style={s.sub}>바쁜 당신 대신, 검증된 러너가{'\n'}반려견과 함께 달립니다.</Text>
      </View>

      <View style={{ gap: 12 }}>
        <Pressable
          style={[s.roleCard, { backgroundColor: colors.volt }, role === 'owner' && s.sel]}
          onPress={() => setRole('owner')}
        >
          <Text style={[s.roleTitle, { color: colors.ink }]}>보호자예요</Text>
          <Text style={[s.roleDesc, { color: colors.ink }]}>믿을 수 있는 러너에게 맡겨요</Text>
        </Pressable>
        <Pressable
          style={[s.roleCard, { backgroundColor: '#1c2b21' }, role === 'runner' && s.sel]}
          onPress={() => setRole('runner')}
        >
          <Text style={[s.roleTitle, { color: colors.volt }]}>러너예요</Text>
          <Text style={[s.roleDesc, { color: colors.cream }]}>달리면서 수익도 얻어요</Text>
        </Pressable>
      </View>

      <Btn
        label={busy ? '저장 중...' : role ? '시작하기' : '역할을 선택하세요'}
        variant="volt"
        disabled={!role || busy}
        onPress={start}
        style={{ marginTop: 20, marginBottom: 24 }}
      />
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.ink, padding: 26, justifyContent: 'flex-end' },
  hero: { marginBottom: 36 },
  big: { fontSize: 64.5, lineHeight: 69, fontWeight: '900', color: colors.volt },
  sub: { marginTop: 16, fontSize: 17, lineHeight: 27.5, color: '#b9b6a4' },
  roleCard: { borderRadius: 18, padding: 16, borderWidth: 2, borderColor: 'transparent' },
  sel: { borderColor: colors.tang },
  roleTitle: { fontSize: 27.5, fontWeight: '800' },
  roleDesc: { fontSize: 15, marginTop: 4, opacity: 0.75 },
});
