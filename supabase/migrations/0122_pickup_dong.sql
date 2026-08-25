-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0122 — pickup 동 (법정동) for the PRE-ACCEPT runner request card
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean's Q6 ruling, verbatim (2026-08-25, docs/decisions/awaiting-sean.md §0-undetricies):
--   「q6: if the runner is searching for a run, then a how far away they are from the starting
--    point is a metric they need to see and doesnt show the actual address anyways; also
--    include the 동.」  [end of his words]
--
-- 🔴 THIS FILE BUILDS THE 동 HALF ONLY. The distance half of the same sentence is NOT here and
--    is NOT smuggled in: it needs the RUNNER's own coordinate, i.e. a location reading taken
--    while no run is in progress, and `docs/legal/privacy-policy.md` currently publishes the
--    opposite sentence (「러닝 중이 아닐 때는 위치를 수집하지 않습니다」). That question went to
--    counsel on 2026-08-25 (`docs/biz/location-law-counsel-brief.md` §추가 질의, question 4 of
--    that section explicitly carves the 동 half out as proceeding independently), and the
--    product options (A/B/C) are still Sean's. Nothing in this file reads, stores, derives or
--    returns a runner coordinate, and nothing here returns a pickup coordinate either.
--
-- ── DATA CLASSIFICATION, stated because it is the whole reason this is buildable ────────────
-- A 법정동 label of a FIXED home address is **개인정보 at 동 granularity — not 위치정보**. It is
-- the same class as `addresses.addr` (which the product already stores and already discloses,
-- through `booking_pickup_address`): a property of a place the owner typed in, not a reading of
-- where a person is right now. 0120's own header draws the same line for the opposite reason —
-- 「a fixed address is 개인정보 not 위치정보」 — which is why that slice deliberately left
-- `booking_pickup_address` untouched. Consequences that follow from the classification and are
-- implemented below rather than asserted:
--   · at rest the column inherits `addresses`' owner-only RLS (`0002:82 "addresses owner all"`),
--     exactly like `addr`/`detail`/`lat`/`lng`;
--   · disclosure happens ONLY through the one definer window in §3, whose row set is the set of
--     requests the caller can already see;
--   · no 위치정보법 제16조 ledger row is written, because no 개인위치정보 is provided. If counsel
--     disagrees with the classification (question 4 of the brief), the remedy is to route §3
--     through 0120's `location_access_log` — a change to ONE function, which is why the window
--     is a single choke point.
--
-- ── WHAT THIS FILE REFUSES TO DO (the contract, so a reviewer can execute it) ───────────────
--   ✗ it does not touch `booking_pickup_address` (0060 + 0065) by a single byte — the sealed
--     assigned-runner-only address window keeps its five-column shape and its gates;
--   ✗ it does not add a column to `marketplace_open_requests` — 98 H6 pins that view at exactly
--     17 columns, name and ordinal, and it is right to: the view is the open-pool choke point;
--   ✗ §3 never returns lat/lng/addr/label/detail/gate_code_enc/address_id or any other
--     coordinate-shaped value. Its declared return type is two columns and that is the seal;
--   ✗ §3 never raises for a caller without a JWT — `auth.uid() is null` is 0 rows. And the role
--     (`current_user`) is never consulted as an identity: BLOCKER-10's class, where a definer
--     asks who it is RUNNING as instead of who CALLED it and therefore answers `postgres`.
--
-- ── WHY NO WRITER FUNCTION (the shape decision, stated as required) ────────────────────────
-- The minimal correct writer is **no SQL writer at all**. `dong` is derived from the coordinates
-- the owner already pinned, by reverse-geocoding them against NCP — an outbound HTTP call, which
-- Postgres cannot make and should not. So the single writer is the `geocode-address` edge
-- function running as `service_role` (§2 of this file's client/edge half), which reads the row's
-- OWN lat/lng after a party gate and writes the label back. The client never supplies a 동, and
-- §2 below makes that structural rather than conventional.

-- ═══ §1 the column ════════════════════════════════════════════════════════════════════════
-- Nullable with no default and no backfill. NULL means "not known yet" and the client renders
-- absence, never a placeholder — an invented 동 on a stranger's card is worse than no 동.
alter table addresses add column dong text;

-- Length cap only. 20 is ~4× the longest real 법정동 name and exists to bound a field that is
-- printed on someone else's screen, not to validate 행정구역 vocabulary (we have no such
-- vocabulary and a regex pretending to have one is 0119 §A's "verification field with no
-- verifier"). The lower bound is part of the same cap and carries 0073's recorded rule: '' and
-- NULL must not become two ways to say "unknown", because the render is `dong ? … : nothing`
-- (Correction, blind review MINOR-6: the earlier claim that '' would DRAW an empty token was
-- wrong — '' is falsy in JS and every render site already omits it. The lower bound survives as
-- a data-hygiene belt only: '' and NULL must not become two spellings of 'unknown' in the column
-- itself, 0073's recorded rule. It is pinned now, so a loosened bound cannot pass silently.)
alter table addresses add constraint addresses_dong_len
  check (dong is null or char_length(dong) between 1 and 20);

comment on column addresses.dong is
  '법정동 label (개인정보 at 동 granularity, NOT 위치정보 — 0122 header). Derived server-side by
reverse-geocoding this row''s own lat/lng; NULL until the owner pins the address and the
reverse call succeeds. Owner-only at rest (0002:82); the ONLY disclosure path is
open_request_pickup_dong() (0122 §3), which hands it to runners who can already see the
request. Written by service_role alone — client writes are refused by _guard_address_dong (§2).';

-- ═══ §2 the column is server-owned — a client may not author it ═══════════════════════════
-- Why this belt exists, and why it is not scope creep: `addresses` has **no column grants
-- anywhere** (0073 §2 measured this and recorded it as a pre-existing hole needing its own
-- slice), so `authenticated` holds table-wide UPDATE and an owner's own row is fully writable
-- by that owner over PostgREST. Every OTHER column on the table is the owner's own statement
-- about their own home, so that is merely untidy. `dong` is different in kind: it is the first
-- column on this table that is (a) written by the server from a derivation and (b) **printed to
-- a stranger before they accept anything**. Left ungated it is a free-text channel from an owner
-- to a pre-accept runner — the same class 0114 §C.6 closed by refusing to print `pace_label` on
-- a nomination card. So the slice that OPENS the disclosure closes its own write path, and the
-- table-wide REVOKE stays 0073 §2's separate slice, untouched here.
--
-- ⚠ A `current_user` branch is CORRECT here and wrong three files away, and the difference is
-- the same one 0119 §D wrote down: this guard protects a SERVER column FROM a client, so asking
-- the role is asking exactly the right question; 0119's gate protects a dog from the product,
-- whose real writers ARE service_role and definers, so a role branch there would exempt every
-- writer. Copied shape: `_guard_booking_insert_cols` (0083 §2), same table-guard family.
create or replace function _guard_address_dong() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    -- INSERT: a row may be born without a 동 (that is the normal path — addAddress writes
    -- label/addr/detail/is_default and nothing else). It may not be born WITH one.
    -- UPDATE: the value may not move, in either direction, including to NULL. `is distinct
    -- from` is deliberate — `<>` is NULL-blind and would let a client erase the label.
    if (tg_op = 'INSERT' and new.dong is not null)
       or (tg_op = 'UPDATE' and new.dong is distinct from old.dong)
    then
      raise exception 'address_dong_server_only'
        using detail = '동 정보는 서버가 지도에서 확인해 기록해요 — 직접 입력할 수 없어요';
    end if;
  end if;
  -- ⚠ [blind review BLOCKER-1 / MAJOR-2, 2026-08-25 — the reviewer EXECUTED both failures and
  -- this fix] THE LABEL IS DERIVED FROM (lat,lng); WHEN THE PIN MOVES OR IS ERASED, THE
  -- DERIVATION IS STALE AND MUST CLEAR. Without this arm, two shipped guarantees were silently
  -- false: (1) `delete_my_account_tx` (0115) redacts lat/lng but never learned this column, so
  -- a withdrawn user's 법정동 survived account deletion FOREVER on a row that is deliberately
  -- kept as an FK anchor — measured: dong='반포동' after deletion, against 0115:443's own
  -- invariant "LOCATES NOTHING AND IDENTIFIES NOBODY". (2) A moved pin whose reverse geocode
  -- failed printed the OLD 동 on a stranger's card indefinitely, and the write seal above meant
  -- neither party could correct it. One arm closes both: 0115's anonymisation sets lat/lng to
  -- NULL, which lands here as a coordinate change and clears the label — no edit to shipped
  -- 0115 needed. A same-coordinate re-pin (the no-op confirm) preserves the label; the
  -- service_role reverse writer lands AFTER this trigger's row and re-derives freely.
  if tg_op = 'UPDATE' and (new.lat, new.lng) is distinct from (old.lat, old.lng) then
    new.dong := null;
  end if;
  return new;
end $$;

drop trigger if exists _guard_address_dong_write on addresses;
create trigger _guard_address_dong_write before insert or update on addresses
  for each row execute function _guard_address_dong();

comment on function _guard_address_dong is
  '0122 §2 — addresses.dong is server-authored. authenticated/anon may neither set it on INSERT
nor change it on UPDATE (including to NULL). service_role (the geocode-address reverse writer),
postgres and definer functions are unaffected. This does NOT seal the rest of the table —
0073 §2''s table-wide REVOKE is still its own slice.';

-- ═══ §3 the disclosure window — two flat columns, one row set, no coordinates ══════════════
-- Row set = **exactly what the caller can already see**, expressed by INHERITING the existing
-- choke point rather than by re-typing its predicate:
--   ⓐ `select id from marketplace_open_requests` — the 0042 view as narrowed by 0056. Its five
--      gates (status='matching' · runner_id is null · club_session_id is null ·
--      is_active_runner() · not-declined-by-me) come along for free and, more importantly,
--      CANNOT DRIFT from the pool the runner is actually looking at. Re-typing them here would
--      make one gate two, and the next 0056 would fix one of them.
--   ⓑ the caller's own directed rows — `status = 'runner_pending' and runner_id = auth.uid()`,
--      club rows excluded on the same doctrine as the view. These are not in ⓐ (different
--      status) and the client's inbox draws them in the same list, so a card that has the
--      nominee's name on it must not be the one card with no 동.
--
-- `auth.uid() is not null` is written even though `runner_id = auth.uid()` already yields no
-- rows for a NULL uid: a bare `col = auth.uid()` is one schema change away from being the
-- repo's most-repeated bug (a NULL matching a NULL), and the belt costs nothing. Arm ⓐ needs no
-- such belt — is_active_runner() is false for a NULL uid, by its own EXISTS.
--
-- LEFT JOIN, not JOIN, and the poison check rides the ON clause: a booking with no address, an
-- address with no 동 yet, and an address whose owner ≠ the booking's owner (0060's poisoned-row
-- case) all produce the SAME answer — the row is present and `pickup_dong` is NULL. One shape,
-- one meaning of NULL, and no inference channel that distinguishes the three. An inner join
-- would instead make "this booking has no address" a visible fact.
create or replace function open_request_pickup_dong()
returns table (booking_id uuid, pickup_dong text)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.id, a.dong
  from (
    select id from marketplace_open_requests
    union
    select b2.id from bookings b2
    where b2.status = 'runner_pending'
      and auth.uid() is not null
      and b2.runner_id = auth.uid()
      and b2.club_session_id is null
  ) v
  join bookings b on b.id = v.id
  left join addresses a on a.id = b.address_id and a.owner_id = b.owner_id
$$;

revoke execute on function open_request_pickup_dong() from public, anon;
grant  execute on function open_request_pickup_dong() to authenticated;

comment on function open_request_pickup_dong is
  'Pickup 동 for requests the caller can already see (0122 §3, Sean''s Q6 ruling 2026-08-25).
Flat two columns (booking_id, pickup_dong) — no coordinate, no address text, no address id,
ever. Row set = marketplace_open_requests (the 0042/0056 choke point, INHERITED not re-typed)
∪ the caller''s own runner_pending non-club rows. NULL pickup_dong = unknown (no address, no
pin yet, or a poisoned row) and the client renders absence, never a placeholder. No JWT = 0
rows, never an exception. STABLE: this window writes nothing, including no access ledger —
a 동 label of a fixed address is 개인정보, not 개인위치정보 (header).';
