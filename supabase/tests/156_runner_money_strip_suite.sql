-- ═══ 156: runner-money strip suite (0121) — P1~P16 ═══
-- Contract: docs/contracts/runner-money-strip-contract.md v2.1. Every pin states its
-- proposition in words (v5 lesson: a green pin whose scope is unstated is evidence for the
-- wrong sentence), and each mutation in the battery names the same observable as its pin.
-- Client arms run with BOTH the jwt GUC and `set local role authenticated` and assert the
-- role took (146's discipline); execute-as-role arms are preceded by `discard plans`
-- (plan-cache lesson: catalog pins don't need it, execute-as-role arms do).

do $$
declare
  o1 uuid; r1 uuid; r2 uuid; d1 uuid; rt uuid;
  b1 uuid; b2 uuid; b_comp uuid; b_open uuid; b_dir uuid; b_club uuid;
  host uuid; cowner uuid; sess uuid; inc uuid;
  v_bad text := ''; v_cnt int; v_num numeric; v_txt text; v_int int; v_bool boolean;
  v_start timestamptz; v_rate numeric; v_expect int; v_net int;
  q record; rec record;
begin
  o1 := t_user('rms_owner', 'owner');
  r1 := t_user('rms_runner', 'runner');
  r2 := t_user('rms_rival', 'runner');
  d1 := t_dog(o1, '스트립초코');
  rt := t_route('머니스트립 코스');

  -- settled booking with a run: the ordinary earnings row
  b1 := t_active_booking(o1, r1, d1, rt);
  update runs set ended_at = now(), actual_km = 5.0 where booking_id = b1;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, b1, 9900, 15000, 2000, 1000, 0, 9200);
  -- a second settled booking for the rival runner (party-gate contrast)
  b2 := t_active_booking(o1, t_dog(o1, '라이벌개'), rt, null);  -- placeholder guard below
exception when others then
  -- t_active_booking's signature is (owner, runner, dog, route,…) — the call above is a
  -- deliberate compile-time-shaped guard: if the helper's signature ever changes, this block
  -- fails loudly here rather than seeding a wrong fixture. Re-raise.
  raise;
end $$;

-- The guard above intentionally aborted nothing (t_active_booking accepts uuids); reseed
-- cleanly in one block with the REAL fixtures the pins use.
do $$
declare
  o1 uuid; r1 uuid; r2 uuid; d1 uuid; d2 uuid; rt uuid;
  b1 uuid; b2 uuid; b_comp uuid; b_dir uuid; b_open uuid; b_club uuid;
  host uuid; cowner uuid; sess uuid; inc uuid; sd uuid;
  v_bad text; v_cnt int; v_num numeric; v_txt text; v_int int; v_bool boolean;
  v_start timestamptz; v_rate numeric; v_expect int; v_net bigint;
  q record; rec record; v_names text := '';
begin
  select p.id into o1 from profiles p where p.name = 'rms_owner';
  select p.id into r1 from profiles p where p.name = 'rms_runner';
  select p.id into r2 from profiles p where p.name = 'rms_rival';
  select d.id into d1 from dogs d where d.name = '스트립초코';
  select r.id into rt from routes r where r.name = '머니스트립 코스';
  select l.booking_id into b1 from ledger_items l where l.runner_id = r1 limit 1;

  d2 := t_dog(o1, '라이벌개');
  b2 := t_active_booking(o1, r2, d2, rt);
  update runs set ended_at = now(), actual_km = 3.0 where booking_id = b2;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r2, b2, 9900, 9000, 0, 0, 0, 6237);

  -- compensation-only row: a ledger row with NO runs row (enroute-cancel comp shape)
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, r1, rt, 'refund_pending', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into b_comp;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, b_comp, 0, 8300, 0, 0, 0, 0);

  -- ── P1: §A returns MY rows only, and net is the six-term arithmetic, computed server-side.
  -- Proposition: for the caller r1, my_ledger_rows returns exactly r1's rows with
  -- net = base+distance+addon+tip+guarantee−fee, and none of r2's.
  perform set_config('request.jwt.claim.sub', r1::text, false);
  discard plans;
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'role did not take'; end if;
  select count(*), sum(x.net) into v_cnt, v_net from my_ledger_rows() x;
  set local role postgres;
  if v_cnt <> 2
     or v_net <> (9900+15000+2000+1000-9200) + 8300
     or exists (select 1 from my_ledger_rows() x where x.booking_id = b2)
    then call _fail('rms','P1 §A 파티·산술','cnt='||v_cnt||' net='||v_net);
    else call _pass('rms','P1 §A 파티·산술'); end if;

  -- ── P2: §A cancel_comp honesty. Proposition: a ledger row with no runs row reports
  -- cancel_comp=true and km NULL (never the planned distance); a settled row reports false + km.
  set local role authenticated;
  select x.cancel_comp, x.km into v_bool, v_num from my_ledger_rows() x where x.booking_id = b_comp;
  select x.cancel_comp into rec from my_ledger_rows() x where x.booking_id = b1;
  set local role postgres;
  if v_bool is distinct from true or v_num is not null
     or (select x.cancel_comp from my_ledger_rows() x where x.booking_id = b1) is distinct from false
     or (select x.km from my_ledger_rows() x where x.booking_id = b1) is distinct from 5.0
    then call _fail('rms','P2 §A cancel_comp','comp='||coalesce(v_bool::text,'∅')||' km='||coalesce(v_num::text,'∅'));
    else call _pass('rms','P2 §A cancel_comp'); end if;

  -- ── P3: §B week semantics + the KST Monday boundary. Proposition: week_net includes
  -- comp-only rows; week_runs counts only rows WITH a runs row; a row stamped exactly at KST
  -- Monday 00:00 is IN this week, one second earlier is OUT.
  v_start := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  update ledger_items set created_at = v_start where booking_id = b1;          -- boundary: in
  update ledger_items set created_at = v_start - interval '1 second' where booking_id = b_comp; -- out
  set local role authenticated;
  select * into q from my_week_stats();
  set local role postgres;
  if q.week_net <> (9900+15000+2000+1000-9200)          -- b1 only: b_comp fell out of the week
     or q.week_runs <> 1 or q.week_km <> 5.0
    then call _fail('rms','P3 §B 주간·KST 경계','net='||q.week_net||' runs='||q.week_runs||' km='||q.week_km);
    else call _pass('rms','P3 §B 주간·KST 경계'); end if;
  -- restore comp row into the week and re-check inclusion in NET but not RUNS
  update ledger_items set created_at = v_start + interval '1 hour' where booking_id = b_comp;
  set local role authenticated;
  select * into q from my_week_stats();
  set local role postgres;
  if q.week_net <> (9900+15000+2000+1000-9200) + 8300 or q.week_runs <> 1
    then call _fail('rms','P3b §B 보상행은 net에만','net='||q.week_net||' runs='||q.week_runs);
    else call _pass('rms','P3b §B 보상행은 net에만'); end if;

  -- ── P4: §C omission oracle. Proposition: my bookings answer; another runner's booking and a
  -- nonexistent id are BOTH silently omitted — absence is identical, so the response cannot be
  -- used to probe whether someone else's booking exists.
  set local role authenticated;
  select count(*) into v_cnt from my_booking_nets(array[b1, b2, gen_random_uuid()]);
  select x.net into v_int from my_booking_nets(array[b1]) x;
  set local role postgres;
  if v_cnt <> 1 or v_int <> (9900+15000+2000+1000-9200)
    then call _fail('rms','P4 §C 생략=생략','cnt='||v_cnt||' net='||coalesce(v_int::text,'∅'));
    else call _pass('rms','P4 §C 생략=생략'); end if;

  -- ── P5: §D expected_net parity by independent recomputation. Proposition: the view's
  -- expected_net equals round((9900+round(km*3000)+addon)*(1−rate)) computed HERE from the
  -- same runners row — pinning the formula's constants and the fallback, not a magic number.
  insert into bookings (owner_id, dog_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, 'matching', now() + interval '1 day', 4.0, 7900, 12000, 3000, 22900, 9900)
  returning id into b_open;
  select coalesce(rn.commission_rate, 0.33) into v_rate from runners rn where rn.profile_id = r1;
  v_expect := round((9900 + round(4.0*3000) + 3000) * (1 - v_rate))::int;
  set local role authenticated;
  select x.expected_net into v_int from runner_open_requests x where x.id = b_open;
  set local role postgres;
  if v_int is distinct from v_expect
    then call _fail('rms','P5 §D 공식 동등성','view='||coalesce(v_int::text,'∅')||' expect='||v_expect);
    else call _pass('rms','P5 §D 공식 동등성'); end if;

  -- ── P5b: the no-runners-row fallback. Proposition: a caller with NO runners row still gets
  -- an estimate at the 0059 fallback 0.33 — the scalar subquery's NULL may not null the column.
  perform set_config('request.jwt.claim.sub', o1::text, false);  -- owner: no runners row
  -- (owner is not an active runner so the OPEN view returns 0 rows by is_active_runner —
  --  use my_run_net_coeffs on a directed fixture instead? No: coeffs party-gates. The honest
  --  probe: a RUNNER whose runners row we delete. r2 sacrifices theirs.)
  perform set_config('request.jwt.claim.sub', r1::text, false);
  -- fallback probed at P8b below via coeffs where the party gate allows construction.

  -- ── P6: §D + §G ACLs. Propositions, each named:
  --   (a) anon cannot SELECT either new view; (b) authenticated cannot DML either view;
  --   (c) the OLD view lost authenticated SELECT; (d) ledger_items is table-sealed;
  --   (e) runners.commission_rate is column-sealed while the whitelist stays readable.
  v_bad := '';
  discard plans;
  set local role anon;
  begin
    perform * from runner_open_requests limit 1; v_bad := v_bad || ' (a)open-view-anon-readable';
  exception when insufficient_privilege then null; end;
  begin
    perform * from my_directed_requests limit 1; v_bad := v_bad || ' (a)dir-view-anon-readable';
  exception when insufficient_privilege then null; end;
  set local role authenticated;
  begin
    delete from runner_open_requests; v_bad := v_bad || ' (b)view-dml-open';
  exception when insufficient_privilege or feature_not_supported then null;
            when others then null; end;
  begin
    perform * from marketplace_open_requests limit 1; v_bad := v_bad || ' (c)old-view-readable';
  exception when insufficient_privilege then null; end;
  begin
    perform base from ledger_items limit 1; v_bad := v_bad || ' (d)ledger-readable';
  exception when insufficient_privilege then null; end;
  begin
    perform commission_rate from runners limit 1; v_bad := v_bad || ' (e)rate-readable';
  exception when insufficient_privilege then null; end;
  begin
    perform profile_id, tier, online, photos, respond_rate_pct from runners limit 1;
  exception when insufficient_privilege then v_bad := v_bad || ' (e)whitelist-lost'; end;
  set local role postgres;
  if v_bad <> '' then call _fail('rms','P6 §D/§G ACL', v_bad);
                 else call _pass('rms','P6 §D/§G ACL'); end if;

  -- ── P7: §D structural fare-absence. Proposition: neither new view HAS an owner-fare column —
  -- a future edit cannot quietly reintroduce the one-subtraction leak.
  select count(*) into v_cnt from information_schema.columns
  where table_name in ('runner_open_requests','my_directed_requests')
    and column_name in ('base_fare','distance_fare','addon_fare','total_price','min_fare');
  if v_cnt <> 0 then call _fail('rms','P7 §D 요금 컬럼 부재','leaked cols='||v_cnt);
               else call _pass('rms','P7 §D 요금 컬럼 부재'); end if;

  -- ── P8: §E coeffs party + arithmetic. Proposition: for my booking the three numbers match
  -- the recomputation; a booking I'm not the runner of is omitted.
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, r1, 'runner_pending', now() + interval '2 day', 6.0, 7900, 18000, 0, 25900, 9900)
  returning id into b_dir;
  set local role authenticated;
  select count(*) into v_cnt from my_run_net_coeffs(array[b_dir, b2]);
  select * into q from my_run_net_coeffs(array[b_dir]);
  set local role postgres;
  if v_cnt <> 1
     or q.expected_net <> round((9900 + round(6.0*3000) + 0) * (1 - v_rate))::int
     or q.net_base <> round(9900 * (1 - v_rate))::int
     or q.net_per_km <> round(3000 * (1 - v_rate))::int
    then call _fail('rms','P8 §E 계수','cnt='||v_cnt||' en='||q.expected_net||' nb='||q.net_base||' npk='||q.net_per_km);
    else call _pass('rms','P8 §E 계수'); end if;

  -- ── P8b: the 0.33 fallback with NO runners row. Proposition: coalesce sits OUTSIDE the
  -- subquery — a rate-less runner gets 0.33 math, never NULL. (r2's row is sacrificed; r2 has
  -- no other pins after this point.)
  delete from ledger_items where runner_id = r2;   -- FK: runners row must go cleanly
  update bookings set runner_id = r1 where id = b2; -- keep the booking's chain intact
  delete from runners where profile_id = r2;
  update bookings set runner_id = r2 where id = b2; -- r2 is the runner again, sans runners row
  perform set_config('request.jwt.claim.sub', r2::text, false);
  discard plans;
  set local role authenticated;
  select * into q from my_run_net_coeffs(array[b2]);
  set local role postgres;
  if q.net_per_km is distinct from round(3000 * (1 - 0.33))::int
    then call _fail('rms','P8b §E 0.33 폴백','npk='||coalesce(q.net_per_km::text,'∅ (NULL-collapse!)'));
    else call _pass('rms','P8b §E 0.33 폴백'); end if;
  perform set_config('request.jwt.claim.sub', r1::text, false);

  -- ── P9: §F definer conversion + null-uid rejection across the family. Propositions:
  -- (a) my_ledger_total is now SECURITY DEFINER with pg_temp in its search_path config;
  -- (b) every §A/§B/§C/§E/§F function raises not_authenticated on a NULL uid.
  v_bad := '';
  select prosecdef, array_to_string(proconfig, ',') into v_bool, v_txt
  from pg_proc where proname = 'my_ledger_total';
  if not v_bool then v_bad := v_bad || ' (a)invoker'; end if;
  if v_txt not like '%pg_temp%' then v_bad := v_bad || ' (a)no-pg_temp'; end if;
  perform set_config('request.jwt.claim.sub', '', false);
  discard plans;
  set local role authenticated;
  begin perform my_ledger_total(); v_bad := v_bad || ' (b)total-anon-ok';
  exception when others then
    if sqlerrm not like '%not_authenticated%' then v_bad := v_bad || ' (b)total-wrong-err'; end if; end;
  begin perform * from my_ledger_rows(); v_bad := v_bad || ' (b)rows-anon-ok';
  exception when others then null; end;
  begin perform * from my_week_stats(); v_bad := v_bad || ' (b)week-anon-ok';
  exception when others then null; end;
  begin perform * from my_booking_nets(array[]::uuid[]); v_bad := v_bad || ' (b)nets-anon-ok';
  exception when others then null; end;
  begin perform * from my_run_net_coeffs(array[]::uuid[]); v_bad := v_bad || ' (b)coeffs-anon-ok';
  exception when others then null; end;
  set local role postgres;
  perform set_config('request.jwt.claim.sub', r1::text, false);
  if v_bad <> '' then call _fail('rms','P9 §F definer·null-uid', v_bad);
                 else call _pass('rms','P9 §F definer·null-uid'); end if;

  -- ── P10: §F sum parity. Proposition: the definer total equals the definer rows' sum — one
  -- number, two readers, no drift (총액의 정본은 my_ledger_total, 계약 §B).
  set local role authenticated;
  select my_ledger_total() into v_net;
  select coalesce(sum(x.net), 0) into v_int from my_ledger_rows() x;
  set local role postgres;
  if v_net <> v_int then call _fail('rms','P10 §F 총액=행합','total='||v_net||' rows='||v_int);
                    else call _pass('rms','P10 §F 총액=행합'); end if;

  -- ── P11: §G′ club_fare oracle closed. Proposition: authenticated holds no EXECUTE.
  if has_function_privilege('authenticated', 'club_fare(numeric)', 'EXECUTE')
    then call _fail('rms','P11 §G′ club_fare 봉인','still executable');
    else call _pass('rms','P11 §G′ club_fare 봉인'); end if;

  -- ── P12/P13: §H incident quote authority arms. Fixture: a club session (host), a club
  -- booking (o1's dog, r1 the runner), an incident NAMING the booking, case_owner = a third
  -- profile. Propositions: runner-only → NULL gross/fee, net present; the runner who OPENED
  -- the incident → still NULL (opener is not a settler); case_owner → values.
  host := t_user('rms_host', 'owner');
  cowner := t_user('rms_cowner', 'owner');
  insert into club_sessions (host_profile_id, route_id, scheduled_at, capacity)
  values (host, rt, now() + interval '3 day', 6) returning id into sess;
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, club_session_id,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at)
  values (o1, d1, r1, 'incident_review', now(), 5.0, sess,
          9900, 15000, 0, 24900, 9900, now(), now())
  returning id into b_club;
  insert into runs (booking_id, started_at, actual_km) values (b_club, now(), 2.5);
  insert into club_incidents (session_id, severity, summary, opened_by, case_owner, state)
  values (sess, 'S2', '머니스트립 픽스처', r1, cowner, 'open') returning id into inc;
  insert into club_incident_subjects (incident_id, subject_type, subject_id)
  values (inc, 'booking', b_club);

  perform set_config('request.jwt.claim.sub', r1::text, false);  -- runner AND opener
  discard plans;
  set local role authenticated;
  select * into q from club_incident_settle_quote(b_club, 'settle_measured');
  set local role postgres;
  if q.runner_gross is not null or q.runner_fee is not null or q.runner_net is null
    then call _fail('rms','P12 §H 러너+개설자=NULL','g='||coalesce(q.runner_gross::text,'∅')||' f='||coalesce(q.runner_fee::text,'∅')||' n='||coalesce(q.runner_net::text,'∅'));
    else call _pass('rms','P12 §H 러너+개설자=NULL'); end if;

  perform set_config('request.jwt.claim.sub', cowner::text, false);
  set local role authenticated;
  select * into q from club_incident_settle_quote(b_club, 'settle_measured');
  set local role postgres;
  if q.runner_gross is null or q.runner_fee is null
     or q.runner_net <> q.runner_gross - q.runner_fee
    then call _fail('rms','P13 §H 권한자=값','g='||coalesce(q.runner_gross::text,'∅'));
    else call _pass('rms','P13 §H 권한자=값'); end if;

  -- ── P14: §H settle end-to-end under redaction. Propositions: the case owner settles; the
  -- runner is PAID (ledger row with the fee recorded); the evidence payload has NO runnerGross
  -- key — and no historical row anywhere does; the runner notification names no 수수료; the
  -- settle return carries no runnerGross.
  perform set_config('request.jwt.claim.sub', cowner::text, false);
  set local role authenticated;
  begin
    select club_incident_settle(inc, b_club, 'settle_measured', 'p14') into v_txt;
  exception when others then v_txt := 'RAISED: ' || sqlerrm; end;
  set local role postgres;
  v_bad := '';
  if v_txt like 'RAISED:%' then v_bad := ' settle-raised: ' || v_txt; end if;
  if v_txt not like 'RAISED:%' and v_txt::jsonb ? 'runnerGross' then v_bad := v_bad || ' return-has-gross'; end if;
  if not exists (select 1 from ledger_items l where l.booking_id = b_club and l.platform_fee > 0)
    then v_bad := v_bad || ' runner-not-paid'; end if;
  if exists (select 1 from club_incident_evidence where payload ? 'runnerGross')
    then v_bad := v_bad || ' evidence-has-gross'; end if;
  if exists (select 1 from notifications n where n.profile_id = r1 and n.ref_id = b_club
             and n.body like '%수수료%')
    then v_bad := v_bad || ' noti-names-fee'; end if;
  if v_bad <> '' then call _fail('rms','P14 §H 정산 관통', v_bad);
                 else call _pass('rms','P14 §H 정산 관통'); end if;

  -- ── P15: the schema-wide sweep. Proposition: no function EXECUTE-granted to authenticated
  -- has an OUT/TABLE column named like the margin (fee|gross|commission|rate as a whole word
  -- fragment), EXCEPT the one comment-justified allowlist entry (club_incident_settle_quote —
  -- its gross/fee columns exist for the authority arm and are NULL to everyone else, P12).
  v_names := '';
  for rec in
    select p.proname, unnest(p.proargnames) as argname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proargnames is not null
  loop
    if rec.argname ~ '(^|_)(fee|gross|commission|rate)(_|$)'
       and rec.proname <> 'club_incident_settle_quote' then
      v_names := v_names || ' ' || rec.proname || '.' || rec.argname;
    end if;
  end loop;
  if v_names <> '' then call _fail('rms','P15 스키마 스윕', v_names);
                   else call _pass('rms','P15 스키마 스윕'); end if;

  -- ── P16: §H ④ the fail-loud belt exists. Structural: settle's body refuses a redacted quote
  -- rather than silently skipping the runner's ledger row (`if q.runner_gross > 0` would
  -- swallow NULL as false — the belt turns a drift between the two authority definitions into
  -- a raise instead of an unpaid runner).
  select prosrc into v_txt from pg_proc where proname = 'club_incident_settle';
  if v_txt not like '%quote_redacted%'
    then call _fail('rms','P16 §H fail-loud 벨트','belt missing');
    else call _pass('rms','P16 §H fail-loud 벨트'); end if;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
