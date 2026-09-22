// `resolve_return` — the OPS door out of a stranded return. 0193 §C-b's edge half.
//
//   deno test --allow-all --node-modules-dir=auto _test
//
// ═══ §1 WHY THIS ACTION EXISTS AT ALL ═══
// Codex A1/A2 on 0188: a return where one party never stamps sits `active` forever (one alarm at
// two hours, then silence) and a return NOBODY stamps is escalated to `incident_review`, from which
// 0066:56 gives exactly one exit and `_settle_sealed_run` is `active`-only. In both shapes the
// runner walked the dog, brought it home, and cannot be paid. The remedy 0096 §7 names —
// `force_return_tx` — has had ZERO callers since it shipped, so the only exit was a human typing
// SQL against production. This is the caller.
//
// ═══ §2 THE ACTOR IS DERIVED, NEVER TAKEN FROM THE BODY — `confirm_return.ts` §1's law ═══
// `transition-booking` talks to the database as `admin()` (service_role), so `auth.uid()` inside
// `ops_resolve_return_tx` is NULL and the migration cannot see who asked. It therefore takes the
// ops profile id as an argument — and that argument MUST be the `uid` this function was handed by
// `caller(req, db)`, which verified the JWT. Reading an id out of `meta` would let anyone name an
// operator and settle any stranded booking they liked. The roster check itself stays in SQL
// (`ops_recipients_for('return_strand')`), so this file decides nothing about who is ops.
//
// ═══ §3 THE PRICE IS COMPUTED EXACTLY AS `confirm_return` COMPUTES IT ═══
// `quoteFor` is imported rather than re-implemented: one pricing read, from the frozen `runs` row,
// through `compute_runner_payout`, with `settle-run/handler.ts:152`'s commission fallback. A second
// copy here would be a second money rule that drifts. The RPC REQUIRES the quote (`quote_required`)
// — a resolution with no price writes a seal and no settlement, which is the state this whole slice
// exists to make unreachable.
//
// ═══ §4 THE PARTY GATE ABOVE THE SWITCH DOES NOT APPLY, AND THAT IS DELIBERATE ═══
// `index.ts` refuses a non-party for every action but `runner_accept`. An operator is by definition
// not a party to the booking they are resolving, so this action is named in that exception — and
// the gate it trades for is STRICTER, not looser: the SQL refuses everyone who is not on the
// `return_strand` roster (`not_ops`), before it reads a single field of the booking, so a stranger
// cannot even learn that the booking exists.
//
// 🔴 [0201 §C, codex 2026-09-22 #5] THAT ARGUMENT WAS TRUE OF THE SQL AND FALSE OF THE EDGE, and
// the gap was worth a real probe: `index.ts` read the booking and this file priced it, both ahead
// of the only membership check there was, so one stranger identity got **503** for an unpriceable
// run and **403 not_ops** for a priceable one — an oracle for any booking id, plus free privileged
// pricing. `index.ts` now calls `ops_is_member('return_strand', uid)` BEFORE the booking read, so
// a non-operator never reaches this file at all and every booking id answers identically.
// ⚠ NOTHING HERE WAS REMOVED. The SQL gate inside `ops_resolve_return_tx` is still the rule and
// `mapResolveError`'s `not_ops` arm still stands: the edge check is an earlier refusal, and an
// earlier refusal that replaced the real one would be the same mistake wearing a fix's costume.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { HttpError } from "../_shared/ctx.ts";
import { quoteFor } from "./confirm_return.ts";
import { collectAfterSettle } from "../_shared/charge.ts";

/** `ops_resolve_return_tx`'s raises, each with its own status and its own sentence. `not_ops` is a
 *  403 that says nothing about the booking: this endpoint must not become an oracle for which
 *  bookings are stranded. */
function mapResolveError(msg: string): HttpError {
  if (msg.includes("not_ops") || msg.includes("not_party") || msg.includes("ops_actor_required")) {
    return new HttpError(403, "담당자만 반환을 대신 정리할 수 있어요");
  }
  if (msg.includes("memo_required")) return new HttpError(400, "무엇을 확인했는지 적어주세요 — 판정에는 기록이 필요해요");
  if (msg.includes("club_out_of_scope")) return new HttpError(400, "클럽 위탁은 이 경로로 정리할 수 없어요");
  if (msg.includes("run_not_ended")) return new HttpError(409, "아직 러닝이 끝나지 않았어요");
  if (msg.includes("already_sealed")) {
    return new HttpError(409, "이미 봉인된 예약이에요 — 정산 재구동이 필요해요 (담당자 확인)");
  }
  if (msg.includes("not_resolvable")) return new HttpError(409, "지금은 이 경로로 정리할 수 없는 예약이에요");
  if (msg.includes("quote_required") || msg.includes("settle_quote_malformed")) {
    return new HttpError(503, "정산 금액을 계산하지 못했어요 — 잠시 뒤 다시 시도해주세요 (기록은 그대로예요)");
  }
  if (msg.includes("run_freeze_incomplete") || msg.includes("run_stop_not_recorded")) {
    return new HttpError(409, "러닝 종료 기록이 온전하지 않아요 — 정산할 수 없어요");
  }
  if (msg.includes("not_found")) return new HttpError(404, "booking not found");
  return new HttpError(409, msg);
}

export interface ResolveReturnResult {
  resolved: boolean;
  settled: boolean;
  unchanged: boolean;
  resolution_id?: string;
  from_status?: string;
  runner_stamped?: boolean;
  owner_stamped?: boolean;
}

export async function resolveReturn(
  db: SupabaseClient,
  args: { bookingId: string; uid: string; bk: Record<string, unknown>; meta: Record<string, unknown> | null | undefined },
): Promise<ResolveReturnResult> {
  const { bookingId, uid, bk, meta } = args;
  const memo = typeof meta?.memo === "string" ? meta.memo : "";
  // Refused HERE as well as in SQL, and the two are not redundant: this one gives the operator a
  // sentence before a round trip, and the SQL one is the rule. Neither is the other's evidence.
  if (!memo.trim()) throw new HttpError(400, "무엇을 확인했는지 적어주세요 — 판정에는 기록이 필요해요");

  const priced = await quoteFor(db, bookingId, (bk.runner_id as string | null) ?? null);
  if (!priced) {
    // FAIL CLOSED. A resolution with no price is a seal with no settlement — the exact shape 0193
    // §B closed on the party path — so the refusal is the correct outcome, not a degradation.
    console.error(`[transition-booking] resolve_return quote failed booking=${bookingId}`);
    throw new HttpError(503, "정산 금액을 계산하지 못했어요 — 잠시 뒤 다시 시도해주세요 (기록은 그대로예요)");
  }

  const { data, error } = await db.rpc("ops_resolve_return_tx", {
    p_booking: bookingId,
    p_quote: priced.quote,
    p_memo: memo.trim(),
    // §2 — the VERIFIED caller, never a value from the body.
    p_actor: uid,
  });
  if (error) throw mapResolveError(error.message ?? "");
  const res = (data ?? {}) as ResolveReturnResult;

  // COLLECTION — the same half, through the same shared function `confirm_return` uses, gated the
  // same way. `settled && !unchanged` rather than `settled` alone: a re-call on an already-completed
  // booking answers `{resolved:false, settled:true, unchanged:true}` and must not dispatch a second
  // `pending` charge row. Nothing here can change the response or throw upward — settlement never
  // waits on collection (`settle-run`'s ordering law).
  if (res.settled && !res.unchanged) {
    try {
      const collected = await collectAfterSettle(db, bookingId, priced.endReason, priced.actualKm);
      console.log(
        `[transition-booking] resolve_return collection booking=${bookingId} ` +
          `collection=${collected.collection} detail=${collected.detail}`,
      );
    } catch (e) {
      console.error(
        `[transition-booking] resolve_return collection threw past its own catch booking=${bookingId}: ` +
          (e instanceof Error ? e.message : String(e)),
      );
    }
  }
  console.log(
    `[transition-booking] resolve_return booking=${bookingId} by=${uid} from=${res.from_status} ` +
      `settled=${res.settled} resolution=${res.resolution_id}`,
  );
  return res;
}
