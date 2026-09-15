-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0174 — `payments_reconciliation()` gets a per-row KEY that is never NULL
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 204_reconciliation_group_key_suite.sql (tag `rgk`).
-- Closes fix-wave-2 re-attack **R2** (`docs/reviews/2026-09-15-fixwave2-reattack-verdict.md`):
--   *「Arms seven and eight both emit `payment_id = NULL` … and SQL groups all NULLs together
--   exactly as the base warning states. Their booking populations being disjoint does not help:
--   different bookings still share the same grouped NULL key.」*
--
-- ⚠ THIS IS A READ. It moves no money, mints nothing, writes nothing. Its entire effect is that
--   `select * from payments_reconciliation()` returns one more COLUMN than it did before.
--
-- ═══ WHOSE OBJECT THIS FILE RE-CREATES (REGISTRY.md silent-collision law) ═══════════════════
--   `payments_reconciliation`  ← 0076 §D → 0080 → 0084 §C (five arms) → 0118 §G (seven) →
--   **0173 §A (eight)**. `0173:141` is the LAST definition and is the base here, carried forward
--   with every arm's PREDICATES byte-identical; the only edit inside the body is one extra
--   select-list expression appended to each of the eight arms. Nothing else in the repo creates
--   or replaces it.
--
-- ═══ ① THE DEFECT, stated as the sentence the fix has to satisfy ════════════════════════════
--   `0118:1372-1376` addressed a warning to whoever added arm eight, and 0173 read it, measured
--   「no shipped pin moved」, and wrote down WHY: arm seven needs a CANCELLED club booking and arm
--   eight needs a stamped settled run, so nothing in the fixture chain can hold one of each at the
--   same moment. That record was honest and it was not a fix — 0173's own header says so:
--   *「the pins are green because the two populations are disjoint in this fixture chain, not
--   because anything asserts they must stay disjoint」*.
--   The re-attack is narrower and worse than 「one of each」: **two rows from arm EIGHT ALONE, on
--   two different bookings, already collide**, because both carry `payment_id = NULL` and
--   `group by payment_id` puts every NULL in one group. Suite 203 creates four such rows and
--   never re-runs the invariant afterwards. The duplicate-detector fires on a state that is
--   CORRECT — two different bookings, each visible once — which is the worst direction for an ops
--   board: the pin that exists to say 「this board lists one row twice」 says it about a board that
--   does not.
--
-- ═══ ② THE KEY, and why it is NOT prefixed with the arm name ════════════════════════════════
--       row_key  =  coalesce(payment_id::text, 'booking:' || booking_id::text)
--   read per-arm as the literal it is (`p.id::text` in arms one…six, `'booking:' || b.id::text`
--   in arms seven and eight), never as a `coalesce` over a column that cannot be NULL there.
--
--   🔴 **The obvious form — `arm || ':' || coalesce(payment_id, booking_id)` — silently DELETES
--   the property the invariant exists for, and it is worth writing down because it is what a
--   reader reaches for first.** `116 C11`'s own mutation map says the pin must redden when you
--   *「widen any arm so two arms claim one row」*. Prefix the key with the arm and that row gets
--   TWO DIFFERENT keys — `stale_pending:<uuid>` and `stale_dispatched:<uuid>` — so
--   `group by row_key having count(*) > 1` finds nothing, and the pin becomes incapable of
--   failing for the single case it was written for. A key that makes every row unique is not a
--   group key; it is the absence of one wearing a group key's costume. Measured rather than
--   argued: with the key below, widening `stale_pending` to swallow a dispatched row — one
--   payments row claimed by TWO arms — still reddens **116 C11** (`두 팔에 동시 등장하는 행 1개`).
--   ⚠ Written after the run, not before it: J4 stays GREEN under that plant, because its own
--   fixture holds no pending row old enough for the widened arm at the moment it executes. C11 is
--   the door this property is observable through; J4 is re-keyed for correctness going forward,
--   not because this battery can see it move.
--
--   So the key is a SUBJECT identity, not a row identity. The subject of arms one…six is the
--   payments row; the subject of arms seven and eight is the BOOKING, because there is no
--   payments row — that absence is the finding (`0118:1387-1389`, `0173:⑥`). Two rows share a key
--   exactly when they are two claims about one subject, which is precisely the sentence C11 and
--   J4 were written to enforce and precisely the sentence `payment_id` stopped expressing the
--   moment a second NULL-emitting arm existed.
--   ⚠ The `'booking:'` prefix is not decoration: it keeps the two key SPACES disjoint by
--   construction rather than by luck. A bare `booking_id::text` would be a uuid in the same
--   namespace as a payment uuid, and 「they will never collide」 is an argument, not a guarantee.
--
--   ⚠ **NAMED, and deliberate: arm seven and arm eight on the SAME booking still collide.** That
--   is not a residue of the old bug — it is the invariant doing its job. One booking claimed by
--   two arms IS one subject listed twice, and an operator reading the board would see the same
--   booking under two names. 0173 argues the two populations cannot overlap; if that ever stops
--   being true, this key is what says so.
--
-- ═══ ③ WHY THIS FILE DROPS THE FUNCTION, WHICH THIS REPO OTHERWISE REFUSES TO DO ════════════
--   🔴 **MEASURED, on a scratch PG16 cluster, 2026-09-15 — `create or replace` CANNOT do this:**
--       create function f() returns table (a text, b int) …            → CREATE FUNCTION
--       create or replace function f() returns table (a text, b int, c text) …
--         → ERROR:  cannot change return type of existing function
--           DETAIL:  Row type defined by OUT parameters is different.
--           HINT:  Use DROP FUNCTION f() first.
--   `0173:⑥` predicted exactly this and concluded 「the reason must ride an existing column」,
--   which is what arm eight does with `payment_status`. A group KEY cannot ride an existing
--   column — every one of the eight is already carrying a meaning, and overloading one would
--   re-create the same ambiguity one level down. So the column is real, and the drop is the price.
--
--   The two reasons the house law gives for refusing a drop are both answered, by value:
--     · **Grant preservation.** The whole point of `create or replace` here was to keep the ACL.
--       This file does not RELY on preservation at all — it restates the ACL verbatim below
--       (`0118:1454-1455`, the file that last set it, carried through `0173:262-263`), which is
--       the thing the law actually demands (*「Write the `revoke` explicitly, every time」*). The
--       drop and the create are in ONE migration file, and `supabase db push` — mirrored by the
--       harness's `--single-transaction`, self-pinned at `harness.sh:81` — applies a file inside
--       one transaction, so there is no instant at which the function is absent or PUBLIC.
--     · **「seven shipped suites read it」.** Swept by hand, because no tool points at this: every
--       read in `109`, `116`, `120`, `153`, `203` is either `select count(*) … from
--       payments_reconciliation() where <named columns>` or `select r.<named column> into …`.
--       There is no `select *` into a fixed-arity target and no positional read anywhere, so an
--       appended column is invisible to all of them. The two that group by `payment_id` are the
--       point of this slice and are moved below.
--   **Dependency check, and it fails CLOSED either way:** no view, function or default in the
--   repo references `payments_reconciliation` (swept across `supabase/migrations/*.sql`; every hit
--   is a prior definition, an ACL line, a comment or a prose mention). A dependant nobody found
--   would make the bare `drop function` raise and abort the apply — which is the correct outcome,
--   not a silent one. `if exists` covers a partial-apply environment where the function is absent;
--   it does not weaken that, because the `create` immediately follows.
--
-- ═══ ④ BLAST RADIUS OUTSIDE SQL, enumerated by hand (the widening-a-return's-meaning law) ═══
--   `payments_reconciliation()` still has NO runtime caller: zero `.rpc("payments_reconciliation")`
--   in `supabase/functions` and `app/`. `_shared/ops.ts` is the only code-level dependant and it
--   **never reads a row** — its `RECONCILIATION_ARM` map (`ops.ts:89-105`) turns an ops event class
--   into the ARM NAME it interpolates into a Korean sentence telling an operator which arm to look
--   at. It touches no column, by name or by position, so an appended column cannot reach it. No
--   TypeScript changes in this slice and `_test/ops_routing_test.ts` is untouched.
--   ⚠ Said in the direction that can be wrong: if a later slice makes an edge function SELECT from
--   this query, `row_key` is the handle it should key an ops-board row on — not `payment_id`,
--   which is NULL for two of the eight arms and will be NULL for every future bookings-anchored
--   arm, because a bookings-anchored arm exists precisely when there is no payments row.
--
-- ═══ ⑤ THE TWO SHIPPED PINS MOVE, per the suite-update law ══════════════════════════════════
--   `116 C11` and `120 J4` each end with the same idiom —
--   `select payment_id from payments_reconciliation() group by payment_id having count(*) > 1` —
--   and both are re-keyed onto `row_key` in this same slice, with the reason written at the site.
--   **What they assert is not weakened**: on the payment-bearing arms `row_key` is
--   `payment_id::text` and the grouping is byte-for-byte the old one (204 `0174-K3` pins that
--   identity as a fact that can fail); on the NULL-payment arms it stops flattening distinct
--   subjects into one group. 0174 owns the new property; 204 `0174-K1`…`K4` are its pins.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══ §A — `payments_reconciliation`: 0173 §A predicate-faithful, plus `row_key` ═════════════
-- The drop is forced by PostgreSQL (§③) and is paired with the create in one transaction.
drop function if exists payments_reconciliation();

create or replace function payments_reconciliation()
returns table (
  kind text,
  payment_id uuid,
  booking_id uuid,
  amount int,
  payment_status text,
  booking_status text,
  needs_manual_cancel boolean,
  age interval,
  -- [0174] the group key. NEVER NULL, and appended LAST so every existing by-name reader is
  -- unchanged. Arms one…six key on the payments row; arms seven and eight key on the BOOKING,
  -- because they exist exactly when there is no payments row to key on.
  row_key text
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select 'orphan_capture'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         coalesce((p.raw->>'needs_manual_cancel')::boolean, false), now() - p.created_at,
         p.id::text
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'confirmed'
    and b.status in ('draft', 'quoted', 'payment_hold', 'expired')
  union all
  select 'stale_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at,
         p.id::text
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending' and p.created_at < now() - interval '1 hour'
    and (p.raw->>'dispatched_at') is null
  union all
  select 'stale_dispatched'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'dispatched_at')::timestamptz,
         p.id::text
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending'
    and (p.raw->>'dispatched_at') is not null
    and (p.raw->>'dispatched_at')::timestamptz < now() - interval '1 hour'
  union all
  select 'ladder_exhausted'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at,
         p.id::text
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'failed'
    and (p.raw->>'kind') is not null
    and coalesce((p.raw->>'attempts')::int, 0) >= 3
  union all
  select 'incident_waive_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'review_opened_at')::timestamptz,
         p.id::text
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'waived'
    and (p.raw->>'review') = 'incident_pending'
    and (p.raw->>'review_resolved_at') is null
  union all
  select 'refund_shaped_server_charge'::text, p.id, p.booking_id, p.amount, p.status,
         b.status::text, false, now() - p.created_at,
         p.id::text
  from payments p join bookings b on b.id = p.booking_id
  where p.status in ('canceled', 'partial_canceled')
    and (p.raw->>'kind') is not null
    and exists (select 1 from runs r where r.booking_id = b.id and r.settled_at is not null)
  union all
  select 'club_fee_unminted'::text, null::uuid, b.id, b.cancel_fee, null::text,
         b.status::text, false, now() - b.club_fee_event_at,
         -- [0174] no payments row exists, so the SUBJECT is the booking (0118:1387-1389)
         'booking:' || b.id::text
  from bookings b
  where b.club_fee_event_at is not null
    and b.club_fee_event_at < now() - interval '1 hour'
    and _club_fee_event_collectable(b.id)
    and not exists (select 1 from _cancel_fee_existing_payment(b.id))
  union all
  -- ── [0173] ARM EIGHT — `settled_without_payment` ─────────────────────────────────────────
  -- The run settled, the sweep has had an hour of five-minute ticks, and there is still no
  -- payments row. Every column below is justified in 0173's header; the short form:
  --   `amount` NULL and `payment_status` carrying the SKIP REASON, because there is no payments
  --   row to have either — `payment_id` NULL is the finding, and a priced `amount` would be a
  --   number nobody computed.
  select 'settled_without_payment'::text, null::uuid, b.id, null::int,
         case when rn.end_reason is null then 'missing_end_reason'
              when rn.actual_km  is null then 'missing_actual_km'
              else 'unpriced' end,
         b.status::text, false, now() - rn.settled_at,
         -- [0174] same reason as arm seven, and this arm is why the key exists: before it, NULL
         -- payment_id had exactly one emitter, so grouping on it could not flatten two subjects.
         'booking:' || b.id::text
  from bookings b
  join runs rn on rn.booking_id = b.id
  where rn.ended_at is not null
    and rn.ended_at >= (select f.payments_live_since from ops_flags f where f.id)
    and rn.settled_at is not null
    and rn.settled_at < now() - interval '1 hour'
    and not exists (
      select 1 from payments p
      where p.booking_id = b.id
        and ((p.raw->>'kind') is not null or p.status in ('confirmed', 'waived'))
    )
$$;
-- ACL restated VERBATIM from `0118:1454-1455` (the file that last set it), carried through
-- `0173:262-263`. NOT relying on grant preservation — and here it cannot: §③ drops the function,
-- so this is a plain CREATE and a SECURITY DEFINER born PUBLIC-executable is the worst shape this
-- repo can produce (`0116:636`).
revoke execute on function payments_reconciliation() from public, anon, authenticated;
grant execute on function payments_reconciliation() to service_role;

comment on function payments_reconciliation is
  '0084 §C + 0118 §G + [0173] + [0174]: 결제 조정 질의 8종. The sixth,
refund_shaped_server_charge, surfaces kind-bearing canceled/partial_canceled rows on a settled
run. 0116 deliberately keeps automatic sweeps away from these
rows to prevent a second full charge; this human queue is the corresponding resolution mechanism.
The seventh, club_fee_unminted, is QUEUE-INDEPENDENT: a club fee recorded on bookings, collectable,
with no payments row and no recovery for an hour. It sees the booking whose durable-queue write
ALSO failed, which club_fee_mint_reconciliation() structurally cannot. [0173] The EIGHTH,
settled_without_payment, is BOOKINGS-anchored (`runs.settled_at`, 0116:47-52 — never
bookings.status, never ledger_items presence) and is the only arm that can see a booking with NO
payments row at all: sweep_settled_without_payments() SKIPS a settled run it cannot price
(end_reason NULL 0116:100 / actual_km NULL 0116:112 / a mint that raised 0116:125) with nothing but
a RAISE NOTICE, so before this arm that booking was invisible to every ops query. Its reason rides
payment_status — free by construction, because payment_id is NULL — and amount is NULL rather than
guessed. `unpriced` means only 「an hour of sweeps produced no row」: the mint''s exception path
leaves NO database trace, so SQL cannot distinguish a raising mint from a sweep that has not run.
Scoped by the sweep''s own ops_flags.payments_live_since predicate, so it is silent while charging
is off. Pinned by 203 0173-A1…A5.
[0174] ROW_KEY is the per-row GROUP KEY and is never NULL: the payments row for arms one…six
(`payment_id::text`, byte-identical to the old grouping) and `booking:<booking_id>` for arms seven
and eight, which exist precisely because there is no payments row. It is a SUBJECT identity, not a
row identity — deliberately NOT prefixed with the arm name, because that would give a row claimed
by two arms two distinct keys and delete the duplicate-detection property 116 C11 / 120 J4 exist
for. Those two pins group by row_key from 0174 onward. Pinned by 204 0174-K1…K4';


-- ═══ VERIFY — the deployed ARTIFACT, read back from the catalog ═════════════════════════════
-- House form. Every arm is `is not true` / `is distinct from` / an explicit boolean — never a bare
-- `IF` on a possibly-NULL predicate, because every arm here exists to notice that something is
-- MISSING and a NULL predicate makes a plpgsql `IF` silent.
do $$
declare
  v_src      text;
  v_segs     text[];
  v_seg      text;
  v_names    text[];
  v_types    oid[];
  v_secdef   boolean;
  v_path     boolean;
  v_pub      boolean;
  v_svc      boolean;
  v_arms     int;
  v_i        int;
  v_nullkeys int;
  v_rows     int;
  v_bad      text := '';
begin
  select p.prosrc,
         p.prosecdef,
         coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false),
         p.proargnames,
         p.proallargtypes
    into v_src, v_secdef, v_path, v_names, v_types
  from pg_proc p where p.oid = 'payments_reconciliation()'::regprocedure;

  -- NO-SOURCE arm, first: `prosrc` NULL makes every `position()`/`like` below NULL, and a set of
  -- silent arms is precisely how a source pin passes on a function that is not there at all.
  if v_src is null then
    raise exception '0174 VERIFY FAILED: NO-SOURCE(payments_reconciliation) — prosrc is NULL, every source arm below would have been silent';
  end if;

  -- ── ⓐ THE CATALOG FACT: `row_key` is the LAST output column and it is text. This is the
  --    RETURN SHAPE itself, not our prose about it, and it is the arm that a source match cannot
  --    give you — a body could name `row_key` in a comment and not declare it.
  if v_names is null or array_length(v_names, 1) is distinct from 9 then
    v_bad := v_bad || ' OUT-COLUMN-COUNT=' || coalesce(array_length(v_names, 1)::text, 'NULL') || '/9';
  elsif v_names[9] is distinct from 'row_key' then
    v_bad := v_bad || ' LAST-COLUMN=' || coalesce(v_names[9], 'NULL') || ' (expected row_key — a column inserted anywhere but the END breaks a positional reader)';
  elsif v_types[9] is distinct from 'text'::regtype::oid then
    v_bad := v_bad || ' ROW-KEY-TYPE=' || coalesce(v_types[9]::regtype::text, 'NULL') || '/text';
  end if;
  -- and the eight that were there before are still where they were
  if v_names is not null and array_length(v_names, 1) = 9 then
    if v_names[1:8] is distinct from
       array['kind','payment_id','booking_id','amount','payment_status','booking_status','needs_manual_cancel','age']
    then
      v_bad := v_bad || ' BASE-SHAPE-MOVED(' || array_to_string(v_names[1:8], ',') || ')';
    end if;
  end if;

  -- ── ⓑ COMMENTS STRIPPED BEFORE MATCHING, and it is load-bearing rather than tidy: `prosrc` is
  --    the body PLUS our own prose, and the two arms below carry inline comments that NAME the
  --    key. Without this, a migration that DOCUMENTED the key and failed to emit it would satisfy
  --    every source arm here — the instrument would reward the documentation as if it were the
  --    implementation.
  v_src := regexp_replace(v_src, '--[^\n]*', '', 'g');

  -- EVERY arm emits a key. Split on the arm separator rather than searching the whole body: a
  -- single `p.id::text` anywhere would otherwise satisfy a body-wide match for all eight.
  v_segs := regexp_split_to_array(v_src, 'union all');
  v_arms := coalesce(array_length(v_segs, 1), 0);
  if v_arms is distinct from 8 then
    v_bad := v_bad || ' ARM-COUNT=' || v_arms::text || '/8 (a forward-redefine dropped or added an arm)';
  else
    for v_i in 1..8 loop
      v_seg := v_segs[v_i];
      if (v_seg like '%p.id::text%' or v_seg like '%''booking:'' || b.id::text%') is not true then
        v_bad := v_bad || ' KEY-MISSING(arm ' || v_i::text || ')';
      end if;
    end loop;
    -- and the two bookings-anchored arms key on the BOOKING, not on a NULL payment_id
    if (v_segs[7] like '%''booking:'' || b.id::text%') is not true then
      v_bad := v_bad || ' ARM7-KEY-NOT-BOOKING(club_fee_unminted)';
    end if;
    if (v_segs[8] like '%''booking:'' || b.id::text%') is not true then
      v_bad := v_bad || ' ARM8-KEY-NOT-BOOKING(settled_without_payment)';
    end if;
  end if;

  -- the eight arm NAMES are still there — a widening that dropped one would be a silent
  -- regression in a query nobody calls from code
  select count(*)::int into v_arms from (
    select unnest(array['orphan_capture', 'stale_pending', 'stale_dispatched', 'ladder_exhausted',
                        'incident_waive_pending', 'refund_shaped_server_charge',
                        'club_fee_unminted', 'settled_without_payment']) as a
  ) q where position(q.a in v_src) > 0;
  if v_arms is distinct from 8 then
    v_bad := v_bad || ' BASE-ARMS-PRESENT=' || coalesce(v_arms::text, 'NULL') || '/8';
  end if;

  -- ── ⓒ BEHAVIOURAL, and preferred over the source arms above because it asks what the function
  --    DOES. ⚠ Honest about its own reach: at apply time this database may hold zero
  --    reconciliation rows, in which case `0 = 0` is vacuously true and this arm licenses only
  --    「the column exists and the query executes」. It is `204 0174-K4` that runs it against a
  --    fixture proven non-empty, which is the version that can fail. Both are kept: this one
  --    fires on the deployed database, K4 fires on a populated one.
  select count(*)::int, count(*) filter (where r.row_key is null)::int
    into v_rows, v_nullkeys
  from payments_reconciliation() r;
  if v_nullkeys is distinct from 0 then
    v_bad := v_bad || ' NULL-ROW-KEY=' || coalesce(v_nullkeys::text, 'NULL') || '/' || coalesce(v_rows::text, 'NULL') || ' rows';
  end if;

  if v_secdef is not true then v_bad := v_bad || ' NOT-SECURITY-DEFINER'; end if;
  if v_path   is not true then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;

  v_pub := has_function_privilege('anon', 'payments_reconciliation()', 'execute')
        or has_function_privilege('authenticated', 'payments_reconciliation()', 'execute');
  v_svc := has_function_privilege('service_role', 'payments_reconciliation()', 'execute');
  if v_pub is distinct from false then v_bad := v_bad || ' CLIENT-ROLE-CAN-EXECUTE'; end if;
  if v_svc is distinct from true  then v_bad := v_bad || ' SERVICE-ROLE-CANNOT-EXECUTE'; end if;

  if v_bad <> '' then
    raise exception '0174 VERIFY FAILED:%', v_bad;
  end if;
end $$;
