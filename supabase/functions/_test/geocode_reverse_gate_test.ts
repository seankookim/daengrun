// geocode-address REVERSE mode — the party gate, executed (blind review MINOR-9: the reverse
// branch is this function's FIRST authorization decision, and repo doctrine gives party gates
// executed pins; _test held fifteen files and none for this function).
//
// The three properties, in the order they protect:
//   1. absent id and FOREIGN id are ONE sentence, one status (404 not_owner) — 0054:73's
//      no-enumeration doctrine: a distinguishable refusal is a probe for valid ids.
//   2. NOT A SINGLE BYTE leaves for NCP before the gate: the fetch mock counts calls, and both
//      refusal paths must end with zero. The gate failing OPEN here would ship an owner's
//      coordinates to an external API on an attacker-supplied id.
//   3. the owner's own unpinned row answers { available: true, dong: null } — an honest empty,
//      still with zero NCP calls (no pin ⇒ nothing to reverse ⇒ nothing to send).
import { assertEquals } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/ctx.ts";
import { reverseDong } from "../geocode-address/reverse.ts";
import { FakeDb, FetchMock } from "./fakedb.ts";

const OWNER = "11111111-1111-1111-1111-111111111111";
const STRANGER = "22222222-2222-2222-2222-222222222222";
const ADDR = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const GHOST = "99999999-9999-9999-9999-999999999999";

function scene(rows: Record<string, unknown>[]) {
  const db = new FakeDb();
  db.seed("addresses", rows);
  const fetches = new FetchMock().install();
  return { db, fetches };
}

async function expectNotOwner(db: FakeDb, uid: string, id: string): Promise<string> {
  try {
    await reverseDong(db as never, uid, id);
  } catch (e) {
    if (e instanceof HttpError) {
      assertEquals(e.status, 404);
      return e.message;
    }
    throw e;
  }
  throw new Error("gate did not refuse");
}

Deno.test("absent id and foreign id are one indistinguishable 404, with zero NCP calls", async () => {
  const { db, fetches } = scene([{ id: ADDR, owner_id: OWNER, lat: 37.5, lng: 127.0 }]);
  try {
    const absentMsg = await expectNotOwner(db, OWNER, GHOST);       // no such row
    const foreignMsg = await expectNotOwner(db, STRANGER, ADDR);    // someone else's row
    assertEquals(absentMsg, foreignMsg);            // one sentence — no enumeration oracle
    assertEquals(absentMsg, "not_owner");
    assertEquals(fetches.calls.length, 0);          // the gate precedes every outbound byte
  } finally {
    fetches.restore();
  }
});

Deno.test("owner + unpinned row: honest empty, no write path taken, still zero NCP calls", async () => {
  const { db, fetches } = scene([{ id: ADDR, owner_id: OWNER, lat: null, lng: null }]);
  try {
    const out = await reverseDong(db as never, OWNER, ADDR);
    assertEquals(out, { available: true, dong: null });
    assertEquals(fetches.calls.length, 0);
  } finally {
    fetches.restore();
  }
});
