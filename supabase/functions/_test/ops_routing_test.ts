// `_shared/ops.ts` — who hears about an ops event, and what they are allowed to be told.
//
//   deno test -A supabase/functions/_test/
//
// Sean's ruling ③ (2026-08-13): the single `OPS_PROFILE_ID` env var becomes `ops_recipients` with
// per-event-class routing — "build for full scale, not just for pilot". Two things are pinned here
// and they pull in opposite directions, which is why both need a test:
//
//   ① Ops must never be SILENCED. Table → env var → loud log, in that order, and an empty or
//      unreadable routing table falls through instead of swallowing the event.
//   ② A recipient id is a raw uuid a human typed. If it is wrong the notification lands on a REAL
//      user's lock screen (0024's insert trigger pushes `body` verbatim), so the body may not
//      contain an order id, an amount, or a booking id. Routing MULTIPLIES that risk — one bad row
//      in a table is as good as one bad env var — so the redaction pin is repeated per recipient
//      here, not only in confirm_payment_test.
//
// The SQL half (sealed table, RLS with zero policies, `ops_recipients_for` revoked from clients,
// active-only rows) is 0084's suite. What is testable here is the Deno fallback ladder, which SQL
// cannot see: `ops_recipients_for` reports emptiness honestly and this file decides what that means.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { notifyOps, type OpsEventClass } from "../_shared/ops.ts";
import { FakeDb, type Row } from "./fakedb.ts";

const OPS_ENV = "99999999-9999-9999-9999-999999999999";
const MONEY_OPS = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const SAFETY_OPS = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const RETIRED_OPS = "dddddddd-dddd-dddd-dddd-dddddddddddd";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

Deno.env.set("OPS_PROFILE_ID", OPS_ENV);

/**
 * Stand-in for 0084's `ops_recipients_for(p_event_class)` (Unit P), backed by a seeded
 * `ops_recipients` table so the filtering this module depends on is the SQL's filtering: active
 * rows, for the asked class, and `setof uuid` → an array of bare strings through PostgREST.
 */
function installRecipients(db: FakeDb, rows: Row[]) {
  db.seed("ops_recipients", rows);
  const seen: string[] = [];
  db.rpcs["ops_recipients_for"] = (args: Row) => {
    seen.push(String(args.p_event_class));
    return {
      data: db.rows("ops_recipients")
        .filter((r) => r.event_class === args.p_event_class && r.active)
        .map((r) => r.profile_id),
    };
  };
  return seen;
}

function scene(rows: Row[] = []) {
  const db = new FakeDb();
  db.seed("notifications", []);
  installRecipients(db, rows);
  return db;
}

function captureErrors() {
  const lines: string[] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  return { lines, restore: () => { console.error = orig; } };
}

const notes = (db: FakeDb) => db.rows("notifications");

// ═══ routing ═══════════════════════════════════════════════════════════════════════════════
Deno.test("two active recipients on a class → one notification each, same redacted copy", async () => {
  const db = scene([
    { profile_id: MONEY_OPS, event_class: "payment_manual_cancel", active: true },
    { profile_id: SAFETY_OPS, event_class: "payment_manual_cancel", active: true },
  ]);
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "payment_manual_cancel", { refId: BOOKING });
    assertEquals(notes(db).length, 2);
    assertEquals(notes(db).map((n) => n.profile_id).sort(), [MONEY_OPS, SAFETY_OPS].sort());
    for (const n of notes(db)) {
      assertEquals(n.kind, "system");
      assertEquals(n.ref_id, BOOKING); // a bare handle for the ops surface; never rendered in push
      assertEquals(n.title, "결제 자동 취소 실패 — 수동 취소 필요");
    }
    // The env var is NOT also notified — the fallback is a fallback, not an extra copy.
    assert(!notes(db).some((n) => n.profile_id === OPS_ENV), "the env fallback fired alongside the table");
    assertEquals(cap.lines, []);
  } finally {
    cap.restore();
  }
});

Deno.test("class filtering — money's operator does not get safety's event, and vice versa", async () => {
  const db = scene([
    { profile_id: MONEY_OPS, event_class: "payment_manual_cancel", active: true },
    { profile_id: SAFETY_OPS, event_class: "enroute_comp_failed", active: true },
    // Unsubscribed by an operator who moved on: still a row, must never be notified again.
    { profile_id: RETIRED_OPS, event_class: "payment_manual_cancel", active: false },
  ]);
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "payment_manual_cancel", { refId: BOOKING });
    assertEquals(notes(db).map((n) => n.profile_id), [MONEY_OPS]);

    await notifyOps(db as never, "enroute_comp_failed", { refId: BOOKING });
    assertEquals(notes(db).map((n) => n.profile_id), [MONEY_OPS, SAFETY_OPS]);
    // ...and the copy is the class's own, not the first one's.
    assertEquals(notes(db)[1].title, "이동 중 취소 보상 기록 실패 — 수동 확인 필요");
    assertEquals(cap.lines, []);
  } finally {
    cap.restore();
  }
});

Deno.test("the asked class is the one that reaches SQL (a mis-wired emitter cannot hide)", async () => {
  const db = scene([{ profile_id: MONEY_OPS, event_class: "charge_ladder_exhausted", active: true }]);
  const seen = installRecipients(db, db.rows("ops_recipients"));
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "charge_ladder_exhausted", {});
    assertEquals(seen, ["charge_ladder_exhausted"]);
    assertEquals(notes(db).map((n) => n.profile_id), [MONEY_OPS]);
    assertEquals(notes(db)[0].ref_id, null); // refId is optional; no handle is honest, not a crash
  } finally {
    cap.restore();
  }
});

// ═══ the fallback ladder — ops is never silenced ═══════════════════════════════════════════
Deno.test("empty routing table → the OPS_PROFILE_ID env var still gets it (one release of belt)", async () => {
  const db = scene([{ profile_id: SAFETY_OPS, event_class: "enroute_comp_failed", active: true }]);
  const cap = captureErrors();
  try {
    // Nobody has subscribed to THIS class — the table is provisioned but incomplete, which is the
    // exact way a routing migration goes wrong. The pre-ruling behaviour has to still be there.
    await notifyOps(db as never, "payment_manual_cancel", { refId: BOOKING });
    assertEquals(notes(db).length, 1);
    assertEquals(notes(db)[0].profile_id, OPS_ENV);
    assertEquals(notes(db)[0].title, "결제 자동 취소 실패 — 수동 취소 필요");
  } finally {
    cap.restore();
  }
});

Deno.test("no rows AND no env var → loud log, no notification, no throw", async () => {
  const db = scene([]);
  Deno.env.delete("OPS_PROFILE_ID");
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "payment_manual_cancel", { refId: BOOKING });
    assertEquals(notes(db).length, 0);
    // The exact substring the pre-ruling code logged — grep handles outlive refactors.
    assert(
      cap.lines.some((l) => l.includes("OPS_PROFILE_ID unset") && l.includes("payment_manual_cancel")),
      `not loud enough: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
    Deno.env.set("OPS_PROFILE_ID", OPS_ENV);
  }
});

Deno.test("an ops_recipients_for that ERRORS falls back to the env var — never silence", async () => {
  // The state of the world before 0084 is applied, and after any permission drift. A routing table
  // that cannot be read must not be the thing that stops ops hearing about captured money.
  const db = scene([]);
  db.rpcs["ops_recipients_for"] = () => ({ error: { message: "function does not exist" } });
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "payment_manual_cancel", { refId: BOOKING });
    assertEquals(notes(db).map((n) => n.profile_id), [OPS_ENV]);
    assert(
      cap.lines.some((l) => l.includes("ops_recipients_for failed") && l.includes("function does not exist")),
      `the routing failure was swallowed: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
  }
});

Deno.test("a failing notifications insert is logged, never thrown (the caller already committed)", async () => {
  const db = scene([{ profile_id: MONEY_OPS, event_class: "payment_manual_cancel", active: true }]);
  db.fail("notifications:insert", "deadlock detected");
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "payment_manual_cancel", { refId: BOOKING });
    assertEquals(notes(db).length, 0);
    assert(
      cap.lines.some((l) => l.includes("notify failed") && l.includes("deadlock detected")),
      `insert failure was silent: ${cap.lines.join("|")}`,
    );
  } finally {
    cap.restore();
  }
});

// ═══ redaction — the rule routing multiplies ═══════════════════════════════════════════════
Deno.test("no recipient is ever told a financial detail, however the event was routed", async () => {
  const secrets = [BOOKING, "24900", "24,900", "dr_order_1", "tviva_key_1"];
  const classes: OpsEventClass[] = [
    "payment_manual_cancel",
    "enroute_comp_failed",
    "charge_ladder_exhausted", // no bespoke copy → the generic line, held to the same rule
  ];
  for (const cls of classes) {
    for (const routed of [true, false]) {
      const db = scene(routed ? [{ profile_id: MONEY_OPS, event_class: cls, active: true }] : []);
      const cap = captureErrors();
      try {
        await notifyOps(db as never, cls, { refId: BOOKING });
        assertEquals(notes(db).length, 1);
        const n = notes(db)[0];
        const text = `${n.title} ${n.body}`;
        for (const s of secrets) {
          assert(!text.includes(s), `${cls} (routed=${routed}) leaked ${s}: ${text}`);
        }
        // Redaction is only acceptable because the copy says WHERE the detail lives — a body with
        // neither the numbers nor a place to look would just be a shrug.
        assert(
          ["payments_reconciliation", "record_enroute_cancel_comp", "서버 로그"].some((h) => String(n.body).includes(h)),
          `${cls} body names nowhere to look: ${n.body}`,
        );
      } finally {
        cap.restore();
      }
    }
  }
});

Deno.test("a class with no bespoke copy still says WHICH class it is", async () => {
  // The class name is our own identifier, not a customer's data — safe on a stranger's screen, and
  // the only thing that makes a generic ping worth sending.
  const db = scene([{ profile_id: SAFETY_OPS, event_class: "incident_waive_pending", active: true }]);
  const cap = captureErrors();
  try {
    await notifyOps(db as never, "incident_waive_pending", { refId: BOOKING });
    assertEquals(notes(db).length, 1);
    assert(
      String(notes(db)[0].body).includes("incident_waive_pending"),
      `generic copy is not actionable: ${notes(db)[0].body}`,
    );
  } finally {
    cap.restore();
  }
});
