// collect-charges — the retry side of the post-pay machine (toss-plan §0-ter).
//
// TWO callers, two auth paths, one execution core (`_shared/charge.ts`):
//
//  ① the owner, with their own JWT and a booking_id — the single CTA on the debt screen. It is a
//     MANUAL retry: it ignores the attempt cap and `next_retry_at`, because the third ladder rung
//     is "stop and let a human act" and the human acting is precisely this request. A CTA that
//     refuses to do anything after the third failure is a dead button (CLAUDE.md honesty law).
//  ② the cron, with `X-Cron-Key` — the ladder sweep. Every row that is due gets one attempt, and
//     every long-dispatched pending gets ASKED ABOUT (the verification arm below).
//
// Batch mode NEVER 500s on one row: a single owner's dead card must not stop everyone else's
// collection. Each row's outcome is reported individually and the response is always 200.
//
// input:  owner mode `{ booking_id }` · cron mode: no body needed
// output: { mode, scanned?, due?, processed, results: [{ payment_id, order_id, outcome, error? }],
//           verified?: [{ payment_id, order_id, outcome, error? }] }
//
// ⚠ Deploy note: the cron calls this through `net.http_post` (0078's `dispatch_due_charges`), so
// the function is deployed with --no-verify-jwt and `X-Cron-Key` IS the authentication. The owner
// path still authenticates through `caller()` — the platform gateway is not what is gating it here.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, HttpError } from "../_shared/ctx.ts";
import { type ChargeOutcome, dispatchCharge, MAX_ATTEMPTS } from "../_shared/charge.ts";
import { tossGetByOrderId, type TossResult } from "../_shared/toss.ts";

/** One sweep's ceiling. The pilot's whole payments table is smaller than this; the cap exists so a
 * runaway backlog degrades into "several sweeps" instead of one request that never returns. */
const BATCH_LIMIT = 200;

/**
 * How long a dispatched pending is allowed to stay unexplained before the sweep asks Toss about it.
 * Under it, the row is simply in flight (the billing call's own ceiling is 10s). Over it, the
 * isolate that dispatched it is long gone and nobody is coming back — so we ask, rather than let
 * the row sit until a human runs the reconciliation query. Comfortably inside the 1h at which
 * `owner_has_unsettled_charge` starts counting a dispatched pending as debt: an outage must be
 * resolved by a machine before it becomes an owner's locked account.
 */
const VERIFY_AFTER_MS = 15 * 60_000;

interface RowResult {
  payment_id: string;
  order_id: string | null;
  outcome: ChargeOutcome | "error";
  error?: string;
}

/** The verification arm's vocabulary — deliberately NOT ChargeOutcome: nothing here charges a card.
 *  `redispatchable` = Toss never saw the order, so the dispatch marker was a lie and is now gone. */
interface VerifyResult {
  payment_id: string;
  order_id: string | null;
  outcome: "confirmed" | "redispatchable" | "unresolved" | "error";
  error?: string;
}

export async function collectCharges(req: Request, db: SupabaseClient) {
  const cronKey = req.headers.get("X-Cron-Key");
  if (cronKey !== null) {
    const expected = Deno.env.get("CRON_COLLECT_KEY");
    // An unset secret must never authenticate anybody. Without this line, `null === null` (or
    // ""==="") would turn a misconfigured deploy into an open batch-charging endpoint.
    if (!expected) throw new HttpError(503, "수금 배치가 설정되지 않았어요");
    if (cronKey !== expected) throw new HttpError(401, "unauthorized");
    return await runBatch(db);
  }
  return await runOwner(req, db);
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// ① owner mode — party gate before anything else
// ═══════════════════════════════════════════════════════════════════════════════════════════
async function runOwner(req: Request, db: SupabaseClient) {
  const uid = await caller(req, db);
  const body = await req.json().catch(() => ({}));
  const bookingId = body?.booking_id ?? body?.bookingId;
  // Scoped to one booking on purpose: the debt screen always knows which booking it is showing,
  // and "retry everything I owe" would be a much wider blast radius for the same button.
  if (!bookingId) throw new HttpError(400, "missing fields");

  // Party gate before the state gate (CLAUDE.md law) — otherwise "no charge to retry" tells a
  // stranger about someone else's booking. And ONE answer for "no such booking" and "not yours"
  // (0054:73, the create-booking-hold idiom): two different answers make this endpoint an
  // enumeration oracle over other people's booking ids, which is a worse leak than it sounds when
  // the id is also the thing a debt screen shows. A malformed uuid arrives as 0 rows, i.e. here.
  const { data: bk, error: bErr } = await db.from("bookings")
    .select("id, owner_id").eq("id", bookingId).maybeSingle();
  if (bErr) throw new HttpError(500, bErr.message);
  if (!bk || bk.owner_id !== uid) throw new HttpError(403, "forbidden");

  const { data: rows, error: pErr } = await db.from("payments")
    .select("id, booking_id, order_id, amount, status, raw")
    .eq("booking_id", bookingId).in("status", ["pending", "failed"]);
  if (pErr) throw new HttpError(500, pErr.message);

  // Only server-minted charge intents. A widget-era pending (no `raw.kind`) captured nothing and
  // is not something a billing key may complete behind the owner's back.
  const mine = (rows ?? []).filter((r) => !!(r.raw ?? {}).kind && r.amount > 0);
  const results: RowResult[] = [];
  for (const r of mine) {
    results.push(await attempt(db, r.id, r.order_id, { manual: true }));
  }
  return { mode: "owner", processed: results.length, results };
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// ② cron mode — the ladder sweep
// ═══════════════════════════════════════════════════════════════════════════════════════════
async function runBatch(db: SupabaseClient, now: Date = new Date()) {
  // The CANDIDATE predicate is in the query, not in TS: `raw->kind is not null` is the difference
  // between "200 rows of anything" and "200 rows we could actually collect". The widget era left
  // pending/failed rows behind that this function will never touch, and with a TS-only filter a
  // few hundred of them would fill BATCH_LIMIT and starve every real charge behind them — a
  // silent, permanent stall that looks exactly like "nothing was due". The ladder arithmetic stays
  // in TS below because it lives inside jsonb and is three-way; the volume no longer does.
  const { data, error } = await db.from("payments")
    .select("id, booking_id, order_id, amount, status, payment_key, raw")
    .in("status", ["pending", "failed"])
    .not("raw->kind", "is", null)
    .order("created_at", { ascending: true })
    .limit(BATCH_LIMIT);
  if (error) throw new HttpError(500, error.message);

  const rows = data ?? [];
  const due = rows.filter((r) => isDue(r, now));
  const results: RowResult[] = [];
  for (const r of due) {
    // One row's explosion is that row's result, never the batch's. Sequential on purpose: these
    // are card charges, and a burst of parallel billing calls is how a PG starts rate-limiting us.
    results.push(await attempt(db, r.id, r.order_id, { now }));
  }

  // ── the verification arm — the automatic resolver for "we do not know" ────────────────────
  // These rows are NOT due and must never be re-charged blind (§0-ter #2). But leaving them for a
  // human means one Toss outage turns into a pile of pendings that age into derived debt and lock
  // real owners out of booking. So: ask Toss what the order IS. The answer resolves the row, or
  // proves the charge never landed and hands it back to the ladder.
  const stale = rows.filter((r) => isStaleDispatched(r, now));
  const verified: VerifyResult[] = [];
  for (const r of stale) verified.push(await verifyDispatched(db, r as PendingRow, now));

  return {
    mode: "cron",
    scanned: rows.length,
    due: due.length,
    processed: results.length,
    results,
    verified,
  };
}

function isDue(r: { amount: number; status: string; raw: Record<string, unknown> | null }, now: Date): boolean {
  const raw = (r.raw ?? {}) as Record<string, unknown>;
  if (!raw.kind) return false; // widget-era rows are not ours to charge (the query already excludes them)
  if (!(r.amount > 0)) return false; // a zero row is a waive that never became one

  if (r.status === "pending") {
    // ONLY never-dispatched pendings (§0-ter #2). A dispatched pending means an HTTP call whose
    // answer we never heard; re-firing it blind is not a timer's call — it is the verification
    // arm's, below, which asks Toss first.
    return !raw.dispatched_at;
  }
  // failed → the ladder decides. ⚠ This predicate is a TWIN of 0078's SQL due-rule; they are
  // changed together or they disagree, and a disagreement here means either a charge that two
  // paths both attempt or one that neither does.
  if (raw.needs_card_relink) return false; // a dead key on a timer is three identical notifications
  if (Number(raw.attempts ?? 0) >= MAX_ATTEMPTS) return false; // spent; manual CTA only
  const next = raw.next_retry_at;
  // A MISSING next_retry_at is DUE, not exempt. That row shape is real: a pending intent the stale
  // sweep flipped to failed (the card-less owner who never got a rung written). Reading "no rung
  // scheduled" as "never collect" is how a real debt becomes invisible forever — the failure
  // direction to prefer is one extra attempt, which the attempt cap already bounds. An unparseable
  // timestamp goes the same way for the same reason.
  if (typeof next !== "string") return true;
  const at = Date.parse(next);
  return !Number.isFinite(at) || at <= now.getTime();
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// the verification arm
// ═══════════════════════════════════════════════════════════════════════════════════════════

interface PendingRow {
  id: string;
  order_id: string;
  amount: number;
  status: string;
  raw: Record<string, unknown> | null;
}

/** A pending that carries a dispatch marker older than the grace window — an unanswered charge. */
function isStaleDispatched(
  r: { amount: number; status: string; raw: Record<string, unknown> | null },
  now: Date,
): boolean {
  const raw = (r.raw ?? {}) as Record<string, unknown>;
  if (!raw.kind || r.status !== "pending" || !(r.amount > 0)) return false;
  const at = typeof raw.dispatched_at === "string" ? Date.parse(raw.dispatched_at) : NaN;
  return Number.isFinite(at) && at <= now.getTime() - VERIFY_AFTER_MS;
}

// Toss's "there is no such order" class. This is the ONLY answer that proves the charge never
// reached them — anything else (a 5xx, a timeout, an unparsable body) leaves the question open.
const NOT_FOUND_CODES = new Set(["NOT_FOUND_PAYMENT", "NOT_FOUND_PAYMENT_SESSION"]);
function isNotFound(res: TossResult): boolean {
  const code = typeof res.body?.code === "string" ? res.body.code : "";
  return !res.ok && (res.httpStatus === 404 || NOT_FOUND_CODES.has(code));
}

async function verifyDispatched(db: SupabaseClient, r: PendingRow, now: Date): Promise<VerifyResult> {
  const base = { payment_id: r.id, order_id: r.order_id };
  const raw = (r.raw ?? {}) as Record<string, unknown>;
  try {
    const look = await tossGetByOrderId(r.order_id);

    if (look.ok && look.body?.status === "DONE") {
      const paymentKey = typeof look.body.paymentKey === "string" ? look.body.paymentKey : "";
      const paid = Number(look.body.totalAmount);
      // The same three-way check `charge.ts` applies to a 2xx: a capture without a key cannot be
      // written confirmed (payments_settled_has_key), and a capture for a different number is a
      // dispute, not a collection.
      if (!paymentKey || (Number.isFinite(paid) && paid !== r.amount)) {
        const why = !paymentKey ? "no_payment_key" : `amount_${paid}_vs_${r.amount}`;
        await patchPending(db, r, { ...raw, needs_manual_review: true, last_error: `verify_${why}` }, now);
        console.error(`[collect-charges] verify: DONE but unusable payment=${r.id} order=${r.order_id} why=${why}`);
        return { ...base, outcome: "unresolved", error: why };
      }
      // The money DID move. Status + key in one statement (0076), CASed on pending so a dispatcher
      // that came back to life first wins instead of being overwritten.
      const { data: flipped, error } = await db.from("payments").update({
        status: "confirmed",
        payment_key: paymentKey,
        raw: { ...raw, charge: look.body, verified_at: now.toISOString() },
        updated_at: now.toISOString(),
      }).eq("id", r.id).eq("status", "pending").select("id");
      if (error) throw new Error(error.message);
      if (!flipped || flipped.length === 0) return { ...base, outcome: "unresolved", error: "row_moved" };
      return { ...base, outcome: "confirmed" };
    }

    if (isNotFound(look)) {
      // Toss has never heard of this order, so the request died before it arrived: nothing was
      // charged and nothing will be. The dispatch marker is now a false statement — clear it (and
      // ONLY it: `attempts` stays, because the attempt really was made and the ladder's budget is
      // a count of tries, not of successes). The row becomes a never-dispatched pending again and
      // the NEXT sweep dispatches it through the normal path.
      const cleared: Record<string, unknown> = { ...raw, last_error: `verify_not_found:${look.httpStatus}` };
      delete cleared.dispatched_at;
      const { error } = await db.from("payments")
        .update({ raw: cleared, updated_at: now.toISOString() })
        .eq("id", r.id).eq("status", "pending");
      if (error) throw new Error(error.message);
      return { ...base, outcome: "redispatchable" };
    }

    // Everything else — an order that exists but is not DONE, a 5xx, a refused credential. Still
    // "we do not know"; the row keeps its marker and reconciliation's third arm keeps it.
    const detail = `${look.httpStatus}:${typeof look.body?.code === "string" ? look.body.code : String(look.body?.status ?? "-")}`;
    await patchPending(db, r, { ...raw, last_error: `verify:${detail}` }, now);
    return { ...base, outcome: "unresolved", error: detail };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[collect-charges] verify payment=${r.id} threw: ${msg}`);
    return { ...base, outcome: "error", error: msg };
  }
}

/** Merge a raw patch onto a still-pending row. Non-fatal: the verdict above is the real output. */
async function patchPending(db: SupabaseClient, r: PendingRow, raw: Record<string, unknown>, now: Date) {
  const { error } = await db.from("payments")
    .update({ raw, updated_at: now.toISOString() })
    .eq("id", r.id).eq("status", "pending");
  if (error) console.error(`[collect-charges] verify patch failed payment=${r.id}: ${error.message}`);
}

async function attempt(
  db: SupabaseClient,
  paymentId: string,
  orderId: string | null,
  opts: { manual?: boolean; now?: Date },
): Promise<RowResult> {
  try {
    const res = await dispatchCharge(db, paymentId, opts);
    return { payment_id: paymentId, order_id: res.order_id, outcome: res.outcome, ...(res.error ? { error: res.error } : {}) };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[collect-charges] payment=${paymentId} threw: ${msg}`);
    return { payment_id: paymentId, order_id: orderId, outcome: "error", error: msg };
  }
}
