-- 0111 — own the entry point: a client can no longer MAKE a booking row, nor the series row a
--        definer cron copies into one.
--
-- Supersedes the reviewer-rejected `0105_booking_insert_party_guard.sql` (deleted in this same
-- commit, together with suite 140 and its `HELD` line). Contract:
-- `docs/contracts/booking-entry-rebuild-contract.md` — built in a scratch cluster and ATTACKED
-- before a line of this file existed (21/21 pins, plus the pins that review found missing).
--
-- ═══ §0 THE HOLE, MEASURED ══════════════════════════════════════════════════════════════════
-- Every measurement below is a production `select` (2026-08-19, `supabase db query --linked`) or a
-- file:line in this repo. Nothing here is reasoned from.
--
-- ① `bookings owner insert` (`0002_rls.sql:95`) is `with check (owner_id = auth.uid() and
--    status = 'draft')`. `dog_id`, `runner_id`, `address_id`, `club_session_id` and `series_id`
--    are all unconstrained, and `authenticated`/`anon` hold table INSERT. Executed against
--    production as a real owner and rolled back: an INSERT naming an unrelated real runner was
--    ACCEPTED. The row is what `is_booking_party()` (`0002:15-22`, no status filter) reads, so a
--    forged draft is a key — chat thread to the victim, a review naming them, an `incidents` row,
--    the realtime `chat-*`/`bk-*` rooms (`0108:34,129`), and an attacker-authored push on the
--    victim's phone through `notifications`. A row carrying someone else's `dog_id` at
--    `status='matching'` also publishes that dog — name, breed, weight, memo, photo — to every
--    active runner through `marketplace_open_requests` (`0056:43-75`).
--
-- ② `recurring_series` is a CLIENT-WRITABLE MIRROR of ① that a definer cron copies in.
--    `series owner all` is `for all using (owner_id = auth.uid())` with `with_check` **NULL**
--    (`0002:100`); for a FOR ALL policy Postgres reuses USING as the insert check, so only
--    `owner_id` was ever pinned. `generate_recurring_bookings()` is `security definer` (so
--    `current_user` is `postgres` and no `current_user`-keyed trigger can see it) and copies the
--    series row into `bookings` (`0080_charge_machine.sql:765-775`). `cron.job` id 5,
--    `recurring-gen`, `7 * * * *`, active — measured live. Executed with 0105 applied: a
--    client-written series naming a VICTIM's dog with zero fares was ACCEPTED and the cron minted
--    the booking. Every FARE column is copied verbatim, and `min_fare` is the runner's gross
--    FLOOR (`0101_compute_runner_payout.sql:136`) — owner fares 0 + `min_fare` 500000 = owner
--    charged ₩0, colluding runner paid ₩500,000, platform funds the difference.
--
-- ③ **The one nothing else saw: the UPDATE arm of ②.** `recurring_series` has NO TRIGGER
--    (production `pg_trigger` read: zero non-internal triggers), and `authenticated` held
--    table-wide UPDATE. An owner of a wholly LEGITIMATE series could
--    `update recurring_series set dog_id = <victim dog>, base_fare = 0, min_fare = 500000` and the
--    cron mints exactly ②'s row. **Revoking INSERT alone does not close this** — reproduced in the
--    reviewer's cluster from a series created through the sanctioned `create_recurring_series`
--    RPC. The audit did not mention the table; 0105 could not see it.
--
-- ④ Sibling, same policy shape, same migration line: `holds self` on `slot_holds` (`0002:102`) is
--    also `for all using (…)` with `with_check` NULL, and a client hold naming any `runner_id` is
--    counted by `is_slot_available` (`0003_availability.sql:58+`). Calendar DoS against any
--    runner, no booking required.
--
-- ═══ §0b WHY THIS SUPERSEDES 0105 RATHER THAN EXTENDING IT ══════════════════════════════════
-- 0105 extended `_guard_booking_insert_cols` with party arms, and its header argued the specified
-- fix (revoke client INSERT) was too large because it needed a client change. **That premise is
-- false and was verified false**: `grep "from('bookings')" app/src app/app` → 31 hits, every one a
-- `.select(...)`. Zero client INSERT/UPDATE/UPSERT/DELETE on `bookings` anywhere. So the revoke
-- has zero client blast radius, needs no `create_booking_draft` RPC, and is strictly stronger than
-- a column blacklist — it covers `series_id` (which 0105 missed) and every column added in future.
-- 0105 also closes only ①; ② and ③ survive it untouched. It was never applied to any environment
-- (production `prosrc like '%booking_runner_is_server_assigned%'` → false, `srclen = 827` = the
-- 0083 body), so deleting it costs nothing and retires the `HELD` line it needed.
--
-- **`_guard_booking_insert_cols` IS NOT TOUCHED BY THIS FILE.** Once the grant is gone the
-- `current_user in ('authenticated','anon')` branch is unreachable by construction, so 0105's arms
-- would be dead code carrying a disproved rationale. The 0083 body stays exactly as it is —
-- nothing to change is nothing to accidentally revert (the 0086 §B trap).
--
-- ═══ §0c WHAT THIS FILE DOES NOT TOUCH — and why, named so nobody reads a closure into it ═════
-- · **`transition-booking`'s `payment_ok` arm** (`supabase/functions/transition-booking/index.ts:29-51`,
--   mirrored in `confirm-payment/handler.ts:192-198`). Measured and load-bearing: it is a **bare
--   owner-gated CAS that verifies NOTHING about payment** — no PG receipt, no ledger row, no
--   amount. Sean's "payment after the run" ruling makes it a product/state-machine change with a
--   different owner. Adjacent slice, both call sites named.
-- · **`is_booking_party`'s missing status filter** (`0002:15-22`). Narrowing it touches 9+ policies
--   across `runs`, `reviews`, `chat_threads`, `chat_messages`, `incidents` and 0108's realtime
--   policies, and it changes what a legitimately-nominated-but-unaccepted runner may reach — a
--   product question (Sean's D1/D2). Adjacent slice, not started here.
--   ⚠ **This is the B-11 residual, and it is audit finding #2 still reachable by any owner.**
--   `create-booking-hold` with the attacker's OWN dog (every ownership check passes) →
--   `payment_ok` (bare CAS, zero money moved) → `request_runner` with `meta.runner_id = <any real
--   runner>` ⇒ `bookings.runner_id = victim` at `runner_pending`, no acceptance — then chat,
--   attacker-authored messages, push on the victim's phone, reviews, incidents. Every step is a
--   sanctioned path behaving as designed, which is precisely why nothing below intersects it.
--   **This file moves the entry point and removes the forged-dog and forged-fare halves. CSO
--   finding #2 is PARTIALLY CLOSED, not CLOSED.** See `docs/security-booking-party-forgery.md` §E.9.
-- · **UPDATE and DELETE grants on `bookings`.** UPDATE is already deny-all'd for client roles by
--   `_guard_booking_cols` (`0058_security_hardening_2.sql:263-278`, `if new is distinct from old
--   then raise`; production `srclen = 578` confirms the deny-all body is live) and DELETE has no
--   permissive policy at all. Revoking them is CSO #12's general slice and would force edits to
--   the 0057/0058 suites. Named as adjacent; **pinned here for the first time** (D-9) because it
--   is the one load-bearing claim in 0105's header that was true and unpinned.
-- · **TRUNCATE / TRIGGER / REFERENCES.** Already closed on these three tables by
--   `0109_revoke_truncate.sql`, DEPLOYED to production 2026-08-19 evening. Not this slice's work
--   and deliberately not re-pinned here; suite 144 owns it, and the authority on a production
--   privilege bit is production's own `relacl`, re-read after deploy.
-- · **Club money path** (`session_pay_delegation`, `0081_club_money_gates.sql:184-198`) — R6 by
--   the `0080:658-665` boundary. Its `not_owner` gate, null runner and derived fare are already
--   pinned by suites 50 and 117; suite 146 regression-checks those rather than re-pinning them.
-- · **CSO #13** (`request_runner` lacks a `club_session_id` check) — adjacent, same file,
--   different finding.
-- · **DO-NOT-REFACTOR (CLAUDE.md):** owner-home/fitness collapsing heroes; the meetup stage
--   machine, polling and `confirmHandoff`; the three deliberately-distinct availability
--   predicates. Nothing below touches any of them — `is_slot_available` is only ever *read*.
--
-- ═══ §0d COMPANION, NOT A MIGRATION ═════════════════════════════════════════════════════════
-- `supabase/functions/create-booking-hold/handler.ts` stops taking `runner_id` from the request
-- body (400 `runner_id_not_accepted_here`) and writes `runner_id: null` into both the booking and
-- the `slot_holds` row. Pinned by Deno tests (D-18/D-19), because the SQL harness cannot see a
-- TypeScript branch. **Deploy order: either — measured.** `service_role` retains INSERT (D-20)
-- and `rolbypassrls = true`, so the old function keeps working after this file; the new function
-- is strictly narrower, so it works under the old grants. They close disjoint holes.
--
-- ═══ §0e MUTATION EVIDENCE (CLAUDE.md law — each fix broken in turn, on THIS tree) ═══════════
-- Harness green with this file + suite 146 applied: **655 pass / 0 fail** (baseline before the
-- slice: 641/0 — suite 140's 7 pins leave, suite 146's 21 arrive). Restore after each mutation
-- returns to 655/0. Full detail, including the two contract predictions that came back FALSE,
-- lives in suite 146's header; the summary:
--   M1   §1's revoke deleted, verify kept → the MIGRATION refuses: `0111: client roles still hold
--        INSERT on 2 table-role pair(s): bookings:anon, bookings:authenticated`.
--   M1b  §1's revoke + both verify blocks deleted → 654/1, **red = [D-20] alone.** The effects
--        pins stay green because §1's OTHER layer (the dropped policy) refuses with the SAME
--        sqlstate — 42501 covers both an RLS refusal and a privilege refusal. This is the "fix
--        that worked for the wrong reason" case, and only the catalog pin can see it.
--   M1c  §1's revoke AND its policy drop AND the verify blocks deleted (the true pre-0111 world)
--        → 649/6, red = [D-4, D-5, D-6, D-1, D-3, D-20] — the exploit reproduces verbatim.
--   M2   `service_role` added to §1's revoke → the MIGRATION refuses: `0111 OVER-REVOKE:
--        service_role lost INSERT on bookings`. Verify removed → 651/4, red = [D-20, D-11,
--        119 ren R2, 125 frc F5]: D-11 executes the outage, D-20 names its cause.
--   M3u  §2's revoke narrowed to `insert, delete` (UPDATE verb dropped) → 652/3,
--        red = [D-2, D-9c, D-21]. ⚠ D-2's cron half stayed GREEN — §3's belt caught the repointed
--        series and minted nothing. Under a broken fence the belt is measurably load-bearing.
--   M4   §3's ⓔ ownership re-check deleted → 654/1, red = [D-1b] alone.
--   M6   `grant update (min_fare) on recurring_series to authenticated` added → 653/2,
--        red = [D-21, D-9c] — the widened grant is immediately money (min_fare 9900 → 500000).

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §1  bookings — own the entry point (closes §0 ①, and 0077's forged-draft seeding)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Two independent layers on purpose: the grant is the fence, and dropping the policy means a
-- future re-grant does not silently re-open the hole — it would land on a table with no permissive
-- INSERT policy at all, i.e. still closed.
-- `service_role` (create-booking-hold) and the definers that run as `postgres`
-- (`generate_recurring_bookings`, `session_pay_delegation`, `create_recurring_series`) are
-- unaffected: a table grant to `anon`/`authenticated` is not what any of them writes through.
revoke insert on bookings from anon, authenticated;
drop policy if exists "bookings owner insert" on bookings;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §2  recurring_series — close the client's write surface (closes §0 ② AND ③)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **The column grant is the load-bearing half, not the policy split.** An explicit `with_check`
-- still lets an owner rewrite `dog_id`/`min_fare` on their OWN series — that is §0 ③, and only
-- `grant update (paused)` stops it. The policy split exists so the write surface is *described*
-- correctly in the catalog, not because it closes anything on its own.
--
-- Blast radius EXECUTED, not reasoned (contract §C.2): the client's only write to this table is
-- `.update({ paused: true }).eq('id', seriesId)` (`app/src/lib/api.ts:395`). It filters on `id`
-- and `authenticated` keeps table-wide SELECT, so the WHERE clause still has its required SELECT
-- privilege — the `0091 §E` PostgREST trap does not fire here. D-14 runs it in both the
-- hand-written and the `json_to_record` (PostgREST-emitted PATCH) shapes: 1 row each.
-- Series CREATION stays `create_recurring_series` (definer, party-gated, `0077:32-63`) — the only
-- path that can put fares in a series row, and it copies them from a booking the caller owns.
revoke insert, update, delete on recurring_series from anon, authenticated;
grant update (paused) on recurring_series to authenticated;

drop policy if exists "series owner all" on recurring_series;
create policy "series owner read" on recurring_series for select
  using (owner_id = auth.uid());
-- explicit `with check`, not an inherited USING: a FOR-ALL policy with a NULL with_check is
-- exactly the defect §0 ② names, and it must not be reproduced by omission in its own fix.
create policy "series owner pause" on recurring_series for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §2b slot_holds — F1's SIBLING, closed in the same breath (closes §0 ④)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Marked clearly as what it is: **the same defect on the same migration line** (`0002:102`), named
-- by the reviewer in the same paragraph as ②. It is not scope creep and it is not a new finding —
-- leaving it out would mean this rebuild closed two thirds of one finding. Blast radius measured
-- ZERO: `grep slot_holds app/src app/app` → 0 hits, so the client neither writes nor reads holds.
-- SELECT stays (a read the client does not use today costs nothing and breaks nothing if it
-- appears); the write policy is retired for the same two-layer reason as §1.
revoke insert, update, delete on slot_holds from anon, authenticated;
drop policy if exists "holds self" on slot_holds;
create policy "holds self read" on slot_holds for select
  using (owner_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §3  generate_recurring_bookings — validate at copy time (a SECOND BELT, not the fix)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ SHARED OBJECT: this function is owned by `0080_charge_machine.sql:681-790`. The body below is
-- copied from THERE (not from 0026, which is two revisions behind), byte-faithful, with exactly
-- one addition — the ownership re-check immediately before the insert. Confirmed at write time
-- that no branch has replaced it since. Its REGISTRY row lists it in the shared-objects column.
--
-- ⚠ **Labelled honestly as a belt, because the obvious rationale for it is FALSE.** The tempting
-- justification — "a dog could be deleted or transferred between series creation and generation" —
-- is UNREACHABLE, and was checked rather than assumed:
--   · `recurring_series_dog_id_fkey` has no `ON DELETE` clause → NO ACTION, so deleting a dog with
--     a live series raises a foreign-key violation. A series can never point at a deleted dog.
--   · `dogs owner all` is `for all using (owner_id = auth.uid())` with no separate `with check`,
--     and Postgres reuses USING as the update check when `with check` is absent — so an owner
--     cannot reassign `dogs.owner_id` to anyone else either.
--   · There is no dog-transfer RPC anywhere in the repo (grepped: zero definers write
--     `dogs.owner_id`).
-- So the stale-data case does not exist. What this check IS: **a second belt against a future
-- re-grant.** §2's revoke is the fence; this is what still refuses if a later migration, a support
-- script, or a definer re-opens a write path into `recurring_series`. It costs one `exists` per
-- series row per hour. Keep it labelled that way — never as a fix for a reachable bug.
--
-- ⚠ **`continue`, not `raise` — measured, and recorded so nobody "tightens" it back.** This
-- function is ONE invocation over ONE loop, so an exception unwinds the entire statement: a
-- `raise` here aborts the whole hourly sweep for EVERY owner, the cron records a failure, and the
-- next hour hits the same forged row and dies again. The loop has no `ORDER BY`, so which owners
-- got their bookings before the abort differs run to run — a nondeterministic partial outage
-- caused by one attacker-controlled row. `continue` + `raise warning` is the only shape that is
-- both observable and non-DoSable.
--
-- ⚠ **The fares are NOT re-derived here.** They are a deliberate snapshot of a real, consented
-- quote (`0026:161`, `0077:44-60`); re-deriving would change what a recurring owner is charged,
-- which the money canon puts with Sean. §2's column grant is what makes the snapshot trustworthy.
--
-- Grants: `0026:152` revoked EXECUTE from public/anon/authenticated and `create or replace`
-- preserves ACLs; deliberately NOT re-revoked here, so suite 20's A4 keeps measuring preservation
-- rather than measuring this line (the `0060:101` / 100 W10 doctrine).
-- `set search_path = public, pg_temp` is IN THE BODY (98 H1 law — an ALTER-applied config is reset
-- by `create or replace`).
create or replace function generate_recurring_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record;
  n int := 0;
  v_dow int; v_time text;
  v_kst_now timestamp;
  v_next_date date;
  v_sched timestamptz;
  v_start timestamptz; v_end timestamptz;
  v_runner uuid; v_avail boolean; v_clash boolean;
  v_bid uuid;
  v_live boolean;              -- [0080] cutover switch, read once per sweep
  v_block text;                -- [0080] null | 'debt' | 'no_card'
  v_notified uuid[] := '{}';   -- [0080] owners already told this sweep (ⓓ)
begin
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;

  for s in select * from recurring_series where not paused and dog_id is not null loop
    v_dow := (s.rule->'weekdays'->>0)::int;
    v_time := s.rule->>'time';
    if v_dow is null or v_time is null then continue; end if;

    -- 다음 발생 시각 (KST) — 오늘 포함, 최소 통보 2h 미달이면 다음 주
    v_kst_now := now() at time zone 'Asia/Seoul';
    v_next_date := v_kst_now::date + ((v_dow - extract(dow from v_kst_now)::int + 7) % 7);
    v_sched := (v_next_date::text || ' ' || v_time)::timestamp at time zone 'Asia/Seoul';
    if v_sched < now() + interval '2 hours' then
      v_sched := v_sched + interval '7 days';
    end if;
    if v_sched > now() + interval '72 hours' then continue; end if;

    -- dedup: 같은 시리즈, 같은 KST 날짜에 이미 예약 존재 (첫 예약 포함 — series_id 링크가 가드)
    if exists (
      select 1 from bookings
      where series_id = s.id
        and (scheduled_at at time zone 'Asia/Seoul')::date = (v_sched at time zone 'Asia/Seoul')::date
    ) then continue; end if;

    v_start := v_sched;
    v_end := v_sched + make_interval(mins => (s.km * 8 + 25)::int); -- 실소요 공식 (hold와 동일)

    -- 같은 강아지 라이브 예약 겹침 가드 (create-booking-hold와 동일 로직의 SQL판)
    select exists (
      select 1 from bookings c
      where c.dog_id = s.dog_id
        and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
        and c.scheduled_at < v_end
        and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
    ) into v_clash;
    if v_clash then continue; end if;

    -- 같은 러너 우선 — 시리즈 최근 확정+ 러너, 가용성 재검증 (감사 ① 교훈: 지명은 검증 후)
    v_runner := null;
    select b2.runner_id into v_runner from bookings b2
    where b2.series_id = s.id and b2.runner_id is not null
      and b2.status in ('confirmed','runner_enroute','picked_up','active','completed')
    order by b2.scheduled_at desc limit 1;
    if v_runner is not null then
      begin
        select is_slot_available(v_runner, v_start, v_end) into v_avail;
      exception when others then
        v_avail := false;
      end;
      if not coalesce(v_avail, false) then v_runner := null; end if;
    end if;

    -- ⓑ/ⓒ [0080 §0-ter #3] money gates — the last thing before the insert.
    v_block := null;
    if owner_has_unsettled_charge(s.owner_id) then
      v_block := 'debt';
    elsif v_live and not exists (select 1 from billing_keys bk where bk.profile_id = s.owner_id) then
      v_block := 'no_card';
    end if;
    if v_block is not null then
      if not (s.owner_id = any(v_notified)) then          -- ⓓ once per owner per sweep
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (s.owner_id, 'booking', '반복 예약 일시 중지',
                '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null);
        v_notified := v_notified || s.owner_id;
      end if;
      continue;
    end if;

    -- ⓔ [0111] the series row is a snapshot, and a snapshot can go stale or (before this
    -- migration) be FORGED. Ownership is re-asked at copy time, not trusted from write time.
    -- A silent `continue` would make a skipped series indistinguishable from a series with
    -- nothing due, so say so in the log first — this warning is the ONLY signal that the second
    -- belt fired at all. `continue`, never `raise`: see this file's §3 header.
    if not exists (select 1 from dogs d where d.id = s.dog_id and d.owner_id = s.owner_id)
       or (s.address_id is not null
           and not exists (select 1 from addresses a where a.id = s.address_id and a.owner_id = s.owner_id))
    then
      raise warning 'recurring_series % skipped: dog/address not owned by series owner', s.id;
      continue;
    end if;

    insert into bookings
      (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
       km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values
      (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
       (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
       v_sched, s.km, s.pace_label, s.addons,
       s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
    returning id into v_bid;

    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.owner_id, 'booking', '반복 러닝 예약 생성',
            to_char(v_sched at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
            || ' 러닝이 자동 예약됐어요'
            || case when v_runner is null then ' — 러너를 찾는 중이에요' else '' end,
            v_bid);
    if v_runner is not null then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_runner, 'booking', '지명 러닝 요청',
              '반복 예약 보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', v_bid);
    end if;

    n := n + 1;
  end loop;
  return n;
end $$;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘: 미수금 보호자는 생성 중단(항상), payments_live_since가 설정된
뒤엔 카드 없는 보호자도 중단. 보호자당 스윕 1회만 통지. 그 둘이 없으면 ≤1건 노출 한도가 거짓이 된다
+ [0111] 복사 시점 소유권 재확인 (두 번째 벨트): 시리즈의 dog/address가 시리즈 소유자의 것이 아니면
raise warning 후 continue — 절대 raise 아님 (한 행이 전체 스윕을 영구 중단시킨다)';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY, DO NOT ASSUME — fail closed, the D-20 shape
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Two directions in one block, on purpose. Checking only that clients lost INSERT would let the
-- failure mode that turns a security fix into an OUTAGE — the revoke catching `service_role` —
-- ship silently; the positive controls in the suite detect that only indirectly.
do $$
declare
  v_client text;
  v_missing text;
  v_n int;
begin
  select count(*), string_agg(t || ':' || r, ', ' order by t, r)
    into v_n, v_client
    from unnest(array['bookings', 'recurring_series', 'slot_holds']) t,
         unnest(array['anon', 'authenticated']) r
   where has_table_privilege(r, t, 'INSERT');
  if v_n > 0 then
    raise exception '0111: client roles still hold INSERT on % table-role pair(s): %', v_n, v_client
      using hint = 'the revoke did not take. Two usual causes: the aclitem carries a grantor other than the migration role (a REVOKE only removes grants it issued itself), or a later statement in this file re-granted it.';
  end if;

  select string_agg(t, ', ' order by t)
    into v_missing
    from unnest(array['bookings', 'recurring_series', 'slot_holds']) t
   where not has_table_privilege('service_role', t, 'INSERT');
  if v_missing is not null then
    raise exception '0111 OVER-REVOKE: service_role lost INSERT on %', v_missing
      using hint = 'create-booking-hold writes bookings and slot_holds as service_role. Name only anon and authenticated in every revoke in this file.';
  end if;

  raise notice '0111: anon/authenticated hold INSERT on 0 of bookings/recurring_series/slot_holds; service_role holds it on all three';
end $$;

-- and the column grant is the fence it claims to be: EXACTLY one client column grant survives
-- across the three tables. Anything else means a revoke was written wider or narrower than
-- intended, and the catalog is the only place that shows it before a user does.
do $$
declare
  v_cols text;
  v_n int;
begin
  select count(*), string_agg(c.relname || '.' || a.attname || ':' || pg_get_userbyid(x.grantee) || ':' || x.privilege_type, ', ')
    into v_n, v_cols
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace ns on ns.oid = c.relnamespace,
         lateral aclexplode(a.attacl) x
   where ns.nspname = 'public'
     and c.relname in ('bookings', 'recurring_series', 'slot_holds')
     and (x.grantee = 0 or pg_get_userbyid(x.grantee) in ('anon', 'authenticated'));

  if v_n <> 1 or v_cols is distinct from 'recurring_series.paused:authenticated:UPDATE' then
    raise exception '0111: expected exactly one client column grant (recurring_series.paused:authenticated:UPDATE), found %: %', v_n, coalesce(v_cols, '(none)')
      using hint = 'a second column grant to a client role on these tables is a re-opened write surface. Suite 146 D-21 pins the same property.';
  end if;
  raise notice '0111: client column grants on the three tables = 1 (recurring_series.paused UPDATE authenticated)';
end $$;
