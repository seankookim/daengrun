// In-app account deletion (App Store 5.1.1(v) · PIPA 제37조) — the half that cannot be SQL.
// input:  { confirm: "DELETE" }   ⚠ NO user id. The uid comes from the JWT and from nowhere else.
// out:    { ok, tombstoned, already, storage_removed, auth_deleted, deleted, forfeited, kept,
//           bank_kept }
//
// ═══ WHY THIS IS SPLIT AND NOT ONE THING ══════════════════════════════════════════════════
// The `auth.users` row can only be removed by the Auth admin API — there is no in-database call
// for it — so a definer RPC alone would leave a credentialed, signable-into account behind,
// which fails 5.1.1(v)'s "delete, not deactivate" limb. Equally an edge-function-only design is
// wrong: the SQL half is a dozen writes that must be atomic, and edge functions have no
// transaction. Hence the split, which is also the house shape (start_run → start_run_tx).
//
//   verify JWT → uid                     here (only place with the request)
//   state gate + tombstone + deletes     delete_my_account_tx, ONE transaction
//   enumerate + remove storage objects   here — `storage.protect_delete` raises 42501 even for
//                                        service_role, so a definer RPC CANNOT delete an object
//                                        (and a raise mid-transaction would roll back a
//                                        half-done deletion)
//   auth.admin.deleteUser(uid)           here
//
// ═══ ORDER IS STORAGE BEFORE AUTH, AND THE REASON MATTERS (F14) ═══════════════════════════
// The old rationale was "after the auth user is gone the JWT that authorised the enumeration is
// dead." **That is false**: both the enumeration and the removal run on `admin()`, a service-role
// client holding no user JWT at all (`_shared/ctx.ts:22-27`). The caller's JWT is used ONCE, by
// `caller()`, to establish `uid`, and never touched again — deleting the auth user does not
// revoke it. The rule is still right for a different reason: **orphan avoidance.** Storage
// objects are keyed by `{uid}/` and nothing else — no owner column, no FK, no trigger, no cascade
// from `auth.users` into `storage.objects`. Once the auth row is gone, `uid` survives only in the
// tombstoned `profiles.id` and in this function's local variable; if the process dies between the
// auth delete and the sweep, those objects are unreferenced bytes only a manual prefix scan will
// ever find. Storage-first makes the worst case "objects removed, auth delete retried" — which
// the retry path below handles — instead of "account gone, objects orphaned forever", which
// nothing handles.
//
// ═══ 🔴 THE SWEEP SET IS FOUR PREFIXES, NOT `{uid}/%` (F5) ════════════════════════════════
// Every object a user owns lives under `{uid}/` in both buckets, so `{uid}/%` is the obvious
// sweep unit and it is WRONG. Three of the five writer prefixes are the media half of rows this
// deletion KEEPS:
//     {uid}/runs/**       run evidence hanging off KEEP `runs`/`bookings`
//     {uid}/chat/**       `chat_messages.media_path` — KEEP, body deliberately not nulled
//     {uid}/clubchat/**   `club_chat_messages.media_path` — same
// Removing one of those leaves a kept row pointing at an object that is gone: a message that
// renders as a broken image, a run whose photos 404. That is the SET NULL mutilation the whole
// contract condemns, reached from the storage side — the row still READS as valid evidence and
// silently is not.
//
// ⚠ The enumeration is therefore folder-scoped, not pattern-scoped, and that is a deliberate
// structural choice rather than a filter: this function never LISTS runs/chat/clubchat, so no
// bug in a predicate can reach them. At the `avatars/{uid}` root it removes `avatar.jpg` BY NAME
// and nothing else, because `{uid}/club-{id}.jpg` also lives there (0064:9-15) and is a club's
// photo, not this user's identity.
//
// ═══ NO CORS ═══ zero hits for cors|Access-Control|OPTIONS across supabase/functions. The
// client is React Native via `functions.invoke`. Do not add CORS.
import { caller, HttpError } from "../_shared/ctx.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/** The complete deletable set. Anything not named here survives, on purpose. */
export const SWEEP: ReadonlyArray<{ bucket: string; folder: string; only?: string }> = [
  { bucket: "avatars", folder: "", only: "avatar.jpg" }, // {uid}/avatar.jpg — by name, see above
  { bucket: "avatars", folder: "gallery" }, //             {uid}/gallery/**
  { bucket: "avatars", folder: "gear" }, //                {uid}/gear/**
  { bucket: "media", folder: "dogs" }, //                  {uid}/dogs/**
];

/** Prefixes that MUST survive — asserted in the Deno tests, stated here so the list is one edit. */
export const KEEP_SEGMENTS = ["/runs/", "/chat/", "/clubchat/"];

const PAGE = 100;

async function listFiles(db: SupabaseClient, bucket: string, prefix: string): Promise<string[]> {
  const out: string[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await db.storage.from(bucket).list(prefix, { limit: PAGE, offset });
    if (error) throw error;
    const page = data ?? [];
    for (const f of page) {
      // A `list()` entry with a null id is a pseudo-folder, not an object. Skipping them means
      // this never recurses into a subfolder it did not name — which is the point (F5).
      if (f && (f as { id?: string | null }).id) out.push(prefix ? `${prefix}/${f.name}` : f.name);
    }
    if (page.length < PAGE) return out;
  }
}

export async function deleteAccount(req: Request, db: SupabaseClient): Promise<unknown> {
  // 1. The uid comes from the JWT. There is no body field that can name a user, and adding one
  //    would hand every authenticated caller a delete-anyone button — the RPC takes `p_uid` as a
  //    parameter and holds no `auth.uid()` of its own (which is why only service_role may call it).
  const uid = await caller(req, db);

  // 2. An explicit acknowledgement. A stray invoke must not delete an account.
  let body: { confirm?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  if (body?.confirm !== "DELETE") throw new HttpError(400, "confirm_required");

  // 3. The SQL half, atomically. Any state-gate token surfaces verbatim as a 409 so the client
  //    can key Korean copy on it (twelve tokens, twelve copy entries).
  //
  //    🔴 EXCEPT ONE, AND THE EXCEPTION IS THE POINT: `not_authenticated` IS NOT A 409.
  //    The RPC's party gate raises it when `p_uid is null` (0115 §D ①). Every other token this
  //    function forwards is a statement about the ACCOUNT — "your state forbids this, here is what
  //    to clear" — and 409 Conflict is exactly that claim. An expired or malformed session is not
  //    an account state; it is the absence of one, and there is nothing about the account for the
  //    user to fix. Returning 409 for it would put a permanent, unactionable refusal in front of a
  //    user whose only real problem is that they need to sign in again — a dead-end refusal under
  //    the honesty laws and an unreasonable obstacle under 5.1.1(v).
  //    **The client keys 401 → session expired → sign out → /login.** `caller()` above already
  //    401s on a missing/bad JWT with `unauthorized`; this arm is the same class arriving from one
  //    layer deeper, and it keeps its own distinct token so the two are never confused.
  //    ⚠ The comparison is EXACT (`===`), not a prefix or an includes. A substring test would let
  //    any future token that merely mentions the word downgrade a real account-state refusal into
  //    a sign-out. Everything that is not literally `not_authenticated` stays a 409 with the token
  //    verbatim — including tokens that do not exist yet, which is the correct default.
  const { data: tx, error: txError } = await db.rpc("delete_my_account_tx", { p_uid: uid });
  if (txError) {
    if (txError.message === "not_authenticated") throw new HttpError(401, "not_authenticated");
    throw new HttpError(409, txError.message);
  }
  const result = (tx ?? {}) as Record<string, unknown>;
  const logId = (result.log_id as string | null) ?? null;

  // 4. Storage — only if the RPC succeeded, and only the four deletable folders.
  //    Failure here is LOGGED AND REPORTED, NOT FATAL: the account must still be deleted, and
  //    leftovers are swept by hand. The count is in the result rather than in a log nobody reads.
  let storageRemoved = 0;
  for (const s of SWEEP) {
    try {
      const prefix = s.folder ? `${uid}/${s.folder}` : uid;
      let names = await listFiles(db, s.bucket, prefix);
      if (s.only) names = names.filter((n) => n === `${uid}/${s.only}`);
      if (names.length === 0) continue;
      const { error } = await db.storage.from(s.bucket).remove(names);
      if (error) throw error;
      storageRemoved += names.length;
    } catch (e) {
      console.error("delete-account: storage sweep failed", s.bucket, s.folder, e);
    }
  }

  // 5. The credential. Hard delete — no `shouldSoftDelete`: 5.1.1(v) is "delete, not deactivate".
  const { error: authError } = await db.auth.admin.deleteUser(uid);

  // 6. ONLY HERE is `auth_deleted` written (F15). The transaction in step 3 committed before this
  //    call was even attempted, so a value it wrote would have been a claim about the future.
  if (logId) {
    await db.from("account_deletions").update({
      auth_deleted: !authError,
      storage_removed: storageRemoved,
    }).eq("id", logId);
  }

  if (authError) {
    // 🔴 A REAL, REACHABLE, DURABLE STATE — not an error message. The profile is already
    // tombstoned and the transaction already committed, so the user is left with a redacted
    // account they can still sign into. **The row stays tombstoned**: no rollback, no
    // un-anonymise, `deleted_at` stays set. The client keeps the user signed in (the JWT is
    // needed for the retry) and offers one button that re-invokes this function — which hits the
    // RPC's `already: true` short-circuit, skips the whole SQL half, and comes straight back to
    // step 4/5. That is why the idempotent short-circuit is load-bearing rather than defensive.
    // ⚠ TOKEN NOTE: the contract's §C.1.c step 5 named this `500 auth_delete_failed`. It is
    // `202 auth_delete_pending` here, by the implementation brief, and the change is an
    // improvement worth stating rather than a drift: nothing FAILED — the user's data is
    // redacted exactly as promised — and 202 plus "pending" is what the retry UI is actually
    // rendering. **ui2 keys its copy on `auth_delete_pending`; there is one token, not two.**
    console.error("delete-account: auth.admin.deleteUser failed", authError);
    throw new HttpError(202, "auth_delete_pending");
  }

  // 7. Flat, whitelisted. No row contents.
  return {
    ok: true,
    tombstoned: result.tombstoned === true,
    already: result.already === true,
    storage_removed: storageRemoved,
    auth_deleted: true,
    deleted: result.deleted ?? {},
    forfeited: result.forfeited ?? {},
    kept: result.kept ?? [],
    // 🔵 Sean 2026-08-20, A-intact-when-owed: the payout destination was KEPT INTACT because the
    // runner has `ledger_items` on the books. A per-user FACT, not a member of `kept` (which is a
    // static list of table names) — the confirm sheet must be able to say "정산되지 않은 수익이
    // 있어 정산 계좌는 보관됩니다" exactly when it is true and never when it is not. Defaulting to
    // FALSE is the safe direction: a client that under-promises retention is honest, one that
    // announces a retained bank account that was actually deleted is not.
    bank_kept: result.bank_kept === true,
  };
}
