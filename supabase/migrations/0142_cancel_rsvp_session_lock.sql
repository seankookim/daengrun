-- ═══ 0142: the cancel path takes the session lock the add paths already take ═══
--
-- Found by the announcer session's review agent, verified at source here before acting on it
-- (a relayed analysis is evidence, not authority — CLAUDE.md).
--
-- MEASURED on origin's 0134: `for update` on `club_sessions` appears twice — `session_rsvp:57`
-- and `session_add_my_dog:156` — and **not at all** in `session_cancel_rsvp`. So the two paths
-- that ADD a dog serialize against each other, and the path that REMOVES one runs beside them
-- unserialized.
--
-- ⚠ THE COMMENT I WROTE IN 0134 IS THE EVIDENCE AGAINST ME. Its §B belt-2 note says 「The
--   `for update` on club_sessions serializes same-session RSVPs, so belt 1 is not racy today」.
--   That sentence is true of the add paths and I wrote it while looking at them; it is not true
--   of the whole family, because cancel does not participate. A serialization argument is only
--   as good as its least-locked member, and I had not enumerated the members.
--
-- WHAT IS ACTUALLY AT RISK, stated precisely rather than as 「a race」:
--   · `session_rsvp` and `session_add_my_dog` both COUNT then INSERT (people cap, dog cap).
--     A concurrent cancel changes the count between their read and their write. For a CAP the
--     direction is benign — a delete only shrinks the count, so the worst case is admitting
--     someone who could have been admitted anyway.
--   · 0140's `club_owner_dog_limit` trigger is likewise a count-then-insert, serialized on the
--     add side by this same lock. A cancel racing it also only shrinks.
--   · So this is an ASYMMETRY, not a live breach — and that is exactly why it is worth closing
--     now rather than arguing about: the next writer to add a rule to the cancel path will
--     inherit a body that looks serialized (its siblings are) and is not. The cost is one line.
--
-- ⚠ WHERE THE LOCK GOES IS THE WHOLE DECISION. It must be taken BEFORE the membership read, or
--   the ordering it buys is worthless: two transactions could both read `session_people`, both
--   decide the caller is a member, and only then queue on the lock. Placed first, the lock
--   orders the entire body — read, gate, and delete — against the add paths, which is what
--   「serialized」 has to mean to be worth writing down.
--
-- Everything else in 0134's cancel body is copied verbatim (§10 T4 faithful-copy from the newest
-- definition on origin). One statement is added and nothing else moves.
create or replace function session_cancel_rsvp(p_session uuid)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_role text; v_checked timestamptz;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- [0142] The lock the add paths take (0134:57, 0134:156). First statement after the party
  -- gate's cheapest check, so every subsequent read in this body is ordered against them.
  -- `perform` rather than a select-into: nothing here needs the row's columns, only its lock,
  -- and binding a variable we never read would invite someone to start reading it.
  perform 1 from club_sessions where id = p_session for update;

  select role, checked_in_at into v_role, v_checked
    from session_people where session_id = p_session and profile_id = auth.uid();
  -- The one-sentence anti-enumeration answer: a session that does not exist and a session the
  -- caller never joined produce the identical row-absent condition and the identical token.
  -- PRESERVED DELIBERATELY — do not "improve" this into a not_found/not_joined split.
  -- ⚠ And note the lock above does NOT change that: `for update` on a missing row locks nothing
  --   and raises nothing, so a nonexistent session still falls through to `not_joined` exactly
  --   as before. Checked, because a lock that raised here would have been a new oracle.
  if v_role is null then raise exception 'not_joined'; end if;
  if v_role = 'host_runner' then raise exception 'host_cannot_leave'; end if;

  -- 🔴 ORDER RULING (0134): `already_checked_in` BEFORE `delegation_active`. Both are refusals,
  --    but already_checked_in is TERMINAL and delegation_active is RESOLVABLE — answering the
  --    resolvable one first sends a mixed-mode owner off to cancel a real, money-bearing
  --    delegation and then refuses them anyway.
  -- ⚠ THE PREDICATE IS `checked_in_at is not null`, NOT `attendance = 'checked_in'`: attendance
  --   can move to 'no_show' while the stamp stands (95:52), and someone who checked in still
  --   physically attended.
  if v_checked is not null then raise exception 'already_checked_in'; end if;

  -- [0052 §3] 위탁은 참여 취소로 조용히 사라지지 않는다 — 먼저 위탁을 취소해야 한다
  if exists (select 1 from session_dogs
             where session_id = p_session and owner_profile_id = auth.uid()
               and custody = 'runner_delegated' and service_state is distinct from 'ended') then
    raise exception 'delegation_active';
  end if;
  delete from session_dogs where session_id = p_session and owner_profile_id = auth.uid()
    and custody = 'owner_handled';
  delete from session_people where session_id = p_session and profile_id = auth.uid();
  update club_sessions set status = 'open' where id = p_session and status = 'full';
end $$;
revoke execute on function session_cancel_rsvp(uuid) from public, anon;
grant execute on function session_cancel_rsvp(uuid) to authenticated;
