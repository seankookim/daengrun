-- 0097 — 0096이 없앤 경보를 되살린다. 일은 끝났는데 러너가 지급받지 못한 예약.
--
-- ═══ §0 WHY THIS EXISTS — I removed the alarm, so I owe the replacement ══════════════════
-- `0096` fixed a real deadlock: a runner blocked from all future work by an escalated booking
-- neither party could clear. It did that correctly. But money's review of it found the thing I
-- did not:
--
--   BEFORE 0096:  an escalated booking left the runner **gated AND unpaid**   → loud
--   AFTER  0096:  the same booking leaves the runner **un-gated and unpaid**  → quiet
--
-- The runner goes back to work and nothing surfaces. The chronic problem — `0083 §0h`, that
-- `incident_review` has no marketplace money exit, so a runner is permanently unpaid for work
-- already done — was never mine and is not fixed here. But **the acute fix removed the symptom
-- that would have made someone notice the chronic one**, and that is mine.
--
-- This is the composition-hazard instinct from `0096` §0 applied one level in, and I did not
-- apply it to my own change: I checked what the fix broke, not what it made invisible. Recorded
-- because that is the generalisable half — **a fix that removes a symptom inherits a duty to the
-- disease.** The three-migration composition and this are the same failure at different scales.
--
-- ═══ §1 WHY THIS IS NOT A COLUMN ON `ops_gated_runners` ══════════════════════════════════
-- The natural suggestion (money's, and it is the obvious one) is to add a column to `0096 §7`'s
-- `ops_gated_runners` saying "this booking has an ended run and no settlement". **That cannot
-- work**, and the reason is worth stating so nobody re-proposes it:
--   `ops_gated_runners`' predicate requires `(runner_confirmed_return_at is null or
--   owner_confirmed_return_at is null)` — a MISSING stamp. The quiet case begins at the exact
--   moment both stamps land, which is the exact moment the row LEAVES that function.
-- The two populations barely overlap: one is "cannot work", the other is "was not paid". A
-- column on the first would be blank for every row of the second. So this is its own predicate,
-- keyed on the run and the settlement rather than on the stamps.
--
-- ═══ §2 SCOPE — detection only, and the boundary is deliberate ═══════════════════════════
-- Under the fleet split money owns `ledger_items`, `payments` and the `settle_*` family; custody
-- owns booking state and the stamps. **Paying a stranded runner is money's slice** (`0083 §0h`,
-- which needs a runner-payout price in SQL — the same missing piece `§0g` names). This file
-- writes nothing, moves no money, changes no status, and creates no new state. It is a `stable`
-- query function and nothing else.
-- ⚠ It also does NOT page. `ops_recipients` is 0 rows in production and `OPS_PROFILE_ID` is
-- unset (verified independently by money via `supabase secrets list`), so a pager would resolve
-- to `console.error` — ⑫'s memo: a signal whose remedy does not apply is worse than an
-- unmonitored state. Who receives, who acknowledges, severity and response time are Sean's.
--
-- ═══ §3 WHAT "UNPAID FOR WORK DONE" ACTUALLY MEANS HERE ══════════════════════════════════
-- The run ENDED (`runs.ended_at is not null` — the work happened and its measurement is frozen)
-- and money never moved (`runs.settled_at is null` AND no `ledger_items` row). Status is not
-- `completed`, because a completed booking settled by definition.
-- ⚠ `ledger_items` is checked as well as `runs.settled_at`, and not instead of it: `0081`'s
-- `record_enroute_cancel_comp` writes a ledger row for CANCELLED bookings, so ledger-presence
-- alone is not a settlement anchor (REGISTRY's shared-object table says so explicitly). Requiring
-- both to be absent is the conservative reading — a row appears here only when nothing paid the
-- runner by either route.
-- ⚠ Clubs are excluded: they have their own payout machine (`club_release_payouts`, 0045/0072)
-- and would report as stranded while being perfectly well handled.

create or replace function ops_unsettled_runs()
returns table (
  booking_id uuid,
  runner_id uuid,
  status text,
  run_ended_at timestamptz,
  unpaid_for interval,
  both_confirmed boolean,
  escalated boolean,
  why text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.id,
         b.runner_id,
         b.status::text,
         r.ended_at,
         now() - r.ended_at,
         (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null),
         (b.status::text = 'incident_review'),
         -- Name the reason per row. An operator seeing "unpaid" needs to know whether this is the
         -- known dead end (0083 §0h, no marketplace exit — needs money's slice) or an ordinary
         -- settlement that simply has not run yet, because the two have different remedies and
         -- an alert that conflates them sends someone to the wrong place.
         case
           when b.status::text = 'incident_review'
             then '0083 §0h — incident_review has no marketplace money exit; the runner cannot be paid without an ops/money path. NOT self-serve.'
           when b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null
             then 'both parties confirmed and the seal exists but settle-run has not completed — retryable through the normal settle path'
           else 'return not yet confirmed by both parties — ordinary, becomes a concern only if it escalates (see ops_gated_runners)'
         end
    from bookings b
    join runs r on r.booking_id = b.id
   where b.runner_id is not null
     and b.club_session_id is null           -- clubs pay through club_release_payouts (0045/0072)
     and r.ended_at is not null              -- the work happened
     and r.settled_at is null                -- money never moved…
     and b.status::text <> 'completed'
     -- …and no ledger row by any route. Checked SEPARATELY from settled_at because 0081 writes a
     -- ledger row for cancelled bookings, so its presence is not proof of settlement — but its
     -- absence, together with settled_at being null, is proof the runner got nothing.
     and not exists (select 1 from ledger_items li where li.booking_id = b.id)
   order by r.ended_at, b.id
$$;

revoke execute on function ops_unsettled_runs() from public, anon, authenticated;
grant  execute on function ops_unsettled_runs() to service_role;

comment on function ops_unsettled_runs is
  '0097 — 일이 끝났는데(runs.ended_at) 러너에게 아무것도 지급되지 않은(settled_at NULL이고 원장 행도
없음) 마켓플레이스 예약. 0096이 게이트 교착을 풀면서 "묶인 러너"라는 시끄러운 증상을 없앴는데,
그 아래의 만성 문제(0083 §0h — incident_review에는 마켓플레이스 상업적 출구가 없다)는 그대로라
러너가 조용히 미지급으로 남는다. 이 함수가 그 조용한 경우를 보이게 한다.
⚠ ops_gated_runners의 컬럼이 될 수 없다 — 그쪽은 스탬프가 비어 있어야 행이 잡히는데, 조용한 경우는
스탬프가 다 찍히는 순간 시작된다 (모집단이 거의 겹치지 않는다).
⚠ 탐지 전용. 지급 경로는 money의 슬라이스(§0h)다. 이 파일은 아무것도 쓰지 않는다.';
