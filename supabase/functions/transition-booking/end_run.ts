// `end_run` — THE STOP. The run's other bookend to `start_run.ts`, and the first product caller
// `end_run_tx` (0083 §3) has ever had.
//
//   deno test -A supabase/functions/_test/
//
// ═══ WHY THIS IS AN ACTION IN transition-booking AND NOT A NEW FUNCTION ═══
// Four things this needs already exist here and are already pinned: the guarded `req.json()`
// (`bad_body`), the party gate above the switch, the booking row load, and `notify()` with M2's
// lost-notification log line. A new function would be a second copy of all four, a second deploy
// target, and a second place for the party gate to drift. `start_run` — the same run's opening —
// is the precedent, and it lives here as its own module for the same reason this does: `Deno.serve`
// at index.ts's top level makes that file unimportable, so a testable arm is an extracted one.
//
// ═══ WHAT THIS FILE REFUSES TO DO ═══
// It does not settle. That is the whole re-sequencing: before this slice `runner/run.tsx` called
// `settle-run` at the stop and the booking went `active → completed` with the dog still on the
// leash. The stop now only FREEZES; money waits for the two return stamps (`confirm_return.ts`).
//
// It sends no clock (`start_run.ts`'s law, and 0083 §3 has no timestamp parameter either): the
// stop moment is the server's `now()` inside the freeze, never a claim that crossed the wire.
//
// It does not map `incident` or `owner_forced`. `end_run_tx` restricts `p_end_reason` to the four
// a runner may declare and raises `end_reason_not_runner_declarable` otherwise — that whitelist is
// a MONEY control (0083's header: an `incident` freeze hands the runner's own client a free run
// and pre-empts a review nobody opened; `owner_forced` bills the owner the full planned distance).
// This file passes the token through and lets the migration own the list; re-stating it here would
// be a second copy of a money rule.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { HttpError } from "../_shared/ctx.ts";

// deno-lint-ignore no-explicit-any
type Booking = Record<string, any>;
type Notify = (profileId: string, title: string, body: string) => PromiseLike<{ message: string } | null>;

/** The title the counterparty is asked with. Client contract: `app/src/lib/notification-route.ts`
 *  routes it (runner → `/runner/return-seal` · owner → the bid-scoped report) and
 *  `app/test/notification-route.test.cjs` reads THIS constant out of THIS file, so the two
 *  spellings cannot drift. Deliberately NOT 「인계 확인 요청」: that is the PICKUP ask, it belongs to
 *  `HANDOFF_TITLES`, and a club party tapping it is sent to the club session screen — a return ask
 *  routed there would land on a screen with no return CTA. */
export const RETURN_ASK_TITLE = "반환 확인 요청";

/** The four `runs.end_reason` tokens a runner may declare, as the CLIENT spells them. The mapping
 *  to the enum is the client's (`api.ts`); what this map is for is the refusal: a token that is not
 *  one of these never reaches the RPC, so the runner gets a sentence instead of a raw SQL error. */
const RUNNER_END_REASONS = ["completed", "dog_condition", "owner_request", "runner_personal"];

/** `end_run_tx`'s raises, each with its own status and its own Korean sentence. They fall through
 *  to a generic 500 otherwise, which reads like OUR bug and invites a retry — and retrying is the
 *  wrong instinct for every one of them. Same discipline as `settle-run/handler.ts:239-262`. */
function mapEndRunError(msg: string): HttpError {
  if (msg.includes("not_run_runner")) return new HttpError(403, "이 러닝의 담당 러너만 종료할 수 있어요");
  if (msg.includes("club_out_of_scope")) return new HttpError(400, "클럽 러닝은 이 경로로 종료할 수 없어요");
  if (msg.includes("not_active")) return new HttpError(409, "진행 중인 러닝이 아니에요");
  if (msg.includes("end_reason_not_runner_declarable")) {
    return new HttpError(400, "이 사유로는 종료할 수 없어요 — 사고·응급은 인계 절차로, 강제 종료는 운영자가 처리해요");
  }
  if (msg.includes("completed_needs_half_distance")) {
    return new HttpError(400, "완주로 종료하려면 계획 거리의 50% 이상 실측이 필요해요 — 조기 종료 사유를 골라주세요");
  }
  if (msg.includes("km_out_of_band")) return new HttpError(400, "실측 거리가 타당 범위를 벗어났어요 — 고객센터로 문의해주세요");
  if (msg.includes("condition_note_required")) return new HttpError(400, "컨디션 종료는 관찰한 내용을 적어야 해요");
  if (msg.includes("invalid_km")) return new HttpError(400, "실측 거리를 읽지 못했어요");
  if (msg.includes("invalid_duration")) return new HttpError(400, "러닝 시간을 읽지 못했어요");
  if (msg.includes("not_found")) return new HttpError(404, "booking not found");
  return new HttpError(409, msg);
}

export interface EndRunResult {
  unchanged: boolean;
  run_ended_at: string | null;
  actual_km?: number;
  end_reason?: string;
}

export async function endRun(
  db: SupabaseClient,
  args: {
    bookingId: string;
    uid: string;
    bk: Booking;
    // deno-lint-ignore no-explicit-any
    meta: Record<string, any> | null | undefined;
    notify: Notify;
  },
): Promise<EndRunResult> {
  const { bookingId, uid, bk, meta, notify } = args;
  // PARTY GATE BEFORE STATE GATE (house law), and before we read a single field of `meta`: a
  // stranger must learn nothing about which bookings exist or which reasons the server treats
  // specially. index.ts's gate already refused a non-party; this is the narrowing to THE RUNNER.
  if (bk.runner_id !== uid) throw new HttpError(403, "이 러닝의 담당 러너만 종료할 수 있어요");

  const m = meta ?? {};
  const endReason = String(m.end_reason ?? "");
  if (!RUNNER_END_REASONS.includes(endReason)) {
    throw new HttpError(400, "알 수 없는 종료 사유예요 — 앱을 최신 버전으로 업데이트한 뒤 다시 시도해주세요");
  }
  // `actual_km` is money (`compute_runner_payout` pays km × 3,000), so a missing or unreadable
  // value must be a refusal and never a coerced 0.
  // 🔴 THE NULL CHECK IS SEPARATE AND IS NOT REDUNDANT — caught by this file's own deno pin on its
  // first run. `Number(undefined)` is NaN and `Number.isFinite` refuses it, but **`Number(null)`
  // is 0**, which is finite — so a body with `actual_km: null` passed the finite check and would
  // have frozen a real run at ZERO DISTANCE, unsettleably (`completed_needs_half_distance`) or
  // for no money at all. An absent value and a measured zero are different facts and the
  // coercion silently merges them; `== null` catches both null and undefined before that happens.
  if (m.actual_km == null) throw new HttpError(400, "실측 거리를 읽지 못했어요");
  const km = Number(m.actual_km);
  if (!Number.isFinite(km)) throw new HttpError(400, "실측 거리를 읽지 못했어요");
  const durationRaw = m.duration_sec;
  const durationSec = durationRaw == null ? null : Number(durationRaw);
  if (durationSec !== null && !Number.isFinite(durationSec)) throw new HttpError(400, "러닝 시간을 읽지 못했어요");

  const { data, error } = await db.rpc("end_run_tx", {
    p_booking: bookingId,
    p_actual_km: km,
    p_duration_sec: durationSec,
    p_end_reason: endReason,
    p_condition_note: m.condition_note ?? null,
    // null means "I brought nothing new", never "erase what the run recorded" (0083 §3). The
    // trace is saved during the run by `saveRunTrace`; this argument exists for the last batch.
    p_trace: m.trace ?? null,
  });
  if (error) throw mapEndRunError(error.message ?? "");

  const res = (data ?? {}) as EndRunResult;
  // A SECOND STOP IS NOT AN EVENT. `end_run_tx` answers `{unchanged:true}` on a re-tap (a retry
  // after a lost response, a re-entry into the screen), and asking the owner twice for the same
  // return is how an inbox teaches people to ignore the ask that matters. The first call already
  // asked; the sweep's ⓑ-② alarm is what covers a lost one, not a duplicate here.
  if (!res.unchanged) {
    await notify(
      bk.owner_id,
      RETURN_ASK_TITLE,
      "러닝이 끝났어요 — 반려견을 받으면 앱에서 인계를 확인해주세요",
    );
  }
  return res;
}
