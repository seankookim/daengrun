// Telling OPS — **never the owner, never the runner.** An event nobody but an operator can act on
// does not belong in a customer's notification tray; it only delivers anxiety about a thing they
// cannot fix. The processing party here is a human, and that human is ops.
//
// ═══ Routing (Sean's ruling ③, 2026-08-13 — "build for full scale, not just for pilot") ═══
// The single `OPS_PROFILE_ID` env var becomes a table: `ops_recipients (profile_id, event_class,
// active)` (0084), read through `ops_recipients_for(p_event_class)`. "Full scale" is really about
// ROUTING, not plurality — one operator can own money while another owns safety, without a code
// change. Order of resort, and each step is load-bearing:
//   1. active rows for this event class → one notification per recipient;
//   2. ZERO rows (the honest answer of an empty/unprovisioned table) → the `OPS_PROFILE_ID` env
//      var, kept readable for exactly one release so a mis-provisioned table cannot SILENCE ops;
//   3. neither → `console.error`, loudly. Never a silent return. This is today's behaviour,
//      preserved exactly: the notification is speed, not the safety net — the real consumer of
//      these events is `payments_reconciliation()`, which finds the rows with or without a ping.
//
// ═══ ⚠ THE BODY CARRIES NO FINANCIAL DETAIL — deliberately (2026-08-13 hardening) ═══
// A recipient id is a raw uuid, in an env var or in a table row. A typo that still parses as a
// valid profile id delivers this notification to a REAL USER, and 0024's insert trigger pushes the
// body verbatim to their lock screen — i.e. one bad id turns an ops alert into another customer's
// order number and amount on a stranger's phone. Cross-checking the id with a second value only
// moves the question. Removing the payload removes the CLASS: the alert says WHAT happened and
// WHERE to look, while the identifiers stay in the caller's `console.error` (ops-only) and in
// `payments_reconciliation()`. A misdelivered alert is then merely confusing, never disclosing.
// `confirm_payment_test`'s "ops notification carries no financial detail" pins this.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/**
 * The routing vocabulary, shared with 0084's `ops_recipients.event_class` (its table comment
 * carries the same list). A class this file does not name cannot be routed, so adding an emitter
 * means adding it in both places.
 *
 * Only two of these are emitted from an edge function today (see COPY below). The other four are
 * `payments_reconciliation()` arms — SQL finds those rows; when a sweep grows the ability to ping
 * about them, it routes through here rather than inventing a second recipient rule.
 */
export type OpsEventClass =
  | "payment_manual_cancel"
  | "charge_ladder_exhausted"
  | "charge_dispatch_stale"
  | "settled_without_payment"
  | "enroute_comp_failed"
  | "late_comp_failed"
  | "incident_waive_pending";

interface OpsCopy {
  title: string;
  body: string;
}

/**
 * Per-class copy. Redacted by construction (see the header): every string here must survive being
 * read by a stranger. Partial on purpose — a class with no bespoke copy gets the generic line
 * below rather than an entry written in advance for an emitter that does not exist yet.
 */
const COPY: Partial<Record<OpsEventClass, OpsCopy>> = {
  payment_manual_cancel: {
    title: "결제 자동 취소 실패 — 수동 취소 필요",
    body: "payments_reconciliation()에서 orphan_capture 행을 확인해주세요 (주문번호·금액은 조정 질의에 있어요)",
  },
  enroute_comp_failed: {
    title: "이동 중 취소 보상 기록 실패 — 수동 확인 필요",
    body:
      "러너 보상이 원장에 기록되지 않은 취소 건이 있어요 — 서버 로그에서 booking 을 확인하고 record_enroute_cancel_comp 를 다시 실행해주세요",
  },
  // [0085 ⑩] Its own class, and the reason is not tidiness. The two comp writers gate on
  // DIFFERENT cancel_reason markers (0080:1137 refuses anything that is not
  // 'owner_cancel_enroute'), so an operator told to re-run the en-route function against a
  // LATE-tier booking runs a no-op, the alert reads as handled, and the runner is never paid.
  // A remedy that refuses by design is worse than no remedy: it closes the queue item.
  late_comp_failed: {
    title: "취소 보상 기록 실패 (24시간 이내 취소) — 수동 확인 필요",
    body:
      "러너 배분이 원장에 기록되지 않은 취소 건이 있어요 — 서버 로그에서 booking 을 확인하고 record_late_cancel_share 를 다시 실행해주세요",
  },
};

/**
 * The class name is an internal identifier, not a customer's data — safe on a stranger's lock
 * screen under the redaction rule, and the only handle that makes a generic ping actionable.
 */
function generic(eventClass: OpsEventClass): OpsCopy {
  return {
    title: "운영 확인이 필요한 이벤트가 있어요",
    body: `payments_reconciliation()에서 ${eventClass} 항목을 확인해주세요 (식별자·금액은 조정 질의와 서버 로그에 있어요)`,
  };
}

/**
 * Notify every ops recipient subscribed to `eventClass`.
 *
 * Non-fatal by construction: callers reach this on a path where something has ALREADY happened
 * (money captured, a cancel committed), so throwing from here would turn a recorded event into a
 * 500 and hand the customer a sentence that is not true. Every failure inside is a log line.
 *
 * `refId` is a bare uuid with no meaning outside our own tables and is never rendered in the push
 * body — it exists so the ops surface has a handle to open.
 */
export async function notifyOps(
  db: SupabaseClient,
  eventClass: OpsEventClass,
  opts: { refId?: string | null } = {},
): Promise<void> {
  const copy = COPY[eventClass] ?? generic(eventClass);
  let recipients = await recipientsFor(db, eventClass);

  if (recipients.length === 0) {
    const env = Deno.env.get("OPS_PROFILE_ID");
    if (!env) {
      console.error(
        `[ops] ${eventClass}: no ops_recipients row and OPS_PROFILE_ID unset, no notification sent`,
      );
      return;
    }
    recipients = [env];
  }

  const { error } = await db.from("notifications").insert(
    recipients.map((profile_id) => ({
      profile_id,
      kind: "system",
      title: copy.title,
      body: copy.body,
      ref_id: opts.refId ?? null,
    })),
  );
  if (error) {
    console.error(`[ops] ${eventClass}: notify failed for ${recipients.length} recipient(s): ${error.message}`);
  }
}

/**
 * `ops_recipients_for` returns `setof uuid`, which PostgREST hands back as an array of bare
 * strings; tolerate the object-per-row shape too, the same way the mint callers tolerate both
 * `returns table(...)` shapes.
 *
 * An RPC ERROR is treated as "no routing rows", NOT as a reason to stop: the whole point of
 * keeping the env fallback for a release is that a routing table which cannot be read (missing
 * migration, permission drift, a transient) must never be the thing that silences ops. It is
 * logged, because a routing table that stopped answering is itself an operational fact.
 */
async function recipientsFor(db: SupabaseClient, eventClass: OpsEventClass): Promise<string[]> {
  const { data, error } = await db.rpc("ops_recipients_for", { p_event_class: eventClass });
  if (error) {
    console.error(`[ops] ${eventClass}: ops_recipients_for failed (${error.message}) — falling back to OPS_PROFILE_ID`);
    return [];
  }
  const rows = Array.isArray(data) ? data : data == null ? [] : [data];
  return rows
    .map((r) => (typeof r === "string" ? r : r && typeof r === "object" ? Object.values(r)[0] : null))
    .filter((v): v is string => typeof v === "string" && v.length > 0);
}
