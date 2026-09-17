-- ═══ 215 — 0184: the stamp's cycle after a re-match · an observed answer remembered beyond retention — 0184-F1…F3, tag `atm` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS (codex re-review of 0183, REJECT/2):
--   · F1 the health view's `stuck_unreadable` counts an answered-but-unreadable tick, all time.
--     (#1 — the stamp's cycle after a re-match, and its MIRROR order — is the EDGE's and lives in
--     deno `[0184]`: SQL cannot tell a stale request's ask from a fresh one once both carry the
--     current id, and a party-scoped UPDATE is the edge's statement. This file does not pretend
--     to pin it; the cold review's #3 caught an earlier F1 that did.)
--   · F2 #2: an unnamed reconciliation error persists `response_observed_at` and `reconcile_error`;
--     the tick is never `no_response` even after its answer is deleted and the TTL has passed; it
--     is re-read past the TTL while its answer exists, and reconciles once the error clears.
--   · F3 deployed shape.
--
-- ─── MUTATION MAP — measured 2026-09-18, not predicted (numbers in the REGISTRY row) ───
--   Lab: an md5-identical copy of 0184 (+ tests, + functions and app/src for the deno side), every
--   plant `&&`-chained to its run, the control observed first (1297 / 0; deno 17 / 0 for the edge
--   file). 「demoted」 = 0184's VERIFY raise turned into a notice so the SUITE is what is measured;
--   「un-demoted」 = the shipped file, where the VERIFY aborts the apply before any suite runs.
--   (i)   an unnamed fault records nothing (0183 again) → F2 (observation-not-recorded · error=NULL ·
--         after-deletion+TTL: no_response — the answered tick blamed on the worker) + F3;
--         un-demoted ABORTS (UNNAMED-FAULT-NOT-RECORDED). Codex's #2.
--   (ii)  `no_response` ignores the record                → F2 (after-deletion+TTL: no_response) +
--         F3; un-demoted ABORTS.
--   (iii) the TTL blocks an observed tick again           → F2 (after-clear: sent/NULL — never
--         reconciled) + F3; un-demoted ABORTS.
--   (iv)  the verdict keeps a stale error                 → F2 (after-clear: error-not-cleared).
--   (v)   the verdict does not record the observation     → F2 (control-c) + F3 (2/3); un-demoted ABORTS.
--   (vi)  the `failed` marking does not record it         → F3 (2/3) only — source: no fixture here
--         reaches a `failed` verdict (214 E5 owns 22003/P0001; adding the column read there would
--         be this file's property leaking into that one); un-demoted ABORTS.
--   (vii) 0183's first-draft abort back                   → F1 + F2 (call-1 RAISED) + F3 + 213 D5 +
--         214 E5; un-demoted ABORTS.
--   (viii) the health view keeps no stuck column          → F1 (the-view-has-no-stuck_unreadable-
--         column — guarded so a missing column reddens the pin instead of aborting the block) + F3;
--         un-demoted ABORTS (HEALTH-VIEW-HAS-NO-STUCK-COLUMN).
--   (ix)  the `failed` verdict keeps a stale error        → F2 (d: failed/42883…/the reason in detail).
--   Deno (the edge file, control 19/0): (a) 0183's shape back — the stamp, then a separate read →
--   4 red (every `[0184]` pin: a read follows the stamp; the ask carries what the read said; no
--   party scope; the zero-row 409); (b) the stamp no longer returns the id → red at TYPE-CHECK
--   (TS2339) before any pin runs; (c) the ask sourced from the pre-stamp snapshot → 1 red (the ask
--   carries B, not A); (d) the stamp no longer party-scoped → 2 red (both party-scope arms);
--   (e) the recipient from the snapshot again → 1 red; (f) PostgREST's raw sentence in the 409 →
--   1 red.
--   NAMED GAP: a stale request whose ask carries the CURRENT id cannot be told from a fresh one in
--   SQL — the fix and its only pin live at the stamp (deno). The answer's content cannot outlive
--   pg_net's retention; past it an observed tick stays `sent` with `reconcile_error` — measured in
--   F2 as 「still sent, never no_response」, which is the whole of what SQL can promise there.
--
-- ─── FIXTURE NOTES ───
--  ① Helpers from 212/213 (`t_ask_bk`, `t_asks`). ② The fault stand-in is 214 E5's: a temporary
--     trigger on the tick table raising a chosen SQLSTATE on the main path's `accepted` write.
--  ③ 「the answer deleted」 = the `net._http_response` row removed by hand (what pg_net's retention
--     does); 「the TTL passed」 = `sent_at` moved 7 hours back.
set client_min_messages = warning;

do $$
declare
  o uuid; r1 uuid; r2 uuid; d uuid; rt uuid; bk1 uuid; v_a uuid; v_b uuid;
  t1 uuid; t2 uuid; t3 uuid; t4 uuid; v_req int; v_err text; v_bad text; v_msg text; v_src text; v_n int; v_oid oid; r record;
begin
  o := t_user('atm_owner', 'owner'); r1 := t_user('atm_runner1', 'runner'); r2 := t_user('atm_runner2', 'runner');
  d := t_dog(o, 'atm-dog'); rt := t_route('atm 코스');
  begin perform sweep_run_end_recovery(); exception when others then null; end;

  -- ---------- [0184-F1] the operator's one-row read counts a stuck tick (answered, unreadable, still `sent`) ----------
  -- (the earlier F1 restated 0183 E1 and passed with this slice absent — the cold review's #3; the
  -- stamp-cycle race and its mirror are the EDGE's and are pinned in deno `[0184]`; this file pins
  -- what 0184 owns in SQL)
  v_bad := '';
  create or replace function t_atm_tick_fault() returns trigger language plpgsql as $f$
  begin
    if new.id::text = current_setting('atm.fault_tick', true) and new.outcome = 'accepted' then
      raise exception 'stand-in fault %', current_setting('atm.fault_code', true) using errcode = current_setting('atm.fault_code', true);
    end if;
    return new;
  end $f$;
  create trigger t_atm_tick_fault before update on billing_key_dispatch_ticks for each row execute function t_atm_tick_fault();
  -- the column must exist before it is read: a missing column would abort this block (loud, nameless)
  -- instead of reddening this pin (the 0179 #14 class)
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_health'::regclass and not attisdropped and attname = 'stuck_unreadable';
  if v_n <> 1 then
    v_bad := v_bad || ' the-view-has-no-stuck_unreadable-column';
    drop trigger t_atm_tick_fault on billing_key_dispatch_ticks; drop function t_atm_tick_fault();
    v_msg := v_bad; call _fail('atm','0184-F1 health-view', v_msg);
  else
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from 0 then v_bad := v_bad || ' before: stuck_unreadable=' || coalesce(v_n::text, 'NULL'); end if;
  select 815000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 815000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, v_req, now() - interval '5 minutes') returning id into t1;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('atm.fault_tick', t1::text, true); perform set_config('atm.fault_code', '42883', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call RAISED [' || sqlerrm || ']'; end;
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from 1 then v_bad := v_bad || ' stuck: stuck_unreadable=' || coalesce(v_n::text, 'NULL') || ' (expected 1)'; end if;
  -- past the 24-hour window the row must STILL count (the column is all-time on purpose)
  update billing_key_dispatch_ticks set sent_at = now() - interval '3 days' where id = t1;
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from 1 then v_bad := v_bad || ' past-24h: stuck_unreadable=' || coalesce(v_n::text, 'NULL') || ' (expected 1 — the window must not hide it)'; end if;
  -- a named verdict is NOT stuck: a tick that ends `failed` leaves the count
  perform set_config('atm.fault_tick', '', true);
  update billing_key_dispatch_ticks set sent_at = now() - interval '5 minutes' where id = t1;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-2 RAISED [' || sqlerrm || ']'; end;
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from 0 then v_bad := v_bad || ' after-clear: stuck_unreadable=' || coalesce(v_n::text, 'NULL') || ' (expected 0)'; end if;
  drop trigger t_atm_tick_fault on billing_key_dispatch_ticks; drop function t_atm_tick_fault();
  if v_bad = '' then call _pass('atm','0184-F1 billing_key_dispatch_health.stuck_unreadable — 답은 있는데 못 읽어 sent로 남은 틱을 센다: 고장 전 0, 고장 중 1, 24시간 창 밖이어도 1(전 기간), 오류가 걷혀 판정되면 0');
  else v_msg := v_bad; call _fail('atm','0184-F1 health-view', v_msg); end if;
  end if;

  -- ---------- [0184-F2] an observed answer is remembered: never no_response after deletion + TTL; re-read past the TTL; reconciles once the error clears ----------
  v_bad := '';
  create or replace function t_atm_tick_fault() returns trigger language plpgsql as $f$
  begin
    if new.id::text = current_setting('atm.fault_tick', true) and new.outcome = 'accepted' then
      raise exception 'stand-in fault %', current_setting('atm.fault_code', true) using errcode = current_setting('atm.fault_code', true);
    end if;
    return new;
  end $f$;
  create trigger t_atm_tick_fault before update on billing_key_dispatch_ticks for each row execute function t_atm_tick_fault();
  select 815000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 815000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, v_req, now() - interval '5 minutes') returning id into t1;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('atm.fault_tick', t1::text, true); perform set_config('atm.fault_code', '42883', true);   -- a persistent unnamed error
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-1 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'sent' then v_bad := v_bad || ' after-fault: outcome=' || coalesce(r.outcome, 'NULL'); end if;
  if r.response_observed_at is null then v_bad := v_bad || ' after-fault: observation-not-recorded'; end if;
  if (r.reconcile_error ~ '^42883: ') is distinct from true then v_bad := v_bad || ' after-fault: error=' || coalesce(left(r.reconcile_error, 40), 'NULL'); end if;
  -- the answer is deleted (retention) and the TTL passes: still NOT no_response
  delete from net._http_response where id = v_req;
  update billing_key_dispatch_ticks set sent_at = now() - interval '7 hours' where id = t1;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-2 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'sent' then v_bad := v_bad || ' after-deletion+TTL: outcome=' || coalesce(r.outcome, 'NULL') || ' (an answered tick blamed on the worker)'; end if;
  if r.reconcile_error is null then v_bad := v_bad || ' after-deletion+TTL: the error was forgotten'; end if;
  -- the answer is back (as if retention had not run) while the TTL is still passed: RE-READ despite
  -- the cutoff, and once the error clears it reconciles and the error is cleared, the observation kept
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-3 RAISED [' || sqlerrm || ']'; end;
  if (select outcome from billing_key_dispatch_ticks where id = t1) is distinct from 'sent' then v_bad := v_bad || ' still-faulting: outcome=' || (select outcome from billing_key_dispatch_ticks where id = t1); end if;
  perform set_config('atm.fault_tick', '', true);                                               -- the error clears
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-4 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'accepted' or r.claimed_count is distinct from 3 then v_bad := v_bad || ' after-clear: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(r.claimed_count::text, 'NULL') || ' (expected accepted/3 — the TTL must not block an observed tick)'; end if;
  if r.reconcile_error is not null then v_bad := v_bad || ' after-clear: error-not-cleared'; end if;
  if r.response_observed_at is null then v_bad := v_bad || ' after-clear: observation-lost'; end if;
  -- controls: (a) a tick never observed, answered, past the TTL is NOT re-read (0150's cutoff still holds for it)
  select 815000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 815000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 1, v_req, now() - interval '7 hours') returning id into t2;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":1,"revoked":1,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' control-a RAISED [' || sqlerrm || ']'; end;
  if (select outcome from billing_key_dispatch_ticks where id = t2) is distinct from 'sent' then v_bad := v_bad || ' control-a: an unobserved tick past the TTL was read (' || (select outcome from billing_key_dispatch_ticks where id = t2) || ')'; end if;
  -- (b) a tick never observed and never answered, past the bound, IS no_response
  select 815000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 815000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 1, v_req, now() - interval '5 minutes') returning id into t3;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' control-b RAISED [' || sqlerrm || ']'; end;
  if (select outcome from billing_key_dispatch_ticks where id = t3) is distinct from 'no_response' then v_bad := v_bad || ' control-b: an unanswered tick is ' || (select outcome from billing_key_dispatch_ticks where id = t3); end if;
  -- (d) an unnamed fault FOLLOWED by a named one: the `failed` verdict clears the stale error and
  --     the reason lives in `detail` (cold review 0184 #7 — the failed write's clear was unpinned)
  select 815000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 815000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, v_req, now() - interval '1 minute') returning id into t4;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('atm.fault_tick', t4::text, true); perform set_config('atm.fault_code', '42883', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' d-1 RAISED [' || sqlerrm || ']'; end;
  if (select reconcile_error from billing_key_dispatch_ticks where id = t4) is null then v_bad := v_bad || ' d: the unnamed fault left no error'; end if;
  perform set_config('atm.fault_code', '22003', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' d-2 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t4;
  if r.outcome is distinct from 'failed' or r.reconcile_error is not null or (r.detail ~ '22003') is distinct from true then v_bad := v_bad || ' d: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(r.reconcile_error, '∅') || '/' || coalesce(left(r.detail, 60), '∅') || ' (expected failed, no stale error, the reason in detail)'; end if;
  perform set_config('atm.fault_tick', '', true);
  -- (c) a verdict stamps the observation too, with no error
  select 815000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 815000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 2, v_req, now() - interval '1 minute') returning id into t4;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":2,"revoked":2,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' control-c RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t4;
  if r.outcome is distinct from 'accepted' or r.response_observed_at is null or r.reconcile_error is not null then v_bad := v_bad || ' control-c: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(r.response_observed_at::text, 'no-observation') || '/' || coalesce(r.reconcile_error, '∅'); end if;
  drop trigger t_atm_tick_fault on billing_key_dispatch_ticks; drop function t_atm_tick_fault();
  if v_bad = '' then call _pass('atm','0184-F2 이름 없는 오류(42883)는 response_observed_at·reconcile_error를 남긴다; 답이 지워지고 TTL이 지나도 no_response가 아니다; 답이 있는 동안은 TTL 너머에서도 다시 읽고, 오류가 걷히면 accepted/3(오류 지움, 관찰 유지); 관찰 없는 TTL 지난 틱은 안 읽고(0150), 답 없는 틱은 여전히 no_response, 판정도 관찰을 남긴다; 이름 없는 오류 뒤의 판정(22003)은 failed이고 낡은 오류를 지운다');
  else v_msg := v_bad; call _fail('atm','0184-F2 evidence', v_msg); end if;

  -- ---------- [0184-F3] deployed shape ----------
  v_bad := '';
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_ticks'::regclass and not attisdropped and attname in ('response_observed_at', 'reconcile_error') and (atthasdef or attnotnull);
  if v_n <> 0 then v_bad := v_bad || ' 새 열에 기본값/not null=' || v_n; end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then v_bad := ' NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' 클라 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE';
    else
      if (v_src ~ 'reconcile_error      = left\(sqlstate \|\| '': '' \|\| sqlerrm, 300\)') is distinct from true then v_bad := v_bad || ' 이름 없는 오류를 기록하지 않는다'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'response_observed_at = coalesce\(response_observed_at, now\(\)\)', 'g');
      if v_n <> 3 then v_bad := v_bad || ' 관찰 기록 수=' || v_n || '(판정·failed·이름 없는 오류 3곳이어야)'; end if;
      if (v_src ~ 'and response_observed_at is null\s+and not exists \(select 1 from net\._http_response h where h\.id = request_id\)') is distinct from true then v_bad := v_bad || ' no_response가 관찰 기록을 무시한다'; end if;
      if (v_src ~ 'or t\.response_observed_at is not null\)') is distinct from true then v_bad := v_bad || ' TTL이 관찰된 틱을 막는다'; end if;
      if (v_src ~ 'not in \(''22'', ''23'', ''P0''\) then raise;') is distinct from false then v_bad := v_bad || ' 이름 없는 오류가 호출을 죽인다'; end if;
    end if;
  end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_health'::regclass and not attisdropped and attname = 'stuck_unreadable';
  if v_n <> 1 then v_bad := v_bad || ' health view: stuck_unreadable 없음'; end if;
  if v_bad = '' then call _pass('atm','0184-F3 배포 형태 — 새 열 기본값 없음; definer·ACL; 이름 없는 오류 기록, 관찰 기록 3곳, no_response가 관찰을 존중, TTL이 관찰된 틱을 안 막음, 호출을 죽이지 않음');
  else v_msg := v_bad; call _fail('atm','0184-F3 shape', v_msg); end if;
end $$;
