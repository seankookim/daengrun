import { useEffect, useState } from 'react';
import { getLiveLastFix } from './geo';
import { PACK_PUBLISH_MAX_FIX_AGE_MS, PACK_PUB_MIN_MS } from './pack';
import { supabase } from './supabase';
import { packPublish, type ClubSessionDetail, type PackPublishRefusal } from './api';

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
// So the publishing belongs where the TRACKING is, and all three such screens now call it:
//   · `club/companion/[sid].tsx`  — Mode A / 동반, an owner walking their own dog        (wired)
//   · `club/map/[sid].tsx`        — the map itself, for anyone who opens it mid-run       (wired)
//   · `club/run/[sid].tsx`        — the delegated runner                                  (wired,
//     U2 `1cccaea`. ⚠ This block used to say it was NOT wired and named it as a live gap; it landed
//     the same night. A handoff that describes closed work as open manufactures a false problem in
//     the one artifact nobody distrusts, so the line is corrected here rather than in a note.)
//
// ═══ 🔴 N MOUNTED HOOKS DRIVE ONE TICK LOOP, AND THE TRUNK CLAIM THAT THEY NEED NOT WAS FALSE ═══
// This block used to say 「calling this hook twice on one device is harmless — it costs an RPC
// call, not truth, and the second one is answered `too_fast`」. **The normal stack falsifies it.**
// Expo Router keeps the screen you pushed FROM mounted, so a map opened over the run screen has
// TWO hooks ticking at 3 s against a server throttle of 2 s. The phases do not stay apart: whichever
// hook ticks second inside a 2 s shadow is refused, and with `too_fast` mapped to keep-previous the
// starved screen sat on `null` — 「내 위치 확인 중...」 — for as long as it was open, over a device
// that was publishing perfectly (eng blocking-3).
//
// So publishing is a MODULE-LEVEL, REF-COUNTED SINGLETON PER SESSION: one interval, one in-flight
// request, one answer, and every mounted hook subscribes to it. Two consequences worth naming:
//   · `too_fast` now maps to **true**, not to keep-previous. It is positive evidence that THIS
//     ACCOUNT published inside the last 2 seconds — which is precisely what 「내 위치 공유 중」
//     claims. It also fixes the case no client singleton can reach: the same account on two
//     devices, where the second device's refusal is the first device's success.
//   · a tick is SKIPPED while the previous await is unresolved, so a slow network cannot stack
//     requests behind each other and answer with an older one last.
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

/**
 * WHY the last publish attempt answered the way it did — the additive half of this module.
 *
 * 🔴 IT EXISTS BECAUSE `PackShareState` IS FROZEN AND TOO NARROW TO BE HONEST (addendum 3, design
 * F8). Three screens take a `boolean | null` from `usePackShare`, so that signature does not move;
 * but a bare `false` cannot tell 「my GPS has not produced a fix yet」 (transient, our fault, about
 * to fix itself) from 「the window closed」 (terminal, nothing to wait for), and the screen answered
 * by naming no cause at all. `usePackShareDetail` reads the SAME singleton, adds no call site
 * obligations, and lets the map say the true sentence — `pack.ts`'s `packShareLine` maps it.
 *
 * `no_fix` is the client-knowable one: it never reaches the server, which is exactly why the
 * server's refusal vocabulary alone could not answer this question.
 */
export type PackShareCause =
  | PackPublishRefusal
  | 'no_fix'    // no fresh fix in the shared buffer — the RPC was never called
  | 'threw'     // the call threw (offline, DNS, TLS): not a refusal, and not evidence we are on the map
  | 'unknown'   // the RPC refused with a string this build does not recognise
  | null;       // nothing refused: either ok, or nothing has been attempted yet

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The publish loop — one per session, module scope, ref-counted. See the header for why it cannot
// be per-hook. Nothing here is exported: the two hooks below are the only doors.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

type PackLoop = {
  sessionId: string;
  /** Non-null exactly while at least one PUBLISHING hook is mounted. It is also the liveness test
   *  a resolved await consults: no timer, no publisher, nothing to say. */
  timer: ReturnType<typeof setInterval> | null;
  /** Bumped whenever the loop stops, so an await that outlives its own loop cannot land. Same
   *  generation guard as `geo.ts`'s `pubCh !== ch` and the screen's `loadGen`. */
  gen: number;
  /** True from the moment a request leaves until it resolves. A tick inside that window is SKIPPED
   *  rather than queued — stacking requests lets an older answer land last. */
  inFlight: boolean;
  state: PackShareState;
  cause: PackShareCause;
  stateSubs: Set<(s: PackShareState) => void>;
  causeSubs: Set<(c: PackShareCause) => void>;
};

const packLoops = new Map<string, PackLoop>();

function packLoopFor(sessionId: string): PackLoop {
  let loop = packLoops.get(sessionId);
  if (!loop) {
    loop = {
      sessionId, timer: null, gen: 0, inFlight: false, state: null, cause: null,
      stateSubs: new Set(), causeSubs: new Set(),
    };
    packLoops.set(sessionId, loop);
  }
  return loop;
}

/** Forget a loop nobody is watching. Doing it here rather than on the last publisher's exit is what
 *  lets a detail observer outlive the publisher without resurrecting a second record for the same
 *  session — one record per session is what makes the two hooks agree. */
function dropPackLoopIfIdle(loop: PackLoop): void {
  if (loop.timer !== null || loop.stateSubs.size > 0 || loop.causeSubs.size > 0) return;
  if (packLoops.get(loop.sessionId) === loop) packLoops.delete(loop.sessionId);
}

/** One writer for both answers, so a state and its cause can never disagree. Silent when nothing
 *  moved — a 3 s tick that changes nothing must not re-render three screens. */
function settlePackLoop(loop: PackLoop, state: PackShareState, cause: PackShareCause): void {
  if (loop.state !== state) {
    loop.state = state;
    for (const fn of Array.from(loop.stateSubs)) fn(state);
  }
  if (loop.cause !== cause) {
    loop.cause = cause;
    for (const fn of Array.from(loop.causeSubs)) fn(cause);
  }
}

async function packTick(loop: PackLoop): Promise<void> {
  if (loop.timer === null) return;   // the last publisher left between the schedule and the fire
  if (loop.inFlight) return;         // see PackLoop.inFlight
  const fix = getLiveLastFix();
  const age = fix ? Date.now() - fix.t : Infinity;
  // No fix, or one too old to stand behind. Re-publishing a ten-minute-old point says "I am here"
  // about a place we have left — so we do not send, and we say WHICH of the two it was.
  if (!fix || age > PACK_PUBLISH_MAX_FIX_AGE_MS) { settlePackLoop(loop, false, 'no_fix'); return; }
  const gen = loop.gen;
  loop.inFlight = true;
  try {
    const r = await packPublish(loop.sessionId, fix.lat, fix.lng, Math.max(0, age));
    // The loop stopped (or stopped and restarted) while we awaited. Writing now would overwrite the
    // `null` the teardown just wrote and leave a stale claim for the next mount to read as measured.
    if (loop.gen !== gen) return;
    if (r.ok) settlePackLoop(loop, true, null);
    // ⚠ `too_fast` IS A TRUE ANSWER, NOT A MISSING ONE. The server only says it when this account
    // published inside the last 2 seconds, which is the very thing 「내 위치 공유 중」 asserts. It is
    // also the ONLY evidence a second device can get that the first one is publishing.
    else if (r.refusal === 'too_fast') settlePackLoop(loop, true, 'too_fast');
    else settlePackLoop(loop, false, r.refusal ?? 'unknown');
  } catch {
    // A throw is a network failure, not a refusal. It is still not evidence that we are on the
    // map, so it lands in the honest half — with its own cause, so the copy does not name GPS.
    if (loop.gen === gen) settlePackLoop(loop, false, 'threw');
  } finally {
    loop.inFlight = false;
  }
}

/** A publishing hook joins. The FIRST one starts the interval; the last one to leave stops it. */
function joinPackLoop(sessionId: string, onState: (s: PackShareState) => void): () => void {
  const loop = packLoopFor(sessionId);
  loop.stateSubs.add(onState);
  // Replay the current answer. Without it, a screen mounted over a running loop would render
  // 「확인 중...」 until the next tick over a device that is demonstrably publishing — the same trap
  // `subscribePack` records for a second listener on an already-joined channel.
  onState(loop.state);
  if (loop.timer === null) {
    loop.timer = setInterval(() => { void packTick(loop); }, PACK_PUB_MIN_MS);
  }
  return () => {
    loop.stateSubs.delete(onState);
    if (loop.stateSubs.size > 0) return;
    if (loop.timer !== null) { clearInterval(loop.timer); loop.timer = null; }
    loop.gen++;   // an in-flight await now belongs to a loop that no longer exists
    // Leaving is not evidence about anything. Back to "not measured", for the same reason the
    // per-hook cleanup did it: a stale `true` read by the next mount is a claim nobody checked.
    settlePackLoop(loop, null, null);
    dropPackLoopIfIdle(loop);
  };
}

/** A detail observer attaches. It does NOT start the loop — asking why the last publish was
 *  refused must not cause a publish. */
function observePackLoopCause(sessionId: string, onCause: (c: PackShareCause) => void): () => void {
  const loop = packLoopFor(sessionId);
  loop.causeSubs.add(onCause);
  onCause(loop.cause);
  return () => {
    loop.causeSubs.delete(onCause);
    dropPackLoopIfIdle(loop);
  };
}

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
 * Who the local user is on this session's map, as the three screens can each answer it.
 *
 * ⚠ IT IS A DESCRIPTOR AND NOT A SCREEN TYPE ON PURPOSE. The first draft took a
 * `ClubSessionDetail`, which the map and 동반 screens both hold — and `club/run/[sid].tsx`, the
 * screen that matters most, holds a `DelegationBoard` instead and never fetches the other. A hook
 * whose signature only fits the screens you happened to write is a hook the third screen cannot
 * adopt in one line, and 「one line」 was the entire reason to extract it.
 */
export interface PackIdentity {
  /** true = a checked-in participant of THIS session · false = not · **null = not known yet**,
   *  which must never be collapsed into false. */
  eligible: boolean | null;
  /** ⚠ NO LONGER READ BY THIS HOOK, and kept on purpose. Before 0160 this was the caption the hook
   *  put in the payload; `club_pack_publish` now takes the name from `profiles` server-side, so
   *  nothing here can set it. The field stays because the three call sites pass it and this
   *  signature is frozen for them — removing it is an edit to two screens held by other sessions,
   *  not a change this slice may make silently. Nothing renders it; it is not a fallback for
   *  anything. */
  name: string | null;
}

/** Derive the descriptor from `club_session_detail`, for the screens that have one.
 *
 * The two conjuncts, each with its own reason:
 *   `joined`      a `session_people` row for this session (`0053:358`). A delegated runner gets
 *                 one from `session_runner_commit` (`0037:100`), a 동반 owner from RSVP, the host
 *                 at creation. It is what makes this position belong on THIS session's map.
 *   `checked_in`  a runner cannot receive a dog without it (`0038:42-44`) and the 동반 screen gates
 *                 its own start on it, so every genuine live run in this session has it. It is
 *                 also the closest thing the client can observe to 「is at the meetup」.
 */
export function packIdentity(detail: ClubSessionDetail | null): PackIdentity {
  if (detail == null) return { eligible: null, name: null };
  return {
    eligible: !!detail.joined && detail.myAttendance === 'checked_in',
    name: detail.people.find((p) => p.isMe)?.name ?? null,
  };
}

/**
 * Publish the local user's live position onto this session's pack channel, if and only if they are
 * an eligible participant whose GPS is producing fixes right now.
 *
 * Eligibility is the caller's to state (see `PackIdentity`); the fresh fix is this hook's, and it
 * is the only observation that says a run is happening NOW rather than earlier today.
 *
 * ═══ 🔴 WHAT `true` MEANS CHANGED IN 0160, AND THAT IS THE POINT ══════════════════════════════
 * It used to mean 「my GPS produced a fix and I handed it to a channel object」 — which the screen
 * rendered as 「내 위치 공유 중」 while the channel might be unjoined, denied, or offline (codex #7:
 * a claim about the outside world made from a local variable). Publishing is now an RPC that
 * re-checks membership and the window, broadcasts, and VERIFY-READS its own row before answering,
 * so `true` here is the server saying the message landed. Nothing else can produce it.
 *
 * The three answers, and why each is the honest one:
 *   `true`   the last RPC returned ok — a delivered position, not an attempt.
 *   `false`  a refusal we can stand behind: no fix · a fix too old · not checked in · the window
 *            closed · the RPC not deployed yet · the send not delivered · a call that threw.
 *   `null`   NOT MEASURED. The caller does not know our eligibility yet, or nothing has ticked.
 *
 * ⚠ `too_fast` IS `true` SINCE 0160's FIX PASS, and the reason is in the header: the server says it
 * only when THIS ACCOUNT published inside the last 2 seconds, which is the same proposition
 * 「내 위치 공유 중」 states. The keep-previous it replaces starved whichever of two mounted screens
 * lost the phase race, and left it on 「확인 중...」 for the life of the screen.
 *
 * ⚠ RESIDUAL, stated rather than hidden: the shared buffer does not record WHICH run filled it.
 * A user who is eligible here and simultaneously mid-marketplace-run would publish that run's
 * position onto this map. Distinguishing them needs a change to `startTracking`'s contract.
 */
export function usePackShare(
  sessionId: string | null | undefined,
  who: PackIdentity,
): PackShareState {
  // A mirror of the SINGLETON's answer, not a second source of it. Everything else about what this
  // hook returns is DERIVED at the bottom rather than pushed in from an effect, so there is one
  // writer and no cascading render.
  const [shared, setShared] = useState<PackShareState>(null);
  const myId = useMyProfileId();

  // Destructured to a PRIMITIVE: `packIdentity(detail)` builds a fresh object every render, so an
  // effect keyed on the object would tear the ticker down and stand a new one up on every frame.
  const { eligible } = who;
  // `myId` is still a conjunct even though the RPC takes identity from the JWT: a device with no
  // session cannot publish, and asking is the difference between a refusal and a wasted call.
  const mayPublish = !!sessionId && !!myId && eligible === true;

  useEffect(() => {
    // Ineligible: join nothing. That ANSWER is derived at the bottom — an effect that pushes it in
    // is a cascading render for a value that was already knowable. An ineligible hook must also not
    // ref-count the loop, or an anon viewer would keep a publisher alive that never publishes.
    if (!sessionId || !mayPublish) return;
    return joinPackLoop(sessionId, setShared);
  }, [sessionId, mayPublish]);

  // `null` = NOT MEASURED YET, reached two ways that must not be collapsed into `false`: the
  // caller does not know yet whether we are eligible, or nothing has ticked.
  // `false` is a CLAIM — "you are not on the map" — and is only made once something was checked.
  if (eligible === null) return null;
  if (!mayPublish) return false;
  return shared;
}

/**
 * Why the last publish attempt on this session answered the way it did — ADDITIVE, and deliberately
 * a second hook rather than a widened return.
 *
 * ⚠ THE SHAPE IS THE POINT. `usePackShare`'s `boolean | null` has three live call sites (map ·
 * companion · run) held by other sessions, so widening it is an edit to two screens this slice may
 * not make. A second export costs those two screens nothing — they never call it — and gives the
 * map the cause it needs to stop rendering one sentence for four different situations.
 *
 * It OBSERVES the same singleton and does not start it: a screen that asks why gets `null` when
 * nothing is publishing, which is the truthful answer to 「why were we refused」 when we never asked.
 */
export function usePackShareDetail(sessionId: string | null | undefined): PackShareCause {
  const [cause, setCause] = useState<PackShareCause>(null);
  useEffect(() => {
    if (!sessionId) return;
    return observePackLoopCause(sessionId, setCause);
  }, [sessionId]);
  return cause;
}
