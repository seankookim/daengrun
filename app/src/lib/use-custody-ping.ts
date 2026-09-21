// The 귀가 heartbeat, as one hook — so the two screens a runner is actually on between `end_run`
// and the second return stamp share ONE loop instead of two that can drift apart.
//
// `runner/return-seal.tsx` is where the stop routes (run.tsx:846 `router.replace`), and
// `runner/done.tsx` is the one door out of it that stays inside custody (return-seal.tsx:377's
// 「기록 먼저 보기」, drawn in frame b — my stamp in, the owner's not). Both are custody-phase
// screens; both ping.
//
// Everything decidable is in `custody-ping-policy.ts` and tested there. This file holds only the
// timer, the AppState subscription and the call.
import { useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { custodyPing } from './api';
import {
  isFatalPingRefusal, nextPingState, pingDelayMs, PING_START, pingStripVisible, type PingState,
} from './custody-ping-policy';

export type CustodyPingHandle = {
  /** True after PING_STRIP_AFTER consecutive misses, false again on the next success. The screen
   *  renders one line from it; it never blocks anything. */
  failing: boolean;
};

/**
 * @param bookingId the booking in custody, or null (no booking → no loop)
 * @param inCustody the caller's belief that this booking is still in the custody phase. It only
 *        OPENS the loop; the server closes it — a `not_in_custody` refusal stops the loop for
 *        good, which is what makes `done.tsx` safe even though it reads its status once.
 */
export function useCustodyPing(bookingId: string | null, inCustody: boolean): CustodyPingHandle {
  const [failing, setFailing] = useState(false);
  // The state machine lives in a ref: the loop reads it inside a timer callback, and a re-render
  // per ping would be a re-render per minute on a ceremony screen for a value nothing draws.
  const stateRef = useRef<PingState>(PING_START);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const alive = useRef(false);

  useEffect(() => {
    if (!bookingId || !inCustody) return;
    // A new booking is a new loop — a previous booking's stop must not silence this one.
    stateRef.current = PING_START;
    setFailing(false);
    alive.current = true;

    const clear = () => { if (timer.current) { clearTimeout(timer.current); timer.current = null; } };

    const tick = async () => {
      timer.current = null;
      if (!alive.current || stateRef.current.stopped) return;
      // Foreground only. A backgrounded JS timer is throttled to nothing by both platforms, so a
      // loop that kept "running" there would be a heartbeat the product claims and does not send.
      if (AppState.currentState !== 'active') return;
      try {
        await custodyPing(bookingId);
        stateRef.current = nextPingState(stateRef.current, { ok: true });
      } catch (e) {
        const msg = (e as Error)?.message ?? null;
        stateRef.current = nextPingState(stateRef.current, { ok: false, message: msg });
        // Logged, never shown — a failed ping must not interrupt the return ceremony. The strip
        // below is the only runner-facing consequence, and only after three in a row.
        console.warn('[custody-ping]', msg);
        if (isFatalPingRefusal(msg)) {
          // Non-transient: this runner cannot ping this booking, now or later. Stop, and draw
          // nothing — it is not a signal problem and must not be reported to the runner as one.
          if (alive.current) setFailing(false);
          return;
        }
      }
      if (!alive.current) return;
      setFailing(pingStripVisible(stateRef.current));
      clear();
      timer.current = setTimeout(tick, pingDelayMs(stateRef.current.fails));
    };

    // Ping immediately: the runner arrives here seconds after the stop, and the first ping is also
    // the cheapest way to learn the channel is refused.
    void tick();

    const sub = AppState.addEventListener('change', (st) => {
      if (!alive.current || stateRef.current.stopped) return;
      if (st === 'active') {
        // Resumed. The gap may already be past the server's 90 s threshold, so ping NOW rather
        // than waiting out a fresh period.
        clear();
        void tick();
      } else {
        clear();
      }
    });

    return () => {
      alive.current = false;
      clear();
      sub.remove();
    };
  }, [bookingId, inCustody]);

  return { failing };
}
