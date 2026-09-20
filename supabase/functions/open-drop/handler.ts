// 드랍 오픈 — 보급 상자 열기 / 픽 드랍 선택 적용. The WORK is `open_drop_tx` (0176), one SQL
// transaction; this file is its wiring and nothing else.
// input:  { drop_id, pick_choice? }  (pick 드랍은 choice 필수: boost | miles | gear)
// output: { applied: {...} } — the RPC's bare object, RE-WRAPPED. `api.ts` (openDrop) unwraps exactly
//         one level, so returning the bare object would silently re-open audit M4: every alert
//         would read 「보상이 적용됐어요」 again, and no gate can see that shape. The envelope test in
//         `_test/open_drop_test.ts` is the guard.
//
// ═══ WHAT MOVED INTO THE DATABASE, AND WHY THIS FILE NO LONGER HAS ARMS ═══
// The previous handler read the drop, gated party/state/choice itself, stamped `opened_at` through a
// consuming CAS, and THEN paid miles / card / gear / boost in separate PostgREST statements — so one
// failed writer burned the drop for good (backend audit 2026-09-17 · H2; 0106 §3 freezes
// `opened_at`), and the best this file could do was REPORT the loss (`failed`, an `error` beside
// `applied` in a 200). `open_drop_tx` does the gates, the CAS and every reward in one transaction —
// any raise rolls the stamp back — and suite 207 (0176-O1…O7) owns that behaviour. Keeping a copy of
// the gates or the writers here would be a second product surface for the same decision, judged by
// different code; so there is none. What stays is what only an edge can do: validate the caller's
// JWT, refuse a malformed body, bind the RPC to the CALLER, and translate the refusal tokens.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, callerBoundClient, HttpError, internalError } from "../_shared/ctx.ts";

/**
 * Preserve the RPC's user-facing detail and keep its token separately for diagnostics.
 * These sentences are fallbacks for mapped refusals without a detail.
 */
export const RPC_TOKEN_MAP: Record<string, { status: number; message: string }> = {
  not_signed_in: { status: 401, message: "로그인이 필요해요" },
  drop_not_found: { status: 404, message: "드랍을 찾을 수 없어요" },
  not_drop_owner: { status: 403, message: "내 드랍만 열 수 있어요" },
  already_opened: { status: 409, message: "이미 열린 드랍이에요" },
  bad_pick_choice: { status: 400, message: "보상을 하나 골라 주세요" },
  drop_pays_nothing: { status: 409, message: "이 드랍에는 보상이 없어요 — 관리자 확인이 필요해요" },
};

export async function openDrop(
  req: Request,
  db: SupabaseClient,
  mkUserDb: (req: Request) => SupabaseClient = callerBoundClient,
) {
  // The JWT is validated here, against the service client, before anything else: a bad token is a
  // 401 `unauthorized`, not whatever shape a downstream refusal would take.
  const uid = await caller(req, db);

  // A malformed or absent body is the CALLER's mistake, so it must not wear our 500 (audit · M1).
  const { drop_id, pick_choice } = await req.json().catch(() => {
    throw new HttpError(400, "bad_body");
  }) ?? {};
  if (!drop_id) throw new HttpError(400, "missing drop_id");

  // ═══ THE CALL — through the CALLER's client, never `db` ═══
  // `open_drop_tx` is granted to `authenticated` only and its subject is `auth.uid()`; called with
  // the service key it has no subject (0176 revokes service_role outright → 42501). The user-bound
  // client makes the RPC's own party gate the one that decides, as 0077's caller doctrine requires.
  // `pick_choice` absent → NULL: a mini takes no choice and the RPC refuses a stray one.
  const userDb = mkUserDb(req);
  const { data, error } = await userDb.rpc("open_drop_tx", {
    p_drop_id: drop_id,
    p_pick_choice: pick_choice ?? null,
  });

  if (error) {
    const mapped = RPC_TOKEN_MAP[error.message];
    if (mapped) throw new HttpError(mapped.status, error.details || mapped.message, error.message);
    // Anything else — a permission error from a mis-wired key, a network failure, a Postgres text
    // no token covers — is OURS, and its sentence stays in the log (audit · L1).
    throw internalError(
      { message: `drop=${drop_id} runner=${uid} open_drop_tx: ${error.message}` },
      "open_drop_tx",
    );
  }
  // A success with no object is not a receipt anyone may render (the honesty law: bind real fields
  // or omit). The RPC always returns a jsonb object; if that ever stops being true, fail closed.
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw internalError(
      { message: `drop=${drop_id} runner=${uid} open_drop_tx returned a non-object: ${JSON.stringify(data)}` },
      "open_drop_tx:shape",
    );
  }

  return { applied: data as Record<string, unknown> };
}
