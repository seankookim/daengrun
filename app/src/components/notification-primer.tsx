import AsyncStorage from '@react-native-async-storage/async-storage';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { primerAction, PrimerAction } from '../lib/notification-primer-gate';
import { readPushPermission, registerPushToken, requestPushPermission } from '../lib/push';
import { paper } from '../theme';
import { PaperBtn } from './paper-btn';

// 첫 홈 진입 알림 프라이머 — HIG row S1/O3 (patterns/managing-notifications), 2026-09-22.
// Modelled on `location-primer.tsx`, the repo's only other primer: one plate, the benefit stated
// in the person's own terms, and the system alert fired on a BUTTON rather than on mount.
//
// WHY THIS EXISTS: `push.ts` used to call `requestPermissionsAsync` from both homes' mount
// effects. For a signed-in user that is launch — so the single question iOS ever grants was asked
// of someone who had just seen a logo. A reflexive 허용 안 함 there is unrecoverable in-app
// (`canAskAgain` goes false and the alert never returns), and for this product the push IS the
// product: an owner learns their dog was picked up, a runner learns a job exists.
//
// ⚠ WHERE IT DIFFERS FROM THE LOCATION PRIMER, and the difference is Sean's ruling read narrowly.
// Location has NO 「나중에」 — verbatim 「go with 1, no 나중에」 — because location is what the
// running product rests on and the recovery path (the run screens refuse to start and deep-link
// to Settings) already strands nobody. Notifications are not that: nothing in the app fails
// without them, they arrive when the person is NOT looking, and there is no screen that would
// naturally re-ask. A single-button plate over a home screen would be a takeover with no exit.
// So this one has two buttons, and the cost is the same one the location ruling accepted — a
// 나중에 cannot be re-asked in-app either, because the flag is written on BOTH paths.
//
// ⚠ COPY CEILING: the three moments named per role must be things this product ACTUALLY sends.
// Owner — 러너 배정 (요청 수락), 픽업 (러너가 출발/도착), 귀가 (러닝 종료·리포트).
// Runner — 새 요청, 예약 확정, 인계 시각. All six have real writers in `api.ts` / the migrations.
// Never name a notification here that nothing sends; that is the mockup law wearing copy's costume.

export type PrimerRole = 'owner' | 'runner';

// One flag, one install. Bumping the suffix re-asks everyone, so it is versioned deliberately
// rather than by accident — a rename is a product decision, not a refactor.
const DISMISSED_KEY = 'noti-primer-dismissed-v1';

/** Has this install already answered the primer (either button)? A throwing store reads as YES —
 *  the safe direction: a primer we cannot remember dismissing would reappear on every launch. */
export async function primerDismissed(): Promise<boolean> {
  try {
    return (await AsyncStorage.getItem(DISMISSED_KEY)) === '1';
  } catch (e) {
    console.warn('[noti-primer] read:', (e as Error)?.message);
    return true;
  }
}

async function markDismissed(): Promise<void> {
  try {
    await AsyncStorage.setItem(DISMISSED_KEY, '1');
  } catch (e) {
    // A failed write means the primer may show again next launch. That is visible and harmless;
    // it is not a reason to pretend the person answered.
    console.warn('[noti-primer] write:', (e as Error)?.message);
  }
}

/**
 * The world-reading wrapper around the pure rule. Both homes call exactly this on mount.
 * 'primer' ⇒ draw <NotificationPrimer>. 'register' / 'skip' ⇒ call `registerPushToken()`, which
 * no longer prompts and is therefore safe on every branch.
 */
export async function decideNotificationPrimer(): Promise<PrimerAction> {
  const [perm, dismissed] = await Promise.all([readPushPermission(), primerDismissed()]);
  return primerAction(perm, dismissed);
}

export function NotificationPrimer({ role, onDone }: { role: PrimerRole; onDone: () => void }) {
  const insets = useSafeAreaInsets();
  const [asking, setAsking] = useState(false);

  const ask = async () => {
    if (asking) return;
    setAsking(true);
    try {
      await requestPushPermission();
      await markDismissed();
      // Granted ⇒ this registers the token. Refused ⇒ it returns without prompting again.
      // Either way the deep-link listeners arm, so a tap on a push delivered later still routes.
      await registerPushToken();
    } finally {
      // Either answer moves on — the screen's job was the explanation, not the gate.
      setAsking(false);
      onDone();
    }
  };

  const later = async () => {
    if (asking) return;
    await markDismissed();
    // No ask, and nothing to register — but arm the deep links anyway (see registerPushToken).
    await registerPushToken();
    onDone();
  };

  const owner = role === 'owner';

  return (
    <View style={[s.wrap, { paddingTop: insets.top, paddingBottom: Math.max(insets.bottom, 12) }]}>
      <View style={s.body}>
        <Text style={s.kicker}>알림</Text>
        <Text style={s.head}>
          {owner ? '아이가 나가고\n돌아오는 순간에' : '요청이 오는\n바로 그때'}
        </Text>
        <Text style={s.lede}>
          {owner
            ? '러너 배정, 픽업, 귀가 — 보호자가 놓치면 안 되는 세 순간에 알림을 보내드려요.'
            : '새 요청, 예약 확정, 인계 시각 — 일이 생기는 순간에 알림을 보내드려요.'}
        </Text>
      </View>

      {/* solid coral hairline — 이 선이 곧 브랜드 (DESIGN.md §4) */}
      <View style={s.rule} />
      {/* The limit line names a real destination: settings.tsx:142 pushes /notification-settings,
          whose four category switches are real columns (0187 §A). Never promise a control that
          does not ship. */}
      <Text style={s.limit}>종류별로 끄고 켜는 건 설정 › 알림에서 언제든 할 수 있어요.</Text>

      <View style={s.actions}>
        {/* 「계속」, never 「허용」: HIG (Privacy → pre-alert screens) — a custom screen whose button
            says Allow makes the person think they already granted, then the real system alert asks
            again. The system alert owns the word 허용. (Row O4, and the same word the location
            primer was corrected to.) busy = label swap, never an opacity trick (DESIGN.md matrix). */}
        <PaperBtn label="계속" busyLabel="확인 중…" busy={asking} onPress={ask} />
        {/* quiet, not secondary: 나중에 is the genuinely low-involvement move and must not read as
            a second action of equal weight. It is a real route with a real effect — the flag is
            written and the homes stop asking — so it is not a dead button. */}
        <PaperBtn label="나중에" variant="quiet" disabled={asking} onPress={later} style={{ marginTop: 8 }} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: paper.canvas },
  body: { paddingHorizontal: 20, paddingTop: 28 },
  kicker: { fontSize: 15, fontWeight: '800', letterSpacing: 1.9, color: paper.faint },
  head: { fontSize: 26, lineHeight: 34, fontWeight: '900', color: paper.ink, marginTop: 10 },
  lede: { fontSize: 16, lineHeight: 24, color: paper.text, marginTop: 12 },
  rule: { height: 1, backgroundColor: paper.line, marginTop: 'auto' },
  limit: { fontSize: 15, lineHeight: 22, color: paper.dim, paddingHorizontal: 20, paddingVertical: 16 },
  actions: { paddingHorizontal: 20, paddingBottom: 12 },
});
