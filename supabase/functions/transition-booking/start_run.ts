// `start_run` — the run OPENS through one server transaction (0087 §2).
//
// Extracted from index.ts's switch, and ONLY this case, for cancel_owner.ts's reason: `Deno.serve`
// at that module's top level makes it unimportable, and this case became a money path the day
// `runs.started_at` became the column 0083 §6's cutover grandfathering reads. The rest of
// transition-booking is untouched; this function is called with the same values the case body
// used to close over.
//
// ═══ What it replaces, and why that shape was a hole ═══
//     await set({ status: "active" });
//     await db.from("runs").insert({ booking_id, started_at: new Date().toISOString() });
// Two commits, and the second one's result was never bound to a variable — so its error was
// discarded in silence. An assigned runner could pre-plant a `runs` row through the RLS insert
// policy (`0002_rls.sql:107`, now dropped), the insert here would fail on the unique
// `booking_id`, nothing would notice, and the run would go live carrying a client-chosen
// `started_at` of `'2000-01-01'` — which is `< return_seal_since` forever, so the run settles
// with no return seal. See 0087 §0 ① for the full chain.
//
// ═══ The law of this file ═══
// THE SERVER CHOOSES THE CLOCK. This function passes no timestamp; `start_run_tx` takes none.
// A `started_at` that crossed the wire is not a start time, it is a claim about one.
//
// The RPC's error is now THROWN, not swallowed — that is half the fix and the half that lives in
// TypeScript. The refusals it can raise are all honest states the runner can act on
// (`not_picked_up` = the handoff is not finished; `not_run_runner` = not your booking), and a
// second start is `{unchanged:true}` rather than an error, so the retry path the runner's screen
// depends on (`runner/run.tsx:623` re-fires on every re-entry) is unaffected.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { HttpError } from "../_shared/ctx.ts";

// deno-lint-ignore no-explicit-any
type Booking = Record<string, any>;
/** index.ts's `notify` helper, passed in so the copy and the insert stay in one place. */
type Notify = (profileId: string, title: string, body: string) => PromiseLike<unknown>;

export async function startRun(
  db: SupabaseClient,
  args: { bookingId: string; uid: string; bk: Booking; notify: Notify },
): Promise<void> {
  const { bookingId, uid, bk, notify } = args;
  if (bk.runner_id !== uid) throw new HttpError(403, "runner only");

  const { error } = await db.rpc("start_run_tx", { p_booking: bookingId });
  if (error) throw new HttpError(409, error.message);

  // Behaviour preserved EXACTLY (0087 §0c): the notification fires on every accepted call,
  // including an idempotent re-start, because that is what the two-step did — the transition
  // trigger short-circuits `old.status = new.status` (0066 §1), so a re-tap has always been a
  // silent success with a second "러닝 시작". Whether that duplicate should be suppressed is a
  // client-slice question; this file is closing a money hole and changes nothing else.
  await notify(bk.owner_id, "러닝 시작", `${bk.km}km 러닝이 시작됐어요 — 실시간으로 지켜보세요`);
}
