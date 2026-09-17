-- ═══ 211 — 0180's two closed gaps — 0180-A1…A2 (the cron's dog lock) · 0180-B1…B4 (the tick split), tag `cdl` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS:
--   §A the hourly recurring sweep takes, for every dog it is about to write, the SAME advisory lock
--      `create_booking_hold_tx` (0179) takes — transaction-scoped, held to commit — before it reads
--      that dog's bookings, so the sweep and an edge hold for one dog serialize (cold review 0179
--      #10, recorded there, closed here).
--   §B a reconciled tick row keeps the worker's per-cause split (0178) — six counters, NULL when the
--      body did not carry them, and a body whose counters do not sum to `claimed` is kept as sent
--      and named in `detail` (cold review 0178 #6, recorded there, closed here).
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE:
--   · the sweep's own behaviour (dedup, the 72h window, the money gates, nomination, the copy-time
--     belt) — 20 · 116 · 117 · 146 · 154 own it, the body is 0127's plus three marked lines, and
--     they are unmoved (measured). 161 P4 freezes the WHOLE body by digest and is the one shipped
--     suite this slice moves — its four constants re-read (161:405-417), with 0180 named as why.
--   · the reconciler's verdicts (accepted / rejected / failed / no_response, the prune) — 181.
--   · the two-connection race (sweep transaction open, edge hold arriving) — PINNED, but not
--     here: `90_race_check.sh` RG runs it with two psql processes (the RD template), and it is
--     the pin that reddens when the lock is deleted or released early. A2's single-session
--     shadow is what THIS file can see: the lock is HELD after the sweep, and a hold for that dog
--     in the same session meets the sweep's row in the clash guard — A2 cannot see an early
--     unlock (measured: under a session lock it still answers dog_slot_clash); RG can.
--   · the bounded wait (`lock_timeout`) as BEHAVIOUR — measured by hand (below), pinned as source
--     in A1: a suite arm that waits 2 s on every run is a cost the harness does not pay.
--
-- ─── MUTATION MAP — measured 2026-09-18, not predicted (numbers in the REGISTRY row) ───
--   Lab: an md5-identical copy of 0180, every plant `&&`-chained to its run, the control observed
--   first (1269 / 0). 「demoted」 = 0180's own VERIFY raise turned into a notice so the SUITE is what
--   is measured; 「un-demoted」 = the shipped file, where the VERIFY aborts the apply before any
--   suite runs. P4 = 161's whole-body md5 of the sweep, which reddens on ANY change to the body and
--   names nothing — the cdl arm beside it is the one that names the property. RG = the two-process
--   race in `90_race_check.sh`; its red carries the row count.
--   (i)    the dog lock deleted from the sweep        → A1 (강아지 락 없음 · 락이 dedup 읽기 뒤 · 락이
--          insert 뒤 · 키 텍스트 다름) + A2 (dog-lock-not-held-after-the-sweep) + RG (rows=2
--          clash=0) + P4; un-demoted the apply ABORTS (A:DOG-LOCK-MISSING …). The hole REPRODUCES.
--   (ii)   `order by dog_id, id` removed              → A1 (루프 순서 없음) + P4.
--   (iii)  a SESSION lock (`pg_advisory_lock`) with `pg_advisory_unlock` right after the insert —
--          the brief's original shape                 → A1 (… 세션 unlock 있음) + A2 (nothing held
--          after the sweep) + RG (rows=2 clash=0 — the unlock lands BEFORE the sweep's commit, so
--          the hold's clash guard cannot see the row) + P4; un-demoted the apply ABORTS. This is
--          why the lock is transaction-scoped, and why A1 pins the ABSENCE of a session unlock.
--   (iv)   the key text drifted (`booking_hold_dogs:`) → A1 (두 함수의 락 키 텍스트가 다르다) + A2
--          (the key the sweep holds is not the key 0179 waits on) + RG (rows=2) + P4.
--   (v)    the balance check disabled (`elsif false`) → B3 (detail=NULL) — demoted and un-demoted
--          alike: the VERIFY reads the source for the detail STRING, which this plant leaves in
--          place, so B3 is the property's only owner.
--   (vi)   all-or-nothing removed (a partial split stored as found) → B2 (partial-split-stored-as-
--          if-complete) + B5 (a-float-body-stored-a-split).
--   (vii)  `stale_count … default 0`                  → B2 (an-idle-tick-has-counters ·
--          columns-with-default-or-not-null=1); un-demoted the apply ABORTS.
--   (viii) the reconciler writes NULL for three of the six → B1 (split=1/1/NULL/NULL/NULL/0
--          does-not-balance) + B3 (numbers-not-kept-as-sent) + B6 (six-discarded-with-claimed).
--   (ix)   `lock_timeout` deleted                      → A1 (lock_timeout 없음) + P4; un-demoted the
--          apply ABORTS (A:NO-LOCK-TIMEOUT). By hand (below): the sweep waits the holder out.
--   (x)    the seven reads 「tidied」 back to bare `(v_body->>'x')::int` → B5 (reconciler-RAISED
--          [invalid input syntax for type integer: "1.5"]) + B1 + B2 + B3 + B6 (nothing written —
--          every tick in the call is still `sent`); un-demoted the apply ABORTS
--          (B:UNGUARDED-BODY-CAST). The cold review's wedge, reproduced.
--   (xi)   the negative check disabled (`elsif false`) → B6 (negative-detail=NULL).
--   (xii)  six good numbers discarded when `claimed` is missing → B6 (six-discarded-with-claimed).
--   BY HAND, two connections — the race is RG's now; the bounded wait is not a pin:
--     sweep-vs-hold (RG's shape, run before RG existed): shipped → the hold blocks on the dog lock
--       (statement timeout at 1.5 s), after commit `dog_slot_clash`, 1 row; (i) and (iii) → the
--       hold lands beside the sweep's row, 2 rows.
--     lock_timeout: a second connection holds ONE dog lock for 8 s and the sweep (with a due series
--       for that dog) is called: shipped → `canceling statement due to lock timeout` at 2 s, 0 rows,
--       the transaction and its locks gone; (ix) → the sweep waits ~7 s (the holder's remaining
--       time) and then writes the row. Not pinned: a suite arm that waits 2 s on every run is a
--       cost the harness does not pay; A1 + VERIFY pin the line.
--   NAMED GAP (the cold review's M2): the lock's ORDER relative to the reads is held by source arms
--   alone (A1 + VERIFY) — A2 asserts the lock is held, not where it was taken; the lock moved after
--   the dedup read reddens A1 only.
--
-- ─── FIXTURE NOTES ───
--  ① The series is made the way the product makes one — `create_recurring_series(<confirmed
--     booking>)` as the owner — then the original booking is moved a week back (20 G2's trick) so
--     the next occurrence falls inside the 72h window and is not deduped. A2's first arm asserts
--     the sweep actually produced a row (a precondition, so a green cannot be an empty world).
--  ② `pg_locks` is read for THIS backend: a 64-bit advisory key `k` shows as classid = k >> 32,
--     objid = k & 0xFFFFFFFF, objsubid = 1. The suite's `do` block is one transaction, so the
--     xact lock the sweep took is still held when the arm reads it — which is the property.
--  ③ §B's ticks are seeded exactly as 181 seeds them (a `sent` tick + a `net._http_response` row
--     by id), with request ids in the 812xxx range so the two suites' rows never meet.
set client_min_messages = warning;

do $$
declare
  o uuid; d uuid; d2 uuid; rt uuid; bid uuid; sid uuid;
  next_sched timestamptz;
  v_key bigint; v_key2 bigint;
  v_n int; v_n2 int; v_bad text; v_msg text; v_src text; v_src2 text; v_acl text; v_oid oid; j jsonb;
  t1 uuid; t2 uuid; t3 uuid; t4 uuid; t5 uuid; t6 uuid; t7 uuid; v_err text;
  r record;
begin
  -- ---------- §A fixture (①) ----------
  o := t_user('cdl_owner', 'owner'); d := t_dog(o, 'cdl-dog'); d2 := t_dog(o, 'cdl-dog-2'); rt := t_route('cdl 코스');
  next_sched := date_trunc('hour', now()) + interval '26 hours';
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, d, null, rt, 'confirmed', next_sched, 5.0, 9900, 15000, 0, 24900, 9900) returning id into bid;
  perform set_config('request.jwt.claim.sub', o::text, true);
  sid := create_recurring_series(bid);
  perform set_config('request.jwt.claim.sub', '', true);
  -- the original moves a week back, so this week's occurrence is due and not deduped; its status
  -- stays `confirmed` (20 G2's note: the transition guard refuses confirmed → completed directly)
  update bookings set scheduled_at = next_sched - interval '7 days' where id = bid;
  v_key  := hashtextextended('booking_hold_dog:' || d::text, 0);
  v_key2 := hashtextextended('booking_hold_dog:' || d2::text, 0);

  -- ---------- [0180-A1] the lock in the DEPLOYED source, byte-for-byte 0179's key, before any read, never unlocked early ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'generate_recurring_bookings';
  if v_oid is null then v_bad := ' NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' ACL 기본값'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' authenticated 실행 가능'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src2 from pg_proc where proname = 'create_booking_hold_tx';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(sweep)';
    elsif v_src2 is null then v_bad := v_bad || ' NO-SOURCE(create_booking_hold_tx)';
    else
      if (position('pg_advisory_xact_lock(hashtextextended(''booking_hold_dog:'' || s.dog_id::text, 0))' in v_src) > 0) is distinct from true then v_bad := v_bad || ' 강아지 락 없음'; end if;
      if (position('pg_advisory_xact_lock' in v_src) > 0 and position('pg_advisory_xact_lock' in v_src) < position('series_id = s.id' in v_src)) is distinct from true then v_bad := v_bad || ' 락이 dedup 읽기 뒤'; end if;
      if (position('pg_advisory_xact_lock' in v_src) > 0 and position('pg_advisory_xact_lock' in v_src) < position('insert into bookings' in v_src)) is distinct from true then v_bad := v_bad || ' 락이 insert 뒤'; end if;
      if (v_src ~ 'pg_advisory_unlock') is distinct from false then v_bad := v_bad || ' 세션 unlock 있음(조기 해제 = 레이스 재개)'; end if;
      if (v_src ~ 'order by dog_id, id') is distinct from true then v_bad := v_bad || ' 루프 순서 없음'; end if;
      if (v_src ~ 'set_config\(''lock_timeout'', ''2000'', true\)') is distinct from true then v_bad := v_bad || ' lock_timeout 없음(대기 무한 — 이미 잡은 강아지 락을 전부 쥔 채)'; end if;
      -- the two functions must spell the SAME key family: same prefix literal, same hash, same seed
      if (v_src ~ 'hashtextextended\(''booking_hold_dog:'' \|\| s\.dog_id::text, 0\)' and v_src2 ~ 'hashtextextended\(''booking_hold_dog:'' \|\| p_dog::text, 0\)') is distinct from true then v_bad := v_bad || ' 두 함수의 락 키 텍스트가 다르다'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('cdl','0180-A1 스윕 소스(주석 제거)에 0179와 같은 텍스트의 강아지 xact 락이 dedup 읽기·insert 앞에 있고, 세션 unlock 없음, 루프는 dog_id 순, lock_timeout 2s; definer·search_path·ACL 그대로');
  else v_msg := v_bad; call _fail('cdl','0180-A1 source', v_msg); end if;

  -- ---------- [0180-A2] the lock is TAKEN for the dog the sweep wrote, not for a dog it did not, and it is still held ----------
  v_bad := '';
  select count(*) into v_n from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1 and l.classid = ((v_key >> 32) & 4294967295)::oid and l.objid = (v_key & 4294967295)::oid;
  if v_n <> 0 then v_bad := v_bad || ' lock-held-BEFORE-the-sweep(' || v_n || ')'; end if;
  begin
    select generate_recurring_bookings() into v_n2;
  exception when others then v_n2 := -1; v_bad := v_bad || ' sweep-RAISED [' || sqlerrm || ']';
  end;
  -- ≥ 1, not = 1: the sweep is GLOBAL, so a due series left by an earlier suite adds to this count
  -- without touching the property (cold review 0180 #9); the series-scoped count is asserted below
  if v_n2 < 1 then v_bad := v_bad || ' sweep-generated=' || v_n2 || ' (expected ≥ 1 — the fixture is due; if 0 the pin has no subject)'; end if;
  select count(*) into v_n from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1 and l.classid = ((v_key >> 32) & 4294967295)::oid and l.objid = (v_key & 4294967295)::oid;
  if v_n <> 1 then v_bad := v_bad || ' dog-lock-not-held-after-the-sweep(' || v_n || ')'; end if;
  select count(*) into v_n from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1 and l.classid = ((v_key2 >> 32) & 4294967295)::oid and l.objid = (v_key2 & 4294967295)::oid;
  if v_n <> 0 then v_bad := v_bad || ' CONTROL: a dog with no series got a lock(' || v_n || ')'; end if;
  -- the single-session shadow of the race: a hold for THIS dog at the generated time meets the
  -- sweep's row in the clash guard; the other dog at the same time is free
  begin
    perform create_booking_hold_tx(o, d, next_sched, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900, true, gen_random_uuid());
    v_bad := v_bad || ' a-hold-for-the-swept-dog-PASSED';
  exception when others then
    if sqlerrm <> 'dog_slot_clash' then v_bad := v_bad || ' swept-dog hold: [' || sqlerrm || ']'; end if;
  end;
  begin
    j := create_booking_hold_tx(o, d2, next_sched, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900, true, gen_random_uuid());
    if (j->>'booking_id') is null then v_bad := v_bad || ' other-dog hold answered no id'; end if;
  exception when others then v_bad := v_bad || ' other-dog hold: [' || sqlerrm || ']';
  end;
  select count(*) into v_n from bookings where dog_id = d and series_id = sid and status = 'matching';
  if v_n <> 1 then v_bad := v_bad || ' swept-row-count=' || v_n; end if;
  if v_bad = '' then call _pass('cdl','0180-A2 스윕이 쓴 강아지의 xact 락이 잡혀 있고(그 전엔 없고, 시리즈 없는 강아지는 없음), 같은 세션의 그 강아지 홀드는 dog_slot_clash, 다른 강아지는 자유');
  else v_msg := v_bad; call _fail('cdl','0180-A2 lock-held', v_msg); end if;

  -- ---------- §B fixture (③): four ticks, four bodies ----------
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 4, 812001, now() - interval '1 minute') returning id into t1;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (812001, 200, '{"claimed":4,"revoked":1,"failed":1,"stale":1,"not_processing":1,"absent":0,"unreported":0}', false, now());
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 2, 812002, now() - interval '1 minute') returning id into t2;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (812002, 200, '{"claimed":2,"revoked":2,"failed":0,"stale":0}', false, now());          -- an OLD worker's body: no split
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, 812003, now() - interval '1 minute') returning id into t3;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (812003, 200, '{"claimed":3,"revoked":1,"failed":0,"stale":1,"not_processing":0,"absent":0,"unreported":0}', false, now());   -- does not balance (3 <> 2)
  insert into billing_key_dispatch_ticks (outcome, due_count) values ('idle', 0) returning id into t4;   -- a tick that never sent: no columns given
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 4, 812005, now() - interval '1 minute') returning id into t5;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (812005, 200, '{"claimed":4,"revoked":1.5,"failed":1,"stale":1,"not_processing":0,"absent":0,"unreported":0}', false, now());   -- a float where an integer belongs
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 0, 812006, now() - interval '1 minute') returning id into t6;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (812006, 200, '{"claimed":0,"revoked":-1,"failed":1,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());   -- balances, and is nonsense
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 2, 812007, now() - interval '1 minute') returning id into t7;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (812007, 200, '{"revoked":1,"failed":1,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());   -- the six, no claimed
  -- one call for all seven ticks, in a sub-block so a raise is NAMED by B5 rather than aborting the suite
  v_err := null;
  begin
    perform reconcile_billing_key_dispatch_ticks();
  exception when others then v_err := sqlerrm;
  end;

  -- ---------- [0180-B1] a reconciled tick keeps all six counters from the body, and they balance ----------
  v_bad := '';
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'accepted' then v_bad := v_bad || ' outcome=' || coalesce(r.outcome,'NULL'); end if;
  if r.claimed_count is distinct from 4 then v_bad := v_bad || ' claimed=' || coalesce(r.claimed_count::text,'NULL'); end if;
  if r.revoked_count is distinct from 1 or r.failed_count is distinct from 1 or r.stale_count is distinct from 1
     or r.not_processing_count is distinct from 1 or r.absent_count is distinct from 0 or r.unreported_count is distinct from 0 then
    v_bad := v_bad || ' split=' || coalesce(r.revoked_count::text,'NULL') || '/' || coalesce(r.failed_count::text,'NULL') || '/' || coalesce(r.stale_count::text,'NULL') || '/' || coalesce(r.not_processing_count::text,'NULL') || '/' || coalesce(r.absent_count::text,'NULL') || '/' || coalesce(r.unreported_count::text,'NULL');
  end if;
  if r.detail is not null then v_bad := v_bad || ' detail-on-a-clean-tick=' || left(r.detail, 60); end if;
  if (r.claimed_count = r.revoked_count + r.failed_count + r.stale_count + r.not_processing_count + r.absent_count + r.unreported_count) is distinct from true then v_bad := v_bad || ' does-not-balance'; end if;
  if v_bad = '' then call _pass('cdl','0180-B1 2xx 본문의 일곱 숫자가 틱 행에 남는다 — revoked·failed·stale·not_processing·absent·unreported, 합이 claimed와 같고 detail 없음');
  else v_msg := v_bad; call _fail('cdl','0180-B1 split-kept', v_msg); end if;

  -- ---------- [0180-B2] a body WITHOUT the split leaves the six NULL — not 0 — and says so ----------
  v_bad := '';
  select * into r from billing_key_dispatch_ticks where id = t2;
  if r.outcome is distinct from 'accepted' or r.claimed_count is distinct from 2 then v_bad := v_bad || ' outcome/claimed=' || coalesce(r.outcome,'NULL') || '/' || coalesce(r.claimed_count::text,'NULL'); end if;
  if r.not_processing_count is not null or r.absent_count is not null or r.unreported_count is not null then v_bad := v_bad || ' a-missing-counter-became-a-number'; end if;
  if r.revoked_count is not null or r.stale_count is not null or r.failed_count is not null then v_bad := v_bad || ' partial-split-stored-as-if-complete'; end if;
  -- the detail names the three fields the body lacked — what the code measured, not a guess at the worker
  if (r.detail ~ 'per-cause split incomplete' and r.detail ~ 'not_processing \(absent\)' and r.detail ~ 'absent \(absent\)' and r.detail ~ 'unreported \(absent\)') is distinct from true then v_bad := v_bad || ' detail=' || coalesce(left(r.detail,100),'NULL'); end if;
  -- and a tick that never carried a body has NULLs, because the columns have NO default
  select * into r from billing_key_dispatch_ticks where id = t4;
  if r.revoked_count is not null or r.failed_count is not null or r.stale_count is not null or r.not_processing_count is not null or r.absent_count is not null or r.unreported_count is not null then v_bad := v_bad || ' an-idle-tick-has-counters'; end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_ticks'::regclass and not attisdropped
     and attname in ('revoked_count','failed_count','stale_count','not_processing_count','absent_count','unreported_count') and (atthasdef or attnotnull);
  if v_n <> 0 then v_bad := v_bad || ' columns-with-default-or-not-null=' || v_n; end if;
  if v_bad = '' then call _pass('cdl','0180-B2 분할 없는 옛 본문 ⇒ 여섯 열 전부 NULL(0이 아니다) + detail이 빠진 세 필드를 이름 짓는다; 보내지 않은 틱도 NULL — 열에 기본값이 없다');
  else v_msg := v_bad; call _fail('cdl','0180-B2 null-not-zero', v_msg); end if;

  -- ---------- [0180-B3] a body that does not balance is kept AS SENT and named in detail ----------
  v_bad := '';
  select * into r from billing_key_dispatch_ticks where id = t3;
  if r.claimed_count is distinct from 3 or r.revoked_count is distinct from 1 or r.stale_count is distinct from 1 or r.failed_count is distinct from 0 then v_bad := v_bad || ' numbers-not-kept-as-sent'; end if;
  if (r.detail ~ 'counters do not balance: claimed 3') is distinct from true then v_bad := v_bad || ' detail=' || coalesce(left(r.detail,80),'NULL'); end if;
  if r.outcome is distinct from 'accepted' then v_bad := v_bad || ' outcome=' || coalesce(r.outcome,'NULL') || ' (the verdict is the HTTP answer; the imbalance is a worker bug, not a transport failure)'; end if;
  if v_bad = '' then call _pass('cdl','0180-B3 합이 안 맞는 본문은 숫자를 보낸 그대로 두고 detail이 모순을 이름 짓는다; 판정은 그대로 accepted');
  else v_msg := v_bad; call _fail('cdl','0180-B3 imbalance-named', v_msg); end if;

  -- ---------- [0180-B5] a number that is not an integer does NOT abort the reconciler — named, six NULL, the other ticks still reconciled ----------
  v_bad := '';
  if v_err is not null then v_bad := v_bad || ' reconciler-RAISED [' || v_err || '] (one malformed body wedges every tick for the TTL)'; end if;
  select * into r from billing_key_dispatch_ticks where id = t5;
  if r.outcome is distinct from 'accepted' or r.claimed_count is distinct from 4 then v_bad := v_bad || ' outcome/claimed=' || coalesce(r.outcome,'NULL') || '/' || coalesce(r.claimed_count::text,'NULL'); end if;
  if r.revoked_count is not null or r.failed_count is not null or r.stale_count is not null or r.not_processing_count is not null or r.absent_count is not null or r.unreported_count is not null then v_bad := v_bad || ' a-float-body-stored-a-split'; end if;
  if (r.detail ~ 'per-cause split incomplete' and r.detail ~ 'revoked=1\.5 \(not an integer\)') is distinct from true then v_bad := v_bad || ' detail=' || coalesce(left(r.detail,100),'NULL'); end if;
  -- the ticks beside it in the same call were reconciled (the wedge, had it happened, leaves them `sent`)
  select count(*) into v_n from billing_key_dispatch_ticks where id in (t1, t2, t3) and outcome = 'accepted';
  if v_n <> 3 then v_bad := v_bad || ' ticks-reconciled-beside-it=' || v_n || '/3'; end if;
  -- and the deployed source casts NO body field straight to int (the precondition of the wedge)
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src2 from pg_proc where proname = 'reconcile_billing_key_dispatch_ticks';
  if v_src2 is null then v_bad := v_bad || ' NO-SOURCE(reconciler)';
  elsif (v_src2 ~ '\(v_body->>''[a-z_]+''\)::int') is distinct from false then v_bad := v_bad || ' 본문 필드를 바로 ::int 캐스트(소수·범위 밖이면 호출 전체가 죽는다)'; end if;
  if v_bad = '' then call _pass('cdl','0180-B5 정수가 아닌 숫자(1.5)는 리컨실러를 죽이지 않는다 — 여섯 열 NULL, detail이 필드와 값을 이름 짓고, 같은 호출의 다른 틱은 정리됨; 소스에 본문 직접 ::int 캐스트 없음');
  else v_msg := v_bad; call _fail('cdl','0180-B5 no-wedge', v_msg); end if;

  -- ---------- [0180-B6] a negative counter is named; a body with the six and no claim count keeps the six, unchecked ----------
  v_bad := '';
  select * into r from billing_key_dispatch_ticks where id = t6;
  if r.claimed_count is distinct from 0 or r.revoked_count is distinct from -1 or r.failed_count is distinct from 1 then v_bad := v_bad || ' negative-numbers-not-kept-as-sent'; end if;
  if (r.detail ~ 'a counter is negative: claimed 0, revoked -1') is distinct from true then v_bad := v_bad || ' negative-detail=' || coalesce(left(r.detail,100),'NULL'); end if;
  select * into r from billing_key_dispatch_ticks where id = t7;
  if r.outcome is distinct from 'accepted' or r.claimed_count is not null then v_bad := v_bad || ' no-claimed outcome/claimed=' || coalesce(r.outcome,'NULL') || '/' || coalesce(r.claimed_count::text,'NULL'); end if;
  if r.revoked_count is distinct from 1 or r.failed_count is distinct from 1 or r.stale_count is distinct from 0 or r.not_processing_count is distinct from 0 or r.absent_count is distinct from 0 or r.unreported_count is distinct from 0 then v_bad := v_bad || ' six-discarded-with-claimed'; end if;
  if (r.detail ~ 'no claim count' and r.detail ~ 'split kept, unchecked') is distinct from true then v_bad := v_bad || ' no-claimed-detail=' || coalesce(left(r.detail,100),'NULL'); end if;
  if v_bad = '' then call _pass('cdl','0180-B6 음수 카운터는 보낸 그대로 두고 detail이 이름 짓는다; claimed 없는 본문은 여섯 열을 남기고 「검산 안 됨」이라 말한다');
  else v_msg := v_bad; call _fail('cdl','0180-B6 negative-and-unclaimed', v_msg); end if;

  -- ---------- [0180-B4] deployed shape: the reconciler writes the split, checks the balance; ACL unchanged ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then v_bad := ' NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' ACL 기본값'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' authenticated 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE';
    else
      if (v_src ~ 'not_processing_count' and v_src ~ 'absent_count' and v_src ~ 'stale_count' and v_src ~ 'unreported_count' and v_src ~ 'revoked_count' and v_src ~ 'failed_count') is distinct from true then v_bad := v_bad || ' 여섯 열을 안 쓴다'; end if;
      if (v_src ~ 'counters do not balance') is distinct from true then v_bad := v_bad || ' 합 검사 없음'; end if;
      if (v_src ~ 'jsonb_typeof\(v_body->v_f\) is not distinct from ''number''' and v_src ~ 'v_num = trunc\(v_num\)') is distinct from true then v_bad := v_bad || ' 정수일 때만 읽는 가드 없음'; end if;
      if (v_src ~ 'a counter is negative') is distinct from true then v_bad := v_bad || ' 음수 검사 없음'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('cdl','0180-B4 배포 형태 — 리컨실러가 여섯 열을 쓰고 합·음수를 검사하며 정수일 때만 읽는다; definer·search_path·ACL(service_role만) 그대로');
  else v_msg := v_bad; call _fail('cdl','0180-B4 shape', v_msg); end if;
end $$;
