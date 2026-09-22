-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0209 — the runner's earnings have a SHAPE, and the request card stops hiding a field we collect
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 240_ledger_month_totals_suite.sql (tag `lmt`) — 0209-M1 · M2 · M3 · M4 · M5 · N1 · S1
-- Deploy: `supabase db push` only, plus a client build. No edge function, no cron, no new table.
--
-- ─── §0 WHAT IS MISSING, MEASURED ON TRUNK f813376 ─────────────────────────────────────────────
-- `runner/earnings.tsx` today can answer exactly two questions about money over time: 「what have
-- I not been paid yet」 (`my_ledger_unpaid_total`, 0192 §B) and 「what have I earned in my whole
-- life」 (`my_ledger_total`, 0027 → 0121 §F). Between those two there is nothing, and the list
-- that would supply it — `my_ledger_rows()` (0121 §A, extended by 0192 §A) — carries
-- **`limit 30`**. So a runner who has done more than thirty runs cannot see last month at all,
-- and one who has done fewer cannot see it either, because thirty undated rows are not a month.
--
-- ⚠ The obvious client-side shape — bucket `created_at` in JS — is the defect this file exists to
--   not ship, twice over: (a) the 30-row cap means the buckets would be silently WRONG for
--   exactly the runners who work most, which is the `fetchRunnerJobs` cap class (CLAUDE.md,
--   2026-08-26) arriving through an aggregate instead of a list; (b) the bucket boundary is a KST
--   calendar fact and a phone is not in KST. `kst.ts` could do the arithmetic honestly, but it
--   cannot see the rows the cap removed. The count has to be the server's.
--
-- ⚠ `fetchLedgerMonth` existed once and was deleted with the v4 hero (0121 §B's own header
--   records it had ZERO callers). This is not that function restored. That one re-read rows; this
--   one returns an AGGREGATE and never a row, which is what makes the cap irrelevant to it.
--
-- ─── §0b WHY A MONTH NET DOES NOT REOPEN THE MARGIN RULING, AND WHAT WOULD ─────────────────────
-- Sean, 2026-08-24, verbatim: 「For runner money, don't show them the 수수료 … only show the final
-- profit per run; keep the margin a secret.」 The rule is about COMPONENTS: any component printed
-- beside a net hands the fee back by subtraction (fee = Σcomponents − net) and with it the rate
-- (fee ÷ gross). A monthly NET is a sum of numbers the runner already reads one at a time on the
-- same screen — it discloses no new quantity and admits no subtraction, because there is nothing
-- to subtract it FROM. Adding a `gross_won`, a `fee_won` or a `commission_rate` here would undo in
-- one column what that ruling removed from thirty rows, so this function returns **net only**, and
-- 240 `0209-S1` asserts the absence by argument name rather than by anyone's care.
-- ⚠ `paid_won` is a net too — it is the part of the same net that has already moved. It is not a
--   second money axis; it is the same axis split by `paid_payout_id`, the marker 0186 wrote and
--   0192 §B already narrows on.
--
-- ─── §0c THE SAME ROWS, THE SAME PREDICATES — NOT A THIRD OPINION ABOUT WHAT A RUNNER EARNED ───
-- Three functions now answer money questions over `ledger_items` for one runner, and a fourth
-- that disagreed with them would be worse than no fourth at all: two numbers on one screen that
-- do not add up read as a bug in the money, not as a bug in a query.
--   `my_ledger_total`         Σ over `runner_id = auth.uid()`                       — LIFETIME
--   `my_ledger_unpaid_total`  the same Σ, `and paid_payout_id is null`              — UNPAID
--   `my_ledger_month_totals`  the same Σ, GROUPED by KST month, windowed            — THIS FILE
-- The summand is written out character for character as 0027/0121 §F wrote it. 240 `0209-M2`
-- pins the consequence rather than the transcription: over a window wide enough to hold every
-- row, **Σ of the month nets equals `my_ledger_total()` on the same fixture**. A drifted summand
-- cannot satisfy that, and no amount of reading the two bodies side by side proves it.
--
-- ⚠ `run_count` is `my_week_stats`'s `week_runs` (0121 §B, 0158 §A), clause for clause:
--   `count(r.id) filter (where b.runner_id = l.runner_id)`. It counts rows that HAVE a run and
--   whose run belongs to THIS runner, so a cancellation-compensation row (0080
--   `record_enroute_cancel_comp` · 0085 `record_late_cancel_share` — no `runs` row exists) adds
--   to the month's MONEY and not to its RUN COUNT. That asymmetry is deliberate and is already
--   the product's vocabulary: 156 P3 pins it for the week strip. A month that says 「3회」 beside
--   money from four ledger rows is telling the truth about both; a month that said 「4회」 would
--   be claiming a run that never happened, which is the exact 「뛰지 않은 5km」 defect 0121 §A
--   fixed on the row beneath it.
--
-- ─── §0d THE MONTH BOUNDARY IS KST, AND THE SESSION ZONE MUST NOT BE ABLE TO REACH IT ──────────
-- 🔴 This is the one thing in this file that has already gone wrong once in this repo, on this
--    exact operator. 0121's mutation M3 dropped the KST wrapping from `date_trunc('week', …)` and
--    the harness came back **GREEN** — because `date_trunc` truncates a `timestamptz` in the
--    SESSION timezone and the machine ran KST, so the mutation was invisible locally and live on
--    production's UTC. The shape that cannot do that is to leave timestamptz FIRST:
--        date_trunc('month', l.created_at at time zone 'Asia/Seoul')
--    `created_at at time zone 'Asia/Seoul'` is a plain `timestamp` holding the KST wall clock, and
--    `date_trunc` on a `timestamp` has no session zone to consult. There is no configuration on
--    any database that changes this expression's answer.
-- ⚠ The window's lower bound is expressed in the other direction on purpose —
--   `(date_trunc('month', now() at time zone 'Asia/Seoul') - make_interval(...)) at time zone
--   'Asia/Seoul'` — so the comparison is `l.created_at >= <timestamptz>`, which is sargable and
--   which compares two instants rather than two wall clocks. Both halves are KST-anchored; only
--   one of them has to be, and doing both keeps the boundary in one vocabulary.
-- ⚠ 240 `0209-M1` measures this under `America/New_York` AND under `Asia/Seoul` and demands the
--   SAME answer. A UTC-only arm would not be enough: the rows that separate the two readings sit
--   in the nine hours between UTC midnight and KST midnight, and a New_York session disagrees
--   with KST about a far wider band. A Seoul-only run is worth nothing for this class
--   (CLAUDE.md, measured on the 2026-08-27 KST slice: 25 pins red under New_York, ZERO under
--   Seoul).
--
-- ─── §0e THE WINDOW, AND WHY IT IS CLAMPED RATHER THAN TRUSTED ─────────────────────────────────
-- `p_months` counts KST calendar months back from and INCLUDING the current one, so the default
-- 6 means 「this month and the five before it」. It is clamped to [1, 24]:
--   · NULL or absent → 6. A caller that forgot the argument gets the screen's number, not zero
--     months (which would render an empty state on a runner who has earned money).
--   · < 1 → 1. A zero or negative window is not a question anyone can mean, and answering it with
--     an empty set would look identical to 「you have never earned anything」.
--   · > 24 → 24. This is a definer over sealed money rows reachable by any authenticated caller;
--     an unbounded window is an unbounded scan someone else pays for. Two years is past every
--     screen this product has and past every screen it plausibly grows.
-- ⚠ **A month with no rows is ABSENT, not a zero row.** A zero-filled month is the server
--   asserting 「you earned nothing in July」, which is true only if we know July happened for this
--   runner — and for a runner who joined in August it is a sentence about a month they were not
--   here for. Absence says only what we know. The screen renders what comes back and says
--   「아직 정산된 러닝이 없어요」 when nothing does.
--
-- ─── §0f §B: `dogs.neutered` HAS BEEN COLLECTED SINCE 0001 AND SHOWN TO NOBODY ─────────────────
-- Measured on trunk: `dogs.neutered` (0001:44) is written by `owner/dog.tsx` (a three-way
-- control — 예/아니오/unanswered), mapped by `api.ts`'s `DOG_SELECT`, and read by **zero**
-- surfaces the runner can reach. The runner's request card draws breed · weight · vaccine count ·
-- preference tags · memo and not this, and it cannot draw it, because the card's rows come from
-- `runner_open_requests` / `my_directed_requests` (0121 §D) and neither view selects the column.
-- So the field is a question we ask an owner and then drop.
-- ⚠ It is the same disclosure family as the five fields already there — a husbandry fact the
--   owner entered FOR a runner, about the animal the runner is about to take out alone, and one
--   that genuinely changes the walk (an intact dog's behaviour around other dogs, a bitch in
--   season). It is not a medical record and not a person's datum. §B appends it to both views and
--   nothing else about them moves.
-- ⚠ `create or replace view` and never DROP (CLAUDE.md, grant preservation), and the column is
--   APPENDED — postgres refuses a replace that renames, retypes or reorders an existing view
--   column, and permits only additions at the end. 0121's four ACL lines are restated here for
--   the same reason 0192 §A restates a function's: a view that is ABSENT on the database being
--   applied to is created fresh by this statement, and 0107:98 records that default privileges
--   hand `anon` SELECT on a new view.
-- ⚠ THE UNANSWERED VALUE IS NULL AND STAYS NULL. `owner/dog.tsx` offers no 「모름」 and writes
--   `neutered ?? undefined`, so a dog whose owner never answered has NULL here. The client renders
--   NOTHING for NULL — not 「중성화 정보 없음」, not a dash. An absent answer is not a third answer.
--
-- ─── §0g WHAT THIS FILE DOES NOT DO ────────────────────────────────────────────────────────────
-- No ledger row, settlement amount or payout moves. `my_ledger_rows`, `my_ledger_total`,
-- `my_ledger_unpaid_total`, `my_week_stats` and `ops_payouts_due` are untouched — this is a READ
-- beside them, and 0192 §0's reasoning for adding a SECOND function rather than widening a
-- correct one applies here unchanged (the §④ class: widening what an existing value MEANS breaks
-- correct callers with no edit to them). The 0186:192-195 column seal on `payouts` is not
-- consulted; this function never reads `payouts` at all, only `ledger_items.paid_payout_id`.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A my_ledger_month_totals — one row per KST month the runner actually earned in
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ THE PARTY GATE IS AN ABSENCE, NOT A CONDITION. There is no `p_runner` argument: the only
--   runner this function can be asked about is `auth.uid()`, and it is the FIRST conjunct of the
--   only WHERE clause here. That shape is stronger than a checked argument because there is
--   nothing to check — and 240 `0209-M4` asserts it over `pg_proc.proargnames` rather than over
--   behaviour, because a `p_runner` added later would redden no behavioural arm on a fixture
--   where the caller and the subject are the same person (0203 `E4`'s law).
-- ⚠ Money is `bigint`, not `int`, even though no month will approach 2^31. `my_ledger_total` and
--   `my_ledger_unpaid_total` are both bigint and `0209-M2` compares this function's sum against
--   one of them; a narrower type here would put a cast on the equality the pin exists to measure.
create function my_ledger_month_totals(p_months int default 6)
returns table (month_start date, net_won bigint, run_count int, paid_won bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_months int;
  v_from   timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  -- §0e: absent → the screen's number, absurd → the nearest question someone could mean.
  v_months := least(greatest(coalesce(p_months, 6), 1), 24);
  -- §0d: KST wall clock FIRST, so no session timezone can reach date_trunc.
  v_from := (date_trunc('month', now() at time zone 'Asia/Seoul')
               - make_interval(months => v_months - 1)) at time zone 'Asia/Seoul';
  return query
  select date_trunc('month', l.created_at at time zone 'Asia/Seoul')::date,
         -- the summand of 0027/0121 §F, character for character (§0c)
         coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0) - l.platform_fee), 0)::bigint,
         -- my_week_stats' week_runs, clause for clause: a run that exists AND is this runner's.
         -- A cancellation-compensation row has no `runs` row and is counted by neither filter.
         (count(r.id) filter (where b.runner_id = l.runner_id))::int,
         -- the same net, narrowed by 0186's marker — the half that has already moved (§0b)
         coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0) - l.platform_fee)
                    filter (where l.paid_payout_id is not null), 0)::bigint
  from ledger_items l
  left join bookings b on b.id = l.booking_id
  left join runs r on r.booking_id = l.booking_id
  where l.runner_id = auth.uid() and l.created_at >= v_from
  group by 1
  order by 1 desc;
end $$;
revoke execute on function my_ledger_month_totals(int) from public, anon;
grant execute on function my_ledger_month_totals(int) to authenticated;

comment on function my_ledger_month_totals is
  '0209 §A: 러너 수익의 **월별 집계** — KST 달 경계로 묶은 한 달 한 행. 0121 §A의 목록은
`limit 30`이라 많이 뛴 러너일수록 지난달을 통째로 못 본다; 이건 행이 아니라 합계라서 그 캡과
무관하다. 합산식은 my_ledger_total(0027/0121 §F)의 것을 글자 그대로 옮겼고, 240 0209-M2가
「모든 달의 net 합 = my_ledger_total」을 같은 픽스처에서 잰다(옮겨 적기가 아니라 결과를 핀).
run_count는 my_week_stats의 week_runs 그대로 — runs 행이 있고 그 run이 이 러너의 것인 행만
세므로 취소 보상 행은 **돈에는 들어가고 횟수에는 안 들어간다**(156 P3가 주간 스트립에서 이미
핀한 어휘). paid_won은 0186의 표식(paid_payout_id)으로 가른 같은 net이다 — 두 번째 돈 축이 아니다.
🔴 수수료·gross·commission_rate 칸은 없다(Sean 2026-08-24 마진 비밀): 순액 옆에 구성요소가 하나라도
찍히면 뺄셈으로 수수료가, 나눗셈으로 요율이 돌아간다. 달 경계는 `created_at at time zone
''Asia/Seoul''`을 **먼저** 만든 뒤 date_trunc를 거는 형태다 — timestamptz에 date_trunc를 걸면
세션 타임존이 답을 고르고, 0121의 M3가 바로 그 변이에서 초록을 냈다(하네스 기계가 KST였다).
p_months는 현재 달을 포함해 뒤로 세는 KST 달 수이고 [1, 24]로 조인다. 행이 없는 달은 **없는
행**이지 0원 행이 아니다 — 0원 행은 그 러너가 없던 달에 대해서도 문장을 만든다.
240 0209-M1 ~ M5 · S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B the two request views learn `dogs.neutered` — a field we have collected since 0001
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Byte-faithful copies of 0121:110 and 0121:133 with ONE column appended to each. Nothing else in
-- either body moves: the fare columns stay absent by construction (0121 contract §D), the inline
-- `commission_rate` scalar subquery stays inline and stays un-helper'd (0121's O-F2/X-№1 — a
-- helper this view could call, a client could call, and the helper IS the rate oracle), the
-- constants 9900/3000 stay 0101's, and both WHERE clauses are untouched. 240 `0209-N1` reads the
-- shape back and 156 P5/P6/P7 keep measuring the halves this file did not touch.
create or replace view runner_open_requests as
select
  b.id, b.scheduled_at, b.km, b.pace_label, b.route_id,
  r.name as route_name,
  d.id as dog_id, d.name as dog_name, d.breed, d.weight_kg, d.memo, d.photo_url,
  d.preferences, d.vaccinations,
  round((9900 + round(b.km * 3000) + coalesce(b.addon_fare, 0))
        * (1 - coalesce((select r2.commission_rate from runners r2
                         where r2.profile_id = auth.uid()), 0.33)))::int as expected_net,
  -- [0209 §B] APPENDED, never inserted: `create or replace view` permits additions only at the
  -- end. NULL when the owner never answered, and the client draws nothing for NULL.
  d.neutered
from bookings b
join dogs d on d.id = b.dog_id
left join routes r on r.id = b.route_id
where b.status = 'matching'
  and b.runner_id is null
  and b.club_session_id is null
  and is_active_runner()
  and not exists (
    select 1 from booking_declines bd
    where bd.booking_id = b.id and bd.runner_profile_id = auth.uid()
  );

create or replace view my_directed_requests as
select
  b.id, b.scheduled_at, b.km, b.pace_label, b.route_id,
  r.name as route_name,
  d.id as dog_id, d.name as dog_name, d.breed, d.weight_kg, d.memo, d.photo_url,
  d.preferences, d.vaccinations,
  round((9900 + round(b.km * 3000) + coalesce(b.addon_fare, 0))
        * (1 - coalesce((select r2.commission_rate from runners r2
                         where r2.profile_id = auth.uid()), 0.33)))::int as expected_net,
  d.neutered   -- [0209 §B] the two legs are shape-identical by contract (0121's mapper law)
from bookings b
join dogs d on d.id = b.dog_id
left join routes r on r.id = b.route_id
where b.status = 'runner_pending'
  and b.runner_id = auth.uid();

-- 0121:150-153's four lines, restated. `create or replace` PRESERVES grants where the view
-- already exists — and where it does not, this statement is a plain CREATE, and 0107:98 records
-- that default privileges hand `anon` SELECT on a new view. Restating costs nothing and is the
-- only thing standing between these two views and an anonymous reader on a rebuilt environment.
revoke all on runner_open_requests from public, anon, authenticated;
revoke all on my_directed_requests from public, anon, authenticated;
grant select on runner_open_requests to authenticated;
grant select on my_directed_requests to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C VERIFY — apply-time, on whatever database this file actually lands on
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The suite asserts these properties against the schema the harness builds from scratch; this
-- block asserts them against the schema THIS statement just built, and aborts before anything
-- downstream runs. The overlap is deliberate — 0131-G4's lesson: a property checked only at apply
-- is protected exactly until someone recreates the object, and a property checked only in a suite
-- is not checked on the environment the file lands on.
-- ⚠ Comments are STRIPPED before every source match. `prosrc` is source PLUS our own prose, and
--   §A's body documents `Asia/Seoul` and `auth.uid()` in comments — an un-stripped match would be
--   satisfied by the writing that EXPLAINS the guard (CLAUDE.md, the comment-matching law).
do $$
declare
  v_bad text := '';
  v_src text;
  v_raw text;
  v_oid oid;
begin
  select p.oid into v_oid from pg_proc p
   where p.proname = 'my_ledger_month_totals' and p.pronamespace = 'public'::regnamespace;
  -- absence must be LOUD: every arm below is vacuously true on a function that is not there.
  if v_oid is null then v_bad := v_bad || ' MISSING(my_ledger_month_totals)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
    -- a CREATE is born PUBLIC-executable (0116:636). The NULL arm goes FIRST, because
    -- aclexplode(NULL) returns zero rows and an `exists` test alone is silent on exactly that.
    if (select proacl from pg_proc where oid = v_oid) is null
      then v_bad := v_bad || ' DEFAULT-PUBLIC-ACL';
    elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
      then v_bad := v_bad || ' PUBLIC-OR-ANON'; end if;
    -- the positive half: a seal that also shut the front door passes every negative sweep and
    -- ships an outage (189 0158-B5's warning, applied at birth).
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' AUTHENTICATED-CANNOT'; end if;

    -- ① no money column beyond net — §0b's ruling, asserted by NAME rather than by care
    if exists (select 1 from unnest(
                 (select proargnames from pg_proc where oid = v_oid)) n
                where n in ('gross_won', 'fee_won', 'commission_rate', 'platform_fee', 'gross'))
      then v_bad := v_bad || ' MARGIN-COLUMN-ON-A-RUNNER-SURFACE'; end if;
    -- ② the party gate is an ABSENCE: the only IN argument is the window
    if (select count(*) from unnest(
          (select proargnames from pg_proc where oid = v_oid)) n
         where n in ('p_runner', 'p_uid', 'p_profile', 'p_runner_profile_id')) is distinct from 0
      then v_bad := v_bad || ' TAKES-A-SUBJECT(the gate must be auth.uid() and nothing else)'; end if;

    select prosrc into v_raw from pg_proc where oid = v_oid;
    if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(my_ledger_month_totals)';
    else
      v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
      -- ③ §0d: date_trunc never sees a timestamptz. Both KST conversions must be in the
      --    EXECUTABLE text, and `created_at` must be converted before it is truncated.
      if (v_src ~ 'date_trunc\(''month'', l\.created_at at time zone ''Asia/Seoul''\)')
           is distinct from true
        then v_bad := v_bad || ' MONTH-BOUNDARY-NOT-KST-ANCHORED'; end if;
      if (v_src ~ 'date_trunc\(''month'', now\(\) at time zone ''Asia/Seoul''\)')
           is distinct from true
        then v_bad := v_bad || ' WINDOW-ORIGIN-NOT-KST-ANCHORED'; end if;
      -- ④ the row scope, and it is the runner's own uid
      if (v_src ~ 'l\.runner_id = auth\.uid\(\)') is distinct from true
        then v_bad := v_bad || ' NO-PARTY-SCOPE'; end if;
      if (v_src ~ 'not_authenticated') is distinct from true
        then v_bad := v_bad || ' NO-ANONYMOUS-REFUSAL'; end if;
      -- ⑤ the CRUDE CONTROL for the stripper: the RAW source does contain a `--` comment
      --    mentioning Asia/Seoul, so a stripper that silently did nothing would make ③ pass for
      --    the wrong reason and this arm is the only thing that can tell.
      if (v_raw ~ '-- §0d') is distinct from true
        then v_bad := v_bad || ' STRIP-CONTROL-ABSENT(the comment arms above prove nothing)'; end if;
    end if;
  end if;

  -- ⑥ §B: both views carry the new column, and neither carries it for `anon`
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'runner_open_requests'
         and column_name = 'neutered') is distinct from 1
    then v_bad := v_bad || ' OPEN-VIEW-MISSING-NEUTERED'; end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'my_directed_requests'
         and column_name = 'neutered') is distinct from 1
    then v_bad := v_bad || ' DIRECTED-VIEW-MISSING-NEUTERED'; end if;
  if has_table_privilege('anon', 'public.runner_open_requests', 'select') is distinct from false
    then v_bad := v_bad || ' ANON-READS-OPEN-REQUESTS'; end if;
  if has_table_privilege('anon', 'public.my_directed_requests', 'select') is distinct from false
    then v_bad := v_bad || ' ANON-READS-DIRECTED-REQUESTS'; end if;
  if has_table_privilege('authenticated', 'public.runner_open_requests', 'select')
       is distinct from true
    then v_bad := v_bad || ' AUTHENTICATED-LOST-OPEN-REQUESTS'; end if;
  if has_table_privilege('authenticated', 'public.my_directed_requests', 'select')
       is distinct from true
    then v_bad := v_bad || ' AUTHENTICATED-LOST-DIRECTED-REQUESTS'; end if;
  -- ⑦ 0121 §D's fare seal is not this file's to move, and a §B rewrite that reintroduced a fare
  --    column would still pass every arm above.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public'
                and table_name in ('runner_open_requests', 'my_directed_requests')
                and column_name in ('base_fare', 'distance_fare', 'addon_fare', 'total_price',
                                    'min_fare', 'commission_rate'))
    then v_bad := v_bad || ' FARE-COLUMN-BACK-ON-A-REQUEST-VIEW(0121 §D)'; end if;

  if v_bad <> '' then raise exception '0209 VERIFY failed:%', v_bad; end if;
end $$;
