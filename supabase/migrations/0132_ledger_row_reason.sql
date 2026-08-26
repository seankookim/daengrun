-- ═══ 0132: why this run paid what it paid — end_reason reaches the runner's ledger ═══
--
-- Sean, 2026-08-26, verbatim: 「maybe for the profits showing screen it'd be nice to add a one
-- phrase description per ledger row like completed run or partial complete or something b/c price
-- fluctuates per run and runner may be like why is it different」.
--
-- He is describing a real gap, not a decoration. The price genuinely does fluctuate by end
-- reason, and 0101 §A is where it happens: `completed`/`dog_condition`/`incident` price on ACTUAL
-- km, `owner_request`/`owner_forced` add a 50% guarantee on the UNRUN half of the plan, and
-- `runner_personal` delegates to 0086 §A ⑨a — base 0, addons 0, NO min_fare floor, the whole
-- payout is distance. Three different amounts for the same dog over the same route are all
-- correct, and the earnings screen could not say why, because `my_ledger_rows` (0121 §A) does not
-- return the reason. This adds it.
--
-- ⚠ WHAT THIS DELIBERATELY DOES NOT DO — Sean 2026-08-24, still in force: 「don't show them the
--   수수료 … not the calcuations ever; only show the final profit per run; keep the margin a
--   secret」. This ships the REASON, never the arithmetic. No component, no gross, no fee, no
--   guarantee amount, no rate. A runner learns 「보호자 요청으로 중단」 and 「완주」 are different
--   kinds of run; they learn nothing about how either number was built. The 0121 seal is intact.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 🔴 AND IT CLOSES A LATENT DISCLOSURE RATHER THAN DOUBLING IT.
--
-- 0121 §A joins `left join runs r on r.booking_id = l.booking_id` — keyed to the BOOKING. But
-- `runs` has NO runner column at all (measured against production: id, booking_id, started_at,
-- ended_at, actual_km, duration_sec, avg_pace_sec_per_km, end_reason, trace, condition_note,
-- photos, events, pace_suggest_sec, settled_at). A run's runner identity lives in
-- `bookings.runner_id`, which is MUTABLE — 0057, 0058, 0118 and 0124 all carry writers that
-- `update bookings set … runner_id`, and Sean explicitly KEPT host reassignment (2026-08-25).
--
-- So: runner A holds a ledger row on booking X (a cancellation compensation, say). X is later
-- reassigned and runner B performs it. A's row LEFT JOINs B's run, and `my_ledger_rows` hands A
-- B's data. Adding `end_reason` onto that join unexamined would have shipped a NEW disclosure
-- (「B's run ended in `incident`」) on top of an OLD one, and it would have read as verified
-- because the new column was the part under review.
--
-- ⚠ `km` IS ALREADY ON THAT JOIN, so 「narrower than the km beside it」 establishes nothing — km
--   is not a safe baseline, it is the first instance. Found by the announcer session on review of
--   this slice's claim; a THIRD instance (`§B my_week_stats`, same unkeyed join feeding
--   `count(r.id)` and `sum(r.actual_km)`) was found here and is fixed in the same file. Two
--   occurrences is a bug; three is a class, and the class is 「a ledger row reached a run without
--   asking whose run it was」.
--
-- MEASURED ON PRODUCTION BEFORE WRITING (both halves, 2026-08-26):
--     ledger rows whose runner_id <> their booking's runner_id ........ 0
--     ...of those, with a runs row (would actually expose) ............ 0
-- LATENT, NOT BREACHED. Nothing is disclosed today; the mechanism is live and the population is
-- zero only because no reassigned booking has yet been run. This is the cheap moment to close it.
--
-- 🔴 RESIDUAL, NAMED RATHER THAN PAPERED OVER — this gate asks 「is this ledger row's runner the
--    booking's CURRENT runner?」, which is not quite 「did this runner perform this run?」. Those
--    two questions differ in one direction: if a run is performed and the booking is reassigned
--    AFTERWARDS, the new runner's ledger row would read the previous runner's run. That case is
--    unreachable with today's writers (a reassignment away from a completed run has no caller)
--    and it is strictly narrower than what shipped, so this is an improvement rather than a
--    complete answer. The complete answer is a runner column ON `runs` — the fact 「who performed
--    this run」 has no home in the schema at all right now, which is the root cause of all three
--    instances. That is its own slice, with a backfill, and it is NOT smuggled in here. Suite 165
--    pins the direction that is reachable; nothing pins the direction that is not, deliberately,
--    because a pin over an unreachable state asserts a guarantee the code does not make.
--
-- ⚠ `cancel_comp` KEEPS THE UNKEYED PREDICATE ON PURPOSE. It is `(r.id is null)`, and re-keying
--   it would relabel a reassigned row as a cancellation — trading a disclosure for a LIE, and
--   0121's own type comment forbids exactly that (「an unknown must not be labelled 'cancelled'」).
--   Only the two run-DERIVED projections gate on identity; the existence test does not. On every
--   row where the runner matches — which is every row in production — the output is byte-identical
--   to 0121. That is what makes this safe to land without a client-side flag day.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
--
-- Discipline (0121 §2 preamble, unchanged): definer + IN-BODY search_path (98 H1 watches it) ·
-- explicit null-uid rejection · party gate before state gate · flat whitelisted returns · explicit
-- ACLs, never default PUBLIC EXECUTE and never grant preservation (0116:636).

-- ═══ §A my_ledger_rows — gains end_reason, and its run join learns whose run it is ═══
-- ⚠ DROP-then-CREATE, not `create or replace`: postgres refuses to change the return type of an
--   existing function, and adding a column to `returns table` IS a return-type change. That drops
--   the grants with it, which is precisely why the revoke/grant below is written out rather than
--   inherited — the 0127 CRITICAL (a definer born PUBLIC-executable on a path where the function
--   was absent) is the same shape one step removed.
drop function if exists my_ledger_rows();
create function my_ledger_rows()
returns table (id uuid, booking_id uuid, net int, cancel_comp boolean,
               km numeric, end_reason text, dog_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
  select l.id, l.booking_id,
         (l.base + l.distance_pay + l.addon_pay + l.tip
            + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::int,
         -- existence, NOT attribution — see the cancel_comp note in the header
         (r.id is null),
         -- the two run-derived facts, and ONLY these, answer 「whose run?」 first
         case when r.id is null or b.runner_id is distinct from l.runner_id
              then null else b.km end,
         case when b.runner_id is distinct from l.runner_id
              then null else r.end_reason::text end,
         d.name, l.created_at
  from ledger_items l
  join bookings b on b.id = l.booking_id
  left join dogs d on d.id = b.dog_id
  left join runs r on r.booking_id = l.booking_id
  where l.runner_id = auth.uid()
  order by l.created_at desc
  limit 30;
end $$;
revoke execute on function my_ledger_rows() from public, anon;
grant execute on function my_ledger_rows() to authenticated;

-- ═══ §B my_week_stats — the third instance of the same unkeyed join ═══
-- Return type is UNCHANGED, so `create or replace` is correct here and grants survive; the
-- revoke/grant is restated anyway because a replace that silently relies on preservation is the
-- pattern `check-definer-acl.mjs` exists to refuse.
-- `week_net` is deliberately NOT filtered: every ledger row belongs to this runner by the
-- `l.runner_id = auth.uid()` gate, so all of it is their money regardless of who ran the booking.
-- What must not cross is the RUN — count and km are facts about a performance, and a performance
-- has exactly one performer. `left join bookings` (never inner) so no row can be dropped.
create or replace function my_week_stats()
returns table (week_net bigint, week_runs int, week_km numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_start timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  v_start := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  return query
  select coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0) - l.platform_fee), 0)::bigint,
         (count(r.id) filter (where b.runner_id = l.runner_id))::int,
         round(coalesce(sum(r.actual_km) filter (where b.runner_id = l.runner_id), 0), 1)
  from ledger_items l
  left join bookings b on b.id = l.booking_id
  left join runs r on r.booking_id = l.booking_id
  where l.runner_id = auth.uid() and l.created_at >= v_start;
end $$;
revoke execute on function my_week_stats() from public, anon;
grant execute on function my_week_stats() to authenticated;

comment on function my_ledger_rows is
  '0132 (was 0121 §A): the runner earnings list. Net-only — the six money components never leave
the server (Sean 2026-08-24 margin secrecy). Returns `end_reason` so the client can name WHY an
amount differs (0101 §A prices the six reasons differently) without exposing any arithmetic.
`km` and `end_reason` are NULL when `bookings.runner_id <> ledger_items.runner_id` — a reassigned
booking''s run belongs to whoever performed it, and `runs` carries no runner of its own.
`cancel_comp` stays the unkeyed existence test on purpose: re-keying it would relabel a reassigned
row as a cancellation, which is a lie rather than a redaction.';
