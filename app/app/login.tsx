import * as Linking from 'expo-linking';
import { router } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { useEffect, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { useDisplayFont } from '../src/lib/displayFont';
import { supabase } from '../src/lib/supabase';
import { colors } from '../src/theme';

// 로그인 — 이메일 OTP (지금 동작) + 카카오 (provider 설정 후 활성화, backend.md §3).

export default function Login() {
  const { session } = useAuth();
  const df = useDisplayFont(); // 브랜드 워드마크 — 디스플레이 서체 (미설치 시 시스템 900 폴백)
  const [stage, setStage] = useState<'email' | 'otp'>('email');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (session) router.replace('/');
  }, [session]);

  const sendCode = async () => {
    if (!email.includes('@')) return Alert.alert('이메일을 확인해주세요');
    setBusy(true);
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { shouldCreateUser: true },
    });
    setBusy(false);
    if (error) return Alert.alert('전송 실패', error.message);
    setStage('otp');
  };

  const verify = async () => {
    if (code.length < 6) return Alert.alert('6자리 코드를 입력해주세요');
    setBusy(true);
    const { error } = await supabase.auth.verifyOtp({
      email: email.trim(),
      token: code.trim(),
      type: 'email',
    });
    setBusy(false);
    if (error) return Alert.alert('인증 실패', error.message);
    router.replace('/'); // 역할 선택으로
  };

  const kakao = async () => {
    if (busy) return; // 더블탭 가드
    try {
      setBusy(true);
      // 이전 시도의 잔여 세션 정리 ("Another web browser is already open" 방지)
      // iOS에서는 void 반환 — promise 아님
      try { WebBrowser.dismissAuthSession(); } catch { /* no-op */ }
      const redirectTo = Linking.createURL('login'); // Expo Go: exp://IP:8081/--/login · prod: daengrun://login
      console.log('[kakao] redirectTo =', redirectTo, '— 이 값이 Supabase Redirect URLs에 있어야 함');
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: 'kakao',
        options: { redirectTo, skipBrowserRedirect: true },
      });
      if (error || !data?.url) throw error ?? new Error('no auth url');

      const res = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
      if (res.type === 'success' && res.url) {
        const code = new URL(res.url).searchParams.get('code');
        if (code) {
          const { error: xErr } = await supabase.auth.exchangeCodeForSession(code);
          if (xErr) throw xErr;
          router.replace('/');
          return;
        }
      }
    } catch (e) {
      Alert.alert(
        '카카오 로그인 실패',
        `${(e as Error)?.message ?? e}\n\nSupabase provider 설정을 확인해주세요 (backend.md §3)`,
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <KeyboardAvoidingView style={s.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={{ flex: 1, justifyContent: 'center' }}>
        <Text style={[s.logo, df]}>도그스<Text style={{ color: colors.volt }}>하이</Text></Text>
        <Text style={s.tagline}>러너스 하이를, 우리 아이에게</Text>

        {stage === 'email' ? (
          <>
            <TextInput
              style={s.input}
              value={email}
              onChangeText={setEmail}
              placeholder="이메일 주소"
              placeholderTextColor="#6d7a68"
              autoCapitalize="none"
              keyboardType="email-address"
              autoComplete="email"
            />
            <Pressable style={[s.primary, busy && { opacity: 0.5 }]} disabled={busy} onPress={sendCode}>
              <Text style={s.primaryText}>{busy ? '전송 중...' : '인증 코드 받기'}</Text>
            </Pressable>
          </>
        ) : (
          <>
            <Text style={s.otpHint}>{email}로 보낸 6자리 코드를 입력해주세요</Text>
            <TextInput
              style={[s.input, { textAlign: 'center', fontSize: 27.5, letterSpacing: 8 }]}
              value={code}
              onChangeText={setCode}
              placeholder="······"
              placeholderTextColor="#6d7a68"
              keyboardType="number-pad"
              maxLength={6}
              autoFocus
            />
            <Pressable style={[s.primary, busy && { opacity: 0.5 }]} disabled={busy} onPress={verify}>
              <Text style={s.primaryText}>{busy ? '확인 중...' : '로그인'}</Text>
            </Pressable>
            <Pressable style={{ alignItems: 'center', padding: 12 }} onPress={() => setStage('email')}>
              <Text style={{ fontSize: 14.5, color: '#8fa093' }}>이메일 다시 입력</Text>
            </Pressable>
          </>
        )}

        <View style={s.divider}>
          <View style={s.divLine} />
          <Text style={{ fontSize: 14, color: '#6d7a68' }}>또는</Text>
          <View style={s.divLine} />
        </View>

        <Pressable style={s.kakao} onPress={kakao}>
          <Text style={{ fontSize: 17, fontWeight: '800', color: '#191919' }}>카카오로 3초 만에 시작하기</Text>
        </Pressable>

        <Text style={s.legal}>
          로그인하면 이용약관과 개인정보 처리방침에 동의하게 돼요
        </Text>
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.ink, paddingHorizontal: 28 },
  // 아이콘 락업과 동일: 도그스 = 화이트, 하이 = volt (히어로 음절)
  logo: { fontSize: 60, fontWeight: '900', color: '#fff', textAlign: 'center' },
  tagline: { fontSize: 16, color: '#8fa093', textAlign: 'center', marginTop: 6, marginBottom: 40 },
  input: {
    backgroundColor: '#1a231a', borderRadius: 16, borderWidth: 1, borderColor: '#2c3a2c',
    paddingHorizontal: 18, paddingVertical: 16, fontSize: 18.5, color: colors.cream,
  },
  otpHint: { fontSize: 15, color: colors.cream, textAlign: 'center', marginBottom: 14 },
  primary: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 17, marginTop: 12 },
  primaryText: { fontSize: 18.5, fontWeight: '900', color: colors.ink },
  divider: { flexDirection: 'row', alignItems: 'center', gap: 12, marginVertical: 26 },
  divLine: { flex: 1, height: 1, backgroundColor: '#2c3a2c' },
  kakao: { backgroundColor: '#FEE500', borderRadius: 16, alignItems: 'center', paddingVertical: 17 },
  legal: { fontSize: 14, color: '#5d6b5d', textAlign: 'center', marginTop: 24, lineHeight: 18 },
});
