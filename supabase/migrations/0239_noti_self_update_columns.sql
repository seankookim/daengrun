-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0239 — a client may mark its own notifications READ, and may change nothing else about them
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 270_noti_self_update_columns_suite.sql (tag `nsu`) — 0239-C1 · C2 · C3 · C4 · D1 · W1 · M1 · M2 · S1
-- The root-cause follow-up 0238 §0d recommended and deliberately did not take (its three reasons are
-- answered below, §0d). Stacked on cloud/0238-ops-bell-keys @ 185b96f.
--
-- ═══ §0a WHAT IS WRONG, MEASURED ON THE BASE (185b96f, harness 1633/0) ═════════════════════════
-- `noti self update` (0002:139) is `for update using (profile_id = auth.uid())` — no WITH CHECK (so
-- it defaults to the USING predicate) and no column restriction, and the table carries Supabase's
-- default `grant all … to anon, authenticated` (the shim mirrors it, 00_shim.sql:128). So ANY
-- signed-in user may rewrite ANY column of their OWN rows: kind, title, body, ref_id, created_at,
-- handoff_cycle_id, id — everything but the row's owner. That is door ⓢ in 0238 §0a. 0238 and
-- 0233 §C made the SHIPPED ops bells key on a bell identity (kind `system` AND a recipient who is
-- or was seated at the bell's class), which excludes a STRANGER's rewritten row but cannot exclude
-- a row whose recipient IS or WAS seated — and deactivation (`ops_roster_set`'s only removal) does
-- not revoke that. Reproduced with 270 against the base (this file absent): every forge pin red,
-- each for its stated reason — a re-kinded/re-titled/re-ref'd/backdated row LANDS (C1), a row can
-- be marked unread again (C4), and a DEACTIVATED former `return_strand` operator's rewritten row
-- silences the active operator's 「반환 좌초 — 확인 필요」 and puts 2000-01-01 on
-- `ops_stranded_returns` (D1). Numbers in REGISTRY's 0239 row.
--
-- ═══ §0b EVERY CLIENT WRITE TO `notifications`, ENUMERATED (app/src + app/app, grep, then read) ══
--   UPDATE — three wrappers, each `.update({ read_at: new Date().toISOString() })`, nothing else:
--     · api.ts `markAllNotificationsRead`   … `.is('read_at', null)`
--     · api.ts `markNotificationsRead(ids)` … `.in('id', ids).is('read_at', null)`
--     · api.ts `markNotificationsReadByTap` … `.eq('title', t).is('read_at', null)` and
--       `.eq('ref_id', r)` or `.is('ref_id', null)` (called from push.ts on an OS-push tap)
--     Their filters read id / title / ref_id / read_at — that needs SELECT, which stays table-wide
--     (`noti self`, 0002:138, row-scoped). postgrest-js 2.109 `update()` sends no `Prefer` header
--     (only `count=` when asked), and PostgREST's default return is minimal, so no column is
--     RETURNED. Every one of them sets `read_at` from NULL to a non-NULL instant.
--     ⚠ WITHOUT A SESSION (fix round, from the executing review — not in the first enumeration):
--     supabase-js sends a session-less request with the anon key, i.e. as `anon`. Before this file
--     `anon` held UPDATE (default privileges) and such a write matched 0 rows; after §A it holds
--     none, so the same write fails 42501 `permission denied for table notifications` — the
--     wrappers' meaning WIDENS for that caller. The one reachable signed-out path is push.ts's tap
--     listener (it stays armed after sign-out) → `markNotificationsReadByTap`, which previously
--     logged nothing and would now log `[push] tap mark read: permission denied…` (not
--     user-visible, never awaited). Answered on the client, not by granting `anon` back:
--     `markNotificationsReadByTap` now reads the session first and skips the write without one
--     (270 `0239-M2` pins the server half; app/test/push-token-signout.test.cjs Ⓓ executes the
--     client half). `markAllNotificationsRead` / `markNotificationsRead` run only from signed-in
--     screens (alerts.tsx, ops/index.tsx); were one ever to run signed out, the 42501 surfaces as a
--     failed mark, which is the honest answer (nothing was marked) — their callers clear the local
--     seal only on success.
--   INSERT — five paths, all through `noti party insert` (0114:273-283), all `kind: 'booking'`
--     addressed to the booking counterparty: `addRunEvent`, `notifyKmMilestone`, `sendSOS`,
--     `openBookingIncident`, `notifyRunStop`. The policy is therefore STILL NEEDED and is NOT
--     touched here (§0e).
--   DELETE / UPSERT — none. (`notifications` has no DELETE policy, so RLS refuses every client
--     delete row by row.)
--   RPCs that write `notifications` on the client's behalf — every one read, every one a DEFINER
--   owned by postgres, which neither a grant to `authenticated` nor this policy reaches (the owner
--   bypasses RLS; `notifications` is not FORCE ROW LEVEL SECURITY):
--     · `chat_mark_read(uuid)` / `chat_mark_read_to(uuid, bigint)` (0228 §A/§B) — the only SQL
--       UPDATEs of the table in the repo (`update notifications` grep: exactly these two);
--     · every INSERTing definer / sweep (0238 §0c lists the readers; the writers are server-side);
--     · `delete_my_account_tx` (deletes the caller's rows; definer).
--   Edge code: every `from("notifications")` in `supabase/functions/` is an INSERT through the
--   SERVICE_ROLE client (`admin()`), which keeps its table-wide grant and has BYPASSRLS.
--
-- ═══ §0c WHAT THIS FILE DOES ════════════════════════════════════════════════════════════════
--   ① `revoke update on notifications from public, anon, authenticated` — a table-level REVOKE also
--      revokes any column-level UPDATE those roles held (PostgreSQL REVOKE semantics), so no
--      earlier column grant can survive it.
--   ② `grant update (read_at) on notifications to authenticated` — the one column §0b proves a
--      client writes. anon gets nothing (it has no auth.uid(), so it never had a row to write) —
--      and a session-less write therefore ERRORS instead of matching 0 rows (§0b ⚠, 270 M2).
--   ③ `noti self update` gains an explicit WITH CHECK and a role:
--        to authenticated
--        using      (profile_id = auth.uid())
--        with check (profile_id = auth.uid() and read_at is not null)
--      `profile_id = auth.uid()` in the WITH CHECK is a second wall behind ② (profile_id is not
--      granted, so a re-address is refused by privilege before any policy is consulted). ⚠ And for
--      any UPDATE that reads a column (every filtered client write), PostgreSQL also applies the
--      SELECT policy `noti self` to the old AND the new row — so USING and this conjunct are
--      observable only through an UPDATE that reads no column; 270 C3 carries such arms. `read_at is not null` means a client may mark read but never
--      mark UNREAD: every client writer sets a non-NULL instant (§0b), and the only server logic that
--      reads `read_at` reads `is null` — 0090's 「새 메시지」 debounce and 0228's re-arm — so an
--      un-read is a way to hold one's own chat nudge suppressed, which no screen needs.
--      `alter policy`, not drop + create: the policy is never absent, not even inside the apply.
--   ④ VERIFY (§C): fails the APPLY unless, for EVERY column of the table enumerated from the catalog
--      (so a future column is covered without editing this file), `authenticated` holds UPDATE on
--      exactly `read_at` and `anon` on none; `service_role` still holds table-level UPDATE; the
--      policy's WITH CHECK is present and names `read_at`; `noti self update` is the table's only
--      UPDATE policy. This measures PRODUCTION's state at `db push` — the harness cannot reproduce
--      a production grant this repo never wrote.
--   Nothing else moves: no function, no other policy, no SELECT / INSERT / DELETE grant, no title.
--
-- ═══ §0d 0238 §0d's THREE REASONS NOT TO DO THIS, ANSWERED ══════════════════════════════════
--   (1) 「it does not close the class」 — still true, and not claimed: ⓟ stays (§0e). What this file
--       closes is ⓢ, and with it the one residual 0238's identity could not reach: a profile that
--       IS OR WAS seated forging on its own row. 0238's identity stays load-bearing against ⓟ.
--   (2) 「it moves three shipped suites」 — moved here, in the same slice (§0g).
--   (3) 「it deserves its own review」 — it is its own slice. ⚠ codex was NOT available in the
--       container that built it; no review verdict exists (REGISTRY row).
--
-- ═══ §0e WHAT THIS FILE DELIBERATELY DOES NOT CLOSE — named ═════════════════════════════════
--   · ⓟ `noti party insert` is untouched and still lets a booking PARTY insert a `kind='booking'`
--     row with ANY title and ANY `created_at` (and `read_at`, `handoff_cycle_id`) addressed to either
--     party. 0238 §0e's party-addressed one-shots and per-recipient keys stay forgeable by the
--     counterparty exactly as 0238 recorded. Two follow-ups, neither taken here: an INSERT column
--     grant (`profile_id, kind, title, body, ref_id` — the five §0b paths send nothing else) would
--     end client backdating; only a writer-provenance column ends look-alikes (0238 §0e, Sean's queue).
--   · A client can still move its OWN already-read row's `read_at` to another non-NULL instant. No
--     server logic reads the value (only `is null`), so it changes nothing anyone else sees.
--   · The grant is per ROLE: a future server-side writer that runs as `authenticated` (a SECURITY
--     INVOKER function) and UPDATEs another column would be refused. None exists (§0b); a later
--     slice that adds one must write it as a definer, as every current writer is.
--
-- ═══ §0f WHOSE OBJECTS THIS TOUCHES ═════════════════════════════════════════════════════════
--   ALTERS policy `noti self update` (0002:139, its only declaration). REVOKES/GRANTS on table
--   `notifications` (no earlier file grants on it; the privileges came from default privileges).
--   CREATES nothing.
--
-- ═══ §0g SHIPPED PINS THAT MOVE (same slice, each with a [0239] comment saying why) ════════════
--   264 `0233-B4` arm (ii) · 265 `0234-L3` · 269's `t_obk_forge_self` (feeds A1 · A2 · F1 · F2 · F3 ·
--   G1 · G2 · G3 · G4 · D1) — each staged its look-alike THROUGH ⓢ and asserted the forge LANDED.
--   Each now asserts the client forge is REFUSED (42501, row unchanged) and then plants the same
--   look-alike as the table owner, so the bell identity those pins exist for stays observable
--   through every conjunct (a look-alike can still reach the table through ⓟ or a future door).
--   Forecast in 0238 §0d (lab, 1621/11) and re-measured on this slice before the pins moved.

-- ═══ §A the column grant ═════════════════════════════════════════════════════════════════════
revoke update on notifications from public, anon, authenticated;
grant  update (read_at) on notifications to authenticated;

-- ═══ §B the policy: row stays the caller's, and read never becomes unread ═════════════════════
alter policy "noti self update" on notifications
  to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid() and read_at is not null);

comment on policy "noti self update" on notifications is
  '0239: a signed-in client may UPDATE only its own rows (USING), may leave them only its own and read (WITH CHECK: profile_id = auth.uid() and read_at is not null), and — by the column grant in the same file — may write only read_at. Every client writer (api.ts markAllNotificationsRead / markNotificationsRead / markNotificationsReadByTap) sets read_at and nothing else; server writers are definers or service_role.';

-- ═══ §C VERIFY — fail the apply, not a later harness run ════════════════════════════════════
do $verify$
declare
  v_bad text := '';
  v_tbl oid := to_regclass('public.notifications');
  r record;
  v_n int := 0;
  v_wc text;
begin
  if v_tbl is null then raise exception '0239 VERIFY: public.notifications does not exist'; end if;
  for r in select a.attname from pg_attribute a
            where a.attrelid = v_tbl and a.attnum > 0 and not a.attisdropped loop
    v_n := v_n + 1;
    if has_column_privilege('anon', v_tbl, r.attname, 'UPDATE') is not false
      then v_bad := v_bad || ' anon may update ' || r.attname || ';'; end if;
    if r.attname = 'read_at' then
      if has_column_privilege('authenticated', v_tbl, r.attname, 'UPDATE') is not true
        then v_bad := v_bad || ' authenticated cannot update read_at (the mark-read wrappers would die);'; end if;
    elsif has_column_privilege('authenticated', v_tbl, r.attname, 'UPDATE') is not false
      then v_bad := v_bad || ' authenticated may update ' || r.attname || ';'; end if;
  end loop;
  if v_n < 9 then v_bad := v_bad || ' only ' || v_n || ' columns enumerated (expected >= 9);'; end if;
  if has_table_privilege('service_role', v_tbl, 'UPDATE') is not true
    then v_bad := v_bad || ' service_role lost table-level UPDATE;'; end if;
  select pg_get_expr(p.polwithcheck, p.polrelid) into v_wc
    from pg_policy p where p.polrelid = v_tbl and p.polname = 'noti self update';
  if v_wc is null or (v_wc ~ 'read_at IS NOT NULL' and v_wc ~ 'profile_id = auth\.uid\(\)') is not true
    then v_bad := v_bad || ' noti self update WITH CHECK is ' || coalesce(v_wc, 'ABSENT') || ';'; end if;
  if (select count(*) from pg_policy p where p.polrelid = v_tbl and p.polcmd in ('w', '*')) is distinct from 1::bigint
    then v_bad := v_bad || ' notifications has other UPDATE-capable policies;'; end if;
  if v_bad <> '' then raise exception '0239 VERIFY failed:%', v_bad; end if;
end $verify$;
