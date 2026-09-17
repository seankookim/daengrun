-- ═══ 0180: two recorded gaps closed — the cron takes the dog lock; the tick row keeps the split ═══
--
-- Both halves are gaps the cold reviews of 0178 and 0179 RECORDED rather than fixed, because each
-- belonged to a file those slices did not own. This file owns them.
--
-- ═══ §A `generate_recurring_bookings` takes `create_booking_hold_tx`'s dog lock ═══
-- 0179 made the same-dog clash guard atomic with the insert it guards — for every caller of
-- `create_booking_hold_tx`. Its header said so and named the one writer outside it: this hourly
-- sweep (0111:317-322, :369) runs its own clash check with NO lock and inserts straight at
-- `matching`/`runner_pending`, so the sweep and an edge hold for the same dog could both pass —
-- as they could before 0179 (cold review 0179 #10). The body below is 0127's VERBATIM (the
-- latest definition, itself a byte-carry of 0119/0111/0080/0026), with exactly three changes, all
-- marked `[0180]`:
--   · `perform pg_advisory_xact_lock(hashtextextended('booking_hold_dog:' || s.dog_id::text, 0))`
--     — the SAME key text 0179 takes — placed after the 72h gate (a series with nothing due takes
--     nothing) and before any read of this dog's bookings (the dedup and the clash guard).
--   · `order by dog_id, id` on the series loop, so two overlapping ticks take locks in one sequence
--     (0117 MINOR-14's rule) — a cycle needs opposite orders, and now there is only one.
--   · `set_config('lock_timeout', '2000', true)` at the top — MINOR-14's OTHER half, the bounded
--     wait (`late_booking_sweep`, 0117:1209). The sweep now WAITS on dog locks, and while it waits
--     it holds every dog lock it already took; a holder stuck past 2 s makes the statement raise
--     `lock_not_available`, this transaction and all its locks release, the edge holds queued
--     behind it proceed, and the next hourly tick retries (pg_cron keeps the failed run in
--     cron.job_run_details). The same bound answers 0117:1202-1206's objection to queueing ticks
--     behind a slow predecessor: an overlapping tick blocked on the leader's first contended dog
--     fails fast instead of queueing for the leader's whole transaction. Measured by hand (211
--     header): a holder at 8 s → the sweep raises at ~2 s; the line deleted → it waits all 8 s.
-- ⚠ THE LOCK IS TRANSACTION-SCOPED AND HELD TO COMMIT — a deliberate departure from the brief's
--   「unlock on every exit path, 0117's exception-arm shape」. 0117's shape is a JOB lock (one sweep
--   at a time, session-scoped, unlocked in the handler so a raise does not wedge the next tick).
--   A per-DOG lock released before commit would reopen the race it closes: an edge hold takes the
--   freed lock, its clash guard reads a snapshot in which this sweep's row is still uncommitted,
--   and both land. `pg_advisory_xact_lock` releases itself at commit or rollback, every exit path
--   included, so there is no unlock to write and no exception arm to keep it in. 211-A1 pins the
--   ABSENCE of a session unlock as a source arm for that reason. Cost: an edge hold for a dog the
--   sweep has already passed waits until the sweep commits — one hourly transaction, seconds
--   (cold review, measured: 1011 due series → 1001 bookings in 472 ms). The other axis is COUNT:
--   every locked dog is one entry in the cluster-wide lock table until commit, and at the harness
--   defaults (max_locks_per_transaction 64 × max_connections 100) one transaction ran out of
--   shared memory at ~12.8k advisory locks — a ceiling thousands of due series away from the
--   pilot's ten; the remedy when it nears is to batch the loop, never to release early.
-- ⚠ Deadlock analysis, stated: the edge takes key-lock → dog-lock and then only waits on the
--   database; this sweep takes dog locks only, in `order by dog_id`; two sweeps take them in the
--   same order. No participant waits on a lock while holding one another participant wants out of
--   order, so no cycle is possible without a 64-bit hash collision across key families.
-- ⚠ `create or replace` of a definer FIRST DEFINED IN 0026, so the ACL is restated below
--   (check-definer-acl law; 0026:152 verbatim). Suites 20 · 116 · 117 · 146 · 154 pin the
--   sweep's behaviour and are unmoved (measured). 161 P4 freezes the WHOLE body by digest, so this
--   slice re-reads its four constants (161:405-417, the suite-update law) — the one shipped suite
--   this file moves. 211 owns the lock; `90_race_check.sh` RG owns the two-connection race.
--
-- ═══ §B `billing_key_dispatch_ticks` keeps the per-cause split ═══
-- 0178 split the revocation worker's `false` into `stale` · `not_processing` · `absent` and taught
-- the handler to count `revoked` · `failed` · `unreported` beside them — in the RESPONSE. The tick
-- table kept only `claimed_count` (0150), so the split lived in the function log and in
-- `net._http_response` for six hours and nowhere durable (cold review 0178 #6, recorded as the
-- open half). Six nullable columns, and the reconciler reads each from the body ONLY when it is
-- there as a JSON integer in int4 range — a float, an out-of-range number or a string is NAMED in
-- `detail` and leaves the six NULL, because a cast that raises inside the loop aborts the whole
-- call and every tick behind it stays `sent` for the 6-hour TTL (cold review 0180 #2, measured:
-- one poisoned body stopped the reconciler, the stale sweep and the prune together). ⚠ NO DEFAULT, a deliberate departure from 「nullable-default-0」: a default
-- would backfill every historical tick with a 0 nobody measured, and a 0 reads as 「measured,
-- none」 where the truth is 「not measured」. NULL means exactly that, and it has three causes: the
-- tick predates the split; the tick was reconciled BEFORE 0180 (the loop re-reads only `sent` /
-- `no_response` ticks, so an answer already on disk is not re-read); the body did not carry the
-- value as an integer. The health view and any reader that sums must say what it does with NULL —
-- ⚠ and no reader ships here: `billing_key_dispatch_health` (0166) still sums `claimed_count`
-- only; the reader is a later slice's. The reconciler also checks that the six sum to `claimed` —
-- every claimed row ends in exactly one bucket (handler.ts) — and when they do not it keeps the
-- numbers AS SENT and names the contradiction in `detail`, rather than trusting either side or
-- averaging; a negative counter is the same contradiction and is named the same way. A body that
-- carries the six and no `claimed` keeps the six and says the arithmetic went unchecked. The
-- worker needs no change: it has written all seven since 0178; this is the table finally keeping
-- what it is told.
-- ⚠ `create or replace` of a definer FIRST DEFINED IN 0150, ACL restated (0150:272-273 verbatim).
--   Suite 181 pins the reconciler's verdicts and is unmoved (measured); 211 owns the split.
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 211's header and the REGISTRY row.

-- ═══ §A ═══
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

  -- [0180] the bounded wait (0117 MINOR-14's other half, late_booking_sweep's value): the dog
  -- locks below can WAIT, and a sweep stalled on one holds every lock it already took. Past 2 s
  -- the statement raises, this transaction and its locks release, and the next tick retries.
  perform set_config('lock_timeout', '2000', true);

  -- [0180] deterministic candidate order: two overlapping ticks take the dog locks below in the
  -- same sequence, so they queue instead of deadlocking (0117 MINOR-14's lesson, applied here).
  for s in select * from recurring_series where not paused and dog_id is not null
           order by dog_id, id loop
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

    -- [0180] THE DOG LOCK — the same key text `create_booking_hold_tx` (0179) takes, so this sweep
    -- and an edge hold for the same dog SERIALIZE: whichever runs second sees the first's committed
    -- row in the clash guard below. Transaction-scoped and held to COMMIT on purpose — releasing it
    -- early (a session lock unlocked in an exception arm, 0117's job-lock shape) would let an edge
    -- hold take the lock, read a snapshot with this sweep's row still uncommitted, and pass: the
    -- exact race this lock exists to close. Taken only for a series with something due (after the
    -- 72h gate), before any read of this dog's bookings. The edge takes key-lock then dog-lock; this
    -- sweep takes only dog locks, in `order by dog_id` sequence, so no lock cycle is possible.
    perform pg_advisory_xact_lock(hashtextextended('booking_hold_dog:' || s.dog_id::text, 0));

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

revoke execute on function generate_recurring_bookings() from public, anon, authenticated;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘: 미수금 보호자는 생성 중단(항상), payments_live_since가 설정된
뒤엔 카드 없는 보호자도 중단. 보호자당 스윕 1회만 통지. 그 둘이 없으면 ≤1건 노출 한도가 거짓이 된다
+ [0111] 복사 시점 소유권 재확인 (두 번째 벨트): 시리즈의 dog/address가 시리즈 소유자의 것이 아니면
raise warning 후 continue — 절대 raise 아님 (한 행이 전체 스윕을 영구 중단시킨다)
+ [0180] 강아지별 xact 어드바이저리 락(create_booking_hold_tx와 같은 키 텍스트) — 스윕과 엣지 홀드가 같은 강아지에서 직렬화, 시리즈는 dog_id 순 (겹치는 틱은 교착 없이 줄을 선다)';

-- ═══ §B ═══
alter table billing_key_dispatch_ticks add column if not exists revoked_count        int;
alter table billing_key_dispatch_ticks add column if not exists failed_count         int;
alter table billing_key_dispatch_ticks add column if not exists stale_count          int;
alter table billing_key_dispatch_ticks add column if not exists not_processing_count int;
alter table billing_key_dispatch_ticks add column if not exists absent_count         int;
alter table billing_key_dispatch_ticks add column if not exists unreported_count     int;
-- one sentence on EVERY column — `\d+` shows one column at a time, and the NULL rule is the design
comment on column billing_key_dispatch_ticks.revoked_count        is '0180: the worker''s count of claimed rows whose key was revoked (0178). NULL = not measured — the tick predates the split, was reconciled before 0180, or the body did not carry the value as an integer; never 0.';
comment on column billing_key_dispatch_ticks.failed_count         is '0180: the worker''s count of claimed rows whose revocation failed (0178). NULL = not measured — the tick predates the split, was reconciled before 0180, or the body did not carry the value as an integer; never 0.';
comment on column billing_key_dispatch_ticks.stale_count          is '0180: the worker''s count of claimed rows whose lease was lost before the report (0178 stale). NULL = not measured — the tick predates the split, was reconciled before 0180, or the body did not carry the value as an integer; never 0.';
comment on column billing_key_dispatch_ticks.not_processing_count is '0180: the worker''s count of late reports on a row no longer processing (0178). NULL = not measured — the tick predates the split, was reconciled before 0180, or the body did not carry the value as an integer; never 0.';
comment on column billing_key_dispatch_ticks.absent_count         is '0180: the worker''s count of reports on a row that was gone (0178). NULL = not measured — the tick predates the split, was reconciled before 0180, or the body did not carry the value as an integer; never 0.';
comment on column billing_key_dispatch_ticks.unreported_count     is '0180: the worker''s count of claimed rows whose outcome could not be recorded (0178). NULL = not measured — the tick predates the split, was reconciled before 0180, or the body did not carry the value as an integer; never 0.';

create or replace function reconcile_billing_key_dispatch_ticks()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  -- A response written seconds after dispatch, against a cron that ticks every 10 minutes. Two
  -- minutes is generous for the first, far inside the second, and well clear of pg_net's own
  -- default request timeout.
  c_bound constant interval := interval '2 minutes';
  -- pg_net's measured retention (`pg_net.ttl = 6 hours`). Past this the answer is gone and cannot
  -- improve, so a tick stops being re-read and keeps whatever verdict it has.
  c_ttl   constant interval := interval '6 hours';
  -- History is kept, but not forever, and NOT symmetrically — see the delete below.
  c_keep  constant interval := interval '30 days';
  r record;
  v_changed int := 0; v_n int;
  v_outcome text; v_claimed int; v_detail text; v_body jsonb;
  -- [0180] the worker's per-cause counters (0178 split them in the response; the table kept only
  -- `claimed`). NULL = 「the body did not carry this number」, never 0.
  v_revoked int; v_failed int; v_stale int; v_not_processing int; v_absent int; v_unreported int;
  -- [0180] the seven counters are read through ONE guarded path: a JSON number is taken only when
  -- it is an integer in int4 range; anything else is NAMED, never cast — a cast that raises here
  -- aborts the whole call, and every tick behind it stays `sent` for the 6-hour TTL (cold review).
  c_fields constant text[] := array['claimed','revoked','failed','stale','not_processing','absent','unreported'];
  v_f text; v_num numeric; v_vals jsonb; v_missing text[];
begin
  for r in
    select distinct on (t.id)
           t.id as tick_id, h.status_code, h.timed_out, h.error_msg, h.content
      from billing_key_dispatch_ticks t
      join net._http_response h on h.id = t.request_id
     where t.outcome in ('sent','no_response')
       and t.request_id is not null
       and t.sent_at > now() - c_ttl
     order by t.id, h.id desc
  loop
    v_claimed := null; v_detail := null; v_body := null;
    v_revoked := null; v_failed := null; v_stale := null; v_not_processing := null; v_absent := null; v_unreported := null;

    -- ⚠ `coalesce(…, false)`: `timed_out` is a nullable boolean and a bare `if r.timed_out` is
    --   NOT TAKEN on NULL, which would silently drop the row into a later arm. The NULL-collapse
    --   law (CLAUDE.md) is about pins; it is the same statement about a branch.
    if coalesce(r.timed_out, false) then
      v_outcome := 'failed';
      v_detail  := 'pg_net timed out — the endpoint did not answer in time';
    elsif r.error_msg is not null then
      v_outcome := 'failed';
      v_detail  := left('transport: ' || r.error_msg, 300);
    elsif r.status_code between 200 and 299 then
      v_outcome := 'accepted';
      begin
        v_body := r.content::jsonb;
      exception when others then
        v_body := null;
      end;
      -- `handle()` returns the handler's object un-wrapped (`_shared/ctx.ts:46`), so the claim
      -- count is top level. A different envelope leaves `claimed_count` NULL and says so in
      -- `detail` — visible, rather than a zero that reads like a measurement.
      if v_body is not null and jsonb_typeof(v_body) = 'object' then
        -- [0180] one guarded read for all seven. `jsonb_typeof = 'number'` guards the READ; the
        -- integer test guards the CAST (1.5, 4.0 and 3000000000 are all JSON numbers, and each
        -- would have raised `invalid input syntax` / `out of range` from a bare `::int`). What is
        -- not taken is listed in `v_missing` with its raw value, so `detail` names what it saw.
        v_vals := '{}'::jsonb; v_missing := '{}';
        foreach v_f in array c_fields loop
          if jsonb_typeof(v_body->v_f) is not distinct from 'number' then
            v_num := (v_body->>v_f)::numeric;
            if v_num = trunc(v_num) and v_num between -2147483648 and 2147483647 then
              v_vals := v_vals || jsonb_build_object(v_f, v_num::int);
            else
              v_missing := array_append(v_missing, v_f || '=' || v_num::text || ' (not an integer)');
            end if;
          elsif v_body ? v_f then
            v_missing := array_append(v_missing, v_f || '=' || coalesce(left(v_body->>v_f, 40), 'null') || ' (not a number)');
          elsif v_f <> 'claimed' then
            v_missing := array_append(v_missing, v_f || ' (absent)');
          end if;
        end loop;
        v_claimed        := (v_vals->>'claimed')::int;
        v_revoked        := (v_vals->>'revoked')::int;
        v_failed         := (v_vals->>'failed')::int;
        v_stale          := (v_vals->>'stale')::int;
        v_not_processing := (v_vals->>'not_processing')::int;
        v_absent         := (v_vals->>'absent')::int;
        v_unreported     := (v_vals->>'unreported')::int;
        if v_revoked is null or v_failed is null or v_stale is null or v_not_processing is null
           or v_absent is null or v_unreported is null then
          -- ALL or NOTHING: a body that carries some of the six is an OLDER worker's shape, and in
          -- that shape `stale` still merges three causes (pre-0178). Storing the three it happens
          -- to name beside three NULLs would put a differently-defined number in the same column.
          -- The detail names each field that was absent or unreadable — a diagnosis the code made,
          -- not a guess about which worker sent it.
          v_revoked := null; v_failed := null; v_stale := null;
          v_not_processing := null; v_absent := null; v_unreported := null;
          v_detail := case when v_claimed is null then '2xx with no claim count in the body; ' else '' end
                      || 'per-cause split incomplete — ' || array_to_string(v_missing, ', ') || ' — counters left NULL';
        elsif v_claimed is null then
          -- the six are measurements the worker sent; kept, and the detail says the arithmetic
          -- could not be checked against a claim count that is not there (or not an integer)
          v_detail := '2xx with no claim count in the body'
                      || case when v_body ? 'claimed' then ' (claimed=' || coalesce(left(v_body->>'claimed', 40), 'null') || ')' else '' end
                      || ' — split kept, unchecked';
        elsif least(v_claimed, v_revoked, v_failed, v_stale, v_not_processing, v_absent, v_unreported) < 0 then
          -- 「minus one key was revoked」 is a contradiction whether or not it happens to balance
          v_detail := 'a counter is negative: claimed ' || v_claimed || ', revoked ' || v_revoked || ', failed ' || v_failed
                      || ', stale ' || v_stale || ', not_processing ' || v_not_processing || ', absent ' || v_absent
                      || ', unreported ' || v_unreported;
        elsif v_claimed <> v_revoked + v_failed + v_stale + v_not_processing + v_absent + v_unreported then
          -- the tick row must never carry a set of numbers that contradict each other in silence:
          -- every claimed row ends in exactly one bucket (handler.ts), so a body where they do not
          -- sum is a worker bug, and the detail names it while the numbers are kept as sent.
          v_detail := 'counters do not balance: claimed ' || v_claimed || ' <> revoked ' || v_revoked
                      || ' + failed ' || v_failed || ' + stale ' || v_stale || ' + not_processing '
                      || v_not_processing || ' + absent ' || v_absent || ' + unreported ' || v_unreported;
        end if;
      else
        v_detail := '2xx with no claim count in the body';
      end if;
    elsif r.status_code in (401, 403, 503) then
      -- 🔴 THE FINDING. 401 = the cron key is wrong, 503 = it is unset (handler.ts:26-27). Either
      --    way the endpoint answered without claiming a single row, and every tick from here on
      --    will do the same until somebody changes a secret.
      v_outcome := 'rejected';
      v_detail  := left('the endpoint refused this caller (' || r.status_code || '): '
                        || coalesce(left(r.content, 200), ''), 300);
    else
      v_outcome := 'failed';
      v_detail  := left('unexpected answer (' || coalesce(r.status_code::text, 'no status') || '): '
                        || coalesce(left(r.content, 200), ''), 300);
    end if;

    update billing_key_dispatch_ticks
       set outcome              = v_outcome,
           status_code          = r.status_code,
           claimed_count        = v_claimed,
           revoked_count        = v_revoked,
           failed_count         = v_failed,
           stale_count          = v_stale,
           not_processing_count = v_not_processing,
           absent_count         = v_absent,
           unreported_count     = v_unreported,
           detail               = v_detail,
           resolved_at          = now()
     where id = r.tick_id;
    v_changed := v_changed + 1;
  end loop;

  -- ⚠ THE THIRD STATE. A tick that sent and was never answered is NOT the same as one that was
  --   refused, and it is not silence either — it says the pg_net worker is not running, or the
  --   request never left. Declared only AFTER the bound, so an in-flight tick is never libelled.
  update billing_key_dispatch_ticks
     set outcome     = 'no_response',
         detail      = 'no pg_net response within ' || c_bound::text
                       || ' — the worker may be down, or the request never left',
         resolved_at = now()
   where outcome = 'sent'
     and sent_at <= now() - c_bound;
  get diagnostics v_n = row_count;
  v_changed := v_changed + v_n;

  -- ⚠ THE PRUNE IS DELIBERATELY ASYMMETRIC AND MUST STAY THAT WAY. Only the two outcomes that
  --   mean 「this tick was fine」 are ever deleted. `rejected`, `failed`, `no_response` and
  --   `deferred` are the evidence — the whole reason this table exists — and a retention rule
  --   that swept them on a timer would re-create the defect on a 30-day delay. A permanently
  --   broken system accumulating 144 rows a day is not this table's problem; it is the finding.
  delete from billing_key_dispatch_ticks
   where outcome in ('idle', 'accepted')
     and sent_at < now() - c_keep;

  return v_changed;
end $$;

revoke execute on function reconcile_billing_key_dispatch_ticks() from public, anon, authenticated;
grant  execute on function reconcile_billing_key_dispatch_ticks() to service_role;

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 211 ═══
do $$
declare
  v_oid oid; v_src text; v_acl text; v_bad text := ''; v_key text; v_n int;
begin
  -- §A
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'generate_recurring_bookings';
  if v_oid is null then raise exception '0180 VERIFY FAILED: NO-FUNCTION(generate_recurring_bookings)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:NO-IN-BODY-SEARCH-PATH'; end if;
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' A:PUBLIC-EXECUTE(acl-is-default)'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:authenticated-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' A:NO-SOURCE';
  else
    v_key := 'pg_advisory_xact_lock(hashtextextended(''booking_hold_dog:'' || s.dog_id::text, 0))';
    if (position(v_key in v_src) > 0) is distinct from true then v_bad := v_bad || ' A:DOG-LOCK-MISSING'; end if;
    -- before any read of this dog's bookings (the dedup exists is the first), before the insert
    if (position(v_key in v_src) > 0 and position(v_key in v_src) < position('series_id = s.id' in v_src)) is distinct from true then v_bad := v_bad || ' A:LOCK-AFTER-DEDUP-READ'; end if;
    if (position(v_key in v_src) > 0 and position(v_key in v_src) < position('insert into bookings' in v_src)) is distinct from true then v_bad := v_bad || ' A:LOCK-AFTER-INSERT'; end if;
    if (v_src ~ 'pg_advisory_unlock') is distinct from false then v_bad := v_bad || ' A:SESSION-UNLOCK-PRESENT(early release reopens the race)'; end if;
    if (v_src ~ 'order by dog_id, id') is distinct from true then v_bad := v_bad || ' A:LOOP-ORDER-MISSING'; end if;
    if (v_src ~ 'set_config\(''lock_timeout'', ''2000'', true\)') is distinct from true then v_bad := v_bad || ' A:NO-LOCK-TIMEOUT(an unbounded wait holds every dog lock already taken)'; end if;
    -- the key text must be byte-identical to the one create_booking_hold_tx takes
    if (select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') ~ 'hashtextextended\(''booking_hold_dog:'' \|\| p_dog::text, 0\)'
          from pg_proc where proname = 'create_booking_hold_tx') is distinct from true then v_bad := v_bad || ' A:0179-KEY-TEXT-DRIFTED'; end if;
  end if;
  -- §B
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_ticks'::regclass and not attisdropped
     and attname in ('revoked_count','failed_count','stale_count','not_processing_count','absent_count','unreported_count');
  if v_n is distinct from 6 then v_bad := v_bad || ' B:COLUMNS(' || v_n || '/6)'; end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_ticks'::regclass and not attisdropped
     and attname in ('revoked_count','failed_count','stale_count','not_processing_count','absent_count','unreported_count') and (atthasdef or attnotnull);
  if v_n is distinct from 0 then v_bad := v_bad || ' B:COLUMN-HAS-DEFAULT-OR-NOT-NULL(' || v_n || ')'; end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then raise exception '0180 VERIFY FAILED: NO-FUNCTION(reconcile_billing_key_dispatch_ticks)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NO-IN-BODY-SEARCH-PATH'; end if;
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' B:PUBLIC-EXECUTE(acl-is-default)'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' B:service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
  else
    if (v_src ~ 'not_processing_count' and v_src ~ 'absent_count' and v_src ~ 'stale_count' and v_src ~ 'unreported_count' and v_src ~ 'revoked_count' and v_src ~ 'failed_count') is distinct from true then v_bad := v_bad || ' B:RECONCILER-DOES-NOT-WRITE-THE-SPLIT'; end if;
    if (v_src ~ 'counters do not balance') is distinct from true then v_bad := v_bad || ' B:NO-BALANCE-CHECK'; end if;
    if (v_src ~ 'a counter is negative') is distinct from true then v_bad := v_bad || ' B:NO-NEGATIVE-CHECK'; end if;
    -- no body field is cast straight to int: a non-integer JSON number would abort the whole call
    if (v_src ~ '\(v_body->>''[a-z_]+''\)::int') is distinct from false then v_bad := v_bad || ' B:UNGUARDED-BODY-CAST'; end if;
  end if;
  if v_bad <> '' then raise exception '0180 VERIFY FAILED:%', v_bad; end if;
end $$;
