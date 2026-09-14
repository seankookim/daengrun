-- ═══ 0158: settled money is labelled with the distance that priced it, and an aggregate
--            that could not see a run says so instead of counting it as zero ═══
--
-- Two findings from the run-end codex review (`docs/reviews/2026-08-28-codex-runend-money.md`,
-- #9 MEDIUM and #8 HIGH). Both are the same law 0152 was written for, one level up:
--
--     「the run measured 0 km」   → a real measurement. A total that includes it is honest.
--     「the run was never measured」 → there is no distance. It must not be ADDED AS ZERO,
--                                     and it must not be RENDERED as zero.
--
-- 0152 fixed the per-run money surface (`club_incident_settle_quote`) and the per-run display
-- surfaces (report · receipt · my-record). It left the AGGREGATES and it left the ledger row's
-- LABEL, and those are the last executable zero-conversions in this family.
--
-- ⚠ **A FIX THAT REFUSES BOTH IS THE SAME DEFECT WITH THE OPPOSITE SIGN**, which is why every
--   change below is paired with the case it must NOT break:
--     · a week with ZERO runs still returns `week_km = 0` — that zero is TRUE, nobody ran.
--     · a run genuinely measured at 0.00 km still enters every sum and every count as 0.
--     · a leaderboard group with a measured 0 still ranks and renders as `0km`.
--   Only 「there were runs and not one of them carries a distance」 becomes NULL, and only
--   「some of these runs carry no distance」 becomes a labelled lower bound.
--
-- ═══ MEASURED BEFORE WRITING (production, read-only, 2026-08-28) ═══
--   `completed` bookings whose `runs.actual_km` is NULL ......... 0 of 8
--   runs with NULL km AND NULL duration ......................... 1 of 9  (`end_reason='incident'`,
--                                                                  its booking in `incident_review`)
-- So this class is **schema-reachable and not observable today**, and it is exactly ONE state
-- transition from being observable on five screens at once: the moment that incident booking
-- resolves to `completed`, every aggregate below starts printing an unqualified `0km`.
-- Recorded as a rung, not a verdict: the counts are OBSERVED; 「it will arm on that transition」
-- is a READ of the predicates below (`b.status = 'completed'` on both boards, `ledger_items`
-- on the week stats), not a measurement of the future.
--
-- ═══ THE SHAPE, AND WHY THIS ONE ═══
-- The review offered two: make the aggregate NULLABLE, or return an explicit measured/unmeasured
-- COUNT. This file does **both, in one shape**, and the reason is that the client already chose it:
-- `fetchFitness` (api.ts) was converted in the 0152 pass to a measured-only sum PLUS an
-- `unmeasured` RUN COUNT, and `owner/fitness.tsx` renders that count as a note under the bars.
-- Inventing a second vocabulary server-side would leave two honest idioms for one fact. So every
-- aggregate here returns:
--     `km`         — the sum of the runs it COULD measure; NULL when it could measure none.
--     `unmeasured` — how many runs it left out. **A RUN COUNT, NEVER A DISTANCE.**
-- A renderer with both can say the three different true things: a complete total, a lower bound,
-- and 「no distance was recorded」. With only a nullable km it could not distinguish a partial
-- total from a complete one, and with only a count it would still print a fabricated 0.
--
-- ⚠ **THIS WIDENS WHAT `km` MEANS, AND THAT BREAKS CORRECT CALLERS WITH NO EDIT TO THE CALLER**
--   (the §④ law). Every consumer was enumerated by hand and each is fixed in this slice's client
--   half; the TypeScript types were made nullable at the source so `tsc` enumerates them too:
--     my_ledger_rows            → api.ts fetchLedger → runner/earnings.tsx
--     my_week_stats             → api.ts fetchRunnerWeekStats → runner/home.tsx
--     leaderboard_dogs_weekly   → api.ts fetchLeaderboards / fetchDogBoardDelta fallback
--                                 → leaderboard.tsx, owner/home.tsx ticker
--     leaderboard_runners_weekly→ api.ts fetchLeaderboards → leaderboard.tsx (renders 회, not km)
--     leaderboard_dogs_weekly_delta → api.ts fetchDogBoardDelta → owner/home.tsx ticker
--     grant_weekly_rewards      → cron `weekly-rewards` (0014:70). No client.
--   NOT converted, and named rather than smuggled: `runners.total_km` / `dogs.total_km` are
--   STORED accumulators, not derived aggregates. They can only ever be fed a measured value —
--   `settle_run_tx` (0083:663) raises on a NULL `p_actual_km` before the `+=` at 0083:797 — so
--   they contain no fabricated zero. They are a LOWER BOUND that silently omits unmeasured runs,
--   and saying so needs a schema column and a backfill. That is its own slice.
--
-- Discipline: definer + IN-BODY search_path (98 H1) · explicit ACL on every recreation, never
-- grant preservation and never a default PUBLIC EXECUTE (0116:636) · flat whitelisted returns.
-- ⚠ Four of the six functions gain a RETURN COLUMN, and postgres refuses a return-type change on
--   `create or replace` — so they are DROP + CREATE, which discards the ACL. That is precisely why
--   the revoke/grant pairs below are written out instead of inherited. The ACLs restated here were
--   READ OFF PRODUCTION first (`pg_proc.proacl`, 2026-08-28) rather than guessed from the files:
--   the boards carry `authenticated + service_role` (0057:80's sweep revoked the default PUBLIC),
--   `grant_weekly_rewards` carries `service_role` ALONE (0057:352 — anon could otherwise mint
--   unlimited 하이 포인트).


-- ═══ §A my_ledger_rows — the settled row stops being labelled with the PLANNED distance ═══
--                                                                            (review finding #9)
--
-- 0132 §A returns `b.km`. That is the distance the booking was PRICED AT WHEN IT WAS SOLD, and
-- the net beside it on the same line is priced from what actually happened: `compute_runner_payout`
-- (0101 §A) prices `completed`/`dog_condition`/`incident` on the run's ACTUAL km, and 0144's freeze
-- makes that the server's own derived number. So a 5 km booking that ended at 1.8 km rendered
--     「초코 · 5km」   beside   「실수령 …원」 computed from 1.8 km
-- — the runner's earnings screen stating a distance the money in the same row disagrees with.
-- Sean's 0132 ruling was that this line answers 「why is this number different」; a planted
-- planned-distance answers it WRONG.
--
-- ⚠ And the second half is the 0152 class again: an incident `pay_full` row has `actual_km` NULL,
--   so the planned km was printed **as if it were a measurement of a run nobody measured.**
--
-- The attribution gate is unchanged and still does the work it was added for (0132's header: a
-- reassigned booking's run belongs to whoever performed it, and `runs` carries no runner of its
-- own). Only the COLUMN changes. `r.id is null` is kept in the disjunction even though
-- `r.actual_km` is NULL on that branch anyway — it states the intent, and it keeps this gate
-- textually identical to `end_reason`'s directly below it.
--
-- ⚠ NO COALESCE ON THE WAY OUT, and the client half must not add one: `LiveLedgerItem.km` is
--   already `number | null` and `runner/earnings.tsx` already renders the dog's name ALONE when it
--   is null (that null used to mean 「cancellation compensation — no run」). It now ALSO means
--   「this run was never measured」, and the two stay distinguishable because the line underneath
--   names the reason: 「취소 보상」 vs 「사고로 중단」.
--
-- Return type is UNCHANGED, so `create or replace` is correct and the ACL survives — restated
-- anyway, because a replace that silently relies on preservation is the pattern
-- `check-definer-acl.mjs` exists to refuse.
create or replace function my_ledger_rows()
returns table (id uuid, booking_id uuid, net int, cancel_comp boolean,
               km numeric, end_reason text, dog_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
  select l.id, l.booking_id,
         (l.base + l.distance_pay + l.addon_pay + l.tip
            + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::int,
         -- existence, NOT attribution — see the cancel_comp note in 0132's header
         (r.id is null),
         -- [0158 §A] the MEASURED distance, never the planned one. NULL when the run exists and
         -- nobody measured it — the money on this line was priced from the same absence.
         case when r.id is null or b.runner_id is distinct from l.runner_id
              then null else r.actual_km end,
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

comment on function my_ledger_rows is
  '0158 (was 0132 §A, was 0121 §A): the runner earnings list. Net-only — the six money components
never leave the server (Sean 2026-08-24 margin secrecy). `km` is `runs.actual_km`, the distance the
net was PRICED FROM — never `bookings.km`, which is what the booking was SOLD at and disagrees with
the money beside it on an early-ended run. NULL means one of three things and all three are
"say nothing": no run row (cancellation compensation), a run performed by a DIFFERENT runner after
the booking was reassigned, or a run nobody measured. `end_reason` on the line below separates them
for a reader.';


-- ═══ §B my_week_stats — a week whose runs were never measured stops reporting 0km ═══
--                                                                            (review finding #8)
--
-- 0132 §B ends `round(coalesce(sum(r.actual_km) filter (…), 0), 1)`. `sum` over a group whose every
-- `actual_km` is NULL returns NULL, and that coalesce turns it into **0.0** — beside a run COUNT
-- that is real and a net that is real money. The runner's home row then reads
--     「1회 · 0km · 정산 예정 12,450원」
-- which is a fabricated measurement standing next to two true facts, so it reads as the third.
--
-- ⚠ THE ZERO THAT MUST SURVIVE, and it is why this is not simply `delete the coalesce`: a week
--   with NO runs must still answer `0`, because nobody ran and 0 km is the TRUE total. Removing
--   the coalesce outright would answer NULL there and the screen would print 「—km」 for a runner
--   who correctly ran nothing — the refusal-of-both failure this file's header names. So the
--   zero is re-established explicitly on the run count, and NULL is reserved for the one state it
--   belongs to: **runs happened and not one of them carries a distance.**
--
-- `week_unmeasured` is a RUN COUNT. It is what lets the client tell a PARTIAL total (a lower
-- bound, which must be labelled) from a COMPLETE one (which must not be), a distinction a
-- nullable km alone cannot carry.
--
-- ⚠ The `filter (where b.runner_id = l.runner_id)` attribution guard from 0132 §B is preserved on
--   all three run-derived projections, including the new one — a count of runs SOMEONE ELSE failed
--   to have measured is not this runner's fact either.
--
-- Return type GAINS a column, so this is a drop + create and the ACL is written out.
drop function if exists my_week_stats();
create function my_week_stats()
returns table (week_net bigint, week_runs int, week_km numeric, week_unmeasured int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_start timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  v_start := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  return query
  select coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0) - l.platform_fee), 0)::bigint,
         (count(r.id) filter (where b.runner_id = l.runner_id))::int,
         -- 0 runs → a true 0. Runs but no measurement → NULL. Anything measured → its sum.
         case when count(r.id) filter (where b.runner_id = l.runner_id) = 0 then 0::numeric
              else round(sum(r.actual_km) filter (where b.runner_id = l.runner_id), 1) end,
         (count(r.id) filter (where b.runner_id = l.runner_id and r.actual_km is null))::int
  from ledger_items l
  left join bookings b on b.id = l.booking_id
  left join runs r on r.booking_id = l.booking_id
  where l.runner_id = auth.uid() and l.created_at >= v_start;
end $$;
revoke execute on function my_week_stats() from public, anon;
grant execute on function my_week_stats() to authenticated;

comment on function my_week_stats is
  '0158 (was 0132 §B, was 0121 §B): the runner week row. `week_net` is real money from ledger_items
and is never NULL. `week_km` is the sum of the runs that carry a distance: 0 when there were no runs
at all (a true zero), NULL when runs happened and none of them was measured, otherwise the measured
sum — which `week_unmeasured > 0` marks as a LOWER BOUND. `week_unmeasured` is a RUN COUNT, never a
distance. Run-derived columns keep 0132''s attribution filter.';


-- ═══ §C the three weekly boards — an unmeasured group stops being ranked and drawn as 0km ═══
--                                                                            (review finding #8)
--
-- All three coalesce a group's `sum(actual_km)` to zero (0012:8, 0012:23, 0022:9) and two of them
-- RANK on that coalesced value (0022:11, 0022:19). A dog whose only run this week was an incident
-- appears on the neighbourhood board as having run `0km` — a public claim about someone's dog,
-- derived from a measurement that does not exist.
--
-- ⚠ ORDERING IS THE PART THAT NEEDED A DECISION, not the display. `order by <expr> desc` in
--   postgres is NULLS FIRST, so simply deleting the coalesce would put an UNMEASURED group at
--   **rank 1**. `nulls last` is written explicitly on every one. That is a real choice and it is
--   named rather than hidden: an unknown total is placed after every measured one, INCLUDING a
--   measured 0. Placing it anywhere is a claim, and this is the least-wrong claim available,
--   because it never fabricates a NUMBER — the row's own km renders as 「기록 없음」, so the order
--   is the only thing being asserted and the reader is not told a distance.
--   (Under the old coalesce these groups sorted AT 0, i.e. tied with a genuinely-0 group; the only
--   ordering that changes is that tie, and it changes in the direction that stops an unknown
--   outranking a measurement.)
--
-- ⚠ The runners board orders by `count` first and km only as a tiebreak, so its `nulls last`
--   matters only inside a tie — written anyway, because a predicate that is correct by accident of
--   the column ahead of it stops being correct when someone reorders the columns.
--
-- All three gain a column → drop + create → explicit ACL (production: authenticated + service_role).

drop function if exists leaderboard_dogs_weekly();
create function leaderboard_dogs_weekly()
returns table(dog_name text, photo_url text, km numeric, runs bigint, unmeasured bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  select d.name, d.photo_url,
         sum(r.actual_km)::numeric(7,2),
         count(r.id),
         count(r.id) filter (where r.actual_km is null)
  from runs r
  join bookings b on b.id = r.booking_id and b.status = 'completed'
  join dogs d on d.id = b.dog_id
  where r.ended_at >= date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
  group by d.id, d.name, d.photo_url
  order by sum(r.actual_km) desc nulls last
  limit 10;
$$;
revoke execute on function leaderboard_dogs_weekly() from public, anon;
grant execute on function leaderboard_dogs_weekly() to authenticated, service_role;

drop function if exists leaderboard_runners_weekly();
create function leaderboard_runners_weekly()
returns table(runner_name text, avatar_url text, km numeric, runs bigint, unmeasured bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  select pr.name, pr.avatar_url,
         sum(r.actual_km)::numeric(7,2),
         count(r.id),
         count(r.id) filter (where r.actual_km is null)
  from runs r
  join bookings b on b.id = r.booking_id and b.status = 'completed' and b.runner_id is not null
  join profiles pr on pr.id = b.runner_id
  where r.ended_at >= date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
  group by pr.id, pr.name, pr.avatar_url
  order by count(r.id) desc, sum(r.actual_km) desc nulls last
  limit 10;
$$;
revoke execute on function leaderboard_runners_weekly() from public, anon;
grant execute on function leaderboard_runners_weekly() to authenticated, service_role;

drop function if exists leaderboard_dogs_weekly_delta();
create function leaderboard_dogs_weekly_delta()
returns table(dog_name text, photo_url text, km numeric, runs bigint, unmeasured bigint, delta int)
language sql stable security definer set search_path = public, pg_temp as $$
  with cur as (
    select d.id, d.name, d.photo_url,
           sum(r.actual_km)::numeric(7,2) as km,
           count(r.id) as runs,
           count(r.id) filter (where r.actual_km is null) as unmeasured,
           rank() over (order by sum(r.actual_km) desc nulls last) as rk
    from runs r
    join bookings b on b.id = r.booking_id and b.status = 'completed'
    join dogs d on d.id = b.dog_id
    where r.ended_at >= date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    group by d.id, d.name, d.photo_url
  ), prev as (
    select d.id,
           rank() over (order by sum(r.actual_km) desc nulls last) as rk
    from runs r
    join bookings b on b.id = r.booking_id and b.status = 'completed'
    join dogs d on d.id = b.dog_id
    where r.ended_at >= (date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') - interval '7 days'
      and r.ended_at < date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    group by d.id
  )
  select cur.name, cur.photo_url, cur.km, cur.runs, cur.unmeasured,
         (prev.rk - cur.rk)::int
  from cur
  left join prev on prev.id = cur.id
  order by cur.km desc nulls last
  limit 10;
$$;
revoke execute on function leaderboard_dogs_weekly_delta() from public, anon;
grant execute on function leaderboard_dogs_weekly_delta() to authenticated, service_role;

comment on function leaderboard_dogs_weekly_delta is
  '0158 (was 0022): 홈 티커용 — 주간 km 보드 + 지난주 대비 랭크 델타 (신규 진입은 null). `km` is the
sum of the MEASURED runs in the group and is NULL when the group holds no measurement at all;
`unmeasured` counts the runs left out, so a caller can tell a complete total from a lower bound.
Ranking is `nulls last` — an unknown total never outranks a measured one.';


-- ═══ §D grant_weekly_rewards — the reader the review did not name, and it SPENDS ═══
--
-- 🔴 Found by sweeping every aggregate of `actual_km` rather than only the sites the reviewer
--    cited (the standing law: a finding's SENTENCE is the property; the cited site is one place it
--    is observable). The weekly miles cron (0014:70, `weekly-rewards`, every Sunday) picks the
--    owner TOP 3 with:
--        order by sum(rr.actual_km) desc            -- 0029, and DEPLOYED: prosrc read 2026-08-28
--    There is no coalesce here, which is exactly why it is WORSE than the boards rather than
--    exempt: `desc` is **NULLS FIRST** in postgres, so an owner whose every completed run last week
--    was unmeasured sorts **ahead of everyone who actually ran** and is paid 200 하이 포인트 for it.
--    Same class, opposite sign — the boards convert an unknown into the smallest number, this
--    converts it into the largest. And this one is not a label: it writes `miles_ledger`.
--
-- ⚠ The runner arm is untouched. It ranks on `count(*)` of `end_reason='completed'` runs (0029's
--   own correction) and never reads a distance, so it has nothing to be blind to.
--
-- Body is 0029's, verbatim, plus `nulls last` and the in-body `pg_temp`. Return type unchanged →
-- `create or replace`; ACL restated (0057:352 — service_role ONLY; anon holding this could mint
-- unlimited 하이 포인트, which is the finding 0057 wrote it for).
create or replace function grant_weekly_rewards() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record;
  amounts int[] := array[200, 100, 50];
  i int;
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  -- 강아지(보호자) 부문: 지난주 km TOP3 — 실측 km는 조기 종료여도 실제 달린 거리 (유지)
  -- [0158 §D] nulls last: 거리를 재지 못한 러닝만 있는 보호자가 1위가 되지 않는다.
  i := 1;
  for r in (
    select b.owner_id as pid
    from runs rr
    join bookings b on b.id = rr.booking_id and b.status = 'completed'
    where rr.ended_at >= week_start - interval '7 days' and rr.ended_at < week_start
    group by b.owner_id
    order by sum(rr.actual_km) desc nulls last
    limit 3
  ) loop
    insert into miles_ledger (profile_id, delta, reason) values (r.pid, amounts[i], 'weekly_top_dog');
    i := i + 1;
  end loop;

  -- 러너 부문: 지난주 '완주' 수 TOP3 — [0029] 부분 러닝 제외 (인센티브는 완주만)
  i := 1;
  for r in (
    select b.runner_id as pid
    from runs rr
    join bookings b on b.id = rr.booking_id and b.status = 'completed' and b.runner_id is not null
    where rr.ended_at >= week_start - interval '7 days' and rr.ended_at < week_start
      and rr.end_reason = 'completed'
    group by b.runner_id
    order by count(*) desc
    limit 3
  ) loop
    insert into miles_ledger (profile_id, delta, reason) values (r.pid, amounts[i], 'weekly_top_runner');
    i := i + 1;
  end loop;
end $$;
revoke execute on function grant_weekly_rewards() from public, anon, authenticated;
grant execute on function grant_weekly_rewards() to service_role;


-- ═══ §E VERIFY — the apply refuses if any of the six landed with the defect still in it ═══
--
-- ⚠ A property checked ONLY here survives exactly until someone recreates the function, so suite
--   189 owns the standing versions of every claim below. This block is the apply-time belt: it
--   fires on the machine doing the push, before anything else in the transaction commits.
-- ⚠ COMMENTS ARE STRIPPED BEFORE EVERY MATCH. This file documents the zero-conversion it removes,
--   in prose, inside the function bodies — so an un-stripped `prosrc` match would find the
--   coalesce it is looking for in the sentence explaining that the coalesce is gone, and the check
--   would be satisfied by the quality of the documentation. (The standing comment-matching law.)
do $$
declare
  v_bad text := '';
  v_src text;
  f text;
  v_defs text[] := array['my_ledger_rows','my_week_stats','leaderboard_dogs_weekly',
                         'leaderboard_runners_weekly','leaderboard_dogs_weekly_delta',
                         'grant_weekly_rewards'];
begin
  foreach f in array v_defs loop
    -- absence must be LOUD: every arm below is vacuously true on a function that is not there.
    if not exists (select 1 from pg_proc p where p.proname = f
                     and p.pronamespace = 'public'::regnamespace) then
      v_bad := v_bad || ' MISSING(' || f || ')'; continue;
    end if;
    select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
      from pg_proc p where p.proname = f and p.pronamespace = 'public'::regnamespace;
    -- ① no aggregate distance may be coalesced to a number again
    if v_src ~ 'coalesce\s*\(\s*sum\s*\(\s*r{1,2}\.actual_km' then
      v_bad := v_bad || ' COALESCED-SUM(' || f || ')';
    end if;
    -- ② definer + in-body search_path (98 H1's invariant, asserted here at birth)
    if not exists (select 1 from pg_proc p where p.proname = f
                     and p.pronamespace = 'public'::regnamespace
                     and p.prosecdef
                     and p.proconfig::text like '%search_path=public, pg_temp%') then
      v_bad := v_bad || ' SHAPE(' || f || ')';
    end if;
    -- ③ never PUBLIC-executable, never anon (a DROP discards the ACL; a CREATE is born PUBLIC)
    -- ⚠ THE NULL ARM IS THE ONE THAT MATTERS AND IT IS EASY TO OMIT: a function that was never
    --   granted carries `proacl IS NULL`, which means owner + **PUBLIC** — and `aclexplode(NULL)`
    --   returns ZERO ROWS, so an `exists` test alone is silent on precisely the state 0116:636
    --   records as this repo's worst shape. Checked positively, before the explode.
    if (select p.proacl from pg_proc p where p.proname = f
          and p.pronamespace = 'public'::regnamespace) is null then
      v_bad := v_bad || ' DEFAULT-PUBLIC-ACL(' || f || ')';
    elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.proname = f and p.pronamespace = 'public'::regnamespace
                     and (a.grantee = 0 or a.grantee = 'anon'::regrole)) then
      v_bad := v_bad || ' PUBLIC-OR-ANON(' || f || ')';
    end if;
  end loop;

  -- ④ the finding-#9 fact itself: the ledger row reads the RUN's distance, not the booking's.
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc p where p.proname = 'my_ledger_rows' and p.pronamespace = 'public'::regnamespace;
  if v_src is null or v_src !~ 'r\.actual_km' then v_bad := v_bad || ' LEDGER-NOT-ACTUAL'; end if;
  if v_src is not null and v_src ~ 'b\.km' then v_bad := v_bad || ' LEDGER-STILL-PLANNED'; end if;

  -- ⑤ the ranking decision, as source — the only place NULLS FIRST is observable without a fixture
  --    that has an all-unmeasured group, and the cron has no return value to read at all.
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc p where p.proname = 'grant_weekly_rewards' and p.pronamespace = 'public'::regnamespace;
  if v_src is null or v_src !~ 'sum\(rr\.actual_km\)\s+desc\s+nulls\s+last' then
    v_bad := v_bad || ' MILES-NULLS-FIRST';
  end if;

  if v_bad <> '' then
    raise exception '0158 VERIFY failed:%', v_bad;
  end if;
end $$;
