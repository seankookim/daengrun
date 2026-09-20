// `confirm_return` — ⑪'s two-stamp return, and the door ⑫'s work gate opens behind.
//
//   deno test -A supabase/functions/_test/
//
// ═══ §1 THE SIDE IS DERIVED, NEVER TAKEN FROM THE BODY — this is the security core ═══
// `confirm_return_tx` has two caller classes (0083 §6): a JWT-bearing CLIENT must BE the side it
// claims, and a SERVER caller (service_role, `auth.uid()` NULL) "has already authenticated its
// user". This file is the second class — `transition-booking` uses `admin()` — so the migration's
// own party gate is BYPASSED here by design, and the authentication it trusts is the line below.
//
// 🔴 Therefore `p_side` MUST be computed from the verified `uid` against the booking's two party
// columns, and a `meta.side` must never be read. Taking the side from the body would let the
// runner post `side: 'owner'` and produce BOTH stamps alone — which seals, and the seal settles.
// That is precisely the outcome Sean's 0089 ruling forbids ("the confirmation must happen with
// both parties and never just the runner") and it would arrive through the one path where the SQL
// gate cannot see it. Pinned: `run_end_ceremony_test.ts`, three ways.
//
// ═══ §2 THE PRICE RIDES WITH THE STAMP, SO THE SECOND STAMP SETTLES IN ONE TRANSACTION ═══
// `p_quote` exists so a server-class caller can settle inside the SAME locked transaction as the
// stamp that sealed it (0083 §6 ④). We compute it on EVERY call, not only when we think this
// stamp will be the second one: "am I second?" answered outside the row lock is a TOCTOU, and a
// first stamp carrying a quote is harmless — `confirm_return_tx` reaches `_settle_sealed_run`
// only under `v_both`.
//
// The consequence is the thing the re-sequencing needed: there is NO WINDOW between the stamp and
// the settlement for a client to die in. A phone that loses power the instant after its tap has
// already had its run settled by the server, or has written nothing at all.
//
// 🔴 THIS PARAGRAPH USED TO SAY THE HOLE WAS UNREACHABLE, AND THAT WAS THE WRONG ARGUMENT.
// It read: a caller bypassing the app can stamp directly and seal without a price, "but it is
// unreachable through every product surface this slice ships". That is a claim about our BUTTONS;
// the door was the API. `confirm_return_tx` is in `public` and was granted to `authenticated`,
// and PostgREST exposes `public` — `api.ts` proves the shape works by calling `runner_work_gate`
// exactly that way — so any signed-in party could POST the RPC with the shipped anon key and
// their own JWT, and if theirs was the SECOND stamp the row sealed with no settlement and no
// in-app repair (both stamps exist ⇒ every confirm CTA is gone by construction).
// 0188 §B REVOKES the grant from `authenticated`; pinned by 219 `0188-D1`, with a positive arm
// asserting `service_role` still holds it, because a revoke that caught the server's grant would
// strand every settlement and would look identical from inside the negative arm alone.
// A server caller can still seal-now-settle-later — that capability is 0083 §6's design and
// suite 133 exists to detect its residue; what is closed is a PHONE being the stamp that seals.
//
// ═══ §3 `incident_review` ═══
// 0096 lets a party stamp from `incident_review` and deliberately does NOT seal or settle there.
// This file does not second-guess that: it passes the quote, and the migration ignores it under
// `v_may_settle`. The response's `case_open` is what the client renders.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { HttpError } from "../_shared/ctx.ts";
import { RETURN_ASK_TITLE } from "./end_run.ts";

// deno-lint-ignore no-explicit-any
type Booking = Record<string, any>;
type Notify = (profileId: string, title: string, body: string) => PromiseLike<{ message: string } | null>;

/** Both parties are told when the pair completes. Routed by `notification-route.ts` exactly like
 *  the ask; read by `app/test/notification-route.test.cjs` out of THIS file. */
export const RETURN_SEALED_TITLE = "반환 확인 완료";

/** `confirm_return_tx`'s raises. `not_party` is reported as a 403 with no detail about the
 *  booking: this endpoint must not become an oracle for which bookings exist. */
function mapConfirmError(msg: string): HttpError {
  if (msg.includes("not_party")) return new HttpError(403, "이 예약의 당사자만 인계를 확인할 수 있어요");
  if (msg.includes("club_out_of_scope")) return new HttpError(400, "클럽 위탁은 이 경로로 확인할 수 없어요");
  if (msg.includes("run_not_ended")) return new HttpError(409, "아직 러닝이 끝나지 않았어요 — 러너가 종료하면 확인할 수 있어요");
  if (msg.includes("not_active")) return new HttpError(409, "지금은 인계를 확인할 수 없는 예약이에요");
  if (msg.includes("quote_from_client")) return new HttpError(500, "정산 가격 전달 경로가 잘못됐어요 — 담당자에게 알려주세요");
  if (msg.includes("settle_quote_malformed")) return new HttpError(500, "정산 금액을 계산하지 못했어요 — 잠시 뒤 다시 시도해주세요");
  if (msg.includes("run_freeze_incomplete") || msg.includes("run_stop_not_recorded")) {
    return new HttpError(409, "러닝 종료 기록이 온전하지 않아요 — 담당자가 확인해야 해요");
  }
  if (msg.includes("not_found")) return new HttpError(404, "booking not found");
  return new HttpError(409, msg);
}

export interface ConfirmReturnResult {
  stamped: boolean;
  sealed: boolean;
  settled: boolean;
  unchanged: boolean;
  both_confirmed?: boolean;
  case_open?: boolean;
  /** which side the SERVER decided this caller is — echoed so the client never has to guess, and
   *  so a test can see the derivation rather than infer it from a write. */
  side: "runner" | "owner";
}

/**
 * The quote for THIS booking, priced from the numbers the stop froze.
 *
 * Every input is the server's: `runs.actual_km` / `runs.end_reason` are what `end_run_tx` wrote
 * and `_settle_sealed_run` re-reads under the lock, and the commission is the runner's row. The
 * `0.33` fallback is `settle-run/handler.ts:152`'s, quoted rather than re-chosen — a missing
 * `runners` row must not under-charge commission (0059 policy).
 *
 * Returns null when the run is not frozen enough to price, or when pricing failed. The caller
 * turns a null into a 503 whenever `run_ended_at` is set — see the refusal below, and read its
 * comment before "optimising" it back to only-when-sealing.
 */
async function quoteFor(
  db: SupabaseClient,
  bookingId: string,
  runnerId: string | null,
): Promise<Record<string, number> | null> {
  const { data: run } = await db.from("runs").select("actual_km, end_reason").eq("booking_id", bookingId).maybeSingle();
  if (!run || run.actual_km == null || run.end_reason == null) return null;
  const { data: runner } = runnerId
    ? await db.from("runners").select("commission_rate").eq("profile_id", runnerId).maybeSingle()
    : { data: null };
  const commission = Number(runner?.commission_rate ?? 0.33);
  const { data: po, error } = await db.rpc("compute_runner_payout", {
    p_booking: bookingId,
    p_end_reason: String(run.end_reason),
    p_actual_km: Number(run.actual_km),
    p_commission: commission,
  });
  if (error) {
    // FAIL CLOSED, loudly. Nothing is written yet, so a refusal costs a retry while carrying on
    // without a price would commit a seal that no sweep can settle (§2). There is deliberately no
    // fallback arithmetic to carry on WITH — `settle-run/handler.ts:189-193`'s rule.
    console.error(`[transition-booking] confirm_return quote failed booking=${bookingId}: ${error.message}`);
    return null;
  }
  const row = (Array.isArray(po) ? po[0] : po) as Record<string, number> | null | undefined;
  if (!row) return null;
  // `_settle_sealed_run` validates these five as JSON numbers and raises `settle_quote_malformed`
  // otherwise; PostgREST can hand an int back as a string, so they are coerced HERE rather than
  // discovered inside the transaction.
  return {
    base: Number(row.base),
    distance_pay: Number(row.distance),
    addon_pay: Number(row.addon),
    guarantee: Number(row.guarantee),
    fee: Number(row.fee),
  };
}

export async function confirmReturn(
  db: SupabaseClient,
  args: { bookingId: string; uid: string; bk: Booking; notify: Notify },
): Promise<ConfirmReturnResult> {
  const { bookingId, uid, bk, notify } = args;

  // ── §1 THE SIDE, DERIVED ────────────────────────────────────────────────────────────────
  const isRunner = bk.runner_id === uid;
  const isOwner = bk.owner_id === uid;
  // Both at once is impossible in data and would be ambiguous in law; refuse rather than pick.
  if (isRunner && isOwner) throw new HttpError(409, "이 예약의 보호자와 러너가 같아요 — 담당자가 확인해야 해요");
  if (!isRunner && !isOwner) throw new HttpError(403, "이 예약의 당사자만 인계를 확인할 수 있어요");
  const side: "runner" | "owner" = isRunner ? "runner" : "owner";

  // ── §2 THE PRICE ────────────────────────────────────────────────────────────────────────
  // Read the CURRENT stamps to know whether this call can seal. This is a hint, not a gate: the
  // authority is `confirm_return_tx`'s `v_both` under the row lock. It is used for one thing —
  // refusing to seal without a price — and it is deliberately conservative: a stale read that says
  // "not sealing" when it will seal is caught by the migration ignoring a null quote, and the row
  // is then reported by arm ⓐ rather than silently settled at a guessed number.
  // 🔴 [cold review #6] THE REFUSAL IS UNCONDITIONAL ON A FROZEN RUN, and the first version's
  // `sealsNow` guard was the bug. It read the counterparty's stamp from `bk` — a SNAPSHOT taken by
  // `index.ts` before this function ran — and refused only when that snapshot already said this
  // call would seal. In the direction that matters the snapshot is stale the other way: it says
  // the counterparty has NOT stamped, they stamp between the read and the RPC, `sealsNow` is
  // false, a pricing failure sails past the guard, `p_quote` arrives NULL, and
  // `confirm_return_tx` writes the durable seal with no settlement — exactly the state the 503
  // exists to prevent, reached by the one path the 503 could not see. A guard conditioned on a
  // stale read of the very race it guards against is not a guard.
  //
  // So: if the run is frozen (`run_ended_at`), a missing price is a refusal, full stop. The cost
  // is that a FIRST stamp is also refused during a pricing outage — which is the right trade:
  // a refused stamp is a retry, and a sealed-unsettled row is unrepairable from inside the app.
  const quote = await quoteFor(db, bookingId, bk.runner_id ?? null);
  if (bk.run_ended_at && !quote) {
    throw new HttpError(503, "정산 금액을 계산하지 못했어요 — 잠시 뒤 다시 확인해주세요 (기록은 그대로예요)");
  }

  const { data, error } = await db.rpc("confirm_return_tx", {
    p_booking: bookingId,
    p_side: side,
    p_quote: quote,
  });
  if (error) throw mapConfirmError(error.message ?? "");
  const res = { ...((data ?? {}) as Record<string, unknown>), side } as unknown as ConfirmReturnResult;

  // ── §3 TELL THE OTHER SIDE ──────────────────────────────────────────────────────────────
  // Only on a stamp that actually landed: `stamped:false` is a re-tap, and a re-tap must not push.
  if (res.stamped) {
    const counterparty = side === "runner" ? bk.owner_id : bk.runner_id;
    if (res.sealed || res.both_confirmed) {
      // The pair is complete. The party who just tapped knows; the one who stamped FIRST is the
      // one waiting on a screen, so they are the one told.
      if (counterparty) {
        await notify(
          counterparty,
          RETURN_SEALED_TITLE,
          res.settled
            ? "양측 인계 확인이 끝났어요 — 러닝이 마무리됐어요"
            : "양측 인계 확인이 끝났어요 — 정산은 담당자 확인 뒤에 진행돼요",
        );
      }
    } else if (counterparty) {
      await notify(
        counterparty,
        RETURN_ASK_TITLE,
        side === "runner"
          ? "러너가 반려견을 돌려줬다고 확인했어요 — 받으셨으면 앱에서 확인해주세요"
          : "보호자가 반려견을 돌려받았다고 확인했어요 — 앱에서 확인해주세요",
      );
    }
  }
  return res;
}
