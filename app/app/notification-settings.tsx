import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { AppState, Linking, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { NotificationPrimer } from '../src/components/notification-primer';
import { StatusBarCover } from '../src/components/status-bar-cover';
import { ScreenHead } from '../src/components/ui';
import { fetchNotificationPrefs, opsMe, saveNotificationPrefs } from '../src/lib/api';
import { haptic } from '../src/lib/haptics';
import { primerAction, PushPermissionRead } from '../src/lib/notification-primer-gate';
import { NotiPrefs, PREFS_NOTE, PrefKey, visiblePrefRows } from '../src/lib/notification-prefs';
import { readPushPermission } from '../src/lib/push';
import { session } from '../src/store';
import { colors, layout, paper } from '../src/theme';

// 알림 설정 — 0187. `settings.tsx`의 준비 중 카드에 「알림 설정 · 푸시 도입 후」로 앉아 있던 자리가
// 실화면이 됐다. 푸시는 0024부터 나가고 있었으므로 그 라벨은 거짓이었다.
//
// 🔴 이 화면이 끄는 것은 **기기 푸시 하나뿐**이다. `notifications` 행은 어느 쪽이든 쓰이고
//   `alerts.tsx` 인박스는 그대로 보여준다 (0187 §C). 그래서 제목 아래에 PREFS_NOTE 한 줄이
//   서 있고, 각 설명문 어디에도 「알림이 사라져요」라고 쓰지 않는다 — 그건 이 화면이 하지 않는
//   일이고, 정직법상 하지 않는 일을 말하면 안 된다. `notification-prefs.test.cjs`가 양방향으로 핀.
//
// 🔴 안전·긴급 행은 **끌 수 없는 스위치**로 그린다. 비활성 스위치 + 이유 한 줄이지, 눌러도
//   아무 일 없는 스위치가 아니다 (죽은 버튼 금지법). 서버에도 칸이 없다 —
//   `notify_push`는 safety/system 이면 선호 테이블을 **읽지도 않고** 나간다.
//
// 상태는 네 개가 전부 다르게 그려진다:
//   'loading' — 아직 모름 → 문장 한 줄 (스위치를 기본값으로 미리 그리지 않는다. 안 읽힌 값을
//               켜짐으로 그리는 건 0 을 로딩으로 그리는 것과 같은 거짓말이다)
//   'error'   — 못 읽음 → 라우드-페일 스트립 + 「다시 시도」, 스위치는 아예 없다
//   'ready'   — 서버 진실
//   저장 실패 — 낙관적 토글을 **되돌리고** 별도 스트립. 성공하면 서버가 돌려준 행으로 덮어쓴다.

export default function NotificationSettings() {
  const insets = useSafeAreaInsets();
  const [prefs, setPrefs] = useState<NotiPrefs | null>(null);
  const [loadErr, setLoadErr] = useState(false);
  const [saveErr, setSaveErr] = useState<string | null>(null);
  const [savingKey, setSavingKey] = useState<PrefKey | null>(null);
  // 🔴 [0210] 운영 알림 행은 **운영자에게만** 그린다. `system` 푸시는 ops_recipients 에 있는
  //   사람에게만 갈 수 있으므로(0084 §E), 나머지 모두에게는 받을 수 없는 알림의 스위치 —
  //   죽은 버튼이다. 판정은 서버가 한다(`ops_me()` 0198 §A: 콘솔 문들이 쓰는 그 창구).
  //   ⚠ null 은 **모름**이고(프로브 실패 포함) 그때는 행을 숨긴다. 양쪽 다 안전한 방향이다:
  //     비운영자는 못 쓰는 스위치를 안 보고, 프로브가 실패한 운영자는 그리지 않은 행이
  //     칸을 건드리지 않으므로 푸시를 그대로 받는다. 이 화면의 다른 다섯 상태와 달리
  //     라우드-페일 스트립을 띄우지 않는 이유: 이건 **실패가 아니라 부재**다. 비운영자에게
  //     「운영자 여부를 확인하지 못했어요」는 자기와 상관없는 일의 오류다.
  const [isOps, setIsOps] = useState<boolean | null>(null);

  // ── The DEVICE's answer, which outranks every switch below (onboarding-first-run-4) ──────────
  // The switches are real server columns, but iOS decides whether ANY push reaches this phone. A
  // person who refused the system alert used to see four live-looking switches while nothing was
  // ever delivered, and nothing in the app said so or offered a way back. Two states get a strip:
  //   'denied' — only the OS can undo it, so the strip opens the system Settings page.
  //   'ask'    — the one system question is still unspent. The strip opens the EXISTING
  //              NotificationPrimer, whose 계속 button stays the only code that fires the system
  //              alert (push.ts, "THE PRIMER'S BUTTON IS THE ONLY CALLER"). This screen never asks.
  //   null     — granted, or unreadable (old build / throwing module): nothing to say, the same
  //              fold push.ts makes. A permission we cannot read is not drawn as a refusal.
  // Re-read on focus AND on return to the foreground: coming back from Settings must move the
  // strip, and there is no event for "the user changed a system permission" (onboard/runner.tsx
  // idiom). readPushPermission never throws — it folds failures to null itself.
  const [perm, setPerm] = useState<PushPermissionRead | null>(null);
  const [primerOpen, setPrimerOpen] = useState(false);
  useFocusEffect(useCallback(() => {
    let alive = true;
    const read = () => { readPushPermission().then((p) => { if (alive) setPerm(p); }); };
    read();
    const sub = AppState.addEventListener('change', (st) => { if (st === 'active') read(); });
    return () => { alive = false; sub.remove(); };
  }, []));
  // Denied is checked FIRST: Android can report a re-askable denial, and the Settings page is the
  // door that works on both platforms. `dismissed` is passed as false on purpose — the home-screen
  // primer is once per install, but here the person came looking for this control.
  const osGate: 'denied' | 'ask' | null =
    perm?.status === 'denied' ? 'denied'
      : primerAction(perm, false) === 'primer' ? 'ask'
        : null;
  const openOsSettings = () => {
    Linking.openSettings().catch((e) => console.warn('[noti-prefs] openSettings:', (e as Error)?.message ?? e));
  };

  const load = useCallback(() => {
    setLoadErr(false);
    setPrefs(null);
    fetchNotificationPrefs()
      .then(setPrefs)
      .catch((e) => {
        console.warn('[noti-prefs] load:', (e as Error)?.message ?? e);
        setLoadErr(true);
      });
    opsMe()
      .then((m) => setIsOps(m.isOps))
      .catch((e) => {
        console.warn('[noti-prefs] ops_me:', (e as Error)?.message ?? e);
        setIsOps(null);
      });
  }, []);
  useEffect(() => { load(); }, [load]);

  const rows = visiblePrefRows(isOps);

  // 낙관적 토글 + 롤백. 저장 성공 시에는 **서버가 돌려준 행**으로 덮어쓴다 — 낙관값을 그대로
  // 두면 화면이 서버가 실제로 가진 값이 아니라 우리가 추측한 값을 보여주게 된다.
  // ⚠ The save is started OUTSIDE the state updater, deliberately. React re-invokes an updater
  // function under StrictMode, so a network call placed inside one fires twice — and for a
  // preference that means two writes racing over the same row. The value we roll back to is
  // captured from this render, and the switches are disabled while a save is in flight, so there
  // is only ever one `before` and one request.
  const toggle = useCallback((key: PrefKey, next: boolean) => {
    if (prefs === null || savingKey !== null) return;
    const before = prefs;
    setPrefs({ ...prefs, [key]: next });
    setSaveErr(null);
    setSavingKey(key);
    haptic('light');
    saveNotificationPrefs({ [key]: next })
      .then((stored) => setPrefs(stored))
      .catch((e) => {
        console.warn('[noti-prefs] save:', (e as Error)?.message ?? e);
        setPrefs(before);
        setSaveErr((e as Error)?.message || '설정을 저장하지 못했어요');
      })
      .finally(() => setSavingKey(null));
  }, [prefs, savingKey]);

  // The primer takes the whole screen, exactly as both homes draw it; either of its buttons hands
  // back here and the permission is read again so the strip reflects the answer.
  if (primerOpen) {
    return (
      <NotificationPrimer
        role={session.role === 'runner' ? 'runner' : 'owner'}
        onDone={() => {
          setPrimerOpen(false);
          readPushPermission().then(setPerm);
        }}
      />
    );
  }

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: paper.canvas }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top, paddingBottom: 40 }}
      >
        <ScreenHead title="알림 설정" />

        {osGate === 'denied' && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>기기 설정에서 알림이 꺼져 있어요</Text>
            <Pressable onPress={openOsSettings} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryTxt}>설정 열기 ›</Text>
            </Pressable>
          </View>
        )}
        {osGate === 'ask' && (
          <View style={s.askStrip}>
            <Text style={s.askTxt}>기기 알림이 아직 꺼져 있어요</Text>
            <Pressable onPress={() => setPrimerOpen(true)} accessibilityRole="button" style={s.retryBtn}>
              <Text style={[s.retryTxt, { color: paper.actionInk }]}>알림 켜기 ›</Text>
            </Pressable>
          </View>
        )}

        <Text style={s.note}>{PREFS_NOTE}</Text>

        {prefs === null && !loadErr && (
          <Text style={s.loading}>설정을 불러오는 중이에요…</Text>
        )}

        {loadErr && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>알림 설정을 불러오지 못했어요</Text>
            <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
              <Text style={s.retryTxt}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {prefs !== null && (
          <>
            {saveErr !== null && (
              <View style={s.failStrip}>
                <Text style={s.failTxt}>{saveErr}</Text>
                {/* 되돌려 놓았다는 사실을 말한다 — 스위치가 왜 제자리로 갔는지 설명이 없으면
                    사용자는 앱이 자기 조작을 삼켰다고 읽는다. 「다시 시도」 버튼은 두지 않는다:
                    다시 시도는 스위치를 한 번 더 누르는 것이고, 그 문은 바로 아래 열려 있다. */}
                <Text style={{ fontSize: 15, lineHeight: 21, color: paper.critical, marginTop: 4 }}>
                  스위치는 원래대로 돌려놨어요 · 다시 눌러보세요
                </Text>
              </View>
            )}

            <View style={s.rule} />
            <View>
              {rows.map((r, i) => {
                const on = r.key === null ? true : prefs[r.key];
                return (
                  <View key={r.label}>
                    {i > 0 && <View style={s.div} />}
                    <View style={s.prefRow}>
                      <View style={{ flex: 1, paddingRight: 12 }}>
                        <Text style={s.label}>{r.label}</Text>
                        <Text style={s.desc}>{r.desc}</Text>
                        {r.alwaysOn === true && <Text style={s.reason}>{r.reason}</Text>}
                      </View>
                      <Switch
                        value={on}
                        disabled={r.alwaysOn === true || savingKey !== null}
                        onValueChange={(v) => { if (r.key !== null) toggle(r.key, v); }}
                        accessibilityRole="switch"
                        accessibilityState={{ checked: on, disabled: r.alwaysOn === true || savingKey !== null }}
                        accessibilityLabel={r.alwaysOn === true ? `${r.label} 알림 — 항상 켜짐` : `${r.label} 알림`}
                        trackColor={{ false: colors.line, true: paper.action }}
                        thumbColor="#FFFFFF"
                        ios_backgroundColor={colors.line}
                      />
                    </View>
                  </View>
                );
              })}
            </View>
          </>
        )}
      </ScrollView>
      <StatusBarCover color={paper.canvas} />
    </>
  );
}

// Paper grammar (DESIGN.md §2 · §3b): radius 0, the switch list opens under a full-bleed coral
// rule instead of sitting in a card, rows divide with neutral #EEE.
const s = StyleSheet.create({
  // 15pt 플로어 (DESIGN.md:145) — 한국어는 kicker 면제를 타지 않는다
  note: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 14, marginBottom: 2 },
  rule: { height: 1, backgroundColor: paper.line, marginHorizontal: -layout.gutter, marginTop: 14 },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  prefRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 14 },
  label: { fontSize: 16, fontWeight: '700', color: paper.ink },
  desc: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: paper.dim, marginTop: 3 },
  reason: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.actionInk, marginTop: 4 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 16 },
  // loud-fail strip — criticalWash ground, critical ink, underlined action ≥44pt (house grammar)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 14 },
  failTxt: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // notice panel (not a failure): the wash grammar — the question is still unspent, nothing broke
  askStrip: { backgroundColor: paper.wash, padding: 13, marginTop: 14 },
  askTxt: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.actionInk },
});
