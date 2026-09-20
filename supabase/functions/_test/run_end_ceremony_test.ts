// transition-booking `end_run` + `confirm_return` — the run-end ceremony's edge half (0188).
//
//   deno test -A supabase/functions/_test/
//
// ═══ THE INVARIANT THESE PINS DEFEND ═══
// **THE SIDE IS THE SERVER'S, AND THE PRICE NEVER COMES FROM A PHONE.**
//
// `confirm_return_tx` has two caller classes (0083 §6): a JWT-bearing client must BE the side it
// claims, and a server caller with no `auth.uid()` is trusted to have already authenticated its
// user. `transition-booking` uses `admin()`, so it is the SECOND class — the migration's party
// gate is structurally blind here, and the only thing between a runner and BOTH return stamps is
// the derivation in `confirm_return.ts`. A `meta.side` read would let one party seal alone, and a
// seal settles: Sean's 0089 ruling ("the confirmation must happen with both parties and never
// just the runner") would be defeated through the one path where SQL cannot see it.
//
// The SQL half — the stamps, the seal, the settlement, the work gate, the sweep — is pinned by
// `219_run_end_ceremony_suite.sql`. Nothing here re-asserts it, exactly as `start_run_test.ts`
// leaves the insert seal to 123.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { endRun, RETURN_ASK_TITLE } from "../transition-booking/end_run.ts";
import { confirmReturn, RETURN_SEALED_TITLE } from "../transition-booking/confirm_return.ts";
import { FakeDb, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const STRANGER = "55555555-5555-5555-5555-555555555555";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

function scene(over: {
  booking?: Row;
  run?: Row | null;
  endRunTx?: (args: Row) => { data?: unknown; error?: { message: string } };
  confirmTx?: (args: Row) => { data?: unknown; error?: { message: string } };
  payout?: (args: Row) => { data?: unknown; error?: { message: string } };
} = {}) {
  const db = new FakeDb();
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "active", km: 5,
    // ⚠ `run_ended_at` is STAMPED by default, because every booking that can legally reach
    // `confirm_return` has been through `end_run_tx` — `confirm_return_tx` raises `run_not_ended`
    // otherwise. The first version of this scene left it null, which made the fail-closed pin
    // below pass for the wrong reason: the refusal it was testing is keyed on exactly this field,
    // so a fixture without it could not distinguish the guard from its absence. (`end_run`'s own
    // tests do not read the field, so one scene serves both.)
    run_ended_at: "2026-09-21T10:00:00.000Z",
    runner_confirmed_return_at: null, owner_confirmed_return_at: null,
    ...(over.booking ?? {}),
  }]);
  db.seed("runs", over.run === null ? [] : [{
    booking_id: BOOKING, actual_km: "5.00", end_reason: "completed", ...(over.run ?? {}),
  }]);
  db.seed("runners", [{ profile_id: RUNNER, commission_rate: 0.33 }]);
  db.seed("notifications", []);
  db.rpcs["end_run_tx"] = over.endRunTx ??
    (() => ({ data: { unchanged: false, run_ended_at: "2026-09-21T10:00:00.000Z", actual_km: 5, end_reason: "completed" } }));
  db.rpcs["confirm_return_tx"] = over.confirmTx ??
    (() => ({ data: { stamped: true, sealed: false, settled: false, unchanged: false, both_confirmed: false, case_open: false } }));
  db.rpcs["compute_runner_payout"] = over.payout ??
    (() => ({ data: [{ base: 9900, distance: 15000, addon: 0, guarantee: 0, fee: 4980 }] }));
  return db;
}

const bk = (db: FakeDb) => db.rows("bookings")[0];
const notifier = (db: FakeDb) => (profile_id: string, title: string, body: string) =>
  db.from("notifications").insert({ profile_id, kind: "booking", title, body, ref_id: BOOKING });
const META = { end_reason: "completed", actual_km: 5.0, duration_sec: 1800 };

// ══════════════════════════════════════════════════════════════════════════════════════════
// end_run
// ══════════════════════════════════════════════════════════════════════════════════════════

Deno.test("end_run: the stop goes through end_run_tx and settles NOTHING — the re-sequencing itself", async () => {
  const db = scene();
  await endRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), meta: META, notify: notifier(db) });

  assert(db.log.includes("rpc:end_run_tx"), `expected the freeze, got ${JSON.stringify(db.log)}`);
  // The whole point of the slice: no settlement at the stop. Before 0188 this path called
  // settle-run and the booking reached `completed` with the dog still out.
  assertEquals(db.log.filter((l) => l.startsWith("rpc:settle_run_tx")).length, 0);
  assertEquals(db.log.filter((l) => l.startsWith("rpc:confirm_return_tx")).length, 0);
  // and the edge writes no booking state of its own — the definer moved it, not us
  assertEquals(db.log.filter((l) => l.startsWith("update:bookings")).length, 0);
  assertEquals(bk(db).status, "active");
});

Deno.test("end_run: NO CLOCK crosses the wire — the stop moment is the server's", async () => {
  const db = scene();
  let seen: Row | null = null;
  db.rpcs["end_run_tx"] = (args: Row) => {
    seen = args;
    return { data: { unchanged: false, run_ended_at: "2026-09-21T10:00:00.000Z" } };
  };
  await endRun(db as never, {
    bookingId: BOOKING,
    uid: RUNNER,
    bk: bk(db),
    // a malicious or stale client trying to choose the moment, exactly as 0087 §0 ① describes
    meta: { ...META, run_ended_at: "2000-01-01T00:00:00.000Z", ended_at: "2000-01-01T00:00:00.000Z" },
    notify: notifier(db),
  });
  assertEquals(
    Object.keys(seen!).sort(),
    ["p_actual_km", "p_booking", "p_condition_note", "p_duration_sec", "p_end_reason", "p_trace"],
  );
});

Deno.test("end_run: the party gate is THE RUNNER, above every field of the body", async () => {
  for (const who of [OWNER, STRANGER]) {
    const db = scene();
    const err = await assertRejects(
      () => endRun(db as never, { bookingId: BOOKING, uid: who, bk: bk(db), meta: META, notify: notifier(db) }),
      HttpError,
    );
    assertEquals((err as HttpError).status, 403);
    // refused BEFORE the RPC and before any reason is validated: a stranger must learn nothing
    // about which reasons this server treats specially
    assertEquals(db.log.filter((l) => l.startsWith("rpc:")).length, 0);
    assertEquals(db.rows("notifications").length, 0);
  }
});

Deno.test("end_run: a reason outside the runner-declarable four never reaches the RPC", async () => {
  for (const reason of ["incident", "owner_forced", "", "whatever"]) {
    const db = scene();
    const err = await assertRejects(
      () =>
        endRun(db as never, {
          bookingId: BOOKING,
          uid: RUNNER,
          bk: bk(db),
          meta: { ...META, end_reason: reason },
          notify: notifier(db),
        }),
      HttpError,
    );
    assertEquals((err as HttpError).status, 400);
    assertEquals(db.log.filter((l) => l.startsWith("rpc:end_run_tx")).length, 0, `reason ${reason} reached the RPC`);
  }
});

Deno.test("end_run: a missing or unreadable actual_km is a refusal, never a coerced 0", async () => {
  // `Number(null)` is 0 and km is money (3,000/km) — a silent 0 would freeze a real run at zero
  // distance and pay for none of it.
  for (const km of [null, undefined, "abc", NaN]) {
    const db = scene();
    await assertRejects(
      () =>
        endRun(db as never, {
          bookingId: BOOKING,
          uid: RUNNER,
          bk: bk(db),
          meta: { end_reason: "completed", actual_km: km, duration_sec: 1800 },
          notify: notifier(db),
        }),
      HttpError,
    );
    assertEquals(db.log.filter((l) => l.startsWith("rpc:end_run_tx")).length, 0);
  }
});

Deno.test("end_run: the owner is asked once, and a re-stop asks nobody", async () => {
  const db = scene();
  await endRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), meta: META, notify: notifier(db) });
  const asks = db.rows("notifications");
  assertEquals(asks.length, 1);
  assertEquals(asks[0].profile_id, OWNER);
  assertEquals(asks[0].title, RETURN_ASK_TITLE);
  assertEquals(asks[0].ref_id, BOOKING);

  // A retry after a lost response answers `{unchanged:true}` (0083 §3). Asking again is how an
  // inbox teaches people to ignore the ask that matters.
  const db2 = scene({ endRunTx: () => ({ data: { unchanged: true, run_ended_at: "2026-09-21T10:00:00.000Z" } }) });
  await endRun(db2 as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db2), meta: META, notify: notifier(db2) });
  assertEquals(db2.rows("notifications").length, 0);
});

Deno.test("end_run: every refusal the migration raises gets its own status and its own sentence", async () => {
  const cases: [string, number, string][] = [
    ["club_out_of_scope", 400, "클럽"],
    ["not_active", 409, "진행 중인"],
    ["end_reason_not_runner_declarable", 400, "사유"],
    ["completed_needs_half_distance", 400, "50%"],
    ["condition_note_required", 400, "관찰"],
    ["not_found", 404, "booking"],
  ];
  for (const [raise, status, fragment] of cases) {
    const db = scene({ endRunTx: () => ({ error: { message: `${raise}` } }) });
    const err = await assertRejects(
      () => endRun(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), meta: META, notify: notifier(db) }),
      HttpError,
    );
    assertEquals((err as HttpError).status, status, `${raise} → ${(err as HttpError).status}`);
    assertStringIncludes((err as Error).message, fragment);
    // a refusal asks nobody anything
    assertEquals(db.rows("notifications").length, 0);
  }
});

// ══════════════════════════════════════════════════════════════════════════════════════════
// confirm_return — the side derivation is the security core
// ══════════════════════════════════════════════════════════════════════════════════════════

Deno.test("confirm_return: 🔴 the side is DERIVED from the caller — a meta.side is ignored entirely", async () => {
  // The attack: the runner posts `side: 'owner'` to produce the owner's stamp too. With
  // `transition-booking` calling as service_role, `confirm_return_tx`'s party gate takes the
  // server-caller branch and cannot see who asked — so if the body were read, this succeeds and
  // the runner seals (and settles) alone.
  for (
    const [uid, claimed, expected] of [
      [RUNNER, "owner", "runner"],
      [OWNER, "runner", "owner"],
      [RUNNER, "ops", "runner"],
    ] as const
  ) {
    const db = scene();
    let seen: Row | null = null;
    db.rpcs["confirm_return_tx"] = (args: Row) => {
      seen = args;
      return { data: { stamped: true, sealed: false, settled: false, unchanged: false } };
    };
    const res = await confirmReturn(db as never, {
      bookingId: BOOKING,
      uid,
      // the body's opinion, planted on the booking-shaped argument the switch passes through
      bk: { ...bk(db), side: claimed },
      notify: notifier(db),
    });
    assertEquals(seen!.p_side, expected, `caller ${uid} claiming ${claimed} → ${seen!.p_side}`);
    assertEquals(res.side, expected);
  }
});

Deno.test("confirm_return: a stranger is refused before the RPC and learns nothing", async () => {
  const db = scene();
  const err = await assertRejects(
    () => confirmReturn(db as never, { bookingId: BOOKING, uid: STRANGER, bk: bk(db), notify: notifier(db) }),
    HttpError,
  );
  assertEquals((err as HttpError).status, 403);
  assertEquals(db.log.filter((l) => l.startsWith("rpc:confirm_return_tx")).length, 0);
  assertEquals(db.rows("notifications").length, 0);
});

Deno.test("confirm_return: a booking whose owner IS its runner is refused, not silently picked", async () => {
  // Ambiguous in law: one human holding both stamps is exactly the outcome 0089 forbids. Refusing
  // is the only honest answer; picking a side would manufacture a two-sided confirmation.
  const db = scene({ booking: { owner_id: RUNNER } });
  const err = await assertRejects(
    () => confirmReturn(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) }),
    HttpError,
  );
  assertEquals((err as HttpError).status, 409);
  assertEquals(db.log.filter((l) => l.startsWith("rpc:confirm_return_tx")).length, 0);
});

Deno.test("confirm_return: the price is computed by the SERVER from the FROZEN run, never from the body", async () => {
  const db = scene({ run: { actual_km: "4.20", end_reason: "owner_request" } });
  let payoutArgs: Row | null = null;
  db.rpcs["compute_runner_payout"] = (args: Row) => {
    payoutArgs = args;
    return { data: [{ base: 9900, distance: 12600, addon: 0, guarantee: 3000, fee: 5100 }] };
  };
  let seen: Row | null = null;
  db.rpcs["confirm_return_tx"] = (args: Row) => {
    seen = args;
    return { data: { stamped: true, sealed: true, settled: true, unchanged: false } };
  };
  await confirmReturn(db as never, {
    bookingId: BOOKING,
    uid: OWNER,
    bk: { ...bk(db), runner_confirmed_return_at: "2026-09-21T10:01:00.000Z" },
    notify: notifier(db),
  });
  // the numbers come off `runs`, which is what `_settle_sealed_run` re-reads under the lock
  assertEquals(payoutArgs!.p_actual_km, 4.2);
  assertEquals(payoutArgs!.p_end_reason, "owner_request");
  assertEquals(payoutArgs!.p_commission, 0.33);
  // …and the quote reaches the RPC in the five-key shape `_settle_sealed_run` validates
  assertEquals(Object.keys(seen!.p_quote).sort(), ["addon_pay", "base", "distance_pay", "fee", "guarantee"]);
  assertEquals(seen!.p_quote.guarantee, 3000);
});

Deno.test("confirm_return: a quote rides on EVERY call, so 'am I second?' is never answered outside the lock", async () => {
  // Deciding sealing-ness from an unlocked read is a TOCTOU; a first stamp carrying a price is
  // harmless because `confirm_return_tx` reaches `_settle_sealed_run` only under `v_both`.
  const db = scene();
  let seen: Row | null = null;
  db.rpcs["confirm_return_tx"] = (args: Row) => {
    seen = args;
    return { data: { stamped: true, sealed: false, settled: false, unchanged: false } };
  };
  await confirmReturn(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) });
  assert(seen!.p_quote, "the first stamp carried no quote — a later second stamp would seal unsettled");
});

Deno.test("confirm_return: a sealing call with NO price FAILS CLOSED — nothing is stamped", async () => {
  // The seal without a settlement is the one state no sweep can repair (0083 §0f), so a pricing
  // failure must cost a retry rather than commit a durable seal at a guessed number.
  const db = scene({ payout: () => ({ error: { message: "boom" } }) });
  const err = await assertRejects(
    () =>
      confirmReturn(db as never, {
        bookingId: BOOKING,
        uid: OWNER,
        bk: { ...bk(db), runner_confirmed_return_at: "2026-09-21T10:01:00.000Z" },
        notify: notifier(db),
      }),
    HttpError,
  );
  assertEquals((err as HttpError).status, 503);
  assertEquals(db.log.filter((l) => l.startsWith("rpc:confirm_return_tx")).length, 0);
  assertEquals(db.rows("notifications").length, 0);
});

Deno.test("confirm_return: 🔴 the fail-closed does NOT depend on the snapshot knowing it will seal", async () => {
  // [cold review #6] THE PIN THE FIRST VERSION WAS MISSING. The refusal used to be conditioned on
  // `sealsNow` — computed from `bk`, a snapshot `index.ts` took BEFORE this function ran. In the
  // direction that matters the snapshot is stale the other way: it says the counterparty has NOT
  // stamped (so `sealsNow` is false), they stamp in between, and a pricing failure then sails
  // past the guard and writes a durable seal with no settlement — the exact state the 503 exists
  // to prevent, through the one path it could not see. A guard conditioned on a stale read of the
  // race it guards against is not a guard.
  //
  // This fixture IS that snapshot: no counterparty stamp visible, pricing broken. Under the old
  // condition the RPC was called; under the new one nothing is written at all.
  const db = scene({ payout: () => ({ error: { message: "boom" } }) });
  const err = await assertRejects(
    () => confirmReturn(db as never, { bookingId: BOOKING, uid: OWNER, bk: bk(db), notify: notifier(db) }),
    HttpError,
  );
  assertEquals((err as HttpError).status, 503);
  assertEquals(db.log.filter((l) => l.startsWith("rpc:confirm_return_tx")).length, 0);
  assertEquals(db.rows("notifications").length, 0);
});

Deno.test("confirm_return: an UNFROZEN run is not refused for a pricing failure — the freeze is the key", async () => {
  // The mirror of the pin above, and the reason the refusal is conditional rather than blanket:
  // refusing the first stamp on a pricing hiccup would leave the runner gated for a money problem
  // that has nothing to do with them.
  // ⚠ REWRITTEN with the fail-closed's actual key: an UNFROZEN run. Once `run_ended_at` is
  // stamped the refusal is unconditional (see the pin above), and that is deliberate — a refused
  // first stamp costs a retry, while a sealed-unsettled row cannot be repaired from inside the
  // app. What this pin still owns is that the refusal is keyed on the FREEZE and not on "any
  // pricing failure anywhere": a booking with no frozen run is not in the ceremony at all, and
  // `confirm_return_tx` will refuse it by name (`run_not_ended`) rather than this file guessing.
  const db = scene({ booking: { run_ended_at: null }, payout: () => ({ error: { message: "boom" } }) });
  const res = await confirmReturn(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) });
  assert(res.stamped);
  assertEquals(db.log.filter((l) => l.startsWith("rpc:confirm_return_tx")).length, 1);
});

Deno.test("confirm_return: the counterparty is asked on a first stamp, told on the seal, and never on a re-tap", async () => {
  // first stamp → the ask, to the other side
  const db = scene();
  await confirmReturn(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) });
  assertEquals(db.rows("notifications").length, 1);
  assertEquals(db.rows("notifications")[0].profile_id, OWNER);
  assertEquals(db.rows("notifications")[0].title, RETURN_ASK_TITLE);

  // second stamp → the pair is complete; the party who stamped FIRST is the one waiting
  const db2 = scene({ confirmTx: () => ({ data: { stamped: true, sealed: true, settled: true, unchanged: false } }) });
  await confirmReturn(db2 as never, {
    bookingId: BOOKING,
    uid: OWNER,
    bk: { ...bk(db2), runner_confirmed_return_at: "2026-09-21T10:01:00.000Z" },
    notify: notifier(db2),
  });
  assertEquals(db2.rows("notifications").length, 1);
  assertEquals(db2.rows("notifications")[0].profile_id, RUNNER);
  assertEquals(db2.rows("notifications")[0].title, RETURN_SEALED_TITLE);

  // a re-tap stamps nothing and must push nothing
  const db3 = scene({ confirmTx: () => ({ data: { stamped: false, sealed: false, settled: false, unchanged: false } }) });
  await confirmReturn(db3 as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db3), notify: notifier(db3) });
  assertEquals(db3.rows("notifications").length, 0);
});

Deno.test("confirm_return: the seal notice does not claim a settlement that did not happen", async () => {
  // From `incident_review` 0096 stamps without sealing or settling (`case_open`). Telling the
  // counterparty the run is finished there would be a claim about money that did not move.
  const db = scene({
    booking: { status: "incident_review" },
    confirmTx: () => ({
      data: { stamped: true, sealed: false, settled: false, unchanged: false, both_confirmed: true, case_open: true },
    }),
  });
  const res = await confirmReturn(db as never, {
    bookingId: BOOKING,
    uid: OWNER,
    bk: { ...bk(db), status: "incident_review", runner_confirmed_return_at: "2026-09-21T10:01:00.000Z" },
    notify: notifier(db),
  });
  assertEquals(res.case_open, true);
  assertEquals(res.settled, false);
  const body = String(db.rows("notifications")[0].body);
  assertStringIncludes(body, "담당자");
  assert(!body.includes("마무리됐어요"), `claimed a settlement that did not happen: ${body}`);
});

Deno.test("confirm_return: refusals keep their own status, and `not_party` says nothing about the booking", async () => {
  const cases: [string, number][] = [
    ["not_party", 403],
    ["club_out_of_scope", 400],
    ["run_not_ended", 409],
    ["not_active", 409],
    ["not_found", 404],
  ];
  for (const [raise, status] of cases) {
    const db = scene({ confirmTx: () => ({ error: { message: raise } }) });
    const err = await assertRejects(
      () => confirmReturn(db as never, { bookingId: BOOKING, uid: RUNNER, bk: bk(db), notify: notifier(db) }),
      HttpError,
    );
    assertEquals((err as HttpError).status, status, `${raise} → ${(err as HttpError).status}`);
    assertEquals(db.rows("notifications").length, 0);
  }
});
