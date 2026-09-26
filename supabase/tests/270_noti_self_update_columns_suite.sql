-- ═══ 270 — 0239: a client may mark its own notifications READ, and may change nothing else
-- ═══        0239-C1 · C2 · C3 · C4 · D1 · W1 · M1 · S1, tag `nsu`
--
-- THE PROPOSITION, once, without reference to any mutation: **a signed-in client's UPDATE of
-- `notifications` can touch only its OWN rows, can write only `read_at`, can never leave a row
-- unread, and can never move a row to someone else — while every legitimate writer (the three
-- client mark-read wrappers, the definer RPCs, the sweeps, service_role) still works.**
--
--   · C1 **EVERY FORBIDDEN COLUMN IS REFUSED.** For EVERY column of the table enumerated from the
--        catalog except `read_at` (a FIXTURE arm asserts the enumeration found the nine known columns,
--        so an empty loop cannot pass), the row's OWNER, as `authenticated`, runs
--        `update … set <col> = <col>` on their own row → SQLSTATE 42501 `permission denied`. Plus the
--        forge 0238 recorded — kind `system`, an ops title, another booking's id, `created_at`
--        2000-01-01 — refused, and a mixed `set read_at, kind` refused whole; the row is read back
--        byte-identical. On the base (0239 absent) every one of these LANDS.
--        ⚠ The row is an already-READ row, on purpose: on an UNREAD row the WITH CHECK's
--        `read_at is not null` also refuses every one of these writes (42501, `row-level security`),
--        so the first battery's broad-grant plant left the forges refused and the pins green-by-
--        message only. On a read row the GRANT is the only wall, and the message must say so.
--   · C2 **`read_at` IS STILL WRITABLE.** The owner marks their own row read: exactly 1 row, read_at
--        NULL → set, every other column unchanged.
--   · C3 **NO RE-ADDRESSING, NO REACH.** `set profile_id = <another user>` on one's own row is
--        refused (42501) — both FILTERED (`where id = …`) and UNFILTERED (`where $1 is not null`, no
--        column read); `set read_at` on ANOTHER user's row changes 0 rows and leaves it unread; an
--        UNFILTERED `set read_at` changes exactly the caller's one unread row and not the other
--        user's. ⚠ The unfiltered arms exist because PostgreSQL applies the SELECT policy (`noti
--        self`) to both the old AND the new row of any UPDATE that reads a column — so every filtered
--        arm is also held by `noti self`, and neither the UPDATE policy's USING nor its WITH CHECK
--        profile conjunct is observable through one (measured: USING widened to `true` → 1641/0 with
--        filtered arms only). An UPDATE that reads no column skips SELECT policies, and that is the
--        shape through which those two conjuncts can be seen.
--        ⚠ This held on the base too — C3 is the control that 0239 did not LOSE it, not a reproduction.
--   · C4 **READ NEVER BECOMES UNREAD.** `set read_at = null` on one's own READ row is refused by the
--        WITH CHECK (42501, `row-level security`), and the row stays read. Lands on the base.
--   · D1 **A DEACTIVATED OPERATOR CAN NO LONGER SILENCE A BELL** — 0238 §0e's residual. A former
--        `return_strand` operator (seated, then `active = false`) tries 0238's forge on their own row
--        (kind system, 「반환 좌초 — 확인 필요」's title, a strand booking, 2000-01-01) → refused; one
--        sweep tick rings the ACTIVE operator exactly once for that booking, and
--        `ops_stranded_returns()` dates it with the real bell, never 2000. CONTROL (the reason the
--        refusal is what matters): the same look-alike PLANTED by the table owner on a twin strand
--        booking DOES silence it (0 rows to the active operator) — 0238's identity counts a former
--        operator's row by design (269 `0238-D1`), so the door is the only wall. On the base the
--        forge lands and the forged booking is silenced exactly like the control.
--   · W1 **SERVER WRITERS STILL WORK.** ⓐ a sweep tick rings a fresh strand booking: 0 → exactly 1
--        `system` row to the active operator; ⓑ `chat_mark_read(uuid)` called AS `authenticated`
--        (a definer — 0228 §B, the repo's only other UPDATE of the table beside 0228 §A) releases
--        the caller's unread 「새 메시지」 row written by the real `chat_messages_notify` trigger:
--        1 unread → 0 unread; ⓒ `service_role` rewrites a non-`read_at` column (title): 1 row.
--   · M1 **THE CLIENT'S THREE MARK-READ WRAPPERS, REPLAYED AS POSTGREST SENDS THEM.** `api.ts`
--        `markNotificationsReadByTap` (ref and ref-less), `markNotificationsRead(ids)` and
--        `markAllNotificationsRead` — each as PostgREST's `UPDATE … SET read_at = pgrst_body.read_at
--        FROM json_populate_record(…) … WHERE <the wrapper's filters> RETURNING 1`, run as
--        `authenticated` with the caller's claim. Each changes EXACTLY the caller's matching unread
--        rows (counted), never a stranger's same-titled unread row, never an already-read row's
--        instant.
--   · S1 **DEPLOYED SHAPE.** Per column: `authenticated` holds UPDATE on `read_at` only, `anon` on
--        none; `service_role` keeps table UPDATE; `noti self update` is the only UPDATE-capable
--        policy, is `TO authenticated`, and its WITH CHECK names both conjuncts; `noti party insert`
--        and `noti self` (select) are still present (0239 does not touch them); RLS is ENABLED on the
--        table (the precondition every policy arm reads). NO-TABLE / NO-POLICY fail loudly.
--
-- ─── GAPS (prose — no pin claims these) ───
--   · The WITH CHECK's `profile_id = auth.uid()` conjunct is NOT separately observable: a re-address
--     dies at the column grant first (and, filtered, at `noti self` on the new row), and if the grant
--     were widened AND the WITH CHECK dropped, PostgreSQL would reuse USING (`profile_id = auth.uid()`)
--     as the check. Defence in depth behind the grant; only a plant that widens the grant AND replaces
--     the check with `true` can redden C3's unfiltered re-address arm. S1 pins that it is written.
--   · PostgREST's exact SQL varies by version; M1 replays the documented shape (a `json_populate_record`
--     body, `RETURNING 1`), not a captured wire request. The property M1 needs — the statement names
--     only `read_at` in SET and reads id/title/ref_id/read_at in WHERE — is what the wrappers send.
--   · Nothing here pushes (`00_shim.sql` stubs `net.http_post`).
--
-- ─── FIXTURE NOTES ───
--  ① Every pin is its own rolled-back world (`nsu_rollback`); `ops_flags`, the roster and every row
--     leave nothing behind for a later suite.
--  ② Every role switch is asserted (`current_user`), and every refusal is matched on SQLSTATE AND the
--     message, so a pin cannot pass on an unrelated error.
--  ③ The strand fixture is 269's shape (clocks ~3000 days old, so the sweep's oldest-first batch
--     cannot shadow it). Bell counts are scoped to this suite's bookings and ONE active operator.
set client_min_messages = warning;

-- run ONE statement as `authenticated` with p_uid's claim; $1 = p_id. Returns {n} or {state,msg}.
create or replace function t_nsu_as(p_uid uuid, p_sql text, p_id uuid) returns jsonb
language plpgsql as $$
declare v int;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'nsu: role did not take'; end if;
  execute p_sql using p_id;
  get diagnostics v = row_count;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('n', v);
exception when others then
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('state', sqlstate, 'msg', sqlerrm);
end $$;

-- PostgREST's UPDATE shape for `.update({ read_at }).<filters>` with Prefer: return=minimal.
-- $1 = the JSON body, $2 = ids, $3 = title, $4 = ref_id. Returns {n} or {state,msg}.
create or replace function t_nsu_pgrst(p_uid uuid, p_where text, p_ids uuid[], p_title text, p_ref uuid)
returns jsonb language plpgsql as $$
declare v int;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'nsu: role did not take'; end if;
  execute
    'with pgrst_source as (
       update public.notifications set read_at = pgrst_body.read_at
         from (select $1 as json_data) pgrst_payload,
              lateral (select read_at from json_populate_record(null::public.notifications, pgrst_payload.json_data)) pgrst_body
        where ' || p_where || '
       returning 1)
     select count(*)::int from pgrst_source'
    into v
    using json_build_object('read_at', now()), p_ids, p_title, p_ref;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('n', v);
exception when others then
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('state', sqlstate, 'msg', sqlerrm);
end $$;

-- 269's strand shape (fixture note ③): active, run ended, only the runner's return stamp
create or replace function t_nsu_strand(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid)
returns uuid language plpgsql as $$
declare v uuid; t0 timestamptz := now() - interval '3000 days';
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at,
                        run_ended_at, runner_confirmed_return_at)
  values (p_owner, p_dog, p_runner, p_route, 'active', t0, 5.0, 9900, 15000, 0, 24900, 9900,
          t0 + interval '1 minute', t0 + interval '2 minutes',
          t0 + interval '90 minutes', t0 + interval '91 minutes')
  returning id into v;
  insert into runs (booking_id, started_at, ended_at, trace)
  values (v, t0 + interval '3 minutes', t0 + interval '90 minutes', '[]'::jsonb);
  return v;
end $$;

create or replace function t_nsu_bells(p_booking uuid, p_title text, p_ops uuid) returns int
language sql as $$
  select count(*)::int from notifications
   where ref_id = p_booking and title = p_title and kind = 'system' and profile_id = p_ops
$$;

-- ops_stranded_returns as ONE caller: rows keyed by booking id, OR the raise word
create or replace function t_nsu_returns(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  select coalesce(jsonb_object_agg(x.booking_id::text, to_jsonb(x)), '{}'::jsonb) into v
    from ops_stranded_returns() x;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('rows', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- a row as the server would write it (the table owner), returning its id
create or replace function t_nsu_row(p_uid uuid, p_title text, p_ref uuid, p_read boolean) returns uuid
language sql as $$
  insert into notifications (profile_id, kind, title, body, ref_id, read_at)
  values (p_uid, 'booking', p_title, 'nsu', p_ref, case when p_read then now() - interval '1 day' end)
  returning id
$$;

do $$
declare
  u uuid; x uuid; o uuid; rr uuid; dg uuid; rt uuid; opsA uuid; opsF uuid;
  T_STR constant text := '반환 좌초 — 확인 필요';
  nid uuid; nid2 uuid; nxid uuid; bk uuid; bk2 uuid; th uuid;
  before_row jsonb; after_row jsonb;
  j jsonb; w jsonb; v_bad text; v_msg text; v_n int; v_err text; v_txt text;
  r record; v_tbl oid; v_wc text; v_roles text;
  cols text[] := '{}';
  known constant text[] := array['id','profile_id','kind','title','body','ref_id','created_at','handoff_cycle_id'];
begin
  perform set_config('request.jwt.claim.sub', '', true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-C1] every forbidden column is refused (rolled back)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_err := null; w := '{}'::jsonb; cols := '{}';
    begin
      u := t_user('nsu_c1_u', 'owner'); o := t_user('nsu_c1_o', 'owner'); rr := t_user('nsu_c1_r', 'runner');
      dg := t_dog(o, 'nsu c1'); rt := t_route('nsu c1');
      bk := t_nsu_strand(o, rr, dg, rt);
      nid := t_nsu_row(u, 'nsu c1', null, true);   -- READ: the grant must be the only wall (header)
      select to_jsonb(n) into before_row from notifications n where n.id = nid;
      for r in select a.attname::text as col from pg_attribute a
                where a.attrelid = 'public.notifications'::regclass and a.attnum > 0 and not a.attisdropped
                  and a.attname <> 'read_at' order by a.attnum loop
        cols := cols || r.col;
        w := w || jsonb_build_object(r.col,
               t_nsu_as(u, format('update notifications set %I = %I where id = $1', r.col, r.col), nid));
      end loop;
      w := w || jsonb_build_object('_forge', t_nsu_as(u, format(
             'update notifications set kind = %L, title = %L, ref_id = %L, created_at = %L where id = $1',
             'system', T_STR, bk, '2000-01-01'), nid));
      w := w || jsonb_build_object('_mixed', t_nsu_as(u,
             'update notifications set read_at = now(), kind = ''system'' where id = $1', nid));
      select to_jsonb(n) into after_row from notifications n where n.id = nid;
      raise exception 'nsu_rollback';
    exception when others then
      if sqlerrm is distinct from 'nsu_rollback' then v_err := sqlerrm; end if;
    end;
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
    -- FIXTURE: the enumeration found every known column (an empty loop would pass vacuously)
    foreach v_txt in array known loop
      if (v_txt = any (cols)) is not true then v_bad := v_bad || ' FIXTURE: column ' || v_txt || ' not enumerated'; end if;
    end loop;
    foreach v_txt in array cols || array['_forge', '_mixed'] loop
      j := w->v_txt;
      if (j->>'state') is distinct from '42501' or (j->>'msg' ~ 'permission denied') is not true
        then v_bad := v_bad || ' 🔴 ' || v_txt || ': ' || coalesce(j::text, 'NULL') || ' (expected 42501 permission denied)'; end if;
    end loop;
    if after_row is distinct from before_row
      then v_bad := v_bad || ' 🔴 the row changed: ' || coalesce(after_row::text, 'NULL'); end if;
    if v_bad = '' then call _pass('nsu','0239-C1 행 주인이 authenticated로 read_at 외의 모든 컬럼(카탈로그 열거, 8개) 수정 시 42501 permission denied — kind system·운영 제목·다른 예약·2000-01-01 위조와 read_at+kind 동시 수정도 통째로 거부, 행은 그대로');
    else v_msg := v_bad; call _fail('nsu','0239-C1 forbidden columns refused', v_msg); end if;
  exception when others then reset role; call _fail('nsu','0239-C1 forbidden columns refused', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-C2] read_at is still writable (rolled back)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_err := null; j := null; before_row := null; after_row := null;
    begin
      u := t_user('nsu_c2_u', 'owner');
      nid := t_nsu_row(u, 'nsu c2', null, false);
      select to_jsonb(n) into before_row from notifications n where n.id = nid;
      j := t_nsu_as(u, 'update notifications set read_at = now() where id = $1', nid);
      select to_jsonb(n) into after_row from notifications n where n.id = nid;
      raise exception 'nsu_rollback';
    exception when others then
      if sqlerrm is distinct from 'nsu_rollback' then v_err := sqlerrm; end if;
    end;
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
    if (before_row->>'read_at') is not null then v_bad := v_bad || ' FIXTURE: the row was already read'; end if;
    if (j->>'n') is distinct from '1' then v_bad := v_bad || ' 🔴 mark-read: ' || coalesce(j::text, 'NULL') || ' (1 row)'; end if;
    if (after_row->>'read_at') is null then v_bad := v_bad || ' 🔴 read_at still NULL after the update'; end if;
    if (after_row - 'read_at') is distinct from (before_row - 'read_at')
      then v_bad := v_bad || ' 🔴 another column moved: ' || coalesce(after_row::text, 'NULL'); end if;
    if v_bad = '' then call _pass('nsu','0239-C2 자기 행의 read_at 표시는 그대로 된다 — 정확히 1행, NULL → 시각, 다른 컬럼 불변');
    else v_msg := v_bad; call _fail('nsu','0239-C2 read_at writable', v_msg); end if;
  exception when others then reset role; call _fail('nsu','0239-C2 read_at writable', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-C3] no re-addressing, no reach into another user's row (rolled back)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_err := null; w := '{}'::jsonb;
    begin
      u := t_user('nsu_c3_u', 'owner'); x := t_user('nsu_c3_x', 'owner');
      nid := t_nsu_row(u, 'nsu c3', null, false);
      nxid := t_nsu_row(x, 'nsu c3', null, false);
      w := w || jsonb_build_object('readdr', t_nsu_as(u, format('update notifications set profile_id = %L where id = $1', x), nid));
      -- unfiltered: reads no column, so no SELECT policy is applied (header, C3)
      w := w || jsonb_build_object('readdrAll', t_nsu_as(u, format('update notifications set profile_id = %L where $1::uuid is not null', x), nid));
      w := w || jsonb_build_object('reach', t_nsu_as(u, 'update notifications set read_at = now() where id = $1', nxid));
      w := w || jsonb_build_object('x_read0', (select read_at is not null from notifications where id = nxid));
      w := w || jsonb_build_object('reachAll', t_nsu_as(u, 'update notifications set read_at = now() where $1::uuid is not null', nid));
      w := w || jsonb_build_object('own_after', (select profile_id::text from notifications where id = nid),
                                   'own_read', (select read_at is not null from notifications where id = nid),
                                   'x_read', (select read_at is not null from notifications where id = nxid));
      raise exception 'nsu_rollback';
    exception when others then
      if sqlerrm is distinct from 'nsu_rollback' then v_err := sqlerrm; end if;
    end;
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
    if (w->'readdr'->>'state') is distinct from '42501'
      then v_bad := v_bad || ' 🔴 re-address: ' || coalesce((w->'readdr')::text, 'NULL') || ' (expected 42501)'; end if;
    if (w->'readdrAll'->>'state') is distinct from '42501'
      then v_bad := v_bad || ' 🔴 unfiltered re-address: ' || coalesce((w->'readdrAll')::text, 'NULL') || ' (expected 42501)'; end if;
    if (w->>'own_after') is distinct from u::text then v_bad := v_bad || ' 🔴 the row now belongs to ' || coalesce(w->>'own_after', 'NULL'); end if;
    if (w->'reach'->>'n') is distinct from '0' then v_bad := v_bad || ' 🔴 reach into another user''s row: ' || coalesce((w->'reach')::text, 'NULL') || ' (0 rows)'; end if;
    if (w->>'x_read0') is distinct from 'false' then v_bad := v_bad || ' 🔴 the filtered reach marked the other user''s row read'; end if;
    if (w->'reachAll'->>'n') is distinct from '1' then v_bad := v_bad || ' 🔴 unfiltered mark-read touched ' || coalesce((w->'reachAll')::text, 'NULL') || ' rows (exactly the caller''s 1)'; end if;
    if (w->>'own_read') is distinct from 'true' then v_bad := v_bad || ' FIXTURE: the unfiltered mark-read did not reach the caller''s own row'; end if;
    if (w->>'x_read') is distinct from 'false' then v_bad := v_bad || ' 🔴 the unfiltered mark-read marked the other user''s row read'; end if;
    if v_bad = '' then call _pass('nsu','0239-C3 자기 행을 남에게 넘기는 수정은 필터 유무 모두 42501 (' || coalesce(w->'readdr'->>'msg', '') || ' / ' || coalesce(w->'readdrAll'->>'msg', '') || '), 남의 행 read_at 수정은 0행, 필터 없는 읽음 표시는 자기 행 1개만 — 남의 행은 안 읽음 그대로');
    else v_msg := v_bad; call _fail('nsu','0239-C3 no re-address, no reach', v_msg); end if;
  exception when others then reset role; call _fail('nsu','0239-C3 no re-address, no reach', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-C4] read never becomes unread (rolled back)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_err := null; j := null; v_txt := null;
    begin
      u := t_user('nsu_c4_u', 'owner');
      nid := t_nsu_row(u, 'nsu c4', null, true);
      j := t_nsu_as(u, 'update notifications set read_at = null where id = $1', nid);
      select read_at::text into v_txt from notifications where id = nid;
      raise exception 'nsu_rollback';
    exception when others then
      if sqlerrm is distinct from 'nsu_rollback' then v_err := sqlerrm; end if;
    end;
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
    if (j->>'state') is distinct from '42501' or (j->>'msg' ~ 'row-level security') is not true
      then v_bad := v_bad || ' 🔴 un-read: ' || coalesce(j::text, 'NULL') || ' (expected 42501 row-level security)'; end if;
    if v_txt is null then v_bad := v_bad || ' 🔴 the row is unread now'; end if;
    if v_bad = '' then call _pass('nsu','0239-C4 읽은 행을 다시 안 읽음으로 되돌리는 수정은 WITH CHECK가 거부(42501 row-level security), 행은 읽음 그대로');
    else v_msg := v_bad; call _fail('nsu','0239-C4 no un-read', v_msg); end if;
  exception when others then reset role; call _fail('nsu','0239-C4 no un-read', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-D1] a deactivated operator can no longer silence a bell  +  [0239-W1] server writers
  --           ONE rolled-back world (fixture note ①): flags, roster, bookings
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_err := null; w := '{}'::jsonb;
    begin
      o    := t_user('nsu_d1_o', 'owner');  rr := t_user('nsu_d1_r', 'runner');
      opsA := t_user('nsu_d1_opsA', 'owner'); opsF := t_user('nsu_d1_opsF', 'owner');
      dg := t_dog(o, 'nsu d1'); rt := t_route('nsu d1');
      insert into ops_recipients (profile_id, event_class, active) values (opsA, 'return_strand', true)
      on conflict (profile_id, event_class) do update set active = true;
      insert into ops_recipients (profile_id, event_class, active) values (opsF, 'return_strand', true)
      on conflict (profile_id, event_class) do update set active = true;
      update ops_recipients set active = false where profile_id = opsF;          -- opsF is now FORMER
      w := w || jsonb_build_object('former',
        (select count(*) from ops_recipients where profile_id = opsF and event_class = 'return_strand' and not active),
        'active', (select count(*) from ops_recipients where profile_id = opsA and event_class = 'return_strand' and active));
      update ops_flags set return_strand_minutes = 60 where id;
      bk  := t_nsu_strand(o, rr, dg, rt);     -- the former operator tries to silence this one
      bk2 := t_nsu_strand(o, rr, dg, rt);     -- CONTROL: the same look-alike, planted by the owner
      -- the former operator's own row, then the forge, as a client
      nid := t_nsu_row(opsF, 'nsu d1 seed', null, true);   -- READ, so the grant is the only wall (C1's note)
      w := w || jsonb_build_object('forge', t_nsu_as(opsF, format(
             'update notifications set kind = %L, title = %L, ref_id = %L, created_at = %L where id = $1',
             'system', T_STR, bk, '2000-01-01'), nid));
      -- the control look-alike: exactly the row the forge would have produced, on bk2
      insert into notifications (profile_id, kind, title, body, ref_id, created_at)
      values (opsF, 'system', T_STR, 'nsu', bk2, '2000-01-01');
      w := w || jsonb_build_object('pre', t_nsu_bells(bk, T_STR, opsA) + t_nsu_bells(bk2, T_STR, opsA));
      -- W1 ⓐ: a fresh strand booking the sweep must ring
      w := w || jsonb_build_object('fresh', t_nsu_strand(o, rr, dg, rt));
      w := w || jsonb_build_object('freshPre', t_nsu_bells((w->>'fresh')::uuid, T_STR, opsA));
      perform sweep_run_end_recovery();
      w := w || jsonb_build_object(
        'bk', t_nsu_bells(bk, T_STR, opsA), 'bk2', t_nsu_bells(bk2, T_STR, opsA),
        'fresh1', t_nsu_bells((w->>'fresh')::uuid, T_STR, opsA),
        'bkAt', (select min(created_at) from notifications
                  where ref_id = bk and title = T_STR and kind = 'system' and profile_id = opsA),
        'list', t_nsu_returns(opsA));
      -- W1 ⓑ: chat_mark_read, as authenticated, releases the real trigger's 「새 메시지」 row
      insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                            base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o, dg, rr, rt, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bk2;
      insert into chat_threads (booking_id) values (bk2) returning id into th;
      insert into chat_messages (thread_id, sender_id, body, created_at)
      values (th, rr, 'nsu 안녕하세요', now() - interval '1 minute');
      w := w || jsonb_build_object('nudgeUnread0',
        (select count(*) from notifications where profile_id = o and ref_id = bk2 and title = '새 메시지' and read_at is null));
      perform set_config('request.jwt.claim.sub', o::text, true);
      set local role authenticated;
      if current_user <> 'authenticated' then raise exception 'w1: role did not take'; end if;
      perform chat_mark_read(th);
      reset role;
      perform set_config('request.jwt.claim.sub', '', true);
      w := w || jsonb_build_object('nudgeUnread1',
        (select count(*) from notifications where profile_id = o and ref_id = bk2 and title = '새 메시지' and read_at is null));
      -- W1 ⓒ: service_role rewrites a non-read_at column
      nid2 := t_nsu_row(o, 'nsu w1 sr', null, false);
      set local role service_role;
      if current_user <> 'service_role' then raise exception 'w1: service_role did not take'; end if;
      update notifications set title = 'nsu w1 sr rewritten' where id = nid2;
      get diagnostics v_n = row_count;
      reset role;
      w := w || jsonb_build_object('sr', v_n);
      raise exception 'nsu_rollback';
    exception when others then
      if sqlerrm is distinct from 'nsu_rollback' then v_err := sqlerrm; end if;
    end;
    reset role; perform set_config('request.jwt.claim.sub', '', true);

    -- ── D1 ──
    begin
      v_bad := '';
      if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
      if (w->>'former') is distinct from '1' or (w->>'active') is distinct from '1'
        then v_bad := v_bad || ' FIXTURE: forger former ' || coalesce(w->>'former', 'NULL') || '/1, operator active ' || coalesce(w->>'active', 'NULL') || '/1'; end if;
      if (w->>'pre') is distinct from '0' then v_bad := v_bad || ' FIXTURE: a real bell existed before the tick (' || coalesce(w->>'pre', 'NULL') || ')'; end if;
      if (w->>'bk2') is distinct from '0'
        then v_bad := v_bad || ' CONTROL: a planted former-operator look-alike did NOT silence the bell (' || coalesce(w->>'bk2', 'NULL') || ') — the fixture is not one where a landed forge matters'; end if;
      if (w->'forge'->>'state') is distinct from '42501' or (w->'forge'->>'msg' ~ 'permission denied') is not true
        then v_bad := v_bad || ' 🔴 the former operator''s forge: ' || coalesce((w->'forge')::text, 'NULL') || ' (expected 42501 permission denied)'; end if;
      if (w->>'bk') is distinct from '1'
        then v_bad := v_bad || ' 🔴 the active operator got ' || coalesce(w->>'bk', 'NULL') || ' bell(s) for the booking the former operator targeted (1)'; end if;
      if (w->'list') ? 'raised' or (w->'list') is null then v_bad := v_bad || ' list: ' || coalesce((w->'list')::text, 'NULL');
      elsif (w->'list'->'rows'->bk::text->>'notified_at') is null
        then v_bad := v_bad || ' 🔴 ops_stranded_returns does not date the booking';
      elsif ((w->'list'->'rows'->bk::text->>'notified_at')::timestamptz = (w->>'bkAt')::timestamptz) is not true
        then v_bad := v_bad || ' 🔴 notified_at=' || (w->'list'->'rows'->bk::text->>'notified_at') || ' is not the real bell (' || coalesce(w->>'bkAt', 'NULL') || ')'; end if;
      if v_bad = '' then call _pass('nsu','0239-D1 비활성(전직) return_strand 운영자의 자기 행 위조(system·반환 좌초·2000-01-01)는 42501 — 한 tick에 현직 운영자에게 그 예약 벨 정확히 1개, ops_stranded_returns notified_at은 실제 벨 시각; 대조군: 같은 흉내 행을 소유자가 심으면 벨이 꺼진다(0)');
      else v_msg := v_bad; call _fail('nsu','0239-D1 former operator cannot silence', v_msg); end if;
    exception when others then call _fail('nsu','0239-D1 former operator cannot silence', sqlerrm); end;

    -- ── W1 ──
    begin
      v_bad := '';
      if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
      if (w->>'freshPre') is distinct from '0' or (w->>'fresh1') is distinct from '1'
        then v_bad := v_bad || ' 🔴 ⓐ sweep: fresh strand bells ' || coalesce(w->>'freshPre', 'NULL') || ' → ' || coalesce(w->>'fresh1', 'NULL') || ' (0 → 1)'; end if;
      if (w->>'nudgeUnread0') is distinct from '1' then v_bad := v_bad || ' FIXTURE: ⓑ the trigger wrote ' || coalesce(w->>'nudgeUnread0', 'NULL') || ' unread nudge(s) (1)'; end if;
      if (w->>'nudgeUnread1') is distinct from '0' then v_bad := v_bad || ' 🔴 ⓑ chat_mark_read left ' || coalesce(w->>'nudgeUnread1', 'NULL') || ' unread nudge(s) (0)'; end if;
      if (w->>'sr') is distinct from '1' then v_bad := v_bad || ' 🔴 ⓒ service_role title rewrite changed ' || coalesce(w->>'sr', 'NULL') || ' row(s) (1)'; end if;
      if v_bad = '' then call _pass('nsu','0239-W1 서버 쓰기는 그대로 — 스윕 한 tick이 새 좌초 예약에 벨 0→1, authenticated로 부른 chat_mark_read(정의자)가 트리거가 쓴 「새 메시지」 안 읽음 1→0, service_role의 title 수정 1행');
      else v_msg := v_bad; call _fail('nsu','0239-W1 server writers', v_msg); end if;
    exception when others then call _fail('nsu','0239-W1 server writers', sqlerrm); end;
  exception when others then reset role; call _fail('nsu','0239-D1/W1 staging', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-M1] the client's three mark-read wrappers, replayed in PostgREST's shape (rolled back)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_err := null; w := '{}'::jsonb;
    begin
      u := t_user('nsu_m1_u', 'owner'); x := t_user('nsu_m1_x', 'owner');
      bk := gen_random_uuid();   -- a ref only (no FK on notifications.ref_id)
      w := w || jsonb_build_object(
        'a',  t_nsu_row(u, 'nsu m1 tap',  bk,   false),   -- tap with ref
        'b',  t_nsu_row(u, 'nsu m1 bare', null, false),   -- tap without ref
        'c',  t_nsu_row(u, 'nsu m1 ids',  null, false),   -- markNotificationsRead
        'r',  t_nsu_row(u, 'nsu m1 read', null, true),    -- already read: its instant must not move
        'xa', t_nsu_row(x, 'nsu m1 tap',  bk,   false),   -- a stranger's same-titled row
        'xb', t_nsu_row(x, 'nsu m1 bare', null, false),
        'xc', t_nsu_row(x, 'nsu m1 ids',  null, false));
      w := w || jsonb_build_object('rAt0', (select read_at::text from notifications where id = (w->>'r')::uuid));
      -- markNotificationsReadByTap(refId, title): .eq('title').is('read_at', null).eq('ref_id')
      w := w || jsonb_build_object('tapRef', t_nsu_pgrst(u,
        'public.notifications.title = $3 and public.notifications.read_at is null and public.notifications.ref_id = $4',
        null, 'nsu m1 tap', bk));
      -- markNotificationsReadByTap(null, title): … .is('ref_id', null)
      w := w || jsonb_build_object('tapBare', t_nsu_pgrst(u,
        'public.notifications.title = $3 and public.notifications.read_at is null and public.notifications.ref_id is null',
        null, 'nsu m1 bare', null));
      -- markNotificationsRead(ids): .in('id', ids).is('read_at', null) — the stranger's id rides along
      w := w || jsonb_build_object('ids', t_nsu_pgrst(u,
        'public.notifications.id = any ($2) and public.notifications.read_at is null',
        array[(w->>'c')::uuid, (w->>'xc')::uuid], null, null));
      -- a fresh unread row, then markAllNotificationsRead: .is('read_at', null)
      w := w || jsonb_build_object('d', t_nsu_row(u, 'nsu m1 all', null, false));
      w := w || jsonb_build_object('all', t_nsu_pgrst(u, 'public.notifications.read_at is null', null, null, null));
      w := w || jsonb_build_object(
        'uUnread', (select count(*) from notifications where profile_id = u and read_at is null),
        'xUnread', (select count(*) from notifications where profile_id = x and read_at is null),
        'rAt1', (select read_at::text from notifications where id = (w->>'r')::uuid));
      raise exception 'nsu_rollback';
    exception when others then
      if sqlerrm is distinct from 'nsu_rollback' then v_err := sqlerrm; end if;
    end;
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    if v_err is not null then v_bad := v_bad || ' staging raised: ' || v_err; end if;
    if (w->'tapRef'->>'n') is distinct from '1' then v_bad := v_bad || ' 🔴 byTap(ref): ' || coalesce((w->'tapRef')::text, 'NULL') || ' (1)'; end if;
    if (w->'tapBare'->>'n') is distinct from '1' then v_bad := v_bad || ' 🔴 byTap(no ref): ' || coalesce((w->'tapBare')::text, 'NULL') || ' (1)'; end if;
    if (w->'ids'->>'n') is distinct from '1' then v_bad := v_bad || ' 🔴 markNotificationsRead: ' || coalesce((w->'ids')::text, 'NULL') || ' (1 — the caller''s row only)'; end if;
    if (w->'all'->>'n') is distinct from '1' then v_bad := v_bad || ' 🔴 markAll: ' || coalesce((w->'all')::text, 'NULL') || ' (1 — only the fresh row was still unread)'; end if;
    if (w->>'uUnread') is distinct from '0' then v_bad := v_bad || ' 🔴 the caller still has ' || coalesce(w->>'uUnread', 'NULL') || ' unread'; end if;
    if (w->>'xUnread') is distinct from '3' then v_bad := v_bad || ' 🔴 the stranger has ' || coalesce(w->>'xUnread', 'NULL') || ' unread (3 — none of theirs may move)'; end if;
    if (w->>'rAt0') is null or (w->>'rAt1') is distinct from (w->>'rAt0')
      then v_bad := v_bad || ' 🔴 an already-read row''s instant moved (' || coalesce(w->>'rAt0', 'NULL') || ' → ' || coalesce(w->>'rAt1', 'NULL') || ')'; end if;
    if v_bad = '' then call _pass('nsu','0239-M1 클라이언트의 읽음 표시 세 래퍼(탭-ref·탭-무ref·ids·모두 읽음)를 PostgREST 모양으로 authenticated 재생 — 각각 호출자의 해당 안 읽은 행만 정확히(1·1·1·1), 같은 제목 남의 행 3개 불변, 이미 읽은 행의 시각 불변');
    else v_msg := v_bad; call _fail('nsu','0239-M1 mark-read wrappers', v_msg); end if;
  exception when others then reset role; call _fail('nsu','0239-M1 mark-read wrappers', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0239-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_n := 0;
    v_tbl := to_regclass('public.notifications');
    if v_tbl is null then v_bad := ' NO-TABLE(notifications)';
    else
      for r in select a.attname::text as col from pg_attribute a
                where a.attrelid = v_tbl and a.attnum > 0 and not a.attisdropped loop
        v_n := v_n + 1;
        if has_column_privilege('anon', v_tbl, r.col, 'UPDATE') is not false then v_bad := v_bad || ' anon may update ' || r.col; end if;
        if (has_column_privilege('authenticated', v_tbl, r.col, 'UPDATE') is not distinct from (r.col = 'read_at')) is not true
          then v_bad := v_bad || ' authenticated UPDATE on ' || r.col || ' = '
                       || coalesce(has_column_privilege('authenticated', v_tbl, r.col, 'UPDATE')::text, 'NULL'); end if;
      end loop;
      if v_n < 9 then v_bad := v_bad || ' FIXTURE: ' || v_n || ' columns enumerated (>= 9)'; end if;
      if has_table_privilege('service_role', v_tbl, 'UPDATE') is not true then v_bad := v_bad || ' service_role lost UPDATE'; end if;
      if has_table_privilege('authenticated', v_tbl, 'SELECT') is not true then v_bad := v_bad || ' authenticated lost SELECT (the wrappers'' filters)'; end if;
      select pg_get_expr(p.polwithcheck, p.polrelid),
             (select string_agg(rolname, ',' order by rolname) from pg_roles where oid = any (p.polroles))
        into v_wc, v_roles
        from pg_policy p where p.polrelid = v_tbl and p.polname = 'noti self update';
      if not found then v_bad := v_bad || ' NO-POLICY(noti self update)';
      else
        if (v_wc ~ 'profile_id = auth\.uid\(\)' and v_wc ~ 'read_at IS NOT NULL') is not true
          then v_bad := v_bad || ' WITH CHECK is ' || coalesce(v_wc, 'ABSENT'); end if;
        if v_roles is distinct from 'authenticated' then v_bad := v_bad || ' policy roles ' || coalesce(v_roles, 'NULL (public)'); end if;
      end if;
      if (select count(*) from pg_policy p where p.polrelid = v_tbl and p.polcmd in ('w', '*')) is distinct from 1::bigint
        then v_bad := v_bad || ' more than one UPDATE-capable policy'; end if;
      if not exists (select 1 from pg_policy p where p.polrelid = v_tbl and p.polname = 'noti party insert' and p.polcmd = 'a')
        then v_bad := v_bad || ' noti party insert is gone (0239 does not touch it; five client paths use it)'; end if;
      if not exists (select 1 from pg_policy p where p.polrelid = v_tbl and p.polname = 'noti self' and p.polcmd = 'r')
        then v_bad := v_bad || ' noti self (select) is gone'; end if;
      if (select c.relrowsecurity from pg_class c where c.oid = v_tbl) is not true
        then v_bad := v_bad || ' RLS is not enabled on notifications (every policy arm is disarmed)'; end if;
    end if;
    if v_bad = '' then call _pass('nsu','0239-S1 배포 모양 — 컬럼별로 authenticated UPDATE는 read_at만, anon은 없음(카탈로그 열거 ' || v_n || '개), service_role UPDATE·authenticated SELECT 유지, noti self update는 유일한 UPDATE 정책·TO authenticated·WITH CHECK 두 조건, noti party insert·noti self 그대로');
    else v_msg := v_bad; call _fail('nsu','0239-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('nsu','0239-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
