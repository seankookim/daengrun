// transition-booking `cancel_owner` — the EN-ROUTE compensated cancel carries the compensation
// title (gap sweep 2, runner-journey-4, 2026-09-25).
//
//   deno test --allow-all --node-modules-dir=auto _test
//
// The en-route tier's body said 「취소 수수료(결제 금액의 50%)가 러너 보상으로 기록됐어요」 under the
// title 「예약 취소됨」 — a lock screen that read as a plain cancellation, and a tap that the client
// routes to the CALENDAR (notification-route.ts), which shows neither the booking nor the money.
// The title is also a receipt, so it may only name compensation when the ledger row exists.
// (A separate file from cancel_fee_test.ts because that file belongs to no slice in this sweep.)
//
// The mutations that redden it: revert the title ternary to `lateShare > 0` only (the brief's
// plant) · gate the title on the marker alone (a failed or zero-fee comp would print a receipt).
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { cancelOwner } from "../transition-booking/cancel_owner.ts";
import { FakeDb, type Row } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const RUNNER = "33333333-3333-3333-3333-333333333333";
const BOOKING = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const FEE_50 = 6950;

Deno.env.set("OPS_PROFILE_ID", "99999999-9999-9999-9999-999999999999");

/** The client's own constant, read from the TS file so the two spellings cannot part. */
async function clientCompTitle(): Promise<string> {
  const src = await Deno.readTextFile(new URL("../../../app/src/lib/notification-route.ts", import.meta.url));
  const m = src.match(/export const CANCEL_COMP_TITLE = '([^']+)'/);
  assert(m, "notification-route.ts no longer declares CANCEL_COMP_TITLE");
  return m![1];
}

function scene(comp: { written: boolean; comp: number } | { fail: string }, storedFee = FEE_50) {
  const db = new FakeDb();
  db.seed("bookings", [{
    id: BOOKING, owner_id: OWNER, runner_id: RUNNER, status: "runner_enroute",
    total_price: 13900, cancel_fee: null, cancel_reason: null,
  }]);
  db.seed("payments", []);
  db.seed("notifications", []);
  db.seed("ledger_items", []);
  // 0117 §9c's trigger, modelled as cancel_fee_test.ts models it: the stored fee and the tier
  // marker are written together from the ladder when the row enters cancelled_owner.
  db.triggers["bookings"] = (row: Row, before: Row) => {
    if (row.status !== "cancelled_owner" || before.status === "cancelled_owner") return;
    row.cancel_fee = storedFee;
    row.cancel_reason = "owner_cancel_enroute";
  };
  db.rpcs["marketplace_cancel_fee"] = () => ({ data: [{ fee: FEE_50, status: "runner_enroute" }] });
  db.rpcs["record_enroute_cancel_comp"] = () =>
    "fail" in comp ? { error: { message: comp.fail } } : { data: [{ comp: comp.comp, written: comp.written }] };
  db.rpcs["ops_recipients_for"] = () => ({ data: [] });
  db.rpcs["mint_cancel_fee_intent"] = () => ({ data: [] }); // charging not live — no Toss call
  return db;
}

async function cancelAndReadRunnerPush(db: FakeDb): Promise<Row> {
  const sent: Row[] = [];
  const notify = (profile_id: string, title: string, body: string) => {
    sent.push({ profile_id, title, body });
    return Promise.resolve(null);
  };
  const log = console.log, err = console.error;
  console.log = () => {};
  console.error = () => {};
  try {
    await cancelOwner(db as never, { bookingId: BOOKING, uid: OWNER, bk: db.rows("bookings")[0], notify, expectedFee: FEE_50 });
  } finally {
    console.log = log;
    console.error = err;
  }
  const toRunner = sent.filter((s) => s.profile_id === RUNNER);
  assertEquals(toRunner.length, 1, `expected one runner push: ${JSON.stringify(sent)}`);
  return toRunner[0];
}

Deno.test("[runner-journey-4] en-route cancel with the compensation RECORDED → the compensation title, body unchanged", async () => {
  const msg = await cancelAndReadRunnerPush(scene({ written: true, comp: FEE_50 }));
  assertEquals(msg.title, await clientCompTitle());
  assertEquals(msg.title, "시간을 비워둔 보상이 기록됐어요");
  assertStringIncludes(String(msg.body), "러너 보상으로 기록됐어요");
});

Deno.test("[runner-journey-4] en-route cancel whose comp write FAILED keeps 「예약 취소됨」 — the title is a receipt", async () => {
  const msg = await cancelAndReadRunnerPush(scene({ fail: "deadlock detected" }));
  assertEquals(msg.title, "예약 취소됨");
  assertEquals(msg.body, "보호자가 예약을 취소했어요");
});

Deno.test("[runner-journey-4] en-route cancel under the zero-fee waiver (comp not written) keeps 「예약 취소됨」", async () => {
  // The marker is still owner_cancel_enroute here — so a title gated on the marker alone would
  // print a compensation receipt for a cancellation that moved no money.
  const msg = await cancelAndReadRunnerPush(scene({ written: false, comp: 0 }, 0));
  assertEquals(msg.title, "예약 취소됨");
  assert(!String(msg.body).includes("러너 보상으로 기록됐어요"), `a receipt for no row: ${msg.body}`);
});
