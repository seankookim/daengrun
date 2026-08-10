-- 0065 — address coordinates: pair/bounds CHECK + booking_pickup_address widened
-- (coordinates slice; plan: docs/plans/coordinates-geocoding-plan.md)
--
-- Two changes, both additive for old clients:
--
-- §1 CHECK on addresses(lat,lng). NULL-footgun-aware form (ES-1): CHECK treats a
--   NULL result as pass, so the naive `(both null) or (both between ...)` admits
--   half-pairs — `false OR NULL` is NULL. `(lat is null) = (lng is null)` is a
--   plain boolean even when one side is NULL, which is the whole trick.
--   Bounds 33..39 / 124..132 are Korea-plausible and deliberately disjoint: a
--   lat/lng swap bug becomes a constraint violation instead of silent garbage.
--   Added without NOT VALID — prod must be probed for non-NULL rows before push
--   (rollout step 0.5 in the plan; local seed.sql:28 has one in-bounds row).
--
-- §2 booking_pickup_address returns (label, addr, detail, lat, lng). Return-type
--   change requires DROP (create-or-replace cannot change OUT columns). The drop
--   discards grants and the comment, so both are re-issued below; the generic
--   pins (98 H1 search_path scan, 99 S1 anon definer scan, 100 W2-e anon probe,
--   W10 authenticated positive control) fence the recreation, and W6 pins the
--   widened 5-column contract with a value assertion (constant-NULL mutation
--   turns it red). Gates are byte-identical to 0060: party gate before state
--   gate, single not_runner error for absent/foreign/wrong-status (0054:73
--   anti-oracle), 24h confirmed window, 0-row (not error) for unassigned or
--   poisoned address rows. Coordinates ride the same posture as the address
--   text they accompany — no new audience learns where an owner lives.

-- §1 pair + bounds constraint
alter table addresses
  add constraint addresses_latlng_shape check (
    (lat is null) = (lng is null)
    and (lat is null or (lat between 33 and 39 and lng between 124 and 132))
  );

comment on constraint addresses_latlng_shape on addresses is
  'Coordinates come in pairs and must be Korea-plausible (lat 33-39, lng 124-132). '
  'The (lat is null) = (lng is null) form is deliberate: CHECK passes on NULL, so '
  'the naive OR form silently admits half-pairs. Disjoint bounds make a lat/lng '
  'swap a hard failure. (0065)';

-- §2 widened pickup-address RPC (drop + recreate; see header)
drop function booking_pickup_address(uuid);

create or replace function booking_pickup_address(p_booking uuid)
returns table (label text, addr text, detail text, lat numeric, lng numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- party + state gate (absent / foreign / wrong status all raise the same
  -- string — probing-oracle blocker, unchanged from 0060)
  if not coalesce((
        select b.runner_id = auth.uid()
           and (b.status in ('runner_enroute', 'picked_up', 'active')
                or (b.status = 'confirmed' and b.scheduled_at < now() + interval '24 hours'))
        from bookings b where b.id = p_booking), false)
  then
    raise exception 'not_runner';
  end if;

  -- unassigned (address_id null) · poisoned row (address owner ≠ booking owner)
  -- → 0 rows (not an error), unchanged from 0060
  return query
    select a.label, a.addr, a.detail, a.lat, a.lng
    from bookings b
    join addresses a on a.id = b.address_id
    where b.id = p_booking
      and a.owner_id = b.owner_id;
end $$;

revoke execute on function booking_pickup_address(uuid) from public, anon;
grant  execute on function booking_pickup_address(uuid) to authenticated;

comment on function booking_pickup_address is
  'Pickup address for the assigned runner only (0060, widened by 0065) — flat 5
fields label/addr/detail/lat/lng. Gate: that booking''s runner + (one of the 3
in-flight states | confirmed & starting within 24h). Everything else raises
not_runner (absent/foreign/wrong-status indistinguishable — 0054:73 oracle
doctrine). Unassigned address or owner mismatch → 0 rows (not an error).
lat/lng are NULL until the owner pins the address (client renders the honest
dark state); gate_code_enc remains structurally absent — decryption is its own
slice.';
