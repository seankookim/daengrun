import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { markRolePicked, useAuth } from '../src/auth-context';
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

  // Return type is annotated because `fail`'s retry references `start` — an un-annotated
  // self-referential const would make TS infer `any` (7022).
  const start = async (role: Role): Promise<void> => {
    if (busy || !auth) return;
    setBusy(role);

    // 실패는 실패로 — 시작 경로의 모든 단계가 재시도 가능한 알림으로 끝난다 (조용한 스킵 금지).
    const fail = (title: string, msg: string) => {
      setBusy(null);
      Alert.alert(title, msg, [
        { text: '다시 시도', onPress: () => { void start(role); } },
        { text: '닫기', style: 'cancel' },
      ]);
    };

    // 프로필 실화: profiles 행 upsert (RLS self-insert)
    //
    // ⚠ react-doctor `supabase-client-owned-authz-field` 가 여기서 경고한다 — 클라이언트가
    // `role`을 쓴다고. **의도된 것이고, 실측으로 확인했다 (2026-08-19):**
    //   · RLS: profiles self write = `auth.uid() = id`, 컬럼 제한 없음 — 서버가 허용하는 쓰기다
    //   · 어떤 RLS 정책도, 어떤 RPC도, 어떤 엣지 함수도 `profiles.role`을 인가에 쓰지 않는다
    //   · 러너 **권한**은 `runners` 행과 그 `tier`가 결정한다 (public runner read 정책이 보는 것)
    // 그래서 `role`은 인가 필드가 아니라 **표시·라우팅 선호**다. 사용자가 자기 것을 바꿔도 얻는
    // 권한이 없다. 규칙은 이름이 `role`인 필드를 패턴으로 잡은 것이다. 만약 언젠가 서버가
    // 이 컬럼으로 뭔가를 가로막기 시작하면 이 주석은 거짓이 되고, 그때는 진짜 결함이다.
    //
    // ⚠ Read before write. The old payload always carried `name`, so the upsert's conflict arm
    // rewrote it on EVERY launch — clobbering whatever onboarding (or 마이) had saved with the
    // email stem, or with '사용자' for a Kakao account that has no email. `name` is NOT NULL, so
    // it must still be supplied on the INSERT; the fix is to send it only when there is no row.
    // This read also feeds the first-run gate below (profiles select grants: 0088 §A + 0091 §E⑤).
    const { data: existing, error: readErr } = await supabase
      .from('profiles').select('name, district').eq('id', auth.user.id).maybeSingle();
    if (readErr) { fail('프로필을 불러오지 못했어요', readErr.message); return; }

    // ⚠ UPDATE or INSERT — never `upsert` here. `upsert` is INSERT … ON CONFLICT DO UPDATE, and
    // Postgres forms and NOT NULL-checks the proposed tuple BEFORE conflict resolution — so an
    // existing-row payload of `{ id, role }` (correctly omitting `name`, which must not be
    // rewritten) died on `profiles.name`'s NOT NULL every launch: 「프로필 저장 실패 — null value in
    // column "name" … violates not-null constraint」. The constraint refused it, so nothing was
    // corrupted — but the role write silently never landed. Measured on device 2026-08-20; this is
    // the tail of the same fix that stopped `name` being clobbered, and the two must be solved by
    // choosing the statement, not by shaping the payload.
    const { error } = existing
      ? await supabase.from('profiles').update({ role }).eq('id', auth.user.id)
      // `||`, not `??`: login is Kakao-only and the email scope needs business verification, so
      // GoTrue can hand back an EMPTY STRING rather than undefined. `''?.split('@')[0]` is `''`
      // and `'' ?? x` is `''` — the fallback could never fire, and since `name` is written only on
      // INSERT it could never self-heal either. `||` catches both shapes.
      : await supabase.from('profiles').insert({ id: auth.user.id, role, name: auth.user.email?.split('@')[0] || '사용자' });
    if (error) { fail('프로필 저장 실패', error.message); return; }

    // 러너 선택 시 runners 행 + 기본 가용시간 확보 (0057 K-3: applicant 민팅)
    if (role === 'runner') {
      try { await ensureRunner(); } catch (e) { console.warn('ensureRunner:', e); }
    }

    // First run is DERIVED — there is no `onboarded` flag (and none is needed): an owner with no
    // dog cannot request a run, and a runner with no 동네 gets an unsorted course strip. Both
    // reads must fail LOUDLY: skipping onboarding on a network blip would drop the owner on a
    // home screen whose primary action immediately dead-ends.
    let next: '/owner/home' | '/runner/home' | '/onboard/owner' | '/onboard/runner';
    if (role === 'owner') {
      // A DIRECT count, not `fetchMyDogs().length`. That helper resolves `[]` for a signed-out
      // user, and `getUser()` returns `{ user: null, error }` — not a throw — on a transient
      // failure or a 429. A returning owner with two dogs therefore got `[]` with no error and
      // was replaced onto a first-run screen. Here `error` and `count === 0` are different
      // answers, and only the second one is "you have no dog yet".
      const { count, error: dogErr } = await supabase
        .from('dogs').select('id', { count: 'exact', head: true }).eq('owner_id', auth.user.id);
      if (dogErr) { fail('시작하지 못했어요', dogErr.message); return; }
      next = (count ?? 0) === 0 ? '/onboard/owner' : '/owner/home';
    } else {
      // `existing` was read before ensureRunner, which never writes district — still current.
      next = (existing?.district ?? '').trim() === '' ? '/onboard/runner' : '/runner/home';
    }

    setBusy(null);
    session.role = role;
    // This choice is authoritative for the session — a late profile hydration in AuthProvider
    // must not undo it.
    markRolePicked();
    // `push`, not `replace`, into onboarding. The root stack is headerShown:false +
    // gestureEnabled:false, so a `replace` left a mistapped role with NO in-app exit: the CTA
    // stays disabled until a dog name AND an address are filled, and 나중에 does not render until
    // an address row exists. Pushing puts role-select back on the stack, and each onboarding
    // screen renders a back control that is shown only when `router.canGoBack()` is true.
    router.push(next);
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
