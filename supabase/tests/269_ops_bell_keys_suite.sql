-- ═══ 269 — 0238: no client can silence a SHIPPED ops bell or fake its instant on an ops list
-- ═══        0238-A1 · A2 · F1 · F2 · F3 · G1 · G2 · G3 · G4 · S1, tag `obk`
--
-- THE PROPOSITION, once, without reference to any mutation: **a row counts as 「this ops bell
-- already rang」 — for the sweep's one-shot, for a list's `notified_at`, and for a list's 「a bell
-- exists」 admission — only when it is kind `system` AND addressed to someone who is or was seated
-- at that bell's roster class.** Two production doors let a client write a look-alike otherwise:
--   ⓟ `noti party insert` (0114:273-283): a booking PARTY inserts `kind='booking'` rows with ANY
--      title and ANY `created_at` on a booking in the accepted set, addressed to either party.
--   ⓢ `noti self update` (0002:139, USING-only): ANY signed-in user rewrites one of their own rows'
--      kind / title / ref_id / created_at (WITH CHECK defaults to USING, so only `profile_id` is held).
-- Each pin plants BOTH shapes, and they are chosen so that each conjunct of the identity is
-- separately observable (264 `0233-B4`'s design):
--   · OPERATOR-OWNER look-alike (ⓟ): a seated operator of the bell's class who OWNS the booking
--     inserts `kind='booking'` + the bell's title, dated 2000-01-01. Its recipient IS on the roster,
--     so ONLY the `kind = 'system'` conjunct excludes it.
--   · STRANGER look-alike (ⓢ): a signed-in stranger rewrites one of their own rows to kind `system`,
--     the bell's title, the booking's id and 2000-01-01. Its kind IS system, so ONLY the recipient
--     conjunct excludes it.
-- Every forging write is asserted to have LANDED (exactly one row) before anything is read — a pin
-- over a fixture where the forge was refused would be green for the wrong reason.
--
--   · A1 **arm ⓐ's operator bell 「정산 미완료 — 확인 필요」 (payout_due).** A sealed-unsettled booking
--        carrying either look-alike still gets exactly ONE `system` row to the seated operator on the
--        next tick — like an untouched CONTROL booking — and a booking whose REAL bell rang on an
--        earlier tick gets NO second row (a real ring still suppresses; the identity is not so narrow
--        that it matches nothing).
--   · A2 **`ops_sealed_unsettled().notified_at`** is the real bell's instant for both forged
--        bookings (never 2000), and exactly the earlier tick's instant for the really-rung one.
--   · F1 **arm ⓕ's 「반환 좌초 — 확인 필요」 (return_strand)** — A1's proposition, candidate query
--        and in-lock re-check together.
--   · F2 **`ops_stranded_returns().notified_at`** — A2's, for arm ⓕ.
--   · F3 **`ops_stranded_returns()`'s 「a bell exists」 admission.** With the deadline switched off
--        (NULL), a strand carrying only a look-alike (either shape) is NOT listed, while a strand whose
--        real bell rang IS (the control that the admission still works).
--   · G1 / G2 **arm ⓖ's 「러닝 시작 좌초」 / 「러닝 종료 좌초 — 확인 필요」 (return_strand)** — A1's
--        proposition for each shape (the two in-lock re-checks are separate branches, so two pins).
--   · G3 **`ops_stranded_custody().notified_at`** for both shapes.
--   · G4 **`ops_stranded_custody()`'s admission** — F3's, with both custody thresholds NULL.
--   · S1 **DEPLOYED SHAPE.** Each re-declared function carries the identity at exactly the sites it
--        has (comment-stripped, counted), keyed on the RIGHT class constant; definers with in-body
--        search_path; ACLs both ways. NO-FUNCTION / NO-SOURCE fail loudly.
--
-- ─── GAPS (prose — the harness cannot separate these, so no pin claims them) ───
--   · The candidate query and the in-lock re-check of arms ⓕ / ⓖ each carry the identity; a single
--     session cannot stage the race the re-check exists for, but a SUPPRESSED bell is visible through
--     EITHER half (either half's exclusion alone keeps the row silent), so each conjunct IS separately
--     observable here — the battery in 0238's header measures each one (22 deletions, 22 reddened).
--   · The OPPOSITE error — a candidate query's identity made too NARROW (keyed on a class nobody
--     sits on) — is NOT observable here: the in-lock re-check still skips the really-rung row, so no
--     duplicate bell appears (battery W2: S1 alone). Its real cost is shadowing (rung rows stop
--     draining; past 50 they take every batch slot), which needs a 51-row fixture this suite does not
--     build. S1's per-function site count is the only guard. Both halves too narrow IS caught (W3).
--   · A seated operator of the class can still forge on their OWN row through ⓢ (kind system,
--     recipient on the roster) — the named residual 0233 §C already carries. No pin claims it closed.
--   · Party-addressed one-shots (「정산을 확인하고 있어요」, 「반환 확인이 멈춰 있어요」, 「러닝 시작이 /
--     종료가 멈춰 있어요」) are NOT ops bells and are NOT changed by 0238 — see its header §0c.
--
-- ─── FIXTURE NOTES ───
--  ① ONE staging world, rolled back at the end (`obk_rollback`), so flags, rosters, bookings and
--     every forged row leave nothing behind for a later suite. Pins read the captured values.
--  ② The sweep is global and batched (arms ⓕ/ⓖ `limit 50`, oldest first), so every fixture's clock
--     is ~3000 days old — older than anything another suite builds — and cannot be shadowed.
--  ③ Tick 1 runs BEFORE any forged booking exists (it rings the REAL-bell bookings only); tick 2
--     runs after every forge. Counts are scoped to this suite's bookings and to the ONE seated
--     operator of each class (other suites may have seated more).
set client_min_messages = warning;

-- a marketplace booking in one of four shapes, every clock ~3000 days old (fixture note ②)
--   sealed : active, run ended, both return stamps, settlement_ready_at set   → arm ⓐ
--   strand : active, run ended, only the runner's return stamp, not sealed    → arm ⓕ (+ ⓑ-②)
--   start  : picked_up, both handoff stamps, no run                           → arm ⓖ start_run
--   endrun : active, a run started and never stopped                          → arm ⓖ end_run
create or replace function t_obk_booking(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid, p_shape text)
returns uuid language plpgsql as $$
declare v uuid; t0 timestamptz := now() - interval '3000 days';
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at,
                        run_ended_at, runner_confirmed_return_at, owner_confirmed_return_at,
                        settlement_ready_at)
  values (p_owner, p_dog, p_runner, p_route,
          case p_shape when 'start' then 'picked_up' else 'active' end::booking_status,
          t0, 5.0, 9900, 15000, 0, 24900, 9900,
          t0 + interval '1 minute', t0 + interval '2 minutes',
          case when p_shape in ('sealed', 'strand') then t0 + interval '90 minutes' end,
          case when p_shape in ('sealed', 'strand') then t0 + interval '91 minutes' end,
          case when p_shape = 'sealed' then t0 + interval '92 minutes' end,
          case when p_shape = 'sealed' then t0 + interval '93 minutes' end)
  returning id into v;
  if p_shape in ('sealed', 'strand', 'endrun') then
    insert into runs (booking_id, started_at, trace) values (v, t0 + interval '3 minutes', '[]'::jsonb);
    if p_shape <> 'endrun' then update runs set ended_at = t0 + interval '90 minutes' where booking_id = v; end if;
  end if;
  return v;
end $$;

-- ⓟ: `p_uid` (a party of `p_booking`) inserts a kind='booking' look-alike AS authenticated.
-- Returns the number of rows that LANDED (1 = the door is open, which the pins require first).
create or replace function t_obk_forge_party(p_uid uuid, p_booking uuid, p_title text) returns int
language plpgsql as $$
declare v int;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)
  values (p_uid, 'booking', p_title, 'obk look-alike', p_booking, '2000-01-01');
  get diagnostics v = row_count;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

-- ⓢ: `p_uid` rewrites one of their OWN rows (seeded here as the server would) to kind system, the
-- bell's title, `p_booking` and 2000-01-01, AS authenticated. Returns the rows the UPDATE changed.
create or replace function t_obk_forge_self(p_uid uuid, p_booking uuid, p_title text) returns int
language plpgsql as $$
declare v int; v_id uuid;
begin
  insert into notifications (profile_id, kind, title, body) values (p_uid, 'booking', 'obk seed', 'x')
  returning id into v_id;
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  update notifications set kind = 'system', title = p_title, ref_id = p_booking, created_at = '2000-01-01'
   where id = v_id;
  get diagnostics v = row_count;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

-- `system` rows with this title on this booking, addressed to THIS operator
create or replace function t_obk_n(p_booking uuid, p_title text, p_ops uuid) returns int
language sql as $$
  select count(*)::int from notifications
   where ref_id = p_booking and title = p_title and kind = 'system' and profile_id = p_ops
$$;

-- the real bell's instant (the rows the sweep wrote to this operator)
create or replace function t_obk_at(p_booking uuid, p_title text, p_ops uuid) returns timestamptz
language sql as $$
  select min(created_at) from notifications
   where ref_id = p_booking and title = p_title and kind = 'system' and profile_id = p_ops
$$;

-- an ops list as ONE caller: rows keyed by booking id, OR the raise word
create or replace function t_obk_list(p_fn text, p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    execute format('select coalesce(jsonb_object_agg(x.booking_id::text, to_jsonb(x)), ''{}''::jsonb) from %I() x', p_fn)
      into v;
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('rows', v);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_obk_src(p_name text) returns text
language sql stable as $$
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;

do $$
declare
  oo uuid; sx uuid; opsR uuid; opsP uuid; rr uuid; dg uuid; rt uuid;
  T_SEAL  constant text := '정산 미완료 — 확인 필요';
  T_STR   constant text := '반환 좌초 — 확인 필요';
  T_START constant text := '러닝 시작 좌초 — 확인 필요';
  T_END   constant text := '러닝 종료 좌초 — 확인 필요';
  -- bookings
  aReal uuid; aOp uuid; aSt uuid; aCtl uuid;
  fReal uuid; fOp uuid; fSt uuid; fCtl uuid; fNbOp uuid; fNbSt uuid;
  gsReal uuid; gsOp uuid; gsSt uuid; gsCtl uuid;
  geReal uuid; geOp uuid; geSt uuid; geCtl uuid; gNbOp uuid; gNbSt uuid;
  -- captured world
  w jsonb := '{}'::jsonb;        -- counts and instants, keyed by name
  forged jsonb := '{}'::jsonb;   -- rows landed per forging write
  lSeal jsonb; lRet jsonb; lCus jsonb; lRetNull jsonb; lCusNull jsonb;
  stage_err text;
  -- scratch
  v_bad text; v_msg text; v_n int; v_src text; v_oid oid; fn text; k text; v_txt text;
  r record;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    oo   := t_user('obk_owner', 'owner');
    sx   := t_user('obk_stranger', 'owner');
    opsR := t_user('obk_ops_ret', 'owner');
    opsP := t_user('obk_ops_pay', 'owner');
    rr   := t_user('obk_runner', 'runner');
    dg   := t_dog(oo, 'obk 견');
    rt   := t_route('obk 코스');
    insert into ops_recipients (profile_id, event_class, active) values (opsR, 'return_strand', true)
    on conflict (profile_id, event_class) do update set active = true;
    insert into ops_recipients (profile_id, event_class, active) values (opsP, 'payout_due', true)
    on conflict (profile_id, event_class) do update set active = true;
    -- every threshold ON for the ticks (rolled back with everything else)
    update ops_flags set return_strand_minutes = 60, custody_start_strand_minutes = 30,
                         custody_end_strand_minutes = 30 where id;

    -- ── tick 1: only the REAL-bell bookings exist ──────────────────────────────────────────────
    aReal  := t_obk_booking(oo, rr, dg, rt, 'sealed');
    fReal  := t_obk_booking(oo, rr, dg, rt, 'strand');
    gsReal := t_obk_booking(oo, rr, dg, rt, 'start');
    geReal := t_obk_booking(oo, rr, dg, rt, 'endrun');
    perform sweep_run_end_recovery();
    w := w || jsonb_build_object(
      'aReal1', t_obk_n(aReal, T_SEAL, opsP),  'aRealAt', t_obk_at(aReal, T_SEAL, opsP),
      'fReal1', t_obk_n(fReal, T_STR, opsR),   'fRealAt', t_obk_at(fReal, T_STR, opsR),
      'gsReal1', t_obk_n(gsReal, T_START, opsR), 'gsRealAt', t_obk_at(gsReal, T_START, opsR),
      'geReal1', t_obk_n(geReal, T_END, opsR),   'geRealAt', t_obk_at(geReal, T_END, opsR));

    -- ── the forged world ─────────────────────────────────────────────────────────────────────
    aOp  := t_obk_booking(opsP, rr, dg, rt, 'sealed');  aSt  := t_obk_booking(oo, rr, dg, rt, 'sealed');
    aCtl := t_obk_booking(oo, rr, dg, rt, 'sealed');
    fOp  := t_obk_booking(opsR, rr, dg, rt, 'strand');  fSt  := t_obk_booking(oo, rr, dg, rt, 'strand');
    fCtl := t_obk_booking(oo, rr, dg, rt, 'strand');
    gsOp := t_obk_booking(opsR, rr, dg, rt, 'start');   gsSt := t_obk_booking(oo, rr, dg, rt, 'start');
    gsCtl := t_obk_booking(oo, rr, dg, rt, 'start');
    geOp := t_obk_booking(opsR, rr, dg, rt, 'endrun');  geSt := t_obk_booking(oo, rr, dg, rt, 'endrun');
    geCtl := t_obk_booking(oo, rr, dg, rt, 'endrun');
    forged := jsonb_build_object(
      'aOp',  t_obk_forge_party(opsP, aOp, T_SEAL),   'aSt',  t_obk_forge_self(sx, aSt, T_SEAL),
      'fOp',  t_obk_forge_party(opsR, fOp, T_STR),    'fSt',  t_obk_forge_self(sx, fSt, T_STR),
      'gsOp', t_obk_forge_party(opsR, gsOp, T_START), 'gsSt', t_obk_forge_self(sx, gsSt, T_START),
      'geOp', t_obk_forge_party(opsR, geOp, T_END),   'geSt', t_obk_forge_self(sx, geSt, T_END));
    -- no real bell on any of them yet (a delta the tick causes)
    w := w || jsonb_build_object('pre',
      t_obk_n(aOp, T_SEAL, opsP) + t_obk_n(aSt, T_SEAL, opsP) + t_obk_n(aCtl, T_SEAL, opsP)
      + t_obk_n(fOp, T_STR, opsR) + t_obk_n(fSt, T_STR, opsR) + t_obk_n(fCtl, T_STR, opsR)
      + t_obk_n(gsOp, T_START, opsR) + t_obk_n(gsSt, T_START, opsR) + t_obk_n(gsCtl, T_START, opsR)
      + t_obk_n(geOp, T_END, opsR) + t_obk_n(geSt, T_END, opsR) + t_obk_n(geCtl, T_END, opsR));

    -- ── tick 2 ───────────────────────────────────────────────────────────────────────────────
    perform sweep_run_end_recovery();
    w := w || jsonb_build_object(
      'aReal2', t_obk_n(aReal, T_SEAL, opsP), 'aOp', t_obk_n(aOp, T_SEAL, opsP),
      'aSt', t_obk_n(aSt, T_SEAL, opsP), 'aCtl', t_obk_n(aCtl, T_SEAL, opsP),
      'aOpAt', t_obk_at(aOp, T_SEAL, opsP), 'aStAt', t_obk_at(aSt, T_SEAL, opsP),
      'fReal2', t_obk_n(fReal, T_STR, opsR), 'fOp', t_obk_n(fOp, T_STR, opsR),
      'fSt', t_obk_n(fSt, T_STR, opsR), 'fCtl', t_obk_n(fCtl, T_STR, opsR),
      'fOpAt', t_obk_at(fOp, T_STR, opsR), 'fStAt', t_obk_at(fSt, T_STR, opsR),
      'gsReal2', t_obk_n(gsReal, T_START, opsR), 'gsOp', t_obk_n(gsOp, T_START, opsR),
      'gsSt', t_obk_n(gsSt, T_START, opsR), 'gsCtl', t_obk_n(gsCtl, T_START, opsR),
      'gsOpAt', t_obk_at(gsOp, T_START, opsR), 'gsStAt', t_obk_at(gsSt, T_START, opsR),
      'geReal2', t_obk_n(geReal, T_END, opsR), 'geOp', t_obk_n(geOp, T_END, opsR),
      'geSt', t_obk_n(geSt, T_END, opsR), 'geCtl', t_obk_n(geCtl, T_END, opsR),
      'geOpAt', t_obk_at(geOp, T_END, opsR), 'geStAt', t_obk_at(geSt, T_END, opsR));
    lSeal := t_obk_list('ops_sealed_unsettled', opsP);
    lRet  := t_obk_list('ops_stranded_returns', opsR);
    lCus  := t_obk_list('ops_stranded_custody', opsR);

    -- ── the admission world: every deadline OFF, then look-alikes on fresh never-rung rows ──────
    update ops_flags set return_strand_minutes = null, custody_start_strand_minutes = null,
                         custody_end_strand_minutes = null where id;
    fNbOp := t_obk_booking(opsR, rr, dg, rt, 'strand');  fNbSt := t_obk_booking(oo, rr, dg, rt, 'strand');
    gNbOp := t_obk_booking(opsR, rr, dg, rt, 'start');   gNbSt := t_obk_booking(oo, rr, dg, rt, 'start');
    forged := forged || jsonb_build_object(
      'fNbOp', t_obk_forge_party(opsR, fNbOp, T_STR),   'fNbSt', t_obk_forge_self(sx, fNbSt, T_STR),
      'gNbOp', t_obk_forge_party(opsR, gNbOp, T_START), 'gNbSt', t_obk_forge_self(sx, gNbSt, T_START));
    lRetNull := t_obk_list('ops_stranded_returns', opsR);
    lCusNull := t_obk_list('ops_stranded_custody', opsR);
    raise exception 'obk_rollback';
  exception when others then
    if sqlerrm is distinct from 'obk_rollback' then stage_err := sqlerrm; end if;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-A1] arm ⓐ's operator bell: a look-alike does not silence it; a real ring still does
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if (forged->>'aOp') is distinct from '1' or (forged->>'aSt') is distinct from '1'
      then v_bad := v_bad || ' FIXTURE: a forging write did not land (' || coalesce(forged->>'aOp', 'NULL') || '/' || coalesce(forged->>'aSt', 'NULL') || ') — the pin would prove nothing'; end if;
    if (w->>'aReal1') is distinct from '1' then v_bad := v_bad || ' FIXTURE: tick 1 did not ring the real-bell booking (' || coalesce(w->>'aReal1', 'NULL') || ')'; end if;
    if (w->>'pre') is distinct from '0' then v_bad := v_bad || ' FIXTURE: a real bell existed on a forged booking before tick 2 (' || coalesce(w->>'pre', 'NULL') || ')'; end if;
    if (w->>'aCtl') is distinct from '1' then v_bad := v_bad || ' CONTROL: the untouched booking got ' || coalesce(w->>'aCtl', 'NULL') || ' (1) — the tick proves nothing'; end if;
    if (w->>'aOp') is distinct from '1' then v_bad := v_bad || ' 🔴 the operator-owner''s kind=booking look-alike silenced the bell (' || coalesce(w->>'aOp', 'NULL') || ')'; end if;
    if (w->>'aSt') is distinct from '1' then v_bad := v_bad || ' 🔴 the stranger''s rewritten system row silenced the bell (' || coalesce(w->>'aSt', 'NULL') || ')'; end if;
    if (w->>'aReal2') is distinct from '1' then v_bad := v_bad || ' 🔴 a REAL earlier ring did not suppress: ' || coalesce(w->>'aReal2', 'NULL') || ' rows (1)'; end if;
    if v_bad = '' then call _pass('obk','0238-A1 arm ⓐ 「정산 미완료 — 확인 필요」: the operator-owner''s kind=booking look-alike (party insert) and a stranger''s row rewritten to system (self update), each asserted landed, do not silence the bell — one system row each, like the control — and a real earlier ring still suppresses (rolled back)');
    else v_msg := v_bad; call _fail('obk','0238-A1 seal bell identity', v_msg); end if;
  exception when others then call _fail('obk','0238-A1 seal bell identity', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-A2] ops_sealed_unsettled.notified_at is the real bell's instant
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if lSeal is null or lSeal ? 'raised' then v_bad := v_bad || ' list: ' || coalesce(lSeal::text, 'NULL');
    else
      for r in select * from (values (aOp::text, w->>'aOpAt'), (aSt::text, w->>'aStAt'), (aReal::text, w->>'aRealAt')) x(id, real_at) loop
        if (lSeal->'rows'->r.id) is null then v_bad := v_bad || ' ' || r.id || ' not listed';
        elsif r.real_at is null then v_bad := v_bad || ' FIXTURE: ' || r.id || ' has no real bell';
        elsif ((lSeal->'rows'->r.id->>'notified_at')::timestamptz = r.real_at::timestamptz) is not true
          then v_bad := v_bad || ' 🔴 ' || r.id || ' notified_at=' || coalesce(lSeal->'rows'->r.id->>'notified_at', 'NULL') || ' — not the real bell''s instant ' || r.real_at; end if;
      end loop;
    end if;
    if v_bad = '' then call _pass('obk','0238-A2 ops_sealed_unsettled: notified_at is the real bell''s instant for both forged bookings (never the forged 2000-01-01) and for the really-rung one');
    else v_msg := v_bad; call _fail('obk','0238-A2 sealed notified_at', v_msg); end if;
  exception when others then call _fail('obk','0238-A2 sealed notified_at', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-F1] arm ⓕ's strand bell
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if (forged->>'fOp') is distinct from '1' or (forged->>'fSt') is distinct from '1'
      then v_bad := v_bad || ' FIXTURE: a forging write did not land (' || coalesce(forged->>'fOp', 'NULL') || '/' || coalesce(forged->>'fSt', 'NULL') || ')'; end if;
    if (w->>'fReal1') is distinct from '1' then v_bad := v_bad || ' FIXTURE: tick 1 did not ring the real-bell strand (' || coalesce(w->>'fReal1', 'NULL') || ')'; end if;
    if (w->>'pre') is distinct from '0' then v_bad := v_bad || ' FIXTURE: pre=' || coalesce(w->>'pre', 'NULL'); end if;
    if (w->>'fCtl') is distinct from '1' then v_bad := v_bad || ' CONTROL: the untouched strand got ' || coalesce(w->>'fCtl', 'NULL') || ' (1)'; end if;
    if (w->>'fOp') is distinct from '1' then v_bad := v_bad || ' 🔴 the operator-owner''s look-alike silenced the strand bell (' || coalesce(w->>'fOp', 'NULL') || ')'; end if;
    if (w->>'fSt') is distinct from '1' then v_bad := v_bad || ' 🔴 the stranger''s system row silenced the strand bell (' || coalesce(w->>'fSt', 'NULL') || ')'; end if;
    if (w->>'fReal2') is distinct from '1' then v_bad := v_bad || ' 🔴 a REAL earlier ring did not suppress: ' || coalesce(w->>'fReal2', 'NULL') || ' rows (1)'; end if;
    if v_bad = '' then call _pass('obk','0238-F1 arm ⓕ 「반환 좌초 — 확인 필요」: neither look-alike silences the return_strand bell (one system row each, like the control); a real earlier ring still suppresses (rolled back)');
    else v_msg := v_bad; call _fail('obk','0238-F1 strand bell identity', v_msg); end if;
  exception when others then call _fail('obk','0238-F1 strand bell identity', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-F2] ops_stranded_returns.notified_at
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if lRet is null or lRet ? 'raised' then v_bad := v_bad || ' list: ' || coalesce(lRet::text, 'NULL');
    else
      for r in select * from (values (fOp::text, w->>'fOpAt'), (fSt::text, w->>'fStAt'), (fReal::text, w->>'fRealAt')) x(id, real_at) loop
        if (lRet->'rows'->r.id) is null then v_bad := v_bad || ' ' || r.id || ' not listed';
        elsif r.real_at is null then v_bad := v_bad || ' FIXTURE: ' || r.id || ' has no real bell';
        elsif ((lRet->'rows'->r.id->>'notified_at')::timestamptz = r.real_at::timestamptz) is not true
          then v_bad := v_bad || ' 🔴 ' || r.id || ' notified_at=' || coalesce(lRet->'rows'->r.id->>'notified_at', 'NULL') || ' — not the real bell''s instant ' || r.real_at; end if;
      end loop;
    end if;
    if v_bad = '' then call _pass('obk','0238-F2 ops_stranded_returns: notified_at is the real strand bell''s instant for both forged bookings and the really-rung one');
    else v_msg := v_bad; call _fail('obk','0238-F2 returns notified_at', v_msg); end if;
  exception when others then call _fail('obk','0238-F2 returns notified_at', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-F3] ops_stranded_returns' 「a bell exists」 admission
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if (forged->>'fNbOp') is distinct from '1' or (forged->>'fNbSt') is distinct from '1'
      then v_bad := v_bad || ' FIXTURE: a forging write did not land (' || coalesce(forged->>'fNbOp', 'NULL') || '/' || coalesce(forged->>'fNbSt', 'NULL') || ')'; end if;
    if lRetNull is null or lRetNull ? 'raised' then v_bad := v_bad || ' list: ' || coalesce(lRetNull::text, 'NULL');
    else
      if (lRetNull->'rows'->fReal::text) is null then v_bad := v_bad || ' CONTROL: the really-rung strand is not listed with the deadline off — the admission proves nothing'; end if;
      if (lRetNull->'rows'->fNbOp::text) is not null then v_bad := v_bad || ' 🔴 the operator-owner''s look-alike put a never-rung strand on the list'; end if;
      if (lRetNull->'rows'->fNbSt::text) is not null then v_bad := v_bad || ' 🔴 the stranger''s system row put a never-rung strand on the list'; end if;
    end if;
    if v_bad = '' then call _pass('obk','0238-F3 ops_stranded_returns with the deadline off: a never-rung strand carrying either look-alike is NOT listed; the really-rung strand IS');
    else v_msg := v_bad; call _fail('obk','0238-F3 returns admission', v_msg); end if;
  exception when others then call _fail('obk','0238-F3 returns admission', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-G1] arm ⓖ start_run bell · [0238-G2] arm ⓖ end_run bell
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  foreach k in array array['gs', 'ge'] loop
    begin
      v_bad := '';
      v_txt := case k when 'gs' then '0238-G1 custody start bell identity' else '0238-G2 custody end bell identity' end;
      if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
      if (forged->>(k || 'Op')) is distinct from '1' or (forged->>(k || 'St')) is distinct from '1'
        then v_bad := v_bad || ' FIXTURE: a forging write did not land (' || coalesce(forged->>(k || 'Op'), 'NULL') || '/' || coalesce(forged->>(k || 'St'), 'NULL') || ')'; end if;
      if (w->>(k || 'Real1')) is distinct from '1' then v_bad := v_bad || ' FIXTURE: tick 1 did not ring the real-bell custody (' || coalesce(w->>(k || 'Real1'), 'NULL') || ')'; end if;
      if (w->>'pre') is distinct from '0' then v_bad := v_bad || ' FIXTURE: pre=' || coalesce(w->>'pre', 'NULL'); end if;
      if (w->>(k || 'Ctl')) is distinct from '1' then v_bad := v_bad || ' CONTROL: the untouched custody got ' || coalesce(w->>(k || 'Ctl'), 'NULL') || ' (1)'; end if;
      if (w->>(k || 'Op')) is distinct from '1' then v_bad := v_bad || ' 🔴 the operator-owner''s look-alike silenced the bell (' || coalesce(w->>(k || 'Op'), 'NULL') || ')'; end if;
      if (w->>(k || 'St')) is distinct from '1' then v_bad := v_bad || ' 🔴 the stranger''s system row silenced the bell (' || coalesce(w->>(k || 'St'), 'NULL') || ')'; end if;
      if (w->>(k || 'Real2')) is distinct from '1' then v_bad := v_bad || ' 🔴 a REAL earlier ring did not suppress: ' || coalesce(w->>(k || 'Real2'), 'NULL') || ' rows (1)'; end if;
      if v_bad = '' then call _pass('obk', split_part(v_txt, ' ', 1) || ' arm ⓖ ' || case k when 'gs' then '「러닝 시작 좌초」' else '「러닝 종료 좌초」' end
                                     || ': neither look-alike silences the return_strand bell (one system row each, like the control); a real earlier ring still suppresses (rolled back)');
      else v_msg := v_bad; call _fail('obk', v_txt, v_msg); end if;
    exception when others then call _fail('obk', v_txt, sqlerrm); end;
  end loop;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-G3] ops_stranded_custody.notified_at, both shapes
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if lCus is null or lCus ? 'raised' then v_bad := v_bad || ' list: ' || coalesce(lCus::text, 'NULL');
    else
      for r in select * from (values (gsOp::text, w->>'gsOpAt'), (gsSt::text, w->>'gsStAt'), (gsReal::text, w->>'gsRealAt'),
                                      (geOp::text, w->>'geOpAt'), (geSt::text, w->>'geStAt'), (geReal::text, w->>'geRealAt')) x(id, real_at) loop
        if (lCus->'rows'->r.id) is null then v_bad := v_bad || ' ' || r.id || ' not listed';
        elsif r.real_at is null then v_bad := v_bad || ' FIXTURE: ' || r.id || ' has no real bell';
        elsif ((lCus->'rows'->r.id->>'notified_at')::timestamptz = r.real_at::timestamptz) is not true
          then v_bad := v_bad || ' 🔴 ' || r.id || ' notified_at=' || coalesce(lCus->'rows'->r.id->>'notified_at', 'NULL') || ' — not the real bell''s instant ' || r.real_at; end if;
      end loop;
    end if;
    if v_bad = '' then call _pass('obk','0238-G3 ops_stranded_custody: notified_at is the real custody bell''s instant for both forged bookings of each shape and for the really-rung ones');
    else v_msg := v_bad; call _fail('obk','0238-G3 custody notified_at', v_msg); end if;
  exception when others then call _fail('obk','0238-G3 custody notified_at', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-G4] ops_stranded_custody's 「a bell exists」 admission
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if stage_err is not null then v_bad := v_bad || ' staging raised: ' || stage_err; end if;
    if (forged->>'gNbOp') is distinct from '1' or (forged->>'gNbSt') is distinct from '1'
      then v_bad := v_bad || ' FIXTURE: a forging write did not land (' || coalesce(forged->>'gNbOp', 'NULL') || '/' || coalesce(forged->>'gNbSt', 'NULL') || ')'; end if;
    if lCusNull is null or lCusNull ? 'raised' then v_bad := v_bad || ' list: ' || coalesce(lCusNull::text, 'NULL');
    else
      if (lCusNull->'rows'->gsReal::text) is null then v_bad := v_bad || ' CONTROL: the really-rung custody is not listed with the thresholds off — the admission proves nothing'; end if;
      if (lCusNull->'rows'->gNbOp::text) is not null then v_bad := v_bad || ' 🔴 the operator-owner''s look-alike put a never-rung custody on the list'; end if;
      if (lCusNull->'rows'->gNbSt::text) is not null then v_bad := v_bad || ' 🔴 the stranger''s system row put a never-rung custody on the list'; end if;
    end if;
    if v_bad = '' then call _pass('obk','0238-G4 ops_stranded_custody with both thresholds off: a never-rung custody carrying either look-alike is NOT listed; the really-rung one IS');
    else v_msg := v_bad; call _fail('obk','0238-G4 custody admission', v_msg); end if;
  exception when others then call _fail('obk','0238-G4 custody admission', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0238-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    for r in select * from (values
        ('sweep_run_end_recovery',  'c_seal_ops_class',   1, false),
        ('sweep_run_end_recovery',  'c_strand_ops_class', 2, false),
        ('_sweep_custody_strands',  'c_ops_class',        3, false),
        ('ops_stranded_custody',    'c_ops_class',        2, true),
        ('ops_sealed_unsettled',    'c_ops_class',        1, true),
        ('ops_stranded_returns',    'c_ops_class',        2, true)) x(fn, cls, n, is_read) loop
      v_oid := to_regprocedure('public.' || r.fn || '()');
      if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || r.fn || ')'; continue; end if;
      v_src := t_obk_src(r.fn);
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || r.fn || ')'; continue; end if;
      -- whitespace collapsed; the identity spelled as ONE unit, so a site missing either conjunct
      -- does not count toward the site total
      v_src := regexp_replace(v_src, '\s+', ' ', 'g');
      select count(*)::int into v_n from regexp_matches(v_src,
        'and nt\.kind = ''system'' and exists \(select 1 from ops_recipients orr where orr\.profile_id = nt\.profile_id and orr\.event_class = ' || r.cls || '\)', 'g');
      if v_n is distinct from r.n then v_bad := v_bad || ' ' || r.fn || ': ' || v_n || ' identity site(s) on ' || r.cls || ' (' || r.n || ')'; end if;
      if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' ' || r.fn || ': not a definer'; end if;
      if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
        then v_bad := v_bad || ' ' || r.fn || ': no in-body search_path'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || r.fn || ': anon can execute'; end if;
      if r.is_read then
        if has_function_privilege('authenticated', v_oid, 'execute') is not true then v_bad := v_bad || ' ' || r.fn || ': authenticated cannot execute (a dead door)'; end if;
      else
        if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || r.fn || ': authenticated can execute (server-only)'; end if;
        if has_function_privilege('service_role', v_oid, 'execute') is not true then v_bad := v_bad || ' ' || r.fn || ': service_role cannot execute'; end if;
      end if;
    end loop;
    -- each class constant still names the roster the bell rings (a wrong constant would key the
    -- identity on a roster nobody who received the bell sits on)
    for r in select * from (values
        ('sweep_run_end_recovery', 'c_seal_ops_class',   'payout_due'),
        ('sweep_run_end_recovery', 'c_strand_ops_class', 'return_strand'),
        ('_sweep_custody_strands', 'c_ops_class',        'return_strand'),
        ('ops_stranded_custody',   'c_ops_class',        'return_strand'),
        ('ops_sealed_unsettled',   'c_ops_class',        'payout_due'),
        ('ops_stranded_returns',   'c_ops_class',        'return_strand')) x(fn, cls, val) loop
      v_src := t_obk_src(r.fn);
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || r.fn || ')'; continue; end if;
      if (v_src ~ (r.cls || '\s+constant text := ''' || r.val || '''')) is not true
        then v_bad := v_bad || ' ' || r.fn || ': ' || r.cls || ' is not ''' || r.val || ''''; end if;
    end loop;
    if v_bad = '' then call _pass('obk','0238-S1 deployed shape — the bell identity (kind system AND a recipient who is or was seated) at exactly 1+2 sites of sweep_run_end_recovery, 3 of _sweep_custody_strands, 2 of ops_stranded_custody, 1 of ops_sealed_unsettled, 2 of ops_stranded_returns (comment-stripped), each keyed on the class its bell rings; definers with in-body search_path; ACLs both ways');
    else v_msg := v_bad; call _fail('obk','0238-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('obk','0238-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
