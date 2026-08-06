import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { ensureRunner } from '../src/lib/api';
import { supabase } from '../src/lib/supabase';
import { session } from '../src/store';
import { paper } from '../src/theme';

type Role = 'owner' | 'runner';

// 순백/코랄 1호 화면 (2026-08-06) — 볼트 월드 은퇴 시작점.
// Sean 지시: 풀스크린·풀블리드 큰 버튼 둘뿐 — 보호자 위, 러너 아래. 탭 한 번 = 역할 확정 + 시작.
export default function RoleSelect() {
  const { session: auth, loading } = useAuth();
  const [busy, setBusy] = useState<Role | null>(null);

  // route guard: 로그인 없으면 로그인 화면으로
  useEffect(() => {
    if (!loading && !auth) router.replace('/login');
  }, [loading, auth]);

  const start = async (role: Role) => {
    if (busy || !auth) return;
    setBusy(role);
    // 프로필 실화: profiles 행 upsert (RLS self-insert)
    const { error } = await supabase.from('profiles').upsert({
      id: auth.user.id,
      role,
      name: auth.user.email?.split('@')[0] ?? '사용자',
    });
    if (error) {
      setBusy(null);
      Alert.alert('프로필 저장 실패', error.message);
      return;
    }
    // 러너 선택 시 runners 행 + 기본 가용시간 확보 (0057 K-3: applicant 민팅)
    if (role === 'runner') {
      try { await ensureRunner(); } catch (e) { console.warn('ensureRunner:', e); }
    }
    setBusy(null);
    session.role = role;
    router.push(role === 'owner' ? '/owner/home' : '/runner/home');
  };

  return (
    <View style={s.root}>
      <Text style={s.brand}>도그스하이 · DOGS HIGH</Text>

      <Pressable
        style={({ pressed }) => [s.half, pressed && s.pressed]}
        onPress={() => start('owner')}
        disabled={busy != null}
      >
        <Text style={s.kicker}>OWNER</Text>
        <Text style={s.name}>보호자예요</Text>
        <Text style={s.desc}>{busy === 'owner' ? '저장 중...' : '믿을 수 있는 러너에게 맡겨요'}</Text>
      </Pressable>

      <View style={s.divider} />

      <Pressable
        style={({ pressed }) => [s.half, pressed && s.pressed]}
        onPress={() => start('runner')}
        disabled={busy != null}
      >
        <Text style={s.kicker}>RUNNER</Text>
        <Text style={s.name}>러너예요</Text>
        <Text style={s.desc}>{busy === 'runner' ? '저장 중...' : '달리면서 수익도 얻어요'}</Text>
      </Pressable>
    </View>
  );
}

const s = StyleSheet.create({
  // 풀블리드 — 사이드 마진 0, 코랄 라인이 화면 끝까지
  root: { flex: 1, backgroundColor: paper.canvas },
  brand: {
    paddingTop: 64, paddingBottom: 14, textAlign: 'center',
    fontSize: 12, letterSpacing: 3, color: paper.faint, // 장식 클래스 (14pt 플로어 면제 유일 지점)
  },
  half: { flex: 1, justifyContent: 'center', paddingHorizontal: 26 },
  pressed: { backgroundColor: paper.wash },
  divider: { height: 1, backgroundColor: paper.line, alignSelf: 'stretch' },
  kicker: { fontSize: 12, letterSpacing: 3, color: paper.faint, marginBottom: 10 },
  name: { fontSize: 40, lineHeight: 48, fontWeight: '800', color: paper.ink },
  desc: { fontSize: 15.5, lineHeight: 22, fontWeight: '600', color: paper.dim, marginTop: 8 },
});
