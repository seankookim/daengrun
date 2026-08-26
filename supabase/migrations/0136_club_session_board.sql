-- ═══ 0136: club_session_board — the member-facing session board (spec v2 S2) ═══
--
-- Contract: docs/contracts/club-board-s2-contract.md v1 (+ §13 delta). Sean's ruling #9:
-- 「always fine; it's like a public dashboard」 — so the reader class is settled and this
-- projection is designed as a POSTER: it admits nothing we would not put on one.
--
-- THE INVARIANT (§0): this function returns exactly one class of fact — WHERE IS THIS DOG RIGHT
-- NOW, and WHO IS AT THIS SESSION. Never an address, a money value, a phone or emergency
-- contact, an incident, a health/breed attribute, or the identity of a runner who has not yet
-- accepted. To anyone.
--
-- ⚠ SEQUENCING MEASURED AT WRITE TIME, NOT ASSUMED: the contract's §13a rewrites several arms
--   「after S2.5」 (the admission retirement, which makes `session_delegate_dog` insert
--   `approval='approved'` and removes the `pending` producer). **S2.5 HAS NOT LANDED** —
--   production's `session_delegate_dog` still writes `'pending'` at insert, verified against the
--   live catalog before authoring. So §3a ships AS WRITTEN (P0 pending rows are included and
--   pinned), and §13a's rewrites belong to whoever lands S2.5. Suite 169's P6 says this in its
--   own comment so the next reader does not "fix" a pin that is currently correct.
--
-- ⚠ §10 T4 FAITHFUL-COPY: this file creates ONE new function and re-creates NOTHING. The
--   contract's §5 (operational-board `load`/`finishBlocker` and the `_club_dogs_unresolved`
--   de-duplication) is deliberately NOT in this migration — see the note at the bottom.

-- ═══ §1 club_session_board — one definer, flat whitelisted rows ═══
--
-- ⚠ NOT the wrapper/impl split `club_delegation_board` uses (0052:149 → 0053:227). That split
--   exists because ITS payload is grade-parameterised, so a `language sql` builder taking a
--   grade must be unreachable or the client picks its own grade. After ruling #9 this projection
--   is NOT grade-parameterised: one gate, one payload. A split here would be a revoked helper
--   whose only argument is a constant — ceremony without a gate.
--
-- ⚠ Flat `returns table`, never jsonb (house law). The operational board is jsonb for historical
--   reasons; a flat signature is what makes §8's absence pins MECHANICAL — a column that does
--   not exist cannot leak, and P14 reads the OUT-column list straight off pg_proc.
--
-- ⚠ NO `_club_require_v2()`. The shipped board does not call it either (0052:149-158), and a
--   READ surface that dies when the feature flag is off takes the club home down with it.
--   Transcribed deliberately, not omitted.
create or replace function club_session_board(p_session uuid)
returns table (
  row_kind         text,
  -- ⚠ bigint, not int: the contract's §1 signature says `int` and `session_dogs.seq` is
  --   BIGINT (measured against the live catalog). A narrowing return type raises
  --   「structure of query does not match function result type」 at CALL time, not at
  --   create time — so it would have shipped and failed on the first real board load.
  seq              bigint,
  dog_name         text,
  dog_photo_url    text,
  owner_name       text,
  is_mine          boolean,
  state            text,
  state_since      timestamptz,
  runner_name      text,
  runner_photo_url text
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  -- ═══ §2 THE GATE — party gate before a single row of the projection is built (0116 §D) ═══
  -- Zero rows, never an exception (§10 T3): a session that does not exist and a session the
  -- caller cannot see must be INDISTINGUISHABLE, or the function is an enumeration oracle over
  -- session ids. Pinned as P4 ≡ P5 rather than left as prose.
  --
  -- ⚠ NULL-UID EXEMPTION, deliberate (0116 §D's shared shape): the gate fires only for a
  --   signed-in caller. After the revoke below the only EXECUTE holders are `authenticated`
  --   (which by construction carries a JWT sub) and server roles (which carry none) — so a null
  --   uid is ops/harness, never a client. P18 pins it instead of assuming it.
  --
  -- ⚠ Written `coalesce(exists(…) or exists(…), false)`, never a bare column comparison inside
  --   a NOT (§10 T2). 151 B5 caught `club_incident_settle_quote` FAIL-OPEN because a NULL
  --   collapsed the disjunction and `not NULL` never fired (0116:425) — a stranger read a full
  --   fare breakdown. Same shape, so the same armour.
  if v_uid is not null and not coalesce(
       exists (select 1 from club_members m
                 join club_sessions cs on cs.id = p_session
                where m.club_id = cs.club_id and m.profile_id = v_uid)
    or _club_shell_access(p_session, v_uid) <> 'none'
  , false) then
    return;
  end if;

  return query
  -- ═══ §3a/§3b DOG ROWS ═══
  select
    (case when sd.custody = 'owner_handled' then 'owner_handled' else 'delegated' end)::text,
    sd.seq,
    d.name,
    d.photo_url,
    op.name,
    coalesce(sd.owner_profile_id = v_uid, false),
    -- ═══ §3d THE STATE LABEL ═══
    -- ⚠ `club_dog_ui_state` is NOT called, for two measured reasons (§3d): (a) it returns a
    --   jsonb blob carrying incident-adjacent severity/blocker fields and a secondaryBadges
    --   array (0116:610-620) that are OPERATIONAL, not public — pulling it in and then stripping
    --   fields is exactly the leak shape this file refuses; (b) `auth.uid()` survives a definer
    --   boundary (0116:549-551), so ITS party gate would fire inside ours and NULL out rows for
    --   a member whose shell grade is `none` — and our gate is deliberately WIDER than the shell
    --   grade, so the two gates would fight. The labels are derived here from columns directly.
    (case
       when sd.custody = 'owner_handled' then '보호자 동반'
       when sd.custody_phase = 'resolved' or sd.service_state = 'ended' then '귀가 완료'
       when sd.custody_phase = 'return_pending'   then '귀가 중'
       when sd.custody_phase = 'transfer_pending' then '이동 중'
       when sd.custody_phase = 'with_custodian'   then '러닝 중'
       when sd.custody_phase = 'outbound_pending' then '픽업 이동 중'
       when sd.assignment_state = 'accepted'      then '페어링 완료'
       when sd.assignment_state = 'proposed'      then '수락 대기'
       when sd.booking_id is not null             then '러너 선택 중'
       else '대기 중'
     end)::text,
    -- ═══ §4 R6 — state_since, and the honest limit of it ═══
    -- 🔴 THE CONTRACT SPECIFIES A COLUMN THE SCHEMA CAN ONLY PARTLY PRODUCE, and this is the
    --    honest resolution rather than a plausible one. `session_dogs` has NO `created_at` and
    --    NO `updated_at` (measured against the live catalog: 41 columns, neither present). The
    --    only recorded transition times for a pairing are `dog_custody_events.occurred_at`
    --    (0045:44 mints one at pickup, and the custody chain writes the rest).
    --    So: state_since is the latest custody event for this pairing, and **NULL for every
    --    state that precedes custody** (대기 중 · 러너 선택 중 · 수락 대기 · 페어링 완료).
    --    NULL is the truthful answer there — no column records when those began.
    --    ⚠ `bookings.updated_at` EXISTS and was REJECTED as a source: it is "the last write of
    --      any kind to this booking", not "when this state began". It would produce a number
    --      that looks like an answer and is not one — the exact shape the honesty laws forbid,
    --      and worse than NULL because a reader cannot tell it is wrong.
    --    ⚠ R6 also forbids returning the per-leg stamps individually: published to a
    --      neighbourhood they read 「this named person's home was empty from 08:12 to 09:40」.
    --      One aggregate MAX is not that; the four separate columns would be.
    (select max(e.occurred_at) from dog_custody_events e where e.session_dog_id = sd.id),
    -- ═══ §4 R3 — a pick-pending row carries NO runner identity to third parties ═══
    -- 0053:315-320's sub-gate, INVERTED for the new chooser: today host + proposed-runner see
    -- the candidate and the owner does not; the owner authored the pick and must. Everyone else
    -- sees 수락 대기 with no name until acceptance makes the pairing public.
    -- Sean's board shows pairs, not courtships.
    -- ⚠ Every arm is `exists`/equality under coalesce — the nullable `backup_host_profile_id` is
    --   precisely the 0116:425 fail-open shape (§10 T2), so it is never compared bare inside a NOT.
    (case when sd.assignment_state = 'accepted' then rp.name
          when sd.assignment_state = 'proposed' and coalesce(
                 sd.owner_profile_id = v_uid
              or sd.proposed_runner_profile_id = v_uid
              or exists (select 1 from club_sessions cs2 where cs2.id = sd.session_id
                          and (cs2.host_profile_id = v_uid or cs2.backup_host_profile_id = v_uid))
          , false) then pp.name
          else null end)::text,
    (case when sd.assignment_state = 'accepted' then rp.avatar_url
          when sd.assignment_state = 'proposed' and coalesce(
                 sd.owner_profile_id = v_uid
              or sd.proposed_runner_profile_id = v_uid
              or exists (select 1 from club_sessions cs2 where cs2.id = sd.session_id
                          and (cs2.host_profile_id = v_uid or cs2.backup_host_profile_id = v_uid))
          , false) then pp.avatar_url
          else null end)::text
  from session_dogs sd
  join dogs d on d.id = sd.dog_id
  left join profiles op on op.id = sd.owner_profile_id
  left join profiles rp on rp.id = sd.current_runner_profile_id
  left join profiles pp on pp.id = sd.proposed_runner_profile_id
  where sd.session_id = p_session
    and (
      -- §3a delegated liveness — 0053:331-332's clause MINUS its third arm.
      -- ⚠ REFUSAL: 0053:333's `or (owner = auth.uid() and approval in ('rejected','withdrawn'))`
      --   is the owner's private "honest last word" card. The operational board keeps it; the
      --   PUBLIC dashboard does not publish who was turned down — not even to the person turned
      --   down, because this projection has one payload for everyone and a self-arm here would
      --   make the board's contents depend on who is reading. P6 pins it.
      (sd.custody = 'runner_delegated'
        and (sd.service_state is distinct from 'ended' or sd.booking_id is not null)
        and coalesce(sd.approval, '') not in ('rejected', 'withdrawn'))
      -- §3b — 동반견. Today they appear on NO board (0053:330 filters to runner_delegated).
      -- Ruling #2 puts them here; F2 (「Stays free」) is why there is no money field to omit.
      or (sd.custody = 'owner_handled' and sd.service_state is distinct from 'ended')
    )

  union all

  -- ═══ §3c CREW ROWS — dogless RSVPs, GUESTS INCLUDED (ruling #6) ═══
  -- ⚠ ROLE-BLIND between the two RSVP roles, and this is where ruling #6 overrides the spec.
  --   `session_rsvp` assigns `runner_attending` ONLY to a runner with tier <> 'applicant'
  --   (0048:178-180); every other dogless RSVP gets `owner_attending`. The spec's
  --   「companions = role='runner_attending'」 would have listed only runners and dropped every
  --   guest — precisely what 「Guests can be crew too」 rules out (§11 CORRECTION 1).
  -- Excluded roles, each for a reason: `host_runner` is already named as hostName by
  -- `club_session_detail`; `handling_runner` is a committed runner surfaced through the pairing
  -- rows — and `session_runner_commit` PROMOTES a crew row to it (0043:238-240), so committing
  -- leaves the crew list by construction. P8 pins that transition rather than assuming it.
  select
    'crew'::text,
    null::bigint,
    null::text,
    null::text,
    cp.name,
    coalesce(sp.profile_id = v_uid, false),
    '함께 달려요'::text,
    null::timestamptz,
    null::text,
    null::text
  from session_people sp
  left join profiles cp on cp.id = sp.profile_id
  where sp.session_id = p_session
    and sp.attendance <> 'no_show'
    and sp.role in ('runner_attending', 'owner_attending')
    and not exists (select 1 from session_dogs sd2
                     where sd2.session_id = p_session
                       and sd2.owner_profile_id = sp.profile_id
                       and sd2.service_state is distinct from 'ended')
  order by 1 desc, 2 nulls last;
end $$;
-- Explicit ACL in the defining file — never grant preservation (0116:636).
-- ⚠ anon is NEVER granted. Ruling #9 accepted that the gate is one self-serve tap from public;
--   it did not order an anon grant, and a signed-in identity is what makes an audit trail exist.
--   Written as a refusal because 「effectively public」 is exactly the phrase that talks someone
--   into `grant … to anon` six weeks from now (§10 T7).
revoke execute on function club_session_board(uuid) from public, anon;
grant execute on function club_session_board(uuid) to authenticated;

comment on function club_session_board is
  '0136 (spec v2 S2, contract club-board-s2): the MEMBER-facing session board. One definer, one
gate, one payload — not grade-parameterised (ruling #9 settled the reader class), so unlike
club_delegation_board there is no wrapper/impl split. Returns where each dog is and who is at the
session, and NOTHING else: no address, no money of any kind, no phone/emergency contact, no
incident, no breed or health attribute, no ids beyond what render needs. A pick-pending runner is
anonymous to third parties (pairs are public, courtships are not). A missing session and an
inaccessible one both return ZERO ROWS, never an exception. state_since is the latest
dog_custody_events.occurred_at and is NULL before custody begins — session_dogs records no
transition time, and bookings.updated_at was rejected as a plausible-but-wrong stand-in.';

-- ⚠ NOT IN THIS MIGRATION, deliberately, and named so the contract is not read as half-done:
--   contract §5 (the operational board's `load` + `finishBlocker`, and re-creating
--   `_club_dogs_unresolved` over a new `_club_dog_finish_blocker` helper) is a `create or
--   replace` of `_club_delegation_board_impl`, which §13d records as a COLLISION with S2.5 —
--   the slice that rewrites the same function's approval counts. Whichever lands second must
--   rebuild from the newest body on origin (§10 T4: 0086 §B's measured failure, where a body
--   rebuilt from an older definition silently reverted a newer slice while the harness stayed
--   green). S2.5 is unlanded and unclaimed by me; taking that function now would create exactly
--   the race the contract tells us to avoid. §5 rides whichever slice owns the impl next, and
--   `_club_dogs_unresolved` gates session closure (0045:343), so it is not a drive-by.
