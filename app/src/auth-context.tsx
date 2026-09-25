import type { Session } from '@supabase/supabase-js';
import { createContext, ReactNode, useContext, useEffect, useState } from 'react';
import { releasePushToken, resetPushRegistration } from './lib/push';
import { supabase } from './lib/supabase';
import { session as appSession } from './store';

// App-wide auth state. Screens read { session, loading }; index guards routing.
//
// ⚠ This also HYDRATES `session.role` from `store.ts`. That value was un-persisted module state
// whose only writer is the role-select screen (`app/index.tsx`), so any entrance that bypasses
// that screen kept the 'owner' default. Two such entrances exist: the Live Activity deep links
// `daengrun://runner/run` (runActivity.ts:21) and `daengrun://owner/live` (ownerActivity.ts:62).
// So a runner whose app was killed mid-run and who taps the lock-screen banner comes back
// looking at runner screens while the app believes they are an owner. The worst path that
// combination produced was SOS — see the sendSOS comment in api.ts.
//
// Two design rules here:
//  ① FAIL OPEN. A slow or failed profile read must never block launch — the role stays at its
//     default and the role-select screen remains the final writer. Making this read a
//     precondition of launch would be a bigger bug than the one it fixes.
//  ② NEVER OVERWRITE A CHOICE. If the user picked a role this session, that wins. Hydration
//     fills in what the server knows when nobody has chosen yet; it does not undo a choice.

const AuthCtx = createContext<{
  session: Session | null;
  loading: boolean;
  signOut: () => Promise<void>;
}>({ session: null, loading: true, signOut: async () => {} });

// Did the user pick a role in this session? Set by `app/index.tsx` — after that, hydration loses.
let rolePickedThisSession = false;
export function markRolePicked() { rolePickedThisSession = true; }

async function hydrateRole(uid: string): Promise<void> {
  try {
    const { data, error } = await supabase.from('profiles').select('role').eq('id', uid).maybeSingle();
    if (error) { console.warn('[auth] role hydrate:', error.message); return; }
    const role = data?.role;
    // There may be no row — a new account that has not chosen a role yet. That is "not known
    // yet", not an error: keep the default and let the role-select screen answer it.
    if (role !== 'owner' && role !== 'runner') return;
    if (rolePickedThisSession) return;   // this session's choice is newer than the server record
    appSession.role = role;
  } catch (e) {
    console.warn('[auth] role hydrate:', e);   // fail open — never block launch
  }
}

// [ops-notifications-2] Sign-out releases this device's push token FIRST. Until 2026-09-25 this was
// the session end and nothing else, so the signed-out account's `push_tokens` row kept pointing at
// this phone (its chat, request and money pushes kept arriving here, possibly under someone else's
// login) and push.ts's per-process `_registered` flag stayed true, so the next account on this
// device never registered at all. Order is load-bearing and pinned by
// `test/push-token-signout.test.cjs`: the delete needs the outgoing session (RLS `push self all`
// admits only the row's own profile), so it precedes the session end; the registration reset
// precedes it too, so no home mount in between can re-register the outgoing account.
// Best-effort, bounded inside `releasePushToken`: a failure is a warning, never a blocked sign-out.
async function signOutReleasingPush(): Promise<void> {
  try {
    const { data } = await supabase.auth.getSession();
    const uid = data.session?.user?.id ?? null;
    if (uid) await releasePushToken(uid);
  } catch (e) {
    console.warn('[auth] push token release:', (e as Error)?.message ?? e);
  }
  resetPushRegistration();
  await supabase.auth.signOut();
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
      if (data.session?.user?.id) void hydrateRole(data.session.user.id);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s);
      // Also on sign-in: a session that arrived by logging in needs the same fact as a cold start.
      if (s?.user?.id) void hydrateRole(s.user.id);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  return (
    <AuthCtx.Provider value={{ session, loading, signOut: signOutReleasingPush }}>
      {children}
    </AuthCtx.Provider>
  );
}

export function useAuth() {
  return useContext(AuthCtx);
}
