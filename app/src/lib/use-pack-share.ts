import { useEffect, useRef, useState } from 'react';
import { createPackPublisher, getLiveLastFix } from './geo';
import { PACK_PUBLISH_MAX_FIX_AGE_MS, PACK_PUB_MIN_MS, type PackPos } from './pack';
import { supabase } from './supabase';
import type { ClubSessionDetail } from './api';

// 팩 지도 송신 — one hook, called from every screen that TRACKS a club run.
//
// ═══ WHY IT IS A HOOK AND NOT CODE INSIDE THE MAP SCREEN ═══════════════════════════════════════
// The first draft published from `club/map/[sid].tsx`. That is wrong in a way the map itself
// cannot show: **you would only appear on the pack map while you had the pack map open.** A runner
// who is running — which is the entire population the map exists to draw — is looking at their run
// screen, not at the map, so the map would render a nearly empty pack while looking like it works.
// That is the honesty law's worst case, and no copy on the map can repair it, because the map does
// not know who is missing.
//
// So the publisher belongs where the TRACKING is, and there are three such screens:
//   · `club/companion/[sid].tsx`  — Mode A / 동반, an owner walking their own dog        (wired)
//   · `club/map/[sid].tsx`        — the map itself, for anyone who opens it mid-run       (wired)
//   · `club/run/[sid].tsx`        — the delegated runner                                  (NOT wired:
//     that file is held exclusively by another session tonight. It needs exactly the one line this
//     hook exists to make possible, and that line is reported to the coordinator rather than taken.)
// Until the third lands, a delegated runner appears on the pack map only while they have the map
// open. **That is a real gap, it is stated in the handoff, and it is one line wide.**
//
// ⚠ Calling this hook twice on one device is harmless: both publishers carry the same `profileId`,
// and the receiving side is newest-wins per profile (`mergePeer`). It costs messages, not truth.
//
// ═══ 🔴 THIS HOOK NEVER CALLS `startTracking` ══════════════════════════════════════════════════
// `geo.ts`'s `liveSub` is a module SINGLETON — a second `startTracking` silently replaces the
// first caller's callback. The screens this hook is called from are exactly the screens that own
// that callback, and taking it from them would freeze a live `km` while it still rendered as
// live. km is money (settle-run pays km * 3000). So the hook READS the shared buffer through
// `getLiveLastFix` and starts nothing. The consequence is the contract, restated as a mechanism:
// you publish only while something else is genuinely tracking you.

/** What the caller may say about the local user's own sharing.
 *  `null` means NOT MEASURED YET — never rendered as 「not sharing」, which is a claim. */
export type PackShareState = boolean | null;

/** The signed-in user's profile id, or null while unknown / signed out.
 *
 *  It lives here so 「which dot is me」 and 「whose position am I publishing」 have ONE definition —
 *  two answers to that question is how a screen ends up labelling a stranger as the viewer.
 *  ⚠ `getUser()` does NOT throw on a transient failure, it resolves with no user (api.ts:352), so
 *  a null here means 「we do not know」 and callers must not read it as 「signed out」. */
export function useMyProfileId(): string | null {
  const [myId, setMyId] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    supabase.auth.getUser()
      .then(({ data }) => { if (alive) setMyId(data?.user?.id ?? null); })
      .catch(() => { if (alive) setMyId(null); });
    return () => { alive = false; };
  }, []);
  return myId;
}

/**
 * Broadcast the local user's live position on this session's pack channel, if and only if they
 * are a checked-in participant of it whose GPS is producing fixes right now.
 *
 * The three conjuncts, each with its own reason:
 *   `joined`      a `session_people` row for this session (`0053:358`). A delegated runner gets
 *                 one from `session_runner_commit` (`0037:100`), a 동반 owner from RSVP, the host
 *                 at creation. It is what makes this position belong on THIS session's map.
 *   `checked_in`  a runner cannot receive a dog without it (`0038:42-44`) and the 동반 screen gates
 *                 its own start on it, so every genuine live run in this session has it. It is
 *                 also the closest thing the client can observe to 「is at the meetup」.
 *   a fresh fix   the only observation that says a run is happening NOW rather than earlier today.
 *
 * ⚠ RESIDUAL, stated rather than hidden: the shared buffer does not record WHICH run filled it.
 * A user who is checked in here and simultaneously mid-marketplace-run would publish that run's
 * position onto this map. Distinguishing them needs a change to `startTracking`'s contract, which
 * lives in a file another session holds tonight.
 */
export function usePackShare(
  sessionId: string | null | undefined,
  detail: ClubSessionDetail | null,
): PackShareState {
  // Only the TICK writes this — 「is my GPS actually producing fixes right now」. Everything else
  // about the answer is DERIVED at the bottom rather than pushed in from an effect, so there is
  // one writer and no cascading render.
  const [fixLive, setFixLive] = useState<boolean | null>(null);
  const myId = useMyProfileId();

  const myName = detail?.people.find((p) => p.isMe)?.name ?? null;
  const detailLoaded = detail != null;
  const mayPublish = !!sessionId && !!myId
    && !!detail?.joined && detail?.myAttendance === 'checked_in';

  // The name travels through a ref so a late-arriving roster does not tear the publisher down and
  // stand a new one up mid-run — the caption would flicker and the channel would churn.
  // ⚠ Assigned in an EFFECT, not during render: a ref written during render is torn under
  // concurrent rendering, and `react-hooks/refs` says so. The first draft wrote it during render
  // and the lint caught it.
  const nameRef = useRef<string | null>(null);
  useEffect(() => { nameRef.current = myName; }, [myName]);

  useEffect(() => {
    // Ineligible: return without touching state. That ANSWER is derived at the bottom — an effect
    // that pushes it in is a cascading render for a value that was already knowable.
    if (!sessionId || !mayPublish || !myId) return;
    const pub = createPackPublisher(sessionId);
    const tick = () => {
      const fix = getLiveLastFix();
      // No fix, or one too old to stand behind. Re-broadcasting a ten-minute-old point says
      // "I am here" about a place we have left.
      if (!fix || Date.now() - fix.t > PACK_PUBLISH_MAX_FIX_AGE_MS) { setFixLive(false); return; }
      setFixLive(true);
      const pos: PackPos = {
        profileId: myId,
        name: nameRef.current ?? '참가자',
        lat: fix.lat,
        lng: fix.lng,
        // ISO of the FIX's own OS timestamp, never of send time: a background batch arrives all
        // at once, and stamping it with arrival time would present an old point as current.
        // Epoch → ISO is absolute, so this is not a KST fact and does not go through `kst.ts`.
        at: new Date(fix.t).toISOString(),
      };
      pub.publish(pos);
    };
    // ⚠ NO immediate tick. It would be a setState in the effect body, and it would buy nothing:
    // `createPackPublisher` sends nothing until the channel has joined, which is a round trip
    // away, so the first tick that can actually publish is the one 3 s from now either way.
    const t = setInterval(tick, PACK_PUB_MIN_MS);
    return () => {
      clearInterval(t);
      pub.stop();
      // Leaving is not evidence about the GPS. Back to "not measured".
      setFixLive(null);
    };
  }, [sessionId, mayPublish, myId]);

  // `null` = NOT MEASURED YET, reached two ways that must not be collapsed into `false`: the
  // roster has not loaded, or the publisher has not ticked once. `false` is a CLAIM — "you are
  // not on the map" — and is only made once something was actually checked.
  if (!detailLoaded) return null;
  if (!mayPublish) return false;
  return fixLive;
}
