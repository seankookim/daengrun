// A test double for `create_booking_hold_tx` (0179) — what the SQL transaction DOES, replayed on a
// FakeDb so the booking suites keep asserting on rows. It is deliberately a FUNCTION the suites
// install, not a FakeDb field: FakeDb is shared with every other function test and must not grow a
// field for one caller's convenience (revoke_billing_keys_test.ts:29's rule).
//
// ⚠ This fake models the CONTRACT (party gate → replay → mismatch → clash → rows → status), not the
// database's atomicity or its locks; those are pinned against a real database by SQL suite 210
// (0179-K1…K8). A green here says the EDGE speaks the contract, nothing more.
import { FakeDb, type Row } from "./fakedb.ts";

const LIVE = ["matching", "runner_pending", "confirmed", "runner_enroute", "picked_up", "active"];

export function installHoldTx(db: FakeDb): Row[] {
  const calls: Row[] = [];
  db.rpcs["create_booking_hold_tx"] = (a: Row) => {
    calls.push(a);
    const dog = db.rows("dogs").find((d) => d.id === a.p_dog);
    if (!dog || dog.owner_id !== a.p_owner) return { error: { message: "forbidden" } };
    if (a.p_address) {
      const ad = db.rows("addresses").find((x) => x.id === a.p_address);
      if (!ad || ad.owner_id !== a.p_owner) return { error: { message: "forbidden" } };
    }
    if (a.p_client_request_id) {
      const ex = db.rows("bookings").find((bk) =>
        bk.owner_id === a.p_owner && bk.client_request_id === a.p_client_request_id
      );
      if (ex) {
        const same = ex.dog_id === a.p_dog &&
          (ex.route_id ?? null) === (a.p_route ?? null) &&
          (ex.address_id ?? null) === (a.p_address ?? null) &&
          ex.scheduled_at === a.p_scheduled_at &&
          Number(ex.km) === Number(a.p_km) &&
          (ex.pace_label ?? null) === (a.p_pace_label ?? null) &&
          JSON.stringify(ex.addons) === JSON.stringify(a.p_addons) &&
          ex.total_price === a.p_total_price &&
          ex.min_fare === a.p_min_fare;
        if (!same) return { error: { message: "request_mismatch" } };
        const hold = db.rows("slot_holds").find((h) => h.booking_id === ex.id);
        return {
          data: {
            booking_id: ex.id, hold_expires_at: hold?.expires_at ?? null,
            total_price: ex.total_price, booking_status: ex.status, unchanged: true,
          },
        };
      }
    }
    const start = new Date(a.p_scheduled_at).getTime();
    const end = start + (Number(a.p_km) * 8 + 25) * 60_000;
    const clash = db.rows("bookings").some((c) => {
      if (c.dog_id !== a.p_dog || !LIVE.includes(c.status)) return false;
      const cs = new Date(c.scheduled_at).getTime();
      const ce = cs + (Number(c.km) * 8 + 25) * 60_000;
      return cs < end && ce > start;
    });
    if (clash) return { error: { message: "dog_slot_clash" } };
    const id = crypto.randomUUID();
    const expires = new Date(Date.now() + (a.p_hold_minutes ?? 5) * 60_000).toISOString();
    const status = a.p_close_to_matching === true ? "matching" : "payment_hold";
    db.rows("bookings").push({
      id, owner_id: a.p_owner, dog_id: a.p_dog, runner_id: null,
      route_id: a.p_route ?? null, address_id: a.p_address ?? null, status,
      scheduled_at: a.p_scheduled_at, km: a.p_km, pace_label: a.p_pace_label ?? null,
      addons: a.p_addons, base_fare: a.p_base_fare, distance_fare: a.p_distance_fare,
      addon_fare: a.p_addon_fare, total_price: a.p_total_price, min_fare: a.p_min_fare,
      recommended_route_id: a.p_recommended_route ?? null, selection_origin: a.p_selection_origin ?? null,
      route_status_at_booking: a.p_route_status ?? null, route_chips: a.p_route_chips ?? {},
      client_request_id: a.p_client_request_id ?? null,
    });
    db.rows("slot_holds").push({
      id: crypto.randomUUID(), runner_id: null, owner_id: a.p_owner,
      starts_at: a.p_scheduled_at, ends_at: new Date(end).toISOString(), expires_at: expires, booking_id: id,
    });
    return { data: { booking_id: id, hold_expires_at: expires, total_price: a.p_total_price, booking_status: status, unchanged: false } };
  };
  return calls;
}
