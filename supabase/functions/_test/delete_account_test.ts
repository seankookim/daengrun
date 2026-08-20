// `delete-account` — the half of App Store 5.1.1(v) deletion that cannot be SQL.
//
//   deno test -A supabase/functions/_test/
//
// The invariants these tests defend, and each one is a finding rather than a preference:
//   ① THE UID COMES FROM THE JWT. There is no body field that names a user; if there were, every
//      authenticated caller would hold a delete-anyone button, because `delete_my_account_tx`
//      takes `p_uid` as a PARAMETER and has no `auth.uid()` of its own.
//   ② DENO DELETES NO APPLICATION ROW. Same invariant as `start_run_test.ts`: the SQL half is one
//      transaction, and anything this file could delete would be outside it.
//   ③ 🔴 THE SWEEP IS FOUR FOLDERS, NOT `{uid}/%` (F5). `runs/`, `chat/` and `clubchat/` are the
//      media half of rows the deletion KEEPS — sweeping them leaves a kept row pointing at an
//      object that is gone, which is the SET NULL mutilation the contract condemns, reached from
//      the storage side. The positive arm is the one that matters: an "empty storage" pin alone
//      rewards the wrong implementation, because a sweep that deletes everything passes it
//      perfectly.
//   ④ STORAGE BEFORE AUTH, for ORPHAN AVOIDANCE and not for the reason first written (F14): both
//      calls run on `admin()`, a service-role client holding no user JWT, so deleting the auth
//      user revokes nothing. What it does destroy is the last easy route back to `{uid}/` —
//      storage objects are keyed by uid and by nothing else.
//   ⑤ `auth_deleted` IS WRITTEN BY THIS FUNCTION, AFTER THE CALL (F15) — never inside the
//      transaction, which commits before the auth delete is even attempted.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { deleteAccount, KEEP_SEGMENTS } from "../delete-account/handler.ts";
import { FakeDb, req } from "./fakedb.ts";

const UID = "11111111-1111-1111-1111-111111111111";
const VICTIM = "99999999-9999-9999-9999-999999999999";
const JWT = "jwt-uid";
const LOG = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

function scene(over: { rpc?: (args: Record<string, unknown>) => { data?: unknown; error?: { message: string } } } = {}) {
  const db = new FakeDb();
  db.users[JWT] = UID;
  db.seed("account_deletions", [{ id: LOG, profile_id: UID, auth_deleted: null, storage_removed: null }]);
  db.rpcs["delete_my_account_tx"] = over.rpc ?? (() => ({
    data: {
      ok: true,
      already: false,
      tombstoned: true,
      log_id: LOG,
      deleted: { push_tokens: 1 },
      forfeited: { miles: 700, drops: 1 },
      kept: ["bookings"],
      bank_kept: false,
    },
  }));
  // Both buckets, all five writer prefixes — the three that must survive included.
  db.seedObjects("avatars", [
    `${UID}/avatar.jpg`,
    `${UID}/club-abc.jpg`, //            a CLUB's photo, not this user's identity (0064:9-15)
    `${UID}/gallery/1.jpg`,
    `${UID}/gallery/2.jpg`,
    `${UID}/gear/leash.jpg`,
  ]);
  db.seedObjects("media", [
    `${UID}/dogs/d1.jpg`,
    `${UID}/runs/bk1/1.jpg`, //          run evidence — KEEP
    `${UID}/chat/th1/1.jpg`, //          chat_messages.media_path — KEEP
    `${UID}/clubchat/s1/1.jpg`, //       club_chat_messages.media_path — KEEP
  ]);
  return db;
}

Deno.test("delete-account: the uid comes from the JWT — a body-supplied id is ignored", async () => {
  const db = scene();
  let seen: unknown = null;
  db.rpcs["delete_my_account_tx"] = (args) => {
    seen = args.p_uid;
    return { data: { ok: true, tombstoned: true, log_id: LOG } };
  };
  // the body names someone else, and carries every plausible spelling of "delete THIS user"
  await deleteAccount(
    req({ confirm: "DELETE", p_uid: VICTIM, uid: VICTIM, profile_id: VICTIM, user_id: VICTIM }, JWT),
    db as never,
  );
  assertEquals(seen, UID, "the RPC must be called with the caller's own uid");
  assert(!db.removed.some((p) => p.startsWith(VICTIM)), "nothing of the named victim may be touched");
  assertEquals(db.deletedUsers, [UID]);
});

Deno.test("delete-account: no Authorization header → 401 unauthorized", async () => {
  const db = scene();
  const e = await assertRejects(() => deleteAccount(req({ confirm: "DELETE" }), db as never), HttpError);
  assertEquals(e.status, 401);
  assertEquals(e.message, "unauthorized");
  assertEquals(db.log.length, 0, "an unauthenticated request must reach nothing");
});

Deno.test("delete-account: a missing confirm → 400 confirm_required, and no rpc is called", async () => {
  const db = scene();
  for (const body of [{}, { confirm: "delete" }, { confirm: true }, { confirm: "DELETE " }]) {
    const e = await assertRejects(() => deleteAccount(req(body, JWT), db as never), HttpError);
    assertEquals(e.status, 400);
    assertEquals(e.message, "confirm_required");
  }
  assertEquals(db.log.filter((l) => l.startsWith("rpc:")).length, 0, "a stray invoke must not delete an account");
  assertEquals(db.deletedUsers.length, 0);
});

Deno.test("delete-account: the RPC's refusal token reaches the client as a 409, verbatim", async () => {
  // one per state-gate arm — the client keys Korean copy on these exact strings
  for (
    const token of [
      "active_booking",
      "active_run",
      "unsettled_run",
      "unsettled_payment",
      "unpaid_payout",
      "km_balance",
      "open_incident",
      "active_recurring",
      "club_host_duty",
      "club_custody",
      // 🔴 the owner-side twin of club_custody. TWO tokens for one condition, on purpose: the
      // holder can finish the handoff, the owner can only wait for the runner to finish it, so
      // one token would force one sentence onto two readers and hand one of them a refusal
      // naming an action they cannot perform.
      "club_custody_owner",
      "club_assignment",
    ]
  ) {
    const db = scene({ rpc: () => ({ error: { message: token } }) });
    const e = await assertRejects(() => deleteAccount(req({ confirm: "DELETE" }, JWT), db as never), HttpError);
    assertEquals(e.status, 409);
    assertEquals(e.message, token, "the token must survive to the client unwrapped");
    assertEquals(db.deletedUsers.length, 0, "a refusal must not delete the credential");
    assertEquals(db.removed.length, 0, "a refusal must not touch storage");
  }
});

Deno.test("delete-account: `not_authenticated` from the RPC is a 401, not a 409", async () => {
  // 🔴 THE ONE TOKEN THAT IS NOT AN ACCOUNT STATE. The RPC's party gate raises it when `p_uid is
  // null` (0115 §D ①). 409 Conflict means "your account state forbids this, here is what to
  // clear" — every other token is exactly that. An expired session is the ABSENCE of an account
  // state and there is nothing about the account for the user to fix, so a 409 would put a
  // permanent, unactionable refusal in front of someone whose only problem is that they need to
  // sign in again. **The client keys 401 → session expired → sign out → /login.**
  const db = scene({ rpc: () => ({ error: { message: "not_authenticated" } }) });
  const e = await assertRejects(() => deleteAccount(req({ confirm: "DELETE" }, JWT), db as never), HttpError);
  assertEquals(e.status, 401);
  assertEquals(e.message, "not_authenticated", "the token stays verbatim — only the status changes");
  assertEquals(db.deletedUsers.length, 0);
  assertEquals(db.removed.length, 0);
});

Deno.test("delete-account: the 401 arm is an EXACT match — a state token that merely mentions it stays a 409", async () => {
  // The control for the arm above, and the reason `===` is written rather than `.includes()`:
  // a substring test would let any future token containing the word downgrade a real
  // account-state refusal into a sign-out, which loses the user's data-state warning entirely.
  for (const token of ["not_authenticated_yet", "club_not_authenticated", " not_authenticated"]) {
    const db = scene({ rpc: () => ({ error: { message: token } }) });
    const e = await assertRejects(() => deleteAccount(req({ confirm: "DELETE" }, JWT), db as never), HttpError);
    assertEquals(e.status, 409, `${token} is not the party-gate token and must stay a 409`);
    assertEquals(e.message, token);
  }
});

Deno.test("delete-account: Deno deletes no application row — every delete goes through the tx", async () => {
  const db = scene();
  await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never);
  assertEquals(
    db.log.filter((l) => l.startsWith("delete:")).length,
    0,
    `no table delete may come from Deno: ${JSON.stringify(db.log)}`,
  );
  assert(db.log.includes("rpc:delete_my_account_tx"));
  // the only write from this side is the log row's auth_deleted / storage_removed (F15)
  assertEquals(db.log.filter((l) => l.startsWith("update:")), ["update:account_deletions:1"]);
});

Deno.test("delete-account: the sweep never touches runs, chat or clubchat, and the four deletable folders are each enumerated", async () => {
  const db = scene();
  const out = await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never) as Record<string, unknown>;

  // ── negative: the identity media is gone
  assertEquals(
    [...db.removed].sort(),
    [`${UID}/avatar.jpg`, `${UID}/gallery/1.jpg`, `${UID}/gallery/2.jpg`, `${UID}/gear/leash.jpg`, `${UID}/dogs/d1.jpg`]
      .sort(),
  );
  assertEquals(out.storage_removed, 5);

  // ── 🔴 positive: the EVIDENCE media is untouched. Without this arm the "empty storage" pin
  //    rewards a `{uid}/%` sweep, which passes it perfectly while creating dangling pointers.
  for (const seg of KEEP_SEGMENTS) {
    assert(
      !db.removed.some((p) => p.includes(seg)),
      `the sweep reached ${seg} — a kept row now points at an object that is gone: ${JSON.stringify(db.removed)}`,
    );
  }
  assertEquals(db.objects["media"], [`${UID}/runs/bk1/1.jpg`, `${UID}/chat/th1/1.jpg`, `${UID}/clubchat/s1/1.jpg`]);
  // and a club's photo in the avatars root is not this user's identity
  assertEquals(db.objects["avatars"], [`${UID}/club-abc.jpg`]);

  // structural, not just filtered: those folders were never even LISTED
  const listed = db.log.filter((l) => l.startsWith("storage:list:"));
  assertEquals(listed, [
    `storage:list:avatars:${UID}`,
    `storage:list:avatars:${UID}/gallery`,
    `storage:list:avatars:${UID}/gear`,
    `storage:list:media:${UID}/dogs`,
  ]);
});

Deno.test("delete-account: storage failure does not abort the deletion", async () => {
  const db = scene();
  db.fail("storage:media:remove", "storage exploded");
  const out = await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never) as Record<string, unknown>;
  assertEquals(db.deletedUsers, [UID], "the account must still be deleted");
  assertEquals(out.auth_deleted, true);
  assertEquals(out.storage_removed, 4, "the avatars bucket still swept; the media failure is reported, not fatal");
});

Deno.test("delete-account: auth.admin.deleteUser failure returns 202 auth_delete_pending, and the log row records it", async () => {
  const db = scene();
  db.fail("auth:deleteUser", "service unavailable");
  const e = await assertRejects(() => deleteAccount(req({ confirm: "DELETE" }, JWT), db as never), HttpError);
  // ⚠ 202 + `auth_delete_pending`, not 500 + `auth_delete_failed`: nothing failed from the user's
  // side — their data IS redacted — and the credential is not yet gone. ui2 renders
  // "탈퇴 처리 중 — 잠시 후 다시 시도해주세요." and keeps the user signed in for the retry.
  assertEquals(e.status, 202);
  assertEquals(e.message, "auth_delete_pending");
  // the log row records the truth rather than the hope, and it is written HERE, after the call,
  // never inside the transaction (F15)
  assertEquals(db.rows("account_deletions")[0].auth_deleted, false);
  const iRpc = db.log.indexOf("rpc:delete_my_account_tx");
  const iUpd = db.log.indexOf("update:account_deletions:1");
  assert(iRpc >= 0 && iUpd > iRpc, `the log update must follow the tx: ${JSON.stringify(db.log)}`);
  // and the tombstone STAYS — no rollback, no un-anonymise
  assertEquals(db.rows("account_deletions").length, 1);
});

Deno.test("delete-account: the retry after auth_delete_pending re-runs only storage + auth, and is not a no-op", async () => {
  const db = scene({
    // the RPC's idempotent short-circuit: profile already tombstoned, SQL half skipped entirely
    rpc: () => ({ data: { ok: true, already: true, tombstoned: true, log_id: LOG } }),
  });
  db.rows("account_deletions")[0].auth_deleted = false;
  const out = await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never) as Record<string, unknown>;
  assertEquals(out.already, true);
  assertEquals(db.deletedUsers, [UID], "the retry must actually call the auth delete");
  assertEquals(db.rows("account_deletions")[0].auth_deleted, true, "the row must flip");
  assertEquals(db.rows("account_deletions").length, 1, "no second log row");
  assertEquals(db.log.filter((l) => l.startsWith("insert:")).length, 0);
});

Deno.test("delete-account: order is tx → storage → auth", async () => {
  const db = scene();
  await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never);
  const iRpc = db.log.indexOf("rpc:delete_my_account_tx");
  const iList = db.log.findIndex((l) => l.startsWith("storage:list:"));
  const iRemove = db.log.findIndex((l) => l.startsWith("storage:remove:"));
  const iAuth = db.log.findIndex((l) => l.startsWith("auth:deleteUser:"));
  assert(iRpc >= 0 && iList > iRpc, "storage must be enumerated after the transaction");
  assert(iRemove > iList);
  assert(
    iAuth > iRemove,
    `auth must go last — orphan avoidance, not JWT revocation (F14): ${JSON.stringify(db.log)}`,
  );
});

Deno.test("delete-account: the result is flat and carries no row contents", async () => {
  const db = scene();
  const out = await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never) as Record<string, unknown>;
  assertEquals(
    Object.keys(out).sort(),
    ["already", "auth_deleted", "bank_kept", "deleted", "forfeited", "kept", "ok", "storage_removed", "tombstoned"],
  );
  assertEquals(out.ok, true);
  assertEquals(out.tombstoned, true);
  assertEquals(out.forfeited, { miles: 700, drops: 1 }, "the forfeit counts are the support answer");
});

Deno.test("delete-account: `bank_kept` is forwarded as a boolean, and defaults FALSE when absent", async () => {
  // 🔵 A-intact-when-owed (Sean, 2026-08-20). The RPC keeps the payout destination INTACT when the
  // runner has `ledger_items`, and the confirm sheet has to be able to say so — a fact the client
  // cannot see is a fact the client will guess.
  const owed = scene({
    rpc: () => ({ data: { ok: true, tombstoned: true, log_id: LOG, bank_kept: true } }),
  });
  const a = await deleteAccount(req({ confirm: "DELETE" }, JWT), owed as never) as Record<string, unknown>;
  assertEquals(a.bank_kept, true);

  // ⚠ The default is FALSE, not "whatever the RPC sent". A missing or non-boolean value must not
  // become truthy: announcing a retained bank account that was in fact deleted is the dishonest
  // direction, and it is the one a loose `?? ` would produce.
  for (const data of [{ ok: true }, { ok: true, bank_kept: "true" }, { ok: true, bank_kept: 1 }, { ok: true, bank_kept: null }]) {
    const db = scene({ rpc: () => ({ data }) });
    const out = await deleteAccount(req({ confirm: "DELETE" }, JWT), db as never) as Record<string, unknown>;
    assertEquals(out.bank_kept, false, `${JSON.stringify(data)} must not read as retained`);
  }
});
