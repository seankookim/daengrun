-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0127 — 맹견 gate REMOVAL, Slice A: the behavior comes out; the columns stay for Slice B
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ═══ THE RULING ═════════════════════════════════════════════════════════════════════════════
-- `docs/decisions/2026-08-25-console-rulings.md` — card 15 ("actually nevermind, no need to worry
-- about 맹견, let's accept all breeds") was HELD, deliberately, because the card that prompted it
-- never told Sean WHY the gate existed. A follow-up card carried the legal-review context in plain
-- words (the statutory duties around five breeds, the readiness review's "one genuine build gap",
-- custody handed to a stranger) and asked remove/keep explicitly. **F1, 2026-08-25 04:39:43Z:
-- "Remove it completely."** Informed, and his call to make. The rulings doc's F1 disposition sets
-- the standard this file is written to: *the same care in REMOVAL that the gate got going in — a
-- half-removed gate is worse than either state.*
--
-- ═══ THE CENSUS — asked of production, not inferred (contract §3) ════════════════════════════
-- `select dangerous_status, count(*) from dogs group by 1` against the LINKED project, run by this
-- session on 2026-08-25 before this file was written:
--
--     dangerous_status | count
--     -----------------+-------
--     undeclared       |     3
--
-- ONE row. Zero `declared_dangerous`, zero `declared_none`. So no owner ever answered the question,
-- no dog was ever refused on a live declaration, and **nothing meaningful is being forgotten** by
-- this removal — there is no owner to tell, and contract §3's escalation ("if any row is
-- declared_dangerous, that is a product question for Sean BEFORE the slice lands") does not fire.
-- The columns keep their three undeclared rows regardless; Slice A deletes no data at all.
--
-- ═══ SLICE A / SLICE B — and why the split buys zero deploy-order constraint ══════════════════
-- Slice A (this file): every trigger and function comes out and `generate_recurring_bookings` is
-- restored. **`dogs.dangerous_status` / `dangerous_basis` / `dangerous_declared_at`, the
-- `dogs_dangerous_basis_pairs_with_status` CHECK, and the `dog_dangerous_status` enum all STAY** —
-- unread and unwritten by the server. That is what makes this landing safe in any order against any
-- installed client: an old bundle that still selects or writes those columns keeps working, a new
-- bundle that never mentions them works, and the gate is OFF in both cases, which is the entire
-- content of the ruling. No `drop type` here, and that is deliberate, not an oversight.
--
-- Slice B (its own migration, later): drops the CHECK, the three columns and the enum — and only
-- once ZERO installed bundles reference them, MEASURED across every EAS channel plus the OTA fleet
-- state and recorded in that file's header. Scheduled by that measurement, never by a calendar.
-- Slice B is also where the fixture-value lines in suites 10/113/139/146/149 come out; they are
-- untouched here because the columns they write still exist.
--
-- ═══ WHAT ELSE MOVES IN THE SAME LANDING (not this file) ═════════════════════════════════════
-- Client (ui6): the seven `dangerousRefusalFrom` call sites, `dog.tsx`'s declaration section AND
-- its `danger === 'undeclared'` save guard, `api.ts`'s columns/types/fields, and the deleted
-- `dangerous-copy` module plus its test-chain link. Edge: `create-booking-hold`'s token→409 mapping
-- removed and the function REDEPLOYED with a version readback, and `_test/booking_danger_token_test.ts`
-- deleted (it injects the refusal itself and would otherwise stay green forever, pinning a behavior
-- the server can no longer produce). None of that is in this file; this file is the schema half.
--
-- ═══ SUITE 154 IS RETIRED BY THE HARNESS LINE, NOT BY DELETING THE FILE ══════════════════════
-- `supabase/tests/154_dangerous_breed_suite.sql` pins the gate's behavior. Every one of its pins is
-- now false-by-ruling, so it is UNREGISTERED from `supabase/tests/harness.sh` in this same commit.
-- **The file itself is kept on disk on purpose**: retirement is the harness dropping it, and the
-- file remains the readable record of what the gate did and why (including its own measured
-- mutation battery). Nothing runs it; nothing can accidentally re-arm it. Its replacement is
-- `supabase/tests/161_breed_gate_removal_suite.sql`, which pins this file's absences and the
-- behaviors that must now succeed.
-- ⚠ 154 also creates a test-only trigger (`a_mgn_flip_dog_during_recurring_insert` on `bookings`).
-- Dropping its harness line takes that trigger out of the run too — which is why 161's trigger-count
-- pin can assert an exact number.
--
-- ═══ 🔴 THE RECURRING GENERATOR RETURNS TO 0111's SEMANTICS, DELIBERATELY ═════════════════════
-- §D restores `generate_recurring_bookings` to **0111:272-395 verbatim, plus 0111:396-401's
-- comment**. That is not a guess about what 0119 changed — the two bodies were diffed at authoring
-- and 0119's delta is EXACTLY the belt, in four parts and nothing else:
--   ① three new `declare` lines (`v_gate`, `v_gate_skips`, `v_gate_dogs`)
--   ② the ⓕ pre-check (`dog_custody_gate(s.dog_id)` → count, remember, `continue`)
--   ③ the per-row INSERT wrapped in a subtransaction whose handler catches `sqlstate 'P0001'`,
--      skips ONLY the three custody tokens, and `raise`s everything else
--   ④ the post-loop `raise warning 'recurring custody gate skipped % series; …'`
--      (+ the comment's 0119 stanza)
-- **There is nothing separable to keep in ③.** Its handler re-raises every non-custody error, so
-- once the three tokens can no longer be produced, the wrapper's only remaining effect is a
-- subtransaction per row that catches nothing — machinery whose entire purpose was the gate.
-- Keeping it would leave a reader believing this loop has per-row isolation for the errors that
-- actually happen. It does not, and this file says so out loud:
--
--   🔴 **The restored loop has NO per-row exception isolation** — one failing INSERT aborts the
--   whole hourly sweep, which is 0116 §C's shape ("one unparseable timestamp stopped charge
--   dispatch for EVERYBODY"). That was 0111's state for eight migrations and it is the state this
--   file returns to, ACKNOWLEDGED rather than inherited by accident. 0111's two belts survive
--   intact and are what keep the loop non-DoSable by a row: the money gates and the ⓔ ownership
--   re-check both `continue` + `raise warning` instead of raising. Generic per-row isolation for
--   OTHER error classes is a real question and an UNRULED one — it belongs to its own slice with
--   its own pin, not smuggled in under a removal.
--
-- ⚠ `search_path` is carried EXACTLY as 0111 had it — `set search_path = public, pg_temp` in the
-- function's own body (98 H1's law: an ALTER-applied config is wiped by `create or replace`).
-- Grants are untouched: `0026:152` revoked EXECUTE from public/anon/authenticated and
-- `create or replace` preserves ACLs, which is what suite 20's A4 measures.
--
-- ═══ ORDER IS DISCIPLINE; THE VERIFY BLOCK IS THE NET ════════════════════════════════════════
-- plpgsql bodies carry no dependency records — dropping a function that another body calls succeeds
-- silently and fails at the next insert. So the order below (triggers → trigger functions → the
-- three rule functions → the generator) is hygiene, and the VERIFY block at the bottom is the thing
-- that actually proves the removal is whole. It checks a NAMED inventory, never a name pattern: a
-- `%dangerous%` sweep cannot see `dog_custody_gate` or `dog_custody_refusal_detail`, and that blind
-- spot is exactly the silent half-removal this file is written against.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE SIX TRIGGERS — one explicit statement per trigger, named with its own table
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- `create or replace` cannot drop a trigger, and a trigger left behind is not inert: its function
-- would be gone, so it does not "just stop refusing" — every write to its table would fail. The
-- highest-severity case is ⓔ below.
--
-- ⓐ/ⓑ the two custody triggers on `bookings` (0119 §D — INSERT and the outward UPDATE arm)
drop trigger if exists bookings_dangerous_dog on bookings;
drop trigger if exists bookings_dangerous_dog_move on bookings;

-- ⓒ/ⓓ the two custody triggers on `session_dogs` (0119 §D — the club application path)
drop trigger if exists session_dogs_dangerous_dog on session_dogs;
drop trigger if exists session_dogs_dangerous_dog_move on session_dogs;

-- ⓔ 🔴 THE DECLARATION TRIGGER ON `dogs` — the one a four-trigger inventory misses, and the one
--    that does the most damage if it survives. It reads `new.dangerous_declared_at` and fires on
--    EVERY insert and update of `dogs`, not only on 맹견 rows. Left behind after its function is
--    dropped, it bricks every dog write in the product — profile edits, name changes, the onboarding
--    insert. Slice B (which drops the column it reads) would brick them a second, different way.
drop trigger if exists dogs_dangerous_declaration on dogs;

-- ⓕ the DELETE latch on `dogs` (0119 §F) — it refused an app-role delete of a declared dog
drop trigger if exists dogs_dangerous_delete on dogs;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  THE THREE TRIGGER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Dropped after their triggers, so no window exists in which a trigger points at a missing function.
-- (Inside one transaction that window is invisible anyway; the order is for the reader.)
drop function if exists _guard_dangerous_dog_custody();
drop function if exists _guard_dog_dangerous_declaration();
drop function if exists _guard_dangerous_dog_delete();


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  THE RULE ITSELF — and the two functions whose names carry no 「dangerous」 at all
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- `dog_custody_gate` and `dog_custody_refusal_detail` are the reason the VERIFY block is a named
-- inventory: a reviewer sweeping for `%dangerous%` finds neither, declares the removal complete,
-- and leaves a live definer that answers "is that stranger's dog a 맹견" to anyone who is ever
-- granted EXECUTE. The breed screen goes with them — it exists only to feed the gate.
drop function if exists dog_custody_gate(uuid);
drop function if exists dog_custody_refusal_detail(text);
drop function if exists _breed_reads_as_dangerous(text);


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  `generate_recurring_bookings` RESTORED — 0111:272-395 verbatim
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- See the header's 🔴 note: this is a verbatim restoration, no-per-row-isolation included, and that
-- is the deliberate decision rather than a side effect. The body below is byte-for-byte 0111's,
-- with 0111's own comments left in place (they explain belts that are still live).
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

-- 0111:396-401's comment, restored with the body it describes. The 0119 stanza is gone because the
-- belt it described is gone; a comment that still claims a custody belt is a lie the next reader
-- would act on (`pg_description` is checked in VERIFY for exactly that reason).
comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘: 미수금 보호자는 생성 중단(항상), payments_live_since가 설정된
뒤엔 카드 없는 보호자도 중단. 보호자당 스윕 1회만 통지. 그 둘이 없으면 ≤1건 노출 한도가 거짓이 된다
+ [0111] 복사 시점 소유권 재확인 (두 번째 벨트): 시리즈의 dog/address가 시리즈 소유자의 것이 아니면
raise warning 후 continue — 절대 raise 아님 (한 행이 전체 스윕을 영구 중단시킨다)';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY, DO NOT ASSUME — a NAMED inventory, in both directions
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Both directions, because the two failure modes are opposite and only one of them is loud:
--   · UNDER-removal (a trigger or a caller survives) is silent until the next write on that table,
--     and for `dogs_dangerous_declaration` that write is every dog profile save in the product.
--   · OVER-removal (the generator restored wrong, an unrelated trigger dropped, the pair-CHECK
--     taken out early) is a Slice-B change smuggled into Slice A, and the CHECK is what stops the
--     three surviving columns from drifting into an inconsistent pair while they wait.
-- Names are spelled out one by one. A `%dangerous%` pattern would pass while `dog_custody_gate`,
-- `dog_custody_refusal_detail` and `_breed_reads_as_dangerous` sit untouched — the exact
-- half-removal this block exists to make impossible.
do $$
declare
  v_left  text;
  v_def   text;
  v_cmt   text;
  v_n     int;
begin
  -- ── ① the SIX triggers, by exact name, each paired with the table it sat on ────────────────
  select string_agg(x.tbl || '.' || x.trg, ', ' order by x.tbl, x.trg) into v_left
    from (values ('bookings',     'bookings_dangerous_dog'),
                 ('bookings',     'bookings_dangerous_dog_move'),
                 ('session_dogs', 'session_dogs_dangerous_dog'),
                 ('session_dogs', 'session_dogs_dangerous_dog_move'),
                 ('dogs',         'dogs_dangerous_declaration'),
                 ('dogs',         'dogs_dangerous_delete')) as x(tbl, trg)
   where exists (select 1
                   from pg_trigger t
                   join pg_class c on c.oid = t.tgrelid
                  where not t.tgisinternal
                    and c.relnamespace = 'public'::regnamespace
                    and c.relname = x.tbl
                    and t.tgname  = x.trg);
  if v_left is not null then
    raise exception '0127: 0119 trigger(s) survived the removal: %', v_left
      using hint = 'a surviving trigger whose function is gone does not stop refusing — it fails every write on its table';
  end if;

  -- ── ② the SIX functions, by exact name (every overload, not just the known signature) ───────
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_left
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_guard_dangerous_dog_custody',
                       '_guard_dog_dangerous_declaration',
                       '_guard_dangerous_dog_delete',
                       'dog_custody_gate',
                       'dog_custody_refusal_detail',
                       '_breed_reads_as_dangerous');
  if v_left is not null then
    raise exception '0127: 0119 function(s) survived the removal: %', v_left;
  end if;

  -- ── ③ the restored generator contains none of the belt — and still contains 0111's own belts ──
  -- The negative half alone would pass on an empty stub, so the positive half names two things
  -- that MUST have come back with the restoration: 0111 ⓔ's ownership warning literal and 0080's
  -- money gate. Together they distinguish "0119's delta removed" from "body destroyed".
  select pg_get_functiondef('generate_recurring_bookings()'::regprocedure) into v_def;
  if v_def is null then
    raise exception '0127: generate_recurring_bookings() is missing after the restoration';
  end if;
  if v_def like '%dog_custody_gate%'
     or v_def like '%dog_dangerous_%'
     or v_def like '%recurring custody gate skipped%' then      -- the belt's warning literal
    raise exception '0127: generate_recurring_bookings still carries the 0119 custody belt'
      using hint = 'the restoration must be 0111:272-395 verbatim — no ⓕ pre-check, no token subtransaction, no post-loop warning';
  end if;
  if v_def not like '%dog/address not owned by series owner%'
     or v_def not like '%owner_has_unsettled_charge%' then
    raise exception '0127 OVER-REACH: the restored generator lost a belt that predates 0119'
      using hint = '0111 ⓔ ownership re-check and the 0080 money gates are NOT part of the 맹견 removal';
  end if;
  -- and its search_path is in the BODY, where `create or replace` cannot wipe it (98 H1)
  if not exists (select 1 from pg_proc p
                  where p.oid = 'generate_recurring_bookings()'::regprocedure::oid
                    and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '0127: generate_recurring_bookings lost its in-body search_path';
  end if;

  -- ── ④ schema-wide: NOBODY calls the dropped rule, anywhere ─────────────────────────────────
  -- The dangling-caller check. plpgsql bodies carry no dependency records, so a caller left behind
  -- is invisible to the catalog and fails at the next execution — a cron at 07 past the hour, or a
  -- club application, long after this migration is green. `prosrc` is the only place it shows.
  select string_agg(p.proname, ', ' order by p.proname) into v_left
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.prosrc like '%dog_custody_gate%'
       or p.prosrc like '%dog_custody_refusal_detail%'
       or p.prosrc like '%_breed_reads_as_dangerous%');
  if v_left is not null then
    raise exception '0127: function(s) still call a dropped 맹견 object: %', v_left;
  end if;

  -- ── ⑤ trigger-count inventory — MEASURED, not asserted ─────────────────────────────────────
  -- Counted two ways at authoring and they agreed name-for-name:
  --   (a) by reading the whole migration chain 0001→0126 (every `create trigger` AND
  --       `create constraint trigger` on these three tables, minus every `drop trigger` that was
  --       not followed by a re-create — `club_v2_axes_poke` is the one that only a
  --       constraint-trigger-aware count finds: 0041:15 drops it and 0041:22 re-creates it as a
  --       DEFERRABLE constraint trigger);
  --   (b) against the LINKED project's live `pg_trigger` on 2026-08-25: bookings 16, dogs 4,
  --       session_dogs 3 — identical name lists.
  -- Minus the six this file drops: bookings 16-2 = 14 · dogs 4-2 = 2 · session_dogs 3-2 = 1.
  -- The two survivors on `dogs` are `t_dogs_touch` (0002) and `club_dog_materiality` (0048); the
  -- one on `session_dogs` is `club_v1_axes_sync` (0040). This pin is what catches "dropped one too
  -- many" as loudly as it catches "left one behind".
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'bookings';
  if v_n <> 14 then
    raise exception '0127: bookings should carry 14 non-internal triggers after this file, found %', v_n;
  end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'dogs';
  if v_n <> 2 then
    raise exception '0127: dogs should carry 2 non-internal triggers after this file (t_dogs_touch, club_dog_materiality), found %', v_n;
  end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'session_dogs';
  if v_n <> 1 then
    raise exception '0127: session_dogs should carry 1 non-internal trigger after this file (club_v1_axes_sync), found %', v_n;
  end if;

  -- ── ⑥ the generator's COMMENT no longer claims a belt it does not have ─────────────────────
  select obj_description('generate_recurring_bookings()'::regprocedure, 'pg_proc') into v_cmt;
  if v_cmt is null then
    raise exception '0127: generate_recurring_bookings lost its comment';
  end if;
  if v_cmt like '%0119%' or v_cmt like '%custody gate%' then
    raise exception '0127: the generator comment still describes the 0119 custody belt';
  end if;
  if v_cmt not like '%[0111]%' then
    raise exception '0127: the generator comment is not 0111:396-401 restored';
  end if;

  -- ── ⑦ SLICE BOUNDARY — what Slice A must NOT have touched ─────────────────────────────────
  -- Present here, absent in Slice B. If a later reviewer finds this block asserting absence, the
  -- slices got merged and an old installed bundle is writing to columns that no longer exist.
  if not exists (select 1 from pg_constraint
                  where conrelid = 'dogs'::regclass
                    and conname = 'dogs_dangerous_basis_pairs_with_status') then
    raise exception '0127 OVER-REACH: the pair CHECK was dropped — that is Slice B, and the columns it constrains are still here';
  end if;
  select count(*) into v_n from information_schema.columns
   where table_schema = 'public' and table_name = 'dogs'
     and column_name in ('dangerous_status', 'dangerous_basis', 'dangerous_declared_at');
  if v_n <> 3 then
    raise exception '0127 OVER-REACH: expected all 3 declaration columns to survive Slice A, found %', v_n;
  end if;
  if not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace
                   and typname = 'dog_dangerous_status') then
    raise exception '0127 OVER-REACH: the dog_dangerous_status enum was dropped — that is Slice B';
  end if;

  raise notice '0127: 6 triggers + 6 functions absent by name; no caller anywhere in public; generator restored to 0111 with its belts intact; trigger counts 14/2/1; columns, pair CHECK and enum held for Slice B';
end $$;
