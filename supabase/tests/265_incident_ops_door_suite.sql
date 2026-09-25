-- ═══ 265 — 0234: a reported incident reaches an operator — the `incident_opened` class, the bell on
-- ═══        `open_incident_tx`, and the roster's read of every open incident
-- ═══        0234-C1 · I1 · I2 · I3 · I4 · B2 · L1 · L2 · S1, tag `iod`
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation:
--   · C1 **AN OPERATOR CAN BE SEATED AT THE NEW DESK FROM THE PRODUCT.** A `payout_due` operator's
--        `ops_roster_set(<p>, 'incident_opened', true)` succeeds (changed = true) and the person is
--        then a recipient; a near-miss class name is still `unknown_class`. (This suite's operator
--        is seated THROUGH that door, so every later pin stands on it.)
--   · I1 **A NEW INCIDENT RINGS THE ROSTER EXACTLY ONCE.** One seated operator; the owner opens a
--        `normal` incident → exactly ONE `system` row, to that operator, titled 「사고 접수 — 확인
--        필요」, `ref_id` = the new incident, with a body that names nobody (no booking id, no
--        incident id, no display name); neither party receives it. A delta: 0 before the call.
--   · I2 **SEVERITY IS IN THE TITLE.** `urgent` → 「긴급 사고 접수 — 확인 필요」, `sos` → 「SOS 사고
--        접수 — 즉시 확인 필요」 — one row each, and no other incident title on either.
--   · I3 **ONLY A NEW INCIDENT RINGS, AND A FAILING BELL NEVER REFUSES THE REPORT.** A second open on
--        the same booking returns the SAME id and adds no row; a stranger's call (`not_party`) and a
--        bad kind (`bad_kind`) add no row. With the bell's insert made to fail (a NOT VALID check
--        constraint refusing the SOS title, inside a rolled-back subtransaction) an SOS open still
--        RETURNS an id, the incident row EXISTS, and no bell row was written — beside a CONTROL
--        open of the same severity without the constraint that DOES write one (so a world with no
--        bell at all cannot pass this pin: measured green on the pre-0234 tree before the control).
--   · I4 **AN EMPTY ROSTER PAGES NOBODY AND THE INCIDENT IS STILL LISTED.** Every `incident_opened`
--        row off → an open writes no ops row; the incident is in `ops_open_incidents()` (read by the
--        re-seated operator) with `notified_at` NULL.
--   · B2 **THE WRITTEN TITLES ARE LEDGERED** — in `_noti_ops_titles()`, `ops` category, not urgent;
--        measured on what `open_incident_tx` actually wrote.
--   · L1 **`ops_open_incidents()` REFUSES EVERYONE OFF THE `incident_opened` ROSTER** — a signed-in
--        stranger, a `payout_due`-only operator and a PARTY to the incident get `not_ops`; no caller
--        gets `not_signed_in`.
--   · L2 **FOR THE OPERATOR IT IS EXACTLY THE OPEN INCIDENTS.** This suite's open incidents are all
--        listed and its RESOLVED one is not; SOS sorts before urgent before normal; `reporter_role`
--        is owner / runner as reported; `notified_at` is set on the belled rows; the KEY SET is exact
--        (no note, no media).
--   · S1 **DEPLOYED SHAPE.** Definers with in-body search_path and effective ACLs both ways; the read
--        takes zero arguments, its roster gate precedes its first read and names `incident_opened`;
--        in `open_incident_tx` (comment-stripped) the bell follows the insert and sits inside its own
--        handler, and the party gate still precedes the state gate; `ops_roster_set` still carries
--        0216's key and now names the class.
--
-- ─── GAPS (prose) ───
--   · Nothing here pushes (`00_shim.sql` stubs `net.http_post`).
--   · The bell's subtransaction is proven with a FORCED insert failure (a constraint), not with the
--     real-world failure it guards against (a recipient row held past a lock wait). The property —
--     「the report stands when the bell cannot be written」 — is the same; the cause is staged.
--
-- ─── FIXTURE NOTES ───
--  ① Counts are scoped to this suite's bookings / incidents. `incident_opened` is NEW, but 239
--     `0208-C1` seats a subject at EVERY allowlisted class, so an earlier suite CAN leave an active
--     row. This suite saves every active `incident_opened` row, switches them off (so 「exactly one
--     recipient」 is a world it built, asserted in C1), and restores them at the end. I4 rolls back.
--  ② `request.jwt.claim.sub` is set and cleared explicitly around every caller-shaped call.
set client_min_messages = warning;

-- a confirmed marketplace booking (in open_incident_tx's reportable set)
create or replace function t_iod_booking(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'confirmed', now() + interval '3 hours', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  return v;
end $$;

-- open_incident_tx as ONE caller: {id} or {raised}
create or replace function t_iod_open(p_uid uuid, p_booking uuid, p_kind text, p_severity text)
returns jsonb language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    v := open_incident_tx(p_booking, p_kind, p_severity, null, '{}');
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('id', v);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- ops_open_incidents as ONE caller: rows keyed by incident id (+ the order), OR the raise word
create or replace function t_iod_list_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb; v_ord jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_object_agg(x.incident_id::text, to_jsonb(x)), '{}'::jsonb),
           coalesce(jsonb_agg(x.incident_id::text order by x.ord), '[]'::jsonb)
      into v, v_ord
      from (select o.*, row_number() over () as ord from ops_open_incidents() o) x;
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('rows', v, 'order', v_ord);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- ops_roster_set as ONE caller
create or replace function t_iod_seat_as(p_uid uuid, p_profile uuid, p_class text, p_active boolean)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select to_jsonb(x) into v from ops_roster_set(p_profile, p_class, p_active) x;
    perform set_config('request.jwt.claim.sub', '', true);
    return v;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_iod_src(p_name text) returns text
language sql stable as $$
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;

do $$
declare
  oo uuid; rr uuid; sx uuid; opsI uuid; opsP uuid;
  dg uuid; rt uuid;
  bN uuid; bU uuid; bS uuid; bF uuid; bE uuid; bR uuid; bG uuid;
  inc_n uuid; inc_u uuid; inc_s uuid; inc_f uuid; inc_e uuid; inc_r uuid;
  T_N constant text := '사고 접수 — 확인 필요';
  T_U constant text := '긴급 사고 접수 — 확인 필요';
  T_S constant text := 'SOS 사고 접수 — 즉시 확인 필요';
  LIST_KEYS constant text[] := array['incident_id','booking_id','dog_name','owner_name','runner_name',
    'booking_status','kind','severity','reporter_role','opened_at','verified_at','notified_at', 'ord'];
  v jsonb; v_bad text; v_msg text; v_n int; v_n2 int; v_src text; v_txt text; v_keys text[];
  r record; p_a int; p_b int; v_oid oid; fn text; v_body text;
  f_id jsonb; f_rows int; f_inc int; f_err text; g_id jsonb; g_rows int;
  e_id jsonb; e_rows int; e_list jsonb; e_err text;
  v_saved uuid[];
begin
  perform set_config('request.jwt.claim.sub', '', true);
  oo   := t_user('iod_owner', 'owner');
  rr   := t_user('iod_runner', 'runner');
  sx   := t_user('iod_stranger', 'owner');
  opsI := t_user('iod_ops_inc', 'owner');
  opsP := t_user('iod_ops_pay', 'owner');
  dg   := t_dog(oo, '사고견');
  rt   := t_route('iod 코스');
  -- the console operator (bootstrapped by INSERT, as every roster suite does — 0208 §0: the first
  -- operator is psql by construction)
  insert into ops_recipients (profile_id, event_class, active) values (opsP, 'payout_due', true)
  on conflict (profile_id, event_class) do update set active = true;
  -- fixture note ①: this suite's roster world, restored at the end
  select coalesce(array_agg(profile_id), '{}') into v_saved
    from ops_recipients where event_class = 'incident_opened' and active;
  update ops_recipients set active = false where event_class = 'incident_opened' and active;
  bN := t_iod_booking(oo, rr, dg, rt); bU := t_iod_booking(oo, rr, dg, rt);
  bS := t_iod_booking(oo, rr, dg, rt); bF := t_iod_booking(oo, rr, dg, rt);
  bE := t_iod_booking(oo, rr, dg, rt); bR := t_iod_booking(oo, rr, dg, rt);
  bG := t_iod_booking(oo, rr, dg, rt);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-C1] the new class is seatable through the product's door
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if exists (select 1 from ops_recipients where event_class = 'incident_opened' and active)
      then v_bad := v_bad || ' FIXTURE: incident_opened still has an active row after neutralising'; end if;
    v := t_iod_seat_as(opsP, opsI, 'incident_opened', true);
    if (v->>'changed') is distinct from 'true' then v_bad := v_bad || ' seat: ' || coalesce(v::text, 'NULL'); end if;
    if (select count(*) from ops_recipients_for('incident_opened') x where x = opsI) is distinct from 1::bigint
      then v_bad := v_bad || ' the seated operator is not a recipient'; end if;
    if (t_iod_seat_as(opsP, opsI, 'incident_open', true)->>'raised') is distinct from 'unknown_class'
      then v_bad := v_bad || ' a near-miss class was not unknown_class'; end if;
    if v_bad = '' then call _pass('iod','0234-C1 payout_due 운영자가 ops_roster_set으로 incident_opened 자리에 사람을 앉힐 수 있다(changed=true, 수신자가 됨); 비슷한 오타 클래스는 여전히 unknown_class');
    else v_msg := v_bad; call _fail('iod','0234-C1 incident_opened seatable', v_msg); end if;
  exception when others then call _fail('iod','0234-C1 incident_opened seatable', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-I1] a new incident rings the roster exactly once
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_n from ops_recipients_for('incident_opened');
    if v_n is distinct from 1 then v_bad := v_bad || ' FIXTURE: incident_opened roster=' || v_n || ' (1 expected)'; end if;
    v := t_iod_open(oo, bN, 'dog_injury', 'normal');
    inc_n := (v->>'id')::uuid;
    if inc_n is null then v_bad := v_bad || ' open refused: ' || v::text;
    else
      select count(*)::int into v_n from notifications where kind = 'system' and ref_id = inc_n;
      if v_n is distinct from 1 then v_bad := v_bad || ' system rows for the incident=' || v_n; end if;
      select count(*)::int into v_n from notifications where ref_id = inc_n and title = T_N and profile_id = opsI and kind = 'system';
      if v_n is distinct from 1 then v_bad := v_bad || ' the operator''s normal-title row=' || v_n; end if;
      if exists (select 1 from notifications where ref_id in (inc_n, bN) and title in (T_N, T_U, T_S) and profile_id in (oo, rr))
        then v_bad := v_bad || ' 🔴 a PARTY got the ops bell'; end if;
      select body into v_body from notifications where ref_id = inc_n and title = T_N limit 1;
      if v_body is null or position(bN::text in v_body) > 0 or position(inc_n::text in v_body) > 0
         or position('iod_owner' in v_body) > 0 or position('사고견' in v_body) > 0
        then v_bad := v_bad || ' the body is missing or names someone: ' || coalesce(v_body, 'NULL'); end if;
    end if;
    if v_bad = '' then call _pass('iod','0234-I1 새 사고 한 건 → incident_opened 명부 1인에게 정확히 system 1행(「사고 접수 — 확인 필요」, ref_id = 사고), 본문은 누구도 이름 짓지 않고 당사자에게는 0');
    else v_msg := v_bad; call _fail('iod','0234-I1 one ops row per new incident', v_msg); end if;
  exception when others then call _fail('iod','0234-I1 one ops row per new incident', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-I2] severity is in the title
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    inc_u := (t_iod_open(rr, bU, 'lost_dog', 'urgent')->>'id')::uuid;
    inc_s := (t_iod_open(oo, bS, 'lost_dog', 'sos')->>'id')::uuid;
    if inc_u is null or inc_s is null then v_bad := v_bad || ' an open was refused';
    else
      if (select count(*) from notifications where ref_id = inc_u and title = T_U) is distinct from 1::bigint
         or (select count(*) from notifications where ref_id = inc_u and title in (T_N, T_S)) is distinct from 0::bigint
        then v_bad := v_bad || ' urgent: wrong title set'; end if;
      if (select count(*) from notifications where ref_id = inc_s and title = T_S) is distinct from 1::bigint
         or (select count(*) from notifications where ref_id = inc_s and title in (T_N, T_U)) is distinct from 0::bigint
        then v_bad := v_bad || ' sos: wrong title set'; end if;
    end if;
    if v_bad = '' then call _pass('iod','0234-I2 심각도가 제목에 있다 — urgent는 「긴급 사고 접수 — 확인 필요」, sos는 「SOS 사고 접수 — 즉시 확인 필요」 각 1행, 다른 사고 제목 0');
    else v_msg := v_bad; call _fail('iod','0234-I2 severity in title', v_msg); end if;
  exception when others then call _fail('iod','0234-I2 severity in title', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-I3] only a NEW incident rings; a failing bell never refuses the report
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_n from notifications where kind = 'system' and title in (T_N, T_U, T_S);
    v := t_iod_open(rr, bN, 'other', 'sos');                                  -- idempotent return
    if (v->>'id') is distinct from inc_n::text then v_bad := v_bad || ' idempotent open returned ' || v::text; end if;
    if (t_iod_open(sx, bE, 'other', 'sos')->>'raised') is distinct from 'not_party' then v_bad := v_bad || ' stranger not refused'; end if;
    if (t_iod_open(oo, bE, 'no_such_kind', 'sos')->>'raised') is distinct from 'bad_kind' then v_bad := v_bad || ' bad kind not refused'; end if;
    select count(*)::int into v_n2 from notifications where kind = 'system' and title in (T_N, T_U, T_S);
    if v_n2 is distinct from v_n then v_bad := v_bad || ' 🔴 a non-new open rang (' || v_n || ' → ' || v_n2 || ')'; end if;
    -- the forced bell failure, rolled back after measuring
    f_err := null;
    begin
      -- CONTROL, same shape and same severity WITHOUT the constraint: the bell DOES write one row.
      -- Without it, a world where the bell never existed would pass every arm below (no row, report
      -- stands) — measured: this pin was green on the pre-0234 tree before this control was added.
      g_id := t_iod_open(oo, bG, 'lost_dog', 'sos');
      select count(*)::int into g_rows from notifications where ref_id = (g_id->>'id')::uuid and title = T_S;
      alter table notifications add constraint iod_refuse_sos check (title is distinct from 'SOS 사고 접수 — 즉시 확인 필요') not valid;
      f_id := t_iod_open(oo, bF, 'lost_dog', 'sos');
      select count(*)::int into f_rows from notifications where ref_id = (f_id->>'id')::uuid;
      select count(*)::int into f_inc from incidents where id = (f_id->>'id')::uuid and booking_id = bF and resolved_at is null;
      raise exception 'iod_i3_rollback';
    exception when others then
      if sqlerrm is distinct from 'iod_i3_rollback' then f_err := sqlerrm; end if;
    end;
    if f_err is not null then v_bad := v_bad || ' staging raised: ' || f_err; end if;
    if g_rows is distinct from 1 then v_bad := v_bad || ' CONTROL: an unconstrained SOS open wrote ' || coalesce(g_rows::text, 'NULL') || ' bell row(s), not 1 — the staging proves nothing'; end if;
    if (f_id->>'id') is null then v_bad := v_bad || ' 🔴 the report was REFUSED when the bell failed: ' || coalesce(f_id::text, 'NULL'); end if;
    if f_inc is distinct from 1 then v_bad := v_bad || ' the incident row did not exist (' || coalesce(f_inc::text, 'NULL') || ')'; end if;
    if f_rows is distinct from 0 then v_bad := v_bad || ' STAGING: the bell was written anyway (' || coalesce(f_rows::text, 'NULL') || ') — the constraint did not bite'; end if;
    if v_bad = '' then call _pass('iod','0234-I3 새 사고만 울린다 — 같은 예약 두 번째 열기는 같은 id·행 추가 0, 낯선 사람(not_party)·잘못된 종류(bad_kind)도 0; 알림 insert가 실패해도(제약으로 강제, 롤백) SOS 신고는 id를 돌려주고 사고 행이 선다');
    else v_msg := v_bad; call _fail('iod','0234-I3 only new rings; bell failure never refuses', v_msg); end if;
  exception when others then call _fail('iod','0234-I3 only new rings; bell failure never refuses', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-I4] an empty roster pages nobody; the incident is still listed (rolled back after)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; e_err := null;
    begin
      update ops_recipients set active = false where event_class = 'incident_opened' and active;
      e_id := t_iod_open(oo, bE, 'equipment', 'normal');
      select count(*)::int into e_rows from notifications where ref_id = (e_id->>'id')::uuid;
      update ops_recipients set active = true where event_class = 'incident_opened' and profile_id = opsI;
      e_list := t_iod_list_as(opsI);
      raise exception 'iod_i4_rollback';
    exception when others then
      if sqlerrm is distinct from 'iod_i4_rollback' then e_err := sqlerrm; end if;
    end;
    if e_err is not null then v_bad := v_bad || ' raised: ' || e_err; end if;
    if (e_id->>'id') is null then v_bad := v_bad || ' open refused: ' || coalesce(e_id::text, 'NULL'); end if;
    if e_rows is distinct from 0 then v_bad := v_bad || ' 🔴 an empty roster wrote ' || coalesce(e_rows::text, 'NULL'); end if;
    if (e_list->'rows' ? (e_id->>'id')) is not true then v_bad := v_bad || ' the unpaged incident is not listed';
    elsif (e_list->'rows'->(e_id->>'id')->>'notified_at') is not null then v_bad := v_bad || ' unpaged incident shows notified_at'; end if;
    if (select count(*) from ops_recipients_for('incident_opened') x where x = opsI) is distinct from 1::bigint
      then v_bad := v_bad || ' the roster was not restored'; end if;
    if v_bad = '' then call _pass('iod','0234-I4 incident_opened 명부가 비면 아무도 호출되지 않고(0행) 신고는 선다 — 그 사고는 목록에 notified_at NULL로 나온다 (측정 후 롤백, 명부 복원 확인)');
    else v_msg := v_bad; call _fail('iod','0234-I4 empty roster', v_msg); end if;
  exception when others then call _fail('iod','0234-I4 empty roster', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-B2] the written titles are ledgered, ops, not urgent
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(distinct title)::int into v_n from notifications where kind = 'system' and ref_id in (inc_n, inc_u, inc_s);
    if v_n is distinct from 3 then v_bad := v_bad || ' FIXTURE: expected three distinct written titles, got ' || v_n; end if;
    for r in select distinct title from notifications where kind = 'system' and ref_id in (inc_n, inc_u, inc_s) loop
      if (r.title = any (_noti_ops_titles())) is not true then v_bad := v_bad || ' unledgered 「' || r.title || '」'; end if;
      if _noti_push_category('system', r.title) is distinct from 'ops' then v_bad := v_bad || ' 「' || r.title || '」 not ops'; end if;
      if (r.title = any (_noti_urgent_noti_titles())) is not false then v_bad := v_bad || ' 「' || r.title || '」 urgent'; end if;
    end loop;
    if v_bad = '' then call _pass('iod','0234-B2 open_incident_tx가 실제로 쓴 세 제목은 모두 _noti_ops_titles에 있고 ops로 분류되며 긴급 계열이 아니다');
    else v_msg := v_bad; call _fail('iod','0234-B2 titles ledgered', v_msg); end if;
  exception when others then call _fail('iod','0234-B2 titles ledgered', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-L1] ops_open_incidents refuses everyone off the incident_opened roster
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (t_iod_list_as(sx)->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' stranger: ' || left(t_iod_list_as(sx)::text, 80); end if;
    if (t_iod_list_as(opsP)->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' payout_due-only operator: ' || left(t_iod_list_as(opsP)::text, 80); end if;
    if (t_iod_list_as(oo)->>'raised') is distinct from 'not_ops' then v_bad := v_bad || ' the reporting party: ' || left(t_iod_list_as(oo)::text, 80); end if;
    if (t_iod_list_as(null)->>'raised') is distinct from 'not_signed_in' then v_bad := v_bad || ' no caller: ' || left(t_iod_list_as(null)::text, 80); end if;
    if v_bad = '' then call _pass('iod','0234-L1 ops_open_incidents — 낯선 사람·payout_due 전용 운영자·신고한 당사자는 not_ops, 호출자 없음은 not_signed_in');
    else v_msg := v_bad; call _fail('iod','0234-L1 non-roster refused', v_msg); end if;
  exception when others then call _fail('iod','0234-L1 non-roster refused', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-L2] for the operator: exactly the open incidents, SOS first
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    inc_r := (t_iod_open(oo, bR, 'other', 'normal')->>'id')::uuid;
    update incidents set resolved_at = now() where id = inc_r;
    v := t_iod_list_as(opsI);
    if v ? 'raised' then v_bad := v_bad || ' operator refused: ' || (v->>'raised');
    else
      foreach v_txt in array array[inc_n::text, inc_u::text, inc_s::text] loop
        if (v->'rows' ? v_txt) is not true then v_bad := v_bad || ' open incident ' || v_txt || ' not listed'; end if;
      end loop;
      if (v->'rows' ? inc_r::text) is not false then v_bad := v_bad || ' 🔴 a RESOLVED incident is listed'; end if;
      -- order: this suite's sos before urgent before normal
      select array_agg(x order by o) into v_keys
        from jsonb_array_elements_text(v->'order') with ordinality as t(x, o)
       where x in (inc_n::text, inc_u::text, inc_s::text);
      if v_keys is distinct from array[inc_s::text, inc_u::text, inc_n::text] then v_bad := v_bad || ' order=' || coalesce(v_keys::text, 'NULL'); end if;
      if (v->'rows'->inc_n::text->>'reporter_role') is distinct from 'owner'
         or (v->'rows'->inc_u::text->>'reporter_role') is distinct from 'runner'
        then v_bad := v_bad || ' reporter_role wrong'; end if;
      if (v->'rows'->inc_s::text->>'severity') is distinct from 'sos' or (v->'rows'->inc_s::text->>'booking_id') is distinct from bS::text
        then v_bad := v_bad || ' sos row fields wrong'; end if;
      if (v->'rows'->inc_n::text->>'notified_at') is null then v_bad := v_bad || ' belled incident has no notified_at'; end if;
      select array_agg(k order by k) into v_keys from jsonb_object_keys(v->'rows'->inc_n::text) k;
      if v_keys is distinct from (select array_agg(x order by x) from unnest(LIST_KEYS) x)
        then v_bad := v_bad || ' key set=' || coalesce(v_keys::text, 'NULL'); end if;
    end if;
    if v_bad = '' then call _pass('iod','0234-L2 incident_opened 운영자에게 열린 사고 전부(해결된 것 없음), SOS → 긴급 → 일반 순, 신고자 역할 owner/runner, 울린 사고는 notified_at, 키 집합 정확(메모·미디어 없음)');
    else v_msg := v_bad; call _fail('iod','0234-L2 open incidents for the operator', v_msg); end if;
  exception when others then call _fail('iod','0234-L2 open incidents for the operator', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0234-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach fn in array array['open_incident_tx(uuid,text,text,text,text[])', 'ops_open_incidents()',
                              'ops_roster_set(uuid,text,boolean)'] loop
      v_oid := to_regprocedure('public.' || fn);
      if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
      if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' ' || fn || ': not a definer'; end if;
      if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
        then v_bad := v_bad || ' ' || fn || ': no in-body search_path'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || fn || ': anon can execute'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true then v_bad := v_bad || ' ' || fn || ': authenticated cannot execute'; end if;
    end loop;
    if has_function_privilege('service_role', 'public.open_incident_tx(uuid,text,text,text,text[])', 'execute') is not true
      then v_bad := v_bad || ' open_incident_tx: service_role lost execute'; end if;
    if (select p.pronargs from pg_proc p where p.oid = to_regprocedure('public.ops_open_incidents()')) is distinct from 0::smallint
      then v_bad := v_bad || ' ops_open_incidents takes arguments'; end if;
    v_src := t_iod_src('ops_open_incidents');
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_open_incidents)';
    else
      p_a := position('ops_recipients_for(c_ops_class)' in v_src); p_b := position('from incidents' in v_src);
      if (p_a > 0 and p_b > 0 and p_a < p_b) is not true then v_bad := v_bad || ' read: the roster gate is not ahead of the read'; end if;
      if (v_src ~ 'c_ops_class\s+constant text := ''incident_opened''') is not true then v_bad := v_bad || ' read: not the incident_opened roster'; end if;
      if (v_src ~ 'i\.note|i\.media') is not false then v_bad := v_bad || ' 🔴 read carries note/media'; end if;
    end if;
    v_src := t_iod_src('open_incident_tx');
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(open_incident_tx)';
    else
      p_a := position('insert into incidents' in v_src); p_b := position('ops_recipients_for(c_ops_class)' in v_src);
      if (p_a > 0 and p_b > 0 and p_a < p_b) is not true then v_bad := v_bad || ' the bell does not follow the insert'; end if;
      if (position('exception when others' in v_src) > p_b) is not true then v_bad := v_bad || ' the bell has no handler of its own'; end if;
      if (position('raise exception ''not_party''' in v_src) < position('raise exception ''booking_not_reportable''' in v_src)
          and position('raise exception ''not_party''' in v_src) > 0) is not true
        then v_bad := v_bad || ' the party gate no longer precedes the state gate'; end if;
      if (v_src ~ 'c_ops_class\s+constant text := ''incident_opened''') is not true then v_bad := v_bad || ' the bell is not the incident_opened class'; end if;
    end if;
    v_src := t_iod_src('ops_roster_set');
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_roster_set)';
    else
      if (position('''incident_opened''' in v_src) > 0) is not true then v_bad := v_bad || ' ops_roster_set: no incident_opened'; end if;
      if (position('pg_advisory_xact_lock(hashtextextended(''ops_roster'', 0))' in v_src) > 0) is not true then v_bad := v_bad || ' ops_roster_set: 0216''s key lost'; end if;
    end if;
    if v_bad = '' then call _pass('iod','0234-S1 배포 형상 — 정의자 셋 모두 본문 search_path·유효 권한(anon ✗, authenticated ✓, open_incident_tx는 service_role ✓); 목록은 인자 0개, 주석 벗긴 소스에서 incident_opened 명부 게이트가 읽기보다 앞이고 note/media 없음; open_incident_tx의 벨은 insert 뒤·자기 핸들러 안, 당사자 게이트가 상태 게이트 앞; ops_roster_set은 0216 키를 유지하고 클래스를 안다');
    else v_msg := v_bad; call _fail('iod','0234-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('iod','0234-S1 deployed shape', sqlerrm); end;

  -- restore the roster world this suite found (fixture note ①)
  update ops_recipients set active = true where event_class = 'incident_opened' and profile_id = any (v_saved);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
