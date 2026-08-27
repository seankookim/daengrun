import * as Linking from 'expo-linking';
import { router } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { useDisplayFont } from '../src/lib/displayFont';
import { supabase } from '../src/lib/supabase';
import { colors } from '../src/theme';

// 로그인 — **카카오 단일 문** (Sean 2026-08-15 판정 "b", cdb7b06).
//
// ═══ 왜 이메일 문을 지웠는가 ═══
// 이 화면에는 문이 둘 있었다: 카카오 OAuth와 6자리 **이메일** 코드. Sean은 늘 카카오로 가입했고
// 이메일 문은 쓴 적이 없다. 전화/SMS 경로는 **애초에 존재한 적이 없다**(코드는 늘 이메일로 갔다).
// SMS를 새로 만드는 대신 파일럿은 카카오 하나로 간다.
//
// ⚠ 클라이언트에서 문을 치우는 것은 절반이다. 서버가 여전히 이메일 OTP를 받아들이면 그건 앱 밖에
// 열려 있는 가입 경로다 — trust가 그 절반을 검증한다. 둘이 합의할 때까지 제거는 완료가 아니다.
//
// ═══ 문이 하나면 실패의 무게가 달라진다 ═══
// 문이 둘일 때 카카오 실패는 불편이었지만, 지금은 **완전한 잠김**이다. 그래서 실패는
// Alert로 한 번 스치고 사라지지 않고 화면에 남는다: 무슨 일이 났는지 + 다시 시도 + 문의.
// 문의 주소는 설정 화면이 이미 쓰는 실제 주소다 — 없는 창구를 지어내지 않는다.
// 사용자가 브라우저를 직접 닫은 것은 실패가 아니다(취소는 조용히 돌아온다).

const SUPPORT_MAIL = 'mailto:seankookim@uchicago.edu?subject=도그스하이 로그인 문의';

export default function Login() {
  const { session } = useAuth();
  const df = useDisplayFont(); // 브랜드 워드마크 — 디스플레이 서체 (미설치 시 시스템 900 폴백)
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (session) router.replace('/');
  }, [session]);

  const kakao = async () => {
    if (busy) return; // 더블탭 가드
    setErr(null);
    try {
      setBusy(true);
      // 이전 시도의 잔여 세션 정리 ("Another web browser is already open" 방지)
      // iOS에서는 void 반환 — promise 아님
      try { WebBrowser.dismissAuthSession(); } catch { /* no-op */ }
      const redirectTo = Linking.createURL('login'); // Expo Go: exp://IP:8081/--/login · prod: daengrun://login
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: 'kakao',
        options: { redirectTo, skipBrowserRedirect: true },
      });
      if (error || !data?.url) throw error ?? new Error('no auth url');

      const res = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
      // 사용자가 닫은 경우 — 본인의 선택이므로 실패로 말하지 않는다
      if (res.type !== 'success' || !res.url) return;

      const code = new URL(res.url).searchParams.get('code');
      // 성공으로 돌아왔는데 코드가 없으면 그건 조용히 넘길 일이 아니다
      if (!code) throw new Error('카카오가 인증 코드를 돌려주지 않았어요');

      const { error: xErr } = await supabase.auth.exchangeCodeForSession(code);
      if (xErr) throw xErr;
      router.replace('/');
    } catch (e) {
      setErr((e as Error)?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={s.root}>
      <View style={{ flex: 1, justifyContent: 'center' }}>
        <Text style={[s.logo, df]}>도그스<Text style={{ color: colors.volt }}>하이</Text></Text>
        <Text style={s.tagline}>러너스 하이를, 우리 아이에게</Text>

        <Pressable
          style={({ pressed }) => [s.kakao, busy && { opacity: 0.6 }, pressed && { opacity: 0.9 }]}
          onPress={kakao}
          disabled={busy}
          accessibilityRole="button"
          accessibilityState={{ disabled: busy, busy }}
          accessibilityLabel="카카오로 시작하기"
        >
          <Text style={s.kakaoText}>{busy ? '카카오로 연결 중…' : '카카오로 3초 만에 시작하기'}</Text>
        </Pressable>

        {/* 문이 하나뿐이므로 실패는 화면에 남아야 한다 — 스쳐 지나가는 Alert는 잠긴 사람에게
            아무것도 남기지 않는다. 원인 문자열은 그대로 보여준다: 문의로 전달될 유일한 단서다. */}
        {err && (
          <View style={s.errBox}>
            <Text style={s.errTitle}>카카오 로그인에 실패했어요</Text>
            <Text style={s.errBody}>{err}</Text>
            <View style={s.errRow}>
              <Pressable onPress={kakao} style={s.errBtn} accessibilityRole="button">
                <Text style={s.errBtnTxt}>다시 시도</Text>
              </Pressable>
              <Pressable
                onPress={() => Linking.openURL(SUPPORT_MAIL)}
                style={s.errBtn}
                accessibilityRole="button"
              >
                <Text style={s.errBtnTxt}>문의하기</Text>
              </Pressable>
            </View>
          </View>
        )}

        <Text style={s.legal}>
          로그인하면 이용약관과 개인정보 처리방침에 동의하게 돼요
        </Text>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.ink, paddingHorizontal: 28 },
  // 아이콘 락업과 동일: 도그스 = 화이트, 하이 = volt (히어로 음절)
  logo: { fontSize: 60, fontWeight: '900', color: '#fff', textAlign: 'center' },
  tagline: { fontSize: 16, color: '#8fa093', textAlign: 'center', marginTop: 6, marginBottom: 40 },
  kakao: { backgroundColor: '#FEE500', borderRadius: 16, alignItems: 'center', paddingVertical: 17, minHeight: 44, justifyContent: 'center' },
  kakaoText: { fontSize: 17, fontWeight: '800', color: '#191919' },

  errBox: { marginTop: 20, borderWidth: 1, borderColor: colors.coralText, borderRadius: 14, padding: 15 },
  errTitle: { fontSize: 15, fontWeight: '800', color: colors.coralText },
  errBody: { fontSize: 15, color: colors.cream, marginTop: 6, lineHeight: 20 },
  errRow: { flexDirection: 'row', gap: 10, marginTop: 13 },
  errBtn: {
    flex: 1, borderWidth: 1.5, borderColor: colors.cream, borderRadius: 12,
    paddingVertical: 11, alignItems: 'center', minHeight: 44, justifyContent: 'center',
  },
  errBtnTxt: { fontSize: 15, fontWeight: '800', color: colors.cream },

  legal: { fontSize: 15, color: '#5d6b5d', textAlign: 'center', marginTop: 24, lineHeight: 18 },
});
