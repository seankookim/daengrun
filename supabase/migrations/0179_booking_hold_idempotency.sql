-- ═══ 0179: the booking hold is ONE transaction with an idempotency key ═══════════════════════
--
-- BACKEND HONESTY AUDIT 2026-09-17 §(a) #3: `create-booking-hold` had no idempotency key. A
-- double-submit — a slow link, a retried invoke, a second tap the client's `payOnce` guard did not
-- cover — made TWO bookings, and the only thing standing in the way was the same-dog overlap
-- guard, which works only because O-5 §C.1 lands `matching` synchronously (a stale `payment_hold`
-- is deliberately not in its LIVE list). The handler then wrote four statements in a row — the
-- booking insert, two status hops, the hold insert — and a closing CAS, none of them in a
-- transaction, with a `compensate()` deleting what it could when the CAS lost.
--
-- WHAT THIS FILE DOES.
--   §1  `bookings.client_request_id uuid` (nullable — every legacy row and every caller that does
--       not send one is untouched) + a PARTIAL unique index on (owner_id, client_request_id) —
--       0162's chat `client_key` shape. The index is the BELT; the function below is the door.
--   §2  `create_booking_hold_tx(...)` SECURITY DEFINER, service_role only (the `settle_run_tx`
--       shape: an edge that has already validated the JWT hands it the owner). ONE transaction:
--       party gate BEFORE any read of state → per-key and per-dog advisory locks (fixed order) →
--       REPLAY: same owner + same key ⇒ the SAME row, `unchanged: true`, and a reused key with a
--       different payload ⇒ `request_mismatch` → the clash guard (moved in from the edge, because
--       a guard that is not atomic with the insert it guards is a suggestion) → the writes: the
--       draft → quoted → payment_hold ladder (unchanged, so nothing that reads history moves),
--       the hold, and the closing CAS — which cannot lose in here, so `compensate()` has nothing
--       left to do and is deleted from the edge. Any raise rolls ALL of it back.
--   §3  VERIFY.
--
-- THE KEY IS OPTIONAL SERVER-SIDE, and that is a decision rather than an omission: the client
-- half ships in this same slice (`api.ts` mints a v4 uuid per submit attempt and reuses it on a
-- retry of the same payload), but installed builds do not update on our schedule. A 400 for an
-- absent key would break every one of them the day this deploys. So a NULL key means 「no
-- idempotency」 — the pre-slice behaviour, exactly — and the 400 is owed the day the store build
-- with the client half is the oldest build in use. Said here so it is a dated obligation.
--
-- REFUSAL TOKENS (the edge maps each to the sentence the client already keys on):
--   not_signed_in · missing_fields · km_out_of_range   belts behind the edge's own 400s
--   forbidden           the dog (or address) is not the owner's — absent and stranger say the SAME
--                       word (0054:73's enumeration-oracle rule), judged BEFORE the replay read
--   request_mismatch    same owner + same key, different slot/money payload
--   dog_slot_clash      a LIVE booking of this dog overlaps (LIVE = matching · runner_pending ·
--                       confirmed · runner_enroute · picked_up · active; NOT payment_hold — a stale
--                       hold must never block a retry, O-5 §C.1b)
--   hold_close_failed   the closing CAS moved 0 rows — unreachable in one transaction on a row
--                       this transaction just inserted, kept as the loud belt it always was
--
-- WHAT THE MISMATCH COMPARES, and why only these: dog · route · address · scheduled_at · km ·
-- pace_label · addons · total_price · min_fare — the fields that define the SLOT and the MONEY.
-- The 0082 analytics snapshot (recommended_route_id · selection_origin · route_chips) is NOT
-- compared: a retry that re-derives a chip is the same request, and refusing it would turn an
-- analytics field into a money gate.
--
-- ⚠ WHAT THE DOG LOCK COVERS, exactly: every caller of THIS function. `generate_recurring_bookings`
--   (0111:317-322, :369) runs its own clash check with no lock and inserts straight at
--   `matching`/`runner_pending`, so the weekly cron and an edge request for the same dog can still
--   both pass — as they could before this file. Not widened here (that function is 0111's and the
--   cron's); named so the header's sentence is not broader than the file. The same lock key text
--   taken there is the one-line fix when that slice comes.
-- ⚠ The ladder (draft → quoted → payment_hold) is enforced by the booking-transition trigger, not
--   by this file's good manners: collapsing it to one hop aborts the apply (measured by the cold
--   reader: `invalid booking transition: draft -> payment_hold`).
--
-- ⚠ LOCK ORDER IS FIXED — key lock first (when a key is present), then the dog lock — and both are
--   transaction-scoped advisory locks, so two requests can never take them in opposite orders.
--   The key lock makes the same-key race take the replay path (the second waits, then finds the
--   row) instead of hitting the unique index; the dog lock makes the clash guard atomic with the
--   insert it guards (two overlapping holds for one dog serialize, and the second SEES the first).
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 210's header and the REGISTRY row.

-- ═══ §1 the key and its belt ═══
alter table bookings add column if not exists client_request_id uuid;
create unique index if not exists bookings_owner_client_request_uni
  on bookings (owner_id, client_request_id)
  where client_request_id is not null;
comment on column bookings.client_request_id is
  '0179: client-minted idempotency key, one per submit attempt; unique per owner when present. NULL = the caller sent none (legacy builds).';

-- ═══ §2 the transaction ═══
create or replace function create_booking_hold_tx(
  p_owner uuid,
  p_dog uuid,
  p_scheduled_at timestamptz,
  p_km numeric,
  p_addons jsonb,
  p_base_fare int,
  p_distance_fare int,
  p_addon_fare int,
  p_total_price int,
  p_min_fare int,
  p_close_to_matching boolean,
  p_client_request_id uuid default null,
  p_route uuid default null,
  p_address uuid default null,
  p_pace_label text default null,
  p_recommended_route uuid default null,
  p_selection_origin text default null,
  p_route_status text default null,
  p_route_chips jsonb default '{}'::jsonb,
  p_hold_minutes int default 5
)
returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_dog_owner  uuid;
  v_addr_owner uuid;
  v_bk         bookings%rowtype;
  v_id         uuid;
  v_start      timestamptz;
  v_end        timestamptz;
  v_expires    timestamptz;
  v_status     booking_status;
  v_n          int;
  v_addons     jsonb := coalesce(p_addons, '[]'::jsonb);
  v_chips      jsonb := coalesce(p_route_chips, '{}'::jsonb);
begin
  -- 0 shape belts (the edge refuses these with its own 400s; here so the door stands alone)
  if p_owner is null then
    raise exception 'not_signed_in';
  end if;
  if p_dog is null or p_scheduled_at is null or p_km is null then
    raise exception 'missing_fields';
  end if;
  if p_km < 1 or p_km > 10 or (p_km * 2) <> floor(p_km * 2) then
    raise exception 'km_out_of_range';
  end if;

  -- 1 PARTY gate, before any read of booking state — absent and stranger say the same word
  select d.owner_id into v_dog_owner from dogs d where d.id = p_dog;
  if v_dog_owner is distinct from p_owner then
    raise exception 'forbidden';
  end if;
  if p_address is not null then
    select a.owner_id into v_addr_owner from addresses a where a.id = p_address;
    if v_addr_owner is distinct from p_owner then
      raise exception 'forbidden';
    end if;
  end if;

  -- 2 serialize: the key first (same-key requests take the replay path in turn), then the dog
  --   (the clash guard below is atomic with the insert it guards). Fixed order, never reversed.
  if p_client_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('booking_hold_key:' || p_owner::text || ':' || p_client_request_id::text, 0));
  end if;
  perform pg_advisory_xact_lock(hashtextextended('booking_hold_dog:' || p_dog::text, 0));

  -- 3 REPLAY: the same owner and the same key name the same row, whatever it has become since
  if p_client_request_id is not null then
    select * into v_bk from bookings b
     where b.owner_id = p_owner and b.client_request_id = p_client_request_id;
    if found then
      if v_bk.dog_id        is distinct from p_dog
      or v_bk.route_id      is distinct from p_route
      or v_bk.address_id    is distinct from p_address
      or v_bk.scheduled_at  is distinct from p_scheduled_at
      or v_bk.km            is distinct from p_km
      or v_bk.pace_label    is distinct from p_pace_label
      or v_bk.addons        is distinct from v_addons
      or v_bk.total_price   is distinct from p_total_price
      or v_bk.min_fare      is distinct from p_min_fare then
        raise exception 'request_mismatch';
      end if;
      -- [cold review #7] A replay may CLOSE what the first attempt left open. Unreachable today
      -- (the edge always asks to close while charging is off), but the day the §C.3 gate goes a
      -- widget owner's first attempt lands `payment_hold`, they register a card and retry with the
      -- SAME key — and a replay that only echoed the row would hand back `payment_hold` with no
      -- screen left to move it (the `e_hold` strand, rebuilt by design). Same CAS, same belt.
      if p_close_to_matching is true and v_bk.status = 'payment_hold' then
        update bookings set status = 'matching' where id = v_bk.id and status = 'payment_hold';
        get diagnostics v_n = row_count;
        if v_n = 1 then v_bk.status := 'matching'; end if;
      end if;
      return jsonb_build_object(
        'booking_id',      v_bk.id,
        'hold_expires_at', (select to_char(max(h.expires_at) at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                              from slot_holds h where h.booking_id = v_bk.id),
        'total_price',     v_bk.total_price,
        'booking_status',  v_bk.status,
        'unchanged',       true);
    end if;
  end if;

  -- 4 the clash guard, under the dog lock (the edge's guard, moved in: km*8+25 minutes, LIVE only)
  v_start := p_scheduled_at;
  v_end   := p_scheduled_at + make_interval(mins => (p_km * 8 + 25)::int);
  if exists (
    select 1 from bookings c
     where c.dog_id = p_dog
       and c.status in ('matching', 'runner_pending', 'confirmed', 'runner_enroute', 'picked_up', 'active')
       -- no ±6h narrowing (the edge's had one as an index hint): the exact overlap predicate is
       -- complete on its own, and a hint that could hide a long same-dog booking (cold review #8,
       -- measured on a km=100 row nothing but the edge's 1–10 bound forbids) is not worth an index.
       and c.scheduled_at < v_end
       and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
  ) then
    raise exception 'dog_slot_clash';
  end if;

  -- 5 the writes — the ladder unchanged (draft → quoted → payment_hold), then the hold, then the CAS
  insert into bookings (
    owner_id, dog_id, runner_id, route_id, address_id, status, scheduled_at, km, pace_label, addons,
    base_fare, distance_fare, addon_fare, total_price, min_fare,
    recommended_route_id, selection_origin, route_status_at_booking, route_chips, client_request_id
  ) values (
    p_owner, p_dog, null, p_route, p_address, 'draft', p_scheduled_at, p_km, p_pace_label, v_addons,
    p_base_fare, p_distance_fare, p_addon_fare, p_total_price, p_min_fare,
    p_recommended_route, p_selection_origin, p_route_status, v_chips, p_client_request_id
  ) returning id into v_id;
  update bookings set status = 'quoted'       where id = v_id;
  update bookings set status = 'payment_hold' where id = v_id;

  v_expires := now() + make_interval(mins => coalesce(p_hold_minutes, 5));
  insert into slot_holds (runner_id, owner_id, starts_at, ends_at, expires_at, booking_id)
  values (null, p_owner, v_start, v_end, v_expires, v_id);

  v_status := 'payment_hold';
  if p_close_to_matching is true then
    update bookings set status = 'matching' where id = v_id and status = 'payment_hold';
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'hold_close_failed';
    end if;
    v_status := 'matching';
  end if;

  return jsonb_build_object(
    'booking_id',      v_id,
    'hold_expires_at', to_char(v_expires at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'total_price',     p_total_price,
    'booking_status',  v_status,
    'unchanged',       false);
end $$;

revoke execute on function create_booking_hold_tx(uuid, uuid, timestamptz, numeric, jsonb, int, int, int, int, int, boolean, uuid, uuid, uuid, text, uuid, text, text, jsonb, int)
  from public, anon, authenticated;
grant  execute on function create_booking_hold_tx(uuid, uuid, timestamptz, numeric, jsonb, int, int, int, int, int, boolean, uuid, uuid, uuid, text, uuid, text, text, jsonb, int)
  to service_role;

comment on function create_booking_hold_tx is
  '0179 (audit §(a) #3): the booking hold as ONE transaction — party gate, key+dog locks, replay on (owner, client_request_id) ⇒ the same row / request_mismatch, the clash guard, the ladder, the hold, the closing CAS. service_role only; the edge hands it the validated owner. NULL key = no idempotency (legacy builds).';

-- ═══ §3 VERIFY — apply-time, and NOT a substitute for suite 210 ═══
do $$
declare
  v_oid oid;
  v_src text;
  v_acl text;
  v_bad text := '';
  v_idx text;
begin
  if (select count(*) from pg_attribute where attrelid = 'public.bookings'::regclass
        and attname = 'client_request_id' and not attisdropped) is distinct from 1
    then v_bad := v_bad || ' NO-COLUMN(client_request_id)'; end if;
  select pg_get_indexdef(i.indexrelid) into v_idx
    from pg_index i join pg_class c on c.oid = i.indexrelid
   where c.relname = 'bookings_owner_client_request_uni';
  if v_idx is null then v_bad := v_bad || ' NO-INDEX';
  else
    if (select indisunique from pg_index i join pg_class c on c.oid = i.indexrelid
          where c.relname = 'bookings_owner_client_request_uni') is distinct from true
      then v_bad := v_bad || ' INDEX-NOT-UNIQUE'; end if;
    if (v_idx ~ '\(owner_id, client_request_id\)') is distinct from true
      then v_bad := v_bad || ' INDEX-WRONG-COLUMNS'; end if;
    if (v_idx ~* 'where \(?client_request_id is not null\)?') is distinct from true
      then v_bad := v_bad || ' INDEX-NOT-PARTIAL'; end if;
  end if;

  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'create_booking_hold_tx';
  if v_oid is null then
    raise exception '0179 VERIFY FAILED: NO-FUNCTION(create_booking_hold_tx)';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'create_booking_hold_tx') is distinct from 1
    then v_bad := v_bad || ' OVERLOADS'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
    then v_bad := v_bad || ' NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
        from pg_proc where oid = v_oid) is distinct from true
    then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false
    then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-is-default)'; end if;
  select array_to_string(proacl, ',') into v_acl from pg_proc where oid = v_oid;
  if (coalesce(v_acl, '') ~ '(^|,)=[^/]*X') is distinct from false
    then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-entry)'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' service_role-CANNOT-EXECUTE'; end if;

  -- source ORDER, comments stripped: party gate → locks → replay read → clash → insert; no handler
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = v_oid;
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE';
  else
    if (v_src ~ '''forbidden''' and v_src ~ '''request_mismatch''' and v_src ~ '''dog_slot_clash'''
        and v_src ~ '''hold_close_failed''') is distinct from true
      then v_bad := v_bad || ' TOKENS-MISSING'; end if;
    if (position('''forbidden''' in v_src) > 0
        and position('''forbidden''' in v_src) < position('pg_advisory_xact_lock' in v_src)) is distinct from true
      then v_bad := v_bad || ' PARTY-GATE-NOT-FIRST'; end if;
    if (position('pg_advisory_xact_lock' in v_src) > 0
        and position('pg_advisory_xact_lock' in v_src) < position('client_request_id = p_client_request_id' in v_src)) is distinct from true
      then v_bad := v_bad || ' LOCK-NOT-BEFORE-REPLAY-READ'; end if;
    if (position('''dog_slot_clash''' in v_src) > 0
        and position('''dog_slot_clash''' in v_src) < position('insert into bookings' in v_src)) is distinct from true
      then v_bad := v_bad || ' CLASH-GUARD-AFTER-INSERT'; end if;
    if (v_src ~* 'exception\s+when') is distinct from false
      then v_bad := v_bad || ' EXCEPTION-HANDLER(atomicity)'; end if;
  end if;

  if v_bad <> '' then
    raise exception '0179 VERIFY FAILED:%', v_bad;
  end if;
end $$;
