import { Stack } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { opsMe } from '../../src/lib/api';
import { goBackOrHome } from '../../src/lib/nav';
import { OpsProvider } from '../../src/lib/ops-context';
// ⚠ The pure module, NOT api.ts's mapper. `opsMe` already folds through `opsError`, so this is a
// second, idempotent pass: a Korean message comes back unchanged and only an English one is
// replaced. It is belt rather than duplication — the policy (which token means what) stays in
// api.ts, and this screen only asserts the OUTPUT is Korean, which is the one thing the 2026-09-22
// measurement proved nobody was asserting.
import { foldRpcError, rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 운영 콘솔 — the gate screen for `app/ops/*`. 0198 §A.
//
// 🔴 THIS IS NOT THE SECURITY BOUNDARY AND MUST NEVER BE READ AS ONE. Every door behind it —
//   `ops_payouts_due` · `ops_runner_payout_detail` · `ops_record_manual_payout` ·
//   `ops_bank_account` · `ops_gear_claims_pending` · `ops_mark_gear_shipped` — carries its own
//   `ops_recipients_for('payout_due')` gate ahead of every read, and a build that deleted this
//   file entirely would leak NOTHING. What this screen buys is that the app does not draw a
//   console for someone who cannot use one: 「no dead buttons」 rather than 「no access」.
//
// FOUR STATES, ALL DRAWN DIFFERENTLY, and none of them is a blank:
//   'checking'  — the answer is not back yet → a real line, not an empty screen and not a
//                 pre-drawn console that flips to a refusal
//   'error'     — the check itself failed → a loud strip with 다시 시도. ⚠ NOT treated as
//                 「not an operator」: a network blip must not tell a real operator they have been
//                 removed from the roster, and it must not silently hide the console either.
//   'refused'   — signed in, not on this desk → the refusal, with 돌아가기
//   'ops'       — the console renders
//
// ⚠ The refusal screen reads `kinds` rather than printing one flat no. An operator subscribed to
//   `charge_dispatch_stale` and not to `payout_due` IS staff — telling them 「you are not an
//   operator」 would be false, and they would go and ask to be given a permission they have. That
//   distinction is exactly why `ops_me()` returns both fields (0198 §0d).
//
// 🔴 **[0213] THIS ANSWER IS NOW THE WHOLE STACK'S, THROUGH `OpsProvider`.** `ops/index.tsx` used
//    to call `opsMe()` again inside a `useFocusEffect` to decide which desks to draw, so opening
//    the console cost TWO round trips to the same RPC and every return from a desk screen cost
//    another — an N+1 on roster membership, which nothing inside this console can change. The gate
//    asks here; the screens read `useOps()`.
//    ⚠ **THE GATE SEMANTICS BELOW ARE UNCHANGED AND MUST STAY SO**: a non-operator still meets the
//    refusal face, a failed check is still 'error' and never 'refused' (a network blip must not
//    tell a real operator they have been removed from the roster), and `kinds` is null until read
//    rather than `[]` — 0206's two desk sections must not be drawn on an unknown, and an unread
//    answer is not a 'no'.
type Phase = 'checking' | 'error' | 'refused' | 'ops';

export default function OpsLayout() {
  const insets = useSafeAreaInsets();
  const [phase, setPhase] = useState<Phase>('checking');
  // null = not read yet, and it must NOT become `[]`: `[]` is a measured 「you hold no classes」,
  // which the desk gating is entitled to act on, and an unread answer is not.
  const [kinds, setKinds] = useState<string[] | null>(null);
  const [isOps, setIsOps] = useState(false);
  const [errMsg, setErrMsg] = useState<string | null>(null);

  const check = useCallback(() => {
    let alive = true;
    setPhase('checking');
    setErrMsg(null);
    opsMe()
      .then((me) => {
        if (!alive) return;
        setKinds(me.kinds);
        setIsOps(me.isOps);
        setPhase(me.isOps ? 'ops' : 'refused');
      })
      .catch((e) => {
        if (!alive) return;
        // ⚠ The message is shown, never swallowed — and never mapped to 'refused'. A failure to
        // ASK is a different fact from an answer of no.
        //
        // 🔴 MEASURED 2026-09-22, and this line is the defect the slice is named for. On a Release
        //    build against production (migration 0156, where `ops_me` does not exist) this strip
        //    rendered 「Could not find the function public.ops_me without parameters in the schema
        //    cache」 — an English database sentence, in the 운영 콘솔's refusal face, in a Korean
        //    product. The four-state machine above was already correct; what was wrong was that
        //    `e.message` was whatever PostgREST said. It is now the mapped Korean
        //    (`foldRpcError`), and the RAW text goes to the log instead.
        console.warn('[ops] ops_me:', rpcRaw(e));
        setErrMsg(foldRpcError(e, { empty: '권한을 확인하지 못했어요' }).message);
        setPhase('error');
      });
    return () => { alive = false; };
  }, []);
  useEffect(() => check(), [check]);

  // [0213] THE ONE REFRESH PATH for this answer, handed to the console's pull-to-refresh.
  // ⚠ It deliberately does NOT go through `check()`: that sets 'checking', which unmounts the
  //   whole `Stack` — so a pull-to-refresh would tear the console down and rebuild it under the
  //   operator's finger. It re-asks silently and updates in place.
  // ⚠ A FAILED refresh keeps the last known answer and only logs. Dropping a working console into
  //   the error face because one re-ask timed out would be the same mistake as mapping a failure
  //   to 'refused' — a failure to ASK is not an answer. A refresh that succeeds and says
  //   `is_ops: false` DOES flip to the refusal face: that is the server answering, and it is the
  //   direction that refuses.
  const refresh = useCallback(async () => {
    try {
      const me = await opsMe();
      setKinds(me.kinds);
      setIsOps(me.isOps);
      setPhase(me.isOps ? 'ops' : 'refused');
    } catch (e: any) {
      console.warn('[ops] ops_me refresh:', rpcRaw(e));
    }
  }, []);

  const ctx = useMemo(() => ({ isOps, kinds, refresh }), [isOps, kinds, refresh]);

  if (phase === 'ops') {
    return (
      <OpsProvider value={ctx}>
        <Stack
          screenOptions={{
            headerShown: false,
            contentStyle: { backgroundColor: colors.cream },
            animation: 'fade',
            animationDuration: 70,
          }}
        />
      </OpsProvider>
    );
  }

  const otherDesks = (kinds?.length ?? 0) > 0;

  return (
    <View style={[s.wrap, { paddingTop: insets.top + 24, paddingBottom: insets.bottom + 24 }]}>
      <Text style={s.title}>운영 콘솔</Text>

      {phase === 'checking' && (
        <Text style={s.body}>권한을 확인하는 중이에요…</Text>
      )}

      {phase === 'error' && (
        <View style={s.failStrip}>
          <Text style={s.failText}>{errMsg}</Text>
          <Pressable onPress={check} accessibilityRole="button" style={s.retryBtn}>
            <Text style={s.retryLabel}>다시 시도</Text>
          </Pressable>
        </View>
      )}

      {phase === 'refused' && (
        <>
          <Text style={s.body}>운영자 전용 화면이에요</Text>
          <Text style={s.sub}>
            {otherDesks
              ? `운영 담당자로 등록돼 있지만 이 창구(정산·배송)는 아니에요 · 현재 담당: ${(kinds ?? []).join(', ')}`
              : '정산과 배송을 처리하는 담당자만 들어올 수 있어요'}
          </Text>
        </>
      )}

      {phase !== 'checking' && (
        <Pressable
          onPress={goBackOrHome}
          accessibilityRole="button"
          style={({ pressed }) => [s.primary, pressed && s.primaryPressed]}
        >
          <Text style={s.primaryLabel}>돌아가기</Text>
        </Pressable>
      )}
    </View>
  );
}

// 15pt floor (DESIGN.md:145). No Korean below 15 here; the kicker exemption is latin-only and this
// screen has no latin kicker.
const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: colors.cream, paddingHorizontal: 22, justifyContent: 'center' },
  title: { fontSize: 23, fontWeight: '900', color: paper.ink, marginBottom: 14 },
  body: { fontSize: 18, lineHeight: 26, fontWeight: '800', color: paper.ink },
  sub: { fontSize: 15, lineHeight: 22, color: paper.dim, marginTop: 8 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // DESIGN.md:203-216 button matrix — Primary is an ink fill with the 3D lip, radius 0.
  primary: {
    marginTop: 26, minHeight: 56, borderRadius: 0, backgroundColor: paper.ink,
    borderBottomWidth: 4, borderBottomColor: paper.inkPressed,
    alignItems: 'center', justifyContent: 'center',
  },
  primaryPressed: { transform: [{ translateY: 3 }], borderBottomWidth: 1 },
  primaryLabel: { fontSize: 17, fontWeight: '800', color: '#FFFFFF' },
});
