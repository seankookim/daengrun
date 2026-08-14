-- ═══ 131 club_critical_titles suite — 0095 pins (the table with no policy to read) ═══
-- C1-C4 = the wall, per role and per verb. C5 = the door that must stay open or the whole
-- acknowledgment machine dies silently. C6 = the arm that survives a future blanket GRANT.
--
-- Style: sibling of 129/124 — `_pass('cct',…)`/`_fail('cct',…)`, one begin…exception per case,
--   `set local role` for every client path, ALWAYS `reset role`.
--   ⚠ Clear `request.jwt.claim.sub` BEFORE `set local role anon` — `set local role` leaves an
--     earlier suite's claim in place, so `auth.uid()` keeps returning a real user. That produced
--     six false positives in 124.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert ───
--   C1 ← 0095: delete `revoke all … from anon, authenticated`                        → RED
--   C2 ← 0095: as C1 (INSERT is the noise/unbounded-write direction)                 → RED
--   C3 ← 0095: as C1 (DELETE is the severance direction — the actual finding)        → RED
--   C4 ← 0095: `revoke … from anon` only, forgetting `authenticated`                 → RED
--   C5 ← NO MUTATION IN 0095 REDDENS IT. See the warning below — this is measured, not a gap
--        I failed to close. C5 reddens if the fanout itself breaks: drop `club_ack_fanout`,
--        drop the trigger's registry lookup, or revoke the registry from the definer's owner.
--   C6 ← 0095: delete `alter table … enable row level security`                      → RED
--
-- ⚠ **C5's MUTATION WAS PREDICTED AND THE PREDICTION WAS WRONG.** This header first claimed C5
--   went red under "add `force row level security`", on the reasoning that FORCE applies RLS to
--   the table owner and would silence the definer trigger. Run: harness stayed **545/0, C5
--   green**. Production says why — `_club_ack_tg` is owned by `postgres`, `rolbypassrls = true`,
--   and **BYPASSRLS overrides FORCE**. So FORCE is inert here, not hazardous.
--   The pin is kept and so is this note. C5 still earns its place: it is the only arm that proves
--   the *feature* survives the wall, and every other pin here would stay green while critical
--   alerts silently stopped producing ack rows. But its named mutation was an inference dressed
--   as a verified fact, in the mutation map — the one place in this file whose entire job is to
--   say "this was executed." Do not restore the FORCE claim.
-- ⚠ C6 exists because C1-C4 would still pass with RLS off, as long as the grants stay revoked.
--   The grants are the half a future `grant all on all tables in schema public to anon` undoes
--   without touching this migration. C6 is what notices.
do $$
declare
  ow uuid;
  v_n int; v_acks int; v_rls boolean;
begin
  -- ---------- seed: an owner to receive a critical notification ----------
  ow := t_user('cct_ow', 'owner');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- C1 — a stranger cannot read the registry.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute 'select count(*) from club_critical_titles' into v_n;
      reset role;
      call _fail('cct', 'C1 anon read blocked',
                 format('anon read %s rows of the critical-title registry', v_n));
    exception when insufficient_privilege then
      reset role;
      call _pass('cct', 'C1 anon read blocked — permission denied');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- C2 — a stranger cannot ADD a title. Direction: noise + unbounded writes into club_acks,
  -- since every notification carrying the injected title would fan out an ack row.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute $q$insert into club_critical_titles(title) values ('__cct_probe__')$q$;
      reset role;
      call _fail('cct', 'C2 anon insert blocked',
                 'anon inserted a title — every notification with it now fans out an ack row');
    exception when insufficient_privilege then
      reset role;
      call _pass('cct', 'C2 anon insert blocked — permission denied');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- C3 — a stranger cannot REMOVE a title. THIS IS THE FINDING: deleting `인시던트 발생`
  -- severs ack creation, so the 30-minute unacked -> host escalation never fires for it, and
  -- nothing anywhere errors.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute $q$delete from club_critical_titles where title = '인시던트 발생'$q$;
      reset role;
      call _fail('cct', 'C3 anon delete blocked',
                 'anon deleted a critical title — escalation for that class is now silently dead');
    exception when insufficient_privilege then
      reset role;
      call _pass('cct', 'C3 anon delete blocked — the severance path is closed');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- C4 — a LOGGED-IN user cannot either. This is an operator-owned registry, not user data,
  -- and every participant in a club session is authenticated — so `authenticated` is the role
  -- an actual attacker here would hold, not `anon`.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', ow::text, true);
    execute 'set local role authenticated';
    begin
      execute $q$delete from club_critical_titles where title = '인시던트 발생'$q$;
      reset role;
      call _fail('cct', 'C4 authenticated delete blocked',
                 'a logged-in user deleted a critical title');
    exception when insufficient_privilege then
      reset role;
      call _pass('cct', 'C4 authenticated delete blocked — revoke covers both client roles');
    end;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- C5 — THE FEATURE STILL WORKS. The definer trigger must still see the registry; if it
  -- cannot, ack rows stop being created and the wall above protects nothing.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    reset role;
    select count(*) into v_acks from club_acks where profile_id = ow;

    insert into notifications (profile_id, kind, title, body)
    values (ow, 'safety', '인시던트 발생', 'cct suite — ack fanout must survive 0095');

    select count(*) into v_n from club_acks where profile_id = ow;
    if v_n = v_acks + 1 then
      call _pass('cct', 'C5 ack fanout survives — definer trigger still reads the registry under RLS');
    else
      call _fail('cct', 'C5 ack fanout survives',
                 format('club_acks went %s -> %s; a critical alert produced no ack row, so the 30-minute escalation cannot fire', v_acks, v_n));
    end if;
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- C6 — RLS is actually ON. C1-C4 pass on grants alone; this is the arm that notices when a
  -- future `grant all on all tables in schema public to anon` puts the grants back.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    select c.relrowsecurity into v_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'club_critical_titles';
    if v_rls then
      call _pass('cct', 'C6 RLS enabled — a future blanket GRANT cannot silently reopen the table');
    else
      call _fail('cct', 'C6 RLS enabled',
                 'relrowsecurity = false; the table is protected by grants alone and one GRANT undoes it');
    end if;
  end;
end $$;
