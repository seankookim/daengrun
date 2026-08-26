-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0130 — 맹견 gate removal, Slice B: the CHECK, the three columns and the enum come out
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Slice A (`0127`, deployed) removed the gate's BEHAVIOUR and deliberately KEPT
-- `dogs.dangerous_status` / `dangerous_basis` / `dangerous_declared_at`, the
-- `dogs_dangerous_basis_pairs_with_status` CHECK and the `dog_dangerous_status` enum, so that an
-- already-installed binary still selecting or writing them would keep working. That is the whole
-- content of the expand/contract split: Slice A carries ZERO deploy-order constraint precisely
-- because nothing it touches is visible to an old bundle. **This file is the contract half.**
--
-- ═══ 🔴 THE GATE ON THIS FILE, AND IT IS NOT A CALENDAR ═══════════════════════════════════════
-- Contract `docs/contracts/maenggyeon-gate-removal-contract.md` §0 permits Slice B "only once ZERO
-- installed bundles reference them, MEASURED: every EAS channel (development / preview /
-- testflight / production per eas.json) checked for bundles whose JS contains `dangerous_status`,
-- plus the OTA fleet state; recorded in Slice B's header." That measurement is below, taken twice
-- by two sessions on two separate invocations, and it is EMPTY.
--
-- ── THE MEASUREMENT, verbatim (2026-08-26, `app/`, EAS CLI already authenticated on this machine
--    as `seankookim`; no credential value was read, typed or relayed) ─────────────────────────
--
--     $ npx eas build:list --non-interactive --limit 20 --json
--     []
--
--     $ npx eas channel:list --non-interactive --json
--     { "currentPage": [ { "name": "testflight",
--                          "createdAt": "2026-08-19T01:17:55.287Z",
--                          "isPaused": false,
--                          "updateBranches": [ { "name": "testflight", "updateGroups": [] } ] } ] }
--
-- Three facts fall out, and each is stated as exactly what it proves and no more:
--   ① **Zero EAS builds have ever been produced for this project.** Not zero recent — zero. There
--      is no bundle whose JS could be searched for `dangerous_status`, so the contract's per-channel
--      bundle grep is satisfied VACUOUSLY rather than by inspection, which is a stronger result and
--      a different one; it is written here as the former, not dressed as the latter.
--   ② **Only one of the four declared channels exists on EAS** (`testflight`, created
--      2026-08-19). `development`, `preview` and `production` have never been created, and EAS
--      creates a channel on first build or update against it — so their absence is itself the
--      evidence that nothing was ever shipped to them.
--   ③ **`testflight` has `updateGroups: []`** — zero OTA updates ever published. The OTA fleet is
--      empty, so `app.json`'s `fallbackToCacheTimeout: 0` (the non-atomic-OTA hazard this whole
--      two-slice shape was designed around) has no population to apply to.
--   ⚠ First taken by the Slice-B readiness audit (`docs/audits/2026-08-26-sliceb-and-definer-audit.md`
--      §A-3) and RE-RUN independently by this session before authoring, per the standing law that
--      a relayed measurement is evidence and not authority. Both runs agree byte-for-byte.
--
-- ── 🔴 WHAT THE MEASUREMENT DOES **NOT** COVER — the one thing still open, and it is Sean's ────
-- Two surfaces are invisible to EAS by construction:
--   · **Locally-built binaries.** `npx expo run:ios` puts a binary on a device or simulator without
--     ever touching EAS. A dev build made before Slice A landed still contains `DOG_SELECT`'s two
--     columns and would 400 on every dog read the moment this file applies.
--   · **App Store Connect / TestFlight submissions made outside EAS.** That surface is Sean-only by
--     credential (CLAUDE.md §Operations), so nobody here measured it, and the existence of a
--     `testflight` CHANNEL with zero builds is consistent with a profile configured but never run —
--     which is a reading, not a measurement, and is not treated as one.
--
-- **THEREFORE: THIS FILE IS AUTHORED, MEASURED AND COMMITTED, AND IT IS NOT PUSHED.** It lands only
-- after Sean answers one sentence: *"Has any 도그스하이 binary ever reached a device other than your
-- own dev phone — TestFlight, App Store, or a build you sideloaded for someone else?"* If **no**,
-- the §0 measurement is complete and this pushes as written. If **yes**, the residual population is
-- exactly "binaries Sean can name" — bounded, not a fleet — and the disposition is his call, not a
-- re-derivation from this header. A green harness on this file proves the SCHEMA is consistent
-- after the drop; it proves nothing whatever about who is holding a phone.
--
-- ═══ THE CENSUS — nothing is being forgotten ═════════════════════════════════════════════════
-- 0127's header records the production census taken before Slice A, against the LINKED project:
--
--     dangerous_status | count
--     -----------------+-------
--     undeclared       |     3
--
-- Zero `declared_dangerous`, zero `declared_none` — no owner ever answered the question, so this
-- drop forgets no declaration anybody made. That is a RELAYED measurement (0127's, [R]), cited as
-- theirs; this session did not re-query production, and the claim this file needs from it is only
-- that no legal record is being destroyed. ⚠ Counsel wording, per contract §0: Slice B's line may
-- say the fields were **deleted**; it may never say "data destroyed" — a dropped column is logical
-- forgetting, and heap/WAL/backups retain bytes on their own lifecycles.
--
-- ═══ 🔴 ORDER IS LOAD-BEARING HERE, NOT COSMETIC ══════════════════════════════════════════════
-- CHECK → columns → enum, and the middle step cannot be moved. Suite 161's measured battery
-- recorded the reason as a MEASUREMENT rather than a reading of the docs: mutation **M9c** dropped
-- the enum while `dogs.dangerous_status` still used it and postgres's own dependency graph refused
-- it at apply time —
--     `cannot drop type dog_dangerous_status because other objects depend on it
--      / column dangerous_status of table dogs`
-- The column Slice A deliberately kept IS the guard on the enum, a structural protection nobody
-- authored, and this file is the one that has to dismantle it in the right order. The CHECK goes
-- first for the same reason in the other direction: `drop column` would take it implicitly, and an
-- implicit drop leaves no statement for a reader to audit against the named inventory below.
-- ⚠ No `cascade` anywhere in this file. RESTRICT is the default and it is the point: if some
-- object this file did not enumerate depends on these columns, postgres must ABORT rather than
-- quietly widen the blast radius. §A catches the class postgres cannot see (plpgsql bodies carry no
-- dependency records); postgres itself catches views, indexes, defaults and policies.
--
-- ═══ WHAT ELSE MOVES IN THIS COMMIT (fixtures — none of it optional) ═════════════════════════
-- Six files write these columns and every one of them dies the moment this file applies. They are
-- authored TOGETHER with this migration, up front, not discovered red-by-red — because
-- `harness.sh:115-123` runs `ON_ERROR_STOP=1` and `exit 1`, so the run DIES at the first affected
-- suite (`10_settle_suite.sql:24`, a `language sql` parse-time death of `t_dog`) and the other four
-- are never reached. A red-by-red loop here is five full harness rebuilds to discover a list that
-- one grep already knows.
--   · `supabase/tests/10_settle_suite.sql:24`      — `t_dog`, the standard fixture dog for 50+ suites
--   · `supabase/tests/113_km_ledger_suite.sql`     — :102, :429, :458
--   · `supabase/tests/139_run_channel_rls_suite.sql` — :32, :33
--   · `supabase/tests/146_booking_entry_suite.sql` — :176-178
--   · `supabase/tests/149_party_active_suite.sql`  — :180-181
--   · `supabase/tests/161_breed_gate_removal_suite.sql` — P2 ⓒ/ⓓ and P6, rewritten (below)
--   · **`supabase/seed.sql:19` — AND IT IS THE ONE THAT WILL BE FORGOTTEN.** `seed.sql` is NOT run
--     by the harness (grep of `harness.sh` for `seed` returns only the English word inside a
--     comment). Its breakage lands on `supabase db reset` / local dev bring-up, so **no harness
--     number will ever go red to remind anyone.** Edited here explicitly for that reason.
--   · `supabase/tests/154_dangerous_breed_suite.sql` — **37 references, and DELIBERATELY UNTOUCHED.**
--     It was unregistered from `harness.sh` by 0127 and is kept on disk as the readable record of
--     what the gate did. Nothing runs it; editing it would erase a record to satisfy a grep. This
--     bullet exists so the next reader does not "finish the job".
--
-- ═══ 🔴 SUITE 161's P6 INVERTS, IN THIS SAME COMMIT ═══════════════════════════════════════════
-- 161 was created BY Slice A and its P6 is a deliberate tripwire pinning the columns' SURVIVAL —
-- it fails with 「Slice B가 앞당겨졌다」 if they go early. That pin is not stale and it is not being
-- deleted: its pinned property legitimately INVERTS with this file, so it is rewritten to pin the
-- new truth in the same slice, with the reason in the file (CLAUDE.md: *"a suite whose pinned
-- behaviour legitimately changes MUST be updated in the same slice … say WHY, and name which new
-- pin owns the new property"*). P6 keeps its name and now owns the removal boundary AND the
-- no-dangling-reference sweep; P2 keeps ⓐ/ⓑ/ⓔ and retires ⓒ/ⓓ, whose subjects no longer exist.
--
-- ═══ WHAT THIS FILE DOES NOT DO ══════════════════════════════════════════════════════════════
-- · No function is created or replaced — so there is no ACL/`search_path` surface here at all, and
--   `check-definer-acl.mjs` has nothing to say about it. Said out loud because "no news from the
--   definer gate" must not be read as a green it did not issue.
-- · No data is written or deleted beyond the columns' own contents.
-- · `dogs.breed` (free text) is untouched, as it was in Slice A.
-- · No functional control is executed inside this migration (an `insert into dogs` needs a
--   `profiles` FK row that does not exist at apply time in a from-scratch chain). Suite 161 P2 owns
--   that proposition and its ordinary INSERT is the first write to `dogs` in the whole file.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  PRE-CHECK — fail closed BEFORE dropping anything postgres cannot protect
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Postgres tracks dependencies for views, indexes, defaults, constraints and policies, and RESTRICT
-- will refuse the drop for any of them. It tracks NOTHING for a plpgsql or sql function body — 0127
-- measured that class directly ("dropping a called function succeeds silently and fails at the next
-- insert"). So the one thing that can survive this file as a live landmine is a routine whose body
-- names one of these columns. This block is the net for exactly that, and it runs BEFORE the drops
-- so a hit costs nothing but an aborted apply.
-- ⚠ `%dangerous_status%` also matches `dog_dangerous_status`, so the enum's name is covered by the
--    same pattern; `dangerous_basis` and `dangerous_declared_at` are named separately because
--    neither is a substring of anything else here.
do $$
declare v_left text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname || '.' || p.proname)
    into v_left
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema')
     and n.nspname not like 'pg_toast%'
     and (p.prosrc like '%dangerous_status%'
       or p.prosrc like '%dangerous_basis%'
       or p.prosrc like '%dangerous_declared_at%');
  if v_left is not null then
    raise exception '0130 ABORT: a routine still references the declaration columns and postgres cannot see it — dropping them would arm a landmine that fires at the next call: %', v_left;
  end if;

  -- cron commands are static text too, and pg_cron is absent in the harness — where it is absent
  -- this arm is NOT APPLICABLE, which is a different thing from passing, and is written that way.
  if to_regclass('cron.job') is not null then
    execute $q$
      select string_agg(jobname || ' :: ' || command, ', ' order by jobname)
        from cron.job
       where command like '%dangerous_status%'
          or command like '%dangerous_basis%'
          or command like '%dangerous_declared_at%'
    $q$ into v_left;
    if v_left is not null then
      raise exception '0130 ABORT: a scheduled cron command still references the declaration columns: %', v_left;
    end if;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  THE PAIR CHECK — dropped by its own name, first
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0119:141-143. `drop column` would take it implicitly; an explicit statement is what lets the
-- VERIFY's named inventory below correspond one-for-one to a statement someone can read.
alter table dogs drop constraint if exists dogs_dangerous_basis_pairs_with_status;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  THE THREE COLUMNS — 0119:133-135, one statement each, RESTRICT
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Their comments (0127 §E, which REPLACED 0119's now-false originals) go with them; a dropped
-- column has no `pg_description` row, so there is nothing left to rewrite or to forget.
alter table dogs drop column if exists dangerous_status;
alter table dogs drop column if exists dangerous_basis;
alter table dogs drop column if exists dangerous_declared_at;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  THE ENUM — 0119:130, and only now that nothing is bound to it
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- See the ORDER note in the header: run this before §C and postgres refuses the whole file. That
-- is not a hypothetical — 161's battery M9c measured the refusal.
drop type if exists dog_dangerous_status;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  VERIFY — absence BY EXACT NAME, no dangling reference anywhere, and the survivors intact
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Same doctrine as 0127's: a NAMED inventory, never a `%dangerous%` name pattern, and every
-- absence arm paired with a positive control on something that must REMAIN — an absence sweep
-- alone is green on a dropped table, which is the failure it must not be able to miss.
do $$
declare
  v_n int;
  v_left text;
  v_trg text[];
  c_trg_dogs constant text[] := array['club_dog_materiality', 't_dogs_touch'];
begin
  -- ── ① the three columns, ABSENT, each named individually so the error says WHICH survived ──
  select string_agg(column_name, ', ' order by column_name) into v_left
    from information_schema.columns
   where table_schema = 'public' and table_name = 'dogs'
     and column_name in ('dangerous_status', 'dangerous_basis', 'dangerous_declared_at');
  if v_left is not null then
    raise exception '0130: declaration column(s) still present on dogs: % — the drop was partial, which is the worst of the three states', v_left;
  end if;

  -- ── ② the pair CHECK, ABSENT by exact name — and no OTHER constraint on dogs mentions it ────
  if exists (select 1 from pg_constraint
              where conrelid = 'dogs'::regclass
                and conname = 'dogs_dangerous_basis_pairs_with_status') then
    raise exception '0130: dogs_dangerous_basis_pairs_with_status still exists';
  end if;
  select string_agg(conname || ' :: ' || pg_get_constraintdef(oid), ', ' order by conname)
    into v_left
    from pg_constraint
   where conrelid = 'dogs'::regclass
     and pg_get_constraintdef(oid) like '%dangerous%';
  if v_left is not null then
    raise exception '0130: a constraint on dogs still references a declaration column: %', v_left;
  end if;

  -- ── ③ the enum, ABSENT — in EVERY non-system namespace, not merely in `public` ───────────────
  -- Scoping this to `public` would be the same mistake 0127's own review found in its caller scan:
  -- a check that calls itself schema-wide while looking at one schema.
  select string_agg(n.nspname || '.' || t.typname, ', ' order by n.nspname) into v_left
    from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where t.typname = 'dog_dangerous_status'
     and n.nspname not in ('pg_catalog', 'information_schema')
     and n.nspname not like 'pg_toast%';
  if v_left is not null then
    raise exception '0130: the dog_dangerous_status type still exists: %', v_left;
  end if;

  -- ── ④ NO DANGLING REFERENCE, in each place a reference can hide ─────────────────────────────
  -- ⓐ routine bodies, every non-system namespace (the class postgres does not track — §A's arm
  --   re-run AFTER the drop, because §A proved the schema was clean going in and this proves the
  --   drop did not itself leave something behind).
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname || '.' || p.proname)
    into v_left
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema')
     and n.nspname not like 'pg_toast%'
     and (p.prosrc like '%dangerous_status%'
       or p.prosrc like '%dangerous_basis%'
       or p.prosrc like '%dangerous_declared_at%');
  if v_left is not null then
    raise exception '0130: a routine body still references a dropped column: %', v_left;
  end if;
  -- ⚠ SCOPE, stated rather than implied: this reads STATIC text. SQL assembled at run time by
  --   `execute format(...)` cannot be settled by any static check and this arm does not claim it.

  -- ⓑ triggers — no trigger anywhere whose function body referenced the columns survives, and no
  --   trigger on `dogs` carries a 맹견 name. (0127 dropped all six; this catches a re-creation.)
  select string_agg(c.relname || '.' || t.tgname, ', ' order by t.tgname) into v_left
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where not t.tgisinternal and n.nspname = 'public'
     and t.tgname like '%dangerous%';
  if v_left is not null then
    raise exception '0130: a trigger named for the removed gate is present: %', v_left;
  end if;

  -- ⓒ views and materialized views — postgres would have REFUSED the drop for a real dependency,
  --   so a hit here means a definition that names the column without depending on it (a literal, a
  --   comment). Cheap, and it is the arm that would catch a view rebuilt after the drop.
  select string_agg(schemaname || '.' || viewname, ', ' order by viewname) into v_left
    from pg_views
   where schemaname not in ('pg_catalog', 'information_schema')
     and (definition like '%dangerous_status%' or definition like '%dangerous_basis%'
       or definition like '%dangerous_declared_at%');
  if v_left is not null then
    raise exception '0130: a view definition still names a dropped column: %', v_left;
  end if;
  select string_agg(schemaname || '.' || matviewname, ', ' order by matviewname) into v_left
    from pg_matviews
   where schemaname not in ('pg_catalog', 'information_schema')
     and (definition like '%dangerous_status%' or definition like '%dangerous_basis%'
       or definition like '%dangerous_declared_at%');
  if v_left is not null then
    raise exception '0130: a materialized view definition still names a dropped column: %', v_left;
  end if;

  -- ⓓ indexes and policies on `dogs` — both are RESTRICT-protected, so this is belt-and-braces
  --   and it costs two catalog reads.
  select string_agg(indexname, ', ' order by indexname) into v_left
    from pg_indexes where schemaname = 'public' and tablename = 'dogs'
     and indexdef like '%dangerous%';
  if v_left is not null then
    raise exception '0130: an index on dogs still references a dropped column: %', v_left;
  end if;
  select string_agg(policyname, ', ' order by policyname) into v_left
    from pg_policies where schemaname = 'public' and tablename = 'dogs'
     and (coalesce(qual, '') like '%dangerous%' or coalesce(with_check, '') like '%dangerous%');
  if v_left is not null then
    raise exception '0130: an RLS policy on dogs still references a dropped column: %', v_left;
  end if;

  -- ⓔ cron, where installed. NOT APPLICABLE in the harness, and that is not a pass.
  if to_regclass('cron.job') is not null then
    execute $q$
      select string_agg(jobname || ' :: ' || command, ', ' order by jobname)
        from cron.job
       where command like '%dangerous_status%'
          or command like '%dangerous_basis%'
          or command like '%dangerous_declared_at%'
    $q$ into v_left;
    if v_left is not null then
      raise exception '0130: a scheduled cron command still references a dropped column: %', v_left;
    end if;
  end if;

  -- ── ⑤ 🔴 THE POSITIVE HALF — what must SURVIVE, or an absence sweep is green on a wasteland ──
  -- ⓐ `dogs` is still a table, and the columns the product actually uses are still on it. The
  --    named list is the point: `count(*) > 0` would pass on a table with one column left.
  if to_regclass('public.dogs') is null then
    raise exception '0130 OVER-REACH: the dogs table itself is gone';
  end if;
  select string_agg(x.col, ', ' order by x.col) into v_left
    from (values ('id'), ('owner_id'), ('name'), ('breed'), ('weight_kg'), ('neutered'),
                 ('memo'), ('weekly_goal_km'), ('cumulative_km')) as x(col)
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = 'public' and c.table_name = 'dogs'
                        and c.column_name = x.col);
  if v_left is not null then
    raise exception '0130 OVER-REACH: this file took column(s) that are not its own: %', v_left;
  end if;

  -- ⓑ the surviving triggers on `dogs` by EXACT NAME SET (0127's ⑤ inventory, the `dogs` arm).
  --    A count says 2; only the name set says WHICH 2 — 161's battery M13 measured that a swap
  --    keeps the count and changes everything.
  select array_agg(t.tgname order by t.tgname) into v_trg
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'dogs';
  if v_trg is distinct from c_trg_dogs then
    raise exception '0130 OVER-REACH: the surviving dogs trigger set changed [actual: %, expected: club_dog_materiality, t_dogs_touch]',
      coalesce(array_to_string(v_trg, ', '), '∅');
  end if;

  -- ⓒ the other two tables in 0127's inventory are untouched by this file and must stay 14 / 1.
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'bookings';
  if v_n <> 14 then
    raise exception '0130 OVER-REACH: bookings should still carry 14 non-internal triggers, found %', v_n;
  end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'session_dogs';
  if v_n <> 1 then
    raise exception '0130 OVER-REACH: session_dogs should still carry 1 non-internal trigger, found %', v_n;
  end if;

  -- ⓓ the recurring generator is still 0111's restored body. It is the object 0119 damaged and
  --    0127 repaired, it is the one that inserts into `bookings` for every owner on a cron, and it
  --    is the thing a careless 맹견 sweep would take next. Suite 161 P4 owns its exact digest; this
  --    arm only refuses to leave the file with the function missing or re-belted.
  if to_regprocedure('public.generate_recurring_bookings()') is null then
    raise exception '0130 OVER-REACH: generate_recurring_bookings is gone';
  end if;
  select prosrc into v_left from pg_proc
   where oid = 'public.generate_recurring_bookings()'::regprocedure;
  if v_left like '%dog_custody_gate%' or v_left like '%dangerous%' then
    raise exception '0130: the recurring generator has re-acquired a 맹견 reference';
  end if;

  raise notice '0130: pair CHECK, 3 columns and the dog_dangerous_status enum absent by exact name; no routine/trigger/view/matview/index/policy (and no cron command where pg_cron exists) references them in any non-system namespace; dogs table + its 9 product columns + its exact 2-trigger set survive, bookings 14 / session_dogs 1 unchanged, generate_recurring_bookings present and 맹견-free. Distribution gate: 0 EAS builds ever, 1 of 4 channels existing, 0 OTA updates — measured twice, recorded in this header; the locally-built-binary question is Sean''s and gates the PUSH, not the apply.';
end $$;
