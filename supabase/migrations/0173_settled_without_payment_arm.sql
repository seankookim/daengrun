-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0173 — the settled booking the sweep CANNOT price becomes a row on the ops board
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 203_settled_without_payment_arm_suite.sql (tag `swp`).
-- Closes fix-wave re-attack **MEDIUM R2** (`docs/reviews/2026-09-15-fixwave-reattack-verdict.md`):
--   *「the sweep skips missing pricing fields and catches mint exceptions using only RAISE NOTICE
--   (0116:105); the current seven-arm reconciliation function has no bookings-anchored
--   settled_without_payment arm (0118:1392)」*.
-- 0172's own header named this as its named-out-of-scope residual (`0172:88-94`) and said it
-- belongs to a reconciliation-arm slice. This is that slice.
--
-- ═══ WHOSE OBJECT THIS FILE RE-CREATES (REGISTRY.md silent-collision law) ═══════════════════
--   `payments_reconciliation`  ← 0076 §D → 0080 §? → 0084 §C (five arms) → **0118 §G (seven)**.
--   `0118:1392` is the LAST definition and is the base here, carried forward BYTE-IDENTICAL —
--   arms one through seven, the `returns table (…)` shape, `language sql stable security definer`
--   and the in-body `set search_path`. This file adds ONE `union all` and changes nothing else.
--   Nothing else in the repo creates or replaces it.
--
-- ⚠ THIS IS A READ. It moves no money, mints nothing, writes nothing. Its entire effect is that a
--   `select * from payments_reconciliation()` returns rows it did not return before.
--
-- ═══ WHAT THE ARM ASKS, AND WHY EACH CONJUNCT IS THE ONE IT IS ═════════════════════════════
--
-- ① **ANCHOR: `runs.settled_at is not null`** — `0116:47-52` is the paragraph that settles this,
--    and it rules out BOTH substitutes a reader will reach for, with reasons:
--      · `bookings.status` — §0-ter #11 / `116 C8`: a settled booking legitimately moves on to
--        `incident_review` / `refund_pending`, so anchoring there HIDES the very crash class this
--        arm exists to surface.
--      · `ledger_items` presence — `0080 §K` writes a ledger row for a **CANCELLED** booking,
--        which is not a run at all. An arm anchored there reports an owner charge as missing for
--        a run that never happened.
--    `runs.settled_at` is written by settlement and by nothing else (`119 R11` is the pin that
--    keeps that true). It is also the sweep's own anchor, which is the point: this arm must see
--    exactly the population the sweep looks at, or it is a second opinion rather than a report.
--    A4 is the control that keeps the anchor honest — a cancelled booking WITH a ledger row must
--    not appear.
--
-- ② **SCOPE: `rn.ended_at is not null and rn.ended_at >= ops_flags.payments_live_since`** —
--    lifted verbatim from the sweep (`0116:73-75`). This is ALSO the flag gate and it needs no
--    separate `if`: `payments_live_since` is NULL while charging is off, a scalar sub-select of a
--    NULL column yields NULL, and `x >= NULL` is NULL, which a `where` treats as false. So the
--    arm returns ZERO rows in the charging-off era — the same answer the sweep gives (`0116:72`
--    `if v_since is null then return 0`) — and it cannot retroactively arraign a pilot-era run.
--    Fails CLOSED, in the direction that cannot invent work.
--
-- ③ **「no qualifying payments row」 — the sweep's OWN predicate, verbatim from `0116:96-106`:**
--        and ((p.raw->>'kind') is not null or p.status in ('confirmed', 'waived'))
--    Copied rather than re-derived, deliberately. It is DELIBERATELY WIDER than the mint's own
--    existence check (review round 2, finding 4: aligning them enabled a ₩15,000+₩20,000
--    double-charge on refund-vocabulary rows; `151 B1 ⓒ′` pins the wider form). If this arm used
--    a narrower 「has a payment」 it would cry about bookings the sweep is deliberately staying
--    out of, and 0118's own warning applies — a board that cries about correct rows is a board
--    nobody reads.
--
-- ④ **GRACE: `rn.settled_at < now() - interval '1 hour'`.**
--    🔴 **THE SWEEP HAS NO GRACE CONSTANT, AND SAYING SO IS MORE USEFUL THAN INVENTING ONE.**
--    Swept: `0080 §G` / `0116 §A` contain no interval at all; the sweep's only cadence is its cron
--    row `sweep-settled-charges` `2-57/5 * * * *` (`0080:643`, read back by `0172 §A`'s VERIFY and
--    pinned standing by `202 0172-S1`) — every five minutes. So the constant reused here is
--    **`payments_reconciliation`'s own**, the `interval '1 hour'` that arms two, three and seven
--    already share, whose reasoning is written at `0118:1378-1381`: an hour is 「long enough that a
--    row here is a real defect rather than the normal window between a failed immediate mint and
--    its next tick」. At a five-minute cadence an hour is TWELVE failed sweeps — strictly more
--    conservative than the six that argument was written for. No new constant is introduced by
--    this file, and therefore nothing in it is PROVISIONAL.
--    It is keyed on `settled_at`, the moment the row became sweepable — not on `created_at`, which
--    is when the booking was made and has nothing to do with how long recovery has been failing.
--    ⚠ **NAMED GAP, measured rather than reasoned:** this conjunct reads the SAME COLUMN as the
--    anchor in ①, and `NULL < now() - interval '1 hour'` is NULL, hence false. So the grace alone
--    already excludes an unsettled run, and **`rn.settled_at is not null` is REDUNDANT and not
--    independently observable through any fixture** — measured: swapping the anchor for
--    `b.status = 'completed'` reddens A5 (source) and, in a first draft, NO behavioural pin at all.
--    It stays for readability, and because a later slice may legitimately re-key the grace onto
--    another column and make it load-bearing again. 203's A4 ⓒ is what actually observes the
--    substitution, from the other direction (`116 C8`: a `bookings.status` anchor HIDES a settled
--    booking that moved on to incident_review). 203's header carries the full record.
--
-- ⑤ **THE REASON, and the honest limit of it.** The sweep refuses a row in three places and only
--    two of them leave a trace:
--      · `0116:100-103`  `end_reason is null`  → `missing_end_reason`
--      · `0116:112-115`  `actual_km is null`   → `missing_actual_km`
--      · `0116:125-126`  `exception when others then raise notice` — **THE MINT RAISED, AND IT
--        LEAVES NO TRACE IN THE DATABASE AT ALL.** No row, no column, no counter; the evidence is
--        a line in the postgres log. So a settled booking with BOTH columns present and still no
--        payments row is indistinguishable, from SQL, from one the sweep has not reached yet —
--        which is exactly what the grace in ④ is for. That case is reported as **`unpriced`**,
--        not as `mint_unknown`: `unpriced` is the observable fact (an hour of sweeps has produced
--        no row), while `mint_unknown` would assert a cause this query cannot see.
--    The `case` evaluates in the SWEEP'S OWN ORDER (`end_reason` first, then `actual_km`), so the
--    reason an operator reads is the reason the sweep would print.
--
-- ⑥ 🔴 **WHERE THE REASON RIDES, said out loud because it is a vocabulary decision and not an
--    implementation detail.** `create or replace function` CANNOT change a `returns table (…)`
--    shape — PostgreSQL refuses with `cannot change return type of existing function` — and
--    dropping this function to widen it is forbidden (grant preservation; and seven shipped
--    suites read it). So the reason must ride an existing column. It rides **`payment_status`**,
--    which in this arm is free BY CONSTRUCTION: `payment_id` is NULL because there IS no payments
--    row — that absence is the whole finding — so the column cannot be holding a payment's status.
--    Arm seven (`club_fee_unminted`, `0118:1370-1372`) already leaves it `null::text` for exactly
--    this reason. `amount` is NULL for the same reason and is NOT guessed: the defining property
--    of these rows is that nobody could price them, and a number here would be a fabricated one.
--    A3 (inside the grace ⇒ absent) and A2 (a payments row appears ⇒ absent) are the two controls
--    that stop this arm from being 「every settled booking」.
--
-- ⚠ **DISJOINTNESS — `0118:1372-1376` addressed a warning to whoever added arm eight, and this is
--   arm eight.** `116 C11` and `120 J4` assert disjointness with
--   `group by payment_id having count(*) > 1`, and SQL groups NULLs together, so a row from arm
--   SEVEN and a row from arm EIGHT existing at the same moment would read as 「one row in two
--   arms」 and redden both pins. Measured on the full harness after this file landed: **1220 → 1225
--   pass / 0 fail**, no shipped pin moved. The reason is structural, not luck: arm seven requires
--   `bookings.club_fee_event_at` set and `_club_fee_event_collectable` true, i.e. a CANCELLED club
--   booking; arm eight requires a run with `settled_at` stamped. A booking cannot be both, and
--   `0118:1376-1381` already records why no fixture in suites 30…108 can reach arm seven at all.
--   Stated as what it is: the pins are green because the two populations are disjoint in this
--   fixture chain, not because anything asserts they must stay disjoint.
--
-- ⚠ **BLAST RADIUS OUTSIDE SQL, enumerated by hand because no tool points at it** (the
--   widening-a-return's-meaning law). `payments_reconciliation()` has no runtime caller — swept:
--   zero `.rpc("payments_reconciliation")` in `supabase/functions` and `app/`. Its only code-level
--   dependant is `_shared/ops.ts`'s `RECONCILIATION_ARM` map, which decides whether an ops push
--   sends the operator TO the query or to the server log. `ops.ts:95-97` said, in a comment,
--   `settled_without_payment` has no arm — true when written, false from this file onward. That
--   map is updated in the same slice, and `_test/ops_routing_test.ts`'s assertion that the copy
--   must NOT name the query is updated with it (a pin whose pinned behaviour legitimately changed).
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══ §A — `payments_reconciliation`: 0118 §G byte-faithful, plus arm eight ══════════════════
create or replace function payments_reconciliation()
returns table (
  kind text,
  payment_id uuid,
  booking_id uuid,
  amount int,
  payment_status text,
  booking_status text,
  needs_manual_cancel boolean,
  age interval
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select 'orphan_capture'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         coalesce((p.raw->>'needs_manual_cancel')::boolean, false), now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'confirmed'
    and b.status in ('draft', 'quoted', 'payment_hold', 'expired')
  union all
  select 'stale_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending' and p.created_at < now() - interval '1 hour'
    and (p.raw->>'dispatched_at') is null
  union all
  select 'stale_dispatched'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'dispatched_at')::timestamptz
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending'
    and (p.raw->>'dispatched_at') is not null
    and (p.raw->>'dispatched_at')::timestamptz < now() - interval '1 hour'
  union all
  select 'ladder_exhausted'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'failed'
    and (p.raw->>'kind') is not null
    and coalesce((p.raw->>'attempts')::int, 0) >= 3
  union all
  select 'incident_waive_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - (p.raw->>'review_opened_at')::timestamptz
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'waived'
    and (p.raw->>'review') = 'incident_pending'
    and (p.raw->>'review_resolved_at') is null
  union all
  select 'refund_shaped_server_charge'::text, p.id, p.booking_id, p.amount, p.status,
         b.status::text, false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status in ('canceled', 'partial_canceled')
    and (p.raw->>'kind') is not null
    and exists (select 1 from runs r where r.booking_id = b.id and r.settled_at is not null)
  union all
  select 'club_fee_unminted'::text, null::uuid, b.id, b.cancel_fee, null::text,
         b.status::text, false, now() - b.club_fee_event_at
  from bookings b
  where b.club_fee_event_at is not null
    and b.club_fee_event_at < now() - interval '1 hour'
    and _club_fee_event_collectable(b.id)
    and not exists (select 1 from _cancel_fee_existing_payment(b.id))
  union all
  -- ── [0173] ARM EIGHT — `settled_without_payment` ─────────────────────────────────────────
  -- The run settled, the sweep has had an hour of five-minute ticks, and there is still no
  -- payments row. Every column below is justified in this file's header; the short form:
  --   `amount` NULL and `payment_status` carrying the SKIP REASON, because there is no payments
  --   row to have either — `payment_id` NULL is the finding, and a priced `amount` would be a
  --   number nobody computed.
  select 'settled_without_payment'::text, null::uuid, b.id, null::int,
         case when rn.end_reason is null then 'missing_end_reason'
              when rn.actual_km  is null then 'missing_actual_km'
              else 'unpriced' end,
         b.status::text, false, now() - rn.settled_at
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
-- ACL restated verbatim from `0118:1454-1455`, the file that last set it. NOT relying on grant
-- preservation: on an apply where the function is absent this statement is a plain CREATE and a
-- SECURITY DEFINER born PUBLIC-executable is the worst shape this repo can produce (`0116:636`).
revoke execute on function payments_reconciliation() from public, anon, authenticated;
grant execute on function payments_reconciliation() to service_role;

comment on function payments_reconciliation is
  '0084 §C + 0118 §G + [0173]: 결제 조정 질의 8종. The sixth,
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
is off. Pinned by 203 0173-A1…A5';


-- ═══ VERIFY — the deployed ARTIFACT, read back from the catalog ═════════════════════════════
-- House form. Every arm is `is not true` / `is distinct from` / an explicit boolean — never a bare
-- `IF` on a possibly-NULL predicate, because every arm here exists to notice that something is
-- MISSING and a NULL predicate makes a plpgsql `IF` silent (the exact collapse that killed five
-- pins in this repo in one afternoon).
do $$
declare
  v_src      text;
  v_arm      text;
  v_secdef   boolean;
  v_path     boolean;
  v_pub      boolean;
  v_svc      boolean;
  v_unions   int;
  v_bad      text := '';
begin
  select p.prosrc,
         p.prosecdef,
         coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false)
    into v_src, v_secdef, v_path
  from pg_proc p where p.oid = 'payments_reconciliation()'::regprocedure;

  -- NO-SOURCE arm, first: `prosrc` NULL makes every `position()`/`like` below NULL, and a set of
  -- silent arms is precisely how a source pin passes on a function that is not there at all.
  if v_src is null then
    raise exception '0173 VERIFY FAILED: NO-SOURCE(payments_reconciliation) — prosrc is NULL, every source arm below would have been silent';
  end if;

  -- ⚠ COMMENTS STRIPPED BEFORE MATCHING, and it is load-bearing rather than tidy: `prosrc` is the
  -- body PLUS our own prose, and the arm's own inline comment names the arm. Without this, a
  -- migration that DOCUMENTED the arm and failed to add it would satisfy every check below — the
  -- instrument would reward the documentation as if it were the implementation.
  v_src := regexp_replace(v_src, '--[^\n]*', '', 'g');

  if position('settled_without_payment' in v_src) = 0 then
    v_bad := v_bad || ' ARM-ABSENT(settled_without_payment)';
  else
    -- Scope the remaining source arms to the arm itself. Arm six also says `settled_at is not
    -- null`, through alias `r`; only arm eight uses `rn`, so these cannot be satisfied by a
    -- neighbour.
    v_arm := substr(v_src, position('settled_without_payment' in v_src));
    if (v_arm like '%rn.settled_at is not null%') is not true then
      v_bad := v_bad || ' ANCHOR-MISSING(runs.settled_at)';
    end if;
    if (v_arm like '%rn.settled_at < now() - interval ''1 hour''%') is not true then
      v_bad := v_bad || ' GRACE-MISSING(1 hour on settled_at)';
    end if;
    if (v_arm like '%payments_live_since%') is not true then
      v_bad := v_bad || ' CUTOVER-SCOPE-MISSING(payments_live_since)';
    end if;
    -- the two wrong anchors, refused BY NAME (0116:47-52). Asserted as explicit booleans in the
    -- positive direction so a NULL cannot make either arm silent.
    if (v_arm like '%b.status = ''completed''%') is true then
      v_bad := v_bad || ' WRONG-ANCHOR(bookings.status)';
    end if;
    if (v_arm like '%ledger_items%') is true then
      v_bad := v_bad || ' WRONG-ANCHOR(ledger_items)';
    end if;
  end if;

  -- the seven it was built on are still there — a 「forward-redefine」 that dropped one would be a
  -- silent regression in a query nobody calls from code
  select count(*)::int into v_unions from (
    select unnest(array['orphan_capture', 'stale_pending', 'stale_dispatched', 'ladder_exhausted',
                        'incident_waive_pending', 'refund_shaped_server_charge',
                        'club_fee_unminted']) as a
  ) q where position(q.a in v_src) > 0;
  if v_unions is distinct from 7 then
    v_bad := v_bad || ' BASE-ARMS-PRESENT=' || coalesce(v_unions::text, 'NULL') || '/7';
  end if;

  if v_secdef is not true then v_bad := v_bad || ' NOT-SECURITY-DEFINER'; end if;
  if v_path   is not true then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;

  v_pub := has_function_privilege('anon', 'payments_reconciliation()', 'execute')
        or has_function_privilege('authenticated', 'payments_reconciliation()', 'execute');
  v_svc := has_function_privilege('service_role', 'payments_reconciliation()', 'execute');
  if v_pub is distinct from false then v_bad := v_bad || ' CLIENT-ROLE-CAN-EXECUTE'; end if;
  if v_svc is distinct from true  then v_bad := v_bad || ' SERVICE-ROLE-CANNOT-EXECUTE'; end if;

  if v_bad <> '' then
    raise exception '0173 VERIFY FAILED:%', v_bad;
  end if;
end $$;
