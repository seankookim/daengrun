// Owner Live Activity control — lazy-loaded (old builds without the widget extension skip quietly).
// iOS 16.2+ · works from the next expo run:ios build.
//
// Lifecycle vs the runner sibling (runActivity.ts): the runner LA lives and dies with the runner's
// app, so start/update/end are all local. The OWNER's app is suspended for most of the run — so
// this controller's real job is the handover to APNs:
//   1. start locally (the owner IS in the app at handoff — meetup screen — or on owner/live),
//   2. read the PER-ACTIVITY ActivityKit push token (not the per-device Expo token of push.ts),
//   3. register it via owner_la_register (0063) and re-register on every rotation,
//   4. hand off — from then on the 0063 server pipeline (trace trigger + stale sweep + status
//      trigger) drives the lock screen; local update() is a foreground nicety only.
// If the build lacks push-enabled widgets (expo-widgets plugin `enablePushNotifications` not set —
// see wave report for Sean's prebuild step), getPushToken() returns null: the LA still works
// locally and we say so in the console instead of pretending pushes exist.

import { ownerLaRegister, ownerLaUnregister } from './api';

export interface OwnerLAProps {
  phase: 'pre' | 'running' | 'stale' | 'done' | 'ended';
  dogName: string;
  runnerName: string;
  km: string;
  targetKm: string;
  pace: string;
  elapsed: string;
  statusLine: string;
  // '' = no claim; server (0078) computes for pushes, client mirrors for local updates.
  paceState?: '' | 'good' | 'slow';
}

let instance: any = null;
let instanceBookingId: string | null = null;
let tokenSub: { remove: () => void } | null = null;

async function registerToken(bookingId: string, token: string | null): Promise<void> {
  if (!token) return;
  try {
    const env = __DEV__ ? 'development' : 'production';
    await ownerLaRegister(bookingId, String(instance?.nativeLiveActivity?.id ?? bookingId), token, env);
  } catch (e) {
    // Registration failure = pushes won't arrive for this activity. The LA does not lie about it:
    // without pushes the server never says '방금 업데이트', and the stale state never falsely
    // appears either — the banner simply stays on its last locally-drawn state.
    console.warn('[ownerLA] token register:', (e as Error)?.message);
  }
}

export function startOwnerActivity(bookingId: string, p: OwnerLAProps): void {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const OwnerRunActivity = require('../activities/OwnerRunActivity').default;

    // Re-entry (owner reopened the app mid-run): adopt the existing activity instead of stacking
    // a second banner on the lock screen.
    if (!instance || instanceBookingId !== bookingId) {
      const existing = OwnerRunActivity.getInstances?.() ?? [];
      if (instanceBookingId !== bookingId && instance) {
        // A different booking's activity is still around (previous run) — end it, it is over.
        try { instance.end('immediate'); } catch { /* already gone */ }
        instance = null;
      }
      instance = existing.length > 0 ? existing[0] : OwnerRunActivity.start(p, 'daengrun://owner/live');
      instanceBookingId = bookingId;

      // Per-activity APNs token — available slightly after start, and it ROTATES: register now and
      // on every rotation event.
      tokenSub?.remove?.();
      tokenSub = instance.addPushTokenListener?.((e: any) => {
        registerToken(bookingId, e?.pushToken ?? null);
      }) ?? null;
      instance.getPushToken?.()
        .then((t: string | null) => {
          if (t) return registerToken(bookingId, t);
          console.warn('[ownerLA] push token 없음 — expo-widgets enablePushNotifications + prebuild 필요 (로컬 갱신만 동작)');
        })
        .catch((e: Error) => console.warn('[ownerLA] push token:', e?.message));
    } else {
      // Same booking, already started — just refresh content.
      try { instance.update(p); } catch { /* no-op */ }
    }
  } catch (e) {
    console.warn('[ownerLA] start:', (e as Error)?.message);
  }
}

export function updateOwnerActivity(p: OwnerLAProps): void {
  if (!instance) return;
  try { instance.update(p); } catch { /* no-op */ }
}

// Local end — fallback for when the app is awake at completion (report screen reached). The 0063
// completion push also ends the activity server-side with the settled numbers; whichever lands
// first wins, the other is a harmless no-op. Kept 8 minutes (lab §C-④), then dismissed.
export function endOwnerActivity(p: OwnerLAProps): void {
  const bid = instanceBookingId;
  if (instance) {
    try { instance.end({ after: new Date(Date.now() + 8 * 60 * 1000) }, p, new Date()); } catch { /* no-op */ }
  }
  tokenSub?.remove?.();
  tokenSub = null;
  instance = null;
  instanceBookingId = null;
  if (bid) ownerLaUnregister(bid).catch(() => {});
}
